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
    { id = "euife.zonelevels", key = "ZoneLevels", api = "_ZoneLevels" },
    { id = "euife.gatherskill", key = "GatherSkill", api = "_GatherSkill" },
    { id = "euife.skinningskill", key = "GatherSkinning", api = "_GatherSkill", field = "skinning" },
  }

  local function Field(f) return f.field or "enabled" end

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.EllesmereUIForeverEssentials, loaded.Details, loaded.Details_TinyThreat = true, true, true
    loaded.MapUtils, loaded.GatherLite = true, true
    return loaded
  end

  -- Mirrors the 9.7.6 feature kit: unset keys read defaults, Apply reads the saved switches.
  -- Gathering Skill's Skinning (9.8.9) is a second switch on the same feature.
  local function BuildFE(w, saved)
    EllesmereUIDB = saved or {}
    EllesmereUI = {}
    w.applied = {}
    for _, f in ipairs(FEATURES) do
      local dbKey = f.api
      EllesmereUI[f.api] = EllesmereUI[f.api] or {
        Get = function(key)
          local c = EllesmereUIDB[dbKey]
          local v = c and c[key]
          if v == nil and (key == "enabled" or key == "skinning") then return false end
          return v
        end,
        Cfg = function()
          EllesmereUIDB[dbKey] = EllesmereUIDB[dbKey] or {}
          return EllesmereUIDB[dbKey]
        end,
        Apply = function()
          local c = EllesmereUIDB[dbKey]
          for _, g in ipairs(FEATURES) do
            if g.api == dbKey then w.applied[g.key] = c and c[Field(g)] == true or false end
          end
        end,
      }
    end
    EllesmereUI._Fishing = { Get = function() end }
  end

  local function Enable(f)
    EllesmereUI[f.api].Cfg()[Field(f)] = true
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
    eq(ids["euife.gatherskill"].when[2], "GatherLite")
    eq(ids["euife.skinningskill"].when[2], "GearInsight_Forever")
    eq(#w.ns.ValidatePolicy(w.ns.policy, w.ns.adapters), 0, "policy validates")
  end)

  -- GatherLite has no switch for its node-skill tooltip line, so only EUI's copy can give way.
  test("GatherLite always adds the node skill line that Forever Essentials Gathering Skill adds", function()
    local function ReadFile(path)
      local file = assert(io.open(path, "rb"))
      local text = file:read("*a")
      file:close()
      return text
    end
    local addons = ADDON_ROOT .. "../"
    local gl = ReadFile(addons .. "GatherLite/scripts/main.lua")
    ok(gl:find("TooltipDataProcessor.AddTooltipPostCall(types.Object, onNativeTooltip)", 1, true),
      "GatherLite hooks world-object tooltips")
    ok(gl:find("tooltip:AddLine(requirement, GatherLite:GetNodeSkillRequirementColor(object, profession))", 1, true),
      "GatherLite adds the skill requirement line")
    ok(not gl:find("db.profile.tooltip", 1, true), "GatherLite still has no tooltip switch")
    local fe = ReadFile(addons .. "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_GatherSkill.lua")
    ok(fe:find("TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)", 1, true),
      "Forever Essentials hooks the same tooltips")
    ok(fe:find('module.Feature("gatherSkill", { enabled = false, skinning = false })', 1, true),
      "Forever Essentials is off by default")
    ok(fe:find("EllesmereUI._GatherSkill = {", 1, true), "Forever Essentials publishes the feature API")
  end)

  -- GearInsight has no switch for its skinning tooltip line, so only EUI's Skinning can give way.
  test("GearInsight always adds the skinning skill line that Forever Essentials Skinning adds", function()
    local function ReadFile(path)
      local file = assert(io.open(path, "rb"))
      local text = file:read("*a")
      file:close()
      return text
    end
    local addons = ADDON_ROOT .. "../"
    local gi = ReadFile(addons .. "GearInsight_Forever/Prof.lua")
    ok(gi:find("TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(t) if t == GameTooltip then pcall(P.SkinTip, t) end end)", 1, true),
      "GearInsight hooks unit tooltips for skinning")
    ok(gi:find("UNIT_SKINNABLE_LEATHER", 1, true), "GearInsight finds the Skinnable line")
    local skinTip = gi:sub(gi:find("function P.SkinTip", 1, true), gi:find("table.insert(ns.modules", 1, true))
    ok(not skinTip:find("db", 1, true) and not skinTip:find("Opt", 1, true), "GearInsight still has no skinning switch")
    local fe = ReadFile(addons .. "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_GatherSkill.lua")
    ok(fe:find('not (F.Enabled() and F.Get("skinning"))', 1, true), "Forever Essentials Skinning reads its own switch")
    ok(fe:find("TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)", 1, true),
      "Forever Essentials hooks the same tooltips")
    ok(fe:find("text == UNIT_SKINNABLE_LEATHER", 1, true), "Forever Essentials annotates the same line")
  end)

  test("Forever Essentials Skinning is switched off without touching Gathering Skill", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    BuildFE(w, { _GatherSkill = { skinning = true } })
    w.Login()
    eq(EllesmereUIDB._GatherSkill.skinning, false, "skinning off")
    eq(EllesmereUIDB._GatherSkill.enabled, nil, "Gathering Skill default left unwritten")
    eq(StatusOf(w.ns.Check(), "euife.skinningskill"), "off")
    eq(StatusOf(w.ns.Check(), "euife.gatherskill"), "off")
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
      api.Cfg()[Field(f)] = true
      api.Apply()
      w.RunTimers()
      eq(api.Get(Field(f)), false, f.key)
      eq(w.applied[f.key], false, f.key .. " applied off")
    end
    Enable(FEATURES[1])
    w.Tick()
    eq(EllesmereUI._SpellUprank.Get("enabled"), false, "direct writes are caught by the ticker")
  end)

  test("Forever Essentials rules are inactive without their owners and leave fishing alone", function()
    local loaded = Loaded()
    loaded.YUI, loaded.Details_TinyThreat, loaded.MapUtils, loaded.GatherLite = nil, nil, nil, nil
    loaded.GearInsight_Forever = nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    BuildFE(w)
    for _, f in ipairs(FEATURES) do Enable(f) end
    w.Login()
    for _, f in ipairs(FEATURES) do
      eq(EllesmereUI[f.api].Get(Field(f)), true, f.key .. " kept without its owner")
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
