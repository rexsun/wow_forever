local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local G,A,S=YUI.GUI2,YUI.API.Bags,YUI.API.Security
local unpack = unpack or table.unpack
local P={controls=setmetatable({}, {__mode="k"}),cooldowns=setmetatable({}, {__mode="k"}),headingInset=0,
    artwork=setmetatable({}, {__mode="k"}),expandedSuffix="",collapsedSuffix=""}
B.Appearance=P
local fixedIconRecipe=G.IconSkins:Resolve({skinId="minimal-rounded",skinOptions={
    ["minimal-rounded"]={border="thin",shadow=true,zoom=.03},
}},B.PRODUCT_ID)
local playerPortrait="portrait:player"
local neutralMaterialColor={1,1,1,1}
local recipeColors={known={.50,.95,.62},unusable={1,.29,.29}}
local contourEmptyColor={0x35/255,0x3B/255,0x44/255,0xB3/255}
local specialSlotColor={.53,.72,.88}
local qualityBorderColors={
    [0]={0x62/255,0x6A/255,0x74/255,1},
    [1]={0xB4/255,0xBC/255,0xC6/255,1},
}
local metrics={
    -- The native panel's TitleContainer starts one unit below TOP and is 20 high.
    native={left=14,right=14,headerTop=1,headerHeight=20,toolsTop=26,toolsHeight=32,contentTop=62,bottom=10,headerInset=8,surfaceInset=8,footerRow=20},
    minimal={left=10,right=10,headerTop=2,headerHeight=22,toolsTop=26,toolsHeight=32,contentTop=62,bottom=6,headerInset=7,surfaceInset=1,footerRow=20},
}
function P:Metrics() return metrics[B:GetConfig().skin] or metrics.native end
local bankDividers=setmetatable({}, {__mode="k"})

local function PaintBankDivider(texture)
    local native=B:GetConfig().skin=="native"
    if native then
        -- Camelot BankFrame and Mainline BankTabDepositSettingsMenuTemplate.
        texture:SetAtlas(YUI.IsForever and "bank-divider" or "_UI-Frame-DiamondMetal-EdgeTop",false)
    else
        texture:SetTexture(nil)
        texture:SetTexCoord(0,1,0,1)
        texture:SetColorTexture(G:GetColor("color.border.subtle"))
    end
    if texture.SetHorizTile then texture:SetHorizTile(native and not YUI.IsForever) end
    texture:SetHeight(native and 8 or 1)
end

-- The caller owns placement, width and visibility across skin changes.
function P:BankDivider(parent)
    local texture=G:CreateTexture(parent,{layer="ARTWORK"})
    bankDividers[texture]=true
    PaintBankDivider(texture)
    return texture
end

local function BankSurface(w,m)
    local art=w.nativeBankSurface
    if not art then
        -- Both clients tile the character-bank atlas and the guild marble.
        -- The window already owns its NineSlice and the cells own their slots.
        art=G:CreateTexture(w.root,{layer="BORDER",subLevel=2})
        if w.liveBank=="bank" then
            art:SetAtlas("bank-frame-background",false)
            art:SetSize(256,256)
        else
            local base=G:CreateTexture(w.root,{layer="BORDER",subLevel=1})
            base:SetColorTexture(31/255,24/255,20/255,1)
            base:SetAllPoints(art)
            w.guildStoneBase=base
            art:SetTexture("Interface\\GuildBankFrame\\GuildVaultBG","REPEAT","REPEAT")
            -- Keep the marble grain, with the background color set by the opaque base.
            art:SetDesaturated(true)
            art:SetVertexColor(.80,.69,.55)
            art:SetBlendMode("ADD")
            art:SetAlpha(.22)
        end
        if art.SetHorizTile then art:SetHorizTile(true);art:SetVertTile(true) end
        art:SetPoint("TOPLEFT",w.root,"TOPLEFT",m.surfaceInset,-math.max(20,m.headerTop+m.headerHeight))
        art:SetPoint("BOTTOMRIGHT",w.root,"BOTTOMRIGHT",-m.surfaceInset,m.surfaceInset)
        w.nativeBankSurface=art
    end
    if not art:IsShown() then art:Show() end
    if w.guildStoneBase and not w.guildStoneBase:IsShown() then w.guildStoneBase:Show() end
end

function P:Surface(w)
    local m=self:Metrics();local root=w.root
    local surface=w.surface
    local native=B:GetConfig().skin=="native"
    local bank=native and (w.liveBank=="bank" or w.liveBank=="guild")
    if bank then BankSurface(w,m)
    elseif w.nativeBankSurface and w.nativeBankSurface:IsShown() then
        w.nativeBankSurface:Hide()
        if w.guildStoneBase then w.guildStoneBase:Hide() end
    end
    -- Native bank art replaces the two local fills. Other native Forever
    -- windows continue to show the shared window shell's rock background.
    if bank or native and B.client=="forever" then
        if surface then surface.base:Hide();surface.grain:Hide() end
        return
    end
    if not surface then
        surface={base=G:CreateTexture(root,"color.surface.sunken","BORDER"),grain=G:CreateTexture(root,{layer="BORDER",subLevel=1})}
        surface.grain:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock","REPEAT","REPEAT")
        surface.grain:SetDesaturated(true);surface.grain:SetBlendMode("ADD");surface.grain:SetAlpha(.06)
        w.surface=surface
    end
    surface.base:Show();surface.grain:Show()
    local top=m.headerTop+m.headerHeight+2
    local width,height=root:GetWidth(),root:GetHeight()
    local inset=m.surfaceInset
    if surface.width==width and surface.height==height and surface.inset==inset and surface.top==top then return end
    for _,texture in ipairs({surface.base,surface.grain}) do
        texture:ClearAllPoints();texture:SetPoint("TOPLEFT",root,"TOPLEFT",inset,-top)
        texture:SetPoint("BOTTOMRIGHT",root,"BOTTOMRIGHT",-inset,inset)
    end
    surface.grain:SetTexCoord(0,math.max(1,width-2*inset)/64,0,math.max(1,height-top-inset)/64)
    surface.width,surface.height,surface.inset,surface.top=width,height,inset,top
