local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end
local unpack = unpack or table.unpack

local Tools = { ids = { "aspects", "totems", "mageTools", "warlockTools", "rogueTools",
    "priestTools", "paladinTools", "druidTools", "warriorTools", "paladinBlessings" },
    classes = { HUNTER = "aspects", SHAMAN = "totems", MAGE = "mageTools",
        WARLOCK = "warlockTools", ROGUE = "rogueTools", PRIEST = "priestTools",
        PALADIN = "paladinTools", DRUID = "druidTools", WARRIOR = "warriorTools" },
    classOrder = { "MAGE", "HUNTER", "SHAMAN", "WARLOCK", "ROGUE", "PRIEST", "PALADIN", "DRUID", "WARRIOR" }, cache = {} }
YAB.ClassTools = Tools
local OWN_FIELDS = { flyoutDirection = true, aspectOrder = true, aspectActiveStyle = true, showUnlearned = true,
    showPetUtilities = true, mageScroll = true, mageIntellect = true, mageArmor = true,
    mageArmorLeft = true, mageArmorMiddle = true, mageArmorRight = true, mageMissingBuffGlow = true, mageManaGemCount = true,
    classToolOrder = true, classToolDisabled = true, classToolSelected = true, teamBlessings = true, teamVisibility = true,
    travelTextOffsetX = true, travelTextOffsetY = true, teamClassIconOffsetX = true, teamClassIconOffsetY = true,
    classToolsEnabled = true, classToolsIndependent = true, classToolsInitialized = true, classToolsDetached = true, label = true }

Tools.manaGemKeys = { "manaGem", "manaGem2", "manaGem3", "manaGem4" }
Tools.manaGemSlot = {}
Tools.defaultManaGemCount = 3
for index, key in ipairs(Tools.manaGemKeys) do Tools.manaGemSlot[key] = index end

Tools.buttonKeys = {
    mageTools = { "scroll", "intellect", "armor", "water", "bread", unpack(Tools.manaGemKeys) },
    aspects = { "aspect1", "aspect2", "aspect3", "aspect4", "aspect5", "aspect6", "aspect7", "aspect8", "trueshotAura", "pet" },
    totems = { "summon", "earth", "fire", "water", "air", "recall", "imbue", "shield" },
    warlockTools = { "demon", "healthstone", "soulstone", "firestone", "spellstone", "armor", "ritual" },
    rogueTools = { "mainhand", "mainhandStone", "offhand", "offhandStone" }, priestTools = { "fortitude", "spirit", "shadow", "innerfire" },
    paladinTools = { "blessing", "righteous", "seal" }, druidTools = { "mark", "thorns" },
    warriorTools = { "battle" },
    paladinBlessings = { "manage", "MAGE", "HUNTER", "SHAMAN", "WARLOCK", "ROGUE", "PRIEST", "PALADIN", "DRUID", "WARRIOR" },
}
table.insert(Tools.buttonKeys.mageTools, "teleport")
table.insert(Tools.buttonKeys.mageTools, "portal")
local LEGACY_FIELDS = { scroll = "mageScroll", intellect = "mageIntellect", armor = "mageArmor" }

