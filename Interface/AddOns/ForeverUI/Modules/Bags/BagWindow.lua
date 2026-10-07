local _, ns = ...

-- The bag window ForeverUI draws itself, to the owner's mock-up: a title
-- with the bag icon and a flat X; a search line with "19 / 64"; a sidebar
-- of categories -- All, Equipment, Consumables, Materials, Quest Items,
-- Miscellaneous -- each with its count; the slots in a grid, ringed in the
-- item's quality colour; and a footer with the money, a cog and Clean Up.
--
-- The slots are Blizzard's own secure item buttons (the container-item
-- template), so picking up, using, splitting and selling are the game's
-- own -- untouched. Only the frame around them is ours. Blizzard's combined
-- bag keeps opening and closing exactly as before (the B key, the bag bar,
-- a merchant, the bank); it is simply made invisible while ours mirrors it.

local module = ns.GetModule("Bags")
if not module then
  return
end

local window
local holders = {}       -- bagID -> holder frame (SetID = bag) owning that bag's buttons
local buttons = {}       -- flat list, in bag/slot order
module.slotButtons = buttons
local categories = {}
local state = { category = "all", filter = "" }
module.windowState = state

local SLOT, GAP, SIDEBAR, HEAD, FOOT, SEARCH = 36, 4, 150, 34, 36, 30
local ApplyLook   -- defined with the look, below; Build calls it
local COLS = 8

local function Settings()
  return ns.db.modules.Bags
end

