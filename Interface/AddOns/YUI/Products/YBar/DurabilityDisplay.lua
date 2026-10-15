local YBar = _G.YUI.YBar
local Display = {}
YBar.DurabilityDisplay = Display

local RETRY_DELAYS = {0.2, 0.5, 1, 2, 3}
local SAMPLES = {"--"}
for value = 0, 100 do SAMPLES[#SAMPLES + 1] = value .. "%" end

function Display.StopRetry(owner)
    if owner.durabilityRetryTimer then
        owner.durabilityRetryTimer:Cancel()
        owner.durabilityRetryTimer = nil
    end
    owner.durabilityRetryCallback = nil
end

function Display.BeginRetry(owner)
    Display.StopRetry(owner)
    owner.durabilityRetryAttempts = 0
    local callback
    callback = function()
        -- 已取消或上一次启用留下的回调不能影响当前 owner。
        if owner.durabilityRetryCallback ~= callback then return end
        owner.durabilityRetryTimer = nil
        if not owner.runtimeAttached then return end
        owner.durabilityRetryAttempts = owner.durabilityRetryAttempts + 1
        owner:UpdateBarItem()
    end
    owner.durabilityRetryCallback = callback
end

function Display.UpdateRetry(owner, needed)
    if not needed then Display.StopRetry(owner); return end
    if not owner.runtimeAttached or not owner.durabilityRetryCallback or owner.durabilityRetryTimer then return end
    local delay = RETRY_DELAYS[owner.durabilityRetryAttempts + 1]
    if not delay then Display.StopRetry(owner); return end
    owner.durabilityRetryTimer = C_Timer.NewTimer(delay, owner.durabilityRetryCallback)
end

local function ReadWidth(text)
    local width = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
    if not width or width <= 0 then width = text:GetStringWidth() end
    return width
end

local function UpperBound(value)
    return type(value) == "number" and math.max(0, math.min(100, math.floor(value))) or 100
end

function Display.MeasureText(owner, font, size, flags, mode, average, lowest)
    local cached = owner.durabilityMeasureFrame == owner.frame and owner.durabilityMeasureFont == font
        and owner.durabilityMeasureSize == size and owner.durabilityMeasureFlags == flags
        and owner.durabilityRangeWidths
    if not cached then
        owner.durabilityRangeWidths = nil
        if owner.durabilityMeasureFrame ~= owner.frame then
            owner.durabilityMeasureText = YBar:CreateThemedText(owner.frame, {wordWrap = false})
            owner.durabilityMeasureText:Hide()
            owner.durabilityMeasureText:SetWidth(0)
            owner.durabilityMeasureFrame = owner.frame
        end
        local measure = owner.durabilityMeasureText
        if measure:SetFont(font, size, flags) == false then return 0, false end
        local ranges, maximum, zeroWidth = {}, 0, 0
        -- 每个上限缓存 0..上限的最宽读数；比例字体的较小数值也可能更宽。
        -- 只在字体变化时测量，耐久下降和显示模式变化直接查表。
        for index, sample in ipairs(SAMPLES) do
            measure:SetText(sample)
            local width = ReadWidth(measure)
            if not width or width <= 0 then measure:SetText(""); return 0, false end
            maximum = math.max(maximum, width)
            if index > 1 then ranges[index - 1] = maximum end
            if index == 2 then zeroWidth = width end
        end
        measure:SetText("0% 0%")
        local pairWidth = ReadWidth(measure)
        measure:SetText("")
        if not pairWidth or pairWidth <= 0 then return 0, false end
        owner.durabilitySpaceWidth = math.max(pairWidth - zeroWidth * 2, 0)
        owner.durabilityMeasureFont, owner.durabilityMeasureSize = font, size
        owner.durabilityMeasureFlags = flags
        owner.durabilityRangeWidths = ranges
    end
    local ranges = owner.durabilityRangeWidths
    -- 暂缺/受限读数先保留完整范围，补读恢复后再按实际读数收紧。
    local averageBound = UpperBound(average)
    local lowestBound = type(average) == "number" and UpperBound(lowest) or 100
    if mode == "average_lowest" then
        return ranges[averageBound + 1] + owner.durabilitySpaceWidth + ranges[lowestBound + 1], true
    end
    return ranges[(mode == "average" and averageBound or lowestBound) + 1], true
end
