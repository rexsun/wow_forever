local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- Roles keep separate settings.
--
-- Healer and tank mean different things by the same keys -- what a click does,
-- which indicators are on -- and a druid or paladin does both. So each role
-- keeps its own copy of those keys. The ACTIVE role's values live on ns.db as
-- usual (so every read site is unchanged); the other role's copy is parked in
-- ns.db.modes[role]. Everything not listed here is shared between roles.

ns.MODE_KEYS = {
  -- "bindings" is deliberately NOT here.
  --
  -- Every key in this list is copied out of ns.db when you leave a role and
  -- copied back in when you return. For settings that is fine. For bindings
  -- it meant the same clicks existed in two places -- the live ns.db.bindings
  -- and the parked ns.db.modes[role].bindings -- and any path that reloaded,
  -- rebuilt or swapped in the wrong order could let one overwrite the other.
  -- They now live in exactly one place, ns.db.modes[role].bindings, and
  -- ns.db.bindings is that same table rather than a copy of it.
  "classDefaults", "auraWatch", "starterWatch", "manualSpells",
  "missingBuffs", "showMissingBuffs",
  "showIncoming", "showOverheal", "overhealLane", "overhealLanePercent", "showChrome",
  "showDispel", "showHots", "gameDispels", "inferHots",
  "showThreat",
  "showThreatMeter", "showThreatPercent", "looseList", "loosePosition",
  "threatAlert", "threatSound", "alertLostTarget", "alertPosition", "showTheirTarget",
  "onYouAlert", "onYouSound", "onYouPosition",
  -- Where the grid sits. Per role because all three are on screen together
  -- now: sharing one position would stack them on top of each other.
  "position",
  -- The focus group: the unit you have focused, as a frame you can cast on,
  -- plus anyone you pinned by name. Per role for the same reason as the grid
  -- -- a healer wants the tank parked beside their cast bar, a damage dealer
  -- may not want it at all -- and each role gets its own spot and size.
  "showFocus", "focusPosition", "focusScale",
}

