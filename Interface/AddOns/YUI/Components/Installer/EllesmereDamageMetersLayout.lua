local _, YUI = ...

YUI.InstallerLayoutAligner = YUI.InstallerLayoutAligner or {}
local Layout = YUI.InstallerLayoutAligner
YUI.EllesmereDamageMetersLayout = Layout

local DAMAGE_METERS_ADDON = "EllesmereUIDamageMeters"
local UNIT_FRAMES_ADDON = "EllesmereUIUnitFrames"
local RAID_FRAMES_ADDON = "EllesmereUIRaidFrames"
local ELLESMERE_MINIMAP_ADDON = "EllesmereUIMinimap"
local ENHANCE_QOL_ADDON = "EnhanceQoL"
local WINDOW_KEY_PREFIX = "EDM_Win"
local WINDOW_FRAME_PREFIX = "EllesmereUIDMFrame"
local MAX_WINDOWS = 5
local BOTTOM_INSET = 23
local MINIMAP_GAP = 10
local AURA_BAR_GAP = 8

local PLAYER_AURA_BUFFS_KEY = "PAB_Buffs"
local PLAYER_AURA_DEBUFFS_KEY = "PAB_Debuffs"
local ELLESMERE_MINIMAP_KEY = "EBS_Minimap"
local ELLESMERE_PARTY_KEY = "RF_PartyFrames"
local ENHANCE_QOL_PARTY_EDIT_MODE_ID = "EQOL_UF_GROUP_PARTY"

local PARTY_PRESETS = {
    ellesmere = {
        right = { point = "CENTER", relPoint = "CENTER", x = 446.4761980796349, y = 20.57142892175792 },
        left = { point = "CENTER", relPoint = "CENTER", x = -446.4761980796349, y = 20.57142892175792 },
    },
    enhanceQoL = {
        right = { point = "CENTER", relPoint = "CENTER", relativeTo = "UIParent", x = 400, y = 130 },
        left = { point = "CENTER", relPoint = "CENTER", relativeTo = "UIParent", x = -400, y = 130 },
    },
}

local TARGET_LABELS = {
    damageMeters = "EllesmereUI 伤害统计",
    playerAuras = "EllesmereUI 玩家增益/减益",
    ellesmereParty = "EllesmereUI 小队框架",
    enhanceQoLParty = "EnhanceQoL 小队框架",
}

local function IsAddonLoaded(name)
    if not (C_AddOns
        and type(C_AddOns.IsAddOnLoaded) == "function"
        and type(name) == "string")
    then
        return false
    end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and loaded == true
end

local function CopyPosition(position)
    return {
        point = position.point,
        relPoint = position.relPoint,
        x = position.x,
        y = position.y,
    }
end

local function GetEllesmereProvider()
    return type(_G.EllesmereUI) == "table" and _G.EllesmereUI or nil
end

local function GetEllesmereModule(addonName)
    local provider = GetEllesmereProvider()
    local modules = provider and provider._ModuleNS
    return type(modules) == "table" and type(modules[addonName]) == "table"
        and modules[addonName] or nil
end

local function GetEllesmereAddon(addonName)
    local provider = GetEllesmereProvider()
    local lite = provider and provider.Lite
    if type(lite) ~= "table" or type(lite.GetAddon) ~= "function" then return nil end
    local ok, addon = pcall(lite.GetAddon, addonName, true)
    return ok and type(addon) == "table" and addon or nil
end

local function GetUnlockAnchors(create)
    local db = _G.EllesmereUIDB
    if type(db) ~= "table" then return nil end
    if type(db.unlockAnchors) ~= "table" then
        if not create then return nil end
        db.unlockAnchors = {}
    end
    return db.unlockAnchors
end

local function CommitAnchorChanges(changed)
    if not changed then return end
    local provider = GetEllesmereProvider()
    if provider then
        provider._anchorLinksStamp = (provider._anchorLinksStamp or 0) + 1
    end
end

local function ClearUnlockAnchor(anchors, key)
    if type(anchors) ~= "table" or anchors[key] == nil then return false end
    anchors[key] = nil
    return true
end

local function AnchorMatches(info, target, side, offsetX, offsetY)
    return type(info) == "table"
        and info.target == target
        and info.side == side
        and info.offsetX == offsetX
        and info.offsetY == offsetY
        and info.fallback == nil
        and info.refX == nil
        and info.refY == nil
        and info.edgeOffX == nil
        and info.edgeOffY == nil
        and info.refFor == nil
