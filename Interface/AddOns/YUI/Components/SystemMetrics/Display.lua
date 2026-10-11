local YUI = _G.YUI
local Metrics = YUI and YUI.SystemMetrics
if not Metrics or Metrics.Display then return end

-- Presentation is shared by hosts; this file owns no frames, events or timers.
local Display = {}
Metrics.Display = Display
Display.Defaults = {
    displayStyle="STANDARD", fpsBadBelow=25, fpsSmoothFrom=40,
    latencySmoothBelow=200, latencyBadFrom=500,
    colorSmooth={1,1,1,1}, colorLag={.91,.85,.06,1}, colorBad={.85,.04,.04,1},
}
local defaults = Display.Defaults
local styles = {STANDARD=true,STANDARD_B=true,ICON=true,LABEL=true,MINIMAL=true}
local colorModes = {threshold=true,fixed=true,inherit=true}
local atlases = {FPS="GM-icon-menu-hover",LATENCY="GM-icon-countdown-hover",TOLERANCE="GM-icon-readyCheck-hover"}
local prefixes = {FPS="FPS ",LATENCY="Lat ",TOLERANCE="SQW "}
local units = {FPS=" fps",LATENCY=" ms",TOLERANCE=" ms"}
local labels = {FPS="system.label.fps",LATENCY="system.label.latency",TOLERANCE="system.label.tolerance"}
local icons = {}
local COLOR_KEYS={"colorSmooth","colorLag","colorBad"}
local thresholdRanges={
    fpsBadBelow={high="fpsSmoothFrom",max=240}, fpsSmoothFrom={low="fpsBadBelow",max=240},
    latencySmoothBelow={high="latencyBadFrom",max=5000}, latencyBadFrom={low="latencySmoothBelow",max=5000},
}

local function Text(key)
    return YUI.Locale:Get("SystemMetrics")[key]
end

local function Number(value, fallback, low, high)
    if issecretvalue and issecretvalue(value) then return fallback end
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
    return math.max(low,math.min(high,number))
end

local function NormalizeColor(value, fallback)
    if type(value) ~= "table" then value={} end
    if type(value[1]) == "table" then value=value[1] end
    for index=1,4 do value[index]=Number(value[index],fallback[index] or 1,0,1) end
    return value
end

function Display:Normalize(config)
    config.displayStyle=styles[config.displayStyle] and config.displayStyle or defaults.displayStyle
    if config.colorMode ~= nil then
        config.colorMode=colorModes[config.colorMode] and config.colorMode or "threshold"
    end
    config.fpsBadBelow=Number(config.fpsBadBelow,defaults.fpsBadBelow,0,240)
    config.fpsSmoothFrom=math.max(config.fpsBadBelow,Number(config.fpsSmoothFrom,defaults.fpsSmoothFrom,0,240))
    config.latencySmoothBelow=Number(config.latencySmoothBelow,defaults.latencySmoothBelow,0,5000)
    config.latencyBadFrom=math.max(config.latencySmoothBelow,Number(config.latencyBadFrom,defaults.latencyBadFrom,0,5000))
    for _,key in ipairs(COLOR_KEYS) do
        config[key]=NormalizeColor(config[key],defaults[key])
    end
    return config
end

function Display:GetValueColor(metric, value, config)
    if config.colorMode == "inherit" then return nil end
    if config.colorMode == "fixed" then return metric == "FPS" and config.fpsColor or config.latencyColor end
    local key
    if metric == "FPS" then
        key=value<(config.fpsBadBelow or defaults.fpsBadBelow) and "colorBad"
            or value<(config.fpsSmoothFrom or defaults.fpsSmoothFrom) and "colorLag" or "colorSmooth"
    else
        key=value<(config.latencySmoothBelow or defaults.latencySmoothBelow) and "colorSmooth"
            or value<(config.latencyBadFrom or defaults.latencyBadFrom) and "colorLag" or "colorBad"
    end
    return config[key] or defaults[key]
end

