local _, ns = ...

-- The look. Every panel, button and checkbox in ForeverUI is drawn here, from
-- plain frames and coloured textures: flat dark fill, one-pixel border, accent
-- on hover. Nothing uses Blizzard's templates, because those carry the stone
-- and gold artwork we're replacing -- and because their names and internals
-- differ between game versions.
--
-- Textures rather than SetBackdrop: backdrops need BackdropTemplate on modern
-- clients and don't on old ones, and a texture works on both.

local skin = {}
ns.Skin = skin

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Unpack(color)
  return color[1], color[2], color[3], color[4] or 1
end

-- One-pixel edges on all four sides, kept at a real pixel whatever the scale.
-- Borders drawn in the accent colour, so changing it can repaint what is
-- already on screen. Weak keys: a frame that goes away takes its entry.
local accentBorders = setmetatable({}, { __mode = "k" })
skin.accentBorders = accentBorders
skin.accentListeners = {}

-- Text and textures painted in the accent. A colour is COPIED into a widget
-- when it is set, so the accent table changing is not enough: each one has to
-- be painted again, which means remembering which asked for the accent.
local accentTexts = setmetatable({}, { __mode = "k" })
local accentTextures = setmetatable({}, { __mode = "k" })
-- Buttons we paint: a selected one wears the accent, and nothing would
-- repaint it until it was hovered or clicked.
local accentButtons = setmetatable({}, { __mode = "k" })
skin.accentTexts, skin.accentTextures, skin.accentButtons = accentTexts, accentTextures, accentButtons

local function PaintAccentText(region, alpha)
  local c = ns.Colors.ui.accent
  region:SetTextColor(c[1], c[2], c[3], alpha or 1)
end

local function PaintAccentTexture(texture, alpha, mode)
  local c = ns.Colors.ui.accent
  if mode == "vertex" then
    texture:SetVertexColor(c[1], c[2], c[3], alpha or 1)
  else
    texture:SetColorTexture(c[1], c[2], c[3], alpha or 1)
  end
end

-- Paint this text in the accent, and keep painting it when the accent changes.
function skin.AccentText(region, alpha)
  if not region or not region.SetTextColor then return region end
  accentTexts[region] = alpha or 1
  PaintAccentText(region, alpha)
  return region
end

-- The same for a texture. "vertex" for an icon or artwork; anything else is
-- a flat colour (a rule, a fill).
function skin.AccentTexture(texture, alpha, mode)
  if not texture then return texture end
  accentTextures[texture] = { alpha = alpha or 1, mode = mode }
  PaintAccentTexture(texture, alpha, mode)
  return texture
end

