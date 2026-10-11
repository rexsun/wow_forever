-- Shared text styling decorates existing inline widgets without replacing their
-- content builders, status rules, event owners or secure action configuration.
local Appearance={}
Appearance.__index=Appearance
local textKeys={"text","value","label","textH","textM","textSep"}
local methods={"UpdateBarItem","UpdateTimeText","UpdateButtons","UpdateMicroMenu","UpdateTalents","UpdateProfessions","RefreshDisplay"}
local empty={}
local function Public(v)return not issecretvalue or not issecretvalue(v)end
local function RememberTheme(state,text)
    local status=text.gui2StatusOwner
    state.key=status and status.gui2ValueColorKey or text.gui2ColorKey
    state.fallback=status and status.gui2ValueColorFallback or text.gui2ColorFallback
end
function Appearance.New(bridge,view)
    return setmetatable({bridge=bridge,view=view,wrapped={},hooked=setmetatable({},{__mode="k"}),
        textState=setmetatable({},{__mode="k"}),classColor={1,1,1,1},depth=0},Appearance)
end
function Appearance:Text(text,color)
    if not text or not text.GetText or not text.SetTextColor then return end
    local state=self.textState[text]
    if color then
        local raw=text:GetText()
        if not Public(raw) then return end
        local r,g,b,a=text:GetTextColor()
        if not Public(r) or not Public(g) or not Public(b) or not Public(a) then return end
        if not state then state={r=r,g=g,b=b,a=a};RememberTheme(state,text);self.textState[text]=state end
        if state.customR and (r~=state.customR or g~=state.customG or b~=state.customB or a~=state.customA) then
            state.r,state.g,state.b,state.a=r,g,b,a
            RememberTheme(state,text)
        end
        if raw~=state.stripped then
            state.original=raw
            state.stripped=type(raw)=="string" and raw:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","") or raw
            if raw~=state.stripped then text:SetText(state.stripped) end
        end
        if r~=color[1] or g~=color[2] or b~=color[3] or a~=(color[4] or 1) then
            if self.bridge.ybar.SetThemedTextRawColor then
                self.bridge.ybar:SetThemedTextRawColor(text,color[1],color[2],color[3],color[4] or 1)
            else text:SetTextColor(color[1],color[2],color[3],color[4] or 1) end
        end
        state.customR,state.customG,state.customB,state.customA=color[1],color[2],color[3],color[4] or 1
    elseif state then
        local raw=text:GetText()
        if Public(raw) and raw==state.stripped and state.original~=state.stripped then text:SetText(state.original) end
        if state.key and self.bridge.ybar.SetThemedTextColor then
            self.bridge.ybar:SetThemedTextColor(text,state.key,state.fallback)
        elseif self.bridge.ybar.SetThemedTextRawColor then
            self.bridge.ybar:SetThemedTextRawColor(text,state.r,state.g,state.b,state.a)
        else text:SetTextColor(state.r,state.g,state.b,state.a) end
        self.textState[text]=nil
    end
end
function Appearance:Paint(frame,color)
    if not frame then return end
    -- BarItem state/theme refreshes own a second text-color write path.
    -- Decorate only these ordinary widgets and retain their hover highlight.
    if frame.gui2Component=="BarItem" then self:Wrap(frame,"SetState",true) end
    for _,key in ipairs(textKeys) do self:Text(frame[key],color) end
end
function Appearance:Apply()
    local bridge,view=self.bridge,self.view
    if not bridge.active or not bridge:GetModel().instances[view.id] then return end
    local M,db=bridge.lib.Model,bridge:GetModel()
    local mode=M.Resolve(db,view.id,"colorMode")
    local color=mode=="custom" and M.Resolve(db,view.id,"color") or nil
    if mode=="class" then
        color=self.classColor
        color[1],color[2],color[3]=bridge.yui.GUI2:GetColor("color.class.primary")
    end
    self:Paint(view.module.frame,color);self:Paint(view.module.content,color)
    for _,button in ipairs(view.module.buttons or empty) do
        local parent=button.GetParent and button:GetParent()
        for _=1,3 do
            if not parent then break end
            if parent==view.module.frame or parent==view.module.content then
                self:Paint(button,color);self:Wrap(button,"Update");break
            end
            parent=parent.GetParent and parent:GetParent()
        end
    end
end
function Appearance:Wrap(owner,key,preserveHover)
    if type(owner[key])~="function" then return end
    local hooked=self.hooked[owner]
    if hooked and hooked[key] then return end
    if not hooked then hooked={};self.hooked[owner]=hooked end
    hooked[key]=true
    local original=owner[key]
    local style=self
    local wrapper=function(...)
        style.depth=style.depth+1
        local ok,a,b,c=pcall(original,...)
        style.depth=style.depth-1
        if not ok then error(a,0) end
        if style.depth==0 and not (preserveHover and owner.gui2State=="hover") then style:Apply() end
        return a,b,c
    end
    owner[key]=wrapper
    self.wrapped[#self.wrapped+1]={owner=owner,key=key,original=original,wrapper=wrapper}
end
function Appearance:Attach()
    for _,key in ipairs(methods) do self:Wrap(self.view.module,key) end
end
function Appearance:Close()
    for _,item in ipairs(self.wrapped) do
        if item.owner[item.key]==item.wrapper then item.owner[item.key]=item.original end
    end
    for text in pairs(self.textState) do self:Text(text,nil) end
    self.wrapped={}
end
local owner=_G.YUI and _G.YUI.YBar
if owner then owner.LayoutLibraries=owner.LayoutLibraries or {};owner.LayoutLibraries.Appearance=Appearance end
return Appearance
