if KallyeRaidFramesLocalSetupDone then return end

local frame = CreateFrame("Frame")
local queued = false
local warned = false

local function CopyActivePreset()
  local info = C_EditMode.GetLayouts()
  local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
  local source = presets[info.activeLayout]
  assert(source, "The active Edit Mode preset is unavailable")
  local copy = CopyTable(source)
  copy.layoutType = Enum.EditModeLayoutType.Character
  local names = {}
  for _, layout in ipairs(info.layouts) do names[layout.layoutName] = true end
  local name, suffix = "Kallye Party Frames", 1
  while names[name] do
    suffix = suffix + 1
    name = "Kallye Party Frames " .. suffix
  end
  copy.layoutName = name
  local combined = {}
  for _, layout in ipairs(presets) do combined[#combined + 1] = layout end
  for _, layout in ipairs(info.layouts) do combined[#combined + 1] = layout end
  combined[#combined + 1] = copy
  info.layouts, info.activeLayout = combined, #combined
  C_EditMode.SaveLayouts(info)
  C_EditMode.SetActiveLayout(info.activeLayout)
end

local function Apply()
  if KallyeRaidFramesLocalSetupDone or InCombatLockdown() then return end
  if not EditModeManagerFrame or not PartyFrame then return end
  if not EditModeManagerFrame.UseRaidStylePartyFrames then
    SetCVar("useCompactPartyFrames", "1")
    if GetCVar("useCompactPartyFrames") ~= "1" then return end
  else
    local lib = LibStub("LibEditModeOverride-1.0", true)
    if not lib or not lib:IsReady() then return end
    lib:LoadLayouts()
    local setting = Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames
    if lib:GetFrameSetting(PartyFrame, setting) ~= 1 then
      -- Blizzard presets cannot be edited; copy the selected one so its positions survive.
      if not lib:CanEditActiveLayout() then
        CopyActivePreset()
        lib:LoadLayouts()
      end
      lib:SetFrameSetting(PartyFrame, setting, 1)
      lib:ApplyChanges()
      if lib:GetFrameSetting(PartyFrame, setting) ~= 1 then return end
    end
  end
  KallyeRaidFramesLocalSetupDone = true
  frame:UnregisterAllEvents()
  print("Kallye Raid Frames: raid-style party frames configured.")
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
  if queued or KallyeRaidFramesLocalSetupDone then return end
  queued = true
  C_Timer.After(0, function()
    queued = false
    local success, problem = pcall(Apply)
    if not success and not warned then
      warned = true
      print("Kallye Raid Frames: raid-style setup is pending: " .. tostring(problem))
    end
  end)
end)
