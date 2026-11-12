local addonName = ...
local YUI = _G.YUI
if addonName ~= "YUI" or not YUI then return end
local E, GUI, Report = YUI.ErrorRecorder, YUI.GUI, YUI.ErrorReport
local L, LC = YUI.Locale:Get("ErrorRecorder"), YUI.Locale:Get("Core")
local ROW_HEIGHT, POOL_SIZE = 60, 9
local function Button(parent, text, width, click)
    return GUI.Form:CreateButton(parent, { text = text, width = width, height = 28, onClick = click })
end
local function Text(region, value)
    if region:GetText() ~= value then region:SetText(value) end
end

function E:SessionOptions()
    local options, collector = {}, self:GetCollector()
    local current = collector.current
    local sessions = collector:GetSessions()
    for i = #sessions, 1, -1 do
        local session = sessions[i]
        if #session.records > 0 then
            options[#options + 1] = { value = session.id, text = session == current and L["current"]:format(#session.records)
                or L["history"]:format(date("%m-%d %H:%M", session.started), #session.records) }
        end
    end
    return options
end
function E:SelectSession(id)
    self.selectedSession = self:GetCollector().current
    for _, session in ipairs(self:GetCollector():GetSessions()) do
        if session.id == id then self.selectedSession = session; break end
    end
    self.selectedIndex, self.copyAll, self.selectedRecord = 1, false, nil
    self.list:SetVerticalScroll(0)
    self:RefreshView(true)
end
function E:SelectRecord(index)
    local records = self.viewRecords or {}
    if index < 1 or index > #records then return end
    self.selectedIndex, self.copyAll = index, false
    self.selectedRecord = records[index]
    self:RevealSelectedRow()
    self:RefreshRows()
    self:ShowReport(true)
end
function E:RevealSelectedRow()
    local top = ((self.selectedIndex or 1) - 1) * ROW_HEIGHT
    local offset, height = self.list:GetVerticalScroll(), self.list:GetHeight()
    if top < offset then self.list:SetVerticalScroll(top)
    elseif top + ROW_HEIGHT > offset + height then self.list:SetVerticalScroll(top + ROW_HEIGHT - height) end
end
function E:UpdateCopyHint()
    local hasText = self.rawReport and self.rawReport ~= ""
    local focused = self.edit and self.edit:HasFocus()
    if not focused and self.copySelectionVisible and not self.selectingCopy then self:SetCopySelectionVisible(false) end
    Text(self.copyHint, hasText and (focused and (self.copySelectionVisible and L["copy.selected"] or L["copy_hint"]) or L["copy_focus"]) or "")
    if self.copyFocused ~= focused then
        self.copyFocused = focused
        GUI:SetBorderColor(self.reportPanel, focused and "color.border.focus" or "color.border.subtle")
    end
end
function E:SetCopySelectionVisible(visible)
    visible = visible == true and self.rawReport ~= nil and self.rawReport ~= ""
    local wasVisible = self.copySelectionVisible
    self.copySelectionVisible = visible
    if visible ~= wasVisible then
        if visible then self.readerScrollOffset = self.reportScroll:GetVerticalScroll() end
        local child = visible and self.edit or self.reportContent
        self.reportScroll.child, self.reportScroll.scrollChild = child, child
        self.reportScroll:SetScrollChild(child)
        self.reportContent:SetShown(not visible)
        self.edit:SetAlpha(visible and 1 or 0); self.edit:Show()
        local range = math.max(0, self.reportContent:GetHeight() - self.reportScroll:GetHeight())
        self.reportScroll:SetVerticalScroll(visible and 0 or math.min(self.readerScrollOffset or 0, range))
    end
    local r, g, b = GUI:GetColor("color.accent.primary")
    self.edit:SetHighlightColor(r, g, b, visible and .45 or 0)
end
function E:FocusReport(showSelection)
    if showSelection ~= true and not self.copySelectionVisible then self:ReleaseCopyFocus(); return end
    if self.rawReport and self.rawReport ~= "" then
        self.selectingCopy = true
        if showSelection ~= nil then self:SetCopySelectionVisible(showSelection) end
        self.edit:SetFocus(); self.edit:HighlightText(0)
        self.selectingCopy = nil
    end
    self:UpdateCopyHint()
end
function E:ReleaseCopyFocus()
    self.copyChordKey = nil
    self.edit:ClearFocus()
    if self.copySelectionVisible then self:SetCopySelectionVisible(false) end
    self:UpdateCopyHint()
end
function E:RefreshTheme()
    self.renderedRevision = nil
    if self.reportText then
        self.reportText:SetFont(GUI:GetFont("font.family.body"), GUI:GetMetric("font.size.md", 13), "")
        self.edit:SetFont(GUI:GetFont("font.family.body"), GUI:GetMetric("font.size.md", 13), "")
        self:SetCopySelectionVisible(self.copySelectionVisible)
    end
    if self.active and self.window and self.window:IsShown() then self:ShowReport(false) end
end
function E:ShowReport(selectText, showSelection)
    local collector, session = self:GetCollector(), self.selectedSession
    local records = self.viewRecords or {}
    local stored = session and session.records
    local record = records[self.selectedIndex or 1]
    self.selectedRecord = record
    self.previous:SetDisabled(not record or self.selectedIndex <= 1)
    self.next:SetDisabled(not record or self.selectedIndex >= #records)
    self.copyButton:SetDisabled(#records == 0)
    Text(self.counter, #records == 0 and "0 / 0" or (self.selectedIndex .. " / " .. #records))
    local heading = record and Report:Heading(record) or Report:Literal(L["empty"])
    Text(self.related, self.copyAll and Report:Literal(L["all_selected"]) or heading)
    local latest = self.copyAll and records[1] or record
    Text(self.meta, latest and (self.copyAll and L["session_meta"]:format(session.build, #records, date("%H:%M:%S", latest.last))
        or Report:Meta(record, session)) or "")
    local revision = self.copyAll and session == collector.current and collector.diagnostics.captured or 0
    local changed = self.renderedRecord ~= record or self.renderedSession ~= session or self.renderedAll ~= self.copyAll
        or self.renderedCount ~= (record and record.count) or self.renderedLast ~= (record and record.last)
        or self.renderedStack ~= (record and record.stack) or self.renderedLocals ~= (record and record.locals)
        or self.renderedRecords ~= stored or self.renderedFirst ~= records[1] or self.renderedTail ~= records[#records]
        or self.renderedRevision ~= revision
    if changed then
        local raw, readable = "", ""
        if self.copyAll then
            local parts = {}
            for i, item in ipairs(records) do parts[i] = Report:Format(collector, item, session) end
            raw, readable = table.concat(parts, "\n\n--------------------\n\n"), Report:ReadableSession(session, records)
        elseif record then raw, readable = Report:Format(collector, record, session), Report:Readable(record) end
        local hadFocus = self.edit:HasFocus()
        self.rawReport = raw
        if self.edit:GetText() ~= raw then
            self.settingReport = true; self.edit:SetText(raw); self.settingReport = nil
            if hadFocus and raw ~= "" then self:FocusReport() end
        end
        if self.reportText:GetText() ~= readable then
            self.reportText:SetText(readable); self.reportText:SetHeight(0)
            self.reportContent:SetHeight(math.max(self.reportScroll:GetHeight(), self.reportText:GetStringHeight() + 16))
        end
        self.renderedRecord, self.renderedSession, self.renderedAll = record, session, self.copyAll
        self.renderedCount, self.renderedLast = record and record.count, record and record.last
        self.renderedStack, self.renderedLocals = record and record.stack, record and record.locals
        self.renderedRecords, self.renderedFirst, self.renderedTail = stored, records[1], records[#records]
        self.renderedRevision = revision
    end
    if selectText and record then
        if showSelection == true then self:FocusReport(true) else self:ReleaseCopyFocus() end
        self.reportScroll:SetVerticalScroll(0)
    elseif not record then self:ReleaseCopyFocus() end
    self:UpdateCopyHint()
end
function E:RefreshRows()
    local records = self.viewRecords or {}
    local first = math.floor(self.list:GetVerticalScroll() / ROW_HEIGHT) + 1
    for i, row in ipairs(self.rows) do
        local index = first + i - 1
        local record = records[index]
        row:SetShown(record ~= nil)
        if record then
            row.index = index
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row.addon:SetText(Report:ListLabel(record))
            row.summary:SetText(Report:Literal(Report:Summary(record)))
            row.count:SetText("×" .. Report:Count(record))
            row.gui2Surface = index == self.selectedIndex and "color.accent.fill" or "color.surface.panel"
            GUI:RefreshPrimitive(row)
        end
    end
end
function E:RefreshView(selectText)
    if not self.window or not self.window:IsShown() then return end
    self.refreshes = self.refreshes + 1
    local collector = self:GetCollector()
    local found = self.selectedSession == collector.current
    for _, session in ipairs(collector:GetSessions()) do if session == self.selectedSession then found = true; break end end
    if not found then self.selectedSession = collector.current; self.selectedRecord = nil; selectText = selectText or self.edit:HasFocus() end
    local records = Report:Ordered(self.selectedSession and self.selectedSession.records or {})
    self.viewRecords = records
    if #records == 0 then self.copyAll = false end
    local selected
    for i, record in ipairs(records) do if record == self.selectedRecord then selected = i; break end end
    self.selectedIndex = selected or 1
    -- An empty reader may select its first arriving record; existing selections stay put.
    if not selected then selectText = self.edit:HasFocus() or selectText end
    self.sessionControl:RefreshOptions()
    self.sessionControl:SetValue(self.selectedSession.id, true)
    self.sessionControl:SetDisabled(#collector:GetSessions() == 0)
    self.list.child:SetHeight(math.max(1, #records * ROW_HEIGHT))
    self.empty:SetShown(#records == 0)
    self.clearButton:SetDisabled(self.selectedSession ~= collector.current or collector:GetCount() == 0)
    if selectText then self:RevealSelectedRow() end
    self:RefreshRows(); self:ShowReport(selectText)
end
function E:ConfirmClearHistory()
    if self.moreMenu then self.moreMenu:Hide() end
    self:ReleaseCopyFocus()
    if not self.confirm then
        self.confirm = GUI.Overlay:CreateConfirmDialog(self.window, { title = L["clear_history"], body = L["clear_confirm"],
            confirmText = LC["common.confirm"], cancelText = LC["common.cancel"],
            onAccept = function() E:GetCollector():ClearHistory(); E.selectedSession = nil; E:RefreshView(true) end })
        self.confirm:SetPoint("CENTER", self.window, "CENTER")
    end
    -- Keep the panel and its existing controls in one strata above the owner.
    self.confirm:SetFrameStrata(self.window:GetFrameStrata())
    self.confirm:SetFrameLevel(self.window:GetFrameLevel() + 30)
    self.confirm:Open()
end
function E:EnsureView()
    if self.window then return end
    local width, height = 960, 570
    local window = GUI:CreatePanel(UIParent, { width = width, height = height,
        surface = "color.surface.window", border = "color.border.default", shadow = true })
    self.window = window
    window:Hide(); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG")
    window:SetToplevel(true); window:EnableMouse(true); window:SetClampedToScreen(true); window:SetMovable(true)
    window:SetScale(math.min(1, (UIParent:GetWidth() - 32) / width, (UIParent:GetHeight() - 32) / height))
    local drag = GUI:CreateFrame(window, { width = width - 70, height = 38 })
    drag:SetPoint("TOPLEFT"); drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() window:StartMoving() end)
    drag:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    local icon = GUI:CreateTexture(window, { texture = self:GetIcon(), layer = "ARTWORK" })
    icon:SetSize(28, 28); icon:SetPoint("TOPLEFT", 14, -8); self.icons[#self.icons + 1] = icon
    local title = GUI:CreateText(window, L["name"], "font.size.lg", "color.text.heading")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    local close = Button(window, "×", 28, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -8)
    self.sessionControl = GUI.Form:CreateDropdown(window, { width = 230, height = 28,
        options = function() return E:SessionOptions() end,
        getLabel = function(id)
            local current = E:GetCollector().current
            if id == current.id then return L["current"]:format(#current.records) end
        end,
        get = function() return E.selectedSession and E.selectedSession.id end,
        set = function(id) E:SelectSession(id) end })
    self.sessionControl:SetPoint("TOPLEFT", 14, -48)
    self.clearButton = Button(window, L["clear"], 100, function()
        local collector = E:GetCollector()
        if E.selectedSession ~= collector.current then return end
        collector:ClearCurrent(); E:RefreshView(true)
    end)
    self.clearButton:SetPoint("TOPRIGHT", -96, -48)
    local more = Button(window, L["more"], 74, function()
        if not E.moreMenu then
            local panel = GUI:CreatePanel(window, { width = 184, height = 46, surface = "color.surface.popup", border = "color.popup.border" })
            E.moreMenu = panel; panel:SetFrameLevel(window:GetFrameLevel() + 20)
            panel:SetPoint("TOPRIGHT", -14, -80)
            local clear = Button(panel, L["clear_history"], 168, function() E:ConfirmClearHistory() end)
            clear:SetPoint("CENTER")
        else E.moreMenu:SetShown(not E.moreMenu:IsShown()) end
    end)
    more:SetPoint("TOPRIGHT", -14, -48)
    local left = GUI:CreatePanel(window, { width = 268, height = 420, surface = "color.surface.panel", border = "color.border.subtle" })
    left:SetPoint("TOPLEFT", 14, -88)
    self.list = GUI:CreateScrollFrame(left, { width = 244, height = 404, childWidth = 244, childHeight = 1, mouseWheel = true })
    self.list:SetPoint("TOPLEFT", 6, -8)
    self.list:HookScript("OnVerticalScroll", function() E:RefreshRows() end)
    self.rows = {}
    for i = 1, POOL_SIZE do
        local row = GUI:CreateButtonFrame(self.list.child, { width = 240, height = ROW_HEIGHT - 2, template = "BackdropTemplate" })
        GUI:ApplyBackdrop(row, "color.surface.panel")
        row.addon = GUI:CreateText(row, "", "font.size.md", "color.text.heading")
        row.addon:SetPoint("TOPLEFT", 8, -7); row.addon:SetWidth(188); row.addon:SetWordWrap(false); row.addon:SetJustifyH("LEFT")
        row.count = GUI:CreateText(row, "", "font.size.sm", "color.text.secondary")
        row.count:SetPoint("TOPRIGHT", -6, -8)
        row.summary = GUI:CreateText(row, "", "font.size.sm", "color.text.secondary")
        row.summary:SetPoint("TOPLEFT", 8, -29); row.summary:SetWidth(224); row.summary:SetWordWrap(false); row.summary:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(owner) E:SelectRecord(owner.index) end)
        row:Hide(); self.rows[i] = row
    end
    self.empty = GUI:CreateText(left, L["empty"], "font.size.md", "color.text.secondary")
    self.empty:SetPoint("CENTER"); self.empty:SetWidth(230); self.empty:SetWordWrap(true)
    self.related = GUI:CreateText(window, "", "font.size.md", "color.text.heading")
    self.related:SetPoint("TOPLEFT", 300, -92); self.related:SetWidth(642); self.related:SetHeight(20); self.related:SetWordWrap(false); self.related:SetJustifyH("LEFT")
    self.meta = GUI:CreateText(window, "", "font.size.sm", "color.text.secondary")
    self.meta:SetPoint("TOPLEFT", 300, -117); self.meta:SetWidth(642); self.meta:SetWordWrap(false); self.meta:SetJustifyH("LEFT")
    self.reportPanel = GUI:CreatePanel(window, { width = 642, height = 366, surface = "color.control.bg", border = "color.border.subtle" })
    self.reportPanel:SetPoint("TOPLEFT", 300, -140); self.reportPanel:EnableMouse(true)
    self.reportPanel:SetScript("OnMouseDown", function() E:FocusReport(true) end)
    self.reportScroll = GUI:CreateScrollFrame(self.reportPanel, { width = 618, height = 350, childWidth = 618, childHeight = 350, mouseWheel = true })
    self.reportScroll:SetPoint("TOPLEFT", 8, -8); self.reportScroll:EnableMouse(true)
    self.reportScroll:SetScript("OnMouseDown", function() E:FocusReport(true) end)
    self.reportContent = self.reportScroll.child
    self.reportText = GUI:CreateText(self.reportContent, "", "font.size.md", "color.text.primary", "LEFT")
    self.reportText:SetPoint("TOPLEFT", 0, -4); self.reportText:SetWidth(612); self.reportText:SetWordWrap(true); self.reportText:SetSpacing(3)
    self.reportText:SetFont(GUI:GetFont("font.family.body"), GUI:GetMetric("font.size.md", 13), "")
    self.reportText:SetShadowColor(0, 0, 0, 0); self.reportText:SetShadowOffset(0, 0)
    -- Reading and native text selection share one clipped viewport and one scrollbar.
    self.edit = GUI.Form:CreateEditBox(self.reportScroll, { width = 612, height = 26, autoFocus = false })
    self.edit:SetTextInsets(0, 0, 4, 0); self.edit:EnableMouse(false)
    if self.edit.gui2Bg then self.edit.gui2Bg:SetAlpha(0) end
    self.edit:SetHighlightColor(0, 0, 0, 0)
    self.edit:SetMultiLine(true); self.edit:SetMaxLetters(0)
    self.reportScroll:SetScrollChild(self.edit)
    self:SetCopySelectionVisible(false)
    self.edit:SetScript("OnEscapePressed", function() E:ReleaseCopyFocus() end)
    self.edit:HookScript("OnEditFocusGained", function() E:UpdateCopyHint() end)
    self.edit:HookScript("OnEditFocusLost", function() E.copyChordKey = nil; E:UpdateCopyHint() end)
    self.edit:HookScript("OnKeyDown", function(_, key)
        if key == "C" and IsControlKeyDown() then E.copyChordKey = key end
    end)
    self.edit:HookScript("OnKeyUp", function(_, key)
        if E.copyChordKey == key then E:ReleaseCopyFocus() end
    end)
    self.edit:SetScript("OnCursorChanged", function()
        if not E.settingReport and not E.selectingCopy and E.edit:HasFocus() then E:FocusReport() end
    end)
    self.edit:HookScript("OnTextChanged", function(owner)
        if not E.settingReport and E.rawReport and owner:GetText() ~= E.rawReport then
            E.settingReport = true; owner:SetText(E.rawReport); E.settingReport = nil
            if owner:HasFocus() then E:FocusReport() end
        end
    end)
    self.copyHint = GUI:CreateText(window, "", "font.size.sm", "color.text.secondary")
    self.copyHint:SetPoint("BOTTOMLEFT", 300, 18)
    self.copyButton = Button(window, L["copy_all"], 100, function() E.copyAll = true; E:ShowReport(true, true) end)
    self.copyButton:SetPoint("BOTTOMRIGHT", -14, 14)
    self.next = Button(window, L["next"], 80, function() E:SelectRecord(E.selectedIndex + 1) end)
    self.next:SetPoint("RIGHT", self.copyButton, "LEFT", -10, 0)
    self.counter = GUI:CreateText(window, "0 / 0", "font.size.sm", "color.text.secondary")
    self.counter:SetPoint("RIGHT", self.next, "LEFT", -8, 0); self.counter:SetWidth(68); self.counter:SetJustifyH("CENTER")
    self.previous = Button(window, L["previous"], 80, function() E:SelectRecord(E.selectedIndex - 1) end)
    self.previous:SetPoint("RIGHT", self.counter, "LEFT", -8, 0)
    GUI:EnableEscapeClose(window, function() window:Hide() end)
    window:SetScript("OnHide", function()
        E:ReleaseCopyFocus(); window:StopMovingOrSizing()
        if E.pendingRefresh then E.pendingRefresh:Cancel(); E.pendingRefresh = nil end
        if E.confirm then E.confirm:Hide() end
        if E.moreMenu then E.moreMenu:Hide() end
    end)
    GUI:RegisterThemeObject(self)
end
function E:Open()
    if not self:IsEnabled() then return end
    self:EnsureView()
    self.selectedSession, self.copyAll = self:GetCollector().current, false
    self.selectedIndex, self.selectedRecord = 1, nil
    self.window:Show(); self.window:Raise(); self:RefreshView(true)
end
function E:Toggle()
    if self.window and self.window:IsShown() then self.window:Hide() else self:Open() end
end
