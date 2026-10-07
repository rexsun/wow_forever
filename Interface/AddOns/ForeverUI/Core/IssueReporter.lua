local _, ns = ...

-- The beta "Issue Reporter": Blizzard_PTRFeedback's PTR_IssueReporter frame,
-- which floats a quarter of the way up the screen and comes back every login.
--
-- Setting `hideIssueReporter` (on by default) hides it outright. Off, it's
-- tucked into the top-left corner, shrunk, and tinted green -- a small
-- digital bug, out of everyone's way -- so the owner can still file reports.
--
-- The frame's own OnShow re-anchors it wherever Blizzard wants it, so both
-- the hide and the tuck are re-applied from an OnShow hook (HookScript runs
-- after theirs, never instead of it). It's a plain DIALOG-strata frame, not
-- protected; everything below is still pcall-guarded and kept out of combat.

local CANDIDATES = { "PTR_IssueReporter", "IssueReporter", "IssueReporterFrame" }

local function Find()
  for _, name in ipairs(CANDIDATES) do
    local frame = _G[name]
    if type(frame) == "table" and frame.SetPoint then
      return frame
    end
  end
end
ns.FindIssueReporter = Find

function ns.IssueReporterHidden()
  return ns.db == nil or ns.db.hideIssueReporter ~= false
end

-- Paint it green: every texture region on it, so the blue bug reads green.
local function Greenify(frame)
  local regions = { frame.GetRegions and frame:GetRegions() }
  for _, region in ipairs(regions) do
    if region and region.GetObjectType and region:GetObjectType() == "Texture"
      and region.SetVertexColor then
      pcall(region.SetVertexColor, region, 0.35, 1.0, 0.45)
    end
  end
  local bug = frame.ReportBug
  if bug and bug.GetNormalTexture then
    local normal = bug:GetNormalTexture()
    if normal and normal.SetVertexColor then
      pcall(normal.SetVertexColor, normal, 0.35, 1.0, 0.45)
    end
  end
end

local hooked = {}
local applying = false

local function Apply()
  local frame = Find()
  if not frame then
    return false
  end
  ns.WhenOutOfCombat(function()
    if applying then return end
    applying = true
    if ns.IssueReporterHidden() then
      pcall(frame.Hide, frame)
    else
      -- Show first: its OnShow re-anchors it to Blizzard's spot, so ours
      -- has to come after.
      pcall(frame.Show, frame)
      pcall(frame.ClearAllPoints, frame)
      pcall(frame.SetPoint, frame, "TOPLEFT", UIParent, "TOPLEFT", 8, -8)
      pcall(frame.SetScale, frame, 0.65)   -- a little bug, not a billboard
      Greenify(frame)
    end
    applying = false
  end)
  if not hooked[frame] and frame.HookScript then
    hooked[frame] = true
    -- Blizzard shows it on login and after its own moves; follow every time.
    pcall(frame.HookScript, frame, "OnShow", function()
      if not applying then
        Apply()
      end
    end)
  end
  return true
end
ns.ApplyIssueReporter = Apply

function ns.SetIssueReporterHidden(hidden)
  ns.db.hideIssueReporter = hidden and true or false
  Apply()
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function()
  Apply()
  -- Its frame is built on PLAYER_ENTERING_WORLD and can land after ours.
  if C_Timer and C_Timer.After then
    C_Timer.After(2, Apply)
    C_Timer.After(5, Apply)
  end
end)
