-- CCIOS File Explorer
-- A normal CraftOS program (see docs/ARCHITECTURE.md). Browses the
-- filesystem, launches .lua files as windows via _G.ccios.launch (the
-- same cascaded/clamped placement the Start menu uses), opens any file
-- in the Text Editor via the Menu dropdown, supports copy/cut/paste,
-- delete, new file/folder (cut, delete, and overwriting all confirm
-- first via the shared dialog helper), accepts files dragged onto the
-- Minecraft window (the "file_transfer" event) into whatever directory
-- is currently open, and can run as a "Save As" picker for the Text
-- Editor (see the "Save As picker mode" section below).

local EDITOR_ENTRY = "/ccios/apps/editor/main.lua"

-- pickerMode == "save" when launched by the Text Editor to pick a save
-- location; see "Save As picker mode" below.
local pickerMode, pickerRequestId, pickerSuggestedName = ...

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

local function joinPath(base, name)
    if base == "/" then
        return "/" .. name
    end
    return base .. "/" .. name
end

local function parentPath(path)
    if path == "/" then
        return "/"
    end
    local trimmed = path:match("^(.*)/[^/]+$")
    if not trimmed or trimmed == "" then
        return "/"
    end
    return trimmed
end

local function listDir(path)
    local ok, names = pcall(fs.list, path)
    if not ok then
        return {}
    end

    local dirs, files = {}, {}
    for _, name in ipairs(names) do
        local full = joinPath(path, name)
        if fs.isDir(full) then
            table.insert(dirs, name)
        else
            table.insert(files, name)
        end
    end
    table.sort(dirs)
    table.sort(files)

    local entries = {}
    if path ~= "/" then
        table.insert(entries, { name = "..", isDir = true, isParent = true })
    end
    for _, n in ipairs(dirs) do
        table.insert(entries, { name = n, isDir = true })
    end
    for _, n in ipairs(files) do
        table.insert(entries, { name = n, isDir = false })
    end
    return entries
end

local function promptText(label, default)
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h)
    term.write(label)
    term.setCursorBlink(true)
    local text = read(nil, nil, nil, default)
    term.setCursorBlink(false)
    return text
end

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------

local currentPath = "/"
local entries = listDir(currentPath)
local selected = #entries > 0 and 1 or 0
local scroll = 0
local status = pickerMode == "save" and "Choose a folder, then click Save" or nil
local lastClick = nil -- { index=, time= } for double-click detection
local lastSelectedFileName = nil -- prefill hint for the save-as filename prompt
local clipboard = nil -- { path=, name=, isDir=, mode="copy"|"cut" }
local closing = false

local menuOpen = false
local menuItems = {}
local menuButtonX1, menuButtonX2
local saveBtnX1, saveBtnX2, cancelBtnX1, cancelBtnX2
local menuX1, menuY1, menuX2, menuY2

local LIST_TOP = 4 -- row the file list starts on (below title, path, separator)

local function refresh()
    entries = listDir(currentPath)
    selected = #entries > 0 and math.min(selected > 0 and selected or 1, #entries) or 0
    scroll = 0
    status = nil
end

local function getLayout()
    local w, h = term.getSize()
    local listBottom = h - 1 -- last row reserved for status/help text
    local visibleRows = math.max(0, listBottom - LIST_TOP + 1)
    return w, h, listBottom, visibleRows
end

local function clampScroll()
    local _, _, _, visibleRows = getLayout()
    if selected < 1 then
        return
    end
    if selected - scroll > visibleRows then
        scroll = selected - visibleRows
    end
    if selected <= scroll then
        scroll = selected - 1
    end
    if scroll < 0 then
        scroll = 0
    end
end

-- ---------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------

local function runLuaFile(full, name)
    if _G.ccios and _G.ccios.launch then
        -- a broken .lua file (syntax error, etc.) would otherwise error
        -- out of this coroutine and crash the whole Explorer window;
        -- pcall keeps that contained to a status message
        local ok, err = pcall(_G.ccios.launch, {
            id = "file:" .. full, name = name, entry = full, width = 40, height = 14,
        })
        status = ok and ("Launched " .. name) or ("Could not launch: " .. tostring(err))
    else
        status = "Can't launch programs outside CCIOS"
    end
end

local function launchEditor(full, name)
    if _G.ccios and _G.ccios.launch then
        local ok, err = pcall(_G.ccios.launch, {
            id = "editor:" .. full, name = "Edit: " .. name, entry = EDITOR_ENTRY,
            width = 54, height = 18, args = { full },
        })
        status = ok and ("Editing " .. name) or ("Could not open editor: " .. tostring(err))
    else
        status = "Can't launch programs outside CCIOS"
    end
