-- 帐篷蹭露营（11-08 用户截图「能不能构思一个看到帐篷自动检测，弹出，选择是否密语，自动请求加入队伍蹭露营的功能」
--   +「蹭完以后自动感谢」）。
--   1. 发现：插件拿不到世界物体列表 → 鼠标指到帐篷时读提示框（第 1 行带「帐篷」、某行「由 XXX 放置」）认出帐篷和主人
--   2. 弹一条：「附近有 XXX 放的帐篷，密他求组蹭露营？」[密语求组] [不用]；⛔ 不点不发（不主动给陌生人发密语），
--      同一个主人 30 分钟只问一次；自己的帐篷 / 已在他队里 / 已有露营效果 / 战斗中 / 副本里都不弹
--   3. 点「请求加入」→ 发系统的入队申请（C_PartyInfo.RequestInviteFromUnit）+ 密一句；⛔ 不自动接受任何邀请（11-08 用户：
--      「不要自动接收，都是等对方同意，咱们可以自动请求加入」），对方同意了才进队；进队后提示在帐篷旁坐下 60 秒
--   4. 感谢：跟主人同队过、之后离队 → 自动密一句谢谢（每个主人一次）；/gi camp thank off 关
--   5. 探针：提示框原文 + 帐篷附近增益变化记进存档，/gi camp probe 弹框复制（露营增益是哪个、英文客户端格式都等它定）
local _, ns = ...
local L = ns.L

local CP = {}
ns.Camp = CP

CP.ASK_CD = 1800       -- 同一个主人多久再问
CP.NEAR = 180          -- 见到帐篷后多久内记增益变化（探针）
CP.TENT = { "帐篷", "帳篷", "[Tt]ent" }
CP.OWNER = { "由%s*(.-)%s*放置", "[Pp]laced by%s+([^>]-)%s*>?$" }
CP.BUFF = { "露营", "露營", "帐篷", "帳篷", "[Cc]amp" }   -- 露营增益名字关键词（只当线索：名字对上还得提示里写着经验才算）
-- 11-09 用户截图：「强化休息」1229451 = 1 小时内不能再从营地帐篷拿充分休息经验 → 有它就别弹（蹭了也白蹭）
CP.LOCK_IDS = { [1229451] = true }
CP.LOCK = { "强化休息", "強化休息" }
-- 11-09 /gi xp probe：帐篷经验加成 = 露营增益 1229741（30 分钟，和强化休息同时挂）
CP.TENT_IDS = { [1229741] = true }
-- GI-234 玩家「在帐篷里获得了露营增益，但是没有经验加成，再指帐篷一直提示已有帐篷增益」：
--   没进主人队伍时站在帐篷里也会挂一个「露营」类效果，名字撞上关键词就被当成「已有帐篷经验」→ 永远不弹。
--   → 只有真带经验加成的才算：ID 1229741（提示读得到却没写经验也不算）/ 名字像露营且提示里写着经验；
--     读不到、保密值一律不算已有（宁可多弹一次，也不能挡住蹭帐篷）
CP.XP_WORDS = { "经验", "經驗", "[Ee]xperience", "XP" }
-- 11-11 用户截图「营火在附近」1283391（营火的增益，英文 Campfire 会撞上 [Cc]amp）：不是露营效果，有它照样弹
CP.BUFF_SKIP_IDS = { [1283391] = true }
CP.BUFF_SKIP = { "营火", "營火", "[Cc]ampfire" }

CP.asked, CP.whispered, CP.thanked = {}, {}, {}
CP.joined = nil        -- { who, at }
CP.seenAt = 0

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return ns.Secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end
function CP.DB()
    ns.db.camp = ns.db.camp or {}
    return ns.db.camp
end
local function on(k) return CP.DB()[k] ~= false end
function CP.Enabled() return on("on") end
function CP.SetOn(v) CP.DB().on = v and true or false; if not v and CP.pop then CP.pop:Hide() end end
local function short(n) n = str(n); return n and (n:match("^([^%-]+)") or n) or nil end

local function anyMatch(s, pats)
    for _, p in ipairs(pats) do if s:find(p) then return true end end
    return false
end

