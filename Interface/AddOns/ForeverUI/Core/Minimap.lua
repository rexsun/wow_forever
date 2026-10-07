local _, ns = ...

-- Minimap button. Left-click opens the options, right-click drops into move
-- mode, and dragging slides it around the minimap's edge. The angle is saved
-- per profile, so it stays where you put it.

local RADIUS = 80
local ICON = ns.MEDIA_PATH .. "foreverui-icon"

-- WoW's Lua has math.atan2; newer Lua (the test harness) folds it into atan.
local atan2 = math.atan2 or math.atan

local button

local function Place()
  if button and button.fuiInBar then
    return   -- the Minimap module has it in the button bar now
  end
  local angle = math.rad(ns.db.minimapAngle or 198)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end
ns.PlaceMinimapButton = Place

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not mx or not cx or not scale or scale == 0 then
    return
  end
  ns.db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
  Place()
end

local function OnEnter(self)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("ForeverUI")
  GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
  GameTooltip:AddLine("Right-click: move frames", 1, 1, 1)
  GameTooltip:AddLine("Drag: slide me around the minimap", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function ns.CreateMinimapButton()
  if button or not Minimap then
    return
  end
  button = CreateFrame("Button", "ForeverUIMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", -1, 1)
  icon:SetTexture(ICON)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", DragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", OnEnter)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      ns.ToggleMovers()
    else
      ns.OpenOptions()
    end
  end)

  ns.minimapButton = button
  Place()
  ns.UpdateMinimapButton()
end

function ns.UpdateMinimapButton()
  if not button then
    return
  end
  button:SetShown(ns.db.minimapButton ~= false)
  Place()
end
