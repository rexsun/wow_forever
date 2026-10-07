local _, ns = ...

-- The bag windows, dressed like the chat: Blizzard's parchment, gold trim
-- and portrait medallion go, and in their place the same dark panel with a
-- thin blue edge, the title in our font, flat item slots. Nothing about how
-- the bags WORK is touched -- the item buttons are Blizzard's secure ones,
-- untouched but for the ring drawn around them -- so picking up, using and
-- moving items is exactly the game's own.
--
-- Covers the combined backpack and the separate bag windows, whichever the
-- client opens. Everything is found by field or by name and skipped when
-- absent, so a client that lays its bags out differently just shows them
-- plain.

local module = ns.RegisterModule({
  name = "Bags",
  title = "Bags",
})

module.defaults = {
  skin = true,
  ownWindow = true,   -- ForeverUI's own bag window (categories, search, quality rings)
  -- The bag window, to the owner's mock-up (23 Sept 2026).
  scale = 1,
  bgAlpha = 0.94,           -- background opacity
  borderSize = 1,           -- pixels; 0 is no border
  locked = false,           -- the title bar won't drag it
  rememberCategory = true,  -- reopening keeps the category you were on
  restoreCategory = false,  -- ...even after a reload
  lastCategory = "all",
  animate = false,          -- a quick fade in and out
  showSearch = true,
  showCount = true,         -- "14 / 38"
  countSide = "right",      -- where the count sits in the search line
  showCategories = true,    -- the category buttons down the side
  showCurrency = true,
  currencyClassColor = false,
  coinIcons = true,
  currencyTextSize = 12,
  currencyIconSize = 12,
  showBagSlots = false,     -- the strip of bag slots above the window (swap bags there)
  clearNewItems = true,     -- forget the game's "new item" glow when the bags close
}

-- The settings a bag preset holds: everything above but the two switches
-- that decide whose bags these are.
module.PRESET_KEYS = { "scale", "bgAlpha", "borderSize", "locked", "rememberCategory", "restoreCategory",
  "animate", "showSearch", "showCount", "countSide", "showCategories", "showCurrency",
  "currencyClassColor", "coinIcons", "currencyTextSize", "currencyIconSize" }

module.options = {
  { type = "heading", label = "Bags" },
  { type = "checkbox", key = "ownWindow", label = "ForeverUI's own bag window (categories, search, quality rings)" },
  { type = "checkbox", key = "showBagSlots", label = "Show your bag slots above the bags",
    desc = "Drag a bigger bag (or a reagent bag) onto a slot to swap it in. The bag button in the window's title does the same.",
    apply = function() local w = ns.GetModule("Bags"); if w and w.UpdateBagSlots then w.UpdateBagSlots() end end },
  { type = "checkbox", key = "clearNewItems", label = "Forget the new-item glow when the bags close",
    desc = "Off: items you picked up stay lit until the game clears them, as in Blizzard's bags." },
  { type = "checkbox", key = "skin", label = "Match Blizzard's bag windows to the rest of the UI", reload = true },
  { type = "checkbox", key = "hideBags", moduleName = "ActionBars", reload = true,
    label = "Hide Blizzard's bag bar", desc = "Action Bars does the hiding, so it needs Action Bars on." },
  { type = "note", label = "The bags themselves are Blizzard's; only their clothes change. Turning this off takes a /reload." },
}

local function Settings()
  return ns.db.modules.Bags
end

local skinned = {}       -- container frame -> true
local slotSkins = {}     -- item button -> our textures
module.skinned, module.slotSkins = skinned, slotSkins

local FRAME_ART_KEYS = { "NineSlice", "Bg", "PortraitContainer", "TitleContainer", "TitleBg", "Portrait", "PortraitButton" }

-- Fade every texture on a frame (not its FontStrings, not its children's
-- buttons) -- the parchment and trim are all textures.
local function FadeTextures(frame, keepText)
  if type(frame) ~= "table" or not frame.GetRegions then
    return
  end
  for _, region in ipairs(ns.Skin.Regions(frame)) do
    if region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
      region:SetAlpha(0)
    end
  end
  if not keepText and frame.Hide and frame ~= UIParent then
    -- Portrait medallions and title backdrops are frames of their own.
    frame:SetAlpha(0)
  end
end

