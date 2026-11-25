-- 11-05 猎人宠物「在哪抓 + 哪只野兽会教哪一级技能」（方案 c：开源数据打底 + 众包校正）
--   PagePet.lua 的第 4 个视图「在哪抓」：选家族 → 每只野兽一行（名字 / 等级 / 地区 / 坐标 / 稀有精英标记 / 会教的技能 / 「地图」按钮）
--   「宠物技能」视图每个技能下面加「会教的野兽」（每一级列几只，点 = 打开地图标点）
-- 数据：PetTameData.lua（scripts/gi_forever_pet_tame.py，经典旧世 1.12 开源数据，见那个文件头的出处 / 许可）
--   11-20 用户「矫正这部分数据」：众包驯服结果核实过 → t 第 3 位 1 = 《无限》玩家驯服实测会教；nt = 实测不教；tn = 几人驯服过
--     《无限》学法没变（经典旧世那套）：驯服会这个技能的野兽 → 宠物带着它 → 战斗中用一次学会 → 「训练野兽」花训练点教给主宠物
--   众包校正：ns.PetTameObs（可选，以后由更新器从服务端 bf / tm 汇总写进来；没有就只用打底数据）
--     格式 { beasts = { [npcID] = { fam=家族ID, cn=, en=, lo=, hi=, ui=, x=, y=, r=, t={ {法术ID, 等级}, ... } } } }
-- ⛔ 这个文件在 HOLD 里：游戏内验收前不进发行包；PagePet.lua 没有 ns.PetTame 时照旧三个视图。
local _, ns = ...; ns = _G.GearInsightForever or ns

local M = {}
ns.PetTame = M

local GREY, GOLD, ORANGE, BLUE = "|cff888888", "|cffffd100", "|cffff9933", "|cff66aaff"
M.RANK_SHOW = 3   -- 技能视图每一级列几只

local function D() return ns.PetTameData end

local function skillByEn()
    local t = {}
    for _, s in ipairs((ns.PetData and ns.PetData.skills) or {}) do t[s.en] = s end
    return t
end

-- 法术 ID → 技能 en 名 + 等级（从 teach 表反查；众包数据只带法术 ID）
local spellIdx
local function spellInfo(sid)
    if not spellIdx then
        spellIdx = {}
        for en, ranks in pairs((D() and D().teach) or {}) do
            for rk, list in pairs(ranks) do spellIdx[list[1]] = { en, rk } end
        end
    end
    local v = spellIdx[sid]
    if v then return v[1], v[2] end
end
M.SpellInfo = spellInfo

local function copy(b)
    local o = {}
    for k, v in pairs(b) do o[k] = v end
    return o
end

