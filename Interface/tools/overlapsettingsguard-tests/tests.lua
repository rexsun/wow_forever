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
    { "graphicsBloomUserMult", "0" },
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
  eq(#w.ns.policy, 69, "rule count")
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
    bySpec = { ROGUE = { ["11572"] = { energy = true, comboPoints = true, swingMainHand = true } } },
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
  eq(ids["yui.resources"], nil, "YUI's class resource bars are not guarded")
  for _, rule in ipairs(w.ns.policy) do
    ok(not (rule.adapter == "YUI" and rule.key == "Resources"), rule.id .. " must not target YUI class resources")
  end
  ok(not w.ns.adapters.YUI.Knows("Resources"), "the YUI adapter has no class resource setting")
  for _, rule in ipairs(w.ns.policy) do
    ok(rule.key ~= "PlayerPower", rule.id .. " must not hide EllesmereUI's player power bar")
  end
  ok(not w.ns.adapters.EllesmereUI.Knows("PlayerPower"), "EllesmereUI's player power bar is not guarded")
  for _, id in ipairs({ "yui.nameplateoutline", "yui.friendlynameplates", "eui.classpower",
    "yui.playerhealth", "yui.playercast", "eui.nameplatepower",
    "gi.friendlynameplates", "gi.combathud", "gi.resources", "gi.levelingstats", "gi.actionbaredits",
    "yui.chatkeywordfilter", "gi.guildchatlevel" }) do
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

test("YUI resource manager contexts cannot bypass the player bar policies", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live, saved = BuildYUI(w)
  local function Contexts(profile)
    local config = profile.resources.byGroup["group:system:resources"]
    config.bySpec, config.formOverrides, config.selectionDefault = {}, {}, "none"
    config.itemsByContext = {
      ["ROGUE:11572:"] = { { id = "energy", enabled = true }, { id = "swingMainHand", enabled = true } },
      ["DRUID:11347:cat"] = { { id = "comboPoints", enabled = true }, { id = "health", enabled = true } },
      ["MAGE:11582:"] = { { id = "cast", enabled = true }, { id = "custom-resource:1", enabled = true } },
    }
    return config.itemsByContext
  end
  local activeItems, savedItems = Contexts(live.YHUD.profile), Contexts(saved)
  local a = w.ns.adapters.YUI
  for _, key in ipairs({ "PlayerHealth", "PlayerCast" }) do
    eq(a.Read(key), true, key)
    eq(a.Revert(key), true, key)
    eq(a.Read(key), false, key)
  end
  for _, items in ipairs({ activeItems, savedItems }) do
    eq(items["ROGUE:11572:"][1].enabled, true, "YUI owns energy")
    eq(items["ROGUE:11572:"][2].enabled, true, "swing timers stay available")
    eq(items["DRUID:11347:cat"][1].enabled, true, "YUI owns combo points")
    eq(items["DRUID:11347:cat"][2].enabled, false)
    eq(items["MAGE:11582:"][1].enabled, false)
    eq(items["MAGE:11582:"][2].enabled, true, "custom resources stay available")
  end
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

-- Mirrors YChat Config.lua in v352: the active filter lives at profile.YChat.messageFilter.
local function BuildYChat(w, live)
  live.YChat = { enabled = true, messageFilter = { enabled = true, prefixes = { "[GearInsight 无限版]" } } }
  YUI_DB.profiles.Alt.YChat = { enabled = true }
  YUI.YChat = {
    GetMessageFilter = function() return live.YChat.messageFilter end,
    SetMessageFilterEnabled = function(self, value)
      if type(value) ~= "boolean" then return false, "invalid-message-filter-value" end
      if live.YChat.messageFilter.enabled == value then return true, false end
      live.YChat.messageFilter.enabled = value
      w.chatRefreshes = (w.chatRefreshes or 0) + 1
      return true, true
    end,
  }
  return live.YChat
end

test("YChat keyword filter is switched off in the active and stored profiles", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local chat = BuildYChat(w, live)
  local a = w.ns.adapters.YUI
  eq(a.Read("ChatKeywordFilter"), true)
  w.Login()
  eq(chat.messageFilter.enabled, false)
  eq(#chat.messageFilter.prefixes, 1, "keyword list is kept")
  eq(YUI_DB.profiles.Alt.YChat.messageFilter.enabled, false, "missing filter in a stored profile defaults on")
  eq(w.chatRefreshes, 1, "active change goes through YChat's setter")
  eq(StatusOf(w.ns.Check(), "yui.chatkeywordfilter"), "off")
  YUI.YChat:SetMessageFilterEnabled(true)
  w.RunTimers()
  eq(chat.messageFilter.enabled, false, "settings toggle is reverted on the next frame")
end)

test("YChat keyword filter is left alone without GearInsight or the YChat API", function()
  local loaded = CurrentLoaded()
  loaded.GearInsight_Forever = nil
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
  local chat = BuildYChat(w, BuildYUI(w))
  w.Login()
  eq(chat.messageFilter.enabled, true)
  w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  chat = BuildYChat(w, live)
  YUI.YChat.SetMessageFilterEnabled = nil
  eq(StatusOf(w.ns.Check(), "yui.chatkeywordfilter"), "blocked")
  eq(chat.messageFilter.enabled, true)
  eq(YUI_DB.profiles.Alt.YChat.messageFilter, nil, "stored profiles untouched when blocked")
end)

test("YUI class resource selections and defaults are never written by the guard", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live, saved, set = BuildYUI(w)
  for _, config in ipairs({ live.YHUD.profile, saved, set }) do
    local r = config.resources.byGroup["group:system:resources"]
    r.bySpec.WARRIOR = { ["11650"] = { rage = true } }
    r.bySpec.SHAMAN = { ["11363"] = { mana = true, foreverMaelstromWeapon = true } }
    r.formOverrides.DRUID["11347"].bear = { enabled = { rage = true } }
  end
  w.Login()
  w.Tick()
  for _, config in ipairs({ live.YHUD.profile, saved, set }) do
    local r = config.resources.byGroup["group:system:resources"]
    eq(r.selectionDefault, "catalog", "unset class resources keep YUI's catalog defaults")
    eq(r.bySpec.ROGUE["11572"].energy, true)
    eq(r.bySpec.ROGUE["11572"].comboPoints, true)
    eq(r.bySpec.WARRIOR["11650"].rage, true)
    eq(r.bySpec.SHAMAN["11363"].mana, true)
    eq(r.bySpec.SHAMAN["11363"].foreverMaelstromWeapon, true)
    eq(r.bySpec.MAGE, nil, "no selections are created for unset classes")
    eq(r.formOverrides.DRUID["11347"].cat.enabled.energy, true)
    eq(r.formOverrides.DRUID["11347"].cat.enabled.comboPoints, true)
    eq(r.formOverrides.DRUID["11347"].bear.enabled.rage, true)
    eq(r.bySpec.ROGUE["11572"].swingMainHand, true)
  end
end)

test("missing YUI runtime APIs block enforcement without mutating saved settings", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  YUI.YHUD.OnLifecycleConfigChanged = nil
  local a = w.ns.adapters.YUI
  ok(a, "YUI adapter")
  live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].cast = true
  eq(a.Read("PlayerCast"), nil)
  eq(a.Revert("PlayerCast"), false)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].cast, true)
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

test("EllesmereUI player combo points are held off under YUI, unset Forever defaults included", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local styleKey = "EllesmereUIUnitFrames\031player.classPowerStyle"
  local rogueKey = "EllesmereUIUnitFrames\031player.foreverRogueClassPowerStyle"
  local unrelated = "EllesmereUIUnitFrames\031player.classPowerSize"
  local bucket = { [styleKey] = "modern", [rogueKey] = "__SPECOV_NIL__", [unrelated] = 12 }
  local default = { frameWidth = 200 }
  local alt = { player = { classPowerStyle = "none", foreverRogueClassPowerStyle = "circles" } }
  EllesmereUIDB = { profiles = {
    Default = { addons = { EllesmereUIUnitFrames = { player = default } },
      specOverrides = { { values = { default = bucket } } } },
    Alt = { addons = { EllesmereUIUnitFrames = alt } },
    Bare = { addons = { EllesmereUIUnitFrames = {} } },
  } }
  _EUF_ReloadFrames = function() w.ufReloads = (w.ufReloads or 0) + 1 end
  local a = w.ns.adapters.EllesmereUI
  eq(a.Read("ClassPower"), true)
  eq(a.Revert("ClassPower"), true)
  eq(a.Read("ClassPower"), false)
  eq(default.classPowerStyle, "none")
  eq(default.showClassPowerBar, false)
  eq(default.foreverRogueClassPowerStyle, nil, "an unset rogue style already builds nothing")
  eq(default.frameWidth, 200)
  eq(alt.player.foreverRogueClassPowerStyle, "none")
  eq(EllesmereUIDB.profiles.Bare.addons.EllesmereUIUnitFrames.player.classPowerStyle, "none")
  eq(bucket[styleKey], "none")
  eq(bucket[rogueKey], "__SPECOV_NIL__")
  eq(bucket[unrelated], 12)
  eq(w.ufReloads, 1)
  eq(a.Read("NameplatePower"), nil, "nameplate refresh API is separate")
end)

test("EllesmereUI player combo points: reading never writes, a missing reload API blocks", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local uf = {}
  EllesmereUIDB = { profiles = { Default = { addons = { EllesmereUIUnitFrames = uf } } } }
  _EUF_ReloadFrames = function() end
  local a = w.ns.adapters.EllesmereUI
  eq(a.Read("ClassPower"), true)
  eq(uf.player, nil)
  _EUF_ReloadFrames = nil
  eq(a.Read("ClassPower"), nil)
  eq(a.Revert("ClassPower"), false)
  eq(uf.player, nil)
end)

test("EllesmereUI player combo points stay available without YUI", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = { EllesmereUIUnitFrames = true, EllesmereUINameplates = true } })
  local player = { classPowerStyle = "modern" }
  EllesmereUIDB = { profiles = { Default = { addons = { EllesmereUIUnitFrames = { player = player } } } } }
  _EUF_ReloadFrames = function() end
  eq(StatusOf(w.ns.Check(), "eui.classpower"), "inactive")
  eq(player.classPowerStyle, "modern")
