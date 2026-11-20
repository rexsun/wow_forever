local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars) then return end

local B = { rows={}, dirty=true, states=setmetatable({}, {__mode="k"}), reads=0 }
YAB.PaladinBlessings = B
local Tools, Unit, Spell, Item, Safe = YAB.ClassTools, YUI.API.Unit, YUI.API.Spell, YUI.API.Item, YUI.API.Security
local G=YUI.GUI2
local L={width=440,padding=14,top=58,rowHeight=40,footer=50,selectX=118,selectWidth=188,statusX=316,castX=378,castSize=34,memberStep=32}
local PANEL_LAYOUT_ID="yactionbar.paladinBlessings.panel"
local PANEL_TIMER_MIN_DELAY=0.05
local GREATER_BLESSING_DURATION=3600
local unpack = unpack or table.unpack
local function Text(key) return YUI.Locale:Get("YActionBar")["class_tools." .. key] end
local function Combat() return YAB.Adapter:InCombat() end
local function Name(id)
    B.names=B.names or {};if B.names[id] then return B.names[id] end
    local info=Spell.GetInfo(id);local name=info and Safe.SafeString(info.name);B.names[id]=name;return name
end
local function Icon(id)
    B.icons=B.icons or {};if B.icons[id] then return B.icons[id] end
    local info=Spell.GetInfo(id);local texture=info and (Safe.SafeNumber(info.originalIconID) or Safe.SafeNumber(info.iconID));B.icons[id]=texture;return texture
end
local function Config() return YAB:GetDB().specialBars[B.entry and B.entry.id or "paladinBlessings"] end
local function Queue() YAB.BarManager:QueueSpecialRefresh(B.entry and B.entry.id or "paladinBlessings", "team-blessing") end
local function PanelTime() return YUI.API.System and Safe.SafeNumber(YUI.API.System.GetTime()) end
local function Font(parent, text, x, y, color, size)
    if Combat() then return end
    local label=G:CreateText(parent, text or "", size or "font.size.md", color or "color.text.primary", "LEFT")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    Tools:StyleText(label)
    return label
end
local function Caption(label, text)
    if label and label.blessingText~=text then label:SetText(text); label.blessingText=text end
end
local function ButtonCaption(host,text)
    local visual=host.blessingVisual
    if visual.text.blessingText~=text then visual:SetText(text);visual.text.blessingText=text end
end
local function Tone(label,key)
    if label and label.gui2ColorKey~=key then G:SetTextColorKey(label,key) end
end
-- Standard Form visuals remain mouse-inert; the existing secure host owns all
-- clicks, bindings and combat actions. Motion is off for protected parents.
local function ButtonVisual(host,opts)
    opts=opts or {};opts.motion=false;opts.tone="default";opts.fontSizeKey=opts.fontSizeKey or "font.size.md"
    local visual=G.Form:CreateButton(host,opts)
    visual:SetAllPoints(host);visual:EnableMouse(false)
    Tools:StyleText(visual.text)
    host.blessingVisual=visual
    local function State(state)
        visual:SetState(state)
        local color=host.blessingClassColor
        if color then visual.text.gui2ColorKey=nil;visual.text:SetTextColor(color.r,color.g,color.b,1) end
    end
    local function Rest() State(host.blessingSelected and "selected" or "normal") end
    host:HookScript("OnEnter",function() State("hover") end)
    host:HookScript("OnLeave",Rest)
    host:HookScript("OnMouseDown",function() State("pressed") end)
    host:HookScript("OnMouseUp",Rest)
    host:HookScript("OnHide",Rest)
    return visual
end
local function Portrait(parent, class, x, y, size)
    if Combat() then return end
    local texture=YUI.GUI2:CreateTexture(parent, {texture="Interface\\TargetingFrame\\UI-Classes-Circles", width=size, height=size, layer="OVERLAY"})
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local coords=CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then texture:SetTexCoord(unpack(coords)) end
    return texture
end
local function ClassName(class)
    for _, info in ipairs(Unit.GetClassInfos() or {}) do if info.classFile==class or info.classFilename==class or info.tag==class then return info.className or info.name end end
    return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end
local function Backdrop(parent)
    if Combat() then return end
    local panel=YUI.GUI2:CreatePanel(parent, {surface="color.surface.popup",border="color.border.subtle",shadow=true})
    panel:SetAllPoints(parent);panel:SetFrameLevel(math.max(0,parent:GetFrameLevel()-1));panel:EnableMouse(false)
    return panel
end
local function PrepareClick(button,mouse,down)
    if down or Combat() or (mouse~="LeftButton" and mouse~="Keybind") then return end
    if mouse=="LeftButton" and ((IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown())) then return end
    B:PrepareTarget(button)
end
local function TooltipTarget(tip, name, row)
    local color = row and Unit.GetClassColor(row.class)
    if color and color.WrapTextInColorCode then name = color:WrapTextInColorCode(name) end
    local r, g, b = G:GetColor("color.tooltip.body")
    tip:AddLine(string.format(Text("blessing_target"), name), r, g, b, true)
end
local function Tooltip(button)
    local state=B.states[button]
    if not state then return end
    if not button:IsShown() or not YAB.SecureFactory:ShouldShowTooltip(button) then
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        B.tooltipButton=nil;return
    end
    B.tooltipButton=button
    B:PrepareTarget(button)
    local tip, row = GameTooltip, state.row
    local spell=row and row.control:GetAttribute("blessing") or B:CurrentSpell()
    tip:SetOwner(button,"ANCHOR_RIGHT")
    Tools:TooltipTitle(tip,state.member and state.member.name or row and row.name or Text("teamBlessing"))
    if state.membersToggle then
        if #row.members>1 then
            Tools:TooltipAction(tip,"LeftButton",Text("blessing_choose_member"))
            local r, g, b = G:GetColor("color.tooltip.secondary")
            tip:AddLine(" ");tip:AddLine(Text("blessing_members_hint"),r,g,b,true)
        elseif #row.members==1 then TooltipTarget(tip, row.members[1].name, row)
        else local r,g,b=G:GetColor("color.text.secondary");tip:AddLine(Text("no_members"),r,g,b,true) end
        tip:Show();return
    end
    if state.manage then
        Tools:TooltipAction(tip,"LeftButton",Text("blessing_panel"))
        Tools:TooltipAction(tip,"LeftButton",Text("blessing_move_bar"),nil,Combat() and Text("blessing_move_locked") or nil,{"SHIFT"})
        Tools:TooltipSettings(tip,button);tip:Show();return
    end
    if B.entry and B.entry.enabled and button:GetAttribute("type1")=="spell" and (not state.member or state.member.targetName) then
        local castSpell=Safe.SafeNumber(button:GetAttribute("spell1"))
        if castSpell and castSpell>0 then Tools:TooltipSpellEffect(tip,castSpell) end
    end
    local reason=(not spell or spell==0) and Text("not_assigned") or nil
    if row and #row.members==0 then reason=Text("no_members")
    elseif row and row.allDead then reason=Text("dead_short") end
    local count=B:Reagents()
    if count==0 then reason=Text("missing") end
    local tone
    if count==nil then reason,tone=Text("state_unknown"),"secondary" end
    if not reason and spell and spell>0 then reason,tone=Tools:SpellUseReason(spell) end
    Tools:TooltipAction(tip,"LeftButton",spell and spell>0 and Name(spell) or Text("cast_current"),spell and spell>0 and Icon(spell),reason,nil,tone)
    local primary=state.toolbar or state.main
    if primary then Tools:TooltipAction(tip,"RightButton",Text("blessing_panel")) end
    local target=button:GetAttribute("blessing-target-name")
    if target or primary then tip:AddLine(" ") end
    if target then TooltipTarget(tip, target, row or B:CurrentRow()) end
    if primary then
        local r, g, b = G:GetColor("color.tooltip.secondary")
        tip:AddLine(Combat() and Text("blessing_combat") or Text("blessing_ooc"),r,g,b,true)
        Tools:TooltipSettings(tip,button)
    end
    tip:Show()
