-- 低等级技能提醒（11-14 用户转来群友「急需无限 WA 低级技能检查…以前时光服有…你搞一个，让插件通报朋友调整」，附的 WA 是 WLK 老版，无限用不了）
--   WA 的做法：施法成功 → 查「技能 id → 第几级 / 下一级几级学」表 → 自己的在聊天框提示，队友的私聊一次
--   这里：
--   · 数据 = TrainNowData.lua（客户端 DB2 × 训练师窗口实测对上的，TrainNow.Rows 解析）：同名技能各级的学习等级；不另带一份表
--   · 自己：放的这级比「已经学会的最高级」低 → 聊天框一行（只有自己看得到）；按 IsSpellKnown 判断，不会误报没学的
--   · 队友（小队 / 团队）：对方等级 ≥ 更高一级的学习等级 + LR.GRACE（刚升级还没去训练师的先不打扰）→ 私聊提醒
--     同一人同一技能整次登录只提醒一次；几秒内放的几个低级技能合成一条；自己脱战后才发；
--     同队几个人都装了插件时只发一份（发之前在插件频道认领，收到别人认领的就不发了）；战场里不提醒
--   · 故意用低级的不管：治疗类（降级省蓝是常规打法）、造水 / 造食（给低级朋友做）、寒冰箭 / 放逐术 1 级（低仇恨减速 / 放逐时间短好控）
--   · 开关：设置页「技能与训练师」三个勾（自己 / 私聊队友 / 队伍频道点名），/gi 低级技能 开 | 关 | 私聊开 | 私聊关 | 点名开 | 点名关；
--     存 ns.db.ui.lowRank / lowRankW / lowRankP（nil = 开，false = 关）
--   · 11-14 用户「队伍频道点名也加上」（WA 的 raidreport）：在小队 / 团队频道说「某某 刚才用的…」，用户随后定「点名默认打开吧」→ 默认开；
--     随机队伍（副本查找器那种）不点名，和 WA 一样；同队别人认领过的照样不重复
--   · 11-14 用户「前缀也加上，可配置」：私聊和点名开头带前缀，默认「[GI技能提醒]」；设置页输入框 / /gi 低级技能 前缀 xxx 改，
--     清空 = 不带（/gi 低级技能 前缀 无），/gi 低级技能 前缀 默认 恢复；存 ns.db.ui.lowRankTag（nil = 默认，"" = 不带）
local _, ns = ...

local LR = {}
ns.LowRank = LR

local function L(cn, en) return ns.L(cn, en) end

LR.GRACE = 2          -- 队友：比更高一级的学习等级再高 2 级才提醒
LR.BATCH = 4          -- 收到第一个低级技能后等几秒再发（把接连放的几个合成一条）
LR.MAX_AGE = 600      -- 一直在战斗里发不出去的，10 分钟后作废
LR.PREFIX = "GIFLR"

LR.SKIP = {
    -- 治疗：降级省蓝是常规打法
    ["圣光术"] = true, ["圣光闪现"] = true, ["次级治疗术"] = true, ["治疗术"] = true, ["强效治疗术"] = true, ["快速治疗"] = true,
    ["恢复"] = true, ["治疗祷言"] = true, ["愈合祷言"] = true, ["苦修"] = true, ["治疗波"] = true, ["次级治疗波"] = true,
    ["治疗链"] = true, ["激流"] = true, ["治疗之触"] = true, ["愈合"] = true, ["回春术"] = true, ["野性成长"] = true, ["治疗宠物"] = true,
    -- 法师给低级朋友做吃喝
    ["造水术"] = true, ["造食术"] = true,
}
LR.SKIP_RANK1 = { ["寒冰箭"] = true, ["放逐术"] = true }

