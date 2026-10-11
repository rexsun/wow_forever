local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local GUI2 = YUI.GUI2 or YUI.GUI
local System = YUI.API and YUI.API.System
if not Adapter then return end

local CopyViewer = {}
YChat.CopyViewer = CopyViewer

local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local concat = table.concat
local floor = math.floor
local huge = math.huge
local format = string.format
local gsub = string.gsub
local pairs = pairs
local type = type
local buttonFrames = setmetatable({}, { __mode = "k" })
local scrollButtonFrames = setmetatable({}, { __mode = "k" })
local buttonOwners = setmetatable({}, { __mode = "k" })
local exportLines = {}

CopyViewer.enabled = false
CopyViewer.popup = nil
CopyViewer.clearingPopup = false
CopyViewer.lastReason = "not-started"

local function T(key, fallback)
    local value = L[key]
    if value == nil or value == key then return fallback end
    return value
end

local function ClearExportBuffer()
    for index = #exportLines, 1, -1 do exportLines[index] = nil end
end

local function SanitizeMessage(text, red, green, blue)
    if type(text) ~= "string" or text:find("|K", 1, true) ~= nil then return nil end
    text = gsub(text, "|T.-|t", "")
    text = gsub(text, "|A.-|a", "")
    if red == nil and green == nil and blue == nil then return text end
    return format(
        "|cff%02x%02x%02x%s|r",
        floor((red * 255) + 0.5),
        floor((green * 255) + 0.5),
        floor((blue * 255) + 0.5),
        text
    )
end

function CopyViewer:PrepareExportText(text, red, green, blue)
    return SanitizeMessage(text, red, green, blue)
end

local function FailureText(reason)
    return format(
        T(
            "copy.unavailable",
            "当前聊天记录暂时无法安全读取（%s）。请稍后重试。"
        ),
        type(reason) == "string" and reason or "unknown"
    )
end

local function CopyScrollMouseDown(scroll)
    local popup = CopyViewer.popup
    if popup and popup.scroll == scroll then popup.edit:SetFocus() end
end

local CopyScrollVerticalChanged

local function SyncCopyViewport(scroll, width, height, force)
    local popup = CopyViewer.popup
    if not popup or popup.scroll ~= scroll then return false end
    if type(width) ~= "number" or width < 1 then width = scroll:GetWidth() or 1 end
    if type(height) ~= "number" or height < 1 then height = scroll:GetHeight() or 1 end
    if width < 1 then width = 1 end
    if height < 1 then height = 1 end
    if not force
        and popup.viewportWidth == width
        and popup.viewportHeight == height
    then
        return true
    end
    popup.viewportWidth = width
    popup.viewportHeight = height

    local edit = popup.edit
    edit:SetSize(width, height)
    if type(scroll.UpdateScrollChildRect) == "function" then
        pcall(scroll.UpdateScrollChildRect, scroll)
    end
    CopyScrollVerticalChanged(scroll, scroll:GetVerticalScroll() or 0)
    return true
end

local function CopyScrollSizeChanged(scroll, width, height)
    SyncCopyViewport(scroll, width, height)
end

CopyScrollVerticalChanged = function(scroll, offset)
    local popup = CopyViewer.popup
    if not popup or popup.scroll ~= scroll then return end
    local edit = popup.edit
    local editHeight = edit:GetHeight() or 0
    local viewportHeight = scroll:GetHeight() or 0
    offset = type(offset) == "number" and offset or 0
    edit:SetHitRectInsets(0, 0, offset, editHeight - offset - viewportHeight)
end

local function CopyTextChanged(_, userInput)
    if userInput then return end
    local popup = CopyViewer.popup
    if popup and popup.scroll.SetVerticalScroll then
        popup.scroll:SetVerticalScroll(0)
    end
end

local function HidePopup()
    if CopyViewer.clearingPopup then return end
    CopyViewer.clearingPopup = true
    local popup = CopyViewer.popup
    if not popup then
        ClearExportBuffer()
        CopyViewer.clearingPopup = false
        return
    end
    popup.edit:SetText("")
    popup.edit:ClearFocus()
    if popup:IsShown() then popup:Hide() end
    ClearExportBuffer()
    CopyViewer.clearingPopup = false
