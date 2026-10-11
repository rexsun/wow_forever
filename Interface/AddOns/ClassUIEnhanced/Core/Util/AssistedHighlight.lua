---@class private
local _, private = ...

-- ClassUIEnhanced — Assisted Highlight
--
-- Draws Blizzard's rotation-helper marching-ants animation
-- (`RotationHelper_Ants_Flipbook_2x`) on whichever tracker button
-- `C_AssistedCombat.GetNextCastSpell()` currently suggests. Shared across
-- every registered tracker so the singleton manager hook fires once and fans
-- out to all of them.
--
-- Usage from a tracker component:
--     private.AssistedHighlight.RegisterButtons(name, getSettings, getButtonsFn)
-- `getSettings` must return a table exposing boolean `rotation_highlight`.
-- Registration is keyed by COMPONENT name, not by CDM viewer key — nothing
-- here reads a CooldownViewer child any more.

---@class AssistedHighlightModule
---@field RegisterButtons fun(name: string, getSettings: fun(): table, getButtonsFn: fun(): table<number, frame>)
---@field UpdateAll fun()
---@field UpdateComponent fun(name: string)
---@field OnSettingChanged fun()
---@field OfferBlizzardHighlightOff fun()
local AssistedHighlight = {}
private.AssistedHighlight = AssistedHighlight

local FLIPBOOK_ATLAS = "RotationHelper_Ants_Flipbook_2x"
local FLIPBOOK_ROWS = 6
local FLIPBOOK_COLUMNS = 5
local FLIPBOOK_FRAMES = 30
local FLIPBOOK_DURATION = 1.0
local FLIPBOOK_INSET = 12

local CVAR_ASSISTED_HIGHLIGHT = "assistedCombatHighlight"

local MODULE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TALENT_UPDATE",
    "SPELLS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "UPDATE_SHAPESHIFT_FORM",
    "EDIT_MODE_LAYOUTS_UPDATED",
}

-- Module-local state. Per-icon overlays are kept here rather than written to
-- the CooldownViewer child (patterns.md: never write Lua keys onto Blizzard
-- frames — taints `wasOnGCDLookup`).
local highlightFrames = {}     ---@type table<frame, frame>
local settingsGetters = {}     ---@type table<string, fun(): table>  by COMPONENT name
local buttonProviders = {}     ---@type table<string, fun(): table<number, frame>>  by component name: spellID-keyed button maps
local eventFrame = CreateFrame("Frame")
local moduleActive = false
local managerHooked = false
local currentSpellID = nil     ---@type number?

local function isComponentActive(componentName)
    local getter = settingsGetters[componentName]
    if not getter then return false end
    local settings = getter()
    if type(settings) ~= "table" then return false end
    return settings.rotation_highlight == true
end

local function anyComponentActive()
    for componentName in pairs(settingsGetters) do
        if isComponentActive(componentName) then return true end
    end
    return false
end

local function getNextSuggestedSpellID()
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        return C_AssistedCombat.GetNextCastSpell()
    end
    return nil
end

local function getChildSpellIDs(child)
    return child and child.cue_spellID or nil
end

local function createHighlightFrame(child)
    local iconTex = child.cue_Icon
    local frame = CreateFrame("Frame", nil, child)
    private.Pixel.SetPoint(frame, "TOPLEFT",     iconTex, "TOPLEFT",     -FLIPBOOK_INSET,  FLIPBOOK_INSET)
    private.Pixel.SetPoint(frame, "BOTTOMRIGHT", iconTex, "BOTTOMRIGHT",  FLIPBOOK_INSET, -FLIPBOOK_INSET)
    frame:SetFrameLevel((child:GetFrameLevel() or 0) + 5)

    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    tex:SetAllPoints()
    tex:SetAtlas(FLIPBOOK_ATLAS)
    tex:SetBlendMode("ADD")
    frame.texture = tex

    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local flip = ag:CreateAnimation("FlipBook")
    flip:SetDuration(FLIPBOOK_DURATION)
    flip:SetFlipBookRows(FLIPBOOK_ROWS)
    flip:SetFlipBookColumns(FLIPBOOK_COLUMNS)
    flip:SetFlipBookFrames(FLIPBOOK_FRAMES)
    flip:SetChildKey("texture")
    flip:SetOrder(1)
    frame.anim = ag

    frame:SetAlpha(0)
    frame:Show()
    return frame
end

local function getOrCreateHighlight(child)
    local frame = highlightFrames[child]
    if frame then return frame end
    frame = createHighlightFrame(child)
    highlightFrames[child] = frame
    return frame
end

local function hideHighlight(child)
    local frame = highlightFrames[child]
    if not frame then return end
    frame:SetAlpha(0)
    if frame.anim and frame.anim:IsPlaying() then
        frame.anim:Stop()
    end
end

