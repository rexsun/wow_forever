local _, ns = ...
local YUI = _G.YUI or ns
local Service = YUI and YUI.InfoOutput
if not Service or Service.OpenSettings then return end

local WINDOW = "YUIInfoOutputSettings"
local WIDTH, HEIGHT, INSET = 620, 515, 18
local CONTENT = WIDTH - INSET * 2
local FONT_PROVIDER = "core.info-output"
local PROFILE_EVENTS = { "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }
local PREVIEW_MODES = { normal = true, burst = true, priority = true }
local PREVIEW_ERRORS = { editing = true, busy = true, disabled = true }
local PRIORITIES = { low = true, normal = true, important = true }
local STATUSES = { queued = true, shown = true, expired = true, overflow = true, cancelled = true }
local window

local function T(key)
    return YUI.Locale:Get("Core")["info_output." .. key]
end

local function Message(key)
    if YUI.Print then YUI:Print(T(key)) end
end

local function Play(mode, fromWindow)
    local ok, reason = Service:PlayPreview(mode)
    if ok and window then window.ownsPreview = fromWindow == true end
    local message = ok and "test.started" or "test." .. (PREVIEW_ERRORS[reason] and reason or "failed")
    if fromWindow then window.feedback:SetText(T(message)) else Message(message) end
end

local function Stop(fromWindow)
    Service:StopPreview()
    if window then window.ownsPreview = nil end
    if fromWindow then window.feedback:SetText(T("test.stopped")) else Message("test.stopped") end
end

local function PlainMessage(value)
    -- Show the label of an item link, with all remaining escapes rendered as text.
    return (value:gsub("|H[^|\r\n]*|h(.-)|h", "%1")
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
        :gsub("||", "|"):gsub("|", "||"))
end

local function RefreshRecent(frame)
    local GUI = YUI.GUI2
    local scroll, rows = frame.scroll, frame.rows
    local recent = Service:GetRecent() or {}
    local count = math.min(100, #recent)
    local now = GetTime()
    local y = 0
    for index = 1, count do
        local record = recent[index]
        local priority = PRIORITIES[record.priority] and record.priority or "normal"
        local status = STATUSES[record.status] and record.status or "unknown"
        local age = math.max(0, math.floor(now - (record.time or now)))
        local row = rows[index]
        if not row then
            local tag = GUI:CreateText(scroll.child, "", "font.size.sm", "color.text.secondary", "LEFT")
            local text = GUI:CreateText(scroll.child, "", "font.size.md", "color.text.primary", "LEFT")
            text:SetWidth(scroll.child:GetWidth())
            text:SetWordWrap(true)
            text:SetNonSpaceWrap(true)
            text:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -2)
            row = { tag = tag, text = text }
            rows[index] = row
        end
        row.tag:ClearAllPoints()
        row.tag:SetPoint("TOPLEFT", 0, -y)
        row.tag:SetText(T("recent.entry"):format(T("priority." .. priority), T("status." .. status), record.count or 1, age))
        row.text:SetText(PlainMessage(record.text or ""))
        row.tag:Show()
        row.text:Show()
        y = y + math.max(14, row.tag:GetStringHeight()) + math.max(17, row.text:GetStringHeight()) + 9
    end
    for index = count + 1, #rows do
        rows[index].tag:Hide()
        rows[index].text:Hide()
    end
    frame.empty:SetShown(count == 0)
    scroll:SetVerticalScroll(0)
    GUI:FitScrollContent(scroll, y)
end

local function RefreshControls(frame)
    for key, control in pairs(frame.controls) do
        control:SetValue(Service:GetSetting(key), true)
    end
    local style = YUI.GUI2.FontStyle
    if style and style.RefreshControls then style:RefreshControls() end
    frame.feedback:SetText("")
end

local function CloseSettingsMenus(frame)
    local GUI = YUI.GUI2
    local dropdown = GUI.DropdownFrame
    for _, control in pairs(frame.controls) do
        if dropdown and dropdown.anchor == control then GUI:CloseDropdown(false) end
        if GameTooltip and GameTooltip:IsOwned(control) then YUI.HideGameTooltip() end
    end
    if GUI.FontStyle and GUI.FontStyle.CloseForProvider then GUI.FontStyle:CloseForProvider(FONT_PROVIDER) end
end

local function SelectPage(frame, recent)
    if recent then CloseSettingsMenus(frame) end
    frame.form:SetShown(not recent)
    frame.recent:SetShown(recent)
    frame.tabs:SetValue(recent and "recent" or "settings", true)
    if recent then RefreshRecent(frame.recent) else RefreshControls(frame) end
end

local function BuildWindow(GUI)
    local Form = GUI.Form
    local frame = GUI:CreatePanel(UIParent, {
        name = WINDOW, width = WIDTH, height = HEIGHT, surface = "color.surface.window",
        border = "color.border.strong", shadow = true,
    })
    frame:Hide()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -36)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    local header = GUI:CreateFrame(frame, { height = 40, mouse = true, drag = true,
        onDragStart = function() frame:StartMoving() end,
        onDragStop = function() frame:StopMovingOrSizing() end,
    })
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", -38, 0)
    GUI:CreateText(header, T("name"), "font.size.lg", "color.text.heading"):SetPoint("LEFT", INSET, 0)
    GUI:CreateCloseButton(frame, function() frame:Hide() end):SetPoint("TOPRIGHT", -10, -8)

    local function Button(parent, key, x, y, width, click)
        local button = Form:CreateButton(parent, { text = T(key), width = width, onClick = click })
        button:SetPoint("TOPLEFT", x, y)
        return button
    end

    local function Label(parent, key, x, y, width, heading)
        local text = GUI:CreateText(parent, T(key), heading and "font.size.md" or "font.size.sm",
            heading and "color.text.heading" or "color.text.secondary", "LEFT")
        text:SetPoint("TOPLEFT", x, y)
        if width then text:SetWidth(width); text:SetWordWrap(true) end
        return text
    end

    local tabs = Form:CreateUnderlineTabs(frame, {
        width = CONTENT, value = "settings", showBaseline = true,
        items = { { value = "settings", text = T("tab.settings") }, { value = "recent", text = T("tab.recent") } },
        onChange = function(_, value) SelectPage(frame, value == "recent") end,
    })
    tabs:SetPoint("TOPLEFT", INSET, -38)
    frame.tabs = tabs

    local function NewPage()
        local page = GUI:CreateFrame(frame)
        page:SetPoint("TOPLEFT", INSET, -82)
        page:SetPoint("BOTTOMRIGHT", -INSET, 14)
        return page
    end

    local page = NewPage()
    frame.form = page
    frame.controls = {}

    local function Slider(key, x, y, width, minimum, maximum, step)
        local control
        control = Form:CreateSlider(page, {
            width = width, inline = true, inputWidth = 50,
            min = minimum, max = maximum, step = step, instantUpdate = false,
            get = function() return Service:GetSetting(key) end,
            onChange = function(_, value)
                if not Service:SetSetting(key, value) then
                    control:SetValue(Service:GetSetting(key), true)
                    frame.feedback:SetText(T("settings.rejected"))
                end
            end,
        })
        Label(page, "field." .. key, x, y)
        control:SetPoint("TOPLEFT", x, y - 17)
        frame.controls[key] = control
    end

    local gap = 16
    local half, third = (CONTENT - gap) / 2, (CONTENT - 2 * gap) / 3
    local function Dropdown(key, x, y, options)
        Label(page, "field." .. key, x, y)
        local control = Form:CreateDropdown(page, {
            width = half, options = options, get = function() return Service:GetSetting(key) end,
            set = function(value) Service:SetSetting(key, value) end,
        })
        control:SetPoint("TOPLEFT", x, y - 17)
        frame.controls[key] = control
    end
    Label(page, "section.display", 0, 0, nil, true)
    Label(page, "field.textStyle", 0, -23)
    Form:CreateFontStyle(page, { key = FONT_PROVIDER .. ":text", width = half }):SetPoint("TOPLEFT", 0, -40)
    Slider("width", half + gap, -23, half, 260, 900, 1)
    Dropdown("align", 0, -72, {
        { value = "LEFT", text = T("align.left") }, { value = "CENTER", text = T("align.center") }, { value = "RIGHT", text = T("align.right") },
    })
    Dropdown("growth", half + gap, -72, {
        { value = "down", text = T("growth.down") }, { value = "up", text = T("growth.up") },
    })

    Label(page, "section.pacing", 0, -127, nil, true)
    Slider("maxRows", 0, -150, third, 2, 8, 1)
    Slider("duration", third + gap, -150, third, 2, 20, 1)
    Slider("interval", (third + gap) * 2, -150, third, 0, 0.75, 0.01)

    Label(page, "section.animation", 0, -205, nil, true)
    Slider("enterDuration", 0, -228, third, 0, 0.6, 0.01)
    Slider("moveDuration", third + gap, -228, third, 0, 0.6, 0.01)
    Slider("exitDuration", (third + gap) * 2, -228, third, 0, 0.6, 0.01)
    Label(page, "animation.hint", 0, -273, CONTENT)

    Label(page, "section.test", 0, -301, nil, true)
    local testWidth = (CONTENT - 3 * 10) / 4
    for index, mode in ipairs({ "normal", "burst", "priority", "stop" }) do
        Button(page, "test." .. mode, (index - 1) * (testWidth + 10), -322, testWidth, function()
            if mode == "stop" then Stop(true) else Play(mode, true) end
        end)
    end
    frame.feedback = GUI:CreateText(page, "", "font.size.md", "color.text.accent", "LEFT")
    frame.feedback:SetPoint("TOPLEFT", 0, -355)
    frame.feedback:SetWidth(CONTENT)
    frame.feedback:SetWordWrap(true)

    Button(page, "settings.move", 0, -389, 168, function()
        if YUI.Layout and YUI.Layout.RequestMoveMode then
            frame:Hide()
            if not YUI.Layout:RequestMoveMode("info-output-settings") then Message("settings.move_failed") end
        end
    end)
    Button(page, "settings.reset", CONTENT - 168, -389, 168, function()
        Service:ResetSettings()
        RefreshControls(frame)
    end)

    local recent = NewPage()
    frame.recent = recent
    recent.rows = {}
    Label(recent, "recent.hint", 0, -4, 410)
    Button(recent, "recent.refresh", CONTENT - 120, 0, 120, function() RefreshRecent(recent) end)
    recent.empty = Label(recent, "recent.empty", 0, -52, 530)
    recent.scroll = GUI:CreateScrollFrame(recent, { width = CONTENT, height = HEIGHT - 144, childWidth = CONTENT - 20, autoHide = true })
    recent.scroll:SetPoint("TOPLEFT", 0, -44)

    function frame:OnProfileChanged() self:Hide() end
    function frame:OnModuleDisabled(_, id)
        if id == "core.info-output" then self:Hide() end
    end
    frame:SetScript("OnShow", function(self)
        local DB = YUI.DB
        local db = DB and DB.GetAceDB and DB:GetAceDB(YUI.ProductId)
        if db and db.RegisterCallback then
            self.database = db
            for _, event in ipairs(PROFILE_EVENTS) do db.RegisterCallback(self, event, "OnProfileChanged") end
        end
        if YUI.Event then YUI.Event:On("YUI_MODULE_DISABLED", "OnModuleDisabled", self) end
    end)
    frame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        CloseSettingsMenus(self)
        if self.ownsPreview then
            self.ownsPreview = nil
            Service:StopPreview()
        end
        if self.database then
            for _, event in ipairs(PROFILE_EVENTS) do self.database.UnregisterCallback(self, event) end
            self.database = nil
        end
        if YUI.Event then YUI.Event:OffOwner(self) end
        for _, row in ipairs(self.recent.rows) do row.text:SetText("") end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, WINDOW) end
    if YUI.Settings and YUI.Settings.RegisterScaleWindow then YUI.Settings:RegisterScaleWindow(frame) end
    return frame
