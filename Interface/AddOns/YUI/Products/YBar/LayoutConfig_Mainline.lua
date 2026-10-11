-- Legacy module accessors resolve into one canonical instance configuration.
-- Facades are runtime-only and never assigned to a saved profile.
local Config={}
Config.__index=Config
function Config.New(model,context,adapters,getModel)
    local self=setmetatable({model=model,context=context,adapters=adapters,getModel=getModel,
        contexts={},first={}},Config)
    self.root=setmetatable({}, {
        __index=function(_,key)return self:Read(key)end,
        __newindex=function(_,key,value)return self:Write(key,value)end,
    })
    self.brokerEntries=setmetatable({}, {
        __newindex=function(entries,name,value)
            local kind="Broker:"..name
            if not self.adapters[kind] then error("unregistered-broker-config") end
            local context=self:GetContext(self:EnsureInstance(kind))
            if value~=context.config then self.getModel().instances[context.id].config=self.model.Copy(value) end
            rawset(entries,name,context.config)
        end,
    })
    self.brokerRoot=setmetatable({}, {
        __index=function(_,key)
            if key=="entries" then self:Refresh();return self.brokerEntries end
            local db=self.getModel().legacyRemainder or {}
            return db.DataBroker and db.DataBroker[key]
        end,
        __newindex=function(_,key,value)
            if key=="entries" and value==self.brokerEntries then return end
            if key=="entries" then error("broker-entry-replacement") end
            local root=self.getModel().legacyRemainder
            root.DataBroker=root.DataBroker or {};root.DataBroker[key]=value
        end,
    })
    return self
end
function Config:Refresh()
    local db=self.getModel()
    if self.indexed==db then return end
    self.indexed=db
    for key in pairs(self.first) do self.first[key]=nil end
    for key in pairs(self.brokerEntries) do rawset(self.brokerEntries,key,nil) end
    for _,id in ipairs(db.instanceOrder) do
        local inst=db.instances[id]
        self.first[inst.moduleType]=self.first[inst.moduleType] or id
        local adapter=self.adapters[inst.moduleType]
        if adapter and adapter.brokerName then
            rawset(self.brokerEntries,adapter.brokerName,self:GetContext(id).config)
        end
    end
end
function Config:GetContext(id)
    local inst=self.getModel().instances[id]
    if not inst then return nil end
    if self.contexts[id] and self.contexts[id].moduleType~=inst.moduleType then self.contexts[id]=nil end
    if not self.contexts[id] then
        local adapter=self.adapters[inst.moduleType] or {}
        self.contexts[id]=self.context.New(self.model,self.getModel,id,adapter.configKey or inst.moduleType,
            function()return self.getModel().legacyRemainder or {}end,adapter.fields)
        self.contexts[id].moduleType=inst.moduleType
    end
    return self.contexts[id]
end
function Config:EnsureInstance(kind)
    self:Refresh()
    if self.first[kind] then return self.first[kind] end
    local id,reason=self.model.Add(self.getModel(),kind,self.adapters[kind] and self.adapters[kind].defaultConfig or {},self.adapters)
    assert(id,reason)
    self.indexed=nil;self:Refresh()
    return id
end
function Config:GetModuleRoot(kind)
    local adapter=self.adapters[kind]
    if not adapter then return self.root end
    return self:GetContext(self:EnsureInstance(kind)):GetRoot()
end
function Config:Read(key)
    local db=self.getModel()
    if key=="version" then return 2 end
    if key=="DataBroker" then return self.brokerRoot end
    if self.adapters[key] then return self:GetContext(self:EnsureInstance(key)).config end
    if key=="fontOutline" then
        local value=db.defaults.outline
        if value~=nil then return value~="NONE" and value~="" and value~=false end
    elseif key=="fontShadow" and db.defaults.shadow~=nil then return db.defaults.shadow end
    return db.legacyRemainder and db.legacyRemainder[key]
end
function Config:Write(key,value)
    if key=="DataBroker" and value==self.brokerRoot then return end
    if self.adapters[key] then
        local id=self:EnsureInstance(key)
        if value~=self:GetContext(id).config then
            assert(type(value)=="table","invalid-module-config")
            self.getModel().instances[id].config=self.model.Copy(value)
        end
        return
    end
    local db=self.getModel()
    db.legacyRemainder=db.legacyRemainder or {}
    db.legacyRemainder[key]=value
end
function Config:Invalidate()
    self.indexed=nil
    local instances=self.getModel().instances
    for id in pairs(self.contexts) do if not instances[id] then self.contexts[id]=nil end end
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Config=Config
end
return Config
