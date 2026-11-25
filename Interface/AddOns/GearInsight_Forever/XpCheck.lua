-- HOLD：经验加成检查（11-09 用户「同步构思一个这个经验 buff 检查器……露营的 buff、睡袋、包里有没有、任务做不做、食物 buff……
--   一个是检查有没有，二是检查还有多长时间要补，给出很好的提示，整个功能都可以开关」→ 方案确认「可以，开工」）
--   查五类：帐篷经验（含「强化休息」冷却）/ 营火 / 睡袋（背包、精神饱满层数、物品冷却、任务线进度）/ 经验食物（buff、包里、能做）/ 休息经验
--   每项：有没有 + 剩多久 + 缺了怎么补。提示三种：
--     ① 小窗（默认只在缺东西或快到期时自动出来，全齐自己收起；可改一直显示）；点一行出「怎么补」
--     ② 到期提醒：剩 10 分钟 / 2 分钟 / 掉了各一次，屏幕中间一行；战斗中不弹（出战斗补报），副本 / 战场里不提营地类
--     ③ 登录 / 升级 / 出副本聊天框一行汇总；/gi xp 看详情
--   ⛔ 不替玩家吃东西 / 铺睡袋（受保护操作，也不该替）；不发任何密语。
--   已知 ID（用户存档 camp.probe 11-08）：营火在附近 1283391、温馨营火 1229739、强化休息 1229451；睡袋物品 211527。
--   帐篷 = 露营增益 1229741（11-09 探针）；睡袋「精神饱满」/ 经验食物 的 buff ID 还没定：先按名字 + 鼠标提示里带「经验」认，探针把真实 ID 记进存档（/gi xp probe）
local _, ns = ...
local L = ns.L

local XC = {}
ns.XpCheck = XC

XC.IDS = {
    lockout = { [1229451] = true },                     -- 强化休息：1 小时内拿不到帐篷经验
    fire = { [1229739] = true, [1283391] = true },      -- 温馨营火 / 营火在附近
    tent = { [1229741] = true },                        -- 露营增益（11-09 用户 /gi xp probe：29m，和强化休息同时挂）
    bag = { [429959] = true }, food = {},               -- 精神饱满 429959（11-17 DB2 核对：每层 +1% 打怪 + 任务经验，2 小时）
    passive = { [1243969] = true, [1225478] = true },   -- 进食充分经验值加成（让食物带经验的条件光环）/ 传承「精神抖擞」：提示带经验，但不是一项加成，别当成食物
}
XC.NAMES = {
    lockout = { "强化休息", "強化休息" },
    fire = { "营火", "營火", "[Cc]ampfire" },
    tent = { "奖励经验", "獎勵經驗", "露营", "露營", "[Tt]ent", "[Cc]amping" },
    bag = { "精神饱满", "精神飽滿", "[Ww]ell [Rr]ested" },
    food = { "进食充分", "進食充分", "[Ww]ell [Ff]ed" },
}
XC.BAG_ITEM = 211527          -- 舒适的睡袋
XC.WOOD, XC.FLINT = 4470, 4471 -- 普通木柴 / 燧石和火绒
XC.BAG_STACKS = 3
-- 11-09 用户「搞成正式服那种，平时透明，快没了就弹出来提醒（15分钟）帐篷5分钟，睡袋看三层」+「还有5分钟开始高亮，10分钟开始出现」：
--   show = 剩多少秒浮出来（提醒条出现 + 聊天框提醒一次），hi = 剩多少秒开始高亮闪（再提醒一次）；睡袋不满 3 层直接出来并高亮
XC.TH = { default = { show = 900, hi = 300 }, tent = { show = 600, hi = 300 }, food = { show = 180, hi = 60 } }   -- 11-09「食物还剩3分钟再提醒」
local function th(k) return XC.TH[k] or XC.TH.default end
XC.Th = th
XC.KEYS = { "tent", "fire", "bag", "food", "boost", "kit", "rest" }
XC.TITLE = {
    tent = { "帐篷经验", "Tent XP" }, fire = { "营火", "Campfire" }, bag = { "睡袋", "Sleeping bag" },
    food = { "经验食物", "XP food" }, boost = { "经验药剂/活动", "XP potion/event" }, kit = { "药剂/武器油", "Elixir/oil" }, rest = { "休息经验", "Rested XP" },
}
XC.ICON = {
    tent = "Interface\\Icons\\Spell_Nature_Tranquility", fire = "Interface\\Icons\\Spell_Fire_Fire", bag = "Interface\\Icons\\Spell_Nature_Sleep",
    food = "Interface\\Icons\\INV_Misc_Food_15", boost = 134803, kit = "Interface\\Icons\\INV_Potion_30", rest = "Interface\\Icons\\Spell_Nature_Sleep",
}

-- ---------- 其他加经验的（boost）+ 合计 ----------
-- 11-17 用户「练级BUFF检查器，加上经验的一起来检查」。盘点《无限》客户端 DB2（wago 1.60.1.70790 / 70938）里所有
--   光环 200「经验获取 %」/ 291「任务经验 %」/ 447「击杀某类生物经验 %」的法术，除了已有的睡袋 / 食物，还有：
--   无尽经验药剂 1328127（物品 289334，+200% 1 小时，70938 新加，客户端标价 3 银 80 铜，哪里卖还没核实）；
--   大法师的智慧 1292997（颈部「大法师的多面坠饰」273049 使用：杀亡灵 +10% 5 分钟，6 小时一次，达拉然城·大法师之影掉落，30 级）；
--   大法师的感知 1293736（同效果，没找到给它的物品）；活动类：智慧烈风 335924（国服专属 +50%）/ 探索之悦 436412（+50%）/
--   魔兽综艺汇——启迪烈风！430496（+50% 5 分钟）/ 冒险等待着你 362859（任务经验 +100%）—— 拿不到，只在身上有的时候显示。
--   每条「光环:加多少:范围:物品:类:要求等级:中文名:英文名」；范围 a 打怪 + 任务 / k 只打怪 / q 只任务 / u 只杀亡灵；类 p 药剂（包里有没喝 = 红 + 用）/ t 饰品（戴着能用 = 灰 + 用）/ e 活动
XC.BOOST_SRC = "1328127:200:a:289334:p:1:无尽经验药剂:Elixir of Endless Experience;1292997:10:u:273049:t:30:大法师的智慧:Archmagister's Wisdom;"
    .. "1293736:10:u:0:e:1:大法师的感知:Archmagister's Perception;335924:50:a:0:e:1:智慧烈风:Winds of Wisdom;436412:50:a:0:e:1:探索之悦:Discoverer's Delight;"
    .. "430496:50:a:0:e:1:魔兽综艺汇——启迪烈风！:WoW Variety Show;362859:100:q:0:e:1:冒险等待着你:Adventure Awaits"
