-- YUI 地图标记数据使用声明
-- 本文件中由 YUI 自主采集、整理与校核的数据由作者阿言维护。
-- 随 YUI 正常使用这些数据无需另行申请。
-- 提取、复制、修改、转载、再分发或用于其他项目之前，必须获得作者阿言的明确同意。
-- 本声明针对 YUI 自主采集与整理的内容；游戏原有名称、资源及公开数据的权利归原权利人。
-- Data notice: YUI-collected and curated data is maintained by 阿言.
-- Normal use within YUI is permitted. Prior express permission from the author is required
-- for extraction, copying, modification, republication, redistribution or use in other projects.
-- Rights in underlying game names, assets and public data remain with their respective owners.

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local MapEnhancement = YUI.YMap.Markers or {}
YUI.YMap.Markers = MapEnhancement

local Data = MapEnhancement.Data or {}
MapEnhancement.Data = Data

if not YUI.IsForever then return end

local function RegisterWeaponTrainerSite(siteID)
    local site = assert(YUI.API.WeaponSkill.GetTrainerSite(siteID), "Missing weapon trainer site")
    local values = {site.pointID, site.x, site.y}
    values.weaponTrainerSiteID = siteID
    Data:RegisterGroup(site.mapID, "equipment.weapon_trainer", site.faction, values)
end

-- 玩家在 Forever 地图 2521 独立采集；保留原始编号与坐标。
Data.maps = { { mapID = 2521, nameKey = "map.forever.2521", order = 10 } }
Data.mapByID = { [2521] = Data.maps[1] }
Data.zoomRules = {}
Data.records = {}
Data:RegisterGroup(2521, "service.inn", nil, {
    "map2521.point.001", 0.6221, 0.7343,
})
Data:RegisterGroup(2521, "service.bank", nil, {
    "map2521.point.003", 0.5784, 0.7713,
})
Data:RegisterGroup(2521, "service.auction", nil, {
    "map2521.point.003.service.auction", 0.5784, 0.7713,
})
Data:RegisterGroup(2521, "travel.dalaran", nil, {
    "map2521.point.004", 0.6544, 0.8376,
})
Data:RegisterGroup(2521, "profession.186", nil, {
    "map2521.point.006", 0.6532, 0.8006,
})
Data:RegisterGroup(2521, "profession.164", nil, {
    "map2521.point.006.profession.164", 0.6532, 0.8006,
})
Data:RegisterGroup(2521, "profession.197", nil, {
    "map2521.point.007", 0.6414, 0.8055,
})
Data:RegisterGroup(2521, "profession.165", nil, {
    "map2521.point.007.profession.165", 0.6414, 0.8055,
})
Data:RegisterGroup(2521, "profession.333", nil, {
    "map2521.point.009", 0.5931, 0.7611,
})
Data:RegisterGroup(2521, "profession.171", nil, {
    "map2521.point.009.profession.171", 0.5931, 0.7611,
})
Data:RegisterGroup(2521, "profession.182", nil, {
    "map2521.point.010", 0.5820, 0.7497,
})
Data:RegisterGroup(2521, "trainer.WARRIOR", nil, {
    "map2521.point.012", 0.5980, 0.7275,
})
Data:RegisterGroup(2521, "trainer.ROGUE", nil, {
    "map2521.point.012.trainer.ROGUE", 0.5980, 0.7275,
})
Data:RegisterGroup(2521, "trainer.HUNTER", nil, {
    "map2521.point.012.trainer.HUNTER", 0.5980, 0.7275,
})
Data:RegisterGroup(2521, "profession.185", nil, {
    "map2521.point.013", 0.6053, 0.7309,
})
Data:RegisterGroup(2521, "profession.202", nil, {
    "map2521.point.014", 0.5382, 0.3945,
})
Data:RegisterGroup(2521, "profession.356", nil, {
    "map2521.point.015", 0.6293, 0.7636,
})
Data:RegisterGroup(2521, "profession.129", nil, {
    "map2521.point.016", 0.6288, 0.7284,
})
Data:RegisterGroup(2521, "trainer.MAGE", nil, {
    "map2521.point.017", 0.6561, 0.8123,
})
Data:RegisterGroup(2521, "trainer.SHAMAN", nil, {
    "map2521.point.018", 0.5781, 0.7911,
})
Data:RegisterGroup(2521, "trainer.DRUID", nil, {
    "map2521.point.019", 0.6356, 0.7562,
})
-- 手动采集 055–059：复合名称按服务拆分，导航保留各组原始坐标。
Data:RegisterGroup(2521, "trainer.MAGE", nil, {
    "map2521.point.055", 0.4506, 0.4544,
})
Data:RegisterGroup(2521, "trainer.WARRIOR", nil, {
    "map2521.point.055.trainer.WARRIOR", 0.4506, 0.4544,
})
Data:RegisterGroup(2521, "trainer.HUNTER", nil, {
    "map2521.point.055.trainer.HUNTER", 0.4506, 0.4544,
})
Data:RegisterGroup(2521, "trainer.DRUID", nil, {
    "map2521.point.055.trainer.DRUID", 0.4506, 0.4544,
})
Data:RegisterGroup(2521, "profession.197", nil, {
    "map2521.point.056", 0.4448, 0.4410,
})
Data:RegisterGroup(2521, "profession.164", nil, {
    "map2521.point.056.profession.164", 0.4448, 0.4410,
})
Data:RegisterGroup(2521, "profession.186", nil, {
    "map2521.point.056.profession.186", 0.4448, 0.4410,
})
Data:RegisterGroup(2521, "profession.165", nil, {
    "map2521.point.056.profession.165", 0.4448, 0.4410,
})
Data:RegisterGroup(2521, "profession.171", nil, {
    "map2521.point.057", 0.4373, 0.4345,
})
Data:RegisterGroup(2521, "profession.185", nil, {
    "map2521.point.057.profession.185", 0.4373, 0.4345,
})
Data:RegisterGroup(2521, "profession.182", nil, {
    "map2521.point.058", 0.4302, 0.4321,
})
Data:RegisterGroup(2521, "profession.393", nil, {
    "map2521.point.058.profession.393", 0.4302, 0.4321,
})
Data:RegisterGroup(2521, "profession.333", nil, {
    "map2521.point.058.profession.333", 0.4302, 0.4321,
})
Data:RegisterGroup(2521, "service.inn", nil, {
    "map2521.point.058.service.inn", 0.4302, 0.4321,
})
Data:RegisterGroup(2521, "trainer.ROGUE", nil, {
    "map2521.point.058.trainer.ROGUE", 0.4302, 0.4321,
})
Data:RegisterGroup(2521, "profession.129", nil, {
    "map2521.point.059", 0.4322, 0.4663,
})
Data.groups = {}