local BAGS = { 0, 1, 2, 3, 4 }
if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
  BAGS[#BAGS + 1] = Enum.BagIndex.ReagentBag
end

---------------------------------------------------------------------------
-- What is in the bags
---------------------------------------------------------------------------

-- Item class -> our category. The numbers are Enum.ItemClass; the names
-- are what the sidebar says.
local CLASS_TO_CATEGORY = {
  [2] = "equipment", [4] = "equipment",                 -- weapon, armor
  [0] = "consumables",                                  -- consumable
  [7] = "materials", [5] = "materials", [6] = "materials", [16] = "materials", -- trade goods, reagent, projectile, glyph
  [12] = "quest",                                       -- quest
}
local CATEGORIES = {
  { key = "all", label = "All" },
  { key = "equipment", label = "Equipment" },
  { key = "consumables", label = "Consumables" },
  { key = "materials", label = "Materials" },
  { key = "quest", label = "Quest Items" },
  { key = "misc", label = "Miscellaneous" },
}
module.CATEGORIES = CATEGORIES

local function CategoryOf(info)
  if not info then
    return nil
  end
  local itemID = ns.Secrets.Number(info.itemID)
  local classID
  if itemID and C_Item and C_Item.GetItemInfoInstant then
    local ok, _, _, _, _, _, cid = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then classID = ns.Secrets.Number(cid) end
  end
  if ns.Secrets.Bool(info.questID or info.isQuestItem, false) then
    return "quest"
  end
  return (classID and CLASS_TO_CATEGORY[classID]) or "misc"
end
module.CategoryOf = CategoryOf

local function SlotInfo(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if ok and type(info) == "table" then
    return info
  end
  return nil
end

local function NumSlots(bag)
  if not (C_Container and C_Container.GetContainerNumSlots) then
    return 0
  end
  local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
  return ok and ns.Secrets.Number(n) or 0
end

---------------------------------------------------------------------------
-- The slots
---------------------------------------------------------------------------

local function Holder(bag)
  local holder = holders[bag]
  if holder then return holder end
  holder = CreateFrame("Frame", "ForeverUIBag" .. bag, window.grid)
  holder:SetID(bag)
  holder:SetAllPoints(window.grid)
  -- What Blizzard's item button asks of its parent.
  holder.IsCombinedBagContainer = function() return false end
  holder.GetBagID = function() return bag end
  holder.MatchesBagID = function(_, id) return id == bag end
  holder.IsBackpack = function() return bag == 0 end
  holders[bag] = holder
  return holder
end

local function Ring(button)
  if button.fuiRing then return end
  local ui = ns.Colors.ui
  local fill = button:CreateTexture(nil, "BACKGROUND", nil, -5)
  fill:SetPoint("TOPLEFT", -1, 1)
  fill:SetPoint("BOTTOMRIGHT", 1, -1)
  fill:SetColorTexture(0.05, 0.05, 0.07, 1)
  local edges = {}
  local px = ns.Media.Pixel()
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = button:CreateTexture(nil, "BORDER")
    t:SetColorTexture(ui.border[1], ui.border[2], ui.border[3], 1)
    if side == "TOP" then t:SetPoint("TOPLEFT", fill); t:SetPoint("TOPRIGHT", fill); t:SetHeight(px)
    elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetHeight(px)
    elseif side == "LEFT" then t:SetPoint("TOPLEFT", fill); t:SetPoint("BOTTOMLEFT", fill); t:SetWidth(px)
    else t:SetPoint("TOPRIGHT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetWidth(px) end
    edges[#edges + 1] = t
  end
  button.fuiRing = edges
  -- Blizzard's own ring, bevel and empty-slot wing, off.
  local normal = button.GetNormalTexture and button:GetNormalTexture()
  if normal and normal.SetAlpha then normal:SetAlpha(0) end
  local pushed = rawget(button, "PushedTexture")
  if pushed and pushed.SetAlpha then pushed:SetAlpha(0) end
  if rawget(button, "emptyBackgroundAtlas") ~= nil then button.emptyBackgroundAtlas = nil end
  local border = rawget(button, "IconBorder")
  if border and border.SetAlpha then border:SetAlpha(0) end -- ours colours the ring instead
end

local function RingColor(button, quality)
  local ui = ns.Colors.ui
  local r, g, b = ui.border[1], ui.border[2], ui.border[3]
  local q = ns.Secrets.Number(quality)
  if q and q >= 2 and C_Item and C_Item.GetItemQualityColor then
    local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, q)
    if ok and qr then r, g, b = qr, qg, qb end
  elseif q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]
    r, g, b = c.r, c.g, c.b
  end
  for _, edge in ipairs(button.fuiRing or {}) do
    edge:SetColorTexture(r, g, b, 1)
  end
end

local function Button(bag, slot, index)
  local button = buttons[index]
  if button then
    if button.fuiBag ~= bag or button:GetID() ~= slot then
      button:SetParent(Holder(bag))
      button:SetID(slot)
      button.fuiBag = bag
    end
    return button
  end
  -- Which bag a slot is in comes from its parent's ID (the holder), never
  -- from SetBagID: that stores the bag through an attribute whose handler
  -- copies it into button.bagID, and set by us it is OUR value -- so
  -- Blizzard's click passed an addon's number to UseContainerItem, and
  -- using any item that casts a spell was "blocked from an action only
  -- available to the Blizzard UI" (CurseForge, 28 Sept 2026: right-clicking
  -- Waylaid crates). The item button falls back to GetParent():GetID(),
  -- which the game answers itself.
  button = CreateFrame("ItemButton", "ForeverUIBagSlot" .. index, Holder(bag), "ContainerFrameItemButtonTemplate")
  button:SetID(slot)
  button.fuiBag = bag
  button:SetSize(SLOT, SLOT)
  Ring(button)
  local count = rawget(button, "Count")
  if count and count.SetFont then ns.Media.SetFont(count, "aura") end
  buttons[index] = button
  return button
end

-- One pass over every slot: texture, count, quality ring, lock, and which
-- category it belongs to for the sidebar.
local function UpdateSlots()
  local counts = { all = 0, equipment = 0, consumables = 0, materials = 0, quest = 0, misc = 0 }
  local used, total = 0, 0
  local filter = (state.filter or ""):lower()
  local index = 0
  local shown = {}
  for _, bag in ipairs(BAGS) do
    local n = NumSlots(bag)
    for slot = 1, n do
      index = index + 1
      total = total + 1
      local button = Button(bag, slot, index)
      local info = SlotInfo(bag, slot)
      local texture = info and info.iconFileID
      local category = info and CategoryOf(info) or nil
      if info then
        used = used + 1
        counts.all = counts.all + 1
        if category then counts[category] = (counts[category] or 0) + 1 end
      end
      if SetItemButtonTexture then pcall(SetItemButtonTexture, button, texture) end
      local icon = rawget(button, "icon") or rawget(button, "Icon")
      if icon then icon:SetShown(texture ~= nil) end
      if SetItemButtonCount then pcall(SetItemButtonCount, button, info and info.stackCount or 0) end
      if SetItemButtonDesaturated then pcall(SetItemButtonDesaturated, button, info and ns.Secrets.Bool(info.isLocked, false)) end
      if button.SetHasItem then pcall(button.SetHasItem, button, texture) end
      if button.UpdateCooldown then pcall(button.UpdateCooldown, button, texture) end
      RingColor(button, info and info.quality)
      -- Loot advice: a green "+" on an upgrade (Modules/Loot).
      local loot = ns.GetModule("Loot")
      if loot and loot.MarkSlot then
        pcall(loot.MarkSlot, button, info and type(info.hyperlink) == "string" and info.hyperlink or nil)
      end
      -- Filter: the sidebar's category, and the search box.
      local passes = state.category == "all" or category == state.category
      if passes and filter ~= "" then
        local name = info and type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]")
        passes = name ~= nil and name:lower():find(filter, 1, true) ~= nil
      end
      if state.category ~= "all" or filter ~= "" then
        -- Filtered views show only what matches: empties fall away too.
        passes = passes and info ~= nil
      end
      button.fuiPasses = passes
      if passes then shown[#shown + 1] = button end
    end
  end
  for i = index + 1, #buttons do
    buttons[i]:Hide()
    buttons[i].fuiPasses = false
  end
  -- Lay the shown ones out in a grid; the rest go away.
  for i, button in ipairs(buttons) do
    if i <= index and not button.fuiPasses then button:Hide() end
  end
  local cols = COLS
  for i, button in ipairs(shown) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", window.grid, "TOPLEFT", col * (SLOT + GAP), -row * (SLOT + GAP))
    button:Show()
  end
  local rows = math.max(1, math.ceil(#shown / cols))
  window.grid:SetSize(cols * (SLOT + GAP) - GAP, rows * (SLOT + GAP) - GAP)
  window.count:SetText(("%d / %d"):format(used, total))
  for _, cat in ipairs(categories) do
    cat.count:SetText(tostring(counts[cat.key] or 0))
    ns.Skin.SetSelected(cat, cat.key == state.category)
  end
  module.slotCounts = counts
  local st = Settings()
  local searchH = st.showSearch ~= false and SEARCH or 0
  local sideH = st.showCategories ~= false and #categories * 32 or 0
  local height = HEAD + searchH + 12 + math.max(rows * (SLOT + GAP) - GAP, sideH) + 12 + FOOT + 8
  window:SetHeight(height)
  return used, total
end
module.UpdateBagWindow = UpdateSlots

local function UpdateMoney()
  if not window or not GetMoney then return end
  local ok, copper = pcall(GetMoney)
  copper = ok and ns.Secrets.Number(copper) or nil
  if not copper then
    window.money:SetText("")
    return
  end
  window.money:SetText(module.MoneyText(copper))
end

-- "87 silver 14 copper", drawn the way the settings say: coin icons (and
-- their size) or letters, the coins' own colours or your class's.
function module.MoneyText(copper)
  local st = Settings()
  local size = st.currencyIconSize or 12
  local class = st.currencyClassColor and UnitClass and select(2, UnitClass("player"))
  local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  local tint = cc and ("%02x%02x%02x"):format(math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255))
  local function Coin(amount, color, icon, letter)
    local mark = st.coinIcons ~= false
      and ("|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d:2:0|t"):format(icon, size, size) or letter
    return ("|cff%s%d|r%s"):format(tint or color, amount, mark)
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local bronze = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = Coin(gold, "ffd700", "Gold", "g") end
  parts[#parts + 1] = Coin(silver, "c7c7cf", "Silver", "s")
  parts[#parts + 1] = Coin(bronze, "eda55f", "Copper", "c")
  return table.concat(parts, "  ")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Category(key, label, index)
  local row = CreateFrame("Button", nil, window.sidebar)
  row.key = key
  row:SetSize(SIDEBAR - 8, 30)
  row:SetPoint("TOPLEFT", 4, -(index - 1) * 32)
  ns.Skin.Button(row, { justify = "LEFT" })
  row:SetText(label)
  row.count = row:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(row.count, "general")
  row.count:SetPoint("RIGHT", -8, 0)
  ns.Skin.AccentText(row.count)
  row:SetScript("OnClick", function()
    state.category = key
    Settings().lastCategory = key
    UpdateSlots()
  end)
  categories[#categories + 1] = row
  return row
end

---------------------------------------------------------------------------
-- The bag slots: swap bags without Blizzard's bag bar
---------------------------------------------------------------------------
--
-- Altiokis and goldfish117 on CurseForge, 30 Sept 2026: "how can i see what
-- bags i have, to swap out for larger bags, or reagent bags?" -- Blizzard's
-- bag bar is hidden with the rest of its art. A strip above the window holds
-- one slot per bag: drag a bag onto it to put it in, click it to pick the bag
-- up. The game's own calls (PickupBagFromSlot / PutItemInBag), on buttons of
-- ours: nothing of Blizzard's bag bar is touched.
local BAG_SLOTS = { { bag = 1, label = "Bag 1" }, { bag = 2, label = "Bag 2" },
  { bag = 3, label = "Bag 3" }, { bag = 4, label = "Bag 4" } }
if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
  BAG_SLOTS[#BAG_SLOTS + 1] = { bag = Enum.BagIndex.ReagentBag, label = "Reagent bag" }
end
module.BAG_SLOTS = BAG_SLOTS
local EMPTY_BAG = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function InvSlotFor(bag)
  local f = (C_Container and C_Container.ContainerIDToInventoryID) or rawget(_G, "ContainerIDToInventoryID")
  if not f then return nil end
  local ok, slot = pcall(f, bag)
  return ok and tonumber(slot) or nil
end
module.InvSlotFor = InvSlotFor

local function PutOrPick(inv)
  if not inv then return nil end
  if CursorHasItem and CursorHasItem() then
    if PutItemInBag then pcall(PutItemInBag, inv) end
    return "put"
  end
  if PickupBagFromSlot then pcall(PickupBagFromSlot, inv) end
  return "picked"
end
module.PutOrPick = PutOrPick

function module.UpdateBagSlots()
  local strip = window and window.bagStrip
  if not strip then return 0 end
  strip:SetShown(Settings().showBagSlots == true)
  local shown = 0
  for _, b in ipairs(strip.slots) do
    b.inv = InvSlotFor(b.bag)
    local texture = b.inv and GetInventoryItemTexture and GetInventoryItemTexture("player", b.inv)
    b.icon:SetTexture(texture or EMPTY_BAG)
    b.icon:SetDesaturated(texture == nil)
    b:SetShown(b.inv ~= nil)
    if b.inv then shown = shown + 1 end
  end
  if window.head and window.head.bagsButton then
    local on = Settings().showBagSlots == true
    window.head.bagsButton:SetAlpha(on and 1 or 0.7)
  end
  return shown
end

local function BuildBagSlots(head)
  local strip = CreateFrame("Frame", nil, window)
  strip:SetSize(#BAG_SLOTS * (SLOT + GAP) - GAP + 12, SLOT + 12)
  strip:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, 4)
  ns.Skin.Panel(strip, { color = { 0.03, 0.03, 0.05, 0.94 }, borderColor = ns.Colors.ui.accent })
  strip.slots = {}
  for i, info in ipairs(BAG_SLOTS) do
    local b = CreateFrame("Button", nil, strip)
    b:SetSize(SLOT, SLOT)
    b:SetPoint("LEFT", 6 + (i - 1) * (SLOT + GAP), 0)
    b.bag, b.label = info.bag, info.label
    ns.Skin.Panel(b, { color = { 0, 0, 0, 1 } })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self) PutOrPick(self.inv) end)
    b:SetScript("OnDragStart", function(self) if self.inv and PickupBagFromSlot then pcall(PickupBagFromSlot, self.inv) end end)
    b:SetScript("OnReceiveDrag", function(self) if self.inv and PutItemInBag then pcall(PutItemInBag, self.inv) end end)
    b:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local has = self.inv and GameTooltip.SetInventoryItem and GameTooltip:SetInventoryItem("player", self.inv)
      if not has then GameTooltip:SetText(self.label .. ": empty - drag a bag here") end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    strip.slots[i] = b
  end
  strip:Hide()
  window.bagStrip = strip

  -- The toggle, beside the X.
  local toggle = CreateFrame("Button", nil, head)
  toggle:SetSize(24, 22)
  toggle:SetPoint("RIGHT", window.close, "LEFT", -4, 0)
  ns.Skin.Button(toggle)
  toggle.glyph = ns.Skin.Icon(toggle, "bags", 14, { 1, 1, 1 }, "OVERLAY")
  toggle.glyph:SetPoint("CENTER")
  toggle:SetScript("OnClick", function()
    Settings().showBagSlots = not Settings().showBagSlots
    module.UpdateBagSlots()
  end)
  toggle:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Your bags")
    GameTooltip:AddLine("Show the bag slots: drag a bigger bag on to swap it in.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  toggle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  head.bagsButton = toggle
  return strip
end

local function Build()
  local ui = ns.Colors.ui
  window = CreateFrame("Frame", "ForeverUIBagWindow", UIParent)
  window:SetSize(SIDEBAR + COLS * (SLOT + GAP) - GAP + 32, 400)
  window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 120)
  window:SetFrameStrata("HIGH")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:SetClampedToScreen(true)
  ns.Skin.Panel(window, { color = { 0.03, 0.03, 0.05, 0.94 }, borderColor = ui.accent })
  window:Hide()
  module.window = window

  -- Title row: the backpack icon, the title, the X.
  local head = CreateFrame("Frame", nil, window)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEAD)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function()
    if not Settings().locked then window:StartMoving() end
  end)
  head:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
  head.icon = ns.Skin.Icon(head, "bags", 20)
  head.icon:SetPoint("LEFT", 10, 0)
  head.title = head:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(head.title, "header")
  head.title:SetPoint("LEFT", head.icon, "RIGHT", 8, 0)
  head.title:SetText("Combined Backpack")
  head.title:SetTextColor(1, 1, 1)
  head.rule = head:CreateTexture(nil, "BORDER")
  head.rule:SetPoint("BOTTOMLEFT"); head.rule:SetPoint("BOTTOMRIGHT"); head.rule:SetHeight(ns.Media.Pixel())
  ns.Skin.AccentTexture(head.rule, 0.5)
  -- The x: Blizzard's own close button on the combined bag (invisible, as
  -- that whole bag is while ours is up) is laid over it -- see
  -- module.CoverClose -- so the click lands on Blizzard's button and the game
  -- closes its bags itself. Calling CloseAllBags from here ran Blizzard's bag
  -- code in ForeverUI's name, and that taint reached the character sheet:
  -- every C afterwards threw TextStatusBar.lua:110 (BAP2521, 2 Oct 2026).
  -- Ours is only reached without Blizzard's button (a controller hides it);
  -- then ours just hides itself.
  local close = CreateFrame("Button", nil, head)
  close:SetSize(24, 22)
  close:SetPoint("RIGHT", -6, 0)
  ns.Skin.Button(close)
  close.glyph = ns.Skin.Icon(close, "close", 12, { 1, 1, 1 }, "OVERLAY")
  close.glyph:SetPoint("CENTER")
  close:SetScript("OnClick", function() window:Hide() end)
  window.head, window.close = head, close
  BuildBagSlots(head)

  -- Search line with the used/total count.
  local search = CreateFrame("EditBox", "ForeverUIBagSearch", window)
  search:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 10, -6)
  search:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -10, -6)
  search:SetHeight(SEARCH - 8)
  search:SetAutoFocus(false)
  ns.Media.SetFont(search, "general")
  search:SetTextInsets(28, 60, 0, 0)
  ns.Skin.Panel(search, { color = { 0.06, 0.06, 0.08, 1 } })
  search.glass = ns.Skin.Icon(search, "search", 14, ui.textDim, "OVERLAY")
  search.glass:SetPoint("LEFT", 8, 0)
  search.hint = search:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(search.hint, "general")
  search.hint:SetPoint("LEFT", 28, 0)
  search.hint:SetText("Search items...")
  search.hint:SetTextColor(unpack(ui.textDim))
  search:SetScript("OnTextChanged", function(self)
    state.filter = self:GetText() or ""
    self.hint:SetShown(state.filter == "")
    UpdateSlots()
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  window.search = search
  window.count = search:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(window.count, "general")
  window.count:SetPoint("RIGHT", -8, 0)
  window.count:SetTextColor(unpack(ui.textDim))

  -- Sidebar of categories.
  local sidebar = CreateFrame("Frame", nil, window)
  sidebar:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -8)
  sidebar:SetSize(SIDEBAR, 200)
  window.sidebar = sidebar
  for i, cat in ipairs(CATEGORIES) do
    Category(cat.key, cat.label, i)
  end

  -- The grid.
  local grid = CreateFrame("Frame", nil, window)
  grid:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
  grid:SetSize(COLS * (SLOT + GAP) - GAP, SLOT)
  window.grid = grid

  -- Footer: money, cog, Clean Up.
  local footer = CreateFrame("Frame", nil, window)
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
  footer:SetHeight(FOOT)
  footer.rule = footer:CreateTexture(nil, "BORDER")
  footer.rule:SetPoint("TOPLEFT"); footer.rule:SetPoint("TOPRIGHT"); footer.rule:SetHeight(ns.Media.Pixel())
  ns.Skin.AccentTexture(footer.rule, 0.5)
  local coins = ns.Skin.Icon(footer, "money", 16)
  coins:SetPoint("LEFT", 12, 0)
  window.coins = coins
  window.money = footer:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(window.money, "general")
  window.money:SetPoint("LEFT", coins, "RIGHT", 8, 0)
  local clean = CreateFrame("Button", nil, footer)
  clean:SetSize(90, 24)
  clean:SetPoint("RIGHT", -8, 0)
  ns.Skin.Button(clean)
  clean:SetText("Clean Up")
  clean.glyph = ns.Skin.Icon(clean, "cleanup", 14, nil, "OVERLAY")
  clean.glyph:SetPoint("RIGHT", clean.text, "LEFT", -4, 0)
  clean:SetScript("OnClick", function()
    if C_Container and C_Container.SortBags then pcall(C_Container.SortBags) end
  end)
  local cog = CreateFrame("Button", nil, footer)
  cog:SetSize(24, 24)
  cog:SetPoint("RIGHT", clean, "LEFT", -8, 0)
  ns.Skin.Button(cog)
  cog.glyph = ns.Skin.Icon(cog, "general", 14, nil, "OVERLAY")
  cog.glyph:SetPoint("CENTER")
  cog:SetScript("OnClick", function() ns.OpenOptions("Bags") end)
  window.footer, window.clean, window.cog = footer, clean, cog

  -- Follow what is in the bags.
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "PLAYER_MONEY",
    "BAG_UPDATE_COOLDOWN", "BAG_NEW_ITEMS_UPDATED", "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "BAG_CONTAINER_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function(_, event)
    if not window:IsShown() then return end
    if event == "PLAYER_MONEY" then UpdateMoney() else UpdateSlots() end
    -- A bag put in or taken out changes both the slots and the strip.
    if event ~= "PLAYER_MONEY" then module.UpdateBagSlots() end
  end)
  window.watcher = watcher

  if UISpecialFrames then
    table.insert(UISpecialFrames, "ForeverUIBagWindow") -- Escape closes it
  end
  if Settings().restoreCategory and Settings().lastCategory then
    state.category = Settings().lastCategory
  end
  ApplyLook()

  window:SetScript("OnHide", function()
    -- Ours closes because Blizzard's did (Escape closes the bags before
    -- anything else). If ours went away while Blizzard's is still open, it
    -- is shown again rather than closed from here: closing it from addon
    -- code is the taint that broke the character sheet (see the x above).
    local blizzard = _G.ContainerFrameCombinedBags
    if blizzard and blizzard:IsShown() and blizzard:GetAlpha() == 0 then
      module.CoverClose(blizzard, false)
      blizzard:SetAlpha(1)
      if blizzard.EnableMouse then pcall(blizzard.EnableMouse, blizzard, true) end
      for _, item in ipairs(rawget(blizzard, "Items") or {}) do
        if item.EnableMouse then pcall(item.EnableMouse, item, true) end
      end
    end
    module.ForgetNewItems()
  end)
