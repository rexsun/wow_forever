local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local State = ns.State or {}
local Util = ns.Util or {}

local MASQUE_ADDON_NAME = "Raid Frame Auras"
local MASQUE_GROUP_BUFFS = "Buffs"
local MASQUE_GROUP_DEBUFFS = "Debuffs"
local MASQUE_GROUP_BUFFS_ID = "RaidFrameAuras_Buffs"
local MASQUE_GROUP_DEBUFFS_ID = "RaidFrameAuras_Debuffs"

State.masqueIcons = State.masqueIcons or setmetatable({}, { __mode = "k" })
State.masqueGroups = State.masqueGroups or {}
State.masqueReskinPending = State.masqueReskinPending or {}

local function DebugLog(text, ...)
    if Util.DebugLog then
        Util.DebugLog(text, ...)
    end
end

local function IsMasqueEnabled()
    return RaidFrameAuras.GetOption and RaidFrameAuras:GetOption("masqueEnabled") == true
end

local function IsMasqueUpdateBlocked()
    return InCombatLockdown and InCombatLockdown()
end

local function DeferMasqueUpdate()
    State.masqueUpdatePending = true
end

local function ClearPendingMasqueReskins()
    if wipe then
        wipe(State.masqueReskinPending)
        return
    end
    for group in pairs(State.masqueReskinPending) do
        State.masqueReskinPending[group] = nil
    end
end

local function CallWithMasqueScaleIgnored(group, callback)
    if type(callback) ~= "function" then
        return false, "missing callback"
    end

    local db = group and group.db
    if type(db) ~= "table" then
        return pcall(callback)
    end

    -- RFA owns aura icon sizing. Masque may skin the icon, but its group scale
    -- must not change RFA's configured/category/auto-scaled dimensions.
    local hadScale = db.Scale ~= nil
    local previousScale = db.Scale
    db.Scale = 1

    local ok, result = pcall(callback)

    if hadScale then
        db.Scale = previousScale
    else
        db.Scale = nil
    end

    return ok, result
end

local function RestoreRFAIconGeometry(icon)
    if icon and State.masqueIcons[icon] and RaidFrameAuras.RestoreAuraIconRegionGeometry then
        RaidFrameAuras:RestoreAuraIconRegionGeometry(icon)
    end
end

local function RemoveIconFromMasque(icon)
    if not icon then
        return false
    end

    local changed = icon.rfaMasqueGroup ~= nil or icon.rfaMasqueButtonType ~= nil
    if icon.rfaMasqueGroup and type(icon.rfaMasqueGroup.RemoveButton) == "function" then
        local ok, err = pcall(icon.rfaMasqueGroup.RemoveButton, icon.rfaMasqueGroup, icon)
        if not ok then
            DebugLog("Masque RemoveButton failed: %s", tostring(err))
        end
    end

    icon.rfaMasqueGroup = nil
    icon.rfaMasqueButtonType = nil
    RestoreRFAIconGeometry(icon)
    return changed
end

local function RestoreMasqueGroupIconGeometry(group, button)
    if button then
        RestoreRFAIconGeometry(button)
        return
    end

    for icon in pairs(State.masqueIcons) do
        if icon.rfaMasqueGroup == group then
            RestoreRFAIconGeometry(icon)
        end
    end
end

local function EnsureMasqueGroupScaleIgnored(group)
    if not group or group.rfaMasqueScaleIgnored then
        return
    end

    local originalReSkin = group.ReSkin
    if type(originalReSkin) ~= "function" then
        return
    end

    group.rfaMasqueOriginalReSkin = originalReSkin
    group.ReSkin = function(self, button)
        local ok, result = CallWithMasqueScaleIgnored(self, function()
            return originalReSkin(self, button)
        end)
        if not ok then
            DebugLog("Masque ReSkin failed: %s", tostring(result))
        else
            RestoreMasqueGroupIconGeometry(self, button)
        end
        return result
    end
    group.rfaMasqueScaleIgnored = true
end

local function ResolveMasque()
    if State.masque then
        return State.masque
    end
    if not LibStub then
        return nil
    end

    local ok, masque = pcall(function()
        return LibStub("Masque", true)
    end)
    if ok and type(masque) == "table" and type(masque.Group) == "function" then
        State.masque = masque
        return masque
    end
    return nil
end

local function GetMasqueGroup(auraType)
    local key = auraType == "BUFF" and "BUFF" or "DEBUFF"
    if State.masqueGroups[key] then
        EnsureMasqueGroupScaleIgnored(State.masqueGroups[key])
        return State.masqueGroups[key]
    end

    local masque = ResolveMasque()
    if not masque then
        return nil
    end

    local groupName = key == "BUFF" and MASQUE_GROUP_BUFFS or MASQUE_GROUP_DEBUFFS
    local staticID = key == "BUFF" and MASQUE_GROUP_BUFFS_ID or MASQUE_GROUP_DEBUFFS_ID
    local ok, group = pcall(masque.Group, masque, MASQUE_ADDON_NAME, groupName, staticID)
    if ok and group then
        State.masqueGroups[key] = group
        EnsureMasqueGroupScaleIgnored(group)
        return group
    end

    DebugLog("Masque group creation failed for %s: %s", tostring(key), tostring(group))
    return nil