-- ---------- 设置 ----------
local function ui() ns.db.ui = ns.db.ui or {}; return ns.db.ui end
function LR.On() return not (ns.db and ns.db.ui and ns.db.ui.lowRank == false) end
function LR.WhisperOn() return not (ns.db and ns.db.ui and ns.db.ui.lowRankW == false) end
function LR.SetOn(v) if ns.db then if v then ui().lowRank = nil else ui().lowRank = false end end end
function LR.SetWhisper(v) if ns.db then if v then ui().lowRankW = nil else ui().lowRankW = false end end end
LR.DEFAULT_TAG = "[GI技能提醒]"
function LR.Tag()
    local t = ns.db and ns.db.ui and ns.db.ui.lowRankTag
    if type(t) ~= "string" then return LR.DEFAULT_TAG end
    return t
end
function LR.SetTag(v)
    if not ns.db then return end
    if v == nil then ui().lowRankTag = nil; return end   -- 恢复默认
    v = tostring(v):gsub("^[ \t]+", ""):gsub("[ \t]+$", ""):gsub("|", "")   -- 去掉聊天转义符，免得发不出去；⛔别用 %s：个别区域设置把 0xA0 当空格，会切坏「无」这类字
    ui().lowRankTag = v
end
local function withTag(msg)
    local t = LR.Tag()
    return t ~= "" and (t .. " " .. msg) or msg
end
function LR.PartyOn() return not (ns.db and ns.db.ui and ns.db.ui.lowRankP == false) end
function LR.SetParty(v) if ns.db then if v then ui().lowRankP = nil else ui().lowRankP = false end end end

-- ---------- 数据：法术 id → { n, r, ranks = { {r, lv, id, pre}… 按 r 升序 } } ----------
local index
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
function LR.Index()
    if index then return index end
    local TN = ns.TrainNow
    if not (TN and TN.Rows) then return nil end
    index = {}
    for _, cls in ipairs(CLASSES) do
        local byName = {}
        for _, e in ipairs(TN.Rows(cls) or {}) do
            if e.r and e.r > 0 and e.id then
                byName[e.n] = byName[e.n] or {}
                table.insert(byName[e.n], { r = e.r, lv = e.lv, id = e.id, pre = (e.c == -1) })
            end
        end
        for n, ranks in pairs(byName) do
            if #ranks > 1 and not LR.SKIP[n] then
                table.sort(ranks, function(a, b) return a.r < b.r end)
                for _, k in ipairs(ranks) do index[k.id] = { n = n, r = k.r, cls = cls, ranks = ranks } end
            end
        end
    end
    return index
end

function LR.Info(id)
    local idx = LR.Index()
    local info = idx and id and idx[id]
    if not info then return nil end
    if info.r == 1 and LR.SKIP_RANK1[info.n] then return nil end
    return info
end

-- 这个等级在训练师那能学到的最高一级（任务给的「前置」级不算可学）
function LR.BestFor(info, level)
    local best
    for _, k in ipairs(info.ranks) do
        if not k.pre and k.lv <= level and (not best or k.r > best.r) then best = k end
    end
    return best
end

-- 自己已经学会的最高一级
function LR.BestKnown(info)
    local known = ns.TrainNow and ns.TrainNow.Known
    if not known then return nil end
    local best
    for _, k in ipairs(info.ranks) do
        if known(k.id) and (not best or k.r > best.r) then best = k end
    end
    return best
end

-- ---------- 判定 ----------
local told = {}       -- [guid .. "|" .. 技能名] = true：这次登录已经提醒过 / 别人认领过
local pending = {}    -- [guid] = { name, unit, due, at, list = { {n, r, best, lv}… } }
LR.told, LR.pending = told, pending

local function now() return GetTime and GetTime() or 0 end
local function inPvp()
    if UnitInBattleground and UnitInBattleground("player") then return true end
    if IsInInstance then
        local _, t = IsInInstance()
        if t == "pvp" or t == "arena" then return true end
    end
    return false
end
local function groupUnit(u) return u == "player" or (type(u) == "string" and (u:match("^party%d+$") or u:match("^raid%d+$"))) end
local function spellText(id, n)
    local link = GetSpellLink and GetSpellLink(id)
    return (type(link) == "string" and link ~= "") and link or ("【" .. n .. "】")
