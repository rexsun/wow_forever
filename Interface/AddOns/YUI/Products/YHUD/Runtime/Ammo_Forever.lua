local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or YUI.IsForever ~= true then return end

local Ammo = {}
YHUD.Ammo = Ammo
Ammo.SOURCE_TYPE = "yhud.ammo-count"
Ammo.ENTRY_KEY = "ammo:equipped"
Ammo.FALLBACK_ICON = 132383

function Ammo:ResolveIcon(state, queryCurrent)
    if queryCurrent then
        local item = YUI.API and YUI.API.Item
        state = item and item.ReadEquippedAmmo and item.ReadEquippedAmmo()
    end
    return state and state.icon or self.FALLBACK_ICON
end

function Ammo:GetPreviewIcon()
    return self:ResolveIcon(nil, true)
end

function Ammo:IsSupported(specKey)
    local unit = YUI.API and YUI.API.Unit
    return YUI.IsForever == true and unit and unit.GetClassToken
        and unit.GetClassToken("player") == "HUNTER"
        and type(specKey) == "string" and specKey:match("^HUNTER:") ~= nil
end

function Ammo:IsApplicable(specKey)
    if not self:IsSupported(specKey) then return false end
    local item = YUI.API and YUI.API.Item
    return not (item and item.GetAmmoCapability and item.GetAmmoCapability() == false)
end

function Ammo:BuildEntry()
    return {
        entryKey = self.ENTRY_KEY, sourceKey = self.ENTRY_KEY,
        sourceIdentity = "player", sourceType = self.SOURCE_TYPE,
        semantic = "cooldown", origin = "preset", presetKey = self.ENTRY_KEY,
        crossSpecMaterialization = "immediate",
        crossSpecEligibility = { classFile = "HUNTER" },
        contentScope = YHUD.CONTENT_SCOPE_SPEC,
        nameKey = "designer.quick.ammo",
        name = YHUD:T("designer.quick.ammo", "弹药数量"),
        icon = self.FALLBACK_ICON, compatibleViews = { icon = true },
        contract = {
            capability = "display", view = "self", group = "free",
            style = "static", fallback = "hide", status = "verified",
        },
    }
end

local function CreateState()
    return {
        sourceKind = "ammo", available = true, resolved = false,
        isEnabled = true, secret = false, startTime = 0, duration = 0,
        nameKey = "monitor.ammo.unknown",
    }
end

local function Read(_, state)
    local item = YUI.API.Item
    local previousID, previousIcon, previousCount = state.itemID, state.icon, state.displayCount
    local previousSlot, previousName = state.slotID, state.nameKey
    local previousResolved, previousSecret = state.resolved, state.secret
    local previousAvailable = state.available
    item.ReadEquippedAmmo(state)
    state.available = state.ammoStatus ~= "unsupported"
    state.nameKey = state.ammoStatus == "unsupported" and "monitor.ammo.unsupported"
        or state.ammoStatus == "missing" and "monitor.ammo.missing"
        or state.ammoStatus == "unknown" and "monitor.ammo.unknown"
        or "designer.quick.ammo"
    if state.ammoStatus == "unsupported" then
        state.lastAmmoID, state.lastAmmoIcon = nil, nil
    elseif state.nameKey == "designer.quick.ammo" then
        state.lastAmmoID, state.lastAmmoIcon = state.itemID, state.icon
    elseif state.nameKey == "monitor.ammo.missing" and state.lastAmmoID then
        -- An exhausted stack can clear the slot. Keep its identity only while
        -- the carried count is confirmed zero; an unequipped supply stays missing.
        local remaining = item.GetCount(state.lastAmmoID, false, false, false, false)
        local security = YUI.API and YUI.API.Security
        local isSecret = security and security.IsSecretValue or _G.issecretvalue
        if isSecret and isSecret(remaining) then
            state.nameKey, state.resolved, state.secret = "monitor.ammo.unknown", false, true
        elseif type(remaining) ~= "number" or remaining < 0 then
            state.nameKey, state.resolved = "monitor.ammo.unknown", false
        elseif remaining == 0 then
            state.itemID, state.icon = state.lastAmmoID, state.lastAmmoIcon
            state.displayCount, state.nameKey = 0, "designer.quick.ammo"
        else
            state.lastAmmoID, state.lastAmmoIcon = nil, nil
        end
    end
    return previousID ~= state.itemID or previousIcon ~= state.icon
        or previousCount ~= state.displayCount or previousSlot ~= state.slotID
        or previousName ~= state.nameKey or previousResolved ~= state.resolved
        or previousSecret ~= state.secret
        or previousAvailable ~= state.available
end

function Ammo:RegisterSourceType()
    if self.registered then return true end
    local item = YUI.API and YUI.API.Item
    if not (item and item.ReadEquippedAmmo) then return nil, "item-api-unavailable" end
    local registered, code = YUI.Monitor:RegisterSourceType(self.SOURCE_TYPE, {
        createState = CreateState, read = Read,
        getIdentity = function() return "player" end,
        events = {
            { event = "BAG_UPDATE_DELAYED", all = true },
            { event = "PLAYER_EQUIPMENT_CHANGED", all = true },
            { event = "UNIT_INVENTORY_CHANGED", unit = "player", all = true },
            { event = "PLAYER_ENTERING_WORLD", all = true },
            { event = "PLAYER_REGEN_ENABLED", all = true },
        },
    })
    if not registered and code ~= "source-type-exists" then return nil, code end
    self.registered = true
    return true
end
