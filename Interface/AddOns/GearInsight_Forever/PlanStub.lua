-- 升级 / 装备子插件（GearInsight_Forever_Plan）在主插件里的「占位」（11-12 重构第 3 期，docs/forever-ui-refactor-design.md 第 4 节）
-- 用户「内存在可用情况下降低到最小」「功能不能少」：升级规划 / 推荐装备 / 掉落 / T1 套装 / 成就这五页和它们的大数据表
--   （整张掉落表、各职业装备候选、稀有怪、技能表、副本任务、按天赋推荐的属性表……）登录时不加载，第一次用到才 LoadAddOn。
--   首次打开会有一次约 0.1–0.2 秒的停顿（用户已接受，不做登录后预加载）。
--
-- 这个文件做四件事：
--   1. ns.PlanLoad()：加载子插件（装了才加载；失败只报一次，之后不再反复试）
--   2. ns.Data 的大字段（tier / loot / rares / achievements / gearCraft / spells / questSeries / gear）没加载时一读就触发加载
--      —— 漏改的读取点不会拿到 nil 静默失效
--   3. 五张占位页：页签、顺序、页名和原来一样；第一次点开 → 加载 → 真页就地顶替（UI.lua 的 ns.RegisterPage 认 lazy 字段）
--   4. 主插件里会在「子插件没加载」时被调用的那几个函数：先放一个外壳，调用时加载再转给真函数
--
-- 合并打包（发版脚本默认，回滚开关）：子插件的文件直接排在主插件 toc 末尾、没有 GearInsight_Forever_Plan 这个文件夹
--   → 这里查不到子插件 = 不放占位页，真页照旧自己登记；ns.Data 用整份 Data.lua，大字段本来就在，下面的元表永远不触发。
local _, ns = ...

local LAZY = { tier = true, loot = true, rares = true, achievements = true, gearCraft = true, spells = true, questSeries = true, gear = true }
ns._PlanLazyKeys = LAZY   -- 测试用

local failed
function ns.PlanReady() return ns._planReady == true end
-- → true = 子插件已经在了（或刚加载上）。没装 / 加载失败 → false（失败的提示 ns.LoadModule 会打一次）
function ns.PlanLoad()
    if ns._planReady then return true end
    if failed or not (ns.LoadModule and ns.ModuleAvailable and ns.ModuleAvailable("plan")) then return false end
    local ok, loaded = pcall(ns.LoadModule, "plan")
    if not (ok and loaded) then failed = true; return false end
    return true
end
function ns._PlanResetFailed() failed = nil end   -- 测试用

-- ---------- 2. ns.Data 的大字段：没加载时一读就加载 ----------
-- ⛔ 只管上面那 8 个名字；别的不存在的键照旧是 nil。加载过程中子插件自己读这些字段时已经 rawset 好了，不会绕回来
if type(ns.Data) == "table" and not getmetatable(ns.Data) then
    local busy
    setmetatable(ns.Data, { __index = function(t, k)
        -- 11-13 第 4 期：别的子插件的字段（天赋树 / 键位技能表 → _Class）由 ModStub.lua 登记在 ns._DataLazy
        if not LAZY[k] then
            local h = ns._DataLazy and ns._DataLazy[k]
            if h and not busy then busy = true; local ok, v = pcall(h, t); busy = nil; return ok and v or nil end
            return nil
        end
        if busy or ns._planReady then return nil end
        busy = true
        pcall(ns.PlanLoad)
        busy = nil
        return rawget(t, k)
    end })
end

-- ---------- 4. 外壳：主插件里可能在子插件加载前就调到的函数 ----------
-- 真函数加载后会把 ns[name] 盖掉；这里调用时再读一次 ns[name]，读到的还是自己 = 没加载上 → 返回 nil（调用方都按「没有」处理）
local function shell(name)
    local stub
    stub = function(...)
        if not ns.PlanLoad() then return nil end
        local f = ns[name]
        if f and f ~= stub then return f(...) end
        return nil
    end
    ns[name] = stub