end
function P:LayoutHeader(window,width)
    local m=self:Metrics();local root=window.root or window
    window.header:ClearAllPoints();window.header:SetPoint("TOPLEFT",root,"TOPLEFT",0,-m.headerTop);window.header:SetSize(width,m.headerHeight)
    window.title:ClearAllPoints();window.title:SetPoint("CENTER",window.header,"CENTER",0,0);window.title:SetJustifyH("CENTER");window.title:SetWordWrap(false)
    if window.minimalClose then
        local close=B:GetConfig().skin=="minimal" and window.minimalClose or window.nativeClose
        if close~=window.close then
            window.close:Hide();window.close=close;close:Show()
            window.settings:ClearAllPoints();window.settings:SetPoint("RIGHT",close,"LEFT",-1,0)
        end
    end
    window.close:ClearAllPoints();window.close:SetPoint("RIGHT",window.header,"RIGHT",-m.headerInset,0)
end
function P:Hover(button)
    local highlight=G:CreateTexture(button,"color.control.hover","HIGHLIGHT");highlight:SetAllPoints()
    button:SetHighlightTexture(highlight)
end
function P:OutlineHover(button,fill,alpha)
    local frame
    if fill then frame=G:CreatePanel(button,{surface="color.control.hover",border="color.border.accent"})
    else frame=G:CreateFrame(button,{hidden=true});G:CreateBorder(frame,"color.border.accent") end
    frame:SetPoint("TOPLEFT",1,-1);frame:SetPoint("BOTTOMRIGHT",-1,1)
    frame:SetAlpha(alpha or (fill and .55 or .85));frame:EnableMouse(false);frame:Hide()
    if fill then frame:SetFrameLevel(math.max(0,button:GetFrameLevel()-1)) end
    button:HookScript("OnEnter",function(owner) if owner:IsEnabled() then frame:Show() end end)
    button:HookScript("OnLeave",function() frame:Hide() end)
    button:HookScript("OnHide",function() frame:Hide() end)
    button.hoverFrame=frame
end
function P:CommandFeedback(button,toolbar)
    if toolbar then
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
        local light=button:GetHighlightTexture()
        light:ClearAllPoints()
        light:SetPoint("TOPLEFT",button.image,"TOPLEFT",-2,2)
        light:SetPoint("BOTTOMRIGHT",button.image,"BOTTOMRIGHT",2,-2)
    else self:OutlineHover(button,true,1) end
    local press=G:CreateTexture(button,"color.control.pressed","ARTWORK")
    press:SetPoint("TOPLEFT",2,-2);press:SetPoint("BOTTOMRIGHT",-2,2);press:SetAlpha(.65);press:Hide()
    local function Release() press:Hide() end
    button:HookScript("OnMouseDown",function(owner,mouse)
        if mouse=="LeftButton" and owner:IsEnabled() then press:Show() end
    end)
    button:HookScript("OnMouseUp",Release);button:HookScript("OnLeave",Release);button:HookScript("OnHide",Release)
    button.pressFeedback=press
end
local textStyles={heading={size=13,outline="shadow"},label={size=12,outline="shadow"}}
local function PaintGuildPlate(tab)
    local hovered=tab.guildHovered and tab.guildEnabled
    local alpha=tab.nativeSelection and (tab.guildSelected and (hovered and 1 or .94) or hovered and .53)
    local plate=tab.guildPlate
    if plate.tabAlpha==alpha then return end
    plate.tabAlpha=alpha
    if alpha then plate:SetAlpha(alpha) end
    plate:SetShown(not not alpha)
end

local function CreateGuildPlate(tab)
    local plate=G:CreateFrame(tab,{hidden=true})
    plate:EnableMouse(false)
    plate:SetAllPoints(tab)
    plate:SetFrameLevel(math.max(0,tab:GetFrameLevel()-1))
    local fill=G:CreateTexture(plate,{layer="BACKGROUND"})
    fill:SetColorTexture(0x49/255,0x32/255,0x1a/255,.97)
    fill:SetAllPoints()
    G:CreateBorder(plate,0xb9/255,0x8e/255,0x4a/255,1)
    tab.guildPlate=plate
    tab:HookScript("OnEnter",function(owner)
        owner.guildHovered=true
        if owner.nativeSelection then owner.hoverFrame:Hide() end
        PaintGuildPlate(owner)
    end)
    local function Leave(owner)
        owner.guildHovered=false
        PaintGuildPlate(owner)
    end
    tab:HookScript("OnLeave",Leave)
    tab:HookScript("OnHide",Leave)
end

function P:GuildTabSelection(tab,selected,enabled,overview)
    local native=B:GetConfig().skin=="native"
    local amber=native and tab.tabIcon~=nil
    if tab.nativeSelection~=native then
        tab.nativeSelection=native
        G:SetTexturePaintKey(tab.active,native and not amber and "color.text.heading" or "color.control.active")
        tab.active:SetAlpha(native and 1 or .85)
        if tab.tabIcon then
            tab.guildHovered=tab:IsMouseOver()
            tab.hoverFrame:SetShown(not native and tab.guildHovered and enabled)
        end
    end
    if amber and not tab.guildPlate then CreateGuildPlate(tab) end
    if tab.guildPlate then
        tab.guildSelected,tab.guildEnabled=selected,enabled
        PaintGuildPlate(tab)
    end
    local ink=enabled and "color.text.primary" or "color.text.secondary"
    if overview then
        ink="color.text.heading"
    elseif selected then
        ink=amber and "color.text.primary" or native and "color.surface.sunken" or "color.text.heading"
    end
    G:SetTextColorKey(tab.label,ink)
    local plus=tab.purchase and tab.purchaseIcon
    if plus and not plus.bound and plus.plusHorizontal then
        local paint=selected and ink or "color.text.heading"
        if plus.strokePaint~=paint then
            G:SetTexturePaintKey(plus.plusHorizontal,paint)
            G:SetTexturePaintKey(plus.plusVertical,paint)
            plus.strokePaint=paint
        end
    end
    tab.active:SetShown(selected and not amber)
    tab.underline:SetShown(selected and not amber)
