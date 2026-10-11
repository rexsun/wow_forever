local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end
local GUI2 = YUI.GUI2
local YBar = YUI.YBar
local F = YUI.F
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local API = YUI.WOW_API
local CombatAPI = YUI.API and YUI.API.Combat or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local ItemAPI = YUI.API and YUI.API.Item or API
local SpellAPI = YUI.API and YUI.API.Spell or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local ChatInputAPI = YUI.API and YUI.API.ChatInput
local Module = YBar.Module:New("Teleports")

-- Constants
local HEARTHSTONE_ITEM_ID = 6948
-- local DARK_PORTAL_TOY_ID = 93672
local DARK_PORTAL_TOY_ID = 184871
local WORMHOLE_TOY_ID = 48933
local ANNOUNCE_DEFAULT_PREFIX = "[YUI]"
local ANNOUNCE_SCOPE_OFF = "off"
local ANNOUNCE_SCOPE_PORTALS = "portals"
local ANNOUNCE_SCOPE_DUNGEONS = "dungeons"
local ANNOUNCE_SCOPE_ALL = "all"
local ANNOUNCE_KIND_PORTAL = "portal"
local ANNOUNCE_KIND_DUNGEON = "dungeon"
local ANNOUNCE_PREVIEW_PARTY_COLOR = "ffaaaaff"
local ANNOUNCE_TRIGGER_CAST_START = "cast_start"
local ANNOUNCE_TRIGGER_CAST_SUCCESS = "cast_success"
local MenuFrame = nil

local function IsTeleportFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and
        not frame.errorText and frame.text and (frame.iconSlot or frame.icon) and
        frame.secure
end

local format = string.format
local tinsert = table.insert

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

local TP_MENU_NAME = YUI.F:GetGradientText(T("teleports.tooltip.title", "传送菜单"), {0.84, 0.41, 1}, {0.64, 0.21, 0.93})

local function IsValidAnnounceScope(scope)
    return scope == ANNOUNCE_SCOPE_OFF or scope == ANNOUNCE_SCOPE_PORTALS or
        scope == ANNOUNCE_SCOPE_DUNGEONS or scope == ANNOUNCE_SCOPE_ALL
end

local function IsValidAnnounceTrigger(trigger)
    return trigger == ANNOUNCE_TRIGGER_CAST_START or trigger == ANNOUNCE_TRIGGER_CAST_SUCCESS
end

function Module:NormalizeAnnouncePrefix()
    local prefix = self.db and self.db.announcePrefix
    if type(prefix) ~= "string" then
        prefix = ANNOUNCE_DEFAULT_PREFIX
    end
    return prefix
end

function Module:GetAnnounceTrigger()
    local trigger = self.db and self.db.announceTrigger or ANNOUNCE_TRIGGER_CAST_START
    if not IsValidAnnounceTrigger(trigger) then
        trigger = ANNOUNCE_TRIGGER_CAST_START
    end
    return trigger
end

function Module:NormalizeAnnouncementName(name)
    if type(name) ~= "string" then
        name = name and tostring(name) or ""
    end
    if name == "" then return nil end
    if name:match("^<.*>$") then return name end
    return "<" .. name .. ">"
end

function Module:GetDungeonAnnouncementName(itemData)
    if type(itemData) == "table" then
        local key = itemData.announceNameKey or itemData.mapKey or itemData.id
        if key then
            local fullName = L["teleports.announce.full_name." .. tostring(key)]
            if type(fullName) == "string" and fullName ~= "" then
                return fullName
            end
        end
        return itemData.announceName or itemData.text
    end
    return itemData
end

function Module:GetAnnouncementTargetName(kind, itemData)
    if kind == ANNOUNCE_KIND_DUNGEON then
        return self:GetDungeonAnnouncementName(itemData)
    end
    if type(itemData) == "table" then
        return itemData.announceName or itemData.text
    end
    return itemData
end

function Module:BuildAnnouncementMessage(kind, itemData, trigger)
    trigger = IsValidAnnounceTrigger(trigger) and trigger or self:GetAnnounceTrigger()
    local name = self:NormalizeAnnouncementName(self:GetAnnouncementTargetName(kind, itemData))
    if not name or name == "" then return nil end
    local body
    if kind == ANNOUNCE_KIND_PORTAL then
        if trigger == ANNOUNCE_TRIGGER_CAST_SUCCESS then
            body = T("teleports.announce.opened", "已开启传送门 %s", name)
        else
            body = T("teleports.announce.opening", "正在开启传送门 %s", name)
        end
    elseif kind == ANNOUNCE_KIND_DUNGEON then
        if trigger == ANNOUNCE_TRIGGER_CAST_SUCCESS then
            body = T("teleports.announce.arrived", "已传送至 %s", name)
        else
            body = T("teleports.announce.going", "正在前往 %s", name)
        end
    end
    if not body then return nil end

    local prefix = self:NormalizeAnnouncePrefix()
    if prefix ~= "" then
        return prefix .. " " .. body
    end
    return body
end

function Module:GetAnnouncementChannel()
    local resolver = ChatInputAPI and ChatInputAPI.ResolveGroupChatType
    return type(resolver) == "function" and resolver() or nil
end

function Module:ShouldAnnounce(kind)
    local scope = self.db and self.db.announceScope or ANNOUNCE_SCOPE_OFF
    if not IsValidAnnounceScope(scope) then
        scope = ANNOUNCE_SCOPE_OFF
    end
    if scope == ANNOUNCE_SCOPE_ALL then
        return kind == ANNOUNCE_KIND_PORTAL or kind == ANNOUNCE_KIND_DUNGEON
    elseif scope == ANNOUNCE_SCOPE_PORTALS then
        return kind == ANNOUNCE_KIND_PORTAL
    elseif scope == ANNOUNCE_SCOPE_DUNGEONS then
        return kind == ANNOUNCE_KIND_DUNGEON
    end
    return false
end

