-- 11-21 用户「LR宝宝对应野兽TOOLTIP显示可以学的技能等级」+「只有LR加载这个功能」（HOLD：游戏内验收完才进发行包）
--   猎人鼠标指向 / 选中野兽时，鼠标提示末尾加「驯服可学：撕咬（等级 6）、突进（等级 2）…」：
--     绿 = 《无限》玩家驯服实测会教（或 ≥2 人看到它放过这一级）· 黄 = 经典旧世数据、无限还没人实测 · 灰 = 你已经学会这一级（或更高）
--     「无限实测不教：X」灰色一行 = 经典数据说会教、≥2 位玩家驯服后都没带（依据 PetTameData.lua 的 nt；与猎人宠物页「在哪抓」同一份数据）
--   数据：BeastTipData.lua（scripts/gi_forever_beast_tip_build.py 从 _Class 的 PetTameData.lua 抽的 npcID 索引，一条字符串约 6 KB）
--     ⛔ 不为一行提示 LoadAddOn _Class（离线 2.6 MB）。野外野兽的 GUID 是 Creature-…-npcID-…（真 npcID；众包 tm / bf 的键就是它，
--        和 PetTameData 的 id 对得上）；《无限》猎人宠物的 GUID 是 Pet-…-165189（通用 ID）→ 只认 Creature，宠物 / 玩家控制的不加行
--   已学会：读主插件 PetSnap.lua 记进存档的「训练野兽」窗口列表（猎人已学会的技能名 + 等级）和当前宠物技能书法术 ID；没打开过训练野兽就不标灰
--   开关：设置 → 功能 → 职业「野兽提示：驯服可学技能」（默认开，ns.db.feat.beasttip）· 猎人宠物页「本页设置」同一个勾；关了当场生效（提示里不再加行）
-- 只有猎人加载（猎人专属子插件 GearInsight_Forever_ClassHunter，主插件 ClassStub.lua 登录时只给猎人 LoadAddOn）；文件头再挡一次。
-- ⛔ 挂提示用 TooltipDataProcessor.AddTooltipPostCall（没有就 HookScript OnTooltipSetUnit），不给暴雪全局赋值；每个 API pcall、保密值不碰。
local _, ns = ...; ns = _G.GearInsightForever or ns
if not ns or select(2, UnitClass("player")) ~= "HUNTER" or not ns.BeastTipData then return end

local B = {}
ns.BeastTip = B
local D = ns.BeastTipData
local GREEN, YELLOW, GREY, GOLD, ORANGE = "|cff66ff66", "|cffffcc66", "|cff888888", "|cffffd100", "|cffff9933"

local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end
local function L(cn, en) return ns.L and ns.L(cn, en) or cn end

function B.On() return not (ns.FeatureOff and ns.FeatureOff("beasttip")) end