end

function Service:OpenSettings(page)
    local GUI = YUI.GUI2
    if not (GUI and GUI.Form and GUI.Form.CreateFontStyle and GUI.Form.CreateUnderlineTabs and UIParent and self.GetSetting and self.SetSetting
        and self.ResetSettings and self.PlayPreview and self.StopPreview and self.GetRecent) then
        Message("settings.unavailable")
        return false
    end
    local layout = YUI.Layout
    if layout and layout.IsEditing and layout:IsEditing() then
        if not layout.CloseEditMode or not layout:CloseEditMode("info-output-settings") then return false end
    end
    if not window then window = BuildWindow(GUI) end
    local settings = _G.YUI_SettingsFrame
    window:SetFrameLevel(math.max(200, settings and settings:GetFrameLevel() + 30 or 0))
    window:Show()
    window:Raise()
    SelectPage(window, page == "recent")
    return true
end

local previousSlashHandler = YUI.HandleSlashCommand
function YUI:HandleSlashCommand(message)
    local command, args = tostring(message or ""):lower():match("^%s*(%S+)%s*(.-)%s*$")
    if command ~= "infooutput" then
        if previousSlashHandler then return previousSlashHandler(self, message) end
        return false
    end
    local mode = args:match("^preview%s+(%S+)$")
    if args == "" or args == "recent" then
        Service:OpenSettings(args)
    elseif args == "preview" or PREVIEW_MODES[mode] then
        if Service.PlayPreview then Play(mode or "normal", false) else Message("settings.unavailable") end
    elseif args == "stop" then
        if Service.StopPreview then Stop(false) else Message("settings.unavailable") end
    else
        Message("settings.usage")
    end
    return true
end

-- Settings-enabled addons already route /yui through HandleSlashCommand.
if SlashCmdList and not SlashCmdList.YUI and not _G.SLASH_YUI1 then
    _G.SLASH_YUI1 = "/yui"
    SlashCmdList.YUI = function(message) YUI:HandleSlashCommand(message) end
end