end
function P:Text(text,role) G:ApplyFontAppearance(text,textStyles[role] or textStyles.label) end

local function ItemFontStyle(font,size)
    return {font=font,size=math.floor(size+.5),outline="outlineShadow"}
end
function P:ItemTextStyle(slotSize)
    local config=B:GetConfig()
    local styles=self.itemTextStyles
    if not styles or styles.fileKey~=config.itemFont or styles.percent~=config.itemTextScale then
        local media=YUI.LSM or (LibStub and LibStub("LibSharedMedia-3.0",true))
        local name=config.itemFont=="default" and B:GetDefaultItemFont() or config.itemFont
        local font=name~="default" and media and media:Fetch("font",name,true) or "default"
        local locale=YUI.Locale
        local language=locale.Current and locale:Current()
        local bindFont=font
        -- SharedMedia already filters by client locale. A YUI language override can differ.
        if locale.GetClientLocale and language~=locale:GetClientLocale() then
            if language=="zhCN" then bindFont="Fonts\\ARKai_T.ttf"
            elseif language=="zhTW" then bindFont="Fonts\\bLEI00D.ttf" end
        end
        styles={fileKey=config.itemFont,percent=config.itemTextScale,font=font,bindFont=bindFont,
            scale=(config.itemTextScale or 100)/100,cooldowns={}}
        self.itemTextStyles=styles
    end
    local style=styles[slotSize]
    if not style then
        local extra=slotSize-36
        local scale=styles.scale
        style={level=ItemFontStyle(styles.font,(13+extra/3)*scale),
            count=ItemFontStyle(styles.font,(14+extra/3)*scale-1),
            bind=ItemFontStyle(styles.bindFont,math.min((11+extra/4)*scale,(slotSize-4)/2)),
            arrow=math.min(16,math.floor((12+extra/4)*scale+.5)),levelWidths={}}
        styles[slotSize]=style
    end
    return style,styles
end
function P:ApplyItemCountText(button,style)
    local count=button.Count
    if not count then return end
    G:ApplyFontAppearance(count,style)
    count:ClearAllPoints()
    count:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-2,1)
end
function P:ApplyItemText(button,style)
    G:ApplyFontAppearance(button.badge,style.level)
    G:ApplyFontAppearance(button.bindBadge,style.bind)
    if button.chargeBadge then G:ApplyFontAppearance(button.chargeBadge,style.bind) end
    self:ApplyItemCountText(button,style.count)
end
function P:ItemCountdownStyle(shortSide,styles,slotHeight,countSize)
    local base=math.max(10,math.min(16,math.floor(shortSide*.38+.5)))
    local size=math.max(8,math.min(math.floor(base*styles.scale+.5),math.floor(shortSide*.48)))
    local offset=countSize and 1 or 0
    if countSize then
        -- Compact slots limit the font instead of pushing the timer farther from center.
        size=math.max(8,math.min(size,slotHeight-countSize-6))
    end
    local style=styles.cooldowns[size]
    if not style then
        style=ItemFontStyle(styles.font,size)
        styles.cooldowns[size]=style
    end
    return style,offset
end
function P:ApplyItemCountdownText(text,anchor,style,offset)
    if not G:ApplyFontAppearance(text,style) then return false end
    text:ClearAllPoints()
    text:SetPoint("CENTER",anchor,"CENTER",0,offset)
    return true
end
function P:HeadingText(section,count,collapsed)
    local text=section=="system" and B:T("group."..(B.client=="forever" and "camp" or "housing")) or B:T("section."..section)
    if collapsed or section=="empty" then text=text.." · "..tostring(count or 0) end
    return text
end
function P:HeadingWidth(section,count,collapsed)
    return self:TextWidth(self:HeadingText(section,count,collapsed),"heading")+18
end
local shortGroups={
    ["Food & Drink"]="food",["Food and Drink"]="food",["食物和饮料"]="food",["食物和飲料"]="food",
    ["Item Enhancement"]="enhancement",["物品强化"]="enhancement",["物品強化"]="enhancement",
    ["Metal & Stone"]="ore",["金属和矿石"]="ore",["金屬和礦石"]="ore",["金屬與礦石"]="ore",
    ["Consumable"]="consumable",["消耗品"]="consumable",["Trade Goods"]="material",["商品"]="material",
}
function P:GroupText(group)
    local setName=B.Classification:SetGroupName(group)
    if setName then return (setName:gsub("|","||")) end
    if shortGroups[group] then return B:T("group."..shortGroups[group]) end
    local text=_G[group] or B:T("group."..group)
    return text=="group."..group and group or text
end
local tradeGold,tradeAmber={1,.83,.48},{1,.60,.28}
local tradeSweepSteps=12
function P:TradeCaptionFrames(text)
    local gradient=YUI.F
    if not gradient or not gradient.GetGradientText then return nil end
    if self.tradeCaptionText==text then return self.tradeCaptionFrames end
    local base=gradient:GetGradientText(text,tradeGold,tradeAmber)
    local frames={[0]=base,[tradeSweepSteps]=base}
    local colorPattern="|cff(%x%x)(%x%x)(%x%x)"
    local _,count=base:gsub(colorPattern,"")
    if count>1 then
        local radius=.32
        for step=1,tradeSweepSteps-1 do
            local center=-radius+(1+2*radius)*step/tradeSweepSteps
            local index=0
            frames[step]=base:gsub(colorPattern,function(r,g,b)
                local weight=1-math.abs(index/(count-1)-center)/radius
                index=index+1
                if weight<=0 then return nil end
                weight=weight*weight*(3-2*weight)
                local green,blue=tonumber(g,16),tonumber(b,16)
                return string.format("|cff%s%02x%02x",r,math.floor(green+(250-green)*weight+.5),
                    math.floor(216*weight+blue*(1-weight)+.5))
            end)
        end
    end
    self.tradeCaptionText,self.tradeCaptionFrames=text,frames
    return frames
