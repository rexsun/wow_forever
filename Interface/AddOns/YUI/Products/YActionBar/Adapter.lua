local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local Adapter = {}
YAB.Adapter = Adapter
Adapter.apiReads = Adapter.apiReads or { total = 0, byReader = {} }
Adapter.statsEnabled = Adapter.statsEnabled or false

function Adapter:CanUseSecureRuntime()
    if Client.supported ~= true then return false, "Unsupported action bar client." end
    if Client.CheckSecureRuntime and not Client.CheckSecureRuntime() then
        local locale = YUI.Locale and YUI.Locale:Get("Core")
        return false, locale and locale["compat.forever.secure_runtime_missing"]
            or "Forever: secure execution is unavailable; native action bars retained."
    end
    return true
end

local Security = YUI.API and YUI.API.Security
local Unit = YUI.API and YUI.API.Unit

local LEGACY_SPECIAL_BUTTON_DISPOSAL = {
    { "PetActionButton", 10, "petButton" },
    { "StanceButton", 10, "stanceButton" },
    { "PossessButton", 2, "possessButton" },
}

local LEGACY_SPECIAL_FRAME_DISPOSAL = {
    { "PetActionBar", "hiddenParent" },
    { "PetActionBarFrame", "hiddenParent" },
    { "StanceBar", "hiddenParent" },
    { "StanceBarFrame", "hiddenParent" },
    { "PossessActionBar", "hiddenParent" },
    { "PossessBarFrame", "hiddenParent" },
}

local function WipeTable(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CountRead(name)
    if not Adapter.statsEnabled then return end
    local stats = Adapter.apiReads
    stats.total = (stats.total or 0) + 1
    local byReader = stats.byReader
    byReader[name] = (byReader[name] or 0) + 1
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f = pcall(func, ...)
    if ok then
        return a, b, c, d, e, f
    end
    return nil
end

local function CallActionBar(method)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar[method]) == "function" then
        return SafeCall(actionBar[method])
    end
    return nil
end

local function CallActionBarForSlot(method, slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar[method]) == "function" then
        return SafeCall(actionBar[method], slot)
    end
    return nil
end

local function CallGlobal(name)
    return SafeCall(_G[name])
end

local function IsSecretValue(value)
    return Security and Security.IsSecretValue and Security.IsSecretValue(value) == true or false
end

local function SafeNumber(value)
    if Security and Security.SafeNumber then
        return Security.SafeNumber(value)
    end
    if value == nil or IsSecretValue(value) then
        return nil
    end
    local ok, numberValue = pcall(tonumber, value)
    if ok and numberValue ~= nil and not IsSecretValue(numberValue) then
        return numberValue
    end
    return nil
end

local function SafeString(value)
    if value == nil or IsSecretValue(value) then return nil end
    if type(value) == "string" then return value end
    return nil
end

local function SafeText(value)
    if IsSecretValue(value) then return value, true end
    if value == nil then return nil, false end
    if type(value) == "string" then return value end
    if type(value) == "number" then return tostring(value) end
    return nil, false
end

local function SafeBoolean(value)
    if value == nil or IsSecretValue(value) then return nil end
    if type(value) == "boolean" then return value end
    local numberValue = SafeNumber(value)
    if numberValue ~= nil then
        return numberValue ~= 0
    end
    return nil
end

local actionHotBackendReady = false
local actionHotBackend

local function NoActionHotResult()
    return nil
end

function Adapter:GetActionHotBackend()
    if actionHotBackendReady then return actionHotBackend end
    actionHotBackendReady = true

    local actionBar = _G.C_ActionBar
    local namespacedHasAction = actionBar and actionBar.HasAction
    local globalHasAction = _G.HasAction
    local hasAction = type(namespacedHasAction) == "function" and namespacedHasAction or globalHasAction
    local retailCooldown = actionBar and actionBar.GetActionCooldown
    local retailCooldownDuration = actionBar and actionBar.GetActionCooldownDuration
    if type(hasAction) == "function"
        and type(retailCooldown) == "function"
        and type(retailCooldownDuration) == "function" then
        local getChargeInfo = actionBar.GetActionCharges
        local getChargeDuration = actionBar.GetActionChargeDuration
        local getDisplayCount = actionBar.GetActionDisplayCount
        local getActionCount = _G.GetActionCount
        actionHotBackend = {
            mode = "retail-duration",
            hasAction = hasAction,
            getCooldownInfo = retailCooldown,
            getCooldownDuration = retailCooldownDuration,
            getChargeInfo = type(getChargeInfo) == "function" and getChargeInfo or NoActionHotResult,
            getChargeDuration = type(getChargeDuration) == "function" and getChargeDuration or NoActionHotResult,
            getDisplayCount = type(getDisplayCount) == "function" and getDisplayCount or NoActionHotResult,
            getActionCount = type(getActionCount) == "function" and getActionCount or NoActionHotResult,
        }
        return actionHotBackend
    end

    local legacyCooldown = _G.GetActionCooldown
    if type(hasAction) == "function" and type(legacyCooldown) == "function" then
        local getChargeInfo = _G.GetActionCharges
        local getActionCount = _G.GetActionCount
        actionHotBackend = {
            mode = "legacy-scalar",
            hasAction = hasAction,
            getCooldownInfo = legacyCooldown,
            getCooldownDuration = NoActionHotResult,
            getChargeInfo = type(getChargeInfo) == "function" and getChargeInfo or NoActionHotResult,
            getChargeDuration = NoActionHotResult,
            getDisplayCount = NoActionHotResult,
            getActionCount = type(getActionCount) == "function" and getActionCount or NoActionHotResult,
        }
        return actionHotBackend
    end

    return nil