end

-- The "new item" glow (Staghelm on CurseForge, 2 Oct 2026: "stop everything
-- in the bag being highlighted on relog/reload"). The slots are Blizzard's,
-- and Blizzard takes an item's "new" mark off when ITS bag window closes.
-- Ours never goes through that, so the marks piled up and everything glowed.
-- So: forgotten when our window closes, as Blizzard's would, and once on
-- entering the world. Bags > "Forget the new-item glow when the bags close".
function module.ForgetNewItems()
  if Settings().clearNewItems == false then return false end
  if not (C_NewItems and C_NewItems.ClearAll) then return false end
  return pcall(C_NewItems.ClearAll)
end

local newItemWatcher = CreateFrame("Frame")
pcall(newItemWatcher.RegisterEvent, newItemWatcher, "PLAYER_ENTERING_WORLD")
newItemWatcher:SetScript("OnEvent", function()
  if ns.ModuleRunning and ns.ModuleRunning("Bags") then module.ForgetNewItems() end
end)
module.newItemWatcher = newItemWatcher

---------------------------------------------------------------------------
-- The look: everything the Bags page sets
---------------------------------------------------------------------------

ApplyLook = function()
  if not window then return end
  local st = Settings()
  window:SetScale(st.scale or 1)
  ns.Skin.SetPanelColor(window, { 0.03, 0.03, 0.05, st.bgAlpha or 0.94 })
  local thickness = st.borderSize or 1
  local px = ns.Media.Pixel() * math.max(thickness, 1)
  for side, edge in pairs(window.borderEdges or {}) do
    if type(side) == "string" then
      if side == "TOP" or side == "BOTTOM" then edge:SetHeight(px) else edge:SetWidth(px) end
      edge:SetShown(thickness > 0)
    end
  end

  -- The search line, and the count in it (or in the title bar without it).
  local search, count = window.search, window.count
  local searching = st.showSearch ~= false
  search:SetShown(searching)
  count:ClearAllPoints()
  if searching then
    count:SetParent(search)
    if st.countSide == "left" then
      count:SetPoint("LEFT", 28, 0)
      search:SetTextInsets(80, 8, 0, 0)
      search.hint:ClearAllPoints()
      search.hint:SetPoint("LEFT", 80, 0)
    else
      count:SetPoint("RIGHT", -8, 0)
      search:SetTextInsets(28, 60, 0, 0)
      search.hint:ClearAllPoints()
      search.hint:SetPoint("LEFT", 28, 0)
    end
  else
    count:SetParent(window.head)
    count:SetPoint("RIGHT", window.close, "LEFT", -8, 0)
  end
  count:SetShown(st.showCount ~= false)

  -- The category buttons, or the grid straight under the search.
  local sidebar, grid = window.sidebar, window.grid
  local sides = st.showCategories ~= false
  sidebar:ClearAllPoints()
  if searching then
    sidebar:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -8)
  else
    sidebar:SetPoint("TOPLEFT", window.head, "BOTTOMLEFT", 6, -8)
  end
  sidebar:SetShown(sides)
  grid:ClearAllPoints()
  if sides then
    grid:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
  else
    grid:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, 0)
    state.category = "all"
  end
  local gridW = COLS * (SLOT + GAP) - GAP
  window:SetWidth(sides and (SIDEBAR + gridW + 32) or (gridW + 20))

  -- The currency line.
  local money = window.money
  money:SetShown(st.showCurrency ~= false)
  window.coins:SetShown(st.showCurrency ~= false)
  local path, _, flags = ns.Media.Role("general")
  money:SetFont(path, st.currencyTextSize or 12, flags or "")
  if window:IsShown() then
    UpdateSlots()
    UpdateMoney()
  end