function Module:AnnounceTeleport(itemData, trigger)
    if not itemData or not self:ShouldAnnounce(itemData.announceKind) then return end
    local channel = self:GetAnnouncementChannel()
    if not channel or not SendChatMessage then return end

    local message = self:BuildAnnouncementMessage(itemData.announceKind, itemData, trigger)
    if message and message ~= "" then
        SendChatMessage(message, channel)
    end
end

function Module:HandleAnnouncementSpellcastEvent(event, spellID)
    local itemData = self:GetSpellcastAnnouncementData(spellID)
    if not itemData then return end

    local trigger = self:GetAnnounceTrigger()
    if event == "UNIT_SPELLCAST_START" then
        if trigger ~= ANNOUNCE_TRIGGER_CAST_START then return end
        self:AnnounceTeleport(itemData, ANNOUNCE_TRIGGER_CAST_START)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if trigger ~= ANNOUNCE_TRIGGER_CAST_SUCCESS then return end
        self:AnnounceTeleport(itemData, ANNOUNCE_TRIGGER_CAST_SUCCESS)
    end
end

function Module:GetAnnouncementPreviewPlayerName()
    local name = T("teleports.announce.preview_player_name", "玩家名")
    if UnitAPI and UnitAPI.UnitName then
        name = UnitAPI.UnitName("player") or name
    elseif UnitName then
        name = UnitName("player") or name
    end

    local classFilename
    if UnitAPI and UnitAPI.UnitClass then
        local _
        _, classFilename = UnitAPI.UnitClass("player")
    elseif UnitClass then
        local _
        _, classFilename = UnitClass("player")
    end

    local colorHex = ANNOUNCE_PREVIEW_PARTY_COLOR
    local classColor = classFilename and UnitAPI and UnitAPI.GetClassColor and UnitAPI.GetClassColor(classFilename)
    if classColor and classColor.GenerateHexColor then
        colorHex = classColor:GenerateHexColor()
    elseif classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename] then
        local color = RAID_CLASS_COLORS[classFilename]
        colorHex = color.GenerateHexColor and color:GenerateHexColor() or color.colorStr or colorHex
    end

    return "|c" .. colorHex .. "[" .. name .. "]|r"
end

function Module:BuildAnnouncementPreviewLine(message)
    local channelName = T("teleports.announce.preview_party_channel", "队伍")
    return "|c" .. ANNOUNCE_PREVIEW_PARTY_COLOR .. "[" .. channelName .. "]|r " ..
        self:GetAnnouncementPreviewPlayerName() .. ": |c" .. ANNOUNCE_PREVIEW_PARTY_COLOR .. (message or "") .. "|r"
end

function Module:GetAnnouncementPreview(kind)
    local name
    if kind == ANNOUNCE_KIND_PORTAL then
        name = T("teleports.announce.preview_portal_name", "传送门名字")
    else
        name = T("teleports.announce.preview_dungeon_name", "副本名字")
    end
    return self:BuildAnnouncementPreviewLine(self:BuildAnnouncementMessage(kind, name, self:GetAnnounceTrigger()))
end

function Module:RefreshAnnouncementPreview()
    if not self.announcePreviewLines then return end
    if self.announcePreviewLines.dungeon then
        self.announcePreviewLines.dungeon:SetText(self:GetAnnouncementPreview(ANNOUNCE_KIND_DUNGEON))
    end
    if self.announcePreviewLines.portal then
        self.announcePreviewLines.portal:SetText(self:GetAnnouncementPreview(ANNOUNCE_KIND_PORTAL))
    end
end

function Module:RenderAnnouncementPreview(parent, x, y, width)
    width = width or 360
    local labelWidth = GUI2.GetMetric and GUI2:GetMetric("layout.form.labelWidth", 120) or 120
    local rowHeight = GUI2.GetMetric and GUI2:GetMetric("layout.form.rowHeight", 32) or 32
    local previewTop = math.max(rowHeight - 6, 24)
    local lineHeight = math.max(rowHeight, 34)
    local lineGap = 0
    local height = previewTop + lineHeight * 2 + lineGap + 2

    local frame = GUI2:CreateFrame(parent, { width = width, height = height })
    frame:SetPoint("TOPLEFT", x, y)

    local title = GUI2:CreateText(frame, T("teleports.settings.announce_preview", "预览"), "font.size.md", "color.text.primary", "LEFT")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
    title:SetWidth(labelWidth)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local dungeon = GUI2:CreateText(frame, self:GetAnnouncementPreview(ANNOUNCE_KIND_DUNGEON), "font.size.md", "color.text.primary", "LEFT")
    dungeon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -previewTop)
    dungeon:SetSize(width, lineHeight)
    dungeon:SetJustifyH("LEFT")
    dungeon:SetWordWrap(true)
    if dungeon.SetNonSpaceWrap then dungeon:SetNonSpaceWrap(true) end

    local portal = GUI2:CreateText(frame, self:GetAnnouncementPreview(ANNOUNCE_KIND_PORTAL), "font.size.md", "color.text.primary", "LEFT")
    portal:SetPoint("TOPLEFT", dungeon, "BOTTOMLEFT", 0, -lineGap)
    portal:SetSize(width, lineHeight)
    portal:SetJustifyH("LEFT")
    portal:SetWordWrap(true)
    if portal.SetNonSpaceWrap then portal:SetNonSpaceWrap(true) end

    self.announcePreviewLines = {
        dungeon = dungeon,
        portal = portal,
    }

    return width, height
end

local function GetItemCooldownValues(itemID)
    local info = ItemAPI.GetCooldown and ItemAPI.GetCooldown(itemID)
    if info then
        return info.startTime or 0, info.duration or 0, info.isEnabled
    end

    return 0, 0, nil
end

