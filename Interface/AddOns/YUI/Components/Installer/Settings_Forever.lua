local _, YUI = ...
if not YUI.IsForever then return end
local Settings = {}
YUI.InstallerSettings = Settings
local LC = YUI.Locale:Get("Core")
local GUI = YUI.GUI2
local System = YUI.API.System
local unpackValues = unpack or table.unpack

local definitions = {
    { id = "npc", label = "installer.settings.npc", value = 3 },
    { id = "camera", cvar = "cameraDistanceMaxZoomFactor", label = "installer.settings.camera", value = 4 },
    { id = "cooldown", cvar = "countdownForCooldowns", label = "installer.settings.cooldown", value = 1,
        tooltip = "installer.settings.cooldown.hint" },
    { id = "combatText", label = "installer.settings.combatText", tooltip = "installer.settings.combatText.hint", writes = {
        { "WorldTextScale_v2", 1.3 },
        { "WorldTextScreenY_v2", 0.03 },
        { "WorldTextCritScreenY_v2", 0.03 },
        { "classicStyleWorldText", 0 },
        { "floatingCombatTextCombatDamageDirectionalScale_v2", 1.5 },
        { "floatingCombatTextCombatDamageDirectionalOffset_v2", 0.2 },
        { "WorldTextStartPosRandomness_v2", 1.0 },
    } },
    { id = "loot", cvar = "autoLootDefault", label = "installer.settings.loot", value = 1 },
    { id = "compare", cvar = "alwaysCompareItems", label = "installer.settings.compare", value = 1 },
    { id = "quest", cvar = "instantQuestText", label = "installer.settings.quest", value = 1 },
    { id = "deathEffect", cvar = "ffxDeath", label = "installer.settings.deathEffect", value = 0,
        tooltip = "installer.settings.deathEffect.hint" },
}
local npcNames = {
    "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
    "UnitNameNPC", "ShowQuestUnitCircles",
}
-- Same five combinations as the native NPC names dropdown.
local npcValues = {
    { 1, 0, 0, 0, 0 }, { 1, 1, 0, 0, 1 }, { 1, 1, 1, 0, 1 },
    { 0, 0, 0, 1, 1 }, { 0, 0, 0, 0, 1 },
}
local definitionsById = {}
for _, definition in ipairs(definitions) do definitionsById[definition.id] = definition end

function Settings:Reset()
    self.selection, self.values = {}, {}
    self.feedback, self.unavailable = {}, {}
    for _, definition in ipairs(definitions) do
        self.selection[definition.id] = true
        self.values[definition.id] = definition.value
    end
    for index = 2, 5 do self.selection["bar" .. index] = true end
end
Settings:Reset()

local function ReadCVar(name)
    return tonumber(System.GetCVarSafe(name))
end

local function WriteCVar(name, value)
    local before = ReadCVar(name)
    if before == nil then return false, false, "unreadable" end
    if math.abs(before - value) < 0.0001 then return true, false end
    local ok = System.SetCVarSafe(name, value)
    local actual = ReadCVar(name)
    return ok and actual ~= nil and math.abs(actual - value) < 0.0001,
        actual ~= nil and math.abs(actual - before) >= 0.0001,
        not ok and "write_failed" or actual == nil and "unreadable" or "mismatch"
end

local function IsEnabled(value)
    return value == true or value == 1 or value == "1"
end

local function ReadBars()
    if type(GetActionBarToggles) ~= "function" then return nil end
    local function Pack(...) return { n = select("#", ...), ... } end
    local ok, values = pcall(function() return Pack(GetActionBarToggles()) end)
    if not ok or values.n < 4 then return nil end
    return values
end

local function CVarAvailability(name)
    if System.GetCVarSafe(name) == nil then return "unsupported" end
    local state = System.GetCVarWriteState(name)
    if state == "MISSING" then return "unsupported" end
    if state == "READ_ONLY" or state == "SECURE" then return "blocked" end
    if ReadCVar(name) == nil then return "unreadable" end
end

local function Availability(id)
    if id:match("^bar%d$") then
        if not ReadBars() or type(SetActionBarToggles) ~= "function" then return "unsupported" end
    else
        local definition = definitionsById[id]
        if id == "npc" then
            for _, name in ipairs(npcNames) do
                local reason = CVarAvailability(name)
                if reason then return reason end
            end
        elseif definition.writes then
            for _, write in ipairs(definition.writes) do
                local reason = CVarAvailability(write[1])
                if reason then return reason end
            end
        else
            return CVarAvailability(definition.cvar)
        end
    end
