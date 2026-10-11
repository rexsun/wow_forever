local YUI = _G.YUI
local YBar = YUI.YBar
local Info, L = YBar.InfoModule, YUI.Locale:Get("YBar")
local LDB = LibStub("LibDataBroker-1.1")
local Manager = YBar.Module:New("DataBroker")
Manager.settingsOnly = true
Manager.entries = {}
YBar.BrokerManager = Manager
YBar:RegisterModule(Manager)

local function Config(name)
    local db = Info.DB(Manager)
    db.entries = db.entries or {}
    db.entries[name] = db.entries[name] or {}
    return db.entries[name]
end
local function Supported(object)
    return object and (object.type == "data source" or object.type == "launcher")
end
local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
local function Text(object, name)
    local text = Public(object.text)
    if text ~= nil and text ~= "" then return tostring(text) end
    local value, suffix = Public(object.value), Public(object.suffix)
    if value ~= nil then return tostring(value) .. (suffix and tostring(suffix) or "") end
    return Public(object.label) or name
end

function Manager:Register(name, object)
    if self.entries[name] then self.entries[name].provider = Supported(object) and object or nil; return end
    local entry = YBar.Module:New("Broker:" .. name)
    entry.brokerName, entry.displayName = name, name
    entry.provider = Supported(object) and object or nil
    entry.CreateBarItem = Info.Create
    function entry:GetSettingsIcon()
        local icon = self.provider and Public(self.provider.icon)
        return (type(icon) == "number" or type(icon) == "string") and icon or 134400
    end
    function entry:GetDisplayDB() return Config(self.brokerName) end
    function entry:GetOptions()
        local options=Info.Options(self)
        options[#options+1]={type="row",gap=12,children={
            {type="checkbox",label=L["broker.custom_text"],width=160,
                get=function()return self:GetDisplayDB().customTextEnabled==true end,
                set=function(v)self:GetDisplayDB().customTextEnabled=v==true;self:UpdateBarItem()end},
            {type="editbox",width=220,
                tooltip=L["broker.custom_text_value"],
                hidden=function()return self:GetDisplayDB().customTextEnabled~=true end,
                get=function()return self:GetDisplayDB().customText or "" end,
                set=function(v)self:GetDisplayDB().customText=v or "";self:UpdateBarItem()end},
        }}
        return options
    end
    function entry:GetWidth() return self.width or 40 end
    function entry:IsBarItemRenderable()
        return self.provider ~= nil and not self.failed and not (self.brokerName == "BugSack" and YBar:IsModuleOnBar("BugSack"))
    end
    function entry:UpdateBarItem()
        if not self:IsBarItemRenderable() then return end
        local icon = Public(self.provider.icon)
        if type(icon) ~= "number" and type(icon) ~= "string" then icon = nil end
        local db=self:GetDisplayDB()
        local text
        if db.customTextEnabled==true then text=type(db.customText)=="string" and db.customText or ""
        else text=Text(self.provider,self.brokerName) end
        Info.Display(self,text,icon)
        if self.frame and self.provider.iconCoords then
            local c = self.provider.iconCoords
            if type(c) == "table" and #c == 4 then self.frame.icon:SetTexCoord(unpack(c)) end
        end
    end
    function entry:Call(key, ...)
        if self.failed or not self.provider or type(self.provider[key]) ~= "function" then return end
        local ok, err = pcall(self.provider[key], ...)
        if not ok then
            self.failed = true
            self:DetachRuntime()
            YBar:UpdateLayout()
            geterrorhandler()(tostring(err))
        end
    end
    function entry:OnClick(frame, button) self:Call("OnClick", frame, button) end
    function entry:OnEnter(frame)
        if not self.provider then return end
        self.hovered = true
        if self.provider.OnEnter then self:Call("OnEnter", frame)
        elseif self.provider.OnTooltipShow then
            Info.Tooltip(self, self.brokerName)
            GameTooltip:ClearLines()
            self:Call("OnTooltipShow", GameTooltip)
            if not self.failed then GameTooltip:Show() end
        end
    end
    function entry:OnLeave(frame)
        if self.hovered then
            self.hovered = nil
            self:Call("OnLeave", frame)
        end
        if GameTooltip:GetOwner() == frame then YUI.HideGameTooltip() end
    end
    function entry:AttributeChanged(_, _, attribute)
        if attribute == "text" or attribute == "value" or attribute == "suffix" or attribute == "label"
            or attribute == "icon" or attribute == "iconCoords" then
            Manager.dirty[self] = true
            Manager:Queue()
        end
    end
    function entry:AttachRuntime()
        if self.active or not self.frame or not self:IsBarItemRenderable() then return end
        self.active = true
        LDB.RegisterCallback(self, "LibDataBroker_AttributeChanged_" .. self.brokerName, "AttributeChanged")
        if self.frame then
            self.frame:EnableMouseWheel(true)
            self.frame:SetScript("OnMouseWheel", function(f, delta) self:Call("OnMouseWheel", f, delta) end)
        end
        self:UpdateBarItem()
    end
    function entry:DetachRuntime()
        if self.active then LDB.UnregisterCallback(self, "LibDataBroker_AttributeChanged_" .. self.brokerName) end
        self.active = false
        Manager.dirty[self] = nil
        if self.frame then
            if self.hovered then
                self.hovered = nil
                if self.provider and type(self.provider.OnLeave) == "function" then pcall(self.provider.OnLeave, self.frame) end
            end
            if GameTooltip:GetOwner() == self.frame then YUI.HideGameTooltip() end
            self.frame:Hide()
        end
    end
    function entry:OnDBReload() self:DetachRuntime(); self.failed = nil end
    self.entries[name] = entry
    local id = name:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)
    YBar:RegisterModule(entry, {id = "ybar.broker." .. id, parent="ybar", product="ybar", scope="ybar", dependencies={"ybar"}})
