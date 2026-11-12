-- 11-10 玩家「下次更新可不可以添加一个进入主城自动关闭友方姓名板 出城再开 太卡了」：
--   进六大主城：友方姓名板开着就临时关掉（记一笔是插件关的）；出城：只把插件关掉的那次开回来。
--   ⛔ 玩家在城里自己又打开了 → 尊重他，出城不再动；姓名板设置战斗中受保护 → 战斗中不动，脱战再补
--   ⛔ 「插件关的」记在存档里：城里下线、下次在城外上线也能开回来
--   《无限》客户端友方姓名板的设置名不固定（10-12 probe：nameplateShowFriends=nil）→ 和 /gi perf plates 同一份候选名，挨个试
local _, ns = ...
local L = ns.L

local CP = {}
ns.CityPlates = CP

CP.CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }   -- 暴风城 / 奥格瑞玛 / 铁炉堡 / 雷霆崖 / 达纳苏斯 / 幽暗城
CP.KEYS = { "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerUnits", "nameplateShowFriends" }

local function cvar(k)
    if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, k); if ok then return v end end
    if GetCVar then local ok, v = pcall(GetCVar, k); if ok then return v end end
    return nil
end
local function setCV(k, v)
    if C_CVar and C_CVar.SetCVar then return (pcall(C_CVar.SetCVar, k, v)) end
    if SetCVar then return (pcall(SetCVar, k, v)) end
    return false
end
function CP.Key()
    for _, k in ipairs(CP.KEYS) do if cvar(k) ~= nil then return k end end
    return nil
end
function CP.DB()
    ns.db.cityPlates = ns.db.cityPlates or {}
    return ns.db.cityPlates
end
function CP.Enabled() return CP.DB().on ~= false end
function CP.SetOn(v)
    CP.DB().on = v and true or false
    if not v then CP.Restore() else CP.Update() end
end

function CP.InCity()
    if not (C_Map and C_Map.GetBestMapForUnit) then return false end
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(m) ~= "number" or (ns.Secret and ns.Secret(m)) then return false end
    if CP.CITIES[m] then return true end
    -- 城里的子地图（比如铁炉堡某个区）：往上找一层父地图
    if C_Map.GetMapInfo then
        local ok2, info = pcall(C_Map.GetMapInfo, m)
        local parent = ok2 and type(info) == "table" and info.parentMapID or nil
        if parent and CP.CITIES[parent] then return true end
    end
    return false
end

local function combat() return InCombatLockdown and InCombatLockdown() end

-- 出城 / 关掉功能：插件关过的开回来（玩家在城里自己又开了的，turnedOff 已被清掉，不动）
function CP.Restore()
    local d = CP.DB()
    if not d.turnedOff then return false end
    if combat() then CP.pending = true; return false end
    local k = d.key or CP.Key()
    if k and cvar(k) == "0" then setCV(k, "1") end
    d.turnedOff, d.key = nil, nil
    return true
end

function CP.Update()
    if not ns.db then return end
    local d = CP.DB()
    if combat() then CP.pending = true; return end
    CP.pending = nil
    if not CP.Enabled() then return end
    local k = CP.Key()
    if not k then return end
    if CP.InCity() then
        if d.turnedOff then
            if cvar(k) == "1" then d.turnedOff, d.key = nil, nil end   -- 城里自己又开了：尊重，出城不再动
            return
        end
        if cvar(k) == "1" and setCV(k, "0") then
            d.turnedOff, d.key = true, k
            if not d.noted then
                d.noted = true
                ns.Print(L("进主城：已临时关掉友方姓名板（城里人多会卡），出城自动打开。设置页「界面」栏可关这个功能",
                    "Entered a capital: friendly nameplates hidden to save FPS, restored when you leave (Settings > Interface to turn off)"))
            end
        end
    else
        CP.Restore()
    end
end

local ev = CreateFrame("Frame")
CP._ev = ev
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_REGEN_ENABLED" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_REGEN_ENABLED" and not CP.pending then return end
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
    ns.Print(string.format(L("进主城自动关友方姓名板：%s（%s cityplates on|off）", "Hide friendly nameplates in capitals: %s (%s cityplates on|off)"),
        CP.Enabled() and L("开", "on") or L("关", "off"), ns.SlashHint or "/gi"))
end
