return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
  local FEATURES = {
    { id = "euife.spelluprank", key = "SpellUprank", api = "_SpellUprank" },
    { id = "euife.mapreveal", key = "MapReveal", api = "_MapReveal" },
    { id = "euife.mapfade", key = "MapFade", api = "_MapFade" },
    { id = "euife.junkitems", key = "JunkItems", api = "_JunkItems" },
    { id = "euife.classicspellbook", key = "ClassicSpellbook", api = "_ClassicSpellbook" },
    { id = "euife.classictalents", key = "ClassicTalents", api = "_ClassicTalents" },
    { id = "euife.maptravel", key = "MapTravel", api = "_MapTravel" },
    { id = "euife.threatmeter", key = "ThreatMeter", api = "_ThreatMeter" },
  }

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.EllesmereUIForeverEssentials, loaded.Details, loaded.Details_TinyThreat = true, true, true
    return loaded
  end

  -- Mirrors the 9.7.6 feature kit: unset keys read defaults, Apply reads the saved switch.
  local function BuildFE(w, saved)
    EllesmereUIDB = saved or {}
    EllesmereUI = {}
    w.applied = {}
    for _, f in ipairs(FEATURES) do
      local dbKey = f.api
      EllesmereUI[f.api] = {
        Get = function(key)
          local c = EllesmereUIDB[dbKey]
          local v = c and c[key]
          if v == nil and key == "enabled" then return false end
          return v
        end,
        Cfg = function()
          EllesmereUIDB[dbKey] = EllesmereUIDB[dbKey] or {}
          return EllesmereUIDB[dbKey]
        end,
        Apply = function()
          local c = EllesmereUIDB[dbKey]
          w.applied[f.key] = c and c.enabled == true or false
        end,
      }
    end
    EllesmereUI._Fishing = { Get = function() end }
  end

  local function Enable(f)
    EllesmereUI[f.api].Cfg().enabled = true
  end

  test("Forever Essentials rules cover the documented YUI and Details overlaps", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local ids = {}
    for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
    for _, f in ipairs(FEATURES) do
      ok(ids[f.id], f.id)
      eq(ids[f.id].when[1], "EllesmereUIForeverEssentials", f.id .. " watches the module first")
    end
    eq(ids["euife.threatmeter"].when[2], "Details_TinyThreat")
    eq(#w.ns.ValidatePolicy(w.ns.policy, w.ns.adapters), 0, "policy validates")
  end)

  test("Forever Essentials defaults stay off and saved overlaps are switched off at login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    BuildFE(w, { _MapReveal = { enabled = true, alpha = 0.5 } })
    w.Login()
    eq(EllesmereUIDB._MapReveal.enabled, false)
    eq(EllesmereUIDB._MapReveal.alpha, 0.5, "other feature settings preserved")
    eq(w.applied.MapReveal, false, "change applied at once")
    for _, f in ipairs(FEATURES) do
      eq(StatusOf(w.ns.Check(), f.id), "off", f.id)
    end
    eq(EllesmereUIDB._SpellUprank, nil, "untouched defaults write nothing")
  end)

  test("Forever Essentials options toggles are reverted on the next frame", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    BuildFE(w)
    w.Login()
    for _, f in ipairs(FEATURES) do
      local api = EllesmereUI[f.api]
      api.Cfg().enabled = true
      api.Apply()
      w.RunTimers()
      eq(api.Get("enabled"), false, f.key)
      eq(w.applied[f.key], false, f.key .. " applied off")
    end
    Enable(FEATURES[1])
    w.Tick()
    eq(EllesmereUI._SpellUprank.Get("enabled"), false, "direct writes are caught by the ticker")
  end)

  test("Forever Essentials rules are inactive without their owners and leave fishing alone", function()
    local loaded = Loaded()
    loaded.YUI, loaded.Details_TinyThreat = nil, nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    BuildFE(w)
    for _, f in ipairs(FEATURES) do Enable(f) end
    w.Login()
    for _, f in ipairs(FEATURES) do
      eq(EllesmereUI[f.api].Get("enabled"), true, f.key .. " kept without its owner")
      eq(StatusOf(w.ns.Check(), f.id), "inactive", f.id)
    end
  end)

  test("Forever Essentials reports a missing feature API instead of writing storage", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    BuildFE(w)
    EllesmereUI._ThreatMeter = nil
    EllesmereUIDB._ThreatMeter = { enabled = true }
    w.Login()
    eq(StatusOf(w.ns.Check(), "euife.threatmeter"), "blocked")
    eq(EllesmereUIDB._ThreatMeter.enabled, true, "nothing written")
    eq(w.ns.adapters.ForeverEssentials.Revert("ThreatMeter"), false)
  end)
end