end

local function SetUnlockAnchor(anchors, key, target, side, offsetX, offsetY)
    if AnchorMatches(anchors[key], target, side, offsetX, offsetY) then
        return false
    end
    anchors[key] = {
        target = target,
        side = side,
        offsetX = offsetX,
        offsetY = offsetY,
    }
    return true
end

local function GetActiveWindows()
    local db = _G._EDM_DB
    local profile = type(db) == "table" and db.profile
    local dm = type(profile) == "table" and profile.dm
    local windows = type(dm) == "table" and dm.windows
    return type(windows) == "table" and windows or nil
end

local function IsSameAnchor(info, target)
    return type(info) == "table"
        and info.target == target
        and info.side == "TOP"
        and info.offsetX == 0
        and info.offsetY == 0
        and info.fallback == nil
end

function Layout:IsAvailable()
    return self:GetCapabilities().any == true
end

local function CanApplyDamageMeters()
    if not IsAddonLoaded(DAMAGE_METERS_ADDON) then return false end

    local windows = GetActiveWindows()
    local rootFrame = _G[WINDOW_FRAME_PREFIX .. 1]
    local provider = _G.EllesmereUI
    return type(windows) == "table"
        and type(windows[1]) == "table"
        and rootFrame ~= nil
        and type(rootFrame.ClearAllPoints) == "function"
        and type(rootFrame.SetPoint) == "function"
        and type(provider) == "table"
        and type(provider.ReapplyUnlockAnchor) == "function"
        and type(_G.EllesmereUIDB) == "table"
        and UIParent ~= nil
end

function Layout:ApplyDamageMeters()
    if not IsAddonLoaded(DAMAGE_METERS_ADDON) then
        return false, "not-loaded"
    end

    local windows = GetActiveWindows()
    local provider = _G.EllesmereUI
    local providerDB = _G.EllesmereUIDB
    if not windows
        or type(provider) ~= "table"
        or type(provider.ReapplyUnlockAnchor) ~= "function"
        or type(providerDB) ~= "table"
        or not UIParent
    then
        return false, "not-ready"
    end

    local live = {}
    for index = 1, MAX_WINDOWS do
        local frame = _G[WINDOW_FRAME_PREFIX .. index]
        if frame
            and type(frame.ClearAllPoints) == "function"
            and type(frame.SetPoint) == "function"
            and type(windows[index]) == "table"
        then
            live[#live + 1] = {
                index = index,
                key = WINDOW_KEY_PREFIX .. index,
                frame = frame,
                db = windows[index],
            }
        end
    end

    if #live == 0 or live[1].index ~= 1 then
        return false, "no-windows"
    end

    local anchors = GetUnlockAnchors(true)

    local linksChanged = false
    for order, window in ipairs(live) do
        if order == 1 then
            linksChanged = ClearUnlockAnchor(anchors, window.key) or linksChanged
        else
            local target = live[order - 1].key
            if not IsSameAnchor(anchors[window.key], target) then
                anchors[window.key] = {
                    target = target,
                    side = "TOP",
                    offsetX = 0,
                    offsetY = 0,
                }
                linksChanged = true
            end
        end
    end

    CommitAnchorChanges(linksChanged)

    local root = live[1]
    root.db.position = {
        point = "BOTTOMRIGHT",
        relPoint = "BOTTOMRIGHT",
        x = 0,
        y = BOTTOM_INSET,
    }
    local rootOK = pcall(function()
        root.frame:ClearAllPoints()
        root.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, BOTTOM_INSET)
    end)
    if not rootOK then return false, "root-position-failed" end

    for order = 2, #live do
        if not pcall(provider.ReapplyUnlockAnchor, live[order].key) then
            return false, "anchor-reapply-failed"
        end
    end

    return true, #live
end

