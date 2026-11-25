-- 要 BUFF 诊断（/gi buff 诊断 · why · check）：现在缺什么、队里谁能给、上次副本为什么没要
--   11-21 从登录加载的组队信标 BuffAsk.lua 原样搬来（给灵魂石提醒的登录触发腾内存；只有敲命令时才用）：
--   BuffAsk.lua 的 slash 先 ns.LoadModule("mage") 加载本子插件再调 BA.Diag；本文件依赖信标的 ns.BuffAsk（BA.ClsName / BA.JoinNames / BA.BuffName 等）
--   网易DD 单文件夹包：_GroupMage 并进主插件、登录就加载，照常可用
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local BA = ns.BuffAsk
if not BA then return end
local function now() return (GetTime and GetTime()) or 0 end
local clsName, joinNames, buffName, inDungeon = BA.ClsName, BA.JoinNames, BA.BuffName, BA.InDungeon

BA.WHY = {
    off = { "副本里设成了「不管」（/gi buff 弹框 打开）", "dungeon buffs set to do nothing" }, notinst = { "不在副本里（野外是选中 / 指向能给 BUFF 的人时弹框问）", "not in a dungeon" },
    solo = { "没在队伍里", "not in a group" }, dead = { "你死着", "you are dead" }, combat = { "战斗中，脱战后再看", "in combat" },
    cooldown = { "刚要过，冷却中", "cooldown" }, noaura = { "读不到你身上的 BUFF（副本里游戏可能把 BUFF 信息保护起来了）", "can't read your buffs here" },
    full = { "你不缺 BUFF", "nothing missing" }, nogiver = { "队里没有能给你缺的 BUFF 的人（或者他们等级不够）", "nobody in the group can give what you miss" },
    send = { "发不出去（聊天受限）", "chat blocked" }, asked = { "这次进本已经要过了", "already asked this run" }, sent = { "已经要了", "asked" },
    showing = { "弹框还开着", "prompt still open" }, far = { "能给的队友离得远，走近了再问", "giver is far away - will ask when near" },
    instance = { "野外弹框在副本里不弹", "field prompt is off in dungeons" }, gap = { "离上次弹框不到 2 分钟", "prompt gap" },
    muted = { "这次登录点过「不再提示」", "muted this session" },
}
function BA.WhyText(k) local t = BA.WHY[k or ""]; return t and L(t[1], t[2]) or tostring(k) end
-- /gi buff 诊断：现在缺什么、队里谁能给、为什么没要
function BA.Diag()
    local out = {}
    local function add(s) out[#out + 1] = s end
    add(string.format(L("要 BUFF 诊断：总开关%s · 野外弹框%s · 副本里缺了%s", "Buff check: master %s / field %s / dungeon: %s"),
        BA.Opt("on") and L("开", "on") or L("关", "off"), BA.Opt("field") and L("开", "on") or L("关", "off"), BA.DModeText()))
    add(L("· 圣骑士祝福：", "· Paladin blessings: ") .. BA.BlessNoText())
    local ids = BA.MyAuras()
    if not ids then
        add(L("· 读不到你身上的 BUFF（受保护），这种时候插件不要，免得要重复", "· Can't read your buffs (protected) - won't ask"))
    else
        local miss = BA.Missing() or {}
        local names = {}
        for _, t in ipairs(BA.TYPES) do if miss[t.k] then names[#names + 1] = buffName(t) end end
        add(#names > 0 and (L("· 你缺：", "· Missing: ") .. table.concat(names, L("、", ", "))) or L("· 你不缺 BUFF", "· Nothing missing"))
        local inInst = inDungeon()
        if inInst then
            local plan = BA.PartyPlan(miss)
            if #plan == 0 then add(plan.far and "· " .. BA.WhyText("far") or L("· 队里没有能给的人", "· Nobody in the group can give them"))
            else for _, p in ipairs(plan) do add("· " .. clsName(p.cls) .. " " .. (tostring(p.who):gsub("%-.*$", "")) .. L(" 能给：", " can give: ") .. joinNames(p.list)) end end
        else
            add(L("· 不在副本里：野外要选中 / 鼠标指向能给的人（牧师 / 法师 / 德鲁伊 / 圣骑士）才弹框", "· Not in a dungeon: target or mouse over a giver to get the prompt"))
        end
    end
    local la = BA.lastAuto2
    if la then add(string.format(L("· 上次副本自动要：%s（%d 秒前）", "· Last dungeon check: %s (%ds ago)"), BA.WhyText(la.why), math.floor(now() - (la.t or now())))) end
    for _, s2 in ipairs(out) do ns.Print(s2) end
    return out
end

-- 示例框（11-23 从信标 BuffAsk.lua 的 /gi buff 命令搬来，给内核腾内存）：不发任何话
--   test = 野外示例 · test2 = 副本示例 · test3 / 测试祝福 = 圣骑士能给几种祝福时的选择行
function BA.Test(rest)
    if rest == "test2" or rest == "测试2" then
        return BA.ShowDungeon({ { cls = "PRIEST", who = L("示例牧师", "Sample Priest"), list = { BA.BY_K.fort } } }, true)
    end
    if rest == "test3" or rest == "测试3" or rest == "测试祝福" then
        local ch, cls = {}, UnitClass and select(2, UnitClass("player"))
        for _, t in ipairs(BA.BlessOrder()) do if BA.Useful(t, cls) then ch[#ch + 1] = t end end
        if #ch < 2 then ch = { BA.BY_K.kings, BA.BY_K.might } end
        BA.ShowField({ who = L("示例圣骑士", "Sample Paladin"), cls = "PALADIN", lv = 40, list = { ch[1] }, choices = ch, sample = true })
    else
        BA.ShowField({ who = L("示例牧师", "Sample Priest"), cls = "PRIEST", lv = 40, list = { BA.BY_K.fort }, sample = true })
    end
    BA.cur = nil   -- 示例框：点「密他要」不发（FieldSend 没有 cur 直接回）
end
