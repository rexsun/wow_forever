local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local GUI2 = YUI.GUI2
local Locale = YUI.Locale
local L = Locale and Locale:Get("YChat") or {}
local format = string.format
local tostring = tostring
local type = type

local DevPanel = {}
YChat.DevPanel = DevPanel

local function T(key, fallback)
    local value = L and L[key]
    if type(value) == "string" and value ~= "" then return value end
    return fallback
end

local function StateLabel(enabled)
    if enabled then return T("command.state.enabled", "enabled") end
    return T("command.state.disabled", "disabled")
end

local function GetStat(field, fallback)
    local stats = YChat.Stats
    if stats and stats.Get then
        local value = stats:Get(field)
        if value ~= nil then return value end
    end
    return fallback
end

local function ShadowEnabled()
    return YChat.IsShadowEnabled and YChat:IsShadowEnabled() == true
end

local function ProbeEnabled()
    return YChat.IsProbeEnabled and YChat:IsProbeEnabled() == true
end

local function RefreshPanel()
    DevPanel:Refresh()
end

local function ReportAction(ok, reason)
    if not ok and YUI.Print then
        local message
        if reason == "native-restore-pending" then
            message = T(
                "command.restore.pending",
                "Native layout restoration is awaiting confirmation; the operation will finish after the next native layout pass."
            )
        else
            message = format(T("command.failed", "Operation failed: %s"), tostring(reason or "unknown"))
        end
        YUI:Print("|cff66c6ffYChat:|r", message)
    end
    RefreshPanel()
end

local function ToggleShadow()
    local enabled = not ShadowEnabled()
    if not YChat.SetShadowEnabled then return ReportAction(false, "lifecycle-entry-unavailable") end
    ReportAction(YChat:SetShadowEnabled(enabled, "developer-panel"))
end

local function ToggleProbe()
    local enabled = not ProbeEnabled()
    if not YChat.SetProbeEnabled then return ReportAction(false, "lifecycle-entry-unavailable") end
    ReportAction(YChat:SetProbeEnabled(enabled, "developer-panel"))
end

local function RestoreNative()
    if not YChat.RestoreNative then return ReportAction(false, "lifecycle-entry-unavailable") end
    ReportAction(YChat:RestoreNative("developer-panel"))
end

local function ResetStats()
    if not YChat.ResetDiagnostics then return ReportAction(false, "diagnostics-entry-unavailable") end
    ReportAction(YChat:ResetDiagnostics("developer-panel"))
end

local function HidePanel()
    DevPanel:Hide()
end

local function MakeButton(parent, text, width, onClick)
    if GUI2.Form and GUI2.Form.CreateButton then
        return GUI2.Form:CreateButton(parent, {
            text = text,
            width = width,
            height = 28,
            onClick = onClick,
        })
    end
    local button = GUI2:CreateButton(parent, text, width, 28)
    button:SetScript("OnClick", onClick)
    return button
end