end
function P:SetTradeSweep(window,label,frames)
    local old=window.tradeSweep
    if old and old.label==label and old.frames==frames then return end
    if old then
        window.tradeSweep=nil
        if old.timer then old.timer:Cancel();B.Stats.timers=B.Stats.timers-1 end
        if old.handle then old.handle:Stop() end
        if old.phase~=0 and old.label:GetText()==old.frames[old.phase] then old.label:SetText(old.frames[0]) end
    end
    local animation=YUI.Animation
    if not (label and frames and frames[1] and animation and animation.Tween and window.root:IsVisible()) then return end
    local state={label=label,frames=frames,phase=0}
    window.tradeSweep=state
    local start
    local function Schedule()
        state.timer=C_Timer.NewTimer(5,start)
        B.Stats.timers=B.Stats.timers+1
    end
    local function Advance(progress)
        if window.tradeSweep~=state then return end
        local phase=math.floor(progress*tradeSweepSteps)
        if phase~=state.phase then
            state.phase=phase
            local text=frames[phase]
            if label:GetText()~=text then label:SetText(text) end
        end
    end
    local function Finish(_,_,finished)
        state.handle=nil
        if not finished or window.tradeSweep~=state then return end
        Advance(0)
        Schedule()
    end
    start=function()
        if window.tradeSweep~=state or not state.timer then return end
        state.timer=nil
        B.Stats.timers=B.Stats.timers-1
        if not B.active or not label:IsVisible() then self:SetTradeSweep(window);return end
        state.handle=animation:Tween({owner=window,target=label,key="ybags.tradeSweep",easing="linear",
            duration=.9,from=0,to=1,onUpdate=Advance,onFinished=Finish})
        if state.handle.noop then self:SetTradeSweep(window) end
    end
    if label:GetText()~=frames[0] then label:SetText(frames[0]) end
    Schedule()
end
function P:TextWidth(text,role,itemStyle)
    self.textWidths=self.textWidths or {}
    local cache=itemStyle and itemStyle.levelWidths or self.textWidths[role]
    if not cache then cache={};self.textWidths[role]=cache end
    if cache[text] then return cache[text] end
    if not self.measureHost then
        self.measureHost=G:CreateFrame(UIParent,{hidden=true})
        self.measure=G:CreateText(self.measureHost,"",12,"color.text.primary")
        self.measure:SetWordWrap(false)
    end
    if itemStyle then G:ApplyFontAppearance(self.measure,itemStyle.level) else self:Text(self.measure,role) end
    self.measure:SetText(text)
    local width=math.ceil(self.measure:GetStringWidth())
    cache[text]=width
    return width
end
function P:WrappedTextHeight(text,width)
    if self:TextWidth(text,"label")<=width then return 14 end
    self.textHeights=self.textHeights or {}
    local cache=self.textHeights[text]
    if not cache then cache={};self.textHeights[text]=cache end
    if cache[width] then return cache[width] end
    if not self.wrapMeasure then
        self.wrapMeasure=G:CreateText(self.measureHost,"",12,"color.text.primary")
        self.wrapMeasure:SetWordWrap(true);self.wrapMeasure:SetNonSpaceWrap(true)
    end
    self:Text(self.wrapMeasure,"label");self.wrapMeasure:SetWidth(width);self.wrapMeasure:SetText(text)
    local height=math.max(14,math.ceil(self.wrapMeasure:GetStringHeight()))
    cache[width]=height
    return height
end
function P:Apply(control)
    local data=self.controls[control]
    if not data then return end
    local native=B:GetConfig().skin=="native"
    for _,texture in ipairs(data.native) do texture:SetAlpha(native and 1 or 0) end
    if data.flat then data.flat:SetShown(not native) end
    if data.highlight then
        data.highlight:SetAlpha(data.toolbar and 1 or data.kind=="icon" and .58 or native and 1 or .15)
        data.highlight:SetDesaturated(not native)
    end
    if data.kind=="button" then
        control:SetNormalFontObject(native and "GameFontNormalSmall" or "GameFontHighlightSmall")
        control:SetDisabledFontObject("GameFontDisableSmall")
    elseif data.kind=="edit" then control:SetFontObject("GameFontHighlightSmall") end
end
function P:Refresh()
    self.textWidths,self.textHeights=nil,nil
    self.itemTextStyles=nil
    for control in pairs(self.controls) do self:Apply(control) end
    for divider in pairs(bankDividers) do PaintBankDivider(divider) end
    for _,window in pairs(B.View.windows) do
        if window.liveBank then self:Surface(window) end
    end
    self:RefreshIconStyle()
end
local function Flat(control)
    local frame=G:CreatePanel(control,{surface="color.control.bg",border="color.border.default"})
    frame:SetAllPoints();frame:SetFrameLevel(math.max(0,control:GetFrameLevel()-1))
    return frame