function Display:GetIcon(metric, size)
    size=size or 21
    local key=metric .. size
    if icons[key] == nil then
        icons[key]=YUI.F and YUI.F.GetAtlasString and YUI.F:GetAtlasString(atlases[metric],size,size,0,2) or ""
    end
    return icons[key]
end

function Display:FormatText(style, metric, value, config, hoverHex, iconSize)
    config=config or defaults
    value=Number(value,0,0,metric=="FPS" and 999 or 999999)
    local text=tostring(value)
    if hoverHex then
        text="|c" .. hoverHex .. text
        if metric == "TOLERANCE" then text=text .. "|r" end
    elseif metric == "TOLERANCE" then
        text="|cff00ccff" .. text .. "|r"
    else
        local color=self:GetValueColor(metric,value,config)
        if color then
            text=string.format("|c%02x%02x%02x%02x%s",math.floor((color[4] or 1)*255),
                math.floor(color[1]*255),math.floor(color[2]*255),math.floor(color[3]*255),text)
        end
    end
    if style == "ICON" then return self:GetIcon(metric,iconSize) .. " " .. text end
    if style == "LABEL" then return Text(labels[metric]) .. text end
    if style == "STANDARD_B" then return prefixes[metric] .. text end
    if style == "MINIMAL" then return text end
    return text .. units[metric]
end

function Display:BuildStyleOptions()
    return {
        {text=Text("system.option.style_standard_a"),value="STANDARD"},
        {text=Text("system.option.style_standard_b"),value="STANDARD_B"},
        {text=string.format(Text("system.option.style_icon"),self:GetIcon("FPS")),value="ICON"},
        {text=Text("system.option.style_label"),value="LABEL"},
        {text=Text("system.option.style_minimal"),value="MINIMAL"},
    }
end

-- Shared field schema; hosts supply storage and refresh behavior.
function Display:BuildFields(getConfig, changed, opts)
    opts=opts or {}
    local fields={}
    local function Add(kind,key,label,extra)
        local field=extra or {}
        field.type=kind
        field.searchKey=label
        field.label=Text(label)
        field.get=function() return getConfig()[key] end
        field.set=function(value)
            local config=getConfig()
            local range=thresholdRanges[key]
            if range then
                value=Number(value,config[key],range.low and config[range.low] or 0,
                    range.high and config[range.high] or range.max)
            end
            config[key]=value
            self:Normalize(config)
            changed(key)
        end
        if thresholdRanges[key] then
            -- Correct only the edited control; changing one boundary never silently changes its partner.
            field.onChange=function(widget)
                if widget:GetValue() ~= field.get() then widget:SetValue(field.get(),true) end
            end
            field.onCommit=function(widget) widget:SetValue(field.get(),true) end
        end
        fields[#fields+1]=field
    end
    Add("dropdown","displayStyle","system.option.display_style",{options=self:BuildStyleOptions(),width=220})
    if opts.allowColorMode then
        Add("dropdown","colorMode","display.color_mode",{options={
            {text=Text("display.color_threshold"),value="threshold"},
            {text=Text("display.color_fixed"),value="fixed"},
            {text=Text("display.color_inherit"),value="inherit"},
        }})
    end
    local mode=getConfig().colorMode or "threshold"
    if mode == "threshold" then
        for _,entry in ipairs({{"fpsBadBelow",240},{"fpsSmoothFrom",240},
            {"latencySmoothBelow",5000},{"latencyBadFrom",5000}}) do
            Add("slider",entry[1],"display." .. entry[1],{min=0,max=entry[2],step=1,inline=true,
                tooltip=Text("display.threshold_hint"),inputWidth=56,width=220})
        end
        for _,entry in ipairs({{"colorSmooth","system.option.smooth"},{"colorLag","system.option.lag"},
            {"colorBad","system.option.bad"}}) do
            Add("color",entry[1],entry[2],{default=defaults[entry[1]],width=100,hasAlpha=opts.hasAlpha==true})
        end
    elseif mode == "fixed" then
        Add("color","fpsColor","display.fps_color",{hasAlpha=true})
        Add("color","latencyColor","display.latency_color",{hasAlpha=true})
    end
    return fields
end
