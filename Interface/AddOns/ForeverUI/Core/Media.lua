local ADDON_FOLDER, ns = ...

-- Fonts, bar textures and borders by name. Modules ask for "font.unitName"
-- rather than a file path, so a theme or a user choice changes everything at
-- once. LibSharedMedia is used if another addon has already loaded it; we
-- don't bundle it.

local media = {}
ns.Media = media

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

media.fonts = {
  ["Friz Quadrata"] = DEFAULT_FONT,
  ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
  ["Skurri"]        = "Fonts\\skurri.ttf",
  ["Morpheus"]      = "Fonts\\MORPHEUS.ttf",
}

media.textures = {
  ["Blizzard"]  = "Interface\\TargetingFrame\\UI-StatusBar",
  ["Raid"]      = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
  ["Flat"]      = "Interface\\Buttons\\WHITE8X8",
}

-- ForeverUI's own bars, the set the party grids use, offered everywhere a
-- bar texture can be picked. Saved by NAME, never by path: a path names the
-- addon's folder, and the folder is not the same on every machine.
do
  local folder = ADDON_FOLDER or "ForeverUI"
  local base = "Interface\\AddOns\\" .. folder .. "\\Modules\\Frames\\Media\\"
  for name, file in pairs({ Smooth = "bar-smooth", Glossy = "bar-glossy", Gradient = "bar-gradient",
      Ridged = "bar-ridged", Dim = "bar-dim", Minimal = "bar-flat" }) do
    media.textures[name] = base .. file
  end
  -- The painted fills (ChatGPT art, grey so a bar's colour tints them).
  for _, file in ipairs({ "sheen", "vines", "energy", "swirl", "metal", "runic", "marble", "heartbeat", "honeycomb", "dotted", "starry", "braid" }) do
    media.textures[file:sub(1, 1):upper() .. file:sub(2)] = base .. "fill-" .. file
  end
end

media.borders = {
  ["Thin"]    = "Interface\\Buttons\\WHITE8X8",
  ["None"]    = nil,
}

-- Where each kind of text gets its size and outline from. Modules name a role
-- ("unitName"), not a font file.
-- Narrow by default: Arial Narrow at a size below Blizzard's, so more fits
-- and the panels read cleaner. Any font can be chosen in the options; these
-- are just the starting point.
media.roles = {
  general    = { font = "Arial Narrow", size = 12, outline = "" },
  header     = { font = "Arial Narrow", size = 13, outline = "" },
  unitName   = { font = "Arial Narrow", size = 10, outline = "" },
  unitHealth = { font = "Arial Narrow", size = 10, outline = "" },
  groupName  = { font = "Arial Narrow", size = 9,  outline = "" },
  aura       = { font = "Arial Narrow", size = 8,  outline = "OUTLINE" },
  cooldown   = { font = "Arial Narrow", size = 11, outline = "OUTLINE" },
  dataText   = { font = "Arial Narrow", size = 10, outline = "" },
  tooltip    = { font = "Arial Narrow", size = 11, outline = "" },
}

local LSM

function ns.InitMedia()
  if LibStub then
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    LSM = ok and lib or nil
  end
  if LSM then
    -- Offer ours to everyone else, and take what other addons registered.
    for name, path in pairs(media.fonts) do
      LSM:Register("font", name, path)
    end
    for name, path in pairs(media.textures) do
      LSM:Register("statusbar", name, path)
    end
  end
end

local function Lookup(kind, list, name, fallback)
  if LSM and name then
    local found = LSM:Fetch(kind, name, true)
    if found then
      return found
    end
  end
  return list[name] or fallback
end

function media.FontPath(name)
  return Lookup("font", media.fonts, name, DEFAULT_FONT)
end

function media.TexturePath(name)
  return Lookup("statusbar", media.textures, name, media.textures.Blizzard)
end

-- Names for the options window; includes anything LibSharedMedia knows about.
function media.List(kind)
  local names = {}
  local own = kind == "font" and media.fonts or media.textures
  for name in pairs(own) do
    names[#names + 1] = name
  end
  if LSM then
    for _, name in ipairs(LSM:List(kind == "font" and "font" or "statusbar")) do
      if not own[name] then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)
  return names
end

-- The settings override the role defaults: one global font and size, with a
-- per-role size offset kept simple by just storing the role's own values.
function media.Role(role)
  local fromDb = ns.db and ns.db.media and ns.db.media.roles and ns.db.media.roles[role]
  local base = media.roles[role] or media.roles.general
  local font = (fromDb and fromDb.font) or (ns.db and ns.db.media and ns.db.media.font) or base.font
  local size = (fromDb and fromDb.size) or base.size
  local outline = (fromDb and fromDb.outline) or base.outline
  return media.FontPath(font), size, outline
end

-- Apply a role's font to a FontString. Modules call this and nothing else.
function media.SetFont(fontString, role)
  if not fontString then
    return
  end
  local path, size, outline = media.Role(role)
  -- Flags must be a string. A FontString tolerates nil for "no outline";
  -- an EditBox does not -- it raises "bad argument #3 to SetFont" -- so
  -- pass the empty string, which both accept.
  fontString:SetFont(path, size, outline or "")
end

function media.StatusBarTexture()
  local name = ns.db and ns.db.media and ns.db.media.texture
  return media.TexturePath(name)
end

-- One pixel, whatever the UI scale is, so thin borders stay thin.
function media.Pixel()
  local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if scale <= 0 then
    return 1
  end
  return math.max(1, math.floor(1 / scale + 0.5))
end
