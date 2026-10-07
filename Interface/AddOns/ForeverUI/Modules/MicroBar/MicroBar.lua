local _, ns = ...

-- The micro bar: one flat row of the windows you keep calling up --
-- character, spells, talents, professions, quests, map, social, achievements, bags,
-- menu -- in the UI's own style, where Blizzard's row of gold micro
-- buttons used to be.
--
-- HOW THE CLICK GETS THERE, and why it is not a plain function call.
--
-- Calling ToggleCharacter() from our own OnClick works on an ordinary
-- client and is what every other micro bar does. It does not work here.
-- Forever hands out health and power as secret values, and Blizzard's own
-- code is allowed to compare them only while the execution is untainted.
-- The moment our click calls into the character frame, that whole path is
-- tainted, and Blizzard's status bar text dies on a comparison it makes
-- every time the panel opens:
--
--   TextStatusBar.lua:110: attempt to compare a secret number value
--   (execution tainted by 'ForeverUIApp')
--
-- Worse, the taint sticks to the panel manager, so afterwards even pressing
-- C -- nothing to do with us -- throws the same error.
--
-- The textbook answer is a secure button forwarding the click to Blizzard's
-- own micro button through the "clickbutton" attribute: the game runs its own
-- button in its own untainted path and we are never on the stack.
--
-- AT FIRST IT DID NOT WORK ON THIS CLIENT, and the way it failed is worth writing
-- down. Every button wired that way went dead -- Character, Spellbook,
-- Talents, Quest Log, Achievements and the game menu. The three that kept
-- working were Map, Social and Bags, and those are exactly the three with no
-- Blizzard micro button of that name to forward to, so they fell through to
-- the plain call. The target was shown, mouse-enabled, enabled and correctly
-- named in the attribute; the click simply never arrived.
--
-- So for a while the forwarding was kept, off, behind the switch below, and
-- every button made the plain call: a window that opens and writes a
-- complaint to the error log beat a button that does nothing at all.
--
-- WHY IT FAILED, found 22 September 2026 against the client's own
-- SecureTemplates.lua (forever branch): the game's "cast on key down" option
-- (CVar ActionButtonUseKeyDown, on by default) makes a secure button act on
-- the PRESS, and these buttons only listen for the release ("AnyUp"). The
-- press never reached them, so nothing was ever forwarded. Each button now
-- says useOnKeyDown = false -- act on the release it does hear -- and the
-- forwarding is on. Blizzard's own micro button opens the window, untainted,
-- and the secret-value error from the plain call is gone.
local FORWARD_CLICKS = true

local module = ns.RegisterModule({
  name = "MicroBar",
  title = "Micro bar",
})

module.defaults = {
  shown = true,          -- the switch: off hides the bar, on brings it back
  -- Width is a MINIMUM now: a tile is as wide as its own glyph, name and key,
  -- so the row reads as a row of labels rather than a grid of equal boxes.
  buttonWidth = 54,
  buttonHeight = 26,
  spacing = 5,
  vertical = false,
  showKeys = true,       -- "Char | C" rather than just "Char"
  -- The look. The blue edge and its glow are the house style, but they are
  -- the first thing people want gone, so both are switches with a colour.
  showBorder = true,
  showGlow = true,
  -- No colour of its own: the tiles follow the UI's border colour (General >
  -- Border colour) until someone picks one here.
  borderColor = nil,
  fillColor = { 0.04, 0.07, 0.12, 0.96 },
  textColor = { 0.93, 0.96, 1.00, 1 },
  -- Staghelm on CurseForge, 1 Oct 2026: "a fade on the micro bar so it only
  -- shows when i hover over it ... trying to go for a minimal UI".
  mouseover = false,
  fadedAlpha = 0,        -- percent, how much of it shows while the mouse is away
  -- mockupDone is deliberately NOT here. Defaults are merged into a profile
  -- before OnInit runs, so a marker listed here would already be true by the
  -- time the nudge below looked at it, and the nudge would never fire for
  -- the profiles it exists for. It is set in OnInit and nowhere else.
}

