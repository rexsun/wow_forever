local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local DEFAULTS = ns.DEFAULTS or {}
local State = ns.State or {}
local Util = ns.Util or {}
local C_Map = C_Map
local C_Timer = C_Timer
local C_Spell = C_Spell
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local OBJECTIVE_REFRESH_DELAY = 0.1
local OBJECTIVE_TICKER_SECONDS = 1
local OBJECTIVE_FRAME_LEVEL_OFFSET = 12

local FLAG_WIDGET_IDS = {
    [1640] = true, -- Warsong Gulch / Twin Peaks
    [1672] = true, -- Eye of the Storm
}

local ORB_WIDGET_IDS = {
    [1683] = true, -- Temple of Kotmogu
}

local function FlagMap(allianceFlagSpellID, hordeFlagSpellID)
    return {
        objectiveType = "FLAG",
        maxSlots = 2,
        [0] = allianceFlagSpellID,
        [1] = hordeFlagSpellID,
    }
end

local function OrbMap()
    return {
        objectiveType = "ORB",
        maxSlots = 4,
        [0] = 121164, -- Blue Orb of Power
        [1] = 121175, -- Purple Orb of Power
        [2] = 121176, -- Green Orb of Power
        [3] = 121177, -- Orange Orb of Power
    }
end

local WSG_FLAGS = FlagMap(156621, 156618)
local EOTS_FLAGS = FlagMap(34976, 34976)
local DEEPHAUL_CRYSTAL = FlagMap(434339, 434339)
local KOTMOGU_ORBS = OrbMap()

local OBJECTIVE_MAPS = {
    -- C_Map UI map IDs used by the objective module in BattleGroundEnemiesFixed.
    [1339] = WSG_FLAGS,        -- Warsong Gulch
    [206] = WSG_FLAGS,         -- Twin Peaks
    [112] = EOTS_FLAGS,        -- Eye of the Storm
    [397] = EOTS_FLAGS,        -- Eye of the Storm (rated)
    [2345] = DEEPHAUL_CRYSTAL, -- Deephaul Ravine
    [417] = KOTMOGU_ORBS,      -- Temple of Kotmogu

    -- Instance/map aliases seen in BattleGroundEnemiesFixed arena-token gating.
    [2106] = WSG_FLAGS,
    [726] = WSG_FLAGS,
    [566] = EOTS_FLAGS,
    [968] = EOTS_FLAGS,
    [2656] = DEEPHAUL_CRYSTAL,
}

local function EnsureObjectiveState()
    local objective = State.objectiveCarriers
    if type(objective) ~= "table" then
        objective = {}
        State.objectiveCarriers = objective
    end
    objective.byUnit = objective.byUnit or {}
    objective.rosterUnits = objective.rosterUnits or {}
    objective.nameToUnit = objective.nameToUnit or {}
    objective.shortNameToUnit = objective.shortNameToUnit or {}
    objective.ambiguousShortNames = objective.ambiguousShortNames or {}
    objective.chatFlagCarriers = objective.chatFlagCarriers or {}
    objective.chatOrbCarriers = objective.chatOrbCarriers or {}
    return objective
end

local function IsPlayerInBattleground()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return false end
    return inInstance == true and instanceType == "pvp"
end

local function GetActiveObjectiveMap()
    local mapID
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, result = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and not Util.IsSecretValue(result) then
            mapID = tonumber(result)
        end
    end
    if mapID and OBJECTIVE_MAPS[mapID] then
        return mapID, OBJECTIVE_MAPS[mapID]
    end

    if type(GetInstanceInfo) == "function" then
        local ok, instanceID = pcall(function()
            return select(8, GetInstanceInfo())
        end)
        if ok and not Util.IsSecretValue(instanceID) then
            instanceID = tonumber(instanceID)
            if instanceID and OBJECTIVE_MAPS[instanceID] then
                return instanceID, OBJECTIVE_MAPS[instanceID]
            end
        end
    end

    return mapID, nil
end

local function ShouldProcessObjectives()
    local db = RaidFrameAuras.db
    if not db or db.enabled ~= true or db.showObjectiveCarriers ~= true then
        return false
    end
    if not IsPlayerInBattleground() then
        return false
    end
    local mapID, config = GetActiveObjectiveMap()
    return config ~= nil, mapID, config
end

local function SafeUnitExists(unit)
    if type(UnitExists) ~= "function" or type(unit) ~= "string" then return false end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or Util.IsSecretValue(exists) then return false end
    return exists == true
