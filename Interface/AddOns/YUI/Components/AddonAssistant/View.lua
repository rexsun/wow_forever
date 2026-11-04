local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end
local G, R, M = YUI.GUI2, A.Runtime, A.Model
local V = { tab = "addons", filter = "all", tag = "all", query = "", pool = {}, rulePool = {} }
A.View = V
local L
local skinnedChecks, nativeControls, nativeSurfaces = {}, {}, {}
local ROW, WINDOW_WIDTH, WIDTH = 30, 960, 960
local DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT, MAX_ROWS = 760, 560, 1000, 28
local MONITOR_ROW, MONITOR_TOP, MONITOR_FOOTER, MONITOR_MAX_ROWS = 20, 62, 48, 35
local MONITOR_HEIGHT, MONITOR_MIN_HEIGHT = 350, 230
local FILTER_X, TAG_X, COUNT_X = 512, 636, 760
local RULE_WIDTH, RULE_GAP = WIDTH-42, 12
local RULE_CARD_WIDTH = (RULE_WIDTH-RULE_GAP)/2

-- Product surfaces use shared GUI2 rendering and theme-derived colors.
local themeReady
local function registerTheme()
if themeReady then return end
themeReady=true
G:RegisterTokenProvider("AddonAssistant", function(tokens)
    local function derive(target, source, alpha, lift, tint)
        local color = tokens[source].value
        local foreground = tokens[tint or "color.text.primary"].value
        lift = lift or 0
        tokens["color.addonAssistant." .. target] = G:CreateSolidPaint(
            color[1]+(foreground[1]-color[1])*lift,
            color[2]+(foreground[2]-color[2])*lift,
            color[3]+(foreground[3]-color[3])*lift, alpha)
    end
    derive("window", "color.surface.raised", 1, .055)
    derive("header", "color.surface.raised", 1, .12)
    derive("list", "color.surface.panel", 1, .035)
    derive("stripe", "color.surface.raised", 1, .04)
    derive("card", "color.surface.raised", 1, .09)
    derive("hover", "color.accent.primary", .12)
    derive("dependency.fill", "color.state.error", .18)
    derive("clear", "color.surface.panel", 0)
    for key,alpha in pairs({header=.38,list=.32,stripe=.12,card=.24}) do
        derive("native."..key,"color.surface.panel",alpha)
    end
    for tag, source in pairs(A.TagColors) do derive("tag." .. tag, source, .13) end
    local base=tokens["color.addonAssistant.card"].value
    for tone, source in pairs({accent="color.accent.primary",success="color.state.success",warning="color.state.warning",danger="color.state.danger"}) do
        local tint=tokens[source].value
        for state, strength in pairs({normal=.32,hover=.44,pressed=.24,border=.6}) do
            tokens["color.addonAssistant.action."..tone.."."..state]=G:CreateSolidPaint(
                base[1]+(tint[1]-base[1])*strength,base[2]+(tint[2]-base[2])*strength,base[3]+(tint[3]-base[3])*strength,1)
        end
    end
end)
end

local function appearanceTheme()
    return R.char and R.char.skin=="dark" and "dark" or "native"
end

-- Native templates are passive decoration. GUI2 remains the only input owner.
-- The original GUI2 background is hidden, so the two styles never stack borders.
local function syncNativeControl(owner)
    local kind=owner.assistantNativeKind
    local native=appearanceTheme()=="native" and not owner.assistantQuiet
    local visual=owner.assistantNativeVisual
    if native then
        -- Keep decoration above the parent panel, with the GUI2 label/input above it.
        local level=owner:GetParent():GetFrameLevel()+2
        if owner:GetFrameLevel()<level then owner:SetFrameLevel(level) end
    end
    if native and not visual then
        if kind=="dropdown" then
            visual=G:CreateFrame(owner,{mouse=false})
            local bg=G:CreateTexture(visual,{layer="BACKGROUND"})
            bg:SetAtlas("common-dropdown-textholder",true)
            bg:SetPoint("TOPLEFT",-8,7); bg:SetPoint("BOTTOMRIGHT",8,-9)
            visual.arrow=G:CreateTexture(visual,{layer="ARTWORK"})
            visual.arrow:SetAtlas("common-dropdown-a-button",true); visual.arrow:SetPoint("RIGHT",1,-3)
        elseif kind=="field" then
            visual=G:CreateFrame(owner,{template="InsetFrameTemplate",mouse=false})
        else
            visual=G:CreateButtonFrame(owner,{template=kind=="close" and "UIPanelCloseButtonNoScripts" or
                kind=="icon" and "UIPanelSquareButton" or "UIPanelButtonTemplate"})
            visual:EnableMouse(false)
            if visual.icon then visual.icon:Hide() end
        end
        visual:SetAllPoints(owner); owner.assistantNativeVisual=visual
    end
    if visual then
        visual:SetShown(native); visual:SetFrameLevel(math.max(0,owner:GetFrameLevel()-1))
    end
    local background=owner.bg or owner.gui2Bg
    if background then background:SetShown(not native) end
    if owner.arrow then owner.arrow:SetShown(not native) end
    if kind=="close" and owner.icon then owner.icon:SetShown(not native) end
    if not native then return end
    if owner.SetBackdropColor then owner:SetBackdropColor(0,0,0,0) end
    G:SetBorderColor(owner,"color.addonAssistant.clear")
    if kind=="button" or kind=="icon" or kind=="close" then
        local enabled=not owner.gui2Disabled
        visual:SetEnabled(enabled)
        if enabled then visual:SetButtonState(owner.assistantPressed and "PUSHED" or "NORMAL") end
        -- The native three-piece background is painted by template scripts, not SetButtonState.
        if kind=="button" then
            local paint=visual:GetScript(not enabled and "OnDisable" or owner.assistantPressed and "OnMouseDown" or "OnMouseUp")
            if paint then paint(visual) end
        end
        if owner:IsMouseOver() and enabled then visual:LockHighlight() else visual:UnlockHighlight() end
        if kind=="button" and owner.text and type(owner.text)~="string" then
            G:SetTextColorKey(owner.text,owner.gui2Disabled and "color.text.disabled" or "color.text.heading")
        end
    else
        visual:SetAlpha(owner.gui2Disabled and .45 or 1)
    end
end

