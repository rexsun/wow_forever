-- 11-10 玩家「下次更新可不可以添加一个进入主城自动关闭友方姓名板 出城再开 太卡了」：
--   进六大主城：友方姓名板开着就临时关掉（记一笔是插件关的）；出城：只把插件关掉的那次开回来。
--   ⛔ 玩家在城里自己又打开了 → 尊重他，出城不再动；姓名板设置战斗中受保护 → 战斗中不动，脱战再补
--   ⛔ 「插件关的」记在存档里：城里下线、下次在城外上线也能开回来
--   《无限》客户端友方姓名板的设置名不固定（10-12 probe：nameplateShowFriends=nil）→ 和 /gi perf plates 同一份候选名，挨个试
-- 11-13 共建看板 GI-244 玩家（战士 1.0.0）「进城关姓名板功能没用，是否还有别的地方需要设置」查实：
--   ① 《无限》客户端友方玩家姓名板默认就是关的（RurutiaSuite 的设置表 default=0；Layer.lua「城里友方姓名板默认不显示」），
--      城里每个人头顶飘的是另一项「显示友方玩家名字」（UnitNameFriendlyPlayerName），以前完全没碰 → 进城什么都没变；
--      友方姓名板开成「只显示名字」的（很多界面包默认这样），关掉姓名板头顶照样换成名字 → 看起来也一样
--      → 进城连「友方玩家名字」一起隐藏，出城一起恢复（同一个开关，不加设置项）
--   ② 第一次进城的提示写的是「设置页『界面』栏」，开关其实在「性能」栏 → 找不到；功能默认开，玩家不用另外设置
--   ③ 组队窗口（QuestMates）在城里打开会把友方姓名板开回来，以前被当成「玩家自己开的」→ 城里不再关、出城还可能被组队窗口关掉
--      → 认出是组队窗口开的（ns.db.qm.platesWeOpened）：城里组队扫描本来就暂停 → 关回去；谁的原值谁还原（见 Restore）
--   ④ 地图：《无限》UiMap 表（data_cache/forever_db2/UiMap_*.csv）主城就是 1453–1458，城里没有子地图；
--      但有的地方 GetBestMapForUnit 会给整块大陆（Layer.lua 11-07 记录）→ 大陆图按坐标再问一次 / 对一下区域名
--   ⑤ 别的插件 / 界面里改了设置：监听 CVAR_UPDATE 下一帧重判，不用等换区域
local _, ns = ...
local L = ns.L

local CP = {}
ns.CityPlates = CP

CP.CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }   -- 暴风城 / 奥格瑞玛 / 铁炉堡 / 雷霆崖 / 达纳苏斯 / 幽暗城
CP.KEYS = { "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerUnits", "nameplateShowFriends" }
CP.NAME_KEY = "UnitNameFriendlyPlayerName"   -- 「显示友方玩家名字」：头顶名字（不是姓名板，但玩家眼里是一回事）

local function cvar(k)
    if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, k); if ok then return v end end
    if GetCVar then local ok, v = pcall(GetCVar, k); if ok then return v end end
    return nil
end
-- 改完读回来核对：受保护 / 被拦下时 SetCVar 不一定报错
local function setCV(k, v)
    CP._setting = true
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, k, v)
    elseif SetCVar then pcall(SetCVar, k, v) end
    CP._setting = nil
    return cvar(k) == v
end
CP._cvar = cvar
function CP.Key()
    for _, k in ipairs(CP.KEYS) do if cvar(k) ~= nil then return k end end
    return nil
