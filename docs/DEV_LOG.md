# Dev log

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
