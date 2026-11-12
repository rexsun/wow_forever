local YUI = _G.YUI
local Assistant = YUI and YUI.MailAssistant
if not (Assistant and Assistant.MailLogModel and Assistant.Inbox) then return end

local Model, Event, Security = Assistant.MailLogModel, YUI.Event, YUI.API.Security
local Log = { tracker = Model.NewTracker(), receiptCount = 0, sendCount = 0, unverified = 0 }
Assistant.MailLog = Log
local owner, sessionOwner = { traceName = "MailAssistant.Log" }, { traceName = "MailAssistant.LogSession" }
local TIMEOUT = 10

local function Number(value)
    if Security.IsSecretValue(value) or type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return nil end
    return value
end
local function Text(value)
    if Security.IsSecretValue(value) or type(value) ~= "string" then return nil end
    return value
end
local function Now() return _G.time() end

function Log:GetStore()
    local store = Assistant:GetMailLogStore()
    if store and not self.storeReady then Model.Prune(store, Now()); self.storeReady = true end
    return store
end

function Log:Changed()
    local view = Assistant.MailLogView
    if view and view.window and view.window:IsShown() then view:Refresh()
    else Assistant:RefreshMailLogClasses(self:GetStore()) end
end

function Log:CancelTimer()
    if self.timer then self.timer:Cancel(); self.timer = nil end
end

local function Tick()
    Log.timer = nil
    Log:Observe()
end

function Log:Schedule()
    if not self.enabled or not self.open or not self.deadline or self.timer then return end
    self.timer = _G.C_Timer.NewTimer(0.2, Tick)
end

function Log:Observe(snapshot)
    if not self.enabled or not self.open then return end
    snapshot = snapshot or Assistant.Inbox:Capture()
    if snapshot then
        local receipts, matched = self.tracker:Observe(snapshot)
        local store, character = self:GetStore(), Assistant:GetMailLogCharacter()
        if store and character then
            for _, receipt in ipairs(receipts) do
                local id = Model.Receive(store, receipt, character, Now())
                self.tracker:SetLogId(receipt.token, id)
                self.receiptCount = self.receiptCount + 1
            end
            if #receipts > 0 then self:Changed() end
        end
        if not matched then
            if self.deadline then self.unverified = self.unverified + 1; self:Changed() end
            self.deadline = nil
        end
        if not self.tracker:HasPendingIntents() then self.deadline = nil end
    end
    if self.deadline and _G.GetTime() >= self.deadline then
        self.deadline = nil; self.unverified = self.unverified + 1; self:Changed()
    end
    if self.deadline then self:Schedule()
    else self.tracker:ClearIntents(); self:CancelTimer() end
end

function Log:BeginIncoming(kind, index, slot)
    if not self.enabled or not Number(index) or (slot and not Number(slot)) then return end
    -- An automatic collector may run earlier in MAIL_SHOW listener order.
    if not self.open and _G.MailFrame and _G.MailFrame:IsShown() then self:Open() end
    if not self.open then return end
    -- Finish an older receipt before a third-party queue dispatches its next
    -- command from the same inbox event, regardless of listener ordering.
    if self.deadline then self:Observe() end
    if self.tracker:Begin(kind, index, slot) then
        self.deadline = _G.GetTime() + TIMEOUT
        self:Observe()
    end
end

