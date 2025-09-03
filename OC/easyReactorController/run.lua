local component = require("component")
local term = require("term")
local event = require("event")
local inv = component.inventory_controller
local reactor = component.proxy(component.list("reactor_chamber")())
local reactorSide = 0

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
    return string.format("\n堆温：[%s] (%d%%)", bar, heatPercent)
end

-- 缓存上一次的物品状态
local lastState = {}

-- 检查槽位是否发生变化
local function hasChanged(slot, item)
    local state = lastState[slot] or {}
    local shortText, durabilityText = getShortNameAndDurability(item)
    local changed = state.shortText ~= shortText or state.durabilityText ~= durabilityText
    lastState[slot] = { shortText = shortText, durabilityText = durabilityText }
    return changed
end

-- 获取终端宽度并计算居中所需的填充空格
local function centerText(text, textWidth)
    local termWidth = term.getViewport() -- 获取终端宽度
    local padding = math.ceil((termWidth - textWidth) / 2)
    if padding > 0 then
        return string.rep(" ", padding) .. text
    end
    return text
end

if findreactor() then
    term.clear()
    term.setCursor(1, 1)
    print("已找到反应堆，开始监控...")

    -- 主循环
    while true do
        local buffer = {}
        local hasAnyChange = false
        local stateLine = ""
        for i = 0, 5, 1 do -- 6 行
            local nameLine = ""
            local durabilityLine = ""
            for j = 1, 9, 1 do
                local currentSlot = i * 9 + j
                local currentItem = inv.getStackInSlot(reactorSide, currentSlot)
                local shortText, durabilityText = getShortNameAndDurability(currentItem)
                if hasChanged(currentSlot, currentItem) then
                    hasAnyChange = true
                end
                nameLine = nameLine .. shortText
                durabilityLine = durabilityLine .. durabilityText
            end
            table.insert(buffer, centerText(nameLine, 45) .. "\n")
            table.insert(buffer, centerText(durabilityLine, 45) .. "\n")
            if reactor.producesEnergy() then
                stateLine = string.format("反应堆状态：开启，输出：%dEU/t", reactor.getReactorEUOutput()) .. getHeatBar()
            else
                stateLine = "反应堆状态：关闭，输出：0EU/t" .. getHeatBar()
            end
        end

        -- 仅在有变化时更新屏幕
        if hasAnyChange then
            term.clear()
            term.write(centerText("<[Q]  反应堆监视器  [E]>", 24) .. '\n')
            term.write(table.concat(buffer))
            term.write(stateLine)
        end

        -- 等待 0.1 秒或中断信号
        local eventName = event.pull(0.1, "interrupted")
        if eventName == "interrupted" then
            term.clear()
            term.setCursor(1, 1)
            print(centerText("监控已停止", 10))
            break
        end
    end
else
    print(centerText("未找到反应堆！"))
end
