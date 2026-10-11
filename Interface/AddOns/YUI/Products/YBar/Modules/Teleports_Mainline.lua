local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Teleports") end
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end
local GUI2 = YUI.GUI2
local YBar = YUI.YBar
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local API = YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or API
local CombatAPI = YUI.API and YUI.API.Combat or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local ItemAPI = YUI.API and YUI.API.Item or API
local SpellAPI = YUI.API and YUI.API.Spell or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local Module = YBar.Module:New("Teleports")

-- Constants
local DEFAULT_ICON_SIZE = 14
local BAR_ICON_SIZE_OFFSET = 2
local DEFAULT_FONT = STANDARD_TEXT_FONT
local HEARTHSTONE_ITEM_ID = 6948
local ANNOUNCE_KIND_PORTAL = "portal"
local ANNOUNCE_KIND_DUNGEON = "dungeon"
local MenuFrame = nil

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

local function CopyHousingData(houseInfoList)
    local result = {}
    if type(houseInfoList) ~= "table" then
        return result
    end

    for _, houseInfo in ipairs(houseInfoList) do
        if type(houseInfo) == "table" then
            result[#result + 1] = {
                neighborhoodGUID = houseInfo.neighborhoodGUID,
                houseGUID = houseInfo.houseGUID,
                plotID = houseInfo.plotID,
            }
        end
    end

    return result
end

local TP_MENU_NAME = YUI.F:GetGradientText(T("teleports.tooltip.title", "传送菜单"), {0.84, 0.41, 1}, {0.64, 0.21, 0.93})

local function IsTeleportFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and
        not frame.errorText and frame.text and (frame.iconSlot or frame.icon) and
        frame.secure
end

-- SubMenu Layout Constants
local SM_COLUMNS = 8
local SM_ITEM_WIDTH = 50
local SM_ITEM_HEIGHT = 46
local SM_PADDING_X = 2
local SM_PADDING_Y = 2
local SM_ICON_SIZE = 32
local SM_FONT_SIZE = 11
local SM_TAB_ICON_SIZE = 12
local MENU_GAP = 2
local MENU_TOLERANCE = 8
local MENU_SCREEN_PADDING = 8
local MENU_CLOSE_DELAY = 0.3
local MENU_SWITCH_DELAY = 0.11
local MENU_AIM_DELAY = 0.45

