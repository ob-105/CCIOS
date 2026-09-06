-- CCIOS Settings
-- A normal CraftOS program (see docs/ARCHITECTURE.md). Currently just
-- the auto-update-on-boot toggle (boot.lua's own setting, read/written
-- via the standard CC `settings` API) and a manual "check now" button
-- that reuses updater.lua directly instead of duplicating its logic.
-- More settings land here as CCIOS grows things worth making
-- configurable.

local dialogOk, dialog = pcall(dofile, "/ccios/kernel/dialog.lua")
if not dialogOk then
    dialog = nil
end

local updaterOk, updater = pcall(dofile, "/ccios/kernel/updater.lua")
if not updaterOk then
    updater = nil
end

local isColor = term.isColor and term.isColor() or false
local function pickColor(colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

settings.define("ccios.autoUpdateCheck", {
    description = "Check for CCIOS updates on boot",
    default = true,
    type = "boolean",
})
settings.load()

local status = nil
local checkBtnX1, checkBtnX2, checkBtnY
local AUTO_UPDATE_ROW = 4

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2, 1)
    term.write("Settings")
    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))

    local autoUpdate = settings.get("ccios.autoUpdateCheck")
    term.setCursorPos(2, AUTO_UPDATE_ROW)
    term.setTextColor(pickColor(colors.yellow, colors.white))
    term.write(autoUpdate and "[x]" or "[ ]")
    term.setTextColor(colors.white)
    term.write(" Check for updates on boot")

    term.setCursorPos(2, 6)
    local version = updater and updater.getInstalledVersion()
    term.write("CCIOS version: " .. (version or "unknown"))

    local btnLabel = " Check for Updates Now "
    checkBtnX1, checkBtnX2, checkBtnY = 2, 2 + #btnLabel - 1, 8
    term.setCursorPos(checkBtnX1, checkBtnY)
    term.setBackgroundColor(pickColor(colors.blue, colors.black))
    term.setTextColor(colors.white)
    term.write(btnLabel)
    term.setBackgroundColor(colors.black)

    term.setCursorPos(2, h)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    term.write((status or "Click a checkbox or button to change something"):sub(1, w - 2))
    term.setTextColor(colors.white)
end

local function toggleAutoUpdate()
    local current = settings.get("ccios.autoUpdateCheck")
    settings.set("ccios.autoUpdateCheck", not current)
    settings.save()
    status = "Saved"
end

local function checkForUpdatesNow()
    if not updater then
        status = "Updater unavailable"
        return
    end
    if not http then
        status = "No http API - can't check for updates"
        return
    end

    status = "Checking..."
    draw()
    local hasUpdate, manifest, err = updater.checkForUpdate()
    if err then
        status = "Check failed: " .. tostring(err)
        return
    end
    if not hasUpdate then
        status = ("Already up to date (%s)"):format(updater.getInstalledVersion() or "?")
        return
    end

    local proceed = true
    if dialog then
        proceed = dialog.confirm(("Update available: %s -> %s. Install?"):format(
            updater.getInstalledVersion() or "?", manifest.version))
    end
    if not proceed then
        status = "Update skipped"
        return
    end

    status = "Updating..."
    draw()
    local ok, applyErr = updater.applyManifest(manifest)
    if not ok then
        status = "Update failed: " .. tostring(applyErr)
        return
    end

    status = "Updated - rebooting..."
    draw()
    os.reboot()
end

local function handleClick(px, py)
    local w = select(1, term.getSize())
    if py == AUTO_UPDATE_ROW and px >= 2 and px <= w - 2 then
        toggleAutoUpdate()
    elseif py == checkBtnY and px >= checkBtnX1 and px <= checkBtnX2 then
        checkForUpdatesNow()
    end
end

draw()

while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "mouse_click" then
        handleClick(p2, p3)
    end
    draw()
end
