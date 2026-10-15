-- 公测数据记录：报到（职业 / 种族 / 阵营 / 是否硬核）· 死亡（死在哪、被谁、几级）· 升级用时（每升一级记 /played）
-- 默认开（/gif data off 关）；⛔不自动上传 —— 玩家自己 /gif data 复制导出串，粘到网站 / 小程序「无限 · 公测数据」。
-- 导出串 "GIFS1:" + base64url(JSON)：
-- {v,build,region,uid,chars:[{cid,cls,race,fac,hc,lvl,t0}],deaths:[{cid,t,lvl,map,zn,inst,kk,k,kn,ks,hc,gs}],lvls:[{cid,t,lvl,played,map,zn}]}
-- ⛔不记角色名 / 服务器名：角色只给随机 cid（本地用 GUID 的哈希对应，GUID 本身不出存档以外）；
--   被玩家杀死只记 kk="pvp"，不记对方名字。
local _, ns = ...

local MAX_DEATHS, MAX_LVLS = 300, 600
local HIT_WINDOW = 10          -- 死前 10 秒内最后一下伤害才算凶手
local lastHit = nil            -- {kk, k, kn, ks, t}
local pendingLvl = nil         -- 刚升级、等 TIME_PLAYED_MSG 回来

local function db() return ns.db end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function randHex(n)
    local t = {}
    for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
    return table.concat(t)
end

-- 硬核服识别：经典硬核有 C_GameRules.IsHardcoreActive；无限客户端有没有待 Beta 核对。1 / 0 / -1(未知)
function ns.IsHardcore()
    if C_GameRules and C_GameRules.IsHardcoreActive then
        local ok, v = pcall(C_GameRules.IsHardcoreActive)
        if ok then return v and 1 or 0 end
    end
    return -1
end

local function mapNow()
    local m = 0
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, v = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and v then m = v end
    end
    return m, (GetZoneText and GetZoneText()) or ""
end

-- 当前角色的 cid；第一次见到的角色登记报到信息
function ns.CurrentChar()
    local d = db()
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return nil end
    local key = hash(guid)
    d.chars = d.chars or {}
    local c = d.chars[key]
    if not c then
        c = { cid = randHex(8), t0 = time() }
        d.chars[key] = c
    end
    local _, cls = UnitClass("player")
    local race
    if UnitRace then race = select(2, UnitRace("player")) end   -- ⛔别写 x and f()：只留第一个返回值
    c.cls, c.race = cls or c.cls or "", race or c.race or ""
    c.fac = (UnitFactionGroup and UnitFactionGroup("player")) or c.fac or ""
    local hc = ns.IsHardcore()
    if hc ~= -1 or c.hc == nil then c.hc = hc end
    c.lvl = UnitLevel("player") or c.lvl or 0
    return c
end

local function push(list, rec, max, sentKey)
    local d = db()
    if #d[list] >= max then
        table.remove(d[list], 1)
        d[sentKey] = math.max(0, (d[sentKey] or 0) - 1)
    end
    table.insert(d[list], rec)
end

-- ---------- 死亡 ----------
local DMG = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    ENVIRONMENTAL_DAMAGE = true, DAMAGE_SHIELD = true }

function ns.OnCombatLog(_, sub, _, srcGUID, srcName, _, _, destGUID, _, _, _, a12, a13)
    if not DMG[sub] or destGUID ~= ns._playerGUID then return end
    local h = { t = time() }
    if sub == "ENVIRONMENTAL_DAMAGE" then
        h.kk, h.k, h.kn = "env", 0, tostring(a12 or "")      -- FALLING / DROWNING / LAVA / FIRE / SLIME / FATIGUE
    else
        local kind, _, _, _, _, id = strsplit("-", srcGUID or "")
        if kind == "Player" then
            h.kk, h.k, h.kn = "pvp", 0, ""                   -- ⛔ 不记对方名字
        elseif kind == "Creature" or kind == "Vehicle" then
            h.kk, h.k, h.kn = "npc", tonumber(id) or 0, srcName or ""
        elseif kind == "Pet" then
            h.kk, h.k, h.kn = "pvp", 0, ""                   -- 玩家宠物 = 玩家击杀
        else
            h.kk, h.k, h.kn = "?", 0, ""
        end
        if sub ~= "SWING_DAMAGE" then h.ks = tonumber(a12) or 0 end
    end
    lastHit = h
end

function ns.RecordDeath(now)
    local d = db()
    if not d.collect then return false end
    local c = ns.CurrentChar()
    if not c then return false end
    now = now or time()
    local m, zn = mapNow()
    local inInst = IsInInstance and IsInInstance()
    local instID = 0
    if inInst and GetInstanceInfo then instID = select(8, GetInstanceInfo()) or 0 end
    local h = (lastHit and now - lastHit.t <= HIT_WINDOW) and lastHit or { kk = "?", k = 0, kn = "" }
    push("deaths", { cid = c.cid, t = now, lvl = UnitLevel("player") or 0, map = m, zn = zn, inst = instID,
        kk = h.kk, k = h.k, kn = h.kn, ks = h.ks or 0, hc = c.hc,
        gs = (GetNumGroupMembers and GetNumGroupMembers()) or 0 }, MAX_DEATHS, "deathsSent")
    c.nd = (c.nd or 0) + 1                                   -- 战绩卡用：这个角色一共死了几次（列表会被清，计数不清）
    if h.kk == "npc" and h.k and h.k > 0 then
        c.kill = c.kill or {}
        c.kill[h.k] = (c.kill[h.k] or 0) + 1
    end
    lastHit = nil
    return true
