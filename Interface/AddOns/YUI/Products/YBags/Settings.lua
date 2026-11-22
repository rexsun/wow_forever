local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local S,G,A=YUI.Settings,YUI.GUI2,YUI.API.Bags
local Render
local pageWidth=740
local forever=B.client=="forever"
local tabs=forever and {"general","bags","bank","guild","rules","cache"} or {"appearance","rules","deposit","currencies","cache"}
local sections={bags={"layout","currencies"},bank={"personal","shared"}}
local aliases={appearance="general",layout="bags",currencies="bags",personal="bank",shared="bank",deposit="guild"}
local state={rule=1,target="bank",currencyQuery="",peerDraft="",currencyKind="currency",currencyID=""}
function B:SetSettingsRoute(tab,subtab)
    if tab==nil then tab,subtab=self.SettingsTab,self.SettingsSubtab end
    if forever then
        if aliases[tab] then subtab,tab=tab,aliases[tab] end
        if tab=="bags" then subtab=subtab=="currencies" and "currencies" or "layout"
        elseif tab=="bank" then subtab=subtab=="shared" and "shared" or "personal"
        else
            subtab=nil
            if tab~="guild" and tab~="cache" and tab~="rules" then tab="general" end
        end
    else
        if tab=="bags" then tab=subtab=="currencies" and "currencies" or "appearance"
        elseif tab=="bank" or tab=="personal" or tab=="shared" or tab=="guild" then
            state.target=tab=="guild" and "guild" or (tab=="shared" or subtab=="shared") and "shared" or "bank"
            tab="deposit"
        elseif tab~="deposit" and tab~="currencies" and tab~="cache" and tab~="rules" then tab="appearance" end
        subtab=nil
    end
    self.SettingsTab,self.SettingsSubtab=tab,subtab
end
local function T(key) return B:T(key) end
local function Rerender(parent) S:ClearConfig(parent);Render(parent) end
local function Action(label,callback,tone)
    return {type="button",text=label,controlWidth=176,height=26,onClick=callback,tone=tone}
end
local function Input(label,value,set)
    return {type="custom",label=label,render=function(container,control,width)
        local committed=tostring(value or "")
        local function Commit(owner)
            local text=owner:GetText()
            if text~=committed then committed=text;set(text) end
        end
        local edit=G.Form:CreateEditBox(container,{width=math.min(width,control.width or width),height=26,text=committed,
            autoFocus=false,placeholder=control.placeholder,searchPlaceholder=control.searchPlaceholder,onFocusLost=Commit})
        edit:SetMaxLetters(160)
        edit:SetScript("OnEnterPressed",function(owner) Commit(owner);owner:ClearFocus() end)
        edit:SetScript("OnEscapePressed",function(owner) owner:SetText(committed);owner:ClearFocus() end)
        return edit
    end}
end
local function Group(options,key,fields,columns)
    options[#options+1]={type="custom",retainedFields=fields,render=function(container,x,y,width)
        width=math.min(width,pageWidth)
        if key then
            local divider=G:CreateDivider(container,{label=T(key),width=width,height=22,alignLeft=true})
            divider:SetPoint("TOPLEFT",x,y)
        end
        local offset=key and 30 or 0
        local _,w,h=S:RenderAlignedFields(container,{x=x,y=y-offset,width=width,columns=columns or 2,
            labelPosition="top",minColumnWidth=220,columnGap=24,rowGap=8,rowHeight=28,fields=fields})
        return w,h+offset
    end}
end
local function Summary(label,text)
    return {type="custom",label=label,span="full",render=function(container,_,width)
        local line=G:CreateText(container,text,12,"color.text.secondary");line:SetWidth(width);line:SetJustifyH("LEFT");line:SetWordWrap(true)
        line:SetHeight(math.max(18,line:GetStringHeight()));return line
    end}
end
local function Check(label,get,set)
    return {type="checkbox",label=label,get=get,set=set}
end
local function Select(label,options,get,set)
    return {type="dropdown",label=label,options=options,get=get,set=set}
end
local function ShortSelect(label,options,get,set)
    local field=Select(label,options,get,set)
    field.layoutPreset="inlineSelector"
    return field
