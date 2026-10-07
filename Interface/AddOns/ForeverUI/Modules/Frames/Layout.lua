local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Where the frames live and how they're arranged.
--
-- One party header (you + party1-4) and eight raid headers, one per raid
-- group, all hanging off a drag anchor. Which set is visible is decided by a
-- secure visibility driver ("[group:raid] ..."), so joining or leaving a raid
-- mid-fight swaps them without any blocked calls. A party header left
-- visible inside a raid would show only your subgroup, hence the driver.

local BUTTON_SPACING = 2
local GROUP_GAP = 6
local GROUP_LABEL_H = 12   -- room over each raid group for "Group 3", when labels are on
local NUM_GROUPS = 8

-- Frame size is a setting; Frames.xml's <Size> is only the starting value.
local function W() return ns.db.frameWidth end
local function H() return ns.db.frameHeight end
local function GroupHeight()
  return ns.db.horizontal and H() or (5 * H() + 4 * BUTTON_SPACING)
end
local function GroupWidth()
  return ns.db.horizontal and (5 * W() + 4 * BUTTON_SPACING) or W()
end
local function PreviewOffset() return W() + 16 end -- previews sit to the right of the real frames

-- Pretend party shown while unlocked, so layout and indicators can be judged solo.
local PREVIEW = {
  { name = "Tankadin",   class = "PALADIN", health = 1080, healthMax = 2140, inRange = true,
    incomingMine = 380, incomingOthers = 300,
    hots = { { icon = "Interface\\Icons\\Spell_Holy_Renew", remaining = 9 },
             { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", remaining = 22 } } },
  { name = "Holyfire",   class = "PRIEST",  health = 1190, healthMax = 1190, inRange = true, isTarget = true,
    dispelType = "Magic", dispelIcon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
  { name = "Stabsworth", class = "ROGUE",   health = 410,  healthMax = 1350, inRange = true,
    -- A heal far bigger than the hole it is filling, so the preview shows
    -- what overhealing looks like: amber at the end of the bar.
    dispelType = "Poison", dispelIcon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath", incomingOthers = 1250,
    hots = { { icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", remaining = 2 } } },
  { name = "Pyroblast",  class = "MAGE",    health = 0,    healthMax = 1100, inRange = true, dead = true },
  { name = "Afkhunter",  class = "HUNTER",  health = 1300, healthMax = 1300, inRange = true, offline = true },
}

---------------------------------------------------------------------------
-- One set of frames per role
---------------------------------------------------------------------------
--
-- Everything below was written for a single grid: `anchor` is a file-local,
-- ns.header is the party header, ns.raidHeaders the eight raid groups. Three
-- grids on screen means three of each.
--
-- Rather than rewrite forty-odd functions to take a role, the set is SWAPPED.
-- ns.WithGrid(role, fn) lends the engine that role's settings (ns.WithMode)
-- and that role's frames, runs fn, and puts the previous ones back. Inside
-- fn, every existing line means what it always meant -- it just happens to be
-- pointing at the tank's frames rather than the healer's.
--
-- The cost of getting this wrong is invisible and nasty: build the tank grid
-- while the healer's settings are loaded and you get a tank grid with healer
-- bindings, which looks fine and casts the wrong spell. So the swap is
-- pcall-wrapped at both layers and always restores.

local anchor, previewParty, previewRaid
local CreateHandle, SizeHandle -- defined further down, used by ApplyFrameSize
ns.raidHeaders = {}

local sets = {}
ns.gridSets = sets
ns.activeGrid = nil

local function GridSet(role)
  local set = sets[role]
  if not set then
    set = { role = role, raidHeaders = {} }
    sets[role] = set
  end
  return set
end
ns.GridSet = GridSet

-- Put the frames the file-locals point at back into the set they belong to.
local function StoreGrid()
  local set = ns.activeGrid and sets[ns.activeGrid]
  if not set then
    return
  end
  set.moveHandle = ns.moveHandle
  set.anchor, set.previewParty, set.previewRaid = anchor, previewParty, previewRaid
  -- Tie the handle to this grid here rather than where it is built: the
  -- handle is created from inside SetLocked, and which anchor was current at
  -- that moment is not something this should depend on.
  if set.moveHandle then
    set.moveHandle.gridRole = set.role
    set.moveHandle.movesGrid = set.anchor
  end
  if set.anchor then
    set.anchor.gridRole = set.role
    set.anchor.movesGrid = set.anchor
  end
  set.header, set.raidHeaders, set.petHeader = ns.header, ns.raidHeaders, ns.petHeader
  -- The target frame and the focus frames are NOT per grid. There is one of
  -- you and one of your target, however many grids are watching the party.
end

-- Point the file-locals at this role's frames.
local function UseGrid(role)
  local set = GridSet(role)
  ns.activeGrid = role
  anchor, previewParty, previewRaid = set.anchor, set.previewParty, set.previewRaid
  ns.anchor, ns.moveHandle = set.anchor, set.moveHandle
  ns.header, ns.raidHeaders, ns.petHeader = set.header, set.raidHeaders or {}, set.petHeader
end

-- The one entry point. Settings AND frames, together -- they are never
-- allowed to disagree about which grid is being worked on.
function ns.WithGrid(role, fn)
  local previousGrid = ns.activeGrid
  StoreGrid()
  UseGrid(role)
  local ok = ns.WithMode(role, fn)
  StoreGrid()
  if previousGrid then
    UseGrid(previousGrid)
  end
  return ok
end

-- Party header first, then raid groups 1-8 (only those that exist yet).
function ns.AllHeaders()
  local list = {}
  if ns.header then
    list[1] = ns.header
  end
  for _, header in ipairs(ns.raidHeaders) do
    list[#list + 1] = header
  end
  if ns.petHeader then
    list[#list + 1] = ns.petHeader
  end
  return list
end

-- Top-left of raid group `index` relative to the anchor's bottom-left.
-- perRow counts groups across, whichever way a group itself runs.
local function LabelHeight()
  return ns.db.groupLabels and GROUP_LABEL_H or 0
end
ns.GroupLabelHeight = LabelHeight

function ns.GroupOffset(index, perRow)
  local column = (index - 1) % perRow
  local row = math.floor((index - 1) / perRow)
  local label = LabelHeight()
  return column * (GroupWidth() + GROUP_GAP), -BUTTON_SPACING - label - row * (GroupHeight() + GROUP_GAP + label)
end

---------------------------------------------------------------------------
-- Anchor, position, scale
---------------------------------------------------------------------------

-- Put THIS grid where this grid belongs.
--
-- It used to read ns.db.position -- the position of the role being
-- configured -- and apply it to whatever `anchor` happened to point at. Those
-- are the same frame only when one grid exists. Called from outside a grid
-- swap (a profile load, a settings apply) it moved one grid to another's
-- spot, which is the layout landing wrong until the next reload put it back.
function ns.ApplyPosition()
  if not anchor then
    return
  end
  local role = ns.activeGrid or ns.GetMode()
  local p = (role == (ns.db.mode or "healer")) and ns.db.position
    or ((ns.db.modes or {})[role] or {}).position
    or ns.db.position
  if not p then
    return
  end
  anchor:ClearAllPoints()
  anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- Every grid that is up, each from its own saved spot. What a profile load or
-- a settings apply should call, rather than moving only the active one.
function ns.ApplyAllPositions()
  for _, role in ipairs(ns.ShownGrids()) do
    ns.WithGrid(role, ns.ApplyPosition)
  end
end

function ns.ResetPosition()
  ns.db.position = ns.CopyTable(ns.DEFAULTS.position)
  ns.ApplyPosition()
end

---------------------------------------------------------------------------
-- Telling one grid from another
---------------------------------------------------------------------------
--
-- Three grids on the same five people are identical until you label them:
-- same names, same bars, same size. So each gets a border and a title strip
-- in its role's colour -- the glyph, the name, which group it is showing, and
-- a collapse dash.
--
-- Drawn from plain textures rather than a backdrop: backdrops need
-- BackdropTemplate on modern clients and not on old ones, and a texture works
-- on both. Parented to UIParent and kept BEHIND the frames, so it never eats
-- a click meant for a unit.
local function CreateChrome(role)
  local look = ns.ROLE_CHROME[role] or ns.ROLE_CHROME.healer
  local chrome = CreateFrame("Frame", "ForeverUIFramesChrome" .. role, UIParent)
  chrome.role = role
  chrome:SetFrameStrata("BACKGROUND")
  chrome:EnableMouse(false)

  chrome.bg = chrome:CreateTexture(nil, "BACKGROUND")
  chrome.bg:SetAllPoints()
  chrome.bg:SetColorTexture(0.05, 0.05, 0.07, 0.80)

  chrome.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = chrome:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(look.color[1], look.color[2], look.color[3], 1)
    if side == "TOP" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(2)
    elseif side == "BOTTOM" then
      tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(2)
    elseif side == "LEFT" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT"); tex:SetWidth(2)
    else
      tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetWidth(2)
    end
    chrome.edges[#chrome.edges + 1] = tex
  end

  local strip = CreateFrame("Frame", nil, chrome)
  strip:SetPoint("TOPLEFT", 2, -2)
  strip:SetPoint("TOPRIGHT", -2, -2)
  strip:SetHeight(22)
  strip.bg = strip:CreateTexture(nil, "BACKGROUND")
  strip.bg:SetAllPoints()
  strip.bg:SetColorTexture(0.10, 0.10, 0.13, 1)
  chrome.strip = strip

  if FUI.Skin and FUI.Skin.Icon then
    strip.glyph = FUI.Skin.Icon(strip, look.icon, 14, look.color, "OVERLAY")
    strip.glyph:SetPoint("LEFT", 6, 0)
  end

  strip.label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  strip.label:SetPoint("LEFT", strip.glyph or strip, strip.glyph and "RIGHT" or "LEFT",
    strip.glyph and 6 or 8, 0)
  strip.label:SetText(look.label)
  strip.label:SetTextColor(look.color[1], look.color[2], look.color[3])


  strip.collapse = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  strip.collapse:SetPoint("RIGHT", -8, 0)
  strip.collapse:SetText("-")
  strip.collapse:SetTextColor(0.7, 0.7, 0.75)

  return chrome
end

-- Wrap the chrome around whatever this grid is currently showing. Called
-- after the headers are laid out, because the extent is theirs, not ours.
-- What each grid actually has, for when the screen disagrees with the
-- settings. Reading this beats guessing from a screenshot.
function ns.GridStatus()
  local lines = {}
  for _, role in ipairs(ns.ROLES) do
    local set = sets[role]
    local pos = (ns.db.modes and ns.db.modes[role] and ns.db.modes[role].position)
      or (role == ns.GetMode() and ns.db.position) or nil
    local header = set and set.header
    local rShown = 0
    for _, h in ipairs((set and set.raidHeaders) or {}) do
      if h:IsShown() then rShown = rShown + 1 end
    end
    lines[#lines + 1] = ("%s: %s anchor=%s(%s) party=%s(%s) raidShown=%d at %s"):format(
      role,
      ns.IsGridShown(role) and "UP" or "down",
      set and set.anchor and (set.anchor:IsShown() and "shown" or "hidden") or "NO",
      set and set.anchor and (set.anchor:GetName() or "?") or "-",
      header and (header:IsShown() and "shown" or "hidden") or "NO",
      header and (header:GetName() or "?") or "-",
      rShown,
      pos and ("%s %d,%d"):format(pos[1], pos[3] or 0, pos[4] or 0) or "?")
  end
  return lines
end

function ns.ApplyChrome()
  local set = ns.activeGrid and sets[ns.activeGrid]
  if not set or not anchor then
    return false
  end
  set.chrome = set.chrome or CreateChrome(ns.activeGrid)
  local chrome = set.chrome

  -- The whole shell off: just the bars, floating. Per role, so a healer can
  -- keep the frame while damage runs bare.
  if ns.db.showChrome == false then
    chrome:Hide()
    return true
  end

  -- Span every header that is actually up. A grid showing raid groups is a
  -- different shape from one showing the party, and the border has to be the
  -- shape of what is there.
  local shown = {}
  for _, header in ipairs(ns.AllHeaders()) do
    if header:IsShown() then
      shown[#shown + 1] = header
    end
  end
  -- Nothing in it (a grid waiting for a group): no empty box on screen. Its
  -- headers bring it back when they show (CreateHeader). Unlocked, it stays,
  -- so it can still be dragged into place.
  if #shown == 0 and ns.db.locked ~= false then
    chrome:Hide()
    return true
  end

  -- The title strip ("Healing", "Tanking", "DPS"), unless switched off on
  -- the Unit Frames page (Party & Raid). Without it the border still says
  -- which grid is which, by colour.
  local titles = not (FUI.db and FUI.db.gridTitles == false)
  chrome.strip:SetShown(titles)
  chrome:ClearAllPoints()
  chrome:SetPoint("TOPLEFT", anchor, "TOPLEFT", -6, titles and 26 or 6)
  if #shown > 0 then
    chrome:SetPoint("BOTTOMRIGHT", shown[#shown], "BOTTOMRIGHT", 6, -6)
  else
    chrome:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 6, -6)
  end
  chrome:SetScale(ns.db.scale or 1)

  chrome:Show()
  return true
end

-- A grid's shell, for anything that needs to look at it (the tests, and the
-- options page when it wants to know whether one exists yet).
function ns.GridChrome(role)
  local set = sets[role or ns.activeGrid]
  return set and set.chrome
end

-- Every grid's chrome again, after the titles are switched on or off.
function ns.ApplyGridTitles()
  local count = 0
  for _, role in ipairs(ns.ROLES) do
    if sets[role] and sets[role].chrome then
      ns.WithGrid(role, function() ns.ApplyChrome() end)
      count = count + 1
    end
  end
  return count
end

local function CreateAnchor()
  -- Build once per grid.
  --
  -- SetupLayout runs again every time a grid is switched on or off, and this
  -- used to make a NEW anchor (and a new set of headers under it) each time.
  -- The old ones were no longer in `sets`, so nothing could ever hide them:
  -- switching a grid off took away its shell and left a derelict copy of its
  -- frames sitting on screen, one more with every toggle.
  if anchor then
    anchor:SetScale(ns.db.scale)
    anchor:Show()
    ns.anchor = anchor
    ns.ApplyPosition()
    return anchor
  end
  -- Named for the grid. Two frames cannot share a global name, and three
  -- grids exist at once now.
  anchor = CreateFrame("Frame", "ForeverUIFramesAnchor" .. (ns.activeGrid or "healer"), UIParent)
  anchor:SetSize(GroupWidth(), 22)
  anchor:SetFrameStrata("MEDIUM")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScale(ns.db.scale)

  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetAllPoints()
  anchor.bg:SetColorTexture(0.07, 0.07, 0.09, 0.85)

  anchor.rule = anchor:CreateTexture(nil, "BORDER")
  anchor.rule:SetPoint("TOPLEFT", -1, 1)
  anchor.rule:SetPoint("BOTTOMRIGHT", 1, -1)
  anchor.rule:SetColorTexture(0.30, 0.76, 1.00, 0.95)

  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  anchor.label:SetPoint("CENTER")
  anchor.label:SetText("Drag to move")
  anchor.label:SetTextColor(0.30, 0.76, 1.00)

  -- Who this handle moves, and whose position it writes. Without these two
  -- the drag falls back to "the grid being configured", which with three on
  -- screen is the wrong one almost every time.
  anchor.gridRole = ns.activeGrid or ns.GetMode()
  anchor.movesGrid = anchor
  anchor:SetScript("OnDragStart", ns.StartMovingFrames)
  anchor:SetScript("OnDragStop", ns.StopMovingFrames)

  ns.anchor = anchor
  ns.ApplyPosition()
end

-- Everything is parented to the anchor, so scaling it scales all frames.
-- Saved offsets are in the anchor's own (scaled) units: convert them so the
-- frames grow or shrink in place instead of drifting across the screen.
-- Scale every grid that is up, each rescaling its OWN saved position.
-- Deferred like everything else here, so the grid it was queued for is pinned
-- and the anchor is checked: by the time it fires that grid may be gone.
function ns.ApplyScale()
  local roles = ns.ShownGrids()
  if #roles > 1 or (roles[1] and roles[1] ~= ns.activeGrid) then
    for _, role in ipairs(roles) do
      ns.WithGrid(role, ns.ApplyGridScale)
    end
    return
  end
  return ns.ApplyGridScale()
end

function ns.ApplyGridScale()
  local grid = ns.activeGrid
  ns.WhenOutOfCombat(function()
    if grid then
      StoreGrid()
      UseGrid(grid)
    end
    if not anchor then
      return
    end
    local old, new = anchor:GetScale(), ns.db.scale
    if old == new then
      return
    end
    local p = ns.db.position
    if p then
      p[3], p[4] = p[3] * old / new, p[4] * old / new
    end
    anchor:SetScale(new)
    ns.ApplyPosition()
  end)
end

---------------------------------------------------------------------------
-- Secure headers
---------------------------------------------------------------------------

-- Roles in Classic are raid assignments (Main Tank / Main Assist), not specs.
local SORTS = {
  index = { sortMethod = "INDEX" },
  name  = { sortMethod = "NAME" },
  class = { sortMethod = "NAME", groupBy = "CLASS",
            groupingOrder = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,SHAMAN,MAGE,WARLOCK,DRUID" },
  group = { sortMethod = "INDEX", groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8" },
  role  = { sortMethod = "NAME", groupBy = "ROLE",
            groupingOrder = "MAINTANK,MAINASSIST,TANK,HEALER,DAMAGER,NONE" },
}

-- Which way frames run inside one header, and in what order.
local function ApplyHeaderLayout(header)
  local sort = SORTS[ns.db.sortMode] or SORTS.index
  if ns.db.tanksFirst then
    -- Group by role first; whatever sort you chose still orders people inside.
    -- The game's assigned role (dungeon finder, role check), not the raid's
    -- Main Tank: a five-player group never has a Main Tank, so "ROLE" left
    -- the tank wherever the group order put them (owner, 25 Sept 2026).
    sort = {
      sortMethod = sort.sortMethod,
      groupBy = "ASSIGNEDROLE",
      groupingOrder = "TANK,HEALER,DAMAGER,NONE",
    }
  end
  header:SetAttribute("point", ns.db.horizontal and "LEFT" or "TOP")
  header:SetAttribute("xOffset", ns.db.horizontal and BUTTON_SPACING or 0)
  header:SetAttribute("yOffset", ns.db.horizontal and 0 or -BUTTON_SPACING)
  -- "roles" is your own order, which the header can only do from a list of
  -- names - and a header given names ignores everyone not on it, so the list
  -- is rebuilt whenever the group changes. Any other sort hands the raid
  -- headers their group number back.
  local nameList
  if ns.db.sortMode == "roles" and header.hfList then
    -- In a group Forever hides everyone's name, and the list can't be built
    -- (it threw, and the frames kept the group order). Then the same order
    -- goes by the game's assigned roles instead - no names needed.
    local ok, lists = pcall(ns.SortedNameLists)
    local list = ok and lists and (header.hfList == "party" and lists.party or (lists.groups[header.hfList] or ""))
    if type(list) == "string" and not (issecretvalue and issecretvalue(list)) then
      nameList = list
      sort = { sortMethod = "NAMELIST" }
    else
      sort = { sortMethod = "INDEX", groupBy = "ASSIGNEDROLE", groupingOrder = ns.AssignedRoleOrder() }
    end
  end
  if header.hfList and header.hfList ~= "party" then
    header:SetAttribute("groupFilter", (not nameList) and tostring(header.hfList) or nil)
  end
  if header.hfList then
    header:SetAttribute("nameList", nameList)
  end
  header:SetAttribute("sortMethod", sort.sortMethod)
  header:SetAttribute("sortDir", ns.db.sortReverse and "DESC" or "ASC")
  header:SetAttribute("groupBy", sort.groupBy)
  header:SetAttribute("groupingOrder", sort.groupingOrder)
  header:SetAttribute("minWidth", GroupWidth())
  header:SetAttribute("minHeight", GroupHeight())
end

local function CreateHeader(name)
  local header = CreateFrame("Frame", name, anchor, "SecureGroupHeaderTemplate")
  -- Stamped onto the header, read by each button it makes. A button that does
  -- not know its grid binds with whatever settings are loaded when its unit
  -- arrives -- which is a tank frame casting a heal, and looks like nothing
  -- is wrong at all.
  header.gridRole = ns.activeGrid or "healer"
  -- The shell follows its headers: a grid that waits for a group (see
  -- ApplyVisibility) gets its border back the moment one forms, in combat
  -- too -- the shell is a plain frame. Next frame, not inside the show, so
  -- it never runs in the middle of another grid's swap.
  local function Reshell()
    local role = header.gridRole
    local later = C_Timer and C_Timer.After
    local function go()
      if sets[role] and sets[role].chrome and ns.IsGridShown(role) then
        ns.WithGrid(role, ns.ApplyChrome)
      end
    end
    if later then later(0, go) else go() end
  end
  header:HookScript("OnShow", Reshell)
  header:HookScript("OnHide", Reshell)
  header:SetAttribute("template", "ForeverUIFramesUnitButtonTemplate")
  -- No "initialConfigFunction": Forever's restricted environment has no
  -- SetWidth/SetHeight, and the error there aborts frame creation entirely,
  -- leaving you with no frames at all. Sizing happens in ns.ApplyFrameSize
  -- and when a frame is handed a unit, both out of combat.
  ApplyHeaderLayout(header)
  return header
end

-- Sorting and direction are header attributes: out of combat only.
function ns.ApplySorting()
  ns.WhenOutOfCombat(function()
    for _, header in ipairs(ns.AllHeaders()) do
      ApplyHeaderLayout(header)
    end
    ns.LayoutPreviews()
    ns.LayoutGroups()
  end)
end

-- Existing frames have to be resized directly; only possible out of combat.
-- The size a frame should be right now; Button_OnAttributeChanged uses it so a
-- frame created mid-combat is sized as soon as it's safe.
function ns.FrameSize()
  return W(), H()
end

-- Size every grid that is up, each from its own settings.
--
-- This ran against whatever `anchor` happened to be, and WhenOutOfCombat
-- defers -- so by the time it fired the swap had moved on and `anchor` could
-- be nil entirely:
--
--   Layout.lua:473: attempt to index upvalue 'anchor' (a nil value)
--
-- Wrapped per grid, and guarded, because a deferred call can always arrive
-- after the grid it was queued for has gone.
function ns.ApplyFrameSize()
  local roles = ns.ShownGrids()
  if #roles > 1 or (roles[1] and roles[1] ~= ns.activeGrid) then
    for _, role in ipairs(roles) do
      ns.WithGrid(role, ns.ApplyGridFrameSize)
    end
    return
  end
  return ns.ApplyGridFrameSize()
end

function ns.ApplyGridFrameSize()
  local grid = ns.activeGrid
  ns.WhenOutOfCombat(function()
    -- The grid may have been switched off between queueing and firing.
    if grid then
      StoreGrid()
      UseGrid(grid)
    end
    if not anchor then
      return
    end
    anchor:SetWidth(GroupWidth())
    for _, header in ipairs(ns.AllHeaders()) do
      header:SetAttribute("minWidth", W())
      header:SetAttribute("minHeight", GroupHeight())
      local i, child = 1, header:GetAttribute("child1")
      while child do
        child:SetSize(W(), H())
        ns.EnableDrag(child)
        i = i + 1
        child = header:GetAttribute("child" .. i)
      end
    end
    ns.LayoutPreviews()
    ns.LayoutGroups()
    ns.RenderPreviews()
    SizeHandle()
  end)
end

-- Bar texture and font size on every frame, real and preview.
-- One frame's look. Called for every frame at startup, and again whenever a
-- new one is built, which is why it lives on ns rather than inside the loop.
local StyleLook
-- Each grid is styled with its own role's look (Modes.lua WithLook).
function ns.StyleButton(button)
  return ns.WithLook(ns.ButtonGrid(button), StyleLook, button)
end

-- How much of the frame the overheal lane keeps back, in pixels.
function ns.OverhealLaneWidth()
  if not ns.db.overhealLane then
    return 0
  end
  local width = select(1, ns.FrameSize())
  local percent = math.max(5, math.min(40, ns.db.overhealLanePercent or 15))
  return math.max(4, math.floor(width * percent / 100 + 0.5))
end

StyleLook = function(button)
  local texture, size = ns.db.barTexture, ns.db.fontSize
  local font = GameFontHighlightSmall and GameFontHighlightSmall:GetFont()
  local power = ns.db.powerBarHeight or 0
  local bar = button.health
  -- The bar stops short when the lane is on, so that "full" is a point
  -- inside the frame and a heal past it has room to show. Applied where the
  -- bar is anchored, further down.
  local lane = ns.OverhealLaneWidth()
  bar:SetStatusBarTexture(texture)
  button.power:SetStatusBarTexture(texture)
  ns.StyleBackground(button)
  local fill = bar:GetStatusBarTexture()
  if fill then
    fill:SetAlpha((ns.db.healthAlpha or 100) / 100)
    -- Gradient fill: a shade over the filled part, lighter at the top. A
    -- colour gradient on the fill itself would need the bar's colour, which
    -- on Forever is picked by the game from secret health.
    if not bar.shade then
      bar.shade = bar:CreateTexture(nil, "ARTWORK", nil, 7)
      bar.shade:SetColorTexture(1, 1, 1, 1)
      if bar.shade.SetGradient and CreateColor then
        bar.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(1, 1, 1, 0.18))
      end
    end
    bar.shade:ClearAllPoints()
    bar.shade:SetAllPoints(fill)
    bar.shade:SetShown(ns.db.barGradient and true or false)
  end
  -- The edge around the bar: 0, 1 or 2 pixels of it show.
  local edge = ns.db.borderSize or 1
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", edge, -edge)
  bar:SetPoint("BOTTOMRIGHT", -edge - lane, edge + (power > 0 and (power + 1) or 0))
  local reverse = ns.db.fillDirection == "right"
  -- "up": the health bar stands on end and fills from the bottom (VuhDo's
  -- vertical bars). The mana bar stays a strip along the bottom.
  local vertical = ns.db.fillDirection == "up"
  if bar.SetOrientation then bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL") end
  if bar.SetRotatesTexture then bar:SetRotatesTexture(vertical) end
  if bar.SetReverseFill then bar:SetReverseFill(reverse) end
  if button.power.SetReverseFill then button.power:SetReverseFill(reverse) end
  -- Where the health text sits along the bottom (bar style).
  local at = ns.db.healthAnchor or "right"
  bar.status:ClearAllPoints()
  local point = ({ left = "BOTTOMLEFT", center = "BOTTOM", right = "BOTTOMRIGHT" })[at] or "BOTTOMRIGHT"
  bar.status:SetPoint(point, ({ left = 4, center = 0, right = -4 })[at] or -4, 4)
  bar.status:SetJustifyH(({ left = "LEFT", center = "CENTER", right = "RIGHT" })[at] or "RIGHT")
  if font then
    -- Outline *and* shadow: a Priest's class colour is white, and white text
    -- on a white bar disappears without both.
    local healthSize = (ns.db.healthFontSize or 0) > 0 and ns.db.healthFontSize or size
    for _, text in ipairs({ bar.name, bar.status, bar.big }) do
      local want = text == bar.big and math.max(10, math.floor(H() * 0.42))
        or (text == bar.status and healthSize) or size
      text:SetFont(font, want, "OUTLINE")
      text:SetShadowColor(0, 0, 0, 1)
      text:SetShadowOffset(1, -1)
    end
  end
end

-- What sits behind the health fill: a dark plate, pure black, a dimmed class
-- colour (Grid's look), or nothing at all.
function ns.StyleBackground(button, class)
  local mode, bg = ns.db.barBackground, button.health.bg
  local a = (ns.db.barOpacity or 100) / 100
  if bg.SetHorizTile then bg:SetHorizTile(false); bg:SetVertTile(false) end
  if ns.db.showLoss and mode ~= "none" then
    -- The missing part of the bar IS the background: show it as a wound.
    bg:SetColorTexture(0.40, 0.05, 0.05, a)
    return
  end
  if type(mode) == "string" and mode:sub(1, 4) == "tex:" then
    -- A painted surface (ChatGPT art, Media/skin/bg-*.tga), repeated along
    -- the bar at its own size.
    bg:SetTexture(ns.BAR_BG_PATH .. mode:sub(5), "REPEAT", "REPEAT")
    if bg.SetHorizTile then bg:SetHorizTile(true); bg:SetVertTile(true) end
    bg:SetVertexColor(1, 1, 1, a)
    return
  end
  bg:SetVertexColor(1, 1, 1, 1)
  if mode == "solid" then
    local c = ns.db.barBackgroundColor or { 0.12, 0.12, 0.12 }
    bg:SetColorTexture(c[1], c[2], c[3], a)
  elseif mode == "none" then
    bg:SetColorTexture(0, 0, 0, 0)
  elseif mode == "black" then
    bg:SetColorTexture(0, 0, 0, a)
  elseif mode == "light" then
    bg:SetColorTexture(0.38, 0.38, 0.42, a)
  elseif mode == "navy" then
    bg:SetColorTexture(0.03, 0.07, 0.14, a)
  elseif mode == "role" then
    local chrome = ns.ROLE_CHROME and ns.ROLE_CHROME[ns.ButtonGrid and ns.ButtonGrid(button) or "healer"]
    local c = chrome and chrome.color or { 0.3, 0.3, 0.3 }
    bg:SetColorTexture(c[1] * 0.22, c[2] * 0.22, c[3] * 0.22, a)
  elseif mode == "class" then
    local r, g, b = ns.ClassColor(class)
    if r then
      bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, a)
    else
      bg:SetColorTexture(0.12, 0.12, 0.12, a)
    end
  else
    bg:SetColorTexture(0.12, 0.12, 0.12, a)
  end
end

function ns.ApplyAppearance()
  local function style(button)
    ns.StyleButton(button)
  end

  ns.ForEachButton(style)
  for _, frame in ipairs({ previewParty, previewRaid }) do
    for _, button in ipairs(frame.buttons) do
      style(button)
    end
  end
  ns.RefreshAll()
  ns.RenderPreviews()
end

-- "Group 3" over each raid group (VuhDo's headers). On the header itself,
-- so it comes and goes with the group; the header is only touched here, out
-- of combat.
function ns.LabelRaidHeader(header, index)
  local label = header.fuiLabel
  if not label and header.CreateFontString then
    label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetTextColor(0.75, 0.75, 0.80)
    header.fuiLabel = label
  end
  if not label then return nil end
  label:ClearAllPoints()
  label:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 2, 1)
  label:SetText(("Group %d"):format(index))
  label:SetShown(ns.db.groupLabels and true or false)
  return label
end

local function PositionRaidHeaders()
  for index, header in ipairs(ns.raidHeaders) do
    local x, y = ns.GroupOffset(index, ns.db.groupsPerRow)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    ns.LabelRaidHeader(header, index)
  end
end

function ns.ApplyVisibility()
  if not ns.header then
    return
  end
  -- A grid that is switched off is switched off by its DRIVER, not by Hide().
  -- These are secure frames under a state-visibility driver, and the driver
  -- wins: a plain Hide() looks like it worked and the grid comes back the
  -- next time the driver re-evaluates -- joining a group, zoning, leaving
  -- combat. Whoever turned it off would swear it turned itself back on.
  local role = ns.activeGrid or ns.GetMode()
  if not ns.IsGridShown(role) then
    RegisterAttributeDriver(ns.header, "state-visibility", "hide")
    for _, header in ipairs(ns.raidHeaders) do
      RegisterAttributeDriver(header, "state-visibility", "hide")
    end
    if ns.petHeader then
      RegisterAttributeDriver(ns.petHeader, "state-visibility", "hide")
    end
    return
  end
  -- Only the grid of the role you are playing shows you on your own. The
  -- others wait for a group: three grids up and nobody to watch was three
  -- boxes with your name in each (owner, 27 Sept 2026: "fix the three role
  -- grids showing while solo"). A driver, so joining a group mid-fight
  -- still brings them up.
  -- ...unless you asked to see them all anyway (wixer5851 on CurseForge,
  -- 27 Sept 2026: a shadow priest with Healer and DPS on saw only one, and
  -- had to click the other before it showed): soloAllGrids.
  -- Now per role: "in groups only" (ns.GridState, owner 30 Sept 2026).
  local party = "show"
  local inGroupsOnly
  if ns.GridState then
    inGroupsOnly = ns.GridState(role) == "group"
  else
    inGroupsOnly = role ~= ns.PlayingRole() and not ns.lockedRole and not ns.db.soloAllGrids
  end
  if inGroupsOnly then
    party = "[group] show; hide"
  end
  if ns.petHeader then
    ns.petHeader:ClearAllPoints()
    if ns.db.horizontal then
      ns.petHeader:SetPoint("TOPLEFT", ns.header, "BOTTOMLEFT", 0, -BUTTON_SPACING)
    else
      ns.petHeader:SetPoint("TOPLEFT", ns.header, "TOPRIGHT", BUTTON_SPACING, 0)
    end
    RegisterAttributeDriver(ns.petHeader, "state-visibility",
      ns.db.showPets and ("[group:raid] hide; " .. party) or "hide")
  end
  local useRaid = ns.db.useRaidFrames
  RegisterAttributeDriver(ns.header, "state-visibility", useRaid and ("[group:raid] hide; " .. party) or party)
  for _, header in ipairs(ns.raidHeaders) do
    RegisterAttributeDriver(header, "state-visibility", useRaid and "[group:raid] show; hide" or "hide")
  end
end

local function CreateHeaders()
  if ns.header then
    -- Already built for this grid: re-apply what can change and stop.
    PositionRaidHeaders()
    ns.ApplyBindings()
    ns.ApplyVisibility()
    return ns.header
  end
  local tag = ns.activeGrid or "healer"
  local party = CreateHeader("ForeverUIFramesPartyHeader" .. tag)
  party.hfList = "party"
  party:SetAttribute("showPlayer", true)
  party:SetAttribute("showSolo", true)
  party:SetAttribute("showParty", true)
  party:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -BUTTON_SPACING)
  ns.header = party

  for group = 1, NUM_GROUPS do
    local header = CreateHeader("ForeverUIFramesRaidGroup" .. tag .. group)
    header.hfList = group
    header:SetAttribute("showRaid", true)
    header:SetAttribute("groupFilter", tostring(group))
    -- Empty groups keep their column's size so the grid doesn't collapse.
    ns.raidHeaders[group] = header
  end

  local pets = CreateFrame("Frame", "ForeverUIFramesPartyPets" .. tag, anchor, "SecureGroupPetHeaderTemplate")
  pets:SetAttribute("template", "ForeverUIFramesUnitButtonTemplate")
  pets:SetAttribute("showParty", true)
  pets:SetAttribute("showPlayer", true)
  ApplyHeaderLayout(pets)
  ns.petHeader = pets

  PositionRaidHeaders()
  ns.ApplyBindings() -- before the drivers show them, so the first buttons come out bound
  ns.ApplyVisibility()
end

---------------------------------------------------------------------------
-- Previews (plain frames, never secure)
---------------------------------------------------------------------------

local function PreviewButton(parent, template, name)
  local button = CreateFrame("Button", nil, parent, "ForeverUIFramesUnitButtonBaseTemplate")
  button:EnableMouse(false)
  button.previewState = ns.CopyTable(template)
  if name then
    button.previewState.name = name
    button.previewState.isTarget = nil
  end
  return button
end

local function CreatePreviews()
  if previewParty then
    return previewParty
  end
  previewParty = CreateFrame("Frame", nil, anchor)
  previewParty:SetAllPoints()
  previewParty.buttons = {}
  for i, template in ipairs(PREVIEW) do
    previewParty.buttons[i] = PreviewButton(previewParty, template)
  end

  previewRaid = CreateFrame("Frame", nil, anchor)
  previewRaid:SetAllPoints()
  previewRaid.columns, previewRaid.buttons = {}, {}
  for group = 1, NUM_GROUPS do
    local column = CreateFrame("Frame", nil, previewRaid)
    previewRaid.columns[group] = column
    column.buttons = {}
    for i = 1, 5 do
      local template = PREVIEW[(group + i) % #PREVIEW + 1]
      local button = PreviewButton(column, template, template.name:sub(1, 6) .. " " .. group)
      column.buttons[i] = button
      previewRaid.buttons[#previewRaid.buttons + 1] = button
    end
  end

  for _, frame in ipairs({ previewParty, previewRaid }) do
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", PreviewOffset(), 2)
    label:SetText(frame == previewRaid and "Preview: raid" or "Preview: party")
  end

  ns.previewParty, ns.previewRaid = previewParty, previewRaid
  ns.LayoutPreviews()
end

-- Preview frames mirror whatever size and spacing the real ones use.
function ns.LayoutPreviews()
  local horizontal = ns.db.horizontal
  for i, button in ipairs(previewParty.buttons) do
    button:SetSize(W(), H())
    button:ClearAllPoints()
    if horizontal then
      button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", PreviewOffset() + (i - 1) * (W() + BUTTON_SPACING), -BUTTON_SPACING)
    else
      button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", PreviewOffset(), -BUTTON_SPACING - (i - 1) * (H() + BUTTON_SPACING))
    end
  end
  for _, column in ipairs(previewRaid.columns) do
    column:SetSize(GroupWidth(), GroupHeight())
    for i, button in ipairs(column.buttons) do
      button:SetSize(W(), H())
      button:ClearAllPoints()
      if horizontal then
        button:SetPoint("TOPLEFT", column, "TOPLEFT", (i - 1) * (W() + BUTTON_SPACING), 0)
      else
        button:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -(i - 1) * (H() + BUTTON_SPACING))
      end
    end
  end
end

function ns.RenderPreviews()
  local now = GetTime()
  for _, frame in ipairs({ previewParty, previewRaid }) do
    for _, button in ipairs(frame.buttons) do
      local s = button.previewState
      s.hotCount = s.hots and #s.hots or 0
      for _, hot in ipairs(s.hots or {}) do
        hot.expires = now + hot.remaining
      end
      ns.Render(button, s)
    end
  end
end

function ns.UpdatePreviewVisibility()
  local unlocked = not ns.db.locked
  previewParty:SetShown(unlocked and not ns.db.previewRaid)
  previewRaid:SetShown(unlocked and ns.db.previewRaid)
end

-- Raid columns: previews move right away, secure headers after combat.
function ns.LayoutGroups()
  for group, column in ipairs(previewRaid.columns) do
    local x, y = ns.GroupOffset(group, ns.db.groupsPerRow)
    column:ClearAllPoints()
    column:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", PreviewOffset() + x, y)
  end
  ns.WhenOutOfCombat(PositionRaidHeaders)
end

-- A labelled box over the frames while unlocked: drag it anywhere,
-- right-click to put the frames back where they started.
function CreateHandle()
  local handle = CreateFrame("Frame", "ForeverUIFramesMoveHandle" .. (ns.activeGrid or "healer"), anchor)
  handle:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  handle:SetFrameStrata("HIGH")
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:Hide()

  -- Barely there on purpose: you are placing the frames, so you have to be
  -- able to see them. A faint wash, a bright edge, and the words kept off the
  -- frames themselves.
  handle.bg = handle:CreateTexture(nil, "BACKGROUND")
  handle.bg:SetAllPoints()
  handle.bg:SetColorTexture(0.30, 0.76, 1.00, 0.10)

  handle.edge = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = handle:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(0.30, 0.76, 1.00, 0.95)
    if side == "TOP" then
      tex:SetPoint("TOPLEFT", -1, 1); tex:SetPoint("TOPRIGHT", 1, 1); tex:SetHeight(2)
    elseif side == "BOTTOM" then
      tex:SetPoint("BOTTOMLEFT", -1, -1); tex:SetPoint("BOTTOMRIGHT", 1, -1); tex:SetHeight(2)
    elseif side == "LEFT" then
      tex:SetPoint("TOPLEFT", -1, 1); tex:SetPoint("BOTTOMLEFT", -1, -1); tex:SetWidth(2)
    else
      tex:SetPoint("TOPRIGHT", 1, 1); tex:SetPoint("BOTTOMRIGHT", 1, -1); tex:SetWidth(2)
    end
    handle.edge[#handle.edge + 1] = tex
  end

  handle.label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  handle.label:SetPoint("BOTTOMLEFT", handle, "TOPLEFT", 2, 4)
  handle.label:SetText(ns.FOLDER .. " frames - drag to move, right-click to reset, then Place")
  handle.label:SetTextColor(0.30, 0.76, 1.00)
  handle.label:SetShadowColor(0, 0, 0, 1)
  handle.label:SetShadowOffset(1, -1)

  handle.hint = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  handle.hint:Hide() -- kept so anything that pokes at it still finds a font string

  -- The way out. Dragging is only half of moving something: without a button
  -- here the only ways to finish were a slash command or a trip back to the
  -- options window, neither of which anyone would guess.
  local place = CreateFrame("Button", nil, handle)
  place:SetSize(150, 24)
  place:SetPoint("TOPLEFT", handle, "BOTTOMLEFT", -1, -6)
  place:SetFrameStrata("DIALOG")
  place.fill = place:CreateTexture(nil, "BACKGROUND")
  place.fill:SetAllPoints()
  place.fill:SetColorTexture(0.10, 0.22, 0.30, 0.95)
  place.edge = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = place:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(0.30, 0.76, 1.00, 1)
    if side == "TOP" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(1)
    elseif side == "BOTTOM" then
      tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(1)
    elseif side == "LEFT" then
      tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT"); tex:SetWidth(1)
    else
      tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetWidth(1)
    end
    place.edge[#place.edge + 1] = tex
  end
  place.text = place:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  place.text:SetPoint("CENTER")
  place.text:SetText("Place frames here")
  place.text:SetTextColor(0.30, 0.76, 1.00)
  place:SetScript("OnEnter", function(self) self.fill:SetColorTexture(0.14, 0.32, 0.44, 0.95) end)
  place:SetScript("OnLeave", function(self) self.fill:SetColorTexture(0.10, 0.22, 0.30, 0.95) end)
  place:SetScript("OnClick", function()
    if InCombatLockdown() then
      ns.Print("can't lock the frames in combat - they'll stay where they are; click again after the fight.")
      return
    end
    ns.CapturePosition()
    ns.SetLocked(true)
    ns.Print("frames placed.")
    if ns.RefreshOptions then
      ns.RefreshOptions()
    end
  end)
  handle.place = place

  handle.gridRole = ns.activeGrid or ns.GetMode()
  handle.movesGrid = anchor
  handle:SetScript("OnDragStart", ns.StartMovingFrames)
  handle:SetScript("OnDragStop", ns.StopMovingFrames)
  handle:SetScript("OnMouseUp", function(_, mouseButton)
    if mouseButton == "RightButton" then
      ns.ResetPosition()
      ns.Print("frames moved back to their starting spot.")
    end
  end)

  ns.moveHandle = handle
  return handle
end

-- The box covers what you can actually see: a party is one group wide, and
-- the eight-group raid shape only applies when the raid frames are the ones
-- on screen. Sizing it for the largest possible layout buried the frames
-- under a box the width of the monitor.
local function ShowingRaid()
  if not ns.db.useRaidFrames then
    return false
  end
  if not ns.db.locked and ns.db.previewRaid then
    return true -- previewing the raid layout
  end
  return IsInRaid and IsInRaid()
end

function SizeHandle()
  if not ns.moveHandle then
    return
  end
  local raid = ShowingRaid()
  local rows = raid and math.ceil(NUM_GROUPS / ns.db.groupsPerRow) or 1
  local width = raid
    and math.min(NUM_GROUPS, ns.db.groupsPerRow) * (GroupWidth() + GROUP_GAP) or GroupWidth()
  ns.moveHandle:SetSize(math.max(GroupWidth(), width), rows * (GroupHeight() + GROUP_GAP + (raid and LabelHeight() or 0)))
end

-- Unlock EVERY grid that is up, not just the one being configured.
--
-- SetLocked touches the active grid's anchor and handle. With one grid that
-- was the whole story; with three it means only the healer's handle appears
-- and the tanking and DPS grids cannot be dragged at all -- which is exactly
-- what happens if you unlock while looking at the healer window.
function ns.SetLockedEverywhere(locked)
  local roles = ns.ShownGrids()
  if #roles == 0 then
    return ns.SetLocked(locked)
  end
  for _, role in ipairs(roles) do
    ns.WithGrid(role, function() ns.SetLocked(locked) end)
  end
  -- The flag is shared, so make sure it survives the last swap back.
  ns.db.locked = locked
  return locked
end

function ns.SetLocked(locked)
  ns.db.locked = locked
  if not anchor then
    return   -- this grid has not been built yet; nothing to unlock
  end
  if not ns.moveHandle then
    CreateHandle()
  end
  SizeHandle()
  ns.moveHandle:SetShown(not locked)
  anchor:EnableMouse(not locked)
  anchor.bg:SetShown(not locked)
  anchor.rule:SetShown(not locked)
  anchor.label:SetShown(not locked)
  anchor:SetHeight(locked and 1 or 22)
  ns.UpdatePreviewVisibility()
  ns.SetTargetLocked(locked)
  ns.SetFocusLocked(locked)
  if ns.SetPanelsLocked then ns.SetPanelsLocked(locked) end
  if ns.SetBuffWatchLocked then ns.SetBuffWatchLocked(locked) end
  if ns.GetMode() == "tank" then
    if ns.SetAlertLocked then ns.SetAlertLocked(locked) end
    if ns.SetLooseLocked then ns.SetLooseLocked(locked) end
  end
  if ns.SetOnYouLocked then ns.SetOnYouLocked(locked) end
end

---------------------------------------------------------------------------
-- Blizzard's party and raid frames
---------------------------------------------------------------------------

-- Opt-in. Blizzard's frames are moved under a hidden parent and stop listening
-- for events. Hide() alone wouldn't stick: Blizzard's code calls Show() on them
-- whenever the roster changes, but a frame under a hidden parent stays hidden.
-- There's no clean way to hand them back, so turning an option off takes a /reload.
local hiddenParent
local blizzardPartyHidden = false
local blizzardRaidHidden = false

-- Takes the mouse off a stashed frame's buttons. A faded parent hides its
-- children, but each unit button still takes clicks where it stands.
local function Deafen(frame, depth)
  if not frame or depth > 3 or not frame.GetChildren then return end
  for _, child in ipairs({ frame:GetChildren() }) do
    if child.EnableMouse then
      pcall(child.EnableMouse, child, false)
    end
    Deafen(child, depth + 1)
  end
end

local function Stash(frame)
  if not frame then
    return
  end
  -- Local patch (4 Oct 2026): fade, never hide or move. PartyFrame,
  -- CompactPartyFrame and the raid container are Edit Mode systems, and
  -- hiding one -- HideBase or SetParent alike -- fires its members' OnHide
  -- (CompactUnitFrame_OnHide) inside our call. The next Edit Mode pass read
  -- what that wrote and ran as ForeverUI: "CompactUnitFrame.lua:699: attempt
  -- to compare local 'oldR' (a secret number value, while execution tainted
  -- by 'ForeverUI')" entering and leaving Edit Mode, and
  -- "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted
  -- by 'ForeverUI'" from InvokeOnAnyEditModeSystemAnchorChanged on level-up.
  -- Same cure as Skin.Conceal's for managed and protected frames.
  local skin = FUI.Skin
  if skin and skin.Fade then
    frame:UnregisterAllEvents()
    skin.Fade(frame)
    Deafen(frame, 1)
    ns.SilenceUnitFrames(frame)
    return
  end
  if not hiddenParent then
    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
  end
  frame:UnregisterAllEvents()
  -- PartyFrame and the raid container are Edit Mode systems: their own Hide
  -- is Lua that writes into the Edit Mode manager under our taint. The C
  -- original is kept beside it as HideBase.
  local hide = rawget(frame, "HideBase") or frame.Hide
  hide(frame)
  frame:SetParent(hiddenParent)
  ns.SilenceUnitFrames(frame)
end

-- Hiding a frame of Blizzard's party or raid frames from here runs each
-- member's OnHide (CompactUnitFrame_OnHide) inside our call, and that
-- re-registers the member's unit events -- health, threat, range -- as ours.
-- Those members still heard every event under the hidden parent, and the
-- first threat update in a fight ran Blizzard's code under ForeverUI's name:
-- "CompactUnitFrame.lua:699: attempt to compare local 'oldR' (a secret number
-- value, while execution tainted by 'ForeverUI')" (BAP2521, 1 Oct 2026). So
-- the members are taken off the events too; nobody can see them anyway.
function ns.SilenceUnitFrames(root)
  local onEvent = rawget(_G, "CompactUnitFrame_OnEvent")
  local count = 0
  local function Visit(frame, depth)
    if not frame or depth > 3 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
      local ok, script = pcall(child.GetScript, child, "OnEvent")
      if ok and script ~= nil and (script == onEvent or rawget(child, "optionTable") ~= nil) then
        pcall(child.UnregisterAllEvents, child)
        count = count + 1
      end
      Visit(child, depth + 1)
    end
  end
  Visit(root, 1)
  return count
end

-- With the controller interface on and Edit Mode's raid-style party frames,
-- the controller picks party members with a cursor that walks Blizzard's
-- CompactPartyFrame (Blizzard_GamepadTargeting, RaidTargetDPAD.lua). Hidden,
-- it would have nothing to land on, so then Blizzard's stay. The D-pad's
-- party1-4 targeting needs no frames and is unaffected either way.
function ns.PadNeedsBlizzardParty()
  local pad = FUI.GamepadUIActive and FUI.GamepadUIActive()
  if not pad then return false end
  local editMode = rawget(_G, "EditModeManagerFrame")
  if not (editMode and editMode.UseRaidStylePartyFrames) then return false end
  local ok, raidStyle = pcall(editMode.UseRaidStylePartyFrames, editMode)
  return ok and raidStyle == true
end

function ns.HideBlizzardParty()
  if blizzardPartyHidden or ns.PadNeedsBlizzardParty() then
    return
  end
  blizzardPartyHidden = true

  if PartyFrame then
    if PartyFrame.PartyMemberFramePool then
      for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
        Stash(member)
      end
    end
    Stash(PartyFrame)
  end
  Stash(CompactPartyFrame)
  for i = 1, 4 do
    Stash(_G["PartyMemberFrame" .. i]) -- older clients
  end
end

-- Only the frames container. CompactRaidFrameManager - the side panel with
-- ready check, raid markers and group filters - is left alone for raid leaders.
function ns.HideBlizzardRaid()
  if blizzardRaidHidden or not CompactRaidFrameContainer then
    return -- not loaded yet: the loader below catches it
  end
  blizzardRaidHidden = true
  Stash(CompactRaidFrameContainer)
end

-- In case Blizzard's raid frames load after HealForever does.
local loader = CreateFrame("Frame")
ns.RegisterEvent(loader, "ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
  if name == "Blizzard_CompactRaidFrames" and ns.db and ns.db.hideBlizzardRaid then
    ns.WhenOutOfCombat(ns.HideBlizzardRaid)
  end
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- This setting changes what a CLICK does, not what a frame looks like, and a
-- click lives in a secure attribute. Nothing else in this table touches those,
-- so without this the value was stored and the buttons kept doing what they
-- did before, until the next reload or binding edit.
local function Rebind()
  if ns.ApplyBindings then
    ns.WhenOutOfCombat(ns.ApplyBindings)
  end
end

local APPLY = {
  -- Downranking changes the spell NAME a click casts (Healing Touch(Rank 1)),
  -- and a click lives in a secure attribute, so the buttons must be rewritten
  -- rather than repainted.
  showRanks = Rebind,
  barColor = function() ns.RefreshAll() end,
  barCustomColor = function() ns.RefreshAll() end,
  lowHealthThreshold = function() ns.RefreshAll() end,
  lowHealthColor = function() ns.RefreshAll() end,
  critHealthThreshold = function() ns.RefreshAll() end,
  critHealthColor = function() ns.RefreshAll() end,
  barBackgroundColor = function() ns.ApplyAppearance() end,
  barGradient = function() ns.ApplyAppearance() end,
  showLoss = function() ns.ApplyAppearance() end,
  healthAlpha = function() ns.ApplyAppearance() end,
  nameText = function() ns.RefreshAll() end,
  showThreat = function() ns.RefreshAll() end,
  missingBuffs = function() ns.ForgetBuffList() end,
  manualRoles = function() ns.RefreshAll(); if ns.db.sortMode == "roles" then ns.ApplySorting() end end,
  -- The lane changes how wide the health bar is, so every frame is restyled.
  showChrome = function() ns.ApplyChrome() end,
  overhealLane = function() ns.ApplyAppearance(); ns.RefreshAll() end,
  overhealLanePercent = function() ns.ApplyAppearance(); ns.RefreshAll() end,
  showFocus = function() ns.ApplyFocus() end,
  focusScale = function() ns.ApplyFocus() end,
  inferHots = function() ns.RefreshAll() end,
  gameDispels = function() ns.ApplyGameAuras() end,
  gameBuffs = function() ns.ApplyGameAuras(true) end,
  gameBuffsCombatOnly = function() if ns.GameBuffsCombat then ns.GameBuffsCombat() end end,
  gameBuffsCount = function() ns.ApplyGameAuras(true) end,
  gameBuffsSize = function() ns.ApplyGameAuras(true) end,
  gameBuffsCorner = function() ns.ApplyGameAuras(true) end,
  showDispel = function() ns.ApplyGameAuras() end,
  focusNames = function() ns.ApplyFocus() end,
  focusPosition = function() ns.ApplyFocusPosition() end,
  roleOrder = function() if ns.db.sortMode == "roles" then ns.ApplySorting() end end,
  showTargetDebuffs = function() ns.RenderTargetDebuffs() end,
  targetIconSize = function() ns.ApplyTargetSize(); ns.RenderTargetDebuffs() end,
  scale = function() ns.ApplyScale(); if ns.ApplyFocus then ns.ApplyFocus() end; if ns.ApplyLooseList then ns.ApplyLooseList() end end,
  threatAlert = function() if ns.UpdateThreatAlert then ns.UpdateThreatAlert() end end,
  looseList = function() if ns.ApplyLooseList then ns.ApplyLooseList() end end,
  showThreatMeter = function() if ns.TickNow then ns.TickNow() end end,
  showThreatPercent = function() if ns.TickNow then ns.TickNow() end end,
  loosePosition = function() if ns.ApplyLoosePosition then ns.ApplyLoosePosition() end end,
  alertPosition = function() if ns.ApplyAlertPosition then ns.ApplyAlertPosition() end end,
  onYouAlert = function() if ns.UpdateOnYou then ns.UpdateOnYou() end end,
  onYouPosition = function() if ns.ApplyOnYouPosition then ns.ApplyOnYouPosition() end end,
  groupsPerRow = function() ns.LayoutGroups() end,
  useRaidFrames = function() ns.WhenOutOfCombat(ns.ApplyVisibility) end,
  previewRaid = function() ns.UpdatePreviewVisibility() end,
  frameWidth = function() ns.ApplyFrameSize() end,
  horizontal = function() ns.ApplySorting() end,
  sortMode = function() ns.ApplySorting() end,
  tanksFirst = function() ns.ApplySorting() end,
  barBackground = function() ns.ApplyAppearance() end,
  showRole = function() ns.RefreshAll(); ns.RenderPreviews() end,
  roleStyle = function() ns.RefreshAll(); ns.RenderPreviews() end,
  rolePosition = function() ns.RefreshAll(); ns.RenderPreviews() end,
  roleSize = function() ns.RefreshAll(); ns.RenderPreviews() end,
  sortReverse = function() ns.ApplySorting() end,
  showPets = function() ns.WhenOutOfCombat(ns.ApplyVisibility) end,
  frameHeight = function() ns.ApplyFrameSize() end,
  barTexture = function() ns.ApplyAppearance() end,
  frameStyle = function() ns.ApplyAppearance() end,
  powerBarHeight = function() ns.ApplyAppearance() end,
  minimapButton = function() ns.ApplyMinimapButton() end,
  fontSize = function() ns.ApplyAppearance() end,
  healthFontSize = function() ns.ApplyAppearance() end,
  nameAnchor = function() ns.ApplyAppearance() end,
  healthAnchor = function() ns.ApplyAppearance() end,
  borderSize = function() ns.ApplyAppearance() end,
  borderColor = function() ns.ApplyAppearance() end,
  barOpacity = function() ns.ApplyAppearance() end,
  fillDirection = function() ns.ApplyAppearance(); ns.RefreshAll() end,
  groupLabels = function() ns.ApplyFrameSize(); ns.LayoutGroups() end,
  nameLength = function() ns.ApplyAppearance() end,
  hideBlizzardParty = function(on)
    if on then
      ns.WhenOutOfCombat(ns.HideBlizzardParty)
    elseif blizzardPartyHidden then
      ns.Print("Blizzard's party frames come back after /reload.")
    end
  end,
  hideBlizzardRaid = function(on)
    if on then
      ns.WhenOutOfCombat(ns.HideBlizzardRaid)
    elseif blizzardRaidHidden then
      ns.Print("Blizzard's raid frames come back after /reload.")
    end
  end,
}

-- Files loaded after this one (Healer.lua, Status.lua, Panels.lua...) add
-- their own settings' handlers here.
ns.SETTING_APPLY = APPLY

function ns.SetSetting(key, value)
  ns.db[key] = value
  if key == "auraWatch" then
    ns.RebuildWatchIndex()
  end
  if APPLY[key] then
    APPLY[key](value)
  end
  ns.RefreshAll()
  ns.RenderPreviews()
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
end

-- One grid. This is what SetupLayout used to be, start to finish; it now runs
-- once per grid that is on screen, with that grid's settings and frames
-- loaded around it.
local function BuildGrid()
  -- Which grid this is, captured NOW.
  --
  -- WhenOutOfCombat defers, and the swap around us is synchronous: by the
  -- time a deferred call runs, the loop has moved on and ns.activeGrid is
  -- whatever was restored at the end. Every grid's headers would then be
  -- built against one grid's anchor, and only that one would appear -- which
  -- is exactly what happened at login while toggling a grid by hand worked
  -- fine, because out of combat the queue drains immediately.
  local role = ns.activeGrid or ns.GetMode()

  CreateAnchor()
  CreatePreviews()
  ns.ApplyAppearance() -- fonts and bar texture, before anything is drawn
  ns.RenderPreviews()
  ns.LayoutGroups()
  ns.SetLocked(ns.db.locked)
  ns.WhenOutOfCombat(function() ns.WithGrid(role, CreateHeaders) end)
  ns.WhenOutOfCombat(function() ns.WithGrid(role, ns.ApplyChrome) end)
  -- Tank extras: the centre-screen alarm and the Loose list. Per grid, not
  -- per character -- a druid with the tank grid up gets them while his
  -- healing grid sits beside it without them.
  if ns.GetMode() == "tank" then
    if ns.CreateThreatAlert then ns.CreateThreatAlert() end
    if ns.CreateLooseList then ns.WhenOutOfCombat(ns.CreateLooseList) end
  elseif ns.GetMode() == "dps" then
    if ns.CreateOnYou then ns.CreateOnYou() end   -- "IT'S ON YOU" (OnYou.lua)
  end
end

-- Hide a grid that is no longer wanted, without destroying it: its frames are
-- secure, so they cannot be taken apart in combat, and keeping them means
-- turning it back on is instant and safe.
local function HideGrid(role)
  local set = sets[role]
  if not set then
    return false
  end
  ns.WhenOutOfCombat(function()
    -- The secure half: tell the drivers, because they outrank Hide(). Done
    -- unconditionally -- gating it on set.header meant a grid whose headers
    -- had not been built yet lost only its shell, leaving the units on
    -- screen under nothing. "Off" has to mean off even half-built.
    ns.WithGrid(role, function()
      if ns.header then
        ns.ApplyVisibility()
      end
    end)
    -- The insecure half: the shell, the drag handle, and the previews that
    -- appear when frames are unlocked. "Off" has to mean gone, not faded --
    -- a grid you switched off must not reappear the moment you unlock.
    if set.chrome then set.chrome:Hide() end
    if set.moveHandle then set.moveHandle:Hide() end
    if set.anchor then set.anchor:Hide() end
    if set.previewParty then set.previewParty:Hide() end
    if set.previewRaid then set.previewRaid:Hide() end
    -- Tank extras belong to the tank grid. Switch it off and the aggro alarm
    -- and the Loose list go with it, or they sit there alone announcing
    -- threat for a grid that is not on screen.
    if role == "tank" then
      if ns.alertFrame then ns.alertFrame:Hide() end
      local loose = _G["ForeverUIFramesLooseList"]
      if loose then loose:Hide() end
    end
  end)
  return true
end

function ns.SetupLayout()
  -- Things there is only ever one of, whatever is on screen.
  ns.CreateMinimapButton()
  ns.CreateTargetFrame()
  ns.WhenOutOfCombat(ns.CreateFocusFrames)
  if ns.ApplyPanels then ns.ApplyPanels() end

  local up = {}
  for _, role in ipairs(ns.ShownGrids()) do
    up[role] = true
    ns.WithGrid(role, BuildGrid)
  end
  for _, role in ipairs(ns.ROLES) do
    if not up[role] then
      HideGrid(role)
    end
  end

  if ns.db.hideBlizzardParty then
    ns.WhenOutOfCombat(ns.HideBlizzardParty)
  end
  if ns.db.hideBlizzardRaid then
    ns.WhenOutOfCombat(ns.HideBlizzardRaid)
  end
end
