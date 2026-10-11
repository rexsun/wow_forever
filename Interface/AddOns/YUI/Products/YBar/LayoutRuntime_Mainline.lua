-- View lifetime and geometry application. Platform operations are supplied by YBar.
local Runtime = {}
Runtime.__index = Runtime
local function Number(value)
    return type(value)=="number" and value==value and value>=0 and value<math.huge
end
function Runtime.New(model, geometry, platform)
    return setmetatable({model=model,geometry=geometry,platform=platform,views={},bars={},
        dirty={},measurements={},applied={},failures={},enabled=false},Runtime)
end
function Runtime:GetModel() return self.platform.getModel() end
function Runtime:Fail(id, reason)
    self.failures[id]=true
    local view=self.views[id]
    if view then
        view.failed=true
        pcall(self.platform.disableView,view)
        view.active=false
    end
    self.measurements[id]=nil
    if self.platform.report then pcall(self.platform.report,reason,id) end
end
function Runtime:MarkDirty(id)
    if self.closed then return end
    local db=self:GetModel()
    if id and db.instances[id] then
        local _,barId=self.model.FindBar(db,id)
        if barId then self.dirty[barId]=true end
    elseif id and db.bars[id] then self.dirty[id]=true
    else for _,barId in ipairs(db.barOrder) do self.dirty[barId]=true end end
    if self.flushing or self.pending or not self.enabled or self.platform.inCombat() then return end
    self.pending=self.platform.schedule(function()
        self.pending=nil
        if not self.closed then self:Flush() end
    end)
end
function Runtime:Reconcile(affected)
    if self.closed then return false,"closed" end
    if self.reconciling then return false,"reconciling" end
    if self.platform.inCombat() then self.reconcilePending=true;return false,"combat" end
    local db=self:GetModel()
    local valid,reason=self.model.Validate(db)
    if not valid then return false,reason end
    self.reconciling=true
    self.reconcilePending=nil
    local completed, failure=pcall(self.ReconcileViews,self,db,affected)
    self.reconciling=false
    if not completed then
        self.fatalFailure="reconcile-failed"
        if self.platform.report then pcall(self.platform.report,failure,"reconcile") end
        return false,"reconcile-failed"
    end
    self:MarkDirty()
    return true
end
function Runtime:ReconcileViews(db,affected)
    for id in pairs(self.failures) do if not db.instances[id] then self.failures[id]=nil end end
    for id,view in pairs(self.views) do
        local inst=db.instances[id]
        if not inst or view.moduleType~=inst.moduleType then
            self.platform.disableView(view)
            self.platform.releaseView(view)
            self.views[id],self.measurements[id],self.applied[id]=nil,nil,nil
        end
    end
    for id,bar in pairs(self.bars) do
        if not db.bars[id] then
            self.platform.releaseBar(id,bar)
            self.bars[id],self.dirty[id]=nil,nil
        end
    end
    for _,barId in ipairs(db.barOrder) do
        if not self.bars[barId] then self.bars[barId]=self.platform.createBar(barId,db.bars[barId]) end
    end
    for _,id in ipairs(db.instanceOrder) do
        local inst=db.instances[id]
        local view=self.views[id]
        local bar,barId=self.model.FindBar(db,id)
        local designing=self.platform.isDesign and self.platform.isDesign()
        local needed=self.enabled and bar and (bar.enabled~=false or designing)
        if needed and not view and not self.failures[id] then
            local ok,result=pcall(self.platform.createView,id,inst)
            if ok and result then
                view=result;view.moduleType=inst.moduleType;self.views[id]=view
            elseif not ok then self:Fail(id,result) end
        end
        if view then
            if needed and not view.failed then
                local ok,errorCode=pcall(function()
                    local refresh=affected==nil or affected==id or affected==barId or not view.active
                    if view.barId~=barId then
                        self.platform.mountView(view,self.bars[barId])
                        view.barId=barId;self.applied[id]=nil
                    end
                    if not view.active then self.platform.enableView(view);view.active=true end
                    if refresh then self.platform.refreshView(view) end
                end)
                if not ok then self:Fail(id,errorCode) end
            elseif view.active then
                self.platform.disableView(view);view.active=false
                self.applied[id]=nil
            end
        end
    end
