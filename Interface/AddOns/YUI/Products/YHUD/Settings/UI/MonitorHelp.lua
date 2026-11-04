local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
local UI = HUD and HUD.DesignerUI
if not UI then return end

local GUI = YUI.GUI2
local Help = {}
UI.MonitorHelp = Help

local WIDTH, SIZE, GAP = 280, 46, 10
local CAPTIONS = {
    auraTimer = { "aura_time", "cooldown_time" },
    auraHighlight = { "gold_on", "gold_off" },
    inactiveDesaturate = { "gray_on", "gray_off" },
    nativeProc = { "triggered", "untriggered" },
    nativeCombat = { "combat_on", "combat_off" },
    cooldownSwipe = { "off", "forward", "reverse" },
}
local GROUP_SWIPE_CAPTIONS = { "swipe_on", "off" }

local function Text(key)
    return HUD:T("designer.monitor.help." .. key)
end

local function ResolveSelection(owner)
    local designer = HUD.Designer
    local profile = designer:GetProfile() or {}
    local monitor = owner.scope == "single" and designer:GetSelectedMonitor() or nil
    local effects = monitor and monitor.stateEffects or {}
    local native = HUD:GetEffectiveNativeProcGlow(profile, monitor)
    local state = { native = native, activation = HUD:GetAuraActivationStyle(profile) }
    local kind = owner.kind
    if kind == "cooldownSwipe" then
        local session = designer:GetSession()
        local groupId = monitor and monitor.groupId or session and session.selectedGroupId
        local group = HUD:GetIconGroupStyle(profile, groupId)
        local mode = monitor and monitor.appearanceOverride and monitor.appearanceOverride.cooldownSwipeMode
        local entry = monitor and profile.entries and profile.entries[monitor.entryKey]
        local enabled, reverse = HUD:ResolveMonitorCooldownSwipe(mode, group.cooldownSwipe,
            HUD:GetEntrySemantic(entry) == "buff")
        state.selected = owner.scope == "group" and (enabled and 1 or 2)
            or (not enabled and 1 or reverse and 3 or 2)
        state.inherited = mode == nil
    elseif kind == "nativeProc" or kind == "nativeCombat" then
        state.selected = kind == "nativeProc" and 1 or (native.combatOnly and 1 or 2)
        state.inherited = not (monitor and monitor.nativeProcGlowOverride)
    else
        local field = kind == "auraTimer" and "skillAuraDisplay"
            or kind == "auraHighlight" and "skillAuraHighlight" or "inactiveDesaturate"
        local enabled = kind ~= "inactiveDesaturate"
        if profile.cdm and type(profile.cdm[field]) == "boolean" then enabled = profile.cdm[field] end
        local override = effects[kind]
        if kind == "auraTimer" and override == nil and monitor then
            override = monitor.skillAuraDisplayOverride
        end
        state.inherited = type(override) ~= "boolean"
        if not state.inherited then enabled = override end
        state.selected = enabled and 1 or 2
    end
    return state
end

function Help:SetCaption(index, key)
    local caption = Text(key)
    if self.selection.selected == index then caption = string.format(Text("current"), caption) end
    self.samples[index].caption:SetText(caption)
end

function Help:Hide(owner)
    if owner and self.owner ~= owner then return end
    self.generation = (self.generation or 0) + 1
    self.owner = nil
    self.selection, self.castStart, self.timerPhase = nil, nil, nil
    if self.timer then self.timer:Cancel(); self.timer = nil end
    for _, sample in ipairs(self.samples or {}) do
        sample.cooldown.helpDuration = nil
        sample.cooldown:Clear()
        if sample.procGlow then GUI:SetManagedProcGlowShown(sample.procGlow, false) end
        if sample.customGlow then sample.customGlow:SetGlowShown(false) end
    end
    if self.panel then
        self.panel:Hide()
        self.panel:ClearAllPoints()
    end
end

