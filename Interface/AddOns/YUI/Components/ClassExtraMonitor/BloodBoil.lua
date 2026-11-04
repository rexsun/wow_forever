local YUI = _G.YUI
local textStyles
if not (YUI and YUI.IsRetail and YUI.ClassExtraMonitor) then return end
local Monitor, GUI2 = YUI.ClassExtraMonitor, YUI.GUI2
local Core = YUI.Monitor
local Sources = Core and Core.CommonSources
local L = Monitor.L
local LAYOUT_ID = "yui.component.class_extra_monitor.blood_boil"
local MODULE_ID = "component:ClassExtraMonitor:BloodBoil"
local BloodBoil = { id = "bloodBoil", labelKey = "settings.tab_blood_boil", label = "自动血沸",
    specID = 250, classFile = "DEATHKNIGHT", order = 30 }
BloodBoil.defaults = { bloodBoilEnabled = true, bloodBoilIconSize = 42,
    bloodBoilFontSize = 18, bloodBoilGlow = true,
    bloodBoilGlowStyle = "pixel", bloodBoilGlowSize = 1,
    bloodBoilGlowLines = 6, bloodBoilGlowThickness = 2, bloodBoilGlowLength = 18,
    bloodBoilGlowSpeed = 0.30, bloodBoilGlowAlpha = 1, bloodBoilGlowFalloff = 0.18,
    bloodBoilGlowOffsetX = 0, bloodBoilGlowOffsetY = 0, bloodBoilGlowColor = { 1, 248 / 255, 38 / 255, 1 }, -- #FFF826
    bloodBoilManualSound = { kind = "none" }, bloodBoilEndingSound = { kind = "none" } }
local VALID_GLOW_STYLES = { none = true, pixel = true, button = true, autocast = true, proc = true, pulse = true }
local GLOW_FIELDS = {
    { key = "size", field = "bloodBoilGlowSize", min = 0.25, max = 5 },
    { key = "lines", field = "bloodBoilGlowLines", min = 1, max = 20, integer = true },
    { key = "thickness", field = "bloodBoilGlowThickness", min = 1, max = 20, integer = true },
    { key = "length", field = "bloodBoilGlowLength", min = 4, max = 80, integer = true },
    { key = "speed", field = "bloodBoilGlowSpeed", min = 0, max = 3 },
    { key = "alpha", field = "bloodBoilGlowAlpha", min = 0, max = 1 },
    { key = "falloff", field = "bloodBoilGlowFalloff", min = 0, max = 1 },
    { key = "offsetX", field = "bloodBoilGlowOffsetX", min = -1, max = 1 },
    { key = "offsetY", field = "bloodBoilGlowOffsetY", min = -1, max = 1 },
}
local enabled, preview, editing, activeDB, handle, frame, glow
local glowOptionsExpanded = false
local manualSequence, endSequence, sequence, armed
local manualOwner, endingOwner = {}, {}
local iconAppearance = { size = 42 }
local textAppearance = { enabled = true, font = "default", size = 18, outline = "outline", position = "center" }
local lastSize, lastFont, lastStart, lastDuration, lastShown, lastGlow
local events = { "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED" }

local function T(key) return L and L[key] or key end
local function ClampNumber(value, min, max, fallback)
    value = tonumber(value)
    if not value or value ~= value then value = fallback end
    return math.max(min, math.min(max, value))
