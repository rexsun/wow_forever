local passed = 0
local function test(name, run)
  local original = _G.print
  local frames, timers, combat, ready = {}, {}, false, true
  local settings = { party = 0, other = 42 }
  local editable, applies, saves, active = true, 0, 0, 3
  local layouts = { { layoutName = "Existing", layoutType = 1, systems = { { setting = 42 } } } }
  _G.KallyeRaidFramesLocalSetupDone = nil
  _G.print = function() end
  _G.InCombatLockdown = function() return combat end
  _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  _G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterAllEvents() self.stopped = true end
    function frame:SetScript(_, fn) self.event = fn end
    frames[#frames + 1] = frame
    return frame
  end
  _G.Enum = { EditModeLayoutType = { Character = 2 }, EditModeUnitFrameSetting = { UseRaidStylePartyFrames = 10 } }
  _G.PartyFrame = { system = 3, systemIndex = 3 }
  _G.EditModeManagerFrame = { UseRaidStylePartyFrames = function() return settings.party == 1 end }
  _G.EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return {
    { layoutName = "Modern", layoutType = 0, systems = { { original = "modern" } } },
    { layoutName = "Classic", layoutType = 0, systems = { { original = "classic" } } },
  } end }
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
  end
  _G.CopyTable = copy
  _G.C_EditMode = {
    GetLayouts = function() return { activeLayout = active, layouts = copy(layouts) } end,
    SaveLayouts = function(info) saves = saves + 1; layouts = info.layouts end,
    SetActiveLayout = function(index) active = index; editable = true end,
  }
  local lib = {}
  function lib:IsReady() return ready end
  function lib:LoadLayouts() end
  function lib:CanEditActiveLayout() return editable end
  function lib:GetFrameSetting() return settings.party end
  function lib:SetFrameSetting(_, setting, value) assert(not combat); assert(setting == 10); settings.party = value end
  function lib:ApplyChanges() assert(not combat); applies = applies + 1 end
  _G.LibStub = setmetatable({}, { __call = function() return lib end })
  local function drain()
    local pending = timers; timers = {}
    for _, fn in ipairs(pending) do fn() end
  end
  local world = {
    event = function(event) frames[1].event(nil, event) end,
    drain = drain,
    combat = function(value) combat = value end,
    ready = function(value) ready = value end,
    preset = function() editable = false; active = 2 end,
    settings = settings,
    applies = function() return applies end,
    saves = function() return saves end,
    layouts = function() return layouts end,
    stopped = function() return frames[1].stopped end,
  }
  local loader, problem = loadfile("AddOns/KallyeRaidFrames/LocalSetup.lua")
  assert(loader, problem)
  loader()
  run(world)
  _G.print = original
  passed = passed + 1
  io.write("PASS  ", name, "\n")
end

test("custom layout changes only party style once", function(w)
  w.event("PLAYER_LOGIN"); w.drain()
  assert(w.settings.party == 1 and w.settings.other == 42)
  assert(w.applies() == 1 and w.saves() == 0)
  assert(KallyeRaidFramesLocalSetupDone == true and w.stopped())
  w.settings.party = 0
  w.event("EDIT_MODE_LAYOUTS_UPDATED"); w.drain()
  assert(w.settings.party == 0 and w.applies() == 1)
end)

test("raid style setup waits for combat and layout readiness", function(w)
  w.combat(true); w.event("PLAYER_LOGIN"); w.drain()
  assert(w.settings.party == 0 and not KallyeRaidFramesLocalSetupDone)
  w.combat(false); w.ready(false); w.event("PLAYER_REGEN_ENABLED"); w.drain()
  assert(w.settings.party == 0 and not KallyeRaidFramesLocalSetupDone)
  w.ready(true); w.event("EDIT_MODE_LAYOUTS_UPDATED"); w.drain()
  assert(w.settings.party == 1 and KallyeRaidFramesLocalSetupDone)
end)

test("an already enabled party style is preserved without layout writes", function(w)
  w.settings.party = 1; w.event("PLAYER_LOGIN"); w.drain()
  assert(w.applies() == 0 and w.saves() == 0)
  assert(KallyeRaidFramesLocalSetupDone and w.stopped())
end)

test("preset copy preserves selected preset and existing layouts", function(w)
  w.preset(); w.event("PLAYER_LOGIN"); w.drain()
  assert(w.saves() == 1 and w.settings.party == 1)
  local layouts = w.layouts()
  assert(layouts[3].layoutName == "Existing")
  assert(layouts[4].systems[1].original == "classic")
  assert(layouts[4].layoutType == 2 and KallyeRaidFramesLocalSetupDone)
end)

io.write(passed, " setup tests passed\n")