end

-- ---------- 升级用时 ----------
-- 升级时向服务器要一次 /played；回来的总时长记到这一级。相邻两级相减 = 这一级用了多久（网站算）。
-- 系统会把 /played 打到聊天框 —— 我们自己要的那次不打，玩家手动 /played 照常显示。
function ns.RecordLevel(lvl, played, now)
    local d = db()
    if not d.collect then return false end
    local c = ns.CurrentChar()
    if not c then return false end
    local m, zn = mapNow()
    push("lvls", { cid = c.cid, t = now or time(), lvl = lvl, played = played or 0, map = m, zn = zn }, MAX_LVLS, "lvlsSent")
    c.lvl = lvl
    return true
end

-- 要一次 /played（会在聊天框显示一行游戏时长，正常提示）。
-- ⛔ 10-07 国服 Beta 两次被判「已被禁用，该功能只对暴雪的 UI 开放」：
--    ① 改写暴雪 ChatFrame_DisplayTimePlayed ② 给暴雪聊天框 UnregisterEvent / RegisterEvent（诊断抓到 Frame:RegisterEvent()）
--    → 不再静默，暴雪的框体和函数一律不碰；也不在登录时自动要，只在升级 / 战绩卡时要
function ns.RequestPlayedSilently()
    if RequestTimePlayed then RequestTimePlayed() end
end

-- ---------- 导出 ----------
local function unsent(list, sentKey, all)
    local d, out = db(), {}
    for i = all and 1 or ((d[sentKey] or 0) + 1), #d[list] do out[#out + 1] = d[list][i] end
    return out
end

-- all=true：连已导出过的一起（登出写存档给更新器用；服务端 UNIQUE(uid,cid,t) / (uid,cid,lvl) 去重）
function ns.StatsExportString(all)
    local d = db()
    pcall(ns.CurrentChar)
    local deaths, lvls = unsent("deaths", "deathsSent", all), unsent("lvls", "lvlsSent", all)
    local chars = {}
    for _, c in pairs(d.chars or {}) do
        chars[#chars + 1] = { cid = c.cid, cls = c.cls or "", race = c.race or "", fac = c.fac or "", hc = c.hc or -1,
            lvl = c.lvl or 0, t0 = c.t0 or 0 }
    end
    table.sort(chars, function(a, b) return a.t0 < b.t0 end)
    if #chars == 0 then return nil, 0, 0 end
    local build = GetBuildInfo and select(1, GetBuildInfo()) or ""
    local bnum = GetBuildInfo and select(2, GetBuildInfo()) or ""
    local region = GetCurrentRegionName and GetCurrentRegionName() or ""
    local doc = { v = 1, build = build .. "." .. bnum, region = string.lower(region or ""), uid = d.uid,
        chars = chars, deaths = deaths, lvls = lvls }
    -- 10-10 键位手法 P5：可选的施法频率（KeysCast.lua，默认关；没装 / 没开就没有这个字段）
    if ns.CastExportDoc then local ok, cf = pcall(ns.CastExportDoc); if ok and cf then doc.cf = cf end end
    if #deaths == 0 then doc.deaths = { __array = true } end
    if #lvls == 0 then doc.lvls = { __array = true } end
    return "GIFS1:" .. ns.B64url(ns.JSON(doc)), #deaths, #lvls
end

function ns.ExportStats()
    local s, nd, nl = ns.StatsExportString()
    if not s then ns.Print(ns.L("还没有角色数据，进游戏后再试", "No character data yet")); return end
    ns.ShowBox(ns.L("导出公测数据（死亡 ", "Export beta data (deaths ") .. nd .. ns.L(" · 升级 ", ", levels ") .. nl .. ns.L("）", ")"),
        ns.L(ns.UPLOAD_HINT_ZH .. "\n上传后 " .. (ns.SlashHint or "/gif") .. " data clear 清掉已导出的",
            ns.UPLOAD_HINT_EN .. "\nThen " .. (ns.SlashHint or "/gif") .. " data clear"), ns.UploadURL(s))
    local d = db()
    d.deathsPending, d.lvlsPending = #d.deaths, #d.lvls
end

function ns.ClearExportedStats()
    local d = db()
    local n = 0
    for _, p in ipairs({ { "deaths", "deathsSent", "deathsPending" }, { "lvls", "lvlsSent", "lvlsPending" } }) do
        local list, sentKey, pendKey = p[1], p[2], p[3]
        local upto = d[pendKey] or 0
        if upto > (d[sentKey] or 0) then
            for _ = 1, upto do table.remove(d[list], 1) end
            n = n + upto
        end
        d[sentKey], d[pendKey] = 0, nil
    end
    if n == 0 then ns.Print(ns.L("没有已导出待清的记录", "Nothing exported to clear")); return end
    ns.Print(ns.L("已清掉导出过的记录 ", "Cleared exported records: ") .. n)