module.options = {
  { type = "heading", label = "Micro bar" },
  { type = "note", label = "The windows you call up most -- character, spells, talents, quests, map, social, achievements, bags, menu -- as one flat row. Drag it with Move frames. /fui micro toggles it too." },
  { type = "checkbox", key = "shown", label = "Show the micro bar", desc = "Off hides the row; the keys still work." },
  { type = "checkbox", key = "hideMicroMenu", moduleName = "ActionBars", reload = true,
    label = "Hide Blizzard's micro menu", desc = "Action Bars does the hiding, so it needs Action Bars on." },
  { type = "stepper", key = "buttonWidth", label = "Button width", min = 36, max = 120, step = 2 },
  { type = "stepper", key = "buttonHeight", label = "Button height", min = 14, max = 40, step = 1 },
  { type = "stepper", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1 },
  { type = "checkbox", key = "vertical", label = "Stack it vertically" },
  { type = "checkbox", key = "showKeys", label = "Show the key beside each name" },
  { type = "checkbox", key = "mouseover", label = "Only show it when the mouse is over it",
    desc = "Fades out when you move away and back in when you point at it. Still clickable while faded.",
    apply = function() local m = ns.GetModule("MicroBar"); if m and m.ApplyFade then m.ApplyFade() end end },
  { type = "stepper", key = "fadedAlpha", label = "While faded, show", min = 0, max = 90, step = 10,
    format = function(v) return ("%d%%"):format(v) end,
    apply = function() local m = ns.GetModule("MicroBar"); if m and m.ApplyFade then m.ApplyFade() end end },
  { type = "heading", label = "How it looks" },
  { type = "checkbox", key = "showBorder", label = "Border around each tile",
    desc = "Off leaves the plain tile with no edge." },
  { type = "color", key = "borderColor", label = "Border colour" },
  { type = "checkbox", key = "showGlow", label = "Glow behind each tile" },
  { type = "color", key = "fillColor", label = "Tile colour" },
  { type = "color", key = "textColor", label = "Text colour" },
}

local function Settings()
  return ns.db.modules.MicroBar
end

-- Profiles written before the border colour was a setting carry the shipped
-- blue. That is not a choice anyone made, so it is cleared and the tiles
-- follow the UI's border colour instead.
local SHIPPED_EDGE = { 0.18, 0.48, 0.78, 1 }
local function DropShippedEdge()
  local set = Settings()
  local c = set and set.borderColor
  if type(c) == "table" and c[1] == SHIPPED_EDGE[1] and c[2] == SHIPPED_EDGE[2] and c[3] == SHIPPED_EDGE[3] then
    set.borderColor = nil
  end
end

-- A tile with no Blizzard button to forward to says which key opens its
-- window instead of opening it (see ns.Skin.OpenHint for why). Bags aren't
-- a panel-manager window, so that one is still opened directly.
local function First(...)
  for i = 1, select("#", ...) do
    local fn = select(i, ...)
    if type(fn) == "function" then
      return pcall(fn)
    end
  end
  return false
end

