local _, ns = ...

-- ForeverAuras: your own cooldown and aura icons, WeakAuras-style, with no
-- WeakAuras (owner, 28 Sept 2026: "lets also create our own Weak Aura
-- without needing Weak Aura. Can we Call It ForeverAura's?").
--
-- Forever hides most numbers from addons in a fight (aura data, cooldown
-- times, other units' health and casts), so every aura here is built only
-- from what the game still hands over, or draws itself (forever-branch
-- docs, 28 Sept 2026 research):
--
--   Cooldown   a spell's icon. Ready or not, and on the global cooldown or
--              not, are never secret (C_Spell.GetSpellCooldown isActive /
--              isOnGCD); the sweep and its numbers are the game's own, from
--              a duration object (GetSpellCooldownDuration ->
--              SetCooldownFromDurationObject, as the action bars do).
--              Charges are a display string (GetSpellDisplayCount). Usable,
--              out of mana and out of range are plain. A proc lights it
--              (spell activation overlay). Optional sound when it comes
--              ready -- a plain yes/no, so it can be acted on.
--   Buff /     one of the game's own aura slots (CustomAuraContainerTemplate
--   Debuff     with includeSpellIDs, the HoT corners' way): the game draws
--              the icon, the time left and the stacks, in or out of combat,
--              solo or grouped. By spell it may watch buffs on you and your
--              group, and debuffs on an enemy (your DoTs on the target) --
--              not a named debuff on you. "Show when missing" puts a dimmed
--              icon underneath, which the game's own icon covers while the
--              buff is up: in a fight whether it's up can't be read, only
--              drawn.
--
-- Each aura is its own movable icon (Unlock to move), shows always, only in
-- combat or only out of it, and by default only on the class that made it
-- (profiles are shared between characters). Import / export as text, the
-- setup backup's format (read as data, never run).

local module = ns.RegisterModule({
  name = "ForeverAuras",
  title = "ForeverAuras",
})

module.defaults = {
  enabled = true,
  locked = true,
  auras = {},
  nextId = 1,
}

-- Restore Defaults puts the page's settings back; it never deletes auras.
module.keepOnRestore = { auras = true, nextId = true, selected = true }

local KINDS = { cooldown = "Cooldown", buff = "Buff", debuff = "Debuff on target" }
module.KINDS = KINDS
local ALERT_SOUND = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local RANGE_TICK = 0.2

local frames = {}              -- aura id -> display frame
module.frames = frames
local ticker

local function Settings()
  return ns.db.modules.ForeverAuras
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

local function PlayerClass()
  if not UnitClass then return nil end
  local _, class = UnitClass("player")
  return class
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

-- "Rejuvenation", "774" or "774, 1058, 1430": the name, icon and spell ID
-- to show, plus every ID it may match (typed ones, and every rank you know).
function module.ResolveSpell(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local ids, typed = {}, {}
  for n in text:gmatch("%d+") do
    local id = tonumber(n)
    if id then ids[id] = true; typed[#typed + 1] = id end
  end
  local lookup = typed[1] or text
  local name, icon, id
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, lookup)
    if ok and type(info) == "table" then
      name, icon, id = info.name, info.iconID or info.originalIconID, info.spellID
    end
  end
  if not name and GetSpellInfo then
    local ok, n, _, i, _, _, _, sid = pcall(GetSpellInfo, lookup)
    if ok and n then name, icon, id = n, i, sid end
  end
  if not name then
    if typed[1] then
      return { id = typed[1], name = "Spell " .. typed[1], icon = 134400, ids = ids }
    end
    return nil
  end
  id = id or typed[1]
  if id then ids[id] = true end
  -- Every rank you know: the game matches auras by exact spell ID.
  local engine = ns.Frames
  if engine and engine.ScanSpellbook then
    local ok, _, byName = pcall(engine.ScanSpellbook, true)
    local entry = ok and type(byName) == "table" and byName[name]
    if entry then
      if entry.spellID then ids[entry.spellID] = true end
      for _, rank in ipairs(entry.ranks or {}) do
        if rank.spellID then ids[rank.spellID] = true end
      end
    end
  end
  return { id = id, name = name, icon = icon or 134400, ids = ids }
end

-- Ready or cooling down, and whether that's only the global cooldown. Both
-- never secret on Forever; asked in a guard all the same.
function module.CooldownState(id)
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(info) == "table" then
      local okA, active = pcall(function() return info.isActive and true or false end)
      local okG, gcd = pcall(function() return info.isOnGCD and true or false end)
      if okA then return active, okG and gcd or false end
    end
  end
  if GetSpellCooldown then
    local ok, start, duration = pcall(GetSpellCooldown, id)
    if ok then
      local okA, active = pcall(function() return (start or 0) > 0 and (duration or 0) > 0 end)
      local okG, gcd = pcall(function() return (duration or 0) <= 1.5 end)
      if okA then return active, active and okG and gcd or false end
    end
  end
  return false, false
end

local function Usable(id)
  local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
  if not fn then return true, false end
  local ok, usable, noMana = pcall(fn, id)
  if not ok then return true, false end
  local okU, u = pcall(function() return usable and true or false end)
  local okM, m = pcall(function() return noMana and true or false end)
  return (not okU) or u, okM and m or false
end

-- true in range, false out, nil when it doesn't apply (no target, no range).
local function InRange(id)
  if not (UnitExists and UnitExists("target")) then return nil end
  local fn = C_Spell and C_Spell.IsSpellInRange
  local ok, r = false, nil
  if fn then
    ok, r = pcall(fn, id, "target")
  elseif IsSpellInRange and GetSpellInfo then
    local name = GetSpellInfo(id)
    if name then ok, r = pcall(IsSpellInRange, name, "target") end
  end
  if not ok then return nil end
  local okR, v = pcall(function()
    if r == nil then return nil end
    return r == true or r == 1
  end)
  if not okR then return nil end
  return v
end

local function Overlayed(id)
  local fn = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed
  if not fn then return false end
  local ok, on = pcall(fn, id)
  local okB, b = pcall(function() return ok and on and true or false end)
  return okB and b or false
end

---------------------------------------------------------------------------
-- The icons
---------------------------------------------------------------------------

local function Glow(f)
  if f.glow then return f.glow end
  local glow = CreateFrame("Frame", nil, f)
  glow:SetPoint("TOPLEFT", -3, 3)
  glow:SetPoint("BOTTOMRIGHT", 3, -3)
  glow:SetFrameLevel(f:GetFrameLevel() + 5)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.82, 0.2, 1)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(2)
    else
      t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(2)
    end
  end
  local pulse = glow.CreateAnimationGroup and glow:CreateAnimationGroup()
  local fade = pulse and pulse.CreateAnimation and pulse:CreateAnimation("Alpha")
  if fade then
    pulse:SetLooping("BOUNCE")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.5)
    glow.pulse = pulse
  end
  glow:Hide()
  f.glow = glow
  return glow
end

local function SetGlow(f, on)
  local glow = Glow(f)
  if on then
    glow:Show()
    if glow.pulse and not glow.pulse:IsPlaying() then glow.pulse:Play() end
  else
    if glow.pulse then glow.pulse:Stop() end
    glow:Hide()
  end
end

local function SavePosition(f)
  local aura = f.aura
  local point, _, relativePoint, x, y = f:GetPoint()
  aura.pos = { point or "CENTER", relativePoint or "CENTER", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
end

local function Build(aura)
  local f = CreateFrame("Frame", "ForeverAura" .. aura.id, UIParent)
  f.aura = aura
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
  end)
  ns.Skin.Panel(f, { color = { 0, 0, 0, 0.6 }, group = "roundButtons" })

  -- What shows under the game's own icon (a buff's "missing" look), or the
  -- icon itself (a cooldown).
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", 1, -1)
  f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cooldown:SetAllPoints(f.icon)
  if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(false) end

  local over = CreateFrame("Frame", nil, f)
  over:SetAllPoints()
  over:SetFrameLevel(f:GetFrameLevel() + 4)
  f.count = over:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(f.count, "aura")
  f.count:SetPoint("BOTTOMRIGHT", -2, 2)
  f.label = over:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(f.label, "general")
  f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)

  -- Unlocked: a tint and the name, so it's clear what to drag.
  f.handle = over:CreateTexture(nil, "OVERLAY")
  f.handle:SetAllPoints()
  local r, g, b = unpack(ns.Colors.ui.accent)
  f.handle:SetColorTexture(r, g, b, 0.3)
  f.handle:Hide()
  return f
