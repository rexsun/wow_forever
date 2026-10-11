local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local Tools = YUI.MythicPlusTools
if not Tools or not Tools.RegisterSubFeature then return end
local ChatInput = YUI.API and YUI.API.ChatInput

local KeystoneTools = {
    id = "keystoneTools",
    order = 20,
}

local ANNOUNCE_TRIGGER_BAG = "bag"
local ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE = "challenge_complete"
local KEYSTONE_SCAN_READY = "ready"
local KEYSTONE_SCAN_PENDING = "pending"
local KEYSTONE_SCAN_EMPTY = "empty"
local KEYSTONE_SCAN_UNAVAILABLE = "unavailable"
local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local INPUT_WIDTH = 52
local VALUE_GAP = 10
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP

local VALID_ANNOUNCE_TRIGGERS = {
    [ANNOUNCE_TRIGGER_BAG] = true,
    [ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE] = true,
}

KeystoneTools.defaults = {
    keystoneAutoInsertEnabled = true,
    keystoneAutoAnnounceEnabled = false,
    keystoneAutoAnnounceTrigger = ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE,
}

local AutoInsertEventOwner = {}
local KeystoneAnnounceEventOwner = {}
local featureActive = false
local autoInsertRuntimeActive = false
local announceRuntimeActive = false
local autoInsertToken = 0
local announceScanToken = 0
local challengeAnnouncePending = false
local announceObservationActive = false
local announceObservationStartedAt = 0
local announceObservationNotBefore = 0
local announceCandidateSignature = nil
local announceCandidateLink = nil
local announceCandidateSeenAt = 0
local pendingAnnounceSignature = nil
local announceBaselinePending = true
local lastKnownKeystoneSignature = nil
local lastAnnouncedKeystoneSignature = nil

local AUTO_INSERT_ATTEMPT_DELAYS = { 0, 0.15, 0.5, 1 }
local ANNOUNCE_SETTLE_DELAY = 1
local ANNOUNCE_CONFIRM_DELAY = 1
local ANNOUNCE_MIN_STABLE_AGE = 3
local ANNOUNCE_RETRY_DELAY = 1
local ANNOUNCE_OBSERVATION_TIMEOUT = 15

local function T(key, fallback)
    if Tools.T then
        return Tools:T(key, fallback)
    end
    return fallback or key
end

local function ScheduleAfter(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, callback)
    else
        callback()
    end
end

local function GetTimeNow()
    if GetTime then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then
            return value
        end
    end
    return 0
end

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) == true
end

local function NormalizeAnnounceTrigger(value)
    if VALID_ANNOUNCE_TRIGGERS[value] then
        return value
    end
    return ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = KeystoneTools.defaults end

    if db.keystoneAutoInsertEnabled == nil then
        db.keystoneAutoInsertEnabled = true
    else
        db.keystoneAutoInsertEnabled = db.keystoneAutoInsertEnabled == true
    end

    db.keystoneAutoAnnounceEnabled = db.keystoneAutoAnnounceEnabled == true
    db.keystoneAutoAnnounceTrigger = NormalizeAnnounceTrigger(db.keystoneAutoAnnounceTrigger)
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and Tools.GetDB then
        db = Tools:GetDB()
    end
    return NormalizeDB(db)
end

local function CancelAutoInsert()
    autoInsertToken = autoInsertToken + 1
end

local function IsAutoInsertRuntimeEnabled()
    return featureActive and autoInsertRuntimeActive and GetDB().keystoneAutoInsertEnabled == true
end

local function IsAnnounceRuntimeEnabled()
    return featureActive and announceRuntimeActive and GetDB().keystoneAutoAnnounceEnabled == true
end

local function HasCursorPayload()
    if CursorHasItem and CursorHasItem() then
        return true
    end
    if GetCursorInfo then
        return GetCursorInfo() ~= nil
    end
    return false
end

local function ClearKeystoneCursor()
    if ClearCursor and HasCursorPayload() then
        ClearCursor()
    end
end

local function HasSlottedKeystone()
    if C_ChallengeMode and C_ChallengeMode.HasSlottedKeystone then
        local ok, hasKeystone = pcall(C_ChallengeMode.HasSlottedKeystone)
        return ok and hasKeystone == true
    end
    return false
end

local function IsKeystoneFrameReady()
    local frame = _G.ChallengesKeystoneFrame
    return frame and frame.IsShown and frame:IsShown()
