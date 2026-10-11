--[[ LibAuraContainer-1.0: Emulated/Filter

Which auras a group or slot shows, and in what order. Pure functions: aura
records, unit tokens and options in; booleans and comparators out. They read
the client's API (C_UnitAuras, C_Spell, UnitCanAssist, ...) at call time and
keep no state.

INTERFACE (Private.Filter)

  Filter.IsValid(filterString) -> ok, reason
      Valid against the 12.1.5 token set with "!" negation, never the
      client's own list. Components are separated by "|" or spaces; empty
      components are skipped; "" is valid. reason is our own message.

  Filter.Compile(filterString) -> compiled | nil, reason
      Validates, then splits the string for this client:
        compiled.engine    string for the client's engine, tokens joined by "|"
                           ("" when nothing is left; the engine applies its
                           defaults to that, as it does on a full query)
        compiled.fallback  list of { token = "IMPORTANT", negated = bool,
                           probe = bool }, evaluated per aura by MatchesFallback:
                           from aura and spell data, or (probe) by asking the
                           engine about the token for that aura alone. A token
                           the engine knows but cannot negate is probed, so
                           "X" and "!X" always split the auras between them.
        compiled.probeSuffix  "|INCLUDE_NAME_PLATE_ONLY" when the string has that
                           modifier and the engine knows it, else ""
      A full parse queries C_UnitAuras.GetUnitAuraInstanceIDs(unit,
      compiled.engine) once per distinct string. Compile reads the client's
      token support each call, so call it when a filter string is set, not
      per aura. Support: a token is the engine's when it is a value of
      AuraUtil.AuraFilters and not in ENGINE_IGNORES (tokens a classic engine
      lists but lets every aura through: CROWD_CONTROL, BIG_DEFENSIVE,
      EXTERNAL_DEFENSIVE, RAID_PLAYER_DISPELLABLE, RAID_IN_COMBAT, seen on MoP
      5.5.4; they go to the data fallback, never probed); "!" only when
      AuraUtil.AuraFilterNegationPrefix is "!".

  Filter.MatchesFallback(unit, aura, compiled) -> bool
  Filter.MatchesFilterString(unit, aura, compiled, engineMatched) -> bool
      engineMatched: the aura came from the engine query for compiled.engine
      (full parse). Otherwise (incremental path) the engine part is checked
      with C_UnitAuras.IsAuraFilteredOutByInstanceID. The fallback part is
      always applied.

  Filter.CanTestIdentity(unit, aura) -> bool
  Filter.PassesCandidateFilters(unit, aura, candidateFilters, processedType) -> bool
      candidateFilters may be nil. processedType is the aura's
      processing-policy classification, nil when the policy is off.
  Filter.IsRoleAura(aura), Filter.IsBossOrRoleAura(aura), Filter.IsPriorityAura(aura) -> bool
      The computed properties the candidate filters compare against.

  Filter.IsMember(unit, aura, compiled, candidateFilters, policy, engineMatched, stringMatched) -> bool
      In order: filter string, processing policy (policy is the
      container's LAC.AuraProcessingPolicy value; under ProcessAura an aura
      whose processedAuraType is the client's AuraUtil.AuraUpdateChangedType.None
      is rejected), candidate filters. stringMatched: the whole filter string
      is known to match (edit-mode preview records); the string test
      is skipped.

  Filter.GetComparator(sortMethod, sortDirection) -> function(a, b) | nil
      A strict "a before b" for table.sort, a total order ending on
      ascending auraInstanceID; Reverse swaps the operands. nil for values
      outside LAC.SortMethod / LAC.SortDirection (the caller validates).
      Comparators are built once; the same function is returned every time.

Aura records are the client's AuraData tables. A boolean field that is nil
counts as false everywhere here.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Filter = {}
Private.Filter = Filter

------------------------------------------------------------------ client queries

local function bool(v)
	return v and true or false
end

-- Asks a C_Spell-style predicate about the aura's spell; false without a spell or API.
local function spellFlag(api, spellId)
	if spellId == nil or api == nil then return false end
	return bool(api(spellId))
end

-- Casters whose auras classic's raid frames count as the player's own.
local OWN_CASTER = { player = true, pet = true, vehicle = true }

local function engineSays(unit, aura, filterString)
	return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, aura.auraInstanceID, filterString)
end

------------------------------------------------------------------ tokens

-- The 12.1.5 token set. Each entry answers "does this aura match the token?" from
-- aura and spell data, for tokens this client's engine cannot evaluate;
-- false when only the engine can tell.
local MATCHERS = {
	HELPFUL = function(aura) return bool(aura.isHelpful) end,
	HARMFUL = function(aura) return bool(aura.isHarmful) end,
	PLAYER = function(aura) return bool(aura.isFromPlayerOrPlayerPet) end,
	RAID = function(aura) return bool(aura.isRaid) end,
	RAID_PLAYER_DISPELLABLE = function(aura) return bool(aura.canActivePlayerDispel) end,
	DISPELLABLE = function(aura) return aura.dispelName ~= nil end,
	IMPORTANT = function(aura) return spellFlag(C_Spell and C_Spell.IsSpellImportant, aura.spellId) end,
	CROWD_CONTROL = function(aura) return spellFlag(C_Spell and C_Spell.IsSpellCrowdControl, aura.spellId) end,
	EXTERNAL_DEFENSIVE = function(aura) return spellFlag(C_Spell and C_Spell.IsExternalDefensive, aura.spellId) end,
	BIG_DEFENSIVE = function(aura)
		if aura.isBigDefensive ~= nil then return bool(aura.isBigDefensive) end
		return spellFlag(C_UnitAuras and C_UnitAuras.AuraIsBigDefensive, aura.spellId)
	end,
	-- The raid-frame rule of classic's own UI: custom visibility data decides when
	-- the spell has it; without it a debuff shows, and a buff only when the
	-- player cast it, could apply it, and it is not a self buff.
	RAID_IN_COMBAT = function(aura)
		if aura.spellId == nil or not (C_Spell and C_Spell.GetVisibilityInfo) then return false end
		local custom, mine, spec = C_Spell.GetVisibilityInfo(aura.spellId, Enum.SpellAuraVisibilityType.RaidInCombat)
		local byPlayer = OWN_CASTER[aura.sourceUnit] == true
		if custom then return bool(spec or (mine and byPlayer)) end
		if aura.isHarmful then return true end
		return byPlayer and aura.canApplyAura == true
			and not spellFlag(C_Spell.IsSelfBuff, aura.spellId)
	end,
	CANCELABLE = false, -- no aura field says "cancelable"
	-- A modifier, not a test: it widens the engine query, so per aura it restricts nothing.
	INCLUDE_NAME_PLATE_ONLY = function() return true end,
	-- A test: Torghast auras only. Classic has none.
	MAW = function() return false end,
}

-- On an engine without "!", "!HELPFUL" is plainly "HARMFUL" and the other way round.
local OPPOSITE = { HELPFUL = "HARMFUL", HARMFUL = "HELPFUL" }

-- 12.1.5 ignores "!" on these two.
local NEVER_NEGATED = { INCLUDE_NAME_PLATE_ONLY = true, MAW = true }

-- Tokens a classic engine lists in AuraUtil.AuraFilters but does not filter on
-- (it lets every aura through): evaluated from data instead. Seen on
-- MoP 5.5.4. Only the emulated backend reads this; retail never gets here.
local ENGINE_IGNORES = {
	CROWD_CONTROL = true,
	BIG_DEFENSIVE = true,
	EXTERNAL_DEFENSIVE = true,
	RAID_PLAYER_DISPELLABLE = true,
	RAID_IN_COMBAT = true,
}

-- Splits on "|" and spaces. Returns the components, or nil and a reason.
local function parse(filterString)
	if type(filterString) ~= "string" then
		return nil, "filter string must be a string"
	end
	local components = {}
	for piece in filterString:gmatch("[^| ]+") do
		local negated = piece:sub(1, 1) == "!"
		local token = negated and piece:sub(2) or piece
		if MATCHERS[token] == nil then
			return nil, "unknown filter token '" .. piece .. "'"
		end
		components[#components + 1] = { token = token, negated = negated and not NEVER_NEGATED[token] }
	end
	return components
end

function Filter.IsValid(filterString)
	local components, reason = parse(filterString)
	if not components then return false, reason end
	return true
end

-- What the client's engine understands: its AuraUtil.AuraFilters values, and "!"
-- only when it defines AuraUtil.AuraFilterNegationPrefix.
local function engineSupport()
	local known, negation = {}, false
	local util = AuraUtil
	if type(util) == "table" then
		if type(util.AuraFilters) == "table" then
			for _, token in pairs(util.AuraFilters) do
				if not ENGINE_IGNORES[token] then known[token] = true end
			end
		end
		negation = util.AuraFilterNegationPrefix == "!"
	end
	return known, negation
end

function Filter.Compile(filterString)
	local components, reason = parse(filterString)
	if not components then return nil, reason end

	local known, negation = engineSupport()
	local engine, fallback, widened = {}, {}, false
	for _, c in ipairs(components) do
		local token, forEngine = c.token, nil
		widened = widened or token == "INCLUDE_NAME_PLATE_ONLY"
		if not c.negated then
			forEngine = known[token] and token
		elseif negation and known[token] then
			forEngine = "!" .. token
		elseif OPPOSITE[token] and known[OPPOSITE[token]] then
			forEngine = OPPOSITE[token]
		elseif token == "CANCELABLE" and known.NOT_CANCELABLE then
			forEngine = "NOT_CANCELABLE"
		end
		if forEngine then
			engine[#engine + 1] = forEngine
		else
			local probe = not MATCHERS[token] or (known[token] and not OPPOSITE[token]) or false
			fallback[#fallback + 1] = { token = token, negated = c.negated, probe = probe }
		end
	end
	return {
		engine = table.concat(engine, "|"),
		fallback = fallback,
		probeSuffix = (widened and known.INCLUDE_NAME_PLATE_ONLY) and "|INCLUDE_NAME_PLATE_ONLY" or "",
	}
end

-- The engine's answer for `token` on this aura alone: the aura's own HELPFUL/HARMFUL
-- plus the string's nameplate-only modifier, so only `token` can filter it out.
local function engineMatchesToken(unit, aura, token, compiled)
	local polarity = aura.isHarmful and "HARMFUL" or "HELPFUL"
	return engineSays(unit, aura, polarity .. "|" .. token .. compiled.probeSuffix)
end

function Filter.MatchesFallback(unit, aura, compiled)
	for _, c in ipairs(compiled.fallback) do
		local matches
		if c.probe then
			matches = engineMatchesToken(unit, aura, c.token, compiled)
		else
			matches = MATCHERS[c.token](aura)
		end
		if matches == c.negated then return false end
	end
	return true
end

function Filter.MatchesFilterString(unit, aura, compiled, engineMatched)
	if not engineMatched and not engineSays(unit, aura, compiled.engine) then
		return false
	end
	return Filter.MatchesFallback(unit, aura, compiled)
end

------------------------------------------------------------------ identity gate

-- UnitIsPlayerControlledOrGroupMember's documented rule, by token: player, pet,
-- vehicle, partyN, partypetN, raidN, raidpetN.
local GROUP_PATTERNS = { "^player$", "^pet$", "^vehicle$", "^party%d+$", "^partypet%d+$", "^raid%d+$", "^raidpet%d+$" }

local groupTokens = {} -- unit as given -> whether it is a group token (few distinct units)

local function isGroupToken(unit)
	local known = groupTokens[unit]
	if known ~= nil then return known end
	known = false
	local lowered = unit:lower()
	for _, pattern in ipairs(GROUP_PATTERNS) do
		if lowered:find(pattern) then
			known = true
			break
		end
	end
	groupTokens[unit] = known
	return known
end

-- Without C_Secrets there is no exemption.
local function isNeverSecret(spellId)
	if spellId == nil or not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then return false end
	return C_Secrets.GetSpellAuraSecrecy(spellId) == Enum.SecrecyLevel.NeverSecret
end

function Filter.CanTestIdentity(unit, aura)
	if isNeverSecret(aura.spellId) then return true end
	if aura.isHelpful and isGroupToken(unit) then return true end
	-- Classic's UnitCanAssist has no immune / uninteractable arguments.
	local friendly = bool(UnitCanAssist("player", unit))
	-- Buffs may be tested on friends, debuffs on everyone else.
	return not ((aura.isHelpful and not friendly) or (aura.isHarmful and friendly))
end

------------------------------------------------------------------ candidate filters

function Filter.IsRoleAura(aura)
	return bool(aura.isTankRoleAura or aura.isHealerRoleAura or aura.isDPSRoleAura)
end

function Filter.IsBossOrRoleAura(aura)
	return bool(aura.isBossAura) or Filter.IsRoleAura(aura)
end

local FORBEARANCE = 25771

function Filter.IsPriorityAura(aura)
	local spellId = aura.spellId
	if spellId == nil then return false end
	if spellId == FORBEARANCE and select(2, UnitClass("player")) == "PALADIN" then return true end
	return spellFlag(C_Spell and C_Spell.IsPriorityAura, spellId)
end

-- Candidate fields compared with a field of the aura record of the same name.
local RECORD_FLAGS = { "canApplyAura", "isBossAura", "isFromPlayerOrPlayerPet", "isStealable", "nameplateShowAll", "nameplateShowPersonal" }

-- Candidate fields compared with a computed property.
local COMPUTED_FLAGS = {
	isRoleAura = Filter.IsRoleAura,
	isBossOrRoleAura = Filter.IsBossOrRoleAura,
	isPriorityAura = Filter.IsPriorityAura,
}

local function passesSpellIDs(unit, aura, include, exclude)
	if include == nil and exclude == nil then return true end
	if not Filter.CanTestIdentity(unit, aura) then
		-- Untestable: an include list admits only what it can see, i.e. nothing.
		return include == nil
	end
	local id = aura.spellId
	if exclude ~= nil and id ~= nil and exclude[id] then return false end
	if include ~= nil and not (id ~= nil and include[id]) then return false end
	return true
end

function Filter.PassesCandidateFilters(unit, aura, f, processedType)
	if f == nil then return true end
	if not passesSpellIDs(unit, aura, f.includeSpellIDs, f.excludeSpellIDs) then return false end

	if f.processedAuraType ~= nil and f.processedAuraType ~= processedType then return false end

	local dispel = aura.dispelName
	if f.excludeDispelTypes ~= nil and dispel ~= nil and f.excludeDispelTypes[dispel] then return false end
	if f.includeDispelTypes ~= nil and not (dispel ~= nil and f.includeDispelTypes[dispel]) then return false end

	for _, field in ipairs(RECORD_FLAGS) do
		local wanted = f[field]
		if wanted ~= nil and bool(aura[field]) ~= wanted then return false end
	end
	for field, compute in pairs(COMPUTED_FLAGS) do
		local wanted = f[field]
		if wanted ~= nil and compute(aura) ~= wanted then return false end
	end

	if f.maxDuration ~= nil then
		-- A limit also hides permanent auras.
		local duration = aura.duration or 0
		if duration == 0 or duration > f.maxDuration then return false end
	end
	return true
end

------------------------------------------------------------------ membership

function Filter.IsMember(unit, aura, compiled, candidateFilters, policy, engineMatched, stringMatched)
	if not stringMatched and not Filter.MatchesFilterString(unit, aura, compiled, engineMatched) then
		return false
	end

	local processedType
	if policy == LAC.AuraProcessingPolicy.ProcessAura then
		processedType = aura.processedAuraType
		if processedType == AuraUtil.AuraUpdateChangedType.None then return false end
	end

	return Filter.PassesCandidateFilters(unit, aura, candidateFilters, processedType)
end

------------------------------------------------------------------ sort methods

-- Sort keys: each maps an aura to a value; a rule says whether value x goes before y.
local function castByPlayer(aura)
	local source = aura.sourceUnit
	return source ~= nil and bool(UnitIsUnit("player", source))
end
local function castByOthers(aura) return not castByPlayer(aura) end
local function priorityField(aura) return bool(aura.isPriorityAura) end
local function applicable(aura) return bool(aura.canApplyAura) end
local function important(aura) return spellFlag(C_Spell and C_Spell.IsSpellImportant, aura.spellId) end
local function displayName(aura) return aura.name or "" end
local function debuffRank(aura) return aura.debuffType or math.huge end
local function expirationOrZero(aura) return aura.expirationTime or 0 end
local function expiresAt(aura) -- permanent (nil or 0) sorts last
	local t = aura.expirationTime
	if t == nil or t == 0 then return math.huge end
	return t
end

local function trueFirst(x) return x end
local function lowFirst(x, y) return x < y end
local function highFirst(x, y) return x > y end

-- Builds "a before b" from (key, rule) pairs, ending on ascending auraInstanceID.
local function ordering(...)
	local steps, count = { ... }, select("#", ...)
	return function(a, b)
		for i = 1, count, 2 do
			local key = steps[i]
			local x, y = key(a), key(b)
			if x ~= y then return steps[i + 1](x, y) end
		end
		return a.auraInstanceID < b.auraInstanceID
	end
end

local M = LAC.SortMethod
local BY_METHOD = {
	[M.Default] = ordering(castByPlayer, trueFirst, priorityField, trueFirst, applicable, trueFirst),
	[M.BigDefensive] = ordering(castByOthers, trueFirst, expirationOrZero, highFirst),
	[M.UnitFrameDebuff] = ordering(debuffRank, lowFirst, castByPlayer, trueFirst, priorityField, trueFirst, applicable, trueFirst),
	[M.ImportantOnly] = ordering(important, trueFirst),
	[M.Expiration] = ordering(castByPlayer, trueFirst, priorityField, trueFirst, applicable, trueFirst, expiresAt, lowFirst),
	[M.ExpirationOnly] = ordering(expiresAt, lowFirst),
	[M.Name] = ordering(castByPlayer, trueFirst, priorityField, trueFirst, applicable, trueFirst, displayName, lowFirst),
	[M.NameOnly] = ordering(displayName, lowFirst),
	[M.AuraInstanceIDOnly] = ordering(),
}

local COMPARATORS = {}
for method, forward in pairs(BY_METHOD) do
	COMPARATORS[method] = {
		[LAC.SortDirection.Normal] = forward,
		[LAC.SortDirection.Reverse] = function(a, b) return forward(b, a) end,
	}
end

function Filter.GetComparator(sortMethod, sortDirection)
	local byDirection = COMPARATORS[sortMethod]
	return byDirection and byDirection[sortDirection]
end