-- How a grid LOOKS, per role too (owner, 22 Sept 2026): a tank may want big
-- orange bars, a healer small ones, and changing one must not change the
-- others. The Appearance page's settings, plus scale and the frame-shape
-- options. Each role starts from the look everyone shared before.
ns.LOOK_KEYS = {
  "scale", "frameWidth", "frameHeight", "powerBarHeight", "frameStyle", "barTexture",
  "barBackground", "barOpacity", "healthText", "fontSize", "healthFontSize", "classColorNames",
  "barColor", "healthColor", "nameText", "nameAnchor", "healthAnchor", "nameLength",
  "borderSize", "borderColor", "fillDirection",
  "barCustomColor", "lowHealthThreshold", "lowHealthColor", "critHealthThreshold", "critHealthColor",
  "barBackgroundColor", "barGradient", "showLoss", "animateHeal", "healthAlpha",
  "auraSize", "auraTimer", "auraTimerSize", "hotRowCorner",
}
for _, key in ipairs(ns.LOOK_KEYS) do
  ns.MODE_KEYS[#ns.MODE_KEYS + 1] = key
end

-- Draw with `role`'s settings for the length of fn, WITHOUT the full swap
-- (PushMode also moves the clicks, which is far too much for every health
-- update). Every grid's buttons are styled and drawn in one pass over all of
-- them, so each button borrows its own grid's look here and hands it back.
-- Reading only: nothing is written to the role's store.
function ns.WithLook(role, fn, ...)
  local db = ns.db
  local current = db and (db.mode or "healer")
  if not db or not role or role == current then
    return fn(...)
  end
  local store = db.modes and db.modes[role] or {}
  -- Per call, never shared: styling can draw, and a nested lend must not
  -- lose the outer one's record of what to hand back.
  local saved, lent = {}, {}
  for _, key in ipairs(ns.MODE_KEYS) do
    local value = store[key]
    if value ~= nil then
      saved[key] = db[key]
      lent[#lent + 1] = key
      db[key] = value
    end
  end
  -- The role itself too: a grid reads and draws AS its role. Lending only
  -- the settings left every "is this the tank grid?" check following the
  -- role you were playing -- the tank grid lost its target and AGGRO wash
  -- while you healed. ns.PlayingRole() still answers the role you're in.
  local savedPlaying = ns.playingRole
  ns.playingRole = savedPlaying or current
  db.mode = role
  local ok, a, b = pcall(fn, ...)
  db.mode = current
  ns.playingRole = savedPlaying
  for _, key in ipairs(lent) do
    db[key] = saved[key]
  end
  if not ok then error(a, 0) end
  return a, b
end

-- Give every role its own copy of the look, from the one they all shared,
-- the first time it is missing. Without this a role that was never opened
-- would keep following whichever role was being edited.
function ns.SeedRoleLooks()
  local db = ns.db
  if not (db and ns.SettingsReady and ns.SettingsReady()) then return end
  db.modes = db.modes or {}
  for _, role in ipairs({ "healer", "tank", "dps" }) do
    db.modes[role] = db.modes[role] or {}
    local store = db.modes[role]
    for _, key in ipairs(ns.LOOK_KEYS) do
      if store[key] == nil and db[key] ~= nil then
        local value = db[key]
        store[key] = type(value) == "table" and ns.CopyTable(value) or value
      end
    end
  end
  ns.MigrateInferHots()
end

-- "Keep my HoTs showing in combat" was off by default on the Tanking and DPS
-- grids (no HoT row there by default), so anyone who turned the HoT row on
-- for those grids saw their Rejuvenation and Regrowth vanish the moment a
-- fight started (owner, 25 Sept 2026). On for every grid now, and switched
-- on once for settings saved before.
function ns.MigrateInferHots()
  local db = ns.db
  if not db or db.inferHotsAllGrids then return false end
  db.inferHotsAllGrids = true
  db.inferHots = true
  for _, store in pairs(db.modes or {}) do
    if type(store) == "table" and store.inferHots == false then store.inferHots = true end
  end
  return true
end

-- Each role's defaults for those keys. Healer == today's HealForever; tank has
-- the threat tools on and the healer-only indicators off.
ns.MODE_DEFAULTS = {
  healer = {
    showIncoming = true, showOverheal = true, showDispel = true, showHots = true,
    gameDispels = true, inferHots = true, showMissingBuffs = true,
    showThreat = true,
    showThreatMeter = false, showThreatPercent = false, looseList = false,
    threatAlert = false, threatSound = false, alertLostTarget = false,
    showTheirTarget = false,
    -- A healer watches one person harder than the rest: the focus group is
    -- on, and sits a little larger than the grid.
    showFocus = true, focusScale = 1.3,
    focusPosition = { "CENTER", "CENTER", 260, -60 },
    bindings = ns.CopyTable(ns.DEFAULT_BINDINGS),
    position = { "TOPLEFT", "TOPLEFT", 20, -118 },
  },
  tank = {
    showIncoming = false, showOverheal = false, showDispel = false, showHots = false,
    gameDispels = false, inferHots = true, showMissingBuffs = false,
    showThreat = true,
    showThreatMeter = true, showThreatPercent = true, looseList = true,
    threatAlert = true, threatSound = true, alertLostTarget = true,
    showTheirTarget = true,
    -- A tank's focus is usually the healer, or the second tank.
    showFocus = true, focusScale = 1.3,
    focusPosition = { "CENTER", "CENTER", 260, -60 },
    bindings = ns.CopyTable(ns.DEFAULT_BINDINGS),
    position = { "TOPLEFT", "TOPLEFT", 420, -118 },
  },
  -- Damage: group utility rather than healing or threat. Dispels and curses
  -- matter, incoming heals and HoTs do not, and the threat tools are off --
  -- but showThreat stays on, because a damage dealer wants to know the
  -- moment something is on THEM.
  dps = {
    showIncoming = false, showOverheal = false, showDispel = true, showHots = false,
    gameDispels = true, inferHots = true, showMissingBuffs = true,
    showThreat = true,
    showThreatMeter = false, showThreatPercent = false, looseList = false,
    threatAlert = false, threatSound = false, alertLostTarget = false,
    showTheirTarget = false,
    -- ...and the moment it IS on them, in the middle of the screen.
    onYouAlert = true, onYouSound = true,
    showFocus = true, focusScale = 1.3,
    focusPosition = { "CENTER", "CENTER", 260, -60 },
    bindings = ns.CopyTable(ns.DEFAULT_BINDINGS),
    position = { "TOPLEFT", "TOPLEFT", 820, -118 },
  },
}

---------------------------------------------------------------------------
-- Borrowing another role's settings for a moment
---------------------------------------------------------------------------
--
-- Three grids are on screen at once, but the engine has ONE ns.db: every
-- function in it reads ns.db.frameWidth, ns.db.showHots, ns.db.bindings. So
-- to build the tank grid we lend the engine the tank's settings, build, and
-- give the healer's back.
--
-- This is the same swap SetMode has always done. What it is NOT is SetMode:
-- no rebuilding the options window, no re-applying the layout, no printing.
-- Those would recurse, because the thing doing the borrowing IS the layout.

local function CaptureInto(store)
  for _, key in ipairs(ns.MODE_KEYS) do
    store[key] = ns.db[key]
  end
end

local function LoadFrom(store, role)
  local fallback = ns.MODE_DEFAULTS[role or ""] or {}
  for _, key in ipairs(ns.MODE_KEYS) do
    if store[key] ~= nil then
      ns.db[key] = store[key]
    elseif fallback[key] ~= nil then
      -- The role has settings saved from before this key was per-role. Left
      -- alone it keeps whatever the LAST role had, which for "position" means
      -- two grids stacked exactly on top of each other and looking like only
      -- one of them drew. Seed it from the role's own defaults instead.
      -- CopyTable only copies TABLES. Most of these defaults are booleans,
      -- and handing one to it threw -- which aborted the grid build and left
      -- the tanking and DPS grids unable to come up at all.
      local value = fallback[key]
      store[key] = (type(value) == "table") and ns.CopyTable(value) or value
      ns.db[key] = store[key]
    end
  end
end

function ns.GetMode()
  return ns.db and ns.db.mode or "healer"
end

-- The role the player is in, even while another role's settings are lent
-- out for a grid's build (ns.WithMode).
function ns.PlayingRole()
  return ns.playingRole or ns.GetMode()
end

-- The one and only home for a role's clicks. Made on demand so a role that
-- has never been used still answers with a table rather than nil.
function ns.BindingStore(role)
  role = role or ns.GetMode()
  if not ns.db then
    return {}
  end
  ns.db.modes = ns.db.modes or {}
  ns.db.modes[role] = ns.db.modes[role] or {}
  local store = ns.db.modes[role]
  if type(store.bindings) ~= "table" then
    local seed = (ns.MODE_DEFAULTS[role] or {}).bindings
    store.bindings = seed and ns.CopyTable(seed) or {}
  end
  return store.bindings
end

-- Point ns.db.bindings AT the active role's store -- the same table, not a
-- copy. Everything that already reads ns.db.bindings keeps working, and there
-- is nothing left to get out of step.
function ns.UseBindingStore(role)
  if not ns.db then
    return nil
  end
  local store = ns.BindingStore(role or ns.GetMode())
  ns.db.bindings = store
  if ns.ForgetBindingAttributes then
    ns.ForgetBindingAttributes()
  end
  return store
end

-- Are we allowed to WRITE settings yet?
--
-- Until InitProfiles runs, ns.db is a throwaway table of defaults, not the
-- saved profile. Anything written to it is written to nothing -- and worse,
-- if that table is still in place when the game saves, it goes to disk ON TOP
-- of the real profile. That is not hypothetical: it destroyed the whole
-- ns.db.modes table on this machine -- every role's bindings, aura watch and
-- position -- because a read created an empty table on the scratch profile
-- and the scratch profile was then saved.
--
-- So every writer asks first. Readers answer from defaults; writers wait.
function ns.SettingsReady()
  return ns.booted == true and ns.db ~= nil
end

-- Lend the engine `role`'s settings. Returns the role that was loaded, to
-- hand back to ns.PopMode.
function ns.PushMode(role)
  if not ns.SettingsReady() then
    return ns.db and ns.db.mode or "healer"
  end
  local current = ns.db.mode or "healer"
  if role == current then
    return current
  end
  ns.db.modes = ns.db.modes or {}
  ns.db.modes[current] = ns.db.modes[current] or {}
  CaptureInto(ns.db.modes[current])
  local incoming = ns.db.modes[role]
  if not incoming then
    incoming = ns.CopyTable(ns.MODE_DEFAULTS[role] or {})
    ns.db.modes[role] = incoming
  end
  LoadFrom(incoming, role)
  ns.db.mode = role
  ns.UseBindingStore(role)
  if ns.Trace then ns.Trace("PushMode -> " .. tostring(role)) end
  if ns.ForgetBindingAttributes then
    ns.ForgetBindingAttributes()
  end
  return current
end

-- Give them back. Always pair with the value PushMode returned.
function ns.PopMode(role)
  if role then
    ns.PushMode(role)
  end
end

-- Run fn with `role`'s settings loaded, whatever happens inside it. An error
-- in one grid's build must not leave the engine holding another grid's
-- settings -- every read after that would be wrong, silently.
function ns.WithMode(role, fn)
  -- Inside, GetMode() answers the role being lent; PlayingRole() still
  -- answers the one the player is actually in.
  local outer = ns.playingRole
  ns.playingRole = outer or ns.GetMode()
  local previous = ns.PushMode(role)
  local ok, err = pcall(fn)
  ns.PopMode(previous)
  ns.playingRole = outer
  if not ok then
    ns.Print(("|cffff6666%s grid failed:|r %s"):format(role, tostring(err)))
  end
  return ok
end

-- Every role that has a grid of its own. All three are real now: each has
-- its own settings, its own bindings and its own window.
ns.ROLES = { "healer", "tank", "dps" }

-- A standalone build does ONE role.
--
-- HealForever is a healing addon and TankForever is a tanking one; that is
-- the whole reason they exist separately from ForeverUI, which carries all
-- three. Locking the role here rather than hiding the others in the UI means
-- every loop over ns.ROLES, every "is this supported", and every grid the
-- layout builds is already narrowed -- there is no second grid to leak out
-- through some path nobody thought to hide.
function ns.LockRole(role)
  local allowed = false
  for _, known in ipairs({ "healer", "tank", "dps" }) do
    allowed = allowed or (role == known)
  end
  if not allowed then
    return nil
  end
  ns.lockedRole = role
  ns.ROLES = { role }
  if ns.db then
    ns.db.mode = role
    ns.db.gridsUp = { [role] = true }
  end
  return role
end

-- How a grid tells you which grid it is. Three of them watching the same five
-- people look identical without this: same names, same bars, same everything.
-- The border and the title carry the role's colour so you know which one your
-- mouse is over before you read a word of it.
ns.ROLE_CHROME = {
  healer = { label = "Healing", icon = "heal", color = { 0.30, 0.85, 0.40 } },
  tank   = { label = "Tanking", icon = "tank", color = { 1.00, 0.55, 0.15 } },
  -- Purple, not red: red is taken by low health, hostile units and danger,
  -- and a DPS grid should never read as a warning.
  dps    = { label = "DPS",     icon = "dps",  color = { 0.66, 0.42, 1.00 } },
}

-- Put every grid back on its own patch of screen. Three grids that have never
-- been dragged all sit where the one grid used to, which reads as "only one
-- of them drew".
function ns.SpaceGrids()
  if not ns.SettingsReady() then
    return 0
  end
  local moved = 0
  for _, role in ipairs(ns.ROLES) do
    local defaults = ns.MODE_DEFAULTS[role]
    if defaults and defaults.position then
      ns.db.modes = ns.db.modes or {}
      ns.db.modes[role] = ns.db.modes[role] or {}
      ns.db.modes[role].position = ns.CopyTable(defaults.position)
      if ns.GetMode() == role then
        ns.db.position = ns.CopyTable(defaults.position)
      end
      moved = moved + 1
    end
  end
  if ns.SetupLayout then
    ns.SetupLayout()
  end
  return moved
end

function ns.IsSupportedMode(mode)
  for _, role in ipairs(ns.ROLES) do
    if mode == role then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Which grids are on screen
---------------------------------------------------------------------------
--
-- Not the same question as which one you are CONFIGURING. A druid has the
-- healing grid and the tanking grid both up while editing whichever of them
-- he happens to be looking at. They are not modes and never were: turning one
-- on does not take another down, and shapeshifting does not touch any of them.

-- Reading this must NOT write.
--
-- It used to do `ns.db.gridsUp = ns.db.gridsUp or {}` first, which looks
-- harmless and is not: before the engine boots, ns.db is a throwaway table of
-- defaults, so one early read stamped an empty gridsUp onto the scratch
-- profile. From then on every role read "not set" and fell back to "only the
-- role you are in" -- one grid up, the other two switched off, while the
-- saved profile plainly said all three were on. It survived reloads and read
-- as a persistence bug for an hour.
function ns.IsGridShown(role)
  if ns.lockedRole then
    return role == ns.lockedRole
  end
  local up = ns.db and ns.db.gridsUp
  if not up or up[role] == nil then
    -- Never asked, or asked too early: the role you are in is up and the
    -- others are not, which is how this behaved when there could only be one.
    return role == ns.GetMode()
  end
  return up[role] == true
end

-- Solo, every switched-on grid or only your role's (Layout.lua ApplyVisibility).
function ns.SetSoloAllGrids(on)
  if not ns.SettingsReady() then return false end
  ns.db.soloAllGrids = on and true or false
  if ns.SetupLayout then ns.SetupLayout() end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return ns.db.soloAllGrids
end

function ns.SetGridShown(role, on)
  if ns.lockedRole then
    return false   -- one role, always on: there is nothing to switch
  end
  if not ns.IsSupportedMode(role) or not ns.SettingsReady() then
    return false
  end
  ns.db.gridsUp = ns.db.gridsUp or {}
  ns.db.gridsUp[role] = on and true or false
  if ns.SetupLayout then
    ns.SetupLayout()
  end
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
  return ns.db.gridsUp[role]
end

-- When a grid shows, in one word per role (owner, 30 Sept 2026: "I do want
-- to be able to manually turn on tanking and DPSing ... when I am leveling,
-- whenever I want to" -- and the old pair of controls, "Tanking frames: on"
-- plus a separate "Solo: every grid that's on", was the confusing part: a
-- grid switched on stayed hidden solo unless the other switch was on too).
--   "always"  solo and in groups
--   "group"   only in a party or raid
--   "off"
-- A role nobody has set shows always if it's the role you're playing (or
-- the old solo switch is on), otherwise in groups -- how it behaved before.
-- Reading this must not write (see IsGridShown).
function ns.GridState(role)
  if not ns.IsGridShown(role) then return "off" end
  if ns.lockedRole then return "always" end
  local solo
  if ns.db and type(ns.db.gridSolo) == "table" then solo = ns.db.gridSolo[role] end
  if solo == nil then
    solo = (ns.db and ns.db.soloAllGrids) or role == ns.PlayingRole()
  end
  return solo and "always" or "group"
end

function ns.SetGridState(role, state)
  if ns.lockedRole or not ns.IsSupportedMode(role) or not ns.SettingsReady() then
    return false
  end
  if state ~= "always" and state ~= "group" and state ~= "off" then return false end
  ns.db.gridsUp = ns.db.gridsUp or {}
  ns.db.gridsUp[role] = state ~= "off"
  if state ~= "off" then
    ns.db.gridSolo = type(ns.db.gridSolo) == "table" and ns.db.gridSolo or {}
    ns.db.gridSolo[role] = state == "always"
  end
  if ns.SetupLayout then ns.SetupLayout() end
  if ns.RefreshOptions then ns.RefreshOptions() end
  return ns.GridState(role)
end

-- One click each: off -> always -> in groups only -> off. From off, the
-- first click is the one that puts it on screen now, solo or not.
local NEXT_STATE = { off = "always", always = "group", group = "off" }
function ns.CycleGridState(role)
  return ns.SetGridState(role, NEXT_STATE[ns.GridState(role)] or "always")
end

-- Every role whose grid is currently on screen, in a stable order.
function ns.ShownGrids()
  local list = {}
  for _, role in ipairs(ns.ROLES) do
    if ns.IsGridShown(role) then
      list[#list + 1] = role
    end
  end
  return list
end

-- A standalone build is one role, locked at boot -- but LockRole runs before
-- the character's settings exist, so those settings still said "healer" (the
-- default) and TankForever booted as a healer: healer clicks, and none of the
-- tank extras, which are built only when the mode says tank (found building
-- DPS Forever, 27 Sept 2026). Called once the settings are loaded: the same
-- swap SetMode does, quietly, before anything is built.
function ns.EnterLockedRole()
  local role = ns.lockedRole
  if not role or not ns.db then
    return false
  end
  ns.db.gridsUp = { [role] = true }
  local current = ns.db.mode or "healer"
  if current == role then
    return false
  end
  ns.db.modes = ns.db.modes or {}
  ns.db.modes[current] = ns.db.modes[current] or {}
  CaptureInto(ns.db.modes[current])
  local incoming = ns.db.modes[role]
  local firstTime = not incoming
  if firstTime then
    incoming = ns.CopyTable(ns.MODE_DEFAULTS[role] or {})
    ns.db.modes[role] = incoming
  end
  -- Clicks someone set up while the build wrongly sat in another role are
  -- theirs: they come along. A fresh install (no click ever changed) keeps
  -- the role's own defaults.
  local oldClicks = ns.db.modes[current].bindings
  if firstTime and type(oldClicks) == "table" and type(ns.db.bindingLog) == "table" and #ns.db.bindingLog > 0 then
    incoming.bindings = ns.CopyTable(oldClicks)
  end
  LoadFrom(incoming, role)
  ns.db.mode = role
  ns.UseBindingStore(role)
  return true
end

-- Switch the active role. Parks the current role's settings, brings in the
-- other role's (a saved copy, or that role's defaults), and re-applies. Safe
-- to call in combat: the secure parts wait for it to end, as they always do.
function ns.SetMode(newMode, opts)
  if ns.lockedRole then
    newMode = ns.lockedRole
  elseif not ns.IsSupportedMode(newMode) then
    newMode = "healer"
  end
  local current = ns.db.mode or "healer"
  if newMode == current and not (opts and opts.force) then
    return current
  end
  ns.db.modes = ns.db.modes or {}
  ns.db.modes[current] = ns.db.modes[current] or {}
  CaptureInto(ns.db.modes[current])

  local incoming = ns.db.modes[newMode]
  if not incoming then
    incoming = ns.CopyTable(ns.MODE_DEFAULTS[newMode] or {})
    ns.db.modes[newMode] = incoming
  end
  LoadFrom(incoming, newMode)
  ns.db.mode = newMode
  ns.UseBindingStore(newMode)
  if ns.Trace then ns.Trace("SetMode -> " .. tostring(newMode)) end

  if ns.RebuildWatchIndex then ns.RebuildWatchIndex() end
  if ns.ApplyClassDefaults then ns.ApplyClassDefaults(false) end
  if ns.ApplyBindings then ns.ApplyBindings() end
  if ns.SetupLayout then ns.SetupLayout() end   -- rebuilds the tank-only frames per mode
  -- The focus group is per role now: its switch, its place and its size all
  -- belong to the role being switched into.
  if ns.ApplyFocusPosition then ns.ApplyFocusPosition() end
  if ns.ApplyFocus then ns.ApplyFocus() end
  if ns.RefreshAll then ns.RefreshAll() end
  if ns.RebuildOptions then
    ns.RebuildOptions()   -- the options panel is laid out per role
  elseif ns.RefreshOptions then
    ns.RefreshOptions()
  end
  return newMode
end

-- Following your form used to live here: shifting into Bear switched the whole
-- UI to the tank setup and back out again, with the clicks handled by a macro
-- that knew both roles. It has been removed in favour of the grids, which
-- put every role on screen at once and switch nothing -- no form to read, no
-- macro conditions, and no handler on UPDATE_SHAPESHIFT_FORM, an event
-- Blizzard's own unit frames also listen for and which used to carry our taint
-- onto their stack. See Modules/Grids.

---------------------------------------------------------------------------
-- Role flips: ask before switching the frames
---------------------------------------------------------------------------
--
-- When you change role within a class -- a druid swapping to Guardian, a
-- paladin to Holy -- the frames don't just switch under you: they ask first,
-- because you might be respeccing for five minutes and want your layout left
-- alone. A role this build has no frames for (the standalone HealForever and
-- TankForever carry one each) is said once, never offered.

local ROLE_LABELS = { tank = "Tank", healer = "Healer", dps = "DPS" }
function ns.RoleLabel(mode)
  return ROLE_LABELS[mode] or mode
end

-- The role the game currently has this character in, as a frame mode. Prefers
-- the active spec's role; falls back to the assigned group role. All guarded,
-- because a low-level Classic+ character may have neither.
function ns.DetectRole()
  local role
  if GetSpecialization and GetSpecializationRole then
    local ok, spec = pcall(GetSpecialization)
    if ok and spec then
      local ok2, r = pcall(GetSpecializationRole, spec)
      if ok2 then role = r end
    end
  end
  if not role and UnitGroupRolesAssigned then
    local ok, r = pcall(UnitGroupRolesAssigned, "player")
    if ok then role = r end
  end
  if role == "TANK" then
    return "tank"
  elseif role == "HEALER" then
    return "healer"
  elseif role == "DAMAGER" or role == "DPS" then
    return "dps"
  end
  return nil
end

if StaticPopupDialogs then
  StaticPopupDialogs["FOREVERUI_FRAMES_ROLESWITCH"] = {
    text = "Your role changed to %s. Switch your frames to the %s layout?",
    button1 = "Switch",
    button2 = "Keep",
    OnAccept = function(_, mode) ns.SetMode(mode) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, -- avoids tainting the default StaticPopup slots
  }
end

-- Asked once per role until it changes to something else, so a respec back and
-- forth doesn't nag. `force` re-asks (used by a manual /fui role auto).
local askedFor
function ns.CheckRoleFlip(force)
  local role = ns.DetectRole()
  if not role then
    return false
  end
  if role == ns.GetMode() then
    askedFor = nil
    return false
  end
  -- A role this build has no frames for: say so once, don't offer a switch to nothing.
  if not ns.IsSupportedMode(role) then
    if askedFor ~= role then
      askedFor = role
      ns.Print(("you're in a %s spec now. This addon has no %s frames -- your %s frames are still here."):format(
        ns.RoleLabel(role), ns.RoleLabel(role), ns.RoleLabel(ns.GetMode())))
    end
    return false
  end
  if askedFor == role and not force then
    return false
  end
  askedFor = role
  if StaticPopup_Show then
    StaticPopup_Show("FOREVERUI_FRAMES_ROLESWITCH", ns.RoleLabel(role), ns.RoleLabel(role), role)
    return true
  end
  return false
end