-- 一个家族的野兽：打底数据 + 众包覆盖（同 ID 用众包的字段盖掉、标 obs；众包新发现的追加）
function M.Beasts(fid)
    local out, idx = {}, {}
    for _, b in ipairs((D() and D().fams and D().fams[fid]) or {}) do
        local o = copy(b)
        out[#out + 1] = o
        idx[o.id] = o
    end
    local O = ns.PetTameObs and ns.PetTameObs.beasts
    if type(O) == "table" then
        for id, ob in pairs(O) do
            if type(ob) == "table" then
                local o = idx[id]
                if o then
                    for k, v in pairs(ob) do if k ~= "fam" then o[k] = v end end
                    o.obs, o.nocn = true, ob.cn == nil and o.nocn or nil
                elseif ob.fam == fid then
                    o = copy(ob); o.id = id; o.obs = true; o.fam = nil
                    o.cn = o.cn or o.en or ("#" .. id)
                    out[#out + 1] = o
                end
            end
        end
    end
    table.sort(out, function(a, b) if (a.lo or 0) ~= (b.lo or 0) then return (a.lo or 0) < (b.lo or 0) end return a.id < b.id end)
    return out
end

local beastIdx
local function beastById(id)
    if not beastIdx then
        beastIdx = {}
        for _, f in ipairs((ns.PetData and ns.PetData.families) or {}) do
            for _, b in ipairs(M.Beasts(f.id)) do beastIdx[b.id] = b end
        end
    end
    return beastIdx[id]
end
function M.Reset() beastIdx, spellIdx = nil, nil end

-- 某技能某一级：会教的野兽（打底 teach 表里的 + 众包里带这个法术的）
function M.Teachers(en, rank)
    local out, seen = {}, {}
    local row = D() and D().teach and D().teach[en] and D().teach[en][rank]
    if row then
        for i = 2, #row do
            local b = beastById(row[i])
            if b and not seen[b.id] then out[#out + 1] = b; seen[b.id] = true end
        end
    end
    local O = ns.PetTameObs and ns.PetTameObs.beasts
    if type(O) == "table" and row then
        for id in pairs(O) do
            local b = beastById(id)
            if b and not seen[id] then
                for _, t in ipairs(b.t or {}) do
                    if t[1] == row[1] then out[#out + 1] = b; seen[id] = true; break end
                end
            end
        end
    end
    return out
end

function M.Ranks(en)
    local out = {}
    for rk in pairs((D() and D().teach and D().teach[en]) or {}) do out[#out + 1] = rk end
    table.sort(out)
    return out
end

local function zoneName(ui)
    local z = (D() and D().zones and D().zones[ui]) or (ns.PetTameObs and ns.PetTameObs.zones and ns.PetTameObs.zones[ui])   -- 众包新地区
    if z then return ns.L(z[1], z[2]) end
    return ui and ("#" .. ui) or "?"
end
M.ZoneName = zoneName

local function beastName(b)
    if ns.zh then return ns.TD(b.cn or b.en) end   -- 11-15 GI-266：野兽名（数据简体）繁体端转
    return b.en or b.cn
end

local function tag(b)
    local t = ({ [1] = ns.L("精英", "Elite"), [2] = ns.L("稀有精英", "Rare elite"), [3] = ns.L("首领", "Boss"), [4] = ns.L("稀有", "Rare") })[b.r or 0]
    local s = t and (" " .. ORANGE .. t .. "|r") or ""
    if b.obs then s = s .. " " .. BLUE .. ns.L("众包", "Crowd") .. "|r" end
    if b.nocn and ns.zh then s = s .. " " .. GREY .. ns.L("暂无中文名", "") .. "|r" end
    return s
end

local function lvText(b)
    if not b.lo then return "?" end
    if b.hi and b.hi ~= b.lo then return b.lo .. "-" .. b.hi end
    return tostring(b.lo)
end

-- verified = true 只要实测过的 / false 只要没实测的 / nil 全要
local function teachText(b, verified)
    local sb, out = skillByEn(), {}
    for _, t in ipairs(b.t or {}) do
        local en, rk = spellInfo(t[1])
        rk = t[2] or rk
        local s = en and sb[en]
        if s and (verified == nil or verified == ((t[3] or 0) >= 1)) then out[#out + 1] = ns.L(s.cn, s.en) .. " " .. (rk or "?") end
    end
    return table.concat(out, ns.L("、", ", "))
end
M.TeachText = teachText

-- 这只野兽教这个技能这一级是不是《无限》实测过的
local function verifiedFor(b, en, rk)
    for _, t in ipairs(b.t or {}) do
        local e, r = spellInfo(t[1])
        if (t[3] or 0) >= 1 and (e == en) and (t[2] or r) == rk then return true end
    end
    return false
end
M.Verified = verifiedFor

local function notTaughtText(b)
    local sb, out = skillByEn(), {}
    for _, en in ipairs(b.nt or {}) do
        local s = sb[en]
        out[#out + 1] = s and ns.L(s.cn, s.en) or en
    end
    return table.concat(out, ns.L("、", ", "))
end

function M.ShowBeast(b)
    if not (b and b.ui and b.x and ns.ShowOnMap) then return false end
    return ns.ShowOnMap(b.ui, { { b.x, b.y or 0 } }, beastName(b) .. " (" .. lvText(b) .. ")")
end

local function tip(self, b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(beastName(b) .. tag(b), 1, 0.82, 0)
    if ns.zh and b.en and b.en ~= b.cn then GameTooltip:AddLine(b.en, 0.6, 0.6, 0.6) end
    GameTooltip:AddDoubleLine(ns.L("等级", "Level"), lvText(b), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(zoneName(b.ui), string.format("%.1f, %.1f", b.x or 0, b.y or 0), 1, 1, 1, 1, 1, 1)
    -- 11-20 用户「矫正这部分数据」：实测过的 / 经典数据未实测的 / 实测不教的 分三行
    local tv, tu, nt = teachText(b, true), teachText(b, false), notTaughtText(b)
    if tv ~= "" then
        GameTooltip:AddLine(ns.L("会教：", "Teaches: ") .. tv, 0.4, 1, 0.4, true)
        if b.tn then GameTooltip:AddLine(string.format(ns.L("（《无限》玩家驯服实测：%d 人驯服后宠物带着这个技能）", "(Verified in Forever: %d players got it after taming)"), tonumber(b.tn) or 2), 0.4, 0.67, 1, true) end
        -- 11-20 众包野兽施法（HunterObs.lua bc）：≥2 人看到它放过这一级
        if b.bn then GameTooltip:AddLine(string.format(ns.L("（《无限》玩家实测：%d 人看到它放过这个技能）", "(Verified in Forever: %d players saw it cast this)"), tonumber(b.bn) or 2), 0.4, 0.67, 1, true) end
    end
    if tu ~= "" then
        GameTooltip:AddLine(ns.L("可能会教：", "May teach: ") .. tu, 1, 0.82, 0.3, true)
        GameTooltip:AddLine(ns.L("（经典旧世数据，《无限》还没人实测；驯服后插件会自动记下宠物技能帮忙核实）", "(Classic Era data, not yet verified in Forever; taming one records it automatically)"), 1, 0.6, 0.2, true)
        if b.w then GameTooltip:AddLine(string.format(ns.L("众包中：已有 %d 位玩家观测", "Crowdsourcing: %d players observed so far"), tonumber(b.w) or 1), 1, 0.82, 0.3, true) end
    end
    if nt ~= "" then
        GameTooltip:AddLine(string.format(ns.L("《无限》不教：%s（经典数据有，%d 位玩家驯服后都没带）", "Not in Forever: %s (Classic data had it; %d players tamed it without)"), nt, tonumber(b.tn) or 2), 1, 0.4, 0.4, true)
    end
    GameTooltip:AddLine(ns.L("学法：驯服它 → 带着它战斗用一次这个技能 → 学会后找回主宠物，用「训练野兽」花训练点教给它",
        "How: tame it, use the ability in combat once, then teach it to your main pet with Beast Training"), 0.7, 0.7, 0.7, true)
    if b.obs then
        GameTooltip:AddLine(string.format(ns.L("等级 / 位置来自《无限》玩家实测：%d 位玩家看到过", "Level / position from Forever players: seen by %d players"), tonumber(b.n) or 2), 0.4, 0.67, 1, true)
    end
    GameTooltip:AddLine(b.obs and ns.L("点击：打开地图标点", "Click: show on map")
        or ns.L("点击：打开地图标点（经典旧世坐标，众包校正中）", "Click: show on map (classic coords, being crowd-corrected)"), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- 当前宠物家族 ID（PagePet 传进来的是客户端语言的家族名）
local function famIdOf(name)
    if not name then return nil end
    for _, f in ipairs((ns.PetData and ns.PetData.families) or {}) do
        if name == f.cn or name == f.en then return f.id end
    end
end
M.FamIdOf = famIdOf

-- ---------- 「在哪抓」视图 ----------
-- ctx = { p, c, box(x, y, w, h, hi), text(parent, tpl, x, y, w, s), mine = 当前宠物家族名, refresh }
function M.View(ctx)
    M.Reset()   -- 众包数据（ns.PetTameObs）可能后来才写进来
    local c, box, text = ctx.c, ctx.box, ctx.text
    local fams = (ns.PetData and ns.PetData.families) or {}
    local mineId = famIdOf(ctx.mine)
    ns.db.ui = ns.db.ui or {}
    local sel = ns.db.ui.petTameFam or mineId or (fams[1] and fams[1].id)
    -- 11-06 用户截图：说明一行放不下折到第二行，「★ = 你现在的宠物家族」压在家族按钮底下 → 说明框按两行留高，按钮往下排；
    --   ★ 说明只在有宠物家族时出（非猎人 / 没带宠物看不到 ★）
    local head = box(0, 0, 618, 32)
    if head.SetBackdropColor then head:SetBackdropColor(0, 0, 0, 0); head:SetBackdropBorderColor(0, 0, 0, 0) end
    local hs = text(head, "GameFontDisableSmall", 2, -2, 614, ORANGE .. ns.L("经典旧世数据打底 + 《无限》玩家众包校正", "Classic Era data + Forever crowd corrections") .. "|r"
        .. ns.L(" · 绿色「会教」= 驯服实测过 · 鼠标指向 / 驯服野兽会自动记录帮忙校正",
            " · green = verified by taming · mousing over / taming beasts helps correct them")
        -- 11-06 用户「有没有众包数据」：众包已采信多少写在说明里（PetTameObsData.lua，scripts/gi_forever_pet_obs_build.py 汇总）
        .. ((ns.PetTameObs and ns.PetTameObs.players) and ("|cff66aaff" .. string.format(ns.L(" · 众包：%d 位玩家 %d 条目击（%s）", " · crowd: %d players, %d sightings (%s)"),
            ns.PetTameObs.players, ns.PetTameObs.sightings or 0, ns.PetTameObs.builtAt or "") .. "|r") or "")
        .. (mineId and ns.L(" · ★ = 你现在的宠物家族", " · ★ = your current pet family") or ""))
    if hs and hs.SetWordWrap then hs:SetWordWrap(true) end
    -- 家族按钮：6 个一行
    local BW, BH, PER = 100, 20, 6
    local y = -36
    for i, f in ipairs(fams) do
        local col, row = (i - 1) % PER, math.floor((i - 1) / PER)
        local n = #M.Beasts(f.id)
        local label = (f.id == mineId and "★" or "") .. ns.L(f.cn, f.en) .. " " .. GREY .. n .. "|r"
        local b = ns.SegButton(c, label, BW - 4, BH, function()
            ns.db.ui.petTameFam = f.id
            if ctx.refresh then ctx.refresh() end
        end)
        b:SetPoint("TOPLEFT", col * BW, y - row * (BH + 4))
        ns.SegSelect(b, f.id == sel)
        ctx.p.items[#ctx.p.items + 1] = b
        if f.id == sel then ctx.selBtn = b end
    end
    y = y - math.ceil(#fams / PER) * (BH + 4) - 4
    local list = M.Beasts(sel)
    ctx.rows = {}
    if #list == 0 then
        local e = box(0, y, 610, 44, sel == mineId)
        text(e, "GameFontHighlightSmall", 10, -8, 590, ns.L("经典旧世数据里没有这个家族（《无限》新增）。鼠标指向 / 选中这种野兽，插件会自动记下位置和等级，众包够了就会显示在这里。",
            "No Classic Era data for this family (new in Forever). Mouse over or target one and the addon records it; crowd data will show here.")):SetWordWrap(true)
        y = y - 48
    end
    local famIcon
    for _, f in ipairs(fams) do if f.id == sel then famIcon = f.icon end end
    for _, b in ipairs(list) do
        local row = box(0, y, 610, 40, false)
        -- 11-06 用户「这里能加怪物图标吗」：左边画这只野兽的头像（模型 ID → SetPortraitTextureFromCreatureDisplayID）；
        --   没模型 ID（众包新发现的）/ 客户端没这个函数 → 用家族图标
        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(32, 32); ic:SetPoint("TOPLEFT", 4, -4)
        local drew = false
        if b.d and b.d > 0 and SetPortraitTextureFromCreatureDisplayID then
            drew = pcall(SetPortraitTextureFromCreatureDisplayID, ic, b.d)
        end
        if not drew then
            ic:SetTexture(famIcon or 132203)
            if ic.SetTexCoord then ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        end
        row.icon = ic
        local nm = text(row, "GameFontNormal", 42, -4, 386, beastName(b) .. ((ns.zh and b.en and b.en ~= b.cn) and (" " .. GREY .. b.en .. "|r") or "") .. tag(b))
        nm:SetWordWrap(false)
        local lv = text(row, "GameFontHighlightSmall", 430, -6, 110, ns.L(lvText(b) .. " 级", "Lv " .. lvText(b)))
        lv:SetJustifyH("RIGHT")
        local tv, tu = teachText(b, true), teachText(b, false)
        local line2 = GOLD .. zoneName(b.ui) .. "|r " .. string.format("(%.1f, %.1f)", b.x or 0, b.y or 0)
            .. (tv ~= "" and ("  |cff66ff66" .. ns.L("会教：", "Teaches: ") .. tv .. "|r") or "")
            .. (tu ~= "" and ("  |cffffcc66" .. tu .. "|r|cffff9933" .. ns.L("（经典数据·待实测）", " (Classic, unverified)") .. "|r") or "")
        local l2 = text(row, "GameFontHighlightSmall", 42, -22, 496, line2)
        l2:SetWordWrap(false)
        local mb = ns.Button(row, ns.L("地图", "Map"), 56, 20, function() M.ShowBeast(b) end)
        mb:SetPoint("TOPRIGHT", -6, -10)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self) tip(self, b) end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row.mapBtn, row.beast = mb, b
        ctx.rows[#ctx.rows + 1] = row
        y = y - 44
    end
    c:SetHeight(-y + 4)
    M.lastView = ctx
end

-- ---------- 「宠物技能」视图：每个技能下面的「会教的野兽」----------
-- 在 parent（技能行）的 y0 处往下画，返回占了多高（0 = 这个技能没有野兽教，比如驯服即会 / 无限新技能）
function M.SkillTeachers(parent, s, y0)
    local ranks = M.Ranks(s.en)
    if #ranks == 0 then return 0 end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 46, y0); fs:SetWidth(556); fs:SetJustifyH("LEFT")
    -- 11-20 用户「矫正这部分数据」：众包驯服结果证实《无限》仍是「驯服学技能」，旧的「玩家反馈不带技能」提示撤掉
    -- 11-21 用户「字数太多了」：说明压成一行，学法写在技能页底部
    fs:SetText(ns.L("会教的野兽（|cff66ff66绿|r = 无限实测 · |cffffcc66黄|r = 经典数据 · 点名字 = 地图标点）",
        "Taught by (|cff66ff66green|r = verified · |cffffcc66yellow|r = Classic data · click = map)"))
    fs:SetWordWrap(true)
    local y = y0 - math.max(15, math.ceil((fs.GetStringHeight and fs:GetStringHeight() or 12) + 3))
    local btns = rawget(parent, "teachBtns") or {}   -- rawget：框体上没有的键别走方法表
    parent.teachBtns = btns
    for _, rk in ipairs(ranks) do
        local lab = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lab:SetPoint("TOPLEFT", 46, y - 2); lab:SetWidth(50); lab:SetJustifyH("LEFT")
        lab:SetText("|cffffcc66" .. ns.L("等级 " .. rk, "Rank " .. rk) .. "|r")
        local list = M.Teachers(s.en, rk)
        for j = 1, math.min(#list, M.RANK_SHOW) do
            local b = list[j]
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(166, 16)
            btn:SetPoint("TOPLEFT", 96 + (j - 1) * 170, y)
            local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", 0, 0); t:SetWidth(166); t:SetJustifyH("LEFT"); t:SetWordWrap(false)
            t:SetText((verifiedFor(b, s.en, rk) and "|cff66ff66" or "|cffffcc66") .. beastName(b) .. "|r " .. GREY .. lvText(b) .. ns.L("级·", " · ") .. zoneName(b.ui) .. "|r")
            btn:SetScript("OnClick", function() M.ShowBeast(b) end)
            btn:SetScript("OnEnter", function(self) tip(self, b) end)
            btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            btn.beast = b
            btns[#btns + 1] = btn
        end
        y = y - 17
    end
    return y0 - y + 2
end
