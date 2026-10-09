local _, OSG = ...

local PREFIX = "|cffff9933OverlapSettingsGuard|r"
local POPUP = "OVERLAPSETTINGSGUARD_OFF"
local POPUP_RELOAD = "OVERLAPSETTINGSGUARD_OFF_RELOAD"
local START_DELAY = 2
-- Safety net for changes that reach no hook, such as `/fui quests guide on`.
local TICK_SECONDS = 2
local POPUP_GAP_SECONDS = 10

local lastPopup = {}
local warnedBlocked = {}
local checkQueued = false
local waitingForCombat = false
local started = false

local function Print(message)
  print(PREFIX, message)
end

local function IsLoaded(name)
  return C_AddOns.IsAddOnLoaded(name) and true or false
end

StaticPopupDialogs[POPUP] = {
  text = "%s",
  button1 = OKAY or "OK",
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs[POPUP_RELOAD] = {
  text = "%s",
  button1 = "Reload now",
  button2 = "Later",
  OnAccept = function()
    ReloadUI()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function ShowPopup(rules, reload)
  local now = GetTime()
  local lines = {}
  for _, rule in ipairs(rules) do
    if not lastPopup[rule.id] or now - lastPopup[rule.id] >= POPUP_GAP_SECONDS then
      lastPopup[rule.id] = now
      lines[#lines + 1] = ("%s\n|cffbbbbbb%s|r"):format(rule.label, rule.reason)
    end
  end
  if #lines == 0 then
    return
  end
  local text = "OverlapSettingsGuard switched off:\n\n" .. table.concat(lines, "\n\n")
    .. "\n\nThese settings overlap another installed add-on and stay off."
  if reload then
    StaticPopup_Show(POPUP_RELOAD, text .. "\nA reload applies the change.")
  else
    StaticPopup_Show(POPUP, text)
  end
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

-- Reverting in combat could touch ForeverUI's map pins, so it waits for combat to end.
local function Enforce(rules)
  if InCombatLockdown() then
    waitingForCombat = true
    return
  end
  local switchedOff, reload = {}, false
  for _, rule in ipairs(rules) do
    local called, ok, needsReload, otherProfiles = pcall(OSG.adapters[rule.adapter].Revert, rule.key, rule)
    if not called then
      ok, needsReload = false, ok
    end
    if ok then
      switchedOff[#switchedOff + 1] = rule
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
  if #switchedOff > 0 then
    ShowPopup(switchedOff, reload)
  end
end

function OSG.Check()
  local results = OSG.Evaluate(OSG.policy, OSG.adapters, IsLoaded)
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
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(START_DELAY, Start)
  elseif event == "PLAYER_REGEN_ENABLED" and waitingForCombat then
    waitingForCombat = false
    RequestCheck()
  end
end)