end

-- 返回提醒类型（"self" / "mate" / nil），测试用
function LR.OnCast(unit, spellID)
    if not LR.On() or not groupUnit(unit) or not UnitGUID then return nil end
    local info = LR.Info(spellID)
    if not info or inPvp() then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local key = guid .. "|" .. info.n
    if told[key] then return nil end

    if unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player")) then
        local best = LR.BestKnown(info)
        if not best or best.r <= info.r then return nil end
        told[key] = true
        ns.Print(string.format(L("你刚才用的 %s 是 %d 级，你已经学会 %d 级了，动作条上的可以换成高级的。",
            "You just cast %s rank %d but you know rank %d. Update your action bar."), spellText(spellID, info.n), info.r, best.r)
            .. L("（/gi 低级技能 关）", " (/gi lowrank off)"))
        return "self"
    end

    if not LR.WhisperOn() and not LR.PartyOn() then return nil end
    local lv = UnitLevel and UnitLevel(unit) or 0
    if not lv or lv <= 0 then return nil end
    local best = LR.BestFor(info, lv - LR.GRACE)
    if not best or best.r <= info.r then return nil end
    local name = UnitName and UnitName(unit)
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    local full = name
    if UnitFullName then
        local n2, realm = UnitFullName(unit)
        if n2 and realm and realm ~= "" then full = n2 .. "-" .. realm end
    end
    told[key] = true
    local p = pending[guid]
    if not p then
        p = { name = full, short = name, at = now(), due = now() + LR.BATCH + math.random(0, 30) / 10, list = {} }
        pending[guid] = p
    end
    table.insert(p.list, { n = info.n, r = info.r, best = best.r, id = spellID })
    return "mate"
end

local function cut255(msg)
    if #msg <= 255 then return msg end
    local i = 256
    while i > 1 and msg:byte(i) and msg:byte(i) >= 128 and msg:byte(i) < 192 do i = i - 1 end   -- 别从一个汉字中间切开
    return msg:sub(1, i - 1)
end
LR.Cut255 = cut255

local function spellList(p)
    local parts = {}
    for i, s in ipairs(p.list) do
        if i > 3 then break end
        parts[#parts + 1] = string.format(L("【%s】%d级（能学%d级了）", "[%s] rank %d (rank %d available)"), s.n, s.r, s.best)
    end
    return table.concat(parts, L("、", ", "))
end

function LR.Message(p)
    local msg = withTag(L("友情提醒：你刚才用的 ", "Friendly heads-up: you just used ")) .. spellList(p)
        .. L("，去训练师学一下，再把动作条上的换成新的就好～打扰啦", ". Visit your trainer and update your action bar. Sorry to bother!")
    return cut255(msg)
end

-- 队伍频道点名
function LR.PartyMessage(p)
    return cut255(withTag(string.format(L("%s 刚才用的 %s，记得去训练师学一下、换上新的～", "%s just used %s - time to visit the trainer!"), p.short or p.name, spellList(p))))
end

local function groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) then return nil end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function claim(guid, list)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local ch = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    if not ch then return end
    for _, s in ipairs(list) do pcall(C_ChatInfo.SendAddonMessage, LR.PREFIX, "C\t" .. guid .. "\t" .. s.n, ch) end
end

