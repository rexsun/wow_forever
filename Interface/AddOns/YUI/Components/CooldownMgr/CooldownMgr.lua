-------------------------------------------------------------------------------
-- YUI | 冷却管理器
-------------------------------------------------------------------------------
local _, YUI = ...

YUI.CooldownMgr = {}
local CM = YUI.CooldownMgr

local C_EncodingUtil = C_EncodingUtil
local C_CooldownViewer = C_CooldownViewer
local C_AddOns = C_AddOns
local UnitClass = UnitClass

-- Constants
local CONFIG_PREFIX = "YUI"
local CD_STR_PREFIX = "1|"
local LC = YUI.Locale:Get("Core")

local function Fail(reason, detail)
    if detail and YUI.Debug then YUI:Debug("CooldownMgr: " .. tostring(detail)) end
    return nil, LC["installer.cooldown." .. reason]
end

-- 获取带版本号的配置名称
function CM:GetVersionedProfileName(specName, version)
    return CONFIG_PREFIX .. " " .. specName .. " v" .. (version or 1)
end

-- 判断是否为 YUI 配置 (支持 "YUI <Spec>", "YUI <Spec> v1" 等)
function CM:IsYUIProfile(profileName, specName)
    if type(profileName) ~= "string" then return false end
    
    -- 基础前缀匹配
    if not profileName:find("^" .. CONFIG_PREFIX) then return false end
    
    -- 如果指定了专精，则精确匹配
    if specName then
        -- 转义专精名中的特殊字符
        local escapedSpec = specName:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
        
        -- 匹配 "YUI <Spec>" (完全匹配)
        if profileName == CONFIG_PREFIX .. " " .. specName then return true end
        
        -- 匹配 "YUI <Spec> v<Num>"
        local pattern = "^" .. CONFIG_PREFIX .. " " .. escapedSpec .. " v%d+$"
        if profileName:match(pattern) then return true end
        
        return false
    end
    
    return true
end

-- 解析配置版本号
function CM:GetProfileVersion(profileName)
    if type(profileName) ~= "string" then return 0 end
    local ver = profileName:match("v(%d+)$")
    return tonumber(ver) or 0 -- 如果没有 vX 后缀，视为版本 0 (旧版)
end
-------------------------------------------------------------------------------
-- 内部辅助函数
-------------------------------------------------------------------------------

function CM:DecodeString(str)
    if not C_EncodingUtil or type(str) ~= "string" then return Fail("invalid") end
    local payload = str:match("^1|(.+)$")
    if not payload then return Fail("invalid") end
    local ok, data = pcall(function()
        local raw = C_EncodingUtil.DecodeBase64(payload)
        local bytes = raw and C_EncodingUtil.DecompressString(raw, Enum.CompressionMethod.Deflate)
        return bytes and C_EncodingUtil.DeserializeCBOR(bytes)
    end)
    if not ok or type(data) ~= "table" then return Fail("invalid", not ok and data) end
    if (data[1] ~= 4 and data[1] ~= 5) or type(data[2]) ~= "table"
        or (data[3] ~= nil and type(data[3]) ~= "table")
        or (data[4] ~= nil and type(data[4]) ~= "table") then return Fail("invalid") end
    return data
end

function CM:Table2String(tbl)
    if not C_EncodingUtil then return Fail("unavailable") end
    local ok, encoded = pcall(function()
        local bytes = C_EncodingUtil.SerializeCBOR(tbl)
        local zipped = bytes and C_EncodingUtil.CompressString(bytes, Enum.CompressionMethod.Deflate)
        return zipped and C_EncodingUtil.EncodeBase64(zipped)
    end)
    if not ok or not encoded then return Fail("invalid", not ok and encoded) end
    return CD_STR_PREFIX .. encoded
end

-- Settings 为按需加载的全局对象，不能在组件加载时缓存其 nil 值。
function CM:GetLayoutManager()
    if not _G.CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
        local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
        if not ok or not loaded then return Fail("unavailable", reason or loaded) end
    end
    local settings = _G.CooldownViewerSettings
    if not settings or not settings.GetLayoutManager then return Fail("unavailable") end
    local manager = settings:GetLayoutManager()
    if not manager or not manager:IsLoaded() then return Fail("pending") end
    return manager
end

local function ReadProfiles(manager)
    local profiles = {}
    for id, layout in manager:EnumerateLayouts() do
        profiles[id] = manager:GetLayoutName(layout)
    end
    return profiles
end

local function GetClassConfig()
    local _, cls = UnitClass("player")
    return cls and YUI.Data and YUI.Data:GetData("CooldownMgr", cls:upper())
