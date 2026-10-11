-- Configuration identities are separate from translated module titles.
local Catalog = {}
local types={"MicroMenu","Stats","Clock","Professions","Talents","Teleports","Currency",
    "CurrencyTracker","SeasonCrests","DurabilityMount","System","MeetingStone","RaidMarkers",
    "BugSack","Shard","EquipmentSets"}
if _G.YUI and _G.YUI.IsForever then
    types = {"MicroMenu", "Stats", "Clock", "Currency", "System", "BugSack", "Talents", "Professions", "Teleports", "DurabilityMount", "MeetingStone", "RaidMarkers", "Shard"}
end
local multi={Clock=true,Stats=true,CurrencyTracker=true}
local info={CurrencyTracker=true,SeasonCrests=true,Shard=true,EquipmentSets=true}
if _G.YUI and _G.YUI.IsForever then info.Talents = true; info.Teleports = true; info.DurabilityMount = true end
local currencyStyle={key="display",
    fromCommon=function(value)return (value=="both" or value=="icon") and "icons" or "numbers"end,
    toCommon=function(value)return value=="icons" and "both" or "text"end}
local function FontPath(value)
    local media=LibStub and LibStub("LibSharedMedia-3.0",true)
    local fonts=media and media.HashTable and media:HashTable("font")
    -- Store the explicitly selected registration, not a global media override.
    return fonts and fonts[value] or value
end
local fontField={key="font",fromCommon=FontPath,toCommon=FontPath}
local upperDisplay={key="display",fromCommon=function(value)return value:upper()end,
    toCommon=function(value)return type(value)=="string" and value:lower() or value end}
local iconToggle={key="display",fromCommon=function(value)return value=="icon" or value=="both"end,
    toCommon=function(value)return value and "both" or "text"end}
local textToggle={key="display",fromCommon=function(value)return value=="text" or value=="both"end,
    toCommon=function(value)return value and "both" or "icon"end}
local defaultConfigs={Currency={showIcon=true,showText=true,currencyID=0,showSmall=false,showBagSpace=false,tooltipCurrencies={}},
    Shard={format="location_shard"}}
function Catalog.Build(root)
    local adapters={}
    for _,name in ipairs(types) do
        local fields={font="font",size="size"}
        if name=="Clock" then fields={font="font",fontSize="size"}
        elseif name=="Stats" then fields={barFont="font",barFontSize="size"} end
        fields[name=="Stats" and "barFont" or "font"]=fontField
        local appearance={font=true,size=true,outline=true,shadow=true,color=true,colorMode=true}
        if info[name] then
            fields.iconBackground="iconBackground"
            fields.iconSize="iconSize";fields.iconGap="iconGap"
            fields.color="color";fields.colorMode="colorMode"
            appearance.iconBackground=true;appearance.iconSize=true;appearance.iconGap=true
            if name=="CurrencyTracker" or name=="SeasonCrests" then
                fields.style=currencyStyle;appearance.display=true
            else fields.display="display";appearance.display=true end
        end
        local allowed
        if name=="MeetingStone" or name=="RaidMarkers" then
            fields.barAppearance=upperDisplay;appearance.display=true
            allowed={icon=true,both=true,text=true,none=true}
        elseif (name=="Teleports" and not info.Teleports) or (name=="DurabilityMount" and not info.DurabilityMount) then
            fields.showIcon=iconToggle;appearance.display=true;allowed={both=true,text=true}
        elseif name=="Currency" then
            fields.showIcon=iconToggle;fields.showText=textToggle;appearance.display=true
            allowed={icon=true,both=true,text=true,none=true}
        end
        if name=="BugSack" then fields.iconBackground="iconBackground";appearance.iconBackground=true end
        local displayValues=allowed or ((name=="CurrencyTracker" or name=="SeasonCrests") and {both=true,text=true} or {icon=true,both=true,text=true})
        adapters[name]={configKey=name,multi=multi[name]==true,fields=fields,appearance=appearance,
            values={display=displayValues},defaultConfig=defaultConfigs[name]}
    end
    local names={}
    for name in pairs(root.DataBroker and root.DataBroker.entries or {}) do names[name]=true end
    for _,row in pairs(root.modules or {}) do
        for _,name in ipairs(row) do
            if type(name)=="string" and name:sub(1,7)=="Broker:" then names[name:sub(8)]=true end
        end
    end
    for name in pairs(names) do
        adapters["Broker:"..name]={multi=false,brokerName=name,
            fields={font=fontField,size="size",display="display",iconBackground="iconBackground",
                iconSize="iconSize",iconGap="iconGap",color="color",colorMode="colorMode"},
            appearance={font=true,size=true,outline=true,shadow=true,color=true,colorMode=true,
                display=true,iconSize=true,iconGap=true,iconBackground=true},
            read=function(db)return db.DataBroker and db.DataBroker.entries and db.DataBroker.entries[name] end,
            write=function(db,config)
                db.DataBroker=db.DataBroker or {};db.DataBroker.entries=db.DataBroker.entries or {}
                db.DataBroker.entries[name]=config
            end,
            remove=function(db)
                if db.DataBroker and db.DataBroker.entries then db.DataBroker.entries[name]=nil end
            end,
        }
    end
    return adapters
end
function Catalog.ExtractAppearance(model,db,adapters)
    for _,id in ipairs(db.instanceOrder) do
        local instance=db.instances[id]
        local adapter=adapters[instance.moduleType]
        if adapter then
            instance.legacyAppearance=instance.legacyAppearance or {}
            for old in pairs(adapter.fields) do
                if instance.config[old]~=nil then instance.legacyAppearance[old]=model.Copy(instance.config[old]) end
            end
            if instance.moduleType=="Currency" and (instance.config.showIcon~=nil or instance.config.showText~=nil) then
                local icon,text=instance.config.showIcon~=false,instance.config.showText~=false
                instance.appearance.display=icon and (text and "both" or "icon") or (text and "text" or "none")
                instance.config.showIcon,instance.config.showText=nil,nil
            end
            for old,key in pairs(adapter.fields) do
                if instance.config[old]~=nil then
                    if type(key)=="table" then instance.appearance[key.key]=key.toCommon(instance.config[old])
                    else instance.appearance[key]=model.Copy(instance.config[old]) end
                    instance.config[old]=nil
                end
            end
        end
    end
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Catalog=Catalog
end
return Catalog
