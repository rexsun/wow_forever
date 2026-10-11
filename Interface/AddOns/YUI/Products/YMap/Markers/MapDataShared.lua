local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local MapEnhancement = YUI.YMap.Markers or {}
YUI.YMap.Markers = MapEnhancement

local Data = MapEnhancement.Data or {}
MapEnhancement.Data = Data

Data.categories = {
    travel = { order = 10, color = { 0.18, 0.82, 1.00 } },
    service = { order = 20, color = { 1.00, 0.82, 0.10 } },
    profession = { order = 30, color = { 0.35, 1.00, 0.48 } },
    trainer = { order = 35, color = { 1.00, 0.65, 0.25 } },
    equipment = { order = 40, color = { 0.88, 0.45, 1.00 } },
    collection = { order = 50, color = { 1.00, 0.52, 0.76 } },
    special = { order = 60, color = { 1.00, 0.42, 0.20 } },
}

local function HasValidProfessionSkillLineIDs(point)
    local skillLineIDs = point.professionSkillLineIDs
    if point.category ~= "profession" then return skillLineIDs == nil end
    if type(skillLineIDs) ~= "table" then return false end
    for index = 1, #skillLineIDs do
        local skillLineID = skillLineIDs[index]
        if type(skillLineID) ~= "number" or skillLineID <= 0 or skillLineID % 1 ~= 0 then
            return false
        end
    end
    return true
end

function Data:IsValidPoint(point)
    return type(point) == "table"
        and type(point.id) == "string" and point.id ~= ""
        and type(point.labelKey) == "string" and point.labelKey ~= ""
        and (point.compactLabelKey == nil or (type(point.compactLabelKey) == "string" and point.compactLabelKey ~= ""))
        and (point.tooltipTitleKey == nil or (type(point.tooltipTitleKey) == "string" and point.tooltipTitleKey ~= ""))
        and type(point.category) == "string" and self.categories[point.category] ~= nil
        and HasValidProfessionSkillLineIDs(point)
        and (point.class == nil or (type(point.class) == "string" and point.class ~= ""))
        and type(point.x) == "number" and point.x >= 0 and point.x <= 1
        and type(point.y) == "number" and point.y >= 0 and point.y <= 1
end