function Log:BeginSend(recipient, subject)
    if self.pendingSend and _G.GetTime() > self.sendDeadline then self:CancelSend() end
    if not self.enabled or self.pendingSend then return end
    recipient, subject = Text(recipient), Text(subject or "")
    local character = Assistant:GetMailLogCharacter()
    if not recipient or recipient == "" or not subject or not character then return end
    if self.sendAmountsInvalid then return end
    local items = {}
    for slot = 1, _G.ATTACHMENTS_MAX_SEND or 12 do
        local name, id, icon, count = _G.GetSendMailItem(slot)
        if Security.IsSecretValue(id) then return end
        if id then
            local link = _G.GetSendMailItemLink and _G.GetSendMailItemLink(slot)
            count = Number(count)
            if not Text(name) or not count or count == 0 or Security.IsSecretValue(link)
                or Security.IsSecretValue(icon) then return end
            items[#items + 1] = { id = id, name = name, link = link, icon = icon, count = count }
        elseif _G.HasSendMailItem and _G.HasSendMailItem(slot) then return end
    end
    local postage = Number(_G.GetSendMailPrice())
    if not postage then return end
    self.pendingSend = { direction = "out", character = character, party = recipient,
        subject = subject, gold = self.sendMoney or 0, cod = self.sendCOD or 0,
        postage = postage, items = items, status = "sent" }
    self.sendDeadline = _G.GetTime() + 30
end

function Log:ConfirmSend()
    local pending, deadline = self.pendingSend, self.sendDeadline
    self:CancelSend()
    if not self.enabled or not pending or _G.GetTime() > deadline then return end
    local store = self:GetStore()
    if not store then return end
    Model.Append(store, pending, Now())
    self.sendCount = self.sendCount + 1
    self:Changed()
end

function Log:CancelSend() self.pendingSend, self.sendDeadline = nil, nil end

function Log:Clear()
    local store = self:GetStore()
    if not store then return false end
    self:CancelTimer(); self:CancelSend()
    self.deadline = nil
    -- Drop old intents and record IDs so delayed receipts cannot restore erased history.
    self.tracker:Reset(self.open and Assistant.Inbox:Capture() or nil)
    self.tracker.ambiguous = 0
    self.receiptCount, self.sendCount, self.unverified = 0, 0, 0
    store.records, store.nextId = {}, 0
    if Assistant.MailLogView then Assistant.MailLogView:OnLogCleared() end
    return true
end

function Log:EnsureHooks()
    if self.hooked then return end
    self.hooked = true
    for name, kind in pairs({ TakeInboxMoney = "money", TakeInboxItem = "item", AutoLootMailItem = "all" }) do
        Security.SafeHook("MailAssistant.Log:" .. name, _G, name,
            function(index, slot) Log:BeginIncoming(kind, index, slot) end)
    end
    for _, name in ipairs({ "ReturnInboxItem", "DeleteInboxItem" }) do
        Security.SafeHook("MailAssistant.Log:" .. name, _G, name, function(index)
            if not Log.enabled or not Log.open or not Number(index) then return end
            local entry = Log.tracker.entries[index]
            if entry and entry.intent then
                local snapshot = Assistant.Inbox:Capture()
                local after = snapshot and snapshot[index]
                -- Closing a manually emptied letter can request its deletion
                -- before the receipt event reaches us. Confirm only an empty
                -- row that is still present; disappearance may be destruction.
                if snapshot and #snapshot == #Log.tracker.entries and after
                    and after.logIdentity == entry.data.logIdentity
                    and after.money == 0 and #after.items == 0 then
                    Log:Observe(snapshot)
                    entry = Log.tracker.entries[index]
                end
            end
            if entry then entry.intent = nil end
        end)
    end
    Security.SafeHook("MailAssistant.Log:SetMoney", _G, "SetSendMailMoney", function(value)
        if Log.enabled then
            Log.sendMoney = Number(value)
            Log.sendAmountsInvalid = Log.sendMoney == nil or Log.sendCOD == nil
        end
    end)
    Security.SafeHook("MailAssistant.Log:SetCOD", _G, "SetSendMailCOD", function(value)
        if Log.enabled then
            Log.sendCOD = Number(value)
            Log.sendAmountsInvalid = Log.sendMoney == nil or Log.sendCOD == nil
        end
    end)
end

local function InboxChanged() Log:Observe() end
local function MailFailed()
    Log:Observe()
    Log.deadline = nil
    Log.tracker:ClearIntents()
    Log:CancelTimer()
end

function Log:Close()
    -- A submitted send can succeed after the player closes the mailbox. Its
    -- immutable draft is consumed by the existing module success listener.
    self:Observe()
    self.open, self.deadline = false, nil
    self:CancelTimer()
    self.tracker:Reset()
    Event:OffOwner(sessionOwner)
    if Assistant.MailLogView then Assistant.MailLogView:Hide() end
end

function Log:Open()
    if not self.enabled or self.open then return end
    self.open = true
    self.tracker:Reset(Assistant.Inbox:Capture() or {})
    Event:OffOwner(sessionOwner)
    Event:On("MAIL_INBOX_UPDATE", InboxChanged, sessionOwner)
    Event:On("MAIL_SUCCESS", InboxChanged, sessionOwner)
    Event:On("MAIL_FAILED", MailFailed, sessionOwner)
    self:EnsureHooks()
    Assistant:RefreshMailLogClasses(self:GetStore())
end

local function Open() Log:Open() end
local function Close() Log:Close() end
function Log:SetEnabled(enabled)
    if self.enabled == enabled then return end
    self.enabled = enabled
    if enabled then
        self.sendMoney, self.sendCOD, self.sendAmountsInvalid = 0, 0, false
        self:EnsureHooks()
        Event:On("MAIL_SHOW", Open, owner)
        Event:On("MAIL_CLOSED", Close, owner)
        if _G.MailFrame and _G.MailFrame:IsShown() then self:Open() end
    else
        self:Close()
        self:CancelSend()
        Event:OffOwner(owner)
    end
end

function Log:GetStats()
    return { enabled = self.enabled, open = self.open, pendingTimers = self.timer and 1 or 0,
        pendingSend = self.pendingSend ~= nil, receipts = self.receiptCount, sends = self.sendCount,
        ambiguous = self.tracker.ambiguous, unverified = self.unverified, rows = #self.tracker.entries }
end

Log:SetEnabled(Assistant.runtime.enabled == true)
