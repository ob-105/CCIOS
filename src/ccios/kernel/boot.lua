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

local screenW, screenH = term.current().getSize()
local aboutW = math.min(36, screenW)
local aboutH = math.min(12, screenH - 1) -- leave room for the taskbar

-- spawns another About window, cascading each new one down-right of the
-- last so overlapping windows (and the topmost-drawn-last z-order) are
-- easy to see and test
local spawnCount = 0
local function spawnAbout()
    local baseX = math.max(1, math.floor((screenW - aboutW) / 2) + 1)
    local baseY = math.max(1, math.floor((screenH - 1 - aboutH) / 2) + 1)
    local step = spawnCount % 6
    local x = math.min(baseX + step * 2, math.max(1, screenW - aboutW + 1))
    local y = math.min(baseY + step, math.max(1, screenH - 1 - aboutH + 1))
    spawnCount = spawnCount + 1
    manager:launch(
        CCIOS_ROOT .. "/apps/about/main.lua",
        "About CCIOS",
        x, y, aboutW, aboutH
    )
end

manager.onNewWindow = spawnAbout

spawnAbout()
spawnAbout()

manager:run()
