local _, ns = ...

-- "About saving on the Forever beta": a window at login, shown only when the
-- game handed back no saved settings (the client bug in docs/saving-bug.md).
-- It says what is happening, that it is Blizzard's to fix, how to report it,
-- and what to do meanwhile so the macro backup (Core/MacroBackup.lua) keeps
-- your changes: change, wait a few seconds, then reload.
--
-- "Don't show this again" is itself carried in the macro backup, since a
-- normal saved flag is exactly what the bug forgets. Once Blizzard fixes the
-- client, settings load again and the window never appears.
--
--   /fui saving   opens it any time

local WIDTH, HEIGHT = 560, 520
local ACCENT = { 0.30, 0.76, 1.00 }
local AMBER  = { 1.00, 0.72, 0.30 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.66, 0.68, 0.74 }

local window

local function Text(parent, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(fs, "general")
  local path, _, flags = fs:GetFont()
  if path then fs:SetFont(path, size, flags or "") end
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetSpacing then fs:SetSpacing(2) end
  return fs
end

-- A ready-made report, with this client's build filled in.
function ns.SaveBugReportText()
  local version, build = "?", "?"
  if GetBuildInfo then
    local v, b = GetBuildInfo()
    version, build = v or "?", b or "?"
  end
  return ("WoW: Forever beta %s (%s): addon SavedVariables are not loaded back. "
    .. "The client writes each addon's settings to WTF\\Account\\...\\SavedVariables correctly, "
    .. "but after a /reload or a restart the addon's saved variable is nil at ADDON_LOADED, "
    .. "so every addon resets to its defaults. It affects all addons, not one in particular. "
    .. "Tracked by the community as github.com/ClassicWoWCommunity/forever-bugs issue 34."):format(version, build)
end

local function Section(parent, y, title, body)
  local head = Text(parent, 15, ACCENT)
  head:SetPoint("TOPLEFT", 20, y)
  head:SetText(title)
  local text = Text(parent, 12, TEXT)
  text:SetPoint("TOPLEFT", 20, y - 20)
  text:SetWidth(WIDTH - 40)
  text:SetText(body)
  return y - 24 - math.ceil(text:GetStringHeight() or 40)
end

local function Build()
  window = CreateFrame("Frame", "ForeverUISaveNotice", UIParent)
  window:SetSize(WIDTH, HEIGHT)
  window:SetPoint("CENTER", 0, 40)
  window:SetFrameStrata("DIALOG")
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  ns.Skin.Panel(window, { color = { 0.03, 0.04, 0.06, 0.97 }, borderColor = AMBER })
  table.insert(UISpecialFrames, "ForeverUISaveNotice")

  local title = Text(window, 19, AMBER)
  title:SetPoint("TOPLEFT", 20, -16)
  title:SetText("About saving on the Forever beta")

  local y = -50
  y = Section(window, y, "What's happening",
    "The Forever beta has a bug in the game itself: it saves every addon's settings, but doesn't load "
    .. "them back after a /reload or a restart. Every addon is affected, not just ForeverUI, and only "
    .. "Blizzard can fix it.")
  y = Section(window, y - 8, "What ForeverUI does about it",
    "It keeps your essentials in a few character macros named \"FUI Save 1\", \"FUI Save 2\" and on: "
    .. "your setup choices, which parts of ForeverUI run, your role grids, their click-casts, and "
    .. "where you've moved things. They come back automatically when you log in. Please don't delete "
    .. "those macros, and keep a few character macro slots free.")
  y = Section(window, y - 8, "Keep your own copy of everything",
    "The macros hold the essentials. For every last setting (colours, textures, sizes), copy your "
    .. "whole setup as text and keep it somewhere safe. After a restart, paste it back and it's all "
    .. "there again, straight away. (/fui backup and /fui restore do the same.)")
  local keep = ns.OptionButton(window, 170, "Copy my whole setup", function()
    if ns.ShowSetupBackup then ns.ShowSetupBackup() end
  end)
  keep:SetHeight(26)
  keep:SetPoint("TOPLEFT", 20, y - 6)
  local paste = ns.OptionButton(window, 170, "Paste it back", function()
    if ns.ShowSetupRestore then ns.ShowSetupRestore() end
  end)
  paste:SetHeight(26)
  paste:SetPoint("LEFT", keep, "RIGHT", 10, 0)
  y = y - 40
  y = Section(window, y - 8, "To keep your changes",
    "1.  Make your change.\n"
    .. "2.  Wait a few seconds (the backup saves about a second after a change).\n"
    .. "3.  Then /reload, log out, or press \"Save and reload UI\" in the Heal, Tank or DPS window.")
  y = Section(window, y - 8, "Please report it to Blizzard",
    "The more players report it, the sooner it's fixed. In game: Game Menu > Support, or the beta's "
    .. "bug button (below). Copy the ready-made report and paste it in.")

  local copy = ns.OptionButton(window, 170, "Copy a bug report", function()
    ns.ShowTextPopup("Bug report for Blizzard (Cmd/Ctrl+C to copy)", ns.SaveBugReportText())
  end)
  copy:SetHeight(26)
  copy:SetPoint("TOPLEFT", 20, y - 10)

  local reporter = ns.OptionButton(window, 210, "Show the bug report button", function()
    if ns.SetIssueReporterHidden then ns.SetIssueReporterHidden(false) end
    ns.Print("the beta's bug report button is back (top-left). Hide it again on the General page.")
  end)
  reporter:SetHeight(26)
  reporter:SetPoint("LEFT", copy, "RIGHT", 10, 0)

  local dontShow = CreateFrame("CheckButton", nil, window)
  dontShow:SetSize(20, 20)
  dontShow:SetPoint("BOTTOMLEFT", 20, 18)
  ns.Skin.Checkbox(dontShow)
  local label = Text(window, 12, DIM)
  label:SetPoint("LEFT", dontShow, "RIGHT", 8, 0)
  label:SetText("Don't show this again")
  window.dontShow = dontShow

  local ok = ns.OptionButton(window, 110, "Got it", function()
    ns.db.saveNoticeSeen = dontShow:GetChecked() and true or nil
    if ns.MacroBackup then pcall(ns.MacroBackup.Write, true) end
    window:Hide()
  end)
  ok:SetHeight(28)
  ok:SetPoint("BOTTOMRIGHT", -20, 16)
  window.ok = ok
  window:Hide()
  return window
end

function ns.ShowSaveNotice()
  if not window then Build() end
  window.dontShow:SetChecked(ns.db and ns.db.saveNoticeSeen and true or false)
  window:Show()
  return window
end

-- At login: only when nothing was read (the bug is live), only for someone
-- who has set ForeverUI up before (a first run has the setup wizard to get
-- through), and not once they've said so.
function ns.MaybeShowSaveNotice()
  if ns.savedRestored ~= false then return false end
  if not (ns.db and ns.db.installed) or ns.db.saveNoticeSeen then return false end
  if ns.installer and ns.installer:IsShown() then return false end
  ns.ShowSaveNotice()
  return true
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function() pcall(ns.MaybeShowSaveNotice) end)
  else
    pcall(ns.MaybeShowSaveNotice)
  end
end)
