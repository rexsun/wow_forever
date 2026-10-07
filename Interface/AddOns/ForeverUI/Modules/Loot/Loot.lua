local _, ns = ...

-- Loot advice (owner, 29 Sept 2026: "When I get loot in my bags that are not
-- beneficial from a drop can you tell me or when I get an upgrade in my bags
-- and I should equip can you tell the player?").
--
-- Each new item that lands in your bags gets one line:
--
--   Junk          grey quality: sell it (and for how much)
--   Not for you   gear the game marks in red for you -- wrong armour or
--                 weapon type, wrong class. The game's own tooltip decides,
--                 so Forever's class changes are respected, not guessed at.
--   Later         the only red line is its level: usable at level N (and
--                 whether it would be an upgrade then)
--   Upgrade       gear you can wear whose stats beat what you have on in
--                 that slot, weighed for your class and role
--   Not an upgrade
--
-- As a toast that fades (movable with /fui move), a line on the item's own
-- tooltip, and a green "+" on upgrades in ForeverUI's bag window. It never
-- equips anything itself -- equipping from addon code is exactly what the
-- game blocks -- it says "right-click to equip".
--
-- The weighing is deliberately simple: a handful of stat weights per role
-- (healer, tank, and three kinds of damage), read from the game's own item
-- stats (C_Item.GetItemStats). Good enough to say "that's better", and it
-- says so plainly rather than pretending to be a theorycrafter.

local module = ns.RegisterModule({
  name = "Loot",
  title = "Loot advice",
})

module.defaults = {
  enabled = true,
  toasts = true,
  chat = false,
  tooltip = true,
  bagMarks = true,
  sayJunk = true,
  sayCantUse = true,
  sayUpgrade = true,
  sayNotUpgrade = true,
  sayLater = true,
  weights = "auto",      -- auto | healer | tank | strength | agility | caster
  sellJunk = false,      -- sell grey items by themselves when a vendor opens
  toastSeconds = 7,
}

local function Settings()
  return ns.db.modules.Loot
end

---------------------------------------------------------------------------
-- Weighing gear
---------------------------------------------------------------------------

-- The game's names for item stats (C_Item.GetItemStats keys).
local S = {
  str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
  int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", armor = "RESISTANCE0_NAME",
  dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
  rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", sp = "ITEM_MOD_SPELL_POWER_SHORT",
  heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
  hit = "ITEM_MOD_HIT_RATING_SHORT", crit = "ITEM_MOD_CRIT_RATING_SHORT",
  shit = "ITEM_MOD_HIT_SPELL_RATING_SHORT", scrit = "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
  def = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", dodge = "ITEM_MOD_DODGE_RATING_SHORT",
  parry = "ITEM_MOD_PARRY_RATING_SHORT", block = "ITEM_MOD_BLOCK_RATING_SHORT",
  blockValue = "ITEM_MOD_BLOCK_VALUE_SHORT",
}

local WEIGHTS = {
  healer   = { int = 1, spi = 0.6, sta = 0.3, heal = 1.2, sp = 0.9, mp5 = 2, scrit = 10, armor = 0.01 },
  tank     = { sta = 1, agi = 0.6, str = 0.5, armor = 0.05, def = 1.2, dodge = 10, parry = 10, block = 5,
               blockValue = 0.3, hit = 5 },
  strength = { str = 1, agi = 0.7, sta = 0.25, ap = 0.5, crit = 10, hit = 10, dps = 3, armor = 0.01 },
  agility  = { agi = 1, str = 0.4, sta = 0.25, ap = 0.5, rap = 0.5, crit = 10, hit = 10, dps = 3, armor = 0.01 },
  caster   = { int = 0.6, spi = 0.2, sta = 0.3, sp = 1, scrit = 10, shit = 10, mp5 = 1 },
}
module.WEIGHTS = WEIGHTS

-- What a class's damage leans on, while levelling.
local DAMAGE_KIND = {
  WARRIOR = "strength", PALADIN = "strength", SHAMAN = "strength",
  ROGUE = "agility", HUNTER = "agility", DRUID = "agility",
  MAGE = "caster", WARLOCK = "caster", PRIEST = "caster",
}

function module.Profile()
  local choice = Settings().weights or "auto"
  if WEIGHTS[choice] then return choice end
  local role = ns.Frames and ns.Frames.PlayingRole and ns.Frames.PlayingRole() or "dps"
  if role == "healer" or role == "tank" then return role end
  local class
  if UnitClass then
    local _, token = UnitClass("player")
    class = token
  end
  return DAMAGE_KIND[class or ""] or "strength"
end

local function Stats(link)
  local get = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not (get and link) then return {} end
  local ok, stats = pcall(get, link)
  return ok and type(stats) == "table" and stats or {}
end

function module.Score(link, profile)
  if not link then return 0 end
  local w = WEIGHTS[profile or module.Profile()] or WEIGHTS.strength
  local stats, total = Stats(link), 0
  for key, weight in pairs(w) do
    local value = tonumber(stats[S[key]])
    if value then total = total + value * weight end
  end
  return total
end

-- Where a kind of gear goes: the slot numbers it could replace.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}
module.SLOTS = SLOTS