function Tools:GetManaGemCount(config)
    local count = tonumber(config and config.mageManaGemCount)
    if not count or count ~= count then return self.defaultManaGemCount end
    return math.max(1, math.min(#self.manaGemKeys, math.floor(count)))
end

function Tools:IsClassBar(id)
    return self.buttonKeys[id] ~= nil
end

function Tools:InitializeDB(db)
    if db.classToolsVersion == 6 then return end
    db.specialBars = db.specialBars or {}
    local existingTeam, old = db.specialBars.paladinBlessings, db.specialBars.paladinTools
    for _, id in ipairs(self.ids) do
        local config = db.specialBars[id]
        local legacy = type(config) == "table" and id ~= "mageTools"
        config = config or (YAB.Defaults and YAB:CopyValue(YAB.Defaults.specialBars[id])) or {}
        -- Only the explicit detach control creates an independent toolbar.
        -- Retain old per-class values as dormant settings, not extra bars.
        config.classToolsDetached = config.classToolsDetached == true
        config.classToolsIndependent = config.classToolsDetached
        if config.classToolsInitialized == nil then config.classToolsInitialized = legacy end
        if type(config.classToolOrder) ~= "table" and id == "aspects" and type(config.aspectOrder) == "table" then
            config.classToolOrder = {}
            for _, index in ipairs(config.aspectOrder) do
                if type(index) == "number" and index >= 1 and index <= 8 then
                    config.classToolOrder[#config.classToolOrder + 1] = "aspect" .. index
                end
            end
        end
        if id == "mageTools" and (tonumber(db.classToolsVersion) or 0) < 4
            and type(config.classToolOrder) == "table" and #config.classToolOrder == 8 then
            local formerDefault = {"scroll","intellect","armor","water","bread","teleport","portal","manaGem"}
            local matches = true
            for index, key in ipairs(formerDefault) do
                if config.classToolOrder[index] ~= key then matches = false; break end
            end
            if matches then config.classToolOrder = {"scroll","intellect","armor","water","bread","manaGem","teleport","portal"} end
        end
        if id == "mageTools" and (config.travelTextOffsetX == nil or config.travelTextOffsetX == 0) then
            config.travelTextOffsetX = 2
        end
        db.specialBars[id] = config
    end
    local team = db.specialBars.paladinBlessings
    if team and not team.blessingBarMigrated then
        team.classToolsIndependent, team.classToolsDetached, team.classToolsInitialized = true, true, true
        if type(old) == "table" then
            local style = old.classToolsDetached and old or db.specialBars.classTools or old
            for key,value in pairs(style) do
                if not OWN_FIELDS[key] and key~="enabled" and key~="layout" and key~="visibility"
                    and key~="buttons" and key~="rows" and key~="blessingBarMigrated"
                    and (not existingTeam or existingTeam[key] == nil) then team[key]=YAB:CopyValue(value) end
            end
            for _, key in ipairs({ "teamBlessings", "teamClassIconOffsetX", "teamClassIconOffsetY" }) do
                if (not existingTeam or existingTeam[key] == nil) and old[key] ~= nil then
                    team[key] = YAB:CopyValue(old[key])
                end
            end
            if (not existingTeam or existingTeam.enabled == nil) and old.classToolDisabled
                and type(old.classToolDisabled.teamBlessing) == "boolean" then
                team.enabled = not old.classToolDisabled.teamBlessing
            end
        end
        team.blessingBarMigrated = true
    end
    db.classToolsVersion = 6
end

function Tools:GetClassToken(id)
    if id == "paladinBlessings" then return "PALADIN" end
    for class, candidate in pairs(self.classes) do if candidate == id then return class end end
end

local ADDED_AFTER = { mainhandStone="mainhand", offhandStone="offhand", firestone="soulstone", spellstone="firestone" }

function Tools:GetButtonOrder(id, config)
    local defaults, result, seen = self.buttonKeys[id] or {}, {}, {}
    local saved = config and config.classToolOrder
    if type(saved) ~= "table" and id == "aspects" and type(config and config.aspectOrder) == "table" then
        saved = {}
        for _, index in ipairs(config.aspectOrder) do saved[#saved + 1] = "aspect" .. tostring(index) end
    end
    for _, key in ipairs(type(saved) == "table" and saved or {}) do
        for _, valid in ipairs(defaults) do
            if key == valid and not seen[key] then result[#result + 1], seen[key] = key, true; break end
        end
    end
    for _, key in ipairs(defaults) do
        if not seen[key] then
            local position
            local slot = id == "mageTools" and self.manaGemSlot[key]
            local previous = slot and (self.manaGemKeys[slot - 1] or "bread") or ADDED_AFTER[key]
            if previous then
                for index, existing in ipairs(result) do if existing == previous then position = index + 1; break end end
            elseif key == "trueshotAura" then
                for index, existing in ipairs(result) do if existing == "pet" then position = index; break end end
            end
            table.insert(result, position or #result + 1, key)
        end
    end
    return result
end

function Tools:GetButtonLabel(id, key)
    if id == "paladinBlessings" then return YUI.Locale:Get("YActionBar")["class_tools.blessing_" .. key] end
    if not self:IsClassBar(id) or not key then return end
    local locale = YUI.Locale:Get("YActionBar")
    local slot = id == "mageTools" and self.manaGemSlot[key]
    if slot and slot > 1 then return locale["class_tools.manaGem"] .. " " .. slot end
    if key:match("^aspect%d+$") then
        local spell = YAB.ClassToolData and YAB.ClassToolData.preview[id][key]
        local info = spell and YUI.API.Spell.GetInfo(spell)
        return info and YUI.API.Security.SafeString(info.name)
    end
    local labelKey = "class_tools." .. (id == "totems" and key == "water" and "water_totem" or key)
    local label = locale[labelKey]
    if label and label ~= labelKey then return label end
end

function Tools:IsButtonEnabled(id, key, config)
    if id == "paladinBlessings" then return true end
    config = config or self:GetConfig(id) or {}
    local slot = id == "mageTools" and self.manaGemSlot[key]
    if slot then
        if slot > self:GetManaGemCount(config) then return false end
        key = "manaGem"
    end
    if config.classToolDisabled and config.classToolDisabled[key] == true then return false end
    if id == "mageTools" and LEGACY_FIELDS[key] then return config[LEGACY_FIELDS[key]] ~= false end
    if id == "aspects" and key == "pet" then return config.showPetUtilities ~= false end
    return true
end

function Tools:SetButtonEnabled(id, key, enabled)
    if id == "paladinBlessings" then return false end
    local db = YAB:GetDB()
    local config = db.specialBars and db.specialBars[id]
    if not (config and self:IsClassBar(id)) then return false end
    if id == "mageTools" and self.manaGemSlot[key] then key = "manaGem" end
    local field = id == "mageTools" and LEGACY_FIELDS[key] or id == "aspects" and key == "pet" and "showPetUtilities"
    local clearDisabled = field and config.classToolDisabled and config.classToolDisabled[key] ~= nil
    if field then
        config[field] = enabled == true
        if config.classToolDisabled then config.classToolDisabled[key] = nil end
    else
        config.classToolDisabled = config.classToolDisabled or {}
        config.classToolDisabled[key] = enabled ~= true
        field = "classToolDisabled"
    end
    self:Invalidate()
    if YAB.ConfigSets then
        if clearDisabled then
            YAB.ConfigSets:SaveActiveSettings(id, {
                { field = field, value = config[field] },
                { field = "classToolDisabled", value = config.classToolDisabled },
            }, "class-tool-enabled", self)
        else
            YAB.ConfigSets:SaveActiveSetting(id, field, config[field], "class-tool-enabled", self)
        end
    end
    local bars = YAB.ClassBars
    if bars and bars.active[id] then
        bars.configDirty[id] = true
        bars:Refresh(id)
    elseif bars and self:IsIndependent(id, db) and YAB.BarManager.QueueSettingsRefresh then
        YAB.BarManager:QueueSettingsRefresh(id, "layout")
    end
    return true
end

function Tools:SwapButtons(id, first, second)
    if YAB.Adapter:InCombat() or not self:IsClassBar(id) or first == second then return false end
    local config = YAB:GetDB().specialBars[id]
    local order, a, b = self:GetButtonOrder(id, config)
    for index, key in ipairs(order) do if key == first then a = index elseif key == second then b = index end end
    if not a or not b then return false end
    order[a], order[b] = order[b], order[a]
    config.classToolOrder = order
    if id == "aspects" then
        config.aspectOrder = {}
        for _, key in ipairs(order) do local index = tonumber(key:match("^aspect(%d+)$")); if index then config.aspectOrder[#config.aspectOrder + 1] = index end end
    end
    self:Invalidate()
    if YAB.ConfigSets then YAB.ConfigSets:SaveActiveSetting(id, "classToolOrder", order, "class-tool-order", self) end
    if YAB.ClassBars then YAB.ClassBars.configDirty[id] = true; YAB.ClassBars:Refresh(id) end
    return true
end

function Tools:ResetClassOptions(id)
    local own = YAB:GetDB().specialBars[id]
    local defaults = YAB.Defaults.specialBars[id]
    if not (own and defaults and self:IsClassBar(id)) then return end
    for key in pairs(OWN_FIELDS) do
        if key ~= "label" and key ~= "classToolsIndependent" and key ~= "classToolsInitialized" and key ~= "classToolsDetached" then
            own[key] = YAB:CopyValue(defaults[key])
        end
    end
    self:Invalidate()
end

function Tools:GetLayoutButtons(record)
    local factory, available = YAB.SecureFactory, {}
    for _, button in ipairs(record.buttons or {}) do
        local meta = factory:GetButtonMeta(button)
        if meta and meta.classToolKey then available[meta.classToolKey] = button end
    end
    if record.petUtilityToggle then available.pet = record.petUtilityToggle end
    local result = record.classToolLayoutButtons or {}
    record.classToolLayoutButtons = result
    for index in pairs(result) do result[index] = nil end
    for _, key in ipairs(self:GetButtonOrder(record.id, self:GetConfig(record.id))) do
        if available[key] then result[#result + 1] = available[key] end
    end
    return result, #result
end

local function OpenSettings(button, mouse, down)
    if down or mouse ~= "LeftButton" or not IsAltKeyDown() then return end
    local meta = YAB.SecureFactory:GetButtonMeta(button)
    if not meta or not meta.classToolKey then return end
    Tools.previewClass = Tools:GetClassToken(meta.barId)
    YAB:OpenSettings(Tools:GetSettingsBarId(meta.barId), "class")
end

function Tools:SetDragTarget(button)
    if self.dragTarget == button then return end
    local visuals = YAB.Visuals
    if visuals and visuals.SetClassDragHighlight then
        if self.dragTarget then visuals:SetClassDragHighlight(self.dragTarget, false) end
        if button then visuals:SetClassDragHighlight(button, true) end
    end
    self.dragTarget = button
end

local function DragEnter(button)
    if not Tools.dragButton then return end
    local meta = YAB.SecureFactory:GetButtonMeta(button)
    local id = button.classToolId or meta and meta.barId
    if button ~= Tools.dragButton and id == Tools.dragId and button:GetParent() == Tools.dragButton:GetParent()
        and not YAB.Adapter:InCombat() then
        Tools:SetDragTarget(button)
    end
    if GameTooltip then GameTooltip:Hide() end
end

local function DragLeave(button)
    if Tools.dragTarget == button then Tools:SetDragTarget(nil) end
end

function Tools:PrepareDragFeedback(button)
    if button.classToolDragFeedback then return end
    button:HookScript("OnEnter", DragEnter)
    button:HookScript("OnLeave", DragLeave)
    button:HookScript("OnHide", DragLeave)
    button.classToolDragFeedback = true
end

function Tools:CancelDrag()
    local button, alpha = self.dragButton, self.dragAlpha
    self.dragButton, self.dragAlpha, self.dragId = nil, nil, nil
    self:SetDragTarget(nil)
    if self.dragVisual then self.dragVisual:StopMovingOrSizing(); self.dragVisual:Hide() end
    if button then button:SetAlpha(alpha or 1) end
end

local function DragVisualHidden()
    if Tools.dragButton then Tools:CancelDrag() end
end

function Tools:PrepareDragVisual()
    if YAB.Adapter:InCombat() then return end
    local gui = YUI.GUI2
    if not (gui and gui.CreateIconSlot) then return end
    if not self.dragVisual then
        self.dragVisual = YUI.GUI2:CreateIconSlot(UIParent, {name="YUI_YActionBar_ClassDragVisual", size=32,
            variant="bare", shape="square", border="none", animate=false})
        self.dragVisual:SetFrameStrata("TOOLTIP")
        self.dragVisual:EnableMouse(false)
        self.dragVisual:SetMovable(true)
        self.dragVisual:Hide()
        self.dragIcon = self.dragVisual.icon
        self.dragVisual:SetScript("OnHide", DragVisualHidden)
        if UISpecialFrames then table.insert(UISpecialFrames, "YUI_YActionBar_ClassDragVisual") end
    end
    return self.dragVisual
end

function Tools:BeginDrag(button, id, key)
    if YAB.Adapter:InCombat() or not IsShiftKeyDown() or (YAB.KeybindMode and YAB.KeybindMode.active)
        or (GetCursorInfo and GetCursorInfo() ~= nil) then return false end
    self:CancelDrag()
    local visual = YAB.Visuals and YAB.Visuals.buttons and YAB.Visuals.buttons[button]
    local texture = visual and visual.icon and visual.icon.GetTexture and visual.icon:GetTexture()
    local security = YUI.API.Security
    texture = security.SafeNumber(texture) or security.SafeString(texture)
    if not texture then
        local spell = YAB.ClassToolData and YAB.ClassToolData.preview[id] and YAB.ClassToolData.preview[id][key]
        local info = spell and YUI.API.Spell.GetInfo(spell)
        texture = info and (security.SafeNumber(info.originalIconID) or security.SafeNumber(info.iconID))
    end
    local ghost = texture and GetCursorPosition and self:PrepareDragVisual()
    if ghost then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local sourceScale = button.GetEffectiveScale and button:GetEffectiveScale() or scale
        local snapshot = visual and visual.runtimeSnapshot or self:GetConfig(id) or {}
        local width = visual and visual.visualWidth or button:GetWidth() or 30
        local height = visual and visual.visualHeight or button:GetHeight() or 30
        ghost:SetIconAppearance({size=width * sourceScale / scale,
            shape=visual and visual.runtimeSkin or snapshot.skin or "square", border=snapshot.border or "thin",
            zoom=snapshot.iconZoom or 0.08})
        ghost:SetSize(width * sourceScale / scale, height * sourceScale / scale)
        ghost:SetIconBorderColor(snapshot.borderColor or visual and visual.borderColorOverride)
        self.dragIcon:SetTexture(texture)
        self.dragIcon:SetVertexColor(1, 1, 1, 1)
        self.dragIcon:SetDesaturated(false)
        local icon = visual and visual.icon
        if icon and icon.GetVertexColor then
            local r, g, b, a = icon:GetVertexColor()
            r, g, b, a = security.SafeNumber(r), security.SafeNumber(g), security.SafeNumber(b), security.SafeNumber(a)
            if r and g and b and a then self.dragIcon:SetVertexColor(r, g, b, a) end
        end
        if icon and icon.GetDesaturation and self.dragIcon.SetDesaturation then
            local amount = security.SafeNumber(icon:GetDesaturation())
            if amount then self.dragIcon:SetDesaturation(amount) end
        elseif icon and icon.IsDesaturated then
            self.dragIcon:SetDesaturated(security.SafeBoolean(icon:IsDesaturated()) == true)
        end
        if icon and icon.GetTexCoord then
            local coords, valid = {icon:GetTexCoord()}, true
            for index, value in ipairs(coords) do
                coords[index] = security.SafeNumber(value)
                if coords[index] == nil then valid = false end
            end
            if valid and (#coords == 4 or #coords == 8) then self.dragIcon:SetTexCoord(unpack(coords)) end
        end
        ghost:ClearAllPoints(); ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        ghost:Show(); ghost:StartMoving()
    end
    self.dragButton, self.dragAlpha, self.dragId = button, button:GetAlpha(), id
    button:SetAlpha(0)
    if GameTooltip then GameTooltip:Hide() end
    return true
end

local function DragStart(button)
    if YAB.Adapter:InCombat() or not IsShiftKeyDown() or (YAB.KeybindMode and YAB.KeybindMode.active)
        or (GetCursorInfo and GetCursorInfo() ~= nil) then return end
    local meta = YAB.SecureFactory:GetButtonMeta(button)
    local record = meta and YAB.BarManager.bars[meta.barId]
    if not record or record.classBarEditing then return end
    Tools:BeginDrag(button, meta.barId, meta.classToolKey)
end

local function DragStop(button)
    if Tools.dragButton ~= button then return end
    local meta = YAB.SecureFactory:GetButtonMeta(button)
    local record = meta and YAB.BarManager.bars[meta.barId]
    local target
    if record and not YAB.Adapter:InCombat() then
        for _, candidate in ipairs(Tools:GetLayoutButtons(record)) do
            if candidate ~= button and candidate:IsMouseOver() then target = YAB.SecureFactory:GetButtonMeta(candidate); break end
        end
    end
    Tools:CancelDrag()
    if target then Tools:SwapButtons(meta.barId, meta.classToolKey, target.classToolKey) end
end

local function Hidden(button)
    if Tools.dragButton == button then Tools:CancelDrag() end
    if Tools.dragTarget == button then Tools:SetDragTarget(nil) end
end

-- A distinct native button suffix keeps keyboard modifiers out of mouse settings/drag gestures.
function Tools:PrepareButton(button, id, key)
    local factory = YAB.SecureFactory
    local meta = factory:GetButtonMeta(button) or { barId = id }
    meta.classToolKey = key
    meta.buttonKey = meta.buttonKey or (id .. "." .. key)
    if not meta.commandName and button:GetName() then meta.commandName = "CLICK " .. button:GetName() .. ":Keybind" end
    meta.keybindClickButton = "Keybind"
    factory:SetButtonMeta(button, meta)
    if not meta.classToolHooked then
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", DragStart); button:SetScript("OnDragStop", DragStop)
        button:HookScript("OnHide", Hidden)
        self:PrepareDragFeedback(button)
        if id ~= "mageTools" or not LEGACY_FIELDS[key] then button:HookScript("PostClick", OpenSettings) end
        if YAB.Keybinds and YAB.Keybinds.HookButton then YAB.Keybinds:HookButton(button, meta.buttonKey) end
        meta.classToolHooked = true
    end
    for _, prefix in ipairs({ "alt-", "alt-ctrl-", "alt-shift-", "alt-ctrl-shift-", "shift-", "ctrl-shift-" }) do
        factory:SetSecureAttribute(button, prefix .. "type1", "none")
    end
    for _, attribute in ipairs({ "type", "spell", "item", "macrotext", "action", "unit" }) do
        local value = button:GetAttribute(attribute .. "1")
        if value == nil then value = button:GetAttribute(attribute) end
        factory:SetSecureAttribute(button, "*" .. attribute .. "-Keybind", value)
    end
    local enabled = self:IsButtonEnabled(id, key)
    if not enabled then factory:SetSecureAttribute(button, "*type-Keybind", "none") end
    YAB.BarManager.buttonsByKey[meta.buttonKey] = enabled and button or nil
    return meta.buttonKey
end

function Tools:ReleaseButton(button)
    local factory = YAB.SecureFactory
    local meta = factory:GetButtonMeta(button)
    factory:SetSecureAttribute(button, "*type-Keybind", "none")
    if meta and meta.buttonKey then YAB.BarManager.buttonsByKey[meta.buttonKey] = nil end
end

-- One native owner handles both restricted aura presence and duration. Callers
-- supply only their bounded spell family and a cold-captured public style.
function Tools:ReleaseAuraTimer(entry)
    if entry.auraDisplay then YUI.API.Unit.ReleaseFilteredAuraDisplay(entry.auraDisplay) end
    entry.auraDisplay, entry.timerStyle = nil, nil
end

function Tools:SyncAuraTimer(entry, parent, key, spellIDs, style)
    if YAB.Adapter:InCombat() then return end
    local same = entry.auraDisplay ~= nil and entry.timerStyle ~= nil
    if same then
        for field, value in pairs(style) do if entry.timerStyle[field] ~= value then same = false; break end end
    end
    if same then return end
    self:ReleaseAuraTimer(entry)
    local handle, code = YUI.API.Unit.CreateFilteredAuraDisplay(parent, {
        unit = "player", filter = "HELPFUL", key = key, spellIDs = spellIDs,
        initializeFrame = function(auraFrame) return YAB.Visuals:CreateStatusTimerBindings(auraFrame, style) end,
    })
    entry.auraDisplay, entry.timerStyle, entry.timerIssue = handle, handle and style or nil, code
end

function Tools:AnchorTeamClassCaption(label,button,class,config)
    label:ClearAllPoints()
    label:SetPoint("TOP",button,"TOP",config.teamClassIconOffsetX or 0,-1+(config.teamClassIconOffsetY or 0))
    label.gui2ColorKey=nil
    local color=YUI.API.Unit.GetClassColor(class)
    if color then label:SetTextColor(color.r,color.g,color.b,1) else label:SetTextColor(1,1,1,1) end
    self:StyleText(label)
end

-- Formatting only: native tooltip ownership and secure actions stay with callers.
function Tools:TooltipTitle(tip, title)
    local r, g, b = YUI.GUI2:GetColor("color.tooltip.heading")
    tip:AddLine(title, r, g, b, true)
    tip:AddLine(" ")
end

function Tools:TooltipIconTitle(tip, title, icon)
    if tip.ClearLines then tip:ClearLines() end
    self:TooltipTitle(tip, YUI.GUI2.Tooltip:IconText(title, icon, 18))
end

function Tools:TooltipEffect(tip, text, tone)
    text = YUI.API.Security.SafeString(text)
    if not text or text == "" then return end
    local r, g, b = YUI.GUI2:GetColor("color.tooltip." .. (tone or "success"))
    tip:AddLine(text, r, g, b, true)
    tip:AddLine(" ")
end

function Tools:TooltipEffectText(text, prefix)
    text = YUI.API.Security.SafeString(text)
    if not text then return end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    text = text:gsub("\r\n", "\n")
    if prefix and prefix ~= "" and text:sub(1, #prefix) == prefix then
        text = text:sub(#prefix + 1):match("^%s*(.-)%s*$")
    end
    if text ~= "" then return text end
end

function Tools:CompactItemEffectText(text, prefix)
    text = self:TooltipEffectText(text, prefix)
    if not text then return end
    local line = text:match("^[^\r\n]+")
    if not line then return end
    local sentence = line:find("。", 1, true)
    if sentence then return line:sub(1, sentence + #"。" - 1) end
    sentence = line:find("%.[%s]")
    return sentence and line:sub(1, sentence) or line
end

function Tools:TooltipSpellEffect(tip, spellID, showCastDetails)
    if not spellID then return end
    local spell = YUI.API.Spell
    local text = spell.GetPublicTooltipDescription and self:TooltipEffectText(spell.GetPublicTooltipDescription(spellID))
    if not text and spell.GetPublicDescription then text = self:TooltipEffectText(spell.GetPublicDescription(spellID)) end
    self:TooltipEffect(tip, text, "heading")
    if showCastDetails or not text then self:TooltipCastDetails(tip, spellID) end
end

function Tools:TooltipCastDetails(tip, spellID)
    if not spellID then return end
    local api, locale = YUI.API, YUI.Locale:Get("YActionBar")
    local info = api.Spell.GetInfo(spellID)
    local castTime = info and api.Security.SafeNumber(info.castTime)
    local mana = api.Spell.GetPublicManaCost and api.Spell.GetPublicManaCost(spellID)
    local details = castTime and castTime > 0 and castTime < math.huge
        and string.format(locale["class_tools.travel_cast_time"], (string.format("%.1f", castTime / 1000):gsub("%.0$", ""))) or nil
    if mana and mana > 0 and mana < math.huge then
        local cost = string.format(locale["class_tools.travel_mana"], mana)
        details = details and (cost .. "  ·  " .. details) or cost
    end
    self:TooltipEffect(tip, details, "heading")
end

function Tools:TooltipNativeTitle(tip)
    -- AppendText updates the native heading without reading restricted tooltip lines.
    tip:AppendText("\n ")
end

function Tools:TooltipAction(tip, button, text, icon, reason, modifiers, reasonTone)
    local formatter = YUI.GUI2.Tooltip
    text = formatter:IconText(text, icon)
    if reason then
        text = text .. " " .. formatter:ColorText(reason, reasonTone or "requirement")
    end
    tip:AddLine(formatter:FormatAction({button=button, modifiers=modifiers, text=text,
        keyTone="body", textTone=reason and "secondary" or "heading"}), 1, 1, 1, true)
end

function Tools:SpellUseReason(spellID)
    local api, security = YUI.API.Spell, YUI.API.Security
    if not (spellID and api.GetUsableState) then return end
    local usable, noPower = api.GetUsableState(spellID)
    usable, noPower = security.SafeBoolean(usable), security.SafeBoolean(noPower)
    local locale = YUI.Locale:Get("YActionBar")
    if noPower == true then return locale["class_tools.no_power"] end
    if usable == false then return locale["class_tools.not_usable"] end
    if usable == nil then return locale["class_tools.state_unknown"], "secondary" end
end

function Tools:TooltipSpell(tip, button, spellID, reason, modifiers, reasonTone)
    local api, security = YUI.API.Spell, YUI.API.Security
    local info = spellID and api.GetInfo(spellID)
    local locale = YUI.Locale:Get("YActionBar")
    if spellID and api.GetKnownState(spellID) == false then reason, reasonTone = locale["class_tools.unlearned_suffix"], nil end
    if not reason then reason, reasonTone = self:SpellUseReason(spellID) end
    self:TooltipAction(tip, button, info and security.SafeString(info.name) or locale["class_tools.cast_current"],
        info and (security.SafeNumber(info.originalIconID) or security.SafeNumber(info.iconID)), reason, modifiers, reasonTone)
end

function Tools:TooltipBinding(tip, button)
    local meta = button and YAB.SecureFactory:GetButtonMeta(button)
    if meta and meta.buttonKey and YAB.Keybinds.GetBindingKeysForButton then
        self.tooltipBindingKeys = self.tooltipBindingKeys or {}
        local keys = YAB.Keybinds:GetBindingKeysForButton(meta.buttonKey, 2, self.tooltipBindingKeys)
        if keys and #keys > 0 then
            tip:AddLine(" ")
            tip:AddLine(string.format(YUI.Locale:Get("YActionBar")["class_tools.binding_left"],
                YUI.GUI2.Tooltip:ColorText(table.concat(keys, " / "), "heading")), 1, 1, 1, true)
        end
    end
end

function Tools:TooltipSettings(tip, button)
    if button then self:TooltipBinding(tip, button) end
    tip:AddLine(" ")
    tip:AddLine(YUI.GUI2.Tooltip:FormatAction({button="LeftButton", modifiers={"ALT"}}, true), 1, 1, 1, true)
end

-- All class labels use the same outline and black 1px shadow as button counts.
function Tools:StyleText(text)
    local gui = YUI.GUI2
    if not (text and text.GetFont and gui and gui.ApplyFontAppearance) then return end
    local font, size = text:GetFont()
    if font and size then
        gui:ApplyFontAppearance(text, {font=font, size=size, maxSize=size, outline="outlineShadow"})
    end
end

function Tools:AnchorCaption(text, button, snapshot)
    if not (text and button and text.ClearAllPoints and text.SetPoint) then return end
    text:ClearAllPoints()
    local width = button.GetWidth and button:GetWidth()
    if text.SetWidth and type(width) == "number" and width > 0 then text:SetWidth(math.max(1, width - 2)) end
    local x = tonumber(snapshot and snapshot.travelTextOffsetX) or 0
    local y = tonumber(snapshot and snapshot.travelTextOffsetY) or 0
    text:SetPoint("TOP", button, "TOP", math.max(-64, math.min(64, x)), -1 + math.max(-64, math.min(64, y)))
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if YAB.Visuals and YAB.Visuals.ApplySingleLineTextConstraints then YAB.Visuals:ApplySingleLineTextConstraints(text) end
end

function Tools:IsIndependent(id, db)
    if id == "paladinBlessings" then return true end
    db = db or YAB:GetDB()
    local config = db.specialBars and db.specialBars[id]
    return config and config.classToolsIndependent == true and config.classToolsDetached == true or false
end

function Tools:HasSharedClasses(db)
    db = db or YAB:GetDB()
    for _, id in ipairs(self.ids) do
        if not self:IsIndependent(id, db) then return true end
    end
    return false
end

function Tools:Invalidate()
    for key in pairs(self.cache) do self.cache[key] = nil end
end

function Tools:GetConfig(id, db)
    db = db or YAB:GetDB()
    local own = db.specialBars and db.specialBars[id]
    if not self:IsClassBar(id) or not own or self:IsIndependent(id, db) then return own end
    if self.db ~= db then self.db = db; self:Invalidate() end
    local compiled = self.cache[id]
    if compiled then return compiled end
    compiled = YAB:CopyValue(db.specialBars.classTools or own)
    for key in pairs(OWN_FIELDS) do compiled[key] = YAB:CopyValue(own[key]) end
    if own.classToolsEnabled == false then compiled.enabled = false end
    self.cache[id] = compiled
    return compiled
end

function Tools:GetPlayerBarId()
    return self.classes[YAB.SpecialBars:GetPlayerClassToken()]
end

function Tools:GetPreviewBarId(id, db)
    if id ~= "classTools" then return id end
    db = db or YAB:GetDB()
    local preferred, player = self.classes[self.previewClass], self:GetPlayerBarId()
    if preferred and not self:IsIndependent(preferred, db) then return preferred end
    if player and not self:IsIndependent(player, db) then return player end
    for _, class in ipairs(self.classOrder) do
        local candidate = self.classes[class]
        if not self:IsIndependent(candidate, db) then return candidate end
    end
    return preferred or player or "mageTools"
end

function Tools:GetPreviewConfig(id, db)
    return self:GetConfig(self:GetPreviewBarId(id, db), db)
end

function Tools:GetSettingsBarId(id, db)
    db = db or YAB:GetDB()
    if not self:IsClassBar(id) then return id end
    return self:IsIndependent(id, db) and id or "classTools"
end

function Tools:GetLayoutId(id, db)
    return "yactionbar." .. self:GetSettingsBarId(id, db)
end

function Tools:SetIndependent(id, independent)
    if id == "paladinBlessings" then return false end
    if not self:IsClassBar(id) or YAB.Adapter:InCombat() then return false end
    local db = YAB:GetDB()
    local own = db.specialBars[id]
    independent = independent == true
    if self:IsIndependent(id, db) == independent then return true end
    if independent and not own.classToolsInitialized then
        for key, value in pairs(db.specialBars.classTools) do
            if not OWN_FIELDS[key] then own[key] = YAB:CopyValue(value) end
        end
        own.classToolsInitialized = true
        if YAB.ConfigSets and YAB.ConfigSets.CopyClassToolsPlacement then
            YAB.ConfigSets:CopyClassToolsPlacement("yactionbar.classTools", "yactionbar." .. id)
        end
    end
    if independent then
        own.enabled = own.classToolsEnabled ~= false
    else
        own.classToolsEnabled = own.enabled ~= false
    end
    own.classToolsIndependent = independent
    own.classToolsDetached = independent
    self:Invalidate()
    local record = YAB.BarManager and YAB.BarManager.bars[id]
    if record and YAB.LayoutBridge and YAB.ClassBars.active[id] then
        YAB.LayoutBridge:Register(id, record, nil, self:GetConfig(id, db))
    end
    if YAB.ClassBars then YAB.ClassBars:SyncEnabled(id) end
    if YAB.ConfigSets then YAB.ConfigSets:SaveActive("class-tools-mode", self) end
    return true
end

function Tools:SelectClass(class, db)
    local id = self.classes[class]
    if not id then return nil end
    self.previewClass = class
    return self:GetSettingsBarId(id, db)
end

function Tools:GetSettingsOrder(order, db)
    local result = {}
    for _, id in ipairs(order) do
        if id == "classTools" then
            if self:HasSharedClasses(db) then result[#result + 1] = id end
        elseif not self:IsClassBar(id) or self:IsIndependent(id, db) then
            result[#result + 1] = id
        end
    end
    return result
end
