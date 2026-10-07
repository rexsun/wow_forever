local _, ns = ...

-- Tooltips on and off (owner, 23 Sept 2026: "can we create a way to turn
-- the tooltip on and off?" - the box that pops up bottom right when you point
-- at something).
--
-- Two settings: players and creatures, and everything else the game fills in
-- (spells, items, buffs). The first cut covered units only, and the owner
-- turned it off and still got a spell's tooltip over his bar: "off" means
-- off. Plain-text tooltips - ForeverUI's own button hints - are never
-- touched. The game still builds the tooltip; when it is one to suppress, it
-- is put away as it is filled in and again whenever it is shown.

local module = ns.RegisterModule({
  name = "Tooltips",
  title = "Tooltips",
})

_G.BINDING_NAME_FOREVERUI_TOGGLE_TOOLTIPS = "Tooltips on/off"

module.defaults = {
  units = "always",      -- players and creatures: always | combat (hidden in a fight) | never
  other = "always",      -- spells, items, buffs - anything else the game fills in
  lastOn = "always",     -- what /fui tooltips turns units back on to
  lastOther = "always",  -- ...and everything else
}

local function Settings()
  return ns.db.modules.Tooltips
end

local function Allowed(mode)
  mode = mode or "always"
  if mode == "never" then
    return false
  end
  if mode == "combat" and InCombatLockdown and InCombatLockdown() then
    return false
  end
  return true
end

-- Should a unit tooltip show right now? (kind "other": a spell's, an item's.)
function module.ShouldShow(kind)
  local s = Settings()
  return Allowed(kind == "other" and s.other or s.units)
end

-- What a tooltip is showing: "unit", "other" (a spell, an item, a buff -
-- anything the game filled in from its own data), or nil for plain text,
-- which is how ForeverUI's own buttons explain themselves and is never
-- touched: turning tooltips off must not make the settings window a guess.
local UNIT_TYPE = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
local function KindOf(tooltip, data)
  if type(data) ~= "table" and tooltip.GetPrimaryTooltipData then
    local ok, got = pcall(tooltip.GetPrimaryTooltipData, tooltip)
    if ok then data = got end
  end
  if type(data) ~= "table" and tooltip.GetTooltipData then
    local ok, got = pcall(tooltip.GetTooltipData, tooltip)
    if ok then data = got end
  end
  if type(data) == "table" and data.type ~= nil then
    local ok, isUnit = pcall(function() return UNIT_TYPE ~= nil and data.type == UNIT_TYPE end)
    return (ok and isUnit) and "unit" or "other"
  end
  if tooltip.GetUnit then
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if ok and unit then return "unit" end
  end
  return nil
end
module.KindOf = KindOf

local function Suppress(tooltip, data)
  if not module.enabledNow or tooltip ~= GameTooltip then
    return
  end
  local kind = KindOf(tooltip, data) or (data == nil and "unit") or nil
  if kind and not module.ShouldShow(kind) then
    tooltip:Hide()
  end
end
module.Suppress = Suppress

-- The game fills a tooltip, then may show it again on its next refresh or
-- when the mouse settles; the first fix only caught the fill, so a tooltip
-- turned off came straight back (owner, 23 Sept 2026: "tool tips still show
-- even when turned off even after reload"). Both are watched now: every fill
-- of any kind, and every time the box is shown.
local function Hook()
  if module.hooked then return end
  module.hooked = true
  local processor = TooltipDataProcessor
  if processor and processor.AddTooltipPostCall then
    local all = processor.AllTypes or "ALL"
    local ok = pcall(processor.AddTooltipPostCall, all, Suppress)
    if not ok and UNIT_TYPE then
      pcall(processor.AddTooltipPostCall, UNIT_TYPE, Suppress)
    end
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(t) Suppress(t) end)
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetSpell", function(t) Suppress(t, { type = "spell" }) end)
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(t) Suppress(t, { type = "item" }) end)
  end
  if GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function(t)
      if not module.enabledNow then return end
      local kind = KindOf(t)
      if kind and not module.ShouldShow(kind) then t:Hide() end
    end)
  end
  -- A fight starting with one open: put it away if that's the setting.
  local watcher = CreateFrame("Frame")
  pcall(watcher.RegisterEvent, watcher, "PLAYER_REGEN_DISABLED")
  watcher:SetScript("OnEvent", function()
    if module.enabledNow and GameTooltip and GameTooltip:IsShown() then
      local kind = KindOf(GameTooltip)
      if kind and not module.ShouldShow(kind) then GameTooltip:Hide() end
    end
  end)
end

-- On and off in one go: /fui tooltips, a key, the switch on its page.
-- Off is "never" for everything the game fills in - players, creatures,
-- spells, items; on puts each back to what it was (always, or hidden in
-- combat). `state` true/false sets it; nil flips it.
function module.Toggle(state)
  local s = Settings()
  local on = s.units ~= "never" or (s.other or "always") ~= "never"
  if state == nil then state = not on end
  if state then
    s.units = (s.lastOn and s.lastOn ~= "never") and s.lastOn or "always"
    s.other = (s.lastOther and s.lastOther ~= "never") and s.lastOther or "always"
  else
    if s.units ~= "never" then s.lastOn = s.units end
    if (s.other or "always") ~= "never" then s.lastOther = s.other or "always" end
    s.units = "never"
    s.other = "never"
    if GameTooltip and GameTooltip:IsShown() and KindOf(GameTooltip) then
      GameTooltip:Hide()
    end
  end
  ns.Print(("tooltips %s."):format(state and "on" or "off"))
  if ns.RefreshOptions then ns.RefreshOptions() end
  return state
end

function module:OnEnable()
  Hook()
  module.enabledNow = true
end

function module:OnDisable()
  module.enabledNow = false
end

function module:Refresh() end

local MODES = function()
  return {
    { label = "Always", value = "always" },
    { label = "Out of combat only", value = "combat" },
    { label = "Never", value = "never" },
  }
end

module.options = {
  { type = "heading", label = "Tooltips", subtitle = "The box that pops up when you point at something." },
  { type = "heading", label = "Tooltips", icon = "info" },
  { type = "checkbox", switch = true, key = "units", label = "Show tooltips",
    desc = "Off hides them all - players, creatures, spells, items. Also: /fui tooltips, or a key in Key Bindings.",
    get = function() local s = Settings(); return s.units ~= "never" or (s.other or "always") ~= "never" end,
    set = function(on) module.Toggle(on) end },
  { type = "cycler", key = "units", label = "Players and creatures", desc = "In the world and on frames.",
    choices = MODES },
  { type = "cycler", key = "other", label = "Spells, items and buffs", desc = "Your action bars, bags and auras.",
    choices = MODES },
  { type = "note", label = "ForeverUI's own button hints always show, so this window stays readable." },
  { type = "note", label = "Party & raid frames: where their tooltip shows and whether it lists what your clicks cast are set per role - Heal, Tank or DPS on the left, On the frames." },
}
