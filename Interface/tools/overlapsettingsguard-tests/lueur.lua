return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local GUARDED = {
    { id = "lueur.nodeherbs", field = "nodeHerbs" },
    { id = "lueur.nodeore", field = "nodeOre" },
  }

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.Lueur = true
    loaded.MapUtils = true
    return loaded
  end

  local function Saved(values)
    return function() LueurDB = values end
  end

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  test("Lueur minimap rules need both addons and are applied before login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local ids = {}
    for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
    for _, setting in ipairs(GUARDED) do
      local rule = ids[setting.id]
      ok(rule, setting.id)
      eq(rule.when[1], "Lueur", setting.id)
      eq(rule.when[2], "MapUtils", setting.id)
      eq(rule.early, true, setting.id .. " runs before login")
    end
  end)

  test("guarded Lueur keys exist in the installed source", function()
    local addons = ADDON_ROOT .. "../"
    local main = ReadFile(addons .. "Lueur/Lueur.lua")
    local scan = ReadFile(addons .. "Lueur/NodeScan.lua")
    for _, setting in ipairs(GUARDED) do
      local default = main:find(setting.field .. "%s*=%s*true") or main:find(setting.field .. "%s*=%s*false")
      ok(default, setting.field .. " default in Lueur")
    end
    ok(scan:find('herb = "nodeHerbs", ore = "nodeOre"', 1, true), "NodeScan reads both switches")
  end)

  test("Lueur first run: missing saved variables are created and need no reload", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    for _, setting in ipairs(GUARDED) do eq(LueurDB[setting.field], false, setting.field) end
    w.Login()
    ok(not ChatContains(w, "/reload"), "no reload before Lueur scanned anything")
  end)

  test("Lueur minimap markers are off before login and its glow settings are preserved", function()
    local saved = { nodeHerbs = true, nodeOre = true, enabled = true, range = 15, effect = "aura", nodeSize = 12 }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(), beforeGuard = Saved(saved) })
    for _, setting in ipairs(GUARDED) do eq(saved[setting.field], false, setting.field) end
    eq(saved.enabled, true, "glow stays on")
    eq(saved.range, 15, "range kept")
    eq(saved.effect, "aura", "effect kept")
    eq(saved.nodeSize, 12, "marker size kept")
    w.Login()
    for _, setting in ipairs(GUARDED) do eq(StatusOf(w.ns.Check(), setting.id), "off", setting.id) end
  end)

  test("Lueur minimap markers switched on after login are reverted and request a reload", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    w.Login()
    w.printed = {}
    LueurDB.nodeOre = true
    w.Tick()
    eq(LueurDB.nodeOre, false)
    ok(ChatContains(w, "/reload"), "reload requested")
  end)

  test("Lueur minimap markers stay available without MapUtils", function()
    local loaded = Loaded()
    loaded.MapUtils = nil
    local saved = { nodeHerbs = true, nodeOre = true }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, beforeGuard = Saved(saved) })
    w.Login()
    eq(saved.nodeHerbs, true)
    eq(saved.nodeOre, true)
    eq(StatusOf(w.ns.Check(), "lueur.nodeherbs"), "inactive")
  end)
end
