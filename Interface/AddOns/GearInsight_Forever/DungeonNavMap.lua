-- 副本导航 · 可视化地图（11-15 用户看了黑暗深渊导航样品：「需要可视化地图，不是就文字！」，HOLD）
--   面板上方画一张副本地图：首领 / 机制点编号圆点 + 推荐路线连线 + 当前目标金色呼吸放大 + 已击杀灰色打勾 + 可选的淡色；
--   多层副本左上角楼层按钮，当前步在哪层自动切过去；「放大」开一个大窗口看同一张图；标题栏「文字 / 地图」切换
--   ⛔ 副本里拿不到玩家坐标 / 朝向 / 地图编号（记忆 dev-notes/forever-instance-no-position-secret-guid-1115.md）→ 不画玩家箭头，
--      只画「目标在哪、路线怎么连」，进度照旧按首领击杀 / 上一步下一步推进
--   贴图：《无限》客户端（wowf 1.60.1.70938）DB2 里没有副本 UiMap（只有 59 张野外 / 主城图），但经典副本地图贴图文件还在客户端里：
--      interface/worldmap/blackfathomdeeps/blackfathomdeeps{1,2,3}_{1..12}.blp（FileDataID 447578-447613，wago.tools 按 wowf 构建能取到），
--      每层 4×3 块 256 像素，可见区域 1002×668 → 按 FileDataID SetTexture 拼。贴图设不上（SetTexture 返回 false）→ 这张图作废，面板退回纯文字
--   坐标：DB2 里没有 JournalEncounter / JournalInstance（wago 查 wowf 构建 Table not found）→ 首领位置按官方地图贴图上自带的骷髅标记取，
--      没骷髅的（稀有 / 召唤 / 火盆 / 楼层出入口）按经典布局手标，approx = true，悬停提示写「约」
--   通用：每个副本数据挂 d.map = { w, h, layers = { { name, short, tiles = { 12 个 FileDataID } } }, points = { [步号] = { 层, x, y, approx } },
--      extras = { 入口 / 楼层出入口 / 火盆，side = "left" 标签放左边 }, route = { 路线节点 } }（像素坐标，按 w × h 的贴图）
--   11-15「所有的副本都要安排」：地图数据挪到 DungeonNavData.lua（scripts/gi_forever_dnav_build.py 生成）：经典副本贴图用零售 DB2 UiMap 定位、
--      按《无限》构建逐块确认存在；首领点 = 冒险手册坐标（零售 / 熊猫人经典 DB2 JournalEncounter）换算；没坐标的步骤不画点、没贴图的副本只出文字
--   本文件在主插件 HOLD 里：不加载 = 副本导航还是原来的纯文字面板，其余照旧
--   11-16「小地图和羊皮纸地图都要，可以切换」：每个本最多两种图 —— d.map = 羊皮纸（经典世界地图 12 块）、d.minimap = 小地图（客户端小地图贴图拼）
--      两种都有 → 标题栏「羊皮纸 / 小地图」切换（放大窗口同样能切），玩家选的存 ns.db.dnav.kind；没选过 = 有羊皮纸先羊皮纸
--      《无限》新副本只有小地图 → 默认就是小地图。贴图设不上 → 那一种这一局作废（M.broken[种类][iid]），自动换另一种，两种都坏 → 纯文字
--      小地图层两种拼法：ADT 网格（cols / tp / ox / oy = 可见区在网格里的偏移 / tiles，0 = 空块）；WMO 平铺（pc = { fid 或差值, x, y, sz, … }，rot = 1 每块顺时针转 90°）
--      不是 3:2 的图按比例缩放、横向居中，高度最多宽度的 0.8 倍
--   11-18「需要标记 boss 位置 / 需要可以放大缩小」：滚轮缩放（以鼠标为中心）/ 按住拖动平移 / 复位 / 换步自动居中 / 首领名标签
--      在资讯子插件 GearInsight_Forever_Info/DnavZoom.lua（HOLD，按需加载，主插件登录内存不涨）；这里只留视图变换（cv.zoomer.View）
--      和可见区裁剪的接口，没加载 = 整张图、和原来一模一样。没坐标的首领照旧不画点（⛔ 不编坐标）
local _, ns = ...
local DN = ns.DungeonNav
if not DN then return end
local L = function(cn, en) return ns.L(cn, en) end
-- 11-15 用户截图「为啥是繁体，要简体」：ns.ToTW 只要繁体表在就转（合并包里繁体表常驻）→ 改用 ns.TD（只在繁体模式下转）
local TW = DN._TW   -- DungeonNav.lua

