# Dev log

## Step 1 — Window manager + About app (2026-09-06)

Built:

- `src/ccios/kernel/wm.lua` — window manager (see ARCHITECTURE.md)
- `src/ccios/kernel/boot.lua` — boots the WM and opens About, centered
- `src/ccios/apps/about/main.lua` — first test app
- `install.lua` — `wget run` bootstrap installer, pulls from
  `raw.githubusercontent.com/ob-105/CCIOS/main/`

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

### Known gaps going into step 2

- No start menu / app launcher yet — boot.lua hardcodes launching About
- Crash messages from a dead app aren't shown anywhere yet
- Windows aren't resizable, only draggable
