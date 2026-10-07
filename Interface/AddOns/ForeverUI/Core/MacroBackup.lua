local _, ns = ...

-- A backup of the essentials, kept in macros.
--
-- The Forever beta client (since ~17 September 2026) writes every addon's
-- saved settings to disk and never reads them back: not after a restart,
-- not after a /reload once a file exists, not for a second addon, not for a
-- load-on-demand one (all tested in the client, docs/saving-bug.md). Macros
-- are kept by the game itself, outside that broken path, and they DO come
-- back after a full quit and relaunch. So ForeverUI writes the choices a
-- player would most miss into one or two character macros, and when a login
-- hands back nothing, reads them back before any module starts:
--
--   the setup answers   installed, loadout, scale, which modules run
--   the role grids      which are up, which role is active
--   every role's clicks key -> spell (as a spell ID when it has one) or action
--   where each grid is  its anchor point and offset
--   what you've moved   every frame dragged with /fui move (28 Sept 2026)
--
-- A macro holds 255 characters, so this is the essentials, not the whole
-- profile (~70 KB): up to five macros, the least important last, so what
-- doesn't fit is the other roles' clicks. The rest of the profile is the
-- player's own copy to keep (/fui backup, Core/Profiles.lua). Nothing here
-- asks anything of the player.

local backup = {}
ns.MacroBackup = backup

local PREFIX = "FUI Save "          -- "FUI Save 1", "FUI Save 2", ...
local MAX_MACROS = 5               -- Forever gives a character 30; positions need the room
local BODY_MAX = 255
local HEADER = "#ForeverUI backup %d/%d - keep\n"
local CHUNK = BODY_MAX - #HEADER - 4
local ICON = "INV_Misc_QuestionMark"
local WRITE_EVERY = 20              -- seconds between checks for changes

-- Fixed orders: the backup outlives the version that wrote it.
local MODULES = { "ActionBars", "Bags", "CastBar", "Chat", "Frames", "MicroBar",
  "Minimap", "Nameplates", "Quests", "UnitFrames", "XPBar",
  -- Added later: only ever append, so an older backup still reads right.
  "QuestForever", "Cooldowns", "Kicks", "Markers", "ForeverAuras", "Loot" }
local ROLE_OF = { h = "healer", t = "tank", d = "dps" }
local LETTER_OF = { healer = "h", tank = "t", dps = "d" }
local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
  "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_INDEX = {}
for i, p in ipairs(POINTS) do POINT_INDEX[p] = i end
local KIND_CODE = { menu = "m", target = "t", focus = "f", assist = "a" }
local KIND_OF = { m = "menu", t = "target", f = "focus", a = "assist" }
local POWER_TEXT_CODE = { current = "c", percent = "p", currentPercent = "b", currentMax = "m" }
local POWER_TEXT_OF = { c = "current", p = "percent", b = "currentPercent", m = "currentMax" }
local ANCHOR_CODE = { left = "l", center = "c", right = "r" }
local ANCHOR_OF = { l = "left", c = "center", r = "right" }
local MOD_ORDER = { { "alt-", "a" }, { "ctrl-", "c" }, { "shift-", "s" } }
local Movers   -- defined with the fields below

---------------------------------------------------------------------------
-- Text in and out
---------------------------------------------------------------------------