function skin.Border(frame, color)
  if color == ns.Colors.ui.accent then
    accentBorders[frame] = true
  end
  local px = ns.Media.Pixel()
  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = frame:CreateTexture(nil, "BORDER")
    tex:SetColorTexture(Unpack(color or ns.Colors.ui.border))
    if side == "TOP" then
      tex:SetPoint("TOPLEFT")
      tex:SetPoint("TOPRIGHT")
      tex:SetHeight(px)
    elseif side == "BOTTOM" then
      tex:SetPoint("BOTTOMLEFT")
      tex:SetPoint("BOTTOMRIGHT")
      tex:SetHeight(px)
    elseif side == "LEFT" then
      tex:SetPoint("TOPLEFT")
      tex:SetPoint("BOTTOMLEFT")
      tex:SetWidth(px)
    else
      tex:SetPoint("TOPRIGHT")
      tex:SetPoint("BOTTOMRIGHT")
      tex:SetWidth(px)
    end
    edges[#edges + 1] = tex
    edges[side] = tex
  end
  frame.borderEdges = edges
  frame.fuiEdge = color or ns.Colors.ui.border
  return edges
end

-- Every border that was drawn in the accent, brought up to the colour it is
-- now. Anything with a colour of its own is left alone.
function skin.RepaintAccent()
  local accent = ns.Colors.ui.accent
  for frame in pairs(accentBorders) do
    if frame.borderEdges then
      skin.SetBorderColor(frame, accent)
    end
  end
  for region, alpha in pairs(accentTexts) do
    pcall(PaintAccentText, region, alpha)
  end
  for texture, how in pairs(accentTextures) do
    pcall(PaintAccentTexture, texture, how.alpha, how.mode)
  end
  for button in pairs(accentButtons) do
    if button.Paint then
      pcall(button.Paint, button)
    elseif skin.PaintButton then
      pcall(skin.PaintButton, button)
    end
  end
  for _, listener in ipairs(skin.accentListeners) do
    pcall(listener, accent)
  end
end

-- Modules that paint their own widgets in the accent (the micro bar's tiles)
-- ask to be told when it changes.
function skin.AddAccentListener(fn)
  skin.accentListeners[#skin.accentListeners + 1] = fn
end

function skin.SetBorderColor(frame, color)
  for _, tex in ipairs(frame.borderEdges or {}) do
    tex:SetColorTexture(Unpack(color))
  end
  frame.fuiEdge = color
  -- The rounded corners' curved edge too.
  local shape = frame.fuiShape
  if shape then
    for _, rim in ipairs(shape.rim) do rim:SetVertexColor(Unpack(color)) end
  end
end

-- A flat panel: fill plus border. opts.color / opts.borderColor override.
-- opts.square keeps it square whatever General > Rounded corners says (bars,
-- nameplates, the minimap: the windows and panels round first);
-- opts.corners = "top" rounds only the top two (a window's title strip);
-- opts.inset shrinks the radius by that much (a strip set 1px inside its
-- window, so its curve follows the window's).
function skin.Panel(frame, opts)
  opts = opts or {}
  -- Sub-level -8 so it sits behind anything the frame already draws at
  -- BACKGROUND -- an action button's spell icon, for one.
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetPoint("TOPLEFT")
  bg:SetPoint("BOTTOMRIGHT")
  bg:SetColorTexture(Unpack(opts.color or ns.Colors.ui.backdrop))
  frame.bg = bg
  if opts.border ~= false then
    skin.Border(frame, opts.borderColor)
  end
  if not opts.square then
    skin.Roundable(frame, opts)
  end
  return frame
end

function skin.SetPanelColor(frame, color)
  if frame.bg then
    frame.bg:SetColorTexture(Unpack(color))
  end
end

---------------------------------------------------------------------------
-- Rounded corners (Gnatz_0815 on CurseForge, 28 Sept 2026: "rounded corners
-- and shadows"; owner: "build rounded corners for the windows and panels
-- first ... make it an option to turn them on and off")
---------------------------------------------------------------------------
--
-- Off, a panel is what it always was: one fill texture and four edges. On,
-- the fill is cut into a centre, four side strips and four corner cells, and
-- each corner cell draws a quarter of a disc -- the game's own round portrait
-- mask (TempPortraitAlphaMask, already used by the setup's dots), coloured,
-- so there is no new art. The border's four edges stop short of the corners
-- and a slightly larger quarter disc in the border colour sits under each
-- corner's fill: the rim that shows round the fill is the curved edge.
--
-- frame.bg stays the one texture callers know. It becomes the centre piece,
-- and whatever a caller does to it -- recolour it, fade it, hide it -- the
-- other pieces follow (hooked, so no caller has to know about corners).

local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local roundable = setmetatable({}, { __mode = "k" })
skin.roundable = roundable
local CORNERS = {
  -- corner, which way in (x, y), texcoords of the disc's quarter
  { "TOPLEFT",     1, -1, 0, 0.5, 0, 0.5, top = true },
  { "TOPRIGHT",   -1, -1, 0.5, 1, 0, 0.5, top = true },
  { "BOTTOMLEFT",  1,  1, 0, 0.5, 0.5, 1 },
  { "BOTTOMRIGHT", -1, 1, 0.5, 1, 0.5, 1 },
}
local OPPOSITE = { TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT" }

-- The radius asked for, 0 when corners are square. A group (action buttons,
-- unit frames) has its own switch under Corners as well.
function skin.CornerRadius(group)
  local db = ns.db
  if not (db and db.roundCorners) then return 0 end
  if group and db[group] == false then return 0 end
  return math.max(0, tonumber(db.cornerRadius) or 6)
end

-- The radius this panel is drawn with now: the setting, less its inset,
-- never more than a quarter of its short side -- a window keeps the radius
-- asked for, a button's is gentler, and a checkbox never turns into a
-- radio button.
function skin.EffectiveRadius(frame)
  local opts = roundable[frame]
  if not opts then return 0 end
  local want = skin.CornerRadius(opts.group)
  if want > 0 then want = math.max(0, want - (opts.inset or 0)) end
  local w, h = frame:GetWidth(), frame:GetHeight()
  if w and h and w > 0 and h > 0 then
    want = math.min(want, math.floor(math.min(w, h) / 4))
  end
  return want
end

-- How far in from the edge a square thing (an icon, a bar) must sit so its
-- corner stays inside a curve of radius r: r * (1 - 1/sqrt 2), rounded up.
function skin.CornerClearance(r)
  if not r or r <= 0 then return 0 end
  return math.ceil(r * 0.3)
end

local function FillColor(frame)
  local c = frame.fuiFill
  if c then return c[1], c[2], c[3], c[4] end
  return Unpack(ns.Colors.ui.backdrop)
end

-- Every piece of the fill takes the centre's colour, alpha and visibility.
local function Mirror(frame)
  local shape = frame.fuiShape
  if not shape then return end
  local r, g, b, a = FillColor(frame)
  local shown = frame.bg:IsShown() and shape.on
  local alpha = frame.bg.GetAlpha and frame.bg:GetAlpha() or 1
  for _, strip in ipairs(shape.strips) do
    strip:SetColorTexture(r, g, b, a)
    strip:SetAlpha(alpha)
    strip:SetShown(shown and true or false)
  end
  for i, cell in ipairs(shape.fill) do
    if shape.round[i] then
      cell:SetVertexColor(r, g, b, a)   -- the disc itself is set in ShapePanel
    else
      cell:SetVertexColor(1, 1, 1, 1)   -- a tint left from being round would multiply in
      cell:SetColorTexture(r, g, b, a)
    end
    cell:SetAlpha(alpha)
    cell:SetShown(shown and true or false)
  end
end

local function EdgeColor(frame)
  local top = frame.borderEdges and frame.borderEdges.TOP
  return frame.fuiEdge or (top and top.fuiColor) or ns.Colors.ui.border
end

local function Pieces(frame)
  local shape = frame.fuiShape
  if shape then return shape end
  shape = { strips = {}, fill = {}, rim = {}, round = {} }
  frame.fuiShape = shape
  for i = 1, 4 do
    shape.strips[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shape.rim[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    shape.fill[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  end
  return shape
end

-- Lay the pieces out for the radius in force now.
function skin.ShapePanel(frame)
  local opts = roundable[frame]
  if not opts or not frame.bg then return end
  -- The rim is as thick as the frame's border (a unit frame's can be 2).
  local px = frame.fuiEdgeWidth or ns.Media.Pixel()
  local r = skin.EffectiveRadius(frame)
  local bg = frame.bg
  local edges = frame.borderEdges
  if r <= 0 then
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT")
    bg:SetPoint("BOTTOMRIGHT")
    if frame.fuiShape then
      frame.fuiShape.on = false
      for _, list in ipairs({ frame.fuiShape.strips, frame.fuiShape.fill, frame.fuiShape.rim }) do
        for _, piece in ipairs(list) do piece:Hide() end
      end
    end
    if edges then
      edges.TOP:ClearAllPoints(); edges.TOP:SetPoint("TOPLEFT"); edges.TOP:SetPoint("TOPRIGHT")
      edges.BOTTOM:ClearAllPoints(); edges.BOTTOM:SetPoint("BOTTOMLEFT"); edges.BOTTOM:SetPoint("BOTTOMRIGHT")
      edges.LEFT:ClearAllPoints(); edges.LEFT:SetPoint("TOPLEFT"); edges.LEFT:SetPoint("BOTTOMLEFT")
      edges.RIGHT:ClearAllPoints(); edges.RIGHT:SetPoint("TOPRIGHT"); edges.RIGHT:SetPoint("BOTTOMRIGHT")
    end
    if opts.onShape then pcall(opts.onShape, frame, 0) end
    return
  end

  local shape = Pieces(frame)
  shape.on = true
  shape.r = r
  local onlyTop = opts.corners == "top"
  local cut = {}   -- corner -> how far the edges stop short of it
  for i, c in ipairs(CORNERS) do
    shape.round[i] = not onlyTop or c.top == true
    cut[c[1]] = shape.round[i] and r or 0
  end

  -- Centre and strips: the fill minus the four corner cells.
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", frame, "TOPLEFT", r, -r)
  bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, r)
  local top, bottom, left, right = shape.strips[1], shape.strips[2], shape.strips[3], shape.strips[4]
  top:ClearAllPoints()
  top:SetPoint("TOPLEFT", frame, "TOPLEFT", r, 0)
  top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -r, -r)
  bottom:ClearAllPoints()
  bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", r, r)
  bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, 0)
  left:ClearAllPoints()
  left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -r)
  left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", r, r)
  right:ClearAllPoints()
  right:SetPoint("TOPLEFT", frame, "TOPRIGHT", -r, -r)
  right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, r)

  -- Corner cells: a quarter disc where rounded, a plain square where not.
  -- With a border the fill's disc is one pixel smaller, and the rim's full
  -- size disc under it shows as the curved edge.
  local bordered = edges ~= nil and (not edges.TOP.IsShown or edges.TOP:IsShown())
  local ec = EdgeColor(frame)
  for i, c in ipairs(CORNERS) do
    local corner, dx, dy = c[1], c[2], c[3]
    local cell, rim = shape.fill[i], shape.rim[i]
    local inner = OPPOSITE[corner]
    local round = shape.round[i]
    local size = (round and bordered) and math.max(1, r - px) or r
    cell:ClearAllPoints()
    cell:SetSize(size, size)
    cell:SetPoint(inner, frame, corner, dx * r, dy * r)
    if round then
      cell:SetTexture(DISC)
      cell:SetTexCoord(c[4], c[5], c[6], c[7])
    else
      cell:SetColorTexture(1, 1, 1, 1)   -- Mirror paints it
      cell:SetTexCoord(0, 1, 0, 1)
    end
    rim:ClearAllPoints()
    rim:SetSize(r, r)
    rim:SetPoint(corner, frame, corner, 0, 0)
    rim:SetTexture(DISC)
    rim:SetTexCoord(c[4], c[5], c[6], c[7])
    rim:SetVertexColor(Unpack(ec))
    rim:SetShown((round and bordered) and true or false)
  end

  -- The straight edges stop where the curve starts.
  if edges then
    edges.TOP:ClearAllPoints()
    edges.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", cut.TOPLEFT, 0)
    edges.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -cut.TOPRIGHT, 0)
    edges.BOTTOM:ClearAllPoints()
    edges.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", cut.BOTTOMLEFT, 0)
    edges.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -cut.BOTTOMRIGHT, 0)
    edges.LEFT:ClearAllPoints()
    edges.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -cut.TOPLEFT)
    edges.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, cut.BOTTOMLEFT)
    edges.RIGHT:ClearAllPoints()
    edges.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -cut.TOPRIGHT)
    edges.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, cut.BOTTOMRIGHT)
  end
  Mirror(frame)
  -- What sits inside (an icon, the bars) moves in to clear the curve.
  if opts.onShape then pcall(opts.onShape, frame, r) end