end
function P:Edit(parent,opts)
    opts=opts or {}
    local edit=G:CreateFrame(parent,{type="EditBox",template="InputBoxTemplate",width=opts.width or 140,height=22})
    edit:SetAutoFocus(false);edit:SetTextInsets(7,7,0,0);edit:SetMaxLetters(opts.max or 160)
    edit:SetText(tostring(opts.text or ""))
    edit.Left:ClearAllPoints();edit.Left:SetPoint("LEFT",0,0)
    self.controls[edit]={kind="edit",native={edit.Left,edit.Middle,edit.Right},flat=Flat(edit)}
    if opts.placeholder then
        edit.placeholder=G:CreateText(edit,opts.placeholder,12,"color.text.secondary")
        edit.placeholder:SetPoint("LEFT",7,0);edit.placeholder:SetJustifyH("LEFT")
        edit.placeholder:SetShown(edit:GetText()=="")
    end
    edit:SetScript("OnEscapePressed",function(owner) owner:ClearFocus() end)
    self:Apply(edit)
    return edit
end
function P:Button(parent,opts)
    opts=opts or {}
    local button=G:CreateButtonFrame(parent,{template="UIPanelButtonTemplate",width=opts.width or 96,height=24})
    button:SetText(opts.text or "")
    self.controls[button]={kind="button",native={button.Left,button.Middle,button.Right},flat=Flat(button),highlight=button:GetHighlightTexture()}
    if opts.onClick then button:SetScript("OnClick",opts.onClick) end
    self:Apply(button)
    return button
end
function P:SettingsButton(parent,onClick)
    local atlas="Warfronts-BaseMapIcons-Empty-Workshop-Minimap"
    local hasAtlas,info
    if C_Texture and type(C_Texture.GetAtlasInfo)=="function" then
        hasAtlas,info=pcall(C_Texture.GetAtlasInfo,atlas)
    end
    local button=G:CreateBlizzardIconButton(parent,{
        atlas=hasAtlas and info and atlas or nil,
        texture=G:GetSettingsIcon("settings"),size=22,crop=false,
        tooltip=B:T("action.settings"),onClick=onClick,
    })
    button.icon:ClearAllPoints();button.icon:SetSize(16,16);button.icon:SetPoint("CENTER",button,"CENTER",0,0)
    return button
end
function P:Icon(parent,opts)
    opts=opts or {}
    local size=opts.iconSize or 18
    local button=G:CreateButtonFrame(parent,{width=22,height=22,frameLevel=parent:GetFrameLevel()+1})
    button.image=G:CreateTexture(button,nil,"ARTWORK");button.image:SetSize(size,size);button.image:SetPoint("CENTER")
    local source=opts.asset or 134400
    if opts.atlas then
        button.image:SetAtlas(opts.atlas);source="atlas:"..opts.atlas
    elseif opts.playerPortrait and A.PlayerPortrait(button.image) then
        source=playerPortrait
    else button.image:SetTexture(source) end
    if opts.command then self:CommandFeedback(button,opts.command=="toolbar")
    else
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
        self:OutlineHover(button)
    end
    button.selected=G:CreateTexture(button,"color.text.heading","OVERLAY")
    button.selected:SetHeight(2);button.selected:SetPoint("BOTTOMLEFT",2,0);button.selected:SetPoint("BOTTOMRIGHT",-2,0);button.selected:Hide()
    self.controls[button]={kind="icon",native={},highlight=button:GetHighlightTexture(),toolbar=opts.command=="toolbar"}
    self:Apply(button)
    if opts.pressedAtlas then
        local function Release() button.image:SetAtlas(opts.atlas) end
        button:HookScript("OnMouseDown",function(owner,mouse)
            if mouse=="LeftButton" and owner:IsEnabled() then button.image:SetAtlas(opts.pressedAtlas) end
        end)
        button:HookScript("OnMouseUp",Release);button:HookScript("OnLeave",Release);button:HookScript("OnHide",Release)
    else self:Artwork(button,button.image,source,size) end
    return button
end
function P:SizeIcon(button,size)
    button:SetSize(size,size)
    button.image:SetSize(size,size)
end
P.toolbarStep=20
P.bagSocketBackground="Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

function P:BagSocketArtwork(button,source,size,quality,empty)
    if button.socketArtwork==source and button.quality==quality and button.socketSize==size
        and button.socketEmpty==empty then return end
    if type(source)=="string" and source:sub(1,6)=="atlas:" then button.icon:SetAtlas(source:sub(7))
    else button.icon:SetTexture(source);button.icon:SetTexCoord(0,1,0,1) end
    if SetItemButtonQuality then SetItemButtonQuality(button,quality) end
    button:GetNormalTexture():Hide()
    self:Artwork(button,button.icon,source,size,quality,"socket",empty)
    button.socketArtwork,button.quality,button.socketSize,button.socketEmpty=source,quality,size,empty
end

function P:Portrait(parent,size)
    local slot=G:CreateIconSlot(parent,{size=size,variant="bare",shape="circle",border="none",zoom=.03,animate=false})
    slot:EnableMouse(false);G:SetIconCircleBackdrop(slot,size,true)
    return slot
end
function P:ClassIconSlot(parent,size)
    local slot=G:CreateIconSlot(parent,{size=size,variant="bare",shape="square",border="none",zoom=.04,animate=false})
    slot:EnableMouse(false)
    return slot
end
function P:IdentityIcon(slot,source,zoom,coords,identity,aspect)
    identity=identity or source
    aspect=aspect or 1
    if slot.ybagsIdentitySource==source and slot.ybagsIdentityKey==identity
        and slot.ybagsIdentityZoom==zoom and slot.ybagsIdentityAspect==aspect then return end
    if source==playerPortrait then
        if not A.PlayerPortrait(slot.icon) then slot:SetIcon(134400) end
    else slot:SetIcon(source) end
    if coords then
        local left,right,top,bottom=coords[1],coords[2],coords[3],coords[4]
        local dx,dy=(right-left)*zoom,(bottom-top)*zoom
        slot.icon:SetTexCoord(left+dx,right-dx,top+dy,bottom-dy)
    elseif type(source)=="string" and source:sub(1,6)=="atlas:" then
        -- Atlas coordinates are a subrectangle, not a whole texture. Changing
        -- the source also resets the crop even when the slot's zoom is unchanged.
        local left,top,_,bottom,right=slot.icon:GetTexCoord()
        local dx,dy=(right-left)*zoom,(bottom-top)*(1-(1-2*zoom)/aspect)*.5
        slot.icon:SetTexCoord(left+dx,right-dx,top+dy,bottom-dy)
    else G:ApplyIconTexCoord(slot.icon,zoom,aspect) end
    slot.ybagsIdentitySource,slot.ybagsIdentityKey,slot.ybagsIdentityZoom,slot.ybagsIdentityAspect=source,identity,zoom,aspect