end
local function Options(ids,prefix)
    local result={};for _,id in ipairs(ids) do result[#result+1]={value=id,text=T(prefix..id)} end;return result
end
local function Confirm(text,callback)
    S:ShowConfirmPopup(text,callback,{titleText=T("action.confirm"),acceptTone="danger"})
end
local textPreview
local function ItemTextPreview(parent)
    if textPreview then
        textPreview:SetParent(parent);textPreview:ClearAllPoints();textPreview:Show()
        return textPreview
    end
    local appearance=B.Appearance
    local preview=G:CreateFrame(parent,{width=160,height=50})
    local gearItem,potionItem={icon=132536,quality=3},{icon=134856,quality=1}
    local questItem={icon="Interface\\Icons\\INV_Misc_Note_01",quality=1}
    local function Slot(item,count)
        local slot=appearance:Item(preview,false)
        slot:EnableMouse(false)
        SetItemButtonTexture(slot,item.icon)
        if SetItemButtonQuality then SetItemButtonQuality(slot,item.quality) end
        SetItemButtonCount(slot,count)
        slot:Show()
        return slot
    end
    local gear,potion,quest=Slot(gearItem,1),Slot(potionItem,79),Slot(questItem,1)
    gear:SetPoint("LEFT")
    potion:SetPoint("LEFT",gear,"RIGHT",8,0)
    quest:SetPoint("LEFT",potion,"RIGHT",8,0)
    local level=G:CreateText(gear,"92",13);level:SetPoint("TOPLEFT",1,-1)
    local bind=G:CreateText(gear,T("item.bind_on_equip"),11);bind:SetPoint("BOTTOMLEFT",2,2)
    local countdown=G:CreateText(potion,"1:32",14)
    local r,g,b=YUI.API.Item.GetQualityColor(3)
    level:SetTextColor(r,g,b);bind:SetTextColor(r,g,b)
    function preview:RefreshText(size)
        local style,styles=appearance:ItemTextStyle(size)
        appearance:RefreshIconStyle()
        gear:SetSize(size,size);potion:SetSize(size,size);quest:SetSize(size,size)
        appearance:CellAppearance(gear,false,gearItem)
        appearance:CellAppearance(potion,false,potionItem)
        appearance:CellAppearance(quest,false,questItem)
        appearance:CellQuest(quest,"starter")
        G:ApplyFontAppearance(level,style.level)
        G:ApplyFontAppearance(bind,style.bind)
        appearance:ApplyItemCountText(potion,style.count)
        local recipe=appearance.iconRecipe
        local width,height=G:GetIconAppearanceSize(size,recipe and recipe.shape or "square")
        local cooldownStyle,offset=appearance:ItemCountdownStyle(math.min(width,height),styles,size,style.count.size)
        appearance:ApplyItemCountdownText(countdown,potion,cooldownStyle,offset)
    end
    textPreview=preview
    return preview
end
local function InlineWindowFields(options,fields,group)
    for _,field in ipairs(fields) do
        field.labelPosition,field.labelWidth="left",96
        field.minControlWidth=field.minControlWidth or 140
    end
    Group(options,group or "settings.group.window",fields)
end
local function General(parent,options,c)
    local function SetRecipeTint(key,value) c[key]=value;B.View:RefreshRecipeTints() end
    local preview
    local function RefreshPreview()
        if preview then preview:RefreshText(c.slotSize) end
    end
    local function SetItemText(key,value)
        if c[key]==value then return end
        c[key]=value
        B.View:RefreshItemText()
        RefreshPreview()
    end
    local iconSkin={type="custom",label=T("settings.icon_skin"),span="full",minControlWidth=180,
        render=function(container,_,width)
            return G.Form:CreateIconSkinControl(container,{
                width=math.min(248,width),product=B.PRODUCT_ID,native=true,builtinOnly=true,
                getPopupAnchor=function() return S.Elements and S.Elements.frame or parent end,
                getStyle=function() return B:GetIconSkin() end,
                getContext=function() return {groupId=B:GetConfig().skin} end,
                set=function(style) B:SetIconSkin(style);RefreshPreview() end,
            })
        end}
    InlineWindowFields(options,{
        ShortSelect(T("settings.skin"),Options({"native","minimal"},"skin."),function() return c.skin end,function(v)
            c.skin=v;B.View:ApplySkin()
            if iconSkin.widget then iconSkin.widget:Refresh() end
            RefreshPreview()
        end),
        iconSkin,
        {type="slider",label=T("settings.opacity"),min=.6,max=1,step=.05,get=function() return c.opacity end,set=function(v) c.opacity=v;B.View:ApplySkin(true) end},
    },"settings.group.shared_appearance")
    local defaultFont=B:GetDefaultItemFont()
    Group(options,"settings.group.items",{
        {type="font",label=T("settings.item_font"),searchKey="settings.item_font",
            get=function() return c.itemFont=="default" and defaultFont or c.itemFont end,
            set=function(v) SetItemText("itemFont",v==defaultFont and "default" or v) end},
        {type="slider",label=T("settings.item_text_scale"),searchKey="settings.item_text_scale",min=80,max=130,step=1,
            instantUpdate=false,get=function() return c.itemTextScale end,set=function(v) SetItemText("itemTextScale",v) end},
        {type="custom",label=T("settings.item_text_preview"),span="full",render=function(container)
            preview=ItemTextPreview(container);RefreshPreview();return preview
        end},
        Check(T("settings.tint_unusable_recipes"),function() return c.tintUnusableRecipes end,function(v) SetRecipeTint("tintUnusableRecipes",v) end),
        Check(T("settings.tint_known_recipes"),function() return c.tintKnownRecipes end,function(v) SetRecipeTint("tintKnownRecipes",v) end),
    })
    local export=Action(T("action.export"),function()
        B.View:Dialog(T("action.export"),{{label=T("settings.share"),value=B:ExportConfig(),max=131072}},function() end)
        local edit=B.View.dialog.inputs[1].edit;edit:SetFocus();edit:HighlightText()
    end,"default")
    local import=Action(T("action.import"),function()
        B.View:Dialog(T("action.import"),{{label=T("settings.share"),max=131072}},function(values)
            if not B:ImportConfig(values[1]) then B:Notify("error.import");return false end
            Rerender(parent)
        end)
    end,"default")
    Group(options,"settings.group.transfer",{export,import})
end
local function BagLayout(parent,options,c)
    local function Set(key,value)
        c[key]=value;B.View:Invalidate();B:RefreshVisible(true);B.View:ApplySkin(true)
    end
    InlineWindowFields(options,{
        ShortSelect(T("settings.layout"),Options({"category","single"},"layout."),function() return c.layout end,function(v)
            if B.View.windows.player then B.View.windows.player.layout=nil end
            Set("layout",v);Rerender(parent)
        end),
        Check(T("settings.auto_size"),function() return c.autoSize end,function(v) Set("autoSize",v);Rerender(parent) end),
        {type="slider",label=T("settings.slot_size"),min=30,max=48,step=1,get=function() return c.slotSize end,set=function(v)
            Set("slotSize",v)
            if not forever and textPreview then textPreview:RefreshText(v) end
        end},
        {type="slider",label=T("settings.columns"),tooltip=T("settings.columns_hint"),min=6,max=24,step=1,disabled=c.autoSize,
            get=function() return c.columns end,set=function(v) Set("columns",v) end},
    })
    local subnames=Check(T("settings.subnames"),function() return c.showSubnames end,function(v) Set("showSubnames",v) end)
    local aggregate=Check(T("settings.aggregate"),function() return c.aggregateItems end,function(v) Set("aggregateItems",v) end)
    subnames.disabled,aggregate.disabled=c.layout=="single",c.layout=="single"
    subnames.tooltip,aggregate.tooltip=T("settings.category_hint"),T("settings.category_hint")
    local fields={subnames,aggregate,
        ShortSelect(T("settings.empty"),Options({"all","one"},"empty."),function() return c.emptyMode end,function(v) Set("emptyMode",v) end),
        Action(T("action.clear_recent"),function() B.Actions:ClearRecent() end,"default"),
    }
    if forever then
        local function RefreshCombinedLayout()
            local w=B.View.windows.player
            if B.active and w then
                if w.open then B.View:Layout(w,true)
                elseif not YUI.API.Bags.InCombat() then
                    w.prepared=false
                    B.View:PreparePlayer()
                end
            end
        end
        local direction=ShortSelect(T("settings.combined_sort_direction"),Options({"forward","reverse"},"sort_direction."),
            function() return c.combinedSortDirection end,function(v) c.combinedSortDirection=v end)
        local wrap=Check(T("settings.combined_wrap_special_bags"),function() return c.combinedWrapSpecialBags end,function(v)
            if c.combinedWrapSpecialBags==v then return end
            c.combinedWrapSpecialBags=v
            RefreshCombinedLayout()
        end)
        direction.disabled,wrap.disabled=c.layout~="single",c.layout~="single"
        direction.tooltip,wrap.tooltip=T("settings.combined_hint"),T("settings.combined_hint")
        direction.searchKey,wrap.searchKey="settings.combined_sort_direction","settings.combined_wrap_special_bags"
        fields[#fields+1]=direction
        fields[#fields+1]=wrap
    end
    Group(options,"settings.group.items",fields)
end
local function Bank(parent,options,c)
    local bank=c.bankView
    local layout=ShortSelect(T("settings.bank_layout"),Options({"category","single"},"layout."),function() return bank.layout end,function(v)
        B:SetBankViewOption("layout",v);Rerender(parent)
    end)
    layout.searchKey="settings.bank_layout"
    local fields={
        layout,
        Check(T("settings.auto_size"),function() return bank.autoSize end,function(v)
            B:SetBankViewOption("autoSize",v);Rerender(parent)
        end),
        {type="slider",label=T("settings.slot_size"),min=30,max=48,step=1,
            get=function() return bank.slotSize end,set=function(v) B:SetBankViewOption("slotSize",v) end},
        {type="slider",label=T("settings.columns"),tooltip=T("settings.columns_hint"),min=6,max=24,step=1,disabled=bank.autoSize,
            get=function() return bank.columns end,set=function(v) B:SetBankViewOption("columns",v) end},
    }
    fields[2].searchKey,fields[3].searchKey,fields[4].searchKey="settings.bank_auto_size","settings.bank_slot_size","settings.bank_columns"
    Group(options,"settings.group.window",fields)
    local subnames=Check(T("settings.subnames"),function() return bank.showSubnames end,function(v)
        B:SetBankViewOption("showSubnames",v)
    end)
    subnames.disabled=bank.layout=="single"
    subnames.tooltip=T("settings.category_hint")
    local empty=ShortSelect(T("settings.empty"),Options({"all","one"},"empty."),function() return bank.emptyMode end,function(v)
        B:SetBankViewOption("emptyMode",v)
    end)
    subnames.searchKey,empty.searchKey="settings.bank_subnames","settings.bank_empty"
    Group(options,"settings.group.items",{subnames,empty})
end

local function Rules(parent,options,c)
    local sections={};for _,id in ipairs(B.Classification.sections) do if id~="system" then sections[#sections+1]=T("section."..id) end end
    Group(options,"rules.builtin",{Summary(nil,table.concat(sections,"  ·  "))})
    local rules={}
    for n,rule in ipairs(c.rules) do rules[#rules+1]={value=n,text=rule.name or rule.id} end
    local picker
    if #rules>0 then
        state.rule=math.min(state.rule,#rules)
        picker=ShortSelect(T("rules.select"),rules,function() return state.rule end,function(v) state.rule=v;Rerender(parent) end)
    else picker=Summary(nil,T("rules.empty"));picker.span=1 end
    local add=Action(T("rules.add"),function()
        local id
        repeat
            state.serial=(state.serial or 0)+1;id="rule-"..time().."-"..state.serial
            local found=false;for _,existing in ipairs(c.rules) do if existing.id==id then found=true end end
            if not found then break end
        until false
        c.rules[#c.rules+1]={id=id,name=T("rules.new"),section="other",priority=0,order=0,contains="",enabled=true}
        state.rule=#c.rules;B:ConfigChanged();Rerender(parent)
    end)
    Group(options,"rules.custom",{picker,add})
    local rule=c.rules[state.rule]
    if not rule then return end
    local function Set(key,value) rule[key]=value;B:ConfigChanged() end
    Group(options,"settings.group.rule_details",{
        Input(T("rules.name"),rule.name,function(v) Set("name",v) end),
        Select(T("rules.section"),Options({"general","consumable","equipment","material","system","other"},"section."),
            function() return rule.section end,function(v) Set("section",v) end),
        Input(T("rules.priority"),rule.priority or 0,function(v) Set("priority",tonumber(v) or 0) end),
        Input(T("rules.order"),rule.order or 0,function(v) Set("order",tonumber(v) or 0) end),
        Check(T("rules.enabled"),function() return rule.enabled~=false end,function(v) Set("enabled",v) end),
    })
    local classes=YUI.API.Bags.ClassOptions();table.insert(classes,1,{value=-1,text=T("rules.all")})
    local qualities={{value=-1,text=T("rules.all")}}
    for id=0,7 do qualities[#qualities+1]={value=id,text=_G["ITEM_QUALITY"..id.."_DESC"] or tostring(id)} end
    local slots={{value="",text=T("rules.all")}}
    for _,id in ipairs({"INVTYPE_WEAPON","INVTYPE_2HWEAPON","INVTYPE_WEAPONMAINHAND","INVTYPE_WEAPONOFFHAND","INVTYPE_SHIELD","INVTYPE_HOLDABLE","INVTYPE_HEAD","INVTYPE_NECK","INVTYPE_SHOULDER","INVTYPE_CLOAK","INVTYPE_CHEST","INVTYPE_ROBE","INVTYPE_WRIST","INVTYPE_HAND","INVTYPE_WAIST","INVTYPE_LEGS","INVTYPE_FEET","INVTYPE_FINGER","INVTYPE_TRINKET","INVTYPE_RANGED","INVTYPE_RANGEDRIGHT","INVTYPE_RELIC","INVTYPE_BODY","INVTYPE_TABARD"}) do slots[#slots+1]={value=id,text=_G[id] or id} end
    local matchAny=Check(T("rules.any"),function() return rule.any==true end,function(v) Set("any",v) end)
    matchAny.span="full";matchAny.tooltip=T("settings.match_hint")
    Group(options,"settings.group.conditions",{
        matchAny,
        Input(T("rules.contains"),rule.contains,function(v) Set("contains",v) end),
        Input(T("rules.exclude"),rule.exclude,function(v) Set("exclude",v) end),
        ShortSelect(T("rules.class"),classes,function() return rule.classID or -1 end,function(v) Set("classID",v~=-1 and v or nil) end),
        ShortSelect(T("rules.quality"),qualities,function() return rule.quality or -1 end,function(v) Set("quality",v~=-1 and v or nil) end),
        ShortSelect(T("rules.equip"),slots,function() return rule.equipLoc or "" end,function(v) Set("equipLoc",v) end),
        Input(T("rules.level"),rule.minLevel,function(v) Set("minLevel",tonumber(v)) end),
    })
    local preview=Action(T("rules.preview"),function(owner)
        local count=0
        for _,item in ipairs(B.Model:List(YUI.API.Bags.GetCarryBags(false))) do if B.Classification:RuleMatches(rule,item) then count=count+1 end end
        B.View:Menu(owner or UIParent,{{text=string.format(T("rules.matches"),count)}})
    end)
    local delete=Action(T("rules.delete"),function()
        Confirm(string.format(T("rules.delete_confirm"),rule.name or rule.id),function()
            if B:GetConfig()~=c then return end
            for index,entry in ipairs(c.rules) do
                if entry==rule then table.remove(c.rules,index);state.rule=math.max(1,index-1);B:ConfigChanged();Rerender(parent);return end
            end
        end)
    end,"danger")
    Group(options,nil,{preview,delete})
end
local function Deposit(parent,options,c,target)
    local rule=c.deposit[target or state.target]
    local fields={}
    if not target then
        fields[1]=Select(T("deposit.target"),Options({"bank","shared","guild"},"cache."),function() return state.target end,function(v) state.target=v;Rerender(parent) end)
    end
    local mode=Select(T("deposit.mode"),Options({"materials","existing","custom"},"deposit."),function() return rule.mode end,function(v) rule.mode=v;Rerender(parent) end)
    fields[#fields+1]=mode
    Group(options,"settings.group.deposit_rule",fields)
    local filters={
        Input(T("rules.contains"),rule.contains,function(v) rule.contains=v end),
        Input(T("rules.exclude"),rule.exclude,function(v) rule.exclude=v end),
        Input(T("deposit.keep"),rule.keep,function(v) rule.keep=math.max(0,math.min(100000,math.floor(tonumber(v) or 0))) end),
    }
    filters[3].controlWidth=120
    if target then
        local prefix="settings."..target.."_"
        mode.searchKey=prefix.."mode"
        filters[1].searchKey,filters[2].searchKey,filters[3].searchKey=prefix.."contains",prefix.."exclude",prefix.."keep"
    end
    if rule.mode=="custom" then
        local classes=YUI.API.Bags.ClassOptions();table.insert(classes,1,{value=-1,text=T("rules.all")})
        filters[#filters+1]=Select(T("rules.class"),classes,function() return rule.classID or -1 end,function(v) rule.classID=v~=-1 and v or nil end)
    end
    Group(options,"settings.group.deposit_filter",filters)
end
local function Guild(parent,options,c)
    local view=c.guildView
    Group(options,"settings.group.guild_display",{
        {type="slider",label=T("settings.guild_slot_size"),min=30,max=48,step=1,
            get=function() return view.slotSize end,set=function(v) B:SetGuildViewOption("slotSize",v) end},
        Check(T("settings.guild_subnames"),function() return view.showSubnames end,function(v) B:SetGuildViewOption("showSubnames",v) end),
    })
    Deposit(parent,options,c,"guild")
    Group(options,nil,{Summary(nil,T("deposit.preset_scope"))},1)
end
local function Currencies(parent,options,c)
    local function Key(entry) return entry.kind..":"..entry.id end
    local function Selected()
        for _,entry in ipairs(c.tracked) do if Key(entry)==state.tracked then return entry end end
        return c.tracked[1]
    end
    local order=Select(T("currency.order"),function()
        local values={}
        for _,entry in ipairs(c.tracked) do
            local info=B.Currency:Info(entry.kind,entry.id)
            values[#values+1]={value=Key(entry),text=info.name or tostring(entry.id),icon=info.icon}
        end
        return values
    end,function()
        local entry=Selected()
        return entry and Key(entry)
    end,function(v) state.tracked=v end)
    order.placeholder=T("settings.no_tracked_currency")
    local RefreshOrder
    local first=Action(T("currency.first"),function()
        local entry=Selected()
        if entry and #c.tracked>1 then B.Currency:First(entry.kind,entry.id);B.View:UpdateCurrencies();RefreshOrder() end
    end,"default")
    order.disabled,first.disabled=#c.tracked<2,#c.tracked<2
    RefreshOrder=function()
        local disabled=#c.tracked<2
        if order.widget then
            order.widget:SetValue(order.get(),{silent=true,animate=false,force=true})
            order.widget:SetDisabled(disabled)
            if order.labelRegion then G:SetTextColorKey(order.labelRegion,disabled and "color.text.disabled" or "color.text.primary") end
        end
        if first.widget then first.widget:SetDisabled(disabled) end
    end
    Group(options,"settings.group.tracked_currency",{order,first})

    local currencyID=Input(T("currency.custom_id"),state.currencyID,function(v) state.currencyID=v end)
    currencyID.controlWidth=148
    local add=Action(T("currency.add"),function()
        if B.Currency:Track(state.currencyKind,state.currencyID) then state.currencyID="";B.View:UpdateCurrencies();Rerender(parent)
        else B:Notify("currency.add_failed") end
    end)
    Group(options,"settings.group.custom_currency",{
        Select(T("currency.custom_type"),Options({"currency","item"},"currency.kind."),function() return state.currencyKind end,function(v) state.currencyKind=v end),
        currencyID,add,
    })

    local search=Input(T("action.search"),state.currencyQuery,function(v) if state.currencyQuery~=v then state.currencyQuery=v;Rerender(parent) end end)
    search.span="full";search.controlWidth=360;search.placeholder=T("settings.currency_search");search.searchPlaceholder=true
    local fields={search}
    for _,entry in ipairs(B.Currency:Candidates(state.currencyQuery)) do
        local id,kind=entry.id,entry.kind
        fields[#fields+1]=Check("|T"..tostring(entry.icon or 134400)..":16|t "..(entry.name or tostring(id)),function()
            for _,value in ipairs(c.tracked) do if value.kind==kind and value.id==id then return true end end
            return false
        end,function(v)
            if v then B.Currency:Track(kind,id) else B.Currency:Untrack(kind,id) end
            B.View:UpdateCurrencies();RefreshOrder()
        end)
    end
    if #fields==1 then fields[2]=Summary(nil,T("settings.no_matching_currency")) end
    Group(options,"settings.group.currency_list",fields)
end
local function RecordRow(name,actions,character)
    return {type="custom",span="full",render=function(container,_,width)
        local row=G:CreateFrame(container,{width=width,height=28})
        local gap=8
        local buttonWidth=math.min(124,math.floor((width-(#actions-1)*gap)/#actions))
        local remaining=width-#actions*buttonWidth-(#actions-1)*gap-16
        local portraitSize,left=character and 24 or 0,character and 50 or 0
        local stacked=remaining-left<160
        local title=name
        if character then
            local anchor=stacked and "TOPLEFT" or "LEFT"
            local race,_,r,g,b=A.CharacterAppearance(character)
            local portrait=B.Appearance:Portrait(row,portraitSize)
            portrait:SetPoint(anchor,0,0)
            B.Appearance:IdentityIcon(portrait,race and "atlas:"..race or 133785,.03)
            local classIcon=B.Appearance:ClassIconSlot(row,14)
            classIcon:SetPoint(anchor,30,stacked and -5 or 0)
            classIcon:SetShown(B.Appearance:ClassIcon(classIcon,character.classFile))
            title=string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+.5),math.floor(g*255+.5),
                math.floor(b*255+.5),(name:gsub("|","||")))
            if character.realm and character.realm~="" then title=title.." · "..character.realm:gsub("|","||") end
        end
        local label=G:CreateText(row,title,"font.size.md",character and "color.text.secondary" or "color.text.primary")
        label:SetWidth(math.max(1,(stacked and width or remaining)-left))
        label:SetJustifyH("LEFT");label:SetWordWrap(true)
        if label.SetNonSpaceWrap then label:SetNonSpaceWrap(true) end
        local height=label:GetStringHeight() or 0
        label:SetPoint(stacked and "TOPLEFT" or "LEFT",left,stacked and math.min(0,(height-portraitSize)/2) or 0)
        local titleHeight=math.max(portraitSize,height)
        row:SetHeight(stacked and titleHeight+34 or math.max(28,titleHeight))
        for index,action in ipairs(actions) do
            local button=G.Form:CreateButton(row,{text=action.text,width=buttonWidth,height=26,onClick=action.onClick,tone=action.tone})
            button:SetPoint(stacked and "BOTTOMRIGHT" or "RIGHT",-(#actions-index)*(buttonWidth+gap),0)
        end
        return row
    end}
end
local function Cache(parent,options)
    B.Cache.db=B:GetCacheDB()
    local peer=Input(T("sync.peer"),state.peerDraft,function(v) state.peerDraft=v end)
    local add=Action(T("sync.add"),function()
        if state.peerDraft~="" and B.Sync:Trust(state.peerDraft) then state.peerDraft="";Rerender(parent) end
    end)
    local peerFields={peer,add}
    local peers={}
    for name in pairs(B.Cache.db.peers) do peers[#peers+1]=name end
    table.sort(peers)
    for _,name in ipairs(peers) do
        peerFields[#peerFields+1]=RecordRow(name,{
            Action(T("sync.request"),function() if not B.Sync:Request(name) then B:Notify("sync.unavailable") end end),
            Action(T("sync.forget"),function() B.Sync:Forget(name);Rerender(parent) end,"default"),
        })
    end
    Group(options,"settings.group.trusted",peerFields)

    local records=B.Cache:List()
    local recordFields={}
    for _,entry in ipairs(records) do
        local key,character=entry.key,entry.data
        recordFields[#recordFields+1]=RecordRow(character.name,{
            Action(T("cache.delete"),function()
                Confirm(T("cache.delete_confirm"),function() B.Cache:Forget(key);Rerender(parent) end)
            end,"danger"),
        },character)
    end
    if #records==0 then recordFields[1]=Summary(nil,T("cache.none")) end
    Group(options,"settings.group.records",recordFields,1)
    if #records>0 then Group(options,"settings.group.cleanup",{
        Action(T("cache.delete_all"),function()
            Confirm(T("cache.delete_all_confirm"),function() B.Cache:Forget();Rerender(parent) end)
        end,"danger"),
    },1) end
end
local function Navigation(parent,ids,selected,main)
    return {type="custom",render=function(container,x,y,width)
        width=math.min(width,pageWidth)
        local bar=G.Form:CreateUnderlineTabs(container,{width=width,height=main and 26 or 30,overflow="scroll",
            showBaseline=not main,gap=16,value=selected,items=Options(ids,"settings.tab."),
            onChange=function(_,value)
                if main then B:SetSettingsRoute(main,value) else B:SetSettingsRoute(value) end
                Rerender(parent)
            end})
        bar:SetPoint("TOPLEFT",x,y);return width,bar:GetHeight()+4
    end}
end
Render=function(parent)
    local c=B:GetConfig()
    B:SetSettingsRoute()
    local tab,subtab=B.SettingsTab,B.SettingsSubtab
    local options={{type="custom",render=function(container,x,y,width)
        width=math.min(width,pageWidth)
        local header=G:CreateFrame(container,{width=width,height=32})
        header:SetPoint("TOPLEFT",x,y)
        local title=G:CreateText(header,T("product.title"),"font.size.title","color.text.heading");title:SetPoint("LEFT",0,0)
        local badge=G.Data:CreateBadge(header,{text=T("product.beta"),tone="orange",variant="solid",height=22,paddingX=8})
        badge:SetPoint("LEFT",title,"RIGHT",10,0)
        if tab=="general" or tab=="appearance" then
            local open=G.Form:CreateButton(header,{text=T("action.open"),width=math.min(144,math.floor(width*.42)),height=28,disabled=B.conflict~=nil,
                onClick=function() B:OpenBagsFromSettings() end})
            open:SetPoint("RIGHT",0,0)
            if S.Search then S.Search:Bind({searchKey="action.open"},open) end
        end
        return width,32
    end},Navigation(parent,tabs,tab)}
    if subtab then options[#options+1]=Navigation(parent,sections[tab],subtab,tab) end
    if B.conflict then Group(options,nil,{Summary(nil,string.format(T("settings.conflict"),B.conflict))},1) end
    if tab=="bank" and subtab=="shared" then Deposit(parent,options,c,"shared")
    elseif tab=="bank" then Bank(parent,options,c)
    elseif tab=="guild" then Guild(parent,options,c)
    elseif tab=="bags" and subtab=="currencies" then Currencies(parent,options,c)
    elseif tab=="bags" then BagLayout(parent,options,c)
    elseif tab=="rules" then Rules(parent,options,c)
    elseif tab=="deposit" then Deposit(parent,options,c)
    elseif tab=="currencies" then Currencies(parent,options,c)
    elseif tab=="cache" then Cache(parent,options)
    else
        General(parent,options,c)
        if not forever then BagLayout(parent,options,c) end
    end
    S:RenderConfig(parent,options)
    parent.ybagsSettingsTab,parent.ybagsSettingsSubtab=tab,subtab
end
local order=S.ModuleOrder
if type(order)=="table" then
    local found=false
    for _,id in ipairs(order) do if id==B.SETTINGS_ENTRY then found=true end end
    if not found then
        local index=#order+1
        for n,id in ipairs(order) do if id=="ymap.settings" or id=="suite.settings.sound" then index=n;break end end
        table.insert(order,index,B.SETTINGS_ENTRY)
    end
end
S:RegisterModule("YBags",133633,Render,{id=B.SETTINGS_ENTRY,product=B.PRODUCT_ID,scope=B.PRODUCT_ID,
    titleKey="product.title",titleNamespace="YBags",navTitleKey="product.nav",navTitleNamespace="YBags",navToggle={moduleId=B.PRODUCT_ID}})
if S.Search then
    local function Catalog(route,keys) S.Search:RegisterCatalog(B.SETTINGS_ENTRY,"YBags",route,keys) end
    local bagKeys="settings.layout settings.auto_size settings.subnames settings.aggregate settings.empty settings.columns settings.slot_size action.clear_recent"
    if forever then bagKeys=bagKeys.." settings.combined_sort_direction settings.combined_wrap_special_bags" end
    Catalog(forever and "general" or "appearance","action.open settings.skin settings.icon_skin settings.opacity settings.item_font settings.item_text_scale settings.tint_known_recipes settings.tint_unusable_recipes action.export action.import")
    Catalog(forever and "layout" or "appearance",bagKeys)
    if forever then
        Catalog("personal","settings.bank_layout settings.bank_auto_size settings.bank_slot_size settings.bank_columns settings.bank_subnames settings.bank_empty")
        Catalog("shared","settings.shared_mode settings.shared_contains settings.shared_exclude settings.shared_keep")
        Catalog("guild","settings.guild_slot_size settings.guild_subnames settings.guild_mode settings.guild_contains settings.guild_exclude settings.guild_keep")
    else Catalog("deposit","deposit.target deposit.mode deposit.keep rules.contains rules.exclude") end
    Catalog("rules","rules.add")
    Catalog("currencies","currency.order currency.first currency.custom_type currency.custom_id currency.add")
    Catalog("cache","sync.peer sync.add")
    S.Search:RegisterRoute(B.SETTINGS_ENTRY,function(tab,key)
        if forever and tab=="appearance" and key and (" "..bagKeys.." "):find(" "..key.." ",1,true) then tab="layout" end
        B:SetSettingsRoute(tab)
    end)
end
