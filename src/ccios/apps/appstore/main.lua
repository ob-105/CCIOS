-- CCIOS App Store
-- A normal CraftOS program (see docs/ARCHITECTURE.md). Fetches
-- store/catalog.json from the CCIOS GitHub repo, shows it as a grid of
-- 3x3-pixel banner tiles, and lets you drill into an app's page to
-- install/update/delete it. Installed apps are ordinary
-- /ccios/apps/<id>/ folders - exactly what apps.lua already scans for
-- the Start menu - so nothing else needed to change to make installed
-- apps show up there; this app just refreshes that list immediately
-- after an install/delete instead of waiting for the next boot.

local dialogOk, dialog = pcall(dofile, "/ccios/kernel/dialog.lua")
if not dialogOk then
    dialog = nil
end

local REPO_RAW = "https://raw.githubusercontent.com/ob-105/CCIOS/main/"
local CATALOG_URL = REPO_RAW .. "store/catalog.json"

local isColor = term.isColor and term.isColor() or false
local function pickColor(colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

-- Named colors from the catalog map to real `colors.*` values; on a
-- mono screen anything "light" collapses to white and everything else
-- to black, since there's no way to show 16 distinct colors on one.
local COLOR_NAMES = {
    white = colors.white, orange = colors.orange, magenta = colors.magenta,
    lightBlue = colors.lightBlue, yellow = colors.yellow, lime = colors.lime,
    pink = colors.pink, gray = colors.gray, lightGray = colors.lightGray,
    cyan = colors.cyan, purple = colors.purple, blue = colors.blue,
    brown = colors.brown, green = colors.green, red = colors.red, black = colors.black,
}
local LIGHT_NAMES = {
    white = true, yellow = true, lime = true, lightBlue = true,
    lightGray = true, pink = true, cyan = true, orange = true,
}

local function bannerColor(name)
    local real = COLOR_NAMES[name] or colors.black
    if isColor then
        return real
    end
    return LIGHT_NAMES[name] and colors.white or colors.black
end

-- ---------------------------------------------------------------------
-- Networking / local install state
-- ---------------------------------------------------------------------

local function fetchFile(url)
    if not http then
        return nil, "http API not enabled"
    end
    local response, err = http.get(url)
    if not response then
        return nil, err or "request failed"
    end
    local body = response.readAll()
    response.close()
    return body
end

local function fetchCatalog()
    local body, err = fetchFile(CATALOG_URL)
    if not body then
        return nil, err
    end
    local data = textutils.unserialiseJSON(body)
    if not data or not data.apps then
        return nil, "could not parse catalog.json"
    end
    return data.apps
end

local function getInstalledVersion(id)
    local path = "/ccios/apps/" .. id .. "/manifest.json"
    if not fs.exists(path) then
        return nil
    end
    local f = fs.open(path, "r")
    local body = f.readAll()
    f.close()
    local data = textutils.unserialiseJSON(body)
    return data and data.version
end

-- Installed apps only show up in the Start menu because boot.lua reads
-- apps.lua's scan once at startup into manager.startMenuApps; refresh
-- that same list here so a fresh install/delete is usable immediately
-- instead of needing a reboot.
local function refreshStartMenu()
    if not (_G.ccios and _G.ccios.wm) then
        return
    end
    local ok, appsModule = pcall(dofile, "/ccios/kernel/apps.lua")
    if ok then
        _G.ccios.wm.startMenuApps = appsModule.discover(_G.ccios.root .. "/apps")
    end
end

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------

local screen = "grid" -- or "detail"
local catalog, catalogError = nil, nil
local selectedApp = nil
local status = nil

local tileRegions = {}   -- grid screen hit-test
local backBtnX1, backBtnX2, backBtnY
local detailButtons = {} -- detail screen hit-test

local TILE_W = 9
local TILE_H = 5

-- Forward-declared: installApp/deleteApp below redraw progress/status
-- before and after their (blocking) network calls, but are defined
-- before the drawing functions further down the file.
local draw

-- ---------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------

local function installApp(app)
    if not http then
        status = "No http API - can't install"
        return
    end
    status = "Installing " .. app.name .. "..."
    draw()

    local manifestBody, err1 = fetchFile(REPO_RAW .. app.path .. "/manifest.json")
    if not manifestBody then
        status = "Install failed: " .. tostring(err1)
        return
    end
    local mainBody, err2 = fetchFile(REPO_RAW .. app.path .. "/main.lua")
    if not mainBody then
        status = "Install failed: " .. tostring(err2)
        return
    end

    local dir = "/ccios/apps/" .. app.id
    if not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local mf = fs.open(dir .. "/manifest.json", "w")
    mf.write(manifestBody)
    mf.close()
    local mn = fs.open(dir .. "/main.lua", "w")
    mn.write(mainBody)
    mn.close()

    refreshStartMenu()
    status = "Installed " .. app.name .. " " .. app.version
end

local function deleteApp(app)
    if not dialog then
        status = "Delete unavailable (dialog helper missing)"
        return
    end
    if not dialog.confirm(("Delete %s? This removes it from this computer."):format(app.name)) then
        status = "Cancelled"
        return
    end
    fs.delete("/ccios/apps/" .. app.id)
    refreshStartMenu()
    status = "Deleted " .. app.name
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local function drawBanner(banner, x, y)
    for row = 1, 3 do
        for col = 1, 3 do
            local name = banner and banner[row] and banner[row][col]
            term.setCursorPos(x + (col - 1) * 2, y + row - 1)
            term.setBackgroundColor(bannerColor(name))
            term.write("  ")
        end
    end
    term.setBackgroundColor(colors.black)
end

local function wrapText(text, width)
    local lines = {}
    local line = ""
    for word in (text or ""):gmatch("%S+") do
        if #line == 0 then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    if #line > 0 then
        table.insert(lines, line)
    end
    return lines
end

local function drawGrid()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2, 1)
    term.write("App Store")
    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))

    tileRegions = {}

    if catalogError then
        term.setCursorPos(2, 4)
        term.setTextColor(pickColor(colors.red, colors.white))
        term.write(("Could not load the store: %s"):format(catalogError):sub(1, w - 2))
        return
    end
    if not catalog then
        term.setCursorPos(2, 4)
        term.write("Loading...")
        return
    end
    if #catalog == 0 then
        term.setCursorPos(2, 4)
        term.write("No apps available")
        return
    end

    local cols = math.max(1, math.floor(w / TILE_W))
    for i, app in ipairs(catalog) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = 1 + col * TILE_W
        local y = 3 + row * TILE_H

        drawBanner(app.banner, x, y)
        term.setCursorPos(x, y + 3)
        term.setTextColor(colors.white)
        term.write((app.name or app.id):sub(1, TILE_W - 1))

        table.insert(tileRegions, { x1 = x, y1 = y, x2 = x + 5, y2 = y + 3, app = app })
    end
