local _, ns = ...

-- The capturer (owner, 27 Sept 2026: "as I play my character ... you learn
-- and make ForeverUI better").
--
-- While you play, it keeps a quiet record of the situations you were in and
-- of anything that looked wrong in them, so a problem never has to be
-- noticed, described or screenshotted to get fixed:
--
--   scenes    where you were and what was going on: zone, combat, solo /
--             party / raid and its roles, what you had targeted, how many
--             auras, which quests, which windows were open, and the last
--             few events that led there.
--   findings  what the layout check saw: our frames off the screen, our
--             frames on top of each other, a game window opening over ours,
--             text cut off, a frame that should be showing and isn't.
--   errors    every ForeverUI error, tied to the scene it happened in.
--   marks     /fui capture mark <note> - "this looks wrong, right here".
--
-- It is the owner's tool, not a player feature: it runs only in his own
-- install (tools/install_fui.sh writes DevOwner.lua, which sets
-- ForeverUI_OWNER). In everyone else's copy it does nothing at all and
-- /fui capture doesn't exist.
--
-- It is written with the rest of the saved variables (a /reload or logging
-- out), where tools/capture_pull.lua reads it and tests/replay.lua plays each
-- scene back against ForeverUI offline.
--
-- It only reads. It never moves, hides or touches a frame, never looks at a
-- secret value (anything the game hides is recorded as hidden, not read),
-- and everything it does is inside pcall: a fault in the capturer is noted
-- in its own record and never reaches the game.

local Capture = {}
ns.Capture = Capture

local MAX_SESSIONS = 4
local MAX_SCENES = 400
local MAX_FINDINGS = 250
local MAX_QUESTS = 25
local RING = 24
local AUDIT_EVERY = 5          -- seconds between layout checks
local TEXT_EVERY = 4           -- ...and every this many checks, the text too
local SCENE_REPEAT = 15        -- the same scene again this soon is not new

local session, started, ring = nil, 0, {}
local lastSignature, lastSceneAt = nil, -1000
local audits, knownErrors = 0, {}
local ticker

---------------------------------------------------------------------------
-- Reading without touching secrets
---------------------------------------------------------------------------

local function IsSecret(value)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, value)
    -- A test that could not answer is treated as hidden: never guess.
    return not ok or secret == true
  end
  return false
end

-- A value safe to keep: plain strings, numbers and booleans only.
local function Plain(value)
  local kind = type(value)
  if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
  if IsSecret(value) then return nil end
  if kind == "string" and #value > 60 then return value:sub(1, 60) end
  return value
end
Capture.Plain = Plain

