local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI or not YUI.IsForever then return end

-- 活动 rollID 与历史组合键分属两个编号域，模型不推测它们相等。
local M = {}
YUI.LootRollModel = M
local ACTIVE_CHECK_INTERVAL, RESULT_GRACE = 0.5, 10
local ASSOCIATION_WINDOW, ZERO_TIME_RESUME_WINDOW = 12, 30
local FINISHED_LIMIT = 1024
local function Identity(link)
    return type(link) == "string" and (link:match("(item:[^|]+)") or link) or nil
end
M.Identity = Identity
local function Terminal(record)
    return record.status == "complete" or record.status == "unavailable"
end
M.Terminal = Terminal
function M.New()
    return { generation = 1, serial = 0, rolls = {}, drops = {}, dropSlots = {}, records = {},
        finished = {}, finishedOrder = {}, finishedHead = 0, results = {}, revision = 0 }
end
local function Touch(model) model.revision = model.revision + 1 end
local function Insert(model, record)
    model.serial = model.serial + 1
    record.serial, record.generation = model.serial, model.generation
    model.records[#model.records + 1] = record
    Touch(model)
    return record
end
-- 原生历史时钟、起始时间和时长都是毫秒，本地队列倒计时是秒。
local function TimingMatches(record, drop)
    if not (record.historyDeadline and drop.startTime and drop.duration) then return nil end
    return math.abs(drop.duration - record.duration * 1000) <= 1000
        and math.abs(drop.startTime + drop.duration - record.historyDeadline) <= 2000
end
local Detach
local function MarkOverlap(record)
    record.overlapping = true
    if not record.history or TimingMatches(record, record.history.drop) ~= true then
        record.ambiguous = true
        Detach(record)
    end
end
local function CheckDuplicates(model, record)
    local identity = Identity(record.data.link)
    if not identity or record.status == "complete" then return end
    for _, other in ipairs(model.records) do
        if other ~= record and other.rollID and not Terminal(other)
            and (other.active or record.started <= (other.nativeClosedAt or other.deadline) + ASSOCIATION_WINDOW)
            and (record.active or other.started <= (record.nativeClosedAt or record.deadline) + ASSOCIATION_WINDOW)
            and Identity(other.data.link) == identity then
            MarkOverlap(other)
            MarkOverlap(record)
        end
    end
end
function M.Start(model, id, data, now, calendar, duration, remaining, resumed, historyDeadline)
    local old = model.rolls[id]
    local sameItem = not old or not data or not data.link or not old.data.link or Identity(data.link) == Identity(old.data.link)
    local newWindow = old and not resumed and remaining and now + remaining > old.deadline + 2
    if old and sameItem and resumed and old.choiceEndedAt and remaining == 0 then return old end
    if old and sameItem and not newWindow and not old.nativeClosedAt and not old.expired and (old.active or resumed) then
        old.historyDeadline = old.historyDeadline or historyDeadline
        return old
    end
    if old and not old.nativeClosedAt then
        old.nativeClosedAt, old.active = now, false
        if not Terminal(old) then old.status, old.withdrawnAt = "settling", now end
    end
    local record = Insert(model, { rollID = id, active = true, status = "pending",
        started = now, firstSeenAt = calendar, duration = duration or 60,
        deadline = now + (remaining or duration or 60), data = data or {}, selfState = 4,
        resumed = resumed, historyDeadline = historyDeadline, resumedAtZero = resumed and remaining == 0 })
    model.rolls[id] = record
    -- 同款 Roll 重叠后，继续等待能区分实例的时序证据。
    CheckDuplicates(model, record)
    return record
end
function M.RefreshRoll(model, record, data)
    if not record or model.rolls[record.rollID] ~= record then return end
    record.data = data or record.data
    CheckDuplicates(model, record)
    Touch(model)
end
function M.Request(model, record, choice, now)
    if not record or not record.active or record.selfState ~= 4 or record.requestUntil and record.requestUntil > now then return false end
    record.request, record.requestUntil = choice, now + 0.5
    Touch(model)
    return true
end
function M.ConfirmPending(model, id)
    local r = model.rolls[id]
    if not r or not r.active or r.selfState ~= 4 then return nil end
    if not r.confirming then r.confirming = true; Touch(model) end
    return r
end
local function Withdraw(record, now)
    if record.active then record.withdrawnAt = now end
    record.active, record.confirming = false, false
end
local function CloseNative(record, now)
    record.nativeClosedAt = record.nativeClosedAt or now or record.started
    Withdraw(record, now or record.nativeClosedAt)
end
function M.Accept(model, id, state, roll, now)
    local r = model.rolls[id]
    if not r or r.nativeSelfState == state and r.nativeSelfRoll == roll then return false end
    r.nativeSelfState, r.nativeSelfRoll = state, roll
    CloseNative(r, now)
    if r.selfState == 4 or not Terminal(r) then r.selfState, r.selfRoll = state, roll end
    if not Terminal(r) then r.status = "settling" end
    Touch(model)
    return true
end
function M.Cancel(model, id, now)
    local r = model.rolls[id]
    if not r or r.nativeClosedAt then return false end
    local visible = r.active or r.confirming
    CloseNative(r, now)
    if not visible then return false end
    if not Terminal(r) then r.status = "settling" end
    -- CANCEL 只证明原生条目撤下，不能证明全员放弃或某个请求已被接受。
    Touch(model)
    return true
end
function M.SyncActive(model, activeRolls, now)
    if not activeRolls then return false end
    local changed = false
    for id in pairs(model.rolls) do
        if not activeRolls[id] and M.Cancel(model, id, now) then changed = true end
    end
    return changed
end
Detach = function(record)
    local history = record.history
    if not history then return end
    history.bound = nil
    record.history, record.historyKey, record.drop, record.source = nil, nil, nil, nil
    record.nativeIdentity, record.historySeenAt = nil, nil
    record.selfState, record.selfRoll = record.nativeSelfState or 4, record.nativeSelfRoll
    record.active = not record.nativeClosedAt and not record.choiceEndedAt and not record.expired
    record.withdrawnAt = record.choiceEndedAt or record.nativeClosedAt
    record.status = record.active and "pending" or record.expired and "unavailable" or "settling"
end
local function CompletePassRoster(record, drop)
    return drop.rosterAllPassed and record.groupSize == #drop.rollInfos
end
local function NormalizeAllPassed(record, drop)
    if drop.allPassed or drop.winner or drop.currentLeader then return end
    -- 已关联的完整队伍名单可以补足缺失的终态标记，同一原生掉落实例可以恢复已保存的终态。
    local savedResult = record.nativeIdentity and record.nativeIdentity == drop.nativeIdentity
        and record.drop and record.drop.allPassed
    if CompletePassRoster(record, drop) or savedResult then drop.allPassed = true end
end
local function MarkFinal(model, history, silent)
    local item = Identity(history.drop.itemHyperlink)
    local stamp = history.nativeIdentity or item
    local previous = model.finished[history.key]
    local first = not history.finalSeen and (not previous or previous.stamp ~= stamp)
    if not previous or previous.stamp ~= stamp then
        local head = model.finishedHead % FINISHED_LIMIT + 1
        local old = model.finishedOrder[head]
        if old then
            if model.finished[old.key] == old then model.finished[old.key] = nil end
            if model.finished[old.slot] == old then model.finished[old.slot] = nil end
            if old.startTime then model.finishedBefore = math.max(model.finishedBefore or 0, old.startTime) end
        end
        previous = { key = history.key, slot = history.slot, stamp = stamp, item = item, startTime = history.drop.startTime }
        model.finished[history.key], model.finishedOrder[head], model.finishedHead = previous, previous, head
    end
    if history.drop.startTime then model.lastFinishedStart = math.max(model.lastFinishedStart or 0, history.drop.startTime) end
    if model.dropSlots[history.slot] == history then model.finished[history.slot] = previous end
    history.finalSeen = true
    if history.publishable and not silent and (first or history.outputFailed) then
        history.outputFailed = nil
        model.results[#model.results + 1] = history
    end
end
local function ApplyOwnChoice(record, state, roll)
    if not state or (state == 4 and record.selfState and record.selfState ~= 4) then return end
    record.selfState = state
    record.selfRoll = roll or (state == record.nativeSelfState and record.nativeSelfRoll) or nil
end
local function UnlinkRoster(record)
    if record and record.rosterHistory then
        record.rosterHistory.rosterRoll = nil
        record.rosterHistory = nil
    end
end
local function ApplyDrop(model, target, history, now, silent)
    local drop = history.drop
    NormalizeAllPassed(target, drop)
    target.historyKey, target.drop, target.source, target.nativeIdentity = history.key, drop, history.source, history.nativeIdentity
    target.historySeenAt = history.firstSeenAt
    local state, roll = drop.playerRollState
    for _, p in ipairs(drop.rollInfos or {}) do
        if p.isSelf then
            if p.state ~= 4 or not state then state, roll = p.state, p.roll end
            break
        end
    end
    ApplyOwnChoice(history, state, roll)
    if history ~= target then ApplyOwnChoice(target, state, roll) end
    target.selfState = target.selfState or 4
    if target.selfState ~= 4 then Withdraw(target, now) end
    if drop.winner or drop.allPassed then
        Withdraw(target, now)
        target.status, history.status = "complete", "complete"
        target.expired = nil
        -- 去重跟随历史掉落实例，列表淘汰和重新关联不会生成第二条播报。
        MarkFinal(model, history, silent)
    elseif target.expired then target.status = "unavailable"
    elseif target.active then target.status = "pending"
    else target.status = "settling" end
    if history ~= target then
        UnlinkRoster(target)
        UnlinkRoster(history.rosterRoll)
        history.bound, target.history = target, history
    end
    Touch(model)
end
local function HasResumeIdentity(record, history)
    if history.resumeRollID == record.rollID and type(history.resumeUntil) == "number" and history.nativeIdentity then
        local grace = record.resumedAtZero and not history.resumeAtZero and ZERO_TIME_RESUME_WINDOW or 0
        if (not history.resumeAtZero or record.resumedAtZero) and record.firstSeenAt <= history.resumeUntil + grace then return true end
    end
    return false
end
local function CanBind(record, history, timed)
    local final = history.drop.winner or history.drop.allPassed
    if timed == false or record.overlapping and not timed then return false end
    if record.history == history then return true end
    if record.expired then return final and timed == true and not record.active end
    if record.resumed then return (not final or record.nativeClosedAt or record.choiceEndedAt) and (timed or HasResumeIdentity(record, history)) end
    if history.baseline or history.hydrated then return false end
    if final or CompletePassRoster(record, history.drop) and record.nativeClosedAt then
        -- 首份终态必须有独立的撤下证据，旧终态也不能吞掉新开的同款。
        return record.nativeClosedAt and (timed or history.serial > record.serial
            and math.abs(record.nativeClosedAt - history.seen) <= ASSOCIATION_WINDOW)
    end
    return timed or math.abs(record.started - history.seen) <= ASSOCIATION_WINDOW
end
local function FindResumedRoll(candidates, history)
    if #candidates < 2 or not history.resumeRollID then return end
    for _, record in ipairs(candidates) do
        if record.resumed and HasResumeIdentity(record, history) and TimingMatches(record, history.drop) then
            return record
        end
    end
end
local function NeedsRoster(record)
    return record.active and record.overlapping and not record.resumed and not record.history and not record.rosterHistory
end
local function PairRosters(model, byItem)
    local unpaired
    for _, record in pairs(model.rolls) do
        if NeedsRoster(record) then unpaired = true; break end
    end
    if not unpaired then return false end
    local changed = false
    -- records 按首次观察顺序排列。以最早的可用 Roll 展示名单，结果和投票仍使用各自的原生身份。
    for _, history in ipairs(model.records) do
        if history.key and history.nativeIdentity and not history.bound and not history.rosterRoll
            and not history.baseline and not Terminal(history) then
            local candidates = byItem[Identity(history.drop.itemHyperlink)]
            local first
            if candidates then
                for _, record in ipairs(candidates) do
                    if NeedsRoster(record) and (not first or record.rollID < first.rollID) and TimingMatches(record, history.drop) then
                        first = record
                    end
                end
            end
            if first then
                first.rosterHistory, history.rosterRoll = history, first
                changed = true
            end
        end
    end
    return changed
end
function M.Reconcile(model, now, silent)
    local byItem, matches = {}, {}
    local identityMatches
    for _, record in pairs(model.rolls) do
        local link = record.status ~= "complete" and Identity(record.data.link)
        if link then
            local candidates = byItem[link]
            if not candidates then candidates = {}; byItem[link] = candidates end
            candidates[#candidates + 1] = record
        end
    end
    if next(byItem) then
        for _, history in pairs(model.drops) do
            local candidates = (not history.bound or history.bound.status ~= "complete") and byItem[Identity(history.drop.itemHyperlink)]
            if candidates then
                local exact = FindResumedRoll(candidates, history)
                if exact then
                    if CanBind(exact, history, true) then
                        identityMatches = identityMatches or {}
                        identityMatches[exact] = identityMatches[exact] == nil and history or false
                    end
                else
                    local count = 0
                    for _, r in ipairs(candidates) do
                        local timed = TimingMatches(r, history.drop)
                        if CanBind(r, history, timed) then
                            count = count + 1
                            if matches[r] == nil then matches[r] = history else matches[r] = false end
                        elseif r.overlapping and (timed or timed == nil and history.seen >= r.started - ASSOCIATION_WINDOW
                            and history.seen <= (r.nativeClosedAt or r.deadline) + ASSOCIATION_WINDOW) then
                            -- 仍可能是这件；可见性或先收到撤下事件不能代替身份。
                            count = count + 1
                        end
                    end
                    if count > 1 then
                        for _, r in ipairs(candidates) do if matches[r] == history then matches[r] = false end end
                    end
                end
            end
        end
    end
    if identityMatches then
        for record, history in pairs(identityMatches) do matches[record] = history end
    end
    local changed = false
    for _, candidates in pairs(byItem) do
        for _, candidate in ipairs(candidates) do
            if candidate.history and candidate.history ~= matches[candidate] then
                Detach(candidate)
                Touch(model)
                changed = true
            end
            local ambiguous = candidate.overlapping and not matches[candidate] and true or nil
            if candidate.ambiguous ~= ambiguous then
                candidate.ambiguous = ambiguous
                Touch(model)
                changed = true
            end
        end
    end
    for candidate, history in pairs(matches) do
        if history and not history.bound then
            ApplyDrop(model, candidate, history, now, silent)
            changed = true
        end
    end
    if next(byItem) and PairRosters(model, byItem) then Touch(model); changed = true end
    if model.deferredUpdates then
        for history in pairs(model.deferredUpdates) do
            if history.bound and history.bound.drop ~= history.drop then
                ApplyDrop(model, history.bound, history, now, silent)
                changed = true
            end
        end
        model.deferredUpdates = nil
    end
    return changed
end
function M.HasRollForDrop(model, drop)
    local link = Identity(drop.itemHyperlink)
    if link then
        for _, r in pairs(model.rolls) do
            if r.active and not r.historyKey and Identity(r.data.link) == link then return true end
        end
    end
    return false
end
local function SlotKey(model, encounter, key)
    return model.generation .. ":" .. tostring(encounter) .. ":" .. tostring(key)
end
local function DropKey(slot, nativeIdentity)
    return nativeIdentity and "drop:" .. nativeIdentity or slot
end
function M.KeepResultDuringClear(model, encounter, key, drop, now)
    local link = Identity(drop.itemHyperlink)
    if not link then return false end
    local slot = SlotKey(model, encounter, key)
    local current = model.drops[DropKey(slot, drop.nativeIdentity)]
    if current and not Terminal(current.bound or current) and current.nativeIdentity == drop.nativeIdentity then
        return true
    end
    if drop.nativeIdentity then
        for _, r in ipairs(model.records) do
            if r.restored and r.unresolved and r.nativeIdentity == drop.nativeIdentity then return true end
        end
    end
    local history = { drop = drop, seen = now, serial = model.serial + 1 }
    for _, record in pairs(model.rolls) do
        if not Terminal(record) and not record.historyKey and Identity(record.data.link) == link then
            local timed = TimingMatches(record, drop)
            if record.active and timed or not record.active and CanBind(record, history, timed) then return true end
        end
    end
    return false
end
local function SamePlayer(a, b)
    if not a or not b then return a == b end
    return a.playerGUID == b.playerGUID and a.playerName == b.playerName and a.playerClass == b.playerClass
        and a.state == b.state and a.roll == b.roll and a.isSelf == b.isSelf and a.isWinner == b.isWinner
end
local function SameDrop(a, b)
    if not a or not b or a.itemHyperlink ~= b.itemHyperlink or a.playerRollState ~= b.playerRollState
        or a.nativeIdentity ~= b.nativeIdentity or a.startTime ~= b.startTime or a.duration ~= b.duration
        or a.rosterAllPassed ~= b.rosterAllPassed
        or a.allPassed ~= b.allPassed or a.isTied ~= b.isTied or not SamePlayer(a.winner, b.winner)
        or not SamePlayer(a.currentLeader, b.currentLeader) or #(a.rollInfos or {}) ~= #(b.rollInfos or {}) then return false end
    for i, p in ipairs(a.rollInfos or {}) do if not SamePlayer(p, b.rollInfos[i]) then return false end end
    return true
end
function M.Drop(model, encounter, key, drop, source, now, calendar, hydrated, defer)
    local slot = SlotKey(model, encounter, key)
    local current = model.dropSlots[slot]
    local item = Identity(drop.itemHyperlink)
    if current and Identity(current.data.link) == item and not drop.nativeIdentity then
        if current.nativeIdentity then
            for _, record in pairs(model.rolls) do
                if record.overlapping and record.status ~= "complete" and Identity(record.data.link) == item then
                    return nil, false
                end
            end
        end
        drop.nativeIdentity, drop.startTime = current.nativeIdentity, current.drop.startTime
    end
    local identity = DropKey(slot, drop.nativeIdentity)
    local history = model.drops[identity]
    if not history and current and not current.nativeIdentity and Identity(current.data.link) == item then
        history = current
        model.drops[history.key] = nil
        if history.bound then history.bound.historyKey = identity end
    elseif history and Identity(history.data.link) ~= item then
        if history.bound and not Terminal(history.bound) then Detach(history.bound) end
        if not Terminal(history) then history.status = "unavailable" end
        history = nil
    end
    local finished = model.finished[identity] or not drop.nativeIdentity and model.finished[slot]
    if not history and finished and (finished.stamp == drop.nativeIdentity
        or not drop.nativeIdentity and finished.item == item) then return nil, false end
    if not history and drop.nativeIdentity then
        for _, r in ipairs(model.records) do
            if r.restored and r.nativeIdentity == drop.nativeIdentity then
                history = r
                history.seen = now
                break
            end
        end
    end
    if not history then
        -- 超出结算索引的旧原生记录通常来自重扫。允许仍有待结算依据的晚到结果。
        -- 同批时间相同，尚未观察到更新一批时保留首次出现的记录。
        local before = model.finishedBefore
        local old = before and drop.startTime and (drop.startTime < before
            or drop.startTime == before and model.lastFinishedStart > before)
        if old
            and not M.KeepResultDuringClear(model, encounter, key, drop, now) then return nil, false end
        history = Insert(model, { status = "settling", seen = now, firstSeenAt = calendar, data = { link = drop.itemHyperlink } })
    end
    history.key, history.slot, history.encounterID, history.lootListKey = identity, slot, encounter, key
    model.drops[identity] = history
    -- 槽位用于寻址当前原生数据；同槽位的旧实例仍可收到带原始时间戳的更新。
    if not current or not current.drop.startTime or not drop.startTime or drop.startTime >= current.drop.startTime then
        model.dropSlots[slot] = history
    end
    if history.drop and history.nativeIdentity == drop.nativeIdentity then drop.duration = drop.duration or history.drop.duration end
    if hydrated then
        history.baseline = history.baseline or not history.drop or history.restored or nil
        if history.baseline then history.hydrated, history.restored = true, true end
    else
        history.publishable = true
    end
    local resumeSettling = history.restored and history.unresolved and not history.resumeRollID
        and (history.settlementDeadline or history.selfState ~= 4)
    if resumeSettling and not (drop.winner or drop.allPassed) then
        history.hydrated, history.restored, history.unresolved = nil, nil, nil
        history.publishable = not hydrated or nil
    end
    NormalizeAllPassed(history.bound or history, drop)
    -- 短暂缺字段的重扫不回退已确认的结果。
    if history.drop and history.drop.winner and not drop.winner then drop.winner = history.drop.winner end
    if history.drop and history.drop.allPassed and not drop.winner then drop.allPassed = true end
    if SameDrop(history.drop, drop) and history.source == source and not resumeSettling then
        if drop.winner or drop.allPassed then
            if not history.publishable or history.restored then MarkFinal(model, history, true) end
            if not hydrated and history.outputFailed then MarkFinal(model, history); return history.bound or history, true end
        end
        return history.bound or history, false
    end
    history.drop, history.source, history.nativeIdentity = drop, source, drop.nativeIdentity
    local target = history.bound or history
    if target ~= history and target.status ~= "complete" then
        if TimingMatches(target, drop) == false then
            Detach(target)
            target = history
        elseif defer and not hydrated then
            model.deferredUpdates = model.deferredUpdates or {}
            model.deferredUpdates[history] = true
            target = history
        end
    end
    ApplyDrop(model, target, history, now, hydrated)
    if not hydrated and not defer and not history.bound then M.Reconcile(model, now) end
    return history.bound or history, true
end
local function SettlementDeadline(record)
    if record.settlementDeadline then return record.settlementDeadline end
    local endedAt = record.choiceEndedAt or record.nativeClosedAt
    if endedAt and record.selfState == 4 then return endedAt + RESULT_GRACE end
    return math.max(record.deadline or record.seen + 180, record.withdrawnAt or 0) + RESULT_GRACE
end
function M.Tick(model, now, timeLeft, activeRollSet)
    local changed, needsClock = false, false
    local checkActiveRolls = now >= (model.nextActiveCheck or 0)
    local activeRolls, expiredHistory, nativeUnknown
    for _, r in ipairs(model.records) do
        local rosterFinished = r.rosterHistory and not r.active and Terminal(r.rosterHistory)
        if not r.bound and not rosterFinished and not Terminal(r) then
            if r.rollID and r.active then
                local remaining = now < r.deadline and timeLeft and timeLeft(r.rollID)
                if remaining and remaining > 0 and remaining <= r.duration then
                    r.deadline = math.min(r.deadline, now + remaining)
                end
                -- 本地倒计时到零后，核对原生列表和剩余时间。丢失终态事件时列表可能滞留。
                if now >= r.deadline and checkActiveRolls then
                    if activeRolls == nil then
                        activeRolls = activeRollSet and activeRollSet() or false
                        model.nextActiveCheck = now + ACTIVE_CHECK_INTERVAL
                        nativeUnknown = false
                    end
                    if activeRolls and not activeRolls[r.rollID] then
                        CloseNative(r, now)
                        r.status, changed = "settling", true
                    else
                        local left = activeRolls and timeLeft and timeLeft(r.rollID)
                        if left == 0 and r.zeroTimeSeen then
                            Withdraw(r, now)
                            r.choiceEndedAt, r.status, changed = now, "settling", true
                        end
                        r.zeroTimeSeen = left == 0 or nil
                        if not activeRolls or left == nil then nativeUnknown = true end
                    end
                end
            end
            if not r.active and now >= SettlementDeadline(r) then
                r.active, r.status, r.expired = false, "unavailable", true; changed = true
                local history = r.history or r.rosterHistory or r
                if history.slot and model.dropSlots[history.slot] == history then
                    expiredHistory = expiredHistory or {}
                    expiredHistory[#expiredHistory + 1] = history
                end
            else needsClock = true end
        end
    end
    if changed then Touch(model) end
    return changed, needsClock, expiredHistory, nativeUnknown
end
function M.Clear(model, now, activeRolls)
    local rolls = {}
    for _, r in ipairs(model.records) do
        local nativeRoll = r.rollID and model.rolls[r.rollID] == r
            and ((activeRolls and activeRolls[r.rollID]) or (not activeRolls and not r.nativeClosedAt and not r.expired))
        if nativeRoll then rolls[r.rollID] = r end
        if nativeRoll and not r.choiceEndedAt then
            local history = r.history
            Detach(r)
            if history then history.discarded = true end
            if r.rosterHistory and not Terminal(r.rosterHistory) then r.rosterHistory.discarded = true end
            r.active, r.status, r.expired, r.nativeClosedAt = true, "pending", nil, nil
            r.selfState, r.selfRoll, r.nativeSelfState, r.nativeSelfRoll = 4, nil, nil, nil
            r.confirming, r.request, r.requestUntil, r.withdrawnAt, r.zeroTimeSeen = nil, nil, nil, nil, nil
        elseif not r.bound and not Terminal(r) then
            r.active, r.status, r.expired = false, "unavailable", true
        end
        UnlinkRoster(r)
        r.nativeIdentity = nil
    end
    local write = 1
    for _, r in ipairs(model.records) do
        if not r.discarded then model.records[write] = r; write = write + 1 end
    end
    for i = write, #model.records do model.records[i] = nil end
    model.generation, model.rolls, model.drops, model.dropSlots = model.generation + 1, rolls, {}, {}
    model.finished, model.finishedOrder, model.finishedHead, model.finishedBefore = {}, {}, 0, nil
    model.lastFinishedStart = nil
    model.results, model.nextActiveCheck = {}, now
    Touch(model)
end
local function RemoveIndexes(model, record)
    UnlinkRoster(record)
    UnlinkRoster(record.rosterRoll)
    if record.key and model.drops[record.key] == record then model.drops[record.key] = nil end
    if record.slot and model.dropSlots[record.slot] == record then model.dropSlots[record.slot] = nil end
    if record.rollID and model.rolls[record.rollID] == record then model.rolls[record.rollID] = nil end
end
function M.RemoveFinished(model, onRemove)
    for _, r in ipairs(model.records) do
        if not r.active and r.rosterHistory and Terminal(r.rosterHistory) then r.evicted = true end
    end
    local write = 0
    for read = 1, #model.records do
        local r = model.records[read]
        if r.evicted or Terminal(r.bound or r) then
            if onRemove then onRemove(r) end
            RemoveIndexes(model, r)
        else
            write = write + 1
            model.records[write] = r
        end
    end
    local length = #model.records
    for index = write + 1, length do model.records[index] = nil end
    if length > write then Touch(model) end
    return length - write
end
function M.Pending(model)
    local list = {}
    for _, r in ipairs(model.records) do if r.rollID and r.active and r.selfState == 4 then list[#list + 1] = r end end
    return list
end
function M.List(model)
    local list = {}
    for _, r in ipairs(model.records) do if not r.bound and not r.rosterHistory then list[#list + 1] = r end end
    return list
end
function M.DisplayDrop(record)
    return record.drop or (record.active and record.rosterHistory and record.rosterHistory.drop)
end
function M.Count(record)
    local drop = M.DisplayDrop(record)
    if not drop or type(drop.rollInfos) ~= "table" or #drop.rollInfos == 0 then return nil end
    local c = { need = 0, greed = 0, transmog = 0, pass = 0, waiting = 0, total = 0, voted = 0 }
    for _, p in ipairs(drop.rollInfos) do
        c.total = c.total + 1
        if p.state == 0 or p.state == 1 then c.need = c.need + 1
        elseif p.state == 2 then c.transmog = c.transmog + 1
        elseif p.state == 3 then c.greed = c.greed + 1
        elseif p.state == 5 then c.pass = c.pass + 1
        else c.waiting = c.waiting + 1 end
    end
    c.voted = c.total - c.waiting
    return c
end
function M.Trim(model, limit)
    local ended = 0
    for index = #model.records, 1, -1 do
        local r = model.records[index]
        if not r.bound and not r.rosterHistory and Terminal(r) then
            ended = ended + 1
            if ended > limit then
                r.evicted = true
                if r.rosterRoll and not r.rosterRoll.active then r.rosterRoll.evicted = true end
            end
        end
    end
    for index = #model.records, 1, -1 do
        local r = model.records[index]
        if r.evicted or r.bound and r.bound.evicted then
            RemoveIndexes(model, r)
            table.remove(model.records, index)
        end
    end
end
local function CopyPlayer(p)
    if not p then return nil end
    return { playerName = p.playerName, playerGUID = p.playerGUID, playerClass = p.playerClass,
        isSelf = p.isSelf == true, state = p.state, roll = p.roll, isWinner = p.isWinner == true }
end
local function CopyDrop(drop)
    local copy = { playerRollState = drop.playerRollState, winner = CopyPlayer(drop.winner),
        currentLeader = CopyPlayer(drop.currentLeader), allPassed = drop.allPassed == true,
        isTied = drop.isTied == true, startTime = drop.startTime, duration = drop.duration, rollInfos = {} }
    for n, p in ipairs(drop.rollInfos or {}) do
        if n > 80 then break end
        copy.rollInfos[n] = CopyPlayer(p)
    end
    return copy
end
function M.Snapshot(model, limit, now, calendar, activeRolls)
    local out = { version = 1, records = {} }
    for index = #model.records, 1, -1 do
        local r = model.records[index]
        if not r.bound and not r.rosterHistory and #out.records < (limit or 200) then
            local details = r.details or {}
            local unresolved = not Terminal(r)
            if r.restored and r.status == "unavailable" then unresolved = r.unresolved end
            local item = { firstSeenAt = r.firstSeenAt, source = r.source, nativeIdentity = r.nativeIdentity or (r.historyKey and model.drops[r.historyKey] and model.drops[r.historyKey].nativeIdentity), status = Terminal(r) and r.status or "unavailable",
                data = { link = r.data.link, name = r.data.name, texture = r.data.texture,
                    quality = r.data.quality or details.quality, quantity = r.data.quantity,
                    classID = details.classID or r.data.classID },
                selfState = r.selfState, selfRoll = r.selfRoll, ambiguous = r.ambiguous,
                unresolved = unresolved }
            if now and calendar and unresolved and not r.active and (r.settlementDeadline or r.seen or r.deadline) then
                item.settleUntil = calendar + math.ceil(SettlementDeadline(r) - now)
            end
            if now and calendar and r.active and r.rollID and r.nativeIdentity and not r.ambiguous then
                if r.deadline > now then
                    item.resumeRollID, item.resumeUntil = r.rollID, calendar + math.ceil(r.deadline - now) + 2
                elseif activeRolls and activeRolls[r.rollID] then
                    item.resumeRollID, item.resumeUntil, item.resumeAtZero = r.rollID, calendar + ZERO_TIME_RESUME_WINDOW, true
                end
            end
            if r.drop then item.drop = CopyDrop(r.drop) end
            out.records[#out.records + 1] = item
        end
    end
    return out
end
function M.Restore(model, snapshot, now, calendar)
    if type(snapshot) ~= "table" or snapshot.version ~= 1 or type(snapshot.records) ~= "table" then return end
    for index = math.min(#snapshot.records, 200), 1, -1 do
        local saved = snapshot.records[index]
        if type(saved) == "table" and type(saved.data) == "table" and type(saved.firstSeenAt) == "number" then
            local data = saved.data
            local r = {
                restored = true, active = false, status = saved.status, firstSeenAt = saved.firstSeenAt,
                source = saved.source, nativeIdentity = saved.nativeIdentity, selfState = saved.selfState,
                selfRoll = saved.selfRoll, ambiguous = saved.ambiguous, unresolved = saved.unresolved,
                resumeRollID = saved.resumeRollID, resumeUntil = saved.resumeUntil, resumeAtZero = saved.resumeAtZero,
                data = { link = data.link, name = data.name, texture = data.texture, quality = data.quality,
                    quantity = data.quantity, classID = data.classID },
            }
            if type(saved.drop) == "table" then r.drop = CopyDrop(saved.drop) end
            if now and calendar and type(saved.settleUntil) == "number" then
                r.settlementDeadline = now + (saved.settleUntil - calendar)
                if r.settlementDeadline <= now then r.unresolved = false end
            end
            if r.status ~= "complete" then
                r.status = "unavailable"
                r.expired = r.unresolved == false or nil
            end
            Insert(model, r)
        end
    end
end
