-- 天赋页：三棵树模拟加点（与小程序 / 网站模拟器同一份数据、同一套 GIF1 配点码）
-- 左键 +1，右键 -1；行解锁 = 每 5 点一行；前置天赋要点满；总数 ≤ 51
-- 颜色：绿=《无限》新增  黄=改动  蓝=换位置  灰=没变
local _, ns = ...

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local CLASS_COLOR = { Warrior = "c79c6e", Paladin = "f58cba", Hunter = "abd473", Rogue = "fff569", Priest = "ffffff",
    Shaman = "0070de", Mage = "69ccf0", Warlock = "9482c9", Druid = "ff7d0a" }
local ST_COLOR = { new = { 0.2, 1, 0.4 }, changed = { 1, 0.82, 0.2 }, moved = { 0.4, 0.7, 1 }, same = { 0.45, 0.45, 0.45 } }
local CELL, GAP = 40, 12

local S = { cls = nil, pts = nil, path = nil, plan = nil, noAuto = {} }
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
    return "GIF1." .. S.cls .. "." .. table.concat(parts, "-")
end

local page
local function refresh()
    if not page or not S.cls then return end
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
            page.buildBtn:SetText((on and "|cffffd100" or "") .. ns.L("推荐：", "Build: ") .. ns.L(dp.specCn or dp.spec or "", dp.spec or "") .. (on and "|r" or ""))
        end
    end
    page.code:SetText(ns.TalentCodeFromSim() or "")
    page.learn:SetEnabled(S.cls == myClass() and n > 0)
end
ns.RefreshTalentSim = refresh

local function setClass(cls)
    S.cls = cls
    S.pts = blank(cls)
    S.path, S.plan = nil, nil
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
    if S.pts[ti][i] ~= old then S.path = nil end   -- 自己动了点：默认路线的顺序不作数了，不再标第几级
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
    -- 10-11 玩家「我是熊 D，推荐的是野德（猫），怎么换？」：推荐方案切换（每职业多套，按角色记住）
    p.buildBtn = ns.Button(p, "", 150, 20, function(self) ns.ShowBuildMenu(self) end)
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
        ns.ShowBox(ns.L("导入配点码", "Import build"), ns.L("粘贴 GIF1 开头的码", "Paste a GIF1 code"), "", ns.LoadSimCode, ns.L("导入", "Import"))
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
ns._sim, ns._simClick = S, click
ns.RegisterPage({ key = "talent", order = 1, title = ns.L("天赋", "Talents"), build = build, refresh = refresh })
