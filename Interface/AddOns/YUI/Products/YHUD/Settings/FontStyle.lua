-- The shared editor owns interaction; Halo owns draft writes and presentation.
local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
local GUI = YUI and YUI.GUI2
local Style = GUI and GUI.FontStyle
if not (HUD and HUD.Designer and Style) then return end
local Designer, Model = HUD.Designer, HUD.ProfileModel
local Adapter = {}
HUD.FontStyle = Adapter

local function T(key, fallback) return HUD:T(key, fallback) end
local function FontPath(value)
    if value == "chat" and _G.ChatFontNormal and _G.ChatFontNormal.GetFont then
        local path = _G.ChatFontNormal:GetFont()
        if path then return path end
    elseif value == "damage" and _G.DAMAGE_TEXT_FONT then return _G.DAMAGE_TEXT_FONT end
    local fallback = GUI:GetFont("font.family.body")
    if value == "default" then return fallback end
    return Style.FontPath(value, fallback)
end
local function RGBA(color)
    return {color.r or color[1] or 1, color.g or color[2] or 1,
        color.b or color[3] or 1, color.a or color[4] or 1}
end
local function Refresh(positionOnly, groupId, sky)
    local ui = HUD.DesignerUI
    if not ui then return end
    if sky and ui.ApplySkyridingPreview then ui:ApplySkyridingPreview(true)
    elseif positionOnly and Designer:GetSession().selectedGroupId == groupId and ui.PreviewSelectedGroup then
        ui.v2SliderPreviewDirty = true
        ui:PreviewSelectedGroup()
    elseif ui.ApplyPreview then ui:ApplyPreview() end
end

function Adapter:Key(groupId, prefix, resourceId)
    return "yhud:" .. groupId .. "/" .. prefix .. (resourceId and ("/" .. resourceId) or "")
end