-- Call fn and keep only the plain results.
-- (Lua 5.1 in the game: no table.pack, so the count comes from select.)
local function Keep(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  local results = { ... }
  for i = 1, n do results[i] = Plain(results[i]) end
  return unpack(results, 1, n)
end

local function Ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  return Keep(pcall(fn, ...))
end

local function Now()
  return math.floor(((GetTime and GetTime()) or 0) - started + 0.5)
end

local function Stamp()
  return (date and date("%Y-%m-%d %H:%M:%S")) or "?"
end

---------------------------------------------------------------------------
-- Switched on
---------------------------------------------------------------------------

-- The owner's own install, and nobody else's (tools/install_fui.sh writes
-- DevOwner.lua). /fui capture off stops it for the session.
local paused = false
function ns.IsOwner()
  return rawget(_G, "ForeverUI_OWNER") == true
end
Capture.Owner = ns.IsOwner

function Capture.Enabled()
  return ns.IsOwner() and not paused
end

local function Store()
  ForeverUIDB = ForeverUIDB or {}
  local store = ForeverUIDB.capture
  if type(store) ~= "table" or store.v ~= 1 then
    store = { v = 1, sessions = {} }
    ForeverUIDB.capture = store
  end
  return store
end
Capture.Store = Store

local function Note(problem)
  if not session then return end
  session.selfErrors = session.selfErrors or {}
  if #session.selfErrors < 20 then
    session.selfErrors[#session.selfErrors + 1] = tostring(problem):sub(1, 200)
  end
end

---------------------------------------------------------------------------
-- Scenes
---------------------------------------------------------------------------

local function Player()
  local _, class = Ask(UnitClass, "player")
  local _, race = Ask(UnitRace, "player")
  local p = { class = class, race = race, level = Ask(UnitLevel, "player") }
  local health, maximum = Ask(UnitHealth, "player"), Ask(UnitHealthMax, "player")
  if health and maximum and maximum > 0 then
    p.hp = math.floor(health / maximum * 100 + 0.5)
  else
    p.hp = "hidden"
  end
  local _, token = Ask(UnitPowerType, "player")
  p.power = token
  p.dead = Ask(UnitIsDeadOrGhost, "player")
  return p
end

local function Group()
  local raid = Ask(IsInRaid) == true
  local size = Ask(GetNumGroupMembers) or 0
  local g = { kind = raid and "raid" or (size > 0 and "party" or "solo"), size = size, roles = {}, classes = {} }
  if size == 0 then return g end
  local prefix, count = raid and "raid" or "party", raid and size or size - 1
  for i = 1, math.min(count, 40) do
    local unit = prefix .. i
    local role = Ask(UnitGroupRolesAssigned, unit) or "NONE"
    g.roles[role] = (g.roles[role] or 0) + 1
    local _, class = Ask(UnitClass, unit)
    if class then g.classes[class] = (g.classes[class] or 0) + 1 end
  end
  return g
end

local function Target()
  if not Ask(UnitExists, "target") then return { kind = "none" } end
  local t = {
    level = Ask(UnitLevel, "target"),
    classification = Ask(UnitClassification, "target"),
    dead = Ask(UnitIsDead, "target"),
    player = Ask(UnitIsPlayer, "target"),
  }
  local enemy = Ask(UnitCanAttack, "player", "target")
  t.kind = enemy and "enemy" or (t.player and "friendlyPlayer" or "friend")
  return t
end

-- How many auras, or "hidden" when the game won't say.
local function Auras(unit)
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if type(get) ~= "function" or not Ask(UnitExists, unit) then return nil end
  local n = 0
  for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
    for i = 1, 40 do
      local ok, data = pcall(get, unit, i, filter)
      if not ok then return "hidden" end
      if data == nil then break end
      if IsSecret(data) then return "hidden" end
      n = n + 1
    end
  end
  return n
end

local function Quests()
  local list = {}
  local log = C_QuestLog
  if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return list end
  local total = Ask(log.GetNumQuestLogEntries) or 0
  for i = 1, total do
    local ok, info = pcall(log.GetInfo, i)
    if ok and type(info) == "table" and not info.isHeader then
      local id = Plain(info.questID)
      if id then
        local done = log.IsComplete and Ask(log.IsComplete, id)
        list[#list + 1] = { id = id, done = done == true or nil }
        if #list >= MAX_QUESTS then break end
      end
    end
  end
  return list
end

-- The game's own windows worth knowing about: what was open when it went
-- wrong, and the ones that have landed on top of our frames before.
local WINDOWS = {
  "LootFrame", "QuestFrame", "GossipFrame", "MerchantFrame", "CharacterFrame",
  "SpellBookFrame", "PlayerSpellsFrame", "PlayerTalentFrame", "WorldMapFrame",
  "ContainerFrameCombinedBags", "ContainerFrame1", "BankFrame", "MailFrame",
  "TradeFrame", "FriendsFrame", "CommunitiesFrame", "GuildFrame", "StaticPopup1",
  "ScriptErrorsFrame", "GameMenuFrame", "SettingsPanel", "EditModeManagerFrame",
}
Capture.WINDOWS = WINDOWS

local function Shown(frame)
  if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then return false end
  local ok, visible = pcall(frame.IsVisible, frame)
  return ok and visible == true
end

local function OpenWindows()
  local open = {}
  for _, name in ipairs(WINDOWS) do
    if Shown(rawget(_G, name)) then open[#open + 1] = name end
  end
  for _, name in ipairs({ "ForeverUIOptions", "ForeverUIErrors", "ForeverUIInstaller" }) do
    if Shown(rawget(_G, name)) then open[#open + 1] = name end
  end
  return open
end

local function Ring()
  local copy = {}
  for i = math.max(1, #ring - 19), #ring do copy[#copy + 1] = ring[i] end
  return copy
end

local function Signature(s)
  return table.concat({
    tostring(s.zone), tostring(s.combat), s.group.kind, tostring(s.group.size),
    s.target.kind, tostring(s.target.classification), table.concat(s.windows, ","),
  }, "|")
end

-- Record where we are. Returns the scene's number (or the last one's, when
-- nothing has changed).
function Capture.Scene(why)
  if not session then return nil end
  local ok, scene = pcall(function()
    local s = {
      at = Now(), why = why,
      zone = Ask(GetRealZoneText) or Ask(GetZoneText),
      subzone = Ask(GetSubZoneText),
      map = C_Map and C_Map.GetBestMapForUnit and Ask(C_Map.GetBestMapForUnit, "player"),
      combat = Ask(InCombatLockdown) == true,
      secrets = C_Secrets and C_Secrets.HasSecretRestrictions and Ask(C_Secrets.HasSecretRestrictions) or nil,
      player = Player(), group = Group(), target = Target(),
      windows = OpenWindows(), quests = Quests(),
    }
    s.auras = { player = Auras("player"), target = Auras("target") }
    return s
  end)
  if not ok then Note(scene) return nil end
  local signature = Signature(scene)
  local forced = why == "mark" or why == "error" or why == "finding"
  if not forced and signature == lastSignature and scene.at - lastSceneAt < SCENE_REPEAT then
    return #session.scenes > 0 and #session.scenes or nil
  end
  if #session.scenes >= MAX_SCENES then
    session.dropped = (session.dropped or 0) + 1
    return #session.scenes
  end
  scene.events = Ring()
  session.scenes[#session.scenes + 1] = scene
  lastSignature, lastSceneAt = signature, scene.at
  scene.n = #session.scenes
  return scene.n
end

---------------------------------------------------------------------------
-- Findings
---------------------------------------------------------------------------

function Capture.Find(kind, key, text)
  if not session then return end
  local list = session.findings
  for _, f in ipairs(list) do
    if f.key == key then
      f.count = f.count + 1
      f.last = Now()
      return f
    end
  end
  if #list >= MAX_FINDINGS then return nil end
  local f = { kind = kind, key = key, text = text, count = 1, first = Now(), last = Now(),
    combat = Ask(InCombatLockdown) == true }
  list[#list + 1] = f
  f.scene = Capture.Scene("finding")
  return f
end

---------------------------------------------------------------------------
-- The layout check
---------------------------------------------------------------------------

-- A frame's box in UIParent's units, or nil when it has none yet.
local function Box(frame)
  if type(frame.GetRect) ~= "function" then return nil end
  local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
  if not ok then return nil end
  left, bottom, width, height = Plain(left), Plain(bottom), Plain(width), Plain(height)
  if not (left and bottom and width and height) or width <= 0 or height <= 0 then return nil end
  local scale = 1
  if type(frame.GetEffectiveScale) == "function" and type(UIParent.GetEffectiveScale) == "function" then
    local a, b = Plain(select(2, pcall(frame.GetEffectiveScale, frame))), Plain(select(2, pcall(UIParent.GetEffectiveScale, UIParent)))
    if a and b and b > 0 then scale = a / b end
  end
  return { l = left * scale, b = bottom * scale, r = (left + width) * scale, t = (bottom + height) * scale }
end
Capture.Box = Box

local function Area(box) return (box.r - box.l) * (box.t - box.b) end

local function Overlap(a, b)
  local w = math.min(a.r, b.r) - math.max(a.l, b.l)
  local h = math.min(a.t, b.t) - math.max(a.b, b.b)
  if w <= 0 or h <= 0 then return 0 end
  return w * h
end
Capture.Overlap = Overlap

local function Name(frame)
  local ok, name = pcall(frame.GetName, frame)
  return ok and Plain(name) or nil
end

-- Frames painted see-through (the faded Blizzard tracker, a put-away mover)
-- aren't in anyone's way.
local function Opaque(frame)
  if type(frame.GetEffectiveAlpha) ~= "function" then return true end
  local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
  alpha = ok and Plain(alpha)
  return alpha == nil or alpha > 0.05
end

-- Pairs that are meant to touch: the minimap's title bar sits on its own
-- map on purpose.
Capture.ALLOWED = {
  ["ForeverUIMinimap x ForeverUIMinimapHeader"] = true,
}

-- Anything to see? A holder with nothing showing in it (the durability
-- figure's box while your gear is fine) isn't in anyone's way.
local function HasContent(frame)
  if type(frame.GetRegions) == "function" then
    for _, region in ipairs({ frame:GetRegions() }) do
      if type(region) == "table" and Shown(region) then return true end
    end
  end
  if type(frame.GetChildren) == "function" then
    for _, child in ipairs({ frame:GetChildren() }) do
      if type(child) == "table" and Shown(child) then return true end
    end
  end
  return false
end
Capture.HasContent = HasContent

-- Our top-level frames on screen now: { name, box }.
local function OurFrames(screen)
  local list = {}
  local children = ns.Skin and ns.Skin.Children and ns.Skin.Children(UIParent)
  if type(children) ~= "table" then
    children = { UIParent:GetChildren() }
  end
  for _, frame in ipairs(children) do
    local name = type(frame) == "table" and Name(frame)
    if name and name:find("^ForeverUI") and not name:find("Mover") and Shown(frame) and Opaque(frame)
      and HasContent(frame) then
      local box = Box(frame)
      -- Full-screen holders (the move-mode shade, a click-catcher) aren't layout.
      if box and not (box.r - box.l >= screen.w * 0.9 and box.t - box.b >= screen.h * 0.9) then
        list[#list + 1] = { name = name, box = box, frame = frame }
      end
    end
  end
  return list
end

local function Screen()
  local w = Plain(select(2, pcall(UIParent.GetWidth, UIParent))) or 1920
  local h = Plain(select(2, pcall(UIParent.GetHeight, UIParent))) or 1080
  return { w = w, h = h }
end

local function CheckOffScreen(ours, screen)
  for _, item in ipairs(ours) do
    local b = item.box
    local inside = math.max(0, math.min(b.r, screen.w) - math.max(b.l, 0))
      * math.max(0, math.min(b.t, screen.h) - math.max(b.b, 0))
    local share = inside / Area(b)
    if share < 0.75 then
      Capture.Find("offscreen", "offscreen:" .. item.name,
        ("%s is %d%% off the screen"):format(item.name, math.floor((1 - share) * 100 + 0.5)))
    end
  end
end

-- Pinned to the other on purpose (a grid and its own chrome): not a clash.
local function PinnedTo(a, b)
  if type(a.GetNumPoints) ~= "function" then return false end
  local ok, n = pcall(a.GetNumPoints, a)
  for i = 1, (ok and Plain(n)) or 0 do
    local got, _, relative = pcall(a.GetPoint, a, i)
    if got and relative == b then return true end
  end
  return false
end

local function CheckOverlaps(ours)
  for i = 1, #ours do
    for j = i + 1, #ours do
      local a, b = ours[i], ours[j]
      local pair = a.name < b.name and (a.name .. " x " .. b.name) or (b.name .. " x " .. a.name)
      if not Capture.ALLOWED[pair] and not PinnedTo(a.frame, b.frame) and not PinnedTo(b.frame, a.frame) then
        local shared = Overlap(a.box, b.box)
        local smaller = math.min(Area(a.box), Area(b.box))
        local w = math.min(a.box.r, b.box.r) - math.max(a.box.l, b.box.l)
        local h = math.min(a.box.t, b.box.t) - math.max(a.box.b, b.box.b)
        if shared > 0 and smaller > 0 and shared / smaller >= 0.25 then
          Capture.Find("overlap", "overlap:" .. pair,
            ("%s covers %d%% of %s"):format(pair, math.floor(shared / smaller * 100 + 0.5),
              Area(a.box) < Area(b.box) and a.name or b.name))
        elseif w >= 20 and h >= 6 then
          -- A strip, not a cover: a label or an edge sitting over the next
          -- frame's (the coordinates over the quest list's title were this).
          Capture.Find("overlap", "edge:" .. pair,
            ("%s overlap by a %dx%d strip"):format(pair, math.floor(w + 0.5), math.floor(h + 0.5)))
        end
      end
    end
  end
end

-- A game window landing on our frames (the loot window over the bars was
-- this): worth knowing, though a window on top is often simply open.
local function CheckCovers(ours)
  for _, name in ipairs(WINDOWS) do
    local window = rawget(_G, name)
    -- (A window we have faded to nothing -- the bag we mirror -- isn't over anything.)
    if name ~= "ScriptErrorsFrame" and Shown(window) and Opaque(window) then
      local box = Box(window)
      if box then
        for _, item in ipairs(ours) do
          local shared = Overlap(box, item.box)
          local area = Area(item.box)
          if area > 0 and shared / area >= 0.4 then
            Capture.Find("covers", "covers:" .. name .. ">" .. item.name,
              ("%s opened over %s"):format(name, item.name))
          end
        end
      end
    end
  end
end

-- Text the frame is too small for. Walks our visible frames only, and not
-- too deep or too far.
local function CheckText(ours)
  local seen = 0
  local function walk(frame, owner, depth)
    if seen > 1500 or depth > 6 then return end
    if type(frame.GetRegions) == "function" then
      for i, region in ipairs({ frame:GetRegions() }) do
        seen = seen + 1
        if type(region) == "table" and type(region.IsTruncated) == "function" and Shown(region) then
          -- On a text the game hides, the answer is hidden too: not ours
          -- to read (the first real capture tripped on exactly this).
          local ok, cut = pcall(region.IsTruncated, region)
          if ok and not IsSecret(cut) and cut == true then
            Capture.Find("clipped", ("clipped:%s#%d@%d"):format(owner, i, depth),
              ("text cut off in %s"):format(owner))
          end
        end
      end
    end
    if type(frame.GetChildren) == "function" then
      for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and Shown(child) then
          walk(child, Name(child) or owner, depth + 1)
        end
      end
    end
  end
  for _, item in ipairs(ours) do walk(item.frame, item.name, 0) end
end

-- What should be on screen and isn't. Each check returns a message when
-- something is missing. Modules can add their own.
Capture.EXPECT = {
  -- More than one role's party grid on screen while solo: the three frames
  -- (Tanking / Healing / DPS) seen mid-screen on 26 Sept.
  function()
    if Ask(IsInGroup) then return nil end
    local showing = {}
    for _, role in ipairs({ "healer", "tank", "dps" }) do
      if Shown(rawget(_G, "ForeverUIFramesChrome" .. role)) then showing[#showing + 1] = role end
    end
    if #showing > 1 then
      return "grids:" .. table.concat(showing, "+"),
        ("%d role grids showing while solo (%s)"):format(#showing, table.concat(showing, ", "))
    end
  end,
  function()
    if not (ns.IsModuleEnabled and ns.IsModuleEnabled("UnitFrames")) then return nil end
    local frame = rawget(_G, "ForeverUIplayer")
    if frame and not Shown(frame) and not Ask(UnitHasVehicleUI, "player") then
      return "missing:player", "the player frame isn't showing"
    end
  end,
}

local function CheckExpected()
  for _, check in ipairs(Capture.EXPECT) do
    local ok, key, text = pcall(check)
    if ok and key then Capture.Find("missing", key, text) end
  end
end

-- New ForeverUI errors since the last look, each tied to a scene.
local function CheckErrors()
  local log = type(ForeverUIDB) == "table" and ForeverUIDB.errors
  if type(log) ~= "table" then return end
  for _, entry in ipairs(log) do
    local key = tostring(entry.msg):sub(1, 160)
    local count = tonumber(entry.count) or 1
    if (knownErrors[key] or 0) < count then
      local first = knownErrors[key] == nil
      knownErrors[key] = count
      if first then
        session.errors[#session.errors + 1] = { msg = key, at = Now(), scene = Capture.Scene("error"), count = count }
      else
        for _, e in ipairs(session.errors) do
          if e.msg == key then e.count = count end
        end
      end
    end
  end
end

function Capture.Audit()
  if not session then return end
  audits = audits + 1
  session.audits = audits
  local ok, problem = pcall(function()
    CheckErrors()
    local screen = Screen()
    session.screen = screen
    local ours = OurFrames(screen)
    CheckOffScreen(ours, screen)
    CheckOverlaps(ours)
    CheckCovers(ours)
    CheckExpected()
    if audits % TEXT_EVERY == 1 then CheckText(ours) end
  end)
  if not ok then Note(problem) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- Every event it listens to goes in the ring (what led up to a scene); the
-- ones marked true are also a scene of their own.
local EVENTS = {
  PLAYER_ENTERING_WORLD = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true,
  PLAYER_TARGET_CHANGED = true, GROUP_ROSTER_UPDATE = true, ZONE_CHANGED_NEW_AREA = true,
  QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, LOOT_OPENED = true, PLAYER_LEVEL_UP = true,
  PLAYER_DEAD = true, GOSSIP_SHOW = true, QUEST_DETAIL = true, QUEST_COMPLETE = true,
  MERCHANT_SHOW = true, PLAYER_ROLES_ASSIGNED = true, UI_SCALE_CHANGED = true,
  DISPLAY_SIZE_CHANGED = true,
  LOOT_CLOSED = false, QUEST_LOG_UPDATE = false, UNIT_AURA = false, BAG_UPDATE = false,
  UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_STOP = false, UNIT_SPELLCAST_SUCCEEDED = false,
  UNIT_THREAT_LIST_UPDATE = false, PLAYER_FOCUS_CHANGED = false, UPDATE_MOUSEOVER_UNIT = false,
}
Capture.EVENTS = EVENTS

-- Unit events only for the units a layout cares about; the rest is noise.
local UNITS = { player = true, target = true, focus = true, pet = true }

local function Remember(event, arg1)
  local arg = Plain(arg1)
  local last = ring[#ring]
  if last and last.e == event and last.a == arg then
    last.c = (last.c or 1) + 1
    last.t = Now()
    return
  end
  ring[#ring + 1] = { e = event, a = arg, t = Now() }
  if #ring > RING then table.remove(ring, 1) end
end

-- Some scenes are worth a second look once the game has laid them out.
local function Soon(fn, delay)
  if C_Timer and C_Timer.After then C_Timer.After(delay or 0.5, fn) else fn() end
end

local throttle = {}
function Capture.OnEvent(event, arg1)
  if not session then return end
  if event:find("^UNIT_") and not (type(arg1) == "string" and not IsSecret(arg1) and UNITS[arg1]) then return end
  Remember(event, arg1)
  if not EVENTS[event] then return end
  local now = Now()
  if (event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE") and (throttle[event] or -100) > now - 3 then
    return
  end
  throttle[event] = now
  Capture.Scene(event)
  Soon(Capture.Audit, 0.5)
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------

function Capture.Start()
  if session or not Capture.Enabled() then return session end
  started = (GetTime and GetTime()) or 0
  ring, lastSignature, lastSceneAt, audits, knownErrors = {}, nil, -1000, 0, {}
  -- Errors already in the book belong to earlier sessions.
  if type(ForeverUIDB) == "table" and type(ForeverUIDB.errors) == "table" then
    for _, entry in ipairs(ForeverUIDB.errors) do
      knownErrors[tostring(entry.msg):sub(1, 160)] = tonumber(entry.count) or 1
    end
  end
  local store = Store()
  local version, build, _, interface = Ask(GetBuildInfo)
  session = {
    started = Stamp(), addon = ns.VERSION, client = { version = version, build = build, interface = interface },
    scenes = {}, findings = {}, errors = {}, marks = {},
  }
  table.insert(store.sessions, 1, session)
  while #store.sessions > MAX_SESSIONS do table.remove(store.sessions) end
  Capture.Scene("login")
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(AUDIT_EVERY, Capture.Audit)
  end
  Soon(Capture.Audit, 2)
  return session
end

function Capture.Stop()
  if ticker and ticker.Cancel then ticker:Cancel() end
  ticker, session = nil, nil
end

function Capture.Session() return session end

function Capture.Mark(note)
  if not session then return nil end
  local n = Capture.Scene("mark")
  session.marks[#session.marks + 1] = { note = tostring(note or ""):sub(1, 200), at = Now(), scene = n }
  Capture.Audit()
  return n
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("PLAYER_LOGIN")
for event in pairs(EVENTS) do
  pcall(listener.RegisterEvent, listener, event)
end
listener:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    pcall(Capture.Start)
    return
  end
  local ok, problem = pcall(Capture.OnEvent, event, arg1)
  if not ok then Note(problem) end
end)
Capture.listener = listener

---------------------------------------------------------------------------
-- /fui capture
---------------------------------------------------------------------------

function Capture.Command(rest)
  local word, note = (rest or ""):match("^(%S*)%s*(.-)$")
  word = (word or ""):lower()
  if not ns.IsOwner() then return end
  if word == "on" then
    paused = false
    Capture.Start()
    ns.Print("capture on. Play as usual; /fui capture mark <note> flags a moment.")
  elseif word == "off" then
    paused = true
    Capture.Stop()
    ns.Print("capture off for this session (it's back on at your next login).")
  elseif word == "mark" then
    if not session then ns.Print("capture is off -- /fui capture on first.") return end
    local n = Capture.Mark(note)
    ns.Print(("marked (scene %s). It's saved at your next /reload or logout."):format(tostring(n)))
  elseif word == "clear" then
    Store().sessions = {}
    Capture.Stop()
    Capture.Start()
    ns.Print("capture cleared.")
  else
    if not session then
      ns.Print("capture is off. /fui capture on to start.")
      return
    end
    ns.Print(("capture on: %d scenes, %d findings, %d errors, %d marks this session."):format(
      #session.scenes, #session.findings, #session.errors, #session.marks))
    for i = 1, math.min(5, #session.findings) do
      local f = session.findings[i]
      print(("  %s x%d  %s"):format(f.kind, f.count, f.text or f.key))
    end
    print("  It's written at /reload or logout; then tell Claude \"check the capture\".")
  end
end
