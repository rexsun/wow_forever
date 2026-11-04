local YUI = _G.YUI
if not YUI then return end
local CATALOGUE_REVISION = 2
local shared = YUI.SpellAlertPreviewDefaults
if shared and (shared.revision or 0) >= CATALOGUE_REVISION then return end

local PREVIEW_CLASSIC_MAX_TEXTURE_ID = 898423
local PREVIEW_FALLBACK_MATERIALS = { left = 450917, right = 450917, top = 450923 }

local DEFAULT_PREVIEW_MATERIALS_BY_CLASS = {
    DEATHKNIGHT = { left = 511104, right = 511104, top = 449487 },
    DEMONHUNTER = { left = 1030393, right = 1030393, top = 801266 },
    DRUID = { left = 450914, right = 450914, top = 463452 },
    EVOKER = { left = 4699056, right = 4699056, top = 4699057 },
    HUNTER = { left = 1029140, right = 1029140, top = 450926 },
    MAGE = { left = 1027132, right = 1027132, top = 6160020 },
    MONK = { left = 623952, right = 623952, top = 627610 },
    PALADIN = { left = 450913, right = 450913, top = 459314 },
    PRIEST = { left = 450933, right = 450933, top = 469752 },
    ROGUE = { left = 449491, right = 449491, top = 449487 },
    SHAMAN = { left = 1057288, right = 1057288, top = 467696 },
    WARLOCK = { left = 449491, right = 449491, top = 458741 },
    WARRIOR = { left = 449493, right = 449493, top = 449494 },
}

local DEFAULT_PREVIEW_MATERIALS_BY_SPEC_ID = {
    [62] = { left = 1027132, right = 1027132, top = 6160020 },
    [63] = { left = 449490, right = 449490, top = 457658 },
    [64] = { left = 449489, right = 449489, top = 450930 },
    [65] = { left = 450933, right = 450933, top = 511469 },
    [66] = { left = 450925, right = 450925, top = 459314 },
    [70] = { left = 450913, right = 450913, top = 459314 },
    [71] = { left = 449493, right = 449493, top = 460830 },
    [72] = { left = 962497, right = 962497, top = 460830 },
    [73] = { left = 449494, right = 449494, top = 627610 },
    [102] = { left = 450914, right = 450914, top = 463452 },
    [103] = { left = 510823, right = 510823, top = 510822 },
    [104] = { left = 774420, right = 774420, top = 449487 },
    [105] = { left = 450929, right = 450929, top = 898423 },
    [250] = { left = 511104, right = 511104, top = 449487 },
    [251] = { left = 458740, right = 458740, top = 450930 },
    [252] = { left = 450932, right = 450932, top = 627609 },
    [253] = { left = 1029140, right = 1029140, top = 450926 },
    [254] = { left = 1029140, right = 1029140, top = 450926 },
    [255] = { left = 1029140, right = 1029140, top = 450926 },
    [256] = { left = 450933, right = 450933, top = 469752 },
    [257] = { left = 450933, right = 450933, top = 469752 },
    [258] = { left = 592058, right = 592058, top = 627609 },
    [259] = { left = 449491, right = 449491, top = 449487 },
    [260] = { left = 449491, right = 449491, top = 449487 },
    [261] = { left = 449491, right = 449491, top = 449487 },
    [262] = { left = 1057288, right = 1057288, top = 467696 },
    [263] = { left = 1057288, right = 1057288, top = 1028138 },
    [264] = { left = 450929, right = 450929, top = 2851788 },
    [265] = { left = 449492, right = 449492, top = 801266 },
    [266] = { left = 2888300, right = 2888300, top = 2851787 },
    [267] = { left = 449491, right = 449491, top = 801266 },
    [268] = { left = 623952, right = 623952, top = 627610 },
    [269] = { left = 623952, right = 623952, top = 627610 },
    [270] = { left = 623952, right = 623952, top = 627610 },
    [577] = { left = 1030393, right = 1030393, top = 801266 },
    [581] = { left = 1030393, right = 1030393, top = 801266 },
    [1467] = { left = 4699056, right = 4699056, top = 4699057 },
    [1468] = { left = 4699056, right = 4699056, top = 4699057 },
    [1473] = { left = 4699056, right = 4699056, top = 4699057 },
    [1480] = { left = 656728, right = 656728, top = 7549806 },
}

local PREVIEW_EXTRA_SIDE_OVERLAYS_BY_SPEC_ID = {
    [62] = { textureID = 449486 },
    [63] = { textureID = 6160021 },
}

