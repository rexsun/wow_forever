local _, ns = ...

-- Minimap. Square, flat, with the buttons around it squared to match, and the
-- player's coordinates under it in neon blue.
--
-- Three switches, and each one can stand alone: the map itself, the icons
-- around it, and the coordinates. Turn the map off and the coordinates stay,
-- on their own, wherever you dragged them. Turn those off too and nothing is
-- left -- which is a perfectly good way to play.

local module = ns.RegisterModule({
  name = "Minimap",
  title = "Minimap",
})

module.defaults = {
  square = true,
  size = 216,          -- a fifth larger than Blizzard's
  squareIcons = true,
  showMinimap = true,
  showCoords = true,
  coordSize = 22,
  hideNativeCoords = true,
  iconLayout = "horizontal",   -- horizontal | vertical | grid
  iconsPerRow = 4,             -- only used by "grid"
  iconSize = 26,
  hiddenButtons = {},  -- name -> true, from /fui hide
  showZone = true,
  hideZoneText = true,   -- ForeverUI draws its own, under the button line
  header = true,         -- the strip over the map: zone name, tracking, zoom
  hideDayNight = true,   -- Blizzard's sun-and-moon disc, which peeked out behind the strip
  showDifficulty = true, -- our own "5 / Dungeon" box, movable; Blizzard's flag sat behind the clock
}

module.options = {
  { type = "heading", label = "Minimap" },
  { type = "checkbox", key = "showMinimap", label = "Show the minimap", reload = true },
  { type = "checkbox", key = "square", label = "Square, not round", reload = true },
  { type = "stepper", key = "size", label = "Size", min = 100, max = 320, step = 10 },
  { type = "checkbox", key = "squareIcons", label = "Square the buttons, in a bar of their own", reload = true },
  { type = "stepper", key = "iconSize", label = "Button size", min = 16, max = 48, step = 2 },
  { type = "cycler", key = "iconLayout", label = "Button layout",
    choices = function()
      return {
        { label = "Horizontal", value = "horizontal" },
        { label = "Vertical", value = "vertical" },
        { label = "Grid", value = "grid" },
      }
    end },
  { type = "stepper", key = "iconsPerRow", label = "Buttons per row (grid)", min = 1, max = 12, step = 1 },
  { type = "checkbox", key = "hideZoneText", label = "Hide Blizzard's floating zone name" },
  { type = "checkbox", key = "hideDayNight", label = "Hide the day/night indicator (the sun and moon)", reload = true },
  { type = "checkbox", key = "showDifficulty", reload = true,
    label = "Dungeon size (5 player, 10 player...) in a box you can move",
    desc = "In place of Blizzard's flag, which sat behind the clock. Move it with /fui move." },
  { type = "checkbox", key = "showZone", label = "Show the zone under the buttons" },
  { type = "checkbox", key = "header", label = "Zone name, tracking and zoom in a strip over the map" },

  { type = "heading", label = "Coordinates" },
  { type = "checkbox", key = "showCoords", label = "Show your coordinates" },
  { type = "stepper", key = "coordSize", label = "Coordinate size", min = 10, max = 48, step = 1 },
  { type = "checkbox", key = "hideNativeCoords", label = "Hide the game's own coordinate text" },
  { type = "note", label = "Coordinates stay when the map is off. The map and its coordinates sit where the game puts them; the button bar moves with /fui move." },
}

local Regions, Walk = ns.Skin.Regions, ns.Skin.Walk

local container, coords, ticker, iconBar, zoneText, header, coordBox

-- The coordinates' colour: a very bright blue, readable at a glance on the
-- dark box and on the open map alike.
local squared = {}
local adopted = {}   -- buttons moved out of the map, in the order found
local placing = false
local LayoutIcons    -- defined below; adoption hooks need to call it

local function Settings()
  return ns.db.modules.Minimap
end

---------------------------------------------------------------------------
-- The map itself
---------------------------------------------------------------------------

-- Blizzard's round frame: the ring, the compass tag, the zoom buttons and the
-- backdrop the whole thing sits in. Anything this client doesn't have is
-- skipped rather than raising.
-- Names this module hides as part of the round frame; they must not then be
-- collected into the button bar, where they would hold an empty slot.
local HIDDEN_BY_US = {}

-- Retail furniture this client carries but never configures. Hovering one
-- runs Blizzard's tooltip code on an empty button and throws; they are put
-- away outright, as the round frame is.
local JUNK = { "ExpansionLandingPageMinimapButton", "GarrisonLandingPageMinimapButton" }

local ROUND_ART = {
  "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture",
  "MinimapZoomIn", "MinimapZoomOut", "MinimapBackdrop", "MinimapToggleButton",
  "MiniMapWorldMapButton", "MinimapZoneTextButton", "MiniMapMailBorder",
  "GameTimeFrameBorder", "MiniMapTrackingBorder", "MiniMapLFGFrameBorder",
  "MiniMapBattlefieldBorder", "MiniMapMailIcon",
}

-- Ring artwork on the buttons around the edge, found by what it looks like
-- rather than what it's called.
local RING = {
  "minimap%-trackingborder", "trackingborder", "minimap%-border",
  "ui%-minimap%-border", "%-border$", "border$", "ring",
}