end
function B:ShowTooltip(button) return Tooltip(button) end
local function Leave() B.tooltipButton=nil;if GameTooltip then GameTooltip:Hide() end end
function B:Reagents() return YAB.UtilityTools.counts and YAB.UtilityTools.counts[21177] end
function B:CurrentRow()
    local class=self.entry and self.entry.button:GetAttribute("team-class")
    return class and self.rows[class]
end
function B:CurrentSpell() local row=self:CurrentRow(); return row and row.control:GetAttribute("blessing") end
function B:Save(row, value)
    local base=self.spells[value] and self.spells[value].base
    local config=Config(); config.teamBlessings=config.teamBlessings or {}
    local previous=config.teamBlessings[row.class]
    if previous==base then return end
    local visibilityChanged=(self.byBase[previous]~=nil)~=(base~=nil)
    config.teamBlessings[row.class]=base
    Tools:Invalidate()
    if YAB.ConfigSets then YAB.ConfigSets:SaveActiveSetting(self.entry.id,"teamBlessings",config.teamBlessings,"team-blessing",self) end
    row.dirty=true
    if self.entry.standalone and visibilityChanged then YAB.ClassBars.configDirty.paladinBlessings=true;YAB.ClassBars.pending=Combat() or YAB.ClassBars.pending end
    Queue()
end
function B:Target(row)
    local preferred=row.cast:GetAttribute("blessing-target-name")
    local living,prepared
    for _,member in ipairs(row.members) do
        if member.targetName then
            if member.name==preferred or not prepared then prepared=member end
            if not (Unit.IsDead and Unit.IsDead(member.unit)) then
                if member.name==preferred or not preferred then return member end
                living=living or member
            end
        end
    end
    -- Keep an enrolled recipient even when everybody is dead at preparation.
    -- The restricted click will only cast after a named member is alive.
    return living or prepared
end
function B:SelectRow(row)
    if Combat() then return end
    local button, cast=self.entry.button,row and row.cast
    local spell=cast and cast:GetAttribute("spell1")
    local target=cast and cast:GetAttribute("unit1")
    button:SetAttribute("team-class",row and row.class)
    button:SetAttribute("blessing-target-index",cast and cast:GetAttribute("blessing-target-index"))
    button:SetAttribute("blessing-target-name",cast and cast:GetAttribute("blessing-target-name"))
    button:SetAttribute("type1",spell and target and "spell" or "none")
    button:SetAttribute("spell1",spell);button:SetAttribute("unit1",target);button:SetAttribute("macrotext1",nil)
    button:SetAttribute("*type-Keybind",spell and target and "spell" or "none")
    button:SetAttribute("*spell-Keybind",spell);button:SetAttribute("*unit-Keybind",target);button:SetAttribute("*macrotext-Keybind",nil)
end
function B:PrepareTarget(button)
    if Combat() or not self.entry or not self.entry.enabled or not Unit.GetAssistTargetState or not Spell.IsInRange then return end
    local state=self.states[button]
    local row=state and (state.main and self:CurrentRow() or state.row)
    if not row or not (state.main or button==row.cast or button==row.barCast) then return end
    local spell=row.control:GetAttribute("blessing")
    if not spell or spell==0 then return end
    local preferred=button:GetAttribute("blessing-target-name")
    local chosen,chosenMember,chosenUnit
    for pass=1,2 do
        for i,member in ipairs(row.members) do
            if Combat() then return end
            if (pass==1 and member.name==preferred) or (pass==2 and member.name~=preferred) then
                local candidate=row.memberButtons[i]
                local unit=candidate and candidate.blessingTarget and Safe.SafeString(candidate.blessingTarget:GetAttribute("unit"))
                if unit and Unit.GetAssistTargetState(unit)==true and not Combat() and Safe.SafeBoolean(Spell.IsInRange(spell,unit))==true then
                    chosen,chosenMember,chosenUnit=candidate,member,unit;break
                end
            end
        end
        if chosen then break end
    end
    -- Unknown range never means out of range. Retain the prepared native action
    -- if no candidate is confirmed, or combat starts while reads are in flight.
    if not chosen or Combat() then return end
    local index=chosen:GetAttribute("blessing-target-index")
    local f=YAB.SecureFactory
    f:SetSecureAttribute(row.cast,"blessing-target-index",index)
    f:SetSecureAttribute(row.cast,"blessing-target-name",chosenMember.name)
    f:SetSecureAttribute(row.cast,"type1","spell")
    f:SetSecureAttribute(row.cast,"spell1",spell)
    f:SetSecureAttribute(row.cast,"unit1",chosenUnit)
    if row.barCast then self:SyncToolbar(row) end
    if state.main and (button:GetAttribute("blessing-target-index")~=index or button:GetAttribute("unit1")~=chosenUnit or button:GetAttribute("spell1")~=spell) then self:SelectRow(row) end
