--[[
增益计时开发说明

首版实现参考了 SpellAlertTimer（SAT）插件的实现，并引用了其法术警报与
Buff 的映射数据。当时未事先与作者简繁沟通并取得授权，对此深表歉意，
也衷心感谢简繁的开发成果与贡献。

2026-10-04，本功能完成基于独立数据采集的代码重写。

采集过程：
2026-09-30 至 2026-10-04，通过各职业切换专精、天赋并反复攻击木桩，
完成了 16 次已归档采集，累计约 1 小时 49 分钟（包含切换与脱战等待）。
其中 15 次具有战斗分段记录，共记录 74 次进入战斗，按分段估算战斗状态
累计约 60 分钟；首次奥法采集未记录此类分段，不计入上述战斗次数与时长。
这些数字描述已保存的样本，不代表所有天赋组合均已验证。

开发流程：
1. 同步记录警报 SHOW/HIDE、玩家施法和本地战斗日志，
   通过同一施法事件校准时间线，本轮共取得 2,484 对施法校时样本。
2. 对照 Buff 的获得、消失与层数变化，反复验证警报与 Buff 的关系，
   保留匿名证据、分析结果及未确认情况。
3. 将确认的不同 ID 关系整理为按专精解析的特殊映射；
   其余警报默认使用自身 ID 查询玩家增益，不设置排除表。
4. 使用游戏原生增益与剩余时间文字绑定，不在 Lua 中计算秘密时间；
   无匹配增益或可显示时间时自然留空。
5. 按警报 SHOW/HIDE 管理文字生命周期；牧师两组警报同时出现时，
   将阴暗面之力的图形和文字整组内移，保留两组显示。
]]

local _, addon = ...
local YUI = _G.YUI or addon
if not (YUI and YUI.Components) then return end
YUI.SpellAlert = YUI.SpellAlert or {}
local Timer = {}
YUI.SpellAlert.BuffTimer = Timer
local Unit = YUI.API.Unit
local GUI = YUI.GUI2
local Rules = YUI.SpellAlert.BuffTimerRules
local pool, settings = {}, {}
local byOverlay = setmetatable({}, { __mode = "k" })
local version, build
if GetBuildInfo then version, build = GetBuildInfo() end
local clientSupported = YUI.IsRetail == true and version == "12.1.0" and tostring(build) == "69933"
local running, owner, relayout, specID, listening = false, nil, nil, nil, false
local formatter, durationOptions, measure, revision = nil, nil, nil, 0
local textWidth = 0
local LIMIT, SLOT = 32, "spell-alert-buff-time"
local loc = Enum and Enum.ScreenLocationType or {}
local LEFT, RIGHT = loc.Left or 1, loc.Right or 2
local LO, RO = loc.LeftOutside or 7, loc.RightOutside or 8
local stats = { created = 0, failures = 0, overflow = 0, styleWrites = 0 }

local function PublicNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value == value
end
local function Clamp(value, low, high, default)
    if not PublicNumber(value) then return default end
    return math.max(low, math.min(high, value))
end
local function Side(position)
    if position == LEFT or position == LO then return -1 end
    if position == RIGHT or position == RO then return 1 end
    return 0
end
function Timer.GetDefaultFontName()
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then
        local path = GUI:GetFont("font.family.body")
        for _, name in ipairs(media.List and media:List("font") or {}) do
            if media:Fetch("font", name, true) == path then return name end
        end
        if media.GetDefault then return media:GetDefault("font") end
    end
    return "Friz Quadrata TT"
end
function Timer.Normalize(db)
    if type(db.countdown) ~= "table" then db.countdown = {} end
    local c = db.countdown
    if type(c.enabled) ~= "boolean" then c.enabled = true end
    if type(c.priestAvoidance) ~= "boolean" then c.priestAvoidance = true end
    if type(c.font) ~= "string" or c.font == "" or c.font == "default" then c.font = Timer.GetDefaultFontName() end
    c.size = math.floor(Clamp(c.size, 10, 80, 21))
    c.sideX = Clamp(c.sideX, -100, 100, Clamp(c.outward, -100, 100, 15))
    c.sideY = Clamp(c.sideY, -100, 100, Clamp(c.y, -100, 100, 0))
    c.topX = Clamp(c.topX, -100, 100, 0)
    c.topY = Clamp(c.topY, -100, 100, Clamp(c.y, -100, 100, 0))
    c.outward, c.y = nil, nil
    if c.outline ~= "" and c.outline ~= "OUTLINE" and c.outline ~= "THICKOUTLINE"
        and c.outline ~= "SHADOW" and c.outline ~= "OUTLINE_SHADOW" then c.outline = "OUTLINE_SHADOW" end
    if type(c.color) ~= "table" then c.color = {} end
    for i = 1, 3 do c.color[i] = Clamp(c.color[i], 0, 1, 1) end
    c.color[4] = 1
    return c