function Help:EnsurePanel()
    if self.panel then return end
    local panel = GUI:CreatePanel(UIParent, {
        width = WIDTH, height = 210, surface = "color.surface.popup",
        border = "color.popup.border", shadow = true,
    })
    panel:Hide()
    panel:SetFrameStrata("TOOLTIP")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(false)
    self.panel = panel
    self.heading = GUI:CreateText(panel, "", "font.size.md", "color.text.heading", "CENTER")
    self.heading:SetPoint("TOPLEFT", 12, -12)
    self.heading:SetWidth(WIDTH - 24)
    self.heading:SetWordWrap(true)
    self.context = GUI:CreateText(panel, "", "font.size.sm", "color.text.secondary", "CENTER")
    self.context:SetWidth(WIDTH - 24)
    self.context:SetWordWrap(true)
    self.body = GUI:CreateText(panel, "", "font.size.sm", "color.text.primary", "LEFT")
    self.body:SetWidth(WIDTH - 24)
    self.body:SetWordWrap(true)
    self.footer = GUI:CreateText(panel, "", "font.size.sm", "color.text.secondary", "LEFT")
    self.footer:SetWidth(WIDTH - 24)
    self.footer:SetWordWrap(true)
    self.samples = {}
    for index = 1, 3 do
        local sample = GUI.Application:CreateCooldownIcon(panel, {
            size = SIZE, icon = 135846, shape = "square", border = "thin", variant = "bare",
        })
        sample:EnableMouse(false)
        sample.cooldown:SetDrawBling(false)
        sample.cooldown:SetScript("OnCooldownDone", function(cooldown)
            if self.owner and panel:IsShown() and cooldown.helpDuration then self:OnTimerDone(index) end
        end)
        sample.caption = GUI:CreateText(panel, "", "font.size.sm", "color.text.primary", "CENTER")
        sample.caption:SetPoint("TOP", sample, "BOTTOM", 0, -8)
        sample.caption:SetWordWrap(true)
        self.samples[index] = sample
    end
    panel:HookScript("OnHide", function() if self.owner then self:Hide() end end)
end

