local tests, failures = {}, {}

local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function eq(actual, expected, what)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
  end
end

local function Frame(spec)
  spec = spec or {}
  local frame = { points = {} }
  function frame:IsShown() return spec.shown ~= false end
  function frame:GetRect() return spec.left, spec.bottom, spec.width, spec.height end
  function frame:GetEffectiveScale() return spec.scale or 1 end
  function frame:GetWidth() return spec.width end
  function frame:GetHeight() return spec.height end
  function frame:GetNumPoints() return #self.points end
  function frame:GetPoint(i) return unpack(self.points[i]) end
  function frame:GetName() return spec.name end
  return frame
end

-- Loads the addon against a 1920x1080 UIParent at scale 1 and returns its namespace.
local function Load(options)
  options = options or {}
  local world = { printed = {}, placers = {} }
  issecretvalue = options.issecretvalue or function() return false end
  UIParent = Frame({ left = 0, bottom = 0, width = 1920, height = 1080, scale = options.uiScale or 1 })
  GroupLootContainer = options.container or Frame({ width = 256, height = 100, scale = options.uiScale or 1 })
  GroupLootFrame1 = Frame({ width = 300, height = 84 })
  YUI = options.yui
  LootRollAnchorDB = nil
  SlashCmdList = {}
  time = function() return 1000 end
  print = function(...) world.printed[#world.printed + 1] = table.concat({ ... }, " ") end
  EllesmereUI = {
    SetFramePlacer = function(frame, owner, fn)
      world.placers[#world.placers + 1] = { frame = frame, owner = owner, fn = fn }
      return true
    end,
  }
  if options.noEUI then EllesmereUI = nil end
  CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(e) self.events[e] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(_, fn) self.onEvent = fn end
    world.events = frame
    return frame
  end
  local ns = {}
  for _, file in ipairs({ "Placement.lua", "LootRollAnchor.lua" }) do
    assert(loadfile(ADDON_ROOT .. file))("LootRollAnchor", ns)
  end
  function world.Fire(event, name)
    if world.events.events[event] then world.events.onEvent(world.events, event, name) end
  end
  world.ns = ns
  return world
end

local function BarYUI(rects)
  local bars, groups = {}, {}
  for i, r in ipairs(rects.bars or {}) do bars["bar" .. i] = { holder = Frame(r) } end
  for i, r in ipairs(rects.groups or {}) do groups[i] = { frame = Frame(r) } end
  return { YActionBar = { BarManager = { bars = bars } }, YHUD = { View = { groups = groups } } }
end

test("stack sits at the base offset when nothing is in the way", function()
  local w = Load({ yui = BarYUI({}) })
  eq(w.ns.Compute(GroupLootContainer), 120)
end)

test("stack steps above centred YUI bars and HUD groups, lowest first", function()
  local w = Load({ yui = BarYUI({
    bars = { { left = 700, bottom = 20, width = 520, height = 120 }, { left = 700, bottom = 140, width = 520, height = 40 } },
    groups = { { left = 860, bottom = 300, width = 200, height = 60 } },
  }) })
  eq(w.ns.Compute(GroupLootContainer), 188, "above both bars; the HUD group starts higher than the stack needs")
  GroupLootContainer = Frame({ width = 256, height = 200 })
  eq(w.ns.Compute(GroupLootContainer), 368, "a taller stack also clears the HUD group")
end)

test("frames outside the roll column or hidden do not move the stack", function()
  local w = Load({ yui = BarYUI({
    bars = { { left = 0, bottom = 100, width = 300, height = 300 }, { left = 800, bottom = 100, width = 300, height = 300, shown = false } },
  }) })
  eq(w.ns.Compute(GroupLootContainer), 120)
end)

test("rects are converted from frame scale into UIParent units and the stack stays on screen", function()
  local w = Load({ yui = BarYUI({ bars = { { left = 400, bottom = 50, width = 400, height = 100, scale = 2 } } }) })
  eq(w.ns.Compute(GroupLootContainer), 308, "bar top at 300 UI units plus the gap")
  w = Load({ yui = BarYUI({ bars = { { left = 700, bottom = 0, width = 520, height = 1060 } } }) })
  eq(w.ns.Compute(GroupLootContainer), 980, "never above the top of the screen")
end)

test("secret frame values defer placement instead of guessing", function()
  local secret = {}
  local w = Load({
    yui = BarYUI({ bars = { { left = 700, bottom = secret, width = 520, height = 100 } } }),
    issecretvalue = function(v) return v == secret end,
  })
  eq(w.ns.Compute(GroupLootContainer), false)
end)

test("placer is registered once on login and returns a UIParent bottom anchor in container units", function()
  local w = Load({ yui = BarYUI({}), uiScale = 0.64 })
  GroupLootContainer = Frame({ width = 256, height = 100, scale = 0.8 })
  w.Fire("ADDON_LOADED", "LootRollAnchor")
  eq(#w.placers, 1)
  eq(w.placers[1].frame, GroupLootContainer)
  eq(w.placers[1].owner, "cdm")
  w.Fire("PLAYER_LOGIN")
  eq(#w.placers, 1, "not registered twice")
  local point, relative, relativePoint, x, y = w.placers[1].fn(GroupLootContainer)
  eq(point, "BOTTOM"); eq(relative, UIParent); eq(relativePoint, "BOTTOM"); eq(x, 0)
  eq(y, 120 * 0.64 / 0.8, "offset converted to the container's scale")
  eq(LootRollAnchorDB.placements, 1)
end)

test("without EllesmereUI's placer Blizzard keeps the position and one message explains it", function()
  local w = Load({ noEUI = true })
  w.Fire("ADDON_LOADED", "LootRollAnchor")
  w.Fire("PLAYER_LOGIN")
  eq(#w.printed, 1)
end)

test("registration waits for a late-loading GroupLootContainer", function()
  local w = Load({ yui = BarYUI({}) })
  local container = GroupLootContainer
  GroupLootContainer = nil
  w.Fire("ADDON_LOADED", "LootRollAnchor")
  w.Fire("PLAYER_LOGIN")
  eq(#w.placers, 0)
  GroupLootContainer = container
  w.Fire("ADDON_LOADED", "Blizzard_UIPanels_Game")
  eq(#w.placers, 1)
end)

for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    io.write("PASS  ", t.name, "\n")
  else
    io.write("FAIL  ", t.name, "\n      ", tostring(err), "\n")
    failures[#failures + 1] = t.name
  end
end
io.write(("\n%d tests, %d failed\n"):format(#tests, #failures))
return #failures
