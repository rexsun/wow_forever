local _, OSG = ...

-- The rule engine. It calls no game API itself, so tools/overlapsettingsguard-tests
-- can run it outside the game.
--
-- An adapter is a table with:
--   Knows(key)            true when it can handle this setting key
--   Read(key)             true (on) / false (off), or nil plus a reason when it cannot tell
--   Revert(key, rule)     true plus whether a reload is needed, or false plus a reason
--   Watch(onChange)       hook the add-on so onChange runs when its settings may have changed
OSG.adapters = {}

OSG.STATUS = {
  ON = "on",
  OFF = "off",
  INACTIVE = "inactive",
  BLOCKED = "blocked",
}

function OSG.EvaluateRule(rule, adapters, isLoaded)
  for _, name in ipairs(rule.when) do
    if not isLoaded(name) then
      return { rule = rule, status = OSG.STATUS.INACTIVE, detail = name .. " is not loaded" }
    end
  end
  local adapter = adapters[rule.adapter]
  if not adapter then
    return { rule = rule, status = OSG.STATUS.BLOCKED, detail = "no adapter named " .. tostring(rule.adapter) }
  end
  local ok, value, problem = pcall(adapter.Read, rule.key)
  if not ok then
    return { rule = rule, status = OSG.STATUS.BLOCKED, detail = tostring(value) }
  end
  if value == nil then
    return { rule = rule, status = OSG.STATUS.BLOCKED, detail = problem or "cannot read the setting" }
  end
  return { rule = rule, status = value and OSG.STATUS.ON or OSG.STATUS.OFF }
end

function OSG.Evaluate(policy, adapters, isLoaded)
  local results = {}
  for _, rule in ipairs(policy) do
    results[#results + 1] = OSG.EvaluateRule(rule, adapters, isLoaded)
  end
  return results
end

function OSG.Violations(results)
  local rules = {}
  for _, result in ipairs(results) do
    if result.status == OSG.STATUS.ON then
      rules[#rules + 1] = result.rule
    end
  end
  return rules
end

-- Mistakes in Policy.lua, reported at login instead of failing quietly in game.
function OSG.ValidatePolicy(policy, adapters)
  local problems, seen = {}, {}
  for index, rule in ipairs(policy) do
    local name = rule.id or ("rule " .. index)
    if not rule.id then
      problems[#problems + 1] = name .. ": missing id"
    elseif seen[rule.id] then
      problems[#problems + 1] = name .. ": duplicate id"
    end
    seen[name] = true
    if type(rule.when) ~= "table" or #rule.when == 0 then
      problems[#problems + 1] = name .. ": `when` must list at least one add-on"
    end
    if not (rule.label and rule.reason) then
      problems[#problems + 1] = name .. ": needs a label and a reason"
    end
    local adapter = adapters[rule.adapter]
    if not adapter then
      problems[#problems + 1] = name .. ": unknown adapter " .. tostring(rule.adapter)
    elseif not adapter.Knows(rule.key) then
      problems[#problems + 1] = name .. ": adapter " .. rule.adapter .. " has no setting " .. tostring(rule.key)
    end
  end
  return problems
end