local function FormatTime(seconds)
    if seconds >= 86400 then
        return string.format("%dd", math.ceil(seconds / 86400))
    elseif seconds >= 3600 then
        return string.format("%dh", math.ceil(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%ds", seconds)
    end
end

local function GetItemCooldownValues(itemID)
    local info = ItemAPI.GetCooldown and ItemAPI.GetCooldown(itemID)
    if info then
        return info.startTime or 0, info.duration or 0, info.isEnabled
    end

    return 0, 0, nil
end

local function GetSpellCooldownInfo(spellID)
    return SpellAPI.GetCooldown and SpellAPI.GetCooldown(spellID) or nil
end

local function IsSecretValue(value)
    return SecurityAPI and SecurityAPI.IsSecretValue and SecurityAPI.IsSecretValue(value) == true
end

local function SafeCooldownNumber(value)
    if value == nil or IsSecretValue(value) then
        return nil
    end

    local ok, numberValue = pcall(tonumber, value)
    if not ok or numberValue == nil or IsSecretValue(numberValue) then
        return nil
    end

    return numberValue
end

local function GetSafeCooldownValues(start, duration)
    return SafeCooldownNumber(start), SafeCooldownNumber(duration)
end

local function GetSafeCurrentTime()
    local now
    if CombatAPI and CombatAPI.GetTime then
        now = CombatAPI.GetTime()
    elseif GetTime then
        now = GetTime()
    end

    return SafeCooldownNumber(now)
end

local function GetSafeItemCooldownValues(itemID)
    local start, duration = GetItemCooldownValues(itemID)
    return GetSafeCooldownValues(start, duration)
end

local function GetSafeCooldownRemaining(start, duration)
    start, duration = GetSafeCooldownValues(start, duration)
    if not start or not duration or start <= 0 or duration <= 0 then
        return nil, start, duration
    end

    local now = GetSafeCurrentTime()
    if not now then
        return nil, start, duration
    end

    local remaining = duration - (now - start)
    if remaining > 0 then
        return remaining, start, duration
    end

    return nil, start, duration
end

local function GetSafeTeleportCooldownValues(itemData)
    if not itemData then
        return nil, nil
    end

    if itemData.type == "toy" or itemData.type == "item" then
        return GetSafeItemCooldownValues(itemData.id)
    elseif itemData.type == "spell" then
        local info = GetSpellCooldownInfo(itemData.id)
        if info then
            return GetSafeCooldownValues(info.startTime, info.duration)
        end
    elseif itemData.type == "housing" and C_Housing and C_Housing.GetVisitCooldownInfo then
        if not itemData.canReturn then
            local info = C_Housing.GetVisitCooldownInfo()
            if info and info.isEnabled then
                return GetSafeCooldownValues(info.startTime, info.duration)
            end
        end
    end

    return nil, nil
end

local function UpdateMenuButtonCooldown(btn, itemData)
    if not btn or not btn.cooldown then
        return
    end

    local start, duration = GetSafeTeleportCooldownValues(itemData)
    if start and duration and duration > 0 then
        btn.cooldown:SetCooldown(start, duration)
        btn.cooldown:Show()
    else
        btn.cooldown:Hide()
    end
end

local DATA = YBar.TeleportCatalog
local ITEM_USAGE_NONE, ITEM_USAGE_TOY, ITEM_USAGE_EQUIPMENT = 0, 1, 2
local ITEM_HISTORICAL_FLAG = 8

local function GetItemUsage(id)
    local flags = DATA.Items[id]
    return flags and flags % ITEM_HISTORICAL_FLAG
end

local function IsHistoricalHearthstone(id)
    local flags = id and DATA.Items[id]
    return flags and flags >= ITEM_HISTORICAL_FLAG
end

local DUNGEON_TELEPORT_VARIANTS = DATA.DungeonVariants

local MAGE_PORTAL_IDS = {}
for _, id in ipairs(DATA.MagePortals) do
    MAGE_PORTAL_IDS[id] = true
end

local function ResolveSpellByPreference(prefer, fallback)
    if prefer and SpellAPI.IsKnown(prefer) then return prefer end
    if fallback and SpellAPI.IsKnown(fallback) then return fallback end
    return prefer or fallback
end

function Module:ResolveDungeonTeleportSpellID(canonicalId)
    local v = DUNGEON_TELEPORT_VARIANTS[canonicalId]
    if not v then return canonicalId end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
    local prefer = (faction == "Horde") and v.Horde or v.Alliance
    local fallback = (prefer == v.Horde) and v.Alliance or v.Horde
    return ResolveSpellByPreference(prefer, fallback) or canonicalId
end

-- Name Overrides / Short Names
local NAME_MAPPING = {
    -- Expansions (Headers)
    ["Cataclysm"] = {"teleports.menu.expansion_cataclysm", "Cataclysm"},
    ["Mists"] = {"teleports.menu.expansion_mists", "Mists"},
    ["Warlords"] = {"teleports.menu.expansion_warlords", "Warlords"},
    ["Legion"] = {"teleports.menu.expansion_legion", "Legion"},
    ["BFA"] = {"teleports.menu.expansion_bfa", "Battle for Azeroth"},
    ["Shadowlands"] = {"teleports.menu.expansion_shadowlands", "Shadowlands"},
    ["Dragonflight"] = {"teleports.menu.expansion_dragonflight", "Dragonflight"},
    ["TWW"] = {"teleports.menu.expansion_tww", "The War Within"},
    ["Midnight"] = {"teleports.menu.expansion_midnight", "Midnight"},

    -- Engineering (Wormholes)
    [30542] = {"teleports.map.30542", "Area 52"},         -- Dimensional Ripper - Area 52
    [18984] = {"teleports.map.18984", "Everlook"},       -- Dimensional Ripper - Everlook
    [18986] = {"teleports.map.18986", "Gadgetzan"},       -- Ultrasafe Transporter: Gadgetzan
    [30544] = {"teleports.map.30544", "Toshley"},       -- Ultrasafe Transporter: Toshley's Station
    [48933] = {"teleports.map.48933", "Northrend"},       -- Wormhole Generator: Northrend
    [87215] = {"teleports.map.87215", "Pandaria"},     -- Wormhole Generator: Pandaria
    [112059] = {"teleports.map.112059", "Draenor"},      -- Wormhole Centrifuge (Draenor)
    [151652] = {"teleports.map.151652", "Argus"},      -- Wormhole Generator: Argus
    [168807] = {"teleports.map.168807", "Kul Tiras"},  -- Wormhole Generator: Kul Tiras
    [168808] = {"teleports.map.168808", "Zandalar"},      -- Wormhole Generator: Zandalar
    [172924] = {"teleports.map.172924", "Shadowlands"},      -- Wormhole Generator: Shadowlands
    [198156] = {"teleports.map.198156", "Dragon Isles"},    -- Wyrmhole Generator: Dragon Isles
    [221966] = {"teleports.map.221966", "Khaz Algar"},  -- Wormhole Generator: Khaz Algar
    [248485] = {"teleports.map.248485", "Quel'Salas"},  -- Wormhole Generator: Quel'Thalas

    -- Items
    [43824] = {"teleports.map.43824", "Violet"},
    [136849] = {"teleports.map.136849", "Nature"},
    [140324] = {"teleports.map.140324", "Shal'Aran"},
    [169298] = {"teleports.map.169298", "Frostwolf"},
    -- Kirin Tor Rings
    [32757] = {"teleports.map.32757", "Karabor"},       -- Blessed Medallion of Karabor
    [37863] = {"teleports.map.37863", "Direbrew"},     -- Direbrew's Remote
    [40586] = {"teleports.map.40586", "Kirin"},       -- Band of the Kirin Tor
    [44935] = {"teleports.map.44935", "Kirin"},       -- Ring of the Kirin Tor
    [40585] = {"teleports.map.40585", "Kirin"},       -- Signet of the Kirin Tor
    [44934] = {"teleports.map.44934", "Kirin"},       -- Loop of the Kirin Tor
    [45688] = {"teleports.map.45688", "Kirin"},       -- Inscribed Band of the Kirin Tor
    [45690] = {"teleports.map.45690", "Kirin"},       -- Inscribed Ring of the Kirin Tor
    [45691] = {"teleports.map.45691", "Kirin"},       -- Inscribed Signet of the Kirin Tor
    [45689] = {"teleports.map.45689", "Kirin"},       -- Inscribed Loop of the Kirin Tor
    [48954] = {"teleports.map.48954", "Kirin"},       -- Etched Band of the Kirin Tor
    [48955] = {"teleports.map.48955", "Kirin"},       -- Etched Loop of the Kirin Tor
    [48956] = {"teleports.map.48956", "Kirin"},       -- Etched Ring of the Kirin Tor
    [48957] = {"teleports.map.48957", "Kirin"},       -- Etched Signet of the Kirin Tor
    [51557] = {"teleports.map.51557", "Kirin"},       -- Runed Signet of the Kirin Tor
    [51558] = {"teleports.map.51558", "Kirin"},       -- Runed Loop of the Kirin Tor
    [51559] = {"teleports.map.51559", "Kirin"},       -- Runed Ring of the Kirin Tor
    [51560] = {"teleports.map.51560", "Kirin"},       -- Runed Band of the Kirin Tor
    [52251] = {"teleports.map.52251", "Jaina"},       -- Jaina's Locket

    -- Guild Cloaks
    -- [63206] = "暴风城",       -- Wrap of Unity (Alliance)
    -- [63207] = "奥格",         -- Wrap of Unity (Horde)
    -- [63352] = "暴风城",       -- Shroud of Cooperation (Alliance)
    -- [63353] = "奥格",         -- Shroud of Cooperation (Horde)
    -- [65274] = "奥格",         -- Cloak of Coordination (Horde)
    -- [65360] = "暴风城",       -- Cloak of Coordination (Alliance)

    -- Other Items
    [46874] = {"teleports.map.46874", "Argent"},       -- Argent Crusader's Tabard
    [50287] = {"teleports.map.50287", "Booty Bay"},     -- Boots of the Bay
    [58487] = {"teleports.map.58487", "Deepholm"},     -- Potion of Deepholm
    [61379] = {"teleports.map.61379", "Gidwin"},       -- Gidwin's Hearthstone
    [63378] = {"teleports.map.63378", "Tol Barad"},   -- Hellscream's Reach Tabard
    [63379] = {"teleports.map.63379", "Tol Barad"},   -- Baradin's Wardens Tabard
    [64457] = {"teleports.map.64457", "Argus"},       -- The Last Relic of Argus
    [68808] = {"teleports.map.68808", "Hero HS"},
    [68809] = {"teleports.map.68809", "Veteran HS"},
    [87548] = {"teleports.map.87548", "Lorewalker"},       -- Lorewalker's Lodestone
    [92510] = {"teleports.map.92510", "Vol'jin"},         -- Vol'jin's Hearthstone
    [95050] = {"teleports.map.95050", "Brawl"},         -- The Brassiest Knuckle (Horde)
    [95051] = {"teleports.map.95051", "Brawl"},         -- The Brassiest Knuckle (Alliance)
    [95567] = {"teleports.map.95567", "Kirin"},       -- Kirin Tor Beacon
    [95568] = {"teleports.map.95568", "Sunreaver"},       -- Sunreaver Beacon
    [103678] = {"teleports.map.103678", "Time-Lost"},    -- Time-Lost Artifact
    [117389] = {"teleports.map.117389", "Archaeology"},        -- Draenor Archaeologist's Lodestone
    [118662] = {"teleports.map.118662", "Bladespire"},    -- Bladespire Relic
    [118663] = {"teleports.map.118663", "Karabor"},      -- Relic of Karabor
    [118907] = {"teleports.map.118907", "Brawl"},        -- Pit Fighter's Punching Ring (Alliance)
    [118908] = {"teleports.map.118908", "Brawl"},        -- Pit Fighter's Punching Ring (Horde)
    [119183] = {"teleports.map.119183", "Risky"},        -- Scroll of Risky Recall
    [128353] = {"teleports.map.128353", "Shipyard"},        -- Admiral's Compass
    [128502] = {"teleports.map.128502", "Tanaan"},      -- Hunter's Seeking Crystal
    [128503] = {"teleports.map.128503", "Tanaan"},      -- Master Hunter's Seeking Crystal
    [129276] = {"teleports.map.129276", "Dalaran"},      -- Beginner's Guide to Dimensional Rifting
    [132119] = {"teleports.map.132119", "Orgrimmar"},        -- Orgrimmar Portal Stone
    [132120] = {"teleports.map.132120", "Stormwind"},      -- Stormwind Portal Stone
    [132517] = {"teleports.map.132517", "Dalaran"},      -- Intra-Dalaran Wormhole Generator
    [132523] = {"teleports.map.132523", "Reaves"},      -- Reaves Battery
    [138448] = {"teleports.map.138448", "Margoss"},        -- Emblem of Margoss
    [139590] = {"teleports.map.139590", "Ravenholdt"},    -- Scroll of Teleport: Ravenholdt
    [139599] = {"teleports.map.139599", "Kirin"},      -- Empowered Ring of the Kirin Tor
    [140493] = {"teleports.map.140493", "Azsuna"},      -- Adept's Guide to Dimensional Rifting
    [141013] = {"teleports.map.141013", "Shala'nir"},    -- Scroll of Town Portal: Shala'nir
    [141014] = {"teleports.map.141014", "Sashj'tar"},      -- Scroll of Town Portal: Sashj'tar
    [141015] = {"teleports.map.141015", "Kal'delar"},      -- Scroll of Town Portal: Kal'delar
    [141016] = {"teleports.map.141016", "Faronaar"},    -- Scroll of Town Portal: Faronaar
    [141017] = {"teleports.map.141017", "Lian'tril"},      -- Scroll of Town Portal: Lian'tril
    [141324] = {"teleports.map.141324", "Shal'dorei"},    -- Talisman of the Shal'dorei
    [141605] = {"teleports.map.141605", "Whistle"},    -- Flight Master's Whistle
    [142298] = {"teleports.map.142298", "Ruby Shoes"},      -- Astonishingly Scarlet Slippers
    [142469] = {"teleports.map.142469", "Karazhan"},      -- Violet Seal of the Grand Magus
    [142543] = {"teleports.map.142543", "Diablo"},        -- Scroll of Town Portal (Diablo 3)
    [144341] = {"teleports.map.144341", "Reaves"},      -- Rechargeable Reaves Battery
    [144391] = {"teleports.map.144391", "Brawl"},        -- Pugilist's Powerful Punching Ring
    [144392] = {"teleports.map.144392", "Brawl"},        -- Pugilist's Powerful Punching Ring
    [150733] = {"teleports.map.150733", "Arathi"},      -- Scroll of Town Portal (Ar'gorok)
    [151016] = {"teleports.map.151016", "Black Temple"},        -- Fractured Necrolyte Skull
    [159224] = {"teleports.map.159224", "Zuldazar"},      -- Zuldazar Hearthstone
    [160219] = {"teleports.map.160219", "Arathi"},      -- Scroll of Town Portal (Stromgarde)
    [163694] = {"teleports.map.163694", "Luxurious"},        -- Scroll of Luxurious Recall
    [166559] = {"teleports.map.166559", "Boralus"},    -- Commander's Signet of Battle
    [166560] = {"teleports.map.166560", "Dazar'alor"},      -- Captain's Signet of Command
    [167075] = {"teleports.map.167075", "Mechagon"},      -- Ultrasafe Transporter: Mechagon
    [168862] = {"teleports.map.168862", "Grom"},      -- G.E.A.R. Tracking Beacon
    [169064] = {"teleports.map.169064", "Cloak"},        -- Montebank's Colorful Cloak
    [169297] = {"teleports.map.169297", "Alterac"},        -- Stormpike Insignia
    [172203] = {"teleports.map.172203", "Cracked"},        -- Cracked Hearthstone
    [173373] = {"teleports.map.173373", "Faol"},        -- Faol's Hearthstone
    [173430] = {"teleports.map.173430", "Coldarra"},      -- Nexus Teleport Scroll
    [173528] = {"teleports.map.173528", "Gilded"},        -- Gilded Hearthstone
    [173532] = {"teleports.map.173532", "Tirisfal"},    -- Tirisfal Camp Scroll
    [173537] = {"teleports.map.173537", "Glowing"},        -- Glowing Hearthstone
    [173716] = {"teleports.map.173716", "Mossy"},    -- Mossy Hearthstone
    [180817] = {"teleports.map.180817", "Ve'nari"},      -- Cypher of Relocation
    [181163] = {"teleports.map.181163", "Theater"},    -- Scroll of Teleport: Theater of Pain
    [184500] = {"teleports.map.184500", "Bastion"},    -- Attendant's Pocket Portal: Bastion
    [184501] = {"teleports.map.184501", "Revendreth"},    -- Attendant's Pocket Portal: Revendreth
    [184502] = {"teleports.map.184502", "Maldraxxus"},  -- Attendant's Pocket Portal: Maldraxxus
    [184503] = {"teleports.map.184503", "Ardenweald"},    -- Attendant's Pocket Portal: Ardenweald
    [184504] = {"teleports.map.184504", "Oribos"},    -- Attendant's Pocket Portal: Oribos
    [189827] = {"teleports.map.189827", "Cartel"},        -- Cartel Xy's Proof of Initiation
    [191029] = {"teleports.map.191029", "Lilian"},      -- Lilian's Hearthstone
    [193000] = {"teleports.map.193000", "Hourglass"},        -- Ring-Bound Hourglass
    [200613] = {"teleports.map.200613", "Aylaag"},      -- Aylaag Windstone Fragment
    [201957] = {"teleports.map.201957", "Thrall"},        -- Thrall's Hearthstone
    [202046] = {"teleports.map.202046", "Tortollan"},      -- Lucky Tortollan Charm
    [204481] = {"teleports.map.204481", "Morqut"},      -- Morqut Hearth Totem
    [205255] = {"teleports.map.205255", "Niffen"},      -- Niffen Diggin' Mitts
    [205456] = {"teleports.map.205456", "Dragonscale"},        -- Lost Dragonscale
    [205458] = {"teleports.map.205458", "Dragonscale"},        -- Lost Dragonscale
    [211788] = {"teleports.map.211788", "Tess"},        -- Tess's Peacebloom
    [230850] = {"teleports.map.230850", "Delve-Bot"},      -- Delve-O-Bot 7001
    [234389] = {"teleports.map.234389", "Gallagio"},  -- Gallagio Loyalty Rewards (Silver)
    [234390] = {"teleports.map.234390", "Gallagio"},  -- Gallagio Loyalty Rewards (Gold)
    [234391] = {"teleports.map.234391", "Gallagio"},  -- Gallagio Loyalty Rewards (Platinum)
    [234392] = {"teleports.map.234392", "Gallagio"},  -- Gallagio Loyalty Rewards (Black)
    [234393] = {"teleports.map.234393", "Gallagio"},  -- Gallagio Loyalty Rewards (Diamond)
    [234394] = {"teleports.map.234394", "Gallagio"},  -- Gallagio Loyalty Rewards (Legendary)
    [238727] = {"teleports.map.238727", "Nostwin"},      -- Nostwin's Voucher
    [243056] = {"teleports.map.243056", "Pathfinder"},      -- Delver's Mana-Bound Ethergate
    [249699] = {"teleports.map.249699", "Shadowguard"},        -- Shadowguard Translocator
    [253629] = {"teleports.menu.arcane_society", "Arcane Society"},
    [266370] = {"teleports.map.266370", "Bountiful"},        -- Bountiful Hearthstone
    [276371] = {"teleports.map.276371", "Lightveil"},        -- Lightveil Recall Beacon

    -- Mage Teleports/Portals
    [3561] = {"teleports.map.3561", "Stormwind"},
    [3562] = {"teleports.map.3562", "Ironforge"},
    [3565] = {"teleports.map.3565", "Darnassus"},
    [32271] = {"teleports.map.32271", "Exodar"},
    [49359] = {"teleports.map.49359", "Theramore"},
    [176248] = {"teleports.map.176248", "Stormshield"},
    [281403] = {"teleports.map.281403", "Boralus"},
    [10059] = {"teleports.map.10059", "Stormwind"}, -- Portal
    [11416] = {"teleports.map.11416", "Ironforge"}, -- Portal
    [11419] = {"teleports.map.11419", "Darnassus"}, -- Portal
    [32266] = {"teleports.map.32266", "Exodar"}, -- Portal
    [49360] = {"teleports.map.49360", "Theramore"}, -- Portal
    [176246] = {"teleports.map.176246", "Stormshield"}, -- Portal
    [281400] = {"teleports.map.281400", "Boralus"}, -- Portal
    [3563] = {"teleports.map.3563", "Undercity"},
    [3566] = {"teleports.map.3566", "Thunder Bluff"},
    [3567] = {"teleports.map.3567", "Orgrimmar"},
    [32272] = {"teleports.map.32272", "Silvermoon"},
    [49358] = {"teleports.map.49358", "Stonard"},
    [176242] = {"teleports.map.176242", "Warspear"},
    [281404] = {"teleports.map.281404", "Dazar'alor"},
    [11418] = {"teleports.map.11418", "Undercity"}, -- Portal
    [11420] = {"teleports.map.11420", "Thunder Bluff"}, -- Portal
    [11417] = {"teleports.map.11417", "Orgrimmar"}, -- Portal
    [32267] = {"teleports.map.32267", "Silvermoon"}, -- Portal
    [49361] = {"teleports.map.49361", "Stonard"}, -- Portal
    [176244] = {"teleports.map.176244", "Warspear"}, -- Portal
    [281402] = {"teleports.map.281402", "Dazar'alor"}, -- Portal
    [33690] = {"teleports.map.33690", "Shattrath"},
    [35715] = {"teleports.map.35715", "Shattrath"},
    [53140] = {"teleports.map.53140", "Dalaran NR"},
    [88342] = {"teleports.map.88342", "Tol Barad"},
    [88344] = {"teleports.map.88344", "Tol Barad"},
    [120145] = {"teleports.map.120145", "Dalaran Old"},
    [132621] = {"teleports.map.132621", "Vale"},
    [132627] = {"teleports.map.132627", "Vale"},
    [193759] = {"teleports.map.193759", "Guardian"},
    [224869] = {"teleports.map.224869", "Dalaran LG"},
    [344587] = {"teleports.map.344587", "Oribos"},
    [395277] = {"teleports.map.395277", "Valdrakken"},
    [446540] = {"teleports.map.446540", "Dornogal"},
    [33691] = {"teleports.map.33691", "Shattrath"}, -- Portal
    [35717] = {"teleports.map.35717", "Shattrath"}, -- Portal
    [53142] = {"teleports.map.53142", "Dalaran NR"}, -- Portal
    [88345] = {"teleports.map.88345", "Tol Barad"}, -- Portal
    [88346] = {"teleports.map.88346", "Tol Barad"}, -- Portal
    [120146] = {"teleports.map.120146", "Dalaran Old"}, -- Portal
    [132620] = {"teleports.map.132620", "Vale"}, -- Portal
    [132626] = {"teleports.map.132626", "Vale"}, -- Portal
    [224871] = {"teleports.map.224871", "Dalaran LG"}, -- Portal
    [344597] = {"teleports.map.344597", "Oribos"}, -- Portal
    [395289] = {"teleports.map.395289", "Valdrakken"}, -- Portal
    [446534] = {"teleports.map.446534", "Dornogal"}, -- Portal

    [1259190] = {"teleports.map.1259190", "Silvermoon"}, -- Teleport
    [1259194] = {"teleports.map.1259194", "Silvermoon"}, -- Portal

    -- Dungeons
    [410080] = {"teleports.map.410080", "Vortex"},
    [424142] = {"teleports.map.424142", "Tides"},
    [445424] = {"teleports.map.445424", "Grim Batol"},
    [131204] = {"teleports.map.131204", "Jade"},
    [131205] = {"teleports.map.131205", "Stormstout"},
    [131206] = {"teleports.map.131206", "Shado-Pan"},
    [131222] = {"teleports.map.131222", "Mogu'shan"},
    [131225] = {"teleports.map.131225", "Gate"},
    [131228] = {"teleports.map.131228", "Niuzao"},
    [131229] = {"teleports.map.131229", "Monastery"},
    [131231] = {"teleports.map.131231", "Halls"},
    [131232] = {"teleports.map.131232", "Scholo"},
    [159901] = {"teleports.map.159901", "Everbloom"},
    [159899] = {"teleports.map.159899", "Shadowmoon"},
    [159900] = {"teleports.map.159900", "Grimrail"},
    [159896] = {"teleports.map.159896", "Iron Docks"},
    [159895] = {"teleports.map.159895", "Bloodmaul"},
    [159897] = {"teleports.map.159897", "Auchindoun"},
    [159898] = {"teleports.map.159898", "Skyreach"},
    [159902] = {"teleports.map.159902", "UBRS"},
    [393764] = {"teleports.map.393764", "HoV"},
    [410078] = {"teleports.map.410078", "Neltharion"},
    [393766] = {"teleports.map.393766", "CoS"},
    [373262] = {"teleports.map.373262", "Karazhan"},
    [424153] = {"teleports.map.424153", "BRH"},
    [424163] = {"teleports.map.424163", "DHT"},
    [410071] = {"teleports.map.410071", "Freehold"},
    [410074] = {"teleports.map.410074", "Underrot"},
    [373274] = {"teleports.map.373274", "Mechagon"},
    [424167] = {"teleports.map.424167", "Waycrest"},
    [424187] = {"teleports.map.424187", "Atal"},
    [445418] = {"teleports.map.445418", "Siege"},
    [464256] = {"teleports.map.464256", "Siege"},
    [467553] = {"teleports.map.467553", "Motherlode"},
    [467555] = {"teleports.map.467555", "Motherlode"},
    [354462] = {"teleports.map.354462", "Necrotic"},
    [354463] = {"teleports.map.354463", "Plaguefall"},
    [354464] = {"teleports.map.354464", "Mists"},
    [354465] = {"teleports.map.354465", "Halls"},
    [354466] = {"teleports.map.354466", "Spires"},
    [354467] = {"teleports.map.354467", "Theater"},
    [354468] = {"teleports.map.354468", "De Other"},
    [354469] = {"teleports.map.354469", "Sanguine"},
    [367416] = {"teleports.map.367416", "Streets"},
    [373190] = {"teleports.map.373190", "Nathria"},
    [373191] = {"teleports.map.373191", "Sanctum"},
    [373192] = {"teleports.map.373192", "Sepulcher"},
    [393256] = {"teleports.map.393256", "RLP"},
    [393262] = {"teleports.map.393262", "Nokhud"},
    [393267] = {"teleports.map.393267", "Bracken"},
    [393273] = {"teleports.map.393273", "Academy"},
    [393276] = {"teleports.map.393276", "Neltharus"},
    [393279] = {"teleports.map.393279", "Azure"},
    [393283] = {"teleports.map.393283", "HoI"},
    [393222] = {"teleports.map.393222", "Uldaman"},
    [424197] = {"teleports.map.424197", "Dawn"},
    [432254] = {"teleports.map.432254", "Vault"},
    [432257] = {"teleports.map.432257", "Aberrus"},
    [432258] = {"teleports.map.432258", "Amirdrassil"},
    [445416] = {"teleports.map.445416", "Threads"},
    [445414] = {"teleports.map.445414", "Dawnbreaker"},
    [445269] = {"teleports.map.445269", "Stonevault"},
    [445443] = {"teleports.map.445443", "Rookery"},
    [445440] = {"teleports.map.445440", "Cinderbrew"},
    [445444] = {"teleports.map.445444", "Priory"},
    [445417] = {"teleports.map.445417", "Ara-Kara"},
    [445441] = {"teleports.map.445441", "Darkflame"},
    [1216786] = {"teleports.map.1216786", "Floodgate"},
    [1237215] = {"teleports.map.1237215", "Eco-Dome"},
    [1226482] = {"teleports.map.1226482", "Undermine"},
    [1239155] = {"teleports.map.1239155", "Omega"},

    [1254572] = {"teleports.map.1254572", "Magisters"},
    [1254400] = {"teleports.map.1254400", "Windrunner"},
    [1254557] = {"teleports.map.1254557", "Skyreach"},
    [1254559] = {"teleports.map.1254559", "Cave"},
    [1254555] = {"teleports.map.1254555", "Saron"},
    [1254563] = {"teleports.map.1254563", "NPX"},
    -- [393273] = "学院",
    [1254551] = {"teleports.map.1254551", "Seat"},

    [1286801] = {"teleports.map.1286801", "VALE"},
    [1286804] = {"teleports.map.1286804", "VOID"},
    [1286807] = {"teleports.map.1286807", "NALO"},
    [1286809] = {"teleports.map.1286809", "MURD"},
    [1286812] = {"teleports.map.1286812", "FANG"},
    [1286828] = {"teleports.map.1286828", "TOS"},
    [1286831] = {"teleports.map.1286831", "KR"},

    -- Class Spells
    [446540] = {"teleports.map.446540", "Dornogal"},
    [446534] = {"teleports.map.446534", "Dornogal"},
    [50977] = {"teleports.map.50977", "Death Gate"},
    [193753] = {"teleports.map.193753", "Dreamway"},
    [18960] = {"teleports.map.18960", "Moonglade"},
    [126892] = {"teleports.map.126892", "Zen"},
    [556] = {"teleports.map.556", "Astral"},
}

local function GetNameMapping(key)
    local mapped = NAME_MAPPING[key]
    if type(mapped) == "table" then
        return T(mapped[1], mapped[2])
    end
    return mapped
end

-- Special Hearthstones
local SPECIAL_HEARTHSTONES = {
    Dalaran = 140192,
    Garrison = 110560,
    Homestead_Alliance = 1233637,
    Homestead_Horde = 1233637,
}

local COVENANT_HEARTHSTONES = {
    [180290] = 3, -- Night Fae Hearthstone (Night Fae)
    [182773] = 4, -- Necrolord Hearthstone (Necrolord)
    [183716] = 2, -- Venthyr Sinstone (Venthyr)
    [184353] = 1, -- Kyrian Hearthstone (Kyrian)
}

function Module:OnInitialize()
    self.db = GetYBarDB().Teleports or {}
    -- Default settings
    if not self.db.font then self.db.font = DEFAULT_FONT end
    if not self.db.size then self.db.size = DEFAULT_ICON_SIZE end
    if not self.db.hearthstoneMode then self.db.hearthstoneMode = "fixed" end
    if self.db.hearthstoneMode == "normal" then self.db.hearthstoneMode = "fixed" end
    if self.db.showIcon == nil then self.db.showIcon = true end
    if self.db.seasonOnMainMenu == nil then self.db.seasonOnMainMenu = true end
    if not self.db.customHearthstone then self.db.customHearthstone = HEARTHSTONE_ITEM_ID end
    if not self.db.nextHearthstone then self.db.nextHearthstone = HEARTHSTONE_ITEM_ID end

    GetYBarDB().Teleports = self.db

    -- Cache known toys
    self.knownHearthstones = {}
    self:UpdateKnownHearthstones()

    -- 自动换装变量
    YBar.TeleportRestore:Cancel()
    self.equippingItemID = nil
    self.housingData = nil
    self.housingDataReady = false
    self.housingRequestPending = false
end

function Module:OnTeleportEvent(event, ...)
    if self._hasError then return end

    if event == "PLAYER_REGEN_ENABLED" and self._pendingDetach then
        self._pendingDetach = false
        self:DetachRuntime()
        return
    end

    if not self._runtimeAttached then
        return
    end

    if event == "YUI_WORLD_READY" then
        self:CheckAndReequip()
        self:UpdateKnownHearthstones()
        self:UpdateBarItem(self.frame)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.needsMenuHide then self:HideMenu() end
        self:CheckAndReequip()
        if self.needsUpdate then
            self.needsUpdate = false
            self:UpdateBarItem(self.frame)
        end
    elseif event == "COVENANT_CHOSEN" then
        self:UpdateKnownHearthstones()
        self:UpdateBarItem(self.frame)
    elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
        local housingInfo = ...
        self.housingRequestPending = false

        if type(housingInfo) == "table" then
            self.housingData = CopyHousingData(housingInfo)
            self.housingDataReady = true

            if MenuFrame and MenuFrame:IsShown() then
                if SecurityAPI.InCombatLockdown() then
                    self:HideMenu()
                else
                    self:PopulateMainMenu(MenuFrame)
                end
            end
        end
        self:UpdateBarItem(self.frame)
    elseif event == "HEARTHSTONE_BOUND"
        or event == "BAG_UPDATE_DELAYED"
        or event == "SPELL_UPDATE_COOLDOWN" then
        self:UpdateBarItem(self.frame)
    end
end

function Module:EnsureHousingData()
    if self.housingDataReady or self.housingRequestPending then
        return self.housingDataReady
    end

    if not (C_Housing and type(C_Housing.GetPlayerOwnedHouses) == "function") then
        self.housingData = {}
        self.housingDataReady = true
        return true
    end

    if type(C_Housing.IsHousingServiceEnabled) == "function"
        and not C_Housing.IsHousingServiceEnabled() then
        self.housingData = {}
        self.housingDataReady = true
        return true
    end

    self.housingRequestPending = true
    C_Housing.GetPlayerOwnedHouses()
    return self.housingDataReady
end

function Module:RegisterSecureEvents()
    if self.secureEventsRegistered then
        return
    end
    self.secureEventsRegistered = true

    YUI.Event:On("YUI_WORLD_READY", "OnTeleportEvent", self)
    YUI.Event:On("HEARTHSTONE_BOUND", "OnTeleportEvent", self)
    YUI.Event:On("BAG_UPDATE_DELAYED", "OnTeleportEvent", self)
    YUI.Event:On("SPELL_UPDATE_COOLDOWN", "OnTeleportEvent", self)
    YUI.Event:On("COVENANT_CHOSEN", "OnTeleportEvent", self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", "OnTeleportEvent", self)
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        YUI.Event:On("PLAYER_HOUSE_LIST_UPDATED", "OnTeleportEvent", self)
    end
end

function Module:AttachRuntime()
    if self._hasError then return end

    self._runtimeAttached = true
    self._pendingDetach = false

    if YUI.Event then
        YUI.Event:OffOwner(self)
        self.secureEventsRegistered = false
        YUI.Event:On("PLAYER_EQUIPMENT_CHANGED", "OnTeleportEvent", self)
    end

    self:RegisterSecureEvents()

    if IsTeleportFrameReady(self.frame) then
        self.frame:Show()
        self:UpdateBarItem(self.frame)
    end
end

function Module:DetachRuntime()
    self:HideMenuTooltip()
    self:CancelTooltipTimer()
    self:CancelCooldownTimer()
    self:StopHideTimer()
    self:StopSubMenuSwitch()
    if MenuFrame then MenuFrame:SetScript("OnUpdate", nil) end
    YBar.TeleportRestore:Cancel()
    self.housingRequestPending = false

    if SecurityAPI.InCombatLockdown() then
        self._runtimeAttached = false
        self._pendingDetach = true
        if YUI.Event then
            YUI.Event:OffOwner(self)
            self.secureEventsRegistered = false
            YUI.Event:On("PLAYER_REGEN_ENABLED", "OnTeleportEvent", self)
        end
        return
    end

    self._runtimeAttached = false
    self._pendingDetach = false

    if YUI.Event then
        YUI.Event:OffOwner(self)
        self.secureEventsRegistered = false
    end

    if MenuFrame and self.menuCombatDriver then
        UnregisterStateDriver(MenuFrame, "combat")
        self.menuCombatDriver = nil
    end

    if self.secure then
        self.secure:UnregisterAllEvents()
    end

    self:CancelTooltipTimer()
    self:CancelCooldownTimer()
    self:StopHideTimer()
    self:HideMenu()

    if GameTooltip then
        YUI.HideGameTooltip()
    end

    if self.frame then
        self.frame:Hide()
    end
end

function Module:OnDBReload()
    self:HideMenu()
    YBar.TeleportRestore:Cancel()
    self:OnInitialize()
    if self.frame then self:UpdateBarItem(self.frame, self.parent) end
end

function Module:CheckAndReequip()
    YBar.TeleportRestore:TryRestore()
end

function Module:UpdateKnownHearthstones()
    self.knownHearthstones = {}
    -- Add default hearthstone if available
    if ItemAPI.GetCount(HEARTHSTONE_ITEM_ID) > 0 then
        table.insert(self.knownHearthstones, HEARTHSTONE_ITEM_ID)
    end

    local covenantID = C_Covenants and C_Covenants.GetActiveCovenantID and C_Covenants.GetActiveCovenantID() or 0

    for _, id in ipairs(DATA.Hearthstones) do
        if PlayerHasToy(id) and (not IsHistoricalHearthstone(id) or
            (C_ToyBox.IsToyUsable(id) and ItemAPI.GetNameByID(id))) then
            -- Check Covenant Restriction
            local requiredCovenant = COVENANT_HEARTHSTONES[id]
            if requiredCovenant then
                if requiredCovenant == covenantID then
                    table.insert(self.knownHearthstones, id)
                end
            else
                table.insert(self.knownHearthstones, id)
            end
        end
    end
end

function Module:GetHearthstoneIcon(id)
    if not id then return 134414 end

    -- Try Item first
    local _, _, _, _, icon = ItemAPI.GetInfoInstant(id)
    if icon then return icon end

    -- Try Toy
    -- C_ToyBox.GetToyInfo returns: itemID, toyName, icon, isFavorite, hasFanfare
    local _, _, toyIcon = C_ToyBox.GetToyInfo(id)
    if toyIcon then return toyIcon end

    return 134414 -- Default Hearthstone Icon
end

function Module:BuildHearthstoneOptions()
    local opts = {}
    local ids = {}
    local known = {}

    self:UpdateKnownHearthstones()

    for _, id in ipairs(self.knownHearthstones) do
        known[id] = true
    end

    if YUI.IsDev then
        local seen = {}
        local function AddID(id)
            if id and not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end

        AddID(HEARTHSTONE_ITEM_ID)
        for _, id in ipairs(DATA.Hearthstones) do
            AddID(id)
        end
    else
        ids = self.knownHearthstones
    end

    local notCollectedText = T("teleports.tooltip.not_collected", "(未获取)")
    for _, id in ipairs(ids) do
        local name = ItemAPI.GetNameByID(id) or ("Item " .. id)
        local icon = ItemAPI.GetIcon(id)
        if YUI.IsDev and not known[id] then
            name = name .. " " .. notCollectedText
        end
        if icon then
            name = format("|T%s:14:14:0:0:64:64:4:60:4:60|t %s", icon, name)
        end
        table.insert(opts, {text = name, value = id})
    end

    return opts
end

function Module:GetRandomHearthstone()
    self:UpdateKnownHearthstones()
    if #self.knownHearthstones <= 1 then return HEARTHSTONE_ITEM_ID end

    local randomIndex = math.random(2, #self.knownHearthstones)
    return self.knownHearthstones[randomIndex]
end

function Module:PickNextHearthstone()
    if self.db.hearthstoneMode == "random" then
        local nextID = self:GetRandomHearthstone()
        self.db.nextHearthstone = nextID
        return nextID
    elseif self.db.hearthstoneMode == "fixed" and self.db.customHearthstone then
        return self.db.customHearthstone
    else
        return HEARTHSTONE_ITEM_ID
    end
end

function Module:GetCurrentHearthstone()
    local selected = self.db.hearthstoneMode == "random" and self.db.nextHearthstone or self.db.customHearthstone
    if IsHistoricalHearthstone(selected) and not (PlayerHasToy(selected) and
        C_ToyBox.IsToyUsable(selected) and ItemAPI.GetNameByID(selected)) then
        return HEARTHSTONE_ITEM_ID
    end
    if self.db.hearthstoneMode == "random" then
        if not self.db.nextHearthstone then
            self.db.nextHearthstone = self:GetRandomHearthstone()
        end
        return self.db.nextHearthstone
    elseif self.db.hearthstoneMode == "fixed" and self.db.customHearthstone then
        return self.db.customHearthstone
    else
        return HEARTHSTONE_ITEM_ID
    end
end

function Module:HasUsableWormholes()
    if YUI.IsDev then return true end
    for _, id in ipairs(DATA.Wormholes) do
        if PlayerHasToy(id) and C_ToyBox.IsToyUsable(id) then
            return true
        end
    end
    return false
end

function Module:HasUsableItems()
    if YUI.IsDev then return true end
    for _, id in ipairs(DATA.ItemTeleports) do
        if self:IsTravelItemAvailable(id) then return true end
    end
    return false
end

function Module:HasMageTeleports()
    if YUI.IsDev then return true end
    local _, classFilename = UnitClass("player")
    if classFilename ~= "MAGE" then return false end
    for _, id in ipairs(DATA.MageTeleports) do
        if SpellAPI.IsKnown(id) then return true end
    end
    return false
end

function Module:HasMagePortals()
    if YUI.IsDev then return true end
    local _, classFilename = UnitClass("player")
    if classFilename ~= "MAGE" then return false end
    for _, id in ipairs(DATA.MagePortals) do
        if SpellAPI.IsKnown(id) then return true end
    end
    return false
end

function Module:HasDungeonTeleports()
    return next(DATA.Dungeons) ~= nil
end

function Module:HasSeasonTeleports()
    if YUI.IsDev then return true end
    for _, id in ipairs(DATA.CurrentSeason) do
        local resolvedId = self:ResolveDungeonTeleportSpellID(id)
        if resolvedId and SpellAPI.IsKnown(resolvedId) then return true end
    end
    return false
end

function Module:CreateBarItem(parent)
    local fontSize = self.db.size or DEFAULT_ICON_SIZE
    local iconSize = fontSize + BAR_ICON_SIZE_OFFSET
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })

    local secure = GUI2:CreateFrame(frame)
    secure:SetAllPoints()

    secure.iconSlot, secure.icon = YBar:CreateIconSlot(secure, {
        size = iconSize,
        shape = "square",
        padding = 0,
    })
    if secure.iconSlot then
        secure.iconSlot:SetPoint("LEFT", secure, "LEFT", 0, 0)
    else
        secure.icon:SetPoint("LEFT", secure, "LEFT", 0, 0)
    end

    secure.statusText, secure.text = YBar:CreateStatusText(secure, {
        variant = "single",
        value = "",
        width = 80,
        height = 20,
        justifyH = "CENTER",
        colorKey = "color.ybar.text",
    })
    secure.text:SetFont(YBar:ResolveFontPath(self.db.font, DEFAULT_FONT), fontSize, "")
    secure.text:SetShadowColor(0, 0, 0, 1)
    secure.text:SetShadowOffset(1, -1)
    secure.text:ClearAllPoints()
    secure.text:SetPoint("LEFT", secure.iconSlot or secure.icon, "RIGHT", 5, 0)
    secure.text:SetPoint("RIGHT", secure, "RIGHT", 0, 0)
    secure.text:SetJustifyH("CENTER")

    frame.iconSlot = secure.iconSlot
    frame.icon = secure.icon
    frame.statusText = secure.statusText
    frame.text = secure.text
    frame.secure = secure

    self.frame = frame
    self.secure = secure

    YBar:CreateActionHost(secure, {
        onEnter = function(_, owner)
            if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end
            self:OnEnter(frame)
            YBar:SetThemedTextAccent(frame.text)
        end,
        onLeave = function(_, owner)
            if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end
            self:CancelTooltipTimer()
            YUI.HideGameTooltip()
            YBar:RestoreThemedTextColor(frame.text, "color.ybar.text")
        end,
    })

    if YBar and YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name) then
        self:RegisterSecureEvents()
    end



    self:UpdateBarItem(frame, parent)

    return frame
end

function Module:RefreshActionHost(frame, hsID)
    frame = frame or self.frame
    if not IsTeleportFrameReady(frame) or not frame.secure.actionHost then return end

    hsID = hsID or self:GetCurrentHearthstone()

    local actions = {
        left = {
            kind = PlayerHasToy(hsID) and "toy" or "item",
            toy = hsID,
            item = "item:" .. hsID,
            afterClick = function(_, _, owner)
                if self.db.hearthstoneMode == "random" and not SecurityAPI.InCombatLockdown() then
                    self:PickNextHearthstone()
                    self:UpdateBarItem(self.frame)
                    local tooltipOwner = GameTooltip:GetOwner()
                    if tooltipOwner == frame or tooltipOwner == frame.secure or tooltipOwner == owner then
                        self:OnEnter(frame)
                    end
                end
            end,
        },
        right = {
            kind = "custom",
            onClick = function()
                if not SecurityAPI.InCombatLockdown() then
                    self:OnClickMenu(frame)
                else
                    print("|cffff0000" .. T("teleports.message.combat_blocked", "战斗中无法打开传送菜单") .. "|r")
                end
            end,
        },
        altLeft = {
            kind = "custom",
            onClick = function()
                YUI:OpenYBarModuleSettings("Teleports")
            end,
        },
    }

    frame.secure.hasWandererLiu = false
    frame.secure.wandererLiuName = nil
    if C_PetJournal then
        local name, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(233190)
        if speciesID then
            local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
            if numOwned and numOwned > 0 then
                actions.shiftLeft = {
                    kind = "macro",
                    macrotext = "/summonpet " .. (name or "漫游者小刘"),
                }
                frame.secure.hasWandererLiu = true
                frame.secure.wandererLiuName = name or "漫游者小刘"
            end
        end
    end

    if not actions.shiftLeft then
        actions.shiftLeft = { kind = "noop" }
    end

    local ok = frame.secure.actionHost:SetActions(actions)
    if not ok then
        self.needsUpdate = true
    end
end

function Module:UpdateBarItem(frame, parent)
    if not IsTeleportFrameReady(frame) then return end

    local fontSize = self.db.size or DEFAULT_ICON_SIZE
    local iconSize = fontSize + BAR_ICON_SIZE_OFFSET
    local font = YBar:ResolveFontPath(self.db.font, DEFAULT_FONT)

    -- Update Icon
    local hsID = self:GetCurrentHearthstone()
    local iconTexture = self:GetHearthstoneIcon(hsID)

    if self.db.showIcon then
        if frame.iconSlot then
            frame.iconSlot:Show()
            frame.iconSlot:SetSize(iconSize, iconSize)
        else
            frame.icon:Show()
            frame.icon:SetSize(iconSize, iconSize)
        end
        frame.icon:SetTexture(iconTexture)

        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", 5, 0)
        frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    else
        if frame.iconSlot then
            frame.iconSlot:Hide()
        else
            frame.icon:Hide()
        end

        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    end

    -- Update Text
    local bindLocation = GetBindLocation() or "Unknown"
    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")

    frame.text:SetFont(font, fontSize, fontFlag)

    if globalDB.fontShadow then
        frame.text:SetShadowColor(0, 0, 0, 1)
        frame.text:SetShadowOffset(1, -1)
    else
        frame.text:SetShadowOffset(0, 0)
    end
    frame.text:SetText(bindLocation)
    frame.defaultText = bindLocation -- Store default text for reset

    -- Size
    local textWidth = frame.text:GetStringWidth()

    if not SecurityAPI.InCombatLockdown() then
        -- Calculate Fixed Width based on Bind Location Text
        frame:SetWidth(iconSize + 5 + textWidth)
        frame:SetHeight(iconSize + 4)

        -- Start Cooldown Monitor
        self:StartCooldownMonitor(frame, hsID)

        self:RefreshActionHost(frame, hsID)
    else
        self.needsUpdate = true
    end
end

function Module:OnClickHearthstone()
    -- Deprecated, handled by SecureButton Attributes
end

function Module:CancelTooltipTimer()
    if self.tooltipTimer then
        self.tooltipTimer:Cancel()
        self.tooltipTimer = nil
    end
end

function Module:CancelCooldownTimer()
    if self.cooldownTimer then
        self.cooldownTimer:Cancel()
        self.cooldownTimer = nil
    end
end

function Module:StartCooldownMonitor(frame, hsID)
    if not IsTeleportFrameReady(frame) then return end

    self:CancelCooldownTimer()

    local start, duration = GetSafeItemCooldownValues(hsID)

    if start and duration and start > 0 and duration > 2 then
        -- Initial Update
        self:UpdateCooldownText(frame, start, duration)
    else
        -- No Cooldown, reset text
        if frame.defaultText then
            frame.text:SetText(frame.defaultText)
            frame.text:SetTextColor(1, 1, 1) -- White
        end
    end
end

function Module:UpdateCooldownText(frame, start, duration)
    if not IsTeleportFrameReady(frame) then return end

    start, duration = GetSafeCooldownValues(start, duration)
    local now = GetSafeCurrentTime()
    if not start or not duration or not now then
        if frame.defaultText then
            frame.text:SetText(frame.defaultText)
            frame.text:SetTextColor(1, 1, 1)
        end
        self:CancelCooldownTimer()
        return
    end

    local remain = duration - (now - start)

    if remain <= 0 then
        -- Cooldown finished
        if frame.defaultText then
            frame.text:SetText(frame.defaultText)
            frame.text:SetTextColor(1, 1, 1)
        end
        self:CancelCooldownTimer()
        return
    end

    -- Format Time
    local timeText = FormatTime(remain)
    frame.text:SetText(timeText)
    frame.text:SetTextColor(1, 0, 0) -- Red for cooldown

    -- Schedule next update
    local delay = 1
    if remain > 60 then
        -- Check every 1s if remain > 60 is requested?
        -- User said: "> 60s, update every 1 minute".
        -- If we update every 1 minute, the text "2m" won't change to "1m" until 60s passed.
        -- But if remain is 65s (2m), and we wait 60s -> 5s (5s). Text jumps from 2m to 5s? No.
        -- FormatTime uses math.ceil.
        -- 61s -> 2m. 60s -> 1m.
        -- We need to update when it crosses a minute boundary.
        -- Calculate time to next boundary.
        local nextBoundary = remain % 60
        if nextBoundary == 0 then nextBoundary = 60 end
        delay = nextBoundary
        -- Add a small buffer to ensure we cross the boundary
        delay = delay + 0.1
    else
        delay = 1
    end

    self.cooldownTimer = C_Timer.NewTimer(delay, function()
        if not self._runtimeAttached or not IsTeleportFrameReady(frame) then
            self:CancelCooldownTimer()
            return
        end
        self:UpdateCooldownText(frame, start, duration)
    end)
end

function Module:OnEnter(frame)
    if not IsTeleportFrameReady(frame) then return end

    local screenHeight = UIParent:GetHeight()
    local anchorY = frame:GetBottom()
    local anchor = "ANCHOR_BOTTOM"
    local yOffset = -5

    if anchorY < screenHeight / 2 then
        anchor = "ANCHOR_TOP"
        yOffset = 5
    end

    GameTooltip:SetOwner(frame, anchor, 0, yOffset)
    GameTooltip:SetText(T("teleports.tooltip.title", "传送助手"))
    GameTooltip:AddLine(" ")

    local hsID = self:GetCurrentHearthstone()
    local name = ItemAPI.GetNameByID(hsID) or T("teleports.tooltip.unknown_hearthstone", "未知炉石")
    local icon = self:GetHearthstoneIcon(hsID)

    local start, duration = GetSafeItemCooldownValues(hsID)

    local cdText = "|cff00ff00" .. (LC["common.ready"] or "就绪") .. "|r"
    local remain = GetSafeCooldownRemaining(start, duration)
    if remain then
        cdText = string.format("|cffff0000%s|r", FormatTime(remain))
    end

    -- GameTooltip:AddDoubleLine("当前炉石", string.format("|T%s:14|t %s %s", icon, name, cdText), 1, 1, 1, 1, 1, 1)

    -- if self.db.hearthstoneMode == "random" then
    --     GameTooltip:AddLine("模式: 随机 (点击使用当前，下次随机切换)", 0.5, 0.8, 1)
    -- end

    GameTooltip:AddDoubleLine(string.format("|T%s:14|t %s", icon, name), cdText, 1, 1, 1, 1, 1, 1)

    -- Check other hearthstones
    local special = {
        {name = T("teleports.menu.dalaran_hearthstone", "Dalaran Hearthstone"), id = SPECIAL_HEARTHSTONES.Dalaran},
        {name = T("teleports.menu.garrison_hearthstone", "Garrison Hearthstone"), id = SPECIAL_HEARTHSTONES.Garrison},
    }

    for _, info in ipairs(special) do
        local sIcon = self:GetHearthstoneIcon(info.id)

        if ItemAPI.GetCount(info.id) > 0 or PlayerHasToy(info.id) then
            local s, d = GetSafeItemCooldownValues(info.id)
            local cd = "|cff00ff00" .. (LC["common.ready"] or "就绪") .. "|r"
            local rem = GetSafeCooldownRemaining(s, d)
            if rem then
                cd = string.format("|cffff0000%s|r", FormatTime(rem))
            end

            GameTooltip:AddDoubleLine(string.format("|T%s:14|t %s", sIcon, info.name), cd, 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(string.format("|T%s:14|t %s", sIcon, info.name), T("teleports.tooltip.not_collected", "(未获取)"), 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
        end
    end

    local headerColor = CreateColor(1, 0.82, 0)
    local headerHex = headerColor:GenerateHexColor()
    local white = "|cffffffff"
    local gold = "|c" .. headerHex

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("teleports.action.use", "使用 %s", name)))
    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("teleports.action.open", "打开 %s", TP_MENU_NAME)))

    if frame.hasWandererLiu then
        local liuName = YUI.F:GetGradientText(frame.wandererLiuName or "漫游者小刘", {0, 0.44, 0.87}, {0, 0.8, 1})
        GameTooltip:AddLine(format("%sShift + %s: |r%s%s|r", white, LC["common.left_click"], gold, T("teleports.action.summon", "召唤 %s", liuName)))
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
    GameTooltip:Show()

    if not self.tooltipTimer then
        self.tooltipTimer = C_Timer.NewTicker(1, function()
            if not self._runtimeAttached then
                self:CancelTooltipTimer()
                return
            end
            if GameTooltip:GetOwner() == frame then
                self:OnEnter(frame)
            else
                self:CancelTooltipTimer()
            end
        end)
    end
