local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not (YUI.IsForever or YUI.IsRetail) then return end

-- Event-fed session accounting. No persisted estimates or polling.
local Model = {}
YUI.ExperienceBarModel = Model

function Model.Number(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function Model.ReadNumber(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if ok then return Model.Number(value) end
end

function Model.Reset(state, now)
    state.started = now
    state.gained = 0
    state.xp, state.maximum, state.level = nil, nil, nil
    state.levelSeconds, state.levelTimeAt = nil, nil
end

function Model.Sample(state, now, level, xp, maximum)
    level, xp, maximum = Model.Number(level), Model.Number(xp), Model.Number(maximum)
    if not level or not xp or not maximum or maximum <= 0 or xp < 0 then
        Model.Reset(state, now)
        return false
    end
    xp = math.min(xp, maximum)
    local delta = 0
    if state.xp then
        if level == state.level and maximum == state.maximum then
            delta = xp - state.xp
        elseif level == state.level + 1 then
            delta = state.maximum - state.xp + xp
            state.levelSeconds, state.levelTimeAt = 0, now
        else
            -- A missed multi-level interval cannot be reconstructed reliably.
            Model.Reset(state, now)
        end
    end
    if delta < 0 then Model.Reset(state, now); delta = 0 end
    state.gained = state.gained + delta
    state.level, state.xp, state.maximum = level, xp, maximum
    return true
end

function Model.Estimate(state, now, locked)
    local elapsed = math.max(0, now - state.started)
    if locked or not state.xp or elapsed < 30 or state.gained <= 0 then return nil, nil end
    local rate = state.gained * 3600 / elapsed
    return rate, (state.maximum - state.xp) * 3600 / rate
end

function Model.Save(state, now)
    return { elapsed = math.max(0, now - state.started), savedAt = now,
        gained = state.gained, xp = state.xp, maximum = state.maximum, level = state.level,
        levelSeconds = state.levelSeconds and state.levelSeconds + now - state.levelTimeAt }
end

function Model.Restore(state, saved, now)
    if type(saved) ~= "table" then return false end
    for _, key in ipairs({ "elapsed", "savedAt", "gained", "xp", "maximum", "level" }) do
        if not Model.Number(saved[key]) or saved[key] < 0 then return false end
    end
    if saved.maximum <= 0 or saved.xp > saved.maximum or saved.savedAt > now then return false end
    local gap = now - saved.savedAt
    Model.Reset(state, now - saved.elapsed - gap)
    state.gained, state.xp, state.maximum, state.level = saved.gained, saved.xp, saved.maximum, saved.level
    if Model.Number(saved.levelSeconds) and saved.levelSeconds >= 0 then
        state.levelSeconds, state.levelTimeAt = saved.levelSeconds + gap, now
    end
    return true
end

function Model.Geometry(layout, width, diameter)
    local radius = diameter / 2
    if layout == "left" then return radius, radius, width - radius end
    if layout == "right" then return width - radius, 0, width - radius end
    return width / 2, 0, width
end

function Model.FillInsets(layout, trackWidth, wellWidth, diameter)
    local hidden = math.max(0, diameter / 2 - (trackWidth - wellWidth) / 2)
    return layout == "left" and hidden or 0, layout == "right" and hidden or 0
end

-- Place the entire track end inside the opaque circle, not its decorative envelope.
function Model.JoinGeometry(layout, width, diameter, height, innerRadius, pixel)
    if layout == "plain" then return diameter, width / 2, 0, width, 0 end
    diameter = math.max(diameter, (height / 2 + 2 * pixel) / innerRadius)
    local radius = diameter * innerRadius - pixel
    local chord = math.max(0, math.sqrt(math.max(0, radius * radius - height * height / 4)) - pixel)
    local center = layout == "left" and diameter / 2 or layout == "right" and width - diameter / 2 or width / 2
    if layout == "left" then return diameter, center, center + chord, width - center - chord, 0 end
    if layout == "right" then return diameter, center, 0, center - chord, 0 end
    return diameter, center, 0, center - chord, center + chord
end

-- Each half owns half of the visible progress; the badge is not part of it.
function Model.SegmentRange(first, last, index, split)
    if not split then return first, last end
    local offset = index == 1 and 0 or 1
    return math.max(0, math.min(1, first * 2 - offset)), math.max(0, math.min(1, last * 2 - offset))
end