local function FormatTime(seconds)
    if seconds >= 86400 then
        return string.format("%dd", math.ceil(seconds / 86400))
    elseif seconds >= 3600 then
        return string.format("%dh", math.ceil(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%ds", seconds)
    end
end

function Module:UpdateKnownHearthstones()
    self.knownHearthstones = {}

    if ItemAPI.GetCount(HEARTHSTONE_ITEM_ID) > 0 then
        tinsert(self.knownHearthstones, HEARTHSTONE_ITEM_ID)
    end

    if PlayerHasToy and PlayerHasToy(DARK_PORTAL_TOY_ID) then
        tinsert(self.knownHearthstones, DARK_PORTAL_TOY_ID)
    end
end

function Module:IsHearthstoneAvailable(id)
    if not id then return false end

    if id == HEARTHSTONE_ITEM_ID then
        return ItemAPI.GetCount(HEARTHSTONE_ITEM_ID) > 0
    end

    if PlayerHasToy and PlayerHasToy(id) then return true end
    return ItemAPI.GetCount(id) > 0
end

function Module:GetRandomHearthstone()
    self:UpdateKnownHearthstones()
    if not self.knownHearthstones or #self.knownHearthstones == 0 then return nil end
    return self.knownHearthstones[math.random(1, #self.knownHearthstones)]
end

function Module:PickNextHearthstone()
    if self.db.hearthstoneMode == "random" then
        local nextID = self:GetRandomHearthstone()
        self.db.nextHearthstone = nextID
        return nextID
    end

    if self.db.hearthstoneMode == "fixed" then
        local id = self.db.customHearthstone or HEARTHSTONE_ITEM_ID
        if self:IsHearthstoneAvailable(id) then return id end
        return nil
    end

    return nil
end

function Module:GetCurrentHearthstone()
    if self.db.hearthstoneMode == "random" then
        local id = self.db.nextHearthstone
        if not self:IsHearthstoneAvailable(id) then
            id = self:GetRandomHearthstone()
            self.db.nextHearthstone = id
        end
        return id
    end

    if self.db.hearthstoneMode == "fixed" then
        local id = self.db.customHearthstone or HEARTHSTONE_ITEM_ID
        if self:IsHearthstoneAvailable(id) then return id end
        return nil
    end

    return nil
end

function Module:GetHearthstoneIcon(id)
    if not id then return 134414 end

    local icon = ItemAPI.GetIcon(id)
    if icon then return icon end

    if C_ToyBox and C_ToyBox.GetToyInfo then
        local _, _, toyIcon = C_ToyBox.GetToyInfo(id)
        if toyIcon then return toyIcon end
    end

    return ItemAPI.GetIcon(HEARTHSTONE_ITEM_ID) or 134414
end

function Module:GetHearthstoneName(id)
    if not id then return T("teleports.settings.hearthstone", "Hearthstone") end
    local name = ItemAPI.GetName(id)
    if name and name ~= "" then return name end
    if id == DARK_PORTAL_TOY_ID then return T("teleports.settings.dark_portal", "Dark Portal") end
    if id == HEARTHSTONE_ITEM_ID then return T("teleports.settings.hearthstone", "Hearthstone") end
    return T("teleports.settings.hearthstone", "Hearthstone")
end

-- Data specific for Wrath
local MAGE_SPELLS = {
    -- { name, teleportID, portalID, faction }
    -- Alliance
    { "teleports.menu.city_stormwind", 3561, 10059, "Alliance" },
    { "teleports.menu.city_ironforge", 3562, 11416, "Alliance" },
    { "teleports.menu.city_darnassus", 3565, 11419, "Alliance" },
    { "teleports.menu.city_exodar", 32271, 32266, "Alliance" },
    { "teleports.menu.city_theramore", 49359, 49360, "Alliance" },
    { "teleports.menu.city_shattrath", 33690, 33691, "Alliance" },
    -- Horde
    { "teleports.menu.city_orgrimmar", 3567, 11417, "Horde" },
    { "teleports.menu.city_undercity", 3563, 11418, "Horde" },
    { "teleports.menu.city_thunder_bluff", 3566, 11420, "Horde" },
    { "teleports.menu.city_silvermoon", 32272, 32267, "Horde" },
    { "teleports.menu.city_stonard", 49358, 49361, "Horde" },
    { "teleports.menu.city_shattrath", 35715, 35717, "Horde" },
    -- Neutral
    { "teleports.menu.city_dalaran", 53140, 53142, "Neutral" },
}

function Module:BuildSpellcastAnnouncementIndex()
    local index = {}

    for _, data in ipairs(MAGE_SPELLS) do
        local portalID = tonumber(data[3])
        if portalID then
            local displayName = T(data[1], data[1])
            index[portalID] = {
                id = portalID,
                announceKind = ANNOUNCE_KIND_PORTAL,
                announceName = displayName,
                text = displayName,
            }
        end
    end

    self.announcementSpellcastIndex = index
    return index
end

function Module:GetSpellcastAnnouncementData(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end

    local index = self.announcementSpellcastIndex or self:BuildSpellcastAnnouncementIndex()
    return index and index[spellID] or nil
end

local CLASS_SPELLS = {
    DEATHKNIGHT = 50977, -- 黑锋之门
    DRUID = 18960,       -- 传送：月光林地
    SHAMAN = 556,        -- 星界传送
}

local REAGENTS = {
    TELEPORT = 17031, -- 传送符文
    PORTAL = 17032,   -- 传送门符文
}

function Module:OnInitialize()
    self.db = GetYBarDB().Teleports or {}
    GetYBarDB().Teleports = self.db
    self.frame = nil

    if not self.db.hearthstoneMode then self.db.hearthstoneMode = "fixed" end
    if self.db.hearthstoneMode == "normal" then self.db.hearthstoneMode = "fixed" end
    if not self.db.customHearthstone then self.db.customHearthstone = HEARTHSTONE_ITEM_ID end
    if not IsValidAnnounceScope(self.db.announceScope) then self.db.announceScope = ANNOUNCE_SCOPE_OFF end
    if not IsValidAnnounceTrigger(self.db.announceTrigger) then self.db.announceTrigger = ANNOUNCE_TRIGGER_CAST_START end
    if type(self.db.announcePrefix) ~= "string" then self.db.announcePrefix = ANNOUNCE_DEFAULT_PREFIX end

    self.announcementSpellcastIndex = nil
    self.knownHearthstones = {}
    self:UpdateKnownHearthstones()
    if self.db.nextHearthstone == nil then
        self.db.nextHearthstone = self:GetRandomHearthstone()
    end
end

function Module:OnTeleportEvent(event, ...)
    if self._hasError or not self._runtimeAttached then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then
            self:HandleAnnouncementSpellcastEvent(event, spellID)
        end
    end
end

function Module:AttachRuntime()
    if self._hasError then return end

    self._runtimeAttached = true

    YUI.Event:OffOwner(self)
    YUI.Event:On("HEARTHSTONE_BOUND", "Refresh", self)
    YUI.Event:On("YUI_WORLD_READY", "Refresh", self)
    YUI.Event:On("BAG_UPDATE_DELAYED", "Refresh", self)
    YUI.Event:On("TOYS_UPDATED", "Refresh", self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", "Refresh", self)
    YUI.Event:On("UNIT_SPELLCAST_START", "OnTeleportEvent", self, { unit = "player" })
    YUI.Event:On("UNIT_SPELLCAST_SUCCEEDED", "OnTeleportEvent", self, { unit = "player" })

    if IsTeleportFrameReady(self.frame) then
        if self.frameOnUpdate then
            self.frame:SetScript("OnUpdate", self.frameOnUpdate)
        end
        self.frame:Show()
        self:Update()
    end
end

function Module:DetachRuntime()
    self._runtimeAttached = false

    YUI.Event:OffOwner(self)

    self:CancelTooltipTimer()
    self:StopHideTimer()
    self:HideMenu()

    if GameTooltip then
        YUI.HideGameTooltip()
    end

    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
end

function Module:CreateBarItem(parent)
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })

    local secure = GUI2:CreateFrame(frame)
    secure:SetAllPoints()

    frame.iconSlot, frame.icon = YBar:CreateIconSlot(frame, {
        size = 14,
        icon = self:GetHearthstoneIcon(self:GetCurrentHearthstone()),
        shape = "square",
        padding = 0,
    })
    if frame.iconSlot then
        frame.iconSlot:SetPoint("LEFT", frame, "LEFT", 0, 0)
    else
        frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon:SetTexture(self:GetHearthstoneIcon(self:GetCurrentHearthstone()))
    end

    frame.statusText, frame.text = YBar:CreateStatusText(frame, {
        variant = "single",
        value = "",
        width = 80,
        height = 20,
        justifyH = "LEFT",
        colorKey = "color.ybar.text",
    })
    frame.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", 4, 0)

    frame.secure = secure
    self.frame = frame

    self:UpdateClassAction(frame)
    YBar:CreateActionHost(secure, {
        onEnter = function()
            if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end
            Module:OnEnter(frame)
            YBar:SetThemedTextAccent(frame.text)
        end,
        onLeave = function()
            if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end
            YUI.HideGameTooltip()
            Module:CancelTooltipTimer()
            Module:StartHideTimer()
            YBar:RestoreThemedTextColor(frame.text, "color.ybar.text")
        end,
    })

    -- Cooldown update loop
    self.frameOnUpdate = function(_, elapsed)
        if not Module._runtimeAttached then
            return
        end

        frame.timer = (frame.timer or 0) + elapsed
        if frame.timer > 1 then
            frame.timer = 0
            Module:UpdateHearthstoneCooldown(frame)
        end
    end
    frame:SetScript("OnUpdate", self.frameOnUpdate)

    -- Set initial layout only outside combat; secure action hosts cannot be
    -- resized while protected.
    if not SecurityAPI.InCombatLockdown() then
        frame:SetWidth(14)
        self:UpdateBarItem(frame)
    else
        self.needsUpdate = true
    end

    return frame
end

function Module:RefreshActionHost(frame, hsID)
    frame = frame or self.frame
    if not IsTeleportFrameReady(frame) or not frame.secure.actionHost then return end

    hsID = hsID or self:GetCurrentHearthstone()

    local actions = {
        altLeft = {
            kind = "custom",
            onClick = function()
                YUI:OpenYBarModuleSettings("Teleports")
            end,
        },
    }

    if hsID then
        actions.left = {
            kind = (PlayerHasToy and PlayerHasToy(hsID)) and "toy" or "item",
            toy = hsID,
            item = "item:" .. hsID,
            afterClick = function(_, _, owner)
                if self.db.hearthstoneMode == "random" and not SecurityAPI.InCombatLockdown() then
                    self:PickNextHearthstone()
                    self:UpdateBarItem(frame)
                    if GameTooltip:GetOwner() == owner then
                        self:OnEnter(frame)
                    end
                end
            end,
        }
    else
        actions.left = { kind = "noop" }
    end

    if PlayerHasToy and PlayerHasToy(WORMHOLE_TOY_ID) then
        actions.shiftLeft = {
            kind = "toy",
            toy = WORMHOLE_TOY_ID,
        }
    elseif ItemAPI.GetCount(WORMHOLE_TOY_ID) > 0 then
        actions.shiftLeft = {
            kind = "item",
            item = "item:" .. WORMHOLE_TOY_ID,
        }
    else
        actions.shiftLeft = { kind = "noop" }
    end

    local _, classFilename = UnitClass("player")
    local spellID = CLASS_SPELLS[classFilename]
    if spellID then
        local spellName = SpellAPI.GetName(spellID)
        if spellName then
            actions.right = {
                kind = "spell",
                spell = spellName,
            }
        end
    elseif classFilename == "MAGE" then
        actions.right = {
            kind = "custom",
            onClick = function()
                if not SecurityAPI.InCombatLockdown() then
                    Module:ToggleMageMenu(frame)
                    YUI.HideGameTooltip()
                end
            end,
        }
    end

    local ok = frame.secure.actionHost:SetActions(actions)
    if not ok then
        self.needsUpdate = true
    end
end

function Module:UpdateBarItem(frame)
    if not IsTeleportFrameReady(frame) then return end
    if SecurityAPI.InCombatLockdown() then
        self.needsUpdate = true
        return
    end

    self.needsUpdate = false

    local fontSize = self.db.fontSize or 12
    local iconSize = self.db.iconSize or 14
    local iconSpacing = self.db.iconSpacing or 4

    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontOutline and "OUTLINE" or ""

    if frame.iconSlot then
        frame.iconSlot:SetSize(iconSize, iconSize)
    else
        frame.icon:SetSize(iconSize, iconSize)
    end
    frame.text:SetFont(STANDARD_TEXT_FONT, fontSize, fontFlag)

    if globalDB.fontShadow then
        frame.text:SetShadowColor(0, 0, 0, 1)
        frame.text:SetShadowOffset(1, -1)
    else
        frame.text:SetShadowOffset(0, 0)
    end

    local bindLocation = GetBindLocation() or ""
    frame.defaultText = bindLocation
    frame.text:SetText(bindLocation)

    local hsID = self:GetCurrentHearthstone()
    local iconTex = self:GetHearthstoneIcon(hsID)
    frame.icon:SetTexture(iconTex)

    -- Size calculation
    if bindLocation ~= "" then
        frame:SetWidth(iconSize + iconSpacing + frame.text:GetStringWidth())
    else
        frame:SetWidth(iconSize)
    end

    self:RefreshActionHost(frame, hsID)

    self:UpdateHearthstoneCooldown(frame)
end

function Module:UpdateClassAction(frame)
    if not IsTeleportFrameReady(frame) then return end
    if SecurityAPI.InCombatLockdown() then return end
    self:RefreshActionHost(frame)
end

function Module:UpdateHearthstoneCooldown(frame)
    if not IsTeleportFrameReady(frame) then return end

    local iconSize = self.db.iconSize or 14
    local iconSpacing = self.db.iconSpacing or 4
    local inCombat = SecurityAPI.InCombatLockdown()

    local hsID = self:GetCurrentHearthstone()
    if not hsID then
        local bindLocation = frame.defaultText or GetBindLocation() or ""
        frame.text:SetText(bindLocation)
        frame.text:SetTextColor(1, 1, 1)
        if not inCombat then
            frame.text:ClearAllPoints()
            frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", iconSpacing, 0)
        end
        return
    end

    local start, duration = GetItemCooldownValues(hsID)
    if start and start > 0 and duration > 2 then
        local remain = duration - (CombatAPI.GetTime() - start)
        if remain > 0 then
            frame.text:SetText(FormatTime(remain))
            frame.text:SetTextColor(1, 0, 0)

            -- Center text during cooldown
            if not inCombat then
                frame.text:ClearAllPoints()
                frame.text:SetPoint("CENTER", frame, "CENTER", (iconSize + iconSpacing) / 2, 0)
            end
            return
        end
    end

    local bindLocation = frame.defaultText or GetBindLocation() or ""
    frame.text:SetText(bindLocation)
    frame.text:SetTextColor(1, 1, 1)

    -- Restore text position when not on cooldown
    if not inCombat then
        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", iconSpacing, 0)
    end
end

function Module:OnEnter(frame)
    if not IsTeleportFrameReady(frame) then return end

    if SecurityAPI.InCombatLockdown() then return end
    if MenuFrame and MenuFrame:IsShown() then return end

    local anchor, yOffset = F:GetTooltipAnchor(frame)

    GameTooltip:SetOwner(frame, anchor, 0, yOffset)
    GameTooltip:SetText(T("teleports.tooltip.title", "传送助手"))
    GameTooltip:AddLine(" ")

    local mode = self.db.hearthstoneMode or "fixed"
    local displayID = (mode == "fixed") and (self.db.customHearthstone or HEARTHSTONE_ITEM_ID) or self:GetCurrentHearthstone()
    local usable = self:IsHearthstoneAvailable(displayID)

    local name = self:GetHearthstoneName(displayID)
    local icon = self:GetHearthstoneIcon(displayID)

    local cdText = "|cff00ff00" .. (LC["common.ready"] or "就绪") .. "|r"
    if usable and displayID then
        local start, duration = GetItemCooldownValues(displayID)
        if start and start > 0 and duration > 0 then
            local remain = duration - (CombatAPI.GetTime() - start)
            if remain > 0 then
                cdText = format("|cffff0000%s|r", FormatTime(remain))
            end
        end
    else
        cdText = "|cffff0000" .. T("teleports.tooltip.unavailable", "不可用") .. "|r"
    end

    GameTooltip:AddDoubleLine(format("|T%s:14|t %s", icon, name), cdText, 1, 1, 1, 1, 1, 1)

    GameTooltip:AddLine(" ")
    if mode == "random" then
        GameTooltip:AddLine(T("teleports.tooltip.mode_random", "模式：随机"))
    else
        GameTooltip:AddLine(T("teleports.tooltip.mode_fixed", "模式：固定"))
    end

    local white = "|cffffffff"
    local gold = "|c" .. CreateColor(1, 0.82, 0):GenerateHexColor()

    -- Check reagents
    local _, classFilename = UnitClass("player")
    if classFilename == "MAGE" then
        local tpRunes = ItemAPI.GetCount(REAGENTS.TELEPORT)
        local portalRunes = ItemAPI.GetCount(REAGENTS.PORTAL)

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("teleports.tooltip.reagents", "施法材料:"))

        local tpColor = tpRunes > 0 and "|cffffffff" or "|cffff0000"
        local portalColor = portalRunes > 0 and "|cffffffff" or "|cffff0000"

        GameTooltip:AddDoubleLine(format("|T%s:14|t %s", ItemAPI.GetIcon(REAGENTS.TELEPORT), T("teleports.tooltip.teleport_rune", "传送符文")), format("%s%d|r", tpColor, tpRunes), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(format("|T%s:14|t %s", ItemAPI.GetIcon(REAGENTS.PORTAL), T("teleports.tooltip.portal_rune", "传送门符文")), format("%s%d|r", portalColor, portalRunes), 1, 1, 1, 1, 1, 1)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("teleports.action.hearthstone", "炉石")))

    if CLASS_SPELLS[classFilename] then
        local spellName = SpellAPI.GetName(CLASS_SPELLS[classFilename])
        if spellName then
            GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, spellName))
        end
    elseif classFilename == "MAGE" then
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("teleports.action.open", "打开 %s", TP_MENU_NAME)))
    end

    if (PlayerHasToy and PlayerHasToy(WORMHOLE_TOY_ID)) or ItemAPI.GetCount(WORMHOLE_TOY_ID) > 0 then
        local itemInfo = ItemAPI.GetInfo(WORMHOLE_TOY_ID)
        local itemName = itemInfo and itemInfo.name
        local itemQuality = itemInfo and itemInfo.quality
        if not itemName and C_ToyBox and C_ToyBox.GetToyInfo then
            _, itemName = C_ToyBox.GetToyInfo(WORMHOLE_TOY_ID)
        end
        itemName = itemName or T("teleports.menu.wormhole_northrend", "Wormhole: Northrend")

        local hex = "ff0070dd" -- 默认精良品质(蓝色)
        if itemQuality then
            local _, _, _, colorHex = ItemAPI.GetQualityColor(itemQuality)
            if colorHex then hex = colorHex end
        end

        local cdText = "|cff00ff00" .. (LC["common.ready"] or "就绪") .. "|r"
        local start, duration = GetItemCooldownValues(WORMHOLE_TOY_ID)
        if start and start > 0 and duration > 0 then
            local remain = duration - (CombatAPI.GetTime() - start)
            if remain > 0 then
                cdText = format("|cffff0000%s|r", FormatTime(remain))
            end
        end

        GameTooltip:AddDoubleLine(format("%sShift + %s: |r%s%s|r", white, LC["common.left_click"], gold, T("teleports.action.use", "使用 %s", "|c" .. hex .. itemName .. "|r")), cdText)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))

    GameTooltip:Show()

    if not self.tooltipTimer then
        self.tooltipTimer = C_Timer.NewTicker(1, function()
            if not self._runtimeAttached then
                self:CancelTooltipTimer()
                return
            end
            if GameTooltip:GetOwner() == frame then
                self:OnEnter(frame)
            else
                self:CancelTooltipTimer()
            end
        end)
    end
