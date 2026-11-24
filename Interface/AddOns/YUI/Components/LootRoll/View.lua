local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI or not YUI.IsForever or not YUI.GUI2 then return end
local GUI, M = YUI.GUI2, YUI.LootRollModel
local L = YUI.Locale:Get("LootRoll")
local API = YUI.API.LootRoll
local Appearance = GUI.WindowAppearance
local ROW_HEIGHT, ROW_GAP, FOOTER_HEIGHT = 42, 2, 28
local ROW_STRIDE = ROW_HEIGHT + ROW_GAP
local QUEUE_ITEM_X, QUEUE_VOTE_INSET, ITEM_NAME_SIZE = ROW_HEIGHT + 5, 106, 14
local VOTE_BUTTON_WIDTH, VOTE_BUTTON_GAP = 24, 12
local QUEUE_ITEM_INSET = QUEUE_ITEM_X + QUEUE_VOTE_INSET
local MAX_VISIBLE, ROW_POOL_SIZE = 12, 24
local HISTORY_PAGE_SIZE, HISTORY_WIDTH = 10, 592
local HISTORY_ROW_HEIGHT, HISTORY_RESULT_WIDTH, HISTORY_DATE_WIDTH = 44, 212, 116
local HISTORY_TABLE_TOP = 70
local HISTORY_HEIGHT = HISTORY_TABLE_TOP + 42 + HISTORY_PAGE_SIZE * HISTORY_ROW_HEIGHT
local POPUP_MIN_WIDTH, POPUP_MAX_WIDTH, ROSTER_ROW_HEIGHT = 232, 376, 21
local SUMMARY_MAX_WIDTH, SUMMARY_RESULT_WIDTH = 448, 212
local SUMMARY_FOOTER_HEIGHT, SUMMARY_HINT_LINE_HEIGHT, SUMMARY_SECTION_HEIGHT = 24, 16, 18
local RESULT_ICON_SIZE, SUMMARY_GAP = 32, 10
local RESULT_ITEM_X = 8 + RESULT_ICON_SIZE + 6
local ROSTER_ICON_SIZE, ROSTER_ICON_GAP, ROSTER_SCORE_WIDTH = 14, 4, 24
local COMPLETION_SECONDS = 10
local URGENCY_SECONDS, PULSE_SECONDS = 8, 3
local URGENCY_TINT, PULSE_TINT = 0.60, 0.20
local PULSE_DURATION, PULSE_DEADLINE_WINDOW = 0.8, 0.1
local TRACK_HEIGHT = 3
local TRACK_RED, TRACK_GREEN, TRACK_BLUE = 0.85, 0.66, 0.27
local TRACK_PIXEL_POLICY = { snapToPixelGrid = true }
local HISTORY_FILTER_ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
local V = { DEFAULT_HISTORY_FONT_SIZE = 14 }
YUI.LootRollView = V
local stateKeys = { [0] = "main", [1] = "off", [2] = "transmog", [3] = "greed", [4] = "waiting", [5] = "pass" }
local rollStates = Enum and Enum.EncounterLootDropRollState
if rollStates and rollStates.Disenchant then stateKeys[rollStates.Disenchant] = "disenchant" end
local choiceColors = { need = "color.text.rewardHeading", greed = "color.state.success",
    transmog = "color.state.success", disenchant = "color.state.success" }
function V.ChoicePresentation(state)
    local choice = (state == 0 or state == 1) and "need" or stateKeys[state]
    return choice, choiceColors[choice]
end
local function Text(region, value)
    value = value or ""
    if region:GetText() ~= value then region:SetText(value) end
end
local function Label(state) return L["choice." .. (stateKeys[state] or "waiting")] end
local function ColorPlayer(text, p)
    local color = p and RAID_CLASS_COLORS[p.playerClass]
    if color then text:SetTextColor(color.r, color.g, color.b) else text:SetTextColor(GUI:GetColor("color.text.secondary")) end
end
local function Font(parent, size, plain, wrap)
    local text = GUI:CreateText(parent, "", size)
    text.gui2ColorKey, text.gui2ColorFallback = nil, nil
    text:SetFont(GUI:GetFont("font.family.body"), size, plain and "" or "OUTLINE")
    text:SetShadowColor(0, 0, 0, plain and 0 or 1)
    text:SetShadowOffset(plain and 0 or 1, plain and 0 or -1)
    text:SetWordWrap(wrap == true)
    if not wrap then text:SetMaxLines(1) end
    return text
end
local function NaturalWidth(region)
    return math.ceil((region.GetUnboundedStringWidth or region.GetStringWidth)(region)) + 2
end
local function FitQueueName(text, name, width)
    local nameChanged = text:GetText() ~= name
    if not nameChanged and text:GetWidth() == width and not text.lootFontChanged then return end
    text.lootFontChanged = nil
    if nameChanged then text:SetText(name) end
    text:SetWidth(width)
    local currentScale = text:GetTextScale()
    local fullWidth = text:GetUnboundedStringWidth() / currentScale
    local scale = math.min(1, (width - 2) / math.max(1, fullWidth))
    if scale ~= currentScale then text:SetTextScale(scale) end
    local scaleStep = 1 / (text.lootFontSize or ITEM_NAME_SIZE)
    while scale > scaleStep and text:IsTruncated() do
        scale = math.max(scaleStep, scale - scaleStep)
        text:SetTextScale(scale)
    end
end
local function FitMetadata(row, timerSpace)
    row.meta:SetWidth(math.max(1, math.min(NaturalWidth(row.meta), row.metaMaxWidth - timerSpace)))
end
local function TextHeight(region, minimum)
    region:SetHeight(0)
    local height = math.max(minimum or 0, math.ceil(region:GetStringHeight()) + 2)
    region:SetHeight(height)
    return height
end
local function FlowText(region, value, top, gap)
    Text(region, value)
    if value == "" then region:Hide(); return top end
    region:ClearAllPoints(); region:SetPoint("TOPLEFT", 10, -top)
    region:Show()
    return top + TextHeight(region) + (gap or 2)
end
local function ResultLayout(row)
    if row.stamp then
        local first = math.max(TextHeight(row.name, 18), TextHeight(row.stamp, 18), TextHeight(row.score, 18))
        local second = math.max(TextHeight(row.meta, 16), TextHeight(row.source, 16), TextHeight(row.leader, 16))
        local resultX = -16 - HISTORY_DATE_WIDTH
        row.item:SetHeight(first + second)
        row.meta:ClearAllPoints(); row.meta:SetPoint("TOPLEFT", 0, -first)
        row.score:ClearAllPoints(); row.score:SetPoint("TOPRIGHT", resultX, -5)
        row.leader:ClearAllPoints(); row.leader:SetPoint("TOPRIGHT", resultX, -5 - first)
        row.stamp:ClearAllPoints(); row.stamp:SetPoint("TOPRIGHT", -8, -5)
        row.source:ClearAllPoints(); row.source:SetPoint("TOPRIGHT", -8, -5 - first)
        row:SetHeight(first + second + 10)
        return
    end
    local top = 8
    local nameHeight, metaHeight = TextHeight(row.name, 20), TextHeight(row.meta, 18)
    local scoreHeight, leaderHeight = TextHeight(row.score, 18), TextHeight(row.leader, 18)
    row.item:SetHeight(nameHeight + metaHeight)
    row.meta:ClearAllPoints(); row.meta:SetPoint("TOPLEFT", 0, -nameHeight)
    row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", 8, -top)
    row.score:ClearAllPoints(); row.score:SetPoint("TOPRIGHT", -8, -top)
    row.leader:ClearAllPoints(); row.leader:SetPoint("TOPRIGHT", -8, -top - scoreHeight)
    row:SetHeight(top + math.max(32, nameHeight + metaHeight, scoreHeight + leaderHeight) + 6)
end
local function BindMotion(view, row)
    row.motionSpec = { owner = view, target = row, key = "loot-row-motion", from = 0, to = 1, easing = "out" }
    row.motionSpec.onUpdate = function(value)
        view:SetRowPose(row, row.fromX + (row.toX - row.fromX) * value,
            row.fromY + (row.toY - row.fromY) * value, row.fromAlpha + (row.toAlpha - row.fromAlpha) * value)
    end
    row.motionSpec.onFinished = function(handle, _, finished)
        if row.motion ~= handle then return end
        row.motion = nil
        if finished then
            view:SetRowPose(row, row.toX, row.toY, row.toAlpha)
            if row.phase == "leaving" then view:FreeRow(row) end
            view:RefreshQueueInput()
        end
    end
end
local function Surface(parent, width, height, kind)
    return GUI:CreateFrame(parent, { type = kind or "Frame", template = "BackdropTemplate", width = width, height = height,
        surface = "color.surface.panel", border = "color.border.default", mouse = true })
end
local function BringToFront(frame)
    local settings = _G.YUI_SettingsFrame
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(math.max(200, settings and settings:GetFrameLevel() + 30 or 0))
    frame:Raise()
end
local function Remaining(record, now)
    if record.preview then return record.remaining or record.duration end
    return math.max(0, record.deadline - now)
end
local function SetUrgency(row, amount)
    if row.urgency == amount then return end
    local red, green, blue = GUI:GetColor("color.state.error")
    local urgent = amount > 0
    if (row.urgency > 0) ~= urgent then
        if urgent then
            row.timerText:SetTextColor(red, green, blue)
            row.track:SetStatusBarColor(red, green, blue)
        else
            row.timerText:SetTextColor(GUI:GetColor("color.text.secondary"))
            row.track:SetStatusBarColor(TRACK_RED, TRACK_GREEN, TRACK_BLUE)
        end
    end
    row.urgency = amount
    local color = row.backgroundStart
    color.r, color.g, color.b = red * amount, green * amount, blue * amount
    row.background:SetGradient("HORIZONTAL", color, row.backgroundEnd)
end
local TIMER_TEXT_WIDTH = 52
local function TimerText(remaining)
    local seconds = math.ceil(remaining)
    if seconds == 0 then return "—" end
    if seconds >= 60 then return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60) end
    return seconds .. "s"
