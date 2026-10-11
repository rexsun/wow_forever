local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.questItems == true) then return end
local Items = { active = false, pending = false, states = {}, order = {}, pool = {}, passes = 0,
    fades = setmetatable({}, { __mode = "k" }) }
YAB.QuestItems = Items
local ID = "questItems"
local API = YUI.API.QuestItems
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE",
    "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
    "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN" }

local function Config()
    local db = YAB:GetDB()
    return db and db.specialBars and db.specialBars[ID], db
end

local function Enabled()
    local config, db = Config()
    return API and db and db.enabled == true and config and config.enabled == true
        and YAB.BarManager and YAB.BarManager.runtimeActive == true
end

local function InCombat() return YAB.Adapter:InCombat() end
local function Text(key) return YUI.Locale:Get("YActionBar")[key] end

function Items:GetPins()
    if self.testData then return self.testData.pins end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(YAB.PRODUCT_ID)
    local char = db and db.char
    if char then
        char.YActionBarQuestItems = char.YActionBarQuestItems or { pins = {} }
        self.pins = char.YActionBarQuestItems.pins
    end
    self.pins = self.pins or {}
    return self.pins
end

local function CancelTimer(key)
    if Items[key] then Items[key]:Cancel(); Items[key] = nil end
end

function Items:CloseMenu()
    if self.menu then self.menu:Hide() end
    if self.dismiss then self.dismiss:Hide() end
    self.menuItemID = nil
    self.menuTargets = nil
    if self.pending then self:Request() end
end

function Items:SetPinned(itemID, value, keepMenu)
    if itemID < 0 and not self.testData then return end
    self:GetPins()[itemID] = value == true and true or nil
    local state = self.states[itemID]
    if state then state.snoozed, state.snoozeSession = nil, nil end
    if keepMenu then self:UpdateMenu() else self:CloseMenu() end
    self:Request()
end

function Items:Snooze(itemID)
    if itemID < 0 and not self.testData then return end
    self:GetPins()[itemID] = nil
    local state = self.states[itemID]
    if state then
        state.snoozed = true
        state.snoozeSession = self.available and self.available[itemID] and self.available[itemID].inside == nil
    end
    self:CloseMenu()
    self:Request()
end

function Items:HasSnoozedItems()
    for _, state in pairs(self.states) do if state.snoozed then return true end end
    return false
end

function Items:SnoozeAll()
    local targets = self.menuTargets
    for _, itemID in ipairs(self.order) do self:Snooze(itemID) end
    for _, itemID in ipairs(targets or {}) do self:Snooze(itemID) end
    self:CloseMenu()
end

function Items:RestoreSnoozedItems()
    for _, state in pairs(self.states) do state.snoozed, state.snoozeSession = nil, nil end
    if self.recoveryButton and self.hovered == self.recoveryButton then
        self.hovered = nil
        if GameTooltip:IsOwned(self.recoveryButton) then GameTooltip:Hide() end
    end
    self:CloseMenu()
    self:Request()
end

function Items:IsMenuPinned()
    for _, id in ipairs(self.menuTargets or {}) do if not self:GetPins()[id] then return false end end
    return true
end

function Items:UpdateMenu()
    if not self.menuTargets then return end
    local pinned = self:IsMenuPinned()
    local tip = YUI.GUI2.Tooltip
    self.modeButton:SetText(tip:ColorText(Text(pinned and "quest_items.always" or "quest_items.auto"), pinned and "heading" or "action"))
    self.modeButton:SetSelected(pinned)
    local single = self.menuItemID ~= nil
    if single then self.snoozeButton:Show() else self.snoozeButton:Hide() end
    self.menu:SetSize(190, single and 182 or 152)
    self.snoozeAllButton:ClearAllPoints()
    self.snoozeAllButton:SetPoint("TOPLEFT", 8, single and -118 or -88)
    self.settingsButton:ClearAllPoints()
    self.settingsButton:SetPoint("TOPLEFT", 8, single and -148 or -118)
end

local function ToggleMenuMode()
    local pinned = not Items:IsMenuPinned()
    for _, id in ipairs(Items.menuTargets or {}) do Items:SetPinned(id, pinned, true) end
end

