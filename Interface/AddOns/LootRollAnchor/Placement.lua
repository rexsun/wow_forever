local _, ns = ...

local Placement = {}
ns.Placement = Placement

local function EarlierBottom(a, b)
  return a.bottom < b.bottom
end

-- All values share one coordinate space. Obstacles that overlap the roll column are stepped over
-- from the lowest up, so the stack takes the lowest free slot at or above floor.
function Placement.Bottom(spec)
  local obstacles = {}
  for i, rect in ipairs(spec.obstacles) do obstacles[i] = rect end
  table.sort(obstacles, EarlierBottom)
  local left, right = spec.center - spec.halfWidth, spec.center + spec.halfWidth
  local bottom = spec.floor
  for _, rect in ipairs(obstacles) do
    if left < rect.right and right > rect.left
      and bottom < rect.top + spec.gap and bottom + spec.height + spec.gap > rect.bottom then
      bottom = rect.top + spec.gap
    end
  end
  return math.min(bottom, spec.ceiling - spec.height)
end
