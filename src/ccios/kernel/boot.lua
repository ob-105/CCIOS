-- CCIOS boot entry point.
-- Loaded by /startup.lua once CCIOS is installed to /ccios on the
-- computer. Optionally checks for updates, then starts the window
-- manager and opens the About app.

local CCIOS_ROOT = "/ccios"

settings.define("ccios.autoUpdateCheck", {
    description = "Check for CCIOS updates on boot",
    default = true,
    type = "boolean",
})
settings.load()

local function checkForUpdatesOnBoot()
    if not settings.get("ccios.autoUpdateCheck") then
        return
    end
    if not http then
        return -- no network access configured; silently skip
    end

    local ok, updater = pcall(dofile, CCIOS_ROOT .. "/kernel/updater.lua")
    if not ok then
        return
    end

    local hasUpdate, manifest, err = updater.checkForUpdate()
    if err or not hasUpdate then
        return
    end

    print(("CCIOS update available: %s -> %s"):format(
        updater.getInstalledVersion() or "unknown", manifest.version))
    io.write("Install now? (y/n) ")
    local answer = read()
    if answer:lower() ~= "y" then
        return
    end

    print("Updating...")
    local applyOk, applyErr = updater.applyManifest(manifest, function(dest)
        print("  " .. dest)
    end)
    if not applyOk then
        printError("Update failed: " .. tostring(applyErr))
        print("Continuing with the current version.")
        return
    end

    print("Updated. Rebooting...")
    os.reboot()
end

checkForUpdatesOnBoot()

local ok, wm = pcall(dofile, CCIOS_ROOT .. "/kernel/wm.lua")
if not ok then
    printError("CCIOS: failed to load window manager:")
    printError(tostring(wm))
    return
end

local manager = wm.new(term.current())

-- A small read-only-by-convention surface so apps (e.g. the System
-- Monitor) can query the running system without CCIOS needing a
-- separate formal "kernel API" yet. Apps should treat _G.ccios.wm as
-- informational and not mutate it - with one deliberate exception: an
-- app may set `_G.ccios.wm.currentWindow.customClose = true` during its
-- own startup (see wm.lua) to opt into handling its own close button
-- instead of the WM closing it unconditionally.
_G.ccios = _G.ccios or {}
_G.ccios.wm = manager
_G.ccios.root = CCIOS_ROOT

local screenW, screenH = term.current().getSize()

local appsOk, appsModule = pcall(dofile, CCIOS_ROOT .. "/kernel/apps.lua")
local installedApps = appsOk and appsModule.discover(CCIOS_ROOT .. "/apps") or {}
manager.startMenuApps = installedApps

-- Launches an app, cascading each new instance of it down-right of the
-- last so overlapping windows (and the topmost-drawn-last z-order) are
-- easy to see and test. Wired up as the Start menu's launch callback.
local spawnCounts = {}
local function launchApp(m, app)
    local w = math.min(app.width, screenW)
    local h = math.min(app.height, screenH - 1) -- leave room for the taskbar
    local baseX = math.max(1, math.floor((screenW - w) / 2) + 1)
    local baseY = math.max(1, math.floor((screenH - 1 - h) / 2) + 1)
    local count = spawnCounts[app.id] or 0
    local step = count % 6
    local x = math.min(baseX + step * 2, math.max(1, screenW - w + 1))
    local y = math.min(baseY + step, math.max(1, screenH - 1 - h + 1))
    spawnCounts[app.id] = count + 1
    m:launch(app.entry, app.name, x, y, w, h, app.virtualWidth, app.virtualHeight, table.unpack(app.args or {}))
end

manager.onLaunchApp = launchApp

-- Lets any app (e.g. the File Explorer opening a .lua file, or the Text
-- Editor via Explorer's Edit action) launch an arbitrary program the
-- same cascaded/clamped way the Start menu does, without needing to
-- duplicate that placement logic itself. `app.args`, if given, is
-- forwarded as extra arguments to the launched program (e.g. a file
-- path for the Text Editor to open).
_G.ccios.launch = function(app)
    launchApp(manager, app)
end

-- boot straight into a couple of About windows so multi-window overlap
-- is visible immediately, same as before the Start menu existed
for _, app in ipairs(installedApps) do
    if app.id == "about" then
        launchApp(manager, app)
        launchApp(manager, app)
    end
end

manager:run()