end

local function SafeUnitGUID(unit)
    if type(UnitGUID) ~= "function" or type(unit) ~= "string" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or Util.IsSecretValue(guid) then return nil end
    return guid
end

local function SafeUnitIsUnit(left, right)
    if type(UnitIsUnit) ~= "function" then return false end
    local ok, sameUnit = pcall(UnitIsUnit, left, right)
    if not ok or Util.IsSecretValue(sameUnit) then return false end
    return sameUnit == true
end

local function Trim(value)
    value = tostring(value or "")
    if strtrim then
        return strtrim(value)
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function NormalizeRealm(realm)
    realm = Trim(realm)
    if realm == "" then return nil end
    return realm:gsub("%s+", "")
end

local function NormalizeCarrierName(name)
    if type(name) ~= "string" then return nil end
    local linkName = name:match("|Hplayer:([^:|]+)")
    if linkName and linkName ~= "" then
        name = linkName
    end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|h%[(.-)%]|h", "%1")
    name = Trim(name)
    if name == "" then return nil end
    local playerName, playerRealm = name:match("^([^%-]+)%-(.+)$")
    if playerName and playerRealm then
        playerRealm = NormalizeRealm(playerRealm)
        if playerRealm then
            return playerName .. "-" .. playerRealm
        end
    end
    return name
end

local function GetShortName(name)
    if type(name) ~= "string" then return nil end
    local short = name:match("^([^%-]+)")
    short = Trim(short)
    return short ~= "" and short or nil
end

local function GetPlayerRealm()
    if type(GetRealmName) ~= "function" then return nil end
    local ok, realm = pcall(GetRealmName)
    if not ok or Util.IsSecretValue(realm) then return nil end
    return NormalizeRealm(realm)
end

local function SafeUnitFullName(unit)
    if type(UnitFullName) ~= "function" then return nil, nil end
    local ok, name, realm = pcall(UnitFullName, unit)
    if not ok or Util.IsSecretValue(name) or Util.IsSecretValue(realm) then
        return nil, nil
    end
    name = Trim(name)
    if name == "" then return nil, nil end
    return name, NormalizeRealm(realm)
end

local function AddNameMapping(objective, nameKey, unit)
    if not nameKey or not unit then return end
    objective.nameToUnit[nameKey] = unit
    local shortName = GetShortName(nameKey)
    if not shortName then return end
    local previous = objective.shortNameToUnit[shortName]
    if previous and previous ~= unit then
        objective.ambiguousShortNames[shortName] = true
        objective.shortNameToUnit[shortName] = nil
    elseif not objective.ambiguousShortNames[shortName] then
        objective.shortNameToUnit[shortName] = unit
    end
end

