-- Pure configuration model. No frames, events, DB migration or runtime activation.
local Model = {}
Model.MAX_HISTORY = 50
Model.MAX_BARS = 32
Model.MAX_INSTANCES = 128
local function Finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function Dense(values, maximum)
    if type(values) ~= "table" then return false end
    local count = 0
    for index in pairs(values) do
        if not Finite(index) or index < 1 or index % 1 ~= 0 then return false end
        count = count + 1
    end
    if count > maximum then return false end
    for i = 1, count do if values[i] == nil then return false end end
    return true
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- Validate before copying imported/draft data: no cycles or runtime objects.
local function Serializable(value, ancestors, depth, budget)
    local kind = type(value)
    if kind == "number" then return Finite(value) end
    if kind ~= "table" then return kind == "string" or kind == "boolean" or kind == "nil" end
    if depth > 24 or ancestors[value] or getmetatable(value) ~= nil then return false end
    ancestors[value] = true
    for k, v in pairs(value) do
        budget.count = budget.count + 1
        if budget.count > 100000 or (type(k) ~= "string" and not Finite(k))
            or not Serializable(v, ancestors, depth + 1, budget) then
            ancestors[value] = nil
            return false
        end
    end
    ancestors[value] = nil
    return true
end
function Model.IsSerializable(value) return Serializable(value, {}, 0, {count=0}) end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = Copy(v) end
    return result
end
Model.Copy = Copy
Model.Equal = Equal
function Model.New(defaults)
    defaults=Copy(defaults or {})
    if defaults.display==nil then defaults.display="both" end
    return { version = 2, surfaceMigrationVersion = 1, nextInstanceId = 1, barOrder = {"top", "bottom"},
        defaults = defaults, instances = {}, instanceOrder = {},
        bars = { top = {kind="top", items={}, appearance={}},
            bottom = {kind="bottom", items={}, appearance={}} } }
end
-- One-time data conversion; never called by measurement or layout hot paths.
function Model.NormalizeGeometry(db)
    if db.geometryVersion==1 then return db end
    for _,barId in ipairs(db.barOrder) do
        local bar=db.bars[barId]
        if bar.legacyGeometry then
            bar.allowOverlap=true
            bar.reserveCenter=false
            for _,id in ipairs(bar.items) do
                local inst=db.instances[id]
                local old=inst.legacyItem or {}
                inst.alignment=inst.alignment or old.align or "LEFT"
                inst.anchorGap=old.margin or 2
            end
        end
        bar.legacyGeometry=nil
    end
    for _,id in ipairs(db.instanceOrder) do
        local inst=db.instances[id]
        if inst.legacyItem then inst.alignment=inst.alignment or inst.legacyItem.align;inst.legacyItem=nil end
    end
    db.geometryVersion=1
    return db
end
function Model.FindBar(db, id)
    for _, barId in ipairs(db.barOrder) do
        local bar = db.bars[barId]
        for index, itemId in ipairs(bar.items) do
            if itemId == id then return bar, barId, index end
        end
    end
