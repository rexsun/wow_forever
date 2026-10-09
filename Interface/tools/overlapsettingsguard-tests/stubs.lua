-- Just enough of the game API, Leatrix Plus and ForeverUI to load OverlapSettingsGuard
-- outside the game. Each Fresh() call builds a new world and loads the add-on into it.

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

local function NewFrame(objectType, parent)
  local frame = { objectType = objectType, parent = parent, children = {}, points = {}, events = {} }
  NewScripts(frame)
  function frame:GetObjectType() return self.objectType end
  function frame:GetChildren() return unpack(self.children) end
  function frame:GetNumPoints() return #self.points end
  function frame:GetPoint(i) return unpack(self.points[i]) end
  function frame:RegisterEvent(event) self.events[event] = true end
  if parent then table.insert(parent.children, frame) end
  return frame
end

-- Leatrix Plus: ten pages filling LeaPlusGlobalPanel, a named nav button for each,
-- and MakeCB-style checkboxes whose values live in a private table.
local function BuildLeatrix(world, values, saved)
  local panel = NewFrame("Frame")
  for _, name in ipairs({ "AutomateQuests", "AutomateGossip", "MoveChatEditBoxToTop", "SetChatFontSize", "MinimapModder", "ShowFlightTimes" }) do
    values[name] = values[name] or "Off"
  end
  local pages = {}
  for i = 0, 9 do
    NewFrame("Button", panel).s = {}
    local page = NewFrame("Frame", panel)
    page.s = {}
    page.points = { { "TOPLEFT", panel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0 } }
    pages[i] = page
  end
  local function MakeCB(page, field, x, y, reload)
    local box = NewFrame("CheckButton", page)
    box.points = { { "TOPLEFT", page, "TOPLEFT", x, y } }
    box.f = { GetText = function() return reload and "Label*" or "Label" end }
    box.enabled, box.checked = true, false
    function box:GetChecked() return self.checked end
    function box:SetChecked(v) self.checked = v and true or false end
    function box:IsEnabled() return self.enabled end
    function box:Click()
      if not self.enabled then return end
      self.checked = not self.checked
      self:Fire("OnClick")
    end
    box:SetScript("OnShow", function(self) self:SetChecked(values[field] == "On") end)
    box:SetScript("OnClick", function(self) values[field] = self:GetChecked() and "On" or "Off" end)
    world.leatrixBoxes[field] = box
    return box
  end
  world.leatrixBoxes = {}
  MakeCB(pages[1], "AutomateQuests", 146, -92, false)
  MakeCB(pages[1], "AutomateGossip", 146, -112, false)
  MakeCB(pages[3], "UnclampChat", 146, -172, true)
  MakeCB(pages[3], "MoveChatEditBoxToTop", 146, -192, true)
  MakeCB(pages[3], "SetChatFontSize", 146, -212, true)
  MakeCB(pages[5], "MinimapModder", 146, -92, true)
  MakeCB(pages[5], "TipModEnable", 146, -112, true)
  MakeCB(pages[7], "ShowFlightTimes", 340, -252, true)
  world.leatrixPanel = panel
  _G.LeaPlusGlobalPanel = panel
  _G.LeaPlusDB = saved
end

local function BuildForeverUI(world, modules, quests, otherProfiles)
  local ui = { db = { modules = modules }, modules = {}, calls = {} }
  modules.Quests = quests
  local profiles = { Default = ui.db }
  for name, profile in pairs(otherProfiles or {}) do
    profiles[name] = profile
  end
  _G.ForeverUIDB = { profiles = profiles, characters = {} }
  function ui.IsModuleEnabled(name)
    local s = ui.db.modules[name]
    return s == nil or s.enabled ~= false
  end
  function ui.SetModuleEnabled(name, enabled)
    ui.db.modules[name] = ui.db.modules[name] or {}
    ui.db.modules[name].enabled = enabled and true or false
  end
  function ui.RefreshOptions() table.insert(ui.calls, "RefreshOptions") end
  ui.modules.QuestForever = {
    Toggle = function(state)
      ui.SetModuleEnabled("QuestForever", state)
      ui.RefreshOptions()
    end,
  }
  ui.modules.Arrow = {}
  ui.modules.Quests = { PaintAutoLine = function() table.insert(ui.calls, "PaintAutoLine") end }
  world.ui = ui
  _G.ForeverUI = ui
end

-- RestedXP: AceDB-style storage. The live profile is the stored table of the current
-- character, as in AceDB.
local function BuildRestedXP(world, rxp)
  local profiles = rxp.profiles or {}
  profiles["Me - Realm"] = rxp.live or {}
  _G.RXPSettings = { profiles = profiles }
  _G.RXP = { settings = { profile = profiles["Me - Realm"] } }
  _G.RXPData = rxp.accountDefault and { defaultProfile = { profile = rxp.accountDefault } } or { defaultProfile = false }
  _G.RXPCData = rxp.characterDefault and { localDB = { profile = rxp.characterDefault } } or {}
  local registry = { NotifyChange = function() end }
  _G.LibStub = setmetatable({}, {
    __call = function(_, name) if name == "AceConfigRegistry-3.0" then return registry end end,
  })
  world.rxpRegistry = registry
end

-- options: loaded = { addon = true }, leatrix = { values, saved, version },
-- foreverui = { modules, quests, otherProfiles }, rxp = { live, profiles, accountDefault, characterDefault }
function Stubs.Fresh(root, options)
  local world = { printed = {}, popups = {}, timers = {}, tickers = {}, frames = {}, now = 100, combat = false }
  local loaded = options.loaded or {}
  local versions = { Leatrix_Plus = (options.leatrix and options.leatrix.version) or "1.60.11" }

  _G.LeaPlusGlobalPanel, _G.LeaPlusDB, _G.ForeverUI, _G.ForeverUIDB = nil, nil, nil, nil
  _G.RXP, _G.RXPSettings, _G.RXPData, _G.RXPCData, _G.LibStub = nil, nil, nil, nil, nil
  _G.C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    GetAddOnMetadata = function(name) return versions[name] end,
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

  if options.leatrix then
    BuildLeatrix(world, options.leatrix.values or {}, options.leatrix.saved or {})
    world.leatrixValues = options.leatrix.values
  end
  if options.foreverui then
    BuildForeverUI(world, options.foreverui.modules or {}, options.foreverui.quests or {}, options.foreverui.otherProfiles)
  end
  if options.rxp then
    BuildRestedXP(world, options.rxp)
  end

  local ns = {}
  for _, file in ipairs({ "Core.lua", "Policy.lua", "Adapters/LeatrixPlus.lua", "Adapters/ForeverUI.lua", "Adapters/RestedXP.lua", "Guard.lua" }) do
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
  function world.Login() world.Fire("PLAYER_LOGIN") end
  return world
end

return Stubs
