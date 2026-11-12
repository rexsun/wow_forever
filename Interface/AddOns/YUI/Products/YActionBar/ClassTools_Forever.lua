local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end

local Tools = { ids = { "aspects", "totems", "mageTools" },
    classes = { HUNTER = "aspects", SHAMAN = "totems", MAGE = "mageTools" },
    classOrder = { "MAGE", "HUNTER", "SHAMAN" }, cache = {} }
YAB.ClassTools = Tools
local OWN_FIELDS = { flyoutDirection = true, aspectOrder = true, aspectActiveStyle = true, showUnlearned = true,
    showPetUtilities = true, mageScroll = true, mageIntellect = true, mageArmor = true,
    mageArmorLeft = true, mageArmorMiddle = true, mageArmorRight = true, mageMissingBuffGlow = true,
    classToolsIndependent = true, classToolsInitialized = true, classToolsDetached = true, label = true }

function Tools:IsClassBar(id)
    return id == "aspects" or id == "totems" or id == "mageTools"
end

function Tools:InitializeDB(db)
    if db.classToolsVersion == 2 then return end
    db.specialBars = db.specialBars or {}
    for _, id in ipairs(self.ids) do
        local config = db.specialBars[id]
        local legacy = type(config) == "table" and id ~= "mageTools"
        config = config or {}
        -- Only the explicit detach control creates an independent toolbar.
        -- Retain old per-class values as dormant settings, not extra bars.
        config.classToolsDetached = config.classToolsDetached == true
        config.classToolsIndependent = config.classToolsDetached
        if config.classToolsInitialized == nil then config.classToolsInitialized = legacy end
        db.specialBars[id] = config
    end
    db.classToolsVersion = 2
end

function Tools:IsIndependent(id, db)
    db = db or YAB:GetDB()
    local config = db.specialBars and db.specialBars[id]
    return config and config.classToolsIndependent == true and config.classToolsDetached == true or false
end

function Tools:HasSharedClasses(db)
    db = db or YAB:GetDB()
    for _, id in ipairs(self.ids) do
        if not self:IsIndependent(id, db) then return true end
    end
    return false
end

function Tools:Invalidate()
    for key in pairs(self.cache) do self.cache[key] = nil end
end

function Tools:GetConfig(id, db)
    db = db or YAB:GetDB()
    local own = db.specialBars and db.specialBars[id]
    if not self:IsClassBar(id) or not own or self:IsIndependent(id, db) then return own end
    if self.db ~= db then self.db = db; self:Invalidate() end
    local compiled = self.cache[id]
    if compiled then return compiled end
    compiled = YAB:CopyValue(db.specialBars.classTools or own)
    for key in pairs(OWN_FIELDS) do compiled[key] = YAB:CopyValue(own[key]) end
    self.cache[id] = compiled
    return compiled
end

function Tools:GetPlayerBarId()
    return self.classes[YAB.SpecialBars:GetPlayerClassToken()]
end

function Tools:GetPreviewBarId(id, db)
    if id ~= "classTools" then return id end
    db = db or YAB:GetDB()
    local preferred, player = self.classes[self.previewClass], self:GetPlayerBarId()
    if preferred and not self:IsIndependent(preferred, db) then return preferred end
    if player and not self:IsIndependent(player, db) then return player end
    for _, class in ipairs(self.classOrder) do
        local candidate = self.classes[class]
        if not self:IsIndependent(candidate, db) then return candidate end
    end
    return preferred or player or "mageTools"
end

function Tools:GetPreviewConfig(id, db)
    return self:GetConfig(self:GetPreviewBarId(id, db), db)
end

function Tools:GetSettingsBarId(id, db)
    db = db or YAB:GetDB()
    if not self:IsClassBar(id) then return id end
    return self:IsIndependent(id, db) and id or "classTools"
end

function Tools:GetLayoutId(id, db)
    return "yactionbar." .. self:GetSettingsBarId(id, db)
end

function Tools:SetIndependent(id, independent)
    if not self:IsClassBar(id) or YAB.Adapter:InCombat() then return false end
    local db = YAB:GetDB()
    local own = db.specialBars[id]
    independent = independent == true
    if self:IsIndependent(id, db) == independent then return true end
    if independent and not own.classToolsInitialized then
        for key, value in pairs(db.specialBars.classTools) do
            if not OWN_FIELDS[key] then own[key] = YAB:CopyValue(value) end
        end
        own.classToolsInitialized = true
        if YAB.ConfigSets and YAB.ConfigSets.CopyClassToolsPlacement then
            YAB.ConfigSets:CopyClassToolsPlacement("yactionbar.classTools", "yactionbar." .. id)
        end
    end
    own.classToolsIndependent = independent
    own.classToolsDetached = independent
    self:Invalidate()
    local record = YAB.BarManager and YAB.BarManager.bars[id]
    if record and YAB.LayoutBridge and YAB.ClassBars.active[id] then
        YAB.LayoutBridge:Register(id, record, nil, self:GetConfig(id, db))
    end
    if YAB.ClassBars then YAB.ClassBars:SyncEnabled() end
    if YAB.ConfigSets then YAB.ConfigSets:SaveActive("class-tools-mode", self) end
    return true
end

function Tools:SelectClass(class, db)
    local id = self.classes[class]
    if not id then return nil end
    self.previewClass = class
    return self:GetSettingsBarId(id, db)
end

function Tools:GetSettingsOrder(order, db)
    local result = {}
    for _, id in ipairs(order) do
        if id == "classTools" then
            if self:HasSharedClasses(db) then result[#result + 1] = id end
        elseif not self:IsClassBar(id) or self:IsIndependent(id, db) then
            result[#result + 1] = id
        end
    end
    return result
end