-- 普通航点：独立客户端扫描；按所属地图选取该地图的原始归一化坐标。
-- 不包含职业专用、占塔、战场、废弃及新区域条件未核实节点。
local function LoadOrdinaryFlights(faction)
    Data:RegisterGroup(1449, "travel.flight", "Neutral", {
        "forever.taxi.79", 0.45298212766647, 0.05965682864189, 79,
    })
    Data:RegisterGroup(1413, "travel.flight", "Neutral", {
        "forever.taxi.80", 0.63117700815201, 0.37107738852501, 80,
    })
    if faction == "Alliance" then
        Data:RegisterGroup(1436, "travel.flight", "Alliance", {
            "forever.taxi.4", 0.56571060419083, 0.52666717767715, 4,
        })
        Data:RegisterGroup(1433, "travel.flight", "Alliance", {
            "forever.taxi.5", 0.25342860817909, 0.58988249301910, 5,
        })
        Data:RegisterGroup(1455, "travel.flight", "Alliance", {
            "forever.taxi.6", 0.55886030197144, 0.47865092754364, 6,
        })
        Data:RegisterGroup(1437, "travel.flight", "Alliance", {
            "forever.taxi.7", 0.09520310908556, 0.59658706188202, 7,
        })
        Data:RegisterGroup(1432, "travel.flight", "Alliance", {
            "forever.taxi.8", 0.33943006396294, 0.50794714689255, 8,
        })
        Data:RegisterGroup(1431, "travel.flight", "Alliance", {
            "forever.taxi.12", 0.77591997385025, 0.44377461075783, 12,
        })
        Data:RegisterGroup(1424, "travel.flight", "Alliance", {
            "forever.taxi.14", 0.49442073702812, 0.52100634574890, 14,
        })
        Data:RegisterGroup(1417, "travel.flight", "Alliance", {
            "forever.taxi.16", 0.45790088176727, 0.46133214235306, 16,
        })
        Data:RegisterGroup(1434, "travel.flight", "Alliance", {
            "forever.taxi.19", 0.27528846263885, 0.77672106027603, 19,
        })
        Data:RegisterGroup(1439, "travel.flight", "Alliance", {
            "forever.taxi.26", 0.36396750807762, 0.45617273449898, 26,
        })
        Data:RegisterGroup(1438, "travel.flight", "Alliance", {
            "forever.taxi.27", 0.58399993181229, 0.93927377462387, 27,
        })
        Data:RegisterGroup(1440, "travel.flight", "Alliance", {
            "forever.taxi.28", 0.34495514631271, 0.48015010356903, 28,
        })
        Data:RegisterGroup(1441, "travel.flight", "Alliance", {
            "forever.taxi.31", 0.07785367965698, 0.17905046045780, 31,
        })
        Data:RegisterGroup(1445, "travel.flight", "Alliance", {
            "forever.taxi.32", 0.67458671331406, 0.51201063394547, 32,
        })
        Data:RegisterGroup(1442, "travel.flight", "Alliance", {
            "forever.taxi.33", 0.36535590887070, 0.07233390212059, 33,
        })
        Data:RegisterGroup(1443, "travel.flight", "Alliance", {
            "forever.taxi.37", 0.64671272039413, 0.10435344278812, 37,
        })
        Data:RegisterGroup(1446, "travel.flight", "Alliance", {
            "forever.taxi.39", 0.50954210758209, 0.29325422644615, 39,
        })
        Data:RegisterGroup(1444, "travel.flight", "Alliance", {
            "forever.taxi.41", 0.30259245634079, 0.43319445848465, 41,
        })
        Data:RegisterGroup(1425, "travel.flight", "Alliance", {
            "forever.taxi.43", 0.11110656708479, 0.46088066697121, 43,
        })
        Data:RegisterGroup(1419, "travel.flight", "Alliance", {
            "forever.taxi.45", 0.65494710206985, 0.24429135024548, 45,
        })
        Data:RegisterGroup(1450, "travel.flight", "Alliance", {
            "forever.taxi.49", 0.47911736369133, 0.67110097408295, 49,
        })
        Data:RegisterGroup(1452, "travel.flight", "Alliance", {
            "forever.taxi.52", 0.62334871292114, 0.36635777354240, 52,
        })
        Data:RegisterGroup(1447, "travel.flight", "Alliance", {
            "forever.taxi.64", 0.11902493983507, 0.77476567029953, 64,
        })
        Data:RegisterGroup(1448, "travel.flight", "Alliance", {
            "forever.taxi.65", 0.62457346916199, 0.24194435775280, 65,
        })
        Data:RegisterGroup(1422, "travel.flight", "Alliance", {
            "forever.taxi.66", 0.42948287725449, 0.84953951835632, 66,
        })
        Data:RegisterGroup(1423, "travel.flight", "Alliance", {
            "forever.taxi.67", 0.71698981523514, 0.49555060267448, 67,
        })
        Data:RegisterGroup(1428, "travel.flight", "Alliance", {
            "forever.taxi.71", 0.84381788969040, 0.68304526805878, 71,
        })
        Data:RegisterGroup(1451, "travel.flight", "Alliance", {
            "forever.taxi.73", 0.50683379173279, 0.34589976072311, 73,
        })
        Data:RegisterGroup(1427, "travel.flight", "Alliance", {
            "forever.taxi.74", 0.37886998057365, 0.30426159501076, 74,
        })
    end
    if faction == "Horde" then
        Data:RegisterGroup(1421, "travel.flight", "Horde", {
            "forever.taxi.10", 0.45557370781898, 0.42421740293503, 10,
        })
        Data:RegisterGroup(1458, "travel.flight", "Horde", {
            "forever.taxi.11", 0.63085001707077, 0.48324432969093, 11,
        })
        Data:RegisterGroup(1424, "travel.flight", "Horde", {
            "forever.taxi.13", 0.60205549001694, 0.18752810359001, 13,
        })
        Data:RegisterGroup(1417, "travel.flight", "Horde", {
            "forever.taxi.17", 0.73061782121658, 0.32623231410980, 17,
        })
        Data:RegisterGroup(1434, "travel.flight", "Horde", {
            "forever.taxi.18", 0.26816296577454, 0.76996052265167, 18,
            "forever.taxi.20", 0.32510015368462, 0.29275542497635, 20,
        })
        Data:RegisterGroup(1418, "travel.flight", "Horde", {
            "forever.taxi.21", 0.04055718332529, 0.44888913631439, 21,
        })
        Data:RegisterGroup(1456, "travel.flight", "Horde", {
            "forever.taxi.22", 0.46654310822487, 0.49898496270180, 22,
        })
        Data:RegisterGroup(1454, "travel.flight", "Horde", {
            "forever.taxi.23", 0.45280817151070, 0.63745778799057, 23,
        })
        Data:RegisterGroup(1413, "travel.flight", "Horde", {
            "forever.taxi.25", 0.51503264904022, 0.30405941605568, 25,
            "forever.taxi.77", 0.44463017582893, 0.59103339910507, 77,
        })
        Data:RegisterGroup(1442, "travel.flight", "Horde", {
            "forever.taxi.29", 0.45164117217064, 0.59887814521790, 29,
        })
        Data:RegisterGroup(1441, "travel.flight", "Horde", {
            "forever.taxi.30", 0.45022010803223, 0.49126511812210, 30,
        })
        Data:RegisterGroup(1443, "travel.flight", "Horde", {
            "forever.taxi.38", 0.21563108265400, 0.74042212963104, 38,
        })
        Data:RegisterGroup(1446, "travel.flight", "Horde", {
            "forever.taxi.40", 0.51617521047592, 0.25519329309464, 40,
        })
        Data:RegisterGroup(1444, "travel.flight", "Horde", {
            "forever.taxi.42", 0.75429588556290, 0.44313532114029, 42,
        })
        Data:RegisterGroup(1447, "travel.flight", "Horde", {
            "forever.taxi.44", 0.21954928338528, 0.49690091609955, 44,
        })
        Data:RegisterGroup(1448, "travel.flight", "Horde", {
            "forever.taxi.48", 0.34415417909622, 0.53867816925049, 48,
        })
        Data:RegisterGroup(1452, "travel.flight", "Horde", {
            "forever.taxi.53", 0.60485273599625, 0.36343804001808, 53,
        })
        Data:RegisterGroup(1445, "travel.flight", "Horde", {
            "forever.taxi.55", 0.35565349459648, 0.31830194592476, 55,
        })
        Data:RegisterGroup(1435, "travel.flight", "Horde", {
            "forever.taxi.56", 0.46052730083466, 0.54679250717163, 56,
        })
        Data:RegisterGroup(1440, "travel.flight", "Horde", {
            "forever.taxi.58", 0.12191276252270, 0.33774498105049, 58,
            "forever.taxi.61", 0.73258119821548, 0.61672240495682, 61,
        })
        Data:RegisterGroup(1423, "travel.flight", "Horde", {
            "forever.taxi.68", 0.70445865392685, 0.47590383887291, 68,
        })
        Data:RegisterGroup(1450, "travel.flight", "Horde", {
            "forever.taxi.69", 0.32149952650070, 0.66334587335587, 69,
        })
        Data:RegisterGroup(1428, "travel.flight", "Horde", {
            "forever.taxi.70", 0.65577530860901, 0.24219237267971, 70,
        })
        Data:RegisterGroup(1451, "travel.flight", "Horde", {
            "forever.taxi.72", 0.48825648427010, 0.36723503470421, 72,
        })
        Data:RegisterGroup(1427, "travel.flight", "Horde", {
            "forever.taxi.75", 0.34829562902451, 0.30583569407463, 75,
        })
        Data:RegisterGroup(1425, "travel.flight", "Horde", {
            "forever.taxi.76", 0.81701326370239, 0.81893259286880, 76,
        })
    end
end

