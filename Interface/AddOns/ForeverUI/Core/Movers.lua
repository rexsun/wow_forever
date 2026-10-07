local _, ns = ...

-- The mover system. A module registers a frame once; from then on the frame's
-- position belongs to the profile, and `/fui move` shows a labelled handle for
-- every registered frame so the whole UI can be arranged by dragging.
--
-- Frames are anchored to their mover, never the other way round, so a secure
-- frame is never moved directly - and nothing moves during combat.

local movers = {}
ns.movers = movers

local overlayShown = false

local function SavedPosition(name)
  return ns.db.movers[name]
end

-- Where a frame goes when it hasn't been dragged: the owner's standard for
-- it if there is one, otherwise where the code put it.
local function StandardPosition(name)
  local standard = ns.STANDARD and ns.STANDARD.movers
  return standard and standard[name]
end

-- Precedence: where you dragged it; then where its module put it (a bar
-- stacked on the one below, a corner picked from the quest dropdown); then
-- the standard; then wherever the code first registered it.
local function ApplyPosition(mover)
  local saved = SavedPosition(mover.moverName)
    or (mover.defaultExplicit and mover.defaultPosition)
    or StandardPosition(mover.moverName)
    or mover.defaultPosition
  mover:ClearAllPoints()
  mover:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
end

-- Snap to the screen's centre lines when close, which is most of what people
-- want from snapping and costs nothing in complexity.
local SNAP = 12
local GRID = 8   -- "Snap to grid" (Unit Frames > General): positions land on multiples of this
local function Snapped(mover)
  local point, _, relativePoint, x, y = mover:GetPoint()
  local centreX = math.abs(x) < SNAP and point:find("LEFT") == nil and point:find("RIGHT") == nil
  if centreX then
    x = 0
  end
  if ns.db and ns.db.moverGrid then
    x = math.floor(x / GRID + 0.5) * GRID
    y = math.floor(y / GRID + 0.5) * GRID
  end
  return point, relativePoint, x, y
end
ns.MoverSnapped = Snapped

-- A handle is either something you drag or something that isn't there.
--
-- It sits over its frame at HIGH strata, and EnableMouse(false) alone did not
-- stop it taking the mouse on this client: every frame with a handle was
-- unclickable, and "clicking" one dragged it. So when the handles are put
-- away they give up everything that could catch a click -- the mouse, mouse
-- motion, the drag registration -- and drop below everything else. When
-- they come out, they take it all back.
local function SetInteractive(mover, on)
  mover:EnableMouse(on)
  if mover.EnableMouseMotion then
    mover:EnableMouseMotion(on)
  end
  if on then
    mover:RegisterForDrag("LeftButton")
  else
    mover:RegisterForDrag()
  end
  if mover.SetPropagateMouseClicks then
    mover:SetPropagateMouseClicks(not on)
  end
  if mover.SetPropagateMouseMotion then
    mover:SetPropagateMouseMotion(not on)
  end
  mover:SetFrameStrata(on and "HIGH" or "BACKGROUND")
  mover.interactive = on and true or false
end
ns.SetMoverInteractive = SetInteractive

