-- 引入OC的API
local component = require("component")
local term = require("term")
local thread = require("thread")
local event = require("event")

local success, rs = pcall(function() return component.redstone end) --本来可以给物品栏控制器和反应堆都加上存在性判断的，但我不想写了

local inv = component.inventory_controller
local reactor = component.proxy(component.list("reactor_chamber")())

local reactorSide = 0
local redStoneSide = 0

local totalPages = 3
local currentPage = 1
local monitorThread = nil


local currentHeat = 0    -- 当前热量
local heatThreshold = 80 -- 默认热量阈值（百分比）

-- 自动化相关变量
local restartFlag = false
local cMins = 0
local cSecs = 10
local isCoolingDown = false
local shutdownStartTime = 0 -- 记录关停开始时间
local cooldownDuration = 0  -- 冷却持续时间（秒）

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

-- 查找红石输出方向
local function findredStone()
    if not success then
        term.clear()
        print("错误：无法加载红石组件。")
        os.sleep(5)
        return
    end
    if reactor.producesEnergy() then
        for i = 0, 5, 1 do
            rs.setOutput(i, 0)
        end
    end
    if reactor.producesEnergy() then
        return false
    end
    for i = 0, 5, 1 do
        rs.setOutput(i, 5)
        if reactor.producesEnergy() then
            rs.setOutput(i, 0)
            redStoneSide = i
            return true
        end
        rs.setOutput(i, 0)
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
    elseif string.sub(name, -7) == "plating" then
        shortText = "⌈ ■ ⌉"
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

-- 获取终端宽度并计算居中所需的填充空格
local function centerText(text, textWidth)
    local termWidth = term.getViewport()
    local padding = math.ceil((termWidth - textWidth) / 2)
    if padding > 0 then
        return string.rep(" ", padding) .. text .. string.rep(" ", termWidth - textWidth - padding - 1)
    end
    return text
end

-- 自动化控制：高温关停和冷却后自动重启
local function autoControl()
    while true do
        currentHeat = reactor.getHeat()
        local currentHeatPercent = math.ceil((currentHeat / 10000) * 100)

        -- 高温关停逻辑
        if currentHeatPercent > heatThreshold and reactor.producesEnergy() and not isCoolingDown then
            rs.setOutput(redStoneSide, 0)
            isCoolingDown = true
            shutdownStartTime = os.time() / 100
            cooldownDuration = cMins * 60 + cSecs
        end

        -- 冷却期检查和自动重启
        if isCoolingDown and restartFlag then
            local elapsed = os.time() / 100 - shutdownStartTime
            if elapsed >= (cooldownDuration - 1.45) then
                rs.setOutput(redStoneSide, 15)
                isCoolingDown = false
            end
        end

        -- 如果反应堆手动开启，重置冷却状态
        if reactor.producesEnergy() and isCoolingDown then
            isCoolingDown = false
        end

        os.sleep(0.02)
    end
end

-- 创建热量显示条
local function getHeatBar()
    local heatPercent = math.ceil((currentHeat / 10000) * 100)
    local barLength = 20
    local filled = math.ceil((currentHeat / 10000) * barLength)
    local empty = barLength - filled
    local bar = string.rep("█", filled) .. string.rep(" ", empty)
    return string.format("堆温：[%s] (%d%%)", bar, heatPercent)
end

-- 获取终端宽度并计算居中所需的起始坐标
local function getCenteredStartX(textWidth)
    local termWidth = term.getViewport()
    return math.ceil((termWidth - textWidth) / 2) + 1
end

-- 更新反应堆监控器的线程
local lastGrid = {}
local gridRows = 6
local gridCols = 9

for i = 1, gridRows do
    lastGrid[i] = {}
    for j = 1, gridCols do
        lastGrid[i][j] = { shortText = "", durabilityText = "" }
    end
end

local function updateMonitor()
    local cellWidth = 5
    local cellHeight = 2
    local startX = getCenteredStartX(45)
    local startY = 2

    local statusText = ""

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
            -- 每行更新后刷新状态栏
            statusText = reactor.producesEnergy() and
                string.format("反应堆状态：开启，输出：%5dEU/t", reactor.getReactorEUOutput()) or
                "反应堆状态：关闭，输出：    0EU/t"
            local heatBarText = getHeatBar()
            term.setCursor(1, 15) -- 固定在第15行，避免与网格重叠
            term.write(centerText(statusText, 45))
            term.setCursor(1, 16)
            term.write(centerText(heatBarText, 45))
            os.sleep(0.005)
        end
    end
end

-- 操作指南页面
local function showGuide()
    local guideLines = {
        "按键控制：",
        "  A，D：切换页面",
        "  Q：关闭反应堆",
        "  E：开启反应堆",
        "图标解释：",
        "  †：单铀燃料棒, ⫲：双铀燃料棒",
        "  ⌗：四铀燃料棒",
        "  ⁜：元件散热片",
        "  〿：散热片",
        "  ◊：热交换器",
        "  ■：反应堆隔板"
    }
    for i, line in ipairs(guideLines) do
        term.setCursor(1, 2 + i)
        term.write(centerText(line, 31))
    end
end

