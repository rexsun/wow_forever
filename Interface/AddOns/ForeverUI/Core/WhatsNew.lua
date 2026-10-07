local _, ns = ...

-- "What's new": once after an update, the changes since the version you last
-- saw (owner, 28 Sept 2026 -- players kept asking for things that had
-- already shipped). The notes are the changelog itself, carried in the addon
-- as Core/WhatsNewData.lua (tools/make_whatsnew.py).
--
-- Which version you last saw is kept in the macro backup too: on the Forever
-- beta saved settings never come back, and without it the window would
-- open at every login.
--
--   /fui new    open it any time (the last few versions)

local WIDTH, HEIGHT = 560, 460
local MAX_VERSIONS = 5
local ACCENT = { 0.30, 0.76, 1.00 }
local TEXT   = { 0.92, 0.92, 0.94 }
local DIM    = { 0.70, 0.72, 0.78 }

local window

-- "0.4.40" < "0.4.100"; anything unreadable counts as older.
local function Parts(v)
  local out = {}
  for n in tostring(v or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return out
end

function ns.VersionLess(a, b)
  local x, y = Parts(a), Parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p < q end
  end
  return false
end

-- The entries to show someone who last saw `seen`: every version after it,
-- newest first, at most a handful. Nothing seen before (an update from
-- before this window existed): just the newest.
function ns.WhatsNewSince(seen)
  local list, out = ns.WHATS_NEW or {}, {}
  if not seen then
    if list[1] then out[1] = list[1] end
    return out
  end
  for _, entry in ipairs(list) do
    if ns.VersionLess(seen, entry.version) then out[#out + 1] = entry end
    if #out >= MAX_VERSIONS then break end
  end
  return out
end

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

local function MarkSeen()
  if not ns.db then return end
  ns.db.whatsNewSeen = ns.VERSION
  if ns.MacroBackup then pcall(ns.MacroBackup.Write, true) end
end

local function Build()
  window = CreateFrame("Frame", "ForeverUIWhatsNew", UIParent)
  window:SetSize(WIDTH, HEIGHT)
  window:SetPoint("CENTER", 0, 40)
  window:SetFrameStrata("DIALOG")
  window:EnableMouse(true)
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  ns.Skin.Panel(window, { color = { 0.03, 0.04, 0.06, 0.97 } })
  table.insert(UISpecialFrames, "ForeverUIWhatsNew")
  ns.Skin.Header(window, "What's new", function() window:Hide() end)
  -- However it closes (Got it, the X, Escape), it has been seen.
  window:SetScript("OnHide", MarkSeen)

  local scroll = CreateFrame("ScrollFrame", "ForeverUIWhatsNewScroll", window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 18, -40)
  scroll:SetPoint("BOTTOMRIGHT", -36, 54)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 60, 10)
  scroll:SetScrollChild(content)
  window.scroll, window.content, window.lines = scroll, content, {}

  local ok = ns.OptionButton(window, 110, "Got it", function() window:Hide() end)
  ok:SetHeight(28)
  ok:SetPoint("BOTTOMRIGHT", -20, 14)
  window.ok = ok
  local hint = Text(window, 11, DIM)
  hint:SetPoint("BOTTOMLEFT", 20, 22)
  hint:SetText("/fui new shows this again any time.")
  window:Hide()
  return window
end

-- Lay the notes out: a line per version, then each change's title and text.
local function Fill(entries)
  local content, width = window.content, WIDTH - 64
  for _, fs in ipairs(window.lines) do fs:Hide() end
  local used, y = 0, 0
  local function Line(size, color, text, gap)
    used = used + 1
    local fs = window.lines[used]
    if not fs then
      fs = Text(content, size, color)
      window.lines[used] = fs
    end
    local path, _, flags = fs:GetFont()
    if path then fs:SetFont(path, size, flags or "") end
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetWidth(width)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, y - (gap or 0))
    fs:SetText(text)
    fs:Show()
    y = y - (gap or 0) - math.ceil(fs:GetStringHeight() or size)
  end
  for i, entry in ipairs(entries) do
    Line(16, ACCENT, "ForeverUI " .. entry.version .. (i == 1 and entry.version == ns.VERSION and "  (this version)" or ""),
      i == 1 and 0 or 18)
    for _, item in ipairs(entry.items) do
      if item[1] ~= "" then Line(13, TEXT, item[1], 10) end
      if item[2] ~= "" then Line(12, DIM, item[2], item[1] ~= "" and 3 or 10) end
    end
  end
  content:SetHeight(math.max(10, -y + 10))
  if window.scroll.SetVerticalScroll then window.scroll:SetVerticalScroll(0) end
end

-- entries: what to show (default: the last few versions).
function ns.ShowWhatsNew(entries)
  entries = entries or ns.WhatsNewSince("0")
  if #entries == 0 then return nil end
  if not window then Build() end
  local header = window.header and window.header.text
  if header then
    header:SetText(("What's new in ForeverUI %s"):format(ns.VERSION or ""))
  end
  Fill(entries)
  window:Show()
  return window
end

-- At login, once per update: only for someone already set up (a first run
-- has the setup), never over the setup, and after the saving notice if that
-- is up first.
function ns.MaybeShowWhatsNew()
  local db = ns.db
  if not (db and db.installed) or not ns.VERSION or ns.VERSION == "dev" then return false end
  if db.whatsNewSeen == ns.VERSION then return false end
  if ns.installer and ns.installer:IsShown() then return false end
  local entries = ns.WhatsNewSince(db.whatsNewSeen)
  if #entries == 0 then
    MarkSeen()
    return false
  end
  local notice = _G.ForeverUISaveNotice
  if notice and notice:IsShown() then
    if not notice.fuiWhatsNewAfter then
      notice.fuiWhatsNewAfter = true
      notice:HookScript("OnHide", function() pcall(ns.MaybeShowWhatsNew) end)
    end
    return false
  end
  ns.ShowWhatsNew(entries)
  return true
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  if C_Timer and C_Timer.After then
    -- After the saving notice (3 s), so it can wait its turn behind it.
    C_Timer.After(4, function() pcall(ns.MaybeShowWhatsNew) end)
  else
    pcall(ns.MaybeShowWhatsNew)
  end
end)
