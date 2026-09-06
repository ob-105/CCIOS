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

## What's intentionally deferred

- Resizable windows (only draggable for now)
- Surfacing app crash messages in the UI
- Forwarding `term_resize` to individual apps
- Pinning/searching in the Start menu, submenus, categories
- Preventing duplicate launches (every click on a Start menu entry opens
  a new instance, same as clicking a taskbar icon in Windows without
  "single instance" apps)