end
function P:ClassIcon(slot,classFile)
    local info=YUI.API.Icons and YUI.API.Icons.GetClassIcon(classFile)
    if not info or not info.texCoord then return false end
    self:IdentityIcon(slot,"Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",.04,info.texCoord,info.classFile)
    return true
end
local portraitMarkup={}
function P:TooltipPortrait(atlas)
    if not atlas then return "" end
    if not portraitMarkup[atlas] then
        local info=C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        local file=info and (info.file or info.filename)
        if file and CreateTextureMarkup then
            local left,right,top,bottom=info.leftTexCoord,info.rightTexCoord,info.topTexCoord,info.bottomTexCoord
            local dx,dy=(right-left)*.10,(bottom-top)*.10
            -- The markup crop uses integer offsets. Quantize the atlas UVs on a common grid.
            local grid=4096
            local function UV(value) return math.floor(value*grid+.5)/grid end
            portraitMarkup[atlas]=CreateTextureMarkup(file,grid,grid,16,16,UV(left+dx),UV(right-dx),UV(top+dy),UV(bottom-dy)).." "
        else
            portraitMarkup[atlas]="|A:"..atlas..":16:16|a "
        end
    end
    return portraitMarkup[atlas]
end
-- Keep native cooldown geometry here, separate from timing and native item input.
function P:ItemCooldownText(button)
    local state=self.cooldowns[button]
    if not state then return end
    local slotStyle,styles=self:ItemTextStyle(state.width)
    local countSize=button.Count and button.Count:IsShown() and slotStyle.count.size or nil
    local style,offset=self:ItemCountdownStyle(state.shortSide,styles,state.height,countSize)
    if state.countdownStyled==style and state.countdownOffset==offset then return end
    local cooldown=button.Cooldown
    if G.IsIconSkinManaged and (G:IsIconSkinManaged(button) or G:IsIconSkinManaged(cooldown)) then return end
    if not cooldown.GetCountdownFontString then state.countdownStyled,state.countdownOffset=style,offset;return end
    local ok,text=pcall(cooldown.GetCountdownFontString,cooldown)
    if ok and text and self:ApplyItemCountdownText(text,cooldown,style,offset) then
        state.countdownStyled,state.countdownOffset=style,offset
    end
end
function P:ItemCooldown(button)
    local cooldown=button.Cooldown
    if not cooldown or G.IsIconSkinManaged and (G:IsIconSkinManaged(button) or G:IsIconSkinManaged(cooldown)) then return end
    local width,height=button:GetWidth(),button:GetHeight()
    local state=self.cooldowns[button]
    local visual=self.artwork[button]
    local recipe=visual and visual.styled and self.iconRecipe
    if state and state.width==width and state.height==height and state.recipe==recipe then return self:ItemCooldownText(button) end
    if A.InCombat() then return end
    if not state then state={};self.cooldowns[button]=state end
    if not state.width or state.recipe~=recipe then
        cooldown:SetSwipeTexture(G:GetIconCooldownTexture(recipe and recipe.shape or "square",recipe and recipe.border or "none"))
        cooldown:SetDrawEdge(false);cooldown:SetDrawBling(false);cooldown:SetUseCircularEdge(false)
    end
    G:RestoreIconCooldownLayout(cooldown)
    cooldown:ClearAllPoints()
    local shortSide=math.min(width,height)
    if recipe then
        local icon=visual.slot.icon
        cooldown:SetAllPoints(icon)
        local iconWidth,iconHeight=G:GetIconAppearanceSize(visual.size,recipe.shape)
        G:ApplyIconCooldownLayout(cooldown,icon,recipe.shape,recipe.border,iconWidth,iconHeight)
        shortSide=math.min(iconWidth,iconHeight)
    else
        local inset=shortSide/38*1.5
        cooldown:SetPoint("TOPLEFT",button.icon or button,"TOPLEFT",inset,-inset)
        cooldown:SetPoint("BOTTOMRIGHT",button.icon or button,"BOTTOMRIGHT",-inset,inset)
    end
    state.width,state.height,state.recipe,state.shortSide=width,height,recipe,shortSide
    self:ItemCooldownText(button)
end
-- Visuals are shared by every cell. The native template supplies live actions only.
function P:Item(parent,live,template)
    local button=G:CreateFrame(parent,{type="ItemButton",template=template or (live and "ContainerFrameItemButtonTemplate" or nil),
        width=38,height=38,frameLevel=parent:GetFrameLevel()+1,hidden=true})
    button.SyncAppearanceWithHasItem=function(owner) P:CellAppearance(owner,not owner.hasItem) end
    button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal=button:GetNormalTexture();normal:ClearAllPoints();normal:SetPoint("CENTER",0,-1);normal:SetSize(64,64)
    if button.icon then button.icon:ClearAllPoints();button.icon:SetAllPoints() end
    if button.IconBorder then button.IconBorder:ClearAllPoints();button.IconBorder:SetAllPoints(button) end
    return button
end
local function IsSpecialSpace(space)
    return type(space)=="string" and space:sub(1,7)=="family:"