end
local function CloseItemTooltip(row)
    if GameTooltip and (GameTooltip:IsOwned(row.icon) or GameTooltip:IsOwned(row.item)) then GameTooltip:Hide() end
end
local function CanUseQueue(view)
    local controller = view.controller
    return controller.active and controller.nativeTakeover == true and not view.editing and not controller.editPreview
end
local function CanInspectQueue(view)
    return not view.editing and (view.displayPreview or CanUseQueue(view))
end
local function CanInspectSummary(view)
    local controller = view.controller
    return not view.editing and (view.displayPreview or controller.active and not controller.gamepad and not controller.editPreview)
end
local function ClearPress(button)
    button.armed, button.armedAction, button.armedModifiers = nil, nil, nil
end
local function Modifiers()
    return (IsShiftKeyDown and IsShiftKeyDown() and 1 or 0)
        + (IsControlKeyDown and IsControlKeyDown() and 2 or 0)
        + (IsAltKeyDown and IsAltKeyDown() and 4 or 0)
        + (IsMetaKeyDown and IsMetaKeyDown() and 8 or 0)
end
local function BindRowClick(view, row, vote)
    local function Action(button)
        local record = row.record
        if not row.inputEnabled or not CanInspectQueue(view) or not record
            or not record.active or record.selfState ~= 4 then return end
        if not vote then return record.data.link end
        if not record.preview and CanUseQueue(view) and API.Allowed(record.data, button.choice) and not API.IsConfirming() then
            return button.choice
        end
    end
    local function OnMouseDown(button, mouse)
        if mouse ~= "LeftButton" then return end
        ClearPress(button)
        local action = Action(button)
        if action then button.armed, button.armedAction, button.armedModifiers = row.record, action, Modifiers() end
    end
    local function OnClick(button, mouse, down)
        if mouse ~= "LeftButton" or down then return end
        local record, action, modifiers = button.armed, button.armedAction, button.armedModifiers
        ClearPress(button)
        if not record or row.record ~= record or action ~= Action(button) or modifiers ~= Modifiers() then return end
        if vote then view.controller:Choose(record, action)
        else HandleModifiedItemClick(action) end
    end
    return OnMouseDown, OnClick
end
local function VoteAtlas(button, choice)
    for method, suffix in pairs({ SetNormalAtlas = "up", SetHighlightAtlas = "highlight", SetPushedAtlas = "down" }) do
        button[method](button, "lootroll-toast-icon-" .. choice .. "-" .. suffix)
    end
end
local function Result(record, compact)
    local drop, own = record.drop, Label(record.selfState)
    local unselected = record.selfState == 4 and (record.status == "complete" or record.rollID and not record.active)
    if unselected then own = L["choice.unselected"] end
    if record.selfRoll then own = own .. " " .. record.selfRoll end
    local ownLine = L["result.self"]:format(own)
    if record.selfState == 4 and record.request then
        local action = record.request == "need" and NEED or Label(record.request == "greed" and 3 or record.request == "transmog" and 2 or 5)
        local key = (M.Terminal(record) or record.choiceEndedAt) and "result.requestUnconfirmed" or "result.request"
        ownLine = L[key]:format(action or Label(0))
    end
    if record.status == "unavailable" then return L["status.unavailable"], ownLine, nil end
    if not drop then return L[record.ambiguous and "status.ambiguous" or "status.sync"], ownLine, nil end
    if drop.allPassed then return L["result.allPassed"], L["result.noWinner"], nil end
    local p = drop.winner or drop.currentLeader
    if not p then return L[(drop.rosterAllPassed or unselected) and "status.settling" or "result.waiting"], ownLine, nil end
    if compact and record.selfRoll and record.selfState == p.state then own = tostring(record.selfRoll) end
    local key = drop.winner and "result.won" or "result.leading"
    if compact then key = key .. "Compact" end
    local name = compact and ((drop.winner and "★ " or drop.isTied and "= " or "") .. (p.playerName or "—"))
        or L[drop.winner and "result.winner" or drop.isTied and "result.tied" or "result.leader"]:format(p.playerName or "—")
    if drop.winner and p.isSelf then return L["result.wonSelf"]:format(Label(p.state), p.roll or record.selfRoll or "—"), name, p end
    return L[key]:format(Label(p.state), p.roll or "—", own), name, p
