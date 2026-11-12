local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local Locale = YUI.Locale
local L = Locale and Locale:Get("YActionBar") or {}
local LayoutBridge = {}
YAB.LayoutBridge = LayoutBridge

LayoutBridge.registered = LayoutBridge.registered or {}

local SPECIAL_GROUP_ID = YAB.SPECIAL_GROUP_ID or "specialActionsGroup"
local SPECIAL_GROUP_LAYOUT_ID = "yactionbar." .. SPECIAL_GROUP_ID
local SPECIAL_GROUP_MEMBER_IDS = { "zoneAbility", "extraAction", "vehicleExit" }
local EXTERNAL_SPECIAL_BAR_IDS = {
    extraAction = true,
    zoneAbility = true,
    vehicleExit = true,
}

local function InCombat()
    if YAB.Adapter and YAB.Adapter.InCombat then
        return YAB.Adapter:InCombat()
    end
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true or false
end

local function CopyPlacement(value)
    if type(value) ~= "table" then return value end
    if YAB.CopyValue then return YAB:CopyValue(value) end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyPlacement(item)
    end
    return result
end

local function ConfiguredDefaultPlacement(layoutId)
    local placement = YAB.DefaultPlacements and YAB.DefaultPlacements[layoutId]
    return type(placement) == "table" and CopyPlacement(placement) or nil
end

local function DefaultPlacement(id, config)
    local configured = ConfiguredDefaultPlacement("yactionbar." .. tostring(id))
    if configured then return configured end
    local layout = config and config.layout or nil
    return {
        point = layout and layout.point or "CENTER",
        relativeTo = "UIParent",
        relativePoint = layout and layout.relativePoint or "CENTER",
        x = layout and layout.x or 0,
        y = layout and layout.y or 0,
    }
end

local function ApplyPlacementToFrame(frame, placement)
    if not frame or type(placement) ~= "table" then return false end
    local anchor = placement.anchor
    local offset = placement.offset
    local point = anchor and anchor.point or placement.point or "CENTER"
    local relativeName = anchor and anchor.relative or placement.relativeTo or "UIParent"
    local relativePoint = anchor and anchor.relativePoint
        or placement.relativePoint
        or point
    local x = offset and offset.x or placement.x or 0
    local y = offset and offset.y or placement.y or 0
    local relativeFrame = relativeName == "UIParent" and UIParent or _G[relativeName]
    if not relativeFrame and type(placement.fallback) == "table" then
        return ApplyPlacementToFrame(frame, placement.fallback)
    end
    if not relativeFrame then return false end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeFrame, relativePoint, x, y)
    return true
end

local function ResolveRecordFrame(record)
    if not record then return nil end
    if record.GetObjectType then return record end
    return record.mover or record.frame or record.holder
end

local function ApplyFallbackPlacement(frame, id, config)
    if not frame then return false end
    if InCombat() then return false end
    return ApplyPlacementToFrame(frame, DefaultPlacement(id, config))
end

local function GetLiveConfig(id)
    local db = YAB.GetDB and YAB:GetDB() or nil
    if not db then return nil, nil end
    if db.bars and db.bars[id] then
        return db.bars[id], db
    end
    if db.specialBars and db.specialBars[id] then
        return YAB.ClassTools and YAB.ClassTools:GetConfig(id, db) or db.specialBars[id], db
    end
    return nil, db
end

local function GetLocalizedBarTitle(id, fallback)
    local key = id == "stance" and Client.ownedStanceButtons == true and "bar.stance.retail" or ("bar." .. tostring(id))
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then return value end
    return fallback or tostring(id)
end

local function GetRuntimeGroupingMode()
    local manager = YAB.BarManager
    if manager and manager.runtimeActive == true and manager.GetSpecialGroupingMode then
        return manager:GetSpecialGroupingMode()
    end
    return YAB.GetSpecialGroupingMode and YAB:GetSpecialGroupingMode() or "independent"
end

local function IsSpecialMemberGrouped(id)
    return EXTERNAL_SPECIAL_BAR_IDS[id] == true
        and YAB.IsSpecialBarGrouped
        and YAB:IsSpecialBarGrouped(id, GetRuntimeGroupingMode()) == true