end
function Timer.IsSupported()
    return clientSupported and Unit and Unit.SupportsFilteredAuraDisplay
        and Unit.SupportsFilteredAuraDisplay() and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding and true or false
end
local function FontPath(name)
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    return (media and media:Fetch("font", name, true)) or GUI:GetFont("font.family.body") or STANDARD_TEXT_FONT
end
local function Style(text, c)
    local flags = c.outline == "OUTLINE_SHADOW" and "OUTLINE" or c.outline == "SHADOW" and "" or c.outline
    local shadow = c.outline == "SHADOW" or c.outline == "OUTLINE_SHADOW"
    assert(text:SetFont(FontPath(c.font), c.size, flags) ~= false, "font-unavailable")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
end
local function Find(overlay)
    return byOverlay[overlay]
end
local function StopDisplay(r)
    if r.displaying then
        r.host:Hide()
        if r.handle then pcall(r.handle.container.SetEnabled, r.handle.container, false); r.handle.proxy:Hide() end
        r.displaying = false
    end
end
local function Place(r)
    local side = Side(r.position)
    local scale = settings.textScale or 1
    if r.textScale ~= scale then r.host:SetScale(scale); r.textScale = scale end
    local x = (side == 0 and settings.topX or side * settings.sideX) / scale
    local y = (side == 0 and settings.topY or settings.sideY) / scale
    if r.anchor ~= r.overlay or r.x ~= x or r.y ~= y then
        r.host:ClearAllPoints()
        r.host:SetPoint("CENTER", r.overlay, "CENTER", x, y)
        r.anchor, r.x, r.y = r.overlay, x, y
    end
end
local function Display(r)
    if not r.active or not running or not settings.enabled or not Timer.IsSupported() then StopDisplay(r); return end
    if r.failed then return end
    if r.displaying and r.revision == revision and r.boundID == r.buffID and r.anchor == r.overlay then return end
    local ok = pcall(function()
        assert(durationOptions, "duration-options-unavailable")
        if not r.host then r.host = GUI:CreateFrame(owner, { width = 1, height = 1 }); r.host:Hide() end
        Place(r)
        if not r.handle then
            r.handle = assert(Unit.CreateFilteredAuraDisplay(r.host, {
                unit = "player", filter = "HELPFUL", key = SLOT, spellIDs = { r.buffID },
                initializeFrame = function(frame)
                    frame:SetAllPoints(r.host)
                    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    text:SetPoint("CENTER")
                    Style(text, settings)
                    r.text = text
                    return { durationText = { target = text, options = durationOptions } }
                end,
            }))
            r.boundID, r.revision = r.buffID, revision
            stats.created = stats.created + 1
        elseif r.boundID ~= r.buffID then
            r.handle.container:SetAuraSlotCandidateFilters(SLOT, { includeSpellIDs = { [r.buffID] = true } })
            r.boundID = r.buffID
        end
        if r.revision ~= revision then
            Style(r.text, settings)
            assert(Unit.SetFilteredAuraDurationTextOptions(r.handle, durationOptions), "duration-options-unavailable")
            r.revision = revision
            stats.styleWrites = stats.styleWrites + 1
        end
        if not r.displaying then
            r.handle.container:SetEnabled(true)
            r.handle.proxy:Show()
            r.host:Show()
            r.displaying = true
        end
    end)
    if not ok then
        if r.host then r.host:Hide() end
        if r.handle then pcall(r.handle.container.SetEnabled, r.handle.container, false); r.handle.proxy:Hide() end
        r.displaying, r.failed = false, true
        stats.failures = stats.failures + 1
    end
end