-- Forever 1.60.1.70009 TaxiPath：仅普通、无节点条件、本阵营的有向航线。
local function LoadFlightRoutes(faction)
    if faction == "Alliance" then
        Data.flightRoutes = {
            [2] = {4, 5, 6, 12, 19, 45, 71},
            [4] = {2, 5, 12, 19},
            [5] = {2, 4, 12, 71},
            [6] = {2, 7, 8, 14, 16, 43, 66, 67, 74},
            [7] = {6, 8, 14, 16},
            [8] = {6, 7, 16},
            [12] = {2, 4, 5, 19, 45},
            [14] = {6, 7, 16, 43, 66},
            [16] = {6, 7, 8, 14, 43},
            [19] = {2, 4, 12},
            [26] = {27, 28, 32, 33, 37, 41, 49, 64, 65},
            [27] = {26},
            [28] = {26, 33, 64},
            [31] = {32, 39, 41},
            [32] = {26, 31, 37, 39, 64, 80},
            [33] = {26, 28, 37},
            [37] = {26, 32, 33, 41},
            [39] = {31, 32, 73, 79},
            [41] = {26, 31, 37, 73},
            [43] = {6, 14, 16, 66, 67},
            [45] = {2, 12, 71},
            [49] = {26, 52, 65},
            [52] = {49, 64, 65},
            [64] = {26, 28, 32, 52, 65, 80},
            [65] = {26, 49, 52, 64},
            [66] = {6, 14, 43, 67},
            [67] = {6, 43, 66},
            [71] = {2, 5, 45, 74},
            [73] = {39, 41, 79},
            [74] = {6, 71},
            [79] = {39, 73},
            [80] = {32, 64},
        }
    end
    if faction == "Horde" then
        Data.flightRoutes = {
            [10] = {11, 13},
            [11] = {10, 13, 17, 21, 68, 76},
            [13] = {10, 11, 17, 76},
            [17] = {11, 13, 21, 76},
            [18] = {20, 21, 56},
            [20] = {18, 21, 56},
            [21] = {11, 17, 18, 20, 56, 70, 75},
            [22] = {23, 25, 29, 30, 38, 40, 42, 44, 55, 77},
            [23] = {22, 25, 40, 44, 48, 53, 55, 61},
            [25] = {22, 23, 29, 30, 40, 42, 44, 48, 55, 58, 61, 77, 80},
            [29] = {22, 25, 38},
            [30] = {22, 25, 40, 42, 77},
            [38] = {22, 29, 42},
            [40] = {22, 23, 25, 30, 42, 55, 72, 79},
            [42] = {22, 25, 30, 38, 40, 72},
            [44] = {22, 23, 25, 48, 53, 61},
            [48] = {23, 25, 44, 53, 69},
            [53] = {23, 44, 48, 69},
            [55] = {22, 23, 25, 40},
            [56] = {18, 20, 21, 70},
            [58] = {25, 61},
            [61] = {23, 25, 44, 58},
            [68] = {11, 76},
            [69] = {48, 53},
            [70] = {21, 56, 75},
            [72] = {40, 42, 79},
            [75] = {21, 70},
            [76] = {11, 13, 17, 68},
            [77] = {22, 25, 30},
            [79] = {40, 72},
            [80] = {25},
        }
    end
end

