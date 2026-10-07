local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Where the frame settings live: INSIDE ForeverUI's profile, not beside it.
--
-- ForeverUI keeps one profile per character (Core/Profiles.lua), and that
-- profile is the whole addon's -- bars, frames, chat, the lot. The frame
-- engine used to carry a profile system of its own under ForeverUIDB.frames,
-- with its own per-character keys, spare copies and reconcile passes, and
-- that second layer is exactly what kept coming back empty. It is gone.
--
--   ForeverUIDB.profiles["Default"].frames = { scale = 1, bindings = {...},
--                                              mode = "healer", modes = {...} }
--
-- ns.db points at that one sub-table. The healer and tank settings both sit
-- inside it (Modes.lua parks whichever role isn't active under db.modes),
-- so a druid who does both has ONE save, and DPS goes in the same shell when
-- it arrives. Nothing in the engine reads ForeverUIDB directly any more.

local function CharacterKey()
  local name = UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return name .. " - " .. realm
end
ns.CharacterKey = CharacterKey

-- The ForeverUI profile this character is on; the frames save into it.
function ns.ActiveProfileName()
  if FUI.ActiveProfileName then
    local ok, name = pcall(FUI.ActiveProfileName)
    if ok and name then
      return name
    end
  end
  return "Default"
end

-- One-time nudges for when a default changes and the stored value would leave
-- a feature invisible. Each runs once per profile and records that it ran, so
-- turning it back off afterwards sticks.
local MIGRATIONS = {
  -- Role markers used to default to hidden; they're the point of having
  -- roles at all, so profiles from before get them switched on once.
  -- Blizzard's party frames are hidden by default since 0.4.65 (players saw
  -- both sets); profiles from before get that once, and turning it back
  -- off afterwards sticks.
  partyHidden = function(profile)
    profile.hideBlizzardParty = true
  end,

  rolesOn = function(profile)
    if profile.showRole == false then
      profile.showRole = true
    end
  end,

  -- Health colours were the default for one version and a bar-colour choice
  -- rather than a switch. They are a switch now, and off unless asked for.
  healthSwitch = function(profile)
    if profile.barColor == "health" then
      profile.barColor = "green"
    end
  end,

  manaBar = function(profile)
    if (profile.powerBarHeight or 0) == 0 then
      profile.powerBarHeight = 5 -- used to default to hidden, which read as missing
    end
  end,
}
ns.MIGRATIONS = MIGRATIONS

-- Saved texture paths name the addon's folder, and the folder has been Mender,
-- HealForever, and whatever this install is called. Rewrite any of ours to
-- point at where the addon actually lives now, or the bars come back blank.
function ns.FixMediaPaths(profile)
  for key, value in pairs(profile) do
    if type(value) == "string" then
      local tail = value:match("^Interface\\AddOns\\[^\\]+\\Media\\(.+)$")
      if tail and (value:find("\\Mender\\", 1, true) or value:find("\\HealForever", 1, true)) then
        profile[key] = ns.MEDIA .. tail
      end
    end
  end
end

local function Migrate(profile)
  profile.migrations = profile.migrations or {}
  for name, fn in pairs(MIGRATIONS) do
    if not profile.migrations[name] then
      fn(profile)
      profile.migrations[name] = true
    end
  end
  return profile
end

local function FillDefaults(profile)
  for key, value in pairs(ns.DEFAULTS) do
    if profile[key] == nil then
      profile[key] = type(value) == "table" and ns.CopyTable(value) or value
    end
  end
  ns.FixMediaPaths(profile)
  return Migrate(profile)
end
ns.FillDefaults = FillDefaults

-- Everything that has to be re-applied when the settings underneath change.
function ns.ApplyAllSettings()
  if not ns.anchor then
    return -- too early: SetupLayout hasn't run yet
  end
  ns.RebuildWatchIndex()
  if ns.ForgetBuffList then ns.ForgetBuffList() end
  ns.ApplyScale()
  ns.ApplyFrameSize()
  ns.ApplySorting()
  ns.ApplyAppearance()
  ns.ApplyMinimapButton()
  ns.LayoutGroups()
  ns.ApplyVisibility()
  ns.ApplyBindings()
  ns.SetLockedEverywhere(ns.db.locked)
  -- Every grid, not just the one being configured.
  if ns.ApplyAllPositions then
    ns.ApplyAllPositions()
  else
    ns.ApplyPosition()
  end
  ns.RefreshAll()
  ns.ApplyTargetPosition()
  ns.ApplyTargetSize()
  ns.RenderTargetDebuffs()
  ns.RenderPreviews()
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
end

-- An explicit save. Everything here is already stored the moment you change
-- it, so this stamps when and for whom, re-applies the lot, and gives the
-- window something honest to show. The disk write itself is the game's: it
-- happens at logout or on /reload, which is what the reload button is for.
function ns.SaveNow()
  -- Where things are beats where they were last written down.
  ns.CapturePosition()
  ns.CaptureTargetPosition()
  ns.CaptureFocusPosition()
  ns.db.savedAt = (time and time()) or (os and os.time and os.time()) or 0
  ns.db.savedBy = CharacterKey()
  ns.ApplyAllSettings()
  return ns.db.savedAt
end

