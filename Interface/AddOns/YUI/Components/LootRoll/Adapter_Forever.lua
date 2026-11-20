local ADDON_NAME, YUI = ...
YUI = _G.YUI or YUI
if not YUI or not YUI.IsForever then return end
local bootstrap = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if bootstrap and bootstrap.productEnabled == false then return end
YUI.API = YUI.API or {}
local API = {}
YUI.API.LootRoll = API
local CLEARED_STAMP_LIMIT = 2048
local ItemAPI = YUI.API.Item
local actions = { pass = 0, need = 1, greed = 2, transmog = 4 }
local historyPass = Enum and Enum.EncounterLootDropRollState and Enum.EncounterLootDropRollState.Pass or 5
local nativeNames = { "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4" }
local nativeState = setmetatable({}, { __mode = "k" })
local nativeMouse = setmetatable({}, { __mode = "k" })
local nativeHooks = setmetatable({}, { __mode = "k" })
local owns, isClosed, lostCallback, updating
local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end
local function PublicValue(value)
    if Public(value) then return value end
end
local function PublicTable(value)
    if Public(value) and type(value) == "table" then return value end
end
local function IsID(value)
    return Public(value) and type(value) == "number" and value > -math.huge and value < math.huge
end
local function PlainPlayer(p)
    if not PublicTable(p) or not Public(p.playerName) or not Public(p.state) or not Public(p.roll) then return nil end
    return { playerName = p.playerName, playerGUID = PublicValue(p.playerGUID), playerClass = PublicValue(p.playerClass),
        isSelf = Public(p.isSelf) and p.isSelf == true, isWinner = Public(p.isWinner) and p.isWinner == true,
        state = p.state, roll = p.roll }
end
function API.IsGamepad()
    if InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" then
        local enabled = InputUtil.IsGamepadUIEnabled()
        if Public(enabled) and type(enabled) == "boolean" then return enabled end
    end
    local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
    if gamepad and C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" then
        local style = C_InputInterfaceStyle.GetCurrentStyle()
        return Public(style) and style == gamepad
    end
    return false
end
function API.Available()
    return type(GetLootRollItemInfo) == "function" and type(GetActiveLootRollIDs) == "function"
        and type(RollOnLoot) == "function" and C_LootHistory and type(C_LootHistory.GetSortedInfoForDrop) == "function"
        and YUI.API.Security and type(YUI.API.Security.SafeHook) == "function"
end
function API.ReadRoll(id)
    if not IsID(id) or not API.Available() then return nil end
    local texture, name, quantity, quality, bind, need, greed, _, reasonNeed, reasonGreed, _, _, transmog = GetLootRollItemInfo(id)
    if not Public(name) or not name or not Public(need) or not Public(greed)
        or not Public(transmog) or not Public(quality) then return nil end
    return { name = name, texture = PublicValue(texture),
        quantity = Public(quantity) and type(quantity) == "number" and quantity or nil, quality = quality,
        link = GetLootRollItemLink and PublicValue(GetLootRollItemLink(id)), bind = Public(bind) and bind == true,
        canNeed = need == true, canGreed = greed == true,
        canTransmog = transmog == true, reasonNeed = Public(reasonNeed) and reasonNeed or nil,
        reasonGreed = Public(reasonGreed) and reasonGreed or nil }
end
function API.ShowItemTooltip(owner, rollID, link)
    local tooltip = GameTooltip
    if not tooltip then return end
    if IsID(rollID) and tooltip.SetLootRollItem then
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
        tooltip:SetLootRollItem(rollID)
    elseif Public(link) and type(link) == "string" then
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
        tooltip:SetHyperlink(link)
    else
        return
    end
    tooltip:Show()
end
local function Seconds(value)
    if Public(value) and type(value) == "number" and value >= 0 and value < math.huge then return value / 1000 end
end
function API.TimeLeft(id)
    if IsID(id) then return Seconds(GetLootRollTimeLeft and GetLootRollTimeLeft(id)) end
end
function API.Duration(id, milliseconds)
    local duration = Seconds(milliseconds)
    if (not duration or duration == 0) and IsID(id) then
        duration = Seconds(C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(id))
    end
    if duration and duration > 0 then return duration end