function DevPanel:Ensure()
    if self.frame then return self.frame end
    if not GUI2 or not GUI2.CreatePanel or not GUI2.CreateText then return nil end

    local frame = GUI2:CreatePanel(_G.UIParent, {
        name = "YUI_YChatStage0Panel",
        width = 520,
        height = 356,
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
    })
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = GUI2:CreateText(frame, T("devpanel.title", "YChat · Stage 0 validation"), "font.size.xl", "color.text.heading")
    title:SetPoint("TOPLEFT", 18, -16)

    local subtitle = GUI2:CreateText(frame, T("devpanel.subtitle", "Developer-only; this is not a player settings page."), "font.size.sm", "color.text.secondary")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

    local status = GUI2:CreateText(frame, "", "font.size.md", "color.text.primary", "LEFT")
    status:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    status:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    status:SetJustifyV("TOP")
    status:SetWordWrap(true)
    status:SetHeight(112)

    local warning = GUI2:CreateText(frame, T(
        "devpanel.warning",
        "Shadow is invisible. Probe changes the real chat frame; disable Blizzard timestamps before checking the two columns. Any mismatch restores native display."
    ), "font.size.sm", "color.text.secondary", "LEFT")
    warning:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)
    warning:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    warning:SetJustifyV("TOP")
    warning:SetWordWrap(true)
    warning:SetHeight(54)

    local shadowButton = MakeButton(frame, T("devpanel.button.shadow", "Toggle shadow"), 88, ToggleShadow)
    shadowButton:SetPoint("BOTTOMLEFT", 18, 18)
    local probeButton = MakeButton(frame, T("devpanel.button.probe", "Toggle probe"), 88, ToggleProbe)
    probeButton:SetPoint("LEFT", shadowButton, "RIGHT", 8, 0)
    local restoreButton = MakeButton(frame, T("devpanel.button.restore", "Restore native"), 88, RestoreNative)
    restoreButton:SetPoint("LEFT", probeButton, "RIGHT", 8, 0)
    local resetButton = MakeButton(frame, T("devpanel.button.reset", "Reset counters"), 88, ResetStats)
    resetButton:SetPoint("LEFT", restoreButton, "RIGHT", 8, 0)
    local refreshButton = MakeButton(frame, T("devpanel.button.refresh", "Refresh"), 88, RefreshPanel)
    refreshButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)

    local closeButton = MakeButton(frame, T("devpanel.button.close", "Close"), 72, HidePanel)
    closeButton:SetPoint("TOPRIGHT", -14, -14)

    self.frame = frame
    self.statusText = status
    self.shadowButton = shadowButton
    self.probeButton = probeButton
    frame:Hide()
    return frame
end

function DevPanel:Refresh()
    local frame = self.frame
    if not frame or not self.statusText then return false end

    if YChat.RefreshRuntimeGauges then YChat:RefreshRuntimeGauges() end
    local shadowEnabled = ShadowEnabled()
    local probeEnabled = ProbeEnabled()
    local restriction = tostring(GetStat("restrictionState", "UNKNOWN"))
    local quality = tostring(GetStat("qualityState", "Q3"))
    self.statusText:SetText(format(
        T(
            "devpanel.status",
            "Shadow: %s    Probe: %s    Restriction: %s    Quality: %s\nComparisons: %d    Mismatches: %d    Hooks: %d\nDrivers: %d    Tickers: %d    Timers: %d    Animations: %d\nQ3 fallbacks: %d    Restores: %d    Cleanup leaks: %d"
        ),
        StateLabel(shadowEnabled),
        StateLabel(probeEnabled),
        restriction,
        quality,
        GetStat("shadowComparisons", 0),
        GetStat("shadowMismatches", 0),
        GetStat("messageHooks", 0),
        GetStat("activeDrivers", 0),
        GetStat("activeTickers", 0),
        GetStat("activeTimers", 0),
        GetStat("activeAnimations", 0),
        GetStat("q3Fallbacks", 0),
        GetStat("q3Restores", 0),
        GetStat("cleanupLeaks", 0)
    ))

    local shadowLabel = shadowEnabled
        and T("devpanel.button.shadow_off", "Stop shadow")
        or T("devpanel.button.shadow_on", "Start shadow")
    if self.shadowButton and self.shadowButton.SetText then
        self.shadowButton:SetText(shadowLabel)
    elseif self.shadowButton and self.shadowButton.text then
        self.shadowButton.text:SetText(shadowLabel)
    end
    local probeLabel = probeEnabled
        and T("devpanel.button.probe_off", "Stop probe")
        or T("devpanel.button.probe_on", "Start probe")
    if self.probeButton and self.probeButton.SetText then
        self.probeButton:SetText(probeLabel)
    elseif self.probeButton and self.probeButton.text then
        self.probeButton.text:SetText(probeLabel)
    end
    return true
end

function DevPanel:Show()
    local frame = self:Ensure()
    if not frame then return false, "gui2-unavailable" end
    self:Refresh()
    frame:Show()
    frame:Raise()
    return true
end

function DevPanel:Hide()
    if self.frame then self.frame:Hide() end
    return true
end

function DevPanel:Toggle()
    local frame = self:Ensure()
    if not frame then return false, "gui2-unavailable" end
    if frame:IsShown() then return self:Hide() end
    return self:Show()
end
