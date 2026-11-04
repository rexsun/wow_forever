local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end
local M = {}
A.Model = M

function M.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = M.Copy(v) end
    return copy
end

function M.Same(a, b)
    for k, v in pairs(a or {}) do if v == true and not (b and b[k]) then return false end end
    for k, v in pairs(b or {}) do if v == true and not (a and a[k]) then return false end end
    return true
end

function M.Index(records)
    local byName, reverse = {}, {}
    for _, r in ipairs(records) do byName[r.name] = r end
    for _, r in ipairs(records) do
        for _, dependency in ipairs(r.deps or {}) do
            reverse[dependency] = reverse[dependency] or {}
            reverse[dependency][#reverse[dependency] + 1] = r.name
        end
    end
    return byName, reverse
end

-- Dependency closure is iterative: cycles and deeply nested modules are bounded.
function M.Resolve(selected, locks, byName)
    local result, missing, queue, seen = {}, {}, {}, {}
    -- Removed addons stay in saved profiles, but only installed roots participate.
    -- A missing dependency of an installed root still blocks that selection.
    for name, enabled in pairs(selected or {}) do if enabled and byName[name] then queue[#queue + 1] = name end end
    for name, locked in pairs(locks or {}) do if locked and byName[name] then queue[#queue + 1] = name end end
    local cursor = 1
    while cursor <= #queue do
        local name = queue[cursor]; cursor = cursor + 1
        if not seen[name] then
            seen[name] = true
            local record = byName[name]
            if record then
                result[name] = true
                for _, dependency in ipairs(record.deps or {}) do queue[#queue + 1] = dependency end
            else missing[name] = true end
        end
    end
    return result, missing
end

-- Saved choices retain disabled dependencies; only explicit locks force them on.
function M.Selection(selected, locks, byName)
    local result, missing = M.Resolve(selected, locks, byName)
    local protected = M.Resolve({}, locks, byName)
    for name in pairs(result) do
        if not (selected and selected[name]) and not protected[name] then result[name] = nil end
    end
    return result, missing
end

function M.Unloadable(selected, byName, reverse)
    local blocked, unavailable, direct, queue = {}, {}, {}, {}
    for name, enabled in pairs(selected or {}) do
        local record = enabled and byName[name]
        if record then
            for _, dependency in ipairs(record.deps or {}) do
                if not selected[dependency] then
                    unavailable[dependency] = true
                    direct[name] = true
                    if not blocked[name] then blocked[name] = true; queue[#queue + 1] = name end
                end
            end
        end
    end
    local cursor = 1
    while cursor <= #queue do
        local name = queue[cursor]; cursor = cursor + 1
        for _, dependent in ipairs(reverse[name] or {}) do
            if selected[dependent] and not blocked[dependent] then
                blocked[dependent] = true; queue[#queue + 1] = dependent
            end
        end
    end
    return blocked, unavailable, direct
end

-- Find a shortest required-dependency path on hover, bounded even for cycles.
function M.DependencyPath(name, selected, byName)
    local queue, seen, previous, cursor = {name}, {[name]=true}, {}, 1
    while cursor <= #queue do
        local current = queue[cursor]; cursor = cursor + 1
        local record = byName[current]
        for _, dependency in ipairs(record and record.deps or {}) do
            if not seen[dependency] then
                seen[dependency], previous[dependency] = true, current
                if not selected[dependency] or not byName[dependency] then
                    local reversed, path, step = {}, {}, dependency
                    while step do reversed[#reversed+1] = step; step = previous[step] end
                    for i=#reversed,1,-1 do path[#path+1] = reversed[i] end
                    return path
                end
                queue[#queue+1] = dependency
            end
        end
    end
end

function M.Disable(selected, names, locks, byName, reverse, cascade)
    local result, removed, queue = M.Copy(selected), {}, {}
    for _, name in ipairs(names) do queue[#queue + 1] = name end
    local protected = M.Resolve({}, locks, byName)
    local cursor = 1
    while cursor <= #queue do
        local name = queue[cursor]; cursor = cursor + 1
        if protected[name] then return nil, "locked", name end
        if not removed[name] then
            removed[name] = true
            result[name] = nil
            if cascade ~= false then
                for _, dependent in ipairs(reverse[name] or {}) do
                    if selected[dependent] then queue[#queue + 1] = dependent end
                end
            end
        end
    end
    return result, removed
end

function M.Diff(before, after, records)
    local changes = {}
    for _, r in ipairs(records) do
        if not not before[r.name] ~= not not after[r.name] then
            changes[#changes + 1] = { name = r.name, title = r.title, enabled = after[r.name] == true }
        end
    end
    return changes
end

function M.Rule(rules, exceptions, context)
    rules = rules or {}
    local scene = context.scene
    local base = rules[scene]
    if not base or not base.profile or base.profile == "" then scene, base = "default", rules.default end
    if not base then return nil end
    local all, exact
    for _, rule in ipairs(exceptions or {}) do
        if rule.class == context.class and rule.scene == scene then
            if rule.spec ~= 0 and rule.spec == context.spec then exact = rule; break end
            if rule.spec == 0 and not all then all = rule end
        end
    end
    local override = exact or all
    return {profile=override and override.profile or base.profile, mode="prompt", scene=scene,
        source=exact and "spec" or all and "class" or "scene", class=override and override.class or 0, spec=override and override.spec or 0}
end

function M.RuleContext(context, rule)
    return table.concat({context.scene, rule and rule.scene or "", rule and rule.source or "",
        rule and rule.class or 0, rule and rule.spec or 0, rule and rule.profile or "", rule and rule.mode or ""}, ":")
end

-- Validation is shared by the editor and the write boundary; drafts never mutate saved rules.
function M.CheckException(exceptions, rule, ignore, rules, profiles)
    local result = {merge={}, overrides={}}
    if type(rule) ~= "table" or type(rule.class) ~= "number" or rule.class < 1 or rule.class % 1 ~= 0
        or type(rule.spec) ~= "number" or rule.spec < 0 or rule.spec % 1 ~= 0
        or not rules[rule.scene] or not profiles[rule.profile] then result.error="invalidRule"; return result end
    for index, existing in ipairs(exceptions) do
        if index ~= ignore and existing.scene == rule.scene and existing.class == rule.class then
            if existing.spec == rule.spec then result.error, result.existing = "duplicateRule", index; return result end
            if rule.spec ~= 0 and existing.spec == 0 then
                if existing.profile == rule.profile then result.error, result.existing = "redundantRule", index; return result end
                result.parent = index
            elseif rule.spec == 0 and existing.spec ~= 0 then
                local target = existing.profile == rule.profile and result.merge or result.overrides
                target[#target+1] = index
            end
        end
    end
    return result
end

function M.Total(selected)
    local count = 0
    for _, enabled in pairs(selected or {}) do if enabled then count = count + 1 end end
    return count
end

function M.Manifest(profile, byName, baseline)
    local rows = {}
    for name, enabled in pairs(profile and profile.addons or {}) do
        if enabled then
            local record = byName[name]
            local rank = not record and 1 or not baseline[name] and 2 or not record.loaded and 3 or 4
            rows[#rows+1] = {name=name, title=record and record.title or name, rank=rank}
        end
    end
    table.sort(rows, function(a,b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.title ~= b.title then return a.title < b.title end
        return a.name < b.name
    end)
    return rows
end

function M.RuleDuplicate(exceptions, rule, ignore)
    for i, existing in ipairs(exceptions) do
        if i ~= ignore and existing.class == rule.class and existing.spec == rule.spec and existing.scene == rule.scene then return true end
    end
    return false
end

function M.Rows(records, byName)
    local rows, nodes, parents, explicit = {}, {}, {}, {}
    for _, record in ipairs(records) do
        nodes[record.name] = {record=record,name=record.name,members={},children={}}
        if record.group and byName[record.group] and record.group~=record.name then
            parents[record.name] = record.group
            explicit[record.name] = true
        else
            -- A tree has one visual parent; the complete dependency graph still owns toggles.
            for _, dependency in ipairs(record.deps or {}) do
                if byName[dependency] and dependency~=record.name then parents[record.name]=dependency; break end
            end
        end
    end
    -- Prefer declared families when a core requires one of its own modules.
    -- Genuine metadata/dependency cycles remain visible rather than hiding records.
    local done = {}
    for _, record in ipairs(records) do
        local path, at, name = {}, {}, record.name
        while name and not done[name] and not at[name] do
            path[#path+1]=name; at[name]=#path; name=parents[name]
        end
        if name and at[name] then
            local inferred=false
            for i=at[name],#path do inferred=inferred or not explicit[path[i]] end
            for i=at[name],#path do if not inferred or not explicit[path[i]] then parents[path[i]]=nil end end
        end
        for _, visited in ipairs(path) do done[visited]=true end
    end
    for _, record in ipairs(records) do
        local node, parent = nodes[record.name], nodes[parents[record.name]]
        node.parent=parent
        local target=parent and parent.children or rows
        target[#target+1]=node
        local ancestor=node
        while ancestor do ancestor.members[#ancestor.members+1]=record.name; ancestor=nodes[parents[ancestor.name]] end
    end
    return rows
end

function M.Count(selected, rows)
    local count = 0
    for _, row in ipairs(rows) do
        for _, name in ipairs(row.members) do
            if selected[name] then count = count + 1; break end
        end
    end
    return count
end

local function sortSiblings(rows, key, descending, selected, baseline, locks, metrics, seen)
    local snapshot, sorted = {}, {}
    for _, row in ipairs(rows) do
        local record, enabled, locked, changed, new = row.record, 0, false, false, false
        local cpu, memory = 0, 0
        for _, name in ipairs(row.members) do
            enabled = enabled + (selected[name] and 1 or 0)
            locked = locked or locks[name]
            changed = changed or (not not selected[name] ~= not not baseline[name])
            new = new or not seen[name]
            local metric = metrics[name] or {}
            cpu, memory = cpu + (metric.cpu or 0), memory + (metric.memory or 0)
        end
        snapshot[row.name] = { name = string.lower(record.title), enabled = enabled / #row.members,
            tags = table.concat(record.tags or {}, ","), locked = locked and 1 or 0,
            status = changed and 2 or (record.loaded and 1 or 0), cpu = cpu, memory = memory, new = new }
        sorted[#sorted + 1] = row
    end
    table.sort(sorted, function(a, b)
        local av, bv = snapshot[a.name], snapshot[b.name]
        if key == "default" and av.new ~= bv.new then return av.new end
        local actual = key == "default" and "name" or key
        if av[actual] ~= bv[actual] then
            if descending then return av[actual] > bv[actual] end
            return av[actual] < bv[actual]
        end
        if av.name ~= bv.name then return av.name < bv.name end
        return a.name < b.name
    end)
    return sorted
end

function M.Sort(rows, key, descending, selected, baseline, locks, metrics, seen)
    local sorted=sortSiblings(rows,key,descending,selected,baseline,locks,metrics,seen)
    local queue={}
    for _,row in ipairs(sorted) do queue[#queue+1]=row end
    local cursor=1
    while cursor<=#queue do
        local row=queue[cursor]; cursor=cursor+1
        if #row.children>0 then
            row.children=sortSiblings(row.children,key,descending,selected,baseline,locks,metrics,seen)
            for _,child in ipairs(row.children) do queue[#queue+1]=child end
        end
    end
    return sorted
end

function M.ValidName(name, profiles, except)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" or #name > 72 or name:find("[|%c]") then return nil, "invalidName" end
    for id, profile in pairs(profiles) do
        if id ~= except and string.lower(profile.name) == string.lower(name) then return nil, "duplicateName" end
    end
    return name
end
