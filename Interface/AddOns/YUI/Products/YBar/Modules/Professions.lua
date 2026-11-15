local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Professions") end
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end
local GUI2 = YUI.GUI2
local YBar = YUI.YBar
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local LegacyAPI = YUI.WOW_API
local API = YUI.API and YUI.API.Profession or LegacyAPI
local SecurityAPI = (YUI.API and YUI.API.Security) or LegacyAPI
local ItemAPI = YUI.API and YUI.API.Item
local SpellAPI = YUI.API and YUI.API.Spell
local Module = YBar.Module:New("Professions")

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

-- 默认常量
local DEFAULT_SIZE = 14
local DEFAULT_SPACING = 5
local DEFAULT_FONT = STANDARD_TEXT_FONT
local MENU_MIN_WIDTH = 240
local MENU_PADDING = 8
local MENU_TEXT_INSET = 72 -- outer padding, icon and the gaps between both text columns

local function SafeNumber(value)
    if SecurityAPI.SafeNumber then return SecurityAPI.SafeNumber(value) end
    if (SecurityAPI.IsSecretValue and SecurityAPI.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value)) then return nil end
    return type(value) == "number" and value or nil
end

local function Colored(text, token)
    local r, g, b = GUI2:GetColor(token)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + .5),
        math.floor(g * 255 + .5), math.floor(b * 255 + .5), text)
end

local function RankText(rank, maximum)
    rank, maximum = SafeNumber(rank), SafeNumber(maximum)
    return Colored(rank and tostring(rank) or "--", rank and maximum and maximum > 0 and rank >= maximum
        and "color.state.success" or "color.text.primary")
        .. " " .. Colored("/ " .. (maximum and tostring(maximum) or "--"), "color.text.secondary")
end

-- 文档
-- 1. 采矿专精左键行为改为直接打开【熔炼】专业面板。
-- 2. 其他专业仍然保持原有的左键打开对应专业面板、右键弹出专业列表。
-- 3. Alt + 左键继续打开模块设置。

function Module:OnInitialize()
    self.frame = nil
    self.buttons = {}
    self.menuOwner, self.menuCleanupOwner = {}, {}
end

local function ShowProfessionMenu(anchor)
    if SecurityAPI.InCombatLockdown() then return end
    local allProfs = {}
    local cooking, enchanting = false, false
    local p1, p2, p3, p4, p5, p6, p7 = API.GetProfessions()
    local profs = {p1, p2, p3, p4, p5, p6, p7}

    for i = 1, (YUI.IsForever and 7 or 6) do
        local index = profs[i]
        if index then
            local skillLine, name, skillLevel, maxSkillLevel, icon, extraSpellId = API.GetProfessionInfo(index)
            if name then
                skillLine = SafeNumber(skillLine)
                if skillLine == 185 then cooking = true end
                if skillLine == 333 then enchanting = true end
                local castName = API.GetOpenName(name, skillLine, extraSpellId, true)
                local menuItem = {
                    icon = icon,
                    text = name,
                    rText = RankText(skillLevel, maxSkillLevel),
                    key = "profession:" .. tostring(skillLine or index),
                    kind = "profession",
                }

                if YUI.IsForever then
                    local spellID = API.GetProfessionSpellID(index)
                    menuItem.action = spellID and {kind = "spell", spellID = spellID} or {kind = "noop"}
                elseif YUI.IsRetail then
                    menuItem.action = {
                        kind = "custom",
                        onClick = function()
                            API.ToggleProfessionFrame(castName, skillLine)
                        end,
                    }
                elseif castName and castName ~= "" then
                    menuItem.action = {
                        kind = "macro",
                        macrotext = "/cast " .. castName,
                    }
                end

                table.insert(allProfs, menuItem)
            end
        end
    end

    if #allProfs > 0 then
        if YUI.IsForever then
            Module:ShowForeverMenu(anchor, allProfs, cooking, enchanting)
        else
            YBar:CreatePopIconMenu(anchor, allProfs, {columns = 1, colWidth = 200, iconSize = 24, fontSize = 16, itemHeight = 32, gui2 = true})
        end
    elseif YUI.IsForever then
        Module:HideForeverMenu()
    end