end

local function IsSpecialGroupingActive()
    return GetRuntimeGroupingMode() ~= (YAB.SPECIAL_GROUPING_MODE_INDEPENDENT or "independent")
end

local function PersistCommittedPlacement(layoutId, placement, reason)
    local configSets = YAB.ConfigSets
    if not (configSets and configSets.PatchActivePlacement) then
        return false, "config-sets-service-unavailable"
    end
    local stored, code, detail = configSets:PatchActivePlacement(
        layoutId,
        placement,
        "layout-placement-" .. tostring(reason or "commit"),
        YAB
    )
    if not stored then return false, code, detail end
    return true
end

local function BuildYActionBarAnchorTargets()
    local targets = {}
    local factory = YAB.SecureFactory
    if not (factory and factory.FrameName) then return targets end
    local db = YAB.GetDB and YAB:GetDB() or nil
    local function AddTarget(id, config)
        if YAB.ClassTools and YAB.ClassTools:IsClassBar(id) and YAB.ClassTools:GetSettingsBarId(id, db) ~= id then return end
        targets[#targets + 1] = {
            name = factory:FrameName("Mover", id),
            label = GetLocalizedBarTitle(id, config and config.label),
        }
    end
    for _, id in ipairs(YAB.BAR_ORDER or {}) do
        AddTarget(id, db and db.bars and db.bars[id])
    end
    for _, id in ipairs(YAB.SPECIAL_BAR_ORDER or {}) do
        AddTarget(id, db and db.specialBars and db.specialBars[id])
    end
    if IsSpecialGroupingActive() then
        AddTarget(SPECIAL_GROUP_ID)
    end
    return targets
end

local function BuildSpecialGroupAnchorTargets()
    local targets = {}
    local factory = YAB.SecureFactory
    if not (factory and factory.FrameName) then return targets end
    local db = YAB.GetDB and YAB:GetDB() or nil
    local function AddTarget(id, config)
        if YAB.ClassTools and YAB.ClassTools:IsClassBar(id) and YAB.ClassTools:GetSettingsBarId(id, db) ~= id then return end
        targets[#targets + 1] = {
            name = factory:FrameName("Mover", id),
            label = GetLocalizedBarTitle(id, config and config.label),
        }
    end
    for _, id in ipairs(YAB.BAR_ORDER or {}) do
        AddTarget(id, db and db.bars and db.bars[id])
    end
    for _, id in ipairs(YAB.SPECIAL_BAR_ORDER or {}) do
        if not IsSpecialMemberGrouped(id) then
            AddTarget(id, db and db.specialBars and db.specialBars[id])
        end
    end
    return targets
end

function LayoutBridge:GetLayoutId(id)
    return self.classLayoutIds and self.classLayoutIds[id]
        or YAB.ClassTools and YAB.ClassTools:GetLayoutId(id) or "yactionbar." .. tostring(id)
end

