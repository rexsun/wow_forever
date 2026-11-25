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
-- 11-14 order 1.85 → 1.15：专业从「升级」大类里拿出来成了左栏独立一级（UI.lua GROUPS 的 grp_up 1.1 / grp_gear 1.2 之间）
M:Page({ key = "prof", order = 1.15, title = ns.L("专业", "Professions"), tabTitle = ns.L("专业", "Profs"),
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

-- 11-15 用户「专业购买的快捷窗口」：开商人 / 拍卖行时贴一个小窗列出专业路线现在要买的（PageProf.lua 的 ns.ProfShop.QuickShow）
--   主插件只管事件：学了制造 / 烹饪 / 急救、没关掉（ns.db.prof.quick ~= false）、不在战斗 → 才加载专业子插件（不学专业的人不会多占内存）
local QUICK_KEYS = { alchemy = true, blacksmithing = true, enchanting = true, engineering = true, leatherworking = true, tailoring = true, cooking = true, firstaid = true }
local function quickWanted()
    if not ns.db or (ns.db.prof and ns.db.prof.quick == false) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local P = ns.Prof
    local sk = P and P.Skills and P.Skills() or {}
    for k, s in pairs(sk) do if QUICK_KEYS[k] and type(s) == "table" and (tonumber(s.r) or 300) < 300 then return true end end
    return false
end
ns.ProfQuickWanted = quickWanted
local qev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(qev.RegisterEvent, qev, e) end
qev:SetScript("OnEvent", function(_, e)
    if e == "MERCHANT_CLOSED" or e == "AUCTION_HOUSE_CLOSED" then
        if ns.ProfShop and ns.ProfShop.QuickHide then pcall(ns.ProfShop.QuickHide) end
        return
    end
    if not quickWanted() then return end
    local kind = (e == "MERCHANT_SHOW") and "merchant" or "ah"
    -- 商人列表要等一帧才齐
    local function go()
        if not ns.ProfShop then pcall(ns.ProfLoad) end
        if ns.ProfShop and ns.ProfShop.QuickShow then pcall(ns.ProfShop.QuickShow, kind) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, go) else go() end
end)
ns._ProfQuickEvent = qev:GetScript("OnEvent")   -- 测试用

-- 11-15 用户截图「锚定个按钮 Gearinsight，可以直接在旁边打开冲专业页面」：拍卖行 / 商人窗口右上角挂一个「GearInsight 冲专业」按钮，
--   点了在它右边打开主面板的「专业 → 专业助手（冲级路线）」，行上的「买 / 搜」直接对着这个窗口用；面板位置只在这次贴过去，不改存的位置
function ns.ProfOpenBeside(host)
    if InCombatLockdown and InCombatLockdown() then return false end
    if ns.ProfShop and ns.ProfShop.QuickHide then pcall(ns.ProfShop.QuickHide) end   -- 页里有同样的买 / 搜，快捷窗就收起
    if not ns.ProfOpenTab then pcall(ns.ProfLoad) end
    if ns.ProfOpenTab then pcall(ns.ProfOpenTab, "route") elseif ns.ToggleMain then ns.ToggleMain("prof") end
    local m = _G.GearInsightForeverMain
    if m and host and m:IsShown() then m:ClearAllPoints(); m:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0) end
    return true
end
-- 11-17 玩家「这个怎么关闭」：右键 = 不再显示（ns.db.prof.btn = false）；/gi 专业购买 找回（内存紧，不单独加命令 / 设置项）
local function attachBtn(host, key)
    if not host then return end
    local old = rawget(host, "_giProfBtn")
    if old then old:SetShown(not (ns.db.prof and ns.db.prof.btn == false)); return end
    local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetSize(128, 22); b:SetText("GearInsight " .. ns.L("冲专业", "Profs"))
    if key == "merchant" then b:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -2)   -- 商人窗口标题栏窄：挂在窗口下沿
    else b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -30, -2) end
    b:SetFrameLevel((host:GetFrameLevel() or 1) + 20)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn)
        if btn ~= "RightButton" then return ns.ProfOpenBeside(host) end
        ns.db.prof = ns.db.prof or {}; ns.db.prof.btn = false; self:Hide()
        ns.Print(ns.L("冲专业按钮已隐藏，找回：/gi 专业购买", "Prof button hidden: /gi profshop"))
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("GearInsight · " .. ns.L("冲专业", "Profession route"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("在旁边打开冲级路线：每行的「买 / 搜」直接对着这个窗口买图纸、材料，或在拍卖行搜。右键：不再显示", "Open your leveling route beside this window; use Buy / Search on each row. Right-click: hide"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    host._giProfBtn = b
    if ns.db.prof and ns.db.prof.btn == false then b:Hide() end
end
ns.ProfAttachBtn = attachBtn
local bev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "AUCTION_HOUSE_SHOW" }) do pcall(bev.RegisterEvent, bev, e) end
bev:SetScript("OnEvent", function(_, e)
    if e == "MERCHANT_SHOW" then pcall(attachBtn, _G.MerchantFrame, "merchant")
    else pcall(attachBtn, _G.AuctionHouseFrame or _G.AuctionFrame, "ah") end
end)
-- /gi 专业购买 · /gi profshop：重新打开自动弹（开着商人 / 拍卖行时顺便弹出来）
ns.ExtraSlash = ns.ExtraSlash or {}
for _, c in ipairs({ "专业购买", "profshop" }) do
    ns.ExtraSlash[c] = function()
        ns.db.prof = ns.db.prof or {}
        ns.db.prof.quick = nil; ns.db.prof.btn = nil   -- 11-17 顺带找回右键隐藏的「冲专业」按钮
        for _, h in ipairs({ _G.MerchantFrame or false, _G.AuctionHouseFrame or false, _G.AuctionFrame or false }) do if h and rawget(h, "_giProfBtn") then attachBtn(h) end end
        ns.Print(ns.L("专业购买窗口和「冲专业」按钮：开商人 / 拍卖行时自动弹（已打开）", "Profession shopping window & button: on"))
        if not ns.ProfShop then pcall(ns.ProfLoad) end
        local S = ns.ProfShop
        if S and S.MerchantOpen and S.MerchantOpen() then S.QuickShow("merchant", true)
        elseif S and S.AHOpen and S.AHOpen() then S.QuickShow("ah", true) end
    end
end

-- 11-17 用户「这些弹出的功能都确保能永久关闭」：按需加载的子插件里会自己弹出来的东西，关掉后这个子插件登录时可能就不加载了，
--   真模块的「窗口与提醒」条目也就没了 → 这里放同 key 的占位：读存档显示状态，点「打开」写回存档再加载子插件（真模块加载后用同一个 key 顶替）
M:Window({ key = "profShop", order = 71, title = function() return ns.L("专业购买窗口（开商人 / 拍卖行时）", "Profession shopping window") end,
    state = function()
        local p = ns.db and ns.db.prof
        return (type(p) == "table" and p.quick == false) and ns.L("已关闭（/gi 专业购买 仍能打开）", "Closed") or ns.L("开商人 / 拍卖行时弹出", "Pops up at merchants / the AH")
    end,
    actions = function()
        local p = ns.db and ns.db.prof
        local on = not (type(p) == "table" and p.quick == false)
        return { { text = on and ns.L("关闭", "Turn off") or ns.L("打开", "Turn on"), fn = function()
            if not ns.db then return end
            if type(ns.db.prof) ~= "table" then ns.db.prof = {} end
            if on then ns.db.prof.quick = false else ns.db.prof.quick = nil end
        end } }
    end }, "PageProf.lua")