end

-- A buff or debuff: one of the game's own aura slots, drawn over our icon.
-- Made out of combat only (the game locks its aura icons away from addons
-- in a fight), then left to the game.
local function StyleSlot(button, f)
  pcall(function()
    local size = f.fuiSize or 36
    button:SetSize(size - 2, size - 2)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    button:SetDurationCooldown(cooldown)
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(cooldown:GetFrameLevel() + 2)
    local count = over:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(count, "aura")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(count)
  end)
end

local function Slot(f, aura, spell)
  if InCombat() or not _G.CustomAuraContainerGroupDefaultOptions then return f.slot end
  -- Not while the controller's navigation is live (Core/Controller.lua).
  if ns.AuraContainersAllowed and not ns.AuraContainersAllowed() then return f.slot end
  local mine = aura.mine ~= false
  local filter = (aura.kind == "debuff" and "HARMFUL" or "HELPFUL") .. (mine and "|PLAYER" or "")
  local unit = aura.kind == "debuff" and "target" or (aura.unit or "player")
  local key = table.concat({ filter, unit, aura.size or 36, (function()
    local list = {}
    for id in pairs(spell.ids) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ",")
  end)() }, "|")
  if f.slot and f.slotKey == key then return f.slot end
  local ok, err = pcall(function()
    local c = f.slot
    if not c then
      c = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
      c:SetAllPoints(f)
      f.slot = c
      c:AddAuraSlot("a", filter, {
        initializeFrame = function(b) StyleSlot(b, f) end,
        candidateFilters = { includeSpellIDs = spell.ids },
      })
      c:SetEnabled(true)
    else
      c:SetAuraSlotFilterString("a", filter)
      c:SetAuraSlotCandidateFilters("a", { includeSpellIDs = spell.ids })
    end
    c:SetUnit(unit)
    local button = c:GetAuraSlotFrame("a")
    if button then
      button:ClearAllPoints()
      button:SetPoint("CENTER", f, "CENTER", 0, 0)
      button:SetSize((aura.size or 36) - 2, (aura.size or 36) - 2)
    end
    f.slotKey = key
  end)
  if not ok then
    f.slotError = tostring(err)
  end
  return f.slot
