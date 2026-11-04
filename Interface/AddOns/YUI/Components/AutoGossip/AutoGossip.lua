local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components and YUI.Event) then return end

local Components = YUI.Components
local Event = YUI.Event
local Gossip = YUI.API and YUI.API.Gossip
local Quest = YUI.API and YUI.API.Quest
local DIALOGUE_SUPPORTED = YUI.IsRetail or YUI.IsForever
local CLIENT = YUI.IsForever and "forever" or YUI.IsMists and "mists" or YUI.IsWrath and "wrath" or "mainline"
local KeyAPI = YUI.WOW_API
local Security = YUI.API and YUI.API.Security
local L = YUI.Locale and YUI.Locale:Get("AutoGossip") or {}

local FEATURE_KEY = "AutoGossip"
local CONFIG_KEY = "AutoGossip_Config"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
        and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"

local MAX_OPTIONS = 32
local MAX_SELECTED_PAGES = 32
local MAX_CUSTOM_OPTIONS = 64
local MAX_CUSTOM_NAME_BYTES = 160
local MAX_CUSTOM_NAME_CHARS = 48
local MAX_SAFE_INTEGER = 9007199254740991
local SELECTION_DELAY_SECONDS = 0.05

local PRESETS_BY_CLIENT = { mainline = {
    { key = "caveEntrance", nameKey = "preset.cave_entrance", ids = { 135009 } },
    { key = "caveBossTwo", nameKey = "preset.cave_boss_two", ids = { 135010 } },
    { key = "plotDisguise", nameKey = "preset.plot_disguise", ids = { 131567 } },
    { key = "plotBarQuest", nameKey = "preset.plot_bar_quest", ids = { 131502 } },
}
}
local PRESETS = PRESETS_BY_CLIENT[CLIENT] or {}

local PRESET_BY_ID = {}
local DEFAULT_PRESET_STATES = {}
for _, preset in ipairs(PRESETS) do
    DEFAULT_PRESET_STATES[preset.key] = true
    for _, optionID in ipairs(preset.ids) do PRESET_BY_ID[optionID] = preset.key end
end

local DEFAULTS = {
    uniqueEnabled = false,
    approvedEnabled = true,
    showOptionIDs = false,
    autoAccept = false,
    autoTurnIn = false,
    pauseMulti = false,
    modifierMode = "none",
    modifierKey = "SHIFT",
    dialogueVersions = {},
}
local MODIFIER_CHECKERS = { SHIFT = "IsShiftKeyDown", CTRL = "IsControlKeyDown", ALT = "IsAltKeyDown" }
local EMPTY_DEFAULTS = {}

local runtimeOwner = {}
local modifierOwner = {}
local profileOwner = {}
local profileCallbacksRegistered = false
local featureEnabled = false
local sectionCollapsed = { advanced = true }
local pendingCustomName = ""
local pendingCustomID = ""

local runtime = {
    active = false,
    db = nil,
    approvedSet = nil,
    selectedSignatures = {},
    selectedPageCount = 0,
    records = {},
    signatureParts = {},
    idParts = {},
    optionIDLabel = nil,
    selectionGeneration = 0,
    selectionPending = false,
    page = nil,
    npcGUID = nil,
    interactionOpen = false,
    interactionPaused = false,
    questAttempts = {},
    questActionCount = 0,
    questTransition = false,
    modifierListening = false,
}

local function T(key, fallback)
    return type(L) == "table" and L[key] or fallback or key
end

local function PrintSelectionAttempt(name)
    if type(YUI.Print) ~= "function" then return end
    YUI:Print(string.format(
        T("message.selection_attempted", "|cffffff00尝试自动选择|r  %s"),
        name
    ))
end

local function ClearTable(value)
    for key in pairs(value) do value[key] = nil end
end