local function GetPlayerAuraContext()
    if not IsAddonLoaded(UNIT_FRAMES_ADDON) or not UIParent then return nil end
    local namespace = GetEllesmereModule(UNIT_FRAMES_ADDON)
    local profile = namespace and namespace.db and namespace.db.profile
    local settings = profile and profile.playerAuraBars
    local buffs = _G.EllesmereUIPlayerAuraBars_Buffs
    local debuffs = _G.EllesmereUIPlayerAuraBars_Debuffs
    local provider = GetEllesmereProvider()
    if type(settings) ~= "table"
        or type(namespace.PAB_ApplyLiveConfig) ~= "function"
        or not buffs or not debuffs
        or type(buffs.GetWidth) ~= "function" or type(buffs.GetHeight) ~= "function"
        or type(debuffs.GetWidth) ~= "function" or type(debuffs.GetHeight) ~= "function"
        or type(provider) ~= "table"
        or type(provider.ReapplyUnlockAnchor) ~= "function"
        or type(_G.EllesmereUIDB) ~= "table"
    then
        return nil
    end

    local ymap = YUI and YUI.YMap
    local ymapMinimap = ymap and ymap.Minimap
    local ymapHolder = _G.YMapMinimapHolder
    if ymapMinimap and ymapMinimap.active == true
        and ymapHolder and type(ymapHolder.GetLeft) == "function"
    then
        return {
            mode = "ymap",
            namespace = namespace,
            settings = settings,
            buffs = buffs,
            debuffs = debuffs,
            minimap = ymapHolder,
            provider = provider,
        }
    end

    local minimapAddon = GetEllesmereAddon(ELLESMERE_MINIMAP_ADDON)
    local minimapProfile = minimapAddon and minimapAddon.db and minimapAddon.db.profile
    local minimapSettings = minimapProfile and minimapProfile.minimap
    local minimap = _G.Minimap
    if IsAddonLoaded(ELLESMERE_MINIMAP_ADDON)
        and type(minimapSettings) == "table" and minimapSettings.enabled == true
        and minimap and type(minimap.GetLeft) == "function"
    then
        return {
            mode = "ellesmere",
            namespace = namespace,
            settings = settings,
            buffs = buffs,
            debuffs = debuffs,
            minimap = minimap,
            provider = provider,
        }
    end
    return nil
end

local function ReadFrameRect(frame)
    if not frame or not UIParent then return nil end
    local left = frame.GetLeft and frame:GetLeft()
    local top = frame.GetTop and frame:GetTop()
    local width = frame.GetWidth and frame:GetWidth()
    local height = frame.GetHeight and frame:GetHeight()
    if type(left) ~= "number" or type(top) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0
    then
        return nil
    end

    local uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or uiScale
    if type(uiScale) ~= "number" or uiScale <= 0 then uiScale = 1 end
    if type(frameScale) ~= "number" or frameScale <= 0 then frameScale = uiScale end
    local ratio = frameScale / uiScale
    return {
        left = left * ratio,
        top = top * ratio,
        width = width * ratio,
        height = height * ratio,
    }
end

local function ApplyPlayerAuraLive(namespace)
    local buffsOK = pcall(namespace.PAB_ApplyLiveConfig, true)
    local debuffsOK = pcall(namespace.PAB_ApplyLiveConfig, false)
    return buffsOK and debuffsOK
end

local function ApplyPlayerAurasToEllesmereMinimap(context, minimapRect, buffRect, debuffRect)
    local anchors = GetUnlockAnchors(true)
    local buffsOffsetY = (minimapRect.height - buffRect.height) / 2
    local debuffsOffsetY = minimapRect.height / 2
        - buffRect.height - AURA_BAR_GAP - debuffRect.height / 2
    local linksChanged = false
    linksChanged = SetUnlockAnchor(
        anchors,
        PLAYER_AURA_BUFFS_KEY,
        ELLESMERE_MINIMAP_KEY,
        "LEFT",
        -MINIMAP_GAP,
        buffsOffsetY
    ) or linksChanged
    linksChanged = SetUnlockAnchor(
        anchors,
        PLAYER_AURA_DEBUFFS_KEY,
        ELLESMERE_MINIMAP_KEY,
        "LEFT",
        -MINIMAP_GAP,
        debuffsOffsetY
    ) or linksChanged
    CommitAnchorChanges(linksChanged)

    if not ApplyPlayerAuraLive(context.namespace) then
        return false, "live-refresh-failed"
    end
    local buffsOK = pcall(context.provider.ReapplyUnlockAnchor, PLAYER_AURA_BUFFS_KEY)
    local debuffsOK = pcall(context.provider.ReapplyUnlockAnchor, PLAYER_AURA_DEBUFFS_KEY)
    return buffsOK and debuffsOK, buffsOK and debuffsOK and "ellesmere" or "anchor-reapply-failed"
