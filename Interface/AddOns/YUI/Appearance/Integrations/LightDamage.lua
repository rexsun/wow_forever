local _, YUI = ...
if not YUI then return end

local Icons = YUI.API and YUI.API.Icons
local ICON_SCOPE_ID = "light_damage"
if not Icons then return end

local hooksecurefunc = hooksecurefunc
local type = type
local ipairs = ipairs
local pcall = pcall
local strlower = string.lower
local strsub = string.sub
local strfind = string.find
local gsub = string.gsub

local checkTimer
local rescanSerial = 0
local yuiIcons = {}
local hookedRegions = {}
local MAX_SCAN_DEPTH = 24
local LIGHT_DAMAGE_ICON_PREFIX = "interface\\addons\\lightdamage\\textures\\icons\\"
local LIGHT_DAMAGE_TEXTURE_PREFIX = "interface\\addons\\lightdamage\\textures\\"

local LIGHT_DAMAGE_SPEC_STEMS = {
    mage_touchofthearchmage = 62,
    mage_firedup = 63,
    mage_handoffrost = 64,
    paladin_beaconofthesavior = 65,
    paladin_gloryofthevanguard = 66,
    paladin_lightwithin = 70,
    warrior_masterofwarfare = 71,
    warrior_rampagingberserker = 72,
    warrior_phalanx = 73,
    druid_ascendanceeclipses = 102,
    druid_unseenpredator = 103,
    druid_wildguardian = 104,
    druid_everbloom = 105,
    deathknight_danceofmidnight = 250,
    deathknight_chosenofthefrostbrood = 251,
    deathknight_forbiddenknowledge = 252,
    hunter_killfrenzy = 253,
    hunter_deadlyinsight = 254,
    hunter_raptorswipe = 255,
    priest_voidshield = 256,
    priest_benediction = 257,
    priest_voidapparitions = 258,
    rogue_ancientarts = 259,
    rogue_gravedigger = 260,
    rogue_implacable = 261,
    shaman_feedbackloop = 262,
    shaman_stormunleashed = 263,
    shaman_stormstreamtotem = 264,
    warlock_shadowsofnathreza = 265,
    warlock_dominionofargus = 266,
    warlock_embersofnihilam = 267,
    monk_bringmeanother = 268,
    monk_tigereyebrew = 269,
    monk_spiritfont = 270,
    demonhunter_eternalhunt = 577,
    demonhunter_untetheredrage = 581,
    demonhunter_midnight = 1480,
    evoker_risingfury = 1467,
    evoker_merithrasblessing = 1468,
    evoker_duplicate = 1473,
}

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
    if not region then return end
    if shown then
        SafeMethod(region, "Show")
    else
        SafeMethod(region, "Hide")
    end
end

local function NormalizeTexturePath(texture)
    if type(texture) ~= "string" or texture == "" then
        return nil
    end
    return strlower((gsub(texture, "/", "\\")))
end

local function StripTextureExtension(value)
    if type(value) ~= "string" then
        return nil
    end
    value = gsub(value, "%.blp$", "")
    value = gsub(value, "%.tga$", "")
    value = gsub(value, "%.dds$", "")
    return value
end

