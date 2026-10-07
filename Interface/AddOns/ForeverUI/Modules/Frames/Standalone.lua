local ADDON_NAME, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- The engine booting on its own, as HealForever or TankForever.
--
-- This file is the ONLY difference between the party/raid frames inside
-- ForeverUI and the two addons that ship them on their own. Everything else
-- -- all 8,000-odd lines of it -- is the same source, built twice. Inside
-- ForeverUI, Integration.lua is loaded and this file is not; in a standalone
-- build it is the other way round, and neither one knows about the other.
--
-- What the engine expects from ForeverUI's core, and what this file has to
-- stand in for:
--
--   FUI.db                the profile the frames live inside (they use
--                         FUI.db.frames, a sub-table, in both builds)
--   FUI.ActiveProfileName which profile that is, for the window's footer
--   FUI.MEDIA_PATH        where the logo and the glyphs are
--   FUI.Skin              drawn by Core/Skin.lua, which the build copies in
--   FUI.OpenOptions       ForeverUI's own window; there isn't one here, and
--                         every call site already checks before using it
--
-- Two things are deliberately NOT copied from ForeverUI: its profile system
-- (a standalone addon keeps one setting-set per character, below) and its
-- options window (the engine has its own, in Options.lua).

---------------------------------------------------------------------------
-- Where the settings live
---------------------------------------------------------------------------

-- The saved variable is named after the folder, so a build under any name --
-- HealForever, TankForever, or a differently-named local copy for testing --
-- gets its own store without a source change. The TOC declares the matching
-- name; the build script writes both from the same string.
local SAVED_NAME = ADDON_NAME .. "DB"

-- On its own, not inside ForeverUI. Read by anything that must not reach into
-- ForeverUI's saved variables from here.
ns.standalone = true

local function CharacterKey()
  local name = UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return name .. " - " .. realm
end
ns.StandaloneCharacterKey = CharacterKey

-- One set of settings per character, which is what a single-purpose addon
-- wants. ForeverUI's richer profile system (named profiles you can copy
-- between characters) belongs to ForeverUI; here it would be a second thing
-- to keep in step for no gain.
local function ResolveDB()
  local store = rawget(_G, SAVED_NAME)
  if type(store) ~= "table" then
    store = {}
    _G[SAVED_NAME] = store
  end
  store.characters = store.characters or {}
  local key = CharacterKey()
  store.characters[key] = store.characters[key] or {}
  FUI.db = store.characters[key]
  return FUI.db
end
ns.StandaloneResolveDB = ResolveDB

function FUI.ActiveProfileName()
  return CharacterKey()
end

---------------------------------------------------------------------------
-- Standing aside for ForeverUI
---------------------------------------------------------------------------

-- ForeverUI carries this same engine. Running both would put two sets of
-- party frames on screen fighting over the same units, so the standalone
-- copy steps aside and says why. It does not turn ForeverUI off and it does
-- not delete anything: it simply doesn't build.
local HOSTS = { "ForeverUI", "ForeverUIApp", "ForeverUICore" }

function ns.ForeverUIPresent()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not loaded then
    return nil
  end
  for _, folder in ipairs(HOSTS) do
    local ok, isLoaded = pcall(loaded, folder)
    if ok and isLoaded then
      return folder
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

-- Everything happens at PLAYER_LOGIN rather than ADDON_LOADED, for the same
-- reason ForeverUI does it there: the character's name is what picks the
-- settings, and it isn't reliably there any earlier.
-- Which role this build is. HealForever heals, TankForever tanks -- that is
-- the point of them being separate downloads from ForeverUI, which carries
-- all three. Read off the folder name so a build under any name still lands
-- on the right one.
local function BuildRole()
  local name = ADDON_NAME:lower()
  if name:find("tank") then
    return "tank"
  elseif name:find("dps") or name:find("damage") then
    return "dps"
  end
  return "healer"
end
ns.StandaloneRole = BuildRole

local function Boot()
  if ns.booted then
    return false
  end

  local host = ns.ForeverUIPresent()
  if host then
    ns.standDown = host
    ns.Print(("ForeverUI is installed and already draws these frames, so %s is standing aside. "
      .. "Open its settings with /fui frames. If you would rather have this one, disable ForeverUI's "
      .. "Party & Raid Frames on its Modules page, or remove this addon."):format(ADDON_NAME))
    return false
  end

  FUI.MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
  ResolveDB()
  -- Before anything reads a role or builds a grid.
  if ns.LockRole then
    ns.LockRole(BuildRole())
  end
  if FUI.InitMedia then FUI.InitMedia() end   -- Core/Media.lua, copied in by the build
  ns.LocalizeSpellNames()   -- spell lists in the game's own language (SpellData.lua)
  ns.InitProfiles()
  if ns.EnterLockedRole then ns.EnterLockedRole() end   -- the settings say which role only now
  ns.LocalizeSavedSpellNames()
  ns.booted = true            -- the event driver in Frames.lua ignores anything before this
  ns.FlushErrors()            -- whatever broke before there were settings to break against
  ns.RebuildWatchIndex()
  ns.SetupLayout()

  -- Once per install: who to tell when it breaks. These two are the addons
  -- people actually download, so they are where the bug reports come from --
  -- and a report only arrives if saying so is easy.
  if not FUI.db.metAuthor then
    FUI.db.metAuthor = true
    ns.Print(("%s is a beta, built for WoW: Forever by Solindius. If something "
      .. "breaks I would rather hear it -- Battle.net |cffffd100Recounted#1297|r. "
      .. "Forever goes live 6 November."):format(ADDON_NAME))
  end
  if ns.CheckRoleFlip then
    ns.WhenOutOfCombat(ns.CheckRoleFlip)
  end
  return true
end
ns.StandaloneBoot = Boot

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
  Boot()
end)
ns.standaloneDriver = driver

-- Already logged in when this loaded (a mid-session enable): boot now, since
-- PLAYER_LOGIN has been and gone.
if IsLoggedIn and IsLoggedIn() then
  Boot()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

-- The dispatcher is the engine's own (Frames.lua), the same one ForeverUI
-- reaches through "/fui frames". Here it gets the short commands instead:
-- /hf or /tf, plus the addon's full name.
-- HealForever becomes /hf, TankForever /tf: the initials of the capitalised
-- words, so a build under any folder name still gets a short command.
local function Initials(name)
  local letters = name:gsub("[^A-Z]", "")
  return letters:lower()
end

local function RegisterSlash()
  local key = ADDON_NAME:upper()
  local short = Initials(ADDON_NAME)
  _G["SLASH_" .. key .. "1"] = "/" .. ADDON_NAME:lower()
  if #short >= 2 then
    _G["SLASH_" .. key .. "2"] = "/" .. short
  end
  ns.SLASH = "/" .. (#short >= 2 and short or ADDON_NAME:lower())   -- for messages that name a command
  SlashCmdList[key] = function(msg)
    if ns.standDown then
      ns.Print(("standing aside for %s -- use /fui frames instead."):format(ns.standDown))
      return
    end
    if ns.HandleSlash then
      ns.HandleSlash(msg or "")
    end
  end
end
RegisterSlash()
ns.StandaloneRegisterSlash = RegisterSlash