end

local function openEntry(index)
    local e = entries[index]
    if not e then
        return
    end

    if e.isParent then
        currentPath = parentPath(currentPath)
        refresh()
        return
    end

    local full = joinPath(currentPath, e.name)
    if e.isDir then
        currentPath = full
        refresh()
    elseif e.name:match("%.lua$") then
        runLuaFile(full, e.name)
    else
        status = "No viewer for this file type yet - try Menu > Edit"
    end
end

local function doCopy(full, name, isDir)
    clipboard = { path = full, name = name, isDir = isDir, mode = "copy" }
    status = "Copied " .. name .. " (paste elsewhere)"
end

local function doCut(full, name, isDir)
    if not dialog then
        status = "Cut unavailable (dialog helper missing)"
        return
    end
    local ok = dialog.confirm(("Cut '%s'? It will be moved when you paste."):format(name))
    if ok then
        clipboard = { path = full, name = name, isDir = isDir, mode = "cut" }
        status = "Cut " .. name .. " (paste elsewhere to move it)"
    else
        status = "Cancelled"
    end
end

local function doDelete(full, name)
    if not dialog then
        status = "Delete unavailable (dialog helper missing)"
        return
    end
    local ok = dialog.confirm(("Delete '%s'? This cannot be undone."):format(name))
    if ok then
        fs.delete(full)
        if clipboard and clipboard.path == full then
            clipboard = nil
        end
        refresh()
        status = "Deleted " .. name
    else
        status = "Cancelled"
    end
end

local function doPaste()
    if not clipboard then
        status = "Nothing to paste"
        return
    end
    local dest = joinPath(currentPath, clipboard.name)
    if dest == clipboard.path then
        status = "Already here"
        return
    end
    if fs.exists(dest) then
        if not dialog then
            status = "Paste unavailable (dialog helper missing)"
            return
        end
        if not dialog.confirm(("Overwrite existing '%s'?"):format(clipboard.name)) then
            status = "Cancelled"
            return
        end
        fs.delete(dest)
    end

    local ok, err
    if clipboard.mode == "cut" then
        ok, err = pcall(fs.move, clipboard.path, dest)
    else
        ok, err = pcall(fs.copy, clipboard.path, dest)
    end

    if ok then
        local pastedName = clipboard.name
        if clipboard.mode == "cut" then
            clipboard = nil
        end
        refresh()
        status = "Pasted " .. pastedName
    else
        status = "Paste failed: " .. tostring(err)
    end
end

local function doNewFile()
    local name = promptText("New file name: ", "")
    if not name or name == "" then
        status = "Cancelled"
        return
    end
    local full = joinPath(currentPath, name)
    if fs.exists(full) then
        status = "Already exists: " .. name
        return
    end
    local f = fs.open(full, "w")
    if not f then
        status = "Could not create " .. name
        return
    end
    f.close()
    refresh()
    status = "Created " .. name
end

local function doNewFolder()
    local name = promptText("New folder name: ", "")
    if not name or name == "" then
        status = "Cancelled"
        return
    end
    local full = joinPath(currentPath, name)
    if fs.exists(full) then
        status = "Already exists: " .. name
        return
    end
    fs.makeDir(full)
    refresh()
    status = "Created folder " .. name
end

local function buildMenuItems()
    local items = {}
    local e = selected >= 1 and entries[selected] or nil

    if e and not e.isParent then
        local full = joinPath(currentPath, e.name)
        if e.isDir then
            table.insert(items, { label = "Open", action = function() openEntry(selected) end })
        elseif e.name:match("%.lua$") then
            table.insert(items, { label = "Run", action = function() runLuaFile(full, e.name) end })
        end
        if not e.isDir then
            table.insert(items, { label = "Edit", action = function() launchEditor(full, e.name) end })
        end
        table.insert(items, { label = "Copy", action = function() doCopy(full, e.name, e.isDir) end })
        table.insert(items, { label = "Cut", action = function() doCut(full, e.name, e.isDir) end })
        table.insert(items, { label = "Delete", action = function() doDelete(full, e.name) end })
    end

    if clipboard then
        table.insert(items, { label = "Paste", action = doPaste })
    end

    table.insert(items, { label = "New File", action = doNewFile })
    table.insert(items, { label = "New Folder", action = doNewFolder })

    return items
end