local function BuildRosterLookups(objective)
    wipe(objective.rosterUnits)
    wipe(objective.nameToUnit)
    wipe(objective.shortNameToUnit)
    wipe(objective.ambiguousShortNames)

    if RaidFrameAuras.RebuildTrackedFrameRegistry and not State.trackedRegistryReady then
        RaidFrameAuras:RebuildTrackedFrameRegistry()
    end

    for unit in pairs(State.unitFrames or {}) do
        if RaidFrameAuras:IsTrackedUnit(unit) and SafeUnitExists(unit) then
            objective.rosterUnits[#objective.rosterUnits + 1] = unit
            local name, realm = SafeUnitFullName(unit)
            if name then
                AddNameMapping(objective, name, unit)
                if realm then
                    AddNameMapping(objective, name .. "-" .. realm, unit)
                else
                    local playerRealm = GetPlayerRealm()
                    if playerRealm then
                        AddNameMapping(objective, name .. "-" .. playerRealm, unit)
                    end
                end
            end
        end
    end
end

local function FindRosterUnitByCarrierName(objective, name)
    local nameKey = NormalizeCarrierName(name)
    if not nameKey then return nil end
    local unit = objective.nameToUnit[nameKey]
    if unit then return unit end
    local shortName = GetShortName(nameKey)
    if not shortName or objective.ambiguousShortNames[shortName] then return nil end
    return objective.shortNameToUnit[shortName]
end

local function FindRosterUnitByArenaToken(objective, arenaToken)
    if not SafeUnitExists(arenaToken) then return nil end

    for i = 1, #objective.rosterUnits do
        local unit = objective.rosterUnits[i]
        if SafeUnitIsUnit(arenaToken, unit) then
            return unit
        end
    end

    local arenaGUID = SafeUnitGUID(arenaToken)
    if not arenaGUID then return nil end
    for i = 1, #objective.rosterUnits do
        local unit = objective.rosterUnits[i]
        if SafeUnitGUID(unit) == arenaGUID then
            return unit
        end
    end
    return nil
end

local function SetObjectiveForUnit(objective, config, unit, arenaIndex, source)
    if not unit or not config or not arenaIndex then return false end
    local spellID = config[arenaIndex - 1]
    if not spellID then return false end
    objective.byUnit[unit] = {
        spellID = spellID,
        arenaIndex = arenaIndex,
        objectiveType = config.objectiveType,
        source = source,
    }
    return true
end

local function ApplyChatCarriers(objective, config)
    if config.objectiveType == "ORB" then
        for arenaIndex, name in pairs(objective.chatOrbCarriers) do
            if arenaIndex and arenaIndex >= 1 and arenaIndex <= config.maxSlots then
                local unit = FindRosterUnitByCarrierName(objective, name)
                SetObjectiveForUnit(objective, config, unit, arenaIndex, "chat")
            end
        end
        return
    end

    for name, arenaIndex in pairs(objective.chatFlagCarriers) do
        if arenaIndex and arenaIndex >= 1 and arenaIndex <= config.maxSlots then
            local unit = FindRosterUnitByCarrierName(objective, name)
            SetObjectiveForUnit(objective, config, unit, arenaIndex, "chat")
        end
    end
end

local function ApplyArenaFallback(objective, config)
    for arenaIndex = 1, config.maxSlots do
        local arenaToken = "arena" .. arenaIndex
        local unit = FindRosterUnitByArenaToken(objective, arenaToken)
        if unit and not objective.byUnit[unit] then
            SetObjectiveForUnit(objective, config, unit, arenaIndex, "arena")
        end
    end
end

function RaidFrameAuras:RebuildObjectiveCarrierAssignments()
    local objective = EnsureObjectiveState()
    wipe(objective.byUnit)
    objective.dirty = nil

    local active, mapID, config = ShouldProcessObjectives()
    objective.activeMapID = mapID
    objective.activeConfig = config
    if not active then
        return false
    end

    BuildRosterLookups(objective)
    ApplyChatCarriers(objective, config)
    ApplyArenaFallback(objective, config)
    return true
end

local function ResolveObjectiveTexture(spellID)
    if not spellID then return nil end
    local texture
    if type(GetSpellTexture) == "function" then
        local ok, result = pcall(GetSpellTexture, spellID)
        if ok and not Util.IsSecretValue(result) then
            texture = result
        end
    end
    return texture or FALLBACK_ICON
end

local function ConfigureObjectiveIcon(icon)
    if not icon then return end
    icon:EnableMouse(false)
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(false)
    end
end

local function EnsureObjectiveIcon(frame)
    local state = RaidFrameAuras:GetFrameState(frame)
    if not state then return nil end
    if state.objectiveCarrierIcon then return state.objectiveCarrierIcon end

    local icon = RaidFrameAuras:CreatePrivateFrame("Frame", "ObjectiveCarrierIcon", frame)
    icon.unitFrame = frame
    icon:Hide()

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetColorTexture(0, 0, 0, 0.85)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    ConfigureObjectiveIcon(icon)
    state.objectiveCarrierIcon = icon
    return icon
end

local function NumberKey(value)
    return tostring(math.floor((Util.AsSafeNumber(value, 0) or 0) * 100 + 0.5))
end

local function SetObjectiveSize(icon, size)
    if not icon or not size then return end
    size = Util.AsSafeNumber(size, DEFAULTS.objectiveCarrierSize or 22)
    if not size or size <= 0 then
        size = DEFAULTS.objectiveCarrierSize or 22
    end
    local key = NumberKey(size)
    if icon.rfaObjectiveSizeKey ~= key then
        icon:SetSize(size, size)
        icon.rfaLayoutWidth = size
        icon.rfaLayoutHeight = size
        icon.rfaLayoutScale = 1
        icon.rfaObjectiveSizeKey = key
    end
end

local function GetObjectiveAnchorTarget(frame)
    if RaidFrameAuras.GetAuraAnchorTarget then
        return RaidFrameAuras:GetAuraAnchorTarget(frame)
    end
    return frame
end

local function ApplyObjectiveLayout(frame, icon, preview)
    local db = RaidFrameAuras.db or DEFAULTS
    local size = Util.Clamp(db.objectiveCarrierSize, 8, 80, DEFAULTS.objectiveCarrierSize or 22)
    local anchor = db.objectiveCarrierAnchor or DEFAULTS.objectiveCarrierAnchor or "CENTER"
    local offsetX = tonumber(db.objectiveCarrierOffsetX) or DEFAULTS.objectiveCarrierOffsetX or 0
    local offsetY = tonumber(db.objectiveCarrierOffsetY) or DEFAULTS.objectiveCarrierOffsetY or 0
    local target = GetObjectiveAnchorTarget(frame)
    local strata = preview and "FULLSCREEN_DIALOG" or db.auraFrameStrata or DEFAULTS.auraFrameStrata or "LOW"
    local baseLevel = frame and frame.GetFrameLevel and frame:GetFrameLevel() or 1
    local level = baseLevel + (tonumber(db.auraFrameLevel) or DEFAULTS.auraFrameLevel or 35) + OBJECTIVE_FRAME_LEVEL_OFFSET

    SetObjectiveSize(icon, size)
    icon:SetScale(1)
    icon:SetFrameStrata(strata)
    icon:SetFrameLevel(level)

    icon:ClearAllPoints()
    icon:SetPoint(anchor, target, anchor, offsetX, offsetY)

    icon.border:ClearAllPoints()
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)

    icon.texture:ClearAllPoints()
    icon.texture:SetAllPoints(icon)

    return size, anchor, offsetX, offsetY, strata, level