end

-- A frame that colours its own border (a unit frame, by class): the curved
-- edge follows.
function skin.SetRimColor(frame, r, g, b, a)
  frame.fuiEdge = { r, g, b, a or 1 }
  local shape = frame.fuiShape
  if shape then
    for _, rim in ipairs(shape.rim) do rim:SetVertexColor(r, g, b, a or 1) end
  end
end

-- A panel that follows the Rounded corners setting from now on.
function skin.Roundable(frame, opts)
  if roundable[frame] then return end
  roundable[frame] = opts or {}
  if not frame.fuiFill and opts and opts.color then
    frame.fuiFill = { Unpack(opts.color) }
  end
  -- The centre is frame.bg: follow whatever is done to it, from the start --
  -- a colour set while the corners are square still counts once they round.
  local bg = frame.bg
  if hooksecurefunc and bg then
    hooksecurefunc(bg, "SetColorTexture", function(_, r, g, b, a)
      frame.fuiFill = { r, g, b, a or 1 }
      Mirror(frame)
    end)
    for _, method in ipairs({ "Show", "Hide", "SetShown", "SetAlpha" }) do
      if type(bg[method]) == "function" then
        hooksecurefunc(bg, method, function() Mirror(frame) end)
      end
    end
  end
  if frame.HookScript then
    pcall(frame.HookScript, frame, "OnSizeChanged", function(self)
      local o = roundable[self]
      if o and skin.CornerRadius(o.group) > 0 then skin.ShapePanel(self) end
    end)
  end
  skin.ShapePanel(frame)
end

-- Rounded corners switched on or off, or the size changed: every panel.
function skin.ApplyCorners()
  for frame in pairs(roundable) do
    pcall(skin.ShapePanel, frame)
  end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local BUTTON_BG     = { 0.14, 0.14, 0.17, 1 }
local BUTTON_HOVER  = { 0.18, 0.20, 0.24, 1 }
local BUTTON_ACTIVE = { 0.10, 0.22, 0.30, 1 }

-- Re-reads the button's state and paints it. Called on hover, click and
-- whenever something else changes `selected`.
local function PaintButton(button)
  local ui = ns.Colors.ui
  accentButtons[button] = true
  -- A button can carry its own palette (the painted options window gives
  -- wood-and-gold ones on the plate, tan ones on parchment).
  local p = button.palette
  if p then
    local state = button.selected and "active" or (button.hovered and "hover" or "idle")
    local c = p[state]
    skin.SetPanelColor(button, c.bg)
    skin.SetBorderColor(button, c.border)
    if not button.keepTextColor then
      button.text:SetTextColor(Unpack(c.text))
      if button.text.SetShadowColor then button.text:SetShadowColor(0, 0, 0, c.shadow or 0.8) end
    end
    return
  end
  if button.selected then
    skin.SetPanelColor(button, BUTTON_ACTIVE)
    skin.SetBorderColor(button, ui.accent)
    button.text:SetTextColor(Unpack(ui.accent))
  elseif button.hovered then
    skin.SetPanelColor(button, BUTTON_HOVER)
    skin.SetBorderColor(button, ui.accent)
    button.text:SetTextColor(Unpack(ui.text))
  else
    skin.SetPanelColor(button, BUTTON_BG)
    skin.SetBorderColor(button, ui.border)
    button.text:SetTextColor(Unpack(ui.text))
  end