end
local function NormalizeDB(db)
    db = type(db) == "table" and db or BloodBoil.defaults
    db.bloodBoilEnabled = db.bloodBoilEnabled ~= false
    -- EnsureConfig merges defaults before normalization; the old false switch
    -- must still win over an injected default style.
    local style = db.bloodBoilGlowStyle == "soft" and "pulse" or db.bloodBoilGlowStyle
    db.bloodBoilGlowStyle = db.bloodBoilGlow == false and "none"
        or (VALID_GLOW_STYLES[style] and style or BloodBoil.defaults.bloodBoilGlowStyle)
    db.bloodBoilGlow = db.bloodBoilGlowStyle ~= "none"
    for _, field in ipairs(GLOW_FIELDS) do
        local value = ClampNumber(db[field.field], field.min, field.max, BloodBoil.defaults[field.field])
        db[field.field] = field.integer and math.floor(value + 0.5) or value
    end
    local color = type(db.bloodBoilGlowColor) == "table" and db.bloodBoilGlowColor or {}
    local normalizedColor = {}
    for i = 1, 4 do normalizedColor[i] = ClampNumber(color[i], 0, 1, BloodBoil.defaults.bloodBoilGlowColor[i]) end
    db.bloodBoilGlowColor = normalizedColor
    db.bloodBoilIconSize = math.max(28, math.min(96, tonumber(db.bloodBoilIconSize) or 42))
    db.bloodBoilFontSize = math.max(10, math.min(48, tonumber(db.bloodBoilFontSize) or 18))
    for _, field in ipairs({ "bloodBoilManualSound", "bloodBoilEndingSound" }) do
        db[field] = YUI.NotificationSound:NormalizeSelection(db[field] or { kind = "none" }) or { kind = "none" }
    end
    return db
end
function BloodBoil:NormalizeDB(db) return NormalizeDB(db) end
local function BuildGlowParams(db)
    local params = { style = db.bloodBoilGlowStyle, color = db.bloodBoilGlowColor }
    for _, field in ipairs(GLOW_FIELDS) do params[field.key] = db[field.field] end
    return params
end
local function ApplyGlowAppearance(db)
    if glow and glow.SetGlowParams then glow:SetGlowParams(BuildGlowParams(db)) end
end
local function CancelSound()
    YUI.NotificationSound:CancelOwner(manualOwner)
    YUI.NotificationSound:CancelOwner(endingOwner)
end
local function Icon()
    local spell = YUI.API and YUI.API.Spell
    return spell and spell.GetTexture and spell.GetTexture(50842) or "Interface\\Icons\\Spell_DeathKnight_BloodBoil"
end
local function OpenSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then YUI.Settings:OpenComponentFeature("ClassExtraMonitor") end
end
local function Render(state)
    local db = activeDB or NormalizeDB(Monitor:GetDB())
    local simulated = preview or editing
    if not (simulated or (handle and state and state.available)) then
        if glow and lastGlow ~= false then glow:SetGlowShown(false); lastGlow = false end
        if frame and lastShown ~= false then
            frame:SetCooldown(0, 0); frame:Hide()
            lastShown, lastStart, lastDuration = false, nil, nil
        end
        return
    end
    if not frame then BloodBoil:EnsureWidget() end
    if not frame then return end
    if lastSize ~= db.bloodBoilIconSize then
        lastSize, iconAppearance.size = db.bloodBoilIconSize, db.bloodBoilIconSize
        frame:SetIconAppearance(iconAppearance)
    end
    if lastFont ~= db.bloodBoilFontSize then
        lastFont, textAppearance.size = db.bloodBoilFontSize, db.bloodBoilFontSize
        if textStyles then
            local style,def=YUI.GUI2.FontStyle,textStyles[1]
            textAppearance.font=style.ConfigValue(def,db,"font")
            textAppearance.outline=style.EncodeEffect({outline=style.ConfigValue(def,db,"outline"),shadow=style.ConfigValue(def,db,"shadow")},"camel")
            textAppearance.monochrome=style.ConfigValue(def,db,"monochrome")
            textAppearance.maxSize=48
            textAppearance.color={style.ConfigColor(def,db)}
        end
        frame:SetCooldownTextAppearance(textAppearance)
    end
    local start, duration = simulated and GetTime() or state.startTime, simulated and 3 or state.duration
    if start ~= lastStart or duration ~= lastDuration then
        frame:SetCooldown(start, duration); lastStart, lastDuration = start, duration
    end
    if glow and lastGlow ~= db.bloodBoilGlow then glow:SetGlowShown(db.bloodBoilGlow); lastGlow = db.bloodBoilGlow end
    if lastShown ~= true then frame:Show(); lastShown = true end