end

local function PaintObjectiveCarrierIcon(frame, objectiveData, preview)
    if not frame or not objectiveData then return false end
    local icon = EnsureObjectiveIcon(frame)
    if not icon then return false end

    local texture = ResolveObjectiveTexture(objectiveData.spellID)
    local size, anchor, offsetX, offsetY, strata, level = ApplyObjectiveLayout(frame, icon, preview)
    local signature = tostring(objectiveData.spellID)
        .. ":" .. tostring(objectiveData.arenaIndex)
        .. ":" .. tostring(objectiveData.objectiveType)
        .. ":" .. tostring(texture)
        .. ":" .. NumberKey(size)
        .. ":" .. tostring(anchor)
        .. ":" .. NumberKey(offsetX)
        .. ":" .. NumberKey(offsetY)
        .. ":" .. tostring(strata)
        .. ":" .. tostring(level)
        .. ":" .. tostring(State.layoutVersion or 0)

    local state = RaidFrameAuras:GetFrameState(frame)
    if state and state.objectiveCarrierSignature == signature and icon:IsShown() then
        return true
    end

    icon.texture:SetTexture(texture)
    icon.texture:SetVertexColor(1, 1, 1, 1)
    icon.border:SetAlpha(0.85)
    icon:Show()

    if state then
        state.objectiveCarrierSignature = signature
    end
    return true
end

function RaidFrameAuras:HideFrameObjectiveCarrier(frame)
    local state = frame and State.frameStates and State.frameStates[frame]
    if not state then return end
    state.objectiveCarrierSignature = nil
    local icon = state.objectiveCarrierIcon
    if icon then
        icon:Hide()
    end
end

function RaidFrameAuras:RefreshObjectiveCarrierIcon(frame)
    local db = self.db
    if not frame or not db or db.enabled ~= true or db.showObjectiveCarriers ~= true then
        self:HideFrameObjectiveCarrier(frame)
        return
    end
    local unit = frame.rfaUnit or (Util.GetFrameUnit and Util.GetFrameUnit(frame))
    if not self:IsTrackedUnit(unit) or not SafeUnitExists(unit) then
        self:HideFrameObjectiveCarrier(frame)
        return
    end

    local objective = EnsureObjectiveState()
    if objective.dirty then
        self:RebuildObjectiveCarrierAssignments()
    end
    local objectiveData = objective.byUnit and objective.byUnit[unit]
    if not objectiveData then
        self:HideFrameObjectiveCarrier(frame)
        return
    end

    PaintObjectiveCarrierIcon(frame, objectiveData, false)
end

function RaidFrameAuras:RefreshObjectiveCarrierPreview(frame)
    if not frame or not self.db or self.db.showObjectiveCarriers ~= true then
        self:HideFrameObjectiveCarrier(frame)
        return
    end
    PaintObjectiveCarrierIcon(frame, {
        spellID = 156621,
        arenaIndex = 1,
        objectiveType = "FLAG",
        source = "preview",
    }, true)
