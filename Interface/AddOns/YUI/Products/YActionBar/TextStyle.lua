local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not YAB then return end
local TextStyle = { prefixes = { "hotkey", "count", "macroName", "cooldownText" }, fields = {}, fieldOrder = {} }
YAB.TextStyle = TextStyle
for _, prefix in ipairs(TextStyle.prefixes) do
    for _, attribute in ipairs({"Font", "Outline", "Shadow", "Monochrome"}) do
        TextStyle.fields[prefix .. attribute] = { prefix = prefix, attribute = attribute, capability = prefix .. "Size" }
        TextStyle.fieldOrder[#TextStyle.fieldOrder+1] = prefix .. attribute
    end
end

function TextStyle:Normalize(field, value)
    local spec = self.fields[field]
    if not spec then return nil, "unsupported" end
    if spec.attribute == "Font" then
        if type(value) == "string" and value ~= "" and #value <= 512 then return value end
    elseif spec.attribute == "Outline" then
        if value == "NONE" or value == "OUTLINE" or value == "THICKOUTLINE" then return value end
    elseif type(value) == "boolean" then return value end
    return nil, "invalid"
end

-- Resolve once on the existing config/appearance path, never in an action update.
function TextStyle:Snapshot(config, snapshot)
    local style = YUI.GUI2 and YUI.GUI2.FontStyle
    for _, prefix in ipairs(self.prefixes) do
        local font = config[prefix .. "Font"]
        snapshot[prefix .. "Font"] = font and style and style.FontPath(font) or nil
        snapshot[prefix .. "Outline"] = config[prefix .. "Outline"]
        snapshot[prefix .. "Shadow"] = config[prefix .. "Shadow"]
        snapshot[prefix .. "Monochrome"] = config[prefix .. "Monochrome"]
        local color = config[prefix .. "Color"]
        if type(color) == "table" and color.mode == "class" and style then
            local r, g, b, a = style.ColorRGBA(color)
            local resolved = snapshot[prefix .. "Color"] or {}
            resolved[1], resolved[2], resolved[3], resolved[4] = r, g, b, a
            snapshot[prefix .. "Color"] = resolved
        end
    end
end

function TextStyle:RegisterEditor(context)
    local gui = YUI.GUI2
    local style = gui and gui.FontStyle
    if not style then return end
    local core = YUI.Locale:Get("Core")
    local labels = YUI.Locale:Get("YActionBar")
    local roles = {hotkey="hotkey",count="count",macroName="macro",cooldownText="cooldown"}
    style:Register("yactionbar", function()
        local db = context.getDB()
        if not db then return end
        local group = { label = labels["settings.title"], targets = {} }
        group.current = function() return context.getDB() == db end
        local owned = {}
        local function Current(entry)
            return group.current() and context.getConfig(db, entry.barId) == entry.config
        end
        local function Read(entry)
            local cfg, prefix = entry.config, entry.prefix
            local value = style.Decode(cfg[prefix.."Outline"] or "OUTLINE",
                cfg[prefix.."Shadow"] ~= false, cfg[prefix.."Monochrome"])
            value.font = cfg[prefix.."Font"] and style.FontPath(cfg[prefix.."Font"]) or gui:GetFont("font.family.body")
            value.size = cfg[prefix.."Size"]
            if value.size == nil then value.size = entry.defaults[prefix.."Size"] or (prefix=="macroName" and 10 or 12) end
            value.color = style.Copy(cfg[prefix.."Color"] or {mode="state"})
            return value
        end
        local function Fields(entry)
            return {font=entry.prefix.."Font",size=entry.prefix.."Size",outline=entry.prefix.."Outline",
                shadow=entry.prefix.."Shadow",monochrome=entry.prefix.."Monochrome",color=entry.prefix.."Color"}
        end
        local function Snapshot(entry)
            local values = {}
            for _, field in pairs(entry.fields) do values[field] = style.Copy(entry.config[field]) end
            return values
        end
        local function Save(entry, fields, positionOnly)
            local changes = {}
            for field in pairs(fields) do changes[#changes+1] = {field=field,value=style.Copy(entry.config[field])} end
            if #changes==0 then return true end
            local ok = context.save(entry.barId, changes)
            if ok == false then return false end
            context.refresh(entry.barId, positionOnly)
            return true
        end
        local function Add(barId)
            local cfg = context.getConfig(db, barId)
            if type(cfg) ~= "table" then return end
            for _, prefix in ipairs(TextStyle.prefixes) do
                if context.supported(barId, roles[prefix]) then
                    local id = barId .. "/" .. prefix
                    local entry = {barId=barId,prefix=prefix,config=cfg,defaults=context.defaults(barId) or {}}
                    entry.fields = Fields(entry); owned[id] = entry
                    local target = {id=id,label=context.label(barId).." · "..labels["settings.preview.text_"..roles[prefix]],
                        capabilities={font=true,size=true,outline=true,shadow=true,monochrome=true,color=true},
                        minSize=prefix=="cooldownText" and 0 or 8,maxSize=prefix=="cooldownText" and 32 or 24,
                        fontOptions=function() return {{value="__theme",text=core["font_style.follow_theme"],
                            fontPath=cfg[prefix.."Font"]==nil and gui:GetFont("font.family.body") or nil}} end,fontOptionsPosition="last",
                        colorModes={state=true,class=true}}
                    target.read = function() return Read(entry) end
                    target.parent = function(attribute)
                        if attribute=="size" then return entry.defaults[prefix.."Size"] or (prefix=="macroName" and 10 or 12) end
                        return ({font=gui:GetFont("font.family.body"),outline="OUTLINE",shadow=true,monochrome=false,color={mode="state"}})[attribute]
                    end
                    target.colorInfo = function(mode)
                        local color = cfg[prefix.."Color"]
                        mode = mode or (color and (color.mode or "custom") or "state")
                        if mode=="class" then
                            return {mode=mode,color={style.ColorRGBA(color and color.mode=="class" and color or {mode="class",alpha=1})}}
                        end
                        if mode=="custom" then return {mode=mode,color=color} end
                        return {mode="state",color=prefix~="cooldownText" and {gui:GetColor("color.text.primary")} or nil,
                            label=core[prefix=="cooldownText" and "font_style.color_native" or "font_style.follow_theme"]}
                    end
                    local function Position()
                        return {x=cfg[prefix.."OffsetX"] or 0,y=cfg[prefix.."OffsetY"] or 0}
                    end
                    local pending, pendingBefore = {}, nil
                    target.position = {x={min=-64,max=64},y={min=-64,max=64},read=Position,
                        apply=function(values)
                            if not Current(entry) then return false end
                            for axis, value in pairs(values) do
                                if (axis~="x" and axis~="y") or type(value)~="number" or value~=value or value < -64 or value > 64 then return false end
                            end
                            if not pendingBefore then
                                pendingBefore = {[prefix.."OffsetX"]=cfg[prefix.."OffsetX"],[prefix.."OffsetY"]=cfg[prefix.."OffsetY"]}
                            end
                            for axis, value in pairs(values) do
                                local field=prefix.."Offset"..axis:upper()
                                if value==(pendingBefore[field] or 0) then
                                    cfg[field]=pendingBefore[field];pending[field]=nil
                                else cfg[field]=value;pending[field]=true end
                            end
                            if not next(pending) then pendingBefore=nil end
                            context.refresh(barId, true)
                            return true
                        end,
                        commit=function()
                            if not Current(entry) then return false end
                            local result=Save(entry,pending,true)
                            if result==false and pendingBefore then
                                for field in pairs(pending) do cfg[field]=pendingBefore[field] end
                                context.refresh(barId,true)
                            end
                            pending,pendingBefore={},nil
                            return result
                        end,
                        reset=function()
                            if not Current(entry) then return false end
                            local fields={}
                            local before = {[prefix.."OffsetX"]=cfg[prefix.."OffsetX"],[prefix.."OffsetY"]=cfg[prefix.."OffsetY"]}
                            for _, axis in ipairs({"X","Y"}) do
                                local field=prefix.."Offset"..axis
                                cfg[field]=entry.defaults[field] or 0; fields[field]=true
                            end
                            pending,pendingBefore={},nil
                            local result=Save(entry,fields,true)
                            if result==false then
                                cfg[prefix.."OffsetX"],cfg[prefix.."OffsetY"]=before[prefix.."OffsetX"],before[prefix.."OffsetY"]
                                context.refresh(barId,true)
                            end
                            return result
                        end}
                    if cfg.skinId == "masque" and prefix ~= "cooldownText" then target.position = nil end
                    entry.target=target; group.targets[#group.targets+1]=target
                end
            end
        end
        for _, barId in ipairs(YAB.BAR_ORDER or {}) do Add(barId) end
        for _, barId in ipairs(YAB.SPECIAL_BAR_ORDER or {}) do Add(barId) end
        Add(YAB.SPECIAL_GROUP_ID or "specialActionsGroup")
        group.snapshot=function(id) return owned[id] and Snapshot(owned[id]) end
        group.apply=function(changes)
            local batches={}
            for id, patch in pairs(changes) do
                local entry=owned[id]
                if not entry or not Current(entry) then return false end
                local attributes={}
                for key in pairs(patch.values or {}) do attributes[key]=true end
                local valid=style.Validate(entry.target,patch.values or {},attributes)
                if not valid then return false end
            end
            for id, patch in pairs(changes) do
                local entry=owned[id]; local touched={}
                for attribute, field in pairs(entry.fields) do
                    if patch.reset and patch.reset[attribute] then
                        entry.config[field]=nil
                        if attribute=="size" then entry.config[field]=entry.target.parent("size") end
                        touched[field]=true
                    elseif patch.values[attribute]~=nil then
                        local value=patch.values[attribute]
                        if attribute=="font" and value=="__theme" or attribute=="color" and value.mode=="state" then value=nil end
                        entry.config[field]=style.Copy(value); touched[field]=true
                    end
                end
                local batch=batches[entry.barId] or {entry=entry,fields={}}
                batches[entry.barId]=batch
                for field in pairs(touched) do batch.fields[field]=true end
            end
            for _, batch in pairs(batches) do if not Save(batch.entry,batch.fields) then return false end end
            return true
        end
        group.restore=function(snapshots,attributes)
            for id in pairs(snapshots) do if not owned[id] or not Current(owned[id]) then return false end end
            local batches={}
            for id, snapshot in pairs(snapshots) do
                local entry=owned[id]; local touched={}
                for attribute,field in pairs(entry.fields) do
                    if not attributes or attributes[attribute] then entry.config[field]=style.Copy(snapshot[field]);touched[field]=true end
                end
                local batch=batches[entry.barId] or {entry=entry,fields={}}
                batches[entry.barId]=batch
                for field in pairs(touched) do batch.fields[field]=true end
            end
            for _, batch in pairs(batches) do if not Save(batch.entry,batch.fields) then return false end end
            return true
        end
        return group
    end)
end

-- Complete the settings binding when the suite loads the product afterwards.
-- The settings entry also calls this when it is the later side to load.
local settings = YUI.Settings and YUI.Settings.YActionBarModule
if settings and settings.RegisterTextStyle then settings:RegisterTextStyle() end
