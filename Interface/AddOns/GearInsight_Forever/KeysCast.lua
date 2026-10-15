-- 键位手法 P5 · 公测众包施法记录（10-10，docs/forever-keybind-rotation-design.md §4-2 / §8）
-- 可选、默认关（键位手法页 · 高级 ▸ 里勾选）：战斗中按「职业 · 天赋系 · 等级段」统计
--   ① 每个技能按了几次（铺条排序 = 无限版的按键频率表）② 「按完 A 接着按 B」的次数（学手法优先级用）③ 战斗总时长
-- ⛔ 只记法术编号和次数，不记角色名 / 服务器 / 目标 / 时间点；随公测数据导出串（GIFS1 的 cf 字段）由玩家自己上传。
-- ⛔ HOLD（_hold.txt），测完才进包。
local _, ns = ...

local C = {}
ns.KeysCast = C
local MAX_BI = 400   -- 每组最多记这么多种「A→B」，超了只累加已有的

local function secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end
function C.On() return ns.db and ns.db.castCollect == true end
function C.Set(on)
    ns.db.castCollect = on and true or nil
    ns.Print(on and ns.L("已开始记录施法频率（匿名，只记技能和次数）；随 /gif data 导出上传", "Recording cast frequency (anonymous); uploads with /gif data")
        or ns.L("已停止记录施法频率", "Stopped recording cast frequency"))
end

local function bucket()
    local tree = ns.Keys and ns.Keys.MainTree() or nil
    local lv = UnitLevel and UnitLevel("player") or 0
    if secret(lv) then lv = 0 end
    return string.format("%s:%d:%d", ns.MyClass() or "?", tree or 0, math.floor((lv or 0) / 10) * 10), tree or 0, math.floor((lv or 0) / 10) * 10
end

local cur, prev, t0
local function rec(spellID)
    if not C.On() or not spellID or secret(spellID) then return end
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    ns.db.casts = ns.db.casts or {}
    local key, tree, band = bucket()
    local b = ns.db.casts[key]
    if not b then b = { cls = ns.MyClass(), tree = tree, band = band, n = 0, sec = 0, f = {}, bi = {}, nbi = 0 }; ns.db.casts[key] = b end
    b.n = b.n + 1
    b.f[spellID] = (b.f[spellID] or 0) + 1
    if prev and prev ~= spellID then
        local k = prev .. ">" .. spellID
        if b.bi[k] then b.bi[k] = b.bi[k] + 1
        elseif b.nbi < MAX_BI then b.bi[k] = 1; b.nbi = b.nbi + 1 end
    end
    prev = spellID
    cur = b
end
C._rec = rec   -- 测试用

-- 导出给 Stats.lua 的 GIFS1：cf = [{ b = 分组键, cls, tree, band, n, sec, f = {{id, 次数}…}, bi = {{a, b, 次数}…} }]
function C.ExportDoc()
    if not C.On() or not ns.db.casts then return nil end
    local out = {}
    for key, b in pairs(ns.db.casts) do
        if b.n >= 20 then   -- 太少的组没意义
            local f, bi = {}, {}
            for id, n in pairs(b.f) do f[#f + 1] = { id, n } end
            for k, n in pairs(b.bi) do
                local a, c = k:match("^(%d+)>(%d+)$")
                if a and n >= 2 then bi[#bi + 1] = { tonumber(a), tonumber(c), n } end
            end
            out[#out + 1] = { b = key, cls = b.cls, tree = b.tree, band = b.band, n = b.n, sec = math.floor(b.sec), f = f, bi = bi }
        end
    end
    return #out > 0 and out or nil
end
ns.CastExportDoc = C.ExportDoc

local ev = CreateFrame("Frame")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, e, _, _, spellID)
    if e == "UNIT_SPELLCAST_SUCCEEDED" then pcall(rec, spellID)
    elseif e == "PLAYER_REGEN_DISABLED" then prev = nil; t0 = GetTime and GetTime() or nil
    elseif e == "PLAYER_REGEN_ENABLED" then
        if t0 and C.On() then
            local key = bucket()
            local b = ns.db.casts and ns.db.casts[key]
            if b then b.sec = b.sec + math.max(0, (GetTime() - t0)) end
        end
        prev, t0 = nil, nil
    end
end)
