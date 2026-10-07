local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Healer tools: the VuhDo features that change what a click DOES (owner,
-- 23 Sept 2026: "can we put all of the features that they have into this
-- app?" - docs/vuhdo-parity.md, phase 1).
--
--   Smart cast       a heal click on a dead player resurrects them instead;
--                    in a fight it battle-rezzes, if you have one.
--   Auto-fire        a trinket, or an instant like Nature's Swiftness, fired
--                    in the same click, just before the heal.
--   Your own macro   any click or key can run a macro of yours on the player
--                    under the mouse.
--   Rez announce     "Resurrecting Solindius" to your group as the cast goes.
--
-- All of it is plain macro text on the secure button: [@mouseover] is the
-- frame you clicked (a frame with a unit is what the game calls mouseover),
-- and macro conditions like [dead] and [combat] are evaluated by the game at
-- the click, securely, so nothing here needs a secure snippet - which Forever
-- can't run. With every option off a click stays a plain spell, exactly as
-- before.

for key, value in pairs({
  smartRez = false,        -- a heal click on a dead player resurrects them
  smartRezCombat = true,   -- ...and in combat, battle-rezzes (if you have one)
  autoTrinket = "off",     -- off | 13 | 14 | both: use the trinket(s) before a heal
  autoFireSpell = "",      -- an instant cast just before the heal ("Nature's Swiftness")
  rezAnnounce = "off",     -- off | group: say who you are resurrecting
}) do
  if ns.DEFAULTS[key] == nil then ns.DEFAULTS[key] = value end
end

-- Out-of-combat resurrection and battle resurrection, by class. The first one
-- your spellbook has is used, so a Forever rework that renames or adds one
-- only needs a line here.
ns.CLASS_REZ = {
  PRIEST = { "Resurrection" },
  PALADIN = { "Redemption" },
  SHAMAN = { "Ancestral Spirit" },
  DRUID = { "Revive", "Rebirth" },
  MONK = { "Resuscitate" },
  EVOKER = { "Return" },
}
ns.CLASS_BATTLE_REZ = {
  DRUID = { "Rebirth" },
  DEATHKNIGHT = { "Raise Ally" },
  WARLOCK = { "Soulstone" },
  PALADIN = { "Intercession" },
}

local function PlayerClass()
  if UnitClass then
    local _, class = UnitClass("player")
    return class
  end
end

local function FirstKnown(list)
  if not list or not ns.ScanSpellbook then
    return nil
  end
  local ok, _, byName = pcall(ns.ScanSpellbook, true)
  if not ok or type(byName) ~= "table" then
    return nil
  end
  for _, name in ipairs(list) do
    if byName[name] then
      return name
    end
  end
  return nil
end

function ns.RezSpell()
  return FirstKnown(ns.CLASS_REZ[PlayerClass() or ""])
end

function ns.BattleRezSpell()
  return FirstKnown(ns.CLASS_BATTLE_REZ[PlayerClass() or ""])
end

local function Trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The macro a heal click becomes, or nil when it should stay a plain spell.
function ns.SpellMacro(binding)
  local spell = ns.CastName(binding)
  if not spell then
    return nil
  end
  local db = ns.db
  local trinket = db.autoTrinket or "off"
  local fire = Trim(db.autoFireSpell)
  local rez = db.smartRez and ns.RezSpell() or nil
  local brez = db.smartRez and db.smartRezCombat ~= false and ns.BattleRezSpell() or nil
  if trinket == "off" and fire == "" and not rez and not brez then
    return nil
  end
  local lines = {}
  -- Only on a living friend: a trinket or an instant must not be spent on
  -- someone the heal can't land on.
  local living = "[@mouseover,help,nodead]"
  if trinket == "13" or trinket == "both" then lines[#lines + 1] = "/use " .. living .. " 13" end
  if trinket == "14" or trinket == "both" then lines[#lines + 1] = "/use " .. living .. " 14" end
  if fire ~= "" then lines[#lines + 1] = "/cast " .. living .. " " .. fire end
  local clauses = {}
  if rez then clauses[#clauses + 1] = "[@mouseover,dead,nocombat] " .. rez end
  if brez then clauses[#clauses + 1] = "[@mouseover,dead,combat] " .. brez end
  clauses[#clauses + 1] = "[@mouseover] " .. spell
  lines[#lines + 1] = "/cast " .. table.concat(clauses, "; ")
  return table.concat(lines, "\n")
end

-- Your own macro. "@unit" in it means the player under the mouse; a macro
-- with no target of its own gets [@mouseover] put on its /cast lines.
local MACRO_LIMIT = 1023

function ns.BindingMacroText(binding)
  local text = binding and binding.macro
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("\r", ""):gsub("@unit", "@mouseover")
  text = Trim(text)
  if text == "" then
    return nil
  end
  return text:sub(1, MACRO_LIMIT)
end

-- Bind a macro to a key ("shift-2", "wheelup").
function ns.SetMacroBinding(key, text)
  text = Trim(text)
  if text == "" then
    ns.SetBinding(key, nil, "healer tools")
    return nil
  end
  local binding = { kind = "macro", macro = text:sub(1, MACRO_LIMIT) }
  ns.SetBinding(key, binding, "healer tools")
  return binding
end

---------------------------------------------------------------------------
-- Rez announce
---------------------------------------------------------------------------

local REZ_NAMES = {}
local function IsRezSpell(name)
  if not name then return false end
  if not next(REZ_NAMES) then
    for _, list in pairs(ns.CLASS_REZ) do for _, n in ipairs(list) do REZ_NAMES[n] = true end end
    for _, list in pairs(ns.CLASS_BATTLE_REZ) do for _, n in ipairs(list) do REZ_NAMES[n] = true end end
  end
  return REZ_NAMES[name] == true
end
ns.IsRezSpell = IsRezSpell

local function GroupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

-- The text, or nil when there's nothing to say or no one to say it to.
function ns.RezAnnouncement(spell, target)
  if (ns.db.rezAnnounce or "off") == "off" or not IsRezSpell(spell) then
    return nil
  end
  -- Secret first: even comparing a secret string with "" throws.
  if issecretvalue and issecretvalue(target) then
    return nil
  end
  if type(target) ~= "string" or target == "" then
    return nil
  end
  local channel = GroupChannel()
  if not channel then
    return nil
  end
  return ("Resurrecting %s (%s)"):format(target, spell), channel
end

local function SpellNameOf(spellID)
  if not spellID or (issecretvalue and issecretvalue(spellID)) then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok then return name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, spellID)
    if ok then return name end
  end
  return nil
end

local announcer = CreateFrame("Frame")
ns.RegisterEvent(announcer, "UNIT_SPELLCAST_SENT")
announcer:SetScript("OnEvent", function(_, _, unit, target, _, spellID)
  if unit ~= "player" or not ns.booted then return end
  local ok, text, channel = pcall(ns.RezAnnouncement, SpellNameOf(spellID), target)
  if ok and text and SendChatMessage then
    pcall(SendChatMessage, text, channel)
  end
end)
ns.rezAnnouncer = announcer

---------------------------------------------------------------------------
-- Settings that rewrite the clicks
---------------------------------------------------------------------------

local function Rebind()
  if ns.ApplyBindings then ns.WhenOutOfCombat(ns.ApplyBindings) end
end
for _, key in ipairs({ "smartRez", "smartRezCombat", "autoTrinket", "autoFireSpell" }) do
  ns.SETTING_APPLY[key] = Rebind
end
