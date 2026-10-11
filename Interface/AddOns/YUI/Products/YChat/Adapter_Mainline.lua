local YUI = _G.YUI
if not YUI or not YUI.YChat or not YUI.YChat.Adapter then return end

local Adapter = YUI.YChat.Adapter
local Backend = {
    flavor = YUI.IsForever and "forever" or "mainline",
}

local restrictedActions = _G.C_RestrictedActions
local CheckAllowProtectedFunctions = restrictedActions and restrictedActions.CheckAllowProtectedFunctions
local chatAPI = _G.C_ChatInfo
local InChatMessagingLockdown = chatAPI and chatAPI.InChatMessagingLockdown
local enum = _G.Enum
local restrictionTypes = enum and enum.AddOnRestrictionType
local restrictionStates = enum and enum.AddOnRestrictionState
local CHAT_RESTRICTION = restrictionTypes and restrictionTypes.Chat
local RESTRICTION_INACTIVE = restrictionStates and restrictionStates.Inactive
local RESTRICTION_ACTIVATING = restrictionStates and restrictionStates.Activating
local RESTRICTION_ACTIVE = restrictionStates and restrictionStates.Active
local constants = _G.Constants
local chatFrameConstants = constants and constants.ChatFrameConstants
local MAX_CHAT_WINDOWS = chatFrameConstants and chatFrameConstants.MaxChatWindows
local GetNumReservedChatWindows = chatAPI and chatAPI.GetNumReservedChatWindows
local IsChatWindowIndexActive = _G.FCF_IsChatWindowIndexActive
local IsInInstance = _G.IsInInstance
local ResolveBNetByName = _G.BNet_GetBNetIDAccount
local ResolveBNetByCharacter = _G.BNet_GetBNetIDAccountFromCharacterName
local BNIsFriend = _G.BNIsFriend
local battleNetAPI = _G.C_BattleNet
local GetBNetAccountInfo = battleNetAPI and battleNetAPI.GetAccountInfoByID
local BNET_CLIENT_WOW = _G.BNET_CLIENT_WOW
local strcmputf8i = _G.strcmputf8i
local pcall = pcall
local floor = math.floor
local type = type
local ipairs = ipairs
local lower = string.lower
local find = string.find
local sub = string.sub

local function ReadTableField(container, key)
    return container[key]
end

local function ReadSafeTableField(container, key)
    if Adapter:IsExplicitlySafeValue(container) ~= true
        or type(container) ~= "table"
    then
        return nil, "table-unsafe"
    end
    local ok, value = pcall(ReadTableField, container, key)
    if not ok or Adapter:IsExplicitlySafeValue(value) ~= true then
        return nil, "field-unsafe"
    end
    return value
end

function Backend:CanCallProtected(object)
    if object == nil then return false, "protected-object-missing" end
    if type(CheckAllowProtectedFunctions) ~= "function" then
        return false, "protected-check-unavailable"
    end

    local ok, allowed = pcall(CheckAllowProtectedFunctions, object, true)
    if not ok then return false, "protected-check-error" end
    if allowed ~= true then return false, "protected-write-denied" end
    return true
end

function Backend:ReadInstanceState()
    if type(IsInInstance) ~= "function" then
        return nil, nil, "instance-state-api-unavailable"
    end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return nil, nil, "instance-state-read-error" end
    if type(inInstance) ~= "boolean"
        or Adapter:IsExplicitlySafeValue(inInstance) ~= true
        or type(instanceType) ~= "string"
        or Adapter:IsExplicitlySafeValue(instanceType) ~= true
    then
        return nil, nil, "instance-state-unsafe"
    end
    return inInstance, instanceType, nil
end

local function NamesEqual(left, right)
    if type(left) ~= "string" or left == ""
        or type(right) ~= "string" or right == ""
        or Adapter:IsExplicitlySafeValue(left) ~= true
        or Adapter:IsExplicitlySafeValue(right) ~= true
    then
        return false
    end
    if type(strcmputf8i) == "function" then
        local ok, compared = pcall(strcmputf8i, left, right)
        if ok and Adapter:IsExplicitlySafeValue(compared) == true then
            return compared == 0
        end
    end
    return lower(left) == lower(right)
