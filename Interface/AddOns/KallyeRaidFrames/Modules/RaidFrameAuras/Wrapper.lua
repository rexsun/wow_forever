local _, ns = ...

-- * avoid conflict override
if ns.CONFLICT then return; end

--[[ TODO:
-- * Fix Core: replace RFA_Core
-- * Config/Defaults: Replace enabled = false
-- * Fix GetLongBuffReason
--]]

local DEFAULT_BUFF_SIZE = 6
local DEFAULT_DEBUFF_SIZE = 6
local DEFAULT_BUFFS_SCALE = 0.75
local DEFAULT_DEBUFFS_SCALE = 1.25

local ORIENTATION_TO_ANCHOR = {
    LeftThenUp = "BOTTOMRIGHT",
    UpThenLeft = "BOTTOMRIGHT",
    RightThenUp = "BOTTOMLEFT",
    UpThenRight = "BOTTOMLEFT",
}
local ORIENTATION_TO_GROWTH = {
    LeftThenUp = "LEFT_UP",
    UpThenLeft = "UP_LEFT",
    RightThenUp = "RIGHT_UP",
    UpThenRight = "UP_RIGHT",
}
local BLIZZARD_AURA_CVARS = {
    { name = "raidFramesDisplayBuffs", label = "Blizzard raid-frame buffs" },
    { name = "raidFramesDisplayDebuffs", label = "Blizzard raid-frame debuffs" },
}

local function resolveOptions(options)
    options = options or ns.Module.cacheOptions
    if (not options or not options.Version) and ns.OPTIONS_NAME then
        options = _G[ns.OPTIONS_NAME]
    end
    return options
end

local function scaleToSize(baseSize, scale, defaultScale)
    scale = tonumber(scale) or defaultScale
    defaultScale = tonumber(defaultScale) or 1
    if defaultScale == 0 then
        defaultScale = 1
    end
    return math.max(4, math.min(80, math.floor(baseSize * scale / defaultScale + 0.5)))
end

local function syncKRFOptionsToRaidFrameAuras(options)
    local RaidFrameAuras = ns.RaidFrameAuras
    if not RaidFrameAuras then
        return false
    end

    options = resolveOptions(options)
    if not options then
        return false
    end

    local active = options.ActiveUnitDebuffs ~= false
    if not RaidFrameAuras.initialized and not active then
        return false
    end

    if not RaidFrameAuras.db then
        RaidFrameAuras:InitializeDatabase()
    end

    local db = RaidFrameAuras.db
    local maxBuffs = tonumber(options.MaxBuffs) or 0
    local maxDebuffs = tonumber(options.MaxDebuffs) or 0

    db.enabled = active
    db.showBuffs = active and maxBuffs > 0
    db.showDebuffs = active and maxDebuffs > 0

    db.buffBorderEnabled = true
    db.buffMax = math.max(1, maxBuffs)
    db.buffWrap = math.max(1, tonumber(options.BuffsPerLine) or 1)
    db.buffAnchor = ORIENTATION_TO_ANCHOR[options.BuffsOrientation] or "BOTTOMRIGHT"
    db.buffGrowth = ORIENTATION_TO_GROWTH[options.BuffsOrientation] or "LEFT_UP"
    db.buffOffsetX = -3 + (tonumber(options.BuffsPosX) or 0)
    db.buffOffsetY = 2 + (tonumber(options.BuffsPosY) or 0)
    db.buffPaddingX = tonumber(options.BuffsSpacingX) or 0
    db.buffPaddingY = tonumber(options.BuffsSpacingY) or 1
    db.buffSize = scaleToSize(DEFAULT_BUFF_SIZE, options.BuffsScale, DEFAULT_BUFFS_SCALE)
    db.buffShowDuration = false

    db.debuffMax = math.max(1, maxDebuffs)
    db.debuffWrap = math.max(1, tonumber(options.DebuffsPerLine) or 1)
    db.debuffAnchor = ORIENTATION_TO_ANCHOR[options.DebuffsOrientation] or "BOTTOMLEFT"
    db.debuffGrowth = ORIENTATION_TO_GROWTH[options.DebuffsOrientation] or "RIGHT_UP"
    db.debuffOffsetX = 3 + (tonumber(options.DebuffsPosX) or 0)
    db.debuffOffsetY = 2 + (tonumber(options.DebuffsPosY) or 0)
    db.debuffPaddingX = tonumber(options.DebuffsSpacingX) or 0
    db.debuffPaddingY = tonumber(options.DebuffsSpacingY) or 1
    db.debuffSize = scaleToSize(DEFAULT_DEBUFF_SIZE, options.DebuffsScale, DEFAULT_DEBUFFS_SCALE)
    db.debuffShowDuration = false
    db.debuffShowDurationCrowdControlOnly = true

    db.directBuffHideLong = true
    db.directBuffHideLongOnlyInCombat = false

    return true
end

local function ensureRaidFrameAurasInitialized()
    local RaidFrameAuras = ns.RaidFrameAuras
    if not RaidFrameAuras then
        return false
    end
    if not RaidFrameAuras.initialized then
        RaidFrameAuras:Initialize()
    end
    return true
end

local function SafeSetCVar(name, value)
    if not SetCVar or value == nil then return false end
    local ok = pcall(SetCVar, name, value)
    return ok == true
end

local function applyBlizzardAuraCVarPolicy(hide)
    local value = hide and "0" or "1"
    for _, spec in ipairs(BLIZZARD_AURA_CVARS) do
        SafeSetCVar(spec.name, value)
    end
end

ns.SyncRaidFramesAuras = function(options)
    applyBlizzardAuraCVarPolicy(false)
    if not syncKRFOptionsToRaidFrameAuras(options) then
        return
    end
    local RaidFrameAuras = ns.RaidFrameAuras
    if not RaidFrameAuras.initialized then
        return
    end
    applyBlizzardAuraCVarPolicy(RaidFrameAuras.db.enabled and options.HideBlizzardAuras)
    RaidFrameAuras:ApplySettings(false)
end

local function disableBlizzAuras(frame)
	if (frame.optionTable and frame.optionTable.displayBuffs ~= false) then
		frame.optionTable.displayBuffs = false
		frame.optionTable.displayDebuffs = false
		frame.optionTable.displayDispelDebuffs = false
		-- CompactUnitFrame_SetOptionTable(frame, frame.optionTable)
        --[[ To test:
        	CompactUnitFrame_SetMaxBuffs(frame, isPvPFrame and 0 or 6);
            CompactUnitFrame_SetMaxDebuffs(frame, 3);
            CompactUnitFrame_SetMaxDispelDebuffs(frame, isPvPFrame and 0 or 3);
        --]]
	end
end

ns.LoadRaidFramesAuras = function(options)
    applyBlizzardAuraCVarPolicy(false)
    ns.RaidFrameAuras:Initialize()
    if not ensureRaidFrameAurasInitialized() then
        return
    end
    if not syncKRFOptionsToRaidFrameAuras(options) then
        return
    end
    local RaidFrameAuras = ns.RaidFrameAuras
    applyBlizzardAuraCVarPolicy(RaidFrameAuras.db.enabled and options.HideBlizzardAuras)
    RaidFrameAuras:ApplySettings(true)

    -- FIXME: TO REMOVE when bugfixed
    if options.HideBlizzardAuras and GetCVar("raidFramesDisplayBuffs") == nil then
        hooksecurefunc("CompactUnitFrame_SetUpFrame", disableBlizzAuras)
    end
end
