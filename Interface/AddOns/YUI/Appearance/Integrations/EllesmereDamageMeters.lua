local _, YUI = ...
if not YUI then return end

local Icons = YUI.API and YUI.API.Icons
local ICON_SCOPE_ID = "ellesmere_damage_meters"
local ADDON_NAME = "EllesmereUIDamageMeters"
local ELEMENT_PREFIX = "EDM_Win"
local MAX_SCAN_DEPTH = 24
if not Icons then return end

local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local strsub = string.sub
local hooksecurefunc = hooksecurefunc

local managedIcons = setmetatable({}, { __mode = "k" })
local registerHooked = false
local scanScheduled = false

local function SafeMethod(object, method, ...)
    if not object then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, object, ...)
    if ok then
        return a, b, c, d
    end
    return nil
end

local function SafeMethodList(object, method)
    if not object then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(function()
        return { fn(object) }
    end)
    if ok and type(result) == "table" then
        return result
    end
    return nil
end

local function SafeSetShown(region, shown)
    if shown then
        SafeMethod(region, "Show")
    else
        SafeMethod(region, "Hide")
    end
end

local function IsScopeEnabled()
    if Icons.IsIconScopeEnabled then
        return Icons.IsIconScopeEnabled(ICON_SCOPE_ID)
    end
    return true
end

local function IsDefaultSpecStyle()
    local ok, style = pcall(function()
        local db = _G._EDM_DB
        return db and db.profile and db.profile.dm and db.profile.dm.iconStyle
    end)
    return ok and (style == nil or style == "spec")
end

local function ShowOriginal(region, yuiIcon)
    SafeMethod(region, "SetAlpha", 1)
    SafeSetShown(yuiIcon, false)
end

local function ResolveYUIIcon(nativeTexture)
    if nativeTexture == nil or not Icons.GetScopedSpecIcon then
        return nil
    end
    local ok, icon = pcall(Icons.GetScopedSpecIcon, nil, nativeTexture, ICON_SCOPE_ID)
    if ok and type(icon) == "table" and icon.custom then
        return icon
    end
    return nil
end

local function ApplyRegionIcon(region, yuiIcon, nativeTexture)
    if not region or not yuiIcon or not IsScopeEnabled() or not IsDefaultSpecStyle() then
        ShowOriginal(region, yuiIcon)
        return
    end

    local icon = ResolveYUIIcon(nativeTexture)
    if not icon or not Icons.ApplyIcon then
        ShowOriginal(region, yuiIcon)
        return
    end

    SafeMethod(region, "SetAlpha", 0)
    SafeSetShown(yuiIcon, SafeMethod(region, "IsShown") == true)

    local setID = icon.setId or (Icons.GetActiveIconSetID and Icons.GetActiveIconSetID()) or "blizzard"
    if yuiIcon.__yuiNativeTexture == nativeTexture and yuiIcon.__yuiIconSetID == setID then
        return
    end

    local ok = pcall(Icons.ApplyIcon, yuiIcon, icon)
    if not ok then
        ShowOriginal(region, yuiIcon)
        return
    end
    yuiIcon.__yuiNativeTexture = nativeTexture
    yuiIcon.__yuiIconSetID = setID
end

local function IsCandidateTexture(region)
    if not region or region.__yuiManagedSpecIcon then
        return false
    end
    if SafeMethod(region, "IsObjectType", "Texture") ~= true then
        return false
    end
    if SafeMethod(region, "GetDrawLayer") ~= "OVERLAY" then
        return false
    end
    local parent = SafeMethod(region, "GetParent")
    return parent and SafeMethod(parent, "IsObjectType", "StatusBar") == true
end

