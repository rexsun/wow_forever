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

local function ChatContains(w, text)
  for _, line in ipairs(w.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function StatusOf(results, id)
  for _, result in ipairs(results) do
    if result.rule.id == id then return result.status, result.detail end
  end
end

local function CurrentLoaded()
  return { YUI = true, GearInsight_Forever = true,
    EllesmereUIUnitFrames = true, EllesmereUIRaidFrames = true, EllesmereUINameplates = true }
end

test("loot effect CVar applies after world-entry handlers finish", function()
  local name = "outlineModeShowLootEffectWhenDisabled"
  local w = Stubs.Fresh(ADDON_ROOT, { cvars = { [name] = "0" } })
  w.Fire("PLAYER_LOGIN")
  eq(GetCVar(name), "0", "login initialization does not apply it early")
  for _, frame in ipairs(w.frames) do
    if frame.events.PLAYER_ENTERING_WORLD then frame:Fire("OnEvent", "PLAYER_ENTERING_WORLD") end
  end
  SetCVar(name, "0")
  w.RunTimers()
  eq(GetCVar(name), "1", "startup overrides initialization values")
  eq(#w.popups, 0, "no startup popup")
end)

test("startup CVars apply individually in order once per session and again after reload", function()
  local expected = {
    { "outlineModeShowLootEffectWhenDisabled", "1" },
    { "cameraDistanceMaxZoomFactor", "4" },
    { "nameplateMaxDistance", "41" },
    { "targetNearestDistanceRadius", "50" },
    { "ffxGlow", "0" },
    { "volumeFog", "0" },
    { "ResampleAlwaysSharpen", "1" },
    { "Contrast", "85" },
    { "Brightness", "55" },
    { "Gamma", "1.5" },
  }
  local function CheckWrites(w)
    eq(#w.cvarWrites, #expected)
    for i, setting in ipairs(expected) do
      eq(w.cvarWrites[i].name, setting[1], "command order")
      eq(w.cvarWrites[i].value, setting[2], setting[1])
      eq(GetCVar(setting[1]), setting[2], "applied value")
    end
  end
  local w = Stubs.Fresh(ADDON_ROOT, {})
  w.Fire("PLAYER_LOGIN")
  eq(#w.cvarWrites, 0, "login does not apply commands early")
  w.Login()
  CheckWrites(w)
  w.Fire("PLAYER_ENTERING_WORLD")
  w.Tick()
  eq(#w.cvarWrites, #expected, "zone transitions and guard ticks do not repeat startup")
  local reloaded = Stubs.Fresh(ADDON_ROOT, {})
  reloaded.Login()
  CheckWrites(reloaded)
end)

test("the shipped policy has no errors", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  local problems = w.ns.ValidatePolicy(w.ns.policy, w.ns.adapters)
  eq(#problems, 0, "policy problems: " .. table.concat(problems, "; "))
  eq(#w.ns.policy, 23, "rule count")
end)

test("ValidatePolicy reports bad rules", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  local bad = {
    { id = "a", adapter = "Nope", key = "x", label = "l", reason = "r", when = { "X" } },
    { id = "a", adapter = "YUI", key = "NotASetting", label = "l", reason = "r", when = {} },
  }
  eq(#w.ns.ValidatePolicy(bad, w.ns.adapters), 4, "problem count")
end)

test("every policy dependency belongs to the installed pack", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  local used = {}
  for _, rule in ipairs(w.ns.policy) do
    for _, addon in ipairs(rule.when) do
      ok(INSTALLED_ADDONS[addon], rule.id .. " requires an absent addon: " .. addon)
    end
    used[rule.adapter] = true
  end
  for name in pairs(w.ns.adapters) do
    ok(used[name], "unused adapter: " .. name)
  end
end)

test("/osg lists every current rule", function()
  local w = Stubs.Fresh(ADDON_ROOT, {})
  w.Login()
  w.printed = {}
  SlashCmdList.OVERLAPSETTINGSGUARD("")
  eq(#w.printed, #w.ns.policy + 1, "header plus every rule")
end)

local function HudConfig()
  return { resources = { byGroup = { ["group:system:resources"] = {
    selectionDefault = "catalog",
    bySpec = { ROGUE = { ["11572"] = { comboPoints = true, swingMainHand = true } } },
    formOverrides = { DRUID = { ["11347"] = { cat = { enabled = { energy = true, comboPoints = true } } } } },
  } } } }
end

local function BuildYUI(w)
  local config = HudConfig()
  local live = { Components = { UtilityTools_Config = { nameplateOutline = true, syncFriendlyNameplates = true } },
    YHUD = { profile = config } }
  local saved = HudConfig()
  local set = HudConfig()
  YUI_DB = { profiles = { Default = live, Alt = { Components = {}, YHUD = { profile = saved },
    SettingsConfigSetsV2 = { providers = { yhud = { items = { custom = { data = { profile = set } } } } } } } } }
  YUI = { DB = { GetProfile = function() return live end, GetAceDB = function() return { profile = live } end },
    YHUD = { GetConfigProfile = function() return config end,
      OnLifecycleConfigChanged = function() w.hudRefreshes = (w.hudRefreshes or 0) + 1 end } }
  for _, name in ipairs({ "UtilityToolsNameplateOutline", "UtilityToolsNameplates" }) do
    YUI[name] = { enabled = true, Disable = function(self) self.enabled = false end }
  end
  return live, saved, set
end

test("current YUI and EllesmereUI policy has enforceable rules", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local ids = {}
  for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
  for _, id in ipairs({ "yui.nameplateoutline", "yui.friendlynameplates", "yui.resources", "yui.playerhealth", "yui.playercast", "eui.nameplatepower",
    "gi.friendlynameplates", "gi.combathud", "gi.resources", "gi.levelingstats", "gi.actionbaredits" }) do
    ok(ids[id], id)
  end
end)

test("YUI player bars stay off across profiles, numeric specs, forms and HUD sets", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live, saved, set = BuildYUI(w)
  for _, profile in ipairs({ live.YHUD.profile, saved, set }) do
    local r = profile.resources.byGroup["group:system:resources"]
    r.bySpec.ROGUE = { [11572] = { health = true, cast = true, swingMainHand = true } }
    r.formOverrides.DRUID["11347"].cat.enabled.health = true
    r.formOverrides.DRUID["11347"].cat.enabled.cast = true
    profile.groups = { items = {
      cast = { layout = "resource", contentPolicy = "cast-only", enabled = true },
      other = { layout = "resource", enabled = true },
    } }
    profile.playerCast = { hideNative = true }
  end
  local a = w.ns.adapters.YUI
  for _, key in ipairs({ "PlayerHealth", "PlayerCast" }) do
    ok(a.Knows(key), key)
    eq(a.Read(key), true, key)
    eq(a.Revert(key), true, key)
    eq(a.Read(key), false, key)
  end
  for _, profile in ipairs({ live.YHUD.profile, saved, set }) do
    local r = profile.resources.byGroup["group:system:resources"]
    eq(r.bySpec.ROGUE[11572].health, false)
    eq(r.bySpec.ROGUE[11572].cast, false)
    eq(r.bySpec.ROGUE[11572].swingMainHand, true)
    eq(r.bySpec.WARRIOR["11650"].health, false)
    eq(r.formOverrides.DRUID["11347"].cat.enabled.health, false)
    eq(r.formOverrides.DRUID["11347"].cat.enabled.cast, false)
    eq(profile.groups.items.cast.enabled, false)
    eq(profile.groups.items.other.enabled, true)
    eq(profile.playerCast.hideNative, false)
  end
end)

test("YUI opt-in player bars do not trigger enforcement when unset", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  BuildYUI(w)
  eq(w.ns.adapters.YUI.Read("PlayerHealth"), false)
  eq(w.ns.adapters.YUI.Read("PlayerCast"), false)
end)

test("YUI cast-only groups alone are enforced and failed refreshes retry independently", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local group = { layout = "resource", contentPolicy = "cast-only", enabled = true }
  live.YHUD.profile.groups = { items = { custom = group } }
  local a = w.ns.adapters.YUI
  eq(a.Read("PlayerCast"), true)
  YUI.YHUD.OnLifecycleConfigChanged = function() return nil, "specialization-transition" end
  eq(a.Revert("PlayerCast"), false)
  eq(group.enabled, false)
  eq(a.Read("PlayerCast"), true)
  eq(a.Read("PlayerHealth"), false)
  eq(a.Revert("PlayerHealth"), false)
  eq(a.Read("PlayerCast"), true)
  YUI.YHUD.OnLifecycleConfigChanged = function() return true end
  eq(a.Revert("PlayerCast"), true)
  eq(a.Read("PlayerCast"), false)
end)

test("YUI player bar policies defer combat, catch resets and require EUI unit frames", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local selected = live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"]
  selected.health, selected.cast = true, true
  w.combat = true
  w.Login()
  eq(selected.health, true)
  eq(selected.cast, true)
  w.combat = false
  w.Fire("PLAYER_REGEN_ENABLED")
  eq(selected.health, false)
  eq(selected.cast, false)
  selected.health, selected.cast = true, true
  w.Tick()
  eq(selected.health, false)
  eq(selected.cast, false)
  w = Stubs.Fresh(ADDON_ROOT, { loaded = { YUI = true, EllesmereUIRaidFrames = true } })
  live = BuildYUI(w)
  selected = live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"]
  selected.health, selected.cast = true, true
  w.Login()
  eq(selected.health, true)
  eq(selected.cast, true)
end)

test("missing YUI player-bar refresh API leaves selections and groups unchanged", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local selected = live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"]
  selected.health, selected.cast = true, true
  live.YHUD.profile.groups = { items = { cast = { layout = "resource", contentPolicy = "cast-only", enabled = true } } }
  YUI.YHUD.OnLifecycleConfigChanged = nil
  for _, key in ipairs({ "PlayerHealth", "PlayerCast" }) do
    eq(w.ns.adapters.YUI.Read(key), nil)
    eq(w.ns.adapters.YUI.Revert(key), false)
  end
  eq(selected.health, true)
  eq(selected.cast, true)
  eq(live.YHUD.profile.groups.items.cast.enabled, true)
end)

test("installed YUI catalog keeps guarded selections off after normalization", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  YUI.IsForever, YUI.API = true, {}
  local getConfigProfile = YUI.YHUD.GetConfigProfile
  for _, file in ipairs({ "Client/Forever.lua", "Catalog/Forever/DefaultProfile.lua", "Product/Defaults.lua", "Catalog/Forever/Resources.lua",
    "Catalog/Resources/Registry.lua", "Catalog/Forever/Classes.lua" }) do
    assert(loadfile(ADDON_ROOT .. "../YUI/Products/YHUD/" .. file))("YUI")
  end
  local hud, a = YUI.YHUD, w.ns.adapters.YUI
  hud.GetConfigProfile = getConfigProfile
  local profile = live.YHUD.profile
  local r = profile.resources.byGroup["group:system:resources"]
  r.bySpec.ROGUE["11572"].health, r.bySpec.ROGUE["11572"].cast = true, true
  r.formOverrides.DRUID["11347"].cat.enabled.health = true
  r.formOverrides.DRUID["11347"].cat.enabled.cast = true
  eq(a.Revert("PlayerHealth"), true)
  eq(a.Revert("PlayerCast"), true)
  local catalog = hud.ResourceCatalog
  r.bySpec = catalog:NormalizeSelections(r.bySpec)
  r.formOverrides = catalog:NormalizeFormOverrides(r.formOverrides)
  local count = 0
  for class, selections in pairs(r.bySpec) do
    for spec in pairs(selections) do
      count = count + 1
      for _, resource in ipairs({ "health", "cast" }) do
        eq(catalog:IsPresetEnabled(hud:GetResourceProfile(profile), class, spec, resource), false)
      end
    end
  end
  eq(count, 27)
  eq(catalog:IsPresetEnabled(hud:GetResourceProfile(profile), "ROGUE", 11572, "health"), false)
  eq(catalog:IsPresetEnabled(hud:GetResourceProfile(profile), "ROGUE", 11572, "cast"), false)
  eq(catalog:IsPresetEnabled(hud:GetResourceProfile(profile), "ROGUE", 11572, "swingMainHand"), true)
  local formsChecked = 0
  for _, form in ipairs({ "caster", "moonkin", "cat", "bear", "travel" }) do
    for _, preset in ipairs(catalog:GetFormPresets(hud:GetResourceProfile(profile), "DRUID", 11347, form)) do
      if preset.id == "health" or preset.id == "cast" then
        eq(preset.enabled, false)
        formsChecked = formsChecked + 1
      end
    end
  end
  eq(formsChecked, 10)
end)

test("YUI nameplate settings and active runtimes are disabled across profiles", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local a = w.ns.adapters.YUI
  ok(a, "YUI adapter")
  for _, key in ipairs({ "NameplateOutline", "FriendlyNameplates" }) do
    eq(a.Read(key), true)
    eq(a.Revert(key), true)
    eq(a.Read(key), false)
  end
  eq(live.Components.UtilityTools_Config.nameplateOutline, false)
  eq(YUI_DB.profiles.Alt.Components.UtilityTools_Config.nameplateOutline, false)
  eq(YUI.UtilityToolsNameplates.enabled, false)
  eq(YUI.UtilityToolsNameplateOutline.enabled, false)
end)

test("YUI resource enforcement covers defaults, druid forms and saved HUD sets without removing swings", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live, saved, set = BuildYUI(w)
  local a = w.ns.adapters.YUI
  ok(a, "YUI adapter")
  eq(a.Read("Resources"), true)
  eq(a.Revert("Resources"), true)
  eq(a.Read("Resources"), false)
  for _, config in ipairs({ live.YHUD.profile, saved, set }) do
    local r = config.resources.byGroup["group:system:resources"]
    eq(r.bySpec.ROGUE["11572"].comboPoints, false)
    eq(r.bySpec.WARRIOR["11650"].rage, false)
    eq(r.bySpec.MAGE["11582"].mana, false)
    eq(r.formOverrides.DRUID["11347"].cat.enabled.energy, false)
    eq(r.bySpec.ROGUE["11572"].swingMainHand, true)
  end
  eq(w.hudRefreshes, 1)
end)

test("missing YUI runtime APIs block enforcement without mutating saved settings", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  YUI.YHUD.OnLifecycleConfigChanged = nil
  local a = w.ns.adapters.YUI
  ok(a, "YUI adapter")
  eq(a.Read("Resources"), nil)
  eq(a.Revert("Resources"), false)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].comboPoints, true)
end)

test("EllesmereUI nameplate resources are disabled in profiles and spec presets", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local active = { showClassPower = true, fontSize = 13 }
  EllesmereUIDB = { activeProfile = "Default", profiles = {
    Default = { addons = { EllesmereUINameplates = active } },
    Alt = { addons = { EllesmereUINameplates = { showClassPower = true } },
      specPresets = { rogue = { showClassPower = true } } },
  } }
  _ENP_RefreshAllSettings = function() w.euiRefreshes = (w.euiRefreshes or 0) + 1 end
  local a = w.ns.adapters.EllesmereUI
  ok(a, "EllesmereUI adapter")
  eq(a.Read("NameplatePower"), true)
  eq(a.Revert("NameplatePower"), true)
  eq(a.Read("NameplatePower"), false)
  eq(active.fontSize, 13)
  eq(EllesmereUIDB.profiles.Alt.specPresets.rogue.showClassPower, false)
  eq(w.euiRefreshes, 1)
end)

test("EllesmereUI reports unavailable refresh API instead of changing only storage", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  EllesmereUIDB = { profiles = { Default = { addons = { EllesmereUINameplates = { showClassPower = true } } } } }
  local a = w.ns.adapters.EllesmereUI
  ok(a, "EllesmereUI adapter")
  eq(a.Read("NameplatePower"), nil)
  eq(a.Revert("NameplatePower"), false)
  eq(EllesmereUIDB.profiles.Default.addons.EllesmereUINameplates.showClassPower, true)
end)

test("EllesmereUI spec override keys cannot restore nameplate class power", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local key = "EllesmereUINameplates\031showClassPower"
  local unrelated = "EllesmereUIUnitFrames\031showClassPowerBar"
  local values = { [key] = true, [unrelated] = true }
  EllesmereUIDB = { profiles = { Default = {
    addons = { EllesmereUINameplates = { showClassPower = false } },
    specOverrides = { { values = { default = values, [259] = { [key] = true } } } },
  } } }
  _ENP_RefreshAllSettings = function() end
  local a = w.ns.adapters.EllesmereUI
  eq(a.Read(), true)
  eq(a.Revert(), true)
  eq(values[key], false)
  eq(values[unrelated], true)
  eq(EllesmereUIDB.profiles.Default.specOverrides[1].values[259][key], false)
  eq(a.Read(), false)
end)

test("current frame overlaps defer in combat and catch changes bypassing hooks", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  w.combat = true
  w.Login()
  eq(live.Components.UtilityTools_Config.nameplateOutline, true)
  w.combat = false
  w.Fire("PLAYER_REGEN_ENABLED")
  eq(live.Components.UtilityTools_Config.nameplateOutline, false)
  live.Components.UtilityTools_Config.nameplateOutline = true
  live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].comboPoints = true
  w.Tick()
  eq(live.Components.UtilityTools_Config.nameplateOutline, false)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].comboPoints, false)
end)

test("failed live HUD refresh stays pending and is retried", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  BuildYUI(w)
  local a = w.ns.adapters.YUI
  YUI.YHUD.OnLifecycleConfigChanged = function() return nil, "specialization-transition" end
  eq(a.Revert("Resources"), false)
  eq(a.Read("Resources"), true, "pending refresh is still a violation")
  YUI.YHUD.OnLifecycleConfigChanged = function() return true end
  eq(a.Revert("Resources"), true)
  eq(a.Read("Resources"), false)
end)

test("numeric YUI spec keys retain their swing timers and form ordering", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local r = live.YHUD.profile.resources.byGroup["group:system:resources"]
  r.bySpec.ROGUE = { [11572] = { comboPoints = true, swingMainHand = true } }
  r.formOverrides.DRUID = { [11347] = { cat = { order = { "energy", "comboPoints" }, enabled = { energy = true } } } }
  eq(w.ns.adapters.YUI.Revert("Resources"), true)
  eq(r.bySpec.ROGUE[11572].comboPoints, false)
  eq(r.bySpec.ROGUE[11572].swingMainHand, true)
  eq(r.formOverrides.DRUID[11347].cat.order[1], "energy")
end)

test("EllesmereUI refresh hooks undo a re-enabled display and retry refresh failures", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = { EllesmereUINameplates = true, EllesmereUIUnitFrames = true } })
  local settings = { showClassPower = false }
  EllesmereUIDB = { profiles = { Default = { addons = { EllesmereUINameplates = settings } } } }
  _ENP_RefreshAllSettings = function() end
  w.Login()
  settings.showClassPower = true
  _ENP_RefreshAllSettings()
  w.RunTimers()
  eq(settings.showClassPower, false)
  local a = w.ns.adapters.EllesmereUI
  settings.showClassPower = true
  _ENP_RefreshAllSettings = function() error("refresh unavailable") end
  eq(a.Revert("NameplatePower"), false)
  eq(a.Read("NameplatePower"), true)
  _ENP_RefreshAllSettings = function() end
  eq(a.Revert("NameplatePower"), true)
  eq(a.Read("NameplatePower"), false)
end)

test("a YUI profile reset is enforced without cached old profile references", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  BuildYUI(w)
  w.Login()
  local fresh = { Components = {}, YHUD = { profile = HudConfig() } }
  YUI_DB.profiles.Fresh = fresh
  YUI.DB.GetProfile = function() return fresh end
  YUI.YHUD.GetConfigProfile = function() return fresh.YHUD.profile end
  w.Tick()
  eq(fresh.Components.UtilityTools_Config.nameplateOutline, false)
  eq(fresh.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].comboPoints, false)
end)

test("new rules stay inactive when their owner addon is absent", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = { YUI = true } })
  local live = BuildYUI(w)
  w.Login()
  eq(live.Components.UtilityTools_Config.nameplateOutline, true)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].comboPoints, true)
end)

assert(loadfile(TESTS_ROOT .. "gearinsight.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
assert(loadfile(TESTS_ROOT .. "skinner.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf)

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
