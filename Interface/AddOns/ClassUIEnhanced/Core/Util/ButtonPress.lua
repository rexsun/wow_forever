
--[[
    ButtonPress — pressed overlay utility for tracker icons.

    Mirrors the action bar "pushed" visual onto tracker icons when the
    player presses the corresponding keybind. Supports Blizzard default
    bars (ActionButtonDown/Up, MultiActionButtonDown/Up) and any addon
    that uses LibActionButton-1.0 (ElvUI, Bartender4, Dominos, etc.)
    via PreClick hooks.

    The overlay is a dark wash texture (SetColorTexture black at 40%
    alpha) over the icon. It shows on key-down and hides on key-up.

    Gated by profile.button_press.enabled (default off).
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field ButtonPress buttonpress

---@class buttonpress : table
---@field Initialize fun()

---@type buttonpress
local bp = {}

---Addon-owned lookup for pressed overlay frames, keyed by icon reference.
---Never write overlay references directly to CooldownViewer child frame tables —
---insecure writes taint the frame, causing secret value comparison failures
---in Blizzard's secure OnUnitAura iteration (see patterns.md).
local pressedOverlays = {} ---@type table<frame, frame>

-- ---------------------------------------------------------------------------
-- SpellID resolution from action buttons
-- ---------------------------------------------------------------------------

---Build a set of related spellIDs (base + override) for fuzzy matching.
---@param spellID number
---@return table<number, boolean>
local function createSpellIDCollection(spellID)
    local collection = {}
    collection[spellID] = true

    local overrideSpell = private.compat.GetOverrideSpell(spellID)
    if overrideSpell then
        collection[overrideSpell] = true
    end

    local baseSpell = private.compat.GetBaseSpell(spellID)
    if baseSpell then
        collection[baseSpell] = true
    end

    return collection
end

---Get the spell from a macro name.
---@param macroName string
---@return number|nil
local function getSpellIDFromMacro(macroName)
    if not macroName then return nil end
    return GetMacroSpell(macroName)
end

---Resolve the spellID from an action button frame.
---@param btn frame
---@return number|nil spellID
local function getSpellIDFromButton(btn)
    if not btn or not btn.action then return nil end

    local actionType, id, subType = GetActionInfo(btn.action)
    if actionType == "spell" then
        return id
    elseif actionType == "macro" and subType == "spell" then
        return id
    elseif actionType == "macro" then
        local macroName = GetActionText(btn.action)
        return getSpellIDFromMacro(macroName)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Icon matching — find tracker icon by spellID
-- ---------------------------------------------------------------------------

---Search standalone tracker icons for a matching spellID.
---@param collection table<number, boolean>
---@return frame|nil
local function findStandaloneIcon(collection)
    -- RacialTracker: icons keyed by spellID
    if private.RacialTracker and private.RacialTracker.GetResolvedSpellIDs then
        local spellIDs = private.RacialTracker.GetResolvedSpellIDs()
        if spellIDs then
            for _, sid in ipairs(spellIDs) do
                if collection[sid] then
                    local icon = private.RacialTracker.GetIconFrame(sid)
                    if icon and icon:IsShown() then
                        return icon
                    end
                end
            end
        end
    end

    -- TrinketTracker: icons keyed by slotID, resolve to spellID via item
    if private.TrinketTracker and private.TrinketTracker.GetIconFrame then
        for _, slotID in ipairs({13, 14}) do
            local icon = private.TrinketTracker.GetIconFrame(slotID)
            if icon and icon:IsShown() then
                local itemID = GetInventoryItemID("player", slotID)
                if itemID then
                    local itemSpellName, itemSpellID = C_Item.GetItemSpell(itemID)
                    if itemSpellID and collection[itemSpellID] then
                        return icon
                    end
                end
            end
        end
    end

    -- ConsumableTracker: icons have .itemId, resolve to spellID
    if private.ConsumableTracker and private.ConsumableTracker.GetCategoryIDs then
        local catIDs = private.ConsumableTracker.GetCategoryIDs()
        if catIDs then
            for catKey, catID in pairs(catIDs) do
                local icons = private.ConsumableTracker.GetIconsByCategory(catID)
                if icons then
                    for _, icon in ipairs(icons) do
                        if icon:IsShown() and icon.itemId then
                            local itemSpellName, itemSpellID = C_Item.GetItemSpell(icon.itemId)
                            if itemSpellID and collection[itemSpellID] then
                                return icon
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

---Find the tracker icon matching a spellID across all tracker types.
---@param spellID number
---@return frame|nil
local function findIconBySpellID(spellID)
    if not spellID then return nil end

    local collection = createSpellIDCollection(spellID)

    -- Cooldown/Utilities trackers: pooled addon-owned icons keyed by spellID.
    -- These used to be found through the CDM viewer's children, which the 12.1
    -- rework suppressed at alpha 0 — the flash landed on an invisible Blizzard
    -- frame instead of our button.
    for _, comp in ipairs({ private.CooldownTracker, private.UtilitiesTracker }) do
        if comp and comp.GetIconFrame then
            for spellID in pairs(collection) do
                local icon = comp.GetIconFrame(spellID)
                if icon and icon:IsShown() then return icon end
            end
        end
    end

    -- Search standalone trackers
    return findStandaloneIcon(collection)
end

-- ---------------------------------------------------------------------------
-- Pressed overlay — lazy per-icon creation
-- ---------------------------------------------------------------------------

---Get or create the pressed overlay frame for an icon.
---@param icon frame
---@return frame
local function getOrCreateOverlay(icon)
    if pressedOverlays[icon] then
        return pressedOverlays[icon]
    end

    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints(icon)
    overlay:SetFrameLevel(icon:GetFrameLevel() + 5)

    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(overlay)
    tex:SetColorTexture(0, 0, 0, 0.4)

    overlay:Hide()
    pressedOverlays[icon] = overlay
    return overlay
end

---Show the pressed overlay on an icon.
---@param icon frame
local function showPressed(icon)
    if not icon then return end
    -- Skip press feedback on icons hidden by icon_visibility_mode (override=0):
    -- the icon itself is at alpha 0 but the press overlay's texture is set via
    -- SetColorTexture and renders the click area as a visible dark square.
    if private.Util and private.Util.GetIconAlphaOverride
        and private.Util.GetIconAlphaOverride(icon) == 0 then
        return
    end
    local overlay = getOrCreateOverlay(icon)
    overlay:Show()
end

---Hide the pressed overlay on an icon.
---@param icon frame
local function hidePressed(icon)
    if not icon then return end
    local overlay = pressedOverlays[icon]
    if overlay then
        overlay:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Cleanup — hide all active overlays on release
-- ---------------------------------------------------------------------------

---@type frame[]
local activeOverlayIcons = {}
local isCleaning = false

local function cleanupActive()
    if isCleaning then return end
    isCleaning = true
    for i, icon in ipairs(activeOverlayIcons) do
        hidePressed(icon)
        activeOverlayIcons[i] = nil
    end
    isCleaning = false
end

-- ---------------------------------------------------------------------------
-- Hook: Blizzard action bars
-- ---------------------------------------------------------------------------

local isInitialized = false

---@type table<frame, boolean>  guard against double-hooking LAB buttons
local hookedLABButtons = {}

---Handle a button press event.
---@param spellID number|nil
local function onButtonDown(spellID)
    if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
        return
    end
    if not spellID then return end

    local icon = findIconBySpellID(spellID)
    if not icon then return end

    showPressed(icon)
    activeOverlayIcons[#activeOverlayIcons + 1] = icon
end

---Handle a button release event.
---@param spellID number|nil
local function onButtonUp(spellID)
    if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
        return
    end
    if spellID then
        local icon = findIconBySpellID(spellID)
        if icon then
            hidePressed(icon)
        end
    end
    cleanupActive()
end

-- ---------------------------------------------------------------------------
-- Hook: LibActionButton-1.0 (ElvUI, Bartender4, Dominos, etc.)
-- ---------------------------------------------------------------------------

---Hook PreClick on a single LAB button frame.
---@param button frame
local function hookLABButton(button)
    if not button or hookedLABButtons[button] then return end
    hookedLABButtons[button] = true

    button:HookScript("PreClick", function(self, mouseButton, down)
        if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
            return
        end
        if down then
            cleanupActive()
            local spellID = getSpellIDFromButton(self)
            if spellID then
                onButtonDown(spellID)
            end
        else
            local spellID = getSpellIDFromButton(self)
            onButtonUp(spellID)
        end
    end)
end

---Hook a Dominos button (has an extra .bind frame).
---@param button frame
local function hookDominosButton(button)
    if not button then return end
    hookLABButton(button)
    if button.bind and not hookedLABButtons[button.bind] then
        hookedLABButtons[button.bind] = true
        button.bind:HookScript("PreClick", function(self, mouseButton, down)
            if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
                return
            end
            if down then
                cleanupActive()
                local spellID = getSpellIDFromButton(button)
                if spellID then
                    onButtonDown(spellID)
                end
            else
                local spellID = getSpellIDFromButton(button)
                onButtonUp(spellID)
            end
        end)
    end
end

---Hook all active LAB buttons and register for future ones.
local function hookLAB()
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if not LAB then return end

    -- Hook existing buttons
    if LAB.activeButtons then
        for button in pairs(LAB.activeButtons) do
            hookLABButton(button)
        end
    end

    -- Hook future buttons
    LAB:RegisterCallback("OnButtonUpdate", function(_, button)
        hookLABButton(button)
    end)
end

---Hook ElvUI's own LAB instance (separate from the standalone one).
local function hookElvUILAB()
    local ElvUI = _G.ElvUI and _G.ElvUI[1]
    if not ElvUI then return end
    local ElvUILAB = ElvUI.Libs and ElvUI.Libs.LAB
    if not ElvUILAB then return end

    if ElvUILAB.activeButtons then
        for button in pairs(ElvUILAB.activeButtons) do
            hookLABButton(button)
        end
    end

    ElvUILAB:RegisterCallback("OnButtonUpdate", function(_, button)
        hookLABButton(button)
    end)
end

---Hook all Dominos buttons.
local function hookDominos()
    local Dominos = _G.Dominos
    if not Dominos or not Dominos.ActionButtons or not Dominos.ActionButtons.GetAll then
        return
    end

    -- Hook on layout load for future buttons
    Dominos.RegisterCallback(Dominos, "LAYOUT_LOADED", function()
        for button in Dominos.ActionButtons:GetAll() do
            hookDominosButton(button)
        end
    end)

    -- Hook existing buttons now
    for button in Dominos.ActionButtons:GetAll() do
        hookDominosButton(button)
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function bp.Initialize()
    if isInitialized then return end
    isInitialized = true

    -- Blizzard default action bars
    hooksecurefunc("ActionButtonDown", function(id)
        if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
            return
        end
        -- In a pet battle Blizzard hands the key to PetBattleFrame instead
        -- (CheckPetActionButtonEvent, ActionButton.lua), so no action is used.
        if C_PetBattles.IsInBattle() then return end
        -- Blizzard's own resolver: OverrideActionBarButton<id> while the
        -- override/vehicle bar is shown, else ActionButton<id>.
        local btn = GetActionButtonForID(id)
        local spellID = getSpellIDFromButton(btn)
        if spellID then
            local icon = findIconBySpellID(spellID)
            if icon then
                showPressed(icon)
                activeOverlayIcons[#activeOverlayIcons + 1] = icon
            end
        end
    end)

    hooksecurefunc("ActionButtonUp", function(id)
        if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
            return
        end
        if C_PetBattles.IsInBattle() then return end
        local btn = GetActionButtonForID(id)
        local spellID = getSpellIDFromButton(btn)
        if spellID then
            local icon = findIconBySpellID(spellID)
            if icon then
                hidePressed(icon)
            end
        end
        cleanupActive()
    end)

    hooksecurefunc("MultiActionButtonDown", function(bar, id)
        if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
            return
        end
        local btn = _G[bar .. "Button" .. id]
        local spellID = getSpellIDFromButton(btn)
        if spellID then
            local icon = findIconBySpellID(spellID)
            if icon then
                showPressed(icon)
                activeOverlayIcons[#activeOverlayIcons + 1] = icon
            end
        end
    end)

    hooksecurefunc("MultiActionButtonUp", function(bar, id)
        if not private.profile or not private.profile.button_press or not private.profile.button_press.enabled then
            return
        end
        local btn = _G[bar .. "Button" .. id]
        local spellID = getSpellIDFromButton(btn)
        if spellID then
            local icon = findIconBySpellID(spellID)
            if icon then
                hidePressed(icon)
            end
        end
        cleanupActive()
    end)

    -- Addon action bar support (LibActionButton-1.0)
    hookLAB()
    hookElvUILAB()
    hookDominos()
end

private.ButtonPress = bp
