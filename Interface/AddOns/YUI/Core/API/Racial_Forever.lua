local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.IsForever) then return end
YUI.API = YUI.API or {}
-- Forever 1.60.1.70205: race masks and spell families from DB2.
-- Passive traits and triggered damage/healing spells are not cooldown presets.
YUI.API.ForeverRacialCatalog = {
    races = { SKYBORNE_HIGHORDER = 95, SKYBORNE_WINDSHAPER = 96 },
    presets = {
        HUMAN = { 1259718, 20600,
            { spellID = 19275, aliases = {19274,19273,19271,13896}, class = "PRIEST" },
            { spellID = 1277378, aliases = {1277377,1277376,1277374,1277372,1277371,1277370}, class = "PRIEST" },
        },
        DWARF = { 20594, 2481,
            { spellID = 19243, aliases = {19242,19241,19240,19238,19236,13908}, class = "PRIEST" },
            { spellID = 1277335, aliases = {1277334,1277333,1277332,1277331}, class = "PRIEST" },
        },
        NIGHTELF = { 1259799, 20580,
            { spellID = 19305, aliases = {19304,19303,19302,19299,19296,10797}, class = "PRIEST" },
            { spellID = 2651, class = "PRIEST" },
        },
        GNOME = { 20589,
            { spellID = 1259812, aliases = {1259813,1259817,1259821,1259823} },
            { spellID = 1277455, class = "PRIEST" },
            { spellID = 1277640, aliases = {1277639,1277638,1277634,1277462}, class = "PRIEST" },
        },
        ORC = { 20572, 1299026 },
        SCOURGE = { 7744, 20577,
            { spellID = 19266, aliases = {19265,19264,19262,19261,2652}, class = "PRIEST" },
            { spellID = 1277328, aliases = {1277327,1277326,1277325,1277324}, class = "PRIEST" },
        },
        TAUREN = { 20549, 1312643 },
        TROLL = { 20554, 1260270,
            { spellID = 19285, aliases = {19284,19283,19282,19281,9035}, class = "PRIEST" },
            { spellID = 19312, aliases = {19311,19310,19309,19308,18137}, class = "PRIEST" },
        },
        SKYBORNE_HIGHORDER = { 1259416, 1259705 },
        SKYBORNE_WINDSHAPER = { 1259416, 1259686 },
    },
}
