local _, ns = ...

-- Quest tracker. Blizzard's watch list is plain text dropped on the right of
-- the screen, positioned by the game and not movable by you. This puts it in
-- a panel of its own: a header you can click to roll the list up, a position
-- dropdown for the four corners, a drag handle like every other frame, and a
-- switch to turn the whole thing off.
--
-- The list itself stays Blizzard's. Quest text, objectives and the click
-- behaviour are the game's business; we own the frame around them and where
-- it sits. The tracker is called different things on different clients, so
-- both known names are tried and /fui quests says which one was found.

local module = ns.RegisterModule({
  name = "Quests",
  title = "Quests",
})

-- The modern tracker first: a client that has it is using it, and the old
-- QuestWatchFrame may still exist beside it doing nothing.
local TRACKER_NAMES = { "ObjectiveTrackerFrame", "QuestWatchFrame" }


module.defaults = {
  hide = false,
  strip = true,        -- hide Blizzard's own headers and gold artwork
  restyleText = true,
  fontSize = 12,
  opacity = 75,        -- how solid the panel behind the list is
  autoHeight = true,   -- the panel follows the length of the list
  nearbyOnly = true,   -- track only the few nearest quests, not all of them
  maxShown = 5,        -- how many the tracker keeps
  pruneLevelGap = 6,   -- "drop these" suggestions: this far below your level
  collapsed = false,
  width = 260,
  height = 320,
  position = "topright",
  showHeader = true,
  ownList = true,       -- ForeverUI's own drawn list (tabs, badges, distances) instead of Blizzard's tracker
  showCompleted = true,
  trackedOnly = false,  -- the game's own behaviour: only quests you ticked in the log
  guideOnAccept = true, -- open the quest guide when you pick a quest up
  -- ...and with a controller: off, because the guide is a mouse window that
  -- B doesn't close (Altiokis on CurseForge, 2 Oct 2026).
  guideOnAcceptPad = false,
}

module.options = {
  { type = "heading", label = "Quest tracker" },
  { type = "checkbox", key = "ownList", label = "ForeverUI's own quest list (tabs, badges, distances)", reload = true },
  { type = "checkbox", key = "showCompleted", label = "Show completed quests in the list" },
  { type = "checkbox", key = "trackedOnly", label = "Only tracked quests",
    desc = "Off: every quest in your log. On: only the ones ticked in the quest log, which is what the game does." },
  { type = "checkbox", key = "hide", label = "Hide the quest tracker" },
  { type = "checkbox", key = "guideOnAccept", label = "Open the quest guide when I pick up a quest" },
  { type = "checkbox", key = "guideOnAcceptPad", label = "...also when playing with a controller",
    desc = "Off: with the controller interface on, picking up a quest leaves the guide closed. Open it from the quest list any time." },
  { type = "stepper", key = "width", label = "Width", min = 160, max = 480, step = 10 },
  { type = "stepper", key = "height", label = "Height", min = 120, max = 700, step = 20 },
  { type = "checkbox", key = "showHeader", label = "Show the header bar" },
  { type = "checkbox", key = "strip", label = "Strip Blizzard's headers and artwork", reload = true },
  { type = "checkbox", key = "restyleText", label = "Use ForeverUI's font", reload = true },
  { type = "stepper", key = "fontSize", label = "Text size", min = 8, max = 20, step = 1 },
  { type = "stepper", key = "opacity", label = "Background", min = 0, max = 100, step = 5,
    format = function(v) return ("%d%%"):format(v) end },
  { type = "checkbox", key = "autoHeight", label = "Fit the panel to the list" },
  { type = "heading", label = "Which quests" },
  { type = "checkbox", key = "nearbyOnly", label = "Track only the nearest quests" },
  { type = "stepper", key = "maxShown", label = "How many to show", min = 3, max = 20, step = 1 },
  { type = "action", label = "Open the quest log", width = 200,
    onClick = function() ns.GetModule("Quests").OpenLog() end },
  { type = "action", label = "Suggest quests to drop", width = 200,
    onClick = function() ns.GetModule("Quests").SuggestPrune() end },
  { type = "note", label = "The tracker keeps the nearest few; the rest stay in the quest log. Suggestions list low-level or far-off quests you could abandon -- it never drops one for you." },
  { type = "action", label = "Roll the list up", width = 200,
    labelFor = function()
      return ns.db.modules.Quests.collapsed and "Roll the list down" or "Roll the list up"
    end,
    onClick = function() ns.GetModule("Quests").ToggleCollapsed() end },
  { type = "note", label = "Move the quest list with /fui move (Quick Setup: Move frames)." },
}

local panel, header, arrow, tracker

local function Settings()
  return ns.db.modules.Quests
end

-- Shared with the other modules that have to work around Blizzard's frames.
local Regions, Walk = ns.Skin.Regions, ns.Skin.Walk
module.Walk = Walk

