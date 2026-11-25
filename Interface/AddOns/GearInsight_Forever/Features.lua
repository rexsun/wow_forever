-- 功能清单（11-17 界面重构第 6 期「功能开关中心」，设计稿 docs/forever-ui-refactor-p6-design.md 第 1 节）
--   用户 11-17「所有功能可以勾选开启，勾选关闭，按需加载，界面功能分类更加合理，更容易寻找」：
--   每个用户能感知的功能在这里登记一条（单一真相源，纯描述，不建框体、不注册事件），设置页「功能」子页按这份画勾选框，
--   第 6b 期按 files 把文件搬进按需加载的子插件、按开关决定登录加不加载。
--   ⛔ 排在 Core.lua / ModManifest.lua 之后、任何功能文件之前（功能文件开头的文件闸要用 ns.FeatureOff）
--
-- 一条的字段：
--   key 唯一 · cat 分类（CATS 里的 key）· zh / en 名称 · dzh / den 一句话说明 · def 默认开 / 关（⛔ 一律保持现在的默认行为）
--   开关从哪读写（三选一，按这个顺序认）：
--     get / set   自己写（⛔ 读写和原设置项同一个存档键；子插件没加载、原设置项还没登记时也要能读写）
--     sw          已有总开关：复用 Settings.lua / 各模块 RegisterSettings 里那条 check 项的 get / set（存档键不变）
--     （都没有）  新存档键 ns.db.feat[key]（nil = 默认 def），配合 gate / pageFeat 用
--   gate = true     没有自带开关：内核文件把正文包成函数交给 ns.FeatureDefer(key, body)（子插件里的文件可以直接开头一行 FeatureOff return），关 / 开都要重载生效
--   pageFeat = true 纯页面功能：关了左栏不出这一页（UI.lua visiblePages 认 ns.FeaturePageOff），重载生效
--   files 属于它的文件（第 6b 期搬子插件用）· page「打开 ›」去哪页 · cfg「设置 ›」跳到哪个设置项 / 设置组（默认 = sw）
--   class 职业专属（只给这个职业显示）· hold 依赖的文件（HOLD 没进包时不显示）· avail 能不能用（函数，出错当不能用）
--   mod 勾上时要加载的子插件（group / mage = UI.lua ns.LoadModule；class / xp / … = ModStub.lua ns.ModLoad）
--
-- ⛔ 文件闸的局限（第 6a 期）：游戏里主插件的存档要等它所有文件都执行完才读进来（ADDON_LOADED 之前读不到），
--   所以文件闸只在「按需加载的子插件里的文件」（加载时存档早就有了）真正生效；还留在内核里的文件闸文件要等第 6b 期搬进子插件才生效。
--   离线测试按「存档已就绪」验证文件闸本身（GearInsightForeverDB 提前给好）。
local _, ns = ...

local CATS = {
    { key = "up", zh = "升级", en = "Leveling" },
    { key = "dungeon", zh = "副本", en = "Dungeons" },
    { key = "gear", zh = "装备", en = "Gear" },
    { key = "class", zh = "职业", en = "Class" },
    { key = "prof", zh = "专业", en = "Professions" },
    { key = "bag", zh = "背包", en = "Bags" },
    { key = "social", zh = "社交", en = "Social" },
    { key = "info", zh = "资讯", en = "News" },
    { key = "set", zh = "设置", en = "Settings" },
}
local CATBY = {}
for i, c in ipairs(CATS) do c.order = i; CATBY[c.key] = c end
ns.FEATURE_CATS = CATS

local LIST, BYKEY, PAGEFEAT = {}, {}, {}
ns._Features = LIST   -- 测试 / 清单脚本用