end

local function AssistantAvailable()
    local assistant = YUI.ProfessionAssistant
    return assistant and type(assistant.IsAvailable) == "function" and type(assistant.Open) == "function"
        and assistant:IsAvailable() or false
end

local function WriteText(region, value)
    if region.professionText ~= value then region.professionText = value; region:SetText(value); return true end
    return false
end

local function MenuTooltipKey(row, state)
    return row.kind .. ":" .. row.text .. ":" .. (row.rText or "") .. ":" .. tostring(row.disabled)
        .. (row.kind == "craft" and (":" .. tostring(state.tools) .. ":" .. tostring(state.recipeLearned)) or "")
end

function Module:HideForeverMenu()
    if self.professionMenu and not SecurityAPI.InCombatLockdown() then self.professionMenu:Hide() end
end

function Module:CancelMenuRefresh()
    if self.menuTimer then self.menuTimer:Cancel(); self.menuTimer = nil end
end

function Module:ScheduleMenuRefresh()
    if not self.runtimeAttached or not self.professionMenu or not self.professionMenu:IsShown()
        or SecurityAPI.InCombatLockdown() or self.menuTimer then return end
    self.menuTimer = C_Timer.NewTimer(.05, function()
        self.menuTimer = nil
        if self.runtimeAttached and self.professionMenu:IsShown() and not SecurityAPI.InCombatLockdown() then
            ShowProfessionMenu(self.menuAnchor)
        end
    end)
end

function Module:OnMenuEnter(host, owner)
    local row = owner.professionRow
    if not row or not self.runtimeAttached then return end
    self.menuTooltipButton = owner
    self.menuTooltipKey = MenuTooltipKey(row, self.campfireState)
    GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(row.text, 1, 1, 1)
    local errorR, errorG, errorB = GUI2:GetColor("color.state.error")
    if row.kind == "craft" then
        local state = self.campfireState
        GameTooltip:AddLine(T("professions.forever.wood_format", "普通木柴 %s / %d", state.wood or "--", state.required), 1, 1, 1)
        GameTooltip:AddLine(T("professions.forever.tool_format", "燧石和火绒：%s", state.tools == nil and "--" or state.tools > 0
            and T("professions.forever.owned", "已持有") or T("professions.forever.missing", "未持有")), 1, 1, 1)
        if not row.disabled then
            GameTooltip:AddLine(T("professions.forever.craft_hint", "可制造 %d 个；点击制造 1 个", math.floor(state.wood / state.required)), 1, 1, 1)
        else
            GameTooltip:AddLine(T("professions.forever.craft_unavailable", "材料或工具不足，或配方尚不可用。"), errorR, errorG, errorB)
        end
    elseif row.kind == "use" then
        GameTooltip:AddLine(T("professions.forever.use_hint", "使用背包中的基础营火工具包。"), 1, 1, 1)
        if row.disabled then GameTooltip:AddLine(T("professions.forever.no_kits", "背包中没有可用的营火工具包。"), errorR, errorG, errorB) end
    elseif row.kind == "assistant" then
        GameTooltip:AddLine(T("professions.forever.assistant_hint", "打开现有分解助手。"), 1, 1, 1)
    else
        GameTooltip:AddLine(row.rText, 1, 1, 1)
    end
    GameTooltip:Show()
end

