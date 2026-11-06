local _, ns = ...

local PREFIX = "|cff66ccffLootRollAnchor|r"
local PLACER_OWNER = "cdm"
-- In UIParent units: the stack's lowest spot when nothing is in the way, and the space kept
-- between it and a YUI bar or HUD group.
local BASE_OFFSET = 120
local GAP = 8
-- Roll window artwork is wider than GroupLootContainer.
local ROLL_ART_WIDTH = 286

local registered = false
local warned = false

local function Public(value)
  return not (issecretvalue and issecretvalue(value))
end

local function Read(frame, method, ...)
  if not frame or type(frame[method]) ~= "function" then return false end
  local ok, a, b, c, d = pcall(frame[method], frame, ...)
  if not ok or not Public(a) or not Public(b) or not Public(c) or not Public(d) then return false end
  return true, a, b, c, d
end

local function Number(value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
  return value
end

-- Returns false when a rect cannot be read safely, so the placer retries after combat.
local function AddRect(list, frame, uiScale)
  local ok, shown = Read(frame, "IsShown")
  if not ok then return false end
  if not shown then return true end
  local got, left, bottom, width, height = Read(frame, "GetRect")
  local scaled, scale = Read(frame, "GetEffectiveScale")
  left, bottom, width, height = Number(left), Number(bottom), Number(width), Number(height)
  scale = scaled and Number(scale)
  if not got or not scaled then return false end
  if not (left and bottom and width and height and scale) or width <= 0 or height <= 0 or scale <= 0 then
    return true
  end
  local k = scale / uiScale
  list[#list + 1] = { left = left * k, right = (left + width) * k, bottom = bottom * k, top = (bottom + height) * k }
  return true
end

local function YUIFrames()
  local frames = {}
  local yui = _G.YUI
  local bars = yui and yui.YActionBar and yui.YActionBar.BarManager
  for _, record in pairs(bars and type(bars.bars) == "table" and bars.bars or {}) do
    if type(record) == "table" and record.holder then frames[#frames + 1] = record.holder end
  end
  local view = yui and yui.YHUD and yui.YHUD.View
  for _, runtime in pairs(view and type(view.groups) == "table" and view.groups or {}) do
    if type(runtime) == "table" and runtime.frame then frames[#frames + 1] = runtime.frame end
  end
  return frames
end

local function RollWidth()
  local ok, width = Read(_G.GroupLootFrame1, "GetWidth")
  width = ok and Number(width) or 0
  return math.max(width, ROLL_ART_WIDTH)
end

function ns.Compute(container)
  local okUI, uiScale = Read(UIParent, "GetEffectiveScale")
  local okW, uiWidth = Read(UIParent, "GetWidth")
  local okH, uiHeight = Read(UIParent, "GetHeight")
  local okC, containerScale = Read(container, "GetEffectiveScale")
  local okR, height = Read(container, "GetHeight")
  uiScale, uiWidth, uiHeight = Number(uiScale), Number(uiWidth), Number(uiHeight)
  containerScale, height = Number(containerScale), Number(height)
  if not (okUI and okW and okH and okC and okR) then return false end
  if not (uiScale and uiWidth and uiHeight and containerScale and height) or uiScale <= 0 or containerScale <= 0 then
    return false
  end
  local obstacles = {}
  for _, frame in ipairs(YUIFrames()) do
    if not AddRect(obstacles, frame, uiScale) then return false end
  end
  local bottom = ns.Placement.Bottom({
    obstacles = obstacles, center = uiWidth / 2, halfWidth = RollWidth() / 2,
    floor = BASE_OFFSET, gap = GAP, height = math.max(height, 1), ceiling = uiHeight,
  })
  return bottom, #obstacles, height, uiScale / containerScale
end

local function Place(container)
  local bottom, obstacles, height, toContainer = ns.Compute(container)
  if not bottom then return false end
  local db = LootRollAnchorDB
  if type(db) == "table" then
    db.placements = (db.placements or 0) + 1
    db.last = { at = time(), bottom = bottom, obstacles = obstacles, height = height }
  end
  return "BOTTOM", UIParent, "BOTTOM", 0, bottom * toContainer
end

local function Register()
  if registered then return true end
  local container = _G.GroupLootContainer
  local eui = _G.EllesmereUI
  if not container then return false end
  if not (eui and type(eui.SetFramePlacer) == "function") then
    if not warned then
      warned = true
      print(PREFIX, "EllesmereUI frame placement is unavailable; loot rolls keep Blizzard's position.")
    end
    return false
  end
  registered = eui.SetFramePlacer(container, PLACER_OWNER, Place) == true
  if not registered and not warned then
    warned = true
    print(PREFIX, "EllesmereUI refused to place GroupLootContainer; loot rolls keep Blizzard's position.")
  end
  return registered
end

local function Describe(frame)
  local ok, count = Read(frame, "GetNumPoints")
  if not ok or not count or count == 0 then return "no anchor" end
  local got, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
  if not got or not Public(point) or not Public(x) or not Public(y) then return "secret anchor" end
  local name = relative and relative.GetName and relative:GetName() or tostring(relative)
  return ("%s %s %s %.1f %.1f"):format(tostring(point), tostring(name), tostring(relativePoint), x or 0, y or 0)
end

SLASH_LOOTROLLANCHOR1 = "/lra"
SlashCmdList.LOOTROLLANCHOR = function()
  local container = _G.GroupLootContainer
  print(PREFIX, registered and "placing GroupLootContainer" or "not placing (Blizzard position)")
  if container then
    local _, shown = Read(container, "IsShown")
    print(("  container: %s, %s"):format(shown and "shown" or "hidden", Describe(container)))
  end
  local bottom, obstacles, height = ns.Compute(container or UIParent)
  if bottom then
    print(("  computed bottom %.1f above %d YUI frames, stack height %.1f"):format(bottom, obstacles, height))
  else
    print("  position cannot be computed now (secret or missing values)")
  end
  local db = LootRollAnchorDB
  if type(db) == "table" and db.last then
    print(("  placements this account: %d, last bottom %.1f"):format(db.placements or 0, db.last.bottom or 0))
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == "LootRollAnchor" then
    if type(LootRollAnchorDB) ~= "table" then LootRollAnchorDB = {} end
  end
  if (event == "PLAYER_LOGIN" or event == "ADDON_LOADED") and Register() then
    self:UnregisterAllEvents()
  end
end)