end

local function ApplyPlayerAurasToYMap(context, minimapRect, buffRect, debuffRect)
    local parentRect = ReadFrameRect(UIParent)
    if not parentRect then return false, "parent-geometry-unavailable" end

    local right = minimapRect.left - MINIMAP_GAP
    local buffPosition = {
        point = "TOPLEFT",
        relPoint = "TOPLEFT",
        x = right - buffRect.width - parentRect.left,
        y = minimapRect.top - parentRect.top,
    }
    local debuffPosition = {
        point = "TOPLEFT",
        relPoint = "TOPLEFT",
        x = right - debuffRect.width - parentRect.left,
        y = minimapRect.top - buffRect.height - AURA_BAR_GAP - parentRect.top,
    }
    context.settings.buffsPos = buffPosition
    context.settings.debuffsPos = debuffPosition

    local anchors = GetUnlockAnchors(true)
    local linksChanged = ClearUnlockAnchor(anchors, PLAYER_AURA_BUFFS_KEY)
    linksChanged = ClearUnlockAnchor(anchors, PLAYER_AURA_DEBUFFS_KEY) or linksChanged
    CommitAnchorChanges(linksChanged)

    if not ApplyPlayerAuraLive(context.namespace) then
        return false, "live-refresh-failed"
    end
    return true, "ymap"
end

function Layout:ApplyPlayerAuras()
    local context = GetPlayerAuraContext()
    if not context then return false, "not-ready" end
    local minimapRect = ReadFrameRect(context.minimap)
    local buffRect = ReadFrameRect(context.buffs)
    local debuffRect = ReadFrameRect(context.debuffs)
    if not minimapRect or not buffRect or not debuffRect then
        return false, "geometry-unavailable"
    end
    if context.mode == "ymap" then
        return ApplyPlayerAurasToYMap(context, minimapRect, buffRect, debuffRect)
    end
    return ApplyPlayerAurasToEllesmereMinimap(context, minimapRect, buffRect, debuffRect)
end

local function GetEllesmerePartyContext()
    if not IsAddonLoaded(RAID_FRAMES_ADDON) or not UIParent then return nil end
    local namespace = GetEllesmereModule(RAID_FRAMES_ADDON)
    local profile = namespace and namespace.db and namespace.db.profile
    local frame = namespace and namespace._partyContainerFrame
    if type(profile) ~= "table"
        or type(namespace.ReloadPartyFrames) ~= "function"
        or not frame
        or type(frame.ClearAllPoints) ~= "function"
        or type(frame.SetPoint) ~= "function"
        or type(_G.EllesmereUIDB) ~= "table"
    then
        return nil
    end
    return { namespace = namespace, profile = profile, frame = frame }
end

local function GetEnhanceQoLPartyContext()
    if not IsAddonLoaded(ENHANCE_QOL_ADDON) then return nil end
    local addon = _G.EnhanceQoL
    local groupFrames = addon and addon.Aura and addon.Aura.UF and addon.Aura.UF.GroupFrames
    local editMode = addon and addon.EditMode
    if type(groupFrames) ~= "table"
        or type(groupFrames.GetConfig) ~= "function"
        or type(groupFrames.SyncGroupEditModePositionValues) ~= "function"
        or type(groupFrames.ApplyHeaderAttributes) ~= "function"
        or type(editMode) ~= "table"
        or type(editMode.RefreshFrame) ~= "function"
    then
        return nil
    end
    local ok, config = pcall(groupFrames.GetConfig, groupFrames, "party")
    if not ok or type(config) ~= "table" then return nil end
    return { addon = addon, groupFrames = groupFrames, config = config }
end