end

Manager.dirty = {}
function Manager:Flush()
    self.timer = nil
    for entry in pairs(self.dirty) do
        self.dirty[entry] = nil
        if entry.active then
            local ok, err = pcall(entry.UpdateBarItem, entry)
            if not ok then
                entry.failed = true
                entry:DetachRuntime()
                YBar:UpdateLayout()
                geterrorhandler()(tostring(err))
            end
        end
    end
end
local function Flush() Manager:Flush() end
function Manager:Queue()
    if not self.timer then self.timer = C_Timer.NewTimer(0, Flush) end
end
function Manager:Created(_, name, object)
    if not Supported(object) then return end
    self:Register(name, object)
    YBar:UpdateLayout()
end
function Manager:Sync()
    local active = YBar:IsEnabled() or self.settingsVisible
    if active and not self.active then
        self.active = true
        local db = Info.DB(self)
        for name in pairs(db.entries or {}) do self:Register(name, LDB:GetDataObjectByName(name)) end
        for name, object in LDB:DataObjectIterator() do if Supported(object) then self:Register(name, object) end end
        LDB.RegisterCallback(self, "LibDataBroker_DataObjectCreated", "Created")
        YBar:UpdateLayout()
    elseif not active and self.active then
        self.active = false
        LDB.UnregisterCallback(self, "LibDataBroker_DataObjectCreated")
        if self.timer then self.timer:Cancel(); self.timer = nil end
        for _, entry in pairs(self.entries) do entry:DetachRuntime() end
    end
end

function Manager:OnSettingsEnter() self.settingsVisible = true; self:Sync() end
function Manager:OnSettingsLeave() self.settingsVisible = false; self:Sync() end

function Manager:ResetProfile()
    if self.active then LDB.UnregisterCallback(self, "LibDataBroker_DataObjectCreated") end
    self.active = false
    if self.timer then self.timer:Cancel(); self.timer = nil end
    for _, entry in pairs(self.entries) do entry:DetachRuntime(); entry.failed = nil end
end

function Manager:PreferEntry(name)
    local other
    if name == "Broker:BugSack" then other = "BugSack"
    elseif name == "BugSack" then other = "Broker:BugSack" end
    if other and YBar:IsModuleOnBar(other) then
        YBar:RemoveModuleFromLayout(other)
        YUI:Print(L["broker.entry_switch"])
    end
end

function Manager:SelectPlacement(entry, placement)
    local designer=YBar.LayoutDesigner
    if designer and designer.active then
        designer:Discover();designer.config:Refresh()
        local db=designer:GetModel()
        local id=designer.config.first[entry.name] or designer.lib.Model.Add(db,entry.name,{},designer.adapters)
        if not id then return false end
        if placement~="none" then self:PreferEntry(entry.name) end
        designer.lib.Model.Move(db,id,placement~="none" and placement or nil)
        entry.failed=nil;designer:Changed(id)
        return true
    end
    local root = YBar:EnsureDB()
    YBar:RemoveModuleFromLayout(entry.name)
    if placement ~= "none" then
        self:PreferEntry(entry.name)
        local list = root.modules[placement]
        local index
        for i, value in ipairs(list) do if value == "None" then index = i; break end end
        list[index or #list + 1] = entry.name
        Config(entry.brokerName)
        entry.failed = nil
    end
    YBar:SyncModuleLifecycles()
    YBar:UpdateLayout()
end

function Manager:GetOptions()
    -- A settings visit refreshes discovery even when the information bar is disabled.
    for name, object in LDB:DataObjectIterator() do if Supported(object) then self:Register(name, object) end end
    local function choices()
    local result = {}
    for name, entry in pairs(self.entries) do
        if not self.search or name:lower():find(self.search:lower(), 1, true) then
            result[#result + 1] = {text = name .. (not entry.provider and (" — " .. L["broker.unloaded"]) or ""), value = name, icon = entry:GetSettingsIcon()}
        end
    end
    table.sort(result, function(a,b) return a.value < b.value end)
    return result
    end
    local initial = choices()
    self.selected = self.selected or (initial[1] and initial[1].value)
    local function refresh() if YBar.RefreshFeatureSettings then YBar:RefreshFeatureSettings() end end
    local options = {
        {type="divider", label=L["feature.contents"], width=400, alignLeft=true},
        {type="editbox", label=L["feature.search"], width=220, get=function() return self.search or "" end,
            set=function(v) self.search=v end},
        {type="dropdown", label=L["broker.component"], width=220, options=choices,
            get=function() return self.selected end, set=function(v) if self.selected==v then return end; self.selected=v; refresh() end},
    }
    local entry = self.entries[self.selected]
    if entry then
        for _, option in ipairs(Info.Options(entry)) do options[#options+1]=option end
    end
    options[#options+1]={type="text",label=L["broker.help"],width=400}
    return options
end