-- 提示框几行 → 是不是帐篷、主人是谁
function CP.Parse(lines)
    local first = str(lines[1])
    if not first or not anyMatch(first, CP.TENT) then return false end
    for i = 1, #lines do
        local s = str(lines[i])
        if s then
            for _, p in ipairs(CP.OWNER) do
                local who = s:match(p)
                who = who and who:gsub("^[<%s]+", ""):gsub("[>%s]+$", "")
                if who and who ~= "" then return true, who end
            end
        end
    end
    return true, nil
end

-- 自己的全名（《无限》名字带姓：GetUnitName("player", true) 回「名 姓」）
local function isMe(who)
    local me = str(UnitName and UnitName("player"))
    if not me then return false end
    if who == me then return true end
    if GetUnitName then
        local ok, full = pcall(GetUnitName, "player", true)
        full = ok and short(full)
        if full and who == full then return true end
    end
    return false
end

-- 跟谁同队（名字可能带姓 / 带服务器）
function CP.InGroupWith(who)
    if not who or not (IsInGroup and IsInGroup()) then return false end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or ("party" .. i)
        local nm
        if GetUnitName then
            local ok, v = pcall(GetUnitName, u, true)
            nm = ok and short(v)
        end
        if not nm and UnitName then nm = short(UnitName(u)) end
        if nm and (nm == who or who:sub(1, #nm + 1) == nm .. " " or nm:sub(1, #who + 1) == who .. " ") then return true end
    end
    return false
end

-- 身上有没有露营效果
local function eachBuff(fn, filter)
    filter = filter or "HELPFUL"
    for i = 1, 40 do
        local name, sid
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
            if not ok or not a then break end
            name, sid = a.name, a.spellId
        elseif UnitBuff then
            local ok, n, _, _, _, _, _, _, _, s = pcall(filter == "HARMFUL" and UnitDebuff or UnitBuff, "player", i)
            if not ok or not n then break end
            name, sid = n, s
        else break end
        if fn(str(name), (sid ~= nil and not secret(sid)) and tonumber(sid) or nil, i, filter) then return true end
    end
    return false
end

-- 增益的鼠标提示原文（读不到 / 保密值 → nil）
function CP.AuraTip(i, filter)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then return nil end
    local ok, d = pcall(C_TooltipInfo.GetUnitAura, "player", i, filter)
    if not ok or type(d) ~= "table" or type(d.lines) ~= "table" then return nil end
    local t = {}
    for _, ln in ipairs(d.lines) do
        local s = type(ln) == "table" and str(ln.leftText)
        if s then t[#t + 1] = s end
    end
    return #t > 0 and table.concat(t, " ") or nil
end

-- 这个增益算哪类：lockout（强化休息冷却）/ xp（真带经验的帐篷加成）/ nonxp（名字像露营但没经验）/ nil（不相干）
--   tip = 鼠标提示原文；nil = 读不到
function CP.TentKind(name, sid, tip)
    if (sid and CP.BUFF_SKIP_IDS[sid]) or (name and anyMatch(name, CP.BUFF_SKIP)) then return nil end
    if (sid and CP.LOCK_IDS[sid]) or (name and anyMatch(name, CP.LOCK)) then return "lockout" end
    local byId = sid and CP.TENT_IDS[sid]
    if not byId and not (name and anyMatch(name, CP.BUFF)) then return nil end
    local xp = tip and anyMatch(tip, CP.XP_WORDS)
    if byId then
        if tip and not xp then return "nonxp" end   -- 提示读到了却没写经验：不当成加成
        return "xp"
    end
    return xp and "xp" or "nonxp"                   -- 只靠名字的：提示里得写着经验（读不到不算）
end

-- 返回 has, 效果名, 原因（"xp" 已有帐篷经验 / "lockout" 强化休息冷却）, 名字像露营但没经验的那个效果名
function CP.HasCampBuff()
    local found, kind, nonxp
    local function hit(name, sid, i, filter)
        local tentish = (sid and (CP.TENT_IDS[sid] or CP.LOCK_IDS[sid])) or (name and (anyMatch(name, CP.BUFF) or anyMatch(name, CP.LOCK)))
        if not tentish then return false end
        local k = CP.TentKind(name, sid, CP.AuraTip(i, filter))
        if k == "xp" or k == "lockout" then found, kind = name or tostring(sid), k; return true end
        if k == "nonxp" then nonxp = nonxp or name or tostring(sid) end
        return false
    end
    -- 强化休息这类冷却可能挂成减益，两边都看
    if eachBuff(hit) or eachBuff(hit, "HARMFUL") then return true, found, kind end
    return false, nil, nil, nonxp
end

-- ---------- 探针 ----------
local function probeAdd(line)
    local d = CP.DB()
    d.probe = d.probe or {}
    for _, l in ipairs(d.probe) do if l == line then return end end
    if #d.probe >= 60 then table.remove(d.probe, 1) end
    d.probe[#d.probe + 1] = line
end
local lastBuffs
function CP.OnAura()
    local cur = {}
    eachBuff(function(name, sid) if name or sid then cur[(sid or 0) .. ":" .. (name or "?")] = true end; return false end)
    if lastBuffs and now() - CP.seenAt < CP.NEAR then
        for k in pairs(cur) do if not lastBuffs[k] then probeAdd("buff+ " .. k .. (IsInGroup and IsInGroup() and " grp" or " solo")) end end
        for k in pairs(lastBuffs) do if not cur[k] then probeAdd("buff- " .. k) end end
    end
    lastBuffs = cur
end

-- ---------- 弹窗 ----------
local pop
local function buildPop()
    local f = CreateFrame("Frame", "GearInsightForeverCampPop", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(360, 74); f:SetPoint("TOP", 0, -150); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.05, 0.9); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.85)
    end
    f.t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.t:SetPoint("TOPLEFT", 10, -10); f.t:SetPoint("TOPRIGHT", -10, -10); f.t:SetJustifyH("LEFT"); f.t:SetWordWrap(true)
    f.yes = ns.Button(f, L("密他求组", "Whisper"), 120, 22, function() f:Hide(); CP.Request(f.owner) end)
    f.yes:SetPoint("BOTTOMLEFT", 10, 8)
    f.no = ns.Button(f, L("不用", "No thanks"), 80, 22, function() f:Hide() end)
    f.no:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)
    -- 11-08 玩家「鼠标路过别人帐篷 组队的 哪里关啊」：弹窗上直接给「不再提示」，设置页也有开关
    f.off = ns.Button(f, L("不再提示", "Don't ask again"), 90, 22, function()
        f:Hide(); CP.SetOn(false)
        ns.Print(string.format(L("帐篷蹭露营提示已关：设置页「界面」栏或 %s camp on 可重新打开", "Tent prompts off - turn back on in Settings or with %s camp on"), ns.SlashHint or "/gi"))
    end)
    f.off:SetPoint("BOTTOMRIGHT", -10, 8)
    f:Hide()
    return f
end

-- 11-09 用户截图「为啥不弹了？」：不弹时第二个返回值说原因（ReadTooltip 在聊天框提示一次，免得以为坏了）
function CP.CanOffer(who)
    if not who or isMe(who) then return false end
    if not on("on") then return false, "off" end
    if InCombatLockdown and InCombatLockdown() then return false end
    if IsInInstance then local inst = IsInInstance(); if inst then return false end end
    if now() - (CP.asked[who] or -1e9) < CP.ASK_CD then return false, "asked" end
    if CP.InGroupWith(who) then return false end
    local has, buff, kind, nonxp = CP.HasCampBuff()
    if has then return false, (kind == "lockout") and "lockout" or "buff", buff end
    CP.nonxp = nonxp   -- 身上有「露营」但没经验：照样弹，弹窗里说一句
    return true
end

-- GI-227 玩家「关了之后一直在聊天频道提示，太烦人了」：原来按「原因+主人」各 10 分钟一次，帐篷多的地方就刷屏
-- → 只按原因算：自己关掉的（off）本次登录只说一次；buff / asked 不分主人 30 分钟一次
CP.WHY_CD = 1800
CP.whyNoted = {}
function CP.NoteWhy(who, why, extra)
    if not why then return end
    if why == "off" then
        if CP.whyNoted.off then return end
    elseif now() - (CP.whyNoted[why] or -1e9) < CP.WHY_CD then return end
    CP.whyNoted[why] = now()
    local slash = ns.SlashHint or "/gi"
    local msg
    if why == "off" then
        msg = string.format(L("看到 %s 的帐篷，但帐篷蹭露营提示是关的（点过「不再提示」）：设置页「界面」栏或 %s camp on 打开（本次登录不再说）",
            "Saw %s's tent, but tent prompts are off - turn on in Settings or with %s camp on (won't repeat this session)"), who, slash)
    elseif why == "buff" then
        msg = string.format(L("看到 %s 的帐篷，没弹：你身上已有带经验加成的帐篷效果「%s」（不用再蹭）",
            "Saw %s's tent, not prompting: you already have the tent XP bonus \"%s\""), who, extra or "?")
    elseif why == "lockout" then
        msg = string.format(L("看到 %s 的帐篷，没弹：你身上有「%s」（1 小时内帐篷给不了经验，蹭了也白蹭）",
            "Saw %s's tent, not prompting: you have \"%s\" (no tent XP for 1 hour)"), who, extra or "?")
    elseif why == "asked" then
        local left = math.ceil((CP.ASK_CD - (now() - (CP.asked[who] or 0))) / 60)
        msg = string.format(L("看到 %s 的帐篷，没弹：30 分钟内已经问过这个主人（还有 %d 分钟）",
            "Saw %s's tent, not prompting: already asked this owner (%d min left)"), who, left)
    end
    if msg then ns.Print(msg) end
end

function CP.Offer(who)
    local can, why, extra = CP.CanOffer(who)
    if not can then CP.NoteWhy(who, why, extra); return false end
    CP.asked[who] = now()
    pop = pop or buildPop()
    CP.pop = pop
    pop.owner = who
    local text = string.format(L("附近有 |cffffd100%s|r 放的帐篷，密他求组蹭露营？（他拉你才进队）", "|cffffd100%s|r placed a tent nearby. Whisper them for an invite?"), who)
    if CP.nonxp then
        text = text .. "\n" .. string.format(L("你身上的「%s」没有经验加成：进他队伍后在帐篷旁坐满 60 秒才有", "Your \"%s\" gives no XP: join their group and sit by the tent for 60 seconds"), CP.nonxp)
    end
    pop.t:SetText(text)
    -- 11-08 用户截图：主人名字长（「看我脸色行事 大天使泰瑞尔」）时第三行被截掉 → 按文字实际高度撑开
    local th = tonumber(pop.t.GetStringHeight and pop.t:GetStringHeight()) or 28
    pop:SetHeight(math.max(74, th + 50))
    pop:Show()
    pop.at = now()
    if C_Timer and C_Timer.After then
        local at = pop.at
        C_Timer.After(30, function() if pop and pop.at == at then pop:Hide() end end)
    end
    return true
end

local function send(msg, who)
    local f = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not (f and msg and who) then return false end
    return (pcall(f, msg, "WHISPER", nil, who))
end

-- 11-09 用户「措辞委婉点，比如说老哥，求xxx」→「多弄几个变体，可以随机出，不至于被认出来」：
--   求组 / 感谢各一池随机挑，和上一句不重样；/gi camp msg、/gi camp thanks 自定义了就只用自定义的
CP.ASK = {
    { "老哥，求拉一下蹭个帐篷~ 坐一分钟就走，谢谢啦！", "Hey friend, mind inviting me to share your tent? Just a minute, thanks a lot!" },
    { "大佬，能拉我进队蹭下帐篷不？蹭完就退，感谢感谢~", "Hi! Could you invite me to rest at your tent? I'll leave right after, thanks!" },
    { "兄弟，路过看到你的帐篷，求带一下~ 坐会儿就走", "Hey, saw your tent - mind inviting me for a minute?" },
    { "老板好，求组一下蹭个帐篷经验，一分钟就退，谢啦！", "Hello! Could I join for a minute to use your tent? Thanks!" },
    { "老哥你好~ 帐篷能借我坐一下不？拉我进队就行，蹭完马上走", "Hi there - could I borrow a spot at your tent? Just invite me, I'll head off soon after." },
    { "打扰啦，求拉进队蹭个帐篷，坐满一分钟就退，谢谢老哥！", "Sorry to bother - could you invite me to share the tent? Only a minute, thank you!" },
    { "好心人求拉一下~ 想在你帐篷边坐会儿，马上就走", "Kind stranger, could you invite me to sit by your tent for a bit?" },
}
CP.THANK = {
    { "谢谢老哥的帐篷，祝你玩得开心！", "Thanks for the tent, have fun!" },
    { "蹭完啦，谢谢大佬~ 祝出好装备！", "All done - thank you! Good luck with your loot!" },
    { "谢谢兄弟，帐篷很舒服，一路顺风~", "Thanks a lot, the tent was great. Safe travels!" },
    { "感谢老板的帐篷！祝升级飞快~", "Thanks for the tent! Happy leveling!" },
    { "谢谢好心人~ 有缘再见！", "Thank you, kind stranger - see you around!" },
}
local lastPick = {}
function CP.Pick(pool)
    local n = #pool
    local i = math.random(1, n)
    if n > 1 and i == lastPick[pool] then i = i % n + 1 end
    lastPick[pool] = i
    return L(pool[i][1], pool[i][2])
end

-- 11-10 用户「无限露营主动发私聊就行，申请加入功能放到设置，默认关闭」：点了只密一句（对方愿意就拉你）；
--   系统入队申请（RequestInviteFromUnit）改成设置项 camp.reqJoin，默认关
function CP.ReqJoinOn() return CP.DB().reqJoin == true end
-- 求组：密一句说明来意（+ 设置里开了才发系统入队申请）；不自动接受任何邀请
function CP.Request(who)
    if not who then return false end
    local req = false
    if CP.ReqJoinOn() and C_PartyInfo and C_PartyInfo.RequestInviteFromUnit then
        req = (pcall(C_PartyInfo.RequestInviteFromUnit, who))
    end
    local msg = CP.DB().msg or CP.Pick(CP.ASK)
    local sent = send(msg, who)
    -- 11-09 用户「只主动拒绝露营申请的人」：再发一个插件暗号，对方插件靠它认出这是来蹭露营的（自定义话术里没「帐篷」也认得出）
    local am = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if am then pcall(am, CP.PREFIX, "ask", "WHISPER", who) end
    if not (req or sent) then return false end
    CP.whispered[who] = now()
    ns.Print(string.format(req and L("已密 %s 并发了入队申请，等对方同意", "Whispered %s and sent a join request - waiting for them to accept")
        or L("已密 %s 求组，等对方拉你", "Whispered %s - waiting for an invite"), who))
    return true
end
CP.Whisper = CP.Request

-- 进队 / 离队：同过队的帐篷主人，离队时密一句谢谢
function CP.OnRoster()
    if CP.joined then
        if not CP.InGroupWith(CP.joined.who) then
            local who = CP.joined.who
            CP.joined = nil
            if on("thank") and not CP.thanked[who] then
                local msg = CP.DB().thankMsg or CP.Pick(CP.THANK)
                if send(msg, who) then CP.thanked[who] = true end
            end
        end
        return
    end
    for who, t in pairs(CP.whispered) do
        if now() - t < 7200 and CP.InGroupWith(who) then
            CP.joined = { who = who, at = now() }
            ns.Print(L("已进队：在帐篷旁坐下（按 X）满 60 秒才拿到奖励经验", "Joined: sit (X) next to the tent for 60 sec to get the rested XP"))
            return
        end
    end
end

-- ---------- 读提示框 ----------
function CP.ReadTooltip(tt)
    tt = tt or GameTooltip
    if tt ~= GameTooltip or not tt.NumLines then return end
    -- 自己插件的提示（经验加成提醒条的「帐篷经验」图标）不是世界里的帐篷，别当成帐篷记探针
    local owner = tt.GetOwner and tt:GetOwner()
    local oname = owner and owner.GetName and owner:GetName()
    if type(oname) == "string" and oname:find("^GearInsight") then return end
    local p = owner and owner.GetParent and owner:GetParent()
    local pname = p and p.GetName and p:GetName()
    if type(pname) == "string" and pname:find("^GearInsight") then return end
    local n = tonumber(tt:NumLines()) or 0
    if n == 0 then return end
    local lines = {}
    for i = 1, math.min(n, 6) do
        local fs = _G["GameTooltipTextLeft" .. i]
        lines[i] = fs and fs.GetText and fs:GetText() or nil
    end
    local tent, who = CP.Parse(lines)
    if not tent then return end
    CP.seenAt = now()
    local raw = {}
    for i = 1, #lines do raw[#raw + 1] = str(lines[i]) or "?" end
    probeAdd("tip " .. table.concat(raw, " | "))
    if who then CP.Offer(who) end
end

table.insert(ns.modules, function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        local t = TooltipDataProcessor.AllTypes or (Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object)
        if t then TooltipDataProcessor.AddTooltipPostCall(t, function(tt) pcall(CP.ReadTooltip, tt) end) end
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function(tt) pcall(CP.ReadTooltip, tt) end)
    end
end)

-- ---------- 别人申请加入我的队伍（我放帐篷时一堆人「申请加入」）----------
-- 11-09 用户「增加一个单人（没组队的情况下）自动接收的选项，默认关闭, 自动拒绝……，默认关闭」→ 实测「自动拒绝能用」
--   → 「错了，只主动拒绝露营申请的人」「不是所有的」：拒绝只针对来蹭露营的申请。怎么认：
--     · 对方用本插件「请求加入」：除了那句密语，还发一个插件暗号（GIFCAMP ask）；
--     · 没装插件的：申请前后 2 分钟内密过我带「帐篷 / 露营 / 营地 / tent / camp」的话；
--     · 什么都没说直接申请的：分不清来意 → 不动，系统弹框留给玩家。
--   单人自动同意不分来意（没组队时谁申请都同意）；同一个人两个都命中时拒绝优先。只处理「申请加入」这一种确认。
--   官方接口：GROUP_INVITE_CONFIRMATION → GetNextPendingInviteConfirmation → GetInviteConfirmationInfo → RespondToInviteConfirmation
--   （11-09 用户实测无限客户端里插件能调）。调失败就留着系统弹框让玩家自己点，并只提示一次
CP.PREFIX = "GIFCAMP"
CP.CAMP_WORDS = { "帐篷", "帳篷", "露营", "露營", "营地", "營地", "[Tt]ent", "[Cc]amp" }
CP.ASK_WIN = 120       -- 秒：申请前后多久内的密语 / 暗号算「来蹭露营」
CP.REQ_NOTE_CD = 600   -- 同一个人的「已自动处理」聊天提示多久一次（被刷屏时别跟着刷）
CP.reqNoted, CP.campAsk, CP.reqWait = {}, {}, {}
local function sameName(a, b)
    a, b = short(a), short(b)
    if not a or not b then return false end
    if a == b then return true end
    return a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end
function CP.NoteCampAsk(sender)
    local s = short(sender)
    if s then CP.campAsk[s] = now() end
end
function CP.IsCampAsk(name)
    local t = now()
    for k, at in pairs(CP.campAsk) do
        if t - at > CP.ASK_WIN then CP.campAsk[k] = nil
        elseif sameName(k, name) then return true end
    end
    return false
end
function CP.OnWhisper(text, sender)
    text = str(text)
    if text and anyMatch(text, CP.CAMP_WORDS) then CP.NoteCampAsk(sender) end
end
local function confirmInfo(guid)
    local f = (C_PartyInfo and C_PartyInfo.GetInviteConfirmationInfo) or GetInviteConfirmationInfo
    if not f then return nil end
    local ok, ctype, name = pcall(f, guid)
    if not ok then return nil end
    return ctype, str(name)
end
-- 这条申请怎么处理：decline / accept / wait（像是来蹭露营但暗号 / 密语还没到，等一下再看）/ nil（不动）
function CP.ReqAction(name, waited)
    local d = CP.DB()
    if d.reqDecline then
        if CP.IsCampAsk(name) then return "decline" end
        if not waited then return "wait" end   -- 申请先到、密语后到：等 3 秒再看一次
    end
    if d.reqAcceptSolo and not (IsInGroup and IsInGroup()) then return "accept" end
    return nil
end
function CP.OnInviteConfirmation(waited)
    local d = CP.DB()
    if not (d.reqDecline or d.reqAcceptSolo) then return end
    local nextF = GetNextPendingInviteConfirmation or (C_PartyInfo and C_PartyInfo.GetNextPendingInviteConfirmation)
    local respond = RespondToInviteConfirmation or (C_PartyInfo and C_PartyInfo.RespondToInviteConfirmation)
    if not (nextF and respond) then return end
    local REQ = _G.LE_INVITE_CONFIRMATION_REQUEST or (Enum and Enum.InviteConfirmationType and Enum.InviteConfirmationType.Request) or 1
    for _ = 1, 10 do   -- 一次可能排着好几个
        local okG, guid = pcall(nextF)
        if not okG or not guid then break end
        local ctype, name = confirmInfo(guid)
        if ctype ~= REQ then break end   -- 不是「申请加入」：留给玩家自己处理
        local act = CP.ReqAction(name, waited or CP.reqWait[guid])
        if act == "wait" then
            if not CP.reqWait[guid] and C_Timer and C_Timer.After then
                CP.reqWait[guid] = true
                C_Timer.After(3, function() pcall(CP.OnInviteConfirmation, true) end)
            end
            break
        end
        if not act then break end   -- 不是来蹭露营的、也不自动同意：系统弹框留着
        CP.reqWait[guid] = nil
        local accept = act == "accept"
        local ok = pcall(respond, guid, accept)
        if not ok then
            if not CP.reqFailNoted then
                CP.reqFailNoted = true
                ns.Print(L("自动处理入队申请失败（这个客户端不让插件代点），请手动点同意 / 拒绝", "Couldn't auto-handle the join request - please click it yourself"))
            end
            break
        end
        if StaticPopup_Hide then pcall(StaticPopup_Hide, "GROUP_INVITE_CONFIRMATION") end
        local who = short(name) or "?"
        if now() - (CP.reqNoted[who] or -1e9) > CP.REQ_NOTE_CD then
            CP.reqNoted[who] = now()
            ns.Print(string.format(accept and L("已自动同意 %s 的入队申请（单人时自动同意，设置里可关）", "Auto-accepted %s's join request")
                or L("已自动拒绝 %s 的蹭露营申请（设置里可关）", "Auto-declined %s's tent request"), who))
        end
        if accept then break end   -- 同意一个就进了队，后面的按「有队伍」处理（留给玩家）
    end
end

local ev = CreateFrame("Frame")
CP._ev = ev
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, CP.PREFIX) end
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "GROUP_INVITE_CONFIRMATION", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player") else pcall(ev.RegisterEvent, ev, "UNIT_AURA") end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
    if not ns.db then return end
    if e == "UNIT_AURA" then if a1 == "player" then pcall(CP.OnAura) end
    elseif e == "GROUP_INVITE_CONFIRMATION" then pcall(CP.OnInviteConfirmation)
    elseif e == "CHAT_MSG_WHISPER" then pcall(CP.OnWhisper, a1, a2)
    elseif e == "CHAT_MSG_ADDON" then if a1 == CP.PREFIX and a2 == "ask" then pcall(CP.NoteCampAsk, a4) end
    else pcall(CP.OnRoster) end
