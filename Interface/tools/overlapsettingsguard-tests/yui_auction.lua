return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local KEY = "AuctionHelper"

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.Auctionator = true
    return loaded
  end

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function BuildYUI(activeValue)
    local live = { Components = { [KEY] = activeValue } }
    local other = { Components = { [KEY] = true, Other = true } }
    local unset = { Components = {} }
    local empty = {}
    local calls = {}
    local components = {
      features = { [KEY] = { product = "suite", default = true } },
      initializedFeatureStates = { [KEY] = activeValue ~= false },
    }
    function components:GetStore() return live.Components end
    function components:SetFeatureEnabled(key, enable)
      live.Components[key] = enable == true
      self.initializedFeatureStates[key] = enable == true
      calls[#calls + 1] = enable == true
      return true
    end
    YUI = { DB = { GetProfile = function() return live end }, Components = components }
    YUI_DB = { profiles = { Default = live, Other = other, Unset = unset, Empty = empty } }
    return live, other, unset, empty, calls
  end

  test("YUI auction panel rule needs YUI and Auctionator and runs after login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local rule
    for _, candidate in ipairs(w.ns.policy) do
      if candidate.id == "yui.auctionhelper" then rule = candidate end
    end
    ok(rule, "yui.auctionhelper")
    eq(rule.when[1], "YUI")
    eq(rule.when[2], "Auctionator")
    eq(rule.early, nil, "the panel is built only when the auction house opens")
  end)

  test("YUI auction panel is off in every profile and the panel is hidden at once", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live, other, unset, empty, calls = BuildYUI(true)
    w.Login()
    eq(live.Components[KEY], false)
    eq(other.Components[KEY], false)
    eq(other.Components.Other, true, "other components kept")
    eq(unset.Components[KEY], false, "an unset value reads as YUI's default on")
    eq(empty.Components, nil, "profiles without components are not created")
    eq(calls[#calls], false, "YUI's own switch runs the disable callback")
    ok(ChatContains(w, "Other"), "other profile named in chat")
    ok(not ChatContains(w, "/reload"), "no reload")
    eq(StatusOf(w.ns.Check(), "yui.auctionhelper"), "off")
    YUI.Components:SetFeatureEnabled(KEY, true)
    w.RunTimers()
    eq(live.Components[KEY], false, "switching it back on in YUI is caught")
  end)

  test("YUI auction panel stays on without Auctionator", function()
    local loaded = Loaded()
    loaded.Auctionator = nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local live, _, _, _, calls = BuildYUI(true)
    w.Login()
    eq(live.Components[KEY], true)
    eq(#calls, 0)
    eq(StatusOf(w.ns.Check(), "yui.auctionhelper"), "inactive")
  end)

  test("YUI auction panel reports a missing API instead of writing", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live = BuildYUI(true)
    YUI.Components.features = {}
    w.Login()
    eq(StatusOf(w.ns.Check(), "yui.auctionhelper"), "blocked")
    eq(live.Components[KEY], true, "nothing written")
  end)

  test("YUI's auction panel and component switch exist in the installed source", function()
    local addons = ADDON_ROOT .. "../YUI/"
    local load = ReadFile(addons .. "Components/!load_Forever.xml")
    ok(load:find("AuctionHelper\\AuctionHelper.lua", 1, true), "Forever loads the auction panel")
    local helper = ReadFile(addons .. "Components/AuctionHelper/AuctionHelper.lua")
    ok(helper:find('RegisterFeature("AuctionHelper"', 1, true), "the panel is a YUI component feature")
    ok(helper:find("default = true", 1, true), "the panel is on by default")
    local components = ReadFile(addons .. "Core/Components.lua")
    ok(components:find("function Components:SetFeatureEnabled(key, enable, options)", 1, true), "YUI publishes SetFeatureEnabled")
    ok(components:find("function Components:GetStore(productId)", 1, true), "YUI publishes GetStore")
    ok(components:find("Components.initializedFeatureStates[key] = isEnabled", 1, true), "YUI records the running state")
  end)
end
