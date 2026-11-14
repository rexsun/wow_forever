-- 我的升级报告（10-19 一期，协议 docs/forever-report-protocol.md · GIFP1）
--   插件把「这个角色现在的样子」打成一串 → 网址 # 后面 → 网站 /wow/forever/me 解码出定制路线。
--   编码：ns.JSON(doc) → ns.B64url → 校验和（djb 变体，对 b64url 那一段）→ GIFP1.<b64url>.<sum6>，整串 ≤ 4000 字符（超了按 §3 裁）。
--   网站解码：services/dashboard/forever_report_codec.py（两端测试都用它对拍：scripts/gi_forever_report_test.py）。
-- ⛔ 别人的角色名任何时候都不带（公会、小队、附近的人只带人数和分布）。
--    10-19 用户「默认直接带，不要选项」：自己的「角色名-服务器」（who）和公会名原文（gu.name）一律带，两个勾去掉；
--    doc.opt 固定 { gn = 1, who = 1 }（协议兼容，网站照读）；旧存档里的 ns.db.ui.report 不再读。rh / gh 哈希照旧带。
-- ⛔ 每一样读取都包 pcall：哪个接口在《无限》客户端没有 / 报错，就当这一项没有，Build 本身永远不炸。
-- ⛔ HOLD（_hold.txt）：没在游戏里实测前不进发行包。
local _, ns = ...; ns = _G.GearInsightForever or ns

local R = {}
ns.Report = R

local PREFIX = "GIFP1"
local MAX_LEN = 4000
local MAX_LV, MAX_D, MAX_W = 60, 20, 20
local QM_EXPIRE = 150   -- 秒：和 QuestMates.lua 的 EXPIRE 一致（这么久没心跳就不算附近的人）
R.MAX_LEN = MAX_LEN

