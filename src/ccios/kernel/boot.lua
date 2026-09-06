-- CCIOS boot entry point.
-- Loaded by /startup.lua once CCIOS is installed to /ccios on the
-- computer. Starts the window manager and opens the About app.

local CCIOS_ROOT = "/ccios"

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
local aboutX = math.max(1, math.floor((screenW - aboutW) / 2) + 1)
local aboutY = math.max(1, math.floor((screenH - 1 - aboutH) / 2) + 1)

manager:launch(
    CCIOS_ROOT .. "/apps/about/main.lua",
    "About CCIOS",
    aboutX, aboutY, aboutW, aboutH
)

manager:run()