end

function Module:CancelTooltipTimer()
    if self.tooltipTimer then
        self.tooltipTimer:Cancel()
        self.tooltipTimer = nil
    end
end

function Module:ToggleMageMenu(anchor)
    if not self._runtimeAttached then return end
    if SecurityAPI.InCombatLockdown() then return end

    if MenuFrame and MenuFrame:IsShown() then
        self:HideMenu()
        return
    end

    if not MenuFrame then
        -- SecureHandlerStateTemplate must stay on native CreateFrame.
        MenuFrame = CreateFrame("Frame", "YBarMageTeleportMenu", UIParent, "SecureHandlerStateTemplate")
        MenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        GUI2:CreateBackdrop(MenuFrame, {
            surface = "color.surface.popup",
            border = "color.popup.border",
            nativeFrameBorder = true,
            nativeFrameBorderStyle = "tooltip",
        })

        MenuFrame:SetScript("OnEnter", function() self:StopHideTimer() end)
        MenuFrame:SetScript("OnLeave", function() self:StartHideTimer() end)
    end

    if not MenuFrame._yuiVisibilityDriver then
        if UnregisterStateDriver then
            pcall(UnregisterStateDriver, MenuFrame, "combat")
            pcall(UnregisterStateDriver, MenuFrame, "visibility")
        end

        MenuFrame:SetAttribute("_onstate-visibility", [[
            if newstate == "hide" then
                self:Hide()
            end
        ]])
        RegisterStateDriver(MenuFrame, "visibility", "[combat] hide; 0")
        MenuFrame._yuiVisibilityDriver = true
    end

    self:PopulateMageMenu(MenuFrame)

    MenuFrame:ClearAllPoints()

    local screenHeight = GetScreenHeight()
    local anchorY = anchor:GetBottom()

    if anchorY > screenHeight / 2 then
        MenuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    else
        MenuFrame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
    end

    MenuFrame:Show()
