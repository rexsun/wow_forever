local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Util = ns.Util or {}
local State = ns.State or {}

local function IsPlayerInCombat()
    return (UnitAffectingCombat and UnitAffectingCombat("player") == true)
        or (InCombatLockdown and InCombatLockdown() == true)
end

local function NormalizeAuraType(iconOrType)
    if type(iconOrType) == "table" then
        return iconOrType.auraType
    end
    return iconOrType
end

local function PositionAuraTooltip(icon, isBuff)
    local frame = icon.unitFrame
    local db = RaidFrameAuras.db
    local anchor = isBuff and db.tooltipBuffAnchor or db.tooltipDebuffAnchor
    local anchorPos = isBuff and db.tooltipBuffAnchorPos or db.tooltipDebuffAnchorPos
    local x = isBuff and db.tooltipBuffX or db.tooltipDebuffX
    local y = isBuff and db.tooltipBuffY or db.tooltipDebuffY

    if anchor == "CURSOR" then
        GameTooltip:SetOwner(icon, "ANCHOR_CURSOR")
    elseif anchor == "FRAME" then
        GameTooltip:SetOwner(icon, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint(Util.GetOppositeAnchor(anchorPos), icon, anchorPos, x or 0, y or 0)
    else
        GameTooltip_SetDefaultAnchor(GameTooltip, icon)
    end
end

local function MarkTooltipActivity()
    State.tooltipActivitySerial = (State.tooltipActivitySerial or 0) + 1
    return State.tooltipActivitySerial
end

local function IsSuppressedTooltipOwner(owner)
    if not owner or not GameTooltip.GetOwner then
        return true
    end

    local ok, tooltipOwner = pcall(GameTooltip.GetOwner, GameTooltip)
    if not ok then
        return true
    end

    if tooltipOwner == owner then
        return true
    end

    local unitFrame = owner.unitFrame
    return unitFrame ~= nil and tooltipOwner == unitFrame
end

function RaidFrameAuras:IsAuraTooltipAllowed(iconOrType)
    local db = self.db
    if not db or db.enabled == false then return false end

    local auraType = NormalizeAuraType(iconOrType)
    if auraType == "BUFF" then
        if not db.tooltipBuffEnabled then return false end
        if db.tooltipBuffDisableInCombat and IsPlayerInCombat() then return false end
        return true
    elseif auraType == "DEBUFF" then
        if not db.tooltipDebuffEnabled then return false end
        if db.tooltipDebuffDisableInCombat and IsPlayerInCombat() then return false end
        return true
    end

    return false
end

function RaidFrameAuras:SuppressAuraTooltip(owner)
    if not GameTooltip or not GameTooltip.Hide then return end
    local serial = MarkTooltipActivity()
    GameTooltip:Hide()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if State.tooltipActivitySerial == serial and IsSuppressedTooltipOwner(owner) then
                GameTooltip:Hide()
            end
        end)
    end
end

function RaidFrameAuras:ShowAuraTooltip(icon)
    if not icon or not icon:IsShown() then return end
    local db = self.db
    if not db then return end
    local isBuff = icon.auraType == "BUFF"
    if not self:IsAuraTooltipAllowed(icon) then
        self:SuppressAuraTooltip(icon)
        return
    end
    if not icon.auraData or not icon.auraData.auraInstanceID then return end
    if icon.rfaPreviewSpellId and GameTooltip.SetSpellByID then
        MarkTooltipActivity()
        PositionAuraTooltip(icon, isBuff)
        GameTooltip:SetSpellByID(icon.rfaPreviewSpellId)
        GameTooltip:Show()
        return
    end
    local rawUnit = icon.rfaUnit or (icon.unitFrame and icon.unitFrame.rfaUnit) or Util.GetFrameUnit(icon.unitFrame)
    local unit = Util.GetCleanRosterUnitForTooltip(icon.unitFrame, rawUnit) or rawUnit
    if not unit or not GameTooltip.SetUnitAuraByAuraInstanceID then return end
    MarkTooltipActivity()
    PositionAuraTooltip(icon, isBuff)
    GameTooltip:SetUnitAuraByAuraInstanceID(unit, icon.auraData.auraInstanceID)
    GameTooltip:Show()
end