function ns.Feature(f)
    if not (f and f.key and CATBY[f.cat]) or BYKEY[f.key] then return end
    if f.sw and f.cfg == nil then f.cfg = f.sw end
    BYKEY[f.key] = f
    LIST[#LIST + 1] = f
    if f.pageFeat and f.page then PAGEFEAT[f.page] = f end
end
function ns.FeatureDef(key) return BYKEY[key] end

local function featDB(create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if create and type(db.feat) ~= "table" then db.feat = {} end
    return type(db.feat) == "table" and db.feat or nil
end
local function swItem(f) local t = ns._SettingsItems; return f.sw and t and t[f.sw] or nil end

-- 文件闸用：这个功能关着没有。存档还没读进来（主插件加载期间）就看全局存档（离线测试 / 子插件里的文件）；都没有 = 按默认
function ns.FeatureOff(key)
    local f = BYKEY[key]
    if not f then return false end
    if (f.get or f.sw) and ns.db then return not ns.FeatureOn(key) end
    local db = ns.db or _G.GearInsightForeverDB
    local t = type(db) == "table" and db.feat or nil
    local v
    if type(t) == "table" then v = t[key] end   -- ⛔ 别写成 `and t[key] or nil`：存的 false 会被吞成 nil
    if v == nil then return not f.def end
    return v == false
end

-- 11-17 内核文件的文件闸：主插件的存档要等 ADDON_LOADED（全部文件执行完）才读进来，文件开头那行 FeatureOff 读不到玩家的开关
--   （游戏里勾掉重载后照样在跑）→ 内核里带文件开关的功能文件把正文包成函数交给这里：
--   存档已经在（后加载的子插件）= 当场按开关跑；还没读 = 排进 ns.modules，ADDON_LOADED 读完存档按登记顺序跑，开着才跑正文
--   ⛔ 包进来的正文里不许注册 ADDON_LOADED / VARIABLES_LOADED（跑的时候已经过了）
-- 11-17 关着没跑的正文先记下（ns.FeatureRunLate 用：「窗口与提醒」里点「打开」= 不用重载当场跑起来，例如新版说明）
local deferSkip = {}
function ns.FeatureDefer(key, body)
    if ns.db then
        if not ns.FeatureOff(key) then body() else deferSkip[key] = body end
        return
    end
    table.insert(ns.modules, function() if not ns.FeatureOff(key) then body() else deferSkip[key] = body end end)
end
-- 登录时关着、现在打开了：把当时没跑的正文补跑一次（只跑一次；正文里 PLAYER_LOGIN 之类早过了的事件不会再来，调用方自己补）。返回 true = 跑了
function ns.FeatureRunLate(key)
    local body = deferSkip[key]
    if not body or ns.FeatureOff(key) then return false end
    deferSkip[key] = nil
    local ok, err = pcall(body)
    if not ok and ns.Print then ns.Print(tostring(err)) end
    return ok
end

function ns.FeatureOn(key)
    local f = BYKEY[key]
    if not f then return false end
    if f.get then
        local ok, v = pcall(f.get)
        if ok then return v and true or false end
        return f.def and true or false
    end
    local it = swItem(f)
    if it and type(it.get) == "function" then
        local ok, v = pcall(it.get)
        if ok then return v and true or false end
    end
    if f.sw then return f.def and true or false end
    return not ns.FeatureOff(key)
end

local function loadMod(m)
    if m == "group" then return ns.LoadModule and ns.LoadModule("group") end
    if m == "mage" then return ns.LoadModule and ns.LoadModule("group") and ns.GroupLoadMage and ns.GroupLoadMage(true) end
    return ns.ModLoad and ns.ModLoad(m)
end

-- 勾选 / 取消：有自带开关的立刻生效；文件闸 / 纯页面功能写 ns.db.feat（等于默认值时存 nil），重载后生效
function ns.SetFeature(key, v)
    local f = BYKEY[key]
    if not f or not ns.db then return false end
    v = v and true or false
    local it = swItem(f)
    if f.set then
        local ok, err = pcall(f.set, v)
        if not ok and ns.Print then ns.Print(tostring(err)) end
    elseif it and type(it.set) == "function" then
        local ok, err = pcall(it.set, v)
        if not ok and ns.Print then ns.Print(tostring(err)) end
    else
        local t = featDB(true)
        if v == (f.def and true or false) then t[key] = nil else t[key] = v end
    end
    if v and f.mod then pcall(loadMod, f.mod) end
    return true
end

-- 职业专属 / HOLD 没进包 / 不可用的不显示
local function classOk(f) return not f.class or (ns.MyClass ~= nil and ns.MyClass() == f.class) end
local function pageThere(key)
    for _, p in ipairs(ns._Pages or {}) do
        if p.key == key then return not p.class or (ns.MyClass ~= nil and ns.MyClass() == p.class) end
    end
    return false
end
local function holdOk(f)
    if not f.hold then return true end
    for mod, files in pairs(ns._ModFiles or {}) do
        if files[f.hold] then return ns.ModHas ~= nil and ns.ModHas(mod, f.hold) end
    end
    return true   -- 内核文件：HOLD 没进包 = 文件根本没执行，由 avail 判断（各条自己写）
end
function ns.FeatureShown(f)
    if type(f) == "string" then f = BYKEY[f] end
    if not f or not classOk(f) or not holdOk(f) then return false end
    if f.pageFeat and not pageThere(f.page) then return false end
    if f.avail then
        local ok, v = pcall(f.avail)
        if not (ok and v) then return false end
    end
    return true
end

function ns.FeatureList(cat, all)
    local out = {}
    for _, f in ipairs(LIST) do
        if (not cat or f.cat == cat) and (all or ns.FeatureShown(f)) then out[#out + 1] = f end
    end
    return out
end

-- 要重载才生效的（文件闸 / 纯页面）：登录时的状态记一份，功能页顶部「N 项改动重载后生效」拿它比
function ns.FeatureNeedsReload(f)
    if type(f) == "string" then f = BYKEY[f] end
    return f ~= nil and (f.gate or f.pageFeat) and true or false
end
local boot
table.insert(ns.modules, function()
    boot = {}
    for _, f in ipairs(LIST) do
        if ns.FeatureNeedsReload(f) then boot[f.key] = ns.FeatureOn(f.key) end
    end
end)
function ns.FeaturePending()
    local out = {}
    if not boot then return 0, out end
    for _, f in ipairs(LIST) do
        if boot[f.key] ~= nil and boot[f.key] ~= ns.FeatureOn(f.key) and ns.FeatureShown(f) then out[#out + 1] = f end
    end
    return #out, out
end
-- 纯页面功能关了：左栏不出这一页（按登录时的状态，改了重载生效 —— 左栏在主窗口第一次打开时就排好了）
function ns.FeaturePageOff(page)
    local f = PAGEFEAT[page]
    if not f then return false end
    if boot and boot[f.key] ~= nil then return boot[f.key] == false end
    return ns.FeatureOff(f.key)
end

-- ================= 功能条目（按设计稿第 3 节分类；def = 现在的默认行为）=================
local F = ns.Feature
local function db() return ns.db end
local function classHas(file, name) return ns[name] ~= nil or (ns.ModHas ~= nil and ns.ModHas("class", file)) end
local function classDo(name, fn)
    local t = ns[name]
    if t then return fn(t) end
    if ns.ModLoad and ns.ModLoad("class", function() if ns[name] then fn(ns[name]) end end) and ns[name] then return fn(ns[name]) end
end
ns._ClassHas, ns._ClassDo = classHas, classDo   -- 11-20 Settings.lua 共用
local function groupThere() return ns.ModuleAvailable ~= nil and (ns.ModuleAvailable("group") or ns.ModuleLoaded("group")) and true or false end

-- ---------- 升级 ----------
F({ key = "plan", cat = "up", zh = "升级规划", en = "Leveling plan", pageFeat = true, page = "plan", def = true,
    dzh = "按等级排好的地图 / 地下城 / 任务线 / 技能 / 装备一页看完", den = "Zones, dungeons, quest lines, skills and gear by level" })
F({ key = "leveling", cat = "up", zh = "升级指引小窗", en = "Leveling guide window", sw = "plan.leveling", def = true, files = { "Leveling.lua" }, page = "plan",
    avail = function() return ns.LevelingShown ~= nil end,
    dzh = "满 60 级前登录自动显示推荐地图 / 地下城 / 任务线", den = "Shown on login until 60: suggested zones, dungeons, quest lines" })
F({ key = "chain", cat = "up", zh = "任务线追踪", en = "Quest line tracker", sw = "plan.chain", def = true, files = { "SideChains.lua", "SideChainsData.lua" }, page = "plan",
    avail = function() return ns.SideChains ~= nil and ns.SideChains.TrackerEnabled ~= nil end,
    dzh = "睡袋等任务线钉在屏幕上显示当前第几步，做完自动消失", den = "Pins the sleeping-bag style quest lines on screen until done" })
F({ key = "xpcheck", cat = "up", zh = "经验加成检查", en = "XP bonus check", sw = "xp.on", def = true, files = { "XpCheck.lua" }, page = "xp",
    avail = function() return ns.XpCheck ~= nil end,
    dzh = "帐篷 / 营火 / 食物 / 药剂 / 休息经验有没有、还剩多久，快没了提醒", den = "Tent / fire / food / elixir / rested: what you have and when it ends" })
F({ key = "xpprep", cat = "up", zh = "出发前清单", en = "Departure checklist", sw = "xp.prep", cfg = "xp", def = true, files = { "XpSupply.lua", "PageXp.lua" }, page = "xp",
    avail = function() return ns.XpCheck ~= nil and ns.XpCheck.DB ~= nil end,
    get = function() return ns.XpCheck.DB().prep ~= false end, set = function(v) ns.XpCheck.DB().prep = v and true or false end,
    dzh = "进主城 / 旅店时弹出经验加成和物资清单，离开自动收起", den = "Pops the XP-bonus and supplies checklist in towns / inns" })
F({ key = "camp", cat = "up", zh = "帐篷蹭露营", en = "Tent sharing", sw = "camp.on", def = true, files = { "Camp.lua" }, page = "xp",
    avail = function() return ns.Camp ~= nil and ns.Camp.Enabled ~= nil end,
    dzh = "指到别人的帐篷时弹窗问要不要密他求组拿露营经验", den = "Offers to whisper the owner when you mouse over a tent" })
F({ key = "trainnow", cat = "up", zh = "该学技能提醒", en = "Trainable spell reminder", sw = "trainnow.remind", def = true, files = { "TrainNow.lua", "TrainNowData.lua" }, page = "talent",
    avail = function() return ns.TrainNow ~= nil end,
    dzh = "进有职业训练师的城镇时，提醒这一级能学的技能", den = "Lists trainable spells when you enter a town with your trainer" })
F({ key = "lowrank", cat = "up", zh = "低级技能提醒", en = "Low-rank spell alert", cfg = "trainnow.lowrank", def = true, files = { "LowRank.lua" }, page = "talent",
    avail = function() return ns.LowRank ~= nil end,
    get = function() local R = ns.LowRank; return R.On() or R.WhisperOn() or R.PartyOn() end,
    set = function(v) local R = ns.LowRank; R.SetOn(v); R.SetWhisper(v); R.SetParty(v) end,
    dzh = "放了已经学会更高级的技能时提醒（自己 / 队友，细项在设置里）", den = "Alerts when you or teammates cast an outdated rank" })
-- 11-17「永久关闭」：升级时弹的「这一级点什么天赋」（PvPShout.lua 的框，LevelShare.lua 判断）—— 存档 ns.db.ui.lvlTalent（false = 关，/gi 升级天赋 同一个键）
F({ key = "lvltalent", cat = "up", zh = "升级天赋提示", en = "Level-up talent tip", def = true, page = "talent",
    avail = function() return ns.LevelShare ~= nil and ns.PvPShout ~= nil end,
    get = function() return not (db() and type(db().ui) == "table" and db().ui.lvlTalent == false) end,
    set = function(v)
        if ns.PvPShout and ns.PvPShout.SetNever then ns.PvPShout.SetNever("talent", not v); return end
        local d = db(); d.ui = d.ui or {}
        if v then d.ui.lvlTalent = nil else d.ui.lvlTalent = false end
    end,
    dzh = "升级时弹框提示这一级点什么天赋，点「去点」打开天赋面板", den = "On level-up, shows which talent to take and opens the talent panel" })
F({ key = "ach", cat = "up", zh = "成就 · 传承", en = "Achievements", pageFeat = true, page = "ach", def = true,
    dzh = "传承进度和还差哪些成就", den = "Heritage progress and the achievements you still need" })

-- ---------- 副本 ----------
F({ key = "loot", cat = "dungeon", zh = "掉落 · 心愿单", en = "Loot & wishlist", pageFeat = true, page = "loot", def = true,
    dzh = "各副本首领掉落、心愿单、副本任务和入口", den = "Boss loot, wishlist, dungeon quests and entrances" })
F({ key = "dnav", cat = "dungeon", zh = "副本导航", en = "Dungeon navigator", sw = "dnav.on", def = true, files = { "DungeonNav.lua", "DungeonNavData.lua", "DungeonNavMap.lua" },
    avail = function() return ns.DungeonNav ~= nil end,
    dzh = "进副本弹面板：首领顺序、怎么走、地图，击杀自动推进", den = "In dungeons: boss order, route and map; advances on kills" })
F({ key = "loottip", cat = "dungeon", zh = "掉落提示", en = "Loot tips", gate = true, def = true, files = { "LootTip.lua" }, page = "loot",
    dzh = "物品提示写掉落来源，心愿单装备进本 / 开打 / 拾取时提醒，稀有怪提示掉落", den = "Drop source in tooltips, wishlist alerts, rare mob drops" })
-- 11-17 用户「这些弹出的功能都确保能永久关闭」：心愿单提醒里屏幕中间的大字 + 提示音单独一个开关（存档 ns.db.ui.wishCenter，nil = 开；
--   LootTip.lua notice() 读同一个键，设置页「窗口与提醒」也走这里），关了聊天框那一行照旧
F({ key = "wishcenter", cat = "dungeon", zh = "心愿单屏幕提醒", en = "Wishlist on-screen alert", def = true, page = "loot",
    get = function() return not (db() and type(db().ui) == "table" and db().ui.wishCenter == false) end,
    set = function(v)
        local d = db(); d.ui = d.ui or {}
        if v then d.ui.wishCenter = nil else d.ui.wishCenter = false end
        if not v and ns.CloseHint then
            ns.CloseHint("wishCenter", ns.L("心愿单屏幕中间的提醒已关闭（聊天框照旧）。找回：GI 菜单 → 窗口与提醒 → 心愿单屏幕提醒，或设置 → 功能",
                "Wishlist on-screen alert off (chat line stays). Bring it back: GI menu > Windows & alerts > Wishlist alert, or Settings > Features"))
        end
    end,
    dzh = "心愿单装备进本 / 开打 / 掉落时屏幕中间大字 + 提示音（关了只在聊天框说）", den = "Big on-screen text + sound for wishlist items (off = chat only)" })

-- ---------- 装备 ----------
F({ key = "gear", cat = "gear", zh = "推荐装备", en = "Gear picks", pageFeat = true, page = "gear", def = true,
    dzh = "按等级和专精推荐每个部位去哪拿", den = "Per-slot gear picks by level and spec, and where to get them" })
F({ key = "bis", cat = "gear", zh = "装备角标", en = "BiS corner icons", sw = "bis.on", def = true, files = { "BisCorner.lua" }, page = "gear",
    avail = function() return ns.BisCorner ~= nil end,
    dzh = "角色面板装备格上标出这一级的推荐装备", den = "Marks this level's best item on character panel slots" })
F({ key = "ilvl", cat = "gear", zh = "装等显示", en = "Item levels", sw = "ilvl.on", def = true, files = { "ItemLevel.lua" }, page = "gear",
    avail = function() return ns.ItemLevel ~= nil end,
    dzh = "鼠标提示 / 角色面板每格 / 背包里显示装等", den = "Item levels in tooltips, character panel and bags" })
F({ key = "tier", cat = "gear", zh = "T1 套装", en = "Tier 1 sets", pageFeat = true, page = "tier", def = true,
    dzh = "各职业 T1 套装部件、属性和掉落", den = "Tier 1 pieces, bonuses and drops per class" })

-- ---------- 职业 ----------
F({ key = "talent", cat = "class", zh = "天赋", en = "Talents", pageFeat = true, page = "talent", def = true,
    dzh = "天赋模拟、导入配点码、热门配点、按计划逐点学", den = "Talent planner, import codes, popular builds" })
F({ key = "cguide", cat = "class", zh = "职业攻略", en = "Class guide", pageFeat = true, page = "cguide", def = true,
    dzh = "本职业的入门要点、PVP 和推荐链接", den = "Class basics, PvP tips and links" })
F({ key = "rot", cat = "class", zh = "手法", en = "Rotation", pageFeat = true, page = "rot", def = true,
    dzh = "按当前天赋系的技能优先级和手法讲解", den = "Priority list and rotation notes for your spec" })
F({ key = "rotboard", cat = "class", zh = "手法钉板", en = "Rotation board", sw = "rot.board", def = false, files = { "KeysRot.lua", "KeysRotData.lua" }, page = "rot", mod = "class",
    avail = function() return classHas("KeysRot.lua", "KeysRot") end,
    get = function() return db() ~= nil and db().keysBoard and true or false end,
    set = function(v)
        classDo("KeysRot", function(KR) KR.Toggle(v) end)
        if not v and db().keysHud then classDo("KeysHud", function(KH) KH.Toggle(false) end) end
    end,
    dzh = "屏幕上一个小框：现在该按哪个技能、哪个键", den = "A small frame: what to press now and which key" })
F({ key = "rothud", cat = "class", zh = "决策 HUD", en = "Decision HUD", sw = "rot.hud", def = false, files = { "KeysHud.lua" }, page = "rot", mod = "class",
    avail = function() return classHas("KeysHud.lua", "KeysHud") end,
    get = function() return db() ~= nil and db().keysHud and true or false end,
    set = function(v) classDo("KeysHud", function(KH) KH.Toggle(v) end) end,
    dzh = "钉板下的资源 / 持续伤害 / 冷却 / 触发面板（会顺带打开钉板）", den = "Resource / DoT / cooldown / proc panel under the board" })
F({ key = "keys", cat = "class", zh = "键位", en = "Keys", pageFeat = true, page = "keys", def = true,
    dzh = "按手法推荐键位，逐个设置、虚拟键盘", den = "Key suggestions per rotation, one at a time, virtual keyboard" })
F({ key = "cdmkeys", cat = "class", zh = "冷却管理器键位", en = "Cooldown Manager keybinds", sw = "keys.cdm", def = true, files = { "KeysCdm.lua" }, page = "keys",
    avail = function() return classHas("KeysCdm.lua", "KeysCdm") end,
    dzh = "官方冷却管理器图标上显示快捷键", den = "Shows keybinds on the Cooldown Manager icons" })
F({ key = "macro", cat = "class", zh = "宏库", en = "Macros", pageFeat = true, page = "macro", def = true,
    dzh = "本职业常用宏，一键建到宏列表", den = "Common class macros, one click to create" })
F({ key = "pet", cat = "class", zh = "猎人宠物", en = "Hunter pets", class = "Hunter", pageFeat = true, page = "pet", def = true,
    dzh = "宠物技能、去哪抓、会教的野兽", den = "Pet skills, where to tame, which beasts teach what" })
F({ key = "ammo", cat = "class", zh = "弹药商", en = "Ammo vendors", class = "Hunter", pageFeat = true, page = "ammo", def = true,
    dzh = "最近的弓箭 / 子弹商人", den = "Nearest arrow / bullet vendors" })
F({ key = "ammoremind", cat = "class", zh = "弹药提醒", en = "Ammo reminder", class = "Hunter", sw = "ammo.on", def = true, files = { "AmmoRemind.lua" }, page = "ammo", mod = "class",
    avail = function() return classHas("AmmoRemind.lua", "AmmoRemind") end,
    dzh = "箭 / 子弹快没了提醒，商人那里一键补满", den = "Low-ammo reminder, one-click top-up at vendors" })
F({ key = "conj", cat = "class", zh = "造水", en = "Conjure", class = "Mage", pageFeat = true, page = "conj", def = true,
    dzh = "按对方等级造对应档的水 / 面包", den = "Conjure the right rank of food / water for a player's level" })
F({ key = "conjpop", cat = "class", zh = "密语要水弹窗", en = "Water request pop-up", class = "Mage", sw = "conj.pop", def = true, files = { "MageConjure.lua" }, page = "conj",
    avail = function() return ns.MageConjure ~= nil end,
    dzh = "有人密你要水 / 面包时弹窗，一键造对应的档", den = "Pops a window when someone whispers for water" })
F({ key = "pally", cat = "class", zh = "一键祝福", en = "One-click blessings", class = "Paladin", sw = "pally.page", def = true, files = { "PallyBless.lua" }, page = "pally",
    avail = function() return classHas("PallyBless.lua", "PallyBless") end,
    dzh = "在「职业」里显示一键祝福页（按职业分配祝福）", den = "Shows the Blessings page (assign blessings by class)" })
F({ key = "pallyfloat", cat = "class", zh = "祝福悬浮按钮", en = "Blessing button", class = "Paladin", sw = "pally.float", def = true, files = { "PallyBless.lua" }, page = "pally", mod = "class",
    avail = function() return classHas("PallyBless.lua", "PallyBless") end,
    dzh = "组队时屏幕上一个一键祝福按钮", den = "A one-click blessing button while grouped" })
F({ key = "pallyaura", cat = "class", zh = "光环提醒", en = "Aura reminder", class = "Paladin", sw = "pally.aura", def = true, files = { "AuraRemind.lua" }, page = "pally", mod = "class",
    avail = function() return classHas("AuraRemind.lua", "AuraRemind") end,
    dzh = "圣骑士光环没开时提醒，一键开光环", den = "Reminds you when no paladin aura is on" })
F({ key = "liminal", cat = "class", zh = "阈限传送", en = "Liminal teleport", class = "Mage", pageFeat = true, page = "liminal", def = true,
    dzh = "法师阈限传送的地点和材料", den = "Mage liminal teleport spots and reagents" })
-- 11-18 GI-303 一键给路人上BUFF（AutoBuff.lua，HOLD）：法师 / 牧师 / 德鲁伊三个职业用（class 只能写一个 → 职业判断放 avail）；新功能默认关
F({ key = "autobuff", cat = "class", zh = "一键给路人上BUFF", en = "One-key buffing", def = false, files = { "AutoBuff.lua" }, mod = "class", hold = "AutoBuff.lua",
    avail = function() return ns.MyClass ~= nil and ns.AUTOBUFF_CLS ~= nil and ns.AUTOBUFF_CLS[ns.MyClass()] == true and classHas("AutoBuff.lua", "AutoBuff") end,
    get = function() return db() ~= nil and type(db().autoBuff) == "table" and db().autoBuff.on == true end,
    set = function(v)
        if type(db().autoBuff) ~= "table" then db().autoBuff = {} end
        db().autoBuff.on = v and true or false   -- ⛔ 和 AutoBuff.lua 的 AB.SetOn 同一个键
        classDo("AutoBuff", function(AB) AB.SetOn(v) end)
    end,
    dzh = "法师 / 牧师 / 德鲁伊：屏幕上一个按钮，自动挑附近缺你 BUFF 的玩家，按一下（或快捷键）给他上一个", den = "Mage / Priest / Druid: a button that picks nearby players missing your buff; press to buff one" })

-- ---------- 专业 ----------
F({ key = "prof", cat = "prof", zh = "专业助手", en = "Profession helper", pageFeat = true, page = "prof", def = true,
    dzh = "每个专业最省材料的冲级路线、材料清单", den = "Cheapest leveling route and shopping list per profession" })
F({ key = "reagent", cat = "prof", zh = "材料来源提示", en = "Material sources", sw = "reagent.on", def = true, files = { "ReagentSrc.lua", "ReagentSrcData.lua" }, page = "prof",
    avail = function() return ns.ReagentSrcTip ~= nil end,
    dzh = "材料鼠标提示写从哪来（采集点 / 掉落的怪 / 商人）", den = "Material tooltips show where to get them" })
F({ key = "profseen", cat = "prof", zh = "配方记录", en = "Recipe sightings", gate = true, def = true, files = { "ProfSeen.lua" }, page = "prof",
    dzh = "商人 / 拾取时记下见过的图纸，专业页显示实测出处", den = "Records recipes seen at vendors / in loot for the profession page" })

-- ---------- 背包 ----------
F({ key = "trash", cat = "bag", zh = "清背包", en = "Bag cleanup", pageFeat = true, page = "trash", def = true,
    dzh = "按价值从低到高列出背包物品，一键摧毁最便宜的", den = "Lists bag items cheapest first, one click to destroy" })
F({ key = "trashfull", cat = "bag", zh = "背包满提示", en = "Bags-full hint", sw = "trash.full", def = true, page = "trash",
    avail = function() return ns.BagHas ~= nil and ns.BagHas("Trash.lua") end,
    dzh = "背包满时在聊天框提示一次可以用「清背包」", den = "One chat hint to use Bag cleanup when bags are full" })
F({ key = "selljunk", cat = "bag", zh = "卖垃圾", en = "Sell junk", sw = "sell.panel", def = true, files = { "SellJunk.lua", "MerchantDockUI.lua" }, page = "trash",
    avail = function() return ns.BagHas ~= nil and ns.BagHas("SellJunk.lua") end,
    dzh = "打开商人时在旁边弹「卖垃圾」面板，点一下才卖", den = "A Sell junk panel beside merchants; sells only when you click" })
F({ key = "bagbuttons", cat = "bag", zh = "背包按钮", en = "Bag buttons", sw = "bagbtn.gen", def = true, files = { "BagButtons.lua" }, page = "trash",
    avail = function() return ns.BagButtons ~= nil end,
    dzh = "背包窗口上放「清背包」「卖垃圾」两个小按钮", den = "Bag cleanup / Sell junk buttons on your bag window" })

-- ---------- 社交 ----------
F({ key = "group", cat = "social", zh = "组队（附近任务）", en = "Group up (nearby quests)", sw = "group.load", def = true, mod = "group",
    avail = groupThere,
    dzh = "登录就加载组队：和附近同任务的人互相看到进度、一起组", den = "Loads Group up at login: see nearby players on your quests" })
F({ key = "buffask", cat = "social", zh = "要 BUFF", en = "Ask for buffs", sw = "buffask.on", cfg = "group", def = true, files = { "BuffAsk.lua" }, mod = "group",
    avail = groupThere,
    get = function() return not (db() and type(db().buffAsk) == "table" and db().buffAsk.on == false) end,
    set = function(v)
        if ns.BuffAsk then return ns.BuffAsk.SetOpt("on", v) end
        if type(db().buffAsk) ~= "table" then db().buffAsk = {} end
        if v then db().buffAsk.on = nil else db().buffAsk.on = false end   -- ⛔ 和 BuffAsk.lua 的 BA.SetOpt 一致（默认开 = 存 nil）
    end,
    dzh = "碰到能给你缺的 BUFF 的人弹框问（点了才密），副本里缺了提醒", den = "Prompts when someone nearby can give a buff you lack" })
F({ key = "mage", cat = "social", zh = "法师吃喝", en = "Mage food & water", sw = "mage.on", def = false, files = { "MageWater.lua" }, mod = "mage",
    avail = groupThere,
    get = function() local d = db() and db().dchat; return type(d) == "table" and type(d.rec) == "table" and d.rec.mageAsk and true or false end,
    set = function(v)
        if ns.MageWater then return ns.MageWater.SetOn(v) end
        local d = db()
        if type(d.dchat) ~= "table" then d.dchat = {} end
        if type(d.dchat.rec) ~= "table" then d.dchat.rec = {} end
        d.dchat.rec.mageAsk = v and true or nil   -- ⛔ 和 MageWater.lua 的 MW.SetOn 同一个键
    end,
    dzh = "不是法师：帮你找法师要水；是法师：有人要时提醒、一键放入", den = "Ask mages for water, or hand it out if you are one" })
F({ key = "guildchat", cat = "social", zh = "聊天里显示等级", en = "Levels in chat", sw = "guild.chat", def = true, files = { "GuildChatLevel.lua" },
    avail = function() return ns.GuildChatLevel ~= nil and not ns.GuildChatLevel.Paused end,
    dzh = "公会 / 密语 / 小队消息前显示说话人的等级和地区", den = "Shows the speaker's level (and zone) in guild / whisper / party chat" })
F({ key = "lvlshare", cat = "social", zh = "升级播报", en = "Level-up shout", cfg = "guild.shout.ask", def = true, files = { "LevelShare.lua" },
    avail = function() return ns.LevelShare ~= nil end,
    get = function() return (db() and db().lvlShare or "ask") ~= "off" end,
    set = function(v)
        local cur = db().lvlShare or "ask"
        if v and cur == "off" then ns.LevelShare.SetMode("ask") elseif not v and cur ~= "off" then ns.LevelShare.SetMode("off") end
    end,
    dzh = "升级时发到公会频道（6 级起，逢 5 级自动、其他弹框问）", den = "Shouts level-ups to guild chat (from 6)" })
F({ key = "lvlmute", cat = "social", zh = "屏蔽别人的升级播报", en = "Hide others' level-up spam", sw = "guild.mute", def = false, files = { "LevelMute.lua" },
    avail = function() return ns.LevelMute ~= nil end,
    dzh = "隐藏各家插件在公会 / 队伍里刷的升级 / 入会欢迎", den = "Hides addon level-up / welcome spam in guild and group chat" })
F({ key = "pvpshout", cat = "social", zh = "野外 PvP 通报", en = "World PvP alerts", cfg = "guild.pvp.kill", def = true, files = { "PvPShout.lua" },
    avail = function() return ns.PvPShout ~= nil end,
    get = function() return ns.PvPShout.On("kill") or ns.PvPShout.On("death") end,
    set = function(v) ns.PvPShout.Set("kill", v); ns.PvPShout.Set("death", v) end,
    dzh = "野外荣誉击杀 / 被玩家击杀时弹框，点了才发到公会 / 队伍", den = "Offers to announce world kills / deaths to guild or group" })
F({ key = "tentshout", cat = "social", zh = "帐篷通报", en = "Tent announce", cfg = "guild.pvp.tent", def = true, files = { "PvPShout.lua" },
    avail = function() return ns.PvPShout ~= nil and ns.PvPShout.OfferTent ~= nil end,
    get = function() return ns.PvPShout.On("tent") end,
    set = function(v) ns.PvPShout.Set("tent", v) end,
    dzh = "自己放帐篷时弹框问要不要通报公会 / 队伍（带坐标），点了才发", den = "Offers to announce your tent to guild or group (with location)" })
F({ key = "trade", cat = "social", zh = "交易回执", en = "Trade receipt", sw = "trade.on", def = true, files = { "TradeReceipt.lua" },
    avail = function() return ns.TradeReceipt ~= nil end,
    dzh = "交易成功后私聊对方写明给了什么", den = "Whispers your partner what you gave after a trade" })
F({ key = "invite", cat = "social", zh = "右键邀请入会", en = "Invite to guild", sw = "guild.invite", def = true, files = { "InviteMenu.lua" },
    avail = function() return ns.InviteMenu ~= nil and ns.InviteMenu.Enabled ~= nil end,
    dzh = "右键玩家菜单里加「邀请入会」", den = "Adds Invite to guild to the player right-click menu" })
F({ key = "mageask", cat = "social", zh = "右键找法师要水", en = "Ask a mage (menu)", sw = "guild.mageAsk", def = true, files = { "MageAskMenu.lua" },
    avail = function() return ns.MageAskMenu ~= nil and ns.MageAskMenu.Enabled ~= nil end,
    dzh = "右键法师菜单里加「找他要水」", den = "Adds Ask for water to a mage's right-click menu" })
F({ key = "buffaskmenu", cat = "social", zh = "右键找他要BUFF", en = "Ask for buffs (menu)", sw = "guild.buffAsk", def = true, files = { "BuffAskMenu.lua" },
    avail = function() return ns.BuffAskMenu ~= nil and ns.BuffAskMenu.Enabled ~= nil end,
    dzh = "右键能给你缺的 BUFF 的人，菜单里加「找他要BUFF」", den = "Adds Ask for buffs to the right-click menu of players who can buff you" })
F({ key = "cityplates", cat = "social", zh = "进城隐藏姓名板", en = "Hide nameplates in towns", sw = "perf.cityPlates", def = true, files = { "CityPlates.lua" },
    avail = function() return ns.CityPlates ~= nil end,
    dzh = "进主城自动隐藏友方玩家姓名板，出城恢复（城里人多会卡）", den = "Hides friendly nameplates in capitals, restores outside" })
F({ key = "layer", cat = "social", zh = "位面", en = "Layers", sw = "layer.on", def = true, files = { "Layer.lua", "LayerGuild.lua", "LayerHop.lua", "PageLayer.lua" }, page = "layer",
    avail = function() return ns.Layer ~= nil and ns.Layer.DB ~= nil end,
    get = function() return not (db() and type(db().layer) == "table" and db().layer.on == false) end,
    set = function(v)
        local d = ns.Layer.DB()
        d.on = v and true or false   -- ⛔ 和位面页那个勾一样（PageLayer.lua：D().on）
        if ns.Layer.SyncPub then pcall(ns.Layer.SyncPub) end   -- GI-287：关了退插件频道，开了按图加回
        if v and ns.Layer.Beat then pcall(ns.Layer.Beat, true) end
    end,
    dzh = "识别当前位面、公会位面互通、换到最优层", den = "Detects your layer, shares with guild, helps you switch" })

-- ---------- 资讯 ----------
F({ key = "news", cat = "info", zh = "资讯", en = "News", pageFeat = true, page = "news", def = true,
    dzh = "《无限》官方改动和新闻", den = "Official changes and news" })
F({ key = "guide", cat = "info", zh = "攻略", en = "Guides", pageFeat = true, page = "guide", def = true,
    dzh = "分职业 / 专业攻略和视频", den = "Class and profession guides" })
F({ key = "board", cat = "info", zh = "共建", en = "Feedback board", pageFeat = true, page = "board", def = true,
    dzh = "玩家提的需求和进度，提 BUG", den = "Player requests, progress and bug reports" })
F({ key = "adv", cat = "info", zh = "进阶", en = "Advanced", pageFeat = true, page = "adv", def = true,
    dzh = "网站 / 小程序、我的升级报告、导出数据", den = "Website / mini program, leveling report, data export" })
F({ key = "whatsnew", cat = "info", zh = "新版说明", en = "What's new", gate = true, def = true, files = { "WhatsNew.lua", "WhatsNewData.lua" },
    dzh = "每个新版本登录时弹一次更新内容（/gi 更新 随时看）", den = "Shows the update notes once per version" })
F({ key = "report", cat = "info", zh = "我的升级报告", en = "Leveling report", gate = true, def = true, files = { "Report.lua" }, page = "adv", hold = "Report.lua",
    dzh = "把升级记录生成链接，网站出定制路线（/gi report）", den = "Turns your leveling log into a link for a custom route" })

-- ---------- 设置 ----------
F({ key = "minimap", cat = "set", zh = "小地图按钮", en = "Minimap button", sw = "ui.minimap", def = true,
    avail = function() return ns.SetMinimapShown ~= nil end,
    dzh = "小地图边上的 GearInsight 按钮（右键快捷菜单）", den = "The GearInsight minimap button (right-click menu)" })
F({ key = "perfguard", cat = "set", zh = "自动卡顿检测", en = "Auto lag detection", sw = "perf.guard", def = true, files = { "PerfGuard.lua" },
    avail = function() return ns.PerfGuard ~= nil end,
    dzh = "一直量帧率，卡顿是组队引起的就自动关掉组队", den = "Watches frame times; turns Group off if it causes lag" })
F({ key = "obs", cat = "set", zh = "众包观测", en = "Crowdsourced data", gate = true, def = true, files = { "ObsProf.lua", "ObsVendor.lua", "ObsPet.lua", "ObsDungeon.lua" },
    avail = function() return ns.ObsPet ~= nil or ns.ObsProf ~= nil or ns.ObsVendor ~= nil or ns.ObsDungeon ~= nil or ns.FeatureOff("obs") end,
    dzh = "记商人标价 / 野兽位置 / 首领顺序等，随导出数据匿名上传补全数据", den = "Records vendor prices, beasts, boss order for the data export" })
F({ key = "castshare", cat = "set", zh = "贡献施法频率", en = "Share cast frequency", sw = "rot.share", def = false, files = { "KeysCast.lua" }, page = "rot", mod = "class",
    avail = function() return classHas("KeysCast.lua", "KeysCast") end,
    get = function() return db() ~= nil and db().castCollect == true end,
    set = function(v) classDo("KeysCast", function(KC) KC.Set(v) end) end,
    dzh = "匿名记录技能和次数，用来做「顶尖手法 · 公测版」", den = "Anonymously records casts to build the beta rotation" })