local function Equipped(slot)
  if not GetInventoryItemLink then return nil end
  local ok, link = pcall(GetInventoryItemLink, "player", slot)
  return ok and link or nil
end

-- The score of what's worn where this would go: for rings, trinkets and
-- one-handers the weaker of the two; a two-hander against both hands.
local function WornScore(equipLoc, profile)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  if equipLoc == "INVTYPE_2HWEAPON" then
    return module.Score(Equipped(16), profile) + module.Score(Equipped(17), profile), not Equipped(16)
  end
  local worst, empty
  for _, slot in ipairs(slots) do
    local link = Equipped(slot)
    if not link then empty = true end
    local score = link and module.Score(link, profile) or 0
    if not worst or score < worst then worst = score end
  end
  return worst or 0, empty
end

-- The game's own verdict on whether this is for you: a red line on its
-- tooltip. Returns "ok", "level" (only the level stands in the way), or
-- "no" (armour or weapon type, class...).
local LEVEL_PATTERN = (ITEM_MIN_LEVEL or "Requires Level %d"):gsub("%%d", "(%%d+)")
function module.Usable(link)
  local tip = C_TooltipInfo and C_TooltipInfo.GetHyperlink
  if not tip then return "ok" end
  local ok, data = pcall(tip, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return "ok" end
  local red, levelOnly, level = false, true, nil
  for _, line in ipairs(data.lines) do
    for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
      local text, color = side[1], side[2]
      if type(text) == "string" and type(color) == "table" then
        local r, g, b = tonumber(color.r), tonumber(color.g), tonumber(color.b)
        if r and g and b and r > 0.9 and g < 0.3 and b < 0.3 then
          red = true
          local n = text:match(LEVEL_PATTERN)
          if n then level = tonumber(n) else levelOnly = false end
        end
      end
    end
  end
  if not red then return "ok" end
  if levelOnly and level then return "level", level end
  return "no"
end

local function Money(copper)
  copper = tonumber(copper) or 0
  if copper <= 0 then return nil end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 and g == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end
module.Money = Money

local PROFILE_WORDS = { healer = "healing", tank = "tanking", strength = "strength damage",
  agility = "agility damage", caster = "spell damage" }

-- Verdicts are kept until what you wear, your level or the weighing changes
-- (the bag window asks for every slot on every refresh).
local verdicts = {}
function module.ClearVerdicts()
  verdicts = {}
end

-- { kind, text, delta } for an item, or nil when there's nothing to say
-- (a potion, a quest item, cloth for tailoring).
local Judge
function module.Judge(link)
  if type(link) ~= "string" then return nil end
  local hit = verdicts[link]
  if hit ~= nil then return hit or nil end
  local verdict = Judge(link)
  verdicts[link] = verdict or false
  return verdict
end

function Judge(link)
  if type(link) ~= "string" or not GetItemInfo then return nil end
  local ok, name, _, quality, _, reqLevel, _, _, _, equipLoc, _, sellPrice = pcall(GetItemInfo, link)
  if not ok or not name then return nil end
  if quality == 0 then
    local price = Money(sellPrice)
    return { kind = "junk", text = price and ("Junk: sell it (" .. price .. ")") or "Junk: sell it" }
  end
  if not equipLoc or equipLoc == "" or not SLOTS[equipLoc] or equipLoc == "INVTYPE_BODY" then
    return nil
  end
  -- A fishing pole is a tool, not a weapon to weigh (weapon class 2,
  -- subclass 20).
  if GetItemInfoInstant then
    local okI, _, _, _, _, _, classID, subClassID = pcall(GetItemInfoInstant, link)
    if okI and classID == 2 and subClassID == 20 then return nil end
  end
  local profile = module.Profile()
  local usable, level = module.Usable(link)
  if usable == "no" then
    local price = Money(sellPrice)
    return { kind = "cantuse", text = "Not for you" .. (price and (": sell it (" .. price .. ")") or "") }
  end
  local mine = module.Score(link, profile)
  local worn, empty = WornScore(equipLoc, profile)
  local delta = mine - (worn or 0)
  local better = (empty and mine > 0) or (delta > 0.5 and delta > (worn or 0) * 0.03)
  local percent = (worn and worn > 0) and math.floor(delta / worn * 100 + 0.5) or nil
  local why = PROFILE_WORDS[profile] or profile
  if usable == "level" then
    return { kind = "later", delta = delta,
      text = ("Usable at level %d%s"):format(level or reqLevel or 0, better and " - an upgrade then" or "") }
  end
  if better then
    local by = (empty and "you have nothing there") or (percent and ("+" .. percent .. "%")) or "better"
    return { kind = "upgrade", delta = delta,
      text = ("Upgrade for %s (%s): right-click to equip"):format(why, by) }
  end
  return { kind = "notupgrade", delta = delta, text = ("Not an upgrade for %s"):format(why) }
end

---------------------------------------------------------------------------
-- Saying so
---------------------------------------------------------------------------

local COLORS = {
  junk = { 0.62, 0.62, 0.62 }, cantuse = { 1, 0.45, 0.35 }, later = { 1, 0.82, 0.3 },
  upgrade = { 0.35, 1, 0.45 }, notupgrade = { 0.75, 0.75, 0.8 },
}
module.COLORS = COLORS
local SAY = { junk = "sayJunk", cantuse = "sayCantUse", later = "sayLater", upgrade = "sayUpgrade",
  notupgrade = "sayNotUpgrade" }

local anchor
local toasts = {}
local MAX_TOASTS = 3

local function Anchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", "ForeverUILootToasts", UIParent)
  anchor:SetSize(320, 40)
  anchor:SetFrameStrata("HIGH")
  if ns.RegisterMover then
    ns.RegisterMover("loot", "Loot advice", anchor, { "BOTTOM", "BOTTOM", 0, 320 })
  else
    anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 320)
  end
  return anchor