end)

test("installed sources keep the combo-point hand-off between EllesmereUI and YUI", function()
  local function Read(path)
    local file = assert(io.open(ADDON_ROOT .. "../" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end
  local uf = Read("EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua")
  ok(uf:find('classPowerStyle = (EllesmereUI.IS_FOREVER == true) and "modern"', 1, true), "Forever default style")
  ok(Read("EllesmereUIUnitFrames/EUI_UnitFrames_StockStyles.lua"):find('return "foreverRogueClassPowerStyle"', 1, true),
    "rogue style key")
  ok(Read("EllesmereUIUnitFrames/EUI_UnitFrames_OptionsSetup.lua"):find("_G._EUF_ReloadFrames = ns.ReloadFrames", 1, true),
    "reload API")
  local classes = Read("YUI/Products/YHUD/Catalog/Forever/Classes.lua")
  ok(classes:find('[11580] = { "energy", "comboPoints" }', 1, true), "YUI rogue combo points")
  ok(classes:find('cat = Form({ "energy", "comboPoints", "mana" }', 1, true), "YUI cat-form combo points")
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
  live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].health = true
  w.Tick()
  eq(live.Components.UtilityTools_Config.nameplateOutline, false)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].health, false)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].energy, true)
end)

test("failed live HUD refresh stays pending and is retried", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].health = true
  local a = w.ns.adapters.YUI
  YUI.YHUD.OnLifecycleConfigChanged = function() return nil, "specialization-transition" end
  eq(a.Revert("PlayerHealth"), false)
  eq(a.Read("PlayerHealth"), true, "pending refresh is still a violation")
  YUI.YHUD.OnLifecycleConfigChanged = function() return true end
  eq(a.Revert("PlayerHealth"), true)
  eq(a.Read("PlayerHealth"), false)
