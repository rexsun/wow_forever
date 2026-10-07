local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Minimap button: left-click opens the options, right-click locks or unlocks
-- the frames, and it can be dragged around the minimap's edge.

local RADIUS = 80 -- how far from the minimap's centre the button sits

-- WoW's Lua has math.atan2; newer Lua (used by the test harness) folds it into atan.
local atan2 = math.atan2 or math.atan

local button

local function Place()
  local angle = math.rad(ns.db.minimapAngle or 200)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end
ns.PlaceMinimapButton = Place

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  ns.db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
  Place()
end

function ns.CreateMinimapButton()
  if button or not Minimap then
    return
  end
  button = CreateFrame("Button", "ForeverUIFramesMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", -1, 1)
  icon:SetTexture(ns.MEDIA .. "healforever-icon")
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

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      if InCombatLockdown() then
        ns.Print("can't move frames in combat.")
        return
      end
      ns.SetLockedEverywhere(not ns.db.locked)
      ns.Print(ns.db.locked and "frames locked." or "frames unlocked - drag the green bar.")
    else
      ns.ToggleOptions()
    end
  end)

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverUIFrames")
    GameTooltip:AddLine("Left-click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: lock or unlock the frames", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  Place()
  button:SetShown(ns.db.minimapButton ~= false)
  ns.minimapButton = button
end

function ns.ApplyMinimapButton()
  if button then
    button:SetShown(ns.db.minimapButton ~= false)
    Place()
  end
end
