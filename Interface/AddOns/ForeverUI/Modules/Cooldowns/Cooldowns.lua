local _, ns = ...

-- Cooldowns: Blizzard's Cooldown Manager, in ForeverUI's style.
--
-- On Forever an addon can't read cooldowns (or auras) in a fight, so a
-- tracker of our own would go blank exactly when it matters. Blizzard's
-- Cooldown Manager doesn't have that problem - the game draws it - so this
-- takes the game's four viewers (Essential, Utility, the buff icons and the
-- buff bars) and gives them the ForeverUI look: square icons cropped clean,
-- a flat one-pixel border, our font on the counts, flat bars. It reads
-- nothing; every number on it is still the game's.
--
-- Which cooldowns show is Blizzard's settings panel ("Choose cooldowns");
-- where they sit and how big is Edit Mode ("Move them") - both a click away
-- here. What this adds on top: the look, and fading the whole thing out of
-- combat if you only want it in a fight.
--
-- Suggested by wixer5851 on CurseForge, 24 Sept 2026.

local module = ns.RegisterModule({
  name = "Cooldowns",
  title = "Cooldowns",
})

module.defaults = {
  restyle = true,          -- ForeverUI's look on Blizzard's viewers
  crop = true,             -- square icons, the round mask and frame art gone
  showBorder = true,
  outOfCombatAlpha = 1,    -- how solid the viewers are out of combat, 0..1
}

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer",
  "BuffBarCooldownViewer" }
module.VIEWERS = VIEWERS

local ATLAS_ART = {
  ["UI-HUD-CoolDownManager-IconOverlay"] = true,
  ["UI-HUD-CoolDownManager-Bar-BG"] = true,
  ["UI-HUD-CoolDownManager-Bar-Pip"] = true,
}

local function Settings()
  return ns.db.modules.Cooldowns
end

local function Running()
  return ns.IsModuleEnabled("Cooldowns") and Settings().restyle
end

-- The game's own switch for the whole Cooldown Manager.
function module.ManagerOn()
  local ok, value = pcall(GetCVar, "cooldownViewerEnabled")
  return ok and (value == "1" or value == 1 or value == true)
end

function module.SetManagerOn(on)
  ns.SetCVar("cooldownViewerEnabled", on and "1" or "0")
end

-- Hide Blizzard's frame art on an item: the round mask on the icon and the
-- overlay ring (neither has a key, so they are found by what they are).
local function StripArt(frame, icon)
  if icon and icon.GetNumMaskTextures and icon.RemoveMaskTexture then
    for i = icon:GetNumMaskTextures(), 1, -1 do
      local mask = icon:GetMaskTexture(i)
      if mask then pcall(icon.RemoveMaskTexture, icon, mask) end
    end
  end
  for _, region in ipairs({ frame:GetRegions() }) do
    local atlas = region.GetAtlas and region:GetAtlas()
    if atlas and ATLAS_ART[atlas] then region:SetAlpha(0) end
  end
end

-- A child region or frame by key, or nil (never a method of the same name).
local function Part(parent, key)
  if type(parent) ~= "table" then return nil end
  local v = parent[key]
  return type(v) == "table" and v or nil
end

local function Crop(icon)
  if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- One icon (Essential, Utility, buff icon).
local function SkinIcon(frame)
  local icon = frame.Icon
  if type(icon) ~= "table" or not icon.SetTexCoord then return end
  local s = Settings()
  if s.crop then
    StripArt(frame, icon)
    Crop(icon)
  end
  if s.showBorder and not frame.fuiBorder then
    local px = ns.Media.Pixel()
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
    local back = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 1)
    ns.Skin.Border(frame, ns.Colors.ui.border)
    frame.fuiBorder = true
  end
  if type(frame.Cooldown) == "table" and frame.Cooldown.SetSwipeColor then
    pcall(frame.Cooldown.SetSwipeTexture, frame.Cooldown, "Interface\\Buttons\\WHITE8X8")
    pcall(frame.Cooldown.SetSwipeColor, frame.Cooldown, 0, 0, 0, 0.75)
  end
  local count = Part(Part(frame, "ChargeCount"), "Current")
  if count then ns.Media.SetFont(count, "general") end
  local apps = Part(Part(frame, "Applications"), "Applications")
  if apps then ns.Media.SetFont(apps, "general") end
  frame.fuiSkinned = true
end

-- One bar (the buff bar viewer): icon on the left, a flat bar beside it.
local function SkinBar(frame)
  local s = Settings()
  local iconHolder = frame.Icon
  local icon = iconHolder and iconHolder.Icon
  if icon and s.crop then
    StripArt(iconHolder, icon)
    Crop(icon)
  end
  local bar = frame.Bar
  if bar and bar.SetStatusBarTexture then
    bar:SetStatusBarTexture(ns.Media.StatusBarTexture())
    StripArt(bar)
    if not bar.fuiBack then
      local back = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
      back:SetAllPoints()
      back:SetColorTexture(0, 0, 0, 0.6)
      bar.fuiBack = back
      if s.showBorder then ns.Skin.Border(bar, ns.Colors.ui.border) end
    end
    if bar.Name then ns.Media.SetFont(bar.Name, "general") end
    if bar.Duration then ns.Media.SetFont(bar.Duration, "general") end
  end
  frame.fuiSkinned = true
