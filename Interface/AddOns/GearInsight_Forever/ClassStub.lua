-- 职业子插件（GearInsight_Forever_Class）在主插件里的「占位」（11-13 重构第 4 期，docs/forever-ui-refactor-design.md 第 4.3 / 4.4 节）
-- 天赋模拟 / 天赋计划小窗 / 宏库 / 键位 / 手法钉板 / 决策 HUD / 冷却管理器键位 / 猎人宠物 / 弹药商 / 弹药提醒和它们的数据
--   （整份天赋树 DataClass.lua、宏库 MacroData.lua、默认加点、宠物数据……离线约 2.6 MB）登录不加载，第一次用到才 LoadAddOn。
--
-- ⛔ 这个子插件里有安全按钮 / 改键位动作条（天赋面板「去点」的 SecureActionButton、键位页 SetBinding……）→ 战斗中一律不加载：
--   战斗中点到入口 → 聊天框说一次「脱战后自动打开」，PLAYER_REGEN_ENABLED 后加载完再执行（ModStub.lua 的 noCombat）。
-- 登录时按存档条件加载（登录后 2 秒、脱战时）：玩家开着、登录就该出现 / 生效的功能 ——
--   天赋计划小窗开着 · 手法钉板开着 · 决策 HUD 开着 · 贡献施法频率开着 · 冷却管理器键位开着且客户端真有冷却管理器 · 猎人且弹药提醒开着
-- 内核里只留：天赋树骨架（TalentIndexData.lua）+ 配点码读法（TraitTalents.lua：ns.CurrentTalentCode / ParseTalentCode / MyMainTree）、
--   天赋面板上「GI 热门配点 / 发到手机」两个按钮（Card.lua）、小下拉菜单 ns.PopMenu（下面，公会子插件也用）。
local _, ns = ...

local M = ns.LazyModule({ key = "class", addon = "GearInsight_Forever_Class", zh = "职业", en = "Class", noCombat = true,
    what = "天赋 / 键位 / 手法 / 宏库 / 宠物页", whatEn = "the Talents / Keys / Rotation / Macros / Pets pages" })
ns._ClassMod = M   -- 测试用

local function classKey()
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 斜杠主命令（Core.lua 的 /gi keys … / probe keys）：处理函数在 _Class 里 → 先加载（战斗中排到脱战后再执行这条命令）
--   → true = 可以接着执行（已加载 / 没有子插件文件夹 = 合并包或没装）
function ns.ClassPrep(after)
    if ns._modReady.class or not M.installed then return true end
    return M:Load(after)
end
function ns.ClassLoad() return M:Load(nil, true) end

-- ---------- 占位页（⛔ 页名 / 顺序 / 图标要和各文件里真页的 ns.RegisterPage 一模一样）----------
M:Page({ key = "talent", order = 1, title = ns.L("天赋", "Talents"), file = "PageTalent.lua" })
M:Page({ key = "ammo", order = 1.45, class = "Hunter", title = ns.L("弹药商", "Ammo vendors"), file = "PageAmmo.lua" })
M:Page({ key = "macro", order = 1.5, title = ns.L("宏库", "Macros"), file = "PageMacro.lua" })
M:Page({ key = "keys", order = 1.6, title = ns.L("键位", "Keys"), tabTitle = ns.L("键位", "Keys"),
    icon = "Interface\\Icons\\INV_Misc_Key_03", file = "PageKeys.lua" })
