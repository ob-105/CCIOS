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
- **The Menu button** (top-right of the window, hidden in Save As picker
  mode — see below) opens a dropdown built fresh each time from the
  currently-selected entry: a directory gets `Open`; a `.lua` file gets
  `Run` and `Edit`; anything else gets just `Edit`; everything gets
  `Copy`/`Cut`/`Delete`; `Paste` only appears once something's on the
  clipboard; `New File`/`New Folder` are always there regardless of
  selection (they prompt for a name via a blocking `read()`, same
  technique as the Save As prompt below, and act on `currentPath`, not
  the selected entry). It's implemented the same way as the WM's own
  Start menu (a button that toggles a positioned list, click-away to
  dismiss) — there wasn't a reason to generalize that pattern into
  `wm.lua` since only Explorer needs it so far.
- **Clipboard**: `Copy`/`Cut` just remember `{path, name, isDir, mode}`
  locally (no confirmation needed — nothing on disk changes yet). `Cut`
  *does* confirm despite being non-destructive at that point, because
  that's what was asked for; the actual move only happens at `Paste`,
  via `fs.move`/`fs.copy` (both already handle directories recursively,
  so Explorer doesn't reimplement that). `Paste` additionally confirms
  if it would overwrite an existing file.
- **`Edit`** opens any file — `.lua` or not — in the Text Editor app,
  passing the path as a launch argument through `_G.ccios.launch`'s
  `args` field (see below). This is how "open non-Lua files" is
  implemented: not a viewer built into Explorer, just handing the file
  to another app that already knows how to show text.
- Rename is explicitly **not** implemented yet.

## Save As picker mode (cross-app communication without an IPC system)

The Text Editor doesn't have its own "browse for a folder" UI. Instead,
saving a buffer with no path yet launches File Explorer itself with
extra arguments — `local pickerMode, pickerRequestId, pickerSuggestedName
= ...` at the top of `explorer/main.lua` — which switches its header to
`Save`/`Cancel` buttons (hiding the Menu button), makes clicking a file
select it instead of running/editing it, and makes double-click/Enter on
a file mean "use this name" instead of "open it". Clicking `Save`
prompts for a filename (pre-filled, editable, same `read(nil, nil, nil,
default)` trick used elsewhere) and, once confirmed (with an
overwrite-confirm if the name collides with something), needs to report
the chosen path back to whichever Editor window asked for it.

That report can't be a plain function call. Explorer and the Editor
that launched it are two *independent* coroutines the WM resumes on its
own schedule, each with `term` redirected to its own window right
before resuming it (see "Core idea" above) — if Explorer's coroutine
directly called a closure that belongs to the Editor's coroutine (e.g.
one that calls the Editor's own `draw()`), that code would run while
`term` is still redirected to *Explorer's* window, corrupting Explorer's
display and leaving the Editor's window showing stale content. So
instead Explorer does:

```lua
os.queueEvent("ccios_save_dialog_result", pickerRequestId, fullPath)
```

`os.queueEvent` puts a normal event on CraftOS's real event queue, which
`wm.lua` picks up like any other event and — since it's not in the
focused-only set — broadcasts to every window, including the Editor
that's sitting at `os.pullEvent()` waiting for it. The Editor checks
`p1 == pickerRequestId` (a fresh `tostring({})` per request, so multiple
Editor windows each mid-save-as don't cross-match each other's results)
and, if it matches, updates its own state and writes the file — all on
its own coroutine, with `term` correctly redirected to its own window by
the time the WM resumes it. This is the same "just send an event"
pattern every other app already uses; it just happens to be one app
sending it to another instead of the WM sending it to an app.

If the picker window is closed via the title-bar `x` instead of
`Cancel`, no result event is ever queued (there's no way for the WM's
own close handling to run app code — see the deferred "OK to close?"
item above) and the waiting Editor just... keeps waiting, silently,
until the user tries Save again. Not a crash, just a dead end — the
`Cancel` button and Escape key both exist specifically so there's an
explicit way out that does report back.

## Confirmation dialogs (`dialog.lua`)

`src/ccios/kernel/dialog.lua` is a small shared helper (`dofile`'d by
an app, not part of the `_G.ccios` surface) with one function,
`dialog.confirm(message)`, that draws a centered Yes/No box and blocks
until answered (click, or Y/Enter/N/Escape). It can block like that
because the calling app is itself just a coroutine the WM feeds events
to (see "Core idea" above) — nesting another `os.pullEvent` loop inside
a click handler is exactly as safe as CraftOS's own `read()` blocking
the same way mid-program. The caller just needs to redraw its own UI
afterwards, which File Explorer and the Text Editor already do every
loop iteration regardless.

This is currently used by File Explorer (Cut/Delete/overwrite-on-Paste)
and the Text Editor (closing with unsaved changes). It's deliberately
just a Yes/No box, not a general dialog/toast/notification system —
extend it if a third real need shows up, not before.

## Text Editor

`src/ccios/apps/editor/main.lua` is a plain line-buffer editor (an
array of strings, a `{row, col}` cursor, independent vertical/horizontal
scroll) — nothing fancier like a rope or piece table, since CCIOS files
are small enough that array operations on `table.insert`/`table.remove`
are plenty fast. A few things worth knowing:

- **Ctrl+S** is tracked manually: CraftOS reports Ctrl and S as
  separate `key` events, so the app tracks whether `keys.leftCtrl` /
  `keys.rightCtrl` is currently held (via `key`/`key_up`) and checks
  that flag when it sees `keys.s`. This is the same pattern CraftOS's
  own built-in `edit` program uses.
- **Launched two ways**: from the Start menu with no arguments (blank,
  untitled buffer — `Save` opens the Save As picker described above), or
  from Explorer's `Edit` action with a file path as the first launch
  argument (`local path = ...`).
- **Closing itself**: the in-app `Close` button confirms first if there
  are unsaved changes (via `dialog.confirm`), then just lets its own
  `while not closing do ... end` loop end and the file's top-level chunk
  return — same "returning ends the coroutine, WM notices it's dead and
  reaps the window" mechanism noted in Window lifecycle above, no
  special "close myself" API needed. Note this is *different* from
  clicking the window's title-bar `x`, which the WM handles directly and
  unconditionally — closing that way skips the unsaved-changes check
  entirely, since the WM has no way to ask an app "is it OK to close
  you?" yet (see the deferred list below).

## What's intentionally deferred

- Surfacing app crash messages in the UI
- Forwarding the *real* `term_resize` (the physical screen resizing) to
  individual apps — only resize-handle-triggered resizes are forwarded
  right now
- Pinning/searching in the Start menu, submenus, categories
- Preventing duplicate launches (every click on a Start menu entry opens
  a new instance, same as clicking a taskbar icon in Windows without
  "single instance" apps)
- Letting the WM ask an app "OK to close?" before the title-bar `x`
  closes it — right now that always closes unconditionally, bypassing
  e.g. the Text Editor's unsaved-changes confirm (its own in-app Close
  button is the only closing path that checks)
- File Explorer: rename, multi-select, creating a new folder from within
  Save As picker mode (Menu is hidden there entirely right now)
- Text Editor: syntax highlighting, find/replace, undo
