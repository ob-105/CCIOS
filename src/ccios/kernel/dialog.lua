-- CCIOS shared dialog helper.
-- Not app-specific; apps that need a modal confirm box dofile this
-- (currently File Explorer and Text Editor). Kept intentionally small -
-- extend when a third real need shows up, not before.

local dialog = {}

local function pickColor(colorValue, monoValue)
    local isColor = term.isColor and term.isColor() or false
    return isColor and colorValue or monoValue
end

-- Draws a centered Yes/No box over whatever is currently on screen and
-- blocks until the user answers (click, or Y/Enter/N/Escape). Returns
-- true for Yes, false for No/cancel.
--
-- This runs its own tiny event loop via os.pullEvent, which works
-- because the calling app is itself just a coroutine the WM resumes
-- with events (see docs/ARCHITECTURE.md) - nesting another pullEvent
-- loop inside a key/click handler is no different from CraftOS's own
-- `read()` blocking the same way. The caller is responsible for calling
-- its own draw() again afterwards to erase the box.
function dialog.confirm(message, yesLabel, noLabel)
    yesLabel = yesLabel or "Yes"
    noLabel = noLabel or "No"

    local w, h = term.getSize()
    local boxW = math.min(w - 2, math.max(24, #message + 4))
    local boxH = 5
    local x = math.max(1, math.floor((w - boxW) / 2) + 1)
    local y = math.max(1, math.floor((h - boxH) / 2) + 1)

    local yx1, yx2, nx1, nx2, by

    local function draw()
        for row = 0, boxH - 1 do
            term.setCursorPos(x, y + row)
            term.setBackgroundColor(pickColor(colors.gray, colors.black))
            term.setTextColor(colors.white)
            term.write(string.rep(" ", boxW))
        end

        term.setCursorPos(x + 2, y + 1)
        term.write(message:sub(1, boxW - 4))

        local yesText = " " .. yesLabel .. " "
        local noText = " " .. noLabel .. " "
        by = y + 3

        yx1 = x + 2
        term.setCursorPos(yx1, by)
        term.setBackgroundColor(pickColor(colors.green, colors.white))
        term.setTextColor(pickColor(colors.white, colors.black))
        term.write(yesText)
        yx2 = yx1 + #yesText - 1

        nx1 = yx2 + 3
        term.setCursorPos(nx1, by)
        term.setBackgroundColor(pickColor(colors.red, colors.black))
        term.setTextColor(colors.white)
        term.write(noText)
        nx2 = nx1 + #noText - 1

        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    draw()

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "mouse_click" then
            local px, py = p2, p3
            if py == by and px >= yx1 and px <= yx2 then
                return true
            elseif py == by and px >= nx1 and px <= nx2 then
                return false
            end
        elseif event == "key" then
            if p1 == keys.y or p1 == keys.enter then
                return true
            elseif p1 == keys.n or p1 == keys.escape then
                return false
            end
        elseif event == "term_resize" then
            w, h = term.getSize()
            x = math.max(1, math.floor((w - boxW) / 2) + 1)
            y = math.max(1, math.floor((h - boxH) / 2) + 1)
            draw()
        end
    end
end

return dialog
