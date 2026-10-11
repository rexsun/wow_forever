local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
local UI = HUD and HUD.DesignerUI
if not UI then return end
local GUI, Settings = YUI.GUI2, YUI.Settings
local function T(key, ...) local value=HUD:T('designer.library.'..key); return select('#',...)>0 and string.format(value,...) or value end
local function Label(parent,text,size,color)
    return GUI:CreateText(parent,text,size or 'font.size.md',color or 'color.text.primary','LEFT')
end
local function Scope(row)
    if row.error then return T('invalid') end
    if #row.specs==0 then return T('full') end
    return UI:GetToolbarSpecNames(row.specs)
end

function UI:SelectRecommended(row)
    local frame=self.recommendedLibrary
    frame.selected=row
    frame.heading:SetText(row.entry.name or '')
    frame.author:SetText(T('author',row.entry.author or ''))
    frame.scope:SetText(Scope(row))
    frame.sound:SetText(T('sounds',row.soundCount or 0))
    frame.description:SetText(row.error and T('invalid_detail',row.error) or row.entry.description)
    frame.import:SetDisabled(row.error~=nil)
    for _,button in ipairs(frame.pool) do button:SetSelected(button.row==row) end
end

function UI:ToggleRecommendedLibrary()
    if self.busyKind then return end
    if Settings.SoundCenter and Settings.SoundCenter.CloseDesignerWindow then Settings.SoundCenter:CloseDesignerWindow() end
    self:HideSpecializationPicker()
    local frame=self.recommendedLibrary
    if frame and frame:IsShown() then frame:Hide(); return end
    if not frame then
        frame=GUI:CreatePanel(UIParent,{name='YUI_YHUD_RecommendedLibrary',width=940,height=490,surface='color.surface.popup',border='color.popup.border',shadow=true})
        self.recommendedLibrary=frame; frame.pool={}
        frame:SetFrameStrata('FULLSCREEN_DIALOG'); frame:SetFrameLevel(580); frame:EnableMouse(true)
        Label(frame,T('title'),'font.size.lg','color.text.heading'):SetPoint('TOPLEFT',20,-20)
        GUI:CreateCloseButton(frame,function() frame:Hide() end):SetPoint('TOPRIGHT',-14,-16)
        frame.empty=Label(frame,T('empty'),'font.size.lg','color.text.secondary'); frame.empty:SetPoint('CENTER')
        frame.scroll=GUI:CreateScrollFrame(frame,{template='UIPanelScrollFrameTemplate',width=358,height=392,childWidth=340,childHeight=392})
        frame.scroll:SetPoint('TOPLEFT',16,-72)
        frame.detail=GUI:CreateFrame(frame,{width=512,height=392}); frame.detail:SetPoint('TOPLEFT',400,-72)
        frame.heading=Label(frame.detail,'','font.size.lg','color.text.heading'); frame.heading:SetPoint('TOPLEFT'); frame.heading:SetWidth(500)
        frame.author=Label(frame.detail,'',nil,'color.badge.purple'); frame.author:SetPoint('TOPLEFT',0,-36)
        frame.scope=Label(frame.detail,'',nil,'color.text.accent'); frame.scope:SetPoint('TOPLEFT',0,-65); frame.scope:SetWidth(300)
        frame.sound=Label(frame.detail,'',nil,'color.state.success'); frame.sound:SetPoint('TOPRIGHT',0,-65)
        frame.description=Label(frame.detail,''); frame.description:SetPoint('TOPLEFT',0,-112); frame.description:SetSize(500,205); frame.description:SetJustifyV('TOP'); frame.description:SetWordWrap(true)
        frame.import=GUI.Form:CreateButton(frame.detail,{text=T('import'),width=156,height=36,tone='success',onClick=function()
            if frame.selected and not frame.selected.error then self:ImportRecommended(frame.selected.entry) end
        end}); frame.import:SetPoint('BOTTOMRIGHT')
        frame:SetScript('OnHide',function() frame.selected=nil; GameTooltip:Hide() end)
    end
    frame:ClearAllPoints(); frame:SetPoint('TOP',self.toolbar,'BOTTOM',0,-64)
    frame:SetScale(math.min(1,(UIParent:GetWidth()-48)/940,(UIParent:GetHeight()-180)/490))
    local rows=HUD.Recommended:List()
    for index,row in ipairs(rows) do
        local button=frame.pool[index]
        if not button then
            button=GUI.Form:CreateButton(frame.scroll.child,{text='',width=338,height=104,onClick=function(control) self:SelectRecommended(control.row) end})
            button.image=GUI:CreateIcon(button,{icon=134400,size=82,crop=false}); button.image:SetPoint('LEFT',8,0)
            button.name=Label(button,'',nil,'color.text.heading'); button.name:SetPoint('TOPLEFT',102,-14); button.name:SetWidth(225); button.name:SetWordWrap(false)
            button.author=Label(button,'','font.size.sm','color.badge.purple'); button.author:SetPoint('TOPLEFT',102,-43); button.author:SetWidth(225); button.author:SetWordWrap(false)
            button.scope=Label(button,'','font.size.sm','color.text.accent'); button.scope:SetPoint('TOPLEFT',102,-68); button.scope:SetWidth(130); button.scope:SetWordWrap(false)
            button.sound=Label(button,'','font.size.sm','color.state.success'); button.sound:SetPoint('TOPRIGHT',-8,-68)
            button:HookScript('OnEnter',function(control)
                local r=control.row; GameTooltip:SetOwner(control,'ANCHOR_RIGHT')
                GameTooltip:SetText(r.entry.name or '')
                if r.specs then local _,full=self:GetToolbarSpecNames(r.specs); if full~='' then GameTooltip:AddLine(full,1,1,1,true) end end
                GameTooltip:Show()
            end)
            button:HookScript('OnLeave',function() GameTooltip:Hide() end)
            frame.pool[index]=button
        end
        button.row=row; button:SetPoint('TOPLEFT',0,-(index-1)*114)
        button.name:SetText(row.entry.name or T('invalid')); button.author:SetText(T('author',row.entry.author or ''))
        button.scope:SetText(Scope(row)); button.sound:SetText(T('sounds',row.soundCount or 0))
        local texture=row.entry.image and YUI.Assets:Product('yhud',row.entry.image) or YUI.Assets:Product('yhud','icons\\logo_32.png')
        button.image:SetTexture(texture); button:Show()
    end
    for index=#rows+1,#frame.pool do frame.pool[index]:Hide() end
    frame.scroll.child:SetHeight(math.max(392,#rows*114)); frame.scroll:SetVerticalScroll(0)
    frame.empty:SetShown(#rows==0); frame.scroll:SetShown(#rows>0); frame.detail:SetShown(#rows>0)
    if rows[1] then self:SelectRecommended(rows[1]) end
    frame:Show()
end

function UI:ImportRecommended(entry)
    local row,code=HUD.Recommended:Describe(entry)
    if not row then self:SetStatus(T('invalid_detail',code)); return nil,code end
    self:PrepareToolbarExternalAction(T('title'),function()
        local frame=self.recommendedLibrary
        self.libraryImportActive=true
        self:SetBusyInteractionBlocked(true)
        local imported=false
        local ok,why=HUD.Sharing:ShowImport(entry.share,{
            layoutOwner=frame,
            independentNotice=T('independent'),
            onComplete=function() imported=true end,
            onClosed=function()
                self.libraryImportActive=nil
                self:SetBusyInteractionBlocked(self.busyKind~=nil)
                if imported then
                    frame:Hide()
                    if self.active then self:ReloadAfterExternalImport() end
                end
            end,
        })
        if not ok then self.libraryImportActive=nil; self:SetBusyInteractionBlocked(false); self:SetStatus(T('invalid_detail',why or 'unknown')) end
    end)
end
