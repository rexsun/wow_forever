-- 天赋页：三棵树模拟加点（与小程序 / 网站模拟器同一份数据、同一套 GIF2 配点码）
-- 左键 +1，右键 -1；行解锁 = 每 5 点一行；前置天赋要点满；总数 ≤ 51
-- 颜色：绿=《无限》新增  黄=改动  蓝=换位置  灰=没变
local _, ns = ...; ns = _G.GearInsightForever or ns

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local CLASS_COLOR = { Warrior = "c79c6e", Paladin = "f58cba", Hunter = "abd473", Rogue = "fff569", Priest = "ffffff",
    Shaman = "0070de", Mage = "69ccf0", Warlock = "9482c9", Druid = "ff7d0a" }
local ST_COLOR = { new = { 0.2, 1, 0.4 }, changed = { 1, 0.82, 0.2 }, moved = { 0.4, 0.7, 1 }, same = { 0.45, 0.45, 0.45 } }
local CELL, GAP = 40, 12

local S = { cls = nil, pts = nil, path = nil, plan = nil, noAuto = {}, wcl = nil }

-- 11-23 重构 P2「WCL 热门」：TalentWclData.lua（scripts/gi_forever_talents_wcl.py 生成，forever WCL 60 级 51 点角色）按职业现解
--   → { { spec, specCn, n 样本, tree 主系, rec 推荐码正文, recN 推荐同款人数, diff 和最热门差几点, top = { { code, n }, … } }, … }；没数据（HOLD 没进包）= nil
local wclCache = {}
function ns.TalentWclSpecs(cls)
    local D = ns.TalentWclData
    if not (cls and type(D) == "table" and type(D.d) == "string") then return nil end
    if wclCache[cls] ~= nil then return wclCache[cls] or nil end
    local out = {}
    for line in D.d:gmatch("[^\r\n]+") do
        local f = {}
        for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
        if f[1] == cls then
            local top = {}
            for code, n in (f[9] or ""):gmatch("([^,;]+),(%d+)") do top[#top + 1] = { code = code, n = tonumber(n) } end
            out[#out + 1] = { spec = f[2], specCn = f[3], n = tonumber(f[4]) or 0, tree = tonumber(f[5]) or 1,
                rec = f[6], recN = tonumber(f[7]) or 0, diff = tonumber(f[8]) or 0, top = top }
        end
    end
    wclCache[cls] = #out > 0 and out or false
    return wclCache[cls] or nil
end
-- 10-07 用户截图「怎么没有默认配点路径？」：天赋页打开时这个职业一点没点 → 自动载入本职业默认升级加点（DefaultBuilds.lua），
--   每个点了的天赋右上角标「第几级开始点」，悬停写「第 10–14 级点这里（5 点）」；自己动了点就不再标（顺序不作数了）；
--   「清空」之后本次不再自动载入；底部「默认路线」随时一键恢复
local function pathOf(plan)
    local path = {}
    for k, o in ipairs(plan.order or {}) do
        local ti, i, lv = o[1], o[2], 9 + k
        path[ti] = path[ti] or {}
        local e = path[ti][i]
        if not e then path[ti][i] = { first = lv, last = lv, n = 1 } else e.last = lv; e.n = e.n + 1 end
    end
    return path
end

local function myClass()
    local _, token = UnitClass("player")
    token = token or "Warrior"
    return token:sub(1, 1) .. token:sub(2):lower()
end

local function blank(cls)
    local pts = {}
    for ti, tr in ipairs(ns.Data.talents[cls]) do
        pts[ti] = {}
        for i = 1, #tr.t do pts[ti][i] = 0 end
    end
    return pts
end

local function treeSum(ti, upToRow)
    local n = 0
    for i, t in ipairs(ns.Data.talents[S.cls][ti].t) do
        if not upToRow or t.r < upToRow then n = n + S.pts[ti][i] end
    end
    return n
end

local function total()
    local n = 0
    for ti = 1, #S.pts do n = n + treeSum(ti) end
    return n
end

local function findAt(ti, r, c)
    for i, t in ipairs(ns.Data.talents[S.cls][ti].t) do
        if t.r == r and t.col == c then return i, t end
    end
end

-- 整树合法：每个有点的天赋，它上面几行的点数够、前置点满
local function treeValid(ti)
    for i, t in ipairs(ns.Data.talents[S.cls][ti].t) do
        local v = S.pts[ti][i]
        if v > 0 then
            if treeSum(ti, t.r) < (t.r - 1) * 5 then return false end
            if t.rq then
                local j, rt = findAt(ti, t.rq[1], t.rq[2])
                if not j or S.pts[ti][j] < rt.m then return false end
            end
        end
    end
    return true
end

function ns.TalentCodeFromSim()
    if not S.cls then return nil end
    local parts = {}
    for ti = 1, #S.pts do
        local s = {}
        for i = 1, #S.pts[ti] do s[i] = tostring(math.min(9, S.pts[ti][i])) end
        parts[ti] = table.concat(s)
    end
    return "GIF2." .. S.cls .. "." .. table.concat(parts, "-")
end

local page
-- 11-12 重构第 1 期：「计划小窗」按钮（导入过配点计划才出）——小窗点 × 关掉后从这里再打开
local function planWinBtn()
    local b = page and rawget(page, "planWin")
    if not b then return end
    local st = ns.TalentPlanState and ns.TalentPlanState() or "none"
    if st == "shown" then b:SetText(ns.L("关闭计划小窗", "Hide plan window")); b:Show()
    elseif st == "hidden" then b:SetText(ns.L("打开计划小窗", "Show plan window")); b:Show()
    else b:Hide() end
end
ns._TalentPlanWinBtn = planWinBtn   -- 测试用
-- 11-23 用户截图「这里展示不对」：顶栏右侧几个按钮都是各自建的（本页设置 Settings.lua、训练师可学 TrainNow.lua、WCL 这里），
--   以前各锚各的 → 训练师按钮（TOPRIGHT -108）和 WCL 按钮叠在一起、副标题被挤。每次刷新从右往左排一遍：
--   本页设置 · WCL 热门天赋 · 训练师可学 · 副标题；按钮限宽、字超长省略，副标题单行省略 → 任何宽度都不叠
--   （TrainNow 的 paintBtn 之后会把副标题右端锚到训练师按钮左边 —— 训练师按钮本来就排在最左，一致）
local function layoutHead()
    local p = page
    if not p then return end
    local left = rawget(p, "_setBtn")
    local function put(b, w)
        b:SetWidth(w)
        local ok, fs = pcall(b.GetFontString, b)
        if ok and fs then fs:SetWidth(w - 12); fs:SetWordWrap(false) end
        b:ClearAllPoints()
        if left then b:SetPoint("RIGHT", left, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -7) end
        left = b
    end
    -- 11-23 用户截图「选不了其他排名了」：右键菜单没人发现 → WCL 按钮右边加「▼」，左键点它就是选专精 / 热门 #2 #3 / 推荐
    if p.wclArrow then p.wclArrow:SetShown(p.wclBtn and p.wclBtn:IsShown()) end
    if p.wclArrow and p.wclArrow:IsShown() then put(p.wclArrow, 22); left = p.wclArrow end
    if p.wclBtn and p.wclBtn:IsShown() then put(p.wclBtn, 116) end
    local TN = ns.TrainNow
    local tb = TN and TN._Btn and TN._Btn()
    if tb and rawequal(select(2, pcall(tb.GetParent, tb)), p) then put(tb, 116) end
    local sub = rawget(p, "_sub")
    if sub then
        sub:SetWordWrap(false)
        if left then sub:SetPoint("RIGHT", left, "LEFT", -8, 0) end
    end
end
local function refresh()
    -- 11-05 玩家「选了鸟德的天赋，天赋页还是野德的推荐」：天赋页第一次打开时就定了路线，之后点数投到别的系也不换
    --   → 自己职业、显示的是没动过的默认路线时，推荐方案变了（DefaultBuildKey 按投点最多的系）就换成新的
    if S.cls and S.cls == myClass() and S.plan and S.plan.default and S.path and not S.noAuto[S.cls]
        and ns.DefaultBuildKey and ns.LoadDefaultSim then
        local want = ns.DefaultBuildKey(S.cls)
        if want and want ~= S.plan.key then ns.LoadDefaultSim(S.cls); return end
    end
    if not page or not S.cls then return end
    planWinBtn()
    local trees = ns.Data.talents[S.cls]
    for ti, tr in ipairs(trees) do
        local col = page.trees[ti]
        col.head:SetText(ns.L(tr.c, tr.n) .. "  |cffffffff" .. treeSum(ti) .. "|r")
        for i, t in ipairs(tr.t) do
            local cell = col.cells[i]
            local v = S.pts[ti][i]
            cell.rank:SetText(v .. "/" .. t.m)
            local unlocked = treeSum(ti, t.r) >= (t.r - 1) * 5
            if v >= t.m then cell.rank:SetTextColor(1, 0.82, 0)
            elseif v > 0 then cell.rank:SetTextColor(0.2, 1, 0.4)
            else cell.rank:SetTextColor(0.75, 0.75, 0.75) end
            -- 10-07 用户「优化UI」：边框按经典天赋界面的状态上色（满 = 金 / 有点 = 绿 / 可点 = 白 / 锁 = 暗），
            -- 改动类型（新增 / 改动 / 换位）缩成左上角小圆点；⛔别再整格铺状态色 + 半透明图标，那就是「一墙黄块」
            local e
            if v >= t.m then e = { 1, 0.82, 0 }
            elseif v > 0 then e = { 0.2, 0.9, 0.3 }
            elseif unlocked then e = { 0.75, 0.75, 0.75 }
            else e = { 0.22, 0.22, 0.22 } end
            cell.edge:SetColorTexture(e[1], e[2], e[3], 1)
            cell.icon:SetDesaturated(v == 0 and not unlocked)
            local k = (v > 0 or unlocked) and 1 or 0.45
            cell.icon:SetVertexColor(k, k, k)
            cell.rank:SetShown(v > 0 or unlocked); cell.rb:SetShown(v > 0 or unlocked)
            local pe = S.path and S.path[ti] and S.path[ti][i]
            cell.lv:SetText(pe and tostring(pe.first) or ""); cell.lvbg:SetShown(pe ~= nil)
        end
    end
    for _, b in ipairs(page.classBtns) do b.sel:SetShown(b.cls == S.cls) end
    local n = total()
    page.info:SetText(ns.L("已用 ", "Spent ") .. n .. " / 51" .. ns.L("　需要等级 ", "   Required level ") .. (n > 0 and (n + 9) or "-"))
    -- 10-11 推荐方案按钮：当前职业选中的那套；正在按它的路线点就高亮
    local dp = S.cls and ns.DefaultPlan and ns.DefaultPlan(S.cls)
    if page.buildBtn then
        page.buildBtn:SetShown(dp ~= nil)
        if dp then
            local on = S.plan and S.path and S.plan.key == dp.key
            page.buildBtn:SetText((on and "|cffffd100" or "") .. ns.L("升级天赋选择：", "Leveling build: ") .. ns.L(dp.specCn or dp.spec or "", dp.spec or "") .. (on and "|r" or ""))
        end
    end
    if page.wclBtn then
        page.wclBtn:SetShown(ns.TalentWclSpecs(S.cls) ~= nil)
        page.wclBtn:SetText(S.wcl and ("|cffffd100WCL：" .. S.wcl .. "|r") or ns.L("WCL 热门天赋", "WCL popular"))
    end
    layoutHead()
    page.code:SetText(ns.TalentCodeFromSim() or "")
    page.learn:SetEnabled(S.cls == myClass() and n > 0)
end
ns.RefreshTalentSim = refresh

local function setClass(cls)
    S.cls = cls
    S.pts = blank(cls)
    S.path, S.plan, S.wcl = nil, nil, nil
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.simCls = cls
    if page then
        for ti, tr in ipairs(ns.Data.talents[cls]) do
            local col = page.trees[ti]
            for i, cell in ipairs(col.cells) do cell:Hide() end
            for i, t in ipairs(tr.t) do
                local cell = col.cells[i]
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", 8 + (t.col - 1) * (CELL + GAP), -24 - (t.r - 1) * (CELL + 8))
                local c = ST_COLOR[t.s]
                cell.dot:SetShown(c ~= nil); cell.dotbg:SetShown(c ~= nil)
                if c then cell.dot:SetVertexColor(c[1], c[2], c[3]) end
                cell.icon:SetTexture("Interface\\Icons\\" .. ((t.i and t.i ~= "") and t.i or "inv_misc_questionmark"))
                cell.ti, cell.i, cell.t = ti, i, t
                cell:Show()
            end
        end
    end
    refresh()
end

-- 载入本职业默认升级加点（带逐点顺序 → 右上角标第几级开始点）
local function loadDefault(cls)
    local plan = ns.DefaultPlan and ns.DefaultPlan(cls)
    if not plan then return false end
    setClass(cls)
    for ti = 1, #S.pts do for i = 1, #S.pts[ti] do S.pts[ti][i] = (plan.pts[ti] and plan.pts[ti][i]) or 0 end end
    S.plan, S.path = plan, pathOf(plan)
    refresh()
    return true
end
ns.LoadDefaultSim = loadDefault
-- 切职业：这个职业还没点过 → 自动载入默认路线（「清空」过的本次不自动）
local function showClass(cls)
    setClass(cls)
    if not S.noAuto[cls] then loadDefault(cls) end
end

function ns.LoadSimCode(code)
    local plan, why = ns.ParseTalentCode(code)
    if not plan then ns.Print(why); return false end
    setClass(plan.cls)
    S.pts = plan.pts
    refresh()
    return true   -- 导入的码只有最终配点、没有顺序：不标第几级
end

-- WCL 热门：把一套码载入模拟器（⛔ 只改模拟器，不动玩家天赋；要学照旧点「按这套逐点学」）
function ns.LoadWclSim(cls, body, label)
    local plan = ns.ParseTalentCode("GIF2." .. tostring(cls) .. "." .. tostring(body or ""))
    if not plan or plan.cls ~= cls then return false end
    S.noAuto[cls] = true   -- 本次不再被默认路线自动盖掉
    setClass(cls)
    S.pts, S.wcl = plan.pts, label
    refresh()
    return true
end

local function click(cell, btn)
    local ti, i, t = cell.ti, cell.i, cell.t
    local old = S.pts[ti][i]
    if btn == "RightButton" then
        if old == 0 then return end
        S.pts[ti][i] = old - 1
        if not treeValid(ti) then S.pts[ti][i] = old end
    else
        if old >= t.m or total() >= 51 then return end
        S.pts[ti][i] = old + 1
        if not treeValid(ti) then S.pts[ti][i] = old end
    end
    if S.pts[ti][i] ~= old then S.path, S.wcl = nil, nil end   -- 自己动了点：默认路线的顺序不作数了，不再标第几级（WCL 那套也不算了）
    refresh()
end

local function cellTooltip(cell)
    local t = cell.t
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.L(t.c, t.n), 1, 0.82, 0)
    -- 10-07 用户「确保都翻译」：中文界面不再附英文天赋名
    GameTooltip:AddLine(ns.L("等级 ", "Rank ") .. S.pts[cell.ti][cell.i] .. "/" .. t.m, 1, 1, 1)
    local pe = S.path and S.path[cell.ti] and S.path[cell.ti][cell.i]
    if pe then
        GameTooltip:AddLine((pe.first == pe.last) and string.format(ns.L("默认路线：第 %d 级点这里", "Default route: level %d"), pe.first)
            or string.format(ns.L("默认路线：第 %d 至 %d 级点这里（%d 点）", "Default route: levels %d-%d (%d points)"), pe.first, pe.last, pe.n), 0.4, 1, 0.4)
        GameTooltip:AddLine(ns.L("图标右上角的数字 = 默认路线里第几级开始点它（来源 ", "Corner number = level the default route starts it (source ")
            .. (S.plan and S.plan.src or "?") .. ns.L("）", ")"), 0.6, 0.6, 0.6, true)
    end
    local desc = ns.L(t.d, t.dEn)
    if desc and desc ~= "" then GameTooltip:AddLine(ns.EnSafe(desc), 1, 1, 1, true) end
    local note = ns.TooltipLookup and (ns.TooltipLookup(t.c) or ns.TooltipLookup(t.n))
    if note then
        local txt = ns.L(note.cn, note.en)
        if txt and txt ~= "" then GameTooltip:AddLine(txt, 1, 0.82, 0.4, true) end
    end
    if t.rq then
        local _, rt = findAt(cell.ti, t.rq[1], t.rq[2])
        if rt then GameTooltip:AddLine(ns.L("前置：", "Requires: ") .. ns.L(rt.c, rt.n) .. " " .. rt.m .. "/" .. rt.m, 1, 0.4, 0.4) end
    end
    GameTooltip:AddLine(ns.L("左键 +1　右键 -1", "Left +1   Right -1"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function build(p)
    page = p
    ns.PageHeader(p, ns.L("天赋", "Talents"), ns.L("和小程序 / 网站模拟器同一套配点码", "Same build codes as the site and mini program"))

    -- 11-23 重构 P2：右上角「WCL 热门天赋」（数据没进包时不显示）
    p.wclBtn = ns.Button(p, ns.L("WCL 热门天赋", "WCL popular"), 150, 20, function(self) ns.WclTop1(self) end)
    if p.wclBtn.RegisterForClicks then p.wclBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    p.wclBtn:SetScript("OnClick", function(self, btn) GameTooltip:Hide(); if btn == "RightButton" then ns.ShowWclMenu(self) else ns.WclTop1(self) end end)
    p.wclArrow = ns.Button(p, "▼", 22, 20, function(self) GameTooltip:Hide(); ns.ShowWclMenu(self) end)
    p.wclArrow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT"); GameTooltip:AddLine(ns.L("选别的专精 / 热门 #2 #3 / 推荐", "Other spec / #2 #3 / recommended"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.wclArrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.wclBtn:SetPoint("TOPRIGHT", -10, -7)
    if p._sub then p._sub:SetPoint("RIGHT", p.wclBtn, "LEFT", -8, 0) end
    p.wclBtn:SetScript("OnEnter", function(self) ns.WclTip(self, "ANCHOR_BOTTOMLEFT") end)
    p.wclBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 职业按钮
    p.classBtns = ns.ClassBar(p, -38, function(cls) showClass(cls) end)

    -- 三棵树
    p.trees = {}
    local colW = 4 * CELL + 3 * GAP + 16
    for ti = 1, 3 do
        local col = CreateFrame("Frame", nil, p)
        col:SetSize(colW, 24 + 7 * (CELL + 8))
        col:SetPoint("TOPLEFT", 6 + (ti - 1) * (colW + 4), -66)
        local bg = col:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03)
        local band = col:CreateTexture(nil, "BACKGROUND", nil, 1)
        band:SetPoint("TOPLEFT"); band:SetPoint("TOPRIGHT"); band:SetHeight(20); band:SetColorTexture(1, 0.82, 0, 0.08)
        col.head = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        col.head:SetPoint("TOP", 0, -4)
        col.cells = {}
        for i = 1, 24 do
            local c = CreateFrame("Button", nil, col)
            c:SetSize(CELL, CELL)
            c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            c.edge = c:CreateTexture(nil, "BACKGROUND", nil, -1); c.edge:SetAllPoints()
            local inner = c:CreateTexture(nil, "BACKGROUND", nil, 0)
            inner:SetPoint("TOPLEFT", 2, -2); inner:SetPoint("BOTTOMRIGHT", -2, 2); inner:SetColorTexture(0, 0, 0, 1)
            -- 改动类型小圆点（新增绿 / 改动金 / 换位蓝；没改的不显示）
            -- 小方块 = 黑底 + 色块（⛔别用 ● 字符 / 不确定存在的贴图：英文字体里 ● 是方框）
            c.dotbg = c:CreateTexture(nil, "OVERLAY", nil, 3); c.dotbg:SetSize(10, 10); c.dotbg:SetPoint("TOPLEFT", 0, 0)
            c.dotbg:SetColorTexture(0, 0, 0, 1)
            c.dot = c:CreateTexture(nil, "OVERLAY", nil, 4); c.dot:SetSize(8, 8); c.dot:SetPoint("CENTER", c.dotbg)
            c.dot:SetColorTexture(1, 1, 1, 1); c.dot:Hide()
            c.icon = c:CreateTexture(nil, "ARTWORK")
            c.icon:SetPoint("TOPLEFT", 2, -2); c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local rb = c:CreateTexture(nil, "OVERLAY", nil, 1)
            rb:SetColorTexture(0, 0, 0, 0.75)
            rb:SetPoint("BOTTOMRIGHT", -2, 2); rb:SetSize(24, 12); c.rb = rb
            c.lvbg = c:CreateTexture(nil, "OVERLAY", nil, 1); c.lvbg:SetColorTexture(0, 0, 0, 0.8)
            c.lvbg:SetPoint("TOPRIGHT", -2, -2); c.lvbg:SetSize(18, 12); c.lvbg:Hide()
            c.lv = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.lv:SetDrawLayer("OVERLAY", 2)
            c.lv:SetPoint("CENTER", c.lvbg, "CENTER", 0, 0); c.lv:SetTextColor(0.4, 1, 0.4)
            c.rank = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            c.rank:SetDrawLayer("OVERLAY", 2)
            c.rank:SetPoint("BOTTOMRIGHT", -3, 2)
            local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
            c:SetScript("OnClick", click)
            c:SetScript("OnEnter", cellTooltip)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            c:Hide()
            col.cells[i] = c
        end
        p.trees[ti] = col
    end

    -- 底部：码 + 操作
    p.info = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.info:SetPoint("BOTTOMLEFT", 10, 34)
    -- 左上角小圆点的图例
    local lg = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lg:SetPoint("BOTTOMRIGHT", -12, 36)
    local function dotTxt(c, txt)
        return string.format("|TInterface\\Buttons\\WHITE8X8:9:9:0:0:8:8:0:8:0:8:%d:%d:%d|t %s",
            c[1] * 255, c[2] * 255, c[3] * 255, txt)
    end
    lg:SetText(dotTxt(ST_COLOR.new, ns.L("《无限》新增", "New")) .. "   " .. dotTxt(ST_COLOR.changed, ns.L("改动", "Changed"))
        .. "   " .. dotTxt(ST_COLOR.moved, ns.L("换位置", "Moved")))
    p.planWin = ns.Button(p, "", 118, 20, function()
        if ns.ShowTalentPlan then ns.ShowTalentPlan(ns.TalentPlanState() ~= "shown", true) end
        planWinBtn()
    end)
    p.planWin:SetPoint("RIGHT", lg, "LEFT", -12, 0); p.planWin:Hide()
    -- 10-11 玩家「我是熊 D，推荐的是野德（猫），怎么换？」：推荐方案切换（每职业多套，按角色记住）
    p.buildBtn = ns.Button(p, "", 170, 20, function(self) ns.ShowBuildMenu(self) end)
    p.buildBtn:SetPoint("LEFT", p.info, "RIGHT", 10, 0)
    p.buildBtn:SetScript("OnEnter", function(self)   -- 名字可能被截 → 悬停看全
        local L = S.cls and ns.DefaultBuilds(S.cls) or {}
        local cur = S.cls and ns.DefaultBuildKey(S.cls)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.L("推荐升级加点", "Recommended leveling build"), 1, 0.82, 0)
        for _, b in ipairs(L) do
            local rn = ns.ROLE_NAME[b.role or ""]
            GameTooltip:AddLine((b.key == cur and "|cffffd100" or "|cffcccccc") .. ns.L(b.specCn or b.spec or "", b.spec or "")
                .. (rn and (" · " .. ns.L(rn[1], rn[2])) or "") .. "|r", 1, 1, 1)
        end
        GameTooltip:AddLine(#L > 1 and ns.L("点击切换方案（按角色记住）", "Click to switch (remembered per character)")
            or ns.L("这个职业目前只有一套", "Only one build for this class so far"), 0.2, 1, 0.6, true)
        GameTooltip:AddLine(ns.L("来源 wowforeverbuilds.com，《无限》Beta 树里没有的天赋已自动调整", "From wowforeverbuilds.com, adjusted to the Forever beta tree"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    p.buildBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.code = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.code:SetPoint("LEFT", p.info, "RIGHT", 14, 0)
    p.code:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    p.code:SetJustifyH("LEFT"); p.code:SetWordWrap(false)
    -- 10-07 用户：右下那串配点码看着像乱码 → 不显示，要用就点「复制配点码」
    p.code:Hide()

    local x = 8
    local function btn(text, w, fn)
        local b = ns.Button(p, text, w, 22, fn)
        b:SetPoint("BOTTOMLEFT", x, 6)
        x = x + w + 4
        return b
    end
    btn(ns.L("复制配点码", "Copy code"), 92, function()
        ns.ShowBox(ns.L("配点码", "Build code"), ns.L("Ctrl+C 复制，粘到小程序 / 网站模拟器", "Ctrl+C, paste into the site / mini program"), ns.TalentCodeFromSim())
    end)
    btn(ns.L("导入", "Import"), 60, function()
        ns.ShowBox(ns.L("导入配点码", "Import build"), ns.L("粘贴 GIF2 开头的码", "Paste a GIF2 code"), "", ns.LoadSimCode, ns.L("导入", "Import"))
    end)
    btn(ns.L("读我的天赋", "Read mine"), 88, function()
        local code = ns.CurrentTalentCode and ns.CurrentTalentCode()
        if code then ns.LoadSimCode(code) end
    end)
    p.learn = btn(ns.L("按这套逐点学", "Learn this build"), 112, function()
        if ns.ApplyTalentCode(ns.TalentCodeFromSim()) then ns.ToggleMain() end
    end)
    btn(ns.L("热门配点", "Popular"), 76, function() ns.ShowPopBuilds() end)
    btn(ns.L("发到手机", "To phone"), 76, function()
        local code = ns.TalentCodeFromSim()
        if code and total() > 0 then
            ns.ShowQR(ns.L("把这套配点发到手机", "Send this build to your phone"),
                ns.L("微信扫码：在小程序天赋模拟器里打开", "Scan with WeChat to open it in the simulator"),
                "https://gearinsight.cn/fv/t?c=" .. code, "M")
        end
    end)
    btn(ns.L("默认路线", "Default"), 76, function() if S.cls then S.noAuto[S.cls] = nil; loadDefault(S.cls) end end)
    btn(ns.L("清空", "Reset"), 56, function() if S.cls then S.noAuto[S.cls] = true; setClass(S.cls) end end)

    showClass((ns.db.ui and ns.db.ui.simCls) or myClass())
end

-- 推荐方案菜单：一行一套（名字 · 定位），点了就切过去并载入它的路线
local menu
function ns.ShowBuildMenu(anchor)
    if not S.cls then return end
    local L = ns.DefaultBuilds(S.cls)
    if #L <= 1 then return end
    if not menu then
        menu = CreateFrame("Frame", "GearInsightForeverBuildMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
        if menu.SetBackdrop then
            menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            menu:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
        end
        menu.rows = {}
        menu:EnableMouse(true)
        menu:SetScript("OnHide", function() end)
    end
    for _, r in ipairs(menu.rows) do r:Hide() end
    local cur = ns.DefaultBuildKey(S.cls)
    for k, b in ipairs(L) do
        local r = menu.rows[k]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetSize(200, 22)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.t:SetPoint("LEFT", 8, 0); r.t:SetPoint("RIGHT", -6, 0)
            r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.18)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnEnter", function(self)
                local bb = self.b
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.L(bb.specCn or bb.spec or "", bb.spec or ""), 1, 0.82, 0)
                if bb.url and bb.url ~= "" then GameTooltip:AddLine(bb.url, 0.6, 0.6, 0.6, true) end
                if (bb.adjusted or 0) > 0 then
                    GameTooltip:AddLine(string.format(ns.L("按《无限》Beta 天赋树调整了 %d 处", "%d adjustments for the Forever beta tree"), bb.adjusted), 0.8, 0.8, 0.8)
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            menu.rows[k] = r
        end
        r.b = b
        local rn = ns.ROLE_NAME[b.role or ""]
        r.t:SetText(ns.L(b.specCn or b.spec or "", b.spec or "") .. (rn and ("  |cff9a9a9a" .. ns.L(rn[1], rn[2]) .. "|r") or ""))
        r.sel:SetShown(b.key == cur)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (k - 1) * 22)
        r:SetScript("OnClick", function()
            ns.SetDefaultBuild(S.cls, b.key)
            S.noAuto[S.cls] = nil
            loadDefault(S.cls)
            menu:Hide()
            if ns.RefreshPlan then pcall(ns.RefreshPlan) end
        end)
        r:Show()
    end
    menu:SetSize(208, 8 + #L * 22)
    menu:ClearAllPoints(); menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    menu:SetShown(not menu:IsShown() or menu._for ~= S.cls)
    menu._for = S.cls
end

ns._BuildMenu = function() return menu end   -- 测试用

-- 11-23 重构 P2「WCL 热门」菜单：本职业每个专精一组（标题 = 专精 · 样本），下面「推荐」+ 热门前 3（占比 · 人数），点一行载入模拟器
local wmenu
local function wclRows(cls)
    local rows = {}
    local mt = (cls == myClass()) and ns.MyMainTree and ns.MyMainTree() or nil
    for _, s in ipairs(ns.TalentWclSpecs(cls) or {}) do
        local name = ns.L(s.specCn, s.spec)
        rows[#rows + 1] = { head = true, text = ((mt and s.tree == mt) and "|cffffd100" or "|cffcfcfcf") .. name .. "|r  |cff9a9a9a"
            .. string.format(ns.L("样本 %d 人", "%d players"), s.n) .. "|r" }
        -- 11-23 用户截图「默认直接换热门1」：热门 #1 排第一，推荐（逐格选取率）挪到最后
        for k, b in ipairs(s.top) do
            rows[#rows + 1] = { code = b.code, label = name .. "#" .. k, spec = s,
                text = string.format(ns.L("热门 #%d  %.1f%%", "Popular #%d  %.1f%%"), k, s.n > 0 and 100 * b.n / s.n or 0)
                    .. "  |cff9a9a9a" .. string.format(ns.L("%d 人在用", "%d players"), b.n) .. "|r" }
        end
        local recPct = s.n > 0 and (100 * s.recN / s.n) or 0
        rows[#rows + 1] = { code = s.rec, label = name .. ns.L("·推荐", " rec"), spec = s, rec = true,
            text = ns.L("推荐（逐格选取率）", "Recommended (per-talent)") .. "  |cff9a9a9a"
                .. (s.diff == 0 and ns.L("= 最热门", "= most popular") or string.format(ns.L("和最热门差 %d 点", "%d pts from top"), s.diff))
                .. (s.recN > 0 and string.format(ns.L(" · 同款 %.1f%%", " · %.1f%% exact"), recPct) or "") .. "|r" }
    end
    return rows
end
ns._WclRows = wclRows   -- 测试用
-- WCL 按钮悬停提示（天赋页右上角的按钮、游戏天赋窗上的「GI WCL 天赋」共用）
function ns.WclTip(self, where)
    local D, T = ns.TalentWclData or {}, GameTooltip
    T:SetOwner(self, where)
    T:AddLine(ns.L("GI · WCL 热门天赋（60 级）", "GI · WCL popular builds (level 60)"), 1, 0.82, 0)
    T:AddLine(string.format(ns.L("数据来自 WCL 全球 60 级排行：%s 至 %s\n共 %d 份日志，只算天赋点正好 51 的角色",
        "WCL level-60 rankings worldwide: %s-%s, %d logs, exactly 51 points"),
        tostring(D.from or "?"), tostring(D.to or "?"), D.reports or 0), 1, 1, 1, false)   -- 11-23 截图：自动折行时提示框太窄、一句折成四五行 → 手动换行、不自动折
    T:AddLine(ns.L("左键：在 GI 天赋页直接载入热门 #1（按你天赋点最多那系的专精）\n右键或旁边「▼」：选别的专精 / 热门 #2 #3 / 推荐（逐格选取率）",
        "Left: Popular #1 for your main spec\nRight: other spec / #2 #3 / recommended"), 0.2, 1, 0.6, false)
    T:AddLine(ns.L("只是在 GI 里模拟显示，不会改你的天赋，要自己去点", "Simulator only - your talents are not changed"), 1, 0.6, 0.3, false)
    T:Show()
end
-- 11-23 用户「默认直接换热门1」：按钮左键 = 直接载入热门 #1（看自己职业 = 我天赋点最多那系的专精；看别的职业 = 样本最多的专精）；右键 = 菜单
function ns.WclTop1Spec(cls)
    local specs = cls and ns.TalentWclSpecs(cls)
    if not specs then return nil end
    local mt = (cls == myClass()) and ns.MyMainTree and ns.MyMainTree() or nil
    local pick
    for _, s in ipairs(specs) do if mt and s.tree == mt and s.top[1] then pick = s end end
    if not pick then for _, s in ipairs(specs) do if s.top[1] and (not pick or s.n > pick.n) then pick = s end end end
    return pick
end
-- cls 不传 = 天赋页当前看的职业；游戏天赋窗上的「GI WCL 天赋」按钮传自己的职业
function ns.WclTop1(anchor, cls)
    cls = cls or S.cls
    local s = ns.WclTop1Spec(cls)
    if not s then return ns.ShowWclMenu(anchor, cls) end
    return ns.LoadWclSim(cls, s.top[1].code, ns.L(s.specCn, s.spec) .. "#1")
end

function ns.ShowWclMenu(anchor, cls)
    cls = cls or S.cls
    if not cls or not ns.TalentWclSpecs(cls) then return end
    if not wmenu then
        wmenu = CreateFrame("Frame", "GearInsightForeverWclMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        wmenu:SetFrameStrata("DIALOG"); wmenu:SetClampedToScreen(true); wmenu:EnableMouse(true)
        if wmenu.SetBackdrop then
            wmenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            wmenu:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
        end
        wmenu.rows = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverWclMenu") end
    end
    for _, r in ipairs(wmenu.rows) do r:Hide() end
    local list = wclRows(cls)
    for k, it in ipairs(list) do
        local r = wmenu.rows[k]
        if not r then
            r = CreateFrame("Button", nil, wmenu)
            r:SetSize(300, 20)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 8, 0); r.t:SetPoint("RIGHT", -6, 0)
            r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            wmenu.rows[k] = r
        end
        r.it = it
        r.t:SetText(ns.EnSafe((it.head and "" or "    ") .. it.text))
        r:EnableMouse(not it.head)
        r:SetScript("OnClick", not it.head and function(self)
            if ns.LoadWclSim(wmenu._for, self.it.code, self.it.label) then wmenu:Hide() end
        end or nil)
        r:SetScript("OnEnter", not it.head and function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.it.label, 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("点一下载入模拟器（不改你的天赋）", "Click to load into the simulator (your talents are not changed)"), 0.2, 1, 0.6, true)
            if self.it.rec then
                GameTooltip:AddLine(ns.L("每个天赋格按「点了的人数比例」从高到低挑，守行解锁和前置，点满 51 点", "Each talent taken by share of players, highest first, within row and prerequisite rules, filled to 51"), 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end or nil)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (k - 1) * 20)
        r:Show()
    end
    wmenu:SetSize(308, 8 + #list * 20)
    wmenu:ClearAllPoints(); wmenu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    wmenu:SetShown(not wmenu:IsShown() or wmenu._for ~= cls)
    wmenu._for = cls
end
ns._WclMenu = function() return wmenu end   -- 测试用

-- 11-23 用户截图游戏天赋窗「GI WCL天赋可以直接挂到这里吗放到上面天赋模拟旁边」：
--   天赋窗（Talents.lua TF_NAMES 那几个，ns.HookTalentFrame 挂钩时顺带调这里）顶上「天赋模拟」页签右边挂「GI WCL 天赋」。
--   页签是别的插件加的、可能晚于窗口建：每次窗口显示都重新找一次（窗口下层控件里文字是「天赋模拟」的那个控件），找不到就放窗口左上（头像右边）。
--   ⛔ 普通按钮（不是安全按钮）：只打开 GI 天赋页、载入模拟器，不碰玩家天赋；不往别人的框体上写字段（按钮记在自己的弱表里）
-- 11-23 用户截图：按钮落在回退位置（左上，压在「主要」页签上方）—— 旧版深度优先搜、上限 800 个节点，
--   天赋窗里三棵树几十个天赋格（每格好几个贴图）先把额度吃光，根本没搜到顶上的页签。
--   现在：广度优先（页签离窗口近）、上限 4000；文字先剥 |T..|t 图标 / |A..|a / |c 颜色 / |r / 空白再 find（子串，不是前缀）；
--   认 Button:GetText 和所有 FontString；窗口显示后 0.1 / 0.5 / 1.5 秒重找。
--   ⛔ 别对中文 :lower()（按字节 tolower 会改坏 UTF-8）
local function isSim(o)
    local ok, t = pcall(o.GetText, o)
    if not ok or type(t) ~= "string" or (issecretvalue and issecretvalue(t)) then return end
    t = t:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", "")
    return t:find("天赋模拟", 1, true) or t:find("天賦模擬", 1, true) or t:find("TalentSim", 1, true)
end
local function typ(o) local ok, t = pcall(o.GetObjectType, o); return ok and type(t) == "string" and t or "" end
-- 这个框自己或它的文字 region 是「天赋模拟」→ 返回页签（文字直接挂在窗口上时返回那个 FontString；文字在页签按钮的子框上 → 返回页签按钮）
local function simIn(f, tf)
    local hit = f ~= tf and isSim(f) and f
    if not hit then
        local rs = { pcall(f.GetRegions, f) }
        for i = 2, #rs do if isSim(rs[i]) then hit = f ~= tf and f or rs[i]; break end end
    end
    local ok, par = pcall(f.GetParent, f)
    if hit == f and ok and type(par) == "table" and par ~= tf and typ(par):find("Button") and not typ(f):find("Button") then return par end
    return hit
end
local function findSim(tf)
    local q, h = { tf }, 1
    while q[h] and h <= 4000 do
        local f = q[h]; q[h] = false; h = h + 1
        local hit = simIn(f, tf)
        if hit then return hit end
        local cs = { pcall(f.GetChildren, f) }
        for i = 2, #cs do q[#q + 1] = cs[i] end
    end
end
local simTabs = setmetatable({}, { __mode = "kv" })   -- [窗口] = 找到的页签（还是那个文字就不重找）
local function placeWclBtn(b, tf)
    local tab = simTabs[tf]
    if not (tab and simIn(tab, tf)) then tab = findSim(tf); simTabs[tf] = tab end
    local _, h = pcall(tab and tab.GetHeight, tab)
    local _, lv = pcall(tab and tab.GetFrameLevel, tab)
    h = tonumber(h) or 0
    local bh = tab and h >= 18 and h <= 40 and h or (tab and 24 or 20)
    local _, fs = pcall(b.GetFontString, b)
    local _, tw = pcall(fs and fs.GetStringWidth, fs)
    tw = tonumber(tw) or 0
    b:SetSize(math.floor(((tw > 0) and tw or 84) + 2 * 16 + 0.5), bh)   -- 字宽 + 左右 16 padding（和页签同量级）
    b:ClearAllPoints()
    if tab then b:SetPoint("LEFT", tab, "RIGHT", 8, 0)
    else   -- 找不到页签：放标题栏右侧（「天赋」标题右边、关闭按钮左边），⛔ 别再压在页签上方
        local okn, n = pcall(tf.GetName, tf)
        local close = rawget(tf, "CloseButton") or (okn and type(n) == "string" and _G[n .. "CloseButton"])
        if type(close) == "table" then b:SetPoint("RIGHT", close, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", tf, "TOPRIGHT", -34, -3) end
    end
    b:SetFrameLevel(math.max(tonumber(tf:GetFrameLevel()) or 0, tonumber(lv) or 0) + 3)
    b:SetShown(ns.TalentWclSpecs(myClass()) ~= nil)   -- 数据没进包（HOLD）= 不显示
    return tab
end
local wclBtns = setmetatable({}, { __mode = "k" })
function ns.AttachWclTalentBtn(tf)
    if type(tf) ~= "table" or not tf.HookScript then return end
    local b = wclBtns[tf]
    if not b then
        -- 外观：和「天赋模拟」那个高亮页签一个样子 —— 主插件扁平按钮的「选中」态（暗金底 + 金边 + 亮金字 + 底下金线，悬停淡金光），不用 GI 灰底小按钮
        b = ns.Button(tf, ns.L("GI · WCL 天赋", "GI · WCL talents"), 110, 24)
        if ns.SegSelect then ns.SegSelect(b, true) end
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn)
            if ns.CurrentPage() then ns.ShowPage("talent") else ns.ToggleMain("talent") end   -- 打开 GI 主界面 职业 → 天赋
            if btn == "RightButton" then ns.ShowWclMenu(self, myClass()) else ns.WclTop1(self, myClass()) end
        end)
        b:SetScript("OnEnter", function(self) ns.WclTip(self, "ANCHOR_BOTTOMRIGHT") end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        wclBtns[tf] = b
        -- 别的插件的页签可能窗口显示时才建 / 才 SetText：当场摆一次，0.1 / 0.5 / 1.5 秒后再摆
        local function place() pcall(placeWclBtn, b, tf) end
        tf:HookScript("OnShow", function()
            place()
            for _, d in ipairs({ 0.1, 0.5, 1.5 }) do C_Timer.After(d, place) end
        end)
    end
    pcall(placeWclBtn, b, tf)
    return b
end
ns._TalentPage = function() return page end   -- 测试用
ns._sim, ns._simClick = S, click
ns.RegisterPage({ key = "talent", order = 1, title = ns.L("天赋", "Talents"), build = build, refresh = refresh })

-- 11-05 天赋页开着时点了天赋：推荐方案跟着投点最多的系换（refresh 里判断），不用关了再开
do
    local ev = CreateFrame("Frame")
    for _, e in ipairs(ns.TALENT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function() if page and page.IsShown and page:IsShown() then pcall(refresh) end end)
end
