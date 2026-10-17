local Stubs = {}

local function NewScripts(frame)
  frame.scripts, frame.hooks = {}, {}
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  function frame:GetScript(name) return self.scripts[name] end
  function frame:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
  end
  function frame:Fire(name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, fn in ipairs(self.hooks[name] or {}) do fn(self, ...) end
  end
end

local function NewFrame(objectType)
  local frame = { objectType = objectType, events = {} }
  NewScripts(frame)
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsShown() return self.shown == true end
  return frame
end

function Stubs.Fresh(root, options)
  local world = { printed = {}, popups = {}, timers = {}, tickers = {}, frames = {}, now = 100, combat = false }
  local loaded = options.loaded or {}
  world.cvars = options.cvars or {}
  world.cvarWrites = {}
  _G.GetCVar = function(name) return world.cvars[name] end
  _G.SetCVar = function(name, value)
    world.cvars[name] = tostring(value)
    table.insert(world.cvarWrites, { name = name, value = tostring(value) })
  end

  _G.GearInsightForever, _G.GearInsightForeverDB = nil, nil
  _G.GearInsightForeverLeveling, _G.GearInsightForeverKeysHud = nil, nil
  _G.LibStub = nil
  _G.YUI, _G.YUI_DB = nil, nil
  _G.Skinner, _G.SkinnerDB = nil, nil
  _G.EllesmereUIDB, _G._ENP_RefreshAllSettings = nil, nil
  _G.C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
  }
  _G.C_Timer = {
    After = function(_, fn) table.insert(world.timers, fn) end,
    NewTicker = function(_, fn) table.insert(world.tickers, fn) end,
  }
  _G.CreateFrame = function(objectType)
    local frame = NewFrame(objectType)
    table.insert(world.frames, frame)
    return frame
  end
  _G.hooksecurefunc = function(target, name, hook)
    if type(target) == "string" then target, name, hook = _G, target, name end
    local original = target[name]
    target[name] = function(...)
      local results = { original(...) }
      hook(...)
      return unpack(results)
    end
  end
  _G.InCombatLockdown = function() return world.combat end
  _G.GetTime = function() return world.now end
  _G.StaticPopupDialogs = {}
  _G.StaticPopup_Show = function(which, text) table.insert(world.popups, { which = which, text = text }) end
  _G.ReloadUI = function() world.reloaded = true end
  _G.SlashCmdList = {}
  _G.OKAY = "Okay"
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    table.insert(world.printed, table.concat(parts, " "))
  end


  if options.beforeGuard then options.beforeGuard(world) end
  local ns = {}
  for _, file in ipairs(ADDON_FILES) do
    local chunk = assert(loadfile(root .. file))
    chunk("OverlapSettingsGuard", ns)
  end
  world.ns = ns

  function world.RunTimers()
    local guard = 0
    while #world.timers > 0 do
      guard = guard + 1
      assert(guard < 100, "timers keep re-queuing")
      local pending = world.timers
      world.timers = {}
      for _, fn in ipairs(pending) do fn() end
    end
  end
  function world.Tick()
    for _, fn in ipairs(world.tickers) do fn() end
    world.RunTimers()
  end
  function world.Fire(event)
    for _, frame in ipairs(world.frames) do
      if frame.events[event] then frame:Fire("OnEvent", event) end
    end
    world.RunTimers()
  end
  function world.Login()
    world.Fire("PLAYER_LOGIN")
    world.Fire("PLAYER_ENTERING_WORLD")
  end
  return world
end

return Stubs
