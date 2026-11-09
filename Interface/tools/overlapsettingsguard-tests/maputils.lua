return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local GUARDED = {
    { id = "mu.worldmapmove", field = "WORLDMAPMOVE" },
    { id = "mu.worldmapscale", field = "WORLDMAPSCALE" },
    { id = "mu.worldmapfade", field = "WORLDMAPFADE" },
    { id = "mu.pierpins", field = "WORLDMAPPINS" },
  }
  local FLIGHT = "travel.flight"

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.MapUtils = true
    return loaded
  end

  local function Saved(values)
    return function() MAUTTAB = values end
  end

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function BuildYUI(activeFilters)
    local live = { YMap = { markers = { serviceFilters = activeFilters or {} } } }
    local other = { YMap = { markers = { serviceFilters = { [FLIGHT] = true, ["service.bank"] = false } } } }
    local noMarkers = { YMap = {} }
    YUI = {
      DB = { GetProfile = function() return live end },
      YMap = { Markers = { GetConfig = function() return live.YMap.markers end } },
    }
    YUI_DB = { profiles = { Default = live, Other = other, Empty = noMarkers } }
    return live, other, noMarkers
  end

  local function BuildRevealYUI(activeEnabled)
    local live = { YMap = { worldMap = { reveal = { enabled = activeEnabled, tint = true } } } }
    local other = { YMap = { worldMap = { reveal = { enabled = true, tint = false } } } }
    local noReveal = { YMap = { worldMap = {} } }
    local empty = { YMap = {} }
    local reveal = { disabled = 0 }
    function reveal:Disable() self.disabled = self.disabled + 1 end
    local map = { MapReveal = reveal, Markers = { GetConfig = function() return { serviceFilters = {} } end } }
    function map:GetDB() return live.YMap end
    YUI = { DB = { GetProfile = function() return live end }, YMap = map }
    YUI_DB = { profiles = { Default = live, Other = other, NoReveal = noReveal, Empty = empty } }
    return live, other, noReveal, empty, reveal
  end

  test("MapUtils rules need both addons and are applied before login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local ids = {}
    for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
    for _, setting in ipairs(GUARDED) do
      local rule = ids[setting.id]
      ok(rule, setting.id)
      eq(rule.when[1], "MapUtils", setting.id)
      eq(rule.when[2], "YUI", setting.id)
      eq(rule.early, true, setting.id .. " runs before login")
    end
    eq(ids["yui.flightmarkers"].when[2], "MapUtils")
    eq(ids["yui.mapreveal"].when[2], "MapUtils")
    eq(ids["euife.zonelevels"].when[2], "MapUtils")
    eq(ids["mu.mapreveal"], nil, "MapUtils keeps its reveal")
  end)

  test("MapUtils is the only reveal that can draw under One Map", function()
    local addons = ADDON_ROOT .. "../"
    local detail = ReadFile(addons .. "MapUtils/zonedetail.lua")
    ok(detail:find('EnumeratePinsByTemplate("MapExplorationPinTemplate")', 1, true), "One Map hides the exploration pin")
    ok(detail:find("pin:SetShown(not hide)", 1, true), "One Map toggles the exploration pin")
    ok(detail:find("MapUtils:GetRevealTint(mapID)", 1, true), "One Map art asks for the reveal tint")
    local reveal = ReadFile(addons .. "MapUtils/reveal.lua")
    ok(reveal:find('MAUTTAB["REVEALMAP"] == false', 1, true), "MapUtils reads its reveal switch")
    local yui = ReadFile(addons .. "YUI/Products/YMap/MapReveal.lua")
    ok(yui:find('TEMPLATE = "MapExplorationPinTemplate"', 1, true), "YUI draws on the exploration pin")
    ok(yui:find("config.enabled and db.worldMap.enabled", 1, true), "YUI reads its reveal switch")
    ok(yui:find("function Reveal:Disable()", 1, true), "YUI publishes Disable")
  end)

  test("YUI reveal is off in every profile and other reveal settings are kept", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live, other, noReveal, empty, reveal = BuildRevealYUI(true)
    w.Login()
    eq(live.YMap.worldMap.reveal.enabled, false)
    eq(live.YMap.worldMap.reveal.tint, true, "tint kept")
    eq(other.YMap.worldMap.reveal.enabled, false)
    eq(other.YMap.worldMap.reveal.tint, false, "stored tint kept")
    eq(noReveal.YMap.worldMap.reveal.enabled, false, "a missing reveal table reads as on")
    eq(empty.YMap.worldMap, nil, "profiles without a world map are not created")
    ok(reveal.disabled > 0, "drawn textures are released at once")
    ok(ChatContains(w, "Other"), "other profile named in chat")
    ok(not ChatContains(w, "/reload"), "no reload")
    eq(StatusOf(w.ns.Check(), "yui.mapreveal"), "off")
    live.YMap.worldMap.reveal.enabled = true
    w.Tick()
    eq(live.YMap.worldMap.reveal.enabled, false, "turning it back on is caught")
  end)

  test("YUI reveal stays on without MapUtils", function()
    local loaded = Loaded()
    loaded.MapUtils = nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local live, _, _, _, reveal = BuildRevealYUI(true)
    w.Login()
    eq(live.YMap.worldMap.reveal.enabled, true)
    eq(reveal.disabled, 0)
    eq(StatusOf(w.ns.Check(), "yui.mapreveal"), "inactive")
  end)

  test("YUI reveal reports a missing API instead of writing", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live = BuildRevealYUI(true)
    YUI.YMap.MapReveal = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), "yui.mapreveal"), "blocked")
    eq(live.YMap.worldMap.reveal.enabled, true, "nothing written")
  end)

  test("guarded MapUtils keys and YUI's flight filter exist in the installed source", function()
    local addons = ADDON_ROOT .. "../"
    local settings = ReadFile(addons .. "MapUtils/settings.lua")
    local mapframe = ReadFile(addons .. "MapUtils/mapframe.lua")
    for _, setting in ipairs(GUARDED) do
      ok(settings:find('"' .. setting.field .. '"', 1, true), setting.field .. " in MapUtils settings")
    end
    ok(mapframe:find('IsEnabled("WORLDMAPMOVE")', 1, true), "MapUtils reads the move switch")
    ok(mapframe:find('IsEnabled("WORLDMAPSCALE")', 1, true), "MapUtils reads the scale switch")
    ok(mapframe:find('MAUTTAB["WORLDMAPFADE"] ~= false', 1, true), "MapUtils reads the fade switch")
    local markers = ReadFile(addons .. "YUI/Products/YMap/Markers/MapEnhancement.lua")
    local data = ReadFile(addons .. "YUI/Products/YMap/Markers/MapDataShared.lua")
    ok(markers:find("config.serviceFilters[source.typeID] ~= false", 1, true), "YUI filters by marker type")
    ok(data:find('typeID == "travel.flight"', 1, true), "YUI flight groups use the guarded type")
    local zones = ReadFile(addons .. "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_ZoneLevels.lua")
    ok(zones:find("EllesmereUI._ZoneLevels", 1, true), "Forever Essentials publishes zone levels")
  end)

  test("MapUtils first run: missing saved variables are created and need no reload", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    for _, setting in ipairs(GUARDED) do eq(MAUTTAB[setting.field], false, setting.field) end
    w.Login()
    ok(not ChatContains(w, "/reload"), "no reload before MapUtils applied anything")
  end)

  test("MapUtils saved overlaps are off before login and other settings are preserved", function()
    local saved = { WORLDMAPMOVE = true, WORLDMAPSCALE = true, WORLDMAPFADE = true, REVEALMAP = true, WORLDMAPPINS = true,
      WORLDMAPSCALEVALUE = 1.2, ONEMAP = true, MINIMAPPINS = true, VESSELWORLDMAPPINS = true,
      FLIGHTWORLDMAPPINS = true, CROSSINGWORLDMAPPINS = true, FISHINGLEVELS = true, ZONELEVELS = true }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(), beforeGuard = Saved(saved) })
    for _, setting in ipairs(GUARDED) do eq(saved[setting.field], false, setting.field) end
    for _, key in ipairs({ "ONEMAP", "MINIMAPPINS", "VESSELWORLDMAPPINS", "FLIGHTWORLDMAPPINS",
      "CROSSINGWORLDMAPPINS", "FISHINGLEVELS", "ZONELEVELS" }) do
      eq(saved[key], true, key .. " kept")
    end
    eq(saved.REVEALMAP, true, "reveal kept")
    eq(saved.WORLDMAPSCALEVALUE, 1.2, "scale value kept")
    w.Login()
    ok(not ChatContains(w, "/reload"), "no reload")
    for _, setting in ipairs(GUARDED) do eq(StatusOf(w.ns.Check(), setting.id), "off", setting.id) end
  end)

  test("MapUtils options toggled after login are reverted and request a reload", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    w.Login()
    w.printed = {}
    MAUTTAB.WORLDMAPFADE = true
    w.Tick()
    eq(MAUTTAB.WORLDMAPFADE, false)
    ok(ChatContains(w, "/reload"), "reload requested")
  end)

  test("MapUtils settings stay available without YUI", function()
    local loaded = Loaded()
    loaded.YUI = nil
    local saved = { WORLDMAPMOVE = true }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, beforeGuard = Saved(saved) })
    w.Login()
    eq(saved.WORLDMAPMOVE, true)
    eq(StatusOf(w.ns.Check(), "mu.worldmapmove"), "inactive")
  end)

  test("YUI flight markers are off in every profile; other filters are kept", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live, other, noMarkers = BuildYUI({ ["service.bank"] = true })
    w.Login()
    eq(live.YMap.markers.serviceFilters[FLIGHT], false)
    eq(live.YMap.markers.serviceFilters["service.bank"], true, "active filter kept")
    eq(other.YMap.markers.serviceFilters[FLIGHT], false)
    eq(other.YMap.markers.serviceFilters["service.bank"], false, "stored filter kept")
    eq(noMarkers.YMap.markers, nil, "profiles without markers are not created")
    ok(ChatContains(w, "Other"), "other profile named in chat")
    eq(StatusOf(w.ns.Check(), "yui.flightmarkers"), "off")
    live.YMap.markers.serviceFilters = {}
    w.Tick()
    eq(live.YMap.markers.serviceFilters[FLIGHT], false, "filter reset is caught")
  end)

  test("YUI flight markers stay on without MapUtils", function()
    local loaded = Loaded()
    loaded.MapUtils = nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local live = BuildYUI({})
    w.Login()
    eq(live.YMap.markers.serviceFilters[FLIGHT], nil)
    eq(StatusOf(w.ns.Check(), "yui.flightmarkers"), "inactive")
  end)

  test("YUI flight markers report a missing marker API instead of writing", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local live = BuildYUI({})
    YUI.YMap.Markers = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), "yui.flightmarkers"), "blocked")
    eq(live.YMap.markers.serviceFilters[FLIGHT], nil, "nothing written")
  end)
end