end

function Module:PopulateMageMenu(frame)
    if not frame.buttons then
        frame.buttons = {}
    end

    -- Hide all existing buttons first
    for _, btn in pairs(frame.buttons) do
        btn:Hide()
    end

    local iconSize = 32
    local padding = 4
    local columns = 2
    local x, y = padding, -padding

    local playerFaction = UnitFactionGroup("player")
    local displayIndex = 1

    for i, data in ipairs(MAGE_SPELLS) do
        local name = T(data[1], data[1])
        local tpID = data[2]
        local portalID = data[3]
        local spellFaction = data[4]

        if spellFaction == "Neutral" or spellFaction == playerFaction then
            -- Teleport Button (Right Column)
            local btnTp = frame.buttons["tp_"..i]
            if not btnTp then
                btnTp = self:CreateSpellButton(frame, tpID, iconSize, name)
                frame.buttons["tp_"..i] = btnTp
            end
            btnTp:SetPoint("TOPLEFT", x + iconSize + padding, y)
            btnTp:Show()

            -- Portal Button (Left Column)
            local btnPortal = frame.buttons["portal_"..i]
            if not btnPortal then
                btnPortal = self:CreateSpellButton(frame, portalID, iconSize, name)
                frame.buttons["portal_"..i] = btnPortal
            end
            btnPortal:SetPoint("TOPLEFT", x, y)
            btnPortal:Show()

            y = y - iconSize - padding
            displayIndex = displayIndex + 1
        end
    end

    -- Reagents
    local portalCount = ItemAPI.GetCount(REAGENTS.PORTAL)
    local tpCount = ItemAPI.GetCount(REAGENTS.TELEPORT)

    -- Portal Reagent (Left Column)
    local runePortal = frame.buttons["rune_portal"]
    if not runePortal then
        runePortal = self:CreateReagentFrame(frame, REAGENTS.PORTAL, iconSize)
        frame.buttons["rune_portal"] = runePortal
    end
    runePortal:SetPoint("TOPLEFT", x, y)
    runePortal.countText:SetText(portalCount)
    if portalCount == 0 then
        YBar:SetThemedTextColor(runePortal.countText, "color.ybar.dynamic", { 1, 0, 0, 1 })
        runePortal.icon:SetDesaturated(true)
        runePortal.icon:SetVertexColor(0.5, 0.5, 0.5)
    else
        YBar:SetThemedTextColor(runePortal.countText, "color.ybar.text", { 1, 1, 1, 1 })
        runePortal.icon:SetDesaturated(false)
        runePortal.icon:SetVertexColor(1, 1, 1)
    end
    runePortal:Show()

    -- Teleport Reagent (Right Column)
    local runeTp = frame.buttons["rune_tp"]
    if not runeTp then
        runeTp = self:CreateReagentFrame(frame, REAGENTS.TELEPORT, iconSize)
        frame.buttons["rune_tp"] = runeTp
    end
    runeTp:SetPoint("TOPLEFT", x + iconSize + padding, y)
    runeTp.countText:SetText(tpCount)
    if tpCount == 0 then
        YBar:SetThemedTextColor(runeTp.countText, "color.ybar.dynamic", { 1, 0, 0, 1 })
        runeTp.icon:SetDesaturated(true)
        runeTp.icon:SetVertexColor(0.5, 0.5, 0.5)
    else
        YBar:SetThemedTextColor(runeTp.countText, "color.ybar.text", { 1, 1, 1, 1 })
        runeTp.icon:SetDesaturated(false)
        runeTp.icon:SetVertexColor(1, 1, 1)
    end
    runeTp:Show()

    y = y - iconSize - padding

    frame:SetSize((iconSize * 2) + (padding * 3), math.abs(y))