end
skin.PaintButton = PaintButton

-- A plain Button, skinned. Its label is a real FontString handed to
-- SetFontString, so button:SetText() works the way callers expect.
function skin.Button(button, opts)
  opts = opts or {}
  skin.Panel(button, { color = BUTTON_BG })

  local text = button:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(text, opts.role or "general")
  text:SetPoint("LEFT", opts.justify == "LEFT" and 8 or 4, 0)
  text:SetPoint("RIGHT", -4, 0)
  text:SetJustifyH(opts.justify or "CENTER")
  button.text = text
  if button.SetFontString then
    button:SetFontString(text)
  end

  button:HookScript("OnEnter", function(self)
    self.hovered = true
    PaintButton(self)
  end)
  button:HookScript("OnLeave", function(self)
    self.hovered = false
    PaintButton(self)
  end)
  PaintButton(button)
  return button
end

skin.PaintButton = PaintButton

function skin.SetSelected(button, selected)
  button.selected = selected and true or false
  PaintButton(button)
end

-- A checkbox: small flat box, accent fill when ticked.
function skin.Checkbox(box)
  skin.Panel(box, { color = BUTTON_BG })

  -- Ticked: the box fills accent and a white check mark sits on it.
  local tick = box:CreateTexture(nil, "ARTWORK")
  tick:SetPoint("TOPLEFT", 1, -1)
  tick:SetPoint("BOTTOMRIGHT", -1, 1)
  tick:SetTexture(WHITE)
  tick:SetVertexColor(Unpack(ns.Colors.ui.accent))
  box.tick = tick
  local mark = box:CreateTexture(nil, "OVERLAY")
  mark:SetPoint("TOPLEFT", -2, 2)
  mark:SetPoint("BOTTOMRIGHT", 2, -2)
  mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  mark:SetVertexColor(1, 1, 1)
  box.mark = mark

  local function paint(self)
    local on = self:GetChecked() and true or false
    tick:SetShown(on)
    mark:SetShown(on)
    -- A caller can give the box its own colours (the painted options window).
    local accent = self.accent or ns.Colors.ui.accent
    tick:SetVertexColor(Unpack(accent))
    skin.SetBorderColor(self, (on or self.hovered) and (self.edgeLit or accent) or (self.edge or ns.Colors.ui.border))
  end
  box.Paint = paint
  box:HookScript("OnEnter", function(self) self.hovered = true; paint(self) end)
  box:HookScript("OnLeave", function(self) self.hovered = false; paint(self) end)
  box:HookScript("OnClick", paint)
  paint(box)
  return box
end

---------------------------------------------------------------------------
-- Icons: the Icons8 Fluent set in Media/icons, white, tinted here
---------------------------------------------------------------------------

-- The glyph for a name: a white PNG from Media/icons, tinted `color` (the
-- accent by default). Flat, one colour, no ring -- the mock-ups' icons.
-- Anything not in the set falls back to the gear so nothing is blank.
function skin.IconPath(name)
  return ns.MEDIA_PATH .. "icons\\" .. (name or "general")
end

function skin.Icon(parent, name, size, color, layer)
  local tex = parent:CreateTexture(nil, layer or "ARTWORK")
  tex:SetSize(size or 18, size or 18)
  tex:SetTexture(skin.IconPath(name))
  local c = color or ns.Colors.ui.accent
  tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  -- No colour asked for means the accent, so it follows the border colour.
  if not color then
    skin.accentTextures[tex] = { alpha = c[4] or 1, mode = "vertex" }
  end
  tex.iconName = name
  return tex
end

function skin.SetIcon(tex, name, color)
  tex:SetTexture(skin.IconPath(name))
  local c = color or ns.Colors.ui.accent
  tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  if not color then
    skin.accentTextures[tex] = { alpha = c[4] or 1, mode = "vertex" }
  end
  tex.iconName = name
end

---------------------------------------------------------------------------
-- Window furniture
---------------------------------------------------------------------------

-- The title strip: emblem, title, close button. Returns the strip so callers
-- can anchor their content beneath it.
function skin.Header(frame, title, onClose)
  local ui = ns.Colors.ui
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(28)
  -- Set a pixel inside the window: round its top two corners to follow the
  -- window's own, a pixel tighter.
  skin.Panel(header, { color = { 0.12, 0.12, 0.15, 1 }, border = false, corners = "top", inset = 1 })

  local line = header:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(ns.Media.Pixel())
  line:SetColorTexture(Unpack(ui.border))

  local logo = header:CreateTexture(nil, "ARTWORK")
  logo:SetSize(30, 15)   -- the mark is 2:1
  logo:SetPoint("LEFT", 8, 0)
  logo:SetTexture(ns.MEDIA_PATH .. "foreverui-logo")
  header.logo = logo

  local text = header:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(text, "header")
  text:SetPoint("LEFT", logo, "RIGHT", 8, 0)
  text:SetText(title)
  text:SetTextColor(Unpack(ui.accent))
  header.text = text

  local close = CreateFrame("Button", nil, header)
  close:SetSize(20, 20)
  close:SetPoint("RIGHT", -5, 0)
  skin.Button(close)
  close:SetText("X")
  close:SetScript("OnClick", onClose or function() frame:Hide() end)
  header.close = close

  frame.header = header
  return header
end

---------------------------------------------------------------------------
-- Walking someone else's frames
---------------------------------------------------------------------------
--
-- Blizzard's frames are named differently between builds, and a hide list
-- written against one client quietly misses on another. Walking what is
-- actually there and matching on what it looks like survives that, which
-- naming frames one by one does not.

-- Some of the game's frames are "forbidden": touching one at all raises
-- "attempt to access forbidden object from code tainted by an AddOn", and
-- that error taints us -- after which our own action buttons stop casting,
-- because casting from a tainted addon is a protected action.
--
-- So nothing is touched without asking first, and every call that reaches
-- into someone else's frame is guarded. A frame we can't read is skipped,
-- which costs nothing: it was never ours to restyle.
function skin.Forbidden(frame)
  if type(frame) ~= "table" then
    return true
  end
  local ok, forbidden = pcall(function()
    return frame.IsForbidden and frame:IsForbidden()
  end)
  return (not ok) or forbidden == true
end