end

local function GetMasqueButtonType(auraType)
    return auraType == "BUFF" and "Buff" or "Debuff"
end

local function EnsureMasqueGroups()
    local buffs = GetMasqueGroup("BUFF")
    local debuffs = GetMasqueGroup("DEBUFF")
    return buffs ~= nil or debuffs ~= nil
end

local function ScheduleMasqueReSkin(group)
    if not IsMasqueEnabled() then
        return
    end
    if not group or type(group.ReSkin) ~= "function" or State.masqueReskinPending[group] then
        return
    end

    State.masqueReskinPending[group] = true
    local function Run()
        State.masqueReskinPending[group] = nil
        if not IsMasqueEnabled() then
            return
        end
        local ok, err = CallWithMasqueScaleIgnored(group, function()
            return group.ReSkin(group)
        end)
        if not ok then
            DebugLog("Masque ReSkin failed: %s", tostring(err))
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function RegisterIcon(icon, auraType)
    if not icon then
        return false
    end

    auraType = auraType == "BUFF" and "BUFF" or "DEBUFF"
    State.masqueIcons[icon] = auraType

    if not IsMasqueEnabled() then
        if IsMasqueUpdateBlocked() then
            if icon.rfaMasqueGroup then
                DeferMasqueUpdate()
            end
            return false
        end
        return RemoveIconFromMasque(icon)
    end

    if IsMasqueUpdateBlocked() then
        DeferMasqueUpdate()
        return false
    end

    local group = GetMasqueGroup(auraType)
    if not group or type(group.AddButton) ~= "function" then
        return false
    end

    local buttonType = GetMasqueButtonType(auraType)
    if icon.rfaMasqueGroup == group and icon.rfaMasqueButtonType == buttonType then
        RestoreRFAIconGeometry(icon)
        return true
    end

    if icon.rfaMasqueGroup and type(icon.rfaMasqueGroup.RemoveButton) == "function" then
        pcall(icon.rfaMasqueGroup.RemoveButton, icon.rfaMasqueGroup, icon)
    end

    local ok, err = CallWithMasqueScaleIgnored(group, function()
        return group.AddButton(group, icon, {
            Icon = icon.texture,
            Cooldown = icon.cooldown,
        }, buttonType)
    end)
    if not ok then
        icon.rfaMasqueGroup = nil
        icon.rfaMasqueButtonType = nil
        DebugLog("Masque AddButton failed for %s icon: %s", tostring(auraType), tostring(err))
        return false
    end

    icon.rfaMasqueGroup = group
    icon.rfaMasqueButtonType = buttonType
    RestoreRFAIconGeometry(icon)
    ScheduleMasqueReSkin(group)
    return true
end

local function DisableMasqueSupport()
    ClearPendingMasqueReskins()
    local changed = false
    for icon in pairs(State.masqueIcons) do
        if RemoveIconFromMasque(icon) then
            changed = true
        end
    end
    return changed
end

local function EnableMasqueSupport()
    if not ResolveMasque() then
        return false
    end
    EnsureMasqueGroups()

    local changed = false
    for icon, auraType in pairs(State.masqueIcons) do
        if RegisterIcon(icon, auraType) then
            changed = true
        end
    end
    return changed
end

function RaidFrameAuras:InitializeMasque()
    return self:ApplyMasqueEnabledState()
end

function RaidFrameAuras:ApplyMasqueEnabledState()
    if IsMasqueUpdateBlocked() then
        DeferMasqueUpdate()
        return false
    end

    State.masqueUpdatePending = nil
    if IsMasqueEnabled() then
        return EnableMasqueSupport()
    end
    return DisableMasqueSupport()
end

function RaidFrameAuras:ProcessPendingMasqueUpdate()
    if not State.masqueUpdatePending or IsMasqueUpdateBlocked() then
        return false
    end

    State.masqueUpdatePending = nil
    local changed = self:ApplyMasqueEnabledState() == true
    if changed and self.ScheduleRefreshBurst then
        self:ScheduleRefreshBurst("layout")
    end
    return changed
end

function RaidFrameAuras:RegisterMasqueAuraIcon(icon, auraType)
    return RegisterIcon(icon, auraType)
end

function RaidFrameAuras:ScheduleMasqueIconReskin(icon)
    if IsMasqueEnabled() and icon and icon.rfaMasqueGroup then
        ScheduleMasqueReSkin(icon.rfaMasqueGroup)
    end
end

function RaidFrameAuras:IsMasqueEnabled()
    return IsMasqueEnabled()
end

function RaidFrameAuras:IsMasqueAvailable()
    return ResolveMasque() ~= nil
end