function Module:EnsureProfessionMenu()
    if not self.professionMenu then
        local menu = GUI2:CreatePanel(UIParent, {template = "BackdropTemplate,SecureHandlerStateTemplate",
            width = MENU_MIN_WIDTH, height = 40, surface = "color.surface.popup", border = "color.popup.border", shadow = true})
        self.professionMenu = menu
        menu.buttons = {}
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetClampedToScreen(true)
        menu:SetAttribute("_onstate-visibility", [[if newstate == "hide" then self:Hide() end]])
        menu.divider = YBar:CreateThemedTexture(menu, {colorKey = "color.border.subtle"})
        menu.divider:SetSize(MENU_MIN_WIDTH - 20, 1)
        menu.closer = GUI2:CreateButtonFrame(UIParent)
        menu.closer:SetFrameStrata("FULLSCREEN_DIALOG")
        menu.closer:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
        menu.closer:SetAllPoints(UIParent)
        menu.closer:RegisterForClicks("AnyUp")
        menu.closer:SetScript("OnClick", function() self:HideForeverMenu() end)
        menu:SetScript("OnHide", function()
            self:CancelMenuRefresh()
            YUI.Event:OffOwner(self.menuOwner)
            self.menuListeners = 0
            self.menuTooltipButton, self.menuTooltipKey = nil, nil
            menu.closer:Hide()
            YUI.HideGameTooltip()
        end)
        menu:Hide()
    end
    if not self.menuDriver then
        RegisterStateDriver(self.professionMenu, "visibility", "[combat] hide; 0")
        self.menuDriver = true
    end
    return self.professionMenu
end

function Module:CreateProfessionMenuRow(menu)
    local button = GUI2:CreateFrame(menu, {template = "BackdropTemplate"})
    GUI2:ApplyBackdrop(button, "color.surface.popup")
    GUI2:CreateBorder(button, "color.border.subtle")
    button.iconSlot, button.icon = YBar:CreateIconSlot(button, {size = 28, padding = 0, shape = "square", variant = "surface"})
    button.iconSlot:EnableMouse(false)
    button.iconSlot:SetPoint("LEFT", button, "LEFT", 5, 0)
    button.text = YBar:CreateThemedText(button, {fontPath = DEFAULT_FONT, fontSize = 16, wordWrap = false, colorKey = "color.text.primary", justifyH = "LEFT"})
    button.text:SetPoint("LEFT", button.iconSlot, "RIGHT", 9, 0)
    button.rText = YBar:CreateThemedText(button, {fontPath = DEFAULT_FONT, fontSize = 15, wordWrap = false, colorKey = "color.text.secondary", justifyH = "RIGHT"})
    button.rText:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.text:SetPoint("RIGHT", button.rText, "LEFT", -6, 0)
    YBar:CreateActionHost(button, {
        useOnKeyDown = false,
        onEnter = function(host, owner)
            if owner.SetBackdropColor then owner:SetBackdropColor(GUI2:GetColor("color.control.hover")) end
            self:OnMenuEnter(host, owner)
        end,
        onLeave = function(_, owner)
            if owner.SetBackdropColor then owner:SetBackdropColor(GUI2:GetColor("color.surface.popup")) end
            self.menuTooltipButton, self.menuTooltipKey = nil, nil
            YUI.HideGameTooltip()
        end,
        afterClick = function(_, mouseButton, owner)
            if mouseButton ~= "LeftButton" then return end
            local row = owner.professionRow
            if row.disabled then return end
            if row.kind == "profession" or row.kind == "assistant" or row.kind == "craft" then self:HideForeverMenu()
            else self:ScheduleMenuRefresh() end
        end,
    })
    return button
end