-- The frame is drawn at the handle's scale.
--
-- The handle is scaled to General > UI Scale; the frame is pinned to it by
-- its top-left corner but is not its child, so scaling the handle alone
-- never shrank the frame -- the handle shrank round its own anchor and left
-- the full-size frame hanging off it, lower and further right. That is what
-- a player saw after picking a smaller scale in the setup and reloading:
-- the action bars and micro bar out of place until /fui move (which re-fits
-- the handles) put them back (goldfish117 on CurseForge, 28 Sept 2026).
-- So the frame takes the handle's effective scale, and the handle takes the
-- frame's size through the ratio -- 1, unless a frame keeps a scale of its
-- own (fuiOwnScale: the kick alerts' own size slider).
local function ScaleFrame(mover)
  local frame = mover and mover.frame
  if not frame or frame.fuiOwnScale or not frame.SetScale or not mover.GetEffectiveScale then
    return
  end
  local parent = frame.GetParent and frame:GetParent()
  local base = parent and parent.GetEffectiveScale and parent:GetEffectiveScale()
  local want = mover:GetEffectiveScale()
  if not base or base <= 0 or not want or want <= 0 then
    return
  end
  local scale = want / base
  if frame.GetScale and math.abs((frame:GetScale() or 1) - scale) < 0.001 then
    return
  end
  if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
    ns.WhenOutOfCombat(function() ScaleFrame(mover) end)
    return
  end
  frame:SetScale(scale)
end

function ns.RegisterMover(name, label, frame, defaultPosition)
  assert(not movers[name], "mover registered twice: " .. name)

  local mover = CreateFrame("Frame", "ForeverUIMover" .. name, UIParent)
  mover.moverName, mover.label = name, label
  mover.defaultPosition = defaultPosition or { "CENTER", "CENTER", 0, 0 }
  mover:SetSize(frame:GetWidth() or 100, frame:GetHeight() or 30)
  mover:SetMovable(true)
  mover:SetClampedToScreen(true)
  SetInteractive(mover, false)

  mover.bg = mover:CreateTexture(nil, "BACKGROUND")
  mover.bg:SetAllPoints()
  mover.bg:SetColorTexture(ns.Colors.Get("ui", "accent"))
  mover.bg:SetAlpha(0.35)
  mover.bg:Hide()

  mover.text = mover:CreateFontString(nil, "OVERLAY")
  mover.text:SetPoint("CENTER")
  ns.Media.SetFont(mover.text, "general")
  mover.text:SetText(label)
  mover.text:Hide()

  mover:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then
      ns.Print("frames can't be moved in combat.")
      return
    end
    self:StartMoving()
  end)

  mover:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relativePoint, x, y = Snapped(self)
    ns.db.movers[self.moverName] = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
    ApplyPosition(self)
    if ns.RefreshOptions then
      ns.RefreshOptions()
    end
  end)

  -- Right-click a handle to put that one frame back.
  mover:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and not InCombatLockdown() then
      ns.ResetMover(self.moverName)
    end
  end)

  movers[name] = mover
  mover:SetScale(ns.db.scale or 1)
  mover.frame = frame
  ScaleFrame(mover)
  ns.FitMover(name)
  ApplyPosition(mover)

  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", mover, "TOPLEFT")
  return mover
end

-- Modules that lay themselves out (stacked action bars) set a new starting
-- position as sizes change. A frame the player has dragged keeps its own.
function ns.SetMoverDefault(name, position)
  local mover = movers[name]
  if not mover then
    return false
  end
  mover.defaultPosition = position
  mover.defaultExplicit = true   -- set by a module, so it beats the standard
  if not ns.db.movers[name] then
    ApplyPosition(mover)
  end
  return true
end

-- The handle, the exact size its frame is DRAWN at.
--
-- A handle used to take its frame's size once, when registered, and keep it.
-- The quest list then changed width (its own setting) and height (every
-- quest added or finished), and the handle did not: it stayed wider than the
-- panel, and because a handle is clamped to the screen, that invisible
-- extra strip hit the right edge first -- the panel could never be dragged
-- flush right. The frame's own scale can differ from the handle's too, so
-- the size is converted through both.
local function FitToFrame(mover)
  local frame = mover and mover.frame
  if not frame or not frame.GetWidth then
    return false
  end
  local width, height = frame:GetWidth(), frame:GetHeight()
  if not width or width <= 0 or not height or height <= 0 then
    return false
  end
  local ratio = 1
  if frame.GetEffectiveScale and mover.GetEffectiveScale then
    local mine = mover:GetEffectiveScale()
    if mine and mine > 0 then
      ratio = frame:GetEffectiveScale() / mine
    end
  end
  -- A list that grows as things are added (the quest list) keeps its top
  -- edge and grows DOWN. Pinned by its middle, every quest picked up pushed
  -- its title half a line higher, until at five quests it sat under the
  -- minimap's bottom edge (the play recorder's first capture, 27 Sept 2026).
  local top, left, right = nil, nil, nil
  if mover.growDown and mover.GetTop then
    top, left, right = mover:GetTop(), mover:GetLeft(), mover:GetRight()
  end
  mover:SetSize(width * ratio, height * ratio)
  if top and left and right then
    local point = mover:GetPoint()
    local side = type(point) == "string" and ((point:find("RIGHT") and "RIGHT") or (point:find("LEFT") and "LEFT")) or nil
    mover:ClearAllPoints()
    if side == "RIGHT" then
      mover:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    elseif side == "LEFT" then
      mover:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
      mover:SetPoint("TOP", UIParent, "BOTTOMLEFT", (left + right) / 2, top)
    end
  end
  return true
end

function ns.FitMover(name)
  return FitToFrame(movers[name])
end

