-- QuestForever on the game's own tooltips: hover a mob, an NPC or an object
-- in the world and it says which of your quests it is for, and how far along
-- you are -
--
--   Kobold Vermin
--   Level 3
--   The Fargodeep Mine
--     Kobold Vermin slain: 3/10
--
-- - and a quest giver says which quests they have for you. Matched by name,
-- not by the unit's ID: names are what Forever still hands an addon.

local QF = QuestForever
local D = QF.data

local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.9, 0.9, 0.9 }
local BLUE = { 0.3, 0.76, 1 }

local function Secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

-- name -> { {quest, step}, ... } for your unfinished objectives. Rebuilt
-- after anything changes (the log, a kill, a loot).
local byName, dirty = {}, true
QF.OnChange(function() dirty = true end)

local function Index()
  if not dirty then return byName end
  dirty = false
  byName = {}
  for id, state in pairs(QF.inLog) do
    local q = QF.Quest(id)
    if q and not state.complete then
      for _, step in ipairs(QF.HowTo(q, state)) do
        if not step.done then
          for _, name in ipairs(step.names or {}) do
            local key = name:lower()
            local list = byName[key]
            if not list then list = {}; byName[key] = list end
            list[#list + 1] = { quest = q, step = step }
          end
        end
      end
    end
  end
  return byName
end

-- name -> quest ids it starts; and which names are objects. Built once.
local starters, objects
local function Starters()
  if starters then return starters end
  starters, objects = {}, {}
  for _, rec in pairs(D.O) do objects[rec[1]:lower()] = true end
  for id, raw in pairs(D.Q) do
    if raw[8] then
      for kind, ref in raw[8]:gmatch("([no])(%d+)") do
        local name = QF.Name(kind, tonumber(ref))
        if name then
          local key = name:lower()
          local list = starters[key]
          if not list then list = {}; starters[key] = list end
          list[#list + 1] = id
        end
      end
    end
  end
  return starters
end

-- The lines for a name: { {text, color}, ... }
function QF.TooltipLines(name)
  local out = {}
  if type(name) ~= "string" or name == "" then return out end
  local key = name:lower()
  local shown = {}
  for _, e in ipairs(Index()[key] or {}) do
    if not shown[e.quest.id] then
      shown[e.quest.id] = true
      out[#out + 1] = { e.quest.name, GOLD }
    end
    local step = e.step
    local text = step.progress or step.text
    if step.item and not step.progress then text = "Loot " .. step.item end
    out[#out + 1] = { "  " .. text, WHITE }
  end
  local offers = 0
  for _, id in ipairs(Starters()[key] or {}) do
    local q = QF.Quest(id)
    if q and QF.IsAvailable(q) then
      offers = offers + 1
      if offers <= 4 then
        out[#out + 1] = { "! " .. q.name, BLUE }
      end
    end
  end
  if offers > 4 then out[#out + 1] = { ("! ...and %d more quests"):format(offers - 4), BLUE } end
  return out
end

-- For a nameplate (ForeverUI; Gnatz_0815 on CurseForge, 2026: "a counter on
-- the nameplate how many kills are left"): what this mob still counts for,
-- as short as the plate needs -- the count from the game's own objective
-- line ("Kobold Vermin slain: 3/10" -> "3/10"), one per objective, at most
-- two. Nil when it counts for nothing unfinished, or the step has no count
-- (talk to, use) -- a plate tag should mean "kill or loot this".
function QF.PlateProgress(name)
  if not QF.running then return nil end
  if type(name) ~= "string" or Secret(name) or name == "" then return nil end
  local list = Index()[name:lower()]
  if not list then return nil end
  local counts, seen = {}, {}
  for _, e in ipairs(list) do
    local text = e.step.progress
    local have, need = nil, nil
    if type(text) == "string" then have, need = text:match("(%d+)%s*/%s*(%d+)%s*$") end
    if have and tonumber(have) < tonumber(need) then
      local count = have .. "/" .. need
      if not seen[count] and #counts < 2 then
        seen[count] = true
        counts[#counts + 1] = count
      end
    end
  end
  if #counts == 0 then return nil end
  return table.concat(counts, "  ")
end

function QF.IsObjectName(name)
  Starters()
  return type(name) == "string" and objects[name:lower()] == true
end

local function Add(tooltip, name)
  if not QF.running or not QF.Setting("tooltips") then return end
  if Secret(name) then return end
  local lines = QF.TooltipLines(name)
  if #lines == 0 then return end
  for _, l in ipairs(lines) do
    tooltip:AddLine(l[1], l[2][1], l[2][2], l[2][3])
  end
  tooltip:Show()
end

-- Mobs and NPCs.
local function OnUnit(tooltip)
  if tooltip ~= GameTooltip then return end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  unit = (ok and unit) or "mouseover"
  local okP, isPlayer = pcall(UnitIsPlayer, unit)
  if not okP or Secret(isPlayer) or isPlayer then return end
  local okN, name = pcall(UnitName, unit)
  -- A secret name can't be looked up (or even tested): no quest lines then.
  if okN and type(name) == "string" and not Secret(name) then Add(tooltip, name) end
end
QF.OnUnitTooltip = OnUnit

-- Objects in the world (a chest, a poster, a plant): a short tooltip with no
-- unit, whose first line is the object's name.
local function OnShow(tooltip)
  if tooltip.questForeverDone then return end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if ok and unit then return end
  if tooltip.NumLines and tooltip:NumLines() > 3 then return end
  local first = _G[(tooltip:GetName() or "GameTooltip") .. "TextLeft1"]
  local okT, name = pcall(function() return first and first:GetText() end)
  if not okT or not name or Secret(name) or not QF.IsObjectName(name) then return end
  tooltip.questForeverDone = true
  Add(tooltip, name)
end
QF.OnObjectTooltip = OnShow

if GameTooltip then
  local post = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
  local types = Enum and Enum.TooltipDataType
  if post and types and types.Unit then
    post(types.Unit, OnUnit)
  elseif GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
  end
  if GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", OnShow)
    GameTooltip:HookScript("OnHide", function(tooltip) tooltip.questForeverDone = nil end)
  end
end