end

local function BuildPlan(profiles, cfg, force)
    local plan, skipped, count, netNew = {}, 0, 0, 0
    for _ in pairs(profiles) do count = count + 1 end
    for specID, info in pairs(cfg) do
        local replaceID, installed
        for id, name in pairs(profiles) do
            if CM:IsYUIProfile(name, info.Name) then
                local version = CM:GetProfileVersion(name)
                if not installed or version > installed then replaceID, installed = id, version end
            end
        end
        if not force and installed and installed >= info.Version then
            skipped = skipped + 1
        else
            plan[#plan + 1] = { specID = specID, info = info, replaceID = replaceID }
            if not replaceID then netNew = netNew + 1 end
        end
    end
    table.sort(plan, function(a, b) return a.specID < b.specID end)
    return plan, skipped, count, netNew
end

-- 对原生布局对象做事务，避免多专精导入失败后残留部分配置。
local function ChangeLayouts(manager, change)
    local layouts, previous = {}, {}
    for id, layout in manager:EnumerateLayouts() do layouts[id] = layout end
    for tag, id in manager:EnumeratePreviouslyActiveLayoutIDs() do previous[tag] = id end
    local active, pending = manager:GetActiveLayoutID(), manager:HasPendingChanges()
    local serializer = manager:GetSerializer()
    local saved = serializer:GetSerializedData()
    local saving = false
    manager:LockNotifications()
    local ok, result = pcall(function()
        local value = change()
        saving = true
        manager:SaveLayouts()
        return value
    end)
    if not ok then
        local restored, restoreError = pcall(function()
            local current = {}
            for id in manager:EnumerateLayouts() do current[#current + 1] = id end
            for _, id in ipairs(current) do manager:RemoveLayout(id) end
            for id, layout in pairs(layouts) do manager:SetLayout(id, layout) end
            for tag, id in pairs(previous) do
                if manager:IsDefaultLayoutID(id) then
                    manager:SetPreviouslyActiveLayoutForSpecToDefault(tag)
                else
                    manager:SetPreviouslyActiveLayout(manager:GetLayout(id))
                end
            end
            if active then manager:SetActiveLayoutByID(active) else manager:ClearActiveLayout() end
            if saving then serializer:SetSerializedData(saved) end
            manager:SetHasPendingChanges(pending)
        end)
        if not restored then result = tostring(result) .. "; " .. tostring(restoreError) end
    end
    -- 保存已结束，界面监听器异常不能再次破坏已提交的配置。
    local unlocked, unlockError = pcall(manager.UnlockNotifications, manager)
    if not unlocked and YUI.Debug then YUI:Debug("CooldownMgr: " .. tostring(unlockError)) end
    if not ok then return Fail("failed", result) end
    return result
end

-------------------------------------------------------------------------------
-- 删除指定名称的布局
function CM:DeleteProfile(name)
    if InCombatLockdown() then return false, LC["installer.cooldown.combat"] end
    local manager, err = self:GetLayoutManager()
    if not manager then return false, err end
    local ids = {}
    for id, profile in pairs(ReadProfiles(manager)) do
        if profile == name then ids[#ids + 1] = id end
    end
    if #ids == 0 then return false end
    local removed, reason = ChangeLayouts(manager, function()
        for _, id in ipairs(ids) do manager:RemoveLayout(id) end
        return true
    end)
    return removed == true, reason
end

function CM:DeleteNonYUIProfiles(count)
    if InCombatLockdown() then return 0, LC["installer.cooldown.combat"] end
    if not count or count <= 0 then return 0 end
    local manager, err = self:GetLayoutManager()
    if not manager then return 0, err end
    local ids = {}
    for id, name in pairs(ReadProfiles(manager)) do
        if not self:IsYUIProfile(name) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local limit = math.min(count, #ids)
    if limit == 0 then return 0 end
    local removed, reason = ChangeLayouts(manager, function()
        for i = 1, limit do manager:RemoveLayout(ids[i]) end
        return limit
    end)
    return removed or 0, reason
end

-- 原始导出读取仅供显式调用，布局列表和安装流程使用原生管理器。
function CM:GetLayoutData()
    if not C_CooldownViewer or not C_CooldownViewer.GetLayoutData then return Fail("unavailable") end
    local ok, text = pcall(C_CooldownViewer.GetLayoutData)
    if not ok then return Fail("invalid", text) end
    if text == "" then return { [1] = 4, [2] = {}, [3] = {}, [4] = {} } end
    return self:DecodeString(text)
end

function CM:CheckProfileLimit()
    local manager, err = self:GetLayoutManager()
    if not manager then return nil, nil, nil, err end
    local cfg = GetClassConfig()
    if not cfg then return nil, nil, nil, LC["installer.cooldown.no_presets"] end
    local _, _, count, netNew = BuildPlan(ReadProfiles(manager), cfg)
    return count, (5 - count) < netNew, netNew
end

function CM:GetInstalledVersions()
    local manager, err = self:GetLayoutManager()
    if not manager then return nil, err end
    local versions = {}
    for _, name in pairs(ReadProfiles(manager)) do
        if self:IsYUIProfile(name) then
            local specName, version = name:match("^YUI (.+) v(%d+)%s*$")
            specName = specName or name:match("^YUI (.+)%s*$")
            if specName then
                specName = specName:gsub("%s+$", "")
                versions[specName] = math.max(versions[specName] or 0, tonumber(version) or 0)
            end
        end
    end
    return versions
end

-- 获取当前职业的所有专精图标
function CM:GetClassSpecIcons()
    local _, cls = UnitClass("player")
    if not cls then return {} end
    cls = cls:upper()
    
    local icons = {}
    -- 获取职业ID
    local classID = select(3, UnitClass("player"))
    if not classID then return {} end
    
    local numSpecs = GetNumSpecializationsForClassID(classID)
    for i = 1, numSpecs do
        local id, name, _, icon = GetSpecializationInfoForClassID(classID, i)
        if icon then
            table.insert(icons, { id, name, icon })
        end
    end
    
    return icons
end

function CM:ImportClassCooldowns(force)
    if InCombatLockdown() then return false, LC["installer.cooldown.combat"] end
    local manager, err = self:GetLayoutManager()
    if not manager then return false, err end
    local cfg = GetClassConfig()
    if not cfg then return false, LC["installer.cooldown.no_presets"] end
    local plan, skipped, count, netNew = BuildPlan(ReadProfiles(manager), cfg, force)
    if count + netNew > 5 then return false, LC["installer.text.060"] end
    if #plan == 0 then
        if skipped > 0 then return true, LC["installer.cooldown.latest"] end
        return false, LC["installer.cooldown.no_presets"]
    end
    if not CreateFromMixins or not CooldownViewerLayoutManagerMixin
        or not CooldownViewerDataStoreSerializationMixin then return false, LC["installer.cooldown.unavailable"] end

    -- 在独立的内存管理器中使用原生反序列化，校验失败不会触碰玩家配置。
    local staged, stageError = pcall(function()
        local temporary = CreateFromMixins(CooldownViewerLayoutManagerMixin)
        local serializer = CreateFromMixins(CooldownViewerDataStoreSerializationMixin)
        temporary.SetHasPendingChanges = function(self, value) self.hasPendingChanges = value end
        temporary.NotifyListeners = function() end
        temporary:Init(manager:GetDataProvider(), serializer)
        serializer:Init(temporary, {
            GetSerializedData = function() return "" end,
            SetSerializedData = function() end,
            ClearSerializedData = function() end,
        })
        for _, entry in ipairs(plan) do
            local data, reason = self:DecodeString(entry.info.Data)
            if not data then error(reason) end
            local ids = temporary:CreateLayoutsFromSerializedData(entry.info.Data)
            if type(ids) ~= "table" or #ids ~= 1 then error(LC["installer.cooldown.invalid"]) end
            entry.layout = temporary:GetLayout(ids[1])
            if not entry.layout then error(LC["installer.cooldown.invalid"]) end
        end
    end)
    if not staged then
        local _, reason = Fail("invalid", stageError)
        return false, reason
    end

    local applied, reason = ChangeLayouts(manager, function()
        for _, entry in ipairs(plan) do
            if entry.replaceID then manager:RemoveLayout(entry.replaceID) end
            local layout = manager:ImportLayout(self:GetVersionedProfileName(entry.info.Name, entry.info.Version), entry.layout)
            if not layout then error(LC["installer.cooldown.failed"]) end
            manager:SetPreviouslyActiveLayout(layout)
            if CooldownManagerLayout_GetClassAndSpecTag(layout) == manager:GetCurrentSpecTag() then
                manager:SetActiveLayout(layout)
            end
        end
        return #plan
    end)
    if not applied then return false, reason end
    local message = string.format(LC["installer.cooldown.applied"], applied)
    if skipped > 0 then message = message .. string.format(LC["installer.cooldown.skipped"], skipped) end
    return true, message
end
