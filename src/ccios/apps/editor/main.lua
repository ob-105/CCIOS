-- CCIOS Text Editor
-- A normal CraftOS program (see docs/ARCHITECTURE.md). Edits any plain
-- text file - opened either from the Start menu (blank, untitled) or
-- from the File Explorer's "Edit" menu action, which passes the file
-- path as a launch argument.

local path = ...

local EXPLORER_ENTRY = "/ccios/apps/explorer/main.lua"

local dialogOk, dialog = pcall(dofile, "/ccios/kernel/dialog.lua")
if not dialogOk then
    dialog = nil
end

local isColor = term.isColor and term.isColor() or false
local function pickColor(colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

-- ---------------------------------------------------------------------
-- Buffer
-- ---------------------------------------------------------------------

local lines = { "" }
local modified = false

if path and fs.exists(path) and not fs.isDir(path) then
    local f = fs.open(path, "r")
    if f then
        local content = f.readAll() or ""
        f.close()
        lines = {}
        for line in (content .. "\n"):gmatch("(.-)\n") do
            table.insert(lines, line)
        end
        if #lines == 0 then
            lines = { "" }
        end
    end
end

local cursorRow, cursorCol = 1, 1
local scrollTop, scrollLeft = 1, 0
local status = nil
local ctrlHeld = false

local CONTENT_TOP = 2

local function currentLine()
    return lines[cursorRow] or ""
end

-- Set while a Save As picker window is open for this buffer, so the
-- "ccios_save_dialog_result" event this coroutine eventually receives
-- (broadcast, see wm.lua's event routing) can be matched back to this
-- request rather than some other Editor window's.
local pickerRequestId = nil

local function writeToPath(p)
    local content = table.concat(lines, "\n")
    local f = fs.open(p, "w")
    if not f then
        status = "Save failed: could not open " .. p
        return false
    end
    f.write(content)
    f.close()
    modified = false
    status = "Saved " .. p
    return true
end

-- Opens the File Explorer as a "Save As" picker: browse to any folder,
-- click Save, type a name. See docs/ARCHITECTURE.md for why the result
-- comes back as a queued event rather than a callback function.
local function requestSaveAs()
    if not (_G.ccios and _G.ccios.launch) then
        status = "Can't open Save As outside CCIOS"
        return
    end
    pickerRequestId = tostring({})
    local suggested = (path and fs.getName and fs.getName(path)) or "untitled.txt"
    local ok, err = pcall(_G.ccios.launch, {
        id = "saveas:" .. pickerRequestId, name = "Save As", entry = EXPLORER_ENTRY,
        width = 46, height = 18, args = { "save", pickerRequestId, suggested },
    })
    if not ok then
        status = "Could not open Save As: " .. tostring(err)
        pickerRequestId = nil
    else
        status = "Choose a location in the Save As window"
    end
end

local function save()
    if not path then
        requestSaveAs()
        return
    end
    writeToPath(path)
end

-- Returns true if it's fine to close (no unsaved changes, or the user
-- confirmed they don't care).
local function confirmClose()
    if not modified then
        return true
    end
    if not dialog then
        return true -- no dialog available; don't block closing over it
    end
    return dialog.confirm("Unsaved changes. Close without saving?")
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local saveBtnX1, saveBtnX2, closeBtnX1, closeBtnX2

local function draw()
    local w, h = term.getSize()
    local contentBottom = h - 1
    local visibleRows = math.max(0, contentBottom - CONTENT_TOP + 1)

    -- keep cursor on screen
    if cursorRow < scrollTop then
        scrollTop = cursorRow
    end
    if cursorRow > scrollTop + visibleRows - 1 then
        scrollTop = cursorRow - visibleRows + 1
    end
    if scrollTop < 1 then
        scrollTop = 1
    end
    if cursorCol < scrollLeft + 1 then
        scrollLeft = cursorCol - 1
    end
    if cursorCol > scrollLeft + w then
        scrollLeft = cursorCol - w
    end
    if scrollLeft < 0 then
        scrollLeft = 0
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    -- header
    local title = "Text Editor - " .. (path or "untitled") .. (modified and " *" or "")
    term.setCursorPos(2, 1)
    term.write(title:sub(1, math.max(0, w - 14)))

    local saveLabel, closeLabel = " Save ", " Close "
    closeBtnX2 = w
    closeBtnX1 = w - #closeLabel + 1
    saveBtnX2 = closeBtnX1 - 2
    saveBtnX1 = saveBtnX2 - #saveLabel + 1

    term.setCursorPos(saveBtnX1, 1)
    term.setBackgroundColor(pickColor(colors.green, colors.black))
    term.setTextColor(colors.white)
    term.write(saveLabel)

    term.setCursorPos(closeBtnX1, 1)
    term.setBackgroundColor(pickColor(colors.red, colors.black))
    term.setTextColor(colors.white)
    term.write(closeLabel)
    term.setBackgroundColor(colors.black)

    -- content
    for row = 1, visibleRows do
        local lineIndex = scrollTop + row - 1
        local y = CONTENT_TOP + row - 1
        term.setCursorPos(1, y)
        local line = lines[lineIndex]
        if line then
            term.write(line:sub(scrollLeft + 1, scrollLeft + w))
        end
    end

    -- status
    term.setCursorPos(1, h)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    local help = status or ("Ctrl+S: Save   Line %d/%d"):format(cursorRow, #lines)
    term.write(help:sub(1, w))
    term.setTextColor(colors.white)

    local screenX = cursorCol - scrollLeft
    local screenY = CONTENT_TOP + (cursorRow - scrollTop)
    if screenX >= 1 and screenX <= w and screenY >= CONTENT_TOP and screenY <= contentBottom then
        term.setCursorPos(screenX, screenY)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

-- ---------------------------------------------------------------------
-- Editing
-- ---------------------------------------------------------------------

local function insertChar(ch)
    local line = currentLine()
    lines[cursorRow] = line:sub(1, cursorCol - 1) .. ch .. line:sub(cursorCol)
    cursorCol = cursorCol + 1
    modified = true
    status = nil
end

local function insertNewline()
    local line = currentLine()
    local before = line:sub(1, cursorCol - 1)
    local after = line:sub(cursorCol)
    lines[cursorRow] = before
    table.insert(lines, cursorRow + 1, after)
    cursorRow = cursorRow + 1
    cursorCol = 1
    modified = true
    status = nil
end

local function backspace()
    if cursorCol > 1 then
        local line = currentLine()
        lines[cursorRow] = line:sub(1, cursorCol - 2) .. line:sub(cursorCol)
        cursorCol = cursorCol - 1
        modified = true
        status = nil
    elseif cursorRow > 1 then
        local prevLen = #lines[cursorRow - 1]
        lines[cursorRow - 1] = lines[cursorRow - 1] .. lines[cursorRow]
        table.remove(lines, cursorRow)
        cursorRow = cursorRow - 1
        cursorCol = prevLen + 1
        modified = true
        status = nil
    end
end

local function deleteForward()
    local line = currentLine()
    if cursorCol <= #line then
        lines[cursorRow] = line:sub(1, cursorCol - 1) .. line:sub(cursorCol + 1)
        modified = true
        status = nil
    elseif cursorRow < #lines then
        lines[cursorRow] = line .. lines[cursorRow + 1]
        table.remove(lines, cursorRow + 1)
        modified = true
        status = nil
    end
end

local function moveUp()
    if cursorRow > 1 then
        cursorRow = cursorRow - 1
        cursorCol = math.min(cursorCol, #lines[cursorRow] + 1)
    end
end

local function moveDown()
    if cursorRow < #lines then
        cursorRow = cursorRow + 1
        cursorCol = math.min(cursorCol, #lines[cursorRow] + 1)
    end
end

local function moveLeft()
    if cursorCol > 1 then
        cursorCol = cursorCol - 1
    elseif cursorRow > 1 then
        cursorRow = cursorRow - 1
        cursorCol = #lines[cursorRow] + 1
    end
end

local function moveRight()
    if cursorCol <= #currentLine() then
        cursorCol = cursorCol + 1
    elseif cursorRow < #lines then
        cursorRow = cursorRow + 1
        cursorCol = 1
    end
end

-- ---------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------

local function handleKey(key)
    if key == keys.leftCtrl or key == keys.rightCtrl then
        ctrlHeld = true
    elseif ctrlHeld and key == keys.s then
        save()
    elseif key == keys.up then
        moveUp()
    elseif key == keys.down then
        moveDown()
    elseif key == keys.left then
        moveLeft()
    elseif key == keys.right then
        moveRight()
    elseif key == keys.home then
        cursorCol = 1
    elseif key == keys["end"] then
        cursorCol = #currentLine() + 1
    elseif key == keys.enter then
        insertNewline()
    elseif key == keys.backspace then
        backspace()
    elseif key == keys.delete then
        deleteForward()
    end
end

local function handleKeyUp(key)
    if key == keys.leftCtrl or key == keys.rightCtrl then
        ctrlHeld = false
    end
end

local closing = false

local function handleClick(px, py)
    local w, h = term.getSize()
    if py == 1 then
        if px >= saveBtnX1 and px <= saveBtnX2 then
            save()
        elseif px >= closeBtnX1 and px <= closeBtnX2 then
            closing = confirmClose()
        end
        return
    end
    if py >= CONTENT_TOP and py <= h - 1 then
        local lineIndex = scrollTop + (py - CONTENT_TOP)
        if lines[lineIndex] then
            cursorRow = lineIndex
            cursorCol = math.min(#lines[lineIndex] + 1, scrollLeft + px)
            status = nil
        end
    end
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

draw()

-- Returning from this file ends the app's coroutine; the WM notices it
-- went dead and closes the window on its own (see wm:resumeWindow) -
-- no separate "close myself" API needed.
while not closing do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "char" then
        insertChar(p1)
    elseif event == "key" then
        handleKey(p1)
    elseif event == "key_up" then
        handleKeyUp(p1)
    elseif event == "mouse_click" then
        handleClick(p2, p3)
    elseif event == "ccios_save_dialog_result" and pickerRequestId and p1 == pickerRequestId then
        pickerRequestId = nil
        if p2 then
            path = p2
            writeToPath(path)
        else
            status = "Save As cancelled"
        end
    end

    if not closing then
        draw()
    end
end