local function Esc(s)
  return (tostring(s):gsub("[%%;,=:!%^|'\n]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unesc(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function SpellInfo(x)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(x)
    if info then return info.name, info.spellID end
  end
  if GetSpellInfo then
    local name, _, _, _, _, _, id = GetSpellInfo(x)
    return name, id
  end
end

-- A spell by its ID when it has a clean one (short, and survives a locale),
-- otherwise by name. Ranked names ("Heal(Rank 2)") keep their exact text.
local function SpellToken(name)
  if type(name) ~= "string" or name == "" then return nil end
  if not name:find("(", 1, true) then
    local _, id = SpellInfo(name)
    if id and SpellInfo(id) == name then
      return tostring(id)
    end
  end
  return "'" .. Esc(name)
end

local function SpellFrom(token)
  if token:sub(1, 1) == "'" then
    return Unesc(token:sub(2))
  end
  local id = tonumber(token)
  return id and (SpellInfo(id)) or nil
end

-- "alt-ctrl-shift-wheelup" <-> "acswheelup". No binding suffix starts with
-- a, c or s, so the letters in front are always the modifiers.
local function KeyToken(key)
  local mods, rest = "", key
  for _, m in ipairs(MOD_ORDER) do
    local from, to = rest:find(m[1], 1, true)   -- plain: "-" is magic in a pattern
    if from then
      mods = mods .. m[2]
      rest = rest:sub(1, from - 1) .. rest:sub(to + 1)
    end
  end
  return mods .. rest
end

local function KeyFrom(token)
  local mods, rest = token:match("^([acs]*)(.+)$")
  if not rest then return nil end
  local key = ""
  for _, m in ipairs(MOD_ORDER) do
    if mods:find(m[2], 1, true) then key = key .. m[1] end
  end
  return key .. rest
end

local function BindingToken(b)
  if type(b) ~= "table" then return nil end
  local out
  if b.kind == "spell" then
    out = SpellToken(b.spell)
  elseif b.kind == "engage" then
    out = "e" .. (b.spell and ("." .. (SpellToken(b.spell) or "")) or "")
  elseif b.kind == "mark" then
    out = "r" .. tostring(tonumber(b.marker) or 8)   -- a raid mark on their target
  else
    out = KIND_CODE[b.kind]
  end
  if not out then return nil end
  if b.their then out = out .. "^" end
  if b.chosen then out = out .. "!" end
  return out
end

local function BindingFrom(token)
  local chosen = token:sub(-1) == "!"
  if chosen then token = token:sub(1, -2) end
  local their = token:sub(-1) == "^"
  if their then token = token:sub(1, -2) end
  local b
  if token:sub(1, 1) == "e" and (#token == 1 or token:sub(2, 2) == ".") then
    b = { kind = "engage" }
    if #token > 2 then b.spell = SpellFrom(token:sub(3)) end
  elseif token:match("^r%d$") then
    b = { kind = "mark", marker = tonumber(token:sub(2)) }
  elseif KIND_OF[token] then
    b = { kind = KIND_OF[token] }
  else
    local spell = SpellFrom(token)
    if not spell then return nil end
    b = { kind = "spell", spell = spell }
  end
  if their then b.their = true end
  if chosen then b.chosen = true end
  return b
end

---------------------------------------------------------------------------
-- Where the frames keep a role's values
---------------------------------------------------------------------------

-- The player's class token ("DRUID"). Not `UnitClass and UnitClass(...)`:
-- an `and` keeps only the first return, the localized name.
local function PlayerClass()
  if not UnitClass then return nil end
  local _, class = UnitClass("player")
  return class
end

-- The ACTIVE role's per-role settings live on the frames table itself; the
-- others are parked under modes[role] (Modules/Frames/Modes.lua). The clicks
-- are the exception: always modes[role].bindings.
local function ActiveRole(f)
  return f.mode or "healer"
end

-- `parkedFirst`: a grid that moves writes modes[role].position (and the live
-- copy only for the active one), so for positions the parked copy is the truth.
local function RoleValue(f, role, key, parkedFirst)
  local parked = f.modes and f.modes[role] and f.modes[role][key]
  if parkedFirst and parked ~= nil then return parked end
  if role == ActiveRole(f) and f[key] ~= nil then
    return f[key]
  end
  return parked
end

local function SetRoleValue(f, role, key, value)
  f.modes = f.modes or {}
  f.modes[role] = f.modes[role] or {}
  f.modes[role][key] = value
  if role == ActiveRole(f) then
    f[key] = type(value) == "table" and ns.CopyTable(value) or value
  end
end

---------------------------------------------------------------------------
-- Encode / decode
---------------------------------------------------------------------------

-- Where the player has dragged things with /fui move (ns.db.movers): only
-- the ones moved, one field each, "W<name>:<point>,<relative>,<x>,<y>".
-- Owner, 28 Sept 2026: a layout snapped back to the defaults on every
-- restart, because these were never kept.
function Movers(db, fields)
  local names = {}
  for name, pos in pairs(type(db.movers) == "table" and db.movers or {}) do
    if type(pos) == "table" and POINT_INDEX[pos[1]] and POINT_INDEX[pos[2]]
      and tonumber(pos[3]) and tonumber(pos[4]) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local pos = db.movers[name]
    fields[#fields + 1] = ("W%s:%d,%d,%d,%d"):format(Esc(name), POINT_INDEX[pos[1]], POINT_INDEX[pos[2]],
      math.floor(pos[3] + 0.5), math.floor(pos[4] + 0.5))
  end
end

-- ForeverAuras, one field each (owner, 28 Sept 2026: they'd be gone at
-- every restart otherwise):
--   "A<kind>:<spell>:<point>,<relative>,<x>,<y>:<size>:<flags>:<unit><when>:<class>"
-- kind c/b/d; flags are the switches that are on (m mine, s show missing,
-- n name, p proc glow, r ready glow, o ready sound, x every class).
local AURA_KIND = { cooldown = "c", buff = "b", debuff = "d" }
local AURA_KIND_OF = { c = "cooldown", b = "buff", d = "debuff" }
local AURA_FLAGS = { { "mine", "m", true }, { "showMissing", "s" }, { "showName", "n", true },
  { "glowProc", "p", true }, { "glowReady", "r" }, { "soundReady", "o" } }
local AURA_UNIT = { player = "p", target = "t", focus = "f" }
local AURA_UNIT_OF = { p = "player", t = "target", f = "focus" }
local AURA_WHEN = { always = "a", combat = "c", nocombat = "n" }
local AURA_WHEN_OF = { a = "always", c = "combat", n = "nocombat" }

local function Auras(db, fields)
  local settings = db.modules and db.modules.ForeverAuras
  for _, aura in ipairs(settings and settings.auras or {}) do
    if AURA_KIND[aura.kind] and aura.spell and tostring(aura.spell) ~= "" then
      local pos = type(aura.pos) == "table" and aura.pos or {}
      local flags = {}
      for _, f in ipairs(AURA_FLAGS) do
        local on = aura[f[1]]
        if on == nil then on = f[3] end
        if on then flags[#flags + 1] = f[2] end
      end
      if aura.classOnly == false then flags[#flags + 1] = "x" end
      fields[#fields + 1] = ("A%s:%s:%d,%d,%d,%d:%d:%s:%s%s:%s"):format(AURA_KIND[aura.kind], Esc(aura.spell),
        POINT_INDEX[pos[1]] or 5, POINT_INDEX[pos[2]] or 5, math.floor((tonumber(pos[3]) or 0) + 0.5),
        math.floor((tonumber(pos[4]) or 0) + 0.5), math.floor(tonumber(aura.size) or 40), table.concat(flags),
        AURA_UNIT[aura.unit or "player"] or "p", AURA_WHEN[aura.when or "always"] or "a", Esc(aura.class or ""))
    end
  end
end

-- The profile as a list of fields, most important first: if it all won't
-- fit, the tail is what gets left out.
function backup.Fields(db)
  db = db or ns.db
  local fields = { "V1" }
  if db.installed then fields[#fields + 1] = "I" end
  if db.saveNoticeSeen then fields[#fields + 1] = "N" end
  -- The last "What's new" seen, or it would open at every login.
  if db.whatsNewSeen then fields[#fields + 1] = "Y" .. Esc(db.whatsNewSeen) end
  if db.loadout then fields[#fields + 1] = "L" .. Esc(db.loadout) end
  if db.scale then fields[#fields + 1] = "S" .. math.floor(db.scale * 100 + 0.5) end
  -- The controller choice, when it isn't Auto.
  if db.controllerMode == "on" or db.controllerMode == "off" then
    fields[#fields + 1] = "J" .. (db.controllerMode == "on" and "o" or "f")
  end
  -- The chat's look (sprutorgel, 28 Sept 2026), only when it isn't the
  -- shipped one: "K<size>:<t|b>:<bg rrggbb>:<opacity>:<border rrggbb or ->".
  local chat = db.modules and db.modules.Chat
  if type(chat) == "table" then
    local function Hex(c)
      if type(c) ~= "table" then return nil end
      return ("%02x%02x%02x"):format(math.floor((c[1] or 0) * 255 + 0.5), math.floor((c[2] or 0) * 255 + 0.5),
        math.floor((c[3] or 0) * 255 + 0.5))
    end
    local size, top = tonumber(chat.fontSize) or 0, chat.editBoxPosition == "top"
    local bg, opacity = Hex(chat.bgColor), tonumber(chat.bgOpacity) or 92
    local border = chat.ownBorderColor and Hex(chat.borderColor) or "-"
    if size > 0 or top or (bg and bg ~= "08080d") or opacity ~= 92 or border ~= "-" then
      fields[#fields + 1] = ("K%d:%s:%s:%d:%s"):format(size, top and "t" or "b", bg or "08080d",
        math.floor(opacity + 0.5), border)
    end
  end
  -- Chat tabs fading out completely (29 Sept 2026), when on.
  if type(chat) == "table" and chat.fadeTabs then
    fields[#fields + 1] = "T1"
  end
  -- The micro bar fading until the mouse is over it (1 Oct 2026): "U<faded %>".
  local micro = db.modules and db.modules.MicroBar
  if type(micro) == "table" and micro.mouseover then
    fields[#fields + 1] = "U" .. math.floor(tonumber(micro.fadedAlpha) or 0)
  end
  -- Power text on the unit frames (sprutorgel, 1 Oct 2026), when on:
  -- "X<format><anchor><size>", e.g. "Xpc9" = percent, centred, 9 point.
  local uf = db.modules and db.modules.UnitFrames
  local powerCode = type(uf) == "table" and POWER_TEXT_CODE[uf.powerText]
  if powerCode then
    fields[#fields + 1] = "X" .. powerCode .. (ANCHOR_CODE[uf.powerTextAnchor] or "c")
      .. math.floor(tonumber(uf.powerTextSize) or 9)
  end
  -- Selling junk at vendors (2 Oct 2026), when on: "C1".
  local loot = db.modules and db.modules.Loot
  if type(loot) == "table" and loot.sellJunk then
    fields[#fields + 1] = "C1"
  end
  -- Action button icon zoom, when not the shipped 8%.
  local ab = db.modules and db.modules.ActionBars
  if type(ab) == "table" and tonumber(ab.iconZoom) and tonumber(ab.iconZoom) ~= 8 then
    fields[#fields + 1] = "Z" .. math.floor(tonumber(ab.iconZoom) + 0.5)
  end
  if db.roundCorners then
    fields[#fields + 1] = "R" .. math.floor(tonumber(db.cornerRadius) or 6)
      .. (db.roundButtons == false and "b" or "") .. (db.roundUnitFrames == false and "u" or "")
  end
  local bits = {}
  for i, name in ipairs(MODULES) do
    local m = db.modules and db.modules[name]
    bits[i] = (m and m.enabled == false) and "0" or "1"
  end
  fields[#fields + 1] = "E" .. table.concat(bits)

  local f = db.frames
  if type(f) ~= "table" then
    Movers(db, fields)
    Auras(db, fields)
    return fields
  end
  local active = ActiveRole(f)
  fields[#fields + 1] = "M" .. (LETTER_OF[active] or "h")
  local up = ""
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    if f.gridsUp and f.gridsUp[role] then up = up .. LETTER_OF[role] end
  end
  fields[#fields + 1] = "G" .. up
  -- When each grid shows (30 Sept 2026): "Q<always>/<in groups only>",
  -- only for roles someone has set.
  if type(f.gridSolo) == "table" then
    local always, group = "", ""
    for _, role in ipairs({ "healer", "tank", "dps" }) do
      if f.gridSolo[role] == true then always = always .. LETTER_OF[role]
      elseif f.gridSolo[role] == false then group = group .. LETTER_OF[role] end
    end
    if always ~= "" or group ~= "" then fields[#fields + 1] = "Q" .. always .. "/" .. group end
  end

  local class = PlayerClass()
  local order = { active }
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    if role ~= active then order[#order + 1] = role end
  end
  -- One role's clicks; a long list spans several fields.
  local function Clicks(role)
    local store = f.modes and f.modes[role] and f.modes[role].bindings
    if type(store) == "table" then
      local keys = {}
      for key in pairs(store) do keys[#keys + 1] = key end
      table.sort(keys)
      local entries, size = {}, 0
      local function flush()
        fields[#fields + 1] = "B" .. LETTER_OF[role] .. ":" .. table.concat(entries, ",")
        entries, size = {}, 0
      end
      flush() -- an empty field first: "this role's clicks start here"
      for _, key in ipairs(keys) do
        local token = BindingToken(store[key])
        if token then
          local entry = KeyToken(key) .. "=" .. token
          if size + #entry > CHUNK - 12 then flush() end
          entries[#entries + 1] = entry
          size = size + #entry + 1
        end
      end
      if #entries > 0 then flush() end
      local cd = RoleValue(f, role, "classDefaults")
      if class and type(cd) == "table" and cd[class] then
        fields[#fields + 1] = "D" .. LETTER_OF[role]
      end
    end
  end
  -- Most important first, as the macros only hold so much: the clicks you
  -- play with, then where everything sits, then the other roles' clicks.
  Clicks(active)
  -- Where each grid sits.
  for _, role in ipairs(order) do
    local pos = RoleValue(f, role, "position", true)
    if type(pos) == "table" and POINT_INDEX[pos[1]] and POINT_INDEX[pos[2]] and pos[3] and pos[4] then
      fields[#fields + 1] = ("P%s:%d,%d,%d,%d"):format(LETTER_OF[role], POINT_INDEX[pos[1]],
        POINT_INDEX[pos[2]], math.floor(pos[3] + 0.5), math.floor(pos[4] + 0.5))
    end
  end
  Movers(db, fields)
  Auras(db, fields)
  for i = 2, #order do Clicks(order[i]) end
  return fields
end

-- Fields packed into macro-sized chunks, in order, up to MAX_MACROS.
function backup.Chunks(fields)
  local chunks, current = {}, ""
  for _, field in ipairs(fields) do
    local piece = (current == "" and "" or ";") .. field
    if #current + #piece > CHUNK then
      if #chunks + 1 >= MAX_MACROS then
        break -- the rest doesn't fit; it was the least important
      end
      chunks[#chunks + 1] = current
      current = field
    else
      current = current .. piece
    end
  end
  if current ~= "" then chunks[#chunks + 1] = current end
  return chunks
end

-- A backup's text laid over a (fresh) profile. Returns true if it applied.
function backup.Apply(text, db)
  db = db or ns.db
  if type(text) ~= "string" or not text:find("^V1") then
    return false
  end
  local class = PlayerClass()
  db.modules = db.modules or {}
  db.frames = db.frames or {}
  local f = db.frames
  f.modes = f.modes or {}
  local started = {}
  for field in text:gmatch("[^;]+") do
    local c, v = field:sub(1, 1), field:sub(2)
    if c == "I" then
      db.installed = true
    elseif c == "N" then
      db.saveNoticeSeen = true
    elseif c == "Y" and v ~= "" then
      db.whatsNewSeen = Unesc(v)
    elseif c == "L" then
      db.loadout = Unesc(v)
    elseif c == "S" and tonumber(v) then
      db.scale = tonumber(v) / 100
    elseif c == "A" then
      local k, spell, a, b, x, y, size, flags, unit, when, auraClass =
        v:match("^(%a):([^:]*):(%d+),(%d+),(%-?%d+),(%-?%d+):(%d+):(%a*):(%a)(%a):(.*)$")
      if k and AURA_KIND_OF[k] and POINTS[tonumber(a)] and POINTS[tonumber(b)] then
        db.modules.ForeverAuras = db.modules.ForeverAuras or {}
        local fa = db.modules.ForeverAuras
        if not started.auras then
          -- The backup is the whole list: replace, don't add to it.
          fa.auras, fa.nextId, started.auras = {}, 1, true
        end
        local aura = { id = fa.nextId, kind = AURA_KIND_OF[k], spell = Unesc(spell), size = tonumber(size),
          pos = { POINTS[tonumber(a)], POINTS[tonumber(b)], tonumber(x), tonumber(y) },
          unit = AURA_UNIT_OF[unit] or "player", when = AURA_WHEN_OF[when] or "always",
          class = auraClass ~= "" and Unesc(auraClass) or nil, classOnly = not flags:find("x", 1, true) }
        for _, flag in ipairs(AURA_FLAGS) do aura[flag[1]] = flags:find(flag[2], 1, true) ~= nil end
        fa.nextId = fa.nextId + 1
        fa.auras[#fa.auras + 1] = aura
      end
    elseif c == "K" then
      local size, pos, bg, opacity, border = v:match("^(%d+):([tb]):(%x%x%x%x%x%x):(%d+):(.*)$")
      if size then
        local function Color(hex)
          return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
        end
        db.modules.Chat = db.modules.Chat or {}
        local chat = db.modules.Chat
        chat.fontSize, chat.editBoxPosition = tonumber(size), pos == "t" and "top" or "bottom"
        chat.bgColor, chat.bgOpacity = Color(bg), tonumber(opacity)
        chat.ownBorderColor = border:match("^%x%x%x%x%x%x$") ~= nil
        if chat.ownBorderColor then chat.borderColor = Color(border) end
      end
    elseif c == "U" and tonumber(v) then
      db.modules.MicroBar = db.modules.MicroBar or {}
      db.modules.MicroBar.mouseover = true
      db.modules.MicroBar.fadedAlpha = tonumber(v)
    elseif c == "X" and v:match("^%a%a%d+$") and POWER_TEXT_OF[v:sub(1, 1)] then
      db.modules.UnitFrames = db.modules.UnitFrames or {}
      local uf = db.modules.UnitFrames
      uf.powerText = POWER_TEXT_OF[v:sub(1, 1)]
      uf.powerTextAnchor = ANCHOR_OF[v:sub(2, 2)] or "center"
      uf.powerTextSize = tonumber(v:sub(3))
    elseif c == "C" and v == "1" then
      db.modules.Loot = db.modules.Loot or {}
      db.modules.Loot.sellJunk = true
    elseif c == "T" and v == "1" then
      db.modules.Chat = db.modules.Chat or {}
      db.modules.Chat.fadeTabs = true
    elseif c == "J" and (v == "o" or v == "f") then
      db.controllerMode = v == "o" and "on" or "off"
    elseif c == "Z" and tonumber(v) then
      db.modules.ActionBars = db.modules.ActionBars or {}
      db.modules.ActionBars.iconZoom = tonumber(v)
    elseif c == "W" then
      local name, a, b, x, y = v:match("^([^:]+):(%d+),(%d+),(%-?%d+),(%-?%d+)$")
      if name and POINTS[tonumber(a)] and POINTS[tonumber(b)] then
        db.movers = type(db.movers) == "table" and db.movers or {}
        db.movers[Unesc(name)] = { POINTS[tonumber(a)], POINTS[tonumber(b)], tonumber(x), tonumber(y) }
      end
    elseif c == "R" and v:match("^%d+%a*$") then
      local radius, off = v:match("^(%d+)(%a*)$")
      db.roundCorners = true
      db.cornerRadius = tonumber(radius)
      -- Letters name the parts left square: b = action buttons, u = unit frames.
      db.roundButtons = not off:find("b", 1, true)
      db.roundUnitFrames = not off:find("u", 1, true)
    elseif c == "E" then
      for i, name in ipairs(MODULES) do
        local bit = v:sub(i, i)
        if bit == "0" or bit == "1" then
          db.modules[name] = db.modules[name] or {}
          db.modules[name].enabled = bit == "1"
        end
      end
    elseif c == "M" and ROLE_OF[v] then
      f.mode = ROLE_OF[v]
    elseif c == "G" then
      f.gridsUp = {}
      for letter, role in pairs(ROLE_OF) do
        f.gridsUp[role] = v:find(letter, 1, true) ~= nil
      end
    elseif c == "Q" then
      local always, group = v:match("^(%a*)/(%a*)$")
      if always then
        f.gridSolo = {}
        for letter, role in pairs(ROLE_OF) do
          if always:find(letter, 1, true) then f.gridSolo[role] = true
          elseif group:find(letter, 1, true) then f.gridSolo[role] = false end
        end
      end
    elseif c == "B" then
      local letter, list = v:match("^(%a):(.*)$")
      local role = ROLE_OF[letter or ""]
      if role then
        f.modes[role] = f.modes[role] or {}
        if not started[role] then
          -- The backup is the whole set: replace, don't merge with defaults.
          f.modes[role].bindings = {}
          started[role] = true
        end
        local store = f.modes[role].bindings
        for entry in list:gmatch("[^,]+") do
          local k, t = entry:match("^([^=]+)=(.+)$")
          local key = k and KeyFrom(k)
          local b = t and BindingFrom(t)
          if key and b then store[key] = b end
        end
        if role == ActiveRole(f) then
          -- The live table IS the store (Frames/Profiles.lua), or the
          -- engine would fold a default copy back over it at boot.
          f.bindings = store
        end
      end
    elseif c == "D" and ROLE_OF[v] and class then
      SetRoleValue(f, ROLE_OF[v], "classDefaults", { [class] = true })
    elseif c == "P" then
      local letter, a, b, x, y = v:match("^(%a):(%d+),(%d+),(%-?%d+),(%-?%d+)$")
      local role = ROLE_OF[letter or ""]
      if role and POINTS[tonumber(a)] and POINTS[tonumber(b)] then
        SetRoleValue(f, role, "position", { POINTS[tonumber(a)], POINTS[tonumber(b)], tonumber(x), tonumber(y) })
      end
    end
  end
  return true
end

---------------------------------------------------------------------------
-- The macros
---------------------------------------------------------------------------

local function MacroIndex(i)
  local index = GetMacroIndexByName and GetMacroIndexByName(PREFIX .. i)
  return (index and index > 0) and index or nil
end

-- The backup's text, or nil if there isn't one.
function backup.Read()
  if not GetMacroBody then return nil end
  local parts = {}
  for i = 1, MAX_MACROS do
    local index = MacroIndex(i)
    if not index then break end
    local body = GetMacroBody(index) or ""
    parts[#parts + 1] = (body:gsub("^#[^\n]*\n", ""))
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ";")
end

local lastWritten
backup.full = false

-- How many macros this character may have. Forever keeps the number in
-- Constants.MacroConsts (30); the old global is gone there, and falling back
-- to Classic's 18 called a character with 18-29 macros "full" and refused
-- to write (goldfish117 on CurseForge, 28 Sept 2026: "failed to save using
-- the macros until I created them myself, even though I had open macro slots").
function backup.CharacterLimit()
  local consts = Constants and Constants.MacroConsts
  return (consts and tonumber(consts.MAX_CHARACTER_MACROS)) or tonumber(MAX_CHARACTER_MACROS) or 18
end

-- Write the backup if it changed. Never in combat (the game refuses macro
-- edits there) and never with the macro window open (it would fight it).
function backup.Write(force)
  if not (CreateMacro and EditMacro and GetMacroIndexByName) then return false end
  if not (ns.db and ns.db.installed) then return false end -- nothing chosen yet
  if InCombatLockdown and InCombatLockdown() then return false end
  if MacroFrame and MacroFrame.IsShown and MacroFrame:IsShown() then return false end
  local chunks = backup.Chunks(backup.Fields())
  local joined = table.concat(chunks, ";")
  if not force and joined == lastWritten then return false end
  for i = 1, MAX_MACROS do
    local name = PREFIX .. i
    local index = MacroIndex(i)
    if chunks[i] then
      local body = HEADER:format(i, #chunks) .. chunks[i]
      if index then
        EditMacro(index, name, ICON, body)
      else
        local _, numCharacter = GetNumMacros()
        local limit = backup.CharacterLimit()
        if numCharacter and numCharacter >= limit then
          if not backup.full then
            backup.full = true
            ns.Print(("couldn't keep a backup of your setup: this character's macro slots are full (%d of %d). "
              .. "Free one or two so ForeverUI can survive the beta's saving bug."):format(numCharacter, limit))
          end
          return false
        end
        local ok, err = pcall(CreateMacro, name, ICON, body, true)
        if not ok or not MacroIndex(i) then
          -- Say why once, with the counts, rather than retrying in silence.
          if not backup.full then
            backup.full = true
            ns.Print(("couldn't make the backup macro %s (character macros %s of %d): %s"):format(
              name, tostring(numCharacter), limit, tostring(ok and "the game didn't keep it" or err)))
          end
          return false
        end
      end
    elseif index then
      DeleteMacro(index)
    end
  end
  lastWritten = joined
  backup.full = false
  return true
end

-- At login, after the character's profile is picked and before any module
-- starts. Only when the game handed back nothing: a working save always wins.
function backup.RestoreIfNeeded()
  if ns.savedRestored ~= false or not ns.db then return false end
  local text = backup.Read()
  if not text then return false end
  local ok = pcall(backup.Apply, text)
  if ok then
    backup.restored = true
    lastWritten = text
  end
  return ok
end

-- A second after a change, not up to 20 later: a player who sets a click
-- and reloads straight away lost it (oxydie on CurseForge, 22 Sept 2026 --
-- "they reset every time I reload").
local pending = false
function backup.Soon()
  if pending or not (C_Timer and C_Timer.After) then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    pcall(backup.Write)
  end)
end

-- Everything that changes what the backup holds, hooked once at login.
function backup.HookChanges()
  if backup.hooked or not hooksecurefunc then return end
  backup.hooked = true
  local frames = ns.Frames
  for _, name in ipairs({ "SetBinding", "SetSetting", "SetGridShown", "SetMode" }) do
    if frames and type(frames[name]) == "function" then
      hooksecurefunc(frames, name, backup.Soon)
    end
  end
  for _, name in ipairs({ "SetModuleEnabled", "ApplyLoadout", "RefreshAllModules" }) do
    if type(ns[name]) == "function" then
      hooksecurefunc(ns, name, backup.Soon)
    end
  end
end

-- Check for changes now and then, and soon after anything big.
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(WRITE_EVERY, function() pcall(backup.Write) end)
end