end

-- Menu System

local function CaptureTeleportMenuEquipState(actionHost, itemData)
    if not itemData or itemData.type ~= "item" or not ItemAPI.IsEquippable(itemData.id) then
        actionHost.wasEquipped = nil
        return
    end

    local isEquipped = ItemAPI.IsEquipped(itemData.id)
    actionHost.wasEquipped = isEquipped

    if isEquipped or SecurityAPI.InCombatLockdown() then
        return
    end

    YBar.TeleportRestore:Capture(itemData.id)
end

local function CaptureTeleportMenuCooldownState(actionHost, itemData)
    if not itemData then
        actionHost.isOnCooldown = false
        return
    end

    local start, duration = GetSafeTeleportCooldownValues(itemData)
    actionHost.isOnCooldown = start and duration and start > 0 and duration > 2 or false
end

local function BuildTeleportMenuAction(btn, itemData)
    if not itemData then return nil end
    if itemData.isLocked then return { kind = "noop" } end

    local action
    if itemData.type == "toy" then
        action = { kind = "toy", toy = itemData.id }
    elseif itemData.type == "item" then
        action = { kind = "item", item = "item:" .. itemData.id }
    elseif itemData.type == "spell" then
        action = { kind = "spell", spell = itemData.id }
    elseif itemData.type == "housing" then
        if itemData.canReturn then
            action = { kind = "returnhome" }
            if btn.icon then btn.icon:SetAtlas("dashboard-panel-homestone-teleport-out-button") end
        else
            action = { kind = "teleporthome" }
            if itemData.housingData then
                action.attributes = {
                    ["house-neighborhood-guid"] = itemData.housingData.neighborhoodGUID,
                    ["house-guid"] = itemData.housingData.houseGUID,
                    ["house-plot-id"] = itemData.housingData.plotID,
                }
            end
        end
    end

    if not action then return nil end

    action.beforeClick = function(actionHost)
        CaptureTeleportMenuEquipState(actionHost, itemData)
        CaptureTeleportMenuCooldownState(actionHost, itemData)
    end
    action.afterClick = function(actionHost)
        if actionHost.isOnCooldown then
            return
        end
        if itemData.type == "item" and ItemAPI.IsEquippable(itemData.id) and not actionHost.wasEquipped then
            return
        end
        Module:HideMenu()
    end

    return action