end
function Model.Add(db, moduleType, config, capabilities)
    local cap = capabilities[moduleType]
    if not cap then return nil, "unknown-module" end
    if #db.instanceOrder >= Model.MAX_INSTANCES then return nil, "instance-limit" end
    if not cap.multi then
        for _, id in ipairs(db.instanceOrder) do
            if db.instances[id].moduleType == moduleType then return nil, "singleton-exists" end
        end
    end
    local id = "instance:" .. db.nextInstanceId
    db.nextInstanceId = db.nextInstanceId + 1
    db.instances[id] = {moduleType=moduleType, config=Copy(config or {}), appearance={}}
    db.instanceOrder[#db.instanceOrder + 1] = id
    return id
end
function Model.AddBar(db, name)
    if #db.barOrder >= Model.MAX_BARS then return nil, "bar-limit" end
    local serial = db.nextBarId or 1
    while db.bars["bar:" .. serial] do serial = serial + 1 end
    local id = "bar:" .. serial
    db.nextBarId = serial + 1
    db.bars[id] = {kind="independent", name=name, items={}, appearance={},
        orientation="horizontal", sizing="auto", spacing=10, minCrossSize=21,
        padding={before=4,after=4,crossBefore=2,crossAfter=2},
        placement={anchor={point="CENTER",relative="UIParent",relativePoint="CENTER"},offset={x=0,y=0}},
        surface={preset="none"}}
    db.barOrder[#db.barOrder+1] = id
    return id
end
function Model.Move(db, id, destination, index)
    if index ~= nil and (type(index) ~= "number" or index ~= index or index == math.huge or index == -math.huge or index % 1 ~= 0) then
        return false, "invalid-index"
    end
    if not db.instances[id] then return false, "missing-instance" end
    if destination and not db.bars[destination] then return false, "missing-bar" end
    local old, oldId, oldIndex = Model.FindBar(db, id)
    if old then
        table.remove(old.items, oldIndex)
        if oldId ~= destination and old.centerInstanceId == id then old.centerInstanceId = nil end
    end
    if destination then
        local items = db.bars[destination].items
        table.insert(items, math.max(1, math.min(index or #items + 1, #items + 1)), id)
    end
    return true
end
-- Alignment is independent of ordering; center remains a single explicit anchor.
function Model.Align(db, id, alignment)
    local bar = Model.FindBar(db, id)
    if not bar or (alignment ~= "LEFT" and alignment ~= "CENTER" and alignment ~= "RIGHT") then return false end
    -- Changing direction must not replace the bar geometry or its spacing.
    local instance=db.instances[id]
    local current=bar.centerInstanceId==id and "CENTER" or instance.alignment
    if not current then
        current="LEFT"
        if bar.centerInstanceId then
            local _,_,index=Model.FindBar(db,id)
            local _,_,centerIndex=Model.FindBar(db,bar.centerInstanceId)
            if centerIndex and index>centerIndex then current="RIGHT" end
        end
    end
    if current==alignment then return true end
    if alignment=="CENTER" and bar.centerInstanceId and bar.centerInstanceId~=id then
        local _,_,oldIndex=Model.FindBar(db,bar.centerInstanceId)
        local _,_,newIndex=Model.FindBar(db,id)
        if oldIndex and newIndex then
            -- Reconnect the displaced center and intervening chain to the new anchor.
            local direction=oldIndex<newIndex and "RIGHT" or "LEFT"
            for index=math.min(oldIndex,newIndex),math.max(oldIndex,newIndex)do
                local other=bar.items[index]
                if other~=id then db.instances[other].alignment=direction end
            end
        end
    end
    if bar.centerInstanceId == id then bar.centerInstanceId = nil end
    if alignment == "CENTER" then bar.centerInstanceId = id; db.instances[id].alignment = nil
    else db.instances[id].alignment = alignment end
    return true
end
function Model.DeleteInstance(db, id)
    if not db.instances[id] then return false end
    Model.Move(db, id, nil)
    db.instances[id] = nil
    for index, value in ipairs(db.instanceOrder) do
        if value == id then table.remove(db.instanceOrder, index); break end
    end
    return true
end
-- The old default was a transparent LSM texture, without a separate border.
function Model.IsLegacyEmptyTexture(texture)
    if texture==nil then return true end
    if type(texture)~="string" then return false end
    local name=texture:gsub("|[cC]%x%x%x%x%x%x%x%x",""):gsub("|[rR]",""):match("^%s*(.-)%s*$")
    return name=="" or name=="None" or name=="YUI None"
end
function Model.NormalizeLegacySurface(db)
    if db.surfaceMigrationVersion==1 then return db end
    local result=Model.Copy(db)
    for _,bar in pairs(result.bars) do
        local surface=bar.surface
        if surface and surface.preset=="legacy" and surface.borderColor==nil
            and Model.IsLegacyEmptyTexture(surface.texture) then
            surface.preset="none"
        end
    end
    result.surfaceMigrationVersion=1
    return result
end
function Model.NormalizeDisplayPreferences(db)
    if db.displayPreferencesVersion==1 then return db end
    db=Model.Copy(db)
    db.defaults.display="both"
    for _,bar in pairs(db.bars)do bar.appearance.display="both" end
    local keep
    for _,id in ipairs(db.bars.top and db.bars.top.items or {})do
        if db.instances[id].moduleType=="SeasonCrests" then keep=id;break end
    end
    if not keep then
        for _,id in ipairs(db.instanceOrder)do if db.instances[id].moduleType=="SeasonCrests" then keep=id;break end end
    end
    for index=#db.instanceOrder,1,-1 do
        local id=db.instanceOrder[index]
        if id~=keep and db.instances[id].moduleType=="SeasonCrests" then Model.DeleteInstance(db,id) end
    end
    db.displayPreferencesVersion=1
    return db
end
function Model.DeleteBar(db, barId)
    local bar = db.bars[barId]
    if not bar then return false, "missing-bar" end
    if bar.kind ~= "independent" then return false, "fixed-bar" end
    db.bars[barId] = nil
    for index, id in ipairs(db.barOrder) do
        if id == barId then table.remove(db.barOrder, index); break end
    end
    return true -- Instances and all original config remain unplaced.
end
function Model.Ordinal(db, id)
    local instance = db.instances[id]
    if not instance then return nil end
    local ordinal = 0
    for _, candidate in ipairs(db.instanceOrder) do
        if db.instances[candidate].moduleType == instance.moduleType then ordinal = ordinal + 1 end
        if candidate == id then return ordinal end
    end
end
function Model.Resolve(db, id, key)
    local instance = db.instances[id]
    if not instance then return nil, "missing-instance" end
    if instance.appearance[key] ~= nil then return instance.appearance[key], "instance" end
    local bar = Model.FindBar(db, id)
    if bar and bar.appearance[key] ~= nil then return bar.appearance[key], "bar" end
    return db.defaults[key], "global"
end
function Model.Sync(db, source, targets, keys, mode, capabilities)
    if not db.instances[source] then return false, "missing-source" end
    if mode ~= "copy" and mode ~= "inherit" then return false, "invalid-mode" end
    local values = {}
    local sourceCap = capabilities[db.instances[source].moduleType]
    for _, key in ipairs(keys) do
        if not sourceCap or not sourceCap.appearance or not sourceCap.appearance[key] then
            return false, "unsupported-source-key"
        end
        values[key] = Copy(Model.Resolve(db, source, key))
    end
    for _, id in ipairs(targets) do
        if not db.instances[id] then return false, "missing-target" end
    end
    local skipped = 0
    for _, id in ipairs(targets) do
        if id ~= source then
            local instance = db.instances[id]
            local cap = capabilities[instance.moduleType]
            for _, key in ipairs(keys) do
                local allowed=cap and cap.values and cap.values[key]
                if cap and cap.appearance and cap.appearance[key] and (mode=="inherit" or not allowed or allowed[values[key]]) then
                    if mode == "inherit" then instance.appearance[key] = nil
                    else instance.appearance[key] = Copy(values[key]) end
                else skipped = skipped + 1 end
            end
        end
    end
    return true, skipped
end
function Model.CrossSize(contentSize, before, after, minimum)
    return math.max(minimum or 0, (contentSize or 0) + (before or 0) + (after or 0))
end
local function Color(value)
    if type(value)~="table" then return false end
    for i=1,4 do
        local v=value[i]
        if i<4 or v~=nil then if not Finite(v) or v<0 or v>1 then return false end end
    end
    return true
end
local function Appearance(value)
    if type(value)~="table" then return false end
    for _,key in ipairs({"size","iconSize","iconGap"}) do
        local number=value[key]
        if number~=nil and (not Finite(number) or number<0 or number>256) then return false end
    end
    if value.size~=nil and value.size<6 then return false end
    if value.font~=nil and type(value.font)~="string" then return false end
    if value.shadow~=nil and type(value.shadow)~="boolean" then return false end
    if value.color~=nil and not Color(value.color) then return false end
    if value.outline~=nil and value.outline~="NONE" and value.outline~="OUTLINE" and value.outline~="THICKOUTLINE" then return false end
    if value.display~=nil and value.display~="icon" and value.display~="both" and value.display~="text" and value.display~="none" then return false end
    if value.colorMode~=nil and value.colorMode~="state" and value.colorMode~="class" and value.colorMode~="custom" then return false end
    return true
end
local points={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}
local function Placement(value)
    if value==nil then return true end
    if type(value)~="table" or type(value.anchor)~="table" or type(value.offset)~="table" then return false end
    local anchor,offset=value.anchor,value.offset
    return points[anchor.point]==true and points[anchor.relativePoint]==true and type(anchor.relative)=="string"
        and Finite(offset.x) and Finite(offset.y) and math.abs(offset.x)<=20000 and math.abs(offset.y)<=20000
end
function Model.Validate(db)
    if type(db) ~= "table" or db.version ~= 2 or type(db.bars) ~= "table"
        or type(db.barOrder) ~= "table" or type(db.instances) ~= "table"
        or type(db.instanceOrder) ~= "table" or type(db.defaults) ~= "table" then return false, "invalid-schema" end
    if not Serializable(db, {}, 0, {count=0}) then return false, "invalid-config-value" end
    if db.geometryVersion~=nil and db.geometryVersion~=1 then return false,"invalid-geometry-version" end
    if not Appearance(db.defaults) then return false,"invalid-appearance" end
    if not Dense(db.barOrder, Model.MAX_BARS) or not Dense(db.instanceOrder, Model.MAX_INSTANCES) then
        return false, "invalid-order"
    end
    if not Finite(db.nextInstanceId) or db.nextInstanceId < 1 or db.nextInstanceId % 1 ~= 0 then
        return false, "invalid-next-id"
    end
    local bars, ids, placed = {}, {}, {}
    for _, id in ipairs(db.instanceOrder) do
        local inst = db.instances[id]
        if type(id) ~= "string" or ids[id] or type(inst) ~= "table" or type(inst.moduleType) ~= "string"
            or type(inst.config) ~= "table" or type(inst.appearance) ~= "table" then
            return false, "invalid-instance"
        end
        ids[id] = true
        if inst.alignment~=nil and inst.alignment~="LEFT" and inst.alignment~="RIGHT" then return false,"invalid-alignment" end
        if inst.expandBarHeight~=nil and type(inst.expandBarHeight)~="boolean" then return false,"invalid-expand-bar-height" end
        if inst.verticalAlignment~=nil and inst.verticalAlignment~="TOP" and inst.verticalAlignment~="CENTER"
            and inst.verticalAlignment~="BOTTOM" then return false,"invalid-vertical-alignment" end
        if inst.verticalOffset~=nil and (not Finite(inst.verticalOffset) or math.abs(inst.verticalOffset)>200) then
            return false,"invalid-vertical-offset"
        end
        if not Appearance(inst.appearance) then return false,"invalid-appearance" end
        for _,key in ipairs({"before","after","anchorGap"}) do
            if inst[key]~=nil and (not Finite(inst[key]) or math.abs(inst[key])>20000) then return false,"invalid-spacing" end
        end
        local serial = tonumber(id:match("^instance:(%d+)$"))
        if not serial or serial >= db.nextInstanceId then return false, "invalid-instance-id" end
    end
    for id in pairs(db.instances) do if not ids[id] then return false, "unordered-instance" end end
    for _, id in ipairs(db.barOrder) do
        local bar = db.bars[id]
        if type(id) ~= "string" or bars[id] or type(bar) ~= "table" or not Dense(bar.items, Model.MAX_INSTANCES)
            or type(bar.appearance) ~= "table" then return false, "invalid-bar" end
        if id ~= "top" and id ~= "bottom" and bar.kind ~= "independent" then return false, "invalid-bar-kind" end
        if bar.orientation and bar.orientation ~= "horizontal" and bar.orientation ~= "vertical" then return false, "invalid-orientation" end
        if bar.sizing and bar.sizing ~= "auto" and bar.sizing ~= "fixed" then return false, "invalid-sizing" end
        for _,key in ipairs({"reserveCenter","allowOverlap"}) do
            if bar[key]~=nil and type(bar[key])~="boolean" then return false,"invalid-geometry-option" end
        end
        if not Appearance(bar.appearance) then return false,"invalid-appearance" end
        if bar.enabled~=nil and type(bar.enabled)~="boolean" then return false,"invalid-bar-enabled" end
        if not Placement(bar.placement) then return false,"invalid-bar-placement" end
        if bar.padding~=nil then
            if type(bar.padding)~="table" then return false,"invalid-padding" end
            for _,key in ipairs({"before","after","crossBefore","crossAfter"}) do
                local v=bar.padding[key]
                if v~=nil and (not Finite(v) or v<0 or v>1000) then return false,"invalid-padding" end
            end
        end
        if bar.surface~=nil then
            local surface=bar.surface
            if type(surface)~="table" then return false,"invalid-surface" end
            if surface.classColor~=nil and type(surface.classColor)~="boolean" then return false,"invalid-surface-class-color" end
            if surface.texture~=nil and type(surface.texture)~="string" then return false,"invalid-surface-texture" end
            local presets={none=true,solid=true,rounded=true,metal=true,stone=true,native=true,custom=true,legacy=true}
            if surface.preset~=nil and not presets[surface.preset] then return false,"invalid-surface-preset" end
            local c=surface.color
            if c and type(c)=="table" and type(c[1])=="table" then c=c[1] end
            if c~=nil and not Color(c) then return false,"invalid-surface-color" end
            if surface.borderColor~=nil and not Color(surface.borderColor) then return false,"invalid-border-color" end
        end
        for _, key in ipairs({"length", "minCrossSize", "spacing"}) do
            if bar[key] ~= nil and (not Finite(bar[key]) or bar[key] < 0 or bar[key] > 20000) then
                return false, "invalid-geometry"
            end
        end
        bars[id] = true
        local centerFound = bar.centerInstanceId == nil
        for _, item in ipairs(bar.items) do
            if not ids[item] or placed[item] then return false, "invalid-placement" end
            placed[item] = true
            if item == bar.centerInstanceId then centerFound = true end
        end
        if not centerFound then return false, "invalid-center" end
    end
    for id in pairs(db.bars) do if not bars[id] then return false, "unordered-bar" end end
    if not bars.top or not bars.bottom or db.bars.top.kind ~= "top"
        or db.bars.bottom.kind ~= "bottom" then return false, "missing-fixed-bars" end
    return true
end
function Model.BeginDraft(db, revision)
    local ok, reason = Model.Validate(db)
    if not ok then return nil, reason end
    return {value=Copy(db), revision=revision, undo={}, redo={}}
end
function Model.ApplyDraft(draft, command)
    local candidate=Copy(draft.value)
    local ok, result, reason=pcall(command,candidate)
    if not ok then return false, "command-failed" end
    if result == false then return false, reason end
    local valid, errorCode=Model.Validate(candidate)
    if not valid then return false,errorCode end
    if Equal(candidate, draft.value) then return true, "unchanged" end
    draft.undo[#draft.undo+1]=draft.value
    if #draft.undo > Model.MAX_HISTORY then table.remove(draft.undo, 1) end
    draft.value=candidate;draft.redo={}
    return true
end
function Model.UndoDraft(draft)
    if #draft.undo==0 then return false end
    draft.redo[#draft.redo+1]=draft.value
    draft.value=table.remove(draft.undo)
    return true
end
function Model.RedoDraft(draft)
    if #draft.redo==0 then return false end
    draft.undo[#draft.undo+1]=draft.value
    draft.value=table.remove(draft.redo)
    return true
end
function Model.ExportDraft(draft, currentRevision)
    if currentRevision ~= draft.revision then return nil, "stale-revision" end
    local valid, reason=Model.Validate(draft.value)
    if not valid then return nil,reason end
    return Copy(draft.value)
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Model=Model
end
return Model