end

local function MatchAccountName(name, accountInfo)
    if type(accountInfo) ~= "table"
        or Adapter:IsExplicitlySafeValue(accountInfo) ~= true
    then
        return false
    end
    if NamesEqual(name, accountInfo.accountName) then return true end
    local battleTag = accountInfo.battleTag
    if type(battleTag) == "string"
        and Adapter:IsExplicitlySafeValue(battleTag) == true
    then
        local marker = find(battleTag, "#", 1, true)
        local shortTag = marker and sub(battleTag, 1, marker - 1) or battleTag
        if NamesEqual(name, shortTag) then return true end
    end
    local gameAccountInfo = accountInfo.gameAccountInfo
    return type(gameAccountInfo) == "table"
        and Adapter:IsExplicitlySafeValue(gameAccountInfo) == true
        and NamesEqual(name, gameAccountInfo.characterName)
end

local function ValidateAccountID(name, accountID, requireFriend)
    if Adapter:IsExplicitlySafeValue(accountID) ~= true
        or type(accountID) ~= "number"
        or accountID < 1
        or floor(accountID) ~= accountID
    then
        return false
    end
    if requireFriend == true then
        local friendOK, isFriend = pcall(BNIsFriend, accountID)
        if not friendOK
            or Adapter:IsExplicitlySafeValue(isFriend) ~= true
            or isFriend ~= true
        then
            return false
        end
    end
    local infoOK, accountInfo = pcall(GetBNetAccountInfo, accountID)
    return infoOK and MatchAccountName(name, accountInfo)
end

local function ReadResolvedBNetCandidate(callback, name)
    if type(callback) ~= "function" then return nil, true end
    local ok, candidate = pcall(callback, name)
    if not ok or Adapter:IsExplicitlySafeValue(candidate) ~= true then
        return nil, false
    end
    if candidate == nil then return nil, true end
    if type(candidate) ~= "number"
        or candidate < 1
        or floor(candidate) ~= candidate
    then
        return nil, false
    end
    return candidate, true
end

local function IsHistoryBattleTag(value)
    return Adapter:IsExplicitlySafeValue(value) == true and type(value) == "string"
        and value:match("^[^#%s%c|:]+#%d+$") ~= nil
end

function Backend:ReadHistoryBattleTag(accountID)
    if Adapter:IsExplicitlySafeValue(accountID) ~= true or type(accountID) ~= "number"
        or accountID < 1 or accountID == math.huge or floor(accountID) ~= accountID
        or type(GetBNetAccountInfo) ~= "function" then return nil end
    local ok, info = pcall(GetBNetAccountInfo, accountID)
    if not ok then return nil end
    local tag = ReadSafeTableField(info, "battleTag")
    if IsHistoryBattleTag(tag) then return tag end
end

-- 回放批次内一次性建立映射；不把当前姓名、账号编号或映射持久化。
function Backend:BuildHistoryBNetLookup()
    local getCount = _G.BNGetNumFriends
    local getFriend = battleNetAPI and battleNetAPI.GetFriendAccountInfo
    if type(getCount) ~= "function" or type(getFriend) ~= "function" then return nil end
    local ok, count = pcall(getCount)
    if not ok or Adapter:IsExplicitlySafeValue(count) ~= true or type(count) ~= "number"
        or count < 0 or count > 1000 or floor(count) ~= count then return nil end
    local lookup = {}
    for index = 1, count do
        local infoOK, info = pcall(getFriend, index)
        if not infoOK or Adapter:IsExplicitlySafeValue(info) ~= true
            or type(info) ~= "table" then return nil end
        local tag = ReadSafeTableField(info, "battleTag")
        if IsHistoryBattleTag(tag) then
            local id = ReadSafeTableField(info, "bnetAccountID")
            local name = ReadSafeTableField(info, "accountName")
            local friend = ReadSafeTableField(info, "isFriend")
            if lookup[tag] ~= nil then
                lookup[tag] = false
            elseif friend == true and type(id) == "number" and id > 0
                and id < math.huge and floor(id) == id
                and type(name) == "string" and name ~= "" and not name:find("[:%c]")
                and (not name:find("|", 1, true) or name:match("^|K[^|:]+|k$")) then
                lookup[tag] = { accountID = id, name = name }
            else
                lookup[tag] = false
            end
        end
    end
    return lookup