end

local function AttachTeleportMenuActionHost(btn, itemData)
    local host = YBar:CreateActionHost(btn, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if host then
        host:SetActions({
            left = BuildTeleportMenuAction(btn, itemData) or { kind = "noop" },
        })
    end
    return host
end

local function TooltipOverlapsMenu(frame, left, bottom, width, height)
    if not frame or not frame:IsShown() then return false end
    local x, y, w, h = frame:GetRect()
    if not x or not y then return false end
    return left < x + w + MENU_SCREEN_PADDING and left + width > x - MENU_SCREEN_PADDING and
        bottom < y + h + MENU_SCREEN_PADDING and bottom + height > y - MENU_SCREEN_PADDING
end

local function TryMenuTooltipPosition(tooltip, pane, x, top, width, height)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if width > screenWidth - 2 * MENU_SCREEN_PADDING or height > screenHeight - 2 * MENU_SCREEN_PADDING then return false end
    x = math.max(MENU_SCREEN_PADDING, math.min(screenWidth - width - MENU_SCREEN_PADDING, x))
    top = math.max(height + MENU_SCREEN_PADDING, math.min(screenHeight - MENU_SCREEN_PADDING, top))
    if TooltipOverlapsMenu(MenuFrame, x, top - height, width, height) or
        TooltipOverlapsMenu(pane, x, top - height, width, height) then return false end
    local scale = tooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, top / scale)
    return true
