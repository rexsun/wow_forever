-- 性能探针 /gi perf [秒数]（10-18 用户「这两个会不会掉帧，目前有用户反馈会掉帧，怎么排查性能」）
--   采样 N 秒（默认 15）：
--   ① 帧时间：平均帧率、最慢一帧、超过 33ms（掉到 30 帧以下）/ 100ms（明显卡顿）的帧数 —— 游戏整体，不分插件
--   ② 入口计时：组队 / 本公会 / 副本组队各自的事件框体，按「框体:事件名」/「框体:OnUpdate」记 次数 / 总耗时 / 单次最长 / 超 5ms 次数。
--      插件代码只能从这些入口进来（外加按钮点击和定时器），入口合计 ≈ 这几个模块的全部开销
--   ③ 函数计时：QM / GuildHome / GroupLFG 表上每个函数（含嵌套调用，所以各行相加会重复，只用来找热点）
--   ④ 暴雪插件分析器 C_AddOnProfiler（客户端有才用）：GI 各子插件近期平均 / 峰值耗时，和全部插件合计比
--   ⑤ 内存：GI 各子插件采样前后的内存，涨得快 = 一直在造垃圾（垃圾回收也会卡帧）
--   ⑥ 现场：组队 / 本公会抽屉开没开、钉没钉、友方姓名板开没开、身边姓名板个数、公会人数
--   结果打到聊天框，并存 ns.db.perfProbe（最多 10 轮）；/reload 后读存档对比「开着 vs 关掉」。
-- ⛔ 只读不改：不碰任何设置；只包我们自己的框体和表，采样完原样换回（暴雪框体一个都不碰，免得污染）
local _, ns = ...

local Perf = {}
ns.Perf = Perf

local GI_ADDONS = { "GearInsight_Forever", "GearInsight_Forever_Group", "GearInsight_Forever_Guild" }
local TABLES = { { "QM", "QM" }, { "GuildHome", "GH" }, { "GroupLFG", "LFG" } }
-- { ns 下的表, 表里存框体的字段, 显示名 }
local FRAMES = { { "QM", "_ev", "QM.ev" }, { "QM", "_thEv", "QM.thanks" }, { "GuildHome", "_ev", "GH.ev" }, { "GroupLFG", "_ev", "LFG.ev" } }

local running
local clock = debugprofilestop or function() return (GetTime and GetTime() or 0) * 1000 end

local function profMetric(addon, key)
    if not (C_AddOnProfiler and Enum and Enum.AddOnProfilerMetric) then return nil end
    local m = Enum.AddOnProfilerMetric[key]
    if m == nil then return nil end
    local ok, v
    if addon then ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, addon, m)
    else ok, v = pcall(C_AddOnProfiler.GetOverallMetric, m) end
    return ok and tonumber(v) or nil
end

local function loaded(a)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(a) end
    return IsAddOnLoaded and IsAddOnLoaded(a)
end

local function mems()
    local out = {}
    if not GetAddOnMemoryUsage then return out end
    if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
    for _, a in ipairs(GI_ADDONS) do
        if loaded(a) then local ok, v = pcall(GetAddOnMemoryUsage, a); out[a] = ok and tonumber(v) or nil end
    end
    return out
end

-- 现场快照
local function scene()
    local s = {}
    local qm, gh = ns.QM, ns.GuildHome
    s.qm = qm and qm.drawer and qm.drawer:IsShown() and 1 or 0
    s.qmPin = ns.db and ns.db.qm and ns.db.qm.pinned and 1 or 0
    s.gh = gh and gh.drawer and gh.drawer:IsShown() and 1 or 0
    s.main = _G.GearInsightForeverMain and _G.GearInsightForeverMain:IsShown() and 1 or 0
    if qm and qm.FriendCVar then local k, v = qm.FriendCVar(); s.fplates = k and (k .. "=" .. tostring(v)) or "?" end
    s.plates = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, l = pcall(C_NamePlate.GetNamePlates)
        if ok and type(l) == "table" then s.plates = #l end
    end
    if qm and qm.near then local n = 0; for _ in pairs(qm.near) do n = n + 1 end; s.near = n end
    if IsInGuild and IsInGuild() and GetNumGuildMembers then
        local ok, t, o = pcall(GetNumGuildMembers)
        if ok then s.guild = tonumber(t); s.guildOn = tonumber(o) end
    end
    if GetNumGuildTradeSkill then local ok, n = pcall(GetNumGuildTradeSkill); s.gtsRows = ok and tonumber(n) or nil end
    s.zone = GetZoneText and GetZoneText() or nil
    s.fps = GetFramerate and math.floor(GetFramerate() + 0.5) or nil
    return s
end

local function newStat() return { n = 0, ms = 0, max = 0, over5 = 0 } end
-- 不建表：pcall 的返回值直接透传（每次调用都 new 表会自己制造垃圾，干扰测量）
local function done(st, t0, ok, ...)
    local dt = clock() - t0
    st.n = st.n + 1; st.ms = st.ms + dt
    if dt > st.max then st.max = dt end
    if dt > 5 then st.over5 = st.over5 + 1 end
    if not ok then error((...), 0) end
    return ...
end