function LayoutBridge:Register(id, record, title, config)
    local frame = ResolveRecordFrame(record)
    if not frame then return false end
    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyFallbackPlacement(frame, id, config)
        return false
    end
    local layoutId = YAB.ClassTools and YAB.ClassTools:GetLayoutId(id) or "yactionbar." .. tostring(id)
    local classTransition = YAB.ClassTools and YAB.ClassTools:IsClassBar(id)
    if classTransition and InCombat() then return false end
    if classTransition then record.classBarLayoutTransition = true end
    if YAB.ClassTools and YAB.ClassTools:IsClassBar(id) then
        self.classLayoutIds = self.classLayoutIds or {}
        if self.classLayoutIds[id] and self.classLayoutIds[id] ~= layoutId then self:Unregister(id, true) end
        self.classLayoutIds[id] = layoutId
        if layoutId == "yactionbar.classTools" then
            if self.classToolsPlaceholderActive then self:Unregister("classTools", true) end
            frame = YAB.SecureFactory:CreateMover("classTools")
            frame:SetSize(record.layoutWidth or 36, record.layoutHeight or 36)
        end
    end
    -- Core Layout skips onApply on register/refresh. Connect the runtime mover
    -- to the shared anchor here so its holder and buttons have a real position.
    if record.mover and record.mover ~= frame and not InCombat() then
        record.mover:ClearAllPoints()
        record.mover:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    local localizedTitle = GetLocalizedBarTitle(layoutId == "yactionbar.classTools" and "classTools" or id, title)
    YUI.Layout:RegisterFrame(layoutId, {
        frame = frame,
        title = localizedTitle or layoutId,
        category = "product",
        defaultPlacement = function()
            return DefaultPlacement(id, config)
        end,
        combatProtected = true,
        showOnlyInEditMode = record.classToolsPlaceholder == true,
        movable = true,
        snap = true,
        anchorTargets = BuildYActionBarAnchorTargets,
        minWidth = 24,
        minHeight = 24,
        getMoverBounds = function()
            local width = tonumber(record and record.layoutWidth) or (frame.GetWidth and frame:GetWidth()) or 24
            local height = tonumber(record and record.layoutHeight) or (frame.GetHeight and frame:GetHeight()) or 24
            return math.max(width, 24), math.max(height, 24), 0, 0
        end,
        onApply = function(appliedFrame)
            if record and record.holder and not (YAB.Adapter and YAB.Adapter:InCombat()) then
                record.holder:ClearAllPoints()
                record.holder:SetPoint("CENTER", record.mover or appliedFrame, "CENTER", 0, 0)
            end
        end,
        onEnterEditMode = record.onEnterEditMode,
        onExitEditMode = record.onExitEditMode,
        onEditModeFilterChanged = record.onEditModeFilterChanged,
        onPlacementCommitted = function(_, placement, _, _, reason)
            return PersistCommittedPlacement(layoutId, placement, reason)
        end,
        openPluginSettings = function()
            if YAB.OpenSettings then
                YAB:OpenSettings(YAB.ClassTools and YAB.ClassTools:GetSettingsBarId(id) or id)
                return true
            end
            return false
        end,
        isEnabled = function()
            local liveConfig, db = GetLiveConfig(id)
            if not (db and db.enabled == true) then return false end
            if IsSpecialMemberGrouped(id) then return false end
            if liveConfig then
                return liveConfig.enabled ~= false
            end
            return config and config.enabled ~= false or false
        end,
    })
    self.registered[layoutId] = true
    if YAB.ConfigSets and YAB.ConfigSets.ApplyDormantPlacement then
        YAB.ConfigSets:ApplyDormantPlacement(layoutId)
    end
    if classTransition then record.classBarLayoutTransition = nil end
    return true
end

-- Other classes have no runtime buttons on this character, but their shared
-- placement must remain editable after the current class detaches.
function LayoutBridge:SyncClassToolsMover()
    local tools, manager = YAB.ClassTools, YAB.BarManager
    if not tools or not manager or InCombat() or not (YUI.Layout and YUI.Layout.RegisterFrame) then return false end
    local db, shared = YAB:GetDB(), false
    if not (db.enabled and manager.runtimeActive) then return self:Unregister("classTools", true) end
    for _, id in ipairs(tools.ids) do
        if not tools:IsIndependent(id, db) then
            shared = true
            if YAB.ClassBars.active[id] and self:GetLayoutId(id) == "yactionbar.classTools" then return true end
        end
    end
    if not shared then return self:Unregister("classTools", true) end
    local config = db.specialBars.classTools
    local record = self.classToolsPlaceholder
    if not record then
        record = { mover = YAB.SecureFactory:CreateMover("classTools"), classToolsPlaceholder = true }
        self.classToolsPlaceholder = record
    end
    record.layoutWidth, record.layoutHeight = manager:MeasureDormantActionBar(config)
    record.mover:SetSize(record.layoutWidth, record.layoutHeight)
    record.mover:Show()
    local registered = self:Register("classTools", record, nil, config)
    self.classToolsPlaceholderActive = registered
    return registered
end