local inputBuffer = "" -- 用于页面3的输入缓冲区
local pointer = 1      -- 页面3的选项指针
local function showAutoSettings()
    local settingLines = {
        ((pointer == 1) and "-> " or "   ") .. string.format("温度阈值：%d%% (超过自动关停)", heatThreshold),
        ((pointer == 2) and "-> " or "   ") .. string.format("是否自动重启%s", restartFlag and "：是" or "：否"),
        ((pointer == 3) and "-> " or "   ") .. string.format("停机冷却周期：%2d分%2d秒", cMins, cSecs),
        "",
        ((pointer ~= 2) and ("   输入：" .. string.format(" %6s", inputBuffer)) or "   "),
        "",
        "   W，S移动光标，数字键输入，回车键确认。"
    }
    for i, line in ipairs(settingLines) do
        term.setCursor(1, 2 + i)
        term.write(centerText(line, 38))
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
                if monitorThread and monitorThread:status() == "suspended" then
                    monitorThread:resume()
                end
            elseif currentPage == 2 then
                term.write(centerText("<[A]  操作指南  [D]>", 20))
                if monitorThread and monitorThread:status() == "running" then
                    monitorThread:suspend()
                    for i = 1, gridRows do
                        lastGrid[i] = {}
                        for j = 1, gridCols do
                            lastGrid[i][j] = { shortText = "", durabilityText = "" }
                        end
                    end
                end
                showGuide()
            elseif currentPage == 3 then
                term.write(centerText("<[A]  自动化  [D]>", 18))
                if monitorThread and monitorThread:status() == "running" then
                    monitorThread:suspend()
                    for i = 1, gridRows do
                        lastGrid[i] = {}
                        for j = 1, gridCols do
                            lastGrid[i][j] = { shortText = "", durabilityText = "" }
                        end
                    end
                end

                showAutoSettings()
            end
        else
            -- 如果是页面3，动态更新显示（输入缓冲区变化）
            if currentPage == 3 then
                showAutoSettings()
            end
        end
        os.sleep(0.05)
    end
end

-- 监听键盘输入的线程
local maxLength = 6
local function listenForKeyPress()
    while true do
        local _, _, char, code = event.pull("key_down")
        -- 分页切换（所有页面有效）
        if char == 97 then -- A
            if currentPage > 1 then
                currentPage = currentPage - 1
            else
                currentPage = totalPages
            end
        elseif char == 100 then -- D
            if currentPage < totalPages then
                currentPage = currentPage + 1
            else
                currentPage = 1
            end
        elseif char == 101 then -- E 开启反应堆（所有页面有效）
            if not reactor.producesEnergy() then
                rs.setOutput(redStoneSide, 15)
            end
        elseif char == 113 then -- Q 关闭反应堆（所有页面有效）
            if reactor.producesEnergy() then
                rs.setOutput(redStoneSide, 0)
            end
        elseif currentPage == 3 then
            -- 页面3特定输入
            if char == 13 then -- Enter
                if pointer == 1 then
                    -- 设置温度阈值
                    local newThresh = tonumber(inputBuffer)
                    if newThresh and newThresh >= 1 and newThresh <= 99 then
                        heatThreshold = newThresh
                    end
                    inputBuffer = ""
                elseif pointer == 2 then
                    -- 切换自动重启选项
                    restartFlag = not restartFlag
                    inputBuffer = "" -- 清空缓冲区，虽然pointer2不输入
                elseif pointer == 3 then
                    -- 设置停机冷却周期
                    local input = inputBuffer
                    inputBuffer = ""
                    if string.find(input, ",") then
                        -- "num,num" 格式
                        local parts = {}
                        for part in string.gmatch(input, "[^,]+") do
                            table.insert(parts, part)
                        end
                        if #parts == 2 then
                            local mins = tonumber(parts[1]) or 0
                            local secs = tonumber(parts[2]) or 0
                            cMins = math.max(0, mins)
                            cSecs = math.min(59, math.max(0, secs))
                        end
                    else
                        -- 单个数字，只改变秒数
                        local secs = tonumber(input) or 0
                        cSecs = math.min(59, math.max(0, secs))
                    end
                end
            elseif (pointer == 1 or pointer == 3) and char >= 48 and char <= 57 then -- 数字0-9
                if #inputBuffer < maxLength then
                    inputBuffer = inputBuffer .. string.char(char)
                end
                -- 可选：如果长度已满，显示提示（通过更新页面）
            elseif pointer == 3 and char == 44 then                                     -- 逗号 (ASCII 44)
                if #inputBuffer < maxLength and string.sub(inputBuffer, -1) ~= "," then -- 避免连续逗号，并检查长度
                    inputBuffer = inputBuffer .. ","
                end
            elseif (pointer == 1 or pointer == 3) and code == 14 then -- Backspace
                inputBuffer = inputBuffer:sub(1, -2)
            elseif char == 119 then
                -- W键：上移指针
                if pointer > 1 then
                    pointer = pointer - 1
                else
                    pointer = 3
                end
                inputBuffer = "" -- 切换指针时清空缓冲区
            elseif char == 115 then
                -- S键：下移指针
                if pointer < 3 then
                    pointer = pointer + 1
                else
                    pointer = 1
                end
                inputBuffer = "" -- 切换指针时清空缓冲区
            end
        end
    end
end

-- 主程序
if findreactor() then
    if findredStone() then
        term.clear()

        local inputThread = thread.create(listenForKeyPress)
        local pageThread = thread.create(updatePage)
        local autoThread = thread.create(autoControl)

        monitorThread = thread.create(updateMonitor)

        -- 等待线程结束（实际上不会结束，除非程序被中断）
        thread.waitForAll({ pageThread, monitorThread, inputThread, autoThread })
    else
        print(centerText("红石I/O端口安装不当或存在其他红石输入", 37))
        os.sleep(5)
    end
else
    print(centerText("未找到反应堆！", 14))
    os.sleep(5)
end