function Module:ShowForeverMenu(anchor, professions, cooking, enchanting)
    if not self.runtimeAttached or SecurityAPI.InCombatLockdown() then return end
    self.menuOwner = self.menuOwner or {}
    self.menuCleanupOwner = self.menuCleanupOwner or {}
    local rows = {}
    if cooking then
        self.campfireState = API.ReadCampfire(self.campfireState)
        local state = self.campfireState
        if state then
            local craftAction = API.GetCampfireCraftAction()
            rows[#rows + 1] = {key = "craft", kind = "craft", text = T("professions.forever.craft", "制造营火"), icon = 135805,
                rText = T("professions.forever.wood_short", "木柴 %s / %d", state.wood == nil and "--"
                    or Colored(tostring(state.wood), state.wood < state.required and "color.state.error" or "color.text.primary"), state.required),
                disabled = not state.canCraft or not craftAction,
                action = craftAction}
            rows[#rows + 1] = {key = "use", kind = "use", text = T("professions.forever.use", "使用营火"),
                icon = SafeNumber(ItemAPI.GetIcon(state.itemID)) or 7808148,
                rText = T("professions.forever.kits", "持有 %s", state.kits or "--"),
                disabled = state.kits == nil or state.kits < 1,
                -- SecureCmdItemParse treats an unprefixed number as an equipment slot.
                action = {kind = "item", item = "item:" .. state.itemID}}
        end
    end
    if enchanting and AssistantAvailable() then
        rows[#rows + 1] = {key = "assistant", kind = "assistant", text = T("professions.forever.assistant", "分解助手"),
            icon = SpellAPI.GetTexture(13262), rText = T("professions.forever.open", "打开"),
            action = {kind = "custom", onClick = function()
                if self.runtimeAttached and AssistantAvailable() then YUI.ProfessionAssistant:Open() end
            end}}
    end
    local quickCount = #rows
    for _, row in ipairs(professions) do rows[#rows + 1] = row end
    local menu = self:EnsureProfessionMenu()
    local y = 8
    local width = MENU_MIN_WIDTH
    for i, row in ipairs(rows) do
        if quickCount > 0 and i == quickCount + 1 then
            if menu.dividerY ~= y then
                menu.dividerY = y
                menu.divider:ClearAllPoints(); menu.divider:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -y - 4)
            end
            y = y + 14
        end
        local button = menu.buttons[i]
        if not button then button = self:CreateProfessionMenuRow(menu); menu.buttons[i] = button end
        local height = i <= quickCount and 40 or 38
        if button.rowY ~= y or button.rowHeight ~= height then
            button.rowY, button.rowHeight = y, height
            button.rowWidth = button.rowWidth or MENU_MIN_WIDTH - MENU_PADDING * 2
            button:SetSize(button.rowWidth, height); button:ClearAllPoints()
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -y)
        end
        button.professionRow = row
        local text = row.disabled and Colored(row.text, "color.text.disabled") or row.text
        local textChanged = WriteText(button.text, text)
        local valueChanged = WriteText(button.rText, row.rText or "")
        if textChanged or valueChanged or not button.contentWidth then
            button.contentWidth = math.ceil(button.text:GetStringWidth() + button.rText:GetStringWidth() + MENU_TEXT_INSET)
        end
        width = math.max(width, button.contentWidth)
        if button.rowIcon ~= row.icon then button.rowIcon = row.icon; YBar:SetIconSlotTexture(button.iconSlot, row.icon) end
        if button.rowDisabled ~= not not row.disabled then
            button.rowDisabled = not not row.disabled
            button.icon:SetDesaturated(button.rowDisabled)
        end
        local action = row.action
        local actionKey = row.key .. ":" .. tostring(row.disabled) .. ":" .. tostring(action and action.kind)
            .. ":" .. tostring(action and (action.spellID or action.item or action.macrotext))
        if button.actionKey ~= actionKey then
            local applied = button.actionHost:SetActions({left = row.disabled and {kind = "noop"} or row.action})
            if not applied then self:HideForeverMenu(); return end
            button.actionKey = actionKey
        end
        if not button:IsShown() then button:Show() end
        y = y + height + 4
    end
    for i = #rows + 1, #menu.buttons do if menu.buttons[i]:IsShown() then menu.buttons[i]:Hide() end end
    for i = 1, #rows do
        local button = menu.buttons[i]
        if button.rowWidth ~= width - MENU_PADDING * 2 then
            button.rowWidth = width - MENU_PADDING * 2
            button:SetWidth(button.rowWidth)
        end
    end
    if menu:GetWidth() ~= width then menu:SetWidth(width); menu.divider:SetWidth(width - 20) end
    local height = y + 4
    if menu:GetHeight() ~= height then menu:SetHeight(height) end
    if quickCount > 0 then if not menu.divider:IsShown() then menu.divider:Show() end
    elseif menu.divider:IsShown() then menu.divider:Hide() end
    local _, anchorY = anchor:GetCenter()
    local above = not anchorY or anchorY <= UIParent:GetHeight() / 2
    if self.menuAnchor ~= anchor or menu.above ~= above then
        menu:ClearAllPoints()
        menu:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", anchor, above and "TOPLEFT" or "BOTTOMLEFT", 0, above and 2 or -2)
        menu.above = above
        self.menuAnchor = anchor
    end
    if not menu:IsShown() then
        YUI.Event:OffOwner(self.menuOwner)
        local refresh = function(_, id)
            if id == nil or id == "component.professionassistant" or type(id) ~= "string" then self:ScheduleMenuRefresh() end
        end
        for _, event in ipairs({"BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "GET_ITEM_INFO_RECEIVED",
            "YUI_MODULE_ENABLED", "YUI_MODULE_DISABLED"}) do
            YUI.Event:On(event, (event == "YUI_MODULE_ENABLED" or event == "YUI_MODULE_DISABLED") and refresh
                or function() self:ScheduleMenuRefresh() end, self.menuOwner)
        end
        self.menuListeners = 6
        menu.closer:Show(); menu:Show()
    end
    local tooltipButton = self.menuTooltipButton
    if tooltipButton and GameTooltip:GetOwner() == tooltipButton.actionHost then
        if not tooltipButton:IsShown() then
            self.menuTooltipButton, self.menuTooltipKey = nil, nil
            YUI.HideGameTooltip()
        elseif self.menuTooltipKey ~= MenuTooltipKey(tooltipButton.professionRow, self.campfireState) then
            self:OnMenuEnter(tooltipButton.actionHost, tooltipButton)
        end
    end