end

local function CloseClicked()
    HidePopup()
end

local function SelectAllClicked()
    local popup = CopyViewer.popup
    if not popup or not popup:IsShown() then return end
    popup.edit:SetFocus()
    popup.edit:HighlightText(0, -1)
end

local function EnsurePopup()
    if CopyViewer.popup then return true end
    if not (GUI2
        and type(GUI2.CreatePanel) == "function"
        and type(GUI2.CreateScrollFrame) == "function"
        and GUI2.Form
        and type(GUI2.Form.CreateButton) == "function"
        and type(_G.CreateFrame) == "function"
        and _G.UIParent)
    then
        return false, "copy-gui-unavailable"
    end

    local popup = GUI2:CreatePanel(_G.UIParent, {
        name = "YUI_YChatCopyViewer",
        width = 700,
        height = 430,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(9000)
    if popup.SetToplevel then popup:SetToplevel(true) end
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)
    popup:Hide()

    local title = GUI2:CreateText(
        popup,
        T("copy.title", "聊天记录"),
        "font.size.lg",
        "color.text.heading"
    )
    title:SetPoint("TOPLEFT", 18, -16)

    local close = GUI2.Form:CreateButton(popup, {
        text = T("common.close", "关闭"),
        width = 72,
        height = 26,
        onClick = CloseClicked,
    })
    close:SetPoint("TOPRIGHT", -16, -12)

    local selectAll = GUI2.Form:CreateButton(popup, {
        text = T("copy.select_all", "全选"),
        width = 72,
        height = 26,
        onClick = SelectAllClicked,
    })
    selectAll:SetPoint("RIGHT", close, "LEFT", -8, 0)

    local scroll = GUI2:CreateScrollFrame(popup, {
        name = "YUI_YChatCopyViewerScroll",
        child = false,
        mouseWheel = true,
    })
    scroll:SetPoint("TOPLEFT", 16, -52)
    scroll:SetPoint("BOTTOMRIGHT", -28, 16)
    if type(scroll.SetFrameLevel) == "function" then
        scroll:SetFrameLevel((popup:GetFrameLevel() or 1) + 2)
    end
    if type(scroll.HookScript) == "function" then
        scroll:HookScript("OnMouseDown", CopyScrollMouseDown)
        scroll:HookScript("OnSizeChanged", CopyScrollSizeChanged)
        scroll:HookScript("OnVerticalScroll", CopyScrollVerticalChanged)
    end

    local edit = _G.CreateFrame("EditBox", nil, popup)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    if type(edit.SetMaxLetters) == "function" then edit:SetMaxLetters(0) end
    edit:EnableMouse(true)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetJustifyH("LEFT")
    if edit.SetJustifyV then edit:SetJustifyV("TOP") end
    local font = GUI2.GetFont and GUI2:GetFont("font.family.body")
        or _G.STANDARD_TEXT_FONT
    local size = GUI2.GetMetric and GUI2:GetMetric("font.size.md", 13) or 13
    edit:SetFont(font, size, "")
    if type(edit.SetFrameLevel) == "function" then
        edit:SetFrameLevel((scroll:GetFrameLevel() or popup:GetFrameLevel() or 1) + 1)
    end
    if GUI2.GetColor then edit:SetTextColor(GUI2:GetColor("color.text.primary")) end
    if type(edit.SetHighlightColor) == "function" and GUI2.GetColor then
        local red, green, blue = GUI2:GetColor("color.accent.primary")
        if type(red) == "number" and type(green) == "number" and type(blue) == "number" then
            edit:SetHighlightColor(red, green, blue, 0.42)
        end
    end
    edit:SetScript("OnEscapePressed", CloseClicked)
    edit:SetScript("OnTextChanged", CopyTextChanged)
    edit:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    scroll:SetScrollChild(edit)

    popup.scroll = scroll
    popup.edit = edit
    popup.title = title
    popup.lineHeight = size + 2
    CopyViewer.popup = popup
    SyncCopyViewport(scroll, nil, nil, true)
    popup:SetScript("OnHide", HidePopup)
    return true
end

local function PresentText(titleText, text, reason)
    local popupOK, popupReason = EnsurePopup()
    if not popupOK then return false, popupReason end
    local popup = CopyViewer.popup
    if popup.title and type(popup.title.SetText) == "function" then
        popup.title:SetText(titleText or T("copy.title", "聊天记录"))
    end
    local value = type(text) == "string" and text or ""
    popup:Show()
    if popup.Raise then popup:Raise() end
    -- Resolve the viewport before assigning multiline text. Retail grows the
    -- EditBox vertically from this minimum size; forcing SetSize afterwards
    -- collapses the scroll child and can leave a non-empty snapshot blank.
    SyncCopyViewport(popup.scroll, nil, nil, true)
    local textOK = pcall(popup.edit.SetText, popup.edit, value)
    if not textOK then
        pcall(popup.edit.SetText, popup.edit, FailureText("copy-text-write-failed"))
        return false, "copy-text-write-failed"
    end
    if type(popup.edit.GetText) == "function" then
        local readOK, written = pcall(popup.edit.GetText, popup.edit)
        if not readOK or type(written) ~= "string" or written ~= value then
            pcall(popup.edit.SetText, popup.edit, FailureText("copy-text-write-unconfirmed"))
            return false, "copy-text-write-unconfirmed"
        end
    end
    if popup.scroll.SetVerticalScroll then popup.scroll:SetVerticalScroll(0) end
    popup.edit:SetFocus()
    popup.edit:SetCursorPosition(0)
    popup.edit:HighlightText(0, -1)
    CopyViewer.lastReason = reason or "copy-open"
    return true
end

local function ResolveCopyTimestamp(frame, messageIndex, count, serverNow, monotonicNow, pattern)
    if type(serverNow) ~= "number" or serverNow < 0 or serverNow >= huge
        or type(monotonicNow) ~= "number" or monotonicNow < 0 or monotonicNow >= huge
    then
        return nil
    end
    local _, nativeTimestamp = Adapter:ReadHistoricalEntrySample(
        frame,
        count - messageIndex + 1
    )
    if type(nativeTimestamp) ~= "number"
        or nativeTimestamp < 0
        or nativeTimestamp > monotonicNow
        or nativeTimestamp >= huge
    then
        return nil
    end
    local epoch = floor(serverNow - (monotonicNow - nativeTimestamp) + 0.5)
    if epoch < 0 or epoch >= huge or not (System and System.FormatDate) then return nil end
    return System.FormatDate(pattern, epoch)
end

local function MessageTextOwnsTimestamp(timestamp)
    local layout = YChat.timestampLayoutAtLoad
    if type(layout) ~= "string" then
        layout = timestamp and timestamp.layout or "column"
    end
    local enabled = YChat.timestampEnabledAtLoad
    if type(enabled) ~= "boolean" then
        enabled = timestamp and timestamp.enabled == true
    end
    return enabled == true and layout == "nativeInline"
end

local function ExportFrame(frame)
    if not CopyViewer.enabled then return false, "copy-disabled" end
    local popupOK, popupReason = EnsurePopup()
    if not popupOK then return false, popupReason end
    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then
        return PresentText(
            T("copy.title", "聊天记录"),
            FailureText("copy-restriction-not-open"),
            "copy-unavailable"
        )
    end
    if not Adapter:IsTrustedSupportedFrame(frame)
        or Adapter:CanCallProtected(frame) ~= true
    then
        return PresentText(
            T("copy.title", "聊天记录"),
            FailureText("copy-frame-unsafe"),
            "copy-unavailable"
        )
    end
    local count, countReason = Adapter:ReadNumMessages(frame)
    if count == nil then
        return PresentText(
            T("copy.title", "聊天记录"),
            FailureText(countReason),
            "copy-unavailable"
        )
    end

    ClearExportBuffer()
    local timestamp = type(YChat.GetTimestamp) == "function" and YChat:GetTimestamp() or nil
    local pattern = timestamp and timestamp.format == "hm" and "%H:%M" or "%H:%M:%S"
    local prependTimestamp = not MessageTextOwnsTimestamp(timestamp)
    local serverNow = prependTimestamp
        and System and System.GetServerTime and System.GetServerTime() or nil
    local monotonicNow = prependTimestamp
        and System and System.GetTime and System.GetTime() or nil
    local exported = 0
    local skipped = 0
    for index = 1, count do
        local text, red, green, blue = Adapter:ReadCopyMessageForExplicitExport(frame, index)
        if text == nil then
            if red == "copy-message-unsafe" then
                skipped = skipped + 1
            else
                ClearExportBuffer()
                return PresentText(
                    T("copy.title", "聊天记录"),
                    FailureText(red or "copy-message-read-failed"),
                    "copy-unavailable"
                )
            end
        else
            local safeText = SanitizeMessage(text, red, green, blue)
            if safeText == nil then
                skipped = skipped + 1
            else
                local timeText = prependTimestamp and ResolveCopyTimestamp(
                    frame,
                    index,
                    count,
                    serverNow,
                    monotonicNow,
                    pattern
                ) or nil
                exported = exported + 1
                exportLines[exported] = timeText
                    and (timeText .. " " .. safeText)
                    or safeText
            end
        end
    end
    if skipped > 0 then
        exported = exported + 1
        exportLines[exported] = format(
            T("copy.skipped_unsafe", "已跳过 %d 条无法安全导出的消息。"),
            skipped
        )
    end

    return PresentText(
        T("copy.title", "聊天记录"),
        concat(exportLines, "\n"),
        "copy-open"
    )
end

local function CopyButtonClicked(button)
    local frame = buttonOwners[button]
    if frame then ExportFrame(frame) end
end

local function ScrollBottomButtonClicked(button)
    local frame = buttonOwners[button]
    if frame then Adapter:ScrollChatFrameToBottom(frame) end
end

local RefreshButtonVisibility

local function CopyButtonEntered(button)
    local frame = buttonOwners[button]
    if frame then RefreshButtonVisibility(frame) end
end

local function CopyButtonLeft(button)
    local frame = buttonOwners[button]
    if frame then RefreshButtonVisibility(frame) end
end

local function CopyFrameEntered(frame)
    RefreshButtonVisibility(frame)
end

local function CopyFrameLeft(frame)
    RefreshButtonVisibility(frame)
end

local function EnsureButtons(frame)
    local button = buttonFrames[frame]
    local scrollButton = scrollButtonFrames[frame]
    if button and scrollButton then return button, scrollButton end
    if not (GUI2
        and type(GUI2.CreateBareMicroIconButton) == "function"
        and Adapter:CanCallProtected(frame) == true)
    then
        return nil, nil, "copy-button-gui-unavailable"
    end
    if not button then
        button = GUI2:CreateBareMicroIconButton(frame, {
            size = 20,
            microIconSize = 16,
            iconName = "copy",
            colorKey = "color.text.muted",
            hoverColorKey = "color.accent.primary",
            normalAlpha = 0.72,
            hoverAlpha = 1,
            tooltip = T("copy.button", "复制"),
            tooltipAnchor = "ANCHOR_LEFT",
            onClick = CopyButtonClicked,
        })
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -3)
        button:SetFrameLevel((frame:GetFrameLevel() or 1) + 12)
        if type(button.HookScript) == "function" then
            button:HookScript("OnEnter", CopyButtonEntered)
            button:HookScript("OnLeave", CopyButtonLeft)
        end
        button:Hide()
        buttonFrames[frame] = button
        buttonOwners[button] = frame
    end
    if not scrollButton then
        scrollButton = GUI2:CreateBareMicroIconButton(frame, {
            size = 20,
            microIconSize = 16,
            iconName = "download",
            colorKey = "color.text.muted",
            hoverColorKey = "color.accent.primary",
            normalAlpha = 0.72,
            hoverAlpha = 1,
            tooltip = T("copy.scroll_bottom", "滚动到底部"),
            tooltipAnchor = "ANCHOR_LEFT",
            onClick = ScrollBottomButtonClicked,
        })
        scrollButton:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
        scrollButton:SetFrameLevel((frame:GetFrameLevel() or 1) + 12)
        if type(scrollButton.HookScript) == "function" then
            scrollButton:HookScript("OnEnter", CopyButtonEntered)
            scrollButton:HookScript("OnLeave", CopyButtonLeft)
        end
        scrollButton:Hide()
        scrollButtonFrames[frame] = scrollButton
        buttonOwners[scrollButton] = frame
    end
    return button, scrollButton