local function StartsWith(value, prefix)
    return type(value) == "string" and strsub(value, 1, #prefix) == prefix
end

local function GetLightDamageSpecID(texture)
    local path = NormalizeTexturePath(texture)
    if not StartsWith(path, LIGHT_DAMAGE_ICON_PREFIX) then
        return nil
    end

    local rest = strsub(path, #LIGHT_DAMAGE_ICON_PREFIX + 1)
    local slash = strfind(rest, "\\", 1, true)
    if not slash then
        return nil
    end

    local stem = StripTextureExtension(strsub(rest, slash + 1))
    return LIGHT_DAMAGE_SPEC_STEMS[stem]
end

local function IsLightDamageChromeTexture(texture)
    local path = NormalizeTexturePath(texture)
    return StartsWith(path, LIGHT_DAMAGE_TEXTURE_PREFIX)
        and not StartsWith(path, LIGHT_DAMAGE_ICON_PREFIX)
end

local function IsScopeEnabled()
    if Icons.IsIconScopeEnabled then
        return Icons.IsIconScopeEnabled(ICON_SCOPE_ID)
    end
    return true
end

local function IsLightDamageLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("LightDamage") or _G.LightDamageFrame ~= nil
    end
    return _G.LightDamageFrame ~= nil
end

local function ShowOriginal(region, yIcon)
    if region then
        SafeMethod(region, "SetAlpha", 1)
    end
    if yIcon then
        SafeSetShown(yIcon, false)
    end
end

local function ResolveYUIIcon(newTex)
    local specID = GetLightDamageSpecID(newTex)
    if specID then
        if Icons.GetScopedSpecIcon then
            return Icons.GetScopedSpecIcon(specID, nil, ICON_SCOPE_ID), true
        elseif Icons.GetSpecIcon then
            return Icons.GetSpecIcon(specID), true
        end
    end

    if Icons.GetSpecIconByNativeTexture then
        local icon = Icons.GetSpecIconByNativeTexture(newTex)
        if icon and icon.custom then
            return icon, true
        end
    end

    return nil, false
end

local function ApplyRegionIcon(region, yIcon, newTex)
    if not region or not yIcon or not IsScopeEnabled() then
        ShowOriginal(region, yIcon)
        return
    end

    local icon, shouldOverlay = ResolveYUIIcon(newTex)
    if not shouldOverlay or not icon or not Icons.ApplyIcon then
        ShowOriginal(region, yIcon)
        return
    end

    SafeMethod(region, "SetAlpha", 0)
    SafeSetShown(yIcon, SafeMethod(region, "IsShown") == true)

    local setId = icon.setId or (Icons.GetActiveIconSetID and Icons.GetActiveIconSetID()) or "blizzard"
    if yIcon.lastTex == newTex and yIcon.lastTheme == setId then
        return
    end
    yIcon.lastTex = newTex
    yIcon.lastTheme = setId

    local ok = pcall(Icons.ApplyIcon, yIcon, icon)
    if not ok then
        ShowOriginal(region, yIcon)
    end
end

local function IsCandidateTexture(region)
    if not region or yuiIcons[region] or region.__yuiManagedSpecIcon or region.__yuiLightDamageHooked then
        return false
    end
    if SafeMethod(region, "IsObjectType", "Texture") ~= true then
        return false
    end
    if SafeMethod(region, "GetDrawLayer") ~= "OVERLAY" then
        return false
    end
    if IsLightDamageChromeTexture(SafeMethod(region, "GetTexture")) then
        return false
    end
    return true
end

local function HookRegion(region)
    if not IsCandidateTexture(region) then
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

    local hookedSetTexture = type(hooksecurefunc) == "function"
        and pcall(hooksecurefunc, region, "SetTexture", function(self, newTex)
            local icon = yuiIcons[self]
            if not icon then return end
            self.__yuiOriginalID = newTex
            ApplyRegionIcon(self, icon, newTex)
        end)

    if not hookedSetTexture then
        SafeSetShown(yuiIcon, false)
        return
    end

    pcall(hooksecurefunc, region, "Show", function(self)
        local icon = yuiIcons[self]
        if icon then
            ApplyRegionIcon(self, icon, self.__yuiOriginalID or SafeMethod(self, "GetTexture"))
        end
    end)

    pcall(hooksecurefunc, region, "Hide", function(self)
        local icon = yuiIcons[self]
        if icon then
            SafeSetShown(icon, false)
        end
    end)

    region.__yuiLightDamageHooked = true
    yuiIcons[region] = yuiIcon
    hookedRegions[#hookedRegions + 1] = region

    local currentTex = SafeMethod(region, "GetTexture")
    if currentTex then
        region.__yuiOriginalID = currentTex
        ApplyRegionIcon(region, yuiIcon, currentTex)
    end
end

local function HookAllIcons(frame, visited, depth)
    if not frame or visited[frame] or (depth or 0) > MAX_SCAN_DEPTH then
        return
    end
    visited[frame] = true

    local regions = SafeMethodList(frame, "GetRegions") or {}
    for _, region in ipairs(regions) do
        HookRegion(region)
    end

    local children = SafeMethodList(frame, "GetChildren") or {}
    for _, child in ipairs(children) do
        if child then
            HookAllIcons(child, visited, (depth or 0) + 1)
        end
    end
end

local function RefreshAllIcons()
    for _, region in ipairs(hookedRegions) do
        local yIcon = yuiIcons[region]
        if yIcon then
            ApplyRegionIcon(region, yIcon, region.__yuiOriginalID or SafeMethod(region, "GetTexture"))
        end
    end
end

local function RescanAndRefresh()
    local frame = _G.LightDamageFrame
    if frame then
        HookAllIcons(frame, {}, 0)
    end
    RefreshAllIcons()
end

local function QueueRescan(delay, serial)
    if not C_Timer or not C_Timer.After then
        return
    end
    C_Timer.After(delay, function()
        if serial == rescanSerial then
            RescanAndRefresh()
        end
    end)
end

local function QueueDelayedRescans()
    if not C_Timer or not C_Timer.After then
        return
    end
    rescanSerial = rescanSerial + 1
    local serial = rescanSerial
    QueueRescan(0, serial)
    QueueRescan(0.2, serial)
    QueueRescan(1, serial)
end

local function StopWaiting()
    if checkTimer then
        checkTimer:Cancel()
        checkTimer = nil
    end
end

local function TryHook()
    if not IsScopeEnabled() then
        StopWaiting()
        RefreshAllIcons()
        return
    end
    if not IsLightDamageLoaded() then
        return
    end

    if _G.LightDamageFrame then
        RescanAndRefresh()
        StopWaiting()
        QueueDelayedRescans()
    end
end

local function StartWaiting()
    if not IsScopeEnabled() then
        RefreshAllIcons()
        return
    end
    if not IsLightDamageLoaded() then
        return
    end

    TryHook()
    if not _G.LightDamageFrame and not checkTimer and C_Timer and C_Timer.NewTicker then
        checkTimer = C_Timer.NewTicker(1, TryHook)
    end
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        StartWaiting()
    end)

    YUI.Event:On("ADDON_LOADED", function(_, addonName)
        if addonName == "LightDamage" then
            StartWaiting()
        end
    end)
    YUI.Event:On("PLAYER_LOGIN", function()
        StartWaiting()
    end)
    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", function()
        RescanAndRefresh()
    end)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == ICON_SCOPE_ID then
            StartWaiting()
            RescanAndRefresh()
        end
    end)
end