end
V.Result = Result
function V.New(controller, placement)
    local self = { controller = controller, rows = {}, rowPool = {}, rowByRecord = {}, desired = {}, exitingCount = 0,
        summaryRows = {}, historyRows = {}, people = {}, page = 1, offset = 0, builds = 1, writes = 0,
        batchRecords = {}, batchResults = setmetatable({}, { __mode = "k" }),
        batchModel = controller.model, batchGeneration = controller.model.generation,
        batchSerial = controller.model.serial, pulsed = setmetatable({}, { __mode = "k" }), pulseDeadlines = {} }
    local hud = GUI:CreateFrame(UIParent, { name = "YUILootRollHUD", width = controller.config.width, height = 290, strata = "DIALOG", clamped = true, mouse = false })
    self.hud = hud
    -- Layout 保存 UIParent 单位的位置和边界；缩放只作用于内部队列。
    local content = GUI:CreateFrame(hud, { width = controller.config.width, height = 290, mouse = false })
    self.content = content
    content:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    self.previewLabel = Font(content, 13)
    self.previewLabel:SetPoint("BOTTOMLEFT", content, "TOPLEFT", 0, 4)
    Text(self.previewLabel, L["preview.label"]); self.previewLabel:Hide()
    local anchor, offset = placement.anchor, placement.offset
    hud:SetPoint(anchor.point, UIParent, anchor.relativePoint, offset.x, offset.y)
    local footer = GUI:CreateFrame(content, { height = FOOTER_HEIGHT, mouse = true })
    self.footer, self.more = footer, Font(footer, 13)
    BindMotion(self, footer)
    self.more:SetPoint("LEFT", 0, 0)
    local settling = GUI:CreateFrame(footer, { type = "Button", width = 1, height = 22, mouse = true, mouseWheel = true })
    self.settling, self.settlingText = settling, Font(settling, 13)
    settling:SetPoint("RIGHT"); self.settlingText:SetPoint("RIGHT", -1, 0); self.settlingText:SetJustifyH("RIGHT")
    settling:RegisterForClicks("LeftButtonUp")
    settling:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then
            settling.armedModifiers = footer.inputEnabled and CanInspectSummary(self) and Modifiers() or nil
        end
    end)
    settling:SetScript("OnClick", function(_, mouse, down)
        if mouse ~= "LeftButton" or down then return end
        local modifiers = settling.armedModifiers
        settling.armedModifiers = nil
        if footer.inputEnabled and CanInspectSummary(self) and modifiers == Modifiers() then controller:OpenHistory() end
    end)
    local popup = Surface(UIParent, POPUP_MIN_WIDTH, 96)
    popup:SetFrameStrata("TOOLTIP"); popup:SetClampedToScreen(true); popup:EnableMouseWheel(true); popup:Hide()
    self.popup, self.popupTitle, self.popupInfo = popup, Font(popup, 14, nil, true), Font(popup, 12, nil, true)
    self.popupAction = Font(popup, 15, nil, true)
    self.popupAction:SetTextColor(GUI:GetColor("color.text.rewardHeading"))
    self.popupAction:Hide()
    self.popupBackground = GUI:CreateTexture(popup, { layer = "BACKGROUND", subLevel = -1 })
    self.popupBackground:SetPoint("TOPLEFT", 1, -1); self.popupBackground:SetPoint("BOTTOMRIGHT", -1, 1)
    self.popupSummaryHint = Font(popup, 12); self.popupSummaryHint:SetPoint("BOTTOMLEFT", 10, 8)
    self.popupSummaryHint:SetWidth(SUMMARY_MAX_WIDTH - 20); self.popupSummaryHint:SetJustifyH("LEFT")
    self.popupSummaryHint:SetTextColor(GUI:GetColor("color.text.secondary")); Text(self.popupSummaryHint, L["queue.open"]); self.popupSummaryHint:Hide()
    self.popupSummaryRange = Font(popup, 12); self.popupSummaryRange:SetPoint("BOTTOMLEFT", self.popupSummaryHint, "TOPLEFT", 0, 2)
    self.popupSummaryRange:SetJustifyH("LEFT"); self.popupSummaryRange:SetTextColor(GUI:GetColor("color.text.secondary")); self.popupSummaryRange:Hide()
    self.popupSummarySettling, self.popupSummarySettled = Font(popup, 12, true), Font(popup, 12, true)
    Text(self.popupSummarySettling, L["status.settling"]); self.popupSummarySettling:Hide()
    Text(self.popupSummarySettled, L["status.complete"]); self.popupSummarySettled:Hide()
    self.rosterNameMeasure, self.rosterPickMeasure = Font(popup, 14), Font(popup, 13, true)
    self.rosterNameMeasure:Hide(); self.rosterPickMeasure:Hide()
    self.rosterText = { self.popupAction, self.popupTitle, self.popupInfo }
    for _, region in ipairs(self.rosterText) do
        region:SetJustifyH("LEFT"); region:SetJustifyV("TOP")
    end
    local function CancelClose() if self.closeTimer then self.closeTimer:Cancel(); self.closeTimer = nil end end
    local function Leave()
        CancelClose()
        if not self.popup:IsShown() then return end
        self.closeTimer = C_Timer.NewTimer(0.10, function() self.closeTimer = nil; self:CloseHover() end)
    end
    self.cancelClose, self.leave = CancelClose, Leave
    popup:SetScript("OnEnter", CancelClose); popup:SetScript("OnLeave", Leave)
    popup:SetScript("OnMouseWheel", function(_, delta) self:Wheel(delta) end)
    local function AttachHover(frame, row, kind)
        local canInspect = kind == "summary" and CanInspectSummary or CanInspectQueue
        local function HasInput() return row.inputEnabled and canInspect(self) end
        frame:EnableMouseWheel(true)
        frame:SetScript("OnEnter", function()
            if not HasInput() then return end
            local record = row.record
            if record and not record.preview and CanUseQueue(self) then controller:RefreshChoice(record) end
            if not HasInput() or row.record ~= record then return end
            self:Hover(record, kind, frame)
        end)
        frame:SetScript("OnLeave", function() if HasInput() then Leave() end end)
        frame:SetScript("OnMouseWheel", function(_, delta) if HasInput() then CancelClose(); self:Wheel(delta) end end)
    end
    local function CreateItem(parent, result, width, stripe)
        local row = stripe and GUI:CreateFrame(parent, { width = width, height = HISTORY_ROW_HEIGHT, mouse = true })
            or result and Surface(parent, width, 52, "Button")
            or GUI:CreateFrame(parent, { width = controller.config.width, height = ROW_HEIGHT, mouse = false })
        local iconSize = result and RESULT_ICON_SIZE or ROW_HEIGHT
        if stripe then
            row.stripe = GUI:CreateTexture(row, { paint = stripe, layer = "BACKGROUND" })
            row.stripe:SetAllPoints()
        end
        local itemDown, itemClick
        if not result then itemDown, itemClick = BindRowClick(self, row, false) end
        row.icon = GUI:CreateIconSlot(row, { size = iconSize, variant = "bare", animate = false,
            shape = "roundedSquare", border = "contour", zoom = 0.08, materialTint = true, clicks = "LeftButtonUp",
            onClick = itemClick })
        row.icon:SetPoint("LEFT", result and 8 or 0, 0)
        if not result then
            row.background = GUI:CreateTexture(row, { texture = "Interface\\Buttons\\WHITE8X8", layer = "BACKGROUND" })
            row.background:SetBlendMode("BLEND")
            row.backgroundStart, row.backgroundEnd = CreateColor(0, 0, 0, 0.65), CreateColor(0, 0, 0, 0)
            row.urgency = 0
            row.background:SetGradient("HORIZONTAL", row.backgroundStart, row.backgroundEnd)
            row.background:SetPoint("LEFT", row.icon, "CENTER", 0, 0)
            row.background:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.background:SetHeight(iconSize)
        end
        row.texture = row.icon.icon
        row.shadow = GUI:CreateShapeShadow(row.icon)
        GUI:ApplyShapeShadow(row.shadow, { enabled = true, shape = "roundedSquare" },
            { anchor = row.icon, width = iconSize, height = iconSize, allowLayout = true })
        if not stripe then
            row.voted = Font(row.icon, 12); row.voted:SetPoint("BOTTOM", 0, -1); row.voted:SetDrawLayer("OVERLAY", 7)
        end
        row.quantity = Font(row.icon, 12); row.quantity:SetPoint("TOPRIGHT", 0, 2)
        row.quantity:SetDrawLayer("OVERLAY", 7)
        row.binding = Font(row.icon, 10)
        if result then
            row.binding:SetPoint("CENTER", row.icon, "TOP", 0, -1)
        else
            row.binding:SetPoint("TOP", row.icon, "TOP", 0, -3)
            row.binding:SetWidth(iconSize)
            row.binding:SetJustifyH("CENTER")
        end
        row.binding:SetDrawLayer("OVERLAY", 7)
        row.binding:SetTextColor(GUI:GetColor("color.text.secondary"))
        row.binding:Hide()
        local itemX = RESULT_ITEM_X
        local resultWidth = stripe and HISTORY_RESULT_WIDTH or SUMMARY_RESULT_WIDTH
        row.metaMaxWidth = stripe and (width - itemX - 24 - HISTORY_RESULT_WIDTH - HISTORY_DATE_WIDTH)
            or result and (width - itemX - 16 - resultWidth) or controller.config.width - QUEUE_ITEM_INSET
        row.item = GUI:CreateButtonFrame(row, { width = row.metaMaxWidth, height = result and 38 or 30, clicks = "LeftButtonUp" })
        if stripe then row.item:SetPoint("TOPLEFT", itemX, -5)
        elseif result then row.item:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
        else row.item:SetPoint("LEFT", row, "LEFT", QUEUE_ITEM_X, 0) end
        row.name = Font(row.item, stripe and V.DEFAULT_HISTORY_FONT_SIZE or ITEM_NAME_SIZE)
        row.meta = Font(row.item, 12)
        row.timerText = Font(row.item, 12); row.timerText:SetWidth(TIMER_TEXT_WIDTH); row.timerText:SetJustifyH("LEFT")
        row.timerText:SetPoint("LEFT", row.meta, "RIGHT", 5, 0)
        row.timerText:SetTextColor(GUI:GetColor("color.text.secondary"))
        row.name:SetPoint("TOPLEFT", 0, 0); row.name:SetWidth(row.metaMaxWidth); row.name:SetHeight(result and 20 or 16); row.name:SetJustifyH("LEFT")
        row.meta:SetPoint("BOTTOMLEFT", 0, 0); row.meta:SetWidth(row.metaMaxWidth); row.meta:SetHeight(result and 18 or 14); row.meta:SetJustifyH("LEFT")
        if result then
            row.score, row.leader = Font(row, 13, true), Font(row, 13, true)
            row.score:SetWidth(resultWidth); row.score:SetJustifyH("RIGHT")
            row.leader:SetWidth(resultWidth); row.leader:SetJustifyH("RIGHT")
            row.timerText:Hide()
            -- 摘要没有二级交互，只有整个历史行可以悬停名单。
            row.icon:EnableMouse(false); row.item:EnableMouse(false)
        else
            row.icon:SetScript("OnMouseDown", itemDown)
            row.item:SetScript("OnMouseDown", itemDown)
            row.item:SetScript("OnClick", itemClick)
            local function EnterItem(owner)
                local record = row.record
                if not row.inputEnabled or not CanInspectQueue(self) or not record then return end
                self:CloseHover()
                API.ShowItemTooltip(owner, not record.preview and record.active and record.rollID or nil, record.data.link)
            end
            local function LeaveItem(owner)
                if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
            end
            row.icon:SetScript("OnEnter", EnterItem); row.icon:SetScript("OnLeave", LeaveItem)
            row.item:SetScript("OnEnter", EnterItem); row.item:SetScript("OnLeave", LeaveItem)
            row.buttons = {}
            local voteDown, voteClick = BindRowClick(self, row, true)
            for i = 1, 3 do
                local button = GUI:CreateButtonFrame(row, { width = VOTE_BUTTON_WIDTH, height = 26, clicks = "LeftButtonUp" })
                button:SetPoint("RIGHT", row, "RIGHT", -3 - (3 - i) * (VOTE_BUTTON_WIDTH + VOTE_BUTTON_GAP), -2)
                button.count = Font(button, 20); button.count:SetFont(DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT, 20, "OUTLINE")
                button.count:SetPoint("TOP", 0, 5)
                button:SetScript("OnMouseDown", voteDown)
                button:SetScript("OnClick", voteClick)
                AttachHover(button, row, i == 1 and "need" or i == 3 and "pass" or "middle")
                row.buttons[i] = button
            end
            row.track = CreateFrame("StatusBar", nil, row)
            row.track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", QUEUE_ITEM_X, 0)
            row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 0)
            row.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            row.track:SetStatusBarColor(TRACK_RED, TRACK_GREEN, TRACK_BLUE)
            GUI:ApplyTexturePixelPolicy(row.track:GetStatusBarTexture(), TRACK_PIXEL_POLICY)
            local trackBackground = GUI:CreateTexture(row.track, { paint = "color.control.track", layer = "BACKGROUND" })
            trackBackground:SetAllPoints()
            GUI:ApplyTexturePixelPolicy(trackBackground, TRACK_PIXEL_POLICY)
        end
        return row
    end
    self.createItem = CreateItem
    for index = 1, ROW_POOL_SIZE do
        local row = CreateItem(content)
        row.phase = "free"; row:Hide(); self.rowPool[index] = row
        BindMotion(self, row)
        V.SetRowInput(self, row, false)
    end
    function hud.UpdateGUI2PixelLayout(frame)
        local height = math.max(GUI:GetPixelSize(content), GUI:SnapLayoutBoundary(content, TRACK_HEIGHT))
        for _, row in ipairs(self.rowPool) do row.track:SetHeight(height) end
    end
    table.insert(GUI.PixelObjects, hud)
    hud:UpdateGUI2PixelLayout()
    for index = 1, 8 do
        local line = GUI:CreateFrame(popup, { height = ROSTER_ROW_HEIGHT })
        line.name, line.pick, line.score = Font(line, 14), Font(line, 13, true), Font(line, 14, true)
        line.name:SetPoint("LEFT"); line.name:SetHeight(ROSTER_ROW_HEIGHT); line.name:SetJustifyH("LEFT")
        line.pick:SetPoint("RIGHT", -ROSTER_SCORE_WIDTH - 8, 0); line.pick:SetHeight(18); line.pick:SetJustifyH("LEFT")
        line.score:SetPoint("RIGHT"); line.score:SetWidth(ROSTER_SCORE_WIDTH); line.score:SetHeight(20); line.score:SetJustifyH("RIGHT")
        line.icon = GUI:CreateTexture(line, { width = ROSTER_ICON_SIZE, height = ROSTER_ICON_SIZE, layer = "ARTWORK" })
        line.icon:SetPoint("RIGHT", line.pick, "LEFT", -ROSTER_ICON_GAP, 0)
        self.people[index] = line
    end
    self.summaryRows[1] = CreateItem(popup, true, SUMMARY_MAX_WIDTH - 16)
    self.summaryRows[1]:EnableMouse(false)
    AttachHover(settling, footer, "summary")
    V.SetFooterInput(self, false)
    hud:Hide()
    return setmetatable(self, { __index = V })