-- One item slot, flat: dark fill, one-pixel edge, and none of Blizzard's
-- three layers of slot art -- the bevelled backing the combined bag draws
-- under each slot (ItemSlotBackground), the gold ring (NormalTexture), and
-- the "wing" an empty slot shows on its icon (the emptyBackgroundAtlas).
-- The button itself is untouched: still Blizzard's, still secure.
local function FlattenSlot(button)
  local backing = rawget(button, "ItemSlotBackground")
  if backing and backing.SetAlpha then backing:SetAlpha(0) end
  local normal = button.GetNormalTexture and button:GetNormalTexture()
  if normal and normal.SetAlpha then normal:SetAlpha(0) end
  local ring = rawget(button, "NormalTexture")
  if ring and ring.SetAlpha then ring:SetAlpha(0) end
  local pushed = rawget(button, "PushedTexture")
  if pushed and pushed.SetAlpha then pushed:SetAlpha(0) end
  -- An empty slot's icon is the wing; with no empty-slot atlas the icon is
  -- simply hidden until an item lands in it.
  if rawget(button, "emptyBackgroundAtlas") ~= nil then
    button.emptyBackgroundAtlas = nil
  end
  local icon = rawget(button, "icon") or rawget(button, "Icon")
  if icon and icon.GetAtlas then
    if rawget(button, "hasItem") then
      icon:Show() -- an item is in here: whatever the atlas says, show it
    else
      local ok, atlas = pcall(icon.GetAtlas, icon)
      if ok and type(atlas) == "string" and atlas:find("item-slot", 1, true) then
        icon:Hide()
      end
    end
  end
end