Style:Register("yhud", function()
    if not Designer:IsOpen() then return end
    local session = Designer:GetSession()
    local draft, profile, specKey = session.draft, session.draft.profile, session.viewSpecKey
    local catalog = {label = T("settings.title", "Halo 监控台"), targets = {}}
    local entries = {}
    catalog.current = function()
        return Designer:IsOpen() and Designer:GetSession() == session and session.draft == draft
            and draft.profile == profile and session.viewSpecKey == specKey and not draft.closed
    end
    local function Current(entry)
        if not catalog.current() then return false end
        if entry.sky then return true end
        local group = profile.groups.items[entry.groupId]
        return group and group.layout == entry.layout and (not entry.resourceId
            or HUD:GetResourceSetting(profile, entry.resourceId, entry.groupId).textOverride ~= nil)
    end
    local function Config(entry, parent)
        if entry.sky then
            return HUD:NormalizeSkyridingSettings(parent and {} or draft.root.skyriding).styles[entry.sky]
        elseif entry.resourceId then
            return parent and HUD:GetResourceGroupStyle(profile, entry.groupId)
                or HUD:GetResourceSetting(profile, entry.resourceId, entry.groupId).textOverride
        end
        if parent then
            return entry.layout == "icons" and HUD:NormalizeIconGroupStyle({})
                or entry.layout == "resource" and HUD:NormalizeResourceGroupStyle({})
                or HUD:NormalizeDurationGroupStyle({})
        end
        return entry.layout == "icons" and HUD:GetIconGroupStyle(profile, entry.groupId)
            or entry.layout == "resource" and HUD:GetResourceGroupStyle(profile, entry.groupId)
            or HUD:GetDurationGroupStyle(profile, entry.groupId)
    end
    local function Read(entry, config)
        local fields = entry.fields
        config = config or Config(entry)
        local value = Style.Decode(config[fields.outline], nil, config[fields.monochrome])
        local font = config[fields.font]
        value.font = FontPath(font)
        value.size = config[fields.size]
        local color = config[fields.color]
        value.color = type(color) == "table" and RGBA(color) or {mode = "state"}
        return value
    end
    local function Write(entry, patch)
        if not Current(entry) then return false end
        if entry.sky then return Model:SetSkyridingStyleSettings(draft, entry.sky, patch)
        elseif entry.resourceId then
            return Model:SetResourceTextOverride(draft, entry.resourceId, true, patch, entry.groupId)
        end
        local setter = entry.layout == "icons" and Model.SetGroupIconStyle
            or entry.layout == "resource" and Model.SetGroupResourceStyle or Model.SetGroupDurationStyle
        return setter(Model, draft, entry.groupId, patch)
    end
    local function Patch(entry, values, reset)
        local config, fields = Config(entry), entry.fields
        local value = Read(entry, config)
        local parent = reset and Config(entry, true)
        local defaults = parent and Read(entry, parent)
        local patch = {}
        for _, attribute in ipairs(Style.attributes) do
            if reset and reset[attribute] then value[attribute] = defaults[attribute]
            elseif values[attribute] ~= nil then value[attribute] = values[attribute] end
            if (reset and reset[attribute]) or values[attribute] ~= nil then
                if attribute == "outline" or attribute == "shadow" then
                    patch[fields.outline] = true
                elseif attribute == "color" then
                    local color = value.color
                    patch[fields.color] = color.mode == "state" and "default"
                        or {r=color[1], g=color[2], b=color[3], a=color[4] or 1}
                else
                    patch[fields[attribute]] = reset and reset[attribute] and parent[fields[attribute]] or value[attribute]
                end
            end
        end
        if patch[fields.outline] then patch[fields.outline] = Style.EncodeEffect(value, "camel") end
        return patch
    end
    local function Add(groupId, layout, prefix, label, resourceId, sky)
        local id = groupId .. "/" .. prefix .. (resourceId and ("/" .. resourceId) or "")
        local entry = {groupId=groupId, layout=layout, prefix=prefix, resourceId=resourceId, sky=sky,
            fields={font=prefix.."Font", size=prefix.."Size", outline=prefix.."Outline",
                monochrome=prefix.."Monochrome", color=prefix.."Color"}}
        if sky and prefix == "speedText" then entry.fields.font, entry.fields.size = "speedFont", "speedFontSize" end
        local target = {id=id, label=label, minSize=8, maxSize=32,
            capabilities={font=true,size=true,outline=true,shadow=true,monochrome=true,color=true},
            fontOptionsPosition="last", colorModes=sky and {state=true} or nil,
            fontOptions=function()
                local selected = Config(entry)[entry.fields.font]
                return {
                    {value="chat", text=T("designer.font.chat", "聊天字体"), fontPath=selected == "chat" and FontPath("chat") or nil},
                    {value="damage", text=T("designer.font.damage", "伤害数字"), fontPath=selected == "damage" and FontPath("damage") or nil},
                    {value="default", text=T("designer.font.default", "默认"), fontPath=selected == "default" and FontPath("default") or nil},
                }
            end}
        target.read = function() return Read(entry) end
        target.parent = function(attribute) return Read(entry, Config(entry, true))[attribute] end
        if sky then
            target.colorInfo = function(mode)
                local value = Read(entry).color
                if mode == "state" or (not mode and value.mode == "state") then
                    return {mode="state", color={GUI:GetColor("color.text.primary")},
                        label=YUI.Locale:Get("Core")["font_style.follow_theme"]}
                end
                return {mode="custom", color=value.mode ~= "state" and value or {GUI:GetColor("color.text.primary")}}
            end
        end
        if layout ~= "resource" and not sky
            and not (layout == "icons" and Config(entry).skinId == "masque"
                and (prefix == "countText" or prefix == "keybindText")) then
            target.position = {x={min=-64,max=64}, y={min=-64,max=64},
                read=function()
                    local config = Config(entry)
                    return {x=config[prefix.."OffsetX"] or 0,y=config[prefix.."OffsetY"] or 0}
                end,
                apply=function(values)
                    if not Current(entry) then return false end
                    local patch = {}
                    for axis, value in pairs(values) do
                        if (axis ~= "x" and axis ~= "y") or type(value) ~= "number"
                            or value ~= value or value < -64 or value > 64 then return false end
                        patch[prefix.."Offset"..axis:upper()] = value
                    end
                    if not Write(entry, patch) then return false end
                    Refresh(true, groupId)
                    return true
                end,
                commit=function()
                    if not Current(entry) then return false end
                    local ui = HUD.DesignerUI
                    if ui and ui.CommitV2SliderPreview then ui:CommitV2SliderPreview() end
                    return true
                end,
                reset=function()
                    local defaults = Config(entry, true)
                    if not Write(entry, {[prefix.."OffsetX"]=defaults[prefix.."OffsetX"] or 0,
                        [prefix.."OffsetY"]=defaults[prefix.."OffsetY"] or 0}) then return false end
                    Refresh(false, groupId)
                    return true
                end}
        end
        entry.target = target
        entries[id] = entry
        catalog.targets[#catalog.targets+1] = target
    end
    for _, id in ipairs(profile.groups.order) do
        local group = profile.groups.items[id]
        local label = group.nameKey and T(group.nameKey, group.name or id)
            or group.name or id
        if group.layout == "resource" then
            Add(id, group.layout, "text", label .. " · " .. T("designer.resource.global_settings", "全局设置"))
            local resources = HUD:GetResourceConfig(profile, id)
            for resourceId, setting in pairs(resources.settingsByResource or {}) do
                if setting.textOverride and resourceId ~= "cast" then
                    local definition = HUD.ResourceCatalog and HUD.ResourceCatalog:GetDefinition(resourceId)
                    local name = definition and T(definition.labelKey or definition.nameKey, resourceId) or resourceId
                    Add(id, group.layout, "text", label .. " · " .. name, resourceId)
                end
            end
        elseif group.layout == "icons" or group.layout == "bars" or group.layout == "rings" then
            Add(id, group.layout, group.layout == "icons" and "cooldownText" or "timeText",
                label .. " · " .. T(group.layout == "icons" and "designer.text_target.cooldown" or "designer.text_target.duration", "时间"))
            Add(id, group.layout, "countText", label .. " · " .. T("designer.text_target.count", "层数/充能"))
            if group.layout == "icons" then
                Add(id, group.layout, "keybindText", label .. " · " .. T("designer.keybind.title", "按键文本"))
            elseif group.layout ~= "bars" or HUD:GetDurationGroupLayout(profile, id, group.layout).orientation ~= "vertical" then
                Add(id, group.layout, "nameText", label .. " · " .. T("designer.text_target.name", "名称"))
            end
        end
    end
    if not (HUD.Client and HUD.Client.skyriding == false) then
        Add("skyriding", nil, "speedText", T("skyriding.settings.speed_font", "速度文字字体"), nil, "halo")
        Add("skyriding", nil, "cooldownBarText", T("skyriding.settings.cooldown_bar_font", "冷却条倒计时字体"), nil, "halo")
    end
    catalog.snapshot = function(id)
        local entry = entries[id]
        if not entry or not Current(entry) then return end
        local config, snapshot = Config(entry), {}
        for _, field in pairs(entry.fields) do snapshot[field] = Style.Copy(config[field]) end
        return snapshot
    end
    catalog.apply = function(changes)
        local patches, skyOnly = {}, true
        for id, change in pairs(changes) do
            local entry, attributes = entries[id], {}
            if not entry or not Current(entry) then return false end
            for attr in pairs(change.values or {}) do attributes[attr] = true end
            if next(attributes) and not Style.Validate(entry.target, change.values or {}, attributes) then return false end
            local values = change.values or {}
            if values.font and #values.font > 160 or values.size and values.size % 1 ~= 0 then return false end
            for attr in pairs(change.reset or {}) do
                if not entry.target.capabilities[attr] then return false end
            end
            patches[id] = Patch(entry, change.values or {}, change.reset)
            skyOnly = skyOnly and entry.sky ~= nil
        end
        for id, patch in pairs(patches) do if not Write(entries[id], patch) then return false end end
        Refresh(false, nil, skyOnly)
        return true
    end
    catalog.restore = function(snapshots, attributes)
        local skyOnly = true
        for id in pairs(snapshots) do if not entries[id] or not Current(entries[id]) then return false end end
        for id, snapshot in pairs(snapshots) do
            local entry, values = entries[id], {}
            skyOnly = skyOnly and entry.sky ~= nil
            local restored = Read(entry, snapshot)
            for _, attr in ipairs(Style.attributes) do
                if not attributes or attributes[attr] then values[attr] = restored[attr] end
            end
            local patch = Patch(entry, values)
            if values.font ~= nil then patch[entry.fields.font] = snapshot[entry.fields.font] end
            if not Write(entry, patch) then return false end
        end
        Refresh(false, nil, skyOnly)
        return true
    end
    return catalog
end)