end
function BloodBoil:EnsureWidget()
    if frame then return frame end
    if not (GUI2 and GUI2.Application and UIParent) then return end
    frame = GUI2.Application:CreateCooldownIcon(UIParent, { size = 42, icon = Icon(), shape = "rounded" })
    frame:SetPoint("CENTER", UIParent, "CENTER", -50, -66)
    frame:EnableMouse(false)
    frame:Hide()
    glow = GUI2.CreateGlow and GUI2:CreateGlow(frame, BuildGlowParams(activeDB or NormalizeDB(Monitor:GetDB())))
    if glow then glow:SetGlowShown(false) end
    if YUI.Layout and YUI.Layout.RegisterFrame then
        YUI.Layout:RegisterFrame(LAYOUT_ID, {
            frame = frame, title = T("settings.tab_blood_boil"), category = "component",
            defaultPlacement = function() return { version = 1,
                anchor = { point = "CENTER", relative = "UIParent", relativePoint = "CENTER" },
                offset = { x = -50, y = -66 } } end,
            movable = true, snap = true, anchorTargets = { "UIParent" }, minWidth = 28, minHeight = 28,
            isEnabled = function() return (enabled or preview or editing) and (activeDB or Monitor:GetDB()).bloodBoilEnabled end,
            getMoverBounds = function() local size = (activeDB or Monitor:GetDB()).bloodBoilIconSize; return size, size end,
            openPluginSettings = OpenSettings,
            onEnterEditMode = function() editing = true; Render() end,
            onHideEditModePreview = function() editing = false; Render(handle and handle.source.state) end,
            onExitEditMode = function() editing, preview = false, false; Render(handle and handle.source.state) end,
        })
    end
    return frame
end
local function PlaySegment(state, segment)
    local manual = segment == "manual"
    local selection = activeDB[manual and "bloodBoilManualSound" or "bloodBoilEndingSound"]
    if selection.kind == "none" then return end
    return YUI.NotificationSound:Play(manual and manualOwner or endingOwner,
            "blood-boil:" .. segment .. ":" .. tostring(manual and state.manualSequence or state.endSequence), selection,
            { nativeSound = "RAID_WARNING", defaultChannel = "Master" })
end
function BloodBoil:OnSource(state)
    local oldManual, oldEnding, oldSequence = manualSequence, endSequence, sequence
    manualSequence, endSequence, sequence = state.manualSequence, state.endSequence, state.sequence
    if state.phase == "reset" then armed = nil; CancelSound()
    else
        if oldManual ~= nil and manualSequence ~= oldManual then PlaySegment(state, "manual") end
        if oldEnding ~= nil and endSequence ~= oldEnding and armed then PlaySegment(state, "ending") end
        if not state.available then armed = nil
        elseif oldSequence ~= nil and sequence ~= oldSequence then armed = true end
    end
    Render(state)
end
local function Release()
    if handle then Core:ReleaseSource(handle); handle = nil end
    manualSequence, endSequence, sequence, armed = nil, nil, nil, nil
    CancelSound()
end
local function Applicable()
    local talent = YUI.API and YUI.API.Talent
    local get = talent and (talent.GetCurrentConfigurationSpecializationInfo or talent.GetCurrentSpecializationInfo)
    local info = get and get()
    return type(info) == "table" and info.specID == 250 and info.classFile == "DEATHKNIGHT"
end
function BloodBoil:RefreshRuntime(db)
    Monitor:NotifySoundSettingsChanged()
    db = NormalizeDB(db or Monitor:GetDB())
    if activeDB ~= db then Release() end
    activeDB = db
    lastFont = nil
    if enabled and db.bloodBoilEnabled and Applicable() and Sources then
        if not handle then
            local descriptor = Sources:DescribeBoilingPoint()
            if descriptor then
                handle = Core:AcquireSource(self, descriptor.key, descriptor.type, descriptor.params, "OnSource")
                if handle then
                    local state = handle.source.state
                    manualSequence, endSequence, sequence = state.manualSequence, state.endSequence, state.sequence
                end
            end
        end
    else Release() end
    ApplyGlowAppearance(db)
    Render(handle and handle.source.state)
    if YUI.Layout and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(LAYOUT_ID) end