local BUTTONS = {
  { key = "C", label = "Char", tip = "Character", icon = "char", micro = "CharacterMicroButton",
    click = function() return ns.Skin.OpenHint("character") end },
  { key = "P", label = "Spells", tip = "Spellbook", icon = "bookopen", micro = "SpellbookMicroButton",
    click = function() return ns.Skin.OpenHint("spellbook") end },
  { key = "N", label = "Talents", tip = "Talents", icon = "talents", micro = "TalentMicroButton",
    click = function() return ns.Skin.OpenHint("talents") end },
  -- K: the professions window (owner, 25 Sept 2026). Forever's button is
  -- ProfessionMicroButton and K runs ToggleProfessionsBook (binding
  -- TOGGLEPROFESSIONBOOK). The hammer glyph is ChatGPT's, made to match the
  -- Icons8 set (docs/art/professions-glyph.png).
  { key = "K", label = "Professions", tip = "Professions", icon = "professions", micro = "ProfessionMicroButton",
    click = function() return ns.Skin.OpenHint("professions") end },
  { key = "L", label = "Quests", tip = "Quest log", icon = "scroll", micro = "QuestLogMicroButton",
    click = function() return ns.Skin.OpenHint("questlog") end },
  -- M: no map micro button on Forever; the minimap's zone name opens it
  -- (ns.Skin.OPENERS), so the click is handed to that.
  { key = "M", label = "Map", tip = "World map", icon = "map", opener = "map",
    click = function() return ns.Skin.OpenHint("map") end },
  -- O: Forever has no Social micro button, and the friends button by the
  -- chat (QuickJoinToastButton) belongs to Blizzard_QuickJoin, which only
  -- loads on retail. So with nothing to hand the click to, every click only
  -- said "press O" (owner, 2 Oct 2026). The tile is a secure macro button
  -- instead, running the game's own /friends, which opens the list in the
  -- game's secure path. Not "/run ToggleFriendsFrame()": a /run script is
  -- insecure code, and opening a window from it taints the panel manager --
  -- the next C then fails, as Bags did. /friends with a PLAYER targeted adds
  -- or removes them as a friend, so then the macro stops first and the tile
  -- says to press O instead (macroHint).
  { key = "O", label = "Social", tip = "Friends and guild", icon = "social", micro = "SocialsMicroButton",
    macro = "/stopmacro [@target,player]\n/friends",
    macroHint = function()
      local ok, isPlayer = pcall(UnitIsPlayer, "target")
      return ok and ns.Secrets.Bool(isPlayer, false) and ns.Skin.OpenHint("friends")
    end,
    click = function() return ns.Skin.OpenHint("friends") end },
  -- J: the guild window (owner, 25 Sept 2026). Forever keeps retail's
  -- Guild & Communities window behind GuildMicroButton, and J runs
  -- ToggleGuildFrame; older clients have the guild as a tab of Social. The
  -- shield glyph reads as a guild crest.
  { key = "J", label = "Guild", tip = "Guild & Communities", icon = "roles", micro = "GuildMicroButton",
    click = function() return ns.Skin.OpenHint("guild") end },
  -- Forever's button is LFDMicroButton; LFGMicroButton is the older name.
  { key = "I", label = "Group", tip = "Looking for Group", icon = "lfg", micro = { "LFDMicroButton", "LFGMicroButton" },
    click = function() return ns.Skin.OpenHint("lfg") end },
  -- Y on Forever is the Legacy progress track (TOGGLELEGACYSYSTEM), not the
  -- old achievement window -- that one is left over from retail and throws
  -- "compare nil with number" in AchievementShield_SetPoints when opened.
  -- Forwarded to LegacyMicroButton (29 Sept 2026). Blizzard keeps that
  -- button disabled only until a character has Legacy progress (the forever
  -- branch, MainMenuBarMicroButtons.lua), and a disabled button ignores the
  -- click -- so then the tile says to press Y. Never ToggleLegacySystemUI
  -- from here: that leaves the panel manager tainted and the NEXT window
  -- opened (the character sheet) is what dies.
  { key = "Y", label = "Legacy", tip = "Legacy progress", icon = "achieve", opener = "legacy",
    click = function() return ns.Skin.OpenHint("legacy") end },
  { key = "B", label = "Bags", tip = "All bags", icon = "bags",
    -- ToggleBackpack, as the B key does: on Forever ToggleAllBags also opens
    -- the reagent bag in a window of its own beside the combined bag, which
    -- ForeverUI's bag window already shows (goldfish117 on CurseForge, 30
    -- Sept 2026: "it opens the FUI bag, as well as the blizzard UI for my
    -- reagent bag. This doesn't happen when hitting the hotkey").
    -- Forwarded to Blizzard's own backpack button (its click toggles the
    -- backpack, as B does), not called: ToggleBackpack from here opened and
    -- closed Blizzard's bags in ForeverUI's name, and the next Escape closed
    -- the bags and then the character sheet tainted -- after which every C
    -- threw TextStatusBar.lua:110 (BAP2521 on CurseForge, 2 Oct 2026). The
    -- plain call stays only for a client without that button.
    micro = "MainMenuBarBackpackButton",
    click = function() return First(ToggleBackpack, ToggleAllBags) end },
  -- Overlaid, not forwarded or called: Blizzard blocks addons from opening
  -- the game menu ("ForeverUICore has been blocked..."), and its own button
  -- opens it only "if self:IsMouseOver()". So the real MainMenuMicroButton
  -- sits invisibly on top of this tile and takes the click itself.
  { key = "Esc", label = "Menu", tip = "Game menu", icon = "gear", overlay = "MainMenuMicroButton",
    click = function() return ns.Skin.OpenHint("menu") end },
}
module.BUTTONS = BUTTONS

local bar
local buttons = {}
module.buttons = buttons