XC.FOOD_PCT, XC.BAG_PCT = 5, 1   -- DB2：进食充分经验值加成 1243969 打怪 +5%（不加任务）；精神饱满 429959 每层 +1%（打怪 + 任务）
XC.TH.boost = { show = 180, hi = 60 }
local boostList, boostAura
function XC.BoostData()
    if not boostList then
        boostList, boostAura = {}, {}
        for aura, pct, sc, item, cat, lv, zh, en in XC.BOOST_SRC:gmatch("([0-9]+):([0-9]+):(%a):([0-9]+):(%a):([0-9]+):([^:]+):([^;]+)") do
            local e = { aura = tonumber(aura), pct = tonumber(pct), sc = sc, item = tonumber(item), cat = cat, lv = tonumber(lv), zh = zh, en = en }
            boostList[#boostList + 1] = e
            boostAura[e.aura] = e
        end
    end
    return boostList, boostAura
end
local SCOPE = { a = { "", "" }, k = { "打怪", "kills " }, q = { "任务", "quests " }, u = { "杀亡灵", "Undead kills " } }
-- 提示里「经验 … N%」的 N（食物 / 认不出的经验增益用；读不到返回 nil）
local function pctOf(tip)
    if type(tip) ~= "string" then return nil end
    local s = tip:match("经验(.*)") or tip:match("經驗(.*)") or tip:match("[Ee]xperience(.*)")
    return s and tonumber(s:match("([0-9]+)%%")) or nil
end
XC.PctOf = pctOf

-- ---------- 练级消耗品：药剂 + 武器油 / 磨刀石（kit）----------
-- 11-17 用户分享抖音「魔兽无限服只要 6 银币，战力提升 50%，练级速度提升 20%」+「这个做个功能到练级BUFF里，这样可以主动的在开始练级前准备好」。
--   视频讲的是三件低级消耗品：初级奥法药剂（拍卖约 1 银）+ 初级巫师之油（约 2 银）+ 烤鼠尾鱼（约 3 银）；物理职业换成磨刀石 + 力量 / 敏捷药剂 + 加属性食物。
--   食物那份上面「经验食物」已经管（烤鼠尾鱼本来就在经验食物表里），这里只补「药剂 + 武器强化」两样。
--   核对（《无限》客户端 DB2，wago.tools 1.60.1.70790：ItemXItemEffect → SpellEffect / SpellItemEnchantment）：
--     初级奥法药剂 247754 → 光环 1245244「法术伤害 +5」30 分钟，1 级能喝；初级巫师之油 20744 → 武器临时附魔 2623「法伤 / 治疗 +8」30 分钟，5 级；
--     坚固的磨刀石 7964 → 磨快 +6 30 分钟，《无限》改成 25 级能用（经典旧服 35）；食人魔力量药剂 3391 → 光环 3164 力量 +8 一小时，20 级。
--   ⛔ 视频「战力 +50% / 练级速度 +20%」是 25 级德鲁伊一发愤怒 37→52 的单次实测 + 自己推算，插件里不写这两个数，只写每样实打实加多少。
--   状态：生效中 = ok（剩 ≤3 分钟 warn）；包里有没用 = miss（红，点页里的「用」或背包右键）；包里没有 = info（灰，可选、要花钱，跟营火一样不算「缺」）。
--   10 级前不提（掉级快、不值当）；副本里只显示生效中的，不提缺。
XC.KIT_MIN_LV = 10
XC.TH.kit = { show = 180, hi = 60 }
-- 物品表（内存预算：写成一串字、第一次用到才拆成表）。每条「物品:光环:要求等级:类:加多少:中文名:英文名」，光环 0 = 武器临时附魔（读 GetWeaponEnchantInfo）
--   类：sp 法伤药剂 / str 力量 / agi 敏捷 / oil 巫师之油（法伤）/ sharp 磨刀石（利器）/ blunt 平衡石（钝器）
XC.KIT_SRC = "247754:1245244:1:sp:5:初级奥法药剂:Minor Arcane Elixir;250342:1250971:25:sp:15:次级奥法药剂:Lesser Arcane Elixir;9155:11390:37:sp:20:奥法药剂:Arcane Elixir;"
    .. "13454:17539:47:sp:35:强效奥法药剂:Greater Arcane Elixir;2454:2367:1:str:4:初级力量药剂:Elixir of Minor Strength;3391:3164:20:str:8:食人魔力量药剂:Elixir of Ogre's Strength;"
    .. "9206:11405:48:str:25:强效力量药剂:Elixir of Greater Strength;2457:2374:2:agi:4:初级敏捷药剂:Elixir of Minor Agility;3390:3160:18:agi:8:次级敏捷药剂:Elixir of Lesser Agility;"
    .. "8949:11328:27:agi:15:敏捷药剂:Elixir of Agility;9187:11334:38:agi:25:强效敏捷药剂:Elixir of Greater Agility;"
    .. "20744:0:5:oil:8:初级巫师之油:Minor Wizard Oil;20746:0:30:oil:16:次级巫师之油:Lesser Wizard Oil;20750:0:40:oil:24:巫师之油:Wizard Oil;20749:0:45:oil:36:卓越巫师之油:Brilliant Wizard Oil;"
    .. "2862:0:1:sharp:2:劣质磨刀石:Rough Sharpening Stone;2863:0:5:sharp:3:粗制磨刀石:Coarse Sharpening Stone;2871:0:15:sharp:4:重磨刀石:Heavy Sharpening Stone;"
    .. "7964:0:25:sharp:6:坚固的磨刀石:Solid Sharpening Stone;12404:0:35:sharp:8:致密磨刀石:Dense Sharpening Stone;3239:0:1:blunt:2:劣质平衡石:Rough Weightstone;"
    .. "3240:0:5:blunt:3:粗制平衡石:Coarse Weightstone;3241:0:15:blunt:4:重平衡石:Heavy Weightstone;7965:0:25:blunt:6:坚固的平衡石:Solid Weightstone;12643:0:35:blunt:8:致密平衡石:Dense Weightstone"
-- 不推荐买、但喝了也算「有药剂」的光环：次级奥法（旧 217398）/ 火焰 / 冰霜 / 暗影强化 / 猫鼬 / 蛮力 /《无限》新次级智力 / 力量 / 智力药剂
XC.KIT_AURA_EXTRA = "439959 7844 21920 11474 17538 17537 1250988 1250984 1250989"
XC.KIT_FX = { sp = { "法伤 +", "+%s spell dmg" }, oil = { "法伤 +", "+%s spell dmg" }, str = { "力量 +", "+%s Str" }, agi = { "敏捷 +", "+%s Agi" },
    sharp = { "武器伤害 +", "+%s weapon dmg" }, blunt = { "武器伤害 +", "+%s weapon dmg" } }
-- 职业 → 用哪几类：e 药剂 / w 武器（猎人靠远程，不提武器）；h = 混合职业，推荐写两样
XC.KIT_ROLE = {
    MAGE = { e = "sp", w = "oil" }, WARLOCK = { e = "sp", w = "oil" }, PRIEST = { e = "sp", w = "oil" },
    WARRIOR = { e = "str agi", w = "sharp blunt" }, ROGUE = { e = "agi str", w = "sharp blunt" }, HUNTER = { e = "agi" },
    PALADIN = { e = "str sp", w = "sharp blunt oil", h = true }, SHAMAN = { e = "str sp", w = "sharp blunt oil", h = true },
    DRUID = { e = "sp str agi", w = "oil sharp blunt", h = true },
}
local kitList, kitAura
function XC.KitData()
    if not kitList then
        kitList, kitAura = {}, {}
        for item, aura, lv, kind, amt, zh, en in XC.KIT_SRC:gmatch("(%d+):(%d+):(%d+):(%a+):(%d+):([^:]+):([^;]+)") do
            local e = { item = tonumber(item), aura = tonumber(aura), lv = tonumber(lv), kind = kind, amt = amt, zh = zh, en = en }
            kitList[#kitList + 1] = e
            if e.aura > 0 then kitAura[e.aura] = true end
        end
        for id in XC.KIT_AURA_EXTRA:gmatch("%d+") do kitAura[tonumber(id)] = true end
        XC.IDS.elixir = kitAura
    end
    return kitList, kitAura
end
XC.IDS.elixir, XC.NAMES.elixir = setmetatable({}, { __index = function(_, id) local _, a = XC.KitData(); return a[id] end }), {}   -- 药剂光环只按 ID 认（光环名就叫「力量」「敏捷」，按名字认会误中）

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end
local function num(v) if v == nil or secret(v) then return nil end return tonumber(v) end
local function T(k) local t = XC.TITLE[k]; return L(t[1], t[2]) end

function XC.DB()
    ns.db.xpcheck = ns.db.xpcheck or {}
    return ns.db.xpcheck
end
local function opt(k, def)
    local v = XC.DB()[k]
    if v == nil then return def end
    return v
end
function XC.Enabled() return opt("on", true) end
function XC.ItemOn(k) local t = XC.DB().items; return not (t and t[k] == false) end
function XC.Set(k, v)
    XC.DB()[k] = v
    XC.Update()
end
function XC.SetItem(k, v)
    local d = XC.DB()
    d.items = d.items or {}
    if v then d.items[k] = nil else d.items[k] = false end
    XC.Update()
end

local function anyMatch(s, pats)
    if not s then return false end
    for _, p in ipairs(pats) do if s:find(p) then return true end end
    return false
end

-- ---------- 读 buff ----------
-- 返回 { {name, id, left(秒，nil=不限时), stacks, xp(提示里带经验)} ... }
local function auraTip(i, filter)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then return nil end
    local ok, d = pcall(C_TooltipInfo.GetUnitAura, "player", i, filter)
    if not ok or type(d) ~= "table" or type(d.lines) ~= "table" then return nil end
    local t = {}
    for _, ln in ipairs(d.lines) do t[#t + 1] = str(ln.leftText) or "" end
    return table.concat(t, " ")
end
-- 11-18 内存（用户截图插件 143 MB）：每次检查、每个增益都新建这几张常量小表 → 提到外面只建一次（内容不变）
local AURA_FILTERS = { "HELPFUL", "HARMFUL" }
local KNOWN_KS = { "lockout", "fire", "bag", "elixir" }
local CLASSIFY_KS = { "lockout", "fire", "bag", "tent", "food" }
function XC.Auras()
    local out = {}
    for _, filter in ipairs(AURA_FILTERS) do
        for i = 1, 40 do
            local name, sid, exp, cnt, icon
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or not a then break end
                name, sid, exp, cnt, icon = a.name, a.spellId, a.expirationTime, a.applications, a.icon
            elseif UnitAura then
                local ok, n, ic, c, _, _, e, _, _, _, s = pcall(UnitAura, "player", i, filter)
                if not ok or not n then break end
                name, sid, exp, cnt, icon = n, s, e, c, ic
            else break end
            name, sid, exp, cnt = str(name), num(sid), num(exp), num(cnt)
            local left = (exp and exp > 0) and math.max(0, exp - now()) or nil
            local a = { name = name, id = sid, left = left, stacks = cnt or 0, icon = (icon and not secret(icon)) and icon or nil }   -- 图标用增益自己的（11-09 截图：帐篷图标客户端里没有，空着）
            -- 读鼠标提示有开销：名字 / ID 已经认出是营火 / 睡袋 / 帐篷 / 强化休息的就不读，只有剩下的才看提示里带不带「经验」
            local known = false
            for _, k in ipairs(KNOWN_KS) do
                if (sid and XC.IDS[k][sid]) or anyMatch(name, XC.NAMES[k]) then known = true; break end
            end
            if sid and (XC.IDS.passive[sid] or select(2, XC.BoostData())[sid]) then known = true end
            -- GI-234 玩家「获得了露营增益，但是没有经验加成」：名字像露营的不一定带经验 → 帐篷类也读提示，
            --   提示读到了就按这一刻写没写经验算（不拿存档里记过的顶，免得同名的没经验效果被当成有）
            if not known and ((sid and XC.IDS.tent[sid]) or anyMatch(name, XC.NAMES.tent)) then
                known = true
                local tip = auraTip(i, filter)
                tip = (tip and tip:gsub("%s", "") ~= "") and tip or nil
                local key = sid or name
                local seen = XC.DB().xpAura
                local hit = tip and (tip:find("经验") or tip:find("經驗") or tip:lower():find("experience")) and true or false
                if hit and key then XC.DB().xpAura = seen or {}; XC.DB().xpAura[key] = true end
                a.tipRead = tip and true or false
                a.xp = hit or (not tip and key and seen and seen[key] and true) or false
                a.pct = hit and pctOf(tip) or nil
            end
            if not known then
                -- 11-09 用户截图「错误报」：食物还剩 2 分钟却报「经验食物没了」—— 提示偶尔读不到（空 / 没加载好），
                --   这一刻食物就认不出来。读到过带「经验」的法术 ID / 名字记下来（存档里），之后提示读不到时按记下的算
                local key = sid or name
                local seen = XC.DB().xpAura
                local tip = auraTip(i, filter)
                local hit = tip and tip ~= "" and (tip:find("经验") or tip:find("經驗") or tip:lower():find("experience"))
                if hit and key then
                    XC.DB().xpAura = seen or {}
                    XC.DB().xpAura[key] = true
                end
                a.xp = (hit or (key and seen and seen[key])) and true or false
                a.pct = hit and pctOf(tip) or nil
            end
            out[#out + 1] = a
        end
    end
    return out
end

local function classify(a)
    if a.id and XC.IDS.elixir[a.id] then return "elixir" end
    if a.id and XC.IDS.passive[a.id] then return a.id == 1225478 and "legacy" or nil end
    if a.id and select(2, XC.BoostData())[a.id] then return "boost" end
    for _, k in ipairs(CLASSIFY_KS) do
        local byId = a.id and XC.IDS[k][a.id]
        if byId or anyMatch(a.name, XC.NAMES[k]) then
            if k == "tent" then
                -- GI-234：按 ID 认的，提示读到了却没写经验就不算；只靠名字的，得写着经验（读不到按之前认出过的算）
                if (byId and not (a.tipRead and not a.xp)) or (not byId and a.xp) then return k end
            elseif k ~= "food" or a.xp then return k end
        end
    end
    if a.xp then return "food" end   -- 提示里带「经验」但认不出来的：多半是食物 / 其他经验加成，归到食物那行
    return nil
end

-- 探针：带「经验」或认出来的增益，记 ID / 名字 / 持续时间，定 ID 用
local function probe(a, k)
    local d = XC.DB()
    d.probe = d.probe or {}
    local line = string.format("%s %s:%s %s", k or "?", tostring(a.id or 0), a.name or "?", a.left and math.floor(a.left / 60 + 0.5) .. "m" or "-")
    -- 11-18 内存：每次检查都会走到这里，一模一样的一行已经在了就不用再逐条 match（每条 match 都新建一个字符串）
    for _, l in ipairs(d.probe) do if l == line then return end end
    local key = line:match("^(%S+ [^ ]+)")
    for i, l in ipairs(d.probe) do if l:match("^(%S+ [^ ]+)") == key then d.probe[i] = line; return end end
    if #d.probe >= 40 then table.remove(d.probe, 1) end
    d.probe[#d.probe + 1] = line
end

-- ---------- 背包 / 技能 ----------
-- 11-18 GI-302（法师「出发前清单未识别背包内已有物品」：经验食物 / 睡袋等在包里却显示缺）：
--   原来只走 ns.Prof.BagCount = 老接口 GetItemCount，《无限》客户端里读不到（11-17 练级补全器 XpSupply 已因同样原因改成逐格扫，这里漏了）
--   → 新接口 C_Item.GetItemCount、老接口、逐格扫背包 0~4、原来的 ns.Prof.BagCount 几种数法取大的
local function cfn(k) return (C_Container and C_Container[k]) or rawget(_G, k) end
-- 11-18 用户「重载了还是巨卡」：原来每数一种物品就把整包扫一遍（几十种 × 一百来格，主城清单每 2 秒一刷）→
--   整包扫一次存成 { [物品] = 数量 }，同一帧里复用（一次刷新里几十次查询只扫一遍）；换帧 / 背包变了才重扫
local bagMap, bagMapT, bagDirty = {}, nil, true
local function now0() return GetTime and GetTime() or 0 end
local function rescan()
    local nslots, info = cfn("GetContainerNumSlots"), cfn("GetContainerItemInfo")
    for k in pairs(bagMap) do bagMap[k] = nil end
    bagDirty, bagMapT = false, now0()
    if not (nslots and info) then return end
    for b = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local ok, cnt = pcall(nslots, b)
        cnt = ok and num(cnt) or 0
        for s = 1, cnt do
            local ok2, a, c, _, _, _, _, link, _, _, iid = pcall(info, b, s)
            if ok2 then
                local sid, k
                if type(a) == "table" then sid, k = num(a.itemID), num(a.stackCount)
                else
                    sid, k = num(iid), num(c)
                    if not sid and type(link) == "string" and not secret(link) then sid = tonumber(link:match("item:(%d+)")) end
                end
                if sid then bagMap[sid] = (bagMap[sid] or 0) + (k or 1) end
            end
        end
    end
end
function XC.BagDirty() bagDirty = true end
local function scanCount(id)
    if bagDirty or bagMapT ~= now0() then rescan() end
    return bagMap[id] or 0
end
local function bag(id)
    local best = 0
    local fs = { C_Item and C_Item.GetItemCount or false, GetItemCount or false }   -- ⛔ 别放 nil：ipairs 遇到 nil 就停，后面的老接口不调
    for _, f in ipairs(fs) do
        if f then
            local ok, n = pcall(f, id)
            n = ok and num(n) or 0
            if n > best then best = n end
        end
    end
    local P = ns.Prof   -- 原来的数法（专业模块；含银行）也算上，读得到就不比原来少
    if P and P.BagCount then local ok, n = pcall(P.BagCount, id); n = ok and num(n) or 0; if n > best then best = n end end
    local s = scanCount(id)
    return s > best and s or best
end
XC.BagHave = bag   -- 测试用
local function level() return num(UnitLevel and UnitLevel("player")) or 1 end
local function maxLevel() return (num(GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60) end
local function cookRank()
    local P = ns.Prof
    if not (P and P.Skills) then return nil end
    local ok, sk = pcall(P.Skills)
    local c = ok and type(sk) == "table" and sk.cooking
    return c and c.r or nil
end
local function itemCD(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0 end
    local ok, s, d = pcall(f, id)
    s, d = ok and num(s), ok and num(d)
    if not s or not d or s == 0 or d <= 1.5 then return 0 end
    return math.max(0, s + d - now())
end
-- 物品名：客户端缓存里有就用；没缓存（刚登录常见）用我们自己的名字，别显示成数字
local NAMES = { [4470] = { "普通木柴", "Simple Wood" }, [4471] = { "燧石和火绒", "Flint and Tinder" }, [273049] = { "大法师的多面坠饰", "Archmagister's Faceted Pendant" } }
local function itemName(id, zh, en)
    local n = ns.ItemInfo and ns.ItemInfo(id)
    if str(n) then return n end
    if zh then return L(zh, en or zh) end
    if NAMES[id] then return L(NAMES[id][1], NAMES[id][2]) end
    local P = ns.Prof
    local pn = P and P.ItemName and P.ItemName(id)
    if pn and pn ~= tostring(id) then return pn end
    return "#" .. id
end

-- 经验食物：配方成品（ProfRecipes[7]）；包里有的 + 能做的（烹饪够、材料齐）
-- 11-13 重构第 4 期：专业大表 / 配方库按需加载 → 经验食物清单和成品物品读常驻的 ProfCoreData.lua（同一份数据抽出来的）
function XC.Foods()
    local D = ns.ProfCore
    local have, make = {}, {}
    if not (D and D.foods) then return have, make end
    local lv, ck = level(), cookRank()
    for _, f in ipairs(D.foods) do
        local item = ns.ProfFoodItem and ns.ProfFoodItem(f.sp)
        if item and (f.use or 1) <= lv then
            local n = bag(item)
            if n > 0 then have[#have + 1] = { item = item, n = n, use = f.use or 1, f = f } end
            if ck and f.learn <= ck then
                local short = {}
                for _, m in ipairs(f.m or {}) do
                    local b = bag(m[1])
                    if b < m[2] then short[#short + 1] = { m[1], m[2] - b } end
                end
                make[#make + 1] = { item = item, use = f.use or 1, f = f, short = short }
            end
        end
    end
    local function by(a, b) if a.use ~= b.use then return a.use > b.use end return a.item < b.item end
    table.sort(have, by)
    table.sort(make, function(a, b)
        if (#a.short == 0) ~= (#b.short == 0) then return #a.short == 0 end
        return by(a, b)
    end)
    return have, make
end

-- ---------- 药剂 / 武器油（kit）----------
local function none() end
-- 只数背包（不带银行：银行里的拿不出来用）
local function bagOnly(id)
    local ok, n = pcall((C_Item and C_Item.GetItemCount) or GetItemCount or none, id)   -- 11-17 新客户端优先 C_Item
    return (ok and num(n)) or 0
end
-- 主手：nil = 没拿武器；"blunt" 锤 / 法杖；"sharp" 其他；"sharp blunt" 拳套 / 读不到类型（两种石头都算）
local BLUNT = { [4] = true, [5] = true, [10] = true }
local function mainHand()
    local ok, id = pcall(GetInventoryItemID or none, "player", 16)
    if not (ok and num(id)) then return nil end
    local ok2, _, _, _, _, _, cls, sub = pcall((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant or none, id)
    sub = ok2 and num(cls) == 2 and num(sub)
    if not sub or sub == 13 then return "sharp blunt" end
    return BLUNT[sub] and "blunt" or "sharp"
end
-- 主手临时附魔（巫师之油 / 磨刀石 / 毒药 / 萨满武器附魔都算）：{ left = 秒 } / false = 没有 / nil = 读不到
local function weaponEnchant()
    local ok, has, exp = pcall(GetWeaponEnchantInfo or none)
    if not ok or has == nil or secret(has) or type(has) ~= "boolean" then return nil end
    exp = has and num(exp)
    return has and { left = (exp and exp > 0) and exp / 1000 or nil }
end
local function kitName(e) return itemName(e.item, e.zh, e.en) end
local function kitFx(e) local f = XC.KIT_FX[e.kind]; return L(f[1] .. e.amt, string.format(f[2], e.amt)) end
XC.KitFx = kitFx
-- 一份（药剂 / 武器）：kinds 允许的类、等级够的 → bag 包里有的最高一档 / best 每类该买的最高一档
local function kitPart(kinds, lv, weapon)
    local p = { best = {} }
    for _, e in ipairs((XC.KitData())) do
        if (e.aura == 0) == weapon and kinds:find(e.kind, 1, true) and e.lv <= lv then
            local n = bagOnly(e.item)
            if n > 0 and (not p.bag or e.lv > p.bag.e.lv) then p.bag = { e = e, n = n } end
            if not p.best[e.kind] or e.lv > p.best[e.kind].lv then p.best[e.kind] = e end
        end
    end
    return p
end
function XC.Kit(got, lv)
    local _, _, cls = pcall(UnitClass or none, "player")
    local role = XC.KIT_ROLE[str(cls) or ""] or XC.KIT_ROLE.DRUID
    local el = kitPart(role.e, lv, false)
    el.active = got and got.elixir
    local out = { role = role, el = el }
    local mh = role.w and mainHand()
    local we = mh and weaponEnchant()
    if we ~= nil then
        -- 巫师之油哪把武器都能涂；石头看主手是利器还是钝器
        local kinds = role.w:gsub("%a+", function(k) if k ~= "oil" and not mh:find(k, 1, true) then return "" end end)
        out.wp = kitPart(kinds, lv, true)
        out.wp.active = we or nil
    end
    return out
end

local function sleepChain()
    for _, c in ipairs(ns.SideChainsData or {}) do if c.item == XC.BAG_ITEM then return c end end
end

local function fmt(sec)
    if not sec then return "" end
    sec = math.floor(sec)
    if sec >= 3600 then return string.format("%d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return string.format(L("%d 分钟", "%dm"), math.floor(sec / 60 + 0.5)) end
    return string.format(L("%d 秒", "%ds"), sec)
end
XC.Fmt = fmt

local function inInstance()
    if not IsInInstance then return false end
    local ok, inst = pcall(IsInInstance)
    return ok and inst and true or false
end

-- ---------- 核心：算出每项状态 ----------
-- 每项 { key, st = "ok" / "warn" / "miss" / "info", text = 一行, how = { 怎么补… }, left = 秒, action = 函数 }
function XC.Check()
    local res = {}
    local lv = level()
    if lv >= maxLevel() then return res, true end
    local got = {}
    for _, a in ipairs(XC.Auras()) do
        local k = classify(a)
        if k == "boost" then
            got.boosts = got.boosts or {}
            got.boosts[#got.boosts + 1] = a
        end
        if k then
            local g = got[k]
            if not g or (a.left or 1e9) > (g.left or 1e9) then got[k] = a end
            if k ~= "elixir" and k ~= "legacy" then probe(a, k) end   -- 探针只记经验类的
        elseif a.xp then probe(a, nil) end
    end
    local wild = not inInstance()
    local function add(r) if XC.ItemOn(r.key) then res[#res + 1] = r end end
    local function timed(key, a, label)
        local t = th(key)
        local warn = a.left and a.left <= t.show
        return { key = key, st = warn and "warn" or "ok", left = a.left, hi = (a.left and a.left <= t.hi) or nil, icon = a.icon, stacks = a.stacks,
            text = label .. (a.left and ("  " .. L("剩 ", "") .. fmt(a.left)) or "") }
    end

    -- 帐篷经验
    if got.tent then
        add(timed("tent", got.tent, L("帐篷经验加成中", "Tent XP active")))
    elseif got.lockout then
        add({ key = "tent", st = "info", left = got.lockout.left,
            text = L("帐篷经验冷却中", "Tent XP on cooldown") .. (got.lockout.left and ("  " .. L("还剩 ", "") .. fmt(got.lockout.left)) or ""),
            how = { L("「强化休息」：1 小时内帐篷给不了经验，冷却完再去蹭", "Enhanced rest: no tent XP for 1 hour; come back after it ends") } })
    elseif wild then
        -- 11-17「路上碰到还可以刷新」：刚指到过别人的帐篷（Camp.lua 记的）→ 写明附近有谁的帐篷
        local CP = ns.Camp
        local near = CP and CP.seenWho and now() - (CP.seenAt or 0) < 180 and CP.seenWho or nil
        add({ key = "tent", st = "miss", text = L("没有帐篷经验", "No tent XP"), near = near,
            srcText = near and string.format(L("附近有 %s 的帐篷（再指一下帐篷就弹请求进队）", "%s's tent is nearby (mouse over it to ask for an invite)"), near) or nil,
            how = { L("附近有人放「资深冒险者的探险帐篷」就鼠标指一下，插件弹窗帮你请求进队", "Mouse over someone's adventurer's tent - the addon offers to ask for an invite"),
                L("进队后在帐篷旁坐下（按 X）满 60 秒才拿到经验", "Once grouped, sit (X) next to the tent for 60 seconds") } })
    end

    -- 营火
    if got.fire then
        add({ key = "fire", st = "ok", left = got.fire.left, text = L("在营火边", "By a campfire") .. (got.fire.left and ("  " .. L("剩 ", "") .. fmt(got.fire.left)) or "") })
    elseif wild then
        local ck = cookRank()
        local how = {}
        if ck then
            local w, f = bag(XC.WOOD), bag(XC.FLINT)
            if w > 0 and f > 0 then
                how[#how + 1] = L("包里有木柴和燧石：在安全的地方生火坐下就有", "You have wood and flint: light a fire and sit down")
            else
                local miss = {}
                if f == 0 then miss[#miss + 1] = itemName(XC.FLINT) end
                if w == 0 then miss[#miss + 1] = itemName(XC.WOOD) end
                how[#how + 1] = L("自己生火还缺：", "To light one you need: ") .. table.concat(miss, L("、", ", ")) .. L("（杂货商有卖）", " (trade goods vendor)")
            end
        else
            how[#how + 1] = L("没学烹饪：找队友的营火，或学烹饪自己生火（燧石和火绒 + 普通木柴）", "No Cooking: use a party member's fire, or learn Cooking (flint + wood)")
        end
        -- 11-17 用户「营火不算buff」：营火只是坐着才有的地点效果，不在边上 ≠ 缺 buff → 灰着（info），不标红「缺」、不闪框、不算进缺几项
        add({ key = "fire", st = "info", text = L("不在营火边", "No campfire"), how = how })
    end

    -- 睡袋
    local bagN = bag(XC.BAG_ITEM)
    if got.bag then
        local s = math.max(1, got.bag.stacks or 1)
        local r = timed("bag", got.bag, string.format(L("精神饱满 %d/%d 层", "Well rested %d/%d"), s, XC.BAG_STACKS))
        if s < XC.BAG_STACKS then
            r.st = "warn"; r.hi = true
            r.how = { L("再躺几分钟叠满 3 层（每满 1 分钟 1 层）", "Lie in the bag a few more minutes for 3 stacks") }
        end
        add(r)
    elseif bagN > 0 then
        local cd = itemCD(XC.BAG_ITEM)
        -- 11-18 官方在线修正：骑着坐骑不能再躺进睡袋；睡袋改为像猎人陷阱一样放到指定位置，范围内有休息光环提示
        local mounted = IsMounted and IsMounted()
        if cd > 0 then
            local how = { L("冷却好了再铺；队友的睡袋也能躺", "Wait for the cooldown, or use a party member's bag") }
            if mounted then
                table.insert(how, 1, L("骑着坐骑躺不进睡袋（11-18 热修），先下坐骑再走进睡袋范围", "You can't use a sleeping bag while mounted (Nov 18 hotfix): dismount and step into its range"))
            end
            add({ key = "bag", st = "info", left = cd, text = L("睡袋冷却中", "Bag on cooldown") .. "  " .. L("还剩 ", "") .. fmt(cd), how = how })
        elseif wild then
            add({ key = "bag", st = "miss", text = L("睡袋可以铺了", "Sleeping bag ready"),
                how = { L("先下坐骑，像放猎人陷阱一样把睡袋放到想要的位置（读条 15 秒）；进到范围内会有休息光环提示，躺 3 分钟叠满 3 层，经验 +3%，持续 2 小时",
                    "Dismount, then place the bag like a hunter trap (15 s cast); a resting aura shows when you're in range. Lie 3 minutes for 3 stacks: +3% XP for 2 hours") } })
        end
    elseif lv >= 14 then
        local c = sleepChain()
        local txt, how = L("还没有睡袋", "No sleeping bag yet"), {}
        if c and ns.SideChains and ns.SideChains.Progress then
            local ok, _, n, total = pcall(ns.SideChains.Progress, c)
            if ok and total and total > 0 then
                txt = txt .. string.format(L("  任务线 %d/%d", "  quest line %d/%d"), n, total)
                how[#how + 1] = L("点这一行打开睡袋任务线步骤", "Click to open the sleeping bag quest steps")
            end
        end
        how[#how + 1] = L("做完任务线拿「舒适的睡袋」：躺满 3 分钟经验 +3%，持续 2 小时", "Finish the quest line for the Cozy Sleeping Bag: +3% XP for 2 hours")
        add({ key = "bag", st = "miss", text = txt, how = how,
            action = c and ns.SideChains and ns.SideChains.Show and function() ns.SideChains.Show(c) end or nil })
    end

    -- 经验食物
    if got.food then
        add(timed("food", got.food, (got.food.name or L("经验食物", "XP food")) .. L(" 生效中", " active")))
    else
        local have, make = XC.Foods()
        local how = {}
        if have[1] then
            how[#how + 1] = L("包里有：", "In your bags: ") .. itemName(have[1].item, have[1].f.zh, have[1].f.en) .. " ×" .. have[1].n .. L("，吃一个", " - eat one")
        end
        for i = 1, math.min(2, #make) do
            local m = make[i]
            if #m.short == 0 then
                how[#how + 1] = L("营火边能做：", "Can cook at a fire: ") .. itemName(m.item, m.f.zh, m.f.en) .. L("（材料齐了）", " (mats ready)")
            else
                local s = {}
                for _, x in ipairs(m.short) do s[#s + 1] = itemName(x[1]) .. "×" .. x[2] end
                how[#how + 1] = L("能做 ", "Can cook ") .. itemName(m.item, m.f.zh, m.f.en) .. L("，还缺 ", ", need ") .. table.concat(s, L("、", ", "))
            end
        end
        if #how == 0 then how[1] = L("学烹饪做经验食物，或拍卖行 / 队友那里买", "Learn Cooking for XP food, or buy it from the AH / friends") end
        add({ key = "food", st = "miss", text = have[1] and L("没吃经验食物（包里有）", "No XP food (you have some)") or L("没吃经验食物", "No XP food"), how = how })
    end

    -- 经验药剂 / 饰品 / 活动（BOOST_SRC，数据驱动）：生效中 = ok；包里有药剂没喝 = 红 + 用；戴着坠饰、冷却好了 = 灰 + 用；其他（活动）只在身上有时显示
    local _, bAura = XC.BoostData()
    if XC.ItemOn("boost") then
        local act, minLeft, how, use, st = {}, nil, {}, nil, nil
        for _, a in ipairs(got.boosts or {}) do
            local e = bAura[a.id]
            act[#act + 1] = L(e.zh, e.en) .. " +" .. e.pct .. "%" .. (a.left and (" " .. fmt(a.left)) or "")
            how[#how + 1] = L(e.zh, e.en) .. L("：", ": ") .. L(SCOPE[e.sc][1], SCOPE[e.sc][2]) .. L("经验 +", "XP +") .. e.pct .. "%"
            if a.left and (not minLeft or a.left < minLeft) then minLeft = a.left end
        end
        for _, e in ipairs(wild and XC.BoostData() or {}) do
            if e.item > 0 and e.lv <= lv and not use then
                local fx = L(SCOPE[e.sc][1], SCOPE[e.sc][2]) .. L("经验 +", "XP +") .. e.pct .. "%"
                if e.cat == "p" and bagOnly(e.item) > 0 then
                    use, st = { item = e.item, n = bagOnly(e.item), name = itemName(e.item, e.zh, e.en), fx = fx }, "miss"
                elseif e.cat == "t" then
                    local ok, id = pcall(GetInventoryItemID or none, "player", 2)
                    if ok and num(id) == e.item and itemCD(e.item) == 0 then use, st = { item = e.item, n = 1, name = itemName(e.item), fx = fx, trinket = true }, "info" end
                end
            end
        end
        if act[1] then
            local t = th("boost")
            add({ key = "boost", st = (minLeft and minLeft <= t.show) and "warn" or "ok", left = minLeft, hi = (minLeft and minLeft <= t.hi) or nil,
                text = table.concat(act, L("、", ", ")), how = how, icon = got.boost.icon })
        elseif use then
            add({ key = "boost", st = st, use = use,
                text = st == "miss" and string.format(L("包里有%s没喝", "%s in your bags, not used"), use.name) or string.format(L("%s可以用了", "%s is ready"), use.name),
                how = { use.name .. L("：", ": ") .. use.fx .. (st == "miss" and L("，1 小时", ", 1 hour") or L("，5 分钟；6 小时一次，打亡灵前用", ", 5 min, 6 h cooldown - use before fighting Undead")),
                    L("经验加成页里点「用」一键用上（战斗中不能用），或背包里右键", "Click \"Use\" on the XP page (not in combat), or right-click it in your bags") } })
        end
    end

    -- 药剂 / 武器油（11-17 抖音「6 银币」那套，见文件头 XC.KIT_SRC 注释）
    if lv >= XC.KIT_MIN_LV and XC.ItemOn("kit") then
        local k = XC.Kit(got, lv)
        local act, use, how, miss, minLeft = {}, nil, {}, {}, nil
        for _, x in ipairs({ { p = k.el, name = L("药剂", "Elixir") }, { p = k.wp, name = L("武器油", "Weapon oil"), w = true } }) do
            local p = x.p
            if p and p.active then
                local left = p.active.left
                act[#act + 1] = x.name .. (left and (" " .. fmt(left)) or "")
                if left and (not minLeft or left < minLeft) then minLeft = left end
            elseif p and p.bag then
                use = use or { item = p.bag.e.item, n = p.bag.n, weapon = x.w, name = kitName(p.bag.e), fx = kitFx(p.bag.e) }
            elseif p then
                miss[#miss + 1] = x.name
                local s = {}
                for kind in (x.w and "oil sharp blunt" or (k.role.h and "str sp" or "sp str agi")):gmatch("%a+") do
                    local e = p.best[kind]
                    if e then s[#s + 1] = kitName(e) .. L("（", " (") .. kitFx(e) .. L("）", ")") end
                end
                if s[1] then how[#how + 1] = string.format(L("没%s：拍卖行搜 %s", "No %s: buy %s on the AH"), x.name, table.concat(s, L(" 或 ", " or "))) end
            end
        end
        if use then
            table.insert(how, 1, L("包里有：", "In your bags: ") .. use.name .. " ×" .. use.n .. L("（", " (") .. use.fx .. L("）", ")")
                .. (use.weapon and L("，用了以后点一下主手武器", " - use it, then click your main-hand weapon") or L("，喝一瓶", " - drink one")))
            table.insert(how, 2, L("经验加成页里点「用」一键用上（战斗中不能用），或背包里右键", "Click \"Use\" on the XP page (not in combat), or right-click it in your bags"))
        end
        if miss[1] then how[#how + 1] = L("都是 30 分钟～1 小时的低级消耗品，拍卖行几个银币一份（炼金 / 附魔 / 锻造做的）；打怪前用上", "Cheap 30-60 min consumables (alchemy / enchanting / blacksmithing) - use them before you start pulling") end
        local txt = table.concat(act, L("、", ", "))
        local icon = got.elixir and got.elixir.icon
        if use and wild then
            add({ key = "kit", st = "miss", text = string.format(L("包里有%s没用", "%s in your bags, not used"), use.name) .. (txt ~= "" and ("  ·  " .. txt) or ""),
                how = how, left = minLeft, use = use, icon = icon })
        elseif act[1] then
            local t = th("kit")
            if miss[1] and wild then txt = txt .. L("（没", " (no ") .. table.concat(miss, L("、", ", ")) .. L("）", ")") end
            add({ key = "kit", st = (minLeft and minLeft <= t.show) and "warn" or "ok", left = minLeft, hi = (minLeft and minLeft <= t.hi) or nil, text = txt, how = how[1] and how or nil, icon = icon })
        elseif wild then
            -- 包里也没有：可选增益、要花钱 → 灰着（info），不标红、不算「缺」（同 11-17 营火）
            add({ key = "kit", st = "info", how = how,
                text = k.wp and L("没喝药剂、没上武器油（可选）", "No elixir / weapon oil (optional)") or L("没喝药剂（可选）", "No elixir (optional)") })
        end
    end

    -- 休息经验
    local ex = num(GetXPExhaustion and GetXPExhaustion())
    local mx = num(UnitXPMax and UnitXPMax("player"))
    if mx and mx > 0 then
        local pct = math.floor((ex or 0) / mx * 100 + 0.5)
        local resting = IsResting and IsResting() and true or false
        if pct >= 140 then
            add({ key = "rest", st = "warn", pct = pct, text = string.format(L("休息经验 %d%%（快满了）", "Rested %d%% (almost full)"), pct),
                how = { L("休息经验最多攒到 150%，满了就浪费：先去打怪把它用掉", "Rested XP caps at 150% - go use it before it's wasted") } })
        elseif pct > 0 then
            -- 11-09 用户「最高该有多少」「能提示吗」：提示里写上限 + 怎么攒 + 攒满还要多久（经典规则：旅店 / 主城 / 睡袋下线每 8 小时 +5%，野外 1/4）
            local hrs = math.ceil((150 - pct) / 5 * 8)
            local full = hrs >= 48 and string.format(L("约 %d 天", "~%d days"), math.floor(hrs / 24 + 0.5)) or string.format(L("约 %d 小时", "~%d h"), hrs)
            add({ key = "rest", st = "ok", pct = pct, text = string.format(L("休息经验 %d%%（最多 150%%）", "Rested %d%% (max 150%%)"), pct),
                how = { L("最多攒到 150%（一级半经验），满了不再涨", "Caps at 150% (1.5 levels)"),
                    L("在旅店 / 主城下线、或躺在睡袋里下线：每 8 小时 +5%；野外下线只有 1/4", "Log out in an inn / city / sleeping bag: +5% per 8 h (1/4 in the wild)"),
                    string.format(L("从现在攒满还要%s（在旅店下线算）", "Full in %s (logged out in an inn)"), full) } })
        else
            add({ key = "rest", st = resting and "ok" or "info", pct = 0, text = L("没有休息经验", "No rested XP"),
                how = { L("下线前在旅店 / 主城，或躺在睡袋里下线，能攒休息经验", "Log out in an inn, a city, or your sleeping bag to earn rested XP") } })
        end
        local r = res[#res]
        if r and r.key == "rest" then
            r.how = r.how or {}
            table.insert(r.how, L("有休息经验时打怪经验翻倍（+100%），和其他加成分开算；任务经验不吃", "While rested, kill XP is doubled (+100%), counted separately; quests don't use it"))
            if got.legacy then r.how[#r.how + 1] = L("传承「精神抖擞」：休息经验攒得更快、上限更高（每级 +4%，最多 +20%）", "Legacy \"Well Rested\": rested XP builds faster with a higher cap (+4% per rank, up to +20%)") end
        end
    end

    -- 合计（11-17）：生效中的百分比加成。DB2 里都是同一种光环（200 打怪 / 291 任务），游戏里多项是相加还是相乘没法核实
    --   → 按相加算，两项以上标「约」（几项都是个位数时两种算法差不到 1%）
    local tot = { parts = {}, kill = 0, quest = 0, undead = 0 }
    local function part(name, pct, sc)
        if not pct or pct <= 0 then return end
        tot.parts[#tot.parts + 1] = { name = name, pct = pct, sc = sc }
        if sc == "u" then tot.undead = tot.undead + pct else
            if sc ~= "q" then tot.kill = tot.kill + pct end
            if sc ~= "k" then tot.quest = tot.quest + pct end
        end
    end
    if got.tent then part(T("tent"), got.tent.pct, "a") end
    if got.bag then part(T("bag"), math.max(1, got.bag.stacks or 1) * XC.BAG_PCT, "a") end
    if got.food then part(T("food"), got.food.pct or XC.FOOD_PCT, "k") end
    for _, a in ipairs(got.boosts or {}) do local e = bAura[a.id]; part(L(e.zh, e.en), e.pct, e.sc) end
    tot.rest = (mx and mx > 0 and ex and ex > 0) and math.floor(ex / mx * 100 + 0.5) or 0
    tot.approx = #tot.parts >= 2
    tot.tentRest = got.tent and not got.tent.pct
    XC.total = tot
    return res, false
end

-- 合计一行「经验 约 +8%（睡袋 3 · 食物 5）· 休息经验翻倍（剩 50%）」；XC.TotalLines = 悬停逐项明细
local SC2 = { a = { "打怪 + 任务", "kills + quests" }, k = { "只算打怪", "kills only" }, q = { "只算任务", "quests only" }, u = { "只算杀亡灵", "Undead kills only" } }
function XC.TotalText()
    local t = XC.total
    if not t then return nil end
    local s, p = "", {}
    for _, x in ipairs(t.parts) do p[#p + 1] = x.name .. " " .. x.pct end
    if t.kill > 0 or t.quest > 0 then
        s = L("经验 ", "XP ") .. (t.approx and L("约 ", "~") or "") .. "+" .. math.max(t.kill, t.quest) .. "%" .. L("（", " (") .. table.concat(p, " · ") .. L("）", ")")
        if t.kill ~= t.quest then s = s .. string.format(L(" 打怪 +%d%% / 任务 +%d%%", " kills +%d%% / quests +%d%%"), t.kill, t.quest) end
    elseif t.undead > 0 then s = string.format(L("经验 杀亡灵 +%d%%", "XP Undead kills +%d%%"), t.undead)
    else s = L("经验加成：无", "XP bonus: none") end
    if t.undead > 0 and (t.kill > 0 or t.quest > 0) then s = s .. string.format(L(" · 杀亡灵再 +%d%%", " · Undead +%d%%"), t.undead) end
    if t.rest > 0 then s = s .. string.format(L(" · 休息经验翻倍（剩 %d%%）", " · rested x2 (%d%% left)"), t.rest) end
    return s
end
function XC.TotalLines()
    local t, out = XC.total, {}
    if not t then return out end
    for _, x in ipairs(t.parts) do out[#out + 1] = x.name .. L("：+", ": +") .. x.pct .. "%" .. L("（", " (") .. L(SC2[x.sc][1], SC2[x.sc][2]) .. L("）", ")") end
    if t.tentRest then out[#out + 1] = L("帐篷：补的是休息经验（最多补到一级的 5%），不算百分比加成", "Tent: tops up rested XP (to 5% of a level), not a % bonus") end
    if t.rest > 0 then out[#out + 1] = string.format(L("休息经验：打怪经验翻倍，还剩一级的 %d%%（另算，不加进上面的数）", "Rested: kill XP doubled, %d%% of a level left (separate)"), t.rest) end
    if t.approx then out[#out + 1] = L("多项按相加估算（游戏里是相加还是相乘核实不了，所以写「约」）", "Summed - whether the game adds or multiplies them is unverified") end
    return out
end

-- ---------- 提醒 ----------
local warned = {}   -- key → 已提醒到第几档（1 = 浮出来，2 = 高亮）
local hadBuff = {}  -- key → 上次检查时这项在生效
local pending = {}  -- 战斗中攒着，出战斗再报
local missAt = {}   -- key → 第一次读到「缺」的时间（GI-211 防抖）
local MISS_CONFIRM = 4
XC.MISS_CONFIRM = MISS_CONFIRM
local function flash(msg)
    if not opt("warn", true) then return end
    if InCombatLockdown and InCombatLockdown() then pending[#pending + 1] = msg; return end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0) end
    ns.Print(msg)
    if opt("sound", false) and PlaySound then pcall(PlaySound, 8959) end
end
function XC.Alerts(res)
    local seen = {}
    for _, r in ipairs(res) do
        seen[r.key] = true
        local active = (r.st == "ok" or r.st == "warn") and r.left ~= nil
        if r.st ~= "miss" then missAt[r.key] = nil end
        if active then
            hadBuff[r.key] = true
            local t = th(r.key)
            local lv = { t.show, t.hi }
            for i = #lv, 1, -1 do
                if r.left <= lv[i] and (warned[r.key] or 0) < i then
                    warned[r.key] = i
                    flash(string.format(L("GearInsight：%s 还剩 %s，记得补", "GearInsight: %s ends in %s"), T(r.key), fmt(r.left)))
                    break
                end
            end
            if r.left > t.show then warned[r.key] = nil end
        elseif r.st == "miss" and hadBuff[r.key] and not (missAt[r.key] and now() - missAt[r.key] >= MISS_CONFIRM) then
            -- 「没了」要连着两次都读不到（隔 ≥ MISS_CONFIRM 秒）才报：偶尔一次读空（加载 / 切地图 / 加密值）不算
            missAt[r.key] = missAt[r.key] or now()
        elseif r.st == "miss" and hadBuff[r.key] then
            hadBuff[r.key] = nil; warned[r.key] = nil; missAt[r.key] = nil
            if r.key ~= "tent" and r.key ~= "fire" then   -- 帐篷 / 营火离开就没，不唠叨
                flash(string.format(L("GearInsight：%s 没了", "GearInsight: %s ended"), T(r.key)) .. ((r.how and r.how[1]) and ("  " .. r.how[1]) or ""))
            end
        elseif not active then
            hadBuff[r.key] = nil
        end
    end
end
function XC.Flush()
    local p = pending
    pending = {}
    for _, m in ipairs(p) do flash(m) end
end

-- ---------- 提醒条（11-09 用户「搞成正式服那种，平时透明，快没了就弹出来提醒」）----------
-- 照正式服物资提醒：平时看不见；某项剩到 show 秒浮出来（图标 + 剩余时间），剩到 hi 秒高亮闪；睡袋不满 3 层直接出来并高亮。
-- 左键图标 = 打开经验加成页；右键 = 这一项这次不再弹（补上 / 刷新后恢复）；Shift + 拖 = 挪位置。
-- 「一直半透明」= 生效中的加成常驻半透明显示，快没了的照样亮起来。缺的（没营火 / 没吃食物）不进提醒条，去页里看。
local win
local COLOR = { ok = { 0.25, 0.9, 0.35 }, warn = { 1, 0.82, 0.1 }, miss = { 1, 0.35, 0.3 }, info = { 0.7, 0.7, 0.7 } }
local ICON_SZ, GAP = 36, 8
local IDLE_ALPHA = 0.35
local snooze = {}
XC._snooze = snooze

local function short(sec)
    if not sec then return "" end
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
    if sec >= 60 then return string.format("%dm", math.floor(sec / 60 + 0.5)) end
    return string.format("%ds", sec)
end
XC.Short = short

local function savePos()
    if not win then return end
    local p, _, _, x, y = win:GetPoint()
    XC.DB().pos = { p or "CENTER", x or 0, y or 0 }
end

-- GI-225 设置页「移动提醒条」/「重置位置」，/gi xp move|reset
function XC.SetMoving(on)
    XC.moving = on and true or false
    XC.hidden = false
    XC.Update()
    if win and win.tip then win.tip:SetShown(XC.moving) end
    if XC.moving then
        ns.Print(L("提醒条已摆出来：按住图标拖到想放的位置，再点一次「锁定位置」", "Reminder bar shown: drag it where you like, then click \"Lock\""))
    end
end
function XC.ResetPos()
    XC.DB().pos = nil
    if win then win:ClearAllPoints(); win:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end
    ns.Print(L("提醒条位置已恢复默认（屏幕中间偏下）", "Reminder bar position reset"))
end

function XC.CloseForGood()
    if GameTooltip then GameTooltip:Hide() end
    XC.moving = false
    XC.Set("win", false)
    if ns.RefreshSettings then pcall(ns.RefreshSettings) end
    if ns.CloseHint then
        ns.CloseHint("xpBar", L("经验提醒条已永久关闭（聊天框提醒照旧）。找回：GI 菜单 → 窗口与提醒 → 经验提醒条，或设置页「显示提醒条」",
            "XP reminder bar closed for good (chat alerts stay). Bring it back: GI menu > Windows & alerts > XP reminder bar, or Settings > Show the reminder bar"))
    end
end

local function buildWin()
    local f = CreateFrame("Frame", "GearInsightForeverXpCheck", UIParent)
    f:SetSize(ICON_SZ, ICON_SZ + 16); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)   -- 11-09 截图：MEDIUM 被主面板（HIGH）盖住看不见
    local pos = XC.DB().pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end
    f:SetMovable(true)
    f.btns = {}
    f.tip = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.tip:SetPoint("BOTTOM", f, "TOP", 0, 8)
    f.tip:SetText(L("拖我挪位置", "Drag to move"))
    f.tip:SetShown(XC.moving == true)
    f.sumFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.sumFs:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    local acc, tick = 0, 0
    f:SetScript("OnUpdate", function(self, el)
        el = el or 0
        acc = acc + el; tick = tick + el
        local pulse = 0.45 + 0.55 * math.abs(math.sin(acc * 4))
        for _, b in ipairs(self.btns) do
            if b:IsShown() and b.glow:IsShown() then b.glow:SetAlpha(pulse) end
        end
        if tick < 1 then return end
        tick = 0
        for _, b in ipairs(self.btns) do
            local it = b.it
            if b:IsShown() and it and it.left then b.time:SetText(short(it.left - (now() - (self.at or now())))) end
        end
    end)
    return f
end

local function btn(i)
    local b = win.btns[i]
    if b then return b end
    b = CreateFrame("Button", nil, win)
    b:SetSize(ICON_SZ, ICON_SZ)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetPoint("TOPLEFT", -2, 2); b.bg:SetPoint("BOTTOMRIGHT", 2, -2)   -- 2px 边框：缺 = 红框
    b.bg:SetColorTexture(0, 0, 0, 0.85)
    b.ic = b:CreateTexture(nil, "ARTWORK"); b.ic:SetAllPoints(); b.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
    if b.glow.SetVertexColor then b.glow:SetVertexColor(1, 0.82, 0.1) end
    b.glow:SetPoint("CENTER"); b.glow:SetSize(ICON_SZ * 1.9, ICON_SZ * 1.9); b.glow:Hide()
    b.cnt = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.cnt:SetPoint("BOTTOMRIGHT", -2, 2)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.time:SetPoint("TOP", b, "BOTTOM", 0, -3)
    -- 11-09 用户截图：亮背景上「缺」字看不清 → 描边
    for _, fs in ipairs({ b.cnt, b.time }) do
        local f, sz = fs:GetFont()
        if f then pcall(fs.SetFont, fs, f, math.max(12, tonumber(sz) or 12), "OUTLINE") end
    end
    b:SetScript("OnEnter", function(self)
        local it = self.it
        if not it or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(T(it.key), 1, 0.82, 0)
        GameTooltip:AddLine(it.text, 1, 1, 1, true)
        -- 11-17「buff和来源要可视化对应」：提醒条悬停也写「来源：…」（页里是图标排开的，这里一行字）
        local src = it.srcText or (it.how and it.how[1])
        if src then GameTooltip:AddLine(L("来源：", "Source: ") .. src, 0.25, 0.9, 0.35, true) end
        for i, h in ipairs(it.how or {}) do if h ~= src or i > 1 then GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end end
        if opt("total", true) and XC.TotalText() then
            GameTooltip:AddLine(XC.TotalText(), 0.25, 0.9, 0.35, true)
            for _, h in ipairs(XC.TotalLines()) do GameTooltip:AddLine("· " .. h, 0.8, 0.8, 0.8, true) end
        end
        local rt =(it.st == "miss") and L("右键：要不到先不提醒（变灰，拿到后恢复）", "Right: can't get it - stop nagging until you have it") or L("右键：这次不再弹", "Right: snooze")
        GameTooltip:AddLine(L("左键：详情  ·  ", "Left: details · ") .. rt .. L("  ·  按住拖动：挪位置", " · Drag: move"), 0.5, 0.75, 1, true)
        GameTooltip:AddLine(L("Ctrl + 右键：永久关闭提醒条", "Ctrl + right-click: close the bar for good"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self, mb)
        local it = self.it
        if not it then return end
        -- 11-17 用户「这些弹出的功能都确保能永久关闭」：右键照旧只管这一项这一次；Ctrl + 右键 = 整条提醒条永久不出
        --   （存档 xpcheck.win = false，和设置页「显示提醒条」、窗口与提醒「经验提醒条」同一个键；聊天框提醒另有开关，不动）
        if mb == "RightButton" and IsControlKeyDown and IsControlKeyDown() then XC.CloseForGood(); return end
        if mb == "RightButton" then snooze[it.key] = true; XC.Update(); return end
        if XC.OpenPage then XC.OpenPage() end
    end)
    -- GI-225「提醒条可以移动」：原来要 Shift+拖，玩家不知道 → 直接按住拖（拖动不会触发点击）
    b:SetScript("OnDragStart", function() win:StartMoving() end)
    b:SetScript("OnDragStop", function() win:StopMovingOrSizing(); savePos() end)
    win.btns[i] = b
    return b
end

-- 进提醒条的：快没了的（warn，没被右键按掉）；「一直半透明」时再加上生效中的
local function barItems(res)
    local t = {}
    local on = opt("win", true) and not XC.hidden
    local always = opt("always", false)
    -- GI-225 移动模式：五项全摆出来给你拖（平时快没了才浮出来，没东西可拖）
    if XC.moving then return res end
    for _, r in ipairs(res) do
        -- 补上 / 刷新了 → 下次快没了照样弹。11-15 用户截图「要不到谁咋整」：原来缺（miss）也会立刻清掉 → 右键按不掉红框；
        --   改成拿到了（ok）才清：缺的右键 = 这次先不红（变灰），拿到以后再缺照样红
        if r.st == "ok" then snooze[r.key] = nil end
        if on then
            -- 快没了才弹：只认有倒计时的 + 睡袋层数（休息经验快满不算「快没了」，去页里看）
            local ending = r.st == "warn" and (r.left or r.key == "bag")
            if ending then
                if not snooze[r.key] then t[#t + 1] = r end
            elseif always then   -- 11-09 用户截图「没看见啊」：一直半透明 = 五项都摆出来（缺的灰掉），不是只摆有倒计时的
                t[#t + 1] = r
            end
        end
    end
    return t
end

function XC.Draw(res)
    local list = barItems(res)
    if #list == 0 then if win then win:Hide() end; return end
    win = win or buildWin()
    XC.win = win
    win.at = now()
    for i, r in ipairs(list) do
        local b = btn(i)
        b.it = r
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", win, "TOPLEFT", (i - 1) * (ICON_SZ + GAP), 0)
        b.ic:SetTexture(r.icon or XC.ICON[r.key])
        local dim = (r.st == "miss" or r.st == "info")
        if b.ic.SetDesaturated then b.ic:SetDesaturated(dim) end
        b.cnt:SetText((r.key == "bag" and (r.stacks or 0) > 0) and (r.stacks .. "/" .. XC.BAG_STACKS) or "")
        local ending = r.st == "warn" and (r.left or r.key == "bag")
        -- 11-09 用户截图「缺了高亮啊」：缺的不透明 + 红框 + 红字；生效中的半透明；快没了的不透明 + 金圈闪；冷却中的半透明灰
        local miss = r.st == "miss" and not snooze[r.key]
        b:SetAlpha((ending or miss) and 1 or IDLE_ALPHA)
        -- 11-10 用户截图「没了直接出高亮边框」：缺的也套闪动光圈（红色），快没了的照旧金色
        b.glow:SetShown((r.hi or miss) and true or false)
        if b.glow.SetVertexColor then
            if miss then b.glow:SetVertexColor(1, 0.25, 0.2) else b.glow:SetVertexColor(1, 0.82, 0.1) end
        end
        if miss then b.bg:SetColorTexture(1, 0.2, 0.15, 0.95)
        elseif ending then b.bg:SetColorTexture(1, 0.82, 0.1, 0.9)
        else b.bg:SetColorTexture(0, 0, 0, 0.85) end
        local c = ((r.hi and not snooze[r.key]) or miss) and COLOR.miss or (r.st == "warn" and COLOR.warn) or (dim and COLOR.info) or { 1, 1, 1 }
        local label = (r.left and short(r.left)) or (r.pct and (r.pct .. "%")) or (r.st == "miss" and L("缺", "-")) or ""
        b.time:SetText(label); b.time:SetTextColor(c[1], c[2], c[3])
        b:Show()
    end
    for i = #list + 1, #win.btns do win.btns[i]:Hide() end
    -- 11-17 合计：图标上面一行小字「经验 +8%」（设置可关）；逐项明细在图标的鼠标提示里
    local t = XC.total
    win.sumFs:SetText((opt("total", true) and t and (t.kill > 0 or t.quest > 0)) and (L("经验 ", "XP ") .. (t.approx and L("约 ", "~") or "") .. "+" .. math.max(t.kill, t.quest) .. "%") or "")
    win:SetWidth(#list * (ICON_SZ + GAP) - GAP)
    win:Show()
end

function XC.Update()
    if not ns.db then return end
    if not XC.Enabled() then if win then win:Hide() end; return end
    -- GI-211「没杀死一个怪，就提示没有睡袋和食物」：战斗中增益数据读不到（加密值），一读就全成「缺」，
    --   出战斗又读到 → 每打一只怪报一次「没了」。战斗中不查不画，提醒条保持进战斗前的样子
    if InCombatLockdown and InCombatLockdown() then return end
    local ok, res, done = pcall(XC.Check)
    if not ok then return end
    XC.last = res
    if done then if win then win:Hide() end; return end
    XC.Alerts(res)
    XC.Draw(res)
end

-- 聊天框一行汇总
function XC.Summary()
    local res, done = XC.Check()
    if done then ns.Print(L("经验加成：已满级，不用查了", "XP bonuses: max level")); return end
    local parts = {}
    for _, r in ipairs(res) do
        -- 11-09 用户截图：✓ ✗ 聊天字体里没有，显示成方框 → 用游戏自带的就绪检查图标（绿勾 / 红叉 / 问号）
        local mark = (r.st == "ok" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t") or (r.st == "warn" and "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t")
            or (r.st == "miss" and "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t") or "|cff999999·|r"
        parts[#parts + 1] = mark .. r.text
    end
    if #parts == 0 then return end
    ns.Print(L("经验加成：", "XP bonuses: ") .. table.concat(parts, "  ") .. ((opt("total", true) and XC.TotalText()) and ("  |cff40e060" .. XC.TotalText() .. "|r") or ""))
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
XC._ev = ev
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") else pcall(ev.RegisterEvent, ev, "UNIT_AURA") end
local lastAura, wasInst = 0, nil
-- 11-17 用户「练级buff补全器，可以从主城就开始准备」：进主城 / 旅店（休息状态）自动弹「出发前清单」（子插件按需加载），
--   离开休息区收起；回来再弹。设置「进主城弹出发前清单」可关（prep，默认开）；战斗中 / 副本 / 满级不弹
function XC.PrepCheck()
    local resting = IsResting and IsResting() and true or false
    if not resting then
        XC.wasResting = false
        if XC.Prep and XC.Prep.Hide then pcall(XC.Prep.Hide) end
        return
    end
    if XC.wasResting or (InCombatLockdown and InCombatLockdown()) then return end   -- 战斗中进城：脱战再弹
    XC.wasResting = true
    if not (XC.Enabled() and opt("prep", true)) or level() >= maxLevel() or inInstance() then return end
    if ns.XpLoad() and XC.Prep and XC.Prep.Show then pcall(XC.Prep.Show, true) end
end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "BAG_UPDATE_DELAYED" then XC.BagDirty() end
    -- 11-17 喊 BUFF 回谢：有人给我加了 BUFF（子插件 XpSupply.lua 的 XC.ThankAura；「总是回谢」开着时进世界就加载子插件）
    if ns.db and e == "UNIT_AURA" and a1 == "player" and XC.ThankAura then pcall(XC.ThankAura) end
    if ns.db and e == "PLAYER_ENTERING_WORLD" and XC.DB().thankAlways == true and XC.DB().thank ~= false and not XC.ThankAura
        and C_Timer and C_Timer.After then C_Timer.After(5, function() if not (InCombatLockdown and InCombatLockdown()) then ns.XpLoad() end end) end
    if not ns.db or not XC.Enabled() then return end
    if e == "PLAYER_UPDATE_RESTING" or e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(XC.PrepCheck) end) else pcall(XC.PrepCheck) end
    end
    if e == "UNIT_AURA" then
        if a1 ~= "player" or now() - lastAura < 1 then return end
        lastAura = now()
    elseif e == "PLAYER_REGEN_ENABLED" then
        XC.Flush()
    elseif e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_LEVEL_UP" or e == "ZONE_CHANGED_NEW_AREA" then
        local inst = inInstance()
        local leftInst = (wasInst == true and not inst)
        if e ~= "ZONE_CHANGED_NEW_AREA" or leftInst then
            if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(XC.Summary) end) end
        end
        wasInst = inst
    end
    XC.Update()
end)
table.insert(ns.modules, function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() pcall(XC.Update) end) end
end)

-- ---------- 主面板页签「经验加成」：11-17 起页面在按需加载的 GearInsight_Forever_Xp（PageXp.lua），这里只放占位 ----------
-- 用户 11-17「练级BUFF补全器…从主城就开始准备，路上碰到还可以刷新」「buff和来源要可视化对应」「物资等」：
--   页面（增益 / 物资 ←「从哪来」）、出发前清单、物资检查都在子插件里，登录不加载：点页签 / 左键提醒条 / /gi xp / 进主城（出发前清单开着）才加载。
--   这里留：检查 + 合计 + 到期提醒 + 提醒条（登录就要跑）；占位页名 / 顺序 / 图标要和 PageXp.lua 的真页一模一样
local XM = ns.LazyModule and ns.LazyModule({ key = "xp", addon = "GearInsight_Forever_Xp", zh = "经验加成", en = "XP bonuses", noCombat = true,   -- 页里有「用」安全按钮：战斗中不加载
    what = "经验加成页 / 出发前清单", whatEn = "XP page / departure checklist" }) or nil
XC.PAGE = { key = "xp", order = 1.87, title = ns.L("经验加成", "XP bonuses"), tabTitle = ns.L("经验加成", "XP"), icon = "Interface\\Icons\\INV_Misc_Tent" }
if XM then
    local d = {}
    for k, v in pairs(XC.PAGE) do d[k] = v end
    d.file = "PageXp.lua"
    XM:Page(d)
end
function ns.XpLoad() if ns._modReady.xp then return true end return XM and XM:Load(nil, true) or false end

-- 11-17 用户「这些弹出的功能都确保能永久关闭」：按需加载的子插件里会自己弹出来的东西，关掉后这个子插件登录时可能就不加载了，
--   真模块的「窗口与提醒」条目也就没了 → 这里放同 key 的占位：读存档显示状态，点「打开」写回存档再加载子插件（真模块加载后用同一个 key 顶替）
if XM then
    XM:Window({ key = "xpPrep", order = 31, title = function() return ns.L("出发前清单（进主城自动弹）", "Departure checklist (auto in towns)") end,
        state = function()
            return XC.DB().prep ~= false and ns.L("进主城 / 旅店时弹出", "Opens in towns / inns") or ns.L("已关闭（进城不自动弹）", "Closed (no auto-open)")
        end,
        actions = function()
            local auto = XC.DB().prep ~= false
            return { { text = auto and ns.L("关闭", "Turn off") or ns.L("打开", "Turn on"), fn = function()
                if auto then XC.DB().prep = false else XC.DB().prep = nil end
            end } }
        end }, "PageXp.lua")
end
function XC.RefreshPage() if XC.Page and XC.Page.Refresh then XC.Page.Refresh() end end

function XC.OpenPage()
    if ns.ToggleMain then
        local f = XC.page and XC.page:GetParent()
        if f and f:IsShown() and XC.page:IsShown() then XC.RefreshPage(); return end
        ns.ToggleMain("xp")
    end
end

-- ---------- 命令 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.xp = function(rest)
    rest = (rest or ""):lower()
    if rest == "off" then XC.Set("on", false); ns.Print(L("经验加成检查：已关", "XP check: off"))
    elseif rest == "on" then XC.Set("on", true); XC.hidden = false; ns.Print(L("经验加成检查：已开", "XP check: on"))
    elseif rest == "move" then XC.SetMoving(not XC.moving)
    elseif rest == "reset" then XC.ResetPos()
    elseif rest == "probe" then
        ns.ShowBox(L("经验加成探针", "XP probe"), L("Ctrl+C 复制发给开发者", "Ctrl+C to copy"), table.concat(XC.DB().probe or {}, "\n"))
    else
        -- 11-09 用户「/gi xp 无效」：汇总出错要说出来（原来报错被吞 / 全齐时小窗不出 → 看着像没反应），然后直接打开图形页
        XC.hidden = false
        if not XC.Enabled() then ns.Print(L("经验加成检查是关着的：/gi xp on 打开，或在页里点「已关闭」", "XP check is off: /gi xp on")) end
        local ok, err = pcall(XC.Summary)
        if not ok then ns.Print(L("经验加成检查出错（请截图发我们）：", "XP check error (please screenshot): ") .. tostring(err)) end
        pcall(XC.Update)
        XC.OpenPage()
    end
end
ns.ExtraSlash["经验"] = ns.ExtraSlash.xp

-- 11-12 重构第 1 期：提醒条登记进设置页「窗口与提醒」
ns.RegisterWindow({ key = "xpBar", order = 30, title = function() return L("经验提醒条", "XP reminder bar") end,
    state = function()
        if not XC.Enabled() then return L("经验加成检查已关", "XP check is off") end
        local d = XC.DB()
        if d.win == false then return L("不显示", "Off") end
        if d.always == true then return L("一直显示（半透明）", "Always shown") end
        return L("加成快没了才出", "Shown when a bonus is ending")
    end,
    actions = function()
        local on = XC.Enabled() and XC.DB().win ~= false
        return {
            { text = on and L("关闭", "Hide") or L("打开", "Show"), fn = function()
                if on then XC.Set("win", false)
                else XC.DB().on = true; XC.hidden = false; XC.Set("win", true) end
            end },
            { text = XC.moving and L("锁定位置", "Lock position") or L("移动", "Move"), fn = function() XC.SetMoving(not XC.moving) end },
            { text = L("重置位置", "Reset position"), fn = function() XC.ResetPos() end },
        }
    end })
-- 11-17 喊 BUFF 回谢框（弹框在按需加载的 XpSupply.lua）：点过「不再提示」= thank 存 false（永久关），这里找回
ns.RegisterWindow({ key = "xpThank", order = 31, title = function() return L("加 BUFF 回谢框", "Buff thank-you prompt") end,
    state = function()
        local d = XC.DB()
        if d.thank == false then return L("已关闭", "Off") end
        if d.thankAlways == true then return L("有人加 BUFF 就弹", "Whenever someone buffs you") end
        return L("喊过 BUFF 后 10 分钟内弹", "Within 10 min of asking")
    end,
    actions = function()
        local d = XC.DB()
        return {
            { text = d.thank == false and L("打开", "Turn on") or L("关闭", "Turn off"), fn = function() if d.thank == false then d.thank = nil else d.thank = false end end },
            { text = d.thankAlways == true and L("只在喊过之后", "Only after asking") or L("总是回谢", "Always"), fn = function() d.thankAlways = (d.thankAlways ~= true) or nil; if d.thankAlways then d.thank = nil end end },
        }
    end })