end

function Adapter:ResetStats()
    self.apiReads.total = 0
    WipeTable(self.apiReads.byReader)
end

function Adapter:SetStatsEnabled(enabled, reset)
    enabled = enabled == true
    if self.statsEnabled == enabled and reset ~= true then
        return
    end
    self.statsEnabled = enabled
    self:ResetStats()
end

function Adapter:GetVersion()
    return Client.id
end

function Adapter:InCombat()
    if type(_G.UnitAffectingCombat) == "function" then
        local ok, affecting = pcall(_G.UnitAffectingCombat, "player")
        if ok and affecting == true then return true end
    end
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true or false
end

function Adapter:EnsureSpecialNativeSuppressed(kinds)
    local result = {
        ok = true,
        changed = false,
        mode = "native-reuse",
        failures = 0,
        blockedKinds = {},
        changedKinds = {},
    }
    if type(kinds) ~= "table" or #kinds == 0 then
        return result
    end
    if Client.nativeSpecialButtons ~= true then
        result.mode = "unsupported-version"
        return result
    end
    for _, kind in ipairs(kinds) do
        result.changedKinds[#result.changedKinds + 1] = kind
    end
    return result
end

function Adapter:GetActionBarPage()
    return CallActionBar("GetActionBarPage") or CallGlobal("GetActionBarPage") or 1
end

function Adapter:GetBonusBarIndex()
    return CallActionBar("GetBonusBarIndex") or CallGlobal("GetBonusBarIndex") or 0
end

function Adapter:GetOverrideBarIndex()
    return CallActionBar("GetOverrideBarIndex") or CallGlobal("GetOverrideBarIndex") or 14
end

local function GetVehicleBarIndexFromAPI()
    return CallActionBar("GetVehicleBarIndex") or CallGlobal("GetVehicleBarIndex")
end

function Adapter:GetVehicleBarIndex()
    return GetVehicleBarIndexFromAPI() or Client.vehicleFallbackPage
end

function Adapter:GetTempShapeshiftBarIndex()
    return CallActionBar("GetTempShapeshiftBarIndex") or CallGlobal("GetTempShapeshiftBarIndex") or 13
end

function Adapter:GetPossessActionPage()
    return SafeNumber(GetVehicleBarIndexFromAPI()) or 16
end

function Adapter:HasOverrideActionBar()
    local value = CallActionBar("HasOverrideActionBar")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("HasOverrideActionBar")
    return SafeBoolean(value) == true
end

function Adapter:HasVehicleActionBar()
    local value = CallActionBar("HasVehicleActionBar")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("HasVehicleActionBar")
    return SafeBoolean(value) == true
end

function Adapter:HasVehicleUnit()
    return Unit and Unit.Exists and Unit.Exists("vehicle") == true or false
end

function Adapter:HasTempShapeshiftActionBar()
    local value = CallActionBar("HasTempShapeshiftActionBar")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("HasTempShapeshiftActionBar")
    return SafeBoolean(value) == true
end

function Adapter:HasBonusActionBar()
    local value = CallActionBar("HasBonusActionBar")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("HasBonusActionBar")
    return SafeBoolean(value) == true
end

function Adapter:IsPossessBarVisible()
    local value = CallActionBar("IsPossessBarVisible")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("IsPossessBarVisible")
    return SafeBoolean(value) == true
end

function Adapter:UseMainActionBarForPossess()
    return Client.mainPossess == true
end

function Adapter:SupportsPetBattleState()
    return Client.petBattle == true or (Client.petBattle == "available" and _G.C_PetBattles ~= nil)
end

function Adapter:IsPetBattleActive()
    local petBattles = _G.C_PetBattles
    if petBattles and type(petBattles.IsInBattle) == "function" then
        return SafeBoolean(SafeCall(petBattles.IsInBattle)) == true
    end
    return false
end

function Adapter:IsHouseEditorAvailable()
    local houseEditor = _G.C_HouseEditor
    return houseEditor and type(houseEditor.IsHouseEditorActive) == "function" or false
end

function Adapter:IsHouseEditorActive()
    local houseEditor = _G.C_HouseEditor
    if houseEditor and type(houseEditor.IsHouseEditorActive) == "function" then
        return SafeBoolean(SafeCall(houseEditor.IsHouseEditorActive)) == true
    end
    return false
end

function Adapter:GetSystemBindingSuppressionReason()
    if self:IsPetBattleActive() then
        return "petbattle"
    end
    if self:IsHouseEditorActive() then
        return "house-editor"
    end
    return nil
end

function Adapter:HasPetActionButtons()
    local value = CallActionBar("HasPetActionButtons")
    local safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    value = CallGlobal("HasPetActionButtons")
    safe = SafeBoolean(value)
    if safe ~= nil then return safe end
    return true
end

function Adapter:GetActionPageState()
    return {
        actionPage = self:GetActionBarPage(),
        effectiveMainPage = self:GetEffectiveMainActionPage(),
        bonusPage = self:GetBonusBarIndex(),
        overridePage = self:GetOverrideBarIndex(),
        vehiclePage = self:GetVehicleBarIndex(),
        possessPage = self:GetPossessActionPage(),
        tempShapeshiftPage = self:GetTempShapeshiftBarIndex(),
        hasOverride = self:HasOverrideActionBar(),
        hasVehicle = self:HasVehicleActionBar(),
        hasPossess = self:IsPossessBarVisible(),
        hasTempShapeshift = self:HasTempShapeshiftActionBar(),
        hasBonus = self:HasBonusActionBar(),
    }
end

local BAR_DEFINITIONS = {
    main = {
        page = 1,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "ACTIONBUTTON",
        buttonType = "ACTIONBUTTON",
    },
    bar2 = {
        page = 6,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR1BUTTON",
        buttonType = "MULTIACTIONBAR1BUTTON",
    },
    bar3 = {
        page = 5,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR2BUTTON",
        buttonType = "MULTIACTIONBAR2BUTTON",
    },
    bar4 = {
        page = 3,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR3BUTTON",
        buttonType = "MULTIACTIONBAR3BUTTON",
    },
    bar5 = {
        page = 4,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR4BUTTON",
        buttonType = "MULTIACTIONBAR4BUTTON",
    },
    bar6 = {
        page = 13,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR5BUTTON",
        buttonType = "MULTIACTIONBAR5BUTTON",
    },
    bar7 = {
        page = 14,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR6BUTTON",
        buttonType = "MULTIACTIONBAR6BUTTON",
    },
    bar8 = {
        page = 15,
        buttonTemplate = "ActionBarButtonTemplate",
        commandNamePrefix = "MULTIACTIONBAR7BUTTON",
        buttonType = "MULTIACTIONBAR7BUTTON",
    },
}

function Adapter:GetActionBarDefinition(barId)
    local def = BAR_DEFINITIONS[barId] or BAR_DEFINITIONS.main
    return {
        id = barId,
        page = def.page,
        buttonTemplate = def.buttonTemplate,
        commandNamePrefix = def.commandNamePrefix,
        buttonType = def.buttonType,
    }
end

function Adapter:GetActionBarPageForBar(barId, fallbackPage)
    local def = BAR_DEFINITIONS[barId]
    return SafeNumber(def and def.page) or SafeNumber(fallbackPage) or 1
end

function Adapter:BuildMainPageDriver()
    local overridePage = SafeNumber(self:GetOverrideBarIndex()) or 14
    local vehiclePage = SafeNumber(self:GetVehicleBarIndex()) or 16
    local tempShapeshiftPage = SafeNumber(self:GetTempShapeshiftBarIndex()) or 13
    local parts = {
        "[overridebar] " .. overridePage,
        "[vehicleui][possessbar] " .. vehiclePage,
        "[shapeshift] " .. tempShapeshiftPage,
    }
    if Client.vehiclePageFirst == true then parts[1], parts[2] = parts[2], parts[1] end
    parts[#parts + 1] = "[bar:6] 6"
    parts[#parts + 1] = "[bar:5] 5"
    parts[#parts + 1] = "[bar:4] 4"
    parts[#parts + 1] = "[bar:3] 3"
    parts[#parts + 1] = "[bar:2] 2"
    for index = 10, 1, -1 do
        parts[#parts + 1] = "[bonusbar:" .. index .. "] bonus" .. index
    end
    parts[#parts + 1] = "1"
    return table.concat(parts, "; ")
end

local function BuildBaseVisibilityDriver(mode)
    local driver
    if mode == "hidden" then
        driver = "hide"
    elseif mode == "combat" then
        driver = "[combat] show; hide"
    elseif mode == "outOfCombat" then
        driver = "[combat] hide; show"
    elseif mode == "mounted" then
        driver = "[mounted] show; hide"
    elseif mode == "unmounted" then
        driver = "[mounted] hide; show"
    else
        driver = "show"
    end
    return driver
end

local function BuildConditionalVisibilityDriver(mode, condition)
    condition = SafeString(condition)
    if not condition or condition == "" then
        return BuildBaseVisibilityDriver(mode)
    end
    if mode == "hidden" then
        return "hide"
    elseif mode == "combat" then
        return "[" .. condition .. ",combat] show; hide"
    elseif mode == "outOfCombat" then
        return "[" .. condition .. ",combat] hide; [" .. condition .. "] show; hide"
    elseif mode == "mounted" then
        return "[" .. condition .. ",mounted] show; hide"
    elseif mode == "unmounted" then
        return "[" .. condition .. ",mounted] hide; [" .. condition .. "] show; hide"
    end
    return "[" .. condition .. "] show; hide"
end

local function PrefixDriver(driver, prefix)
    if type(prefix) ~= "string" or prefix == "" or driver == "hide" then
        return driver
    end
    return prefix .. driver
end

function Adapter:BuildVisibilityDriver(mode, hideSkyriding, context)
    local barId, kind
    if type(context) == "table" then
        barId = SafeString(context.id) or SafeString(context.barId)
        kind = SafeString(context.kind)
    elseif type(context) == "string" then
        barId = context
    end
    kind = kind or barId

    local petBattlePrefix = self:SupportsPetBattleState() and "[petbattle] hide; " or ""
    local specialStatePrefix = petBattlePrefix .. "[vehicleui][overridebar][possessbar,@vehicle,exists] hide; "
    local driver

    if barId == "main" then
        driver = PrefixDriver(BuildBaseVisibilityDriver(mode), petBattlePrefix)
    elseif kind == "action" then
        driver = PrefixDriver(BuildBaseVisibilityDriver(mode), specialStatePrefix)
    elseif kind == "pet" then
        driver = PrefixDriver(BuildConditionalVisibilityDriver(mode, "pet,novehicleui,nooverridebar,nopossessbar"), petBattlePrefix)
    elseif kind == "stance" then
        driver = PrefixDriver(BuildBaseVisibilityDriver(mode), specialStatePrefix)
    elseif kind == "possess" and self:UseMainActionBarForPossess() then
        driver = "hide"
    elseif kind == "possess" then
        driver = PrefixDriver(BuildConditionalVisibilityDriver(mode, "possessbar,novehicleui,nooverridebar"), petBattlePrefix)
    elseif kind == "vehicleExit" then
        driver = PrefixDriver(BuildConditionalVisibilityDriver(mode, "canexitvehicle"), petBattlePrefix)
    else
        driver = PrefixDriver(BuildBaseVisibilityDriver(mode), petBattlePrefix)
    end

    if hideSkyriding == true and driver ~= "hide" and Client.skyridingVisibility then
        return "[advflyable,flying] hide; " .. driver
    end
    return driver
end

function Adapter:GetEffectiveMainActionPage()
    local actionPage = SafeNumber(self:GetActionBarPage()) or 1
    if self:HasVehicleActionBar() then
        return SafeNumber(self:GetVehicleBarIndex()) or actionPage
    end
    if self:HasOverrideActionBar() then
        return SafeNumber(self:GetOverrideBarIndex()) or actionPage
    end
    if self:IsPossessBarVisible() then
        return SafeNumber(self:GetPossessActionPage()) or actionPage
    end
    if self:HasTempShapeshiftActionBar() then
        return SafeNumber(self:GetTempShapeshiftBarIndex()) or actionPage
    end
    if self:HasBonusActionBar() and actionPage == 1 then
        return SafeNumber(self:GetBonusBarIndex()) or actionPage
    end
    return actionPage
end

function Adapter:GetActionSlot(page, index)
    page = SafeNumber(page) or 1
    index = SafeNumber(index) or 1
    return ((page - 1) * 12) + index
end

function Adapter:GetActionTexture(slot)
    return _G.GetActionTexture and _G.GetActionTexture(slot) or nil
end

function Adapter:GetActionInfo(slot)
    if not _G.GetActionInfo then return nil end
    return _G.GetActionInfo(slot)
end

function Adapter:NormalizeSpellID(value)
    return SafeNumber(value)
end

function Adapter:GetActionCount(slot)
    return _G.GetActionCount and _G.GetActionCount(slot) or 0
end

function Adapter:GetActionDisplayCount(slot, maxDisplayCount)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionDisplayCount) == "function" then
        local displayCount
        if maxDisplayCount ~= nil then
            displayCount = actionBar.GetActionDisplayCount(slot, maxDisplayCount)
        else
            displayCount = actionBar.GetActionDisplayCount(slot)
        end
        local text, textIsSecret = SafeText(displayCount)
        if textIsSecret == true then return text end
        return text or ""
    end
    local count = SafeNumber(self:GetActionCount(slot)) or 0
    local maxCount = SafeNumber(maxDisplayCount)
    if maxCount and count > maxCount then
        return "*"
    end
    return count > 1 and tostring(count) or ""
end

function Adapter:GetActionText(slot)
    local actionBar = _G.C_ActionBar
    local text
    if actionBar and type(actionBar.GetActionText) == "function" then
        text = actionBar.GetActionText(slot)
    elseif _G.GetActionText then
        text = _G.GetActionText(slot)
    end
    return SafeText(text)
end

function Adapter:GetActionCooldownDurationObject(slot, ignoreGCD)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionCooldownDuration) == "function" then
        return actionBar.GetActionCooldownDuration(slot, ignoreGCD == true)
    end
    return nil
end

function Adapter:GetActionCooldownInfo(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionCooldown) == "function" then
        local info = actionBar.GetActionCooldown(slot)
        if type(info) == "table" then
            return SafeBoolean(info.isActive), SafeBoolean(info.isOnGCD), info
        end
    end
    return nil, nil, nil
end

function Adapter:GetActionChargeDurationObject(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionChargeDuration) == "function" then
        return actionBar.GetActionChargeDuration(slot)
    end
    return nil
end

function Adapter:GetActionCooldown(slot)
    if not _G.GetActionCooldown then return nil end
    local start, duration, enable, modRate = _G.GetActionCooldown(slot)
    return start, duration, enable, modRate
end

function Adapter:GetActionSpellID(slot)
    local actionType, id, subType = self:GetActionInfo(slot)
    actionType = SafeString(actionType)
    id = SafeNumber(id)
    subType = SafeString(subType)
    return self:GetActionSpellIDFromInfo(actionType, id, subType)
end

function Adapter:GetActionSpellIDFromInfo(actionType, id, subType)
    if actionType == "spell" then
        return id
    end
    if actionType == "macro" and id then
        if subType == "spell" then
            return id
        end
        if _G.GetMacroSpell then
            local macroSpell, macroSpellID = SafeCall(_G.GetMacroSpell, id)
            macroSpell = SafeNumber(macroSpell) or SafeNumber(macroSpellID)
            if macroSpell then
                return macroSpell
            end
        end
    end
    return nil
end

function Adapter:GetActionProcInfoFromInfo(actionType, id, subType)
    actionType = SafeString(actionType)
    id = SafeNumber(id)
    subType = SafeString(subType)

    local spellID = self:GetActionSpellIDFromInfo(actionType, id, subType)
    local flyoutID = actionType == "flyout" and id or nil
    return spellID, flyoutID, actionType, id, subType
end

function Adapter:IsProcSpellOverlayed(spellID)
    spellID = SafeNumber(spellID)
    local overlay = _G.C_SpellActivationOverlay
    if not (overlay and type(overlay.IsSpellOverlayed) == "function" and spellID) then
        return false
    end
    return SafeCall(overlay.IsSpellOverlayed, spellID) == true
end

function Adapter:IsFlyoutProcGlowFor(flyoutID, spellID)
    flyoutID = SafeNumber(flyoutID)
    spellID = SafeNumber(spellID)
    local flyout = _G.C_Flyout
    local reader = flyout and type(flyout.FlyoutHasSpell) == "function" and flyout.FlyoutHasSpell
        or _G.FlyoutHasSpell
    if not (flyoutID and spellID and type(reader) == "function") then return false end
    return SafeCall(reader, flyoutID, spellID) == true
end

function Adapter:IsUsableAction(slot)
    local actionBar = _G.C_ActionBar
    local reader = actionBar and type(actionBar.IsUsableAction) == "function" and actionBar.IsUsableAction or nil
    if not reader and type(_G.IsUsableAction) == "function" then
        reader = _G.IsUsableAction
    end
    if not reader then return nil, nil end

    local usable, noMana = SafeCall(reader, slot)
    usable = SafeBoolean(usable)
    noMana = SafeBoolean(noMana)
    if usable == nil or noMana == nil then return nil, nil end
    return usable, noMana
end

function Adapter:IsActionInRange(slot)
    if not _G.IsActionInRange then return nil end
    local value = _G.IsActionInRange(slot)
    return value
end

function Adapter:SetActionRangeCheck(slot, enabled)
    local actionBar = _G.C_ActionBar
    if not (actionBar and type(actionBar.EnableActionRangeCheck) == "function") then
        return false
    end
    local ok = pcall(actionBar.EnableActionRangeCheck, slot, enabled == true)
    return ok == true
end

function Adapter:HasAction(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.HasAction) == "function" then
        return actionBar.HasAction(slot) == true
    end
    return _G.HasAction and SafeBoolean(_G.HasAction(slot)) == true or false
end

function Adapter:GetActionCharges(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionCharges) == "function" then
        local info = actionBar.GetActionCharges(slot)
        if type(info) == "table" then
            return info.currentCharges,
                info.maxCharges,
                info.cooldownStartTime,
                info.cooldownDuration,
                info.chargeModRate,
                info.isActive
        end
    end
    if _G.GetActionCharges then
        local charges, maxCharges, chargeStart, chargeDuration, chargeModRate = SafeCall(_G.GetActionCharges, slot)
        local safeChargeDuration = SafeNumber(chargeDuration)
        return charges, maxCharges, chargeStart, chargeDuration, chargeModRate, safeChargeDuration ~= nil and safeChargeDuration > 0
    end
    return nil
end

function Adapter:GetActionLossOfControlCooldown(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.GetActionLossOfControlCooldownInfo) == "function" then
        local info = SafeCall(actionBar.GetActionLossOfControlCooldownInfo, slot)
        if type(info) == "table" then
            return info.startTime, info.duration, info.modRate, info.isActive, info.shouldReplaceNormalCooldown
        end
    end
    return nil
end

function Adapter:IsCurrentAction(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.IsCurrentAction) == "function" then
        return SafeBoolean(SafeCall(actionBar.IsCurrentAction, slot)) == true
    end
    return _G.IsCurrentAction and SafeBoolean(_G.IsCurrentAction(slot)) == true or false
end

function Adapter:IsAutoRepeatAction(slot)
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.IsAutoRepeatAction) == "function" then
        return SafeBoolean(SafeCall(actionBar.IsAutoRepeatAction, slot)) == true
    end
    return _G.IsAutoRepeatAction and SafeBoolean(_G.IsAutoRepeatAction(slot)) == true or false
end

function Adapter:IsActionProcGlow(slot)
    local actionType, id, subType = self:GetActionInfo(slot)
    return self:IsActionProcGlowFor(actionType, id, subType)
end

function Adapter:IsActionProcGlowFor(actionType, id, subType)
    local spellID = self:GetActionSpellIDFromInfo(SafeString(actionType), SafeNumber(id), SafeString(subType))
    return self:IsProcSpellOverlayed(spellID)
end

function Adapter:IsAssistedCombatAction(slot)
    if Client.assistedCombat ~= true then return false end
    CountRead("assistedCombat")
    return SafeBoolean(CallActionBarForSlot("IsAssistedCombatAction", slot)) == true
end

local ASSISTED_COMBAT_MIN_UPDATE_INTERVAL = 0.05
local ASSISTED_COMBAT_FALLBACK_UPDATE_INTERVAL = 0.10

function Adapter:GetAssistedCombatUpdateInterval()
    if Client.assistedCombat ~= true then return nil end
    CountRead("assistedCombatRate")
    local manager = _G.AssistedCombatManager
    local interval = manager
        and type(manager.GetUpdateRate) == "function"
        and SafeNumber(SafeCall(manager.GetUpdateRate, manager))
        or nil
    if interval == nil then
        interval = SafeNumber(SafeCall(_G.GetCVar, "assistedCombatIconUpdateRate"))
    end
    interval = interval or ASSISTED_COMBAT_FALLBACK_UPDATE_INTERVAL
    if interval < ASSISTED_COMBAT_MIN_UPDATE_INTERVAL then
        return ASSISTED_COMBAT_MIN_UPDATE_INTERVAL
    end
    if interval > 1 then return 1 end
    return interval
end

function Adapter:GetAssistedCombatNextSpell()
    if Client.assistedCombat ~= true then return nil, false end
    local assistedCombat = _G.C_AssistedCombat
    if not (assistedCombat and type(assistedCombat.GetNextCastSpell) == "function") then
        return nil, false
    end
    CountRead("assistedCombatNextSpell")
    local ok, spellID = pcall(assistedCombat.GetNextCastSpell, false)
    if not ok then return nil, false end
    if spellID == nil then return nil, true end
    spellID = SafeNumber(spellID)
    if spellID == nil then return nil, false end
    return spellID, true
end

function Adapter:ForceUpdateAssistedCombatAction(slot)
    if Client.assistedCombat ~= true then return false end
    local numberSlot = SafeNumber(slot)
    if numberSlot == nil then return false end
    local actionBar = _G.C_ActionBar
    if not (actionBar and type(actionBar.ForceUpdateAction) == "function") then return false end
    CountRead("assistedCombatForce")
    return pcall(actionBar.ForceUpdateAction, numberSlot) == true
end

function Adapter:ReadActionIdentity(slot, out, maxDisplayCount, backend)
    CountRead("identity")
    out = out or {}
    backend = backend or self:GetActionHotBackend()
    if backend and backend.hasAction then
        out.hasAction = backend.hasAction(slot) == true
    else
        out.hasAction = self:HasAction(slot)
    end
    out.texture = self:GetActionTexture(slot)
    if backend and backend.mode == "retail-duration" then
        out.count = 0
        out.displayCount = nil
    else
        out.count = SafeNumber(self:GetActionCount(slot)) or 0
        out.displayCount = self:GetActionDisplayCount(slot, maxDisplayCount)
    end
    out.macroText = self:GetActionText(slot) or ""
    local actionType, id, subType = self:GetActionInfo(slot)
    local spellID, flyoutID, safeType, safeID, safeSubType = self:GetActionProcInfoFromInfo(actionType, id, subType)
    out.actionType = safeType
    out.actionID = safeID
    out.actionSubType = safeSubType
    out.actionSpellID = spellID
    out.procSpellID = spellID
    out.flyoutID = flyoutID
    out.assistedCombat = self:IsAssistedCombatAction(slot)
    return out
end

function Adapter:ReadActionSafeIdentity(slot, out, backend)
    CountRead("identityProbe")
    out = out or {}
    backend = backend or self:GetActionHotBackend()
    if backend and backend.hasAction then
        out.hasAction = backend.hasAction(slot) == true
    else
        out.hasAction = self:HasAction(slot)
    end
    out.texture = self:GetActionTexture(slot)
    local actionType, id, subType = self:GetActionInfo(slot)
    local spellID, flyoutID, safeType, safeID, safeSubType = self:GetActionProcInfoFromInfo(actionType, id, subType)
    out.actionType = safeType
    out.actionID = safeID
    out.actionSubType = safeSubType
    out.actionSpellID = spellID
    out.procSpellID = spellID
    out.flyoutID = flyoutID
    return out
end

function Adapter:ReadActionProcIdentity(slot, out)
    CountRead("procIdentity")
    out = out or {}
    out.hasAction = self:HasAction(slot)
    local actionType, id, subType = self:GetActionInfo(slot)
    local spellID, flyoutID, safeType, safeID, safeSubType = self:GetActionProcInfoFromInfo(actionType, id, subType)
    out.actionType = safeType
    out.actionID = safeID
    out.actionSubType = safeSubType
    out.actionSpellID = spellID
    out.procSpellID = spellID
    out.flyoutID = flyoutID
    return out
end

function Adapter:ReadActionCounts(slot, out, maxDisplayCount, backend)
    CountRead("counts")
    out = out or {}
    backend = backend or self:GetActionHotBackend()
    if backend and backend.mode == "retail-duration" then
        out.count = 0
        out.displayCount = nil
    else
        out.count = SafeNumber(self:GetActionCount(slot)) or 0
        out.displayCount = self:GetActionDisplayCount(slot, maxDisplayCount)
    end
    return out
end

function Adapter:ReadActionMainCooldown(slot, out)
    CountRead("cooldown")
    out = out or {}
    out.cooldownDurationObject = nil
    out.realCooldownDurationObject = nil
    out.cooldownStart = nil
    out.cooldownDuration = nil
    out.cooldownModRate = nil
    out.cooldownEnable = false
    out.cooldownActive = false
    out.cooldownOnGCD = false

    local backend = self:GetActionHotBackend()
    if not backend or backend.mode ~= "legacy-scalar" then return out end
    local cooldownStartRaw, cooldownDurationRaw, cooldownEnableRaw, cooldownModRateRaw = backend.getCooldownInfo(slot)
    local cooldownStartValue = SafeNumber(cooldownStartRaw)
    local cooldownDurationValue = SafeNumber(cooldownDurationRaw)
    local cooldownModRateValue = SafeNumber(cooldownModRateRaw)
    local cooldownEnableValue = SafeBoolean(cooldownEnableRaw)
    local active = cooldownEnableValue == true and cooldownDurationValue ~= nil and cooldownDurationValue > 0
    out.cooldownStart = cooldownStartValue
    out.cooldownDuration = cooldownDurationValue
    out.cooldownEnable = active
    out.cooldownActive = active
    out.cooldownOnGCD = cooldownDurationValue ~= nil and cooldownDurationValue <= 1.5
    out.cooldownModRate = cooldownModRateValue
    return out
end

function Adapter:ReadActionChargeState(slot, out, maxDisplayCount)
    CountRead("charges")
    out = out or {}
    out.chargeDurationObject = nil
    out.chargeStart = nil
    out.chargeDuration = nil
    out.chargeModRate = nil
    out.chargeEnable = false
    out.charges = nil
    out.maxCharges = nil
    out.count = 0
    out.displayCount = ""

    local backend = self:GetActionHotBackend()
    if not backend or backend.mode ~= "legacy-scalar" then return out end
    local charges, maxCharges, chargeStart, chargeDuration, chargeModRate = backend.getChargeInfo(slot)
    local chargeCountValue = SafeNumber(charges)
    local maxChargeValue = SafeNumber(maxCharges)
    out.charges = chargeCountValue
    out.maxCharges = maxChargeValue
    if maxChargeValue ~= nil and maxChargeValue > 1 then
        out.count = SafeNumber(self:GetActionCount(slot)) or 0
        out.displayCount = self:GetActionDisplayCount(slot, maxDisplayCount)
    end
    local chargeDurationValue = SafeNumber(chargeDuration)
    out.chargeStart = SafeNumber(chargeStart)
    out.chargeDuration = chargeDurationValue
    out.chargeModRate = SafeNumber(chargeModRate)
    out.chargeEnable = chargeDurationValue ~= nil and chargeDurationValue > 0 and chargeCountValue ~= nil and maxChargeValue ~= nil and chargeCountValue < maxChargeValue
    return out
end

function Adapter:ReadActionCooldown(slot, out)
    CountRead("cooldown")
    out = out or {}
    out.cooldownDurationObject = nil
    out.realCooldownDurationObject = nil
    out.chargeDurationObject = nil
    out.cooldownStart = nil
    out.cooldownDuration = nil
    out.cooldownModRate = nil
    out.chargeStart = nil
    out.chargeDuration = nil
    out.chargeModRate = nil
    out.cooldownEnable = false
    out.chargeEnable = false
    out.charges = nil
    out.maxCharges = nil
    out.cooldownActive = false
    out.cooldownOnGCD = false

    local backend = self:GetActionHotBackend()
    if not backend or backend.mode ~= "legacy-scalar" then return out end
    local cooldownStartRaw, cooldownDurationRaw, cooldownEnableRaw, cooldownModRateRaw = backend.getCooldownInfo(slot)
    local cooldownStartValue = SafeNumber(cooldownStartRaw)
    local cooldownDurationValue = SafeNumber(cooldownDurationRaw)
    local cooldownModRateValue = SafeNumber(cooldownModRateRaw)
    local cooldownEnableValue = SafeBoolean(cooldownEnableRaw)
    local active = cooldownEnableValue == true and cooldownDurationValue ~= nil and cooldownDurationValue > 0
    out.cooldownStart = cooldownStartValue
    out.cooldownDuration = cooldownDurationValue
    out.cooldownEnable = active
    out.cooldownActive = active
    out.cooldownOnGCD = cooldownDurationValue ~= nil and cooldownDurationValue <= 1.5
    out.cooldownModRate = cooldownModRateValue

    local charges, maxCharges, chargeStart, chargeDuration, chargeModRate = backend.getChargeInfo(slot)
    local chargeCountValue = SafeNumber(charges)
    local maxChargeValue = SafeNumber(maxCharges)
    out.charges = chargeCountValue
    out.maxCharges = maxChargeValue
    local chargeDurationValue = SafeNumber(chargeDuration)
    out.chargeStart = SafeNumber(chargeStart)
    out.chargeDuration = chargeDurationValue
    out.chargeModRate = SafeNumber(chargeModRate)
    out.chargeEnable = chargeDurationValue ~= nil and chargeDurationValue > 0 and chargeCountValue ~= nil and maxChargeValue ~= nil and chargeCountValue < maxChargeValue
    return out
end

function Adapter:ReadActionUsable(slot, out)
    CountRead("usable")
    out = out or {}
    if out.hasAction ~= true then
        out.usable = true
        out.noMana = false
        return out
    end

    local usable, noMana = self:IsUsableAction(slot)
    if usable ~= nil and noMana ~= nil then
        out.usable = usable
        out.noMana = noMana
    end
    return out
end

function Adapter:ReadActionRange(slot, out)
    CountRead("range")
    out = out or {}
    local range = self:IsActionInRange(slot)
    local rangeBool = SafeBoolean(range)
    if rangeBool ~= nil then
        out.inRange = rangeBool
    else
        out.inRange = nil
    end
    return out
end

function Adapter:ReadActionState(slot, out)
    CountRead("state")
    out = out or {}
    out.checked = out.hasAction and (self:IsCurrentAction(slot) or self:IsAutoRepeatAction(slot)) or false
    return out
end

function Adapter:ReadActionGlow(slot, out)
    CountRead("glow")
    out = out or {}
    if out.actionType == nil or out.actionID == nil then
        local actionType, id, subType = self:GetActionInfo(slot)
        local spellID, flyoutID, safeType, safeID, safeSubType = self:GetActionProcInfoFromInfo(actionType, id, subType)
        out.actionType = safeType
        out.actionID = safeID
        out.actionSubType = safeSubType
        out.actionSpellID = spellID
        out.procSpellID = spellID
        out.flyoutID = flyoutID
    end
    out.procGlow = out.hasAction and self:IsProcSpellOverlayed(out.procSpellID) or false
    return out
end

function Adapter:ReadActionVisual(slot, out)
    out = out or {}
    local backend = self:GetActionHotBackend()
    self:ReadActionIdentity(slot, out, nil, backend)
    self:ReadActionCooldown(slot, out)
    self:ReadActionUsable(slot, out)
    self:ReadActionRange(slot, out)
    self:ReadActionState(slot, out)
    self:ReadActionGlow(slot, out)
    return out
end

function Adapter:BuildPlayerAuraLookup(reuse)
    Unit = YUI.API and YUI.API.Unit or Unit
    if Unit and type(Unit.FillPlayerAuraDisplayLookup) == "function" then
        return Unit.FillPlayerAuraDisplayLookup(reuse)
    end
    local lookup = type(reuse) == "table" and reuse or {}
    WipeTable(lookup)
    return lookup, "aura-api-unavailable"
end

function Adapter:GetPetActionInfo(index)
    CountRead("petInfo")
    if not _G.GetPetActionInfo then return nil end
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = _G.GetPetActionInfo(index)
    return name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID
end

function Adapter:GetPetActionCooldown(index)
    CountRead("petCooldown")
    if not _G.GetPetActionCooldown then return nil end
    local start, duration, enable = _G.GetPetActionCooldown(index)
    return start, duration, enable
end

function Adapter:IsPetActionUsable(index)
    CountRead("petUsable")
    if not _G.GetPetActionSlotUsable then return true end
    return SafeBoolean(_G.GetPetActionSlotUsable(index)) == true
end

function Adapter:GetShapeshiftFormInfo(index)
    CountRead("stanceInfo")
    if not _G.GetShapeshiftFormInfo then return nil end
    local icon, active, castable, spellID = _G.GetShapeshiftFormInfo(index)
    return icon, SafeBoolean(active) == true, SafeBoolean(castable), SafeNumber(spellID)
end

function Adapter:GetShapeshiftFormCooldown(index)
    CountRead("stanceCooldown")
    if not _G.GetShapeshiftFormCooldown then return nil end
    local start, duration, enable = _G.GetShapeshiftFormCooldown(index)
    return SafeNumber(start), SafeNumber(duration), SafeBoolean(enable)
end

function Adapter:GetPossessInfo(index)
    CountRead("possessInfo")
    if not _G.GetPossessInfo then return nil end
    local texture, spellID, enabled = _G.GetPossessInfo(index)
    return texture, SafeNumber(spellID), SafeBoolean(enabled)
end

function Adapter:GetNumShapeshiftForms()
    return _G.GetNumShapeshiftForms and _G.GetNumShapeshiftForms() or 0
end

function Adapter:GetNativeFrames()
    local frames = {}
    for _, entry in ipairs(self:GetNativeFrameDisposal()) do
        frames[#frames + 1] = entry.name
    end
    return frames
end

function Adapter:GetNativeButtonDisposal()
    local frames = {}
    local ordinaryMode = Client.nonStructuralNativeSuppression == true and "retailSuppressed" or "actionButton"
    local function AddPrefix(prefix, count, mode)
        for index = 1, count do
            frames[#frames + 1] = { name = prefix .. tostring(index), mode = mode or "actionButton" }
        end
    end
    AddPrefix("ActionButton", 12, ordinaryMode)
    AddPrefix("MultiBarBottomLeftButton", 12, ordinaryMode)
    AddPrefix("MultiBarBottomRightButton", 12, ordinaryMode)
    AddPrefix("MultiBarRightButton", 12, ordinaryMode)
    AddPrefix("MultiBarLeftButton", 12, ordinaryMode)
    AddPrefix("MultiBar5Button", 12, ordinaryMode)
    AddPrefix("MultiBar6Button", 12, ordinaryMode)
    AddPrefix("MultiBar7Button", 12, ordinaryMode)
    AddPrefix("BonusActionButton", 12, ordinaryMode)
    if Client.nonStructuralNativeSuppression ~= true then
        for _, entry in ipairs(LEGACY_SPECIAL_BUTTON_DISPOSAL) do
            AddPrefix(entry[1], entry[2], entry[3])
        end
    end
    return frames
end

function Adapter:GetNativeFrameDisposal()
    local mainMode = Client.nonStructuralNativeSuppression == true and "retailSuppressed" or "main"
    local ordinaryMode = Client.nonStructuralNativeSuppression == true and "retailSuppressed" or "hiddenParent"
    local wrapperMode = Client.nonStructuralNativeSuppression == true and "retailSuppressed" or "hiddenParent"
    local frames = {
        { name = "MainActionBar", mode = mainMode },
        { name = "MultiBarRight", mode = ordinaryMode },
        { name = "MultiBarLeft", mode = ordinaryMode },
        { name = "MultiBarBottomLeft", mode = ordinaryMode },
        { name = "MultiBarBottomRight", mode = ordinaryMode },
        { name = "MultiBar5", mode = ordinaryMode },
        { name = "MultiBar6", mode = ordinaryMode },
        { name = "MultiBar7", mode = ordinaryMode },
        { name = "ActionBarParent", mode = wrapperMode },
        { name = "MainMenuBar", mode = wrapperMode },
        { name = "MainMenuBarArtFrame", mode = wrapperMode },
    }
    for _, entry in ipairs(LEGACY_SPECIAL_FRAME_DISPOSAL) do
        frames[#frames + 1] = { name = entry[1], mode = entry[2] }
    end
    return frames
end

function Adapter:GetSpecialFrameNames(kind)
    if kind == "extraAction" then
        return { "ExtraActionBarFrame", "ExtraActionButton1" }
    elseif kind == "zoneAbility" then
        return { "ZoneAbilityFrame" }
    elseif kind == "vehicleExit" then
        return {}
    end
    return {}
end

function Adapter:GetCapabilities()
    return {
        version = self:GetVersion(),
        actionPage = true,
        overridePage = true,
        vehiclePage = true,
        tempShapeshiftPage = true,
        availableBars = { "main", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" },
        actionBars = BAR_DEFINITIONS,
        specialFrameFlags = {
            extraAction = _G.ExtraActionBarFrame ~= nil or _G.ExtraActionButton1 ~= nil,
            zoneAbility = _G.ZoneAbilityFrame ~= nil,
            vehicleExit = true,
        },
        secretRisk = Client.secretRisk == true,
    }
end

function Adapter:GetStats()
    return self.apiReads or { total = 0, byReader = {} }
end
