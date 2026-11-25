local _, baseline = ...

-- Windows other add-ons and the client open by themselves at login: first-run setup on a new
-- character or account, and notices after an add-on update. The account's shared profiles
-- already hold the finished setup, so each one is skipped, not answered. Manual entry points
-- stay available, e.g. YUI's game-menu installer button, /gif lv for GearInsight's leveling
-- window and YUI's Changelog settings page.

local NEVER = 2147483647

local function Loaded(name)
  return C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded(name) and true or false
end

-- YUI's login tasks look these up when they run, so replacing them here is enough.
-- Skipping the wizard also leaves the character unmarked, which keeps YUI's own Edit Mode
-- prompt idle; EditModeLayout.lua selects the account layout instead.
local function QuietYUI()
  local yui = _G.YUI
  if type(yui) ~= "table" then return end
  if type(yui.Installer) == "table" then
    yui.Installer.CheckInstall = function(_, onDone)
      if type(onDone) == "function" then onDone() end
      return false
    end
  end
  if type(yui.EditMode) == "table" then
    yui.EditMode.CheckAndPromptSwitchToYUI = function() end
  end
  if type(yui.Changelog) == "table" then
    yui.Changelog.CheckVersion = function(changelog)
      local data = type(changelog.GetData) == "function" and changelog:GetData()
      local latest = type(data) == "table" and data[1] and data[1].version
      if latest and type(yui.global) == "table" then yui.global.lastChangelogVersion = latest end
    end
  end
end

-- On a fresh EllesmereUI account the module and style pickers open (ending in a forced reload);
-- an account restored with profiles is stamped the same way by EllesmereUI itself. Its
-- once-per-session incompatible-add-on popup is held too: OverlapSettingsGuard covers overlaps.
local function QuietEllesmereUI()
  local db, eui = _G.EllesmereUIDB, _G.EllesmereUI
  if type(db) == "table" then
    db.firstInstallPopupShown = true
    db.styleChoicePending = nil
  end
  if type(eui) == "table" then
    eui._firstInstallPending = nil
    eui._styleChoicePending = nil
  end
  _G._EUI_ConflictCheckRan = true
end

-- GearInsight shows its leveling window per character below level 60; OverlapSettingsGuard's
-- gi.levelingstats rule turns it off under YUI only after it has appeared and been announced.
local function QuietGearInsight()
  local gi = _G.GearInsightForever
  if type(gi) ~= "table" then return end
  if Loaded("YUI") and type(gi.LevelingShown) == "function" and type(gi.SetLevelingShown) == "function"
    and gi.LevelingShown() then
    gi.SetLevelingShown(false)
  end
  local news = gi.WhatsNew
  if type(news) == "table" and type(news.Current) == "function" then
    news.Check = function()
      local _, version = news.Current()
      if version and type(gi.db) == "table" then gi.db.whatsNewSeen = version end
      return false
    end
  end
end

-- The welcome wizard opens only on an account's first Details run; that run's other setup stays.
local function QuietDetails()
  local details = _G.Details
  if not (type(details) == "table" and details.is_first_run) then return end
  local open = details.OpenWelcomeWindow
  if type(open) ~= "function" or details.quietLogin then return end
  details.quietLogin = true
  details.OpenWelcomeWindow = function() details.OpenWelcomeWindow = open end
end

local function QuietGatherLite()
  local gather = _G.GatherLite
  local db = type(gather) == "table" and gather.db
  if type(db) == "table" and type(db.global) == "table" then db.global.controlsGuideSeen = true end
end

-- MapUtils keeps an existing WHATSNEW table when it builds the window at login. Since 1.7.35 it
-- marks a profile without saved settings PRESETSHOWN=false at PLAYER_LOGIN and opens its map
-- preset dialog at PLAYER_ENTERING_WORLD; a stored true skips that. /maputils preset still opens it.
local function QuietMapUtils()
  if type(_G.MAUTTAB) ~= "table" then
    if not Loaded("MapUtils") then return end
    _G.MAUTTAB = {}
  end
  local db = _G.MAUTTAB
  db.PRESETSHOWN = true
  if type(db.WHATSNEW) ~= "table" then db.WHATSNEW = {} end
  db.WHATSNEW.enabled = false
end

-- Bagnon's outdated-version popup waits for this time; another player's newer version
-- updates the version but leaves the time alone.
local function QuietBagnon()
  local sets = _G.Bagnon_Sets
  if type(sets) ~= "table" then return end
  if type(sets.latest) ~= "table" then sets.latest = {} end
  sets.latest.cooldown = NEVER
end

-- Blizzard help tips are remembered per character (closedInfoFrames) and per account.
local function QuietBlizzard()
  local cvar = C_CVar
  if not (cvar and type(cvar.GetCVarBitfield) == "function" and type(cvar.SetCVarBitfield) == "function") then return end
  for name, flag in pairs(_G) do
    if type(name) == "string" and type(flag) == "number" and name:find("^LE_FRAME_TUTORIAL_") then
      local field = name:find("^LE_FRAME_TUTORIAL_ACCOUNT_") and "closedInfoFramesAccountWide" or "closedInfoFrames"
      if not cvar.GetCVarBitfield(field, flag) then cvar.SetCVarBitfield(field, flag, true) end
    end
  end
  if type(cvar.GetCVar) == "function" and cvar.GetCVar("showTutorials") == "1" then cvar.SetCVar("showTutorials", "0") end
end

local steps = { QuietYUI, QuietEllesmereUI, QuietGearInsight, QuietDetails, QuietGatherLite, QuietMapUtils, QuietBagnon, QuietBlizzard }

function baseline.QuietLogin()
  for _, step in ipairs(steps) do pcall(step) end
end

baseline.QuietLogin()
local events = CreateFrame("Frame")
-- The realm name, which GearInsight's per-character key needs, is complete only from login.
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() baseline.QuietLogin() end)