-- 到点的私聊发出去（自己战斗中先压着）
function LR.Flush(t)
    t = t or now()
    local fighting = (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown())
    local sent = 0
    for guid, p in pairs(pending) do
        if t - p.at > LR.MAX_AGE then
            pending[guid] = nil
        elseif t >= p.due and not fighting then
            pending[guid] = nil
            local keep = {}
            for _, s in ipairs(p.list) do if not p.claimed or not p.claimed[s.n] then keep[#keep + 1] = s end end
            if #keep > 0 and SendChatMessage then
                p.list = keep
                claim(guid, keep)
                if LR.WhisperOn() then SendChatMessage(LR.Message(p), "WHISPER", nil, p.name); sent = sent + 1 end
                local ch = LR.PartyOn() and groupChannel()
                if ch then SendChatMessage(LR.PartyMessage(p), ch); sent = sent + 1 end
            end
        end
    end
    return sent
end

-- 别的装插件的队友认领了：同一人同一技能我就不发了
function LR.OnClaim(msg, sender)
    local kind, guid, n = (msg or ""):match("^(%a)\t([^\t]+)\t(.+)$")
    if kind ~= "C" or not guid or not n then return end
    local me = UnitName and UnitName("player")
    if sender and me and (sender == me or sender:match("^([^%-]+)") == me) then return end
    told[guid .. "|" .. n] = true
    local p = pending[guid]
    if p then p.claimed = p.claimed or {}; p.claimed[n] = true end
end

-- ---------- 事件 ----------
local f = CreateFrame("Frame")
LR.frame = f
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, LR.PREFIX)
elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, LR.PREFIX) end

local acc = 0
f:SetScript("OnUpdate", function(_, el)
    if not next(pending) then return end
    acc = acc + (el or 0)
    if acc < 1 then return end
    acc = 0
    LR.Flush()
end)
f:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
    if ev == "UNIT_SPELLCAST_SUCCEEDED" then
        -- 经典客户端：unit, castGUID, spellID
        local id = a3 or a2
        if type(id) == "number" and ns.db then pcall(LR.OnCast, a1, id) end
    elseif ev == "CHAT_MSG_ADDON" then
        if a1 == LR.PREFIX then LR.OnClaim(a2, a4) end
    elseif ev == "PLAYER_REGEN_ENABLED" then
        if next(pending) then LR.Flush() end
    end
end)

-- ---------- 命令 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
do
    ns.ExtraSlash["低级技能"] = function(rest, rawRest)
        local tag = (rawRest or ""):match("^前缀[ \t]*(.-)[ \t]*$") or (rawRest or ""):match("^[Pp][Rr][Ee][Ff][Ii][Xx][ \t]*(.-)[ \t]*$")
        if tag then
            if tag == "默认" or tag == "default" then LR.SetTag(nil)
            elseif tag == "无" or tag == "none" or tag == "" then LR.SetTag("")
            else LR.SetTag(tag) end
            local t = LR.Tag()
            ns.Print(L("低等级技能提醒的前缀：", "Low-rank message prefix: ") .. (t ~= "" and t or L("（不带）", "(none)"))
                .. L("。/gi 低级技能 前缀 文字 | 无 | 默认", ". /gi lowrank prefix <text>|none|default"))
            return
        end
        rest = (rest or ""):gsub("[ \t]+", "")
        if rest == "开" or rest == "on" then LR.SetOn(true)
        elseif rest == "关" or rest == "off" then LR.SetOn(false)
        elseif rest == "私聊开" or rest == "whisper" then LR.SetWhisper(true)
        elseif rest == "私聊关" or rest == "nowhisper" then LR.SetWhisper(false)
        elseif rest == "点名开" or rest == "party" then LR.SetParty(true)
        elseif rest == "点名关" or rest == "noparty" then LR.SetParty(false) end
        local function s(v) return v and L("开", "on") or L("关", "off") end
        ns.Print(L("低等级技能提醒：", "Low-rank spell check: ") .. s(LR.On()) .. L("；私聊提醒队友：", "; whisper teammates: ") .. s(LR.WhisperOn())
            .. L("；队伍频道点名：", "; call out in group chat: ") .. s(LR.PartyOn())
            .. L("；前缀：", "; prefix: ") .. (LR.Tag() ~= "" and LR.Tag() or L("（不带）", "(none)"))
            .. L("。/gi 低级技能 开 | 关 | 私聊开 | 私聊关 | 点名开 | 点名关 | 前缀 文字", ". /gi lowrank on|off|whisper|nowhisper|party|noparty|prefix <text>"))
    end
    ns.ExtraSlash.lowrank = ns.ExtraSlash["低级技能"]
end