-- Each standalone carries this file. Upgrade older carriers in place so an
-- earlier consumer keeps the same table; equal/newer revisions are reused.
local Defaults = shared or {}
Defaults.revision = CATALOGUE_REVISION
Defaults.classicMaxTextureID = PREVIEW_CLASSIC_MAX_TEXTURE_ID
Defaults.fallback = PREVIEW_FALLBACK_MATERIALS
Defaults.byClass = DEFAULT_PREVIEW_MATERIALS_BY_CLASS
Defaults.bySpec = DEFAULT_PREVIEW_MATERIALS_BY_SPEC_ID
Defaults.extraBySpec = PREVIEW_EXTRA_SIDE_OVERLAYS_BY_SPEC_ID
YUI.SpellAlertPreviewDefaults = Defaults

-- Retail 12.1.0.69933 original recorder SHOW pairs (2026-09-30 / 2026-10-04).
-- Anonymous texture/location fixture: Tests/Components/SpellAlert/test-preview-defaults.lua.
-- Each entry is a separate sample state, not a union of mutually exclusive procs.
Defaults.statesBySpec = {
    [62] = {
        {left=1027131, right=1027131, top=6160020, extraLeft=449486, extraRight=449486},
        {left=1027132, right=1027132, top=6160020, extraLeft=449486, extraRight=449486},
        {left=1027133, right=1027133, top=6160020, extraLeft=449486, extraRight=449486},
    },
    [63] = {
        {left=449490, right=449490},
        {left=449490, right=449490, extraLeft=6160021, extraRight=6160021},
    },
    [64] = {{left=449489, top=450930}, {left=449489, right=449489, top=450930}},
    [65] = {{left=459313}, {left=459313, right=459313}},
    [66] = {{left=450925, right=450925, top=459314}},
    [70] = {{left=450913, top=459314}, {left=450913, right=450913, top=459314}},
    [71] = {{left=449493, right=449493}},
    [72] = {{left=962497, right=962497}},
    [73] = {{left=449494, right=603339}},
    [102] = {{left=450914}, {right=450915}},
    [103] = {{left=510823, right=510823}},
    [104] = {{left=450914, top=510822}},
    [105] = {{left=450929, right=450929}},
    [250] = {{left=511104, right=511104}},
    [251] = {{left=458740, top=450930}, {left=458740, right=458740, top=450930}},
    [252] = {{left=450932}, {left=450932, right=450932}},
    [253] = {{left=774420, right=774420}},
    [254] = {{left=1029138, right=1029138, top=450926}},
    [256] = {{left=592058, right=592058}, {left=450933}, {left=450933, right=450933}},
    [257] = {{left=450933}, {left=450933, right=450933}},
    [258] = {{left=592058, top=627609}, {left=592058, right=592058, top=627609}},
    [260] = {{top=450926}},
    [262] = {{left=449491, right=449491}},
    -- 77762 after switching to Enhancement was inherited, not a new proc.
    [263] = {{top=1028136}, {top=1028137}, {top=1028138}, {top=1028139}, {top=450927}, {top=467696}},
    [264] = {{left=449491, right=449491}},
    [265] = {{left=449492, right=449492}},
    [266] = {{left=2888300, right=2888300}},
    -- Stagger samples are visual only; this does not extend HELPFUL buff timing.
    [268] = {{left=1028092, right=1028092, top=469752}, {left=1028091, right=1028091, top=469752}},
    [269] = {{left=623950, right=1001511}},
    [581] = {{left=7549744, right=7549744}},
    [1467] = {{left=4699056}, {left=4699056, right=4699056}},
    [1468] = {{left=4699056}, {left=4699056, right=4699056}},
    [1473] = {{left=4699056}, {left=4699056, right=4699056}},
    [1480] = {{left=7549744, right=7549744, top=7549806}},
}
Defaults.placeholderSpecs = {[577]=581, [255]=253, [259]=260, [261]=260, [267]=265, [270]=269}
Defaults.classSpecs = {
    DEATHKNIGHT=250, DEMONHUNTER=581, DRUID=102, EVOKER=1467,
    HUNTER=253, MAGE=62, MONK=269, PALADIN=70, PRIEST=257,
    ROGUE=260, SHAMAN=262, WARLOCK=265, WARRIOR=71,
}
Defaults.slots = {'left', 'right', 'top', 'extraLeft', 'extraRight'}

