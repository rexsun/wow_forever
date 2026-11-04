local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end

A.Catalog = {
    Details = { "combat", "instance" }, DBM = { "instance" }, BigWigs = { "instance" }, LittleWigs = { "instance" },
    WeakAuras = { "combat", "interface" }, Cell = { "healing", "frames" }, Grid2 = { "healing", "frames" },
    Plater = { "nameplates" }, Platynator = { "nameplates" }, ThreatPlates = { "nameplates" },
    ElvUI = { "interface", "frames" }, EllesmereUI = { "interface" }, NDui = { "interface" }, Bagnon = { "bags" }, Baganator = { "bags" },
    AdiBags = { "bags" }, BetterBags = { "bags" }, Auctionator = { "trade" }, TradeSkillMaster = { "trade" },
    TomTom = { "map" }, HandyNotes = { "map" }, Leatrix_Maps = { "map" }, WorldQuestTracker = { "quest", "map" },
    Questie = { "quest", "map" }, MythicDungeonTools = { "instance" }, RaiderIO = { "instance" },
    Pawn = { "equipment" }, Simulationcraft = { "equipment" }, Masque = { "interface" },
    YUI = { "interface" }, YUI_NovaToolbox = { "utility" }, YUI_AddonAssistant = { "utility" },
    YUI_AuctionHelper = { "trade" }, YUI_Halo = { "combat" }, YUI_YHUD = { "combat" }, YUI_YActionBar = { "interface" }, YUI_OrbitInfoBar = { "utility" },
}
A.TagOrder = { "combat", "instance", "healing", "frames", "nameplates", "interface", "bags", "trade", "map", "quest", "equipment", "utility" }
A.TagColors = { combat = "color.state.error", instance = "color.accent.primary", healing = "color.state.success",
    frames = "color.text.accent", nameplates = "color.state.warning", interface = "color.text.secondary",
    bags = "color.state.warning", trade = "color.text.heading", map = "color.state.success", quest = "color.text.accent",
    equipment = "color.accent.primary", utility = "color.text.secondary" }
A.SceneOrder = { "default", "dungeon", "raid", "battleground", "arena" }
A.SceneAtlas = {default="QuestBonusObjective",world="QuestBonusObjective",dungeon="delves-regular",raid="vignettekillboss",
    battleground="Warfronts-FieldMapIcons-Neutral-Banner-Minimap",arena="VignetteEventElite"}

function A.Classify(name, dependencies, metadata)
    local tags = A.Catalog[name]
    local prefix = name:match("^([^-_]+)[-_]")
    tags = tags or A.Catalog[prefix]
    local group = type(metadata) == "string" and metadata:match("^%s*([%w_!%-]+)%s*$") or nil
    if group == name then group = nil end
    if name:match("^DBM%-") and name ~= "DBM-Core" then group = "DBM-Core"
    elseif name:match("^BigWigs_") then group = "BigWigs" end
    -- Managed diagnostic slots are one visual family, independent of their own Group metadata.
    if name:match("^Lychee Dev ") then group = "Lychee Dev"; tags = {"utility"} end
    tags = tags or A.Catalog[group]
    return A.Model.Copy(tags or {}), group
end