end
function V:SetRowInput(row, enabled)
    if row.inputEnabled == enabled then return end
    row.inputEnabled = enabled
    if not enabled then
        if row.record and self.hoverRecord == row.record and not self.hoverHistory then self:CloseHover() end
        CloseItemTooltip(row)
        ClearPress(row.icon); ClearPress(row.item)
    end
    row.icon:EnableMouse(enabled)
    row.item:EnableMouse(enabled)
    for _, button in ipairs(row.buttons) do
        if not enabled then ClearPress(button) end
        button:EnableMouse(enabled); button:EnableMouseWheel(enabled)
    end
end
function V:SetFooterInput(enabled)
    if self.footer.inputEnabled == enabled then return end
    self.footer.inputEnabled = enabled
    if not enabled then self.settling.armedModifiers = nil end
    self.footer:EnableMouse(enabled)
    self.settling:EnableMouse(enabled); self.settling:EnableMouseWheel(enabled)
end
local function MotionOverlaps(direction, start, finish, other, height)
    if not other.motion or not other:IsShown() then return false end
    local from, target = direction * other.poseY, direction * other.toY
    return start < math.max(from, target) + height and finish > math.min(from, target)
end
function V:IsQueueSlotClear(row, height)
    if row.motion or row.poseAlpha ~= 1 then return false end
    local direction = self.growth == "up" and 1 or -1
    local start = direction * row.poseY
    local finish = start + height
    if MotionOverlaps(direction, start, finish, self.footer, FOOTER_HEIGHT) then return false end
    for _, other in ipairs(self.rowPool) do
        if MotionOverlaps(direction, start, finish, other, ROW_HEIGHT) then return false end
    end
    return true
end
function V:RefreshQueueInput()
    -- 输入区只在当前行就位且其他动画不会经过该位置时开放。
    local enabled = self.hud:IsShown() and CanInspectQueue(self)
    for _, row in ipairs(self.rows) do
        self:SetRowInput(row, enabled and row.phase == "active" and self:IsQueueSlotClear(row, ROW_HEIGHT) or false)
    end
    self:SetFooterInput(self.hud:IsShown() and CanInspectSummary(self) and self.footer:IsShown() and self.settling:IsShown()
        and self:IsQueueSlotClear(self.footer, FOOTER_HEIGHT) or false)
end
function V:SetRowPose(row, x, y, alpha)
    row.poseX, row.poseY, row.poseAlpha = x, y, alpha
    local point = self.growth == "up" and "BOTTOMLEFT" or "TOPLEFT"
    row:ClearAllPoints(); row:SetPoint(point, self.content, point, x, y); row:SetAlpha(alpha)
end
function V:FreeRow(row)
    if row.motion then local handle = row.motion; row.motion = nil; handle:Stop(false) end
    if self.pulseRow == row then self.pulseRow = nil end
    SetUrgency(row, 0)
    if row.phase == "leaving" then self.exitingCount = math.max(0, self.exitingCount - 1) end
    if self.rowByRecord[row.record] == row then self.rowByRecord[row.record] = nil end
    row.phase, row.record, row.toX, row.toY, row.toAlpha = "free", nil, nil, nil, nil
    row:Hide(); row:SetAlpha(1); self:SetRowInput(row, false)
    if self.exitingCount == 0 and #self.rows == 0 and #(self.tracked or {}) == 0 and not self.completeUntil then self.hud:Hide() end
end
function V:StopMotion(clear)
    if YUI.Animation and YUI.Animation.StopOwner then YUI.Animation:StopOwner(self, false) end
    self.pulseRow = nil
    for _, row in ipairs(self.rowPool) do
        self:SetRowInput(row, false)
        row.motion = nil
        if clear or row.phase == "leaving" then self:FreeRow(row)
        elseif row.phase == "active" and row.toY then self:SetRowPose(row, row.toX, row.toY, row.toAlpha) end
    end
    self:SetFooterInput(false)
    self.footer.motion = nil
    if self.footer.toY then self:SetRowPose(self.footer, 0, self.footer.toY, 1) end
    if clear then
        for index = #self.rows, 1, -1 do self.rows[index] = nil end
        for record in pairs(self.desired) do self.desired[record] = nil end
    end
end
function V:MoveRow(row, x, y, alpha, duration)
    if row.toX == x and row.toY == y and row.toAlpha == alpha and not self.suppressMotion and (duration > 0 or not row.motion) then return end
    if row.motion then local handle = row.motion; row.motion = nil; handle:Stop(false) end
    row.fromX, row.fromY, row.fromAlpha = row.poseX or x, row.poseY or y, row.poseAlpha or 1
    row.toX, row.toY, row.toAlpha = x, y, alpha
    local changed = row.fromX ~= x or row.fromY ~= y or row.fromAlpha ~= alpha
    if changed and duration > 0 and not self.suppressMotion and YUI.Animation and YUI.Animation.Tween then
        if row == self.footer then self:SetFooterInput(false) else self:SetRowInput(row, false) end
        row.motionSpec.duration = duration
        row.motion = YUI.Animation:Tween(row.motionSpec)
        if row.motion and row.motion:IsPlaying() then return end
        row.motion = nil
    end
    self:SetRowPose(row, x, y, alpha)
    if row.phase == "leaving" then self:FreeRow(row) end
end
function V:ReleaseRow(row)
    if row.phase ~= "active" then return end
    if self.pulseRow == row then
        self.pulseRow = nil
        SetUrgency(row, URGENCY_TINT)
    end
    if self.hoverAnchor == row then self:CloseHover() end
    if self.rowByRecord[row.record] == row then self.rowByRecord[row.record] = nil end
    row.phase = "leaving"; self.exitingCount = self.exitingCount + 1
    self:SetRowInput(row, false)
    self:MoveRow(row, 8, row.poseY or row.toY or 0, 0, 0.10)
end
function V:AcquireRow(record)
    local row = self.rowByRecord[record]
    if row then return row, false end
    for _, candidate in ipairs(self.rowPool) do
        if candidate.phase == "leaving" and candidate.record == record then
            candidate.phase = "active"; self.exitingCount = self.exitingCount - 1
            self.rowByRecord[record] = candidate
            return candidate, false
        end
    end
    for _, candidate in ipairs(self.rowPool) do if candidate.phase == "free" then row = candidate; break end end
    if not row then
        for _, candidate in ipairs(self.rowPool) do if candidate.phase == "leaving" then self:FreeRow(candidate); row = candidate; break end end
    end
    if not row then return nil end
    row.phase, row.record, row.toX, row.toY, row.toAlpha = "active", record, nil, nil, nil
    self.rowByRecord[record] = row
    return row, true
end
function V:GetAnimationCount()
    local count = self.footer.motion and self.footer.motion:IsPlaying() and 1 or 0
    for _, row in ipairs(self.rowPool) do if row.motion and row.motion:IsPlaying() then count = count + 1 end end
    return count
end
function V:SetEditing(editing)
    editing = editing == true
    if self.editing == editing then return end
    self.editing = editing
    self:StopMotion(false)
    self:CloseHover()
    self.hud:EnableMouse(false)
    if editing then
        for _, row in ipairs(self.historyRows) do CloseItemTooltip(row) end
    end
end
function V:GetMoverBounds()
    -- 包含图标外阴影与文字描边，不改变实际队列锚点。
    local padding = 12 * (self.queueScale or 1)
    return self.hud:GetWidth() + padding, self.hud:GetHeight() + padding, 0, 0
end
local function ResolveFont(font, fallback)
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = media and media:Fetch("font", font, true)
    return type(path) == "string" and path ~= "" and path or fallback
end
function V:ApplyQueueAppearance()
    local config = self.controller.config
    local font, size, countSize, scale = config.font, config.fontSize or 14,
        config.countFontSize or 20, config.scale or 1
    local changed = false
    if self.queueScale ~= scale then
        self.queueScale, changed = scale, true
        self.content:SetScale(scale)
        self.hud:SetSize(self.content:GetWidth() * scale, self.content:GetHeight() * scale)
        self.hud:UpdateGUI2PixelLayout()
    end
    local fontChanged = self.queueFont ~= font
    local countFontChanged = self.queueCountFont ~= config.countFont
    local textChanged = fontChanged or self.queueFontSize ~= size
    local countChanged = countFontChanged or self.queueCountSize ~= countSize
    if not textChanged and not countChanged then return changed end
    self.queueFont, self.queueFontSize, self.queueCountSize = font, size, countSize
    self.queueCountFont = config.countFont
    if fontChanged then
        self.queueFontPath = ResolveFont(font, GUI:GetFont("font.family.body"))
    end
    if countFontChanged then
        self.queueCountPath = ResolveFont(config.countFont, DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT or GUI:GetFont("font.family.body"))
    end
    local path, countPath = self.queueFontPath, self.queueCountPath
    for _, row in ipairs(self.rowPool) do
        if textChanged then
            row.name:SetFont(path, size, "OUTLINE")
            row.name.lootFontSize, row.name.lootFontChanged = size, true
            row.name:SetTextScale(1)
            row.name:SetHeight(size + 2)
            row.meta:SetFont(path, size - 2, "OUTLINE"); row.meta:SetHeight(size)
            row.timerText:SetFont(path, size - 2, "OUTLINE")
            row.timerText:SetWidth(math.ceil(TIMER_TEXT_WIDTH * (size - 2) / 12))
            row.item:SetHeight(size * 2 + 2)
            row.quantity:SetFont(path, size - 2, "OUTLINE")
            row.voted:SetFont(path, size - 2, "OUTLINE")
            row.binding:SetFont(path, math.max(8, size - 4), "OUTLINE")
        end
        if countChanged then
            for _, button in ipairs(row.buttons) do button.count:SetFont(countPath, countSize, "OUTLINE") end
        end
    end
    if textChanged then
        self.previewLabel:SetFont(path, size - 1, "OUTLINE")
        self.more:SetFont(path, size - 1, "OUTLINE")
        self.settlingText:SetFont(path, size - 1, "OUTLINE")
    end
    return true
