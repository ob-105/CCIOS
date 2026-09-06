# Dev log

## Step 10 — Right-click menus, taskbar clock, maximize (2026-09-06)

Confirmed working in-game: steps 1-9.

"Make it feel more like Windows" grab-bag, minus drag-to-edge snapping
(explicitly asked to skip unless an accidental-trigger-proof version
could be guaranteed - a real snap gesture needs a preview outline and a
release-to-commit threshold to avoid exactly that, which is more than
this pass covers, so it's skipped rather than shipped half-safe).

Built:

- File Explorer: right-click (`button == 2` on `mouse_click`, which
  turns out CC has supported this whole time - it was already being
  forwarded by `wm.lua`, just never read) opens the same context menu
  the Menu button does, positioned at the cursor instead of anchored to
  the button. Right-clicking empty list space offers Paste/New File/New
  Folder without file-specific actions.
- Taskbar clock (`os.date("%H:%M")`, real time), bottom-right. Needed
  `wm:run()` to grow its own re-arming `os.startTimer(1)` so the WM
  redraws roughly once a second even with no other activity - previously
  it only ever redrew in response to some event happening.
- Maximize/restore button (`o`) on every title bar, next to close.
  Fills to the screen size (down to the taskbar) and back, reusing the
  same `term_resize`-notification mechanism the resize handle already
  used. Manually dragging or resizing a maximized window un-maximizes it
  first, so the maximize button doesn't restore to a stale size
  afterward.

### Things to specifically check when testing

- [ ] Right-clicking a file/folder in Explorer opens a context menu at
      the cursor (not jumping to the top-right like the Menu button)
- [ ] Right-clicking empty space in the file list opens a menu with just
      Paste (if applicable) and New File/New Folder
- [ ] The right-click menu's actions work identically to the same
      actions via the Menu button
- [ ] Right-click is NOT offered in the Save As picker
- [ ] Clock is visible, correct, and keeps ticking forward even if you
      don't touch anything for a while
- [ ] Clock never gets overwritten/corrupted by a long window title in
      the taskbar
- [ ] Clicking `o` maximizes a window to fill the screen (not covering
      the taskbar); clicking it again restores the original size/position
- [ ] Dragging a maximized window's title bar (or its resize handle)
      un-maximizes it at the size/position you end up at, rather than
      snapping back to the pre-maximize size later
- [ ] All of the above still work on a mono (standard) screen and on a
      pocket computer's small screen

## Step 9 — Configurable close button (2026-09-06)

Confirmed working in-game: steps 1-8.

Requested directly to close a real gap noted at the end of step 8: the
Save As picker's title-bar `[x]` would leave a waiting Text Editor
stuck forever, and separately, the Editor's own unsaved-changes confirm
only fired via its in-app Close button, not the title-bar one.

Built:

- `wm.lua`: windows default to closing instantly on `[x]` (unchanged
  behavior for every existing app that doesn't touch this). A window can
  opt out via `entry.customClose = true`, in which case `[x]` delivers a
  `ccios_close_request` event to that window instead of closing it
  directly - bypassing filter matching the same way `terminate` does, so
  the app always gets a chance to respond. New `wm.currentWindow` field,
  set to the entry right before every resume, is how an app identifies
  "myself" to set this during its own startup (see docs/ARCHITECTURE.md
  for why a direct field write here, unlike everything else on
  `_G.ccios.wm`, is the one sanctioned exception to "read-only").
- Text Editor now opts in unconditionally and handles
  `ccios_close_request` with the same `confirmClose()` its Close button
  already used - so both closing paths now behave identically.
- Save As picker (File Explorer in `pickerMode == "save"`) opts in only
  while picking, and its handler is just `cancelSave()` - the same thing
  its own Cancel button does - so `[x]` now correctly reports
  "cancelled" back to the Editor instead of leaving it hanging.

### Things to specifically check when testing

- [ ] Text Editor: clicking the title-bar `[x]` with no unsaved changes
      closes immediately, same as before
- [ ] Text Editor: clicking `[x]` WITH unsaved changes now shows the
      same "Unsaved changes. Close without saving?" dialog the in-app
      Close button already showed, and "No" leaves the window open
- [ ] Save As picker: clicking `[x]` closes the picker AND the waiting
      Editor shows "Save As cancelled" (not stuck/unresponsive)
- [ ] Every other app (About, System Monitor, plain File Explorer
      browsing, any `.lua` file launched directly) still closes
      instantly on `[x]` - this should be a no-op for anything that
      doesn't opt in
- [ ] A crash while handling `ccios_close_request` (contrived, but worth
      a sanity check if convenient) still results in the window closing
      rather than becoming permanently unclosable

## Step 8 — New File/Folder, Save As picker (2026-09-06)

Confirmed working in-game: steps 1-7.

Built:

- File Explorer's Menu gains `New File` and `New Folder`, always
  available regardless of what's selected (they act on `currentPath`).
  Both prompt for a name via the same blocking-`read()`-with-default
  technique used elsewhere, refuse to overwrite an existing entry with
  the same name (no confirm needed here — it just fails with a status
  message rather than proceeding, since creating-with-collision isn't
  really "destructive" the way overwriting content is), then refresh.
- Text Editor's `Save` with no path set no longer prompts inline for a
  path — it now launches File Explorer itself as a "Save As" picker:
  browse to any folder, click `Save`, type a filename (pre-filled with
  a suggested name, fully editable), confirm if it would overwrite
  something. Same visual flow as Windows' save dialog, built by
  repurposing Explorer rather than writing a second file-browsing UI.
- The picker reports its result back to the Editor via
  `os.queueEvent("ccios_save_dialog_result", requestId, path)` rather
  than a direct callback, because Explorer and the Editor are separate
  coroutines the WM redirects `term` for independently — see
  docs/ARCHITECTURE.md's new "Save As picker mode" section for why a
  direct closure call would have corrupted whichever window was on
  screen at the time. `requestId` (a fresh `tostring({})` per request)
  keeps multiple simultaneous Editor-picker pairs from cross-matching.
- Known gap, called out in the architecture doc: if the picker window
  is closed via the title-bar `x` instead of its own `Cancel`
  button/Escape key, no result is ever sent and the Editor just keeps
  waiting silently (not a crash - Save just never completes until tried
  again). Wiring a real "window closed" notification into the WM is a
  bigger change than this step warranted.

### Things to specifically check when testing

- [ ] Menu > New File / New Folder in Explorer both prompt, create the
      right thing, and show up in the list afterward
- [ ] Trying to create a file/folder with a name that already exists in
      the current directory fails cleanly (status message, nothing
      overwritten) instead of erroring
- [ ] Text Editor: Ctrl+S (or the Save button) on a brand-new untitled
      document opens a "Save As" Explorer window instead of the old
      inline prompt
- [ ] In the Save As window: browsing into folders works normally,
      clicking Save prompts for a name (pre-filled with a sensible
      default), and confirming actually writes the file to the chosen
      folder and closes the picker
- [ ] After a successful Save As, the Editor's title bar/status updates
      to show the new path and the "unsaved changes" indicator clears
- [ ] Save As picker's Cancel button (and Escape) closes it without
      saving, and the Editor correctly shows "Save As cancelled"
      instead of hanging
- [ ] Clicking a file inside the Save As picker pre-fills its name when
      you then click Save (rather than requiring it to be typed by hand)
- [ ] Opening two Text Editor windows and triggering Save As on both
      around the same time doesn't cross-wire which picker's result goes
      to which Editor

## Step 7 — Text Editor, Explorer Menu + clipboard (2026-09-06)

Confirmed working in-game: steps 1-6.

Built:

- `src/ccios/kernel/dialog.lua` — shared modal Yes/No confirm box,
  `dofile`'d by an app when it needs one (see docs/ARCHITECTURE.md for
  why this could be a blocking call inside a click handler)
- `src/ccios/apps/editor/` — fourth real app, a plain-text/Lua editor:
  arrow-key/mouse cursor movement, Ctrl+S or a `[Save]` button to save
  (prompts for a path if launched with none), `[Close]` button that
  confirms first if there are unsaved changes
- `_G.ccios.launch` now threads an optional `app.args` through to the
  launched program (`boot.lua`'s `launchApp` already supported passing
  extra args to `wm:launch`, just wasn't wired up yet) — this is how
  Explorer hands the Text Editor a file path to open
- File Explorer: a `Menu` button (top-right) opens a dropdown built from
  the selected entry — `Open`/`Run`/`Edit`/`Copy`/`Cut`/`Delete`, plus
  `Paste` when the clipboard has something. Implemented the same way as
  the WM's own Start menu.
- Clipboard: `Copy`/`Cut` (Cut confirms via the dialog, as asked for,
  even though nothing on disk changes until `Paste`), `Paste` uses
  `fs.move`/`fs.copy` and confirms before overwriting an existing file
- `Edit` opens *any* file type in the Text Editor, not just `.lua` —
  this is how non-Lua files became viewable/editable, per the request,
  without building a separate viewer into Explorer itself

### Things to specifically check when testing

- [ ] Text Editor opens from the Start menu with a blank buffer, and
      from Explorer's Menu > Edit with the file's actual content loaded
- [ ] Typing, arrow keys, Home/End, Enter, Backspace, and Delete all
      behave correctly, including at the start/end of lines (merging
      with the previous/next line)
- [ ] Ctrl+S saves; the `[Save]` button does the same; a brand-new
      untitled buffer prompts for a filename first
- [ ] `[Close]` with no changes closes immediately; with unsaved changes
      it asks first, and "no" leaves the window open
- [ ] Explorer's `Menu` button shows the right actions per entry type
      (folder vs `.lua` file vs other file), and `Paste` only appears
      once something's been copied/cut
- [ ] Copy then Paste duplicates a file/folder; Cut then Paste moves it
      (and Cut itself shows a confirm dialog first)
- [ ] Delete confirms, then actually removes the file/folder and updates
      the list
- [ ] Pasting over an existing file/folder confirms before overwriting
- [ ] Clicking Menu > Edit on a `.lua` file opens it in the Text Editor
      (separate from Run, which still launches it as a program)
- [ ] All of the above still work correctly on a mono (standard, non-
      Advanced) screen — nothing here should error over color usage

## Step 6 — File Explorer (2026-09-06)

Confirmed working in-game: steps 1-5.

Built:

- `src/ccios/apps/explorer/` — third real app: browse directories
  (`fs.list`/`fs.isDir`), navigate with arrow keys/PageUp/PageDown/
  Enter/Backspace or mouse clicks, `..` entry to go up
- Double-click detection (CraftOS has no such event; tracked manually as
  "second click on the same entry within 0.5s")
- Double-click or Enter on a `.lua` file launches it as a window via a
  new `_G.ccios.launch(app)` (`boot.lua`'s cascaded/clamped placement
  logic, now reusable by any app instead of just the Start menu)
- Drag-and-drop: listens for CraftOS's `file_transfer` event and writes
  dropped files into whatever directory Explorer currently has open
- `wm.lua`: `file_transfer` added to the focused-only event set, so a
  drop only ever lands in the Explorer window you actually have open and
  focused, not every open window
- Other file types / delete / rename / copy / move are explicitly *not*
  implemented yet — see docs/ARCHITECTURE.md's deferred list for why
  (need a text viewer and a confirmation-dialog primitive first)

### Things to specifically check when testing

- [ ] File Explorer appears in the Start menu and opens at `/`
- [ ] Navigating into folders and back out (`..`, Backspace) works
- [ ] Arrow keys / PageUp / PageDown move selection and scroll correctly
      once the list is longer than the window
- [ ] Single-click selects; a second click on the same item shortly after
      opens it (double-click); clicking a *different* item right after a
      first click does NOT count as a double-click on either
- [ ] Double-click / Enter on a `.lua` file opens a new window running it
- [ ] Drag-and-dropping a file onto the Minecraft window while Explorer
      is open and focused copies it into the currently-open folder, and
      it shows up in the list after
- [ ] Dropping a file while Explorer is open but NOT focused (some other
      window focused) does *not* silently go into Explorer's folder
- [ ] Clicking a non-`.lua` file shows the "no viewer yet" message
      instead of erroring

## Step 5 — System Monitor app (2026-09-06)

Confirmed working in-game: steps 1-4.

Built:

- `src/ccios/apps/sysmon/` — second real app, shows:
  - Disk usage (`fs.getFreeSpace`/`fs.getCapacity` on `/`), with a bar
  - "Watchdog headroom" — see docs/ARCHITECTURE.md's new section; this is
    an *approximation* of how close the computer is coming to CraftOS's
    "too long without yielding" kill switch, not a real instruction
    counter (CraftOS doesn't expose one). Worth reading that section
    before trusting the number.
  - Lua memory (`collectgarbage("count")`, if available)
  - Open window count / installed app count
  - Peripheral count (`peripheral.getNames()`)
  - Uptime (`os.clock()`), computer ID, CraftOS version, screen size
  - Refreshes every second and on resize
- `_G.ccios` global surface (`boot.lua`) exposing the live WM instance
  to apps — first real "kernel API" surface, currently just informational
- `wm:run()` now times each dispatch+draw cycle and tracks the worst one
  seen (`self.stats.lastBurst` / `maxBurst`) — this is what sysmon's
  watchdog gauge reads
- Bug fix while wiring this up: `boot.lua`'s `launchApp` didn't clamp an
  app's requested window size to the actual screen size, so a wide app
  (sysmon defaults to 42 wide) could hang off the edge of a small pocket
  computer screen. Now clamped the same way the original About window
  always was.

### Things to specifically check when testing

- [ ] System Monitor appears in the Start menu and opens correctly
- [ ] Disk numbers look plausible (compare against `fs.getFreeSpace("/")`
      typed directly in the shell)
- [ ] Values update every second without flicker/tearing
- [ ] Resizing the System Monitor window reflows its content instead of
      leaving stale text
- [ ] On a pocket computer's small screen, the window (now clamped)
      doesn't hang off the edge, and text doesn't get too cramped to read
- [ ] Watchdog gauge reads near 0% during normal use; worth trying to
      intentionally add a slow/busy app later to confirm it actually
      moves (not required for this step, just noting for later)

## Step 4 — Resizable windows (2026-09-06)

Confirmed working in-game: steps 1-3.

Built:

- Resize handle (`\`) in the bottom-right corner of every window,
  dragging it resizes the window the same way dragging the title bar
  moves it (see `self.resizeDrag` in `wm.lua`, mirrors `self.chromeDrag`)
- Min size clamp (8 wide, 3 tall) and clamped to stay on-screen / above
  the taskbar, same as dragging
- Resizing now sends the window's app a `term_resize` event so it can
  redraw at the new size — the About app already had a `term_resize`
  branch waiting for this from step 1, it was just never reachable
  before
- Draw order changed so window content is blitted *before* chrome (title
  bar, close button, resize handle), otherwise a resize handle sitting
  on the app's own content row would get overwritten by that app's draw

### Things to specifically check when testing

- [ ] Dragging the `\` in a window's bottom-right corner resizes it live
- [ ] About app's text reflows/redraws correctly as the window shrinks
      and grows (no leftover garbage from the old size)
- [ ] Can't shrink a window below a usable minimum size
- [ ] Can't resize a window off the bottom of the screen (into/past the
      taskbar) or off the right edge
- [ ] Resize handle is still clickable/draggable after moving the window
      with the title bar first (position tracking staying in sync)
- [ ] On a pocket computer's small screen, the resize handle is still
      findable/usable despite being a single cell

## Step 3 — Start menu (2026-09-06)

Confirmed working in-game: steps 1-2.

Built:

- `src/ccios/kernel/apps.lua` — scans `/ccios/apps/*/manifest.json` and
  returns the installed app list; nothing in the kernel hardcodes app
  paths anymore
- Taskbar `+` button replaced with a proper `Start` button + popup menu
  listing installed apps (currently just "About CCIOS"); clicking an
  entry launches it, cascaded like the old `+` button did
- `boot.lua` now launches its two demo About windows through the same
  `onLaunchApp` path the Start menu uses, instead of a separate
  hardcoded spawn function

Only one real app exists so the menu is a bit of a formality right now,
but the plumbing (manifest discovery -> menu -> launch callback) is the
same path an app-store install will use later, so there's nothing to
redo when app #2 shows up.

### Things to specifically check when testing

- [ ] Clicking `Start` opens a menu listing "About CCIOS" above the
      taskbar, without covering the taskbar itself
- [ ] Clicking "About CCIOS" in the menu opens a new window and closes
      the menu
- [ ] Clicking `Start` again while the menu is open closes it without
      launching anything
- [ ] Clicking elsewhere (a window, empty desktop, a taskbar entry)
      while the menu is open closes the menu AND still performs that
      click normally (e.g. focuses the window you clicked)
- [ ] Menu position/width stays sane on a small pocket-computer screen
- [ ] Boots the same as before: two overlapping About windows already
      open

## Step 2 — Multiple windows (2026-09-06)

Confirmed working in-game: step 1 (window manager + About app, mono and
color, standard and pocket computers).

Built:

- Taskbar `+` button (`wm.onNewWindow` callback) that spawns another
  window on demand; `boot.lua` wires it to open more About windows,
  cascaded diagonally so overlaps are obvious
- Boots with two About windows open already, so overlap is visible
  immediately without needing to click anything

The window manager already drew windows back-to-front in z-order and
moved a window to the top of that order on focus (click, or on launch) —
step 1 just never had more than one window to prove it with. No change
needed there; this step is really "give it something to overlap."

### Things to specifically check when testing

- [ ] Boots with two overlapping About windows; the second one (topmost)
      visibly covers part of the first
- [ ] Clicking a partially-hidden window (on its visible sliver) brings
      it to front and covers the other one instead
- [ ] Taskbar `+` button spawns another window, cascaded to a new
      position, without covering the taskbar itself
- [ ] Taskbar entries for all open windows are clickable and correctly
      focus/minimize the right one once there are 3+ windows
- [ ] Closing the topmost window reveals the one beneath it correctly
      (no leftover visual garbage from the closed window)
- [ ] Dragging one window over another still redraws correctly (no
      stale pixels left behind at the old position)

## Step 1 — Window manager + About app (2026-09-06)

Built:

- `src/ccios/kernel/wm.lua` — window manager (see ARCHITECTURE.md)
- `src/ccios/kernel/boot.lua` — boots the WM and opens About, centered
- `src/ccios/apps/about/main.lua` — first test app
- `install.lua` — `wget run` bootstrap installer, driven by `manifest.json`
- `src/ccios/kernel/updater.lua` — shared install/update logic: fetches
  `manifest.json`, compares its `version` against `/ccios/version.json`,
  re-downloads everything listed if they differ. Used by `install.lua`,
  `/update.lua` (manual command), and `boot.lua` (check-on-boot).
- Auto-update-on-boot is opt-out via the CC `settings` API
  (`ccios.autoUpdateCheck`, default on) and always asks for confirmation
  before writing anything or rebooting — no silent overwrites of files a
  tester might be mid-edit on.

Not yet tested in-game — this was written and reasoned through without a
CC:Tweaked runtime available in the dev environment (no local Lua/CraftOS
emulator was installed here). **Needs manual testing before step 2.**

### Things to specifically check when testing

- [ ] Boots correctly on a **standard** computer (mono screen)
- [ ] Boots correctly on an **advanced** computer (color screen)
- [ ] Boots correctly on a **standard pocket computer**
- [ ] Boots correctly on an **advanced pocket computer**
- [ ] Title bar drag actually moves the window and clamps to screen bounds
- [ ] Close button (`x`) closes the window and exits CCIOS cleanly (no
      windows left → `wm:run()` returns → falls back to shell)
- [ ] Taskbar entry click focuses / minimizes / restores correctly
- [ ] Mouse clicks inside the About window's content area don't get
      misrouted (off-by-one on the title-bar-height offset is the likely
      failure mode if something's wrong)
- [ ] Ctrl+T while the About window is focused closes just that window,
      not the whole computer session
- [ ] `install.lua` actually fetches and installs once pushed to GitHub
      `main`
- [ ] Boot-time update check: shows up when `manifest.json` on `main` has
      a newer `version` than `/ccios/version.json`, declines cleanly on
      "n", applies + reboots cleanly on "y"
- [ ] `update` command works the same way when run manually from the shell
- [ ] With `http` disabled (or no network), boot doesn't hang or error —
      it should just skip the check silently

### Known gaps going into step 2

- No start menu / app launcher yet — boot.lua hardcodes launching About
- Crash messages from a dead app aren't shown anywhere yet
- Windows aren't resizable, only draggable