-- Frames change size (a raid grid, a resized unit frame); keep the handle in step.
function ns.UpdateMoverSize(name, width, height)
  local mover = movers[name]
  if mover then
    -- The size is the frame's; the handle may be drawn at another scale.
    local ratio = 1
    local frame = mover.frame
    if frame and frame.GetEffectiveScale and mover.GetEffectiveScale then
      local mine = mover:GetEffectiveScale()
      if mine and mine > 0 then ratio = frame:GetEffectiveScale() / mine end
    end
    mover:SetSize(width * ratio, height * ratio)
  end
end

function ns.ResetMover(name)
  local mover = movers[name]
  if not mover then
    return false
  end
  ns.db.movers[name] = nil
  ApplyPosition(mover)
  return true
end

-- Clears saved positions for everything, including frames whose module is
-- currently switched off and so hasn't registered its mover this session.
function ns.ResetAllMovers()
  ns.Wipe(ns.db.movers)
  ns.ApplyMoverPositions()
  -- And the party/raid grids, which keep their own positions -- one each, so
  -- resetting has to put all three back on their own patch of screen rather
  -- than only the one being configured.
  if ns.Frames and ns.Frames.SpaceGrids then
    pcall(ns.Frames.SpaceGrids)
  elseif ns.Frames and ns.Frames.ResetPosition then
    pcall(ns.Frames.ResetPosition)
  end
end

function ns.ApplyMoverPositions()
  local scale = ns.db.scale or 1
  for _, mover in pairs(movers) do
    -- The frame rides on its mover and is drawn at its scale (ScaleFrame).
    mover:SetScale(scale)
    ScaleFrame(mover)
    FitToFrame(mover)
    ApplyPosition(mover)
  end
end

function ns.MoversShown()
  return overlayShown
end

-- The panel that comes up with the handles: what to do, and a way out that
-- isn't typing a command. Positions save the moment a handle is let go of;
-- Done just puts the handles away.
local movePanel

local function BuildMovePanel()
  movePanel = CreateFrame("Frame", "ForeverUIMovePanel", UIParent)
  movePanel:SetSize(360, 96)
  movePanel:SetPoint("TOP", UIParent, "TOP", 0, -80)
  movePanel:SetFrameStrata("DIALOG")
  movePanel:EnableMouse(true)
  ns.Skin.Panel(movePanel, { color = { 0.06, 0.06, 0.08, 0.96 } })
  ns.Skin.Header(movePanel, "Moving frames", function() ns.ToggleMovers(false) end)

  movePanel.text = movePanel:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(movePanel.text, "general")
  movePanel.text:SetPoint("TOPLEFT", 14, -36)
  movePanel.text:SetPoint("TOPRIGHT", -14, -36)
  movePanel.text:SetJustifyH("LEFT")
  movePanel.text:SetTextColor(unpack(ns.Colors.ui.text))
  movePanel.text:SetText("Drag the handles. Each one saves the moment you let go. Right-click a handle to reset it.")

  movePanel.done = ns.OptionButton(movePanel, 120, "Done", function()
    ns.ToggleMovers(false)
  end)
  movePanel.done:SetPoint("BOTTOMRIGHT", -14, 12)

  movePanel.reset = ns.OptionButton(movePanel, 120, "Reset all", function()
    ns.ResetAllMovers()
    ns.Print("every frame is back where it started.")
  end)
  movePanel.reset:SetPoint("BOTTOMLEFT", 14, 12)

  -- Escape closes it, and closing it by any means ends move mode.
  table.insert(UISpecialFrames, "ForeverUIMovePanel")
  movePanel:SetScript("OnHide", function()
    if overlayShown then
      ns.ToggleMovers(false)
    end
  end)
  ns.movePanel = movePanel
  return movePanel
end

-- A handle in move mode: draggable, unless its frame was locked where it is
-- (Cast Bar > "Lock it where it is"): then it shows, dimmed and marked, and
-- stays put.
local function ShowHandle(mover)
  local locked = mover.locked and true or false
  SetInteractive(mover, overlayShown and not locked)
  mover.bg:SetShown(overlayShown)
  mover.bg:SetAlpha(locked and 0.12 or 0.35)
  mover.text:SetShown(overlayShown)
  mover.text:SetText(locked and (mover.label .. " (locked)") or mover.label)
end

function ns.SetMoverLocked(name, locked)
  local mover = movers[name]
  if not mover then return false end
  mover.locked = locked and true or nil
  ShowHandle(mover)
  return true
