-- 专业子插件（GearInsight_Forever_Prof）在主插件里的「占位」（11-13 重构第 4 期，docs/forever-ui-refactor-design.md 第 4.3 节）
-- 专业页、冲级路线、配方库、专业助手和两张大表（ProfData.lua / ProfRecipes.lua，离线约 4.4 MB）登录不加载，第一次用到才 LoadAddOn：
--   · 点「专业」页签 / /gi prof / 小地图菜单「专业」（都走 ToggleMain("prof") → 下面的占位页）
--   · 升级规划页画专业行（ns.ProfPlanItems / ns.ProfRenderRow / ns.ProfOpenTab 外壳）
--   · 内核里漏改的 ns.Prof.<专业页才用的函数> / ns.ProfData / ns.ProfRecipes 读取（元表 / 占位表兜底，不会静默拿到 nil）
-- 登录就要用的留在主插件：Prof.lua 小核（读角色专业、专业名、事件、探针、/gi prof 命令）+ ProfCoreData.lua 精简数据
--   + ProfSeen.lua（见到图纸记出处）+ ReagentSrc.lua / ReagentSrcData.lua（材料鼠标提示，默认开、任何物品提示都会问一句，
--   放进子插件 = 指到第一种材料就把 4 MB 全拉进来，所以它和它约 260 KB 的数据留在内核）
--   + Prices.lua 价格层（HOLD；只读写存档、不建框体，以后拍卖行扫描要在拍卖行事件里直接写价格，不该为了记一笔价拉起整个专业模块）。
local _, ns = ...

local M = ns.LazyModule({ key = "prof", addon = "GearInsight_Forever_Prof", zh = "专业", en = "Professions",
    what = "专业页 / 冲级路线 / 配方库", whatEn = "the Professions page / leveling routes / recipe library" })
ns._ProfMod = M   -- 测试用

-- ⛔ 页名 / 顺序 / 图标要和 PageProf.lua 里真页的 ns.RegisterPage 一模一样
M:Page({ key = "prof", order = 1.85, title = ns.L("专业", "Professions"), tabTitle = ns.L("专业", "Profs"),
    icon = "Interface\\Icons\\Trade_BlackSmithing", hold = true, file = "PageProf.lua" })

-- 升级规划（_Plan）里画专业行用的函数
M:Shell("ProfPlanItems", { file = "ProfLib.lua" })
M:Shell("ProfRenderRow", { file = "ProfLib.lua" })
M:Shell("ProfOpenTab", { file = "PageProf.lua" })
M:Shell("ProfRecipeBySpell", { file = "PageProf.lua" })   -- 漏改兜底（内核原来经验食物走它，现在走 ns.ProfFoodItem）

-- 大表：漏改的 ns.ProfData.x / ns.ProfRecipes.x 读取 → 加载后返回真表里的字段
M:Table("ProfData", "ProfData.lua")
M:Table("ProfRecipes", "ProfRecipes.lua")

-- ns.Prof 上专业页才用的函数（ProfLib.lua / ProfPlan.lua 挂上去的）：没加载时一读就加载
--   ⛔ 名单要和那两个文件实际挂的一致（gi_forever_split_p4_test.py 核对）
ns._ProfLibNames = {
    "GatherColor", "HEX", "COLOR_NAME", "RecipeColor", "TierIndex", "NextTier", "RouteStep", "CurrentZone", "ZoneGather", "XpFoods",
    "BlueprintProf", "LegacyClaimed", "Strategy", "SetStrategy", "GATHER", "CRAFT",
    "MUST_GAP", "MUST_LEVELS", "Legs", "LegAt", "LegFor", "CurLeg", "NodeName", "ZoneGate", "ZoneReach", "Gate", "SideOK", "FirstSpot",
    "TrainerIn", "AnyTrainer", "NextTrainerLeg", "Hub", "CAPITAL", "CAPITALS", "CityHub", "TrainWhere", "PRIMARY", "PICK", "PICK_NOTE",
    "Planned", "SetPlanned", "PlanSkills", "Timeline", "CampHas", "CraftNow", "WHERE",
}
if M.installed and type(ns.Prof) == "table" and not getmetatable(ns.Prof) then
    local LIB = {}
    for _, k in ipairs(ns._ProfLibNames) do LIB[k] = true end
    setmetatable(ns.Prof, { __index = function(t, k)
        if not LIB[k] or ns._modReady.prof then return nil end
        M:Load(nil, true)
        return rawget(t, k)
    end })
end

function ns.ProfLoad() return M:Load(nil, true) end