end

---------------------------------------------------------------------------
-- Keeping them current
---------------------------------------------------------------------------

local function Loaded(aura)
  if aura.disabled then return false end
  if aura.classOnly ~= false and aura.class and aura.class ~= PlayerClass() then return false end
  return true
end

-- Show always / in combat / out of combat, and never while nothing's set.
-- Faded rather than hidden: nothing here is protected, but the game's aura
-- slot inside keeps its place untouched.
local function Visible(aura)
  local when = aura.when or "always"
  if when == "combat" and not InCombat() then return false end
  if when == "nocombat" and InCombat() then return false end
  return true
end

local function UpdateCooldown(f, aura, spell)
  local active, gcd = module.CooldownState(spell.id)
  local cooling = active and not gcd
  if f.cooldown.SetCooldownFromDurationObject and C_Spell and C_Spell.GetSpellCooldownDuration then
    local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spell.id, true)
    if ok and duration then pcall(f.cooldown.SetCooldownFromDurationObject, f.cooldown, duration) end
  elseif GetSpellCooldown and not InCombat() then
    local ok, start, dur = pcall(GetSpellCooldown, spell.id)
    if ok then pcall(f.cooldown.SetCooldown, f.cooldown, start, dur) end
  end
  if not cooling and f.cooldown.Clear then pcall(f.cooldown.Clear, f.cooldown) end
  f.icon:SetDesaturated(cooling and true or false)
  -- Charges, as the game writes them ("2"); nothing for a one-charge spell.
  local text = ""
  if C_Spell and C_Spell.GetSpellDisplayCount then
    local ok, v = pcall(C_Spell.GetSpellDisplayCount, spell.id)
    if ok and v ~= nil then text = v end
  end
  f.count:SetText(text)
  -- Can't cast: grey-blue for no mana, red for out of range.
  local usable, noMana = Usable(spell.id)
  local range = InRange(spell.id)
  if noMana then
    f.icon:SetVertexColor(0.45, 0.55, 1)
  elseif range == false then
    f.icon:SetVertexColor(1, 0.3, 0.3)
  elseif not usable then
    f.icon:SetVertexColor(0.55, 0.55, 0.55)
  else
    f.icon:SetVertexColor(1, 1, 1)
  end
  local ready = not cooling
  SetGlow(f, (aura.glowReady and ready and usable) or (aura.glowProc ~= false and Overlayed(spell.id)))
  -- Came ready: the sound, once per ready.
  if f.wasCooling and ready and aura.soundReady and PlaySound then
    pcall(PlaySound, ALERT_SOUND, "Master")
  end
  f.wasCooling = cooling
