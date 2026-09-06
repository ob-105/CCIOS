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
  `"Terminated"`) is caught, the window is closed, the error is stashed
  on `entry.crashMessage`, and a toast is queued via `wm:notify` (see
  below) so it's no longer just a window silently vanishing.
- The WM's `run()` loop exits once no windows remain and no
  notification is still queued (see below - otherwise a crash in the
  last open window would exit CCIOS before its toast was ever shown).

## Crash notifications

`wm:notify(title, message)` pushes onto `self.notifications`, a queue
drawn one at a time as a small red toast in the top-right corner
(`wm:drawNotification`) — on top of everything, including the Start
menu, since it's drawn last in `wm:draw()`. It's dismissed by clicking
it (checked first, before anything else, in `handleMouseClick`) or
automatically after 10 seconds (checked on the same per-second timer
tick that drives the taskbar clock — see "Taskbar clock" below). The
only thing that currently queues one is `wm:resumeWindow` when an app
crashes; nothing app-facing calls `wm:notify` yet, though there's no
reason another WM-level event couldn't use it later.

This is deliberately WM-level chrome, not a per-window dialog: unlike
`dialog.lua` (which an *app* draws into its own window, correctly,
because it's running on that app's own coroutine with `term` redirected
to it), a notification has no owning window to draw into by the time
the app that crashed is gone - it has to be something the WM itself
draws directly via `self.nativeTerm`, the same way all of its own
chrome (title bars, taskbar, Start menu) already does.

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

## System scrollbars

Some apps have more to show than fits in a comfortably-sized window
(the System Monitor being the concrete case that prompted this). The
fix isn't "make apps implement their own scrolling" — that's what File
Explorer and the Text Editor already do, because they specifically need
to scroll one thing (a list, a text buffer) while keeping other UI
(header, buttons) fixed. This is a different, simpler case: a whole
screenful of static-ish output that just doesn't fit, from an app that
never had to think about scrolling at all. For that, the WM can give a
window a drawing surface bigger than what's visible and handle showing
a scrolled slice of it automatically — the app keeps using
`term.getSize()`/`term.write()` exactly as if it had a bigger window,
and never finds out it's being scrolled.

**Why this needs two windows per app, not one.** CC:Tweaked's `window`
object has no concept of "this buffer is bigger than what's on screen,
show me a scrolled portion of it" — a window's `redraw()` always blits
its *entire* declared area. So a window bigger than the visible space
can never safely become `visible`; it would overflow across the rest of
the desktop the moment it's drawn. Instead, a scrollable window entry
gets:

- `entry.win` — the big, requested-size buffer, permanently invisible.
  This is what apps draw into (`term.redirect(entry.win)` before every
  resume, exactly as with any other window) and what `term.getSize()`
  reports the size of.
- `entry.viewWin` — a small buffer sized to what's actually visible.
  This is the one that ever gets `setVisible(true)`/`redraw()`'d to the
  real screen.

Every frame, `wm:compositeScrollable(entry)` copies the currently-
scrolled-to slice of `entry.win` into `entry.viewWin`, one row at a
time, using `window.getLine(y)` (returns a row's text plus its
per-character foreground/background color codes — the same shape
`term.blit` takes) and `viewWin.blit(...)`. This is the one part of the
feature that depends on a CC:Tweaked capability CCIOS doesn't otherwise
use: if `getLine` isn't present (older CC:Tweaked versions), `wm:launch`
detects that at creation time and just falls back to an ordinary
single, correctly-sized window — the app quietly doesn't get the extra
room, rather than anything crashing. Worth confirming in-game since
this is the one piece of the feature resting on an assumption about the
CC:Tweaked API surface rather than something already exercised
elsewhere in CCIOS.

**How an app asks for this.** There's no runtime call for it (unlike
`customClose`) because of a timing problem: an app can only make
requests *after* being resumed for the first time, but by then `wm:launch`
has already had to decide what kind of window to create and let the app
start drawing into it. So instead it's declared up front, in the
manifest, alongside `width`/`height`:

```json
"window": { "width": 42, "height": 16, "virtualHeight": 20 }
```

(`virtualWidth` works the same way, for horizontal scrolling.)
`apps.lua` reads these into the app descriptor, `boot.lua`'s `launchApp`
passes them to `wm:launch` as two extra positional parameters ahead of
the app's own launch args, and `wm:launch` only builds the two-window
setup when a virtual size bigger than the visible size was actually
requested — every app that doesn't ask for this (which is most of them)
gets the exact same single-window path as before, at no extra cost.
This is why it isn't automatic for every app: nothing else needed
changing to add it (System Monitor's manifest is the only app file
touched), but it does mean a new app with more content than fits has to
add one line to its manifest to get scrolling, rather than it happening
for free.