end
function Runtime:FlushBar(db,barId)
    local config,host=db.bars[barId],self.bars[barId]
    if not config or not host then return end
    local designing=self.platform.isDesign and self.platform.isDesign()
    local enabled=self.enabled and (config.enabled~=false or designing)
    self.platform.showBar(host,enabled)
    if not enabled then return end
    local maximumCross=0
    for _,id in ipairs(config.items) do
        local view=self.views[id]
        if view and view.active and not view.failed then
            local ok,width,height,visible=pcall(self.platform.measureView,view)
            if ok and Number(width) and Number(height) then
                local measure=self.measurements[id] or {}
                self.measurements[id]=measure
                measure.width,measure.height,measure.renderable=width,height,visible~=false
                if visible~=false then maximumCross=math.max(maximumCross,height) end
            else self:Fail(id,ok and "invalid-view-measurement" or width) end
        else self.measurements[id]=nil end
    end
    local input=config
    if config.kind~="independent" then
        input=setmetatable({sizing="fixed",length=self.platform.availableLength(barId,config)},{__index=config})
    end
    local result=self.geometry.Flow(input,db.instances,self.measurements)
    local vertical=config.orientation=="vertical"
    if designing and #config.items==0 then
        result.length=math.max(result.length,160);result.crossSize=math.max(result.crossSize,24)
    end
    local visibleItems,hidden=self.geometry.Visible(result,config,self.measurements)
    if #hidden>0 and self.platform.overflowWidth then
        visibleItems,hidden=self.geometry.Visible(result,config,self.measurements,math.max(0,result.length-self.platform.overflowWidth))
    end
    result.overflow=result.overflow or #hidden>0
    self.platform.sizeBar(host,vertical and result.crossSize or result.length,
        vertical and result.length or result.crossSize,result.overflow)
    if self.platform.overflow then self.platform.overflow(host,hidden,vertical) end
    for _,id in ipairs(config.items) do
        local view,measure=self.views[id],self.measurements[id]
        if view and view.active and measure then
            local position=result.positions[id]
            local visible=visibleItems[id]==true
            local previous=self.applied[id]
            local cross=vertical and measure.width or measure.height
            local x=vertical and (result.crossSize-cross)/2 or position
            local y=vertical and position or self.geometry.VerticalPosition(config,db.instances[id],measure.height,result.crossSize)
            if not previous or previous.visible~=visible or previous.x~=x or previous.y~=y
                or previous.width~=measure.width or previous.height~=measure.height then
                self.platform.placeView(view,x or 0,y or 0,measure.width,measure.height,visible)
                previous=previous or {};self.applied[id]=previous
                previous.x,previous.y,previous.visible=x,y,visible
                previous.width,previous.height=measure.width,measure.height
            end
        end
    end
end
function Runtime:Flush()
    if self.closed or not self.enabled or self.reconciling then return end
    if self.platform.inCombat() then return end
    if self.pending then self.pending:Cancel();self.pending=nil end
    self.flushing=true
    local db=self:GetModel()
    for barId in pairs(self.dirty) do if not db.bars[barId] then self.dirty[barId]=nil end end
    for _,barId in ipairs(db.barOrder) do
        if self.dirty[barId] then
            self.dirty[barId]=nil
            local ok,reason=pcall(self.FlushBar,self,db,barId)
            if not ok then
                self.fatalFailure="bar-layout-failed"
                if self.platform.report then pcall(self.platform.report,reason,barId) end
            end
        end
    end
    self.flushing=false
    if self.platform.afterFlush then self.platform.afterFlush() end
    if next(self.dirty) then self:MarkDirty(next(self.dirty)) end
end
function Runtime:SetEnabled(enabled)
    if self.closed then return end
    self.enabled=enabled==true
    if self.enabled then return self:Reconcile() end
    if self.pending then self.pending:Cancel();self.pending=nil end
    for id,view in pairs(self.views) do
        if view.active then self.platform.disableView(view);view.active=false end
        self.applied[id]=nil
    end
    for _,bar in pairs(self.bars) do self.platform.showBar(bar,false) end
end
function Runtime:OnCombatEnded()
    if self.closed then return end
    if self.closePending then return self:Close() end
    if self.reconcilePending then self:Reconcile() end
    self:Flush()
end
function Runtime:Close()
    self:SetEnabled(false)
    if self.platform.inCombat() then self.closePending=true;return false,"combat" end
    for _,view in pairs(self.views) do self.platform.releaseView(view) end
    for id,bar in pairs(self.bars) do self.platform.releaseBar(id,bar) end
    self.views,self.bars,self.measurements,self.applied,self.dirty={},{},{},{},{}
    self.closed=true
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Runtime=Runtime
end
return Runtime