local function updateChild(child, componentName)
    if not child or not child.cue_Icon then return end
    if not isComponentActive(componentName) then
        hideHighlight(child)
        return
    end
    local spellID = getChildSpellIDs(child)
    if not spellID then
        hideHighlight(child)
        return
    end
    local match = currentSpellID and spellID == currentSpellID
    local frame = getOrCreateHighlight(child)
    if match then
        frame:SetAlpha(1)
        if frame.anim and not frame.anim:IsPlaying() then
            frame.anim:Play()
        end
    else
        frame:SetAlpha(0)
        if frame.anim and frame.anim:IsPlaying() then
            frame.anim:Stop()
        end
    end
end

function AssistedHighlight.UpdateComponent(name)
    local provider = buttonProviders[name]
    if not provider then return end
    for _, button in pairs(provider()) do
        updateChild(button, name)
    end
end

function AssistedHighlight.UpdateAll()
    currentSpellID = getNextSuggestedSpellID()
    for name in pairs(buttonProviders) do
        AssistedHighlight.UpdateComponent(name)
    end
end

-- `AssistedCombatManager` is a Blizzard singleton (not a mixin template
-- instantiated onto individual frames), so the feedback_no_global_hooks rule's
-- motivating case — hooking a mixin table whose methods never propagate to
-- runtime frames — does not apply here. This hook is the official notifier
-- Blizzard fires whenever the suggested rotation spell changes; one install
-- services every tracker the module registers.
local function installManagerHook()
    if managerHooked then return end
    if not AssistedCombatManager or not AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        return
    end
    managerHooked = true
    hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
        if moduleActive then
            AssistedHighlight.UpdateAll()
        end
    end)
end

local function clearAllHighlights()
    for _, provider in pairs(buttonProviders) do
        for _, button in pairs(provider()) do
            hideHighlight(button)
        end
    end
end

local function refreshModuleState()
    local shouldRun = anyComponentActive()
    if shouldRun and not moduleActive then
        moduleActive = true
        for _, ev in ipairs(MODULE_EVENTS) do
            eventFrame:RegisterEvent(ev)
        end
        installManagerHook()
        -- Rotation helper only populates GetNextCastSpell when this CVar is
        -- on. Force-enable on setting toggle; guarded for the cachable-CVar
        -- pattern (patterns.md).
        if C_CVar.GetCVar(CVAR_ASSISTED_HIGHLIGHT) ~= "1" then
            C_CVar.SetCVar(CVAR_ASSISTED_HIGHLIGHT, "1")
        end
        AssistedHighlight.UpdateAll()
    elseif not shouldRun and moduleActive then
        moduleActive = false
        eventFrame:UnregisterAllEvents()
        currentSpellID = nil
        clearAllHighlights()
    elseif shouldRun and moduleActive then
        -- Still active but a viewer's per-component toggle changed; repaint.
        AssistedHighlight.UpdateAll()
    end
end

function AssistedHighlight.OnSettingChanged()
    refreshModuleState()
end

---Once no tracker uses Rotation Highlight any more, ask whether to switch
---Blizzard's own Assisted Highlight off too. Enabling ours forced the account
---CVar on, and that CVar also draws the suggestion on the action bars; nothing
---ever turned it back off. Asked rather than done: the player may want
---Blizzard's highlight for its own sake. Call after the setting was turned off.
function AssistedHighlight.OfferBlizzardHighlightOff()
    if anyComponentActive() then return end
    if C_CVar.GetCVar(CVAR_ASSISTED_HIGHLIGHT) ~= "1" then return end
    if not StaticPopupDialogs["CLASSUIENHANCED_ASSISTED_HIGHLIGHT_OFF"] then
        StaticPopupDialogs["CLASSUIENHANCED_ASSISTED_HIGHLIGHT_OFF"] = {
            text = private.L["ASSISTED_HIGHLIGHT_OFF_CONFIRM"],
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                if C_CVar.GetCVar(CVAR_ASSISTED_HIGHLIGHT) ~= "0" then
                    C_CVar.SetCVar(CVAR_ASSISTED_HIGHLIGHT, "0")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("CLASSUIENHANCED_ASSISTED_HIGHLIGHT_OFF")
end

---Register a plain-frame tracker's pooled buttons as a highlight target.
---getButtonsFn returns the live spellID-keyed button map (buttons carry
---cue_spellID / cue_Icon); no viewer hook is installed — the manager hook
---and module events drive repaints, and highlight frames are anchored to
---the buttons so relayouts move them automatically.
---@param name string  component name (settings must expose rotation_highlight)
---@param getSettings fun(): table
---@param getButtonsFn fun(): table<number, frame>
function AssistedHighlight.RegisterButtons(name, getSettings, getButtonsFn)
    if type(name) ~= "string" or type(getSettings) ~= "function"
        or type(getButtonsFn) ~= "function" then return end
    settingsGetters[name] = getSettings
    buttonProviders[name] = getButtonsFn
    refreshModuleState()
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        installManagerHook()
    end
    if moduleActive then
        AssistedHighlight.UpdateAll()
    end
end)