end

local function GetContainerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end

    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID or nil
    end

    return nil
end

local function GetContainerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end

    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and (info.hyperlink or info.itemLink) or nil
    end

    return nil
end

local function CreateBagItemLocation(bag, slot)
    if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end

    local ok, itemLocation = pcall(function()
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
    end)
    if not ok or not itemLocation then return nil end

    if itemLocation.IsValid and not itemLocation:IsValid() then
        return nil
    end
    if C_Item and C_Item.DoesItemExist then
        local existsOK, exists = pcall(C_Item.DoesItemExist, itemLocation)
        if existsOK and exists == false then
            return nil
        end
    end

    return itemLocation
end

local function CanUseKeystoneInCurrentMap(itemLocation)
    if not (C_ChallengeMode and C_ChallengeMode.CanUseKeystoneInCurrentMap and itemLocation) then
        return false
    end

    local ok, canUse = pcall(C_ChallengeMode.CanUseKeystoneInCurrentMap, itemLocation)
    return ok and canUse == true
end

local function FindUsableKeystone()
    local ItemAPI = YUI.API and YUI.API.Item
    if not (C_Container and C_Container.GetContainerNumSlots and ItemAPI and ItemAPI.IsKeystoneByID) then
        return nil
    end

    local maxBag = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, maxBag do
        local slots = tonumber(C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local itemID = GetContainerItemID(bag, slot)
            if itemID and ItemAPI.IsKeystoneByID(itemID) then
                local itemLocation = CreateBagItemLocation(bag, slot)
                if itemLocation and CanUseKeystoneInCurrentMap(itemLocation) then
                    return bag, slot
                end
            end
        end
    end

    return nil
end

local function FindPlayerKeystoneLink()
    local ItemAPI = YUI.API and YUI.API.Item
    if not (C_Container and C_Container.GetContainerNumSlots and ItemAPI and ItemAPI.IsKeystoneByID) then
        return nil, KEYSTONE_SCAN_UNAVAILABLE
    end

    local maxBag = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, maxBag do
        local slots = tonumber(C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local itemID = GetContainerItemID(bag, slot)
            if itemID and ItemAPI.IsKeystoneByID(itemID) then
                local link = GetContainerItemLink(bag, slot)
                if type(link) == "string" and not IsSecretValue(link) and link ~= "" then
                    return link, KEYSTONE_SCAN_READY
                end
                return nil, KEYSTONE_SCAN_PENDING
            end
        end
    end

    return nil, KEYSTONE_SCAN_EMPTY
end

local function IsKeystoneItemInfo(itemInfo)
    if type(itemInfo) ~= "string" or IsSecretValue(itemInfo) or itemInfo == "" then
        return false
    end
    if itemInfo:find("Hkeystone:", 1, true) then
        return true
    end

    local ItemAPI = YUI.API and YUI.API.Item
    if ItemAPI and ItemAPI.IsKeystoneByID then
        local ok, isKeystone = pcall(ItemAPI.IsKeystoneByID, itemInfo)
        return ok and isKeystone == true
    end

    if C_Item and C_Item.IsItemKeystoneByID then
        local ok, isKeystone = pcall(C_Item.IsItemKeystoneByID, itemInfo)
        return ok and isKeystone == true
    end

    return false
end

local function IsKeystoneItemChange(previousHyperlink, newHyperlink)
    return IsKeystoneItemInfo(previousHyperlink) or IsKeystoneItemInfo(newHyperlink)
end

local function SlotKeystoneFromBag(bag, slot)
    if not (C_Container and C_Container.PickupContainerItem and C_ChallengeMode and C_ChallengeMode.SlotKeystone) then
        return false
    end
    if HasCursorPayload() then
        return false
    end

    local pickupOK = pcall(C_Container.PickupContainerItem, bag, slot)
    if not pickupOK or not (CursorHasItem and CursorHasItem()) then
        ClearKeystoneCursor()
        return false
    end

    local slotOK = pcall(C_ChallengeMode.SlotKeystone)
    if slotOK and HasSlottedKeystone() then
        return true
    end

    ClearKeystoneCursor()
    return false
end

local function TryAutoSlot(token, attempt)
    if token ~= autoInsertToken then return end
    if not IsAutoInsertRuntimeEnabled() then return end

    if HasSlottedKeystone() then
        CancelAutoInsert()
        return
    end

    if not IsKeystoneFrameReady() then
        local nextDelay = AUTO_INSERT_ATTEMPT_DELAYS[attempt + 1]
        if nextDelay then
            ScheduleAfter(nextDelay, function()
                TryAutoSlot(token, attempt + 1)
            end)
        end
        return
    end

    local bag, slot = FindUsableKeystone()
    if bag and slot and SlotKeystoneFromBag(bag, slot) then
        CancelAutoInsert()
        return
    end

    local nextDelay = AUTO_INSERT_ATTEMPT_DELAYS[attempt + 1]
    if nextDelay then
        ScheduleAfter(nextDelay, function()
            TryAutoSlot(token, attempt + 1)
        end)
    end
end

local function ScheduleAutoSlot()
    if not IsAutoInsertRuntimeEnabled() then return end

    CancelAutoInsert()
    local token = autoInsertToken
    ScheduleAfter(AUTO_INSERT_ATTEMPT_DELAYS[1], function()
        TryAutoSlot(token, 1)
    end)
end

local function OnAutoInsertEvent(event)
    if event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
        ScheduleAutoSlot()
    elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
        CancelAutoInsert()
    end
end

local function BindAutoInsertEvents()
    if not (YUI.Event and YUI.Event.On) then return false end

    if YUI.Event.OffOwner then
        YUI.Event:OffOwner(AutoInsertEventOwner)
    end
    YUI.Event:On("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN", OnAutoInsertEvent, AutoInsertEventOwner)
    YUI.Event:On("CHALLENGE_MODE_KEYSTONE_SLOTTED", OnAutoInsertEvent, AutoInsertEventOwner)
    return true
end

local function EnableAutoInsertRuntime()
    if autoInsertRuntimeActive then return end
    if not BindAutoInsertEvents() then return end

    autoInsertRuntimeActive = true
end

local function DisableAutoInsertRuntime()
    autoInsertRuntimeActive = false
    CancelAutoInsert()

    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(AutoInsertEventOwner)
    end
end

local function ParseKeystoneLink(link)
    if type(link) ~= "string" or IsSecretValue(link) or link == "" then return nil, nil end

    local mapID, level = link:match("|Hkeystone:[^:]+:(%d+):(%d+)")
    mapID = tonumber(mapID)
    level = tonumber(level)
    if not mapID or mapID <= 0 or not level or level <= 0 then return nil, nil end
    return math.floor(mapID), math.floor(level)
end

local function GetKeystoneSignature(mapID, level)
    mapID = tonumber(mapID)
    level = tonumber(level)
    if not mapID or mapID <= 0 or not level or level <= 0 then return nil end
    return string.format("%d:%d", math.floor(mapID), math.floor(level))
end

local function ReadPlayerKeystoneCandidate()
    local link, scanState = FindPlayerKeystoneLink()
    if scanState ~= KEYSTONE_SCAN_READY then
        return nil, nil, scanState
    end

    local linkMapID, linkLevel = ParseKeystoneLink(link)
    if not linkMapID or not linkLevel then
        return nil, nil, KEYSTONE_SCAN_PENDING
    end

    local KeystoneAPI = YUI.API and YUI.API.Keystone
    if not (KeystoneAPI and type(KeystoneAPI.GetPlayerKeystone) == "function") then
        return nil, nil, KEYSTONE_SCAN_UNAVAILABLE
    end

    local ok, data = pcall(KeystoneAPI.GetPlayerKeystone)
    if not ok or type(data) ~= "table" or IsSecretValue(data) then
        return nil, nil, KEYSTONE_SCAN_UNAVAILABLE
    end

    local mapID = tonumber(data.mapID)
    local level = tonumber(data.level)
    if not mapID or mapID <= 0 or not level or level <= 0 then
        return nil, nil, KEYSTONE_SCAN_PENDING
    end
    mapID = math.floor(mapID)
    level = math.floor(level)
    if mapID ~= linkMapID or level ~= linkLevel then
        return nil, nil, KEYSTONE_SCAN_PENDING
    end

    return GetKeystoneSignature(mapID, level), link, KEYSTONE_SCAN_READY
end

local function PrimeAnnounceKeystone(allowEmpty)
    local signature, _, scanState = ReadPlayerKeystoneCandidate()
    if scanState == KEYSTONE_SCAN_READY then
        lastKnownKeystoneSignature = signature
        return true
    end
    if allowEmpty and scanState == KEYSTONE_SCAN_EMPTY then
        lastKnownKeystoneSignature = nil
        return true
    end
    return false
end

local function IsWorldReady()
    local lifecycle = YUI.Lifecycle
    if not (lifecycle and type(lifecycle.IsReady) == "function") then
        return false
    end

    local ok, ready = pcall(lifecycle.IsReady, lifecycle, "YUI_WORLD_READY")
    return ok and ready == true
end

local function ConsumeInitialAnnounceBaseline(event)
    if not announceBaselinePending then return false end
    if event ~= "BAG_UPDATE" and event ~= "BAG_UPDATE_DELAYED"
        and event ~= "ITEM_CHANGED" and event ~= "ITEM_PUSH"
    then
        return false
    end

    if PrimeAnnounceKeystone(event == "BAG_UPDATE_DELAYED") then
        announceBaselinePending = false
    end
    return true
end

local function ReadRestrictionFlag(func, ...)
    if type(func) ~= "function" then return false end

    local ok, value = pcall(func, ...)
    if not ok or type(value) ~= "boolean" then
        return true
    end
    return value
end

local function IsAnnounceRestricted()
    if C_ChatInfo and ReadRestrictionFlag(C_ChatInfo.InChatMessagingLockdown) then
        return true
    end

    local restrictionType = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
    if restrictionType ~= nil and C_RestrictedActions
        and ReadRestrictionFlag(C_RestrictedActions.IsAddOnRestrictionActive, restrictionType)
    then
        return true
    end

    local weeklyRewardsType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.WeeklyRewards
    if weeklyRewardsType ~= nil and C_PlayerInteractionManager
        and ReadRestrictionFlag(C_PlayerInteractionManager.IsInteractingWithNpcOfType, weeklyRewardsType)
    then
        return true
    end

    return false
end

local function GetAnnounceChannel()
    if not (C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function") then return nil end
    local resolver = ChatInput and ChatInput.ResolveGroupChatType
    if type(resolver) ~= "function" then return nil end
    local chatType = resolver()
    return chatType ~= "RAID" and chatType or nil
end

local function AnnounceKeystoneLink(link)
    local channel = GetAnnounceChannel()
    if not channel or not link then
        return false, false
    end
    if IsAnnounceRestricted() then
        return false, true
    end

    local template = T("keystone.announce.new_keystone", "我的新钥石是: %s")
    local ok, message = pcall(string.format, template, link)
    if not ok or type(message) ~= "string" or message == "" then
        message = "我的新钥石是: " .. tostring(link)
    end

    local sentOK = pcall(C_ChatInfo.SendChatMessage, message, channel)
    return sentOK == true, false
end

local function ResetAnnounceCandidate()
    announceCandidateSignature = nil
    announceCandidateLink = nil
    announceCandidateSeenAt = 0
end

local function StopAnnounceObservation(clearPending)
    announceScanToken = announceScanToken + 1
    announceObservationActive = false
    announceObservationStartedAt = 0
    announceObservationNotBefore = 0
    ResetAnnounceCandidate()
    if clearPending then
        challengeAnnouncePending = false
        pendingAnnounceSignature = nil
    end
end

local RunAnnounceScan

local function ScheduleAnnounceScan(delay)
    if not IsAnnounceRuntimeEnabled() or not announceObservationActive then return end

    announceScanToken = announceScanToken + 1
    local token = announceScanToken
    ScheduleAfter(delay or ANNOUNCE_RETRY_DELAY, function()
        RunAnnounceScan(token)
    end)
end

local function BeginAnnounceObservation(isChallenge)
    if not IsAnnounceRuntimeEnabled() then return false end

    local now = GetTimeNow()
    if not announceObservationActive then
        announceObservationActive = true
        announceObservationStartedAt = now
    end
    if isChallenge then
        challengeAnnouncePending = true
    end

    announceObservationNotBefore = now + ANNOUNCE_MIN_STABLE_AGE
    ResetAnnounceCandidate()
    ScheduleAnnounceScan(ANNOUNCE_SETTLE_DELAY)
    return true
end

local function CommitStableAnnounceCandidate(signature, link)
    lastKnownKeystoneSignature = signature
    if signature == lastAnnouncedKeystoneSignature then
        StopAnnounceObservation(true)
        return true
    end

    local sent, deferred = AnnounceKeystoneLink(link)
    if sent then
        lastAnnouncedKeystoneSignature = signature
        StopAnnounceObservation(true)
        return true
    end
    if deferred then
        pendingAnnounceSignature = signature
        StopAnnounceObservation(false)
        return false
    end

    StopAnnounceObservation(true)
    return false
end

RunAnnounceScan = function(token)
    if token ~= announceScanToken then return end
    if not IsAnnounceRuntimeEnabled() or not announceObservationActive then return end

    local now = GetTimeNow()
    if now - announceObservationStartedAt >= ANNOUNCE_OBSERVATION_TIMEOUT then
        StopAnnounceObservation(true)
        return
    end

    local signature, link, scanState = ReadPlayerKeystoneCandidate()
    if scanState ~= KEYSTONE_SCAN_READY then
        ResetAnnounceCandidate()
        if scanState == KEYSTONE_SCAN_EMPTY and not challengeAnnouncePending and not pendingAnnounceSignature then
            StopAnnounceObservation(true)
        else
            ScheduleAnnounceScan(ANNOUNCE_RETRY_DELAY)
        end
        return
    end

    if signature == lastAnnouncedKeystoneSignature then
        lastKnownKeystoneSignature = signature
        StopAnnounceObservation(true)
        return
    end

    local isPendingSignature = pendingAnnounceSignature ~= nil and signature == pendingAnnounceSignature
    if signature == lastKnownKeystoneSignature and not isPendingSignature then
        ResetAnnounceCandidate()
        if challengeAnnouncePending then
            ScheduleAnnounceScan(ANNOUNCE_RETRY_DELAY)
        else
            StopAnnounceObservation(true)
        end
        return
    end

    if signature ~= announceCandidateSignature then
        announceCandidateSignature = signature
        announceCandidateLink = link
        announceCandidateSeenAt = now
        local delay = math.max(ANNOUNCE_CONFIRM_DELAY, announceObservationNotBefore - now)
        ScheduleAnnounceScan(delay)
        return
    end

    announceCandidateLink = link
    local confirmDelay = ANNOUNCE_CONFIRM_DELAY - (now - announceCandidateSeenAt)
    local stableDelay = announceObservationNotBefore - now
    if confirmDelay > 0 or stableDelay > 0 then
        ScheduleAnnounceScan(math.max(ANNOUNCE_RETRY_DELAY, confirmDelay, stableDelay))
        return
    end

    CommitStableAnnounceCandidate(signature, announceCandidateLink)
end

local function ResumePendingAnnounce()
    if not pendingAnnounceSignature then return false end
    if not IsAnnounceRuntimeEnabled() then
        StopAnnounceObservation(true)
        return false
    end
    return BeginAnnounceObservation(false)
end

local function OnAnnounceEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        StopAnnounceObservation(true)
        if announceBaselinePending and PrimeAnnounceKeystone(false) then
            announceBaselinePending = false
        end
        return
    end

    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local _, state = ...
        local inactiveState = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive
        if inactiveState ~= nil and state == inactiveState then
            ResumePendingAnnounce()
        end
        return
    end

    if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        local weeklyRewardsType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.WeeklyRewards
        if weeklyRewardsType ~= nil and interactionType == weeklyRewardsType then
            ResumePendingAnnounce()
        end
        return
    end

    if ConsumeInitialAnnounceBaseline(event) then
        return
    end

    local db = GetDB()
    if db.keystoneAutoAnnounceTrigger == ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE then
        if event == "CHALLENGE_MODE_COMPLETED" then
            BeginAnnounceObservation(true)
        elseif event == "CHALLENGE_MODE_COMPLETED_REWARDS"
            and (challengeAnnouncePending or pendingAnnounceSignature)
        then
            BeginAnnounceObservation(false)
        elseif (event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_PUSH")
            and (challengeAnnouncePending or pendingAnnounceSignature)
        then
            BeginAnnounceObservation(false)
        elseif event == "ITEM_CHANGED" and (challengeAnnouncePending or pendingAnnounceSignature)
            and IsKeystoneItemChange(...)
        then
            BeginAnnounceObservation(false)
        end
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_PUSH" then
        BeginAnnounceObservation(false)
    elseif event == "ITEM_CHANGED" and IsKeystoneItemChange(...) then
        BeginAnnounceObservation(false)
    end
end

local function BindAnnounceEvents()
    if not (YUI.Event and YUI.Event.On) then return false end

    if YUI.Event.OffOwner then
        YUI.Event:OffOwner(KeystoneAnnounceEventOwner)
    end
    YUI.Event:On("PLAYER_ENTERING_WORLD", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("BAG_UPDATE", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("BAG_UPDATE_DELAYED", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("ITEM_CHANGED", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("ITEM_PUSH", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("CHALLENGE_MODE_COMPLETED", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("CHALLENGE_MODE_COMPLETED_REWARDS", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("ADDON_RESTRICTION_STATE_CHANGED", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    YUI.Event:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", OnAnnounceEvent, KeystoneAnnounceEventOwner)
    return true
end

local function EnableAnnounceRuntime()
    if announceRuntimeActive then return end
    if not BindAnnounceEvents() then return end

    announceRuntimeActive = true
    StopAnnounceObservation(true)
    announceBaselinePending = true
    if PrimeAnnounceKeystone(IsWorldReady()) then
        announceBaselinePending = false
    end
end

local function DisableAnnounceRuntime()
    announceRuntimeActive = false
    StopAnnounceObservation(true)
    announceBaselinePending = true

    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(KeystoneAnnounceEventOwner)
    end
end

local function RefreshAutoInsertRuntime(db)
    if featureActive and GetDB(db).keystoneAutoInsertEnabled == true then
        EnableAutoInsertRuntime()
    else
        DisableAutoInsertRuntime()
    end
end

local function RefreshAnnounceRuntime(db)
    if featureActive and GetDB(db).keystoneAutoAnnounceEnabled == true then
        EnableAnnounceRuntime()
    else
        DisableAnnounceRuntime()
    end
end

local function BuildAnnounceTriggerOptions()
    return {
        {
            text = T("settings.keystone_announce_trigger_bag", "任意背包变化"),
            value = ANNOUNCE_TRIGGER_BAG,
        },
        {
            text = T("settings.keystone_announce_trigger_challenge_complete", "大秘境完成后"),
            value = ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE,
        },
    }
end

function KeystoneTools:NormalizeDB(db)
    return NormalizeDB(db)
end

function KeystoneTools:RefreshRuntime(db)
    RefreshAutoInsertRuntime(db)
    RefreshAnnounceRuntime(db)
end

function KeystoneTools:OnFeatureToggle(enable, db)
    featureActive = enable == true
    RefreshAutoInsertRuntime(db)
    RefreshAnnounceRuntime(db)
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or COLUMN_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or BODY_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or VALUE_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function KeystoneTools:BuildOptions(db)
    db = GetDB(db)

    local options = {}

    AddAlignedFieldGroup(options, T("settings.keystone_auto_insert", "自动插入"), {
        {
            type = "checkbox",
            label = T("settings.auto_keystone", "自动插钥石"),
            settingsToggle = "keystoneAutoInsert",
            searchKey = "settings.auto_keystone",
            get = function() return db.keystoneAutoInsertEnabled == true end,
            set = function(value)
                db.keystoneAutoInsertEnabled = value == true
                RefreshAutoInsertRuntime(db)
            end,
        },
    }, { columns = 1, hideDivider = true })

    AddAlignedFieldGroup(options, T("settings.keystone_announce", "钥石通报"), {
        {
            type = "checkbox",
            label = T("settings.auto_announce_new_keystone", "自动通报新钥石"),
            settingsToggle = "keystoneAutoAnnounce",
            searchKey = "settings.auto_announce_new_keystone",
            get = function() return db.keystoneAutoAnnounceEnabled == true end,
            set = function(value)
                db.keystoneAutoAnnounceEnabled = value == true
                RefreshAnnounceRuntime(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.keystone_announce_trigger", "通报触发方式"),
            options = BuildAnnounceTriggerOptions,
            default = ANNOUNCE_TRIGGER_CHALLENGE_COMPLETE,
            get = function() return NormalizeAnnounceTrigger(db.keystoneAutoAnnounceTrigger) end,
            set = function(value)
                db.keystoneAutoAnnounceTrigger = NormalizeAnnounceTrigger(value)
                StopAnnounceObservation(true)
                announceBaselinePending = true
                if PrimeAnnounceKeystone(IsWorldReady()) then
                    announceBaselinePending = false
                end
            end,
        },
    })

    return options
end

Tools.KeystoneTools = KeystoneTools
Tools:RegisterSubFeature(KeystoneTools)