end
function B:CreateRow(entry, class)
    local f, panel=YAB.SecureFactory,entry.panel
    local row={class=class,name=ClassName(class),members={},memberButtons={},choiceButtons={},dirty=true}
    row.control=f:CreateBlessingRow(panel); row.control:SetSize(L.width-L.padding*2,L.rowHeight); row.control:SetAttribute("class",class)
    row.choices=f:CreateMageScrollPanel(row.control); row.choices:SetSize(L.selectWidth,144); row.choices:SetPoint("TOPLEFT",row.control,"TOPLEFT",L.selectX,-34)
    row.memberPanel=f:CreateMageScrollPanel(row.control); row.memberPanel:SetWidth(L.width-L.padding*2-28); row.memberPanel:SetPoint("TOPLEFT",row.control,"TOPLEFT",28,-L.rowHeight)
    row.control:SetFrameRef("choices",row.choices); row.control:SetFrameRef("members-panel",row.memberPanel)
    Backdrop(row.choices)
    row.toggle=f:CreateBlessingControl(row.control,entry.button,row.control,"members"); row.toggle:SetSize(114,34); row.toggle:SetPoint("TOPLEFT")
    Portrait(row.toggle,class,0,-7,21)
    row.nameLabel=Font(row.toggle,row.name,28,-10); row.nameLabel:SetWidth(86);row.nameLabel.gui2ColorKey=nil
    local color=Unit.GetClassColor(class); if color then row.nameLabel:SetTextColor(color.r,color.g,color.b,1) end
    self.states[row.toggle]={row=row,membersToggle=true};row.toggle:SetScript("OnEnter",Tooltip);row.toggle:SetScript("OnLeave",Leave)
    row.select=f:CreateBlessingControl(row.control,entry.button,row.control,"select"); row.select:SetSize(L.selectWidth,34); row.select:SetPoint("TOPLEFT",L.selectX,0)
    G:SkinDropdownButton(row.select);row.selectionText=row.select.text;Tools:StyleText(row.selectionText)
    row.selectionText:ClearAllPoints();row.selectionText:SetPoint("LEFT",36,0);row.selectionText:SetPoint("RIGHT",-24,0)
    row.selectionIcon=G:CreateIcon(row.select,{icon=Icon(25898),size=22,crop=true});row.selectionIcon:SetPoint("LEFT",7,0)
    local refresh=row.select.RefreshTheme
    row.select.RefreshTheme=function(frame) refresh(frame);G:SetTextColorKey(frame.text,row.selectionTone or "color.text.secondary") end
    row.status=Font(row.control,"",L.statusX,-10,"color.text.secondary"); row.status:SetWidth(52)
    row.cast=f:CreateBlessingControl(row.control,entry.button,row.control,"cast"); row.cast:SetPoint("TOPLEFT",L.castX,0)
    row.control:SetFrameRef("cast",row.cast)
    row.control.SelectionChanged=function(_,value) B:Save(row,value) end
    self.states[row.cast]={row=row}; row.cast:SetScript("OnEnter",Tooltip); row.cast:SetScript("OnLeave",Leave)
    row.cast:HookScript("PreClick",PrepareClick)
    self.rows[class]=row
    return row
end
-- The management window and the action bar use the public layout drag lifecycle.
function B:PreparePanelLayout(entry)
    if Combat() then return end
    local layout=YUI.Layout
    if not (layout and layout.RegisterFrame) then return end
    local panel=entry.panel
    if not self.panelLayoutRegistered then
        layout:RegisterFrame(PANEL_LAYOUT_ID,{
            frame=panel,title=Text("teamBlessing"),category="product",movable=true,snap=false,combatProtected=true,
            defaultPlacement=function()
                return {point="BOTTOMLEFT",relativeTo=panel:GetAttribute("blessing-panel-opener") or B.manager:GetName(),relativePoint="TOPLEFT",x=0,y=12}
            end,
            isEnabled=function() return B.entry~=nil and B.entry.enabled and panel:IsShown() end,
            onPlacementCommitted=function()
                if not Combat() then panel:SetAttribute("blessing-panel-moved",true) end
            end,
        })
        self.panelLayoutRegistered=true
    end
    panel:SetAttribute("blessing-panel-moved",layout:HasPlacement(PANEL_LAYOUT_ID))
end
function B:BeginDrag(kind)
    if Combat() or self.dragKind or not self.entry or not self.entry.enabled
        or YAB.BarManager.bindPresentationActive or (YAB.KeybindMode and YAB.KeybindMode.active) then return false end
    local layout=YUI.Layout
    if not (layout and layout.BeginDirectDrag) then return false end
    if kind=="panel" then self:PreparePanelLayout(self.entry) end
    local id=kind=="panel" and PANEL_LAYOUT_ID or Tools:GetLayoutId("paladinBlessings")
    if not layout:BeginDirectDrag(id,{snap=kind~="panel"}) then return false end
    self.dragKind=kind
    if GameTooltip then GameTooltip:Hide() end
    return true
end
function B:StopDrag(cancel)
    if not self.dragKind then return end
    self.dragKind=nil
    if YUI.Layout and YUI.Layout.EndDirectDrag then YUI.Layout:EndDirectDrag(cancel) end