**Scrollbars and input.** `wm:updateViewport(entry)` derives
`needsVScroll`/`needsHScroll` by comparing the fixed virtual size
against the *current* outer window size — so maximizing a window whose
virtual size now fits inside the visible area makes its scrollbar(s)
disappear on their own, and shrinking it back down brings them back.
Whichever scrollbars are needed eat into the visible viewport (a column
for vertical, a row for horizontal) the same way a real OS's do. A
vertical scrollbar's track can end up sharing its bottom cell with the
resize handle when there's no horizontal scrollbar; the resize handle
wins there both visually (chrome is drawn after scrollbars) and for
hit-testing (checked first in `handleMouseClick`). Interaction is the usual
three ways: mouse wheel (intercepted by the WM for scrollable windows,
not forwarded to the app), dragging the thumb, or clicking empty track
to jump straight there — tracked in `self.vScrollDrag`/`self.hScrollDrag`,
the same pattern as `chromeDrag`/`resizeDrag`.

## Maximize/restore

A second title-bar button (`o`, just left of the close `x`) calls
`wm:toggleMaximize(entry)`, which stashes the window's current
`x/y/w/h` in `entry.restoreX/Y/W/H`, resizes it to fill the screen down
to the taskbar, and flips `entry.maximized`; clicking it again restores
the stashed bounds. It reuses the exact same `win.reposition` +
`term_resize` notification the resize handle uses — maximizing is really
just "resize to the full screen" from the app's point of view.

Manually dragging the title bar or the resize handle clears
`entry.maximized` first, so a window doesn't stay "logically maximized"
after being moved/resized by hand — otherwise clicking the maximize
button afterward would restore to the stale pre-maximize size instead of
un-maximizing the size you actually meant to keep. There's deliberately
no drag-to-edge-to-snap gesture: an accidental snap-to-maximize while
dragging near the top of the screen was called out as a specific thing
to avoid, and a real "is this an intentional snap or did the mouse just
pass through that pixel" gesture needs more care (a preview outline, a
release-to-commit threshold) than this pass covers — the button is an
unambiguous, deliberate action instead.

## Taskbar clock

`wm:run()` starts its own `os.startTimer(1)`, re-armed every time it
fires, purely so the WM's loop wakes up and redraws roughly once a
second even when nothing else is happening — otherwise the clock
(`os.date("%H:%M")`, real time, drawn last in `drawTaskbar` so it always
sits on top of anything that would otherwise run into its space) would
only update whenever some other event happened to occur. This timer
event flows through `dispatch()` like any other (broadcast to every
window) rather than being special-cased out — harmless, since no app's
own timer id will ever match it.

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

Treat `wm` as read-only/informational from app code, with one deliberate
exception (below) — poking anything else in `_G.ccios.wm`'s internals
from an app would be reaching past the intended surface. `launch`, on
the other hand, is meant to be called: it's `boot.lua`'s own
cascaded/screen-clamped placement logic (the same thing the Start menu
uses), exposed so any app can open another program the same way instead
of reimplementing window placement itself. The File Explorer uses it to
open `.lua` files.

This will likely grow into something more structured once an app needs
more than this (e.g. the app store wanting the Start menu to refresh
after installing something).

### Opting into custom close handling

By default, clicking a window's title-bar `[x]` closes it immediately —
no app code runs at all, which is exactly what most apps want and why
it's the default. An app that needs a chance to object (the Text
Editor, to confirm unsaved changes; the Save As picker, to report back
"cancelled" instead of just vanishing) can opt out of that default
during its own startup, before its first `os.pullEvent()`:

```lua
if _G.ccios and _G.ccios.wm and _G.ccios.wm.currentWindow then
    _G.ccios.wm.currentWindow.customClose = true
end
```

`wm.currentWindow` is the one exception to "`_G.ccios.wm` is read-only"
— it's set to an app's own window entry right before every resume of
that app's coroutine (see `wm:resumeWindow`), so at the very top of a
script, before any yield, it reliably points at "myself". Once
`customClose` is set, clicking `[x]` delivers a `ccios_close_request`
event to that window instead of closing it — bypassing filter matching
entirely, the same way `terminate` does, so the app is guaranteed to see
it regardless of what it was actually waiting for. The app then decides:
call `dialog.confirm` if it wants to, and either end its own coroutine
(closing itself, same "return and the WM reaps you" mechanism as
always) or just do nothing and stay open. If the app's handling of that
event errors, `resumeWindow`'s usual crash handling marks it dead anyway
— a broken close handler can't make a window unclosable.

