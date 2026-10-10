local Stubs = assert(loadfile(TESTS_ROOT .. "stubs.lua"))()

local tests, failures = {}, {}

local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
  end
end

local function ok(value, what)
  if not value then error((what or "condition") .. " failed", 2) end
end

local function StatusOf(results, id)
  for _, result in ipairs(results) do
    if result.rule.id == id then return result.status, result.detail end
  end
end

local function AllLoaded()
  return { Leatrix_Plus = true, ForeverUI = true, RXPGuides = true }
end

local function DefaultUI()
  return {
    modules = { QuestForever = { enabled = false }, Arrow = { enabled = false } },
    quests = { guideOnAccept = false, guideOnAcceptPad = false },
  }
end

test("the shipped policy has no errors", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  local problems = w.ns.ValidatePolicy(w.ns.policy, w.ns.adapters)
  eq(#problems, 0, "policy problems: " .. table.concat(problems, "; "))
  eq(#w.ns.policy, 16, "rule count")
end)

local function RxpOff()
  return { autoSellJunk = false, enableTalentGuides = false, enableMaxNameplateDistance = false, disableUpgradeTooltip = true, enableQuestAutomation = false, enableQuestRewardAutomation = false, enableQuestChoiceAutomation = false, enableGossipAutomation = false }
end

test("RestedXP settings read with RXP's defaults, the upgrade tooltip inverted", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), rxp = { live = {} } })
  local a = w.ns.adapters.RestedXP
  eq(a.Read("AutoSellJunk"), false, "autoSellJunk defaults off")
  eq(a.Read("TalentGuides"), true, "talent guides default on")
  eq(a.Read("MaxNameplateDistance"), true, "nameplate distance default on")
  eq(a.Read("UpgradeTooltip"), true, "tooltip shown while disableUpgradeTooltip is unset")
end)

test("RestedXP settings are switched off in the live profile, every stored profile and both templates", function()
  local loaded = AllLoaded()
  loaded.TalentsForeverBook = true
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, foreverui = DefaultUI(), rxp = {
    live = { autoSellJunk = true },
    profiles = { ["Alt - Realm"] = {} },
    accountDefault = {},
    characterDefault = { enableTalentGuides = true },
  } })
  w.Login()
  -- The templates get explicit values; a stored profile without its own value inherits
  -- the account template, as AceDB does, so it needs no write.
  for _, store in ipairs({ RXP.settings.profile, RXPData.defaultProfile.profile, RXPCData.localDB.profile }) do
    for field, value in pairs(RxpOff()) do
      if not (field == "autoSellJunk" and store[field] == nil) then
        eq(store[field] or false, value, field)
      end
    end
  end
  eq(RXP.settings.profile.autoSellJunk, false, "live autoSellJunk")
  for _, key in ipairs({ "AutoSellJunk", "TalentGuides", "MaxNameplateDistance", "UpgradeTooltip" }) do
    eq(w.ns.adapters.RestedXP.Read(key), false, key .. " off everywhere")
  end
  eq(w.popups[1].which, "OVERLAPSETTINGSGUARD_OFF_RELOAD", "talent guides and nameplate distance need a reload")
  local named = false
  for _, line in ipairs(w.printed) do
    if line:find("Talents Guides", 1, true) and line:find("Also switched off in profiles: account default, character default", 1, true) then
      named = true
    end
  end
  ok(named, "chat names the other copies")
end)

test("a stored RestedXP profile with its own on value is switched off", function()
  local loaded = AllLoaded()
  loaded.TalentsForeverBook = true
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, rxp = {
    live = RxpOff(),
    profiles = { ["Alt - Realm"] = { enableTalentGuides = true, disableUpgradeTooltip = false } },
  } })
  w.Login()
  eq(RXPSettings.profiles["Alt - Realm"].enableTalentGuides, false, "Alt talent guides")
  eq(RXPSettings.profiles["Alt - Realm"].disableUpgradeTooltip, true, "Alt tooltip")
  eq(RXPSettings.profiles["Alt - Realm"].enableMaxNameplateDistance, false, "Alt nameplate distance (unset = default on)")
  eq(w.popups[1].which, "OVERLAPSETTINGSGUARD_OFF", "no reload: this character's live values were already off")