function Items:OpenMenu(itemID, button)
    if not self.active or (itemID and not self.states[itemID]) then return end
    local targets = {}
    if itemID then targets[1] = itemID else
        for _, id in ipairs(self.availableOrder or {}) do
            if self.states[id] and self.states[id].snoozed then targets[#targets + 1] = id end
        end
    end
    if #targets == 0 then return end
    local gui = YUI.GUI2
    if not self.menu then
        self.dismiss = gui:CreateButtonFrame(UIParent)
        self.dismiss:SetAllPoints(UIParent)
        self.dismiss:SetFrameStrata("DIALOG")
        self.dismiss:SetScript("OnClick", function() Items:CloseMenu() end)
        self.menu = gui:CreatePanel(self.dismiss, { width = 190, height = 152,
            surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        self.menu:SetFrameStrata("DIALOG")
        self.menu:SetFrameLevel(self.dismiss:GetFrameLevel() + 2)
        self.menu:SetClampedToScreen(true)
        self.menuHeading = gui:CreateText(self.menu, Text("quest_items.display_mode"), "font.size.lg", "color.tooltip.heading")
        self.menuHeading:SetPoint("TOPLEFT", 8, -8)
        self.modeButton = gui.Form:CreateButton(self.menu, { width = 174, height = 28, tone = "default",
            onClick = ToggleMenuMode })
        self.modeButton:SetPoint("TOPLEFT", 8, -36)
        local divider = gui:CreatePanel(self.menu, { width = 174, height = 1, border = false, surface = "color.border.subtle" })
        divider:SetPoint("TOPLEFT", 8, -76)
        self.snoozeButton = gui.Form:CreateButton(self.menu, { text = Text("quest_items.snooze"), width = 174, height = 26,
            onClick = function()
                if Items.menuItemID then Items:Snooze(Items.menuItemID) end
            end })
        self.snoozeButton:SetPoint("TOPLEFT", 8, -88)
        self.snoozeAllButton = gui.Form:CreateButton(self.menu, { text = Text("quest_items.snooze_all"), width = 174, height = 26,
            onClick = function() Items:SnoozeAll() end })
        self.settingsButton = gui.Form:CreateButton(self.menu, { text = Text("quest_items.settings"), width = 174, height = 26,
            onClick = function() Items:CloseMenu(); YAB.SettingsBridge:Open(ID, "display") end })
        self.settingsButton:SetPoint("TOPLEFT", 8, -118)
    end
    self.menuItemID, self.menuTargets = itemID, targets
    self:UpdateMenu()
    self.menu:ClearAllPoints()
    self.menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 4)
    self.dismiss:Show()
    self.menu:Show()
end

local function OpenEditor()
    Items:CloseMenu()
    local layout = YUI.Layout
    if layout and layout.OpenEditMode and layout:OpenEditMode("quest-items") then
        layout:SelectFrame("yactionbar." .. ID)
    end
end

local function AddHelp(recovery)
    local tip = YUI.GUI2.Tooltip
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(tip:FormatAction({ key = Text("quest_items.use_keys"),
        text = Text(recovery and "quest_items.restore" or "quest_items.use"), textTone = "heading" }))
    GameTooltip:AddLine(tip:FormatAction({ button = "LeftButton", modifiers = { "ALT" },
        text = Text("quest_items.menu"), textTone = "heading" }))
    GameTooltip:AddLine(tip:FormatAction({ button = "RightButton", modifiers = { "ALT" },
        text = Text("quest_items.edit"), textTone = "heading" }))
end

local function AddTooltipDivider()
    GameTooltip:AddLine(" ")
    local line = _G[GameTooltip:GetName() .. "TextLeft" .. GameTooltip:NumLines()]
    if not line then return end
    if not Items.tooltipDivider then
        Items.tooltipDivider = YUI.GUI2:CreateDivider(GameTooltip, { width = 1, height = 1 })
        local function HideDivider() Items.tooltipDivider:Hide() end
        GameTooltip:HookScript("OnHide", HideDivider)
        GameTooltip:HookScript("OnTooltipCleared", HideDivider)
    end
    local divider = Items.tooltipDivider
    divider:ClearAllPoints()
    divider:SetPoint("LEFT", line, "LEFT", 0, 0)
    divider:SetPoint("RIGHT", GameTooltip, "RIGHT", -12, 0)
    divider:Show()
end

local Leave
local function Enter(button)
    local entry = Items.bound[button]
    if not entry or not Items.active or Items.editing then return end
    Items.hovered = button
    local fade = Items.fades[button]
    if fade and fade.to == 0 and not InCombat() then Items:FadeButton(button, 1, 0.15) end
    local _, db = Config()
    if db.interaction.tooltipMode == "outOfCombat" and InCombat() then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.testItem then
        GameTooltip:SetText(entry.label)
        GameTooltip:AddLine(Text("quest_items.test_help"))
    else
        GameTooltip:SetHyperlink(entry.link)
    end
    AddTooltipDivider()
    GameTooltip:AddLine(YUI.GUI2.Tooltip:ColorText(entry.title, "heading"))
    AddHelp(false)
    GameTooltip:Show()
end

function Items:EnsureRecoveryButton(record)
    if not self.recoveryButton then
        local gui = YUI.GUI2
        self.recoveryButton = gui:CreateBlizzardIconButton(record.holder, { size = 28,
            atlas = "questlog-icon-expand", crop = false,
            onClick = function(button, mouseButton)
                if IsAltKeyDown() then
                    if mouseButton == "RightButton" then OpenEditor() else Items:OpenMenu(nil, button) end
                else Items:RestoreSnoozedItems() end
            end })
        local button = self.recoveryButton
        button.icon:ClearAllPoints()
        button.icon:SetSize(18, 18)
        button.icon:SetPoint("CENTER")
        button:SetScript("OnEnter", function(owner)
            Items.hovered = owner
            local fade = Items.fades[owner]
            if fade and fade.to == 0 and not InCombat() then Items:FadeButton(owner, 1, 0.15) end
            local _, db = Config()
            if db.interaction.tooltipMode == "outOfCombat" and InCombat() then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(Text("quest_items.restore"))
            AddHelp(true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", Leave)
        button:Hide()
    end
    self.recoveryButton:SetParent(record.holder)
    self.recoveryButton:SetFrameStrata("MEDIUM")
    record.recoveryButton = self.recoveryButton
    return self.recoveryButton
end

Leave = function(button)
    if Items.hovered == button then Items.hovered = nil end
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    if Items.pending then Items:Request() end
end

local function OpenItemMenu(button)
    local entry = Items.bound[button]
    if entry then Items:OpenMenu(entry.itemID, button) end
end

local function TestUse(button)
    local entry = Items.bound[button]
    if entry and entry.testItem then YUI:Print(string.format(Text("quest_items.test_used"), entry.label)) end
end

function Items:GetTestCount()
    return self.testData and #self.testData.rows or 0
end

function Items:HandleTestCommand(args)
    local command, count = args or ""
    if command == "" or command == "toggle" then
        count = self:GetTestCount() > 0 and 0 or 3
    elseif command == "off" then
        count = 0
    elseif command == "on" then
        count = 3
    else
        count = tonumber(command)
    end
    if not count or count < 0 or count > 20 or count ~= math.floor(count) then
        YUI:Print(Text("quest_items.test_usage"))
        return true
    end
    local ok, reason = self:SetTestItems(count)
    if not ok then
        YUI:Print(Text(reason == "combat" and "quest_items.test_combat" or "quest_items.test_inactive"))
    else
        YUI:Print(count > 0 and string.format(Text("quest_items.test_on"), count) or Text("quest_items.test_off"))
    end
    return true
end

function Items:ClearTestItems()
    local data = self.testData
    if not data then return end
    self.states, self.order = data.states, data.order
    self.available, self.availableOrder = data.available, data.availableOrder
    self.testData = nil
end

-- Manual test data stays outside the quest API and character SavedVariables.
function Items:SetTestItems(count)
    if type(count) ~= "number" or count < 0 or count > 20 or count ~= math.floor(count) then return false, "count" end
    if count > 0 then
        if InCombat() then return false, "combat" end
        if not Enabled() then return false, "inactive" end
    end
    self:StopFades()
    if self.hovered and GameTooltip:IsOwned(self.hovered) then GameTooltip:Hide() end
    self.hovered = nil
    self:CloseMenu()
    self:ClearTestItems()
    if count > 0 then
        local data = { rows = {}, pins = {}, states = self.states, order = self.order,
            available = self.available, availableOrder = self.availableOrder }
        local textures = { "Interface\\Icons\\Ability_Druid_ForceofNature",
            "Interface\\Icons\\Spell_Nature_Lightning", "Interface\\Icons\\Ability_Mount_RidingHorse" }
        for index = 1, count do
            data.rows[index] = { itemID = -index, questID = -index, testItem = true, link = "",
                label = string.format(Text("quest_items.test_item"), index),
                title = string.format(Text("quest_items.test_quest"), index),
                texture = textures[(index - 1) % #textures + 1], charges = index,
                tracked = true, inside = true }
        end
        self.testData, self.states, self.order = data, {}, {}
        self:SyncEnabled()
    end
    self.appliedConfig = nil
    self:Request()
    return true
end

function Items:EnsureRecord()
    if self.record then return self.record end
    local factory = YAB.SecureFactory
    local mover = factory:CreateMover(ID)
    local holder = factory:CreateHolder(ID)
    if not mover or not holder then return nil end
    holder:SetFrameStrata("MEDIUM")
    self.record = { id = ID, kind = ID, mover = mover, holder = holder, buttons = {} }
    self.record.onEnterEditMode = function() Items:SetEditMode(true) end
    self.record.onExitEditMode = function() Items:SetEditMode(false) end
    self.record.onEditModeFilterChanged = function(_, visible) Items:SetEditMode(visible) end
    self.bound = setmetatable({}, { __mode = "k" })
    YAB.LayoutBridge:Register(ID, self.record, Text("bar.questItems"), Config())
    return self.record
end

function Items:RefreshCooldowns()
    if not self.active or not self.record or self.editing then return end
    for _, button in ipairs(self.record.buttons) do
        local entry = self.bound[button]
        if entry and not entry.testItem then
            local state = entry.visualState
            state.cooldownStart, state.cooldownDuration, state.cooldownEnable = API.GetCooldown(entry.questID)
            state.cooldownActive = state.cooldownEnable and state.cooldownDuration > 0
            YAB.Visuals:UpdateButton(button, state, "cooldown")
        end
    end
end

-- One item can belong to several quests. Aggregate native area information
-- before starting a leave deadline, so one source cannot remove another source.
function Items:Collect(now)
    local rows = self.testData and self.testData.rows or API.ReadLog()
    if not rows then return nil end
    local entries, ids = {}, {}
    for _, row in ipairs(rows) do
        local inside, tracked = row.inside, row.tracked
        local entry = entries[row.itemID]
        if not entry then
            entry = row
            entry.inside, entry.autoInside, entry.areaKnown, entry.anyTracked = nil, false, false, false
            entry.areaUnknown = false
            entries[row.itemID] = entry
            ids[#ids + 1] = row.itemID
        end
        if inside ~= nil then entry.areaKnown = true end
        if inside == nil then entry.areaUnknown = true end
        if inside == true then entry.inside = true end
        if tracked then entry.anyTracked = true end
        if tracked and inside == true then entry.autoInside = true end
    end
    local pins = self:GetPins()
    local visible, nextDeadline = {}, nil
    for _, itemID in ipairs(ids) do
        local entry = entries[itemID]
        if entry.inside ~= true and entry.areaKnown and not entry.areaUnknown then entry.inside = false end
        local state = self.states[itemID] or {}
        self.states[itemID] = state
        if entry.inside == true then
            state.leaveAt = nil
        elseif entry.inside == nil then
            state.leaveAt, state.wasAutoInside = nil, nil
        elseif entry.inside == false and (state.wasInside or (state.snoozed and not state.snoozeSession)) then
            state.leaveAt = state.leaveAt or now + 5
            if now >= state.leaveAt then
                if not state.snoozeSession then state.snoozed = nil end
                state.wasInside, state.leaveAt = nil, nil
            else
                nextDeadline = math.min(nextDeadline or state.leaveAt, state.leaveAt)
            end
        end
        if entry.inside == true then state.wasInside = true end
        local hold = entry.anyTracked and state.leaveAt and state.wasAutoInside == true
        if entry.autoInside then state.wasAutoInside = true
        elseif not state.leaveAt then state.wasAutoInside = nil end
        if pins[itemID] or (not state.snoozed and (entry.autoInside or hold)) then visible[itemID] = entry end
    end
    for itemID in pairs(self.states) do
        if not entries[itemID] then self.states[itemID] = nil end
    end
    for itemID in pairs(pins) do if not entries[itemID] then pins[itemID] = nil end end
    self.available, self.availableOrder = entries, ids
    return visible, ids, nextDeadline
end

local function LeaveDeadline()
    Items.leaveTimer = nil
    Items:Request()
end

local function SameConfig(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not SameConfig(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

-- Native alpha animations only; secure bindings and layout wait for completion.
function Items:FadeButton(button, alpha, duration)
    local animation, previous = YUI.Animation, self.fades[button]
    local from = button:GetAlpha()
    if previous and previous.handle and not previous.ready then
        local progress = math.min((GetTime() - previous.startedAt) / previous.duration, 1)
        from = previous.from + (previous.to - previous.from) * progress
    end
    if animation then animation:StopTarget(button, "quest-items") end
    local state = { from = from, to = alpha, startedAt = GetTime(), duration = duration }
    self.fades[button] = state
    if not animation or not button.CreateAnimationGroup or from == alpha then
        button:SetAlpha(alpha)
        state.ready = true
        return
    end
    state.handle = animation:Fade(button, from, alpha, { driver = "native", owner = self,
        key = "quest-items", duration = duration, easing = "linear",
        onFinished = function(_, _, finished)
            if not finished or Items.fades[button] ~= state then return end
            if InCombat() then button:SetAlpha(1); Items.fades[button] = nil; return end
            state.ready = true
            if alpha == 0 then Items:Request() end
        end })
    if state.handle.noop then button:SetAlpha(alpha); state.ready = true end
end

function Items:StopFades()
    if YUI.Animation then YUI.Animation:StopOwner(self) end
    for button in pairs(self.fades) do button:SetAlpha(1); self.fades[button] = nil end
end

function Items:PrepareRemoval(visible, recovery)
    if self.editing or self.appliedEditing then return true end
    local waiting = false
    for _, button in ipairs(self.record and self.record.buttons or {}) do
        local entry, fade = self.bound[button], self.fades[button]
        local wanted = button == self.recoveryButton and recovery or (entry and visible[entry.itemID])
        if wanted then
            if fade and fade.to == 0 then self:FadeButton(button, 1, 0.15) end
        elseif not (fade and fade.to == 0 and fade.ready) then
            if not fade or fade.to ~= 0 then self:FadeButton(button, 0, 0.20) end
            if not self.fades[button].ready then waiting = true end
        end
    end
    return not waiting
end

function Items:SetEditMode(editing)
    editing = editing == true
    if self.editing == editing then return end
    self.editing = editing
    self:StopFades()
    if self.hovered and GameTooltip:IsOwned(self.hovered) then GameTooltip:Hide() end
    self.hovered = nil
    self:CloseMenu()
    self:Request()
end

function Items:Apply(visible, ids)
    local order, used = {}, {}
    for _, itemID in ipairs(self.order) do
        if visible[itemID] then order[#order + 1] = itemID; used[itemID] = true end
    end
    for _, itemID in ipairs(ids) do
        if visible[itemID] and not used[itemID] then order[#order + 1] = itemID end
    end
    local config, db = Config()
    local editing = self.editing == true
    local count = editing and 3 or #order
    local recovery = not editing and self:HasSnoozedItems()
    local pressedEffect = db.appearance and db.appearance.pressedEffect
    local changed = not self.record or #order ~= #self.order or not SameConfig(config, self.appliedConfig)
        or pressedEffect ~= self.appliedPressedEffect or recovery ~= self.recoveryVisible or editing ~= self.appliedEditing
    if not changed then
        for index, itemID in ipairs(order) do
            if index > count then break end
            local entry, old = visible[itemID], self.bound[self.record.buttons[index]]
            if itemID ~= self.order[index] or not old or entry.questID ~= old.questID
                or entry.link ~= old.link or entry.texture ~= old.texture
                or entry.charges ~= old.charges or entry.title ~= old.title then changed = true; break end
        end
    end
    if not changed then self:RefreshCooldowns(); return true end
    local record = self:EnsureRecord()
    if not record then return false end
    self.recoveryVisible = recovery
    self.appliedConfig = YAB:CopyValue(config)
    self.appliedPressedEffect = pressedEffect
    self.appliedEditing = editing
    self.order = order
    record.buttons = {}
    local firstEntry = visible[order[1]]
    for index = 1, count do
        local itemID = order[index]
        local button = self.pool[index]
        if not button then
            button = YUI.GUI2.Secure:CreateActionHost(record.holder, { useOnKeyDown = false,
                onEnter = Enter, onLeave = Leave, frameLevelOffset = 1 })
            if not button then return false end
            -- Action hosts fill their owner by default; each item occupies its own slot.
            button:ClearAllPoints()
            self.pool[index] = button
            YAB.SecureFactory:SetButtonMeta(button, { barId = ID, index = index, kind = ID })
        end
        local entry, old = visible[itemID], self.bound[button]
        local appearing = not editing and (not old or old.itemID ~= itemID)
        if editing then
            button:SetAlpha(1)
        elseif appearing then
            if YUI.Animation then YUI.Animation:StopTarget(button, "quest-items") end
            self.fades[button] = nil
            button:SetAlpha(0)
        end
        self.bound[button] = entry
        local use = not editing and (entry.testItem and { kind = "custom", onClick = TestUse }
            or { kind = "item", item = "item:" .. itemID })
        button:SetActions(editing and {} or { left = use, right = use,
            altLeft = { kind = "custom", onClick = OpenItemMenu },
            altRight = { kind = "custom", onClick = OpenEditor } })
        record.buttons[index] = button
        button:Show()
        local state = { hasAction = true, usable = true,
            texture = entry and entry.texture or firstEntry and firstEntry.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
            hotkeyText = "", nameText = "", countText = not editing and config.showCounts ~= false
                and entry.charges and entry.charges > 1 and tostring(entry.charges) or "" }
        if entry then entry.visualState = state end
        button.previewState = editing and state or nil
        if appearing then self:FadeButton(button, 1, 0.15) end
    end
    for index = count + 1, #self.pool do
        local button = self.pool[index]
        button:Hide()
        button:SetActions({})
        self.bound[button] = nil
        button.previewState = nil
        self.fades[button] = nil
        record.buttons[index] = nil
        YAB.Visuals:ReleaseButton(button)
    end
    if recovery then
        local button = self:EnsureRecoveryButton(record)
        local appearing = not button:IsShown()
        if appearing then button:SetAlpha(0) end
        record.buttons[count + 1] = button
        button:Show()
        if appearing then self:FadeButton(button, 1, 0.15) end
    elseif self.recoveryButton then
        self.recoveryButton:Hide()
        self.fades[self.recoveryButton] = nil
        record.buttons[count + 1] = nil
    end
    record.configSnapshot = YAB.BarManager:RefreshConfigSnapshot(ID, db)
    record.configSnapshot.buttons = math.max(#record.buttons, 1)
    YAB.BarManager:ApplyLayout(record, config, db)
    for _, button in ipairs(record.buttons) do
        local entry = self.bound[button]
        local state = button.previewState or entry and entry.visualState
        if state then YAB.Visuals:UpdateButton(button, state, "full") end
    end
    YAB.BarManager:ApplyRecordVisibility(record)
    YAB.BarManager:ApplyMouseoverVisibility(record)
    self:RefreshCooldowns()
    return true
end

function Items:Refresh()
    if not self.active or not Enabled() then self:Stop(); return end
    self.pending = true
    if InCombat() or self.hovered or self.menuTargets then return end
    local now = GetTime()
    local visible, ids, deadline = self:Collect(now)
    if not visible then
        self:StopFades()
        -- The enabled editor mover does not depend on readable quest candidates.
        if not self.record or self.editing ~= self.appliedEditing then self:Apply({}, {}) end
        return
    end
    CancelTimer("leaveTimer")
    if deadline then self.leaveTimer = C_Timer.NewTimer(math.max(deadline - now, 0.01), LeaveDeadline) end
    self.pending = not (self:PrepareRemoval(visible, self:HasSnoozedItems()) and self:Apply(visible, ids))
    self.passes = self.passes + 1
end

local function RunPending()
    Items.refreshTimer = nil
    Items:Refresh()
end

function Items:Request()
    if not self.active then return end
    self.pending = true
    if not self.refreshTimer and not InCombat() and not self.hovered and not self.menuTargets then
        self.refreshTimer = C_Timer.NewTimer(0.1, RunPending)
    end
end

function Items:HideRecord()
    local record = self.record
    if not record then return end
    if record.visibilityHandle and YUI.Visibility then YUI.Visibility:Release(record.visibilityHandle); record.visibilityHandle = nil end
    if YAB.Drivers and YAB.Drivers.ClearFrame then YAB.Drivers:ClearFrame(record.holder) end
    if YAB.BarManager.ReleaseMouseoverFade then YAB.BarManager:ReleaseMouseoverFade(record) end
    if YAB.BarManager.ResetMouseoverProxy then YAB.BarManager:ResetMouseoverProxy(record) end
    if YAB.BarManager.mouseoverRecords then
        YAB.BarManager.mouseoverRecords[record.holder] = nil
        for _, button in ipairs(self.pool) do YAB.BarManager.mouseoverRecords[button] = nil end
        if self.recoveryButton then YAB.BarManager.mouseoverRecords[self.recoveryButton] = nil end
    end
    for _, button in ipairs(self.pool) do
        button:Hide()
        button:SetActions({})
        button.previewState = nil
        YAB.Visuals:ReleaseButton(button)
    end
    if self.recoveryButton then self.recoveryButton:Hide() end
    self.appliedEditing, self.recoveryVisible = nil, false
    record.buttons = {}
    record.holder:Hide()
    record.mover:Hide()
    YAB.LayoutBridge:Unregister(ID, true)
    self.record, self.bound, self.order, self.appliedConfig, self.appliedPressedEffect = nil, nil, {}, nil, nil
end

function Items:Stop()
    self:ClearTestItems()
    self.active, self.pending, self.editing = false, false, false
    self:StopFades()
    CancelTimer("refreshTimer")
    CancelTimer("leaveTimer")
    self:CloseMenu()
    if self.tooltipDivider then self.tooltipDivider:Hide() end
    if self.hovered and GameTooltip:IsOwned(self.hovered) then GameTooltip:Hide() end
    self.hovered = nil
    if self.frame then self.frame:UnregisterAllEvents() end
    if InCombat() and self.record then
        self.pendingStop = true
        if self.frame then self.frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    else
        self:HideRecord()
        self.pendingStop = nil
        if self.frame then self.frame:SetScript("OnEvent", nil) end
    end
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then Items:StopFades(); return end
    if event == "PLAYER_REGEN_ENABLED" and Items.pendingStop then Items:Stop(); return end
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then Items:RefreshCooldowns() else Items:Request() end
end

function Items:SyncEnabled()
    if not Enabled() then self:Stop(); return end
    if not self.active then
        self.frame = self.frame or CreateFrame("Frame")
        self.frame:SetScript("OnEvent", OnEvent)
        for _, event in ipairs(EVENTS) do
            self.frame:RegisterEvent(event)
        end
        self.active, self.pendingStop = true, nil
    end
    self:Request()
end

-- Cold settings access also works when the bar is disabled or every item is hidden.
function Items:GetAvailableItems()
    local rows = self.testData and self.testData.rows or API.ReadLog() or {}
    local result, seen = {}, {}
    for _, row in ipairs(rows) do
        if not seen[row.itemID] then
            seen[row.itemID] = true
            row.pinned = self:GetPins()[row.itemID] == true
            result[#result + 1] = row
        end
    end
    return result
end

function Items:GetStats()
    local activeFades = 0
    for _, fade in pairs(self.fades) do if fade.handle and not fade.ready then activeFades = activeFades + 1 end end
    return { active = self.active, pending = self.pending, pendingStop = self.pendingStop == true,
        testItems = self:GetTestCount(),
        visibleItems = #self.order, pooledButtons = #self.pool, passes = self.passes,
        activeFades = activeFades, recoveryVisible = self.recoveryVisible == true,
        timers = (self.refreshTimer and 1 or 0) + (self.leaveTimer and 1 or 0),
        listeners = self.active and #EVENTS or self.pendingStop and 1 or 0 }
end
