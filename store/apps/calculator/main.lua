-- CCIOS Calculator
-- A normal CraftOS program (see docs/ARCHITECTURE.md). A simple
-- four-function calculator - not part of core CCIOS, installed on
-- demand through the App Store, which is why it lives under
-- store/apps/ in the repo rather than src/ccios/apps/.

local isColor = term.isColor and term.isColor() or false
local function pickColor(colorValue, monoValue)
    if isColor then
        return colorValue
    end
    return monoValue
end

local display = "0"
local stored = nil     -- left-hand operand, once an operator is pressed
local pendingOp = nil  -- "+", "-", "*", "/"
local justEvaluated = false

local BUTTONS = {
    { "7", "8", "9", "/" },
    { "4", "5", "6", "*" },
    { "1", "2", "3", "-" },
    { "C", "0", "=", "+" },
}

local buttonRegions = {} -- [y] = { {x1=,x2=,label=}, ... }

local function apply(a, op, b)
    if op == "+" then return a + b end
    if op == "-" then return a - b end
    if op == "*" then return a * b end
    if op == "/" then return b ~= 0 and a / b or 0 end
    return b
end

local function formatNumber(n)
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return tostring(math.floor(n))
    end
    return ("%.10g"):format(n)
end

local function pressDigit(d)
    if justEvaluated then
        display = d
        justEvaluated = false
    elseif display == "0" then
        display = d
    else
        display = display .. d
    end
end

local function pressOp(op)
    if stored and pendingOp and not justEvaluated then
        stored = apply(stored, pendingOp, tonumber(display))
        display = formatNumber(stored)
    else
        stored = tonumber(display)
    end
    pendingOp = op
    justEvaluated = true -- next digit starts a fresh number
end

local function pressEquals()
    if stored and pendingOp then
        local result = apply(stored, pendingOp, tonumber(display))
        display = formatNumber(result)
        stored = nil
        pendingOp = nil
    end
    justEvaluated = true
end

local function pressClear()
    display = "0"
    stored = nil
    pendingOp = nil
    justEvaluated = false
end

local function pressButton(label)
    if label == "C" then
        pressClear()
    elseif label == "=" then
        pressEquals()
    elseif label:match("[%+%-%*/]") then
        pressOp(label)
    else
        pressDigit(label)
    end
end

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setCursorPos(2, 1)
    term.write("Calculator")

    -- display
    term.setCursorPos(2, 3)
    term.setBackgroundColor(pickColor(colors.gray, colors.white))
    term.setTextColor(pickColor(colors.white, colors.black))
    local shown = display:sub(1, math.max(1, w - 4))
    term.write(string.rep(" ", w - 4))
    term.setCursorPos(math.max(2, 2 + (w - 4) - #shown), 3)
    term.write(shown)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    buttonRegions = {}
    local startY = 5
    for row, labels in ipairs(BUTTONS) do
        local y = startY + row - 1
        buttonRegions[y] = {}
        local x = 2
        for _, label in ipairs(labels) do
            term.setCursorPos(x, y)
            term.setBackgroundColor(pickColor(colors.blue, colors.black))
            term.setTextColor(colors.white)
            term.write(" " .. label .. " ")
            table.insert(buttonRegions[y], { x1 = x, x2 = x + 2, label = label })
            x = x + 4
        end
    end
    term.setBackgroundColor(colors.black)
end

local function handleClick(px, py)
    local row = buttonRegions[py]
    if not row then
        return
    end
    for _, btn in ipairs(row) do
        if px >= btn.x1 and px <= btn.x2 then
            pressButton(btn.label)
            return
        end
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
