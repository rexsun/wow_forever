local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsForever then return end

local Data = { definitions = {}, byID = {}, presets = {}, treePresets = {} }

local RED = { 255 / 255, 85 / 255, 85 / 255 }
local GREEN = { 85 / 255, 255 / 255, 85 / 255 }
local WHITE = { 255 / 255, 255 / 255, 255 / 255 }
local BLUE = { 51 / 255, 153 / 255, 255 / 255 }
local SPIRIT = { 102 / 255, 255 / 255, 204 / 255 }
local HEALING = { 136 / 255, 238 / 255, 153 / 255 }
local SPELL = { 197 / 255, 152 / 255, 255 / 255 }
local HIT = { 114 / 255, 224 / 255, 235 / 255 }
local CRIT = { 255 / 255, 153 / 255, 0 / 255 }
local HASTE = { 255 / 255, 255 / 255, 0 / 255 }
local EXPERTISE = { 255 / 255, 204 / 255, 119 / 255 }
local ARMOR = { 204 / 255, 170 / 255, 119 / 255 }
local DEFENSE = { 234 / 255, 215 / 255, 172 / 255 }
local DODGE = { 102 / 255, 204 / 255, 255 / 255 }
local PARRY = { 255 / 255, 119 / 255, 119 / 255 }
local BLOCK = { 184 / 255, 150 / 255, 228 / 255 }
local REGEN = { 102 / 255, 186 / 255, 255 / 255 }
local NEUTRAL = { 231 / 255, 229 / 255, 223 / 255 }