end)

-- ---------- /gi camp ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.camp = function(rest, rawRest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    local rawArg = (rawRest or ""):match("^%S*%s*(.-)$") or arg
    local d = CP.DB()
    local C = (ns.SlashHint or "/gif") .. " camp"
    if sub == "on" or sub == "off" then d.on = sub == "on"
    elseif sub == "thank" and (arg == "on" or arg == "off") then d[sub] = arg == "on"
    elseif sub == "accept" and (arg == "on" or arg == "off") then d.reqAcceptSolo = arg == "on" or nil
    elseif sub == "decline" and (arg == "on" or arg == "off") then d.reqDecline = arg == "on" or nil
    elseif sub == "msg" then d.msg = rawArg ~= "" and rawArg or nil
    elseif sub == "thanks" then d.thankMsg = rawArg ~= "" and rawArg or nil
    elseif sub == "probe" then
        ns.ShowBox(L("帐篷探针", "Tent probe"), L("复制全部发给开发者", "Copy all and send to the developer"), table.concat(d.probe or {}, "\n"))
        return
    end
    local function st(k) return on(k) and L("开", "on") or L("关", "off") end
    local function st2(v) return v and L("开", "on") or L("关", "off") end
    ns.Print(string.format(L("帐篷蹭露营：%s · 离队自动感谢：%s · 入队申请单人自动同意：%s · 自动拒绝蹭露营的：%s", "Tent: %s - thank on leave: %s - auto-accept solo: %s - decline tent requests: %s"),
        st("on"), st("thank"), st2(d.reqAcceptSolo), st2(d.reqDecline))
        .. "\n" .. L(C .. " on|off · " .. C .. " thank on|off · " .. C .. " accept on|off 单人自动同意 · " .. C .. " decline on|off 拒绝蹭露营的 · " .. C .. " msg 求组话术 · " .. C .. " thanks 感谢话术 · " .. C .. " probe 探针",
            C .. " on|off · thank on|off · accept on|off · decline on|off · msg <text> · thanks <text> · probe"))
end
