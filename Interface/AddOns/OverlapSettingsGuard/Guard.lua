local _, OSG = ...

local PREFIX = "|cffff9933OverlapSettingsGuard|r"
local START_DELAY = 2
-- Some profile changes bypass option hooks.
local TICK_SECONDS = 2

local warnedBlocked = {}
local checkQueued = false
local waitingForCombat = false
local started = false
local startQueued = false

local function Print(message)
  print(PREFIX, message)
end

local function IsLoaded(name)
  return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function ReportBlocked(results)
  for _, result in ipairs(results) do
    if result.status == OSG.STATUS.BLOCKED and not warnedBlocked[result.rule.id] then
      warnedBlocked[result.rule.id] = true
      Print(("cannot enforce %s: %s. Update the rule in OverlapSettingsGuard."):format(
        result.rule.label, result.detail))
    end
  end
end

-- Protected frame and CVar changes must wait until combat ends.
local function Enforce(rules)
  if InCombatLockdown() then
    waitingForCombat = true
    return
  end
  local reload = false
  for _, rule in ipairs(rules) do
    local called, ok, needsReload, otherProfiles = pcall(OSG.adapters[rule.adapter].Revert, rule.key, rule)
    if not called then
      ok, needsReload = false, ok
    end
    if ok then
      reload = reload or (rule.needsReload and needsReload) or false
      local also = ""
      if type(otherProfiles) == "table" and #otherProfiles > 0 then
        also = (" Also switched off in profiles: %s."):format(table.concat(otherProfiles, ", "))
      end
      Print(("switched off %s. %s%s"):format(rule.label, rule.reason, also))
    else
      Print(("could not switch off %s: %s"):format(rule.label, tostring(needsReload)))
    end
  end
  if reload then
    Print("A reload applies these changes. Type /reload when ready.")
  end
end

function OSG.Check(earlyOnly)
  local policy = OSG.policy
  if earlyOnly then
    policy = {}
    for _, rule in ipairs(OSG.policy) do
      if rule.early then policy[#policy + 1] = rule end
    end
  end
  local results = OSG.Evaluate(policy, OSG.adapters, IsLoaded)
  ReportBlocked(results)
  local violations = OSG.Violations(results)
  if #violations > 0 then
    Enforce(violations)
  end
  return results
end

-- Hooks fire inside the other add-on's own handlers; checking on the next frame lets
-- those finish first and folds a burst of hook calls into one check.
local function RequestCheck()
  if checkQueued or not started then
    return
  end
  checkQueued = true
  C_Timer.After(0, function()
    checkQueued = false
    OSG.Check()
  end)
end

local function Start()
  for _, problem in ipairs(OSG.ValidatePolicy(OSG.policy, OSG.adapters)) do
    Print("policy error: " .. problem)
  end
  local watched = {}
  for _, rule in ipairs(OSG.policy) do
    local adapter = OSG.adapters[rule.adapter]
    if adapter and not watched[adapter] and IsLoaded(rule.when[1]) then
      watched[adapter] = true
      local ok, err = pcall(adapter.Watch, RequestCheck)
      if not ok then
        Print(("could not watch %s: %s"):format(rule.adapter, tostring(err)))
      end
    end
  end
  started = true
  OSG.Check()
  C_Timer.NewTicker(TICK_SECONDS, RequestCheck)
  SetCVar("outlineModeShowLootEffectWhenDisabled", "1")
  SetCVar("cameraDistanceMaxZoomFactor", "4")
  SetCVar("nameplateMaxDistance", "41")
  SetCVar("targetNearestDistanceRadius", "50")
  SetCVar("ffxGlow", "0")
  SetCVar("volumeFog", "0")
  SetCVar("ResampleAlwaysSharpen", "1")
  SetCVar("Contrast", "85")
  SetCVar("Brightness", "55")
  SetCVar("Gamma", "1.5")
end

local STATUS_TEXT = {
  [OSG.STATUS.OFF] = "|cff60ff60locked off|r",
  [OSG.STATUS.ON] = "|cffff6060on, switching off|r",
  [OSG.STATUS.INACTIVE] = "|cff999999inactive|r",
  [OSG.STATUS.BLOCKED] = "|cffffb030cannot enforce|r",
}

SLASH_OVERLAPSETTINGSGUARD1 = "/osg"
SlashCmdList.OVERLAPSETTINGSGUARD = function()
  local results = OSG.Evaluate(OSG.policy, OSG.adapters, IsLoaded)
  Print("rules:")
  for _, result in ipairs(results) do
    local detail = result.detail and (" (" .. result.detail .. ")") or ""
    print(("  %s: %s%s"):format(result.rule.label, STATUS_TEXT[result.status], detail))
  end
  RequestCheck()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    OSG.Check(true)
  elseif event == "PLAYER_ENTERING_WORLD" and not startQueued then
    startQueued = true
    -- World-entry handlers can overwrite CVars during login initialization.
    C_Timer.After(START_DELAY, Start)
  elseif event == "PLAYER_REGEN_ENABLED" and waitingForCombat then
    waitingForCombat = false
    RequestCheck()
  end
end)

-- Skinner can enable its UnitFrames module during PLAYER_LOGIN, before our handler.
OSG.Check(true)