local function Define(id, color, percent, related)
    local prefix = "forever.stat." .. id
    local definition = {
        id = id,
        shortKey = prefix .. ".short",
        nameKey = prefix .. ".name",
        descriptionKey = prefix .. ".description",
        color = { color[1], color[2], color[3] },
        percent = percent,
        related = related,
    }
    Data.definitions[#Data.definitions + 1] = definition
    Data.byID[id] = definition
end

Define("str", RED, false, { "ap", "block_value" })
Define("agi", GREEN, false, { "crit_melee", "crit_ranged", "armor", "dodge", "ap", "rap" })
Define("sta", WHITE, false, { "hp" })
Define("int", BLUE, false, { "mana", "crit_spell" })
Define("spirit", SPIRIT, false, { "regen_cast", "regen_idle" })
Define("ap", RED, false, { "str", "agi", "main_damage", "off_damage" })
Define("rap", RED, false, { "agi", "ranged_damage" })
Define("healing", HEALING, false, {  })
Define("sp_holy", SPELL, false, { "sp_fire", "sp_nature", "sp_frost", "sp_shadow", "sp_arcane" })
Define("sp_fire", SPELL, false, { "sp_holy", "sp_nature", "sp_frost", "sp_shadow", "sp_arcane", "sp_frostfire" })
Define("sp_nature", SPELL, false, { "sp_holy", "sp_fire", "sp_frost", "sp_shadow", "sp_arcane" })
Define("sp_frost", SPELL, false, { "sp_holy", "sp_fire", "sp_nature", "sp_shadow", "sp_arcane", "sp_frostfire" })
Define("sp_shadow", SPELL, false, { "sp_holy", "sp_fire", "sp_nature", "sp_frost", "sp_arcane" })
Define("sp_arcane", SPELL, false, { "sp_holy", "sp_fire", "sp_nature", "sp_frost", "sp_shadow" })
Define("sp_frostfire", SPELL, false, { "sp_frost", "sp_fire" })
Define("hit_melee", HIT, true, { "hit_offhand", "hit_ranged", "hit_spell" })
Define("hit_offhand", HIT, true, { "hit_melee", "hit_ranged", "hit_spell" })
Define("hit_ranged", HIT, true, { "hit_melee", "hit_offhand", "hit_spell" })
Define("hit_spell", HIT, true, { "hit_melee", "hit_offhand", "hit_ranged" })
Define("crit_melee", CRIT, true, { "agi" })
Define("crit_ranged", CRIT, true, { "agi" })
Define("crit_spell", CRIT, true, { "int" })
Define("haste_melee", HASTE, true, { "main_speed", "off_speed" })
Define("haste_ranged", HASTE, true, { "ranged_speed" })
Define("haste_spell", HASTE, true, {  })
Define("expertise", EXPERTISE, true, { "expertise_off" })
Define("expertise_off", EXPERTISE, true, { "expertise" })
Define("hp", WHITE, false, { "sta" })
Define("mana", BLUE, false, { "int" })
Define("armor", ARMOR, false, { "agi" })
Define("defense", DEFENSE, false, {  })
Define("dodge", DODGE, true, { "agi" })
Define("parry", PARRY, true, {  })
Define("block", BLOCK, true, { "block_value" })
Define("block_value", BLOCK, false, { "str" })
Define("regen_cast", REGEN, false, { "spirit", "regen_idle" })
Define("regen_idle", REGEN, false, { "spirit", "regen_cast" })
Define("mp5", REGEN, false, { "regen_cast", "regen_idle" })
Define("piercing", NEUTRAL, false, {  })
Define("armorpen", NEUTRAL, false, {  })
Define("main_speed", NEUTRAL, false, { "haste_melee", "off_speed" })
Define("off_speed", NEUTRAL, false, { "haste_melee", "main_speed" })
Define("ranged_speed", NEUTRAL, false, { "haste_ranged" })
Define("main_skill", NEUTRAL, false, { "off_skill", "ranged_skill" })
Define("off_skill", NEUTRAL, false, { "main_skill", "ranged_skill" })
Define("ranged_skill", NEUTRAL, false, { "main_skill", "off_skill" })
Define("main_damage", NEUTRAL, false, { "ap", "main_speed" })
Define("off_damage", NEUTRAL, false, { "ap", "off_speed" })
Define("ranged_damage", NEUTRAL, false, { "rap", "ranged_speed" })
Define("pet_hp", WHITE, false, { "pet_armor" })
Define("pet_armor", ARMOR, false, { "pet_hp" })
Define("pet_ap", RED, false, {})
Define("pet_hit", HIT, true, {})
Define("pet_crit", CRIT, true, {})

-- A full bar is a visual reference. Damage ranges have no single plotted value.
local meterMaxByID = {
    str = 400, agi = 400, sta = 400, int = 400, spirit = 400,
    ap = 1000, rap = 1500, healing = 700,
    sp_holy = 600, sp_fire = 600, sp_nature = 600, sp_frost = 600,
    sp_shadow = 600, sp_arcane = 600, sp_frostfire = 600,
    hit_melee = 10, hit_offhand = 10, hit_ranged = 10, hit_spell = 10,
    crit_melee = 30, crit_ranged = 30, crit_spell = 30,
    haste_melee = 20, haste_ranged = 20, haste_spell = 20,
    expertise = 10, expertise_off = 10, armor = 6000, defense = 100,
    dodge = 30, parry = 30, block = 30, block_value = 200,
    regen_cast = 200, regen_idle = 300, mp5 = 200, piercing = 100, armorpen = 1000,
    main_speed = 5, off_speed = 5, ranged_speed = 5,
    main_skill = 350, off_skill = 350, ranged_skill = 350,
    pet_hp = 6000, pet_armor = 6000, pet_ap = 1000, pet_hit = 10, pet_crit = 30,
}
local Icons = YUI.API and YUI.API.Icons
local GetStatIcon = Icons and Icons.GetCharacterStatIcon
for id, def in pairs(Data.byID) do
    def.icon, def.meterMax = GetStatIcon and GetStatIcon(id), meterMaxByID[id]
end

Data.schools = {
    PALADIN = { sp_holy = true }, PRIEST = { sp_holy = true, sp_shadow = true },
    SHAMAN = { sp_nature = true, sp_fire = true, sp_frost = true },
    MAGE = { sp_arcane = true, sp_fire = true, sp_frost = true },
    WARLOCK = { sp_shadow = true, sp_fire = true }, DRUID = { sp_nature = true, sp_arcane = true },
}

local function CopyIDs(ids)
    local result = {}
    for i, id in ipairs(ids) do result[i] = id end
    return result
end

local function Preset(classFile, id, rows, core)
    local entries = Data.presets[classFile]
    if not entries then
        entries = {}
        Data.presets[classFile] = entries
    end
    entries[#entries + 1] = {
        id = id,
        nameKey = "forever.preset." .. classFile .. "." .. id,
        rows = CopyIDs(rows),
        core = CopyIDs(core),
    }
end

local PHYSICAL = { "ap", "hit_melee", "crit_melee", "expertise", "haste_melee" }
local TANK = { "hp", "armor", "defense", "dodge", "parry", "block" }
local HEALER = { "healing", "crit_spell", "haste_spell", "regen_cast", "mana" }

Preset("WARRIOR", "arms", PHYSICAL, { "ap" })
Preset("WARRIOR", "fury", PHYSICAL, { "ap" })
Preset("WARRIOR", "protection", TANK, { "hp", "armor" })
Preset("PALADIN", "holy", { "healing", "mana", "crit_spell", "regen_cast", "spirit" }, { "healing" })
Preset("PALADIN", "protection", TANK, { "hp", "armor" })
Preset("PALADIN", "retribution", { "ap", "sp_holy", "hit_melee", "hit_spell", "crit_melee", "expertise" }, { "ap", "sp_holy" })
Preset("HUNTER", "beast", { "rap", "hit_ranged", "crit_ranged", "haste_ranged", "mana" }, { "rap" })
Preset("HUNTER", "marks", { "rap", "hit_ranged", "crit_ranged", "haste_ranged", "mana" }, { "rap" })
Preset("HUNTER", "survival", { "ap", "hit_melee", "crit_melee", "expertise", "mana" }, { "ap" })
Preset("ROGUE", "assassination", PHYSICAL, { "ap" })
Preset("ROGUE", "combat", PHYSICAL, { "ap" })
Preset("ROGUE", "subtlety", PHYSICAL, { "ap" })
Preset("PRIEST", "discipline", { "healing", "crit_spell", "regen_cast", "spirit", "mana" }, { "healing" })
Preset("PRIEST", "holy", { "healing", "crit_spell", "regen_cast", "spirit", "mana" }, { "healing" })
Preset("PRIEST", "shadow", { "sp_shadow", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_shadow" })
Preset("PRIEST", "smite", { "sp_holy", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_holy" })
Preset("SHAMAN", "elemental", { "sp_nature", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_nature" })
Preset("SHAMAN", "enhancement", { "ap", "sp_nature", "hit_melee", "hit_spell", "crit_melee", "expertise" }, { "ap", "sp_nature" })
Preset("SHAMAN", "restoration", HEALER, { "healing" })
Preset("MAGE", "arcane", { "sp_arcane", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_arcane" })
Preset("MAGE", "fire", { "sp_fire", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_fire" })
Preset("MAGE", "frost", { "sp_frost", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_frost" })
Preset("MAGE", "frostfire", { "sp_frostfire", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_frostfire" })
Preset("WARLOCK", "affliction", { "sp_shadow", "hit_spell", "crit_spell", "haste_spell", "hp" }, { "sp_shadow" })
Preset("WARLOCK", "demonology", { "sp_shadow", "hit_spell", "crit_spell", "haste_spell", "hp" }, { "sp_shadow" })
Preset("WARLOCK", "destruction", { "sp_fire", "hit_spell", "crit_spell", "haste_spell", "hp" }, { "sp_fire" })
Preset("DRUID", "balance", { "sp_nature", "hit_spell", "crit_spell", "haste_spell", "regen_cast" }, { "sp_nature" })
Preset("DRUID", "cat", PHYSICAL, { "ap" })
Preset("DRUID", "bear", { "hp", "armor", "defense", "dodge", "ap", "hit_melee" }, { "hp", "armor" })
Preset("DRUID", "restoration", { "healing", "crit_spell", "regen_cast", "spirit", "mana" }, { "healing" })

-- Talent tree order follows YUI.API.Talent.ConfigurationCatalog.
-- Feral shares one tree; bear, Smite and Frostfire remain separate playstyles.
Data.treePresets.WARRIOR = { "arms", "fury", "protection" }
Data.treePresets.PALADIN = { "holy", "protection", "retribution" }
Data.treePresets.HUNTER = { "beast", "marks", "survival" }
Data.treePresets.ROGUE = { "assassination", "combat", "subtlety" }
Data.treePresets.PRIEST = { "discipline", "holy", "shadow" }
Data.treePresets.SHAMAN = { "elemental", "enhancement", "restoration" }
Data.treePresets.MAGE = { "arcane", "fire", "frost" }
Data.treePresets.WARLOCK = { "affliction", "demonology", "destruction" }
Data.treePresets.DRUID = { "balance", "cat", "restoration" }

YUI.CharacterStatsPanelForeverData = Data