end
function API.HistoryTime()
    local value = C_LootHistory and C_LootHistory.GetLootHistoryTime and C_LootHistory.GetLootHistoryTime()
    if Public(value) and type(value) == "number" and value >= 0 and value < math.huge then return value end
end
function API.HistoryOwner()
    local guid = UnitGUID and UnitGUID("player")
    if Public(guid) and type(guid) == "string" and guid ~= "" then return guid end
end
function API.ActiveIDs()
    local ids = GetActiveLootRollIDs and GetActiveLootRollIDs()
    if not PublicTable(ids) then return end
    for _, id in ipairs(ids) do
        if not IsID(id) then return end
    end
    return ids
end
function API.ActiveRollSet(ids)
    if not Public(ids) then return end
    if ids == nil then
        ids = GetActiveLootRollIDs and GetActiveLootRollIDs()
    end
    if not PublicTable(ids) then return end
    local rolls = {}
    for _, id in ipairs(ids) do
        if not IsID(id) then return end
        rolls[id] = true
    end
    return rolls
end
function API.GroupSize()
    local count = GetNumGroupMembers and GetNumGroupMembers()
    if Public(count) and type(count) == "number" and count > 0 then return count end
end
function API.AllEncounters()
    local read = C_LootHistory and C_LootHistory.GetAllEncounterInfos
    return read and PublicTable(read()) or {}
end
function API.EncounterDrops(id)
    local read = C_LootHistory and C_LootHistory.GetSortedDropsForEncounter
    return read and IsID(id) and PublicTable(read(id)) or {}
end
function API.HistoryID(value, field)
    local id = PublicTable(value) and value[field]
    if IsID(id) then return id end
end
local function HistoryStamp(encounter, key, startTime)
    if IsID(encounter) and IsID(key) and Public(startTime) and type(startTime) == "number"
        and startTime >= 0 and startTime < math.huge then
        return tostring(encounter) .. ":" .. tostring(key) .. ":" .. tostring(startTime)
    end
end
function API.StampFromIdentity(identity)
    return Public(identity) and type(identity) == "string" and identity:match("^([^:]+:[^:]+:[^:]+):") or nil
end
local function VisitHistory(visit)
    for _, info in ipairs(API.AllEncounters()) do
        local encounterID = API.HistoryID(info, "encounterID")
        for _, raw in ipairs(API.EncounterDrops(encounterID)) do
            if PublicTable(raw) then
                local stamp = HistoryStamp(encounterID, raw.lootListKey, raw.startTime)
                if stamp then visit(stamp, encounterID, raw) end
            end
        end
    end
end
function API.ClearedHistoryStamps(previous, keep)
    local stamps, through = {}
    for stamp in pairs(previous or {}) do stamps[stamp] = true end
    VisitHistory(function(stamp, encounterID, raw)
        if (PublicTable(raw.winner) or Public(raw.allPassed) and raw.allPassed == true)
            and not (keep and keep(encounterID, raw.lootListKey, raw)) then
            stamps[stamp] = true
            through = math.max(through or 0, raw.startTime)
        end
    end)
    return stamps, through
