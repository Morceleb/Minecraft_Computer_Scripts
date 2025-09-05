local component = require("component")
local term = require("term")
local thread = require("thread")
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
    local shortText

    if name == "ic2:uranium_fuel_rod" then
        shortText = "⌈ † ⌉"
    elseif name == "ic2:dual_uranium_fuel_rod" then
        shortText = "⌈ ⫲ ⌉"
    elseif name == "ic2:quad_uranium_fuel_rod" then
        shortText = "⌈ ⌗ ⌉"
    elseif name == "ic2:component_heat_vent" then
        shortText = "⌈ ⁜ ⌉"
    elseif string.sub(name, -4) == "vent" then
        shortText = "⌈ 〿 ⌉"
    elseif string.sub(name, -9) == "exchanger" then
        shortText = "⌈ ◊ ⌉"
    else
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
        shortText = string.format("⌈%-3s⌉", short)
    end

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
    local maxHeat = 10000
    local currentHeat = reactor.getHeat() or 0
    local heatPercent = math.ceil((currentHeat / maxHeat) * 100)
    local barLength = 20
    local filled = math.ceil((currentHeat / maxHeat) * barLength)
    local empty = barLength - filled
    local bar = string.rep("█", filled) .. string.rep(" ", empty)
    return string.format("堆温：[%s] (%d%%)", bar, heatPercent)
end

-- 获取终端宽度并计算居中所需的填充空格
local function centerText(text, textWidth)
    local termWidth = term.getViewport()
    local padding = math.ceil((termWidth - textWidth) / 2)
    if padding > 0 then
        return string.rep(" ", padding) .. text .. string.rep(" ", termWidth - textWidth - padding - 1)
    end
    return text
end

-- 获取终端宽度并计算居中所需的起始坐标
local function getCenteredStartX(textWidth)
    local termWidth = term.getViewport()
    return math.ceil((termWidth - textWidth) / 2) + 1
end

-- 更新反应堆网格的线程
local function updateGrid()
    local gridRows = 6
    local gridCols = 9
    local cellWidth = 5
    local cellHeight = 2
    local gridWidth = gridCols * cellWidth
    local startX = getCenteredStartX(gridWidth)
    local startY = 2
    local lastGrid = {}

    for i = 1, gridRows do
        lastGrid[i] = {}
        for j = 1, gridCols do
            lastGrid[i][j] = { shortText = "", durabilityText = "" }
        end
    end

    while true do
        for i = 1, gridRows do
            for j = 1, gridCols do
                local currentSlot = (i - 1) * 9 + j
                local currentItem = inv.getStackInSlot(reactorSide, currentSlot)
                local shortText, durabilityText = getShortNameAndDurability(currentItem)
                local x = startX + (j - 1) * cellWidth
                local y = startY + (i - 1) * cellHeight
                if lastGrid[i][j].shortText ~= shortText then
                    term.setCursor(x, y)
                    term.write(shortText)
                    lastGrid[i][j].shortText = shortText
                end
                if lastGrid[i][j].durabilityText ~= durabilityText then
                    term.setCursor(x, y + 1)
                    term.write(durabilityText)
                    lastGrid[i][j].durabilityText = durabilityText
                end
            end
            os.sleep(0.05)
        end
    end
end

-- 更新反应堆状态和热量条的线程
local function updateStatus()
    while true do
        local statusText = reactor.producesEnergy() and
            string.format("反应堆状态：开启，输出：%5dEU/t", reactor.getReactorEUOutput()) or
            "反应堆状态：关闭，输出：    0EU/t"
        local heatBarText = getHeatBar()

        -- 绘制状态和热量条（在网格下方）
        term.setCursor(1, 15) -- 固定在第15行，避免与网格重叠
        term.write(centerText(statusText, 45))
        term.setCursor(1, 16)
        term.write(centerText(heatBarText, 45))
        os.sleep(0.01)
    end
end

-- 主程序
if findreactor() then
    term.clear()
    term.setCursor(1, 1)
    term.write(centerText("<<<<  反应堆监视器  >>>>", 24))

    -- 创建两个线程
    local statusThread = thread.create(updateStatus)

    local gridThread = thread.create(updateGrid)

    -- 等待线程结束（实际上不会结束，除非程序被中断）
    thread.waitForAll({ gridThread, statusThread })
else
    print(centerText("未找到反应堆！"))
end