local function SkinSlot(button)
  if not button or not button.CreateTexture then
    return
  end
  FlattenSlot(button)
  if slotSkins[button] then
    return
  end
  local ui = ns.Colors.ui
  local fill = button:CreateTexture(nil, "BACKGROUND", nil, -5) -- above the bevel it replaces
  fill:SetPoint("TOPLEFT", -1, 1)
  fill:SetPoint("BOTTOMRIGHT", 1, -1)
  fill:SetColorTexture(0.08, 0.08, 0.10, 1)
  local parts = { fill }
  local px = ns.Media.Pixel()
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = button:CreateTexture(nil, "BORDER")
    t:SetColorTexture(ui.border[1], ui.border[2], ui.border[3], 1)
    if side == "TOP" then t:SetPoint("TOPLEFT", fill); t:SetPoint("TOPRIGHT", fill); t:SetHeight(px)
    elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetHeight(px)
    elseif side == "LEFT" then t:SetPoint("TOPLEFT", fill); t:SetPoint("BOTTOMLEFT", fill); t:SetWidth(px)
    else t:SetPoint("TOPRIGHT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetWidth(px) end
    parts[#parts + 1] = t
  end
  local count = rawget(button, "Count") or (button.GetName and _G[(button:GetName() or "") .. "Count"])
  if count and count.SetFont then ns.Media.SetFont(count, "general") end
  -- The game re-lays a slot every time its contents change; the wing comes
  -- back with an empty one, so it is put away again on each pass.
  if hooksecurefunc and button.SetItemButtonTexture then
    hooksecurefunc(button, "SetItemButtonTexture", function(self, texture)
      local ic = rawget(self, "icon") or rawget(self, "Icon")
      if not ic then return end
      if texture or rawget(self, "hasItem") then
        ic:Show()
      else
        ic:Hide()
      end
    end)
  end
  slotSkins[button] = parts
end

-- Every item button a container frame holds, however this client keeps them.
local function EachItem(frame, fn)
  if frame.EnumerateValidItems then
    local ok = pcall(function()
      for _, item in frame:EnumerateValidItems() do fn(item) end
    end)
    if ok then return end
  end
  local items = rawget(frame, "Items")
  if type(items) == "table" then
    for _, item in ipairs(items) do fn(item) end
    return
  end
  local name = frame.GetName and frame:GetName()
  if name then
    for i = 1, 40 do
      local item = _G[name .. "Item" .. i]
      if not item then break end
      fn(item)
    end
  end
end

local function SkinSlots(frame)
  EachItem(frame, SkinSlot)
end

local function SkinContainer(frame)
  if not frame or skinned[frame] or not frame.CreateTexture then
    return false
  end
  skinned[frame] = true
  local ui = ns.Colors.ui

  -- The parchment: the frame's own textures plus the named dressing frames.
  FadeTextures(frame, true)
  for _, key in ipairs(FRAME_ART_KEYS) do
    local piece = rawget(frame, key)
    if type(piece) == "table" then
      if key == "TitleContainer" then
        FadeTextures(piece, true) -- keep the title text
      else
        FadeTextures(piece)
      end
    end
  end

  -- Our shell: the same fill and blue edge the chat wears.
  local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  fill:SetColorTexture(0.03, 0.03, 0.05, 0.92)
  local px = ns.Media.Pixel()
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = frame:CreateTexture(nil, "BORDER")
    ns.Skin.AccentTexture(t, 0.85)
    if side == "TOP" then t:SetPoint("TOPLEFT", fill); t:SetPoint("TOPRIGHT", fill); t:SetHeight(px)
    elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetHeight(px)
    elseif side == "LEFT" then t:SetPoint("TOPLEFT", fill); t:SetPoint("BOTTOMLEFT", fill); t:SetWidth(px)
    else t:SetPoint("TOPRIGHT", fill); t:SetPoint("BOTTOMRIGHT", fill); t:SetWidth(px) end
  end
  frame.fuiShell = fill

  -- The title, in our font and the accent colour.
  local container = rawget(frame, "TitleContainer")
  local title = (container and rawget(container, "TitleText")) or rawget(frame, "TitleText")
    or (frame.GetName and _G[(frame:GetName() or "") .. "Name"])
  if title and title.SetFont then
    ns.Media.SetFont(title, "header")
    if title.SetTextColor then ns.Skin.AccentText(title) end
  end

  -- The close button: Blizzard's red X becomes our flat one.
  local close = rawget(frame, "CloseButton") or (frame.GetName and _G[(frame:GetName() or "") .. "CloseButton"])
  if close and close.CreateTexture then
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
      local t = close[get] and close[get](close)
      if t and t.SetAlpha then t:SetAlpha(0) end
    end
    ns.Skin.Button(close)
    close:SetText("X")
    close:SetSize(20, 20)
  end

  -- Search box and money line: their gold frames go, a flat inset in
  -- the box's own colours takes over, text in our font. The magnifier and
  -- the coins are icons, kept.
  local function Flat(piece, keep)
    if type(piece) ~= "table" or not piece.CreateTexture then return end
    for _, region in ipairs(ns.Skin.Regions(piece)) do
      if region.GetObjectType and region:GetObjectType() == "Texture" and region ~= keep and region.SetAlpha then
        region:SetAlpha(0)
      elseif region.GetObjectType and region:GetObjectType() == "FontString" and region.SetFont then
        ns.Media.SetFont(region, "general")
      end
    end
    local inset = piece:CreateTexture(nil, "BACKGROUND", nil, -6)
    inset:SetPoint("TOPLEFT", 0, 0)
    inset:SetPoint("BOTTOMRIGHT", 0, 0)
    inset:SetColorTexture(0.08, 0.08, 0.10, 1)
    local line = piece:CreateTexture(nil, "BORDER")
    line:SetColorTexture(ui.border[1], ui.border[2], ui.border[3], 1)
    line:SetPoint("TOPLEFT", inset, "TOPLEFT")
    line:SetPoint("TOPRIGHT", inset, "TOPRIGHT")
    line:SetHeight(px)
    local under = piece:CreateTexture(nil, "BORDER")
    under:SetColorTexture(ui.border[1], ui.border[2], ui.border[3], 1)
    under:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")
    under:SetHeight(px)
  end
  -- The search box is one shared global that moves between bag windows;
  -- its frame is three textures (Left, Middle, Right) on the box itself.
  local search = rawget(frame, "SearchBox") or _G.BagItemSearchBox
  if search and not rawget(search, "fuiFlat") then
    search.fuiFlat = true
    Flat(search, rawget(search, "searchIcon"))
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
      local t = rawget(search, key)
      if t and t.SetAlpha then t:SetAlpha(0) end
    end
    if search.SetFont then ns.Media.SetFont(search, "general") end
  end
  -- The money line's gold coin-box is a child frame of its own (Border).
  local money = rawget(frame, "MoneyFrame")
  if money then
    Flat(money)
    local border = rawget(money, "Border")
    if border then FadeTextures(border) end
  end

  SkinSlots(frame)
  -- Slots are pooled and re-laid whenever the bag opens or changes size.
  if frame.HookScript then
    frame:HookScript("OnShow", function(self) SkinSlots(self) end)
  end
  if hooksecurefunc and frame.UpdateItems then
    hooksecurefunc(frame, "UpdateItems", function(self) SkinSlots(self) end)
  end
  return true
end
module.SkinContainer = SkinContainer

local function CandidateFrames()
  local list = {}
  if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local frame = _G["ContainerFrame" .. i]
    if frame then list[#list + 1] = frame end
  end
  return list
end

local function Apply()
  if not Settings().skin then
    return 0
  end
  local count = 0
  for _, frame in ipairs(CandidateFrames()) do
    if SkinContainer(frame) then count = count + 1 end
  end
  module.count = count
  return count
end
module.Apply = Apply

function module:OnEnable()
  Apply()
  if module.HookBags then module.HookBags() end
end

function module:Refresh()
  Apply()
  if module.HookBags then module.HookBags() end
  if module.ApplyBagLook then module.ApplyBagLook() end
  local blizzard = _G.ContainerFrameCombinedBags
  if blizzard and module.MirrorBags then module.MirrorBags(blizzard) end
end

function module:OnDisable()
  -- Textures created on Blizzard's frames stay; the switch asks for a reload.
end
