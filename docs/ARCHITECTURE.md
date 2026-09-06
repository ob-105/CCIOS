# Architecture — Step 1: Window Manager

## Core idea

Apps are **ordinary CraftOS programs**. They read input with the normal
`os.pullEvent()` and draw with the normal `term.*` API. Nothing app-side
needs to know it's running inside CCIOS. This keeps app development
simple (important once there's an app store and docs for third parties)
and mirrors how CraftOS's own `multishell` works internally.

The window manager (`src/ccios/kernel/wm.lua`) makes this possible with
two tricks:

1. **Output** — each window owns a CC:Tweaked `window.create(...)`
   buffer. Right before resuming an app's coroutine, the WM calls
   `term.redirect(win)`, so every `term.write`/`print`/etc. the app does
   lands in its own buffer instead of the real screen. The WM composites
   all window buffers (plus title bars and the taskbar) onto the real
   terminal itself.

2. **Input** — each app is run as a Lua **coroutine**. When the app calls
   `os.pullEvent(filter)`, that call yields back up to the WM with the
   requested filter. The WM's own event loop pulls real system events via
   `os.pullEventRaw()`, decides which window(s) should see each one, and
   resumes the matching coroutine(s) with the event — after translating
   screen-space mouse coordinates into window-local coordinates.

This means a single cooperative loop drives the WM and every app, exactly
like CraftOS itself drives the shell — there's no real threading (CC
doesn't have any), just coroutines taking turns.

## Event routing rules

| Event(s) | Delivered to |
|---|---|
| `mouse_click` | topmost window under the cursor (also brings it to front); clicks on a title bar/close button/taskbar are handled by the WM itself and never reach the app |
| `mouse_drag`, `mouse_up` | whichever window most recently got a `mouse_click` in its content area |
| `mouse_scroll` | topmost window under the cursor |
| `key`, `key_up`, `char`, `paste` | the **focused** (topmost) window only |
| `terminate` (Ctrl+T) | the focused window, unconditionally — mirrors real CraftOS, where terminate always interrupts `os.pullEvent` regardless of what filter it was called with |
| `file_transfer` (dragging a file onto the Minecraft window) | the focused window only — this is what lets the File Explorer decide the dropped file goes into whatever folder it currently has open, without every open window trying to claim it |
| everything else (timers, redstone, disk, http, ...) | broadcast to every open window, so background work (e.g. a timer an app started) keeps working even while another window is focused |

Windows track the `filter` their coroutine last yielded (from
`os.pullEvent(filter)`) and events that don't match are simply not
delivered that round — same semantics as real `os.pullEvent`.

## Color handling

Standard (non-Advanced) computers, turtles, and pocket computers only
support `colors.white` / `colors.black`. The WM checks
`term.isColor()` once at startup and picks mono-safe fallbacks for all
chrome (title bars, taskbar, close button) so the same code works
unmodified on both device tiers.

## Window lifecycle

- `wm:launch(path, title, x, y, w, h, ...)` loads an app file and starts
  it as a coroutine inside a new window.
- Closing (clicking the title bar's `x`) removes the window immediately.
- A crashed app (an error propagating out of `os.pullEvent`, other than
  `"Terminated"`) is caught, the window is closed, and the error is
  stashed on `entry.crashMessage` (not yet surfaced in the UI — the app
  launcher error dialog is a step-2 concern).
- The WM's `run()` loop exits once no windows remain.

## App discovery and the Start menu

`src/ccios/kernel/apps.lua` scans `/ccios/apps/*/manifest.json` at boot
and returns a list of `{id, name, entry, width, height}` — this is the
same manifest format each app already ships (see
`src/ccios/apps/about/manifest.json`). `boot.lua` hands that list to
`manager.startMenuApps` and sets `manager.onLaunchApp = function(m, app)
... end` to actually launch one.

This keeps `wm.lua` itself app-agnostic: it doesn't know what a "app" is
beyond `{id, name, entry, width, height}`, doesn't hardcode paths, and
just calls back into `onLaunchApp` when the user picks something from
the menu. Clicking the Start button toggles the menu; clicking an entry
launches it and closes the menu; clicking anywhere else while it's open
closes the menu and then still acts on whatever's underneath (a window,
a taskbar entry) — same click-away behavior as a normal desktop.

This is also the seam the future app store will hang off of: installing
an app from the store just means writing a new `/ccios/apps/<id>/`
folder with a `manifest.json`, and it shows up in the Start menu on the
next boot with no other code changes.

## Resizing

Every window's bottom-right cell is a resize handle (drawn as `\`,
painted on top of the window's content each frame so the app can't
cover it up). Dragging it works exactly like dragging the title bar —
same `mouse_click` → `mouse_drag`* → `mouse_up` lifecycle, tracked in
`self.resizeDrag` instead of `self.chromeDrag` — except it changes
`entry.w`/`entry.h` and calls `entry.win.reposition(x, y, w, h)` instead
of just moving `x`/`y`. Size is clamped to a minimum
(`MIN_WINDOW_W`/`MIN_WINDOW_H`) and to stay above the taskbar and within
the screen, the same way dragging is clamped to stay on-screen.