end)

test("a stored RestedXP profile without the value uses the account template", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), rxp = {
    live = RxpOff(),
    profiles = { ["Alt - Realm"] = {} },
    accountDefault = RxpOff(),
  } })
  eq(w.ns.adapters.RestedXP.Read("TalentGuides"), false, "Alt inherits the template's off")
  eq(w.ns.adapters.RestedXP.Read("UpgradeTooltip"), false, "inverted flag inherited too")
end)

test("a change in RestedXP's options is undone through AceConfig's NotifyChange", function()
  local loaded = AllLoaded()
  loaded.TalentsForeverBook = true
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, foreverui = DefaultUI(), rxp = { live = RxpOff() } })
  w.Login()
  eq(#w.popups, 0, "nothing to do at login")
  RXP.settings.profile.enableMaxNameplateDistance = true
  w.rxpRegistry:NotifyChange("Some Other Addon")
  eq(#w.timers, 0, "other add-ons' changes are ignored")
  w.rxpRegistry:NotifyChange("RestedXP Guides")
  w.RunTimers()
  eq(RXP.settings.profile.enableMaxNameplateDistance, false, "switched back")
end)

test("ValidatePolicy reports bad rules", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  local bad = {
    { id = "a", adapter = "Nope", key = "x", label = "l", reason = "r", when = { "X" } },
    { id = "a", adapter = "LeatrixPlus", key = "NotASetting", label = "l", reason = "r", when = {} },
  }
  eq(#w.ns.ValidatePolicy(bad, w.ns.adapters), 4, "problem count")
end)

test("rules are inactive without their add-ons", function()
  local w = Stubs.Fresh(ADDON_ROOT, {
    loaded = { Leatrix_Plus = true, ForeverUI = true },
    leatrix = { values = { AutomateQuests = "On" } },
    foreverui = DefaultUI(),
  })
  local results = w.ns.Check()
  eq(StatusOf(results, "rxp.autoquests"), "inactive", "autoquests without RXP")
  eq(StatusOf(results, "leatrix.minimap"), "off", "minimap")
  eq(w.leatrixValues.AutomateQuests, "On", "Leatrix value left alone")
end)

test("Leatrix boxes are told apart by page, not only by offsets", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = { MinimapModder = "On" } } })
  eq(w.ns.adapters.LeatrixPlus.Read("MinimapModder"), true, "MinimapModder")
  eq(w.ns.adapters.LeatrixPlus.Read("AutomateQuests"), false, "AutomateQuests at the same offsets on page 1")
end)

test("Leatrix revert clicks the box and asks for a reload only when the running value was on", function()
  local values = { SetChatFontSize = "On", AutomateGossip = "On" }
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = values, saved = { SetChatFontSize = "On", AutomateGossip = "Off" } } })
  local reverted, reload = w.ns.adapters.LeatrixPlus.Revert("SetChatFontSize")
  eq(reverted, true, "reverted")
  eq(reload, true, "reload for a running reload-only option")
  eq(values.SetChatFontSize, "Off", "Leatrix value")
  reverted, reload = w.ns.adapters.LeatrixPlus.Revert("AutomateGossip")
  eq(reverted, true, "gossip reverted")
  eq(reload, false, "no reload for an instant option")
  reverted = w.ns.adapters.LeatrixPlus.Revert("MinimapModder")
  eq(reverted, true, "already-off setting")
  eq(values.MinimapModder, "Off", "an off setting is not clicked on")
end)

test("Leatrix rule is blocked when the box at the spot is a different option", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = {}, version = "1.61.0" } })
  w.leatrixBoxes.MinimapModder.f = { GetText = function() return "Label" end }
  local results = w.ns.Check()
  local status, detail = StatusOf(results, "leatrix.minimap")
  eq(status, "blocked", "status")
  ok(detail:find("different option") and detail:find("1.61.0"), "detail names the cause and version: " .. detail)
end)

test("Leatrix rule is blocked without the options panel", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = {} } })
  _G.LeaPlusGlobalPanel = nil
  eq(StatusOf(w.ns.Check(), "leatrix.editbox"), "blocked", "status")
end)

