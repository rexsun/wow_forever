local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- The frames window's pages for the VuhDo features (docs/vuhdo-parity.md):
--   Healer tools   smart cast, auto-fire, rez announce, your own macros
--   Status         raid marker, the one status icon and its order, labels
--   Panels         extra grids and the target bars           (Panels.lua)
--   Buff Watch     your buffs, who lacks them, click to rebuff (BuffWatch.lua)
-- Built from Options.lua's parts (ns.OptionsParts), so they look and refresh
-- like every other page.

local function Parts() return ns.OptionsParts end

local function AddPage(key, label, icon, build, after)
  local list = ns.FRAME_CATEGORIES
  local at = #list + 1
  if after then
    for i, category in ipairs(list) do
      if category.key == after then at = i + 1 end
    end
  end
  table.insert(list, at, { key = key, label = label })
  ns.FRAME_PAGE_ICONS[key] = icon
  ns.FRAME_PAGE_BUILDERS[key] = build
end

-- A one-line text box that writes a setting when you press Enter or leave it.
function ns.SettingEditBox(page, x, y, width, key, onCommit)
  local P = Parts()
  local box = CreateFrame("EditBox", nil, page)
  box:SetSize(width, 24)
  box:SetPoint("TOPLEFT", x, y)
  box:SetAutoFocus(false)
  box:SetFontObject("GameFontHighlight")
  box:SetTextInsets(6, 6, 0, 0)
  P.Fill(box, P.THEME.inset)
  P.Border(box)
  local function commit(self)
    local text = self:GetText() or ""
    if onCommit then onCommit(text) else ns.SetSetting(key, text) end
  end
  box:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local control = { box = box }
  function control.refresh()
    if key and not box:HasFocus() then box:SetText(tostring(ns.db[key] or "")) end
  end
  P.Controls()["edit:" .. (key or tostring(box))] = control
  return box
end

---------------------------------------------------------------------------
-- Healer tools
---------------------------------------------------------------------------

local TRINKETS = {
  { label = "Off", value = "off" },
  { label = "Top trinket (13)", value = "13" },
  { label = "Bottom trinket (14)", value = "14" },
  { label = "Both trinkets", value = "both" },
}
local ANNOUNCE = {
  { label = "Off", value = "off" },
  { label = "To my group", value = "group" },
}

local macroModifier, macroKey = 1, 1

local function MacroTarget()
  local P = Parts()
  return P.MODIFIERS[macroModifier].prefix .. P.MOUSE_KEYS[macroKey].suffix,
    P.MODIFIERS[macroModifier].label, P.MOUSE_KEYS[macroKey].label
end