function Data:LoadPlayerFactionPoints()
    if self.foreverFactionLoaded then return end
    local unitAPI = YUI.API and YUI.API.Unit
    local faction = unitAPI and unitAPI.UnitFactionGroup and unitAPI.UnitFactionGroup("player")
    if faction ~= "Alliance" and faction ~= "Horde" then return end
    self.foreverFactionLoaded = faction
    LoadOrdinaryFlights(faction)
    LoadFlightRoutes(faction)
    do
        local map = { mapID = 1453, nameKey = "map.forever.1453", order = 20 }
        self.maps[#self.maps + 1], self.mapByID[1453] = map, map
    end
    do
        local map = { mapID = 1455, nameKey = "map.forever.1455", order = 30 }
        self.maps[#self.maps + 1], self.mapByID[1455] = map, map
    end
    do
        local map = { mapID = 1439, nameKey = "map.forever.1439", order = 40 }
        self.maps[#self.maps + 1], self.mapByID[1439] = map, map
    end
    do
        local map = { mapID = 1437, nameKey = "map.forever.1437", order = 50 }
        self.maps[#self.maps + 1], self.mapByID[1437] = map, map
    end
    do
        local map = { mapID = 1424, nameKey = "map.forever.1424", order = 60 }
        self.maps[#self.maps + 1], self.mapByID[1424] = map, map
    end
    do
        local map = { mapID = 1457, nameKey = "map.forever.1457", order = 70 }
        self.maps[#self.maps + 1], self.mapByID[1457] = map, map
    end
    do
        local map = { mapID = 1438, nameKey = "map.forever.1438", order = 80 }
        self.maps[#self.maps + 1], self.mapByID[1438] = map, map
    end
    self.unclusteredTextPoints = {
        ["map1439.point.021"] = true,
        ["map1439.point.034"] = true,
        ["map1439.point.035"] = true,
    }

    Data:RegisterGroup(1453, "travel.tram", nil, {
        "forever.1453.021", 0.66642153263092, 0.33815658092499,
    }, { [1] = "poi.tooltip.tram.ironforge" })
    Data:RegisterGroup(1455, "travel.tram", nil, {
        "forever.1455.travel.tram", 0.73499929904938, 0.50423908233643,
    }, { [1] = "poi.tooltip.tram.stormwind" })
    do
        local map = { mapID = 1420, nameKey = "map.forever.1420", order = 110 }
        self.maps[#self.maps + 1], self.mapByID[1420] = map, map
    end
    do
        local map = { mapID = 1434, nameKey = "map.forever.1434", order = 130 }
        self.maps[#self.maps + 1], self.mapByID[1434] = map, map
    end
    do
        local map = { mapID = 1411, nameKey = "map.forever.1411", order = 150 }
        self.maps[#self.maps + 1], self.mapByID[1411] = map, map
    end
    Data:RegisterGroup(1411, "travel.zeppelin.gromgol", nil, {
        "map1411.point.053", 0.5035, 0.1235,
    })
    Data:RegisterGroup(1411, "travel.zeppelin.undercity", nil, {
        "map1411.point.054", 0.5073, 0.1396,
    })
    Data:RegisterGroup(1420, "travel.zeppelin.orgrimmar", nil, {
        "map1420.point.048", 0.6059, 0.5871,
    })
    Data:RegisterGroup(1420, "travel.zeppelin.gromgol", nil, {
        "map1420.point.049", 0.6189, 0.5896,
    })
    Data:RegisterGroup(1434, "travel.zeppelin.undercity", nil, {
        "map1434.point.050", 0.3140, 0.2987,
    })
    Data:RegisterGroup(1434, "travel.zeppelin.orgrimmar", nil, {
        "map1434.point.050.orgrimmar", 0.3140, 0.2987,
    })
    Data:RegisterGroup(1439, "travel.boat.stormwind", nil, {
        "map1439.point.021", 0.3090, 0.4120,
    })
    Data:RegisterGroup(1439, "travel.boat.darnassus", nil, {
        "map1439.point.035", 0.3317, 0.3974,
    })
    Data:RegisterGroup(1439, "travel.boat.menethil_southshore", nil, {
        "map1439.point.034", 0.3238, 0.4388,
    })
    Data:RegisterGroup(1453, "travel.boat.auberdine", nil, {
        "map1453.point.024", 0.2263, 0.5610,
    }, { [1] = "travel.boat.auberdine.connections" })
    Data:RegisterGroup(1437, "travel.boat.theramore", nil, {
        "map1437.point.025", 0.0558, 0.6363,
    })
    Data:RegisterGroup(1424, "travel.boat.auberdine_menethil", nil, {
        "map1424.point.028", 0.5070, 0.6980,
    })
    Data:RegisterGroup(1437, "travel.boat.southshore_auberdine", nil, {
        "map1437.point.032", 0.0473, 0.5706,
    })
    Data:RegisterGroup(1438, "travel.boat.auberdine", nil, {
        "map1438.point.036", 0.5490, 0.9634,
    })
    Data:RegisterGroup(1438, "travel.portal.darnassus", nil, {
        "map1438.point.039", 0.5596, 0.8976,
    })
    Data:RegisterGroup(1457, "travel.portal.ruttheran", nil, {
        "map1457.point.038", 0.3035, 0.4148,
    })
    if faction == "Horde" then
        do
            local map = { mapID = 1454, nameKey = "map.forever.1454", order = 140 }
            self.maps[#self.maps + 1], self.mapByID[1454] = map, map
        end
        RegisterWeaponTrainerSite("orgrimmar")
        Data:RegisterGroup(1454, "profession.129", "Horde", {
            "forever.1454.profession.129", 0.34244215488434, 0.84310865402222,
        })
        Data:RegisterGroup(1454, "profession.164", "Horde", {
            "forever.1454.profession.164", 0.82079398632050, 0.23469457030296,
        })
        Data:RegisterGroup(1454, "profession.165", "Horde", {
            "forever.1454.profession.165", 0.62863004207611, 0.45011731982231,
        })
        Data:RegisterGroup(1454, "profession.171", "Horde", {
            "forever.1454.profession.171", 0.56694459915161, 0.34071138501167,
        })
        Data:RegisterGroup(1454, "profession.182", "Horde", {
            "forever.1454.profession.182", 0.55207097530365, 0.40116557478905,
        })
        Data:RegisterGroup(1454, "profession.185", "Horde", {
            "forever.1454.profession.185", 0.57087451219559, 0.52693879604340,
        })
        Data:RegisterGroup(1454, "profession.186", "Horde", {
            "forever.1454.profession.186", 0.72969907522202, 0.26094004511833,
        })
        Data:RegisterGroup(1454, "profession.197", "Horde", {
            "forever.1454.profession.197", 0.62744778394699, 0.50375103950500,
        })
        Data:RegisterGroup(1454, "profession.202", "Horde", {
            "forever.1454.profession.202", 0.75870198011398, 0.25167152285576,
        })
        Data:RegisterGroup(1454, "profession.333", "Horde", {
            "forever.1454.profession.333", 0.53782135248184, 0.38098236918449,
        })
        Data:RegisterGroup(1454, "profession.356", "Horde", {
            "forever.1454.profession.356", 0.69520556926727, 0.29903969168663,
        })
        Data:RegisterGroup(1454, "profession.393", "Horde", {
            "forever.1454.profession.393", 0.62863004207611, 0.45011731982231,
        })
        Data:RegisterGroup(1454, "service.auction", "Horde", {
            "forever.1454.service.auction", 0.54862743616104, 0.63571476936340,
        })
        Data:RegisterGroup(1454, "service.bank", "Horde", {
            "forever.1454.service.bank", 0.49531319737434, 0.68671905994415,
        })
        Data:RegisterGroup(1454, "service.barber", "Horde", {
            "forever.1454.service.barber", 0.46903452277184, 0.53235858678818,
        })
        Data:RegisterGroup(1454, "service.guild", "Horde", {
            "forever.1454.service.guild", 0.43786418437958, 0.74506753683090,
        })
        Data:RegisterGroup(1454, "service.inn", "Horde", {
            "forever.1454.service.inn", 0.54661005735397, 0.67282170057297,
        })
        Data:RegisterGroup(1454, "service.stable", "Horde", {
            "forever.1454.service.stable", 0.70107311010361, 0.15047577023506,
        })
        Data:RegisterGroup(1454, "service.transmogrifier", "Horde", {
            "forever.1454.service.transmogrifier", 0.46152654290199, 0.53907275199890,
        })
        Data:RegisterGroup(1454, "trainer.HUNTER", "Horde", {
            "forever.1454.trainer.HUNTER", 0.67354649305344, 0.17001801729202,
        })
        Data:RegisterGroup(1454, "trainer.MAGE", "Horde", {
            "forever.1454.trainer.MAGE", 0.38694417476654, 0.87941366434097,
        })
        Data:RegisterGroup(1454, "trainer.PALADIN", "Horde", {
            "forever.1454.trainer.PALADIN", 0.37774726748466, 0.37896266579628,
        })
        Data:RegisterGroup(1454, "trainer.PRIEST", "Horde", {
            "forever.1454.trainer.PRIEST", 0.35836198925972, 0.88907772302628,
        })
        Data:RegisterGroup(1454, "trainer.ROGUE", "Horde", {
            "forever.1454.trainer.ROGUE", 0.42661395668983, 0.53504270315170,
        })
        Data:RegisterGroup(1454, "trainer.SHAMAN", "Horde", {
            "forever.1454.trainer.SHAMAN", 0.35739865899086, 0.37259083986282,
        })
        Data:RegisterGroup(1454, "trainer.WARLOCK", "Horde", {
            "forever.1454.trainer.WARLOCK", 0.48416304588318, 0.45359244942665,
        })
        Data:RegisterGroup(1454, "trainer.WARRIOR", "Horde", {
            "forever.1454.trainer.WARRIOR", 0.79395860433578, 0.30997622013092,
        })
        Data:RegisterGroup(1454, "collection.reagents", "Horde", {
            "map1454.point.051", 0.4586, 0.4055,
            "map1454.point.052", 0.4541, 0.5686,
        })
        do
            local map = { mapID = 1458, nameKey = "map.forever.1458", order = 120 }
            self.maps[#self.maps + 1], self.mapByID[1458] = map, map
        end
        RegisterWeaponTrainerSite("undercity")
        Data:RegisterGroup(1458, "profession.129", "Horde", {
            "forever.1458.profession.129", 0.73588997125626, 0.55974614620209,
        })
        Data:RegisterGroup(1458, "profession.164", "Horde", {
            "forever.1458.profession.164", 0.61305725574493, 0.28424555063248,
        })
        Data:RegisterGroup(1458, "profession.165", "Horde", {
            "forever.1458.profession.165", 0.70541745424271, 0.59238344430923,
        })
        Data:RegisterGroup(1458, "profession.171", "Horde", {
            "forever.1458.profession.171", 0.47530528903008, 0.71569108963013,
        })
        Data:RegisterGroup(1458, "profession.182", "Horde", {
            "forever.1458.profession.182", 0.54600626230240, 0.49969407916069,
        })
        Data:RegisterGroup(1458, "profession.185", "Horde", {
            "forever.1458.profession.185", 0.62385404109955, 0.43992388248444,
        })
        Data:RegisterGroup(1458, "profession.186", "Horde", {
            "forever.1458.profession.186", 0.56036996841431, 0.36723071336746,
        })
        Data:RegisterGroup(1458, "profession.197", "Horde", {
            "forever.1458.profession.197", 0.70897120237350, 0.29432123899460,
        })
        Data:RegisterGroup(1458, "profession.202", "Horde", {
            "forever.1458.profession.202", 0.76066344976425, 0.73325085639954,
        })
        Data:RegisterGroup(1458, "profession.333", "Horde", {
            "forever.1458.profession.333", 0.61965298652649, 0.60791110992432,
        })
        Data:RegisterGroup(1458, "profession.356", "Horde", {
            "forever.1458.profession.356", 0.81737464666367, 0.30939656496048,
        })
        Data:RegisterGroup(1458, "profession.393", "Horde", {
            "forever.1458.profession.393", 0.70538246631622, 0.59261727333069,
        })
        Data:RegisterGroup(1458, "service.auction", "Horde", {
            "forever.1458.service.auction", 0.65980702638626, 0.35562324523926,
        })
        Data:RegisterGroup(1458, "service.bank", "Horde", {
            "forever.1458.service.bank", 0.66787022352219, 0.44103172421455,
        })
        Data:RegisterGroup(1458, "service.guild", "Horde", {
            "forever.1458.service.guild", 0.69589120149612, 0.44332832098007,
        })
        Data:RegisterGroup(1458, "service.inn", "Horde", {
            "forever.1458.service.inn", 0.67981296777725, 0.37262147665024,
        })
        Data:RegisterGroup(1458, "service.stable", "Horde", {
            "forever.1458.service.stable", 0.67379891872406, 0.38082450628281,
        })
        Data:RegisterGroup(1458, "service.barber", "Horde", {
            "map1458.point.046", 0.7103, 0.4727,
        })
        Data:RegisterGroup(1458, "collection.reagents", "Horde", {
            "map1458.point.047", 0.6944, 0.3897,
        })
        Data:RegisterGroup(1458, "trainer.portal", "Horde", {
            "forever.1458.trainer.portal", 0.85491311550140, 0.15131458640099,
        })
        Data:RegisterGroup(1458, "trainer.MAGE", "Horde", {
            "forever.1458.trainer.MAGE", 0.85491311550140, 0.15131458640099,
        })
        Data:RegisterGroup(1458, "trainer.PALADIN", "Horde", {
            "forever.1458.trainer.PALADIN", 0.47390347719193, 0.14920592308044,
        })
        Data:RegisterGroup(1458, "trainer.PRIEST", "Horde", {
            "forever.1458.trainer.PRIEST", 0.49165907502174, 0.18685592710972,
        })
        Data:RegisterGroup(1458, "trainer.ROGUE", "Horde", {
            "forever.1458.trainer.ROGUE", 0.84239083528519, 0.71767300367355,
        })
        Data:RegisterGroup(1458, "trainer.WARLOCK", "Horde", {
            "forever.1458.trainer.WARLOCK", 0.85474693775177, 0.15157897770405,
        })
        Data:RegisterGroup(1458, "trainer.WARRIOR", "Horde", {
            "forever.1458.trainer.WARRIOR", 0.47426649928093, 0.15989126265049,
        })
        do
            local map = { mapID = 1456, nameKey = "map.forever.1456", order = 90 }
            self.maps[#self.maps + 1], self.mapByID[1456] = map, map
        end
        do
            local map = { mapID = 1412, nameKey = "map.forever.1412", order = 100 }
            self.maps[#self.maps + 1], self.mapByID[1412] = map, map
        end
        Data:RegisterGroup(1412, "trainer.WARRIOR", "Horde", {
            "forever.1412.trainer.WARRIOR", 0.48313280940056, 0.63677543401718,
        })
        Data:RegisterGroup(1412, "trainer.DRUID", "Horde", {
            "forever.1412.trainer.DRUID", 0.47494027018547, 0.62866276502609,
        })
        Data:RegisterGroup(1412, "trainer.SHAMAN", "Horde", {
            "forever.1412.trainer.SHAMAN", 0.47431901097298, 0.62606406211853,
        })
        Data:RegisterGroup(1412, "trainer.HUNTER", "Horde", {
            "forever.1412.trainer.HUNTER", 0.46883878111839, 0.59599393606186,
        })
        Data:RegisterGroup(1456, "trainer.PALADIN", "Horde", {
            "forever.1456.trainer.PALADIN", 0.25194650888443, 0.14396764338017,
        })
        Data:RegisterGroup(1456, "profession.164", "Horde", {
            "forever.1456.profession.164", 0.39451846480370, 0.56012189388275,
        })
        RegisterWeaponTrainerSite("thunder_bluff")
        Data:RegisterGroup(1456, "profession.356", "Horde", {
            "forever.1456.profession.356", 0.56100124120712, 0.45896184444427,
        })
        Data:RegisterGroup(1456, "service.stable", "Horde", {
            "forever.1456.service.stable", 0.44821172952652, 0.60388356447220,
        })
        Data:RegisterGroup(1456, "profession.171", "Horde", {
            "forever.1456.profession.171", 0.46886104345322, 0.33854365348816,
        })
        Data:RegisterGroup(1456, "trainer.SHAMAN", "Horde", {
            "forever.1456.trainer.SHAMAN", 0.22841814160347, 0.20053797960281,
        })
        Data:RegisterGroup(1456, "trainer.WARRIOR", "Horde", {
            "forever.1456.trainer.WARRIOR", 0.60450434684753, 0.81389093399048,
        })
        Data:RegisterGroup(1456, "trainer.HUNTER", "Horde", {
            "forever.1456.trainer.HUNTER", 0.60450434684753, 0.81389093399048,
        })
        Data:RegisterGroup(1456, "profession.186", "Horde", {
            "forever.1456.profession.186", 0.34648030996323, 0.57365977764130,
        })
        Data:RegisterGroup(1456, "profession.129", "Horde", {
            "forever.1456.profession.129", 0.30290994048119, 0.21066302061081,
        })
        Data:RegisterGroup(1456, "profession.182", "Horde", {
            "forever.1456.profession.182", 0.49646422266960, 0.41347694396973,
        })
        Data:RegisterGroup(1456, "profession.393", "Horde", {
            "forever.1456.profession.393", 0.44597151875496, 0.42908480763435,
        })
        Data:RegisterGroup(1456, "trainer.DRUID", "Horde", {
            "forever.1456.trainer.DRUID", 0.76813542842865, 0.29386362433434,
        })
        Data:RegisterGroup(1456, "profession.185", "Horde", {
            "forever.1456.profession.185", 0.51535248756409, 0.52383315563202,
        })
        Data:RegisterGroup(1456, "profession.333", "Horde", {
            "forever.1456.profession.333", 0.44877073168755, 0.37746348977089,
        })
        Data:RegisterGroup(1456, "service.guild", "Horde", {
            "forever.1456.service.guild", 0.37277844548225, 0.64167702198029,
        })
        Data:RegisterGroup(1456, "service.auction", "Horde", {
            "forever.1456.service.auction", 0.39723357558250, 0.50058209896088,
        })
        Data:RegisterGroup(1456, "service.inn", "Horde", {
            "forever.1456.service.inn", 0.45696657896042, 0.64106124639511,
        })
        Data:RegisterGroup(1456, "service.bank", "Horde", {
            "forever.1456.service.bank", 0.47187879681587, 0.58606076240540,
        })
        Data:RegisterGroup(1456, "profession.165", "Horde", {
            "forever.1456.profession.165", 0.43094581365585, 0.44009247422218,
        })
        Data:RegisterGroup(1456, "profession.197", "Horde", {
            "forever.1456.profession.197", 0.43094581365585, 0.44009247422218,
        })
        Data:RegisterGroup(1456, "trainer.MAGE", "Horde", {
            "forever.1456.trainer.MAGE", 0.30769926309586, 0.30353683233261,
        })
        Data:RegisterGroup(1456, "trainer.PRIEST", "Horde", {
            "forever.1456.trainer.PRIEST", 0.30769926309586, 0.30353683233261,
        })
        Data:RegisterGroup(1412, "service.inn", "Horde", {
            "map1412.point.041", 0.46060000000000, 0.64170000000000,
        })
        Data:RegisterGroup(1412, "profession.129", "Horde", {
            "map1412.point.041.profession.129", 0.46060000000000, 0.64170000000000,
        })
        Data:RegisterGroup(1412, "service.stable", "Horde", {
            "map1412.point.042", 0.46540000000000, 0.63370000000000,
        })
        Data:RegisterGroup(1412, "profession.185", "Horde", {
            "map1412.point.043", 0.45030000000000, 0.61650000000000,
        })
        Data:RegisterGroup(1412, "profession.393", "Horde", {
            "map1412.point.044", 0.45200000000000, 0.61300000000000,
        })
        Data:RegisterGroup(1420, "trainer.PALADIN", "Horde", {
            "forever.1420.trainer.PALADIN", 0.60271096229553, 0.52543067932129,
        })
        Data:RegisterGroup(1420, "profession.356", "Horde", {
            "forever.1420.profession.356", 0.67101955413818, 0.51040017604828,
        })
        Data:RegisterGroup(1420, "profession.393", "Horde", {
            "forever.1420.profession.393", 0.65537476539612, 0.59955883026123,
        })
        Data:RegisterGroup(1420, "trainer.MAGE", "Horde", {
            "forever.1420.trainer.MAGE", 0.61908054351807, 0.52379119396210,
        })
        Data:RegisterGroup(1420, "profession.197", "Horde", {
            "forever.1420.profession.197", 0.52562385797501, 0.55628281831741,
        })
        Data:RegisterGroup(1420, "profession.171", "Horde", {
            "forever.1420.profession.171", 0.59509313106537, 0.52205473184586,
        })
        Data:RegisterGroup(1420, "trainer.WARRIOR", "Horde", {
            "forever.1420.trainer.WARRIOR", 0.61805766820908, 0.52431869506836,
        })
        Data:RegisterGroup(1420, "profession.129", "Horde", {
            "forever.1420.profession.129", 0.61754828691483, 0.52796393632889,
        })
        Data:RegisterGroup(1420, "service.inn", "Horde", {
            "forever.1420.service.inn", 0.61755573749542, 0.52133458852768,
        })
        Data:RegisterGroup(1420, "profession.182", "Horde", {
            "forever.1420.profession.182", 0.59825456142426, 0.52014273405075,
        })
        Data:RegisterGroup(1420, "profession.165", "Horde", {
            "forever.1420.profession.165", 0.65354865789413, 0.60072702169418,
        })
        Data:RegisterGroup(1420, "profession.333", "Horde", {
            "forever.1420.profession.333", 0.61712205410004, 0.51678395271301,
        })
        Data:RegisterGroup(1420, "service.stable", "Horde", {
            "forever.1420.service.stable", 0.60070985555649, 0.52077370882034,
        })
        Data:RegisterGroup(1420, "trainer.ROGUE", "Horde", {
            "forever.1420.trainer.ROGUE", 0.61729711294174, 0.52112561464310,
        })
        Data:RegisterGroup(1420, "trainer.WARLOCK", "Horde", {
            "forever.1420.trainer.WARLOCK", 0.61652731895447, 0.52449464797974,
        })
        Data:RegisterGroup(1420, "trainer.PRIEST", "Horde", {
            "forever.1420.trainer.PRIEST", 0.61635971069336, 0.52218145132065,
        })
        -- 杜隆塔尔部落卫兵问路采集，保留原始坐标。
        Data:RegisterGroup(1411, "profession.186", "Horde", {
            "forever.1411.profession.186", 0.51869350671768, 0.40890559554100,
        })
        Data:RegisterGroup(1411, "service.inn", "Horde", {
            "forever.1411.service.inn", 0.51562577486038, 0.41691440343857,
        })
        Data:RegisterGroup(1411, "profession.356", "Horde", {
            "forever.1411.profession.356", 0.53237473964691, 0.81526905298233,
        })
        Data:RegisterGroup(1411, "trainer.ROGUE", "Horde", {
            "forever.1411.trainer.ROGUE", 0.51943439245224, 0.43760800361633,
        })
        Data:RegisterGroup(1411, "trainer.WARRIOR", "Horde", {
            "forever.1411.trainer.WARRIOR", 0.54130697250366, 0.42440423369408,
        })
        Data:RegisterGroup(1411, "trainer.MAGE", "Horde", {
            "forever.1411.trainer.MAGE", 0.56229019165039, 0.75111031532288,
        })
        Data:RegisterGroup(1411, "profession.129", "Horde", {
            "forever.1411.profession.129", 0.54148870706558, 0.42018660902977,
        })
        Data:RegisterGroup(1411, "trainer.SHAMAN", "Horde", {
            "forever.1411.trainer.SHAMAN", 0.54363507032394, 0.42568400502205,
        })
        Data:RegisterGroup(1411, "profession.164", "Horde", {
            "forever.1411.profession.164", 0.52084153890610, 0.40711599588394,
        })
        Data:RegisterGroup(1411, "trainer.WARLOCK", "Horde", {
            "forever.1411.trainer.WARLOCK", 0.54353880882263, 0.41204339265823,
        })
        Data:RegisterGroup(1411, "trainer.PRIEST", "Horde", {
            "forever.1411.trainer.PRIEST", 0.54195910692215, 0.42896699905396,
        })
        Data:RegisterGroup(1411, "profession.202", "Horde", {
            "forever.1411.profession.202", 0.52226191759109, 0.40833270549774,
        })
        Data:RegisterGroup(1411, "profession.182", "Horde", {
            "forever.1411.profession.182", 0.55496954917908, 0.75023746490479,
        })
        Data:RegisterGroup(1411, "profession.171", "Horde", {
            "forever.1411.profession.171", 0.55448544025421, 0.74002426862717,
        })
        Data:RegisterGroup(1411, "trainer.HUNTER", "Horde", {
            "forever.1411.trainer.HUNTER", 0.51900380849838, 0.43468508124352,
        })
        Data:RegisterGroup(1411, "service.stable", "Horde", {
            "forever.1411.service.stable", 0.51974886655807, 0.41929638385773,
        })
        return
    end
    -- 此后仅实例化联盟服务；公共交通已在上方注册。
    Data:RegisterGroup(1453, "trainer.PALADIN", "Alliance", {
        "forever.1453.001", 0.54430466890335, 0.54029917716980,
    })
    Data:RegisterGroup(1453, "trainer.PRIEST", "Alliance", {
        "forever.1453.001.trainer.PRIEST", 0.54430466890335, 0.54029917716980,
    })
    Data:RegisterGroup(1453, "profession.202", "Alliance", {
        "forever.1453.002", 0.62302553653717, 0.30439308285713,
    })
    Data:RegisterGroup(1453, "profession.186", "Alliance", {
        "forever.1453.003", 0.60438984632492, 0.36293369531631,
    })
    Data:RegisterGroup(1453, "trainer.MAGE", "Alliance", {
        "forever.1453.004", 0.49825936555862, 0.87428617477417,
    })
    Data:RegisterGroup(1453, "trainer.WARLOCK", "Alliance", {
        "forever.1453.005", 0.42361143231392, 0.81387275457382,
    })
    Data:RegisterGroup(1453, "profession.393", "Alliance", {
        "forever.1453.006", 0.72568678855896, 0.61431902647018,
    })
    Data:RegisterGroup(1453, "profession.165", "Alliance", {
        "forever.1453.006.profession.165", 0.72568678855896, 0.61431902647018,
    })
    Data:RegisterGroup(1453, "trainer.ROGUE", "Alliance", {
        "forever.1453.007", 0.78838509321213, 0.67883443832397,
    })
    Data:RegisterGroup(1453, "trainer.WARRIOR", "Alliance", {
        "forever.1453.008", 0.79433453083038, 0.62072491645813,
    })
    Data:RegisterGroup(1453, "profession.171", "Alliance", {
        "forever.1453.009", 0.54333984851837, 0.84558224678040,
    })
    Data:RegisterGroup(1453, "profession.182", "Alliance", {
        "forever.1453.009.profession.182", 0.54333984851837, 0.84558224678040,
    })
    Data:RegisterGroup(1453, "trainer.HUNTER", "Alliance", {
        "forever.1453.010", 0.66938120126724, 0.37505358457565,
    })
    Data:RegisterGroup(1453, "profession.185", "Alliance", {
        "forever.1453.011", 0.74786537885666, 0.55718517303467,
    })
    Data:RegisterGroup(1453, "profession.129", "Alliance", {
        "forever.1453.012", 0.52858269214630, 0.44861695170403,
    })
    Data:RegisterGroup(1453, "profession.164", "Alliance", {
        "forever.1453.013", 0.64029192924500, 0.37766063213348,
    })
    Data:RegisterGroup(1453, "trainer.DRUID", "Alliance", {
        "forever.1453.014", 0.37245470285416, 0.65081149339676,
    })
    Data:RegisterGroup(1453, "profession.197", "Alliance", {
        "forever.1453.015", 0.54766762256622, 0.81560671329498,
    })
    Data:RegisterGroup(1453, "profession.356", "Alliance", {
        "forever.1453.016", 0.56462246179581, 0.68834853172302,
    })
    Data:RegisterGroup(1453, "profession.333", "Alliance", {
        "forever.1453.017", 0.54133534431458, 0.72732609510422,
    })
    Data:RegisterGroup(1453, "service.bank", "Alliance", {
        "forever.1453.018", 0.62323200702667, 0.76796156167984,
    })
    Data:RegisterGroup(1453, "service.auction", "Alliance", {
        "forever.1453.019", 0.60809451341629, 0.70509684085846,
    })
    Data:RegisterGroup(1453, "service.inn", "Alliance", {
        "forever.1453.020", 0.60390442609787, 0.75264656543732,
    })
    Data:RegisterGroup(1453, "travel.flight", "Alliance", {
        "forever.1453.023", 0.71614134311676, 0.72253340482712, 2,
    })
    RegisterWeaponTrainerSite("stormwind")
    Data:RegisterGroup(1453, "service.guild", "Alliance", {
        "forever.1453.service.guild", 0.64894264936447, 0.76883459091187,
    })
    Data:RegisterGroup(1453, "service.stable", "Alliance", {
        "forever.1453.service.stable", 0.67211383581161, 0.37729835510254,
    })
    Data:RegisterGroup(1453, "service.barber", "Alliance", {
        "forever.1453.service.barber", 0.61417317390442, 0.66083395481110,
    })
    Data:RegisterGroup(1453, "service.transmogrifier", "Alliance", {
        "forever.1453.service.transmogrifier", 0.48211717605591, 0.84707474708557,
    })
    Data:RegisterGroup(1455, "service.stable", "Alliance", {
        "forever.1455.service.stable", 0.69367599487305, 0.83579528331757,
    })
    Data:RegisterGroup(1455, "profession.164", "Alliance", {
        "forever.1455.profession.164", 0.50160151720047, 0.43164741992950,
    })
    Data:RegisterGroup(1455, "profession.202", "Alliance", {
        "forever.1455.profession.202", 0.67876487970352, 0.43654131889343,
    })
    Data:RegisterGroup(1455, "profession.356", "Alliance", {
        "forever.1455.profession.356", 0.47853028774261, 0.05434165894985,
    })
    Data:RegisterGroup(1455, "trainer.WARRIOR", "Alliance", {
        "forever.1455.trainer.WARRIOR", 0.68311691284180, 0.86018782854080,
    })
    Data:RegisterGroup(1455, "trainer.HUNTER", "Alliance", {
        "forever.1455.trainer.HUNTER", 0.68311691284180, 0.86018782854080,
    })
    RegisterWeaponTrainerSite("ironforge")
    Data:RegisterGroup(1455, "profession.186", "Alliance", {
        "forever.1455.profession.186", 0.50952011346817, 0.25742962956429,
    })
    Data:RegisterGroup(1455, "profession.165", "Alliance", {
        "forever.1455.profession.165", 0.39714142680168, 0.33314687013626,
    })
    Data:RegisterGroup(1455, "profession.393", "Alliance", {
        "forever.1455.profession.393", 0.39714142680168, 0.33314687013626,
    })
    Data:RegisterGroup(1455, "service.inn", "Alliance", {
        "forever.1455.service.inn", 0.20108111202717, 0.53305089473724,
    })
    Data:RegisterGroup(1455, "profession.197", "Alliance", {
        "forever.1455.profession.197", 0.43431439995766, 0.28500342369080,
    })
    Data:RegisterGroup(1455, "trainer.PALADIN", "Alliance", {
        "forever.1455.trainer.PALADIN", 0.26924127340317, 0.10951310396194,
    })
    Data:RegisterGroup(1455, "trainer.MAGE", "Alliance", {
        "forever.1455.trainer.MAGE", 0.26924127340317, 0.10951310396194,
    })
    Data:RegisterGroup(1455, "trainer.PRIEST", "Alliance", {
        "forever.1455.trainer.PRIEST", 0.26924127340317, 0.10951310396194,
    })
    Data:RegisterGroup(1455, "profession.171", "Alliance", {
        "forever.1455.profession.171", 0.66814213991165, 0.54825216531754,
    })
    Data:RegisterGroup(1455, "profession.333", "Alliance", {
        "forever.1455.profession.333", 0.61083024740219, 0.44442558288574,
    })
    Data:RegisterGroup(1455, "trainer.SHAMAN", "Alliance", {
        "forever.1455.trainer.SHAMAN", 0.47161209583282, 0.13858740031719,
    })
    Data:RegisterGroup(1455, "profession.129", "Alliance", {
        "forever.1455.profession.129", 0.55593860149384, 0.59203195571899,
    })
    Data:RegisterGroup(1455, "profession.182", "Alliance", {
        "forever.1455.profession.182", 0.55593860149384, 0.59203195571899,
    })
    Data:RegisterGroup(1455, "service.auction", "Alliance", {
        "forever.1455.service.auction", 0.25045046210289, 0.73568290472031,
    })
    Data:RegisterGroup(1455, "trainer.WARLOCK", "Alliance", {
        "forever.1455.trainer.WARLOCK", 0.50196772813797, 0.06783296167850,
    })
    Data:RegisterGroup(1455, "trainer.ROGUE", "Alliance", {
        "forever.1455.trainer.ROGUE", 0.51909464597702, 0.14895574748516,
    })
    Data:RegisterGroup(1455, "service.guild", "Alliance", {
        "forever.1455.service.guild", 0.35777121782303, 0.85635966062546,
    })
    Data:RegisterGroup(1455, "profession.185", "Alliance", {
        "forever.1455.profession.185", 0.59574133157730, 0.37639909982681,
    })
    Data:RegisterGroup(1455, "service.bank", "Alliance", {
        "forever.1455.service.bank", 0.35148194432259, 0.61157566308975,
    })
    Data:RegisterGroup(1437, "profession.356", "Alliance", {
        "map1437.point.026", 0.0829, 0.5867,
    })
    Data:RegisterGroup(1424, "profession.356", "Alliance", {
        "map1424.point.029", 0.5055, 0.6388,
    })
    Data:RegisterGroup(1424, "service.stable", "Alliance", {
        "map1424.point.030", 0.5034, 0.5876,
    })
    Data:RegisterGroup(1424, "service.inn", "Alliance", {
        "map1424.point.031", 0.5103, 0.5859,
    })
    RegisterWeaponTrainerSite("darnassus")
    Data:RegisterGroup(1457, "trainer.WARRIOR", "Alliance", {
        "forever.1457.trainer.WARRIOR", 0.62170571088791, 0.40583151578903,
    })
    Data:RegisterGroup(1457, "trainer.PRIEST", "Alliance", {
        "forever.1457.trainer.PRIEST", 0.39068394899368, 0.82069295644760,
    })
    Data:RegisterGroup(1457, "service.guild", "Alliance", {
        "forever.1457.service.guild", 0.69805389642715, 0.22943356633186,
    })
    Data:RegisterGroup(1457, "profession.165", "Alliance", {
        "forever.1457.profession.165", 0.64496994018555, 0.21498116850853,
    })
    Data:RegisterGroup(1457, "profession.393", "Alliance", {
        "forever.1457.profession.393", 0.64362901449203, 0.22234930098057,
    })
    Data:RegisterGroup(1457, "trainer.DRUID", "Alliance", {
        "forever.1457.trainer.DRUID", 0.34761658310890, 0.07413093745709,
    })
    Data:RegisterGroup(1457, "profession.129", "Alliance", {
        "forever.1457.profession.129", 0.51772433519363, 0.12500543892384,
    })
    Data:RegisterGroup(1457, "service.auction", "Alliance", {
        "forever.1457.service.auction", 0.56614923477173, 0.53270798921585,
    })
    Data:RegisterGroup(1457, "service.inn", "Alliance", {
        "forever.1457.service.inn", 0.67638754844666, 0.14880889654160,
    })
    Data:RegisterGroup(1457, "trainer.ROGUE", "Alliance", {
        "forever.1457.trainer.ROGUE", 0.32053679227829, 0.16481737792492,
    })
    Data:RegisterGroup(1457, "profession.171", "Alliance", {
        "forever.1457.profession.171", 0.54954612255096, 0.23014220595360,
    })
    Data:RegisterGroup(1457, "profession.185", "Alliance", {
        "forever.1457.profession.185", 0.49052849411964, 0.21214871108532,
    })
    Data:RegisterGroup(1457, "trainer.HUNTER", "Alliance", {
        "forever.1457.trainer.HUNTER", 0.40371400117874, 0.08646157383919,
    })
    Data:RegisterGroup(1457, "profession.182", "Alliance", {
        "forever.1457.profession.182", 0.48018237948418, 0.68175727128983,
    })
    Data:RegisterGroup(1457, "profession.197", "Alliance", {
        "forever.1457.profession.197", 0.63322693109512, 0.22475700080395,
    })
    Data:RegisterGroup(1457, "profession.356", "Alliance", {
        "forever.1457.profession.356", 0.47828394174576, 0.56977659463882,
    })
    Data:RegisterGroup(1457, "service.bank", "Alliance", {
        "forever.1457.service.bank", 0.40253263711929, 0.42489004135132,
    })
    Data:RegisterGroup(1457, "profession.333", "Alliance", {
        "forever.1457.profession.333", 0.59048908948898, 0.13067243993282,
    })
    Data:RegisterGroup(1457, "service.stable", "Alliance", {
        "forever.1457.service.stable", 0.39278134703636, 0.10077307373285,
    })
    Data:RegisterGroup(1457, "trainer.portal", "Alliance", {
        "map1457.point.037", 0.4060, 0.8216,
    })
    Data:RegisterGroup(1453, "trainer.portal", "Alliance", {
        "forever.1453.trainer.portal", 0.49825936555862, 0.87428617477417,
    })
    Data:RegisterGroup(1455, "trainer.portal", "Alliance", {
        "forever.1455.trainer.portal", 0.26924127340317, 0.10951310396194,
    })
    Data:RegisterGroup(1455, "service.barber", "Alliance", {
        "map1455.point.040", 0.2547, 0.5145,
    })
    -- 联盟卫兵问路采集：丹莫罗；只录入原生地图坐标，排除大陆投影。
    local dunMorogh = { mapID = 1426, nameKey = "map.forever.1426", order = 35 }
    self.maps[#self.maps + 1] = dunMorogh
    self.mapByID[1426] = dunMorogh
    Data:RegisterGroup(1426, "service.stable", "Alliance", {
        "forever.1426.service.stable", 0.47006949782372, 0.52662557363510,
    })
    Data:RegisterGroup(1426, "trainer.PALADIN", "Alliance", {
        "forever.1426.trainer.PALADIN", 0.47605612874031, 0.52008336782455,
    })
    Data:RegisterGroup(1426, "profession.129", "Alliance", {
        "forever.1426.profession.129", 0.47169980406761, 0.52623575925827,
    })
    Data:RegisterGroup(1426, "trainer.WARRIOR", "Alliance", {
        "forever.1426.trainer.WARRIOR", 0.47354868054390, 0.52627241611481,
    })
    Data:RegisterGroup(1426, "service.inn", "Alliance", {
        "forever.1426.service.inn", 0.46963366866112, 0.51990658044815,
    })
    Data:RegisterGroup(1426, "trainer.WARLOCK", "Alliance", {
        "forever.1426.trainer.WARLOCK", 0.47321555018425, 0.53677684068680,
    })
    Data:RegisterGroup(1426, "trainer.MAGE", "Alliance", {
        "forever.1426.trainer.MAGE", 0.47535452246666, 0.52089959383011,
    })
    Data:RegisterGroup(1426, "trainer.ROGUE", "Alliance", {
        "forever.1426.trainer.ROGUE", 0.47556835412979, 0.52611094713211,
    })
    Data:RegisterGroup(1426, "profession.185", "Alliance", {
        "forever.1426.profession.185", 0.47647830843925, 0.52305907011032,
    })
    Data:RegisterGroup(1426, "trainer.PRIEST", "Alliance", {
        "forever.1426.trainer.PRIEST", 0.47357764840126, 0.52145385742188,
    })
    Data:RegisterGroup(1426, "trainer.HUNTER", "Alliance", {
        "forever.1426.trainer.HUNTER", 0.45803141593933, 0.53045111894608,
    })
    Data:RegisterGroup(1426, "trainer.SHAMAN", "Alliance", {
        "forever.1426.trainer.SHAMAN", 0.47585082054138, 0.51952916383743,
    })
    Data:RegisterGroup(1426, "profession.186", "Alliance", {
        "forever.1426.profession.186", 0.50010073184967, 0.50315862894058,
    })
    Data:RegisterGroup(1426, "profession.356", "Alliance", {
        "forever.1426.profession.356", 0.35506969690323, 0.40248030424118,
    })
    Data:RegisterGroup(1426, "profession.164", "Alliance", {
        "forever.1426.profession.164", 0.45330446958542, 0.51931571960449,
    })
    -- 艾尔文森林卫兵问路：排除城内服务的外部地图投影。
    local elwynn = { mapID = 1429, nameKey = "map.forever.1429", order = 25 }
    self.maps[#self.maps + 1] = elwynn
    self.mapByID[1429] = elwynn
    Data:RegisterGroup(1429, "profession.185", "Alliance", {
        "forever.1429.profession.185", 0.44328933954239, 0.66014379262924,
    })
    Data:RegisterGroup(1429, "trainer.PRIEST", "Alliance", {
        "forever.1429.trainer.PRIEST", 0.43287038803101, 0.65734827518463,
    })
    Data:RegisterGroup(1429, "trainer.PALADIN", "Alliance", {
        "forever.1429.trainer.PALADIN", 0.41124540567398, 0.66077464818954,
    })
    Data:RegisterGroup(1429, "trainer.MAGE", "Alliance", {
        "forever.1429.trainer.MAGE", 0.43274101614952, 0.66169017553329,
    })
    Data:RegisterGroup(1429, "service.stable", "Alliance", {
        "forever.1429.service.stable", 0.42916062474251, 0.65974617004395,
    })
    Data:RegisterGroup(1429, "profession.356", "Alliance", {
        "forever.1429.profession.356", 0.47658455371857, 0.62515199184418,
    })
    Data:RegisterGroup(1429, "profession.393", "Alliance", {
        "forever.1429.profession.393", 0.46257734298706, 0.62281090021133,
    })
    Data:RegisterGroup(1429, "profession.171", "Alliance", {
        "forever.1429.profession.171", 0.39811170101166, 0.48278933763504,
    })
    Data:RegisterGroup(1429, "service.inn", "Alliance", {
        "forever.1429.service.inn", 0.43025293946266, 0.65660494565964,
    })
    Data:RegisterGroup(1429, "trainer.WARLOCK", "Alliance", {
        "forever.1429.trainer.WARLOCK", 0.44355350732803, 0.66259723901749,
    })
    Data:RegisterGroup(1429, "trainer.ROGUE", "Alliance", {
        "forever.1429.trainer.ROGUE", 0.43854713439941, 0.65910679101944,
    })
    Data:RegisterGroup(1429, "profession.129", "Alliance", {
        "forever.1429.profession.129", 0.43359091877937, 0.65551239252090,
    })
    Data:RegisterGroup(1429, "profession.197", "Alliance", {
        "forever.1429.profession.197", 0.79179131984711, 0.69011861085892,
    })
    Data:RegisterGroup(1429, "profession.165", "Alliance", {
        "forever.1429.profession.165", 0.46405169367790, 0.62064629793167,
    })
    Data:RegisterGroup(1429, "profession.182", "Alliance", {
        "forever.1429.profession.182", 0.39937931299210, 0.48437502980232,
    })
    Data:RegisterGroup(1429, "trainer.WARRIOR", "Alliance", {
        "forever.1429.trainer.WARRIOR", 0.41082650423050, 0.65767216682434,
    })
    Data:RegisterGroup(1429, "profession.164", "Alliance", {
        "forever.1429.profession.164", 0.41705092787743, 0.65541267395020,
    })
    -- 泰达希尔联盟卫兵问路采集；保留原始区域坐标。
    Data:RegisterGroup(1438, "trainer.WARRIOR", "Alliance", {
        "forever.1438.trainer.WARRIOR", 0.56248158216476, 0.59205365180969,
    })
    Data:RegisterGroup(1438, "trainer.PRIEST", "Alliance", {
        "forever.1438.trainer.PRIEST", 0.55540668964386, 0.56724584102631,
    })
    Data:RegisterGroup(1438, "trainer.DRUID", "Alliance", {
        "forever.1438.trainer.DRUID", 0.55991059541702, 0.61574161052704,
    })
    Data:RegisterGroup(1438, "profession.171", "Alliance", {
        "forever.1438.profession.171", 0.57658261060715, 0.60807454586029,
    })
    Data:RegisterGroup(1438, "profession.333", "Alliance", {
        "forever.1438.profession.333", 0.36687836050987, 0.33993482589722,
    })
    Data:RegisterGroup(1438, "profession.185", "Alliance", {
        "forever.1438.profession.185", 0.57121753692627, 0.61290943622589,
    })
    Data:RegisterGroup(1438, "profession.393", "Alliance", {
        "forever.1438.profession.393", 0.42057031393051, 0.49963977932930,
    })
    Data:RegisterGroup(1438, "profession.129", "Alliance", {
        "forever.1438.profession.129", 0.55295979976654, 0.56814205646515,
    })
    Data:RegisterGroup(1438, "profession.182", "Alliance", {
        "forever.1438.profession.182", 0.57715857028961, 0.60625326633453,
    })
    Data:RegisterGroup(1438, "service.stable", "Alliance", {
        "forever.1438.service.stable", 0.56631302833557, 0.59606081247330,
    })
    Data:RegisterGroup(1438, "profession.165", "Alliance", {
        "forever.1438.profession.165", 0.41894191503525, 0.49463081359863,
    })
    Data:RegisterGroup(1438, "trainer.ROGUE", "Alliance", {
        "forever.1438.trainer.ROGUE", 0.56400352716446, 0.60176265239716,
    })
    Data:RegisterGroup(1438, "trainer.HUNTER", "Alliance", {
        "forever.1438.trainer.HUNTER", 0.56726032495499, 0.59407186508179,
    })
    Data:RegisterGroup(1438, "service.inn", "Alliance", {
        "forever.1438.service.inn", 0.56061106920242, 0.59219539165497,
    })
    Data:RegisterGroup(1455, "collection.reagents", "Alliance", {
        "map1455.point.060", 0.3115, 0.2689,
    })
    Data:RegisterGroup(1453, "collection.reagents", "Alliance", {
        "map1453.point.061", 0.6413, 0.7436,
    })
end

Data:LoadPlayerFactionPoints()
if not Data.foreverFactionLoaded and YUI.Event then
    YUI.Event:Once("PLAYER_LOGIN", function() Data:LoadPlayerFactionPoints() end, Data)
end