end
-- The hidden owner retains the former quick-blessing command. Visible management
-- and class controls have separate identities, actions, layout and enable switches.
function B:BuildStandalone(record,config)
    if Combat() then return end
    local f,utility=YAB.SecureFactory,YAB.UtilityTools
    utility:ReadBook();utility:ReadInventory("paladinTools")
    local entry=self.standaloneEntry
    if not entry then
        local button,panel=f:CreateClassTool(record.holder,"paladinTools","teamBlessing")
        entry={id="paladinBlessings",key="legacy",button=button,panel=panel,choices={},visual={},standalone=true,
            definition=YAB.ClassToolData.catalog.paladinTools.teamBlessing}
        self.standaloneEntry=entry
        local meta=f:GetButtonMeta(button);meta.barId=record.id;meta.buttonKey="paladinTools.teamBlessing"
    end
    entry.button:SetParent(record.holder);entry.panel:SetParent(record.holder)
    record.buttons,record.classButtons={},{}
    self:Build(entry,record,config)
    if not self.manager then
        self.manager=f:CreateBlessingControl(record.holder,entry.button,entry.button,"manage")
        local meta=f:GetButtonMeta(self.manager);meta.barId=record.id;meta.classToolChoice=nil
        self.managerEntry={definition={},visual={}}
        self.states[self.manager]={manage=true}
        self.manager:SetScript("OnEnter",Tooltip);self.manager:SetScript("OnLeave",Leave)
    end
    entry.panel:SetFrameRef("class-tool-opener",self.manager)
    self.manager:SetParent(record.holder)
    self.manager.barEnabled=Tools:IsButtonEnabled(record.id,"manage",config)
    self.manager:SetAttribute("blessing-bar-enabled",self.manager.barEnabled)
    if self.manager.barEnabled then
        Tools:PrepareButton(self.manager,record.id,"manage");self.manager:Show()
    else Tools:ReleaseButton(self.manager);self.manager:Hide() end
    if not self.manager.blessingMoveHooked then
        self.manager:SetScript("OnDragStart",function() if IsShiftKeyDown() then B:BeginDrag("bar") end end)
        self.manager:SetScript("OnDragStop",function() B:StopDrag(false) end)
        self.manager:HookScript("OnHide",function() B:StopDrag(true) end)
        self.manager.blessingMoveHooked=true
    end
    for _,class in ipairs(Tools.classOrder) do
        local row=self.rows[class]
        if not row.barCast then
            row.barCast=f:CreateBlessingControl(record.holder,entry.button,row.control,"toolbar",class)
            local meta=f:GetButtonMeta(row.barCast);meta.barId=record.id;meta.classToolChoice=nil
            row.barCast:SetAttribute("blessing-toolbar",true)
            row.control:SetFrameRef("toolbar",row.barCast)
            row.barVisual={};row.barEntry={definition={},visual=row.barVisual}
            self.states[row.barCast]={row=row,toolbar=true}
            row.barCast:SetScript("OnEnter",Tooltip);row.barCast:SetScript("OnLeave",Leave)
            row.barCast:HookScript("PreClick",PrepareClick)
        end
        row.barCast:SetParent(record.holder)
        row.barCast:SetAttribute("blessing-bar-enabled",Tools:IsButtonEnabled(record.id,class,config) and entry.enabled)
        self:SyncToolbar(row)
        row.barEnabled=Tools:IsButtonEnabled(record.id,class,config) and row.control:GetAttribute("blessing")>0
        if row.barEnabled then Tools:PrepareButton(row.barCast,record.id,class);row.barCast:Show()
        else Tools:ReleaseButton(row.barCast);row.barCast:Hide() end
    end
    for _,key in ipairs(Tools:GetButtonOrder(record.id,config)) do
        local button=key=="manage" and self.manager or self.rows[key] and self.rows[key].barCast
        if button and (key=="manage" and self.manager.barEnabled or self.rows[key] and self.rows[key].barEnabled) then record.buttons[#record.buttons+1]=button end
    end
    record.classToolPrepared=true
    if YAB.BarManager.SyncClassBarEvents then YAB.BarManager:SyncClassBarEvents() end
end
function B:SyncToolbar(row)
    if Combat() or not row.barCast then return end
    local button,cast=row.barCast,row.cast
    for _,field in ipairs({"type","spell","unit","macrotext"}) do
        local value=cast:GetAttribute(field.."1")
        button:SetAttribute(field.."1",value);button:SetAttribute("*"..field.."-Keybind",value)
    end
    button:SetAttribute("blessing-target-index",cast:GetAttribute("blessing-target-index"))
    button:SetAttribute("blessing-target-name",cast:GetAttribute("blessing-target-name"))
    -- Native click snippets resolve the prepared target from the owner by index.
end
function B:LayoutToolbar(record)
    if Combat() then YAB.ClassBars.pending,YAB.ClassBars.configDirty.paladinBlessings=true,true;return end
    local utility,snapshot=YAB.UtilityTools,record.configSnapshot
    utility:PrepareVisual(self.manager,self.managerEntry,snapshot)
    local entry=self.standaloneEntry
    if not entry.panel:GetAttribute("blessing-panel-moved") then
        entry.panel:ClearAllPoints();entry.panel:SetPoint("BOTTOMLEFT",self.manager,"TOPLEFT",0,12)
    end
    for _,class in ipairs(Tools.classOrder) do
        local row=self.rows[class]
        local button,view=row.barCast,row.barEntry
        utility:PrepareVisual(button,view,snapshot)
        local visual=YAB.Visuals.buttons[button]
        if visual and visual.cooldown and view.timerHook~=visual.cooldown then
            visual.cooldown:HookScript("OnCooldownDone",function()
                if B.entry and B.entry.enabled and row.expiration then row.dirty=true;Queue() end
            end)
            view.timerHook=visual.cooldown
        end
        if not view.statusLabel then view.statusLabel=Font(visual and visual.classTextHost or button,"",0,0) end
        local textHost=visual and visual.classTextHost or button
        if view.statusLabel:GetParent()~=textHost then view.statusLabel:SetParent(textHost) end
        view.statusLabel:ClearAllPoints();view.statusLabel:SetPoint("CENTER",button,"CENTER",0,0)
        if not view.estimateLabel then view.estimateLabel=Font(textHost,"",0,0,"color.text.secondary","font.size.sm") end
        if view.estimateLabel:GetParent()~=textHost then view.estimateLabel:SetParent(textHost) end
        view.estimateLabel:ClearAllPoints();view.estimateLabel:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",2,1)
        Tools:AnchorTeamClassCaption(view.label,button,class,Config())
        Caption(view.label,Text("blessing_short_"..class))
    end
end
function B:Build(entry, record, config)
    if Combat() then return end
    self.entry,self.record=entry,record
    local f, utility=YAB.SecureFactory,YAB.UtilityTools
    self.spells,self.byBase,self.learned={}, {}, {}
    self.normalBlessings={}
    for _,family in ipairs(YAB.ClassToolData.catalog.paladinTools.blessing.families) do
        for _,spell in ipairs(family) do self.normalBlessings[spell]=true end
    end
    for _, family in ipairs(entry.definition.families) do
        local spell=utility:Highest(family)
        if spell then local info={spell=spell,base=family[1]}; self.spells[spell]=info;self.byBase[family[1]]=info;self.learned[#self.learned+1]=info end
    end
    local members, raiding,complete
    if Unit.ReadGroupMembers then members,complete=Unit.ReadGroupMembers()
    elseif Unit.ReadRaidMembers then members,raiding,complete=Unit.ReadRaidMembers() end
    self.rosterUnknown=members==nil or complete==false
    self.raiding=raiding==true; self.unitRows={};self.rosterStale=false
    local player=Unit.GetDisplayNameInfo and Unit.GetDisplayNameInfo("player")
    local playerName=player and Safe.SafeString(player.displayName)
    local grouped={}; for _, class in ipairs(Tools.classOrder) do grouped[class]={} end
    local hasPlayer=false
    for _, member in ipairs(members or {}) do
        member.targetName = Unit.GetGroupRosterName and Unit.GetGroupRosterName(member.unit)
        if not member.targetName then self.rosterUnknown = true end
        local class=member.class or Unit.GetClassToken and Unit.GetClassToken(member.unit)
        if grouped[class] then grouped[class][#grouped[class]+1]=member end
        if playerName and member.name==playerName then hasPlayer=true end
    end
    if playerName and not hasPlayer and #(members or {})<40 then
        local class=Unit.GetClassToken and Unit.GetClassToken("player")
        local targetName=Unit.GetGroupRosterName and Unit.GetGroupRosterName("player")
        if not targetName then self.rosterUnknown=true end
        if grouped[class] then grouped[class][#grouped[class]+1]={unit="player",name=playerName,class=class,targetName=targetName} end
    end
    local enabled=config.enabled~=false and Tools:IsButtonEnabled(entry.id,entry.key,config) and #self.learned>0
    entry.enabled=enabled and not record.classBarEditing and not YAB.BarManager.bindPresentationActive
    if not entry.enabled then entry.panel:Hide() end
    f:SetSecureAttribute(entry.button,"class-tool-interactive",entry.enabled)
    f:SetSecureAttribute(entry.button,"class-tool-choices",entry.enabled and 9 or 0)
    entry.button.TeamClassSelected=function() Queue() end
    entry.button.TeamBlessingSubmitted=function(_,index,spell) self:NoteSubmission(index,spell) end
    entry.button.TeamBlessingSubmissionEnded=function() self.submitted=nil end
    self.states[entry.button]={main=true}; entry.button:SetScript("OnEnter",Tooltip); entry.button:SetScript("OnLeave",Leave)
    if not entry.autoTargetHooked then entry.button:HookScript("PreClick",PrepareClick);entry.autoTargetHooked=true end
    if not self.chrome then
        self.chrome=Backdrop(entry.panel)
        Font(entry.panel,Text("teamBlessing"),L.padding,-11,"color.text.heading","font.size.lg")
        for i, text in ipairs({Text("blessing_class"),Text("blessing_assigned"),Text("blessing_status"),Text("blessing_cast")}) do Font(entry.panel,text,({L.padding,L.padding+L.selectX,L.padding+L.statusX,L.padding+L.castX-3})[i],-35,"color.text.secondary") end
        self.reagentHost=G:CreateFrame(entry.panel,{width=200,height=22,mouse=true});self.reagentHost:SetPoint("BOTTOMLEFT",entry.panel,"BOTTOMLEFT",L.padding,23)
        self.reagentIcon=G:CreateIcon(self.reagentHost,{icon=Safe.SafeNumber(Item.GetIcon(21177)),size=20,crop=true});self.reagentIcon:SetPoint("LEFT")
        self.footer=Font(self.reagentHost,Text("king_symbols"),0,0);self.footer:ClearAllPoints();self.footer:SetPoint("LEFT",self.reagentIcon,"RIGHT",6,0)
        self.reagentCount=Font(self.reagentHost,"",0,0,"color.text.heading");self.reagentCount:ClearAllPoints();self.reagentCount:SetPoint("LEFT",self.footer,"RIGHT",6,0)
        f:SetButtonMeta(self.reagentHost, {barId=entry.id})
        self.reagentHost:SetScript("OnEnter", function(host)
            if not f:ShouldShowTooltip(host) then return end
            GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(21177)
            GameTooltip:Show()
        end)
        self.reagentHost:SetScript("OnLeave",Leave)
        self.hint=Font(entry.panel,Text("blessing_panel_hint"),0,0,"color.text.secondary");self.hint:ClearAllPoints();self.hint:SetPoint("BOTTOMLEFT",entry.panel,"BOTTOMLEFT",L.padding,7)
        entry.panel:EnableMouse(true)
        entry.panel:SetAttribute("class-tool-persistent",true)
        self.header=G:CreateFrame(entry.panel,{height=30,mouse=true})
        self.header:SetPoint("TOPLEFT",entry.panel,"TOPLEFT",0,0);self.header:SetPoint("TOPRIGHT",entry.panel,"TOPRIGHT",-34,0)
        self.header:RegisterForDrag("LeftButton")
        self.header:SetScript("OnDragStart",function() B:BeginDrag("panel") end)
        self.header:SetScript("OnDragStop",function() B:StopDrag(false) end)
        entry.panel:HookScript("OnHide",function() B:CancelPanelTimer();B:StopDrag(true) end)
        local close=entry.panel.classToolClose;close:SetSize(16,16);close:SetPoint("TOPRIGHT",entry.panel,"TOPRIGHT",-10,-10)
        local visual=G:CreateCloseButton(close)
        visual:SetAllPoints(close);visual:EnableMouse(false)
        close.blessingCloseVisual=visual
        for event,state in pairs({OnEnter="hover",OnLeave="normal",OnMouseDown="pressed",OnMouseUp="hover",OnHide="normal"}) do
            close:HookScript(event,function() visual:SetState(state) end)
        end
        entry.panel:HookScript("OnShow",function() B.dirty=true;Queue() end)
    end
    self.reagentIcon:SetTexture(Safe.SafeNumber(Item.GetIcon(21177)))
    self.ordered={}
    local previousCoverage=self.memberCoverage or {}
    -- An incomplete roster cannot evict existing observations or add new keys.
    self.memberCoverage=self.rosterUnknown and previousCoverage or {}
    self.submitted,self.pendingCast=nil,nil
    self.memberPool=self.memberPool or {}
    self.memberCursor=0
    for _,button in ipairs(self.memberPool) do
        button:SetAttribute("type1","none");button:SetAttribute("spell1",nil);button:SetAttribute("unit1",nil);button:Hide()
    end
    for rowIndex, class in ipairs(Tools.classOrder) do
        local row=self.rows[class] or self:CreateRow(entry,class)
        self.ordered[#self.ordered+1]=row.control
        local expanded=row.memberPanel:IsShown()
        row.members,row.dirty=grouped[class],true
        row.memberButtons={}
        local saved=config.teamBlessings and config.teamBlessings[class]
        local selected=saved and self.byBase[saved]; local spell=selected and selected.spell or 0
        row.control:SetAttribute("blessing",spell);row.control:SetAttribute("members",#row.members)
        local columns=#row.members>24 and 4 or 3
        local memberWidth=math.floor((row.memberPanel:GetWidth()-(columns-1)*4)/columns)
        row.control:SetAttribute("member-height",math.ceil(#row.members/columns)*L.memberStep)
        row.choices:SetFrameLevel(entry.panel:GetFrameLevel()+30)
        row.choices:SetHeight((#self.learned+1)*34+8);row.choices:ClearAllPoints()
        if rowIndex>=7 then row.choices:SetPoint("BOTTOMLEFT",row.control,"TOPLEFT",L.selectX,2)
        else row.choices:SetPoint("TOPLEFT",row.control,"TOPLEFT",L.selectX,-34) end
        row.memberPanel:SetHeight(math.max(1,math.ceil(#row.members/columns)*L.memberStep));row.memberPanel:Hide();row.choices:Hide()
        local targetMember=entry.enabled and self:Target(row) or nil
        local target=targetMember and targetMember.unit
        row.control:SetAttribute("target",target)
        row.cast:SetAttribute("blessing-target-index",nil)
        row.cast:SetAttribute("blessing-target-name",targetMember and targetMember.name)
        row.cast:SetAttribute("type1",spell>0 and target and "spell" or "none")
        row.cast:SetAttribute("spell1",spell>0 and target and spell or nil)
        row.cast:SetAttribute("unit1",target);row.cast:SetAttribute("macrotext1",nil)
        row.cast:SetShown(spell>0)
        for i,member in ipairs(row.members) do
                local key=member.targetName
                member.coverage=key and previousCoverage[key] or {}
                if key and not self.rosterUnknown then self.memberCoverage[key]=member.coverage end
                self.memberCursor=self.memberCursor+1
                local button=self.memberPool[self.memberCursor]
                if not button then
                    button=f:CreateBlessingControl(row.memberPanel,entry.button,row.control,"cast");self.memberPool[self.memberCursor]=button
                    button:SetAttribute("blessing-member",true)
                    button:SetScript("OnEnter",Tooltip);button:SetScript("OnLeave",Leave)
                    local visual=ButtonVisual(button,{width=memberWidth,height=28,contentAlign="left",textLeftPadding=8,textRightPadding=8,justifyH="LEFT"})
                    button.memberText=visual.text
                end
                 if not button.blessingHeader then button.blessingHeader,button.blessingTarget=f:CreateBlessingTarget(record.holder) end
                 if entry.enabled and member.targetName then f:PrepareBlessingTarget(button.blessingHeader,member.targetName,member.unit)
                 else f:ReleaseBlessingTarget(button.blessingHeader) end
                 button:SetFrameRef("blessing-target",button.blessingTarget)
                 button:SetAttribute("blessing-target-index",self.memberCursor)
                 button:SetAttribute("blessing-target-name",member.name)
                 entry.button:SetFrameRef("blessing-target"..self.memberCursor,button.blessingTarget)
                 if member==targetMember then
                     row.cast:SetFrameRef("blessing-target",button.blessingTarget)
                     row.cast:SetAttribute("blessing-target-index",self.memberCursor)
                 end
                button:SetParent(row.memberPanel);button:SetFrameRef("row",row.control);row.memberButtons[i]=button
                button:SetSize(memberWidth,28);button:ClearAllPoints();button:SetPoint("TOPLEFT",((i-1)%columns)*(memberWidth+4),-math.floor((i-1)/columns)*L.memberStep)
                ButtonCaption(button,member.name);button.memberText:SetWidth(memberWidth-16)
                local color=Unit.GetClassColor(class);button.blessingClassColor=color
                if color then button.blessingVisual:SetTextColor(color.r,color.g,color.b,1) end
                -- The native header resolves this fixed member to a current unit token.
                button:SetAttribute("type1",entry.enabled and spell>0 and "spell" or "none")
                button:SetAttribute("spell1",spell>0 and spell or nil);button:SetAttribute("unit1",member.unit)
                self.states[button]={row=row,member=member}
                row.control:SetFrameRef("member"..i,button);button:Show();self.unitRows[member.unit]=row
                if member.name==playerName then self.unitRows.player=row end
        end
        for i=1,math.max(#self.learned+1,#row.choiceButtons) do
            local info=i>1 and self.learned[i-1] or nil
            local button=row.choiceButtons[i]
            if i<=#self.learned+1 then
                local value=info and info.spell or 0
                if not button then
                    button=f:CreateBlessingControl(row.choices,entry.button,row.control,"choice");row.choiceButtons[i]=button
                    local visual=ButtonVisual(button,{width=L.selectWidth-8,height=30,icon=info and Icon(value),iconSize=20,preserveIconColor=true,
                        contentAlign="left",textLeftPadding=33,textRightPadding=8,justifyH="LEFT"})
                    button.caption=visual.text
                end
                button:SetAttribute("value",value);button:SetSize(L.selectWidth-8,30);button:ClearAllPoints();button:SetPoint("TOPLEFT",4,-4-(i-1)*34)
                ButtonCaption(button,info and Name(value) or Text("not_assigned"))
                if button.blessingVisual.icon then button.blessingVisual.icon:SetTexture(Icon(value)) end
                button:Show()
            elseif button then button:Hide() end
        end
        if expanded and #row.members>0 then row.memberPanel:Show() end
        row.control:Show()
        record.classButtons[#record.classButtons+1]=row.control
    end
    for i=self.memberCursor+1,#self.memberPool do f:ReleaseBlessingTarget(self.memberPool[i].blessingHeader) end
    f:PrepareBlessingLayout(entry.button,self.ordered,L)
    local selected=self:CurrentRow()
    if not selected or (selected.control:GetAttribute("blessing") or 0)==0 or #selected.members==0 then selected=nil end
    if not selected then for _, class in ipairs(Tools.classOrder) do local row=self.rows[class];if row.control:GetAttribute("blessing")>0 and #row.members>0 then selected=row;break end end end
    self:SelectRow(selected)
    Tools:PrepareButton(entry.button,entry.id,entry.key)
    if RegisterStateDriver then RegisterStateDriver(entry.button,"visibility",enabled and not entry.standalone and "show" or "hide") end
    if enabled and not entry.standalone then record.buttons[#record.buttons+1]=entry.button end
    if enabled then record.classButtons[#record.classButtons+1]=entry.panel else entry.button:Hide() end
    self.groupAuraActive=false
    if entry.enabled then for unit in pairs(self.unitRows) do if unit~="player" then self.groupAuraActive=true;break end end end
    self.dirty=true
end
function B:OnUnitAura(unit)
    unit=Safe.SafeString(unit);local row=unit and self.unitRows and self.unitRows[unit]
    if self.entry and self.entry.enabled and row then row.dirty=true;Queue() end
end

function B:NoteSubmission(index,spell)
    self.submitted=nil
    if not self.entry or not self.entry.enabled or self.rosterStale or self.rosterUnknown then return end
    local button=self.memberPool[Safe.SafeNumber(index)]
    local state=button and self.states[button]
    local member=state and state.member
    if member and member.targetName then
        self.submitted={member=member,row=state.row,spell=Safe.SafeNumber(spell)}
    end
end

function B:CastRecipient(target)
    if not target or target=="" then return end
    local found
    for index=1,self.memberCursor do
        local state=self.states[self.memberPool[index]]
        local member=state and state.member
        if member and member.targetName then
            if target==member.targetName or target==member.name or target==member.targetName:match("^([^-]+)") then
                if found then return end
                found=state
            end
        end
    end
    return found
end

function B:OnSpellcast(event,unit,...)
    if Safe.SafeString(unit)~="player" or not self.entry or not self.entry.enabled
        or self.rosterStale or self.rosterUnknown then return end
    if event=="UNIT_SPELLCAST_SENT" then
        local target,guid,spell=...
        target,guid,spell=Safe.SafeString(target),Safe.SafeString(guid),Safe.SafeNumber(spell)
        local submitted=self.submitted
        self.submitted,self.pendingCast=nil,nil
        if not guid or not spell or not (self.spells[spell] or self.normalBlessings[spell]) then return end
        local recipient=self:CastRecipient(target)
        -- SENT is synchronous with the hardware cast request. The secure post
        -- handler clears unused hints even when a click sends no request.
        if (not target or target=="") and submitted and submitted.spell==spell then recipient=submitted end
        if recipient then self.pendingCast={guid=guid,spell=spell,member=recipient.member,row=recipient.row} end
        return
    end
    local guid,spell=...
    local cast=self.pendingCast
    if not cast or Safe.SafeString(guid)~=cast.guid then return end
    self.pendingCast=nil
    if event~="UNIT_SPELLCAST_SUCCEEDED" or Safe.SafeNumber(spell)~=cast.spell then return end
    local coverage=cast.member.coverage
    if self.spells[cast.spell] then
        local now=PanelTime()
        if not now then return end
        -- Other class members may be out of range. Only the direct recipient
        -- can get an estimated timer from the cast event itself.
        coverage.spell,coverage.expiration=cast.spell,now+GREATER_BLESSING_DURATION
        coverage.duration,coverage.own=GREATER_BLESSING_DURATION,true
    elseif coverage.own then
        coverage.expiration=nil
    else return end
    cast.row.dirty=true
    Queue()
end
function B:Layout(entry,record)
    if Combat() then return end
    local utility,snapshot=YAB.UtilityTools,record.configSnapshot
    utility:PrepareVisual(entry.button,entry,snapshot)
    local y=L.top
    for _,class in ipairs(Tools.classOrder) do
        local row=self.rows[class]
        row.control:ClearAllPoints();row.control:SetPoint("TOPLEFT",entry.panel,"TOPLEFT",L.padding,-y)
        y=y+L.rowHeight+(row.memberPanel:IsShown() and row.control:GetAttribute("member-height") or 0)
        row.cast:SetSize(L.castSize,L.castSize)
        row.snapshot=YAB:CopyValue(snapshot);row.snapshot.size,row.snapshot.buttonHeight,row.snapshot.showHotkeys,row.snapshot.showCounts=L.castSize,L.castSize,false,false
        YAB.Skins:ApplyButton(row.cast,YAB.Skins:Normalize("default"),{size=L.castSize,width=L.castSize,height=L.castSize,zoom=snapshot.iconZoom,snapshot=row.snapshot})
        YAB.BarManager.buttonConfigSnapshots[row.cast]=row.snapshot
    end
    entry.panel:SetSize(L.width,y+L.footer)
    self:LayoutToolbar(record)
    self:PreparePanelLayout(entry)
end
function B:ReadStatus(row,now)
    if not row.dirty and not self.dirty and not (now and row.expiration and row.expiration<=now) then return end
    row.dirty=nil;self.reads=self.reads+1
    local spell=row.control:GetAttribute("blessing")
    row.expiration,row.duration,row.missing,row.unknown,row.allDead=nil,nil,false,false,false
    if self.rosterStale or self.rosterUnknown then row.unknown=true;return end
    if not spell or spell==0 or #row.members==0 then return end
    local name=Name(spell)
    if not name then row.unknown=true;return end
    if row.readName~=name then row.readName,row.readFilter=name,{[name]="blessing"} end
    local living=0
    for _, member in ipairs(row.members) do
        local coverage=member.coverage
        if Unit.IsDead and Unit.IsDead(member.unit) then
            coverage.expiration=nil
        else
            living=living+1
            local result,unavailable=Unit.ReadHelpfulTimersByName(member.unit,row.readFilter)
            local aura=result and result.blessing
            local expiration=aura and Safe.SafeNumber(aura.expirationTime)
            local duration
            if not result or unavailable and unavailable.blessing or aura and not expiration then
                row.unknown=true
                if coverage.spell==spell and coverage.expiration and now and coverage.expiration>now then
                    expiration,duration=coverage.expiration,coverage.duration
                else expiration=nil end
            elseif not aura or now and expiration<=now then
                row.missing=true
                if coverage.spell==spell then coverage.expiration=nil end
                expiration=nil
            else
                duration=Safe.SafeNumber(aura.duration) or GREATER_BLESSING_DURATION
                coverage.spell,coverage.expiration,coverage.duration=spell,expiration,duration
                coverage.own=Safe.SafeString(aura.sourceUnit)=="player"
            end
            if expiration and (not row.expiration or expiration<row.expiration) then
                row.expiration,row.duration=expiration,duration
            end
        end
    end
    row.allDead=living==0
end
local function CaptionTime(row, remaining)
    local prefix=row.unknown and "~" or ""
    if remaining>=3600 then
        Caption(row.status,prefix.."1h")
        return remaining-3600+PANEL_TIMER_MIN_DELAY
    end
    local step=remaining>60 and 60 or 1
    local amount=math.ceil(remaining/step)
    Caption(row.status,prefix..amount..(step==60 and "m" or "s"))
    return remaining-(amount-1)*step
end
function B:CancelPanelTimer()
    local timer=self.panelTimer
    self.panelTimer,self.panelDeadline=nil,nil
    if timer then timer:Cancel() end
end
function B:SchedulePanelTimer(now, delay)
    local deadline=delay and now+math.max(PANEL_TIMER_MIN_DELAY,delay)
    if self.panelTimer and deadline and math.abs(deadline-self.panelDeadline)<0.001 then return end
    self:CancelPanelTimer()
    if not deadline then return end
    local timer
    timer=C_Timer.NewTimer(deadline-now,function()
        if self.panelTimer~=timer then return end
        self.panelTimer,self.panelDeadline=nil,nil
        self:UpdatePanelTimers()
    end)
    self.panelTimer,self.panelDeadline=timer,deadline
end
function B:UpdatePanelTimers()
    local entry=self.entry
    if not entry or not entry.enabled or not entry.panel:IsVisible() or self.dirty then return end
    local now=PanelTime()
    if not now then return end
    local nextDelay,expired
    for _,class in ipairs(Tools.classOrder) do
        local row=self.rows[class]
        if row.expiration and not row.missing and not row.dirty then
            local remaining=row.expiration-now
            if remaining>0 then
                local delay=CaptionTime(row,remaining)
                nextDelay=nextDelay and math.min(nextDelay,delay) or delay
            else
                row.dirty=true
                expired=true
            end
        end
    end
    self:SchedulePanelTimer(now,nextDelay)
    if expired then Queue() end
end
function B:Refresh(entry)
    if not self.entry or entry~=self.entry then return end
    local count=self:Reagents()
    local now=PanelTime()
    local panelOpen=entry.enabled and entry.panel:IsVisible()
    local showCooldownText=(self.record.configSnapshot.cooldownTextSize or 0)>0
    local nextDelay
    for _,class in ipairs(Tools.classOrder) do
        local row=self.rows[class];self:ReadStatus(row,now)
        local members=(self.rosterStale or self.rosterUnknown) and "?" or #row.members
        if row.countCaption~=members then Caption(row.nameLabel,string.format(Text("blessing_class_count"),row.name,tostring(members)));row.countCaption=members end
        local spell=row.control:GetAttribute("blessing") or 0
        local text=(self.rosterStale or self.rosterUnknown) and Text("unknown_short") or #row.members==0 and Text("no_members") or spell==0 and "—" or row.allDead and Text("dead_short") or row.missing and Text("buff_missing") or row.unknown and Text("unknown_short") or Text("buff_ready")
        local ready=row.expiration and not row.missing and not self.rosterStale and not self.rosterUnknown
        if ready and now then
            local delay=CaptionTime(row,row.expiration-now)
            if panelOpen then nextDelay=nextDelay and math.min(nextDelay,delay) or delay end
        else
            Caption(row.status,text)
        end
        local tone=row.missing and "color.state.warning" or ready and not row.unknown and "color.state.success" or "color.text.secondary"
        Tone(row.status,tone)
        Caption(row.selectionText,spell>0 and Name(spell) or Text("not_assigned"))
        row.selectionTone=spell>0 and "color.text.heading" or "color.text.secondary";Tone(row.selectionText,row.selectionTone)
        if row.selectionSpell~=spell then row.selectionIcon:SetTexture(spell>0 and Icon(spell) or nil);row.selectionIcon:SetAlpha(spell>0 and 1 or 0);row.selectionSpell=spell end
        for _,choice in ipairs(row.choiceButtons) do
            local selected=choice:GetAttribute("value")==spell
            if choice.blessingSelected~=selected then choice.blessingSelected=selected;choice.blessingVisual:SetSelected(selected) end
        end
        local state=row.visual or {};row.visual=state
        state.hasAction,state.texture,state.usable=spell>0,spell>0 and Icon(spell) or nil,spell>0 and #row.members>0 and not row.allDead and count~=0
        state.countText,state.hotkeyText,state.checked="","",false
        YAB.Visuals:UpdateButton(row.cast,state,"full")
        if row.barCast then
            local barState=row.barVisual
            barState.hasAction,barState.texture,barState.usable=state.hasAction,state.texture,state.usable
            barState.countText,barState.checked="",false
            local duration=ready and row.duration and row.duration>0 and row.duration or nil
            barState.cooldownStart=duration and row.expiration-duration or nil
            barState.cooldownDuration=duration
            barState.cooldownEnable,barState.cooldownIsStatus=duration~=nil,true
            YAB.Visuals:UpdateButton(row.barCast,barState,"full")
            Caption(row.barEntry.statusLabel,row.missing and Text("blessing_missing_short") or row.unknown and not duration and "?" or "")
            Tone(row.barEntry.statusLabel,row.missing and "color.state.warning" or "color.text.secondary")
            Caption(row.barEntry.estimateLabel,row.unknown and duration and showCooldownText and "~" or "")
        end
        local alpha=spell>0 and 1 or 0
        if row.castAlpha~=alpha then row.cast:SetAlpha(alpha);row.castAlpha=alpha end
        if not Combat() and not self.nextRow and spell>0 and #row.members>0 and row.missing then self.nextRow=row end
    end
    if not Combat() and self.nextRow then self:SelectRow(self.nextRow) end
    self.nextRow,self.dirty=nil,nil
    self:SchedulePanelTimer(now,nextDelay)
    local spell=self:CurrentSpell()
    local state=entry.visual
    state.hasAction,state.texture,state.usable=true,Icon(spell and spell>0 and spell or 25898),spell~=nil and spell>0 and count~=0
    state.countText,state.checked,state.missingBuff=count~=nil and tostring(count) or "—",false,false
    YAB.Visuals:UpdateButton(entry.button,state,"full")
    if entry.standalone and self.manager then
        local manage=self.managerEntry.visual
        manage.hasAction,manage.texture,manage.usable=true,Safe.SafeNumber(Item.GetIcon(21177)),true
        manage.countText=count~=nil and tostring(count) or "—"
        YAB.Visuals:UpdateButton(self.manager,manage,"full")
    end
    Caption(self.reagentCount,count~=nil and tostring(count) or "—")
    Tone(self.reagentCount,count==0 and "color.state.error" or count==nil and "color.text.secondary" or "color.text.heading")
    local hovered=self.tooltipButton
    if hovered and GameTooltip:IsOwned(hovered) and GameTooltip:IsShown() then Tooltip(hovered) end
end
function B:OnEvent(event,...)
    if YAB.ClassBars.mageCastEvents and YAB.ClassBars.mageCastEvents[event] then
        self:OnSpellcast(event,...)
        return
    end
    local restrictionsChanged=event=="ADDON_RESTRICTION_STATE_CHANGED"
    if event=="PLAYER_REGEN_DISABLED" then self:StopDrag(true) end
    if event=="GROUP_ROSTER_UPDATE" or event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" then
        self.pendingCast,self.submitted=nil,nil
        if event=="PLAYER_ENTERING_WORLD" then self.memberCoverage=nil end
        YAB.ClassBars.configDirty.paladinBlessings=true
        if Combat() then YAB.ClassBars.pending=true;self.rosterStale=true;self.dirty=true end
    end
    if event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_REGEN_ENABLED"
        or restrictionsChanged and self.entry and self.entry.enabled then self.dirty=true end
    if self.dirty then self:CancelPanelTimer() end
    if (self.rosterUnknown or self.rosterStale)
        and (event=="PLAYER_REGEN_ENABLED" or restrictionsChanged and not Combat()) then
        YAB.ClassBars.configDirty.paladinBlessings=true
    end
end
function B:Stop(entry)
    if Combat() then YAB.ClassBars.pending=true;return false end
    local hovered=self.tooltipButton
    if (hovered and GameTooltip:IsOwned(hovered)) or (self.reagentHost and GameTooltip:IsOwned(self.reagentHost)) then GameTooltip:Hide() end
    self.tooltipButton=nil
    self.pendingCast,self.submitted,self.memberCoverage=nil,nil,nil
    self:CancelPanelTimer()
    self:StopDrag(true)
    if self.panelLayoutRegistered and YUI.Layout and YUI.Layout.UnregisterFrame then
        YUI.Layout:UnregisterFrame(PANEL_LAYOUT_ID);self.panelLayoutRegistered=nil
    end
    entry.panel:Hide()
    entry.button:SetAttribute("class-tool-interactive",false)
    entry.button:SetAttribute("type1","none");entry.button:SetAttribute("spell1",nil);entry.button:SetAttribute("unit1",nil)
    if entry.standalone then
        local function Release(button)
            if not button then return end
            Tools:ReleaseButton(button)
            button:SetAttribute("blessing-bar-enabled",false)
            button:SetAttribute("type1","none");button:SetAttribute("spell1",nil);button:SetAttribute("unit1",nil)
            button:Hide();YAB.Visuals:ReleaseButton(button)
            YAB.BarManager.buttonConfigSnapshots[button],YAB.BarManager.mouseoverRecords[button]=nil,nil
            if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end
        Release(entry.button);Release(self.manager)
        for _,row in pairs(self.rows) do Release(row.barCast) end
        YAB.BarManager.mouseoverRecords[entry.panel]=nil
    end
    self.groupAuraActive=nil
    if RegisterStateDriver and UnregisterStateDriver then UnregisterStateDriver(entry.button,"visibility") end
    for _,row in pairs(self.rows) do
        if GameTooltip and GameTooltip:IsOwned(row.cast) then GameTooltip:Hide() end
        row.choices:Hide();row.memberPanel:Hide();row.control:Hide()
        YAB.BarManager.mouseoverRecords[row.choices],YAB.BarManager.mouseoverRecords[row.memberPanel],YAB.BarManager.mouseoverRecords[row.control]=nil,nil,nil
        row.cast:SetAttribute("type1","none");row.cast:SetAttribute("macrotext1",nil)
        row.members={}
        row.control:SetAttribute("target",nil);row.cast:SetAttribute("spell1",nil);row.cast:SetAttribute("unit1",nil)
        YAB.Visuals:ReleaseButton(row.cast);YAB.BarManager.buttonConfigSnapshots[row.cast]=nil
    end
    for _,button in ipairs(self.memberPool or {}) do
        YAB.SecureFactory:ReleaseBlessingTarget(button.blessingHeader)
        if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        button:SetAttribute("type1","none");button:SetAttribute("spell1",nil);button:SetAttribute("unit1",nil);Caption(button.memberText,"")
        self.states[button]=nil
        YAB.BarManager.mouseoverRecords[button]=nil
    end
    self.unitRows,self.entry,self.dirty=nil,nil,true
end