end

function Module:PositionMenuTooltip()
    local tooltip, owner = self.MenuTooltip, self.menuTooltipOwner
    if not tooltip or not owner or not MenuFrame or not MenuFrame:IsShown() then return false end
    local scale = tooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local width, height = tooltip:GetWidth() * scale, tooltip:GetHeight() * scale
    local left, right, bottom, top = MenuFrame:GetLeft(), MenuFrame:GetRight(), MenuFrame:GetBottom(), MenuFrame:GetTop()
    local pane = self.SubMenuFrame
    if pane and pane:IsShown() then
        left, right = math.min(left, pane:GetLeft()), math.max(right, pane:GetRight())
        bottom, top = math.min(bottom, pane:GetBottom()), math.max(top, pane:GetTop())
    end
    local cx, cy = owner:GetCenter()
    local gap = MENU_SCREEN_PADDING + 2
    if TryMenuTooltipPosition(tooltip, pane, self.subMenuOpensLeft and left - gap - width or right + gap,
        cy + height / 2, width, height) then return true end
    if TryMenuTooltipPosition(tooltip, pane, self.subMenuOpensLeft and right + gap or left - gap - width,
        cy + height / 2, width, height) then return true end
    if TryMenuTooltipPosition(tooltip, pane, cx - width / 2, top + gap + height, width, height) then return true end
    if TryMenuTooltipPosition(tooltip, pane, cx - width / 2, bottom - gap, width, height) then return true end
    -- A short tooltip can fit above or below the main menu beside a tall submenu.
    if TryMenuTooltipPosition(tooltip, pane, MenuFrame:GetLeft(), MenuFrame:GetTop() + gap + height, width, height) then return true end
    return TryMenuTooltipPosition(tooltip, pane, MenuFrame:GetLeft(), MenuFrame:GetBottom() - gap, width, height)
end

local function MenuTooltipHidden(tooltip)
    if Module.menuTooltipListening then
        tooltip:UnregisterEvent("TOOLTIP_DATA_UPDATE")
        Module.menuTooltipListening = nil
    end
    if not Module.menuTooltipUpdating then
        Module.menuTooltipOwner, Module.menuTooltipData, Module.menuTooltipCompact = nil, nil, nil
    end
end

function Module:HideMenuTooltip(owner)
    if owner and self.menuTooltipOwner ~= owner then return end
    self.menuTooltipOwner, self.menuTooltipData, self.menuTooltipCompact = nil, nil, nil
    if self.MenuTooltip then
        self.MenuTooltip:Hide()
        MenuTooltipHidden(self.MenuTooltip)
    end
end

function Module:RefreshMenuTooltipPosition()
    if self.menuTooltipUpdating or not self.menuTooltipOwner then return end
    local tooltip, item = self.MenuTooltip, self.menuTooltipData
    if not self._runtimeAttached or not self.menuTooltipOwner:IsShown() then self:HideMenuTooltip(); return end
    if self:PositionMenuTooltip() then return end
    if not self.menuTooltipCompact then
        self.menuTooltipUpdating, self.menuTooltipCompact = true, true
        tooltip:ClearLines()
        tooltip:SetText(item.text or tostring(item.id))
        local start, duration = GetSafeTeleportCooldownValues(item)
        local remaining = GetSafeCooldownRemaining(start, duration)
        if remaining and remaining > 0 then
            tooltip:AddLine(T("teleports.tooltip.cooldown_seconds", "冷却: %d秒", math.ceil(remaining)), 1, 0, 0)
        end
        tooltip:Show()
        self.menuTooltipUpdating = nil
    end
    if not self:PositionMenuTooltip() then self:HideMenuTooltip() end
end

local function MenuTooltipSizeChanged()
    Module:RefreshMenuTooltipPosition()
end

function Module:ShowMenuTooltip(owner, item)
    if not self._runtimeAttached or SecurityAPI.InCombatLockdown() then return end
    YUI.HideGameTooltip()
    if not self.MenuTooltip then
        self.MenuTooltip = GUI2:CreateFrame(UIParent, {
            type = "GameTooltip", name = "YBarTeleportTooltip", template = "GameTooltipTemplate",
        })
        self.MenuTooltip.supportsItemComparison = false
        self.MenuTooltip:SetFrameStrata("TOOLTIP")
        self.MenuTooltip:EnableMouse(false)
        self.MenuTooltip:HookScript("OnSizeChanged", MenuTooltipSizeChanged)
        self.MenuTooltip:HookScript("OnHide", MenuTooltipHidden)
    end
    local tooltip = self.MenuTooltip
    self.menuTooltipUpdating = true
    self.menuTooltipOwner, self.menuTooltipData, self.menuTooltipCompact = owner, item, nil
    tooltip:SetOwner(owner, "ANCHOR_NONE")
    if item.type == "toy" then tooltip:SetToyByItemID(item.id)
    elseif item.type == "item" then tooltip:SetItemByID(item.id)
    elseif item.type == "spell" then tooltip:SetSpellByID(item.id)
    elseif item.type == "housing" then
        tooltip:SetText(item.canReturn and (_G.HOUSING_DASHBOARD_RETURN or T("teleports.tooltip.return_home", "返回原处")) or
            (_G.HOUSING_DASHBOARD_TELEPORT_TO_PLOT or T("teleports.tooltip.teleport_home", "传送: 家宅")), 1, 1, 1)
        if not item.canReturn and C_Housing and C_Housing.GetVisitCooldownInfo then
            local info = C_Housing.GetVisitCooldownInfo()
            if info and info.isEnabled then
                local remaining = GetSafeCooldownRemaining(info.startTime, info.duration)
                if remaining then tooltip:AddLine(T("teleports.tooltip.cooldown_seconds", "冷却: %d秒", math.ceil(remaining)), 1, 0, 0) end
            end
        end
    end
    tooltip:Show()
    self.menuTooltipUpdating = nil
    if not self.menuTooltipListening then
        tooltip:RegisterEvent("TOOLTIP_DATA_UPDATE")
        self.menuTooltipListening = true
    end
    self:RefreshMenuTooltipPosition()
end

function Module:CreateMenuButton(parent, text, icon, itemData, hasSubMenu, subMenuData, style)
    -- Determine if we need Secure Template
    -- If it has a submenu, it's just a UI button (Insecure)
    -- If it's a leaf node (item/toy/spell), it needs Secure Template

    local btn = GUI2:CreateButtonFrame(parent)

    -- Default Style: List
    local width, height = 140, 24
    local iconSize = 32
    local fontSize = 11
    style = style or "list"

    if style == "grid_icon" or style == "grid_icon_overlay" then
        width, height = SM_ICON_SIZE, SM_ICON_SIZE
        iconSize = SM_ICON_SIZE
        if style == "grid_icon_overlay" then
            fontSize = 10
        end
    elseif style == "grid_text_bottom" then
        width, height = SM_ITEM_WIDTH, SM_ITEM_HEIGHT -- 32 icon + text
        iconSize = SM_ICON_SIZE
        fontSize = SM_FONT_SIZE
    elseif style == "list_large" then -- Categories
        width, height = 152, 32
        iconSize = 32
        local locale = YUI.Locale and YUI.Locale.Current and YUI.Locale:Current()
        fontSize = (locale == "zhCN" or locale == "zhTW") and 16 or 14
    end

    btn:SetSize(width, height)

    -- Style
    btn.iconSlot, btn.icon = YBar:CreateIconSlot(btn, {
        size = iconSize,
        icon = icon,
        variant = (style == "grid_icon" or style == "grid_icon_overlay") and "bare" or nil,
        shape = (style == "grid_icon" or style == "grid_icon_overlay") and "rounded" or "square",
        padding = 0,
    })
    local iconFrame = btn.iconSlot or btn.icon

    if style == "list" or style == "list_large" then
        iconFrame:SetPoint("LEFT", 4, 0)
    elseif style == "grid_icon" or style == "grid_icon_overlay" then
        iconFrame:SetAllPoints() -- Fill
    elseif style == "grid_text_bottom" then
        iconFrame:SetPoint("TOP", 0, -2)
    end

    if icon then
        if btn.iconSlot then
            YBar:SetIconSlotTexture(btn.iconSlot, icon)
        else
            btn.icon:SetTexture(icon)
        end
        iconFrame:Show()

        if not btn.iconSlot then
            -- Application IconSlot fallback still uses GUI2 primitives.
            local iconBg = GUI2:CreateFrame(btn, { template = "BackdropTemplate" })
            iconBg:SetAllPoints(btn.icon)
            iconBg:SetFrameLevel(btn:GetFrameLevel())
            GUI2:CreateBorder(iconBg)
            btn.iconBg = iconBg
        end

    else
        iconFrame:Hide()
    end

    -- Text
    btn.textFrame = GUI2:CreateFrame(btn)
    btn.textFrame:SetHeight(height)
    btn.statusText, btn.text = YBar:CreateStatusText(btn.textFrame, {
        value = text,
        single = true,
        justifyH = (style == "grid_text_bottom" or style == "grid_icon_overlay") and "CENTER" or "LEFT",
        colorKey = "color.ybar.text",
    })
    btn.text:SetFont(STANDARD_TEXT_FONT, fontSize, "")
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetShadowOffset(1, -1)

    if style == "list" or style == "list_large" then
        btn.textFrame:SetPoint("LEFT", iconFrame, "RIGHT", 5, 0)
        btn.textFrame:SetPoint("RIGHT", hasSubMenu and -18 or -2, 0)
        btn.text:SetJustifyH("LEFT")
        btn.text:SetText(text)
    elseif style == "grid_icon" then
        -- No text for grid_icon usually, or overlay count?
        -- User said: "纯图标+冷却文本" -> Cooldown is handled by CooldownFrame.
        -- Maybe we don't need text label here.
        btn.textFrame:Hide()
    elseif style == "grid_text_bottom" then
        btn.textFrame:SetHeight(fontSize + 2)
        btn.textFrame:SetPoint("TOP", iconFrame, "BOTTOM", 0, -1)
        btn.textFrame:SetPoint("LEFT", 2, 0)
        btn.textFrame:SetPoint("RIGHT", -2, 0)
        btn.text:SetJustifyH("CENTER")
        -- Use Mapping or shorten text?
        -- Text is passed in, caller should handle mapping?
        -- Let's handle mapping here if passed, or caller does it.
        -- Caller is better.
        btn.text:SetText(text)
    elseif style == "grid_icon_overlay" then
        btn.textFrame:SetHeight(fontSize + 4)
        btn.textFrame:SetPoint("BOTTOMLEFT", 1, 1)
        btn.textFrame:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.text:SetJustifyH("CENTER")
        btn.text:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        btn.text:SetText(text)
    end

    -- Cooldown Frame
    if itemData then
        -- CooldownFrameTemplate must stay on native CreateFrame.
        btn.cooldown = CreateFrame("Cooldown", "$parentCooldown", btn, "CooldownFrameTemplate")
        btn.cooldown:SetAllPoints(iconFrame)
        btn.cooldown:SetDrawEdge(false)
        btn.cooldown:SetSwipeTexture("Interface\\Cooldown\\star4") -- Optional: Use a cleaner swipe if desired
        btn.cooldown:SetHideCountdownNumbers(false) -- Ensure standard numbers show? Or hide and use custom text?
        -- User requested: "冷却文本缩小到合适的尺寸"
        -- CooldownFrame uses standard fonts. We can try to modify regions if we want custom size,
        -- but usually 'SetHideCountdownNumbers(true)' and adding our own FontString is safer for control.
        -- However, CooldownFrameTemplate is efficient.
        -- Let's check if we can scale the text.
        -- CooldownFrame_SetTextScale exists in newer APIs? No.
        -- We can iterate regions.
        for _, region in ipairs({btn.cooldown:GetRegions()}) do
            if region:GetObjectType() == "FontString" then
                region:SetScale(0.7) -- Scale down text
            end
        end

        if btn.iconSlot and btn.iconSlot.SetIconAppearance then
            btn.iconSlot.cooldown = btn.cooldown
            if style == "grid_icon" or style == "grid_icon_overlay" then
                btn.iconSlot.gui2HoverBorderColor = "color.border.focus"
            end
            btn.iconSlot:SetIconAppearance({
                size = iconSize,
                shape = btn.iconSlot.gui2Shape,
                border = (style == "grid_icon" or style == "grid_icon_overlay") and "medium" or "thin",
                zoom = btn.iconSlot.gui2IconZoom,
            })
        end

        -- Update Cooldown immediately
        UpdateMenuButtonCooldown(btn, itemData)

        -- Register Event for updates?
        -- Or just update on Show?
        -- Buttons are created/shown dynamically.
        btn:SetScript("OnShow", function(self)
             UpdateMenuButtonCooldown(self, self._ybarMenuItemData)
        end)
    end

    if hasSubMenu then
        btn.arrow = YBar:CreateThemedTexture(btn, {
            layer = "ARTWORK",
            texture = "Interface\\ChatFrame\\ChatFrameExpandArrow",
            colorKey = "color.ybar.teleports.arrow",
            fallback = { 1, 1, 1, 1 },
            colorMode = "vertex",
        })
        btn.arrow:SetSize(10, 10)
        btn.arrow:SetPoint("RIGHT", -5, 0)

        -- Insecure Click for Submenu
        btn:SetScript("OnClick", function(button)
            Module:StopSubMenuSwitch()
            Module:ShowSubMenu(button, button._ybarMenuSubMenuData)
        end)
    end

    if hasSubMenu then
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end

    btn:SetScript("OnEnter", function(self)
        Module:StopHideTimer()
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "hover")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.accent")
        end

        local currentItemData = self._ybarMenuItemData
        if self._ybarMenuHasSubMenu and self._ybarMenuSubMenuData then
            Module:RequestSubMenu(self, self._ybarMenuSubMenuData)
        else
            -- Close SubMenu if hovering a button that doesn't have one (e.g. Top Row Hearthstones)

            -- Show Tooltip
            if currentItemData then
                -- Hide SubMenu if item is level 1
                if currentItemData.isLv1Item then
                    Module:RequestSubMenu(self, nil)
                end

                Module:ShowMenuTooltip(self, currentItemData)
            end
        end
    end)

    btn:SetScript("OnLeave", function(self)
        Module:StartHideTimer()
        Module:HideMenuTooltip(self)
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "normal")
        elseif self.iconBg then
            GUI2:SetBorderColor(self.iconBg, "color.border.default")
        end
        YUI.HideGameTooltip()

    end)
    btn:HookScript("OnHide", function(self) Module:HideMenuTooltip(self) end)

    if style == "grid_text_bottom" then
        btn:EnableMouseWheel(true)
        btn:SetScript("OnMouseWheel", function(_, delta) Module:ScrollSubMenuBy(delta) end)
    end

    btn._ybarMenuItemData = itemData
    btn._ybarMenuHasSubMenu = hasSubMenu == true
    btn._ybarMenuSubMenuData = subMenuData
    if not hasSubMenu and itemData then
        btn.actionHost = AttachTeleportMenuActionHost(btn, itemData)
    end

    return btn