end
local function NativeCell(button,empty)
    if button.EmptyBagIcon then button.EmptyBagIcon:Hide() end
    local normal=button:GetNormalTexture()
    normal:SetVertexColor(1,1,1,1)
    local special=empty and IsSpecialSpace(button.ybagsSpace)
    normal:SetDesaturated(special==true)
    if empty then
        -- Both live and cached cells use the same native empty-slot atlas.
        if button.icon then button.icon:SetTexture(nil) end
        normal:SetAtlas("bags-item-slot64");normal:ClearAllPoints();normal:SetAllPoints();normal:Show()
        if special then normal:SetVertexColor(unpack(specialSlotColor))
        elseif button.ybagsSpace and button.ybagsSpace~="normal" then normal:SetVertexColor(G:GetColor("color.text.heading")) end
        if button.IconBorder then button.IconBorder:Hide() end
    else
        normal:SetTexture("Interface\\Buttons\\UI-Quickslot2");normal:SetTexCoord(0,1,0,1);normal:ClearAllPoints();normal:SetPoint("CENTER",0,-1)
        normal:SetSize(button:GetWidth()*64/37,button:GetHeight()*64/37);normal:Show()
    end
end
local function SuppressNativeCellFrame(button)
    -- The native button may show its normal texture again when a press ends.
    local normal=button:GetNormalTexture()
    if normal:GetAlpha()~=0 then normal:SetAlpha(0) end
    normal:Hide()
    local border=button.IconBorder
    if border then
        if border:GetAlpha()~=0 then border:SetAlpha(0) end
        border:Hide()
    end
end

local function ApplyStateMask(state,mask)
    local highlight,pushed=state.highlight,state.pushed
    if state.mask then
        if highlight and highlight.RemoveMaskTexture then highlight:RemoveMaskTexture(state.mask) end
        if pushed and pushed.RemoveMaskTexture then pushed:RemoveMaskTexture(state.mask) end
    end
    state.mask=mask
    if mask then
        if highlight and highlight.AddMaskTexture then highlight:AddMaskTexture(mask) end
        if pushed and pushed.AddMaskTexture then pushed:AddMaskTexture(mask) end
    end
end
local function ApplyPressedShape(owner,state,shape)
    local native=state.nativePushed
    if not (native and owner.SetPushedTexture and G.PaintIconPressedVisual) then return end
    if G.IsIconSkinManaged and (G:IsIconSkinManaged(owner) or G:IsIconSkinManaged(native)) then return end
    if not state.pressedOverlay then
        state.pressedOverlay=G:CreateTexture(owner,nil,"BORDER")
        state.pressedOverlay:Hide()
        state.pressedEffect="innerGlow"
    end
    local overlay=state.pressedOverlay
    if state.pushed~=overlay then
        ApplyStateMask(state,nil)
        owner:SetPushedTexture(overlay)
        native:SetAlpha(0);native:Hide()
        state.pushed=overlay
    end
    overlay:ClearAllPoints();overlay:SetAllPoints(state.slot)
    G:PaintIconPressedVisual(state,shape)
    overlay:SetAlpha((state.alpha or 1)*(overlay.yabNativeVisualAlpha or 1))
end