end
function V:Paint(row, r, result)
    if row.record and row.record ~= r then
        if self.hoverAnchor == row then self:CloseHover() end
        CloseItemTooltip(row)
    end
    row.record = r
    local d, details = r.data, r.details or {}
    row.icon:SetIcon(d.texture or details.texture or 134400)
    local name = d.name or details.name or L["item.loading"]
    if result then Text(row.name, name)
    else FitQueueName(row.name, name, row.metaMaxWidth) end
    local quality = d.quality or details.quality or 1
    local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    if color then
        row.name:SetTextColor(color.r, color.g, color.b)
        if row.iconQuality ~= quality then
            row.iconQuality = quality
            row.icon:SetIconBorderColor(color)
            row.binding:SetTextColor(color.r, color.g, color.b)
        end
    end
    local c
    if row.voted then
        if not M.Terminal(r) then c = M.Count(r) end
        if c then
            Text(row.voted, c.voted .. "/" .. c.total)
            row.voted:SetTextColor(GUI:GetColor(c.voted < c.total and "color.state.success" or "color.text.rewardHeading"))
        end
        row.voted:SetShown(c ~= nil)
    end
    Text(row.quantity, (d.quantity or 1) > 1 and ("×" .. d.quantity) or "")
    local meta = (details.type or "") .. (details.slot and details.slot ~= "" and " · " .. details.slot or "")
    Text(row.meta, meta)
    local bindOnEquip = details.bindType == 2
    Text(row.binding, bindOnEquip and L["binding.equip"] or "")
    if row.binding:IsShown() ~= bindOnEquip then
        row.binding:SetShown(bindOnEquip)
        row.quantity:ClearAllPoints()
        if bindOnEquip and not result then
            row.quantity:SetPoint("TOPRIGHT", row.binding, "BOTTOMRIGHT", 0, -1)
        else
            row.quantity:SetPoint("TOPRIGHT", 0, bindOnEquip and -7 or 2)
        end
    end
    FitMetadata(row, result and 0 or row.timerText:GetWidth() + 5)
    if details.equip == "usable" then row.meta:SetTextColor(0.12, 1, 0.18)
    elseif details.equip == "unusable" then row.meta:SetTextColor(1, 0.2, 0.2)
    else row.meta:SetTextColor(GUI:GetColor("color.text.secondary")) end
    if result then
        local score, name, player = Result(r, true)
        Text(row.score, score); Text(row.leader, name); ColorPlayer(row.leader, player)
        local resultColor = player and (M.Terminal(r) and "color.text.rewardHeading" or "color.state.success") or "color.text.secondary"
        local _, choiceColor = V.ChoicePresentation(player and player.state)
        row.score:SetTextColor(GUI:GetColor(choiceColor or resultColor))
        ResultLayout(row)
    else
        if row.itemLink ~= d.link then
            row.itemLink = d.link
            ClearPress(row.icon); ClearPress(row.item)
        end
        for index, choice in ipairs({ "need", d.canTransmog and "transmog" or "greed", "pass" }) do
            local button = row.buttons[index]
            if button.choice ~= choice then
                ClearPress(button)
                button.choice = choice; VoteAtlas(button, choice)
            end
            local allowed = API.Allowed(d, choice)
            if not allowed then ClearPress(button) end
            button:SetAlpha(allowed and 1 or 0.35)
            if c then
                Text(button.count, tostring(c[choice]))
                button.count:SetTextColor(GUI:GetColor(choiceColors[choice] or "color.text.rewardHeading"))
            end
            button.count:SetShown(c ~= nil)
        end
        row.track:SetMinMaxValues(0, r.duration)
    end
    row:Show()
end
function V:ResetCompletion()
    local model = self.controller.model
    self.batchModel, self.batchGeneration, self.batchSerial = model, model.generation, model.serial
    self.completeUntil, self.completedResults = nil, nil
    for record in pairs(self.batchRecords) do self.batchRecords[record] = nil end
    for record in pairs(self.batchResults) do self.batchResults[record] = nil end
