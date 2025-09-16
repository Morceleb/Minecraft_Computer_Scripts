-- 引入OC的API
local component = require("component")
local term = require("term")
local thread = require("thread")
local event = require("event")
local keyboard = require("keyboard")

local inv = component.inventory_controller
local reactor = component.proxy(component.list("reactor_chamber")())

local reactorSide = 0
local totalPages = 2
local currentPage = 1
local gridThread = nil
local statusThread = nil


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

local lastGrid = {}
local gridRows = 6
local gridCols = 9

for i = 1, gridRows do
    lastGrid[i] = {}
    for j = 1, gridCols do
        lastGrid[i][j] = { shortText = "", durabilityText = "" }
    end
end

local function updateGrid()
    local cellWidth = 5
    local cellHeight = 2
    local startX = getCenteredStartX(45)
    local startY = 2


    while true do
        for i = 1, gridRows do
            for j = 1, gridCols do
                local currentSlot = (i - 1) * 9 + j
                local currentItem = inv.getStackInSlot(reactorSide, currentSlot)
                local shortText, durabilityText = getShortNameAndDurability(currentItem)
                local x = startX + (j - 1) * cellWidth
                local y = startY + (i - 1) * cellHeight
                if lastGrid[i][j].shortText ~= shortText or lastGrid[i][j].durabilityText ~= durabilityText then
                    term.setCursor(x, y)
                    term.write(shortText)
                    term.setCursor(x, y + 1)
                    term.write(durabilityText)

                    lastGrid[i][j].shortText = shortText
                    lastGrid[i][j].durabilityText = durabilityText
                end
            end
            os.sleep(0.01)
        end
    end
end

-- 更新反应堆状态和热量条的线程
local function updateStatus()
    while true do
        if currentPage == 1 then
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
        else
            thread.current():suspend()
        end
    end
end

-- 操作指南页面
local function showGuide()
    if currentPage == 2 then
        local guideLines = {
            "操作指南：",
            "  A，D：切换页面",
            "  CTRL+C： 退出程序",
            "  （以下需要红石I/O）",
            "  Q：关闭反应堆",
            "  O：开启反应堆",
            "图标解释：",
            "  †：单铀燃料棒",
            "  ⫲：双铀燃料棒",
            "  ⌗：四铀燃料棒",
            "  ⁜：元件散热片",
            "  〿：散热片",
            "  ◊：热交换器",
        }
        for i, line in ipairs(guideLines) do
            term.setCursor(1, 2 + i)
            term.write(centerText(line, 31))
        end
    end
end


-- 更新页面标题的线程
local function updatePage()
    local lastPage = 1
    term.setCursor(1, 1)
    term.write(centerText("<[A]  反应堆监视器  [D]>", 24))
    while true do
        if lastPage ~= currentPage then
            lastPage = currentPage
            term.clear()
            term.setCursor(1, 1)
            if currentPage == 1 then
                term.write(centerText("<[A]  反应堆监视器  [D]>", 24))
                if gridThread and gridThread:status() == "suspended" then
                    gridThread:resume()
                end
                if statusThread and statusThread:status() == "suspended" then
                    statusThread:resume()
                end
            elseif currentPage == 2 then
                term.write(centerText("<[A]  操作指南  [D]>", 20))
                if gridThread and gridThread:status() == "running" then
                    gridThread:suspend()
                    for i = 1, gridRows do
                        lastGrid[i] = {}
                        for j = 1, gridCols do
                            lastGrid[i][j] = { shortText = "", durabilityText = "" }
                        end
                    end
                end
                if statusThread and statusThread:status() == "running" then
                    statusThread:suspend()
                end
                showGuide()
            elseif currentPage == 3 then
                term.write(centerText("<[A]  系统设置  [D]>", 20))
            end
        end
        os.sleep(0.05)
    end
end

-- 监听键盘输入的线程
local function listenForKeyPress()
    while true do
        local _, _, _, code = event.pull("key_down")
        if code == keyboard.keys.a then -- A键
            if currentPage > 1 then
                currentPage = currentPage - 1
            else
                currentPage = totalPages
            end
        elseif code == keyboard.keys.d then -- D键
            if currentPage < totalPages then
                currentPage = currentPage + 1
            else
                currentPage = 1
            end
        end
    end
end


-- 主程序
if findreactor() then
    term.clear()

    local inputThread = thread.create(listenForKeyPress)
    local pageThread = thread.create(updatePage)

    statusThread = thread.create(updateStatus)
    gridThread = thread.create(updateGrid)



    -- 等待线程结束（实际上不会结束，除非程序被中断）
    thread.waitForAll({ pageThread, statusThread, gridThread, inputThread })
else
    print(centerText("未找到反应堆！"))
end