-- ---------------------------------------------------------------------
-- Save As picker mode
--
-- The Text Editor, when saving a buffer with no path yet, launches this
-- same app with args {"save", requestId, suggestedName} instead of a
-- normal window. Browsing works exactly as normal, but the Menu button
-- (and everything it offers, including New Folder) is hidden in this
-- mode - clicking [Save] prompts for a filename and, once confirmed,
-- reports the chosen path back to the Editor and closes.
--
-- The result travels back via os.queueEvent rather than calling a
-- function the Editor passed in directly: this coroutine and the
-- Editor's are resumed independently by the WM, each with `term`
-- redirected to its own window, so directly invoking a closure that
-- belongs to the Editor's coroutine from inside this one would draw
-- into the wrong window. Queuing a broadcast event instead means the
-- Editor updates its own state and redraws itself, on its own
-- coroutine, exactly like handling any other event - see
-- docs/ARCHITECTURE.md.
-- ---------------------------------------------------------------------

local function finishSave(name)
    if not name or name == "" then
        status = "Enter a filename"
        return
    end
    local fullPath = joinPath(currentPath, name)
    if fs.exists(fullPath) then
        if not dialog or not dialog.confirm(("Overwrite existing '%s'?"):format(name)) then
            status = "Cancelled"
            return
        end
    end
    os.queueEvent("ccios_save_dialog_result", pickerRequestId, fullPath)
    closing = true
end

local function cancelSave()
    os.queueEvent("ccios_save_dialog_result", pickerRequestId, nil)
    closing = true
end

