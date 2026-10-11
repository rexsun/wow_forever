local YUI = _G.YUI
local YBar = YUI.YBar
local Info = YBar.InfoModule
local Talent = YUI.API.Talent
local Security = YUI.API.Security
local Combat = YUI.API.Combat
local WeaponSkill = YUI.API.WeaponSkill
local Frame = YUI.API.Frame
local GUI = YUI.GUI2
local Tooltip = GUI.Tooltip
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local Module = YBar.Module:New("Talents")

local TrainingTitles = {
    ["Coming Soon"] = true, ["即将学习"] = true, ["即將可以訓練"] = true,
    ["Bientôt disponible"] = true, ["Скоро будет"] = true,
    ["Demnächst"] = true, ["곧 사용 가능"] = true,
}
local AvailableTrainingTitles = {
    ["Available Now"] = true, ["可学"] = true, ["現在可以訓練"] = true,
    ["Disponible"] = true, ["Доступен сейчас"] = true,
    ["Jetzt verfügbar"] = true, ["지금 사용 가능"] = true,
}

local function TrainingText(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "string"
        and #value <= 4096 and not value:find("[%c]")
end

-- 使用稳定的收集器；外部回调可以保留它，但不能接管真实提示框或保留技能列表。
local TrainingSink = {}
function TrainingSink:IsShown() return false end
function TrainingSink:AddLine(left)
    if not self.lines then return end
    if not TrainingText(left) or #self.lines >= 128 then
        self.invalid = true
        error("Invalid training tooltip")
    end
    self.lines[#self.lines+1] = {left=left}
end
function TrainingSink:AddDoubleLine(left, right)
    if not self.lines then return end
    if not TrainingText(left) or not TrainingText(right) or #self.lines >= 128 then
        self.invalid = true
        error("Invalid training tooltip")
    end
    self.lines[#self.lines+1] = {left=left, right=right}
end

local function ReadTrainingSpell(text)
    local icon, name = text:match("^  |T(%d+):0|t (.-) — ")
    icon = tonumber(icon)
    if not icon or icon < 1 or icon > 2147483647 or not name or not name:find("%S")
        or name:find("|", 1, true) then return end
    return {icon=icon, name=name}
end

local function ReadTraining()
    local System = YUI.API.System
    if not System or type(System.IsAddOnLoadedSafe) ~= "function"
        or not System.IsAddOnLoadedSafe("WhatsTraining") then return end
    if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then return end
    local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if type(ldb) ~= "table" or type(ldb.GetDataObjectByName) ~= "function" then return end
    local provider = ldb:GetDataObjectByName("WhatsTraining")
    if type(provider) ~= "table" or type(provider.OnTooltipShow) ~= "function" then return end

    local lines = {}
    TrainingSink.lines = lines
    provider.OnTooltipShow(TrainingSink)
    if TrainingSink.invalid then return end
    local green = TrainingText(GREEN_FONT_COLOR_CODE) and GREEN_FONT_COLOR_CODE or "|cff19ff19"
    local groups, available, current, active, seen, count = {}, nil, nil, nil, {}, 0
    for _, row in ipairs(lines) do
        if not row.right then
            local color, title = row.left:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r — ")
            local kind = color == green and AvailableTrainingTitles[title] and "available"
                or color == "|cff82c5ff" and TrainingTitles[title] and "soon"
            if kind then
                if active or seen[kind] then return end
                active, seen[kind], current, count = kind, true, nil, 0
                if kind == "available" then available = {available=true, spells={}} end
            elseif active then
                if row.left == " " then
                    if count == 0 then return end
                    active = nil
                elseif active == "available" then
                    local spell = ReadTrainingSpell(row.left)
                    if not spell or count >= 10 then return end -- 截断提示也不能当作技能行。
                    available.spells[#available.spells+1] = spell
                    count = count + 1
                else
                    return
                end
            end
        elseif active then
            if active ~= "soon" then return end
            local spell = ReadTrainingSpell(row.left)
            local level = row.right:match("^%D*([1-9]%d*)%D*$")
            level = tonumber(level)
            if not spell or not level or level > 1000
                or row.right:find("|", 1, true) or count >= 10 then return end
            if not current or current.level ~= level then
                if current and current.level > level then return end
                current = {level=level, levelText=row.right, spells={}}
                groups[#groups+1] = current
            elseif current.levelText ~= row.right then
                return
            end
            current.spells[#current.spells+1] = spell
            count = count + 1
        end
    end
    if active then return end -- 两个分组都必须完整结束，才提交本次结果。
    if available then table.insert(groups, 1, available) end
    if #groups > 0 then return groups end
end

local function GroupName(group)
    return L[group == 2 and "talents.forever.secondary" or "talents.forever.primary"]
end

function Module:OnInitialize()
    self.frame = nil
    self.runtimeAttached = false
end

function Module:GetGroupDisplay(group, showClassName)
    local info, configID, staged = Talent.GetTalentGroupDistribution(group)
    self.distributions = self.distributions or {}
    local cached = self.distributions[group]
    if info then
        self.distributions[group] = {configID=configID, info=info}
    elseif staged and cached and cached.configID == configID then
        info = cached.info
    else
        self.distributions[group] = nil
    end
    local index = Talent.GetSpecialization()
    local icon
    if index then local _, _, _, texture = Talent.GetSpecializationInfo(index); icon = texture end
    if not info then return L["talents.forever.unavailable"], icon or 134400 end
    local name = L["talents.forever.unassigned"]
    if info.total > 0 then
        name = string.format("%s (%d/%d/%d)", info.name,
            info.trees[1].points, info.trees[2].points, info.trees[3].points)
        icon = info.icon
    elseif showClassName then
        local className = YUI.API.Unit.UnitClass("player")
        if (not issecretvalue or not issecretvalue(className))
            and type(className) == "string" and className ~= "" then
            name = className
        end
    end
    if info.unspent and info.unspent > 0 then
        name = name .. string.format(" |cffffd100+%d|r", info.unspent)
    end
    return name, icon or 134400
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not self.frame then return end
    local active = Talent.GetActiveTalentGroup()
    local name, icon = L["talents.forever.unavailable"], 134400
    if active == 1 or active == 2 then name, icon = self:GetGroupDisplay(active, true) end
    Info.Display(self, name, icon or 134400)
    local Icons = YUI.API.Icons
    if self.frame.iconSlot and Icons and Icons.GetScopedSpecIcon then
        local iconData = Icons.GetScopedSpecIcon(nil, icon, "ybar")
        YBar:SetIconSlotIcon(self.frame.iconSlot, iconData, icon or 134400)
        YBar:SetIconSlotChromeVisible(self.frame.iconSlot, self.chrome and not (iconData and iconData.custom))
    end
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.frame then self:OnEnter(self.frame) end
end

function Module:Refresh(event)
    if not self.runtimeAttached then return end
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then self.lastSwitchRequest = nil end
    if self.refreshTimer then return end
    self.refreshTimer = C_Timer.NewTimer(0, function()
        self.refreshTimer = nil
        if self.runtimeAttached then self:UpdateBarItem() end
    end)
end

local function ShiftDown()
    local down = Frame and Frame.IsShiftKeyDown and Frame.IsShiftKeyDown()
    return (not issecretvalue or not issecretvalue(down)) and down == true
end

function Module:OwnsTooltip()
    return self.runtimeAttached and self.frame and GameTooltip and GameTooltip.GetOwner
        and GameTooltip:GetOwner() == self.frame
end

function Module:OnModifierChanged(_, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if self:OwnsTooltip() and self.tooltipExpanded ~= ShiftDown() then self:OnEnter(self.frame) end
end

function Module:OnWeaponSkillsChanged(event)
    if not self:OwnsTooltip() or self.tooltipTimer
        or not (self.tooltipExpanded or (event == "SPELLS_CHANGED" and self.trainingShown)) then return end
    self.tooltipTimer = C_Timer.NewTimer(0, function()
        self.tooltipTimer = nil
        if self:OwnsTooltip() and (self.tooltipExpanded or self.trainingShown) then self:OnEnter(self.frame) end
    end)
end

local function AddWeaponLine(text, tone)
    local r, g, b = GUI:GetColor("color.tooltip." .. tone)
    GameTooltip:AddLine(text, r, g, b, true)
end

local function AddWeaponRow(left, right, leftTone, rightTone)
    local r, g, b = GUI:GetColor("color.tooltip." .. leftTone)
    local rr, rg, rb = GUI:GetColor("color.tooltip." .. rightTone)
    -- 续行不能用空字符串作左列，否则原生行高可能塌陷。
    GameTooltip:AddDoubleLine(left == "" and " " or left, right, r, g, b, rr, rg, rb)
end

local function TrainerName(name)
    return Tooltip:ColorText(name, "npc")
end

local function CityName(name)
    return Tooltip:ColorText(name, "city")
end

function Module:AddTraining()
    -- 获取、解析和外部字段读取均受保护；验证结束前不向真实提示写入任何行。
    local ok, groups = pcall(ReadTraining)
    TrainingSink.lines = nil
    TrainingSink.invalid = nil
    self.trainingShown = ok and groups ~= nil
    if not self.trainingShown then return end
    for _, group in ipairs(groups) do
        GameTooltip:AddLine(" ")
        local suffix = #group.spells == 1 and "_one" or "_many"
        if group.available then
            AddWeaponLine(string.format(L["talents.training.available" .. suffix], #group.spells), "success")
        else
            AddWeaponLine(string.format(L["talents.training.soon" .. suffix], group.levelText, #group.spells), "subheading")
        end
        for _, spell in ipairs(group.spells) do
            AddWeaponLine(string.format("|T%d:16:16|t %s", spell.icon, spell.name), "body")
        end
    end
end

function Module:AddWeaponSkills()
    local catalog = WeaponSkill and WeaponSkill.GetCatalog()
    if not catalog then return end
    local rows = {}
    local faction = YUI.API.Unit.UnitFactionGroup and YUI.API.Unit.UnitFactionGroup("player")
    for _, skill in ipairs(catalog.skills) do
        local state, rank, maximum, modifier = WeaponSkill.GetPlayerSkill(skill)
        rows[#rows+1] = {skill=skill, state=state, rank=rank, maximum=maximum, modifier=modifier}
    end
    GameTooltip:AddLine(" ")
    AddWeaponLine(L["talents.weapons.title"], "heading")
    for _, group in ipairs({"learned", "unlearned", "unavailable"}) do
        local heading
        for _, row in ipairs(rows) do
            if row.state == group then
                if not heading then
                    if group ~= "learned" then GameTooltip:AddLine(" ") end
                    local column = group == "learned" and L["talents.weapons.rank"]
                        or group == "unlearned" and L["talents.weapons.location"] or ""
                    local tone = group == "unavailable" and "secondary" or "subheading"
                    AddWeaponRow(L["talents.weapons." .. group], column, tone, tone)
                    heading = true
                end
                local name = LC[row.skill.nameKey]
                if group == "learned" then
                    local value = string.format("%d/%d", row.rank, row.maximum)
                    if row.modifier ~= 0 then value = string.format("%d (%+d)/%d", row.rank, row.modifier, row.maximum) end
                    AddWeaponRow(name, value, "body", row.rank >= row.maximum and "success" or "body")
                elseif group == "unavailable" then
                    AddWeaponRow(name, "--", "secondary", "secondary")
                else
                    if row.skill.minLevel then
                        name = name .. Tooltip:ColorText(string.format(L["talents.weapons.level"], row.skill.minLevel), "requirement")
                    end
                    local location = WeaponSkill.GetLearningLocations(row.skill, faction, TrainerName, CityName)
                    local tone = location and "body" or "secondary"
                    location = location or L["talents.weapons.location_unknown"]
                    local first = true
                    for line in location:gmatch("[^\n]+") do
                        AddWeaponRow(first and name or "", line, "body", tone)
                        first = false
                    end
                end
            end
        end
    end
end

function Module:AttachRuntime()
    if not self.frame then return end
    self.runtimeAttached = true
    YUI.Event:OffOwner(self)
    YUI.Event:On("YUI_WORLD_READY", "Refresh", self)
    YUI.Event:On("PLAYER_TALENT_UPDATE", "Refresh", self)
    YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", "Refresh", self)
    YUI.Event:On("PLAYER_LEVEL_UP", "Refresh", self)
    YUI.Event:On("TRAIT_CONFIG_UPDATED", "Refresh", self)
    YUI.Event:On("MODIFIER_STATE_CHANGED", "OnModifierChanged", self)
    YUI.Event:On("SKILL_LINES_CHANGED", "OnWeaponSkillsChanged", self)
    YUI.Event:On("SPELLS_CHANGED", "OnWeaponSkillsChanged", self)
    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", "Refresh", self)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == "ybar" then self:Refresh() end
    end, self)
    self:UpdateBarItem()
end

function Module:DetachRuntime()
    self.runtimeAttached = false
    YUI.Event:OffOwner(self)
    if self.refreshTimer then self.refreshTimer:Cancel(); self.refreshTimer = nil end
    if self.tooltipTimer then self.tooltipTimer:Cancel(); self.tooltipTimer = nil end
    self.tooltipExpanded = nil
    self.trainingShown = nil
    self.lastSwitchRequest = nil
    self.distributions = nil
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.frame then YUI.HideGameTooltip() end
    if self.frame then self.frame:Hide() end
end

function Module:OnClick(frame, button)
    if not self.runtimeAttached or Security.InCombatLockdown() then return end
    if not Talent.CanUseTalentGroups() then return end
    if button == "LeftButton" then
        Talent.ToggleTalentFrame()
    elseif button == "RightButton" then
        local active = Talent.GetActiveTalentGroup()
        if Talent.GetNumTalentGroups() < 2 or (active ~= 1 and active ~= 2) then return end
        local now = Combat.GetTime()
        if self.lastSwitchRequest and now - self.lastSwitchRequest < 1 then return end
        if Talent.SetActiveTalentGroup(active == 1 and 2 or 1) then self.lastSwitchRequest = now end
    end
end

function Module:OnEnter(frame)
    if not self.runtimeAttached then return end
    local anchor, offset = YUI.F:GetTooltipAnchor(frame)
    GameTooltip:SetOwner(frame, anchor, 0, offset)
    GameTooltip:ClearLines()
    self.tooltipExpanded = ShiftDown()
    self.trainingShown = nil
    GameTooltip:AddLine(L["ybar.module.talents"])
    GameTooltip:AddLine(" ")
    local active, count = Talent.GetActiveTalentGroup(), Talent.GetNumTalentGroups()
    local canUse, reason = Talent.CanUseTalentGroups()
    for group = 1, 2 do
        local current = group == active
        local status = group > count and L["talents.forever.locked"] or self:GetGroupDisplay(group)
        local label = GroupName(group)
        if current then label = label .. " · " .. L["talents.forever.current"] end
        if current then
            GameTooltip:AddDoubleLine(label, status, 1, 0.82, 0, 1, 0.82, 0)
        elseif group > count then
            GameTooltip:AddDoubleLine(label, status, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        else
            GameTooltip:AddDoubleLine(label, status, 1, 1, 1, 1, 1, 1)
        end
    end
    if not canUse then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(reason or L["talents.forever.locked"], 1, 0.2, 0.2, true)
    end
    self:AddTraining()
    if self.tooltipExpanded then self:AddWeaponSkills() end
    GameTooltip:AddLine(" ")
    if canUse then
        GameTooltip:AddLine(Tooltip:FormatAction({button="LeftButton", text=L["talents.action.open_talents"], textTone="heading"}))
        if count > 1 and (active == 1 or active == 2) then
            GameTooltip:AddLine(Tooltip:FormatAction({button="RightButton", textTone="heading",
                text=string.format(L["talents.forever.switch_to"], GroupName(active == 1 and 2 or 1))}))
        end
    end
    GameTooltip:AddLine(Tooltip:FormatAction({key="SHIFT", keyAction=self.tooltipExpanded and "release" or "hold",
        text=L[self.tooltipExpanded and "talents.weapons.hide" or "talents.weapons.show"], textTone="heading"}))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Tooltip:FormatAction({modifiers={"ALT"}, keyTone="secondary", textTone="secondary"}, true))
    GameTooltip:Show()
end

function Module:OnLeave()
    if self.tooltipTimer then self.tooltipTimer:Cancel(); self.tooltipTimer = nil end
    self.tooltipExpanded = nil
    self.trainingShown = nil
    YUI.HideGameTooltip()
end

function Module:CreateBarItem(parent)
    self:DetachRuntime()
    -- Info.Display 的缓存必须随新视图失效。
    self.text, self.icon, self.font, self.size, self.iconSize, self.width, self.chrome, self.shadow = nil, nil, nil, nil, nil, nil, nil, nil
    return Info.Create(self, parent)
end

function Module:GetWidth() return self.width or 10 end
function Module:GetOptions() return Info.Options(self) end
Info.Register(Module)