end

function Module:FinishProfessionMenuCleanup()
    if SecurityAPI.InCombatLockdown() then return end
    YUI.Event:OffOwner(self.menuCleanupOwner)
    if self.runtimeAttached then return end
    self:HideForeverMenu()
    if self.menuDriver then UnregisterStateDriver(self.professionMenu, "visibility"); self.menuDriver = nil end
    if self.frame then self.frame:Hide() end
end

function Module:GetStats()
    return {menuButtons = self.professionMenu and #self.professionMenu.buttons or 0,
        menuListeners = self.menuListeners or 0, menuTimers = self.menuTimer and 1 or 0,
        refreshTimers = self.refreshTimer and 1 or 0, menuDriver = self.menuDriver == true}
end

local function ConfigureProfessionActions(btn, info, preferExtraSpell)
    if not btn or not btn.actionHost then return end

    if not YUI.IsRetail and SecurityAPI.InCombatLockdown() then
        Module.needsUpdate = true
        return
    end

    local actions = {
        altLeft = {
            kind = "custom",
            onClick = function(_, _, owner)
                YUI:OpenYBarModuleSettings("Professions")
            end,
        },
        right = {
            kind = "custom",
            onClick = function(_, _, owner)
                ShowProfessionMenu(owner)
            end,
        },
    }

    if YUI.IsForever then
        local spellID = info and API.GetProfessionSpellID(info.index)
        actions.left = spellID and {kind = "spell", spellID = spellID} or {kind = "noop"}
    elseif YUI.IsRetail then
        actions.left = {
            kind = "custom",
            onClick = function(_, _, owner)
                if not owner or not owner.info then return end
                local professionName = owner.info.name or ""
                local castName = API.GetOpenName(professionName, owner.info.skillLine, owner.info.extraSpellId, false)
                API.ToggleProfessionFrame(castName, owner.info.skillLine)
            end,
        }
    else
        local castName = info and API.GetOpenName(info.name, info.skillLine, info.extraSpellId, preferExtraSpell)
        if castName and castName ~= "" then
            actions.left = {
                kind = "macro",
                macrotext = "/cast " .. castName,
            }
        else
            actions.left = { kind = "noop" }
        end
    end

    local ok = btn.actionHost:SetActions(actions)
    if not ok then
        Module.needsUpdate = true
    end
end