end

local EnsureObjectiveTicker

local function RefreshObjectiveCarrierFrames()
    if EnsureObjectiveTicker then
        EnsureObjectiveTicker()
    end
    if RaidFrameAuras.RebuildObjectiveCarrierAssignments then
        RaidFrameAuras:RebuildObjectiveCarrierAssignments()
    end
    if RaidFrameAuras.ForEachTrackedFrame then
        RaidFrameAuras:ForEachTrackedFrame(function(frame)
            RaidFrameAuras:RefreshObjectiveCarrierIcon(frame)
        end)
    end
end

function RaidFrameAuras:RefreshObjectiveCarrierFrames()
    RefreshObjectiveCarrierFrames()
end

local function StopObjectiveTicker(objective)
    if objective and objective.ticker then
        objective.ticker:Cancel()
        objective.ticker = nil
    end
end

EnsureObjectiveTicker = function()
    local objective = EnsureObjectiveState()
    local active = ShouldProcessObjectives()
    if not active then
        StopObjectiveTicker(objective)
        return
    end
    if objective.ticker or not C_Timer or not C_Timer.NewTicker then
        return
    end
    objective.ticker = C_Timer.NewTicker(OBJECTIVE_TICKER_SECONDS, function()
        RefreshObjectiveCarrierFrames()
    end)
end

local function MarkObjectiveDirty()
    EnsureObjectiveState().dirty = true
end

local function ScheduleObjectiveRefresh(delay)
    local objective = EnsureObjectiveState()
    objective.refreshToken = (objective.refreshToken or 0) + 1
    local token = objective.refreshToken
    MarkObjectiveDirty()

    local function RunRefresh()
        if token ~= objective.refreshToken then return end
        EnsureObjectiveTicker()
        RefreshObjectiveCarrierFrames()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, RunRefresh)
    else
        RunRefresh()
    end
end

function RaidFrameAuras:MarkObjectiveCarriersDirty()
    ScheduleObjectiveRefresh(0)
end

local function FindLocalizedToken(text, ...)
    if type(text) ~= "string" then return nil end
    for i = 1, select("#", ...) do
        local token = select(i, ...)
        if type(token) == "string" and token ~= "" and text:find(token, 1, true) then
            return token
        end
    end
    return nil
end

local function GetFlagArenaIndex(flagName)
    if type(flagName) ~= "string" then return nil end
    local allianceText = ALLIANCE or FACTION_ALLIANCE or "Alliance"
    local hordeText = HORDE or FACTION_HORDE or "Horde"
    if FindLocalizedToken(flagName, allianceText, "Alliance") then
        return 1
    end
    if FindLocalizedToken(flagName, hordeText, "Horde") then
        return 2
    end
    return nil
end

local ORB_COLOR_TO_ARENA_INDEX = {
    Blue = 1,
    Purple = 2,
    Green = 3,
    Orange = 4,
}

local function AddOrbColorToken(token, arenaIndex)
    if type(token) == "string" and token ~= "" then
        ORB_COLOR_TO_ARENA_INDEX[token] = arenaIndex
    end
end

AddOrbColorToken(BLUE, 1)
AddOrbColorToken(PURPLE, 2)
AddOrbColorToken(GREEN, 3)
AddOrbColorToken(ORANGE, 4)

local function GetOrbArenaIndex(message, orbColor)
    if type(orbColor) == "string" then
        local direct = ORB_COLOR_TO_ARENA_INDEX[orbColor]
        if direct then return direct end
    end
    for colorName, arenaIndex in pairs(ORB_COLOR_TO_ARENA_INDEX) do
        if type(colorName) == "string" and message and message:find(colorName, 1, true) then
            return arenaIndex
        end
    end
    return nil
end

local function SetChatFlagCarrier(objective, name, arenaIndex)
    name = NormalizeCarrierName(name)
    if not name or not arenaIndex then return false end
    for trackedName, trackedSlot in pairs(objective.chatFlagCarriers) do
        if trackedSlot == arenaIndex and trackedName ~= name then
            objective.chatFlagCarriers[trackedName] = nil
        end
    end
    objective.chatFlagCarriers[name] = arenaIndex
    return true
end

