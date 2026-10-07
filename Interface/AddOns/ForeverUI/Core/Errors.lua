local _, ns = ...

-- ForeverUI's own error book.
--
-- Someone else's game can't send you a report over the wire -- the game
-- forbids addons any network. So instead ForeverUI keeps the errors it causes
-- in the saved variables, tidied and de-duplicated, and shows them in a
-- window you can select and copy from. Ask a reporter to run /fui errors and
-- paste what's there (Discord, a CurseForge comment, wherever).
--
-- It watches by CHAINING onto whatever error handler is already installed --
-- BugSack, the red box, nothing -- so it never takes anyone else's place, and
-- an error it records still reaches them.

ns.Errors = ns.Errors or {}
local Errors = ns.Errors

local MAX = 50

local function Log()
  ForeverUIDB = ForeverUIDB or {}
  ForeverUIDB.errors = ForeverUIDB.errors or {}
  return ForeverUIDB.errors
end
Errors.Log = Log

-- Ours if ForeverUI is anywhere in the message -- our own files, or Blizzard
-- code the game says WE tainted ("tainted by 'ForeverUI'"). Other addons'
-- errors are left for their own authors.
local function Ours(msg)
  return type(msg) == "string" and msg:find("ForeverUI", 1, true) ~= nil
end
Errors.Ours = Ours

local function Now()
  return (date and date("%Y-%m-%d %H:%M:%S")) or "?"
end

-- Keep the important line, drop the noise, so duplicates from the same fault
-- collapse to one entry however deep the stack was when it fired.
local function Record(msg, stack)
  if not Ours(msg) then
    return false
  end
  local log = Log()
  for _, entry in ipairs(log) do
    if entry.msg == msg then
      entry.count = (entry.count or 1) + 1
      entry.last = Now()
      return true
    end
  end
  log[#log + 1] = {
    msg = msg,
    stack = stack or (debugstack and debugstack(3, 20, 0)) or "",
    count = 1,
    first = Now(),
    last = Now(),
    version = ns.VERSION,
  }
  while #log > MAX do
    table.remove(log, 1)
  end
  return true
end
Errors.Record = Record

local installed = false
function Errors.Install()
  if installed or type(seterrorhandler) ~= "function" then
    return false
  end
  installed = true
  local previous = geterrorhandler and geterrorhandler()
  seterrorhandler(function(err, ...)
    pcall(Record, err)
    if previous then
      return previous(err, ...)
    end
  end)
  return true
end

function Errors.Count()
  return #Log()
end

function Errors.Clear()
  ns.Wipe(Log())
  return true
end

-- The whole book as plain text, newest first, ready to copy.
function Errors.Text()
  local log = Log()
  if #log == 0 then
    return "No ForeverUI errors recorded. Nice."
  end
  local parts = {}
  for i = #log, 1, -1 do
    local e = log[i]
    parts[#parts + 1] = ("[v%s  x%d  %s]\n%s\n%s"):format(
      e.version or "?", e.count or 1, e.last or "?", e.msg or "",
      (e.stack or ""):gsub("^%s+", ""))
  end
  return table.concat(parts, "\n\n" .. ("-"):rep(48) .. "\n\n")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local frame
local function Build()
  frame = CreateFrame("Frame", "ForeverUIErrors", UIParent)
  frame:SetSize(620, 440)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  ns.Skin.Panel(frame, { color = { 0.06, 0.06, 0.08, 0.97 } })
  ns.Skin.Header(frame, "ForeverUI errors", function() frame:Hide() end)

  local hint = frame:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(hint, "general")
  hint:SetPoint("BOTTOMLEFT", 16, 12)
  hint:SetPoint("BOTTOMRIGHT", -16, 12)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(unpack(ns.Colors.ui.textDim))
  hint:SetText("Select all (Cmd/Ctrl+A), copy (Cmd/Ctrl+C) and paste it in a comment on ForeverUI's CurseForge page. /fui errors clear empties this.")

  local scroll = CreateFrame("ScrollFrame", "ForeverUIErrorsScroll", frame,
    "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -40)
  scroll:SetPoint("BOTTOMRIGHT", -34, 40)

  local edit = CreateFrame("EditBox", nil, scroll)
  if edit.SetMultiLine then edit:SetMultiLine(true) end
  if edit.SetAutoFocus then edit:SetAutoFocus(false) end
  if edit.SetWidth then edit:SetWidth(560) end
  ns.Media.SetFont(edit, "general")
  if edit.SetTextColor then edit:SetTextColor(unpack(ns.Colors.ui.text)) end
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  if scroll.SetScrollChild then scroll:SetScrollChild(edit) end
  frame.edit = edit

  if UISpecialFrames then
    table.insert(UISpecialFrames, "ForeverUIErrors")
  end
  Errors.frame = frame
  return frame
end

function Errors.Open()
  if not frame then
    Build()
  end
  frame.edit:SetText(Errors.Text())
  frame:Show()
  if frame.edit.HighlightText then frame.edit:HighlightText() end
  if frame.edit.SetFocus then frame.edit:SetFocus() end
  return frame
end
