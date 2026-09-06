# CCIOS — CC Interlinked Operating System

A Windows 11-styled GUI operating system for [CC: Tweaked](https://tweaked.cc/),
for standard and advanced Computers and Pocket Computers.

Built one part at a time, bug-tested manually in-game after each step.

## Status

**Steps 1-7 (window manager, multiple windows, Start menu, resizing, System Monitor, File Explorer, Text Editor) — tested in-game, working.**
**Step 8 (New File/Folder + Save As picker) — done, pending in-game testing.**

- Floating, draggable, closable, resizable windows with title bars
- Multiple windows at once; focusing a window (by clicking it, or
  launching a new one) always draws it on top of the others
- Taskbar with per-window entries (click to focus, click again to
  minimize) and a Start button that opens a menu of installed apps
- Installed apps are discovered at boot from `/ccios/apps/*/manifest.json`
  — no hardcoded app list anywhere in the kernel
- Drag a window's bottom-right corner (`\`) to resize it; apps get a
  `term_resize` event and can redraw at the new size
- Works on color (Advanced) and mono (standard) screens
- Apps are ordinary CraftOS programs (`term.*` / `os.pullEvent`) — no
  special API required to write one
- "About CCIOS", "System Monitor" (disk usage, watchdog headroom,
  memory, open windows, peripherals), "File Explorer", and "Text Editor"
  apps, all in the Start menu
- File Explorer: browse folders, double-click (or Enter) a `.lua` file
  to run it, drag-and-drop a file onto the Minecraft window to copy it
  into whatever folder is currently open, and a Menu button (top-right)
  with contextual actions — Run/Edit/Copy/Cut/Delete/Paste/New
  File/New Folder. Cut, Delete, and pasting over an existing file all
  confirm first via a shared modal dialog.
- Text Editor: plain-text/Lua editing with save (Ctrl+S or a button),
  opened from Explorer's Menu (any file type) or directly from the
  Start menu (blank document). Saving a document with no path yet opens
  the File Explorer as a "Save As" picker — browse to any folder, click
  Save, type a name — the same way Windows does it.
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
installing (toggle with `settings.set("ccios.autoUpdateCheck", false)`
then `settings.save()`). To check on demand, run:

```text
update
```

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
docs/
  ARCHITECTURE.md
  DEV_LOG.md
```

## Roadmap

1. **Window manager + About app** (this step)
2. App launcher / start menu, multiple simultaneous windows
3. App store: browsing, install/update/remove from GitHub-hosted app repo
4. App developer documentation + app submission process
5. Core apps (file manager, settings, terminal, text editor, ...)
6. Pocket-computer specific UX polish
