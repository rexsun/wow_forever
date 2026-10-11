local YUI = _G.YUI
if not YUI or not YUI.YMap then return end

local YMap = YUI.YMap
local Migration = {}
YMap.Migration = Migration

local MIGRATION_VERSION = 1
local BUTTON_OFFSET_MIGRATION_VERSION = 1
local QUEUE_OFFSET_MIGRATION_VERSION = 1
local SQUARE_APPEARANCE_DISPLAY_MIGRATION_VERSION = 2
local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local SQUARE_ELEMENT_ANCHORS = {
    expansion = "BOTTOMLEFT",
    tracking = "BOTTOMLEFT",
    calendar = "TOPRIGHT",
    mail = "TOPRIGHT",
    crafting = "TOPRIGHT",
    difficulty = "TOPLEFT",
}

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Boolean(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

local function Point(value, fallback)
    return VALID_POINTS[value] and value or fallback
end

local function MigrateMapPosition(components, db)
    local source = components and components.MapPos
    if type(source) ~= "table" or type(db.worldMap) ~= "table" then
        return false
    end
    if db.worldMap.position ~= nil then
        return false
    end

    local point = Point(source.point or source[1], nil)
    local relativePoint = Point(source.relativePoint or source[3], point)
    local x = tonumber(source.x or source[4])
    local y = tonumber(source.y or source[5])
    if not point or not relativePoint or not x or not y then
        return false
    end

    db.worldMap.position = {
        point = point,
        relativeTo = "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    return true
end

local function MigrateEQoL(components, db)
    local source = components and components.EQoLAdapter_Config
    if type(source) ~= "table" then return false end

    local worldMap = db.worldMap
    local minimap = db.minimap
    local queue = minimap and minimap.queue
    if type(worldMap) ~= "table" or type(minimap) ~= "table" or type(queue) ~= "table" then
        return false
    end

    -- Preserve the legacy choices even when that component was disabled. The caller
    -- decides product activation separately from configuration migration.
    worldMap.scale = Clamp(source.worldMapScale, 0.5, 2, worldMap.scale)
    minimap.zoneTextAlignment = source.centerMinimapZoneText == true and "center" or "native"
    minimap.hideZoomButtons = Boolean(source.hideMinimapZoom, minimap.hideZoomButtons)
    queue.customLayout = Boolean(source.enableQueueStatus, queue.customLayout)
    queue.size = Clamp(source.queueStatusSize, 6, 64, queue.size)
    queue.anchor = Point(source.queueStatusAnchor, queue.anchor)
    queue.offsetX = Clamp(source.queueStatusOffsetX, -200, 200, queue.offsetX)
    queue.offsetY = Clamp(source.queueStatusOffsetY, -200, 200, queue.offsetY)
    if (tonumber(db.migrations.queueOffsets) or 0) >= QUEUE_OFFSET_MIGRATION_VERSION then
        if tonumber(source.queueStatusOffsetX) and (queue.anchor == "TOPLEFT" or queue.anchor == "BOTTOMLEFT") then
            queue.offsetX = -queue.offsetX
        end
        if tonumber(source.queueStatusOffsetY) and (queue.anchor == "BOTTOMLEFT" or queue.anchor == "BOTTOMRIGHT") then
            queue.offsetY = -queue.offsetY
        end
    end
    return true
end

local function MigrateDrawer(components, db, active)
    local source = components and components.MinimapCollection_Config
    local drawer = db.buttonDrawer
    if type(drawer) ~= "table" then return false end

    if components and components.MinimapCollection ~= nil then
        drawer.enabled = active == true
    end
    if type(source) ~= "table" then return active == true end

    drawer.iconSize = Clamp(source.iconSize, 16, 64, drawer.iconSize)
    drawer.spacingX = Clamp(source.spacingX, 0, 24, drawer.spacingX)
    drawer.spacingY = Clamp(source.spacingY, 0, 24, drawer.spacingY)
    drawer.triggerSize = Clamp(source.mainIconSize, 10, 40, drawer.triggerSize)
    drawer.triggerOffsetX = Clamp(source.mainIconOffsetX or source.mainIconOffset, -100, 100, drawer.triggerOffsetX)
    drawer.triggerOffsetY = Clamp(source.mainIconOffsetY or source.mainIconOffset, -100, 100, drawer.triggerOffsetY)

    if source.expandMode == "hoverPanel" or source.expandMode == "hoverIcon" or source.expandMode == "click" then
        drawer.expandMode = source.expandMode
    elseif source.expandMode == "clickIcon" then
        drawer.expandMode = "click"
    elseif source.showOnMouseOver == false then
        drawer.expandMode = "click"
    end
    drawer.layoutDirection = (source.panelPosition == "left" or source.panelPosition == "right")
        and "downRight"
        or "rightDown"
    if source.panelBackground == "black" then
        drawer.panelBackground = "solid"
    elseif source.panelBackground == "translucent" then
        drawer.panelBackground = "transparent"
    elseif source.panelBackground == "none" or source.panelBackground == "solid" or source.panelBackground == "transparent" then
        drawer.panelBackground = source.panelBackground
    end
    drawer.triggerVisibility = "always"
    if source.mainIconPosition == "topLeft" or source.mainIconPosition == "topRight"
        or source.mainIconPosition == "bottomLeft" or source.mainIconPosition == "bottomRight"
    then
        drawer.triggerPosition = source.mainIconPosition
    end
    return true
end

local function MigrateSquareElementOffsets(db)
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    if (tonumber(db.migrations.squareElementOffsets) or 0) >= BUTTON_OFFSET_MIGRATION_VERSION then
        return false
    end

    local minimap = type(db.minimap) == "table" and db.minimap or nil
    local elements = minimap and type(minimap.squareElements) == "table" and minimap.squareElements or nil
    if elements then
        for key, fallbackAnchor in pairs(SQUARE_ELEMENT_ANCHORS) do
            local element = elements[key]
            if type(element) == "table" then
                local anchor = SQUARE_ELEMENT_ANCHORS[key]
                if element.anchor == "TOPLEFT" or element.anchor == "TOPRIGHT"
                    or element.anchor == "BOTTOMLEFT" or element.anchor == "BOTTOMRIGHT"
                then
                    anchor = element.anchor
                else
                    anchor = fallbackAnchor
                end
                local x = tonumber(element.offsetX)
                local y = tonumber(element.offsetY)
                if x and (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") then
                    element.offsetX = -x
                end
                if y and (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") then
                    element.offsetY = -y
                end
            end
        end
    end

    db.migrations.squareElementOffsets = BUTTON_OFFSET_MIGRATION_VERSION
    return true
end

local function MigrateQueueOffsets(db)
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    if (tonumber(db.migrations.queueOffsets) or 0) >= QUEUE_OFFSET_MIGRATION_VERSION then
        return false
    end

    local minimap = type(db.minimap) == "table" and db.minimap or nil
    local queue = minimap and type(minimap.queue) == "table" and minimap.queue or nil
    if queue then
        local anchor = Point(queue.anchor, "BOTTOMRIGHT")
        local x = tonumber(queue.offsetX)
        local y = tonumber(queue.offsetY)
        if x and (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") then
            queue.offsetX = -x
        end
        if y and (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") then
            queue.offsetY = -y
        end
    end

    db.migrations.queueOffsets = QUEUE_OFFSET_MIGRATION_VERSION
    return true
end

local function MigrateSquareAppearanceDisplay(db)
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    local version = tonumber(db.migrations.squareAppearanceDisplay) or 0
    if version >= SQUARE_APPEARANCE_DISPLAY_MIGRATION_VERSION then
        return false
    end

    local minimap = type(db.minimap) == "table" and db.minimap or nil
    local appearance = minimap and type(minimap.squareAppearance) == "table" and minimap.squareAppearance or nil
    if appearance then
        if version < 1 then
            appearance.zoneNameMode = appearance.zoneNameOnHover == false and "always" or "hover"
        end
        if type(appearance.showClock) == "boolean" then
            appearance.clockMode = appearance.showClock and "always" or "never"
        elseif type(appearance.hideClock) == "boolean" then
            appearance.clockMode = appearance.hideClock and "never" or "always"
        elseif appearance.clockMode ~= "always" and appearance.clockMode ~= "hover" then
            appearance.clockMode = "never"
        end
        if not VALID_POINTS[appearance.clockPosition] or appearance.clockPosition == "CENTER" then
            appearance.clockPosition = "TOPRIGHT"
        end
        appearance.showClock = nil
        appearance.hideClock = nil
        appearance.zoneNameOnHover = nil
    end

    db.migrations.squareAppearanceDisplay = SQUARE_APPEARANCE_DISPLAY_MIGRATION_VERSION
    return true
end

function Migration:Migrate(profile, db)
    if type(profile) ~= "table" or type(db) ~= "table" then
        return { migrated = false, reason = "missing-profile" }
    end
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    local legacyAlreadyMigrated = (tonumber(db.migrations.legacyMapComponents) or 0) >= MIGRATION_VERSION

    local mapPositionActive = false
    local eqolActive = false
    local drawerActive = false
    local positionMigrated = false
    local eqolMigrated = false
    local drawerMigrated = false
    local enabledFromLegacy = false
    if not legacyAlreadyMigrated then
        local components = type(profile.Components) == "table" and profile.Components or nil
        mapPositionActive = components and components.MapPosition == true or false
        eqolActive = components and components.EQoLAdapter == true or false
        drawerActive = components and components.MinimapCollection == true or false

        positionMigrated = MigrateMapPosition(components, db)
        eqolMigrated = MigrateEQoL(components, db)
        drawerMigrated = MigrateDrawer(components, db, drawerActive)
        enabledFromLegacy = mapPositionActive or eqolActive or drawerActive

        if enabledFromLegacy then
            db.enabled = true
            db.minimap = type(db.minimap) == "table" and db.minimap or {}
            db.minimap.style = "native"
        end
        db.migrations.legacyMapComponents = MIGRATION_VERSION
    end

    local offsetsMigrated = MigrateSquareElementOffsets(db)
    local queueOffsetsMigrated = MigrateQueueOffsets(db)
    local squareAppearanceDisplayMigrated = MigrateSquareAppearanceDisplay(db)
    if legacyAlreadyMigrated
        and not offsetsMigrated
        and not queueOffsetsMigrated
        and not squareAppearanceDisplayMigrated
    then
        return { migrated = false, reason = "already-migrated" }
    end

    return {
        migrated = true,
        enabledFromLegacy = enabledFromLegacy,
        mapPositionActive = mapPositionActive,
        eqolActive = eqolActive,
        drawerActive = drawerActive,
        positionMigrated = positionMigrated,
        eqolMigrated = eqolMigrated,
        drawerMigrated = drawerMigrated,
        offsetsMigrated = offsetsMigrated,
        queueOffsetsMigrated = queueOffsetsMigrated,
        squareAppearanceDisplayMigrated = squareAppearanceDisplayMigrated,
    }
end

function Migration:Run()
    local profile = YMap:GetProfile()
    local db = YMap:EnsureDB()
    return self:Migrate(profile, db)
end
