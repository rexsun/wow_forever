-- HOLD：找最近的职业训练师（10-16 用户「导入训练师的坐标，然后点击找到最近的训练师，并打开小地图」）。
-- 数据：TrainerData.lua（经典旧世基线）+ 本地补记（打开训练窗口时记下训练师名字和你站的位置，新地区靠它）。
-- 距离：两边都换成世界坐标（C_Map.GetWorldPosFromMapPos），同一块大陆才比；换不了就退回「同一张地图优先」。
local _, ns = ...

local T = {}
ns.Trainers = T

local function myClass()
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end

local function myFac()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Horde" and "H" or "A"
end

local function seenDB()
    ns.db.trainerSeen = ns.db.trainerSeen or {}
    return ns.db.trainerSeen
end

local function playerPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ui = C_Map.GetBestMapForUnit("player")
    if not ui then return nil end
    local p = C_Map.GetPlayerMapPosition(ui, "player")
    if not p then return nil end
    local x, y = p:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return ui, x * 100, y * 100
end

-- 地图百分比 → 大陆 + 世界坐标（码）
local wcache = {}
local function world(ui, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local key = ui .. ":" .. x .. ":" .. y
    local c = wcache[key]
    if c == nil then
        local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(x / 100, y / 100))
        c = (ok and cont and v) and { cont, v.x, v.y } or false
        wcache[key] = c
    end
    return c or nil
end

local function zoneName(ui)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ui)
    return info and info.name or tostring(ui)
end

-- 候选：内置（本职业、本阵营或中立）+ 本地补记（本职业）
local function candidates(cls)
    local list, fac = {}, myFac()
    for _, t in ipairs((ns.TrainerData or {})[cls] or {}) do
        if t[6] == fac or t[6] == "N" then
            list[#list + 1] = { ui = t[1], x = t[2], y = t[3], name = ns.L(t[4], t[5]) }
        end
    end
    for name, s in pairs(seenDB()) do
        if s.cls == cls and s.ui then
            list[#list + 1] = { ui = s.ui, x = s.x, y = s.y, name = name, seen = true }
        end
    end
    return list
end

-- 最近的几位：{ {t, 距离码 or nil}, ... }，最近的在前
function T.Nearest(cls, max)
    cls = cls or myClass()
    local list = candidates(cls)
    local pui, px, py = playerPos()
    local pw = pui and world(pui, px, py)
    local scored = {}
    for _, t in ipairs(list) do
        local d
        local tw = pw and world(t.ui, t.x, t.y)
        if pw and tw and tw[1] == pw[1] then
            d = math.sqrt((tw[2] - pw[2]) ^ 2 + (tw[3] - pw[3]) ^ 2)
        elseif pui and t.ui == pui then
            d = math.sqrt((t.x - px) ^ 2 + (t.y - py) ^ 2) * 10   -- 换不了世界坐标：同图粗估
        end
        scored[#scored + 1] = { t = t, d = d }
    end
    -- 都比不了距离（别的大陆 / 新地区）：去过的 > 本阵营主城 > 其他
    local CAP = { [1453] = 1, [1455] = 1, [1457] = 1, [1454] = 1, [1456] = 1, [1458] = 1 }
    local function rank(t) return t.seen and 0 or (CAP[t.ui] and 1 or 2) end
    table.sort(scored, function(a, b)
        if a.d and b.d then return a.d < b.d end
        if a.d or b.d then return a.d ~= nil end
        if rank(a.t) ~= rank(b.t) then return rank(a.t) < rank(b.t) end
        return (a.t.name or "") < (b.t.name or "")
    end)
    local out = {}
    for i = 1, math.min(max or 3, #scored) do out[i] = scored[i] end
    return out, #list
end

-- 11-10 GI-224 进城提醒用：这张图上有没有已知的本职业训练师（内置 + 本地补记）
function T.OnMap(ui, cls)
    for _, t in ipairs(candidates(cls or myClass())) do
        if t.ui == ui then return true end
    end
    return false
end

-- 点一下：最近的那位插旗 + 打开世界地图；聊天框列出最近三位
function T.Go(cls)
    local res, total = T.Nearest(cls, 3)
    local first = res[1]
    if not first then
        ns.Print(ns.L("还没有你这个职业训练师的位置资料；打开一次训练师的窗口，插件会记下来", "No trainer locations yet; open a trainer once and it will be remembered"))
        return
    end
    if not first.d then
        ns.Print(ns.L("这片大陆上没有已知的职业训练师（《无限》新地区的训练师要你打开一次训练窗口才会记下），先列出主城的：",
            "No known trainer on this continent (new Forever zones are learned when you open a trainer); capital cities:"))
    end
    local t = first.t
    ns.ShowOnMap(t.ui, { { t.x, t.y } }, t.name)
    for i, r in ipairs(res) do
        local z = zoneName(r.t.ui)
        ns.Print(string.format("%d. %s  |cffaaaaaa%s %.1f, %.1f|r%s%s", i, r.t.name, z, r.t.x, r.t.y,
            r.d and string.format(ns.L("  约 %d 码", "  ~%d yd"), r.d) or "",
            r.t.seen and ns.L("  |cff33ff99（你去过）|r", "  |cff33ff99(visited)|r") or ""))
    end
    ns.Print(ns.L("已在地图上插旗（小地图边上有箭头指路）", "Waypoint set (follow the arrow on your minimap)"))
end

-- 打开训练窗口：是职业训练师就记下名字和你站的位置（同名覆盖成最近一次）
local f = CreateFrame("Frame")
f:RegisterEvent("TRAINER_SHOW")
f:SetScript("OnEvent", function()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    local name = UnitName and UnitName("npc")
    local ui, x, y = playerPos()
    if not name or not ui then return end
    seenDB()[name] = { cls = myClass(), ui = ui, x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10, t = time and time() or 0 }
end)

-- 11-10 职业百宝箱的弹药商（PageAmmo.lua）用同一套定位
T.PlayerPos, T.World, T.ZoneName = playerPos, world, zoneName

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.trainer = function() T.Go() end
ns.ExtraSlash["训练师"] = ns.ExtraSlash.trainer