-- In picker mode, "opening" an entry means picking it (a file) or
-- navigating into it (a folder) - never running/editing.
local function pickerOpenEntry(index)
    local e = entries[index]
    if not e then
        return
    end
    if e.isParent then
        currentPath = parentPath(currentPath)
        refresh()
        return
    end
    if e.isDir then
        currentPath = joinPath(currentPath, e.name)
        refresh()
    else
        finishSave(e.name)
    end
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local function drawMenu()
    if not menuOpen then
        return
    end
    local w = select(1, term.getSize())

    local width = 0
    for _, item in ipairs(menuItems) do
        width = math.max(width, #item.label)
    end
    width = math.min(w, width + 2)

    local x = math.max(1, menuButtonX2 - width + 1)
    local y = 2

    menuX1, menuY1 = x, y
    menuX2, menuY2 = x + width - 1, y + #menuItems - 1

    for i, item in ipairs(menuItems) do
        local ry = y + i - 1
        term.setCursorPos(x, ry)
        term.setBackgroundColor(pickColor(colors.gray, colors.white))
        term.setTextColor(pickColor(colors.white, colors.black))
        local label = (" " .. item.label):sub(1, width)
        term.write(label .. string.rep(" ", width - #label))
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function draw()
    local w, h, listBottom, visibleRows = getLayout()
    clampScroll()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2, 1)
    term.write(pickerMode == "save" and "Save As" or "File Explorer")

    if pickerMode == "save" then
        local saveLabel, cancelLabel = " Save ", " Cancel "
        cancelBtnX2 = w
        cancelBtnX1 = w - #cancelLabel + 1
        saveBtnX2 = cancelBtnX1 - 2
        saveBtnX1 = saveBtnX2 - #saveLabel + 1

        term.setCursorPos(saveBtnX1, 1)
        term.setBackgroundColor(pickColor(colors.green, colors.black))
        term.setTextColor(colors.white)
        term.write(saveLabel)

        term.setCursorPos(cancelBtnX1, 1)
        term.setBackgroundColor(pickColor(colors.red, colors.black))
        term.setTextColor(colors.white)
        term.write(cancelLabel)

        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    else
        local menuLabel = " Menu "
        menuButtonX2 = w
        menuButtonX1 = w - #menuLabel + 1
        term.setCursorPos(menuButtonX1, 1)
        term.setBackgroundColor(menuOpen and pickColor(colors.white, colors.black) or pickColor(colors.blue, colors.black))
        term.setTextColor(menuOpen and pickColor(colors.black, colors.white) or pickColor(colors.white, colors.white))
        term.write(menuLabel)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    term.setCursorPos(2, 2)
    term.write(currentPath:sub(1, math.max(0, w - 2)))

    term.setCursorPos(1, 3)
    term.write(string.rep("-", w))

    for row = 1, visibleRows do
        local index = scroll + row
        local y = LIST_TOP + row - 1
        local e = entries[index]
        term.setCursorPos(1, y)
        if e then
            local isSel = (index == selected)
            local label = e.isDir and ("[" .. e.name .. "]") or e.name
            label = " " .. label
            local bg = isSel and pickColor(colors.blue, colors.black) or colors.black
            local fg
            if isSel then
                fg = pickColor(colors.white, colors.white)
            elseif e.isDir then
                fg = pickColor(colors.yellow, colors.white)
            else
                fg = colors.white
            end
            term.setBackgroundColor(bg)
            term.setTextColor(fg)
            term.write(label:sub(1, w))
            if #label < w then
                term.write(string.rep(" ", w - #label))
            end
            term.setBackgroundColor(colors.black)
        end
    end

    term.setCursorPos(1, h)
    term.setTextColor(pickColor(colors.lightGray, colors.white))
    local help
    if status then
        help = status
    elseif pickerMode == "save" then
        help = "Click a file to select it, or click Save to name a new one"
    else
        help = "Enter/dbl-click: open  Menu: actions  drag a file in to copy it here"
    end
    term.write(help:sub(1, w))
    term.setTextColor(colors.white)

    drawMenu()
end

-- ---------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------

local function handleClick(px, py)
    if pickerMode == "save" and py == 1 then
        if px >= saveBtnX1 and px <= saveBtnX2 then
            local name = promptText("Save as: ", lastSelectedFileName or pickerSuggestedName or "")
            finishSave(name)
        elseif px >= cancelBtnX1 and px <= cancelBtnX2 then
            cancelSave()
        end
        return
    end

    if pickerMode ~= "save" and py == 1 and menuButtonX1 and px >= menuButtonX1 and px <= menuButtonX2 then
        if menuOpen then
            menuOpen = false
        else
            menuItems = buildMenuItems()
            menuOpen = true
        end
        return
    end

    if menuOpen then
        menuOpen = false
        if px >= menuX1 and px <= menuX2 and py >= menuY1 and py <= menuY2 then
            local item = menuItems[py - menuY1 + 1]
            if item and item.action then
                item.action()
            end
        end
        return
    end

    local _, _, listBottom = getLayout()
    if py < LIST_TOP or py > listBottom then
        return
    end
    local index = scroll + (py - LIST_TOP + 1)
    local e = entries[index]
    if not e then
        return
    end

    local now = os.clock()
    if lastClick and lastClick.index == index and (now - lastClick.time) < 0.5 then
        lastClick = nil
        if pickerMode == "save" then
            pickerOpenEntry(index)
        else
            openEntry(index)
        end
    else
        selected = index
        status = nil
        lastClick = { index = index, time = now }
        if pickerMode == "save" and not e.isDir then
            lastSelectedFileName = e.name
        end
    end
end

local function handleKey(key)
    if key == keys.enter then
        if selected >= 1 then
            if pickerMode == "save" then
                pickerOpenEntry(selected)
            else
                openEntry(selected)
            end
        end
    elseif key == keys.backspace then
        if currentPath ~= "/" then
            currentPath = parentPath(currentPath)
            refresh()
        end
    elseif key == keys.up then
        if selected > 1 then
            selected = selected - 1
            status = nil
        end
    elseif key == keys.down then
        if selected < #entries then
            selected = selected + 1
            status = nil
        end
    elseif key == keys.pageUp or key == keys.pageDown then
        local _, _, _, visibleRows = getLayout()
        local delta = (key == keys.pageUp) and -visibleRows or visibleRows
        if #entries > 0 then
            selected = math.max(1, math.min(#entries, selected + delta))
        end
        status = nil
    elseif pickerMode == "save" and key == keys.escape then
        cancelSave()
    end
end

local function handleFileTransfer(transfer)
    local files = transfer.getFiles()
    local count = 0
    for _, file in ipairs(files) do
        local ok, name = pcall(file.getName)
        if ok then
            local readOk, content = pcall(file.readAll)
            pcall(file.close)
            if readOk and content then
                local dest = joinPath(currentPath, name)
                local out = fs.open(dest, "w")
                if out then
                    out.write(content)
                    out.close()
                    count = count + 1
                end
            end
        end
    end
    refresh()
    status = ("Received %d file(s) into %s"):format(count, currentPath)
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

draw()

while not closing do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "mouse_click" then
        handleClick(p2, p3)
    elseif event == "key" then
        handleKey(p1)
    elseif event == "file_transfer" then
        handleFileTransfer(p1)
    elseif event == "term_resize" then
        -- layout may have changed; nothing else to do, draw() handles it
    end

    if not closing then
        draw()
    end
end
