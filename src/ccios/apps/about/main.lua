-- CCIOS About app
-- A normal CraftOS program: it just draws to whatever `term` currently
-- points at (its own window, injected by the WM) and reads events via
-- the ordinary os.pullEvent. Nothing here is CCIOS-window-manager-aware.

local function centerText(y, text, w)
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    term.setCursorPos(x, y)
    term.write(text)
end

local function draw()
    local w, h = term.getSize()
    local isColor = term.isColor and term.isColor() or false

    term.setBackgroundColor(isColor and colors.black or colors.black)
    term.setTextColor(isColor and colors.white or colors.white)
    term.clear()

    centerText(2, "CCIOS", w)
    centerText(3, "CC Interlinked Operating System", w)
    centerText(4, string.rep("-", math.min(w - 2, 32)), w)

    local id = os.getComputerID and os.getComputerID() or -1
    local label = (os.getComputerLabel and os.getComputerLabel()) or "(unlabeled)"
    local deviceKind = "Computer"
    if pocket then
        deviceKind = "Pocket Computer"
    elseif turtle then
        deviceKind = "Turtle"
    end

    local lines = {
        "Version    : 0.7.0",
        "Device     : " .. deviceKind .. (isColor and " (advanced)" or " (standard)"),
        "Computer ID: " .. tostring(id),
        "Label      : " .. label,
        "CraftOS    : " .. tostring(os.version and os.version() or "unknown"),
        "Screen     : " .. w .. "x" .. h,
    }

    local startY = 6
    for i, line in ipairs(lines) do
        term.setCursorPos(2, startY + i - 1)
        term.write(line)
    end

    term.setCursorPos(2, startY + #lines + 1)
    term.write("Drag this window's title bar to move it.")
    term.setCursorPos(2, startY + #lines + 2)
    term.write("Click the [x] on the title bar to close.")
end

draw()

-- keep the app alive so the window stays open; redraw on resize/focus
-- and quietly consume anything else so it doesn't error out.
while true do
    local event = os.pullEvent()
    if event == "term_resize" then
        draw()
    end
end