end
function BloodBoil:OnRefreshEvent() self:RefreshRuntime() end
function BloodBoil:OnFeatureToggle(value, db)
    enabled = value == true
    if YUI.Event then
        YUI.Event:OffOwner(self)
        if enabled then
            for _, event in ipairs(events) do YUI.Event:On(event, "OnRefreshEvent", self, { moduleId = MODULE_ID }) end
        end
    end
    if not enabled then preview, editing = false, false end
    self:RefreshRuntime(db)
end
function BloodBoil:OnSettingsLeave() preview = false; Render(handle and handle.source.state) end
function BloodBoil:GetDiagnostics()
    return { enabled = enabled == true, subscribed = handle ~= nil, armed = armed == true,
        preview = preview == true or editing == true, visible = lastShown == true }
end
local function BuildGlowStyleOptions()
    local options = {}
    for _, style in ipairs({ "none", "pixel", "button", "autocast", "proc", "pulse" }) do
        options[#options + 1] = { text = T("settings.glow_style_" .. style), value = style }
    end
    return options
end
local function BuildGlowDefaultsByStyle()
    local defaults = {}
    for _, style in ipairs({ "pixel", "button", "autocast", "proc", "pulse" }) do
        local value = BuildGlowParams(BloodBoil.defaults)
        value.style = style
        if style ~= "pixel" then value.lines = style == "autocast" and 4 or 1 end
        defaults[style] = value
    end
    return defaults
end
local function BuildGlowControlLabels()
    return {
        type = T("settings.glow_type"), expand = T("settings.glow_params"),
        collapse = T("settings.glow_params"), params = T("settings.glow_params"),
        paramsDetail = T("settings.glow_params_detail"), noParams = T("settings.glow_no_params"),
        none = T("settings.glow_style_none"), noneSummary = T("settings.glow_style_none"),
        color = T("settings.glow_color"), size = T("settings.glow_size"),
        lines = T("settings.glow_lines"), thickness = T("settings.glow_thickness"),
        length = T("settings.glow_length"), speed = T("settings.glow_speed"),
        alpha = T("settings.glow_alpha"), falloff = T("settings.glow_falloff"),
        offsetX = T("settings.glow_offset_x"), offsetY = T("settings.glow_offset_y"),
        reset = T("settings.glow_reset"), summaryLines = T("settings.glow_summary_lines"),
        summaryThickness = T("settings.glow_summary_thickness"), summaryLength = T("settings.glow_summary_length"),
        summarySpeed = T("settings.glow_summary_speed"), summarySize = T("settings.glow_summary_size"),
        summaryAlpha = T("settings.glow_summary_alpha"), summaryOffset = T("settings.glow_summary_offset"),
        summaryColor = T("settings.glow_summary_color"),
    }
end
function BloodBoil:BuildOptions(db)
    db = NormalizeDB(db or Monitor:GetDB())
    local options = {}
    Monitor:AppendIconDivider(options, T("settings.tab_blood_boil"), Icon, 620)
    options[#options + 1] = { type = "checkbox", settingsToggle = self.id, label = T("settings.devourer_enabled"),
        get = function() return db.bloodBoilEnabled end,
        set = function(value) db.bloodBoilEnabled = value == true; self:RefreshRuntime(db) end }
    options[#options + 1] = { type = "button", text = preview and T("settings.preview_stop") or T("settings.preview"), onClick = function(button)
        activeDB, preview = db, not preview
        ApplyGlowAppearance(db)
        Render(handle and handle.source.state)
        if button and button.SetText then button:SetText(preview and T("settings.preview_stop") or T("settings.preview")) end
    end }
    options[#options + 1] = { type = "text", label = T("settings.blood_boil_help") }
    for _, item in ipairs({ { "bloodBoilManualSound", "settings.blood_boil_manual_sound" },
        { "bloodBoilEndingSound", "settings.blood_boil_ending_sound" } }) do
        local field = item[1]
        options[#options + 1] = { type = "notificationSound", label = T(item[2]), span = "full",
            nativeSound = "RAID_WARNING", default = { kind = "none" },
            get = function() return db[field] end,
            set = function(value)
                YUI.NotificationSound:CancelOwner(field == "bloodBoilManualSound" and manualOwner or endingOwner)
                db[field] = YUI.NotificationSound:NormalizeSelection(value) or { kind = "none" }
                Monitor:NotifySoundSettingsChanged()
            end }
    end
    options[#options + 1] = { type = "divider", label = T("settings.appearance") }
    for _, item in ipairs({ { "bloodBoilIconSize", "settings.icon_size", 28, 96 },
        { "bloodBoilFontSize", "settings.timer_font_size", 10, 48 } }) do
        local field = item[1]
        options[#options + 1] = { type = "slider", fontStyleSource=field, label = T(item[2]), min = item[3], max = item[4], step = 1,
            get = function() return db[field] end,
            set = function(value) db[field] = value; self:RefreshRuntime(db) end }
    end
    options[#options + 1] = { type = "divider", label = T("settings.glow") }
    options[#options + 1] = {
        type = "glow", label = T("settings.glow"), rowWidth = 620,
        width = 176, controlWidth = 176, panelWidth = 498,
        labelWidth = 112, gap = 10, inputWidth = 56,
        styleOptions = BuildGlowStyleOptions, labels = BuildGlowControlLabels(),
        default = BuildGlowParams(BloodBoil.defaults), defaultsByStyle = BuildGlowDefaultsByStyle,
        applyStyleDefaultsOnChange = true,
        get = function() return BuildGlowParams(db) end,
        set = function(value)
            value = type(value) == "table" and value or {}
            db.bloodBoilGlowStyle = value.style
            db.bloodBoilGlow = value.style ~= "none"
            db.bloodBoilGlowColor = value.color
            for _, field in ipairs(GLOW_FIELDS) do db[field.field] = value[field.key] end
            self:RefreshRuntime(db)
        end,
        getExpanded = function() return glowOptionsExpanded end,
        setExpanded = function(value) glowOptionsExpanded = value == true end,
        onRequestRefresh = function()
            local feature = YUI.Components and YUI.Components.features and YUI.Components.features.ClassExtraMonitor
            if feature and feature.RefreshCurrentModule then feature.RefreshCurrentModule() end
        end,
    }
    -- Use the same responsive field renderer as the existing class monitors.
    local grouped, fields = {}, {}
    local function FlushFields()
        if #fields == 0 then return end
        local group = fields
        grouped[#grouped + 1] = { type = "custom", retainedFields = group, width = 620,
            render = function(parent, x, y, width)
                local _, gridWidth, gridHeight = YUI.Settings:RenderAlignedFields(parent, {
                    x = x, y = y, width = math.min(width or 620, 620), columns = 2,
                    labelPosition = "top", columnGap = 24, labelWidth = 112, labelGap = 10,
                    bodyWidth = 176, valueWidth = 56, valueGap = 10, rowHeight = 32, rowGap = 10,
                    fields = group,
                })
                return gridWidth, gridHeight
            end }
        fields = {}
    end
    for _, item in ipairs(options) do
        if item.type == "custom" or item.type == "divider" or item.type == "text" or item.type == "glow" then
            FlushFields(); grouped[#grouped + 1] = item
        else fields[#fields + 1] = item end
    end
    FlushFields()
    if YUI.GUI2 and YUI.GUI2.FontStyle and YUI.GUI2.FontStyle.MergeOptions then
        YUI.GUI2.FontStyle:MergeOptions(grouped, {{key="class_blood:timer",label=T("settings.timer_text"),sources={"bloodBoilFontSize"}}})
    end
    return grouped
end
Monitor:RegisterSubFeature(BloodBoil)

if YUI.GUI2 and YUI.GUI2.FontStyle and YUI.GUI2.FontStyle.RegisterConfig then
    local style=YUI.GUI2.FontStyle
    textStyles={
        style.FullConfig({id="timer",label=function() return T("settings.timer_text") end,fields={size="bloodBoilFontSize"},defaults=BloodBoil.defaults,minSize=10,maxSize=48},"bloodBoil",{color=nil})
    }
    style:RegisterConfig("class_blood", {
        label=function() return T("settings.tab_blood_boil") end,
        get=function() return style.ComponentConfig(Monitor.PRODUCT_ID,Monitor.CONFIG_KEY) end,
        refresh=function(db) if enabled or preview or editing then BloodBoil:RefreshRuntime(db) end end,
        targets=textStyles,
    })
end