-- Fillers reserve space for layout editing; they do not assert a proc exists
-- on the target spec. Prefer recorded same-class positions, then older artwork.
-- Top fillers must use horizontal artwork, never a squeezed side bracket.
Defaults.layoutFallbacksByClass = {
    DEATHKNIGHT={left=511104, right=511104, top=450930},
    DEMONHUNTER={left=7549744, right=7549744, top=7549806},
    DRUID={left=450914, right=450915, top=510822},
    EVOKER={left=4699056, right=4699056, top=4699057},
    HUNTER={left=774420, right=774420, top=450926},
    MAGE={left=449489, right=449489, top=457658},
    MONK={left=623950, right=1001511, top=469752},
    PALADIN={left=450913, right=450913, top=459314},
    PRIEST={left=450933, right=450933, top=627609},
    ROGUE={left=1030393, right=1030393, top=450926},
    SHAMAN={left=449491, right=449491, top=467696},
    WARLOCK={left=449492, right=449492, top=2851787},
    WARRIOR={left=449493, right=449493, top=627610},
}

local classicStates = {}
local genericStates = {PREVIEW_FALLBACK_MATERIALS}

-- Pure data lookup. Missing slots stay absent; classic clients retain the old
-- material defaults and availability cutoff independently of Retail evidence.
function Defaults:GetState(specKey, classic, index)
    local class, spec = tostring(specKey or ''):match('^([^:]+):(%d+)$')
    spec = tonumber(spec)
    if classic then
        local key = specKey or ''
        if not classicStates[key] then
            local side, top, extra = self:Get(specKey, true)
            classicStates[key] = {left=side, right=side, top=top, extraLeft=extra, extraRight=extra}
        end
        return classicStates[key], 1, false
    end
    local source = self.placeholderSpecs[spec] or self.classSpecs[class]
    local states = self.statesBySpec[spec] or self.statesBySpec[source] or genericStates
    return states[((index or 1) - 1) % #states + 1], #states, self.statesBySpec[spec] == nil
end

-- Pure preview data; loading this file never enables the enhancement component.
function Defaults:Get(specKey, classic)
    local class, spec = tostring(specKey or ''):match('^([^:]+):(%d+)$')
    spec = tonumber(spec)
    local values = self.bySpec[spec] or self.byClass[class] or self.fallback
    local side, top = values.left, values.top
    local extra = self.extraBySpec[spec]
    extra = extra and extra.textureID
    if classic then
        if side > self.classicMaxTextureID then side = self.fallback.left end
        if top > self.classicMaxTextureID then top = self.fallback.top end
        if extra and extra > self.classicMaxTextureID then extra = nil end
    end
    return side, top, extra
end

local layouts, layoutFillers = {}, {}

-- Fixed design coverage: all three primary positions, plus recorded outside
-- overlays. Recorded variants stay available above as evidence, not a timer.
function Defaults:GetLayout(specKey, classic)
    if classic then
        local state = self:GetState(specKey, true)
        return state, false
    end
    local key = specKey or ''
    if not layouts[key] then
        local class, spec = tostring(key):match('^([^:]+):(%d+)$')
        spec = tonumber(spec)
        local source = self.statesBySpec[spec] and spec or self.placeholderSpecs[spec] or self.classSpecs[class]
        local samples = self.statesBySpec[source]
        local layout, fillers = {}, {}
        if samples then
            -- The last recorded tier is normally the fullest; Stagger's first
            -- sample is the higher severity recorded in this catalogue.
            local representative = samples[source == 268 and 1 or #samples]
            for _, slot in ipairs(self.slots) do
                layout[slot] = representative[slot]
                if not layout[slot] then
                    for index = #samples, 1, -1 do
                        if samples[index][slot] then layout[slot] = samples[index][slot]; break end
                    end
                end
                if layout[slot] and not self.statesBySpec[spec] then fillers[slot] = true end
            end
        end
        -- A missing opposite bracket uses the same design with native mirroring.
        if not layout.left and layout.right then layout.left, fillers.left = layout.right, true end
        if not layout.right and layout.left then layout.right, fillers.right = layout.left, true end
        local fallback = self.layoutFallbacksByClass[class] or self.fallback
        for _, slot in ipairs({'left', 'right', 'top'}) do
            if not layout[slot] then layout[slot], fillers[slot] = fallback[slot], true end
        end
        layouts[key], layoutFillers[key] = layout, fillers
    end
    local fillers = layoutFillers[key]
    return layouts[key], next(fillers) ~= nil, fillers
end