local function BuildToolsPage(page)
  local P = Parts()
  local TOP, X = P.TOP, P.CONTENT_X
  P.Card(page, TOP, 132, nil)
  P.Heading(page, TOP, "Smart cast")
  P.Checkbox(page, TOP - 26, "Click a dead player with a heal to resurrect them", "smartRez")
  P.Checkbox(page, TOP - 50, "...in a fight, battle-rez them instead (if you have one)", "smartRezCombat")
  local spells = P.Note(page, "GameFontHighlightSmall")
  spells:SetPoint("TOPLEFT", X + 24, TOP - 72)
  P.Cycler(page, TOP - 96, "Say who you're resurrecting", "rezAnnounce", ANNOUNCE)

  P.Card(page, TOP - 142, 112, nil)
  P.Heading(page, TOP - 142, "Fire first, in the same click")
  P.Cycler(page, TOP - 168, "Use a trinket", "autoTrinket", TRINKETS)
  local fireLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fireLabel:SetPoint("TOPLEFT", X + 6, TOP - 198)
  fireLabel:SetText("Then cast (an instant)")
  fireLabel:SetTextColor(unpack(P.THEME.label))
  ns.SettingEditBox(page, 250, TOP - 192, 220, "autoFireSpell")
  local fireNote = P.Note(page, "GameFontHighlightSmall")
  fireNote:SetPoint("TOPLEFT", X + 6, TOP - 222)
  fireNote:SetText("Only when the click lands on a living friend. Leave empty for none.")

  P.Card(page, TOP - 264, 196, nil)
  P.Heading(page, TOP - 264, "Your own macro on a click")
  local modButton, keyButton
  modButton = P.Button(page, 150, "", function()
    macroModifier = macroModifier % #P.MODIFIERS + 1
    ns.RefreshOptions()
  end)
  modButton:SetPoint("TOPLEFT", X + 6, TOP - 288)
  keyButton = P.Button(page, 150, "", function()
    macroKey = macroKey % #P.MOUSE_KEYS + 1
    ns.RefreshOptions()
  end)
  keyButton:SetPoint("TOPLEFT", X + 162, TOP - 288)
  local current = P.Note(page, "GameFontHighlightSmall")
  current:SetPoint("TOPLEFT", X + 322, TOP - 294)
  current:SetWidth(200)
  current:SetJustifyH("LEFT")

  local edit = CreateFrame("EditBox", nil, page)
  edit:SetMultiLine(true)
  edit:SetSize(500, 72)
  edit:SetPoint("TOPLEFT", X + 6, TOP - 318)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetTextInsets(6, 6, 4, 4)
  edit:SetMaxLetters(1023)
  P.Fill(edit, P.THEME.inset)
  P.Border(edit)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local bind = P.Button(page, 120, "Bind macro", function()
    local key = MacroTarget()
    ns.SetMacroBinding(key, edit:GetText())
    edit:ClearFocus()
    ns.RefreshOptions()
  end)
  bind:SetPoint("TOPLEFT", X + 6, TOP - 396)
  local clear = P.Button(page, 120, "Clear this click", function()
    ns.SetBinding((MacroTarget()), nil, "healer tools")
    edit:SetText("")
    ns.RefreshOptions()
  end)
  clear:SetPoint("TOPLEFT", X + 132, TOP - 396)
  local help = P.Note(page, "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", X + 262, TOP - 400)
  help:SetText("@unit = the player under the mouse.")

  local shownKey
  P.Controls()["tools:page"] = { modButton = modButton, keyButton = keyButton, edit = edit,
    bind = bind, clear = clear, spells = spells, current = current, refresh = function()
    local rez, brez = ns.RezSpell(), ns.BattleRezSpell()
    spells:SetText(("Your resurrection: %s.  Battle rez: %s."):format(rez or "none found", brez or "none"))
    local key, modLabel, keyLabel = MacroTarget()
    modButton:SetText("Hold: " .. modLabel)
    keyButton:SetText("Click: " .. keyLabel)
    local binding = ns.db.bindings and ns.db.bindings[key]
    if binding and binding.kind == "macro" then
      current:SetText("|cff4dc3ffThis click runs your macro.|r")
    elseif binding then
      current:SetText("Now: " .. (ns.SpellLabel(binding) or binding.kind) .. " (replaced if you bind)")
    else
      current:SetText("Nothing on this click yet.")
    end
    -- Load the macro that's there when you land on a different click.
    if shownKey ~= key and not edit:HasFocus() then
      edit:SetText(binding and binding.kind == "macro" and binding.macro or "")
      shownKey = key
    end
  end }
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function PlaceChoices()
  local list = {}
  for _, key in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "OUTLEFT", "OUTRIGHT" }) do
    list[#list + 1] = { label = ns.ROLE_PLACE_LABELS[key] or key, value = key }
  end
  return list
end

local function BuildStatusPage(page)
  local P = Parts()
  local TOP, X = P.TOP, P.CONTENT_X
  local places = PlaceChoices()
  P.Card(page, TOP, 108, nil)
  P.Heading(page, TOP, "Raid marker")
  P.Checkbox(page, TOP - 26, "Show skull, cross, star... on whoever has one", "showRaidMarker")
  P.Cycler(page, TOP - 52, "Where", "raidMarkerPosition", places)
  P.Stepper(page, TOP - 80, "Size", "raidMarkerSize", 8, 32, 1, function(v) return v .. " px" end)

  P.Card(page, TOP - 118, 250, nil)
  P.Heading(page, TOP - 118, "Status icon")
  P.Checkbox(page, TOP - 144, "One icon showing the first of these that applies", "showStatusIcon")
  P.Cycler(page, TOP - 170, "Where", "statusPosition", places)
  P.Stepper(page, TOP - 198, "Size", "statusSize", 10, 36, 1, function(v) return v .. " px" end)
  local rows = {}
  for i = 1, 5 do
    local y = TOP - 226 - (i - 1) * 26
    local row = {}
    row.toggle = P.Button(page, 220, "", function()
      local kind = ns.db.statusOrder[i]
      if kind then ns.ToggleStatus(kind) end
    end)
    row.toggle:SetPoint("TOPLEFT", X + 6, y)
    row.up = P.Button(page, 26, "^", function() ns.MoveStatus(i, -1) end)
    row.up:SetPoint("TOPLEFT", X + 232, y)
    row.down = P.Button(page, 26, "v", function() ns.MoveStatus(i, 1) end)
    row.down:SetPoint("TOPLEFT", X + 262, y)
    rows[i] = row
  end
  P.Controls()["status:order"] = { rows = rows, refresh = function()
    local order = ns.db.statusOrder or ns.DEFAULTS.statusOrder
    local show = ns.db.statusShow or ns.DEFAULTS.statusShow
    for i, row in ipairs(rows) do
      local kind = order[i]
      row.toggle:SetText(kind and (("%d. %s: %s"):format(i, ns.STATUS_KINDS[kind] or kind,
        show[kind] and "|cff66ff66on|r" or "|cff999999off|r")) or "")
      row.up:SetShown(i > 1)
      row.down:SetShown(i < #order)
    end
  end }

  P.Card(page, TOP - 378, 60, nil)
  P.Heading(page, TOP - 378, "Raid groups")
  P.Checkbox(page, TOP - 404, "\"Group 3\" over each raid group", "groupLabels")
end

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local pickGroup, pickClass = 1, 5

local function ClassName(token)
  local names = LOCALIZED_CLASS_NAMES_MALE
  return (names and names[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

local function BuildPanelsPage(page)
  local P = Parts()
  local TOP, X = P.TOP, P.CONTENT_X
  local function Added(index)
    if not index then
      ns.Print(#ns.PanelList() >= ns.MAX_PANELS and ("that's the most panels there can be (%d)."):format(ns.MAX_PANELS)
        or "nothing to add - fill it in first.")
    end
  end
  P.Card(page, TOP, 146, nil)
  P.Heading(page, TOP, "Add a panel")
  local tanks = P.Button(page, 150, "+ Tanks", function() Added(ns.AddPanel("tanks")) end)
  tanks:SetPoint("TOPLEFT", X + 6, TOP - 26)
  local healers = P.Button(page, 150, "+ Healers", function() Added(ns.AddPanel("healers")) end)
  healers:SetPoint("TOPLEFT", X + 162, TOP - 26)
  local targets = P.Button(page, 200, "+ Target, their target, focus", function() Added(ns.AddPanel("targets")) end)
  targets:SetPoint("TOPLEFT", X + 318, TOP - 26)

  local groupPick = P.Button(page, 100, "", function() pickGroup = pickGroup % 8 + 1; ns.RefreshOptions() end)
  groupPick:SetPoint("TOPLEFT", X + 6, TOP - 54)
  local addGroup = P.Button(page, 110, "+ Add group", function()
    Added(ns.AddPanel("group", tostring(pickGroup)))
  end)
  addGroup:SetPoint("TOPLEFT", X + 110, TOP - 54)
  local classPick = P.Button(page, 110, "", function() pickClass = pickClass % #CLASSES + 1; ns.RefreshOptions() end)
  classPick:SetPoint("TOPLEFT", X + 250, TOP - 54)
  local addClass = P.Button(page, 110, "+ Add class", function()
    Added(ns.AddPanel("class", CLASSES[pickClass]))
  end)
  addClass:SetPoint("TOPLEFT", X + 364, TOP - 54)

  local names = CreateFrame("EditBox", nil, page)
  names:SetSize(300, 24)
  names:SetPoint("TOPLEFT", X + 6, TOP - 82)
  names:SetAutoFocus(false)
  names:SetFontObject("GameFontHighlight")
  names:SetTextInsets(6, 6, 0, 0)
  P.Fill(names, P.THEME.inset)
  P.Border(names)
  names:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local addNames = P.Button(page, 190, "+ Add these players", function()
    local index = ns.AddPanel("names", names:GetText() or "")
    Added(index)
    if index then names:SetText("") end
    names:ClearFocus()
  end)
  addNames:SetPoint("TOPLEFT", X + 312, TOP - 82)
  local note = P.Note(page, "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", X + 6, TOP - 112)
  note:SetText("Names separated by commas. Move frames (bottom of the window) to drag the panels.")

  P.Card(page, TOP - 156, 298, nil)
  P.Heading(page, TOP - 156, "Your panels")
  local rows = {}
  for i = 1, ns.MAX_PANELS do
    local y = TOP - 182 - (i - 1) * 26
    local row = {}
    row.text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", X + 6, y - 5)
    row.text:SetWidth(250)
    row.text:SetJustifyH("LEFT")
    row.shown = P.Button(page, 80, "", function()
      local entry = ns.PanelList()[i]
      if entry then ns.SetPanelField(i, "shown", entry.shown == false) end
    end)
    row.shown:SetPoint("TOPLEFT", X + 262, y)
    row.dir = P.Button(page, 90, "", function()
      local entry = ns.PanelList()[i]
      if entry then ns.SetPanelField(i, "horizontal", not entry.horizontal) end
    end)
    row.dir:SetPoint("TOPLEFT", X + 346, y)
    row.remove = P.Button(page, 26, "x", function() ns.RemovePanel(i) end)
    row.remove:SetPoint("TOPLEFT", X + 440, y)
    rows[i] = row
  end
  local empty = P.Note(page, "GameFontHighlightSmall")
  empty:SetPoint("TOPLEFT", X + 6, TOP - 186)
  empty:SetText("None yet. Add one above: a tanks panel beside your bars is the usual start.")

  P.Controls()["panels:page"] = { rows = rows, tanks = tanks, healers = healers, targets = targets,
    groupPick = groupPick, addGroup = addGroup, classPick = classPick, addClass = addClass,
    names = names, addNames = addNames, refresh = function()
    groupPick:SetText("Group " .. pickGroup)
    classPick:SetText(ClassName(CLASSES[pickClass]))
    local list = ns.PanelList()
    empty:SetShown(#list == 0)
    for i, row in ipairs(rows) do
      local entry = list[i]
      row.text:SetShown(entry ~= nil)
      row.shown:SetShown(entry ~= nil)
      row.dir:SetShown(entry ~= nil)
      row.remove:SetShown(entry ~= nil)
      if entry then
        row.text:SetText(entry.name or ns.PanelLabel(entry))
        row.shown:SetText(entry.shown == false and "Show" or "Hide")
        row.dir:SetText(entry.horizontal and "In a row" or "In a column")
      end
    end
  end }
end

---------------------------------------------------------------------------
-- Buff Watch
---------------------------------------------------------------------------

local function BuildBuffsPage(page)
  local P = Parts()
  local TOP, X = P.TOP, P.CONTENT_X
  P.Card(page, TOP, 150, nil)
  P.Heading(page, TOP, "Buff Watch")
  P.Checkbox(page, TOP - 26, "Show the Buff Watch panel: who's missing your buffs, click to rebuff", "showBuffWatch")
  P.Stepper(page, TOP - 54, "\"Running out\" under", "buffWatchSoon", 10, 600, 10, function(v) return v .. "s" end)
  P.Stepper(page, TOP - 82, "Group version when this many need it", "buffWatchGroupAt", 2, 10, 1, P.Plain)
  local note = P.Note(page, "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", X + 6, TOP - 110)
  note:SetWidth(520)
  note:SetJustifyH("LEFT")
  note:SetText("Red: someone is missing it. Yellow: someone's runs out soon. Green: everyone has it. "
    .. "It holds still in a fight - the game hides buffs until the fight ends.")

  P.Card(page, TOP - 160, 196, nil)
  P.Heading(page, TOP - 160, "Your buffs")
  local rows = {}
  for i = 1, 6 do
    local row = P.Button(page, 330, "", function()
      local choice = rows[i].choice
      if choice then ns.SetGroupBuff(choice.entry.spell, not choice.on) end
    end)
    row:SetPoint("TOPLEFT", X + 6, TOP - 186 - (i - 1) * 26)
    rows[i] = row
  end
  local none = P.Note(page, "GameFontHighlightSmall")
  none:SetPoint("TOPLEFT", X + 6, TOP - 190)
  none:SetText("Your class has no group buffs to watch.")
  P.Controls()["buffs:page"] = { rows = rows, refresh = function()
    local choices = ns.GroupBuffChoices()
    none:SetShown(#choices == 0)
    for i, row in ipairs(rows) do
      local choice = choices[i]
      row.choice = choice
      row:SetShown(choice ~= nil)
      if choice then
        local state = not choice.known and "|cff999999not learned|r"
          or (choice.on and "|cff66ff66watched|r" or "|cff999999off|r")
        row:SetText(("%s: %s"):format(choice.label, state))
      end
    end
  end }
end

---------------------------------------------------------------------------
-- Looks
---------------------------------------------------------------------------

-- A colour swatch with a label. `get` returns r, g, b; `set` takes them.
function ns.SwatchControl(page, x, y, label, get, set, name)
  local P = Parts()
  local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", x, y)
  text:SetText(label)
  text:SetTextColor(unpack(P.THEME.label))
  local swatch = CreateFrame("Button", nil, page)
  swatch:SetSize(40, 16)
  swatch:SetPoint("TOPLEFT", x + 110, y + 2)
  P.Fill(swatch, { 0, 0, 0, 1 })
  P.Border(swatch)
  local fill = swatch:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  swatch:SetScript("OnClick", function()
    local r, g, b = get()
    ns.OpenColorPicker(r or 1, g or 1, b or 1, set)
  end)
  local control = { swatch = swatch, fill = fill }
  function control.refresh()
    local r, g, b = get()
    fill:SetColorTexture(r or 1, g or 1, b or 1)
  end
  P.Controls()["swatch:" .. name] = control
  return control
end

local function SettingColor(key, fallback)
  return function()
    local c = ns.db[key]
    if type(c) ~= "table" then c = fallback end
    return c[1], c[2], c[3]
  end, function(r, g, b) ns.SetSetting(key, { r, g, b }) end
end

local function BuildLooksPage(page)
  local P = Parts()
  local TOP, X = P.TOP, P.CONTENT_X
  P.Card(page, TOP, 108, nil)
  P.Heading(page, TOP, "HoT bars")
  P.Checkbox(page, TOP - 26, "A shrinking bar per HoT along the bottom of the frame", "hotBars")
  P.Stepper(page, TOP - 52, "How many", "hotBarCount", 1, 5, 1, P.Plain)
  P.Stepper(page, TOP - 78, "Thickness", "hotBarHeight", 1, 6, 1, function(v) return v .. " px" end)
  local hotGet, hotSet = SettingColor("hotBarColor", { 0.35, 0.95, 0.45 })
  ns.SwatchControl(page, X + 410, TOP - 26, "Colour", hotGet, hotSet, "hotBar")

  local places = {}
  for _, key in ipairs({ "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT", "CENTER" }) do
    places[#places + 1] = { label = ns.DEBUFF_PLACES[key], value = key }
  end
  P.Card(page, TOP - 118, 108, nil)
  P.Heading(page, TOP - 118, "Debuff icons (drawn by the game, even in combat)")
  P.Stepper(page, TOP - 144, "How many", "debuffIconCount", 1, 5, 1, P.Plain)
  P.Stepper(page, TOP - 170, "Size", "debuffIconSize", 8, 24, 1, function(v) return v .. " px" end)
  P.Cycler(page, TOP - 196, "Where", "debuffIconPosition", places)
  P.Checkbox(page, TOP - 144, "Every debuff, not only ones I can dispel", "debuffShowAll", { x = X + 400 })

  P.Card(page, TOP - 236, 82, nil)
  P.Heading(page, TOP - 236, "Colours")
  P.Checkbox(page, TOP - 262, "Dead players' bars in a colour", "colorDead")
  local deadGet, deadSet = SettingColor("deadColor", { 0.45, 0.08, 0.08 })
  ns.SwatchControl(page, X + 250, TOP - 262, "Dead", deadGet, deadSet, "dead")
  local mineGet, mineSet = SettingColor("incomingMineColor", ns.PREDICT_MINE)
  local othersGet, othersSet = SettingColor("incomingOthersColor", ns.PREDICT_OTHERS)
  ns.SwatchControl(page, X + 6, TOP - 290, "My heals coming", mineGet, mineSet, "incomingMine")
  ns.SwatchControl(page, X + 250, TOP - 290, "Others' heals", othersGet, othersSet, "incomingOthers")
  local resetIncoming = P.Button(page, 70, "Default", function()
    ns.SetSetting("incomingMineColor", false)
    ns.SetSetting("incomingOthersColor", false)
  end)
  resetIncoming:SetPoint("TOPLEFT", X + 440, TOP - 288)

  P.Card(page, TOP - 328, 118, nil)
  P.Heading(page, TOP - 328, "Class colours")
  for i, class in ipairs(ns.CLASS_LIST) do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local label = (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
    ns.SwatchControl(page, X + 6 + col * 175, TOP - 354 - row * 24, label,
      function() return ns.ClassColor(class) end,
      function(r, g, b) ns.SetSetting("classColor_" .. class, { r, g, b }) end, "class" .. class)
  end
  local resetClasses = P.Button(page, 150, "Game's class colours", function()
    ns.ResetClassColors()
    ns.RefreshOptions()
  end)
  resetClasses:SetPoint("TOPLEFT", X + 6, TOP - 428)
  P.Controls()["looks:page"] = { resetClasses = resetClasses, resetIncoming = resetIncoming }
end

AddPage("tools", "Healer tools", "spells", BuildToolsPage, "bindings")
AddPage("status", "Status", "eye", BuildStatusPage)
AddPage("panels", "Panels", "framemgmt", BuildPanelsPage)
AddPage("buffs", "Buff Watch", "star", BuildBuffsPage)
AddPage("looks", "Looks", "appearance", BuildLooksPage)