-- Text you may show but not read.
--
-- Forever's secret values are not only numbers: a FontString can hand back a
-- string that may be passed to another widget but not inspected. Calling
-- anything on it -- find, lower, even indexing it -- raises "attempt to index
-- a secret string value", and that error taints us, after which our own
-- action buttons stop casting.
--
-- So text from someone else's frame is only ever read through here, and what
-- comes back is a plain lowercase string that is safe to match on, or
-- nothing. The lowering is the test: whatever the value claims to be, if it
-- survives being read it is a string we may use.
function skin.Text(region)
  if not region or skin.Forbidden(region) or not region.GetText then
    return nil
  end
  local ok, text = pcall(region.GetText, region)
  if not ok or text == nil then
    return nil
  end
  local usable, lowered = pcall(string.lower, text)
  if not usable or type(lowered) ~= "string" then
    return nil
  end
  return lowered
end

function skin.Regions(frame)
  if not frame or skin.Forbidden(frame) or not frame.GetRegions then
    return {}
  end
  local ok, regions = pcall(function()
    return { frame:GetRegions() }
  end)
  if not ok then
    return {}
  end
  local safe = {}
  for _, region in ipairs(regions) do
    if not skin.Forbidden(region) then
      safe[#safe + 1] = region
    end
  end
  return safe
end

function skin.Children(frame)
  if not frame or skin.Forbidden(frame) or not frame.GetChildren then
    return {}
  end
  local ok, children = pcall(function()
    return { frame:GetChildren() }
  end)
  if not ok then
    return {}
  end
  local safe = {}
  for _, child in ipairs(children) do
    if not skin.Forbidden(child) then
      safe[#safe + 1] = child
    end
  end
  return safe
end

-- Depth-first: every frame beneath this one. Depth is capped so a frame that
-- somehow points at itself can't hang the client.
function skin.Walk(frame, visit, depth)
  depth = depth or 0
  if not frame or depth > 8 or skin.Forbidden(frame) then
    return
  end
  visit(frame, depth)
  for _, child in ipairs(skin.Children(frame)) do
    skin.Walk(child, visit, depth + 1)
  end
end

-- Any texture on this frame whose file or atlas name matches one of these
-- patterns. Used to find artwork by what it is rather than what it's called.
function skin.TextureMatches(texture, patterns)
  if skin.Forbidden(texture) then
    return false
  end
  local names = {}
  if texture.GetTexture then
    names[#names + 1] = texture:GetTexture()
  end
  if texture.GetAtlas then
    names[#names + 1] = texture:GetAtlas()
  end
  for _, name in ipairs(names) do
    if type(name) == "string" then
      local lowered = name:lower()
      for _, pattern in ipairs(patterns) do
        if lowered:find(pattern) then
          return true
        end
      end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Getting rid of Blizzard's frames without getting blocked
---------------------------------------------------------------------------
--
-- Some of Blizzard's frames are protected: the action bars, and anything the
-- secure environment manages. Re-parenting or re-anchoring one of those is a
-- protected action, and an addon that attempts it is blocked and *tainted* --
-- after which its own action buttons stop working, because casting from a
-- tainted button is itself a protected action.
--
-- So a protected frame is only made invisible and click-through, which needs
-- no protected call. Everything else is stashed under a hidden parent, where
-- Blizzard's own Show() can't bring it back.

-- THE EDIT MODE TRAP. Every frame Edit Mode manages -- the action bars,
-- the micro menu, the bag bar, the XP bar, the unit frames, the cast bar,
-- the minimap cluster, the quest tracker, the chat window -- swaps its own
-- Hide, SetShown, SetPoint, ClearAllPoints and SetScale for Lua that writes
-- into the Edit Mode manager: dirty flags, anchor records, "snapped-to"
-- lists (hiding the micro menu, for one, re-anchors the bag bar that snaps
-- to it). Called from an addon, those writes carry the addon's taint, and
-- the next layout pass Edit Mode runs -- a level-up fires one -- reads them
-- tainted, updates the quest tracker tainted, and dies reading an aura.
-- The C originals are kept beside the overrides as HideBase, SetPointBase
-- and so on. Those are what this uses: same effect, nothing written.
function skin.Plain(frame, method, ...)
  local base = rawget(frame, method .. "Base")
  local fn = type(base) == "function" and base or frame[method]
  if type(fn) ~= "function" then
    return nil
  end
  return fn(frame, ...)
end

-- Take the mouse off a frame's own buttons.
--
-- Hiding a bar normally takes its buttons with it: a child of a hidden frame
-- is not visible and cannot be clicked. Blizzard's bars do not always stay
-- hidden, though. The game re-shows them on a layout pass, a bar page change,
-- or entering the world, and a bar that comes back brings twelve invisible
-- buttons with it, sitting one frame level above ours and eating the click.
-- Nothing looks wrong, which is what makes it hard to find.
--
-- Taking the mouse off each button means a bar that comes back is still not
-- in the way, and it only has to be done once: EnableMouse survives the frame
-- being hidden and shown again. EnableMouse is not a protected method, so it
-- is allowed on Blizzard's own buttons, and it is guarded anyway.
--
-- This is NOT part of Conceal. Conceal is used on unit frames, the cast bar
-- and the minimap as well, and the first version of this hooked OnShow on
-- every frame it touched so a bar that came back would be quietened again.
-- That runs addon code inside a Blizzard frame's own OnShow -- including
-- while the game is part way through a protected path -- and taints it. The
-- game then blocks the next protected call and says so out loud. Only the
-- action bars need this, so only the action bars ask for it.
-- Local patch (4 Oct 2026): this used to wrap SetCooldown on every child it
-- touched, too. That wrapper is Lua written by us into Blizzard's own cooldown
-- frames, so every Blizzard read of it ran as ForeverUI. The stance, pet and
-- possess bars are among the children, and Edit Mode shows them on the way in
-- (EditModeFrameSetup, before the target and party frames), so the rest of
-- that pass ran tainted: "CompactUnitFrame.lua:699: attempt to compare local
-- 'oldR' (a secret number value, while execution tainted by 'ForeverUI')", and
-- TargetUnit()/FocusUnit() blocked (Logs/taint.log). EnableMouse is a plain C
-- call and writes nothing; the action buttons that sit in the game's shared
-- button loops are still guarded by ActionBars.lua.

local function Deafen(frame)
  if not frame.GetChildren then
    return 0
  end
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if not ok then
    return 0
  end
  local quieted = 0
  for _, child in ipairs(kids) do
    if child and not skin.Forbidden(child) and child.EnableMouse then
      if pcall(child.EnableMouse, child, false) then
        quieted = quieted + 1
      end
    end
  end
  return quieted
end
skin.Deafen = Deafen

-- Out of sight, but still there.
--
-- Conceal hides a frame outright, and a hidden frame cannot be clicked --
-- not even by the game itself. That is right for artwork, and wrong for
-- Blizzard's micro buttons, because our own micro bar forwards its clicks to
-- them (see ForwardClick). A hidden target makes the click go nowhere, which
-- is exactly the bug this pairing exists to avoid.
--
-- Parking keeps the frame shown AND clickable, so a forwarded click still
-- reaches it, and takes away the two things that matter: it is transparent,
-- and it is moved thousands of pixels off screen where no cursor can reach
-- it. Turning its mouse off as well seems tidier and is not: the game
-- refuses to forward a click to a button that cannot be clicked, which left
-- every button on the micro bar dead.
local parked

function skin.Park(frame)
  if not frame or skin.Forbidden(frame) then
    return nil
  end
  -- A micro button the micro bar lays over one of its tiles (the game menu,
  -- which only opens under the mouse). Parking it would undo that.
  if frame.fuiKeepPlace then
    return "kept"
  end
  if not parked then
    parked = CreateFrame("Frame", nil, UIParent)
    parked:SetSize(1, 1)
    -- Far BELOW the bottom-left corner. Shown, so its children stay
    -- reachable. Not above the screen: Blizzard sizes its right-hand action
    -- bars to the space between the minimap and the top of the parked
    -- MicroButtonAndBagsBar (EditModeManager UpdateRightActionBarPositions,
    -- Mainline overrides), and with that 5000 px above the screen the space
    -- came out negative -- "MultiBarRight:SetScale(): Scale must be > 0".
    parked:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -5000, -5000)
    parked:SetAlpha(0)
    skin.parkedParent = parked
  end
  if frame.SetAlpha then frame:SetAlpha(0) end
  -- An Edit Mode frame is only faded, never moved: re-parenting one from
  -- addon code runs the game's layout pass tainted -- which, on Forever,
  -- happens every time the controller takes over (the micro menu anchors
  -- the controller's action bar). As Conceal does.
  if frame.isManagedFrame then
    return "faded"
  end
  -- The mouse is deliberately LEFT ON. A secure click forwarded to this
  -- button is refused if the button cannot take a mouse click, so turning it
  -- off here is what stopped every micro bar button working. It costs
  -- nothing to leave on: the frame is transparent and parked thousands of
  -- pixels off the screen, where no cursor will ever reach it.
  local protected = frame.IsProtected and frame:IsProtected()
  if not protected and frame.SetParent then
    pcall(frame.SetParent, frame, parked)
    if frame.ClearAllPoints then
      pcall(skin.Plain, frame, "ClearAllPoints")
      pcall(skin.Plain, frame, "SetPoint", "CENTER", parked, "CENTER", 0, 0)
    end
  end
  return "parked"
end

-- Hand a click to one of Blizzard's own buttons instead of calling the
-- game's function ourselves.
--
-- Opening a panel -- the character sheet, the quest log, the world map --
-- goes through Blizzard's panel manager, and the manager writes into its own
-- tables as it works. Do that from inside our click and those tables are
-- tainted from then on. On Forever that matters far more than usual: the
-- game only lets its own code compare a secret value while the execution is
-- untainted, so once the panel manager is poisoned, opening the character
-- sheet throws on its own status bar text, and so does pressing C.
--
-- A secure button with "clickbutton" set lets the game run its own button in
-- its own path, with none of our Lua on the stack. The button has to have
-- been created from a secure template for this to take; when there is no
-- Blizzard button of that name to forward to, the caller's fallback is used
-- and the taint is accepted, because a window that never opens is worse.
--
-- The target must be left clickable -- see Park.

-- When there is no Blizzard button to forward to, ForeverUI does NOT open
-- the window itself -- not even as a fallback. Every one of these goes
-- through the panel manager (ShowUIPanel), and one call from addon code
-- leaves its records carrying our taint: the next time the player presses
-- C, the character sheet's health text dies on a secret number, and Edit
-- Mode's party frames on a secret colour (mattp25_ on CurseForge, 27 Sept
-- 2026, both "execution tainted by 'ForeverUI'"). The key does it cleanly,
-- so say which key.
local WINDOWS = {
  character   = { "TOGGLECHARACTER0", "the character sheet" },
  spellbook   = { "TOGGLESPELLBOOK", "the spellbook" },
  talents     = { "TOGGLETALENTS", "talents" },
  professions = { "TOGGLEPROFESSIONBOOK", "professions" },
  questlog    = { "TOGGLEQUESTLOG", "the quest log" },
  map         = { "TOGGLEWORLDMAP", "the world map" },
  friends     = { "TOGGLESOCIAL", "the friends list" },
  guild       = { "TOGGLEGUILDTAB", "the guild window" },
  lfg         = { "TOGGLEGROUPFINDER", "Looking for Group" },
  legacy      = { "TOGGLELEGACYSYSTEM", "Legacy progress" },
  menu        = { "TOGGLEGAMEMENU", "the game menu" },
  editmode    = { nil, "Edit Mode", "open the game menu (Esc) and choose Edit Mode" },
  cooldowns   = { nil, "the Cooldown Manager's settings", "open them from the game menu (Esc) - Options or Edit Mode" },
}
skin.WINDOWS = WINDOWS

function skin.OpenHint(kind)
  local window = WINDOWS[kind]
  if not window then
    return false
  end
  local how = window[3]
  local key = window[1] and GetBindingKey and GetBindingKey(window[1])
  if key then
    how = ("press %s"):format(GetBindingText and GetBindingText(key) or key)
  end
  ns.Print(("To open %s, %s."):format(window[2], how or "use its key"))
  return true
end

function skin.ForwardClick(button, microName, fallback)
  local target = type(microName) == "table" and microName or (microName and rawget(_G, microName))
  if target and button.SetAttribute then
    button.microTarget = target
    -- Attributes are protected in combat; this runs at login, but a /reload
    -- mid-fight would land here, so it waits rather than throwing.
    ns.WhenOutOfCombat(function()
      button:SetAttribute("type", "click")
      button:SetAttribute("clickbutton", target)
      -- Act on the release these buttons hear, whatever the game's "cast on
      -- key down" says -- otherwise the press is never forwarded at all
      -- (the micro bar found this on 22 Sept 2026, MicroBar.lua).
      button:SetAttribute("useOnKeyDown", false)
    end)
    return true
  end
  if fallback then
    button:SetScript("OnClick", fallback)
  end
  return false
end

-- Blizzard buttons whose own click opens a window, so a click of ours can
-- be handed to them (sprutorgel on CurseForge, 29 Sept 2026: the map, the
-- quest log and Legacy used to open directly; since the panel-manager fix
-- they only named the key). Found against the forever branch:
--   questlog  QuestLogMicroButton -- on Forever's micro menu
--             (Blizzard_MicroMenu Camelot overrides)
--   map       no WorldMapMicroButton on Forever; the minimap's zone name
--             is a button whose OnClick is ToggleWorldMap()
--             (Blizzard_Minimap/Mainline/Minimap.lua:105, .xml:34). It
--             needn't be visible or take the mouse: Click() still runs it.
--   legacy    LegacyMicroButton -- disabled until a character has Legacy
--             progress, and a disabled button ignores the click, so then
--             the key is named instead.
-- The friends list has no such button: the micro bar's Social tile runs the
-- game's own /friends in a secure macro instead, and stops first when a
-- player is targeted (there /friends adds or removes them as a friend).
local OPENERS = {
  questlog = { "QuestLogMicroButton" },
  map = { "WorldMapMicroButton", function()
    local cluster = rawget(_G, "MinimapCluster")
    return type(cluster) == "table" and rawget(cluster, "ZoneTextButton") or nil
  end },
  legacy = { "LegacyMicroButton" },
}
skin.OPENERS = OPENERS

function skin.OpenerFor(kind)
  for _, source in ipairs(OPENERS[kind] or {}) do
    local frame
    if type(source) == "function" then
      local ok, found = pcall(source)
      frame = ok and found or nil
    else
      frame = rawget(_G, source)
    end
    if type(frame) == "table" and frame.Click then return frame end
  end
  return nil
end

-- Make `button` open `kind`'s window through Blizzard's own button. `after`
-- (optional) runs once the window has had its chance -- in PostClick, never
-- before: our Lua ahead of the forwarded click would run the game's opening
-- code tainted, the very thing this avoids. If the Blizzard button refuses
-- (disabled, or none on this client), the key is named instead. `button`
-- must be made from SecureActionButtonTemplate.
function skin.ForwardOpen(button, kind, after)
  local target = skin.OpenerFor(kind)
  if target and button.SetAttribute and button.HookScript then
    if button.RegisterForClicks then button:RegisterForClicks("AnyUp") end
    skin.ForwardClick(button, target)
    button:HookScript("PostClick", function()
      if target.IsEnabled and not target:IsEnabled() then skin.OpenHint(kind) end
      if after then after() end
    end)
    return true
  end
  button:SetScript("OnClick", function()
    skin.OpenHint(kind)
    if after then after() end
  end)
  return false
end

-- The same for a plain button inside a window we show and hide in a fight
-- (the quest guide's "Map" and "Blizzard's log"). A secure button inside
-- that window would make the whole window protected -- no showing it,
-- hiding it or moving it in combat -- so the window's buttons stay plain,
-- and ONE invisible secure button is laid over whichever of them the
-- pointer is on. It is placed by screen position, never anchored to the
-- window (an anchor would make the window protected too), and only out of
-- combat; in a fight the plain button names the key as before.
local openOverlay
local function OpenOverlay()
  if openOverlay then return openOverlay end
  local o = CreateFrame("Button", "ForeverUIOpenOverlay", UIParent, "SecureActionButtonTemplate")
  if o.RegisterForClicks then o:RegisterForClicks("AnyUp") end
  o:SetAlpha(0)
  o:Hide()
  o:SetScript("OnEnter", function(self)
    local enter = self.host and self.host:GetScript("OnEnter")
    if enter then pcall(enter, self.host) end
  end)
  o:SetScript("OnLeave", function(self)
    local host = self.host
    local leave = host and host:GetScript("OnLeave")
    if leave then pcall(leave, host) end
    ns.WhenOutOfCombat(function() if not self:IsMouseOver() then self:Hide() end end)
  end)
  o:HookScript("PostClick", function(self)
    local target, kind, after = self.target, self.kind, self.after
    if target and target.IsEnabled and not target:IsEnabled() then skin.OpenHint(kind) end
    if after then pcall(after) end
  end)
  openOverlay = o
  return o
end
skin.OpenOverlay = OpenOverlay

local function PlaceOverlay(host, kind, after)
  if InCombatLockdown and InCombatLockdown() then return false end
  local target = skin.OpenerFor(kind)
  if not target then return false end
  local ok, l, b, w, h = pcall(host.GetRect, host)
  if not (ok and tonumber(l) and tonumber(b) and tonumber(w) and tonumber(h)) then return false end
  local ratio = (host:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local o = OpenOverlay()
  o.host, o.kind, o.after, o.target = host, kind, after, target
  o:ClearAllPoints()
  o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
  o:SetSize(w * ratio, h * ratio)
  o:SetFrameStrata(host:GetFrameStrata())
  o:SetFrameLevel((host:GetFrameLevel() or 1) + 20)
  o:SetAttribute("type", "click")
  o:SetAttribute("clickbutton", target)
  o:SetAttribute("useOnKeyDown", false)
  o:Show()
  return true
end
skin.PlaceOverlay = PlaceOverlay

-- `host` is a plain button: pointing at it lays the secure overlay on it,
-- clicking it (in a fight, or when there is no Blizzard button) names the key.
function skin.OpenOver(host, kind, after)
  host:HookScript("OnEnter", function(self) PlaceOverlay(self, kind, after) end)
  host:HookScript("OnHide", function()
    if openOverlay and openOverlay.host == host then
      ns.WhenOutOfCombat(function() if openOverlay.host == host then openOverlay:Hide() end end)
    end
  end)
  host:SetScript("OnClick", function()
    skin.OpenHint(kind)
    if after then after() end
  end)
end

-- A faded frame stays faded: Blizzard paints alpha back on some of these
-- (range checks, vehicle swaps, Edit Mode), so each SetAlpha it makes is
-- followed by ours, back to 0.
local zeroing = false
local function KeepFaded(frame)
  if zeroing or not rawget(frame, "fuiConcealed") then
    return
  end
  zeroing = true
  pcall(frame.SetAlpha, frame, 0)
  zeroing = false
end

local function Fade(frame)
  frame.fuiConcealed = true
  if hooksecurefunc and frame.SetAlpha and not rawget(frame, "fuiFadeHook") then
    frame.fuiFadeHook = true
    hooksecurefunc(frame, "SetAlpha", KeepFaded)
  end
  if frame.SetAlpha then
    frame:SetAlpha(0)
  end
  if frame.EnableMouse then
    pcall(frame.EnableMouse, frame, false)
  end
  return "faded"
end
skin.KeepFaded = KeepFaded
skin.Fade = Fade

function skin.Conceal(frame, hiddenParent)
  if not frame or skin.Forbidden(frame) then
    return nil
  end
  if frame.UnregisterAllEvents then
    frame:UnregisterAllEvents()
  end
  -- A frame UIParent's frame manager lays out (the right-hand action bars,
  -- the pet and stance bars, the quest tracker): hiding it -- even with the
  -- C original, and re-parenting it under a hidden frame just the same --
  -- fires its OnHide, which takes it off the manager's list from inside our
  -- code. The manager's tables carry our taint from then on, the next Edit
  -- Mode layout pass reads them, and on Forever that pass updates the quest
  -- tracker tainted and dies reading an aura (26 Sept 2026). So these are
  -- faded and made deaf where they stand; nothing is hidden or moved.
  if frame.isManagedFrame then
    return Fade(frame)
  end
  -- Local patch (4 Oct 2026): every Edit Mode system frame is faded too (the
  -- bag bar, the cast bar, the status-tracking manager...). HideBase only
  -- skips Edit Mode's Hide override; the frame's OnHide still runs Edit Mode
  -- Lua from inside our call, and SetParent hides its children the same way.
  -- What that writes -- snapped-frame records among them -- carried our taint
  -- into every later Edit Mode pass. Systems are the frames Edit Mode gave a
  -- HideBase.
  if rawget(frame, "HideBase") ~= nil or rawget(frame, "system") ~= nil then
    return Fade(frame)
  end
  -- Protected frames -- Blizzard's player, target, target-of-target, focus
  -- and pet frames, the action bars -- are faded and made deaf too, never
  -- hidden. Their parent and points can't be touched, and hiding them fires
  -- their OnHide from inside our code: the target-of-target's OnHide
  -- reconfigures the TARGET frame's aura container, so the target frame
  -- carried our taint, Edit Mode read it on the way in and out, and the
  -- rest of that pass ran as ForeverUI -- Blizzard's party frames redrawn
  -- under our name ("CompactUnitFrame.lua:699 ... secret number value ...
  -- tainted by 'ForeverUI'", sprutorgel and Altiokis), their events signed
  -- up as ours, and the same error again at the flight master.
  local protected = frame.IsProtected and frame:IsProtected()
  if protected then
    return Fade(frame)
  end
  if frame.Hide then
    skin.Plain(frame, "Hide")
  end
  if frame.SetParent and hiddenParent then
    frame:SetParent(hiddenParent)
  end
  return "hidden"
end

-- What the mouse is over. Recent clients replaced GetMouseFocus() with
-- GetMouseFoci(), which returns a list; calling the old one on a client that
-- has dropped it returns nil every time, which reads as "nothing" and is a lie.
function skin.MouseFocus()
  if GetMouseFoci then
    local ok, foci = pcall(GetMouseFoci)
    if ok and type(foci) == "table" and foci[1] then
      return foci[1], foci
    end
  end
  if GetMouseFocus then
    local ok, focus = pcall(GetMouseFocus)
    if ok and focus then
      return focus, { focus }
    end
  end
  return nil, {}
end

-- Keep a window inside the screen. At a high UI scale a fixed 720x560 panel
-- can be taller than the viewport, so shrink it rather than let it run off.
function skin.FitToScreen(frame, margin)
  margin = margin or 0.9
  local width, height = frame:GetWidth(), frame:GetHeight()
  local availableWidth = UIParent:GetWidth() or width
  local availableHeight = UIParent:GetHeight() or height
  if not width or not height or width <= 0 or height <= 0 then
    return 1
  end
  local scale = math.min(1, (availableWidth * margin) / width, (availableHeight * margin) / height)
  frame:SetScale(scale)
  return scale
end

---------------------------------------------------------------------------
-- A sliding switch
---------------------------------------------------------------------------

-- On/off where the answer has to be readable at a glance from across the
-- window: a short track with a knob that slides to the lit end and takes the
-- track's colour with it. The checkbox above is for a settings page you are
-- reading; this is for a row you are scanning.
--
-- `color` is the role's own -- green for healing, orange for tanking, red for
-- damage -- so an on switch says WHICH thing is on, not merely that one is.
function skin.Switch(parent, color, onToggle)
  local sw = CreateFrame("Button", nil, parent)
  sw:SetSize(28, 14)
  skin.Panel(sw, { color = { 0.16, 0.16, 0.19, 1 } })

  local knob = sw:CreateTexture(nil, "OVERLAY")
  knob:SetSize(10, 10)
  sw.knob = knob
  sw.color = { color[1], color[2], color[3], color[4] or 1 }

  function sw:SetOn(on)
    self.on = on and true or false
    local c = self.color
    knob:ClearAllPoints()
    if self.on then
      knob:SetPoint("RIGHT", -2, 0)
      knob:SetColorTexture(c[1], c[2], c[3], 1)
      -- The track darkens towards the same hue rather than filling with it:
      -- a solid bar behind a bright knob loses the knob.
      skin.SetPanelColor(self, { c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1 })
      skin.SetBorderColor(self, c)
    else
      knob:SetPoint("LEFT", 2, 0)
      knob:SetColorTexture(0.42, 0.42, 0.47, 1)
      skin.SetPanelColor(self, { 0.16, 0.16, 0.19, 1 })
      skin.SetBorderColor(self, ns.Colors.ui.border)
    end
    return self.on
  end

  sw:SetScript("OnClick", function(self)
    self:SetOn(not self.on)
    if onToggle then
      onToggle(self.on)
    end
  end)
  sw:SetOn(false)
  return sw
end