test("ForeverUI adapter reads and reverts each setting", function()
  local ui = DefaultUI()
  ui.modules.QuestForever.enabled = true
  ui.modules.Arrow.enabled = nil
  ui.quests.guideOnAccept = nil
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = ui })
  local a = w.ns.adapters.ForeverUI
  eq(a.Read("QuestForeverModule"), true, "QuestForever on")
  eq(a.Read("ArrowModule"), true, "missing Arrow flag counts as on")
  eq(a.Read("QuestGuideOnAccept"), true, "missing guideOnAccept counts as on")
  for _, key in ipairs({ "QuestForeverModule", "ArrowModule", "QuestGuideOnAccept" }) do
    eq(a.Revert(key), true, key .. " reverted")
    eq(a.Read(key), false, key .. " now off")
  end
  eq(w.ui.db.modules.Quests.guideOnAcceptPad, false, "controller variant off")
end)

test("ForeverUI is read from the current profile after a switch", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = DefaultUI() })
  eq(w.ns.adapters.ForeverUI.Read("ArrowModule"), false, "before")
  w.ui.db = { modules = { Arrow = { enabled = true }, Quests = {} } }
  eq(w.ns.adapters.ForeverUI.Read("ArrowModule"), true, "after the profile table was replaced")
end)

test("ForeverUI settings are switched off in every stored profile, not only the active one", function()
  local ui = DefaultUI()
  ui.otherProfiles = {
    Leveling = { modules = { QuestForever = { enabled = true }, Quests = { guideOnAccept = true } } },
    Fresh = {},
  }
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = ui })
  w.Login()
  local leveling, fresh = ForeverUIDB.profiles.Leveling, ForeverUIDB.profiles.Fresh
  eq(leveling.modules.QuestForever.enabled, false, "Leveling QuestForever")
  eq(leveling.modules.Quests.guideOnAccept, false, "Leveling guide on accept")
  eq(fresh.modules.Arrow.enabled, false, "a profile with no saved modules counts as on and is switched off")
  eq(w.ui.IsModuleEnabled("QuestForever"), false, "active profile left off")
  local mentioned = false
  for _, line in ipairs(w.printed) do
    if line:find("Also switched off in profiles: Fresh, Leveling", 1, true) then mentioned = true end
  end
  ok(mentioned, "chat names the other profiles")
end)

test("a stored profile switched on later is caught by the ticker", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = (function()
    local ui = DefaultUI()
    ui.otherProfiles = { Alt = { modules = { Arrow = { enabled = false }, QuestForever = { enabled = false }, Quests = { guideOnAccept = false } } } }
    return ui
  end)() })
  w.Login()
  ForeverUIDB.profiles.Alt.modules.Arrow.enabled = true
  w.Tick()
  eq(ForeverUIDB.profiles.Alt.modules.Arrow.enabled, false, "Alt arrow")
end)

test("login switches off violations and shows one popup with a reload button", function()
  local values = { MinimapModder = "On", AutomateQuests = "On" }
  local ui = DefaultUI()
  ui.modules.QuestForever.enabled = true
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = values, saved = { MinimapModder = "On" } }, foreverui = ui })
  w.Login()
  eq(values.MinimapModder, "Off", "minimap")
  eq(values.AutomateQuests, "On", "Leatrix keeps auto quests")
  eq(w.ui.IsModuleEnabled("QuestForever"), false, "QuestForever")
  eq(#w.popups, 1, "popups")
  eq(w.popups[1].which, "OVERLAPSETTINGSGUARD_OFF_RELOAD", "popup kind")
  ok(w.popups[1].text:find("Enhance minimap"), "popup names the setting")
end)

test("ticking a locked Leatrix box is undone on the next frame", function()
  local values = {}
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = values }, foreverui = DefaultUI() })
  w.Login()
  eq(#w.popups, 0, "nothing to do at login")
  ok(w.leatrixBoxes.SetChatFontSize.tiptext:find("Locked off"), "tooltip note")
  w.leatrixBoxes.SetChatFontSize:Click()
  eq(values.SetChatFontSize, "On", "Leatrix took the click")
  w.RunTimers()
  eq(values.SetChatFontSize, "Off", "switched back")
  eq(#w.popups, 1, "popup")
  eq(w.popups[1].which, "OVERLAPSETTINGSGUARD_OFF", "no reload: the running value never changed")
end)

test("a ForeverUI change through its options is undone through the RefreshOptions hook", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = DefaultUI() })
  w.Login()
  w.ui.db.modules.Quests.guideOnAccept = true
  w.ui.RefreshOptions()
  w.RunTimers()
  eq(w.ui.db.modules.Quests.guideOnAccept, false, "guideOnAccept")
