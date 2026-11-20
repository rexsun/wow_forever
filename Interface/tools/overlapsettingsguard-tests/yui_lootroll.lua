return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local KEY = "LootRoll"
  local RULE = "yui.lootroll"

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.LootRollMover = true
    return loaded
  end

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function BuildYUI(activeValue)
    local live = { Components = { [KEY] = activeValue, AuctionHelper = false } }
    local other = { Components = { [KEY] = true, Other = true, AuctionHelper = false } }
    local unset = { Components = { AuctionHelper = false } }
    local calls = {}
    local components = {
      features = {
        [KEY] = { product = "suite", default = true },
        AuctionHelper = { product = "suite", default = true },
      },
      initializedFeatureStates = { [KEY] = activeValue ~= false, AuctionHelper = false },
    }
    function components:GetStore() return live.Components end
    function components:SetFeatureEnabled(key, enable)
      live.Components[key] = enable == true
      self.initializedFeatureStates[key] = enable == true
      calls[#calls + 1] = key .. "=" .. tostring(enable == true)
      return true
    end
    YUI = { DB = { GetProfile = function() return live end }, Components = components }
    YUI_DB = { profiles = { Default = live, Other = other, Unset = unset } }
    return live, other, unset, calls
  end

  test("YUI loot roll rule needs YUI and LootRollMover and runs after login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local rule
    for _, candidate in ipairs(w.ns.policy) do
      if candidate.id == RULE then rule = candidate end
    end
    ok(rule, RULE)
    eq(rule.when[1], "YUI")
    eq(rule.when[2], "LootRollMover")
    eq(rule.early, nil, "the component starts with YUI after login")
  end)

  test("YUI loot roll HUD is off in every profile and Blizzard's roll frames are handed back at once", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live, other, unset, calls = BuildYUI(true)
    w.Login()
    eq(live.Components[KEY], false)
    eq(other.Components[KEY], false)
    eq(other.Components.Other, true, "other components kept")
    eq(unset.Components[KEY], false, "an unset value reads as YUI's default on")
    local disabled = false
    for _, call in ipairs(calls) do
      if call == KEY .. "=false" then disabled = true end
      ok(call ~= "AuctionHelper=true", "the auction panel is not switched on")
    end
    ok(disabled, "YUI's own switch runs the disable callback")
    ok(ChatContains(w, "Other"), "other profile named in chat")
    ok(not ChatContains(w, "/reload"), "no reload")
    eq(StatusOf(w.ns.Check(), RULE), "off")
    YUI.Components:SetFeatureEnabled(KEY, true)
    w.RunTimers()
    eq(live.Components[KEY], false, "switching it back on in YUI is caught")
  end)

  test("YUI loot roll HUD stays on without LootRollMover", function()
    local loaded = Loaded()
    loaded.LootRollMover = nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local live = BuildYUI(true)
    w.Login()
    eq(live.Components[KEY], true)
    eq(StatusOf(w.ns.Check(), RULE), "inactive")
  end)

  test("YUI loot roll HUD reports a missing API instead of writing", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live = BuildYUI(true)
    YUI.Components.features[KEY] = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), RULE), "blocked")
    eq(live.Components[KEY], true, "nothing written")
  end)

  test("YUI's loot roll component and the frames it hides exist in the installed source", function()
    local addons = ADDON_ROOT .. "../YUI/"
    local load = ReadFile(addons .. "Components/!load_Forever.xml")
    ok(load:find("LootRoll\\!load_Forever.xml", 1, true), "Forever loads the loot roll component")
    local roll = ReadFile(addons .. "Components/LootRoll/LootRoll.lua")
    ok(roll:find('local KEY, MODULE, LAYOUT = "LootRoll"', 1, true), "the component key is LootRoll")
    ok(roll:find("Components:RegisterFeature(KEY, Feature)", 1, true), "the HUD is a YUI component feature")
    ok(roll:find('local Feature = { id = KEY, name = L["name"], description = L["description"], default = true,', 1, true),
      "the HUD is on by default")
    ok(roll:find("callback = function(enabled) if enabled then YUI.Module:Enable(MODULE) else YUI.Module:Disable(MODULE) end end", 1, true),
      "switching the feature off disables the module")
    ok(roll:find("C.active, C.nativeTakeover = false, false; API.Release()", 1, true), "disabling hands the native frames back")
    local adapter = ReadFile(addons .. "Components/LootRoll/Adapter_Forever.lua")
    ok(adapter:find("GroupLootFrame", 1, true), "it takes over Blizzard's group loot roll frames")
    ok(adapter:find("function API.Release(keepClosed)", 1, true), "it can restore them")
    local mover = ReadFile(ADDON_ROOT .. "../LootRollMover/LootRollMover.lua")
    ok(mover:find("GroupLootFrame", 1, true), "LootRollMover positions the same frames")
  end)
end