end

function ns.SetCollect(on)
    db().collect = on and true or false
    ns.Print(on and ns.L("公测数据记录：已开（死亡 / 升级 / 报到，只存在本地，导出才上传）", "Beta data logging: ON (local only until you export)")
        or ns.L("公测数据记录：已关", "Beta data logging: OFF"))
end

-- 当前总时长 / 这一级已用（秒），按收到 /played 之后的游戏内时间往上加；没拿到返回 nil
function ns.PlayedNow()
    local p = ns._played
    if not p then return nil end
    local dt = (GetTime and GetTime() or p.at) - p.at
    if dt < 0 then dt = 0 end
    local lvl = UnitLevel("player") or p.lvl
    local thisLvl = (lvl == p.lvl) and (p.level + dt) or nil       -- 升级了但新的 /played 还没回来 → 这一级未知
    return p.total + dt, thisLvl
end

-- 登出时把全部记录的导出串写进存档（GearInsightForeverDB.autoExport），给 Windows 更新器读了自动上传（玩家在更新器里勾选同意才传）。
-- ⛔ 记录关了（/gif data off）就不写，并把旧的清掉；插件自己从不联网。
function ns.WriteAutoExport()
    local d = db()
    if not d.collect then d.autoExport = nil; return false end
    local stats = ns.StatsExportString and ns.StatsExportString(true)
    local loot = ns.LootExportString and ns.LootExportString(true)
    if not stats and not loot then d.autoExport = nil; return false end
    -- 协议（docs/forever-addon-link-protocol.md ②）：只许 stats / loot / at 三个键、不许嵌套；内容没变就不动 at（更新器按 at 去重）
    local old = d.autoExport
    if type(old) == "table" and old.stats == stats and old.loot == loot and old.at then return false end
    d.autoExport = { stats = stats, loot = loot, at = time() }
    return true
end

table.insert(ns.modules, function()
    local d = db()
    if d.collect == nil then d.collect = true end
    d.deaths, d.lvls, d.chars = d.deaths or {}, d.lvls or {}, d.chars or {}
    d.deathsSent, d.lvlsSent = d.deathsSent or 0, d.lvlsSent or 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_DEAD")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("TIME_PLAYED_MSG")
    -- ⛔⛔ 10-07 国服 Beta 一直弹「GearInsight_Forever 已被禁用，该功能只对暴雪的 UI 开放」的真凶：
    --    12.0 引擎起 COMBAT_LOG_EVENT_UNFILTERED 对插件关闭，注册即 ADDON_ACTION_FORBIDDEN（正式服 GI CombatStats.lua 有同样注释），
    --    《无限》客户端（Interface 16001）同一引擎。→ 不注册；死亡记录照记，凶手记为未知（kk="?"）
    f:RegisterEvent("PLAYER_LOGOUT")
    ns._statsEvent = function(_, e, a1, a2)
        if e == "COMBAT_LOG_EVENT_UNFILTERED" then
            if CombatLogGetCurrentEventInfo then ns.OnCombatLog(CombatLogGetCurrentEventInfo()) end
        elseif e == "PLAYER_ENTERING_WORLD" then
            ns._playerGUID = UnitGUID and UnitGUID("player")
            pcall(ns.CurrentChar)
            -- 登录后静默要一次 /played：升级小窗「你这一级用了多久」、战绩卡的总时长都靠它（只要一次）
            -- ⛔ 登录不再自动要 /played（10-07：不碰暴雪聊天框后没法静默，登录刷一行游戏时长太吵）
        elseif e == "PLAYER_LOGOUT" then
            pcall(ns.WriteAutoExport)
        elseif e == "PLAYER_DEAD" then
            pcall(ns.RecordDeath)
        elseif e == "PLAYER_LEVEL_UP" then
            if db().collect and RequestTimePlayed then
                pendingLvl = a1
                ns.RequestPlayedSilently()
            end
        elseif e == "TIME_PLAYED_MSG" then
            -- a1 = 总时长，a2 = 这一级已用时长（秒）；GetTime 记下收到的时刻，之后往上加
            ns._played = { total = tonumber(a1) or 0, level = tonumber(a2) or 0, at = GetTime and GetTime() or 0,
                lvl = UnitLevel("player") or 0 }
            if pendingLvl then
                local lvl = pendingLvl
                pendingLvl = nil
                pcall(ns.RecordLevel, lvl, a1)
                if lvl % 10 == 0 then
                    ns.Print(ns.L("已记下你的升级用时。" .. (ns.SlashHint or "/gif") .. " data 导出，到网站「无限 · 公测数据」看自己排第几",
                        "Level time saved. " .. (ns.SlashHint or "/gif") .. " data to export and compare on GearInsight"))
                end
            end
        end
    end
    f:SetScript("OnEvent", ns._statsEvent)
end)