end

local function Apply(aura)
  local f = frames[aura.id]
  if not Loaded(aura) or not ns.IsModuleEnabled("ForeverAuras") then
    if f then f:SetAlpha(0); f:EnableMouse(false) end
    return f
  end
  f = f or Build(aura)
  frames[aura.id] = f
  f.aura = aura
  local size = math.max(16, math.min(96, tonumber(aura.size) or 36))
  f.fuiSize = size
  if not InCombat() then
    f:SetSize(size, size)
    local p = aura.pos or { "CENTER", "CENTER", 0, -160 }
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  end
  local spell = module.ResolveSpell(aura.spell)
  f.spell = spell
  f.icon:SetTexture(spell and spell.icon or 134400)
  f.label:SetText(aura.showName ~= false and (spell and spell.name or "?") or "")
  -- The tile and border: a cooldown always has one; a buff only while its
  -- "missing" icon is on (otherwise the game's icon is all there is).
  local framed = aura.kind == "cooldown" or aura.showMissing
  for side, edge in pairs(f.borderEdges or {}) do
    if type(side) == "string" then edge:SetShown(framed and true or false) end
  end
  ns.Skin.ShapePanel(f)
  if aura.kind == "cooldown" then
    f.icon:SetAlpha(1)
    f.bg:SetAlpha(1)
    f.cooldown:Show()
    if spell then UpdateCooldown(f, aura, spell) end
  else
    -- Missing: the dimmed icon under the game's. Otherwise nothing of ours.
    f.icon:SetDesaturated(true)
    f.icon:SetVertexColor(1, 1, 1)
    f.icon:SetAlpha(aura.showMissing and 0.45 or 0)
    f.count:SetText("")
    f.cooldown:Hide()
    f.bg:SetAlpha(aura.showMissing and 1 or 0)
    if spell then Slot(f, aura, spell) end
  end
  local unlocked = not Settings().locked
  f.handle:SetShown(unlocked)
  f:EnableMouse(unlocked)
  if unlocked then
    f:SetAlpha(1)
  else
    f:SetAlpha(Visible(aura) and 1 or 0)
  end
  return f
end
module.Apply = Apply

local function ForEachLive(fn)
  for _, aura in ipairs(Settings().auras or {}) do
    local f = frames[aura.id]
    if f and f.spell and Loaded(aura) then fn(f, aura) end
  end
end

function module.UpdateCooldowns()
  ForEachLive(function(f, aura)
    if aura.kind == "cooldown" then UpdateCooldown(f, aura, f.spell) end
  end)
end

function module.UpdateVisibility()
  local unlocked = not Settings().locked
  for _, aura in ipairs(Settings().auras or {}) do
    local f = frames[aura.id]
    if f and Loaded(aura) then f:SetAlpha((unlocked or Visible(aura)) and 1 or 0) end
  end
end

-- Target or focus changed: the game's slots re-read their unit.
local function RefreshSlots()
  ForEachLive(function(f)
    if f.slot and f.slot.UpdateAllAuras then pcall(f.slot.UpdateAllAuras, f.slot) end
  end)
end

function module:Refresh()
  local seen = {}
  for _, aura in ipairs(Settings().auras or {}) do
    seen[aura.id] = true
    Apply(aura)
  end
  for id, f in pairs(frames) do
    if not seen[id] then f:SetAlpha(0); f:EnableMouse(false) end
  end
end

local events = CreateFrame("Frame")
local EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN",
  "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
  "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "SPELLS_CHANGED" }
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
    RefreshSlots()
    module.UpdateCooldowns()
  elseif event == "PLAYER_REGEN_ENABLED" then
    module:Refresh()          -- anything waiting on the fight to end
  elseif event == "PLAYER_REGEN_DISABLED" then
    module.UpdateVisibility()
  elseif event == "SPELLS_CHANGED" then
    if not InCombat() then module:Refresh() end
  else
    module.UpdateCooldowns()
  end
end)