local function StartTimer(sample, duration, reverse, gold, start)
    local cooldown = sample.cooldown
    cooldown:SetDrawSwipe(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetReverse(reverse == true)
    local constants = _G.CooldownViewerConstants
    local color = constants and (gold and constants.ITEM_AURA_COLOR or constants.ITEM_COOLDOWN_COLOR)
    if color then
        cooldown:SetSwipeColor(color.r, color.g, color.b, color.a)
    elseif gold then
        local r, g, b = GUI:GetColor("color.text.heading")
        cooldown:SetSwipeColor(r, g, b, 0.7)
    else
        cooldown:SetSwipeColor(0, 0, 0, 0.7)
    end
    cooldown.helpDuration = duration
    cooldown:SetCooldown(start, duration)
end

local function ShowDefaultGlow(sample)
    if not sample.procGlow then
        sample.procGlow = GUI:CreateManagedProcGlow(sample, "square", SIZE, SIZE,
            sample:GetFrameLevel() + 10, "TOOLTIP", "square")
    end
    GUI:SetManagedProcGlowShown(sample.procGlow, true)
end

local function ShowSelectedGlow(sample, config)
    if config.mode == "disabled" then return end
    if config.mode ~= "custom" then ShowDefaultGlow(sample); return end
    if not sample.customGlow then
        sample.customGlow = GUI:CreateGlow(sample, {
            hidden = true, trustedFrameLevel = sample:GetFrameLevel() + 10,
            trustedFrameStrata = "TOOLTIP",
        })
    end
    local appearance = config.appearance
    sample.customGlow:SetGlowParams(appearance)
    if sample.customGlow.SetGlowShape then sample.customGlow:SetGlowShape("square", "square") end
    sample.customGlow:SetGlowShown(true)
end

function Help:OnTimerDone(index)
    if self.owner.kind == "auraTimer" then
        if index == 1 and self.timerPhase == "aura" and GetTime() >= self.castStart + 10 then
            self.timerPhase = "cooldown"
            StartTimer(self.samples[1], 30, false, false, self.castStart)
            self.samples[1].cooldown:SetDrawSwipe(false)
            self:SetCaption(1, "aura_ended")
        elseif index == 2 and GetTime() >= self.castStart + 30 then
            self:RenderSamples(self.owner.kind, self.owner.scope, GetTime())
        end
    elseif index == 1 then
        self:RenderSamples(self.owner.kind, self.owner.scope, GetTime())
    end
end

function Help:RenderSamples(kind, scope, cycleStart)
    for _, sample in ipairs(self.samples) do
        sample.icon:SetDesaturated(false)
        sample.cooldown:SetHideCountdownNumbers(true)
    end
    local first, second = self.samples[1], self.samples[2]
    local start = cycleStart or GetTime() - 3
    if kind == "auraTimer" then
        self.castStart, self.timerPhase = cycleStart or GetTime() - 5, "aura"
        StartTimer(first, 10, false, false, self.castStart)
        StartTimer(second, 30, false, false, self.castStart)
        self:SetCaption(1, "aura_time")
        first.cooldown:SetDrawSwipe(false)
        second.cooldown:SetDrawSwipe(false)
    elseif kind == "auraHighlight" then
        local gold = self.selection.activation.mode ~= "custom"
        start = cycleStart or GetTime() - 1
        StartTimer(first, 8, not gold, gold, start)
        StartTimer(second, 8, true, false, start)
        if not gold then ShowSelectedGlow(first, self.selection.activation) end
    elseif kind == "inactiveDesaturate" then
        first.icon:SetDesaturated(true)
    elseif kind == "cooldownSwipe" then
        if scope == "group" then
            StartTimer(first, 8, false, false, start)
            StartTimer(second, 8, false, false, start)
            second.cooldown:SetDrawSwipe(false)
        else
            for index, sample in ipairs(self.samples) do
                StartTimer(sample, 8, index == 3, false, start)
            end
            first.cooldown:SetDrawSwipe(false)
        end
    elseif kind == "nativeProc" then
        ShowSelectedGlow(first, self.selection.native)
    elseif kind == "nativeCombat" then
        ShowSelectedGlow(second, self.selection.native)
    end
end

function Help:Show(owner)
    if self.owner ~= owner or not owner:IsVisible() or not owner.label:IsVisible() then return end
    self:EnsurePanel()
    self.selection = ResolveSelection(owner)
    if YUI.HideGameTooltip then YUI.HideGameTooltip() end
    local panel, dock = self.panel, UI.panel
    panel:SetScale(dock:GetEffectiveScale() / UIParent:GetEffectiveScale())
    self.heading:SetText(owner.label:GetText())
    self.heading:SetHeight(0)
    local config = owner.kind == "auraHighlight" and self.selection.activation
        or (owner.kind == "nativeProc" or owner.kind == "nativeCombat") and self.selection.native
    local context = Text("context." .. owner.kind)
    if config then
        local style = config.mode == "disabled" and HUD:T("designer.glow.native_disabled")
            or config.mode == "custom" and HUD:T("designer.glow.style." .. config.appearance.style)
            or owner.kind == "auraHighlight" and HUD:T("designer.monitor.activation_gold") or Text("native_default")
        context = context .. "\n" .. string.format(Text("style"), style)
    end
    self.context:SetText(context)
    self.context:SetHeight(0)
    self.context:ClearAllPoints()
    self.context:SetPoint("TOPLEFT", self.heading, "BOTTOMLEFT", 0, -8)
    local sampleY = 34 + self.heading:GetStringHeight() + self.context:GetStringHeight()
    local groupSwipe = owner.kind == "cooldownSwipe" and owner.scope == "group"
    local captions = groupSwipe and GROUP_SWIPE_CAPTIONS or CAPTIONS[owner.kind]
    local step = (WIDTH - 24) / #captions
    local captionHeight = 0
    for index, sample in ipairs(self.samples) do
        sample:SetShown(index <= #captions)
        sample.caption:SetShown(index <= #captions)
        if index <= #captions then
            sample:ClearAllPoints()
            sample:SetPoint("TOP", panel, "TOPLEFT", 12 + step * (index - 0.5), -sampleY)
            sample.caption:SetWidth(step - 8)
            local key = captions[index]
            if owner.kind == "auraHighlight" and self.selection.activation.mode == "custom" and index == 1 then
                key = "glow_on"
            end
            self:SetCaption(index, key)
            sample.caption:SetHeight(0)
            captionHeight = math.max(captionHeight, sample.caption:GetStringHeight())
        end
    end
    local bodyKey = groupSwipe and "cooldownSwipe_group" or owner.kind
    if owner.kind == "auraHighlight" and self.selection.activation.mode == "custom" then bodyKey = "auraHighlight_glow" end
    self.body:SetText(Text(bodyKey))
    self.body:SetHeight(0)
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(sampleY + SIZE + 22 + captionHeight))
    local footer = owner.kind == "auraHighlight" and owner.scope == "global" and "global_activation" or owner.scope
    if owner.scope == "single" then
        footer = owner.kind == "cooldownSwipe" and (self.selection.inherited and "inherit_group" or "override_group")
            or (self.selection.inherited and "inherit_global" or "override_global")
        if owner.kind == "auraHighlight" and not self.selection.inherited then footer = "override_activation" end
    end
    self.footer:SetText(Text(footer))
    self.footer:SetHeight(0)
    self.footer:ClearAllPoints()
    self.footer:SetPoint("TOPLEFT", self.body, "BOTTOMLEFT", 0, -10)
    panel:SetHeight(sampleY + SIZE + 22 + captionHeight
        + self.body:GetStringHeight() + 10 + self.footer:GetStringHeight() + 12)

    -- All geometry belongs to ordinary settings frames; compare physical pixels across UI scales.
    local dockScale, screenScale = dock:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local left = dock:GetLeft() * dockScale
    local right = UIParent:GetWidth() * screenScale - dock:GetRight() * dockScale
    local useRight = right >= (WIDTH + GAP) * dockScale or right >= left
    local offsetY = (owner:GetTop() * owner:GetEffectiveScale() - dock:GetTop() * dockScale) / dockScale
    panel:ClearAllPoints()
    panel:SetPoint(useRight and "TOPLEFT" or "TOPRIGHT", dock,
        useRight and "TOPRIGHT" or "TOPLEFT", useRight and GAP or -GAP, offsetY)
    panel:Show()
    self:RenderSamples(owner.kind, owner.scope)
end

function Help:Queue(owner)
    self:Hide()
    if not owner.label:IsVisible() then return end
    self.owner = owner
    local generation = self.generation
    self.timer = C_Timer.NewTimer(0.2, function()
        if self.generation ~= generation then return end
        self.timer = nil
        self:Show(owner)
    end)
end

function Help:Bind(label, kind, scope)
    if label.yhudMonitorHelp then return label.yhudMonitorHelp end
    local region = GUI:CreateFrame(label:GetParent(), { mouse = false })
    region.label, region.kind, region.scope = label, kind, scope
    region:SetPoint("TOPLEFT", label, "TOPLEFT", -2, 3)
    region:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 2, -3)
    region:SetMouseClickEnabled(false)
    region:SetMouseMotionEnabled(true)
    region:SetScript("OnEnter", function(owner) self:Queue(owner) end)
    region:SetScript("OnLeave", function(owner) self:Hide(owner) end)
    region:SetScript("OnHide", function(owner) self:Hide(owner) end)
    local function SyncVisibility()
        region:SetShown(label:IsShown())
    end
    -- FontStrings have no frame scripts; follow only these owned labels' visibility methods.
    hooksecurefunc(label, "Show", SyncVisibility)
    hooksecurefunc(label, "Hide", SyncVisibility)
    hooksecurefunc(label, "SetShown", SyncVisibility)
    hooksecurefunc(label, "SetParent", function()
        self:Hide(region)
        region:SetParent(label:GetParent())
        SyncVisibility()
    end)
    SyncVisibility()
    label.yhudMonitorHelp = region
    if UI.inspectorScroll and not self.scrollBound then
        self.scrollBound = true
        UI.inspectorScroll:HookScript("OnVerticalScroll", function() self:Hide() end)
        UI.inspectorScroll:HookScript("OnMouseWheel", function() self:Hide() end)
    end
    return region
end