-- The look: a dark navy tile with a blue edge and a soft blue glow outside
-- it, the glyph on the left, the name, a hairline, then the key in blue.
-- The house colours: the defaults a setting falls back to, and what the
-- tiles are built with before Paint runs.
local FILL       = { 0.04, 0.07, 0.12, 0.96 }
local EDGE       = { 0.18, 0.48, 0.78, 1 }
local GLOW       = { 0.20, 0.60, 0.95, 0.30 }
local KEY_COLOR  = { 0.42, 0.72, 0.98 }
local LABEL      = { 0.93, 0.96, 1.00 }

local PAD_X, ICON_GAP, KEY_GAP = 9, 8, 9

-- Hover lifts the fill, brightens the edge and widens the glow, which is the
-- only state the row has. Nothing here is a spell, so there is no "active".
-- A colour from the settings, falling back to the house one. Hovering lifts
-- whatever colour is set rather than jumping back to blue.
local function Lift(c, by)
  return { math.min(1, c[1] + by), math.min(1, c[2] + by), math.min(1, c[3] + by), c[4] or 1 }
end

local function Colour(key, fallback)
  local set = Settings and Settings()
  local c = set and set[key]
  if type(c) == "table" and #c >= 3 then
    return c
  end
  return fallback
end

local function Paint(button)
  local hovered = button.hovered
  local s = Settings and Settings() or {}
  local fill = Colour("fillColor", FILL)
  local edge = Colour("borderColor", ns.Colors.ui.accent or EDGE)
  local text = Colour("textColor", LABEL)
  ns.Skin.SetPanelColor(button, hovered and Lift(fill, 0.05) or fill)
  if s.showBorder == false then
    ns.Skin.SetBorderColor(button, { 0, 0, 0, 0 })
  else
    ns.Skin.SetBorderColor(button, hovered and Lift(edge, 0.25) or edge)
  end
  if button.glow then
    if s.showGlow == false then
      ns.Skin.SetBorderColor(button.glow, { 0, 0, 0, 0 })
    else
      local glow = { edge[1], edge[2], edge[3], hovered and 0.55 or 0.30 }
      ns.Skin.SetBorderColor(button.glow, glow)
    end
  end
  button.glyph:SetVertexColor(unpack(hovered and Lift(edge, 0.25) or edge))
  if button.label then button.label:SetTextColor(text[1], text[2], text[3]) end
  -- The key letter is the accent too, a shade brighter so it still reads as
  -- the key rather than part of the edge.
  if button.keyText then
    local key = Lift(edge, 0.18)
    button.keyText:SetTextColor(key[1], key[2], key[3])
  end
  if button.divider then
    button.divider:SetColorTexture(edge[1], edge[2], edge[3], 0.5)
  end
end
module.Paint = Paint

-- How wide a tile has to be to hold what is in it. The mock-up's tiles are
-- each as wide as their own label rather than all one width, so a long name
-- is never squeezed and a short one never floats in space.
local function Measure(button, settings)
  local width = PAD_X + button.glyph:GetWidth() + ICON_GAP
    + math.ceil(button.label:GetStringWidth() or 0)
  if settings.showKeys then
    width = width + KEY_GAP + 1 + KEY_GAP + math.ceil(button.keyText:GetStringWidth() or 0)
  end
  return math.max(settings.buttonWidth, width + PAD_X)
end

local function Layout()
  local settings = Settings()
  local h, gap = settings.buttonHeight, settings.spacing
  local iconSize = math.max(10, math.min(h - 6, 16))

  local widths, total = {}, 0
  for i, button in ipairs(buttons) do
    local entry = BUTTONS[i]
    button.label:SetText(entry.label)
    button.keyText:SetText(entry.key)
    button.glyph:SetSize(iconSize, iconSize)
    button.keyText:SetShown(settings.showKeys)
    button.divider:SetShown(settings.showKeys)
    widths[i] = Measure(button, settings)
    total = total + widths[i]
  end

  local widest = settings.buttonWidth
  for _, w in ipairs(widths) do
    if w > widest then widest = w end
  end

  local n = #buttons
  if settings.vertical then
    -- Stacked, every tile the same width, or the column would look ragged.
    bar:SetSize(widest, n * h + (n - 1) * gap)
  else
    bar:SetSize(total + (n - 1) * gap, h)
  end

  local x = 0
  for i, button in ipairs(buttons) do
    local w = settings.vertical and widest or widths[i]
    button:SetSize(w, h)
    button:ClearAllPoints()
    if settings.vertical then
      button:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -((i - 1) * (h + gap)))
    else
      button:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
      x = x + w + gap
    end
    button.divider:SetHeight(math.max(8, h - 10))
    Paint(button)
  end
  ns.UpdateMoverSize("microbar", bar:GetWidth(), bar:GetHeight())
