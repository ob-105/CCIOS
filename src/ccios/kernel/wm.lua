-- CCIOS Window Manager
-- Runs floating, draggable app windows on top of a shared terminal.
-- Apps are ordinary CraftOS programs: they use term.* / os.pullEvent
-- like any normal program would. The WM redirects `term` to the app's
-- own window buffer before resuming it, and translates screen-space
-- input events into window-local coordinates before delivering them.

local wm = {}
wm.__index = wm

-- Picks a color-safe value: falls back to mono-friendly colors on
-- basic (non-color) computers and pocket computers.
local function pickColor(isColor, colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

function wm.new(nativeTerm)
    nativeTerm = nativeTerm or term.current()
    local screenW, screenH = nativeTerm.getSize()

    local self = setmetatable({}, wm)
    self.nativeTerm = nativeTerm
    self.isColor = nativeTerm.isColor and nativeTerm.isColor() or false
    self.screenW = screenW
    self.screenH = screenH
    self.taskbarY = screenH
    self.windows = {}        -- ordered back-to-front; last = topmost/focused
    self.nextId = 1
    self.running = false
    self.activeMouseWindow = nil -- window currently owning a mouse_click..mouse_up drag
    self.chromeDrag = nil        -- {window=, offsetX=, offsetY=} when dragging a titlebar
    return self
end

-- ---------------------------------------------------------------------
-- Window lifecycle
-- ---------------------------------------------------------------------

-- Launches `path` (a normal CraftOS program file) inside a new window.
function wm:launch(path, title, x, y, w, h, ...)
    local ok, fn = pcall(loadfile, path)
    if not ok or fn == nil then
        error(("CCIOS: could not load app '%s': %s"):format(path, tostring(fn)))
    end

    local args = { ... }
    local contentH = math.max(1, h - 1)
    local win = window.create(self.nativeTerm, x, y + 1, w, contentH, false)

    local entry = {
        id = self.nextId,
        title = title or "Untitled",
        x = x, y = y, w = w, h = h,
        win = win,
        filter = nil,
        minimized = false,
        dead = false,
        co = coroutine.create(function()
            fn(table.unpack(args))
        end),
    }
    self.nextId = self.nextId + 1

    table.insert(self.windows, entry)
    self:focus(entry)
    self:resumeWindow(entry) -- prime the coroutine so it can request its first event
    self:draw()
    return entry
end

function wm:closeWindow(entry)
    for i, w in ipairs(self.windows) do
        if w == entry then
            table.remove(self.windows, i)
            break
        end
    end
    if self.activeMouseWindow == entry then
        self.activeMouseWindow = nil
    end
end

-- Moves a window to the top of the z-order and marks it focused.
function wm:focus(entry)
    for i, w in ipairs(self.windows) do
        if w == entry then
            table.remove(self.windows, i)
            break
        end
    end
    table.insert(self.windows, entry)
    entry.minimized = false
end

function wm:focused()
    return self.windows[#self.windows]
end

-- ---------------------------------------------------------------------
-- Coroutine plumbing
-- ---------------------------------------------------------------------

-- Resumes an app's coroutine with the given event, redirecting `term`
-- to its window buffer for the duration of the resume.
function wm:resumeWindow(entry, event, a, b, c, d)
    if entry.dead or coroutine.status(entry.co) == "dead" then
        return
    end

    local prev = term.redirect(entry.win)
    local ok, result = coroutine.resume(entry.co, event, a, b, c, d)
    term.redirect(prev)

    if not ok then
        entry.dead = true
        if result ~= "Terminated" then
            entry.crashMessage = result
        end
    elseif coroutine.status(entry.co) == "dead" then
        entry.dead = true
    else
        -- `result` is whatever filter the app passed to os.pullEvent(filter)
        entry.filter = result
    end
end

local function matchesFilter(entry, eventName)
    return entry.filter == nil or entry.filter == eventName
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local function fillRow(t, x, y, w, bg)
    t.setCursorPos(x, y)
    t.setBackgroundColor(bg)
    t.write(string.rep(" ", w))
end

function wm:drawWindowChrome(entry, isFocused)
    local t = self.nativeTerm
    local titleBg = pickColor(self.isColor,
        isFocused and colors.blue or colors.gray,
        isFocused and colors.black or colors.white)
    local titleFg = pickColor(self.isColor, colors.white, isFocused and colors.white or colors.black)

    fillRow(t, entry.x, entry.y, entry.w, titleBg)
    t.setTextColor(titleFg)
    t.setCursorPos(entry.x + 1, entry.y)
    local label = entry.title
    local maxLabelW = entry.w - 3
    if #label > maxLabelW then
        label = label:sub(1, math.max(0, maxLabelW))
    end
    t.write(label)

    -- close button
    t.setCursorPos(entry.x + entry.w - 1, entry.y)
    t.setBackgroundColor(pickColor(self.isColor, colors.red, colors.black))
    t.setTextColor(pickColor(self.isColor, colors.white, colors.white))
    t.write("x")
end

function wm:drawTaskbar()
    local t = self.nativeTerm
    local bg = pickColor(self.isColor, colors.lightGray, colors.white)
    local fg = pickColor(self.isColor, colors.black, colors.black)
    fillRow(t, 1, self.taskbarY, self.screenW, bg)
    t.setTextColor(fg)
    t.setCursorPos(1, self.taskbarY)
    t.write(" CCIOS")

    local cx = 8
    if self.onNewWindow then
        t.setCursorPos(cx, self.taskbarY)
        t.setBackgroundColor(pickColor(self.isColor, colors.green, colors.black))
        t.setTextColor(pickColor(self.isColor, colors.white, colors.white))
        t.write(" + ")
        self.newWindowX1 = cx
        self.newWindowX2 = cx + 2
        cx = cx + 4
    else
        self.newWindowX1 = nil
        self.newWindowX2 = nil
    end

    for _, entry in ipairs(self.windows) do
        if cx < self.screenW then
            local isFocused = (entry == self:focused()) and not entry.minimized
            t.setCursorPos(cx, self.taskbarY)
            t.setBackgroundColor(isFocused and pickColor(self.isColor, colors.white, colors.black) or bg)
            t.setTextColor(isFocused and pickColor(self.isColor, colors.black, colors.white) or fg)
            local label = " " .. entry.title:sub(1, 12) .. " "
            t.write(label)
            entry.taskbarX1 = cx
            entry.taskbarX2 = cx + #label - 1
            cx = cx + #label + 1
        end
    end
end

function wm:draw()
    local t = self.nativeTerm
    t.setBackgroundColor(pickColor(self.isColor, colors.cyan, colors.black))
    t.setTextColor(pickColor(self.isColor, colors.white, colors.white))
    t.clear()

    for _, entry in ipairs(self.windows) do
        if not entry.minimized then
            self:drawWindowChrome(entry, entry == self:focused())
            entry.win.setVisible(true)
            entry.win.redraw()
        end
    end

    self:drawTaskbar()
    t.setCursorBlink(false)
end

-- ---------------------------------------------------------------------
-- Hit testing
-- ---------------------------------------------------------------------

local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w - 1 and py >= y and py <= y + h - 1
end

-- Returns topmost window under (px, py), or nil.
function wm:windowAt(px, py)
    for i = #self.windows, 1, -1 do
        local entry = self.windows[i]
        if not entry.minimized and pointInRect(px, py, entry.x, entry.y, entry.w, entry.h) then
            return entry
        end
    end
    return nil
end

-- ---------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------

function wm:handleMouseClick(button, px, py)
    if py == self.taskbarY then
        if self.newWindowX1 and px >= self.newWindowX1 and px <= self.newWindowX2 then
            if self.onNewWindow then
                self.onNewWindow(self)
            end
            return
        end
        for _, entry in ipairs(self.windows) do
            if entry.taskbarX1 and px >= entry.taskbarX1 and px <= entry.taskbarX2 then
                if entry == self:focused() and not entry.minimized then
                    entry.minimized = true
                else
                    self:focus(entry)
                end
                return
            end
        end
        return
    end

    local entry = self:windowAt(px, py)
    if not entry then
        return
    end

    self:focus(entry)

    if py == entry.y then
        if px == entry.x + entry.w - 1 then
            self:closeWindow(entry)
        else
            self.chromeDrag = { entry = entry, offsetX = px - entry.x, offsetY = py - entry.y }
        end
        return
    end

    -- content click: translate to window-local space and deliver
    self.activeMouseWindow = entry
    local localX = px - entry.x + 1
    local localY = py - entry.y
    if matchesFilter(entry, "mouse_click") then
        self:resumeWindow(entry, "mouse_click", button, localX, localY)
    end
end

function wm:handleMouseDrag(button, px, py)
    if self.chromeDrag then
        local d = self.chromeDrag
        local entry = d.entry
        local newX = px - d.offsetX
        local newY = py - d.offsetY
        newX = math.max(1, math.min(newX, self.screenW - entry.w + 1))
        newY = math.max(1, math.min(newY, self.taskbarY - entry.h))
        entry.x, entry.y = newX, newY
        entry.win.reposition(entry.x, entry.y + 1)
        return
    end

    local entry = self.activeMouseWindow
    if entry and matchesFilter(entry, "mouse_drag") then
        local localX = px - entry.x + 1
        local localY = py - entry.y
        self:resumeWindow(entry, "mouse_drag", button, localX, localY)
    end
end

function wm:handleMouseUp(button, px, py)
    if self.chromeDrag then
        self.chromeDrag = nil
        return
    end
    local entry = self.activeMouseWindow
    if entry and matchesFilter(entry, "mouse_up") then
        local localX = px - entry.x + 1
        local localY = py - entry.y
        self:resumeWindow(entry, "mouse_up", button, localX, localY)
    end
    self.activeMouseWindow = nil
end

function wm:handleMouseScroll(dir, px, py)
    local entry = self:windowAt(px, py)
    if entry and matchesFilter(entry, "mouse_scroll") then
        local localX = px - entry.x + 1
        local localY = py - entry.y
        self:resumeWindow(entry, "mouse_scroll", dir, localX, localY)
    end
end

-- ---------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------

local FOCUSED_ONLY = {
    key = true, key_up = true, char = true, paste = true, terminate = true,
}

function wm:dispatch(event, a, b, c, d)
    if event == "mouse_click" then
        self:handleMouseClick(a, b, c)
    elseif event == "mouse_drag" then
        self:handleMouseDrag(a, b, c)
    elseif event == "mouse_up" then
        self:handleMouseUp(a, b, c)
    elseif event == "mouse_scroll" then
        self:handleMouseScroll(a, b, c)
    elseif event == "term_resize" then
        self.screenW, self.screenH = self.nativeTerm.getSize()
        self.taskbarY = self.screenH
        for _, entry in ipairs(self.windows) do
            entry.x = math.min(entry.x, math.max(1, self.screenW - entry.w + 1))
            entry.y = math.min(entry.y, math.max(1, self.taskbarY - entry.h))
            entry.win.reposition(entry.x, entry.y + 1)
        end
    elseif event == "terminate" then
        -- mirrors CraftOS: terminate always interrupts, regardless of
        -- what filter the app's os.pullEvent is currently waiting on
        local entry = self:focused()
        if entry then
            self:resumeWindow(entry, event)
        end
    elseif FOCUSED_ONLY[event] then
        local entry = self:focused()
        if entry and matchesFilter(entry, event) then
            self:resumeWindow(entry, event, a, b, c, d)
        end
    else
        -- broadcast background/system events (timers, redstone, etc.)
        -- iterate over a snapshot since resuming may close windows
        local snapshot = {}
        for i, entry in ipairs(self.windows) do snapshot[i] = entry end
        for _, entry in ipairs(snapshot) do
            if not entry.dead and matchesFilter(entry, event) then
                self:resumeWindow(entry, event, a, b, c, d)
            end
        end
    end

    -- reap dead windows
    for i = #self.windows, 1, -1 do
        if self.windows[i].dead then
            table.remove(self.windows, i)
        end
    end
end

-- Runs the WM loop. Returns when no windows remain.
function wm:run()
    self.running = true
    self:draw()

    while self.running do
        if #self.windows == 0 then
            break
        end
        local event, a, b, c, d = os.pullEventRaw()
        self:dispatch(event, a, b, c, d)
        self:draw()
    end

    self.nativeTerm.setBackgroundColor(colors.black)
    self.nativeTerm.setTextColor(colors.white)
    self.nativeTerm.clear()
    self.nativeTerm.setCursorPos(1, 1)
end

return wm