end

local function drawDetail()
    local w = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    local backLabel = " < Back "
    term.setCursorPos(1, 1)
    term.setBackgroundColor(pickColor(colors.gray, colors.black))
    term.setTextColor(colors.white)
    term.write(backLabel)
    term.setBackgroundColor(colors.black)
    backBtnX1, backBtnX2, backBtnY = 1, #backLabel, 1

    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))

    drawBanner(selectedApp.banner, 2, 4)

    term.setCursorPos(9, 4)
    term.setTextColor(colors.white)
    term.write(selectedApp.name or selectedApp.id)
    term.setCursorPos(9, 5)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    term.write("by " .. (selectedApp.author or "unknown"))
    term.setTextColor(colors.white)

    local descLines = wrapText(selectedApp.description, w - 2)
    local y = 8
    for _, line in ipairs(descLines) do
        term.setCursorPos(2, y)
        term.write(line)
        y = y + 1
    end

    y = y + 1
    local installed = getInstalledVersion(selectedApp.id)
    term.setCursorPos(2, y)
    term.write("Latest version: " .. (selectedApp.version or "?"))
    y = y + 1
    term.setCursorPos(2, y)
    term.write("Installed: " .. (installed or "not installed"))
    y = y + 2

    detailButtons = {}
    local bx = 2
    local function addButton(label, action, color)
        term.setCursorPos(bx, y)
        term.setBackgroundColor(pickColor(color, colors.black))
        term.setTextColor(colors.white)
        term.write(label)
        term.setBackgroundColor(colors.black)
        table.insert(detailButtons, { x1 = bx, x2 = bx + #label - 1, y = y, action = action })
        bx = bx + #label + 2
    end

    if not installed then
        addButton(" Install ", function() installApp(selectedApp) end, colors.green)
    else
        if installed ~= selectedApp.version then
            addButton(" Update ", function() installApp(selectedApp) end, colors.green)
        end
        addButton(" Delete ", function() deleteApp(selectedApp) end, colors.red)
    end

    -- anchored right below the buttons, not to the bottom of the window
    -- (`h`) - with a taller virtual size than what's visible, `h` would
    -- put this far below the visible viewport
    y = y + 2
    term.setCursorPos(2, y)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    term.write((status or ""):sub(1, w - 2))
    term.setTextColor(colors.white)
end

draw = function()
    if screen == "grid" then
        drawGrid()
    else
        drawDetail()
    end
end

-- ---------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------

local function handleGridClick(px, py)
    for _, region in ipairs(tileRegions) do
        if px >= region.x1 and px <= region.x2 and py >= region.y1 and py <= region.y2 then
            selectedApp = region.app
            status = nil
            screen = "detail"
            return
        end
    end
end

local function handleDetailClick(px, py)
    if py == backBtnY and px >= backBtnX1 and px <= backBtnX2 then
        screen = "grid"
        selectedApp = nil
        status = nil
        return
    end
    for _, btn in ipairs(detailButtons) do
        if py == btn.y and px >= btn.x1 and px <= btn.x2 then
            btn.action()
            return
        end
    end
end

local function handleClick(px, py)
    if screen == "grid" then
        handleGridClick(px, py)
    else
        handleDetailClick(px, py)
    end
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

draw() -- shows "Loading..." before the (blocking) catalog fetch below
local apps, err = fetchCatalog()
catalog, catalogError = apps, err
draw()

while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "mouse_click" then
        handleClick(p2, p3)
    end
    draw()
end
