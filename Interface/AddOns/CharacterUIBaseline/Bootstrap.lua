local _, baseline = ...
CharacterUIBaselineDB = CharacterUIBaselineDB or {}
CharacterUIBaselineAccountDB = CharacterUIBaselineAccountDB or {}
local state = CharacterUIBaselineDB
local queued, attempts, sessionDone = false, 0, false
local Queue
local points = { CENTER=true, LEFT=true, RIGHT=true, TOP=true, BOTTOM=true,
  TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true }

local function Number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function CopyPosition(position)
  if not (type(position) == "table" and points[position.point] and points[position.relPoint]
    and Number(position.x) and Number(position.y)) then return end
  return { point=position.point, relPoint=position.relPoint, x=position.x, y=position.y }
end

local function Enabled()
  return type(baseline.source) == "table" and baseline.source.enabled == true
end

local function IsSource()
  local name, surname = (UnitNameUnmodified or UnitName)("player")
  local realm = GetRealmName()
  if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then return nil end
  local full = surname and surname ~= "" and (name .. "-" .. surname) or name
  return full == baseline.source.character and realm == baseline.source.realmName
end

local function Valid(data)
  return type(data) == "table" and type(data.layoutName) == "string" and data.layoutName ~= ""
    and type(data.cvars) == "table" and type(data.chat) == "table"
    and Number(data.chatFontSize) and data.chatFontSize >= 6 and data.chatFontSize <= 72
    and Number(data.chat.x) and Number(data.chat.y) and data.chat.x >= 0 and data.chat.x <= 1
    and data.chat.y >= 0 and data.chat.y <= 1 and Number(data.chat.width) and data.chat.width > 0
    and Number(data.chat.height) and data.chat.height > 0
end

local function Current()
  local published = CharacterUIBaselineAccountDB
  if published.sourceKey == baseline.source.key and Valid(published.baseline) then return published.baseline end
  return baseline
end

local function RaidProfile()
  local db = _G.EllesmereUIDB
  local profile = db and db.profiles and db.profiles[db.activeProfile or "Default"]
  return profile and profile.addons and profile.addons.EllesmereUIRaidFrames
end

local function NativeReady()
  local api, manager = C_EditMode, EditModeManagerFrame
  if not (api and type(api.GetLayouts) == "function" and type(api.SetActiveLayout) == "function"
    and manager and type(manager.IsInitialized) == "function" and manager:IsInitialized()
        and Enum and Enum.EditModePresetLayoutsMeta) then return false end
  if manager:IsEditModeActive() or manager:HasActiveChanges() then return false end
  return true
end

local function LayoutIndex(data)
  if not NativeReady() then return end
  local api = C_EditMode
  if Number(data.presetLayout) and data.presetLayout >= 1
    and data.presetLayout <= Enum.EditModePresetLayoutsMeta.NumValues
    and data.presetLayout == math.floor(data.presetLayout) then return data.presetLayout end
  local layouts = api.GetLayouts()
  if not (layouts and type(layouts.layouts) == "table") then return end
  for index, layout in ipairs(layouts.layouts) do
    if layout.layoutName == data.layoutName then
      return Enum.EditModePresetLayoutsMeta.NumValues + index
    end
  end
end

local function Apply()
  local source = IsSource()
  if source == nil then return false end
  if source then return true end
  local data = Current()
  if not Valid(data) or not NativeReady() then return false end
  if not (ChatFrame1 and type(FCF_SetChatWindowFontSize) == "function"
    and type(FCF_SavePositionAndDimensions) == "function") then return false end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  if not Number(width) or not Number(height) or width <= 0 or height <= 0 then return false end
  local index = LayoutIndex(data)
  if not data.presetLayout and type(data.nativeLayout) == "string" and data.nativeLayout ~= "" then
    local existing = index and C_EditMode.GetLayouts().layouts[index - Enum.EditModePresetLayoutsMeta.NumValues]
    local encoded = existing and C_EditMode.ConvertLayoutInfoToString and C_EditMode.ConvertLayoutInfoToString(existing)
    if encoded ~= data.nativeLayout then
      if not (EllesmereUI and type(EllesmereUI.ApplyPresetEditMode) == "function"
        and EllesmereUI.ApplyPresetEditMode(data.nativeLayout, data.layoutName)) then return false end
      index = LayoutIndex(data)
    end
  end
  if not index then return false end
  C_EditMode.SetActiveLayout(index)
  if C_EditMode.GetLayouts().activeLayout ~= index then return false end
  for name in pairs(baseline.cvars) do
    if type(data.cvars[name]) == "string" then SetCVar(name, data.cvars[name]) end
  end
  for i = 1, 10 do
    local frame = _G["ChatFrame" .. i]
    if frame then FCF_SetChatWindowFontSize(nil, frame, data.chatFontSize) end
  end
  ChatFrame1:ClearAllPoints()
  ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", data.chat.x * width, data.chat.y * height)
  ChatFrame1:SetSize(data.chat.width, data.chat.height)
  FCF_SavePositionAndDimensions(ChatFrame1)
  local raid = RaidProfile()
  if raid and type(data.euiPositions) == "table" then
    for _, key in ipairs({ "partyUnlockPos", "unlockPos" }) do
      local position = CopyPosition(data.euiPositions[key])
      if position then raid[key] = position end
    end
  end
  if type(_ERF_RefreshAll) == "function" then _ERF_RefreshAll() end
  state.revision = baseline.revision
  state.sourceKey = baseline.source.key
  return true
