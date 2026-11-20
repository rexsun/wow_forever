local ADDON_NAME, YUI = ...
YUI = _G.YUI or YUI
if not YUI or not YUI.IsForever or not YUI.Components or not YUI.GUI2 then return end
local bootstrap = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if bootstrap and bootstrap.productEnabled == false then return end
local API, M, View = YUI.API.LootRoll, YUI.LootRollModel, YUI.LootRollView
if not API or not M or not View then return end
local L, Components = YUI.Locale:Get("LootRoll"), YUI.Components
local PRODUCT = YUI:GetAddonProductId(ADDON_NAME, "suite") or "suite"
local KEY, MODULE, LAYOUT = "LootRoll", "component.lootroll", "yui.component.lootroll"
local CLEAR_BOUNDARY_LIMIT = 16
local MIN_WIDTH, MAX_WIDTH = 280, 440
local defaults = { width = MIN_WIDTH, growth = "up", visibleItems = 6 }
local DEFAULT_PLACEMENT = {
    anchor = { point = "BOTTOMRIGHT", relative = "UIParent", relativePoint = "CENTER" },
    offset = { x = -230, y = 195 },
}
local owner = {}
local C = { active = false, nativeTakeover = false, model = M.New(), events = 0, refreshes = 0, listeners = 0, retries = {}, itemDetails = {} }
YUI.LootRoll = C
local function Config()
    local config = Components:EnsureConfig("LootRoll_Config", defaults, PRODUCT)
    if (tonumber(config.layoutVersion) or 0) < 2 then
        if config.width == 400 then config.width = defaults.width end
        config.layoutVersion = 2
    end
    config.width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, tonumber(config.width) or defaults.width))
    config.visibleItems = math.max(3, math.min(12, math.floor(tonumber(config.visibleItems) or 6)))
    if config.growth ~= "up" and config.growth ~= "down" then config.growth = defaults.growth end
    return config