local function CopyDefault(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = CopyDefault(child) end
    return result
end

local function FillMissing(target, defaults)
    if type(target) ~= "table" then return end
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyDefault(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            FillMissing(target[key], value)
        end
    end
end

local function NormalizeID(value)
    local ok, optionID = pcall(tonumber, value)
    if not ok or not optionID or optionID <= 0 or optionID > MAX_SAFE_INTEGER
        or optionID ~= math.floor(optionID) then return nil end
    return optionID
end

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function IsCustomNameValid(name)
    if name == "" or #name > MAX_CUSTOM_NAME_BYTES then return false end
    if type(_G.strlenutf8) == "function" then
        local ok, length = pcall(_G.strlenutf8, name)
        if not ok or type(length) ~= "number" or length > MAX_CUSTOM_NAME_CHARS then return false end
    end
    return true
end

local function NormalizeDB(db)
    if type(db) ~= "table" then return DEFAULTS end
    -- Existing settings used Shift to pause; a fresh, empty config uses no key control.
    if db.modifierMode == nil and next(db) ~= nil then db.modifierMode = "pause" end
    FillMissing(db, DEFAULTS)
    if db.modifierMode ~= "pause" and db.modifierMode ~= "hold" then db.modifierMode = "none" end
    if not MODIFIER_CHECKERS[db.modifierKey] then db.modifierKey = "SHIFT" end
    if type(db.dialogueVersions) ~= "table" then db.dialogueVersions = {} end
    -- Old unscoped rules were authored exclusively for Mainline.
    if type(db.presetStates) == "table" or type(db.customOptions) == "table" then
        local old = db.dialogueVersions.mainline
        if type(old) ~= "table" then old = {}; db.dialogueVersions.mainline = old end
        if type(old.presetStates) ~= "table" then old.presetStates = db.presetStates end
        if type(old.customOptions) ~= "table" then old.customOptions = db.customOptions end
        db.presetStates, db.customOptions = nil, nil
    end
    local dialogue = db.dialogueVersions[CLIENT]
    if type(dialogue) ~= "table" then dialogue = {}; db.dialogueVersions[CLIENT] = dialogue end
    FillMissing(dialogue, { presetStates = DEFAULT_PRESET_STATES, customOptions = {} })
    db.autoAccept = db.autoAccept == true
    db.autoTurnIn = db.autoTurnIn == true
    db.pauseMulti = db.pauseMulti == true
    db.uniqueEnabled = db.uniqueEnabled == true
    db.approvedEnabled = db.approvedEnabled == true
    db.showOptionIDs = db.showOptionIDs == true

    if type(dialogue.presetStates) ~= "table" then dialogue.presetStates = CopyDefault(DEFAULT_PRESET_STATES) end
    for _, preset in ipairs(PRESETS) do
        dialogue.presetStates[preset.key] = dialogue.presetStates[preset.key] == true
    end

    local normalized = {}
    local count = 0
    if type(dialogue.customOptions) == "table" then
        for rawID, entry in pairs(dialogue.customOptions) do
            local optionID = NormalizeID(rawID)
            if optionID and not PRESET_BY_ID[optionID] and not normalized[optionID]
                and type(entry) == "table"
                and count < MAX_CUSTOM_OPTIONS then
                local name = Trim(entry.name)
                if not IsCustomNameValid(name) then name = tostring(optionID) end
                normalized[optionID] = { name = name, enabled = entry.enabled ~= false }
                count = count + 1
            end
        end
    end
    dialogue.customOptions = normalized
    return db
end

local function GetDB()
    local db = Components:EnsureConfig(CONFIG_KEY, EMPTY_DEFAULTS, PRODUCT_ID)
    return NormalizeDB(db)
end

local function InvalidateApprovedSet()
    runtime.approvedSet = nil
end

local function GetApprovedSet()
    if runtime.approvedSet then return runtime.approvedSet end
    local db = runtime.db or GetDB()
    local approved = {}
    for _, preset in ipairs(PRESETS) do
        if db.dialogueVersions[CLIENT].presetStates[preset.key] == true then
            for _, optionID in ipairs(preset.ids) do approved[optionID] = true end
        end
    end
    for optionID, entry in pairs(db.dialogueVersions[CLIENT].customOptions) do
        if entry.enabled ~= false then approved[optionID] = true end
    end
    runtime.approvedSet = approved
    return approved
end

local function ClearInteractionState()
    ClearTable(runtime.selectedSignatures)
    runtime.selectedPageCount = 0
    ClearTable(runtime.questAttempts)
    runtime.questActionCount = 0
    runtime.questTransition = false
    runtime.npcGUID = nil
    runtime.interactionOpen = false
    runtime.interactionPaused = false
end

local function InvalidatePendingSelection()
    runtime.selectionGeneration = runtime.selectionGeneration + 1
    runtime.selectionPending = false
end

local function IsAutomationAllowed(db)
    if db.modifierMode == "none" then return true end
    if db.modifierMode == "pause" and runtime.interactionPaused then return false end
    local name = MODIFIER_CHECKERS[db.modifierKey]
    local checker = name and ((KeyAPI and KeyAPI[name]) or _G[name])
    if type(checker) ~= "function" then return false end
    local ok, down = pcall(checker)
    if not ok or (Security and Security.IsSecretValue and Security.IsSecretValue(down))
        or type(down) ~= "boolean" then return false end
    if db.modifierMode == "hold" then return down end
    if down then runtime.interactionPaused = true end
    return not down
end

local function ReadCurrentOptions()
    if not Gossip then return nil end
    local options = Gossip.GetOptions()
    if type(options) ~= "table" or #options == 0 or #options > MAX_OPTIONS then return nil end

    for index, option in ipairs(options) do
        local reuse = runtime.records[index] or {}
        local record = Gossip.ReadOption(option, index, reuse)
        if not record then return nil end
        runtime.records[index] = record
    end
    for index = #options + 1, #runtime.records do runtime.records[index] = nil end
    return runtime.records, #options
end

local function BuildPageSignature(records, count)
    local parts = runtime.signatureParts
    ClearTable(parts)
    local text = Gossip.GetText() or ""
    parts[1] = tostring(#text) .. ":" .. text
    for index = 1, count do
        local record = records[index]
        local name = record.name or ""
        parts[index + 1] = table.concat({
            tostring(record.orderIndex),
            tostring(record.optionID or 0),
            tostring(record.status),
            tostring(record.flags),
            tostring(#name) .. ":" .. name,
        }, ":")
    end
    return table.concat(parts, "\031")
end

local function IsAvailableForAutomation(record)
    return Gossip.IsOptionAvailable(record) and record.selectOptionWhenOnlyOption ~= true
end

local function IsSafeUniqueOption(record)
    if not IsAvailableForAutomation(record) or record.hasRewards or record.spellID then return false end
    local movieFlag = _G.Enum and _G.Enum.GossipOptionRecFlags
        and _G.Enum.GossipOptionRecFlags.PlayMovieLabelPrepend
    return not movieFlag or not Gossip.HasOptionFlag(record, movieFlag)
end

local function ResolveCandidate(records, count, db)
    if db.approvedEnabled then
        local approved = GetApprovedSet()
        local match
        for index = 1, count do
            local record = records[index]
            if record.optionID and approved[record.optionID] then
                if match then return nil end
                match = record
            end
        end
        if match then return match, "approved" end
    end

    if count == 1 and db.uniqueEnabled and IsSafeUniqueOption(records[1]) then
        return records[1], "unique"
    end
    return nil
end

local function TryQuestAction(db)
    if not Quest or not runtime.page or not (db.autoAccept or db.autoTurnIn) then return false end
    if not Quest.CanAct() or Quest.GetNPCGUID() ~= runtime.npcGUID then return true end
    local page = runtime.page
    local greeting = page == "QUEST_GREETING"
    local listPage = greeting or page == "GOSSIP_SHOW"
    if runtime.questActionCount >= MAX_SELECTED_PAGES then return true end
    if listPage then
        -- Read fresh lists after every server event; never retain stale list indices.
        if not runtime.npcGUID then return true end
        local active = Quest.GetList(greeting, true)
        local available = Quest.GetList(greeting, false)
        if not active or not available then return true end
        local candidate, isActive
        if db.autoTurnIn then
            for _, record in ipairs(active) do
                if record.complete then candidate, isActive = record, true; break end
            end
        end
        if not candidate and db.autoAccept and #available > 0 then
            if db.pauseMulti and #available > 1 then return true end
            candidate, isActive = available[1], false
        end
        if not candidate then return false end
        -- Include the current list in legacy page identity: indices are not quest IDs.
        local signature = page .. ":" .. tostring(isActive) .. ":" .. candidate.id
        if greeting then
            signature = signature .. ":" .. #active .. ":" .. #available
        end
        if runtime.questAttempts[signature] then return true end
        runtime.questAttempts[signature] = true
        runtime.questActionCount = runtime.questActionCount + 1
        runtime.questTransition = page
        if not Quest.Select(greeting, isActive, candidate.id) then runtime.questTransition = false end
        return true
    end
    local action
    if page == "QUEST_DETAIL" and db.autoAccept then action = Quest.Accept
    elseif page == "QUEST_PROGRESS" and db.autoTurnIn then action = Quest.Progress
    elseif page == "QUEST_COMPLETE" and db.autoTurnIn then action = Quest.Reward end
    if not action then return true end
    local questID = Quest.GetID()
    if not questID or questID == 0 then return true end
    local signature = page .. ":" .. questID
    if runtime.questAttempts[signature] then return true end
    runtime.questAttempts[signature] = true
    runtime.questActionCount = runtime.questActionCount + 1
    runtime.questTransition = page
    if not action() then runtime.questTransition = false end
    return true
end

local function TrySelect()
    if not runtime.active or not runtime.page or runtime.selectedPageCount >= MAX_SELECTED_PAGES then return end
    local db = runtime.db or GetDB()
    if not IsAutomationAllowed(db) then return end
    if Quest and Quest.GetNPCGUID() ~= runtime.npcGUID then return end
    if TryQuestAction(db) then return end
    if not DIALOGUE_SUPPORTED or runtime.page ~= "GOSSIP_SHOW" then return end
    if not db.uniqueEnabled and not db.approvedEnabled then return end

    local records, count = ReadCurrentOptions()
    if not records then return end
    local signature = BuildPageSignature(records, count)
    if runtime.selectedSignatures[signature] then return end
    local candidate = ResolveCandidate(records, count, db)
    if not candidate then return end

    runtime.selectedSignatures[signature] = true
    runtime.selectedPageCount = runtime.selectedPageCount + 1
    local selected = false
    if candidate.optionID and type(Gossip.SelectOptionByID) == "function" then
        selected = Gossip.SelectOptionByID(candidate.optionID)
    else
        selected = Gossip.SelectOptionByIndex(candidate.orderIndex)
    end
    if not selected then
        if runtime.selectedSignatures[signature] then
            runtime.selectedSignatures[signature] = nil
            runtime.selectedPageCount = math.max(0, runtime.selectedPageCount - 1)
        end
    else
        PrintSelectionAttempt(candidate.name)
    end
end

local function QueueSelection()
    if not runtime.active then return end
    -- Capture a held pause key at the page event, before the delayed action can run.
    if runtime.db and runtime.db.modifierMode == "pause" and not IsAutomationAllowed(runtime.db) then
        InvalidatePendingSelection()
        return
    end
    if runtime.selectionPending then return end
    local timerAPI = _G.C_Timer
    if not (timerAPI and type(timerAPI.After) == "function") then return end

    runtime.selectionPending = true
    local generation = runtime.selectionGeneration
    timerAPI.After(SELECTION_DELAY_SECONDS, function()
        if generation ~= runtime.selectionGeneration then return end
        runtime.selectionPending = false
        if runtime.active then TrySelect() end
    end)
end

local function OnModifierChanged(_, key)
    local db = runtime.db
    if not runtime.active or not db or db.modifierMode == "none" then return end
    local modifier = db.modifierKey
    if key ~= modifier and key ~= "L" .. modifier and key ~= "R" .. modifier then return end
    if db.modifierMode == "pause" then
        if runtime.interactionOpen and not IsAutomationAllowed(db) then InvalidatePendingSelection() end
        return
    end
    if not runtime.page then return end
    if IsAutomationAllowed(db) then QueueSelection() else InvalidatePendingSelection() end
end

local function SyncModifierListener()
    local db = runtime.db
    -- Only keep a gap listener when our quest action is awaiting another task page.
    local awaitingQuestPage = runtime.questTransition == "GOSSIP_SHOW"
        or runtime.questTransition == "QUEST_GREETING" or runtime.questTransition == "QUEST_PROGRESS"
    local listen = runtime.active and db and (
        (db.modifierMode == "pause" and runtime.interactionOpen and (runtime.page ~= nil or awaitingQuestPage))
        or (db.modifierMode == "hold" and runtime.page ~= nil)
    )
    if listen and not runtime.modifierListening then
        Event:On("MODIFIER_STATE_CHANGED", OnModifierChanged, modifierOwner, {
            moduleId = "component:" .. FEATURE_KEY, traceName = "AutoGossip:modifier",
        })
        runtime.modifierListening = true
    elseif not listen and runtime.modifierListening then
        Event:OffOwner(modifierOwner)
        runtime.modifierListening = false
    end
end

local function HideOptionIDLabel()
    if runtime.optionIDLabel then runtime.optionIDLabel:Hide() end
end

local function GetOptionIDAnchor(gossipFrame)
    local panel = gossipFrame and gossipFrame.GreetingPanel
    return panel and panel.ScrollBox or panel or gossipFrame
end

local function EnsureOptionIDLabel()
    if runtime.optionIDLabel then return runtime.optionIDLabel end
    local gossipFrame = _G.GossipFrame
    if not (gossipFrame and type(gossipFrame.CreateFontString) == "function") then return nil end
    local label = gossipFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetTextColor(0.70, 0.78, 0.82, 1)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    runtime.optionIDLabel = label
    return label
end

local function UpdateOptionIDLabel()
    local db = runtime.db or GetDB()
    if not DIALOGUE_SUPPORTED or not runtime.active or not db.showOptionIDs then HideOptionIDLabel(); return end
    local gossipFrame = _G.GossipFrame
    local label = EnsureOptionIDLabel()
    if not gossipFrame or not label then return end
    local records, count = ReadCurrentOptions()
    if not records then HideOptionIDLabel(); return end

    local parts = runtime.idParts
    ClearTable(parts)
    for index = 1, count do
        local record = records[index]
        if record.optionID then
            parts[#parts + 1] = tostring(record.orderIndex) .. ":" .. tostring(record.optionID)
        end
    end
    if #parts == 0 then HideOptionIDLabel(); return end

    local anchor = GetOptionIDAnchor(gossipFrame)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    label:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
    label:SetText(T("gossip.id_prefix", "对话 ID：") .. table.concat(parts, "  "))
    label:Show()
end

local function OnGossipEvent(event, interactionIsContinuing)
    if event == "GOSSIP_CLOSED" then
        InvalidatePendingSelection()
        runtime.page = nil
        HideOptionIDLabel()
        if interactionIsContinuing ~= true then ClearInteractionState() end
        SyncModifierListener()
        return
    end
    if runtime.page ~= "GOSSIP_SHOW" then InvalidatePendingSelection() end
    local npcGUID = Quest and Quest.GetNPCGUID()
    if npcGUID and runtime.npcGUID and npcGUID ~= runtime.npcGUID then ClearInteractionState() end
    runtime.npcGUID = npcGUID or (runtime.db.modifierMode == "pause" and runtime.npcGUID) or nil
    runtime.interactionOpen = true
    runtime.questTransition = false
    runtime.page = "GOSSIP_SHOW"
    SyncModifierListener()
    UpdateOptionIDLabel()
    QueueSelection()
end

local function OnQuestEvent(event)
    InvalidatePendingSelection()
    HideOptionIDLabel()
    if event == "QUEST_FINISHED" then
        if not runtime.questTransition then
            ClearInteractionState()
        elseif runtime.questTransition == "QUEST_DETAIL" or runtime.questTransition == "QUEST_COMPLETE" then
            -- Accept/reward finish the interaction; list/progress actions still await the next page.
            runtime.interactionOpen = false
            runtime.interactionPaused = false
        end
        runtime.page = nil
        SyncModifierListener()
        return
    end
    local npcGUID = Quest and Quest.GetNPCGUID()
    local pauseMode = runtime.db.modifierMode == "pause"
    -- Missing identity during a page transition must not start a new pause interaction.
    if npcGUID ~= runtime.npcGUID and (not pauseMode or (npcGUID and runtime.npcGUID)) then ClearInteractionState() end
    runtime.npcGUID = npcGUID or (pauseMode and runtime.npcGUID) or nil
    runtime.interactionOpen = true
    runtime.questTransition = false
    runtime.page = event
    SyncModifierListener()
    QueueSelection()
end

local function AttachRuntime()
    if runtime.active then return end
    runtime.active = true
    if Quest then
        for _, event in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED" }) do
            Event:On(event, OnQuestEvent, runtimeOwner, {
                moduleId = "component:" .. FEATURE_KEY, traceName = "AutoGossip:" .. event,
            })
        end
    end
    Event:On("GOSSIP_SHOW", OnGossipEvent, runtimeOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "AutoGossip:show",
    })
    if DIALOGUE_SUPPORTED then Event:On("GOSSIP_OPTIONS_REFRESHED", OnGossipEvent, runtimeOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "AutoGossip:options-refreshed",
    }) end
    Event:On("GOSSIP_CLOSED", OnGossipEvent, runtimeOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "AutoGossip:closed",
    })
end

local function DetachRuntime()
    if runtime.active then Event:OffOwner(runtimeOwner) end
    runtime.active = false
    InvalidatePendingSelection()
    runtime.db = nil
    runtime.page = nil
    SyncModifierListener()
    InvalidateApprovedSet()
    ClearInteractionState()
    HideOptionIDLabel()
end

local function RefreshRuntime()
    InvalidatePendingSelection()
    runtime.db = GetDB()
    runtime.page = nil
    InvalidateApprovedSet()
    ClearInteractionState()
    SyncModifierListener()
    if featureEnabled then AttachRuntime() else DetachRuntime() end
    if Event.Emit then Event:Emit("YUI_QUEST_AUTOMATION_CHANGED") end
end

local function RefreshFeatureSettings(feature)
    if feature and feature.RefreshCurrentModule then feature:RefreshCurrentModule() end
end

local function RefreshModifierSettings(feature)
    runtime.db = GetDB()
    runtime.interactionPaused = false
    InvalidatePendingSelection()
    SyncModifierListener()
    if runtime.page then QueueSelection() end
    RefreshFeatureSettings(feature)
end

local function CountCustomOptions(db)
    local count = 0
    for _ in pairs(db.dialogueVersions[CLIENT].customOptions) do count = count + 1 end
    return count
end

local function AddCustomOption(optionID, name)
    local db = GetDB()
    optionID = NormalizeID(optionID)
    if not optionID then return false, "invalid_id" end
    name = Trim(name)
    if name == "" then return false, "missing_name" end
    if not IsCustomNameValid(name) then return false, "name_too_long" end
    if PRESET_BY_ID[optionID] or db.dialogueVersions[CLIENT].customOptions[optionID] then return false, "duplicate" end
    if CountCustomOptions(db) >= MAX_CUSTOM_OPTIONS then return false, "limit" end
    db.dialogueVersions[CLIENT].customOptions[optionID] = { name = name, enabled = true }
    runtime.db = db
    InvalidateApprovedSet()
    return true
end

local function RemoveCustomOption(optionID)
    local db = GetDB()
    if not db.dialogueVersions[CLIENT].customOptions[optionID] then return false end
    db.dialogueVersions[CLIENT].customOptions[optionID] = nil
    runtime.db = db
    InvalidateApprovedSet()
    return true
end

local function Notify(key, fallback)
    if type(YUI.Print) == "function" then YUI:Print(T(key, fallback)) end
end

local function GetSortedCustomOptions(db)
    local items = {}
    for optionID, entry in pairs(db.dialogueVersions[CLIENT].customOptions) do
        items[#items + 1] = { optionID = optionID, entry = entry }
    end
    table.sort(items, function(left, right) return left.optionID < right.optionID end)
    return items
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    if DIALOGUE_SUPPORTED then
        rows[#rows + 1] = { label = T("settings.unique", "自动选择唯一对话"), enabled = db.uniqueEnabled == true }
    end
    rows[#rows + 1] = { label = T("settings.auto_accept", "自动接任务"), enabled = db.autoAccept == true }
    rows[#rows + 1] = { label = T("settings.auto_turn_in", "自动交任务"), enabled = db.autoTurnIn == true }
    local version = db.dialogueVersions and db.dialogueVersions[CLIENT]
    if DIALOGUE_SUPPORTED and (#PRESETS > 0 or (version and type(version.customOptions) == "table" and next(version.customOptions))) then
        rows[#rows + 1] = { label = T("settings.approved", "自动选择指定对话"), enabled = db.approvedEnabled == true }
    end
    return rows
end

local function GetOptions(feature)
    local options = {
        { type = "divider", label = T("settings.quests", "任务"), width = 620, alignLeft = true },
        {
            type = "row", gap = 24,
            children = {
                {
                    type = "checkbox", text = T("settings.auto_accept", "自动接任务"), width = 260,
                    get = function() return GetDB().autoAccept end,
                    set = function(value)
                        GetDB().autoAccept = value == true
                        RefreshRuntime()
                        RefreshFeatureSettings(feature)
                    end,
                },
                {
                    type = "checkbox", text = T("settings.auto_turn_in", "自动交任务"), width = 260,
                    get = function() return GetDB().autoTurnIn end,
                    set = function(value) GetDB().autoTurnIn = value == true; RefreshRuntime() end,
                },
            },
        },
        {
            type = "checkbox", text = T("settings.pause_multi", "多个可接任务时手动选择"), width = 580,
            tooltip = T("settings.pause_multi.tooltip", "NPC 有多个可接任务时，由你选择；选定后自动接取。"),
            hidden = function() return not GetDB().autoAccept end,
            get = function() return GetDB().pauseMulti end,
            set = function(value) GetDB().pauseMulti = value == true; RefreshRuntime() end,
        },
        { type = "text", label = T("settings.quest_rules"), width = 620, justify = "LEFT", tone = "muted" },
        {
            type = "divider", label = T("settings.dialogue_rules", "对话"), width = 620, alignLeft = true,
            hidden = function() return not DIALOGUE_SUPPORTED end,
        },
        {
            type = "checkbox",
            hidden = function() return not DIALOGUE_SUPPORTED end,
            text = T("settings.unique", "自动选择唯一对话"),
            tooltip = T("settings.unique.tooltip", "只有一个安全可用的普通对话选项时自动选择；不处理任务、确认或输入。"),
            width = 360,
            get = function() return GetDB().uniqueEnabled end,
            set = function(value) GetDB().uniqueEnabled = value == true end,
        },
        {
            type = "checkbox",
            hidden = function() return not DIALOGUE_SUPPORTED or (#PRESETS == 0 and CountCustomOptions(GetDB()) == 0) end,
            text = T("settings.approved", "自动选择指定对话"),
            tooltip = T("settings.approved.tooltip", "按下方启用的规则自动选择对话；同时匹配多条时由你选择。"),
            width = 360,
            get = function() return GetDB().approvedEnabled end,
            set = function(value)
                GetDB().approvedEnabled = value == true
                RefreshFeatureSettings(feature)
            end,
        },
        {
            type = "divider",
            label = T("settings.presets", "内置规则"),
            collapsible = true,
            collapsed = true,
            collapseKey = "AutoGossip:presets",
            width = 620,
            alignLeft = true,
            hidden = function() return not DIALOGUE_SUPPORTED or #PRESETS == 0 or not GetDB().approvedEnabled end,
        },
    }

    for _, preset in ipairs(PRESETS) do
        local presetRef = preset
        local ids = table.concat(presetRef.ids, ", ")
        options[#options + 1] = {
            type = "checkbox",
            text = T(presetRef.nameKey, presetRef.key),
            tooltip = T("gossip.id_prefix", "对话 ID：") .. ids,
            width = 420,
            hidden = function() return not DIALOGUE_SUPPORTED or not GetDB().approvedEnabled end,
            get = function() return GetDB().dialogueVersions[CLIENT].presetStates[presetRef.key] == true end,
            set = function(value)
                GetDB().dialogueVersions[CLIENT].presetStates[presetRef.key] = value == true
                InvalidateApprovedSet()
            end,
        }
    end

    local customItems = GetSortedCustomOptions(GetDB())
    if #customItems > 0 then
        options[#options + 1] = {
            type = "divider",
            label = T("settings.custom", "我的规则"),
            width = 620,
            alignLeft = true,
            hidden = function() return not DIALOGUE_SUPPORTED or not GetDB().approvedEnabled end,
        }
        for _, item in ipairs(customItems) do
            local optionID = item.optionID
            options[#options + 1] = {
                type = "row",
                gap = 12,
                hidden = function() return not DIALOGUE_SUPPORTED or not GetDB().approvedEnabled end,
                children = {
                    {
                        type = "checkbox",
                        text = item.entry.name,
                        tooltip = T("gossip.id_prefix", "对话 ID：") .. tostring(optionID),
                        width = 420,
                        get = function()
                            local entry = GetDB().dialogueVersions[CLIENT].customOptions[optionID]
                            return entry and entry.enabled ~= false or false
                        end,
                        set = function(value)
                            local entry = GetDB().dialogueVersions[CLIENT].customOptions[optionID]
                            if entry then entry.enabled = value == true; InvalidateApprovedSet() end
                        end,
                    },
                    {
                        type = "button",
                        label = T("settings.delete", "删除"),
                        width = 72,
                        onClick = function()
                            if RemoveCustomOption(optionID) then
                                Notify("message.removed", "已删除自定义对话。")
                                RefreshFeatureSettings(feature)
                            end
                        end,
                    },
                },
            }
        end
    end

    options[#options + 1] = {
        type = "divider", label = T("settings.extra", "额外选项"), width = 620, alignLeft = true,
    }
    options[#options + 1] = {
        type = "row", gap = 24,
        children = {
            {
                type = "dropdown", label = T("settings.modifier_mode", "按键控制"), width = 260,
                tooltip = T("settings.modifier_mode.tooltip", "仅控制已开启的自动对话和任务交接功能。"),
                options = {
                    { text = T("modifier.none", "不使用"), value = "none" },
                    { text = T("modifier.pause", "按住暂停"), value = "pause" },
                    { text = T("modifier.hold", "按住启用"), value = "hold" },
                },
                get = function() return GetDB().modifierMode end,
                set = function(value) GetDB().modifierMode = value; RefreshModifierSettings(feature) end,
            },
            {
                type = "dropdown", label = T("settings.modifier_key", "控制按键"), width = 260,
                hidden = function() return GetDB().modifierMode == "none" end,
                options = {
                    { text = "Shift", value = "SHIFT" },
                    { text = "Ctrl", value = "CTRL" },
                    { text = "Alt", value = "ALT" },
                },
                get = function() return GetDB().modifierKey end,
                set = function(value) GetDB().modifierKey = value; RefreshModifierSettings(feature) end,
            },
        },
    }
    local db = GetDB()
    local hint = T("modifier.none_hint", "按已勾选的功能自动处理。")
    local keyName = db.modifierKey == "CTRL" and "Ctrl" or db.modifierKey == "ALT" and "Alt" or "Shift"
    if db.modifierMode == "pause" then
        hint = string.format(T("modifier.pause_hint", "按住 %s 暂停自动对话与任务交接。"), keyName)
    elseif db.modifierMode == "hold" then
        hint = string.format(T("modifier.hold_hint", "按住 %s 才自动处理对话与任务交接。"), keyName)
    end
    options[#options + 1] = { type = "text", label = hint, width = 620, justify = "LEFT", tone = "muted" }

    options[#options + 1] = {
        type = "divider",
        label = T("settings.advanced", "添加自定义对话"),
        width = 620,
        alignLeft = true,
        hidden = function() return not DIALOGUE_SUPPORTED end,
        collapsible = true,
        collapsed = sectionCollapsed.advanced == true,
        onToggle = function(collapsed)
            sectionCollapsed.advanced = collapsed == true
            RefreshFeatureSettings(feature)
        end,
    }
    local advancedHidden = function() return not DIALOGUE_SUPPORTED or sectionCollapsed.advanced == true end
    options[#options + 1] = {
        type = "checkbox",
        text = T("settings.show_ids", "显示对话 ID"),
        tooltip = T("settings.show_ids.tooltip", "在 NPC 对话框底部显示“顺序号:Gossip ID”。"),
        width = 360,
        hidden = advancedHidden,
        get = function() return GetDB().showOptionIDs end,
        set = function(value)
            GetDB().showOptionIDs = value == true
            UpdateOptionIDLabel()
        end,
    }
    options[#options + 1] = {
        type = "row",
        gap = 10,
        hidden = advancedHidden,
        children = {
            {
                type = "editbox",
                label = T("settings.custom_name", "规则名称"),
                tooltip = T("settings.custom_name.tooltip", "用于在设置列表中识别这条规则。"),
                width = 250,
                get = function() return pendingCustomName end,
                set = function(value) pendingCustomName = value or "" end,
            },
            {
                type = "editbox",
                label = T("settings.custom_id", "Gossip ID"),
                tooltip = T("settings.custom_id.tooltip", "填写普通对话选项的 Gossip ID。"),
                width = 130,
                get = function() return pendingCustomID end,
                set = function(value) pendingCustomID = value or "" end,
            },
            {
                type = "button",
                label = T("settings.add", "添加规则"),
                width = 100,
                onClick = function()
                    local added, code = AddCustomOption(pendingCustomID, pendingCustomName)
                    if not added then
                        local messages = {
                            invalid_id = { "message.invalid_id", "请输入有效的 Gossip ID。" },
                            missing_name = { "message.missing_name", "请输入规则名称。" },
                            name_too_long = { "message.name_too_long", "规则名称过长。" },
                            duplicate = { "message.duplicate", "该 Gossip ID 已存在。" },
                            limit = { "message.limit", "自定义规则已达到上限。" },
                        }
                        local message = messages[code] or messages.invalid_id
                        Notify(message[1], message[2])
                        return
                    end
                    pendingCustomName, pendingCustomID = "", ""
                    Notify("message.added", "已添加自定义对话。")
                    RefreshFeatureSettings(feature)
                end,
            },
        },
    }

    return options
end

local function ToggleFeature(enabled)
    featureEnabled = enabled == true
    RefreshRuntime()
end

local function RegisterProfileCallbacks()
    if profileCallbacksRegistered or not (YUI.DB and type(YUI.DB.GetAceDB) == "function") then return end
    local db = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (db and type(db.RegisterCallback) == "function") then return end
    db.RegisterCallback(profileOwner, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileReset", "OnProfileChanged")
    profileCallbacksRegistered = true
end

function profileOwner:OnProfileChanged()
    pendingCustomName, pendingCustomID = "", ""
    featureEnabled = Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) or false
    RefreshRuntime()
end

Components:RegisterFeature(FEATURE_KEY, {
    name = T("feature.name", "自动对话与任务"),
    description = T("feature.description", "自动处理对话和任务交接。"),
    default = true,
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    versions = { "mainline", "mists", "wrath", "forever" },
    assetFolders = { "Components\\AutoGossip\\Media" },
    modSwitchImage = "modswitch\\autogossip-bg.png",
    modSwitchImageCrop = false,
    settingsMode = "inline",
    callback = ToggleFeature,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
    GetQuestAutomationState = function()
        local db = GetDB()
        return featureEnabled and runtime.active, db.autoAccept, db.autoTurnIn
    end,
    SetQuestAutomationEnabled = function(_, enabled)
        enabled = enabled == true
        local db = GetDB()
        db.autoAccept, db.autoTurnIn = enabled, enabled
        if enabled and not featureEnabled then
            Components:SetFeatureEnabled(FEATURE_KEY, true)
        end
        RefreshRuntime()
        return not enabled or (featureEnabled and runtime.active)
    end,
    GetStats = function()
        return {
            active = runtime.active,
            pendingSelections = runtime.selectionPending and 1 or 0,
            questActions = runtime.questActionCount,
            dialoguePages = runtime.selectedPageCount,
        }
    end,
    transfer = {
        dataPaths = { CONFIG_KEY },
        fieldWhitelists = {
            [CONFIG_KEY] = {
                uniqueEnabled = true,
                approvedEnabled = true,
                showOptionIDs = true,
                autoAccept = true,
                autoTurnIn = true,
                pauseMulti = true,
                modifierMode = true,
                modifierKey = true,
                dialogueVersions = true,
                presetStates = true, -- Legacy import migration.
                customOptions = true,
            },
        },
    },
})

if Event.Once then
    Event:Once("YUI_DB_READY", RegisterProfileCallbacks, profileOwner, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "AutoGossip:profile-callbacks",
    })
else
    RegisterProfileCallbacks()
end
