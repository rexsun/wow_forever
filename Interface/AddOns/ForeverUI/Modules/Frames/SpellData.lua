local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- The Classic spells a healer actually watches, so nobody has to type them.
--
-- Names only, deliberately: HealForever matches auras by name, a name casts and
-- matches whatever rank you have, and Forever is free to renumber every spell
-- ID it likes without breaking any of this. Anything missing can still be
-- typed in by hand.
--
-- Dispel types are the Classic rules, which are not the modern ones:
--   Priest   Magic, Disease
--   Paladin  Magic, Poison, Disease
--   Druid    Curse, Poison
--   Shaman   Poison, Disease
--   Mage     Curse
-- Warlocks and everyone else remove nothing from a friendly player.

ns.DISPEL_BY_CLASS = {
  PRIEST  = { Magic = true, Disease = true },
  PALADIN = { Magic = true, Poison = true, Disease = true },
  DRUID   = { Curse = true, Poison = true },
  SHAMAN  = { Poison = true, Disease = true },
  MAGE    = { Curse = true },
}

-- category = what it is, class = whose it is (nil for anyone's),
-- dispel = which cure removes it.
ns.SPELL_LIBRARY = {
  {
    name = "Heals over time and shields",
    note = "Put these in a corner to see at a glance who already has one.",
    spells = {
      { name = "Renew", class = "PRIEST" },
      { name = "Power Word: Shield", class = "PRIEST" },
      { name = "Weakened Soul", class = "PRIEST",
        note = "can't be shielded again until it falls off" },
      { name = "Forbearance", class = "PALADIN",
        note = "can't take another Hand or Shield until it falls off" },
      { name = "Healing Way", class = "SHAMAN",
        note = "stacks from Healing Wave; more healing on this target" },
      { name = "Rejuvenation", class = "DRUID" },
      { name = "Regrowth", class = "DRUID" },
      { name = "Abolish Poison", class = "DRUID" },
      { name = "Abolish Disease", class = "PRIEST" },
      { name = "Healing Stream Totem", class = "SHAMAN" },
    },
  },
  {
    name = "Raid buffs worth seeing",
    note = "Missing buffs show up as an empty corner.",
    spells = {
      { name = "Power Word: Fortitude", class = "PRIEST" },
      { name = "Divine Spirit", class = "PRIEST" },
      { name = "Shadow Protection", class = "PRIEST" },
      { name = "Inner Fire", class = "PRIEST" },
      { name = "Fear Ward", class = "PRIEST" },
      { name = "Mark of the Wild", class = "DRUID" },
      { name = "Thorns", class = "DRUID" },
      { name = "Arcane Intellect", class = "MAGE" },
      { name = "Blessing of Might", class = "PALADIN" },
      { name = "Blessing of Wisdom", class = "PALADIN" },
      { name = "Blessing of Kings", class = "PALADIN" },
      { name = "Blessing of Salvation", class = "PALADIN" },
      { name = "Blessing of Light", class = "PALADIN" },
      { name = "Soulstone Resurrection", class = "WARLOCK" },
    },
  },
  {
    name = "Immunities and saves",
    note = "Don't waste a cast on someone who is already safe.",
    spells = {
      { name = "Divine Shield", class = "PALADIN" },
      { name = "Blessing of Protection", class = "PALADIN" },
      { name = "Divine Protection", class = "PALADIN" },
      { name = "Ice Block", class = "MAGE" },
      { name = "Shield Wall", class = "WARRIOR" },
      { name = "Last Stand", class = "WARRIOR" },
      { name = "Evasion", class = "ROGUE" },
      { name = "Spirit of Redemption", class = "PRIEST" },
    },
  },
  {
    name = "Magic - cured by Priest and Paladin",
    dispel = "Magic",
    spells = {
      { name = "Polymorph" },
      { name = "Fear" },
      { name = "Howl of Terror" },
      { name = "Frost Nova" },
      { name = "Frostbolt" },
      { name = "Curse of Tongues", dispel = "Curse" },
      { name = "Immolate" },
      { name = "Shadow Word: Pain" },
      { name = "Devouring Plague" },
      { name = "Holy Fire" },
      { name = "Moonfire" },
      { name = "Insect Swarm" },
      { name = "Flame Shock" },
      { name = "Frost Shock" },
      { name = "Judgement of Justice" },
      { name = "Hammer of Justice" },
      { name = "Mind Control" },
      { name = "Psychic Scream" },
    },
  },
  {
    name = "Curses - cured by Druid and Mage",
    dispel = "Curse",
    spells = {
      { name = "Curse of Agony" },
      { name = "Curse of Weakness" },
      { name = "Curse of Tongues" },
      { name = "Curse of Recklessness" },
      { name = "Curse of the Elements" },
      { name = "Curse of Shadow" },
      { name = "Curse of Doom" },
      { name = "Entangling Roots" },
      { name = "Hex of Weakness" },
    },
  },
  {
    name = "Poisons - cured by Druid, Paladin and Shaman",
    dispel = "Poison",
    spells = {
      { name = "Deadly Poison" },
      { name = "Crippling Poison" },
      { name = "Mind-numbing Poison" },
      { name = "Wound Poison" },
      { name = "Serpent Sting" },
      { name = "Scorpid Sting" },
      { name = "Viper Sting" },
      { name = "Wyvern Sting" },
    },
  },
  {
    name = "Diseases - cured by Priest, Paladin and Shaman",
    dispel = "Disease",
    spells = {
      { name = "Disease Cloud" },
      { name = "Devouring Plague", note = "counts as Magic in Classic" },
      { name = "Shadow Vulnerability" },
      { name = "Necrotic Poison" },
    },
  },
  {
    name = "Damage over time - your own, on your target",
    note = "These belong on the target debuff row rather than a party frame.",
    spells = {
      { name = "Shadow Word: Pain", class = "PRIEST" },
      { name = "Devouring Plague", class = "PRIEST" },
      { name = "Holy Fire", class = "PRIEST" },
      { name = "Vampiric Embrace", class = "PRIEST" },
      { name = "Moonfire", class = "DRUID" },
      { name = "Insect Swarm", class = "DRUID" },
      { name = "Rip", class = "DRUID" },
      { name = "Corruption", class = "WARLOCK" },
      { name = "Curse of Agony", class = "WARLOCK" },
      { name = "Immolate", class = "WARLOCK" },
      { name = "Siphon Life", class = "WARLOCK" },
      { name = "Serpent Sting", class = "HUNTER" },
      { name = "Rupture", class = "ROGUE" },
      { name = "Garrote", class = "ROGUE" },
      { name = "Rend", class = "WARRIOR" },
      { name = "Deep Wound", class = "WARRIOR" },
      { name = "Flame Shock", class = "SHAMAN" },
      { name = "Pyroblast", class = "MAGE" },
      { name = "Ignite", class = "MAGE" },
    },
  },
  {
    name = "Trouble on a friendly player",
    note = "Healing reduced, silenced, or about to die to something.",
    spells = {
      { name = "Mortal Strike", note = "healing taken is halved" },
      { name = "Silence" },
      { name = "Kidney Shot" },
      { name = "Cheap Shot" },
      { name = "Sap" },
      { name = "Blind" },
      { name = "Gouge" },
      { name = "Hamstring" },
      { name = "Sunder Armor" },
      { name = "Demoralizing Shout" },
      { name = "Corrupted Blood" },
      { name = "Shadow Flame" },
      { name = "Living Bomb" },
      { name = "Ignite Mana" },
    },
  },
}

-- WHAT A HEALER SEES BEFORE CONFIGURING ANYTHING
--
-- Corners are 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right, matching
-- ns.WATCH_CORNERS. Each class gets its own heal-over-time where it has one,
-- and the debuff that says "don't bother, it won't land" - Weakened Soul for a
-- Priest, Forbearance for a Paladin - because casting into those is the
-- mistake that costs someone their life.
ns.STARTER_WATCH = {
  PRIEST = {
    { spell = "Renew", corner = 1, mine = "mine" },
    { spell = "Power Word: Shield", corner = 2, mine = "any" },
    { spell = "Weakened Soul", corner = 4, mine = "any" },
  },
  DRUID = {
    { spell = "Rejuvenation", corner = 1, mine = "mine" },
    { spell = "Regrowth", corner = 2, mine = "mine" },
    { spell = "Abolish Poison", corner = 3, mine = "any" },
    { spell = "Power Word: Shield", corner = 4, mine = "any" },
  },
  PALADIN = {
    { spell = "Divine Shield", corner = 1, mine = "any" },
    { spell = "Blessing of Protection", corner = 2, mine = "any" },
    { spell = "Forbearance", corner = 4, mine = "any" },
    { spell = "Power Word: Shield", corner = 3, mine = "any" },
  },
  SHAMAN = {
    { spell = "Healing Way", corner = 1, mine = "mine" },
    { spell = "Power Word: Shield", corner = 2, mine = "any" },
    { spell = "Weakened Soul", corner = 4, mine = "any" },
  },
}

-- Everyone else still heals sometimes: a Warlock's Soulstone and whoever's
-- shield is on the tank are worth seeing whatever you are.
ns.STARTER_WATCH_ANY = {
  { spell = "Power Word: Shield", corner = 2, mine = "any" },
  { spell = "Soulstone Resurrection", corner = 3, mine = "any" },
}

-- Put the starter set in. Once per class per profile, and never over a list
-- someone has already built - `force` is the button on the Auras page.
function ns.ApplyStarterWatch(force)
  local class
  if UnitClass then
    _, class = UnitClass("player")
  end
  local set = (class and ns.STARTER_WATCH[class]) or ns.STARTER_WATCH_ANY
  ns.db.starterWatch = ns.db.starterWatch or {}
  if not force then
    if ns.db.starterWatch[class or "OTHER"] or #ns.db.auraWatch > 0 then
      return nil
    end
  end
  ns.db.starterWatch[class or "OTHER"] = true

  local added = 0
  for _, entry in ipairs(set) do
    if ns.AddWatch(entry.spell) then
      local watch = ns.db.auraWatch[#ns.db.auraWatch]
      watch.corner, watch.mine = entry.corner, entry.mine
      added = added + 1
    end
  end
  if added > 0 then
    ns.SetSetting("auraWatch", ns.db.auraWatch)
  end
  return added > 0 and added or nil
end

-- The categories that matter to this character first: what you can cure, and
-- what your class puts on people, before everyone else's.
function ns.LibraryForPlayer()
  local class
  if UnitClass then
    _, class = UnitClass("player")
  end
  local cures = class and ns.DISPEL_BY_CLASS[class] or {}
  local mine, theirs = {}, {}
  for _, category in ipairs(ns.SPELL_LIBRARY) do
    local relevant = (category.dispel and cures[category.dispel]) or nil
    if relevant then
      mine[#mine + 1] = category
    else
      theirs[#theirs + 1] = category
    end
  end
  local ordered = {}
  for _, c in ipairs(mine) do ordered[#ordered + 1] = c end
  for _, c in ipairs(theirs) do ordered[#ordered + 1] = c end
  return ordered, cures
end

-- Flat list of { header = "..." } and { spell = "...", note = "..." } rows,
-- which is what a scrolling list wants.
function ns.LibraryRows(filter)
  local rows = {}
  filter = (filter or ""):lower()
  for _, category in ipairs(ns.LibraryForPlayer()) do
    local matches = {}
    for _, spell in ipairs(category.spells) do
      if filter == "" or spell.name:lower():find(filter, 1, true) then
        matches[#matches + 1] = spell
      end
    end
    if #matches > 0 then
      rows[#rows + 1] = { header = category.name, note = category.note }
      for _, spell in ipairs(matches) do
        rows[#rows + 1] = { spell = spell.name, note = spell.note, class = spell.class }
      end
    end
  end
  return rows
end

---------------------------------------------------------------------------
-- Buffs you hand out
---------------------------------------------------------------------------

-- What each class is expected to keep on the group. The first name is the one
-- you cast (and the one looked up in your spellbook - a buff you haven't
-- learned is never asked for); the rest count as "has it", whoever cast them.
--   manaOnly  only matters to someone with a mana bar
--   prefix    any aura starting with one of these, cast by YOU, counts
--             (a Paladin gives each player one blessing, of several kinds)
--   off       listed, but not nagged about until you switch it on
ns.GROUP_BUFFS = {
  PRIEST = {
    { spell = "Power Word: Fortitude", also = { "Prayer of Fortitude" } },
    { spell = "Divine Spirit", also = { "Prayer of Spirit" }, off = true },
    { spell = "Shadow Protection", also = { "Prayer of Shadow Protection" }, off = true },
  },
  DRUID = {
    { spell = "Mark of the Wild", also = { "Gift of the Wild" } },
    { spell = "Thorns", off = true },
  },
  MAGE = {
    { spell = "Arcane Intellect", also = { "Arcane Brilliance" }, manaOnly = true },
  },
  PALADIN = {
    { spell = "Blessing of Might", label = "A blessing from you", mine = true,
      prefix = { "Blessing of ", "Greater Blessing of " },
      -- The prefix only works in English; these are what it means, by name,
      -- so a Russian or German client (translated below) matches them too.
      covers = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation",
        "Blessing of Light", "Blessing of Sanctuary", "Greater Blessing of Might", "Greater Blessing of Wisdom",
        "Greater Blessing of Kings", "Greater Blessing of Salvation", "Greater Blessing of Light",
        "Greater Blessing of Sanctuary" } },
  },
}

---------------------------------------------------------------------------
-- Spell names in the game's own language
---------------------------------------------------------------------------

-- Every spell named in this engine's lists is written in English, and the
-- game names spells in the player's language: on a Russian client the
-- spellbook says "Знак дикой природы", never "Mark of the Wild", so Buff
-- Watch couldn't find a Druid's buffs (CurseForge comment, 25 Sept 2026),
-- and the same went for the starter watch, the default heal on left click,
-- taunts and resurrections. Each English name is looked up by spell ID and
-- swapped for the game's own name at start-up. On an English client nothing
-- changes. IDs from the Classic SpellName and SkillLineAbility tables
-- (1.15.9; a few newer spells from 5.5.4): the player's own rank, the one
-- whose name most ranks share in every language (Blizzard translates a few
-- ranks differently), original-game IDs before Season of Discovery's.
-- Checked in German, French, Spanish (both), Portuguese, Russian, Korean
-- and both Chinese; Italian Classic is untranslated, so it stays English.
-- A name without an ID stays English.
ns.SPELL_IDS = {
  ["Abolish Disease"] = 552, ["Abolish Poison"] = 2893, ["Ancestral Spirit"] = 20777,
  ["Arcane Brilliance"] = 23028, ["Arcane Intellect"] = 10157, ["Battle Shout"] = 25289,
  ["Blessing of Kings"] = 20217, ["Blessing of Light"] = 19979, ["Blessing of Might"] = 25291,
  ["Blessing of Protection"] = 10278, ["Blessing of Salvation"] = 1038,
  ["Blessing of Sanctuary"] = 20914, ["Blessing of Wisdom"] = 25290, ["Blind"] = 2094,
  ["Cheap Shot"] = 1833, ["Cleanse"] = 4987, ["Corrupted Blood"] = 24328, ["Corruption"] = 25311,
  ["Crippling Poison"] = 3420, ["Cure Disease"] = 2870, ["Cure Poison"] = 8946,
  ["Curse of Agony"] = 11713, ["Curse of Doom"] = 603, ["Curse of Recklessness"] = 11717,
  ["Curse of Shadow"] = 17937, ["Curse of Tongues"] = 11719, ["Curse of Weakness"] = 11708,
  ["Curse of the Elements"] = 11722, ["Dark Command"] = 56222, ["Deadly Poison"] = 2835,
  ["Death Grip"] = 1219093, ["Deep Wound"] = 12721, ["Demoralizing Shout"] = 11556,
  ["Detect Invisibility"] = 2970, ["Devouring Plague"] = 19280, ["Disease Cloud"] = 12187,
  ["Dispel Magic"] = 988, ["Distracting Shot"] = 20736, ["Divine Protection"] = 5573,
  ["Divine Shield"] = 1020, ["Divine Spirit"] = 27841, ["Earth Shock"] = 10414,
  ["Entangling Roots"] = 9853, ["Evasion"] = 5277, ["Fear"] = 6215, ["Fear Ward"] = 6346,
  ["Flame Shock"] = 29228, ["Flash Heal"] = 10917, ["Flash of Light"] = 19993,
  ["Forbearance"] = 25771, ["Frost Nova"] = 10230, ["Frost Shock"] = 10473, ["Frostbolt"] = 25304,
  ["Garrote"] = 11290, ["Gift of the Wild"] = 21850, ["Gouge"] = 11286,
  ["Greater Blessing of Kings"] = 25898, ["Greater Blessing of Light"] = 25890,
  ["Greater Blessing of Might"] = 25916, ["Greater Blessing of Salvation"] = 25895,
  ["Greater Blessing of Sanctuary"] = 25899, ["Greater Blessing of Wisdom"] = 25918,
  ["Greater Heal"] = 25314, ["Growl"] = 14927, ["Hammer of Justice"] = 10308, ["Hamstring"] = 7373,
  ["Hand of Reckoning"] = 407631, ["Heal"] = 6064, ["Healing Stream Totem"] = 10463,
  ["Healing Touch"] = 25297, ["Healing Wave"] = 25357, ["Healing Way"] = 29206,
  ["Hex of Weakness"] = 19285, ["Holy Fire"] = 15267, ["Holy Light"] = 25292,
  ["Howl of Terror"] = 17928, ["Ice Block"] = 11958, ["Ignite"] = 12848, ["Ignite Mana"] = 19659,
  ["Immolate"] = 25309, ["Inner Fire"] = 10952, ["Innervate"] = 29166, ["Insect Swarm"] = 24977,
  ["Intervene"] = 403338, ["Judgement of Justice"] = 20184, ["Kick"] = 1769,
  ["Kidney Shot"] = 8643, ["Last Stand"] = 12976, ["Lesser Heal"] = 2053,
  ["Lesser Healing Wave"] = 10468, ["Living Bomb"] = 20475, ["Mark of the Wild"] = 9885,
  ["Mind Control"] = 10912, ["Mind-numbing Poison"] = 5763, ["Misdirection"] = 56879,
  ["Mocking Blow"] = 20560, ["Moonfire"] = 9835, ["Mortal Strike"] = 21553,
  ["Necrotic Poison"] = 28776, ["Polymorph"] = 28272, ["Power Word: Fortitude"] = 10938,
  ["Power Word: Shield"] = 10901, ["Prayer of Fortitude"] = 21564,
  ["Prayer of Shadow Protection"] = 27683, ["Prayer of Spirit"] = 27681, ["Provoke"] = 115546,
  ["Psychic Scream"] = 10890, ["Purge"] = 8012, ["Purify"] = 1152, ["Pyroblast"] = 18809,
  ["Raise Ally"] = 61999, ["Rebirth"] = 20748, ["Reckoning"] = 20182, ["Redemption"] = 20773,
  ["Regrowth"] = 9858, ["Rejuvenation"] = 25299, ["Remove Curse"] = 2782,
  ["Remove Lesser Curse"] = 475, ["Rend"] = 11574, ["Renew"] = 25315, ["Resurrection"] = 20770,
  ["Resuscitate"] = 115178, ["Return"] = 41060, ["Revive"] = 437138, ["Righteous Defense"] = 31789,
  ["Rip"] = 9896, ["Rupture"] = 11275, ["Sap"] = 11297, ["Scorpid Sting"] = 14277,
  ["Serpent Sting"] = 25295, ["Shadow Flame"] = 22539, ["Shadow Protection"] = 10958,
  ["Shadow Vulnerability"] = 15258, ["Shadow Word: Pain"] = 10894, ["Shield Wall"] = 871,
  ["Silence"] = 15487, ["Siphon Life"] = 18881, ["Soulstone"] = 6203,
  ["Soulstone Resurrection"] = 20707, ["Spellsteal"] = 56602, ["Spirit of Redemption"] = 20711,
  ["Sunder Armor"] = 11597, ["Taunt"] = 355, ["Thorns"] = 9910, ["Torment"] = 11775,
  ["Tranquilizing Shot"] = 19801, ["Tricks of the Trade"] = 63898, ["Unending Breath"] = 5697,
  ["Vampiric Embrace"] = 15286, ["Viper Sting"] = 14280, ["Weakened Soul"] = 6788,
  ["Wound Poison"] = 13220, ["Wyvern Sting"] = 24135,
}

local function IsEnglish()
  local locale = GetLocale and GetLocale()
  return locale == nil or locale == "enUS" or locale == "enGB"
end

local function GameName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return nil
end

-- The game's name for an English spell name (the name itself if unknown).
local localNames = {}
function ns.LocalSpell(name)
  if type(name) ~= "string" or IsEnglish() then return name end
  local cached = localNames[name]
  if cached then return cached end
  local id = ns.SPELL_IDS[name]
  local found = id and GameName(id)
  if found then localNames[name] = found end
  return found or name
end

local function SwapList(list)
  local n = 0
  for i, name in ipairs(list or {}) do
    local mine = ns.LocalSpell(name)
    if mine ~= name then list[i], n = mine, n + 1 end
  end
  return n
end

local function SwapField(entry, key)
  local name = entry[key]
  local mine = ns.LocalSpell(name)
  if mine ~= name then
    entry[key] = mine
    return 1
  end
  return 0
end

local function SwapKeys(map)
  local n = 0
  for name, value in pairs(ns.CopyTable(map or {})) do
    local mine = ns.LocalSpell(name)
    if mine ~= name then map[name], map[mine], n = nil, value, n + 1 end
  end
  return n
end

-- Put the game's names into every list. Once; returns how many changed.
local localized
function ns.LocalizeSpellNames()
  if localized or IsEnglish() then return 0 end
  localized = true
  local n = 0
  for _, category in ipairs(ns.SPELL_LIBRARY or {}) do
    for _, spell in ipairs(category.spells or {}) do n = n + SwapField(spell, "name") end
  end
  for _, set in pairs(ns.STARTER_WATCH or {}) do
    for _, entry in ipairs(set) do n = n + SwapField(entry, "spell") end
  end
  for _, entry in ipairs(ns.STARTER_WATCH_ANY or {}) do n = n + SwapField(entry, "spell") end
  for _, set in pairs(ns.GROUP_BUFFS or {}) do
    for _, entry in ipairs(set) do
      n = n + SwapField(entry, "spell") + SwapList(entry.also) + SwapList(entry.covers)
    end
  end
  for _, key in ipairs({ "CLASS_REZ", "CLASS_BATTLE_REZ", "CLASS_HEALS", "CLASS_TAUNTS",
    "CLASS_RESCUES", "CLASS_UTILITY" }) do
    for _, list in pairs(ns[key] or {}) do n = n + SwapList(list) end
  end
  n = n + SwapKeys(ns.SEED_DURATIONS)
  if ns.LINKED_AURAS then
    n = n + SwapKeys(ns.LINKED_AURAS)
    for _, list in pairs(ns.LINKED_AURAS) do n = n + SwapList(list) end
  end
  if ns.ForgetBuffList then ns.ForgetBuffList() end
  return n
end

-- Settings saved before this carry the English names (a starter watch, a
-- default heal on left click, the buffs switched on or off): the same swap,
-- once per profile. A spell the player typed in themselves is left alone
-- unless it is one of ours word for word.
local function Walk(t, seen, depth)
  if type(t) ~= "table" or seen[t] or depth > 8 then return 0 end
  seen[t] = true
  local n = 0
  if type(t.spell) == "string" then n = n + SwapField(t, "spell") end
  for key, value in pairs(t) do
    if key == "missingBuffs" and type(value) == "table" then
      n = n + SwapKeys(value)
    elseif type(value) == "table" then
      n = n + Walk(value, seen, depth + 1)
    end
  end
  return n
end

function ns.LocalizeSavedSpellNames()
  if IsEnglish() or not ns.db or ns.db.spellNamesLocalized == (GetLocale and GetLocale()) then return 0 end
  local n = Walk(ns.db, {}, 0)
  ns.db.spellNamesLocalized = GetLocale and GetLocale()
  if n > 0 then
    if ns.RebuildWatchIndex then ns.RebuildWatchIndex() end
    if ns.ForgetBuffList then ns.ForgetBuffList() end
  end
  return n
end