end

function Module:UpdateMenuButton(btn, text, icon, itemData, hasSubMenu, subMenuData)
    if not btn then return end

    btn._ybarMenuItemData = itemData
    btn._ybarMenuHasSubMenu = hasSubMenu == true
    btn._ybarMenuSubMenuData = subMenuData

    if btn.text then
        btn.text:SetText(text or "")
    end
    if btn.iconSlot then
        YBar:SetIconSlotTexture(btn.iconSlot, icon)
        btn.iconSlot:SetShown(icon ~= nil)
    elseif btn.icon then
        btn.icon:SetTexture(icon)
        btn.icon:SetShown(icon ~= nil)
    end
    if btn.cooldown then
        UpdateMenuButtonCooldown(btn, itemData)
    end
    if btn.actionHost then
        btn.actionHost:SetActions({
            left = BuildTeleportMenuAction(btn, itemData) or { kind = "noop" },
        })
    end
end

function Module:AcquireMenuButton(frame, poolName, index, text, icon, itemData, hasSubMenu, subMenuData, style)
    local pool = frame[poolName]
    if not pool then
        pool = {}
        frame[poolName] = pool
    end

    local btn = pool[index]
    if not btn then
        btn = self:CreateMenuButton(frame, text, icon, itemData, hasSubMenu, subMenuData, style)
        pool[index] = btn
    else
        self:UpdateMenuButton(btn, text, icon, itemData, hasSubMenu, subMenuData)
    end
    return btn
end

local function HideMenuButtonPool(pool)
    if not pool then return end
    for _, btn in ipairs(pool) do
        btn:Hide()
    end
end


local ITEM_GROUPS = { "toy", "equipment", "bag" }
local ITEM_GROUP_LABELS = {
    toy = "teleports.menu.items_toys",
    equipment = "teleports.menu.items_equipment",
    bag = "teleports.menu.items_bag",
}

local function GetMenuCursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function PointerInside(frame, x, y, padding)
    if not frame or not frame:IsShown() then return false end
    local left, bottom, width, height = frame:GetRect()
    if not left or not bottom then return false end
    return x >= left - padding and x <= left + width + padding and
        y >= bottom - padding and y <= bottom + height + padding
end

function Module:IsPointerInMenu(x, y)
    return PointerInside(MenuFrame, x, y, MENU_TOLERANCE) or
        PointerInside(self.SubMenuFrame, x, y, MENU_TOLERANCE) or
        PointerInside(self.menuOpenAnchor, x, y, MENU_TOLERANCE)
end

function Module:StopSubMenuSwitch()
    if self.subMenuSwitchTimer then self.subMenuSwitchTimer:Cancel() end
    self.subMenuSwitchTimer = nil
    self.pendingMenuAnchor = nil
end

function Module:IsHeadingToSubMenu(x, y)
    local pane = self.SubMenuFrame
    local ox, oy = self.menuAimX, self.menuAimY
    if not pane or not pane:IsShown() or not ox or not oy then return false end
    local edge = self.subMenuOpensLeft and pane:GetRight() or pane:GetLeft()
    if not edge or math.abs(edge - x) >= math.abs(edge - ox) then return false end
    local progress = (x - ox) / (edge - ox)
    if progress < 0 or progress > 1 then return false end
    local low = oy + (pane:GetBottom() - MENU_TOLERANCE - oy) * progress
    local high = oy + (pane:GetTop() + MENU_TOLERANCE - oy) * progress
    return y >= low and y <= high
end

function Module:RequestSubMenu(anchor, category)
    if not self._runtimeAttached or SecurityAPI.InCombatLockdown() then return end
    self:StopHideTimer()
    if self.activeMenuCategory == category and self.SubMenuFrame and self.SubMenuFrame:IsShown() then
        self:StopSubMenuSwitch()
        return
    end
    self:StopSubMenuSwitch()
    if not self.SubMenuFrame or not self.SubMenuFrame:IsShown() then
        if category then self:ShowSubMenu(anchor, category) end
        return
    end
    local x, y = GetMenuCursor()
    local delay = self:IsHeadingToSubMenu(x, y) and MENU_AIM_DELAY or MENU_SWITCH_DELAY
    self.pendingMenuAnchor = anchor
    self.subMenuSwitchTimer = C_Timer.NewTimer(delay, function()
        self.subMenuSwitchTimer = nil
        self.pendingMenuAnchor = nil
        if not self._runtimeAttached or SecurityAPI.InCombatLockdown() then return end
        local px, py = GetMenuCursor()
        if not PointerInside(anchor, px, py, 0) then return end
        if category then self:ShowSubMenu(anchor, category) else self:HideSubMenu() end
    end)
end

function Module:StartHideTimer()
    if self.hideTimer or not MenuFrame or not MenuFrame:IsShown() then return end
    self.hideTimer = C_Timer.NewTimer(MENU_CLOSE_DELAY, function()
        self.hideTimer = nil
        if SecurityAPI.InCombatLockdown() then return end
        local x, y = GetMenuCursor()
        if not self._runtimeAttached or not self:IsPointerInMenu(x, y) then
            self:HideMenu()
        end
    end)
end

function Module:StopHideTimer()
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = nil
end

function Module:UpdateMenuPointer(elapsed)
    if not self._runtimeAttached or not MenuFrame:IsShown() then return end
    if SecurityAPI.InCombatLockdown() then return end
    self.menuPointerElapsed = (self.menuPointerElapsed or 0) + elapsed
    if self.menuPointerElapsed < 0.03 then return end
    self.menuPointerElapsed = 0
    local x, y = GetMenuCursor()
    if PointerInside(self.activeMenuAnchor, x, y, 0) then
        self.menuAimX, self.menuAimY = x, y
    end
    if PointerInside(self.SubMenuFrame, x, y, 0) then self:StopSubMenuSwitch() end
    if self:IsPointerInMenu(x, y) then
        if not self.pendingMenuAnchor or not PointerInside(self.pendingMenuAnchor, x, y, 0) then
            self:StopSubMenuSwitch()
        end
        self:StopHideTimer()
    else
        self:StopSubMenuSwitch()
        self:StartHideTimer()
    end
end

local function TrackTeleportMenuPointer(_, elapsed)
    Module:UpdateMenuPointer(elapsed)
end

function Module:OnClickMenu(anchor)
    if not self._runtimeAttached then return end
    if SecurityAPI.InCombatLockdown() then return end

    YUI.HideGameTooltip()

    if MenuFrame and MenuFrame:IsShown() then
        self:HideMenu()
        return
    end

    if not MenuFrame then
        MenuFrame = GUI2:CreateFrame(UIParent, { name = "YBarTeleportMenu", template = "SecureHandlerStateTemplate,BackdropTemplate" })
        MenuFrame:SetSize(150, 200) -- dynamic
        MenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        MenuFrame:SetClampedToScreen(true)
        GUI2:CreateBackdrop(MenuFrame, {
            surface = "color.surface.popup",
            border = "color.popup.border",
            nativeFrameBorder = true,
            nativeFrameBorderStyle = "tooltip",
        })


        MenuFrame:EnableMouse(true)
        MenuFrame:SetHitRectInsets(-MENU_TOLERANCE, -MENU_TOLERANCE, -MENU_TOLERANCE, -MENU_TOLERANCE)
        MenuFrame:SetAttribute("_onstate-combat", "if newstate == 'hide' then self:Hide() end")
        MenuFrame:SetScript("OnEnter", function() self:StopHideTimer() end)
        MenuFrame:SetScript("OnLeave", function() self:StartHideTimer() end)
        MenuFrame:SetScript("OnHide", function(frame)
            self:HideMenuTooltip()
            frame:SetScript("OnUpdate", nil)
            self:StopHideTimer()
            self:StopSubMenuSwitch()
            self.activeMenuCategory, self.activeMenuAnchor = nil, nil
            self.menuOpenAnchor = nil
            self.menuAimX, self.menuAimY = nil, nil
            self.menuPointerElapsed = nil
            YUI.HideGameTooltip()
        end)
    end
    if not self.menuCombatDriver then
        RegisterStateDriver(MenuFrame, "combat", "[combat] hide; idle")
        self.menuCombatDriver = true
    end

    self:HideSubMenu()
    self:EnsureHousingData()

    -- Populate Main Menu
    self:PopulateMainMenu(MenuFrame)
    self.menuOpenAnchor = anchor

    MenuFrame:ClearAllPoints()

    -- Smart Positioning (Up/Down)
    local screenHeight = UIParent:GetHeight()
    local anchorY = anchor:GetBottom()

    if anchorY > screenHeight / 2 then
        -- Top half: Open Downwards
        MenuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    else
        -- Bottom half: Open Upwards
        MenuFrame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
    end

    MenuFrame:Show()
    MenuFrame:SetScript("OnUpdate", TrackTeleportMenuPointer)
end