end

local function Toast(i)
  local t = toasts[i]
  if t then return t end
  t = CreateFrame("Frame", nil, Anchor())
  t:SetSize(320, 40)
  ns.Skin.Panel(t, { color = { 0.04, 0.04, 0.06, 0.92 } })
  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(30, 30)
  t.icon:SetPoint("LEFT", 5, 0)
  t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  t.name = t:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(t.name, "general")
  t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 8, -1)
  t.name:SetPoint("RIGHT", -6, 0)
  t.name:SetJustifyH("LEFT")
  t.line = t:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(t.line, "general")
  t.line:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 8, 1)
  t.line:SetPoint("RIGHT", -6, 0)
  t.line:SetJustifyH("LEFT")
  t:Hide()
  toasts[i] = t
  return t
end

local queue = {}
local function Layout()
  for i = 1, MAX_TOASTS do
    local t = toasts[i]
    local entry = queue[i]
    if entry then
      t = Toast(i)
      t:ClearAllPoints()
      t:SetPoint("BOTTOM", Anchor(), "BOTTOM", 0, (i - 1) * 44)
      t.icon:SetTexture(entry.icon or 134400)
      t.name:SetText(entry.link or entry.name or "")
      t.line:SetText(entry.text)
      local c = COLORS[entry.kind] or COLORS.notupgrade
      t.line:SetTextColor(c[1], c[2], c[3])
      t:SetAlpha(1)
      t:Show()
    elseif t then
      t:Hide()
    end
  end
end

function module.Announce(link, verdict)
  local s = Settings()
  if not verdict or not s[SAY[verdict.kind] or ""] then return false end
  if s.chat then
    ns.Print(("%s: %s"):format(link, verdict.text))
  end
  if s.toasts then
    local icon = GetItemIcon and select(2, pcall(GetItemIcon, link)) or nil
    table.insert(queue, 1, { link = link, icon = icon, text = verdict.text, kind = verdict.kind,
      born = GetTime and GetTime() or 0 })
    while #queue > MAX_TOASTS do table.remove(queue) end
    Layout()
  end
  return true
end

