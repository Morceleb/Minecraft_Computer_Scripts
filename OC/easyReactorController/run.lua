local component = require("component")
local term = require("term")
local reactor = component.proxy(component.list("reactor_chamber")())
local inv = component.inventory_controller

--初始化全局变量
local reactorSide = 0
local termWidth = 0


-- 查找反应堆方向
local function findreactor()
    for i = 0, 5, 1 do
        if inv.getInventorySize(i) == 58 then
            reactorSide = i
            return true
        end
    end
    return false
end

-- 提取物品名称缩写和耐久值
local function getShortNameAndDurability(item)
    if item == nil then
        return "⌈   ⌉", "⌊   ⌋"
    end
    local name = item.name or "unknown"
    local base = string.match(name, "^ic2:(.+)") or name
    local parts = {}
    for part in string.gmatch(base, "[^_]+") do
        table.insert(parts, part)
    end
    local short = ""
    for _, part in ipairs(parts) do
        if #part > 0 then
            short = short .. string.sub(part, 1, 1)
        end
    end
    short = string.sub(short, 1, 3)
    local shortText = string.format("⌈%-3s⌉", short)
    local durabilityText
    if item.maxDamage and item.maxDamage > 0 and item.damage and type(item.damage) == "number" then
        local durability = math.ceil(((item.maxDamage - item.damage) / item.maxDamage) * 100)
        durabilityText = string.format("⌊%3d⌋", durability)
    else
        durabilityText = "⌊---⌋"
    end
    return shortText, durabilityText
end

-- 创建热量显示条
local function getHeatBar()
    local maxHeat = 10000 -- IC2 核反应堆最大热量
    local currentHeat = reactor.getHeat() or 0
    local heatPercent = math.ceil((currentHeat / maxHeat) * 100)
    local barLength = 20 -- 热量条长度（字符数）
    local filled = math.ceil((currentHeat / maxHeat) * barLength)
    local empty = barLength - filled
    local bar = string.rep("█", filled) .. string.rep(" ", empty)
    return string.format("堆温：[%s] (%d%%)", bar, heatPercent)
end

-- 获取终端宽度并计算居中所需的填充空格
local function centerText(text, textWidth)
    local padding = math.ceil((termWidth - textWidth) / 2)
    if padding > 0 then
        -- 在文本前填充空格（居中），在文本后填充空格以达到总长度
        return string.rep(" ", padding) .. text .. string.rep(" ", termWidth - textWidth - padding)
    end
    return text
end

-- 更新屏幕显示
local function updateDisplay()
    local buffer = {}
    local stateLine = ""
    local heatLine = getHeatBar()
    termWidth = term.getViewport()
    for i = 0, 5, 1 do -- 6 行
        local nameLine = ""
        local durabilityLine = ""
        for j = 1, 9, 1 do
            local currentSlot = i * 9 + j
            local currentItem = inv.getStackInSlot(reactorSide, currentSlot)
            local shortText, durabilityText = getShortNameAndDurability(currentItem)
            nameLine = nameLine .. shortText
            durabilityLine = durabilityLine .. durabilityText
        end
        table.insert(buffer, centerText(nameLine, 45) .. "\n")
        table.insert(buffer, centerText(durabilityLine, 45) .. "\n")
        if reactor.producesEnergy() then
            stateLine = string.format("反应堆状态：开启，输出：%dEU/t\n", reactor.getReactorEUOutput())
        else
            stateLine = "反应堆状态：关闭，输出：0EU/t\n"
        end
    end
    term.setcursor(1, 1)
    io.write(centerText("<[Q]  反应堆监视器  [E]>\n", 24))
    io.write(table.concat(buffer))
    io.write('\n')
    io.write(centerText(stateLine, 45))
    io.write(centerText(heatLine, 45))
end

--主程序
local function main()
    if findreactor() then
        print("已找到反应堆，正在启动系统...")
        term.clear()

        while true do
            updateDisplay() -- 每次循环直接更新屏幕
        end
    else
        print(centerText("未找到反应堆！"))
    end
end

main()