end

function Settings:HasSelection()
    for id, selected in pairs(self.selection) do if selected and not self.unavailable[id] then return true end end
    return false
end

function Settings:Apply()
    local result = { applied = 0, changed = false, failed = {}, details = {} }
    if InCombatLockdown() then return false, result, "combat" end
    local function Failed(id, label, reason)
        result.failed[#result.failed + 1] = label
        result.details[id] = reason
    end
    local barsRequested = false
    for index = 2, 5 do barsRequested = barsRequested or self.selection["bar" .. index] end
    if barsRequested then
        local bars = ReadBars()
        if not bars or type(SetActionBarToggles) ~= "function" then
            for index = 2, 5 do
                if self.selection["bar" .. index] then
                    Failed("bar" .. index, string.format(LC["installer.settings.bar"], index), "unsupported")
                end
            end
        else
            local changed = false
            local before = {}
            for index = 2, 5 do
                before[index - 1] = bars[index - 1]
                if self.selection["bar" .. index] then
                    changed = changed or not IsEnabled(bars[index - 1])
                    bars[index - 1] = true
                end
            end
            local ok = not changed or pcall(SetActionBarToggles, unpackValues(bars, 1, bars.n))
            local actual = ReadBars()
            for index = 2, 5 do
                if self.selection["bar" .. index] then
                    if actual and IsEnabled(actual[index - 1]) ~= IsEnabled(before[index - 1]) then
                        result.changed = true
                    end
                    if ok and actual and IsEnabled(actual[index - 1]) then
                        result.applied = result.applied + 1
                    else
                        Failed("bar" .. index, string.format(LC["installer.settings.bar"], index),
                            not ok and "write_failed" or "mismatch")
                    end
                end
            end
        end
    end
    for _, definition in ipairs(definitions) do
        if self.selection[definition.id] then
            local value = self.values[definition.id]
            local writes = {}
            local valid, reason = true, Availability(definition.id)
            if reason then
                valid = false
            elseif definition.id == "npc" then
                local values = npcValues[value]
                if values then
                    for index, name in ipairs(npcNames) do writes[#writes + 1] = { name, values[index] } end
                end
            elseif definition.writes then
                writes = definition.writes
            elseif definition.id ~= "camera" or (type(value) == "number" and value >= 1 and value <= 4) then
                writes[1] = { definition.cvar, value }
            end
            if valid then
                valid = #writes > 0
                if not valid then reason = "invalid" end
                for _, write in ipairs(writes) do
                    local ok, changed, failure = WriteCVar(write[1], write[2])
                    valid = valid and ok
                    result.changed = result.changed or changed
                    if not ok then reason = reason or failure end
                end
            end
            if valid then
                result.applied = result.applied + 1
            else
                Failed(definition.id, LC[definition.label], reason)
            end
        end
    end
    self.feedback = result.details
    return result.applied > 0 and #result.failed == 0, result
end

function Settings:BuildPage(content, onSelectionChanged)
    local controls, options, hints, tooltips = {}, {}, {}, {}
    content.settingsControls = controls
    local RefreshFeedback
    local function Changed()
        self.feedback = {}
        if RefreshFeedback then RefreshFeedback() end
        onSelectionChanged()
    end
    local function Card(title, column, y, height, width)
        local card = GUI:CreatePanel(content, {
            width = width or 181, height = height, surface = "color.surface.panel", border = "color.border.subtle",
        })
        card:SetPoint("TOPLEFT", content, "TOPLEFT", column * 189, -44 - y)
        local label = GUI:CreateText(card, LC[title], 12, "color.text.primary")
        label:SetPoint("TOPLEFT", 9, -8)
        return card
    end
    local function Checkbox(card, id, text, y, x, width)
        self.unavailable[id] = Availability(id)
        if self.unavailable[id] then self.selection[id] = false end
        local definition = definitionsById[id]
        tooltips[id] = definition and definition.tooltip
            and LC[definition.tooltip] .. "\n\n" .. LC["installer.settings.preserve"]
            or LC["installer.settings.preserve"]
        local opts = {
            width = width or 163, height = 22, text = text, checked = self.selection[id],
            disabled = self.unavailable[id] ~= nil,
            tooltip = tooltips[id],
            onClick = function(_, checked)
                self.selection[id] = checked == true
                if controls[id .. "Value"] then controls[id .. "Value"]:SetDisabled(not checked) end
                Changed()
            end,
        }
        local checkbox = GUI.Form:CreateCheckbox(card, opts)
        checkbox:SetPoint("TOPLEFT", x or 9, -y)
        checkbox.box:SetSize(16, 16)
        checkbox.text:SetFont(GUI:GetFont("font.family.body"), 12)
        controls[id] = checkbox
        options[id] = opts
        return checkbox
    end
    local function Hint(card, id, text, y, height)
        local hint = GUI:CreateText(card, text, 11, "color.text.secondary")
        hint:SetPoint("TOPLEFT", 9, -y)
        hint:SetWidth(163)
        hint:SetHeight(height or 24)
        hint:SetJustifyH("LEFT")
        hints[id] = { label = hint, text = text }
    end
    local bars = Card("installer.settings.bars", 0, 0, 88)
    for index = 2, 5 do
        local cell = index - 2
        Checkbox(bars, "bar" .. index, string.format(LC["installer.settings.bar.short"], index),
            28 + math.floor(cell / 2) * 26, 9 + (cell % 2) * 85, 77)
    end
    local camera = Card("installer.settings.camera.card", 0, 96, 104)
    Checkbox(camera, "camera", LC["installer.settings.camera"], 28)
    local slider = GUI.Form:CreateSlider(camera, {
        width = 163, inline = true, inputWidth = 38, min = 1, max = 4, step = 0.1, precision = 1,
        get = function() return self.values.camera end,
        set = function(value) self.values.camera = value; Changed() end,
        disabled = not self.selection.camera,
    })
    slider:SetPoint("TOPLEFT", 9, -54)
    controls.cameraValue = slider
    Hint(camera, "camera", LC["installer.settings.camera.hint"], 84, 16)

    local names = Card("installer.settings.names", 1, 0, 88)
    Checkbox(names, "npc", LC["installer.settings.npc"], 29)
    local npcOptions = {}
    for index = 1, 5 do
        npcOptions[index] = { text = LC["installer.settings.npc." .. index], value = index }
    end
    local dropdownOptions = {
        width = 163, height = 26, options = npcOptions,
        get = function() return self.values.npc end,
        set = function(value)
            self.values.npc = value
            Changed()
        end,
        disabled = not self.selection.npc,
        tooltip = LC["installer.settings.npc." .. self.values.npc],
    }
    local dropdown = GUI.Form:CreateDropdown(names, dropdownOptions)
    dropdown:SetPoint("TOPLEFT", 9, -54)
    if dropdown.text then dropdown.text:SetFont(GUI:GetFont("font.family.body"), 11) end
    controls.npcValue = dropdown

    local combat = Card("installer.settings.combat", 2, 0, 88)
    Checkbox(combat, "cooldown", LC["installer.settings.cooldown"], 29)
    Checkbox(combat, "combatText", LC["installer.settings.combatText"], 56)
    local convenience = Card("installer.settings.convenience", 1, 96, 104, 370)
    Checkbox(convenience, "loot", LC["installer.settings.loot"], 27)
    Checkbox(convenience, "compare", LC["installer.settings.compare"], 27, 198)
    Checkbox(convenience, "quest", LC["installer.settings.quest"], 57)
    Checkbox(convenience, "deathEffect", LC["installer.settings.deathEffect"], 57, 198)

    RefreshFeedback = function()
        for id, checkbox in pairs(controls) do
            if options[id] then
                local reason = self.unavailable[id] or self.feedback[id]
                local message = reason and LC["installer.settings.reason." .. reason]
                options[id].tooltip = message or tooltips[id]
                GUI:SetTextColorKey(checkbox.text, self.unavailable[id] and "color.text.disabled"
                    or reason and "color.state.warning" or "color.text.primary")
                if hints[id] then
                    hints[id].label:SetText(message or hints[id].text)
                    GUI:SetTextColorKey(hints[id].label, reason and "color.state.warning" or "color.text.secondary")
                end
            end
        end
        dropdownOptions.tooltip = self.unavailable.npc and LC["installer.settings.reason." .. self.unavailable.npc]
            or self.feedback.npc and LC["installer.settings.reason." .. self.feedback.npc]
            or LC["installer.settings.npc." .. self.values.npc]
    end
    content.RefreshSettingsFeedback = RefreshFeedback
    RefreshFeedback()
end