end

function Backend:ResolveBNetAccountID(name, candidateID)
    if type(name) ~= "string" or name == ""
        or Adapter:IsExplicitlySafeValue(name) ~= true
        or type(GetBNetAccountInfo) ~= "function"
        or type(BNIsFriend) ~= "function"
    then
        return nil, "bnet-account-resolution-unavailable"
    end
    if ValidateAccountID(name, candidateID, false) then return candidateID end

    local characterID, characterOK =
        ReadResolvedBNetCandidate(ResolveBNetByCharacter, name)
    local accountID, accountOK = ReadResolvedBNetCandidate(ResolveBNetByName, name)
    if not characterOK or not accountOK
        or (characterID ~= nil and accountID ~= nil and characterID ~= accountID)
    then
        return nil, "bnet-account-resolution-ambiguous"
    end
    local resolved = characterID or accountID
    if resolved == nil then return nil, "bnet-account-resolution-missing" end

    local friendOK, friend = pcall(BNIsFriend, resolved)
    if not friendOK
        or Adapter:IsExplicitlySafeValue(friend) ~= true
        or friend ~= true
    then
        return nil, "bnet-account-not-friend"
    end
    local infoOK, accountInfo = pcall(GetBNetAccountInfo, resolved)
    if not infoOK or not MatchAccountName(name, accountInfo) then
        return nil, "bnet-account-name-mismatch"
    end
    return resolved
end

function Backend:ResolveCurrentBNetClassToken(accountID)
    if type(GetBNetAccountInfo) ~= "function"
        or type(BNET_CLIENT_WOW) ~= "string"
        or BNET_CLIENT_WOW == ""
        or Adapter:IsExplicitlySafeValue(accountID) ~= true
        or type(accountID) ~= "number"
        or accountID < 1
        or floor(accountID) ~= accountID
    then
        return nil, "bnet-current-game-unavailable"
    end

    local infoOK, accountInfo = pcall(GetBNetAccountInfo, accountID)
    if not infoOK or Adapter:IsExplicitlySafeValue(accountInfo) ~= true
        or type(accountInfo) ~= "table"
    then
        return nil, "bnet-account-info-unsafe"
    end
    local gameAccountInfo = ReadSafeTableField(accountInfo, "gameAccountInfo")
    if type(gameAccountInfo) ~= "table" then
        return nil, "bnet-current-game-missing"
    end
    local clientProgram = ReadSafeTableField(gameAccountInfo, "clientProgram")
    local isOnline = ReadSafeTableField(gameAccountInfo, "isOnline")
    if clientProgram ~= BNET_CLIENT_WOW or isOnline ~= true then
        return nil, "bnet-current-game-not-wow"
    end
    local classToken = ReadSafeTableField(gameAccountInfo, "classFilename")
    if Adapter:IsExplicitlySafeValue(classToken) ~= true
        or type(classToken) ~= "string" or classToken == ""
    then
        return nil, "bnet-current-game-class-missing"
    end
    return classToken
end