-- Only public spell-alert geometry is inspected; the native aura text is never read.
local function Avoidance()
    local dark, surge = false, false
    for _, r in ipairs(pool) do
        if r.active then
            if r.id == 198069 then dark = true end
            if r.id == 114255 or r.id == 128654 then surge = true end
        end
    end
    local distance = 0
    if running and YUI.IsRetail and settings.priestAvoidance and dark and surge then
        local units = (UIParent and UIParent:GetEffectiveScale() or 1) / owner:GetEffectiveScale()
        local gap = 8 * units
        distance = math.max(48 * units, textWidth * units + gap)
        for _, r in ipairs(pool) do
            local side = Side(r.position)
            if r.active and r.id == 198069 and side ~= 0 and r.overlay.GetCenter then
                local x = r.overlay:GetCenter()
                if PublicNumber(x) then
                    local scale = r.overlay:GetEffectiveScale() / owner:GetEffectiveScale()
                    local base = x * scale - (r.inset or 0)
                    for _, other in ipairs(pool) do
                        if other.active and (other.id == 114255 or other.id == 128654)
                            and Side(other.position) == side and other.overlay.GetCenter then
                            local ox = other.overlay:GetCenter()
                            if PublicNumber(ox) then
                                local oscale = other.overlay:GetEffectiveScale() / owner:GetEffectiveScale()
                                distance = math.max(distance, textWidth * units + gap + side * (base - ox * oscale))
                            end
                        end
                    end
                end
            end
        end
    end
    for _, r in ipairs(pool) do
        local inset = r.active and r.id == 198069 and -Side(r.position) * distance or 0
        if r.inset ~= inset then
            r.inset = inset
            if r.overlay and relayout then relayout(r.overlay, r.position) end
        end
    end
end
function Timer.GetInset(overlay)
    local r = Find(overlay)
    return r and r.inset or 0
end
function Timer.HideAll()
    for _, r in ipairs(pool) do r.active = false; StopDisplay(r) end
    Avoidance()
end
function Timer.Hide(id)
    if id == nil then Timer.HideAll(); return end
    if not PublicNumber(id) then return end
    for _, r in ipairs(pool) do if r.id == id then r.active = false; StopDisplay(r) end end
    Avoidance()
end
function Timer.Release(overlay)
    local r = Find(overlay)
    if not r then return end
    r.active = false
    StopDisplay(r)
    Avoidance()
    byOverlay[overlay] = nil
    r.overlay, r.anchor, r.inset = nil, nil, 0