function Module:PopulateMainMenu(frame)
    if SecurityAPI.InCombatLockdown() then
        self.needsMenuHide = true
        return
    end

    HideMenuButtonPool(frame.topButtons)
    HideMenuButtonPool(frame.categoryButtons)
    HideMenuButtonPool(frame.seasonButtons)
    if frame.seasonHeader then frame.seasonHeader:Hide() end

    local hsItems = {}
    local catItems = {}

    -- Get Known Class Spells
    local _, classFilename = UnitClass("player")
    local classSpells = DATA.ClassSpells[classFilename] or {}
    local knownClassSpells = {}

    -- Support priority list (table) or single spell (number)
    for _, spellInfo in ipairs(classSpells) do
        local found = false
        if type(spellInfo) == "table" then
            -- Priority List: Check each spell, use first known
            for _, id in ipairs(spellInfo) do
                if SpellAPI.IsKnown(id) then
                    table.insert(knownClassSpells, id)
                    found = true
                    break
                end
            end
        else
            -- Single Spell
            if SpellAPI.IsKnown(spellInfo) then
                local resolved = SpellAPI.GetOverrideSpellID and SpellAPI.GetOverrideSpellID(spellInfo) or spellInfo
                table.insert(knownClassSpells, resolved or spellInfo)
            end
        end
    end

    -- 1. Direct Hearthstones (Top Row)

    -- Slot 1: Class Spell 1 OR Main Hearthstone
    if knownClassSpells[1] then
        local id = knownClassSpells[1]
        local name = SpellAPI.GetName(id)
        local icon = SpellAPI.GetTexture(id)

        -- Apply Mapping
        name = GetNameMapping(id) or name

        table.insert(hsItems, {
            text = name,
            icon = icon,
            type = "spell",
            id = id,
            announceKind = MAGE_PORTAL_IDS[id] and ANNOUNCE_KIND_PORTAL or nil,
            announceName = MAGE_PORTAL_IDS[id] and name or nil,
            isLv1Item = true
        })
    else
        local hsID = self:GetCurrentHearthstone()
        local hsName = ItemAPI.GetNameByID(hsID) or T("teleports.tooltip.unknown_hearthstone", "未知炉石")
        table.insert(hsItems, {
            text = hsName,
            icon = self:GetHearthstoneIcon(hsID),
            type = PlayerHasToy(hsID) and "toy" or "item",
            id = hsID,
            isLv1Item = true
        })
    end

    -- Slot 2: Class Spell 2 OR Dalaran Hearthstone
    if knownClassSpells[2] then
        local id = knownClassSpells[2]
        local name = SpellAPI.GetName(id)
        local icon = SpellAPI.GetTexture(id)
        name = GetNameMapping(id) or name

        table.insert(hsItems, {
            text = name,
            icon = icon,
            type = "spell",
            id = id,
            announceKind = MAGE_PORTAL_IDS[id] and ANNOUNCE_KIND_PORTAL or nil,
            announceName = MAGE_PORTAL_IDS[id] and name or nil,
            isLv1Item = true
        })
    elseif ItemAPI.GetCount(SPECIAL_HEARTHSTONES.Dalaran) > 0 or PlayerHasToy(SPECIAL_HEARTHSTONES.Dalaran) then
        table.insert(hsItems, {
            text = T("teleports.menu.dalaran_hearthstone", "Dalaran Hearthstone"),
            icon = self:GetHearthstoneIcon(SPECIAL_HEARTHSTONES.Dalaran),
            type = "toy",
            id = SPECIAL_HEARTHSTONES.Dalaran,
            isLv1Item = true
        })
    end

    -- Slot 3: Class Spell 3 OR Arcane Sanctuary OR Garrison Hearthstone
    if knownClassSpells[3] then
        local id = knownClassSpells[3]
        local name = SpellAPI.GetName(id)
        local icon = SpellAPI.GetTexture(id)
        name = GetNameMapping(id) or name

        table.insert(hsItems, {
            text = name,
            icon = icon,
            type = "spell",
            id = id,
            announceKind = MAGE_PORTAL_IDS[id] and ANNOUNCE_KIND_PORTAL or nil,
            announceName = MAGE_PORTAL_IDS[id] and name or nil,
            isLv1Item = true
        })
    else
        -- Check Arcane Sanctuary (253629)
        local ARCANE_ID = 253629
        local GARRISON_ID = SPECIAL_HEARTHSTONES.Garrison
        local hasArcane = ItemAPI.GetCount(ARCANE_ID) > 0 or PlayerHasToy(ARCANE_ID)

        if hasArcane then
             table.insert(hsItems, {
                text = T("teleports.menu.arcane_society", "Arcane Society"),
                icon = self:GetHearthstoneIcon(ARCANE_ID),
                type = PlayerHasToy(ARCANE_ID) and "toy" or "item",
                id = ARCANE_ID,
                isLv1Item = true
            })
        elseif ItemAPI.GetCount(GARRISON_ID) > 0 or PlayerHasToy(GARRISON_ID) then
            table.insert(hsItems, {
                text = T("teleports.menu.garrison_hearthstone", "Garrison Hearthstone"),
                icon = self:GetHearthstoneIcon(GARRISON_ID),
                type = PlayerHasToy(GARRISON_ID) and "toy" or "item",
                id = GARRISON_ID,
                isLv1Item = true
            })
        end
    end

    -- Housing / Homestead
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        local houses = self.housingDataReady and self.housingData or nil

        if houses and #houses > 0 then
            local housingInfo = houses[1]
            local faction = UnitFactionGroup("player")
            if #houses > 1 and faction == "Horde" then
                housingInfo = houses[2]
            end

            if housingInfo then
                local canReturn = C_HousingNeighborhood and C_HousingNeighborhood.CanReturnAfterVisitingHouse and C_HousingNeighborhood.CanReturnAfterVisitingHouse()
                local icon = SpellAPI.GetTexture(1263273) or 134414

                table.insert(hsItems, {
                    text = T("teleports.menu.housing", "Housing"),
                    icon = icon,
                    type = "housing",
                    id = 1263273, -- Using Spell ID for icon/reference
                    housingData = housingInfo,
                    canReturn = canReturn,
                    isLv1Item = true
                })
            end
        end
    end

    -- Racial shortcuts use the official spell names and icons.
    for _, id in ipairs(DATA.RacialSpells) do
        if SpellAPI.IsKnownOrInSpellBook and SpellAPI.IsKnownOrInSpellBook(id) then
            local name = SpellAPI.GetName(id)
            local icon = SpellAPI.GetTexture(id)
            if name and icon then
                table.insert(hsItems, {
                    text = name,
                    icon = icon,
                    type = "spell",
                    id = id,
                    isLv1Item = true,
                })
            end
        end
    end

    -- 2. Categories (List)
    local faction = UnitFactionGroup("player")
    local portalIcon = (faction == "Alliance") and 135748 or 135744

    local categories = {}

    if self:HasUsableWormholes() then
        table.insert(categories, { text = T("teleports.menu.engineering_short", "Wormholes"), subMenu = "Wormholes", icon = 4620673 })
    end

    if self:HasUsableItems() then
        table.insert(categories, { text = T("teleports.menu.items_short", "Items"), subMenu = "Items", icon = 134943 })
    end

    if self:HasMageTeleports() then
        table.insert(categories, { text = T("teleports.menu.mage_teleports_short", "Teleports"), subMenu = "MageTeleports", icon = 237509 })
    end

    if self:HasMagePortals() then
        table.insert(categories, { text = T("teleports.menu.mage_portals_short", "Portals"), subMenu = "MagePortals", icon = portalIcon })
    end

    if self:HasDungeonTeleports() then
        table.insert(categories, { text = T("teleports.menu.hero_path", "Dungeons"), subMenu = "Dungeons", icon = 2011139 })
    end

    if self.db.seasonOnMainMenu == false then
        table.insert(categories, { text = T("teleports.menu.current_season", "Season"), subMenu = "CurrentSeason", icon = 5927657 })
    end

    for _, cat in ipairs(categories) do
        table.insert(catItems, cat)
    end

    -- Create Buttons
    local y = -5

    -- Top shortcuts: fixed four columns, additional entries wrap automatically.
    for i, item in ipairs(hsItems) do
        local btn = self:AcquireMenuButton(
            frame,
            "topButtons",
            i,
            item.text,
            item.icon,
            item,
            false,
            nil,
            "grid_icon"
        )

        btn:ClearAllPoints()
        local column = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        btn:SetPoint("TOPLEFT", 9 + column * 34, y - row * 36)
        btn:Show()
    end

    local topRows = math.max(1, math.ceil(#hsItems / 4))
    y = y - topRows * 36

    -- Rows 2+: Categories
    for i, item in ipairs(catItems) do
        local btn = self:AcquireMenuButton(
            frame,
            "categoryButtons",
            i,
            item.text,
            item.icon,
            item,
            true,
            item.subMenu,
            "list_large"
        )

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 5, y)
        btn:Show()

        y = y - 34 -- 32 + 2 padding
    end

    if self.db.seasonOnMainMenu ~= false then
        if not frame.seasonHeader then
            frame.seasonHeader = GUI2:CreateFrame(frame)
            frame.seasonHeader:SetHeight(18)
            frame.seasonHeaderStatus, frame.seasonHeaderText = YBar:CreateStatusText(frame.seasonHeader, {
                value = T("teleports.menu.current_season", "Season"),
                single = true,
                justifyH = "CENTER",
                colorKey = "color.ybar.dynamic",
            })
        end
        frame.seasonHeader:ClearAllPoints()
        frame.seasonHeader:SetPoint("TOPLEFT", 5, y)
        frame.seasonHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, y)
        frame.seasonHeader:Show()
        y = y - 20

        for i, baseId in ipairs(DATA.CurrentSeason) do
            local resolvedId = self:ResolveDungeonTeleportSpellID(baseId)
            local name = SpellAPI.GetName(resolvedId)
            local icon = SpellAPI.GetTexture(resolvedId)
            local text = GetNameMapping(baseId) or GetNameMapping(name) or name or "?"
            local item = {
                text = text,
                icon = icon,
                type = "spell",
                id = resolvedId,
                mapKey = baseId,
                announceNameKey = baseId,
                announceKind = ANNOUNCE_KIND_DUNGEON,
                isLv1Item = true,
            }
            local btn = self:AcquireMenuButton(
                frame,
                "seasonButtons",
                i,
                text,
                icon,
                item,
                false,
                nil,
                "grid_icon_overlay"
            )
            local known = SpellAPI.IsKnown(resolvedId)
            btn.icon:SetDesaturated(not known)
            if btn.statusText then
                YBar:SetStatusTextColor(
                    btn.statusText,
                    "color.ybar.dynamic",
                    known and { 1.0, 0.5, 0.0, 1 } or { 0.5, 0.5, 0.5, 1 }
                )
            end
            btn:ClearAllPoints()
            local column = (i - 1) % 4
            local row = math.floor((i - 1) / 4)
            btn:SetPoint("TOPLEFT", 9 + column * 34, y - row * 34)
            btn:Show()
        end
        y = y - math.ceil(#DATA.CurrentSeason / 4) * 34
    end

    frame:SetHeight(math.abs(y) + 5)
    frame:SetWidth(162)
end


function Module:IsTravelItemAvailable(id)
    local usage = GetItemUsage(id)
    if usage == nil or usage == ITEM_USAGE_NONE then return false end
    if usage == ITEM_USAGE_TOY then
        return PlayerHasToy(id) and C_ToyBox.IsToyUsable(id)
    end
    return ItemAPI.GetCount(id) > 0 and (usage == ITEM_USAGE_EQUIPMENT or ItemAPI.IsUsable(id))
end

function Module:GetItemGroupIcon(group)
    local ids = DATA.ItemGroups[group]
    local id = ids[1]
    for _, candidate in ipairs(ids) do
        if self:IsTravelItemAvailable(candidate) then id = candidate; break end
    end
    local icon = id and ItemAPI.GetIcon(id)
    if id and GetItemUsage(id) == ITEM_USAGE_TOY then
        local _, _, toyIcon = C_ToyBox.GetToyInfo(id)
        icon = toyIcon or icon
    end
    return icon or 134414
end

function Module:GetItemGroupCount(group)
    local count = 0
    for _, id in ipairs(DATA.ItemGroups[group]) do
        if YUI.IsDev then
            count = count + 1
        elseif self:IsTravelItemAvailable(id) then
            local name = ItemAPI.GetNameByID(id)
            if GetItemUsage(id) == ITEM_USAGE_TOY then
                local _, toyName = C_ToyBox.GetToyInfo(id)
                name = toyName or name
            end
            if name then count = count + 1 end
        end
    end
    return count
end

function Module:BuildSubMenuItems(category, group)
    local items = {}
    local function AddItem(item, force)
        local known = item.type == "spell" and SpellAPI.IsKnown(item.id) or
            (item.type ~= "spell" and self:IsTravelItemAvailable(item.id))
        if YUI.IsDev or force or known then items[#items + 1] = item end
    end
    if category == "Wormholes" or category == "Items" then
        local ids = category == "Wormholes" and DATA.Wormholes or DATA.ItemGroups[group or "toy"]
        for _, id in ipairs(ids) do
            if YUI.IsDev or self:IsTravelItemAvailable(id) then
                local usage = GetItemUsage(id)
                local name, icon = ItemAPI.GetNameByID(id), ItemAPI.GetIcon(id)
                if usage == ITEM_USAGE_TOY then
                    local _, toyName, toyIcon = C_ToyBox.GetToyInfo(id)
                    name, icon = toyName or name, toyIcon or icon
                end
                if name or YUI.IsDev then
                    items[#items + 1] = { text = name or tostring(id), icon = icon or 134414,
                        type = usage == ITEM_USAGE_TOY and "toy" or "item", id = id }
                end
            end
        end
    elseif category == "MageTeleports" or category == "MagePortals" then
        for _, id in ipairs(DATA[category]) do
            AddItem({ text = SpellAPI.GetName(id), icon = SpellAPI.GetTexture(id), type = "spell", id = id,
                announceKind = category == "MagePortals" and ANNOUNCE_KIND_PORTAL or nil })
        end
    elseif category == "CurrentSeason" then
        for _, id in ipairs(DATA.CurrentSeason) do
            local resolved = self:ResolveDungeonTeleportSpellID(id)
            AddItem({ text = SpellAPI.GetName(resolved), icon = SpellAPI.GetTexture(resolved), type = "spell",
                id = resolved, mapKey = id, announceNameKey = id, announceKind = ANNOUNCE_KIND_DUNGEON }, true)
        end
    elseif category == "Dungeons" then
        for _, exp in ipairs(DATA.ExpansionOrder) do
            local headerIndex = #items + 1
            items[headerIndex] = { text = GetNameMapping(exp) or exp, isHeader = true }
            for _, id in ipairs(DATA.Dungeons[exp] or {}) do
                local resolved = self:ResolveDungeonTeleportSpellID(id)
                AddItem({ text = SpellAPI.GetName(resolved), icon = SpellAPI.GetTexture(resolved), type = "spell",
                    id = resolved, mapKey = id, announceNameKey = id, announceKind = ANNOUNCE_KIND_DUNGEON,
                    isLocked = not SpellAPI.IsKnown(resolved) }, true)
            end
            if #items == headerIndex then items[headerIndex] = nil end
        end
    end
    return items
end

function Module:ScrollSubMenu(value)
    if SecurityAPI.InCombatLockdown() then return end
    local pane = self.SubMenuFrame
    if not pane or not pane:IsShown() then return end
    value = math.max(0, math.min(pane.scrollMax or 0, value))
    if value == pane.scroll:GetVerticalScroll() then return end
    pane.scroll:SetVerticalScroll(value)
    pane.scrollBar:SetScrollState(value + 1, pane.contentHeight, pane.viewportHeight, true)
    self:StopHideTimer()
    self:StopSubMenuSwitch()
    self:HideMenuTooltip()
    YUI.HideGameTooltip()
end

function Module:ScrollSubMenuBy(delta)
    local pane = self.SubMenuFrame
    if pane and pane.scroll then
        self:ScrollSubMenu(pane.scroll:GetVerticalScroll() - delta * (SM_ITEM_HEIGHT + SM_PADDING_Y))
    end
end

function Module:EnsureSubMenu()
    if self.SubMenuFrame then return self.SubMenuFrame end
    local pane = GUI2:CreateFrame(MenuFrame, { name = "YBarTeleportSubMenu", template = "BackdropTemplate" })
    self.SubMenuFrame = pane
    pane:SetFrameStrata("FULLSCREEN_DIALOG")
    pane:SetFrameLevel(MenuFrame:GetFrameLevel() + 5)
    pane:EnableMouse(true)
    pane:SetHitRectInsets(-MENU_TOLERANCE, -MENU_TOLERANCE, -MENU_TOLERANCE, -MENU_TOLERANCE)
    GUI2:CreateBackdrop(pane, {
        surface = "color.surface.popup", border = "color.popup.border",
        nativeFrameBorder = true, nativeFrameBorderStyle = "tooltip",
    })
    pane:SetScript("OnEnter", function() self:StopHideTimer(); self:StopSubMenuSwitch() end)
    pane:SetScript("OnLeave", function() self:StartHideTimer() end)
    pane.scroll = GUI2:CreateScrollFrame(pane, { template = false, child = false })
    pane.scroll:SetClipsChildren(true)
    pane.emptyText = GUI2:CreateText(pane.scroll, {
        text = T("teleports.menu.no_items", "No usable items"), size = 11, color = "color.text.muted",
    })
    pane.emptyText:SetPoint("CENTER", pane.scroll, "CENTER")
    pane.emptyText:Hide()
    pane.content = GUI2:CreateFrame(pane.scroll)
    pane.scroll:SetScrollChild(pane.content)
    pane.scrollBar = GUI2:CreateVirtualScrollBar(pane, {
        width = 8,
        onValueChanged = function(value) self:ScrollSubMenu(value - 1) end,
    })
    local function Wheel(_, delta) self:ScrollSubMenuBy(delta) end
    for _, frame in ipairs({ pane, pane.scroll, pane.scrollBar }) do
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", Wheel)
    end
    pane.tabs = {}
    for i, group in ipairs(ITEM_GROUPS) do
        local tab = GUI2:CreateButtonFrame(pane)
        tab:SetSize(82, 22)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * 84, -6)
        tab.iconSlot = GUI2:CreateIconSlot(tab, {
            icon = 134414, size = SM_TAB_ICON_SIZE, variant = "bare", shape = "circle",
            border = "none", zoom = 0.08, animate = false,
        })
        tab.iconSlot:EnableMouse(false)
        local silhouette = GUI2:GetIconAppearancePreset("circle").mask
        tab.iconOutline = GUI2:CreateIcon(tab.iconSlot, { icon = silhouette, crop = false, layer = "BACKGROUND", subLevel = 1 })
        tab.iconShadow = GUI2:CreateIcon(tab.iconSlot, { icon = silhouette, crop = false, layer = "BACKGROUND", subLevel = 0 })
        tab.iconOutline:SetVertexColor(0.04, 0.03, 0.02, 0.95)
        tab.iconShadow:SetVertexColor(0, 0, 0, 0.30)
        tab.iconOutline:SetPoint("CENTER", tab.iconSlot, "CENTER", 0, 0)
        tab.iconShadow:SetPoint("CENTER", tab.iconSlot, "CENTER", 0, -0.5)
        tab.iconOutline:SetSize(SM_TAB_ICON_SIZE + 1, SM_TAB_ICON_SIZE + 1)
        tab.iconShadow:SetSize(SM_TAB_ICON_SIZE + 2, SM_TAB_ICON_SIZE + 2)
        tab.label = GUI2:CreateText(tab, { text = "", fontSize = 11, color = "color.ybar.text" })
        tab.label:SetPoint("LEFT", tab.iconSlot, "RIGHT", 5, 0)
        tab.label:SetJustifyH("LEFT")
        tab.label:SetWordWrap(false)
        tab:SetScript("OnEnter", function()
            self:StopHideTimer()
            self:StopSubMenuSwitch()
            if self.itemMenuGroup ~= group then
                self:ShowSubMenu(self.activeMenuAnchor, "Items", group)
            end
        end)
        tab:SetScript("OnLeave", function() self:StartHideTimer() end)
        tab:SetScript("OnClick", function() self:ShowSubMenu(self.activeMenuAnchor, "Items", group) end)
        pane.tabs[i] = tab
    end
    return pane
end

function Module:ShowSubMenu(anchor, category, itemGroup)
    if not self._runtimeAttached or not anchor or not category or SecurityAPI.InCombatLockdown() then return end
    self:StopHideTimer()
    self:StopSubMenuSwitch()
    self:HideMenuTooltip()
    YUI.HideGameTooltip()
    local sameCategory = self.activeMenuCategory == category
    if category == "Items" then
        itemGroup = itemGroup or self.itemMenuGroup or "toy"
        if not DATA.ItemGroups[itemGroup] then itemGroup = "toy" end
    end
    local pane = self:EnsureSubMenu()
    local savedScroll = sameCategory and (category ~= "Items" or self.itemMenuGroup == itemGroup) and pane.scroll:GetVerticalScroll() or 0
    self.activeMenuCategory, self.activeMenuAnchor = category, anchor
    self.itemMenuGroup = itemGroup or self.itemMenuGroup
    self.menuAimX, self.menuAimY = GetMenuCursor()

    local items, maxGroupItems = nil, 0
    local headerHeight = category == "Items" and 32 or 8
    if category == "Items" then
        items = self:BuildSubMenuItems(category, itemGroup)
        for i, group in ipairs(ITEM_GROUPS) do
            local count = group == itemGroup and #items or self:GetItemGroupCount(group)
            maxGroupItems = math.max(maxGroupItems, count)
            local tab = pane.tabs[i]
            tab.iconSlot.icon:SetTexture(self:GetItemGroupIcon(group))
            tab.label:SetText(T(ITEM_GROUP_LABELS[group], group) .. " " .. count)
            GUI2:SetTextColorKey(tab.label, group == itemGroup and "color.text.accent" or "color.text.muted")
            tab:Show()
        end
    else
        for _, tab in ipairs(pane.tabs) do tab:Hide() end
        items = self:BuildSubMenuItems(category)
    end
    pane.emptyText:SetShown(category == "Items" and #items == 0)

    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local anchorX, anchorY = anchor:GetCenter()
    local keepItemLayout = category == "Items" and sameCategory and pane:IsShown() and
        pane.itemLayoutAnchor == anchor and pane.itemLayoutAnchorX == anchorX and pane.itemLayoutAnchorY == anchorY and
        pane.itemLayoutScreenWidth == screenWidth and pane.itemLayoutScreenHeight == screenHeight
    local leftSpace = MenuFrame:GetLeft() - MENU_SCREEN_PADDING - MENU_GAP
    local rightSpace = screenWidth - MenuFrame:GetRight() - MENU_SCREEN_PADDING - MENU_GAP
    self.subMenuOpensLeft = leftSpace > rightSpace
    local availableWidth = math.max(leftSpace, rightSpace)
    local columns = math.max(1, math.min(SM_COLUMNS, math.floor((availableWidth - 24) / (SM_ITEM_WIDTH + SM_PADDING_X))))
    local longestRow, rowSize = 0, 0
    for _, item in ipairs(items) do
        if item.isHeader then rowSize = 0
        else rowSize = rowSize + 1; longestRow = math.max(longestRow, math.min(columns, rowSize)) end
    end
    if category == "Items" then longestRow = maxGroupItems end
    columns = math.max(1, math.min(columns, math.max(1, longestRow)))
    if keepItemLayout then columns = pane.itemLayoutColumns end
    local contentWidth = columns * (SM_ITEM_WIDTH + SM_PADDING_X)
    local totalWidth = math.min(availableWidth, math.max(category == "Items" and 268 or 0, contentWidth + 24))
    if keepItemLayout then totalWidth = pane:GetWidth() end
    if category == "Items" and not keepItemLayout then
        local tabWidth = (totalWidth - 16) / #ITEM_GROUPS
        for i, tab in ipairs(pane.tabs) do
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", 8 + (i - 1) * tabWidth, -6)
            tab:SetWidth(tabWidth - 2)
        end
    end
    if category == "Items" then
        for _, tab in ipairs(pane.tabs) do
            local labelWidth = math.min(tab.label:GetStringWidth(), math.max(1, tab:GetWidth() - SM_TAB_ICON_SIZE - 9))
            tab.label:SetWidth(labelWidth)
            tab.iconSlot:ClearAllPoints()
            tab.iconSlot:SetPoint("LEFT", tab, "CENTER", -(SM_TAB_ICON_SIZE + 5 + labelWidth) / 2, 0)
        end
    end
    local content = pane.content
    HideMenuButtonPool(content.headerButtons)
    HideMenuButtonPool(content.itemButtons)
    local y, column, headerIndex, itemIndex = 0, 0, 0, 0
    local firstRowCenter
    for _, item in ipairs(items) do
        if item.isHeader then
            if column > 0 then y = y + SM_ITEM_HEIGHT + SM_PADDING_Y; column = 0 end
            headerIndex = headerIndex + 1
            local header = content.headerButtons and content.headerButtons[headerIndex]
            if not header then
                header = GUI2:CreateFrame(content)
                header.label = GUI2:CreateText(header, { text = "", fontSize = 13, color = "color.text.accent" })
                header.label:SetAllPoints(header)
                content.headerButtons = content.headerButtons or {}
                content.headerButtons[headerIndex] = header
            end
            header:SetSize(contentWidth, 24)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 0, -y)
            header.label:SetText(item.text)
            header:Show()
            y = y + 24
        else
            itemIndex = itemIndex + 1
            item.text = GetNameMapping(item.mapKey or item.id) or GetNameMapping(item.text) or item.text or "?"
            local button = self:AcquireMenuButton(content, "itemButtons", itemIndex,
                item.text, item.icon or 134414, item, false, nil, "grid_text_bottom")
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", column * (SM_ITEM_WIDTH + SM_PADDING_X), -y)
            local owned = item.type == "spell" and SpellAPI.IsKnown(item.id) or
                (item.type == "toy" and PlayerHasToy(item.id)) or
                (item.type == "item" and ItemAPI.GetCount(item.id) > 0)
            button.icon:SetDesaturated(not owned)
            local r, g, b = 1, 1, 1
            if not owned then r, g, b = 0.5, 0.5, 0.5
            elseif item.type == "spell" then
                if category == "Dungeons" or category == "CurrentSeason" then r, g, b = 1, 0.5, 0
                elseif category == "MageTeleports" then r, g, b = 0.41, 0.80, 0.94
                else r, g, b = 1, 0.82, 0 end
            else
                local info = ItemAPI.GetInfo(item.id)
                if info and info.quality then r, g, b = ItemAPI.GetQualityColor(info.quality) end
            end
            YBar:SetStatusTextColor(button.statusText, "color.ybar.dynamic", { r, g, b, 1 })
            button:Enable()
            button:Show()
            if not firstRowCenter then firstRowCenter = headerHeight + y + SM_ICON_SIZE / 2 + 2 end
            column = column + 1
            if column >= columns then column = 0; y = y + SM_ITEM_HEIGHT + SM_PADDING_Y end
        end
    end
    if column > 0 then y = y + SM_ITEM_HEIGHT + SM_PADDING_Y end
    local contentHeight = math.max(y, SM_ITEM_HEIGHT)
    local layoutHeight = category == "Items" and math.max(SM_ITEM_HEIGHT,
        math.ceil(maxGroupItems / columns) * (SM_ITEM_HEIGHT + SM_PADDING_Y)) or contentHeight
    local totalHeight = math.min(layoutHeight + headerHeight + 8, math.min(560, screenHeight - 16))
    if keepItemLayout then totalHeight = pane:GetHeight() end
    local viewportHeight = math.max(1, totalHeight - headerHeight - 8)
    if not keepItemLayout then pane:SetSize(totalWidth, totalHeight) end
    pane.scroll:ClearAllPoints()
    pane.scroll:SetPoint("TOPLEFT", 8, -headerHeight)
    pane.scroll:SetSize(totalWidth - 24, viewportHeight)
    content:SetSize(totalWidth - 24, contentHeight)
    pane.scrollBar:ClearAllPoints()
    pane.scrollBar:SetPoint("TOPRIGHT", -4, -headerHeight)
    pane.scrollBar:SetHeight(viewportHeight)
    pane.contentHeight, pane.viewportHeight = contentHeight, viewportHeight
    pane.scrollMax = math.max(0, contentHeight - viewportHeight)
    savedScroll = math.max(0, math.min(pane.scrollMax, savedScroll))
    pane.scroll:SetVerticalScroll(savedScroll)
    pane.scrollBar:SetScrollState(savedScroll + 1, contentHeight, viewportHeight, true)
    local _, anchorCenter = anchor:GetCenter()
    local top = math.max(totalHeight + MENU_SCREEN_PADDING,
        math.min(screenHeight - MENU_SCREEN_PADDING, anchorCenter + (firstRowCenter or headerHeight + 18)))
    local x = self.subMenuOpensLeft and MenuFrame:GetLeft() - MENU_GAP - totalWidth or MenuFrame:GetRight() + MENU_GAP
    x = math.max(MENU_SCREEN_PADDING, math.min(screenWidth - totalWidth - MENU_SCREEN_PADDING, x))
    if not keepItemLayout then
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
        pane:SetHitRectInsets(self.subMenuOpensLeft and -MENU_TOLERANCE or -1,
            self.subMenuOpensLeft and -1 or -MENU_TOLERANCE, -MENU_TOLERANCE, -MENU_TOLERANCE)
    end
    if category == "Items" then
        pane.itemLayoutAnchor, pane.itemLayoutAnchorX, pane.itemLayoutAnchorY = anchor, anchorX, anchorY
        pane.itemLayoutScreenWidth, pane.itemLayoutScreenHeight, pane.itemLayoutColumns = screenWidth, screenHeight, columns
    end
    pane:Show()
end

function Module:HideSubMenu()
    if self.menuTooltipData and not self.menuTooltipData.isLv1Item then self:HideMenuTooltip() end
    self:StopSubMenuSwitch()
    self.activeMenuCategory, self.activeMenuAnchor = nil, nil
    self.menuAimX, self.menuAimY = nil, nil
    if self.SubMenuFrame and not SecurityAPI.InCombatLockdown() then self.SubMenuFrame:Hide() end
end

function Module:HideMenu()
    self:StopHideTimer()
    self:StopSubMenuSwitch()
    if SecurityAPI.InCombatLockdown() then self.needsMenuHide = true; return end
    self.needsMenuHide = nil
    self:HideSubMenu()
    if MenuFrame then MenuFrame:Hide() end
end

function Module:GetWidth()
    if self.frame then
        return self.frame:GetWidth()
    end
    return 10
end

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("YBar") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    local options = {
        { type = "divider", label = YBarL["teleports.settings.appearance_header"] or "Appearance", alignLeft = true, width = 600 },
        {
            type = "dropdown",
            label = CoreL["common.font"] or "Font",
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return self.db.font or defaultFont end,
            set = function(val)
                self.db.font = val
                self:UpdateBarItem(self.frame)
            end
        },
        {
            type = "slider",
            label = CoreL["common.size"] or "Size",
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return self.db.size or DEFAULT_ICON_SIZE end,
            set = function(val)
                self.db.size = val
                self:UpdateBarItem(self.frame)
            end
        },
        {
            type = "checkbox",
            label = CoreL["common.show_icon"] or "Show Icon",
            get = function() return self.db.showIcon end,
            set = function(v)
                self.db.showIcon = v
                self:UpdateBarItem(self.frame)
            end,
        },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.hearthstone_mode"] or "Hearthstone Mode",
            width = 220,
            options = {
                {text = YBarL["ybar.settings.option.fixed"] or "Fixed", value = "fixed"},
                {text = YBarL["ybar.settings.option.random"] or "Random", value = "random"},
            },
            get = function() return self.db.hearthstoneMode end,
            set = function(v)
                self.db.hearthstoneMode = v
                self:UpdateBarItem(self.frame)
            end,
            onChange = function(widget, value)
                local parent = widget:GetParent()
                if parent and parent:GetParent() then
                    parent = parent:GetParent()
                end
                local S = YUI.Settings
                if parent and S and S.ClearConfig and S.RenderConfig then
                    S:ClearConfig(parent)
                    S:RenderConfig(parent, self:GetOptions())
                end
            end,
        },
        {
            type = "dropdown",
            label = YBarL["teleports.settings.select_hearthstone"] or "Select Hearthstone",
            width = 220,
            requires = function() return self.db.hearthstoneMode == "fixed" end,
            options = function()
                return self:BuildHearthstoneOptions()
            end,
            get = function() return self.db.customHearthstone end,
            set = function(v)
                self.db.customHearthstone = v
                self:UpdateBarItem(self.frame)
            end,
        },
        {
            type = "checkbox",
            label = YBarL["teleports.settings.season_on_main_menu"] or "当前赛季传送门显示在主菜单",
            tooltip = YBarL["teleports.settings.season_on_main_menu_tip"]
                or "开启后，当前赛季的大秘境传送门直接显示在传送菜单主页面；关闭后收纳到当前赛季二级菜单。",
            get = function() return self.db.seasonOnMainMenu ~= false end,
            set = function(value)
                self.db.seasonOnMainMenu = value == true
                if MenuFrame and MenuFrame:IsShown() then
                    if SecurityAPI.InCombatLockdown() then
                        self:HideMenu()
                    else
                        self:PopulateMainMenu(MenuFrame)
                    end
                end
            end,
        },

    }
    for _, option in ipairs(YUI.TeleportAnnouncement:GetOptions(600)) do
        options[#options + 1] = option
    end
    return options
end

YBar:RegisterModule(Module, {
    id = "ybar.teleports",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.event", "core.api", "gui"},
    defaultEnabled = true,
})