-- ---------- 查表：npcID → { t = { {sid, sk, rk, f}, ... }, nt = { 技能序号, ... } }（解析结果缓存，最多 64 只）----------
local cache, cacheN = {}, 0
function B.Lookup(npc)
    npc = tonumber(npc)
    if not npc or npc <= 0 then return nil end
    local c = cache[npc]
    if c ~= nil then return c or nil end
    local s
    local _, e = string.find(D.b, ";" .. npc .. "=", 1, true)
    if e then
        local stop = string.find(D.b, ";", e + 1, true)
        s = string.sub(D.b, e + 1, (stop or 0) - 1)
    end
    local out = false
    if s and s ~= "" then
        out = { t = {}, nt = {} }
        for item in string.gmatch(s, "[^,]+") do
            local nk = string.match(item, "^!(%d+)$")
            if nk then
                out.nt[#out.nt + 1] = tonumber(nk)
            else
                local sid, k, r, f = string.match(item, "^(%d+):(%d+):(%d+):(%d+)$")
                if sid then out.t[#out.t + 1] = { sid = tonumber(sid), sk = tonumber(k), rk = tonumber(r), f = tonumber(f) } end
            end
        end
    end
    if cacheN >= 64 then cache, cacheN = {}, 0 end
    cache[npc], cacheN = out, cacheN + 1
    return out or nil
end

local function skName(k)
    local s = D.sk[k]
    if not s then return "?" end
    if ns.zh then return ns.TD and ns.TD(s[2]) or s[2] end
    return s[1]
end

-- ---------- 已学会（主插件 PetSnap.lua 的存档：训练野兽列表 + 当前宠物技能书）----------
local function snap()
    local g = clean(call(UnitGUID, "player"))
    local t = ns.db and ns.db.petSnap
    return type(g) == "string" and type(t) == "table" and type(t[g]) == "table" and t[g] or nil
end
local kc, kcAt
function B.Known()
    local m = snap()
    if not m then return nil end
    local stamp = tostring(m.craftAt) .. "/" .. tostring(type(m.cur) == "table" and m.cur.at or "")
    if kc and kcAt == stamp then return kc end
    local K = { names = {}, ids = {} }
    for _, c in ipairs(type(m.crafts) == "table" and m.crafts or {}) do
        if type(c) == "table" and type(c.n) == "string" then
            local r = tonumber(c.r) or 1
            if (K.names[c.n] or 0) < r then K.names[c.n] = r end
        end
    end
    for _, id in ipairs(type(m.cur) == "table" and type(m.cur.spells) == "table" and m.cur.spells or {}) do
        if tonumber(id) then K.ids[tonumber(id)] = true end
    end
    kc, kcAt = K, stamp
    return K
end
local function isKnown(K, t)
    if not K then return false end
    if K.ids[t.sid] then return true end
    local s = D.sk[t.sk]
    local names = { clean(call(GetSpellInfo, t.sid)) or false }
    if s then names[#names + 1] = s[1]; names[#names + 1] = s[2]; if ns.TD then names[#names + 1] = ns.TD(s[2]) end end
    for _, n in ipairs(names) do
        if n and (K.names[n] or 0) >= t.rk then return true end
    end
    return false
end
B.IsKnown = isKnown

-- ---------- 要加的行：{ {文字, r, g, b}, ... }；查不到 = nil ----------
-- blv = 野兽等级、plv = 玩家等级（野兽等级高于自己驯服不了 → 提示一句）
function B.Lines(npc, blv, plv)
    local r = B.Lookup(npc)
    if not r then return nil end
    local K = B.Known()
    local parts, used = {}, {}
    for _, t in ipairs(r.t) do
        local col
        if isKnown(K, t) then col, used.grey = GREY, true
        elseif (t.f or 0) >= 1 then col, used.green = GREEN, true
        else col, used.yellow = YELLOW, true end
        parts[#parts + 1] = col .. skName(t.sk) .. L("（等级 " .. t.rk .. "）", " (Rank " .. t.rk .. ")") .. "|r"
    end
    local out = {}
    if #parts > 0 then
        local leg = {}
        if used.green then leg[#leg + 1] = GREEN .. L("绿=无限实测", "green = verified") .. "|r" end
        if used.yellow then leg[#leg + 1] = YELLOW .. L("黄=经典数据待核实", "yellow = Classic data, unverified") .. "|r" end
        if used.grey then leg[#leg + 1] = GREY .. L("灰=已学会", "grey = learned") .. "|r" end
        out[#out + 1] = { GOLD .. L("驯服可学：", "Tame to learn: ") .. "|r" .. table.concat(parts, L("、", ", ")), 1, 1, 1 }
        out[#out + 1] = { GREY .. "(|r" .. table.concat(leg, GREY .. " · |r") .. GREY .. ")|r", 1, 1, 1 }
    end
    if #r.nt > 0 then
        local nt = {}
        for _, k in ipairs(r.nt) do nt[#nt + 1] = skName(k) end
        out[#out + 1] = { L("无限实测不教：", "Not taught in Forever: ") .. table.concat(nt, L("、", ", ")), 0.53, 0.53, 0.53 }
    end
    blv, plv = tonumber(blv), tonumber(plv)
    if #parts > 0 and blv and plv and blv > 0 and plv > 0 and blv > plv then
        out[#out + 1] = { ORANGE .. string.format(L("要 %d 级才能驯服（你现在 %d 级）", "Need level %d to tame (you are %d)"), blv, plv) .. "|r", 1, 1, 1 }
    end
    if #out == 0 then return nil end
    return out
end

-- GUID → 野外怪的 npcID（只认 Creature；宠物 Pet-… 的生物 ID 在《无限》是通用 165189，不认）
function B.NpcOfGuid(guid)
    guid = clean(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    id = tonumber(id)
    return id and id > 0 and id or nil
end

-- ---------- 鼠标提示 ----------
B.added = 0
function B.OnUnit(tt, data)
    if tt ~= GameTooltip or not B.On() then return false end
    local unit
    if tt.GetUnit then
        local ok, _, u = pcall(tt.GetUnit, tt)
        if ok then unit = clean(u) end
    end
    local guid = type(data) == "table" and clean(data.guid) or nil
    if not guid and unit then guid = clean(call(UnitGUID, unit)) end
    local npc = B.NpcOfGuid(guid)
    if not npc then return false end
    if unit and (clean(call(UnitIsPlayer, unit)) or clean(call(UnitPlayerControlled, unit))) then return false end
    local blv = unit and clean(call(UnitLevel, unit)) or nil
    local lines = B.Lines(npc, blv, clean(call(UnitLevel, "player")))
    if not lines then return false end
    for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4], true) end
    if tt.IsShown and tt:IsShown() and tt.Show then pcall(tt.Show, tt) end   -- 重新量高度
    B.added = B.added + 1
    return true
end

function B.Hook()
    if B.hooked then return B.hooked end
    local TDP = TooltipDataProcessor
    local TT = Enum and Enum.TooltipDataType
    if TDP and TDP.AddTooltipPostCall and TT and TT.Unit then
        TDP.AddTooltipPostCall(TT.Unit, function(tt, d) pcall(B.OnUnit, tt, d) end)
        B.hooked = "tdp"
    elseif GameTooltip and GameTooltip.HookScript and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(B.OnUnit, tt) end)
        B.hooked = "script"
    end
    return B.hooked
end
pcall(B.Hook)

-- ---------- 开关（功能中心 + 猎人宠物页「本页设置」）：子插件只给猎人加载 → 这两条也只有猎人看得到 ----------
if ns.Feature then
    ns.Feature({ key = "beasttip", cat = "class", zh = "野兽提示：驯服可学技能", en = "Beast tooltip: tameable abilities", class = "Hunter", def = true,
        files = { "BeastTip.lua" }, page = "pet", cfg = "beasttip.on",
        dzh = "鼠标指向野兽时，提示里显示驯服它能学到的宠物技能和等级", den = "Mouse over a beast to see which pet abilities (and ranks) taming it teaches" })
end
if ns.RegisterSettings then
    ns.RegisterSettings({ key = "beasttip", order = 58.2, page = "pet", avail = function() return ns.BeastTip ~= nil end,
        title = function() return L("野兽提示", "Beast tooltip") end, short = function() return L("野兽提示", "Beast tooltip") end,
        items = {
            { type = "check", id = "beasttip.on", text = function() return L("鼠标指向野兽时显示「驯服可学」技能和等级", "Show \"Tame to learn\" abilities and ranks on beast tooltips") end,
              get = function() return B.On() end, set = function(v) if ns.SetFeature then ns.SetFeature("beasttip", v) end end },
        } })
end