function Layout:ApplyEllesmereParty(side)
    local context = GetEllesmerePartyContext()
    if not context then return false, "not-ready" end
    local preset = PARTY_PRESETS.ellesmere[side] or PARTY_PRESETS.ellesmere.right
    context.profile.partyUnlockPos = CopyPosition(preset)

    local anchors = GetUnlockAnchors(true)
    local linksChanged = ClearUnlockAnchor(anchors, ELLESMERE_PARTY_KEY)
    CommitAnchorChanges(linksChanged)

    local namespace = context.namespace
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat and not pcall(function()
        context.frame:ClearAllPoints()
        context.frame:SetPoint(preset.point, UIParent, preset.relPoint, preset.x, preset.y)
    end) then
        return false, "live-position-failed"
    end
    if type(namespace._RFRegisterUnlock) == "function"
        and not pcall(namespace._RFRegisterUnlock)
    then
        return false, "unlock-refresh-failed"
    end
    if inCombat then
        local provider = GetEllesmereProvider()
        if type(provider._applySavedPositions) ~= "function"
            or not pcall(provider._applySavedPositions)
        then
            return false, "combat-defer-failed"
        end
    end
    if not pcall(namespace.ReloadPartyFrames) then
        return false, "layout-refresh-failed"
    end
    return true, side
end

function Layout:ApplyEnhanceQoLParty(side)
    local context = GetEnhanceQoLPartyContext()
    if not context then return false, "not-ready" end
    local preset = PARTY_PRESETS.enhanceQoL[side] or PARTY_PRESETS.enhanceQoL.right
    local config = context.config
    config.point = preset.point
    config.relativePoint = preset.relPoint
    config.relativeTo = preset.relativeTo
    config.x = preset.x
    config.y = preset.y

    local groupFrames = context.groupFrames
    local syncOK = pcall(
        groupFrames.SyncGroupEditModePositionValues,
        "party",
        ENHANCE_QOL_PARTY_EDIT_MODE_ID,
        config
    )
    local refreshOK = pcall(groupFrames.ApplyHeaderAttributes, groupFrames, "party")
    local editMode = context.addon.EditMode
    local editModeOK = pcall(
        editMode.RefreshFrame,
        editMode,
        ENHANCE_QOL_PARTY_EDIT_MODE_ID
    )
    if not syncOK then
        return false, "edit-mode-sync-failed"
    elseif not refreshOK or not editModeOK then
        return false, "layout-refresh-failed"
    end
    return true, side
end

function Layout:GetCapabilities()
    local capabilities = {
        damageMeters = CanApplyDamageMeters(),
        playerAuras = GetPlayerAuraContext() ~= nil,
        ellesmereParty = GetEllesmerePartyContext() ~= nil,
        enhanceQoLParty = GetEnhanceQoLPartyContext() ~= nil,
    }
    capabilities.hasPartyFrames = capabilities.ellesmereParty or capabilities.enhanceQoLParty
    capabilities.any = capabilities.damageMeters
        or capabilities.playerAuras
        or capabilities.hasPartyFrames
    return capabilities
end

local TARGETS = {
    {
        id = "damageMeters",
        available = function(capabilities) return capabilities.damageMeters end,
        apply = function() return Layout:ApplyDamageMeters() end,
    },
    {
        id = "playerAuras",
        available = function(capabilities) return capabilities.playerAuras end,
        apply = function() return Layout:ApplyPlayerAuras() end,
    },
    {
        id = "ellesmereParty",
        available = function(capabilities) return capabilities.ellesmereParty end,
        apply = function(side) return Layout:ApplyEllesmereParty(side) end,
    },
    {
        id = "enhanceQoLParty",
        available = function(capabilities) return capabilities.enhanceQoLParty end,
        apply = function(side) return Layout:ApplyEnhanceQoLParty(side) end,
    },
}

function Layout:Apply(options)
    options = type(options) == "table" and options or {}
    local partySide = options.partySide == "left" and "left" or "right"
    local capabilities = self:GetCapabilities()
    local summary = {
        partySide = partySide,
        applied = {},
        skipped = {},
        failed = {},
    }

    for _, target in ipairs(TARGETS) do
        if target.available(capabilities) then
            local callOK, applied, detail = pcall(target.apply, partySide)
            if callOK and applied == true then
                summary.applied[#summary.applied + 1] = {
                    id = target.id,
                    label = TARGET_LABELS[target.id],
                    detail = detail,
                }
            else
                summary.failed[#summary.failed + 1] = {
                    id = target.id,
                    label = TARGET_LABELS[target.id],
                    reason = callOK and detail or applied,
                }
            end
        else
            summary.skipped[#summary.skipped + 1] = {
                id = target.id,
                label = TARGET_LABELS[target.id],
            }
        end
    end

    local succeeded = #summary.applied > 0 and #summary.failed == 0
    return succeeded, summary
end
