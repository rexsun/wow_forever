-- All ordinary controls are rendered through the existing Settings renderer.
local Options={}
Options.__index=Options
local commonKeys={"font","size","outline","shadow","colorMode","color","display","iconSize","iconBackground","iconGap"}
function Options.New(designer)
    local bridge=designer.bridge
    return setmetatable({designer=designer,bridge=bridge,M=bridge.lib.Model,
        L=bridge.yui.Locale:Get("YBar"),C=bridge.yui.Locale:Get("Core")},Options)
end
function Options:Label(key)return self.L["designer."..key]end
function Options:Command(fn,affected)
    return function(value)return (self.bridge.session or self.bridge.settingsSession):Apply(function(db)return fn(db,value)end,affected)end
end
function Options:Field(kind,key,get,set,extra)
    local item={type=kind,label=self:Label(key),width=220,get=get,set=set}
    if kind=="slider" then item.instantUpdate=true end
    for k,v in pairs(extra or {}) do item[k]=v end
    return item
end
function Options:Choices(names)
    local values={}
    for _,name in ipairs(names) do values[#values+1]={text=self:Label(name),value=name} end
    return values
end
function Options:Section(key)
    return {type="divider",label=self:Label(key),width=460,alignLeft=true}
end
function Options:Appearance(scope,id)
    local bridge,M=self.bridge,self.M
    local function target(db)
        if scope=="instance" then return db.instances[id].appearance end
        if scope=="bar" then return db.bars[id].appearance end
        return db.defaults
    end
    local function value(key)
        local db=bridge:GetModel()
        if scope=="instance" then return M.Resolve(db,id,key) end
        if scope=="bar" and target(db)[key]==nil then return db.defaults[key],"global" end
        return target(db)[key],scope
    end
    local inst=scope=="instance" and bridge:GetModel().instances[id]
    local cap=inst and bridge.adapters[inst.moduleType]
    local registeredFonts=LibStub("LibSharedMedia-3.0"):HashTable("font")
    local fonts={}
    for name,path in pairs(registeredFonts) do
        fonts[#fonts+1]={text=name,value=path}
    end
    table.sort(fonts,function(a,b)return a.text<b.text end)
    local definitions={
        font={type="dropdown",options=fonts},size={type="slider",min=8,max=40,step=1},
        outline={type="dropdown",options=self.designer.gui.Form:BuildFontOutlineOptions({
            values={none="NONE",outline="OUTLINE",thick="THICKOUTLINE",shadow="SHADOW",outlineShadow="OUTLINE_SHADOW"}})},
        shadow={type="checkbox"},colorMode={type="dropdown",tooltip=self:Label("state_help"),options=self:Choices({"state","class","custom"})},
        color={type="color",hasAlpha=true},display={type="dropdown",options=self:Choices({"icon","both","text","none"})},
        iconSize={type="slider",min=8,max=48,step=1},iconBackground={type="checkbox"},
        iconGap={type="slider",min=0,max=24,step=1},
    }
    if cap and cap.values and cap.values.display then
        local allowed={}
        for _,item in ipairs(definitions.display.options) do if cap.values.display[item.value] then allowed[#allowed+1]=item end end
        definitions.display.options=allowed
    elseif not cap then
        definitions.display.options=self:Choices({"icon","both","text"})
    end
    local function inherited(key)
        local db=bridge:GetModel()
        local bar=scope=="instance" and M.FindBar(db,id)
        if bar and bar.appearance[key]~=nil then return bar.appearance[key] end
        return db.defaults[key]
    end
    local function effective(key,v)
        if key=="font" and bridge.ybar.ResolveFontPath then return bridge.ybar:ResolveFontPath(registeredFonts[v] or v,STANDARD_TEXT_FONT) end
        if key=="size" then return v or 14 end
        if key=="outline" then return v or "NONE" end
        if key=="display" then
            v=v or "both"
            if cap and cap.values and cap.values.display and not cap.values.display[v] then
                return cap.values.display.both and "both" or definitions.display.options[1].value
            end
        end
        return v
    end
    local options,row={},nil
    if scope~="global" then
        options[#options+1]={type="text",label=self:Label("inherit_hint"),width=400,colorKey="color.text.secondary"}
    end
    for _,key in ipairs(commonKeys) do
        if key~="shadow" and (not cap or cap.appearance[key]) then
            local section=key=="font" and "text" or key=="colorMode" and "colors" or key=="display" and "icon_text"
            if section then options[#options+1]=self:Section(section);row=nil end
            local definition=definitions[key]
            local item=self:Field(definition.type,key,function()
                if key=="outline" and value("shadow") then return effective(key,value(key))=="NONE" and "SHADOW" or "OUTLINE_SHADOW" end
                local result=effective(key,value(key))
                if result==nil and key=="color" then return {1,1,1,1} end
                return result
            end,self:Command(function(db,v)
                if key=="outline" then
                    target(db).outline=v=="OUTLINE_SHADOW" and "OUTLINE" or v=="SHADOW" and "NONE" or v
                    target(db).shadow=v=="OUTLINE_SHADOW" or v=="SHADOW"
                else target(db)[key]=M.Copy(v) end
            end,id),definition)
            item.width=194;item.inline=true;item.inputWidth=48
            if scope~="global" and (not M.Equal(effective(key,value(key)),effective(key,inherited(key)))
                or key=="outline" and (value("shadow")==true)~=(inherited("shadow")==true)) then
                item.restore=self:Command(function(db)
                    target(db)[key]=nil
                    if key=="outline" then target(db).shadow=nil end
                end,id)
            end
            if not row or #row.children==2 then
                row={type="custom",width=400,children={}}
                local fields=row.children
                row.render=function(parent,x,y)
                    local gui=self.designer.gui
                    local factories={dropdown="CreateDropdown",slider="CreateSlider",checkbox="CreateCheckbox",color="CreateColorPicker"}
                    for index,field in ipairs(fields)do
                        local cell=gui:CreateFrame(parent,{width=194,height=48})
                        cell:SetPoint("TOPLEFT",x+(index-1)*206,y)
                        local label=gui:CreateText(cell,field.label,"font.size.md","color.text.primary")
                        label:SetPoint("TOPLEFT");label:SetWidth(field.restore and 166 or 194);label:SetJustifyH("LEFT");label:SetWordWrap(false)
                        local spec={};for k,v in pairs(field)do spec[k]=v end
                        spec.label=nil;spec.restore=nil;spec.height=28
                        local control=gui.Form[factories[field.type]](gui.Form,cell,spec)
                        control:SetPoint("TOPLEFT",0,-20)
                        if field.restore then
                            local reset=gui:CreateButtonFrame(cell,{width=22,height=20})
                            local glyph=gui:CreateText(reset,"↶","font.size.md","color.text.heading")
                            glyph:SetPoint("CENTER")
                            reset:SetScript("OnClick",field.restore)
                            reset:SetScript("OnEnter",function()
                                GameTooltip:SetOwner(reset,"ANCHOR_RIGHT");GameTooltip:SetText(self:Label("inherit"));GameTooltip:Show()
                            end)
                            local function hide()if GameTooltip:GetOwner()==reset then self.bridge.yui.HideGameTooltip()end end
                            reset:SetScript("OnLeave",hide);reset:SetScript("OnHide",hide)
                            reset:SetPoint("TOPRIGHT",0,0)
                        end
                    end
                    return 400,48
                end
                options[#options+1]=row
            end
            row.children[#row.children+1]=item
        end
    end
    return options
end
function Options:RestoreAppearance(scope,id)
    return self:Command(function(db)
        local target=scope=="instance" and db.instances[id].appearance or db.bars[id].appearance
        for _,key in ipairs(commonKeys)do target[key]=nil end
    end,id)()
end

function Options:SliderRow(fields)
    return {type="custom",width=400,children=fields,render=function(parent,x,y)
        local gui=self.designer.gui
        local width=#fields==1 and 400 or 194
        if #fields==1 then
            local spec={};for k,v in pairs(fields[1])do spec[k]=v end
            spec.width=400;spec.inline=true;spec.inputWidth=48;spec.labelWidth=132
            local slider=gui.Form:CreateSlider(parent,spec);slider:SetPoint("TOPLEFT",x,y)
            return 400,28
        end
        for index,item in ipairs(fields)do
            local cell=gui:CreateFrame(parent,{width=width,height=66})
            cell:SetPoint("TOPLEFT",x+(index-1)*206,y)
            local label=gui:CreateText(cell,item.label,"font.size.md","color.text.primary")
            label:SetPoint("TOPLEFT");label:SetWidth(width);label:SetHeight(32);label:SetWordWrap(true);label:SetJustifyH("LEFT")
            local spec={};for k,v in pairs(item)do spec[k]=v end
            spec.label=nil;spec.width=width;spec.inline=true;spec.inputWidth=48
            local slider=gui.Form:CreateSlider(cell,spec);slider:SetPoint("TOPLEFT",0,-36)
        end
        return 400,66
    end}
end
function Options:Bar(id,tab)
    local bridge=self.bridge
    local function bar()return bridge:GetModel().bars[id]end
    if tab=="appearance" then
        local Surface=bridge.lib.Surface
        local function resolved()return Surface.Resolve(bar().surface)end
        local function edit(key)
            return self:Command(function(db,v)
                local target=db.bars[id]
                local preset,color,border=Surface.Resolve(target.surface)
                local surface=target.surface or {}
                local emptyColors=surface.color==nil and surface.borderColor==nil
                target.surface=surface
                surface.preset=preset;surface.color=bridge.lib.Model.Copy(color);surface.borderColor=bridge.lib.Model.Copy(border)
                surface[key]=v
                if key=="preset" and preset=="none" and v~="none" and emptyColors then
                    surface.color=nil;surface.borderColor=nil
                end
            end,id)
        end
        local options={self:Section("background"),self:Field("dropdown","background",resolved,
            edit("preset"),{options=self:Choices({"none","solid","rounded","legacy"})})}
        local preset=resolved()
        if preset=="legacy" then
            local textures={}
            for name in pairs(LibStub("LibSharedMedia-3.0"):HashTable("statusbar")) do textures[#textures+1]={text=name,value=name} end
            table.sort(textures,function(a,b)return a.text<b.text end)
            options[#options+1]=self:Field("dropdown","texture",function()return (bar().surface or {}).texture end,
                edit("texture"),{options=textures})
        end
        if preset~="none" then
            local mode=self:Field("dropdown",preset=="legacy" and "texture_palette" or "background_palette",
                function()return (bar().surface or {}).classColor==true and "class" or "custom" end,
                function(v)return edit("classColor")(v=="class")end,{width=320,options=self:Choices({"custom","class"})})
            local fields={mode}
            if not (bar().surface or {}).classColor then
                fields[2]=self:Field("color","background_color",function()local _,color=resolved();return color end,
                    function(v)
                        local _,color=resolved()
                        return edit("color")({v[1],v[2],v[3],color[4] or 1})
                    end,{width=48,hasAlpha=false,getDefault=function()
                        local currentPreset=resolved()
                        local _,color=Surface.Resolve({preset=currentPreset})
                        return color
                    end})
            end
            options[#options+1]={type="custom",width=400,children=fields,render=function(parent,x,y)
                local gui=self.designer.gui
                local label=gui:CreateText(parent,mode.label,"font.size.md","color.text.primary")
                label:SetPoint("TOPLEFT",x,y)
                local dropdown=gui.Form:CreateDropdown(parent,{width=320,options=mode.options,get=mode.get,set=mode.set})
                dropdown:SetPoint("TOPLEFT",x,y-22)
                if fields[2] then
                    local picker=gui.Form:CreateColorPicker(parent,{width=48,hasAlpha=false,get=fields[2].get,set=fields[2].set,getDefault=fields[2].getDefault})
                    picker:SetPoint("TOPLEFT",x+336,y-22)
                end
                return 400,58
            end}
            options[#options+1]=self:Field("slider","background_opacity",
                function()local _,color=resolved();return (color[4] or 1)*100 end,
                function(v)
                    local _,color=resolved()
                    return edit("color")({color[1],color[2],color[3],v/100})
                end,{min=0,max=100,step=1,width=400,inline=true,inputWidth=56})
            options[#options+1]=self:Field("color","borderColor",
                function()local _,_,border=resolved();return border end,edit("borderColor"),{hasAlpha=true,getDefault=function()
                    local currentPreset=resolved()
                    local _,_,border=Surface.Resolve({preset=currentPreset})
                    return border
                end})
        end
        for _,item in ipairs(self:Appearance("bar",id)) do options[#options+1]=item end
        return options
    end
    local options={self:Section("layout")}
    if bar().kind=="independent" then
        options[#options+1]=self:Field("editbox","name",function()return bar().name or id end,
            self:Command(function(db,v)db.bars[id].name=v end,id))
        options[#options+1]=self:Field("dropdown","orientation",function()return bar().orientation or "horizontal"end,
            self:Command(function(db,v)db.bars[id].orientation=v end,id),{options=self:Choices({"horizontal","vertical"})})
        options[#options+1]=self:Field("dropdown","length_mode",function()return bar().sizing or "auto"end,
            self:Command(function(db,v)db.bars[id].sizing=v;db.bars[id].length=db.bars[id].length or 300 end,id),{options=self:Choices({"auto","fixed"})})
        if bar().sizing=="fixed" then
            options[#options+1]=self:Field("slider","length",function()return bar().length or 300 end,
                self:Command(function(db,v)db.bars[id].length=v end,id),{min=40,max=1600,step=1})
        end
    end
    for _,key in ipairs({"spacing","minCrossSize"}) do
        options[#options+1]=self:Field("slider",key,function()return bar()[key] or 0 end,
            self:Command(function(db,v)db.bars[id][key]=v end,id),{min=0,max=key=="spacing" and 500 or 80,step=1})
    end
    options[#options+1]=self:Section("section_padding")
    local paddingRow
    for i,key in ipairs({"before","after","crossBefore","crossAfter"}) do
        if i%2==1 then
            paddingRow={type="row",gap=12,rowGap=12,children={}}
            options[#options+1]=paddingRow
        end
        paddingRow.children[#paddingRow.children+1]=self:Field("slider","padding_"..key,function()return (bar().padding or {})[key] or 0 end,
            self:Command(function(db,v)local b=db.bars[id];b.padding=b.padding or {};b.padding[key]=v end,id),
            {min=0,max=40,step=1,width=194,inline=true,inputWidth=48})
    end
    options[#options+1]=self:Section("visibility")
    options[#options+1]=self:Field("checkbox","enabled",function()return bar().enabled~=false end,
        self:Command(function(db,v)db.bars[id].enabled=v end,id),{tooltip=self:Label("enabled_help")} )
    if bar().kind=="independent" then
        options[#options+1]={type="button",label=self:Label("delete_bar"),width=220,onClick=function()
            self.designer:DeleteBar(id)
        end}
    end
    for index,item in ipairs(options)do
        if item.type=="slider" then options[index]=self:SliderRow({item})
        elseif item.type=="row" and item.children[1] and item.children[1].type=="slider" then
            options[index]=self:SliderRow(item.children)
        end
    end
    return options
end
function Options:Alignment(id)
    local db=self.bridge:GetModel()
    local bar,_,index=self.M.FindBar(db,id)
    if not bar then return "LEFT" end
    if bar.centerInstanceId==id then return "CENTER" end
    if db.instances[id].alignment then return db.instances[id].alignment end
    local _,_,centerIndex=self.M.FindBar(db,bar.centerInstanceId)
    return centerIndex and index>centerIndex and "RIGHT" or "LEFT"
end
function Options:AppendVerticalLayout(options,id)
    local bar=self.M.FindBar(self.bridge:GetModel(),id)
    if not bar or bar.orientation=="vertical" then return end
    local function instance()return self.bridge:GetModel().instances[id]end
    options[#options+1]=self:Field("checkbox","expand_bar_height",function()return instance().expandBarHeight~=false end,
        self:Command(function(db,v)db.instances[id].expandBarHeight=v end,id),{width=312})
    options[#options+1]=self:Field("dropdown","vertical_alignment",function()return instance().verticalAlignment or "CENTER" end,
        self:Command(function(db,v)db.instances[id].verticalAlignment=v end,id),{width=312,options={
            {text=self:Label("vertical_top"),value="TOP"},{text=self:Label("vertical_center"),value="CENTER"},
            {text=self:Label("vertical_bottom"),value="BOTTOM"}}})
    options[#options+1]=self:Field("slider","vertical_offset",function()return instance().verticalOffset or 0 end,
        self:Command(function(db,v)db.instances[id].verticalOffset=v end,id),{min=-200,max=200,step=1,width=312,
            tooltip=self:Label("vertical_offset_help")})
end
function Options:QuickInstance(id)
    local alignment=self:Alignment(id)
    local buttons={}
    for _,value in ipairs({"LEFT","CENTER","RIGHT"})do
        local direction=value
        buttons[#buttons+1]={type="button",label=self:Label("align_"..direction),width=101,
            selected=alignment==direction,onClick=self:Command(function(db)return self.M.Align(db,id,direction)end,id)}
    end
    local options={{type="row",children=buttons}}
    if alignment~="CENTER" then
        options[#options+1]=self:Field("slider",alignment=="LEFT" and "left_gap" or "right_gap",function()
            return self.bridge:GetModel().instances[id].anchorGap or 0
        end,self:Command(function(db,v)db.instances[id].anchorGap=v end,id),{min=-50,max=500,step=1,width=312})
    end
    self:AppendVerticalLayout(options,id)
    return options
end
function Options:QuickBar(id)
    local options={}
    for _,key in ipairs({"minCrossSize","spacing"})do
        local field=key
        options[#options+1]=self:Field("slider",field,function()return self.bridge:GetModel().bars[id][field]or 0 end,
            self:Command(function(db,v)db.bars[id][field]=v end,id),{min=0,max=field=="spacing" and 500 or 80,step=1,width=312,
                label=self:Label(field=="minCrossSize" and (self.bridge:GetModel().bars[id].orientation=="vertical" and "min_width" or "min_height") or field)})
    end
    return options
end
function Options:Instance(id,tab)
    local bridge,M=self.bridge,self.M
    local function instance()return bridge:GetModel().instances[id]end
    if tab=="appearance" then return self:Appearance("instance",id) end
    if tab=="layout" then
        local options={self:Field("dropdown","location",function()local _,barId=M.FindBar(bridge:GetModel(),id);return barId or "unplaced"end,
            self:Command(function(db,v)return M.Move(db,id,v~="unplaced" and v or nil)end,id),{options=function()return self.designer:BarChoices(true)end})}
        local bar,barId,index=M.FindBar(bridge:GetModel(),id)
        if bar then
            options[#options+1]={type="row",children={
                {type="button",label=self:Label("previous"),width=140,disabled=index==1,onClick=self:Command(function(db)return M.Move(db,id,barId,index-1)end,id)},
                {type="button",label=self:Label("next"),width=140,disabled=index==#bar.items,onClick=self:Command(function(db)return M.Move(db,id,barId,index+1)end,id)}}}
            local alignmentButtons={}
            for _,alignment in ipairs({"LEFT","CENTER","RIGHT"}) do
                local value=alignment
                alignmentButtons[#alignmentButtons+1]={type="button",label=self:Label("align_"..value),width=94,
                    onClick=self:Command(function(db)return M.Align(db,id,value)end,id)}
            end
            options[#options+1]={type="row",children=alignmentButtons}
        end
        if self:Alignment(id)~="CENTER" then
            options[#options+1]=self:Field("slider",self:Alignment(id)=="LEFT" and "left_gap" or "right_gap",
                function()return instance().anchorGap or 0 end,
                self:Command(function(db,v)db.instances[id].anchorGap=v end,id),{min=-50,max=500,step=1})
        end
        self:AppendVerticalLayout(options,id)
        options[#options+1]=self:Field("dropdown","visibility",function()
            return instance().visibility or bridge.original.GetModuleDisplayMode(bridge.ybar,instance().moduleType)
        end,
            self:Command(function(db,v)db.instances[id].visibility=v end,id),{options=self:Choices({"ALWAYS","MOUSEOVER","GROUP1","GROUP2","GROUP3","GROUP4","GROUP5","GROUP6"})})
        local cap=bridge.adapters[instance().moduleType]
        if cap and cap.multi then
            options[#options+1]={type="button",label=self:Label("duplicate"),width=220,onClick=function()self.designer:Duplicate(id)end}
        end
        if cap and cap.multi or barId then
            options[#options+1]={type="button",label=self:Label(cap and cap.multi and "delete_instance" or "remove_from_bar"),width=220,onClick=function()
                self.designer:DeleteInstance(id)
            end}
        end
        return options
    end
    local view=bridge.runtime.views[id]
    if not view then
        local ok,result=pcall(bridge.NewView,bridge,id,instance())
        if ok and result then view=result;bridge.runtime.views[id]=view end
    end
    local module=view and view.module
    if not module or not module.GetOptions then return {{type="text",label=self:Label("unloaded")}} end
    module.RunConfigEdit=function(_,callback,...)
        local args={...}
        return (bridge.session or bridge.settingsSession):Edit(function()return callback(unpack(args))end,id)
    end
    local commonLabels={[self.C["common.font"]]=true,[self.C["common.size"]]=true,[self.C["common.font_size"]]=true}
    local capability=bridge.adapters[instance().moduleType]
    if capability and capability.appearance.display then
        commonLabels[self.L["feature.display"]]=true
        commonLabels[self.L["tracking.style"]]=true
        commonLabels[self.C["common.show_icon"]]=true
        if instance().moduleType=="RaidMarkers" or instance().moduleType=="MeetingStone" then
            commonLabels[self.L["ybar.settings.option.appearance"]]=true
        end
    end
    if capability and capability.appearance.iconBackground then commonLabels[self.L["bugsack.option.icon_background"]]=true end
    commonLabels[self.L["ybar.settings.section.info_bar"]]=true
    local function wrap(items)
        local result={}
        for _,original in ipairs(items) do
            if not commonLabels[original.label] then
                local item={}
                for k,v in pairs(original) do item[k]=v end
                if item.children then item.children=wrap(item.children) end
                if item.type=="slider" then item.instantUpdate=true end
                if item.width and item.type~="custom" and item.type~="custom-gui" then
                    item.width=math.min(item.width,(item.type=="text" or item.type=="divider") and 440 or 220)
                end
                for _,key in ipairs({"set","onClick","onFocusLost"}) do
                    local callback=item[key]
                    if callback and not item.transient then item[key]=function(...)
                        local args={...}
                        local ok,reason=(bridge.session or bridge.settingsSession):Edit(function()return callback(unpack(args))end,id)
                        if ok then bridge:QueueDesignerRefresh(id) end
                        return ok,reason
                    end end
                end
                if not item.children or #item.children>0 then result[#result+1]=item end
            end
        end
        return result
    end
    local result=wrap(module:GetOptions())
    result[#result+1]=self:Section("visibility")
    result[#result+1]=self:Field("dropdown","visibility",function()
        return instance().visibility or bridge.original.GetModuleDisplayMode(bridge.ybar,instance().moduleType)
    end,self:Command(function(db,v)db.instances[id].visibility=v end,id),
        {options=self:Choices({"ALWAYS","MOUSEOVER","GROUP1","GROUP2","GROUP3","GROUP4","GROUP5","GROUP6"})})
    return result
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Options=Options
end
return Options
