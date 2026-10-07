local ADDON, ns = ...

-- ForeverUI core: the namespace, the module registry, and the event plumbing
-- everything else hangs off. Modules register here rather than wiring
-- themselves into the game directly, so the core can enable, disable and
-- re-apply them as one, and so a broken module can't take the UI with it.

_G.ForeverUI = ns -- the one global; XML scripts and other addons reach us here

ns.ADDON = ADDON
-- Media lives under whatever the folder is called (it may be installed under
-- another name -- see tools/install_fui.sh).
ns.MEDIA_PATH = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
-- Classic Era moved this into C_AddOns; older clients keep the global.
local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (metadata and metadata(ADDON, "Version")) or "dev"

---------------------------------------------------------------------------
-- Small shared helpers
---------------------------------------------------------------------------

function ns.CopyTable(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = type(v) == "table" and ns.CopyTable(v) or v
  end
  return copy
end

function ns.Wipe(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end

-- Fill missing keys from `defaults` without touching what the user set.
function ns.FillDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then
        target[key] = {}
      end
      ns.FillDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

-- The name in front of everything we say, in the UI's border colour so the
-- chat matches the rest of it.
local function Prefix()
  local c = ns.Colors and ns.Colors.ui and ns.Colors.ui.accent
  if not c then
    return "|cff4dc3ffForeverUI|r"
  end
  return ("|cff%02x%02x%02xForeverUI|r"):format(
    math.floor((c[1] or 0.3) * 255 + 0.5),
    math.floor((c[2] or 0.76) * 255 + 0.5),
    math.floor((c[3] or 1) * 255 + 0.5))
end

function ns.Print(...)
  print(Prefix(), ...)
end

---------------------------------------------------------------------------
-- Combat lockdown: secure frames can't be built or moved in combat.
---------------------------------------------------------------------------

local pending = {}

function ns.WhenOutOfCombat(fn)
  if InCombatLockdown() then
    pending[#pending + 1] = fn
  else
    fn()
  end
end

-- A game setting, written only when it is actually changing. Every SetCVar
-- fires CVAR_UPDATE at once, and Blizzard's listeners (the status-bar
-- manager re-lays out Edit Mode containers on it) then run in ForeverUI's
-- name -- so a login or an options refresh that sets the same values again
-- shouldn't touch the game at all. Returns true if it changed something.
function ns.SetCVar(cvar, value)
  if not SetCVar then return false end
  value = tostring(value)
  if GetCVar then
    local ok, current = pcall(GetCVar, cvar)
    if ok and current == value then return false end
  end
  return (pcall(SetCVar, cvar, value))
end

function ns.HasPending()
  return #pending > 0
end

-- Each job on its own: one that throws is reported and the rest still run
-- (it used to stop the loop, and every job queued after it was dropped).
local function RunPending()
  local queued = pending
  pending = {}
  for i = 1, #queued do
    local ok, err = pcall(queued[i])
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

---------------------------------------------------------------------------
-- Reloading
---------------------------------------------------------------------------
--
-- A few things genuinely can't be undone while the game is running: Blizzard
-- frames we took apart only come back when the interface is rebuilt. Where
-- that's true, ForeverUI asks for one -- once, with a button.
--
-- It used to call ReloadUI() on a timer, which the game blocks: reloading is
-- a protected action and an addon may only trigger it from a real click.
-- Doing it on a timer earned an ADDON_ACTION_BLOCKED and no reload. So a
-- prompt appears instead and the click is yours.
--
-- Several changes coalesce into one prompt, and it never appears in combat --
-- it waits until the fight is over.

local reloadPending = false
local prompt

function ns.ReloadPending()
  return reloadPending
end

local function BuildPrompt()
  prompt = CreateFrame("Frame", "ForeverUIReloadPrompt", UIParent)
  prompt:SetSize(340, 120)
  prompt:SetPoint("TOP", UIParent, "TOP", 0, -160)
  prompt:SetFrameStrata("DIALOG")
  prompt:EnableMouse(true)
  prompt:SetMovable(true)
  prompt:RegisterForDrag("LeftButton")
  prompt:SetScript("OnDragStart", prompt.StartMoving)
  prompt:SetScript("OnDragStop", prompt.StopMovingOrSizing)
  ns.Skin.Panel(prompt, { color = { 0.06, 0.06, 0.08, 0.96 } })
  ns.Skin.Header(prompt, "ForeverUI", function() prompt:Hide() end)

  prompt.text = prompt:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(prompt.text, "general")
  prompt.text:SetPoint("TOPLEFT", 16, -38)
  prompt.text:SetPoint("TOPRIGHT", -16, -38)
  prompt.text:SetJustifyH("LEFT")
  prompt.text:SetTextColor(unpack(ns.Colors.ui.text))

  prompt.reload = ns.OptionButton(prompt, 140, "Reload now", function()
    -- A real click, so the game allows it. A timer would not.
    if ns.MacroBackup then pcall(ns.MacroBackup.Write) end
    if ReloadUI then
      ReloadUI()
    end
  end)
  prompt.reload:SetPoint("BOTTOMRIGHT", -16, 14)

  prompt.later = ns.OptionButton(prompt, 100, "Later", function()
    prompt:Hide()
  end)
  prompt.later:SetPoint("BOTTOMLEFT", 16, 14)

  ns.reloadPrompt = prompt
  return prompt
end

function ns.RequestReload(reason)
  -- A loadout switch moves a dozen modules at once, and several of them may
  -- each ask for a reload. Naming whichever one happened to ask first is
  -- true but useless ("Cast Bar off needs a reload" when what you did was
  -- ask for the frames only), so the switch says what it is and that wins.
  reason = ns.reloadReason or reason
  if reloadPending then
    return true
  end
  reloadPending = true
  ns.WhenOutOfCombat(function()
    if not prompt then
      BuildPrompt()
    end
    prompt.text:SetText(("%s needs the interface reloaded to take effect."):format(
      reason or "That change"))
    prompt:Show()
  end)
  ns.Print(("%s needs a reload - there's a button for it."):format(reason or "that change"))
  return true
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
--
-- A module is a table:
--   name       unique key, also its settings key
--   title      what the options window calls it
--   defaults   settings table merged into every profile
--   OnInit     once, after saved variables load and the profile is chosen
--   OnEnable   every time the module turns on (and on profile switch)
--   OnDisable  when it turns off; put Blizzard's frames back if you took them
--   Refresh    settings changed; re-read them
--   needsReload  true if disabling can't be undone without /reload

ns.modules = {}
ns.moduleOrder = {}

function ns.RegisterModule(module)
  assert(module.name, "module needs a name")
  assert(not ns.modules[module.name], "module registered twice: " .. module.name)
  ns.modules[module.name] = module
  ns.moduleOrder[#ns.moduleOrder + 1] = module.name
  return module
end

function ns.GetModule(name)
  return ns.modules[name]
end

-- In registration order, so a module can rely on earlier ones being ready.
function ns.ForEachModule(fn)
  for _, name in ipairs(ns.moduleOrder) do
    fn(ns.modules[name], name)
  end
end

function ns.IsModuleEnabled(name)
  local settings = ns.db and ns.db.modules and ns.db.modules[name]
  return settings == nil or settings.enabled ~= false
end

-- Switched on, and not sitting out for the controller (Core/Controller.lua).
function ns.ModuleRunning(name)
  return ns.IsModuleEnabled(name) and not (ns.ControllerSuspended and ns.ControllerSuspended(name))
end

local function SafeCall(module, method, ...)
  local fn = module[method]
  if not fn then
    return
  end
  -- One module's error shouldn't stop the rest of the UI loading.
  local ok, err = pcall(fn, module, ...)
  if not ok then
    ns.Print(("|cffff6666%s.%s failed:|r %s"):format(module.name, method, tostring(err)))
  end
end

function ns.SetModuleEnabled(name, enabled)
  local module = ns.modules[name]
  if not module then
    return
  end
  ns.db.modules[name] = ns.db.modules[name] or {}
  ns.db.modules[name].enabled = enabled and true or false
  if enabled and ns.ControllerSuspended and ns.ControllerSuspended(name) then
    return   -- remembered; it starts when the controller isn't in charge
  elseif enabled then
    SafeCall(module, "OnEnable")
  elseif module.needsReload then
    SafeCall(module, "OnDisable")
    ns.RequestReload(("%s off"):format(module.title or name))
  else
    SafeCall(module, "OnDisable")
  end
end

-- Re-apply every enabled module, e.g. after switching profiles.
function ns.RefreshAllModules()
  ns.ForEachModule(function(module, name)
    if ns.ModuleRunning(name) then
      SafeCall(module, "Refresh")
    end
  end)
end

local function InitModules()
  ns.ForEachModule(function(module, name)
    ns.db.modules[name] = ns.db.modules[name] or {}
    SafeCall(module, "OnInit")
  end)
  ns.ForEachModule(function(module, name)
    if ns.ModuleRunning(name) then
      SafeCall(module, "OnEnable")
    end
  end)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

driver:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    self:UnregisterEvent("ADDON_LOADED")
    -- First thing, so it's watching before any of our own setup can throw.
    if ns.Errors then
      ns.Errors.Install()
    end
    ns.InitProfiles()  -- Core/Profiles.lua
    ns.InitMedia()     -- Core/Media.lua
  elseif event == "PLAYER_LOGIN" then
    ns.ResolveProfile() -- now the game knows which character this is
    -- The beta handed back nothing? Lay the macro backup over the fresh
    -- profile before any module reads it (Core/MacroBackup.lua).
    if ns.MacroBackup then ns.MacroBackup.RestoreIfNeeded() end
    -- Before the modules build anything: they take the accent colour by
    -- reference, so it has to say what this profile wants first.
    ns.ApplyAccentColor()
    ns.loggingIn = true    -- until the world is in (see the QuestForever module)
    InitModules()
    if ns.MacroBackup then ns.MacroBackup.HookChanges() end
    ns.CreateMinimapButton()
    -- Made after the modules start, so the minimap has to be told to collect
    -- it into the button bar with the rest.
    local minimap = ns.modules.Minimap
    if minimap and minimap.GatherButtons and ns.IsModuleEnabled("Minimap") then
      SafeCall(minimap, "GatherButtons")
    end
    -- Frames taken with /fui grab are taken again, after the bar has had
    -- its pick, so a grab wins over the bar.
    pcall(ns.RegrabAll)
    -- First run: one window. The welcome, the questions and who to tell
    -- when it breaks are all steps of the same wizard (Core/Install.lua).
    -- (Opened once the world is in, not now: entering the world closes every
    -- window Escape can close, and the wizard is one. Opened at login it was
    -- gone within a second, every login - the play recorder's first capture,
    -- 27 Sept 2026 - so a player who hadn't finished setup never saw it.)
    ns.installerDue = not ns.db.installed
    -- If we've logged any faults, mention it once -- quietly, and only the
    -- count, so a report is one /fui errors away without nagging.
    if ns.Errors then
      local n = ns.Errors.Count()
      if n > 0 then
        ns.Print(("caught %d error%s so far. Type /fui errors to copy them for a bug report.")
          :format(n, n == 1 and "" or "s"))
      end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    ns.loggingIn = false
    if ns.installerDue then
      ns.installerDue = false
      local function open()
        if ns.db and not ns.db.installed then ns.ShowInstaller() end -- first run: guided setup
      end
      if C_Timer and C_Timer.After then C_Timer.After(1.5, open) else open() end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    RunPending()
  end
end)

ns.eventDriver = driver
