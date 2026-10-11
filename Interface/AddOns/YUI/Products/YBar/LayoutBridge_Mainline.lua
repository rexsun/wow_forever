-- Native frame adapter for the configuration model and incremental layout runtime.
-- Installation is performed after all Mainline modules have registered.
local Bridge={}
Bridge.__index=Bridge
function Bridge.New(yui, libraries)
    local self=setmetatable({yui=yui,ybar=yui.YBar,lib=libraries,active=false,bars={},original={},revision=0,
        hostWrites=setmetatable({},{__mode="k"}),viewPool={},hostPool={}},Bridge)
    self.adapters=libraries.Catalog.Build({})
    return self
end
function Bridge:GetModel()
    local session=self.session or self.settingsSession
    return session and session.state~="closed" and session:GetModel() or self.committed
end
function Bridge:GetRawRoot()
    local profile=self.ybar:GetProfile()
    return profile and profile.YBar
end
function Bridge:Report(reason,id)
    local handler=geterrorhandler and geterrorhandler()
    if handler then handler("Orbit "..tostring(id or "layout")..": "..tostring(reason)) end
end
function Bridge:Discover()
    local names={}
    for kind in pairs(self.ybar.RegisteredModules) do names[#names+1]=kind end
    for _,id in ipairs(self:GetModel().instanceOrder) do names[#names+1]=self:GetModel().instances[id].moduleType end
    local adapters=self.lib.Catalog.Build({modules={top=names}})
    for name,adapter in pairs(adapters) do self.adapters[name]=adapter end
    if self.config then self.config:Invalidate() end
end
function Bridge:Changed(affected)
    if self:InCombat() then return end
    self.config:Invalidate()
    if self.runtime then
        self.runtime:Reconcile(affected);self.runtime:Flush()
    end
    if self.yui.Layout then
        for id,host in pairs(self.bars) do
            if id~="top" and id~="bottom" then
                local placement=self:GetModel().bars[id].placement
                if not self.lib.Model.Equal(host.ybarAppliedPlacement,placement) then
                    self.yui.Layout:RefreshFrame("ybar."..id)
                    host.ybarAppliedPlacement=self.lib.Model.Copy(placement)
                end
            end
        end
    end
    if self.ybar.UpdateDisplayModes then self.ybar:UpdateDisplayModes() end
    if self.designer then self.designer:Refresh(affected) end
end
function Bridge:InCombat()
    local security=self.yui.API and self.yui.API.Security
    return security and security.InCombatLockdown() or InCombatLockdown()
end
function Bridge:Prepare(source)
    local M=self.lib.Model
    if type(source)~="table" then return nil,"invalid-profile" end
    if source.version==2 then
        local ok,reason=M.Validate(source)
        if not ok then return nil,reason end
        source=M.NormalizeLegacySurface(M.NormalizeDisplayPreferences(source))
        local names={}
        for _,id in ipairs(source.instanceOrder) do names[#names+1]=source.instances[id].moduleType end
        self.adapters=self.lib.Catalog.Build({modules={top=names}})
        ok,reason=self:Validate(source)
        if not ok then return nil,reason end
        return M.NormalizeGeometry(source)
    end
    if not M.IsSerializable(source) then return nil,"invalid-profile-values" end
    local copy=M.Copy(source)
    if self.ybar.CurrencyTracking then self.ybar.CurrencyTracking.Prepare(copy) end
    self.adapters=self.lib.Catalog.Build(copy)
    local db,reason=self.lib.Migration.Build(copy,self.adapters)
    if not db then return nil,reason end
    self.lib.Catalog.ExtractAppearance(M,db,self.adapters)
    db.defaults.font=STANDARD_TEXT_FONT
    db.defaults.size=14
    db.defaults.colorMode="state"
    db.defaults.iconGap=4
    db.defaults.iconBackground=true
    db.defaults.iconSize=16
    db.defaults.color={1,1,1,1}
    db.defaults.display="both"
    for _,id in ipairs(db.instanceOrder) do
        local inst=db.instances[id]
        if inst.moduleType=="Clock" and inst.appearance.size==nil then inst.appearance.size=21 end
    end
    return M.NormalizeDisplayPreferences(db)
end
function Bridge:NewHost(id,config)
    local ybar,gui=self.ybar,self.yui.GUI2
    local frame=id=="top" and ybar.topFrame or id=="bottom" and ybar.bottomFrame
    if not frame then
        frame=table.remove(self.hostPool) or gui:CreateFrame(ybar.frame,{width=100,height=21})
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(false)
        frame.bg=frame.bg or gui:CreateTexture(frame,{layer="BACKGROUND"});frame.bg:SetAllPoints(frame)
    end
    frame.ybarLayoutId=id
    frame.ybarAppliedPlacement=nil
    self.bars[id]=frame
    if config.kind=="independent" and self.yui.Layout then
        local bridge=self
        local storage={
            identity=function()return bridge:GetModel()end,
            get=function()
                local bar=bridge:GetModel().bars[id]
                return bar and bar.placement
            end,
            set=function(_,_,placement)
                local bar=bridge:GetModel().bars[id]
                if not bar then return false,"missing-bar" end
                if bridge.session then
                    -- The Layout caller completes frame placement before the
                    -- queued designer refresh; never re-enter Layout here.
                    return bridge.session:Edit(function()bar.placement=placement end,id)
                end
                bar.placement=placement
                bridge.revision=bridge.revision+1
                return true
            end,
            clear=function()
                local bar=bridge:GetModel().bars[id]
                if not bar then return false,"missing-bar" end
                if bridge.session then return bridge.session:Edit(function()bar.placement=nil end,id) end
                bar.placement=nil;bridge.revision=bridge.revision+1
                return true
            end,
        }
        self.yui.Layout:RegisterFrame("ybar."..id,{
            frame=frame,title=config.name or id,editModeCategory="information",
            defaultPlacement={anchor={point="CENTER",relative="UIParent",relativePoint="CENTER"},offset={x=0,y=0}},
            placementStorage=storage,
            onPlacementCommitted=function()
                if bridge.onPlacementCommitted then bridge.onPlacementCommitted(id) end
            end,
        })
    elseif config.kind=="independent" then
        frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    end
    return frame
end
function Bridge:ReleaseHost(id,frame)
    if id~="top" and id~="bottom" and self.yui.Layout then self.yui.Layout:UnregisterFrame("ybar."..id) end
    frame:Hide()
    if id~="top" and id~="bottom" then self.hostPool[#self.hostPool+1]=frame end
    self.bars[id]=nil;self.hostWrites[frame]=nil
end
function Bridge:NewView(id,instance)
    local kind=instance.moduleType
    local adapter=self.adapters[kind]
    if not adapter and not self.session then return nil end
    adapter=adapter or {}
    local factory=self.ybar.ModuleFactories and self.ybar.ModuleFactories[kind]
    local registered=self.ybar.RegisteredModules[kind]
    if not factory and not registered and not self.session then return nil end
    local pool=self.viewPool[kind]
    local reused=pool and table.remove(pool)
    local context=reused and reused.context or self.config:GetContext(id)
    context.id=id
    context.events=self.signals
    local module=reused and not reused.placeholderModule and reused.module or factory and factory(context) or registered
    local placeholderModule=not module
    if not module and reused and reused.placeholderModule then module=reused.module end
    if not module and self.session then
        local gui=self.yui.GUI2
        module={name=kind,CreateBarItem=function(m,parent)m.frame=gui:CreateFrame(parent,{width=80,height=20})end,
            IsBarItemRenderable=function()return false end,UpdateBarItem=function()end,GetWidth=function()return 80 end}
    end
    if not module then return nil end
    local view={id=id,module=module,context=context,moduleType=kind,ownsModule=factory~=nil,
        preview=self.session~=nil and factory==nil,placeholderModule=placeholderModule}
    if reused then view.snapshot=reused.snapshot;view.placeholder=reused.placeholder end
    if factory then module.name=id end
    if not factory and adapter.configKey and module.db then module.db=context:GetConfig() end
    if factory and module.OnLifecycleInitialize then module:OnLifecycleInitialize() end
    if factory then self.ybar.RegisteredModules[id]=module end
    if self.lib.Appearance then
        view.appearance=self.lib.Appearance.New(self,view);view.appearance:Attach()
    end
    return view
end
function Bridge:RefreshView(view)
    local module=view.module
    -- The parking parent remains hidden; restore local visibility for snapshots.
    if view.preview and module.frame then module.frame:Show() end
    if not view.bound then
        view.bound=true
        if module.OnDBReload then module:OnDBReload()
        elseif view.moduleType=="RaidMarkers" or view.moduleType=="MeetingStone" then module:OnInitialize() end
    end
    if module.UpdateBarItem then module:UpdateBarItem(module.frame,module.parent)
    elseif module.Update then module:Update() end
end
function Bridge:Measure(view)
    local module,config=view.module,view.context:GetConfig()
    local visible=not module.IsBarItemRenderable or module:IsBarItemRenderable()
    if not visible then
        if not self.session then return 0,0,false end
        if not view.placeholder then
            view.placeholder=self.yui.GUI2:CreatePanel(view.host,{width=120,height=24})
            view.placeholder.text=self.yui.GUI2:CreateText(view.placeholder,"",12,"color.text.secondary")
            view.placeholder.text:SetPoint("CENTER")
        end
        view.placeholder:SetParent(view.host)
        view.placeholder.text:SetText(self.designer and self.designer:InstanceTitle(view.id) or view.moduleType)
        if view.displayFrame~=view.placeholder then
            view.displayFrame:Hide();view.displayFrame=view.placeholder;self.runtime.applied[view.id]=nil
        end
        return math.max(view.placeholder.text:GetStringWidth()+16,80),24,true
    elseif view.placeholder then
        view.placeholder:Hide()
        if view.displayFrame~=view.baseDisplayFrame then view.displayFrame=view.baseDisplayFrame;self.runtime.applied[view.id]=nil end
    end
    if view.preview and module.frame then module.frame:Show() end
    local width=module.GetWidth and module:GetWidth() or module.frame:GetWidth()
    local size=self.lib.Model.Resolve(self:GetModel(),view.id,"size") or config.size or 14
    local height=module.contentHeight
    if view.moduleType=="Clock" then
        -- Internal text adjustment must not resize the module or its bar.
        height=config.fontSize or size
    elseif not height then height=size+6 end
    if view.preview and view.snapshot then
        -- Snapshot child anchors only after the parked source has its measured size.
        module.frame:SetSize(math.max(width,1),math.max(height,1))
        view.snapshot:Update(module.frame)
    end
    return width,height,true
end
function Bridge:CreateRuntime()
    local bridge,ybar=self,self.ybar
    self.signals=self.signals or self.lib.Signals.New(self.yui.Event,function(reason,owner)
        local runtime=bridge.runtime
        local id=owner and owner.name
        if runtime and id and runtime.views[id] then
            bridge.signals:OffOwner(owner);runtime:Fail(id,reason);runtime:MarkDirty(id)
        else bridge:Report(reason,id) end
    end,function(delay,callback)return C_Timer.NewTicker(delay,callback)end)
    self.config=self.lib.Config.New(self.lib.Model,self.lib.Context,self.adapters,function()return bridge:GetModel()end)
    if self.lib.Surface and not self.surface then
        self.surface=self.lib.Surface.New(self.yui.GUI2,LibStub("LibSharedMedia-3.0"),self.yui.API and self.yui.API.Unit)
    end
    self.runtime=self.lib.Runtime.New(self.lib.Model,self.lib.Geometry,{
        getModel=function()return bridge:GetModel()end,inCombat=function()return bridge:InCombat()end,
        isDesign=function()return bridge.session~=nil end,
        schedule=function(callback)return C_Timer.NewTimer(0,callback)end,
        createBar=function(id,config)return bridge:NewHost(id,config)end,
        releaseBar=function(id,frame)bridge:ReleaseHost(id,frame)end,
        showBar=function(frame,shown)
            if bridge:InCombat() then return end
            local cached=bridge.hostWrites[frame] or {};bridge.hostWrites[frame]=cached
            if cached.shown~=shown then frame:SetShown(shown);cached.shown=shown end
        end,
        sizeBar=function(frame,width,height,overflow)
            local cached=bridge.hostWrites[frame] or {};bridge.hostWrites[frame]=cached
            width,height=math.max(width,1),math.max(height,1)
            if cached.width~=width or cached.height~=height then
                frame:SetSize(width,height);cached.width=width;cached.height=height
                if frame.ybarLayoutId~="top" and frame.ybarLayoutId~="bottom" and bridge.yui.Layout then
                    bridge.yui.Layout:RefreshFrame("ybar."..frame.ybarLayoutId)
                end
            end
            frame.ybarOverflow=overflow
            if bridge.surface then bridge.surface:Apply(frame,bridge:GetModel().bars[frame.ybarLayoutId].surface) end
        end,
        availableLength=function()return ybar.frame:GetWidth()end,
        overflowWidth=28,
        overflow=function(host,hidden,vertical)bridge:UpdateOverflow(host,hidden,vertical)end,
        createView=function(id,instance)return bridge:NewView(id,instance)end,
        mountView=function(view,host)
            local module=view.module
            local parent=view.preview and bridge:GetParking() or host
            if not module.frame and module.CreateBarItem then module:CreateBarItem(parent) end
            assert(module.frame,"missing-module-frame")
            module.frame:SetParent(parent);module.parent=parent;module.frame.module=module
            if view.preview then
                -- A newly added module has never received a live placement.
                -- Give its hidden source a resolved origin before reading regions.
                module.frame:ClearAllPoints()
                module.frame:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
                if not view.snapshot then view.snapshot=bridge.lib.Snapshot.New(bridge.yui.GUI2,host) end
                view.displayFrame=view.snapshot.frame;view.displayFrame:SetParent(host)
            else view.displayFrame=module.frame end
            view.baseDisplayFrame=view.displayFrame
            view.host=host
        end,
        enableView=function(view)
            if not view.preview then
                if view.module.AttachRuntime then view.module:AttachRuntime() end
            end
        end,
        disableView=function(view)
            if bridge:InCombat() then bridge.cleanupPending=true;return end
            local timer=ybar.displayTimers and ybar.displayTimers[view.module.name]
            if timer then timer:Cancel();ybar.displayTimers[view.module.name]=nil end
            if view.module.DetachRuntime then view.module:DetachRuntime() end
            if view.module.frame then
                if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(view.module.frame) end
                view.module.frame:Hide()
            end
            if view.displayFrame then view.displayFrame:Hide() end
            if view.placeholder then view.placeholder:Hide() end
        end,
        releaseView=function(view)
            if view.appearance then view.appearance:Close() end
            if view.displayFrame then view.displayFrame:Hide() end
            if view.snapshot then view.snapshot.frame:Hide() end
            if view.placeholder then view.placeholder:Hide() end
            bridge.signals:OffOwner(view.module)
            if view.ownsModule then ybar.RegisteredModules[view.id]=nil end
            local pool=bridge.viewPool[view.moduleType] or {};bridge.viewPool[view.moduleType]=pool
            pool[#pool+1]=view
        end,
        refreshView=function(view)bridge:RefreshView(view)end,
        measureView=function(view)return bridge:Measure(view)end,
        placeView=function(view,x,y,width,height,visible)
            local frame=view.displayFrame
            frame:ClearAllPoints();frame:SetPoint("TOPLEFT",view.host,"TOPLEFT",x,-y)
            frame:SetSize(math.max(width,1),math.max(height,1));frame:SetShown(visible)
        end,
        report=function(reason,id)bridge:Report(reason,id)end,
        afterFlush=function()
            if bridge.designer and bridge.session then bridge.designer:RefreshCanvas() end
        end,
    })
end
function Bridge:GetParking()
    if not self.parking then
        self.parking=self.yui.GUI2:CreateFrame(UIParent,{width=1,height=1})
        self.parking:SetPoint("CENTER");self.parking:Hide()
    end
    return self.parking
end
function Bridge:ParkModules()
    for key,timer in pairs(self.ybar.displayTimers or {}) do
        timer:Cancel();self.ybar.displayTimers[key]=nil
    end
    for _,module in pairs(self.ybar.RegisteredModules) do
        if module.DetachRuntime then module:DetachRuntime() end
        if module.frame then
            if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(module.frame) end
            module.frame:SetParent(self:GetParking());module.parent=self.parking
        end
    end
end
function Bridge:OnCombatEnded()
    if self.reloadPending then self.reloadPending=nil;return self.ybar:ReloadDB() end
    if self.cleanupPending then
        self.cleanupPending=nil
        if not self.ybar:IsEnabled() then self:ParkModules() end
    end
    if self.runtime then self.runtime:OnCombatEnded() end
end
function Bridge:OnCombatStarted()
    self:CloseModuleSettings()
    if self.session then self.session:Suspend() end
end
function Bridge:OnViewportChanged()
    if self.runtime then self.runtime:MarkDirty() end
    if self.designer and self.designer.visible and not self:InCombat() then self.designer:FitViewport() end
end
function Bridge:BindEvents()
    if self.eventsBound then return end
    self.eventsBound=true
    self.yui.Event:On("PLAYER_REGEN_ENABLED","OnCombatEnded",self)
    self.yui.Event:On("PLAYER_REGEN_DISABLED","OnCombatStarted",self)
    self.yui.Event:On("UI_SCALE_CHANGED","OnViewportChanged",self)
    self.yui.Event:On("DISPLAY_SIZE_CHANGED","OnViewportChanged",self)
end
function Bridge:Activate(model)
    if self:InCombat() then return false,"combat" end
    if self.runtime then
        -- Runtime owns its active modules and detaches each exactly once.
        self.runtime:Close();self.signals:Close()
    else
        -- Only initial takeover needs to stop the legacy lifecycle owners.
        for _,module in pairs(self.ybar.RegisteredModules) do
            if module.DetachRuntime then module:DetachRuntime() end
        end
    end
    if model.geometryVersion~=1 then model=self.lib.Model.NormalizeGeometry(model) end
    model=self.lib.Model.NormalizeDisplayPreferences(model)
    self.committed=model
    self.active=true
    self:CreateRuntime()
    self.ybar.db=self.config.root
    self:BindEvents()
    local ok,reason=self.runtime:SetEnabled(self.config.root.enable~=false)
    self.runtime:Flush()
    if self.ybar.UpdateDisplayModes then self.ybar:UpdateDisplayModes() end
    return ok~=false,reason
end
function Bridge:UpdateOverflow(host,hidden,vertical)
    local badge=host.ybarOverflowBadge
    if #hidden==0 then if badge then badge:Hide() end;return end
    if not badge then
        badge=self.yui.GUI2:CreateButtonFrame(host,{width=26,height=20})
        badge.text=self.yui.GUI2:CreateText(badge,"…",12,"color.text.accent");badge.text:SetPoint("CENTER")
        badge:SetScript("OnEnter",function()
            local L=self.yui.Locale:Get("YBar")
            GameTooltip:SetOwner(badge,host.ybarLayoutId=="top" and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
            GameTooltip:ClearLines();GameTooltip:AddLine(L["designer.overflow"])
            for _,id in ipairs(badge.hidden) do
                local inst=self:GetModel().instances[id]
                if inst then GameTooltip:AddLine(self.designer and self.designer:InstanceTitle(id) or inst.moduleType,1,1,1) end
            end
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave",function()self.yui.HideGameTooltip()end)
        badge:SetScript("OnClick",function()
            local ok=self:OpenDesigner()
            if ok then self.designer:Select("bar",host.ybarLayoutId) end
        end)
        host.ybarOverflowBadge=badge
    end
    badge.hidden=hidden;badge:ClearAllPoints()
    badge:SetPoint(vertical and "BOTTOM" or "RIGHT",host,vertical and "BOTTOM" or "RIGHT",0,0)
    badge:SetFrameLevel(host:GetFrameLevel()+8);badge:Show()
end
function Bridge:Validate(model)
    local ok,reason=self.lib.Model.Validate(model)
    if not ok then return false,reason end
    local seen={}
    for _,id in ipairs(model.instanceOrder) do
        local kind=model.instances[id].moduleType
        local adapter=self.adapters[kind]
        if adapter and not adapter.multi and seen[kind] then return false,"duplicate-singleton" end
        seen[kind]=true
    end
    local bug,broker
    for _,id in ipairs(model.instanceOrder) do
        local kind=model.instances[id].moduleType
        local bar=self.lib.Model.FindBar(model,id)
        if bar and bar.enabled~=false then
            bug=bug or kind=="BugSack";broker=broker or kind=="Broker:BugSack"
        end
    end
    if bug and broker then return false,"duplicate-broker-entry" end
    return true
end
function Bridge:CommitDesigner(model,raw)
    if self:GetRawRoot()~=raw or self:InCombat() then return false,"stale-profile" end
    local session,previous=self.session,self.committed
    if self.designer then self.designer:Hide() end
    self.session=nil
    local ok,result,reason=pcall(self.Activate,self,model)
    if ok and result~=false and not next(self.runtime.failures) and not self.runtime.fatalFailure then
        self.ybar:GetProfile().YBar=model
        self.committed=model;self.revision=self.revision+1;self.preparedCommit=model
        return true
    end
    -- Saved configuration is still untouched. Rebuild the editable draft so a
    -- failed native activation is a recoverable save error, not a partial save.
    if self.runtime then self.runtime:Close();self.signals:Close() end
    self.committed=previous;self.session=session;self:ParkModules()
    self:CreateRuntime();self.ybar.db=self.config.root
    self.runtime:SetEnabled(true);self.runtime:Flush()
    if self.designer then self.designer:Show() end
    return false,ok and (reason or "runtime-activation-failed") or "runtime-activation-failed"
end
function Bridge:CloseModuleSettings()
    if not self.settingsSession then return end
    local pending=self.designerRefresh
    local affected=self.designerAffected
    if pending then pending:Cancel();self.designerRefresh=nil;self.designerAffected=nil end
    self.settingsSession=nil
    if self.designer and self.designer.liveSettings then
        self.designer.liveSettings=nil;self.designer:Hide()
    end
    if pending and self.runtime then
        if self:InCombat()then self.reloadPending=true else self:Changed(affected)end
    end
end
function Bridge:OpenModuleSettings(moduleName)
    if self:InCombat() then return false,"combat" end
    if self.session then
        self.config:Refresh()
        local id=self:GetModel().instances[moduleName] and moduleName or self.config.first[moduleName]
        if id then self.designer:Select("instance",id);self.designer:OpenDetails() end
        return id~=nil
    end
    self:CloseModuleSettings()
    if not self.active then
        local model,reason=self:Prepare(self:GetRawRoot())
        if not model then return false,reason end
        local ok;ok,reason=self:Activate(model);if not ok then return false,reason end
    end
    self.config:Refresh()
    local id=self:GetModel().instances[moduleName] and moduleName or self.config.first[moduleName]
    if not id then return false,"missing-instance" end
    local expected=self:GetRawRoot()
    local bridge=self
    local session,reason=self.lib.Session.New(self.lib.Model,self.committed,self.revision,{
        revision=function()return bridge:GetRawRoot()==expected and bridge.revision or -1 end,
        changed=function(affected)
            local session=bridge.settingsSession
            bridge.committed=session:GetModel()
            bridge.ybar:GetProfile().YBar=bridge.committed;expected=bridge.committed
            bridge.revision=bridge.revision+1;session.draft.revision=bridge.revision
            session.draft.undo={};session.draft.redo={}
            bridge:QueueDesignerRefresh(affected)
        end,
    })
    if not session then return false,reason end
    self.settingsSession=session
    if not self.designer then self.designer=self.lib.Designer.New(self) end
    local d=self.designer
    d.liveSettings=true;d.visible=true;d.scope="instance";d.selected=id
    d:OpenDetails()
    return true
end
function Bridge:OpenDesigner()
    self:CloseModuleSettings()
    if self:InCombat() then return false,"combat" end
    if self.session then
        local ok,reason=self.session:Resume()
        if ok then self.designer:Show() end
        return ok,reason
    end
    if not self.active then
        local model,reason=self:Prepare(self:GetRawRoot())
        if not model then return false,reason end
        self.committed=model
    end
    local bridge=self
    local raw=self:GetRawRoot()
    local sourceCopy=self.lib.Model.Copy(raw)
    local revision=self.revision
    local session,reason=self.lib.Session.New(self.lib.Model,self.committed,revision,{
        revision=function()
            if bridge:GetRawRoot()~=raw or not bridge.lib.Model.Equal(raw,sourceCopy) then return -1 end
            return bridge.revision
        end,
        inCombat=function()return bridge:InCombat()end,
        changed=function(affected)bridge:QueueDesignerRefresh(affected)end,
        validate=function(model)return bridge:Validate(model)end,
        commit=function(model)return bridge:CommitDesigner(model,raw)end,
        stopInput=function()if bridge.designer then bridge.designer:Hide() end end,
        close=function()bridge:CloseDesigner()end,
    })
    if not session then return false,reason end
    if self.runtime then self.runtime:Close();self.signals:Close() end
    self:ParkModules()
    self.session=session;self.active=true
    self:CreateRuntime();self.ybar.db=self.config.root
    self:BindEvents()
    if self.ybar.BrokerManager then self.ybar.BrokerManager:OnSettingsEnter() end
    self:Discover()
    self.runtime:SetEnabled(true);self.runtime:Flush()
    if self.ybar.UpdateDisplayModes then self.ybar:UpdateDisplayModes() end
    if not self.designer then self.designer=self.lib.Designer.New(self) end
    self.designer:Show()
    return true
end
function Bridge:QueueDesignerRefresh(affected)
    if self.designerRefresh then
        if self.designerAffected~=affected then self.designerAffected=nil end
        return
    end
    self.designerAffected=affected
    self.designerRefresh=C_Timer.NewTimer(0,function()
        self.designerRefresh=nil
        if (self.session or self.settingsSession) and (self.session or self.settingsSession).state=="editing" then self:Changed(self.designerAffected) end
        self.designerAffected=nil
    end)
end
function Bridge:CloseDesigner()
    if self.designerRefresh then self.designerRefresh:Cancel();self.designerRefresh=nil end
    if self.designer then self.designer:Hide() end
    if self:InCombat() then self.reloadPending=true;return end
    if self.yui.Layout and self.layoutOpened then self.yui.Layout:CloseEditMode("ybar");self.layoutOpened=nil end
    self.session=nil
    local raw=self:GetRawRoot()
    if self.preparedCommit==raw then self.preparedCommit=nil
    elseif raw.version==2 then self:Activate(raw)
    else
        if self.runtime then self.runtime:Close();self.signals:Close() end
        self.active=false;self.ybar.db=raw
        self.original.ReloadDB(self.ybar)
    end
    if self.ybar.BrokerManager then self.ybar.BrokerManager:OnSettingsLeave() end
end
function Bridge:Install()
    local ybar,bridge=self.ybar,self
    local names={"EnsureDB","EnsureDefaults","UpdateLayout","UpdateLayoutImmediate","IsModuleOnBar",
        "IsSubModuleEnabled","SyncModuleLifecycles","GetModule","ReloadDB","Initialize",
        "RemoveModuleFromLayout","RestoreModuleToLayout","SetSubModuleEnabled","GetModuleDisplayMode",
        "UpdateAppearance","UpdatePosition","OnLifecycleDisable","OnLifecycleEnable","RegisterModule"}
    for _,name in ipairs(names) do self.original[name]=ybar[name] end
    function ybar:RegisterModule(module,descriptor)
        local result=bridge.original.RegisterModule(self,module,descriptor)
        if bridge.active then
            bridge:Discover()
            if bridge.runtime then bridge.runtime.reconcilePending=true end
        end
        return result
    end
    function ybar:GetModuleRoot(kind)
        if bridge.active then return bridge.config:GetModuleRoot(kind) end
        return bridge.original.EnsureDB(self)
    end
    function ybar:EnsureDB()
        if bridge.active then self.db=bridge.config.root;return self.db end
        local raw=bridge.original.EnsureDB(self)
        if raw and raw.version==2 then
            local model,reason=bridge:Prepare(raw)
            if not model then bridge:Report(reason);return raw end
            bridge.committed=model
            bridge.config=bridge.lib.Config.New(bridge.lib.Model,bridge.lib.Context,bridge.adapters,function()return bridge:GetModel()end)
            bridge.active=true
            self.db=bridge.config.root
            return self.db
        end
        return raw
    end
    function ybar:EnsureDefaults()
        self:EnsureDB()
        if bridge.active then return self:EnsureDB() end
        return bridge.original.EnsureDefaults(self)
    end
    function ybar:UpdateLayout(id)
        if bridge.active then
            if bridge.runtime then
                if bridge.runtime.reconcilePending and not bridge.runtime.reconciling then bridge.runtime:Reconcile() end
                return bridge.runtime:MarkDirty(id)
            end
            return
        end
        return bridge.original.UpdateLayout(self)
    end
    function ybar:UpdateLayoutImmediate()
        if bridge.active then
            if not bridge.runtime then bridge:CreateRuntime();bridge.runtime:SetEnabled(bridge.config.root.enable~=false) end
            bridge.runtime:Reconcile();return bridge.runtime:Flush()
        end
        return bridge.original.UpdateLayoutImmediate(self)
    end
    function ybar:IsModuleOnBar(name)
        if not bridge.active then return bridge.original.IsModuleOnBar(self,name) end
        bridge.config:Refresh()
        local db=bridge:GetModel()
        local id=db.instances[name] and name or bridge.config.first[name]
        local bar=id and bridge.lib.Model.FindBar(db,id)
        return bar~=nil and bar.enabled~=false
    end
    function ybar:IsSubModuleEnabled(name)
        if not bridge.active then return bridge.original.IsSubModuleEnabled(self,name) end
        if bridge.adapters[name] and bridge.adapters[name].multi then return false end
        if bridge.session and not bridge:GetModel().instances[name] then return false end
        return self:IsEnabled() and self:IsModuleOnBar(name)
    end
    function ybar:SyncModuleLifecycles()
        if bridge.active then
            if self.BrokerManager then self.BrokerManager:Sync();bridge:Discover() end
            if bridge.runtime then return bridge.runtime:Reconcile() end
            return
        end
        return bridge.original.SyncModuleLifecycles(self)
    end
    function ybar:GetModule(name)
        if bridge.active then
            bridge.config:Refresh()
            local id=bridge:GetModel().instances[name] and name or bridge.config.first[name]
            local view=id and bridge.runtime and bridge.runtime.views[id]
            if view then return view.module end
        end
        return bridge.original.GetModule(self,name)
    end
    function ybar:ReloadDB()
        bridge:CloseModuleSettings()
        if bridge:InCombat() then
            bridge.reloadPending=true;bridge:BindEvents()
            if bridge.session then bridge.session:Suspend() end
            return
        end
        if bridge.active then
            if bridge.designer then bridge.designer:Hide() end
            bridge.session=nil
            if bridge.runtime then bridge.runtime:Close();bridge.runtime=nil end
            if bridge.signals then bridge.signals:Close() end
            bridge.active=false
        end
        if self.TeleportRestore then self.TeleportRestore:Cancel() end
        if self.BrokerManager then self.BrokerManager:ResetProfile() end
        local raw=bridge:GetRawRoot()
        if raw and raw.version==2 then
            local model,reason=bridge:Prepare(raw)
            if model then return bridge:Activate(model) end
            bridge:Report(reason);return
        end
        bridge.original.ReloadDB(self)
        raw=bridge:GetRawRoot()
        local model,reason=bridge:Prepare(raw)
        if not model then bridge:Report(reason);return false,reason end
        local ok,detail=bridge:Activate(model)
        if ok then self:GetProfile().YBar=model else bridge:Report(detail) end
        return ok,detail
    end
    function ybar:RemoveModuleFromLayout(name)
        if not bridge.active then return bridge.original.RemoveModuleFromLayout(self,name) end
        bridge.config:Refresh()
        local id=bridge:GetModel().instances[name] and name or bridge.config.first[name]
        if not id then return false end
        local _,barId,index=bridge.lib.Model.FindBar(bridge:GetModel(),id)
        if not barId then return false end
        bridge.lastPositions=bridge.lastPositions or {};bridge.lastPositions[id]={barId,index}
        return bridge.lib.Model.Move(bridge:GetModel(),id,nil)
    end
    function ybar:RestoreModuleToLayout(name)
        if not bridge.active then return bridge.original.RestoreModuleToLayout(self,name) end
        bridge:Discover();bridge.config:Refresh()
        local db=bridge:GetModel()
        local id=db.instances[name] and name or bridge.config.first[name]
        if not id then
            id=bridge.lib.Model.Add(db,name,bridge.adapters[name] and bridge.adapters[name].defaultConfig or {},bridge.adapters)
            if not id then return false end
        end
        if self.BrokerManager then self.BrokerManager:PreferEntry(db.instances[id].moduleType) end
        local last=bridge.lastPositions and bridge.lastPositions[id]
        return bridge.lib.Model.Move(db,id,last and db.bars[last[1]] and last[1] or "bottom",last and last[2])
    end
    function ybar:SetSubModuleEnabled(name,enabled)
        if not bridge.active then return bridge.original.SetSubModuleEnabled(self,name,enabled) end
        local changed=enabled and self:RestoreModuleToLayout(name) or not enabled and self:RemoveModuleFromLayout(name)
        if changed then bridge:Changed() end
        return changed
    end
    function ybar:GetModuleDisplayMode(name)
        if not bridge.active then return bridge.original.GetModuleDisplayMode(self,name) end
        if bridge.session then return "ALWAYS" end
        bridge.config:Refresh()
        local db=bridge:GetModel()
        local id=db.instances[name] and name or bridge.config.first[name]
        local inst=id and db.instances[id]
        if inst and inst.visibility then return inst.visibility end
        return bridge.original.GetModuleDisplayMode(self,inst and inst.moduleType or name)
    end
    function ybar:UpdateAppearance()
        if not bridge.active then return bridge.original.UpdateAppearance(self) end
        if bridge.runtime then bridge.runtime:MarkDirty() end
    end
    function ybar:UpdatePosition()
        if not bridge.active then return bridge.original.UpdatePosition(self) end
        if self.frame and not bridge:InCombat() then self.frame:SetShown(self:IsEnabled() or bridge.session~=nil) end
        if bridge.runtime then bridge.runtime:SetEnabled(self:IsEnabled() or bridge.session~=nil) end
    end
    function ybar:OnLifecycleDisable()
        if bridge.session then bridge.session:Discard() end
        bridge.original.OnLifecycleDisable(self)
        if bridge.active and bridge.runtime then bridge.runtime:SetEnabled(false) end
        if not bridge:InCombat() then bridge.yui.Event:OffOwner(bridge);bridge.eventsBound=nil end
    end
    function ybar:OnLifecycleEnable()
        if bridge.active then bridge:BindEvents() end
        return bridge.original.OnLifecycleEnable(self)
    end
    function ybar:Initialize()
        bridge.original.Initialize(self)
        -- EnsureDB installs the v2 facade before CreateBar. Activation is complete
        -- only once the runtime exists; the facade alone cannot display modules.
        if self.frame and (not bridge.active or not bridge.runtime) then
            if bridge:InCombat() then
                bridge.reloadPending=true;bridge:BindEvents()
                return
            end
            local raw=bridge:GetRawRoot()
            local model,reason=bridge:Prepare(raw)
            if model then
                local ok,detail=bridge:Activate(model)
                if ok then self:GetProfile().YBar=model else bridge:Report(detail) end
            else bridge:Report(reason) end
        end
    end
    function ybar:OpenDesigner()return bridge:OpenDesigner()end
    local refreshFeatureSettings=ybar.RefreshFeatureSettings
    function ybar:RefreshFeatureSettings()
        if bridge.session then return bridge:QueueDesignerRefresh(bridge.designer and bridge.designer.selected) end
        if refreshFeatureSettings then return refreshFeatureSettings(self) end
    end
    self.ybar.LayoutDesigner=bridge
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Bridge=Bridge
end
return Bridge