end
-- 这个客户端里要管的设置：友方姓名板（第一个存在的名字）+ 友方玩家名字
function CP.Managed()
    local out = {}
    local k = CP.Key()
    if k then out[#out + 1] = k end
    if cvar(CP.NAME_KEY) ~= nil then out[#out + 1] = CP.NAME_KEY end
    return out
end
function CP.DB()
    ns.db.cityPlates = ns.db.cityPlates or {}
    local d = ns.db.cityPlates
    d.off = d.off or {}   -- [设置名] = true：插件关掉的、出城要开回来的
    d.qm = d.qm or {}     -- [设置名] = true：插件关的时候，那份「开着」是组队窗口替他开的（不是玩家的原值）
    if d.turnedOff then   -- 11-10 旧存档：只记了一项
        if d.key then d.off[d.key] = true end
        d.turnedOff, d.key = nil, nil
    end
    return d
end
function CP.Off(k) local d = CP.DB(); return d.off[k] and true or false end
function CP.AnyOff() return next(CP.DB().off) ~= nil end
function CP.Enabled() return CP.DB().on ~= false end
function CP.SetOn(v)
    CP.DB().on = v and true or false
    if not v then CP.Restore() else CP.Update() end
end

-- ---------- 组队窗口（QuestMates，子插件）那边的记账 ----------
local function qmDB() return ns.db and ns.db.qm or nil end
local function qmOpened(k) local q = qmDB(); return (q and q.platesWeOpened == k) and true or false end
-- 组队的「进主城暂停扫描」开着（默认开）→ 城里组队用不上友方姓名板
local function qmCityPause()
    local QM = ns.QM
    if QM and QM.CityPauseOn then local ok, v = pcall(QM.CityPauseOn); if ok then return v and true or false end end
    local q = qmDB()
    return not (q and q.cityPause == false)
end

-- ---------- 在不在主城 ----------
local function secret(v) return ns.Secret and ns.Secret(v) end
local function cityMap(m)
    if type(m) ~= "number" or secret(m) then return false end
    if CP.CITIES[m] then return true end
    -- 城里的子地图：往上找一层父地图（《无限》现在没有，留着防以后加）
    if C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, m)
        local parent = ok and type(info) == "table" and info.parentMapID or nil
        if parent and CP.CITIES[parent] then return true end
    end
    return false
end
local cityNames
local function zoneIsCity()
    if not GetRealZoneText then return false end
    local okz, z = pcall(GetRealZoneText)
    if not okz or type(z) ~= "string" or secret(z) or z == "" then return false end
    if not cityNames and C_Map.GetMapInfo then
        local t, n = {}, 0
        for id in pairs(CP.CITIES) do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then t[info.name] = true; n = n + 1 end
        end
        if n > 0 then cityNames = t end   -- 一个名字都没拿到：下次再问
    end
    return cityNames and cityNames[z] or false
end
function CP.InCity()
    if not (C_Map and C_Map.GetBestMapForUnit) then return false end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or secret(m) then return false end
    if cityMap(m) then return true end
    if type(m) == "number" and C_Map.GetMapInfo then
        local ok2, info = pcall(C_Map.GetMapInfo, m)
        local t = ok2 and type(info) == "table" and tonumber(info.mapType)
        local cont = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
        if t and t > cont then return false end   -- 认出是别的地区：不是城里
        -- 给的是整块大陆：按我在大陆图上的位置问落在哪个地区
        if t and C_Map.GetPlayerMapPosition and C_Map.GetMapInfoAtPosition then
            local okp, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
            local okx, x, y
            if okp and pos then okx, x, y = pcall(pos.GetXY, pos) end
            if okx and type(x) == "number" and type(y) == "number" and not secret(x) and not secret(y) then
                local oki, zi = pcall(C_Map.GetMapInfoAtPosition, m, x, y)
                if oki and type(zi) == "table" and cityMap(tonumber(zi.mapID)) then return true end
            end
        end
    end
    -- 没给地图 / 只给了大陆：对一下区域名（暴风城 / 奥格瑞玛 …）
    return zoneIsCity() and true or false
end

local function combat() return InCombatLockdown and InCombatLockdown() end

-- 出城 / 关掉功能：插件关过的开回来（玩家在城里自己又开了的，off 已被清掉，不动）
--   ⛔ 关的时候那份「开着」是组队窗口替他开的、组队窗口城里已经关了 → 原值本来就是关的，不开
function CP.Restore()
    local d = CP.DB()
    if not next(d.off) then return false end
    if combat() then CP.pending = true; return false end
    for k in pairs(d.off) do
        local back = not (d.qm[k] and not qmOpened(k))
        if back and cvar(k) == "0" then setCV(k, "1") end
    end
    d.off, d.qm = {}, {}
    return true
end

function CP.Update()
    if not ns.db then return end
    local d = CP.DB()
    if combat() then CP.pending = true; return end
    CP.pending = nil
    if not CP.Enabled() then return end
    if not CP.InCity() then CP.Restore(); return end
    local changed = false
    local q = qmDB()
    for _, k in ipairs(CP.Managed()) do
        local v = cvar(k)
        local byQM = qmOpened(k)
        if d.off[k] then
            if v == "1" then
                if byQM and qmCityPause() then
                    -- 组队窗口在城里又把它打开了：城里组队扫描本来就暂停 → 关回去。
                    --   原值是玩家开着的 → 组队那笔「我开的」作废，免得关窗口时把玩家的设置关掉；原值本来就是组队开的 → 留给组队关
                    if setCV(k, "0") and q and not d.qm[k] then q.platesWeOpened = nil end
                elseif byQM then
                    -- 玩家关了组队的「城里暂停」，组队要扫身边的人 → 让给组队；原值是玩家开着的就把组队那笔清掉
                    if q and not d.qm[k] then q.platesWeOpened = nil end
                    d.off[k], d.qm[k] = nil, nil
                else
                    d.off[k], d.qm[k] = nil, nil   -- 城里自己（或在别处）又开了：尊重，出城不再动
                end
            end
        elseif v == "1" and not (byQM and not qmCityPause()) then
            if setCV(k, "0") then
                d.off[k] = true
                if byQM then d.qm[k] = true end
                changed = true
            end
        end
    end
    if changed and d.noteV ~= 2 then
        d.noteV, d.noted = 2, true
        ns.Print(string.format(L("进主城：已临时隐藏友方玩家的姓名板和头顶名字（城里人多会卡），出城自动恢复。不想要：设置页「性能」栏取消勾选，或输入 %s cityplates off",
            "Entered a capital: friendly player nameplates and names hidden to save FPS, restored when you leave. Turn off in Settings > Performance, or %s cityplates off"),
            ns.SlashHint or "/gi"))
    end
end

local ev = CreateFrame("Frame")
CP._ev = ev
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
local function isManaged(name)
    if name == CP.NAME_KEY then return true end
    for _, k in ipairs(CP.KEYS) do if k == name then return true end end
    return false
end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "PLAYER_REGEN_ENABLED" and not CP.pending then return end
    if e == "CVAR_UPDATE" then
        -- 只管自己那几项、不是自己改的；下一帧再判（组队窗口先改设置、后记「我开的」）
        if CP._setting or type(a1) ~= "string" or not isManaged(a1) or CP._queued then return end
        if not (ns.db and (CP.AnyOff() or CP.InCity())) then return end
        CP._queued = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() CP._queued = nil; pcall(CP.Update) end)
        else CP._queued = nil; pcall(CP.Update) end
        return
    end
    if e == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
        C_Timer.After(2, function() pcall(CP.Update) end)   -- 刚进图地图编号可能还没好
        return
    end
    pcall(CP.Update)
end)

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.cityplates = function(rest)
    local a = (rest or ""):match("^(%S*)")
    if a == "on" or a == "off" then CP.SetOn(a == "on") end
    ns.Print(string.format(L("进主城自动隐藏友方姓名板和名字：%s（%s cityplates on|off）", "Hide friendly nameplates and names in capitals: %s (%s cityplates on|off)"),
        CP.Enabled() and L("开", "on") or L("关", "off"), ns.SlashHint or "/gi"))
end