The Text Editor always opts in (`confirmClose()` decides per-close
whether that actually means showing a dialog). The Save As picker only
opts in while `pickerMode == "save"`, and its handler is just a call to
the same `cancelSave()` its own Cancel button uses — so closing via
`[x]` now correctly reports "cancelled" back to the waiting Editor
instead of leaving it stuck (see "Save As picker mode" below, and the
deferred item about this from step 8 - now resolved).

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
  mode — see below) and **right-click** both open the same dropdown,
  via a shared `openMenu(items, anchorX, anchorY, alignRight)` /
  `buildMenuItems(targetIndex)` pair — `targetIndex` is the
  currently-selected entry for the Menu button, or whatever's under the
  cursor for a right-click (`nil` if you right-click empty list space,
  which just gets you `Paste`/`New File`/`New Folder` — nothing
  entry-specific). A directory gets `Open`; a `.lua` file gets `Run` and
  `Edit`; anything else gets just `Edit`; everything gets
  `Copy`/`Cut`/`Delete`; `Paste` only appears once something's on the
  clipboard; `New File`/`New Folder` are always there (they prompt for a
  name via a blocking `read()`, same technique as the Save As prompt
  below, and act on `currentPath`, not the selected entry). Right-click
  is just CC's ordinary `mouse_click` event with `button == 2` — nothing
  special had to be added to `wm.lua` for it, since that button value
  was already being forwarded to every window's content clicks from the
  start; Explorer just hadn't been reading it. `openMenu` positions the
  dropdown at its anchor point (right-aligned below the Menu button, or
  top-left at the click point for a right-click), flipping/clamping to
  stay on screen either way. This whole pattern (button toggles a
  positioned list, click-away dismisses) is the same one the WM's own
  Start menu uses — there wasn't a reason to generalize it into `wm.lua`
  itself since only Explorer needs it so far.
- Middle-click (`button == 3`) isn't given any meaning.
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

