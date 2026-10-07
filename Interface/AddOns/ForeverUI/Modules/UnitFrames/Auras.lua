local _, ns = ...

-- Buffs and debuffs on the player, target, focus, pet and target-of-target
-- frames.
--
-- Forever hides auras from addons in a fight: the reads come back secret, and
-- an addon that reads them itself goes blank the moment combat starts. So
-- ForeverUI doesn't read them at all. Each frame gets one of the game's own
-- aura containers (CustomAuraContainerTemplate, Blizzard_AuraContainer) - a
-- frame the game fills itself, in or out of combat. ForeverUI hands every
-- icon it makes the parts to draw into (the icon, the timer spiral, the stack
-- count, the dispel-colour border) and says where the rows go. The game picks
-- the auras, sorts them, shows the tooltip, and lets a right-click cancel your
-- own buff, as on its own frames.
--
-- The icons the game makes are locked to addons while auras are secret, so
-- everything here that touches them runs out of combat. Ten of each kind are
-- made when a frame is built - the game makes them in tens - so a busy fight
-- never needs a new one.

local module = ns.GetModule("UnitFrames")

-- Which frames show auras until their own tab says otherwise. The player's
-- are already top right, on the game's own buff bar.
local SHOWN_BY_DEFAULT = { target = true, focus = true }

local MAX_PER_GROUP = 10
local SPACING = 2
local GAP = 4          -- between the frame and the first row

local function Settings()
  return ns.db.modules.UnitFrames
end

-- The game's container exists on this client? It is a Blizzard addon that
-- the target frame loads; if nothing has loaded it yet, ask once.
local function Available()
  -- Not while the controller's navigation is live (Core/Controller.lua):
  -- the containers' own CreateFrame runs it tainted.
  if ns.GamepadUIActive and (ns.GamepadUIActive() or ns.controllerAtBoot) then
    return false
  end
  if _G.CustomAuraContainerGroupDefaultOptions then
    return true
  end
  if not module.auraLoadTried then
    module.auraLoadTried = true
    local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if load then pcall(load, "Blizzard_AuraContainer") end
  end
  return _G.CustomAuraContainerGroupDefaultOptions ~= nil
end
module.AurasAvailable = Available

function module.AurasOn(key)
  local own = Settings().unitOpts and Settings().unitOpts[key]
  if own and own.auras ~= nil then
    return own.auras and true or false
  end
  -- The game's buff bar hidden: your own frame takes over showing them.
  if key == "player" and Settings().hideBlizzardBuffs then
    return true
  end
  return SHOWN_BY_DEFAULT[key] == true
end

-- Icon size for a frame: its own if set, else the size for its kind of frame.
function module.AuraSize(info)
  local settings = Settings()
  local own = settings.unitOpts and settings.unitOpts[info.key]
  if own and own.auraSize then
    return own.auraSize
  end
  return info.small and settings.smallAuraSize or settings.auraSize
end

-- "Only debuffs I cast" is for what you put on enemies; your own frame and
-- your pet's show whatever is on them.
function module.DebuffFilter(info)
  if module.Opt("onlyMyDebuffs", info.key) and info.key ~= "player" and info.key ~= "pet" then
    return "HARMFUL|PLAYER"
  end
  return "HARMFUL"
end

---------------------------------------------------------------------------
-- The icons
---------------------------------------------------------------------------

