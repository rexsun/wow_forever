local ADDON_NAME = ...
local YUI = _G.YUI
local Assistant = YUI and YUI.MailAssistant
if not (Assistant and Assistant.MailLog) then return end
local GUI, Appearance, Model = YUI.GUI2, YUI.GUI2.WindowAppearance, Assistant.MailLogModel
local unpack = _G.unpack or table.unpack
local View = { filter = { direction = "all", character = "all", days = 7, query = "" }, page = 1 }
Assistant.MailLogView = View
local WIDTH, HEIGHT, PAGE_SIZE = 760, 494, 8
local NATIVE_LIST = {
    background = { 0.129, 0.106, 0.086, 1 },
    grain = { 0.60, 0.52, 0.40, 0.07 },
    header = { 0.18, 0.145, 0.11, 0.7 },
    primary = { 0.90, 0.87, 0.81, 1 },
    secondary = { 0.73, 0.66, 0.55, 1 },
    success = { 0.34, 0.72, 0.40, 1 },
    warning = { 0.94, 0.74, 0.30, 1 },
    accent = { 0.80, 0.70, 0.30, 1 },
    highlight = { 0.75, 0.61, 0.35, 0.12 },
    divider = { 0.53, 0.39, 0.23, 0.32 },
}
local COLUMNS = { { "time", 0, 106 }, { "direction", 110, 52 }, { "party", 166, 162 },
    { "contents", 332, 276 }, { "status", 612, 104 } }
local function T(key, fallback) return Assistant:Translate(key, fallback) end
local function Money(value)
    local format = _G.GetMoneyString or _G.GetCoinTextureString
    if format then return format(value or 0) end
    value = math.floor(value or 0)
    local parts, gold, silver, copper = {}, math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    if gold > 0 then parts[#parts + 1] = gold .. (_G.GOLD_AMOUNT_SYMBOL or "g") end
    if silver > 0 then parts[#parts + 1] = silver .. (_G.SILVER_AMOUNT_SYMBOL or "s") end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. (_G.COPPER_AMOUNT_SYMBOL or "c") end
    return table.concat(parts, " ")
end
local function Stamp(value, full) return _G.date(full and "%Y-%m-%d %H:%M:%S" or "%m/%d %H:%M", value) end
local function Status(entry) return T("log.status." .. entry.status, entry.status) end
local function Tone(entry) return entry.status == "partial" and "color.state.warning"
    or entry.direction == "out" and "color.text.accent" or "color.state.success" end
local function Text(parent, value, size, tone, x, y, width)
    local text = GUI:CreateText(parent, value, size or 13, tone or "color.text.primary", "LEFT")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    text:SetWidth(width or 100)
    text:SetWordWrap(false)
    return text
end

local function ListColor(label, tone, native)
    if native then
        local role = tone == "color.state.success" and "success" or tone == "color.state.warning" and "warning"
            or tone == "color.text.accent" and "accent" or tone == "color.text.secondary" and "secondary" or "primary"
        label:SetTextColor(unpack(NATIVE_LIST[role]))
    else GUI:SetTextColorKey(label, tone or "color.text.primary") end
end

local function ListFont(label, context)
    Appearance:ApplyFont(label, context)
    if context and context.source == "native" then
        local path, size = label:GetFont()
        label:SetFont(path, math.max(14, size), "")
        label:SetShadowOffset(0, 0)
        label:SetShadowColor(0, 0, 0, 0)
    end
end

local function AccentText(label, r, g, b)
    label:SetTextColor(r, g, b, 1)
end

local function ClassText(value, classFile)
    if not classFile then return value end
    local r, g, b = Assistant:GetMailClassColor(classFile)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), value)
end

local function PartyColor(label, classFile, context)
    ListFont(label, context)
    ListColor(label, "color.text.primary", context and context.source == "native")
    if classFile then AccentText(label, Assistant:GetMailClassColor(classFile)) end
end

local function ItemColor(label, item, context)
    ListFont(label, context)
    ListColor(label, "color.text.primary", context and context.source == "native")
    local color = item and item.link and item.link:match("|c%x%x(%x%x%x%x%x%x)")
    if color then
        AccentText(label, tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255)
    elseif item and not item.currency then
        local api = YUI.API.Item
        if not (api and api.GetInfo and api.GetQualityColor) then return end
        local ok, info = pcall(api.GetInfo, item.link or item.id)
        if not ok or type(info) ~= "table" or YUI.API.Security.IsSecretValue(info.quality)
            or type(info.quality) ~= "number" then return end
        local colorOK, r, g, b = pcall(api.GetQualityColor, info.quality)
        if colorOK and not YUI.API.Security.IsSecretValue(r) and not YUI.API.Security.IsSecretValue(g)
            and not YUI.API.Security.IsSecretValue(b) and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            AccentText(label, r, g, b)
        end
    end
