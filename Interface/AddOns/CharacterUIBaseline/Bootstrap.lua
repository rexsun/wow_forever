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

-- Read-only: selecting or importing an Edit Mode layout from addon code runs Blizzard's
-- EDIT_MODE_LAYOUTS_UPDATED handler in tainted execution, which broke Edit Mode and
-- blocked logout. The layout is therefore only reported; the player selects it.
local function ActiveLayoutName()
  local layouts = C_EditMode and type(C_EditMode.GetLayouts) == "function" and C_EditMode.GetLayouts()
  local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
  if not (layouts and Number(presets) and Number(layouts.activeLayout)) then return end
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

local layoutNotice
-- At PLAYER_LOGOUT the layout API reported the Modern preset although the source used
-- a custom layout, so the source's layout is remembered while it is still in the world.
local seenLayoutName, seenPreset

local function RememberLayout()
  local name, preset = ActiveLayoutName()
  if type(name) == "string" and name ~= "" then seenLayoutName, seenPreset = name, preset end
end

local function Apply()
  local source = IsSource()
  if source == nil then return false end
  if source then return true end
  local data = Current()
  if not Valid(data) then return false end
  if not (ChatFrame1 and type(FCF_SetChatWindowFontSize) == "function"
    and type(FCF_SavePositionAndDimensions) == "function") then return false end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  if not Number(width) or not Number(height) or width <= 0 or height <= 0 then return false end
  local activeName = ActiveLayoutName()
  layoutNotice = activeName and activeName ~= data.layoutName
    and ("CharacterUIBaseline: Edit Mode layout is '" .. activeName .. "'; the source uses '"
      .. data.layoutName .. "'. Select it in Edit Mode if this character should match.") or nil
  for name in pairs(baseline.cvars) do
    local value = data.cvars[name]
    if type(value) == "string" and GetCVar(name) ~= value then SetCVar(name, value) end
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
  local layoutName, preset = seenLayoutName, seenPreset
  if not (type(layoutName) == "string" and ChatFrame1) then return false end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  local parentScale, scale = UIParent:GetEffectiveScale(), ChatFrame1:GetEffectiveScale()
  if not (Number(width) and Number(height) and width > 0 and height > 0
    and Number(parentScale) and parentScale > 0 and Number(scale) and scale > 0) then return false end
  local getter = _G.GetChatWindowInfo or _G.FCF_GetChatWindowInfo
  if type(getter) ~= "function" then return false end
  local _, font = getter(1)
  local left, bottom = ChatFrame1:GetLeft(), ChatFrame1:GetBottom()
  if not (Number(left) and Number(bottom)) then return false end
  local data = { revision=baseline.revision, layoutName=layoutName, cvars={}, chatFontSize=font,
    chat={ x=left * scale / parentScale / width, y=bottom * scale / parentScale / height,
      width=ChatFrame1:GetWidth(), height=ChatFrame1:GetHeight() }, euiPositions={} }
  data.presetLayout = preset
  for name in pairs(baseline.cvars) do
    local value = GetCVar(name)
    if type(value) ~= "string" then return false end
    data.cvars[name] = value
  end
  if not Valid(data) then return false end
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
      if layoutNotice then print(layoutNotice) end
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
events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then
    local ok, captured = pcall(Capture)
    if Enabled() and IsSource() and (not ok or not captured) then
      print("CharacterUIBaseline: source capture unavailable; last published UI retained.")
    end
  else
    if Enabled() and IsSource() then pcall(RememberLayout) end
    if event ~= "EDIT_MODE_LAYOUTS_UPDATED" then Queue() end
  end
end)

SLASH_CHARACTERUIBASELINE1 = "/uib"
SlashCmdList.CHARACTERUIBASELINE = function(message)
  if message:match("^%s*capture%s*$") then
    pcall(RememberLayout)
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