local function ProfessionButtonOnEnter(host, owner)
    owner = owner or host
    if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(owner:GetParent()) end
    local tooltipAnchor = "ANCHOR_TOP"
    local bar = Module.parent

    if bar and bar:GetBottom() > GetScreenHeight() / 2 then
        tooltipAnchor = "ANCHOR_BOTTOM"
    end

    if owner.info and owner.info.skillLine then
        GameTooltip:SetOwner(host, tooltipAnchor)
        GameTooltip:AddLine(string.format("|c%s%s|r (%s)", YBar.Colors_Hex.HEADER_TEXT_COLOR, owner.info.name,
            RankText(owner.info.skillLevel, owner.info.maxSkillLevel)), 1, 1, 1)
        GameTooltip:AddLine(" ")

        local headerColor = CreateColor(1, 0.82, 0)
        local headerHex = headerColor:GenerateHexColor()
        local white = "|cffffffff"
        local gold = "|c" .. headerHex

        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("professions.action.open_profession", "打开%s", owner.info.name)))
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("professions.action.open_all", "打开所有专业")))
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
        GameTooltip:Show()
    else
        GameTooltip:SetOwner(host, tooltipAnchor)
        GameTooltip:AddLine(T("professions.tooltip.unlearned", "尚未学习 %s", owner.info and owner.info.name or ""), 1, 1, 1)
        GameTooltip:Show()
    end

    -- 文本高亮为当前 GUI2 accent token
    if owner.text then YBar:SetThemedTextAccent(owner.text) end
end

local function ProfessionButtonOnLeave(host, owner)
    owner = owner or host
    if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(owner:GetParent()) end
    YUI.HideGameTooltip()
    if owner.text then YBar:RestoreThemedTextColor(owner.text, "color.ybar.text") end
end

local function CreateProfessionButton(parent, index)
    -- 初始值（将在 UpdateProfessions 中更新）
    local size = DEFAULT_SIZE
    local iconSize = size + 2

    local btn = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = iconSize + 4 + 120,
        height = size + 6,
        showIcon = true,
        iconSize = iconSize,
        iconShape = "square",
        iconPadding = 0,
        iconLeftPadding = 0,
        hoverIcon = false,
        text = "",
        value = false,
        textColorKey = "color.ybar.text",
        textRightPadding = 0,
        gap = 4,
    })
    
    btn:SetHeight(size + 6)
    btn:SetPoint("CENTER", 0, 0)

    -- 图标
    if btn.iconSlot then
        btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
    else
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    end

    -- 文本
    btn.text:SetFont(DEFAULT_FONT, size, "")
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetShadowOffset(1, -1)
    btn.text:ClearAllPoints()
    btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 4, 0)
    btn.text:SetJustifyH("LEFT")

    YBar:CreateActionHost(btn, {
        onEnter = ProfessionButtonOnEnter,
        onLeave = ProfessionButtonOnLeave,
    })

    return btn
end

local function IsProfessionTooltipOwner(owner)
    if not owner then return false end
    if owner == Module.frame then return true end
    if Module.buttons then
        for _, btn in ipairs(Module.buttons) do
            if owner == btn or owner == btn.actionHost then return true end
        end
    end
    return false
end

local function ProfessionsOnEvent(event)
    local frame = Module.frame
    if not frame or not Module.runtimeAttached then return end

    if event == "YUI_WORLD_READY" then
        Module:UpdateBarItem(frame)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Module.needsUpdate then
            Module.needsUpdate = false
            Module:UpdateBarItem(frame)
        end
    else
        if not Module.refreshTimer then
            frame.updatePending = true
            Module.refreshTimer = C_Timer.NewTimer(1, function()
                Module.refreshTimer = nil
                frame.updatePending = false
                if not Module.runtimeAttached or Module.frame ~= frame then return end
                if YBar and YBar.IsSubModuleEnabled and not YBar:IsSubModuleEnabled(Module.name) then
                    return
                end
                Module:UpdateBarItem(frame)
            end)
        end
    end
end

