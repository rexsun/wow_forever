local _, baseline = ...

-- New characters start on a Blizzard preset; every character should use this account layout.
local TARGET_LAYOUT = "rex"
local RETRY_SECONDS = 2
local MAX_ATTEMPTS = 30
-- One reload per spec group: if the selection did not persist, a second reload would loop.
local MAX_RELOADS = 1

local function Number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function PresetCount()
  local meta = Enum and Enum.EditModePresetLayoutsMeta
  return meta and Number(meta.NumValues) and meta.NumValues or nil
end

function baseline.ActiveLayoutName()
  local layouts = C_EditMode and type(C_EditMode.GetLayouts) == "function" and C_EditMode.GetLayouts()
  local presets = PresetCount()
  if not (layouts and presets and Number(layouts.activeLayout)) then return end
  local active = layouts.activeLayout
  if active >= 1 and active <= presets then
    local manager = EditModePresetLayoutManager
    local copies = manager and type(manager.GetCopyOfPresetLayouts) == "function" and manager:GetCopyOfPresetLayouts()
    local preset = copies and copies[active]
    return preset and preset.layoutName, active
  end
  local layout = type(layouts.layouts) == "table" and layouts.layouts[active - presets]
  return layout and layout.layoutName
end

local function SpecGroup()
  local info = C_SpecializationInfo
  local group = info and type(info.GetActiveSpecGroup) == "function" and info.GetActiveSpecGroup()
    or type(GetActiveTalentGroup) == "function" and GetActiveTalentGroup()
  return Number(group) and group or 1
end

local function Ready()
  local manager = EditModeManagerFrame
  if InCombatLockdown() or not (manager and manager.accountSettings) then return false end
  if type(manager.IsInitialized) == "function" and not manager:IsInitialized() then return false end
  if type(manager.IsEditModeActive) == "function" and manager:IsEditModeActive() then return false end
  if type(manager.HasActiveChanges) == "function" and manager:HasActiveChanges() then return false end
  return C_EditMode and type(C_EditMode.GetLayouts) == "function"
    and type(C_EditMode.SetActiveLayout) == "function" and type(ReloadUI) == "function" and PresetCount() ~= nil
end

local function TargetIndex(layouts, presets)
  if type(layouts.layouts) ~= "table" then return end
  for index, layout in ipairs(layouts.layouts) do
    if type(layout) == "table" and layout.layoutName == TARGET_LAYOUT then return presets + index end
  end
end

local function Record()
  local db = _G.CharacterUIBaselineDB
  if type(db) ~= "table" then
    db = {}
    _G.CharacterUIBaselineDB = db
  end
  if type(db.editModeLayout) ~= "table" then db.editModeLayout = {} end
  return db.editModeLayout
end

-- Selecting a layout from addon code runs Blizzard's EDIT_MODE_LAYOUTS_UPDATED handler
-- tainted (2026-10-17: Edit Mode broke and logout hung). An immediate reload discards that
-- tainted state while the selection itself persists, so a switch is always followed by one.
-- Returns "wait", "missing", "done", "kept", "failed" or "switched".
function baseline.AssignLayout()
  if not Ready() then return "wait" end
  local layouts = C_EditMode.GetLayouts()
  local presets = PresetCount()
  if type(layouts) ~= "table" or not Number(layouts.activeLayout) then return "wait" end
  local target = TargetIndex(layouts, presets)
  if not target then return "missing" end
  local record, group = Record(), tostring(SpecGroup())
  if type(record[group]) ~= "table" then record[group] = {} end
  local entry = record[group]
  if layouts.activeLayout == target then
    entry.assigned, entry.reloads = TARGET_LAYOUT, nil
    return "done"
  end
  -- A character that already used the target, or picked its own saved layout, chose this on purpose.
  if entry.assigned or layouts.activeLayout > presets then return "kept" end
  if (entry.reloads or 0) >= MAX_RELOADS then return "failed" end
  entry.reloads = (entry.reloads or 0) + 1
  C_EditMode.SetActiveLayout(target)
  print("CharacterUIBaseline: Edit Mode layout set to '" .. TARGET_LAYOUT .. "'; reloading the UI.")
  ReloadUI()
  return "switched"
end

local queued, attempts, settled = false, 0, false
local MESSAGES = {
  missing = "CharacterUIBaseline: Edit Mode layout '" .. TARGET_LAYOUT
    .. "' is not saved on this account; this character keeps its current layout.",
  failed = "CharacterUIBaseline: the Edit Mode layout did not switch to '" .. TARGET_LAYOUT
    .. "'. Select it once in Edit Mode.",
}

local function Queue()
  if queued or settled or attempts >= MAX_ATTEMPTS then return end
  queued = true
  C_Timer.After(RETRY_SECONDS, function()
    queued = false
    if settled then return end
    local ok, status = pcall(baseline.AssignLayout)
    if not ok or status == "wait" then
      attempts = attempts + 1
      return Queue()
    end
    settled = true
    if MESSAGES[status] then print(MESSAGES[status]) end
    if status == "switched" then
      -- Reached only when the reload did not happen.
      C_Timer.After(5, function() print("CharacterUIBaseline: type /reload to finish the layout switch.") end)
    end
  end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", function(_, event)
  if event == "ACTIVE_TALENT_GROUP_CHANGED" then settled = false end
  if event ~= "PLAYER_ENTERING_WORLD" then attempts = 0 end
  Queue()
end)
