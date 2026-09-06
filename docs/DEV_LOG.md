# Dev log

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