local function SetChatOrbCarrier(objective, name, arenaIndex)
    name = NormalizeCarrierName(name)
    if not name or not arenaIndex then return false end
    objective.chatOrbCarriers[arenaIndex] = name
    return true
end

local function ClearChatFlagCarrierByName(objective, name)
    name = NormalizeCarrierName(name)
    if name then
        objective.chatFlagCarriers[name] = nil
    end
end

local function ClearChatCarrierSlot(objective, arenaIndex)
    objective.chatOrbCarriers[arenaIndex] = nil
    for name, slot in pairs(objective.chatFlagCarriers) do
        if slot == arenaIndex then
            objective.chatFlagCarriers[name] = nil
        end
    end
end

local function HandleObjectiveChatMessage(message)
    if type(message) ~= "string" or Util.IsSecretValue(message) then return false end
    local objective = EnsureObjectiveState()
    local changed = false

    local pickedUpBy = message:match("picked up by (.+)%!")
    if pickedUpBy then
        local flagName = message:match("The (.-) was picked up")
        local arenaIndex = GetFlagArenaIndex(flagName)
        if SetChatFlagCarrier(objective, pickedUpBy, arenaIndex) then
            changed = true
        end
        return changed
    end

    local droppedBy = message:match("dropped by (.+)%!")
    if droppedBy then
        ClearChatFlagCarrierByName(objective, droppedBy)
        return true
    end

    local orbCarrierName = message:match("^(.-) has taken the")
    local orbColor = message:match("the |c%x+([^|]+)|r orb")
    if orbCarrierName then
        local arenaIndex = GetOrbArenaIndex(message, orbColor)
        if SetChatOrbCarrier(objective, orbCarrierName, arenaIndex) then
            changed = true
        end
        return changed
    end

    if message:find("captured the", 1, true)
        or message:find("returned to its base by", 1, true)
        or message:find("placed at their bases", 1, true) then
        wipe(objective.chatFlagCarriers)
        return true
    end

    if message:find("wins", 1, true) then
        wipe(objective.chatFlagCarriers)
        wipe(objective.chatOrbCarriers)
        return true
    end

    return changed
end

local function HandleArenaOpponentUpdate(unitToken, updateReason)
    if type(unitToken) ~= "string" then return false end
    if updateReason ~= "cleared" and updateReason ~= "destroyed" and updateReason ~= "unseen" then
        return false
    end
    local arenaIndex = tonumber(unitToken:match("^arena(%d+)$"))
    if not arenaIndex then return false end
    ClearChatCarrierSlot(EnsureObjectiveState(), arenaIndex)
    return true
end

function RaidFrameAuras:InitializeObjectiveCarriers()
    if self.objectiveCarriersInitialized then return end
    self.objectiveCarriersInitialized = true

    local eventFrame = self:CreatePrivateFrame("Frame", "ObjectiveCarrierEvents")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
    eventFrame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
    eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            local objective = EnsureObjectiveState()
            wipe(objective.chatFlagCarriers)
            wipe(objective.chatOrbCarriers)
            ScheduleObjectiveRefresh(0.35)
            return
        end

        if event == "GROUP_ROSTER_UPDATE" then
            ScheduleObjectiveRefresh(OBJECTIVE_REFRESH_DELAY)
            return
        end

        if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
            or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
            or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
            if HandleObjectiveChatMessage(...) then
                ScheduleObjectiveRefresh(0)
            end
            return
        end

        if not IsPlayerInBattleground() then
            ScheduleObjectiveRefresh(0)
            return
        end

        if event == "UPDATE_UI_WIDGET" then
            local widgetInfo = ...
            local widgetID = widgetInfo and widgetInfo.widgetID
            if FLAG_WIDGET_IDS[widgetID] or ORB_WIDGET_IDS[widgetID] then
                ScheduleObjectiveRefresh(OBJECTIVE_REFRESH_DELAY)
            end
        elseif event == "ARENA_OPPONENT_UPDATE" then
            if HandleArenaOpponentUpdate(...) then
                ScheduleObjectiveRefresh(0)
            else
                ScheduleObjectiveRefresh(OBJECTIVE_REFRESH_DELAY)
            end
        elseif event == "UNIT_CLASSIFICATION_CHANGED" then
            ScheduleObjectiveRefresh(OBJECTIVE_REFRESH_DELAY)
        end
    end)

    EnsureObjectiveState().eventFrame = eventFrame
    ScheduleObjectiveRefresh(0.35)
end
