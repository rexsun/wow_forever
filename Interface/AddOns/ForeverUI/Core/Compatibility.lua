local _, ns = ...

-- One place that knows what this client can do, so modules ask a question
-- instead of testing for the game version themselves. Options for features a
-- client lacks are hidden rather than left there broken.

local compat = {}
ns.Compat = compat

local _, _, _, interface = GetBuildInfo()
compat.interface = interface or 11509

-- Forever is the 1.60 line; Classic Era is 1.15; Retail is 11xxxx / 12xxxx.
compat.IsForever = compat.interface >= 16000 and compat.interface < 20000
compat.IsClassicEra = compat.interface >= 11000 and compat.interface < 12000
compat.IsRetail = compat.interface >= 100000
compat.IsClassic = compat.interface < 100000

-- Presence of an API is the honest test; version numbers only say which
-- family we're in, and Forever is new enough that assumptions go stale.
local FEATURES = {
  healPrediction   = function() return UnitGetIncomingHeals ~= nil end,
  absorbs          = function() return UnitGetTotalAbsorbs ~= nil end,
  focusUnit        = function() return FocusFrame ~= nil or _G.FocusFrame ~= nil end,
  bossFrames       = function() return compat.interface >= 30000 end,
  arenaFrames      = function() return compat.interface >= 30000 end,
  classResources   = function() return compat.IsRetail end,
  specializations  = function() return GetSpecialization ~= nil end,
  nameplates       = function() return C_NamePlate ~= nil end,
  auraDataByIndex  = function() return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex ~= nil end,
  spellBookModern  = function() return C_SpellBook and C_SpellBook.GetSpellBookItemInfo ~= nil end,
  petBattles       = function() return C_PetBattles ~= nil end,
  itemLevelApi     = function() return GetDetailedItemLevelInfo ~= nil end,
  roleAssignments  = function() return GetPartyAssignment ~= nil end,
}

local cache = {}

function compat.HasFeature(name)
  if cache[name] == nil then
    local test = FEATURES[name]
    cache[name] = test and test() or false
  end
  return cache[name]
end

-- For tests and for /fui version.
function compat.Describe()
  local family = compat.IsForever and "Forever" or compat.IsClassicEra and "Classic Era"
    or compat.IsRetail and "Retail" or "Classic"
  return ("%s (interface %d)"):format(family, compat.interface)
end