end

function Module:CreateSpellButton(parent, spellID, size, displayName)
    local btn = GUI2:CreateButtonFrame(parent)
    btn:SetSize(size, size)

    btn.iconSlot, btn.icon = YBar:CreateIconSlot(btn, {
        size = size,
        icon = SpellAPI.GetTexture(spellID),
        shape = "square",
        padding = 0,
    })
    local iconFrame = btn.iconSlot or btn.icon
    iconFrame:SetAllPoints()

    if not btn.iconSlot then
        local iconBg = GUI2:CreateFrame(btn, { template = "BackdropTemplate" })
        iconBg:SetAllPoints(btn.icon)
        iconBg:SetFrameLevel(btn:GetFrameLevel())
        GUI2:CreateBorder(iconBg)
        btn.iconBg = iconBg
    end

    if displayName then
        btn.textFrame = GUI2:CreateFrame(btn)
        btn.textFrame:SetPoint("BOTTOM", btn, "BOTTOM", 1, 2)
        btn.textFrame:SetSize(size, 16)
        local _, text = YBar:CreateStatusText(btn.textFrame, {
            value = displayName,
            single = true,
            justifyH = "CENTER",
            colorKey = "color.ybar.text",
        })
        text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        text:SetWidth(size)
        text:SetJustifyH("CENTER")
        text:SetText(displayName)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        btn.text = text
    end

    local isKnown = SpellAPI.IsKnown(spellID)
    local spellName = isKnown and SpellAPI.GetName(spellID) or nil
    if not isKnown then
        btn.icon:SetDesaturated(true)
        btn.icon:SetVertexColor(0.5, 0.5, 0.5)
    end

    btn:SetScript("OnEnter", function(self)
        Module:StopHideTimer()
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "hover")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.accent")
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellID)
        if not isKnown then
            GameTooltip:AddLine(T("teleports.tooltip.unlearned", "未学习"), 1, 0, 0)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "normal")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.default")
        end
        YUI.HideGameTooltip()
        Module:StartHideTimer()
    end)

    local host = YBar:CreateActionHost(btn, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if host then
        host:SetActions({
            left = isKnown and {
                kind = "spell",
                spell = spellName or spellID,
                afterClick = function()
                    Module:HideMenu()
                end,
            } or { kind = "noop" },
        })
    end

    return btn
end

function Module:CreateReagentFrame(parent, itemID, size)
    local frame = GUI2:CreateFrame(parent)
    frame:SetSize(size, size)

    frame.iconSlot, frame.icon = YBar:CreateIconSlot(frame, {
        size = size,
        icon = ItemAPI.GetIcon(itemID),
        shape = "square",
        padding = 0,
    })
    local iconFrame = frame.iconSlot or frame.icon
    iconFrame:SetAllPoints()

    if not frame.iconSlot then
        local iconBg = GUI2:CreateFrame(frame, { template = "BackdropTemplate" })
        iconBg:SetAllPoints(frame.icon)
        iconBg:SetFrameLevel(frame:GetFrameLevel())
        GUI2:CreateBorder(iconBg)
        frame.iconBg = iconBg
    end

    local countParent = frame.iconSlot or frame
    local countText = YBar:CreateThemedText(countParent, {
        fontPath = STANDARD_TEXT_FONT,
        fontSize = 12,
        fontFlags = "OUTLINE",
        colorKey = "color.ybar.text",
        fallback = { 1, 1, 1, 1 },
        justifyH = "RIGHT",
    })
    countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
    countText:SetJustifyH("RIGHT")
    frame.countText = countText

    frame:SetScript("OnEnter", function(self)
        Module:StopHideTimer()
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "hover")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.accent")
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemID)
        GameTooltip:Show()
    end)

    frame:SetScript("OnLeave", function(self)
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "normal")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.default")
        end
        YUI.HideGameTooltip()
        Module:StartHideTimer()
    end)

    return frame