-- Toasts fade out on their own.
local fader = CreateFrame("Frame")
fader:SetScript("OnUpdate", function(_, elapsed)
  if #queue == 0 then return end
  fader.t = (fader.t or 0) + elapsed
  if fader.t < 0.1 then return end
  fader.t = 0
  local now, life = GetTime and GetTime() or 0, tonumber(Settings().toastSeconds) or 7
  local changed = false
  for i = #queue, 1, -1 do
    local age = now - (queue[i].born or now)
    if age > life then
      table.remove(queue, i)
      changed = true
    elseif age > life - 1 and toasts[i] then
      toasts[i]:SetAlpha(math.max(0, life - age))
    end
  end
  if changed then Layout() end
end)

---------------------------------------------------------------------------
-- Noticing what's new
---------------------------------------------------------------------------

-- How many of each item are in the bags. Something is new when there are
-- more of it than before -- not when it merely moved slot.
local function Count()
  local counts, links = {}, {}
  local c = C_Container
  if not (c and c.GetContainerNumSlots and c.GetContainerItemInfo) then return counts, links end
  for bag = 0, 4 do
    local okN, n = pcall(c.GetContainerNumSlots, bag)
    n = okN and ns.Secrets.Number(n) or 0
    for slot = 1, n do
      local ok, info = pcall(c.GetContainerItemInfo, bag, slot)
      if ok and type(info) == "table" and info.itemID and type(info.hyperlink) == "string" then
        local id = ns.Secrets.Number(info.itemID)
        if id then
          counts[id] = (counts[id] or 0) + (ns.Secrets.Number(info.stackCount) or 1)
          links[id] = links[id] or info.hyperlink
        end
      end
    end
  end
  -- What you wear counts too: taking something off puts it in your bags, and
  -- that is not new loot (goldfish117 on CurseForge, 30 Sept 2026: "Fishing
  -- Pole" came up as an upgrade the moment it went back in the bag).
  if GetInventoryItemID then
    for slot = 1, 19 do
      local ok, id = pcall(GetInventoryItemID, "player", slot)
      id = ok and ns.Secrets.Number(id) or nil
      if id then counts[id] = (counts[id] or 0) + 1 end
    end
  end
  return counts, links
end
module.Count = Count

local known
-- After a loading screen the bags fill in over a moment, and everything
-- already carried looked new (the same report: it popped up "after the zone
-- change on a boat"). For a few seconds each look only learns.
local LEARN_SECONDS = 4
local learnUntil = 0
function module.LearnFor(seconds)
  learnUntil = (GetTime and GetTime() or 0) + (seconds or LEARN_SECONDS)
end
function module.Scan()
  local counts, links = Count()
  local now = GetTime and GetTime() or 0
  if not known or now < learnUntil then
    known = counts          -- the first look only learns what you carry
    return {}
  end
  local fresh = {}
  for id, n in pairs(counts) do
    if n > (known[id] or 0) then fresh[#fresh + 1] = links[id] end
  end
  known = counts
  for _, link in ipairs(fresh) do
    module.Announce(link, module.Judge(link))
  end
  return fresh
end

function module.Forget()
  known = nil
end

-- Selling junk at a vendor (Altiokis on CurseForge, 2 Oct 2026: "Is there an
-- automatic sell junk option?"). Through the game's own sell-all-junk
-- (C_MerchantFrame.SellAllJunkItems, what Blizzard's own button calls): grey
-- items only, decided by the game, so nothing else can ever be sold.
function module.SellJunk()
  if not Settings().sellJunk then return 0 end
  local merchant = C_MerchantFrame
  if not (merchant and merchant.SellAllJunkItems and merchant.GetNumJunkItems) then return 0 end
  if merchant.IsSellAllJunkEnabled then
    local okOn, on = pcall(merchant.IsSellAllJunkEnabled)
    if okOn and on == false then return 0 end
  end
  local okN, n = pcall(merchant.GetNumJunkItems)
  n = okN and tonumber(n) or 0
  if n <= 0 then return 0 end
  local before = GetMoney and GetMoney() or nil
  if not pcall(merchant.SellAllJunkItems) then return 0 end
  local function Report()
    local gained = before and GetMoney and (GetMoney() - before) or 0
    local worth = gained > 0 and Money(gained) or nil
    ns.Print(("sold %d junk item%s%s."):format(n, n == 1 and "" or "s", worth and (" for " .. worth) or ""))
  end
  if C_Timer and C_Timer.After then C_Timer.After(1.5, Report) else Report() end
  return n
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    module.SellJunk()
  elseif event == "PLAYER_ENTERING_WORLD" then
    module.Forget()
    module.LearnFor(LEARN_SECONDS)
    module.Scan()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
    -- What you wear (or your level) changed what counts as an upgrade.
    module.ClearVerdicts()
    if ns.GetModule("Bags") and ns.GetModule("Bags").UpdateBagWindow then pcall(ns.GetModule("Bags").UpdateBagWindow) end
  else
    module.Scan()
  end
end)

---------------------------------------------------------------------------
-- The tooltip line and the bag marks
---------------------------------------------------------------------------

function module.TooltipLine(tooltip, link)
  local s = Settings()
  if not (s.tooltip and ns.IsModuleEnabled("Loot") and tooltip and link) then return false end
  local verdict = module.Judge(link)
  if not verdict or verdict.kind == "junk" then return false end
  local c = COLORS[verdict.kind] or COLORS.notupgrade
  tooltip:AddLine("ForeverUI: " .. verdict.text, c[1], c[2], c[3], true)
  return true
end

local tooltipHooked = false
local function HookTooltip()
  if tooltipHooked then return end
  tooltipHooked = true
  local processor = TooltipDataProcessor
  local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
  if processor and processor.AddTooltipPostCall and itemType then
    pcall(processor.AddTooltipPostCall, itemType, function(tooltip)
      if tooltip ~= GameTooltip or not tooltip.GetItem then return end
      local ok, _, link = pcall(tooltip.GetItem, tooltip)
      if ok and link then pcall(module.TooltipLine, tooltip, link) end
    end)
  end
end

-- A green "+" on an upgrade in ForeverUI's bag window (Bags calls this).
function module.MarkSlot(button, link)
  if not button then return end
  local mark = button.fuiUpgrade
  local show = false
  if link and Settings().bagMarks and ns.IsModuleEnabled("Loot") then
    local verdict = module.Judge(link)
    show = verdict ~= nil and verdict.kind == "upgrade"
  end
  if show and not mark then
    mark = button:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(mark, "header")
    mark:SetPoint("TOPLEFT", 2, -1)
    mark:SetText("+")
    mark:SetTextColor(0.35, 1, 0.45)
    button.fuiUpgrade = mark
  end
  if mark then mark:SetShown(show) end
end

function module:OnEnable()
  for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_LEVEL_UP", "MERCHANT_SHOW" }) do
    pcall(events.RegisterEvent, events, event)
  end
  HookTooltip()
  Anchor()
  module.Scan()
end

-- A setting changed (the weighing, what to say): judge afresh.
function module:Refresh()
  module.ClearVerdicts()
end

function module:OnDisable()
  events:UnregisterAllEvents()
  queue = {}
  Layout()
end

module.options = {
  { type = "heading", label = "Loot advice", subtitle = "What each new item in your bags is good for." },
  { type = "note", label = "When loot lands in your bags: junk to sell, gear that isn't for you, gear you "
    .. "can wear later, and upgrades worth putting on - weighed for your class and role. It never equips "
    .. "anything itself: right-click the item in your bags. Drag the messages with /fui move." },
  { type = "heading", label = "Tell me about", columns = 2, icon = "bags" },
  { type = "checkbox", key = "sayUpgrade", label = "Upgrades to put on" },
  { type = "checkbox", key = "sayJunk", label = "Junk (grey) to sell" },
  { type = "checkbox", key = "sayCantUse", label = "Gear that isn't for you" },
  { type = "checkbox", key = "sayLater", label = "Gear for a higher level" },
  { type = "checkbox", key = "sayNotUpgrade", label = "Gear that's no better than yours" },
  { type = "heading", label = "How", columns = 2, icon = "general" },
  { type = "checkbox", key = "toasts", label = "A message on screen" },
  { type = "checkbox", key = "chat", label = "A line in chat" },
  { type = "checkbox", key = "tooltip", label = "A line on the item's tooltip" },
  { type = "checkbox", key = "bagMarks", label = "A green + on upgrades in the bags" },
  { type = "heading", label = "At a vendor", icon = "bags" },
  { type = "checkbox", key = "sellJunk", label = "Sell junk (grey items) by itself at vendors",
    desc = "Uses the game's own sell-all-junk, so only grey items are ever sold. It says what it sold in chat." },
  { type = "heading", label = "Weighing", icon = "general" },
  { type = "cycler", key = "weights", label = "What counts as better",
    desc = "Automatic follows your role (healer, tank, damage) and class.",
    choices = function()
      return { { value = "auto", label = "Automatic" }, { value = "healer", label = "Healing" },
        { value = "tank", label = "Tanking" }, { value = "strength", label = "Strength damage" },
        { value = "agility", label = "Agility damage" }, { value = "caster", label = "Spell damage" } }
    end },
}
