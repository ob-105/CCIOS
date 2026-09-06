-- CCIOS System Monitor
-- A normal CraftOS program (see docs/ARCHITECTURE.md for why apps can
-- just be that). Reads a small read-only info surface the kernel
-- exposes at _G.ccios (see boot.lua) plus a few standard CC APIs, and
-- shows disk usage, an approximation of how close the computer is to
-- CraftOS's "too long without yielding" watchdog, and other general
-- system stats. Refreshes once a second and on resize.

local WATCHDOG_BUDGET_S = 7 -- CraftOS's approx default "too long without yielding" limit

local function formatBytes(n)
    if n >= 1024 * 1024 then
        return ("%.1fMB"):format(n / 1024 / 1024)
    elseif n >= 1024 then
        return ("%.1fKB"):format(n / 1024)
    end
    return n .. "B"
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return ("%dh %dm %ds"):format(h, m, s)
    elseif m > 0 then
        return ("%dm %ds"):format(m, s)
    end
    return ("%ds"):format(s)
end

local function bar(fraction, width)
    fraction = math.max(0, math.min(1, fraction))
    local filled = math.floor(fraction * width + 0.5)
    return "[" .. string.rep("=", filled) .. string.rep(" ", width - filled) .. "]"
end

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    local y = 0
    local function line(text, color)
        y = y + 1
        if y > h then
            return
        end
        term.setCursorPos(2, y)
        if color then
            term.setTextColor(color)
        end
        term.write((text or ""):sub(1, math.max(0, w - 2)))
        term.setTextColor(colors.white)
    end

    local barWidth = math.max(4, math.min(20, w - 8))
    local wmInfo = _G.ccios and _G.ccios.wm

    line("System Monitor", colors.white)
    line(string.rep("-", math.min(w - 2, 20)))

    -- Disk usage
    line("")
    local free = fs.getFreeSpace("/")
    local capacity = fs.getCapacity and fs.getCapacity("/") or nil
    if capacity and capacity > 0 then
        local used = capacity - free
        local frac = used / capacity
        line(("Disk: %s / %s"):format(formatBytes(used), formatBytes(capacity)))
        line(("%s %d%%"):format(bar(frac, barWidth), math.floor(frac * 100 + 0.5)))
    else
        line(("Disk free: %s (no capacity limit)"):format(formatBytes(free)))
    end

    -- Watchdog / "instruction limit" approximation. CraftOS doesn't
    -- expose a real instruction/time budget to Lua scripts; this times
    -- how long the window manager's own dispatch+draw took between
    -- yields, which is the closest available proxy for how close the
    -- whole computer is coming to being killed for running too long.
    line("")
    if wmInfo then
        local maxMs = wmInfo.stats.maxBurst * 1000
        local lastMs = wmInfo.stats.lastBurst * 1000
        local frac = wmInfo.stats.maxBurst / WATCHDOG_BUDGET_S
        line(("Watchdog headroom (worst seen):"))
        line(("%s %d%% of ~%ds"):format(bar(frac, barWidth), math.floor(frac * 100 + 0.5), WATCHDOG_BUDGET_S))
        line(("last: %.0fms (approx; often reads 0)"):format(lastMs))
    else
        line("Watchdog headroom: unavailable (not running under CCIOS WM)")
    end

    -- Memory
    line("")
    local memOk, memKb = pcall(collectgarbage, "count")
    if memOk and type(memKb) == "number" then
        line(("Lua memory in use: %.1f KB"):format(memKb))
    end

    -- CCIOS-level stats
    if wmInfo then
        line(("Open windows: %d"):format(#wmInfo.windows))
        line(("Installed apps: %d"):format(#wmInfo.startMenuApps))
    end

    -- Peripherals
    if peripheral then
        local names = peripheral.getNames()
        line(("Peripherals attached: %d"):format(#names))
    end

    -- General device info
    line("")
    line(("Uptime: %s"):format(formatDuration(os.clock())))
    local id = os.getComputerID and os.getComputerID() or -1
    line(("Computer #%d  CraftOS %s"):format(id, tostring(os.version and os.version() or "unknown")))
    line(("Screen: %dx%d  Color: %s"):format(w, h, tostring(term.isColor and term.isColor() or false)))
end

draw()

local refreshTimer = os.startTimer(1)
while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == refreshTimer then
        draw()
        refreshTimer = os.startTimer(1)
    elseif event == "term_resize" then
        draw()
    end
end