end
function API.TrimClearedStamps(stamps)
    if not stamps then return end
    local count = 0
    for _ in pairs(stamps) do count = count + 1 end
    if count <= CLEARED_STAMP_LIMIT then return end

    local visible, entries = {}, {}
    VisitHistory(function(stamp, _, raw)
        if stamps[stamp] then visible[stamp] = raw.startTime end
    end)
    for stamp in pairs(stamps) do
        local time = type(stamp) == "string" and tonumber(stamp:match(":([^:]+)$"))
        entries[#entries + 1] = { stamp = stamp, time = IsID(time) and time or -1, visible = visible[stamp] ~= nil }
    end
    table.sort(entries, function(a, b)
        if a.visible ~= b.visible then return a.visible end
        if a.time ~= b.time then return a.time > b.time end
        return tostring(a.stamp) > tostring(b.stamp)
    end)
    local through
    for index = CLEARED_STAMP_LIMIT + 1, #entries do
        local entry = entries[index]
        stamps[entry.stamp] = nil
        if entry.visible then through = math.max(through or 0, entry.time) end
    end
    return through, true
end
-- 历史的通用分类不是怪物名称；也用于回看旧快照。
function API.SourceName(value)
    if not Public(value) or type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or value == OTHER or value == MISCELLANEOUS or value == "Other" or value == "其他" or value == "其它" or value == "其他來源" then return nil end
    return value
end
function API.ReadDrop(encounter, key, raw)
    if not IsID(encounter) or not IsID(key) then return nil end
    raw = PublicTable(raw or C_LootHistory.GetSortedInfoForDrop(encounter, key))
    if not raw or not Public(raw.itemHyperlink) or type(raw.itemHyperlink) ~= "string" then return nil end
    local readEncounter = C_LootHistory.GetInfoForEncounter
    local encounterInfo = readEncounter and PublicTable(readEncounter(encounter))
    local drop = { itemHyperlink = raw.itemHyperlink, playerRollState = Public(raw.playerRollState) and raw.playerRollState or nil,
        currentLeader = PlainPlayer(raw.currentLeader), winner = PlainPlayer(raw.winner),
        allPassed = Public(raw.allPassed) and raw.allPassed == true,
        isTied = Public(raw.isTied) and raw.isTied == true, rollInfos = {} }
    local stamp = HistoryStamp(encounter, key, raw.startTime)
    if stamp then
        drop.nativeIdentity = stamp .. ":" .. raw.itemHyperlink
        drop.startTime = raw.startTime
    end
    if Public(raw.duration) and type(raw.duration) == "number" and raw.duration > 0 and raw.duration < math.huge then drop.duration = raw.duration end
    local allPass = Public(raw.winner) and raw.winner == nil
        and Public(raw.currentLeader) and raw.currentLeader == nil and drop.playerRollState == historyPass
    local sawSelf = false
    for _, p in ipairs(PublicTable(raw.rollInfos) or {}) do
        local player = PlainPlayer(p)
        if player then drop.rollInfos[#drop.rollInfos + 1] = player end
        allPass = allPass and player and player.state == historyPass
        if player and player.isSelf then sawSelf = true end
    end
    drop.rosterAllPassed = allPass and sawSelf or nil
    -- 首版保留采集时刻；历史时基尚未实机校准，不把原始 startTime 当日历时间。
    return drop, API.SourceName(encounterInfo and encounterInfo.encounterName), stamp
end
function API.Allowed(data, choice)
    if not PublicTable(data) or not Public(choice) then return false end
    return choice == "pass" or choice == "need" and Public(data.canNeed) and data.canNeed == true
        or choice == "greed" and Public(data.canTransmog) and not data.canTransmog
            and Public(data.canGreed) and data.canGreed == true
        or choice == "transmog" and Public(data.canTransmog) and data.canTransmog == true
end
function API.Reason(data, choice)
    local reason = data and data[choice == "need" and "reasonNeed" or "reasonGreed"]
    if Public(reason) and (type(reason) == "number" or type(reason) == "string") then
        return _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
    end
end
function API.Request(id, choice, data)
    local action = Public(choice) and actions[choice]
    if not action or not IsID(id) or not Public(data) or type(RollOnLoot) ~= "function"
        or API.IsGamepad() or API.IsConfirming() then return false end
    -- 内部调用者可复用本次点击读出的权限；提交前仍核对原生待选列表。
    if data == nil then data = API.ReadRoll(id) end
    if not API.Allowed(data, choice) then return false end
    local rolls = API.ActiveRollSet()
    if not rolls then return false, "native-unavailable" end
    if not rolls[id] then return false, "native-closed" end
    RollOnLoot(id, action)
    return true
end
function API.IsConfirming(id)
    if not StaticPopup_Visible or not Public(id) then return false end
    local name, popup = StaticPopup_Visible("CONFIRM_LOOT_ROLL")
    if id == nil then
        return (Public(name) and type(name) == "string") or (Public(popup) and popup ~= nil)
    end
    if not IsID(id) or not Public(popup) or not popup then return false end
    local rollID = popup.data
    return Public(rollID) and rollID == id
end
function API.ItemDetails(link)
    local info = Public(link) and type(link) == "string" and ItemAPI and PublicTable(ItemAPI.GetInfo(link))
    if not info then return { equip = "unknown" } end
    local slot = Public(info.equipLoc) and type(info.equipLoc) == "string" and info.equipLoc or nil
    local equipment = slot and slot ~= "" and slot ~= "INVTYPE_BAG"
    local equip = Public(info.equipLoc) and "none" or "unknown"
    if equipment then
        equip = "unknown"
        local id = tonumber(link:match("item:(%d+)"))
        if id and C_PlayerInfo and C_PlayerInfo.CanUseItem then
            local usable = C_PlayerInfo.CanUseItem(id)
            if Public(usable) and type(usable) == "boolean" then equip = usable and "usable" or "unusable" end
        end
        local minLevel = PublicValue(info.minLevel)
        local level = type(minLevel) == "number" and UnitLevel and UnitLevel("player")
        if Public(level) and type(level) == "number" and minLevel > level then equip = "unusable" end
    end
    return { name = PublicValue(info.name), texture = PublicValue(info.texture), quality = PublicValue(info.quality),
        type = equipment and PublicValue(info.subType) or PublicValue(info.type), slot = _G[slot or ""] or "", equip = equip,
        classID = Public(info.classID) and type(info.classID) == "number" and info.classID or nil,
        bindType = Public(info.bindType) and info.bindType or nil }
end
local function LookupMethod(frame, name)
    return frame[name]
end
local function OptionalMethod(frame, name)
    local ok, method = pcall(LookupMethod, frame, name)
    return ok and type(method) == "function" and method or nil
end
local function HooksFor(frame)
    local hooks = nativeHooks[frame]
    if not hooks then
        hooks = { isForbidden = OptionalMethod(frame, "IsForbidden") }
        nativeHooks[frame] = hooks
    end
    return hooks
end
local function CanMask(frame)
    local protected = frame:IsProtected()
    if not Public(protected) or protected ~= false then return false end
    local isForbidden = HooksFor(frame).isForbidden
    if not isForbidden then return true end
    local forbidden = isForbidden(frame)
    return Public(forbidden) and forbidden == false
end
local function HookMethod(frame, method, callback)
    local hooks = HooksFor(frame)
    if not hooks[method] then
        if YUI.API.Security.SafeHook("LootRoll:Native:" .. method, frame, method, callback) ~= true then return false end
        hooks[method] = true
    end
    return true
end
local function HookScript(frame, script, callback)
    local hooks = HooksFor(frame)
    if not hooks[script] then
        if frame:HookScript(script, callback) == false then return false end
        hooks[script] = true
    end
    return true
end
local function IsNativeRoot(frame)
    for _, name in ipairs(nativeNames) do
        if _G[name] == frame then return true end
    end
    return false
end
local function IsInNativeTree(frame, root)
    while frame do
        if frame == root then return true end
        frame = frame:GetParent()
    end
    return false
end
-- Keep an already masked, closed slot quiet even if another slot forces fallback.
-- A recycled or still-playable ID must go through normal native ownership again.
local function KeepClosedMask(frame)
    local saved = nativeState[frame]
    local id = frame.rollID
    if not saved or not saved.masked or not IsNativeRoot(frame) or not frame:IsShown()
        or not IsID(id) or id ~= saved.rollID then return false end
    local closed
    if isClosed then closed = isClosed(id) end
    if closed == true or closed == nil and saved.closed then
        local remaining = API.TimeLeft(id)
        local active = remaining == nil and API.ActiveRollSet()
        if remaining == 0 or active and not active[id] then
            saved.closed = true
            return true
        end
    end
    saved.closed = nil
    return false
end
local function ShouldMask(frame)
    local id = frame.rollID
    return frame:IsShown() and IsID(id) and (owns and owns(id) or KeepClosedMask(frame))
end
local function ReadMouse(frame, split)
    local click, motion
    if split then
        click, motion = frame:IsMouseClickEnabled(), frame:IsMouseMotionEnabled()
    else
        click = frame:IsMouseEnabled()
        motion = click
    end
    if Public(click) and type(click) == "boolean" and Public(motion) and type(motion) == "boolean" then
        return click, motion
    end
end
local function RestoreMouse(frame, state)
    local click, motion = ReadMouse(frame, state.split)
    if click == state.click and motion == state.motion then return true end
    if state.click == state.motion then
        frame:EnableMouse(state.click)
    else
        frame:SetMouseClickEnabled(state.click)
        frame:SetMouseMotionEnabled(state.motion)
    end
    click, motion = ReadMouse(frame, state.split)
    return click == state.click and motion == state.motion
end
local function ForgetMouse(frame, state)
    nativeMouse[frame] = nil
    nativeState[state.root].mouse[frame] = nil
end
local function TryRestoreMouse(frame, state)
    local ok, restored = pcall(RestoreMouse, frame, state)
    if not ok or not restored then return false end
    ForgetMouse(frame, state)
    return true
end
local function SetNativeAlpha(frame, alpha)
    frame:SetAlpha(alpha)
    local actual = frame:GetAlpha()
    return Public(actual) and actual == alpha
end
local function RestoreAlpha(frame, alpha)
    local current = frame:GetAlpha()
    return not Public(current) or current == alpha or SetNativeAlpha(frame, alpha)
end
local function RestoreNative(frame)
    local saved = nativeState[frame]
    if not saved then return true end
    if saved.alpha ~= nil then
        local ok, restored = pcall(RestoreAlpha, frame, saved.alpha)
        if ok and restored then saved.alpha = nil end
    end
    for child, state in pairs(saved.mouse) do TryRestoreMouse(child, state) end
    if saved.alpha ~= nil or next(saved.mouse) then return false end
    nativeState[frame] = nil
    return true
end
function API.Release(keepClosed)
    local wasUpdating = updating
    updating = true
    owns, lostCallback = nil, nil
    local restored = true
    for frame in pairs(nativeState) do
        local ok, keep = false, false
        if keepClosed then ok, keep = pcall(KeepClosedMask, frame) end
        if not (ok and keep) and not RestoreNative(frame) then restored = false end
    end
    isClosed, updating = nil, wasUpdating
    return restored
end
local function RunNativeUpdate(update, ...)
    updating = true
    local ok, result = pcall(update, ...)
    updating = false
    return ok and result == true
end
local function RunNativeHook(update, frame, ...)
    if updating or RunNativeUpdate(update, frame, ...) or not owns then return end
    local notify = lostCallback
    API.Release(true)
    if notify then pcall(notify) end
end
local function MaskMouse(frame, state, click, motion)
    if not click and not motion then return true end
    if not CanMask(frame) then return false end
    frame:EnableMouse(false)
    local enabledClick, enabledMotion = ReadMouse(frame, state.split)
    return enabledClick == false and enabledMotion == false
end
local function RefreshNativeMouse(frame)
    local state = nativeMouse[frame]
    if not state then return true end
    local click, motion = ReadMouse(frame, state.split)
    if click == nil then
        ForgetMouse(frame, state)
        return false
    end
    if not IsInNativeTree(frame, state.root) then
        ForgetMouse(frame, state)
        return true
    end
    state.click, state.motion = click, motion
    if API.IsGamepad() then return false end
    if not IsNativeRoot(state.root) or not ShouldMask(state.root) then return RestoreNative(state.root) end
    return MaskMouse(frame, state, click, motion)
end
local function OnNativeMouse(frame)
    if nativeMouse[frame] then RunNativeHook(RefreshNativeMouse, frame) end
end
local function SyncMouseTree(root, frame, saved)
    if not CanMask(frame) or not HookMethod(frame, "EnableMouse", OnNativeMouse) then return false end
    local state = nativeMouse[frame]
    if state and state.root ~= root then
        if not TryRestoreMouse(frame, state) then return false end
        state = nil
    end
    if not state then
        local split = OptionalMethod(frame, "IsMouseClickEnabled") and OptionalMethod(frame, "IsMouseMotionEnabled")
            and OptionalMethod(frame, "SetMouseClickEnabled") and OptionalMethod(frame, "SetMouseMotionEnabled")
        state = { root = root, split = split ~= nil }
    end
    local click, motion = ReadMouse(frame, state.split)
    if click == nil then return false end
    if state.click == nil or click or motion then state.click, state.motion = click, motion end
    saved.mouse[frame], nativeMouse[frame] = state, state
    if not MaskMouse(frame, state, click, motion) then return false end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not SyncMouseTree(root, child, saved) then return false end
    end
    return true
end
local function ReadNativeAlpha(frame, saved, fromHook)
    local alpha = frame:GetAlpha()
    if not Public(alpha) or type(alpha) ~= "number" or alpha < 0 or alpha > 1 or alpha ~= alpha then
        saved.alpha = nil
        return nil
    end
    if fromHook or saved.alpha == nil or alpha ~= 0 then saved.alpha = alpha end
    return alpha
end
local function RefreshNativeAlpha(frame)
    local saved = nativeState[frame]
    local alpha = ReadNativeAlpha(frame, saved, true)
    if alpha == nil or API.IsGamepad() then return false end
    if not IsNativeRoot(frame) or not ShouldMask(frame) then return RestoreNative(frame) end
    return alpha == 0 or CanMask(frame) and SetNativeAlpha(frame, 0)
end
local function OnNativeAlpha(frame)
    if nativeState[frame] then RunNativeHook(RefreshNativeAlpha, frame) end
end
local SyncFrame
local function OnNativeShow(frame)
    if owns or nativeState[frame] then RunNativeHook(SyncFrame, frame) end
end
local function RestoreHiddenFrame(frame)
    return KeepClosedMask(frame) or RestoreNative(frame)
end
local function OnNativeHide(frame)
    if nativeState[frame] then RunNativeHook(RestoreHiddenFrame, frame) end
end
SyncFrame = function(frame)
    if API.IsGamepad() then return false end
    if not IsNativeRoot(frame) then return RestoreNative(frame) end
    if KeepClosedMask(frame) then
        local alpha = ReadNativeAlpha(frame, nativeState[frame], false)
        return alpha == 0 or alpha ~= nil and CanMask(frame) and SetNativeAlpha(frame, 0)
    end
    local saved = nativeState[frame]
    if saved and Public(frame.rollID) and saved.rollID ~= frame.rollID then
        if not RestoreNative(frame) then return false end
        saved = nil
    end
    if not CanMask(frame) or not HookScript(frame, "OnShow", OnNativeShow)
        or not HookScript(frame, "OnHide", OnNativeHide) then return false end
    if not ShouldMask(frame) then return RestoreNative(frame) end
    if not HookMethod(frame, "SetAlpha", OnNativeAlpha) then return false end
    if not saved then
        saved = { mouse = {}, rollID = frame.rollID }
        nativeState[frame] = saved
    end
    local alpha = ReadNativeAlpha(frame, saved, false)
    if alpha == nil or not SyncMouseTree(frame, frame, saved) then return false end
    for child, state in pairs(saved.mouse) do
        if not IsInNativeTree(child, frame) and not TryRestoreMouse(child, state) then return false end
    end
    saved.masked = alpha == 0 or SetNativeAlpha(frame, 0)
    return saved.masked
end
local function SyncFrames()
    local security = YUI.API.Security
    if API.IsGamepad() or not security or type(security.SafeHook) ~= "function" then return false end
    for frame in pairs(nativeState) do
        if not IsNativeRoot(frame) and not RestoreNative(frame) then return false end
    end
    for _, name in ipairs(nativeNames) do
        local frame = _G[name]
        if frame and not SyncFrame(frame) then return false end
    end
    return true
end
function API.SyncNative()
    if not owns or updating then return false end
    if RunNativeUpdate(SyncFrames) then return true end
    API.Release(true)
    return false
end
function API.Acquire(predicate, onLost, closedPredicate)
    if owns or updating or type(predicate) ~= "function" or not API.Release(true) then return false end
    owns, isClosed = predicate, closedPredicate
    if not API.SyncNative() then return false end
    lostCallback = type(onLost) == "function" and onLost or nil
    return true
end
