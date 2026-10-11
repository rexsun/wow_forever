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

if not YUI.IsRetail then return end


-- 首批采集范围。points 只接受 YUI 自主采集并复核的数据。
Data.maps = {
    { mapID = 2393, nameKey = "map.silvermoon", order = 10 },
    { mapID = 2339, nameKey = "map.dornogal", order = 20 },
    { mapID = 2472, nameKey = "map.tazavesh", order = 30 },
    { mapID = 2112, nameKey = "map.valdrakken", order = 40 },
    { mapID = 627, nameKey = "map.dalaran_legion", order = 50 },
    { mapID = 628, nameKey = "map.dalaran_sewers", order = 60, parentMapID = 627 },
    { mapID = 85, nameKey = "map.orgrimmar", order = 70 },
    { mapID = 86, nameKey = "map.orgrimmar_cleft", order = 75, parentMapID = 85 },
    { mapID = 84, nameKey = "map.stormwind", order = 80 },
    { mapID = 499, nameKey = "map.deeprun_tram", order = 85, parentMapID = 84 },
}

Data.mapByID = {}
-- 正式服按预设区域切换远景/详细文字，不参与 Forever 的距离聚合。
Data.zoomRules = {}
for _, mapID in ipairs({2393, 2339, 2472, 2112, 627, 85, 84}) do
    Data.zoomRules[mapID] = {compactEnter = 0.30, detailEnter = 0.38}