---------------------------------------------------------------------------
-- Which quests the tracker carries
---------------------------------------------------------------------------
--
-- The owner runs with a full log, and the tracker shows every watched quest
-- at once -- it runs off the screen. So keep only the nearest few tracked,
-- and leave the rest in the quest log (a button opens it). On this client
-- the quest APIs are "secret": a questID may be a value addon code can hold
-- and hand back but never compare or branch on, and a distance may arrive
-- secret too. Everything here is guarded; if the client refuses a read, the
-- feature quietly does less rather than throwing (which would taint us).

-- Read C_QuestLog fresh each call, not cached at load: it may not exist yet
-- when this file runs, and the tests swap it in.
local issecret = _G.issecretvalue

local function WatchCount()
  if C_QuestLog and C_QuestLog.GetNumQuestWatches then
    local ok, n = pcall(C_QuestLog.GetNumQuestWatches)
    if ok and type(n) == "number" then
      return n
    end
  end
  return 0
end

-- Squared distance to a quest as a PLAIN number, or nil when it's unknown or
-- secret. A secret number would throw the moment it's compared, so it's
-- dropped here rather than carried into the sort.
local function QuestDistance(qid)
  if not (C_QuestLog and C_QuestLog.GetDistanceSqToQuest) then
    return nil
  end
  local ok, d = pcall(C_QuestLog.GetDistanceSqToQuest, qid)
  if not ok or type(d) ~= "number" then
    return nil
  end
  if issecret and issecret(d) then
    return nil
  end
  return d
end
module.QuestDistance = QuestDistance

