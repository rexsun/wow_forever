local _, OSG = ...

-- RestedXP Guides keeps its settings in the AceDB "RXPSettings". The live table is
-- RXP.settings.profile, the active character's profile, which a profile switch replaces
-- (SettingsPanel.lua RefreshProfile), so it is read fresh every time. A locked setting is
-- switched off in every copy RXP may load it from:
--   the live profile            this character
--   RXPSettings.profiles[name]  every character's stored profile (account file)
--   RXPData.defaultProfile      the account-wide template new profiles start from
--   RXPCData.localDB            this character's fallback template
-- AceDB leaves out stored values equal to the template, so a missing stored value means
-- the template's, or else RXP's built-in default (SettingsPanel.lua settingsDBDefaults).
local adapter = {}
OSG.adapters.RestedXP = adapter

-- `inverted`: RXP stores the opposite switch, so "on" means the stored flag is false.
local KEYS = {
  AutoSellJunk = { field = "autoSellJunk", default = false },
  TalentGuides = { field = "enableTalentGuides", default = true },
  MaxNameplateDistance = { field = "enableMaxNameplateDistance", default = true },
  UpgradeTooltip = { field = "disableUpgradeTooltip", default = false, inverted = true },
}
local OPTIONS_APP = "RestedXP Guides"

local function LiveProfile()
  local rxp = _G.RXP
  local profile = type(rxp) == "table" and type(rxp.settings) == "table" and rxp.settings.profile
  return type(profile) == "table" and profile or nil
end

local function Template(holder)
  local profile = type(holder) == "table" and holder.profile
  return type(profile) == "table" and profile or nil
end

local function AccountTemplate()
  return type(_G.RXPData) == "table" and Template(_G.RXPData.defaultProfile) or nil
end

local function CharacterTemplate()
  return type(_G.RXPCData) == "table" and Template(_G.RXPCData.localDB) or nil
end

local function Stored(spec, store, fallback)
  local value = store[spec.field]
  if value == nil and fallback then
    value = fallback[spec.field]
  end
  if value == nil then
    value = spec.default
  end
  return value == true
end

local function IsOn(spec, store, fallback)
  local value = Stored(spec, store, fallback)
  if spec.inverted then
    return not value
  end
  return value
end

local function SwitchOff(spec, store)
  store[spec.field] = spec.inverted and true or false
end

-- Every copy other than the live profile, each with a name for the chat line and the
-- template a missing value falls back to.
local function OtherCopies(live)
  local copies = {}
  local account, character = AccountTemplate(), CharacterTemplate()
  if account then
    copies[#copies + 1] = { name = "account default", store = account }
  end
  if character then
    copies[#copies + 1] = { name = "character default", store = character }
  end
  local profiles = type(_G.RXPSettings) == "table" and _G.RXPSettings.profiles
  if type(profiles) == "table" then
    for name, profile in pairs(profiles) do
      if type(profile) == "table" and not rawequal(profile, live) then
        copies[#copies + 1] = { name = tostring(name), store = profile, fallback = account }
      end
    end
  end
  return copies
end

function adapter.Knows(key)
  return KEYS[key] ~= nil
end

function adapter.Read(key)
  local live = LiveProfile()
  if not live then
    return nil, "RestedXP Guides has not finished loading"
  end
  local spec = KEYS[key]
  if IsOn(spec, live) then
    return true
  end
  for _, copy in ipairs(OtherCopies(live)) do
    if IsOn(spec, copy.store, copy.fallback) then
      return true
    end
  end
  return false
end

-- Returns true, whether the live value was on (the rule says if that needs a reload),
-- and the names of the other copies that were changed.
function adapter.Revert(key)
  local live = LiveProfile()
  if not live then
    return false, "RestedXP Guides has not finished loading"
  end
  local spec = KEYS[key]
  local liveWasOn = IsOn(spec, live)
  if liveWasOn then
    SwitchOff(spec, live)
  end
  local changed = {}
  for _, copy in ipairs(OtherCopies(live)) do
    if IsOn(spec, copy.store, copy.fallback) then
      SwitchOff(spec, copy.store)
      changed[#changed + 1] = copy.name
    end
  end
  table.sort(changed)
  return true, liveWasOn, changed
end

-- RXP's options panel is AceConfig; AceConfigDialog calls NotifyChange after every
-- change. Slash commands and profile switches reach no hook; Guard.lua's ticker
-- catches those.
function adapter.Watch(onChange)
  local registry = type(LibStub) == "table" and LibStub("AceConfigRegistry-3.0", true)
  if registry and type(registry.NotifyChange) == "function" then
    hooksecurefunc(registry, "NotifyChange", function(_, app)
      if app == OPTIONS_APP then
        onChange()
      end
    end)
  end
end