function Module:AttachRuntime()
    if not self.frame then return end
    self.menuOwner = self.menuOwner or {}
    self.menuCleanupOwner = self.menuCleanupOwner or {}
    YUI.Event:OffOwner(self.menuCleanupOwner)
    self.runtimeAttached = true
    YUI.Event:OffOwner(self)
    YUI.Event:On("YUI_WORLD_READY", ProfessionsOnEvent, self)
    YUI.Event:On("SKILL_LINES_CHANGED", ProfessionsOnEvent, self)
    YUI.Event:On("CHAT_MSG_SKILL", ProfessionsOnEvent, self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", ProfessionsOnEvent, self)
    if YUI.IsForever then YUI.Event:On("SPELLS_CHANGED", ProfessionsOnEvent, self) end

    self:UpdateBarItem(self.frame, self.parent)
end

function Module:DetachRuntime()
    self.runtimeAttached = false
    if self.refreshTimer then self.refreshTimer:Cancel(); self.refreshTimer = nil end
    self:CancelMenuRefresh()
    YUI.Event:OffOwner(self)
    if self.menuOwner then YUI.Event:OffOwner(self.menuOwner) end
    self.menuListeners = 0
    self:HideForeverMenu()
    if self.frame then
        self.frame.updatePending = false
        if not SecurityAPI.InCombatLockdown() then self.frame:Hide() end
    end

    self.needsUpdate = false

    if YBar and YBar.PopIconMenu and not SecurityAPI.InCombatLockdown() then
        YBar.PopIconMenu:Hide()
    end

    if GameTooltip and GameTooltip.GetOwner and IsProfessionTooltipOwner(GameTooltip:GetOwner()) then
        YUI.HideGameTooltip()
    end
    self.menuCleanupOwner = self.menuCleanupOwner or {}
    if SecurityAPI.InCombatLockdown() then
        YUI.Event:On("PLAYER_REGEN_ENABLED", function() self:FinishProfessionMenuCleanup() end, self.menuCleanupOwner)
    else
        self:FinishProfessionMenuCleanup()
    end
end

function Module:UpdateProfessions(skipLayout)
    if not self.buttons or #self.buttons == 0 then return end

    if SecurityAPI.InCombatLockdown() then
        self.needsUpdate = true
        return
    end
    
    -- 加载设置
    local db = GetYBarDB().Professions or {}
    local size = db.size or DEFAULT_SIZE
    local iconSize = size + 2    
    local spacing = db.spacing or DEFAULT_SPACING
    local font = db.font
    local fontPath = YBar:ResolveFontPath(font, DEFAULT_FONT)
    local prof1, prof2 = API.GetProfessions()
    local professions = {prof1 or -1, prof2 or -1}

    local prev = nil
    local totalWidth = 0
    
    for i, index in ipairs(professions) do
        local btn = self.buttons[i]
        local skillLine, name, skillLevel, maxSkillLevel, icon, extraSpellId
        
        local displayName = nil
        if index ~= -1 then
            skillLine, name, skillLevel, maxSkillLevel, icon, extraSpellId = API.GetProfessionInfo(index)
            name = name or T("professions.unknown", "未知专业")
        else
            name, icon, skillLevel, maxSkillLevel, skillLine, extraSpellId = "|c"
                .. YBar.Colors_Hex.INACTIVE_ZONE_COLOR
                .. T("professions.empty_slot_format", "专业%d", i)
                .. "|r", 134940, nil, nil, nil, nil
        end
        
        btn.info = {
            index = index ~= -1 and index or nil,
            name = name,
            displayName = displayName or name,
            icon = icon,
            skillLevel = skillLevel,
            maxSkillLevel = maxSkillLevel,
            skillLine = skillLine,
            extraSpellId = extraSpellId
        }
        ConfigureProfessionActions(btn, btn.info, false)

        -- 更新样式
        btn:SetHeight(size + 6)
        if btn.actionHost and btn.actionHost.SetActionHostFrameLevel then
            btn.actionHost:SetActionHostFrameLevel()
        end
        if btn.iconSlot then
            btn.iconSlot:SetSize(iconSize, iconSize)
            btn.iconSlot:ClearAllPoints()
            btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
        else
            btn.icon:SetSize(iconSize, iconSize)
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
        end
        local globalDB = GetYBarDB() or {}
        local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")
        
        btn.text:SetFont(fontPath, size, fontFlag)
        -- 设置文字阴影
        if globalDB.fontShadow then
            btn.text:SetShadowColor(0, 0, 0, 1)
            btn.text:SetShadowOffset(1, -1)
        else
            btn.text:SetShadowOffset(0, 0)
        end
        btn.text:ClearAllPoints()
        btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 4, 0)
        btn.icon:SetTexture(icon)
        btn.text:SetText(btn.info.displayName or name)

        -- 计算宽度
        local textWidth = btn.text:GetStringWidth()
        local btnWidth = iconSize + 4 + textWidth
        btn:SetWidth(btnWidth)
        btn:Show()
        
        -- 定位
        btn:ClearAllPoints()
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", spacing * 2, 0) -- Spacing setting
        else
            btn:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
        end
        
        prev = btn
        totalWidth = totalWidth + btnWidth + (prev and (spacing * 2) or 0)
    end
    
    -- 重新计算精确总宽度
    totalWidth = 0
    local visibleCount = 0
    for i = 1, 2 do
        if self.buttons[i] and self.buttons[i]:IsShown() then
            if visibleCount > 0 then
                totalWidth = totalWidth + (spacing * 2)
            end
            totalWidth = totalWidth + self.buttons[i]:GetWidth()
            visibleCount = visibleCount + 1
        end
    end
    
    if self.frame then
        if not SecurityAPI.InCombatLockdown() then
            self.frame:SetWidth(totalWidth > 0 and totalWidth or 10) -- 最小宽度 10 以避免问题
            self.frame:SetHeight(size + 6)
        else
            self.needsUpdate = true
        end
    end
    
    if not skipLayout and YBar and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
