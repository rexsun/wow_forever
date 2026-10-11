-- Read-only migration candidate. Caller supplies verified module config adapters.
-- No SavedVariables writes or automatic activation.
local function NewMigration(Model)
    local Migration = {}
    function Migration.Build(legacy, adapters)
        if type(legacy) ~= "table" then return nil, {"invalid-profile"} end
        if legacy.version == 2 then return nil, {"already-v2"} end
        if not Model.IsSerializable(legacy) then return nil, {"invalid-profile-values"} end
        local db = Model.New({outline=legacy.fontOutline and "OUTLINE" or "NONE", shadow=legacy.fontShadow})
        local report, seen, extracted = {}, {}, {}
        -- Keep all root-level and extension fields until per-module adapters account for them.
        db.legacyRemainder = Model.Copy(legacy)
        for _, barId in ipairs(db.barOrder) do
            local bar = db.bars[barId]
            bar.legacyGeometry = true
            bar.minCrossSize = legacy[barId .. "Height"] or 21
            bar.surface = {preset=Model.IsLegacyEmptyTexture(legacy.texture) and "none" or "legacy", texture=legacy.texture, color=Model.Copy(legacy.bgColor), classColor=legacy.classColor}
            for index, name in ipairs((legacy.modules or {})[barId] or {}) do
                if name ~= "None" then
                    if type(name) ~= "string" then return nil, {"invalid-module-name"} end
                    if seen[name] then return nil, {"duplicate-reference:" .. name} end
                    seen[name] = true
                    local adapter = adapters[name]
                    local key = adapter and adapter.configKey
                    local source = adapter and adapter.read and adapter.read(legacy) or (key and legacy[key])
                    local id = "instance:" .. db.nextInstanceId
                    db.nextInstanceId = db.nextInstanceId + 1
                    db.instanceOrder[#db.instanceOrder+1] = id
                    db.instances[id] = {moduleType=name, config=Model.Copy(source or {}), appearance={},
                        legacyConfigPresent=source ~= nil, legacyItem=Model.Copy((legacy.items or {})[name] or {})}
                    if key then extracted[key] = true end
                    if not adapter then report[#report+1] = "unloaded:" .. name end
                    bar.items[#bar.items+1] = id
                    if (legacy.center or {})[barId] == index then bar.centerInstanceId = id end
                end
            end
        end
        -- Known configured but unplaced modules must survive too.
        local names = {}
        for name in pairs(adapters) do names[#names+1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local key = adapters[name].configKey
            local source = adapters[name].read and adapters[name].read(legacy) or (key and legacy[key])
            if not seen[name] and source ~= nil then
                local id = "instance:" .. db.nextInstanceId
                db.nextInstanceId = db.nextInstanceId + 1
                db.instanceOrder[#db.instanceOrder+1] = id
                db.instances[id] = {moduleType=name, config=Model.Copy(source), appearance={},
                    legacyConfigPresent=true, legacyItem=Model.Copy((legacy.items or {})[name] or {})}
                if key then extracted[key] = true end
            end
        end
        for key in pairs(extracted) do db.legacyRemainder[key] = nil end
        for _, adapter in pairs(adapters) do
            if adapter.remove then adapter.remove(db.legacyRemainder) end
        end
        db.legacyRemainder.modules, db.legacyRemainder.items, db.legacyRemainder.center = nil, nil, nil
        -- Preserve exact original layout fields for inverse verification, not repeated snapshots.
        db.legacyLayout = {modules=Model.Copy(legacy.modules), items=Model.Copy(legacy.items), center=Model.Copy(legacy.center)}
        return Model.NormalizeGeometry(db), report
    end
    function Migration.Restore(db, adapters)
        local legacy = Model.Copy(db.legacyRemainder)
        for key, value in pairs(db.legacyLayout) do legacy[key] = Model.Copy(value) end
        for _, id in ipairs(db.instanceOrder) do
            local inst = db.instances[id]
            local adapter = adapters[inst.moduleType]
            if adapter and inst.legacyConfigPresent then
                local config=Model.Copy(inst.config)
                for key,value in pairs(inst.legacyAppearance or {}) do config[key]=Model.Copy(value) end
                if adapter.write then adapter.write(legacy, config)
                elseif adapter.configKey then legacy[adapter.configKey] = config end
            end
        end
        return legacy
    end
    return Migration
end

local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.MigrationFactory=NewMigration
end
return NewMigration