end

function Module:HideMenu()
    if SecurityAPI.InCombatLockdown() then return end
    if MenuFrame then
        MenuFrame:Hide()
    end
end

function Module:StartHideTimer()
    if self.hideTimer then
        self.hideTimer:Cancel()
    end
    self.hideTimer = C_Timer.NewTimer(0.3, function()
        if not self._runtimeAttached then
            self:HideMenu()
            return
        end
        if SecurityAPI.InCombatLockdown() then return end
        if MenuFrame and not MenuFrame:IsMouseOver() and not (self.frame and self.frame:IsMouseOver()) then
            self:HideMenu()
        end
    end)
end

function Module:StopHideTimer()
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
end

function Module:Update()
    -- Called when config changes or by YBar's passive update
    if SecurityAPI.InCombatLockdown() then
        self.needsUpdate = true
        return
    end

    if IsTeleportFrameReady(self.frame) then
        self:UpdateBarItem(self.frame)
        self:UpdateClassAction(self.frame)
    end
end

function Module:Refresh()
    if self._hasError or not self._runtimeAttached then
        return
    end

    if SecurityAPI.InCombatLockdown() then
        self.needsUpdate = true
        return
    end

    self:Update()
    if YBar and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
end

function Module:GetOptions()
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("YBar") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    return {
        { type = "divider", label = YBarL["teleports.settings.appearance_header"] or "Appearance", alignLeft = true, width = 600 },
        {
            type = "slider",
            label = CoreL["common.font_size"] or "Font Size",
            key = "fontSize",
            min = 10, max = 24, step = 1,
            default = 12,
            onChange = function(_, value)
                Module.db.fontSize = value
                Module:Refresh()
            end
        },
        {
            type = "slider",
            label = YBarL["ybar.settings.option.icon_size"] or "Icon Size",
            key = "iconSize",
            min = 10, max = 32, step = 1,
            default = 14,
            onChange = function(_, value)
                Module.db.iconSize = value
                Module:Refresh()
            end
        },
        {
            type = "slider",
            label = YBarL["ybar.settings.option.icon_spacing"] or "Icon Spacing",
            key = "iconSpacing",
            min = 0, max = 20, step = 1,
            default = 4,
            onChange = function(_, value)
                Module.db.iconSpacing = value
                Module:Refresh()
            end
        },
        { type = "divider", label = YBarL["ybar.settings.section.hearthstone"] or "Hearthstone", alignLeft = true, width = 600 },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.hearthstone_mode"] or "Hearthstone Mode",
            key = "hearthstoneMode",
            default = "fixed",
            options = {
                { text = YBarL["ybar.settings.option.fixed"] or "Fixed", value = "fixed" },
                { text = YBarL["ybar.settings.option.random"] or "Random", value = "random" },
            },
            onChange = function(widget, value)
                Module.db.hearthstoneMode = value
                if value == "random" and Module.db.nextHearthstone == nil then
                    Module.db.nextHearthstone = Module:GetRandomHearthstone()
                end
                Module:Refresh()

                local parent = widget:GetParent()
                if parent and parent:GetParent() then
                    parent = parent:GetParent()
                end
                local S = YUI.Settings
                if parent and S and S.ClearConfig and S.RenderConfig then
                    S:ClearConfig(parent)
                    S:RenderConfig(parent, self:GetOptions())
                end
            end,
        },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.fixed_hearthstone"] or "Fixed Hearthstone",
            key = "customHearthstone",
            default = HEARTHSTONE_ITEM_ID,
            hidden = function()
                return Module.db.hearthstoneMode ~= "fixed"
            end,
            options = {
                { text = YBarL["teleports.settings.hearthstone"] or "Hearthstone", value = HEARTHSTONE_ITEM_ID },
                { text = YBarL["teleports.settings.dark_portal"] or "Dark Portal", value = DARK_PORTAL_TOY_ID },
            },
            onChange = function(_, value)
                Module.db.customHearthstone = value
                Module:Refresh()
            end,
        },
        { type = "divider", label = YBarL["teleports.settings.announce_header"] or "Teleport Announcement", alignLeft = true, width = 600 },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.announce_scope"] or "Announcement Scope",
            width = 220,
            options = {
                { text = YBarL["teleports.settings.announce_scope_off"] or "Off", value = ANNOUNCE_SCOPE_OFF },
                { text = YBarL["teleports.settings.announce_scope_portals"] or "Portals", value = ANNOUNCE_SCOPE_PORTALS },
                { text = YBarL["teleports.settings.announce_scope_dungeons"] or "Mythic+", value = ANNOUNCE_SCOPE_DUNGEONS },
                { text = YBarL["teleports.settings.announce_scope_all"] or "Portals + Dungeons", value = ANNOUNCE_SCOPE_ALL },
            },
            get = function() return Module.db.announceScope or ANNOUNCE_SCOPE_OFF end,
            set = function(value)
                Module.db.announceScope = IsValidAnnounceScope(value) and value or ANNOUNCE_SCOPE_OFF
            end,
        },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.announce_trigger"] or "Trigger Condition",
            width = 220,
            options = {
                { text = YBarL["teleports.settings.announce_trigger_cast_start"] or "Cast Start", value = ANNOUNCE_TRIGGER_CAST_START },
                { text = YBarL["teleports.settings.announce_trigger_cast_success"] or "Cast Success", value = ANNOUNCE_TRIGGER_CAST_SUCCESS },
            },
            get = function() return Module:GetAnnounceTrigger() end,
            set = function(value)
                Module.db.announceTrigger = IsValidAnnounceTrigger(value) and value or ANNOUNCE_TRIGGER_CAST_START
                Module:RefreshAnnouncementPreview()
            end,
        },
        {
            type = "editbox",
            label = YBarL["teleports.settings.announce_prefix"] or "Announcement Prefix",
            width = 220,
            get = function() return Module:NormalizeAnnouncePrefix() end,
            set = function(value)
                Module.db.announcePrefix = tostring(value or "")
                Module:RefreshAnnouncementPreview()
            end,
        },
        {
            type = "custom",
            render = function(parent, x, y, width)
                return Module:RenderAnnouncementPreview(parent, x, y, width)
            end,
        },
    }
end

YBar:RegisterModule(Module, {
    id = "ybar.teleports",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.event", "core.api", "gui"},
    defaultEnabled = true,
})
