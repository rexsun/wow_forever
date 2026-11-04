local YUI = _G.YUI
local Assistant = YUI and YUI.MailAssistant
if not (Assistant and Assistant.InboxModel and Assistant.Compatibility) then return end

local Event, GUI2 = YUI.Event, YUI.GUI2
local Security = YUI.API.Security
local Model, Compatibility = Assistant.InboxModel, Assistant.Compatibility
local Inbox = { model = Model.New(), checks = {}, rowLayouts = {}, enabled = false, dockOffset = 6 }
Assistant.Inbox = Inbox
local owner, sessionOwner = {}, {}
local STEP_DELAY, RECEIPT_TIMEOUT = 0.2, 10
local CHECK_SIZE, CHECK_INSET, TEXT_GAP = 24, 4, 4
local function T(key, fallback) return Assistant:Translate(key, fallback) end
local function Shown(frame) return frame and frame.IsVisible and frame:IsVisible() end
local function Secret(value) return Security.IsSecretValue and Security.IsSecretValue(value) end
local function Scalar(value)
    if Secret(value) then return nil end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return tostring(value) end
    return value == nil and "" or nil
end
local function Join(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local value = Scalar(select(index, ...))
        if value == nil then return nil end
        parts[index] = #value .. ":" .. value
    end
    return table.concat(parts, "|")
end

-- Both supported clients expose the same mail assets. Read every attachment
-- before using an inbox index; visual refresh entry points are resolved separately.
function Inbox:Capture()
    if not Compatibility:HasNativeInbox() then return nil end
    local loaded, total = _G.GetInboxNumItems()
    if Secret(loaded) or type(loaded) ~= "number" then return nil end
    local snapshot = {}
    for index = 1, loaded do
        local _, stationery, sender, subject, money, cod, _, itemCount, wasRead, returned, textCreated, _, gm = _G.GetInboxHeaderInfo(index)
        local identity = Join(stationery, sender, subject, cod, returned, textCreated, gm)
        if not identity or Secret(money) or type(money) ~= "number"
            or Secret(itemCount) or Secret(cod) or Secret(gm) or not subject then return nil end
        local items, keys = {}, {}
        for slot = 1, _G.ATTACHMENTS_MAX_RECEIVE or 16 do
            local name, id, icon, count, _, _, currency = _G.GetInboxItem(index, slot)
            if Secret(id) or Secret(count) or Secret(currency) then return nil end
            if id then
                local link = _G.GetInboxItemLink and _G.GetInboxItemLink(index, slot)
                if Secret(link) then return nil end
                local key = Join(id, count, link or name, currency)
                local assetKey = Join(id, link or name, currency)
                if not key or not assetKey or not count or Secret(name) or Secret(icon) then return nil end
                items[#items + 1] = { slot = slot, key = key, assetKey = assetKey, id = id,
                    name = name, link = link, icon = icon, count = count, currency = currency == true }
                keys[#keys + 1] = key
            end
        end
        if (itemCount or 0) ~= #items then return nil end
        table.sort(keys)
        local itemKey = table.concat(keys, "\031")
        local deletable = type(_G.InboxItemCanDelete) == "function" and _G.InboxItemCanDelete(index)
        snapshot[index] = { identity = identity, money = money, items = items, itemKey = itemKey,
            logIdentity = Join(stationery, sender, subject, returned, textCreated, gm),
            sender = sender or "", subject = subject, cod = cod or 0,
            wasRead = not Secret(wasRead) and wasRead == true,
            deletable = not Secret(deletable) and deletable == true,
            restricted = (cod or 0) > 0 or gm == true, key = Join(identity, money, itemKey) }
    end
    self.loaded, self.total = loaded, not Secret(total) and tonumber(total) or loaded
    return snapshot
end

function Inbox:FreeSlots()
    local api, free = _G.C_Container, 0
    if not (api and api.GetContainerNumFreeSlots) then return 0 end
    for bag = 0, _G.NUM_BAG_SLOTS or 4 do
        local slots, family = api.GetContainerNumFreeSlots(bag)
        if not Secret(slots) and not Secret(family) and family == 0 then free = free + (slots or 0) end
    end
    return free
end

function Inbox:Availability()
    if not self.enabled or not self.open or not Shown(_G.MailFrame) then return "closed" end
    if not Assistant:GetConfiguration().inboxEnabled then return "off" end
    if not Compatibility:HasNativeInbox() then return "unsupported" end
    local external = Compatibility:GetOwners()
    if external then self.external = external; return "conflict" end
    self.external = nil
    if self.nativeBusy or (_G.OpenAllMail and _G.OpenAllMail.IsEventRegistered
        and _G.OpenAllMail:IsEventRegistered("MAIL_INBOX_UPDATE")) then return "native_busy" end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return "combat" end
    if Shown(_G.SendMailFrame) then return "send" end
    if Shown(_G.OpenMailFrame) then return "detail" end
    if not Shown(_G.InboxFrame) then return "unsupported" end
    local loaded = _G.GetInboxNumItems()
    if not Secret(loaded) and type(loaded) == "number" and loaded > 0
        and not Shown(_G.MailItem1Button) then return "unsupported" end
    return nil
end

function Inbox:CancelTimer()
    if self.timer then self.timer:Cancel(); self.timer = nil end
end

local function Tick()
    Inbox.timer = nil
    Inbox:Advance()
end

function Inbox:Schedule()
    if self.timer or not self.open or not self.enabled then return end
    if _G.C_Timer and _G.C_Timer.NewTimer then self.timer = _G.C_Timer.NewTimer(STEP_DELAY, Tick) end
end

function Inbox:Stop(reason)
    self.model:Stop(reason)
    if self.model.pending then self:Schedule() else self:CancelTimer() end
    self:RefreshView()
end

function Inbox:Advance()
    if not self.open or not self.enabled then return end
    self:EnsureUI()
    local model = self.model
    local unavailable = self:Availability()
    if unavailable then self:CancelDelete() end
    if unavailable and model:IsBusy() then model:Stop(unavailable) end
    if unavailable and not model.pending then
        self:CancelTimer()
        Assistant:ApplyPanelVisibility()
        return
    end
    local snapshot = self:Capture()
    self.loading = snapshot == nil
    if snapshot then self.loadingSince = nil end
    if snapshot then model:Observe(snapshot) end
    if model.pending then
        if _G.GetTime() - (self.commandTime or 0) >= RECEIPT_TIMEOUT then
            model:Invalidate(snapshot or {}, "timeout")
            model.state = "timeout"
            self:CancelTimer()
        else self:Schedule() end
    elseif model.state == "running" and not unavailable then
        if not snapshot then
            self.loadingSince = self.loadingSince or _G.GetTime()
            if _G.GetTime() - self.loadingSince >= RECEIPT_TIMEOUT then
                model:Invalidate({}, "timeout"); model.state = "timeout"
            else self:Schedule() end
        elseif _G.C_Mail.IsCommandPending() then
            -- An inbox update can precede the server clearing our command flag.
            if self.awaitClear and _G.GetTime() - self.commandTime < RECEIPT_TIMEOUT then self:Schedule()
            elseif self.awaitClear then model:Invalidate(snapshot, "timeout"); model.state = "timeout"
            else model:Stop("native_busy") end
        else
            self.awaitClear = false
            local command = model:Next(self:FreeSlots(), Assistant:GetConfiguration().bagReserve)
            if command then
                self.commandTime, self.issuing, self.awaitClear = _G.GetTime(), true, true
                local ok
                if command.kind == "money" then ok = pcall(_G.TakeInboxMoney, command.index)
                elseif command.kind == "delete" then ok = pcall(_G.DeleteInboxItem, command.index)
                else ok = pcall(_G.TakeInboxItem, command.index, command.slot) end
                self.issuing = false
                if not ok then model:Fail("error") end
                self:Schedule()
            end
        end
    end
    Assistant:ApplyPanelVisibility()
end

function Inbox:Start(mode, approved)
    if self:Availability() or self.model:IsBusy() or _G.C_Mail.IsCommandPending() then return false end
    local snapshot = self:Capture()
    if not snapshot then self.loading = true; self:RefreshView(); return false end
    if not self.model:Observe(snapshot) then self:RefreshView(); return false end
    self.awaitClear = false
    if not self.model:Start(mode, approved) then return false end
    self:Advance()
    return true
end

function Inbox:CancelDelete()
    self.deleteApproval = nil
    if self.ui and self.ui.confirm then self.ui.confirm:Hide() end
end

function Inbox:RequestDelete()
    if self:Availability() or self.loading or self.model:IsBusy() or _G.C_Mail.IsCommandPending() then return false end
    local snapshot = self:Capture()
    if not snapshot or not self.model:Observe(snapshot) then self:RefreshView(); return false end
    local candidates, unread = self.model:DeletionCandidates()
    if #candidates == 0 then return false end
    self.deleteApproval = candidates
    self:EnsureDeleteDialog()
    self.ui.confirmText:SetText(string.format(T("inbox.delete.confirm", "Delete %d selected empty letters?\nNo items or gold; %d unread.\n\nThe letter text will be permanently deleted."), #candidates, unread))
    self.ui.accept:SetText(string.format(T("inbox.delete.accept", "Delete %d"), #candidates))
    self.ui.confirm:Show()
    self:RefreshView()
    return true
end

function Inbox:ConfirmDelete()
    local approved = self.deleteApproval
    self:CancelDelete()
    if not approved or type(_G.DeleteInboxItem) ~= "function" then self:RefreshView(); return false end
    local started = self:Start("delete", approved)
    self:RefreshView()
    return started
end

function Inbox:Select(index, value, range)
    if self:Availability() or self.model:IsBusy() then return false end
    local snapshot = self:Capture()
    if not snapshot or not self.model:Observe(snapshot) then self:RefreshView(); return false end
    local selected = self.model:Select(index, value, range)
    self:RefreshView()
    return selected
end

function Inbox:SelectPage(scope)
    if self:Availability() or self.model:IsBusy() then return end
    local snapshot = self:Capture()
    if not snapshot or not self.model:Observe(snapshot) then self:RefreshView(); return end
    local first = ((_G.InboxFrame.pageNum or 1) - 1) * 7 + 1
    for index = first, math.min(first + 6, #self.model.entries) do
        local data = self.model.entries[index].data
        local matches = scope == "empty" and Model.CanDelete(data)
            or scope == "assets" and Model.HasAssets(data) or not scope or scope == "all"
        self.model:Select(index, matches == true)
    end
    self:RefreshView()
end

local STATUS = {
    idle = "Use the selection column; Shift-click selects a range.",
    running = "Collecting. New mail is not added to this batch.",
    waiting = "Waiting for the server to confirm collection…",
    stopping = "Stopping after the current receipt…",
    stopped = "Stopped. Selection kept.",
    full = "Paused: bags full.\nFree space, then continue.",
    reserve = "Paused: reserve reached.\nFree space or lower reserve.",
    changed = "Mail changed; select again.",
    done = "Collection complete.",
    error = "Collection failed. Check the game error; no automatic retry.",
    timeout = "No confirmed receipt. Check your mail before selecting again.",
    loading = "Mail is still loading. Try again after it updates.",
    native_busy = "Another mail operation is active. Try again when it finishes.",
    conflict = "Another addon handles collection. Disable its mail feature to use Nova.",
    detail = "Close the open letter to select or collect mail.",
    unsupported = "The current mailbox does not expose the native mail list.",
    combat = "Collection is paused during combat.",
    empty = "There is no mail to collect.",
    no_attachments = "No items or gold. Open letters individually to read.",
    selected_no_attachments = "Nothing to collect in this selection. Open letters individually to read.",
    off = "Collection is disabled in settings.",
    closed = "Mailbox closed.",
    send = "Collection stopped after switching to Send Mail.",
}
local DELETE_STATUS = {
    done = { "complete", "Deletion complete." },
    waiting = { "waiting", "Waiting for deletion confirmation…" },
    timeout = { "timeout", "Deletion unconfirmed. Check remaining mail." },
    error = { "error", "Deletion failed. Check the game error." },
    stopped = { "stopped", "Deletion stopped." },
    stopping = { "stopping", "Stopping after deletion confirmation…" },
}

function Inbox:RefreshView()
    local ui, model = self.ui, self.model
    if not ui then return end
    Assistant:SyncPanelSize()
    local unavailable = self:Availability()
    local busy = model:IsBusy()
    local show = self.open and Assistant.runtime.panelMode == "inbox" and not Assistant.runtime.temporarilyClosed
    ui.root:SetShown(show == true)
    if self.deleteApproval then
        local candidates = model:DeletionCandidates()
        local valid = not unavailable and not self.loading and #candidates == #self.deleteApproval
        for index, candidate in ipairs(candidates) do
            local approved = self.deleteApproval[index]
            if not approved or candidate.token ~= approved.token or candidate.key ~= approved.key then valid = false end
        end
        if not valid then self:CancelDelete() end
    end
    local active = show and not unavailable and not self.loading and not self.deleteApproval
    local selected = model:CountSelected()
    local hasGold, selectable, collectible, selectedCollectible = false, 0, 0, 0
    local selectedGold, selectedItems = 0, 0
    local pageFirst = ((_G.InboxFrame.pageNum or 1) - 1) * 7 + 1
    local pageSelectable, pageAssets, pageEmpty = 0, 0, 0
    for index, entry in ipairs(model.entries) do
        if index >= pageFirst and index < pageFirst + 7 then
            if Model.CanSelect(entry.data) then pageSelectable = pageSelectable + 1 end
            if Model.HasAssets(entry.data) then pageAssets = pageAssets + 1 end
            if Model.CanDelete(entry.data) then pageEmpty = pageEmpty + 1 end
        end
        if Model.CanSelect(entry.data) then selectable = selectable + 1 end
        if model.selected[entry.token] then
            selectedGold = selectedGold + entry.data.money
            selectedItems = selectedItems + #entry.data.items
        end
        if Model.HasAssets(entry.data) then
            collectible = collectible + 1
            if model.selected[entry.token] then selectedCollectible = selectedCollectible + 1 end
            if entry.data.money > 0 then hasGold = true end
        end
    end
    local deleting = model.batchMode == "delete"
    local candidates = model:DeletionCandidates()
    ui.loaded:SetText(string.format(T("inbox.loaded", "Loaded %d / %d"), self.loaded or 0, self.total or 0))
    ui.loaded:SetShown((self.loaded or 0) < (self.total or 0) or self.loading)
    ui.selected:SetText(string.format(T("inbox.summary", "%d letters · %d selected"), self.loaded or 0, selected))
    local preview = selectedItems == 0 and selectedGold == 0
        and T("inbox.preview.empty", "No items or gold")
        or string.format(T("inbox.preview", "%d items · %s gold"), selectedItems,
            _G.GetMoneyString and _G.GetMoneyString(selectedGold) or tostring(math.floor(selectedGold / 10000)))
    if selectedItems > 0 and selectedGold == 0 then
        preview = string.format(T("inbox.preview.items", "%d items"), selectedItems)
    elseif selectedItems == 0 and selectedGold > 0 then
        preview = _G.GetMoneyString and _G.GetMoneyString(selectedGold) or tostring(math.floor(selectedGold / 10000))
    end
    if busy then
        preview = string.format(T(deleting and "inbox.deleting" or "inbox.collecting", "Processing letter %d"),
            math.min(model.completed + 1, model.total))
    end
    ui.preview:SetText(preview)
    ui.collect:SetDisabled(not active or busy or selectedCollectible == 0)
    ui.collect:SetShown(not busy)
    ui.gold:SetDisabled(not active or busy or not hasGold)
    ui.all:SetDisabled(not active or busy or pageSelectable == 0)
    ui.assets:SetDisabled(not active or busy or pageAssets == 0)
    ui.empty:SetDisabled(not active or busy or pageEmpty == 0)
    ui.clear:SetDisabled(not active or busy or selected == 0)
    ui.delete:SetDisabled(not active or busy or #candidates == 0 or type(_G.DeleteInboxItem) ~= "function")
    -- Selection and confirmation already show counts; keep the action readable
    -- in both faces instead of squeezing a changing count beside the icon.
    local deleteText = T("inbox.delete", "Delete empty")
    if ui.delete:GetText() ~= deleteText then ui.delete:SetText(deleteText) end
    ui.stop:SetShown(busy)
    local stopText = T(deleting and "inbox.delete.stop" or "inbox.stop", deleting and "Stop deleting" or "Stop collection")
    if ui.stop:GetText() ~= stopText then ui.stop:SetText(stopText) end
    ui.stop:SetDisabled(model.state ~= "running")
    ui.reserve:SetDisabled(not active or busy)
    ui.reserve:SetValue(Assistant:GetConfiguration().bagReserve, true)
    ui.bags:SetText(string.format(T("inbox.bag_summary", "Bags %d slots · Reserve"), self:FreeSlots()))
    local state = unavailable or (self.loading and "loading") or model.state
    if not unavailable and state == "conflict" then state = "stopped" end
    if state == "running" and (model.pending or self.awaitClear) then state = "waiting" end
    if state == "idle" and #model.entries == 0 then state = "empty" end
    if state == "idle" then
        if selected > 0 and selectedCollectible == 0 then state = "selected_no_attachments"
        elseif selectable > 0 and collectible == 0 then state = "no_attachments" end
    end
    local status = T("inbox.state." .. state, STATUS[state] or STATUS.idle)
    if deleting and DELETE_STATUS[state] then
        local message = DELETE_STATUS[state]
        status = T("inbox.delete." .. message[1], message[2])
    end
    if state == "conflict" and self.external then
        if self.external == "NDui" then
            status = T("inbox.state.ndui_conflict", 'NDUI Settings - Ease of Use\nDisable "Enable Mailbox Enhancement"\nThen /reload.')
        else
            status = self.external .. "\n" .. status
        end
    end
    ui.attention = state == "reserve" or state == "full" or state == "error" or state == "timeout"
    ui.notice:SetShown(ui.attention)
    GUI2:SetTextColorKey(ui.status, (ui.attention or state == "conflict") and "color.state.warning" or "color.text.secondary")
    ui.status:SetText((state == "idle" or state == "no_attachments" or state == "selected_no_attachments") and "" or status)
    local resumable = state == "reserve" or state == "full" or state == "stopped"
    local collectText = T(resumable and "inbox.resume" or "inbox.collect", resumable and "Continue" or "Collect selected")
    if ui.collect:GetText() ~= collectText then ui.collect:SetText(collectText) end
    ui.progress:SetText(string.format(T("inbox.confirmed", "Done %d/%d"), model.completed, model.total))
    ui.earned:SetText(string.format(T("inbox.earned", "Collected: %s"),
        _G.GetMoneyString and _G.GetMoneyString(model.gold) or tostring(math.floor(model.gold / 10000))))
    ui.earned:SetShown(model.total > 0 and not deleting)
    local value = model.total > 0 and model.completed / model.total or 0
    if ui.progressValue ~= value then
        ui.progressValue = value
        ui.progressBar:SetValue(value, true)
    end
    local color = model.state == "done" and "color.state.success"
        or (busy and "color.accent.primary" or "color.state.warning")
    if self.appearanceContext and self.appearanceContext.source == "native" then color = "native" end
    if ui.progressColor ~= color then
        ui.progressColor = color
        if color == "native" then ui.progressBar:SetFillColor(1, 0.82, 0, 1)
        else ui.progressBar:SetFillColor(color) end
    end
    ui.progressBar:SetShown(model.total > 0)
    ui.progress:SetShown(model.total > 0)
    ui.remaining:SetShown(model.total > model.completed)
    ui.remaining:SetText(string.format(T("inbox.remaining", "%d left"), math.max(0, model.total - model.completed)))
    self:Layout()
    ui.shield:SetShown((busy or self.deleteApproval ~= nil) and show and Shown(_G.InboxFrame) and not unavailable)
    for rowIndex, checkbox in ipairs(self.checks) do
        local button = _G["MailItem" .. rowIndex .. "Button"]
        local index = button and button.index
        local entry = index and model.entries[index]
        checkbox.mailIndex = index
        local visible = active and checkbox.positioned and entry ~= nil and Shown(button) or false
        local checked = entry and model.selected[entry.token] == true or false
        checkbox:SetShown(visible)
        checkbox.selection:SetShown(visible and checked)
        checkbox:SetChecked(checked, true)
        local disabled = busy or self.deleteApproval ~= nil or not entry or not Model.CanSelect(entry.data)
        checkbox:SetDisabled(disabled)
        if checkbox.native then
            checkbox.native:SetChecked(checked)
            checkbox.native:SetEnabled(not disabled)
        end
    end
end

-- Retain the skin's geometry, and restore only values still owned by us.
-- A later skin pass becomes the new baseline instead of accumulating offsets.
local function ReadPoints(region)
    local points = {}
    for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
    return points
end

local function SamePoints(region, points, offset)
    if region:GetNumPoints() ~= #points then return false end
    for index, point in ipairs(points) do
        local anchor, relative, relativeAnchor, x, y = region:GetPoint(index)
        if anchor ~= point[1] or relative ~= point[2] or relativeAnchor ~= point[3]
            or x ~= point[4] + (offset or 0) or y ~= point[5] then return false end
    end
    return true
end

local function WritePoints(region, points, offset)
    region:ClearAllPoints()
    for _, point in ipairs(points) do
        region:SetPoint(point[1], point[2], point[3], point[4] + (offset or 0), point[5])
    end
end

local function RestoreText(state)
    local region = state.region
    if state.appliedWidth and region:GetWidth() == state.appliedWidth then region:SetWidth(state.width) end
    if state.wrap ~= nil and region:CanWordWrap() == false then region:SetWordWrap(state.wrap) end
end

local function LimitText(state, right)
    local region = state.region
    local width = region:GetWidth()
    if width ~= state.appliedWidth then state.width = width end
    if region.CanWordWrap then
        local wrap = region:CanWordWrap()
        if wrap then state.wrap = wrap; region:SetWordWrap(false) end
    end
    local target = math.max(1, math.min(state.width, right / region:GetEffectiveScale() - region:GetLeft()))
    if width ~= target then region:SetWidth(target) end
    state.appliedWidth = target
end

function Inbox:RestoreRow(index)
    local state = self.rowLayouts[index]
    if not state then return end
    if SamePoints(state.date, state.points, state.offset) then WritePoints(state.date, state.points) end
    RestoreText(state.sender); RestoreText(state.subject)
    self.rowLayouts[index] = nil
end

function Inbox:LayoutRows()
    local active = self.open and not Assistant.runtime.temporarilyClosed
        and Assistant.runtime.panelMode == "inbox" and not self:Availability()
    for index, checkbox in ipairs(self.checks) do
        local row = _G["MailItem" .. index]
        local sender, subject, date = _G["MailItem" .. index .. "Sender"],
            _G["MailItem" .. index .. "Subject"], _G["MailItem" .. index .. "ExpireTime"]
        local state = self.rowLayouts[index]
        if state and (not active or state.row ~= row or state.date ~= date
            or state.sender.region ~= sender or state.subject.region ~= subject) then
            self:RestoreRow(index); state = nil
        end
        checkbox.positioned = false
        if active and row and sender and subject and date and date:GetNumPoints() > 0
            and row:GetRight() and sender:GetLeft() and subject:GetLeft() and date:GetRight() then
            if not state then
                state = { row = row, date = date, points = ReadPoints(date), offset = 0,
                    sender = { region = sender, width = sender:GetWidth() },
                    subject = { region = subject, width = subject:GetWidth() } }
                self.rowLayouts[index] = state
            elseif not SamePoints(date, state.points, state.offset) then
                state.points, state.offset = ReadPoints(date), 0
            end
            if checkbox.row ~= row then
                checkbox.row = row
                checkbox.rowRoot:SetParent(row)
                checkbox.rowRoot:ClearAllPoints()
                checkbox.rowRoot:SetAllPoints(row)
                checkbox.rowRoot:SetFrameLevel(row:GetFrameLevel() + 1)
            end
            local scale, dateScale = row:GetEffectiveScale(), date:GetEffectiveScale()
            local textRight = (row:GetRight() - CHECK_INSET - CHECK_SIZE - TEXT_GAP) * scale
            local originalRight = (date:GetRight() - state.offset) * dateScale
            local offset = math.min(0, (textRight - originalRight) / dateScale)
            if not SamePoints(date, state.points, offset) then WritePoints(date, state.points, offset) end
            state.offset = offset
            -- The date button is wider than its right-aligned text. Measure the
            -- actual glyphs, so long senders retain all available space.
            local dateLeft = date:GetLeft() * dateScale
            local font = date:GetFontString()
            if font and font:GetJustifyH() == "RIGHT" then
                dateLeft = date:GetRight() * dateScale
                    - math.min(date:GetWidth() * dateScale, font:GetStringWidth() * font:GetEffectiveScale())
            end
            LimitText(state.sender, math.min(textRight, dateLeft - TEXT_GAP * scale))
            LimitText(state.subject, textRight)
            checkbox.positioned = true
        elseif state then
            self:RestoreRow(index)
        end
        checkbox.rowRoot:SetShown(checkbox.positioned)
    end
end

function Inbox:Layout()
    local ui, panel = self.ui, Assistant.runtime.panel
    if not ui or not panel then return end
    self:LayoutRows()
    local width, height = panel:GetWidth() - 24, panel:GetHeight() - 50
    local native = self.appearanceContext and self.appearanceContext.source == "native"
    local compact = height < 350
    local buttonHeight = compact and 26 or (native and 30 or 32)
    local primaryHeight = buttonHeight + 4
    local hasLoaded = (self.loaded or 0) < (self.total or 0) or self.loading
    if ui.layoutWidth == width and ui.layoutHeight == height and ui.native == native and ui.hasLoaded == hasLoaded
        and ui.layoutAttention == ui.attention then return end
    ui.layoutWidth, ui.layoutHeight, ui.native, ui.hasLoaded = width, height, native, hasLoaded
    ui.layoutAttention = ui.attention
    local function Place(control, x, y, w, h)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", ui.root, "TOPLEFT", x, -y)
        control:SetWidth(w)
        if h then control:SetHeight(h) end
        if control.LayoutButtonContent then control:LayoutButtonContent() end
    end
    Place(ui.selected, 0, 0, width)
    Place(ui.loaded, 0, 22, width)
    local toolbarY = hasLoaded and (compact and 40 or 44) or 26
    local quickWidth = (width - 12) / 4
    for index, button in ipairs({ ui.all, ui.assets, ui.empty, ui.clear }) do
        Place(button, (index - 1) * (quickWidth + 4), toolbarY, quickWidth, buttonHeight)
    end
    local half = (width - 8) / 2
    local previewY = toolbarY + buttonHeight + (compact and 6 or 8)
    Place(ui.preview, 0, previewY, width, 20)
    local actionY = previewY + (compact and 22 or 26)
    Place(ui.collect, 0, actionY, width, primaryHeight)
    Place(ui.stop, 0, actionY, width, primaryHeight)
    local secondaryY = actionY + primaryHeight + (compact and 6 or 8)
    local goldWidth = math.min(106, half)
    Place(ui.gold, 0, secondaryY, goldWidth, buttonHeight)
    Place(ui.delete, goldWidth + 8, secondaryY, width - goldWidth - 8, buttonHeight)
    local statusY = secondaryY + buttonHeight + (compact and 4 or 10)
    local statusHeight = math.max(16, height - statusY - 104)
    Place(ui.notice, 0, statusY, width, math.min(64, statusHeight))
    ui.status:SetParent(ui.attention and ui.notice or ui.root)
    Place(ui.status, ui.attention and 34 or 0, statusY + (ui.attention and 8 or 0),
        width - (ui.attention and 44 or 0), ui.attention and math.min(64, statusHeight) - 16 or statusHeight)
    ui.progressBar:SetBarSize(width, 12)
    ui.progress:SetWidth(width - 100)
    ui.earned:SetWidth(width)
    ui.bags:SetWidth(width - 76)
end

function Inbox:ApplyAppearance(context)
    self.appearanceContext = context
    if not self.ui then return end
    local appearance = GUI2.WindowAppearance
    if appearance and appearance.ApplyFont then
        for _, region in ipairs(self.ui.texts) do appearance:ApplyFont(region, context) end
    end
    for _, button in ipairs(self.ui.buttons) do button:LayoutButtonContent() end
    local r, g, b
    if appearance and appearance.GetAccentColor then r, g, b = appearance:GetAccentColor(context) end
    if not r then r, g, b = GUI2:GetColor("color.accent.primary") end
    for _, checkbox in ipairs(self.checks) do
        local native = context and context.source == "native"
        if native and not checkbox.native then
            local face = _G.CreateFrame("CheckButton", nil, checkbox, "UICheckButtonTemplate")
            face:SetSize(26, 26)
            face:SetPoint("CENTER")
            face:SetScript("OnClick", function(button)
                Inbox:Select(checkbox.mailIndex, button:GetChecked(), _G.IsShiftKeyDown and _G.IsShiftKeyDown())
            end)
            checkbox.native = face
        end
        checkbox.box:SetShown(not native)
        if checkbox.native then checkbox.native:SetShown(native) end
        checkbox.selection:SetColorTexture(r, g, b, 0.07)
    end
    self:Layout()
    self:RefreshView()
end

function Inbox:EnsureDeleteDialog()
    local ui = self.ui
    if ui.confirm then return end
    local modal = GUI2:CreateFrame(ui.root, { width = 360, height = 210 })
    modal:SetPoint("CENTER", _G.MailFrame, "CENTER", 120, 0)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(ui.root:GetFrameLevel() + 50)
    modal:EnableMouse(true)
    ui.confirm = modal
    local title = GUI2:CreateText(modal, T("inbox.delete.title", "Confirm batch deletion"), 14, "color.text.primary", "CENTER")
    title:SetPoint("TOP", modal, "TOP", 0, -12)
    ui.confirmText = GUI2:CreateText(modal, "", 13, "color.text.primary", "CENTER")
    ui.confirmText:SetPoint("TOPLEFT", modal, "TOPLEFT", 20, -48)
    ui.confirmText:SetSize(320, 104)
    ui.confirmText:SetWordWrap(true)
    local cancel = Assistant:CreateMailButton(modal, { text = T("inbox.delete.cancel", "Cancel"), width = 148, height = 36,
        onClick = function() Inbox:CancelDelete(); Inbox:RefreshView() end })
    cancel:SetPoint("BOTTOMLEFT", modal, "BOTTOMLEFT", 24, 14)
    ui.accept = Assistant:CreateMailButton(modal, { text = "", width = 148, height = 36, tone = "danger",
        onClick = function() Inbox:ConfirmDelete() end })
    ui.accept.modern.gui2SurfaceToken = "color.state.danger"
    ui.accept.modern.gui2TextColorKey = "color.accent.text"
    if ui.accept.modern.RefreshTheme then ui.accept.modern:RefreshTheme() end
    ui.accept:SetPoint("BOTTOMRIGHT", modal, "BOTTOMRIGHT", -24, 14)
    modal:EnableKeyboard(true)
    modal:SetPropagateKeyboardInput(true)
    modal:SetScript("OnKeyDown", function(frame, key)
        frame:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Inbox:CancelDelete(); Inbox:RefreshView() end
    end)
    modal:Hide()
    GUI2.WindowAppearance:Register(modal, { blizzardWindow = "mail", nativeLayout = "Dialog",
        themeProvider = function() return Assistant:GetMailThemeStyle() end,
        onRefresh = function(_, context)
            GUI2.WindowAppearance:ApplyFont(title, context)
            GUI2.WindowAppearance:ApplyFont(ui.confirmText, context)
            cancel:ApplySkin(context); ui.accept:ApplySkin(context)
        end })
end

function Inbox:EnsureUI()
    if self.ui or not Assistant.runtime.panel or not Compatibility:HasNativeInbox() then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    local panel = Assistant.runtime.panel
    local root = GUI2:CreateFrame(panel, {})
    root:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -38)
    root:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
    local ui = { root = root, texts = {}, buttons = {} }
    self.ui = ui
    local function Text(key, y, size, color)
        local region = GUI2:CreateText(root, "", size or 12, color or "color.text.primary", "LEFT")
        region:SetPoint("TOPLEFT", root, "TOPLEFT", 0, y)
        region:SetWidth(panel:GetWidth() - 24)
        region:SetWordWrap(true)
        region:SetJustifyV("TOP")
        ui[key] = region; ui.texts[#ui.texts + 1] = region
        return region
    end
    local function Button(key, text, x, y, width, action, microIcon, atlas, tooltip)
        local quick = key == "all" or key == "assets" or key == "empty" or key == "clear"
        local button = Assistant:CreateMailButton(root, { text = text, width = width, height = 36,
            primary = key == "collect" or key == "stop", relief = "hairline",
            tone = key == "collect" and "accent" or "default", onClick = action,
            microIcon = microIcon, atlas = atlas, preserveIconColor = atlas ~= nil,
            mailAction = quick and "quick" or key,
            nativeIcon = key == "collect" and { icon = "Interface\\MailFrame\\Mail-Icon", iconSize = 16 }
                or key == "gold" and { atlas = "coin-gold", iconSize = 14 } or false,
            iconSize = quick and 12 or 16, iconLeftPadding = quick and 4 or 8,
            iconGap = quick and 3 or 5, textRightPadding = quick and 3 or 8, justifyH = "CENTER", tooltip = tooltip })
        button:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
        ui[key] = button
        ui.buttons[#ui.buttons + 1] = button
        if button.text then ui.texts[#ui.texts + 1] = button.text end
        return button
    end
    Text("loaded", -22, 12, "color.text.secondary")
    Text("selected", 0, 13)
    Button("all", T("inbox.quick.all", "All"), 0, 0, 56, function() Inbox:SelectPage("all") end, "check", nil,
        T("inbox.quick.all.hint", "Select this page. Other pages keep their selection."))
    Button("assets", T("inbox.quick.assets", "Loot"), 0, 0, 56, function() Inbox:SelectPage("assets") end, "download", nil,
        T("inbox.quick.assets.hint", "Select only mail with items or gold on this page."))
    Button("empty", T("inbox.quick.empty", "Empty"), 0, 0, 56, function() Inbox:SelectPage("empty") end, "copy", nil,
        T("inbox.quick.empty.hint", "Select only deletable empty mail on this page. Nothing is deleted."))
    Button("clear", T("inbox.quick.clear", "Clear"), 0, 0, 56, function() Inbox.model:Clear(); Inbox:RefreshView() end, "x", nil,
        T("inbox.quick.clear.hint", "Clear the selection on all pages."))
    Button("collect", T("inbox.collect", "Collect selected"), 0, -88, 170, function() Inbox:Start("selected") end, "download")
    Button("gold", T("inbox.gold.short", "Gold only"), 0, -122, 114, function() Inbox:Start("gold") end, nil,
        "coin-gold")
    Button("delete", T("inbox.delete", "Delete empty"), 0, 0, 114, function() Inbox:RequestDelete() end, "trash-2")
    Text("preview", 0, 13)
    Text("bags", 0, 12, "color.text.secondary")
    ui.bags:ClearAllPoints(); ui.bags:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 9)
    local reserves = {}
    for value = 0, 20 do reserves[#reserves + 1] = { text = tostring(value), value = value } end
    ui.reserve = Assistant:CreateMailControl(root, "dropdown", { width = 68, height = 30, items = reserves, value = 0,
        onChange = function(_, value) Assistant:GetConfiguration().bagReserve = value; Inbox:RefreshView() end })
    ui.reserve:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    ui.notice = GUI2:CreatePanel(root, { surface = "color.control.bg", border = "color.state.warning" })
    ui.notice:Hide()
    ui.noticeIcon = GUI2:CreateMicroIcon(ui.notice, { iconName = "alert-triangle", size = 16, colorKey = "color.state.warning",
        point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -10 })
    ui.noticeIcon:ClearAllPoints(); ui.noticeIcon:SetPoint("TOPLEFT", ui.notice, "TOPLEFT", 10, -10)
    Text("status", -222, 13, "color.text.secondary")
    ui.progress = GUI2:CreateText(root, "", 12, "color.text.primary", "LEFT")
    ui.progress:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 86)
    ui.progress:SetWordWrap(false)
    ui.texts[#ui.texts + 1] = ui.progress
    ui.progressBar = GUI2.Data:CreateProgressBar(root, { width = panel:GetWidth() - 24, height = 12, value = 0, animate = false })
    ui.progressBar:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 64)
    ui.remaining = GUI2:CreateText(root, "", 12, "color.text.secondary", "LEFT")
    ui.remaining:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 86)
    ui.remaining:SetWidth(100)
    ui.remaining:SetJustifyH("RIGHT")
    ui.remaining:SetWordWrap(false)
    ui.texts[#ui.texts + 1] = ui.remaining
    ui.earned = GUI2:CreateText(root, "", 12, "color.text.secondary", "LEFT")
    ui.earned:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 44)
    ui.texts[#ui.texts + 1] = ui.earned
    Button("stop", T("inbox.stop", "Stop"), 0, -88, 170, function() Inbox:Stop("stopped") end, "square")
    ui.shield = GUI2:CreateFrame(_G.InboxFrame, {})
    ui.shield:SetAllPoints(_G.InboxFrame)
    ui.shield:SetFrameLevel(_G.InboxFrame:GetFrameLevel() + 30)
    ui.shield:EnableMouse(true)
    ui.shield:EnableMouseWheel(true)
    ui.shield:Hide()
    for index = 1, 7 do
        local rowRoot = GUI2:CreateFrame(_G.MailFrame, {})
        rowRoot:EnableMouse(false)
        rowRoot:Hide()
        local checkbox = GUI2.Form:CreateCheckbox(rowRoot, { text = "", width = CHECK_SIZE, height = CHECK_SIZE,
            onChange = function(check, value)
                local button = _G["MailItem" .. index .. "Button"]
                Inbox:Select(button and button.index, value, _G.IsShiftKeyDown and _G.IsShiftKeyDown())
            end })
        checkbox.box:ClearAllPoints()
        checkbox.box:SetPoint("CENTER")
        checkbox.box:SetSize(16, 16)
        checkbox:SetPoint("RIGHT", rowRoot, "RIGHT", -CHECK_INSET, 0)
        checkbox.rowRoot = rowRoot
        checkbox.selection = GUI2:CreateTexture(rowRoot, { layer = "BACKGROUND" })
        checkbox.selection:SetPoint("TOPLEFT", rowRoot, "TOPLEFT", 43, -1)
        checkbox.selection:SetPoint("BOTTOMRIGHT", rowRoot, "BOTTOMRIGHT", -2, 2)
        checkbox.selection:Hide()
        self.checks[index] = checkbox
    end
    self:ApplyAppearance(self.appearanceContext)
    self:RefreshView()
end

local function MailUpdate() if Inbox.open then Inbox:Schedule() end end
local function MailFailure()
    if Inbox.model.pending then Inbox:Stop("error") end
end
local function ForeignAction()
    if Inbox.open and not Inbox.issuing then
        local snapshot = Inbox:Capture()
        Inbox.loading = snapshot == nil
        if Inbox.model:IsBusy() then
            Inbox.model:Invalidate(snapshot or {}, "changed")
            Inbox:CancelTimer()
        elseif snapshot then
            -- A native click on a text-only letter may issue a no-op loot call.
            -- Preserve selection until a real snapshot change is observed.
            Inbox.model:Observe(snapshot)
        end
        if not snapshot then Inbox:Schedule() end
        Inbox:RefreshView()
    end
end
local function NativeOpening(value)
    Inbox.nativeBusy = value == true
    if Inbox.open then
        if value and Inbox.model:IsBusy() then Inbox:Stop("native_busy") end
        Inbox:RefreshView()
    end
end
local function InboxPaint()
    if Inbox.open then Inbox:RefreshView(); Inbox:Schedule() end
end
local function TabChanged()
    if not Inbox.open then return end
    if Inbox:Availability() and Inbox.model:IsBusy() then Inbox:Stop("stopped") end
    Assistant:ApplyPanelVisibility()
    Inbox:Schedule()
end

function Inbox:EnsureHooks()
    Compatibility:EnsureHooks()
    if self.hooked or not Compatibility:HasNativeInbox() then return end
    self.hooked = true
    local target, method = Compatibility:GetInboxRefreshTarget()
    if target then Security.SafeHook("MailAssistant:InboxPaint", target, method, InboxPaint) end
    Security.SafeHook("MailAssistant:NativeOpening", _G.C_Mail, "SetOpeningAll", NativeOpening)
    for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem", "ReturnInboxItem", "DeleteInboxItem" }) do
        if type(_G[name]) == "function" then Security.SafeHook("MailAssistant:" .. name, _G, name, ForeignAction) end
    end
    _G.InboxFrame:HookScript("OnShow", TabChanged)
    _G.SendMailFrame:HookScript("OnShow", TabChanged)
    if _G.OpenMailFrame then
        _G.OpenMailFrame:HookScript("OnShow", TabChanged)
        _G.OpenMailFrame:HookScript("OnHide", TabChanged)
    end
end

function Inbox:Close()
    self:CancelDelete()
    self.open, self.nativeBusy, self.loading, self.awaitClear = false, false, false, false
    self.loadingSince = nil
    self:CancelTimer()
    Event:OffOwner(sessionOwner)
    self.model:Reset()
    self:RefreshView()
end

function Inbox:Open()
    if not self.enabled then return end
    self:Close()
    self.open = true
    Assistant.runtime.temporarilyClosed = false
    Assistant:EnsureUI()
    self:EnsureHooks()
    self:EnsureUI()
    Assistant:RegisterPanelLayout()
    local snapshot = self:Capture()
    self.loading = snapshot == nil
    self.model:Reset(snapshot or {})
    Event:On("MAIL_INBOX_UPDATE", MailUpdate, sessionOwner)
    Event:On("MAIL_SUCCESS", MailUpdate, sessionOwner)
    Event:On("BAG_UPDATE_DELAYED", MailUpdate, sessionOwner)
    Event:On("MAIL_FAILED", MailFailure, sessionOwner)
    Event:On("PLAYER_REGEN_DISABLED", TabChanged, sessionOwner)
    Event:On("PLAYER_REGEN_ENABLED", MailUpdate, sessionOwner)
    Assistant:RefreshAppearance()
    Assistant:ApplyPanelVisibility()
end

local function OnOpen() Inbox:Open() end
local function OnClose() Inbox:Close() end
local function OnAddon()
    if Inbox.enabled then Inbox:EnsureHooks() end
    if Inbox.open then Assistant:ApplyPanelVisibility(); Inbox:Schedule() end
end

function Inbox:SetEnabled(enabled)
    if self.enabled == enabled then return end
    self.enabled = enabled
    if enabled then
        Event:On("MAIL_SHOW", OnOpen, owner)
        Event:On("MAIL_CLOSED", OnClose, owner)
        Event:On("ADDON_LOADED", OnAddon, owner)
        self:EnsureHooks()
        if Shown(_G.MailFrame) then self:Open() end
    else
        Event:OffOwner(owner)
        self:Close()
    end
end

function Inbox:GetStats()
    return { enabled = self.enabled, open = self.open, state = self.model.state,
        mode = self.model.batchMode, pendingDeletionReview = self.deleteApproval ~= nil,
        selected = self.model:CountSelected(), completed = self.model.completed,
        total = self.model.total, remaining = math.max(0, self.model.total - self.model.completed),
        pendingTimers = self.timer and 1 or 0, pendingCommand = self.model.pending ~= nil,
        checkboxCount = #self.checks }
end

Inbox:SetEnabled(Assistant.runtime.enabled == true)
