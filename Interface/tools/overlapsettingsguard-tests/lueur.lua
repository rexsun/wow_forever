return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  -- Lueur 2.0.0 removed its minimap herb and ore markers and drops their saved keys, so the
  -- guard has nothing of Lueur's left to own: it must neither list a rule nor write LueurDB.
  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.Lueur = true
    loaded.MapUtils = true
    return loaded
  end

  local function ReadFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
  end

  test("Lueur has no guard rule or adapter", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    for _, rule in ipairs(w.ns.policy) do
      ok(rule.adapter ~= "Lueur" and not rule.id:find("^lueur%."), "obsolete Lueur rule: " .. rule.id)
    end
    eq(w.ns.adapters.Lueur, nil, "Lueur adapter")
  end)

  test("installed Lueur has no minimap node markers", function()
    local addons = ADDON_ROOT .. "../"
    eq(ReadFile(addons .. "Lueur/NodeScan.lua"), nil, "NodeScan.lua removed")
    local toc = assert(ReadFile(addons .. "Lueur/Lueur.toc"))
    ok(not toc:find("NodeScan", 1, true), "TOC loads no node scan")
    local settings = assert(ReadFile(addons .. "Lueur/Settings.lua"))
    ok(settings:find('"nodeHerbs", "nodeOre"', 1, true), "Lueur migrates the marker keys away")
  end)

  test("Lueur saved settings are left untouched with MapUtils loaded", function()
    local saved = { enabled = true, range = 15, effect = "aura", schema = 11 }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(), beforeGuard = function() LueurDB = saved end })
    w.Login()
    w.Tick()
    eq(saved.nodeHerbs, nil, "nodeHerbs not written")
    eq(saved.nodeOre, nil, "nodeOre not written")
    ok(not ChatContains(w, "Lueur"), "no Lueur report")
  end)
end