M:Page({ key = "rot", order = 1.65, title = ns.L("手法", "Rotation"), tabTitle = ns.L("手法", "Rotation"),
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout", file = "PageRot.lua" })
M:Page({ key = "pet", order = 3.6, class = "Hunter", title = ns.L("猎人宠物", "Hunter pets"), tabTitle = ns.L("猎人宠物", "Hunter pets"),
    icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", hold = true, file = "PagePet.lua" })

-- ---------- 斜杠命令（⛔ 名单要和各文件实际登记的 ns.ExtraSlash 键一致，gi_forever_split_p4_test.py 核对）----------
M:Slash({ "kb" }, "PageKeys.lua")
M:Slash({ "rot", "手法" }, "PageRot.lua")
M:Slash({ "talentprobe" }, "Talents.lua")
if M:Has("AmmoRemind.lua") then M:Slash({ "ammo", "弹药" }, "AmmoRemind.lua") else M:Slash({ "ammo", "弹药" }, "PageAmmo.lua") end

-- ---------- 主插件 / 别的子插件会调到的函数 ----------
-- 打开窗口 / 改配点这类动作：战斗中排到脱战后（defer）
M:Shell("ImportTalentDialog", { file = "Talents.lua", defer = true })   -- /gi t、窗口与提醒「导入配点码」
M:Shell("ShowTalentPlan", { file = "Talents.lua", defer = true })       -- /gi talent plan、小地图菜单「打开天赋计划小窗」
M:Shell("ApplyTalentCode", { file = "Talents.lua", defer = true })      -- 天赋面板「GI 热门配点」的「套用」（Card.lua）、攻略页
M:Shell("LoadSimCode", { file = "PageTalent.lua", defer = true })       -- 攻略页「在模拟器里打开」
M:Shell("ImportMacro", { file = "PageMacro.lua", defer = true })        -- 升级规划「拿宏」
-- 升级规划（_Plan 的 PagePlan.lua）画天赋 / 宏行用的查询：战斗中拿不到就当「没有」（那一行这次不画）
for _, n in ipairs({ "ActivePlan", "PlanSpentStep", "PlanTalentSteps", "TalentGoFallback", "TalentOpenerHover" }) do M:Shell(n, { file = "Talents.lua" }) end
for _, n in ipairs({ "MacroBody", "MacroState", "MacrosOnBars", "SpellIcon" }) do M:Shell(n, { file = "PageMacro.lua" }) end
-- 数据表：升级规划读宏库（(ns.Macros or {})[职业]）、专业页读野兽所在地区（ns.PetTameData.zones）
M:Table("Macros", "MacroData.lua")
M:Table("PetTameData", "PetTameData.lua")
-- 整份天赋树 / 键位技能表：漏改的 ns.Data.talents / ns.Data.keys 读取一读就加载（内核正常读法走 ns.TalentTrees 骨架）
M:DataKeys({ "talents", "keys" })

-- 天赋计划小窗在不在（小地图菜单 / 窗口与提醒要问）：没加载 = 小窗没建（开着的话登录时就条件加载了）
if M:Active("Talents.lua") and rawget(ns, "TalentPlanState") == nil then
    function ns.TalentPlanState()
        local p = ns.db and ns.db.talentPlan
        if p and p.v ~= 2 then ns.db.talentPlan = nil; p = nil end   -- 开服前（旧树）导入的计划作废，同 Talents.lua
        if not p then return "none" end
        if p.cls ~= classKey() then return "other" end
        return "hidden"
    end
end

-- ---------- 「窗口与提醒」占位（真模块用同一个 key 登记会顶替；标题 / 顺序和真的一样）----------
local function after(fn) return function() if M:Load(fn) then fn() end end end
M:Window({ key = "keysBoard", order = 50, title = function() return ns.L("手法钉板", "Rotation board") end,
    state = function() return ns.L("已关闭", "Closed") end,
    actions = function()
        return {
            { text = ns.L("打开", "Show"), fn = after(function() if ns.KeysRot then ns.KeysRot.Toggle(true) end end) },
            { text = ns.L("重置位置", "Reset position"), fn = function() if ns.db then ns.db.keysBoardPos = nil end end },
        }
    end }, "KeysRot.lua")
M:Window({ key = "keysHud", order = 51, title = function() return ns.L("决策 HUD（钉板下方）", "Decision HUD (below the board)") end,
    state = function() return ns.L("已关闭", "Closed") end,
    actions = function()
        return { { text = ns.L("打开", "Show"), fn = after(function() if ns.KeysHud then ns.KeysHud.Toggle(true) end end) } }
    end }, "KeysHud.lua")
M:Window({ key = "talentPlan", order = 40, title = function() return ns.L("天赋计划小窗", "Talent plan") end,
    state = function()
        local st = ns.TalentPlanState()
        if st == "shown" then return ns.L("显示中", "Shown") end
        if st == "hidden" then return ns.L("已关闭（计划还在）", "Closed (plan kept)") end
        return ns.L("还没有导入配点计划", "No plan imported")
    end,
    actions = function()
        local st = ns.TalentPlanState()
        if st == "none" or st == "other" then
            return { { text = ns.L("导入配点码", "Import build"), fn = function() ns.ImportTalentDialog() end } }
        end
        return {
            { text = st == "shown" and ns.L("关闭", "Hide") or ns.L("打开", "Show"), fn = function() ns.ShowTalentPlan(st ~= "shown") end },
            { text = ns.L("重置位置", "Reset position"), fn = after(function() if ns.ResetTalentPlanPos then ns.ResetTalentPlanPos() end end) },
        }
    end }, "Talents.lua")

-- ---------- 登录时按存档条件加载 ----------
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
-- → 要加载的原因（测试 / 诊断用），不用加载 = nil
function ns.ClassLoginWhy()
    local db = ns.db
    if not db or ns._modReady.class or not M.installed then return nil end
    local tp = db.talentPlan
    if M:Has("Talents.lua") and type(tp) == "table" and tp.v == 2 and tp.cls == classKey() and not tp.hidden then return "talentPlan" end
    if M:Has("KeysRot.lua") and db.keysBoard then return "keysBoard" end
    if M:Has("KeysHud.lua") and db.keysHud then return "keysHud" end
    if M:Has("KeysCast.lua") and db.castCollect == true then return "castCollect" end
    if M:Has("KeysCdm.lua") and not (db.ui and db.ui.cdmKeys == false) then
        for _, n in ipairs(VIEWERS) do if _G[n] then return "cdmKeys" end end
    end
    if M:Has("AmmoRemind.lua") and ns.MyClass and ns.MyClass() == "Hunter" and not (type(db.ammoRemind) == "table" and db.ammoRemind.on == false) then return "ammo" end
    return nil
end
local function loginCheck()
    if ns.ClassLoginWhy() then M:Load(function() end, true) end   -- 战斗中：脱战后再加载（不提示）
end
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("ADDON_LOADED")
    pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
    local TF_NAMES = { "PlayerTalentFrame", "TalentFrame", "ClassTalentFrame", "PlayerSpellsFrame", "TalentUIFrame", "EUI_ClassicTalents" }
    -- 天赋面板第一次打开：加载 _Class（天赋计划「下一点」的绿框在 Talents.lua，加载后它自己挂钩子），这一次的绿框补画上
    local function hl() if ns.HighlightTalentStep and C_Timer and C_Timer.After then C_Timer.After(0.1, ns.HighlightTalentStep) end end
    local hooked = setmetatable({}, { __mode = "k" })   -- 记在自己的表里，不往暴雪框体上写字段
    local function hookShow()
        if not M:Active("Talents.lua") then return end
        for _, n in ipairs(TF_NAMES) do
            local f = _G[n]
            if type(f) == "table" and type(f.HookScript) == "function" and not hooked[f] then
                hooked[f] = true
                f:HookScript("OnShow", function() if not ns._modReady.class and M:Load(hl, true) then hl() end end)
            end
        end
    end
    ev:SetScript("OnEvent", function(_, e, name)
        if e == "PLAYER_LOGIN" then
            pcall(hookShow)
            if C_Timer and C_Timer.After then C_Timer.After(2, loginCheck) else loginCheck() end
        elseif e == "ADDON_LOADED" then
            if type(name) == "string" and name:find("Talent", 1, true) then pcall(hookShow) end
            if name == "Blizzard_CooldownViewer" and ns.db and not ns._modReady.class then loginCheck() end
        elseif e == "LEARNED_SPELL_IN_TAB" then
            -- 升级学会新技能、键位页用过（keysMode）：「该上条的技能不在条上」提醒在键位页文件里 → 加载后照常提醒
            if ns._modReady.class or not (ns.db and ns.db.keysMode) or not M:Active("PageKeys.lua") then return end
            local function tell() if ns._KeysLearned then ns._KeysLearned() end end
            if M:Load(tell, true) then tell() end
        end
    end)
    ns._ClassLoginEvent = ev:GetScript("OnEvent")   -- 测试用
end

-- ---------- 小下拉菜单（键位模板 / 公会会员名；不依赖 MenuUtil / EasyMenu，《无限》客户端没验过它们）----------
-- 11-13 第 4 期从 KeysKb.lua 挪来（KB.Menu 现在转调这里），公会子插件点会员名也用，不用为了它加载 _Class
local menu
function ns.PopMenu(anchor, title, items)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetClampedToScreen(true); menu:EnableMouse(true)
        if menu.SetBackdrop then
            menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            menu:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
        end
        menu.t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); menu.t:SetPoint("TOPLEFT", 10, -8)
        menu.rows = {}
        local cl = CreateFrame("Button", nil, menu, "UIPanelCloseButton"); cl:SetSize(20, 20); cl:SetPoint("TOPRIGHT", 0, 0)
        cl:SetScript("OnClick", function() menu:Hide() end)   -- 10-18 战斗中关不掉：原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    end
    menu.t:SetText(title or "")
    for _, r in ipairs(menu.rows) do r:Hide() end
    for i, it in ipairs(items) do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetSize(200, 18)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 6, 0); r.t:SetJustifyH("LEFT")
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
            menu.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 18)
        r.t:SetText(it.text)
        r:SetScript("OnClick", function() menu:Hide(); pcall(it.fn) end)
        r:Show()
    end
    menu:SetSize(214, 32 + #items * 18)
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
    ns._PopMenu = menu   -- 测试用
    return menu
end