Each time the size actually changes, the WM resumes that window's
coroutine with a `term_resize` event (subject to the same filter-match
rule as any other event) so the app can redraw at its new size. This
doesn't rely on CraftOS's own `term_resize` event at all — the WM
already drives each app's coroutine directly, so it just delivers the
event itself the moment it changes the window's buffer size.

## The `_G.ccios` surface

There isn't a formal kernel API yet, but apps that need to know
something about the running system (the System Monitor being the first)
read it from a small global table `boot.lua` sets up:

```lua
_G.ccios = {
    wm = manager,       -- the live wm instance (see wm.lua)
    root = "/ccios",
    launch = function(app) ... end, -- launch an arbitrary {id,name,entry,width,height}
}
```

Treat `wm` as read-only/informational from app code — nothing enforces
that, but poking `_G.ccios.wm`'s internals from an app would be reaching
past the intended surface. `launch`, on the other hand, is meant to be
called: it's `boot.lua`'s own cascaded/screen-clamped placement logic
(the same thing the Start menu uses), exposed so any app can open
another program the same way instead of reimplementing window placement
itself. The File Explorer uses it to open `.lua` files.

This will likely grow into something more structured once an app needs
more than this (e.g. closing another window, or the app store wanting
the Start menu to refresh after installing something).

## Watchdog headroom (the System Monitor's "instruction limit" gauge)

CraftOS doesn't expose a real instruction counter or "time remaining
this burst" value to Lua scripts — the actual mechanism is a wall-clock
watchdog: if a program runs for too long between yields (`os.pullEvent`
calls), CraftOS kills it with a "Too long without yielding" error. Since
every app in CCIOS runs *inside* the WM's own dispatch/draw cycle
between its calls to `os.pullEventRaw()`, that cycle's duration is the
real thing standing between "normal" and "the whole computer gets
killed" — not any individual app's own event loop.

`wm:run()` times each dispatch+draw cycle with `os.clock()` and tracks
it in `self.stats = { lastBurst, maxBurst }` (seconds). The System
Monitor reads `_G.ccios.wm.stats` and shows `maxBurst` as a fraction of
CraftOS's commonly-cited ~7 second default budget. This is a proxy, not
a measurement of the actual configured limit (which isn't queryable) —
`os.clock()`'s resolution is tied to the server tick rate (~50ms), so
fast cycles frequently read as 0. It's most useful for catching an app
that's doing real work (a tight loop, a big computation) without
yielding, which is also the one thing that can freeze or crash *all* of
CCIOS at once, since it's all one Lua state — there's no per-window
isolation the way real threads would give you.

## File Explorer

`src/ccios/apps/explorer/main.lua` is, deliberately, nothing more than
`fs.list`/`fs.isDir` plus the same coroutine/window pattern every other
app uses — there's no filesystem API of CCIOS's own. A few notable
choices:

- **Double-click** isn't a CraftOS concept; CC only fires one
  `mouse_click` per click. The app tracks `{index, time}` of the last
  click and treats a second click on the same entry within 0.5s (using
  `os.clock()`) as a double-click. Single-click just selects.
- **Opening a `.lua` file** calls `_G.ccios.launch({id, name, entry,
  width, height})` — the exact same shape `apps.lua` produces from a
  manifest, just built ad hoc from the clicked file instead of read from
  JSON. This is why `wm.lua` never needed to know the difference between
  "a real app" and "a file someone opened": both are just `{entry =
  <path to a .lua file>, ...}` to `wm:launch`.
- **Drag-and-drop** uses CraftOS's `file_transfer` event, which fires
  when a file is dropped onto the Minecraft window while a computer's
  GUI is open. `transfer.getFiles()` returns `TransferredFile` objects
  (`getName()` + the same read/close methods as an `fs.open` handle);
  the app reads each one and writes it into `currentPath`. Because
  `file_transfer` is focused-only (see the event routing table), a drop
  always lands in whichever folder the *focused* Explorer window has
  open — if Explorer isn't the focused window, it doesn't receive the
  event at all.
- Non-`.lua` files and delete/rename/copy/move are explicitly **not**
  handled yet (see below) — clicking one just shows a status message.

## What's intentionally deferred

- Surfacing app crash messages in the UI
- Forwarding the *real* `term_resize` (the physical screen resizing) to
  individual apps — only resize-handle-triggered resizes are forwarded
  right now
- Pinning/searching in the Start menu, submenus, categories
- Preventing duplicate launches (every click on a Start menu entry opens
  a new instance, same as clicking a taskbar icon in Windows without
  "single instance" apps)
- File Explorer: opening non-`.lua` files (needs a text editor/viewer
  app first), delete/rename/copy/move (needs a confirmation dialog
  primitive first — not building one just to wire up a destructive
  action with no "are you sure")