end
for _, name in ipairs({
    "PlanShowLevel",     -- 专业页等级刻度：点一下跳到升级规划的那一级（PageProf.lua）
    "PlanSetView",       -- /gi route、/gi zones（Route.lua）
    "SetPlanRange",      -- /gi zones
    "LootShowDungeon",   -- 路线页的副本按钮 / 装备角标「打开掉落页」
    "ItemFallbackTip",   -- 物品信息没缓存时的兜底提示（装备角标 / 攻略页）
    "PlanRankOf",        -- 训练师可学技能（TrainNow.lua）
}) do shell(name) end

-- ---------- 3. 占位页 ----------
local function lazyBuild(p)
    local mine
    mine = function(f)
        if ns.PlanLoad() and p.build and p.build ~= mine then return p.build(f) end
        -- 加载不上：页面上说清楚（不留一张白页）
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 0, 20)
        fs:SetWidth(520)
        fs:SetText(ns.L("这一页在「GearInsight_Forever_Plan」文件夹里，没能加载上。\n请重新安装插件（解压时把压缩包里的文件夹全部放进 AddOns），或在插件列表里把它勾上。",
            "This page lives in the GearInsight_Forever_Plan folder, which couldn't be loaded.\nReinstall the addon (copy every folder from the zip into AddOns) or enable it in your AddOns list."))
    end
    return mine
end

local function addonThere()
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not f then return false end
    local ok, n, _, _, _, reason = pcall(f, "GearInsight_Forever_Plan")
    return ok and n ~= nil and reason ~= "MISSING"
end

if addonThere() and ns.RegisterPage then
    -- ⛔ 页名 / 顺序 / 图标要和子插件里真页的 ns.RegisterPage 一模一样（真页顶替时页名沿用这里的）
    local list = {
        { key = "plan", order = 1.8, title = ns.L("升级规划", "Leveling plan"), icon = "Interface\\Icons\\Ability_Hunter_Pathfinding" },
        { key = "gear", order = 1.95, title = ns.L("推荐装备", "Gear picks"), tabTitle = ns.L("推荐装备", "Gear picks"), icon = "Interface\\Icons\\INV_Chest_Plate03" },
        { key = "loot", order = 2, title = ns.L("掉落 · 心愿单", "Loot"), tabTitle = ns.L("掉落", "Loot") },
        { key = "tier", order = 3, title = ns.L("T1 套装", "Tier 1") },
        { key = "ach", order = 3.2, title = ns.L("成就 · 传承", "Achievements"), tabTitle = ns.L("成就", "Achieve"), icon = "Interface\\Icons\\Achievement_Zone_Ashenvale_01" },
    }
    for _, p in ipairs(list) do
        p.lazy = "plan"
        p.build = lazyBuild(p)
        ns.RegisterPage(p)
    end
    ns._PlanStubPages = list   -- 测试用
else
    -- 既没有子插件文件夹、合并包里的文件也没跟上（只装了主插件）：五页不出现，登录后说一次
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if ns._planReady then return end
        local function say()
            if ns._planReady then return end
            ns.Print(ns.L("安装不完整：缺少 GearInsight_Forever_Plan 文件夹，升级规划 / 推荐装备 / 掉落 / 套装 / 成就页暂时用不了。请重新安装（把压缩包里的文件夹全部放进 AddOns）。",
                "Incomplete install: the GearInsight_Forever_Plan folder is missing, so Leveling plan / Gear picks / Loot / Tier / Achievements are unavailable. Please reinstall (copy every folder from the zip into AddOns)."))
        end
        if C_Timer and C_Timer.After then C_Timer.After(8, say) else say() end
    end)
    ns._PlanMissingNotice = ev:GetScript("OnEvent")   -- 测试用
end
