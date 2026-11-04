local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end
local System, Talent = YUI.API.System, YUI.API.Talent
local C = {}
A.Client = C

local function clean(text)
    return type(text) == "string" and text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|", "") or ""
end

local function displayTitle(text)
    -- Icons have their own column; preserve only valid inline color escapes in the name.
    return text:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|([^|]*)", function(part)
        local color = part:match("^[cC](%x%x%x%x%x%x%x%x)")
        if color then return "|c" .. color .. part:sub(10) end
        if part:match("^[rR]") then return "|r" .. part:sub(2) end
        return part
    end)
end

local function iconInfo(name, title)
    local texture = System.GetAddOnMetadata(name, "IconTexture")
    if texture and texture ~= "" then return tonumber(texture) or texture end
    local atlas = System.GetAddOnMetadata(name, "IconAtlas")
    if atlas and atlas ~= "" then return nil, atlas end
    local markup = type(title) == "string" and title:match("|T(.-)|t")
    if markup then
        local fields = {}; for field in (markup .. ":"):gmatch("(.-):") do fields[#fields+1] = field end
        local width, height = tonumber(fields[6]), tonumber(fields[7])
        local left, right, top, bottom = tonumber(fields[8]), tonumber(fields[9]), tonumber(fields[10]), tonumber(fields[11])
        local coords = width and height and width > 0 and height > 0 and left and right and top and bottom
            and {left/width, right/width, top/height, bottom/height} or nil
        if fields[1] ~= "" then return tonumber(fields[1]) or fields[1], nil, coords end
    end
    return nil, type(title) == "string" and title:match("|A:?([^:|]+):") or nil
end

function C.Scan()
    local records, enabled = {}, {}
    for i = 1, System.GetNumAddOns() do
        local name, title, notes, loadable, reason = System.GetAddOnInfo(i)
        if name and not name:match("^Blizzard_") then
            local deps = System.GetRequiredAddOnDependencies(name)
            local checked = System.GetAddOnEnabledState(name)
            if deps == nil or checked == nil then return nil, "unavailable" end
            local managedDeps = {}
            for _, dep in ipairs(deps) do if not dep:match("^Blizzard_") then managedDeps[#managedDeps + 1] = dep end end
            local metadata = System.GetAddOnMetadata(name, "X-Part-Of") or System.GetAddOnMetadata(name, "Group")
            local tags, group = A.Classify(name, managedDeps, metadata)
            local icon, iconAtlas, iconCoords = iconInfo(name, title)
            local plainTitle = clean(title)
            local shownTitle = plainTitle ~= "" and displayTitle(title) or name
            records[#records + 1] = { name = name, title = plainTitle ~= "" and plainTitle or name, displayTitle = shownTitle, notes = clean(notes),
                author = clean(System.GetAddOnMetadata(name, "Author")), deps = managedDeps, tags = tags, group = group,
                loaded = System.IsAddOnLoaded(name) == true, loadable = loadable, reason = reason,
                onDemand = System.GetAddOnMetadata(name, "LoadOnDemand") == "1",
                icon = icon, iconAtlas = iconAtlas, iconCoords = iconCoords }
            if checked then enabled[name] = true end
        end
    end
    return records, enabled
end

function C.Read(records)
    local enabled = {}
    for _, record in ipairs(records) do
        local value = System.GetAddOnEnabledState(record.name)
        if value == nil then return nil end
        if value then enabled[record.name] = true end
    end
    return enabled
end

function C.Apply(target, records)
    if not System.IsAddOnSwitchSafe() then return false, "unsafe" end
    local before = C.Read(records)
    if not before then return false, "unavailable" end
    local changed = {}
    local function rollback()
        local restored = true
        for i = #changed, 1, -1 do
            local name = changed[i]
            if not System.SetCurrentCharacterAddOnEnabled(name, before[name] == true) then restored = false end
        end
        return System.SaveAddOns() and restored
    end
    for _, record in ipairs(records) do
        local name = record.name
        if not not before[name] ~= not not target[name] then
            changed[#changed + 1] = name
            if not System.SetCurrentCharacterAddOnEnabled(name, target[name] == true) then
                return false, rollback() and "applyFailed" or "rollbackFailed"
            end
        end
    end
    if not System.SaveAddOns() then return false, rollback() and "applyFailed" or "rollbackFailed" end
    return true, before
end

function C.Context()
    local kind, difficulty, map = System.GetCombatLogContext()
    if not kind then return nil end
    local _, class, classID = UnitClass("player")
    local configuration = Talent.GetCurrentConfigurationSpecializationInfo()
    if A.flavor == "forever" and not configuration then return nil end
    local spec = configuration and configuration.specID or 0
    local scene = "world"
    if kind == "raid" then scene = "raid"
    elseif kind == "arena" then scene = "arena"
    elseif kind == "pvp" then scene = "battleground"
    elseif kind == "party" then scene = "dungeon" end
    return { scene = scene, class = classID, classFile = class, spec = spec or 0, map = map or 0,
        key = table.concat({scene, classID or 0, spec or 0, map or 0}, ":") }
end

function C.Metrics(records,mode)
    mode=mode or "both"
    local result = {}
    local memory = mode~="cpu" and System.RefreshAddOnMemoryUsage()
    local cpu = mode~="memory"
    for _, record in ipairs(records) do
        record.loaded = System.IsAddOnLoaded(record.name) == true
        if mode=="both" or record.loaded then
            result[record.name] = { memory = memory and System.GetAddOnMemoryKilobytes(record.name) or nil,
                cpu = cpu and System.GetAddOnCPURecentAverage(record.name) or nil }
        end
    end
    return result, cpu and {application=System.GetApplicationCPURecentAverage(), total=System.GetOverallCPURecentAverage()} or {}
end

C.Safe = System.IsAddOnSwitchSafe
C.CanResetCPU = System.CanResetCPUUsage
C.ResetCPU = System.ResetCPUUsage
C.Character = System.GetAddOnManagementCharacter
C.Reload = YUI.API.Frame.ReloadUI