-- One short line for the window's footer -- it shares the footer with the
-- buttons, so it can't wrap up into them.
function ns.SaveSummary()
  return ("Saves as you go, in ForeverUI profile \"%s\"."):format(ns.ActiveProfileName())
end

---------------------------------------------------------------------------
-- Adopting the old separate store
---------------------------------------------------------------------------

-- Until 0.3.1 the frames kept their own profiles under ForeverUIDB.frames.
-- If that table is still around from an earlier version, the profile this
-- character was on is lifted into the ForeverUI profile once -- in memory,
-- the game writes the file -- and the old store is dropped so there is
-- exactly one place the settings can be.
local function CountSpells(profile)
  local n = 0
  for _, binding in pairs(profile and profile.bindings or {}) do
    if binding.kind == "spell" then n = n + 1 end
  end
  return n
end

local function AdoptOldStore(target)
  local old = rawget(_G, "ForeverUIDB")
  old = old and old.frames
  if type(old) ~= "table" then
    return nil
  end
  local profiles = old.profiles or {}
  local chosen = old.profileKeys and old.profileKeys[CharacterKey()]
  local source = chosen and profiles[chosen]
  if not source then
    -- Whichever old profile had the most spells on it is the one worth keeping.
    local best = -1
    for name, profile in pairs(profiles) do
      local spells = CountSpells(profile)
      if spells > best then
        best, source, chosen = spells, profile, name
      end
    end
  end
  local adopted = nil
  if source and next(target) == nil then
    for key, value in pairs(source) do
      target[key] = type(value) == "table" and ns.CopyTable(value) or value
    end
    adopted = chosen
  end
  -- Clear the old store ONLY when this build owns it.
  --
  -- Inside ForeverUI, ForeverUIDB is ours and dropping the stale sub-table is
  -- the whole point of this migration. In a standalone HealForever or
  -- TankForever it belongs to a DIFFERENT addon that may well be installed
  -- alongside, and reaching into it would delete that addon's frame settings.
  -- Unguarded it also raises outright when ForeverUI is not installed at all.
  if not ns.standalone and rawget(_G, "ForeverUIDB") then
    ForeverUIDB.frames = nil
  end
  return adopted
end
ns.AdoptOldStore = AdoptOldStore

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

-- A saved texture path names the folder the addon was in when it was saved.
-- Installed under any other name -- "ForeverUI" from CurseForge, a test copy
-- locally -- that path points at nothing and every bar draws blank. Re-root
-- any path into our own Media folder at the folder we are actually in.
local function RepairTexture(store)
  local texture = type(store) == "table" and store.barTexture
  if type(texture) == "string" then
    local file = texture:match("[Mm]odules\\Frames\\Media\\([^\\]+)$")
    if file and texture ~= ns.MEDIA .. file then
      store.barTexture = ns.MEDIA .. file
    end
  end
end

function ns.RepairMediaPaths(db)
  RepairTexture(db)
  -- Each role keeps its own look (db.modes[role]), and each grid draws with
  -- its own copy: repairing only the top one left the other grids blank.
  for _, store in pairs(type(db.modes) == "table" and db.modes or {}) do
    RepairTexture(store)
  end
end

-- Point ns.db at the frames sub-table of ForeverUI's active profile. Called
-- when the frames module initialises (ForeverUI has resolved the character's
-- profile by then) and again whenever ForeverUI switches profile, so the
-- engine always writes into the profile the rest of the addon is on.
-- Returns true if it landed on a different table than before.
function ns.InitProfiles()
  local core = FUI.db
  if type(core) ~= "table" then
    return false -- ForeverUI hasn't loaded its profile yet; keep the scratch table
  end
  if ns.TraceSaved then ns.TraceSaved("InitProfiles: before touching anything") end
  core.frames = core.frames or {}
  ns.adopted = AdoptOldStore(core.frames)
  local changed = ns.db ~= core.frames
  ns.db = FillDefaults(core.frames)
  ns.RepairMediaPaths(ns.db)

  -- One home for the clicks, from here on.
  --
  -- Profiles written before this have the same clicks in two places: a live
  -- ns.db.bindings and a parked copy under modes[mode]. Whichever the player
  -- touched last is the live one, so it wins -- and then ns.db.bindings
  -- becomes the parked table itself rather than a copy of it, which is what
  -- stops the two ever disagreeing again.
  local mode = ns.db.mode or "healer"
  local live = rawget(ns.db, "bindings")
  local store = ns.BindingStore(mode)
  if type(live) == "table" and live ~= store and next(live) ~= nil then
    for key, value in pairs(live) do
      store[key] = value
    end
  end
  ns.UseBindingStore(mode)
  if ns.Trace then ns.Trace("InitProfiles: done") end
  if ns.TraceSaved then ns.TraceSaved("InitProfiles: done") end
  -- And again much later, when everything has settled, so a profile swapped
  -- out from under us after boot shows up too.
  if C_Timer and C_Timer.After and ns.TraceSaved then
    C_Timer.After(5, function() ns.TraceSaved("five seconds after boot") end)
  end
  return changed
end

-- Until the module boots, anything that reads ns.db (the ticker, an early
-- event) gets a throwaway table full of defaults rather than an error.
if not ns.db then
  ns.db = FillDefaults({})
end