-- ---------- 小工具 ----------
local function try(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(f, ...)
    if ok then return a, b, c, d end
    return nil
end
local function secret(v) return ns.Secret and ns.Secret(v) or false end
local function num(v) v = tonumber(v); if v == nil or secret(v) then return nil end return v end
local function int(v) v = num(v); return v and math.floor(v) or 0 end
-- 空表编码成 []（ns.JSON 认 __array；⛔非空表别带 __array，否则会被当对象）
local function arr(t) if t and #t > 0 then return t end return { __array = true } end

-- 校验和：h = (h*33 + 字节) % 2^24，%06x（和 forever_report_codec.checksum / 正式服 GI1 同款）
function R.Checksum(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
    return string.format("%06x", h)
end

-- 只把 A-Z 变小写（⛔ string.lower 在某些环境会改坏中文 UTF-8 字节，见 Core.lua 斜杠命令那段注释）
local function asciiLower(s)
    return (tostring(s or ""):gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function realmName()
    local r = try(GetRealmName)
    if type(r) ~= "string" or secret(r) or r == "" then r = try(GetNormalizedRealmName) end
    if type(r) ~= "string" or secret(r) or r == "" then return nil end
    return r
end

local function guildName()
    if not (IsInGuild and try(IsInGuild)) then return nil end
    local g = try(GetGuildInfo, "player")
    if type(g) == "string" and not secret(g) and g ~= "" then return g end
end

-- ---------- 各项读取（每个都 pcall 包住，出错 = 这一项没有）----------
local function readChar()
    local _, cls = try(UnitClass, "player")
    local fac = try(UnitFactionGroup, "player")
    local lv = int(try(UnitLevel, "player"))
    local xp, xpMax = num(try(UnitXP, "player")), num(try(UnitXPMax, "player"))
    local money = num(try(GetMoney)) or 0
    local map = num(C_Map and try(C_Map.GetBestMapForUnit, "player")) or 0
    local hc = ns.IsHardcore and try(ns.IsHardcore)
    local race = ns.RouteRace and try(ns.RouteRace)
    return {
        cls = (type(cls) == "string" and not secret(cls)) and cls or "",
        race = race or "",
        fac = (fac == "Alliance" and "A") or (fac == "Horde" and "H") or "",
        lv = lv,
        xp = (xp and xpMax and xpMax > 0) and math.floor(xp / xpMax * 100 + 0.5) / 100 or 0,
        hc = (hc == 1) and 1 or 0,
        gb = (money >= 500000 and 2) or (money >= 100000 and 1) or 0,   -- 铜：10 金 = 100000
        map = math.floor(map),
    }
end

local function readTalents()
    local pts, code = { 0, 0, 0 }, nil
    local c, total = nil, nil
    if ns.CurrentTalentCode then c, total = try(ns.CurrentTalentCode) end
    if type(c) == "string" then
        local a, b, d = c:match("^GIF2%.[%a]+%.([%d]*)%-([%d]*)%-([%d]*)$")
        if a then
            for i, seg in ipairs({ a, b, d }) do
                local s = 0
                for ch in seg:gmatch("%d") do s = s + tonumber(ch) end
                pts[i] = s
            end
            if (tonumber(total) or (pts[1] + pts[2] + pts[3])) > 0 then code = c end
        end
    end
    if not code and GetTalentTabInfo then   -- 拿不到码：至少读每系点数
        for i = 1, 3 do
            local _, _, spent = try(GetTalentTabInfo, i)
            pts[i] = int(spent)
        end
    end
    return { pts = pts, code = code }
end

local function readSpec()
    if ns.PlanLoad then try(ns.PlanLoad) end   -- 11-12 第 3 期：天赋定位表在按需加载的 GearInsight_Forever_Plan（出报告是玩家点的，这时加载）
    if not (ns.SpecGear and ns.SpecGear.Current and ns.MyClass) then return nil end
    local cls = try(ns.MyClass)
    return cls and try(ns.SpecGear.Current, cls) or nil
end

-- 本角色升级记录：同一级多条留最后一条，按等级升序，最多 60 条
local function readLvls(cid)
    local by = {}
    for _, r in ipairs((ns.db and ns.db.lvls) or {}) do
        if r.cid == cid and tonumber(r.lvl) then by[tonumber(r.lvl)] = r end
    end
    local ks = {}
    for l in pairs(by) do ks[#ks + 1] = l end
    table.sort(ks)
    local out = {}
    for i = math.max(1, #ks - MAX_LV + 1), #ks do
        local r = by[ks[i]]
        out[#out + 1] = { ks[i], int(r.played), int(r.map) }
    end
    return out
end

-- 本角色死亡：按时间，最近 20 条
local function readDeaths(cid)
    local list = {}
    for _, r in ipairs((ns.db and ns.db.deaths) or {}) do
        if r.cid == cid then list[#list + 1] = r end
    end
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local out = {}
    for i = math.max(1, #list - MAX_D + 1), #list do
        local r = list[i]
        local kn = (type(r.kn) == "string" and r.kk == "npc") and r.kn or ""   -- 只带怪名（pvp 本来就没记名字）
        out[#out + 1] = { int(r.lvl), int(r.map), int(r.k), kn, int(r.t) }
    end
    return out
end

local function readProfs()
    local out = {}
    if not (ns.Prof and ns.Prof.Skills) then return out end
    local s = try(ns.Prof.Skills)
    if type(s) ~= "table" then return out end
    local seen = {}
    for _, k in ipairs(ns.Prof.ORDER or {}) do
        local v = s[k]
        if type(v) == "table" and num(v.r) then out[#out + 1] = { k, int(v.r), int(v.m) }; seen[k] = true end
    end
    for k, v in pairs(s) do   -- ORDER 以外的（以后新增的专业）也带上
        if not seen[k] and type(k) == "string" and type(v) == "table" and num(v.r) then out[#out + 1] = { k, int(v.r), int(v.m) } end
    end
    return out
end

local function readGear()
    local out = {}
    if not GetInventoryItemID then return out end
    for slot = 1, 18 do
        if slot ~= 4 then   -- 4 = 衬衣
            local id = num(try(GetInventoryItemID, "player", slot))
            if id and id > 0 then out[#out + 1] = { slot, math.floor(id) } end
        end
    end
    return out
end

local function readWish()
    local ids = {}
    for id, v in pairs((ns.db and ns.db.wish) or {}) do
        id = tonumber(id)
        if id and v then ids[#ids + 1] = math.floor(id) end
    end
    table.sort(ids)
    local out = {}
    for i = 1, math.min(MAX_W, #ids) do out[i] = ids[i] end
    return out
end

local function readQuests()
    local n = 0
    local f = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries
    if f then
        local a, b = try(f)
        n = int(num(b) or num(a))
    end
    local sc = {}
    local SC = ns.SideChains
    if SC and SC.Progress then
        for _, c in ipairs(ns.SideChainsData or {}) do
            local _, done, total = try(SC.Progress, c)
            if c.key and tonumber(total) and total > 0 and (tonumber(done) or 0) >= total then sc[#sc + 1] = c.key end
        end
    end
    return { n = n, sc = arr(sc) }
end

-- 公会专业人数：公会子插件加载了用它（游戏自带 + 插件同步合并）；没加载直接读游戏自带公会专业的标题行人数
local function guildProfs()
    local pf = {}
    local GH = ns.GuildHome
    if GH and GH.Collect then
        local list = try(GH.Collect)
        for _, e in ipairs(type(list) == "table" and list or {}) do
            if e.key then pf[e.key] = math.max(tonumber(e.total) or 0, #(e.members or {})) end
        end
        if next(pf) then return pf end
    end
    if not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then return pf end
    local n = int(try(GetNumGuildTradeSkill))
    for i = 1, n do
        local ok, skillID, _, _, header, _, _, numPlayers = pcall(GetGuildTradeSkillInfo, i)
        if ok and header then
            local key = ns.Prof and ns.Prof.KeyOf and (ns.Prof.KeyOf(skillID) or ns.Prof.KeyOf(header))
            if key and num(numPlayers) then pf[key] = int(numPlayers) end
        end
    end
    return pf
end

local function readGuild(myLv, realmLower)
    local gname = guildName()
    if not gname then return nil end
    local total, online = try(GetNumGuildMembers)
    total = int(total)
    local b, cl, on = { 0, 0, 0, 0, 0, 0, 0 }, {}, 0
    local me = try(UnitName, "player")
    if secret(me) then me = nil end
    local higher, skippedMe, others = 0, false, 0
    if GetGuildRosterInfo then
        for i = 1, total do
            local ok, name, _, _, level, _, _, _, _, isOnline, _, cls = pcall(GetGuildRosterInfo, i)
            level = ok and num(level) or nil
            if level then
                local bi = (level >= 60 and 7) or (math.floor(level / 10) + 1)
                if bi >= 1 and bi <= 7 then b[bi] = b[bi] + 1 end
                if type(cls) == "string" and not secret(cls) and cls ~= "" then cl[cls] = (cl[cls] or 0) + 1 end
                if isOnline then on = on + 1 end
                -- 第几个到当前等级：比我等级高的人一定先到 → 名次 = 比我高的人数 + 1（同 LevelShare.GuildRank；同级的先后拿不到）
                local short = (type(name) == "string" and not secret(name)) and (name:match("^([^%-]+)") or name) or nil
                if not skippedMe and me and short == me then skippedMe = true
                else
                    others = others + 1
                    if level > myLv then higher = higher + 1 end
                end
            end
        end
    end
    if on == 0 then on = int(online) end
    local gu = {
        n = total, on = on, b = b, cl = cl, pf = guildProfs(),
        rk = (others > 0 and myLv > 0) and (higher + 1) or nil,
        lead = (IsGuildLeader and try(IsGuildLeader)) and 1 or 0,
    }
    gu.name = gname   -- 10-19「默认直接带」：公会名原文一律带
    return gu, gname
end

local function readParty()
    if not UnitExists then return nil end
    local out = {}
    for i = 1, 4 do
        local u = "party" .. i
        if try(UnitExists, u) then
            local _, cls = try(UnitClass, u)
            local role = UnitGroupRolesAssigned and try(UnitGroupRolesAssigned, u)
            if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = "NONE" end
            out[#out + 1] = { (type(cls) == "string" and not secret(cls)) and cls or "", int(try(UnitLevel, u)), role }
        end
    end
    return #out > 0 and out or nil
end

local function readQM()
    local QM = ns.QM
    if not (QM and type(QM.peers) == "table") then return nil end
    local now = (GetTime and try(GetTime)) or 0
    local n = 0
    for _, e in pairs(QM.peers) do
        if type(e) == "table" and now - (tonumber(e.seen) or 0) <= QM_EXPIRE then n = n + 1 end
    end
    return n
end

local function region()
    local r = try(GetCurrentRegionName)
    if type(r) == "string" and r ~= "" then return asciiLower(r) end
    local map = { "us", "kr", "eu", "tw", "cn" }
    return map[int(try(GetCurrentRegion))] or ""
end

-- ---------- 组 doc ----------
-- 10-19「默认直接带，不要选项」：opt 固定全开（只为协议兼容留着这个字段）
function R.Build()
    local opt = { gn = 1, who = 1 }
    local function part(f, ...)
        local ok, v, w = pcall(f, ...)
        if ok then return v, w end
        return nil
    end
    local c = ns.CurrentChar and try(ns.CurrentChar)
    local cid = c and c.cid or ""
    local ver, bnum = try(GetBuildInfo)
    local ch = part(readChar) or { cls = "", race = "", fac = "", lv = 0, xp = 0, hc = 0, gb = 0, map = 0 }
    local realm = realmName()
    local realmLower = realm and asciiLower(realm) or nil
    local doc = {
        v = 1,
        uid = (ns.db and ns.db.uid) or "",
        cid = cid,
        b = (ver or "") .. "." .. (bnum or ""),
        av = (ns.AddonVersion and try(ns.AddonVersion)) or "",
        loc = try(GetLocale) or "",
        rg = part(region) or "",
        c = ch,
        t = part(readTalents) or { pts = { 0, 0, 0 } },
        sp = part(readSpec),
        lv = arr(part(readLvls, cid)),
        pl = 0,
        d = arr(part(readDeaths, cid)),
        pr = arr(part(readProfs)),
        g = arr(part(readGear)),
        w = arr(part(readWish)),
        q = part(readQuests) or { n = 0, sc = arr() },
        pa = part(readParty),
        qm = part(readQM),
        opt = opt,
    }
    if ns.PlayedNow then
        local total = try(ns.PlayedNow)
        doc.pl = int(total)
    end
    doc.rh = realmLower and R.Checksum(realmLower) or nil
    local gu, gname = part(readGuild, ch.lv or 0, realmLower)
    doc.gu = gu
    if gname and realmLower then doc.gh = R.Checksum(realmLower .. "|" .. gname) end
    local me = try(UnitName, "player")   -- 只有自己的名字；别人的一律不带
    if type(me) == "string" and not secret(me) and me ~= "" then doc.who = me .. "-" .. (realm or "") end
    return doc
end

-- ---------- 编码 + 超长裁剪（§3 顺序）----------
local function encodeRaw(doc)
    local body = ns.B64url(ns.JSON(doc))
    return PREFIX .. "." .. body .. "." .. R.Checksum(body)
end

-- 依次执行，直到整串 ≤ 4000；最后一步（lv 从最早的删）是兜底，协议 §3 末尾有写
local TRIM = {
    { "d10", function(doc) local d = doc.d; if #d > 10 then local t = {}; for i = #d - 9, #d do t[#t + 1] = d[i] end; doc.d = t end end },
    { "w5", function(doc) local w = doc.w; if #w > 5 then doc.w = { w[1], w[2], w[3], w[4], w[5] } end end },
    { "lvmap", function(doc) local t = {}; for i, r in ipairs(doc.lv) do t[i] = { r[1], r[2] } end; doc.lv = arr(t) end },
    { "d0", function(doc) doc.d = arr() end },
    { "gu", function(doc) if doc.gu then doc.gu.cl, doc.gu.pf = {}, {} end end },
}
R.TRIM = TRIM

-- 返回：报告串, 用掉的裁剪步骤（{ "d10", … }）
function R.Encode(doc)
    local code = encodeRaw(doc)
    local used = {}
    for _, st in ipairs(TRIM) do
        if #code <= MAX_LEN then break end
        st[2](doc); used[#used + 1] = st[1]
        code = encodeRaw(doc)
    end
    while #code > MAX_LEN and #doc.lv > 0 do   -- 兜底：升级记录从最早的删
        table.remove(doc.lv, 1)
        if used[#used] ~= "lvcut" then used[#used + 1] = "lvcut" end
        if #doc.lv == 0 then doc.lv = arr() end
        code = encodeRaw(doc)
    end
    return code, used
end

function R.Base()
    return ns.zh and "https://gearinsight.cn/wow/forever/me#" or "https://gearinsight.app/wow/en/forever/me#"
end

-- 完整网址, 报告串长度
function R.URL()
    local code = R.Encode(R.Build())
    return R.Base() .. code, #code
end

function R.Show()
    local ok, url = pcall(R.URL)
    if not ok or not url then
        ns.Print(ns.L("生成报告链接出错：", "Couldn't build the report link: ") .. tostring(url)); return
    end
    ns.ShowBox(ns.L("我的升级报告", "My leveling report"),
        ns.L("已选中，Ctrl+C 复制整条，到浏览器打开；发到手机微信也能看",
            "Already selected - Ctrl+C to copy the whole line, then open it in your browser; send it to your phone to read it there too"), url)
end

-- ---------- 页面小标签用 ----------
function R.Summary()
    local doc = R.Build()
    local cls = ns.MyClass and try(ns.MyClass)
    local clsTxt = cls and ns.L((ns.Data and ns.Data.classCn and ns.Data.classCn[cls]) or cls, cls) or ""
    local specTxt
    if doc.sp and ns.SpecGear and ns.SpecGear.SpecInfo and cls then
        local s = try(ns.SpecGear.SpecInfo, cls, doc.sp)
        if s then specTxt = ns.L(s.s or s.zh, s.sEn or s.en) end
    end
    local gs = "none"
    if doc.gu then gs = (doc.gu.lead == 1) and "leader" or "member" end
    return {
        cls = clsTxt, spec = specTxt, level = doc.c.lv or 0,
        nLv = #doc.lv, nProf = #doc.pr, nWish = #doc.w,
        guild = gs, party = doc.pa and #doc.pa or 0,
    }
end

-- ---------- 斜杠：/gi report · /gi 报告 ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.report = function() R.Show() end
ns.ExtraSlash["报告"] = ns.ExtraSlash.report