local function wrapAll(fns, entries)
    local undo = {}
    for _, tb in ipairs(TABLES) do
        local t = ns[tb[1]]
        if type(t) == "table" then
            local names = {}
            for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" and k:sub(1, 1) ~= "_" then names[#names + 1] = k end end
            for _, k in ipairs(names) do
                local f = t[k]
                local st = newStat()
                fns[tb[2] .. "." .. k] = st
                t[k] = function(...) return done(st, clock(), pcall(f, ...)) end
                undo[#undo + 1] = function() t[k] = f end
            end
        end
    end
    for _, fr in ipairs(FRAMES) do
        local t = ns[fr[1]]
        local frame = type(t) == "table" and rawget(t, fr[2]) or nil
        if type(frame) == "table" and frame.GetScript and frame.SetScript then
            local onEv, onUp = frame:GetScript("OnEvent"), frame:GetScript("OnUpdate")
            if onEv then
                frame:SetScript("OnEvent", function(self, e, ...)
                    local key = fr[3] .. ":" .. tostring(e)
                    local st = entries[key]
                    if not st then st = newStat(); entries[key] = st end
                    return done(st, clock(), pcall(onEv, self, e, ...))
                end)
            end
            if onUp then
                local st = newStat()
                entries[fr[3] .. ":OnUpdate"] = st
                frame:SetScript("OnUpdate", function(self, el) return done(st, clock(), pcall(onUp, self, el)) end)
            end
            undo[#undo + 1] = function()
                if onEv then frame:SetScript("OnEvent", onEv) end
                if onUp then frame:SetScript("OnUpdate", onUp) end
            end
        end
    end
    return undo
end

local function fmt(v, d) if v == nil then return "-" end return string.format("%." .. (d or 2) .. "f", v) end

local function top(stats, n)
    local l = {}
    for k, st in pairs(stats) do if st.n > 0 then l[#l + 1] = { k = k, st = st } end end
    table.sort(l, function(a, b) if a.st.ms ~= b.st.ms then return a.st.ms > b.st.ms end return a.k < b.k end)
    local out = {}
    for i = 1, math.min(n, #l) do
        local st = l[i].st
        out[i] = string.format("%s n=%d total=%.1fms max=%.2fms over5=%d", l[i].k, st.n, st.ms, st.max, st.over5)
    end
    return out
end

function Perf.Finish()
    local r = running
    if not r then return end
    running = nil
    r.frame:SetScript("OnUpdate", nil)
    for _, u in ipairs(r.undo) do pcall(u) end
    local secs = (clock() - r.t0) / 1000
    local res = { v = 2, at = date and date("%m-%d %H:%M:%S") or "", secs = math.floor(secs * 10 + 0.5) / 10, before = r.before, after = scene() }
    res.frames = r.frames
    res.avgFps = r.frames > 0 and math.floor(r.frames / secs * 10 + 0.5) / 10 or 0
    res.worstMs = math.floor(r.worst + 0.5)
    res.over33, res.over100 = r.over33, r.over100
    local entryMs = 0
    for _, st in pairs(r.entries) do entryMs = entryMs + st.ms end
    res.entryMs = math.floor(entryMs * 10 + 0.5) / 10
    res.entryPerFrame = r.frames > 0 and math.floor(entryMs / r.frames * 1000 + 0.5) / 1000 or 0
    res.entries = top(r.entries, 12)
    res.hot = top(r.fns, 12)
    local m1 = mems()
    res.addons = {}
    for _, a in ipairs(GI_ADDONS) do
        if loaded(a) then
            local m0 = r.mem0[a]
            res.addons[#res.addons + 1] = string.format("%s recent=%sms peak=%sms over5ms=%s mem=%sKB grow=%sKB", a,
                fmt(profMetric(a, "RecentAverageTime"), 3), fmt(profMetric(a, "PeakTime"), 1), fmt(profMetric(a, "CountTimeOver5Ms"), 0),
                fmt(m1[a], 0), fmt(m0 and m1[a] and (m1[a] - m0), 0))
        end
    end
    res.overall = string.format("ALL recent=%sms peak=%sms", fmt(profMetric(nil, "RecentAverageTime"), 3), fmt(profMetric(nil, "PeakTime"), 1))
    res.profiler = (C_AddOnProfiler and Enum and Enum.AddOnProfilerMetric) and 1 or 0

    ns.db.perfProbe = ns.db.perfProbe or {}
    table.insert(ns.db.perfProbe, res)
    while #ns.db.perfProbe > 10 do table.remove(ns.db.perfProbe, 1) end

    local P = function(s) ns.Print("|cff888888GIPERF2|r " .. s) end
    local b = r.before
    P(string.format("%ss · 平均 %s 帧 · 最慢一帧 %dms · >33ms %d 帧 · >100ms %d 帧", res.secs, res.avgFps, res.worstMs, res.over33, res.over100))
    P(string.format("组队抽屉=%d 钉住=%d 本公会=%d 主面板=%d · 友方姓名板 %s · 姓名板 %d 个 · 身边 %s 人 · 公会 %s 人",
        b.qm, b.qmPin, b.gh, b.main, tostring(b.fplates or "-"), b.plates or 0, tostring(b.near or "-"), tostring(b.guild or "-")))
    P(string.format("组队+公会入口合计 %.1fms（每帧 %.3fms）", res.entryMs, res.entryPerFrame))
    for i = 1, math.min(5, #res.entries) do P(res.entries[i]) end
    for _, s in ipairs(res.addons) do P(s) end
    P(res.overall .. (res.profiler == 1 and "" or "（客户端没有插件分析器）"))
    ns.Print(ns.L("性能采样第 ", "Perf sample #") .. #ns.db.perfProbe .. ns.L(" 轮已记下；换个状态再测一轮，几轮都测完再 /reload",
        " saved; change a setting and run again, /reload after the last one"))
end

function Perf.Start(secs)
    if running then ns.Print(ns.L("性能采样正在进行，等它结束", "A perf sample is already running")); return end
    secs = math.max(5, math.min(60, tonumber(secs) or 15))
    local r = { frames = 0, worst = 0, over33 = 0, over100 = 0, fns = {}, entries = {}, before = scene(), mem0 = mems() }
    r.undo = wrapAll(r.fns, r.entries)
    r.frame = Perf.frame or CreateFrame("Frame")
    Perf.frame = r.frame
    r.t0 = clock()
    local last = r.t0
    local stopAt = r.t0 + secs * 1000
    r.frame:SetScript("OnUpdate", function()
        local t = clock()
        local dt = t - last
        last = t
        r.frames = r.frames + 1
        if r.frames > 1 then   -- 第一帧的间隔含输命令那一下，不算
            if dt > r.worst then r.worst = dt end
            if dt > 33 then r.over33 = r.over33 + 1 end
            if dt > 100 then r.over100 = r.over100 + 1 end
        end
        if t >= stopAt then Perf.Finish() end
    end)
    running = r
    ns.Print(string.format(ns.L("性能采样开始：%d 秒，期间正常走动 / 别开关窗口", "Perf sample started: %ds, move around normally"), secs))
end

-- ---------- /gi perf plates：姓名板设置自动对比（10-18 用户「再打开姓名版的情况下，如何优化帧率」）----------
-- 依次切几种姓名板设置，每种先等 2 秒稳定、再采 10 秒，测完把动过的设置全部还原。
-- ⛔ 这是唯一会改设置的探针，所以：
--   ① 只在脱战时跑；进战斗立刻停，脱战后还原（姓名板设置战斗中受保护）
--   ② 动之前把原值存进 ns.db.perfPlatesRestore，中途 /reload 或掉线，下次登录自动还原
--   ③ 客户端没有的设置（GetCVar 回 nil）直接跳过那一步
--   ④ 帧率上限会把好几种设置都压成同一个数（上次五轮都卡在 99）→ 测试期间临时关掉帧率上限，结束还原
local FRIEND_KEYS = { "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerUnits", "nameplateShowFriends" }
local FRIEND_OTHERS = { "nameplateShowFriendlyNPCs", "nameplateShowFriendlyPets", "nameplateShowFriendlyGuardians",
    "nameplateShowFriendlyTotems", "nameplateShowFriendlyMinions" }
local function cvar(k)
    if not GetCVar then return nil end
    local ok, v = pcall(GetCVar, k)
    return ok and v or nil
end
local function cvarExists(k) return cvar(k) ~= nil end
local function friendKey() for _, k in ipairs(FRIEND_KEYS) do if cvarExists(k) then return k end end end
local function setCV(k, v) if SetCVar then return pcall(SetCVar, k, tostring(v)) end end

local function plateSteps()
    local fk = friendKey()
    local steps = { { "now", "现在的设置", {} } }
    if not fk then return steps, nil end
    steps[#steps + 1] = { "off", "友方姓名板关", { [fk] = "0" } }
    local on = { [fk] = "1" }
    steps[#steps + 1] = { "on", "友方姓名板开（其余照旧）", on }
    local noOthers = { [fk] = "1" }
    local any = false
    for _, k in ipairs(FRIEND_OTHERS) do if cvarExists(k) then noOthers[k] = "0"; any = true end end
    if any then steps[#steps + 1] = { "noNpc", "开 + 不显示友方 NPC / 宠物 / 图腾", noOthers } end
    if cvarExists("nameplateShowOnlyNames") then steps[#steps + 1] = { "names", "开 + 只显示名字（不画血条）", { [fk] = "1", nameplateShowOnlyNames = "1" } } end
    if cvarExists("nameplateMaxDistance") then steps[#steps + 1] = { "dist", "开 + 距离缩到 40 码", { [fk] = "1", nameplateMaxDistance = "40" } } end
    local all = {}
    for k, v in pairs(noOthers) do all[k] = v end
    if cvarExists("nameplateShowOnlyNames") then all.nameplateShowOnlyNames = "1" end
    if cvarExists("nameplateMaxDistance") then all.nameplateMaxDistance = "40" end
    if #steps > 4 then steps[#steps + 1] = { "all", "开 + 以上全部", all } end
    return steps, fk
end

-- 姓名板相关设置全表（找《无限》客户端到底有哪些开关）
-- ⛔ 10-18 实测《无限》客户端 C_Console.GetAllCommands 枚举回来是空的 → 再逐个查一遍已知设置名
local KNOWN_PLATE_CVARS = { "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyPlayers",
    "nameplateShowFriendlyPlayerUnits", "nameplateShowFriendlyNPCs", "nameplateShowFriendlyPets", "nameplateShowFriendlyGuardians",
    "nameplateShowFriendlyTotems", "nameplateShowFriendlyMinions", "nameplateShowOnlyNames", "nameplateMaxDistance",
    "nameplateTargetRadialPosition", "nameplateOtherTopInset", "nameplateMotion", "nameplateGlobalScale", "nameplateMinScale",
    "nameplateMaxScale", "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateOccludedAlphaMult", "nameplateSelectedScale",
    "nameplateLargerScale", "nameplateResourceOnTarget", "nameplateShowSelf", "UnitNameFriendlyPlayerName", "UnitNameNPC",
    "maxFPS", "maxFPSBk", "useMaxFPS", "useMaxFPSBk", "graphicsQuality", "renderScale" }
local function plateCVarDump()
    local out, seen = {}, {}
    if C_Console and C_Console.GetAllCommands then
        local ok, list = pcall(C_Console.GetAllCommands)
        for _, c in ipairs(ok and type(list) == "table" and list or {}) do
            local name = type(c) == "table" and c.command or nil
            if type(name) == "string" and name:lower():find("nameplate", 1, true) then
                local v = cvar(name)
                if v ~= nil then seen[name] = true; out[#out + 1] = name .. "=" .. tostring(v) end
            end
        end
    end
    for _, name in ipairs(KNOWN_PLATE_CVARS) do
        local v = cvar(name)
        if v ~= nil and not seen[name] then seen[name] = true; out[#out + 1] = name .. "=" .. tostring(v) end
    end
    table.sort(out)
    return out
end

-- 装了哪些别的姓名板插件（Plater / Kui / TidyPlates / ThreatPlates …）
local function plateAddons()
    local out = {}
    local n = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
    for i = 1, n do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i)) or (GetAddOnInfo and GetAddOnInfo(i))
        if type(name) == "string" then
            local low = name:lower()
            if (low:find("plate", 1, true) or low:find("kui", 1, true)) and loaded(name) then
                out[#out + 1] = name .. " recent=" .. fmt(profMetric(name, "RecentAverageTime"), 3) .. "ms"
            end
        end
    end
    return out
end

-- 全部已加载插件里最占时间的几个（插件分析器有才有）
local function topAddons(n)
    if not (C_AddOnProfiler and Enum and Enum.AddOnProfilerMetric) then return {} end
    local l = {}
    local cnt = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
    for i = 1, cnt do
        local name = (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i)) or (GetAddOnInfo and GetAddOnInfo(i))
        if type(name) == "string" and loaded(name) then
            local v = profMetric(name, "RecentAverageTime")
            if v and v >= 0.05 then l[#l + 1] = { name = name, ms = v } end
        end
    end
    table.sort(l, function(a, b) if a.ms ~= b.ms then return a.ms > b.ms end return a.name < b.name end)
    local out = {}
    for i = 1, math.min(n, #l) do out[i] = l[i] end
    return out
end

-- 10-18 用户「如果用户怀疑卡是不是有个地方可以关，不要因为这个功能影响插件使用率」：
--   自查跑完给玩家看的大白话结论（{中文, 英文}），设置页「性能」一栏也显示最近一次。
--   依据：姓名板开 / 关两轮交替对照 + 插件分析器；⛔ 只说测到的，测不到的不下结论
function Perf.Verdict(summary, giMs, plateList, top)
    local by = {}
    for _, st in ipairs(summary or {}) do by[st.key] = st end
    local out = {}
    local function add(zh, en) out[#out + 1] = { zh, en } end
    local now = by.now
    if now then
        local smooth = (now.over33 or 0) <= 2
        add(string.format("现在：平均 %s 帧，95%% 的帧在 %s 毫秒内画完%s", now.avgFps, now.p95, smooth and "，整体流畅" or "，有明显卡顿"),
            string.format("Now: %s FPS on average, 95%% of frames under %s ms%s", now.avgFps, now.p95, smooth and " - smooth" or " - noticeable stutter"))
        if giMs then
            local pct = now.avgFps > 0 and giMs / (1000 / now.avgFps) * 100 or 0
            if pct < 10 then
                add(string.format("GearInsight 每帧约 %.2f 毫秒（占一帧 %.1f%%），不是它卡的", giMs, pct),
                    string.format("GearInsight uses about %.2f ms per frame (%.1f%% of a frame) - not the cause", giMs, pct))
            else
                add(string.format("GearInsight 每帧约 %.2f 毫秒（占一帧 %.0f%%），偏高：请把这几行截图发给我们", giMs, pct),
                    string.format("GearInsight uses about %.2f ms per frame (%.0f%%) - higher than expected, please send us a screenshot", giMs, pct))
            end
        end
    end
    local on, off = by.on, by.off
    if on and off then
        local d, dh = on.p95 - off.p95, on.over33 - off.over33
        if d >= 2 or dh >= 10 then
            add(string.format("友方姓名板开着每帧多约 %.1f 毫秒：觉得卡可以在设置里关掉「自动开友方姓名板」（只影响组队的「身边玩家」）", math.max(d, 0)),
                string.format("Friendly nameplates cost about %.1f ms per frame: turn off \"Auto friendly nameplates\" in Settings if it feels laggy (only affects Players around you)", math.max(d, 0)))
        else
            add(string.format("友方姓名板开或关几乎没区别（相差 %.1f 毫秒），不用关", math.abs(d)),
                string.format("Friendly nameplates on or off make almost no difference (%.1f ms) - no need to turn them off", math.abs(d)))
        end
    end
    if plateList and #plateList > 0 then
        add("装了姓名板美化插件：" .. table.concat(plateList, "、") .. "。这类插件不管开不开友方姓名板都会让每帧变慢（我们实测 EllesmereUINameplates 约 3-4 毫秒），卡的话先试着停用它",
            "Nameplate addon(s) installed: " .. table.concat(plateList, ", ") .. ". These slow every frame regardless of friendly nameplates (we measured about 3-4 ms for EllesmereUINameplates); try disabling it first")
    end
    if top and #top > 0 then
        local zh, en = {}, {}
        for _, t in ipairs(top) do zh[#zh + 1] = string.format("%s %.2f 毫秒", t.name, t.ms); en[#en + 1] = string.format("%s %.2f ms", t.name, t.ms) end
        add("每帧最占时间的插件：" .. table.concat(zh, "、"), "Addons using the most time per frame: " .. table.concat(en, ", "))
    end
    return out
end

function Perf.RestorePlates()
    local saved = ns.db and ns.db.perfPlatesRestore
    if not saved then return true end
    if InCombatLockdown and InCombatLockdown() then return false end
    for k, v in pairs(saved) do setCV(k, v) end
    ns.db.perfPlatesRestore = nil
    return true
end

local plateRun
function Perf.Busy() return running ~= nil or plateRun ~= nil end   -- 10-22 PerfGuard：手动采样期间别动组队框体
local function plateFinish(why)
    local r = plateRun
    if not r then return end
    plateRun = nil
    r.frame:SetScript("OnUpdate", nil)
    local restored = Perf.RestorePlates()
    -- 两轮交替测，同一种设置取平均（10-18 实测：铁炉堡人群走动的波动比设置之间的差别还大，单测一次不可信）
    local sum, order = {}, {}
    for _, st in ipairs(r.done) do
        local a = sum[st.key]
        if not a then a = { key = st.key, zh = st.zh, n = 0, fps = 0, p95 = 0, worst = 0, over33 = 0, plates = 0 }; sum[st.key] = a; order[#order + 1] = a end
        a.n = a.n + 1; a.fps = a.fps + st.avgFps; a.p95 = a.p95 + st.p95; a.over33 = a.over33 + st.over33; a.plates = a.plates + st.plates
        if st.worst > a.worst then a.worst = st.worst end
    end
    local summary = {}
    for _, a in ipairs(order) do
        summary[#summary + 1] = { key = a.key, zh = a.zh, passes = a.n, avgFps = math.floor(a.fps / a.n * 10 + 0.5) / 10,
            p95 = math.floor(a.p95 / a.n * 10 + 0.5) / 10, worst = a.worst, over33 = a.over33, plates = math.floor(a.plates / a.n + 0.5) }
    end
    local res = { v = 2, at = date and date("%m-%d %H:%M:%S") or "", why = why, zone = GetZoneText and GetZoneText() or nil,
        friendKey = r.fk, steps = r.done, summary = summary, caps = r.caps, cvars = r.dump, addons = plateAddons() }
    local giMs
    for _, a in ipairs(GI_ADDONS) do
        local v = loaded(a) and profMetric(a, "RecentAverageTime")
        if v then giMs = (giMs or 0) + v end
    end
    local plateNames = {}
    for _, a in ipairs(res.addons) do plateNames[#plateNames + 1] = a:match("^(%S+)") end
    res.giMs, res.top = giMs, topAddons(3)
    res.verdict = Perf.Verdict(summary, giMs, plateNames, res.top)
    ns.db.perfPlates = ns.db.perfPlates or {}
    table.insert(ns.db.perfPlates, res)
    while #ns.db.perfPlates > 5 do table.remove(ns.db.perfPlates, 1) end
    local P = function(s) ns.Print("|cff888888GIPLATE1|r " .. s) end
    for _, st in ipairs(summary) do
        P(string.format("%s：平均 %s 帧 · 95%% 的帧在 %sms 内 · 最卡 %dms · >33ms %d 帧 · 姓名板 %d 个（%d 轮）",
            st.zh, st.avgFps, st.p95, st.worst, st.over33, st.plates, st.passes))
    end
    if #res.addons > 0 then P(ns.L("在用的姓名板插件：", "Nameplate addons: ") .. table.concat(res.addons, "，")) end
    if why ~= "done" then P(ns.L("中途停了：", "Stopped early: ") .. tostring(why)) end
    ns.Print("|cffffd100" .. ns.L("卡顿自查结论：", "Lag check result:") .. "|r")
    for _, v in ipairs(res.verdict) do ns.Print("  " .. ns.L(v[1], v[2])) end
    if ns.RefreshPerfVerdict then pcall(ns.RefreshPerfVerdict) end
    ns.Print(restored and ns.L("姓名板设置已全部还原", "Nameplate settings restored")
        or ns.L("在战斗中，脱战后自动还原姓名板设置", "In combat: settings will be restored when combat ends"))
end

function Perf.Plates()
    if plateRun or running then ns.Print(ns.L("有采样正在进行，等它结束", "A sample is already running")); return end
    if InCombatLockdown and InCombatLockdown() then ns.Print(ns.L("战斗中不能改姓名板设置，脱战后再试", "Not in combat, please")); return end
    local steps, fk = plateSteps()
    if not fk then ns.Print(ns.L("这个客户端找不到友方姓名板的设置名，没法自动对比", "Friendly nameplate setting not found")); return end
    -- 记下所有会动到的设置的原值（含帧率上限）
    local saved = {}
    for _, st in ipairs(steps) do for k in pairs(st[3]) do if saved[k] == nil then saved[k] = cvar(k) end end end
    -- 前台 / 后台帧率上限都临时关（10-18 实测：测到一半切出游戏，后四步全被后台上限压在 30 帧）
    local caps = { maxFPS = cvar("maxFPS"), maxFPSBk = cvar("maxFPSBk"), useMaxFPS = cvar("useMaxFPS"), useMaxFPSBk = cvar("useMaxFPSBk") }
    for _, k in ipairs({ "useMaxFPS", "useMaxFPSBk" }) do
        if cvar(k) == "1" then saved[k] = "1"; setCV(k, "0") end
    end
    ns.db.perfPlatesRestore = saved
    local dump = plateCVarDump()
    -- 两轮交替：A B C … A B C …
    local seq = {}
    for _ = 1, 2 do for _, st in ipairs(steps) do seq[#seq + 1] = st end end
    steps = seq
    local r = { fk = fk, steps = steps, done = {}, i = 0, dump = dump, caps = caps }
    r.frame = Perf.plateFrame or CreateFrame("Frame")
    Perf.plateFrame = r.frame
    plateRun = r
    local SETTLE, SAMPLE = 2000, 8000
    local cur, phaseEnd, last
    local function nextStep()
        r.i = r.i + 1
        local st = steps[r.i]
        if not st then plateFinish("done"); return end
        for k in pairs(saved) do if k ~= "useMaxFPS" and k ~= "useMaxFPSBk" then setCV(k, saved[k]) end end   -- 每步从原样出发，只改这一步要改的
        for k, v in pairs(st[3]) do setCV(k, v) end
        cur = { key = st[1], zh = st[2], frames = 0, worst = 0, over33 = 0, dts = {}, plates = 0, plateN = 0, settling = true }
        phaseEnd = clock() + SETTLE
        ns.Print(string.format(ns.L("姓名板对比 %d/%d：%s", "Nameplate test %d/%d: %s"), r.i, #steps, st[2]))
    end
    r.frame:SetScript("OnUpdate", function()
        if InCombatLockdown and InCombatLockdown() then plateFinish("进战斗了"); return end
        local t = clock()
        if cur.settling then
            if t >= phaseEnd then cur.settling = false; cur.t0 = t; last = t; phaseEnd = t + SAMPLE end
            return
        end
        local dt = t - last
        last = t
        if dt > 0 then
            cur.frames = cur.frames + 1
            cur.dts[#cur.dts + 1] = dt
            if dt > cur.worst then cur.worst = dt end
            if dt > 33 then cur.over33 = cur.over33 + 1 end
        end
        if cur.frames % 30 == 0 and C_NamePlate and C_NamePlate.GetNamePlates then
            local ok, l = pcall(C_NamePlate.GetNamePlates)
            if ok and type(l) == "table" then cur.plates = cur.plates + #l; cur.plateN = cur.plateN + 1 end
        end
        if t >= phaseEnd then
            table.sort(cur.dts)
            local secs = (t - cur.t0) / 1000
            r.done[#r.done + 1] = { key = cur.key, zh = cur.zh, avgFps = math.floor(cur.frames / secs * 10 + 0.5) / 10,
                p95 = math.floor((cur.dts[math.max(1, math.floor(#cur.dts * 0.95))] or 0) * 10 + 0.5) / 10,
                worst = math.floor(cur.worst + 0.5), over33 = cur.over33,
                plates = cur.plateN > 0 and math.floor(cur.plates / cur.plateN + 0.5) or 0,
                all = fmt(profMetric(nil, "RecentAverageTime"), 3) }
            nextStep()
        end
    end)
    ns.Print(string.format(ns.L("开始姓名板对比：%d 种设置各测 2 轮，全程约 %d 秒。站着别动、别进战斗、别切出游戏窗口；测完自动还原",
        "Nameplate comparison: %d settings x2, ~%ds total. Stand still, stay in the game window; settings are restored afterwards"), #steps / 2, #steps * 10))
    nextStep()
end

-- 上次中途 /reload 或进战斗没还原的：登录 / 脱战时补还原
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if not plateRun and ns.db and ns.db.perfPlatesRestore then
            if Perf.RestorePlates() then ns.Print(ns.L("已还原上次姓名板对比改过的设置", "Restored nameplate settings from the last comparison")) end
        end
    end)
    Perf.restoreFrame = f
end

ns.ExtraSlash = ns.ExtraSlash or {}
-- 10-18 用户输 /gi perf plates 却跑成了普通采样：参数没对上就静默按秒数跑，看不出错在哪 →
--   姓名板对比认多种写法（中文用原样参数比，lower() 可能改坏中文字节）；既不是数字也不是这些写法 → 打用法，不跑
-- ---------- /gi itemprobe：物品信息 / 聊天框接口探针（10-18 用户「shift还不行」+ 截图：同一件装备一会儿原生提示一会儿「正在读取」）----------
--   记：① 各接口在不在 ② 「推荐装备」页前 6 件（或 /gi itemprobe 物品ID …）现在能拿到什么 ③ 向服务器要数据、5 秒后再看一遍 + 收到了哪些事件
--   结果打聊天框（GIITEM1 开头）并存 ns.db.itemProbe，/reload 后看存档
local function has(v) return v ~= nil and (type(v) ~= "table" or next(v) ~= nil) and "Y" or "-" end
local function itemState(id)
    local function try(f, ...) if type(f) ~= "function" then return "无" end local r = { pcall(f, ...) } if not r[1] then return "错" end return r end
    local out = {}
    local r = try(C_Item and C_Item.GetItemInfo, id); out[#out + 1] = "C_Item.Info=" .. (type(r) == "table" and tostring(r[2] ~= nil and r[3] or r[2]) or r)
    r = try(GetItemInfo, id); out[#out + 1] = "GetItemInfo=" .. (type(r) == "table" and tostring(r[3] or r[2]) or r)
    r = try(C_Item and C_Item.IsItemDataCachedByID, id); out[#out + 1] = "cached=" .. (type(r) == "table" and tostring(r[2]) or r)
    r = try(C_Item and C_Item.DoesItemExistByID, id); out[#out + 1] = "exists=" .. (type(r) == "table" and tostring(r[2]) or r)
    r = try((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, id); out[#out + 1] = "instant=" .. (type(r) == "table" and tostring(r[2]) or r)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, d = pcall(C_TooltipInfo.GetItemByID, id)
        out[#out + 1] = "tipInfo=" .. (ok and type(d) == "table" and ((d.lines and #d.lines or 0) .. "行," .. (d.hyperlink and "有链接" or "无链接")) or "空")
    end
    if GameTooltip and GameTooltip.SetItemByID then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, id)
        local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
        out[#out + 1] = "SetItemByID=" .. tostring(ok) .. "," .. (GameTooltip.NumLines and GameTooltip:NumLines() or "?") .. "行," .. tostring(first)
        GameTooltip:Hide()
    end
    return table.concat(out, " ")
end
function Perf.ItemProbe(args)
    local ids = {}
    for x in tostring(args or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(x) end
    if #ids == 0 and ns.GearPage and ns.GearPage.gearBtns then
        local seen = {}
        for _, b in pairs(ns.GearPage.gearBtns) do
            local it = rawget(b, "it")
            if type(it) == "table" and it.id and not seen[it.id] and #ids < 6 then seen[it.id] = true; ids[#ids + 1] = it.id end
        end
    end
    if #ids == 0 then ids = { 6948, 2589 } end   -- 炉石、亚麻布：一定存在的物品做对照
    local out = {}
    local function add(x) out[#out + 1] = x end
    add("api C_Item.GetItemInfo=" .. has(C_Item and C_Item.GetItemInfo) .. " GetItemInfo=" .. has(GetItemInfo)
        .. " Request=" .. has(C_Item and C_Item.RequestLoadItemDataByID) .. " C_TooltipInfo=" .. has(C_TooltipInfo and C_TooltipInfo.GetItemByID)
        .. " Handle=" .. has(HandleModifiedItemClick) .. " InsertLink=" .. has(ChatEdit_InsertLink) .. " OpenChat=" .. has(ChatFrame_OpenChat)
        .. " ActiveWin=" .. has(ChatEdit_GetActiveWindow) .. " ChatFrameUtil=" .. has(ChatFrameUtil) .. " EditBox1=" .. has(_G.ChatFrame1EditBox)
        .. " DressUp=" .. has(DressUpItemLink))
    if type(ChatFrameUtil) == "table" then
        local ks = {}
        for k, v in pairs(ChatFrameUtil) do if type(v) == "function" and (k:find("Link") or k:find("Open") or k:find("Active") or k:find("Insert")) then ks[#ks + 1] = k end end
        table.sort(ks); add("ChatFrameUtil: " .. table.concat(ks, ","))
    end
    for _, id in ipairs(ids) do add("now #" .. id .. " " .. itemState(id)) end
    local got = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, e, a1, a2) got[#got + 1] = e .. ":" .. tostring(a1) .. ":" .. tostring(a2) end)
    for _, id in ipairs(ids) do if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end end
    ns.Print(ns.L("物品接口探针：已向服务器要数据，5 秒后出结果", "Item probe: requested data, results in 5 s"))
    C_Timer.After(5, function()
        f:UnregisterAllEvents()
        for _, id in ipairs(ids) do add("5s #" .. id .. " " .. itemState(id)) end
        add("events " .. (#got > 0 and table.concat(got, " ", 1, math.min(#got, 20)) or "无"))
        ns.db.itemProbe = out
        for _, x in ipairs(out) do ns.Print("|cff888888GIITEM1|r " .. x) end
        ns.Print(ns.L("物品接口探针完成：/reload 写进存档后告诉我", "Item probe done: /reload to save"))
    end)
end

local PLATE_ARGS = { plate = true, plates = true, np = true, nameplate = true, nameplates = true, ["姓名板"] = true, ["姓名版"] = true }
-- /gi itemprobe all：「推荐装备」全部候选（9 职业去重约 1500 件）挨个向服务器要数据，记下服务器回「不存在」的
--   10-18 实测：黑石深渊几件经典装备客户端物品表里有，但服务器 ITEM_DATA_LOAD_RESULT 回 false → 推荐了游戏里拿不到的装备。
--   名单存 ns.db.itemExist（/reload 后导出给生成脚本，三端一起排除）；已经缓存的不重复要
function Perf.ItemExistAll()
    if Perf.existRun then ns.Print(ns.L("正在查，等它结束", "Already running")); return end
    if not (C_Item and C_Item.RequestLoadItemDataByID) then ns.Print(ns.L("这个客户端没有请求物品数据的接口", "No item request API")); return end
    local ids, seen = {}, {}
    local function add(id) id = tonumber(id); if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    for _, lst in pairs((ns.Data and ns.Data.gear) or {}) do
        for _, it in ipairs(lst) do add(it.id) end
    end
    -- 10-18 掉落页的全部物品也查（图纸 / 配方 / 任务物品），顺便记下游戏里的官方中文名和提示文字（新物品没有中文名）
    for _, d in ipairs((ns.Data and ns.Data.loot and ns.Data.loot.dungeons) or {}) do
        for _, grp in ipairs({ d.bosses or {}, d.rares or {} }) do
            for _, b in ipairs(grp) do for _, it in ipairs(b.items or {}) do add(it.id) end end
        end
    end
    table.sort(ids)
    local res, i, okN = {}, 0, 0
    local f = Perf.existFrame or CreateFrame("Frame")
    Perf.existFrame = f
    for _, e in ipairs({ "ITEM_DATA_LOAD_RESULT" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, _, id, ok) id = tonumber(id); if id and seen[id] and res[id] == nil then res[id] = ok and true or false end end)
    local acc, doneAt = 0, nil
    Perf.existRun = true
    ns.Print(string.format(ns.L("开始查 %d 件物品（推荐候选 + 掉落页全部）在服务器上存不存在，约 %d 秒，期间别 /reload", "Checking %d items (gear picks + all drops) on the server, ~%ds; don't /reload"), #ids, math.ceil(#ids / 100) + 10))
    f:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if i < #ids then
            if acc < 0.1 then return end
            acc = 0
            for _ = 1, 10 do
                i = i + 1
                local id = ids[i]
                if not id then break end
                local cached = C_Item.IsItemDataCachedByID and select(2, pcall(C_Item.IsItemDataCachedByID, id))
                if cached == true then res[id] = true else pcall(C_Item.RequestLoadItemDataByID, id) end
            end
            if i >= #ids then doneAt = GetTime() + 10 end
            return
        end
        if GetTime() < (doneAt or 0) then return end
        f:SetScript("OnUpdate", nil); f:UnregisterAllEvents(); Perf.existRun = nil
        local bad, none, okIds = {}, {}, {}
        for _, id in ipairs(ids) do
            if res[id] == true then okN = okN + 1; okIds[#okIds + 1] = id   -- 10-18 推荐只用「确认掉过 / 服务器有」→ 存在的也要记
            elseif res[id] == false then bad[#bad + 1] = id
            else none[#none + 1] = id end
        end
        -- 服务器有的：记游戏里的物品名 + 鼠标提示每行文字（去掉颜色码）→ scripts/gi_forever_item_exist_import.py 导出给掉落数据补中文
        local zh = {}
        local function clean(t) return type(t) == "string" and (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) or nil end
        for _, id in ipairs(okIds) do
            local name
            if C_Item.GetItemInfo then
                local okI, nm = pcall(C_Item.GetItemInfo, id)
                if okI then name = nm end
            end
            local lines = {}
            if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                local okT, d = pcall(C_TooltipInfo.GetItemByID, id)
                if okT and type(d) == "table" then
                    for _, ln in ipairs(d.lines or {}) do
                        local l, r = clean(ln.leftText), clean(ln.rightText)
                        if l and l ~= "" then lines[#lines + 1] = (r and r ~= "") and (l .. "	" .. r) or l end
                    end
                end
            end
            if (type(name) == "string" and name ~= "") or #lines > 0 then zh[id] = { n = name, l = lines } end
        end
        ns.db.itemExist = { at = date and date("%m-%d %H:%M:%S") or "", total = #ids, ok = okN, okIds = okIds, bad = bad, none = none, zh = zh }
        ns.Print(string.format("|cff888888GIITEM2|r " .. ns.L("共 %d 件：服务器有 %d 件，回「不存在」%d 件，没回应 %d 件。/reload 写进存档后告诉我",
            "%d items: %d exist, %d missing, %d no reply. /reload to save"), #ids, okN, #bad, #none))
    end)
end
ns.ExtraSlash.itemprobe = function(rest)
    if rest == "all" then Perf.ItemExistAll() else Perf.ItemProbe(rest) end
end
ns.ExtraSlash.perf = function(rest, rawRest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local raw = (rawRest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if PLATE_ARGS[rest] or PLATE_ARGS[raw] then Perf.Plates()
    elseif (rest == "log" or raw == "日志") and ns.PerfGuard then ns.PerfGuard.PrintLog()
    elseif rest == "" or tonumber(rest) then Perf.Start(rest)
    else
        ns.Print(ns.L("用法：/gi perf 采样 15 秒（/gi perf 30 = 30 秒）· /gi perf plates 姓名板设置自动对比 · /gi perf log 自动卡顿记录",
            "Usage: /gi perf (15s sample, /gi perf 30 = 30s) - /gi perf plates (nameplate comparison) - /gi perf log (auto lag log)"))
    end
end