end)

test("numeric YUI spec keys retain their swing timers and form ordering", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
  local live = BuildYUI(w)
  local r = live.YHUD.profile.resources.byGroup["group:system:resources"]
  r.bySpec.ROGUE = { [11572] = { energy = true, comboPoints = true, health = true, swingMainHand = true } }
  r.formOverrides.DRUID = { [11347] = { cat = { order = { "energy", "comboPoints" }, enabled = { energy = true } } } }
  eq(w.ns.adapters.YUI.Revert("PlayerHealth"), true)
  eq(r.bySpec.ROGUE[11572].health, false)
  eq(r.bySpec.ROGUE[11572].energy, true)
  eq(r.bySpec.ROGUE[11572].comboPoints, true)
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
  fresh.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].health = true
  YUI_DB.profiles.Fresh = fresh
  YUI.DB.GetProfile = function() return fresh end
  YUI.YHUD.GetConfigProfile = function() return fresh.YHUD.profile end
  w.Tick()
  eq(fresh.Components.UtilityTools_Config.nameplateOutline, false)
  eq(fresh.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].health, false)
  eq(fresh.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].energy, true)
end)

test("new rules stay inactive when their owner addon is absent", function()
  local w = Stubs.Fresh(ADDON_ROOT, { loaded = { YUI = true } })
  local live = BuildYUI(w)
  w.Login()
  eq(live.Components.UtilityTools_Config.nameplateOutline, true)
  eq(live.YHUD.profile.resources.byGroup["group:system:resources"].bySpec.ROGUE["11572"].energy, true)
end)

assert(loadfile(TESTS_ROOT .. "gearinsight.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
assert(loadfile(TESTS_ROOT .. "skinner.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
assert(loadfile(TESTS_ROOT .. "forever_essentials.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
assert(loadfile(TESTS_ROOT .. "maputils.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "lueur.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "yui_auction.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "yui_lootroll.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "gearinsight_v1.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "gearinsight_v14.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
assert(loadfile(TESTS_ROOT .. "eui_tooltip.lua"))()(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)

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