end

RefreshButtonVisibility = function(frame)
    local button = buttonFrames[frame]
    local scrollButton = scrollButtonFrames[frame]
    if not button or not scrollButton then return false, "copy-button-unavailable" end
    local restriction = Adapter:GetRestrictionState()
    local visible = CopyViewer.enabled
        and (restriction == "OPEN" or restriction == "PAUSED")
        and Adapter:IsTrustedSupportedFrame(frame)
        and (Adapter:IsObjectMouseOver(frame) == true
            or Adapter:IsObjectMouseOver(button) == true
            or Adapter:IsObjectMouseOver(scrollButton) == true)
    if visible then
        button:Show()
        scrollButton:Show()
    else
        button:Hide()
        scrollButton:Hide()
    end
    return true
end

local function ReconcileFrame(frame)
    local button, scrollButton, reason = EnsureButtons(frame)
    if not button then return false, reason end
    local hooked, hookReason = Adapter:InstallCopyHoverHooks(
        frame,
        CopyFrameEntered,
        CopyFrameLeft
    )
    if not hooked then
        button:Hide()
        if scrollButton then scrollButton:Hide() end
        return false, hookReason
    end
    return RefreshButtonVisibility(frame)
end

local function ReconcileDiscovered(frame)
    ReconcileFrame(frame)