function P:ApplyArtwork(owner,state)
    local recipe=fixedIconRecipe
    if state.role then recipe=self.iconRecipe end
    if not recipe or not state.source then
        if not state.styled or state.pressedOverlay and state.pushed==state.pressedOverlay and A.InCombat() then return end
        state.styled=false
        state.slot:Hide()
        ApplyStateMask(state,nil)
        if state.pressedOverlay and state.pushed==state.pressedOverlay then
            owner:SetPushedTexture(state.nativePushed)
            state.pressedOverlay:Hide()
            state.pushed=state.nativePushed
            state.pushed:SetAlpha(state.alpha or 1)
        end
        state.texture:SetAlpha(state.alpha or 1)
        if state.role then
            if owner.Background and state.nativeBackground~=nil then owner.Background:SetShown(state.nativeBackground) end
            if SetItemButtonQuality then SetItemButtonQuality(owner,state.quality) end
            if state.role=="cell" then
                local alpha=state.alpha or 1
                owner:GetNormalTexture():SetAlpha(alpha)
                if owner.IconBorder then owner.IconBorder:SetAlpha(alpha) end
                NativeCell(owner,state.empty)
                self:ItemCooldown(owner)
            end
        end
        return
    end
    local size=state.size
    local geometry=state.recipe~=recipe or state.drawnSize~=size
    if (not state.slot or geometry) and A.InCombat() then return end
    if not state.slot then
        local slot=G:CreateIconSlot(owner,{size=size,variant="bare",border="none",animate=false})
        -- Keep the native count, cooldown and click state above the visual layer.
        slot:SetFrameLevel(math.max(0,owner:GetFrameLevel()-1))
        -- A pixel-snapped slot can be wider or narrower than its source.
        -- Player cells and footer currencies share the source's left edge.
        local anchor=owner.ybagsArtworkAnchor or "CENTER"
        slot:SetPoint(anchor,state.texture,anchor)
        slot:EnableMouse(false)
        state.slot=slot
        local control=self.controls[owner]
        -- Toolbar highlights extend beyond the icon, so keep them outside its mask.
        if not (control and control.toolbar) then
            state.highlight=owner.HighlightTexture or owner.GetHighlightTexture and owner:GetHighlightTexture()
        end
        state.nativePushed=owner.GetPushedTexture and owner:GetPushedTexture() or owner.PushedTexture
        state.pushed=state.nativePushed
    end
    local slot=state.slot
    if geometry then
        slot:SetIconAppearance({size=size,shape=recipe.shape,border=recipe.border,zoom=recipe.zoom,materialTint=state.role~=nil})
        if recipe.shadow and not state.shadow then state.shadow=G:CreateShapeShadow(slot) end
        local width,height=G:GetIconAppearanceSize(size,recipe.shape)
        G:ApplyShapeShadow(state.shadow,{enabled=recipe.shadow,shape=recipe.shape,color=recipe.shadowColor},
            {anchor=slot,width=width,height=height,allowLayout=true})
        state.recipe,state.drawnSize,state.aspect=recipe,size,G:GetIconAppearancePreset(recipe.shape).aspect
        state.material=G:IsIconBorderMaterial(recipe.border)
    end
    if state.role=="cell" and (geometry or not state.styled) then ApplyPressedShape(owner,state,recipe.shape) end
    self:IdentityIcon(slot,state.source,recipe.zoom,nil,nil,state.aspect)
    local mask=G:GetIconAppearanceMask(recipe.shape,recipe.border) and slot.gui2IconAppearanceMask
    if state.mask~=mask then ApplyStateMask(state,mask) end
    local quality=not state.empty and state.quality or nil
    local qualityBorder=state.role~=nil and (recipe.border=="contour" or not state.material and recipe.border~="none")
    if geometry or state.drawnQuality~=quality or state.drawnQualityBorder~=qualityBorder then
        local color=state.material and neutralMaterialColor or recipe.borderColor
        if quality and quality>1 then
            local r,g,b=YUI.API.Item.GetQualityColor(quality)
            color={S.SafeNumber(r) or 1,S.SafeNumber(g) or 1,S.SafeNumber(b) or 1,color[4]}
        elseif qualityBorder then
            color=qualityBorderColors[quality] or (quality==nil and recipe.border=="contour" and contourEmptyColor) or color
        end
        slot:SetIconBorderColor(color)
        state.drawnQuality,state.drawnQualityBorder=quality,qualityBorder
    end
    if geometry or state.drawnTint~=state.tint or state.drawnRecipeTint~=state.recipeTint then
        local color=recipeColors[state.recipeTint]
        if color then slot.icon:SetVertexColor(color[1],color[2],color[3])
        elseif IsSpecialSpace(state.tint) then slot.icon:SetVertexColor(unpack(specialSlotColor))
        elseif state.tint then slot.icon:SetVertexColor(G:GetColor("color.text.heading"))
        else slot.icon:SetVertexColor(1,1,1,1) end
        state.drawnTint,state.drawnRecipeTint=state.tint,state.recipeTint
    end
    if state.drawnDesaturated~=state.desaturated then
        slot.icon:SetDesaturated(state.desaturated==true)
        state.drawnDesaturated=state.desaturated
    end
    if not state.styled then
        state.styled=true
        state.texture:SetAlpha(0)
        slot:SetAlpha(state.alpha or 1)
        slot:Show()
        if state.role and owner.Background then state.nativeBackground=owner.Background:IsShown() end
    end
    if state.role then
        if owner.Background then owner.Background:Hide() end
        if state.role=="cell" then
            SuppressNativeCellFrame(owner)
            self:ItemCooldown(owner)
        else
            if owner.IconBorder then owner.IconBorder:Hide() end
            owner:GetNormalTexture():Hide()
        end
    end
end

function P:Artwork(owner,texture,source,size,quality,role,empty,tint,desaturated,recipeTint)
    local state=self.artwork[owner]
    if not state then state={texture=texture};self.artwork[owner]=state end
    state.source,state.size,state.quality,state.role=source,size,quality,role
    state.empty,state.tint,state.desaturated,state.recipeTint=empty,tint,desaturated,recipeTint
    self:ApplyArtwork(owner,state)
end

function P:RefreshIconStyle()
    if A.InCombat() then return end
    local choice=B:GetIconSkin()
    if self.iconChoice==choice then return end
    self.iconChoice=choice
    self.iconRecipe=choice.skinId~="native" and G.IconSkins:Resolve(choice,B.PRODUCT_ID) or nil
    for owner,state in pairs(self.artwork) do
        if state.role and (state.slot or owner:IsShown()) then self:ApplyArtwork(owner,state) end
    end
end

function P:CellAppearance(button,empty,item,recipeTint)
    local state=self.artwork[button]
    if not self.iconRecipe then
        NativeCell(button,empty)
        self:ItemCooldown(button)
    elseif button.EmptyBagIcon then button.EmptyBagIcon:Hide() end
    if item then
        if recipeTint or state and state.recipeTint then
            local color=recipeColors[recipeTint] or neutralMaterialColor
            button.icon:SetVertexColor(color[1],color[2],color[3])
        end
        local emptyIcon="atlas:bags-item-slot64"
        local source=empty and emptyIcon or item.icon
        local tint=empty and button.ybagsSpace~="normal" and button.ybagsSpace
        self:Artwork(button,button.icon,source,button:GetWidth(),item.quality,"cell",empty,
            tint,IsSpecialSpace(tint) or not empty and (item.held or item.locked)==true,recipeTint)
    elseif state and state.styled then
        SuppressNativeCellFrame(button)
    end
end
function P:CellAlpha(button,alpha)
    -- Intrinsic ItemButton.SetAlpha changes selected regions, not the frame.
    local visual=self.artwork[button]
    button:SetAlpha(alpha)
    if button.splitCount then
        button.Count:SetAlpha(0)
        button.splitCountLabel:SetAlpha(alpha)
    end
    if visual and visual.styled then SuppressNativeCellFrame(button)
    else button:GetNormalTexture():SetAlpha(alpha) end
    if button.Cooldown then button.Cooldown:SetAlpha(alpha) end
    if button.IconOverlay2 then button.IconOverlay2:SetAlpha(alpha) end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(alpha) end
    local pushed=visual and visual.pushed or button.PushedTexture
    if pushed then pushed:SetAlpha(alpha*(pushed.yabNativeVisualAlpha or 1)) end
    if button.slotLock then button.slotLock:SetAlpha(alpha) end
    if visual then
        visual.alpha=alpha
        if visual.styled then visual.texture:SetAlpha(0);visual.slot:SetAlpha(alpha) end
    end
end