local function ClassifyPermanentFrame(frame, includeReserved)
    if frame == nil or type(frame.GetID) ~= "function" or type(frame.GetName) ~= "function" then
        return false, "permanent-frame-identity-unavailable"
    end
    if type(MAX_CHAT_WINDOWS) ~= "number"
        or MAX_CHAT_WINDOWS < 1
        or floor(MAX_CHAT_WINDOWS) ~= MAX_CHAT_WINDOWS
    then
        return false, "permanent-frame-limit-unavailable"
    end
    if type(GetNumReservedChatWindows) ~= "function"
        or type(IsChatWindowIndexActive) ~= "function"
    then
        return false, "permanent-frame-classifier-unavailable"
    end

    local idOK, id = pcall(frame.GetID, frame)
    if not idOK
        or type(id) ~= "number"
        or id < 1
        or floor(id) ~= id
        or id > MAX_CHAT_WINDOWS
    then
        return false, "temporary-or-invalid-chat-frame"
    end
    if frame.isTemporary == true then return false, "temporary-chat-frame" end

    local nameOK, name = pcall(frame.GetName, frame)
    local expectedName = "ChatFrame" .. id
    if not nameOK or type(name) ~= "string" or name ~= expectedName or _G[expectedName] ~= frame then
        return false, "permanent-frame-identity-mismatch"
    end

    local reservedOK, reserved = pcall(GetNumReservedChatWindows)
    if not reservedOK
        or type(reserved) ~= "number"
        or reserved < 1
        or floor(reserved) ~= reserved
        or reserved > MAX_CHAT_WINDOWS
    then
        return false, "reserved-window-count-invalid"
    end
    if includeReserved ~= true and id ~= 1 and id <= reserved then
        return false, "reserved-special-chat-frame"
    end

    local activeOK, active = pcall(IsChatWindowIndexActive, id)
    if not activeOK or Adapter:IsExplicitlySafeValue(active) ~= true then
        return false, "permanent-frame-activity-unknown"
    end
    if active ~= true and active ~= 1 then
        if active == false or active == nil then
            return false, "inactive-permanent-chat-frame"
        end
        return false, "permanent-frame-activity-unknown"
    end
    return true, includeReserved == true
        and "stable-permanent-chat-tab"
        or "ordinary-permanent-chat-frame"
end

function Backend:ClassifyFrame(frame)
    return ClassifyPermanentFrame(frame, false)
end

function Backend:ClassifyTypographyFrame(frame)
    local supported, reason = ClassifyPermanentFrame(frame, false)
    if supported == true then return true, reason end

    if frame == _G.ChatFrame2 and frame == _G.COMBATLOG then
        return self:ClassifyCombatLogFrame(frame)
    end
    if frame == nil
        or Adapter:IsExplicitlySafeValue(frame) ~= true
        or Adapter:IsExplicitlySafeValue(frame.isTemporary) ~= true
        or Adapter:IsExplicitlySafeValue(frame.inUse) ~= true
        or Adapter:IsExplicitlySafeValue(frame.chatType) ~= true
        or frame.isTemporary ~= true
        or frame.inUse ~= true
        or (frame.chatType ~= "WHISPER" and frame.chatType ~= "BN_WHISPER")
        or type(MAX_CHAT_WINDOWS) ~= "number"
        or type(frame.GetID) ~= "function"
        or type(frame.GetName) ~= "function"
    then
        return false, reason or "typography-frame-unsupported"
    end

    local idOK, id = pcall(frame.GetID, frame)
    local nameOK, name = pcall(frame.GetName, frame)
    if not idOK
        or not nameOK
        or Adapter:IsExplicitlySafeValue(id) ~= true
        or Adapter:IsExplicitlySafeValue(name) ~= true
        or type(id) ~= "number"
        or id <= MAX_CHAT_WINDOWS
        or floor(id) ~= id
        or type(name) ~= "string"
        or name ~= "ChatFrame" .. id
        or _G[name] ~= frame
    then
        return false, "temporary-whisper-identity-mismatch"
    end
    return true, "temporary-whisper-typography-frame"
end

function Backend:ClassifyAppearanceTab(frame)
    return ClassifyPermanentFrame(frame, true)
end

function Backend:ClassifyCombatLogFrame(frame)
    if frame == nil
        or frame ~= _G.ChatFrame2
        or frame ~= _G.COMBATLOG
    then
        return false, "combat-log-identity-mismatch"
    end
    local supported, reason = ClassifyPermanentFrame(frame, true)
    if supported ~= true then return false, reason end
    local idOK, id = pcall(frame.GetID, frame)
    if not idOK or id ~= 2 then return false, "combat-log-id-mismatch" end

    local quickBar = _G.CombatLogQuickButtonFrame_Custom
    local filterButton = quickBar and quickBar.AdditionalFilterButton
        or _G.CombatLogQuickButtonFrame_CustomAdditionalFilterButton
    if not quickBar
        or not filterButton
        or type(quickBar.GetParent) ~= "function"
        or type(quickBar.GetNumPoints) ~= "function"
        or type(filterButton.GetParent) ~= "function"
    then
        return false, "combat-log-structure-mismatch"
    end
    local parentOK, parent = pcall(quickBar.GetParent, quickBar)
    local filterParentOK, filterParent = pcall(filterButton.GetParent, filterButton)
    local expectedTab = _G.ChatFrame2Tab
    if not parentOK
        or not filterParentOK
        or (parent ~= frame and parent ~= expectedTab)
        or filterParent ~= quickBar
    then
        return false, "combat-log-parent-mismatch"
    end
    return true, "combat-log-permanent-shell"
