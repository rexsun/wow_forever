local _, ns = ...

-- Chat. Three things: make Blizzard's chat look like the rest of ForeverUI,
-- let you lift the text out to copy it, and -- still -- put the whole thing
-- away and bring it back without a reload.
--
-- Nothing here touches a protected frame or anything secret: chat is plain
-- text the player typed, and the chat frames are ours to restyle. Everything
-- that reaches for a Blizzard frame is guarded, because which pieces exist
-- varies by client.

local module = ns.RegisterModule({
  name = "Chat",
  title = "Chat",
})

module.defaults = {
  skin = true,
  copyButton = true,
  menuButton = true,   -- a flat Menu button in the box, in place of Blizzard's side icons
  emoji = true,        -- turn :) <3 etc into little emoji
  links = true,        -- make web links clickable (opens a copy box)
  hide = false,
  -- sprutorgel on CurseForge, 28 Sept 2026: "choose my own color background
  -- in the chat frame and border, have more font size options than
  -- blizzards, like size 13, 15, option for enter chat box on top or bottom".
  bgColor = { 0.03, 0.03, 0.05 },
  bgOpacity = 92,          -- percent
  ownBorderColor = false,  -- off: General > Border colour, like everything else
  borderColor = { 0.30, 0.76, 1.00 },
  fontSize = 0,            -- 0: the UI's own chat font size
  editBoxPosition = "bottom",
  -- sprutorgel, 29 Sept 2026: "make the chat tabs - general, combat log
  -- etc. - in top of chat window completely fade out?"
  fadeTabs = false,
}

module.options = {
  { type = "heading", label = "Chat" },
  { type = "checkbox", key = "skin", label = "Match the chat to the rest of the UI" },
  { type = "checkbox", key = "copyButton", label = "Show a Copy button on the chat" },
  { type = "checkbox", key = "menuButton", label = "Show a Menu button on the chat (channels, emotes, voice)" },
  { type = "checkbox", key = "emoji", label = "Turn :) and <3 into emoji" },
  { type = "checkbox", key = "links", label = "Make web links clickable" },
  { type = "action", label = "Copy chat now", width = 200,
    onClick = function() module.OpenCopy() end },
  { type = "heading", label = "Look", columns = 2, icon = "appearance" },
  { type = "color", key = "bgColor", label = "Background colour",
    apply = function() module.PaintChat() end },
  { type = "stepper", key = "bgOpacity", label = "Background opacity", min = 0, max = 100, step = 5,
    format = function(v) return ("%d%%"):format(v) end, apply = function() module.PaintChat() end },
  { type = "checkbox", key = "ownBorderColor", label = "Own colour for the chat's border",
    desc = "Off, it follows General > Border colour.", apply = function() module.PaintChat() end },
  { type = "color", key = "borderColor", label = "Chat border colour",
    apply = function() module.PaintChat() end },
  { type = "cycler", key = "fontSize", label = "Font size", desc = "Any size, not only the game's four.",
    choices = function()
      local out = { { value = 0, label = "The UI's own" } }
      for _, n in ipairs({ 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24 }) do
        out[#out + 1] = { value = n, label = tostring(n) }
      end
      return out
    end, apply = function() module.PaintChat() end },
  { type = "cycler", key = "editBoxPosition", label = "Where you type",
    choices = function() return { { value = "bottom", label = "Under the chat" }, { value = "top", label = "Above the chat" } } end,
    apply = function() module.PaintChat() end },
  { type = "checkbox", key = "fadeTabs", label = "Fade the chat tabs out completely",
    desc = "General, Combat Log and the rest vanish until you point at the chat. A tab with a new whisper still shows.",
    apply = function() module.ApplyTabFade() end },
  { type = "heading", label = "Hiding", icon = "general" },
  { type = "checkbox", key = "hide", label = "Hide Blizzard's chat windows" },
  { type = "note", label = "Hiding is reversible on the spot -- untick it and the conversation comes back." },
}

local function Settings()
  return ns.db.modules.Chat
end

local NUM = NUM_CHAT_WINDOWS or 10

---------------------------------------------------------------------------
-- Reading the conversation back out, as plain copyable text
---------------------------------------------------------------------------

local MAX_LINES = 500
local history = {}
module.history = history

-- Strip the markup the game paints into a line -- colours, item and player
-- links, inline textures -- down to the words a person would want to copy.
local function Plain(text)
  if type(text) ~= "string" then
    return nil
  end
  -- A secret string answers type() with "string" and then throws the moment
  -- anything indexes it, so the copy history skips it. Printing a secret
  -- value -- UnitGetIncomingHeals() on Forever hands one back -- used to take
  -- the whole chat frame down with it.
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, text)
    if not ok or secret then
      return nil
    end
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|C%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|H.-|h(.-)|h", "%1")   -- a hyperlink keeps its label
  text = text:gsub("|T.-|t", "")           -- inline texture
  text = text:gsub("|A.-|a", "")           -- inline atlas
  text = text:gsub("|K.-|k", "")           -- obscured names
  text = text:gsub("|n", "\n")
  return text
end
module.Plain = Plain