end

local function SkinItem(viewerName, frame)
  if not frame or not Running() then return end
  if viewerName == "BuffBarCooldownViewer" then
    SkinBar(frame)
  else
    SkinIcon(frame)
  end
end
module.SkinItem = SkinItem

local function ActiveItems(viewer)
  local items = {}
  if viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
    for frame in viewer.itemFramePool:EnumerateActive() do items[#items + 1] = frame end
  elseif viewer.GetItemFrames then
    local ok, list = pcall(viewer.GetItemFrames, viewer)
    if ok and type(list) == "table" then items = list end
  end
  return items
end

function module.SkinAll()
  for _, name in ipairs(VIEWERS) do
    local viewer = _G[name]
    if viewer then
      for _, frame in ipairs(ActiveItems(viewer)) do SkinItem(name, frame) end
    end
  end
end

-- Out of combat, as solid as asked; in combat, always fully shown.
function module.ApplyAlpha()
  local alpha = 1
  if ns.IsModuleEnabled("Cooldowns") and not (InCombatLockdown and InCombatLockdown()) then
    alpha = Settings().outOfCombatAlpha or 1
  end
  for _, name in ipairs(VIEWERS) do
    local viewer = _G[name]
    if viewer and viewer.SetAlpha then viewer:SetAlpha(alpha) end
  end
end

-- Hook each viewer once: every icon it hands out gets our look as it goes up.
local hooked = {}
function module.Hook()
  if not hooksecurefunc then return 0 end
  local n = 0
  for _, name in ipairs(VIEWERS) do
    local viewer = _G[name]
    if viewer and not hooked[name] then
      if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, frame) SkinItem(name, frame) end)
      end
      if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function() module.SkinAll() end)
      end
      hooked[name] = true
      n = n + 1
    end
  end
  return n
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "Blizzard_CooldownViewer" then
      module.Hook()
      module.SkinAll()
      module.ApplyAlpha()
    end
    return
  end
  module.ApplyAlpha()
end)

function module:OnEnable()
  watcher:RegisterEvent("ADDON_LOADED")
  watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
  watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
  module.Hook()
  module.SkinAll()
  module.ApplyAlpha()
end

function module:OnDisable()
  watcher:UnregisterAllEvents()
  module.ApplyAlpha()
end

function module:Refresh()
  module.SkinAll()
  module.ApplyAlpha()
end

-- Blizzard's Cooldown Manager settings and Edit Mode are both panel-manager
-- windows: opening either from here taints the manager, and the character
-- sheet dies on the next C (see ns.Skin.OpenHint). Say where they are.
function module.OpenChooser()
  return ns.Skin.OpenHint("cooldowns")
end

function module.OpenEditMode()
  return ns.Skin.OpenHint("editmode")
end

function module.Status()
  if not _G.EssentialCooldownViewer then
    return "Blizzard's Cooldown Manager isn't on this client."
  end
  if not module.ManagerOn() then
    return "Blizzard's Cooldown Manager is switched off - tick the box above to turn it on."
  end
  return "Blizzard's Cooldown Manager is on. Choose what it tracks and move it with the buttons below."
end

local function Percent(v)
  return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5))
end

module.options = {
  { type = "heading", label = "Cooldowns", subtitle = "Blizzard's Cooldown Manager, in ForeverUI's style",
    icon = "spells" },
  { type = "checkbox", switch = true, key = "enabled", label = "ForeverUI's look on the Cooldown Manager",
    get = function() return ns.IsModuleEnabled("Cooldowns") end,
    set = function(on) ns.SetModuleEnabled("Cooldowns", on) end },
  { type = "checkbox", key = "managerOn", label = "Show Blizzard's Cooldown Manager",
    desc = "The game draws it, so unlike an addon's tracker it keeps working in combat.",
    get = function() return module.ManagerOn() end,
    set = function(on) module.SetManagerOn(on); if ns.RefreshOptions then ns.RefreshOptions() end end },
  { type = "note", labelFor = function() return module.Status() end },
  { type = "action", label = "Choose cooldowns", width = 200, icon = "general",
    desc = "Blizzard's panel: which spells go in which row.",
    onClick = function() module.OpenChooser() end },
  { type = "action", label = "Move them (Edit Mode)", width = 200, icon = "general",
    desc = "Position, icon size and row length are Edit Mode settings.",
    onClick = function() module.OpenEditMode() end },

  { type = "heading", label = "Look", icon = "general" },
  { type = "checkbox", key = "restyle", label = "Restyle the icons and bars (off: only the combat fade)", reload = true },
  { type = "checkbox", key = "crop", label = "Square icons (no round mask or ring)", reload = true },
  { type = "checkbox", key = "showBorder", label = "Thin border around each icon", reload = true },
  { type = "stepper", slider = true, key = "outOfCombatAlpha", label = "Out of combat",
    desc = "How solid the viewers are when you're not fighting. In combat they're always fully shown.",
    min = 0, max = 1, step = 0.05, format = Percent },
}
