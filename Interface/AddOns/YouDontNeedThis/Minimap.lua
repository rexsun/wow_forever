-- You Don't Need This - minimap button (no libraries: a plain button dragged around the minimap edge)
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.
--
-- Left-click: low-level quests window. Right-click: settings. Drag: move it around the minimap.
-- Position and visibility live in YDNT_DB.settings.minimap = { angle = degrees, hide = bool }.

local _, ns = ...

if not Minimap then return end

local DEFAULT_ANGLE = 200

local function Saved() return ns.DB().settings.minimap end

local button = CreateFrame("Button", "YouDontNeedThisMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT")

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture("Interface\\AddOns\\YouDontNeedThis\\icon.png")
icon:SetPoint("TOPLEFT", 7, -6)

-- Place the button on the minimap's edge at the saved angle (degrees, 0 = right, counter-clockwise).
local function Place()
    local angle = math.rad(Saved().angle or DEFAULT_ANGLE)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    Saved().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place()
end

button:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", FollowCursor)
    GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end)

button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif ns.ToggleQuests then
        ns.ToggleQuests()
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("You Don't Need This")
    local n = ns.LowQuests and #ns.LowQuests() or 0
    GameTooltip:AddLine(("%d low-level quest%s in your log"):format(n, n == 1 and "" or "s"), 1, 1, 1)
    GameTooltip:AddLine("Click: low-level quests", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.UpdateMinimapButton()
    if Saved().hide then
        button:Hide()
    else
        Place()
        button:Show()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