end

function ns.ToggleMovers(show)
  if show == nil then
    show = not overlayShown
  end
  if show and InCombatLockdown() then
    ns.Print("frames can't be moved in combat.")
    return
  end
  overlayShown = show and true or false
  for _, mover in pairs(movers) do
    if overlayShown then
      FitToFrame(mover)   -- whatever size the frame has grown or shrunk to
    end
    ShowHandle(mover)
  end
  -- The party/raid grids move with their own green handles, one per grid.
  -- EveryWhere, not SetLocked: the plain one only unlocks the grid currently
  -- being configured, which is why "Move frames" handed you a handle for the
  -- healing grid and nothing for tanking or DPS.
  local unlockGrids = ns.Frames and (ns.Frames.SetLockedEverywhere or ns.Frames.SetLocked)
  if unlockGrids then
    pcall(unlockGrids, not overlayShown)
  end
  if overlayShown then
    if not movePanel then
      BuildMovePanel()
    end
    movePanel:Show()
    ns.Print("drag the handles; right-click one to reset it. Done, or Escape, when you're finished.")
  elseif movePanel then
    movePanel:Hide()
  end
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
end

---------------------------------------------------------------------------
-- Taking a Blizzard frame
---------------------------------------------------------------------------
--
-- "Can we move this?" -- asked of a frame nobody knows the name of. Point at
-- it, /fui grab, and it gets a handle like everything else: dragged with
-- /fui move, remembered per profile, taken again at every login. The frame
-- stays Blizzard's; only where it sits is ours.
--
-- Protected frames can't be re-parented or re-anchored without being blocked
-- (and a blocked addon's buttons stop casting), so those are refused with a
-- reason rather than attempted.

local grabbed = {}   -- name -> frame

local function Root(frame)
  -- The frame worth taking is the whole widget: climb until the parent is
  -- the screen, or one of the game's own containers.
  local depth = 0
  while frame and depth < 10 do
    local parent = frame.GetParent and frame:GetParent()
    if not parent or parent == UIParent or parent == MinimapCluster or parent == Minimap then
      return frame
    end
    -- A button sitting in one of our own bars: the button is the widget,
    -- not the bar it was put in.
    local parentName = parent.GetName and parent:GetName()
    if parentName and parentName:find("^ForeverUI") then
      return frame
    end
    frame = parent
    depth = depth + 1
  end
  return frame
end

local function Hold(frame, mover)
  local anchoring, queued = false, false
  local function anchor()
    if anchoring then
      return
    end
    -- Re-anchoring is a SetPoint. On a frame that turns out to be protected
    -- -- IsProtected can read false before a fight on this client -- a
    -- SetPoint in combat is blocked and taints us. Wait for the fight's end
    -- and do it once.
    if InCombatLockdown() then
      if not queued then
        queued = true
        ns.WhenOutOfCombat(function() queued = false; anchor() end)
      end
      return
    end
    -- Local patch (4 Oct 2026): the C originals (ClearAllPointsBase,
    -- SetPointBase) via Skin.Plain. DurabilityFrame, adopted at every login,
    -- is an Edit Mode system: its own ClearAllPoints/SetPoint are Lua that
    -- writes into the Edit Mode manager, and the hook below runs this inside
    -- every Edit Mode pass. Those writes carried our taint, the layout even
    -- saved "ForeverUIGrabDurabilityFrame" as its anchor, and the rest of the
    -- pass redrew Blizzard's party frames as ForeverUI:
    -- "CompactUnitFrame.lua:699: attempt to compare local 'oldR' (a secret
    -- number value, while execution tainted by 'ForeverUI')".
    anchoring = true
    ns.Skin.Plain(frame, "ClearAllPoints")
    ns.Skin.Plain(frame, "SetPoint", "CENTER", mover, "CENTER", 0, 0)
    anchoring = false
  end
  anchor()
  -- The game puts it back where it wants it on its next update; put it back
  -- where you want it on the same breath.
  if hooksecurefunc and not rawget(frame, "fuiGrabHeld") then
    frame.fuiGrabHeld = true
    hooksecurefunc(frame, "SetPoint", function()
      anchor()
    end)
  end
end