local function nativeControl(owner,kind)
    if owner.assistantNativeKind then return owner end
    owner.assistantNativeKind=kind; nativeControls[#nativeControls+1]=owner
    local refresh,disabled=owner.RefreshTheme,owner.SetDisabled
    if refresh then owner.RefreshTheme=function(control,...)
        local changed=refresh(control,...); syncNativeControl(control); return changed
    end end
    if disabled then owner.SetDisabled=function(control,...)
        local changed=disabled(control,...)
        if changed~=false then syncNativeControl(control) end
        return changed
    end end
    for _,event in ipairs({"OnEnter","OnLeave","OnShow"}) do owner:HookScript(event,syncNativeControl) end
    owner:HookScript("OnMouseDown",function(control) control.assistantPressed=true; syncNativeControl(control) end)
    owner:HookScript("OnMouseUp",function(control) control.assistantPressed=false; syncNativeControl(control) end)
    owner:HookScript("OnHide",function(control) control.assistantPressed=false end)
    syncNativeControl(owner)
    return owner
end

local function skinSurface(object,key,texture)
    if key~="header" and key~="list" and key~="card" and not (texture and key=="stripe") then return end
    nativeSurfaces[#nativeSurfaces+1]={object=object,key=key,texture=texture}
    local token="color.addonAssistant."..(appearanceTheme()=="native" and "native." or "")..key
    if texture then G:SetTexturePaintKey(object,token) else object:SetSurfaceKey(token) end
end

local function registerDialogAppearance(dialog)
    -- Overlay supplies the interaction; WindowAppearance alone paints the shell.
    -- Keep the base panel transparent across primitive/theme refreshes as well.
    G:ApplyBackdrop(dialog,"color.addonAssistant.clear")
    G:SetBorderColor(dialog,"color.addonAssistant.clear")
    nativeControl(dialog.ok,"button"); nativeControl(dialog.cancel,"button")
    function dialog:Open()
        -- Native shell frames sit below their content owner; keep the scrim below both.
        G.Overlay:ShowModalScrim(self,{alpha=.28,frameLevel=math.max(0,self:GetFrameLevel()-3)})
        self:Show()
    end
    G.WindowAppearance:Register(dialog,{themeProvider=appearanceTheme,role="helper",nativeLayout="Dialog",nativeBorderOverflow=true,
        heading=dialog.title,headingColorKey="color.text.heading",onRefresh=function(owner,context)
            if owner.gui2Shadow then owner.gui2Shadow:SetShown(context.source~="native") end
        end})
end

local function refreshNativeCheck(check)
    local native=R.char and R.char.skin=="native"
    local issue=check.assistantDependencyIssue==true and check:GetChecked()
    if native and not check.native then
        local n=G:CreateFrame(check,{type="CheckButton",template="UICheckButtonTemplate",width=24,height=24,mouse=false})
        check.native=n; n:SetPoint("CENTER",check.box,"CENTER"); n:EnableMouse(false)
        local setChecked,setDisabled=check.SetChecked,check.SetDisabled
        check.SetChecked=function(owner,value,silent)
            local changed=setChecked(owner,value,silent); n:SetChecked(owner:GetChecked()); return changed
        end
        check.SetDisabled=function(owner,value,force) setDisabled(owner,value,force); n:SetEnabled(not value) end
    end
    if check.native then
        check.native:SetShown(native and not issue); check.native:SetChecked(check:GetChecked()); check.native:SetEnabled(not check.gui2Disabled)
    end
    check.box:SetShown(not native and not issue)
    if check.assistantIssueSurface then check.assistantIssueSurface:SetShown(issue==true) end
end

local function checkbox(parent,opts)
    local check=G.Form:CreateCheckbox(parent,opts)
    skinnedChecks[#skinnedChecks+1]=check; refreshNativeCheck(check)
    return check
end

function V:RefreshAppearance()
    for _,owner in ipairs(nativeControls) do owner:RefreshTheme() end
    for _,entry in ipairs(nativeSurfaces) do
        local token="color.addonAssistant."..(appearanceTheme()=="native" and "native." or "")..entry.key
        if entry.texture then G:SetTexturePaintKey(entry.object,token) else entry.object:SetSurfaceKey(token) end
    end
    for _,check in ipairs(skinnedChecks) do refreshNativeCheck(check) end
    if self.ruleScroll then self:LayoutAppearance() end
end

local function surface(parent, key, x, y, width, height, radius)
    local panel = G:CreateSolidRoundedSurface(parent, {width=width,height=height,
        surface="color.addonAssistant."..key,radiusPixels=radius or 5,mouse=false})
    panel:SetPoint("TOPLEFT",x,y); panel:SetFrameLevel(parent:GetFrameLevel())
    skinSurface(panel,key,false)
    return panel
end

local function painted(parent, key, layer)
    local texture=G:CreateTexture(parent,{layer=layer or "BACKGROUND"})
    G:SetTexturePaintKey(texture,key)
    skinSurface(texture,key:match("^color%.addonAssistant%.(.+)$"),true)
    return texture
end

local function actionTone(b, tone)
    if b.addonAssistantTone==tone then return b end
    b.addonAssistantTone=tone
    local prefix="color.addonAssistant.action."..tone.."."
    b.gui2SurfaceToken=prefix.."normal"; b.gui2HoverSurfaceToken=prefix.."hover"; b.gui2PressedSurfaceToken=prefix.."pressed"
    b.gui2SelectedSurfaceToken=prefix.."normal"
    b.gui2BorderToken=prefix.."border"; b.gui2HoverBorderToken=prefix.."border"; b.gui2PressedBorderToken=prefix.."border"; b.gui2SelectedBorderToken=prefix.."border"
    b.gui2TextColorKey="color.text.primary"; b.gui2HoverTextColorKey="color.text.primary"
    b.gui2PressedTextColorKey="color.text.primary"; b.gui2SelectedTextColorKey="color.text.primary"
    b:RefreshTheme()
    return b
end

local function iconButton(parent, icon, x, y, callback, hint, tone)
    local micro=(icon=="paintbrush" or icon=="chart-bar-big") and G:GetSettingsMicroIcon(icon,16) or nil
    local b = G.Form:CreateIconButton(parent, {size=26,icon=micro and micro.texture or G:GetSettingsIcon(icon),texCoords=micro and micro.texCoords,crop=false,
        onClick=callback,tooltip=hint,tone="default"})
    b:SetPoint("TOPLEFT",x,y)
    if tone then actionTone(b,tone) end
    return nativeControl(b,icon=="x" and "close" or "icon")
end

local function text(parent, value, x, y, width, color, size)
    local label = G:CreateText(parent, value, size or "font.size.md", color or "color.text.primary", "LEFT")
    label:SetPoint("TOPLEFT", x, y); label:SetWidth(width); label:SetWordWrap(false)
    return label
end
local function button(parent, value, x, y, width, callback, hint, tone)
    local b = G.Form:CreateButton(parent, { text = value, width = width, height = 26, onClick = callback, tooltip = hint, tone = "default" })
    b:SetPoint("TOPLEFT", x, y)
    if tone then actionTone(b,tone) end
    return nativeControl(b,value=="<" and "icon" or "button")
end
local function quietButton(b)
    b.assistantQuiet=true
    b.gui2SurfaceToken="color.addonAssistant.clear"
    b.gui2HoverSurfaceToken="color.addonAssistant.hover"
    b.gui2PressedSurfaceToken="color.control.active"
    b.gui2BorderToken="color.addonAssistant.clear"
    b.gui2HoverBorderToken="color.addonAssistant.clear"
    b.gui2PressedBorderToken="color.addonAssistant.clear"
    b:RefreshTheme()
    return b
end
local function dropdown(parent, x, y, width, options, value, changed, extra)
    local opts={width=width,height=26,options=options,value=value,onChange=function(_,selected) changed(selected) end}
    for key, option in pairs(extra or {}) do opts[key]=option end
    local d = G.Form:CreateDropdown(parent, opts)
    d:SetPoint("TOPLEFT", x, y)
    return nativeControl(d,"dropdown")
end
local function tooltip(owner, title, lines)
    G.Tooltip:Show(owner, { title = title, content = function(body)
        for _, line in ipairs(lines or {}) do body:AddLine(line) end
    end })
end

local function dependencyTooltip(owner, blocked, unavailable)
    local lines={L["dependency.unavailable"]}
    for _,name in ipairs(R:Names(unavailable)) do lines[#lines+1]=name end
    lines[#lines+1]=L["dependency.affected"]
    for _,name in ipairs(R:Names(blocked)) do lines[#lines+1]=name end
    tooltip(owner,L["dependency.disabled"],lines)
end

function V:DependencyDetails(record)
    local lines={L["dependency.disabled"]}
    local path=M.DependencyPath(record.name,R.draft,R.byName)
    if path then
        local last=path[#path]
        path[#path]=string.format(L[R.byName[last] and "dependency.offName" or "dependency.missingName"],last)
        lines[#lines+1]=string.format(L["dependency.path"],table.concat(path," > "))
    end
    lines[#lines+1]=L["dependency.selectedHint"]
    return lines
end

local function fitScrollContent(scroll, height)
    local viewport=scroll:GetHeight()
    local contentHeight=math.max(viewport,height)
    if scroll.child:GetHeight()~=contentHeight then scroll.child:SetHeight(contentHeight) end
    local maximum=math.max(0,height-viewport)
    if scroll:GetVerticalScroll()>maximum then scroll:SetVerticalScroll(maximum) end
end

function V:Modal(title, height)
    if self.menu then self.menu:Hide() end
    if not self.modal then
        self.modal = G.Overlay:CreateConfirmDialog(self.window, {width=460,height=height,cancelText=L.cancel,confirmText=L.confirm})
        self.modal:SetPoint("CENTER"); self.modal:SetFrameStrata("DIALOG"); self.modal:SetFrameLevel(self.window:GetFrameLevel() + 30)
        registerDialogAppearance(self.modal)
        self.modal:EnableMouse(true)
        self.modal.notice = text(self.modal, "", 18, -36, 420, "color.state.error", "font.size.md")
        self.modal.input = G.Form:CreateEditBox(self.modal, { width = 420, height = 28 })
        nativeControl(self.modal.input,"field")
        self.modal.input:SetPoint("TOPLEFT", 18, -64)
        self.modal.input:SetScript("OnEscapePressed", function() self.modal:Hide() end)
        self.modal.input:SetScript("OnEnterPressed", function() self.modal.ok:Click() end)
        self.modal:HookScript("OnHide", function()
            self.modal.input:ClearFocus()
            if self.modal.copyInput then self.modal.copyInput:ClearFocus() end
        end)
    end
    local m = self.modal
    m:Hide(); m:SetHeight(height); m.title:SetText(title); m.body:Hide(); m.bodyScroll:Hide(); m.input:Hide(); m.notice:SetText(""); R.error = nil
    G:SetTextColorKey(m.notice,"color.state.error")
    if m.copyInput then m.copyInput:Hide() end
    if m.copyManifest then m.copyManifest:Hide() end
    m.manifestText=nil
    m.body:SetWidth(394)
    m.cancel:Show(); m.accept=function() return true end
    if m.ruleFields then m.ruleFields:Hide() end
    if m.sceneFields then m.sceneFields:Hide() end
    if m.feedback then m.feedback:Hide(); m.existing:Hide() end
    if m.saveSwitch then m.saveSwitch:Hide() end
    m.ok:SetDisabled(false)
    m.cancel:ClearAllPoints(); m.cancel:SetPoint("BOTTOMRIGHT", -126, 16)
    m.ok:ClearAllPoints(); m.ok:SetPoint("BOTTOMRIGHT", -18, 16)
    m.ok:SetText(L.confirm)
    m.ok:SetWidth(100)
    m:Open(); return m
end

function V:Confirm(title, message, callback)
    local m = self:Modal(title, 180)
    m:SetMessage(message,400); m.accept = callback
end

function V:NameProfile(rename)
    local m = self:Modal(rename and L.rename or L.newProfile, 154)
    m.input:SetText(rename and R.db.profiles[R.editing].name or "")
    m.input:Show(); m.input:SetFocus(); m.input:HighlightText()
    m.accept = function()
        if rename then
            local name, err = M.ValidName(m.input:GetText(), R.db.profiles, R.editing)
            if not name then R:Error(err); return false end
            R.db.profiles[R.editing].name = name; R:Notify(); return true
        end
        return R:SaveProfile(m.input:GetText(), true)
    end
end

function V:Menu(anchor, items, identity)
    if self.menu and self.menu:IsShown() and self.menu.identity == identity then self.menu:Hide(); return end
    if not self.menu then
        self.menu = G:CreateSolidRoundedSurface(self.window,{width=190,height=140,surface="color.addonAssistant.header",radiusPixels=6,mouse=true})
        local menu = self.menu
        menu:SetFrameLevel(self.window:GetFrameLevel()+20); menu.buttons={}
        menu:EnableKeyboard(true); menu:SetPropagateKeyboardInput(true)
        menu:SetScript("OnKeyDown",function(owner,key)
            owner:SetPropagateKeyboardInput(key~="ESCAPE")
            if key=="ESCAPE" then owner:Hide() end
        end)
        menu.dismiss=G:CreateButtonFrame(menu); menu.dismiss:SetAllPoints(UIParent)
        menu.dismiss:SetFrameLevel(menu:GetFrameLevel()-1)
        menu.dismiss:SetScript("OnClick",function() menu:Hide() end)
    end
    local menu=self.menu; menu.identity=identity
    for i,item in ipairs(items) do
        local entry=menu.buttons[i]
        if not entry then
            entry=quietButton(G.Form:CreateButton(menu,{text="",width=178,height=28,tone="default",contentAlign="left",justifyH="LEFT",textLeftPadding=10,
                onClick=function(owner) menu:Hide(); owner.action() end}))
            entry:SetPoint("TOPLEFT",6,-6-(i-1)*28); menu.buttons[i]=entry
        end
        entry:SetText(item.text); entry.action=item.action; entry:Show()
    end
    for i=#items+1,#menu.buttons do menu.buttons[i]:Hide() end
    menu:SetHeight(#items*28+12); menu:SetPropagateKeyboardInput(true)
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-3); menu:Show()
end

function V:GroupMenu(row)
    if not row.item or #row.item.children==0 then return end
    local node=row.item
    self:Menu(row.name,{
        {text=L.groupAll,action=function() R:Group(node,"all") end},
        {text=L.groupNone,action=function() R:Group(node,"none") end},
        {text=L.groupRestore,action=function() R:Group(node,"restore") end},
    },node.name)
end

function V:Manifest()
    local profile=R.db.profiles[R.editing]
    local m=self:Modal(L.manifest.." · "..profile.name,400)
    local colors={"color.state.error","color.state.warning","color.text.primary","color.state.success"}
    local lines,plain={},{}
    local records, current=A.Client.Scan()
    if not records then R:Error(current); return end
    local installed=M.Index(records)
    for _,entry in ipairs(M.Manifest(profile,installed,current)) do
        local r,g,b=G:GetColor(colors[entry.rank])
        lines[#lines+1]=string.format("|cff%02x%02x%02x%s|r",math.floor(r*255),math.floor(g*255),math.floor(b*255),entry.title)
        plain[#plain+1]=entry.title
    end
    m.manifestText=table.concat(plain,"\n")
    m.body:SetText(#lines>0 and table.concat(lines,"\n") or L.empty)
    m.body:SetHeight(0)
    m.body:SetHeight(math.max(24,m.body:GetStringHeight()+8)); m.bodyScroll.child:SetHeight(m.body:GetHeight())
    m.bodyScroll:SetHeight(285); m.bodyScroll:SetVerticalScroll(0); m.body:Show(); m.bodyScroll:Show()
    if not m.copyManifest then
        m.copyManifest=button(m,L["manifest.copy"],18,-358,124,function() self:CopyManifest() end)
        m.copyManifest:ClearAllPoints(); m.copyManifest:SetPoint("BOTTOMLEFT",18,16)
    end
    m.copyManifest:SetDisabled(#plain==0); m.copyManifest:Show()
    m.cancel:Hide(); m.ok:SetText(L.close); m.accept=function() return true end
end

function V:CopyManifest()
    local m=self.modal
    if not m or not m.manifestText or m.manifestText=="" then return end
    if not m.copyInput then
        local edit=G.Form:CreateEditBox(m.bodyScroll.child,{width=394,height=285})
        m.copyInput=edit
        edit:SetPoint("TOPLEFT"); edit:SetMultiLine(true); edit:SetMaxLetters(0); edit:SetTextInsets(8,8,8,8)
        edit:SetScript("OnEscapePressed",function() m:Hide() end)
        edit:HookScript("OnTextChanged",function(owner,userInput)
            if userInput and owner:GetText()~=m.manifestText then owner:SetText(m.manifestText or "") end
        end)
    end
    -- Measure the same plain names at the editable text width, including wrapped titles.
    m.body:SetWidth(378); m.body:SetText(m.manifestText); m.body:SetHeight(0)
    local height=math.max(285,m.body:GetStringHeight()+16)
    m.body:Hide(); m.copyInput:SetHeight(height); m.copyInput:SetText(m.manifestText)
    fitScrollContent(m.bodyScroll,height); m.bodyScroll:SetVerticalScroll(0)
    m.notice:SetText(L["manifest.copyHint"]); G:SetTextColorKey(m.notice,"color.text.primary")
    m.copyInput:Show(); m.copyInput:SetFocus(); m.copyInput:HighlightText()
end

function V:ChooseProfile(id)
    if id==R.editing or not R.db.profiles[id] then self:Refresh(); return end
    local function load() return R:SelectProfile(id) end
    if not R:Unsaved() then load(); return end
    self:Refresh()
    self:Confirm(L.saveChanges,string.format(L.switchProfileHint,R.db.profiles[R.editing].name,R.db.profiles[id].name),load)
    local m=self.modal
    m.ok:SetText(L.discardSwitch); m.ok:SetWidth(130)
    m.cancel:ClearAllPoints(); m.cancel:SetPoint("BOTTOMLEFT",18,16)
    if not m.saveSwitch then m.saveSwitch=button(m,L.saveSwitch,0,0,130,function() if R:SaveProfile() and load() then m:Hide() end end) end
    m.saveSwitch:SetScript("OnClick",function() if R:SaveProfile() and load() then m:Hide() end end)
    m.saveSwitch:ClearAllPoints(); m.saveSwitch:SetPoint("BOTTOMRIGHT",m.ok,"BOTTOMLEFT",-8,0); m.saveSwitch:Show()
end

function V:Search(show)
    if self.menu then self.menu:Hide() end
    self.searching=show
    if show then self.searchInput:SetFocus()
    else self.searchInput:ClearFocus(); self.searchInput:SetText(""); self.query=""; self:FilterRows() end
end

function V:ToggleSkin()
    R.char.skin=R.char.skin=="native" and "dark" or "native"
    if self.window then G.WindowAppearance:Refresh(self.window) end
    if self.monitor then G.WindowAppearance:Refresh(self.monitor) end
    if self.modal then G.WindowAppearance:Refresh(self.modal) end
    if self.switchPreview then G.WindowAppearance:Refresh(self.switchPreview) end
    self:RefreshAppearance()
end

-- Keep the outer window and font sizes fixed. Only the native content budget shrinks.
function V:LayoutAppearance()
    local native=appearanceTheme()=="native"
    local inset=native and 12 or 0
    if self.contentInset==inset then return end
    self.contentInset=inset
    self.headerCompaction=native and 24 or 0
    WIDTH=WINDOW_WIDTH-2*inset
    FILTER_X,TAG_X,COUNT_X=512,636,760
    RULE_WIDTH=WIDTH-42; RULE_CARD_WIDTH=(RULE_WIDTH-RULE_GAP)/2
    self.content:ClearAllPoints(); self.content:SetPoint("TOPLEFT",inset,-inset); self.content:SetWidth(WIDTH)
    self.title:ClearAllPoints(); self.title:SetPoint("CENTER",self.window,"TOP",0,native and -13 or -24)
    self.title:SetHeight(native and 24 or 36)
    for index,control in ipairs({self.close,self.monitorButton,self.skinButton,self.sourceButton}) do
        control:ClearAllPoints()
        control:SetSize(native and 20 or 26,native and 20 or 26)
        control:SetPoint("TOPRIGHT",-12-(index-1)*(native and 26 or 32),native and -3 or -11)
    end
    self.navigation:SetWidth(WIDTH-24); self.plugins:SetWidth(WIDTH)
    self.navigation:ClearAllPoints(); self.navigation:SetPoint("TOPLEFT",12,-44+self.headerCompaction)
    self.plugins:ClearAllPoints(); self.plugins:SetPoint("TOPLEFT",0,-76+self.headerCompaction)
    self.rules:ClearAllPoints(); self.rules:SetPoint("TOPLEFT",12,-76+self.headerCompaction)
    self.toolbarControls:SetWidth(WIDTH-24); self.sceneStrip:SetWidth(WIDTH-24)
    self.searchInput:SetWidth(FILTER_X-24); self.count:SetWidth(WIDTH-12-COUNT_X)
    self.head:SetWidth(WIDTH-24); self.headBackground:SetWidth(WIDTH-24)
    self.listSurface:SetWidth(WIDTH-24); self.scroll:SetWidth(WIDTH-42); self.scroll.child:SetWidth(WIDTH-42)
    self.empty:SetWidth(WIDTH-100)
    self.footer:SetWidth(WIDTH-24); self.message:SetWidth(550-2*inset)
    self.enableAll:ClearAllPoints(); self.enableAll:SetPoint("TOPLEFT",WIDTH-380,0)
    self.disableAll:ClearAllPoints(); self.disableAll:SetPoint("TOPLEFT",WIDTH-264,0)
    self.reload:ClearAllPoints(); self.reload:SetPoint("TOPLEFT",WIDTH-148,0)
    self.rules:SetWidth(WIDTH-24); self.ruleScroll:SetWidth(RULE_WIDTH); self.ruleScroll.child:SetWidth(RULE_WIDTH)
    self.ruleScope:ClearAllPoints(); self.ruleScope:SetPoint("TOPLEFT",RULE_WIDTH-300,0)
    self.addScene:ClearAllPoints(); self.addScene:SetPoint("TOPLEFT",RULE_WIDTH-128,-76)
    self.ruleEmpty:SetWidth(RULE_WIDTH-28)
    self.layoutHeight,self.listTop=nil,nil
    self:RefreshSceneSummary(); self:LayoutAddonList(); self:Refresh()
end

function V:LayoutMonitorAppearance()
    if not self.monitorContent then return end
    local native=appearanceTheme()=="native"
    local inset=native and 8 or 0
    local width=300-2*inset
    self.monitorInset,self.monitorInnerWidth=inset,width
    local content=self.monitorContent
    content:ClearAllPoints(); content:SetPoint("TOPLEFT",inset,-inset); content:SetWidth(width)
    self.monitorTitle:SetWidth(146-2*inset)
    self.monitorTitle:ClearAllPoints()
    self.monitorTitle:SetPoint("TOPLEFT",self.monitor,"TOPLEFT",12,native and -1 or -12)
    self.monitorTitle:SetHeight(native and 24 or 16); self.monitorTitle:SetJustifyV("MIDDLE")
    for index,control in ipairs({self.monitorBack,self.monitorMode,self.monitorClose}) do
        control:ClearAllPoints()
        control:SetSize(index==2 and 58 or (native and 20 or 26),native and 20 or 26)
        if native then
            control:SetPoint("TOPRIGHT",self.monitor,"TOPRIGHT",({-102,-38,-12})[index],-3)
        else
            control:SetPoint("TOPLEFT",({166,198,264})[index],-8)
        end
    end
    self.monitorHeader:SetWidth(width); self.monitorHeader:SetShown(not native); self.monitorTotal:SetWidth(width-24)
    for _,row in ipairs(self.monitorRows) do
        row:SetWidth(width-24); row.name:SetWidth(width-108)
    end
    self.monitorFooter:SetWidth(width-24)
    local buttonWidth=(width-36)/3
    for index,control in ipairs({self.monitorCollect,self.monitorReset,self.monitorRefresh}) do
        control:ClearAllPoints(); control:SetPoint("TOPLEFT",(index-1)*(buttonWidth+6),0)
        control:SetWidth(buttonWidth)
    end
    self.monitorFeedback:SetWidth(width-24)
    local maximum=math.max(MONITOR_MIN_HEIGHT,math.min(MONITOR_TOP+MONITOR_FOOTER+MONITOR_MAX_ROWS*MONITOR_ROW,
        UIParent:GetHeight()-32-2*inset))
    self.monitor:SetResizeBounds(300,MONITOR_MIN_HEIGHT+2*inset,300,maximum+2*inset)
    local preferred=tonumber(R.char.monitorHeight) or MONITOR_HEIGHT
    self.monitor:SetHeight(math.max(MONITOR_MIN_HEIGHT,math.min(maximum,preferred))+2*inset)
    self.monitorLayoutHeight=nil
    self:LayoutMonitorHeight()
end

function V:LayoutMonitorHeight()
    if not self.monitorFooter then return end
    local height=self.monitor:GetHeight()-2*(self.monitorInset or 0)
    local feedback=self.monitorFeedback:IsShown() and self.monitorFeedback:GetHeight()+6 or 0
    if self.monitorLayoutHeight==height and self.monitorFeedbackSpace==feedback then return end
    self.monitorLayoutHeight,self.monitorFeedbackSpace=height,feedback
    self.monitorContent:SetHeight(height)
    local capacity=math.max(1,math.min(MONITOR_MAX_ROWS,math.floor((height-MONITOR_TOP-MONITOR_FOOTER-feedback)/MONITOR_ROW)))
    if self.monitorCapacity~=capacity then
        self.monitorCapacity=capacity; self:RenderMonitorRows()
    end
end

function V:StopMonitorResizing()
    if not self.monitorResizing then return end
    self.monitorResizing=false; self.monitor:StopMovingOrSizing()
    local height=math.floor(self.monitor:GetHeight()+.5)
    self.monitor:SetHeight(height); R.char.monitorHeight=height-2*(self.monitorInset or 0)
end

function V:NewMonitorRow(index)
    local width=self.monitorInnerWidth or 300
    local row=G:CreateFrame(self.monitorContent,{width=width-24,height=MONITOR_ROW,mouse=true})
    row:SetPoint("TOPLEFT",12,-MONITOR_TOP-(index-1)*MONITOR_ROW)
    if index%2==0 then local stripe=painted(row,"color.addonAssistant.stripe"); stripe:SetAllPoints() end
    row.name=text(row,"",4,-2,width-108)
    row.value=text(row,"",0,-2,70,"color.text.heading"); row.value:SetJustifyH("RIGHT")
    row.value:ClearAllPoints(); row.value:SetPoint("TOPRIGHT",-4,-2)
    row:SetScript("OnEnter",function(owner) if owner.item then tooltip(owner,owner.item.title,{L.monitorHint}) end end)
    row:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row:Hide()
    return row
end

function V:RenderMonitorRows()
    if not self.monitorRanked or not self.monitor:IsShown() then return end
    local capacity=self.monitorCapacity or 12
    for i=1,math.max(capacity,#self.monitorRows) do
        local row=self.monitorRows[i]
        if not row and i<=capacity then row=self:NewMonitorRow(i); self.monitorRows[i]=row end
        local item=i<=capacity and self.monitorRanked[i] or nil
        if row.item~=item then
            row.item=item; row:SetShown(item~=nil)
            if item then
                if row.name:GetText()~=item.title then row.name:SetText(item.title) end
                local value=self.monitorFormat(item.value)
                if row.value:GetText()~=value then row.value:SetText(value) end
                local color=item.value~=nil and "color.text.heading" or "color.text.secondary"
                if row.value.usageColor~=color then G:SetTextColorKey(row.value,color); row.value.usageColor=color end
            else G.Tooltip:Hide(row) end
        end
    end
end

function V:ShowMonitor()
    if not R.active or not R.char then return end
    if not self.monitor then
        local w=G:CreateFrame(UIParent,{name="YUIAddonAssistantMonitor",width=300,height=MONITOR_HEIGHT,hidden=true,mouse=true})
        self.monitor=w; w:SetPoint("CENTER"); w:SetFrameStrata("HIGH"); w:SetClampedToScreen(true); w:SetMovable(true); w:SetResizable(true)
        -- Keep the persistent monitor out of the Escape-close window list.
        local content=G:CreateFrame(w,{width=300,height=MONITOR_HEIGHT})
        content:SetPoint("TOPLEFT"); self.monitorContent=content
        self.monitorHeader=surface(content,"header",0,0,300,38,0)
        local drag=G:CreateFrame(content,{width=162,height=38,mouse=true})
        drag:SetPoint("TOPLEFT"); drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart",function() w:StartMoving() end)
        drag:SetScript("OnDragStop",function() w:StopMovingOrSizing() end)
        self.monitorTitle=text(drag,L.monitorTitle,12,-12,146)
        self.monitorMode=button(content,"",198,-8,58,function()
            R.char.monitorMetric=R.char.monitorMetric=="memory" and "cpu" or "memory"
            R:StartMetrics()
        end,L.monitorMetricHint)
        self.monitorClose=iconButton(content,"x",264,-8,function() w:Hide() end,L.close)
        self.monitorBack=button(content,"<",166,-8,26,function() self:Show() end)
        self.monitorBack:HookScript("OnEnter",function(owner) tooltip(owner,L.monitorBack) end)
        self.monitorBack:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
        self.monitorTotal=text(content,"",12,-42,276,"color.text.heading")
        self.monitorRows={}
        self.monitorFooter=G:CreateFrame(content,{width=276,height=26})
        self.monitorFooter:SetPoint("BOTTOMLEFT",12,12)
        self.monitorCollect=button(self.monitorFooter,L.monitorCollect,0,0,88,function() self:MonitorAction("memory") end,L.monitorCollectHint,"success")
        self.monitorReset=button(self.monitorFooter,L.monitorReset,94,0,88,function() self:MonitorAction("cpu") end,L.monitorResetHint,"warning")
        self.monitorRefresh=button(self.monitorFooter,L.monitorRefresh,188,0,88,function() self:MonitorAction("refresh") end,nil,"accent")
        self.monitorFeedback=text(content,"",12,0,276)
        self.monitorFeedback:ClearAllPoints(); self.monitorFeedback:SetPoint("BOTTOMLEFT",12,44)
        self.monitorFeedback:SetWordWrap(true); self.monitorFeedback:Hide()
        self.monitorResizeHandle=G:CreateButtonFrame(w,{width=44,height=10})
        self.monitorResizeHandle:SetPoint("BOTTOM",0,1)
        for i=1,2 do
            local line=painted(self.monitorResizeHandle,"color.text.secondary","ARTWORK")
            line:SetSize(20,1); line:SetPoint("CENTER",0,i*3-4)
        end
        self.monitorResizeHandle:SetScript("OnMouseDown",function(_,key)
            if key=="LeftButton" then self.monitorResizing=true; w:StartSizing("BOTTOM") end
        end)
        self.monitorResizeHandle:SetScript("OnMouseUp",function() self:StopMonitorResizing() end)
        self.monitorResizeHandle:SetScript("OnEnter",function(owner) tooltip(owner,L["window.resizeHeight"]) end)
        self.monitorResizeHandle:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
        w:HookScript("OnSizeChanged",function() self:LayoutMonitorHeight() end)
        G.WindowAppearance:Register(w,{themeProvider=function() return R.char.skin=="native" and "native" or "dark" end,
            heading=self.monitorTitle,headingColorKey="color.text.primary",role="helper",noTopBar=true,
            onRefresh=function() self:LayoutMonitorAppearance()
            end
        })
        w:HookScript("OnShow",function() if not R:StartMetrics() then self:RefreshMonitor() end end)
        w:HookScript("OnHide",function()
            self:StopMonitorResizing(); G.Tooltip:Hide(self.monitorResizeHandle)
            self.monitorRanked=nil
            for _,row in ipairs(self.monitorRows) do G.Tooltip:Hide(row); row.item=nil; row:Hide() end
            R:StartMetrics()
        end)
    end
    self.monitorFeedback:SetText(""); self.monitorFeedback:Hide()
    self:LayoutMonitorAppearance()
    self.window:Hide()
    self.monitor:Show()
end

function V:MonitorAction(action)
    if not R.active or not self.monitor or not self.monitor:IsShown() then return end
    local result,success
    if action=="memory" then
        local reclaimed=YUI.SystemMetricsUsage.ReclaimMemory()
        success=reclaimed~=nil
        result=success and string.format(L.monitorReclaimed,YUI.SystemMetricsUsage.FormatMemory(reclaimed)) or L.monitorActionFailed
    elseif action=="cpu" then
        success=A.Client.ResetCPU()
        result=success and L.monitorResetDone or L.monitorActionFailed
    else success=true; result=L.monitorRefreshed end
    self.monitorFeedback:SetText(result)
    self.monitorFeedback:SetHeight(0); self.monitorFeedback:SetHeight(math.max(20,self.monitorFeedback:GetStringHeight()))
    self.monitorFeedback:Show(); self:LayoutMonitorHeight()
    G:SetTextColorKey(self.monitorFeedback,success and "color.state.success" or "color.state.warning")
    R:StopMetrics(); R:StartMetrics()
end

function V:RefreshMonitor()
    if not self.monitor or not self.monitor:IsVisible() then return end
    self.monitorReset:SetDisabled(not A.Client.CanResetCPU())
    local metric=R.char.monitorMetric=="memory" and "memory" or "cpu"
    local usage,context=YUI.SystemMetricsUsage,R.metricContext or {}
    local ranked={}
    local totalMemory,memoryKnown=0,true
    if metric=="memory" then
        for _,record in ipairs(R.records) do
            if record.loaded then
                local value=(R.metrics[record.name] or {}).memory
                totalMemory=totalMemory+(value or 0); memoryKnown=memoryKnown and value~=nil
            end
        end
    end
    for _,group in ipairs(R.rows) do
        local sum,known,loaded=0,true,0
        for _,name in ipairs(group.members) do
            if R.byName[name].loaded then
                loaded=loaded+1
                local value=(R.metrics[name] or {})[metric]
                known=known and value~=nil; sum=sum+(value or 0)
            end
        end
        if loaded>0 then
            local value=known and sum or nil
            if metric=="cpu" then value=usage.Percent(value,context.application,context.total) end
            ranked[#ranked+1]={title=(group.record.displayTitle or group.record.title).."|r"..(loaded>1 and (" ("..loaded..")") or ""),
                name=group.name,value=value}
        end
    end
    table.sort(ranked,function(a,b)
        if a.value==b.value then return a.name<b.name end
        if a.value==nil then return false end
        if b.value==nil then return true end
        return a.value>b.value
    end)
    local format=metric=="memory" and usage.FormatMemory or usage.FormatPercent
    local total
    if metric=="memory" then total=memoryKnown and totalMemory or nil
    else total=usage.Percent(context.total,context.application,context.total) end
    local modeText,totalText=L["column."..metric],string.format(L.monitorTotal,format(total))
    if self.monitorMode:GetText()~=modeText then self.monitorMode:SetText(modeText) end
    if self.monitorTotal:GetText()~=totalText then self.monitorTotal:SetText(totalText) end
    self.monitorRanked,self.monitorFormat=ranked,format
    self:RenderMonitorRows()
end

function V:Build()
    if self.window then return end
    registerTheme(); L=A.L
    local w=G:CreateFrame(UIParent,{name="YUIAddonAssistantWindow",width=WIDTH,height=DEFAULT_HEIGHT,hidden=true})
    self.window=w
    self.content=G:CreateFrame(w,{width=WIDTH,height=DEFAULT_HEIGHT}); self.content:SetPoint("TOPLEFT")
    w:SetPoint("CENTER"); w:SetFrameStrata("HIGH"); w:SetClampedToScreen(true); w:SetMovable(true); w:EnableMouse(true)
    w:SetResizable(true)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="YUIAddonAssistantWindow" end
    local header=G:CreateFrame(w,{width=WIDTH-108,height=42,mouse=true}); header:SetPoint("TOPLEFT"); header:RegisterForDrag("LeftButton")
    header:SetFrameLevel(w:GetFrameLevel()+2)
    self.headerBackground=painted(header,"color.addonAssistant.header","BACKGROUND")
    self.headerBackground:SetPoint("TOPLEFT",w,"TOPLEFT",6,-6)
    self.headerBackground:SetPoint("BOTTOMRIGHT",w,"TOPRIGHT",-6,-42)
    header:SetScript("OnDragStart",function() w:StartMoving() end)
    header:SetScript("OnDragStop",function() w:StopMovingOrSizing() end)
    self.titleBar=header
    self.title=text(header,L.title,0,0,WIDTH,"color.text.primary","font.size.lg")
    self.title:ClearAllPoints(); self.title:SetPoint("CENTER",w,"TOP",0,-24)
    self.title:SetHeight(36); self.title:SetJustifyH("CENTER"); self.title:SetJustifyV("MIDDLE")
    self.navigation=G:CreateFrame(self.content,{width=WIDTH-24,height=26}); self.navigation:SetPoint("TOPLEFT",12,-44)
    local navigation=self.navigation
    self.tabs=G.Form:CreateUnderlineTabs(navigation,{width=205,height=26,gap=24,colorKey="color.text.primary",selectedColorKey="color.text.heading",
        items={{text=L.addons,value="addons"},{text=L.auto,value="rules"}},value=self.tab,onChange=function(_,value) self:SetTab(value) end})
    self.tabs:SetPoint("TOPLEFT",0,0)
    self.autoDot=painted(navigation,"color.state.success","ARTWORK"); self.autoDot:SetSize(4,4)
    self.autoDot:SetPoint("LEFT",self.tabs.buttons[2].text,"RIGHT",6,0)
    self.tabs.buttons[2]:HookScript("OnEnter",function(owner) tooltip(owner,L.auto,{R.db.automatic and L.autoOn or L.autoOff}) end)
    self.tabs.buttons[2]:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    self.close=iconButton(w,"x",922,-11,function() w:Hide() end,L.close)
    self.skinButton=iconButton(w,"paintbrush",858,-11,function() self:ToggleSkin() end,L.skinToggle)
    self.monitorButton=iconButton(w,"chart-bar-big",890,-11,function() self:ShowMonitor() end,L.monitorOpen)
    self.sourceButton=nativeControl(G.Form:CreateButton(w,{width=26,height=26,tone="default",
        textLeftPadding=2,textRightPadding=2,tooltip=L.sourceHint}),"icon")
    self.sourceButton:SetText("?")
    self.sourceButton:SetPoint("TOPLEFT",826,-11)
    for _,control in ipairs({self.sourceButton,self.skinButton,self.monitorButton,self.close}) do control:SetFrameLevel(header:GetFrameLevel()+1) end
    G.WindowAppearance:Register(w,{themeProvider=function() return R.char.skin=="native" and "native" or "dark" end,
        heading=self.title,headingColorKey="color.text.primary",role="helper",noTopBar=true,
        onRefresh=function(_,context)
            self.headerBackground:SetShown(context.source~="native")
            self:RefreshAppearance()
        end
    })
    self.plugins=G:CreateFrame(self.content,{width=WIDTH,height=504}); self.plugins:SetPoint("TOPLEFT",0,-76)
    local controls=G:CreateFrame(self.plugins,{width=WIDTH-24,height=26}); controls:SetPoint("TOPLEFT",12,0); self.toolbarControls=controls
    local profileLabel=text(controls,L.profile,0,0,48)
    profileLabel:SetHeight(26); profileLabel:SetJustifyV("MIDDLE")
    self.profile=dropdown(controls,56,0,230,function() return R:ProfileOptions(false,true) end,R.editing,function(value) self:ChooseProfile(value) end,
        {menuWidth=440,getLabel=function(value) local profile=R.db.profiles[value]; return profile and profile.name or "" end})
    self.profileCount=text(self.profile,"",0,-7,42); self.profileCount:SetJustifyH("RIGHT")
    self.profileState=text(self.profile,"",0,-7,72); self.profileState:SetJustifyH("RIGHT")
    self.profile:HookScript("OnMouseUp",function() self:LayoutProfileLabel() end)
    self.profile:HookScript("OnEnter",function(owner)
        local profile=R.db.profiles[R.editing]
        local lines={string.format(L.profileSelectionHint,M.Total(profile.addons),M.Total(R.draft))}
        if R:Unsaved() then lines[#lines+1]=L.modifiedHint end
        if not M.Same(R.baseline,R.draft) then lines[#lines+1]=L.switchHint end
        tooltip(owner,profile.name,lines)
    end)
    self.profile:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    self.save=iconButton(controls,"save",294,0,function() R:SaveProfile() end,L.save,"success")
    self.restoreSaved=iconButton(controls,"rotate-ccw",326,0,function()
        if not R:Unsaved() then return end
        if self.menu then self.menu:Hide() end
        R:SelectProfile(R.editing)
    end,L.restoreSaved.."\n"..L.restoreSavedHint,"warning")
    self.manifest=iconButton(controls,"eye",358,0,function() self:Manifest() end,L.manifest,"accent")
    local divider=painted(controls,"color.border.strong"); divider:SetSize(1,18); divider:SetPoint("TOPLEFT",390,-4)
    self.newProfile=iconButton(controls,"plus",398,0,function() self:NameProfile(false) end,L.newProfile,"accent")
    self.renameProfile=iconButton(controls,"pencil",430,0,function() self:NameProfile(true) end,L.rename)
    self.deleteProfile=iconButton(controls,"trash-2",462,0,function()
        local id=R.editing
        self:Confirm(L.deleteProfile,L.deleteProfileHint,function() return R:DeleteProfile(id) end)
    end,L.deleteProfile,"danger")
    self:BuildSceneSummary()
    self.count=text(self.plugins,"",COUNT_X,0,WIDTH-12-COUNT_X); self.count:SetJustifyH("RIGHT")
    self.count:SetHeight(26); self.count:SetJustifyV("MIDDLE")
    self.searchInput=G.Form:CreateEditBox(self.plugins,{width=488,height=26,placeholder=L.searchHint,searchPlaceholder=true,
        onChange=function(_,value) self.query=string.lower(value); self:FilterRows() end})
    nativeControl(self.searchInput,"field")
    self.searchInput:SetPoint("TOPLEFT",12,-38)
    self.searchInput:SetScript("OnEscapePressed",function() self:Search(false) end)
    self.filterSelect=dropdown(self.plugins,FILTER_X,-38,112,function()
        local options={}; for _,key in ipairs({"all","enabled","disabled","locked"}) do options[#options+1]={value=key,text=L[key]} end
        options[#options+1]={value="changes",text=(self.onlyChanges and "✓ " or "")..L.onlyChanges}
        return options
    end,self.filter,function(value)
        if value=="changes" then self.onlyChanges=not self.onlyChanges else self.filter=value end
        self.filterSelect:SetValue(self.filter,{silent=true,force=true}); self:FilterRows()
    end,{menuWidth=220,getLabel=function() return self.onlyChanges and (self.filter=="all" and L.onlyChanges or L[self.filter].." · "..L.changedShort) or L[self.filter] end})
    self.tagSelect=dropdown(self.plugins,TAG_X,-38,112,function()
        local options={{value="all",text=L.allTags}}
        for _,key in ipairs(A.TagOrder) do options[#options+1]={value=key,text=L["tag."..key]} end
        return options
    end,self.tag,function(value) self.tag=value; self:FilterRows() end,{menuWidth=180})
    self.metricValues={}
    self.listSurface=surface(self.plugins,"list",12,-76,WIDTH-24,396,6)
    self.head=G:CreateFrame(self.plugins,{width=WIDTH-24,height=28}); self.head:SetPoint("TOPLEFT",12,-76)
    self.headBackground=surface(self.head,"header",0,0,WIDTH-24,28,4); self.columns={}
    for _,key in ipairs({"enabled","name","tags","cpu","memory"}) do
        local column=G:CreateButtonFrame(self.head,{width=75,height=28})
        column.label=G:CreateText(column,L["column."..key],"font.size.md","color.text.primary","CENTER"); column.label:SetAllPoints(column)
        column:SetScript("OnClick",function() R:Resort(key) end)
        column:SetScript("OnEnter",function(owner)
            local lines={L.sortHint}
            if key=="cpu" or key=="memory" then lines[#lines+1]=L[key.."TotalHint"] end
            tooltip(owner,L["column."..key],lines)
        end)
        column:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end); self.columns[key]=column
    end
    self.scroll=G:CreateScrollFrame(self.plugins,{width=WIDTH-42,height=360,childWidth=WIDTH-42,childHeight=360})
    self.scroll:SetPoint("TOPLEFT",12,-108)
    self.scroll:HookScript("OnVerticalScroll",function() if self.menu then self.menu:Hide() end; self:RenderRows(true) end)
    self.empty=text(self.scroll,L.empty,20,-45,860)
    self.footer=G:CreateFrame(self.content,{width=WIDTH-24,height=36}); self.footer:SetPoint("BOTTOMLEFT",12,10)
    self.message=text(self.footer,"",4,-7,550)
    self.enableAll=button(self.footer,L.enableAll,580,0,108,function() R:Bulk(true) end,nil,"success")
    self.disableAll=button(self.footer,L.disableAll,696,0,108,function() R:Bulk(false) end,L.bulkHint,"danger")
    self.reload=button(self.footer,L.applyReload,812,0,124,function() R:Apply(false) end,nil,"accent")
    self.reload:HookScript("OnEnter",function(owner)
        if self.unloadable and next(self.unloadable) then dependencyTooltip(owner,self.unloadable,self.unavailableDependencies) end
    end)
    self.reload:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    self.resizeHandle=G:CreateButtonFrame(w,{width=44,height=12})
    self.resizeHandle:SetPoint("BOTTOM",0,1)
    self.resizeHandle:SetScript("OnMouseDown",function(_,key)
        if key=="LeftButton" then
            if self.menu then self.menu:Hide() end
            self.resizing=true; w:StartSizing("BOTTOM")
        end
    end)
    self.resizeHandle:SetScript("OnMouseUp",function() self:StopResizing() end)
    self.resizeHandle:SetScript("OnEnter",function(owner) tooltip(owner,L["window.resizeHeight"]) end)
    self.resizeHandle:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    for i=1,2 do
        local line=painted(self.resizeHandle,"color.text.secondary","ARTWORK")
        line:SetSize(20,1); line:SetPoint("CENTER",0,i*3-4)
    end
    self:BuildRules()
    self:RefreshAppearance()
    w:HookScript("OnSizeChanged",function() self:LayoutAddonList() end)
    w:HookScript("OnHide",function()
        self:StopResizing(); G.Tooltip:Hide(self.resizeHandle)
        R:UpdateEvents(); R:StartMetrics()
        for _,row in ipairs(self.pool) do G.Tooltip:Hide(row.name); G.Tooltip:Hide(row.tags); G.Tooltip:Hide(row.lock); G.Tooltip:Hide(row.check) end
        if self.modal then self.modal:Hide() end
        if self.menu then self.menu:Hide() end
        if self.tagPopup then self.tagPopup:Hide() end
        G.Tooltip:Hide(self.profile)
        G.Tooltip:Hide(self.tabs.buttons[2])
        for _, chip in ipairs(self.sceneChips or {}) do G.Tooltip:Hide(chip) end
        R:Evaluate("state")
    end)
    w:HookScript("OnShow",function()
        R:UpdateEvents(); R:Evaluate(false); self:Refresh(); R:StartMetrics()
    end)
end

function V:StopResizing()
    if not self.resizing then return end
    self.resizing=false; self.window:StopMovingOrSizing()
    local height=math.floor(self.window:GetHeight()+.5)
    self.window:SetHeight(height)
    R.char.windowHeight=height
end

function V:FitWindow()
    -- Fit the minimum height first; taller preferences use available space without shrinking text.
    local scale=math.min(1,(UIParent:GetWidth()-32)/WINDOW_WIDTH,(UIParent:GetHeight()-32)/MIN_HEIGHT)
    scale=math.max(.1,scale)
    self.window:SetScale(scale)
    local maximum=math.max(MIN_HEIGHT,math.min(MAX_HEIGHT,math.floor((UIParent:GetHeight()-32)/scale)))
    self.window:SetResizeBounds(WINDOW_WIDTH,MIN_HEIGHT,WINDOW_WIDTH,maximum)
    local preferred=tonumber(R.char.windowHeight) or DEFAULT_HEIGHT
    self.window:SetHeight(math.max(MIN_HEIGHT,math.min(maximum,preferred)))
    self:LayoutAddonList()
end

function V:LayoutProfileLabel()
    self.profileState:ClearAllPoints(); self.profileState:SetPoint("RIGHT",-26,0)
    self.profileCount:ClearAllPoints(); self.profileCount:SetPoint("RIGHT",self.profileState,"LEFT",-6,0)
    if self.profile.text and self.profile.text.ClearAllPoints then
        self.profile.text:ClearAllPoints(); self.profile.text:SetPoint("LEFT",8,0); self.profile.text:SetPoint("RIGHT",self.profileCount,"LEFT",-8,0)
    end
end

function V:BuildSceneSummary()
    self.sceneStrip=G:CreateFrame(self.plugins,{width=WIDTH-24,height=30}); self.sceneStrip:SetPoint("TOPLEFT",12,-32)
    self.sceneChips={}
    for index=1,#A.SceneOrder do
        local chip=G.Form:CreateButton(self.sceneStrip,{text="",width=160,height=28,onClick=function(owner)
            self:SetTab("rules")
        end})
        nativeControl(chip,"field")
        -- Paint on the button itself: an inset child frame leaves a visible seam at fractional UI scales.
        chip.segment=painted(chip,"color.addonAssistant.header")
        chip.segment:SetPoint("TOPLEFT",0,0); chip.segment:SetPoint("BOTTOMLEFT",0,0)
        chip.sceneLabel=text(chip,"",7,0,70,"color.text.secondary")
        chip.sceneLabel:SetHeight(28); chip.sceneLabel:SetJustifyV("MIDDLE")
        chip.profileLabel=text(chip,"",0,-7,100)
        chip.count=text(chip,"",0,-7,32); chip.count:SetJustifyH("RIGHT")
        chip:SetScript("OnEnter",function(owner)
            local rule=R.db.rules[owner.scene]; local profile=rule and R.db.profiles[rule.profile]
            local lines={L.scene..": "..L["scene."..owner.scene],L.profile..": "..(profile and profile.name or "")}
            if owner.scene=="default" then lines[#lines+1]=L.defaultHint end
            lines[#lines+1]=L.editSceneHint
            for _, exception in ipairs(R.db.exceptions) do
                if exception.scene==owner.scene and R.db.profiles[exception.profile] then lines[#lines+1]=self:SpecLabel(exception)..": "..R.db.profiles[exception.profile].name end
            end
            tooltip(owner,L["scene."..owner.scene],lines)
        end)
        chip:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
        self.sceneChips[index]=chip
    end
    self.addSceneChip=iconButton(self.sceneStrip,"plus",0,0,function() self:SetTab("rules"); self:SceneDialog() end,L.addScene)
end

function V:RefreshSceneSummary()
    local entries=R:SceneOptions()
    local canAdd=#R:SceneOptions(true)>0
    -- Give profile names a stable text budget; never measure already clipped labels.
    local columns=math.min(3,#entries)
    local gap=12
    local width=math.min(320,math.floor((WIDTH-24-(canAdd and 38 or 0)-(columns-1)*gap)/columns))
    for i, entry in ipairs(entries) do
        local chip=self.sceneChips[i]; local profile=R.db.profiles[R.db.rules[entry.value].profile]
        chip.scene=entry.value; chip.sceneLabel:SetText(entry.text); chip.profileLabel:SetText(profile.name)
        chip.count:SetText("("..M.Total(profile.addons)..")")
        chip:ClearAllPoints(); chip:SetPoint("TOPLEFT",((i-1)%columns)*(width+gap),-math.floor((i-1)/columns)*34)
        chip:SetWidth(width); chip:Show()
        chip.sceneLabel:SetWidth(0); chip.count:SetWidth(0)
        local segmentWidth=math.ceil(chip.sceneLabel:GetStringWidth())+14
        local countWidth=chip.count:GetStringWidth()+1
        chip.segment:SetWidth(segmentWidth); chip.sceneLabel:SetWidth(segmentWidth-14)
        chip.profileLabel:ClearAllPoints(); chip.profileLabel:SetPoint("LEFT",chip.segment,"RIGHT",8,0)
        chip.profileLabel:SetWidth(width-segmentWidth-countWidth-22)
        chip.count:SetWidth(countWidth); chip.count:ClearAllPoints(); chip.count:SetPoint("RIGHT",-7,0)
    end
    for i=#entries+1,#self.sceneChips do self.sceneChips[i]:Hide() end
    self.sceneSummaryHeight=math.ceil(#entries/columns)*34+2
    self.sceneStrip:SetHeight(self.sceneSummaryHeight)
    self.addSceneChip:ClearAllPoints(); self.addSceneChip:SetPoint("TOPRIGHT",0,-1); self.addSceneChip:SetShown(canAdd)
    self.sceneStrip:SetShown(R.db.automatic==true)
end

function V:LayoutAddonList()
    local top=32+(R.db.automatic and (self.sceneSummaryHeight or 36) or 0)
    local height=self.window:GetHeight()-2*(self.contentInset or 0)
    if self.layingOut or self.layoutHeight==height and self.listTop==top then return end
    self.layingOut=true
    -- Height-only changes do not move the fixed toolbar or column header.
    if self.listTop~=top then
        self.searchInput:ClearAllPoints(); self.searchInput:SetPoint("TOPLEFT",12,-top)
        self.filterSelect:ClearAllPoints(); self.filterSelect:SetPoint("TOPLEFT",FILTER_X,-top)
        self.tagSelect:ClearAllPoints(); self.tagSelect:SetPoint("TOPLEFT",TAG_X,-top)
        self.count:ClearAllPoints(); self.count:SetPoint("TOPLEFT",COUNT_X,-top)
        self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT",12,-top-40)
        self.listSurface:ClearAllPoints(); self.listSurface:SetPoint("TOPLEFT",12,-top-40)
        self.scroll:ClearAllPoints(); self.scroll:SetPoint("TOPLEFT",12,-top-72)
    end
    self.layoutHeight,self.listTop=height,top
    self.content:SetHeight(height)
    local reclaimed=self.headerCompaction or 0
    self.plugins:SetHeight(height-136+reclaimed)
    local viewport=math.max(ROW,height-212-top+reclaimed)
    local changed=self.scroll:GetHeight()~=viewport
    self.scroll:SetHeight(viewport); self.listSurface:SetHeight(viewport+36)
    if changed and self.visible then
        fitScrollContent(self.scroll,#self.visible*ROW)
    end
    self.rules:SetHeight(height-110+reclaimed)
    self.ruleScroll:SetHeight(height-150+reclaimed)
    fitScrollContent(self.ruleScroll,self.ruleContentHeight or 0)
    self.layingOut=false
    if changed then self:RenderRows(true) end
end

function V:ColumnPositions()
    local inset=WINDOW_WIDTH-WIDTH
    return {enabled=18,name=82,tags=478-inset,cpu=686-inset,memory=802-inset}, 386-inset
end

function V:Matches(record)
    local selected, locked, seen = R.draft[record.name], R.char.locks[record.name], R.db.seen[record.name]
    local changed = not not selected ~= not not R.baseline[record.name]
    if self.onlyChanges and not changed then return false end
    if self.filter == "enabled" and not selected or self.filter == "disabled" and selected or self.filter == "locked" and not locked
        or self.filter == "new" and seen then return false end
    if self.filter == "issues" then
        local _, missing = M.Resolve({[record.name]=true}, nil, R.byName)
        if not (self.unloadable and self.unloadable[record.name]) and not next(missing)
            and not (record.reason and record.reason ~= "DISABLED" and record.reason ~= "DEMAND_LOADED") then return false end
    end
    local tags = {}
    for _, tag in ipairs(record.tags) do tags[#tags+1] = L["tag." .. tag] end
    if self.tag ~= "all" then
        local match = false; for _, tag in ipairs(record.tags) do if tag == self.tag then match = true end end
        if not match then return false end
    end
    if self.query ~= "" then
        local haystack = string.lower(table.concat({record.name,record.title,record.author,table.concat(tags," ")}," "))
        if not haystack:find(self.query,1,true) then return false end
    end
    return true
end

function V:FilterRows()
    if not self.scroll or not R.order then return end
    local visible, count, flat, matched = {}, 0, {}, {}
    for _, node in ipairs(R.order) do flat[#flat+1]=node end
    local cursor=1
    while cursor<=#flat do
        local node=flat[cursor]; cursor=cursor+1
        for _, child in ipairs(node.children) do flat[#flat+1]=child end
    end
    for i=#flat,1,-1 do
        local node=flat[i]
        matched[node.name]=matched[node.name] or self:Matches(node.record)
        if matched[node.name] and node.parent then matched[node.parent.name]=true end
    end
    local stack={}
    for i=#R.order,1,-1 do
        local node=R.order[i]
        if matched[node.name] then stack[#stack+1]={node=node,depth=0}; count=count+1 end
    end
    while #stack>0 do
        local entry=table.remove(stack); local node=entry.node
        node.depth=entry.depth; node.nested=entry.depth>0
        visible[#visible+1]=node
        local reveal=not self:Matches(node.record)
        if R.expanded[node.name] or reveal then
            for i=#node.children,1,-1 do
                local child=node.children[i]
                if not reveal or matched[child.name] then stack[#stack+1]={node=child,depth=entry.depth+1} end
            end
        end
    end
    self.visible=visible
    fitScrollContent(self.scroll,#visible*ROW)
    self.count:SetText(string.format(L.listCount,M.Total(R.draft),#R.records))
    self.empty:SetShown(#visible==0)
    self:RenderRows()
end

local function smallIcon(parent, icon, callback)
    local control=G:CreateButtonFrame(parent,{width=16,height=16})
    control.icon=G:CreateTexture(control,{layer="ARTWORK"})
    control.icon:SetSize(14,14); control.icon:SetPoint("CENTER")
    control.icon:SetTexture(G:GetSettingsIcon(icon))
    control.colorKey="color.text.primary"
    control.RefreshTheme=function(owner) owner.icon:SetVertexColor(G:GetColor(owner.colorKey)) end
    control:RefreshTheme(); G:RegisterThemeObject(control)
    control:SetScript("OnClick",callback)
    return control
end

function V:RowHover(row, hovered)
    row.hover:SetShown(hovered)
    row.lock:SetShown(hovered or row.locked==true)
end

function V:NewRow()
    local row = G:CreateFrame(self.scroll.child, { width = WIDTH - 44, height = ROW })
    row.tint=painted(row,"color.addonAssistant.stripe"); row.tint:SetAllPoints()
    row.hover=painted(row,"color.addonAssistant.hover"); row.hover:SetAllPoints(); row.hover:Hide()
    row.check = checkbox(row, { width = 22, height = ROW, retainDisabledSelection = true, onChange = function(_, checked)
        if row.item then
            R:Toggle({row.item.name},checked)
        end
    end })
    row.check:SetPoint("LEFT", 26, 0)
    local issueSurface=G:CreatePanel(row.check,{width=18,height=18,surface="color.addonAssistant.dependency.fill",border="color.state.error",mouse=false})
    row.check.assistantIssueSurface=issueSurface
    issueSurface:SetAllPoints(row.check.box); issueSurface:Hide()
    local issueMark=G:CreateTexture(issueSurface,{layer="OVERLAY"})
    issueMark:SetTexture(G:GetSettingsIcon("check")); issueMark:SetSize(12,12); issueMark:SetPoint("CENTER")
    issueMark.RefreshTheme=function(mark) mark:SetVertexColor(G:GetColor("color.text.primary")) end
    issueMark:RefreshTheme(); G:RegisterThemeObject(issueMark)
    row.expand = smallIcon(row, "plus", function()
        if row.item then R.expanded[row.item.name] = not R.expanded[row.item.name]; self:FilterRows() end
    end)
    row.name = G:CreateButtonFrame(row, { height = ROW, width = 400 })
    row.name:SetPoint("LEFT", 82, 0)
    row.icon = G:CreateTexture(row.name, {layer="ARTWORK"}); row.icon:SetSize(20,20); row.icon:SetPoint("LEFT",0,0); row.icon:SetTexCoord(0,1,0,1)
    row.title = text(row.name, "", 27, -9, 350)
    row.issue=G:CreateText(row.name,"","font.size.sm","color.state.error","RIGHT")
    row.issue:SetPoint("TOPRIGHT",-2,-9); row.issue:SetWordWrap(false); row.issue:Hide()
    row.name:SetScript("OnEnter", function(owner)
        local record = row.item.record
        local lines = { record.name, record.notes, record.author }
        if #record.deps > 0 then lines[#lines+1] = L.dependencies .. ": " .. table.concat(record.deps, ", ") end
        if self.unloadable and self.unloadable[record.name] then
            for _,line in ipairs(self:DependencyDetails(record)) do lines[#lines+1]=line end
        end
        tooltip(owner, (record.displayTitle or record.title).."|r", lines)
    end)
    row.name:SetScript("OnLeave", function(owner) G.Tooltip:Hide(owner) end)
    row.name:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row.name:SetScript("OnClick", function(_,mouseButton)
        if mouseButton=="RightButton" then self:GroupMenu(row); return end
        if #row.item.children > 0 then R.expanded[row.item.name] = not R.expanded[row.item.name]; self:FilterRows()
        elseif not row.protected then R:Toggle(row.item.members, not R.draft[row.item.name]) end
    end)
    row.tags = G:CreateButtonFrame(row, {width=160,height=ROW})
    row.tagLabels, row.tagChips = {}, {}
    for i=1,3 do
        row.tagChips[i]=surface(row.tags,"stripe",(i-1)*49,-7,44,20,3)
        row.tagLabels[i] = G:CreateText(row.tagChips[i],"","font.size.md","color.text.primary","CENTER")
        row.tagLabels[i]:SetAllPoints(row.tagChips[i]); row.tagLabels[i]:SetWordWrap(false)
    end
    row.tags:SetScript("OnClick", function() self:EditTags(row.item.record) end)
    row.tags:SetScript("OnEnter", function(owner)
        local names = {}; for _, tag in ipairs(row.item.record.tags) do names[#names+1] = L["tag."..tag] end
        tooltip(owner, table.concat(names, " · "), {L.edit})
    end)
    row.tags:SetScript("OnLeave", function(owner) G.Tooltip:Hide(owner) end)
    row.lock=smallIcon(row,"unlock",function() if row.lockable then R:Lock({row.item.name}) end end)
    row.lock:SetPoint("LEFT",5,0)
    row.lock:SetScript("OnEnter",function(owner) tooltip(owner,row.locked and L.locked or L.lock,{L.lockedHint}) end)
    row.lock:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row.check:HookScript("OnEnter",function(owner)
        if row.item and self.unloadable and self.unloadable[row.item.name] then
            local lines=self:DependencyDetails(row.item.record)
            if row.protected then lines[#lines+1]=L.lockedHint end
            tooltip(owner,row.item.record.title,lines); return
        end
        if not row.protected then return end
        if row.locked then tooltip(owner,L.locked,{L.lockedHint}); return end
        local names={}
        for name,locked in pairs(R.char.locks) do
            if locked then
                local required=M.Resolve({[name]=true},nil,R.byName)
                if required[row.item.name] then names[#names+1]=R.byName[name] and R.byName[name].title or name end
            end
        end
        table.sort(names)
        tooltip(owner,L.lockedDependency,{table.concat(names,", "),L.lockedDependencyHint})
    end)
    row.check:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row.cpu=text(row,"",0,-10,88,"color.text.heading")
    row.memory=text(row,"",0,-10,88,"color.text.heading")
    row.cpu:SetJustifyH("CENTER"); row.memory:SetJustifyH("CENTER")
    row:SetScript("OnMouseUp",function(_,key) if key=="RightButton" then self:GroupMenu(row) end end)
    row:EnableMouse(true)
    for _,owner in ipairs({row,row.check,row.expand,row.name,row.tags,row.lock}) do
        owner:HookScript("OnEnter",function() self:RowHover(row,true) end)
        owner:HookScript("OnLeave",function() self:RowHover(row,row:IsMouseOver()) end)
    end
    row:HookScript("OnHide",function() row.hover:Hide(); G.Tooltip:Hide(row.lock); G.Tooltip:Hide(row.check) end)

    return row
end

function V:RenderRows(viewportOnly)
    if not self.visible or self.layingOut or self.tab~="addons" or not self.window:IsShown() then return end
    local start = math.floor(self.scroll:GetVerticalScroll() / ROW)
    local capacity=math.min(MAX_ROWS,math.ceil(self.scroll:GetHeight()/ROW)+1)
    if viewportOnly and self.rowStart==start and self.rowCapacity==capacity and self.rowList==self.visible then return end
    local positions,nameWidth,protected,newSuffix
    for i=1,math.max(capacity,#self.pool) do
        local item = i<=capacity and self.visible[start+i]
        local row = self.pool[i]
        if item and (not viewportOnly or not row or row.item~=item or row.index~=start+i) then
            if not positions then
                positions,nameWidth=self:ColumnPositions()
                protected=M.Resolve({},R.char.locks,R.byName)
                local r,g,b=G:GetColor("color.state.success")
                newSuffix=string.format("  |cff%02x%02x%02x· %s|r",math.floor(r*255),math.floor(g*255),math.floor(b*255),L.new)
            end
            if not row then row = self:NewRow(); self.pool[i] = row end
            if row.item~=item then G.Tooltip:Hide(row.name); G.Tooltip:Hide(row.tags); G.Tooltip:Hide(row.lock); G.Tooltip:Hide(row.check) end
            row:SetWidth(WIDTH-44)
            row.item,row.index = item,start+i
            row.tint:SetShown((start+i)%2==0 or item.nested)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(start+i-1)*ROW); row:Show()
            local enabled, new = 0, false
            local locked=R.char.locks[item.name]==true
            for _, name in ipairs(item.members) do
                enabled = enabled + (R.draft[name] and 1 or 0)
                new = new or not R.db.seen[name]
            end
            row.check:SetChecked(R.draft[item.name]==true,true)
            local disabled=protected[item.name]==true
            row.check:SetDisabled(disabled==true)
            row.protected=disabled==true
            local issue=self.unloadable and self.unloadable[item.name]==true
            row.check.assistantDependencyIssue=issue==true
            refreshNativeCheck(row.check)
            row.expand:SetShown(#item.children>0)
            row.expand.icon:SetTexture(G:GetSettingsIcon(R.expanded[item.name] and "minus" or "plus"))
            local indent=math.min(item.depth or 0,10)*18
            row.check:ClearAllPoints(); row.check:SetPoint("LEFT",26+indent,0)
            row.lock:ClearAllPoints(); row.lock:SetPoint("LEFT",5+indent,0)
            row.expand:ClearAllPoints(); row.expand:SetPoint("LEFT",56+indent,0)
            row.name:ClearAllPoints(); row.name:SetPoint("LEFT",82+indent,0); row.name:SetWidth(nameWidth-indent)
            row.issue:SetText(issue and L[self.directDependencyIssues[item.name] and "dependency.directShort" or "dependency.indirectShort"] or "")
            row.issue:SetShown(issue==true)
            local issueWidth=issue and math.min(row.issue:GetStringWidth()+8,math.max(0,row.name:GetWidth()-120)) or 0
            row.issue:SetWidth(issueWidth)
            row.title:SetWidth(math.max(0,nameWidth-32-indent-issueWidth))

            row.icon:SetTexture(nil)
            if item.record.iconAtlas then row.icon:SetAtlas(item.record.iconAtlas,false)
            else
                row.icon:SetTexture(item.record.icon)
                row.icon:SetTexCoord(unpack(item.record.iconCoords or {0,1,0,1}))
            end
            row.icon:SetShown(item.record.icon~=nil or item.record.iconAtlas~=nil)
            local moduleCount=enabled-(R.draft[item.name] and 1 or 0)
            local suffix = #item.children>0 and ("  ("..moduleCount.."/"..(#item.members-1)..")") or ""
            local checked=R.draft[item.name]==true
            local title=(issue or not checked) and item.record.title or (item.record.displayTitle or item.record.title)
            row.title:SetText(title.."|r"..suffix..(new and newSuffix or ""))
            G:SetTextColorKey(row.title,issue and "color.state.error" or checked and "color.text.primary" or "color.text.disabled")
            row.tags:ClearAllPoints(); row.tags:SetPoint("LEFT",positions.tags,0)
            row.tags:SetWidth(positions.cpu-positions.tags-12)
            local tagX=0; local chipWidths={}
            local totalWidth=0
            local tagCount=math.min(3,#item.record.tags)
            local tagBudget=(row.tags:GetWidth()-math.max(0,tagCount-1)*5)/math.max(1,tagCount)
            for index,label in ipairs(row.tagLabels) do
                local tag = item.record.tags[index]
                row.tagChips[index]:SetShown(tag~=nil)
                if tag then row.tagChips[index]:SetSurfaceKey("color.addonAssistant.tag."..tag) end
                label:SetText(index==3 and #item.record.tags>3 and ("+"..(#item.record.tags-2)) or (tag and L["tag."..tag] or ""))
                G:SetTextColorKey(label,tag and A.TagColors[tag] or "color.text.primary")
                local chipWidth=math.min(tagBudget,math.max(40,label:GetStringWidth()+14))
                chipWidths[index]=chipWidth
                if tag then totalWidth=totalWidth+chipWidth end
                row.tagChips[index]:SetSize(chipWidth,22)
            end
            totalWidth=totalWidth+math.max(0,tagCount-1)*5
            tagX=(row.tags:GetWidth()-totalWidth)/2
            for index=1,tagCount do
                row.tagChips[index]:ClearAllPoints(); row.tagChips[index]:SetPoint("TOPLEFT",tagX,-4)
                tagX=tagX+chipWidths[index]+5
            end
            row.locked=locked==true
            row.lockable=R.draft[item.name] or locked
            row.lock.icon:SetTexture(G:GetSettingsIcon(locked and "lock" or "unlock"))
            row.lock.colorKey=locked and "color.text.heading" or "color.text.primary"; row.lock:RefreshTheme()
            row.lock:SetAlpha(row.lockable and 1 or .45)
            self:RowHover(row,row:IsMouseOver())
            for _,key in ipairs({"cpu","memory"}) do
                row[key]:ClearAllPoints(); row[key]:SetPoint("TOPLEFT",positions[key],-10)
                row[key]:SetWidth(key=="cpu" and 110 or 132)
            end
            self:PaintMetrics(row)

        elseif not item and row and row.item then
            row.item=nil; row:Hide()
        end
    end
    self.rowStart,self.rowCapacity,self.rowList=start,capacity,self.visible
end

function V:PaintMetrics(row)
    local cpu,memory,cpuKnown,memoryKnown=0,0,true,true
    for _, name in ipairs(row.item.members) do
        local metric=R.metrics[name] or {}
        cpuKnown=cpuKnown and metric.cpu~=nil; memoryKnown=memoryKnown and metric.memory~=nil
        cpu=cpu+(metric.cpu or 0); memory=memory+(metric.memory or 0)
    end
    local usage=YUI.SystemMetricsUsage
    local context=R.metricContext or {}
    local percent=usage.Percent(cpuKnown and cpu or nil,context.application,context.total)
    local cpuText=usage.FormatPercent(percent)
    local memoryText=usage.FormatMemory(memoryKnown and memory or nil)
    if row.cpu:GetText()~=cpuText then row.cpu:SetText(cpuText) end
    if row.memory:GetText()~=memoryText then row.memory:SetText(memoryText) end
    for key,known in pairs({cpu=percent~=nil,memory=memoryKnown}) do
        local color=known and "color.text.heading" or "color.text.secondary"
        if row[key].usageColor~=color then G:SetTextColorKey(row[key],color); row[key].usageColor=color end
    end
end

function V:PaintMetricHeader(key)
    local column=self.columns[key]
    local arrow=R.sortKey==key and (R.descending and " ↓" or " ↑") or ""
    local value=string.format(L.metricTotal,L["column."..key],self.metricValues[key] or "—")..arrow
    if column.label:GetText()~=value then column.label:SetText(value) end
end

function V:RefreshMetrics()
    if self.metricValues then
        local usage=YUI.SystemMetricsUsage; local context=R.metricContext or {}
        local memory,known=0,true
        for _,record in ipairs(R.records) do local metric=R.metrics[record.name] or {}; known=known and metric.memory~=nil; memory=memory+(metric.memory or 0) end
        local values={cpu=usage.FormatPercent(usage.Percent(context.total,context.application,context.total)),memory=usage.FormatMemory(known and memory or nil)}
        for key,value in pairs(values) do self.metricValues[key]=value; self:PaintMetricHeader(key) end
    end
    for _,row in ipairs(self.pool) do if row:IsShown() and row.item then self:PaintMetrics(row) end end
end

function V:EditTags(record)
    local m = self:Modal(L.tags.." · "..record.title, 280)
    if not self.tagPopup then
        self.tagPopup = G:CreateFrame(m, {width=420,height=170}); self.tagPopup:SetPoint("TOPLEFT",18,-52)
        self.tagChecks = {}
        for i,tag in ipairs(A.TagOrder) do
            local check = checkbox(self.tagPopup,{text=L["tag."..tag],width=135,height=30})
            check:SetPoint("TOPLEFT",((i-1)%3)*140,-math.floor((i-1)/3)*36); self.tagChecks[tag]=check
        end
        m:HookScript("OnHide",function() self.tagPopup:Hide() end)
    end
    self.tagPopup:Show()
    local current={}; for _,tag in ipairs(record.tags) do current[tag]=true end
    for tag,check in pairs(self.tagChecks) do check:SetChecked(current[tag],true) end
    m.accept=function()
        local tags={}; for _,tag in ipairs(A.TagOrder) do if self.tagChecks[tag]:GetChecked() then tags[#tags+1]=tag end end
        R.db.tags[record.name],record.tags=M.Copy(tags),tags; R:Notify()
    end
end

function V:BuildRules()
    local p = G:CreateFrame(self.content,{width=WIDTH-24,height=526}); p:SetPoint("TOPLEFT",12,-76); self.rules=p
    local toggle=checkbox(p,{text=L.autoEnabled,width=170,height=26,onChange=function(_,value)
        R:SetAutomatic(value)
    end}); toggle:SetPoint("TOPLEFT"); self.autoToggle=toggle
    local mode=text(p,L.promptMode,182,0,300)
    mode:SetHeight(26); mode:SetJustifyV("MIDDLE")
    local scope=text(p,L.account,RULE_WIDTH-300,0,300); self.ruleScope=scope
    scope:SetHeight(26); scope:SetJustifyV("MIDDLE"); scope:SetJustifyH("RIGHT")
    self.ruleScroll=G:CreateScrollFrame(p,{width=RULE_WIDTH,height=488,childWidth=RULE_WIDTH,childHeight=488}); self.ruleScroll:SetPoint("TOPLEFT",0,-38)
    self.sceneHeading=text(self.ruleScroll.child,L.sceneRules,0,-76,350)
    self.sceneHeading:SetHeight(26); self.sceneHeading:SetJustifyV("MIDDLE")
    self.addScene=button(self.ruleScroll.child,L.addScene,RULE_WIDTH-128,-76,128,function() self:SceneDialog() end,nil,"accent")
    self.ruleEmpty=text(self.ruleScroll.child,L.addSceneHint,14,-128,RULE_WIDTH-28,"color.text.primary")
    self.exceptionTitle=text(self.ruleScroll.child,L.exceptions,0,-300,300,"color.text.primary")
    self.exceptionTitle:SetHeight(26); self.exceptionTitle:SetJustifyV("MIDDLE")
    self.addException=button(self.ruleScroll.child,L.addException,RULE_WIDTH-128,-296,128,function() self:ExceptionDialog() end,nil,"accent")
end

function V:NewRuleRow()
    local row=G:CreateFrame(self.ruleScroll.child,{width=RULE_WIDTH,height=36})
    row.background=surface(row,"card",0,0,RULE_WIDTH,34,6)
    row.accent=painted(row,"color.accent.primary","ARTWORK")
    row.accent:SetWidth(2); row.accent:SetPoint("TOPLEFT",0,-8); row.accent:SetPoint("BOTTOMLEFT",0,8)
    row.title=text(row,"",8,-9,290)
    row.defaultHint=G:CreateButtonFrame(row,{width=102,height=46})
    row.defaultHint:SetPoint("TOPLEFT",0,-5)
    row.defaultHint:SetScript("OnEnter",function(owner) tooltip(owner,L["scene.default"],{L.defaultHint}) end)
    row.defaultHint:SetScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row.sceneBadge=surface(row,"header",300,-10,130,26,4)
    row.sceneLabel=text(row,"",310,-16,110,"color.text.primary"); row.sceneLabel:SetJustifyH("CENTER")
    row.sceneIcon=G:CreateTexture(row,{layer="ARTWORK"}); row.sceneIcon:SetSize(22,22)
    row.icon=quietButton(button(row,"",12,-9,28,function() if row.exception then self:ExceptionDialog(row.exception) end end))
    row.iconTexture=G:CreateTexture(row.icon,{layer="ARTWORK"}); row.iconTexture:SetSize(22,22); row.iconTexture:SetPoint("CENTER"); row.iconTexture:SetTexCoord(.08,.92,.08,.92)
    row.icon:HookScript("OnEnter",function(owner) if row.rule then tooltip(owner,self:SpecLabel(row.rule),{row.reviewError and L[row.reviewError] or L.edit}) end end)
    row.icon:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row.profile=dropdown(row,340,-4,286,function() return R:ProfileOptions() end,"",function(value)
        if row.scene and not row.exception then R:SetRule(row.scene,value,row.rule.mode) end
    end,{menuWidth=560})
    row.exceptionProfile=G.Form:CreateButton(row,{width=RULE_WIDTH-534,height=26,text="",tone="default",contentAlign="left",justifyH="LEFT",textLeftPadding=12,
        onClick=function() self:ExceptionDialog(row.exception) end})
    nativeControl(row.exceptionProfile,"field")
    row.exceptionProfile:SetPoint("TOPLEFT",446,-10)
    row.exceptionProfile:HookScript("OnEnter",function(owner) local profile=R.db.profiles[row.rule.profile]; tooltip(owner,profile and profile.name or L.invalidRule,{L.edit}) end)
    row.exceptionProfile:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    row.edit=iconButton(row,"pencil",RULE_WIDTH-78,-10,function() self:ExceptionDialog(row.exception) end,L.edit,"accent")
    row.remove=iconButton(row,"x",RULE_WIDTH-40,-4,function()
        if row.exception then R:RemoveException(row.exception)
        else
            local associated=false
            for _, rule in ipairs(R.db.exceptions) do associated=associated or rule.scene==row.scene end
            if associated then self:Confirm(L.removeScene,string.format(L.removeSceneExceptions,L["scene."..row.scene]),function() return R:RemoveRule(row.scene,true) end)
            else R:RemoveRule(row.scene) end
        end
    end,nil,"danger")
    row.remove:HookScript("OnEnter",function(owner) tooltip(owner,row.exception and L.deleteException or L.removeScene,{row.exception and L.exceptionScopeHint or L.defaultHint}) end)
    row.remove:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    return row
end

function V:SpecLabel(rule)
    local info=YUI.API.Unit.GetClassInfoByID(rule.class)
    local label=info and info.className or tostring(rule.class)
    if rule.spec==0 then return label.." · "..L.allSpecs end
    for _,spec in ipairs(YUI.API.Talent.GetClassConfigurationSpecializations(rule.class)) do if spec.specID==rule.spec then return label.." · "..spec.name end end
    return label
end

function V:SpecIcon(rule)
    for _,spec in ipairs(YUI.API.Talent.GetClassConfigurationSpecializations(rule.class)) do if spec.specID==rule.spec then return spec.icon end end
    local icons={135328,135920,132222,132320,135940,135771,136048,135932,136145,608951,625999,1247264,4574311}
    return icons[rule.class] or 134400
end

function V:RefreshRules()
    if not self.rules then return end
    self.autoToggle:SetChecked(R.db.automatic,true)
    local count=0
    local function bind(scene,rule,exception,y,column)
        count=count+1; local row=self.rulePool[count]
        if not row then row=self:NewRuleRow(); self.rulePool[count]=row end
        row.scene,row.rule,row.exception=scene,rule,exception
        row.reviewError=exception and R:CheckException(exception,rule).error or nil
        local isDefault=scene=="default" and not exception
        local width,height=exception and RULE_WIDTH or RULE_CARD_WIDTH,exception and 46 or isDefault and 56 or 88
        row:SetSize(width,height); row.background:SetSize(width,height)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",column or 0,y); row:Show()
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT",46,isDefault and -20 or -16); row.title:SetText(exception and self:SpecLabel(rule) or L["scene."..scene])
        row.title:SetWidth(exception and 240 or isDefault and 56 or RULE_CARD_WIDTH-90)
        G:SetTextColorKey(row.title,row.reviewError and "color.state.warning" or "color.text.primary")
        row.defaultHint:SetShown(isDefault); row.sceneLabel:SetShown(exception~=nil); row.sceneBadge:SetShown(exception~=nil)
        row.accent:SetShown(not exception)
        if exception then row.sceneLabel:SetText(L["scene."..scene]) end
        row.sceneIcon:SetShown(not exception)
        if not exception then row.sceneIcon:ClearAllPoints(); row.sceneIcon:SetPoint("TOPLEFT",14,isDefault and -17 or -13); row.sceneIcon:SetAtlas(A.SceneAtlas[scene],false) end
        row.profile:ClearAllPoints(); row.profile:SetPoint("TOPLEFT",isDefault and 112 or 14,isDefault and -15 or -48)
        row.profile:SetWidth(isDefault and RULE_CARD_WIDTH-126 or RULE_CARD_WIDTH-28); row.profile:SetShown(not exception)
        row.exceptionProfile:SetWidth(RULE_WIDTH-534)
        row.edit:ClearAllPoints(); row.edit:SetPoint("TOPLEFT",RULE_WIDTH-78,-10)
        row.exceptionProfile:SetShown(exception~=nil)
        row.edit:SetShown(exception~=nil)
        if exception then row.exceptionProfile:SetText(R.db.profiles[rule.profile] and (R.db.profiles[rule.profile].name.." ("..M.Total(R.db.profiles[rule.profile].addons)..")") or L.invalidRule) end
        row.icon:SetShown(exception~=nil); row.remove:SetShown(not isDefault)
        row.remove:ClearAllPoints(); row.remove:SetPoint("TOPLEFT",width-40,-10)
        if exception then row.iconTexture:SetTexture(self:SpecIcon(rule)) end
        row.profile:SetValue(rule.profile or "",{silent=true,force=true})
    end
    bind("default",R.db.rules.default,nil,0)
    local added=0
    for _, scene in ipairs(A.SceneOrder) do
        if scene~="default" and R.db.rules[scene] then
            bind(scene,R.db.rules[scene],nil,-116-math.floor(added/2)*100,(added%2)*(RULE_CARD_WIDTH+RULE_GAP)); added=added+1
        end
    end
    self.ruleEmpty:SetShown(added==0); self.addScene:SetDisabled(#R:SceneOptions(true)==0)
    local top=116+(added==0 and 40 or math.ceil(added/2)*100)+16
    self.exceptionTitle:ClearAllPoints(); self.exceptionTitle:SetPoint("TOPLEFT",0,-top+7)
    self.addException:ClearAllPoints(); self.addException:SetPoint("TOPLEFT",RULE_WIDTH-128,-top+7)
    for i,rule in ipairs(R.db.exceptions) do bind(rule.scene,rule,i,-top-36-(i-1)*50) end
    for i=count+1,#self.rulePool do self.rulePool[i]:Hide() end
    self.ruleContentHeight=top+40+#R.db.exceptions*50
    fitScrollContent(self.ruleScroll,self.ruleContentHeight)
end

function V:SceneDialog()
    local available=R:SceneOptions(true); if #available==0 then return end
    local m=self:Modal(L.addScene,220)
    m.sceneDraft={scene=available[1].value,profile=R.editing}
    if not m.sceneFields then
        local f=G:CreateFrame(m,{width=420,height=110}); f:SetPoint("TOPLEFT",18,-56); m.sceneFields=f
        text(f,L.scene,0,-7,96); text(f,L.profile,0,-49,96)
        f.scene=dropdown(f,110,0,310,function() return R:SceneOptions(true) end,available[1].value,function(value) m.sceneDraft.scene=value end)
        f.profile=dropdown(f,110,-42,310,function() return R:ProfileOptions() end,R.editing,function(value) m.sceneDraft.profile=value end)
    end
    m.sceneFields:Show(); m.sceneFields.scene:SetValue(m.sceneDraft.scene,{silent=true,force=true}); m.sceneFields.profile:SetValue(m.sceneDraft.profile,{silent=true,force=true})
    m.accept=function()
        if R.db.rules[m.sceneDraft.scene] then return R:Error("duplicateScene") end
        return R:SetRule(m.sceneDraft.scene,m.sceneDraft.profile,R.db.rules.default.mode)
    end
end

function V:ExceptionDialog(index)
    local context=A.Client.Context() or {class=1}
    local rule=M.Copy(index and R.db.exceptions[index] or {class=context.class,spec=0,scene="default",profile=R.editing})
    local m=self:Modal(index and L.editException or L.addException,390)
    m.rule,m.ruleIndex=rule,index
    if not m.ruleFields then
        local f=G:CreateFrame(m,{width=420,height=188}); f:SetPoint("TOPLEFT",18,-54); m.ruleFields=f
        local labels={"class","spec","scene","profile"}
        for i,key in ipairs(labels) do text(f,L[key],0,-(i-1)*34-6,100,"color.text.primary") end
        f.class=dropdown(f,110,0,310,function()
            local options={}; for _,info in ipairs(YUI.API.Unit.GetClassInfos()) do options[#options+1]={value=info.classID,text=info.className} end; return options
        end,1,function(value) m.rule.class=value; m.rule.spec=0; f.spec:SetValue(0,{silent=true,force=true}); self:UpdateExceptionReview() end)
        f.spec=dropdown(f,110,-34,310,function()
            local options={{value=0,text=L.allSpecs}}
            for _,spec in ipairs(YUI.API.Talent.GetClassConfigurationSpecializations(m.rule.class)) do options[#options+1]={value=spec.specID,text=spec.name,icon=spec.icon} end
            return options
        end,0,function(value) m.rule.spec=value; self:UpdateExceptionReview() end)
        f.scene=dropdown(f,110,-68,310,function() return R:SceneOptions() end,"default",function(value) m.rule.scene=value; self:UpdateExceptionReview() end)
        f.profile=dropdown(f,110,-102,310,function() return R:ProfileOptions() end,"",function(value) m.rule.profile=value; self:UpdateExceptionReview() end)
    end
    m.rule=rule; local f=m.ruleFields
    for _,key in ipairs({"class","spec","scene","profile"}) do f[key]:SetValue(rule[key],{silent=true,force=true}) end
    if not m.feedback then
        m.feedback=text(m,"",18,-214,420,"color.text.primary"); m.feedback:SetWordWrap(true); m.feedback:SetHeight(90)
        m.existing=button(m,L.editExisting,18,-306,160,function() local existing=m.review and m.review.existing; if existing then self:ExceptionDialog(existing) end end)
    end
    f:Show(); m.feedback:Show(); self:UpdateExceptionReview()
    m.accept=function() return R:SetException(index,m.rule,true) end
end

function V:UpdateExceptionReview()
    local m=self.modal; if not m.ruleFields or not m.ruleFields:IsShown() then return end
    local review=R:CheckException(m.ruleIndex,m.rule); m.review=review
    local lines={}
    if review.error then lines[1]=L[review.error]
    else
        if review.parent then
            local parent=R.db.exceptions[review.parent]
            lines[#lines+1]=string.format(L.overrideRuleHint,self:SpecLabel(m.rule),R.db.profiles[m.rule.profile].name,R.db.profiles[parent.profile].name)
        end
        if #review.merge>0 then
            local names={}; for _, index in ipairs(review.merge) do names[#names+1]=self:SpecLabel(R.db.exceptions[index]) end
            lines[#lines+1]=string.format(L.mergeRulesHint,table.concat(names,", "))
        end
        if #review.overrides>0 then
            local names={}; for _, index in ipairs(review.overrides) do names[#names+1]=self:SpecLabel(R.db.exceptions[index]) end
            lines[#lines+1]=string.format(L.keepOverridesHint,table.concat(names,", "))
        end
        local scene=R.db.rules[m.rule.scene]
        if not review.parent and scene and scene.profile==m.rule.profile then lines[#lines+1]=L.sameSceneProfileHint end
        if #lines==0 then lines[1]=L.exceptionScopeHint end
    end
    m.feedback:SetText(table.concat(lines,"\n")); G:SetTextColorKey(m.feedback,review.error and "color.state.error" or (#review.merge>0 or review.parent or #review.overrides>0) and "color.state.warning" or "color.text.primary")
    local height=math.max(70,m.feedback:GetStringHeight()+8)
    m.feedback:SetHeight(height); m:SetHeight(math.max(390,214+height+84))
    m.existing:ClearAllPoints(); m.existing:SetPoint("TOPLEFT",18,-214-height-8)
    m.existing:SetShown(review.existing~=nil); m.ok:SetDisabled(review.error~=nil)
    m.ok:SetText(#review.merge>0 and (m.ruleIndex and L.mergeSave or L.mergeAdd) or m.ruleIndex and L.saveRule or L.confirm)
end

function V:SetTab(tab)
    self.tab=tab
    if self.menu then self.menu:Hide() end
    self:Refresh()
    R:StartMetrics()
end

function V:StopPrompt()
    self.testPending=nil
    if self.prompt then self.prompt:Hide() end
    if self.switchPreview then
        self.switchPreview:Hide(); self.switchPreview.accept=nil
        self.switchPreview.cancel:SetScript("OnClick",nil)
    end
end

function V:IsPromptCurrent(pending)
    if not pending then return false end
    if pending.preview then return self.testPending==pending end
    return R.pending==pending
end

function V:EnsurePrompt()
    if self.prompt then return end
    self.prompt=G.Overlay:CreateTimedNotice(UIParent,{width=380,height=90,
        icon=YUI.Assets:Core("images\\YUI-LOGO-300.png")})
    self.prompt:SetPoint("LEFT",50,-110)
    self.prompt:HookScript("OnEnter",function(owner)
        tooltip(owner,owner.fullTitle,{L["switch.openPreview"],owner.previewHint})
    end)
    self.prompt:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    self.prompt:HookScript("OnHide",function(owner) G.Tooltip:Hide(owner) end)
end

function V:StartPrompt(pending)
    L=A.L; self:EnsurePrompt()
    self.testPending=pending.preview and pending or nil
    local profile=pending.preview and {name=pending.profileName} or R.db.profiles[pending.profile]
    local records=pending.records or R.records
    local current=pending.current or A.Client.Read(records)
    if not profile or not current then R.remaining=nil; return end
    local added,removed=0,0
    for _,change in ipairs(M.Diff(current,pending.target,records)) do
        if change.enabled then added=added+1 else removed=removed+1 end
    end
    local function skip()
        if not self:IsPromptCurrent(pending) then return end
        if pending.preview then self:StopPrompt() else R:Skip() end
    end
    self.prompt.fullTitle=string.format(L.switchTo,profile.name)..(pending.preview and (" · "..pending.testLabel) or "")
    self.prompt.previewHint=pending.preview and pending.hint or nil
    self.prompt:Start({duration=60,pauseOnHover=false,title=self.prompt.fullTitle,
        body=G.Tooltip:ColorText(string.format(L["switch.added"],added),"success").." · "..
            G.Tooltip:ColorText(string.format(L["switch.removed"],removed),"warning"),
        onClick=function() self:PreviewSwitch(pending) end,onDismiss=skip,onExpire=skip,
        onTick=function(_,remaining)
            if not self:IsPromptCurrent(pending) then self:StopPrompt(); return end
            if not pending.preview then R.remaining=remaining end
        end,
    })
end

function V:PreviewSwitch(pending)
    if not self:IsPromptCurrent(pending) or not self.prompt:IsActive() then return end
    if not self.switchPreview then
        registerTheme()
        local p=G.Overlay:CreateConfirmDialog(UIParent,{width=620,height=382,cancelText=L.skip,confirmText=L.switchReload})
        self.switchPreview=p; p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(120)
        registerDialogAppearance(p)
        p.bodyScroll:Hide(); p.body:Hide()
        p.ok:SetWidth(154); p.cancel:ClearAllPoints(); p.cancel:SetPoint("BOTTOMRIGHT",-182,16)
        actionTone(p.ok,"accent")
        p.deltaColumns={}
        for index, key in ipairs({"added","removed"}) do
            local x=18+(index-1)*298
            local panel=G:CreatePanel(p,{width=286,height=232,surface="color.surface.raised",border="color.border.subtle"})
            nativeControl(panel,"field")
            panel:SetPoint("TOPLEFT",x,-54)
            local heading=text(panel,"",12,-12,262,key=="added" and "color.state.success" or "color.state.warning")
            local scroll=G:CreateScrollFrame(panel,{width=262,height=178,childWidth=254,childHeight=178})
            scroll:SetPoint("TOPLEFT",12,-42)
            local names=text(scroll.child,"",0,0,246); names:SetWordWrap(true)
            p.deltaColumns[index]={heading=heading,scroll=scroll,names=names}
        end
        p:HookScript("OnShow",function() self.prompt:Pause("preview") end)
        p:HookScript("OnHide",function() self.prompt:Resume("preview") end)
        p.settingsLink=quietButton(G.Form:CreateButton(p,{text=L["switch.settingsPath"],width=584,height=26,
            contentAlign="left",justifyH="LEFT",textLeftPadding=0,tone="default",onClick=function()
                self:StopPrompt(); self:Show(); self:SetTab("rules")
            end}))
        p.settingsLink:SetPoint("TOPLEFT",18,-302)
        p.dependencyWarning=text(p,"",18,-294,584,"color.state.warning")
        p.dependencyWarning:SetHeight(20)
        p.ok:HookScript("OnEnter",function(owner)
            if p.unloadable and next(p.unloadable) then dependencyTooltip(owner,p.unloadable,p.unavailableDependencies) end
        end)
        p.ok:HookScript("OnLeave",function(owner) G.Tooltip:Hide(owner) end)
    end
    local p=self.switchPreview
    local records=pending.records or R.records
    local current=pending.current or A.Client.Read(records); if not current then return end
    local byName,reverse=M.Index(records)
    p.unloadable,p.unavailableDependencies=M.Unloadable(pending.target,byName,reverse)
    local dependencyCount=M.Total(p.unavailableDependencies)
    p.dependencyWarning:SetText(dependencyCount>0 and string.format(L["dependency.disabledCount"],dependencyCount) or "")
    p.dependencyWarning:SetShown(dependencyCount>0)
    p:SetHeight(dependencyCount>0 and 406 or 382)
    p.settingsLink:ClearAllPoints(); p.settingsLink:SetPoint("TOPLEFT",18,dependencyCount>0 and -326 or -302)
    local names={{},{}}
    for _,change in ipairs(M.Diff(current,pending.target,records)) do
        local index=change.enabled and 1 or 2; names[index][#names[index]+1]=change.title
    end
    p.title:SetText(self.prompt.fullTitle)
    p.ok:SetText(pending.preview and pending.confirmText or L.switchReload)
    p.cancel:SetScript("OnClick",function()
        if not self:IsPromptCurrent(pending) then return end
        if pending.preview then self:StopPrompt() else R:Skip() end
    end)
    for index,column in ipairs(p.deltaColumns) do
        column.heading:SetText(string.format(L[index==1 and "switch.added" or "switch.removed"],#names[index]))
        column.names:SetText(#names[index]>0 and table.concat(names[index],"\n") or L.empty)
        column.names:SetHeight(0); column.names:SetHeight(math.max(24,column.names:GetStringHeight()+8))
        fitScrollContent(column.scroll,column.names:GetHeight()); column.scroll:SetVerticalScroll(0)
    end
    p.ok:SetDisabled(not A.Client.Safe())
    p.accept=function()
        if not self:IsPromptCurrent(pending) or not self.prompt:IsActive() then return false end
        if pending.preview then self:StopPrompt(); return true end
        return R:Apply(true,pending)
    end
    p:Open()
end

function V:RefreshPrompt()
    if self.testPending and A.Client.Safe() then return end
    if not R.pending or R:Interacting() or not A.Client.Safe() then self:StopPrompt() end
end

function V:Refresh(stateOnly)
    if not R.db then return end
    L=A.L; self:RefreshPrompt()
    if not self.window or not self.window:IsVisible() then return end
    if stateOnly then
        if self.tab=="addons" then
            self.reload:SetDisabled((M.Same(R.draft,R.baseline) and not R.reloadRequired) or not A.Client.Safe())
        end
        return
    end
    self.unloadable,self.unavailableDependencies,self.directDependencyIssues = M.Unloadable(R.draft,R.byName,R.reverse)
    if self.modal and self.modal:IsShown() then self.modal.notice:SetText(R.error or "") end
    self.autoDot:SetShown(R.db.automatic==true)
    self.tabs:SetValue(self.tab,true)
    self.plugins:SetShown(self.tab=="addons"); self.rules:SetShown(self.tab=="rules"); self.footer:SetShown(self.tab=="addons")
    self.toolbarControls:SetShown(self.tab=="addons")
    if self.tab=="addons" then self:RefreshSceneSummary() end
    self:LayoutAddonList()
    if self.tab=="addons" then
        self.profile:SetValue(R.editing,{silent=true,force=true})
        local changes=#M.Diff(R.baseline,R.draft,R.records)
        local stateLabel=R:Unsaved() and L.modified or changes>0 and L.pendingReload or L.applied
        self.profileCount:SetText("("..M.Total(R.db.profiles[R.editing].addons)..")"); self.profileState:SetText(stateLabel)
        self.profileCount:SetWidth(math.max(32,self.profileCount:GetStringWidth()+2)); self.profileState:SetWidth(math.max(54,self.profileState:GetStringWidth()+2))
        G:SetTextColorKey(self.profileState,(R:Unsaved() or changes>0) and "color.state.warning" or "color.text.primary")
        self:LayoutProfileLabel()
        local positions=self:ColumnPositions()
        for key,b in pairs(self.columns) do
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",positions[key],0)
            b.label:SetText(L["column."..key]..(R.sortKey==key and (R.descending and " ↓" or " ↑") or ""))
            b:SetWidth(key=="enabled" and 38 or key=="name" and 104 or key=="tags" and positions.cpu-positions.tags-12 or key=="cpu" and 110 or 132)
        end
        self.save:SetDisabled(not R:Unsaved())
        self.restoreSaved:SetDisabled(not R:Unsaved())
        self.deleteProfile:SetDisabled(#R:ProfileOptions()<2)
        local editing=R.db.profiles[R.editing]
        local message=R:Unsaved() and L.unsaved or L.saved
        if changes>0 then message=string.format(L.changes,changes)..(R:Unsaved() and (" · "..L.unsaved) or "") end
        local modal=self.modal and self.modal:IsShown()
        local dependencyCount = M.Total(self.unavailableDependencies)
        local warning = dependencyCount>0 and string.format(L["dependency.disabledCount"],dependencyCount)
        self.message:SetText(not modal and R.error or warning or message)
        G:SetTextColorKey(self.message,not modal and R.error and "color.state.error" or warning and "color.state.warning" or "color.text.primary")
        self.reload:SetDisabled((changes==0 and not R.reloadRequired) or not A.Client.Safe())
        self:FilterRows(); self:RefreshMetrics()
    else self:RefreshRules() end
end

function V:Show()
    if not R.active then R:Enable() end
    if not R.db then return end
    self:Build()
    if self.monitor then self.monitor:Hide() end
    self:FitWindow()
    if self.window:IsShown() then
        R:UpdateEvents(); R:Evaluate(false); self:Refresh(); R:StartMetrics()
    else self.window:Show() end
end

function V:Hide()
    if self.window then self.window:Hide() end
    if self.monitor then self.monitor:Hide() end
    if not R.active or not R.pending then self:StopPrompt() end
end
