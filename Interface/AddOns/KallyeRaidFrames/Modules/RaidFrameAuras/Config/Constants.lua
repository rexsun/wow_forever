local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local Constants = ns.Constants or {}
ns.Constants = Constants

Constants.MAX_COMPACT_PARTY_FRAMES = MEMBERS_PER_RAID_GROUP or 5
Constants.MAX_RAID_FRAMES = MAX_RAID_MEMBERS or 40
Constants.MAX_PRIVATE_AURA_SLOTS = 4
Constants.DEFAULT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
Constants.FONT_PATHS = {
    ["Default"] = Constants.DEFAULT_FONT,
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Unit Name"] = UNIT_NAME_FONT or Constants.DEFAULT_FONT,
    ["Damage"] = DAMAGE_TEXT_FONT or Constants.DEFAULT_FONT,
}

Constants.VALID_AURA_FRAME_STRATA = {
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
}

Constants.VALID_AURA_ANCHOR_TARGETS = {
    FRAME = true,
    HEALTH_BAR = true,
}

Constants.CATEGORY_SCALE_MIN = 0.5
Constants.CATEGORY_SCALE_MAX = 2
Constants.CATEGORY_SCALE_PERCENT_MIN = Constants.CATEGORY_SCALE_MIN * 100
Constants.CATEGORY_SCALE_PERCENT_MAX = Constants.CATEGORY_SCALE_MAX * 100
Constants.DEFAULT_BORDER_INSET = 0
Constants.DEFAULT_EXPIRING_BORDER_INSET = 0
Constants.PREVIEW_WIDTH_MIN = 72
Constants.PREVIEW_WIDTH_MAX = 144
Constants.PREVIEW_HEIGHT_MIN = 36
Constants.PREVIEW_HEIGHT_MAX = 72
Constants.ANCHOR_FACTORS = {
    TOPLEFT = { x = 0, y = 1 },
    TOP = { x = 0.5, y = 1 },
    TOPRIGHT = { x = 1, y = 1 },
    LEFT = { x = 0, y = 0.5 },
    CENTER = { x = 0.5, y = 0.5 },
    RIGHT = { x = 1, y = 0.5 },
    BOTTOMLEFT = { x = 0, y = 0 },
    BOTTOM = { x = 0.5, y = 0 },
    BOTTOMRIGHT = { x = 1, y = 0 },
}

ns.FONT_OPTIONS = {
    { value = "Default", text = "WoW Default" },
    { value = "Friz Quadrata TT", text = "Friz Quadrata TT" },
    { value = "Arial Narrow", text = "Arial Narrow" },
    { value = "Morpheus", text = "Morpheus" },
    { value = "Skurri", text = "Skurri" },
    { value = "Unit Name", text = "Unit Name" },
    { value = "Damage", text = "Damage" },
}