function ns.GrabFrame(frame, name, label, default)
  if not frame or not name then
    return false, "nothing to take"
  end
  if name:find("^ForeverUI") then
    return false, "that's ours already - /fui move drags it"
  end
  if ns.Skin.Forbidden(frame) then
    return false, "the game forbids touching that one"
  end
  if frame.IsProtected and frame:IsProtected() then
    return false, "that frame is protected; moving it would be blocked and would break casting"
  end
  local key = "grab:" .. name
  local mover = movers[key]
  if not mover then
    local width = (frame.GetWidth and frame:GetWidth()) or 40
    local height = (frame.GetHeight and frame:GetHeight()) or 40
    if not width or width < 8 then width = 40 end
    if not height or height < 8 then height = 40 end
    -- Where it is now, so taking it doesn't move it until you do -- unless
    -- the caller named a spot, which the few frames adopted at login do.
    local point, _, relativePoint, x, y = "CENTER", nil, "CENTER", 0, 0
    if default then
      point, relativePoint, x, y = default[1], default[2], default[3], default[4]
    elseif frame.GetCenter and UIParent.GetCenter then
      local cx, cy = frame:GetCenter()
      local ux, uy = UIParent:GetCenter()
      if cx and ux then
        x, y = math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
      end
    end
    local holder = CreateFrame("Frame", "ForeverUIGrab" .. name, UIParent)
    holder:SetSize(width, height)
    mover = ns.RegisterMover(key, label or name, holder, { point, relativePoint, x, y })
    mover.grabHolder = holder
  end
  if UIPARENT_MANAGED_FRAME_POSITIONS then
    UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
  end
  -- Let go of the minimap bar's grip first, if it had one.
  local minimap = ns.GetModule("Minimap")
  if minimap and minimap.Release then
    minimap.Release(frame)
  end
  Hold(frame, mover.grabHolder)
  grabbed[name] = frame
  ns.db.grabbed[name] = true
  if ns.db.released then ns.db.released[name] = nil end
  return true, name
end

function ns.GrabUnderCursor()
  local focus = ns.Skin.MouseFocus()
  local frame = Root(focus)
  local name = frame and frame.GetName and frame:GetName()
  if not frame or not name or name == "" or frame == UIParent then
    ns.Print("point at the thing you want to move, then run this again.")
    return false
  end
  local ok, why = ns.GrabFrame(frame, name)
  if ok then
    ns.Print(("|cff4dc3ff%s|r is yours to move now: /fui move, drag the handle named after it."):format(name))
  else
    ns.Print(why)
  end
  return ok
end

-- Blizzard frames worth moving that nobody should have to go hunting for.
--
-- /fui grab will adopt anything you point at, but a handful of frames come up
-- every time: the armour-damage figure parks itself wherever the game likes,
-- usually on top of something else. These are adopted at login so they simply
-- appear in /fui move with a name on them, like everything else does.
--
-- Anything protected is skipped by GrabFrame itself, so this list can name a
-- frame that turns out to be off limits without breaking the login.
local ADOPTED = {
  -- The starting spot is the owner's own, so the figure lands clear of the
  -- bars instead of wherever the game last parked it.
  { name = "DurabilityFrame", label = "Armour damage",
    default = { "BOTTOM", "BOTTOM", -229, 112 } },
}
ns.ADOPTED_FRAMES = ADOPTED

-- At login: take again everything taken before, plus the few we adopt for you.
function ns.RegrabAll()
  local count = 0
  for name in pairs(ns.db.grabbed or {}) do
    local frame = _G[name]
    if frame and ns.GrabFrame(frame, name) then
      count = count + 1
    end
  end
  for _, entry in ipairs(ADOPTED) do
    -- Only if it wasn't taken above, and only if the player hasn't handed it
    -- back: releasing a frame should stay released.
    if not ns.db.grabbed[entry.name] and not (ns.db.released and ns.db.released[entry.name]) then
      local frame = _G[entry.name]
      if frame and ns.GrabFrame(frame, entry.name, entry.label, entry.default) then
        count = count + 1
      end
    end
  end
  return count
end

function ns.ReleaseGrabs()
  local count = 0
  ns.db.released = ns.db.released or {}
  for name in pairs(ns.db.grabbed or {}) do
    count = count + 1
    -- Remembered, so the handful we adopt for you at login stay handed back
    -- rather than reappearing at the next reload.
    ns.db.released[name] = true
  end
  ns.Wipe(ns.db.grabbed)
  ns.Print(("%d frame%s handed back - they return where the game puts them after a reload."):format(
    count, count == 1 and "" or "s"))
  return count
end

ns.grabbedFrames = grabbed