end

local function Build()
  if bar then
    return
  end
  bar = CreateFrame("Frame", "ForeverUIMicroBar", UIParent)
  module.bar = bar
  for i, entry in ipairs(BUTTONS) do
    -- A secure button, so the click can be handed to Blizzard's own micro
    -- button rather than routed through our Lua. See the note at the top.
    local button = CreateFrame("Button", "ForeverUIMicroBar" .. entry.label, bar,
      "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")

    -- The glow first, so it sits behind the tile: a second border on a frame
    -- two pixels bigger all round. A real soft glow would need artwork; two
    -- edges of blue at low alpha read the same at this size.
    local glow = CreateFrame("Frame", nil, button)
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    ns.Skin.Border(glow, GLOW)
    button.glow = glow

    ns.Skin.Panel(button, { color = FILL, borderColor = EDGE, square = true })

    button.glyph = ns.Skin.Icon(button, entry.icon, 16, KEY_COLOR, "OVERLAY")
    button.glyph:SetPoint("LEFT", PAD_X, 0)

    button.label = button:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(button.label, "general")
    button.label:SetPoint("LEFT", button.glyph, "RIGHT", ICON_GAP, 0)
    button.label:SetTextColor(unpack(LABEL))
    button.label:SetJustifyH("LEFT")

    button.keyText = button:CreateFontString(nil, "OVERLAY")
    ns.Media.SetFont(button.keyText, "general")
    button.keyText:SetPoint("RIGHT", -PAD_X, 0)
    button.keyText:SetTextColor(unpack(KEY_COLOR))

    -- The hairline between the name and the key.
    button.divider = button:CreateTexture(nil, "OVERLAY")
    button.divider:SetWidth(ns.Media.Pixel())
    button.divider:SetPoint("RIGHT", button.keyText, "LEFT", -KEY_GAP, 0)
    button.divider:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.55)

    button:HookScript("OnEnter", function(self)
      self.hovered = true
      Paint(self)
    end)
    button:HookScript("OnLeave", function(self)
      self.hovered = false
      Paint(self)
    end)
    -- `micro` is a name or a list of names, first one this client has.
    local target
    if FORWARD_CLICKS and entry.micro then
      for _, name in ipairs(type(entry.micro) == "table" and entry.micro or { entry.micro }) do
        target = target or _G[name]
      end
    end
    if FORWARD_CLICKS and not target and entry.opener then
      target = ns.Skin.OpenerFor(entry.opener)
    end
    local overlay = entry.overlay and _G[entry.overlay]
    if overlay then
      button.overlay = overlay
      overlay.fuiKeepPlace = true   -- Skin.Park leaves it where we put it
      local placing
      local function Place()
        if placing or InCombatLockdown() then return end
        placing = true
        overlay:SetParent(button)
        overlay:ClearAllPoints()
        overlay:SetAllPoints(button)
        overlay:SetAlpha(0)          -- invisible, but it still takes the mouse
        overlay:SetFrameLevel(button:GetFrameLevel() + 10)
        if overlay.EnableMouse then overlay:EnableMouse(true) end
        placing = false
      end
      ns.WhenOutOfCombat(Place)
      -- Blizzard lays its micro buttons out again now and then; put it back.
      hooksecurefunc(overlay, "SetPoint", function() if not placing then ns.WhenOutOfCombat(Place) end end)
      -- The tile lights up and shows its tip while the mouse is on the button.
      overlay:HookScript("OnEnter", function() button.hovered = true; Paint(button) end)
      overlay:HookScript("OnLeave", function() button.hovered = false; Paint(button) end)
    elseif target then
      button.microTarget = target
      -- Attributes are protected in combat; the bar is built at login, but
      -- a /reload mid-fight would land here, so it waits rather than throws.
      ns.WhenOutOfCombat(function()
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", target)
        -- Act on the release these buttons hear, whatever "cast on key
        -- down" says (see FORWARD_CLICKS above).
        button:SetAttribute("useOnKeyDown", false)
      end)
      -- A Blizzard button that is there but refusing (Legacy before any
      -- progress): say the key rather than do nothing.
      if entry.opener then
        button:HookScript("PostClick", function()
          if target.IsEnabled and not target:IsEnabled() then ns.Skin.OpenHint(entry.opener) end
        end)
      end
    elseif FORWARD_CLICKS and entry.macro then
      ns.WhenOutOfCombat(function()
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.macro)
        button:SetAttribute("useOnKeyDown", false)
      end)
      if entry.macroHint then
        button:HookScript("PostClick", function() entry.macroHint() end)
      end
    else
      button:SetScript("OnClick", function()
        if not entry.click() then
          ns.Print(("%s isn't available on this client."):format(entry.tip))
        end
      end)
    end
    -- Hooked, not set: SetScript here would throw away the hover paint
    -- hooked on above, and the tile would stop lighting up.
    button:HookScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("%s  (%s)"):format(entry.tip, entry.key))
        GameTooltip:Show()
      end
    end)
    button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    buttons[i] = button
  end
  ns.RegisterMover("microbar", "Micro bar", bar, { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 10 })
  Layout()