local function Record(text)
  local line = Plain(text)
  if not line or line == "" then
    return
  end
  history[#history + 1] = line
  while #history > MAX_LINES do
    table.remove(history, 1)
  end
end
module.Record = Record

-- The lines a window already holds, so the copy box isn't empty until the
-- next thing is said. Best effort: not every client answers these.
local function Seed(frame)
  if not frame or not frame.GetNumMessages or not frame.GetMessageInfo then
    return
  end
  local ok, count = pcall(frame.GetNumMessages, frame)
  if not ok or type(count) ~= "number" then
    return
  end
  for i = 1, count do
    local mok, text = pcall(frame.GetMessageInfo, frame, i)
    if mok then
      Record(text)
    end
  end
end

local hooked = {}
local function HookFrame(frame)
  if not frame or hooked[frame] or type(frame.AddMessage) ~= "function" then
    return
  end
  hooked[frame] = true
  hooksecurefunc(frame, "AddMessage", function(_, msg)
    Record(msg)
  end)
end

---------------------------------------------------------------------------
-- A chat-room feel: emoji and clickable links
---------------------------------------------------------------------------
--
-- Incoming lines pass through a message filter -- the game's own, taint-safe
-- way to rewrite chat before it shows. Emoticons become little inline emoji;
-- web links become clickable and open a box to copy from (the game can't
-- open a browser). Both are just text rewriting; nothing here is secret.

local EMOJI_DIR = ns.MEDIA_PATH .. "emoji\\"

-- token -> emoji file. Longer tokens are tried first so ":'(" wins over ":(".
local EMOJI = {
  { ":')", "laugh" }, { ":'(", "cry" }, { ">:(", "angry" },
  { ":-D", "grin" }, { ":D", "grin" }, { "xD", "laugh" }, { "XD", "laugh" },
  { ":-)", "smile" }, { ":)", "smile" }, { "=)", "smile" }, { "(:", "smile" },
  { ":-(", "sad" }, { ":(", "sad" }, { "):", "sad" },
  { ";-)", "wink" }, { ";)", "wink" },
  { ":-P", "tongue" }, { ":P", "tongue" }, { ":p", "tongue" }, { ":-p", "tongue" },
  { ":-O", "surprised" }, { ":O", "surprised" }, { ":o", "surprised" },
  { ":-|", "neutral" }, { ":|", "neutral" },
  { ":-*", "kiss" }, { ":*", "kiss" },
  { "B)", "cool" }, { "8)", "cool" }, { "B-)", "cool" },
  { "</3", "brokenheart" }, { "<3", "heart" },
  { ":thumbsup:", "thumbsup" }, { "(y)", "thumbsup" },
  { ":heart:", "heart" }, { ":smile:", "smile" }, { ":fire:", "fire" },
  { ":skull:", "skull" }, { ":star:", "star" }, { ":cool:", "cool" },
  { ":wink:", "wink" }, { ":cry:", "cry" }, { ":angry:", "angry" },
}

local function escapePattern(token)
  return (token:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function Emojify(text)
  if type(text) ~= "string" then
    return text
  end
  for _, entry in ipairs(EMOJI) do
    local tex = "|T" .. EMOJI_DIR .. entry[2] .. ":16:16|t"
    text = text:gsub(escapePattern(entry[1]), tex)
  end
  return text
end
module.Emojify = Emojify

-- Wrap web links in a clickable ForeverUI link. The replacement comes from a
-- function, so gsub takes it literally -- no %-escaping of the URL needed.
local function wrapURL(url)
  return ("|cff4dc3ff|Hforeveruiurl:%s|h[%s]|h|r"):format(url, url)
end
local URLCHARS = "[%w%.%-_/~:%?#%%@!$&'%(%)%*%+,;=]+"
local function Linkify(text)
  if type(text) ~= "string" then
    return text
  end
  text = text:gsub("(https?://" .. URLCHARS .. ")", wrapURL)
  text = text:gsub("(www%." .. URLCHARS .. ")", wrapURL)
  return text
end
module.Linkify = Linkify

-- Clicking a link can't open a browser, so it opens a box with the address
-- selected, ready to copy.
local function ShowURL(url)
  if not StaticPopupDialogs then
    ns.Print("link: " .. url)
    return
  end
  StaticPopupDialogs["FOREVERUI_URL"] = StaticPopupDialogs["FOREVERUI_URL"] or {
    text = "Copy this link:",
    button1 = _G.OKAY or "Okay",
    hasEditBox = true, editBoxWidth = 350,
    OnShow = function(self)
      local box = self.editBox or (self.GetEditBox and self:GetEditBox())
      if box then box:SetText(self.data or ""); box:HighlightText(); box:SetFocus() end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  if StaticPopup_Show then
    StaticPopup_Show("FOREVERUI_URL", nil, nil, url)
  end
end
module.ShowURL = ShowURL

local linksHooked = false
local function HookLinks()
  if linksHooked or not hooksecurefunc or type(_G.SetItemRef) ~= "function" then
    return
  end
  linksHooked = true
  hooksecurefunc("SetItemRef", function(link)
    local url = type(link) == "string" and link:match("^foreveruiurl:(.+)")
    if url then
      ShowURL(url)
    end
  end)
end

-- The lines the filter runs on -- everything a person actually says.
local FILTER_EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

-- Only the words people typed are rewritten - never the game's own codes in
-- the line. An item link is "|Hitem:6948::::::::40:::|h[Hearthstone]|h", and
-- a run of empty fields ends "::|h": that ":|" is an emoticon, so the link's
-- code was swapped for an emoji, the link broke, and chat showed the raw item
-- number with nothing to click (BAP2521 on CurseForge, 2 Oct 2026: "most
-- things show an item number, then the link and im unable to click any of
-- the links"). Links, textures, atlases and hidden names are set aside first
-- and put back untouched.
local PROTECTED = { "|H.-|h.-|h", "|T.-|t", "|A.-|a", "|K.-|k" }
local function Protect(text, rewrite)
  local kept = {}
  local function Keep(chunk)
    kept[#kept + 1] = chunk
    return "\001" .. #kept .. "\002"
  end
  for _, pattern in ipairs(PROTECTED) do
    text = text:gsub(pattern, Keep)
  end
  text = rewrite(text)
  return (text:gsub("\001(%d+)\002", function(i) return kept[tonumber(i)] or "" end))
end
module.Protect = Protect

local function Transform(_, _, msg, ...)
  if type(msg) == "string" then
    msg = Protect(msg, function(text)
      if Settings().links then text = Linkify(text) end
      if Settings().emoji then text = Emojify(text) end
      return text
    end)
  end
  return false, msg, ...
end
module.Transform = Transform

local filtersInstalled = false
local function InstallFilters()
  HookLinks()
  if filtersInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then
    return
  end
  filtersInstalled = true
  for _, event in ipairs(FILTER_EVENTS) do
    pcall(ChatFrame_AddMessageEventFilter, event, Transform)
  end
end
module.InstallFilters = InstallFilters

---------------------------------------------------------------------------
-- The copy window
---------------------------------------------------------------------------

local copyFrame
local function BuildCopyWindow()
  copyFrame = CreateFrame("Frame", "ForeverUICopyChat", UIParent)
  copyFrame:SetSize(580, 400)
  copyFrame:SetPoint("CENTER")
  copyFrame:SetFrameStrata("DIALOG")
  copyFrame:EnableMouse(true)
  copyFrame:SetMovable(true)
  copyFrame:RegisterForDrag("LeftButton")
  copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
  copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
  ns.Skin.Panel(copyFrame, { color = { 0.06, 0.06, 0.08, 0.97 } })
  ns.Skin.Header(copyFrame, "Copy chat", function() copyFrame:Hide() end)

  local hint = copyFrame:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(hint, "general")
  hint:SetPoint("BOTTOMLEFT", 16, 16)
  hint:SetTextColor(unpack(ns.Colors.ui.textDim))
  hint:SetText("Everything's selected -- press Cmd/Ctrl+C to copy. Escape closes.")

  local scroll = CreateFrame("ScrollFrame", "ForeverUICopyChatScroll", copyFrame,
    "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -40)
  scroll:SetPoint("BOTTOMRIGHT", -34, 40)

  local edit = CreateFrame("EditBox", nil, scroll)
  if edit.SetMultiLine then edit:SetMultiLine(true) end
  if edit.SetAutoFocus then edit:SetAutoFocus(false) end
  if edit.SetWidth then edit:SetWidth(520) end
  ns.Media.SetFont(edit, "general")
  if edit.SetTextColor then edit:SetTextColor(unpack(ns.Colors.ui.text)) end
  edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
  if scroll.SetScrollChild then scroll:SetScrollChild(edit) end
  copyFrame.edit = edit

  if UISpecialFrames then
    table.insert(UISpecialFrames, "ForeverUICopyChat")
  end
  module.copyFrame = copyFrame
  return copyFrame
end

function module.OpenCopy()
  if not copyFrame then
    BuildCopyWindow()
  end
  copyFrame.edit:SetText(table.concat(history, "\n"))
  copyFrame:Show()
  -- Pre-select the lot, so copying is one keystroke.
  if copyFrame.edit.HighlightText then copyFrame.edit:HighlightText() end
  if copyFrame.edit.SetFocus then copyFrame.edit:SetFocus() end
  return copyFrame
end

---------------------------------------------------------------------------
-- The Copy button that sits on the chat
---------------------------------------------------------------------------

-- Two small flat buttons in the box's top-right corner, over the oldest
-- scrollback: Copy (the copy window) and Menu (Blizzard's chat menu --
-- channels, emotes, voice -- which used to be the speech-bubble icon on the
-- side). Everything the chat needs, in one place, in the UI's own style.
local copyButton, menuButton

local function OpenBlizzardMenu()
  local b = _G.ChatFrameMenuButton
  local click = b and b.GetScript and b:GetScript("OnClick")
  if click then
    pcall(click, b, "LeftButton")
  elseif _G.ChatFrame_ToggleMenu then
    pcall(_G.ChatFrame_ToggleMenu)
  end
end
module.OpenBlizzardMenu = OpenBlizzardMenu

local function BuildCopyButton()
  local anchor = _G.ChatFrame1
  if not anchor or copyButton then
    return copyButton
  end
  copyButton = ns.OptionButton(anchor, 46, "Copy", function() module.OpenCopy() end)
  if copyButton.SetHeight then copyButton:SetHeight(16) end
  copyButton:ClearAllPoints()
  copyButton:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 2, -2) -- inside the box
  module.copyButton = copyButton
  return copyButton
end

local function BuildMenuButton()
  local anchor = _G.ChatFrame1
  if not anchor or menuButton then
    return menuButton
  end
  menuButton = ns.OptionButton(anchor, 46, "Menu", OpenBlizzardMenu)
  if menuButton.SetHeight then menuButton:SetHeight(16) end
  menuButton:ClearAllPoints()
  module.menuButton = menuButton
  return menuButton
end

-- Lay the two out right-to-left so a hidden Copy leaves Menu in the corner.
local function PlaceButtons()
  local anchor = _G.ChatFrame1
  if not anchor then return end
  local right = anchor
  local point, relPoint, x = "TOPRIGHT", "TOPRIGHT", 2
  for _, b in ipairs({ copyButton, menuButton }) do
    if b and b:IsShown() then
      b:ClearAllPoints()
      b:SetPoint(point, right, relPoint, x, right == anchor and -2 or 0)
      right, point, relPoint, x = b, "TOPRIGHT", "TOPLEFT", -3
    end
  end
end

local function ApplyCopyButton()
  local settings = Settings()
  if settings.copyButton then
    BuildCopyButton()
    if copyButton then copyButton:Show() end
  elseif copyButton then
    copyButton:Hide()
  end
  if settings.menuButton then
    BuildMenuButton()
    if menuButton then menuButton:Show() end
  elseif menuButton then
    menuButton:Hide()
  end
  PlaceButtons()
end

---------------------------------------------------------------------------
-- Making it look like the rest of the UI
---------------------------------------------------------------------------

-- Textures we hid to flatten something, so turning the skin off can show
-- them again; and the shell textures we drew, to hide them again.
local hiddenBySkin = {}
-- The chat box's colours: the player's own (or the shipped dark), and the
-- border in General's colour unless the chat has its own.
function module.ChatBackground()
  local s = Settings()
  local c = type(s.bgColor) == "table" and s.bgColor or { 0.03, 0.03, 0.05 }
  local a = math.max(0, math.min(100, tonumber(s.bgOpacity) or 92)) / 100
  return c[1] or 0.03, c[2] or 0.03, c[3] or 0.05, a
end

function module.PaintEdge(t, alpha)
  local s = Settings()
  if s.ownBorderColor and type(s.borderColor) == "table" then
    -- Out of the accent's repaint list, or General's colour would win back.
    if ns.Skin.accentTextures then ns.Skin.accentTextures[t] = nil end
    local c = s.borderColor
    t:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, alpha)
  else
    ns.Skin.AccentTexture(t, alpha)
  end
  t.fuiEdgeAlpha = alpha
end

-- Any size, not only the four the game's menu offers.
function module.SizeText(region)
  local size = tonumber(Settings().fontSize) or 0
  if size <= 0 or not (region and region.GetFont and region.SetFont) then return end
  local path, _, flags = region:GetFont()
  if path then pcall(region.SetFont, region, path, size, flags or "") end
end

local shells = {}   -- [chatFrame] = { fill, top, bottom, left, right }
module.shells = shells

-- A solid dark background with a thin blue edge behind a chat window, drawn
-- on the frame itself at the BACKGROUND/BORDER layers so it sits behind the
-- text (and hides and moves with the window). This is the "shell" the rest
-- of the UI wears -- dark panel, blue coat.
local function SkinShell(cf)
  if not cf or shells[cf] or not cf.CreateTexture then
    return
  end
  local name = cf.GetName and cf:GetName()
  local tab = (name and _G[name .. "Tab"]) or _G.GeneralDockManager
  local edit = name and _G[name .. "EditBox"]
  -- One square box behind the window: the messages, and the input line
  -- under them, in a single dark panel with a thin blue edge. Textures
  -- aren't clipped to the frame, so anchoring the fill's bottom out to the
  -- edit box makes one rectangle over both. The tab row is NOT in the box:
  -- it left a band of dead space above the first line, so the tabs sit on
  -- the top edge outside it, faded the way Blizzard fades them, and the
  -- messages fill the box to the top.
  local fill = cf:CreateTexture(nil, "BACKGROUND", nil, -8)
  fill:SetColorTexture(module.ChatBackground())   -- solid dark, or the player's colour
  if tab and tab.ClearAllPoints and tab.SetPoint and not (tab.IsProtected and tab:IsProtected()) then
    -- The tab rides the top edge; the dock re-anchors it on its own terms,
    -- so this is a nudge, not a claim.
    pcall(tab.SetPoint, tab, "BOTTOMLEFT", fill, "TOPLEFT", 2, 0)
  end

  local parts = { fill }
  parts.fill, parts.edit, parts.edges = fill, edit, {}
  local function edge()
    local t = cf:CreateTexture(nil, "BORDER")
    module.PaintEdge(t, 0.85)                            -- the UI's border colour, or the chat's own
    parts[#parts + 1] = t
    parts.edges[#parts.edges + 1] = t
    return t
  end
  local top, bottom, left, right = edge(), edge(), edge(), edge()
  top:SetPoint("TOPLEFT", fill, "TOPLEFT"); top:SetPoint("TOPRIGHT", fill, "TOPRIGHT"); top:SetHeight(1)
  bottom:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT"); bottom:SetHeight(1)
  left:SetPoint("TOPLEFT", fill, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT"); left:SetWidth(1)
  right:SetPoint("TOPRIGHT", fill, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT"); right:SetWidth(1)

  -- A hairline between the messages and the input line, so the one box still
  -- reads as "chat above, type below" without a second border around the box.
  if edit then
    local divider = cf:CreateTexture(nil, "BORDER")
    module.PaintEdge(divider, 0.30)
    divider:SetHeight(1)
    parts[#parts + 1] = divider
    parts.divider = divider
  end

  shells[cf] = parts
  module.PlaceShell(cf, parts)
end

-- The box around messages and input: the input line under the messages, or
-- (sprutorgel's ask) above them, between the tabs and the first line.
function module.PlaceShell(cf, parts)
  local fill, edit = parts.fill, parts.edit
  local onTop = Settings().editBoxPosition == "top" and edit ~= nil
  fill:ClearAllPoints()
  fill:SetPoint("LEFT", cf, "LEFT", -5, 0)
  fill:SetPoint("RIGHT", cf, "RIGHT", 5, 0)
  if onTop then
    fill:SetPoint("TOP", edit, "TOP", 0, 4)
    fill:SetPoint("BOTTOM", cf, "BOTTOM", 0, -4)
  else
    fill:SetPoint("TOP", cf, "TOP", 0, 4)
    fill:SetPoint("BOTTOM", edit or cf, "BOTTOM", 0, -4)
  end
  local divider = parts.divider
  if divider then
    divider:ClearAllPoints()
    divider:SetPoint("LEFT", fill, "LEFT", 1, 0)
    divider:SetPoint("RIGHT", fill, "RIGHT", -1, 0)
    if onTop then
      divider:SetPoint("TOP", edit, "BOTTOM", 0, -2)
    else
      divider:SetPoint("BOTTOM", edit, "TOP", 0, 2)
    end
  end
end

-- The scroll arrows on the side are Blizzard's ornate ones; the wheel still
-- scrolls, so hide them for the clean shell.
local scrollHooked = {}
local function HideScrollWidget(b)
  if type(b) ~= "table" or not b.Hide then return end
  hiddenBySkin[b] = true
  b:Hide()
  -- The jump-to-bottom arrow shows itself again whenever the window is
  -- scrolled up; the wheel and typing still jump, so keep it down.
  if b.HookScript and not scrollHooked[b] then
    scrollHooked[b] = true
    pcall(b.HookScript, b, "OnShow", function(self)
      if hiddenBySkin[self] then self:Hide() end
    end)
  end
end

local function HideScroll(cf)
  if not cf then return end
  local name = cf.GetName and cf:GetName()
  if name then
    for _, suffix in ipairs({ "UpButton", "DownButton", "BottomButton",
      "ScrollToBottomButton", "ButtonFrameUpButton", "ButtonFrameDownButton",
      "ButtonFrameBottomButton", "ScrollBar", "ButtonFrame" }) do
      HideScrollWidget(_G[name .. suffix])
    end
  end
  -- Newer clients keep them as fields, not globals.
  for _, key in ipairs({ "ScrollToBottomButton", "ScrollBar", "ButtonFrame" }) do
    HideScrollWidget(cf[key])
  end
end

-- Hidden AND faded to nothing: Blizzard shows some of these again on its
-- own (the typing box's focus glow, a tab's active art), and Show() doesn't
-- undo an alpha of zero. RemoveSkin puts both back.
local function HideTexture(t)
  if t and t.Hide and t.IsObjectType and t:IsObjectType("Texture") then
    hiddenBySkin[t] = true
    t:Hide()
    if t.SetAlpha then t:SetAlpha(0) end
  end
end

-- A piece of a Blizzard frame by any of the names a client has given it:
-- the old global ("ChatFrame1TabLeft"), the field ("tab.Left"), or the
-- field with a small first letter ("edit.focusLeft").
local function Piece(frame, name, suffix)
  local t = name and _G[name .. suffix]
  if type(t) ~= "table" and frame then
    t = frame[suffix]
    if type(t) ~= "table" then
      t = frame[suffix:sub(1, 1):lower() .. suffix:sub(2)]
    end
  end
  return type(t) == "table" and t or nil
end

-- Blizzard's own frame around the window -- eight border strips and a
-- background, drawn 14px wider than the window itself and faded in on
-- mouse-over -- poked out past the shell's right edge. Off, all of it; the
-- shell is the frame now.
local CHAT_FRAME_ART = {
  "Background", "TopTexture", "BottomTexture", "LeftTexture", "RightTexture",
  "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
}
local function HideFrameArt(cf)
  if not cf then return end
  local name = cf.GetName and cf:GetName()
  local list = _G.CHAT_FRAME_TEXTURES or CHAT_FRAME_ART
  for _, suffix in ipairs(list) do
    HideTexture(Piece(cf, name, suffix))
  end
end

-- The ornate frame around the typing box, gone; a flat panel and our font in
-- its place.
local function SkinEditBox(edit)
  if not edit then
    return
  end
  local name = edit.GetName and edit:GetName()
  for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
    HideTexture(Piece(edit, name, suffix))
  end
  -- No panel of its own any more: the input line lives inside the single
  -- chat box (SkinShell draws the fill and the hairline above it), so a
  -- second border here would just box it off again.
  ns.Media.SetFont(edit, "general")
  if edit.SetTextColor then edit:SetTextColor(unpack(ns.Colors.ui.text)) end
  -- Blizzard hangs the typing box 5px past the window on the left and 16px
  -- past it on the right, so it poked out of the box. Same overhang both
  -- sides, matching the shell's edges. Not protected, and Blizzard only
  -- anchors it once, so a plain re-anchor holds.
  module.PlaceEditBox(edit)
  module.SizeText(edit)
end

-- Under the messages (as Blizzard has it), or above them.
function module.PlaceEditBox(edit)
  local name = edit and edit.GetName and edit:GetName()
  local cf = name and _G[name:gsub("EditBox$", "")]
  if cf and edit.SetPoint and edit.ClearAllPoints and not (edit.IsProtected and edit:IsProtected()) then
    pcall(edit.ClearAllPoints, edit)
    if Settings().editBoxPosition == "top" then
      pcall(edit.SetPoint, edit, "BOTTOMLEFT", cf, "TOPLEFT", -5, 2)
      pcall(edit.SetPoint, edit, "BOTTOMRIGHT", cf, "TOPRIGHT", 5, 2)
    else
      pcall(edit.SetPoint, edit, "TOPLEFT", cf, "BOTTOMLEFT", -5, -2)
      pcall(edit.SetPoint, edit, "TOPRIGHT", cf, "BOTTOMRIGHT", 5, -2)
    end
  end
end

-- The tab: Blizzard's gold parchment art gone, and in its place a flat dark
-- tab in the box's own colours -- dark fill, blue edge on three sides, open
-- at the bottom where it meets the box -- with its label in our font. The
-- tab itself still fades and highlights the way Blizzard drives it; only
-- the clothes change.
local tabSkins = {}
module.tabSkins = tabSkins

local function SkinTab(tab)
  if not tab then
    return
  end
  local name = tab.GetName and tab:GetName()
  for _, suffix in ipairs({ "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle",
    "SelectedRight", "ActiveLeft", "ActiveMiddle", "ActiveRight", "HighlightLeft",
    "HighlightMiddle", "HighlightRight", "Glow" }) do
    HideTexture(Piece(tab, name, suffix))
  end
  if name then HideTexture(_G[name .. "Glow"]) end
  local text = Piece(tab, name, "Text") or (tab.GetFontString and tab:GetFontString())
  if text then
    ns.Media.SetFont(text, "general")
    if text.SetTextColor then text:SetTextColor(unpack(ns.Colors.ui.text)) end
  end
  if tabSkins[tab] or not tab.CreateTexture then
    return
  end
  -- Blizzard paints the label gold again whenever the tab is selected or
  -- flashes; paint it back. Only while the skin is on.
  if text and text.SetTextColor and hooksecurefunc then
    local painting = false
    hooksecurefunc(text, "SetTextColor", function(t)
      if painting or not tabSkins[tab] then return end
      painting = true
      t:SetTextColor(unpack(ns.Colors.ui.text))
      painting = false
    end)
  end
  local fill = tab:CreateTexture(nil, "BACKGROUND", nil, -7)
  fill:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, -6)
  fill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -4, 0)
  fill:SetColorTexture(module.ChatBackground())
  local parts = { fill }
  local function edge()
    local t = tab:CreateTexture(nil, "BORDER")
    module.PaintEdge(t, 0.85)
    parts[#parts + 1] = t
    return t
  end
  local top, left, right = edge(), edge(), edge()
  top:SetPoint("TOPLEFT", fill, "TOPLEFT"); top:SetPoint("TOPRIGHT", fill, "TOPRIGHT"); top:SetHeight(1)
  left:SetPoint("TOPLEFT", fill, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT"); left:SetWidth(1)
  right:SetPoint("TOPRIGHT", fill, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT"); right:SetWidth(1)
  tabSkins[tab] = parts
end

-- Tabs that fade out completely (sprutorgel, 29 Sept 2026). Blizzard fades
-- the tab row itself when the pointer leaves the chat -- but only down to
-- 20-40%, from constants in FloatingChatFrame.lua. Writing those globals
-- would taint the chat's own fading code, so instead each tab's SetAlpha is
-- post-hooked (hooksecurefunc: Blizzard's code runs untouched) and, while
-- the chat is faded out, whatever Blizzard asks for becomes 0. Pointing at
-- the chat fades them back in as usual (FCF_FadeInChatFrame sets
-- hasBeenFaded first). A tab flashing for a new whisper is left visible.
local fadeHooked = {}
module.fadeHooked = fadeHooked

local function TabChatFrame(tab)
  local name = tab.GetName and tab:GetName()
  local frameName = type(name) == "string" and name:match("^(.+)Tab$")
  if frameName and _G[frameName] then return _G[frameName] end
  for i = 1, NUM do
    if _G["ChatFrame" .. i .. "Tab"] == tab then return _G["ChatFrame" .. i] end
  end
  return nil
end

local function TabAlerting(tab)
  local util = rawget(_G, "ChatFrameUtil")
  if util and type(util.IsTabAlerting) == "function" then
    local ok, on = pcall(util.IsTabAlerting, tab)
    if ok then return on and true or false end
  end
  return tab.alerting and true or false
end

-- Should this tab be invisible right now?
function module.TabHidden(tab)
  local s = ns.db and ns.db.modules and ns.db.modules.Chat
  if not (s and s.fadeTabs) or not module.fadeOn then return false end
  if TabAlerting(tab) then return false end
  local cf = TabChatFrame(tab)
  if cf and cf.hasBeenFaded then return false end
  return true
end

local settingAlpha = false
local function OnTabAlpha(tab)
  if settingAlpha or not module.TabHidden(tab) then return end
  settingAlpha = true
  pcall(tab.SetAlpha, tab, 0)
  settingAlpha = false
end

local function HookTabFade(tab)
  if not tab or fadeHooked[tab] or not hooksecurefunc or type(tab.SetAlpha) ~= "function" then return end
  fadeHooked[tab] = true
  hooksecurefunc(tab, "SetAlpha", OnTabAlpha)
end

-- Every tab now (docked, floating, whisper windows), and the switch applied
-- at once rather than on the next fade.
function module.ApplyTabFade()
  for _, name in ipairs(rawget(_G, "CHAT_FRAMES") or {}) do
    HookTabFade(_G[name .. "Tab"])
  end
  for i = 1, NUM do
    HookTabFade(_G["ChatFrame" .. i .. "Tab"])
  end
  for tab in pairs(fadeHooked) do
    if module.TabHidden(tab) then
      OnTabAlpha(tab)
    elseif tab.GetAlpha and tab:GetAlpha() == 0 then
      -- Switched off while hidden: back to what Blizzard would show.
      local cf = TabChatFrame(tab)
      local util = rawget(_G, "ChatFrameUtil")
      local over, idle = 1, 0.4
      if util and type(util.GetTabAlphas) == "function" then
        local ok, a, b = pcall(util.GetTabAlphas, tab)
        if ok and tonumber(a) and tonumber(b) then over, idle = a, b end
      end
      pcall(tab.SetAlpha, tab, cf and cf.hasBeenFaded and over or idle)
    end
  end
end

local tempHooked = false
local function HookTemporaryWindows()
  if tempHooked or not hooksecurefunc or type(rawget(_G, "FCF_OpenTemporaryWindow")) ~= "function" then return end
  tempHooked = true
  hooksecurefunc("FCF_OpenTemporaryWindow", function() pcall(module.ApplyTabFade) end)
end

-- Every chat window, whisper windows (ChatFrame11 and up) included.
local function EachMessageFrame(fn)
  local seen = {}
  for i = 1, NUM do
    local cf = _G["ChatFrame" .. i]
    if cf then seen[cf] = true; fn(cf) end
  end
  for _, name in ipairs(rawget(_G, "CHAT_FRAMES") or {}) do
    local cf = _G[name]
    if cf and not seen[cf] then seen[cf] = true; fn(cf) end
  end
end
module.EachMessageFrame = EachMessageFrame

-- The game re-applies each window's stored size after login (and other
-- add-ons hook the same call), which put the chat back to 18-20 until the
-- options window repainted it. Re-assert the chosen size after every such
-- call and every new whisper window.
local sizeHooked = false
local function HookFontSize()
  if sizeHooked or not hooksecurefunc then return end
  sizeHooked = true
  local function Resize()
    if not module.fadeOn then return end   -- false once the module is disabled
    EachMessageFrame(function(cf) pcall(module.SizeText, cf) end)
  end
  if type(rawget(_G, "FCF_SetChatWindowFontSize")) == "function" then
    hooksecurefunc("FCF_SetChatWindowFontSize", Resize)
  end
  if type(rawget(_G, "FCF_OpenTemporaryWindow")) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", Resize)
  end
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  watcher:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0, Resize) else Resize() end
  end)
end

-- The chat's own buttons -- the social/quick-join count, the voice
-- speakers, the channel and menu buttons -- sit scattered down the left
-- edge by default, in Blizzard's round gold style. They are gathered into
-- one holder and the holder is hidden: the chat menu is reached from the
-- flat Menu button in the box instead, and the rest (voice, quick join) had
-- no place in this UI. They aren't protected, so this is safe; Blizzard's
-- dock re-lays them out on its own, so each re-anchor is caught and folded
-- back into the holder. The holder sits under the Menu button so the menu
-- that anchors to the old icon opens where the new button is.
local CHAT_BUTTONS = {
  "QuickJoinToastButton", "ChatFrameChannelButton",
  "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
  "ChatFrameMenuButton",
}
local buttonRow, grouping, groupHooked = nil, false, {}
module.buttonRow = nil

local function Reflow()
  if not buttonRow or grouping then
    return
  end
  grouping = true
  local y, width = 0, 24
  for _, name in ipairs(CHAT_BUTTONS) do
    local b = _G[name]
    if b and b.ClearAllPoints and b.SetPoint then
      b:ClearAllPoints()
      b:SetPoint("TOP", buttonRow, "TOP", 0, y)
      local h = (b.GetHeight and b:GetHeight()) or 24
      if not h or h < 8 then h = 24 end
      local w = (b.GetWidth and b:GetWidth()) or 24
      if w and w > width then width = w end
      y = y - h - 1
    end
  end
  buttonRow:SetSize(width, math.max(1, -y))
  grouping = false
end

local function GroupButtons()
  local chat = _G.ChatFrame1
  if not chat then
    return
  end
  buttonRow = buttonRow or CreateFrame("Frame", "ForeverUIChatButtons", UIParent)
  module.buttonRow = buttonRow
  buttonRow:ClearAllPoints()
  buttonRow:SetPoint("TOPRIGHT", chat, "TOPRIGHT", 2, -2)
  buttonRow:Hide()
  for _, name in ipairs(CHAT_BUTTONS) do
    local b = _G[name]
    if b and not groupHooked[b] then
      groupHooked[b] = true
      if b.SetParent then b:SetParent(buttonRow) end
      if hooksecurefunc and b.SetPoint then
        hooksecurefunc(b, "SetPoint", function()
          if not grouping then Reflow() end
        end)
      end
    end
  end
  Reflow()
end
module.GroupButtons = GroupButtons

-- The messages themselves, in our font.
local function SkinMessages(frame)
  if frame and frame.SetFont then
    ns.Media.SetFont(frame, "general")
    module.SizeText(frame)
  end
end

local function ApplySkin()
  for i = 1, NUM do
    local cf = _G["ChatFrame" .. i]
    SkinShell(cf)
    SkinMessages(cf)
    SkinEditBox(_G["ChatFrame" .. i .. "EditBox"])
    SkinTab(_G["ChatFrame" .. i .. "Tab"])
    HideScroll(cf)
    HideFrameArt(cf)
  end
  GroupButtons()
end
module.ApplySkin = ApplySkin

-- A colour, the size or the input line's place changed: repaint what's drawn.
function module.PaintChat()
  if not Settings().skin then return end
  local r, g, b, a = module.ChatBackground()
  for cf, parts in pairs(shells) do
    if parts.fill then parts.fill:SetColorTexture(r, g, b, a) end
    for _, t in ipairs(parts.edges or {}) do module.PaintEdge(t, 0.85) end
    if parts.divider then module.PaintEdge(parts.divider, 0.30) end
    module.PlaceShell(cf, parts)
  end
  for _, parts in pairs(tabSkins) do
    parts[1]:SetColorTexture(r, g, b, a)
    for i = 2, #parts do module.PaintEdge(parts[i], 0.85) end
  end
  for i = 1, NUM do
    local cf = _G["ChatFrame" .. i]
    if cf then SkinMessages(cf) end
    local edit = _G["ChatFrame" .. i .. "EditBox"]
    if edit then
      ns.Media.SetFont(edit, "general")
      module.PlaceEditBox(edit)
      module.SizeText(edit)
    end
  end
end

-- Best effort the other way: show what we hid and hand the font back.
local function RemoveSkin()
  -- Forget first, then show: the jump-to-bottom arrow's OnShow hook re-hides
  -- anything still on the list.
  local hidden = {}
  for t in pairs(hiddenBySkin) do hidden[#hidden + 1] = t end
  ns.Wipe(hiddenBySkin)
  for _, t in ipairs(hidden) do
    if t.SetAlpha then t:SetAlpha(1) end
    if t.Show then t:Show() end
  end
  for _, parts in pairs(tabSkins) do
    for _, t in ipairs(parts) do
      if t.Hide then t:Hide() end
    end
  end
  ns.Wipe(tabSkins)
  if buttonRow then buttonRow:Show() end
  for _, parts in pairs(shells) do
    for _, t in ipairs(parts) do
      if t.Hide then t:Hide() end
    end
  end
  ns.Wipe(shells)
  for i = 1, NUM do
    local frame = _G["ChatFrame" .. i]
    if frame and frame.SetFontObject and _G.ChatFontNormal then
      pcall(frame.SetFontObject, frame, _G.ChatFontNormal)
    end
  end
end

---------------------------------------------------------------------------
-- Hide / show (unchanged: reversible on the spot, no reload)
---------------------------------------------------------------------------

local hiddenParent
local stashed = {}

local function Stash(frame)
  if not frame or stashed[frame] then
    return false
  end
  hiddenParent = hiddenParent or CreateFrame("Frame")
  hiddenParent:Hide()
  stashed[frame] = {
    parent = (frame.GetParent and frame:GetParent()) or UIParent,
    shown = frame.IsShown and frame:IsShown() or false,
  }
  if frame.SetParent then frame:SetParent(hiddenParent) end
  if frame.Hide then frame:Hide() end
  return true
end

local function EachChatFrame(fn)
  for i = 1, NUM do
    for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
      fn(_G["ChatFrame" .. i .. suffix])
    end
  end
  for _, name in ipairs({
    "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "GeneralDockManager",
  }) do
    fn(_G[name])
  end
end

local function HideChat()
  -- The controller's radial menu puts you in Blizzard's chat: never hidden
  -- from it.
  if ns.ControllerActive and ns.ControllerActive() then
    return 0
  end
  local count = 0
  EachChatFrame(function(frame)
    if Stash(frame) then count = count + 1 end
  end)
  if copyButton then copyButton:Hide() end
  if menuButton then menuButton:Hide() end
  module.hiddenCount = count
  return count
end
module.HideChat = HideChat

local function ShowChat()
  local count = 0
  for frame, state in pairs(stashed) do
    if frame.SetParent then frame:SetParent(state.parent or UIParent) end
    if state.shown and frame.Show then frame:Show() end
    stashed[frame] = nil
    count = count + 1
  end
  module.hiddenCount = 0
  module.restoredCount = count
  ApplyCopyButton()
  return count
end
module.ShowChat = ShowChat

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function Apply()
  local s = Settings()
  -- Always record, so Copy has something to show whatever else is set.
  for i = 1, NUM do
    HookFrame(_G["ChatFrame" .. i])
  end
  InstallFilters()
  if s.skin then
    ApplySkin()
  else
    RemoveSkin()
  end
  ApplyCopyButton()
  pcall(module.ApplyTabFade)
  if s.hide then
    ns.WhenOutOfCombat(function()
      ns.Print(("chat hidden (%d frames). Untick it to bring it back."):format(HideChat()))
    end)
  else
    ns.WhenOutOfCombat(function()
      if ShowChat() > 0 then
        ns.Print("chat is back.")
      end
    end)
  end
end

function module:OnEnable()
  for i = 1, NUM do
    HookFrame(_G["ChatFrame" .. i])
  end
  InstallFilters()
  Seed(_G.ChatFrame1)
  if Settings().skin then ApplySkin() end
  ApplyCopyButton()
  module.fadeOn = true
  HookTemporaryWindows()
  HookFontSize()
  module.ApplyTabFade()
  if Settings().hide then
    ns.WhenOutOfCombat(HideChat)
  end
end

function module:OnDisable()
  module.fadeOn = false
  pcall(module.ApplyTabFade)
  ns.WhenOutOfCombat(ShowChat)
  if copyButton then copyButton:Hide() end
end

function module:Refresh()
  Apply()
end
