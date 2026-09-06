-- CCIOS Task Manager
-- A normal CraftOS program (see docs/ARCHITECTURE.md). Lists currently
-- open windows via the shared _G.ccios.wm surface and lets you
-- force-close ("End Task") one directly with wm:closeWindow - the
-- blunt instrument for an app that's stuck or misbehaving, same spirit
-- as Windows' Task Manager "End Task" (it bypasses whatever close
-- confirmation the app might otherwise show via customClose; that's
-- the point - if graceful closing worked, you'd just use the title bar).

local isColor = term.isColor and term.isColor() or false
local function pickColor(colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

local status = nil
local ROW_TOP = 3
local endButtons = {} -- [row] = { x1=, x2=, entry= }

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2, 1)
    term.write("Task Manager")
    term.setCursorPos(1, 2)
    term.write(string.rep("-", w))

    endButtons = {}

    local wmInfo = _G.ccios and _G.ccios.wm
    if not wmInfo then
        term.setCursorPos(2, ROW_TOP)
        term.write("Not running under CCIOS")
        return
    end

    local windowsList = wmInfo.windows
    if #windowsList == 0 then
        term.setCursorPos(2, ROW_TOP)
        term.write("No windows open")
    end

    local row = ROW_TOP
    -- topmost/focused window first
    for i = #windowsList, 1, -1 do
        if row > h - 1 then
            break
        end
        local entry = windowsList[i]
        local isFocused = (i == #windowsList) and not entry.minimized

        local endLabel = "[End]"
        local label = entry.title
        if entry.minimized then
            label = label .. " (minimized)"
        end
        local maxLabelW = math.max(0, w - 2 - #endLabel - 2)
        if #label > maxLabelW then
            label = label:sub(1, maxLabelW)
        end

        term.setCursorPos(2, row)
        term.setTextColor(isFocused and pickColor(colors.yellow, colors.white) or colors.white)
        term.write(label)

        local ex1 = w - #endLabel
        term.setCursorPos(ex1, row)
        term.setBackgroundColor(pickColor(colors.red, colors.black))
        term.setTextColor(colors.white)
        term.write(endLabel)
        term.setBackgroundColor(colors.black)

        endButtons[row] = { x1 = ex1, x2 = ex1 + #endLabel - 1, entry = entry }
        row = row + 1
    end

    term.setCursorPos(2, h)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    term.write((status or ("%d window(s) open"):format(#windowsList)):sub(1, w - 2))
    term.setTextColor(colors.white)
end

local function handleClick(px, py)
    local btn = endButtons[py]
    if not (btn and px >= btn.x1 and px <= btn.x2) then
        return
    end
    local wmInfo = _G.ccios and _G.ccios.wm
    if not wmInfo then
        return
    end
    local title = btn.entry.title
    wmInfo:closeWindow(btn.entry)
    status = "Closed " .. title
end

draw()

local refreshTimer = os.startTimer(1)
while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "mouse_click" then
        handleClick(p2, p3)
    elseif event == "timer" and p1 == refreshTimer then
        refreshTimer = os.startTimer(1)
    end
    draw()
end