end

-- A profile from before the tiles were drawn to the mock-up has the old
-- cramped height and spacing saved in it, and would keep them forever. This
-- brings one of those up to the new shape once, and records that it ran, so
-- changing it afterwards sticks.
function module:OnInit()
  DropShippedEdge()
  local settings = Settings()
  if settings and settings.mockupDone == nil then
    settings.buttonHeight = math.max(settings.buttonHeight or 0, 26)
    settings.spacing = math.max(settings.spacing or 0, 5)
    settings.buttonWidth = 54
    settings.mockupDone = true
  end
end

-- Fade to the faded alpha while the mouse is away, back in while it's over
-- the bar (or a tile of it). Alpha only, so it works in a fight too and the
-- tiles stay clickable; a little slack round the edge so it doesn't flicker.
local fader = CreateFrame("Frame")
fader:Hide()
module.fader = fader
local FADE_IN, FADE_OUT = 6, 3   -- alpha per second

function module.FadeTarget()
  local settings = Settings()
  if not (bar and settings.mouseover) then return 1 end
  local over = bar.IsMouseOver and bar:IsMouseOver(6, -6, -6, 6)
  return over and 1 or math.max(0, math.min(1, (tonumber(settings.fadedAlpha) or 0) / 100))
end

function module.StepFade(elapsed)
  if not bar then return 1 end
  local want = module.FadeTarget()
  local now = bar:GetAlpha() or 1
  if now < want then
    now = math.min(want, now + FADE_IN * (elapsed or 0))
  elseif now > want then
    now = math.max(want, now - FADE_OUT * (elapsed or 0))
  end
  bar:SetAlpha(now)
  return now
end

function module.ApplyFade()
  if not bar then return end
  if Settings().mouseover then
    fader:Show()
    module.StepFade(1)   -- straight to where it should be
  else
    fader:Hide()
    bar:SetAlpha(1)
  end
end

fader:SetScript("OnUpdate", function(self, elapsed)
  self.since = (self.since or 0) + elapsed
  if self.since < 0.03 then return end
  local step = self.since
  self.since = 0
  if bar and bar:IsShown() then module.StepFade(step) end
end)

function module:OnEnable()
  Build()
  bar:SetShown(Settings().shown ~= false)
  Layout()
  module.ApplyFade()
end

-- The tiles are painted by us, not by Skin.Border, so the border colour
-- changing has to reach them by hand.
function module.RepaintTiles()
  for _, button in pairs(buttons) do
    if button and button.glyph then
      Paint(button)
    end
  end
end

if ns.Skin and ns.Skin.AddAccentListener then
  ns.Skin.AddAccentListener(function() module.RepaintTiles() end)
end

-- /fui micro: on, off, or flip.
function module.Toggle(state)
  local settings = Settings()
  if state == nil then
    settings.shown = (settings.shown == false)
  else
    settings.shown = state and true or false
  end
  if bar then bar:SetShown(settings.shown) end
  ns.RefreshOptions()
  return settings.shown
end

function module:OnDisable()
  fader:Hide()
  if bar then bar:Hide() end
end

function module:Refresh()
  if bar then
    bar:SetShown(Settings().shown ~= false)
    Layout()
    module.ApplyFade()
  end
end
