return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  -- LootRollMover was removed because YUI's Loot Roll HUD replaces it, so the guard must not
  -- keep that HUD off any more.
  local KEY = "LootRoll"

  local function ReadFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
  end

  local function BuildYUI()
    local live = { Components = { [KEY] = true, AuctionHelper = false } }
    local calls = {}
    local components = {
      features = {
        [KEY] = { product = "suite", default = true },
        AuctionHelper = { product = "suite", default = true },
      },
      initializedFeatureStates = { [KEY] = true, AuctionHelper = false },
    }
    function components:GetStore() return live.Components end
    function components:SetFeatureEnabled(key, enable)
      live.Components[key] = enable == true
      self.initializedFeatureStates[key] = enable == true
      calls[#calls + 1] = key .. "=" .. tostring(enable == true)
      return true
    end
    YUI = { DB = { GetProfile = function() return live end }, Components = components }
    YUI_DB = { profiles = { Default = live } }
    return live, calls
  end

  test("LootRollMover has no guard rule and YUI's loot roll HUD is not guarded", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    for _, rule in ipairs(w.ns.policy) do
      ok(rule.id ~= "yui.lootroll", "obsolete rule yui.lootroll")
      ok(rule.key ~= KEY, "no rule targets YUI's loot roll HUD: " .. rule.id)
      for _, name in ipairs(rule.when or {}) do
        ok(name ~= "LootRollMover", "rule still depends on LootRollMover: " .. rule.id)
      end
    end
    ok(not w.ns.adapters.YUI.Knows(KEY), "the YUI adapter no longer handles LootRoll")
  end)

  test("YUI's loot roll HUD stays on with the installed pack", function()
    local loaded = {}
    for name in pairs(INSTALLED_ADDONS) do loaded[name] = true end
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local live, calls = BuildYUI()
    w.Login()
    w.Tick()
    eq(live.Components[KEY], true)
    for _, call in ipairs(calls) do ok(call ~= KEY .. "=false", "the HUD is not switched off") end
  end)

  test("LootRollMover is gone and YUI's loot roll component loads on Forever", function()
    local addons = ADDON_ROOT .. "../"
    eq(ReadFile(addons .. "LootRollMover/LootRollMover.toc"), nil, "LootRollMover removed")
    local toc = assert(ReadFile(ADDON_ROOT .. "OverlapSettingsGuard.toc"))
    ok(not toc:find("LootRollMover", 1, true), "no TOC dependency on LootRollMover")
    local load = assert(ReadFile(addons .. "YUI/Components/!load_Forever.xml"))
    ok(load:find("LootRoll\\!load_Forever.xml", 1, true), "Forever loads the loot roll component")
    local roll = assert(ReadFile(addons .. "YUI/Components/LootRoll/LootRoll.lua"))
    ok(roll:find('local Feature = { id = KEY, name = L["name"], description = L["description"], default = true,', 1, true),
      "the HUD is on by default")
    local adapter = assert(ReadFile(addons .. "YUI/Components/LootRoll/Adapter_Forever.lua"))
    ok(adapter:find("GroupLootFrame", 1, true), "it takes over Blizzard's group loot roll frames")
  end)
end
