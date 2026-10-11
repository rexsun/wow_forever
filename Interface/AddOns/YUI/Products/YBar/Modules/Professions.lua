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

-- 文档
-- 1. 采矿专精左键行为改为直接打开【熔炼】专业面板。
-- 2. 其他专业仍然保持原有的左键打开对应专业面板、右键弹出专业列表。
-- 3. Alt + 左键继续打开模块设置。

function Module:OnInitialize()
    self.frame = nil
    self.buttons = {}
end

local function ShowProfessionMenu(anchor)
    local allProfs = {}
    local p1, p2, p3, p4, p5, p6, p7 = API.GetProfessions()
    local profs = {p1, p2, p3, p4, p5, p6, p7}

    for i = 1, (YUI.IsForever and 7 or 6) do
        local index = profs[i]
        if index then
            local skillLine, name, skillLevel, maxSkillLevel, icon, extraSpellId = API.GetProfessionInfo(index)
            if name then
                local castName = API.GetOpenName(name, skillLine, extraSpellId, true)
                local menuItem = {
                    icon = icon,
                    text = name,
                    rText = string.format("    |cff%s%d / %d|r", skillLevel >= maxSkillLevel and "00ff00" or "ff0000", skillLevel, maxSkillLevel),
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
        YBar:CreatePopIconMenu(anchor, allProfs, {columns = 1, colWidth = 200, iconSize = 24, fontSize = 16, itemHeight = 32, gui2 = true})
    end
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
        GameTooltip:AddLine(string.format("|c%s%s|r |cff%s(%d/%d)|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, owner.info.name, owner.info.skillLevel >= owner.info.maxSkillLevel and "00ff00" or "ff0000", owner.info.skillLevel, owner.info.maxSkillLevel), 1, 1, 1)
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
    YUI.Event:OffOwner(self)
    if self.frame then
        self.frame.updatePending = false
        self.frame:Hide()
    end

    self.needsUpdate = false

    if YBar and YBar.PopIconMenu then
        YBar.PopIconMenu:Hide()
    end

    if GameTooltip and GameTooltip.GetOwner and IsProfessionTooltipOwner(GameTooltip:GetOwner()) then
        YUI.HideGameTooltip()
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