local function HookRegion(region)
    if not IsCandidateTexture(region) then
        return
    end

    local existing = managedIcons[region]
    if existing then
        ApplyRegionIcon(region, existing, region.__yuiOriginalTexture or SafeMethod(region, "GetTexture"))
        return
    end

    local parent = SafeMethod(region, "GetParent")
    if not parent or type(parent.CreateTexture) ~= "function" then
        return
    end

    local yuiIcon = SafeMethod(parent, "CreateTexture", nil, "OVERLAY", nil, 7)
    if not yuiIcon then
        return
    end
    yuiIcon.__yuiManagedSpecIcon = true
    SafeMethod(yuiIcon, "SetAllPoints", region)
    SafeSetShown(yuiIcon, false)

    local hooked = type(hooksecurefunc) == "function"
        and pcall(hooksecurefunc, region, "SetTexture", function(self, newTexture)
            local overlay = managedIcons[self]
            if not overlay then return end
            self.__yuiOriginalTexture = newTexture
            ApplyRegionIcon(self, overlay, newTexture)
        end)
    if not hooked then
        SafeSetShown(yuiIcon, false)
        return
    end

    pcall(hooksecurefunc, region, "Show", function(self)
        local overlay = managedIcons[self]
        if overlay then
            ApplyRegionIcon(self, overlay, self.__yuiOriginalTexture or SafeMethod(self, "GetTexture"))
        end
    end)
    pcall(hooksecurefunc, region, "Hide", function(self)
        local overlay = managedIcons[self]
        if overlay then
            SafeSetShown(overlay, false)
        end
    end)

    managedIcons[region] = yuiIcon
    region.__yuiOriginalTexture = SafeMethod(region, "GetTexture")
    ApplyRegionIcon(region, yuiIcon, region.__yuiOriginalTexture)
end

local function ScanFrame(frame, visited, depth)
    if not frame or visited[frame] or depth > MAX_SCAN_DEPTH then
        return
    end
    visited[frame] = true

    for _, region in ipairs(SafeMethodList(frame, "GetRegions") or {}) do
        HookRegion(region)
    end
    for _, child in ipairs(SafeMethodList(frame, "GetChildren") or {}) do
        ScanFrame(child, visited, depth + 1)
    end
end

local function IsMeterElementKey(key)
    return type(key) == "string" and strsub(key, 1, #ELEMENT_PREFIX) == ELEMENT_PREFIX
end

local function GetElementFrame(element, key)
    if type(element) ~= "table" or type(element.getFrame) ~= "function" then
        return nil
    end
    local ok, frame = pcall(element.getFrame, key)
    if ok then
        return frame
    end
    return nil
end

local function RescanAndRefresh()
    local provider = _G.EllesmereUI
    local registry = type(provider) == "table" and provider._unlockRegisteredElements or nil
    if type(registry) ~= "table" then
        return
    end

    local visited = {}
    for key, element in pairs(registry) do
        if IsMeterElementKey(key) then
            local frame = GetElementFrame(element, key)
            if frame then
                ScanFrame(frame, visited, 0)
            end
        end
    end
end

local function QueueRescan()
    if scanScheduled then return end
    scanScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            scanScheduled = false
            RescanAndRefresh()
        end)
    else
        scanScheduled = false
        RescanAndRefresh()
    end
end

local function ContainsMeterElement(elements)
    if type(elements) ~= "table" then return false end
    for _, element in ipairs(elements) do
        if type(element) == "table" and IsMeterElementKey(element.key) then
            return true
        end
    end
    return false
end

local function HookRegistration()
    if registerHooked or type(hooksecurefunc) ~= "function" then
        return registerHooked
    end
    local provider = _G.EllesmereUI
    if type(provider) ~= "table" or type(provider.RegisterUnlockElements) ~= "function" then
        return false
    end

    local ok = pcall(hooksecurefunc, provider, "RegisterUnlockElements", function(_, elements, folder)
        if folder == ADDON_NAME or ContainsMeterElement(elements) then
            QueueRescan()
        end
    end)
    registerHooked = ok
    return ok
end

local function Start()
    HookRegistration()
    QueueRescan()
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", Start)
    YUI.Event:On("ADDON_LOADED", function(_, addonName)
        if addonName == ADDON_NAME or addonName == "EllesmereUI" then
            Start()
        end
    end)
    YUI.Event:On("PLAYER_LOGIN", Start)
    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", QueueRescan)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == ICON_SCOPE_ID then
            QueueRescan()
        end
    end)
end