end

function Backend:IsAppearanceTabSelected(frame)
    local supported, supportReason = ClassifyPermanentFrame(frame, true)
    if supported ~= true then return nil, supportReason end

    local isDocked = frame.isDocked
    if Adapter:IsExplicitlySafeValue(isDocked) ~= true then
        return nil, "appearance-tab-dock-state-unsafe"
    end
    if isDocked == nil or isDocked == false then return true end
    if isDocked ~= true and isDocked ~= 1 then
        return nil, "appearance-tab-dock-state-invalid"
    end

    local dock = _G.GENERAL_CHAT_DOCK
    local getSelectedWindow = _G.FCFDock_GetSelectedWindow
    if dock == nil or type(getSelectedWindow) ~= "function" then
        return nil, "appearance-tab-selection-api-unavailable"
    end
    if Adapter:IsExplicitlySafeValue(dock) ~= true then
        return nil, "appearance-tab-dock-unsafe"
    end

    local selectedOK, selectedFrame = pcall(getSelectedWindow, dock)
    if not selectedOK
        or selectedFrame == nil
        or Adapter:IsExplicitlySafeValue(selectedFrame) ~= true
    then
        return nil, "appearance-tab-selection-read-failed"
    end
    return selectedFrame == frame
end

function Backend:IsAppearanceTabDocked(frame)
    local supported, supportReason = ClassifyPermanentFrame(frame, true)
    if supported ~= true then return nil, supportReason end

    local docked = frame.isDocked
    if Adapter:IsExplicitlySafeValue(docked) ~= true then
        return nil, "appearance-tab-dock-state-unsafe"
    end
    if docked == true or docked == 1 then return true end
    if docked == false or docked == nil then return false end
    return nil, "appearance-tab-dock-state-invalid"
end

local function ReadDockTab(frame)
    local supported, supportReason = ClassifyPermanentFrame(frame, true)
    if supported ~= true then return nil, supportReason end
    local nameOK, name = pcall(frame.GetName, frame)
    if not nameOK
        or Adapter:IsExplicitlySafeValue(name) ~= true
        or type(name) ~= "string"
    then
        return nil, "appearance-dock-tab-name-unsafe"
    end
    local tab = _G[name .. "Tab"]
    local tabText = tab and tab.Text
    if tab == nil
        or tabText == nil
        or Adapter:IsExplicitlySafeValue(tab) ~= true
        or Adapter:IsExplicitlySafeValue(tabText) ~= true
        or type(tab.ClearAllPoints) ~= "function"
        or type(tab.SetPoint) ~= "function"
        or type(tab.SetWidth) ~= "function"
        or type(tabText.SetWidth) ~= "function"
    then
        return nil, "appearance-dock-tab-structure-mismatch"
    end
    if Adapter:CanCallProtected(tab) ~= true
        or Adapter:CanCallProtected(tabText) ~= true
    then
        return nil, "appearance-dock-tab-protected"
    end
    return tab, tabText
end

local function IsNativeTemporaryWhisperDockFrame(frame)
    local supported, supportReason = Backend:ClassifyTypographyFrame(frame)
    if supported ~= true
        or supportReason ~= "temporary-whisper-typography-frame"
    then
        return false
    end

    local nameOK, name = pcall(frame.GetName, frame)
    if not nameOK
        or Adapter:IsExplicitlySafeValue(name) ~= true
        or type(name) ~= "string"
    then
        return false
    end
    local tab = _G[name .. "Tab"]
    local tabText = tab and tab.Text
    return tab ~= nil
        and tabText ~= nil
        and Adapter:IsExplicitlySafeValue(tab) == true
        and Adapter:IsExplicitlySafeValue(tabText) == true
