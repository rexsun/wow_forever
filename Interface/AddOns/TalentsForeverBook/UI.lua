-- Talents Forever: the planner window. The site's three trees, drawn in the game's own icons, with the plan, the
-- character's real talents beside it, the leveling order, your builds, a popular build tried on your trees,
-- what changed from Classic, pick rates, racials, share links. Resizable, and it remembers where you left it.
local _, TF = ...
local D = TalentsForeverBookData
local G = TF.Game
local UI = {}
TF.UI = UI

local MEDIA = "Interface\\AddOns\\TalentsForeverBook\\Media\\"
local SKIN = MEDIA .. "skin\\"
-- the look. "glass" (default; the poll on the site chose the game's style 58 to 17) is the dark glass window with the
-- bronze line and the game's own talent art; "site" is talentsforever.com brought in game: its colours, its Cinzel
-- headings, its tree headers and rank badges, its buttons. Both draw on the own-art path.
-- one look only, the dark glass window with the game's own art. The site look was cut on 22 Sep 2026: it was hit by
-- accident and read as a different addon. A saved "site" value from an earlier build is ignored.
local function LOOK() return "glass" end
local function SkinPath() return MEDIA .. (LOOK() == "site" and "skin-site\\" or "skin\\") end
local CINZEL = "Interface\\AddOns\\TalentsForeverBook\\Fonts\\Cinzel.ttf"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BODY = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TILE, GX, GY = 40, 14, 12
local TREE_W, TREE_H = 246, 442
local TREE_HEAD = 58              -- a tree's header: the game's ring around the tree icon, the name, the points box
local TILE_X0, TILE_Y0 = 18, 70   -- the first tile: centred by eye with the rank badges' overhang, 12 under the header
local HEAD_GAP = 6                -- between the header and the trees
local SIDE_W = 340
local PAD = 12                    -- the one left edge every page of the side panel starts on
local PAGE_W = SIDE_W - PAD - 28  -- what a page has to write in: 300, up to the scroll line
local MARGIN, GAP = 12, 10        -- the game's frame has a thin edge: 12 inside it left, right and under; 10 between panels
local TOP = 26                    -- the game's title bar is 21 tall; the header starts just under it
local HEAD_H, FOOT_H = 50, 132
UI.RAIL_H = 70                    -- the rail band inside the footer: its icons, the rail and the level numbers
local TABS_H = 25                 -- the side panel's tabs stand in this: the lit tab is 24 tall to the eye, so its top meets the trees' top
local BASE_W = MARGIN * 2 + TREE_W * 3 + GAP * 2
local BASE_H = TOP + HEAD_H + HEAD_GAP + TREE_H + GAP + FOOT_H + MARGIN

local C = {
  -- gold and white are the game's own two text colours (NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR), grey its GRAY_FONT_COLOR
  gold = { 1, 0.82, 0 }, gold2 = { 0.78, 0.61, 0.10 }, green = { 0.31, 0.75, 0.23 }, blue = { 0.35, 0.65, 1 }, red = { 1, 0.30, 0.30 },
  purple = { 0.72, 0.55, 1 }, ink = { 1, 1, 1 }, ink2 = { 0.80, 0.80, 0.80 }, muted = { 0.5, 0.5, 0.5 }, bg = { 0.07, 0.07, 0.07 },
  panel = { 0.118, 0.118, 0.118 }, raised = { 0.15, 0.15, 0.15 }, line = { 0.23, 0.23, 0.23 },
}
local STATUS_COLOR = { new = C.gold, changed = C.blue, moved = C.purple }
local STATUS_WORD = { new = "New in Forever", changed = "Changed from Classic", moved = "Moved since Classic", same = "Same as Classic" }
local function rgb(c) return c[1], c[2], c[3] end
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function S() return TF.db.settings end
-- the game's font is wide, about 0.6 of its size per letter, and wrapped lines sit one size apart. Heights are
-- estimated with that, and the real measure wins when it is bigger, so rows never sit on each other.
local function estLines(text, width, size) return math.max(1, math.ceil(#(text or "") / math.max(8, width / (size * 0.58)))) end
local function estHeight(text, width, size) return estLines(text, width, size) * size * 1.1 end

-- ---------- small builders ----------
local hasBackdrop = BackdropTemplateMixin ~= nil
local function Frame(kind, name, parent, template)
  if hasBackdrop then template = template and (template .. ",BackdropTemplate") or "BackdropTemplate" end
  return CreateFrame(kind or "Frame", name, parent, template)
end
local function Backdrop(f, bg, border, alpha)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
  if border then f:SetBackdropBorderColor(border[1], border[2], border[3], 1) else f:SetBackdropBorderColor(0, 0, 0, 0) end
end
-- every word is in the game's own face, with the game's one-pixel shadow under it, so the window reads as part of the game
local function Font(fs, size, display, flags)
  if display and (LOOK() == "site" or size >= 14) then
    local ok = pcall(fs.SetFont, fs, CINZEL, size, flags or "")
    if ok then return fs end
  end
  fs:SetFont(BODY, size, flags or "")
  return fs
end
local function Text(parent, size, color, display, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  Font(fs, size, display)
  fs:SetTextColor(rgb(color or C.ink))
  fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
  fs:SetJustifyH("LEFT")
  return fs
end
-- ---------- the game's own parts ----------
-- The window is made of what the game makes its own windows of: its frame with the round portrait and the title bar,
-- its red buttons, its close, its checkboxes, its input boxes, its dropdown, its tab art. They are asked for by name, so
-- they are the real thing and follow whatever art the client ships. Where a client does not have one, the plate further
-- down stands in, so the window always opens.
-- OWN_LOOK: the window wears its own glass skin instead of the game's stock frame and red buttons. The game's own
-- pieces that are better than anything we could draw (the dropdown list, text boxes, checkboxes, tooltips, the talent
-- node art) stay the game's.
local OWN_LOOK = true
local OWN = { PortraitFrameTemplate = true, PortraitFrameFlatTemplate = true, UIPanelButtonTemplate = true, UIPanelCloseButton = true, InsetFrameTemplate = true }
local function Native(kind, name, parent, template)
  if OWN_LOOK and template and OWN[template] then return nil end
  if template == "WowStyle1DropdownTemplate" and LOOK() == "site" then return nil end
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f end
  return nil
end
local function AtlasOK(name)
  local ok, info = pcall(function() return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) end)
  return ok and info ~= nil
end
local function Atlas(tex, name, w, h)
  if not AtlasOK(name) then return false end
  local ok = pcall(tex.SetAtlas, tex, name, false)
  if ok and w then tex:SetSize(w, h) end
  return ok
end
-- the game's own talent node art is there: tiles, arrows and the class painting come from it
local GAME_NODES = AtlasOK("talents-node-square-yellow")
local function FontObject(fs, obj, size)
  if obj and fs.SetFontObject then fs:SetFontObject(obj) else Font(fs, size or 12) end
end
local function Solid(parent, layer, color, alpha, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  t:SetTexture(WHITE); t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
  return t
end
local function Gradient(t, o, r1, g1, b1, a1, r2, g2, b2, a2)
  if t.SetGradient and CreateColor then t:SetGradient(o, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
  elseif t.SetGradientAlpha then t:SetGradientAlpha(o, r1, g1, b1, a1, r2, g2, b2, a2) else t:SetVertexColor(r1, g1, b1, (a1 + a2) / 2) end
end
local function Sound(key)
  if TF.db and TF.db.settings.sounds == false then return end
  local id = SOUNDKIT and SOUNDKIT[key]
  if id then pcall(PlaySound, id) end
end
-- a crisp one-pixel frame around a region, from four plain edges, so it stays sharp at any window scale
local function Edges(parent, region, layer, sub)
  local e = {}
  local function one() local t = parent:CreateTexture(nil, layer or "BORDER", nil, sub or 0); t:SetTexture(WHITE); e[#e + 1] = t; return t end
  local top, bottom, left, right = one(), one(), one(), one()
  top:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
  bottom:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
  left:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, 0)
  right:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
  local function thin(t, horiz)
    if PixelUtil and PixelUtil.SetHeight then if horiz then PixelUtil.SetHeight(t, 1, 1) else PixelUtil.SetWidth(t, 1, 1) end
    elseif horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  thin(top, true); thin(bottom, true); thin(left, false); thin(right, false)
  function e:SetColor(r, g, b, a) for _, t in ipairs(self) do t:SetVertexColor(r, g, b, a or 1) end end
  return e
end
-- A plate: what every button, tab and close in the window is made of. Crisp rectangles, so every edge is exactly one
-- pixel on every button at every size (a stretched outline image never is). A body that runs from light to dark, a lit
-- top edge, a dark bottom edge, a line of shadow under it; gold trim and a wash of light under the mouse (the HIGHLIGHT
-- layer, so no script can lose it); the body turns over while it is held; grey when it cannot be pressed.
local PLATE = {
  dark  = { top = { 0.150, 0.140, 0.125 }, bot = { 0.075, 0.070, 0.062 }, edge = { 0.47, 0.36, 0.14, 1 }, hi = { 1, 0.92, 0.70, 0.10 }, lo = { 0, 0, 0, 0.5 } },
  gold  = { top = { 1.000, 0.860, 0.420 }, bot = { 0.740, 0.550, 0.080 }, edge = { 0.34, 0.24, 0.02, 1 }, hi = { 1, 1, 0.86, 0.65 }, lo = { 0.35, 0.22, 0, 0.55 } },
  quiet = { top = { 0.105, 0.100, 0.092 }, bot = { 0.060, 0.058, 0.054 }, edge = { 0.30, 0.24, 0.11, 1 }, hi = { 1, 1, 1, 0.05 }, lo = { 0, 0, 0, 0.40 } },
}
local function ApplyLook()
  GAME_NODES = AtlasOK("talents-node-square-yellow") and LOOK() ~= "site"
  if LOOK() == "site" then
    -- the site's own colours, in place so every table that holds one of these follows
    local function set(c, r, g, b) c[1], c[2], c[3] = r, g, b end
    set(C.gold, 1, 0.84, 0.37); set(C.green, 0.12, 1, 0); set(C.blue, 0.35, 0.65, 1); set(C.red, 1, 0.30, 0.30)
    set(C.ink, 0.91, 0.91, 0.91); set(C.ink2, 0.74, 0.74, 0.74); set(C.muted, 0.54, 0.54, 0.54)
    set(C.bg, 0.07, 0.07, 0.07); set(C.panel, 0.118, 0.118, 0.118); set(C.raised, 0.15, 0.15, 0.15); set(C.line, 0.23, 0.23, 0.23)
    PLATE.dark = { top = { 0.23, 0.23, 0.23 }, bot = { 0.22, 0.22, 0.22 }, edge = { 0.23, 0.23, 0.23, 1 }, hi = { 1, 1, 1, 0.04 }, lo = { 0, 0, 0, 0.35 } }
    PLATE.quiet = { top = { 0.10, 0.10, 0.10 }, bot = { 0.09, 0.09, 0.09 }, edge = { 0.20, 0.20, 0.20, 1 }, hi = { 1, 1, 1, 0.03 }, lo = { 0, 0, 0, 0.3 } }
    PLATE.gold = { top = { 1.0, 0.82, 0.0 }, bot = { 0.87, 0.69, 0.0 }, edge = { 0.36, 0.27, 0.02, 1 }, hi = { 1, 1, 0.8, 0.5 }, lo = { 0.3, 0.2, 0, 0.5 } }
    TOP = 44
    BASE_H = TOP + HEAD_H + HEAD_GAP + TREE_H + GAP + FOOT_H + MARGIN
  end
end
local function onePixel(t, horiz)
  if PixelUtil and PixelUtil.SetHeight then if horiz then PixelUtil.SetHeight(t, 1, 1) else PixelUtil.SetWidth(t, 1, 1) end
  elseif horiz then t:SetHeight(1) else t:SetWidth(1) end
end
local function Plate(b, kind, noDrop)
  local P = { kind = kind }
  local function tex(layer, sub) local t = b:CreateTexture(nil, layer, nil, sub or 0); t:SetTexture(WHITE); return t end
  if not noDrop then
    P.drop = tex("BACKGROUND", -2); P.drop:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 1, 0); P.drop:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -1, 0); onePixel(P.drop, true); P.drop:SetVertexColor(0, 0, 0, 0.55)
  end
  P.body = tex("BACKGROUND", 0); P.body:SetPoint("TOPLEFT", 1, -1); P.body:SetPoint("BOTTOMRIGHT", -1, 1)
  -- the trim stops a pixel short of each corner, which rounds the plate by exactly one pixel
  local spec = { { "TOPLEFT", 1, 0, "TOPRIGHT", -1, 0, true }, { "BOTTOMLEFT", 1, 0, "BOTTOMRIGHT", -1, 0, true }, { "TOPLEFT", 0, -1, "BOTTOMLEFT", 0, 1, false }, { "TOPRIGHT", 0, -1, "BOTTOMRIGHT", 0, 1, false } }
  P.edges = {}
  for k, e in ipairs(spec) do
    local t = tex("BORDER", 0); t:SetPoint(e[1], e[2], e[3]); t:SetPoint(e[4], e[5], e[6]); onePixel(t, e[7]); P.edges[k] = t
    local h = tex("HIGHLIGHT", 1); h:SetPoint(e[1], e[2], e[3]); h:SetPoint(e[4], e[5], e[6]); onePixel(h, e[7]); h:SetVertexColor(1, 0.86, 0.42, 1)
  end
  P.hi = tex("BORDER", 1); P.hi:SetPoint("TOPLEFT", 1, -1); P.hi:SetPoint("TOPRIGHT", -1, -1); onePixel(P.hi, true)
  P.lo = tex("BORDER", 1); P.lo:SetPoint("BOTTOMLEFT", 1, 1); P.lo:SetPoint("BOTTOMRIGHT", -1, 1); onePixel(P.lo, true)
  local wash = tex("HIGHLIGHT", 0); wash:SetPoint("TOPLEFT", 1, -1); wash:SetPoint("BOTTOMRIGHT", -1, 1); wash:SetBlendMode("ADD")
  Gradient(wash, "VERTICAL", 1, 0.82, 0, 0.05, 1, 0.82, 0, 0.24)
  function P:Paint(kind2, state)
    self.kind = kind2 or self.kind
    local c = PLATE[self.kind] or PLATE.dark
    if state == "off" then
      Gradient(self.body, "VERTICAL", 0.095, 0.095, 0.095, 1, 0.145, 0.145, 0.145, 1)
      for _, t in ipairs(self.edges) do t:SetVertexColor(0.25, 0.25, 0.25, 1) end
      self.hi:SetVertexColor(1, 1, 1, 0.04); self.lo:SetVertexColor(0, 0, 0, 0.3)
      return
    end
    local top, bot = c.top, c.bot
    if state == "down" then top, bot = c.bot, c.top end
    Gradient(self.body, "VERTICAL", bot[1], bot[2], bot[3], 1, top[1], top[2], top[3], 1)
    for _, t in ipairs(self.edges) do t:SetVertexColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4]) end
    self.hi:SetVertexColor(c.hi[1], c.hi[2], c.hi[3], state == "down" and 0 or c.hi[4])
    self.lo:SetVertexColor(c.lo[1], c.lo[2], c.lo[3], c.lo[4])
  end
  P:Paint(kind)
  return P
end
-- Buttons come in two heights, 24 and 20, and nothing else. w = "auto": as wide as the words plus the same padding
-- either side (16, or 12 on the small ones), rounded up to the 8 grid with a floor (80, or 56), so neighbours match
-- instead of each hugging its own words. minW raises the floor; Fit() runs again whenever the words change.
local NOPLATE = { Paint = function() end }
-- a Copy button cannot copy (no addon can write the clipboard): after the click it says the key to press, for a moment
function UI.CopyCue(b)
  b.cueLabel = b.cueLabel or b:GetText() or "Select"
  b:SetText("Ctrl+C"); b.cueAt = GetTime()
  C_Timer.After(6, function() if b.cueAt and GetTime() - b.cueAt >= 5.9 then b:SetText(b.cueLabel); b.cueAt = nil end end)
end
local function Button(parent, label, w, h, onClick, primary)
  h = h or 24
  local small = h < 24
  local b = Native("Button", nil, parent, "UIPanelButtonTemplate")
  if b then
    -- the game's red button, at the game's own height: 22, and 20 for the small ones in rows
    b.native = true; b.kind = primary and "gold" or "dark"; b.plate = NOPLATE
    b:SetSize(tonumber(w) or 96, small and 20 or 22)
    if small and b.SetNormalFontObject and GameFontNormalSmall then
      b:SetNormalFontObject(GameFontNormalSmall); b:SetHighlightFontObject(GameFontHighlightSmall); b:SetDisabledFontObject(GameFontDisableSmall)
    end
    b:SetText(label)
    b.label = b.Text or (b.GetFontString and b:GetFontString())
    function b:Ink() end
  else
    b = CreateFrame("Button", nil, parent)
    b:SetSize(tonumber(w) or 96, h)
    b.kind = primary and "gold" or "dark"
    b.plate = Plate(b, b.kind)
    b.label = b:CreateFontString(nil, "OVERLAY"); Font(b.label, small and 11 or 13); b.label:SetPoint("CENTER", 0, 0); b.label:SetJustifyH("CENTER")
    b.label:SetShadowOffset(primary and 0 or 1, -1)
    b:SetFontString(b.label); b:SetText(label)
    if b.SetPushedTextOffset then b:SetPushedTextOffset(0, -1) end
    function b:Ink()
      if not self:IsEnabled() then self.label:SetTextColor(0.43, 0.43, 0.43); self.label:SetShadowColor(0, 0, 0, 0.6)
      elseif self.kind == "gold" then self.label:SetTextColor(0.13, 0.09, 0.01); self.label:SetShadowColor(1, 0.93, 0.62, 0.45)
      elseif LOOK() == "site" then self.label:SetTextColor(0.96, 0.96, 0.96); self.label:SetShadowColor(0, 0, 0, 0.8)
      else self.label:SetTextColor(1, 0.86, 0.45); self.label:SetShadowColor(0, 0, 0, 0.9) end
    end
    b:Ink()
    b:SetScript("OnEnable", function(self) self.plate:Paint(self.kind); self:Ink() end)
    b:SetScript("OnDisable", function(self) self.plate:Paint(self.kind, "off"); self:Ink() end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.plate:Paint(self.kind, "down"); self.label:SetPoint("CENTER", math.floor(((self.iconW or 0)) / 2), -1) end end)
    b:SetScript("OnMouseUp", function(self) if self:IsEnabled() then self.plate:Paint(self.kind); self.label:SetPoint("CENTER", math.floor(((self.iconW or 0)) / 2), 0) end end)
    -- hover: the words go white (gold ones a shade lighter), the plate's wash and gold rim come up on their own
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then if self.kind == "gold" then self.label:SetTextColor(0.05, 0.03, 0) else self.label:SetTextColor(1, 1, 1) end end end)
    b:HookScript("OnLeave", function(self) self:Ink() end)
  end
  b.primary = primary
  if w == "auto" then
    b.pad = small and 12 or 16
    b.minW = small and 56 or 80
    function b:Fit() local need = ((self.label and self.label:GetStringWidth()) or 40) + self.pad * 2 + (self.iconW or 0); self:SetWidth(math.max(self.minW, math.ceil(need / 8) * 8)) end
    b:Fit()
    if hooksecurefunc then pcall(hooksecurefunc, b, "SetText", function(self) self:Fit() end) end
  end
  b:SetScript("OnClick", function(self, btn) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); onClick(self, btn) end)
  -- a small picture at the left edge; the words shift right to make room, and auto widths count it
  function b:SetIcon(path, coords)
    if not path then if self.icon then self.icon:Hide() end; if self.label then self.label:ClearAllPoints(); self.label:SetPoint("CENTER", 0, 0) end; self.iconW = 0; if self.Fit then self:Fit() end; return end
    local sz = (self:GetHeight() or 22) - 8
    if not self.icon then self.icon = self:CreateTexture(nil, "OVERLAY"); self.icon:SetPoint("LEFT", 7, 0) end
    self.icon:SetSize(sz, sz); self.icon:SetTexture(path); self.icon:SetShown(true)
    if coords then self.icon:SetTexCoord(unpack(coords)) else self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    if self.label then self.label:ClearAllPoints(); self.label:SetPoint("CENTER", math.floor((sz + 4) / 2), 0) end
    self.iconW = sz + 4
    if self.Fit then self:Fit() end
  end
  return b
end
-- one step back or forward: the game's own page arrows (the spellbook's), so a level or a size steps like a page does
-- a slider of our own: a dark bar with a gold knob, whole numbers between lo and hi. get() reads the value, set(v) applies it.
function UI.Slider(parent, w, lo, hi, get, set)
  local s = CreateFrame("Button", nil, parent); s:SetSize(w, 20); s.lo, s.hi = lo, hi
  s.bar = s:CreateTexture(nil, "ARTWORK"); s.bar:SetTexture(WHITE); s.bar:SetVertexColor(0.16, 0.14, 0.10, 1); s.bar:SetHeight(6); s.bar:SetPoint("LEFT", 6, 0); s.bar:SetPoint("RIGHT", -6, 0)
  s.barEdge = Edges(s, s.bar, "ARTWORK", 1); s.barEdge:SetColor(0.47, 0.36, 0.14, 0.9)
  s.fill = s:CreateTexture(nil, "ARTWORK", nil, 2); s.fill:SetTexture(WHITE); s.fill:SetVertexColor(0.78, 0.61, 0.10, 0.8); s.fill:SetHeight(4); s.fill:SetPoint("LEFT", s.bar, "LEFT", 1, 0); s.fill:SetWidth(1)
  s.knob = s:CreateTexture(nil, "OVERLAY"); s.knob:SetTexture(WHITE); s.knob:SetSize(10, 16); s.knob:SetVertexColor(1, 0.82, 0, 1); s.knob:SetPoint("CENTER", s.bar, "LEFT", 0, 0)
  s.knobEdge = Edges(s, s.knob, "OVERLAY", 1); s.knobEdge:SetColor(0.3, 0.2, 0.02, 1)
  local function span() return math.max(1, (s.bar:GetWidth() or (w - 12))) end
  function s:Sync()
    local v = math.max(lo, math.min(hi, get() or lo)); self.value = v
    local px = (v - lo) / (hi - lo) * span()
    self.knob:ClearAllPoints(); self.knob:SetPoint("CENTER", self.bar, "LEFT", px, 0); self.fill:SetWidth(math.max(1, px))
  end
  local function atCursor()
    local cx = GetCursorPosition(); local es = s:GetEffectiveScale() or 1
    local left = (s.bar:GetLeft() or 0) * es
    local v = lo + ((cx - left) / es) / span() * (hi - lo)
    v = math.floor(math.max(lo, math.min(hi, v)) + 0.5)
    if v ~= s.value then set(v); s:Sync() end
  end
  s:SetScript("OnMouseDown", function(self) atCursor(); self:SetScript("OnUpdate", atCursor) end)
  s:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil); Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end)
  s:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
  s:EnableMouseWheel(true); s:SetScript("OnMouseWheel", function(self, d) local v = math.max(lo, math.min(hi, (self.value or lo) + (d > 0 and 1 or -1))); set(v); self:Sync() end)
  s:Sync()
  return s
end
local function Stepper(parent, forward, onClick)
  local b = CreateFrame("Button", nil, parent); b:SetSize(24, 24)
  local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (forward and "NextPage" or "PrevPage")
  b:SetNormalTexture(base .. "-Up"); b:SetPushedTexture(base .. "-Down"); b:SetDisabledTexture(base .. "-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function(self, btn) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); onClick(self, btn) end)
  return b
end
-- a close: the game's red X. On the window it is the frame's own; this one is for the cards and the rows
local function CloseX(parent, size)
  size = size or 20
  local n = Native("Button", nil, parent, "UIPanelCloseButton")
  if n then
    n.native = true; n.plate = NOPLATE
    n:SetSize(size + 4, size + 4); n:SetFrameLevel(parent:GetFrameLevel() + 2)   -- the template asks for level 510; a row's close belongs to its row
    return n
  end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.plate = Plate(b, "quiet", true)
  local pt = size >= 20 and 11 or 9
  b.x = b:CreateFontString(nil, "OVERLAY"); Font(b.x, pt, true); b.x:SetPoint("CENTER", 0, 0); b.x:SetText("X"); b.x:SetTextColor(0.80, 0.72, 0.54)
  b.xh = b:CreateFontString(nil, "HIGHLIGHT"); Font(b.xh, pt, true); b.xh:SetPoint("CENTER", 0, 0); b.xh:SetText("X"); b.xh:SetTextColor(1, 0.92, 0.6)
  b:SetScript("OnMouseDown", function(self) self.plate:Paint("quiet", "down") end)
  b:SetScript("OnMouseUp", function(self) self.plate:Paint("quiet") end)
  return b
end
-- the stock scroll bar goes away; a thin gold line on the right says where you are. The wheel still scrolls.
local function ScrollFade(sc)
  local f = CreateFrame("Frame", nil, sc); f:SetFrameLevel((sc:GetFrameLevel() or 1) + 6)
  f:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0); f:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0); f:SetHeight(18)
  f.tex = f:CreateTexture(nil, "OVERLAY"); f.tex:SetAllPoints(); f.tex:SetTexture(WHITE); Gradient(f.tex, "VERTICAL", 0, 0, 0, 0.85, 0, 0, 0, 0)
  f:EnableMouse(false)
  sc.fade = f
  return f
end
local function Slim(sc)
  ScrollFade(sc)
  local bar = sc.ScrollBar or (sc:GetName() and _G[sc:GetName() .. "ScrollBar"])
  if type(bar) == "table" then
    bar:Hide(); bar:SetAlpha(0)
    if hooksecurefunc then pcall(hooksecurefunc, bar, "Show", function(b) b:Hide() end) end
  end
  sc.track = sc:CreateTexture(nil, "OVERLAY"); sc.track:SetTexture(WHITE); sc.track:SetVertexColor(1, 0.82, 0, 0.1); sc.track:SetWidth(2)
  sc.track:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 16, 0); sc.track:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 16, 0)
  sc.thumb = sc:CreateTexture(nil, "OVERLAY", nil, 1); sc.thumb:SetTexture(WHITE); sc.thumb:SetVertexColor(1, 0.82, 0, 0.75); sc.thumb:SetWidth(2); sc.thumb:SetHeight(20)
  local function upd()
    local range = sc:GetVerticalScrollRange() or 0; local h = sc:GetHeight() or 1
    if range <= 1 then sc.track:Hide(); sc.thumb:Hide(); if sc.fade then sc.fade:Hide() end; return end
    sc.track:Show(); sc.thumb:Show()
    local th = math.max(16, h * h / (h + range)); sc.thumb:SetHeight(th)
    local pos = math.min(1, math.max(0, (sc:GetVerticalScroll() or 0) / range))
    if sc.fade then sc.fade:SetShown(pos < 0.98) end   -- the foot fades only while there is more below
    sc.thumb:ClearAllPoints(); sc.thumb:SetPoint("TOPRIGHT", sc.track, "TOPRIGHT", 0, -(h - th) * pos)
  end
  sc:HookScript("OnScrollRangeChanged", upd); sc:HookScript("OnVerticalScroll", upd); sc:HookScript("OnShow", upd)
  upd()
  return sc
end
-- the tome: a leather cover with gold tooling around a dark page. Four corners, four edges, the page grain
-- tiled underneath and a vignette over it. size is the corner size: 64 for the window, 40 for cards.
local function Skin(f, size)
  size = size or 64
  local inset = size * 0.3
  local function tex(name, layer, sub)
    local t = f:CreateTexture(nil, layer or "BORDER", nil, sub or 0); t:SetTexture(SkinPath() .. name); return t
  end
  f.page = f:CreateTexture(nil, "BACKGROUND", nil, -8); f.page:SetTexture(SkinPath() .. "page.png", "REPEAT", "REPEAT")
  f.page:SetPoint("TOPLEFT", inset, -inset); f.page:SetPoint("BOTTOMRIGHT", -inset, inset)
  if f.page.SetHorizTile then f.page:SetHorizTile(true); f.page:SetVertTile(true) end
  f.vignette = tex("vignette.png", "BACKGROUND", -7); f.vignette:SetPoint("TOPLEFT", inset, -inset); f.vignette:SetPoint("BOTTOMRIGHT", -inset, inset)
  f.cover = {}
  local tl = tex("cover-tl.png"); tl:SetSize(size, size); tl:SetPoint("TOPLEFT")
  local tr = tex("cover-tr.png"); tr:SetSize(size, size); tr:SetPoint("TOPRIGHT")
  local bl = tex("cover-bl.png"); bl:SetSize(size, size); bl:SetPoint("BOTTOMLEFT")
  local br = tex("cover-br.png"); br:SetSize(size, size); br:SetPoint("BOTTOMRIGHT")
  local top = tex("cover-top.png"); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local bottom = tex("cover-bottom.png"); bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = tex("cover-left.png"); left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local right = tex("cover-right.png"); right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  for _, t in ipairs({ top, bottom }) do t:SetTexture(SkinPath() .. (t == top and "cover-top.png" or "cover-bottom.png"), "REPEAT", "CLAMP"); if t.SetHorizTile then t:SetHorizTile(true) end end
  for _, t in ipairs({ left, right }) do t:SetTexture(SkinPath() .. (t == left and "cover-left.png" or "cover-right.png"), "CLAMP", "REPEAT"); if t.SetVertTile then t:SetVertTile(true) end end
  f.cover = { tl, tr, bl, br, top, bottom, left, right }
  return f
end
-- a card that stands on its own outside the window wears the game's tooltip: its border, its dark glass
local function Card(f)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.96); f:SetBackdropBorderColor(0.9, 0.75, 0.4, 1)
  else Skin(f, 32) end
end
-- Where a tooltip opens. One rule, the site's, so the hand learns it once:
--   a talent tile: just off its right edge, level with its top, the way the game and Wowhead do it; off its left edge
--     when the screen ends on the right. Never over the tile, never over the tiles under it in the same column.
--   anything on the side panel (a row, a button, a checkbox): level with it, just outside the panel, over the third
--     tree, so the list you are reading and the thing you are on both stay clear; to the panel's right when the
--     screen has room there. Never far away: the panel's edge is the nearest place that hides nothing of the list.
--   a word, button or box anywhere else (header, footer): under it, left edges level; above it when the screen ends
--     below. Never over the box you are typing in or the arrow you are pressing.
-- Pushed back in from the screen's edges, so nothing is ever cut off.
-- our tooltip is the thing being read: solid dark behind the words, a size up, a gold rim. The game's own style comes
-- back the moment it hides, so no other addon's tooltip is touched.
local function TipStyle(tt)
  tt:SetAlpha(1)
  if not tt.tfBack then
    tt.tfBack = tt:CreateTexture(nil, "BACKGROUND", nil, -8); tt.tfBack:SetTexture(WHITE); tt.tfBack:SetVertexColor(0.02, 0.02, 0.04, 0.80)
    tt.tfBack:SetPoint("TOPLEFT", 3, -3); tt.tfBack:SetPoint("BOTTOMRIGHT", -3, 3)
  end
  tt.tfBack:Show()
  -- the game's own fill steps aside so the plate's number is the whole story; it comes back when the tooltip hides
  local ns = tt.NineSlice
  if type(ns) == "table" then
    if ns.SetBorderColor then pcall(ns.SetBorderColor, ns, 0.85, 0.70, 0.35, 1) end
    if ns.SetCenterColor then pcall(ns.SetCenterColor, ns, 0, 0, 0, 0) end
    if type(ns.Center) == "table" and ns.Center.SetAlpha then pcall(ns.Center.SetAlpha, ns.Center, 0) end
  elseif tt.SetBackdropColor then pcall(tt.SetBackdropColor, tt, 0, 0, 0, 0); pcall(tt.SetBackdropBorderColor, tt, 0.85, 0.70, 0.35, 1) end
end
local function TipBegin(owner)
  local tt = GameTooltip
  if not tt.tfScale then tt.tfScale = tt:GetScale() or 1; tt:SetScale(tt.tfScale * 1.06) end
  tt:SetOwner(owner, "ANCHOR_NONE"); tt:ClearAllPoints(); tt:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
end
if GameTooltip.HookScript then
  GameTooltip:HookScript("OnHide", function(tt)
    if tt.tfScale then tt:SetScale(tt.tfScale); tt.tfScale = nil; if SharedTooltip_SetBackdropStyle then pcall(SharedTooltip_SetBackdropStyle, tt, nil, tt.IsEmbedded) end end
    if tt.tfBack then tt.tfBack:Hide() end
    local ns = tt.NineSlice
    if type(ns) == "table" and type(ns.Center) == "table" and ns.Center.SetAlpha then pcall(ns.Center.SetAlpha, ns.Center, 1) end
    UI.hoverTile = nil
    if UI.peekLevel and UI.LevelPeek then UI.LevelPeek(nil) end
  end)
end
local function inSide(f) while f do if f == UI.sideFrame then return true end; f = f.GetParent and f:GetParent() or nil end; return false end
local function TipEnd(owner, mode)
  local tt = GameTooltip
  tt:Show()
  local ts, us, os_ = tt:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1, owner:GetEffectiveScale() or 1
  local sw, sh = (GetScreenWidth and GetScreenWidth() or 1920) * us, (GetScreenHeight and GetScreenHeight() or 1080) * us
  local l, r, top, bot = (owner:GetLeft() or 0) * os_, (owner:GetRight() or 0) * os_, (owner:GetTop() or 0) * os_, (owner:GetBottom() or 0) * os_
  local w, h = (tt:GetWidth() or 300) * ts, (tt:GetHeight() or 100) * ts
  local gap = 6
  if not mode then mode = (inSide(owner) and "panel") or (owner.ti and owner.i and "beside") or ((top - bot) >= 40 and "beside" or "under") end
  local x, y
  if mode == "panel" and UI.sideFrame then
    local ss = UI.sideFrame:GetEffectiveScale() or 1
    local sl, sr = (UI.sideFrame:GetLeft() or 0) * ss, (UI.sideFrame:GetRight() or 0) * ss
    local fr = (F and F:GetRight() or sr / ss) * (F and F:GetEffectiveScale() or ss)
    x, y = fr + gap, top + 2
    if x + w > sw - 8 then x = sl - gap - w end
    if x < 8 then x = sr + gap end
  elseif mode == "beside" then
    x, y = r + gap, top
    -- to the tile's left when the screen ends, or when the right side would lie over the side panel's words
    local sl = UI.sideFrame and UI.sideFrame:IsShown() and (UI.sideFrame:GetLeft() or 0) * (UI.sideFrame:GetEffectiveScale() or 1) or nil
    if x + w > sw - 8 or (sl and x + w > sl + 24 and l - gap - w > 8) then x = l - gap - w end
  elseif mode == "drawer" and UI.drawer then
    local ds = UI.drawer:GetEffectiveScale() or 1
    local dl, dr = (UI.drawer:GetLeft() or 0) * ds, (UI.drawer:GetRight() or 0) * ds
    local fl = (F and F:GetLeft() or 0) * (F and F:GetEffectiveScale() or 1)
    y = top + 2
    if dl >= fl then x = dr + gap; if x + w > sw - 8 then local ss = UI.sideFrame and UI.sideFrame:GetEffectiveScale() or 1; x = ((UI.sideFrame and UI.sideFrame:GetLeft()) or dl) * ss - gap - w end
    else x = dl - gap - w; if x < 8 then x = dr + gap end end
  elseif mode == "above" then
    x, y = l, top + gap + h
    if y > sh - 8 then y = bot - gap end
    if x + w > sw - 8 then x = sw - 8 - w end
  else
    x, y = l, bot - gap
    if y - h < 8 then y = top + gap + h end
    if x + w > sw - 8 then x = sw - 8 - w end
  end
  if y - h < 8 then y = h + 8 end
  if y > sh - 8 then y = sh - 8 end
  if x < 8 then x = 8 end
  tt:ClearAllPoints(); tt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / ts, y / ts)
  TipStyle(tt)
end
UI.TipBegin, UI.TipEnd = TipBegin, TipEnd
local function Tip(frame, title, body, mode)
  frame:SetScript("OnEnter", function(self)
    TipBegin(self); GameTooltip:SetText(title, 1, 0.82, 0)
    if body then GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true) end
    TipEnd(self, mode)
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- a checkbox drawn like a small tile: dark slot, gold rim when on, a gold tick
local function Check(parent, label, get, set)
  local n = Native("CheckButton", nil, parent, "UICheckButtonTemplate")
  if n then
    -- the game's checkbox; its art has four pixels of air around the box, so callers pull it left by n.air
    n.native = true; n.air = 4
    n:SetSize(26, 26)
    n.label = n.Text or n:CreateFontString(nil, "ARTWORK")
    FontObject(n.label, GameFontNormal, 12)
    n.label:ClearAllPoints(); n.label:SetPoint("LEFT", n, "RIGHT", 2, 1); n.label:SetText(label)
    if n.SetHitRectInsets then n:SetHitRectInsets(0, -((n.label:GetStringWidth() or 60) + 4), 0, 0) end   -- the words click too
    n.get = get
    n:SetChecked(get() and true or false)
    n:SetScript("OnClick", function(self)
      local on = self:GetChecked() and true or false
      set(on); Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF"); UI.Refresh()
    end)
    return n
  end
  local cb = CreateFrame("Button", nil, parent)
  cb:SetSize(18, 18)
  cb.box = cb:CreateTexture(nil, "BACKGROUND"); cb.box:SetTexture(WHITE); cb.box:SetAllPoints()
  cb.edge = Edges(cb, cb, "BORDER", 0)
  cb.tick = cb:CreateTexture(nil, "ARTWORK"); cb.tick:SetTexture(MEDIA .. "check.tga"); cb.tick:SetSize(12, 12); cb.tick:SetPoint("CENTER", 0, 0); cb.tick:SetVertexColor(1, 0.82, 0)
  cb:SetHighlightTexture(WHITE); local hl = cb:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 0.82, 0, 0.15) end
  cb.label = Text(parent, 13, C.ink); cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0); cb.label:SetText(label)
  function cb:SetChecked(v)
    self.on = v and true or false; self.tick:SetShown(self.on)
    if self.on then self.box:SetVertexColor(0.16, 0.12, 0.03, 1); self.edge:SetColor(1, 0.82, 0, 1)
    else self.box:SetVertexColor(0.05, 0.05, 0.05, 1); self.edge:SetColor(0.78, 0.61, 0.10, 0.65) end
  end
  function cb:GetChecked() return self.on end
  cb.get = get
  cb:SetChecked(get())
  cb:SetScript("OnClick", function(self) self:SetChecked(not self.on); set(self.on); Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); UI.Refresh() end)
  return cb
end
-- an edit box in the window's own skin: a dark well, a gold hairline that brightens with focus
local function EditBox(parent, w, h)
  local n = Native("EditBox", nil, parent, "InputBoxTemplate")
  if n then
    -- the game's input box. Its art is 20 tall whatever the box is, and its left end hangs 5 outside: pulled in here so
    -- the box starts on the page's edge like everything else
    n.native = true
    n:SetSize(w, h or 24); n:SetAutoFocus(false)
    if n.Left then n.Left:ClearAllPoints(); n.Left:SetPoint("LEFT", 0, 0) end
    n:SetTextInsets(8, 8, 0, 0)
    n.edge = { SetColor = function() end }
    n.hint = n:CreateFontString(nil, "OVERLAY"); FontObject(n.hint, GameFontDisable, 12); n.hint:SetPoint("LEFT", 8, 0); n.hint:SetJustifyH("LEFT")
    n:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    n:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    n:SetScript("OnEditFocusGained", function(self) if self.selectAll then self:HighlightText() end end)
    n:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    return n
  end
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, h or 24); e:SetAutoFocus(false)
  e:SetFont(BODY, 12, ""); e:SetTextColor(0.91, 0.91, 0.91); e:SetTextInsets(8, 8, 0, 0)
  e.bg = e:CreateTexture(nil, "BACKGROUND"); e.bg:SetTexture(WHITE); e.bg:SetAllPoints(); e.bg:SetVertexColor(0.03, 0.03, 0.03, 0.92)
  e.edge = Edges(e, e, "BORDER", 0); e.edge:SetColor(0.78, 0.61, 0.10, 0.45)
  e.hint = e:CreateFontString(nil, "OVERLAY"); Font(e.hint, 12); e.hint:SetTextColor(0.54, 0.54, 0.54); e.hint:SetPoint("LEFT", 8, 0); e.hint:SetJustifyH("LEFT")
  e:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) self.edge:SetColor(1, 0.82, 0, 0.95); if self.selectAll then self:HighlightText() end end)
  e:SetScript("OnEditFocusLost", function(self) self.edge:SetColor(0.78, 0.61, 0.10, 0.45); self:HighlightText(0, 0) end)
  return e
end
-- the class crest from the game's own sheet; the first tree's icon where the sheet is not there
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function SetClassIcon(tex, cf)
  local cd0 = TalentsForeverBookData.classes[cf]
  if cd0 then
    local ok, r = pcall(tex.SetTexture, tex, "Interface\\Icons\\ClassIcon_" .. cd0.name)
    if ok and r ~= false then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); return end
  end
  local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
  if tc then
    tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"); tex:SetTexCoord(tc[1] + 0.012, tc[2] - 0.012, tc[3] + 0.012, tc[4] - 0.012)
  else
    local cd = TalentsForeverBookData.classes[cf]
    tex:SetTexture("Interface\\Icons\\" .. ((cd and cd.trees[1].icon) or "inv_misc_questionmark")); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
end
local function Book(parent, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK"); t:SetSize(size, size)
  local ok, r = pcall(t.SetTexture, t, MEDIA .. "book-round.tga")
  if not ok or r == false then t:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  return t
end

-- ---------- motion ----------
-- a small tween engine: one driver frame, every tween eased, keyed so a new tween on the same thing replaces the old.
-- Animation groups stay for loops (pulses, motes, mist); tweens do the one-off moves that must end exactly where they aim.
local Motion = { list = {}, byKey = {} }
local driver = CreateFrame("Frame")
local EASE = {
  out = function(u) return 1 - (1 - u) ^ 3 end,
  out4 = function(u) return 1 - (1 - u) ^ 4 end,
  ["in"] = function(u) return u * u * u end,
  inout = function(u) return u < 0.5 and 4 * u * u * u or 1 - (-2 * u + 2) ^ 3 / 2 end,
  back = function(u) local c = 1.70158; return 1 + (c + 1) * (u - 1) ^ 3 + c * (u - 1) ^ 2 end,
  linear = function(u) return u end,
}
local function lerp(a, b, u) return a + (b - a) * u end
function Motion.Update(_, dt)
  local list = Motion.list
  local dead = 0
  for i = 1, #list do
    local tw = list[i]
    if not tw.dead then
      tw.t = tw.t + dt
      if tw.t >= 0 then
        local u = math.min(1, tw.t / tw.dur)
        tw.apply(tw.ease(u), u)
        if u >= 1 then tw.dead = true; if Motion.byKey[tw.key] == tw then Motion.byKey[tw.key] = nil end; if tw.done then tw.done() end end
      end
    end
    if tw.dead then dead = dead + 1 end
  end
  if dead > 0 then
    local keep = {}
    for _, tw in ipairs(list) do if not tw.dead then keep[#keep + 1] = tw end end
    Motion.list = keep
  end
  if #Motion.list == 0 then driver:SetScript("OnUpdate", nil) end
end
-- Tween(key, seconds, function(eased, linear) ... end, { ease = "out"|"in"|"inout"|"back"|"linear", delay = s, done = fn })
local function Tween(key, dur, apply, opts)
  opts = opts or {}
  local old = Motion.byKey[key]
  if old then old.dead = true end
  local tw = { key = key, dur = math.max(0.001, dur), t = -(opts.delay or 0), apply = apply, ease = EASE[opts.ease or "out"] or EASE.out, done = opts.done }
  Motion.byKey[key] = tw
  Motion.list[#Motion.list + 1] = tw
  driver:SetScript("OnUpdate", Motion.Update)
  return tw
end
local function StopTween(key) local old = Motion.byKey[key]; if old then old.dead = true; Motion.byKey[key] = nil end end
-- rows arrive one after another, each rising a few pixels into place (the site's spin-in)
local function SpinRows(rows, rowH, n, off)
  off = off or 0
  for k, r in ipairs(rows) do
    if k <= n and k <= 14 then
      r:SetAlpha(0)
      Tween("spin" .. tostring(r), 0.16, function(e) r:SetAlpha(e * (r.dimTo or 1)); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -off - (k - 1) * rowH - 4 * (1 - e)) end, { delay = 0.012 * k, ease = "out4" })
    elseif k <= n then r:SetAlpha(r.dimTo or 1) end
  end
end
local function Pulse(region, lo, hi, dur)
  local ag = region:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(lo); a:SetToAlpha(hi); a:SetDuration(dur or 1.2); a:SetSmoothing("IN_OUT")
  return ag
end
local function Bump(frame, amount)
  if frame.bump then frame.bump:Stop() else
    local ag = frame:CreateAnimationGroup()
    local up = ag:CreateAnimation("Scale"); up:SetDuration(0.09); up:SetOrder(1); up:SetSmoothing("OUT")
    local down = ag:CreateAnimation("Scale"); down:SetDuration(0.16); down:SetOrder(2); down:SetSmoothing("IN")
    local s = amount or 1.22
    if up.SetScaleFrom then up:SetScaleFrom(1, 1); up:SetScaleTo(s, s); down:SetScaleFrom(s, s); down:SetScaleTo(1, 1)
    else up:SetScale(s, s); down:SetScale(1 / s, 1 / s) end
    if up.SetOrigin then up:SetOrigin("CENTER", 0, 0); down:SetOrigin("CENTER", 0, 0) end
    frame.bump = ag
  end
  frame.bump:Play()
end
local function Flash(tex, peak, dur)
  if not tex.flashAG then
    local ag = tex:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(peak or 0.7); a:SetToAlpha(0); a:SetDuration(dur or 0.4); a:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function() tex:SetAlpha(0) end)
    tex.flashAG = ag
  end
  tex:SetAlpha(peak or 0.7); tex.flashAG:Stop(); tex.flashAG:Play()
end
local function FadeIn(frame, dur, fromScale)
  if not frame.fadeAG then
    local ag = frame:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(dur or 0.18); a:SetSmoothing("OUT")
    if fromScale then
      local s = ag:CreateAnimation("Scale"); s:SetDuration(dur or 0.18); s:SetSmoothing("OUT")
      if s.SetScaleFrom then s:SetScaleFrom(fromScale, fromScale); s:SetScaleTo(1, 1) else s:SetScale(1 / fromScale, 1 / fromScale) end
      if s.SetOrigin then s:SetOrigin("CENTER", 0, 0) end
    end
    frame.fadeAG = ag
  end
  frame.fadeAG:Stop(); frame.fadeAG:Play()
end

-- ---------- icons ----------
local function IconFor(t)
  local tex
  if t.spell then
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(t.spell)
    elseif GetSpellTexture then tex = GetSpellTexture(t.spell) end
  end
  if not tex and type(t.icon) == "number" then return t.icon end   -- an icon known only by its file id (a row recorded at the trainer)
  return tex or ("Interface\\Icons\\" .. (t.icon or "inv_misc_questionmark"))
end

-- ---------- state ----------
local F
local trees = {}      -- trees[ti] = panel with .tiles[i]
local LayoutStage, MakeStage   -- the stage under the trees (defined with BuildTrees)
local side, foot, head
local sheets = {}
local applying = false
local tabs = {}       -- side panel tabs: key -> { button, frame, refresh }
local TAB_ORDER = { "home", "plan", "coach", "builds", "popular", "racials" }
local TAB_LABEL = { home = "Home", plan = "Plan", coach = "Coach", builds = "Builds", popular = "Popular", classic = "Classic", racials = "Races" }

local function plan() return TF.plan end
local function classData() return D.classes[plan().cls] end
local function isOwnClass() return plan().cls == TF.PlayerClass() end
local function pickRate(ti, i)
  local pop = D.popular[plan().cls]
  return pop and pop.pick and pop.pick[ti] and pop.pick[ti][i] or nil
end

-- ---------- tooltips ----------
-- the game's tooltip for a talent as data: every line with words, surfaced. nil when this client cannot say.
local function TipLines(getter, ...)
  if not getter then return nil end
  local ok, data = pcall(getter, ...)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local out = {}
  for _, line in ipairs(data.lines) do
    if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then pcall(TooltipUtil.SurfaceArgs, line) end
    if type(line.leftText) == "string" then out[#out + 1] = line end
  end
  return #out > 0 and out or nil
end
-- lines of the game's tooltip that say nothing on a talent tile: nearly every talent is a passive, so the Passive tag
-- sat at the top of every tooltip; the rank is on the plan line already
local function TipNoise(s)
  return s == "" or s == "Passive" or (SPELL_PASSIVE and s == SPELL_PASSIVE) or s:match("^Rank %d+$") ~= nil or s:match("^Rank %d+ */ *%d+$") ~= nil
end
function UI.Tile(ti, i) return trees[ti] and trees[ti].tiles[i] or nil end
function UI.TreeHot(ti) return trees[ti] and trees[ti].hot or nil end
local function TipTitle(t) return string.format("|T%s:18:18:0:0:64:64:5:59:5:59|t %s", tostring(IconFor(t)), t.name) end
function UI.ShowTip(b, owner, mode, extra)
  owner = owner or b
  local p = plan(); local ti, i = b.ti, b.i
  local t = classData().trees[ti].talents[i]
  local r = p.ranks[ti][i]
  local n = isOwnClass() and G.Node(ti, i) or nil
  UI.hoverTile = b
  -- the spells this talent changes, by the rank the looked-at level would have: hold Ctrl and the tooltip reads them
  local refs = {}
  for _, name in ipairs(t.mentions or {}) do
    local rec = D.learn and D.learn[p.cls] and D.learn[p.cls][name]
    if rec and rec.ids then
      local k = 1
      for j, lv in ipairs(rec.levels or {}) do if lv <= p.level and rec.ids[j] then k = j end end
      if rec.ids[k] then refs[#refs + 1] = { name = name, id = rec.ids[k] } end
    end
  end
  if #refs > 0 and IsControlKeyDown and IsControlKeyDown() then
    TipBegin(owner)
    local first = true
    for _, s in ipairs(refs) do
      if not first then GameTooltip:AddLine(" ") end
      local lines = TipLines(C_TooltipInfo and C_TooltipInfo.GetSpellByID, s.id)
      if lines then
        if first then GameTooltip:SetText(s.name, rgb(C.purple)) else GameTooltip:AddLine(s.name, rgb(C.purple)) end
        for k = 2, #lines do local L = lines[k]; if not TipNoise(L.leftText) then GameTooltip:AddLine(L.leftText, 1, 1, 1, true) end end
      else
        local ok = first and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, s.id)
        if not ok then if first then GameTooltip:SetText(s.name, rgb(C.purple)) else GameTooltip:AddLine(s.name, rgb(C.purple)) end end
      end
      first = false
    end
    GameTooltip:AddLine(" "); GameTooltip:AddLine("Let go of Ctrl for the talent.", 0.54, 0.54, 0.54, true)
    TipEnd(owner, mode)
    return
  end
  TipBegin(owner)
  local shown = false
  local lines = (n and n.entry and TipLines(C_TooltipInfo and C_TooltipInfo.GetTraitEntry, n.entry, math.max(1, r))) or (t.spell and TipLines(C_TooltipInfo and C_TooltipInfo.GetSpellByID, t.spell)) or nil
  if lines then
    GameTooltip:SetText(TipTitle(t), 1, 0.82, 0)
    for k = 2, #lines do
      local L = lines[k]; local lt = L.leftText
      if not TipNoise(lt) then
        local lc, rc = L.leftColor or {}, L.rightColor or {}
        if type(L.rightText) == "string" and L.rightText ~= "" then GameTooltip:AddDoubleLine(lt, L.rightText, lc.r or 1, lc.g or 1, lc.b or 1, rc.r or 1, rc.g or 1, rc.b or 1)
        else GameTooltip:AddLine(lt, lc.r or 1, lc.g or 1, lc.b or 1, true) end
      end
    end
    shown = true
  end
  if not shown and n and n.entry and GameTooltip.SetTraitEntry then shown = pcall(GameTooltip.SetTraitEntry, GameTooltip, n.entry, math.max(1, r)) end
  if not shown and t.spell and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, t.spell) end
  if not shown then GameTooltip:SetText(TipTitle(t), 1, 0.82, 0) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Your plan", string.format("%d / %d", r, t.max), 1, 0.82, 0, 1, 1, 1)
  if n then
    local same = n.rank == r
    GameTooltip:AddDoubleLine("In game", string.format("%d / %d", n.rank, n.max), 0.35, 0.65, 1, same and 1 or 0.35, same and 1 or 0.65, 1)
  end
  if r > 0 then
    local first, last, nextOne
    for _, e in ipairs(TF.NextUp(p)) do
      if e.ti == ti and e.i == i then first = first or e.level; last = e.level end
    end
    if first then
      local when = first == last and string.format("level %d", first) or string.format("levels %d to %d", first, last)
      GameTooltip:AddDoubleLine("In your plan", when, 1, 0.82, 0, 0.74, 0.74, 0.74)
    end
  end
  if UI.nextTile == b then GameTooltip:AddLine("Your next point goes here.", 0.31, 0.75, 0.23, true) end
  if TF.trial and TF.TrialRank(ti, i) > 0 then GameTooltip:AddDoubleLine(TF.trial.name, string.format("%d / %d", TF.TrialRank(ti, i), t.max), 1, 0.82, 0, 1, 0.82, 0) end
  local bk = TF.SettledAt(ti, i)
  if bk then GameTooltip:AddLine(string.format("This build had %d point%s here. %s now, so %s back in your pool.", bk.pts, bk.pts == 1 and "" or "s", (bk.why:gsub(" Talents$", "")), bk.pts == 1 and "it is" or "they are"), 1, 0.69, 0.40, true) end
  local pr = pickRate(ti, i)
  if pr then GameTooltip:AddDoubleLine("Pick rate on the site", pr .. "%", 0.54, 0.54, 0.54, 0.74, 0.74, 0.74) end
  if t.mentions and #t.mentions > 0 then local pr, pg, pb = rgb(C.purple); GameTooltip:AddLine("Changes " .. TF.JoinNames(t.mentions) .. "." .. (#refs > 0 and (" Hold Ctrl to read " .. (#refs == 1 and "it" or "them") .. ".") or ""), pr, pg, pb, true) end
  if r > 0 and r < t.max and n and n.entry and C_TooltipInfo and C_TooltipInfo.GetTraitEntry then
    local ok, data = pcall(C_TooltipInfo.GetTraitEntry, n.entry, r + 1)
    if ok and data and data.lines then
      local words = {}
      for k, line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then pcall(TooltipUtil.SurfaceArgs, line) end
        local s = line.leftText
        if k > 1 and s and #s > 30 then words[#words + 1] = s end
      end
      if #words > 0 then GameTooltip:AddLine(" "); GameTooltip:AddLine("Next rank", 1, 0.82, 0); GameTooltip:AddLine(words[#words], 0.62, 0.62, 0.62, true) end
    end
  end
  if t.classic and t.classic ~= "same" then
    local col = STATUS_COLOR[t.classic] or C.ink2
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(STATUS_WORD[t.classic] .. (t.cwas and (" (was " .. t.cwas .. ")") or ""), col[1], col[2], col[3])
    if t.ctext then GameTooltip:AddLine("Classic: " .. t.ctext, 0.6, 0.6, 0.6, true) end
  end
  local why = TF.CanAdd(p, ti, i)
  if why and why ~= "Max rank" and r == 0 then GameTooltip:AddLine(why, 1, 0.3, 0.3, true) end
  if TF.TotalPts(p) < 5 then GameTooltip:AddLine("Left click adds a point, right click takes one back.", 0.54, 0.54, 0.54, true) end
  if n and n.rank > 0 and G.CanRefund() and n.canRefund ~= false then GameTooltip:AddLine("Shift right click gives the real point back on your character.", 0.35, 0.65, 1, true) end
  if extra then extra() end
  TipEnd(owner, mode)
end

-- Ctrl pressed or let go while a talent is under the mouse: the tooltip turns over
do
  local mf = CreateFrame("Frame")
  pcall(mf.RegisterEvent, mf, "MODIFIER_STATE_CHANGED")
  mf:SetScript("OnEvent", function(_, _, key)
    if (key == "LCTRL" or key == "RCTRL") and UI.hoverTile and GameTooltip:IsShown() and GameTooltip:GetOwner() == UI.hoverTile then UI.ShowTip(UI.hoverTile) end
  end)
end

-- a tile scales about its own centre. WoW scales a frame about its anchor and scales the anchor offsets too,
-- so the anchor is moved to compensate; the tile grows in place instead of sliding away.
local function TileScale(b, s)
  b:SetScale(s)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", (b.x0 - (s - 1) * TILE / 2) / s, (b.y0 + (s - 1) * TILE / 2) / s)
end
local function tileKey(b) return b.ti .. "." .. b.i end
-- a point lands: the site's flash. A gold halo contracts onto the tile while a glow behind it fades, and the rank
-- pops up white and settles back to its colour. quiet = the same halo alone, used to point at a tile.
local function Land(b, quiet)
  local s0, s1 = TILE + 8 + 16, TILE + 8
  b.halo:Show(); b.haloGlow:Show()
  local peak = quiet and 0.6 or 0.95
  Tween("land" .. tileKey(b), 0.32, function(e)
    local sz = lerp(s0, s1, e); b.halo:SetSize(sz, sz); b.halo:SetAlpha(peak * (1 - e))
    b.haloGlow:SetAlpha((quiet and 0.3 or 0.6) * (1 - e))
  end, { done = function() b.halo:Hide(); b.haloGlow:Hide() end })
  if quiet then return end
  local c = b.rankColor or C.gold
  b.rank:SetScale(1.35); b.rank:SetTextColor(1, 1, 1)
  Tween("rank" .. tileKey(b), 0.3, function(e) b.rank:SetScale(lerp(1.3, 1, e)); b.rank:SetTextColor(lerp(1, c[1], e), lerp(1, c[2], e), lerp(1, c[3], e)) end, { ease = "out4" })
end
-- a point comes back: the tile dips and a thin ring lets go outward
local function Unhit(b)
  local s0 = b:GetScale()
  Tween("hover" .. tileKey(b), 0.16, function(_, u) local s = u < 0.3 and lerp(s0, 0.86, u / 0.3) or lerp(0.86, s0, (u - 0.3) / 0.7); TileScale(b, s) end, { ease = "linear" })
  local s1 = TILE + 8
  b.halo:Show()
  Tween("land" .. tileKey(b), 0.28, function(e) local sz = lerp(s1, s1 + 22, e); b.halo:SetSize(sz, sz); b.halo:SetAlpha(0.55 * (1 - e)) end, { done = function() b.halo:Hide() end })
end
local function tileClicked(b, btn)
  if btn == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() and isOwnClass() and G.CanRefund() then
    local ok, msg = G.Refund(b.ti, b.i)
    UI.Note(ok and ("Took a point back from " .. msg .. " on your character.") or msg)
    return
  end
  local view, partial = TF.ViewRanks(plan())
  if btn == "RightButton" then
    if partial and view[b.ti][b.i] <= 0 then UI.Note("That point comes later in your plan. Raise the level to reach it."); UI.ShowTip(b); return end
    local ok, why = TF.Remove(b.ti, b.i, partial and TF.Pool(plan()) or nil)
    if ok then Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF"); Unhit(b) elseif why then UI.Note(why) end
  else
    local ok, why = TF.Add(b.ti, b.i)
    if ok then
      Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); Land(b)
      local pl = plan()
      if pl.level == 60 and TF.TotalPts(pl) == TF.Pool(pl) then
        UI.EmblemPulse()
        UI.Note("That is every point. Save it, or take the link with you.", { { label = "Share", fn = function() UI.OpenSheet("share") end } }, 10)
      end
    elseif why then UI.Note(why) end
  end
  UI.ShowTip(b)
end

-- ---------- tiles ----------
local Chain = {}   -- Chain.Paint and Chain.Light, defined under MakeArrow; the tile's hover uses them
local function MakeTile(panel, ti, i, t)
  local b = CreateFrame("Button", nil, panel)
  b.ti, b.i = ti, i
  b:SetSize(TILE, TILE)
  b.x0, b.y0 = TILE_X0 + (t.col - 1) * (TILE + GX), -(TILE_Y0 + (t.row - 1) * (TILE + GY))
  b:SetPoint("TOPLEFT", panel, "TOPLEFT", b.x0, b.y0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.slot = b:CreateTexture(nil, "BACKGROUND"); b.slot:SetTexture(SkinPath() .. "slot.png"); b.slot:SetSize(TILE + 8, TILE + 8); b.slot:SetPoint("CENTER")
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  if GAME_NODES then
    -- the game's node: a soft shadow under it, the icon inside a rounded square frame whose colour is the state
    b.slot:SetTexture(nil); Atlas(b.slot, "talents-node-square-shadow", TILE * 1.9, TILE * 1.9); b.slot:SetAlpha(0.9)
    b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT", 4, -4); b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    b.frame = b:CreateTexture(nil, "OVERLAY", nil, 1); Atlas(b.frame, "talents-node-square-gray", TILE, TILE); b.frame:SetPoint("CENTER")
  end
  b.glow = b:CreateTexture(nil, "ARTWORK", nil, -1); b.glow:SetTexture(SkinPath() .. "slot-glow.png"); b.glow:SetSize(TILE * 2.4, TILE * 2.4); b.glow:SetPoint("CENTER"); b.glow:SetBlendMode("ADD"); b.glow:SetAlpha(0)
  b.ring = b:CreateTexture(nil, "OVERLAY", nil, 1); b.ring:SetTexture(SkinPath() .. "slot-rim.png"); b.ring:SetSize(TILE + 8, TILE + 8); b.ring:SetPoint("CENTER")
  if GAME_NODES then b.ring:SetTexture(nil); b.ring:Hide() end
  -- the landing flash: a halo that contracts onto the tile, a glow behind it that fades
  b.halo = b:CreateTexture(nil, "OVERLAY", nil, 3); b.halo:SetTexture(SkinPath() .. "slot-rim.png"); b.halo:SetSize(TILE + 30, TILE + 30); b.halo:SetPoint("CENTER"); b.halo:SetVertexColor(1, 0.82, 0); b.halo:Hide()
  b.haloGlow = b:CreateTexture(nil, "ARTWORK", nil, -2); b.haloGlow:SetTexture(SkinPath() .. "slot-glow.png"); b.haloGlow:SetSize(TILE * 2.8, TILE * 2.8); b.haloGlow:SetPoint("CENTER"); b.haloGlow:SetBlendMode("ADD"); b.haloGlow:SetVertexColor(1, 0.86, 0.45); b.haloGlow:Hide()
  b.flash = b:CreateTexture(nil, "OVERLAY", nil, 2); b.flash:SetTexture(WHITE); b.flash:SetAllPoints(b.icon); b.flash:SetBlendMode("ADD"); b.flash:SetAlpha(0)
  -- lit while a talent this one needs, or unlocks, is under the mouse
  b.link = b:CreateTexture(nil, "OVERLAY", nil, 2); b.link:SetTexture(SkinPath() .. "slot-rim.png"); b.link:SetSize(TILE + 8, TILE + 8); b.link:SetPoint("CENTER"); b.link:SetVertexColor(1, 0.82, 0, 0.5); b.link:Hide()
  if GAME_NODES then b.link:SetTexture(nil); Atlas(b.link, "talents-node-square-yellow", TILE, TILE); b.link:SetVertexColor(1, 1, 1, 0.6); b.link:SetBlendMode("ADD") end
  -- the pulse that marks the next point of the path
  b.nextGlow = b:CreateTexture(nil, "OVERLAY", nil, 0); b.nextGlow:SetTexture(SkinPath() .. "slot-rim.png"); b.nextGlow:SetSize(TILE + 16, TILE + 16); b.nextGlow:SetPoint("CENTER"); b.nextGlow:SetVertexColor(1, 0.82, 0); b.nextGlow:SetAlpha(0)
  if GAME_NODES then b.nextGlow:SetTexture(nil); Atlas(b.nextGlow, "talents-node-square-greenglow", TILE * 2.1, TILE * 2.1); b.nextGlow:SetVertexColor(1, 1, 1); b.nextGlow:SetBlendMode("ADD") end
  b.nextPulse = Pulse(b.nextGlow, 0.3, 0.95, 1.4)
  -- the top edge carries the Classic mark: gold new, blue changed, purple moved
  b.mark = b:CreateTexture(nil, "OVERLAY", nil, 4); b.mark:SetTexture(WHITE); b.mark:SetHeight(3); b.mark:SetPoint("TOPLEFT", b.icon, "TOPLEFT", 0, 0); b.mark:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", 0, 0); b.mark:Hide()
  b.rankBg = b:CreateTexture(nil, "OVERLAY", nil, 4); b.rankBg:SetTexture(WHITE); b.rankBg:SetVertexColor(0, 0, 0, 0.94); b.rankBg:SetSize(30, 16); b.rankBg:SetPoint("BOTTOMRIGHT", 8, -7)
  b.rankEdge = Edges(b, b.rankBg, "OVERLAY", 5); b.rankEdge:SetColor(0.27, 0.27, 0.27, 1)
  b.rank = b:CreateFontString(nil, "OVERLAY", nil, 5); Font(b.rank, 11); b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)
  if GAME_NODES then   -- the game writes the rank as outlined text at the node's foot, no box
    b.rankBg:Hide(); b.rankEdge:SetColor(0, 0, 0, 0); Font(b.rank, 12, false, "THICKOUTLINE"); b.rank:ClearAllPoints(); b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 2)
  end
  b.live = b:CreateFontString(nil, "OVERLAY", nil, 5); Font(b.live, 11, false, "OUTLINE"); b.live:SetPoint("TOPLEFT", -6, 6); b.live:SetTextColor(rgb(C.blue))
  b.liveBg = b:CreateTexture(nil, "OVERLAY", nil, 4); b.liveBg:SetTexture(WHITE); b.liveBg:SetVertexColor(0.05, 0.1, 0.2, 0.9); b.liveBg:SetPoint("TOPLEFT", b.live, "TOPLEFT", -3, 2); b.liveBg:SetPoint("BOTTOMRIGHT", b.live, "BOTTOMRIGHT", 3, -2)
  if GAME_NODES then b.live:ClearAllPoints(); b.live:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -2) end
  -- a tried build's talents wear a gold ring, no number
  b.ghostRing = b:CreateTexture(nil, "OVERLAY", nil, 0); b.ghostRing:SetTexture(MEDIA .. "ring.tga"); b.ghostRing:SetSize(TILE + 22, TILE + 22); b.ghostRing:SetPoint("CENTER"); b.ghostRing:SetVertexColor(1, 0.82, 0, 0.85); b.ghostRing:Hide()
  if GAME_NODES then b.ghostRing:SetTexture(nil); Atlas(b.ghostRing, "talents-node-square-ghost", TILE * 1.3, TILE * 1.3); b.ghostRing:SetVertexColor(1, 1, 1, 0.95) end
  b.pick = b:CreateFontString(nil, "OVERLAY", nil, 5); Font(b.pick, 10); b.pick:SetPoint("BOTTOMLEFT", -6, -6); b.pick:SetTextColor(rgb(C.ink2))
  -- a talent that lost points when the loaded build settled against today's rules: an orange dashed ring and how many came back
  b.backRing = b:CreateTexture(nil, "OVERLAY", nil, 0); b.backRing:SetTexture(MEDIA .. "ring-dash.tga"); b.backRing:SetSize(TILE + 18, TILE + 18); b.backRing:SetPoint("CENTER"); b.backRing:SetVertexColor(1, 0.54, 0.12, 0.95); b.backRing:Hide()
  b.backTag = b:CreateFontString(nil, "OVERLAY", nil, 5); Font(b.backTag, 10, false, "OUTLINE"); b.backTag:SetPoint("TOPRIGHT", 7, 7); b.backTag:SetTextColor(1, 0.69, 0.40); b.backTag:Hide()
  b.pickBg = b:CreateTexture(nil, "OVERLAY", nil, 4); b.pickBg:SetTexture(WHITE); b.pickBg:SetVertexColor(0, 0, 0, 0.8); b.pickBg:SetPoint("TOPLEFT", b.pick, "TOPLEFT", -3, 2); b.pickBg:SetPoint("BOTTOMRIGHT", b.pick, "BOTTOMRIGHT", 3, -2)
  b:SetHighlightTexture(SkinPath() .. "slot-rim.png")
  local hl = b:GetHighlightTexture(); if hl then hl:ClearAllPoints(); hl:SetPoint("CENTER"); hl:SetSize(TILE + 8, TILE + 8); hl:SetVertexColor(1, 0.82, 0, 0.55) end
  if GAME_NODES and hl then hl:SetTexture(nil); Atlas(hl, "talents-node-square-yellow", TILE, TILE); hl:SetVertexColor(1, 1, 1, 0.5); hl:SetBlendMode("ADD") end
  b.pulse = Pulse(b.glow, 0.12, 0.42, 1.3)
  local sh = b:CreateAnimationGroup()
  for k, dx in ipairs({ -3, 6, -6, 3 }) do local m = sh:CreateAnimation("Translation"); m:SetOffset(dx, 0); m:SetDuration(0.04); m:SetOrder(k) end
  b.shake = sh
  b:SetScript("OnClick", tileClicked)
  b:SetScript("OnEnter", function(self) UI.ShowTip(self, self); Chain.Light(self, true); local s0 = self:GetScale(); Tween("hover" .. tileKey(self), 0.07, function(e) TileScale(self, lerp(s0, 1.05, e)) end, { ease = "out4" }) end)
  b:SetScript("OnLeave", function(self) GameTooltip:Hide(); Chain.Light(self, false); local s0 = self:GetScale(); Tween("hover" .. tileKey(self), 0.1, function(e) TileScale(self, lerp(s0, 1, e)) end) end)
  return b
end

local function MakeArrow(panel, from, to)
  local parts = {}
  local function line(w, h)
    local t = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    if GAME_NODES and Atlas(t, "talents-arrow-line-gray") then t.kind = "line"; if w > h then h = 6 else w = 6 end else t:SetTexture(WHITE) end
    t:SetSize(w, h); parts[#parts + 1] = t; return t
  end
  local head = panel:CreateTexture(nil, "ARTWORK", nil, 2)
  if GAME_NODES and Atlas(head, "talents-arrow-head-gray", 14, 12) then head.kind = "head" else head:SetTexture(MEDIA .. "arrow.tga"); head:SetSize(14, 14) end
  parts[#parts + 1] = head
  local fx, fy = TILE_X0 + (from.col - 1) * (TILE + GX) + TILE / 2, -(TILE_Y0 + (from.row - 1) * (TILE + GY)) - TILE
  local tx, ty = TILE_X0 + (to.col - 1) * (TILE + GX) + TILE / 2, -(TILE_Y0 + (to.row - 1) * (TILE + GY))
  if from.col == to.col then
    local h = fy - ty - 4
    local v = line(3, math.max(2, h - 8)); v:SetPoint("TOP", panel, "TOPLEFT", fx, fy - 3)
    head:SetPoint("TOP", panel, "TOPLEFT", tx, ty + 12)
  elseif from.row == to.row then
    local dir = to.col > from.col and 1 or -1
    local x1 = TILE_X0 + (from.col - 1) * (TILE + GX) + (dir > 0 and TILE or 0)
    local x2 = TILE_X0 + (to.col - 1) * (TILE + GX) + (dir > 0 and 0 or TILE)
    local yy = fy + TILE / 2
    local hline = line(math.max(2, math.abs(x2 - x1) - 8), 3); hline:SetPoint(dir > 0 and "LEFT" or "RIGHT", panel, "TOPLEFT", dir > 0 and x1 + 2 or x1 - 2, yy)
    head:SetRotation(dir > 0 and math.pi / 2 or -math.pi / 2); head:SetPoint("CENTER", panel, "TOPLEFT", x2 - dir * 6, yy)
  else
    local yy = fy + TILE / 2
    local dir = to.col > from.col and 1 or -1
    local x1 = TILE_X0 + (from.col - 1) * (TILE + GX) + (dir > 0 and TILE or 0)
    local hline = line(math.abs(tx - x1) + 1, 3); hline:SetPoint(dir > 0 and "LEFT" or "RIGHT", panel, "TOPLEFT", x1, yy)
    local v = line(3, yy - ty - 8); v:SetPoint("TOP", panel, "TOPLEFT", tx, yy + 1)
    head:SetPoint("TOP", panel, "TOPLEFT", tx, ty + 12)
  end
  return parts
end
-- an arrow's colour follows the talent it leads to: gold once the prerequisite is filled, locked grey while its
-- row is out of reach, plain grey between; hot = under the mouse, gold for the moment
function Chain.Paint(ti, i, hot)
  local tp = trees[ti]; local parts = tp and tp.arrows[i]; if not parts then return end
  local tree = classData().trees[ti]; local t = tree.talents[i]; local vp = tp.vp or plan()
  local pre = tree.talents[t.req]; local lit = vp.ranks[ti][t.req] >= pre.max
  local locked = TF.Status(vp, ti, t.req) == "locked"
  for _, part in ipairs(parts) do
    if part.kind then Atlas(part, "talents-arrow-" .. part.kind .. "-" .. ((lit or hot) and "yellow" or (locked and "locked" or "gray"))); part:SetVertexColor(1, 1, 1, 1)
    elseif lit or hot then part:SetVertexColor(1, 0.82, 0, 1) else part:SetVertexColor(0.6, 0.5, 0.3, 0.5) end
  end
end
-- hover a talent: what it needs and what it unlocks light up, arrows and all, so the chain reads at a glance
function Chain.Light(b, on)
  local ti, i = b.ti, b.i; local tp = trees[ti]; if not tp then return end
  local tree = classData().trees[ti]; local t = tree.talents[i]
  local function mark(j) local o = tp.tiles[j]; if o and o.link then o.link:SetShown(on) end end
  if t.req then Chain.Paint(ti, i, on); mark(t.req) end
  for j, u in ipairs(tree.talents) do if u.req == i then Chain.Paint(ti, j, on); mark(j) end end
end
UI.LinkLight = function(ti, i, on) local b = trees[ti] and trees[ti].tiles[i]; if b then Chain.Light(b, on) end end

local function PanelHeader(p, title, icon)
  if GAME_NODES and AtlasOK("Talents-Main-Ring-c60") then
    -- the game's own header: the tree's icon in a bronze ring, its name beside it, the points in the small box at the
    -- ring's foot, and the soft line the game draws under a header
    if icon then
      p.icon = p:CreateTexture(nil, "BORDER"); p.icon:SetSize(30, 30); p.icon:SetPoint("TOPLEFT", 16, -7); p.icon:SetTexture(IconFor({ icon = icon })); p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      pcall(function() local m = p:CreateMaskTexture(); m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(p.icon); p.icon:AddMaskTexture(m) end)
      p.ring = p:CreateTexture(nil, "OVERLAY"); Atlas(p.ring, "Talents-Main-Ring-c60", 46, 46); p.ring:SetPoint("CENTER", p.icon, "CENTER", 0, 0)
    end
    p.title = Text(p, 15, C.ink); FontObject(p.title, GameFontWhiteLarge, 15); p.title:SetPoint("LEFT", p, "TOPLEFT", 60, -20); p.title:SetPoint("RIGHT", p, "TOPRIGHT", -12, -20); p.title:SetJustifyH("LEFT"); p.title:SetWordWrap(false); p.title:SetText(title)
    p.title:SetShadowColor(0, 0, 0, 1); p.title:SetShadowOffset(1, -1)
    p.glow = p:CreateTexture(nil, "BORDER", nil, 1); Atlas(p.glow, "Talents-small-divider-c60", TREE_W - 2, 36); p.glow:SetPoint("BOTTOM", p, "TOP", 0, -(TREE_HEAD + 6)); p.glow:SetAlpha(0.9)
    p.gameHeader = true
    p.hot = CreateFrame("Button", nil, p); p.hot:SetPoint("TOPLEFT", 8, -2); p.hot:SetSize(150, TREE_HEAD - 6)
    p.hot:SetScript("OnEnter", function(self) if p.OnHeaderEnter then p.OnHeaderEnter(self) end end)
    p.hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return
  end
  local hl = p:CreateTexture(nil, "BORDER", nil, 1); hl:SetTexture(WHITE); hl:SetPoint("TOPLEFT", 1, -TREE_HEAD); hl:SetPoint("TOPRIGHT", -1, -TREE_HEAD); hl:SetHeight(1)
  -- a quiet band behind the header, so the title reads over any painting
  local band = p:CreateTexture(nil, "BACKGROUND", nil, 4); band:SetTexture(WHITE); band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(TREE_HEAD - 1)
  Gradient(band, "VERTICAL", 0.03, 0.03, 0.03, 0.35, 0.03, 0.03, 0.03, 0.75)
  Gradient(hl, "HORIZONTAL", 0.78, 0.61, 0.10, 0.9, 0.78, 0.61, 0.10, 0.05)
  local x = 12
  if icon then p.icon = p:CreateTexture(nil, "OVERLAY"); p.icon:SetSize(24, 24); p.icon:SetPoint("TOPLEFT", 12, -10); p.icon:SetTexture(IconFor({ icon = icon })); p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); x = 44
    p.iconEdge = Edges(p, p.icon, "OVERLAY", 1); p.iconEdge:SetColor(0.78, 0.61, 0.10, 0.75) end
  p.title = Text(p, 15, LOOK() == "site" and C.ink or C.gold, LOOK() ~= "site"); p.title:SetPoint("LEFT", p, "TOPLEFT", x, -22); p.title:SetText(title); p.title:SetShadowColor(0, 0, 0, 0.9); p.title:SetShadowOffset(1, -1)
  p.hot = CreateFrame("Button", nil, p); p.hot:SetPoint("TOPLEFT", 8, -2); p.hot:SetSize(150, TREE_HEAD - 6)
  p.hot:SetScript("OnEnter", function(self) if p.OnHeaderEnter then p.OnHeaderEnter(self) end end)
  p.hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeTree(ti, tree)
  local p = Frame("Frame", nil, F)
  p:SetSize(TREE_W, TREE_H)
  p.fade = p:CreateTexture(nil, "BACKGROUND", nil, 3); p.fade:SetTexture(SkinPath() .. "fade.png"); p.fade:SetAllPoints()
  p.edge = Edges(p, p, "BORDER", 3); p.edge:SetColor(0.78, 0.61, 0.10, (GAME_NODES and AtlasOK("Talents-inner-frame-c60")) and 0 or 0.22)
  if LOOK() == "site" then p.edge:SetColor(0.23, 0.23, 0.23, 1); p.panelBg = Solid(p, "BACKGROUND", C.raised, 1, 0); p.panelBg:SetAllPoints() end
  p.art = {}
  local okArt = false
  if tree.bg then
    local pieces = { { "TopLeft", 0.8, 0.667, "TOPLEFT" }, { "TopRight", 0.2, 0.667, "TOPRIGHT" }, { "BottomLeft", 0.8, 0.333, "BOTTOMLEFT" }, { "BottomRight", 0.2, 0.333, "BOTTOMRIGHT" } }
    okArt = true
    for _, pc in ipairs(pieces) do
      local t = p:CreateTexture(nil, "BACKGROUND", nil, 1)
      local ok, r = pcall(t.SetTexture, t, "Interface\\TalentFrame\\" .. tree.bg .. "-" .. pc[1])
      if not ok or r == false then okArt = false end
      t:SetSize((TREE_W - 2) * pc[2], (TREE_H - 2) * pc[3]); t:SetPoint(pc[4], p, pc[4], (pc[4]:find("LEFT") and 1 or -1), (pc[4]:find("TOP") and -1 or 1)); t:SetAlpha(0.8)
      p.art[#p.art + 1] = t
    end
  end
  if not okArt then
    for _, t in ipairs(p.art) do t:Hide() end
    local w = p:CreateTexture(nil, "BACKGROUND", nil, 1); w:SetTexture(IconFor({ icon = tree.icon })); w:SetSize(TREE_W * 1.15, TREE_W * 1.15); w:SetPoint("CENTER", p, "CENTER", 0, -10); w:SetAlpha(0.13); w:SetDesaturated(true); w:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
  local shade = p:CreateTexture(nil, "BACKGROUND", nil, 2); shade:SetTexture(WHITE); shade:SetPoint("TOPLEFT", 1, -1); shade:SetPoint("BOTTOMRIGHT", -1, 1); p.shade = shade
  Gradient(shade, "VERTICAL", 0.04, 0.04, 0.04, 0.7, 0.04, 0.04, 0.04, 0.2)
  PanelHeader(p, tree.name, tree.icon)
  p.OnHeaderEnter = function(self)
    local cd = classData(); local tr = cd.trees[ti]; local pop = TF.Popular(plan().cls)
    local share; for _, sp in ipairs(pop and pop.spec or {}) do if sp[1] == tr.name then share = sp[2] end end
    TipBegin(self); GameTooltip:SetText(tr.name, 1, 0.82, 0)
    if share then GameTooltip:AddLine(string.format("%d%% of %s builds on the site lead %s.", share, cd.name, tr.name), 0.9, 0.9, 0.9, true) end
    local n = 0; for _, r in ipairs(plan().ranks[ti]) do n = n + r end
    GameTooltip:AddLine(string.format("%d of your points here.", n), 0.74, 0.74, 0.74)
    TipEnd(self, "above")
  end
  p.fill = p:CreateTexture(nil, "BORDER", nil, 2); p.fill:SetTexture(WHITE); p.fill:SetHeight(3); p.fill:SetPoint("TOPLEFT", 1, -TREE_HEAD); p.fill:SetWidth(1); p.fill:SetAlpha(0)
  Gradient(p.fill, "HORIZONTAL", 0.78, 0.61, 0.10, 1, 1, 0.82, 0, 1)
  p.fillGlow = p:CreateTexture(nil, "BORDER", nil, 1); p.fillGlow:SetTexture(SkinPath() .. "thread.png"); p.fillGlow:SetHeight(10); p.fillGlow:SetPoint("LEFT", p.fill, "LEFT", -4, 0); p.fillGlow:SetPoint("RIGHT", p.fill, "RIGHT", 4, 0); p.fillGlow:SetVertexColor(1, 0.82, 0, 0.35); p.fillGlow:SetBlendMode("ADD")
  if p.gameHeader then
    -- the points as a plain line under the name: "17 points", clear at a glance (the game's small box at the ring's foot was hard to read)
    p.pts = Text(p, 13, C.gold); p.pts:SetPoint("TOPLEFT", p, "TOPLEFT", 60, -36); p.pts:SetJustifyH("LEFT"); p.pts:SetText("0")
    p.ptsWord = Text(p, 11, C.muted); p.ptsWord:SetPoint("LEFT", p.pts, "RIGHT", 4, 0); p.ptsWord:SetText("points")
    p.rowNote = Text(p, 11, C.muted); p.rowNote:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -37); p.rowNote:SetJustifyH("RIGHT")
    p.edge:SetColor(0, 0, 0, 0); p.fill:SetHeight(2); p.fill:ClearAllPoints(); p.fill:SetPoint("TOPLEFT", 1, -(TREE_HEAD - 1)); p.fillGlow:Hide()
  else
    p.pts = Text(p, 18, C.gold, LOOK() ~= "site"); p.pts:SetPoint("RIGHT", p, "TOPRIGHT", -12, -16); p.pts:SetJustifyH("RIGHT"); p.pts:SetText("0")
    p.rowNote = Text(p, 10, C.muted); p.rowNote:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -29); p.rowNote:SetJustifyH("RIGHT")
  end
  p.tiles, p.arrows = {}, {}
  for i, t in ipairs(tree.talents) do p.tiles[i] = MakeTile(p, ti, i, t) end
  for i, t in ipairs(tree.talents) do if t.req then p.arrows[i] = MakeArrow(p, tree.talents[t.req], t) end end
  return p
end

-- ---------- generic scrolling list of rows ----------
local function ListRows(parent, w, rowH, top, bottom, hasDel)
  local sc = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", PAD, -top); sc:SetPoint("BOTTOMRIGHT", -28, bottom); Slim(sc)
  local child = CreateFrame("Frame", nil, sc); child:SetSize(w, 10); sc:SetScrollChild(child)
  sc.child, sc.rows, sc.rowH, sc.offset = child, {}, rowH, 0
  function sc:Row(k)
    local r = self.rows[k]
    if r then return r end
    r = CreateFrame("Button", nil, self.child); r:SetSize(w, rowH); r:SetPoint("TOPLEFT", 0, -self.offset - (k - 1) * rowH)
    r.bg = Solid(r, "BACKGROUND", C.raised, 0.55); r.bg:SetPoint("TOPLEFT", 0, -1); r.bg:SetPoint("BOTTOMRIGHT", 0, 1)
    r.accent = Solid(r, "BACKGROUND", C.gold, 0, 1); r.accent:SetPoint("TOPLEFT", 0, -1); r.accent:SetPoint("BOTTOMLEFT", 0, 1); r.accent:SetWidth(3)
    r:SetHighlightTexture(WHITE); r:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(28, 28); r.icon:SetPoint("LEFT", 8, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- the name has the whole first line to itself; the numbers and the two buttons share the second
    r.name = Text(r, 13, C.ink); r.name:SetPoint("TOPLEFT", 44, -6); r.name:SetPoint("RIGHT", hasDel and -30 or -8, 0); r.name:SetWordWrap(false)
    r.sub = Text(r, 11, C.muted); r.sub:SetPoint("BOTTOMLEFT", 44, 10); r.sub:SetWordWrap(false)
    r.tag = Text(r, 11, C.muted); r.tag:SetPoint("TOPRIGHT", hasDel and -30 or -8, -8); r.tag:SetJustifyH("RIGHT")
    r.tagBtn = CreateFrame("Button", nil, r); r.tagBtn:SetSize(44, 16); r.tagBtn:SetPoint("TOPRIGHT", hasDel and -28 or -6, -6); r.tagBtn:Hide()
    r.tagBtn:SetHighlightTexture(WHITE); r.tagBtn:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.12)
    r.tagBtn:SetScript("OnClick", function() if r.onTag then r.onTag() end end)
    Tip(r.tagBtn, "PvE or PvP?", "Click to mark what this build is for. The mark stays with the saved build on this computer; a link does not carry it.")
    r.del = CloseX(r, 16); r.del:SetPoint("TOPRIGHT", -8, -6); r.del:SetScript("OnClick", function() if r.onDelete then r.onDelete() end end)
    if not hasDel then r.del:Hide() end
    r.ghost = Button(r, "Try it", "auto", 20, function() if r.onGhost then r.onGhost() end end); r.ghost.minW = 72; r.ghost:Fit(); r.ghost:SetPoint("BOTTOMRIGHT", -8, 6)
    r.load = Button(r, "Load", "auto", 20, function() if r.onLoad then r.onLoad() end end); r.load.minW = 64; r.load:Fit(); r.load:SetPoint("RIGHT", r.ghost, "LEFT", -8, 0)
    if rowH <= 40 then   -- compact: everything on one band, so three rows show where two did
      r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 6, 0)
      r.del:ClearAllPoints(); r.del:SetPoint("RIGHT", -4, 0)
      r.ghost:ClearAllPoints(); r.ghost:SetPoint("RIGHT", hasDel and -24 or -6, 0); r.ghost.minW = 64; r.ghost:Fit()
      r.load:ClearAllPoints(); r.load:SetPoint("RIGHT", r.ghost, "LEFT", -6, 0); r.load.minW = 52; r.load:Fit()
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 36, -4); r.name:SetPoint("RIGHT", r.load, "LEFT", -6, 0)
      r.sub:ClearAllPoints(); r.sub:SetPoint("BOTTOMLEFT", 36, 4); r.sub:SetPoint("RIGHT", r.load, "LEFT", -6, 0)
      r.tag:Hide(); r.tagBtn:Hide(); r.compact = true
    end
    r.sub:SetPoint("RIGHT", r.load, "LEFT", -8, 0)
    Tip(r.ghost, "See it next to yours", "Rings the talents this build takes on your trees, over your own points, so you can see where it differs. Load makes it your plan.")
    Tip(r.load, "Put it on your trees", "Replaces the plan you have open. Undo brings yours back.")
    self.rows[k] = r
    return r
  end
  function sc:Fill(n, extra)
    local last = self.offset + n * rowH
    for k, r in ipairs(self.rows) do
      local y = self.rowY and self.rowY[k] or (self.offset + (k - 1) * rowH)
      r:SetShown(k <= n); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
      if k <= n and y + rowH > last then last = y + rowH end
    end
    self.child:SetHeight(math.max(10, last + (extra or 0)))
    local tab = parent; if tab.spinPending then tab.spinPending = false; SpinRows(self.rows, rowH, n, self.offset) end
  end
  return sc
end

-- ---------- the side panel and its tabs ----------
local ROW_H = 28
-- a section title the way the game's own lists mark them: small caps, a thin line running on to the right
local function Section(parent, text, y, rightGap)
  local s = CreateFrame("Frame", nil, parent); s:SetPoint("TOPLEFT", 12, y); s:SetSize(PAGE_W - (rightGap or 0), 14)
  s.text = Text(s, 11, C.muted); s.text:SetPoint("LEFT", 0, 0); s.text:SetText(text)
  s.line = s:CreateTexture(nil, "ARTWORK"); s.line:SetTexture(WHITE); s.line:SetPoint("LEFT", s.text, "RIGHT", 8, 0); s.line:SetPoint("RIGHT", 0, 0); onePixel(s.line, true); s.line:SetVertexColor(0.78, 0.61, 0.10, 0.35)
  function s:SetText(t) self.text:SetText(t) end
  return s
end
-- a flat bar: dark track, one colour of fill, a hairline round it
local barCount = 0
local function Bar(parent, w, h)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(w, h)
  f.track = Solid(f, "BACKGROUND", C.bg, 0.9); f.track:SetAllPoints()
  f.fill = f:CreateTexture(nil, "ARTWORK"); f.fill:SetTexture(WHITE); f.fill:SetPoint("TOPLEFT", 1, -1); f.fill:SetPoint("BOTTOMLEFT", 1, 1); f.fill:SetWidth(1)
  f.edge = Edges(f, f, "OVERLAY", 0); f.edge:SetColor(0.78, 0.61, 0.10, 0.5)
  barCount = barCount + 1; f.key = "bar" .. barCount
  local function paint(frac)
    local inner = (f:GetWidth() or w) - 2
    f.fill:SetWidth(math.max(1, math.floor(inner * frac + 0.5))); f.fill:SetShown(frac > 0.001)
  end
  -- eases to the new value the way the site's bars do; the first value lands at once
  function f:Set(frac, r, g, b)
    frac = math.max(0, math.min(1, frac or 0))
    if r then Gradient(self.fill, "HORIZONTAL", r * 0.7, g * 0.7, b * 0.7, 1, r, g, b, 1) end
    local from = self.frac
    self.frac = frac
    if from == nil or math.abs(from - frac) < 0.002 then paint(frac); return end
    Tween(self.key, 0.35, function(u) paint(lerp(from, frac, u)) end, { ease = "out4" })
  end
  return f
end
function UI.Page(key) return tabs[key] and tabs[key].frame or nil end
local function TabFrame(key)
  local f = CreateFrame("Frame", nil, side)
  f:SetPoint("TOPLEFT", 0, -(TABS_H + 4)); f:SetPoint("BOTTOMRIGHT", 0, 2); f:Hide()
  tabs[key] = { frame = f }
  return f
end

local HERO_H = 96
-- the hero card: a band of the class's own painting, the build's name, a progress bar and what comes next
local function MakeHero(parent, y)
  -- the hero card: a band of the class's own painting, the build's name, a progress bar and what comes next
  local hero = CreateFrame("Frame", nil, parent); hero:SetPoint("TOPLEFT", PAD, y or -6); hero:SetSize(PAGE_W, HERO_H)
  hero.art = hero:CreateTexture(nil, "BACKGROUND"); hero.art:SetAllPoints(); hero.art:SetTexture(WHITE); hero.art:SetVertexColor(0.1, 0.1, 0.1, 1)
  hero.shade = hero:CreateTexture(nil, "BORDER"); hero.shade:SetAllPoints(); hero.shade:SetTexture(WHITE); Gradient(hero.shade, "VERTICAL", 0, 0, 0, 0.82, 0, 0, 0, 0.05)
  hero.edge = Edges(hero, hero, "OVERLAY", 0); hero.edge:SetColor(0.78, 0.61, 0.10, 0.6)
  hero.title = Text(hero, 15, C.gold, true); hero.title:SetPoint("TOPLEFT", 12, -10); hero.title:SetPoint("TOPRIGHT", -12, -10); hero.title:SetJustifyH("LEFT"); hero.title:SetWordWrap(false); hero.title:SetShadowColor(0, 0, 0, 1); hero.title:SetShadowOffset(1, -1)
  hero.sub = Text(hero, 12, C.ink2); hero.sub:SetPoint("TOPLEFT", 12, -32); hero.sub:SetPoint("TOPRIGHT", -12, -32); hero.sub:SetJustifyH("LEFT"); hero.sub:SetWordWrap(false); hero.sub:SetShadowColor(0, 0, 0, 1); hero.sub:SetShadowOffset(1, -1)
  hero.bar = Bar(hero, PAGE_W - 24, 6); hero.bar:SetPoint("TOPLEFT", 12, -52)
  hero.count = Text(hero, 10, C.muted); hero.count:SetPoint("TOPRIGHT", -12, -62); hero.count:SetJustifyH("RIGHT")
  hero.next = Text(hero, 11, C.green); hero.next:SetPoint("TOPLEFT", 12, -62); hero.next:SetPoint("TOPRIGHT", -70, -62); hero.next:SetJustifyH("LEFT"); hero.next:SetWordWrap(false); hero.next:SetShadowColor(0, 0, 0, 1); hero.next:SetShadowOffset(1, -1)
  hero.nextIcon = hero:CreateTexture(nil, "OVERLAY"); hero.nextIcon:SetSize(18, 18); hero.nextIcon:SetPoint("TOPLEFT", 12, -74); hero.nextIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  hero.nextName = Text(hero, 12, C.ink); hero.nextName:SetPoint("TOPLEFT", 36, -76); hero.nextName:SetWidth(PAGE_W - 48); hero.nextName:SetJustifyH("LEFT")
  hero.nextBtn = CreateFrame("Button", nil, hero); hero.nextBtn:SetPoint("TOPLEFT", 8, -72); hero.nextBtn:SetPoint("TOPRIGHT", -8, -72); hero.nextBtn:SetHeight(22)
  hero.nextBtn:SetHighlightTexture(WHITE); hero.nextBtn:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
  hero.nextBtn:SetScript("OnEnter", function(self) local b = hero.nextTile; if b then UI.ShowTip(b, self, nil); Land(b, true) end end)
  hero.nextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  hero.nextBtn:SetScript("OnClick", function() local b = hero.nextTile; if b then Land(b, true) end end); hero.nextName:SetWordWrap(false); hero.nextName:SetShadowColor(0, 0, 0, 1); hero.nextName:SetShadowOffset(1, -1)
  -- a band of the game's own painting for the lead tree: one third of the triptych, a strip of it at the card's shape
  function hero:SetArt(cf, lead)
    local c = D.classes[cf]; local name = c and "talent-background-" .. c.name:lower()
    local ok, info = pcall(function() return name and AtlasOK(name) and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) end)
    if ok and info and info.file and info.leftTexCoord then
      local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
      local pw = (r - l) / 3; local x0 = l + pw * (lead - 1)
      local band = pw * (HERO_H / PAGE_W) * ((info.width or 2046) / (info.height or 1177))
      local y0 = t + (b - t) * 0.30
      pcall(self.art.SetTexture, self.art, info.file); pcall(self.art.SetTexCoord, self.art, x0, x0 + pw, y0, math.min(b, y0 + band)); self.art:SetVertexColor(1, 1, 1, 1)
      self.artOK = true
    else
      self.art:SetTexture(WHITE); self.art:SetTexCoord(0, 1, 0, 1); local cr, cg, cb = TF.ClassColor(cf); self.art:SetVertexColor(cr * 0.25, cg * 0.25, cb * 0.25, 1); self.artOK = false
    end
  end
  function hero:Update(p, cd, live)
    local view, partial = TF.ViewRanks(p); local vp = partial and { cls = p.cls, level = p.level, ranks = view } or p
    local total, pool = TF.TotalPts(p), TF.Pool({ cls = p.cls, level = 60, ranks = p.ranks })
    local lead, best = 1, -1
    for ti = 1, #cd.trees do local n = TF.TreePts(p, ti); if n > best then best, lead = n, ti end end
    if hero.artFor ~= p.cls .. lead then hero.artFor = p.cls .. lead; hero:SetArt(p.cls, lead) end
    local cr, cg, cb = TF.ClassColor(p.cls)
    local title
    if S().starter and isOwnClass() then local b = TF.TopBuild(p.cls); title = b and string.format("Following the #%d %s build", b.rank or 1, b.lead or cd.trees[lead].name) or "Following the top build"
    elseif total == 0 then title = string.format("Your %s plan", cd.name)
    else title = string.format("%s %s", cd.trees[lead].name, cd.name) end
    hero.title:SetText(title); hero.title:SetTextColor(cr, cg, cb)
    local parts = {}
    for ti = 1, #cd.trees do parts[ti] = TF.TreePts(p, ti) end
    hero.sub:SetText(total > 0 and string.format("%s%s at level %d", TF.PlanNamed(p.cls) and (TF.PlanName() .. ", ") or "", table.concat(parts, " / "), TF.FullLevel(p)) or string.format("No points yet. They start at level %d.", TF.StartLevel()))
    hero.bar:Set(pool > 0 and total / pool or 0, cr, cg, cb)
    hero.count:SetText(string.format("%d / %d", total, pool))
    local e, why = TF.WhyNext(p)
    if e then
      local t = cd.trees[e.ti].talents[e.i]
      hero.next:SetText(string.format("NEXT POINT, LEVEL %d", e.level)); hero.next:SetTextColor(rgb(C.green))
      hero.nextIcon:SetTexture(IconFor(t)); hero.nextIcon:Show(); hero.nextName:SetText(string.format("%s %d/%d", t.name, e.rank, t.max)); hero.nextName:Show()
      hero.nextTile = trees[e.ti] and trees[e.ti].tiles[e.i]; hero.nextBtn:EnableMouse(hero.nextTile ~= nil)
    elseif total > 0 then
      hero.next:SetText(total >= pool and "EVERY POINT PLACED" or "PLAN COMPLETE FOR NOW"); hero.next:SetTextColor(rgb(C.gold))
      hero.nextIcon:Hide(); hero.nextName:SetText(""); hero.nextName:Hide(); hero.nextTile = nil; hero.nextBtn:EnableMouse(false)
    else
      hero.next:SetText("START"); hero.next:SetTextColor(rgb(C.gold)); hero.nextTile = nil; hero.nextBtn:EnableMouse(false)
      hero.nextIcon:Hide(); hero.nextName:SetText("Click a talent, or take a popular build."); hero.nextName:Show(); hero.nextName:ClearAllPoints(); hero.nextName:SetPoint("TOPLEFT", 12, -76); hero.nextName:SetWidth(PAGE_W - 24)
    end
    if e then hero.nextName:ClearAllPoints(); hero.nextName:SetPoint("TOPLEFT", 36, -76); hero.nextName:SetWidth(PAGE_W - 48) end
  
  end
  return hero
end

-- Plan: one line per point
local function BuildPlanTab()
  local f = TabFrame("plan")
  f.scroll = CreateFrame("ScrollFrame", "TalentsForeverBookPlanScroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", PAD, -26); f.scroll:SetPoint("BOTTOMRIGHT", -28, 10); Slim(f.scroll)
  f.cap = Text(f, 10, C.muted); f.cap:SetPoint("TOPLEFT", 12, -12); f.cap:SetPoint("TOPRIGHT", -28, -12); f.cap:SetJustifyH("LEFT"); f.cap:SetWordWrap(false)
  f.cap:SetText("A POINT PER LEVEL, IN ORDER")
  f.list = CreateFrame("Frame", nil, f.scroll); f.list:SetSize(PAGE_W, 10); f.scroll:SetScrollChild(f.list)
  f.rows = {}
  f.empty = Text(f, 13, C.muted); f.empty:SetPoint("TOPLEFT", 12, -14); f.empty:SetPoint("TOPRIGHT", -28, -14); f.empty:SetJustifyH("LEFT"); f.empty:SetWordWrap(true)
  f.start = Button(f, "See popular builds", "auto", 24, function() UI.SetTab("popular") end); f.start:SetPoint("TOPLEFT", f.empty, "BOTTOMLEFT", 0, -12); f.start:Hide()
  f.follow = Button(f, "Follow the top build", "auto", 24, function() UI.SetStarter(true) end); f.follow:SetPoint("TOPLEFT", f.start, "BOTTOMLEFT", 0, -8); f.follow:Hide()
  Tip(f.follow, "Follow the top build", "The most popular build for your class becomes your plan. Each level, a card asks before the next point goes in. Change a point by hand and it stops following.")
  local function Row(k)
    local r = f.rows[k]
    if r then return r end
    r = CreateFrame("Button", nil, f.list)
    r:SetSize(PAGE_W, ROW_H); r:SetPoint("TOPLEFT", 0, -(k - 1) * ROW_H)
    r.bg = Solid(r, "BACKGROUND", C.gold, 0); r.bg:SetAllPoints()
    r.lv = Text(r, 12, C.gold); r.lv:SetPoint("LEFT", 0, 0); r.lv:SetWidth(24); r.lv:SetJustifyH("RIGHT")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.lv, "RIGHT", 6, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = Text(r, 12, C.ink); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -34, 0); r.name:SetWordWrap(false)
    r.rank = Text(r, 11, C.ink2); r.rank:SetPoint("RIGHT", -4, 0); r.rank:SetJustifyH("RIGHT")
    r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetTexture(MEDIA .. "check.tga"); r.check:SetSize(14, 14); r.check:SetPoint("RIGHT", -4, 0); r.check:SetVertexColor(rgb(C.green))
    r.pulse = Pulse(r.bg, 0.08, 0.22, 1.1)
    r:SetScript("OnEnter", function(self)
      local b = trees[self.ti] and trees[self.ti].tiles[self.i]
      if b then
        UI.ShowTip(b, self, nil, function()
          local why = self.k and TF.WhyPoint(plan(), self.k) or {}
          if #why > 0 then GameTooltip:AddLine(" "); GameTooltip:AddLine("Why here", 1, 0.82, 0); for _, w in ipairs(why) do GameTooltip:AddLine(w, 0.74, 0.74, 0.74, true) end end
          local spells = self.level and TF.NewSpellsAt(plan().cls, self.level) or {}
          if #spells > 0 then GameTooltip:AddLine(" "); GameTooltip:AddLine(string.format("Trainer at level %d", self.level), 1, 0.82, 0); GameTooltip:AddLine(TF.SpellsSummary(spells), 0.74, 0.74, 0.74, true) end
        end)
        Land(b, true)
      end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
      Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
      if self.level then TF.SetLevel(self.level) end
      local b = trees[self.ti] and trees[self.ti].tiles[self.i]; if b then Land(b, true) end
    end)
    f.rows[k] = r
    return r
  end
  tabs.plan.refresh = function()
    local p = plan(); local cd = classData()
    local list = TF.NextUp(p)
    local live = isOwnClass() and TF.LiveRanks(p.cls)
    for _, r in ipairs(f.rows) do r:Hide(); r.pulse:Stop() end
    if #list == 0 then
      f.empty:SetText(string.format("The plan writes itself here, one line per level from %d. Or begin from what other %ss built.", TF.StartLevel(), cd.name))
      f.empty:Show(); f.start:Show(); f.follow:SetShown(isOwnClass() and TF.TopBuild(plan().cls) ~= nil); f.cap:Hide(); f.list:SetHeight(10)
      local eh = math.ceil(math.max(f.empty:GetStringHeight() or 0, estHeight(f.empty:GetText() or "", PAGE_W - 40, 13)))
      f.start:ClearAllPoints(); f.start:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(14 + eh + 12))   -- whole pixels: a text's measured bottom can be a half
      return
    end
    f.empty:Hide(); f.start:Hide(); f.follow:Hide(); f.cap:Show()
    local nextSeen, lvl = false, UnitLevel("player")
    for k, e in ipairs(list) do
      local r = Row(k); r:Show(); r.ti, r.i, r.level, r.k = e.ti, e.i, e.level, k
      local t = cd.trees[e.ti].talents[e.i]
      r.lv:SetText(e.level); r.icon:SetTexture(IconFor(t)); r.name:SetText(t.name); r.rank:SetText(e.rank .. "/" .. t.max)
      local isNext = live and not e.done and not nextSeen
      if isNext then nextSeen = true end
      r.check:SetShown(live and e.done and true or false)
      r.rank:SetShown(not (live and e.done))
      r.bg:SetAlpha(isNext and 0.18 or 0)
      if isNext then r.pulse:Play() end
      local dim = live and e.done
      r.name:SetTextColor(rgb(dim and C.muted or (isNext and C.gold or C.ink)))
      r.lv:SetTextColor(rgb(dim and C.muted or ((e.level <= lvl) and C.gold or C.ink2)))
      r.icon:SetDesaturated(dim and true or false); r.icon:SetAlpha(dim and 0.55 or 1)
      r.dimTo = (e.level > p.level) and 0.35 or 1; r:SetAlpha(r.dimTo)
    end
    f.list:SetHeight(#list * ROW_H + 4)
    if f.spinPending then f.spinPending = false; SpinRows(f.rows, ROW_H, #list) end
  end
end

-- Home: the hub. The featured build, one thing that needs you, this level's progress, and the way to every page.
local function BuildHomeTab()
  local f = TabFrame("home")
  f.hero = MakeHero(f, -6)
  -- the strip: the one thing that needs you now, with the button that does it
  local a = CreateFrame("Frame", nil, f); a:SetPoint("TOPLEFT", PAD, -(HERO_H + 12)); a:SetSize(PAGE_W, 54); f.alert = a
  a.bg = Solid(a, "BACKGROUND", C.raised, 0.6); a.bg:SetAllPoints()
  a.edge = Edges(a, a, "OVERLAY", 0)
  a.icon = a:CreateTexture(nil, "ARTWORK"); a.icon:SetSize(24, 24); a.icon:SetPoint("LEFT", 8, 0); a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  a.iconEdge = Edges(a, a.icon, "OVERLAY", 1); a.iconEdge:SetColor(0, 0, 0, 0.9)
  a.title = Text(a, 13, C.gold); a.title:SetPoint("TOPLEFT", 40, -7); a.title:SetWidth(PAGE_W - 48); a.title:SetJustifyH("LEFT"); a.title:SetWordWrap(false)
  a.body = Text(a, 12, C.ink2); a.body:SetPoint("TOPLEFT", 40, -25); a.body:SetWidth(PAGE_W - 48); a.body:SetJustifyH("LEFT"); a.body:SetJustifyV("TOP"); a.body:SetWordWrap(true); a.body:SetHeight(28)
  a.btn = Button(a, "Learn it", "auto", 20, function() if a.fn then a.fn() end end); a.btn:SetPoint("TOPRIGHT", -8, -4); a.btn.minW = 72
  -- this level: how far to the next one, and what the plan places when it comes
  local x = CreateFrame("Frame", nil, f); x:SetPoint("TOPLEFT", PAD, -(HERO_H + 72)); x:SetSize(PAGE_W, 54); f.xp = x
  x.bg = Solid(x, "BACKGROUND", C.raised, 0.35); x.bg:SetAllPoints(); x.edge = Edges(x, x, "OVERLAY", 0); x.edge:SetColor(0.78, 0.61, 0.10, 0.3)
  x.head = Text(x, 11, C.muted); x.head:SetPoint("TOPLEFT", 10, -7); x.head:SetText("YOU ARE LEVEL 1")
  x.right = Text(x, 11, C.muted); x.right:SetPoint("TOPRIGHT", -10, -7); x.right:SetJustifyH("RIGHT")
  x.bar = Bar(x, PAGE_W - 20, 8); x.bar:SetPoint("TOPLEFT", 10, -23)
  x.line = Text(x, 12, C.ink2); x.line:SetPoint("TOPLEFT", 10, -36); x.line:SetPoint("TOPRIGHT", -10, -36); x.line:SetJustifyH("LEFT"); x.line:SetWordWrap(false)
  -- coming up: the next five points of the plan from where the character stands. Hover lights the tile and opens
  -- its tooltip beside the window; a click looks at the build as it stands at that level.
  f.comingSec = Section(f, "AFTER THAT", -(HERO_H + 134))
  f.coming = {}
  for k = 1, 4 do
    local r = CreateFrame("Button", nil, f); r:SetSize(PAGE_W, 21); r:SetPoint("TOPLEFT", PAD, -(HERO_H + 152 + (k - 1) * 21))
    r:SetHighlightTexture(WHITE); r:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
    r.level = Text(r, 12, C.gold); r.level:SetPoint("LEFT", 0, 0); r.level:SetWidth(22); r.level:SetJustifyH("RIGHT")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(17, 17); r.icon:SetPoint("LEFT", 30, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.iconEdge = Edges(r, r.icon, "OVERLAY", 1); r.iconEdge:SetColor(0, 0, 0, 0.9)
    r.name = Text(r, 13, C.ink); r.name:SetPoint("LEFT", 53, 0); r.name:SetPoint("RIGHT", -40, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.rank = Text(r, 12, C.ink2); r.rank:SetPoint("RIGHT", -4, 0); r.rank:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self) local b = self.tile; if b then UI.ShowTip(b, self, nil, function() GameTooltip:AddLine(" "); GameTooltip:AddLine(string.format("Level %d in your plan. Click to see the build as it stands then.", self.level0 or 0), 0.54, 0.54, 0.54, true) end); Land(b, true) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) local b = self.tile; if self.level0 then TF.SetLevel(self.level0) end; if b then Land(b, true) end end)
    f.coming[k] = r
  end
  f.comingNone = Text(f, 12, C.muted); f.comingNone:SetPoint("TOPLEFT", PAD, -(HERO_H + 154)); f.comingNone:SetPoint("TOPRIGHT", -PAD, -(HERO_H + 154)); f.comingNone:SetJustifyH("LEFT"); f.comingNone:SetWordWrap(true)
  -- since Classic: what changed for this class, in one line; the row opens the Classic page. Under it the two switches
  -- for the trees (the Classic marks, the pick rates), where they can be seen: they used to live on the Classic page only
  f.classicSec = Section(f, "SINCE CLASSIC", -(HERO_H + 244))
  local cr = CreateFrame("Button", nil, f); cr:SetSize(PAGE_W, 22); cr:SetPoint("TOPLEFT", PAD, -(HERO_H + 262)); f.classicRow = cr
  cr:SetHighlightTexture(WHITE); cr:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
  cr.text = Text(cr, 13, C.ink); cr.text:SetPoint("LEFT", 0, 0); cr.text:SetPoint("RIGHT", -18, 0); cr.text:SetJustifyH("LEFT"); cr.text:SetWordWrap(false)
  cr.arrow = Text(cr, 13, C.gold); cr.arrow:SetPoint("RIGHT", -4, 0); cr.arrow:SetText(">")
  cr:SetScript("OnClick", function() UI.SetTab("classic") end)
  Tip(cr, "Compare to Classic", "Every talent that is new, changed, moved or gone since Classic, tree by tree, with the Classic text beside it.")
  f.marks = Check(f, "Compare to Classic", function() return S().marks end, function(v) S().marks = v end)
  f.picks = Check(f, "Pick rates", function() return S().pickRates end, function(v) S().pickRates = v end)
  Tip(f.marks, "Compare to Classic", "Like the site: a gold edge on a talent new in Forever, blue on one that changed, purple on one that moved. Hover a tile for the Classic text.")
  Tip(f.picks, "Pick rates on the trees", "The share of this class's builds on the site with at least one point in the talent, on every tile.")
  tabs.home.refresh = function()
    local p = plan(); local cd = classData(); local own = isOwnClass()
    local live = own and TF.LiveRanks(p.cls)
    f.hero:Update(p, cd, live)
    -- the strip, by what matters most right now
    local lvl = UnitLevel("player") or 1
    local total, pool = TF.TotalPts(p), TF.Pool({ cls = p.cls, level = 60, ranks = p.ranks })
    local e = TF.WhyNext(p); local nt = e and cd.trees[e.ti].talents[e.i]
    local owed = own and TF.OwedSpells() or nil
    local icon, title, body, label, fn, tone
    if not own then
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = string.format("A %s plan", cd.name); body = string.format("Save it, share it, try builds on it. Apply waits for a %s.", cd.name); tone = C.muted
    elseif G.live and G.Unspent() > 0 and nt and G.CanApply() then
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = string.format("%d unspent point%s", G.Unspent(), G.Unspent() == 1 and "" or "s"); body = "Learn it places your plan's next point."; label = "Learn it"; fn = UI.ApplyNext; tone = C.gold
    elseif total == 0 then
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = "No plan yet"; body = string.format("Start from what other %ss built.", cd.name); label = "Popular"; fn = function() UI.SetTab("popular") end; tone = C.gold
    elseif owed and #owed > 0 then
      icon = IconFor({ icon = owed[1].icon }); title = string.format("%d spell%s at the trainer", #owed, #owed == 1 and "" or "s"); local ct = TF.OwedCostText(owed); body = ct and (ct .. " to learn.") or "Waiting at your class trainer."; label = "The list"; fn = function() UI.OpenTrainer() end; tone = C.gold
    elseif G.live and lvl < TF.StartLevel() then
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = string.format("Points start at level %d", TF.StartLevel()); body = string.format("You are %d. The plan is ready for then.", lvl); tone = C.green
    elseif total >= pool then
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = "Every point placed"; body = "The plan is complete. Share it."; label = "Share"; fn = function() UI.OpenSheet("share") end; tone = C.green
    else
      icon = "Interface\\Icons\\ClassIcon_" .. cd.name; title = "Up to date"; body = string.format("%d of %d points planned. Nothing to do until you level.", total, pool); tone = C.green
    end
    a.icon:SetTexture(icon); a.title:SetText(title); a.body:SetText(body); a.title:SetTextColor(rgb(tone))
    a.edge:SetColor(tone[1], tone[2], tone[3], 0.55)
    a.fn = fn; a.btn:SetShown(label ~= nil); if label then a.btn:SetText(label); a.btn:Fit() end
    local room = label and (math.max(72, a.btn:GetWidth() or 72) + 18) or 8
    a.title:SetWidth(PAGE_W - 40 - room); a.body:SetWidth(PAGE_W - 48)
    -- this level
    local xp, xpMax = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player")
    local frac = (xp and xpMax and xpMax > 0) and xp / xpMax or nil
    if lvl >= 60 then x.head:SetText("YOU ARE LEVEL 60"); x.right:SetText(""); x.bar:Set(1, 0.42, 0.05, 0.50); x.line:SetText(string.format("All %d points earned. %d of them planned.", pool, total))
    else
      x.head:SetText(string.format("YOU ARE LEVEL %d", lvl))
      if frac then x.bar:Set(frac, 0.42, 0.05, 0.50); x.right:SetText(string.format("%d%% TO %d", math.floor(frac * 100 + 0.5), lvl + 1))
      else x.bar:Set(0); x.right:SetText(string.format("TO %d", lvl + 1)) end
      local coming
      for _, en in ipairs(TF.NextUp(p)) do if en.level > lvl and not en.done then coming = en; break end end
      if coming then local ct = cd.trees[coming.ti].talents[coming.i]; x.line:SetText(string.format("Level %d brings %s %d/%d.", coming.level, ct.name, coming.rank, ct.max))
      elseif nt then x.line:SetText(string.format("Next point: %s %d/%d.", nt.name, e.rank, nt.max))
      else x.line:SetText("Nothing planned past this level yet.") end
    end
    x.bar.fill:SetShown(true)
    -- coming up
    local k, skipped = 0, false
    for _, en in ipairs(TF.NextUp(p)) do
      if k >= 4 then break end
      if not en.done and not skipped then skipped = true   -- the first one is the hero's next point
      elseif not en.done then
        k = k + 1; local r = f.coming[k]; local ct = cd.trees[en.ti].talents[en.i]
        r.level:SetText(en.level); r.icon:SetTexture(IconFor(ct)); r.name:SetText(ct.name); r.rank:SetText(string.format("%d/%d", en.rank, ct.max))
        r.tile = trees[en.ti] and trees[en.ti].tiles[en.i]; r.level0 = en.level; r:Show()
      end
    end
    for j = k + 1, 4 do f.coming[j]:Hide(); f.coming[j].tile = nil; f.coming[j].level0 = nil end
    f.comingSec:SetShown(total > 0)
    local cy = total > 0 and (HERO_H + 244) or (HERO_H + 134)
    f.classicSec:ClearAllPoints(); f.classicSec:SetPoint("TOPLEFT", 12, -cy)
    cr:ClearAllPoints(); cr:SetPoint("TOPLEFT", PAD, -(cy + 18))
    f.marks:ClearAllPoints(); f.marks:SetPoint("TOPLEFT", PAD - (f.marks.air or 0), -(cy + 42)); f.marks:SetChecked(S().marks)
    f.picks:ClearAllPoints(); f.picks:SetPoint("TOPLEFT", PAD + 186 - (f.picks.air or 0), -(cy + 42)); f.picks:SetChecked(S().pickRates)
    if total == 0 then f.comingNone:Hide()
    elseif k == 0 then
      f.comingNone:SetText(total == 0 and "Nothing planned yet. Click a talent on the trees, or take a popular build." or (skipped and "That is the last point of the plan." or "Every planned point is placed. Add more on the trees."))
      f.comingNone:Show()
    else f.comingNone:Hide() end
    -- since Classic
    local nn, nc, nm = 0, 0, 0
    for _, tr in ipairs(cd.trees) do for _, ct in ipairs(tr.talents) do if ct.classic == "new" then nn = nn + 1 elseif ct.classic == "changed" then nc = nc + 1 elseif ct.classic == "moved" then nm = nm + 1 end end end
    local gone = cd.removed and #cd.removed or 0
    cr.text:SetText(string.format("%d new, %d changed, %d moved%s.", nn, nc, nm, gone > 0 and string.format(", %d gone", gone) or ""))
  end
end

-- a link as a code a phone's camera reads: a cream plate, the cells as big as the page allows
local function MakeQR(parent, w)
  local q = CreateFrame("Frame", nil, parent); q:SetSize(10, 10); q:Hide()
  q.plate = q:CreateTexture(nil, "BACKGROUND"); q.plate:SetTexture(WHITE); q.plate:SetAllPoints(); q.plate:SetVertexColor(0.94, 0.90, 0.82, 1)
  q.edge = Edges(q, q, "BORDER", 0); q.edge:SetColor(0.78, 0.61, 0.10, 0.9)
  q.cells = {}
  -- true when the link fits a code; false (and the plate small) when it is too long for a phone
  function q:Draw(url)
    if self.url == url then return self.ok end
    self.url = url
    local m, n = TF.QR(url)
    for _, c in ipairs(self.cells) do c:Hide() end
    if not m then self:SetSize(10, 10); self.ok = false; return false end
    local px = math.max(2, math.min(5, math.floor((w - 16) / (n + 8))))
    self:SetSize((n + 8) * px, (n + 8) * px)
    local k = 0
    for y = 0, n - 1 do
      local x = 0
      while x < n do
        if m[y][x] then
          local x0 = x
          while x < n and m[y][x] do x = x + 1 end
          k = k + 1
          local c = self.cells[k]
          if not c then c = self:CreateTexture(nil, "ARTWORK"); c:SetTexture(WHITE); c:SetVertexColor(0.09, 0.06, 0.03, 1); self.cells[k] = c end
          c:ClearAllPoints(); c:SetPoint("TOPLEFT", self, "TOPLEFT", (4 + x0) * px, -(4 + y) * px); c:SetSize((x - x0) * px, px + 0.2); c:Show()
        else x = x + 1 end
      end
    end
    self.ok = true
    return true
  end
  return q
end

-- Builds: three plain blocks. Share this plan (the link, Copy, then a phone code or chat), load one (a link or a
-- targeted player), the builds saved on the account with the box that names them, and at the foot a card of the
-- popular builds so a first visit finds them.
local function BuildBuildsTab()
  local f = TabFrame("builds")
  local W = PAGE_W
  local function label(text, y, gap) return Section(f, text, y, gap) end
  local function shared() return f.shareRec and TF.Decode(f.shareRec.code) or nil end
  -- share
  f.linkLabel = label("SHARE THIS PLAN", -8)
  f.link = EditBox(f, W - 72, 24); f.link:SetPoint("TOPLEFT", 12, -26); f.link.selectAll = true
  f.link.hint:Hide()
  f.link:SetScript("OnTextChanged", function(self) if self:GetText() ~= (f.url or "") then self:SetText(f.url or ""); self:HighlightText() end end)
  f.link:SetScript("OnMouseUp", function(self)
    if IsShiftKeyDown and IsShiftKeyDown() then if TF.InsertLink(f.shareRec and TF.Decode(f.shareRec.code) or plan()) then UI.Note("Link put in the chat box.") end; return end
    self:HighlightText()
  end)
  f.copy = Button(f, "Select", 64, 24, function(self) f.link:SetFocus(); f.link:HighlightText(); UI.CopyCue(self); UI.Note("Link selected. Now press Ctrl+C, then paste it anywhere: Discord, a browser, a friend.", nil, 8) end); f.copy:SetPoint("LEFT", f.link, "RIGHT", 8, 0)
  Tip(f.copy, "Select the link", "Selects the whole link so Ctrl+C takes it. No addon can copy to the clipboard for you; the game does not allow it.")
  f.copyCap = Text(f, 10, C.muted); f.copyCap:SetPoint("TOPLEFT", 12, -80); f.copyCap:SetPoint("TOPRIGHT", -28, -80); f.copyCap:SetJustifyH("LEFT"); f.copyCap:SetWordWrap(false)
  f.copyCap:SetText("Select, then Ctrl+C. An addon cannot copy for you.")
  local bw = (W - 24) / 4
  f.qrBtn = Button(f, "Phone QR", bw, 20, function() f.qrOn = not f.qrOn; if not f.qrOn then f.qrAlt = nil end; tabs.builds.refresh() end); f.qrBtn:SetPoint("TOPLEFT", 12, -58)
  Tip(f.qrBtn, "Open it on your phone", "Shows this link as a code. Point your phone's camera at it and the same build opens on talentsforever.com.")
  f.party = Button(f, "Party", bw, 20, function()
    if IsShiftKeyDown and IsShiftKeyDown() then local ok, why = TF.AskParty(); UI.Note(ok and "Asked your group for their builds. Each one arrives as a card." or why); return end
    local ok = TF.SendBuild(IsInRaid and IsInRaid() and "RAID" or "PARTY", nil, shared()); UI.Note(ok and "Sent to the group. Anyone with the addon can try it on their trees." or "Posted the link to the group.")
  end); f.party:SetPoint("LEFT", f.qrBtn, "RIGHT", 8, 0)
  f.guild = Button(f, "Guild", bw, 20, function() local ok = TF.SendBuild("GUILD", nil, shared()); UI.Note(ok and "Sent to the guild. Anyone with the addon can try it on their trees." or "Posted the link to the guild.") end); f.guild:SetPoint("LEFT", f.party, "RIGHT", 8, 0)
  f.whisper = Button(f, "To target", bw, 20, function()
    local who = UnitName and UnitIsPlayer and UnitIsPlayer("target") and UnitName("target") or nil
    if not who then UI.Note("Target a player first, then press To target."); return end
    TF.SendBuild("WHISPER", who, shared()); UI.Note("Sent to " .. who .. ".")
  end); f.whisper:SetPoint("LEFT", f.guild, "RIGHT", 8, 0)
  Tip(f.party, "Send to your group", "Posts the link in party or raid chat and hands the build to anyone there who runs the addon. Shift-click asks the group for THEIR builds instead.")
  Tip(f.guild, "Send to your guild", "Posts the link in guild chat and hands the build to anyone there who runs the addon.")
  Tip(f.whisper, "Whisper it to your target", "Target a player and press this: the link goes to them in a whisper. If they run the addon they can try it on their trees.")
  -- load
  f.pasteLabel = label("LOAD A BUILD", -94, 118)
  f.inspect = Button(f, "Inspect target", "auto", 20, function() local ok, why = TF.RequestInspect("target"); if not ok then UI.Note(why) else UI.Note("Asking the game for their talents...") end end)
  f.inspect:SetPoint("TOPRIGHT", f, "TOPLEFT", 12 + W, -90)
  Tip(f.inspect, "Someone else's build", "Target a player and press this: their talents come back as a build you can try or load.")
  f.paste = EditBox(f, W - 80, 24); f.paste:SetPoint("TOPLEFT", 12, -112); f.paste.hint:SetText("Paste a link or a code")
  f.load = Button(f, "Load", 72, 24, function()
    local ok, err, back = TF.LoadCode(f.paste:GetText())
    if ok then f.paste:SetText(""); f.paste:ClearFocus(); Sound("IG_MAINMENU_OPEN"); UI.Note("Build loaded into the plan." .. TF.SettledText(back), { { label = "Undo", fn = function() TF.Undo() end } }, back and 12 or nil); if back then UI.SettledCard(back) end
    else UI.Note(err or "That did not read as a build.") end
  end); f.load:SetPoint("LEFT", f.paste, "RIGHT", 8, 0)
  f.paste:SetScript("OnEnterPressed", function() f.load:Click() end)
  -- saved
  f.savedLabel = label("SAVED BUILDS", -152)
  f.name = EditBox(f, W - 80, 24); f.name:SetPoint("TOPLEFT", 12, -170); f.name.hint:SetText("Name this plan")
  f.save = Button(f, "Save", 72, 24, function()
    local rec = TF.SaveBuild(f.name:GetText()); f.name:SetText(""); f.name:ClearFocus(); UI.Note("Saved as " .. rec.name .. ".")
  end); f.save:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
  f.name:SetScript("OnEnterPressed", function() f.save:Click() end)
  Tip(f.save, "Save the plan you have open", "Kept on this account, for every character. It opens on the site too.")
  f.list = ListRows(f, W, 36, 202, 88, true)
  f.empty = Text(f, 12, C.muted); f.empty:SetPoint("TOPLEFT", 12, -206); f.empty:SetPoint("TOPRIGHT", -28, -206); f.empty:SetWordWrap(true); f.empty:SetJustifyH("LEFT")
  f.empty:SetText("Nothing saved yet. Name the plan above and press Save.")
  -- popular: a card at the foot with the five most shared builds as faces; one click loads one
  local pc = CreateFrame("Frame", nil, f); pc:SetPoint("TOPLEFT", 12, -331); pc:SetSize(W, 74); f.popCard = pc
  pc.bg = Solid(pc, "BACKGROUND", C.raised, 0.7); pc.bg:SetAllPoints(); pc.edge = Edges(pc, pc, "OVERLAY", 0); pc.edge:SetColor(1, 0.82, 0, 0.8)
  pc.title = Text(pc, 12, C.gold); pc.title:SetPoint("TOPLEFT", 10, -8); pc.title:SetText("POPULAR BUILDS")
  pc.all = Button(pc, "See all", "auto", 20, function() UI.SetTab("popular") end); pc.all:SetPoint("TOPRIGHT", -6, -4)
  Tip(pc.all, "Popular builds", "What other players of your class build, from the site. Try one on your trees, or load it.")
  pc.btns = {}
  for k = 1, 5 do
    local b = CreateFrame("Button", nil, pc); b:SetSize(34, 34); b:SetPoint("TOPLEFT", 10 + (k - 1) * 42, -30)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.edge = Edges(b, b, "OVERLAY", 1); b.edge:SetColor(0.78, 0.61, 0.10, 0.9)
    b:SetHighlightTexture(WHITE); local hl = b:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 0.82, 0, 0.2) end
    b.rank = Text(b, 10, C.gold); b.rank:SetPoint("BOTTOMRIGHT", -2, 1); b.rank:SetShadowColor(0, 0, 0, 1); b.rank:SetShadowOffset(1, -1)
    b:SetScript("OnEnter", function(self)
      local pb = self.b; if not pb then return end
      TipBegin(self); GameTooltip:SetText(string.format("#%d %s, %s / %s / %s", pb.rank, pb.lead, tostring(pb.pts[1]), tostring(pb.pts[2]), tostring(pb.pts[3])), 1, 0.82, 0)
      GameTooltip:AddLine(string.format("Shared %d times on the site. Click to make it your plan; Undo brings yours back.", pb.shared or 0), 0.9, 0.9, 0.9, true); TipEnd(self)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
      local pb = self.b; if not pb then return end
      local ok, err, back = TF.LoadCode(pb.code)
      if ok then UI.Note(string.format("Loaded the #%d %s build.", pb.rank, pb.lead) .. TF.SettledText(back), { { label = "Undo", fn = function() TF.Undo() end } }, back and 12 or nil); if back then UI.SettledCard(back) end else UI.Note(err) end
    end)
    pc.btns[k] = b
  end
  -- the phone code takes the whole page while it is up
  f.phoneLabel = label("ON YOUR PHONE", -8, 84); f.phoneLabel:Hide()
  f.phoneLabel.line:ClearAllPoints(); f.phoneLabel.line:SetPoint("LEFT", f.phoneLabel.text, "RIGHT", 8, 0); f.phoneLabel.line:SetPoint("RIGHT", f.qrBtn, "LEFT", -8, 0)
  f.qr = MakeQR(f, W); f.qr:SetPoint("TOP", f, "TOPLEFT", 12 + W / 2, -36)
  f.qrCaption = Text(f, 12, C.ink2); f.qrCaption:SetPoint("TOP", f.qr, "BOTTOM", 0, -12); f.qrCaption:SetWidth(W - 16); f.qrCaption:SetJustifyH("CENTER"); f.qrCaption:SetWordWrap(true); f.qrCaption:Hide()
  f.qrLink = EditBox(f, W - 72, 24); f.qrLink:SetPoint("TOPLEFT", 12, -352); f.qrLink.selectAll = true; f.qrLink.hint:Hide(); f.qrLink:Hide()
  f.qrLink:SetScript("OnTextChanged", function(self) if self:GetText() ~= (f.qrUrl or "") then self:SetText(f.qrUrl or ""); self:HighlightText() end end)
  f.qrLink:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  f.qrCopy = Button(f, "Select", 64, 24, function(self) f.qrLink:SetFocus(); f.qrLink:HighlightText(); UI.CopyCue(self); UI.Note("Link selected. Now press Ctrl+C, then paste it anywhere.", nil, 8) end); f.qrCopy:SetPoint("LEFT", f.qrLink, "RIGHT", 8, 0); f.qrCopy:Hide()
  Tip(f.qrCopy, "Select the link", "Selects the link so Ctrl+C takes it. No addon can copy to the clipboard for you.")
  f.qrLinkCap = Text(f, 11, C.muted); f.qrLinkCap:SetPoint("TOPLEFT", 12, -380); f.qrLinkCap:SetPoint("TOPRIGHT", -28, -380); f.qrLinkCap:SetJustifyH("LEFT"); f.qrLinkCap:SetWordWrap(false); f.qrLinkCap:Hide()
  f.qrLinkCap:SetText("Or Select, then Ctrl+C. An addon cannot copy for you.")
  local function drawQR(url, caption)
    local ok = f.qr:Draw(url)
    f.qrCaption:SetText(ok and (caption or "Point your phone's camera at it. The same build opens on talentsforever.com.") or "This link is too long for a code. Copy it from the box below instead.")
  end
  tabs.builds.refresh = function()
    local builds = TF.db.builds
    if f.shareRec then local still = false; for _, b in ipairs(builds) do if b == f.shareRec then still = true end end; if not still then f.shareRec = nil end end
    local sp = shared()
    f.url = TF.ShareURL(sp or plan())
    f.linkLabel:SetText(f.shareRec and (f.shareRec.name:upper():sub(1, 16) .. "'S LINK") or "SHARE THIS PLAN")
    if f.link:GetText() ~= f.url then f.link:SetText(f.url) end
    f.link:SetCursorPosition(0)
    local qr = f.qrOn and true or false
    for _, w in ipairs({ f.linkLabel, f.link, f.copy, f.copyCap, f.party, f.guild, f.whisper, f.pasteLabel, f.inspect, f.paste, f.load, f.savedLabel, f.name, f.save, f.list, f.popCard }) do w:SetShown(not qr) end
    f.qr:SetShown(qr); f.qrCaption:SetShown(qr); f.phoneLabel:SetShown(qr); f.qrLink:SetShown(qr); f.qrLinkCap:SetShown(qr); f.qrCopy:SetShown(qr)
    if qr then f.qrUrl = f.qrAlt or f.url; if f.qrLink:GetText() ~= f.qrUrl then f.qrLink:SetText(f.qrUrl) end; f.qrLink:SetCursorPosition(0) end
    f.qrBtn:SetText(qr and "Back" or "Phone QR"); f.qrBtn:ClearAllPoints()
    if qr then f.qrBtn:SetPoint("TOPRIGHT", f, "TOPLEFT", 12 + W, -2) else f.qrBtn:SetPoint("TOPLEFT", 12, -58) end
    if qr then drawQR(f.qrAlt or f.url, f.qrAlt and "Point your phone's camera at it. It opens the ideas page on talentsforever.com." or nil) end
    f.empty:SetShown(not qr and #builds == 0)
    f.savedLabel:SetText(#builds > 3 and string.format("SAVED BUILDS (%d, SCROLL FOR MORE)", #builds) or (#builds > 0 and string.format("SAVED BUILDS (%d)", #builds) or "SAVED BUILDS"))
    -- the popular card: this class's five most shared, always there
    local pop = TF.Popular(plan().cls); local c0 = D.classes[plan().cls]
    local pc = f.popCard
    pc.title:SetText(string.format("POPULAR %s BUILDS", c0.name:upper()))
    for k, b in ipairs(pc.btns) do
      local pb = pop and pop.top and pop.top[k]
      if pb then
        local lead = 1; for ti, tree in ipairs(c0.trees) do if tree.name == pb.lead then lead = ti end end
        b.b = pb; b.icon:SetTexture(IconFor({ icon = c0.trees[lead].icon })); b.rank:SetText("#" .. pb.rank); b:Show()
      else b.b = nil; b:Hide() end
    end
    -- your own class first, the rest after, each group in the order they were saved
    local mine = TF.PlayerClass(); local order = {}
    for i, b in ipairs(builds) do if b.cls == mine then order[#order + 1] = i end end
    for i, b in ipairs(builds) do if b.cls ~= mine then order[#order + 1] = i end end
    for row, k in ipairs(order) do
      local b = builds[k]
      local r = f.list:Row(row); local c = D.classes[b.cls]
      local lead = 1; local best = -1
      for ti, v in ipairs(b.pts or {}) do if v > best then best, lead = v, ti end end
      r.icon:SetTexture(IconFor({ icon = c and c.trees[lead].icon or "inv_misc_questionmark" }))
      r.name:SetText(c and string.format("|cff%s%s|r", c.color, b.name) or b.name)
      local me = UnitName and UnitName("player") or nil
      r.sub:SetText(string.format("%s, %s%s%s", table.concat(b.pts or {}, "/"), date("%d %b", b.when), (b.who and b.who ~= me) and (", " .. b.who) or "", b.tag and (", " .. b.tag) or ""))
      r.tag:SetText(b.tag or "mark"); r.tag:SetTextColor(rgb(b.tag and C.gold or C.muted)); if not r.compact then r.tagBtn:Show() end
      r.onTag = function() b.tag = (b.tag == nil and "PvE") or (b.tag == "PvE" and "PvP") or nil; tabs.builds.refresh() end
      local isGhost = TF.trial and TF.trial.name == b.name
      r.accent:SetAlpha((isGhost or f.shareRec == b) and 1 or 0)
      r.ghost:SetText(isGhost and "Stop" or "Try it")
      r.onLoad = function() local ok, err = TF.LoadBuild(k); if ok then UI.Note("Loaded " .. b.name .. ".", { { label = "Undo", fn = function() TF.Undo() end } }) else UI.Note(err) end end
      r.onGhost = function() if isGhost then TF.TrialBack() else local p = TF.Decode(b.code); if p then TF.TryBuild(p, b.name) end end end
      r.onDelete = function() TF.DeleteBuild(k) end
      r.del:Show()
      r:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then local p = TF.Decode(b.code); if p and TF.InsertLink(p) then UI.Note("Link put in the chat box.") end; return end
        f.shareRec = (f.shareRec ~= b) and b or nil; tabs.builds.refresh(); f.link:SetFocus()
      end)
      Tip(r, b.name, string.format("%s, level %d, saved %s%s. Click to put its link in the box above, shift-click to put it in chat. Try it rings its talents on your trees.", c and c.name or "?", b.level or 60, date("%d %b %Y", b.when), b.who and (" on " .. b.who) or ""))
      r.buildCode = b.code
    end
    f.list:Fill(#builds)
  end
end

-- Top: the site's most shared builds for this class, and the talents almost everyone takes or skips
local function BuildPopularTab()
  local f = TabFrame("popular")
  f.list = ListRows(f, PAGE_W, 50, 4, 10, false)
  local body = f.list.child
  f.note = Text(body, 12, C.ink2); f.note:SetPoint("TOPLEFT", 0, -4); f.note:SetPoint("TOPRIGHT", -4, -4); f.note:SetWordWrap(false)
  f.spec = Text(body, 11, C.muted); f.spec:SetPoint("TOPLEFT", 0, -22); f.spec:SetPoint("TOPRIGHT", -4, -22); f.spec:SetWordWrap(true); f.spec:SetJustifyH("LEFT")
  f.list.offset = 44
  f.lines = {}
  -- your group: what the people you play with have planned, above the site's list
  f.gLabel = Text(body, 10, C.muted); f.gLabel:SetPoint("TOPLEFT", 0, -8); f.gLabel:SetText("YOUR GROUP"); f.gLabel:Hide()
  f.ask = Button(body, "Ask for their builds", "auto", 20, function() local ok, why = TF.AskParty(); UI.Note(ok and "Asked your group. Each build lands here as it arrives." or why) end)
  f.ask:SetPoint("TOPRIGHT", -4, -2); f.ask:Hide()
  Tip(f.ask, "Your group's builds", "Everyone in your group who runs the addon answers with their plan. Nothing is posted in chat.")
  f.gNone = Text(body, 11, C.muted); f.gNone:SetPoint("TOPLEFT", 0, -30); f.gNone:SetPoint("TOPRIGHT", -4, -30); f.gNone:SetWordWrap(true); f.gNone:SetJustifyH("LEFT"); f.gNone:Hide()
  f.gNone:SetText("Nothing yet. Press the button; anyone in your group with the addon answers.")
  -- one talent per line: point at it and the tile lights up, with its tooltip beside the window
  local function Line(k)
    local l = f.lines[k]
    if l then return l end
    l = CreateFrame("Button", nil, body); l:SetSize(PAGE_W, 20)
    l.head = Text(l, 10, C.muted); l.head:SetPoint("LEFT", 0, 0)
    l.rule = l:CreateTexture(nil, "ARTWORK"); l.rule:SetTexture(WHITE); l.rule:SetPoint("LEFT", l.head, "RIGHT", 8, 0); l.rule:SetPoint("RIGHT", -4, 0); onePixel(l.rule, true); l.rule:SetVertexColor(0.78, 0.61, 0.10, 0.35)
    l.name = Text(l, 12, C.ink2); l.name:SetPoint("LEFT", 10, 0); l.name:SetPoint("RIGHT", -52, 0); l.name:SetWordWrap(false)
    l.pct = Text(l, 12, C.ink2); l.pct:SetPoint("RIGHT", -8, 0); l.pct:SetJustifyH("RIGHT")
    l:SetHighlightTexture(WHITE); l:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
    l:SetScript("OnEnter", function(self) local b = self.tile; if b then UI.ShowTip(b, self, nil); Land(b, true) end end)
    l:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l:SetScript("OnClick", function(self) local b = self.tile; if b then Land(b, true) end end)
    f.lines[k] = l
    return l
  end
  tabs.popular.refresh = function()
    local cf = plan().cls; local pop = TF.Popular(cf); local c = D.classes[cf]
    for _, l in ipairs(f.lines) do l:Hide() end
    -- the group block: label + Ask on one line, then a row per build that came in (or one quiet line)
    local group = TF.GroupBuilds()
    local inGroup = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0) or false
    local showGroup = inGroup or #group > 0
    f.gLabel:SetShown(showGroup); f.ask:SetShown(showGroup); f.gNone:SetShown(showGroup and #group == 0)
    local top = 0
    f.list.rowY = {}
    if showGroup then
      top = 30
      for k, g in ipairs(group) do
        local r = f.list:Row(k); local gc = D.classes[g.cls]
        local lead, best = 1, -1
        for ti = 1, #g.p.ranks do local v = TF.TreePts(g.p, ti); if v > best then best, lead = v, ti end end
        local pts = {}
        for ti = 1, #g.p.ranks do pts[ti] = TF.TreePts(g.p, ti) end
        local name = g.who .. "'s " .. (gc and gc.name or "") .. " build"
        r.icon:SetTexture(IconFor({ icon = gc and gc.trees[lead].icon or "inv_misc_questionmark" }))
        r.name:SetText(string.format("|cff%s%s|r", gc and gc.color or "ffffff", g.who)); r.tag:SetText("")
        r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 44, -5); r.name:SetPoint("RIGHT", -8, 0)
        r.sub:SetText(string.format("%s %s, %s", gc and gc.name or "", table.concat(pts, " / "), TF.Ago(g.when)))
        local isGhost = TF.trial and TF.trial.name == name
        r.accent:SetAlpha(isGhost and 1 or 0); r.ghost:SetText(isGhost and "Stop" or "Try it")
        Tip(r, name, string.format("Level %d, %s. Try it rings its talents on your trees next to yours, Load makes it your plan, shift-click puts its link in chat.", g.p.level or 60, TF.Ago(g.when)))
        r.onLoad = function() TF.Remember(); TF.SetPlan(TF.Decode(g.code) or g.p); UI.Note("Loaded " .. name .. ".", { { label = "Undo", fn = function() TF.Undo() end } }) end
        r.onGhost = function() if isGhost then TF.TrialBack() else TF.TryBuild(TF.Decode(g.code) or g.p, name) end end
        r:SetScript("OnClick", function() if IsShiftKeyDown and IsShiftKeyDown() then if TF.InsertLink(g.p) then UI.Note("Link put in the chat box.") end end end)
        r.buildCode = g.code
        f.list.rowY[k] = top + (k - 1) * f.list.rowH
      end
      top = top + (#group > 0 and #group * f.list.rowH or 22) + 12
    end
    f.note:ClearAllPoints(); f.note:SetPoint("TOPLEFT", 0, -(top + 4)); f.note:SetPoint("TOPRIGHT", -4, -(top + 4))
    f.spec:ClearAllPoints(); f.spec:SetPoint("TOPLEFT", 0, -(top + 22)); f.spec:SetPoint("TOPRIGHT", -4, -(top + 22))
    local gn = #group
    if not pop then f.note:SetText("No numbers for this class yet."); f.spec:SetText(""); f.list:Fill(gn); return end
    f.note:SetText(string.format("%s builds on talentsforever.com", c.name))
    local parts = {}
    for _, sp in ipairs(pop.spec or {}) do parts[#parts + 1] = string.format("%s %d%%", sp[1], sp[2]) end
    f.spec:SetText((pop.window or ""):gsub(" %d%d%d%d$", "") .. ". " .. table.concat(parts, ", ") .. ".")
    f.list.offset = top + math.ceil(26 + math.max(f.spec:GetStringHeight() or 0, estHeight(f.spec:GetText() or "", PAGE_W - 4, 11)) + 8)
    for kk, b in ipairs(pop.top) do
      local k = gn + kk
      f.list.rowY[k] = f.list.offset + (kk - 1) * f.list.rowH
      local r = f.list:Row(k)
      local lead = 1
      for ti, tree in ipairs(c.trees) do if tree.name == b.lead then lead = ti end end
      local name = string.format("#%d %s", b.rank, b.lead)
      r.icon:SetTexture(IconFor({ icon = c.trees[lead].icon }))
      r.name:SetText(string.format("|cff%s%s|r", c.color, name)); r.tag:SetText(b.seated and "most built" or "")
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 44, -5); r.name:SetPoint("RIGHT", b.seated and -84 or -8, 0)
      r.sub:SetText(string.format("%s / %s / %s", tostring(b.pts[1]), tostring(b.pts[2]), tostring(b.pts[3])))
      local isGhost = TF.trial and TF.trial.name == name
      r.accent:SetAlpha(isGhost and 1 or 0); r.ghost:SetText(isGhost and "Stop" or "Try it")
      Tip(r, string.format("#%d %s, %s / %s / %s", b.rank, b.lead, tostring(b.pts[1]), tostring(b.pts[2]), tostring(b.pts[3])),
        string.format("%sShared %d, saved %d, opened %d times%s. Try it rings its talents on your trees next to yours, Load makes it your plan.", b.seated and string.format("The most built %s build, #%d overall. ", b.lead, b.rank) or "", b.shared or 0, b.saved or 0, b.opened or 0,
          (b.variants or 0) > 0 and string.format(", across %d close builds (every full build within four points of this one)", b.variants + 1) or ""))
      r.onLoad = function() local ok, err, back = TF.LoadCode(b.code); if ok then UI.Note(string.format("Loaded the #%d %s build.", b.rank, b.lead) .. TF.SettledText(back), { { label = "Undo", fn = function() TF.Undo() end } }, back and 12 or nil); if back then UI.SettledCard(back) end else UI.Note(err) end end
      r.onGhost = function() if isGhost then TF.TrialBack() else local p = TF.Decode(b.code); if p then TF.TryBuild(p, name) end end end
      r:SetScript("OnClick", function() if IsShiftKeyDown and IsShiftKeyDown() then local p = TF.Decode(b.code); if p and TF.InsertLink(p) then UI.Note("Link put in the chat box.") end end end)
      r.buildCode = b.code
    end
    local y = f.list.offset + #pop.top * f.list.rowH + 10
    local n = 0
    local nRows = gn + #pop.top
    local function find(name) for ti, tree in ipairs(c.trees) do for i, t in ipairs(tree.talents) do if t.name == name then return ti, i end end end end
    local function header(text)
      n = n + 1; local l = Line(n); l:Show(); l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, -y)
      l.head:SetText(text:upper()); l.head:Show(); l.rule:Show(); l.name:SetText(""); l.pct:SetText(""); l.tile = nil; l:EnableMouse(false); y = y + 22
    end
    local function item(x)
      n = n + 1; local l = Line(n); l:Show(); l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, -y)
      l.head:Hide(); l.rule:Hide(); l.name:SetText(x[2]); l.pct:SetText(x[1] .. "%")
      local ti, i = find(x[2]); l.tile = ti and trees[ti] and trees[ti].tiles[i] or nil; l:EnableMouse(true); y = y + 20
    end
    if pop.most and #pop.most > 0 then header("Almost everyone takes"); for _, x in ipairs(pop.most) do item(x) end; y = y + 8 end
    if pop.least and #pop.least > 0 then header("Almost nobody takes"); for _, x in ipairs(pop.least) do item(x) end end
    f.list:Fill(nRows, y - (f.list.offset + #pop.top * f.list.rowH) + 10)
  end
  TF.On("GROUP_CHANGED", function() if F and F:IsShown() and S().sideTab == "popular" then tabs.popular.refresh() end end)
end

-- Classic: what changed since vanilla, the site's signature
local function BuildClassicTab()
  local f = TabFrame("classic")
  f.marks = Check(f, "Compare to Classic", function() return S().marks end, function(v) S().marks = v end); f.marks:SetPoint("TOPLEFT", 12 - (f.marks.air or 0), -4)
  f.picks = Check(f, "Show pick rates", function() return S().pickRates end, function(v) S().pickRates = v end); f.picks:SetPoint("TOPLEFT", 12 - (f.picks.air or 0), -30)
  Tip(f.marks, "Compare to Classic", "A gold edge is a talent new in Forever, blue changed its numbers or words, purple moved trees or rows. Hover a tile for the Classic text.")
  Tip(f.picks, "Pick rates", "The share of this class's builds on the site with at least one point in the talent.")
  f.legend = Text(f, 12, C.ink2); f.legend:SetPoint("TOPLEFT", 12, -58); f.legend:SetPoint("TOPRIGHT", -28, -58); f.legend:SetWordWrap(true); f.legend:SetJustifyH("LEFT")
  f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"); f.scroll:SetPoint("TOPLEFT", PAD, -98); f.scroll:SetPoint("BOTTOMRIGHT", -28, 10); Slim(f.scroll)
  f.body = CreateFrame("Frame", nil, f.scroll); f.body:SetSize(PAGE_W, 10); f.scroll:SetScrollChild(f.body)
  f.blocks = {}
  local function Block(k)
    local b = f.blocks[k]
    if b then return b end
    b = { sec = Section(f.body, "", 0), text = Text(f.body, 12, C.ink2) }
    b.sec:ClearAllPoints(); b.text:SetWidth(PAGE_W - 4); b.text:SetWordWrap(true); b.text:SetJustifyH("LEFT")
    f.blocks[k] = b
    return b
  end
  tabs.classic.refresh = function()
    f.marks:SetChecked(S().marks); f.picks:SetChecked(S().pickRates)
    local cd = classData(); local n = { new = 0, changed = 0, moved = 0, same = 0 }
    local lines = {}
    for _, tree in ipairs(cd.trees) do
      for _, t in ipairs(tree.talents) do n[t.classic or "new"] = (n[t.classic or "new"] or 0) + 1 end
    end
    f.legend:SetText(string.format("%s against Classic: |cffffd75e%d new|r, |cff58a6ff%d changed|r, |cffb88cff%d moved|r, %d the same.", cd.name, n.new, n.changed, n.moved, n.same))
    for _, b in ipairs(f.blocks) do b.sec:Hide(); b.text:Hide() end
    local y = 0
    for ti, tree in ipairs(cd.trees) do
      local news, gone = {}, {}
      for _, t in ipairs(tree.talents) do if t.classic == "new" then news[#news + 1] = t.name end end
      for _, r in ipairs(tree.removed or {}) do gone[#gone + 1] = r.name end
      if #news > 0 or #gone > 0 then
        local b = Block(ti)
        b.sec:Show(); b.sec:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y); b.sec:SetText(tree.name:upper()); y = y + 20
        if #news > 0 then lines[#lines + 1] = "|cffffd75eNew:|r " .. table.concat(news, ", ") .. "." end
        if #gone > 0 then lines[#lines + 1] = "|cffff4d4dGone from Classic:|r " .. table.concat(gone, ", ") .. "." end
        local body = table.concat(lines, "\n"); lines = {}
        b.text:Show(); b.text:ClearAllPoints(); b.text:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y); b.text:SetText(body)
        local measured = b.text:GetStringHeight() or 0
        local est = estHeight(body, PAGE_W - 4, 12) + (#news > 0 and #gone > 0 and 12 or 0)
        y = y + math.ceil(measured > 0 and measured or est) + 14
      end
    end
    f.body:SetHeight(math.max(10, y + 10))
  end
end

-- Races: every race this class can be, as a row of faces, yours first and lit. The page shows the picked race's
-- racials and the class racials it gets, so a Paladin can read what a Dwarf would give before rolling one.
local function BuildRacialsTab()
  local f = TabFrame("racials")
  f.faces = {}
  for k = 1, 10 do
    local b = CreateFrame("Button", nil, f); b:SetSize(26, 26); b:SetPoint("TOPLEFT", 12 + (k - 1) * 30, -8)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.edge = Edges(b, b, "OVERLAY", 1)
    b:SetHighlightTexture(WHITE); local hl = b:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 0.82, 0, 0.2) end
    b:SetScript("OnClick", function(self) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); f.race = self.race; tabs.racials.refresh() end)
    b:SetScript("OnEnter", function(self)
      TipBegin(self); GameTooltip:SetText(self.race or "", 1, 0.82, 0)
      if self.can == false then GameTooltip:AddLine(string.format("Cannot be a %s. Click for its racials anyway.", classData().name), 0.74, 0.74, 0.74, true)
      else GameTooltip:AddLine(self.mine and "Your race. Click another face for its racials with this class." or "Click for its racials with this class.", 0.9, 0.9, 0.9, true) end
      TipEnd(self)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide(); f.faces[k] = b
  end
  f.raceName = Text(f, 14, C.gold, true); f.raceName:SetPoint("TOPLEFT", 12, -44); f.raceName:SetShadowColor(0, 0, 0, 0.9); f.raceName:SetShadowOffset(1, -1)
  f.raceTag = Text(f, 11, C.muted); f.raceTag:SetPoint("LEFT", f.raceName, "RIGHT", 8, 0)
  f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"); f.scroll:SetPoint("TOPLEFT", PAD, -66); f.scroll:SetPoint("BOTTOMRIGHT", -28, 10); Slim(f.scroll)
  f.body = CreateFrame("Frame", nil, f.scroll); f.body:SetSize(PAGE_W, 10); f.scroll:SetScrollChild(f.body)
  f.items = {}
  local function Item(k)
    local it = f.items[k]
    if it then return it end
    it = CreateFrame("Frame", nil, f.body); it:SetWidth(PAGE_W)
    it.icon = it:CreateTexture(nil, "ARTWORK"); it.icon:SetSize(24, 24); it.icon:SetPoint("TOPLEFT", 0, -2); it.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    it.name = Text(it, 13, C.gold); it.name:SetPoint("TOPLEFT", it.icon, "TOPRIGHT", 8, 0); it.name:SetWidth(PAGE_W - 36); it.name:SetWordWrap(false)
    it.text = Text(it, 12, C.ink2); it.text:SetPoint("TOPLEFT", it.name, "BOTTOMLEFT", 0, -3); it.text:SetWidth(PAGE_W - 36); it.text:SetWordWrap(true); it.text:SetNonSpaceWrap(false); it.text:SetJustifyH("LEFT")
    it.head = Section(it, "", -6); it.head:ClearAllPoints(); it.head:SetPoint("TOPLEFT", 0, -8); it.head:SetWidth(PAGE_W - 4)
    f.items[k] = it
    return it
  end
  tabs.racials.refresh = function()
    local R = D.racials; local cf = plan().cls; local cd = D.classes[cf]
    local myRace = (UnitRace("player")) or ""
    local myFac = (UnitFactionGroup and UnitFactionGroup("player")) or nil
    -- every race, Horde then Alliance, yours first; the ones that cannot be this class stay in the row, dimmed
    local list, mine = {}, nil
    for _, fac in ipairs({ "Horde", "Alliance" }) do
      for _, r in ipairs((R.factions or {})[fac] or {}) do
        local can = r.classes == nil
        for _, c in ipairs(r.classes or {}) do if c == cf then can = true end end
        r.can = can
        list[#list + 1] = r
        local base = r.race:gsub("%s*%(.*$", "")
        if myRace:find(base, 1, true) and (not mine or fac == myFac) then mine = r end
      end
    end
    if mine then for k, r in ipairs(list) do if r == mine then table.remove(list, k); table.insert(list, 1, r) end end end
    local sel
    for _, r in ipairs(list) do if r.race == f.race then sel = r end end
    sel = sel or mine or list[1]
    for k, b in ipairs(f.faces) do
      local r = list[k]
      if r then
        b:Show(); b.race = r.race; b.mine = r == mine
        local key = (r.race:lower():gsub("%s*%(.*$", "")):gsub("%s", "")   -- "Night Elf" -> nightelf, "Skyborne (High Order)" -> skyborne
        b.icon:SetTexCoord(0, 1, 0, 1)
        if not Atlas(b.icon, "raceicon-" .. key .. "-male") then b.icon:SetTexture("Interface\\Icons\\achievement_character_" .. key .. "_male"); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        b.can = r.can
        b.icon:SetDesaturated(r ~= sel); b.icon:SetAlpha(r == sel and 1 or (r.can and 0.8 or 0.35))
        if r == sel then b.edge:SetColor(1, 0.82, 0, 1) elseif r == mine then b.edge:SetColor(0.78, 0.61, 0.10, 0.8) else b.edge:SetColor(0.45, 0.38, 0.22, r.can and 0.8 or 0.35) end
      else b:Hide(); b.race = nil end
    end
    f.raceName:SetText(sel and sel.race or "Races")
    f.raceTag:SetText(sel and (sel == mine and "YOUR RACE" or (sel.can == false and ("NOT A " .. cd.name:upper() .. " RACE") or (mine and ("YOU ARE " .. mine.race:gsub("%s*%(.*$", ""):upper()) or ""))) or "")
    local entries = {}
    local function add(head) entries[#entries + 1] = { head = head } end
    local function ab(a) entries[#entries + 1] = { name = a.name, text = a.text, icon = a.icon } end
    if sel then
      for _, a in ipairs(sel.abilities or {}) do ab(a) end
      local cr = R.classRacials and R.classRacials[cf]
      local lst = cr and cr.races and cr.races[sel.race]
      if not lst and cr and cr.races then for rn, l in pairs(cr.races) do if sel.race:find(rn, 1, true) then lst = l end end end
      if lst and #lst > 0 then add(string.format("%s %s ONLY", sel.race:gsub("%s*%(.*$", ""):upper(), cd.name:upper())); for _, a in ipairs(lst) do ab(a) end end
    else
      entries[#entries + 1] = { name = myRace, text = "No racial notes for this race on the site yet.", icon = "inv_misc_questionmark" }
    end
    for _, it in ipairs(f.items) do it:Hide() end
    local y = 0
    for k, e in ipairs(entries) do
      local it = Item(k); it:Show(); it:ClearAllPoints(); it:SetPoint("TOPLEFT", 0, -y)
      if e.head then
        it.head:SetText(e.head); it.head:Show(); it.icon:Hide(); it.name:SetText(""); it.text:SetText(""); it:SetHeight(30); y = y + 30
      else
        it.head:Hide(); it.icon:Show(); it.icon:SetTexture(IconFor({ icon = e.icon })); it.name:SetText(e.name); it.text:SetText(e.text or "")
        -- measured once the text has wrapped; a length estimate keeps rows apart when the measure comes back early
        local est = estHeight(e.text, PAGE_W - 36, 12)
        local measured = it.text:GetStringHeight() or 0
        local h = math.ceil(20 + (measured > 0 and measured or est) + 12)
        it:SetHeight(h); y = y + h
      end
    end
    f.body:SetHeight(math.max(10, y + 10))
  end
end

-- Coach: what a careful friend would say about the plan
local function BuildCoachTab()
  local f = TabFrame("coach")
  f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"); f.scroll:SetPoint("TOPLEFT", PAD, -6); f.scroll:SetPoint("BOTTOMRIGHT", -28, 10); Slim(f.scroll)
  f.body = CreateFrame("Frame", nil, f.scroll); f.body:SetSize(PAGE_W, 10); f.scroll:SetScrollChild(f.body)
  f.items = {}
  local KIND = { good = C.green, note = C.gold, warn = C.red }
  local function Item(k)
    local it = f.items[k]
    if it then return it end
    it = CreateFrame("Frame", nil, f.body); it:SetWidth(PAGE_W)
    it.bar = Solid(it, "BACKGROUND", C.gold, 0.9); it.bar:SetPoint("TOPLEFT", 0, -2); it.bar:SetPoint("BOTTOMLEFT", 0, 2); it.bar:SetWidth(3)
    it.icon = it:CreateTexture(nil, "ARTWORK"); it.icon:SetSize(24, 24); it.icon:SetPoint("TOPLEFT", 12, -6); it.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    it.iconEdge = Edges(it, it.icon, "OVERLAY", 1); it.iconEdge:SetColor(0, 0, 0, 0.9)
    -- a headline in the note's colour, the reasons under it in plain words
    it.head = Text(it, 13, C.gold); it.head:SetPoint("TOPLEFT", 44, -6); it.head:SetWidth(PAGE_W - 48); it.head:SetWordWrap(false); it.head:SetJustifyH("LEFT")
    it.text = Text(it, 12, C.ink2); it.text:SetPoint("TOPLEFT", 44, -24); it.text:SetWidth(PAGE_W - 48); it.text:SetWordWrap(true); it.text:SetJustifyH("LEFT")
    f.items[k] = it
    return it
  end
  -- the trainer's spells, one row each, with a Skip for the ones this character never wants (What's Training's ignore)
  local TROW_H = 26
  f.trows = {}
  f.thead = Section(f.body, "", 0); f.thead:Hide()
  f.tcost = Text(f.body, 11, C.gold); f.tcost:Hide()   -- the money, on its own line: the header is caps and has no room
  local function TRow(k)
    local r = f.trows[k]
    if r then return r end
    r = CreateFrame("Button", nil, f.body); r:SetSize(PAGE_W, TROW_H)
    r.bg = Solid(r, "BACKGROUND", C.raised, 0.35); r.bg:SetPoint("TOPLEFT", 0, -1); r.bg:SetPoint("BOTTOMRIGHT", 0, 1)
    r:SetHighlightTexture(WHITE); r:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 12, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = Text(r, 13, C.ink); r.name:SetPoint("LEFT", 40, 0); r.name:SetPoint("RIGHT", -64, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.cost = Text(r, 11, C.gold); r.cost:SetPoint("RIGHT", -10, 0); r.cost:SetJustifyH("RIGHT")
    r.btn = Button(r, "Skip", "auto", 20, function() if r.spell then TF.SkipSpell(r.spell.name, r.spell.rank, not r.skipped); tabs.coach.refresh() end end)
    r.btn.minW = 56; r.btn:Fit(); r.btn:SetPoint("RIGHT", -8, 0)
    -- Skip shows when the row is under the mouse (a page of red buttons is noise); Back stays, a skipped row is rare
    -- leaving the row hides Skip; stepping onto the button fires the row's leave first and then the button's enter, which shows it again
    local function leave() if not r.skipped then r.btn:Hide(); r.cost:SetShown(r.spell and r.spell.cost and true or false) end end
    r.btn:HookScript("OnEnter", function() r.btn:Show(); r.cost:Hide() end); r.btn:HookScript("OnLeave", leave)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(_, btn) if btn == "RightButton" and r.spell then TF.SkipSpell(r.spell.name, r.spell.rank, not r.skipped); tabs.coach.refresh() end end)
    r:SetScript("OnEnter", function()
      local s = r.spell; if not s then return end
      r.btn:Show(); r.cost:Hide()
      TipBegin(r)
      local shown = false
      if s.id and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, s.id) end
      if not shown then GameTooltip:SetText(s.name, 1, 0.82, 0) end
      local co = TF.Coef(s.id); if co then GameTooltip:AddLine("Scales with " .. co .. ".", 0.62, 0.62, 0.62, true) end
      GameTooltip:AddLine(string.format("The trainer sells this from level %d%s.%s", s.level, s.cost and (" for " .. TF.Money(s.cost)) or "", s.portal and " A portal trainer, not the class trainer." or ""), 0.74, 0.74, 0.74, true)
      GameTooltip:AddLine(r.skipped and "Skipped: it stays out of the reminders. Back, or a right click, puts it back." or "Skip, or a right click, keeps it out of the reminders for this character.", 0.54, 0.54, 0.54, true)
      TipEnd(r)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide(); leave() end)
    f.trows[k] = r
    return r
  end
  tabs.coach.refresh = function()
    local notes = TF.Coach(plan())
    for _, it in ipairs(f.items) do it:Hide() end
    for _, r in ipairs(f.trows) do r:Hide() end
    f.thead:Hide(); f.tcost:Hide()
    local y = 0
    local owed, skipped
    if isOwnClass() then
      owed, skipped = TF.OwedSpells()
      if owed and #owed == 0 and #skipped == 0 then table.insert(notes, 1, { kind = "good", head = "Spellbook up to date", text = "It has everything the trainer sells at your level." }) end
    end
    -- the reading of the plan: one card per thing worth saying, headline first
    for k, n in ipairs(notes) do
      local it = Item(k); it:Show(); it:ClearAllPoints(); it:SetPoint("TOPLEFT", 0, -y)
      local col = KIND[n.kind] or C.gold
      it.bar:SetVertexColor(col[1], col[2], col[3], 0.9)
      local x0 = n.icon and 44 or 12
      if n.icon then it.icon:Show(); it.icon:SetTexture(IconFor({ icon = n.icon })); it.iconEdge:SetColor(0, 0, 0, 0.9) else it.icon:Hide(); it.iconEdge:SetColor(0, 0, 0, 0) end
      it.head:ClearAllPoints(); it.head:SetPoint("TOPLEFT", x0, -6); it.head:SetWidth(PAGE_W - x0 - 4); it.head:SetText(n.head or ""); it.head:SetTextColor(rgb(col))
      it.text:ClearAllPoints(); it.text:SetPoint("TOPLEFT", x0, -24); it.text:SetWidth(PAGE_W - x0 - 4); it.text:SetText(n.text or "")
      -- the estimate counts the words a reader sees, line by line, not the colour codes
      local plain = (n.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""); plain = plain:gsub("|r", "")
      local est = 0
      for line in (plain .. "\n"):gmatch("(.-)\n") do est = est + estHeight(line, PAGE_W - x0 - 4, 12) end
      local h = math.ceil(24 + math.max(it.text:GetStringHeight() or 0, est, n.icon and 12 or 0) + 10)
      it:SetHeight(h); y = y + h + 6
    end
    -- the trainer's list, under the cards: what the character could learn now, with Skip for the ones it never wants
    if owed and (#owed > 0 or #skipped > 0) then
      y = y + 6
      f.thead:Show(); f.thead:ClearAllPoints(); f.thead:SetPoint("TOPLEFT", 12, -y)
      f.thead:SetText(#owed > 0 and string.format("AT THE TRAINER, %d YOU CAN LEARN NOW", #owed) or "AT THE TRAINER, NOTHING NEW")
      y = y + 18
      local ct = #owed > 0 and TF.OwedCostText(owed) or nil
      if ct then f.tcost:Show(); f.tcost:ClearAllPoints(); f.tcost:SetPoint("TOPLEFT", 12, -y); f.tcost:SetWidth(PAGE_W - 24); f.tcost:SetWordWrap(true); f.tcost:SetJustifyH("LEFT"); f.tcost:SetText(ct .. " to learn them."); y = y + math.ceil(math.max(f.tcost:GetStringHeight() or 0, estHeight(ct .. " to learn them.", PAGE_W - 24, 11))) + 6 end
      local k = 0
      local function row(s, isSkipped)
        k = k + 1; local r = TRow(k); r:Show(); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
        r.icon:SetAlpha(isSkipped and 0.4 or 1); r.name:SetAlpha(isSkipped and 0.5 or 1); r.icon:SetDesaturated(isSkipped)
        r.icon:SetTexture(IconFor({ icon = s.icon }))
        r.name:SetText(s.ranks > 1 and string.format("%s (rank %d)", s.name, s.rank) or s.name)
        r.btn:SetText(isSkipped and "Back" or "Skip"); r.btn:Fit(); r.btn:SetShown(isSkipped)
        r.spell = s; r.skipped = isSkipped
        r.cost:SetText(s.cost and TF.Money(s.cost) or ""); r.cost:SetShown(not isSkipped and s.cost and true or false)
        y = y + TROW_H
      end
      for _, s in ipairs(owed) do row(s, false) end
      for _, s in ipairs(skipped) do row(s, true) end
    end
    f.body:SetHeight(math.max(10, y + 10))
  end
end

-- Settings: a page of the side panel, opened by the gear. No card over the trees.
local function BuildSettingsTab()
  local page = TabFrame("settings")
  page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate"); page.scroll:SetPoint("TOPLEFT", 0, 0); page.scroll:SetPoint("BOTTOMRIGHT", 0, 6); Slim(page.scroll)
  local f = CreateFrame("Frame", nil, page.scroll); f:SetSize(PAGE_W + 12, 760); page.scroll:SetScrollChild(f)
  f.title = Text(f, 15, C.gold, true); f.title:SetPoint("TOPLEFT", 12, -8); f.title:SetText("Settings"); f.title:SetShadowColor(0, 0, 0, 0.9); f.title:SetShadowOffset(1, -1)
  local y = -36
  f.boxes = {}
  -- a switch: the box, a small picture of what it is about, the words; one plain sentence on hover
  local function row(label, icon, get, set, tip)
    local cb = Check(f, label, get, set); cb:SetPoint("TOPLEFT", PAD - (cb.air or 0), y); y = y - 26
    cb.icon = f:CreateTexture(nil, "ARTWORK"); cb.icon:SetSize(16, 16); cb.icon:SetPoint("LEFT", cb, "RIGHT", 2, 1); cb.icon:SetTexture("Interface\\Icons\\" .. icon); cb.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cb.iconEdge = Edges(f, cb.icon, "OVERLAY", 1); cb.iconEdge:SetColor(0, 0, 0, 0.9)
    cb.label:ClearAllPoints(); cb.label:SetPoint("LEFT", cb.icon, "RIGHT", 6, 0)
    if cb.SetHitRectInsets then cb:SetHitRectInsets(0, -((cb.label:GetStringWidth() or 60) + 30), 0, 0) end
    if tip then Tip(cb, label, tip) end
    f.boxes[#f.boxes + 1] = cb
    return cb
  end
  local function head(text) local s = Section(f, text, y); y = y - 22; return s end
  head("REMINDERS")
  row("Level-up reminders", "inv_misc_bell_01", function() return S().levelUpNudge end, function(v) S().levelUpNudge = v end, "When you level up, a small card says which talent is next and offers to place it.")
  row("Trainer reminders", "inv_misc_book_07", function() return S().trainerAlerts end, function(v) S().trainerAlerts = v; S().trainerAlertsSet = true end, "A card when you level, or walk into a city, with spells you could learn. Once per level, per place. Off by itself if What's Training is installed.")
  row("Trainer cards only for what you can afford", "inv_misc_coin_01", function() return S().purseOnly == true end, function(v) S().purseOnly = v or nil end, "The card counts only the spells your gold covers, with one line for the rest, and stays away while none is affordable; it comes when the gold does. The card itself offers this the first time it lists something you cannot pay for. Prices come from the trainer window once you have opened one on this character.")
  row("Game-style class list", "inv_misc_note_01", function() return not S().plainClassList end, function(v) S().plainClassList = (not v) or nil; UI.Note("The class picker changes on the next /reload.") end, "The class picker at the top is the game's own dropdown. Off uses a plain button instead. It switches itself off if the game ever blocks the dropdown, and while a gamepad is on.")
  head("OTHER PLAYERS")
  row("Show other people's builds", "inv_misc_groupneedmore", function() return S().othersBuilds ~= false end, function(v) S().othersBuilds = v; UI.LayoutTabs() end, "Off hides the Popular page and the cards other players send. Links in chat still work.")
  row("Answer build requests", "inv_letter_15", function() return S().answerParty ~= false end, function(v) S().answerParty = v end, "Someone in your group can ask everyone for their build. On, yours goes to them as a link. Off, nothing goes.")
  head("HANDS-FREE")
  row("Follow the top build", "ability_hunter_pathfinding", function() return S().starter end, function(v) UI.SetStarter(v) end, "The #1 build for your class becomes your plan. Each level, a card asks before the next point goes in. Change a point by hand and it stops.")
  row("Place points for me, no asking", "achievement_level_10", function() return S().autoApply end, function(v) S().autoApply = v end, "Each time you level, the plan's next point is placed without a card. Never your first point in a tree: that one always asks. Off unless you want it.")
  head("THE WINDOW")
  row("Show plan on the game's talents", "inv_misc_map02", function() return S().overlay end, function(v) S().overlay = v; UI.RefreshOverlay() end, "Your plan's numbers and a ring on your next point, drawn on the game's own talent window.")
  row("Leveling rail", "ability_rogue_sprint", function() return UI.RailOn() end, function(v) S().rail = v; UI.LayoutFoot(); UI.Refresh() end, "The bar under the trees, one mark per level. Off, the window is shorter. At 60 it is off by itself.")
  row("Sounds", "inv_misc_horn_01", function() return S().sounds ~= false end, function(v) S().sounds = v end, "Small clicks and chimes.")
  row("Minimap button", "inv_misc_map_01", function() return not S().minimap.hide end, function(v) S().minimap.hide = not v; UI.SetMinimapShown(v) end, "The book on the minimap. Left click opens the planner, right click the popular builds.")
  row("Book tab on the character pane", "inv_misc_book_09", function() return S().charTab ~= false end, function(v) S().charTab = v; if TalentsForeverBookCharacterTab then TalentsForeverBookCharacterTab:SetShown(v) end end, "The book among the tabs on your character pane. Same as /tf.")
  row("Train all at the trainer", "inv_misc_coin_02", function() return S().trainAll ~= false end, function(v) S().trainAll = v; if not v then local b = _G.TalentsForeverBookTrainAll; if b then b:Hide() end end end, "The Train all button on the trainer window, with what it would cost. Off, the trainer window is the game's own; /talents trainall still buys the lot.")
  row("The talents key opens this", "inv_misc_key_03", function() return S().talentsKey end, function(v) S().talentsKey = v; UI.ApplyTalentsKey(true) end, "Whatever key opens the game's talents (N, unless you changed it) opens Talents Forever instead. Your key bindings stay as they are; off gives the game's window back.")
  row("Open this instead of the game's talents", "inv_misc_book_11", function() return S().replaceTalents end, function(v) S().replaceTalents = v; UI.Note(v and "The game's talent tab opens Talents Forever now. Hold Shift while opening it for the game's window." or "The game's talent window is its own again.", nil, 8) end, "Open the game's talents any way at all (the key, the micro bar, the spellbook's tab) and it closes again with Talents Forever in its place. Hold Shift while opening it to get the game's window that once. Never during a fight.")
  y = y - 8
  f.sizeLabel = Text(f, 12, C.gold); f.sizeLabel:SetPoint("TOPLEFT", PAD, y - 6); f.sizeLabel:SetText("Window size")
  f.smaller = Stepper(f, false, function() S().scaleSet = true; UI.SetScale((F:GetScale() or 1) - 0.1); tabs.settings.refresh() end); f.smaller:SetPoint("TOPLEFT", PAD + 108, y)
  f.sizeValue = Text(f, 13, C.gold); f.sizeValue:SetPoint("LEFT", f.smaller, "RIGHT", 6, 0); f.sizeValue:SetWidth(46); f.sizeValue:SetJustifyH("CENTER")
  f.bigger = Stepper(f, true, function() S().scaleSet = true; UI.SetScale((F:GetScale() or 1) + 0.1); tabs.settings.refresh() end); f.bigger:SetPoint("LEFT", f.sizeValue, "RIGHT", 6, 0)
  -- the slider: 50 to 160 percent, one percent at a time; drag the knob or click the bar
  f.slider = UI.Slider(f, PAGE_W - 8, 50, 160, function() return math.floor((F:GetScale() or 1) * 100 + 0.5) end, function(v) S().scaleSet = true; UI.SetScale(v / 100); f.sizeValue:SetText(v .. "%") end)
  f.slider:SetPoint("TOPLEFT", PAD, y - 34)
  Tip(f.slider, "Window size", "Drag the knob, or click anywhere on the bar. One percent at a time. Ctrl and the wheel on the window do the same.")
  f.center = Button(f, "Center the window", "auto", 24, function() UI.Centre(); UI.Note("Window centered.") end); f.center:SetPoint("TOPLEFT", PAD, y - 60)
  -- the cards (level-up, trainer, a build sent) can be dragged anywhere; this puts them back
  f.card = Button(f, "Reminder card back to the middle", "auto", 24, function() UI.ResetCard(); UI.Note("The cards show above the bottom of the screen again. Drag one to put them somewhere else.", nil, 8) end); f.card:SetPoint("TOPLEFT", PAD, y - 92)
  Tip(f.card, "Where the cards show", "The level-up, trainer and build cards can be dragged anywhere on the screen; they stay where you drop them. This puts them back above the bottom, in the middle.")
  f.hint = Text(f, 12, C.muted); f.hint:SetPoint("TOPLEFT", PAD, y - 124); f.hint:SetPoint("TOPRIGHT", -28, y - 124); f.hint:SetWordWrap(true); f.hint:SetJustifyH("LEFT")
  f.hint:SetText("Ctrl + wheel resizes, so do the bottom corners. Escape closes.")
  Tip(f.center, "Back to the middle", "Puts the window in the middle of the screen. Drag the title to move it, the corner to resize it.")
  f.quiet = Text(f, 12, C.muted); f.quiet:SetPoint("TOPLEFT", PAD, y - 184); f.quiet:SetPoint("TOPRIGHT", -28, y - 184); f.quiet:SetWordWrap(true); f.quiet:SetJustifyH("LEFT")
  f.quiet:SetText("Never posts in chat on its own. A link goes out only when you send it.")
  -- the pages: switch off the ones you never open and their tabs close up
  f.pagesLabel = Text(f, 10, C.muted); f.pagesLabel:SetPoint("TOPLEFT", PAD, y - 222); f.pagesLabel:SetText("PAGES")
  local py = y - 238
  for _, key in ipairs({ "coach", "builds", "popular", "classic", "racials" }) do
    local cb = Check(f, TAB_LABEL[key], function() return not UI.HiddenTab(key) end, function(v) S().hiddenTabs = S().hiddenTabs or {}; S().hiddenTabs[key] = (not v) or nil; UI.LayoutTabs() end)
    cb:SetPoint("TOPLEFT", PAD - (cb.air or 0), py); py = py - 26; f.boxes[#f.boxes + 1] = cb
    if key == "popular" then Tip(cb, "Popular", "Also goes away when Show other people's builds is off.") end
  end
  f:SetHeight(math.abs(py) + 24)
  f.ideas = Button(f, "Feedback", "auto", 20, function() UI.SetTab("feedback") end); f.ideas:SetPoint("TOPLEFT", PAD, y - 156)
  Tip(f.ideas, "Say what would help", "A bug, a wish, a talent that reads wrong: it goes to the inbox of the person who builds this.")
  tabs.settings.refresh = function()
    for _, cb in ipairs(f.boxes) do cb:SetChecked(cb.get()) end
    if f.slider then f.slider:Sync() end
    f.sizeValue:SetText(string.format("%d%%", math.floor(((F and F:GetScale()) or 1) * 100 + 0.5)))
  end
end

-- Feedback: a note to the person who builds this. The game gives an addon no way to send anything, so Send turns the
-- note into a link that lands in the site's ideas inbox when pasted in a browser: one Ctrl+C, one paste. One screen.
-- Under the box, the replies (0.32): every note that turned into something, in the words it came in, with what happened
-- to it. A note sent from this account has its answer under "your note": the link carries a tag the addon made up, the
-- reply comes back with the same tag, and nothing about who sent it is anywhere.
-- one table, not five locals: the main chunk of this file is at Lua's limit of 200
local REPLY = { WORD = { done = "Done", way = "On the way", thinking = "Thinking about it", ["not"] = "Not this one" },
                COLOR = { done = C.gold, way = C.green, thinking = C.blue, ["not"] = C.red },
                MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" } }
function REPLY.date(s)
  local y, m, d = tostring(s or ""):match("^(%d+)%-(%d+)%-(%d+)")
  if not y then return tostring(s or "") end
  return string.format("%d %s", tonumber(d), REPLY.MONTHS[tonumber(m)] or m)
end
-- who asked, without saying who: "u/Konis, Warrior 9, 24 Sep" or "a Warlock, level 3, 23 Sep" or "someone on the site, 23 Sep"
function REPLY.by(r)
  local who = r.who and r.who ~= "" and ((r.who:find("^u/") and r.who) or ("u/" .. r.who)) or nil
  local when = REPLY.date(r.when)
  if who and r.cls then return string.format("%s, %s %d, %s", who, r.cls, r.level or 0, when) end
  if who then return string.format("%s, %s, %s", who, r.from == "reddit" and "on Reddit" or "on the site", when) end
  if r.cls then return string.format("a %s, level %d, %s", r.cls, r.level or 0, when) end
  return string.format("someone %s, %s", r.from == "addon" and "from inside the addon" or r.from == "reddit" and "on Reddit" or "on the site", when)
end
local function BuildFeedbackTab()
  local f = TabFrame("feedback")
  f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate"); f.scroll:SetPoint("TOPLEFT", 0, 0); f.scroll:SetPoint("BOTTOMRIGHT", 0, 6); Slim(f.scroll)
  local body = CreateFrame("Frame", nil, f.scroll); body:SetSize(PAGE_W + 12, 420); f.scroll:SetScrollChild(body); f.body = body
  f.title = Text(body, 15, C.gold, true); f.title:SetPoint("TOPLEFT", 12, -8); f.title:SetText("Say what would help"); f.title:SetShadowColor(0, 0, 0, 0.9); f.title:SetShadowOffset(1, -1)
  f.sub = Text(body, 12, C.ink2); f.sub:SetPoint("TOPLEFT", 12, -30); f.sub:SetPoint("TOPRIGHT", -28, -30); f.sub:SetWordWrap(true); f.sub:SetJustifyH("LEFT")
  f.sub:SetText("A bug, a wish, a talent that reads wrong. It goes to the person who builds this.")
  local well = CreateFrame("Frame", nil, body); well:SetPoint("TOPLEFT", 12, -56); well:SetSize(PAGE_W, 96); f.well = well
  well.bg = Solid(well, "BACKGROUND", C.bg, 0.92); well.bg:SetAllPoints(); well.edge = Edges(well, well, "BORDER", 0); well.edge:SetColor(0.78, 0.61, 0.10, 0.45)
  local sc = CreateFrame("ScrollFrame", nil, well); sc:SetPoint("TOPLEFT", 8, -6); sc:SetPoint("BOTTOMRIGHT", -8, 6)
  local e = CreateFrame("EditBox", nil, sc); e:SetMultiLine(true); e:SetMaxLetters(460); e:SetAutoFocus(false); e:SetFont(BODY, 12, ""); e:SetTextColor(0.91, 0.91, 0.91)
  e:SetWidth(PAGE_W - 16); e:SetHeight(84); sc:SetScrollChild(e); f.box = e
  f.hint = Text(well, 12, C.muted); f.hint:SetPoint("TOPLEFT", 10, -8); f.hint:SetText("Say it how you would say it to a friend.")
  f.left = Text(body, 11, C.muted); f.left:SetPoint("TOPRIGHT", -28, -156); f.left:SetJustifyH("RIGHT"); f.left:SetText("460 left")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnTextChanged", function(self)
    local n = #(self:GetText() or "")
    f.hint:SetShown(n == 0); f.left:SetText(string.format("%d left", 460 - n)); f.send:SetEnabled(#((self:GetText() or ""):gsub("%s", "")) >= 3)
  end)
  e:SetScript("OnEditFocusGained", function() well.edge:SetColor(1, 0.82, 0, 0.95) end)
  e:SetScript("OnEditFocusLost", function() well.edge:SetColor(0.78, 0.61, 0.10, 0.45) end)
  well:EnableMouse(true); well:SetScript("OnMouseDown", function() e:SetFocus() end)
  f.who = EditBox(body, PAGE_W, 24); f.who:SetPoint("TOPLEFT", 12, -172); f.who.hint:SetText("Reddit name, if you want a reply")
  f.send = Button(body, "Send", "auto", 24, function()
    f.url = TF.FeedbackURL(e:GetText(), f.who:GetText()); e:ClearFocus(); f.who:ClearFocus(); tabs.feedback.refresh()
    UI.Note("Link ready and selected: Ctrl+C, then paste it in a browser.", nil, 8)
  end, true); f.send:SetPoint("TOPLEFT", 12, -206); f.send:SetEnabled(false)
  Tip(f.send, "Send", "Makes a link out of the note and selects it. Ctrl+C, paste it in any browser, and it is delivered.")
  -- the link, right under the button, already selected
  f.linkSec = Section(body, "YOUR NOTE, AS A LINK", -244); f.linkSec:Hide()
  f.link = EditBox(body, PAGE_W - 72, 24); f.link:SetPoint("TOPLEFT", 12, -262); f.link.selectAll = true; f.link.hint:Hide(); f.link:Hide()
  f.copy = Button(body, "Select", 64, 24, function(self) f.link:SetFocus(); f.link:HighlightText(); UI.CopyCue(self); UI.Note("Link selected. Now press Ctrl+C, then paste it in any browser.", nil, 8) end); f.copy:SetPoint("LEFT", f.link, "RIGHT", 8, 0); f.copy:Hide()
  Tip(f.copy, "Select the link", "Selects the whole link so Ctrl+C takes it. No addon can copy to the clipboard for you; the game does not allow it.")
  -- the one thing to do, in the game's epic purple
  f.how = Text(body, 12, C.purple); f.how:SetPoint("TOPLEFT", 12, -294); f.how:SetPoint("TOPRIGHT", -28, -294); f.how:SetWordWrap(true); f.how:SetJustifyH("LEFT"); f.how:Hide()
  f.how:SetText("To send it: Select, then Ctrl+C, then paste the link in any browser. An addon cannot copy for you.")
  f.link:SetScript("OnTextChanged", function(self) if self:GetText() ~= (f.url or "") then self:SetText(f.url or ""); self:HighlightText() end end)
  f.link:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  f.cap = Text(body, 12, C.ink2); f.cap:SetPoint("TOPLEFT", 12, -336); f.cap:SetPoint("TOPRIGHT", -28, -336); f.cap:SetWordWrap(true); f.cap:SetJustifyH("LEFT"); f.cap:Hide()
  f.cap:SetText("The page answers Got it. Nothing leaves the game by itself, and your character's name is not in it. The link carries a six-letter tag the addon made up, so a reply can show up here, under your note.")
  -- the replies: what people asked for and what happened to it, yours first
  f.repSec = Section(body, "WHAT PEOPLE ASKED FOR", -400); f.repSec:Hide()
  f.repNote = Text(body, 12, C.ink2); f.repNote:SetPoint("TOPLEFT", 12, -422); f.repNote:SetPoint("TOPRIGHT", -28, -422); f.repNote:SetWordWrap(true); f.repNote:SetJustifyH("LEFT"); f.repNote:Hide()
  f.reps = {}
  local function Rep(k)
    local r = f.reps[k]; if r then return r end
    r = CreateFrame("Frame", nil, body); r:SetSize(PAGE_W, 60)
    r.bg = Solid(r, "BACKGROUND", C.panel, 0.55); r.bg:SetAllPoints()
    r.edge = Edges(r, r, "BORDER", 0); r.edge:SetColor(0.78, 0.61, 0.10, 0.25)
    r.who = Text(r, 11, C.muted); r.who:SetPoint("TOPLEFT", 10, -8); r.who:SetPoint("TOPRIGHT", -10, -8); r.who:SetJustifyH("LEFT"); r.who:SetWordWrap(false)
    r.text = Text(r, 12, C.ink); r.text:SetPoint("TOPLEFT", 10, -24); r.text:SetPoint("TOPRIGHT", -10, -24); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(true)
    r.status = Text(r, 11, C.gold); r.status:SetJustifyH("LEFT"); r.status:SetWordWrap(false)
    r.reply = Text(r, 12, C.ink2); r.reply:SetJustifyH("LEFT"); r.reply:SetWordWrap(true)
    f.reps[k] = r; return r
  end
  tabs.feedback.refresh = function()
    local sent = f.url and true or false
    f.linkSec:SetShown(sent); f.link:SetShown(sent); f.copy:SetShown(sent); f.how:SetShown(sent); f.cap:SetShown(sent)
    if sent then
      if f.link:GetText() ~= f.url then f.link:SetText(f.url) end
      f.link:SetCursorPosition(0); f.link:SetFocus(); f.link:HighlightText()
    end
    for _, r in ipairs(f.reps) do r:Hide() end
    -- the replies start under the Send button, or under the caption when a link is showing (the caption wraps to a few lines)
    local top = sent and (336 + math.ceil(math.max(f.cap:GetStringHeight() or 0, estHeight(f.cap:GetText() or "", PAGE_W - 40, 12))) + 18) or 244
    local list, R = TF.Replies()
    if not list or #list == 0 then f.repSec:Hide(); f.repNote:Hide(); body:SetHeight(top + 10); return end
    local ordered = {}
    for _, r in ipairs(list) do if r.mine then ordered[#ordered + 1] = r end end
    for _, r in ipairs(list) do if not r.mine then ordered[#ordered + 1] = r end end
    local y = top
    f.repSec:ClearAllPoints(); f.repSec:SetPoint("TOPLEFT", 12, -y); f.repSec:SetText(ordered[1].mine and "YOUR NOTE, AND WHAT OTHERS ASKED FOR" or "WHAT PEOPLE ASKED FOR"); f.repSec:Show(); y = y + 22
    local note = "Every note that turned into something, in the words it came in."
    if R.asOf then note = note .. " As of " .. REPLY.date(R.asOf) .. "." end
    if (R.thanks or 0) > 0 then note = note .. string.format(" And %d of you just said thanks. Noted.", R.thanks) end
    f.repNote:ClearAllPoints(); f.repNote:SetPoint("TOPLEFT", 12, -y); f.repNote:SetPoint("TOPRIGHT", -28, -y); f.repNote:SetText(note); f.repNote:Show()
    y = y + math.ceil(math.max(f.repNote:GetStringHeight() or 0, estHeight(note, PAGE_W - 24, 12))) + 10
    for k, r in ipairs(ordered) do
      local row = Rep(k); row:Show(); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 12, -y)
      row.who:SetText(r.mine and ("Your note. " .. REPLY.by(r)) or REPLY.by(r)); row.who:SetTextColor(rgb(r.mine and C.gold or C.muted))
      row.text:SetText(r.text or "")
      local th = math.ceil(math.max(row.text:GetStringHeight() or 0, estHeight(r.text or "", PAGE_W - 20, 12)))
      local sc = REPLY.COLOR[r.status] or C.muted
      row.status:ClearAllPoints(); row.status:SetPoint("TOPLEFT", 10, -(24 + th + 8)); row.status:SetText(REPLY.WORD[r.status] or r.status or ""); row.status:SetTextColor(rgb(sc))
      row.reply:ClearAllPoints(); row.reply:SetPoint("TOPLEFT", 10, -(24 + th + 24)); row.reply:SetPoint("TOPRIGHT", -10, -(24 + th + 24)); row.reply:SetText(r.reply or "")
      local rh = math.ceil(math.max(row.reply:GetStringHeight() or 0, estHeight(r.reply or "", PAGE_W - 20, 12)))
      local h = 24 + th + 24 + rh + 10
      row:SetHeight(h)
      row.edge:SetColor(0.78, 0.61, 0.10, r.mine and 0.9 or 0.25)
      if r.mine then row.bg:SetVertexColor(0.16, 0.12, 0.03, 0.85) else row.bg:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 0.55) end
      y = y + h + 8
    end
    body:SetHeight(y + 16)
  end
end

-- A tab. The game's own tab art: the dark tab, and the lit one for the page that is open. The art is drawn for tabs that
-- hang under a frame; upside down with its top quarter left off it stands on one, which is how the game's own top tabs do
-- it. Only the outer part of each end piece is used and the middle tiles, so a tab can be as narrow as its word needs.
local function MakeTab(parent, label, onClick, isOpen)
  local b = CreateFrame("Button", nil, parent)
  b.text = b:CreateFontString(nil, "OVERLAY"); FontObject(b.text, GameFontNormalSmall, 10); b.text:SetJustifyH("CENTER"); b.text:SetText(label)
  b:SetSize(math.max(44, math.ceil(((b.text:GetStringWidth() or 30) + 20) / 2) * 2), 27)   -- the game pads a tab's word by 20 too
  if not OWN_LOOK and AtlasOK("uiframe-tab-left") and AtlasOK("uiframe-activetab-left") then
    b.native = true
    local function trio(prefix, h, layer, add)
      local L = b:CreateTexture(nil, layer); L:SetAtlas(prefix .. "-left"); L:SetTexCoord(0, 14 / 35, 1, 0.25); L:SetSize(14, h); L:SetPoint("BOTTOMLEFT", -3, 0)
      local R = b:CreateTexture(nil, layer); R:SetAtlas(prefix .. "-right"); R:SetTexCoord(19 / 37, 1, 1, 0.25); R:SetSize(18, h); R:SetPoint("BOTTOMRIGHT", 7, 0)
      local M = b:CreateTexture(nil, layer); M:SetAtlas("_" .. prefix .. "-center"); M:SetTexCoord(0, 1, 1, 0.25); M:SetHeight(h); M:SetPoint("BOTTOMLEFT", L, "BOTTOMRIGHT", 0, 0); M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
      local t = { L, M, R }
      if add then for _, x in ipairs(t) do x:SetBlendMode("ADD"); x:SetAlpha(0.4) end end
      return t
    end
    b.off = trio("uiframe-tab", 27, "BACKGROUND"); b.on = trio("uiframe-activetab", 31.5, "BACKGROUND"); trio("uiframe-tab", 27, "HIGHLIGHT", true)
    function b:SetSelected(on)
      for _, t in ipairs(self.off) do t:SetShown(not on) end
      for _, t in ipairs(self.on) do t:SetShown(on) end
      FontObject(self.text, on and GameFontHighlightSmall or GameFontNormalSmall, 10)
      -- the top 8 of the art is only its shadow: to the eye the dark tab is 19 tall and the lit one 24, and the word sits
      -- in the middle of what the eye sees (the game's own top tabs put it at 8 and 12 for the same reason)
      self.text:ClearAllPoints(); self.text:SetPoint("CENTER", self, "BOTTOM", 0, on and 12 or 9)
      self:SetEnabled(not on)   -- the open tab does not light under the mouse, as in the game
    end
  else
    b:SetHeight(26)
    b.plate = Plate(b, "quiet", true)
    b.text:SetPoint("CENTER", 0, 0)
    function b:SetSelected(on) if on then self.plate:Paint("gold"); self.text:SetTextColor(0.13, 0.09, 0.01) else self.plate:Paint("quiet"); self.text:SetTextColor(rgb(C.ink2)) end end
    b:SetScript("OnMouseDown", function(self) if not isOpen() then self.plate:Paint("quiet", "down") end end)
    b:SetScript("OnMouseUp", function(self) self.plate:Paint(isOpen() and "gold" or "quiet") end)
  end
  b:SetScript("OnClick", function() Sound("IG_CHARACTER_INFO_TAB"); onClick() end)
  return b
end
-- pages a player has switched off close up: their tabs go and the rest slide left (asked for on the ideas page, 19 Sep)
function UI.HiddenTab(key)
  if key == "plan" or key == "settings" or key == "feedback" then return false end
  if key == "popular" and S().othersBuilds == false then return true end
  return (S().hiddenTabs or {})[key] == true
end
function UI.LayoutTabs()
  if not side or not side.tabButtons then return end
  local x = 4
  for _, key in ipairs(TAB_ORDER) do
    local b = side.tabButtons[key]
    if b then
      if UI.HiddenTab(key) then b:Hide() else b:Show(); b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", side, "TOPLEFT", x, -TABS_H); x = x + b:GetWidth() + 1 end
    end
  end
  if UI.HiddenTab(S().sideTab) then UI.SetTab("home") end
end
local function MakeSide()
  local s = Frame("Frame", nil, F)
  s:SetSize(SIDE_W, TREE_H)
  -- the pages sit in the game's inset (its stone, in the dark, so light words read on it); the tabs stand on its top edge
  s.inset = Native("Frame", nil, s, "InsetFrameTemplate")
  if s.inset then
    s.inset:SetPoint("TOPLEFT", 0, -TABS_H); s.inset:SetPoint("BOTTOMRIGHT", 0, 0)
    if s.inset.Bg then s.inset.Bg:SetVertexColor(0.30, 0.29, 0.27) end
  else
    s.pane = CreateFrame("Frame", nil, s); s.pane:SetPoint("TOPLEFT", 0, -TABS_H); s.pane:SetPoint("BOTTOMRIGHT", 0, 0); s.pane:SetFrameLevel(s:GetFrameLevel())
    s.pane.bg = Solid(s.pane, "BACKGROUND", C.bg, 0.55); s.pane.bg:SetAllPoints()
    s.pane.edge = Edges(s.pane, s.pane, "BORDER", 0); s.pane.edge:SetColor(0.47, 0.36, 0.14, 0.8)
    s.pane.lip = s.pane:CreateTexture(nil, "BORDER", nil, 1); s.pane.lip:SetTexture(WHITE); s.pane.lip:SetPoint("TOPLEFT", 1, -1); s.pane.lip:SetPoint("TOPRIGHT", -1, -1); onePixel(s.pane.lip, true); s.pane.lip:SetVertexColor(1, 0.92, 0.7, 0.08)
  end
  s.tabButtons = {}
  local x = 4
  for _, key in ipairs(TAB_ORDER) do
    local b = MakeTab(s, TAB_LABEL[key], function() UI.SetTab(key) end, function() return S().sideTab == key end)
    b:SetPoint("BOTTOMLEFT", s, "TOPLEFT", x, -TABS_H); x = x + b:GetWidth() + 1
    s.tabButtons[key] = b
  end
  side = s
  BuildHomeTab(); BuildPlanTab(); BuildCoachTab(); BuildBuildsTab(); BuildPopularTab(); BuildClassicTab(); BuildRacialsTab(); BuildSettingsTab(); BuildFeedbackTab()
  UI.LayoutTabs()
  return s
end
-- the page turn: the old page folds away to the left, the new one unfolds from the same edge
local function PageTurn(old, new, key)
  if old == new then new:Show(); return end
  if not old.turnOut then
    local ag = old:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale"); s:SetDuration(0.1); s:SetSmoothing("IN")
    if s.SetScaleFrom then s:SetScaleFrom(1, 1); s:SetScaleTo(0.04, 1) else s:SetScale(0.04, 1) end
    if s.SetOrigin then s:SetOrigin("LEFT", 0, 0) end
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(0.1); a:SetSmoothing("IN")
    old.turnOut = ag
  end
  if not new.turnIn then
    local ag = new:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale"); s:SetDuration(0.15); s:SetSmoothing("OUT")
    if s.SetScaleFrom then s:SetScaleFrom(0.04, 1); s:SetScaleTo(1, 1) else s:SetScale(25, 1) end
    if s.SetOrigin then s:SetOrigin("LEFT", 0, 0) end
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15); a:SetSmoothing("OUT")
    new.turnIn = ag
  end
  for _, f in ipairs({ old, new }) do if f.turnOut then f.turnOut:Stop() end; if f.turnIn then f.turnIn:Stop() end end
  old.turnOut:SetScript("OnFinished", function()
    old:Hide()
    if S().sideTab ~= key then return end
    new:Show(); new.turnIn:Play()
  end)
  old.turnOut:Play()
end
function UI.SetTab(key)
  if not tabs[key] or UI.HiddenTab(key) then key = "home" end
  if F and F.gear then F.gear.on = key == "settings"; F.gear:Paint(F.gear.on) end
  local was = S().sideTab
  S().sideTab = key
  for k, t in pairs(tabs) do
    local on = k == key
    if on then
      if was ~= key and tabs[was] and tabs[was].frame:IsShown() then PageTurn(tabs[was].frame, t.frame, key) else t.frame:Show() end
      t.frame.spinPending = was ~= key
    elseif k ~= was or was == key then t.frame:Hide() end
    local b = side.tabButtons[k]
    if b then b:SetSelected(on) end
    if on and t.refresh then t.refresh() end
  end
end

-- ---------- the path ----------
local pathLayer, pathSegs = nil, {}
local function seg(k)
  local t = pathSegs[k]
  if t then return t end
  t = pathLayer:CreateTexture(nil, "OVERLAY"); t:SetTexture(SkinPath() .. "thread.png"); t:SetHeight(7)
  pathSegs[k] = t
  return t
end
local function centerIn(region)
  local x, y = region:GetCenter(); local lx, by = pathLayer:GetLeft(), pathLayer:GetBottom()
  if not x or not lx then return nil end
  return x - lx, y - by
end
-- the spark: one point of light that runs the whole thread, first level to last, and starts again
local pathPoly, spark = {}, nil
local function RunSpark()
  -- the running spark was too much motion for a tool; the thread and the breathing next point say the same thing
  pathLayer:SetScript("OnUpdate", nil)
end
local function DrawPath()
  -- no lines through the trees any more: the next point breathes, the plan list and the journey carry the order
  if not pathLayer then return end
  local keep = UI.nextTile
  local function drop() if keep then keep.nextPulse:Stop(); keep.nextGlow:SetAlpha(0); UI.nextTile = nil end end
  for _, tp in ipairs(trees) do for _, b in ipairs(tp.tiles) do if b ~= keep then b.nextPulse:Stop(); b.nextGlow:SetAlpha(0) end end end
  local list = TF.NextUp(plan())
  if #list < 1 then drop(); return end
  local live = isOwnClass() and G.live
  local nextK
  for k, e in ipairs(list) do if not e.done then nextK = k; break end end
  if not live then nextK = 1 end
  local nb
  if nextK and list[nextK] then local e = list[nextK]; nb = trees[e.ti] and trees[e.ti].tiles[e.i] end
  if nb ~= keep then drop() end
  if nb and nb ~= keep then nb.nextPulse:Play() end
  UI.nextTile = nb
end

-- The path: one mark per level from the first talent point to 60. The gold part ends at the level you are looking
-- at; click any mark, or roll the wheel over it, and the trees show the build as it stands there. Above it sit the
-- abilities worth waiting for: the ones your plan buys, and the class's well-known ones from the trainer.
local ICONIC = {
  WARRIOR = { "Whirlwind", "Execute", "Berserker Stance", "Intercept", "Cleave", "Overpower", "Revenge", "Shield Wall", "Recklessness", "Slam", "Taunt", "Sunder Armor", "Pummel", "Retaliation", "Berserker Rage", "Intimidating Shout", "Disarm", "Victory Rush" },
  PALADIN = { "Divine Shield", "Consecration", "Hammer of Wrath", "Blessing of Kings", "Exorcism", "Lay on Hands", "Blessing of Freedom", "Flash of Light", "Cleanse", "Holy Wrath", "Divine Intervention" },
  HUNTER = { "Feign Death", "Multi-Shot", "Freezing Trap", "Aimed Shot", "Rapid Fire", "Volley", "Aspect of the Cheetah", "Tame Beast", "Tranquilizing Shot", "Explosive Trap", "Aspect of the Pack" },
  ROGUE = { "Vanish", "Blind", "Kidney Shot", "Cheap Shot", "Kick", "Sprint", "Rupture", "Slice and Dice", "Expose Armor", "Garrote", "Ambush", "Poisons", "Distract" },
  PRIEST = { "Mind Control", "Flash Heal", "Psychic Scream", "Prayer of Healing", "Mind Blast", "Shackle Undead", "Dispel Magic", "Fear Ward", "Devouring Plague", "Shadow Word: Death", "Levitate", "Resurrection" },
  SHAMAN = { "Ghost Wolf", "Chain Lightning", "Windfury Weapon", "Chain Heal", "Purge", "Frost Shock", "Flame Shock", "Reincarnation", "Astral Recall", "Grounding Totem", "Windfury Totem", "Tremor Totem" },
  MAGE = { "Blink", "Counterspell", "Polymorph", "Evocation", "Cone of Cold", "Blizzard", "Frost Nova", "Mana Shield", "Arcane Explosion", "Ice Armor", "Scorch", "Frostfire Bolt", "Portal: Orgrimmar", "Portal: Stormwind", "Arcane Brilliance", "Mage Armor", "Teleport: Orgrimmar", "Teleport: Stormwind" },
  WARLOCK = { "Summon Succubus", "Summon Felhunter", "Summon Voidwalker", "Banish", "Death Coil", "Howl of Terror", "Hellfire", "Drain Life", "Create Soulstone", "Summon Felsteed", "Inferno", "Curse of the Elements" },
  DRUID = { "Cat Form", "Bear Form", "Travel Form", "Dire Bear Form", "Rebirth", "Innervate", "Tranquility", "Hibernate", "Regrowth", "Aquatic Form", "Barkskin", "Hurricane" },
}
-- One marker per level that brings something worth waiting for: an ability your plan buys there, or abilities that are
-- new at the trainer (first ranks only, from the beta client's trainer table, which runs to 60). A marker stands for
-- everything new at its level; its tooltip lists it all. Who gets a place when two would touch: what the plan buys, then
-- the late levels (there are few, and they are the ones a leveler waits for), then the class's well-known abilities.
local function Milestones(p)
  local cd = classData(); local start = TF.StartLevel()
  local byLevel = {}
  local function slot(lv) local s = byLevel[lv]; if not s then s = { level = lv, talents = {}, spells = {} }; byLevel[lv] = s end; return s end
  local firstAt = {}
  for k, o in ipairs(TF.FixOrder(p)) do local key = o[1] * 100 + o[2]; if not firstAt[key] then firstAt[key] = start + k - 1 end end
  for ti, tree in ipairs(cd.trees) do for i, t in ipairs(tree.talents) do
    local lv = firstAt[ti * 100 + i]
    if lv and not t.passive then local s = slot(lv); s.talents[#s.talents + 1] = { name = t.name, icon = IconFor(t), ti = ti, i = i } end
  end end
  local pri = {}
  for k, name in ipairs(ICONIC[p.cls] or {}) do pri[name] = k end
  local L = D.learn and D.learn[p.cls]
  if L then
    for name, rec in pairs(L) do
      local lv = rec.levels and rec.levels[1]
      if lv and lv >= start and lv <= 60 and not rec.passive and TF.TrainerTeaches(p.cls, name, rec, 1) then
        local s = slot(lv); s.spells[#s.spells + 1] = { name = name, icon = IconFor({ icon = rec.icon }), pri = pri[name] or 99 }
      end
    end
  end
  local slots = {}
  for _, s in pairs(byLevel) do
    table.sort(s.spells, function(a, b) if a.pri ~= b.pri then return a.pri < b.pri end; return a.name < b.name end)
    s.best = s.spells[1] and s.spells[1].pri or 99
    s.class = (#s.talents > 0 and 0) or (s.level >= 40 and 1) or (s.best < 99 and 2) or 3
    slots[#slots + 1] = s
  end
  table.sort(slots, function(a, b)
    if a.class ~= b.class then return a.class < b.class end
    if a.class == 2 and a.best ~= b.best then return a.best < b.best end
    return a.level < b.level
  end)
  local kept = {}
  for _, s in ipairs(slots) do
    local ok = #kept < 22
    for _, q in ipairs(kept) do if math.abs(q.level - s.level) < 2 then ok = false; break end end
    if ok then kept[#kept + 1] = s end
  end
  return kept
end
local journey
local function MakeJourney(parent)
  local j = CreateFrame("Frame", nil, parent)
  j:SetPoint("TOPLEFT", 0, -30); j:SetPoint("TOPRIGHT", 0, -30); j:SetHeight(22)
  j.rail = j:CreateTexture(nil, "BACKGROUND"); j.rail:SetTexture(SkinPath() .. "thread.png"); j.rail:SetPoint("LEFT", 0, 0); j.rail:SetPoint("RIGHT", 0, 0); j.rail:SetHeight(6); j.rail:SetVertexColor(0.55, 0.45, 0.2, 0.5)
  j.done = j:CreateTexture(nil, "BACKGROUND", nil, 1); j.done:SetTexture(SkinPath() .. "thread.png"); j.done:SetPoint("LEFT", 0, 0); j.done:SetHeight(6); j.done:SetWidth(1)
  Gradient(j.done, "HORIZONTAL", 0.78, 0.61, 0.10, 0.9, 1, 0.82, 0, 1)
  j.ticks, j.labels, j.marks = {}, {}, {}
  -- where you are looking: a small gold pointer under the rail and its level in gold
  j.needle = j:CreateTexture(nil, "OVERLAY", nil, 3); j.needle:SetTexture(MEDIA .. "arrow.tga"); j.needle:SetSize(11, 11); j.needle:SetRotation(math.pi); j.needle:SetVertexColor(1, 0.82, 0)
  j.needleText = Text(j, 11, C.gold); j.needleText:SetJustifyH("CENTER")
  -- where your character is: a gold diamond on the rail with "you" under it (the class crest there read as one more ability)
  j.you = CreateFrame("Button", nil, j); j.you:SetSize(14, 14); j.you:SetFrameLevel(j:GetFrameLevel() + 6)
  j.you.back = j.you:CreateTexture(nil, "ARTWORK", nil, 1); j.you.back:SetTexture(WHITE); j.you.back:SetSize(11, 11); j.you.back:SetPoint("CENTER"); j.you.back:SetRotation(math.rad(45)); j.you.back:SetVertexColor(0.1, 0.07, 0.02, 1)
  j.you.icon = j.you:CreateTexture(nil, "ARTWORK", nil, 2); j.you.icon:SetTexture(WHITE); j.you.icon:SetSize(8, 8); j.you.icon:SetPoint("CENTER"); j.you.icon:SetRotation(math.rad(45)); j.you.icon:SetVertexColor(1, 0.82, 0, 1)
  j.youText = Text(j, 10, C.gold); j.youText:SetJustifyH("CENTER"); j.youText:SetText("you")
  j.you:SetScript("OnEnter", function(self)
    TipBegin(self); GameTooltip:SetText(string.format("You are level %d", UnitLevel("player") or 1), 1, 0.82, 0)
    if (UnitLevel("player") or 1) < TF.StartLevel() then GameTooltip:AddLine(string.format("Talent points start at level %d.", TF.StartLevel()), 0.9, 0.9, 0.9) else GameTooltip:AddLine("Click to look at your build at your level.", 0.9, 0.9, 0.9) end
    TipEnd(self)
  end)
  j.you:SetScript("OnLeave", function() GameTooltip:Hide() end)
  j.you:SetScript("OnClick", function() TF.SetLevel(math.max(TF.StartLevel(), UnitLevel("player") or 60)) end)
  j.hint = Text(j, 13, C.muted); j.hint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -76); j.hint:SetJustifyH("RIGHT")
  j:EnableMouseWheel(true)
  j:SetScript("OnMouseWheel", function(_, d) TF.SetLevel(plan().level + (d > 0 and 1 or -1)) end)
  return j
end
local function RefreshJourney()
  local j = journey; if not j then return end
  local p = plan(); local start = TF.StartLevel()
  local span = 60 - start + 1
  local w = j:GetWidth() or 700; if w < 100 then w = 700 end
  local step = w / span
  local function xAt(level) return math.floor((level - start + 0.5) * step + 0.5) end   -- whole pixels: a mark on a half pixel draws soft
  local list = TF.NextUp(p)
  local live = isOwnClass() and G.live
  local lvl = UnitLevel("player") or 1
  local doneCount = 0
  for k = 1, span do
    local t = j.ticks[k]
    if not t then
      t = CreateFrame("Button", nil, j); t:SetSize(math.max(6, math.floor(step)), 22)
      t.tex = Solid(t, "ARTWORK", C.muted, 0.8); t.tex:SetPoint("CENTER"); t.tex:SetSize(2, 8)
      t:SetScript("OnEnter", function(self)
        local e = self.e
        UI.LevelPeek(self.level); TipBegin(self); GameTooltip:SetText(string.format("Level %d", self.level), 1, 0.82, 0)
        if e then local tt = classData().trees[e.ti].talents[e.i]; GameTooltip:AddLine(string.format("%s %d/%d%s", tt.name, e.rank, tt.max, e.done and "  (placed)" or ""), 0.9, 0.9, 0.9)
        else GameTooltip:AddLine("Nothing planned for this point yet.", 0.6, 0.6, 0.6) end
        local sp = TF.NewSpellsAt(plan().cls, self.level)
        if #sp > 0 then GameTooltip:AddLine("Trainer: " .. TF.SpellsSummary(sp, 4) .. ".", 0.74, 0.74, 0.74, true) end
        GameTooltip:AddLine("The talents lit gold on the trees are what the plan gains by then. Click to look at the build at this level.", 0.54, 0.54, 0.54, true)
        GameTooltip:Show(); self.tex:SetHeight(14)
      end)
      t:SetScript("OnLeave", function(self) GameTooltip:Hide(); self.tex:SetHeight(self.h or 8) end)
      t:SetScript("OnClick", function(self) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); TF.SetLevel(self.level) end)
      j.ticks[k] = t
    end
    t.k = k; t.e = list[k]; t.level = start + k - 1
    t:ClearAllPoints(); t:SetPoint("CENTER", j, "LEFT", xAt(t.level), 0); t:Show()
    local e = list[k]; local beyond = t.level > p.level
    if e and live and e.done then t.tex:SetVertexColor(1, 0.82, 0, 1); t.h = 10; doneCount = k
    elseif e then t.tex:SetVertexColor(0.78, 0.61, 0.10, beyond and 0.4 or 0.9); t.h = 8
    else t.tex:SetVertexColor(0.4, 0.4, 0.4, beyond and 0.4 or 0.7); t.h = 5 end
    t.tex:SetHeight(t.h)
  end
  for k = span + 1, #j.ticks do j.ticks[k]:Hide() end
  -- level numbers every ten levels; the one under the pointer gives way to it
  for i, lv in ipairs({ start, 20, 30, 40, 50, 60 }) do
    local l = j.labels[i]
    if not l then l = Text(j, 10, C.muted); j.labels[i] = l end
    local lx = xAt(lv)
    local youX = isOwnClass() and xAt(math.max(start, math.min(60, lvl))) or -999
    l:ClearAllPoints(); l:SetPoint("TOP", j, "LEFT", lx, -17); l:SetText(lv); l:SetShown(math.abs(lx - xAt(p.level)) >= 26 and math.abs(lx - youX) >= 26)
  end
  -- the pointer and the gold part of the rail glide to the level being looked at
  local to = xAt(p.level)
  local from = j.needleX or to
  j.needleX = to
  j.needleText:SetText((isOwnClass() and p.level == lvl) and (p.level .. ", you") or p.level)
  local function place(x)
    j.needle:ClearAllPoints(); j.needle:SetPoint("CENTER", j, "LEFT", x, -9)
    j.needleText:ClearAllPoints(); j.needleText:SetPoint("TOP", j, "LEFT", x, -16)
    j.done:SetWidth(math.max(1, x))
  end
  if math.abs(from - to) > 0.5 then Tween("needle", 0.16, function(e) place(lerp(from, to, e)) end, { ease = "out4" }) else place(to) end
  -- you
  j.you:SetShown(isOwnClass() and true or false)
  j.youText:Hide()
  if isOwnClass() then
    local yx = math.max(8, math.min(w - 8, xAt(math.max(start, math.min(60, lvl)))))
    j.you:ClearAllPoints(); j.you:SetPoint("CENTER", j, "LEFT", yx, 0)
    -- the word sits under the diamond, unless the pointer's number is about to land on it: then the diamond alone says you
    if p.level ~= lvl and math.abs(to - yx) >= 30 then j.youText:ClearAllPoints(); j.youText:SetPoint("TOP", j, "LEFT", yx, -16); j.youText:Show() end
  end
  -- the abilities worth waiting for
  local ms = Milestones(p)
  for k, m in ipairs(ms) do
    local b = j.marks[k]
    if not b then
      b = CreateFrame("Button", nil, j); b:SetSize(18, 18); b:SetFrameLevel(j:GetFrameLevel() + 4)
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      b.edge = Edges(b, b, "OVERLAY", 1)
      b.stem = b:CreateTexture(nil, "BACKGROUND"); b.stem:SetTexture(WHITE); b.stem:SetSize(1, 6); b.stem:SetPoint("TOP", b, "BOTTOM", 0, 0); b.stem:SetVertexColor(0.78, 0.61, 0.10, 0.5)
      b.more = b:CreateTexture(nil, "OVERLAY", nil, 3); b.more:SetTexture(WHITE); b.more:SetSize(5, 5); b.more:SetPoint("CENTER", b, "TOPRIGHT", 0, 0); b.more:SetVertexColor(1, 0.82, 0)
      b:SetScript("OnEnter", function(self)
        local m2 = self.m
        UI.LevelPeek(m2.level); TipBegin(self); GameTooltip:SetText(string.format("Level %d", m2.level), 1, 0.82, 0)
        for _, t in ipairs(m2.talents) do GameTooltip:AddLine(t.name .. ", from your plan.", 1, 1, 1) end
        if #m2.spells > 0 then
          local names = {}
          for _, sp in ipairs(m2.spells) do names[#names + 1] = sp.name end
          GameTooltip:AddLine("New at the trainer: " .. table.concat(names, ", ") .. ".", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:AddLine("The talents lit gold on the trees are what the plan gains by then. Click to look at the build at this level.", 0.54, 0.54, 0.54, true)
        GameTooltip:Show()
        local t1 = m2.talents[1]
        if t1 then local tile = trees[t1.ti] and trees[t1.ti].tiles[t1.i]; if tile then Land(tile, true) end end
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function(self) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); TF.SetLevel(self.m.level) end)
      j.marks[k] = b
    end
    b.m = m; b:Show(); b:ClearAllPoints(); b:SetPoint("CENTER", j, "LEFT", xAt(m.level), 18)
    local lead = m.talents[1] or m.spells[1]
    b.icon:SetTexture(lead.icon)
    b.more:SetShown((#m.talents + #m.spells) > 1)
    local reached = m.level <= p.level
    if b.lastKey == m.level and b.wasReached == false and reached then Bump(b, 1.22) end
    b.lastKey, b.wasReached = m.level, reached
    b.icon:SetDesaturated(not reached); b.icon:SetVertexColor(reached and 1 or 0.55, reached and 1 or 0.55, reached and 1 or 0.55)
    if #m.talents > 0 then b.edge:SetColor(1, 0.82, 0, reached and 1 or 0.5) else b.edge:SetColor(0.55, 0.50, 0.38, reached and 0.9 or 0.45) end
    b.more:SetAlpha(reached and 1 or 0.5)
  end
  for k = #ms + 1, #j.marks do j.marks[k]:Hide() end
  local fullPool = math.min(51, 60 - 9 + TF.TalentedRank())
  j.hint:SetText(string.format("%d of %d planned%s", #list, fullPool, live and doneCount > 0 and string.format(", %d placed", doneCount) or ""))
end

-- ---------- header and footer ----------
-- the plain class button instead of the game's dropdown: chosen in Settings, forced once the game blocks the dropdown, or while a gamepad is on
function UI.PlainClassList()
  if S().plainClassList then return true end
  if GetCVarBool then local ok, on = pcall(GetCVarBool, "GamePadEnable"); if ok and on then return true end end
  return false
end
local function MakeHead()
  local h = CreateFrame("Frame", nil, F)
  h:SetPoint("TOPLEFT", MARGIN, -TOP); h:SetPoint("TOPRIGHT", -MARGIN, -TOP); h:SetHeight(HEAD_H)
  local mid = -HEAD_H / 2
  local x0 = 56     -- the frame's round portrait stands in the corner; the header starts beside it
  if F.native then
    h.book = F:GetPortrait()
  else
    x0 = 44
  end
  -- the class: its crest, then the game's own dropdown with the nine classes in it, then what the build is
  h.classIcon = h:CreateTexture(nil, "ARTWORK"); h.classIcon:SetSize(24, 24); h.classIcon:SetPoint("LEFT", h, "TOPLEFT", x0, mid)
  h.classEdge = Edges(h, h.classIcon, "OVERLAY", 1); h.classEdge:SetColor(0.78, 0.61, 0.10, 0.85)
  local CLASS_TIP = "Each class keeps its own plan on this character. Apply only ever touches your own."
  -- The game's dropdown template reaches into the gamepad interact path when it opens; on one reader's client (0.34.2,
  -- 27 Sep) that raised ADDON_ACTION_FORBIDDEN and froze the game, and the plain button fixed it. So: the plain button when
  -- a gamepad is enabled, when the game has blocked us once (the boot frame remembers it), or when Settings says so.
  local drop = (not UI.PlainClassList()) and Native("DropdownButton", nil, h, "WowStyle1DropdownTemplate") or nil
  if drop and drop.SetupMenu then
    h.classDrop = drop
    drop:SetSize(150, 25); drop:SetPoint("LEFT", h.classIcon, "RIGHT", 8, 1)
    drop:SetupMenu(function(_, root)
      for _, cf in ipairs(CLASS_ORDER) do
        local cd = D.classes[cf]
        if cd then
          local r, g, bl = TF.ClassColor(cf)
          local name = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(bl * 255 + 0.5), cd.name)
          local radio = root:CreateRadio(name, function() return plan().cls == cf end, function()
            if plan().cls ~= cf then
              local was = classData().name
              if TF.SetClass(cf) then UI.Note(string.format("%s plan open. Your %s plan is kept.", cd.name, was)) end
            end
            return MenuResponse and MenuResponse.Close or nil    -- a pick closes the list, like picking from any of the game's lists
          end)
          if radio and radio.AddInitializer then
            radio:AddInitializer(function(button) if button.AttachTexture then local tex = button:AttachTexture(); tex:SetSize(16, 16); tex:SetPoint("RIGHT", -2, 0); SetClassIcon(tex, cf) end end)
          end
        end
      end
    end)
    drop:HookScript("OnEnter", function(self) TipBegin(self); GameTooltip:SetText("Plan another class", 1, 0.82, 0); GameTooltip:AddLine(CLASS_TIP, 0.9, 0.9, 0.9, true); TipEnd(self, "beside") end)
    drop:HookScript("OnLeave", function() GameTooltip:Hide() end)
    drop:HookScript("OnMouseDown", function() GameTooltip:Hide() end)   -- the list opens where the tooltip sat
    h.sub = Text(h, 13, C.ink2); h.sub:SetPoint("LEFT", drop, "RIGHT", 14, -1)
  else
    -- no dropdown in this client: the class name is a button that opens the other classes in place
    h.classBtn = Button(h, "Class", 104, 24, function() UI.OpenClassCard() end); h.classBtn:SetPoint("LEFT", h.classIcon, "RIGHT", 8, 0)
    if LOOK() == "site" then
      -- the site's banner: the emblem, the class name in Cinzel gold (click it for the other classes), the sentence under it
      h.classIcon:SetSize(34, 34); h.classIcon:ClearAllPoints(); h.classIcon:SetPoint("LEFT", h, "TOPLEFT", x0 - 40, mid)
      h.classEdge:SetColor(0, 0, 0, 0); h.emblem = h:CreateTexture(nil, "BORDER"); h.emblem:SetTexture(SkinPath() .. "disc.png"); h.emblem:SetSize(44, 44); h.emblem:SetPoint("CENTER", h.classIcon, "CENTER", 0, 0)
      pcall(function() local m = h:CreateMaskTexture(); m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); m:SetAllPoints(h.classIcon); h.classIcon:AddMaskTexture(m) end)
      h.classBtn.plate.body:SetAlpha(0); for _, e in ipairs(h.classBtn.plate.edges) do e:SetAlpha(0) end; h.classBtn.plate.hi:SetAlpha(0); h.classBtn.plate.lo:SetAlpha(0); if h.classBtn.plate.drop then h.classBtn.plate.drop:SetAlpha(0) end
      Font(h.classBtn.label, 18, true); h.classBtn.label:ClearAllPoints(); h.classBtn.label:SetPoint("LEFT", 0, 0); h.classBtn.label:SetJustifyH("LEFT")
      h.classBtn:ClearAllPoints(); h.classBtn:SetPoint("LEFT", h.classIcon, "RIGHT", 12, 7); h.classBtn:SetSize(180, 22)
      function h.classBtn:Ink() self.label:SetTextColor(1, 0.84, 0.37); self.label:SetShadowColor(0.48, 0.35, 0.06, 1); self.label:SetShadowOffset(0, -1) end
      h.classBtn:Ink()
    end
    Tip(h.classBtn, "Plan another class", "Opens the classes right here. " .. CLASS_TIP)
    h.sub = Text(h, 13, C.ink2); h.sub:SetPoint("LEFT", h.classBtn, "RIGHT", 10, 0)
    if LOOK() == "site" then h.sub:ClearAllPoints(); h.sub:SetPoint("TOPLEFT", h.classBtn, "BOTTOMLEFT", 0, -2); h.sub:SetWidth(360); h.sub:SetJustifyH("LEFT"); h.sub:SetWordWrap(false); Font(h.sub, 12) end
    h.strip = CreateFrame("Frame", nil, h); h.strip:SetSize(#CLASS_ORDER * 30, 24); h.strip:SetPoint("LEFT", h.classBtn, "RIGHT", 10, 0); h.strip:Hide()
    h.strip.buttons = {}
    for k, cf in ipairs(CLASS_ORDER) do
      if D.classes[cf] then
        local b = CreateFrame("Button", nil, h.strip); b:SetSize(24, 24); b:SetPoint("LEFT", (k - 1) * 30, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); SetClassIcon(b.icon, cf)
        b.edge = Edges(b, b, "OVERLAY", 1)
        b:SetHighlightTexture(WHITE); local hl = b:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 0.82, 0, 0.25) end
        b.cf = cf
        b:SetScript("OnEnter", function(self)
          local cd = TF.CharDB(); local has = (self.cf == plan().cls) and TF.TotalPts(plan()) or (cd.plans and cd.plans[self.cf] and TF.TotalPts(cd.plans[self.cf]) or 0)
          local r, g, bb = TF.ClassColor(self.cf)
          TipBegin(self); GameTooltip:SetText(D.classes[self.cf].name, r, g, bb)
          GameTooltip:AddLine(has > 0 and string.format("%d points planned on this character.", has) or "No plan yet.", 0.9, 0.9, 0.9); TipEnd(self)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
          Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); GameTooltip:Hide()
          local was = classData().name
          h.strip:Hide(); h.sub:Show(); if h.planBtn then h.planBtn:Show() end
          if TF.SetClass(self.cf) then UI.Note(string.format("%s plan open. Your %s plan is kept.", D.classes[self.cf].name, was)) end
        end)
        h.strip.buttons[#h.strip.buttons + 1] = b
      end
    end
    UI.classStrip = h.strip
  end
  -- Plans, a small chip after the class (0.37.0): this character's plans for the class, a new one, a copy, a rename. The chip
  -- names what it does (Chris, 4 Oct); the open plan's name goes on the line beside it once the class keeps more than one.
  h.planBtn = Button(h, "Plans", "auto", 20, function() UI.OpenPlans() end); h.planBtn.minW = 56; h.planBtn:Fit()
  h.planBtn:SetPoint("LEFT", h.classDrop or h.classBtn, "RIGHT", 10, h.classDrop and -1 or 0)
  h.sub:ClearAllPoints(); h.sub:SetPoint("LEFT", h.planBtn, "RIGHT", 10, 0); UI.planBtn = h.planBtn
  Tip(h.planBtn, "Your plans for this class", "Keep more than one plan on this character, like the game's equipment sets: one for leveling, one for later. Click to switch, or to make, copy or rename one. Apply follows the open plan.")
  -- on the right: the points, and beside them the level you are looking at between the game's page arrows
  if AtlasOK("Talents-Square-Box-c60") then
    -- the game's points box: the number of points still free in the dark square, what is placed beside it
    h.ptsBox = h:CreateTexture(nil, "ARTWORK"); Atlas(h.ptsBox, "Talents-Square-Box-c60", 125, 45); h.ptsBox:SetPoint("TOPRIGHT", h, "TOPRIGHT", 4, 2)
    h.points = Text(h, 20, C.gold); h.points:SetPoint("CENTER", h.ptsBox, "RIGHT", -26, 4); h.points:SetJustifyH("CENTER")
    h.leftLabel = Text(h, 10, C.muted); h.leftLabel:SetPoint("TOP", h.points, "BOTTOM", 0, -1); h.leftLabel:SetJustifyH("CENTER"); h.leftLabel:SetText("LEFT")
    h.pointsLabel = Text(h, 12, C.ink2); h.pointsLabel:SetPoint("RIGHT", h.ptsBox, "LEFT", 58, 7); h.pointsLabel:SetJustifyH("RIGHT"); h.pointsLabel:SetText("0 / 51")
    h.placedLabel = Text(h, 10, C.muted); h.placedLabel:SetPoint("RIGHT", h.ptsBox, "LEFT", 58, -8); h.placedLabel:SetJustifyH("RIGHT"); h.placedLabel:SetText("PLACED")
    h.gameBox = true
  else
    h.points = Text(h, 18, C.gold); h.points:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -2); h.points:SetJustifyH("RIGHT")
    h.pointsLabel = Text(h, 10, C.muted); h.pointsLabel:SetPoint("TOPRIGHT", h.points, "BOTTOMRIGHT", 0, -2); h.pointsLabel:SetJustifyH("RIGHT"); h.pointsLabel:SetText("POINTS")
  end
  h.plus = Stepper(h, true, function() TF.SetLevel(plan().level + 1) end); h.plus:SetPoint("RIGHT", h, "TOPRIGHT", -166, mid)
  h.seal = CreateFrame("Button", nil, h); h.seal:SetSize(44, 34); h.seal:SetPoint("RIGHT", h.plus, "LEFT", -2, 0)
  h.lv = Text(h.seal, 20, C.ink); h.lv:SetPoint("TOP", 0, 0); h.lv:SetJustifyH("CENTER")
  h.lvLabel = Text(h.seal, 10, C.muted); h.lvLabel:SetPoint("TOP", h.lv, "BOTTOM", 0, -2); h.lvLabel:SetText("LEVEL"); h.lvLabel:SetJustifyH("CENTER")
  h.seal:SetHighlightTexture(WHITE); local shl = h.seal:GetHighlightTexture(); if shl then shl:SetVertexColor(1, 0.82, 0, 0.08) end
  h.minus = Stepper(h, false, function() TF.SetLevel(plan().level - 1) end); h.minus:SetPoint("RIGHT", h.seal, "LEFT", -2, 0)
  -- find a talent: by its name, or by a spell it changes. Matches light up on the trees, the rest step back.
  h.search = EditBox(h, 150, 20); h.search:SetPoint("RIGHT", h.minus, "LEFT", -18, 0); h.search.hint:SetText("Find a talent")
  local bb = CreateFrame("Button", nil, h); bb:SetSize(108, 26); bb:SetPoint("RIGHT", h.search, "LEFT", -16, 0); h.bookBtn = bb
  -- the site's header chip: a purple disc, the game's own spellbook icon cut round on it, the word beside it. No plate, no square.
  bb.disc = bb:CreateTexture(nil, "BACKGROUND"); bb.disc:SetTexture(SkinPath() .. "disc.png"); bb.disc:SetSize(36, 36); bb.disc:SetPoint("LEFT", -3, 0); bb.disc:SetVertexColor(0.55, 0.36, 1, 0.9); bb.disc:SetBlendMode("ADD")
  bb.halo = bb:CreateTexture(nil, "BACKGROUND", nil, -1); bb.halo:SetTexture(SkinPath() .. "disc.png"); bb.halo:SetSize(48, 48); bb.halo:SetPoint("CENTER", bb.disc, "CENTER", 0, 0); bb.halo:SetVertexColor(0.62, 0.42, 1, 0.3); bb.halo:SetBlendMode("ADD")
  bb.icon = bb:CreateTexture(nil, "ARTWORK"); bb.icon:SetSize(20, 20); bb.icon:SetPoint("CENTER", bb.disc, "CENTER", 0, 0); bb.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); bb.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  bb.label = Text(bb, 13, C.purple); bb.label:SetPoint("LEFT", bb.disc, "RIGHT", 8, 0); bb.label:SetText("Spellbook"); bb.label:SetShadowColor(0.15, 0.05, 0.35, 1); bb.label:SetShadowOffset(1, -1)
  bb.pulse = Pulse(bb.halo, 0.2, 0.5, 2.4); bb.pulse:Play()
  bb:SetScript("OnEnter", function(self) self.label:SetTextColor(0.92, 0.85, 1); self.disc:SetVertexColor(0.72, 0.55, 1, 1) end)
  bb:SetScript("OnLeave", function(self) self.label:SetTextColor(rgb(C.purple)); self.disc:SetVertexColor(0.55, 0.36, 1, 0.9); GameTooltip:Hide() end)
  bb:SetScript("OnClick", function() Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); UI.OpenTrainer(true, "book") end)
  bb:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", self.disc, "CENTER", 0, -1) end); bb:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", self.disc, "CENTER", 0, 0) end)
  do local enter = bb:GetScript("OnEnter"); bb:SetScript("OnEnter", function(self) enter(self); TipBegin(self); GameTooltip:SetText("Your spellbook, by level", 1, 0.82, 0); GameTooltip:AddLine("Every ability of the class from 1 to 60, the level each rank comes, what you have and what is still to come. The game's own book only shows what you have.", 0.9, 0.9, 0.9, true); TipEnd(self) end) end
  h.sub:SetPoint("RIGHT", h.bookBtn, "LEFT", -10, 0); h.sub:SetWordWrap(false)
  h.search:HookScript("OnTextChanged", function(self) UI.Search(self:GetText()) end)
  h.search:SetScript("OnEnterPressed", function(self) UI.SearchJump(); self:ClearFocus() end)
  h.search:HookScript("OnEscapePressed", function(self) self:SetText("") end)
  Tip(h.search, "Find a talent", "Type part of a name, or of a spell: 'frostbolt' lights every talent that changes Frostbolt. Enter jumps to the first. Escape clears.")
  h.seal:SetScript("OnClick", function()
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    local me = math.max(TF.StartLevel(), math.min(60, UnitLevel("player") or 60))
    TF.SetLevel(plan().level == 60 and me or 60)
  end)
  local LEVEL_TIP = "The trees show your build as it stands at this level. Roll the wheel here, press the arrows, or click a mark on the path below. Nothing is lost: later points wait their turn. Click the number to jump between your level and 60."
  Tip(h.seal, "The level you are looking at", LEVEL_TIP)
  for _, fr in ipairs({ h.seal, h.minus, h.plus }) do
    fr:EnableMouseWheel(true); fr:SetScript("OnMouseWheel", function(_, d) TF.SetLevel(plan().level + (d > 0 and 1 or -1)) end)
  end
  Tip(h.minus, "One level earlier", "The trees show the build as it stands at that level. The wheel here does the same.")
  Tip(h.plus, "One level later", "The trees show the build as it stands at that level. The wheel here does the same.")
  h.rule = h:CreateTexture(nil, "ARTWORK"); h.rule:SetTexture(WHITE); h.rule:SetPoint("BOTTOMLEFT", x0, -2); h.rule:SetPoint("BOTTOMRIGHT", 0, -2); h.rule:SetHeight(1)
  Gradient(h.rule, "HORIZONTAL", 0.78, 0.61, 0.10, 0.8, 0.78, 0.61, 0.10, 0.05)
  return h
end
-- the other classes open in the header, in place of the spec line; no card
function UI.OpenClassCard()
  if not head then return end
  if head.classDrop then
    local d = head.classDrop
    if d.IsMenuOpen and d:IsMenuOpen() and d.CloseMenu then d:CloseMenu() elseif d.OpenMenu then d:OpenMenu() end
    return
  end
  local show = not head.strip:IsShown()
  head.strip:SetShown(show); head.sub:SetShown(not show); head.planBtn:SetShown(not show); if show then UI.OpenPlans(false) end
  for _, b in ipairs(head.strip.buttons) do
    local on = b.cf == plan().cls
    b.edge:SetColor(on and 1 or 0.78, on and 0.84 or 0.61, on and 0.37 or 0.10, on and 1 or 0.45)
  end
end

-- the plans card (0.37.0): this character's plans for the open class, under the chip. The open one is marked gold; a click
-- on another opens it and the card closes. Under the list, a name box with New (an empty plan), Copy (the open plan again)
-- and Rename (the open plan). A plan on the shelf has an x; the open one cannot go.
function UI.MakePlanCard()
  local c = CreateFrame("Frame", nil, F); c:SetSize(330, 100); c:SetFrameStrata("DIALOG"); c:SetFrameLevel(F:GetFrameLevel() + 40); Card(c)   -- over the trees and their ring art, under tooltips
  c:SetPoint("TOPLEFT", head.planBtn, "BOTTOMLEFT", -8, -6)
  c.title = Text(c, 11, C.muted); c.title:SetPoint("TOPLEFT", 14, -10)
  c.rows = {}
  local ROW, W = 24, 302
  local function row(k)
    local r = c.rows[k]; if r then return r end
    r = CreateFrame("Button", nil, c); r:SetSize(W, ROW); r:SetPoint("TOPLEFT", 14, -(26 + (k - 1) * ROW))
    r:SetHighlightTexture(WHITE); r:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.08)
    r.accent = Solid(r, "BACKGROUND", C.gold, 0, 1); r.accent:SetPoint("TOPLEFT", -6, -3); r.accent:SetPoint("BOTTOMLEFT", -6, 3); r.accent:SetWidth(3)
    r.name = Text(r, 13, C.ink); r.name:SetPoint("LEFT", 4, 0); r.name:SetPoint("RIGHT", -96, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.pts = Text(r, 11, C.muted); r.pts:SetPoint("RIGHT", -26, 0); r.pts:SetJustifyH("RIGHT")
    r.del = CloseX(r, 14); r.del:SetPoint("RIGHT", -4, 0); r.del:SetScript("OnClick", function() if r.onDelete then r.onDelete() end end)
    Tip(r.del, "Delete this plan", "Only a plan that is not open can go. Open another first to delete the open one.")
    r:SetScript("OnClick", function() if r.onPick then r.onPick() end end)
    c.rows[k] = r; return r
  end
  c.name = EditBox(c, 110, 20); c.name.hint:SetText("Name a plan")
  local function taken(ok, p) if ok then UI.OpenPlans(false); UI.Refresh() else UI.Note(p) end; return ok, p end
  c.new = Button(c, "New", "auto", 20, function()
    local ok, nm = taken(TF.AddPlan(c.name:GetText(), false))
    if ok then UI.Note(nm .. " is open and empty. Click a talent, or load a build into it. The chip after your class switches plans.", nil, 10) end
  end); c.new.minW = 44; c.new:Fit(); c.new:SetPoint("LEFT", c.name, "RIGHT", 8, 0)
  c.copy = Button(c, "Copy", "auto", 20, function()
    local was = TF.PlanName(); local ok, nm = taken(TF.AddPlan(c.name:GetText(), true))
    if ok then UI.Note(string.format("%s is open, a copy of %s. Change it as you like; %s is kept as it was.", nm, was, was), nil, 10) end
  end); c.copy.minW = 44; c.copy:Fit(); c.copy:SetPoint("LEFT", c.new, "RIGHT", 6, 0)
  c.rename = Button(c, "Rename", "auto", 20, function()
    if TF.RenamePlan(c.name:GetText()) then c.name:SetText(""); c.name:ClearFocus(); c:Fill(); UI.Refresh() else UI.Note("Type the new name in the box first.") end
  end); c.rename.minW = 44; c.rename:Fit(); c.rename:SetPoint("LEFT", c.copy, "RIGHT", 6, 0)
  c.name:SetScript("OnEnterPressed", function() c.rename:Click() end)
  Tip(c.new, "A new, empty plan", "Opens a fresh plan for this class and keeps the open one. Name it in the box first, or it gets a number.")
  Tip(c.copy, "This plan again", "Opens a copy of the open plan so you can try changes without touching it. Name it in the box first, or it gets a number.")
  Tip(c.rename, "Rename the open plan", "Type a name in the box, then press this. Enter does the same.")
  function c:Fill()
    local list = TF.PlanList(); local cd = classData()
    self.title:SetText(string.format("YOUR %s PLANS ON THIS CHARACTER", cd.name:upper()))
    for k, e in ipairs(list) do
      local r = row(k); local parts = {}
      for ti = 1, #cd.trees do parts[ti] = TF.TreePts(e.plan, ti) end
      r.name:SetText(e.name); r.name:SetTextColor(rgb(k == 1 and C.gold or C.ink))
      r.pts:SetText(table.concat(parts, "/")); r.accent:SetAlpha(k == 1 and 1 or 0); r.del:SetShown(k > 1)
      r.onPick = function()
        if k == 1 then UI.OpenPlans(false); return end
        local ok, back = TF.SwitchPlan(k)
        if ok then UI.OpenPlans(false); UI.Refresh(); UI.Note(TF.PlanName() .. " is on your trees." .. TF.SettledText(back), nil, back and 12 or nil); if back then UI.SettledCard(back) end end
      end
      r.onDelete = function() local gone = e.name; if TF.DeletePlan(k) then self:Fill(); UI.Refresh(); UI.Note(gone .. " deleted.") end end
      Tip(r, e.name, k == 1 and "The open plan. Apply and the level-up card follow it." or "Click to put it on your trees. The open plan waits here for you, as it is.")
      r:Show()
    end
    for k = #list + 1, #self.rows do self.rows[k]:Hide() end
    local y = 26 + #list * ROW + 10
    self.name:ClearAllPoints(); self.name:SetPoint("TOPLEFT", 14, -y)
    self:SetHeight(y + 20 + 14)
    local room = #list < 8
    self.new:SetEnabled(room); self.copy:SetEnabled(room)
  end
  return c
end
function UI.OpenPlans(show)
  if not head or not head.planBtn then return end
  if show == nil then show = not (head.planCard and head.planCard:IsShown()) end
  if show and not head.planCard then head.planCard = UI.MakePlanCard(); UI.planCard = head.planCard end
  if not head.planCard then return end
  if show then head.planCard:Fill(); head.planCard.name:SetText("") end
  head.planCard:SetShown(show)
end

-- the emblem pulses when a talent is maxed: the site's epulse
function UI.EmblemPulse()
  if not (head and head.book and head.book.CreateAnimationGroup) then return end   -- no portrait on this client's window: nothing to pulse (a Hunter's error on 0.33.0)
  local h = head; if not h then return end
  if not h.bookPulse then
    local ag = h.book:CreateAnimationGroup()
    local s1 = ag:CreateAnimation("Scale"); s1:SetDuration(0.3); s1:SetOrder(1); s1:SetSmoothing("OUT"); if s1.SetScaleFrom then s1:SetScaleFrom(0.72, 0.72); s1:SetScaleTo(1.08, 1.08) else s1:SetScale(1.08, 1.08) end; if s1.SetOrigin then s1:SetOrigin("CENTER", 0, 0) end
    local s2 = ag:CreateAnimation("Scale"); s2:SetDuration(0.25); s2:SetOrder(2); s2:SetSmoothing("IN_OUT"); if s2.SetScaleFrom then s2:SetScaleFrom(1.08, 1.08); s2:SetScaleTo(1, 1) else s2:SetScale(1 / 1.08, 1 / 1.08) end; if s2.SetOrigin then s2:SetOrigin("CENTER", 0, 0) end
    h.bookPulse = ag
  end
  h.bookPulse:Stop(); h.bookPulse:Play()
end

local function MakeFoot()
  local f = CreateFrame("Frame", nil, F)
  f:SetPoint("BOTTOMLEFT", MARGIN, MARGIN); f:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN); f:SetHeight(FOOT_H)
  f.status = Text(f, 13, C.ink2); f.status:SetPoint("TOPLEFT", 0, -76); f.status:SetPoint("TOPRIGHT", -200, -76); f.status:SetJustifyH("LEFT"); f.status:SetWordWrap(false)
  f.statusY = -76
  journey = MakeJourney(f)
  -- a note can carry one or two small actions (Undo, Learn it); they sit where the count sits, for a few seconds
  f.act1 = Button(f, "Undo", "auto", 20, function() local fn = f.fn1; UI.ClearNote(); if fn then fn() end end, true); f.act1:Fit(); f.act1:SetPoint("TOPRIGHT", 0, -73); f.act1:Hide()
  f.act2 = Button(f, "Undo", "auto", 20, function() local fn = f.fn2; UI.ClearNote(); if fn then fn() end end, true); f.act2:Fit(); f.act2:SetPoint("RIGHT", f.act1, "LEFT", -8, 0); f.act2:Hide()
  f.showAll = Button(f, "Show all", "auto", 20, function() TF.SetLevel(60) end); f.showAll:SetPoint("TOPRIGHT", 0, -73); f.showAll:Hide()
  Tip(f.showAll, "Back to the whole plan", "Looks at your build at level 60 again, with every planned point on the trees.")
  -- the doing buttons, a breath, the plan buttons; on the right the way out to the site
  f.apply = Button(f, "Apply next point", "auto", 24, function() UI.ApplyNext() end, true); f.apply.minW = 144; f.apply:Fit(); f.apply:SetPoint("BOTTOMLEFT", 0, 0)
  f.apply:SetMotionScriptsWhileDisabled(true)
  f.apply:SetScript("OnEnter", function(self) TipBegin(self); GameTooltip:SetText("Apply the next planned point", 1, 0.82, 0); GameTooltip:AddLine(UI.applyWhy or "Places the next point of your plan on your character. Until you press this, nothing on your character changes.", 0.9, 0.9, 0.9, true); TipEnd(self) end)
  f.apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.applyAll = Button(f, "Apply all", "auto", 24, function() UI.ApplyAll() end); f.applyAll:SetPoint("LEFT", f.apply, "RIGHT", 8, 0)
  f.applyAll:SetMotionScriptsWhileDisabled(true)
  f.applyAll:SetScript("OnEnter", function(self) TipBegin(self); GameTooltip:SetText("Place every point the plan can", 1, 0.82, 0); GameTooltip:AddLine(UI.applyWhy or "Goes down your leveling plan and places each unspent point in order. After a reset at the trainer this rebuilds the whole build in one click.", 0.9, 0.9, 0.9, true); TipEnd(self) end)
  f.applyAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.fromChar = Button(f, "From character", "auto", 24, function()
    local ok, err = TF.PlanFromGame()
    if ok then UI.Note("Your talents as the game has them, now in the plan.", { { label = "Undo", fn = function() TF.Undo() end } }) else UI.Note(err) end
  end); f.fromChar:SetPoint("LEFT", f.applyAll, "RIGHT", 8, 0)
  f.reset = Button(f, "Reset", "auto", 24, function()
    if TF.TotalPts(plan()) == 0 then UI.Note("The plan is already empty."); return end
    TF.Reset(); UI.Note("Plan cleared. Your character is untouched.", { { label = "Undo", fn = function() TF.Undo() end } })
  end); f.reset:SetPoint("LEFT", f.fromChar, "RIGHT", 8, 0)
  f.undo = Button(f, "Undo", "auto", 24, function()
    if not TF.undo then UI.Note("Nothing to undo. Undo brings the plan back after Reset, Load, From character or Keep it."); return end
    if TF.Undo() then UI.Note("The plan before is back.") end
  end); f.undo:SetPoint("LEFT", f.reset, "RIGHT", 8, 0); f.undo:SetMotionScriptsWhileDisabled(true)
  f.clear = Button(f, "Clear", "auto", 24, function() UI.ClearView() end); f.clear:SetPoint("LEFT", f.undo, "RIGHT", 8, 0)
  f.ghostClear = Button(f, "Stop", "auto", 20, function() TF.TrialBack() end); f.ghostClear:SetPoint("TOPRIGHT", 0, -73); f.ghostClear:Hide()
  f.trialKeep = Button(f, "Load it", "auto", 20, function() local n = TF.trial and TF.trial.name or "it"; TF.TrialKeep(); UI.Note("Loaded " .. n .. ".", { { label = "Undo", fn = function() TF.Undo() end } }) end); f.trialKeep:SetPoint("RIGHT", f.ghostClear, "LEFT", -8, 0); f.trialKeep:Hide()
  f.import = Button(f, "Import", "auto", 24, function() UI.OpenSheet("import") end); f.import:SetPoint("BOTTOMRIGHT", 0, 0); f.import:SetIcon("Interface\\Icons\\INV_Scroll_03")
  -- the row reads as three groups: doing (apply, plan), tools (settings, feedback), sharing (the site, share, import); a
  -- hairline stands between groups, eight pixels between neighbours inside one
  f.dividers = {}
  f.share = Button(f, "Share", "auto", 24, function() UI.OpenSheet("share") end); f.share:SetPoint("RIGHT", f.import, "LEFT", -8, 0)
  f.site = CreateFrame("Button", nil, f); f.site:SetSize(132, 24); f.site:SetPoint("RIGHT", f.share, "LEFT", -8, 0)
  f.site.book = Book(f.site, 18); f.site.book:SetPoint("LEFT", 2, 0)
  f.feedback = Button(f, "Feedback", "auto", 24, function() UI.SetTab("feedback") end); f.feedback:SetPoint("RIGHT", f.site, "LEFT", -8, 0)
  f.settings = Button(f, "Settings", "auto", 24, function() UI.OpenSettings() end); f.settings:SetPoint("RIGHT", f.feedback, "LEFT", -8, 0)
  Tip(f.settings, "Settings", "Reminders, hands-free options, the look, sounds, window size, which pages show.")
  Tip(f.feedback, "Say what would help", "A bug, a wish, a talent that reads wrong: it goes to the inbox of the person who builds this. Nothing leaves the game by itself; the note becomes a link you paste in a browser.")
  f.site.text = Text(f.site, 12, C.gold); f.site.text:SetPoint("LEFT", f.site.book, "RIGHT", 5, 0); f.site.text:SetJustifyH("LEFT"); f.site.text:SetText("talentsforever.com"); f.site.text:SetAlpha(0.95)
  f.site:SetScript("OnEnter", function(self)
    self.text:SetTextColor(rgb(C.gold)); self.text:SetAlpha(1)
    TipBegin(self); GameTooltip:SetText("talentsforever.com", 1, 0.82, 0)
    GameTooltip:AddLine("This planner is the in-game half of the site. Click for your build's link and a code your phone can read: the same build opens there, on any device. The game does not let an addon open a browser, so the link is copied, not clicked.", 0.9, 0.9, 0.9, true); TipEnd(self)
  end)
  f.site:SetScript("OnLeave", function(self) self.text:SetTextColor(rgb(C.gold)); self.text:SetAlpha(0.95); GameTooltip:Hide() end)
  f.site:SetScript("OnClick", function() Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); UI.OpenSheet("phone") end)
  Tip(f.reset, "Empty the plan", "Every point comes back. Nothing happens to your character, and Undo brings the plan back.")
  Tip(f.undo, "Undo", "Brings the plan back from before the last Reset, Load, From character or Keep it. Lit when there is something to bring back.")
  Tip(f.clear, "Back to a quiet window", "Takes a tried build's rings off, shows the whole plan again, closes the trainer or spellbook list, empties the search and goes to Home. Your plan and your character stay as they are.")
  Tip(f.fromChar, "Copy your character into the plan", "Reads the talents you really have, so you can plan the rest from here. Undo brings the old plan back.")
  Tip(f.share, "Share this build", "Opens the Builds page with this plan's link selected, ready for Ctrl+C. The same link the site makes.")
  Tip(f.import, "Load a build", "Opens the Builds page with the paste box ready for a talentsforever.com link or code.")
  Tip(f.ghostClear, "Stop", "Takes the rings off the trees. Your plan was never touched.")
  Tip(f.trialKeep, "Load it", "The tried build becomes your plan. Undo brings your old one back.")
  return f
end
-- the footer's buttons: one chain, eight pixels between each, the chain centred in the row, so every gap is the same
function UI.LayoutFootRow()
  if not foot then return end
  local row = { foot.apply, foot.applyAll, foot.fromChar, foot.reset, foot.undo, foot.clear, foot.settings, foot.feedback, foot.site, foot.share, foot.import }
  -- the site link takes only the room its words need
  if foot.site.text then foot.site:SetWidth(math.ceil((foot.site.text:GetStringWidth() or 100) + 18 + 5 + 6)) end
  local EDGE = 0
  local fw = foot:GetWidth() or (BASE_W - MARGIN * 2)
  -- eleven buttons: with the usual padding they run past the edge, so when the row is full each one pulls its
  -- padding in (16 to 10) and the short ones let go of the 80 floor. Roomier again when the row is not full.
  local function total() local t = 0; for _, b in ipairs(row) do t = t + (b:GetWidth() or 80) end; return t end
  local function refit(tight)
    for _, b in ipairs(row) do
      if b.Fit and b.minW then   -- the site link sizes itself to its words
        b.pad0 = b.pad0 or b.pad; b.minW0 = b.minW0 or b.minW
        b.pad = tight and 10 or b.pad0; b.minW = tight and math.min(b.minW0, 64) or b.minW0; b:Fit()
      end
    end
  end
  refit(false)
  if total() + 4 * (#row - 1) > fw then refit(true) end
  local sum = total()
  -- eight between neighbours; a wider font closes the gaps down to four before anything could touch
  local gap = math.max(4, math.min(8, math.floor((fw - sum) / (#row - 1))))
  local total = sum + gap * (#row - 1)
  local x = EDGE + math.max(0, math.floor((fw - total) / 2))
  for _, b in ipairs(row) do b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", foot, "BOTTOMLEFT", x, 0); x = x + (b:GetWidth() or 80) + gap end
end
-- the rail under the trees is for leveling: at 60 it stands down by itself until Settings says otherwise, and the
-- window gets shorter by its band
function UI.RailOn() local v = S().rail; if v == nil then return (UnitLevel("player") or 1) < 60 end; return v and true or false end
function UI.LayoutFoot()
  if not foot or not F then return end
  local on = UI.RailOn()
  local y = on and -76 or -4
  foot.statusY = y
  if journey then
    journey:SetShown(on); journey.hint:ClearAllPoints(); journey.hint:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, y)
    if not on then journey.hint:Hide() end
  end
  foot.status:ClearAllPoints(); foot.status:SetPoint("TOPLEFT", 0, y); foot.status:SetPoint("TOPRIGHT", -200, y)
  foot.showAll:ClearAllPoints(); foot.showAll:SetPoint("TOPRIGHT", 0, y + 3)
  foot.ghostClear:ClearAllPoints(); foot.ghostClear:SetPoint("TOPRIGHT", 0, y + 3)
  foot.act1:ClearAllPoints(); foot.act1:SetPoint("TOPRIGHT", 0, y + 3)
  foot:SetHeight(on and FOOT_H or (FOOT_H - UI.RAIL_H))
  F:SetHeight(BASE_H - (on and 0 or UI.RAIL_H))
  UI.LayoutFootRow()
end

-- ---------- settings, find, notes ----------
function UI.OpenSettings()
  if S().sideTab == "settings" then UI.SetTab(UI.lastTab or "plan") else UI.lastTab = S().sideTab; UI.SetTab("settings") end
end

-- find a talent by name: the tile lights up and its tooltip opens
function UI.Find(q)
  q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then TF.Print("/talents find <part of a talent name>"); return end
  UI.Show()
  if head and head.search then head.search:SetText(q) end
  for ti, tree in ipairs(classData().trees) do
    for i, t in ipairs(tree.talents) do
      if t.name:lower():find(q, 1, true) then
        local b = trees[ti] and trees[ti].tiles[i]
        if b then Land(b, true); UI.ShowTip(b) end
        TF.Print("%s: %s tree, row %d, %d/%d in the plan.", t.name, tree.name, t.row, plan().ranks[ti][i], t.max)
        return true
      end
    end
  end
  TF.Print("no %s talent called %s.", classData().name, q)
end

-- a note in the footer line: gold for a few seconds, with one or two small actions when there is something to undo
-- or accept. With the window open this is where every message goes; cards are for when it is closed.
function UI.ClearNote()
  if not foot then return end
  foot.noteUntil = nil; foot.fn1, foot.fn2 = nil, nil
  foot.act1:Hide(); foot.act2:Hide()
  foot.status:ClearAllPoints(); foot.status:SetPoint("TOPLEFT", 0, foot.statusY); foot.status:SetPoint("TOPRIGHT", -200, foot.statusY)
  if journey and journey:IsShown() then journey.hint:Show() end
  UI.Refresh()
end
function UI.Note(text, actions, secs)
  if not foot or not text then return end
  local a1, a2 = actions and actions[1], actions and actions[2]
  foot.fn1, foot.fn2 = a1 and a1.fn or nil, a2 and a2.fn or nil
  foot.act1:SetShown(a1 and true or false); foot.act2:SetShown(a2 and true or false)
  if a1 then foot.act1:SetText(a1.label) end
  if a2 then foot.act2:SetText(a2.label) end
  if journey then journey.hint:Hide() end
  foot.showAll:Hide(); foot.ghostClear:Hide(); foot.trialKeep:Hide()
  foot.status:ClearAllPoints(); foot.status:SetPoint("TOPLEFT", 0, foot.statusY); foot.status:SetPoint("TOPRIGHT", -((a2 and 190) or (a1 and 100) or 4), foot.statusY)
  foot.status:SetText(text); foot.status:SetTextColor(rgb(C.gold))
  local hold = secs or (a1 and 8 or 3.5)
  local stamp = GetTime() + hold
  foot.noteUntil = stamp
  C_Timer.After(hold + 0.05, function() if foot.noteUntil == stamp then UI.ClearNote() end end)
end

-- ---------- apply ----------
local function liveGate(ti, i)
  local live = TF.LiveRanks(plan().cls); if not live then return "no data" end
  local tmp = { cls = plan().cls, level = 60, ranks = live }
  return TF.Gate(tmp, ti, i)
end
function UI.ApplyNext()
  if applying then return end
  if not isOwnClass() then UI.Toast("This is a " .. classData().name .. " plan. Only your own class can be applied."); return end
  if not G.live then UI.Toast("The game has not answered about your talents yet."); return end
  if not G.CanApply() then UI.Toast("This client gives addons no way to place a point. The plan on the right shows what to take next in the talent window."); return end
  if G.Unspent() <= 0 then UI.Toast("No unspent talent points right now."); return end
  local list = TF.NextUp()
  for _, e in ipairs(list) do
    if not e.done and not liveGate(e.ti, e.i) then
      applying = true
      local ok, msg = G.Learn(e.ti, e.i)
      applying = false
      local b = trees[e.ti] and trees[e.ti].tiles[e.i]
      if ok then
        Sound("LOOT_WINDOW_COIN_SOUND")
        if b then Land(b, true) end
        UI.Toast(string.format("Learned %s (%d/%d), as planned for level %d.", msg, e.rank, classData().trees[e.ti].talents[e.i].max, e.level))
      else
        UI.Toast(msg or "The game did not take the point.")
      end
      return
    end
  end
  UI.Toast("Nothing in the plan can be placed right now: the points left need rows or talents you do not have yet.")
end
-- place every unspent point the plan can, one after another (after a reset at the trainer this rebuilds the whole build)
local applyingAll = false
function UI.ApplyAll()
  if applyingAll then return end
  if not (isOwnClass() and G.live and G.CanApply()) then UI.ApplyNext(); return end
  local placed, budget = 0, G.Unspent()
  if budget <= 0 then UI.Toast("No unspent talent points right now."); return end
  applyingAll = true
  -- stage every point the plan can place, in order, then apply them all with one commit (one cast, like the window's Apply)
  local lastMsg
  while G.Unspent() > 0 and placed < budget do
    local list = TF.NextUp(); local found
    for _, e in ipairs(list) do if not e.done and not liveGate(e.ti, e.i) then found = e; break end end
    if not found then break end
    local ok, msg = G.Learn(found.ti, found.i, true)
    if not ok then lastMsg = msg; break end
    placed = placed + 1
    local b = trees[found.ti] and trees[found.ti].tiles[found.i]
    if b then Land(b, true) end
  end
  applyingAll = false
  if placed == 0 then UI.Refresh(); UI.Toast(lastMsg or "Nothing in the plan can be placed right now: the points left need rows or talents you do not have yet."); return end
  local okC, msgC = G.Commit()
  UI.Refresh()
  if okC then Sound("LOOT_WINDOW_COIN_SOUND"); UI.Toast(string.format("Applying %d point%s from the plan. The game takes a few seconds to make them stick.", placed, placed == 1 and "" or "s"))
  else UI.Toast("Staged " .. placed .. " but the game did not apply them: " .. tostring(msgC)) end
end

-- ---------- refresh ----------
local function statusLine()
  local p = plan()
  if TF.lastSettled and TF.lastSettled.cls == p.cls then return string.format("Older than the trees: %d point%s came back to you, ringed in orange. Hover one to see why.", TF.lastSettled.n, TF.lastSettled.n == 1 and "" or "s") end
  if TF.trial and TF.trial.cls == p.cls then
    local onlyPlan, onlyTrial, shared = TF.TrialDiff()
    return string.format("Trying %s: its talents are ringed on the trees, next to yours. %d points you share, %d only theirs, %d only yours.", TF.trial.name, shared, onlyTrial, onlyPlan)
  end
  if not isOwnClass() then return string.format("Planning a %s on your %s. Nothing here touches your character.", classData().name, D.classes[TF.PlayerClass()] and D.classes[TF.PlayerClass()].name or "?") end
  if not G.live then return "Reading your talents from the game..." end
  local missing, extra = TF.Diff(p)
  local pts = G.points or {}
  local s
  if missing == 0 and extra == 0 then s = "Your character matches the plan."
  else
    local parts = {}
    if missing > 0 then parts[#parts + 1] = string.format("%d point%s to place", missing, missing == 1 and "" or "s") end
    if extra > 0 then parts[#parts + 1] = string.format("%d on your character the plan does not have", extra) end
    if (pts.unspent or 0) > 0 then parts[#parts + 1] = string.format("%d free now", pts.unspent) end
    s = table.concat(parts, ", ") .. "."
  end
  return s
end
function UI.Refresh()
  if not F or not F:IsShown() then return end
  local p = plan(); local cd = classData()
  local cr, cg, cb = TF.ClassColor(p.cls)
  local view, partial = TF.ViewRanks(p)
  local vp = partial and { cls = p.cls, level = p.level, ranks = view } or p
  local total, shown, pool = TF.TotalPts(p), TF.TotalPts(vp), TF.Pool(p)
  -- header
  if head.classDrop then
    if head.dropCls ~= p.cls then head.dropCls = p.cls; head.classDrop:GenerateMenu() end   -- the dropdown's words follow the class
  else head.classBtn:SetText(cd.name); if head.classBtn.label then head.classBtn.label:SetTextColor(cr, cg, cb) end end
  SetClassIcon(head.classIcon, p.cls)
  local lead, best = 1, -1
  for ti = 1, #cd.trees do local n = TF.TreePts(vp, ti); if n > best then best, lead = n, ti end end
  if shown == 0 then head.sub:SetText("Click a talent to start.")
  else head.sub:SetText(string.format("%s %s, %d / %d / %d", cd.trees[lead].name, cd.name, TF.TreePts(vp, 1), TF.TreePts(vp, 2), TF.TreePts(vp, 3))) end
  if head.planBtn then
    if TF.PlanNamed(p.cls) then head.sub:SetText(TF.PlanName() .. ": " .. head.sub:GetText()) end   -- the chip says what it does; the name goes on the line beside it
    if head.planCard and head.planCard:IsShown() then head.planCard:Fill() end
  end
  head.lv:SetText(p.level)
  Gradient(head.rule, "HORIZONTAL", cr, cg, cb, 0.7, 0.78, 0.61, 0.10, 0.04)
  local ptxt = head.gameBox and tostring(math.max(0, pool - shown)) or string.format("%d / %d", shown, pool)
  if head.points:GetText() ~= ptxt then
    head.points:SetText(ptxt)
    if not head.points.pop then local ag = head.points:CreateAnimationGroup(); local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0.4); a:SetToAlpha(1); a:SetDuration(0.18); a:SetSmoothing("OUT"); head.points.pop = ag end
    head.points.pop:Stop(); head.points.pop:Play()
  end
  if head.gameBox then
    head.pointsLabel:SetText(string.format("%d / %d", shown, pool))
    head.placedLabel:SetText(partial and string.format("%d MORE LATER", total - shown) or "PLACED")
  elseif partial then head.pointsLabel:SetText(string.format("%d MORE LATER", total - shown))
  elseif shown >= pool then head.pointsLabel:SetText("POINTS, FULL")
  else head.pointsLabel:SetText(string.format("POINTS, %d LEFT", pool - shown)) end
  -- trees
  local live = isOwnClass() and TF.LiveRanks(p.cls)
  local marks, picks = S().marks, S().pickRates
  local hasGhost = (TF.trial and TF.trial.cls == p.cls) and true or false
  for ti, tree in ipairs(cd.trees) do
    local tp = trees[ti]
    local tpts = TF.TreePts(vp, ti)
    tp.pts:SetText(tpts)
    local maxRow = 1; for _, t in ipairs(tree.talents) do if t.row > maxRow then maxRow = t.row end end
    local need
    for row = 2, maxRow do if TF.Above(vp, ti, row) < (row - 1) * 5 then need = (row - 1) * 5 - TF.Above(vp, ti, row); break end end
    tp.rowNote:SetText(need and string.format("next row in %d", need) or "all rows open")
    if ti == lead and best > 0 then tp.pts:SetTextColor(cr, cg, cb); Gradient(tp.fill, "HORIZONTAL", cr * 0.6, cg * 0.6, cb * 0.6, 1, cr, cg, cb, 1)
    else tp.pts:SetTextColor(rgb(C.gold)); Gradient(tp.fill, "HORIZONTAL", 0.78, 0.61, 0.10, 1, 1, 0.82, 0, 1) end
    local fillTo = math.max(1, (TREE_W - 2) * tpts / 51)
    if tp.fillW ~= fillTo then
      local from = tp.fillW or 1; tp.fillW = fillTo
      Tween("fill" .. ti, 0.18, function(e) tp.fill:SetWidth(lerp(from, fillTo, e)); tp.fill:SetAlpha(math.min(1, (lerp(from, fillTo, e) - 1) / 6)) end, { ease = "out4" })
    end
    for i, t in ipairs(tree.talents) do
      local b = tp.tiles[i]; local r = vp.ranks[ti][i]; local st = TF.Status(vp, ti, i)
      local later = partial and p.ranks[ti][i] > r
      b.icon:SetTexture(IconFor(t))
      b.rank:SetText(r .. "/" .. t.max)
      local rc = st == "maxed" and C.gold or (st == "partial" and C.ink or (st == "avail" and C.ink2 or C.muted))
      b.rankColor = rc
      if not Motion.byKey["rank" .. tileKey(b)] then b.rank:SetTextColor(rgb(rc)) end
      b.icon:SetAlpha(1); b.slot:SetAlpha(1)
      if b.frame then
        local name = (st == "maxed" or st == "partial") and "yellow" or (st == "avail" and (TF.CanAdd(vp, ti, i) == nil and "green" or "gray") or "locked")
        Atlas(b.frame, "talents-node-square-" .. name); b.frame:SetAlpha(1)
        local dim = st == "locked"
        b.icon:SetDesaturated(dim); b.icon:SetVertexColor(dim and 0.45 or 1, dim and 0.45 or 1, dim and 0.45 or 1)
        if later and r == 0 then Atlas(b.frame, "talents-node-square-yellow"); b.frame:SetAlpha(0.45) end
      elseif st == "maxed" then b.ring:SetVertexColor(1, 0.82, 0.1, 1); b.icon:SetDesaturated(false); b.icon:SetVertexColor(1, 1, 1); b.rankEdge:SetColor(0.70, 0.55, 0.10, 1)
      elseif st == "partial" then b.ring:SetVertexColor(0.78, 0.61, 0.10, 0.95); b.icon:SetDesaturated(false); b.icon:SetVertexColor(1, 1, 1); b.rankEdge:SetColor(0.55, 0.43, 0.08, 1)
      elseif st == "avail" and LOOK() == "site" then b.ring:SetVertexColor(0.12, 1, 0, 0.9); b.icon:SetDesaturated(false); b.icon:SetVertexColor(1, 1, 1); b.rankEdge:SetColor(0.12, 0.85, 0, 1)
      elseif st == "avail" then b.ring:SetVertexColor(0.80, 0.74, 0.58, 0.8); b.icon:SetDesaturated(false); b.icon:SetVertexColor(1, 1, 1); b.rankEdge:SetColor(0.42, 0.40, 0.34, 1)
      else b.ring:SetVertexColor(0.32, 0.32, 0.32, 0.9); b.icon:SetDesaturated(true); b.icon:SetVertexColor(0.5, 0.5, 0.5); b.rankEdge:SetColor(0.22, 0.22, 0.22, 1) end
      -- a talent the plan reaches later, while an earlier level is being looked at: a quiet gold rim says it is coming
      if later and r == 0 and not b.frame then b.ring:SetVertexColor(0.78, 0.61, 0.10, 0.45); b.rankEdge:SetColor(0.45, 0.36, 0.08, 0.9) end
      b.pulse:Stop(); b.glow:SetAlpha((st == "maxed" and not b.frame) and 0.22 or 0)
      local lr = live and live[ti][i]
      if lr and lr > 0 and lr ~= r then b.live:SetText(lr); b.live:Show(); b.liveBg:Show() else b.live:Hide(); b.liveBg:Hide() end
      b.ghostRing:SetShown(hasGhost and TF.TrialRank(ti, i) > 0)
      local bk = (vp == p) and TF.SettledAt(ti, i) or nil
      b.backRing:SetShown(bk ~= nil); if bk then b.backTag:SetText(bk.pts .. " back"); b.backTag:Show() else b.backTag:Hide() end
      local sc = marks and STATUS_COLOR[t.classic]
      if sc then b.mark:SetVertexColor(sc[1], sc[2], sc[3], 0.95); b.mark:Show() else b.mark:Hide() end
      local pr = picks and pickRate(ti, i)
      if pr then b.pick:SetText(pr .. "%"); b.pick:Show(); b.pickBg:Show(); b.pick:SetTextColor(rgb(pr >= 50 and C.gold or (pr <= 10 and C.red or C.ink2))) else b.pick:Hide(); b.pickBg:Hide() end
      tp.vp = vp; Chain.Paint(ti, i)
    end
  end
  -- footer
  local st = statusLine()
  if partial then st = string.format("Your build at level %d. %d more point%s come later. ", p.level, total - shown, (total - shown) == 1 and "" or "s") .. st end
  if isOwnClass() and not TF.trial and not partial then
    local nl, spells = TF.NextTrainerLevel(p.cls, UnitLevel("player"))
    if nl and #spells > 0 then st = st .. string.format("  Trainer at %d: %s.", nl, (TF.SpellsSummary(spells, 3):gsub("%s*%(rank %d+%)", ""))) end
  end
  if not foot.noteUntil or GetTime() >= foot.noteUntil then
    foot.noteUntil = nil; if TF.lastSettled and TF.lastSettled.cls == p.cls then foot.status:SetTextColor(1, 0.69, 0.40) else foot.status:SetTextColor(rgb(C.ink2)) end; foot.status:SetText(st)
    local inset = (hasGhost and ((foot.ghostClear:GetWidth() or 100) + (foot.trialKeep:GetWidth() or 70) + 18) or 0) + (partial and ((foot.showAll:GetWidth() or 80) + 10) or 0)
    foot.status:ClearAllPoints(); foot.status:SetPoint("TOPLEFT", 0, foot.statusY); foot.status:SetPoint("TOPRIGHT", -math.max(inset, hasGhost and 0 or 200), foot.statusY)
    foot.showAll:SetShown(partial and true or false)
    foot.ghostClear:SetShown(hasGhost); foot.trialKeep:SetShown(hasGhost)
    -- they sit side by side when all apply: Back to mine at the edge, Keep it, then Show all
    foot.showAll:ClearAllPoints()
    if hasGhost then foot.showAll:SetPoint("RIGHT", foot.trialKeep, "LEFT", -8, 0) else foot.showAll:SetPoint("TOPRIGHT", 0, foot.statusY + 3) end
    if journey then journey.hint:SetShown(not partial and not hasGhost and journey:IsShown()) end
  end
  local missing = isOwnClass() and G.live and select(1, TF.Diff(p)) or 0
  local can = isOwnClass() and G.live and G.CanApply() and G.Unspent() > 0 and missing > 0
  if not isOwnClass() then UI.applyWhy = "This plan is for another class. Only your own class can be applied."
  elseif not G.live then UI.applyWhy = "Waiting for the game to answer about your talents."
  elseif not G.CanApply() then UI.applyWhy = "This client gives addons no way to place points."
  elseif UnitLevel("player") < TF.StartLevel() then UI.applyWhy = string.format("Talent points start at level %d. You are %d. Plan now, apply then.", TF.StartLevel(), UnitLevel("player"))
  elseif G.Unspent() <= 0 then UI.applyWhy = "No unspent talent points right now. The next one comes with your next level."
  elseif missing <= 0 then UI.applyWhy = "Your character already has every point the plan has."
  else UI.applyWhy = nil end
  foot.apply:SetEnabled(can and true or false)
  foot.undo:SetEnabled(TF.undo ~= nil)
  foot.applyAll:SetEnabled(can and true or false)
  foot.apply:SetText(G.Unspent() > 0 and string.format("Apply next (%d)", G.Unspent()) or "Apply next point")
  do local e = TF.WhyNext(p); local nt = e and cd.trees[e.ti].talents[e.i]; foot.apply:SetIcon(nt and IconFor(nt) or nil) end
  UI.LayoutFootRow()
  if foot.fromChar and foot.fromChar.SetIcon and foot.fromCharCls ~= p.cls then foot.fromCharCls = p.cls; foot.fromChar:SetIcon("Interface\\Icons\\ClassIcon_" .. cd.name) end
  local t = tabs[S().sideTab]
  if side:IsShown() and t and t.refresh then t.refresh() end
  DrawPath()
  RefreshJourney()
end

-- hover a level on the rail: the talents the plan gains by that level pulse gold on the trees, until the mouse leaves.
-- A look at what a click would bring, that goes away by itself.
function UI.LevelPeek(level)
  UI.peekLevel = level
  local p = plan(); local view = TF.ViewRanks(p)
  local start = TF.StartLevel(); local order = TF.FixOrder(p)
  local gain = {}
  if level then
    local n = math.min(#order, level - start + 1)
    for k = 1, n do local o = order[k]; local key = o[1] * 100 + o[2]; gain[key] = (gain[key] or 0) + 1 end
  end
  for ti, tp in ipairs(trees) do
    for i, b in ipairs(tp.tiles) do
      local more = level and gain[ti * 100 + i] and gain[ti * 100 + i] > ((view[ti] and view[ti][i]) or 0)
      if more then
        if not b.peek then
          b.peek = b:CreateTexture(nil, "OVERLAY", nil, 2); b.peek:SetTexture(MEDIA .. "ring.tga"); b.peek:SetSize(TILE + 18, TILE + 18); b.peek:SetPoint("CENTER"); b.peek:SetVertexColor(1, 0.82, 0)
          b.peekPulse = Pulse(b.peek, 0.3, 0.95, 0.7)
        end
        b.peek:Show(); b.peekPulse:Play()
      elseif b.peek then b.peekPulse:Stop(); b.peek:Hide() end
    end
  end
end

-- ---------- size, position and scale ----------
local function savePos()
  local s = S()
  s.pos = { left = F:GetLeft(), top = F:GetTop() }
end
local function placeWindow(dy)
  local s = S()
  F:ClearAllPoints()
  if s.pos and s.pos.left and s.pos.top then F:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.pos.left, s.pos.top + (dy or 0)) else F:SetPoint("CENTER", UIParent, "CENTER", 0, dy or 0) end
end
local function restorePos() placeWindow(0) end
function UI.Centre() S().pos = nil; restorePos() end
function UI.SetScale(scale)
  scale = math.min(1.6, math.max(0.5, scale))
  local left, top = F:GetLeft(), F:GetTop()
  local old = F:GetScale()
  F:SetScale(scale)
  if left and top then
    -- keep the top left corner where it was
    F:ClearAllPoints(); F:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
  end
  S().scale = scale
  savePos()
end
function UI.Layout()
  if pathLayer then pathLayer:EnableMouse(false) end
  local showSide = true
  F:SetSize(BASE_W + (showSide and (SIDE_W + GAP) or 0), BASE_H)
  for ti, tp in ipairs(trees) do tp:ClearAllPoints(); tp:SetPoint("TOPLEFT", F, "TOPLEFT", MARGIN + (ti - 1) * (TREE_W + GAP), -(TOP + HEAD_H + HEAD_GAP)) end
  LayoutStage()
  side:ClearAllPoints(); side:SetPoint("TOPLEFT", F, "TOPLEFT", MARGIN + 3 * (TREE_W + GAP), -(TOP + HEAD_H + HEAD_GAP))
  side:SetShown(showSide)
  if showSide then UI.SetTab(S().sideTab) end
  UI.Refresh()
end

-- the stage the three trees stand on: the game's own talent background, its thin bronze inner frame, the divider under
-- the headers and the two vertical dividers between the trees (ClassTalentsFrameTemplate's art, by name)
local stage, stageTop
function MakeStage()
  if not AtlasOK("Talents-Background-c60") then return end
  stage = CreateFrame("Frame", nil, F); stage:SetFrameLevel(F:GetFrameLevel() + 1); stage:EnableMouse(false)
  stage.bg = stage:CreateTexture(nil, "BACKGROUND"); Atlas(stage.bg, "Talents-Background-c60"); stage.bg:SetAllPoints()
  stage.art = stage:CreateTexture(nil, "BACKGROUND", nil, 1); stage.art:SetAllPoints(); stage.art:Hide()
  stage.shade = stage:CreateTexture(nil, "BACKGROUND", nil, 2); stage.shade:SetTexture(WHITE); stage.shade:SetAllPoints(); Gradient(stage.shade, "VERTICAL", 0, 0, 0, 0.35, 0, 0, 0, 0.05)
  stageTop = CreateFrame("Frame", nil, F); stageTop:SetFrameLevel(F:GetFrameLevel() + 7); stageTop:EnableMouse(false)
  stageTop.border = stageTop:CreateTexture(nil, "OVERLAY"); Atlas(stageTop.border, "Talents-inner-frame-c60"); stageTop.border:SetPoint("TOPLEFT", -2, 4); stageTop.border:SetPoint("BOTTOMRIGHT", 2, -4)
  -- the dividers live UNDER the trees (on the stage), like the game's: their shaded bands must never lie over a header
  stageTop.divL = stage:CreateTexture(nil, "BORDER"); Atlas(stageTop.divL, "Talents-divider-left-c60"); stageTop.divR = stage:CreateTexture(nil, "BORDER"); Atlas(stageTop.divR, "Talents-divider-right-c60")
  stageTop.vl = stage:CreateTexture(nil, "BORDER"); Atlas(stageTop.vl, "Talents-divider-vertical-c60"); stageTop.vr = stage:CreateTexture(nil, "BORDER"); Atlas(stageTop.vr, "Talents-divider-vertical-c60")
end
function LayoutStage()
  if not stage then return end
  local w, h = TREE_W * 3 + GAP * 2, TREE_H
  stage:ClearAllPoints(); stage:SetPoint("TOPLEFT", F, "TOPLEFT", MARGIN, -(TOP + HEAD_H + HEAD_GAP)); stage:SetSize(w, h)
  stageTop:ClearAllPoints(); stageTop:SetAllPoints(stage)
  -- the divider art is a line with a soft grey band above it; over a painting that band reads as a stripe behind the tree
  -- names, so only the lowest third of the art (the line and its glow) is shown
  local function lineOnly(tex, name)
    local ok, info = pcall(function() return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) end)
    if ok and info and info.file and info.leftTexCoord then
      local t, bt = info.topTexCoord, info.bottomTexCoord
      pcall(tex.SetTexture, tex, info.file); pcall(tex.SetTexCoord, tex, info.leftTexCoord, info.rightTexCoord, t + (bt - t) * 0.68, bt)
      return true
    end
  end
  local dh = 18
  if not stageTop.cropped then stageTop.cropped = true; if not lineOnly(stageTop.divL, "Talents-divider-left-c60") then dh = 12 end; lineOnly(stageTop.divR, "Talents-divider-right-c60") end
  stageTop.divL:ClearAllPoints(); stageTop.divL:SetSize(w / 2, dh); stageTop.divL:SetPoint("BOTTOMRIGHT", stageTop, "TOP", 0, -(TREE_HEAD + 8))
  stageTop.divR:ClearAllPoints(); stageTop.divR:SetSize(w / 2, dh); stageTop.divR:SetPoint("BOTTOMLEFT", stageTop, "TOP", 0, -(TREE_HEAD + 8))
  for k, v in ipairs({ stageTop.vl, stageTop.vr }) do
    v:ClearAllPoints(); v:SetSize(2, h - TREE_HEAD - 30); v:SetPoint("TOP", stageTop, "TOPLEFT", k * TREE_W + (k - 0.5) * GAP, -(TREE_HEAD + 16))
  end
  for _, tp in ipairs(trees) do tp:SetFrameLevel(F:GetFrameLevel() + 3) end
  -- the class painting: the game's own three-panel picture for this class, one panel behind each tree
  local c = D.classes[plan().cls]; local name = c and "talent-background-" .. c.name:lower()
  local shown = GAME_NODES and name and AtlasOK(name) and Atlas(stage.art, name)
  stageTop:SetShown(GAME_NODES and true or false)
  stage.art:SetShown(shown and true or false); stage.shade:SetShown(shown and true or false)
  for _, tp in ipairs(trees) do for _, t in ipairs(tp.art or {}) do t:SetShown(not shown) end; if tp.fade then tp.fade:SetShown(not shown) end; if tp.shade then tp.shade:SetAlpha(shown and 0 or 1) end end
end
local builtFor
local function BuildTrees()
  local cf = plan().cls
  if builtFor == cf then return end
  for _, tp in ipairs(trees) do tp:Hide() end
  trees = {}
  for ti, tree in ipairs(D.classes[cf].trees) do trees[ti] = MakeTree(ti, tree) end
  builtFor = cf
  UI.Layout()
end

-- ---------- share and import live in the Builds page; the old doors lead there ----------
-- the search: kept across refreshes, cleared by an empty box
local searchQ, searchHits, searchCls = nil, {}, nil
local function ApplySearch()
  for ti, tr in ipairs(trees) do for i, b in ipairs(tr.tiles) do
    if searchQ then local hit = false; for _, x in ipairs(searchHits) do if x.ti == ti and x.i == i then hit = true end end; b:SetAlpha(hit and 1 or 0.28) else b:SetAlpha(1) end
  end end
end
function UI.Search(q)
  q = (q or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #q < 2 then
    if searchQ then searchQ = nil; searchHits = {}; ApplySearch() end
    return 0
  end
  local hits = TF.SearchTalents(plan().cls, q)
  local was = searchQ
  searchQ, searchHits = q, hits
  ApplySearch()
  searchCls = plan().cls
  if was ~= q and #hits <= 8 then for _, x in ipairs(hits) do local b = trees[x.ti] and trees[x.ti].tiles[x.i]; if b then Land(b, true) end end end
  return #hits
end
function UI.SearchJump()
  local x = searchHits[1]; if not x then return false end
  local b = trees[x.ti] and trees[x.ti].tiles[x.i]; if not b then return false end
  Land(b, true); UI.ShowTip(b)
  return true
end
function UI.SearchState() return searchQ, searchHits end
do
  local base = UI.Refresh
  function UI.Refresh(...) base(...); if searchQ then if searchCls ~= plan().cls then UI.Search(searchQ) else ApplySearch() end end end
end
function UI.OpenSheet(key, rec)
  UI.SetTab("builds")
  local f = tabs.builds and tabs.builds.frame; if not f then return end
  if key == "import" then
    f.qrOn = false; tabs.builds.refresh(); f.paste:SetFocus()
    -- the Load a build box glows gold for a moment and the footer says what to do
    if not f.pasteGlow then f.pasteGlow = Edges(f, f.paste, "OVERLAY", 3) end
    Tween("import-glow", 2.2, function(e) local a = e >= 1 and 0 or (0.55 + 0.45 * math.sin(e * math.pi * 5)); f.pasteGlow:SetColor(1, 0.82, 0, a) end, { ease = "linear" })
    UI.Note("Paste a talentsforever.com link or a build code in the lit box, then Load.", nil, 8)
  elseif key == "phone" then f.qrOn = true; if f.pasteGlow then f.pasteGlow:SetColor(1, 0.82, 0, 0) end; tabs.builds.refresh()
  else f.shareRec = rec; tabs.builds.refresh(); f.link:SetFocus(); f.link:HighlightText() end
end

-- ---------- toasts ----------
local toast
-- where the card shows: 230 up from the bottom middle, unless it has been dragged, then where it was dropped (a Warlock
-- keeps hotbars there, 23 Sep). One place for the account and for every card: level-up, trainer, a build somebody sent.
function UI.PlaceToast(t)
  t:ClearAllPoints()
  local p = S().cardPos
  if p and p.x and p.y then t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y) else t:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230) end
end
function UI.ResetCard() S().cardPos = nil; if toast then UI.PlaceToast(toast) end end
local function MakeToast()
  local t = Frame("Frame", "TalentsForeverBookToast", UIParent)
  t:SetSize(460, 60); t:SetFrameStrata("DIALOG"); t:EnableMouse(true); t:SetClampedToScreen(true)
  UI.PlaceToast(t)
  t:SetMovable(true); t:RegisterForDrag("LeftButton")
  t:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end; self.until_ = nil end)
  t:SetScript("OnDragStop", function(self)
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    local x, y = self:GetCenter()
    if x and y then S().cardPos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }; UI.PlaceToast(self) end
    self.hideSoon(8)
  end)
  Card(t)
  t.book = Book(t, 26); t.book:SetPoint("TOPLEFT", 14, -14)
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(26, 26); t.icon:SetPoint("TOPLEFT", 14, -14); t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  t.text = Text(t, 13, C.ink); t.text:SetPoint("TOPLEFT", 52, -16); t.text:SetPoint("RIGHT", -30, 0); t.text:SetWordWrap(true); t.text:SetJustifyH("LEFT")
  t.learn = Button(t, "Learn it", "auto", 24, function() if t.fn1 then t.fn1() end; if t.fn2 then t.hideSoon(1.5) else t:Hide() end end); t.learn:SetPoint("BOTTOMRIGHT", -16, 14)
  t.open = Button(t, "Open plan", "auto", 24, function() if t.fn2 then t.fn2() end; t:Hide() end); t.open:SetPoint("RIGHT", t.learn, "LEFT", -8, 0)
  t.close = CloseX(t, 16); t.close:SetPoint("TOPRIGHT", -2, -2); t.close:SetScript("OnClick", function() t:Hide() end)
  local ag = t:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.16); a:SetSmoothing("OUT")
  local m = ag:CreateAnimation("Translation"); m:SetOffset(0, 8); m:SetDuration(0.16); m:SetSmoothing("OUT")
  t.inAG = ag
  t.hideSoon = function(secs) t.until_ = GetTime() + (secs or 6) end
  t:SetScript("OnUpdate", function(self) if self.until_ and GetTime() > self.until_ and not self:IsMouseOver() then self:Hide(); self.until_ = nil end end)
  t:Hide()
  return t
end
function UI.Toast(text, icon, withButtons, secs)
  -- with the window open the words go to its footer line; a card is for when it is closed
  if F and F:IsShown() then
    local acts
    if withButtons == true then acts = { { label = "Learn it", fn = UI.ApplyNext } } elseif type(withButtons) == "table" then acts = withButtons end
    UI.Note(text, acts, secs and math.min(secs, 12) or nil)
    return
  end
  UI.Card(text, icon, withButtons, secs)
end
-- the card for a build that settled: what came back, where the rings are, and the offer to fill it in (one click, Undo after)
function UI.SettledCard(back)
  local f, near = TF.Refit(TF.plan, back), TF.ClosestPopular(TF.plan)
  local c = D.classes[TF.plan.cls]
  local function ic(ti, i) return string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t", tostring(IconFor(c.trees[ti].talents[i]))) end
  local function list(a) if #a == 1 then return a[1] end; return table.concat(a, ", ", 1, #a - 1) .. " and " .. a[#a] end
  local L = { "|cffffd100This build is older than the trees.|r", string.format("%d point%s came back to you:", back.n, back.n == 1 and "" or "s") }
  for _, b in ipairs(back.list) do L[#L + 1] = string.format("|cffffb066•|r %s %s  |cffffb066%d back|r", ic(b.ti, b.i), b.name, b.pts) end
  L[#L + 1] = "|cffffb066Ringed in orange on the trees. Hover one to see why.|r"
  if f then
    L[#L + 1] = ""; L[#L + 1] = "|cffffd100Fill it in for me|r"
    for _, st in ipairs(f.steps) do for _, a in ipairs(st.adds) do
      L[#L + 1] = string.format("|cffffb066•|r %s %d in %s  |cff8a8a8a%s|r", ic(a.ti, a.i), a.n, c.trees[a.ti].talents[a.i].name, a.arrow and "the new arrow" or (a.rate and (a.rate .. "% take it") or ""))
    end end
    local backs = {}; for _, st in ipairs(f.steps) do backs[#backs + 1] = ic(st.b.ti, st.b.i) .. " " .. c.trees[st.b.ti].talents[st.b.i].name end
    L[#L + 1] = "|cffffb066•|r then " .. list(backs) .. (#backs == 1 and " goes" or " go") .. " back"
    for _, a in ipairs(f.extra or {}) do L[#L + 1] = string.format("|cffffb066•|r %s %d more in %s  |cff8a8a8a%d%% take it|r", ic(a.ti, a.i), a.n, c.trees[a.ti].talents[a.i].name, a.rate) end
    local tail = {}
    if f.left > 0 then tail[#tail + 1] = string.format("%d point%s yours%s.", f.left, f.left == 1 and " stays" or "s stay", f.noData and ", nothing in the pick rates to place it by" or "") end
    for _, x in ipairs(f.cant) do tail[#tail + 1] = string.format("%s %s.", c.trees[x.b.ti].talents[x.b.i].name, (x.need or 0) > 0 and string.format("needs %d more in %s first", x.need, c.trees[x.b.ti].name) or (x.short and string.format("needs %d more free point%s", x.short, x.short == 1 and "" or "s") or "can't come back yet")) end
    if #tail > 0 then L[#L + 1] = "|cff8a8a8a" .. table.concat(tail, " ") .. "|r" end
  end
  if near then L[#L + 1] = ""; L[#L + 1] = string.format("|cffffd100Closest build people make now:|r #%d %s, %d point%s apart.", near.b.rank, near.b.lead, near.d, near.d == 1 and "" or "s") end
  local acts = {}
  if f then acts[#acts + 1] = { label = "Fill it in for me", fn = function() if TF.ApplyRefit(f) then UI.Refresh(); UI.Note(TF.RefitDone(f), { { label = "Undo", fn = function() TF.Undo() end } }, 20) end end } end
  if near then acts[#acts + 1] = { label = "Closest build now", fn = function() local ok = TF.LoadCode(near.code); if ok then UI.Refresh(); UI.Note(string.format("Loaded the #%d %s build, %d point%s from the one you opened.", near.b.rank, near.b.lead, near.d, near.d == 1 and "" or "s"), { { label = "Undo", fn = function() TF.Undo() end } }, 12) end end } end
  UI.Card(table.concat(L, "\n"), nil, #acts > 0 and acts or nil, (f or near) and 45 or 30)
end
-- the card itself, window open or not: a build that settled against today's rules wants seeing, not a footer line
function UI.Card(text, icon, withButtons, secs)
  if not toast then toast = MakeToast() end
  toast.text:SetText(text)
  if icon then toast.icon:SetTexture(icon); toast.icon:Show(); toast.book:Hide() else toast.icon:Hide(); toast.book:Show() end
  local b1, b2
  if withButtons == true then b1 = { label = "Learn it", fn = UI.ApplyNext }; b2 = { label = "Open plan", fn = UI.Show }
  elseif type(withButtons) == "table" then b1, b2 = withButtons[1], withButtons[2] end
  toast.learn:SetShown(b1 and true or false); toast.open:SetShown(b2 and true or false)
  toast.fn1, toast.fn2 = nil, nil
  if b1 then toast.learn:SetText(b1.label); toast.fn1 = b1.fn end
  if b2 then toast.open:SetText(b2.label); toast.fn2 = b2.fn end
  -- the card is as tall as its words; with buttons they get a line of their own underneath
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")   -- colour codes and icon tags take no room on the line
  local th = math.max(16, toast.text:GetStringHeight() or 0, estHeight(plain, 460 - 52 - 30, 13))
  toast:SetHeight(16 + th + ((b1 or b2) and 46 or 16))
  toast:Show(); toast.inAG:Stop(); toast.inAG:Play(); toast.hideSoon(secs or (withButtons and 20 or 5))
end
local function Nudge(reason)
  if not S().levelUpNudge or not isOwnClass() then return false end
  if not G.live or G.Unspent() <= 0 then return false end
  local list = TF.NextUp()
  for _, e in ipairs(list) do
    if not e.done then
      local t = classData().trees[e.ti].talents[e.i]
      local gate = liveGate(e.ti, e.i)
      -- hands-free placing never opens a tree on its own: a point that would be the character's first in a tree, while
      -- they have points elsewhere, is asked about instead (a Warrior nine into Protection got an Arms point, 23 Sep)
      local newTree = false
      if not gate and S().autoApply then
        local live = TF.LiveRanks(plan().cls)
        if live then
          local here, all = 0, 0
          for a, tr in ipairs(live) do for _, r in ipairs(tr) do all = all + r; if a == e.ti then here = here + r end end end
          newTree = all > 0 and here == 0
        end
      end
      if not gate and S().autoApply and not newTree and G.CanApply() then
        local ok, name = G.Learn(e.ti, e.i)
        if ok then UI.Toast(string.format("%s: placed your point in %s (%d/%d, %s), as planned.", reason, name, e.rank, t.max, classData().trees[e.ti].name), IconFor(t), false, 12); Sound("LOOT_WINDOW_COIN_SOUND"); return true end
      end
      local _, why = TF.WhyNext(plan())
      local msg = not gate and string.format("%s: your plan takes %s (%d/%d) next.%s", reason, t.name, e.rank, t.max, why[1] and (" " .. why[1]) or "")
        or string.format("%s: the plan wants %s next, but it is not open yet (%s).", reason, t.name, gate)
      if newTree then msg = msg .. string.format(" It would be your first point in %s, so it waits for you.", classData().trees[e.ti].name) end
      local spells = TF.NewSpellsAt(plan().cls, UnitLevel("player"))
      if #spells > 0 then msg = msg .. " Trainer: " .. TF.SpellsSummary(spells, 2) .. "." end
      local acts = { (not gate and G.CanApply()) and { label = "Learn it", fn = UI.ApplyNext } or { label = "Open plan", fn = UI.Show } }
      if not (F and F:IsShown()) then acts[2] = { label = "Not again", fn = function() S().levelUpNudge = false; TF.Print("level-up reminders off. Settings, or /talents nudge, turns them back on.") end } end
      UI.Toast(msg, IconFor(t), acts, 25)
      Sound("IG_QUEST_LIST_OPEN")
      return true
    end
  end
end

-- the trainer, for real: what this character could learn now and has not. Once per level and place, so it never nags.
-- the six capitals by map id (Classic's uiMapIDs), and by English name for a client without C_Map
local CAPITAL = { [1453] = "Stormwind City", [1455] = "Ironforge", [1457] = "Darnassus", [1454] = "Orgrimmar", [1456] = "Thunder Bluff", [1458] = "Undercity",
                  ["Stormwind City"] = true, Ironforge = true, Darnassus = true, Orgrimmar = true, ["Thunder Bluff"] = true, Undercity = true }
-- the capital the player stands in, named the way the client names it (a German client says Sturmwind), or nil elsewhere.
-- The map id is asked first, so the zone text's language does not matter; the English zone name still counts without it.
function UI.CityHere(where)
  local id = C_Map and C_Map.GetBestMapForUnit and TF.Try("C_Map.GetBestMapForUnit", C_Map.GetBestMapForUnit, "player")
  if id and CAPITAL[id] then local info = C_Map.GetMapInfo and TF.Try("C_Map.GetMapInfo", C_Map.GetMapInfo, id); return (type(info) == "table" and info.name) or CAPITAL[id] end
  return (where and CAPITAL[where] == true) and where or nil
end
-- the same capital by its English name whatever the client's language: the key the no-trainer list is kept under
function UI.CityKey(where)
  local id = C_Map and C_Map.GetBestMapForUnit and TF.Try("C_Map.GetBestMapForUnit", C_Map.GetBestMapForUnit, "player")
  if id and CAPITAL[id] then return CAPITAL[id] end
  return (where and CAPITAL[where] == true) and where or nil
end
local toldTrainer = {}
local function TrainerAlert(where, force)
  if not S().trainerAlerts or not isOwnClass() then return end
  local owed = TF.OwedSpells(); if not owed or #owed == 0 then return end
  local city, cityKey = UI.CityHere(where), UI.CityKey(where)
  -- a capital with no trainer for this class gets no card (Forever's Thunder Bluff has no Warlock trainer, a Warlock at 24
  -- found, 2 Oct 2026); the card's Not here button teaches the rest, a class trainer window opened there unteaches it
  if cityKey and not force and TF.NoTrainer(cityKey, TF.PlayerClass()) then return end
  local key = (city or where or "") .. "@" .. tostring(UnitLevel("player"))
  if toldTrainer[key] and not force then return end
  -- only what the purse covers: a card about spells the character cannot pay for yet is a nag (a Druid at 16, 1 Oct 2026);
  -- the rest is one short line, and the card waits until something is affordable
  -- a Settings switch (purseOnly), offered on the card itself the first time it lists something the purse cannot cover
  local can, dear = TF.Affordable(owed)
  if S().purseOnly then
    if #can == 0 then UI.waitingGold = true; return end   -- the gold arriving in a capital brings the card (the MONEY hook below)
  else can = owed end
  UI.waitingGold = nil
  toldTrainer[key] = true
  local lead = city and string.format("You are in %s. ", city) or ""
  local ct = TF.OwedCostText(can)
  local more = ""
  if #dear > 0 then more = S().purseOnly and string.format(" %d more when you have the gold.", #dear) or string.format(" %d of %s cost more than you have.", #dear, #dear == 1 and "them" or "them") end
  local acts = { { label = "See the list", fn = function() UI.Show(); UI.SetTab("coach") end } }
  if not S().purseOnly and #dear > 0 then acts[2] = { label = "Only what I can afford", fn = function()
    S().purseOnly = true
    UI.Toast("From now on this card counts only what your gold covers and waits while nothing is. Settings, Trainer cards only for what you can afford, turns that off again.", nil, false, 10)
  end }
  elseif cityKey then acts[2] = { label = "Not here", fn = function()
    TF.SetNoTrainer(cityKey, TF.PlayerClass(), true)
    UI.Toast(string.format("Noted: no %s trainer in %s. No more cards here. Opening a class trainer here puts them back.", classData().name, city or cityKey), nil, false, 8)
  end } end
  UI.Toast(string.format("%s%d spell%s waiting at your trainer%s: %s.%s", lead, #can, #can == 1 and "" or "s", ct and (" (" .. ct .. ")") or "", TF.SpellsSummary(can, 3), more), IconFor({ icon = can[1].icon }), acts, 20)
end
UI.TrainerAlert = TrainerAlert
-- 0.32.1, once: a card at login says "Place points for me, no asking" went off with the update, and where it lives
function UI.UpgradeCard()
  if not S().autoApplyReset then return false end
  S().autoApplyReset = nil
  UI.Toast("This update switched off \"Place points for me, no asking\", so the level-up card asks before a point goes in. Settings turns it back on.", nil,
    { { label = "Settings", fn = function() UI.Show(); UI.SetTab("settings") end } }, 30)
  return true
end
function UI.SetStarter(on)
  local ok, why = TF.SetStarter(on)
  if not ok then UI.Note(why or "Could not start following."); if tabs.settings and tabs.settings.refresh then tabs.settings.refresh() end; return end
  if tabs.settings and tabs.settings.refresh then tabs.settings.refresh() end
end
TF.On("STARTER_CHANGED", function(on, b, why)
  if on and b then
    local c = D.classes[plan().cls]
    UI.Note(string.format("Following the #%d %s build. Each level, the card asks before a point goes in.", b.rank or 1, b.lead or (c and c.name) or ""), { { label = "Undo", fn = function() TF.SetStarter(false); TF.Undo() end } }, 12)
  elseif why == "edited" then UI.Note("You changed the plan, so it is yours now. Following is off.", nil, 8)
  end
  if F and F:IsShown() then UI.Refresh() end
end)

-- Train all, under the game's own trainer window, below its Train button. Buys every available spell this character
-- has not skipped, one after another, and says what it cost. Falls back to a card when the window has another name.
local trainBtn
local function TrainerFrame()
  for _, n in ipairs({ "ClassTrainerFrame", "TrainerFrame" }) do local f = _G[n]; if f and f.IsShown and f:IsShown() then return f end end
end
local function RefreshTrainButton()
  if trainBtn and S().trainAll == false then trainBtn:Hide(); return end
  if not trainBtn then return end
  local plan = TF.TrainerPlan()
  local n = #plan.rows
  trainBtn.plan = plan
  if plan.pet then trainBtn:Hide(); return end   -- Beast Training: the pet's window, nothing of ours on it
  trainBtn:SetText(TF.trainer.queue and "Training..." or (n > 0 and string.format("Train all (%d, %s)", n, TF.Money(plan.cost)) or "Train all"))
  if trainBtn.Fit then trainBtn:Fit() end
  trainBtn:SetEnabled(n > 0 and not TF.trainer.queue)
end
local function TrainTip()
  local plan = trainBtn and trainBtn.plan; if not plan then return end
  GameTooltip:SetOwner(trainBtn, "ANCHOR_RIGHT")
  GameTooltip:SetText("Train all", 1, 0.82, 0)
  if #plan.rows == 0 then GameTooltip:AddLine("Nothing here you want that you can afford.", 0.74, 0.74, 0.74, true)
  else
    for _, r in ipairs(plan.rows) do GameTooltip:AddDoubleLine(r.name, TF.Money(r.cost or 0), 1, 1, 1, 0.74, 0.74, 0.74) end
    GameTooltip:AddDoubleLine(" ", TF.Money(plan.cost), 1, 1, 1, 1, 0.82, 0)
  end
  if plan.skipped > 0 then GameTooltip:AddLine(string.format("%d skipped on the Coach page, left alone.", plan.skipped), 0.54, 0.54, 0.54, true) end
  if plan.short > 0 then GameTooltip:AddLine(string.format("%d more than your money covers.", plan.short), 1, 0.3, 0.3, true) end
  GameTooltip:Show()
end
local function MakeTrainButton()
  local tf = TrainerFrame(); if not tf then return false end
  if trainBtn then if trainBtn:GetParent() ~= tf then trainBtn:SetParent(tf) end; trainBtn:Show(); return true end
  local go = function()
    local n = TF.TrainAll()
    if n == 0 then UI.Toast("Nothing at this trainer that you want and can afford.", nil, false, 6) else RefreshTrainButton() end
  end
  if S().trainAll == false then if trainBtn then trainBtn:Hide() end return true end   -- off in Settings: nothing on the trainer window, no card either
  trainBtn = Native("Button", "TalentsForeverBookTrainAll", tf, "UIPanelButtonTemplate")
  if trainBtn then trainBtn:SetSize(150, 22); trainBtn:SetScript("OnClick", go)
    if not trainBtn.Fit then function trainBtn:Fit() local fs = self:GetFontString(); if fs then self:SetWidth(math.max(150, math.ceil((fs:GetStringWidth() or 100) + 32))) end end end
  else trainBtn = Button(tf, "Train all", "auto", 22, go, true); trainBtn.minW = 150 end
  -- 0.34: under the window, not in its bottom bar. Left of the Train button it grew over the money display once the
  -- text carried a count and a price (two readers). Right-aligned under the frame it sits below the Train button and
  -- covers nothing of the game's.
  local anchor = _G.ClassTrainerTrainButton or (tf.TrainButton)
  if anchor then trainBtn:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8) else trainBtn:SetPoint("TOP", tf, "BOTTOM", 0, -4) end
  trainBtn:SetScript("OnEnter", TrainTip); trainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if trainBtn.SetMotionScriptsWhileDisabled then trainBtn:SetMotionScriptsWhileDisabled(true) end
  return true
end
TF.On("MONEY", function() if UI.waitingGold and S().purseOnly and UI.CityKey() then TrainerAlert(nil) end end)
TF.On("TRAINER", function(kind)
  -- a class trainer window open in a capital proves the class trains here: a Not here mark for it goes (the rows can
  -- arrive with TRAINER_UPDATE rather than TRAINER_SHOW, so both are looked at)
  if kind == "show" or kind == "update" then
    local ck = UI.CityKey()
    if ck and TF.NoTrainer(ck, TF.PlayerClass()) then
      local L = D.learn and D.learn[TF.PlayerClass()] or {}
      for _, r in ipairs(TF.TrainerRows()) do
        if r.key and L[r.key] then
          TF.SetNoTrainer(ck, TF.PlayerClass(), false)
          UI.Toast(string.format("There is a %s trainer in %s after all. The trainer cards are back here.", classData().name, UI.CityHere() or ck), nil, false, 8)
          break
        end
      end
    end
  end
  if kind == "show" then
    local placed = MakeTrainButton()
    RefreshTrainButton()
    if not placed then
      local plan = TF.TrainerPlan()
      if #plan.rows > 0 then UI.Toast(string.format("%d spell%s here that you want, %s.", #plan.rows, #plan.rows == 1 and "" or "s", TF.Money(plan.cost)), IconFor({ icon = (TF.OwedSpells() or {})[1] and (TF.OwedSpells())[1].icon }), { { label = "Train all", fn = function() TF.TrainAll() end } }, 30) end
    end
  elseif kind == "update" then RefreshTrainButton()
  elseif kind == "closed" then if trainBtn then trainBtn:Hide() end end
end)
TF.On("TRAINED", function(bought, spent, short, blocked)
  if trainBtn then RefreshTrainButton() end
  if blocked then UI.Toast(bought > 0 and string.format("Trained %d, then the game stopped the addon here. The window's own Train button does the rest.", bought) or "The game does not let an addon train here. The window's own Train button still works.", nil, false, 8)
  elseif bought > 0 then Sound("LOOT_WINDOW_COIN_SOUND"); UI.Toast(string.format("Trained %d spell%s for %s.%s", bought, bought == 1 and "" or "s", TF.Money(spent), short > 0 and string.format(" %d more when you have the money.", short) or ""), nil, false, 8)
  elseif short > 0 then UI.Toast("Not enough money for any of them.", nil, false, 6) end
  if F and F:IsShown() and S().sideTab == "coach" then tabs.coach.refresh() end
end)
TF.On("SKIP_CHANGED", function() if trainBtn and trainBtn:IsShown() then RefreshTrainButton() end end)
TF.On("INSPECTED", function(p, cf, unit)
  local c = D.classes[cf]; local parts = {}
  for ti = 1, #p.ranks do parts[ti] = TF.TreePts(p, ti) end
  local who = p.who or "They"
  local label = string.format("%s's %s build", who, c and c.name or "")
  UI.Toast(string.format("%s: %s %s, %s. Try it on your trees or load it.", who, c and c.name or "", table.concat(parts, " / "), TF.TotalPts(p) == 0 and "no points yet" or string.format("%d points", TF.TotalPts(p))), IconFor({ icon = c and c.trees[1].icon }),
    { { label = "Try it", fn = function() TF.TryBuild(p, label); UI.Show() end }, { label = "Load it", fn = function() TF.Remember(); TF.SetPlan(p); UI.Show(); UI.Note("Loaded " .. label .. ".", { { label = "Undo", fn = function() TF.Undo() end } }) end } }, 30)
  Sound("IG_QUEST_LIST_OPEN")
end)
TF.On("INSPECT_FAILED", function() UI.Toast("The game gave no talents for them. Step closer and try again.", nil, false, 8) end)
TF.On("RESPEC", function(wasOn)
  if wasOn then UI.Toast("Your talents were reset, so hands-free placing is off: nothing gets spent behind your back. Turn it on again in Settings when your plan is right.", nil, false, 20); Sound("IG_QUEST_LIST_OPEN")
  else UI.Toast("Your talents were reset. Your plan is untouched; Apply next places it from the first point.", nil, false, 12) end
  if tabs.settings and tabs.settings.refresh then tabs.settings.refresh() end
end)

-- ---------- the frame ----------
local function MakeFrame()
  -- the game's own window: its metal edge, its title bar, the round portrait in the corner, its red X. The flat one is the
  -- dark glass the Transmogrify window has; the older stone one where that is missing; our own cover where neither is.
  ApplyLook()
  F = Native("Frame", "TalentsForeverBookFrame", UIParent, "PortraitFrameTemplate") or Native("Frame", "TalentsForeverBookFrame", UIParent, "PortraitFrameFlatTemplate")
  if F and F.SetTitle and F.GetPortrait and F.CloseButton then F.native = true else F = F or Frame("Frame", "TalentsForeverBookFrame", UIParent) end
  F:SetSize(BASE_W, BASE_H); F:SetPoint("CENTER"); F:SetFrameStrata("HIGH"); F:SetToplevel(true)
  F:SetMovable(true); F:EnableMouse(true); F:SetClampedToScreen(true)
  F:RegisterForDrag("LeftButton"); F:SetScript("OnDragStart", F.StartMoving); F:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
  local top = F:GetFrameLevel() + 510     -- the frame's edge art is drawn 500 levels up; what stands in the title bar stands above it
  if F.native then
    F:SetTitle("Talents Forever")
    -- the title in the site's own face: our own string in Cinzel Bold on top of the game's, which goes clear. Setting a
    -- font on the game's title string does not always take, so this never depends on it.
    local tt = F.TitleContainer and F.TitleContainer.TitleText
    if tt and tt.SetAlpha then pcall(tt.SetAlpha, tt, 0) end
    local host = F.TitleContainer or F
    F.tfTitle = host:CreateFontString(nil, "OVERLAY")
    F.tfTitle:SetFont((CINZEL:gsub("Cinzel%.ttf$", "Cinzel-Bold.ttf")), 16, "")
    F.tfTitle:SetTextColor(1, 0.84, 0.37); F.tfTitle:SetShadowOffset(1, -1); F.tfTitle:SetShadowColor(0, 0, 0, 0.9)
    F.tfTitle:SetText("Talents Forever")
    if tt then F.tfTitle:SetPoint("CENTER", tt, "CENTER", 0, 0) else F.tfTitle:SetPoint("TOP", F, "TOP", 0, -9) end
    local p = F:GetPortrait()
    local ok, r = pcall(p.SetTexture, p, MEDIA .. "book-round.tga")
    if not ok or r == false then p:SetTexture("Interface\\Icons\\INV_Misc_Book_09") end
    F.close = F.CloseButton
    F.close:SetScript("OnClick", function() UI.Hide() end)
    -- the close drawn as a gold X, the weight and size of the gear beside it, so the two read as one set (the frame's
    -- own exit art looked like a stranger in this title bar)
    pcall(function()
      F.close:SetSize(18, 18); F.close:ClearAllPoints(); F.close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -7, -5)
      for _, k in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture" }) do if F.close[k] then pcall(F.close[k], F.close, "") end end
      for _, r in ipairs({ F.close:GetRegions() }) do if r.SetAlpha and r ~= F.close.tfA then pcall(r.SetAlpha, r, 0) end end
      F.close.tfA = F.close:CreateTexture(nil, "OVERLAY"); F.close.tfA:SetTexture(WHITE); F.close.tfA:SetSize(16, 2); F.close.tfA:SetPoint("CENTER"); F.close.tfA:SetRotation(math.rad(45))
      F.close.tfB = F.close:CreateTexture(nil, "OVERLAY"); F.close.tfB:SetTexture(WHITE); F.close.tfB:SetSize(16, 2); F.close.tfB:SetPoint("CENTER"); F.close.tfB:SetRotation(math.rad(-45))
      local function paint(hot) local a = hot and 1 or 0.8; F.close.tfA:SetVertexColor(1, 0.82, 0, a); F.close.tfB:SetVertexColor(1, 0.82, 0, a) end
      paint(false)
      F.close:HookScript("OnEnter", function() paint(true) end); F.close:HookScript("OnLeave", function() paint(false) end)
    end)
  else
    Skin(F, 64)
    F.medal = CreateFrame("Frame", nil, F); F.medal:SetSize(60, 60); F.medal:SetPoint("TOPLEFT", -14, 14); F.medal:SetFrameLevel(F:GetFrameLevel() + 14)
    if LOOK() == "site" then F.medal:SetSize(40, 40); F.medal:ClearAllPoints(); F.medal:SetPoint("TOPLEFT", 10, -4) end
    F.medal.halo = F.medal:CreateTexture(nil, "BACKGROUND"); F.medal.halo:SetTexture(SkinPath() .. "disc.png"); F.medal.halo:SetPoint("CENTER"); F.medal.halo:SetSize(64, 64)
    F.medal.book = Book(F.medal, LOOK() == "site" and 30 or 52); F.medal.book:SetPoint("CENTER", 0, 0)
    if LOOK() == "site" then F.medal.halo:SetSize(40, 40) elseif AtlasOK("Talents-Main-Ring-c60") then F.medal.ring = F.medal:CreateTexture(nil, "OVERLAY"); Atlas(F.medal.ring, "Talents-Main-Ring-c60", 76, 76); F.medal.ring:SetPoint("CENTER", 0, 0) end
    F.titleText = Text(F, LOOK() == "site" and 15 or 16, C.gold, true); F.titleText:SetFont((CINZEL:gsub("Cinzel%.ttf$", "Cinzel-Bold.ttf")), 16, ""); F.titleText:SetShadowOffset(1, -1); F.titleText:SetShadowColor(0, 0, 0, 0.9); if LOOK() == "site" then F.titleText:SetPoint("TOPLEFT", 58, -8); F.titleText:SetJustifyH("LEFT") else F.titleText:SetPoint("TOP", 0, -9) end; F.titleText:SetText("Talents Forever"); F.titleText:SetShadowColor(0, 0, 0, 1); F.titleText:SetShadowOffset(1, -1)
    if LOOK() == "site" then F.subText = Text(F, 10, C.muted); F.subText:SetPoint("TOPLEFT", 58, -27); F.subText:SetText("WoW Forever talent calculator, in game"); F.titleRuleY = -(TOP - 2) end
    F.titleRule = F:CreateTexture(nil, "BORDER", nil, 2); F.titleRule:SetTexture(WHITE); F.titleRule:SetPoint("TOPLEFT", 12, -(TOP - 4)); F.titleRule:SetPoint("TOPRIGHT", -12, -(TOP - 4)); if LOOK() == "site" then F.titleRule:SetVertexColor(0.23, 0.23, 0.23, 1) end; onePixel(F.titleRule, true); F.titleRule:SetVertexColor(0.61, 0.46, 0.18, 0.55)
    F.close = CreateFrame("Button", nil, F); F.close:SetSize(18, 18); F.close:SetPoint("TOPRIGHT", -9, -7); F.close:SetFrameLevel(F:GetFrameLevel() + 12); F.close:SetScript("OnClick", function() UI.Hide() end)
    F.close.tfA = F.close:CreateTexture(nil, "OVERLAY"); F.close.tfA:SetTexture(WHITE); F.close.tfA:SetSize(16, 2); F.close.tfA:SetPoint("CENTER"); F.close.tfA:SetRotation(math.rad(45))
    F.close.tfB = F.close:CreateTexture(nil, "OVERLAY"); F.close.tfB:SetTexture(WHITE); F.close.tfB:SetSize(16, 2); F.close.tfB:SetPoint("CENTER"); F.close.tfB:SetRotation(math.rad(-45))
    local function paintX(hot) local a = hot and 1 or 0.8; F.close.tfA:SetVertexColor(1, 0.82, 0, a); F.close.tfB:SetVertexColor(1, 0.82, 0, a) end
    paintX(false); F.close:SetScript("OnEnter", function() paintX(true) end); F.close:SetScript("OnLeave", function() paintX(false) end)
    top = F:GetFrameLevel() + 12
  end
  -- settings: the game's small gold cog, in the title bar beside the X
  F.gear = CreateFrame("Button", nil, F); F.gear:SetSize(16, 16); F.gear:SetPoint("RIGHT", F.close, "LEFT", -6, 0); F.gear:SetFrameLevel(top)
  F.gear.icon = F.gear:CreateTexture(nil, "ARTWORK"); F.gear.icon:SetAllPoints()
  local okc, rc = pcall(F.gear.icon.SetTexture, F.gear.icon, "Interface\\Buttons\\UI-OptionsButton")
  if not okc or rc == false then F.gear.icon:SetTexture("Interface\\Icons\\Trade_Engineering"); F.gear.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  F.gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  function F.gear:Paint(hot) self.icon:SetVertexColor(1, 1, 1, 1); self.icon:SetDesaturated(false); self.icon:SetAlpha((hot or self.on) and 1 or 0.8) end
  F.gear:Paint(false)
  F.gear:SetScript("OnEnter", function(self) self:Paint(true); TipBegin(self); GameTooltip:SetText("Settings", 1, 0.82, 0); GameTooltip:AddLine("Reminders, hands-free options, the look, sounds, window size, which pages show.", 0.9, 0.9, 0.9, true); TipEnd(self) end)
  F.gear:SetScript("OnLeave", function(self) self:Paint(self.on); GameTooltip:Hide() end)
  F.gear:SetScript("OnClick", function() UI.OpenSettings() end)
  Tip(F.close, "Close", "Escape works too.")
  -- ctrl and the wheel scale the whole window
  F:EnableMouseWheel(true)
  F:SetScript("OnMouseWheel", function(_, d) if IsControlKeyDown and IsControlKeyDown() then UI.SetScale((F:GetScale() or 1) + (d > 0 and 0.05 or -0.05)) end end)
  -- the bottom corners: a small gold flourish in each that drags to scale the whole window; the corner across stays put
  local OPP = { BOTTOMRIGHT = "TOPLEFT", BOTTOMLEFT = "TOPRIGHT" }
  local function cornerAt(which)
    local es = F:GetEffectiveScale()
    local x = which:find("LEFT") and F:GetLeft() or F:GetRight()
    local y = which:find("TOP") and F:GetTop() or F:GetBottom()
    return (x or 0) * es, (y or 0) * es
  end
  F.grips = {}
  -- the left one is the right one mirrored, so both point out into their corner
  for _, g in ipairs({ { "BOTTOMRIGHT", -3, 3, false }, { "BOTTOMLEFT", 3, 3, true } }) do
    local which, dx, dy, mirror = g[1], g[2], g[3], g[4]
    local grip = CreateFrame("Button", nil, F)
    grip:SetSize(16, 16); grip:SetPoint(which, dx, dy); grip:SetFrameLevel(top + 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    if mirror then for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do if tex and tex.SetTexCoord then tex:SetTexCoord(1, 0, 0, 1) end end end
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function(self)
      local fixed = OPP[which]
      local fx, fy = cornerAt(fixed)
      local us = UIParent:GetEffectiveScale() or 1
      self:SetScript("OnUpdate", function()
        local cx, cy = GetCursorPosition()
        local w = math.max(200, math.abs(cx - fx)); local h = math.max(120, math.abs(cy - fy))
        local scale = math.min(1.6, math.max(0.5, math.max(w / (F:GetWidth() * us), h / (F:GetHeight() * us))))
        if math.abs(scale - F:GetScale()) > 0.005 then
          F:SetScale(scale); S().scale = scale; S().scaleSet = true
          local es = F:GetEffectiveScale()
          F:ClearAllPoints(); F:SetPoint(fixed, UIParent, "BOTTOMLEFT", fx / es, fy / es)
          if UI.OnScaled then UI.OnScaled() end
        end
      end)
    end)
    grip:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); savePos(); if tabs.settings and tabs.settings.refresh then tabs.settings.refresh() end end)
    Tip(grip, "Resize", "Drag a bottom corner to make the window bigger or smaller; the top stays put. Ctrl and the wheel work anywhere on it. Drag the title to move it. It remembers both.")
    F.grips[which] = grip
  end
  F.grip = F.grips.BOTTOMRIGHT
  pathLayer = CreateFrame("Frame", nil, F); pathLayer:SetPoint("TOPLEFT"); pathLayer:SetPoint("BOTTOMRIGHT"); pathLayer:SetFrameLevel(F:GetFrameLevel() + 12)
  MakeStage(); head = MakeHead(); foot = MakeFoot(); side = MakeSide(); UI.sideFrame = side; F.foot = foot
  UI.LayoutFoot()
  tinsert(UISpecialFrames, "TalentsForeverBookFrame")
  F:SetScript("OnHide", function() Sound("IG_MAINMENU_CLOSE"); for _, s in pairs(sheets) do s:Hide() end; if UI.drawer then UI.drawer:Hide() end; UI.OpenPlans(false); pathLayer:SetScript("OnUpdate", nil) end)
  F:Hide()
  F:SetScale(S().scale or 1)
  restorePos()
end
-- the trainer's list as a drawer off the window's right edge (the left when the screen ends there): what you can
-- learn now with its price, what comes later and at what level, what is already in your book, the way the trainer
-- lays it out. Opened from Home's strip. Right click a row to skip it, like the Coach page.
local function MakeDrawer()
  local d = Frame("Frame", "TalentsForeverBookTrainer", F); d:SetSize(SIDE_W, TREE_H + TABS_H); d:SetFrameLevel(F:GetFrameLevel() + 2)
  d.inset = Native("Frame", nil, d, "InsetFrameTemplate")
  if d.inset then d.inset:SetPoint("TOPLEFT", 0, -TABS_H); d.inset:SetPoint("BOTTOMRIGHT", 0, 0); if d.inset.Bg then d.inset.Bg:SetVertexColor(0.30, 0.29, 0.27) end
  else
    d.bg = Solid(d, "BACKGROUND", C.bg, 0.94); d.bg:SetPoint("TOPLEFT", 0, -TABS_H); d.bg:SetPoint("BOTTOMRIGHT", 0, 0)
    d.edge = Edges(d, d, "BORDER", 0); d.edge:SetColor(0.47, 0.36, 0.14, 0.8)
  end
  -- the strip the tab stands in is a bar of its own, with a drag mark: the list moves by it
  d.top = Solid(d, "BACKGROUND", C.bg, 0.94); d.top:SetPoint("TOPLEFT", 0, 0); d.top:SetPoint("TOPRIGHT", 0, 0); d.top:SetHeight(TABS_H)
  d.topEdge = Edges(d, d.top, "BORDER", 0); d.topEdge:SetColor(0.47, 0.36, 0.14, 0.8)
  d.grip = CreateFrame("Frame", nil, d); d.grip:SetSize(22, 12); d.grip:SetPoint("TOP", d, "TOP", 0, -6)
  for k = 0, 2 do local bar = d.grip:CreateTexture(nil, "ARTWORK"); bar:SetTexture(WHITE); bar:SetSize(18, 2); bar:SetPoint("TOP", 0, -k * 4); bar:SetVertexColor(1, 0.82, 0, 0.55) end
  d.grip:EnableMouse(true); d.grip:SetScript("OnEnter", function(self) TipBegin(self); GameTooltip:SetText("Drag to move the list", 1, 0.82, 0); GameTooltip:AddLine("Anywhere you like. Snap back puts it beside the window again.", 0.9, 0.9, 0.9, true); TipEnd(self, "drawer") end)
  d.grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.grip:RegisterForDrag("LeftButton"); d.grip:SetScript("OnDragStart", function() if d.StartMoving then d:StartMoving() end; d.loose = true; d:SideWord() end); d.grip:SetScript("OnDragStop", function() if d.StopMovingOrSizing then d:StopMovingOrSizing() end end)
  d.tab = MakeTab(d, "Trainer", function() end, function() return true end); d.tab:SetPoint("BOTTOMLEFT", d, "TOPLEFT", 4, -TABS_H); d.tab:SetSelected(true)
  d.close = CloseX(d, 20); d.close:SetPoint("TOPRIGHT", -4, -(TABS_H + 4)); d.close:SetScript("OnClick", function() d:Hide() end)
  -- the list sits beside the window, on the side the player picks; dragged, it comes loose and stays where it is dropped
  d:SetMovable(true); d:EnableMouse(true); d:SetClampedToScreen(true); d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end; self.loose = true; self:SideWord() end)
  d:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
  d.side = Button(d, "Move left", "auto", 20, function()
    if d.loose then d.loose = false else S().drawerSide = d.onLeft and "right" or "left" end
    UI.OpenTrainer(false, d.mode)
  end); d.side:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -3)
  function d:SideWord() self.side:SetText(self.loose and "Snap back" or (self.onLeft and "Move right" or "Move left")); if self.side.Fit then self.side:Fit() end end
  Tip(d.side, "Where the list sits", "Moves the list to the other side of the window. Drag the list by its edge to put it anywhere; Snap back sets it beside the window again.")
  d.head = Section(d, "AT THE TRAINER", -(TABS_H + 12), 36); Font(d.head.text, 12, true); d.head.text:SetTextColor(1, 1, 1)
  d.cost = Text(d, 12, C.ink2); d.cost:SetPoint("TOPLEFT", 12, -(TABS_H + 30)); d.cost:SetPoint("TOPRIGHT", -28, -(TABS_H + 30)); d.cost:SetJustifyH("LEFT"); d.cost:SetWordWrap(true)
  d.scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate"); d.scroll:SetPoint("TOPLEFT", PAD, -(TABS_H + 64)); d.scroll:SetPoint("BOTTOMRIGHT", -28, 10); Slim(d.scroll)
  d.body = CreateFrame("Frame", nil, d.scroll); d.body:SetSize(PAGE_W, 10); d.scroll:SetScrollChild(d.body)
  d.rows, d.heads = {}, {}
  local ROWH = 24
  local function Head(k)
    local h = d.heads[k]; if h then return h end
    h = Section(d.body, "", 0); h:ClearAllPoints(); d.heads[k] = h; return h
  end
  local function Row(k)
    local r = d.rows[k]; if r then return r end
    r = CreateFrame("Button", nil, d.body); r:SetSize(PAGE_W, ROWH)
    r.bg = Solid(r, "BACKGROUND", C.raised, 0.35); r.bg:SetPoint("TOPLEFT", 0, -1); r.bg:SetPoint("BOTTOMRIGHT", 0, 1)
    r:SetHighlightTexture(WHITE); r:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 6, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.name = Text(r, 12, C.ink); r.name:SetPoint("LEFT", 30, 0); r.name:SetPoint("RIGHT", -74, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.sub = Text(r, 11, C.muted); r.sub:SetPoint("BOTTOMLEFT", 36, 4); r.sub:SetPoint("RIGHT", -74, 0); r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false); r.sub:Hide()
    r.right = Text(r, 11, C.gold); r.right:SetPoint("RIGHT", -6, 0); r.right:SetJustifyH("RIGHT")
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(_, btn) if btn == "RightButton" and r.spell and r.spell.state == "now" then TF.SkipSpell(r.spell.name, r.spell.rank, not r.spell.skipped); d:Refresh() end end)
    r:SetScript("OnEnter", function()
      local sp = r.spell; if not sp then return end
      TipBegin(r)
      local shown = sp.id and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, sp.id)
      if not shown then GameTooltip:SetText(sp.name, 1, 0.82, 0) end
      -- how it scales with spell power, from the client's files (asked for from inside the addon, 23 and 24 Sep)
      local co = TF.Coef(sp.id); if co then GameTooltip:AddLine("Scales with " .. co .. ".", 0.62, 0.62, 0.62, true) end
      if sp.state == "now" then GameTooltip:AddLine(string.format("The trainer sells this now%s.%s", sp.cost and (" for " .. TF.Money(sp.cost)) or "", sp.portal and " A portal trainer, not the class trainer." or ""), 0.74, 0.74, 0.74, true); GameTooltip:AddLine(sp.skipped and "Skipped: out of the reminders. Right click puts it back." or "Right click skips it, out of the reminders.", 0.54, 0.54, 0.54, true)
      elseif sp.state == "later" then GameTooltip:AddLine(string.format("From level %d.", sp.level), 0.74, 0.74, 0.74)
      else GameTooltip:AddLine("Already in your spellbook.", 0.31, 0.75, 0.23) end
      TipEnd(r, "drawer")
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.rows[k] = r; return r
  end
  local WORD = { now = "LEARN NOW", later = "LATER", known = "IN YOUR BOOK" }
  function d:Refresh()
    if self.mode == "book" then return self:RefreshBook() end
    if self.tab.text then self.tab.text:SetText("Trainer") end; self.head:SetText("AT THE TRAINER")
    local list = TF.TrainerList()
    for _, r in ipairs(self.rows) do r:Hide() end
    for _, h in ipairs(self.heads) do h:Hide() end
    local y, k, hk, state = 0, 0, 0, nil
    local counts, owedCost = { now = 0, later = 0, known = 0 }, {}
    for _, sp in ipairs(list or {}) do counts[sp.state] = counts[sp.state] + 1; if sp.state == "now" and not sp.skipped then owedCost[#owedCost + 1] = sp end end
    local ct = TF.OwedCostText(owedCost)
    self.cost:SetText(not list and "This client does not say which spells you know." or (counts.now == 0 and "Nothing new to learn at your level." or string.format("%d to learn now%s. Later ones are listed with their level.", counts.now, ct and (", " .. ct) or "")))
    for _, sp in ipairs(list or {}) do
      if sp.state ~= state then
        state = sp.state; hk = hk + 1; local h = Head(hk); h:Show(); h:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -(y + 6)); h:SetText(string.format("%s (%d)", WORD[state], counts[state])); y = y + 26
      end
      k = k + 1; local r = Row(k); r:Show(); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetHeight(ROWH); r.sub:Hide(); r.spell = sp
      r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 6, 0); r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 30, 0); r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
      r.icon:SetTexture(IconFor({ icon = sp.icon })); r.name:SetText(sp.ranks > 1 and string.format("%s (rank %d)", sp.name, sp.rank) or sp.name)
      local dim = sp.state == "known" or sp.skipped
      r.icon:SetDesaturated(dim); r.icon:SetAlpha(dim and 0.45 or 1); r.name:SetAlpha(dim and 0.55 or 1)
      if sp.state == "now" then r.right:SetText(sp.skipped and "skipped" or (sp.cost and TF.Money(sp.cost) or "no price")); r.right:SetTextColor(rgb(sp.skipped and C.muted or (sp.cost and C.gold or C.muted)))
      elseif sp.state == "later" then r.right:SetText(string.format("level %d", sp.level)); r.right:SetTextColor(rgb(C.muted))
      else r.right:SetText("Learned"); r.right:SetTextColor(rgb(C.green)) end
      y = y + ROWH
    end
    self.body:SetHeight(math.max(10, y + 10))
  end
  -- the book: every ability by the level it comes, what you have in green, the rest waiting; the next level lit
  function d:RefreshBook()
    if self.tab.text then self.tab.text:SetText("Spellbook") end; self.head:SetText("YOUR SPELLBOOK, BY LEVEL")
    local list = TF.SpellbookList(plan().cls)
    for _, r in ipairs(self.rows) do r:Hide() end
    for _, h in ipairs(self.heads) do h:Hide() end
    local lvl = UnitLevel("player") or 1; local own = isOwnClass()
    local y, k, hk, level, have, total = 0, 0, 0, nil, 0, 0
    for _, sp in ipairs(list or {}) do total = total + 1; if sp.known then have = have + 1 end end
    self.cost:SetText(not list and "No spellbook for this class yet." or (own and string.format("%d of %d ranks in your book. The rest come with levels, each at the trainer.", have, total) or string.format("Every %s ability from 1 to 60, the level it comes and its trainer price.", classData().name)))
    for _, sp in ipairs(list or {}) do
      if sp.level ~= level then
        level = sp.level; hk = hk + 1; local h = Head(hk); h:Show(); h:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -(y + 6))
        h:SetText(string.format("LEVEL %d%s", level, (own and level == lvl) and ", YOU ARE HERE" or "")); h.text:SetTextColor(rgb((own and level == lvl) and C.gold or C.muted)); y = y + 26
      end
      k = k + 1; local r = Row(k); r:Show(); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetHeight(34); r.spell = sp
      sp.state = sp.known and "known" or (own and sp.level <= lvl and "now" or "later")
      r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 4, 0); r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", 36, -4); r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0); r.sub:ClearAllPoints(); r.sub:SetPoint("BOTTOMLEFT", 36, 4); r.sub:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
      r.icon:SetTexture(IconFor({ icon = sp.icon })); r.name:SetText(sp.name)
      local rec = D.learn and D.learn[plan().cls] and D.learn[plan().cls][sp.name]
      local what = sp.rank == 1 and (rec and rec.talent and "New, from a talent in your plan" or "New ability") or string.format("Rank %d of %d", sp.rank, sp.ranks)
      if sp.skill then what = sp.classic and "Passive, from the trainer. Classic's level, until a Forever trainer confirms it" or "Passive, from the trainer" end   -- Dual Wield, Parry (a Rogue at 9 asked, 27 Sep)
      if sp.quest then what = "From a quest, not the trainer" end   -- Aquatic Form (a Druid at 24, 2 Oct)
      if sp.portal then what = what .. ", portal trainer" end
      r.sub:SetText(what); r.sub:Show()
      local dim = sp.known and true or false
      r.icon:SetDesaturated(dim); r.icon:SetAlpha(dim and 0.5 or 1); r.name:SetAlpha(dim and 0.6 or 1); r.sub:SetAlpha(dim and 0.6 or 1)
      r.name:SetTextColor(rgb(sp.rank == 1 and not dim and C.gold or C.ink))
      if sp.known then r.right:SetText("Learned"); r.right:SetTextColor(rgb(C.green))
      elseif own and sp.level <= lvl then r.right:SetText(sp.cost and TF.Money(sp.cost) or "trainer"); r.right:SetTextColor(rgb(C.gold))
      else r.right:SetText(sp.cost and TF.Money(sp.cost) or "no price"); r.right:SetTextColor(rgb(C.muted)) end
      y = y + 34
    end
    self.body:SetHeight(math.max(10, y + 10))
  end
  d:Hide()
  return d
end
function UI.OpenTrainer(toggle, mode)
  if not F then return end
  UI.drawer = UI.drawer or MakeDrawer()
  local d = UI.drawer
  mode = mode or "trainer"
  if toggle and d:IsShown() and d.mode == mode then d:Hide(); return end
  d.mode = mode
  if not F:IsShown() then UI.Show() end
  -- off the right edge, or the left when the screen ends there or the player asked for it; the top lines up with the
  -- side panel's tabs. A list dragged loose stays where it was dropped until Snap back.
  local es = F:GetEffectiveScale() or 1; local sw = (GetScreenWidth and GetScreenWidth() or 1920) * (UIParent:GetEffectiveScale() or 1)
  local fits = (F:GetRight() or 0) * es + SIDE_W * es <= sw
  local left = S().drawerSide == "left" or (S().drawerSide == nil and not fits)
  if not d.loose then
    d:ClearAllPoints()
    if left then d:SetPoint("TOPRIGHT", F, "TOPLEFT", 6, -(TOP + HEAD_H + HEAD_GAP - 2))
    else d:SetPoint("TOPLEFT", F, "TOPRIGHT", -6, -(TOP + HEAD_H + HEAD_GAP - 2)) end
  end
  d.onLeft = left; d:SideWord()
  d:Refresh(); d:Show()
end

-- the window's size on first open: a bit over two fifths of the screen's width, whatever the screen and the UI scale. A dense
-- laptop screen with a small UI scale would otherwise show the window tiny and its words soft. Once the player sets a size
-- themselves (Settings), that is kept.
function UI.AutoScale()
  if S().scaleSet or not F then return end
  local us = UIParent:GetEffectiveScale() or 1
  local pw = (GetPhysicalScreenSize and select(1, GetPhysicalScreenSize())) or ((GetScreenWidth and GetScreenWidth() or 1920) * us)
  local fw = (F:GetWidth() or BASE_W) * us   -- the window's width in physical pixels at scale 1
  if not pw or pw <= 0 or fw <= 0 then return end
  local want = math.max(0.7, math.min(1.02, (0.42 * pw) / fw))
  if math.abs(want - (F:GetScale() or 1)) > 0.06 then UI.SetScale(want) end
end
-- Clear: everything that was switched on for a look comes off at once and the window is as it opens. The plan is not
-- touched; Reset is the button for that.
function UI.ClearView()
  local did = 0
  if TF.trial then TF.TrialBack(); did = did + 1 end
  if (plan().level or 60) < 60 then TF.SetLevel(60); did = did + 1 end
  if head and head.search and head.search:GetText() ~= "" then head.search:SetText(""); did = did + 1 end
  if UI.drawer and UI.drawer:IsShown() then UI.drawer:Hide(); did = did + 1 end
  local b = tabs.builds and tabs.builds.frame
  if b and (b.qrOn or b.shareRec) then b.qrOn = false; b.shareRec = nil; did = did + 1 end
  if toast and toast:IsShown() then toast:Hide() end
  UI.LevelPeek(nil); GameTooltip:Hide()
  if S().sideTab ~= "home" then did = did + 1 end
  UI.SetTab("home")
  UI.Refresh()
  Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
  UI.Note(did > 0 and "Cleared. Your plan and your character are as they were." or "Nothing was on. Reset is the one that empties the plan.")
end
function UI.Show()
  local first = not F
  if not F then MakeFrame() end
  if toast and toast:IsShown() then toast:Hide() end
  BuildTrees()
  if first then UI.AutoScale() end
  if S().sideTab == "settings" or S().sideTab == nil or not tabs[S().sideTab] then S().sideTab = "home" end
  if TF.TotalPts(plan()) == 0 and S().sideTab == "plan" then S().sideTab = "home" end
  F:Show(); FadeIn(F, 0.18, 0.99); Sound("IG_MAINMENU_OPEN")
  Tween("open", 0.2, function(e) placeWindow(-8 * (1 - e)) end, { ease = "out4" })
  for _, t in pairs(tabs) do t.frame.spinPending = true end
  UI.Layout()
  -- the trees arrive one after another, quickly
  for ti, tp in ipairs(trees) do C_Timer.After(0.03 * ti, function() if tp:IsShown() then FadeIn(tp, 0.14) end end) end
  -- the first time the window opens on this account, three short lines in the footer say how it works
  if not S().seenIntro then S().seenIntro = true; C_Timer.After(0.4, function() UI.Walkthrough(1) end) end
end
-- the walkthrough: one footer line at a time, each waits for Next; it opens the page it talks about
local WALK = {
  { "Left click adds a point, right click takes it back. Nothing touches your character until you press Apply.", "home" },
  { "The right side lists your plan, one point per level. The arrows by the level number show the build as it stands at any level.", "plan" },
  { "Builds: save yours, share it by link or QR, or load one of the popular builds. /talents opens this window any time.", "builds" },
}
function UI.Walkthrough(step)
  step = step or 1
  local w = WALK[step]
  if not w or not F or not F:IsShown() then UI.walkStep = nil; return end
  UI.walkStep = step
  if w[2] and not UI.HiddenTab(w[2]) then UI.SetTab(w[2]) end
  if step == 1 and trees[1] and trees[1].tiles[1] then Land(trees[1].tiles[1], true) end
  local last = step == #WALK
  UI.Note(string.format("%d of %d. %s", step, #WALK, w[1]),
    { { label = last and "Done" or "Next", fn = function() if last then UI.walkStep = nil; UI.SetTab("plan"); UI.ClearNote() else UI.Walkthrough(step + 1) end end },
      (not last) and { label = "Skip", fn = function() UI.walkStep = nil; UI.SetTab("plan"); UI.ClearNote() end } or nil }, 600)
end
function UI.Hide() if F then F:Hide() end end
function TF.Toggle() if F and F:IsShown() then UI.Hide() else UI.Show() end end

-- ---------- the game's talents key ----------
-- With the switch on, whatever key the game has on its talents window (N, unless changed) opens this instead. It is an
-- override binding: the player's saved bindings are untouched, and it is gone the moment the switch goes off. The game
-- refuses binding changes in combat, so a change made in a fight waits for it to end. Asked for by Konis, 24 Sep.
local KEYS = { actions = { "TOGGLETALENTS" } }   -- btn: the named button the key clicks; pending: a change made in combat, waiting
function UI.ApplyTalentsKey(say)
  if not SetOverrideBindingClick or not GetBindingKey or not ClearOverrideBindings then return end
  if InCombatLockdown and InCombatLockdown() then KEYS.pending = true; if say then UI.Note("After the fight: the game takes no key changes in combat.", nil, 6) end; return end
  KEYS.pending = nil
  if not KEYS.btn then KEYS.btn = CreateFrame("Button", "TalentsForeverBookKeyButton", UIParent); KEYS.btn:SetScript("OnClick", function() TF.Toggle() end) end
  ClearOverrideBindings(KEYS.btn)
  if not S().talentsKey then if say then UI.Note("The talents key is the game's again.", nil, 6) end; return end
  local keys = {}
  for _, action in ipairs(KEYS.actions) do
    local k1, k2 = GetBindingKey(action)
    if k1 then keys[#keys + 1] = k1 end
    if k2 then keys[#keys + 1] = k2 end
  end
  for _, k in ipairs(keys) do SetOverrideBindingClick(KEYS.btn, true, k, "TalentsForeverBookKeyButton") end
  if say then UI.Note(#keys > 0 and string.format("%s opens Talents Forever now. Off in Settings gives the game's window back.", table.concat(keys, " and ")) or "The game's talents window has no key in Key Bindings, so there is nothing to take over yet.", nil, 8) end
end
-- bindings change (UPDATE_BINDINGS) and combat ends (PLAYER_REGEN_ENABLED) reach the boot frame below
function UI.TalentsKeyEvent(ev)
  if ev == "PLAYER_REGEN_ENABLED" and not KEYS.pending then return end
  if TF.db and TF.db.settings then UI.ApplyTalentsKey() end
end

-- ---------- minimap button ----------
-- shows or hides the minimap button, whichever kind this session has
function UI.SetMinimapShown(v)
  if UI.dbicon then if v then pcall(UI.dbicon.Show, UI.dbicon, "TalentsForeverBook") else pcall(UI.dbicon.Hide, UI.dbicon, "TalentsForeverBook") end
  elseif TalentsForeverBookMinimap then TalentsForeverBookMinimap:SetShown(v) end
end
local function MakeMinimap()
  local s = S().minimap
  if UI.dbicon or TalentsForeverBookMinimap then return end
  -- LibDBIcon, when another addon has loaded it: the button becomes one of its, so minimap button managers collect and
  -- place it like every other (a Warlock at 14 asked, 2 Oct 2026). Same icon, clicks and tooltip; the hide switch and the
  -- angle carry over (LibDBIcon reads hide and minimapPos from this same table).
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if lib and lib.Register and TF.UpdateBroker() and TF.Broker() then
    s.minimapPos = s.minimapPos or s.angle or 200
    if pcall(lib.Register, lib, "TalentsForeverBook", TF.Broker(), s) then
      UI.dbicon = lib
      if s.hide then pcall(lib.Hide, lib, "TalentsForeverBook") end
      return
    end
  end
  if s.minimapPos then s.angle = s.minimapPos end   -- a session with LibDBIcon dragged it: the own button starts where that left it
  local b = CreateFrame("Button", "TalentsForeverBookMinimap", Minimap)
  b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8); b:SetMovable(true); b:EnableMouse(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  b.disc = b:CreateTexture(nil, "BACKGROUND"); b.disc:SetTexture(SkinPath() .. "disc.png"); b.disc:SetSize(30, 30); b.disc:SetPoint("CENTER"); b.disc:SetVertexColor(0.09, 0.07, 0.03, 1)
  b.icon = Book(b, 21); b.icon:SetPoint("CENTER", 0, 0)
  if AtlasOK("Talents-Main-Ring-c60") then b.ring = b:CreateTexture(nil, "OVERLAY"); Atlas(b.ring, "Talents-Main-Ring-c60", 40, 40); b.ring:SetPoint("CENTER", 0, 0)
  else b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetTexture(MEDIA .. "ring.tga"); b.ring:SetSize(36, 36); b.ring:SetPoint("CENTER"); b.ring:SetVertexColor(0.78, 0.61, 0.10) end
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local function place() local a = math.rad(s.angle or 200); local rad = (Minimap:GetWidth() or 140) / 2 + 5; b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rad, math.sin(a) * rad) end
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition(); local sc = Minimap:GetEffectiveScale()
    s.angle = math.deg(atan2(cy / sc - my, cx / sc - mx)); s.minimapPos = s.angle; place()
  end) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn) if btn == "RightButton" then UI.Show(); S().showPlan = true; UI.Layout(); UI.SetTab("popular") else TF.Toggle() end end)
  Tip(b, "Talents Forever", "Left click: the planner. Right click: popular builds.\nDrag to move this button.\n|cffc79c1atalentsforever.com|r")
  place()
  if s.hide then b:Hide() end
end
UI.MakeMinimap = MakeMinimap

-- ---------- our layer over the game's own talent window (PlayerSpellsFrame.TalentsFrame) ----------
local overlay
local function TalentsFrame() return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame or nil end
local function MakeOverlay(tfr)
  local host = tfr.ButtonsParent or tfr
  local o = CreateFrame("Frame", "TalentsForeverBookOverlay", host)
  o:SetAllPoints(host); o:SetFrameLevel((host:GetFrameLevel() or 1) + 40); o:EnableMouse(false)
  o.segs, o.badges = {}, {}
  o.note = Text(o, 13, C.gold, true); o.note:SetPoint("BOTTOMLEFT", tfr, "BOTTOMLEFT", 30, 12); o.note:SetShadowColor(0, 0, 0, 0.9); o.note:SetShadowOffset(1, -1)
  overlay = o
  return o
end
local function badge(o, k)
  local b = o.badges[k]
  if b then return b end
  b = CreateFrame("Frame", nil, o); b:SetSize(26, 16); b:EnableMouse(false)
  b.bg = Solid(b, "BACKGROUND", C.bg, 0.9); b.bg:SetAllPoints()
  b.text = Text(b, 12, C.gold); b.text:SetPoint("CENTER"); b.text:SetJustifyH("CENTER")
  b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetTexture(MEDIA .. "ring.tga"); b.ring:SetSize(56, 56); b.ring:SetVertexColor(1, 0.82, 0); b.ring:SetAlpha(0)
  b.pulse = Pulse(b.ring, 0.25, 0.9, 0.9)
  o.badges[k] = b
  return b
end
function UI.RefreshOverlay()
  local tfr = TalentsFrame()
  if not tfr or not tfr:IsShown() then return end
  if not overlay then MakeOverlay(tfr) end
  local o = overlay
  for _, t in ipairs(o.segs) do t:Hide() end
  for _, b in ipairs(o.badges) do b:Hide(); b.pulse:Stop(); b.ring:SetAlpha(0) end
  if not S().overlay or not isOwnClass() or not tfr.GetTalentButtonByNodeID then o.note:SetText(""); return end
  local p = plan(); local cd = classData()
  local list = TF.NextUp(p)
  local nextK
  for k, e in ipairs(list) do if not e.done then nextK = k; break end end
  local nb = 0
  local buttons = {}
  for ti, tree in ipairs(cd.trees) do for i, t in ipairs(tree.talents) do
    local ok, btn = pcall(tfr.GetTalentButtonByNodeID, tfr, t.node)
    if ok and btn then
      buttons[ti .. ":" .. i] = btn
      local r = p.ranks[ti][i]
      if r > 0 then
        nb = nb + 1
        local b = badge(o, nb); b:Show(); b:ClearAllPoints(); b:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6)
        b.text:SetText(tostring(r)); b.text:SetTextColor(rgb(C.gold)); b:SetWidth(22)
      end
    end
  end end
  if nextK and list[nextK] then
    local e = list[nextK]; local btn = buttons[e.ti .. ":" .. e.i]
    if btn then nb = nb + 1; local b = badge(o, nb); b:Show(); b:ClearAllPoints(); b:SetPoint("CENTER", btn, "CENTER"); b:SetWidth(1); b.text:SetText(""); b.bg:SetAlpha(0); b.ring:SetPoint("CENTER", b, "CENTER"); b.pulse:Play() end
  end
  local missing = select(1, TF.Diff(p)) or 0
  o.note:SetText(#list > 0 and string.format("Talents Forever: %d planned, %d still to place. Gold numbers are your plan, the ring is your next point.", #list, missing) or "Talents Forever: no plan yet. /talents to make one.")
end
-- "Open this instead of the game's talents" (a Hunter at 20 asked from inside the addon, 30 Sep): the game's talent tab,
-- opened any way at all (the key, the micro bar, the spellbook's own tab), closes again on the next frame and the planner
-- opens in its place. Shift held while opening it keeps the game's window that once, and a fight leaves it alone: the
-- game's panels are not closed from an addon in combat. Off by default; the talents key switch above is separate.
function UI.ReplaceTalents()
  if not (TF.db and TF.db.settings and S().replaceTalents) then return false end
  if IsShiftKeyDown and IsShiftKeyDown() then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  return true
end
function UI.TakeOverTalents()
  local host = PlayerSpellsFrame; local tfr = TalentsFrame()
  if not host or not tfr or not host:IsShown() or not tfr:IsShown() then return end
  if not UI.ReplaceTalents() then return end   -- the switch went off, or a fight started, between the show and this frame
  local ok = HideUIPanel and pcall(HideUIPanel, host)
  if not ok then pcall(host.Hide, host) end
  UI.Show()
end
local overlayHooked = false
local function HookTalentWindow()
  local tfr = TalentsFrame()
  if not tfr or overlayHooked then return end
  overlayHooked = true
  tfr:HookScript("OnShow", function()
    if UI.ReplaceTalents() then C_Timer.After(0, UI.TakeOverTalents); return end
    C_Timer.After(0.2, UI.RefreshOverlay); C_Timer.After(0.8, UI.RefreshOverlay)
  end)
  tfr:HookScript("OnHide", function() if overlay then for _, b in ipairs(overlay.badges) do b:Hide(); b.pulse:Stop() end; for _, t in ipairs(overlay.segs) do t:Hide() end end end)
  if tfr:IsShown() then C_Timer.After(0.2, UI.RefreshOverlay) end
  TF.Log("talent window hooked")
end

-- ---------- the book on the character pane: a seventh side tab ----------
local charTab
local function MakeCharacterTab()
  if charTab or not CharacterFrame or not CharacterFrame.ModeTabs or not CharacterFrame.ModeTabs.Tabs then return end
  local ok, tab = pcall(CreateFrame, "Frame", "TalentsForeverBookCharacterTab", CharacterFrame.ModeTabs, "LargeSideTabButtonTemplate")
  if not ok or not tab then TF.Log("character tab: %s", tostring(tab)); return end
  charTab = tab
  tab.tooltipText = "Talents Forever"
  if tab.Icon then
    local okT, r = pcall(tab.Icon.SetTexture, tab.Icon, MEDIA .. "book-tab.png")
    if not okT or r == false then tab.Icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09") end
    if tab.SetFillToInterior then tab:SetFillToInterior(true, 50) end
  end
  if tab.SetCustomOnMouseUpHandler then tab:SetCustomOnMouseUpHandler(function(_, button, upInside) if button == "LeftButton" and upInside then TF.Toggle(); if tab.SetChecked then tab:SetChecked(false) end end end) end
  tab:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Talents Forever", 1, 0.82, 0); GameTooltip:AddLine("Plan, path, builds. Same as /talents.", 0.9, 0.9, 0.9); GameTooltip:Show() end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local function place()
    local last
    for _, t in ipairs(CharacterFrame.ModeTabs.Tabs) do if t:IsShown() then last = t end end
    tab:ClearAllPoints()
    if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2) else tab:SetPoint("TOPLEFT", CharacterFrame.ModeTabs, "TOPLEFT") end
  end
  place()
  if hooksecurefunc and CharacterFrame.UpdateTabLayout then pcall(hooksecurefunc, CharacterFrame, "UpdateTabLayout", place) end
  if S().charTab == false then tab:Hide() end   -- switched off in Settings
  TF.Log("character tab added")
end

-- ---------- a way in from the game's own talent window ----------
local hooked = {}
local function noteLoaded(name)
  local diag = TF.db and TF.db.diag; if not diag then return end
  diag.loaded = diag.loaded or {}
  diag.loaded[name] = date("%H:%M:%S")
  diag.framesSeen = diag.framesSeen or {}
  for _, n in ipairs({ "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame", "SpellBookFrame", "ClassicTalentFrame", "TalentFrameBase", "PlayerSpellsFrame.TalentsFrame" }) do
    if _G[n] then diag.framesSeen[n] = true end
  end
end
local function HookBlizzard()
  for _, name in ipairs({ "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }) do
    local host = _G[name]
    if host and not hooked[name] and host.CreateFontString then
      hooked[name] = true
      local b = Button(host, "Talents Forever", "auto", 20, function() TF.Toggle() end)
      b:SetPoint("TOPLEFT", host, "TOPLEFT", 64, -3); b:SetFrameLevel(host:GetFrameLevel() + 10)
      Tip(b, "Talents Forever", "Plan here, apply there.")
      TF.Log("button added to %s", name)
    end
  end
end

-- ---------- slash commands and startup ----------
SLASH_TALENTSFOREVERBOOK1 = "/talents"; SLASH_TALENTSFOREVERBOOK2 = "/tfb"; SLASH_TALENTSFOREVERBOOK4 = "/talentsforever"
SlashCmdList.TALENTSFOREVERBOOK = function(msg)
  msg = (msg or ""):gsub("^%s+", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then TF.Toggle()
  elseif cmd == "probe" then G.Probe()
  elseif cmd == "log" then for k = math.max(1, #TF.log - 25), #TF.log do print("  " .. TF.log[k]) end; TF.Print("%d log lines", #TF.log)
  elseif cmd == "import" or cmd == "load" then local ok, err = TF.LoadCode(rest); TF.Print(ok and "loaded." or (err or "no")); if ok then UI.Show() end
  elseif cmd == "share" or cmd == "link" then UI.Show(); UI.OpenSheet("share")
  elseif cmd == "reset" then TF.Reset(); TF.Print("plan cleared (your character is untouched). /talents undo brings it back.")
  elseif cmd == "undo" then TF.Print(TF.Undo() and "the plan is back." or "nothing to undo.")
  elseif cmd == "find" then UI.Find(rest)
  elseif cmd == "settings" or cmd == "options" then UI.Show(); UI.OpenSettings()
  elseif cmd == "next" then UI.ApplyNext()
  elseif cmd == "all" then UI.ApplyAll()
  elseif cmd == "save" then local rec = TF.SaveBuild(rest); TF.Print("saved as %s.", rec.name)
  elseif cmd == "builds" then
    if #TF.db.builds == 0 then TF.Print("no saved builds. /talents save <name> keeps the open plan.") end
    for k, b in ipairs(TF.db.builds) do TF.Print("%d. %s (%s, %s/%s/%s)", k, b.name, D.classes[b.cls] and D.classes[b.cls].name or b.cls, tostring(b.pts[1]), tostring(b.pts[2]), tostring(b.pts[3])) end
  elseif cmd == "open" then
    local pick = tonumber(rest)
    if not pick then for k, b in ipairs(TF.db.builds) do if b.name:lower() == (rest or ""):lower() then pick = k; break end end end
    if pick and TF.LoadBuild(pick) then TF.Print("%s is on your trees.", TF.db.builds[pick].name); UI.Show() else TF.Print("no saved build called %s. /talents builds lists them.", rest) end
  elseif cmd == "plans" then
    for k, e in ipairs(TF.PlanList()) do local parts = {}; for ti = 1, #e.plan.ranks do parts[ti] = TF.TreePts(e.plan, ti) end; TF.Print("%d. %s (%s)%s", k, e.name, table.concat(parts, "/"), k == 1 and ", open" or "") end
    TF.Print("/talents plan <name> opens one; the chip after your class in the window does the same.")
  elseif cmd == "plan" then
    local k = TF.SwitchPlanNamed(rest)
    if k == 0 then TF.Print("%s is already open.", TF.PlanName()) elseif k then TF.Print("%s is on your trees.", TF.PlanName()); UI.Show() else TF.Print("no plan called %s. /talents plans lists them.", rest) end
  elseif cmd == "scale" then local v = tonumber(rest); if F and v then UI.SetScale(v); TF.Print("scale %.2f", F:GetScale()) else TF.Print("/talents scale 0.5 to 1.6, or drag the corner.") end
  elseif cmd == "center" then S().pos = nil; if F then restorePos() end; TF.Print("window centered.")
  elseif cmd == "party" then local ok, why = TF.AskParty(); TF.Print(ok and "asked your group for their builds." or why)
  elseif cmd == "inspect" then local ok, why = TF.RequestInspect("target"); if not ok then TF.Print(why) end
  elseif cmd == "trainall" then if TF.trainer.open then local n = TF.TrainAll(); if n == 0 then TF.Print("nothing here that you want and can afford.") end else TF.Print("open a trainer window first.") end
  elseif cmd == "trainer" then local owed = TF.OwedSpells(); if not owed then TF.Print("this client cannot say which spells you know.") elseif #owed == 0 then TF.Print("your spellbook has everything the trainer sells at your level.") else local ct = TF.OwedCostText(owed); TF.Print("%d waiting at the trainer%s: %s.", #owed, ct and (" (" .. ct .. ")") or "", TF.SpellsSummary(owed, 12)) end
  elseif cmd == "nudge" then S().levelUpNudge = not S().levelUpNudge; TF.Print("level-up reminders %s.", S().levelUpNudge and "on" or "off")
  elseif cmd == "intro" then UI.Show(); UI.Walkthrough(1)
  elseif cmd == "sounds" then S().sounds = not S().sounds; TF.Print("sounds %s.", S().sounds and "on" or "off")
  elseif cmd == "minimap" then S().minimap.hide = not S().minimap.hide; UI.SetMinimapShown(not S().minimap.hide)
  else
    TF.Print("v%s. /talents opens the planner. /talents next and /talents all place planned points. /talents save <name>, /talents builds, /talents open <name>, /talents plans, /talents plan <name>, /talents find <talent>, /talents undo, /talents settings, /talents import <link or code>, /talents share, /talents reset, /talents scale <n>, /talents center, /talents inspect, /talents party, /talents trainer, /talents trainall, /talents nudge, /talents sounds, /talents minimap, /talents intro, /talents log.", TF.VERSION)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED"); boot:RegisterEvent("PLAYER_LOGIN"); boot:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(boot.RegisterEvent, boot, "ADDON_ACTION_FORBIDDEN")   -- the game blocked something of ours: the class dropdown is the one piece that can do that
pcall(boot.RegisterEvent, boot, "CHAT_MSG_ADDON")
pcall(boot.RegisterEvent, boot, "UPDATE_BINDINGS"); pcall(boot.RegisterEvent, boot, "PLAYER_REGEN_ENABLED")   -- the talents key switch
local function onBuildMessage(prefix, text, channel, sender)
  if prefix ~= TF.PREFIX or type(text) ~= "string" then return end
  local me = UnitName("player")
  local who = (sender or "?"):match("^([^%-]+)") or sender
  if who == me then return end
  if text:sub(1, 2) == "Q1" then TF.AnswerParty(channel); return end   -- someone asked the group for builds
  if S().othersBuilds == false then return end   -- they said no to other people's builds
  local p, code = TF.ReceiveBuild(text, sender)
  if not p then return end
  local c = D.classes[p.cls]
  TF.RememberGroupBuild(who, p, code)
  local parts = {}
  for ti = 1, #p.ranks do parts[ti] = TF.TreePts(p, ti) end
  local label = string.format("%s's %s build", who, c.name)
  UI.Toast(string.format("%s sent you a %s build at level %d (%s).", who, c.name, p.level, table.concat(parts, " / ")), IconFor({ icon = c.trees[1].icon }),
    { { label = "Try it", fn = function() TF.TryBuild(p, label); UI.Show() end }, { label = "Load it", fn = function() TF.Remember(); TF.SetPlan(p); UI.Show() end } }, 40)
  Sound("IG_QUEST_LIST_OPEN")
end
local greeted
boot:SetScript("OnEvent", function(_, ev, name, arg2, arg3, arg4)
  if ev == "CHAT_MSG_ADDON" then onBuildMessage(name, arg2, arg3, arg4); return end
  if ev == "ADDON_ACTION_FORBIDDEN" then
    if name == "TalentsForeverBook" and TF.db and TF.db.settings and not S().plainClassList then
      S().plainClassList = true
      TF.Print("the game blocked the class list (%s). The plain class button takes its place from the next /reload.", tostring(arg2))
    end
    return
  end
  if ev == "UPDATE_BINDINGS" or ev == "PLAYER_REGEN_ENABLED" then UI.TalentsKeyEvent(ev); return end
  if ev == "ADDON_LOADED" then
    if name == "TalentsForeverBook" then TF.InitDB(); if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, TF.PREFIX) end end
    if name and name:find("^Blizzard_") then noteLoaded(name); C_Timer.After(0.5, HookBlizzard); C_Timer.After(0.6, HookTalentWindow) end
  elseif ev == "PLAYER_LOGIN" then
    TF.InitDB(); TF.LoadPlan(); MakeMinimap(); pcall(UI.ApplyTalentsKey)
    C_Timer.After(0.5, function()
      if F then return end
      MakeFrame(); BuildTrees(); UI.Layout(); pcall(UI.Refresh)
      for _, t in pairs(tabs) do if t.refresh then pcall(t.refresh) end end
      F:Hide()
    end)
    -- /tf is ours. Another addon may register it too; the one that registers last answers, and this folder loads after
    -- the other TalentsForever's (alphabetical), so ours does.
    SLASH_TALENTSFOREVERBOOK3 = "/tf"
    if hash_SlashCmdList then hash_SlashCmdList["/tf"] = "TALENTSFOREVERBOOK" end
    UI.tfShort = true
    -- What's Training already lists the trainer's spells for most players: until they touch the setting, our reminders stay out of its way
    if not S().trainerAlertsSet then local isl = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded; local ok, on = pcall(isl or error, "WhatsTraining"); S().trainerAlerts = not (ok and on) end C_Timer.After(1, MakeCharacterTab); C_Timer.After(1, HookTalentWindow); pcall(TF.InstallChatLinks); C_Timer.After(3, function() pcall(TF.UpdateBroker) end)
  elseif ev == "PLAYER_ENTERING_WORLD" then
    TF.InitDB(); TF.LoadPlan()
    C_Timer.After(1, HookBlizzard)
    -- a line in chat once per version, not every login: the addon stays quiet unless something changed
    if not greeted then greeted = true; if S().greetedVersion ~= TF.VERSION then S().greetedVersion = TF.VERSION; TF.Print("v%s loaded. %s opens the planner, /talents help lists the rest.", TF.VERSION, UI.tfShort and "/tf or /talents" or "/talents") end end
    -- one card at login, never two: the once-only update card, else the unspent-point card if there is one, else the trainer card
    local loginCard = false
    C_Timer.After(10, function() loginCard = UI.UpgradeCard(); if not loginCard and TF.lastSettled then UI.SettledCard(TF.lastSettled); loginCard = true end end)   -- a plan that settled at login gets the card too
    C_Timer.After(12, function() if not loginCard and G.live and G.Unspent() > 0 then loginCard = Nudge(string.format("%d unspent point%s", G.Unspent(), G.Unspent() == 1 and "" or "s")) and true or false end end)
    C_Timer.After(16, function() if not loginCard then TrainerAlert((GetRealZoneText and GetRealZoneText()) or nil) end end)
    -- once per batch of replies: a card saying what happened to what people asked for. The Feedback page has the words,
    -- and a note sent from this account has its answer under it there.
    local R = D.replies
    if R and R.asOf and S().repliesSeen ~= R.asOf then
      C_Timer.After(24, function()
        if S().repliesSeen == R.asOf then return end
        S().repliesSeen = R.asOf
        local mine = 0; for _, r in ipairs(TF.Replies() or {}) do if r.mine then mine = mine + 1 end end
        local words = mine > 0 and string.format("There is a reply to %s. It is on the Feedback page, under your note.", mine == 1 and "the note you sent from here" or "the notes you sent from here")
          or R.card or "What people asked for from inside the addon, and what happened to it, is on the Feedback page now."
        UI.Toast(words, nil, { { label = "Read it", fn = function() UI.Show(); UI.SetTab("feedback") end } }, 30)
      end)
    end
  end
end)
TF.On("PLAN_CHANGED", function() TF.CharDB().plan = TF.plan; if F and F:IsShown() then if builtFor ~= TF.plan.cls then BuildTrees() end; UI.Refresh() end; for k, s in pairs(sheets) do if s:IsShown() and s.refresh and k ~= "import" then s.refresh() end end; UI.RefreshOverlay() end)
TF.On("GAME_CHANGED", function() UI.Refresh(); UI.RefreshOverlay() end)
TF.On("XP", function() if F and F:IsShown() and S().sideTab == "home" and tabs.home and tabs.home.refresh then tabs.home.refresh() end end)
TF.On("COMMIT_FAILED", function() UI.Toast("The game did not accept the last talent change. Your plan is untouched; try again in a moment.") end)
TF.On("BUILDS_CHANGED", function() if F and F:IsShown() and S().sideTab == "builds" then tabs.builds.refresh() end end)
TF.On("SKIP_CHANGED", function(name, rank, on) UI.Note(on and string.format("%s skipped. It stays out of the reminders for this character.", name) or string.format("%s is back on the list.", name)) end)
TF.On("LEVEL_UP", function(level) local shown = Nudge("Level " .. tostring(level or UnitLevel("player"))); C_Timer.After(shown and 30 or 6, function() TrainerAlert(nil) end) end)
TF.On("ZONE", function(where) if UI.CityHere(where) then TrainerAlert(where) end end)
TF.On("LINK_OPENED", function(p)
  local c = D.classes[p.cls]; UI.Show(); TF.TryBuild(p, "a build from chat")
  UI.Note(string.format("%s build from chat, ringed on your trees next to yours.", c and c.name or "A"),
    { { label = "Load it", fn = function() TF.TrialKeep(); UI.Note("Loaded.", { { label = "Undo", fn = function() TF.Undo() end } }) end }, { label = "Stop", fn = function() TF.TrialBack() end } }, 20)
end)
