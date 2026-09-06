# CCIOS — CC Interlinked Operating System

A Windows 11-styled GUI operating system for [CC: Tweaked](https://tweaked.cc/),
for standard and advanced Computers and Pocket Computers.

Built one part at a time, bug-tested manually in-game after each step.

## Status

**Steps 1-12 (window manager, multiple windows, Start menu, resizing, System Monitor, File Explorer, Text Editor, New File/Save As picker, configurable close button, right-click menus/clock/maximize, system scrollbars, crash notifications/Settings/Task Manager) — tested in-game, working.**
**Step 13 (App Store) — done, pending in-game testing.**

- Floating, draggable, closable, resizable, maximizable windows with
  title bars
- Multiple windows at once; focusing a window (by clicking it, or
  launching a new one) always draws it on top of the others
- Taskbar with per-window entries (click to focus, click again to
  minimize), a Start button that opens a menu of installed apps, and a
  live clock
- Installed apps are discovered at boot from `/ccios/apps/*/manifest.json`
  — no hardcoded app list anywhere in the kernel
- Drag a window's bottom-right corner (`\`) to resize it, or click the
  `o` button on its title bar to maximize/restore; apps get a
  `term_resize` event either way and can redraw at the new size
- A window can request a taller/wider drawing surface than its visible
  size (declared in its manifest); the WM composites and scrolls it
  automatically, with vertical and/or horizontal scrollbars, mouse-wheel
  support, and draggable thumbs — the app itself doesn't need to know
  its content is being scrolled. System Monitor uses this so its full
  output is reachable without having to maximize the window.
- Works on color (Advanced) and mono (standard) screens
- Apps are ordinary CraftOS programs (`term.*` / `os.pullEvent`) — no
  special API required to write one
- "About CCIOS", "System Monitor" (disk usage, watchdog headroom,
  memory, open windows, peripherals), "File Explorer", "Text Editor",
  "Settings", "Task Manager", and "App Store" apps, all in the Start menu
- App Store: browses a GitHub-hosted catalog as a grid of 3x3-pixel
  banner tiles; click one for its page (description, author, latest vs.
  installed version, Install/Update/Delete). Installing just drops a
  normal `/ccios/apps/<id>/` folder — the same shape every other app
  already has — and refreshes the Start menu immediately, no reboot
  needed. Ships with one real optional app (a four-function Calculator)
  to prove the whole pipeline end to end.
- A crashed app now shows a dismissable toast with its error message
  instead of just silently vanishing
- Settings: toggle the auto-update-on-boot check, or check for updates
  right now
- Task Manager: lists every open window and force-closes ("End Task")
  one directly, bypassing whatever close confirmation it might
  otherwise show — for when an app won't close normally
- File Explorer: browse folders, double-click (or Enter) a `.lua` file
  to run it, drag-and-drop a file onto the Minecraft window to copy it
  into whatever folder is currently open, and contextual actions —
  Run/Edit/Copy/Cut/Delete/Paste/New File/New Folder — from either the
  Menu button (top-right) or right-clicking a file/folder (or empty
  space, for Paste/New). Cut, Delete, and pasting over an existing file
  all confirm first via a shared modal dialog.
- Text Editor: plain-text/Lua editing with save (Ctrl+S or a button),
  opened from Explorer's Menu (any file type) or directly from the
  Start menu (blank document). Saving a document with no path yet opens
  the File Explorer as a "Save As" picker — browse to any folder, click
  Save, type a name — the same way Windows does it.
- A window's title-bar close button closes it immediately by default,
  but an app can opt in to handling it itself instead — the Text Editor
  always does, to confirm unsaved changes first; the Save As picker does
  while it's open, so closing it that way correctly cancels instead of
  leaving the Text Editor waiting forever
- Auto-updater: checks GitHub for a newer `manifest.json` on boot (asks
  before installing), plus a manual `update` shell command

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works and
[docs/DEV_LOG.md](docs/DEV_LOG.md) for progress notes and open questions.

## Installing (in-game)

Requires the `http` API to be enabled on the server/config
(`http_enable = true` in CC:Tweaked's config, or the default global rule).

On a Computer or Pocket Computer:

```text
wget run https://raw.githubusercontent.com/ob-105/CCIOS/main/install.lua
```

This installs `/startup.lua` and `/ccios/...`, then reboots into CCIOS.

## Updating

CCIOS checks GitHub for a newer version each boot and asks before
installing (toggle it from the Settings app, or with
`settings.set("ccios.autoUpdateCheck", false)` then `settings.save()`).
To check on demand, run:

```text
update
```

or use Settings' "Check for Updates Now" button.

Both paths compare against `manifest.json` on the `main` branch, so a
push to `main` is what makes an update available to installs in the wild.

## Repo layout

```text
manifest.json             -- version + file list; single source of truth for install/update
install.lua                -- bootstrap installer (wget run this in-game)
src/
  startup.lua               -- installed as /startup.lua; hands off to the kernel
  update.lua                -- installed as /update.lua; manual update command
  ccios/
    kernel/
      wm.lua                -- window manager
      boot.lua              -- kernel entry point: update check, then launches app(s)
      updater.lua           -- shared install/update logic (used by install.lua, update.lua, boot.lua)
      apps.lua               -- scans /ccios/apps for installed apps (feeds the Start menu)
      dialog.lua              -- shared modal confirm-box helper (dofile'd by apps)
    apps/
      about/
        main.lua            -- About CCIOS app
        manifest.json       -- app metadata
      sysmon/
        main.lua            -- System Monitor app
        manifest.json       -- app metadata
      explorer/
        main.lua            -- File Explorer app
        manifest.json       -- app metadata
      editor/
        main.lua            -- Text Editor app
        manifest.json       -- app metadata
      settings/
        main.lua            -- Settings app
        manifest.json       -- app metadata
      taskmgr/
        main.lua            -- Task Manager app
        manifest.json       -- app metadata
      appstore/
        main.lua            -- App Store app
        manifest.json       -- app metadata
store/
  catalog.json                -- App Store's catalog: id/name/description/version/banner/path per app
  apps/
    calculator/
      main.lua                -- optional app, installed on demand via the App Store (not bundled)
      manifest.json
docs/
  ARCHITECTURE.md
  DEV_LOG.md
```

## Roadmap

1. ~~Window manager + About app~~ — done (step 1)
2. ~~App launcher / start menu, multiple simultaneous windows~~ — done (steps 2-3)
3. ~~App store: browsing, install/update/remove from GitHub-hosted app repo~~ — done (step 13); all apps currently live in this same repo under `store/apps/`, not yet a multi-author/multi-repo catalog
4. App developer documentation + app submission process — not started
5. ~~Core apps~~ — file manager, settings, text editor, task manager all done; still no terminal
6. Pocket-computer specific UX polish — not started