local M = { W = 440, BIGW = 860 }
DN.Map = M
ns.DungeonNavMap = M
M.broken = { map = {}, minimap = {} }   -- [种类][iid] = true：贴图设不上，这一局这一种不再试
M.KINDS = { "map", "minimap" }          -- 羊皮纸在前：没选过时有羊皮纸先显示羊皮纸
M.ASPECT = 0.8                          -- 图高最多 = 宽 × 0.8（竖长的小地图缩小、横向居中）
M.TEX_CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
M.TEX_PASS = "Interface\\Buttons\\UI-CheckBox-Check"
M.TEX_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
M.TEX_FIRE = "Interface\\Icons\\Spell_Fire_Fire"
M.TEX_PORTAL = "Interface\\Icons\\Spell_Arcane_PortalDarnassus"

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if r[1] then return unpack(r, 2) end
    return nil
end

-- ---------- 判断 ----------
-- 这个副本能画这种图吗（kind = "map" 羊皮纸 / "minimap" 小地图；不给 = 任意一种）：有数据、层 / 贴图齐全、这一局没被判坏
function M.Usable(d, kind)
    if kind == nil then return M.Usable(d, "map") or M.Usable(d, "minimap") end
    if type(d) ~= "table" or not M.broken[kind] then return false end
    local mp = d[kind]
    if type(mp) ~= "table" or type(mp.layers) ~= "table" or #mp.layers == 0 or M.broken[kind][d.iid] then return false end
    if not (tonumber(mp.w) and tonumber(mp.h) and mp.w > 0 and mp.h > 0) then return false end
    for _, ly in ipairs(mp.layers) do
        if type(ly.tex) == "string" then
        elseif type(ly.pc) == "table" then
            if #ly.pc == 0 or #ly.pc % 4 ~= 0 then return false end
        elseif type(ly.tiles) ~= "table" or #ly.tiles ~= M.TileCount(mp, ly) then
            return false
        end
    end
    return true