end

function CopyViewer:SetEnabled(enabled, reason)
    self.enabled = enabled == true
    if self.enabled then
        local popupOK, popupReason = EnsurePopup()
        if not popupOK then
            self.enabled = false
            self.lastReason = popupReason
            return false, popupReason
        end
    else
        HidePopup()
    end
    Adapter:ForEachSupportedFrame(ReconcileDiscovered)
    for frame, button in pairs(buttonFrames) do
        if not self.enabled then
            button:Hide()
            local scrollButton = scrollButtonFrames[frame]
            if scrollButton then scrollButton:Hide() end
        else
            ReconcileFrame(frame)
        end
    end
    self.lastReason = reason or (self.enabled and "copy-enabled" or "copy-disabled")
    return true
end

function CopyViewer:OnFrameDiscovered(frame, valid)
    if valid ~= true then
        local button = buttonFrames[frame]
        if button then button:Hide() end
        local scrollButton = scrollButtonFrames[frame]
        if scrollButton then scrollButton:Hide() end
        return true
    end
    return ReconcileFrame(frame)
end

function CopyViewer:OnWindowsChanged()
    if not self.enabled then return true end
    Adapter:ForEachSupportedFrame(ReconcileDiscovered)
    return true
end

function CopyViewer:OnRestrictionStateChanged()
    local restriction = Adapter:GetRestrictionState()
    local controlsAllowed = restriction == "OPEN" or restriction == "PAUSED"
    if self.enabled and controlsAllowed then
        Adapter:ForEachSupportedFrame(ReconcileDiscovered)
    end
    for frame, button in pairs(buttonFrames) do
        if not self.enabled or not controlsAllowed then
            button:Hide()
            local scrollButton = scrollButtonFrames[frame]
            if scrollButton then scrollButton:Hide() end
        else
            RefreshButtonVisibility(frame)
        end
    end
    return true
end

function CopyViewer:RestoreAll()
    self.enabled = false
    HidePopup()
    for frame, button in pairs(buttonFrames) do
        button:Hide()
        local scrollButton = scrollButtonFrames[frame]
        if scrollButton then scrollButton:Hide() end
    end
    return true
end

function CopyViewer:OpenTextSnapshot(titleText, text)
    if not self.enabled then return false, "copy-disabled" end
    ClearExportBuffer()
    return PresentText(titleText, text, "history-snapshot-open")
end

function CopyViewer:GetRuntimeGauges(target)
    target = target or {}
    target.copyPopupShown = self.popup and self.popup:IsShown() and 1 or 0
    target.copyBufferedLines = #exportLines
    return target
end