function LayoutBridge:RegisterSpecialGroup(record, defaultPlacement)
    local frame = ResolveRecordFrame(record)
    if not frame then return false end
    local function ResolveDefault()
        local configured = ConfiguredDefaultPlacement(SPECIAL_GROUP_LAYOUT_ID)
        if configured then return configured end
        local placement = type(defaultPlacement) == "function" and defaultPlacement() or defaultPlacement
        if type(placement) == "table" then
            return {
                point = placement.point or "CENTER",
                relativeTo = placement.relativeTo or "UIParent",
                relativePoint = placement.relativePoint or placement.point or "CENTER",
                x = placement.x or 0,
                y = placement.y or 0,
            }
        end
        return DefaultPlacement(nil)
    end
    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        if not InCombat() then
            ApplyPlacementToFrame(frame, ResolveDefault())
        end
        return false
    end
    YUI.Layout:RegisterFrame(SPECIAL_GROUP_LAYOUT_ID, {
        frame = frame,
        title = GetLocalizedBarTitle(SPECIAL_GROUP_ID, "Special action bar group"),
        category = "product",
        defaultPlacement = ResolveDefault,
        combatProtected = true,
        movable = true,
        snap = true,
        anchorTargets = BuildSpecialGroupAnchorTargets,
        minWidth = 24,
        minHeight = 24,
        getMoverBounds = function()
            local width = tonumber(record and record.layoutWidth) or (frame.GetWidth and frame:GetWidth()) or 24
            local height = tonumber(record and record.layoutHeight) or (frame.GetHeight and frame:GetHeight()) or 24
            width = math.max(width, 24)
            height = math.max(height, 24)
            return width, height, 0, 0
        end,
        onApply = function()
            local manager = YAB.BarManager
            if manager and manager.ApplySpecialActionGrouping then
                manager:ApplySpecialActionGrouping("layout-group-applied")
            end
        end,
        onPlacementCommitted = function(_, placement, _, _, reason)
            return PersistCommittedPlacement(
                SPECIAL_GROUP_LAYOUT_ID,
                placement,
                reason
            )
        end,
        openPluginSettings = function()
            if YAB.OpenSettings then
                YAB:OpenSettings(SPECIAL_GROUP_ID)
                return true
            end
            return false
        end,
        isEnabled = function()
            local db = YAB.GetDB and YAB:GetDB() or nil
            return db and db.enabled == true and IsSpecialGroupingActive()
        end,
    })
    self.registered[SPECIAL_GROUP_LAYOUT_ID] = true
    if YAB.ConfigSets and YAB.ConfigSets.ApplyDormantPlacement then
        YAB.ConfigSets:ApplyDormantPlacement(SPECIAL_GROUP_LAYOUT_ID)
    end
    return true
end

function LayoutBridge:RefreshSpecialGroup()
    if not self.registered[SPECIAL_GROUP_LAYOUT_ID] then return false end
    if YUI.Layout and YUI.Layout.RefreshFrame then
        return YUI.Layout:RefreshFrame(SPECIAL_GROUP_LAYOUT_ID)
    end
    return false
end

function LayoutBridge:ReapplySpecialGroupingPlacements()
    local layout = YUI.Layout
    if not (layout and layout.GetPlacement and layout.SetPlacement) then return false end
    local applied = false
    for _, id in ipairs(SPECIAL_GROUP_MEMBER_IDS) do
        local layoutId = "yactionbar." .. id
        if self.registered[layoutId] then
            local placement = layout:GetPlacement(layoutId)
            if placement then
                applied = layout:SetPlacement(layoutId, placement, true) ~= false or applied
            end
        end
    end
    if self.registered[SPECIAL_GROUP_LAYOUT_ID] then
        local placement = layout:GetPlacement(SPECIAL_GROUP_LAYOUT_ID)
        if placement then
            applied = layout:SetPlacement(SPECIAL_GROUP_LAYOUT_ID, placement, true) ~= false or applied
        end
    end
    return applied
end