end

local function ReadDockTabPadding(tab)
    local padding = tab.sizePadding
    if padding == nil then
        padding = 0
    elseif Adapter:IsExplicitlySafeValue(padding) ~= true
        or type(padding) ~= "number"
        or not (padding > -math.huge and padding < math.huge)
    then
        return nil
    end
    return padding
end

local function MeasureDockTabWidth(tab, tabText)
    local padding = ReadDockTabPadding(tab)
    local readWidth = tabText.GetUnboundedStringWidth or tabText.GetStringWidth
    if padding == nil or type(readWidth) ~= "function" then return nil end
    local ok, textWidth = pcall(readWidth, tabText)
    if not ok
        or Adapter:IsExplicitlySafeValue(textWidth) ~= true
        or type(textWidth) ~= "number"
        or not (textWidth >= 0 and textWidth < math.huge)
    then
        return nil
    end
    local width = math.floor(textWidth + 20 + padding + 0.5)
    if width < 48 then width = 48 end
    if width > 160 then width = 160 end
    return width
end

local function SetDockTabWidth(tab, tabText, width)
    local padding = ReadDockTabPadding(tab)
    if padding == nil then return false end
    local textWidth = width - 20 - padding
    if textWidth < 1 then textWidth = 1 end
    return pcall(tabText.SetWidth, tabText, textWidth)
        and pcall(tab.SetWidth, tab, width)
end