end
local function Store() return YUI.DB:GetGlobal(PRODUCT) end
local function Save() Store().lootRollHistory = M.Snapshot(C.model, 200, GetTime(), GetServerTime(), API.ActiveRollSet()) end
local function SaveClearBoundary(store, boundaries, player, boundary)
    boundaries[player] = boundary
    local others = {}
    for owner, saved in pairs(boundaries) do
        if owner ~= player then
            others[#others + 1] = { player = owner, calendar = type(saved) == "table" and tonumber(saved.calendar) or 0 }
        end
    end
    if #others >= CLEAR_BOUNDARY_LIMIT then
        table.sort(others, function(a, b) return (a.calendar or 0) > (b.calendar or 0) end)
        for index = CLEAR_BOUNDARY_LIMIT, #others do boundaries[others[index].player] = nil end
    end
    store.lootRollClearedBefore = boundaries
end
local function UpdateClearedStamps(store, stamps, clearedThrough)
    local boundaries = type(store.lootRollClearedBefore) == "table" and store.lootRollClearedBefore or {}
    -- 兼容试用版曾写入的单角色边界。
    if type(boundaries.player) == "string" then
        boundaries = { [boundaries.player] = boundaries }
        store.lootRollClearedBefore = boundaries
        store.lootRollClearedCompacted = true
    end
    local player, clock, calendar = API.HistoryOwner(), API.HistoryTime(), GetServerTime()
    local previous = player and boundaries[player]
    local before
    if clock and type(previous) == "table"
        and type(previous.startTime) == "number" and previous.startTime >= 0 and previous.startTime <= clock
        and type(previous.clock) == "number" and type(previous.calendar) == "number"
        and math.abs((clock - previous.clock) - (calendar - previous.calendar) * 1000) <= 2000 then
        before = previous.startTime
    end
    local evictedThrough, trimmed = API.TrimClearedStamps(stamps)
    if trimmed then store.lootRollClearedCompacted = true end
    local through = (clearedThrough or evictedThrough) and math.max(clearedThrough or 0, evictedThrough or 0)
    if through and player and clock and through <= clock then
        before = math.max(before or 0, through)
        SaveClearBoundary(store, boundaries, player, { startTime = before, clock = clock, calendar = calendar })
    end
    C.clearedBefore = store.lootRollClearedCompacted and before or nil
    C.clearedHistory = stamps and next(stamps) and stamps or nil
    store.lootRollClearedStamps = C.clearedHistory
end
local function CancelTimer(key) if C[key] then C[key]:Cancel(); C[key] = nil end end
local function CancelCompletionClock()
    if C.clockForCompletion then CancelTimer("clock"); C.clockForCompletion = nil end
end
local function StopOutputPreview()
    local output = YUI.InfoOutput
    if type(output) == "table" and type(output.StopPreview) == "function" then
        if not pcall(output.StopPreview, output, owner) then C.outputErrors = (C.outputErrors or 0) + 1 end
    end
end
local function ClearOutput()
    StopOutputPreview()
    local output = YUI.InfoOutput
    if type(output) == "table" and type(output.ClearOwner) == "function" then
        if not pcall(output.ClearOwner, output, owner) then C.outputErrors = (C.outputErrors or 0) + 1 end
    end
end
local function Fail()
    C.active, C.nativeTakeover = false, false; YUI.Event:OffOwner(owner); C.listeners = 0
    C.settingsPreview, C.editPreview = false, false
    CancelTimer("pending"); CancelTimer("clock"); API.Release()
    C.nativeRetryAt, C.nativeRetryDelay, C.nativeUnknownSince = nil, nil, nil
    C.model.results = {}
    ClearOutput()
    if C.view then C.view:Hide() end
end
local function PreviewModel()
    local model = M.New()
    local staff = { id = 18842, class = 2, kind = "weapon", slot = "INVTYPE_2HWEAPON", quality = 4 }
    local items = {
        { id = 17103, class = 2, kind = "weapon", slot = "INVTYPE_WEAPONMAINHAND", quality = 4 },
        { id = 14551, class = 4, kind = "armor", slot = "INVTYPE_HAND", quality = 4, bindType = 2 },
        { id = 12363, class = 7, kind = "material", quality = 2, quantity = 4 },
        staff,
        { id = 16252, class = 9, kind = "recipe", quality = 2 },
    }
    local pending = C.config.visibleItems + 2
    local seenAt = GetServerTime()
    local classes = { "MAGE", "WARRIOR", "PRIEST", "HUNTER", "ROGUE" }
    local states = { 4, 0, 3, 5, 4 }
    local digits = {}
    for digit in L["preview.name.digits"]:gmatch("[^,]+") do digits[#digits + 1] = digit end
    for index = 1, pending + 2 do
        local finished = index == pending + 2
        local item = finished and staff or items[(index - 1) % #items + 1]
        local id = item.id
        local link = "item:" .. id
        local details = API.ItemDetails(link)
        details.name = details.name or L["preview.item." .. id]
        details.classID = item.class
        details.type = details.type or L["preview." .. item.kind]
        details.slot = details.slot or _G[item.slot or ""] or ""
        details.equip = item.slot and (item.kind == "armor" and "unusable" or "usable") or "none"
        details.bindType = details.bindType or item.bindType
        local players = {}
        local playerCount = (index == 1 or finished) and 40 or 5
        for p = 1, playerCount do
            local role = (p - 1) % #classes + 1
            local playerName = L["preview.name"]:format(digits[math.floor(p / 10) + 1], digits[p % 10 + 1])
            players[p] = { playerName = playerName, playerClass = classes[role], isSelf = p == 1,
                state = states[role], roll = p == 2 and 86 or (role == 2 or role == 3) and 81 - p or nil }
        end
        local record = { preview = true, serial = -index, rollID = -index, active = index <= pending,
            status = index <= pending and "pending" or index == pending + 1 and "settling" or "complete", selfState = index <= pending and 4 or 0,
            firstSeenAt = seenAt - (pending + 2 - index) * 30, duration = 45, remaining = index == 1 and 6 or 34, details = details,
            data = { link = not finished and link or nil, name = finished and L["preview.output.item"] or details.name,
                texture = details.texture or (YUI.API.Item and YUI.API.Item.GetIcon and YUI.API.Item.GetIcon(link)) or 134400,
                quality = item.quality, quantity = item.quantity or 1, canNeed = true, canGreed = true, canTransmog = index == 1 },
            source = L["preview.source"], drop = { playerRollState = 4, rollInfos = players, currentLeader = players[2] } }
        if index > pending then players[1].state, players[1].roll, record.selfRoll = 0, finished and 98 or 35, finished and 98 or 35 end
        if finished then
            players[2].roll, players[2].isWinner = 72, true
            record.drop.winner, record.drop.playerRollState = players[2], 0
        end
        model.records[index] = record
    end
    return model
end
local function HasLiveQueue(controller)
    local completeUntil = controller.view and controller.view.completeUntil
    if completeUntil and completeUntil > GetTime() then return true end
    for _, record in ipairs(controller.model.records) do
        if not record.bound and not record.restored and not record.hydrated and not M.Terminal(record) then
            return true
        end
    end
    return false
end
function C:GetDisplayModel()
    if self.settingsPreview or self.editPreview then
        if not self.active or not HasLiveQueue(self) then
            if not self.previewModel then self.previewModel = PreviewModel() end
            return self.previewModel, true
        end
    end
    return self.model, false
end
local Render, Announce, ScheduleClock, QueueRender, RecoverActive, Drop
local function NativeLost()
    C.nativeTakeover = false
    QueueRender()
end
local function DeferNative(now)
    C.nativeRetryDelay = math.min(4, (C.nativeRetryDelay or 0.5) * 2)
    C.nativeRetryAt = now + C.nativeRetryDelay
    if C.nativeTakeover then
        API.Release(true)
        NativeLost()
    end
    ScheduleClock()
end
local function UpdateTakeover(retry)
    local gamepad = API.IsGamepad()
    local changed = C.gamepad ~= gamepad
    C.gamepad = gamepad
    if gamepad then
        if C.nativeTakeover then API.Release(); C.nativeTakeover = false end
    elseif not C.nativeTakeover and not C.nativeRetryAt and (retry or changed) then
        C.nativeTakeover = API.Acquire(function(id)
            local r = C.model.rolls[id]
            return C.active and not C.editPreview and r and r.data.name ~= nil
        end, NativeLost, function(id)
            local r = C.model.rolls[id]
            if r then
                return not r.active and (r.nativeClosedAt ~= nil or r.choiceEndedAt ~= nil or M.Terminal(r))
            end
        end) == true
    end
    return changed
end
local function EnsureView()
    C.config = Config()
    if not C.view then C.view = View.New(C, DEFAULT_PLACEMENT) end
    if not C.layoutRegistered and YUI.Layout then
        C.layoutRegistered = YUI.Layout:RegisterFrame(LAYOUT, { frame = C.view.hud, title = L["name"], category = "component", movable = true, snap = true,
            exactMoverBounds = true, getMoverBounds = function() return C.view:GetMoverBounds() end,
            anchorTargets = { "UIParent" }, defaultPlacement = DEFAULT_PLACEMENT,
            isEnabled = function() return C.active or C.settingsPreview or C.editPreview end,
            onEnterEditMode = function() C.editPreview = true; Render() end,
            onExitEditMode = function() C.editPreview = false; if C.view then C.view:CloseHover() end; Render() end,
            openPluginSettings = function() if YUI.Settings then YUI.Settings:OpenComponentFeature(KEY) end end }) ~= false
    end
end
local function PlayOutputSamples(model)
    local records = model.records
    local settled = records[#records]
    local players, samples = settled.drop.rollInfos, { settled }
    for index, item in ipairs({ records[1].data, records[2].data, settled.data }) do
        local long = index == 3
        local player = players[math.random(#players)]
        samples[#samples + 1] = {
            preview = true, status = "complete",
            data = { name = long and L["preview.output.alternate"] or item.name, texture = item.texture, quality = item.quality },
            drop = { winner = { playerName = long and player.playerName or player.playerName:match("%S+$"),
                playerClass = player.playerClass, state = index == 2 and 3 or 0, roll = math.random(1, 100) } },
        }
    end
    for index = #samples, 2, -1 do
        local other = math.random(index)
        samples[index], samples[other] = samples[other], samples[index]
    end
    for _, sample in ipairs(samples) do Announce(sample) end
end
function C:SetPreview(enabled)
    if enabled and self.active and HasLiveQueue(self) then return false end
    if self.settingsPreview == (enabled == true) then return end
    self.settingsPreview = enabled == true
    if self.settingsPreview then self.previewModel = nil; EnsureView() end
    if self.view then self.view:CloseHover(); if self.view.history then self.view.history:Hide() end; self.view:Render() end
    if YUI.Layout and self.layoutRegistered and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(LAYOUT) end
    if self.settingsPreview then
        if self.previewModel then PlayOutputSamples(self.previewModel) end
    else
        StopOutputPreview()
    end
    return true
end
local function RuntimeCall(fn, ...)
    local ok, failure, reason = pcall(fn, ...)
    if not ok then
        Fail()
        C.errors = (C.errors or 0) + 1
        if geterrorhandler then geterrorhandler()(failure) end
    end
    return ok, failure, reason
end
local function Details(record)
    local link = record.data.link
    if not link then return end
    local details = C.itemDetails[link]
    if not details then
        details = API.ItemDetails(link)
        if details.name then
            if (C.itemDetailCount or 0) >= 256 then C.itemDetails, C.itemDetailCount = {}, 0 end
            C.itemDetails[link] = details; C.itemDetailCount = (C.itemDetailCount or 0) + 1
        end
    end
    record.details = details
end
Render = function()
    if not C.active and not C.settingsPreview and not C.editPreview then if C.view then C.view:Hide() end; return end
    C.refreshes = C.refreshes + 1
    if C.nativeTakeover and API.SyncNative() == false then C.nativeTakeover = false end
    C.view:Render()
    local completionDelay = C.view:CompletionDelay(GetTime())
    if completionDelay then ScheduleClock(completionDelay) else CancelCompletionClock() end
    if #C.model.results > 0 then
        local queue = C.model.results; C.model.results = {}
        for _, history in ipairs(queue) do
            Announce(history.bound or history, history)
        end
    end
end
QueueRender = function()
    if not C.active or C.pending then return end
    C.pending = C_Timer.NewTimer(0.03, function() C.pending = nil; RuntimeCall(Render) end)
end
local Tick, ClockBody
local function UpdateRecords(now, silent)
    local changed, again, expired, unknown = M.Tick(C.model, now, API.TimeLeft, API.ActiveRollSet)
    if unknown then
        C.nativeUnknownSince = C.nativeUnknownSince or now
        if C.nativeTakeover and now - C.nativeUnknownSince >= 1 then DeferNative(now) end
    elseif unknown == false then
        C.nativeUnknownSince = nil
    end
    -- 有些结果已能从原生历史读取，但没有及时送到更新事件。
    if expired then
        for _, history in ipairs(expired) do Drop(history.encounterID, history.lootListKey, silent) end
    end
    if changed then M.Reconcile(C.model, now, silent); M.Trim(C.model, 200); QueueRender() end
    return again
end
ScheduleClock = function(completionDelay)
    if not C.active then return end
    local now = GetTime()
    local delay = completionDelay or (C.nativeRetryAt and math.max(0.1, C.nativeRetryAt - now)) or 0.1
    local due = now + delay
    if C.clock then
        if C.clockDue <= due then
            if not completionDelay then C.clockForCompletion = nil end
            return
        end
        if not C.clockForCompletion then completionDelay = nil end
        CancelTimer("clock")
    end
    C.clockDue, C.clockForCompletion = due, completionDelay ~= nil
    C.clock = C_Timer.NewTimer(delay, Tick)
end
local function RetryNative(now)
    if API.IsGamepad() then
        C.nativeRetryAt, C.nativeRetryDelay = nil, nil
        return
    end
    local ids = API.ActiveIDs()
    if not ids then DeferNative(now); return end
    for _, id in ipairs(ids) do
        local record = C.model.rolls[id]
        if not record or record.active then
            if not API.ReadRoll(id) or record and now >= record.deadline and API.TimeLeft(id) == nil then
                DeferNative(now)
                return
            end
        end
    end
    C.nativeRetryAt, C.nativeRetryDelay, C.nativeUnknownSince = nil, nil, nil
    RecoverActive(nil, ids)
    UpdateTakeover(true)
    QueueRender()
end
ClockBody = function()
    local completionOnly = C.clockForCompletion
    C.clock, C.clockForCompletion = nil, nil
    if not C.active then return end
    local now = GetTime()
    local wasComplete = C.view.completeUntil
    local completionDelay = C.view:TickCompletion(now)
    if wasComplete and not completionDelay and (C.settingsPreview or C.editPreview) then QueueRender() end
    if completionOnly then
        if completionDelay then ScheduleClock(completionDelay) end
        return
    end
    local again = UpdateRecords(now)
    if C.nativeRetryAt and now >= C.nativeRetryAt then
        if #M.Pending(C.model) > 0 then RetryNative(now)
        else C.nativeRetryAt, C.nativeRetryDelay = nil, nil end
    end
    C.view:Tick()
    local retry = false
    for record, attempts in pairs(C.retries) do
        if now >= attempts.nextAt then
            if attempts.count >= 5 or not record.active or C.model.rolls[record.rollID] ~= record then C.retries[record] = nil
            else
                attempts.count, attempts.nextAt = attempts.count + 1, now + 1
                local data = API.ReadRoll(record.rollID)
                if data and data.name and data.link then M.RefreshRoll(C.model, record, data); Details(record); C.retries[record] = nil; M.Reconcile(C.model, now); QueueRender() end
            end
        end
        retry = true
    end
    if again or retry or C.nativeRetryAt then ScheduleClock() end
    if completionDelay then ScheduleClock(completionDelay) end
end
Tick = function() RuntimeCall(ClockBody) end
local function Start(id, milliseconds, resumed, defer)
    if C.settingsPreview then C:SetPreview(false) end
    local data = API.ReadRoll(id)
    local duration = API.Duration(id, milliseconds) or 60
    local remaining = API.TimeLeft(id)
    if remaining and (remaining > duration or remaining == 0 and not resumed) then remaining = nil end
    local historyNow = remaining and remaining > 0 and API.HistoryTime()
    local r = M.Start(C.model, id, data, GetTime(), GetServerTime(), duration, remaining, resumed,
        historyNow and historyNow + remaining * 1000 or nil)
    r.groupSize = r.groupSize or API.GroupSize()
    Details(r)
    if not data or not data.name or not data.link then C.retries[r] = { count = 0, nextAt = GetTime() + 1 } end
    if not defer then
        M.Reconcile(C.model, GetTime())
        ScheduleClock(); QueueRender()
        if C.nativeTakeover and API.SyncNative() == false then C.nativeTakeover = false end
    end
end
RecoverActive = function(silent, ids)
    local now = GetTime()
    ids = ids or API.ActiveIDs()
    local active = ids and API.ActiveRollSet(ids)
    if active then
        M.SyncActive(C.model, active, now)
        for _, id in ipairs(ids) do Start(id, nil, true, true) end
    end
    M.Reconcile(C.model, now, silent)
    local needsClock = UpdateRecords(now, silent)
    if needsClock or next(C.retries) then ScheduleClock() end
end
local function ColoredText(text, r, g, b)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end
local function ColoredName(text, color)
    return color and ColoredText(text, color.r, color.g, color.b) or text
end
local resultColor = { 0.30, 0.90, 0.38 }

Announce = function(record, history)
    local output, drop = YUI.InfoOutput, record.drop
    if type(output) ~= "table" or not drop or record.status ~= "complete" then return end
    local publish = output.Push
    if record.preview then publish = output.PlayPreviewMessage end
    if type(publish) ~= "function" then return end
    local details = record.details or {}
    local item = record.data.link
    if not item or not item:find("|Hitem:", 1, true) then
        local name = record.data.name or details.name or L["item.loading"]
        item = ColoredName("[" .. name .. "]", ITEM_QUALITY_COLORS[record.data.quality or details.quality or 1])
    end
    local iconBefore = item
    if (record.data.quantity or 1) > 1 then item = item .. " ×" .. record.data.quantity end
    local text
    if drop.winner then
        local winner = drop.winner
        local name = ColoredName(winner.playerName or "—", RAID_CLASS_COLORS[winner.playerClass])
        local score = winner.roll and L["output.score"]:format(winner.roll) or L["output.noScore"]
        local choice, tint = View.ChoicePresentation(winner.state)
        if tint then
            local label = ColoredText(L["choice." .. choice], YUI.GUI2:GetColor(tint))
            text = L["output.wonWithChoice"]:format(name, item, score, label)
        else
            text = L["output.won"]:format(name, item, score)
        end
    elseif drop.allPassed then text = L["output.allPassed"]:format(item) end
    if text then
        local priority = drop.winner and drop.winner.isSelf and "important" or "normal"
        local icon = record.data.texture or details.texture
        local itemAPI = YUI.API.Item
        if not icon and itemAPI and itemAPI.GetIcon then icon = itemAPI.GetIcon(record.data.link) end
        local ok, accepted, reason = pcall(publish, output, owner, text, {
            key = history and "lootroll:" .. history.generation .. ":" .. history.serial or nil,
            priority = priority,
            icon = icon,
            iconBefore = iconBefore,
            color = drop.winner and resultColor or nil,
        })
        if not ok then
            if history then history.outputFailed = true end
            C.outputErrors = (C.outputErrors or 0) + 1
        elseif history and accepted == false and reason ~= "duplicate" and reason ~= "disabled" then
            C.outputRejected = (C.outputRejected or 0) + 1
        end
    end
end
Drop = function(encounter, key, hydrated, defer, raw)
    local drop, source, stamp = API.ReadDrop(encounter, key, raw)
    if not drop or (stamp and C.clearedHistory and C.clearedHistory[stamp]) then return end
    local now = GetTime()
    local withdrew
    local ownChoice = drop.playerRollState and drop.playerRollState ~= 4
    if not hydrated and (ownChoice or drop.winner or drop.allPassed or drop.rosterAllPassed) and M.HasRollForDrop(C.model, drop) then
        withdrew = M.SyncActive(C.model, API.ActiveRollSet(), now)
    end
    local record, changed
    if not (stamp and C.clearedBefore and drop.startTime <= C.clearedBefore)
        or M.KeepResultDuringClear(C.model, encounter, key, drop, now) then
        record, changed = M.Drop(C.model, encounter, key, drop, source, now, GetServerTime(), hydrated, defer)
    end
    if not changed and not withdrew then return end
    if withdrew and not defer then M.Reconcile(C.model, now) end
    if record then Details(record) end
    if not defer then M.Trim(C.model, 200); ScheduleClock(); QueueRender() end
    return true
end
local function Encounter(id, hydrated)
    local changed
    for _, drop in ipairs(API.EncounterDrops(id)) do
        local key = API.HistoryID(drop, "lootListKey")
        if key and Drop(id, key, hydrated, true, drop) then changed = true end
    end
    if changed and not hydrated then
        M.Reconcile(C.model, GetTime())
        M.Trim(C.model, 200); ScheduleClock(); QueueRender()
    end
end
local function RefreshChoice(record)
    if not C.active or not C.nativeTakeover or not record or not record.active or C.model.rolls[record.rollID] ~= record then return end
    local data, previous = API.ReadRoll(record.rollID), record.data
    if not data then return end
    if previous.link and M.Identity(data.link) ~= M.Identity(previous.link) then return end
    if data.canNeed ~= previous.canNeed or data.canGreed ~= previous.canGreed or data.canTransmog ~= previous.canTransmog
        or data.reasonNeed ~= previous.reasonNeed or data.reasonGreed ~= previous.reasonGreed or data.link ~= previous.link then
        M.RefreshRoll(C.model, record, data); Details(record); M.Reconcile(C.model, GetTime()); QueueRender()
    end
    return data
end
function C:RefreshChoice(record)
    local ok, data = RuntimeCall(RefreshChoice, record)
    if ok then return data end
end
local function NativeChoiceClosed(record, now)
    if M.Cancel(C.model, record.rollID, now) then M.Reconcile(C.model, now) end
    QueueRender(); ScheduleClock()
end
function C:Choose(record, choice)
    if record.preview or not record.active or self.editPreview or not self.nativeTakeover
        or self.model.rolls[record.rollID] ~= record or API.IsConfirming() then return false end
    local now = GetTime()
    if now >= record.deadline and API.TimeLeft(record.rollID) == 0 then return false end
    local wasAllowed = API.Allowed(record.data, choice)
    local data = self:RefreshChoice(record)
    if not data then
        if self.nativeTakeover then
            local rolls = API.ActiveRollSet()
            if rolls and not rolls[record.rollID] then NativeChoiceClosed(record, now)
            else DeferNative(now) end
        end
        return false
    end
    if not wasAllowed or not API.Allowed(data, choice) then return false end
    if not M.Request(self.model, record, choice, now) then return false end
    local callOK, accepted, reason = RuntimeCall(API.Request, record.rollID, choice, data)
    if callOK and not accepted then record.request, record.requestUntil = nil, nil end
    if reason == "native-unavailable" then DeferNative(now) end
    if reason == "native-closed" then NativeChoiceClosed(record, now); return false end
    -- 请求发出不等于选择成功；等待服务器状态/原生撤下，取消确认后仍可重选。
    QueueRender(); ScheduleClock()
    return callOK and accepted
end
local function EventBody(event, a, b, c)
    if not C.active then return end
    C.events = C.events + 1
    if event == "START_LOOT_ROLL" then UpdateTakeover(true); Start(a, b)
    elseif event == "CANCEL_LOOT_ROLL" then
        local now = GetTime()
        if M.Cancel(C.model, a, now) then M.Reconcile(C.model, now); QueueRender() end
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        local now = GetTime()
        for id in pairs(C.model.rolls) do M.Cancel(C.model, id, now) end
        M.Reconcile(C.model, now)
        QueueRender()
    elseif event == "MAIN_SPEC_NEED_ROLL" then
        local now = GetTime()
        if M.Accept(C.model, a, 0, b, now) then M.Reconcile(C.model, now); QueueRender() end
    elseif event == "CONFIRM_LOOT_ROLL" then
        local record = M.ConfirmPending(C.model, a)
        C.view:YieldToConfirmation(record)
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then Drop(a, b)
    elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then Encounter(a)
    elseif event == "LOOT_HISTORY_CLEAR_HISTORY" then
        M.Clear(C.model, GetTime(), API.ActiveRollSet()); ClearOutput(); RecoverActive(); QueueRender()
    elseif event == "GET_ITEM_INFO_RECEIVED" and b then
        if C.settingsPreview or C.editPreview then C.previewModel = nil end
        for _, r in ipairs(C.model.records) do
            if r.data.link and tonumber(r.data.link:match("item:(%d+)")) == a then C.itemDetails[r.data.link] = nil; Details(r) end
        end
        QueueRender()
    elseif event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" then
        C.itemDetails, C.itemDetailCount = {}, 0; for _, r in ipairs(C.model.records) do Details(r) end; QueueRender()
    elseif event == "PLAYER_LOGOUT" then Save()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local store = Store()
        if store.lootRollClearedBefore then UpdateClearedStamps(store, C.clearedHistory) end
        UpdateTakeover(true); RecoverActive(); QueueRender()
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        if UpdateTakeover(false) then RecoverActive(); QueueRender() end
    end
end
local function OnEvent(event, a, b, c) RuntimeCall(EventBody, event, a, b, c) end
local events = { "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "MAIN_SPEC_NEED_ROLL", "CONFIRM_LOOT_ROLL",
    "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION" }
local function Toggle(enabled)
    YUI.Event:OffOwner(owner); C.listeners = 0
    CancelTimer("pending"); CancelTimer("clock")
    C.nativeRetryAt, C.nativeRetryDelay, C.nativeUnknownSince = nil, nil, nil
    C.model.results = {}
    ClearOutput()
    if C.active then Save() end
    C.active, C.nativeTakeover = false, false; API.Release()
    C.settingsPreview, C.editPreview = false, false
    if C.view then C.view:Hide() end
    if YUI.Layout and C.layoutRegistered and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(LAYOUT) end
    C.retries, C.itemDetails, C.itemDetailCount = {}, {}, 0
    if not enabled or not API.Available() then return end
    EnsureView()
    local store = Store()
    UpdateClearedStamps(store, type(store.lootRollClearedStamps) == "table" and store.lootRollClearedStamps or nil)
    if not C.restored then M.Restore(C.model, store.lootRollHistory, GetTime(), GetServerTime()); C.restored = true end
    C.active = true
    UpdateTakeover(true)
    if YUI.Layout and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(LAYOUT) end
    -- 先读原生历史，再批量恢复活动 ID，最后检查是否能唯一关联。
    for _, info in ipairs(API.AllEncounters()) do
        local id = API.HistoryID(info, "encounterID")
        if id then Encounter(id, true) end
    end
    M.Trim(C.model, 200)
    RecoverActive(true)
    for _, event in ipairs(events) do YUI.Event:On(event, OnEvent, owner); C.listeners = C.listeners + 1 end
    CancelTimer("pending")
    Render()
end
function C:OpenHistory()
    if API.IsConfirming() or not self.active and not self.settingsPreview and not self.editPreview then return false end
    local model, preview = self:GetDisplayModel()
    if not preview then
        for _, record in ipairs(model.records) do
            if record.restored and not record.details and not record.bound then Details(record) end
        end
    end
    self.view:OpenHistory(); return true
end
function C:ClearHistory()
    local store = Store()
    if type(store) ~= "table" then return false end

    local previous = type(store.lootRollClearedStamps) == "table" and store.lootRollClearedStamps or nil
    local now = GetTime()
    local stamps, through = API.ClearedHistoryStamps(previous, function(encounter, key, raw)
        local drop = API.ReadDrop(encounter, key, raw)
        return drop and M.KeepResultDuringClear(self.model, encounter, key, drop, now)
    end)
    local function Remember(record)
        local stamp = API.StampFromIdentity(record.nativeIdentity)
        if stamp then stamps[stamp] = true end
    end
    local snapshot = store.lootRollHistory
    if type(snapshot) == "table" and type(snapshot.records) == "table" then
        for _, record in ipairs(snapshot.records) do
            -- An earlier save can contain an unavailable copy of an active roll.
            if type(record) == "table" and (record.status == "complete" or record.unresolved == false) then Remember(record) end
        end
    end
    M.RemoveFinished(self.model, function(record)
        if not (record.restored and record.status == "unavailable" and record.unresolved == true) then Remember(record) end
        self.retries[record] = nil
    end)
    -- A final native update may already be readable while its event is still pending.
    -- Let records kept by the model receive that update.
    for _, record in ipairs(self.model.records) do
        local stamp = API.StampFromIdentity(record.nativeIdentity)
        if stamp and not (previous and previous[stamp]) then stamps[stamp] = nil end
    end
    self.model.results = {}; ClearOutput()
    UpdateClearedStamps(store, stamps, through)
    store.lootRollHistory = nil
    if self.view then
        CancelCompletionClock()
        self.view:ResetCompletion()
        self.view.page = 1
        self.view:CloseHover()
        self.view:Render()
    end
    return true
end
function C:ConfirmClearHistory()
    local settings = YUI.Settings
    local history = self.view and self.view.history
    if API.IsConfirming() or not settings or not settings.ShowConfirmPopup or not history or not history:IsShown() then return false end
    self.view:CloseHover()
    local model, preview = self:GetDisplayModel()
    settings:ShowConfirmPopup(L[preview and "history.clearPreviewConfirm" or "history.clearConfirm"], function()
        local current, currentPreview = self:GetDisplayModel()
        if API.IsConfirming() or not history:IsShown() or current ~= model or currentPreview ~= preview then return end
        if preview then
            M.RemoveFinished(model)
            self.view.page = 1
            self.view:CloseHover()
            self.view:Render()
        else
            self:ClearHistory()
        end
    end, { titleText = L["history.clear"], acceptTone = "danger", ownerFrame = history,
        dismissWithOwner = true, frameStrata = "TOOLTIP" })
    return true
end
function C:GetStats()
    return { active = self.active, listeners = self.listeners, pending = self.pending ~= nil,
        timers = (self.pending and 1 or 0) + (self.clock and 1 or 0) + (self.view and self.view.closeTimer and 1 or 0),
        clock = self.clock ~= nil, idleTickers = 0, events = self.events, refreshes = self.refreshes,
        records = #self.model.records, hudRows = self.view and #self.view.rows or 0, hudCapacity = self.config and self.config.visibleItems or 6,
        hudPool = self.view and #self.view.rowPool or 0, animations = self.view and self.view:GetAnimationCount() or 0,
        outputErrors = self.outputErrors or 0, outputRejected = self.outputRejected or 0,
        pendingOutputs = #self.model.results,
        generation = self.model.generation, errors = self.errors or 0,
        preview = self.settingsPreview == true, editing = self.editPreview == true }
end
local function Enable()
    local ok, failure = pcall(Toggle, true)
    if not ok then
        Fail()
        error(failure)
    end
end
local Feature = { id = KEY, name = L["name"], description = L["description"], default = true,
    settingsMode = "inline", product = PRODUCT, storageKey = KEY, toolboxManaged = true,
    usesInfoOutput = true,
    sourceRoot = "Components\\LootRoll", versions = { "forever" }, tags = { "实用功能" }, order = 308,
    assetFolders = { "Components\\LootRoll\\Media" }, modSwitchImage = "modswitch\\lootroll-bg.png", modSwitchImageCrop = false,
    callback = function(enabled) if enabled then YUI.Module:Enable(MODULE) else YUI.Module:Disable(MODULE) end end }
function Feature:GetSettingsTitleAction()
    return { getText = function() return L[C.settingsPreview and "preview.stop" or "preview.start"] end,
        onClick = function() C:SetPreview(not C.settingsPreview) end }
end
function Feature:OnSettingsLeave() C:SetPreview(false) end
function Feature:GetOptions()
    local function Field(kind, key, extra)
        local f = extra or {}; f.type, f.label = kind, L["setting." .. key]
        f.get = function() return Config()[key] end
        f.set = function(value)
            Config()[key] = value; C.config = Config()
            if key == "visibleItems" then C.previewModel = nil end
            if C.active or C.settingsPreview or C.editPreview then Render() end
            if YUI.Layout and C.layoutRegistered and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(LAYOUT) end
        end
        return f
    end
    local options = {
        Field("slider", "width", { min = MIN_WIDTH, max = MAX_WIDTH, step = 4 }),
        Field("slider", "visibleItems", { min = 3, max = 12, step = 1 }),
        Field("dropdown", "growth", { options = { { text = L["growth.down"], value = "down" }, { text = L["growth.up"], value = "up" } } }),
        { type = "button", label = L["history.title"], onClick = function() C:OpenHistory() end },
    }
    local output = YUI.InfoOutput
    if output and output.OpenSettings then
        options[#options + 1] = { type = "button", label = YUI.Locale:Get("Core")["info_output.name"], width = 160,
            onClick = function() output:OpenSettings() end }
    end
    return options
end
function Feature:GetStats() return C:GetStats() end
YUI.Module:Register({ id = MODULE, owner = owner, product = PRODUCT,
    dependencies = { "core.db", "core.event", "core.locale", "core.api" },
    getEnabled = function() return Components:IsEnabled(KEY) end,
    OnEnable = Enable, OnDisable = function() Toggle(false) end,
    OnProfileChanged = function() Toggle(false); C.model = M.New(); C.restored = false; if Components:IsEnabled(KEY) then Enable() end end })
Components:RegisterFeature(KEY, Feature)