end)

test("a change that reaches no hook is caught by the ticker", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = DefaultUI() })
  w.Login()
  w.ui.db.modules.Arrow.enabled = true
  w.Tick()
  eq(w.ui.db.modules.Arrow.enabled, false, "Arrow")
end)

test("in combat the revert waits for combat to end", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = DefaultUI() })
  w.Login()
  w.combat = true
  w.ui.modules.QuestForever.Toggle(true)
  w.RunTimers()
  eq(w.ui.IsModuleEnabled("QuestForever"), true, "left on during combat")
  w.combat = false
  w.Fire("PLAYER_REGEN_ENABLED")
  eq(w.ui.IsModuleEnabled("QuestForever"), false, "switched off after combat")
end)

test("the popup for one rule is shown at most once every 10 seconds", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), foreverui = DefaultUI() })
  w.Login()
  w.ui.db.modules.Arrow.enabled = true
  w.Tick()
  w.ui.db.modules.Arrow.enabled = true
  w.now = w.now + 3
  w.Tick()
  eq(w.ui.db.modules.Arrow.enabled, false, "still switched off")
  eq(#w.popups, 1, "second popup suppressed")
  w.ui.db.modules.Arrow.enabled = true
  w.now = w.now + 10
  w.Tick()
  eq(#w.popups, 2, "popup again after the gap")
end)

test("/osg lists every rule", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = { Leatrix_Plus = true, ForeverUI = true }, leatrix = { values = {} }, foreverui = DefaultUI() })
  w.Login()
  w.printed = {}
  _G.SlashCmdList.OVERLAPSETTINGSGUARD("")
  eq(#w.printed, 17, "header plus 16 rules")
end)

test("Leatrix owns quest automation while RestedXP automation stays off across profiles", function()
  local fields = { "enableQuestAutomation", "enableQuestRewardAutomation", "enableQuestChoiceAutomation", "enableGossipAutomation" }
  local on = {}
  for _, field in ipairs(fields) do on[field] = true end
  local values = { AutomateQuests = "On", AutomateGossip = "On" }
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = AllLoaded(), leatrix = { values = values }, foreverui = DefaultUI(), rxp = {
    live = on, profiles = { Alt = { enableQuestAutomation = true, enableQuestRewardAutomation = true, enableQuestChoiceAutomation = true, enableGossipAutomation = true } },
    accountDefault = { enableQuestAutomation = true, enableQuestRewardAutomation = true, enableQuestChoiceAutomation = true, enableGossipAutomation = true },
    characterDefault = { enableQuestAutomation = true, enableQuestRewardAutomation = true, enableQuestChoiceAutomation = true, enableGossipAutomation = true },
  } })
  w.Login()
  for _, store in ipairs({ RXP.settings.profile, RXPSettings.profiles.Alt, RXPData.defaultProfile.profile, RXPCData.localDB.profile }) do
    for _, field in ipairs(fields) do eq(store[field], false, field .. " off in every copy") end
  end
  eq(values.AutomateQuests, "On", "Leatrix quest automation retained")
  eq(values.AutomateGossip, "On", "Leatrix gossip retained")
  for _, field in ipairs(fields) do RXP.settings.profile[field] = true end
  w.rxpRegistry:NotifyChange("RestedXP Guides")
  w.RunTimers()
  for _, field in ipairs(fields) do eq(RXP.settings.profile[field], false, field .. " cannot be enabled again") end
end)

for _, t in ipairs(tests) do
  local passed, err = pcall(t.fn)
  if passed then
    io.write("PASS  ", t.name, "\n")
  else
    io.write("FAIL  ", t.name, "\n      ", tostring(err), "\n")
    table.insert(failures, t.name)
  end
end
io.write(("\n%d tests, %d failed\n"):format(#tests, #failures))
return #failures