end

function Module:CreateBarItem(parent)
    if self.refreshTimer then self.refreshTimer:Cancel(); self.refreshTimer = nil end
    local container = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })
    
    -- 清理现有按钮逻辑（因创建新容器）
    self.buttons = {}

    -- 创建 2 个按钮
    for i = 1, 2 do
        local btn = CreateProfessionButton(container, i)
        table.insert(self.buttons, btn)
    end
    
    self.frame = container
    container:HookScript("OnHide", function() self:HideForeverMenu() end)
    
    -- Events are attached by the lifecycle runtime.
    -- 移除 TRADE_SKILL_LIST_UPDATE，因为打开/操作专业窗口时触发过于频繁
    
    -- 初始更新
    self:UpdateBarItem(container, parent)

    if YBar and YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end
    
    return container
end

function Module:UpdateBarItem(frame, parent)
    if parent then
        self.parent = parent
    end
    if not frame then return end
    self:UpdateProfessions(true) -- 跳过布局更新，因为可能正在布局更新中
end

function Module:GetWidth()
    if self.frame then
        return self.frame:GetWidth()
    end
    return 10
end

YBar:RegisterModule(Module, {
    id = "ybar.professions",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api"},
    defaultEnabled = true,
})

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")
    local Locale = YUI.Locale
    local CoreL = Locale and Locale:Get("Core") or {}
    
    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)
    
    local options = {
        {
            type = "dropdown",
            label = CoreL["common.font"] or "Font",
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return GetYBarDB().Professions and GetYBarDB().Professions.font or defaultFont end,
            set = function(val)
                if not GetYBarDB().Professions then GetYBarDB().Professions = {} end
                GetYBarDB().Professions.font = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = CoreL["common.size"] or "Size",
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return GetYBarDB().Professions and GetYBarDB().Professions.size or DEFAULT_SIZE end,
            set = function(val)
                if not GetYBarDB().Professions then GetYBarDB().Professions = {} end
                GetYBarDB().Professions.size = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = CoreL["common.spacing"] or "Spacing",
            width = 220,
            min = 0, max = 50, step = 1,
            get = function() return GetYBarDB().Professions and GetYBarDB().Professions.spacing or DEFAULT_SPACING end,
            set = function(val)
                if not GetYBarDB().Professions then GetYBarDB().Professions = {} end
                GetYBarDB().Professions.spacing = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        }
    }
    return options
end