function Backend:ReconcileAppearanceDockTabWidths(
    tabWidth,
    tabWidthMode,
    tabSpacing,
    tabLeftInset,
    hideCombatLog,
    skipNativeRefresh
)
    local dock = _G.GENERAL_CHAT_DOCK
    local update = _G.FCFDock_UpdateTabs
    if dock == nil or type(update) ~= "function" then
        return false, "appearance-dock-tab-api-unavailable"
    end
    if Adapter:IsExplicitlySafeValue(dock) ~= true then
        return false, "appearance-dock-tab-unsafe"
    end
    local allowed = self:CanCallProtected(dock)
    if allowed ~= true then
        return false, "appearance-dock-tab-protected"
    end
    if skipNativeRefresh ~= nil and type(skipNativeRefresh) ~= "boolean" then
        return false, "appearance-dock-tab-refresh-mode-invalid"
    end
    if skipNativeRefresh ~= true and not pcall(update, dock, true) then
        return false, "appearance-dock-tab-update-failed"
    end
    if tabWidth == nil and tabWidthMode == nil then return true end
    if Adapter:IsExplicitlySafeValue(tabWidthMode) ~= true
        or type(tabWidthMode) ~= "string"
        or (tabWidthMode ~= "auto" and tabWidthMode ~= "fixed")
        or (tabWidthMode == "fixed" and (
            Adapter:IsExplicitlySafeValue(tabWidth) ~= true
            or type(tabWidth) ~= "number"
            or not (tabWidth > 20 and tabWidth < math.huge)
        ))
        or Adapter:IsExplicitlySafeValue(tabSpacing) ~= true
        or Adapter:IsExplicitlySafeValue(tabLeftInset) ~= true
        or type(tabSpacing) ~= "number"
        or type(tabLeftInset) ~= "number"
        or not (tabSpacing >= 0 and tabSpacing < math.huge)
        or not (tabLeftInset >= 0 and tabLeftInset < math.huge)
        or (hideCombatLog ~= true and hideCombatLog ~= false)
    then
        return false, "appearance-dock-tab-layout-invalid"
    end

    local frames = dock.DOCKED_CHAT_FRAMES
    local scrollFrame = dock.scrollFrame
    local overflowButton = dock.overflowButton
    if type(frames) ~= "table"
        or scrollFrame == nil
        or overflowButton == nil
        or type(dock.GetWidth) ~= "function"
        or type(scrollFrame.GetScrollChild) ~= "function"
        or type(scrollFrame.ClearAllPoints) ~= "function"
        or type(scrollFrame.SetPoint) ~= "function"
        or type(overflowButton.Show) ~= "function"
        or type(overflowButton.Hide) ~= "function"
        or Adapter:IsExplicitlySafeValue(frames) ~= true
        or Adapter:IsExplicitlySafeValue(scrollFrame) ~= true
        or Adapter:IsExplicitlySafeValue(overflowButton) ~= true
        or Adapter:CanCallProtected(scrollFrame) ~= true
        or Adapter:CanCallProtected(overflowButton) ~= true
    then
        return false, "appearance-dock-tab-layout-structure-mismatch"
    end

    local childOK, scrollChild = pcall(scrollFrame.GetScrollChild, scrollFrame)
    local widthOK, dockWidth = pcall(dock.GetWidth, dock)
    if not childOK
        or not widthOK
        or scrollChild == nil
        or Adapter:IsExplicitlySafeValue(scrollChild) ~= true
        or Adapter:IsExplicitlySafeValue(dockWidth) ~= true
        or type(dockWidth) ~= "number"
        or not (dockWidth > 0 and dockWidth < math.huge)
    then
        return false, "appearance-dock-tab-layout-measure-failed"
    end

    local staticCount = 0
    local dynamicCount = 0
    local selectedDynamicIndex
    local resolvedTabWidth = tabWidthMode == "fixed" and tabWidth or 48
    local nativeTemporaryPresent = false
    for _, frame in ipairs(frames) do
        local tab, tabText = ReadDockTab(frame)
        if not tab then
            if IsNativeTemporaryWhisperDockFrame(frame) then
                nativeTemporaryPresent = true
            else
                return false, "appearance-dock-tab-layout-frame-invalid"
            end
        elseif frame ~= _G.ChatFrame2 or hideCombatLog ~= true then
            if tabWidthMode == "auto" then
                local measuredWidth = MeasureDockTabWidth(tab, tabText)
                if not measuredWidth then
                    return false, "appearance-dock-tab-layout-measure-failed"
                end
                if measuredWidth > resolvedTabWidth then
                    resolvedTabWidth = measuredWidth
                end
            end
            local static = frame.isStaticDocked
            if Adapter:IsExplicitlySafeValue(static) ~= true then
                return false, "appearance-dock-tab-layout-state-unsafe"
            end
            if static then
                staticCount = staticCount + 1
            else
                dynamicCount = dynamicCount + 1
                if dock.selected == frame then
                    selectedDynamicIndex = dynamicCount
                end
            end
        end
    end
    if nativeTemporaryPresent then
        return true, "appearance-dock-tab-native-temporary"
    end

    local overflowWidth = overflowButton.width
    if Adapter:IsExplicitlySafeValue(overflowWidth) ~= true
        or type(overflowWidth) ~= "number"
        or not (overflowWidth > 0 and overflowWidth < math.huge)
    then
        local overflowOK
        overflowOK, overflowWidth = pcall(overflowButton.GetWidth, overflowButton)
        if not overflowOK
            or Adapter:IsExplicitlySafeValue(overflowWidth) ~= true
            or type(overflowWidth) ~= "number"
            or not (overflowWidth > 0 and overflowWidth < math.huge)
        then
            return false, "appearance-dock-tab-overflow-width-invalid"
        end
    end

    local lastStatic
    local lastDynamic
    for _, frame in ipairs(frames) do
        if frame ~= _G.ChatFrame2 or hideCombatLog ~= true then
            local tab, tabText = ReadDockTab(frame)
            if not tab
                or not SetDockTabWidth(tab, tabText, resolvedTabWidth)
                or not pcall(tab.ClearAllPoints, tab)
            then
                return false, "appearance-dock-tab-layout-apply-failed"
            end
            if frame.isStaticDocked then
                local anchored
                if lastStatic then
                    anchored = pcall(
                        tab.SetPoint,
                        tab,
                        "LEFT",
                        lastStatic,
                        "RIGHT",
                        tabSpacing,
                        0
                    )
                else
                    anchored = pcall(
                        tab.SetPoint,
                        tab,
                        "BOTTOMLEFT",
                        dock,
                        "BOTTOMLEFT",
                        tabLeftInset,
                        0
                    )
                end
                if not anchored then
                    return false, "appearance-dock-tab-static-anchor-failed"
                end
                lastStatic = tab
            else
                local anchored
                if lastDynamic then
                    anchored = pcall(
                        tab.SetPoint,
                        tab,
                        "LEFT",
                        lastDynamic,
                        "RIGHT",
                        tabSpacing,
                        0
                    )
                else
                    anchored = pcall(
                        tab.SetPoint,
                        tab,
                        "LEFT",
                        scrollChild,
                        "LEFT",
                        0,
                        -1
                    )
                end
                if not anchored then
                    return false, "appearance-dock-tab-dynamic-anchor-failed"
                end
                lastDynamic = tab
            end
        end
    end

    local scrollLeft = tabLeftInset
    if staticCount > 0 then
        scrollLeft = scrollLeft
            + staticCount * resolvedTabWidth
            + staticCount * tabSpacing
    end
    local availableWidth = dockWidth - scrollLeft
    local dynamicWidth = 0
    if dynamicCount > 0 then
        dynamicWidth = dynamicCount * resolvedTabWidth
            + (dynamicCount - 1) * tabSpacing
    end
    local hasOverflow = dynamicWidth > availableWidth
    local leftAnchor = lastStatic or dock
    local leftPoint = lastStatic and "RIGHT" or "LEFT"
    local leftX = lastStatic and tabSpacing or tabLeftInset
    if not pcall(scrollFrame.ClearAllPoints, scrollFrame)
        or not pcall(
            scrollFrame.SetPoint,
            scrollFrame,
            "LEFT",
            leftAnchor,
            leftPoint,
            leftX,
            0
        )
    then
        return false, "appearance-dock-tab-scroll-anchor-failed"
    end

    if hasOverflow then
        if not pcall(overflowButton.Show, overflowButton)
            or not pcall(
                scrollFrame.SetPoint,
                scrollFrame,
                "BOTTOMRIGHT",
                overflowButton,
                "BOTTOMLEFT",
                -5,
                0
            )
        then
            return false, "appearance-dock-tab-overflow-anchor-failed"
        end
    elseif not pcall(overflowButton.Hide, overflowButton)
        or not pcall(
            scrollFrame.SetPoint,
            scrollFrame,
            "BOTTOMRIGHT",
            dock,
            "BOTTOMRIGHT",
            0,
            -1
        )
    then
        return false, "appearance-dock-tab-scroll-right-anchor-failed"
    end

    scrollFrame.dynTabSize = resolvedTabWidth + tabSpacing
    scrollFrame.numDynFrames = dynamicCount
    scrollFrame.selectedDynIndex = selectedDynamicIndex
    local scrollToSelected = _G.FCFDock_ScrollToSelectedTab
    if type(scrollToSelected) == "function"
        and not pcall(scrollToSelected, dock)
    then
        return false, "appearance-dock-tab-scroll-sync-failed"
    end
    return true
end

function Backend:ReadRestrictionState()
    if type(InChatMessagingLockdown) ~= "function" then return "UNKNOWN" end
    local ok, locked = pcall(InChatMessagingLockdown)
    if not ok or type(locked) ~= "boolean" then return "UNKNOWN" end
    if locked == true then return "PAUSED" end
    if locked == false then return "OPEN" end
    return "UNKNOWN"
end

function Backend:RegisterEvents(frame)
    if type(InChatMessagingLockdown) ~= "function" then return 0 end
    frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    return 1
end

function Backend:HandleEvent(event, restrictionType, restrictionState)
    if event ~= "ADDON_RESTRICTION_STATE_CHANGED" then return false end
    if CHAT_RESTRICTION == nil then return true, "UNKNOWN" end
    if restrictionType ~= CHAT_RESTRICTION then return false end

    if restrictionState == RESTRICTION_ACTIVATING or restrictionState == RESTRICTION_ACTIVE then
        return true, "PAUSED"
    end
    if restrictionState == RESTRICTION_INACTIVE then return true, "REFRESH" end
    return true, "UNKNOWN"
end

Adapter:SetClientBackend(Backend)