function LayoutBridge:RefreshSpecialGrouping()
    local layout = YUI.Layout
    if not (layout and layout.RefreshFrame) then return false end
    local refreshed = false
    for _, id in ipairs(SPECIAL_GROUP_MEMBER_IDS) do
        local layoutId = "yactionbar." .. id
        if self.registered[layoutId] then
            refreshed = layout:RefreshFrame(layoutId) ~= false or refreshed
        end
    end
    if self.registered[SPECIAL_GROUP_LAYOUT_ID] then
        refreshed = layout:RefreshFrame(SPECIAL_GROUP_LAYOUT_ID) ~= false or refreshed
    end
    return refreshed
end

function LayoutBridge:Refresh(id)
    if YAB.ClassTools and YAB.ClassTools:IsClassBar(id) and self:GetLayoutId(id) == "yactionbar.classTools"
        and not InCombat() then
        local record = YAB.BarManager and YAB.BarManager.bars[id]
        if record then YAB.SecureFactory:CreateMover("classTools"):SetSize(record.layoutWidth or 36, record.layoutHeight or 36) end
    end
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(self:GetLayoutId(id))
    end
    local layoutId = self:GetLayoutId(id)
    if not self.registered[layoutId] then return false end
    if YUI.Layout and YUI.Layout.RefreshFrame then
        return YUI.Layout:RefreshFrame(layoutId)
    end
    return false
end

function LayoutBridge:IsRegistered(id)
    local layoutId = self:GetLayoutId(id)
    return self.registered[layoutId] == true
end

function LayoutBridge:Unregister(id, preservePlacement)
    local layoutId = self:GetLayoutId(id)
    if not self.registered[layoutId] then return false end
    if preservePlacement == true
        and YUI.Layout
        and YUI.Layout.GetPlacement
        and YAB.ConfigSets
        and YAB.ConfigSets.PreserveDormantPlacement then
        local placement = YUI.Layout:GetPlacement(layoutId)
        if placement then
            YAB.ConfigSets:PreserveDormantPlacement(layoutId, placement)
        end
    end
    if YUI.Layout and YUI.Layout.UnregisterFrame then
        YUI.Layout:UnregisterFrame(layoutId)
    end
    self.registered[layoutId] = nil
    if layoutId == "yactionbar.classTools" then self.classToolsPlaceholderActive = nil end
    if self.classLayoutIds then self.classLayoutIds[id] = nil end
    return true
end

function LayoutBridge:UnregisterAll()
    if not (YUI.Layout and YUI.Layout.UnregisterFrame) then
        self.registered = {}
        return
    end
    for layoutId in pairs(self.registered) do
        YUI.Layout:UnregisterFrame(layoutId)
    end
    self.registered = {}
    self.classLayoutIds = nil
    self.classToolsPlaceholderActive = nil
end


-- Definitions survive business disable; registration does not initialize action bars.
local function ResolveDormantActionAnchor(layoutId)
    local id = layoutId:match("^yactionbar%.(.+)$")
    local profile = YAB.GetProfile and YAB:GetProfile()
    if not profile then return nil end
    local db = profile[YAB.STORAGE_KEY] or YAB.Defaults
    local config = db and db.bars and db.bars[id]
        or YAB.Defaults and YAB.Defaults.bars and YAB.Defaults.bars[id]
    local manager = YAB.BarManager
    if not config or not manager or not manager.MeasureDormantActionBar then return nil end
    local width, height = manager:MeasureDormantActionBar(config)
    return DefaultPlacement(id, config), width, height, 1
end
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    for _, id in ipairs(YAB.BAR_ORDER or {}) do
        YUI.Layout:RegisterAnchorProvider("yactionbar." .. id, {
            name = "YUI_YActionBar_Mover_" .. id,
            resolve = ResolveDormantActionAnchor,
            getState = function()
                local profile = YAB.GetProfile and YAB:GetProfile()
                if not profile then return "unknown" end
                local db = profile[YAB.STORAGE_KEY] or YAB.Defaults
                if not db then return "unknown" end
                local bar = db.bars and db.bars[id]
                if db.enabled == false or (bar and bar.enabled == false) then return "disabled" end
                return "unknown"
            end,
        })
    end
end
