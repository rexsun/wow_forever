local _, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.FocusHelper) then
    YUI = addonTable
end
if not (YUI and YUI.FocusHelper and YUI.FocusHelper.RegisterSubFeature) then return end

local FocusHelper = YUI.FocusHelper

local FocusMarker = {
    id = "focusMarker",
    order = 20,
}

FocusMarker.defaults = {
    focusMarkerEnabled = false,
    focusMarkerIndex = 1,
    focusMarkerOverwrite = true,
}

local SETTINGS_WIDTH = 620
local FIELD_GAP = 16
local FIELD_WIDTH = math.floor((SETTINGS_WIDTH - FIELD_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local CONTROL_WIDTH = FIELD_WIDTH - LABEL_WIDTH - LABEL_GAP
local VALUE_WIDTH = 56
local RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local MARK_NAMES = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
}

local function T(key, fallback)
    return FocusHelper:T(key, fallback)
end

local function ClampMarker(value)
    value = tonumber(value)
    if not value then return FocusMarker.defaults.focusMarkerIndex end
    value = math.floor(value + 0.5)
    if value < 1 then return 1 end
    if value > 8 then return 8 end
    return value
end

local function GetMarkerTexCoord(index)
    index = ClampMarker(index) - 1
    local column = index % 4
    local row = math.floor(index / 4)
    local size = 0.25
    return {
        column * size,
        (column + 1) * size,
        row * size,
        (row + 1) * size,
    }
end

local function RefreshSubFeatures(db)
    if FocusHelper.RefreshSubFeatures then
        FocusHelper:RefreshSubFeatures(db)
    else
        FocusMarker:RefreshRuntime(db)
    end
end

function FocusMarker:NormalizeDB(db)
    if type(db) ~= "table" then return db end
    db.focusMarkerEnabled = db.focusMarkerEnabled == true
    db.focusMarkerIndex = ClampMarker(db.focusMarkerIndex)
    db.focusMarkerOverwrite = db.focusMarkerOverwrite ~= false
    return db
end

function FocusMarker:RefreshRuntime(db)
    self:NormalizeDB(db or FocusHelper:GetDB())
end

function FocusMarker:OnFeatureToggle(enabled, db)
    self:RefreshRuntime(db)
end

local function BuildMarkerOptions()
    local options = {}
    for index = 1, 8 do
        options[#options + 1] = {
            text = T("raid_marker." .. index, MARK_NAMES[index]),
            value = index,
            icon = RAID_MARKER_TEXTURE,
            texCoord = GetMarkerTexCoord(index),
            iconSize = 18,
        }
    end
    return options
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SETTINGS_WIDTH }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SETTINGS_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SETTINGS_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SETTINGS_WIDTH, SETTINGS_WIDTH),
                columns = 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = FIELD_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = CONTROL_WIDTH,
                valueWidth = VALUE_WIDTH,
                valueGap = LABEL_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function FocusMarker:BuildOptions(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())

    local options = {}
    AddAlignedFieldGroup(options, T("settings.focus_marker", "Focus Marker"), {
        {
            type = "checkbox",
            label = T("settings.focus_marker_enable", "Auto mark focus"),
            settingsToggle = "focusMarker",
            searchKey = "settings.focus_marker_enable",
            get = function() return db.focusMarkerEnabled == true end,
            set = function(value)
                db.focusMarkerEnabled = value == true
                RefreshSubFeatures(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.focus_marker_overwrite", "Overwrite existing mark"),
            get = function() return db.focusMarkerOverwrite == true end,
            set = function(value)
                db.focusMarkerOverwrite = value == true
                RefreshSubFeatures(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.focus_marker_icon", "Marker"),
            options = BuildMarkerOptions,
            default = FocusMarker.defaults.focusMarkerIndex,
            get = function() return db.focusMarkerIndex end,
            set = function(value)
                db.focusMarkerIndex = ClampMarker(value)
                RefreshSubFeatures(db)
            end,
        },
    }, { hideDivider = true })

    return options
end

FocusHelper:RegisterSubFeature(FocusMarker)