The picker also sets `customClose = true` (see "Opting into custom close
handling" above) so that closing it via the title-bar `[x]` runs the
exact same `cancelSave()` its `Cancel` button does, rather than just
vanishing and leaving the Editor waiting forever — that was a real gap
in the first version of this feature, closed once `customClose` existed
to close it with.

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
- **Closing itself**: both the in-app `Close` button and the title-bar
  `[x]` (via `customClose` + `ccios_close_request`, see "Opting into
  custom close handling" above) call the same `confirmClose()`, which
  shows a `dialog.confirm` only if there are unsaved changes. Either
  path, once allowed to proceed, just lets the `while not closing do
  ... end` loop end and the file's top-level chunk return — same
  "returning ends the coroutine, WM notices it's dead and reaps the
  window" mechanism noted in Window lifecycle above, no special "close
  myself" API needed.

## Settings

`src/ccios/apps/settings/main.lua` is intentionally thin: it's a UI on
top of the standard CC `settings` API for the one setting CCIOS
currently defines (`ccios.autoUpdateCheck`, also defined identically in
`boot.lua` - `settings.define` is idempotent, so both call sites
defining it is harmless and means Settings works even if `boot.lua`
somehow hasn't run first) plus a "check now" button that calls
`updater.checkForUpdate()`/`updater.applyManifest()` directly - the same
functions `boot.lua`'s boot-time check and `/update.lua`'s shell command
already use, so there's exactly one place that logic lives. There's
only one real toggle right now; the app exists as the place future
settings land, not because one checkbox needed its own app.

## Task Manager

`src/ccios/apps/taskmgr/main.lua` lists `_G.ccios.wm.windows` (topmost
first) and force-closes one via `wmInfo:closeWindow(entry)` directly -
apps already have raw access to the manager object through `_G.ccios.wm`,
so no new surface was needed for this. This deliberately **bypasses**
`customClose`: End Task is the blunt instrument for a window that won't
close normally (the Text Editor ignoring its own confirm, say), so
asking it nicely again via `ccios_close_request` would defeat the point.
This mirrors Windows' own Task Manager, which also skips graceful
shutdown on End Task. Nothing stops Task Manager from ending its own
window this way; that's harmless (see `wm:closeWindow` - it just leaves
that coroutine parked at its next `os.pullEvent()` forever, eventually
garbage collected, same as any other closed window's coroutine).

## App Store

`src/ccios/apps/appstore/main.lua` fetches `store/catalog.json` from
the CCIOS GitHub repo — a plain JSON array of `{id, name, description,
version, author, path, banner}` — and renders it as a grid of tiles,
each showing a 3x3 "pixel" banner (see below) and the app's name.
Clicking a tile opens a detail screen (description, author, latest
version from the catalog vs. installed version read from
`/ccios/apps/<id>/manifest.json` if it exists) with Install/Update/
Delete buttons chosen based on that comparison — no button at all if
already installed and current except Delete, both Update and Delete if
installed but a different version, just Install if not installed at
all. Version comparison is plain string inequality, not real semver
ordering: good enough for a single-maintainer catalog where "different"
already means "worth reinstalling," not worth the edge cases a real
version-ordering comparison would need to get right.

**Installing** fetches `<path>/manifest.json` and `<path>/main.lua` from
the repo and writes them to a new `/ccios/apps/<id>/` folder — exactly
the shape `apps.lua` already scans for the Start menu, so nothing about
app discovery needed to change for this feature at all. The one thing
App Store does that a plain file copy wouldn't is call `apps.lua`'s
`discover()` again immediately afterward and overwrite
`_G.ccios.wm.startMenuApps` with the result, so a freshly installed app
shows up in the Start menu right away instead of requiring a reboot.
**Deleting** is a confirm (via `dialog.lua`, consistent with every other
destructive action in CCIOS) followed by `fs.delete` and the same
Start-menu refresh.

**Banners** are a 3x3 array of CC color names (`"blue"`, `"white"`,
etc.), each cell drawn as a 1x2-character block (two characters wide so
it reads as roughly square in a monospace terminal, rather than the
tall/narrow rectangle a single character would give a 3-row-tall icon).
On a mono screen, "light" color names (white, yellow, lime, cyan,
lightBlue, lightGray, pink, orange) collapse to white and everything
else to black — a crude but workable approximation for reducing an
arbitrary 16-color banner to 1 bit. This is the "simplified logo" an
app author draws by hand in the catalog JSON, not an uploaded image —
there's no image format CC:Tweaked terminals could show anyway.

**Why store apps live in this same repo, not a separate one per app.**
The `path` field in each catalog entry is a folder under `store/apps/`
in the CCIOS repo itself (`store/apps/calculator`, for the one app that
ships today), fetched via the same `raw.githubusercontent.com` pattern
`updater.lua` already uses for core files. This is a deliberate v1
scope cut, not the end state: a catalog entry doesn't currently carry
its own repo owner/name, so every app in the store has to be something
that got merged into this repo. Making that a per-entry field instead
of an assumption is the natural next step once a second author wants to
publish something without needing commit access here — see the
deferred list below.

**Security note, since this is the first feature where CCIOS downloads
and runs code a user didn't write themselves**: installing an app
executes whatever `main.lua` the catalog points at, with the same trust
as any other CCIOS app (no sandboxing beyond what CC:Tweaked itself
provides for any program). That's an acceptable risk today because the
only publisher is this repo's own maintainer, but it's worth naming
explicitly now rather than discovering it as a surprise later: a
multi-author catalog would need real thought about trust before it's
safe to point people at.

**Why only single-file (`main.lua`) apps.** Installing hardcodes
fetching exactly `manifest.json` and `main.lua` — matching every app
CCIOS ships so far, including the store apps. An app needing more files
(assets, a second module it `dofile`s) isn't supported by the installer
yet; it would need the catalog entry or the app's own manifest to list
its files explicitly, the same problem `install.lua`/`manifest.json`
already solved for core files - reusing that shape here is the obvious
next step if it's ever needed.

## What's intentionally deferred

- Forwarding the *real* `term_resize` (the physical screen resizing) to
  individual apps — only resize-handle-triggered resizes are forwarded
  right now
- Pinning/searching in the Start menu, submenus, categories
- Preventing duplicate launches (every click on a Start menu entry opens
  a new instance, same as clicking a taskbar icon in Windows without
  "single instance" apps)
- File Explorer: rename, multi-select, creating a new folder from within
  Save As picker mode (Menu is hidden there entirely right now)
- Text Editor: syntax highlighting, find/replace, undo
- System scrollbars: changing `virtualWidth`/`virtualHeight` at runtime
  (it's launch-time-only, read from the manifest); resizable content
  within the scrollable viewport reflecting a *different* virtual size
  on resize (right now the virtual size is fixed for the window's whole
  lifetime — only the *viewport* into it changes as the window is
  resized/maximized); scrollbar keyboard shortcuts (Page Up/Down, arrow
  keys) — currently mouse-only (wheel, thumb drag, track click)
- Notifications: only one queued type exists (crashes); no way for an
  app to push its own; no notification history/center to revisit a
  dismissed or auto-expired one
- Settings: only one real setting exists; no search, categories, or
  per-app settings pages
- Task Manager: no per-window resource stats (only the WM-wide
  watchdog headroom in System Monitor exists, not a per-window
  breakdown), no multi-select/end-multiple-at-once
- App Store: multi-author/multi-repo catalog entries (see above),
  multi-file app installs (see above), no search/categories/screenshots,
  no rating/review system, no way to browse without a working `http`
  API and a live GitHub connection (no offline catalog cache), no undo
  after Delete beyond reinstalling, real semver-aware version comparison
  instead of plain string inequality
- App developer documentation: how to write an app, the manifest
  schema, and how to actually get a new one added to `store/catalog.json`
  (right now that's "make a PR/ask the maintainer," not a self-serve
  submission process)
