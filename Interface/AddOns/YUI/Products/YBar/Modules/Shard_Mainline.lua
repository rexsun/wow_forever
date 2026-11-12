local YUI = _G.YUI
local YBar = YUI.YBar
local Info, L = YBar.InfoModule, YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local Unit, Format = YUI.API.Unit, YBar.LocationFormat
local Module = YBar.Module:New("Shard")
Module.defaultIcon = 135759
Module.CreateBarItem = Info.Create
local formats = {"location", "full_location", "shard_label", "shard_spaced", "shard_id", "location_shard", "full_location_shard", "custom"}
local events = {"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "GROUP_ROSTER_UPDATE"}

function Module:GetFormat()
    local db = Info.DB(self)
    if db.format == "custom" or db.format == "shard_label" or db.format == "shard_spaced" or db.format == "shard_id" or Format.templates[db.format] then
        return db.format
    end
    -- Missing format belongs to an existing configuration, including old empty tables.
    return db.idOnly and "shard_id" or "shard_label"
end

function Module:RefreshLocation()
    self.regionName, self.subzoneName, self.locationName = Unit.GetLocationNames()
end

function Module:GetLabelGap()
    return math.max(0, math.min(24, math.floor(tonumber(Info.DB(self).labelGap) or 4)))
end

function Module:GetShardText(colored)
    if not self.zone or not colored or Info.DB(self).colorByID == false then return self.zone end
    if self.coloredZone ~= self.zone then
        -- Work on the decimal digits so large IDs retain a stable palette index.
        local index = 0
        for pos = 1, #self.zone do index = (index * 10 + self.zone:byte(pos) - 48) % 8 end
        local r, g, b = YUI.GUI2:GetColor("color.ybar.shard."..(index + 1))
        self.coloredShard = string.format("|cff%02x%02x%02x%s|r", math.floor(r*255+0.5),
            math.floor(g*255+0.5), math.floor(b*255+0.5), self.zone)
        self.coloredZone = self.zone
    end
    return self.coloredShard
end

function Module:GetValues(colored)
    if self.locationName == nil then self:RefreshLocation() end
    local values = self.locationValues
    if not values then values={}; self.locationValues=values end
    values.zone = self.regionName ~= "" and self.regionName or L["location.unavailable"]
    values.subzone = self.subzoneName
    values.location = self.locationName ~= "" and self.locationName or L["location.unavailable"]
    values.shard = self:GetShardText(colored) or (self.status ~= "shard.instance" and L["shard.value_"..(self.status == "shard.restricted" and "restricted" or "unknown")] or "")
    return values
end

function Module:GetText(colored)
    local kind = self:GetFormat()
    if kind == "shard_label" or kind == "shard_spaced" or kind == "shard_id" then
        local prefix = kind == "shard_id" and "" or kind == "shard_spaced" and L["shard.label"].." " or L["shard.prefix"]
        return self.zone and (prefix..self:GetShardText(colored)) or L[self.status or "shard.unknown"]
    end
    local template = (kind == "custom" and Info.DB(self).customFormat or Format.templates[kind]) or Format.templates.location_shard
    local values = self:GetValues(colored)
    if self.renderedTemplate == template and self.renderedZone == values.zone and self.renderedSubzone == values.subzone
        and self.renderedLocation == values.location and self.renderedShard == values.shard then return self.renderedText end
    if self.compiledTemplate ~= template then
        self.compiledTemplate = template
        self.compiledFormat = Format.Compile(template) or Format.Compile(Format.templates.location_shard)
    end
    local text = Format.Render(self.compiledFormat, values)
    self.renderedTemplate, self.renderedZone, self.renderedSubzone = template, values.zone, values.subzone
    self.renderedLocation, self.renderedShard = values.location, values.shard
    self.renderedText = text ~= "" and text or L[self.status or "shard.unknown"]
    return self.renderedText
end

local function Measure(fontString, text)
    fontString:SetText(text)
    return fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
end

function Module:FitBarText(text, fontString, maxWidth)
    local kind = self:GetFormat()
    if kind ~= "location_shard" and kind ~= "full_location_shard" then return text end
    local values = self:GetValues(true)
    if values.shard == "" then return text end
    local location = kind == "location_shard" and values.location or values.zone..(values.subzone ~= "" and " / "..values.subzone or "")
    return Format.FitLocation(location, " ["..values.shard.."]", maxWidth, Measure, fontString)
end

function Module:FormatError(reason, field)
    local message = L["location.error_"..(reason or "invalid")]
    return reason == "field" and string.format(message, field:gsub("|", "||")) or message
end

function Module:SetCustomFormat(template)
    local nodes, reason, field = Format.Compile(template)
    if not nodes then return false, self:FormatError(reason, field) end
    local db=Info.DB(self)
    if db.customFormat == template then return true end
    db.customFormat = template
    self.compiledTemplate, self.compiledFormat = template, nodes
    self:UpdateBarItem()
    return true
end

function Module:RefreshFormatPreview()
    local panel = self.formatPanel
    if not panel or not panel:IsShown() then return end
    local text
    if panel.input then
        local template = panel.input:GetText()
        if panel.template ~= template then
            panel.template = template
            panel.nodes, panel.reason, panel.field = Format.Compile(template)
        end
        text = panel.nodes and Format.Render(panel.nodes, self:GetValues(true)) or self:FormatError(panel.reason, panel.field)
    else text=self:GetText(true) end
    if panel.value then
        local value = self.zone and self:GetShardText(true) or ""
        if panel.lastValue ~= value then panel.value:SetText(value); panel.lastValue=value end
        local gap = self:GetLabelGap()
        if panel.lastGap ~= gap then
            panel.value:ClearAllPoints()
            panel.value:SetPoint("LEFT", panel.preview, "RIGHT", gap, 0)
            panel.lastGap=gap
        end
        if self.zone then text=L["shard.label"] end
    end
    if text == "" then text=L[self.status or "shard.unknown"] end
    text=L["location.preview"]..text
    if panel.lastText ~= text then panel.preview:SetText(text);panel.lastText=text end
end

function Module:RenderFormatEditor(parent, x, y, width)
    local GUI = YUI.GUI2
    local custom = self:GetFormat() == "custom"
    local height = custom and 146 or 30
    local panel = GUI:CreateFrame(parent, {width=width, height=height})
    local epoch = self.runtimeEpoch or 0
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    panel.preview = GUI:CreateText(panel, "", "font.size.md", "color.text.primary")
    panel.preview:SetPoint("TOPLEFT", 0, custom and -80 or 0)
    panel.preview:SetWidth(width); panel.preview:SetJustifyH("LEFT"); panel.preview:SetWordWrap(true)
    if self:GetFormat() == "shard_spaced" then
        panel.preview:SetWidth(0)
        panel.preview:SetWordWrap(false)
        panel.value = GUI:CreateText(panel, "", "font.size.md", "color.text.primary")
    end
    self.formatPanel = panel
    panel:SetScript("OnHide", function()
        if self.formatPanel == panel then self.formatPanel=nil end
    end)
    panel:SetScript("OnShow", function() self.formatPanel=panel; self:RefreshFormatPreview() end)
    if custom then
        panel.input = GUI.Form:CreateEditBox(panel, {width=width, height=26,
            text=Info.DB(self).customFormat or Format.templates.location_shard,
            onChange=function() self:RefreshFormatPreview() end})
        panel.input:SetPoint("TOPLEFT", 0, 0)
        panel.input:SetMaxLetters(512)
        local function commit()
            if self.formatPanel ~= panel or epoch ~= (self.runtimeEpoch or 0) then return end
            if not panel.nodes or Info.DB(self).customFormat == panel.input:GetText() then return end
            local function apply() return self:SetCustomFormat(panel.input:GetText()) end
            if self.RunConfigEdit then self:RunConfigEdit(apply) else apply() end
            self:RefreshFormatPreview()
        end
        panel.input:SetScript("OnEnterPressed", function(edit) commit(); edit:ClearFocus() end)
        panel.input:HookScript("OnEditFocusLost", commit)
        panel.input:SetScript("OnEscapePressed", function(edit)
            edit:SetValue(Info.DB(self).customFormat or Format.templates.location_shard, true); edit:ClearFocus()
            self:RefreshFormatPreview()
        end)
        for index, key in ipairs({"location", "zone", "subzone", "shard"}) do
            local token = L["location.token_"..key]
            local button = GUI.Form:CreateButton(panel, {width=(width-18)/4, height=26, text=token,
                onClick=function() panel.input:Insert("{"..token.."}"); panel.input:SetFocus() end})
            button:SetPoint("TOPLEFT", (index-1)*(width+6)/4, -36)
        end
        local help = GUI:CreateText(panel, L["location.custom_help"], "font.size.sm", "color.text.secondary")
        help:SetPoint("TOPLEFT", 0, -112); help:SetWidth(width); help:SetJustifyH("LEFT"); help:SetWordWrap(true)
    end
    self:RefreshFormatPreview()
    return width, height
end

function Module:Reset()
    self.zone, self.server, self.instance, self.map, self.sampleTime = nil, nil, nil, nil, nil
    self.status = IsInInstance() and "shard.instance" or "shard.unknown"
end

function Module:Sample(unit)
    if IsInInstance() then self:Reset(); return end
    local guid = UnitGUID(unit)
    local zone, server, instance = Unit.GetShardReference(guid)
    if server == "restricted" then self:Reset(); self.status = "shard.restricted"; return end
    if zone then
        self.zone, self.server, self.instance = zone, server, instance
        local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        self.map = not (issecretvalue and issecretvalue(map)) and map or nil
        self.sampleTime = GetTime()
    end
end

function Module:OnEvent(event, unit)
    if event == "PLAYER_TARGET_CHANGED" then self:Sample("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then self:Sample("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then self:Sample(unit)
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        -- Subzone and indoor transitions update location without invalidating the NPC sample.
        self:RefreshLocation()
    else
        self:Reset()
        if event ~= "GROUP_ROSTER_UPDATE" then self:RefreshLocation() end
    end
    self:UpdateBarItem()
end

function Module:AttachRuntime()
    if self.active then return end
    self.active = true
    self:Reset()
    self:RefreshLocation()
    for _, event in ipairs(events) do
        YUI.Event:On(event, "OnEvent", self)
    end
end
function Module:DetachRuntime()
    self.active = false
    self.runtimeEpoch = (self.runtimeEpoch or 0)+1
    self.formatPanel = nil
    YUI.Event:OffOwner(self)
    self:Reset()
    self.regionName, self.subzoneName, self.locationName, self.locationValues = nil, nil, nil, nil
    self.compiledTemplate, self.compiledFormat = nil, nil
    self.renderedTemplate, self.renderedText, self.text = nil, nil, nil
    self.coloredZone, self.coloredShard = nil, nil
    if self.frame then self:OnLeave() end
end
function Module:OnDBReload() self:DetachRuntime(); if YBar:IsSubModuleEnabled(self.name) then self:AttachRuntime() end end
function Module:UpdateBarItem()
    if self:GetFormat() == "shard_spaced" and self.zone then
        Info.Display(self, self:GetShardText(true), self.defaultIcon, L["shard.label"], self:GetLabelGap())
    else
        Info.Display(self, self:GetText(true), self.defaultIcon)
    end
    self:RefreshFormatPreview()
end
function Module:GetOptions()
    local options=Info.Options(self)
    local choices = {}
    for _, kind in ipairs(formats) do
        choices[#choices+1] = {text=L[kind == "shard_label" and "shard.format_label" or kind == "shard_id" and "shard.format_id" or "location.format_"..kind], value=kind}
    end
    options[#options+1]={type="dropdown",label=L["shard.format"],width=220, options=choices,
        get=function()return self:GetFormat() end,
        set=function(v)
            if self:GetFormat() ~= v then self.text=nil end
            local db=Info.DB(self)
            db.format=v
            if v == "shard_label" or v == "shard_id" then db.idOnly=v == "shard_id" end
            if v == "custom" and db.customFormat == nil then db.customFormat=Format.templates.location_shard end
            self:UpdateBarItem()
        end}
    options[#options+1]={type="slider",label=L["shard.label_gap"],width=220,min=0,max=24,step=1,
        hidden=function()return self:GetFormat() ~= "shard_spaced" end,
        get=function()return self:GetLabelGap() end,
        set=function(v)
            if self:GetLabelGap() == v then return end
            Info.DB(self).labelGap=v
            self:UpdateBarItem()
        end}
    options[#options+1]={type="checkbox",label=L["shard.color_by_id"],
        get=function()return Info.DB(self).colorByID ~= false end,
        set=function(v)
            if (Info.DB(self).colorByID ~= false) == v then return end
            Info.DB(self).colorByID=v
            self:UpdateBarItem()
        end}
    options[#options+1]={type="custom",width=400,
        render=function(parent,x,y,width)return self:RenderFormatEditor(parent,x,y,width) end}
    return options
end
function Module:GetWidth() return self.width or 100 end
function Module:OnEnter()
    YUI.GUI2.Tooltip:Show(self.frame, {
        title=L["ybar.module.shard"],
        anchor=self.parent == YBar.topFrame and "ANCHOR_BOTTOM" or "ANCHOR_TOP",
        content=function(body)
            local values = self:GetValues()
            body:AddDoubleLine(L["location.zone_label"], values.zone, "body", "body")
            if values.subzone ~= "" then
                body:AddDoubleLine(L["location.subzone_label"], values.subzone, "body", "body")
            end
            local value = self:GetShardText(true) or (self.status == "shard.instance" and L["shard.value_instance"] or values.shard)
            body:AddDoubleLine(L["shard.label"], value, "body", "body")
            if self.sampleTime then
                local age = math.max(0, math.floor(GetTime() - self.sampleTime))
                body:AddDoubleLine(L["shard.sample_label"], string.format(L["shard.age"], age), "body", "body")
            end
            if self.status ~= "shard.instance" then
                body:AddSpace()
                body:AddLine(L["shard.sample_help"])
            end
        end,
        footer=string.format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]),
    })
end
function Module:OnLeave()
    YUI.GUI2.Tooltip:Hide(self.frame)
end
Info.Register(Module)