end

function View:FitTooltip(tip)
    tip:SetScale(1)
    local height = tip:GetHeight()
    if height and height > 0 then
        local available = (_G.UIParent:GetHeight() - 24) * _G.UIParent:GetEffectiveScale()
        tip:SetScale(math.min(1, available / (height * self.window:GetEffectiveScale())))
    end
end

function View:HideTooltip()
    self.hovered = nil
    if self.tip then self.tip:Hide() end
    if self.nativeTip then self.nativeTip:Hide() end
end

function View:DetailLines(entry)
    local party, classFile = Assistant:GetMailLogParty(entry.party)
    local _, characterClass = Assistant:GetMailLogParty(entry.character)
    local lines = {
        { entry.subject ~= "" and entry.subject or T("log.no_subject", "(No subject)"), "color.text.heading" },
        { T("log.party", "Other party") .. ": " .. ClassText(party, classFile) },
        { T("log.character", "Character") .. ": " .. ClassText(entry.character, characterClass) },
        { Stamp(entry.at, true), "color.text.secondary" },
    }
    for _, item in ipairs(entry.items) do
        lines[#lines + 1] = { (item.icon and ("|T" .. item.icon .. ":18:18|t ") or "")
            .. (item.link or item.name or ("#" .. item.id)) .. " × " .. item.count }
    end
    if entry.gold > 0 then lines[#lines + 1] = { T("log.gold", "Gold") .. ": " .. Money(entry.gold) } end
    if (entry.cod or 0) > 0 then
        lines[#lines + 1] = { T(entry.direction == "out" and "log.cod.requested" or "log.cod.paid",
            entry.direction == "out" and "COD requested" or "COD paid") .. ": " .. Money(entry.cod), "color.state.warning" }
    end
    if entry.direction == "out" then
        lines[#lines + 1] = { T("log.postage", "Postage") .. ": " .. Money(entry.postage), "color.text.secondary" }
        lines[#lines + 1] = { T("log.sent_hint", "Sent successfully; recipient collection is unknown."), "color.text.secondary" }
    else
        if entry.status == "partial" then
            lines[#lines + 1] = { string.format(T("log.remaining", "%d attachments left"), entry.remainingItems or 0)
                .. ((entry.remainingGold or 0) > 0 and (" · " .. Money(entry.remainingGold)) or ""), "color.state.warning" }
        end
        lines[#lines + 1] = { T("log.actual_hint", "Only confirmed collections are recorded."), "color.text.secondary" }
    end
    return lines
end

function View:ShowTooltip(row)
    self:HideTooltip()
    if not row.record then return end
    self.hovered = row
    local lines = self:DetailLines(row.record)
    if self.context and self.context.source == "native" then
        if not self.nativeTip then
            self.nativeTip = _G.CreateFrame("GameTooltip", ADDON_NAME .. "_MailHistoryTooltip", self.window, "GameTooltipTemplate")
            self.nativeTip:SetClampedToScreen(true)
        end
        local tip = self.nativeTip
        tip:SetOwner(row, "ANCHOR_RIGHT")
        tip:ClearLines()
        for index, line in ipairs(lines) do
            local r, g, b = GUI:GetColor(line[2] or "color.text.primary")
            if index == 1 and _G.NORMAL_FONT_COLOR then
                local color = _G.NORMAL_FONT_COLOR; r, g, b = color.r, color.g, color.b
            end
            tip:AddLine(line[1], r, g, b, true)
        end
        tip:Show()
        self:FitTooltip(tip)
        return
    end
    if not self.tip then
        self.tip = GUI:CreatePanel(self.window, { width = 370, height = 160,
            surface = "color.surface.popup", border = "color.border.accent" })
        self.tip:SetFrameStrata("TOOLTIP")
        self.tip:SetClampedToScreen(true)
        self.tip:EnableMouse(false)
        self.tip.lines = {}
    end
    local tip = self.tip
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 280, 6)
    local height = 12
    for index, line in ipairs(lines) do
        local label = tip.lines[index]
        if not label then label = Text(tip, "", 13, nil, 12, 0, 346); tip.lines[index] = label end
        label:ClearAllPoints(); label:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -height)
        label:SetText(line[1]); label:SetWordWrap(true)
        GUI:SetTextColorKey(label, line[2] or "color.text.primary")
        Appearance:ApplyFont(label, self.context)
        label:Show()
        height = height + math.max(18, label:GetStringHeight()) + (index == 1 and 7 or 4)
    end
    for index = #lines + 1, #tip.lines do tip.lines[index]:Hide() end
    tip:SetHeight(height + 8)
    self:FitTooltip(tip)
    tip:Show()
end

function View:ClearFilters()
    self.filter = { direction = "all", character = "all", days = 0, query = "" }
    self.dateRange:Hide()
    self.search:SetValue("", true)
    self.characters:SetValue("all", true)
    self.dates:SetValue(0, true)
    self.page = 1
    self:Refresh()
end

function View:ChangePage(delta)
    self.page = math.max(1, math.min(self.page + delta, self.pages or 1))
    self:Refresh()
end

function View:CancelClear()
    self.clearRequest = nil
    if self.clearOverlay then self.clearOverlay:Hide() end
end

function View:RequestClear()
    local store = Assistant.MailLog:GetStore()
    if not self.window or not self.window:IsShown() or not store or #store.records == 0 then return false end
    self:EnsureClearDialog()
    self:HideTooltip(); self.dateRange:Hide()
    self.search.modern:ClearFocus(); if self.search.native then self.search.native:ClearFocus() end
    self.clearRequest = { store = store, nextId = store.nextId, count = #store.records }
    self.clearMessage:SetText(string.format(T("log.clear.confirm", "Permanently clear all %d mail history records for every character?\n\nFilters do not limit this action. Mail and contacts are kept."), #store.records))
    Appearance:Refresh(self.clearDialog)
    self.clearOverlay:Show()
    return true
end

function View:ConfirmClear()
    local request, store = self.clearRequest, Assistant.MailLog:GetStore()
    if not request then return false end
    if store ~= request.store or store.nextId ~= request.nextId or #store.records ~= request.count then
        self:CancelClear(); self:RequestClear()
        return false
    end
    self:CancelClear()
    return Assistant:ClearMailLog()
end

function View:OnLogCleared()
    self:CancelClear(); self:HideTooltip()
    self.rows, self.goldIn, self.goldOut, self.page, self.pages = {}, 0, 0, 1, 1
    if self.window then
        for _, row in ipairs(self.rowFrames) do row.record, row.partyClass = nil, nil; row:Hide() end
        self:ClearFilters()
    else self.filter = { direction = "all", character = "all", days = 0, query = "" } end
end

function View:Refresh()
    if not self.window or not self.window:IsShown() or self.building then return end
    self:HideTooltip()
    local store = Assistant.MailLog:GetStore()
    if not store then return end
    Model.Prune(store, _G.time())
    self.rows, self.goldIn, self.goldOut = Model.Filter(store, self.filter, _G.time())
    local characters = {}
    for _, entry in ipairs(store.records) do characters[entry.character] = true end
    local ordered = {}; for name in pairs(characters) do ordered[#ordered + 1] = name end
    table.sort(ordered)
    for index = #self.characterOptions, 1, -1 do self.characterOptions[index] = nil end
    self.characterOptions[1] = { text = T("log.all_characters", "All characters"), value = "all" }
    for _, name in ipairs(ordered) do self.characterOptions[#self.characterOptions + 1] = { text = name, value = name } end
    if self.characters.modern.RefreshOptions then self.characters.modern:RefreshOptions() end
    self.characters:SetValue(self.filter.character, true)
    self.pages = math.max(1, math.ceil(#self.rows / PAGE_SIZE))
    self.page = math.min(self.page, self.pages)
    for index, row in ipairs(self.rowFrames) do
        local entry = self.rows[(self.page - 1) * PAGE_SIZE + index]
        row.record = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.labels.time:SetText(Stamp(entry.at))
            row.labels.direction:SetText(T(entry.direction == "in" and "log.received" or "log.sent", entry.direction))
            ListColor(row.labels.direction, entry.direction == "in" and "color.state.success" or "color.text.accent", self.context and self.context.source == "native")
            local party, classFile = Assistant:GetMailLogParty(entry.party)
            row.partyClass = classFile
            row.labels.party:SetText(party)
            PartyColor(row.labels.party, classFile, self.context)
            row.labels.status:SetText(Status(entry))
            ListColor(row.labels.status, Tone(entry), self.context and self.context.source == "native")
            local item, contents = entry.items[1]
            if item then
                contents = (item.name or item.link or ("#" .. item.id)) .. " × " .. item.count
                if #entry.items > 1 then contents = contents .. "  +" .. (#entry.items - 1) end
                if entry.gold > 0 then contents = contents .. " · " .. Money(entry.gold) end
            else contents = entry.gold > 0 and Money(entry.gold) or (entry.subject ~= "" and entry.subject or T("log.text_only", "Text only")) end
            row.icon:SetShown(item ~= nil)
            if item then row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
            row.labels.contents:ClearAllPoints()
            row.labels.contents:SetPoint("LEFT", row, "LEFT", item and 366 or 332, 0)
            row.labels.contents:SetWidth(item and 242 or 276)
            row.labels.contents:SetText(contents)
            ItemColor(row.labels.contents, item, self.context)
        end
    end
    for _, button in ipairs(self.tabButtons) do button:SetSelected(button.direction == self.filter.direction) end
    self.empty:SetShown(#self.rows == 0)
    self.emptyTitle:SetText(#store.records == 0 and T("log.empty", "No mail history yet") or T("log.no_matches", "No matching records"))
    self.emptyHint:SetText(#store.records == 0 and T("log.empty_hint", "Successful sends and collections will appear here.")
        or T("log.no_matches_hint", "Try another filter or clear the filters."))
    self.pageText:SetText(#self.rows > 0 and (self.page .. " / " .. self.pages) or "")
    self.previous:SetDisabled(self.page == 1)
    self.next:SetDisabled(self.page >= self.pages)
    local totals = {}
    if self.goldIn > 0 then totals[#totals + 1] = T("log.total_in", "Received") .. " " .. Money(self.goldIn) end
    if self.goldOut > 0 then totals[#totals + 1] = T("log.total_out", "Sent") .. " " .. Money(self.goldOut) end
    self.totals:SetText(table.concat(totals, " · "))
    local filtered = self.filter.direction ~= "all" or self.filter.character ~= "all"
        or self.filter.days ~= 0 or self.filter.from ~= nil or self.filter.query ~= ""
    self.reset:SetDisabled(not filtered)
    self.clear:SetDisabled(#store.records == 0)
    local unverified = Assistant.MailLog.unverified
    self.notice:SetText(unverified > 0 and string.format(T("log.unverified", "%d operations could not be verified"), unverified)
        or T("log.retention", "History kept for 90 days"))
    GUI:SetTextColorKey(self.notice, unverified > 0 and "color.state.warning" or "color.text.secondary")
    self.modernTabs:SetValue(self.filter.direction, true)
end

function View:ApplyAppearance(context)
    self.context = context
    self:HideTooltip()
    local native = context and context.source == "native"
    for _, control in ipairs(self.controls) do control:ApplySkin(context) end
    for _, button in ipairs(self.tabButtons) do button:SetShown(native) end
    self.modernTabs:SetShown(not native)
    self.search.modern:SetScript("OnEscapePressed", function() View:Hide() end)
    if self.search.native then self.search.native:SetScript("OnEscapePressed", function() View:Hide() end) end
    local r, g, b = GUI:GetColor("color.text.accent")
    if native and _G.NORMAL_FONT_COLOR then local color = _G.NORMAL_FONT_COLOR; r, g, b = color.r, color.g, color.b end
    self.title:SetTextColor(r, g, b)
    self.reset:SetAccent(r, g, b)
    self.bodyBackground:SetTexCoord(0, 1, 0, 1)
    if native then
        self.bodyBackground:SetColorTexture(unpack(NATIVE_LIST.background))
        self.bodyGrain:SetAtlas("QuestBG-Parchment", false)
        self.bodyGrain:SetVertexColor(unpack(NATIVE_LIST.grain))
        self.bodyHeader:SetColorTexture(unpack(NATIVE_LIST.header))
    else self.bodyBackground:SetColorTexture(GUI:GetColor("color.surface.panel")) end
    self.bodyGrain:SetShown(native); self.bodyHeader:SetShown(native)
    if native then self.emptyIcon:SetVertexColor(unpack(NATIVE_LIST.secondary))
    else self.emptyIcon:SetVertexColor(GUI:GetColor("color.text.secondary")) end
    self.previous:SetAccent(r, g, b); self.next:SetAccent(r, g, b)
    for _, label in ipairs(self.texts) do Appearance:ApplyFont(label, context) end
    for _, label in ipairs(self.listTexts) do
        ListFont(label, context); ListColor(label, "color.text.secondary", native)
    end
    ListFont(self.emptyTitle, context); ListColor(self.emptyTitle, "color.text.primary", native)
    ListFont(self.emptyHint, context); ListColor(self.emptyHint, "color.text.secondary", native)
    for _, row in ipairs(self.rowFrames) do
        for key, label in pairs(row.labels) do
            ListFont(label, context)
            local tone = row.record and (key == "status" and Tone(row.record)
                or key == "direction" and (row.record.direction == "in" and "color.state.success" or "color.text.accent"))
            ListColor(label, tone, native)
        end
        PartyColor(row.labels.party, row.partyClass, context)
        ItemColor(row.labels.contents, row.record and row.record.items[1], context)
        if native then
            row.highlight:SetColorTexture(unpack(NATIVE_LIST.highlight))
            row.divider:SetColorTexture(unpack(NATIVE_LIST.divider))
        else
            row.highlight:SetColorTexture(r, g, b, 0.12)
            row.divider:SetColorTexture(GUI:GetColor("color.border.subtle"))
        end
    end
    Appearance:Refresh(self.dateRange)
    if self.clearDialog then Appearance:Refresh(self.clearDialog) end
end

function View:SyncScale()
    if not self.window then return end
    local parentScale = _G.UIParent:GetEffectiveScale()
    local scale = _G.MailFrame and _G.MailFrame:GetEffectiveScale() / parentScale or 1
    local width, height = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
    if width and height then scale = math.min(scale, (width - 32) / WIDTH, (height - 32) / HEIGHT) end
    self.window:SetScale(math.max(0.1, scale))
end

function View:Hide()
    self:CancelClear()
    self:HideTooltip()
    if self.window then self.window:Hide() end
end

function View:EnsureClearDialog()
    if self.clearDialog then return end
    local overlay = GUI:CreateFrame(self.window, { width = WIDTH, height = HEIGHT })
    self.clearOverlay = overlay
    overlay:SetAllPoints(self.window); overlay:SetFrameLevel(self.window:GetFrameLevel() + 60)
    overlay:EnableMouse(true); overlay:EnableMouseWheel(true)
    overlay:SetScript("OnMouseWheel", function() end)
    overlay:SetScript("OnHide", function() View.clearRequest = nil end)
    local dim = GUI:CreateTexture(overlay, { layer = "BACKGROUND" })
    dim:SetAllPoints(overlay); dim:SetColorTexture(0, 0, 0, 0.55)
    local dialog = GUI:CreateFrame(overlay, { width = 440, height = 204 })
    self.clearDialog = dialog
    dialog:SetPoint("CENTER", overlay, "CENTER", 0, 0); dialog:EnableMouse(true)
    local title = Text(dialog, T("log.clear.title", "Clear all mail history"), 14, "color.text.heading", 24, -14, 392)
    title:SetJustifyH("CENTER")
    self.clearMessage = Text(dialog, "", 14, "color.text.primary", 24, -50, 392)
    self.clearMessage:SetHeight(90); self.clearMessage:SetWordWrap(true); self.clearMessage:SetJustifyH("CENTER")
    self.clearCancel = Assistant:CreateMailControl(dialog, "button", { width = 156, height = 36,
        text = T("log.cancel", "Cancel"), mailAction = "quick", nativeIcon = false,
        onClick = function() View:CancelClear() end })
    self.clearCancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 24, 16)
    self.clearAccept = Assistant:CreateMailControl(dialog, "button", { width = 164, height = 36,
        text = T("log.clear.accept", "Clear all"), mailAction = "delete", nativeIcon = false,
        onClick = function() View:ConfirmClear() end })
    self.clearAccept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -24, 16)
    Appearance:Register(dialog, { blizzardWindow = "mail", nativeLayout = "Dialog", nativeBorderOverflow = true,
        themeProvider = function() return Assistant:GetMailThemeStyle() end,
        onRefresh = function(_, context)
            Appearance:ApplyFont(title, context); Appearance:ApplyFont(View.clearMessage, context)
            View.clearCancel:ApplySkin(context); View.clearAccept:ApplySkin(context)
        end })
    overlay:Hide()
end

function View:EnsureUI()
    if self.window then return self.window end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    self.building, self.controls, self.texts, self.rowFrames, self.tabButtons, self.listTexts = true, {}, {}, {}, {}, {}
    local window = GUI:CreateFrame(_G.UIParent, { width = WIDTH, height = HEIGHT })
    self.window = window
    window:Hide(); window:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG"); window:SetToplevel(true); window:SetClampedToScreen(true)
    window:EnableMouse(true); window:EnableMouseWheel(true); window:SetMovable(true)
    window:SetScript("OnMouseDown", function() window:Raise() end)
    window:SetScript("OnMouseWheel", function(_, delta) View:ChangePage(delta > 0 and -1 or 1) end)
    window:SetScript("OnHide", function()
        View:CancelClear(); View:HideTooltip(); window:StopMovingOrSizing()
        for _, edit in ipairs({ View.search, View.startDate, View.endDate }) do
            edit.modern:ClearFocus(); if edit.native then edit.native:ClearFocus() end
        end
        View.dateRange:Hide()
    end)
    window:EnableKeyboard(true)
    window:SetScript("OnKeyDown", function(_, key)
        window:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then
            if View.clearRequest then View:CancelClear() else View:Hide() end
        end
    end)
    local drag = GUI:CreateFrame(window, { width = WIDTH - 50, height = 26 })
    drag:SetPoint("TOPLEFT", window, "TOPLEFT", 4, -1); drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() window:StartMoving() end)
    drag:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    self.title = Text(window, T("log.title", "Mail History"), 14, "color.text.heading", 24, -6, WIDTH - 48)
    self.title:SetJustifyH("CENTER")
    local close = Assistant:CreateMailChromeButton(window, { atlas = "uitools-icon-close", closeStyle = true,
        onClick = function() View:Hide() end })
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -5)
    local function Control(parent, kind, opts, x, y)
        local control = Assistant:CreateMailControl(parent, kind, opts)
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        self.controls[#self.controls + 1] = control
        return control
    end
    for index, item in ipairs({ { "all", "log.all", "All" }, { "in", "log.in", "Received" }, { "out", "log.out", "Sent" } }) do
        local button = Control(window, "button", { text = T(item[2], item[3]), width = 100, height = 30,
            mailAction = "quick", nativeIcon = false, relief = "hairline", onClick = function()
                View.filter.direction, View.page = item[1], 1; View:Refresh()
            end }, 14 + (index - 1) * 106, -34)
        button.direction = item[1]; self.tabButtons[#self.tabButtons + 1] = button
    end
    self.modernTabs = GUI.Form:CreateUnderlineTabs(window, { width = 318, height = 30, equalWidth = true,
        value = "all", items = { { text = T("log.all", "All"), value = "all" },
            { text = T("log.in", "Received"), value = "in" }, { text = T("log.out", "Sent"), value = "out" } },
        onChange = function(_, value) View.filter.direction, View.page = value, 1; View:Refresh() end })
    self.modernTabs:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -34)
    for _, button in ipairs(self.modernTabs.buttons) do self.texts[#self.texts + 1] = button.text end
    self.notice = Text(window, "", 12, "color.text.secondary", 340, -44, 264); self.notice:SetJustifyH("RIGHT")
    self.clear = Control(window, "button", { width = 128, height = 30, text = T("log.clear", "Clear history"),
        mailAction = "delete", nativeIcon = false, microIcon = "trash-2", relief = "hairline",
        onClick = function() View:RequestClear() end }, 618, -34)
    self.characterOptions = { { text = T("log.all_characters", "All characters"), value = "all" } }
    self.characters = Control(window, "dropdown", { width = 210, height = 32, items = self.characterOptions, value = "all",
        onChange = function(_, value) View.filter.character, View.page = value, 1; View:Refresh() end }, 14, -74)
    self.dates = Control(window, "dropdown", { width = 148, height = 32, value = 7, items = {
        { text = T("log.today", "Today"), value = 1 }, { text = T("log.days7", "Last 7 days"), value = 7 },
        { text = T("log.days30", "Last 30 days"), value = 30 }, { text = T("log.days90", "Last 90 days"), value = 0 },
        { text = T("log.custom", "Custom dates"), value = "custom" } }, onChange = function(_, value)
            if value == "custom" then
                View.startDate:SetText(_G.date("%Y-%m-%d", View.filter.from or (_G.time() - 7 * 86400)))
                View.endDate:SetText(_G.date("%Y-%m-%d", View.filter.to and (View.filter.to - 1) or _G.time()))
                View.dateError:SetText(""); View.dateRange:Show()
                local input = View.context.source == "native" and View.startDate.native or View.startDate.modern
                input:SetFocus()
            else
                View.filter.days, View.filter.from, View.filter.to, View.page = value, nil, nil, 1
                View.dateRange:Hide(); View:Refresh()
            end
        end }, 232, -74)
    self.reset = Assistant:CreateMailChromeButton(window, { size = 30, iconSize = 16,
        icon = GUI:GetUIIcon("rotate-ccw", 16), tooltip = T("log.reset", "Clear filters"),
        onClick = function() View:ClearFilters() end })
    self.reset:SetPoint("LEFT", self.dates, "RIGHT", 6, 0)
    self.search = Control(window, "edit", { width = 322, height = 32,
        placeholder = T("log.search", "Search name, item or subject"), onChange = function(_, value)
            View.filter.query, View.page = value, 1; View:Refresh()
        end }, 424, -74)
    self.body = GUI:CreateFrame(window, { width = WIDTH - 28, height = 334 })
    self.body:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -116)
    self.bodyBackground = GUI:CreateTexture(self.body, { layer = "BACKGROUND" })
    self.bodyBackground:SetAllPoints(self.body)
    self.bodyGrain = GUI:CreateTexture(self.body, { layer = "BACKGROUND" })
    self.bodyGrain:SetAllPoints(self.body)
    self.bodyHeader = GUI:CreateTexture(self.body, { layer = "BACKGROUND" })
    self.bodyHeader:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, 0)
    self.bodyHeader:SetSize(WIDTH - 28, 28)
    for _, column in ipairs(COLUMNS) do
        local label = Text(self.body, T("log.column." .. column[1], column[1]), 12, "color.text.secondary", column[2] + 8, -8, column[3] - 8)
        self.texts[#self.texts + 1] = label
        self.listTexts[#self.listTexts + 1] = label
    end
    for index = 1, PAGE_SIZE do
        local row = GUI:CreateFrame(self.body, { width = WIDTH - 44, height = 37 })
        row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 8, -30 - (index - 1) * 38)
        row:EnableMouse(true)
        row.highlight = GUI:CreateTexture(row, { layer = "BACKGROUND" }); row.highlight:SetAllPoints(row); row.highlight:Hide()
        row.divider = GUI:CreateTexture(row, { layer = "BORDER" })
        row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0); row.divider:SetSize(WIDTH - 44, GUI.mult or 1)
        row.labels = {}
        for _, column in ipairs(COLUMNS) do
            local label = Text(row, "", 13, nil, column[2], -10, column[3] - 6)
            row.labels[column[1]] = label
        end
        row.icon = GUI:CreateTexture(row, { layer = "ARTWORK" })
        row.icon:SetPoint("LEFT", row, "LEFT", 332, 0); row.icon:SetSize(26, 26)
        row:SetScript("OnEnter", function() row.highlight:Show(); View:ShowTooltip(row) end)
        row:SetScript("OnLeave", function() row.highlight:Hide(); if View.hovered == row then View:HideTooltip() end end)
        row:SetScript("OnHide", function() row.highlight:Hide(); if View.hovered == row then View:HideTooltip() end end)
        self.rowFrames[index] = row
    end
    self.empty = GUI:CreateFrame(self.body, { width = 500, height = 126 })
    self.empty:SetPoint("CENTER", self.body, "CENTER", 0, -8)
    local emptyIcon = GUI:CreateIcon(self.empty, { icon = GUI:GetUIIcon("file-text", 38), size = 38, colorKey = "color.text.secondary" })
    self.emptyIcon = emptyIcon
    emptyIcon:ClearAllPoints(); emptyIcon:SetPoint("TOP", self.empty, "TOP", 0, 0)
    self.emptyTitle = Text(self.empty, "", 16, "color.text.primary", 0, -54, 500); self.emptyTitle:SetJustifyH("CENTER")
    self.emptyHint = Text(self.empty, "", 13, "color.text.secondary", 0, -82, 500); self.emptyHint:SetJustifyH("CENTER")
    self.totals = GUI:CreateText(window, "", 12, "color.text.secondary", "RIGHT")
    self.totals:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -18, 14)
    self.totals:SetWordWrap(false)
    self.pageText = Text(window, "", 12, "color.text.secondary", 48, -466, 96); self.pageText:SetJustifyH("CENTER")
    self.previous = Assistant:CreateMailChromeButton(window, { atlas = "uitools-icon-chevron-left", size = 24,
        onClick = function() View:ChangePage(-1) end })
    self.previous:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 9)
    self.next = Assistant:CreateMailChromeButton(window, { atlas = "uitools-icon-chevron-right", size = 24,
        onClick = function() View:ChangePage(1) end })
    self.next:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 148, 9)
    self.dateRange = GUI:CreatePanel(window, { width = 460, height = 146, surface = "color.surface.popup", border = "color.border.accent" })
    self.dateRange:SetPoint("TOPLEFT", window, "TOPLEFT", 232, -108)
    self.dateRange:SetFrameLevel(window:GetFrameLevel() + 40); self.dateRange:EnableMouse(true); self.dateRange:Hide()
    self.dateRange:SetScript("OnHide", function()
        for _, input in ipairs({ View.startDate, View.endDate }) do
            if input then input.modern:ClearFocus(); if input.native then input.native:ClearFocus() end end
        end
        View.dates:SetValue(View.filter.from and "custom" or View.filter.days, true)
    end)
    local dateHint = Text(self.dateRange, T("log.range_hint", "Date range (YYYY-MM-DD)"), 13, nil, 12, -10, 436)
    self.startDate = Control(self.dateRange, "edit", { width = 190, height = 32 }, 12, -36)
    local dash = Text(self.dateRange, "—", 13, nil, 210, -45, 22)
    self.endDate = Control(self.dateRange, "edit", { width = 190, height = 32 }, 246, -36)
    self.dateError = Text(self.dateRange, "", 12, "color.state.danger", 12, -76, 436)
    local function Parse(value)
        local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        year, month, day = tonumber(year), tonumber(month), tonumber(day)
        if not year or year < 2004 or year > 2099 or month < 1 or month > 12 or day < 1 or day > 31 then return nil end
        local stamp = _G.time({ year = year, month = month, day = day, hour = 0 })
        return _G.date("%Y-%m-%d", stamp) == value and stamp or nil
    end
    local function ApplyRange()
        local from, last = Parse(View.startDate:GetText()), Parse(View.endDate:GetText())
        if not from or not last or from > last then View.dateError:SetText(T("log.invalid_range", "Enter a valid date range.")); return end
        local nextDay = _G.date("*t", last); nextDay.day = nextDay.day + 1
        View.filter.from, View.filter.to, View.filter.days, View.page = from, _G.time(nextDay), 0, 1
        View.dateRange:Hide(); View:Refresh()
    end
    self.applyRange = Control(self.dateRange, "button", { width = 120, height = 32, text = T("log.apply", "Apply"),
        primary = true, mailAction = "quick", onClick = ApplyRange }, 190, -104)
    Control(self.dateRange, "button", { width = 120, height = 32, text = T("log.cancel", "Cancel"), mailAction = "quick",
        onClick = function()
            View.dateRange:Hide(); View.dates:SetValue(View.filter.from and "custom" or View.filter.days, true)
        end }, 320, -104)
    for _, label in ipairs({ self.title, self.emptyTitle, self.emptyHint, self.totals, self.pageText, dateHint, dash, self.dateError, self.notice }) do
        self.texts[#self.texts + 1] = label
    end
    Appearance:Register(self.dateRange, { blizzardWindow = "mail", themeProvider = function() return Assistant:GetMailThemeStyle() end,
        nativeLayout = "Dialog", role = "mail-history-dates", onRefresh = function()
            for _, pair in ipairs({ { View.startDate, View.endDate }, { View.endDate, View.startDate } }) do
                for _, face in ipairs({ pair[1].modern, pair[1].native }) do
                    face:SetScript("OnEnterPressed", ApplyRange)
                    face:SetScript("OnEscapePressed", function() View.dateRange:Hide() end)
                    face:SetScript("OnTabPressed", function(box)
                        box:ClearFocus()
                        local nextInput = View.context.source == "native" and pair[2].native or pair[2].modern
                        nextInput:SetFocus()
                    end)
                end
            end
        end })
    Appearance:Register(window, { blizzardWindow = "mail", themeProvider = function() return Assistant:GetMailThemeStyle() end,
        heading = self.title, role = "mail-history", nativeBorderOverflow = true,
        onRefresh = function(_, context) View:ApplyAppearance(context) end })
    if _G.MailFrame then
        YUI.API.Security.SafeHook("MailAssistant.Log:Scale", _G.MailFrame, "SetScale", function() if window:IsShown() then View:SyncScale() end end)
    end
    self.building = false
    return window
end

function View:Toggle()
    if not Assistant.runtime.enabled then return false end
    if self.window and self.window:IsShown() then self:Hide(); return false end
    local window = self:EnsureUI()
    if not window then return false end
    self:SyncScale(); Appearance:Refresh(window); window:Show(); window:Raise(); self:Refresh()
    local search = self.context and self.context.source == "native" and self.search.native or self.search.modern
    search:SetFocus()
    return true
end

Assistant:EnsureMailLogButton()