end
Data.compactTextLabels = {
    ["equipment.item_upgrades"] = "poi.compact.equipment_upgrade",
    ["equipment.set_conversion"] = "poi.compact.set_conversion",
    ["profession.356"] = "poi.compact.fishing",
}
Data.detailTextPoints = {
    ["map2393.point.024"] = true,
    ["map2339.point.048"] = true,
    ["map84.point.214"] = true,
}
-- 同地点拆分出的服务保留独立筛选和导航身份，仅在文字中分行显示。
Data.textBundles = {
    [2393] = {{"map2393.point.004", "map2393.point.004.profession.185"}},
    [2339] = {{"map2339.point.032", "map2339.point.032.profession.185"}},
    [2112] = {{"map2112.point.076", "map2112.point.076.profession.185"}},
    [85] = {{"map85.point.172", "map85.point.172.profession.755"}},
    [84] = {
        {"map84.point.193", "map84.point.193.profession.129"},
        {"map84.point.194", "map84.point.194.profession.202", "map84.point.194.profession.186"},
        {"map84.point.208", "map84.point.208.special.brawl"},
    },
}
Data.records = {}
Data:RegisterGroup(2393, "equipment.item_upgrades", nil, {
    "map2393.point.001", 0.4829, 0.6173,
})
Data:RegisterGroup(2393, "service.bank", nil, {
    "map2393.point.002", 0.5067, 0.6578,
})
Data:RegisterGroup(2393, "travel.portals", nil, {
    "map2393.point.003", 0.5268, 0.6453,
})
Data:RegisterGroup(2393, "service.inn", nil, {
    "map2393.point.004", 0.5607, 0.7042,
})
Data:RegisterGroup(2393, "profession.185", nil, {
    "map2393.point.004.profession.185", 0.5607, 0.7042,
})
Data:RegisterGroup(2393, "travel.timeways", nil, {
    "map2393.point.005", 0.4207, 0.5851,
})
Data:RegisterGroup(2393, "service.crafting_orders", nil, {
    "map2393.point.006", 0.4511, 0.5567,
})
Data:RegisterGroup(2393, "equipment.set_conversion", nil, {
    "map2393.point.007", 0.4024, 0.6518,
})
Data:RegisterGroup(2393, "travel.voidstorm", nil, {
    "map2393.point.009", 0.3523, 0.6608,
})
Data:RegisterGroup(2393, "travel.harai", nil, {
    "map2393.point.010", 0.3678, 0.6826,
})
Data:RegisterGroup(2393, "service.auction", nil, {
    "map2393.point.011", 0.5049, 0.7510,
})
Data:RegisterGroup(2393, "service.trading_post", nil, {
    "map2393.point.012", 0.4905, 0.7827,
})
Data:RegisterGroup(2393, "profession.202", nil, {
    "map2393.point.013", 0.4355, 0.5399,
})
Data:RegisterGroup(2393, "profession.164", nil, {
    "map2393.point.014", 0.4359, 0.5163,
})
Data:RegisterGroup(2393, "profession.773", nil, {
    "map2393.point.015", 0.4667, 0.5120,
})
Data:RegisterGroup(2393, "profession.171", nil, {
    "map2393.point.016", 0.4712, 0.5196,
})
Data:RegisterGroup(2393, "profession.333", nil, {
    "map2393.point.017", 0.4809, 0.5361,
})
Data:RegisterGroup(2393, "profession.197", nil, {
    "map2393.point.018", 0.4844, 0.5437,
})
Data:RegisterGroup(2393, "profession.755", nil, {
    "map2393.point.019", 0.4824, 0.5523,
})
Data:RegisterGroup(2393, "service.barber", nil, {
    "map2393.point.020", 0.4315, 0.7873,
})
Data:RegisterGroup(2393, "special.training_dummies", nil, {
    "map2393.point.021", 0.3627, 0.8456,
})
Data:RegisterGroup(2393, "special.delves", nil, {
    "map2393.point.022", 0.5218, 0.7777,
})
Data:RegisterGroup(2393, "collection.black_market", nil, {
    "map2393.point.023", 0.5216, 0.4834,
})
Data:RegisterGroup(2393, "service.rostrum_of_transformation", nil, {
    "map2393.point.024", 0.5229, 0.7368,
})
Data:RegisterGroup(2393, "service.stable", nil, {
    "map2393.point.053", 0.4644, 0.5555,
})
Data:RegisterGroup(2393, "profession.356", nil, {
    "map2393.point.054", 0.4503, 0.6035,
})
Data:RegisterGroup(2393, "profession.165", nil, {
    "map2393.point.056", 0.4306, 0.5577,
})
Data:RegisterGroup(2393, "profession.186", nil, {
    "map2393.point.057", 0.4281, 0.5277,
})
Data:RegisterGroup(2393, "profession.182", nil, {
    "map2393.point.058", 0.4840, 0.5147,
})
Data:RegisterGroup(2339, "travel.orgrimmar_portal", nil, {
    "map2339.point.026", 0.3845, 0.2744,
})
Data:RegisterGroup(2339, "travel.stormwind_portal", nil, {
    "map2339.point.027", 0.4109, 0.2396,
})
Data:RegisterGroup(2339, "travel.timeways", nil, {
    "map2339.point.028", 0.5374, 0.3896,
})
Data:RegisterGroup(2339, "profession.356", nil, {
    "map2339.point.029", 0.5000, 0.2686,
})
Data:RegisterGroup(2339, "equipment.item_upgrades", nil, {
    "map2339.point.030", 0.5131, 0.4177,
})
Data:RegisterGroup(2339, "service.bank", nil, {
    "map2339.point.031", 0.5232, 0.4516,
})
Data:RegisterGroup(2339, "service.inn", nil, {
    "map2339.point.032", 0.4533, 0.4753,
})
Data:RegisterGroup(2339, "profession.185", nil, {
    "map2339.point.032.profession.185", 0.4533, 0.4753,
})
Data:RegisterGroup(2339, "service.auction", nil, {
    "map2339.point.033", 0.5563, 0.4858,
})
Data:RegisterGroup(2339, "service.barber", nil, {
    "map2339.point.034", 0.5882, 0.5169,
})
Data:RegisterGroup(2339, "service.crafting_orders", nil, {
    "map2339.point.035", 0.5775, 0.5637,
})
Data:RegisterGroup(2339, "profession.165", nil, {
    "map2339.point.036", 0.5450, 0.5903,
})
Data:RegisterGroup(2339, "profession.197", nil, {
    "map2339.point.037", 0.5461, 0.6313,
})
Data:RegisterGroup(2339, "profession.202", nil, {
    "map2339.point.038", 0.4899, 0.5613,
})
Data:RegisterGroup(2339, "profession.164", nil, {
    "map2339.point.039", 0.4901, 0.6369,
})
Data:RegisterGroup(2339, "profession.333", nil, {
    "map2339.point.040", 0.5334, 0.7090,
})
Data:RegisterGroup(2339, "profession.755", nil, {
    "map2339.point.041", 0.5051, 0.7097,
})
Data:RegisterGroup(2339, "profession.773", nil, {
    "map2339.point.042", 0.4794, 0.7107,
})
Data:RegisterGroup(2339, "profession.171", nil, {
    "map2339.point.043", 0.4651, 0.7045,
})
Data:RegisterGroup(2339, "service.rostrum_of_transformation", nil, {
    "map2339.point.044", 0.4790, 0.6789,
})
Data:RegisterGroup(2339, "service.trading_post", nil, {
    "map2339.point.045", 0.4473, 0.5561,
})
Data:RegisterGroup(2339, "special.training_dummies", nil, {
    "map2339.point.046", 0.5925, 0.7531,
})
Data:RegisterGroup(2339, "travel.azj_kahet", nil, {
    "map2339.point.047", 0.6360, 0.5213,
})
Data:RegisterGroup(2339, "collection.black_market", nil, {
    "map2339.point.048", 0.6491, 0.5243,
})
Data:RegisterGroup(2339, "travel.siren_isle", nil, {
    "map2339.point.049", 0.7311, 0.0535,
})
Data:RegisterGroup(2339, "equipment.set_conversion", nil, {
    "map2339.point.050", 0.5000, 0.5349,
})
Data:RegisterGroup(2339, "travel.undermine", nil, {
    "map2339.point.051", 0.5254, 0.5028,
})
Data:RegisterGroup(2339, "service.stable", nil, {
    "map2339.point.052", 0.5532, 0.6746,
})
Data:RegisterGroup(2339, "profession.186", nil, {
    "map2339.point.059", 0.5310, 0.5264,
})
Data:RegisterGroup(2339, "profession.182", nil, {
    "map2339.point.060", 0.4550, 0.6933,
})
Data:RegisterGroup(2472, "special.phase_diving", nil, {
    "map2472.point.061", 0.4659, 0.5693,
})
Data:RegisterGroup(2472, "collection.toys_books", nil, {
    "map2472.point.062", 0.5273, 0.5395,
})
Data:RegisterGroup(2472, "collection.resource_market", nil, {
    "map2472.point.063", 0.5384, 0.5668,
})
Data:RegisterGroup(2472, "equipment.item_upgrades", nil, {
    "map2472.point.065", 0.4117, 0.2999,
})
Data:RegisterGroup(2472, "collection.renown", nil, {
    "map2472.point.066", 0.3909, 0.2864,
})
Data:RegisterGroup(2472, "service.inn", nil, {
    "map2472.point.067", 0.4128, 0.2496,
})
Data:RegisterGroup(2472, "profession.185", nil, {
    "map2472.point.068", 0.4596, 0.1826,
})
Data:RegisterGroup(2472, "travel.dornogal_portal", nil, {
    "map2472.point.069", 0.5001, 0.1947,
})
Data:RegisterGroup(2472, "service.stable", nil, {
    "map2472.point.070", 0.4720, 0.2624,
})
Data:RegisterGroup(2472, "special.ky_veza", nil, {
    "map2472.point.072", 0.3953, 0.5042,
})
Data:RegisterGroup(2112, "travel.orgrimmar_portal.poi_recorded_2112_073", nil, {
    "map2112.point.073", 0.5667, 0.3871,
})
Data:RegisterGroup(2112, "travel.stormwind_portal.poi_recorded_2112_074", nil, {
    "map2112.point.074", 0.5940, 0.4134,
})
Data:RegisterGroup(2112, "service.inn", nil, {
    "map2112.point.076", 0.4803, 0.4868,
    "map2112.point.100", 0.7698, 0.5064,
})
Data:RegisterGroup(2112, "profession.185", nil, {
    "map2112.point.076.profession.185", 0.4803, 0.4868,
})
Data:RegisterGroup(2112, "service.bank", nil, {
    "map2112.point.077", 0.5529, 0.5744,
})
Data:RegisterGroup(2112, "service.auction", nil, {
    "map2112.point.078", 0.4342, 0.5943,
})
Data:RegisterGroup(2112, "special.training_dummies", nil, {
    "map2112.point.080", 0.4052, 0.4464,
})
Data:RegisterGroup(2112, "equipment.item_upgrades", nil, {
    "map2112.point.081", 0.3782, 0.3678,
    "map2112.point.097", 0.4565, 0.5621,
})
Data:RegisterGroup(2112, "travel.badlands_portal", nil, {
    "map2112.point.082", 0.2547, 0.3988,
})
Data:RegisterGroup(2112, "service.rostrum_of_transformation", nil, {
    "map2112.point.083", 0.2500, 0.5047,
})
Data:RegisterGroup(2112, "profession.186", nil, {
    "map2112.point.084", 0.3893, 0.5228,
})
Data:RegisterGroup(2112, "profession.164", nil, {
    "map2112.point.085", 0.3697, 0.4675,
})
Data:RegisterGroup(2112, "profession.202", nil, {
    "map2112.point.086", 0.4223, 0.4890,
})
Data:RegisterGroup(2112, "profession.755", nil, {
    "map2112.point.087", 0.4017, 0.6201,
})
Data:RegisterGroup(2112, "service.crafting_orders", nil, {
    "map2112.point.088", 0.3497, 0.6201,
})
Data:RegisterGroup(2112, "profession.333", nil, {
    "map2112.point.089", 0.3110, 0.6029,
})
Data:RegisterGroup(2112, "profession.165", nil, {
    "map2112.point.090", 0.2855, 0.6139,
})
Data:RegisterGroup(2112, "profession.197", nil, {
    "map2112.point.091", 0.3285, 0.6779,
})
Data:RegisterGroup(2112, "profession.171", nil, {
    "map2112.point.092", 0.3659, 0.7076,
})
Data:RegisterGroup(2112, "profession.773", nil, {
    "map2112.point.093", 0.3910, 0.7414,
})
Data:RegisterGroup(2112, "profession.356", nil, {
    "map2112.point.094", 0.4429, 0.7459,
})
Data:RegisterGroup(2112, "travel.emerald_dream_portal", nil, {
    "map2112.point.095", 0.6352, 0.5759,
})
Data:RegisterGroup(2112, "service.barber", nil, {
    "map2112.point.096", 0.3033, 0.5510,
})
Data:RegisterGroup(2112, "service.stable", nil, {
    "map2112.point.098", 0.4681, 0.7887,
})
Data:RegisterGroup(2112, "collection.heirlooms", nil, {
    "map2112.point.099", 0.7738, 0.4036,
})
Data:RegisterGroup(627, "travel.portal_training", nil, {
    "map627.point.103", 0.5729, 0.4691,
})
Data:RegisterGroup(627, "collection.special_mounts", nil, {
    "map627.point.104", 0.5887, 0.4199,
})
Data:RegisterGroup(627, "service.stable", nil, {
    "map627.point.105", 0.5976, 0.3810,
})
Data:RegisterGroup(627, "service.inn", nil, {
    "map627.point.106", 0.6419, 0.3254,
    "map627.point.107", 0.5005, 0.3867,
    "map627.point.129", 0.4433, 0.6366,
})
Data:RegisterGroup(627, "service.barber", nil, {
    "map627.point.108", 0.5150, 0.3280,
})
Data:RegisterGroup(627, "collection.pvp_vendors", nil, {
    "map627.point.109", 0.5827, 0.2756,
    "map627.point.132", 0.3348, 0.7264,
})
Data:RegisterGroup(627, "travel.orgrimmar_portal.poi_recorded_627_110", nil, {
    "map627.point.110", 0.5597, 0.2418,
})
Data:RegisterGroup(627, "service.bank", nil, {
    "map627.point.111", 0.5244, 0.1920,
    "map627.point.131", 0.4289, 0.7704,
})
Data:RegisterGroup(627, "collection.curious_coins", nil, {
    "map627.point.112", 0.4886, 0.1343,
})
Data:RegisterGroup(627, "profession.186", nil, {
    "map627.point.113", 0.4637, 0.2656,
})
Data:RegisterGroup(627, "profession.164", nil, {
    "map627.point.114", 0.4518, 0.2950,
})
Data:RegisterGroup(627, "profession.794", nil, {
    "map627.point.115", 0.4135, 0.2656,
})
Data:RegisterGroup(627, "profession.202", nil, {
    "map627.point.116", 0.3837, 0.2656,
})
Data:RegisterGroup(627, "profession.165", nil, {
    "map627.point.117", 0.3522, 0.2956,
})
Data:RegisterGroup(627, "profession.197", nil, {
    "map627.point.118", 0.3633, 0.3340,
})
Data:RegisterGroup(627, "profession.171", nil, {
    "map627.point.119", 0.4186, 0.3122,
})
Data:RegisterGroup(627, "profession.182", nil, {
    "map627.point.120", 0.4378, 0.3525,
})
Data:RegisterGroup(627, "profession.773", nil, {
    "map627.point.121", 0.4186, 0.3844,
})
Data:RegisterGroup(627, "profession.755", nil, {
    "map627.point.122", 0.3944, 0.3467,
})
Data:RegisterGroup(627, "profession.333", nil, {
    "map627.point.123", 0.3939, 0.4189,
})
Data:RegisterGroup(627, "travel.underbelly", nil, {
    "map627.point.124", 0.3535, 0.4508,
})
Data:RegisterGroup(627, "collection.toys", nil, {
    "map627.point.125", 0.4314, 0.4661,
})
Data:RegisterGroup(627, "travel.stormwind_portal.poi_recorded_627_127", nil, {
    "map627.point.127", 0.3893, 0.6321,
})
Data:RegisterGroup(627, "profession.185", nil, {
    "map627.point.128", 0.3935, 0.6685,
    "map627.point.134", 0.6975, 0.3886,
})
Data:RegisterGroup(627, "travel.portal", nil, {
    "map627.point.130", 0.4936, 0.4774,
})
Data:RegisterGroup(627, "special.random_dungeon", nil, {
    "map627.point.133", 0.6389, 0.5531,
})
Data:RegisterGroup(627, "travel.argus_portal", nil, {
    "map627.point.135", 0.7448, 0.4965,
})
Data:RegisterGroup(628, "collection.housing", nil, {
    "map628.point.101", 0.6720, 0.6275,
})
Data:RegisterGroup(628, "collection.black_market", nil, {
    "map628.point.102", 0.7146, 0.1902,
})
Data:RegisterGroup(85, "service.auction", nil, {
    "map85.point.136", 0.5333, 0.7391,
    "map85.point.149", 0.6676, 0.3718,
})
Data:RegisterGroup(85, "service.trading_post", nil, {
    "map85.point.137", 0.4827, 0.7532,
})
Data:RegisterGroup(85, "service.bank", nil, {
    "map85.point.138", 0.4908, 0.8209,
})
Data:RegisterGroup(85, "special.guild", nil, {
    "map85.point.139", 0.4718, 0.7977,
})
Data:RegisterGroup(85, "service.inn", nil, {
    "map85.point.140", 0.5395, 0.7861,
})
Data:RegisterGroup(85, "service.embassy", nil, {
    "map85.point.141", 0.3820, 0.8114,
})
Data:RegisterGroup(85, "travel.portal.poi_recorded_85_142", nil, {
    "map85.point.142", 0.3794, 0.7596,
})
Data:RegisterGroup(85, "collection.pvp_vendors", nil, {
    "map85.point.143", 0.4080, 0.7201,
})
Data:RegisterGroup(85, "travel.borean_thunder", nil, {
    "map85.point.144", 0.4477, 0.6267,
})
Data:RegisterGroup(85, "travel.stranglethorn_vale", nil, {
    "map85.point.145", 0.5234, 0.5341,
})
Data:RegisterGroup(85, "collection.quartermaster", nil, {
    "map85.point.146", 0.5006, 0.5890,
})
Data:RegisterGroup(85, "travel.undercity", nil, {
    "map85.point.147", 0.5111, 0.5603,
})
Data:RegisterGroup(85, "special.training_dummies", nil, {
    "map85.point.148", 0.6287, 0.4976,
    "map85.point.151", 0.6416, 0.3286,
})
Data:RegisterGroup(85, "special.brawl", nil, {
    "map85.point.150", 0.7081, 0.3055,
})
Data:RegisterGroup(85, "travel.portal.poi_recorded_85_152", nil, {
    "map85.point.152", 0.5056, 0.3707,
})
Data:RegisterGroup(85, "profession.794", nil, {
    "map85.point.153", 0.4919, 0.7047,
})
Data:RegisterGroup(85, "profession.356", nil, {
    "map85.point.154", 0.3520, 0.6693,
    "map85.point.171", 0.6634, 0.4186,
})
Data:RegisterGroup(85, "service.stable", nil, {
    "map85.point.155", 0.3294, 0.6477,
})
Data:RegisterGroup(85, "profession.185", nil, {
    "map85.point.156", 0.3246, 0.6966,
})
Data:RegisterGroup(85, "travel.portal_training", nil, {
    "map85.point.157", 0.3625, 0.6915,
    "map85.point.169", 0.7472, 0.4265,
})
Data:RegisterGroup(85, "profession.393", nil, {
    "map85.point.159", 0.3899, 0.4937,
})
Data:RegisterGroup(85, "profession.164", nil, {
    "map85.point.160", 0.4030, 0.5087,
    "map85.point.173", 0.7638, 0.3619,
})
Data:RegisterGroup(85, "profession.171", nil, {
    "map85.point.161", 0.5549, 0.4635,
})
Data:RegisterGroup(85, "profession.333", nil, {
    "map85.point.162", 0.5336, 0.4927,
})
Data:RegisterGroup(85, "profession.773", nil, {
    "map85.point.164", 0.5563, 0.5550,
})
Data:RegisterGroup(85, "profession.202", nil, {
    "map85.point.165", 0.5717, 0.5704,
})
Data:RegisterGroup(85, "profession.165", nil, {
    "map85.point.166", 0.6120, 0.5492,
})
Data:RegisterGroup(85, "profession.197", nil, {
    "map85.point.167", 0.6078, 0.5925,
})
Data:RegisterGroup(85, "profession.182", nil, {
    "map85.point.168", 0.5428, 0.5148,
})
Data:RegisterGroup(85, "special.experience_lock", nil, {
    "map85.point.170", 0.7407, 0.4482,
})
Data:RegisterGroup(85, "profession.186", nil, {
    "map85.point.172", 0.7236, 0.3453,
})
Data:RegisterGroup(85, "profession.755", nil, {
    "map85.point.172.profession.755", 0.7236, 0.3453,
})
Data:RegisterGroup(85, "service.barber", nil, {
    "map85.point.174", 0.4106, 0.6071,
})
Data:RegisterGroup(85, "travel.portal_room", nil, {
    "map85.point.176", 0.5774, 0.8970,
})
Data:RegisterGroup(85, "service.chromie", nil, {
    "map85.point.177", 0.4088, 0.7981,
})
Data:RegisterGroup(86, "travel.portal_training", nil, {
    "map86.point.163", 0.4613, 0.6750,
})
Data:RegisterGroup(84, "travel.portal_room", nil, {
    "map84.point.177", 0.4882, 0.8845,
})
Data:RegisterGroup(84, "profession.182", nil, {
    "map84.point.178", 0.5444, 0.8401,
    "map84.point.186", 0.4091, 0.6626,
})
Data:RegisterGroup(84, "profession.197", nil, {
    "map84.point.179", 0.5264, 0.8209,
    "map84.point.193", 0.5211, 0.2001,
})
Data:RegisterGroup(84, "profession.171", nil, {
    "map84.point.180", 0.5552, 0.8602,
})
Data:RegisterGroup(84, "collection.housing", nil, {
    "map84.point.181", 0.5613, 0.7683,
})
Data:RegisterGroup(84, "profession.333", nil, {
    "map84.point.182", 0.5359, 0.7389,
    "map84.point.195", 0.5171, 0.1201,
})
Data:RegisterGroup(84, "profession.356", nil, {
    "map84.point.183", 0.5501, 0.6933,
})
Data:RegisterGroup(84, "service.trading_post", nil, {
    "map84.point.184", 0.5092, 0.7197,
})
Data:RegisterGroup(84, "profession.773", nil, {
    "map84.point.185", 0.4979, 0.7452,
})
Data:RegisterGroup(84, "profession.165", nil, {
    "map84.point.187", 0.4263, 0.6054,
    "map84.point.216", 0.7186, 0.6270,
})
Data:RegisterGroup(84, "travel.darnassus", nil, {
    "map84.point.188", 0.2414, 0.5598,
})
Data:RegisterGroup(84, "travel.dragon_isles", nil, {
    "map84.point.189", 0.2246, 0.5887,
})
Data:RegisterGroup(84, "travel.boralus", nil, {
    "map84.point.190", 0.2130, 0.5469,
})
Data:RegisterGroup(84, "travel.borean_tundra", nil, {
    "map84.point.191", 0.1836, 0.2532,
})
Data:RegisterGroup(84, "profession.185", nil, {
    "map84.point.192", 0.5071, 0.1743,
})
Data:RegisterGroup(84, "profession.129", nil, {
    "map84.point.193.profession.129", 0.5211, 0.2001,
})
Data:RegisterGroup(84, "profession.164", nil, {
    "map84.point.194", 0.4923, 0.1301,
    "map84.point.202", 0.6350, 0.3672,
})
Data:RegisterGroup(84, "profession.186", nil, {
    "map84.point.194.profession.186", 0.4923, 0.1301,
    "map84.point.203", 0.5933, 0.3749,
})
Data:RegisterGroup(84, "profession.202", nil, {
    "map84.point.194.profession.202", 0.4923, 0.1301,
    "map84.point.201", 0.6291, 0.3208,
})
Data:RegisterGroup(84, "travel.portals.poi_recorded_84_197", nil, {
    "map84.point.197", 0.4855, 0.0854,
})
Data:RegisterGroup(84, "service.stable", nil, {
    "map84.point.198", 0.5412, 0.1287,
    "map84.point.209", 0.6711, 0.3796,
})
Data:RegisterGroup(84, "service.chromie", nil, {
    "map84.point.199", 0.5609, 0.1738,
})
Data:RegisterGroup(84, "travel.portals.poi_recorded_84_200", nil, {
    "map84.point.200", 0.7508, 0.1883,
})
Data:RegisterGroup(84, "service.auction", nil, {
    "map84.point.204", 0.5999, 0.3211,
    "map84.point.219", 0.6153, 0.7158,
})
Data:RegisterGroup(84, "service.bank", nil, {
    "map84.point.205", 0.6463, 0.2828,
    "map84.point.221", 0.6251, 0.7762,
})
Data:RegisterGroup(84, "service.inn", nil, {
    "map84.point.206", 0.6565, 0.3230,
    "map84.point.220", 0.6049, 0.7563,
})
Data:RegisterGroup(84, "travel.tram", nil, {
    "map84.point.208", 0.6772, 0.3479,
}, { [1] = "poi.tooltip.tram.ironforge" })
Data:RegisterGroup(84, "special.brawl", nil, {
    "map84.point.208.special.brawl", 0.6772, 0.3479,
})
Data:RegisterGroup(84, "special.experience_lock", nil, {
    "map84.point.210", 0.8743, 0.3591,
})
Data:RegisterGroup(84, "profession.794", nil, {
    "map84.point.211", 0.8514, 0.2531,
})
Data:RegisterGroup(84, "special.training_dummies", nil, {
    "map84.point.212", 0.7903, 0.6278,
})
Data:RegisterGroup(84, "travel.portal_training", nil, {
    "map84.point.213", 0.8058, 0.6966,
})
Data:RegisterGroup(84, "special.si_7", nil, {
    "map84.point.214", 0.8157, 0.6279,
})
Data:RegisterGroup(84, "collection.pvp_vendors", nil, {
    "map84.point.215", 0.7452, 0.6814,
})
Data:RegisterGroup(84, "profession.755", nil, {
    "map84.point.217", 0.6365, 0.6172,
})
Data:RegisterGroup(84, "service.barber", nil, {
    "map84.point.218", 0.6145, 0.6571,
})
Data:RegisterGroup(84, "special.guild", nil, {
    "map84.point.222", 0.6527, 0.7754,
})
Data:RegisterGroup(499, "special.brawl.poi_recorded_499_207", nil, {
    "map499.point.207", 0.5241, 0.4667,
})
Data.groups = {
    [2393] = {{id = "map2393.group.professions", labelKey = "poi.group.2393.professions",
        tooltipKey = "poi.group.2393.professions.tooltip", x = 0.4653, y = 0.5314,
        members = {"map2393.point.013", "map2393.point.014", "map2393.point.015", "map2393.point.016",
            "map2393.point.017", "map2393.point.018", "map2393.point.019", "map2393.point.056",
            "map2393.point.057", "map2393.point.058"}}},
    [2339] = {
        {id = "map2339.group.alchemy_inscription", labelKey = "poi.group.2339.alchemy_inscription",
            tooltipKey = "poi.group.2339.alchemy_inscription.tooltip", x = 0.4723, y = 0.7076,
            members = {"map2339.point.043", "map2339.point.042"}},
        {id = "map2339.group.jewelcrafting_enchanting", labelKey = "poi.group.2339.jewelcrafting_enchanting",
            tooltipKey = "poi.group.2339.jewelcrafting_enchanting.tooltip", x = 0.5193, y = 0.7094,
            members = {"map2339.point.041", "map2339.point.040"}},
    },
    [85] = {{id = "map85.group.professions", labelKey = "poi.group.85.professions",
        tooltipKey = "poi.group.85.professions.tooltip", x = 0.5684, y = 0.5340,
        members = {"map85.point.161", "map85.point.162", "map85.point.164", "map85.point.165",
            "map85.point.166", "map85.point.167", "map85.point.168"}}},
    [84] = {{id = "map84.group.professions", labelKey = "poi.group.84.professions",
        tooltipKey = "poi.group.84.professions.tooltip", x = 0.5094, y = 0.1562,
        members = {"map84.point.192", "map84.point.193", "map84.point.193.profession.129",
            "map84.point.194", "map84.point.194.profession.202", "map84.point.194.profession.186", "map84.point.195"}}},
}
for index = 1, #Data.maps do
    local entry = Data.maps[index]
    Data.mapByID[entry.mapID] = entry
    Data.records[entry.mapID] = Data.records[entry.mapID] or {}
    Data.groups[entry.mapID] = Data.groups[entry.mapID] or {}
end