end
module.ApplyBagLook = ApplyLook

-- A quick fade in and out, when asked for.
local fading
local function Fade(to, done)
  if not window then return end
  if not Settings().animate then
    window:SetAlpha(1)
    if done then done() end
    return
  end
  fading = fading or CreateFrame("Frame")
  local from, t = window:GetAlpha() or (to == 1 and 0 or 1), 0
  fading:SetScript("OnUpdate", function(self, elapsed)
    t = t + (elapsed or 0.05)
    local f = math.min(1, t / 0.15)
    window:SetAlpha(from + (to - from) * f)
    if f >= 1 then
      self:SetScript("OnUpdate", nil)
      if done then done() end
    end
  end)
end

-- What the options page's preview shows: counts per category, used and
-- total, and the first few items as they sit in the bags.
function module.Snapshot(limit)
  local counts = { all = 0, equipment = 0, consumables = 0, materials = 0, quest = 0, misc = 0 }
  local items, used, total = {}, 0, 0
  for _, bag in ipairs(BAGS) do
    for slot = 1, NumSlots(bag) do
      total = total + 1
      local info = SlotInfo(bag, slot)
      if info then
        used = used + 1
        counts.all = counts.all + 1
        local category = CategoryOf(info)
        if category then counts[category] = (counts[category] or 0) + 1 end
        if #items < (limit or 40) then
          items[#items + 1] = { icon = info.iconFileID, quality = info.quality, count = info.stackCount }
        end
      elseif #items < (limit or 40) then
        items[#items + 1] = false
      end
    end
  end
  return { counts = counts, items = items, used = used, total = total }
end

-- Blizzard's close button sits on our x while ours is up (see the x in
-- Build), and goes back to its own corner when Blizzard's bag is shown as
-- itself. Only its place and layer change: it stays Blizzard's child, so
-- clicking it is the game's own close. Not protected, so this is fine in
-- combat too.
function module.CoverClose(blizzard, on)
  local button = blizzard and rawget(blizzard, "CloseButton")
  if not (button and button.SetPoint and window and window.close) then return false end
  if on then
    if not button.fuiHome then
      local home = {}
      for i = 1, (button:GetNumPoints() or 0) do home[i] = { button:GetPoint(i) } end
      button.fuiHome = { points = home, strata = button:GetFrameStrata(), level = button:GetFrameLevel() }
    end
    button:ClearAllPoints()
    button:SetAllPoints(window.close)
    button:SetFrameStrata(window:GetFrameStrata())
    button:SetFrameLevel(window.close:GetFrameLevel() + 10)
    return true
  end
  local home = button.fuiHome
  if not home then return false end
  button.fuiHome = nil
  button:ClearAllPoints()
  for _, p in ipairs(home.points) do button:SetPoint(unpack(p)) end
  if home.strata then button:SetFrameStrata(home.strata) end
  if home.level then button:SetFrameLevel(home.level) end
  return true
end

-- Blizzard's combined bag opens and closes as it always did; ours mirrors
-- it. The Blizzard frame is faded and made click-through while ours is up,
-- never hidden -- hiding it is what closes the bags.
local function Mirror(blizzard)
  if not window then Build() end
  local on = Settings().ownWindow ~= false
  if on and blizzard:IsShown() then
    blizzard:SetAlpha(0)
    if blizzard.EnableMouse then pcall(blizzard.EnableMouse, blizzard, false) end
    for _, item in ipairs(rawget(blizzard, "Items") or {}) do
      if item.EnableMouse then pcall(item.EnableMouse, item, false) end
    end
    if not window:IsShown() then
      local st = Settings()
      if not st.rememberCategory then state.category = "all" end
      if st.showCategories == false then state.category = "all" end
      if st.animate then window:SetAlpha(0) end
      window:Show()
      Fade(1)
    end
    UpdateSlots()
    UpdateMoney()
    module.UpdateBagSlots()
    module.CoverClose(blizzard, true)
  else
    if not on then
      module.CoverClose(blizzard, false)
      blizzard:SetAlpha(1)
      if blizzard.EnableMouse then pcall(blizzard.EnableMouse, blizzard, true) end
      for _, item in ipairs(rawget(blizzard, "Items") or {}) do
        if item.EnableMouse then pcall(item.EnableMouse, item, true) end
      end
    end
    if window:IsShown() and Settings().animate and not (InCombatLockdown and InCombatLockdown()) then
      Fade(0, function() window:Hide(); window:SetAlpha(1) end)
    else
      window:Hide()
    end
  end
end
module.MirrorBags = Mirror

-- A bag Blizzard opens in a window of its own beside the combined one (the
-- reagent bag, when something opens every bag: a vendor, "open all bags")
-- is already in ForeverUI's window. With ours in use it is faded and made
-- click-through like the combined one -- never hidden, which would close it.
local function IsOwnBagFrame(frame)
  local ok, bag = pcall(function() return frame.GetBagID and frame:GetBagID() end)
  if not ok or type(bag) ~= "number" then return false end
  for _, b in ipairs(BAGS) do
    if b == bag then return true end
  end
  return false
end

-- Only while ForeverUI's window is actually up showing them. With the game's
-- "separate bags" setting there is no combined bag for ours to follow, so
-- Blizzard's own bag windows are the ONLY bags -- faded, B opened nothing
-- but the sound (Altiokis on CurseForge, 30 Sept 2026, after 0.4.50).
local function QuietExtraBag(frame)
  if Settings().ownWindow == false or not frame:IsShown() or not IsOwnBagFrame(frame)
    or not (window and window:IsShown()) then
    if frame.fuiQuieted then
      frame.fuiQuieted = nil
      frame:SetAlpha(1)
      if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
    end
    return false
  end
  frame.fuiQuieted = true
  frame:SetAlpha(0)
  if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
  for _, item in ipairs(rawget(frame, "Items") or {}) do
    if item.EnableMouse then pcall(item.EnableMouse, item, false) end
  end
  return true
end
module.QuietExtraBag = QuietExtraBag

function module.HookBags()
  local blizzard = _G.ContainerFrameCombinedBags
  if not blizzard or module.bagsHooked then
    return false
  end
  module.bagsHooked = true
  blizzard:HookScript("OnShow", function(self) Mirror(self) end)
  blizzard:HookScript("OnHide", function(self) Mirror(self) end)
  if blizzard:IsShown() then Mirror(blizzard) end
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local frame = rawget(_G, "ContainerFrame" .. i)
    if type(frame) == "table" and frame.HookScript then
      frame:HookScript("OnShow", function(self) QuietExtraBag(self) end)
    end
  end
  return true
end