local function HideRoundArt()
  local hidden = 0
  ns.Wipe(HIDDEN_BY_US)
  for _, name in ipairs(JUNK) do
    HIDDEN_BY_US[name] = true
    if _G[name] and ns.Skin.Conceal(_G[name]) then
      hidden = hidden + 1
    end
  end
  for _, name in ipairs(ROUND_ART) do
    HIDDEN_BY_US[name] = true
    local frame = _G[name]
    if frame then
      if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
      end
      if ns.Skin.Conceal(frame) then
        hidden = hidden + 1
      end
    end
  end
  if UIPARENT_MANAGED_FRAME_POSITIONS then
    UIPARENT_MANAGED_FRAME_POSITIONS.MinimapCluster = nil
  end
  -- The day/night indicator (owner, 23 Sept 2026: "we never fully got rid of
  -- the daylight marker ... can we auto turn that off?"). It used to be lined
  -- up as a button, and on this client it came to rest behind the strip over
  -- the map. Put away outright unless you ask for it; newer clients keep it
  -- as a field on the cluster rather than by name.
  --
  -- Forever's own is neither of those ("I still see it", same day): the
  -- sun-and-moon disc is MinimapCluster.DielFrame, an unnamed frame that
  -- Blizzard_Minimap/Camelot/Diel.lua hangs off the cluster at the top of
  -- the map. It isn't protected, so it is simply hidden, and kept hidden if
  -- anything shows it again.
  if Settings().hideDayNight ~= false then
    local cluster = MinimapCluster
    local dayNight = {
      _G.GameTimeFrame,
      cluster and rawget(cluster, "GameTime"),
      cluster and rawget(cluster, "DielFrame"),
    }
    HIDDEN_BY_US.GameTimeFrame = true
    for _, frame in pairs(dayNight) do
      if frame and not rawget(frame, "fuiDayNight") then
        rawset(frame, "fuiDayNight", true)
        if ns.Skin.Conceal(frame) then
          hidden = hidden + 1
        end
        if hooksecurefunc and frame.Show and not (frame.IsProtected and frame:IsProtected()) then
          hooksecurefunc(frame, "Show", function(self)
            if Settings().hideDayNight ~= false then
              ns.Skin.Plain(self, "Hide")
            end
          end)
        end
      end
    end
  end
  -- The newer client keeps the rest as fields on the cluster: the wide top
  -- strip behind the buttons (BorderTop), the tracking sun, the zoom pair.
  -- Faded and made click-through rather than hidden: they are children of
  -- an Edit Mode system, and their own Hide is the tainting kind.
  local function Fade(piece)
    if type(piece) == "table" and piece.SetAlpha then
      piece:SetAlpha(0)
      if piece.EnableMouse then pcall(piece.EnableMouse, piece, false) end
      hidden = hidden + 1
    end
  end
  if MinimapCluster then
    for _, key in ipairs({ "BorderTop", "Tracking" }) do
      Fade(rawget(MinimapCluster, key))
    end
    -- Not faded -- its text is Blizzard's zone name, which the option above
    -- shows or hides -- but it stops taking clicks: it is anchored to the
    -- strip we faded, and an unseen button that opens the world map is a
    -- trap wherever it ends up. The header's zone line opens the map.
    local zoneButton = rawget(MinimapCluster, "ZoneTextButton")
    if type(zoneButton) == "table" and zoneButton.EnableMouse then
      pcall(zoneButton.EnableMouse, zoneButton, false)
    end
  end
  if Minimap then
    for _, key in ipairs({ "ZoomIn", "ZoomOut" }) do
      Fade(rawget(Minimap, key))
    end
  end
  -- Blizzard's dungeon-size flag hangs off the cluster and ended up behind
  -- our clock (owner, 25 Sept 2026: "we need to be able to move it
  -- around"). Moving it would taint Edit Mode like the rest of the cluster,
  -- so it is faded and ours - a frame of our own, on a mover - says the same.
  if MinimapCluster and Settings().showDifficulty ~= false then
    Fade(rawget(MinimapCluster, "InstanceDifficulty"))
  end
  module.hiddenArt = hidden
  return hidden
end
module.HideRoundArt = HideRoundArt

-- Blizzard's tracking menu -- Find Herbs, Find Minerals, the townsfolk --
-- opened from our strip. On Forever the game's tracking button is a
-- DropdownButton: it opens on mouse-down and has no OnClick, so "clicking"
-- it did nothing at all (owner, 23 Sept 2026: "there is no way on this map
-- to hunt for herbs or mining nodes?"). Its menu is built by a generator it
-- keeps on itself; hand that to a context menu at our button, so the menu
-- opens where you clicked rather than at the faded button it belongs to.
function module.OpenTracking(owner)
  local holder = MinimapCluster and rawget(MinimapCluster, "Tracking")
  local button = (holder and rawget(holder, "Button"))
    or _G.MiniMapTrackingButton or _G.MiniMapTracking
  local generator = button and rawget(button, "menuGenerator")
  if generator and MenuUtil and MenuUtil.CreateContextMenu then
    local ok = pcall(MenuUtil.CreateContextMenu, owner or button, generator)
    if ok then
      return "menu"
    end
  end
  if button and button.OpenMenu then
    if pcall(button.OpenMenu, button) then
      return "dropdown"
    end
  end
  -- The old clients: a plain button with a click, or a dropdown of its own.
  local click = button and button.GetScript and button:GetScript("OnClick")
  if click and pcall(click, button, "LeftButton") then
    return "click"
  end
  ns.Print("no tracking menu on this client.")
  return nil
end

-- A square mask makes the map itself square; the round border art above is
-- what makes it look round, so both are needed.
local function SquareMap()
  if not Minimap then
    return false
  end
  local settings = Settings()
  if settings.square and Minimap.SetMaskTexture then
    Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
  elseif Minimap.SetMaskTexture then
    Minimap:SetMaskTexture("Textures\\MinimapMask")
  end
  Minimap:SetSize(settings.size, settings.size)
  return true
end
module.SquareMap = SquareMap

---------------------------------------------------------------------------
-- The buttons move out of the map
---------------------------------------------------------------------------
-- The clock: first in a column (the top), last in a row (the corner).
local FIRST = { TimeManagerClockButton = true }

-- The zone name is a Button, but it is a label: dropping it into a row of
-- 26-pixel squares is how "Sen'jin Village" ends up sitting across the middle
-- of the bar. The clock is text too, so it gets a slot wide enough to read.
local NOT_A_BUTTON = {
  MinimapZoneTextButton = true,
  MinimapZoneText = true,
  MinimapToggleButton = true,
}


local WIDE = { TimeManagerClockButton = true }



-- A bar of its own, beside the map and dragged separately, so the buttons
-- stop sitting on top of the thing you are trying to read.
local function AdoptButton(button)
  if not button or adopted[button] then
    return false
  end
  adopted[button] = true
  adopted[#adopted + 1] = button
  button.fuiOrder = #adopted
  if button.SetParent then
    button:SetParent(iconBar)
  end
  button.fuiInBar = true

  -- They put themselves back where the game wants them otherwise; the same
  -- thing the quest tracker does. And when one appears or goes away, the
  -- others close up around it. Hooked here, at adoption: a hidden button
  -- never enters the layout loop, so it must not be the loop that hooks it.
  if hooksecurefunc and not rawget(button, "fuiHeld") then
    button.fuiHeld = true
    hooksecurefunc(button, "SetPoint", function()
      if not placing then
        LayoutIcons()
      end
    end)
    if button.HookScript then
      button:HookScript("OnShow", function() if not placing then LayoutIcons() end end)
      button:HookScript("OnHide", function() if not placing then LayoutIcons() end end)
    end
  end
  return true
end

-- A button someone has taken with /fui grab is no longer the bar's to place.
function module.Release(button)
  if not adopted[button] then
    return false
  end
  adopted[button] = nil
  for index, held in ipairs(adopted) do
    if held == button then
      table.remove(adopted, index)
      break
    end
  end
  button.fuiInBar = nil
  button.fuiReleased = true
  if iconBar then
    LayoutIcons()
  end
  return true
end

function LayoutIcons()
  if placing then
    return
  end
  local settings = Settings()
  local size = settings.iconSize
  -- A row, a column, or a grid of the width you set.
  local layout = settings.iconLayout or "horizontal"
  local perRow  -- settled below, once we know how many are showing
  local gap = 4
  placing = true

  -- Order first, then measure: the widths are kept by position, and the
  -- clock's double-width slot has to stay with the clock after sorting.
  local clockFirst = layout == "vertical"
  table.sort(adopted, function(a, b)
    local aName = (a.GetName and a:GetName()) or ""
    local bName = (b.GetName and b:GetName()) or ""
    local aClock = FIRST[aName] and 1 or 0
    local bClock = FIRST[bName] and 1 or 0
    if aClock ~= bClock then
      if clockFirst then
        return aClock > bClock
      end
      return aClock < bClock
    end
    return (a.fuiOrder or 0) < (b.fuiOrder or 0)
  end)

  -- Only what is showing takes a slot. Blizzard hides a button when it has
  -- nothing to say -- the mailbox with no mail -- and forcing it up either
  -- shows an empty square or, on one of the retail leftovers, runs tooltip
  -- code on a button that was never set up and throws.
  -- And a button with no picture on it -- the mail indicator with nothing
  -- in the box, a placeholder -- would be a blank square in the row; no slot.
  local function Painted(region)
    if region.GetObjectType and region:GetObjectType() == "FontString" then
      local ok, text = pcall(region.GetText, region)
      return ok and text ~= nil and text ~= ""
    end
    local ok, tex = pcall(function() return region:GetTexture() end)
    if ok and tex ~= nil and tex ~= "" then return true end
    local ok2, atlas = pcall(function() return region.GetAtlas and region:GetAtlas() end)
    return ok2 and atlas ~= nil and atlas ~= ""
  end
  local function HasSomethingToShow(button)
    -- Its own regions only: our panel fill and edges don't count as a picture.
    local ours = { [rawget(button, "bg") or false] = true }
    for _, edge in ipairs(rawget(button, "borderEdges") or {}) do ours[edge] = true end
    for _, region in ipairs(Regions(button)) do
      if not ours[region] and (not region.IsShown or region:IsShown()) and Painted(region) then
        return true
      end
    end
    return (button.GetNumChildren and button:GetNumChildren() or 0) > 0 -- something drawn by a child
  end
  local showing = {}
  for _, button in ipairs(adopted) do
    if (not button.IsShown or button:IsShown()) and HasSomethingToShow(button) then
      showing[#showing + 1] = button
      if button.SetAlpha then button:SetAlpha(1) end
    elseif button.SetAlpha then
      -- A shown button with nothing on it still draws its dark square at
      -- its last slot; faded, it doesn't. And it stops taking clicks: left
      -- at its last slot, an unseen button catches the clicks meant for
      -- whatever is laid out there now. It gets the mouse back the moment
      -- it has something to show (the loop below).
      button:SetAlpha(0)
      if button.EnableMouse and not (InCombatLockdown() and button.IsProtected and button:IsProtected()) then
        pcall(button.EnableMouse, button, false)
      end
    end
  end

  -- How wide each button wants to be. The clock is text, so it needs more
  -- room than an icon does.
  local slots = {}
  local widestSlot = size
  for index, button in ipairs(showing) do
    local name = (button.GetName and button:GetName()) or ""
    slots[index] = WIDE[name] and size * 2 or size
    widestSlot = math.max(widestSlot, slots[index])
  end

  -- A single column is a line, and a line looks wrong if its items are
  -- different widths and hung off the left. So every slot in a column is the
  -- same width, and each button is centred in it.
  local count = #showing > 0 and #showing or 1
  if layout == "vertical" then
    perRow = 1
  elseif layout == "grid" then
    perRow = math.max(1, math.min(settings.iconsPerRow or 4, count))
  else
    perRow = count
  end
  local column1 = perRow == 1
  local x, row, column = 0, 0, 0
  local widest = 0
  for index, button in ipairs(showing) do
    local slot = column1 and widestSlot or slots[index]
    if column >= perRow then
      column, row, x = 0, row + 1, 0
    end
    button:SetSize(slots[index], size)
    -- Re-asserted every time, not just when it was taken: whatever else has
    -- happened to it since, a button in the bar has to still take a click.
    if button.EnableMouse then
      button:EnableMouse(true)
    end
    button:ClearAllPoints()
    local offset = column1 and ((slot - slots[index]) / 2) or 0
    button:SetPoint("TOPLEFT", iconBar, "TOPLEFT", x + offset, -row * (size + gap))
    x = x + slot + gap
    widest = math.max(widest, x - gap)
    column = column + 1

  end
  placing = false
  local rows = row + 1
  local width = math.max(widest, size)   -- in a column that is the widest slot
  local height = rows * size + (rows - 1) * gap
  iconBar:SetSize(width, height)
  iconBar:SetShown(#showing > 0 and settings.squareIcons)
  module.shownButtons = showing
  ns.UpdateMoverSize("minimapIcons", width, height)
  return width, height
end
module.LayoutIcons = LayoutIcons
module.adoptedButtons = adopted

---------------------------------------------------------------------------
-- The buttons around it
---------------------------------------------------------------------------

-- One button: the ring comes off, the icon is stretched over the whole
-- square with its own border cropped, and it gets the same one-pixel frame
-- as everything else.
local function SquareButton(button)
  if not button or squared[button] then
    return false
  end
  squared[button] = true

  -- A ring is either named like one or simply bigger than the button it sits
  -- on -- Blizzard's are 54 pixels of artwork around a 32 pixel icon. Matching
  -- the overhang catches the ones whose names we'd never have guessed.
  local width = (button.GetWidth and button:GetWidth()) or 0
  local icon
  for _, region in ipairs(Regions(button)) do
    if region.GetObjectType and region:GetObjectType() == "Texture" then
      local regionWidth = (region.GetWidth and region:GetWidth()) or 0
      local overhangs = width > 0 and regionWidth > width * 1.1
      if ns.Skin.TextureMatches(region, RING) or overhangs then
        if region.SetAlpha then
          region:SetAlpha(0)
        end
      elseif not icon then
        icon = region
      end
    end
  end
  -- LibDBIcon's dark round background is created before its icon, so the
  -- first texture found is the wrong one; its .icon is the picture.
  local own = rawget(button, "icon")
  if own and own.GetObjectType and own:GetObjectType() == "Texture" then
    icon = own
  end

  ns.Skin.Panel(button, { color = { 0, 0, 0, 1 }, square = true })
  if icon and icon.SetTexCoord then
    local px = ns.Media.Pixel()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
  end
  button.fuiIcon = icon
  return true
end
module.SquareButton = SquareButton

-- Buttons hang off several different frames depending on the client and on
-- which addon put them there, so everything under the minimap and its cluster
-- is walked rather than only the map's own children.
local ROOTS = { "Minimap", "MinimapCluster", "MinimapBackdrop" }

local NAMED = {
  "GameTimeFrame", "MiniMapTracking", "MiniMapTrackingFrame", "MiniMapMailFrame",
  "MiniMapLFGFrame", "MiniMapBattlefieldFrame", "MiniMapWorldMapButton",
  "TimeManagerClockButton", "MinimapZoneTextButton",
}

local function IsButton(frame)
  local kind = frame and frame.GetObjectType and frame:GetObjectType()
  return kind == "Button" or kind == "CheckButton"
end

local function SquareIcons()
  if not Settings().squareIcons then
    return 0
  end
  local count = 0
  local function take(frame)
    if not IsButton(frame) or frame == iconBar or rawget(frame, "fuiInBar")
      or rawget(frame, "fuiReleased") then
      return
    end
    -- The strip over the map has its own zoom and tracking (the header);
    -- Blizzard's aren't lined up a second time.
    if Minimap and (frame == rawget(Minimap, "ZoomIn") or frame == rawget(Minimap, "ZoomOut")) then
      return
    end
    local tracking = MinimapCluster and rawget(MinimapCluster, "Tracking")
    if tracking and (frame == tracking or frame == rawget(tracking, "Button")) then
      return
    end
    -- The zone name, which on Forever has no name of its own: a label, like
    -- MinimapZoneTextButton below, and its click opens the world map. Taken
    -- into the bar with its text hidden it sat there invisible over the
    -- ForeverUI button, so clicking the button opened the map (owner, 23
    -- Sept 2026).
    if MinimapCluster and frame == rawget(MinimapCluster, "ZoneTextButton") then
      return
    end
    local name = (frame.GetName and frame:GetName()) or ""
    if NOT_A_BUTTON[name] or rawget(frame, "fuiDayNight") then
      return
    end
    -- Buttons we deliberately put away don't get a slot; an empty slot in a
    -- vertical line reads as a hole in it.
    if name ~= "" and HIDDEN_BY_US[name] then
      return
    end
    if name ~= "" and Settings().hiddenButtons[name] then
      if frame.Hide then
        frame:Hide()
      end
      return
    end
    if SquareButton(frame) then
      count = count + 1
    end
    AdoptButton(frame)
  end

  for _, root in ipairs(ROOTS) do
    if _G[root] then
      Walk(_G[root], function(frame)
        if frame ~= _G[root] then
          take(frame)
        end
      end)
    end
  end
  for _, name in ipairs(NAMED) do
    take(_G[name])
  end

  module.squaredCount = count
  return count
end
module.SquareIcons = SquareIcons

-- Buttons created after this module ran -- ForeverUI's own is one, it is made
-- after the modules start -- are picked up by calling this again.
function module.GatherButtons()
  if not iconBar then
    return 0
  end
  local count = SquareIcons()
  LayoutIcons()
  return count
end

---------------------------------------------------------------------------
-- Getting rid of one you don't want
---------------------------------------------------------------------------
--
-- Rather than keeping a list of every button every addon might add, you point
-- at the one you don't want and say so. The name is remembered per profile,
-- so it stays gone.

-- The thing under the cursor is usually a texture on a button rather than the
-- button, so walk up. But only as far as a button: keep climbing past one and
-- you reach the bar itself, and hide every button at once.
local function NamedAncestor(frame)
  local depth = 0
  while frame and depth < 6 do
    if frame == UIParent then
      return nil, nil   -- climbed out of the interface; nothing was meant
    end
    local name = frame.GetName and frame:GetName()
    if name and name ~= "" and (adopted[frame] or IsButton(frame)) then
      return frame, name
    end
    frame = frame.GetParent and frame:GetParent()
    depth = depth + 1
  end
  return nil, nil
end

function module.HideUnderCursor()
  local bars = ns.GetModule("ActionBars")
  local focus = bars and bars.MouseFocus and bars.MouseFocus()
    or (GetMouseFocus and GetMouseFocus())

  -- In move mode the handles are above everything, so that is what the cursor
  -- finds -- and saying "point at a button" would be unhelpful nonsense.
  local above, depth = focus, 0
  while above and depth < 6 do
    local aboveName = above.GetName and above:GetName()
    if aboveName and aboveName:find("^ForeverUIMover") then
      ns.Print("that's a drag handle - finish moving first with /fui move.")
      return nil
    end
    above = above.GetParent and above:GetParent()
    depth = depth + 1
  end

  local frame, name = NamedAncestor(focus)
  if not frame or not name then
    ns.Print("point at the button you want gone, then run this again.")
    return nil
  end
  Settings().hiddenButtons[name] = true
  if frame.Hide then
    frame:Hide()
  end
  for index, button in ipairs(adopted) do
    if button == frame then
      table.remove(adopted, index)
      break
    end
  end
  adopted[frame] = nil
  frame.fuiInBar = nil
  LayoutIcons()
  ns.Print(("|cff4dc3ff%s|r hidden. /fui hide reset brings them all back."):format(name))
  return name
end

function module.ShowHiddenButtons()
  local names = {}
  for name in pairs(Settings().hiddenButtons) do
    names[#names + 1] = name
    if _G[name] and _G[name].Show then
      _G[name]:Show()
    end
  end
  ns.Wipe(Settings().hiddenButtons)
  module.GatherButtons()
  ns.Print(("%d button%s back."):format(#names, #names == 1 and "" or "s"))
  return #names
end

---------------------------------------------------------------------------
-- Where you are
---------------------------------------------------------------------------

-- Something on this client already prints coordinates in plain white, right
-- where ours go. It has no name we can rely on, so it is found by what it
-- says: a pair of one-decimal numbers, and nothing else.
local COORD_PATTERN = "^%s*%d+%.%d+%s*[,/]?%s*%d+%.%d+%s*$"

local natives = {}   -- { region, holder } for each of the game's own readouts

-- Is this frame part of the minimap? Only then may its whole frame be hidden.
-- Hiding a holder that isn't the minimap's took another addon's window down
-- with it once -- its version label ("0.14.1") reads as a pair of
-- coordinates -- so a holder outside the map is never hidden, only its text
-- is blanked.
local function WithinMinimap(frame)
  local depth = 0
  while frame and depth < 12 do
    if frame == MinimapCluster or frame == Minimap or frame == MinimapBackdrop
      or frame == container then
      return true
    end
    frame = frame.GetParent and frame:GetParent()
    depth = depth + 1
  end
  return false
end
module.WithinMinimap = WithinMinimap

-- It rewrites itself as you walk, so blanking it once doesn't hold. Whatever
-- is found is remembered and put back down on every tick: the text is
-- blanked, and -- only when the frame it hangs off is the minimap's own --
-- that frame is hidden too. Anything else, text only.
local function SilenceNatives()
  local silenced = 0
  for _, native in ipairs(natives) do
    local region, holder = native.region, native.holder
    if region.SetText then
      local text = ns.Skin.Text(region)
      if text and text ~= "" then
        silenced = silenced + 1
      end
      pcall(region.SetText, region, "")
    end
    if region.Hide then
      pcall(region.Hide, region)
    end
    if holder and WithinMinimap(holder)
      and holder ~= MinimapCluster and holder ~= Minimap
      and holder ~= MinimapBackdrop and holder ~= container
      and not ns.Skin.Forbidden(holder) and holder.Hide then
      pcall(holder.Hide, holder)
    end
  end
  return silenced
end
module.SilenceNatives = SilenceNatives
module.natives = natives

-- Every piece of text on the whole interface that reads like coordinates, or
-- that can't be read at all, with the chain of frames it hangs off. For when
-- the sweep above isn't catching whatever draws them on this build: run it,
-- read the chain, and hide the right thing by name.
function module.FindCoordinateText()
  local found = {}
  local seen = {}
  local function chain(frame)
    local names, depth = {}, 0
    while frame and depth < 10 do
      local name = frame.GetName and frame:GetName()
      names[#names + 1] = name or "(unnamed)"
      frame = frame.GetParent and frame:GetParent()
      depth = depth + 1
    end
    return table.concat(names, " < ")
  end
  local function visit(frame)
    for _, region in ipairs(Regions(frame)) do
      if region ~= coords and not seen[region]
        and region.GetObjectType and region:GetObjectType() == "FontString" then
        seen[region] = true
        local ok, raw = pcall(region.GetText, region)
        local text = ns.Skin.Text(region)
        if text and text:find(COORD_PATTERN) then
          found[#found + 1] = { kind = "coordinates", text = text, chain = chain(frame),
            shown = region.IsShown and region:IsShown() }
        elseif ok and raw ~= nil and text == nil then
          found[#found + 1] = { kind = "unreadable", text = "(secret)", chain = chain(frame),
            shown = region.IsShown and region:IsShown() }
        end
      end
    end
  end
  Walk(UIParent, visit, -2)   -- two levels deeper than the usual cap
  for _, root in ipairs({ Minimap, MinimapCluster, container }) do
    Walk(root, visit, -2)
  end
  module.coordinateText = found
  ns.Print(("%d piece%s of text that read like coordinates or can't be read:"):format(
    #found, #found == 1 and "" or "s"))
  for _, hit in ipairs(found) do
    ns.Print(("  %s %s [%s] in %s"):format(
      hit.shown and "|cff4dc3ffshown|r" or "|cff888888hidden|r", hit.kind, hit.text, hit.chain))
  end
  return found
end

local function HideNativeCoords()
  if not Settings().hideNativeCoords then
    return 0
  end
  local hidden = 0
  -- Only the minimap's own subtree is swept. The readout the game draws
  -- lives with the map; walking the whole interface for anything that reads
  -- like a coordinate pair is what caught other addons' version strings --
  -- "0.14.1" reads as a coordinate pair -- and hid their windows. A native
  -- readout stays remembered once found: it blanks to nothing between the
  -- moments it rewrites itself, so it can't be re-found by its text, and
  -- clearing the list would lose it. Since only the map is swept, nothing
  -- foreign ever gets into the list to need clearing.
  local function sweep(root)
    Walk(root, function(frame)
      for _, region in ipairs(Regions(frame)) do
        if region ~= coords and region.GetObjectType and region:GetObjectType() == "FontString" then
          -- Read through the guard: this text can be a secret string, and
          -- matching on one raises.
          local text = ns.Skin.Text(region)   -- safe lowercase, or nothing
          if text and text:find(COORD_PATTERN) then
            if not natives[region] then
              natives[region] = true
              natives[#natives + 1] = { region = region, holder = frame }
            end
            hidden = hidden + 1
          end
        end
      end
    end)
  end
  sweep(Minimap)
  sweep(MinimapCluster)
  sweep(MinimapBackdrop)
  sweep(container)   -- anything that ended up in our own panel counts too
  SilenceNatives()
  module.hiddenNativeCoords = hidden
  return hidden
end
module.HideNativeCoords = HideNativeCoords

-- Nil when the game won't say -- instances and the loading screen both do
-- this, and it is not an error.
local function Position()
  local ok, x, y = pcall(function()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
      local map = C_Map.GetBestMapForUnit("player")
      local point = map and C_Map.GetPlayerMapPosition(map, "player")
      if point and point.GetXY then
        return point:GetXY()
      end
      return nil
    end
    if GetPlayerMapPosition then
      return GetPlayerMapPosition("player")
    end
    return nil
  end)
  if not ok or not x or not y or (x == 0 and y == 0) then
    return nil
  end
  return x * 100, y * 100
end
module.Position = Position

local function UpdateZone()
  if not zoneText then
    return ""
  end
  local settings = Settings()
  if not settings.showZone then
    zoneText:SetText("")
    zoneText:Hide()
    return ""
  end
  local ok, name = pcall(function()
    return (GetMinimapZoneText and GetMinimapZoneText())
      or (GetZoneText and GetZoneText()) or ""
  end)
  name = (ok and type(name) == "string") and name or ""
  zoneText:SetText(name)
  zoneText:SetShown(name ~= "" and Settings().header == false)
  if header and header.zone then
    header.zone.text:SetText(name)
  end
  module.zone = name
  return name
end
module.UpdateZone = UpdateZone

local function UpdateCoords()
  if not coords then
    return ""
  end
  if not Settings().showCoords then
    coords:SetText("")
    coords:Hide()
    return ""
  end
  local x, y = Position()
  local text = x and ("%.1f, %.1f"):format(x, y) or ""
  coords:SetText(text)
  coords:SetShown(text ~= "")
  if coordBox and coordBox:IsShown() then
    local w = coords.GetStringWidth and coords:GetStringWidth() or 60
    local h = coords.GetStringHeight and coords:GetStringHeight() or 12
    coordBox:SetSize((w or 60) + 12, (h or 12) + 8)
  end
  module.lastCoords = text
  return text
end
module.UpdateCoords = UpdateCoords

---------------------------------------------------------------------------
-- Putting it together
---------------------------------------------------------------------------

local function Layout()
  local settings = Settings()
  local size = settings.size
  local showMap = settings.showMinimap

  -- Through the C originals: the cluster is an Edit Mode system and its
  -- own SetShown/Hide are Lua that taints the manager (see Skin.Plain).
  if Minimap then
    ns.Skin.Plain(Minimap, "SetShown", showMap)
  end
  if MinimapCluster then
    ns.Skin.Plain(MinimapCluster, "SetShown", showMap)
  end
  if MinimapZoneText then
    MinimapZoneText:SetShown(showMap and not settings.hideZoneText)
  end

  if zoneText then
    ns.Media.SetFont(zoneText, "dataText")
    ns.Skin.AccentText(zoneText)
  end
  ns.Media.SetFont(coords, "dataText")
  local path, _, outline = ns.Media.Role("dataText")
  coords:SetFont(path, settings.coordSize, outline ~= "" and outline or "OUTLINE")
  ns.Skin.AccentText(coords)

  if header then
    local on = showMap and settings.header ~= false
    header:SetShown(on)
    ns.Media.SetFont(header.zone.text, "general")
    header.zone.text:SetTextColor(1, 1, 1)
    ns.Media.SetFont(header.zone.arrow, "dataText")
  end
  if coordBox then
    -- Into the corner box when the header look is on; under the map otherwise.
    coords:ClearAllPoints()
    if settings.header ~= false and showMap then
      -- The text has to belong to the box, not to the map's container. The
      -- box sits a few levels above the container, so text left on the
      -- container was drawn UNDER the box's dark fill and came out a dim
      -- grey that was hard to read at all.
      coords:SetParent(coordBox)
      coords:SetPoint("BOTTOMLEFT", coordBox, "BOTTOMLEFT", 6, 4)
      coords:SetFont(path, math.max(10, math.floor(settings.coordSize * 0.7)), outline ~= "" and outline or "OUTLINE")
      ns.Skin.AccentText(coords)
      coordBox:Show()
    else
      coords:SetParent(container)
      coords:SetPoint("BOTTOM", container, "BOTTOM", 0, 2)
      coordBox:Hide()
    end
  end

  -- With the map off the panel is just the coordinates, and keeps its handle.
  local width = showMap and size or math.max(80, settings.coordSize * 7)
  local height = showMap and (size + settings.coordSize + 8) or (settings.coordSize + 6)
  container:SetSize(width, height)
  return width, height
end
module.Layout = Layout

local function Build()
  container = CreateFrame("Frame", "ForeverUIMinimap", UIParent)
  container:SetSize(Settings().size, Settings().size)
  container:EnableMouse(false)   -- a holder, not a window

  coords = container:CreateFontString(nil, "OVERLAY")
  coords:SetPoint("BOTTOM", container, "BOTTOM", 0, 2)

  if Minimap then
    -- NEVER reparent or re-anchor the Minimap. It is an Edit Mode system frame
    -- on this client, and moving it taints Edit Mode's layout -- after which the
    -- next layout pass runs the objective tracker's update tainted and dies on
    -- an aura read (GetAuraDataByIndex while tainted by ForeverUI). Same trap as
    -- the quest tracker. So leave the map where Edit Mode puts it (Esc -> Edit
    -- Mode to move it) and wrap our container -- coordinates and border --
    -- around it instead.
    container:ClearAllPoints()
    container:SetPoint("TOP", Minimap, "TOP", 0, 0)
    ns.Skin.Panel(Minimap, { color = { 0, 0, 0, 0 }, square = true })
  end

  -- The strip over the map, as in the owner's mock-up: the zone name on the
  -- left (click it for the world map), and on the right the tracking menu
  -- and the zoom. Our own frame hung on the map -- the map itself is never
  -- moved (Edit Mode owns it).
  if Minimap then
    local ui = ns.Colors.ui
    -- The strip is the top of the map box: it lies over the map's top edge
    -- rather than above it. Edit Mode parks the map hard against the top of
    -- the screen, and a strip stacked above it (with the button bar above
    -- that) ran off the screen; laid over the map, the stack always fits.
    header = CreateFrame("Frame", "ForeverUIMinimapHeader", UIParent)
    header:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
    header:SetHeight(28)
    header:SetFrameStrata("MEDIUM")
    header:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 10)
    ns.Skin.Panel(header, { color = { 0.03, 0.03, 0.05, 0.92 }, borderColor = ui.accent, square = true })

    -- Secure, so clicking it can be handed to Blizzard's own world map
    -- button rather than opening the panel from our Lua and tainting the
    -- panel manager for the session. See ns.Skin.ForwardClick.
    local zone = CreateFrame("Button", nil, header, "SecureActionButtonTemplate")
    zone:SetPoint("LEFT", 8, 0)
    zone:SetPoint("RIGHT", -88, 0)
    zone:SetHeight(28)
    zone.text = zone:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(zone.text, "general") -- a font BEFORE any text: SetText on a bare FontString throws
    zone.text:SetPoint("LEFT", 0, 0)
    zone.text:SetPoint("RIGHT", -14, 0)
    zone.text:SetJustifyH("LEFT")
    if zone.text.SetWordWrap then zone.text:SetWordWrap(false) end -- one line, clipped, never two
    zone.arrow = zone:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(zone.arrow, "dataText")
    zone.arrow:SetPoint("LEFT", zone.text, "RIGHT", 4, 0)
    zone.arrow:SetText("|cff4dc3ffv|r")
    -- Blizzard's zone name opens the map (Skin.OPENERS); a click here is
    -- handed to it. Never ToggleWorldMap from here: see OpenHint.
    ns.Skin.ForwardOpen(zone, "map")
    header.zone = zone

    local function Small(label, tip, onClick)
      local b = CreateFrame("Button", nil, header)
      b:SetSize(24, 22)
      ns.Skin.Button(b)
      b:SetText(label)
      b:SetScript("OnClick", onClick)
      b:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(tip); GameTooltip:Show() end
      end)
      b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      return b
    end
    local zoomIn = Small("+", "Zoom in", function()
      if Minimap.SetZoom and Minimap.GetZoom then pcall(Minimap.SetZoom, Minimap, math.min((Minimap:GetZoomLevels() or 5) - 1, Minimap:GetZoom() + 1)) end
    end)
    zoomIn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    local zoomOut = Small("-", "Zoom out", function()
      if Minimap.SetZoom and Minimap.GetZoom then pcall(Minimap.SetZoom, Minimap, math.max(0, Minimap:GetZoom() - 1)) end
    end)
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -3, 0)
    local tracking = Small("o", "Tracking: herbs, minerals, flight masters...", function(self)
      module.OpenTracking(self)
    end)
    tracking:SetPoint("RIGHT", zoomOut, "LEFT", -3, 0)
    header.tracking, header.zoomIn, header.zoomOut = tracking, zoomIn, zoomOut
    module.header = header

    -- Coordinates in a small dark box in the map's bottom-left corner.
    coordBox = CreateFrame("Frame", nil, container)
    coordBox:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 0, 0)
    coordBox:SetFrameStrata("MEDIUM")
    coordBox:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 5)
    ns.Skin.Panel(coordBox, { color = { 0.03, 0.03, 0.05, 0.85 }, border = false, square = true })
    module.coordBox = coordBox
  end

  iconBar = CreateFrame("Frame", "ForeverUIMinimapIcons", UIParent)
  iconBar:SetSize(26, 26)
  -- Above the map, so a button that ends up over it still gets the click.
  iconBar:SetFrameStrata("MEDIUM")
  iconBar:SetFrameLevel(20)

  -- The zone name, drawn by us and hung under the line rather than left
  -- floating wherever the game put it.
  zoneText = iconBar:CreateFontString(nil, "OVERLAY")
  zoneText:SetPoint("TOP", iconBar, "BOTTOM", 0, -4)
  module.zoneText = zoneText
  module.iconBar = iconBar

  -- No mover for the map itself any more: Edit Mode owns where the minimap
  -- sits (moving it from here taints Edit Mode). Our container just follows it.
  -- The icon bar is our own frame, so it stays movable.
  ns.RegisterMover("minimapIcons", "Minimap buttons", iconBar,
    { "TOPRIGHT", "TOPRIGHT", -8, -8 })
  module.BuildDifficulty()
  module.container, module.coords = container, coords

  -- Coordinates change as you walk; nothing tells you but the clock.
  ticker = CreateFrame("Frame")
  local elapsed, sinceSweep, forceSweep = 0, 0, false
  ticker:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    sinceSweep = sinceSweep + delta
    if elapsed >= 0.2 then
      elapsed = 0
      UpdateCoords()
      UpdateZone()
      SilenceNatives()
      -- The game's readout is empty at login and fills in later, so a sweep
      -- at login finds nothing to match. Sweep briskly until one turns up,
      -- then slowly for good, in case another appears; the tick above holds
      -- down whatever has been found.
      local interval = #natives == 0 and 2 or 15
      if Settings().hideNativeCoords and (forceSweep or sinceSweep >= interval) then
        sinceSweep, forceSweep = 0, false
        HideNativeCoords()
      end
    end
  end)
  module.Resweep = function()
    forceSweep = true
  end
  module.ticker = ticker
end

---------------------------------------------------------------------------
-- Dungeon size: "5" and "Dungeon" in a small box of our own, on a mover
---------------------------------------------------------------------------

local INSTANCE_LABELS = { party = "Dungeon", raid = "Raid", scenario = "Scenario",
  pvp = "Battleground", arena = "Arena" }

-- What to show, or nil outside an instance. Every value through a guard: the
-- name or size may come back hidden, and then only what is plain is shown.
function module.DifficultyText()
  if not GetInstanceInfo then return nil end
  local ok, name, instanceType, _, difficultyName, maxPlayers = pcall(GetInstanceInfo)
  if not ok then return nil end
  instanceType = ns.Secrets.String(instanceType)
  local kind = instanceType and INSTANCE_LABELS[instanceType]
  if not kind then return nil end
  local size = ns.Secrets.Number(maxPlayers)
  return size and size > 0 and tostring(size) or "?", kind,
    ns.Secrets.String(name), ns.Secrets.String(difficultyName)
end

function module.UpdateDifficulty()
  local box = module.difficulty
  if not box then return end
  local size, kind, name, difficultyName = module.DifficultyText()
  if Settings().showDifficulty == false or not size then
    box:Hide()
    return
  end
  box.size:SetText(size)
  box.kind:SetText(kind)
  box.name, box.difficultyName = name, difficultyName
  box:Show()
end

function module.BuildDifficulty()
  if module.difficulty then return end
  local box = CreateFrame("Frame", "ForeverUIInstanceDifficulty", UIParent)
  box:SetSize(64, 36)
  box:SetFrameStrata("MEDIUM")
  ns.Skin.Panel(box, { square = true })
  box.size = box:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(box.size, "dataText")
  box.size:SetPoint("TOP", 0, -3)
  box.size:SetTextColor(1, 0.82, 0.2)
  box.kind = box:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(box.kind, "general")
  box.kind:SetPoint("BOTTOM", 0, 4)
  box.kind:SetTextColor(0.85, 0.85, 0.85)
  box:EnableMouse(true)
  box:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(self.name or self.kind:GetText() or "")
    GameTooltip:AddLine(("%s player %s"):format(self.size:GetText() or "?", (self.kind:GetText() or ""):lower()), 1, 1, 1)
    if self.difficultyName then GameTooltip:AddLine(self.difficultyName, 0.8, 0.8, 0.8) end
    GameTooltip:Show()
  end)
  box:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  box:Hide()
  -- Beside the minimap buttons to start with; /fui move puts it anywhere.
  ns.RegisterMover("instanceDifficulty", "Dungeon size", box, { "TOPRIGHT", "TOPRIGHT", -8, -44 })
  module.difficulty = box
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED",
    "INSTANCE_GROUP_SIZE_CHANGED", "GROUP_ROSTER_UPDATE" }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function() pcall(module.UpdateDifficulty) end)
  module.difficultyWatcher = watcher
end

local function Apply()
  HideRoundArt()
  SquareMap()
  SquareIcons()
  LayoutIcons()
  Layout()
  UpdateZone()
  UpdateCoords()
  pcall(module.UpdateDifficulty)
  -- Last, so it sweeps the finished screen -- and so ours, which is drawn by
  -- now and looks exactly like what it is hunting, has to be exempted.
  HideNativeCoords()
end
module.Apply = Apply

-- Add-ons loaded after ForeverUI (Leatrix, RareScanner, Talents Forever) and
-- those that make their LibDBIcon button at or after login were missed by
-- the one gather at PLAYER_LOGIN and stayed on the map's edge. Gather again
-- whenever a button may have appeared, a moment later, coalesced.
local lateGather
local function GatherSoon()
  if lateGather or not iconBar then return end
  lateGather = true
  local function run()
    lateGather = false
    if module.enabledNow then
      ns.WhenOutOfCombat(module.GatherButtons)
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end

local function WatchForLateButtons()
  if module.lateWatcher then return end
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("ADDON_LOADED")
  watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcher:SetScript("OnEvent", GatherSoon)
  module.lateWatcher = watcher
  local LibStub = rawget(_G, "LibStub")
  local dbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
  if dbIcon and dbIcon.RegisterCallback then
    dbIcon.RegisterCallback(module, "LibDBIcon_IconCreated", GatherSoon)
  end
  -- Some make theirs on a timer after the world is in.
  if C_Timer and C_Timer.After then
    for _, delay in ipairs({ 5, 15 }) do C_Timer.After(delay, GatherSoon) end
  end
end

function module:OnEnable()
  module.enabledNow = true
  ns.WhenOutOfCombat(function()
    if not container then
      Build()
    end
    container:Show()
    Apply()
    WatchForLateButtons()
  end)
end

function module:OnDisable()
  module.enabledNow = false
  if container then
    container:Hide()
  end
  if ticker then
    ticker:SetScript("OnUpdate", nil)
  end
end

module.needsReload = true -- Blizzard's round frame only comes back on a reload

function module:Refresh()
  ns.WhenOutOfCombat(function()
    if not container then
      Build()
    end
    Apply()
  end)
end