end
function V:UpdateCompletion(model, records)
    if self.batchModel ~= model or self.batchGeneration ~= model.generation then self:ResetCompletion() end

    local batch, results = self.batchRecords, self.batchResults
    for _, record in ipairs(records) do
        local terminal = M.Terminal(record)
        if not record.restored and not record.hydrated or record.active and record.rollID then
            -- 首次收到的实时历史可能已结算，且尚未关联到原生 Roll ID。
            if not terminal or (record.serial or 0) > self.batchSerial then batch[record] = true end
        end
    end
    self.batchSerial = model.serial

    local inFlight = false
    for record in pairs(batch) do
        local result = record.bound or (not record.active and record.rosterHistory) or record
        if M.Terminal(result) then
            batch[record] = nil
            results[result] = true
        else
            inFlight = true
        end
    end
    local ended = next(results)
    if inFlight or ended then
        self.completeUntil, self.completedResults = nil, nil
    end
    if not inFlight and ended then
        local completed, hasResult = {}, false
        for index = #records, 1, -1 do
            local record = records[index]
            if results[record] then
                completed[#completed + 1] = record
                hasResult = hasResult or record.status == "complete"
            end
        end
        if hasResult then
            self.completeUntil, self.completedResults = GetTime() + COMPLETION_SECONDS, completed
        end
        for record in pairs(results) do results[record] = nil end
    end
end
function V:CompletionSeconds(now)
    return self.completeUntil and math.min(COMPLETION_SECONDS, math.max(0, math.ceil(self.completeUntil - now - 0.000001))) or 0
end
function V:CompletionDelay(now)
    if self.completeUntil then return math.max(0.01, self.completeUntil - now - self:CompletionSeconds(now) + 1) end
end
function V:PaintFooterLabel(count, seconds)
    local label = count > 0 and L["queue.settling"]:format(count) or seconds > 0 and L["queue.complete"]:format(seconds) or ""
    if self.settlingText:GetText() ~= label then
        Text(self.settlingText, label)
        self.settling:SetWidth(NaturalWidth(self.settlingText) + 6)
    end
    self.settlingText:SetTextColor(GUI:GetColor(count > 0 and "color.state.warning" or "color.text.primary"))
    self.settling:SetShown(label ~= "")
end
function V:TickCompletion(now)
    if not self.completeUntil then return end
    local seconds = self:CompletionSeconds(now)
    if self.completedLabelSeconds ~= seconds then
        self.completedLabelSeconds = seconds
        self:PaintFooterLabel(0, seconds)
    end
    if seconds > 0 then return self:CompletionDelay(now) end

    self.completeUntil, self.completedResults = nil, nil
    if self.hoverKind == "summary" then self:CloseHover() end
    self.footer:Hide()
    self:SetFooterInput(false)
    if self.exitingCount == 0 then self.hud:Hide() end
end
function V:RenderQueue(model, records, preview, showPending)
    local controller, config = self.controller, self.controller.config
    local wasShown = self.hud:IsShown()
    local pending, tracked = showPending and M.Pending(model) or {}, {}
    for _, r in ipairs(records) do
        local awaitingChoice = r.rosterRoll and r.rosterRoll.active and r.selfState == 4
        if not r.active and not awaitingChoice and not r.restored and not r.hydrated and not M.Terminal(r) then
            tracked[#tracked + 1] = r
        end
    end
    self.tracked = tracked
    local capacity = math.max(3, math.min(MAX_VISIBLE, config.visibleItems or 6))
    if self.hoverKind == "summary" and self.capacity ~= capacity then self.offset = 0 end
    local geometryChanged = self.capacity and (self.appearanceChanged or self.capacity ~= capacity
        or self.growth ~= config.growth or self.layoutWidth ~= config.width)
    local leavingPreview = self.displayPreview and not preview
    if geometryChanged or leavingPreview then self:StopMotion(false) end
    self.suppressMotion = self.editing or geometryChanged or leavingPreview
    self.capacity, self.growth, self.layoutWidth, self.displayPreview = capacity, config.growth, config.width, preview
    local settingsPreview = preview and controller.settingsPreview == true
    self.previewLabel:SetShown(settingsPreview and not self.editing)
    local layerMode = self.editing and "edit" or settingsPreview and "preview" or "normal"
    if self.layerMode ~= layerMode then
        self.layerMode = layerMode
        if layerMode == "preview" then BringToFront(self.hud)
        else self.hud:SetFrameStrata(self.editing and "MEDIUM" or "DIALOG"); self.hud:SetFrameLevel(20) end
    end
    local up = config.growth == "up"
    local height = capacity * ROW_STRIDE - ROW_GAP + FOOTER_HEIGHT
    self.content:SetSize(config.width, height)
    self.hud:SetSize(config.width * self.queueScale, height * self.queueScale)
    for record in pairs(self.desired) do self.desired[record] = nil end
    local count, previousCount = math.min(#pending, capacity), #self.rows
    for index = 1, count do self.desired[pending[index]] = true end
    for _, row in ipairs(self.rowPool) do
        if row.phase == "active" and not self.desired[row.record] then self:ReleaseRow(row) end
    end
    local itemWidth = config.width - QUEUE_ITEM_INSET
    for index = 1, count do
        local row, fresh = self:AcquireRow(pending[index])
        local y = (up and 1 or -1) * (index - 1) * ROW_STRIDE
        if fresh then self:SetRowPose(row, self.suppressMotion and 0 or 8, y, self.suppressMotion and 1 or 0) end
        row:SetWidth(config.width)
        row.item:SetWidth(itemWidth); row.metaMaxWidth = itemWidth
        self:Paint(row, pending[index])
        self:MoveRow(row, 0, y, 1, fresh and 0.14 or 0.16)
        self.rows[index] = row
    end
    for index = count + 1, previousCount do self.rows[index] = nil end
    local contentHeight = math.max(0, count * ROW_STRIDE - ROW_GAP)
    local seconds = #pending == 0 and #tracked == 0 and self:CompletionSeconds(GetTime()) or 0
    local hasFooter = #pending > capacity or #tracked > 0 or seconds > 0
    self.footer:SetWidth(config.width)
    local footerY = (up and 1 or -1) * contentHeight
    if self.footer.poseY == nil then self:SetRowPose(self.footer, 0, footerY, 1) end
    self:MoveRow(self.footer, 0, footerY, 1, hasFooter and wasShown and 0.16 or 0)
    Text(self.more, #pending > capacity and L["queue.more"]:format(#pending - capacity) or "")
    self:PaintFooterLabel(#tracked, seconds)
    if seconds > 0 and self.completedLabelSeconds == 0 and self.hoverKind == "summary" then self.offset = 0 end
    self.completedLabelSeconds = seconds
    self.more:SetTextColor(GUI:GetColor("color.text.secondary"))
    self.footer:SetShown(hasFooter)
    if self.hoverKind == "summary" and not self.settling:IsShown() then self:CloseHover() end
    self.hud:SetShown(#pending > 0 or hasFooter or self.exitingCount > 0)
    self:Tick()
    self:RefreshQueueInput()
end
function V:Render()
    local controller = self.controller
    self.appearanceChanged = self:ApplyQueueAppearance()
    local records
    if controller.active then
        records = M.List(controller.model)
        self:UpdateCompletion(controller.model, records)
    end
    local model, preview = controller:GetDisplayModel()
    if model ~= controller.model or not records then records = M.List(model) end
    self:SetEditing(controller.editPreview)
    if preview or self.editing or controller.active and not controller.gamepad then
        local showPending = preview or self.editing or controller.nativeTakeover
        if not showPending and (#self.rows > 0 or self.exitingCount > 0) then
            if self.hoverKind ~= "summary" and not self.hoverHistory then self:CloseHover() end
            self:StopMotion(true)
        end
        self:RenderQueue(model, records, preview, showPending)
    else
        if not self.hoverHistory then self:CloseHover() end
        self.hud:Hide()
        self.footer:Hide()
        self.tracked, self.displayPreview = nil, nil
        if #self.rows > 0 or self.exitingCount > 0 or self.footer.motion then self:StopMotion(true) end
        self:SetFooterInput(false)
    end
    self.writes = self.writes + 1
    if self.history and self.history:IsShown() and API.IsConfirming() then self:YieldToConfirmation() end
    if self.popup:IsShown() then self:RenderPopup() end
    if self.history and self.history:IsShown() then self:RenderHistory() end
end
function V:Hover(record, kind, anchor)
    if self.editing then return end
    if record ~= self.hoverRecord or kind ~= self.hoverKind then self.offset = 0 end
    if kind ~= "summary" and not record then self:CloseHover(); return end
    self.cancelClose()
    self.hoverRecord, self.hoverKind = record, kind
    self.hoverHistory = self.historyList and anchor:GetParent() == self.historyList or false
    self.hoverAnchor = (kind == "summary" or self.hoverHistory) and anchor or anchor:GetParent()
    self:RenderPopup()
    if not self.hoverKind then return end
    self:PositionPopup(); self.popup:Show()
end
function V:PositionPopup()
    local anchor = self.hoverHistory and self.history or self.hud
    self.popup:ClearAllPoints()
    local right = anchor:GetRight() * anchor:GetEffectiveScale()
    local top = self.hoverAnchor and self.hoverAnchor:GetTop()
    local offset = top and anchor:GetTop() and (top * self.hoverAnchor:GetEffectiveScale() - anchor:GetTop() * anchor:GetEffectiveScale()) / self.popup:GetEffectiveScale() or 0
    if right + (self.popup:GetWidth() + 8) * self.popup:GetEffectiveScale() > GetScreenWidth() * UIParent:GetEffectiveScale() then self.popup:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, offset)
    else self.popup:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, offset) end
end
function V:Wheel(delta)
    if not self.hoverKind or delta == 0 then return end
    if self.hoverKind == "summary" then
        if delta < 0 and not self.summaryCanScrollDown or delta > 0 and self.offset == 0 then return end
        self.offset = self.offset + (delta < 0 and 1 or -1)
    else
        self.offset = math.max(0, self.offset - delta * 3)
    end
    self:RenderPopup()
end
local function RosterName(player)
    return (player.isWinner and "★ " or "") .. (player.playerName or "—") .. (player.isSelf and L["roster.you"] or "")
end
local function RosterChoice(player, closed)
    return closed and player.state == 4 and L["choice.unconfirmed"] or Label(player.state)
end
function V:LayoutRoster(drop, kind, list, closed)
    if self.rosterWidth and self.rosterLayoutSource == drop and self.rosterLayoutKind == kind
        and self.rosterLayoutClosed == closed then return self.rosterWidth end
    self.rosterLayoutSource, self.rosterLayoutKind, self.rosterLayoutClosed = drop, kind, closed
    local nameWidth, pickWidth = 0, 0
    for _, player in ipairs(list) do
        Text(self.rosterNameMeasure, RosterName(player))
        Text(self.rosterPickMeasure, RosterChoice(player, closed))
        nameWidth = math.max(nameWidth, NaturalWidth(self.rosterNameMeasure))
        pickWidth = math.max(pickWidth, NaturalWidth(self.rosterPickMeasure))
    end
    local columns = 8 + ROSTER_ICON_SIZE + ROSTER_ICON_GAP + pickWidth + 8 + ROSTER_SCORE_WIDTH
    local width = math.max(POPUP_MIN_WIDTH, math.min(POPUP_MAX_WIDTH, nameWidth + columns + 32))
    self.rosterWidth = width
    local content = width - 20
    for _, region in ipairs(self.rosterText) do region:SetWidth(content) end
    for _, row in ipairs(self.people) do
        row:SetWidth(content)
        row.name:SetWidth(content - columns)
        row.pick:SetWidth(pickWidth)
    end
    return width
end
function V:RenderSummary()
    local tracked, settled, unavailable = self.tracked, nil, 0
    local pendingCount = tracked and #tracked or 0
    if self.completedResults then
        settled = {}
        for _, record in ipairs(self.completedResults) do
            if record.status == "complete" then settled[#settled + 1] = record
            else unavailable = unavailable + 1 end
        end
    elseif pendingCount > 0 and (self.displayPreview or next(self.batchResults)) then
        settled = {}
        local records = M.List(self.controller:GetDisplayModel())
        for index = #records, 1, -1 do
            local record = records[index]
            if record.status == "complete" and (self.displayPreview or self.batchResults[record]) then
                settled[#settled + 1] = record
            end
        end
    end
    local settledCount = settled and #settled or 0
    local total = pendingCount + settledCount
    if total == 0 then self:CloseHover(); return end
    if self.offset >= total then self.offset = 0 end

    local grouped = pendingCount > 0 and settledCount > 0
    if grouped then
        self.popupSummarySettling:SetTextColor(GUI:GetColor("color.state.warning"))
        self.popupSummarySettled:SetTextColor(GUI:GetColor("color.state.success"))
    end
    local note, noteHeight = nil, 0
    if unavailable > 0 then
        note = self.popupSummaryUnavailable
        if not note then
            note = Font(self.popup, 12)
            note:SetJustifyH("LEFT")
            self.popupSummaryUnavailable = note
        end
        Text(note, L["queue.resultsUnavailable"]:format(unavailable))
        note:SetTextColor(GUI:GetColor("color.state.warning"))
        noteHeight = SUMMARY_HINT_LINE_HEIGHT
    end
    local baseFooterHeight = SUMMARY_FOOTER_HEIGHT + noteHeight
    local maxHeight = UIParent:GetHeight() * UIParent:GetEffectiveScale() / self.popup:GetEffectiveScale() - 24
    local top, itemWidth, resultWidth, count = 8, 0, 0, 0
    for i = 1, math.min(self.capacity, total - self.offset) do
        local row = self.summaryRows[i]
        if not row then
            row = self.createItem(self.popup, true, SUMMARY_MAX_WIDTH - 16)
            row:EnableMouse(false)
            self.summaryRows[i] = row
        end
        local index = self.offset + i
        local isPending = index <= pendingCount
        local heading = grouped and (i == 1 or index == pendingCount + 1)
            and (isPending and self.popupSummarySettling or self.popupSummarySettled)
        local rowTop = top + (heading and SUMMARY_SECTION_HEIGHT or 0)
        self:Paint(row, isPending and tracked[index] or settled[index - pendingCount], true)
        local nextTop = rowTop + row:GetHeight() + 2
        local hasMore = self.offset > 0 or index < total
        local footerHeight = baseFooterHeight + (hasMore and SUMMARY_HINT_LINE_HEIGHT or 0)
        if i > 1 and nextTop + footerHeight > maxHeight then
            row:Hide(); row.record = nil
            break
        end
        if heading then
            heading:ClearAllPoints(); heading:SetPoint("TOPLEFT", 10, -top); heading:Show()
        end
        itemWidth = math.max(itemWidth, NaturalWidth(row.name), NaturalWidth(row.meta))
        resultWidth = math.max(resultWidth, NaturalWidth(row.score), NaturalWidth(row.leader))
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 8, -rowTop)
        top, count = nextTop, i
    end

    local last = self.offset + count
    self.summaryCanScrollDown = last < total
    local showRange = self.offset > 0 or self.summaryCanScrollDown
    if showRange then Text(self.popupSummaryRange, L["roster.scroll"]:format(self.offset + 1, last, total)) end
    local hintWidth = math.max(NaturalWidth(self.popupSummaryHint), showRange and NaturalWidth(self.popupSummaryRange) or 0)
    if note then hintWidth = math.max(hintWidth, NaturalWidth(note)) end
    resultWidth = math.min(resultWidth, SUMMARY_RESULT_WIDTH)
    local nonTextWidth = 16 + RESULT_ITEM_X + SUMMARY_GAP + 8
    local width = math.min(SUMMARY_MAX_WIDTH, math.max(POPUP_MIN_WIDTH, hintWidth + 20,
        nonTextWidth + itemWidth + resultWidth))
    local nameWidth = width - nonTextWidth - resultWidth
    for i = 1, count do
        local row = self.summaryRows[i]
        row:SetWidth(width - 16)
        row.metaMaxWidth = nameWidth
        row.item:SetWidth(nameWidth); row.name:SetWidth(nameWidth)
        row.score:SetWidth(resultWidth); row.leader:SetWidth(resultWidth)
        FitMetadata(row, 0)
    end
    self.popupSummaryHint:SetWidth(width - 20); self.popupSummaryHint:Show()
    self.popupSummaryRange:SetWidth(width - 20); self.popupSummaryRange:SetShown(showRange)
    if note then
        note:ClearAllPoints()
        note:SetPoint("BOTTOMLEFT", showRange and self.popupSummaryRange or self.popupSummaryHint, "TOPLEFT", 0, 2)
        note:SetWidth(width - 20); note:Show()
    end
    local height = top + baseFooterHeight + (showRange and SUMMARY_HINT_LINE_HEIGHT or 0)
    local resized = width ~= self.popup:GetWidth() or height ~= self.popup:GetHeight()
    self.popup:SetSize(width, height)
    if resized and self.popup:IsShown() then self:PositionPopup() end
end
function V:RenderPopup()
    local kind, record = self.hoverKind, self.hoverRecord
    if kind == "middle" then
        kind = record and record.data.canTransmog and "transmog" or "greed"
        if kind ~= self.hoverAction then self.offset = 0 end
    end
    self.hoverAction = kind
    local red, green, blue = GUI:GetColor("color.surface.panel")
    self.popupBackground:SetColorTexture(red, green, blue, 1)
    for _, row in ipairs(self.people) do row:Hide() end
    for _, row in ipairs(self.summaryRows) do row:Hide() end
    self.popupSummaryHint:Hide()
    self.popupSummaryRange:Hide()
    self.popupSummarySettling:Hide()
    self.popupSummarySettled:Hide()
    if self.popupSummaryUnavailable then self.popupSummaryUnavailable:Hide() end
    self.popupAction:Hide()
    if kind == "summary" then
        self.popupTitle:Hide(); self.popupInfo:Hide()
        self:RenderSummary()
        return
    end
    if not record then self:CloseHover(); return end
    local action = kind ~= "all"
    self.popupTitle:Show(); self.popupInfo:Show()
    Text(self.popupTitle, (record.data.name or (record.details or {}).name or L["item.loading"]) .. ((record.data.quantity or 1) > 1 and (" ×" .. record.data.quantity) or ""))
    local color = ITEM_QUALITY_COLORS[record.data.quality or (record.details or {}).quality or 1]
    if color then self.popupTitle:SetTextColor(color.r, color.g, color.b) end
    local list, drop = {}, M.DisplayDrop(record)
    for _, p in ipairs(drop and drop.rollInfos or {}) do
        if kind == "all" or kind == "need" and (p.state == 0 or p.state == 1) or stateKeys[p.state] == kind then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) if a.state ~= b.state then return a.state < b.state end; if a.roll ~= b.roll then return (a.roll or -1) > (b.roll or -1) end; return (a.playerName or "") < (b.playerName or "") end)
    local closed = M.Terminal(record) or record.choiceEndedAt ~= nil
    local width = self:LayoutRoster(drop, kind, list, closed)
    self.offset = math.min(self.offset, math.max(0, #list - 8))
    local reason = action and not API.Allowed(record.data, kind) and (API.Reason(record.data, kind) or L["choice.unavailable"])
    local info = reason or (not drop and L[record.ambiguous and "status.ambiguous" or "status.sync"] or L["roster.count"]:format(#list))
    local top = 8
    if action then
        local label = L["choice." .. kind]
        self.popupAction:SetTextColor(GUI:GetColor(choiceColors[kind] or "color.text.rewardHeading"))
        top = FlowText(self.popupAction, drop and L["roster.actionCount"]:format(label, #list) or label, top)
        info = reason or (not drop and info or "")
    end
    top = FlowText(self.popupTitle, self.popupTitle:GetText(), top)
    if self.hoverHistory then
        local count = M.Count(record)
        if record.status == "unavailable" then
            info = L["status.unavailable"]
        elseif count then
            local transmog = record.data.canTransmog
            local key = closed and "history.choicesClosed" or "history.choices"
            info = L[key]:format(count.need, Label(transmog and 2 or 3), transmog and count.transmog or count.greed, count.pass, count.waiting)
        end
    end
    if #list > 8 then
        info = info .. (info ~= "" and "\n" or "") .. L["roster.scroll"]:format(self.offset + 1, math.min(self.offset + 8, #list), #list)
    end
    self.popupInfo:SetTextColor(GUI:GetColor(reason and "color.state.error" or "color.text.secondary"))
    top = FlowText(self.popupInfo, info, top, 4)
    for i = 1, 8 do
        local p, row = list[self.offset + i], self.people[i]
        if p then
            Text(row.name, RosterName(p))
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, -top)
            top = top + row:GetHeight()
            ColorPlayer(row.name, p); Text(row.pick, RosterChoice(p, closed)); Text(row.score, p.roll or "—")
            local choice, choiceColor = V.ChoicePresentation(p.state)
            row.pick:SetTextColor(GUI:GetColor(choiceColor or "color.text.secondary"))
            row.score:SetTextColor(GUI:GetColor(p.isWinner and (choiceColor or "color.text.rewardHeading") or p.roll and "color.text.primary" or "color.text.secondary"))
            choice = choice ~= "waiting" and choice ~= "disenchant" and choice
            row.icon:SetShown(not not choice)
            if choice then row.icon:SetAtlas("lootroll-toast-icon-" .. choice .. "-up") end
            row:Show()
        end
    end
    local resized = width ~= self.popup:GetWidth()
    self.popup:SetSize(width, top + 8)
    if resized and self.popup:IsShown() then self:PositionPopup() end
end
local HISTORY_CLASS_FILTER = {
    [2] = "equipment", [4] = "equipment",
    [9] = "recipe",
    [3] = "material", [5] = "material", [7] = "material",
}
local function HistoryFilterValue(record, key)
    local details = record.details or {}
    if key == "class" then return HISTORY_CLASS_FILTER[details.classID or record.data.classID] or "other" end
    return record.data.quality or details.quality
end
local function HistoryFilterOptions(key)
    local entries = { { value = "all", text = L["history.filter.all"], selectionText = L["history.filter." .. key] } }
    if key == "class" then
        entries[1].icon = "Interface\\Icons\\INV_Misc_Bag_08"
        for _, spec in ipairs({
            { "equipment", "INV_Sword_04" },
            { "recipe", "INV_Misc_Note_01" },
            { "material", "INV_Misc_Gem_01" },
            { "other", "INV_Misc_QuestionMark" },
        }) do
            entries[#entries + 1] = { value = spec[1], text = L["history.filter." .. spec[1]], icon = "Interface\\Icons\\" .. spec[2] }
        end
        for _, entry in ipairs(entries) do
            entry.texCoord, entry.iconSize = HISTORY_FILTER_ICON_CROP, 20
        end
        return entries
    end
    for quality = 0, 5 do
        local label = _G["ITEM_QUALITY" .. quality .. "_DESC"] or L["history.filter.qualityID"]:format(quality)
        local color = ITEM_QUALITY_COLORS[quality]
        if color then
            label = ("|cff%02x%02x%02x%s|r"):format(math.floor(color.r * 255 + 0.5),
                math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), label)
        end
        entries[#entries + 1] = { value = quality, text = label }
    end
    return entries
end
function V:TurnHistoryPage(direction)
    local page = math.max(1, math.min(self.historyPages, self.page + direction))
    if page == self.page then return end
    self.page = page
    self:CloseHover()
    self:RenderHistory()
end
function V:ApplyHistoryRowFonts()
    local config = self.controller.config
    local path = ResolveFont(config.historyFont, GUI:GetFont("font.family.body"))
    local size = config.historyFontSize
    local detailSize, resultSize, bindingSize = size - 2, size - 1, math.max(8, size - 4)
    for _, row in ipairs(self.historyRows) do
        row.name:SetFont(path, size, "OUTLINE")
        row.meta:SetFont(path, detailSize, "OUTLINE")
        row.binding:SetFont(path, bindingSize, "OUTLINE")
        row.quantity:SetFont(path, detailSize, "OUTLINE")
        row.score:SetFont(path, resultSize, "")
        row.leader:SetFont(path, resultSize, "")
        row.stamp:SetFont(path, detailSize, "")
        row.source:SetFont(path, detailSize, "")
    end
end
function V:OpenHistory()
    if API.IsConfirming() then self:YieldToConfirmation(); return false end
    if not self.history then
        local history = GUI:CreateFrame(UIParent, { name = "YUILootRollHistory", template = "BackdropTemplate", width = HISTORY_WIDTH, height = HISTORY_HEIGHT,
            mouse = true, toplevel = true, movable = true, clamped = true })
        history:SetPoint("CENTER")
        local function PageOnWheel(_, delta)
            if delta ~= 0 then self:TurnHistoryPage(delta > 0 and -1 or 1) end
        end
        local function EnablePagingWheel(frame)
            frame:EnableMouseWheel(true)
            frame:SetScript("OnMouseWheel", PageOnWheel)
        end
        EnablePagingWheel(history)
        if GUI.EnableEscapeClose then GUI:EnableEscapeClose(history)
        elseif UISpecialFrames then table.insert(UISpecialFrames, "YUILootRollHistory") end
        self.history = history
        self.historyTitle = Font(history, 16); self.historyTitle:SetPoint("TOP", 0, -10)
        local close = GUI:CreateCloseButton(history, function() history:Hide() end)
        close:SetPoint("TOPRIGHT", -9, -8)
        local drag = GUI:CreateFrame(history, { width = HISTORY_WIDTH - 48, height = 28, mouse = true })
        drag:SetPoint("TOPLEFT", 4, -2); drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() history:StartMoving() end)
        drag:SetScript("OnDragStop", function() history:StopMovingOrSizing() end)
        history:SetScript("OnMouseDown", function() history:Raise() end)
        history:SetScript("OnHide", function()
            self:CloseHover()
            history:StopMovingOrSizing()
            for _, row in ipairs(self.historyRows) do CloseItemTooltip(row) end
            local anchor = GUI.DropdownFrame and GUI.DropdownFrame.anchor
            if anchor and (anchor == self.historyFilters.class or anchor == self.historyFilters.quality) then GUI:CloseDropdown(false) end
        end)
        local function Filter(key, width, x)
            local control = GUI.Form:CreateDropdown(history, { width = width, height = 25, value = "all",
                options = HistoryFilterOptions(key),
                set = function() self.page = 1; self:CloseHover(); self:RenderHistory() end })
            control:SetPoint("TOPLEFT", x, -36)
            return control
        end
        self.historyFilters = { class = Filter("class", 178, 8), quality = Filter("quality", 138, 194) }
        local clear = GUI.Form:CreateButton(history, { width = 142, height = 25, text = L["history.clear"],
            onClick = function() self.controller:ConfirmClearHistory() end })
        clear:SetPoint("TOPRIGHT", -8, -36)
        self.historyEmpty = Font(history, 13, nil, true); self.historyEmpty:SetPoint("CENTER", 0, 0)
        self.historyEmpty:SetWidth(HISTORY_WIDTH - 36); self.historyEmpty:SetHeight(54)
        self.historyList = Surface(history, HISTORY_WIDTH - 16, 2)
        self.historyList:SetPoint("TOPLEFT", 8, -HISTORY_TABLE_TOP)
        EnablePagingWheel(self.historyList)
        for i = 1, HISTORY_PAGE_SIZE do
            local stripe = i % 2 == 1 and "color.surface.panel" or "color.surface.raised"
            local row = self.createItem(self.historyList, true, HISTORY_WIDTH - 18, stripe)
            row.stamp, row.source = Font(row, 12, true), Font(row, 12, true)
            for _, region in ipairs({ row.stamp, row.source }) do
                region:SetWidth(HISTORY_DATE_WIDTH); region:SetJustifyH("RIGHT")
                region:SetTextColor(GUI:GetColor("color.text.secondary"))
            end
            row.icon:EnableMouse(true)
            row.icon:SetScript("OnEnter", function(icon)
                if self.editing or not row.record then return end
                self:CloseHover()
                API.ShowItemTooltip(icon, nil, row.record.data.link)
            end)
            row.icon:SetScript("OnLeave", function() CloseItemTooltip(row) end)
            EnablePagingWheel(row)
            EnablePagingWheel(row.icon)
            row:SetScript("OnEnter", function() self.cancelClose(); self:Hover(row.record, "all", row) end)
            row:SetScript("OnLeave", self.leave)
            self.historyRows[i] = row
        end
        self.historyButtons = {}
        self.historyPage = Font(history, 14)
        self.historyPage:SetSize(64, 26); self.historyPage:SetJustifyH("CENTER")
        self.historyPage:SetPoint("BOTTOM", 0, 7)
        for i, direction in ipairs({ -1, 1 }) do
            local button = GUI.Form:CreateButton(history, { width = 88, height = 26, text = L[direction < 0 and "history.previous" or "history.next"],
                onClick = function() self:TurnHistoryPage(direction) end })
            if direction < 0 then button:SetPoint("RIGHT", self.historyPage, "LEFT", -10, 0)
            else button:SetPoint("LEFT", self.historyPage, "RIGHT", 10, 0) end
            self.historyButtons[i] = button
        end
        Appearance:Register(history, { heading = self.historyTitle, role = "loot-history", shellHeaderHeight = 32,
            onRefresh = function(_, context)
                Appearance:ApplyFont(self.historyPage, context); Appearance:ApplyFont(self.historyEmpty, context)
                Appearance:ApplyFont(clear.text, context)
                for _, button in ipairs(self.historyButtons) do Appearance:ApplyFont(button.text, context) end
                self:ApplyHistoryRowFonts()
                if history:IsShown() then self:RenderHistory() end
            end })
    end
    for _, filter in pairs(self.historyFilters) do filter:SetValue("all", true) end
    self.page = 1; self:CloseHover(); Appearance:Refresh(self.history)
    if not self.history:IsShown() then self:RenderHistory() end
    self.history:Show(); BringToFront(self.history)
    return true
end
function V:RenderHistory()
    local model, preview = self.controller:GetDisplayModel()
    local list = M.List(model)
    local class, quality = self.historyFilters.class:GetValue(), self.historyFilters.quality:GetValue()
    local filtering = class ~= "all" or quality ~= "all"
    if filtering then
        local kept = 0
        local filtered = {}
        for _, record in ipairs(list) do
            if (class == "all" or HistoryFilterValue(record, "class") == class)
                and (quality == "all" or HistoryFilterValue(record, "quality") == quality) then
                kept = kept + 1
                filtered[kept] = record
            end
        end
        list = filtered
    end
    local pages = math.max(1, math.ceil(#list / HISTORY_PAGE_SIZE))
    self.historyPages = pages
    self.page = math.min(self.page, pages)
    Text(self.historyTitle, L[preview and "history.previewTitle" or "history.title"])
    if #list == 0 then Text(self.historyEmpty, L[filtering and "history.noMatches" or "history.empty"]) end
    self.historyEmpty:SetShown(#list == 0)
    Text(self.historyPage, L["history.page"]:format(self.page, pages))
    self.historyButtons[1]:SetDisabled(self.page == 1)
    self.historyButtons[2]:SetDisabled(self.page == pages)
    local top = 1
    local today = date("%Y-%m-%d", GetServerTime())
    for i, row in ipairs(self.historyRows) do
        local record = list[#list - (self.page - 1) * HISTORY_PAGE_SIZE - i + 1]
        if record then
            Text(row.stamp, date("%m-%d %H:%M:%S", record.firstSeenAt))
            local recordedToday = date("%Y-%m-%d", record.firstSeenAt) == today
            row.stamp:SetTextColor(GUI:GetColor(recordedToday and "color.text.primary" or "color.text.muted"))
            Text(row.source, API.SourceName(record.source) or L["history.noSource"])
            self:Paint(row, record, true)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 1, -top)
            top = top + row:GetHeight()
        else
            if row.record and self.hoverRecord == row.record and self.hoverHistory then self:CloseHover() end
            if row.record then CloseItemTooltip(row) end
            row.record = nil; row:Hide()
        end
    end
    self.historyList:SetHeight(top + 1)
    self.historyList:SetShown(#list > 0)
    local height = math.max(HISTORY_HEIGHT, HISTORY_TABLE_TOP + 40 + self.historyList:GetHeight())
    self.history:SetHeight(height)
    self.history:SetScale(math.min(1, (UIParent:GetHeight() - 24) / height, (UIParent:GetWidth() - 24) / HISTORY_WIDTH))
    if self.hoverHistory and self.popup:IsShown() then self:PositionPopup() end
end
local function ClaimPulse(view, record, now)
    view.pulsed[record] = true
    local simultaneous = false
    for deadline in pairs(view.pulseDeadlines) do
        if now >= deadline + PULSE_DEADLINE_WINDOW then
            view.pulseDeadlines[deadline] = nil
        elseif math.abs(record.deadline - deadline) <= PULSE_DEADLINE_WINDOW then
            simultaneous = true
        end
    end
    if simultaneous then return false end
    view.pulseDeadlines[record.deadline] = true
    return true
end
function V:Tick()
    if #self.rows == 0 then return end
    local now = GetTime()
    local canPulse = not self.editing and not self.displayPreview
    local pulse, earliest, shortest = 0, nil, math.huge
    if self.pulseRow then
        local progress = (now - self.pulseStarted) / self.pulseDuration
        if progress < 1 then
            local envelope = 4 * progress * (1 - progress)
            pulse = PULSE_TINT * envelope * envelope
        else
            self.pulseRow = nil
        end
    end
    for _, row in ipairs(self.rows) do
        local r = row.record
        if r and r.active then
            local value = Remaining(r, now)
            row.track:SetValue(value)
            Text(row.timerText, TimerText(value))
            if r.selfState == 4 and value < URGENCY_SECONDS then
                local progress = math.min(1, (URGENCY_SECONDS - value) / (URGENCY_SECONDS - PULSE_SECONDS))
                local tint = URGENCY_TINT * progress * progress * (3 - 2 * progress)
                SetUrgency(row, tint + (row == self.pulseRow and pulse or 0))
                -- 先比较真实剩余时间，已提示的最早条目仍占这个位置，避免同批逐行补闪。
                if canPulse and not r.preview and value > 0 and value <= PULSE_SECONDS and value < shortest then
                    earliest, shortest = row, value
                end
            else
                SetUrgency(row, 0)
            end
        end
    end
    if earliest and not self.pulseRow and not self.pulsed[earliest.record] and ClaimPulse(self, earliest.record, now) then
        self.pulseRow, self.pulseStarted, self.pulseDuration = earliest, now, math.min(shortest, PULSE_DURATION)
    end
end
function V:CloseHover()
    if self.hoverKind == "summary" then
        self.summaryCanScrollDown = nil
        for _, row in ipairs(self.summaryRows) do row.record = nil end
    end
    self.cancelClose(); self.popup:Hide()
    self.hoverRecord, self.hoverKind, self.hoverAction, self.hoverHistory, self.hoverAnchor = nil, nil, nil, nil, nil
    self.rosterLayoutSource, self.rosterWidth = nil, nil
end
function V:YieldToConfirmation(record)
    self:CloseHover()
    local row = self.rowByRecord[record]
    if row then CloseItemTooltip(row) end
    -- The native StaticPopup is DIALOG; our foreground history can cover it.
    if self.history and self.history:IsShown() then self.history:Hide() end
end
function V:Hide()
    self:ResetCompletion()
    self:PaintFooterLabel(0, 0)
    self.footer:Hide()
    self:SetEditing(false)
    self:StopMotion(true)
    self:CloseHover(); self.hud:Hide(); if self.history then self.history:Hide() end
end