-- The numbers on every icon (stack count and the game's countdown): one font
-- object for all of them, so a new size reaches every icon at once
-- (sprutorgel on CurseForge, 26 Sept 2026: "much bigger than the icon").
local countFont
local function TextSize()
  return math.max(6, math.min(24, tonumber(Settings().auraTextSize) or 10))
end
local function CountFont()
  if not countFont and CreateFont then
    countFont = CreateFont("ForeverUIAuraTextFont")
  end
  if countFont then
    local path = ns.Media.Role("unitHealth")
    countFont:SetFont(path, TextSize(), "OUTLINE")
  end
  return countFont
end
module.AuraTextFont = CountFont

-- Style one icon the game has just made. `harmful` icons get the dispel
-- colour on their border (magic blue, poison green...; red for the rest).
-- Guarded: an icon made while auras are secret refuses to be touched, and a
-- refused icon should cost a blank square, not an error in the chat frame.
local function StyleButton(frame, button, harmful)
  pcall(function()
    local size = module.AuraSize(frame.info)
    button:SetSize(size, size)

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 1)
    border:SetVertexColor(0, 0, 0, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetHideCountdownNumbers then
      cooldown:SetHideCountdownNumbers(not Settings().auraTimers)
    end
    if cooldown.SetCountdownFont and CountFont() then
      pcall(cooldown.SetCountdownFont, cooldown, "ForeverUIAuraTextFont")
    end
    button:SetDurationCooldown(cooldown)

    -- Above the spiral, so the count stays readable while it sweeps.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(cooldown:GetFrameLevel() + 2)
    local count = over:CreateFontString(nil, "OVERLAY")
    if CountFont() and count.SetFontObject then
      count:SetFontObject(countFont)
    else
      ns.Media.SetFont(count, "unitHealth")
    end
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    button:SetApplicationCount(count)

    if harmful and Enum and Enum.CustomAuraButtonDispelTypeTextureStyle then
      button:AddDispelTypeTexture(border, {
        style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
        showWithoutDispelType = true,
      })
    end

    -- Kept on the frame, not the icon: the game may hand back a different
    -- handle for the same icon later.
    frame.auraCooldowns = frame.auraCooldowns or {}
    frame.auraCooldowns[#frame.auraCooldowns + 1] = cooldown
  end)
end

-- Every icon a group owns, made or not yet shown.
local function EachButton(container, group, fn)
  local ok, count = pcall(container.GetAuraGroupFrameCount, container, group)
  if not ok or type(count) ~= "number" then return end
  for i = 1, count do
    local okB, button = pcall(container.GetAuraGroupFrame, container, group, i)
    if okB and button then fn(button) end
  end
end

---------------------------------------------------------------------------
-- The containers: one for debuffs, one for buffs, each placed on its own
-- side of the frame (sprutorgel, 26 Sept 2026: "separate Buffs and debuffs
-- ... over, below, right, left").
---------------------------------------------------------------------------

local KINDS = { "debuffs", "buffs" }   -- debuffs first: nearest the frame
local PER_ROW_SIDE = 6                 -- icons per row beside the frame

local function Layout(size)
  return {
    elementSpacing = SPACING, lineSpacing = SPACING,
    groupSpacing = SPACING, groupLineSpacing = SPACING,
    elementWidth = size, elementHeight = size,
  }
end

-- Where one kind goes on this frame: its own setting, else the shared one.
function module.AuraPosition(kind, key)
  local own = module.Opt(kind == "buffs" and "buffPosition" or "debuffPosition", key)
  if own == "above" or own == "below" or own == "left" or own == "right" then
    return own
  end
  local shared = module.Opt("auraPosition", key)
  return (shared == "below") and "below" or "above"
end

-- Build a frame's containers once, out of combat. Nothing happens on a client
-- without the game's container, and a refusal is kept for /fui diagnostics.
function module.BuildAuras(frame)
  if frame.auraBoxes or frame.aurasFailed or not Available() then
    return frame.auraBoxes
  end
  local boxes = {}
  local ok, err = pcall(function()
    local size = module.AuraSize(frame.info)
    for _, kind in ipairs(KINDS) do
      local box = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
      box:SetUnit(frame.unit)
      local harmful = kind == "debuffs"
      box:AddAuraGroup(kind, harmful and module.DebuffFilter(frame.info) or "HELPFUL", {
        maxFrameCount = MAX_PER_GROUP,
        initializeFrame = function(button) StyleButton(frame, button, harmful) end,
        layout = Layout(size),
      })
      boxes[kind] = box
    end
  end)
  if not ok then
    frame.aurasFailed = true
    module.auraError = tostring(err)
    return nil
  end
  frame.auraBoxes = boxes
  frame.auras = boxes.debuffs   -- the first, for anything that asked before
  module.ApplyAuras(frame)
  return boxes
end

-- Put one box on its side of the frame, or beyond `after` (the debuffs,
-- when both share a side).
local function Place(frame, box, where, after, size)
  local settings = Settings()
  local flow = AnchorUtil and AnchorUtil.FlowDirection
  local rel = after or frame
  box:ClearAllPoints()
  if where == "left" or where == "right" then
    box:SetFlowLayoutMaximumLineSize(PER_ROW_SIDE * (size + SPACING))
    if where == "left" then
      box:SetFlowLayoutAnchorPoint("TOPRIGHT")
      if flow then box:SetFlowLayoutGrowthDirection(flow.Left, flow.Down) end
      box:SetPoint("TOPRIGHT", rel, "TOPLEFT", -GAP, 0)
    else
      box:SetFlowLayoutAnchorPoint("TOPLEFT")
      if flow then box:SetFlowLayoutGrowthDirection(flow.Right, flow.Down) end
      box:SetPoint("TOPLEFT", rel, "TOPRIGHT", GAP, 0)
    end
    return
  end
  box:SetFlowLayoutMaximumLineSize(frame:GetWidth())
  if where == "above" then
    box:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    if flow then box:SetFlowLayoutGrowthDirection(flow.Right, flow.Up) end
    box:SetPoint("BOTTOMLEFT", rel, "TOPLEFT", 0, GAP)
  else
    -- Under the cast bar's lane, so a cast never covers them.
    local drop = GAP
    if not after and module.Opt("castBars", frame.info.key) then
      drop = drop + (settings.castBarHeight or 18) + 2
    end
    box:SetFlowLayoutAnchorPoint("TOPLEFT")
    if flow then box:SetFlowLayoutGrowthDirection(flow.Right, flow.Down) end
    box:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -drop)
  end
end

-- Size, place and switch on one frame's auras from the settings. Out of
-- combat only (the caller's job: Refresh and OnEnable run it that way).
function module.ApplyAuras(frame)
  local boxes = frame.auraBoxes
  if not boxes then return end
  local settings = Settings()
  local key = frame.info.key
  local on = module.AurasOn(key)
  local want = {
    buffs = on and module.Opt("showBuffs", key) and true or false,
    debuffs = on and module.Opt("showDebuffs", key) and true or false,
  }
  local limit = { buffs = settings.maxBuffs, debuffs = settings.maxDebuffs }

  pcall(function()
    local size = module.AuraSize(frame.info)
    CountFont()
    boxes.debuffs:SetAuraGroupFilterString("debuffs", module.DebuffFilter(frame.info))
    for _, kind in ipairs(KINDS) do
      local box = boxes[kind]
      box:SetAuraGroupMaxFrameCount(kind, math.min(MAX_PER_GROUP, limit[kind] or MAX_PER_GROUP))
      box:SetAuraGroupLayout(kind, Layout(size))
      EachButton(box, kind, function(button) button:SetSize(size, size) end)
    end
    for _, cooldown in ipairs(frame.auraCooldowns or {}) do
      if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(not settings.auraTimers)
      end
    end
    local debuffAt = module.AuraPosition("debuffs", key)
    local buffAt = module.AuraPosition("buffs", key)
    Place(frame, boxes.debuffs, debuffAt, nil, size)
    -- Same side as the debuffs: the buffs sit beyond them.
    local after = (buffAt == debuffAt and want.debuffs) and boxes.debuffs or nil
    Place(frame, boxes.buffs, buffAt, after, size)
    for _, kind in ipairs(KINDS) do
      boxes[kind]:SetEnabled(want[kind])
      boxes[kind]:SetShown(want[kind])
    end
  end)
end

-- The unit behind a token changed (a new target, a new pet): the game's
-- container only follows aura changes by itself, so tell it to start over.
function module.UpdateAuras(frame)
  for _, box in pairs(frame.auraBoxes or {}) do
    if box:IsShown() then
      pcall(box.UpdateAllAuras, box)
    end
  end
end

---------------------------------------------------------------------------
-- The game's own buff and debuff bar (top right). Edit Mode can't hide it
-- (sprutorgel, 26 Sept 2026), so this can: off by default, since it is an
-- Edit Mode frame and ForeverUI otherwise leaves those alone. With it hidden,
-- your own frame shows your buffs unless its tab says otherwise.
---------------------------------------------------------------------------

local stash
function module.ApplyBlizzardBuffs()
  if not Settings().hideBlizzardBuffs or (InCombatLockdown and InCombatLockdown()) then
    return false
  end
  -- The controller's radial menu opens Blizzard's buff frame: left alone.
  if ns.ControllerActive and ns.ControllerActive() then
    return false
  end
  stash = stash or CreateFrame("Frame")
  stash:Hide()
  local hidden = 0
  for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
    local f = _G[name]
    if f and ns.Skin.Conceal(f, stash) then hidden = hidden + 1 end
  end
  return hidden > 0
end