end
-- 能画的种类（按 M.KINDS 顺序）
function M.Kinds(d)
    local o = {}
    for _, k in ipairs(M.KINDS) do if M.Usable(d, k) then o[#o + 1] = k end end
    return o
end
-- 现在该画哪种：玩家选过且能画 → 那种；否则第一种能画的（有羊皮纸先羊皮纸，新副本只有小地图）
function M.Kind(d)
    local pref = ns.db and ns.db.dnav and ns.db.dnav.kind
    if pref and M.Usable(d, pref) then return pref end
    return M.Kinds(d)[1]
end
function M.KindName(k) return (k == "minimap") and L("小地图", "Minimap") or L("羊皮纸", "Parchment") end
-- 切换按钮：两种都能画才显示，按钮上写「切过去的那种」（和「文字 / 地图」按钮一个习惯）；返回是否显示
function M.KindButton(btn, d)
    if not btn then return false end
    local ks = M.Kinds(d)
    if #ks < 2 then btn:Hide(); return false end
    local cur = M.Kind(d)
    btn:SetText(M.KindName((cur == ks[1]) and ks[2] or ks[1]))
    btn:Show()
    return true
end
-- 切到另一种（两种都能画才切）；记住玩家选的
function M.ToggleKind(d)
    local ks = M.Kinds(d)
    if #ks < 2 then return false end
    local cur = M.Kind(d)
    local nx = (cur == ks[1]) and ks[2] or ks[1]
    if ns.db then ns.db.dnav = ns.db.dnav or {}; ns.db.dnav.kind = nx end
    if DN.Refresh then call(DN.Refresh) end
    if M.big and M.big:IsShown() then M.RefreshBig() end
    return true
end
-- 11-15「新副本的地图」：层的拼法可配 —— cols 列、tp 每块像素（默认 4 列 × 256 = 经典世界地图）；ox / oy = 可见区左上角在网格里的偏移；
--   《无限》新副本用客户端小地图贴图拼（块数不定，tiles 里 0 = 空块）；tex = 插件自带整张图（tc = 贴图坐标 { l, r, t, b }）
function M.Grid(ly) return tonumber(ly.cols) or 4, tonumber(ly.tp) or 256 end
function M.TileCount(mp, ly)
    local cols, tp = M.Grid(ly)
    return cols * math.ceil(((tonumber(ly.oy) or 0) + mp.h) / tp)
end
-- 画布尺寸：宽 w 时的缩放 s、图高 h、横向居中偏移 ox
--   11-17 面板拖过高度：maxH = 地图能用的高度 → 等比缩到宽、高都放得下（不再限 0.8 倍宽，拉高就跟着变大）
function M.Fit(mp, w, maxH)
    maxH = tonumber(maxH)
    local s = (maxH and maxH > 0) and math.min(w / mp.w, maxH / mp.h) or math.min(w / mp.w, w * M.ASPECT / mp.h)
    local h = math.floor(mp.h * s + 0.5)
    return s, h, math.floor((w - mp.w * s) / 2 + 0.5)
end
-- 某步在哪层（没位置 → nil）
function M.StepLayer(mp, i)
    local p = mp.points and mp.points[i]
    return p and p[1] or nil
end
-- 当前该看哪层：手动点过楼层（同一步内）→ 那层；否则当前步所在层；当前步没位置 → 往前找最近有位置的步
function M.PickLayer(cv, mp, cur, n, kind)
    local ul = rawget(cv, "userLayer")
    if ul and rawget(cv, "userStep") == cur and rawget(cv, "userKind") == kind and mp.layers[ul] then return ul end
    cv.userLayer, cv.userStep = nil, nil
    for i = math.min(cur, n), 1, -1 do
        local ly = M.StepLayer(mp, i)
        if ly then return ly end
    end
    return 1
end
-- 一步的状态：kill / pass / cur / opt / todo
function M.StepState(run, s, i, cur)
    local dn = run.done and run.done[i]
    if dn == "kill" then return "kill" end
    if dn == "pass" then return "pass" end
    if i == cur then return "cur" end
    if s and s.opt then return "opt" end
    return "todo"
end
-- 路线拆成线段：{ layer, x1, y1, x2, y2, target = 这段通往的步号 }
function M.Segments(mp)
    if mp._segs then return mp._segs end
    local nodes = {}
    for _, nd in ipairs(mp.route or {}) do
        if nd.s then
            local p = mp.points and mp.points[nd.s]
            if p then nodes[#nodes + 1] = { p[1], p[2], p[3], s = nd.s } end
        elseif nd.go then
            nodes[#nodes + 1] = { go = nd.go }
        elseif nd[1] then
            nodes[#nodes + 1] = { nd[1], nd[2], nd[3] }
        end
    end
    -- 每个节点往后第一个步号 = 它前面那段线通往哪一步
    local nextS = {}
    local tgt
    for j = #nodes, 1, -1 do
        if nodes[j].s then tgt = nodes[j].s end
        nextS[j] = tgt
    end
    local segs = {}
    for j = 2, #nodes do
        local a, b = nodes[j - 1], nodes[j]
        if not a.go and not b.go and a[1] == b[1] and nextS[j] then
            segs[#segs + 1] = { a[1], a[2], a[3], b[2], b[3], target = nextS[j] }
        end
    end
    mp._segs = segs
    return segs
end
-- 线段状态：通往已完成 / 已过的步 = past；通往当前步 = now；通往可选 = opt；其余 todo
function M.SegState(run, steps, target, cur)
    if (run.done and run.done[target]) or target < cur then return "past" end
    if target == cur then return "now" end
    if steps[target] and steps[target].opt then return "opt" end
    return "todo"
end

-- ---------- 画布 ----------
-- 11-18 用户参考图「学下这个」：路线分段配色 粉 = 走过 / 橙 = 当前段 / 黄 = 后面（可选的黄色淡一些）
local SEG_COLOR = {
    past = { 0.93, 0.42, 0.72, 0.75, 2 }, now = { 1, 0.55, 0.1, 1, 3 },
    todo = { 1, 0.85, 0.25, 0.9, 2 }, opt = { 1, 0.85, 0.25, 0.4, 2 },
}
local DOT_COLOR = {
    kill = { 0.45, 0.45, 0.45 }, pass = { 0.45, 0.45, 0.45 }, cur = { 1, 0.78, 0.1 },
    todo = { 0.16, 0.55, 0.85 }, opt = { 0.5, 0.5, 0.5 },
}

local function circle(owner, tex)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    local m = call(owner.CreateMaskTexture, owner)
    if not m then return end
    call(m.SetTexture, m, M.TEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    call(m.SetAllPoints, m, tex)
    call(tex.AddMaskTexture, tex, m)
end
local function smallBtn(parent, w, text, click)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    b:SetSize(w, 16); b:SetText(text)
    b:SetScript("OnClick", click)
    return b
end
local function tipShow(owner, lines)
    local tt = rawget(_G, "GameTooltip")
    if not tt then return end
    call(tt.SetOwner, tt, owner, "ANCHOR_RIGHT")
    for j, ln in ipairs(lines) do
        if j == 1 then call(tt.SetText, tt, ln[1], ln[2] or 1, ln[3] or 0.82, ln[4] or 0, 1, true)
        else call(tt.AddLine, tt, ln[1], ln[2] or 1, ln[3] or 1, ln[4] or 1, true) end
    end
    call(tt.Show, tt)
end
local function tipHide()
    local tt = rawget(_G, "GameTooltip")
    if tt then call(tt.Hide, tt) end
end

function M.Canvas(host)
    if rawget(host, "dnavMap") then return rawget(host, "dnavMap") end
    local cv = CreateFrame("Frame", nil, host)
    cv:SetSize(100, 100)
    cv.bg = cv:CreateTexture(nil, "BACKGROUND")
    cv.bg:SetAllPoints(); call(cv.bg.SetColorTexture, cv.bg, 0, 0, 0, 0.6)
    cv.tiles = {}
    cv.lines, cv.dots, cv.marks = {}, {}, {}
    -- 楼层名（左下）
    cv.floorBg = cv:CreateTexture(nil, "OVERLAY")
    call(cv.floorBg.SetColorTexture, cv.floorBg, 0, 0, 0, 0.55)
    cv.floor = cv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cv.floor:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", 5, 4)
    cv.floorBg:SetPoint("TOPLEFT", cv.floor, "TOPLEFT", -3, 2); cv.floorBg:SetPoint("BOTTOMRIGHT", cv.floor, "BOTTOMRIGHT", 3, -2)
    cv.floorBtns = {}
    cv.zoom = smallBtn(cv, 44, L("放大", "Zoom"), function() M.ToggleBig() end)
    cv.zoom:SetPoint("TOPRIGHT", cv, "TOPRIGHT", -3, -3)
    -- 当前目标呼吸
    cv.t = 0
    cv:SetScript("OnUpdate", function(self, el)
        local g = rawget(self, "glow")
        if not g then return end
        self.t = (self.t or 0) + (tonumber(el) or 0)
        call(g.SetAlpha, g, 0.35 + 0.35 * math.sin(self.t * 4))
    end)
    host.dnavMap = cv
    return cv
end

local function getLine(cv, j)
    local ln = cv.lines[j]
    if ln then return ln end
    if not cv.CreateLine then return nil end
    ln = {}
    ln.under = call(cv.CreateLine, cv, nil, "ARTWORK")
    ln.top = call(cv.CreateLine, cv, nil, "ARTWORK")
    if not (ln.under and ln.top) then return nil end
    call(ln.under.SetDrawLayer, ln.under, "ARTWORK", 1)
    call(ln.top.SetDrawLayer, ln.top, "ARTWORK", 2)
    cv.lines[j] = ln
    return ln
end
local function getDot(cv, j)
    local b = cv.dots[j]
    if b then return b end
    b = CreateFrame("Button", nil, cv)
    b:SetFrameLevel((cv.GetFrameLevel and cv:GetFrameLevel() or 1) + 3)
    b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetPoint("CENTER"); call(b.glow.SetColorTexture, b.glow, 1, 0.82, 0, 1); circle(b, b.glow)
    b.ring = b:CreateTexture(nil, "BORDER"); b.ring:SetPoint("CENTER"); call(b.ring.SetColorTexture, b.ring, 0, 0, 0, 0.95); circle(b, b.ring)
    b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("CENTER"); circle(b, b.fill)
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.num:SetPoint("CENTER", 0, 0)
    b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetPoint("CENTER", 4, -3); b.check:SetSize(12, 12)
    b:SetScript("OnEnter", function(self) local t = rawget(self, "tip"); if t then tipShow(self, t) end end)
    b:SetScript("OnLeave", tipHide)
    cv.dots[j] = b
    return b
end
local function getMark(cv, j)
    local b = cv.marks[j]
    if b then return b end
    b = CreateFrame("Button", nil, cv)
    b:SetFrameLevel((cv.GetFrameLevel and cv:GetFrameLevel() or 1) + 2)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b:SetScript("OnEnter", function(self) local t = rawget(self, "tip"); if t then tipShow(self, t) end end)
    b:SetScript("OnLeave", tipHide)
    cv.marks[j] = b
    return b
end

-- 悬停提示：步名 + 状态 + 位置说明 + 正文（怎么走 / 注意 / 任务 / 掉落）
--   位置说明：小地图上的「约」= 攻略插图对齐的大致位置（《无限》新副本）；ps = "ac" = 经典刷怪点世界坐标换算
function M.StepTip(s, i, state, p, mp, kind)
    local t = { { TW(i .. ". " .. (s.title or "")) } }
    local st = ({ kill = L("已击杀", "Killed"), pass = L("已过", "Passed"), cur = L("当前目标", "Current target"),
                  opt = L("可选", "Optional"), todo = L("待打", "To do") })[state]
    if st then t[#t + 1] = { st, 0.6, 0.85, 1 } end
    if p then
        local where
        if p[4] and kind == "minimap" and not (mp and mp.ps == "ac") then
            where = L("位置：约（按攻略插图大致标注）", "Location: approximate (from guide map)")
        elseif p[4] then
            where = L("位置：约（按经典布局大致标注）", "Location: approximate (classic layout)")
        elseif mp and mp.ps == "ac" then
            where = L("位置：经典刷怪点坐标换算", "Location: classic spawn point")
        else
            where = L("位置：官方副本图骷髅标记", "Location: skull mark on the official map")
        end
        t[#t + 1] = { where, 0.6, 0.6, 0.6 }
    end
    local body = DN.StepBody and DN.StepBody(s, DN.Faction and DN.Faction()) or ""
    for ln in tostring(body):gmatch("[^\n]+") do t[#t + 1] = { TW(ln) } end
    return t
end

-- 画一张：host 里 (x, y) 处、宽 w；返回高度（画不了 → nil，调用方退回纯文字）
--   先画玩家选的那种；贴图设不上 → 那种作废、换另一种再画一次；两种都不行 → nil
function M.Draw(host, w, run, d, cur, x, y, maxH)
    if type(run) ~= "table" then return nil end
    for _ = 1, #M.KINDS do
        local kind = M.Kind(d)
        if not kind then break end
        local h = M.DrawKind(host, w, run, d, cur, x, y, kind, maxH)
        if h then return h end
        if not M.broken[kind][d.iid] then break end
    end
    M.Hide(host)
    return nil
end

-- 一块贴图：设上（失败 → false）、摆到 (l, t) 宽 pw 高 ph（图内像素 × s，再加偏移），只露出画布内看得见的部分
--   vw = { s, ox, oy, 可见区 x0, y0, x1, y1 }（图内像素；11-18 缩放 / 平移后只露出窗口里那块，没缩放 = 整张图）
--   rot = 1：贴图顺时针转 90° 贴（WMO 小地图块），8 参数 SetTexCoord；tc = 整张图的贴图坐标 { l, r, t, b }
local function placeTile(cv, tx, tex, l, t, pw, ph, vw, rot, tc)
    local x0, y0 = math.max(l, vw[4]), math.max(t, vw[5])
    local x1, y1 = math.min(l + pw, vw[6]), math.min(t + ph, vw[7])
    if x1 <= x0 or y1 <= y0 then tx:Hide(); return true end
    if tx:SetTexture(tex) == false then return false end
    local fx0, fx1, fy0, fy1 = (x0 - l) / pw, (x1 - l) / pw, (y0 - t) / ph, (y1 - t) / ph
    tx:ClearAllPoints(); tx:SetPoint("TOPLEFT", cv, "TOPLEFT", vw[2] + x0 * vw[1], -(vw[3] + y0 * vw[1]))
    tx:SetSize((x1 - x0) * vw[1], (y1 - y0) * vw[1])
    if rot == 1 then   -- 画面 (fx, fy) ← 贴图 (u = fy, v = 1 - fx)
        call(tx.SetTexCoord, tx, fy0, 1 - fx0, fy1, 1 - fx0, fy0, 1 - fx1, fy1, 1 - fx1)
    elseif tc then
        local du, dv = tc[2] - tc[1], tc[4] - tc[3]
        call(tx.SetTexCoord, tx, tc[1] + du * fx0, tc[1] + du * fx1, tc[3] + dv * fy0, tc[3] + dv * fy1)
    else
        call(tx.SetTexCoord, tx, fx0, fx1, fy0, fy1)
    end
    tx:Show()
    return true
end

function M.DrawKind(host, w, run, d, cur, x, y, kind, maxH)
    if not M.Usable(d, kind) then return nil end
    local mp = d[kind]
    local steps = d.steps or {}
    local n = #steps
    local cv = M.Canvas(host)
    -- 11-18「需要可以放大缩小」：滚轮缩放 / 拖动平移在资讯子插件 DnavZoom.lua（HOLD，按需加载）；没加载 = 整张图，和原来一样
    if not rawget(cv, "zTried") then cv.zTried = true; call(ns.DnavZoomAttach, cv) end
    local s, h, ox = M.Fit(mp, w, maxH)
    if rawget(cv, "zoomer") then h = math.floor((maxH and maxH > 0) and maxH or w * 0.9) end   -- 11-18「优化视图」：缩放模块按首领范围铺满，地图区加高
    cv:ClearAllPoints(); cv:SetPoint("TOPLEFT", host, "TOPLEFT", x or 0, y or 0); cv:SetSize(w, h)
    cv:Show()
    local layer = M.PickLayer(cv, mp, cur, n, kind)
    cv.layer, cv.kind = layer, kind
    local ly = mp.layers[layer]
    local Z, oy = rawget(cv, "zoomer"), 0
    if Z then
        local s2, ox2, oy2 = call(Z.View, cv, d.iid, kind, layer, cur, w, h, s, ox, mp, d)
        if s2 then s, ox, oy = s2, ox2, oy2 end
    end
    -- 画布里看得见的图内像素范围
    local vw = { s, ox, oy, math.max(0, -ox / s), math.max(0, -oy / s), math.min(mp.w, (w - ox) / s), math.min(mp.h, (h - oy) / s) }
    local function inView(px, py) return px >= vw[4] and px <= vw[6] and py >= vw[5] and py <= vw[7] end
    -- bg = 1（ADT 小地图）：图的范围里铺小地图本身的灰底，空块不露黑洞
    if mp.bg then
        if not rawget(cv, "bg2") then cv.bg2 = cv:CreateTexture(nil, "BACKGROUND", nil, 1) end
        call(cv.bg2.SetColorTexture, cv.bg2, 0.43, 0.43, 0.43, 1)
        cv.bg2:ClearAllPoints(); cv.bg2:SetPoint("TOPLEFT", cv, "TOPLEFT", ox + vw[4] * s, -(oy + vw[5] * s))
        cv.bg2:SetSize((vw[6] - vw[4]) * s, (vw[7] - vw[5]) * s)
        cv.bg2:Show()
    elseif rawget(cv, "bg2") then
        cv.bg2:Hide()
    end
    local function fail()   -- 客户端里没有这张贴图 → 这一种图作废（换另一种 / 退回文字）
        M.broken[kind][d.iid] = true
        cv:Hide()
        return nil
    end
    local function tex(k)
        local tx = cv.tiles[k]
        if not tx then tx = cv:CreateTexture(nil, "BORDER"); cv.tiles[k] = tx end
        return tx
    end
    -- 贴图：tex = 整张图；pc = 平铺块（fid, x, y, w, h）；否则网格 cols 列 × tp 像素一块（经典 4×3 × 256），ox / oy 偏移，0 = 空块
    local nt = 0
    if ly.tex then
        nt = 1
        if not placeTile(cv, tex(1), ly.tex, 0, 0, mp.w, mp.h, vw, nil, ly.tc or { 0, 1, 0, 1 }) then return fail() end
    elseif ly.pc then   -- 每块 4 个数：fid（和上一块相差 < 100000 时是差值）, x, y, sz = log2(宽) × 10 + log2(高)
        local pc, fid = ly.pc, nil
        for j = 1, #pc - 3, 4 do
            local v, sz = pc[j], pc[j + 3]
            fid = (fid and v > -100000 and v < 100000) and (fid + v) or v
            nt = nt + 1
            if not placeTile(cv, tex(nt), fid, pc[j + 1], pc[j + 2], 2 ^ math.floor(sz / 10), 2 ^ (sz % 10), vw, ly.rot) then return fail() end
        end
    else
        local cols, tp = M.Grid(ly)
        local gx, gy = tonumber(ly.ox) or 0, tonumber(ly.oy) or 0
        for k, fid in ipairs(ly.tiles) do
            nt = nt + 1
            local tx = tex(nt)
            if fid and fid ~= 0 then
                local col, row = (k - 1) % cols, math.floor((k - 1) / cols)
                if not placeTile(cv, tx, fid, col * tp - gx, row * tp - gy, tp, tp, vw) then return fail() end
            else
                tx:Hide()
            end
        end
    end
    for k = nt + 1, #cv.tiles do cv.tiles[k]:Hide() end
    -- 路线
    local segs = M.Segments(mp)
    local nl = 0
    local info = { layer = layer, kind = kind, lines = 0, dots = {}, marks = 0, tiles = nt, s = s, ox = ox, h = h }
    for _, sg in ipairs(segs) do
        local a1, b1, a2, b2 = sg[2], sg[3], sg[4], sg[5]
        if Z and Z.Clip then a1, b1, a2, b2 = Z.Clip(a1, b1, a2, b2, vw[4], vw[5], vw[6], vw[7]) end   -- 缩放后裁到窗口里
        if sg[1] == layer and a1 then
            local ln = getLine(cv, nl + 1)
            if not ln then break end
            nl = nl + 1
            local st = M.SegState(run, steps, sg.target, cur)
            local c = SEG_COLOR[st]
            for _, part in ipairs({ ln.under, ln.top }) do
                call(part.ClearAllPoints, part)
                call(part.SetStartPoint, part, "TOPLEFT", cv, ox + a1 * s, -(oy + b1 * s))
                call(part.SetEndPoint, part, "TOPLEFT", cv, ox + a2 * s, -(oy + b2 * s))
                call(part.Show, part)
            end
            call(ln.under.SetThickness, ln.under, c[5] + 2); call(ln.under.SetColorTexture, ln.under, 0, 0, 0, c[4] * 0.7)
            call(ln.top.SetThickness, ln.top, c[5]); call(ln.top.SetColorTexture, ln.top, c[1], c[2], c[3], c[4])
            ln.state = st
        end
    end
    for j = nl + 1, #cv.lines do call(cv.lines[j].under.Hide, cv.lines[j].under); call(cv.lines[j].top.Hide, cv.lines[j].top) end
    info.lines = nl
    -- 入口 / 楼层出入口 / 火盆
    local nm = 0
    for _, e in ipairs(mp.extras or {}) do
        if e.layer == layer and inView(e.x, e.y) then
            nm = nm + 1
            local b = getMark(cv, nm)
            local sz = (e.k == "fire") and 12 or 14
            b:ClearAllPoints(); b:SetPoint("CENTER", cv, "TOPLEFT", ox + e.x * s, -(oy + e.y * s)); b:SetSize(sz, sz)
            b.icon:SetTexture((e.k == "fire" and M.TEX_FIRE) or (e.k == "go" and M.TEX_PORTAL) or "Interface\\Buttons\\WHITE8x8")
            if e.k == "start" then call(b.icon.SetVertexColor, b.icon, 0.3, 0.9, 0.3) else call(b.icon.SetVertexColor, b.icon, 1, 1, 1) end
            b.label:ClearAllPoints()
            if e.label then
                if e.side == "left" then b.label:SetPoint("RIGHT", b, "LEFT", -2, 0) else b.label:SetPoint("LEFT", b, "RIGHT", 2, 0) end
                b.label:SetText(TW(e.label))
                b.label:Show()
            else
                b.label:Hide()
            end
            b.tip = (e.k == "fire") and { { L("火盆（约）", "Brazier (approx.)") }, { L("密室里 4 个火盆，挨个点亮", "Light all 4 braziers in the sanctum") } }
                or (e.k == "go" and { { TW(e.label or "") }, { L("点击切到那一层", "Click to switch floor"), 0.6, 0.85, 1 } })
                or { { L("副本入口", "Entrance") } }
            b:SetScript("OnClick", e.to and function() M.SetLayer(cv, e.to, rawget(cv, "curStep")) end or nil)
            b:Show()
        end
    end
    for j = nm + 1, #cv.marks do cv.marks[j]:Hide() end
    info.marks = nm
    -- 步骤圆点（当前目标最后画在最上面）
    local nd = 0
    cv.glow = nil
    local big = math.max(1, math.min(1.4, w / 430))   -- 11-17 面板拉宽时圆点平滑变大（默认 424 = 1，放大窗口 860 = 1.4，和原来一致）
    local order = {}
    for i = 1, n do if i ~= cur then order[#order + 1] = i end end
    if cur <= n then order[#order + 1] = cur end
    for _, i in ipairs(order) do
        local p = mp.points and mp.points[i]
        if p and p[1] == layer and inView(p[2], p[3]) then
            nd = nd + 1
            local b = getDot(cv, nd)
            local st = M.StepState(run, steps[i], i, cur)
            local r = math.floor(((st == "cur") and 20 or 15) * big + 0.5)
            b:ClearAllPoints(); b:SetPoint("CENTER", cv, "TOPLEFT", ox + p[2] * s, -(oy + p[3] * s)); b:SetSize(r, r)
            b:SetFrameLevel((cv.GetFrameLevel and cv:GetFrameLevel() or 1) + ((st == "cur") and 6 or 3))
            b.ring:SetSize(r, r); b.fill:SetSize(r - 4, r - 4)
            local c = DOT_COLOR[st]
            call(b.fill.SetColorTexture, b.fill, c[1], c[2], c[3], (st == "opt") and 0.75 or 1)
            b.num:SetText((st == "cur") and ("|cff000000" .. i .. "|r") or ((st == "kill" or st == "pass") and ("|cffbbbbbb" .. i .. "|r") or tostring(i)))
            if st == "cur" then
                b.glow:SetSize(r + 12, r + 12); b.glow:Show(); cv.glow = b.glow
            else
                b.glow:Hide()
            end
            if st == "kill" or st == "pass" then
                b.check:SetTexture(st == "kill" and M.TEX_CHECK or M.TEX_PASS); b.check:Show()
            else
                b.check:Hide()
            end
            b.step, b.state = i, st
            b.tip = M.StepTip(steps[i], i, st, p, mp, kind)
            b:Show()
            info.dots[#info.dots + 1] = { i = i, state = st, approx = p[4] and true or false }
        end
    end
    for j = nd + 1, #cv.dots do cv.dots[j]:Hide() end
    -- 楼层按钮（多层才有）
    local nlay = #mp.layers
    for k = 1, math.max(nlay, #cv.floorBtns) do
        local fb = cv.floorBtns[k]
        if k <= nlay and nlay > 1 then
            if not fb then
                fb = smallBtn(cv, 40, "", function() M.SetLayer(cv, k, rawget(cv, "curStep")) end)
                fb:SetScript("OnEnter", function(self) local m = rawget(cv, "mp"); if m and m.layers[k] then tipShow(self, { { TW(m.layers[k].name) } }) end end)
                fb:SetScript("OnLeave", tipHide)
                cv.floorBtns[k] = fb
            end
            fb:ClearAllPoints(); fb:SetPoint("TOPLEFT", cv, "TOPLEFT", 3 + (k - 1) * 42, -3)
            local nmk = TW(mp.layers[k].short or tostring(k))
            fb:SetText(k == layer and ("|cffffd100" .. nmk .. "|r") or nmk)
            if k == layer then call(fb.LockHighlight, fb) else call(fb.UnlockHighlight, fb) end
            fb:Show()
        elseif fb then
            fb:Hide()
        end
    end
    cv.floor:SetText(TW(ly.name))
    cv.curStep = cur
    cv.host = host
    cv.mp = mp
    cv.info = info
    M.last = info
    if Z then cv.args = { host, w, run, d, cur, x, y, kind, maxH }; call(Z.After, cv, d, info) end   -- 缩放后重画 / 首领名 / 复位按钮
    if M.big and host ~= M.big.body and M.big:IsShown() then call(M.RefreshBig) end
    return h
end

-- 手动点楼层：这一步之内保持，换到下一步自动跟着当前步切
function M.SetLayer(cv, k, cur)
    cv.userLayer, cv.userStep, cv.userKind = k, cur, rawget(cv, "kind")
    if M.big and rawget(cv, "host") == M.big.body then M.RefreshBig() else DN.Refresh() end
end
function M.Hide(host)
    local cv = host and rawget(host, "dnavMap")
    if cv then cv:Hide() end
end

-- ---------- 放大窗口 ----------
function M.BuildBig()
    if M.big then return M.big end
    local W = M.BIGW + 16
    local f = CreateFrame("Frame", "GearInsightForeverDungeonNavMap", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, 100)
    f:SetFrameStrata("HIGH")
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        pcall(f.SetBackdropColor, f, 0.05, 0.06, 0.08, 0.95); pcall(f.SetBackdropBorderColor, f, 0.41, 0.8, 0.94, 0.9)
    end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -7)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    -- 11-16「羊皮纸 / 小地图」切换（这个本两种都有才显示；按钮上写切过去的那种）
    f.kindBtn = smallBtn(f, 56, "", function()
        local run = DN.CurRun and DN.CurRun()
        local d = run and (DN.Get and DN.Get(run.iid) or DN.DATA[run.iid])
        if d then M.ToggleKind(d) end
    end)
    f.kindBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    f.kindBtn:Hide()
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 0, -24); f.body:SetSize(W, 100)
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f:Hide()
    M.big = f
    return f
end
function M.RefreshBig()
    local f = M.big
    if not (f and f:IsShown()) then return end
    local run = DN.CurRun and DN.CurRun()
    local d = run and (DN.Get and DN.Get(run.iid) or DN.DATA[run.iid])
    if not d then f:Hide(); return end
    local c = math.min(run.cur or 1, #d.steps + 1)
    f.title:SetText(TW(L("副本地图 · ", "Dungeon map - ") .. d.name))
    local h = M.Draw(f.body, M.BIGW, run, d, c, 8, 0)
    if not h then f:Hide(); return end
    M.KindButton(f.kindBtn, d)
    f.foot:ClearAllPoints(); f.foot:SetPoint("TOPLEFT", f.body, "TOPLEFT", 8, -h - 4)
    f.foot:SetText(M.Legend())
    f:SetHeight(24 + h + 24)
end
function M.ToggleBig()
    local f = M.BuildBig()
    if f:IsShown() then f:Hide(); return end
    f:Show()
    M.RefreshBig()
end
function M.Legend()
    return L("金色 = 当前　灰勾 = 已完成　淡色 = 可选", "Gold = current, tick = done, faded = optional")
end