-- The watched quests, each with its distance when the client gives a plain
-- one. IDs are held opaque and only ever handed back to the watch API.
local function WatchedQuests()
  local list = {}
  if not (C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex) then
    return list
  end
  for i = 1, WatchCount() do
    local ok, qid = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
    if ok and type(qid) ~= "nil" then
      list[#list + 1] = { id = qid, dist = QuestDistance(qid) }
    end
  end
  return list
end
module.WatchedQuests = WatchedQuests

-- The nearest-few cap is applied where the list is DRAWN (QuestList.lua), not
-- by taking quests off the game's watch list. RemoveQuestWatch from addon code
-- fires QUEST_WATCH_LIST_CHANGED on the spot, Blizzard's tracker marks itself
-- dirty inside our call, and its next redraw runs tainted -- for the rest of
-- the session, since that pass writes the tracker's own dirty flag. The
-- scenario part of that redraw reads the player's auras (Blizzard_MawBuffs),
-- which is fr0st6yt3's "Auras cannot be accessed when secret" error.

-- The full quest log. Not opened from here: ToggleQuestLog goes through the
-- panel manager, and calling it from addon code breaks the character sheet
-- for the rest of the session (see ns.Skin.OpenHint). Say the key instead.
local function OpenLog()
  return ns.Skin.OpenHint("questlog")
end
module.OpenLog = OpenLog

-- Quests worth abandoning: well below your level, or nowhere near you. Only
-- ever listed -- abandoning is destructive and stays the player's to do, in
-- the quest log this opens alongside.
local function SuggestPrune()
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
    ns.Print("this client won't list quests to weigh up.")
    return {}
  end
  local myLevel = (UnitLevel and UnitLevel("player")) or 0
  local gap = Settings().pruneLevelGap or 6
  local ok, shown = pcall(C_QuestLog.GetNumQuestLogEntries)
  if not ok or type(shown) ~= "number" then
    return {}
  end
  local candidates = {}
  for i = 1, shown do
    local iok, info = pcall(C_QuestLog.GetInfo, i)
    if iok and type(info) == "table" then
      local hok, isHeader = ns.Secrets.Measure(function() return info.isHeader and true or false end)
      if hok and not isHeader then
        -- Low-level is read through the guard: the level can be secret, and
        -- subtracting it would throw.
        local low = false
        local lok, isLow = ns.Secrets.Measure(function()
          return type(info.level) == "number" and (myLevel - info.level) >= gap
        end)
        if lok then low = isLow end
        local far = type(info.questID) ~= "nil" and QuestDistance(info.questID) == nil
        if low or far then
          local title = type(info.title) == "string" and info.title or "(a quest)"
          candidates[#candidates + 1] = { title = title, low = low, far = far }
        end
      end
    end
  end
  module.pruneCandidates = candidates
  if #candidates == 0 then
    ns.Print("nothing obvious to drop -- your quests are near and about your level.")
  else
    ns.Print(("%d quest%s you could drop (abandon them in the log):"):format(
      #candidates, #candidates == 1 and "" or "s"))
    for _, c in ipairs(candidates) do
      local why = c.low and (c.far and "low-level, far away" or "low-level")
        or "far away"
      print(("  |cffffd100%s|r -- %s"):format(c.title, why))
    end
  end
  return candidates
end
module.SuggestPrune = SuggestPrune

local function FindTracker()
  for _, name in ipairs(TRACKER_NAMES) do
    local frame = _G[name]
    if frame then
      module.trackerName = name
      return frame
    end
  end
  module.trackerName = nil
  return nil
end
module.FindTracker = FindTracker

-- Our panel hangs off the TRACKER, never the other way round. Moving the
-- tracker -- SetParent/SetPoint on an Edit Mode system frame -- taints its
-- layout, and on this client that pass reads auras and dies in combat. So
-- the tracker stays where Edit Mode puts it; we anchor our own panel to its
-- top-left, header above, and sit a level behind so the quest text is on top.

local anchoring = false

local function Anchor()
  if not tracker or not panel or anchoring then
    return false
  end
  anchoring = true
  local settings = Settings()
  local headerH = settings.showHeader and 24 or 6
  -- The modern tracker reserves a tall empty band above its first quest
  -- line. Left alone, our header sits at the tracker's top edge and the
  -- quests float far below it. Drop the panel (and the header with it) by
  -- that gap so the blue header sits right on top of the first quest.
  local gap = (module.MeasureGap and module.MeasureGap()) or 0
  module.gap = gap
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", tracker, "TOPLEFT", -8, headerH - gap)
  if tracker.GetFrameStrata and panel.SetFrameStrata then
    local ok, strata = pcall(tracker.GetFrameStrata, tracker)
    if ok and strata then pcall(panel.SetFrameStrata, panel, strata) end
  end
  if tracker.GetFrameLevel and panel.SetFrameLevel then
    local ok, lvl = pcall(tracker.GetFrameLevel, tracker)
    if ok and type(lvl) == "number" then pcall(panel.SetFrameLevel, panel, math.max(0, lvl - 1)) end
  end
  anchoring = false
  return true
end
module.Anchor = Anchor

-- Adopt just remembers the tracker and puts our panel where it is. It does
-- NOT reparent it, move it, take it off the layout list, or hook its own
-- methods -- every one of those taints the Edit Mode tracker. Our strips and
-- restyles come from quest EVENTS (below), never from inside its update pass.
local function Adopt(frame)
  tracker = frame
  local ok, prot = pcall(function() return frame.IsProtected and frame:IsProtected() and true or false end)
  module.trackerProtected = ok and prot or false
  Anchor()
end

-- `chosen` means someone just picked a corner from the dropdown, which is
-- allowed to throw away a position they dragged to earlier. Startup is not:
-- it only sets where the frame goes if it has never been dragged, or the
-- tracker would jump back to its corner on every login.

-- The panel is as tall as the list when it's up, or just the header when
-- it's rolled away. Measuring is guarded: the tracker's height can be zero
-- for a frame after it's re-shown, before it has rebuilt.
-- How tall the VISIBLE list actually is. Not tracker:GetHeight() -- the
-- modern tracker frame reserves most of the screen, so that gives a panel
-- the height of the screen with a huge empty box under the quests. Measure
-- from the tracker's top edge down to the bottom of the lowest line on
-- screen instead (the mirror of MeasureGap, which finds the top). Text can
-- be secret; text the game shows but won't let us read still counts.
local function ContentExtent()
  if not tracker or not tracker.GetTop then
    return nil
  end
  local top = tracker:GetTop()
  if not top then
    return nil
  end
  local lowest
  Walk(tracker, function(frame)
    if frame == tracker or not frame.GetBottom then
      return
    end
    if (frame.IsShown and not frame:IsShown()) or (frame.GetAlpha and frame:GetAlpha() == 0) then
      return
    end
    for _, region in ipairs(Regions(frame)) do
      if region.GetObjectType and region:GetObjectType() == "FontString"
        and (not region.IsShown or region:IsShown())
        and not (region.GetAlpha and region:GetAlpha() == 0) then
        local text = ns.Skin.Text(region)
        local hasText
        if text == nil then
          local ok, raw = pcall(region.GetText, region)
          hasText = ok and raw ~= nil
        else
          hasText = text ~= ""
        end
        if hasText then
          local bottom = frame:GetBottom()
          if bottom and bottom < top and (not lowest or bottom < lowest) then
            lowest = bottom
          end
          break
        end
      end
    end
  end)
  if not lowest then
    return nil
  end
  return math.max(0, math.floor(top - lowest + 0.5))
end
module.ContentExtent = ContentExtent

local function ContentHeight()
  local settings = Settings()
  if settings.autoHeight then
    local extent = ContentExtent()
    if extent and extent > 0 then
      -- ContentExtent measures from the tracker's top down to the last
      -- line, so it includes the empty band above the first quest. The
      -- panel now starts at the first quest (Anchor drops it by the gap),
      -- so the box is only as tall as the list itself.
      local gap = (module.MeasureGap and module.MeasureGap()) or 0
      local list = math.max(0, extent - gap)
      return list + (settings.showHeader and 34 or 12)
    end
  end
  return settings.height
end

local function ApplyHeight()
  if not panel then
    return 0
  end
  local settings = Settings()
  local height = settings.collapsed and 24 or ContentHeight()
  panel:SetHeight(height)
  module.panelHeight = height
  return height
end
module.ApplyHeight = ApplyHeight

-- Out of sight without Hide.
--
-- The tracker is an Edit Mode frame that UIParent's right-hand frame manager
-- lays out. Hide, Show and SetShown fire its OnHide/OnShow, and those tell
-- the manager to take it off (or put it back on) its list -- and when that
-- runs from inside our code, the manager's tables are written with our
-- taint. Even the C originals (HideBase) fire the scripts. The next Edit
-- Mode layout pass reads those tables, updates the tracker tainted, and on
-- Forever the scenario section of that update reads an aura and dies:
-- "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted
-- by 'ForeverUIApp'" (26 Sept 2026, through EditModeManager's
-- InvokeOnAnyEditModeSystemAnchorChanged and through the tracker's own
-- next-frame update). SetCollapsed and Update are the same story: Blizzard
-- code run from ours writes tainted state.
--
-- So nothing here shows, hides, collapses or updates the tracker. It is
-- made transparent, and the mouse is taken off whatever of it takes the
-- mouse, so invisible lines don't eat clicks. Neither fires a script or
-- runs any Blizzard Lua. The tracker keeps updating itself, unseen.
local deafened = setmetatable({}, { __mode = "k" })

local function Veil(root, hidden)
  if not root then
    return 0
  end
  if root.SetAlpha then
    root:SetAlpha(hidden and 0 or 1)
  end
  local count = 0
  Walk(root, function(frame)
    if hidden then
      if frame.IsMouseEnabled and frame.EnableMouse then
        local ok, on = pcall(frame.IsMouseEnabled, frame)
        if ok and on == true then
          deafened[frame] = true
          pcall(frame.EnableMouse, frame, false)
          count = count + 1
        end
      end
    elseif deafened[frame] then
      deafened[frame] = nil
      pcall(frame.EnableMouse, frame, true)
      count = count + 1
    end
  end)
  if root == tracker then
    module.veiled = hidden
  end
  return count
end
module.Veil = Veil

-- Rolled up = veiled. Returns true: the tracker was never asked to change.
local function SetTrackerCollapsed(collapsed)
  if not tracker then
    return false
  end
  Veil(tracker, collapsed)
  return true
end

local function ApplyCollapsed()
  local collapsed = Settings().collapsed and true or false
  SetTrackerCollapsed(collapsed)
  if arrow then
    arrow:SetText(collapsed and "+" or "-")
  end
  if not collapsed then
    Anchor()   -- expanding must not leave it wherever the game put it
  end
  ApplyHeight()
  -- The rebuild lands over the next frame, so the true height isn't known
  -- this one. Measure again once it has -- this is what fills the empty box.
  if not collapsed and C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if not Settings().collapsed then
        Anchor()
        ApplyHeight()
      end
    end)
  end
end
module.ApplyCollapsed = ApplyCollapsed

function module.ToggleCollapsed()
  Settings().collapsed = not Settings().collapsed
  if Settings().ownList ~= false and module.RefreshList then
    module.RefreshList()
  else
    ApplyCollapsed()
  end
  ns.RefreshOptions()
  return Settings().collapsed
end

-- Every piece of text in the tracker takes our font at our size. Colour is
-- left alone: the game colours quest names by difficulty and that's worth
-- keeping. Blizzard rebuilds these lines as quests come and go, so this runs
-- again on every update rather than once.
local function Restyle()
  if not tracker or not Settings().restyleText then
    return 0
  end
  local path, _, outline = ns.Media.Role("general")
  local size = Settings().fontSize
  local styled = 0
  Walk(tracker, function(frame)
    for _, region in ipairs(Regions(frame)) do
      if region.GetObjectType and region:GetObjectType() == "FontString" and region.SetFont then
        region:SetFont(path, size, outline ~= "" and outline or nil)
        styled = styled + 1
      end
    end
  end)
  -- Older clients keep their lines as globals rather than children.
  for index = 1, 30 do
    local line = _G["QuestWatchLine" .. index]
    if not line then
      break
    end
    if line.SetFont then
      line:SetFont(path, size, outline ~= "" and outline or nil)
      styled = styled + 1
    end
  end
  module.styled = styled
  return styled
end
module.Restyle = Restyle

---------------------------------------------------------------------------
-- Blizzard's own furniture
---------------------------------------------------------------------------
--
-- The modern tracker draws its own "All Objectives" bar and a gold-framed
-- header per section, which is two headers too many once this module has
-- drawn one. Rather than naming every texture -- they differ between builds
-- and there are a lot of them -- each header frame is found and every texture
-- region on it is faded out. Only header frames are touched, so quest icons
-- and objective text are left alone.

local HEADER_PATHS = {
  "HeaderMenu",
  "BlocksFrame.QuestHeader",
  "BlocksFrame.AchievementHeader",
  "BlocksFrame.ScenarioHeader",
  "BlocksFrame.ProfessionHeader",
}

local HEADER_GLOBALS = {
  "ObjectiveTrackerBlocksFrameHeader", "ObjectiveTrackerFrameHeaderMenuTitle",
  "QuestWatchFrameTitle", "ObjectiveTrackerFrameHeaderMenu",
}

-- The header artwork comes from a handful of texture files and atlases. Quest
-- icons and objective text don't, so matching on these finds the furniture
-- without touching the list itself -- and it works whatever this client
-- happens to call the frames, which naming them one by one did not.
local ORNAMENT = {
  "objectivetracker", "objective%-header", "objectiveheader",
  "questlogtitle", "ui%-questlog%-splitter", "questobjective",
}

-- The other half of a header is its label and its minimize button. Fading the
-- artwork leaves those behind, which is how you end up reading "Quests" twice
-- with three collapse controls, only one of which is ours.
--
-- The game's own strings are used rather than the English words, so this holds
-- on a client in any language.
local function HeaderLabels()
  local labels = {}
  for _, name in ipairs({
    "OBJECTIVES_TRACKER_LABEL", "TRACKER_HEADER_QUESTS", "QUESTS_LABEL",
    "TRACKER_HEADER_ACHIEVEMENTS", "TRACKER_HEADER_CAMPAIGN_QUESTS",
    "TRACKER_HEADER_PROFESSION_QUESTS", "TRACKER_HEADER_SCENARIO",
    "TRACKER_HEADER_BONUS_OBJECTIVES", "TRACKER_HEADER_WORLD_QUESTS",
    "TRACKER_HEADER_ADVENTURE", "TRACKER_HEADER_ENDEAVORS", "TRACKER_HEADER_PROFESSION",
    "TRACKER_HEADER_TRAVELERS_LOG", "TRACKER_HEADER_DUNGEON", "TRACKER_HEADER_DELVES",
    "TRACKER_HEADER_MONTHLY_ACTIVITIES",
  }) do
    local text = _G[name]
    if type(text) == "string" and text ~= "" then
      labels[text:lower():gsub("^%s+", ""):gsub("%s+$", "")] = true
    end
  end
  -- A client that doesn't define them still gets the common two.
  -- What this client's tracker was seen calling its sections.
  for _, text in ipairs({
    "all objectives", "quests", "objectives", "achievements", "campaign",
    "bonus objectives", "world quests", "profession", "endeavors", "traveler's log",
    "adventure", "scenario", "dungeon", "delves", "quest timers", "challenges",
    "stage complete",
  }) do
    labels[text] = true
  end
  return labels
end
module.HeaderLabels = HeaderLabels

local function IsOrnament(texture)
  return ns.Skin.TextureMatches(texture, ORNAMENT)
end

-- "BlocksFrame.QuestHeader" -> the frame, if this client has one.
local function Resolve(root, path)
  local node = root
  for part in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = rawget(node, part)
  end
  return type(node) == "table" and node or nil
end

local function Fade(frame)
  if not frame then
    return 0
  end
  local faded = 0
  for _, region in ipairs(Regions(frame)) do
    if region.GetObjectType and region:GetObjectType() == "Texture" and region.SetAlpha then
      region:SetAlpha(0)
      faded = faded + 1
    end
  end
  -- Faded, not hidden: Hide fires Blizzard's OnHide from our code (see Veil).
  return faded + Veil(frame, true) + 1
end

-- Hiding the headers doesn't close the space they held: whatever hangs below
-- them stays put, leaving a blank slab at the top. Guessing that slab from
-- the headers' heights went wrong twice -- headers of empty sections are
-- momentarily showing at login and held no space at all. So it's measured:
-- the tracker's top edge down to the top of the first thing still showing
-- with text on it, which after the strip is the first quest. Positions are
-- ours to read, and the tracker's inside doesn't change with where it sits,
-- so this is exact and settles on the first pass.
local function MeasureGap()
  if not tracker or not tracker.GetTop then
    return 0
  end
  local top = tracker:GetTop()
  local seen = { readable = 0, secret = 0, topless = 0, hidden = 0, trackerTop = top }
  module.gapSeen = seen
  if not top then
    return 0
  end
  local highest
  Walk(tracker, function(frame)
    if frame == tracker or not frame.GetTop then
      return
    end
    if (frame.IsShown and not frame:IsShown()) or (frame.GetAlpha and frame:GetAlpha() == 0) then
      seen.hidden = seen.hidden + 1
      return
    end
    -- A quest line is any showing frame with text on it. The text may be
    -- SECRET on this client -- readable text counts, and so does text the
    -- game will show but not let us read: it is still there on screen, and
    -- there is all the measure needs to know.
    for _, region in ipairs(Regions(frame)) do
      if region.GetObjectType and region:GetObjectType() == "FontString"
        and (not region.IsShown or region:IsShown())
        and not (region.GetAlpha and region:GetAlpha() == 0) then
        local text = ns.Skin.Text(region)
        local hasText = false
        if text == nil then
          local ok, raw = pcall(region.GetText, region)
          if ok and raw ~= nil then
            seen.secret = seen.secret + 1
            hasText = true
          end
        elseif text ~= "" then
          seen.readable = seen.readable + 1
          hasText = true
        end
        if hasText then
          local frameTop = frame:GetTop()
          if not frameTop then
            seen.topless = seen.topless + 1
          -- Only something BELOW the tracker's top edge can be its first
          -- quest. Section headers of other modules hang at, or a pixel
          -- above, that edge; taken for the first quest they measured the
          -- gap as nothing, and the blank band stayed.
          elseif frameTop < top - 0.5 and (not highest or frameTop > highest) then
            highest = frameTop
          end
          break
        end
      end
    end
  end)
  seen.highest = highest
  if not highest then
    return 0
  end
  return math.max(0, math.floor(top - highest + 0.5))
end
module.MeasureGap = MeasureGap

local function StripTracker()
  if not tracker or not Settings().strip then
    return 0, {}
  end
  local count, found = 0, {}

  -- The named ones first, where this client has them.
  for _, path in ipairs(HEADER_PATHS) do
    local frame = Resolve(tracker, path)
    if frame then
      found[#found + 1] = path
      count = count + Fade(frame)
    end
  end
  for _, name in ipairs(HEADER_GLOBALS) do
    if _G[name] then
      found[#found + 1] = name
      count = count + Fade(_G[name])
    end
  end

  -- Then anything wearing header artwork or carrying a header label, named or
  -- not: its artwork, its text and its collapse button all go, leaving one
  -- header -- ours -- with one control that works.
  local labels = HeaderLabels()
  Walk(tracker, function(frame)
    if frame == tracker then
      return
    end
    local isHeader = false
    for _, region in ipairs(Regions(frame)) do
      local kind = region.GetObjectType and region:GetObjectType()
      if kind == "Texture" and IsOrnament(region) then
        isHeader = true
      elseif kind == "FontString" then
        -- Read through the guard: quest text can be a secret string, and
        -- matching on one raises and taints us.
        local lowered = ns.Skin.Text(region)
        if lowered then
          -- Trimmed: a header that pads its label differently is still one.
          local key = lowered:gsub("^%s+", ""):gsub("%s+$", "")
          if labels[key] then
            isHeader = true
          end
        end
      end
    end
    if not isHeader then
      return
    end

    found[#found + 1] = (frame.GetName and frame:GetName()) or "(unnamed header)"
    -- Everything faded, nothing hidden and no text changed: Hide fires
    -- Blizzard's scripts from our code, and the header's label is an
    -- auto-scaling font string whose SetText is Blizzard Lua (see Veil).
    for _, region in ipairs(Regions(frame)) do
      if region.SetAlpha then
        region:SetAlpha(0)
        count = count + 1
      end
    end
    -- The header, its minimize button with it, see-through and deaf.
    count = count + Veil(frame, true) + 1
  end)

  module.stripped, module.strippedFrames = count, found
  module.reclaimed = MeasureGap()
  return count, found
end
module.StripTracker = StripTracker

-- What this client actually calls things, for when the guesses are wrong.
function module.Dump()
  ns.Print(("tracker: %s"):format(module.trackerName or "none found"))
  if not tracker then
    return
  end
  local children = {}
  for _, child in ipairs({ tracker:GetChildren() }) do
    local name = child.GetName and child:GetName()
    children[#children + 1] = name or "(unnamed)"
  end
  ns.Print(("children: %s"):format(#children > 0 and table.concat(children, ", ") or "none"))
  ns.Print(("headers stripped: %s"):format(
    module.strippedFrames and #module.strippedFrames > 0
      and table.concat(module.strippedFrames, ", ") or "none"))
  ns.Print(("%d pieces of artwork faded, %d lines restyled"):format(
    module.stripped or 0, module.styled or 0))
  local seen = module.gapSeen or {}
  ns.Print(("gap: %s px (tracker top %s, first quest top %s; %d readable, %d secret, %d without a top, %d hidden)"):format(
    tostring(module.reclaimed), tostring(seen.trackerTop), tostring(seen.highest),
    seen.readable or 0, seen.secret or 0, seen.topless or 0, seen.hidden or 0))

  -- The walk itself, frame by frame, including the ones the guard steps
  -- around: if a header is being missed, this says where it is hiding.
  local labels = HeaderLabels()
  local lines, skipped = {}, 0
  local function trace(frame, depth)
    if depth > 6 then
      return
    end
    local ok, forbidden = pcall(function()
      return frame.IsForbidden and frame:IsForbidden()
    end)
    local name = (frame.GetName and frame:GetName()) or "(unnamed)"
    if not ok or forbidden then
      skipped = skipped + 1
      lines[#lines + 1] = ("%s|cffff6666FORBIDDEN|r %s"):format(("  "):rep(depth), name)
      return
    end
    local texts, textures = {}, 0
    for _, region in ipairs(Regions(frame)) do
      local kind = region.GetObjectType and region:GetObjectType()
      if kind == "FontString" then
        local text = ns.Skin.Text(region)
        texts[#texts + 1] = text and ('"' .. text:sub(1, 24) .. '"' .. (labels[text:gsub("^%s+", ""):gsub("%s+$", "")] and "|cff4dc3ff=header|r" or ""))
          or "(secret)"
      elseif kind == "Texture" then
        textures = textures + 1
      end
    end
    if #texts > 0 or textures > 0 then
      lines[#lines + 1] = ("%s%s%s: %d tex %s"):format(("  "):rep(depth), name,
        (frame.IsShown and not frame:IsShown()) and " (hidden)" or "", textures, table.concat(texts, " "))
    end
    local okKids, kids = pcall(function() return { frame:GetChildren() } end)
    if okKids then
      for _, child in ipairs(kids) do
        trace(child, depth + 1)
      end
    end
  end
  trace(tracker, 0)
  ns.Print(("walk: %d frames with something on them, %d stepped around as forbidden"):format(#lines, skipped))
  for _, line in ipairs(lines) do
    print(line)
  end
  -- And to disk, so it can be read at leisure rather than off six lines of chat.
  ns.db.questDiagnostics = {
    when = date and date() or "?",
    tracker = module.trackerName,
    gap = module.reclaimed,
    trackerTop = seen.trackerTop,
    firstQuestTop = seen.highest,
    readable = seen.readable, secret = seen.secret, topless = seen.topless, hidden = seen.hidden,
    stripped = module.stripped, styled = module.styled,
    walk = lines,
  }
end

local function Build()
  panel = CreateFrame("Frame", "ForeverUIQuests", UIParent)
  panel:SetSize(Settings().width, Settings().height)
  -- A backdrop, not a window: clicks belong to the quest list inside it.
  panel:EnableMouse(false)
  ns.Skin.Panel(panel, { color = { 0.06, 0.06, 0.08, 0.55 } })

  header = CreateFrame("Button", nil, panel)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(22)
  ns.Skin.Panel(header, { color = { 0.10, 0.10, 0.13, 1 }, border = false })

  local title = header:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(title, "general")
  title:SetPoint("LEFT", 8, 0)
  title:SetText("Quests")
  ns.Skin.AccentText(title)
  header.title = title

  arrow = header:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(arrow, "general")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetTextColor(unpack(ns.Colors.ui.textDim))
  header.arrow = arrow

  header:RegisterForClicks("AnyUp")
  header:SetScript("OnClick", function() module.ToggleCollapsed() end)

  module.panel, module.header = panel, header

  -- Keep our fonts on the list as the game rewrites it.
  -- Whenever the game rebuilds the list, ours has to follow: the headers
  -- come back shown, with their text set and their artwork's alpha restored.
  -- Strip first: that is what measures the gap the anchor then closes. The
  -- other way round, the first pass anchors on last pass's number -- zero
  -- at login -- and a blank band sits under the header until the next
  -- quest event happens to fix it.
  local function Reapply()
    local settings = Settings()
    if settings.hide or settings.ownList ~= false then
      -- Blizzard's list isn't on show: only keep new lines off the mouse.
      if tracker then Veil(tracker, true) end
      return
    end
    StripTracker()
    Restyle()
    Anchor()
    if not Settings().collapsed then
      ApplyHeight()
    end
  end
  module.Reapply = Reapply
  for _, name in ipairs({ "QuestWatch_Update", "ObjectiveTracker_Update" }) do
    if hooksecurefunc and type(_G[name]) == "function" then
      hooksecurefunc(name, Reapply)
    end
  end
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({
    "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
  }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      -- Blizzard sets its tracker up on this same event; catch any module
      -- it hooked up after our pass.
      module.SilenceIfOffScreen()
      if C_Timer and C_Timer.After then C_Timer.After(1, module.SilenceIfOffScreen) end
    end
    if tracker then
      Reapply()
    end
  end)
  module.watcher = watcher
  local manager = _G.ObjectiveTrackerManager
  if hooksecurefunc and type(manager) == "table" and type(manager.SetModuleContainer) == "function" then
    hooksecurefunc(manager, "SetModuleContainer", function(_, trackerModule)
      if module.TrackerOffScreen() and type(trackerModule) == "table" and trackerModule.UnregisterAllEvents then
        pcall(trackerModule.UnregisterAllEvents, trackerModule)
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Blizzard's tracker, off the events while it's off screen
---------------------------------------------------------------------------
--
-- Each part of Blizzard's tracker (quests, scenario, bonus objectives...)
-- listens for quest events and redraws a frame later. When addon code sets
-- one of those events off -- clicking a quest in our list super-tracks it,
-- which fires SUPER_TRACKING_CHANGED inside the click -- the redraw it queues
-- runs tainted, and that pass writes the tracker's own dirty flag, so every
-- later redraw is tainted too. The scenario part reads the player's auras on
-- each redraw (Blizzard_MawBuffs); tainted, in a fight, that is the
-- "Auras cannot be accessed when secret while tainted by 'ForeverUI'" error
-- fr0st6yt3 hit while looting. With the tracker veiled -- our own list on
-- screen, or the tracker turned off -- it has nothing to draw, so its parts
-- are taken off the events altogether and never redraw. (Turning our list
-- off is a reload, which gives them their events back.)
local MODULE_NAMES = {
  "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "ScenarioObjectiveTracker",
  "BonusObjectiveTracker", "WorldQuestObjectiveTracker", "AchievementObjectiveTracker",
  "AdventureObjectiveTracker", "ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker",
  "InitiativeTasksObjectiveTracker", "UIWidgetObjectiveTracker",
}

local function TrackerModules()
  local found, seen = {}, {}
  local function add(m)
    if type(m) == "table" and not seen[m] and type(m.UnregisterAllEvents) == "function" then
      seen[m] = true
      found[#found + 1] = m
    end
  end
  local manager = _G.ObjectiveTrackerManager
  if type(manager) == "table" and type(manager.moduleToContainerMap) == "table" then
    for m in pairs(manager.moduleToContainerMap) do add(m) end
  end
  for _, name in ipairs(MODULE_NAMES) do add(_G[name]) end
  return found
end
module.TrackerModules = TrackerModules

function module.TrackerOffScreen()
  local settings = Settings()
  return settings.hide == true or (settings.ownList ~= false and module.ShowList ~= nil)
end

function module.SilenceTracker()
  local n = 0
  for _, m in ipairs(TrackerModules()) do
    if pcall(m.UnregisterAllEvents, m) then n = n + 1 end
  end
  module.silenced = n
  return n
end

function module.SilenceIfOffScreen()
  if module.TrackerOffScreen() then
    return module.SilenceTracker()
  end
  return 0
end

local function Apply()
  local settings = Settings()
  if settings.hide then
    panel:Hide()
    if module.ShowList then module.ShowList(false) end
    tracker = FindTracker() or tracker
    Veil(tracker, true)   -- never Hide: see Veil
    module.SilenceTracker()
    return
  end
  if settings.ownList ~= false and module.ShowList then
    -- Our own drawn list: Blizzard's tracker goes away (through the C
    -- original, and with its events off so it can't put itself back), and
    -- the dressing-up panel with it.
    panel:Hide()
    tracker = FindTracker() or tracker
    if tracker then
      if tracker.UnregisterAllEvents then pcall(tracker.UnregisterAllEvents, tracker) end
      Veil(tracker, true)   -- never Hide: see Veil
    end
    module.SilenceTracker()
    module.ShowList(true)
    return
  elseif module.ShowList then
    module.ShowList(false)
  end
  if (module.silenced or 0) > 0 then
    -- Blizzard's list is wanted back, but its parts were taken off the
    -- events this session (see SilenceTracker); only a reload restores them.
    module.silenced = 0
    if ns.RequestReload then ns.RequestReload("Showing Blizzard's quest tracker again") end
  end
  -- Looked up every time rather than cached: some clients build the tracker
  -- lazily, so one that wasn't there at login can turn up later.
  tracker = FindTracker() or tracker
  if not tracker or not module.trackerName then
    -- Nothing to frame. An empty black box on screen is worse than nothing.
    panel:Hide()
    return
  end
  panel:Show()
  panel:SetWidth(settings.width)
  header:SetShown(settings.showHeader)
  ns.Skin.SetPanelColor(panel, { 0.05, 0.05, 0.07, (settings.opacity or 75) / 100 })

  if tracker then
    Adopt(tracker)
    Restyle()
    StripTracker()   -- measures the gap; ApplyCollapsed below re-anchors with it
  end
  ApplyCollapsed()
end
module.Apply = Apply

function module:OnEnable()
  ns.WhenOutOfCombat(function()
    if not panel then
      Build()
    end
    Apply()
  end)
end

function module:OnDisable()
  ns.WhenOutOfCombat(function()
    if panel then
      panel:Hide()
    end
  end)
end

function module:Refresh()
  ns.WhenOutOfCombat(function()
    if not panel then
      Build()
    end
    Apply()
  end)
end
