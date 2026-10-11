-- Designer transaction controller; input and GUI2 lifetime belong to its host.
local Session={}
Session.__index=Session
function Session.New(model,source,revision,host)
    local draft,reason=model.BeginDraft(source,revision)
    if not draft then return nil,reason end
    return setmetatable({model=model,draft=draft,baseline=model.Copy(source),host=host,state="editing"},Session)
end
function Session:IsDirty()return not self.model.Equal(self.baseline,self.draft.value)end
function Session:GetModel() return self.draft.value end
function Session:IsCurrent()
    return self.state~="closed" and self.host.revision()==self.draft.revision
end
function Session:Apply(command,affected)
    if not self:IsCurrent() then return false,"stale-revision" end
    if self.state~="editing" then return false,"designer-suspended" end
    local ok,reason=self.model.ApplyDraft(self.draft,command)
    if ok and reason~="unchanged" and self.host.changed then self.host.changed(affected) end
    return ok,reason
end
-- Legacy GetOptions callbacks may capture nested configuration tables. Execute
-- against the current draft, then checkpoint it, instead of swapping its root
-- before the callback. On failure replace the whole draft with the snapshot.
function Session:Edit(callback,affected)
    if not self:IsCurrent() then return false,"stale-revision" end
    if self.state~="editing" then return false,"designer-suspended" end
    local before=self.model.Copy(self.draft.value)
    local ok,result,reason=pcall(callback)
    local valid,detail=self.model.Validate(self.draft.value)
    if not ok or result==false or not valid then
        self.draft.value=before
        if self.host.changed then self.host.changed(affected) end
        return false,not ok and "command-failed" or not valid and detail or reason
    end
    if self.model.Equal(before,self.draft.value) then return true,"unchanged" end
    self.draft.undo[#self.draft.undo+1]=before
    if #self.draft.undo>self.model.MAX_HISTORY then table.remove(self.draft.undo,1) end
    self.draft.redo={}
    if self.host.changed then self.host.changed(affected) end
    return true
end
function Session:Undo()
    if not self:IsCurrent() or self.state~="editing" then return false end
    if not self.model.UndoDraft(self.draft) then return false end
    if self.host.changed then self.host.changed() end
    return true
end
function Session:Redo()
    if not self:IsCurrent() or self.state~="editing" then return false end
    if not self.model.RedoDraft(self.draft) then return false end
    if self.host.changed then self.host.changed() end
    return true
end
function Session:Suspend()
    if self.state=="closed" then return end
    self.state="suspended"
    if self.host.stopInput then self.host.stopInput() end
end
function Session:Resume()
    if not self:IsCurrent() then return false,"stale-revision" end
    if self.host.inCombat() then return false,"combat" end
    self.state="editing"
    if self.host.changed then self.host.changed() end
    return true
end
function Session:CreatePlacementStorage(barId)
    local session=self
    return {
        identity=function()return session.draft.value end,
        get=function()
            local bar=session.draft.value.bars[barId]
            return bar and bar.placement
        end,
        set=function(_,_,placement)
            return session:Apply(function(db)
                local bar=db.bars[barId]
                if not bar then return false,"missing-bar" end
                bar.placement=session.model.Copy(placement)
            end,barId)
        end,
        clear=function()
            return session:Apply(function(db)
                local bar=db.bars[barId]
                if not bar then return false,"missing-bar" end
                bar.placement=nil
            end,barId)
        end,
    }
end
function Session:Save()
    if self.state~="editing" then return false,"designer-suspended" end
    if self.host.inCombat() then self:Suspend();return false,"combat" end
    local candidate,reason=self.model.ExportDraft(self.draft,self.host.revision())
    if not candidate then return false,reason end
    -- Host validates native capabilities and atomically applies/restores runtime.
    local valid,detail=self.host.validate(candidate)
    if not valid then return false,detail end
    self.state="saving"
    local ok,result,errorCode=pcall(self.host.commit,candidate,self.draft.revision)
    if not ok or result==false then
        self.state="editing"
        return false,ok and errorCode or "commit-failed"
    end
    self.state="closed"
    self.host.close(true)
    return true
end
function Session:Discard()
    if self.state=="closed" then return true end
    if self.host.stopInput then self.host.stopInput() end
    self.state="closed"
    self.host.close(false)
    return true
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Session=Session
end
return Session