function module:OnEnable()
  for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
  -- Range changes with no event on this client: a light poll.
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(RANGE_TICK, function() module.UpdateCooldowns() end)
  end
  module:Refresh()
end

function module:OnDisable()
  events:UnregisterAllEvents()
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker = nil
  for _, f in pairs(frames) do f:SetAlpha(0); f:EnableMouse(false) end
end

---------------------------------------------------------------------------
-- Adding, removing, sharing
---------------------------------------------------------------------------

function module.Selected()
  local s = Settings()
  for _, aura in ipairs(s.auras) do
    if aura.id == s.selected then return aura end
  end
  return nil
end

function module.Add(kind, spell)
  local s = Settings()
  local id = s.nextId or 1
  s.nextId = id + 1
  local count = #s.auras
  local aura = {
    id = id, kind = KINDS[kind] and kind or "cooldown", spell = spell or "",
    size = 40, mine = true, showName = true, when = "always", class = PlayerClass(),
    glowProc = true, glowReady = false, soundReady = false, showMissing = kind == "buff",
    pos = { "CENTER", "CENTER", -120 + (count % 6) * 48, -160 - math.floor(count / 6) * 60 },
  }
  s.auras[#s.auras + 1] = aura
  s.selected = id
  if not InCombat() then Apply(aura) end
  return aura
end

function module.Remove(id)
  local s = Settings()
  for i, aura in ipairs(s.auras) do
    if aura.id == id then
      table.remove(s.auras, i)
      break
    end
  end
  local f = frames[id]
  if f then f:SetAlpha(0); f:EnableMouse(false) end
  if s.selected == id then s.selected = s.auras[1] and s.auras[1].id or nil end
end

function module.SetLocked(locked)
  Settings().locked = locked and true or false
  module:Refresh()
end

local EXPORT_KEYS = { "kind", "spell", "size", "mine", "showName", "when", "classOnly", "class",
  "glowProc", "glowReady", "soundReady", "showMissing", "pos" }

-- Every aura (or just one) as a line of text to share.
function module.Export(only)
  local list = {}
  for _, aura in ipairs(Settings().auras) do
    if not only or aura.id == only then
      local copy = {}
      for _, key in ipairs(EXPORT_KEYS) do copy[key] = aura[key] end
      list[#list + 1] = copy
    end
  end
  return "ForeverAuras:1:" .. ns.CompactSerialize(list)
end

-- Adds what's in the text; returns how many, or nil and why.
function module.Import(text)
  local body = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", ""):match("^ForeverAuras:%d+:(.+)$")
  if not body then return nil, "that isn't ForeverAuras text" end
  local list, err = ns.Deserialize(body)
  if type(list) ~= "table" then return nil, "the text is damaged" .. (err and (": " .. err) or "") end
  local added = 0
  for _, item in ipairs(list) do
    if type(item) == "table" and KINDS[item.kind] and item.spell ~= nil then
      local aura = module.Add(item.kind, tostring(item.spell))
      for _, key in ipairs(EXPORT_KEYS) do
        if item[key] ~= nil and key ~= "class" then aura[key] = item[key] end
      end
      -- Shared auras load for the class they were made on.
      aura.class = type(item.class) == "string" and item.class or aura.class
      added = added + 1
    end
  end
  if not InCombat() then module:Refresh() end
  return added
end

---------------------------------------------------------------------------
-- Options (the page edits whichever aura is selected in its list)
---------------------------------------------------------------------------

-- With nothing selected the rows edit a scratch aura, so every control
-- still has a value to show.
local EMPTY = { spell = "", kind = "cooldown", unit = "player", when = "always", size = 40 }
local function Store()
  return module.Selected() or EMPTY
end

local function Choices(list)
  return function()
    local out = {}
    for _, pair in ipairs(list) do out[#out + 1] = { value = pair[1], label = pair[2] } end
    return out
  end
end

local LIST_ROW = 26

local function BuildList(parent, x, y, width)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("TOPLEFT", x, y)
  holder:SetSize(width, LIST_ROW)
  holder.rows = {}
  local function Paint()
    local auras = Settings().auras
    local selected = Settings().selected
    for i = 1, math.max(#auras, #holder.rows) do
      local row = holder.rows[i]
      local aura = auras[i]
      if aura and not row then
        row = CreateFrame("Button", nil, holder)
        row:SetSize(width, LIST_ROW - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW)
        ns.Skin.Panel(row, { color = { 0, 0, 0, 0.25 } })
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(LIST_ROW - 6, LIST_ROW - 6)
        row.icon:SetPoint("LEFT", 3, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY")
        ns.Media.SetFont(row.text, "general")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", -70, 0)
        row.text:SetJustifyH("LEFT")
        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(60, LIST_ROW - 8)
        row.remove:SetPoint("RIGHT", -4, 0)
        ns.Skin.Button(row.remove)
        row.remove:SetText("Delete")
        row:SetScript("OnClick", function(self)
          Settings().selected = self.auraId
          if ns.RefreshOptions then ns.RefreshOptions() end
        end)
        row.remove:SetScript("OnClick", function(self)
          module.Remove(self:GetParent().auraId)
          if ns.RefreshOptions then ns.RefreshOptions() end
        end)
        holder.rows[i] = row
      end
      if row then
        row:SetShown(aura ~= nil)
        if aura then
          local spell = module.ResolveSpell(aura.spell)
          row.auraId = aura.id
          row.icon:SetTexture(spell and spell.icon or 134400)
          local loaded = Loaded(aura) and "" or "  |cff888888(another class)|r"
          row.text:SetText(("%s  |cff9a9aa6%s|r%s"):format(spell and spell.name or ("\"" .. tostring(aura.spell) .. "\"?"),
            KINDS[aura.kind] or aura.kind, loaded))
          ns.Skin.SetPanelColor(row, aura.id == selected and { 0.30, 0.76, 1, 0.25 } or { 0, 0, 0, 0.25 })
        end
      end
    end
    local n = math.max(1, #auras)
    holder:SetHeight(n * LIST_ROW)
    holder.empty = holder.empty or holder:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(holder.empty, "general")
    holder.empty:SetPoint("TOPLEFT", 4, -4)
    holder.empty:SetText("No auras yet: add one above.")
    holder.empty:SetShown(#auras == 0)
  end
  holder.Paint = Paint
  module.listHolder = holder
  Paint()
  return math.max(1, #Settings().auras) * LIST_ROW + 4
end

local function Popup(title, text, onAccept)
  if ns.ShowTextPopup then ns.ShowTextPopup(title, text, onAccept) end
end

module.options = {
  { type = "heading", label = "ForeverAuras", subtitle = "Your own cooldown and aura icons - no WeakAuras needed." },
  { type = "note", label = "Add an aura, type the spell, and drag it where you want it (Unlock to move). Cooldowns: "
    .. "greyed while cooling down, the game's own countdown, red out of range, a glow on a proc. Buffs and your "
    .. "debuffs on the target: drawn by the game itself, so they keep working in combat and in groups." },
  { type = "heading", label = "Add", columns = 3, icon = "general" },
  { type = "action", label = "New cooldown", width = 180, onClick = function()
      module.Add("cooldown", ""); ns.RefreshOptions() end },
  { type = "action", label = "New buff", width = 180, onClick = function()
      module.Add("buff", ""); ns.RefreshOptions() end },
  { type = "action", label = "New debuff on target", width = 180, onClick = function()
      module.Add("debuff", ""); ns.RefreshOptions() end },

  { type = "heading", label = "Your auras", icon = "general" },
  { type = "custom", build = BuildList, refresh = function()
      if module.listHolder then module.listHolder.Paint() end
    end },
  { type = "action", label = "Unlock to move", width = 200, labelFor = function()
      return Settings().locked and "Unlock to move" or "Lock them in place"
    end, onClick = function() module.SetLocked(not Settings().locked); ns.RefreshOptions() end },

  { type = "heading", label = "Selected aura", icon = "general" },
  { type = "input", key = "spell", label = "Spell", hint = "name or ID, e.g. Rejuvenation or 774",
    desc = "For a buff or debuff with ranks, every rank you know is matched. Several IDs: 774, 1058.",
    store = Store, apply = function() module:Refresh() end },
  { type = "cycler", key = "kind", label = "What it tracks", store = Store,
    choices = Choices({ { "cooldown", "Cooldown" }, { "buff", "Buff" }, { "debuff", "Debuff on target" } }),
    apply = function() module:Refresh() end },
  { type = "cycler", key = "unit", label = "Buff on", store = Store,
    desc = "Buffs only. Debuffs are always your target's.",
    choices = Choices({ { "player", "You" }, { "target", "Your target" }, { "focus", "Your focus" } }),
    apply = function() module:Refresh() end },
  { type = "cycler", key = "when", label = "Show", store = Store,
    choices = Choices({ { "always", "Always" }, { "combat", "Only in combat" }, { "nocombat", "Only out of combat" } }),
    apply = function() module:Refresh() end },
  { type = "stepper", key = "size", label = "Size", min = 16, max = 96, step = 2, store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "mine", label = "Only mine (buffs and debuffs)", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "showMissing", label = "Show a dimmed icon while the buff is missing", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "showName", label = "Spell name under the icon", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "glowProc", label = "Glow on a proc (cooldowns)", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "glowReady", label = "Glow while ready (cooldowns)", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "soundReady", label = "Sound when it comes ready (cooldowns)", store = Store,
    apply = function() module:Refresh() end },
  { type = "checkbox", key = "classOnly", label = "Only on this class", store = function()
      local aura = module.Selected()
      if not aura then return { classOnly = true } end
      -- nil means on (the default); the checkbox reads true/false.
      return setmetatable({}, {
        __index = function() return aura.classOnly ~= false end,
        __newindex = function(_, _, v) aura.classOnly = v and true or false end,
      })
    end, apply = function() module:Refresh() end },

  { type = "heading", label = "Share", columns = 2, icon = "copy" },
  { type = "action", label = "Export all", width = 200, onClick = function()
      Popup("Your ForeverAuras -- copy this text to share or keep", module.Export())
    end },
  { type = "action", label = "Import", width = 200, onClick = function()
      Popup("Paste ForeverAuras text, then Import", "", function(text)
        local n, err = module.Import(text)
        ns.Print(n and ("added %d aura%s."):format(n, n == 1 and "" or "s") or ("couldn't import: " .. tostring(err)))
        ns.RefreshOptions()
      end)
    end },
}