-- 每种服务只保存一次名称、图标和过滤要求；地点只保存身份、坐标和例外。
Data.types = {
    ["profession.129"] = { labelKey = "profession.129", category = "profession", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", professionSkillLineIDs = {  } },
    ["profession.164"] = { labelKey = "profession.164", category = "profession", icon = "Interface\\Icons\\Trade_BlackSmithing", professionSkillLineIDs = { 164 } },
    ["profession.165"] = { labelKey = "profession.165", category = "profession", icon = "Interface\\Icons\\Trade_LeatherWorking", professionSkillLineIDs = { 165 } },
    ["profession.171"] = { labelKey = "profession.171", category = "profession", icon = "Interface\\Icons\\Trade_Alchemy", professionSkillLineIDs = { 171 } },
    ["profession.182"] = { labelKey = "profession.182", category = "profession", icon = "Interface\\Icons\\Trade_Herbalism", professionSkillLineIDs = { 182 } },
    ["profession.185"] = { labelKey = "profession.185", category = "profession", icon = "Interface\\Icons\\INV_Misc_Food_15", professionSkillLineIDs = {  } },
    ["profession.186"] = { labelKey = "profession.186", category = "profession", icon = "Interface\\Icons\\Trade_Mining", professionSkillLineIDs = { 186 } },
    ["profession.197"] = { labelKey = "profession.197", category = "profession", icon = "Interface\\Icons\\Trade_Tailoring", professionSkillLineIDs = { 197 } },
    ["profession.202"] = { labelKey = "profession.202", category = "profession", icon = "Interface\\Icons\\Trade_Engineering", professionSkillLineIDs = { 202 } },
    ["profession.333"] = { labelKey = "profession.333", category = "profession", icon = "Interface\\Icons\\Trade_Engraving", professionSkillLineIDs = { 333 } },
    ["profession.356"] = { atlas = "Fishing-Hole", labelKey = "profession.356", category = "profession", icon = "Interface\\Icons\\Trade_Fishing", professionSkillLineIDs = {  } },
    ["profession.393"] = { labelKey = "profession.393", category = "profession", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", professionSkillLineIDs = { 393 } },
    ["service.auction"] = { atlas = "Auctioneer", labelKey = "service.auction", category = "service", icon = "Interface\\Icons\\INV_Hammer_15" },
    ["collection.reagents"] = { atlas = "Reagents", labelKey = "collection.reagents", tooltipTitleKey = "collection.reagents.title", category = "collection" },
    ["service.barber"] = { atlas = "Barbershop-32x32", labelKey = "service.barber", category = "service" },
    ["service.transmogrifier"] = { atlas = "poi-transmogrifier", labelKey = "service.transmogrifier", category = "service" },
    ["service.guild"] = { atlas = "Warfronts-FieldMapIcons-Alliance-Banner-Minimap", factionAtlases = { Alliance = "Warfronts-FieldMapIcons-Alliance-Banner-Minimap", Horde = "Warfronts-FieldMapIcons-Horde-Banner-Minimap" }, labelKey = "service.guild", category = "service", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    ["service.stable"] = { atlas = "StableMaster", labelKey = "service.stable", category = "service", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", class = "HUNTER" },
    ["equipment.weapon_trainer"] = { atlas = "Ammunition", labelKey = "equipment.weapon_trainer", category = "equipment", icon = "Interface\\Icons\\INV_Sword_04" },
    ["service.bank"] = { atlas = "Banker", labelKey = "service.bank", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    ["service.inn"] = { atlas = "Innkeeper", labelKey = "service.inn", category = "service", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
    ["trainer.DRUID"] = { atlas = "groupfinder-icon-class-druid", labelKey = "trainer.short.DRUID", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "DRUID" } },
    ["trainer.HUNTER"] = { atlas = "groupfinder-icon-class-hunter", labelKey = "trainer.short.HUNTER", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "HUNTER" } },
    ["trainer.MAGE"] = { atlas = "groupfinder-icon-class-mage", labelKey = "trainer.short.MAGE", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "MAGE" } },
    ["trainer.PALADIN"] = { atlas = "groupfinder-icon-class-paladin", labelKey = "trainer.short.PALADIN", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "PALADIN" } },
    ["trainer.PRIEST"] = { atlas = "groupfinder-icon-class-priest", labelKey = "trainer.short.PRIEST", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "PRIEST" } },
    ["trainer.ROGUE"] = { atlas = "groupfinder-icon-class-rogue", labelKey = "trainer.short.ROGUE", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "ROGUE" } },
    ["trainer.SHAMAN"] = { atlas = "groupfinder-icon-class-shaman", labelKey = "trainer.short.SHAMAN", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "SHAMAN" } },
    ["trainer.WARLOCK"] = { atlas = "groupfinder-icon-class-warlock", labelKey = "trainer.short.WARLOCK", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "WARLOCK" } },
    ["trainer.WARRIOR"] = { atlas = "groupfinder-icon-class-warrior", labelKey = "trainer.short.WARRIOR", category = "trainer", icon = "Interface\\Icons\\INV_Misc_Book_09", trainerClasses = { "WARRIOR" } },
    ["travel.dalaran"] = { atlas = "FlightMasterFerry", labelKey = "travel.dalaran", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" },
    ["travel.flight"] = { atlas = "TaxiNode_Neutral", labelKey = "travel.flight", category = "travel", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
    ["travel.zeppelin.orgrimmar"] = { atlas = "FlightMasterFerry", labelKey = "travel.zeppelin.orgrimmar", tooltipKey = "travel.zeppelin.orgrimmar.description", category = "travel" },
    ["travel.zeppelin.undercity"] = { atlas = "FlightMasterFerry", labelKey = "travel.zeppelin.undercity", tooltipKey = "travel.zeppelin.undercity.description", category = "travel" },
    ["travel.zeppelin.gromgol"] = { atlas = "FlightMasterFerry", labelKey = "travel.zeppelin.gromgol", tooltipKey = "travel.zeppelin.gromgol.description", category = "travel" },
    ["travel.boat.stormwind"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.stormwind", category = "travel" },
    ["travel.boat.darnassus"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.darnassus", category = "travel" },
    ["travel.boat.menethil"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.menethil", category = "travel" },
    ["travel.boat.theramore"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.theramore", category = "travel" },
    ["travel.boat.auberdine"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.auberdine", category = "travel" },
    ["travel.boat.southshore_auberdine"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.southshore_auberdine", category = "travel" },
    ["travel.boat.menethil_southshore"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.menethil_southshore", category = "travel" },
    ["trainer.portal"] = { atlas = "MagePortalAlliance", factionAtlases = { Alliance = "MagePortalAlliance", Horde = "MagePortalHorde" }, labelKey = "trainer.portal", category = "trainer", class = "MAGE" },
    ["travel.boat.auberdine_menethil"] = { atlas = "FlightMasterFerry", labelKey = "travel.boat.auberdine_menethil", category = "travel" },
    ["travel.portal.darnassus"] = { atlas = "MagePortalAlliance", labelKey = "travel.portal.darnassus", category = "travel" },
    ["travel.portal.ruttheran"] = { atlas = "MagePortalAlliance", labelKey = "travel.portal.ruttheran", category = "travel", tooltipKey = "travel.portal.ruttheran.description" },
    ["travel.harbor"] = { atlas = "FlightMasterFerry", labelKey = "travel.harbor", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" },
    ["travel.tram"] = { atlas = "Vehicle-SilvershardMines-MineCartBlue", labelKey = "travel.tram", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" },
}
if YUI.IsRetail then
    Data.types["collection.black_market"] = { labelKey = "poi.recorded.2393.023", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.curious_coins"] = { labelKey = "poi.recorded.627.112", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.heirlooms"] = { labelKey = "poi.recorded.2112.099", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.housing"] = { labelKey = "poi.recorded.628.101", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.pvp_vendors"] = { labelKey = "poi.recorded.627.109", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.quartermaster"] = { labelKey = "poi.recorded.85.146", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.renown"] = { labelKey = "poi.recorded.2472.066", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.resource_market"] = { labelKey = "poi.recorded.2472.063", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.special_mounts"] = { labelKey = "poi.recorded.627.104", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.toys"] = { labelKey = "poi.recorded.627.125", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["collection.toys_books"] = { labelKey = "poi.recorded.2472.062", category = "collection", icon = "Interface\\Icons\\INV_Misc_Gift_01" }
    Data.types["equipment.item_upgrades"] = { labelKey = "poi.recorded.2393.001", category = "equipment", icon = "Interface\\Icons\\INV_Hammer_20" }
    Data.types["equipment.set_conversion"] = { labelKey = "poi.recorded.2393.007", category = "equipment", icon = "Interface\\Icons\\INV_Hammer_20" }
    Data.types["profession.755"] = { labelKey = "profession.755", category = "profession", icon = "Interface\\Icons\\INV_Misc_Gem_01", professionSkillLineIDs = { 755 } }
    Data.types["profession.773"] = { labelKey = "profession.773", category = "profession", icon = "Interface\\Icons\\INV_Inscription_Tradeskill01", professionSkillLineIDs = { 773 } }
    Data.types["profession.794"] = { labelKey = "profession.794", category = "profession", icon = "Interface\\Icons\\Trade_Archaeology", professionSkillLineIDs = {  } }
    Data.types["service.barber"] = { atlas = "Barbershop-32x32", labelKey = "poi.recorded.2393.020", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" }
    Data.types["service.chromie"] = { labelKey = "poi.recorded.85.177", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01", tooltipKey = "poi.tooltip.chromie" }
    Data.types["service.crafting_orders"] = { labelKey = "poi.recorded.2393.006", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" }
    Data.types["service.embassy"] = { labelKey = "poi.recorded.85.141", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" }
    Data.types["service.rostrum_of_transformation"] = { labelKey = "poi.recorded.2393.024", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" }
    Data.types["service.stable"] = { atlas = "StableMaster", labelKey = "poi.recorded.2393.053", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01", class = "HUNTER" }
    Data.types["service.trading_post"] = { labelKey = "poi.recorded.2393.012", category = "service", icon = "Interface\\Icons\\INV_Misc_Coin_01" }
    Data.types["special.brawl"] = { labelKey = "poi.recorded.85.150", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01", tooltipTitleKey = "poi.recorded.85.150.tooltip_title" }
    Data.types["special.brawl.poi_recorded_499_207"] = { labelKey = "poi.recorded.499.207", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01", tooltipTitleKey = "poi.recorded.499.207.tooltip_title" }
    Data.types["special.delves"] = { labelKey = "poi.recorded.2393.022", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.experience_lock"] = { labelKey = "poi.recorded.85.170", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.guild"] = { labelKey = "poi.recorded.85.139", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.ky_veza"] = { labelKey = "poi.recorded.2472.072", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.phase_diving"] = { labelKey = "poi.recorded.2472.061", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.random_dungeon"] = { labelKey = "poi.recorded.627.133", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.si_7"] = { labelKey = "poi.recorded.84.214", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["special.training_dummies"] = { labelKey = "poi.recorded.2393.021", category = "special", icon = "Interface\\Icons\\INV_Misc_Map_01" }
    Data.types["travel.argus_portal"] = { labelKey = "poi.recorded.627.135", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.627.135.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.azj_kahet"] = { labelKey = "poi.recorded.2339.047", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2339.047.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.badlands_portal"] = { labelKey = "poi.recorded.2112.082", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2112.082.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.boralus"] = { labelKey = "poi.recorded.84.190", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.borean_thunder"] = { labelKey = "poi.recorded.85.144", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.borean_tundra"] = { labelKey = "poi.recorded.84.191", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.darnassus"] = { labelKey = "poi.recorded.84.188", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.dornogal_portal"] = { labelKey = "poi.recorded.2472.069", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2472.069.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.dragon_isles"] = { labelKey = "poi.recorded.84.189", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.emerald_dream_portal"] = { labelKey = "poi.recorded.2112.095", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2112.095.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.harai"] = { labelKey = "poi.recorded.2393.010", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2393.010.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.orgrimmar_portal"] = { labelKey = "poi.recorded.2339.026", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2339.026.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.orgrimmar_portal.poi_recorded_2112_073"] = { labelKey = "poi.recorded.2112.073", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2112.073.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.orgrimmar_portal.poi_recorded_627_110"] = { labelKey = "poi.recorded.627.110", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.627.110.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.portal"] = { labelKey = "poi.recorded.627.130", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.dalaran.central_portals" }
    Data.types["travel.portal.poi_recorded_85_142"] = { labelKey = "poi.recorded.85.142", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.orgrimmar.legion_portals" }
    Data.types["travel.portal.poi_recorded_85_152"] = { labelKey = "poi.recorded.85.152", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.orgrimmar.cataclysm_portals" }
    Data.types["travel.portal_room"] = { labelKey = "poi.recorded.85.176", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.portal_training"] = { labelKey = "poi.recorded.627.103", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", class = "MAGE" }
    Data.types["travel.portals"] = { labelKey = "poi.recorded.2393.003", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.portals.poi_recorded_84_197"] = { labelKey = "poi.recorded.84.197", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.84.197.tooltip_title", tooltipKey = "poi.tooltip.stormwind.allied_race_portals" }
    Data.types["travel.portals.poi_recorded_84_200"] = { labelKey = "poi.recorded.84.200", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.84.200.tooltip_title", tooltipKey = "poi.tooltip.stormwind.cataclysm_portals" }
    Data.types["travel.siren_isle"] = { labelKey = "poi.recorded.2339.049", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.stormwind_portal"] = { labelKey = "poi.recorded.2339.027", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2339.027.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.stormwind_portal.poi_recorded_2112_074"] = { labelKey = "poi.recorded.2112.074", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2112.074.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.stormwind_portal.poi_recorded_627_127"] = { labelKey = "poi.recorded.627.127", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.627.127.tooltip_title", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.stranglethorn_vale"] = { labelKey = "poi.recorded.85.145", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.timeways"] = { labelKey = "poi.recorded.2393.005", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.timeways.midnight_s2" }
    Data.types["travel.underbelly"] = { labelKey = "poi.recorded.627.124", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.undercity"] = { labelKey = "poi.recorded.85.147", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind" }
    Data.types["travel.undermine"] = { labelKey = "poi.recorded.2339.051", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipKey = "poi.tooltip.portal" }
    Data.types["travel.voidstorm"] = { labelKey = "poi.recorded.2393.009", category = "travel", icon = "Interface\\Icons\\Spell_Arcane_TeleportStormWind", tooltipTitleKey = "poi.recorded.2393.009.tooltip_title", tooltipKey = "poi.tooltip.portal" }
end
for typeID, definition in pairs(Data.types) do
    definition.__index, definition.typeID = definition, typeID
end

local function GroupDefinition(self, typeID, faction)
    local definition = assert(self.types[typeID], typeID)
    if faction then
        definition.factions = definition.factions or {}
        if not definition.factions[faction] then
            local variant = setmetatable({faction=faction}, definition)
            if definition.factionAtlases then variant.atlas = definition.factionAtlases[faction] end
            variant.__index = variant
            definition.factions[faction] = variant
        end
        definition = definition.factions[faction]
    end
    return definition
end

function Data:Point(id, typeID, x, y, options)
    local point = {id=id,x=x,y=y}
    for key,value in pairs(options or {}) do if key ~= "faction" then point[key]=value end end
    return setmetatable(point,GroupDefinition(self,typeID,options and options.faction))
end

-- 仅存紧凑记录；普通组每项 id/x/y，航点组每项 id/x/y/taxiNodeID。
function Data:RegisterGroup(mapID, typeID, faction, values, tips)
    self.records = self.records or {}
    local groups = self.records[mapID]
    if not groups then groups = {}; self.records[mapID] = groups end
    local stride = typeID == "travel.flight" and 4 or 3
    assert(#values % stride == 0, "Invalid marker group")
    values.definition = GroupDefinition(self, typeID, faction)
    values.stride, values.tips = stride, tips
    groups[#groups+1] = values
end

-- 不缓存解码结果；调用者仅持有当前地图，关闭/切图即可释放。
function Data:GetMapPoints(mapID)
    local groups = self.records and self.records[mapID]
    if not groups then return nil end
    local points = {}
    for _, group in ipairs(groups) do
        for offset=1,#group,group.stride do
            local index = (offset-1)/group.stride+1
            local point = {id=group[offset],x=group[offset+1],y=group[offset+2]}
            if group.stride == 4 then point.taxiNodeID = group[offset+3] end
            if group.weaponTrainerSiteID then point.weaponTrainerSiteID = group.weaponTrainerSiteID end
            if group.tips then point.tooltipKey = group.tips[index] end
            points[#points+1] = setmetatable(point,group.definition)
        end
    end
    return points
end

function Data:SetPointPosition(mapID, pointID, x, y)
    for _, group in ipairs(self.records and self.records[mapID] or {}) do
        for offset=1,#group,group.stride do
            if group[offset] == pointID then
                group[offset+1],group[offset+2] = x,y
                return true
            end
        end
    end
    return false
end

function Data:HasFlight(mapID, nodeID)
    if not nodeID then return false end
    for _, group in ipairs(self.records and self.records[mapID] or {}) do
        if group.stride == 4 then
            for offset=4,#group,4 do if group[offset] == nodeID then return true end end
        end
    end
    return false
end

function Data:HasUnsyncedFlight(known)
    for _, groups in pairs(self.records or {}) do
        for _, group in ipairs(groups) do
            if group.stride == 4 then
                for offset=4,#group,4 do if known[group[offset]] == nil then return true end end
            end
        end
    end
    return false
end