end

local function Capture()
  if not Enabled() or IsSource() ~= true then return false end
  local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
  local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
  local active = layouts and presets and layouts.layouts and layouts.layouts[(layouts.activeLayout or 0) - presets]
  local preset = layouts and presets and Number(layouts.activeLayout)
    and layouts.activeLayout >= 1 and layouts.activeLayout <= presets and layouts.activeLayout or nil
  if not active and preset and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
    active = EditModePresetLayoutManager:GetCopyOfPresetLayouts()[preset]
  end
  if not (active and type(active.layoutName) == "string" and ChatFrame1) then return false end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  local parentScale, scale = UIParent:GetEffectiveScale(), ChatFrame1:GetEffectiveScale()
  if not (Number(width) and Number(height) and width > 0 and height > 0
    and Number(parentScale) and parentScale > 0 and Number(scale) and scale > 0) then return false end
  local getter = _G.GetChatWindowInfo or _G.FCF_GetChatWindowInfo
  if type(getter) ~= "function" then return false end
  local _, font = getter(1)
  local left, bottom = ChatFrame1:GetLeft(), ChatFrame1:GetBottom()
  if not (Number(left) and Number(bottom)) then return false end
  local data = { revision=baseline.revision, layoutName=active.layoutName, cvars={}, chatFontSize=font,
    chat={ x=left * scale / parentScale / width, y=bottom * scale / parentScale / height,
      width=ChatFrame1:GetWidth(), height=ChatFrame1:GetHeight() }, euiPositions={} }
  data.presetLayout = preset
  for name in pairs(baseline.cvars) do
    local value = GetCVar(name)
    if type(value) ~= "string" then return false end
    data.cvars[name] = value
  end
  if not Valid(data) then return false end
  if type(C_EditMode.ConvertLayoutInfoToString) == "function" then
    local encoded = C_EditMode.ConvertLayoutInfoToString(active)
    if type(encoded) == "string" and encoded ~= "" then data.nativeLayout = encoded end
  end
  local raid = RaidProfile()
  for _, key in ipairs({ "partyUnlockPos", "unlockPos" }) do
    data.euiPositions[key] = raid and CopyPosition(raid[key]) or nil
  end
  CharacterUIBaselineAccountDB.sourceKey = baseline.source.key
  CharacterUIBaselineAccountDB.baseline = data
  CharacterUIBaselineAccountDB.capturedAt = GetServerTime and GetServerTime() or nil
  return true
end

Queue = function()
  if queued or sessionDone or not Enabled() or attempts >= 30 then return end
  queued = true
  C_Timer.After(1, function()
    queued = false
    if sessionDone or InCombatLockdown() then return end
    local ok, applied = pcall(Apply)
    if ok and applied then
      sessionDone = true
      print(IsSource() and "CharacterUIBaseline: source character; UI changes will publish at logout."
        or "CharacterUIBaseline: source UI synchronized for this login.")
      return
    end
    attempts = attempts + 1
    if attempts < 30 then Queue()
    else print("CharacterUIBaseline: sync pending. Leave combat/edit mode, then type /uib apply.") end
  end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then
    local ok, captured = pcall(Capture)
    if Enabled() and IsSource() and (not ok or not captured) then
      print("CharacterUIBaseline: source capture unavailable; last published UI retained.")
    end
  else Queue() end
end)

SLASH_CHARACTERUIBASELINE1 = "/uib"
SlashCmdList.CHARACTERUIBASELINE = function(message)
  if message:match("^%s*capture%s*$") then
    local ok, captured = pcall(Capture)
    print(ok and captured and "CharacterUIBaseline: source UI published."
      or "CharacterUIBaseline: capture is available only on the configured source when UI APIs are ready.")
  elseif message:match("^%s*apply%s*$") then
    sessionDone, attempts = false, 0
    Queue()
  else
    print(not Enabled() and "CharacterUIBaseline: source sync disabled or not configured."
      or sessionDone and "CharacterUIBaseline: this login is synchronized; /uib apply retries, /uib capture publishes on source."
      or "CharacterUIBaseline: sync pending; /uib apply retries.")
  end
end