end
function Timer.Show(id, position, overlay)
    if not running or not overlay or not PublicNumber(id) or not PublicNumber(position) then return end
    local r = Find(overlay)
    if not r then
        for _, entry in ipairs(pool) do if not entry.active then r = entry; break end end
        if not r then
            if #pool >= LIMIT then stats.overflow = stats.overflow + 1; return end
            r = {}; pool[#pool + 1] = r
        end
    end
    local changed = not r.active or r.id ~= id or r.overlay ~= overlay or r.position ~= position
    if changed then
        local restoreLayout = r.overlay == overlay and (r.inset or 0) ~= 0
        StopDisplay(r)
        if r.overlay then byOverlay[r.overlay] = nil end
        byOverlay[overlay] = r
        r.id, r.position, r.overlay, r.active, r.failed, r.inset = id, position, overlay, true, false, 0
        r.buffID = Rules.Resolve(specID, id)
        if restoreLayout and relayout then relayout(overlay, position) end
    end
    Display(r)
    if changed then Avoidance() end
end
function Timer.LayoutComplete()
    -- Normal layout already includes the stored inset; recompute only at cold refreshes.
    Avoidance()
end
local function CurrentSpec()
    local talent = YUI.API.Talent
    local index = talent and talent.GetSpecialization and talent.GetSpecialization()
    local id = index and talent.GetSpecializationInfo and talent.GetSpecializationInfo(index)
    return PublicNumber(id) and id or nil
end
local function PrepareNativeOptions()
    if not clientSupported then return end
    if Unit.EnsureFilteredAuraDisplay then pcall(Unit.EnsureFilteredAuraDisplay) end
    if durationOptions or not Timer.IsSupported() then return end
    pcall(function()
        if not formatter then
            local value = C_StringUtil.CreateNumericRuleFormatter()
            value:SetBreakpoints({ { threshold = 0, step = .1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%.1f" },
                { threshold = 3, step = 1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%d" } })
            formatter = value
        end
        local color = assert(Unit.CreateAuraDurationTextColor(settings.r, settings.g, settings.b, 1))
        durationOptions = { textFormatter = formatter, textColor = color }
    end)
end
local function Retry()
    if not running then return end
    PrepareNativeOptions()
    for _, r in ipairs(pool) do if r.active and (r.failed or not r.displaying) then r.failed = false; Display(r) end end
end
local function SpecChanged()
    if not running then return end
    local current = CurrentSpec()
    if current ~= specID then Timer.HideAll(); specID = current end
end
function Timer.Configure(frame, c, componentEnabled, layoutCallback)
    owner, relayout = frame, layoutCallback or relayout
    local nextRunning = componentEnabled == true and clientSupported and frame ~= nil
    local changed = false
    local scale = frame and (UIParent and UIParent:GetEffectiveScale() or 1) / frame:GetEffectiveScale() or 1
    if settings.textScale ~= scale then settings.textScale = scale; changed = true end
    for _, key in ipairs({ "font", "size", "outline", "sideX", "sideY", "topX", "topY", "enabled", "priestAvoidance" }) do
        if settings[key] ~= c[key] then settings[key] = c[key]; changed = true end
    end
    for i, key in ipairs({ "r", "g", "b" }) do
        if settings[key] ~= c.color[i] then settings[key] = c.color[i]; changed = true end
    end
    if changed then
        revision = revision + 1
        durationOptions = nil
        if nextRunning then
            local ok = pcall(function()
                if not measure then measure = GUI:CreateText(frame, "", c.size, "color.text.primary"); measure:Hide() end
                Style(measure, c)
                measure:SetText("99"); local w = measure:GetStringWidth()
                measure:SetText("9.9"); textWidth = math.max(w, measure:GetStringWidth())
            end)
            if not ok then textWidth = c.size * 3 end
        end
    end
    if nextRunning then
        local current = CurrentSpec()
        if running and current ~= specID then Timer.HideAll() end
        specID = current
    end
    if nextRunning then PrepareNativeOptions() end
    running = nextRunning
    if running and not listening then
        YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", SpecChanged, Timer, { unit = "player" })
        YUI.Event:On("PLAYER_REGEN_ENABLED", Retry, Timer)
        YUI.Event:On("ADDON_RESTRICTION_STATE_CHANGED", Retry, Timer)
        listening = true
    elseif not running and listening then YUI.Event:OffOwner(Timer); listening = false end
    if not running then Timer.HideAll(); return end
    for _, r in ipairs(pool) do
        if r.active then
            if changed then r.failed = false end
            Display(r)
        end
    end
    Avoidance()
end
function Timer.Preview(button, side, c, parent)
    local text = button.yuiBuffTimerPreview
    if not c.enabled or not Timer.IsSupported() then if text then text:Hide() end; return end
    if not text then
        -- Use a sibling of the animated material so its pulse cannot scale text.
        local host = GUI:CreateFrame(parent or button:GetParent(), { width = 1, height = 1 })
        host:SetPoint("CENTER", button, "CENTER")
        host:SetFrameLevel(button:GetFrameLevel() + 1)
        text = GUI:CreateText(host, "", c.size, "color.text.primary")
        button.yuiBuffTimerPreviewHost = host
        button.yuiBuffTimerPreview = text
    end
    local host = button.yuiBuffTimerPreviewHost
    local scale = (UIParent and UIParent:GetEffectiveScale() or 1) / (parent or button:GetParent()):GetEffectiveScale()
    host:SetScale(scale)
    Style(text, c)
    text:SetTextColor(c.color[1], c.color[2], c.color[3], 1)
    text:SetText("5")
    local direction = side == "left" and -1 or side == "right" and 1 or 0
    text:ClearAllPoints()
    text:SetPoint("CENTER", button, "CENTER", (direction == 0 and c.topX or direction * c.sideX) / scale, (direction == 0 and c.topY or c.sideY) / scale)
    text:Show()
end
function Timer.GetStats()
    local active, pending = 0, false
    for _, r in ipairs(pool) do if r.active then active = active + 1; pending = pending or r.failed == true end end
    return { active = active, cached = #pool, created = stats.created, failures = stats.failures,
        overflow = stats.overflow, styleWrites = stats.styleWrites, pending = pending, enabled = running }
end
