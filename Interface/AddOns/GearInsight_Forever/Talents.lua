-- 配点码导入：GIF2.<职业>.<树1>-<树2>-<树3>，每位数字 = 该树第 i 个天赋的点数
-- ⛔ 11-05 GI-187：开服时天赋树大改（数据按开服客户端 70790 的 Trait 表重做），三端约定新树用 GIF2；
--   GIF1 = 开服前的树，同一串数字在新树上是另一套配点 → 一律提示「开服前的配点码」不套用；存档里旧树的计划（没有 v=2）自动作废
-- 天赋顺序 = Data.lua 里的顺序 = 小程序 / 网站模拟器的顺序（⛔Data.lua 生成时别排序）
-- 游戏里按「行 + 列」对上天赋（名字只用来核对），从最上面的行开始一点一点学
local _, ns = ...

local function classKey()
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 一棵树（ns.Data.talents[cls][ti]）里按 行:列 找格子 → index, cell（ns.PlanTalentSteps 查前置用）
local function findAtTree(tree, r, c)
    for i, t in ipairs(tree.t) do
        if t.r == r and t.col == c then return i, t end
    end
end

-- 解析配点码 → { cls=, pts={ {..}, {..}, {..} } } 或 nil, 原因
function ns.ParseTalentCode(code)
    code = tostring(code or ""):gsub("%s+", "")
    if code:match("^GIF1%.") then
        return nil, ns.L("这是开服前的配点码，天赋树已经改了，请到小程序或网站重新生成（GIF2 开头）",
            "This is a pre-launch build code and the talent trees have changed; make a new one (starts with GIF2)")
    end
    local cls, body = code:match("^GIF2%.(%a+)%.(.+)$")
    if not cls then return nil, ns.L("不是配点码（应以 GIF2. 开头）", "Not a build code (should start with GIF2.)") end
    local trees = ns.Data.talents[cls]
    if not trees then return nil, ns.L("不认识的职业：", "Unknown class: ") .. cls end
    local parts = {}
    for p in (body .. "-"):gmatch("([^%-|]*)[%-|]") do parts[#parts + 1] = p end
    local pts, total = {}, 0
    for ti, tr in ipairs(trees) do
        local s = parts[ti] or ""
        pts[ti] = {}
        for i, t in ipairs(tr.t) do
            local v = tonumber(s:sub(i, i)) or 0
            if v > t.m then v = t.m end
            pts[ti][i] = v
            total = total + v
        end
    end
    if total > 51 then return nil, ns.L("点数超过 51", "More than 51 points") end
    return { cls = cls, pts = pts, total = total, v = 2 }
end

-- 游戏里的天赋格：按 行:列 建索引
local function gameIndex(tab)
    local idx = {}
    if not GetTalentInfo then   -- 《无限》：C_Traits 读法（没有格子序号 i，绿框按天赋面板按钮的法术名对）
        local cells = ns.TraitCells and ns.TraitCells()
        for key, c in pairs(cells and cells[tab] or {}) do
            idx[key] = { name = c.name, rank = c.rank, max = c.max, node = c.node }
        end
        return idx
    end
    local n = GetNumTalents and GetNumTalents(tab) or 0
    for i = 1, n do
        local name, _, tier, col, rank, maxRank = GetTalentInfo(tab, i)
        if tier then idx[tier .. ":" .. col] = { i = i, name = name, rank = rank or 0, max = maxRank or 0 } end
    end
    return idx
end

-- 下一步要学的天赋：从最上面一行开始；前置没点满的先跳过
function ns.NextTalentStep(plan)
    local trees = ns.Data.talents[plan.cls]
    local best
    for ti, tr in ipairs(trees) do
        local g = gameIndex(ti)
        for i, t in ipairs(tr.t) do
            local want = plan.pts[ti][i]
            local cell = g[t.r .. ":" .. t.col]
            if want > 0 and cell and cell.rank < want then
                local reqOk = true
                if t.rq then
                    local rc = g[t.rq[1] .. ":" .. t.rq[2]]
                    reqOk = rc and rc.rank >= rc.max
                end
                if reqOk and (not best or t.r < best.row) then
                    best = { tab = ti, index = cell.i, row = t.r, col = t.col, tree = ns.L(tr.c, tr.n), name = ns.L(t.c, t.n), cur = cell.rank, want = want,
                             gameName = cell.name }
                end
            end
        end
    end
    return best
end

-- 计划和游戏里对不上的格子（《无限》改树后数据没跟上时会出现）
function ns.CheckPlanAgainstGame(plan)
    local bad = {}
    for ti, tr in ipairs(ns.Data.talents[plan.cls]) do
        local g = gameIndex(ti)
        for i, t in ipairs(tr.t) do
            if plan.pts[ti][i] > 0 then
                local cell = g[t.r .. ":" .. t.col]
                if not cell then
                    bad[#bad + 1] = ns.L(t.c, t.n)
                elseif cell.name and cell.name ~= t.c and cell.name ~= t.n then
                    bad[#bad + 1] = ns.L(t.c, t.n) .. " / " .. cell.name
                end
            end
        end
    end
    return bad
end

-- 升级规划用：从「当前实际已点」一路模拟到 targetLevel 能点满的那一点，按树序→行→列找下一个可点格子
-- 每一点对应等级 9+N（第 N 个点在 10 级拿到，51 点在 60 级拿满——和 unlocked 公式 treeSum>=(行-1)*5 的算法完全一致）
-- 返回 steps 数组；nil, "noplan" 没导入配点计划；nil, "conflict" 当前已点和计划对不上（多点了计划里没有的）
-- baseLevel 可选：升级规划页「锁定当前等级」时传进来的冻结基准，不传就用玩家实时等级
-- （和 avail 标『现在就能点』用同一把尺子，锁定后不会因为你中途升级而改口）
-- 现在用哪套计划：自己导入的（且是本职业）优先，否则本职业的默认升级加点（DefaultBuilds.lua）
-- 存档里开服前（旧树）导入的计划：作废（同一组点数在新树上是另一套配点）
local function dropOldPlan()
    local p = ns.db and ns.db.talentPlan
    if p and p.v ~= 2 then ns.db.talentPlan = nil end
end
ns.DropOldTalentPlan = dropOldPlan
function ns.ActivePlan()
    dropOldPlan()
    local plan = ns.db.talentPlan
    if plan and plan.cls == classKey() then return plan end
    return ns.DefaultPlan and ns.DefaultPlan(classKey()) or nil
end

function ns.PlanTalentSteps(targetLevel, baseLevel)
    local plan = ns.ActivePlan()
    if not plan then return nil, "noplan" end
    local trees = ns.Data.talents[plan.cls]
    if not trees then return nil, "noplan" end
    local curCode = ns.CurrentTalentCode and classKey() == plan.cls and ns.CurrentTalentCode()
    local cur = curCode and ns.ParseTalentCode(curCode)
    local work, haveNow = {}, 0
    for ti, tr in ipairs(trees) do
        work[ti] = {}
        for i in ipairs(tr.t) do
            local v = cur and (cur.pts[ti][i] or 0) or 0
            if v > (plan.pts[ti][i] or 0) then return nil, "conflict", plan end
            work[ti][i] = v
            haveNow = haveNow + v
        end
    end
    local wantTotal = math.min(plan.total or 0, math.min(51, math.max(0, targetLevel - 9)))
    if wantTotal <= haveNow then return {}, nil, plan end
    local steps, curLv = {}, baseLevel or (UnitLevel and UnitLevel("player")) or 0
    -- 带逐点顺序的计划（默认升级加点 = 攻略顺序）：按顺序走，已经点过的那几点跳过
    if plan.order then
        local used, k = {}, haveNow
        for _, o in ipairs(plan.order) do
            local ti, i = o[1], o[2]
            used[ti] = used[ti] or {}
            used[ti][i] = (used[ti][i] or 0) + 1
            if used[ti][i] > work[ti][i] then
                k = k + 1
                if k > wantTotal then break end
                local tr, t = trees[ti], trees[ti].t[i]
                local lv = 9 + k
                steps[#steps + 1] = { lv = lv, avail = lv <= curLv, tree = ns.L(tr.c, tr.n), name = ns.L(t.c, t.n),
                    d = ns.L(t.d, t.dEn), icon = t.i, tab = ti, row = t.r, col = t.col, rank = used[ti][i], rankMax = t.m }
            end
        end
        return steps, nil, plan
    end
    for n = haveNow + 1, wantTotal do
        local placed = false
        for ti, tr in ipairs(trees) do
            if placed then break end
            local spentInTree = 0
            for i in ipairs(tr.t) do spentInTree = spentInTree + work[ti][i] end
            for i, t in ipairs(tr.t) do
                local want = plan.pts[ti][i] or 0
                if work[ti][i] < want then
                    local rowOk = spentInTree >= (t.r - 1) * 5
                    local reqOk = true
                    if t.rq then
                        local j, rt = findAtTree(trees[ti], t.rq[1], t.rq[2])
                        reqOk = j and work[ti][j] >= rt.m
                    end
                    if rowOk and reqOk then
                        work[ti][i] = work[ti][i] + 1
                        local lv = 9 + n
                        steps[#steps + 1] = { lv = lv, avail = lv <= curLv, tree = ns.L(tr.c, tr.n), name = ns.L(t.c, t.n),
                            d = ns.L(t.d, t.dEn), icon = t.i, tab = ti, row = t.r, col = t.col, rank = work[ti][i], rankMax = t.m }
                        placed = true
                        break
                    end
                end
            end
        end
        if not placed then break end   -- 能通过 ParseTalentCode 的码理论上不会卡在这（行解锁 + 前置都满足），留着保平安
    end
    return steps, nil, plan
end

-- 11-10 用户截图「为啥19级没展示天赋点点哪里」：当前等级那一点已经点了，上面只列没点的 → 本级空着像漏了
-- 第 n 点（等级 9+n）已经点过时，按计划逐点顺序返回那一点（升级规划页标「已点」）；没逐点顺序 / 还没点到 → nil
function ns.PlanSpentStep(n)
    local plan = ns.ActivePlan()
    if not plan or not plan.order or not n or n < 1 then return nil end
    local trees = ns.Data.talents[plan.cls]
    local curCode = trees and ns.CurrentTalentCode and classKey() == plan.cls and ns.CurrentTalentCode()
    local cur = curCode and ns.ParseTalentCode(curCode)
    if not cur then return nil end
    local used, k = {}, 0
    for _, o in ipairs(plan.order) do
        local ti, i = o[1], o[2]
        used[ti] = used[ti] or {}
        used[ti][i] = (used[ti][i] or 0) + 1
        if used[ti][i] <= ((cur.pts[ti] or {})[i] or 0) then
            k = k + 1
            if k == n then
                local tr, t = trees[ti], trees[ti].t[i]
                return { lv = 9 + n, done = true, tree = ns.L(tr.c, tr.n), name = ns.L(t.c, t.n),
                    d = ns.L(t.d, t.dEn), icon = t.i, tab = ti, row = t.r, col = t.col, rank = used[ti][i], rankMax = t.m }
            end
        end
    end
    return nil
end

local panel
local function updatePanel()
    dropOldPlan()
    if not panel or not panel:IsShown() or not ns.db.talentPlan then return end
    local plan = ns.db.talentPlan
    local unspent = ns.UnspentTalentPoints and ns.UnspentTalentPoints() or 0
    local step = ns.NextTalentStep(plan)
    local lines = {}
    for ti, tr in ipairs(ns.Data.talents[plan.cls]) do
        local n = 0
        for i = 1, #tr.t do n = n + plan.pts[ti][i] end
        lines[#lines + 1] = ns.L(tr.c, tr.n) .. " " .. n
    end
    -- 10-07 用户截图：一行塞「三系 + 未用点数」折成两行，第二行「已点完」被压到按钮底下 → 两行分开 + 高度跟着字走
    local head = "|cffffd100" .. ns.L("天赋计划", "Talent plan") .. "|r  |cffaaaaaa" .. table.concat(lines, " / ") .. "|r"
    local status
    if step then
        status = ns.L("下一个：", "Next: ") .. "|cffffd100" .. step.name .. "|r " .. step.cur .. " → " .. step.want
            .. (unspent > 0 and ("　|cff33ff99" .. ns.L("可用点数 ", "unspent ") .. unspent .. "|r")
                or ("　|cff888888" .. ns.L("升级后再点", "level up first") .. "|r"))
        panel.learn:Show()
        panel.learn:SetEnabled(unspent > 0 and not InCombatLockdown())
        panel.clear:ClearAllPoints(); panel.clear:SetPoint("LEFT", panel.learn, "RIGHT", 6, 0)
    else
        status = "|cff33ff99" .. ns.L("已按配点码点完", "Build complete") .. "|r"
        panel.learn:Hide()
        panel.clear:ClearAllPoints(); panel.clear:SetPoint("BOTTOMLEFT", 10, 8)
    end
    panel.text:SetText(ns.EnSafe(head .. "\n" .. status))
    panel:SetHeight(math.max(74, (panel.text:GetStringHeight() or 28) + 50))
end

local function buildPanel()
    local f = CreateFrame("Frame", "GearInsightForeverTalentPlan", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(360, 74); f:SetPoint("TOP", 0, -140)   -- 宽度装得下 指给我看 / 放弃计划 / 发到手机 三个按钮
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.8)
    end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 10, -10); f.text:SetPoint("RIGHT", -28, 0); f.text:SetJustifyH("LEFT"); f.text:SetSpacing(4)
    f.learn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.learn:SetSize(110, 22); f.learn:SetPoint("BOTTOMLEFT", 10, 8)
    f.learn:SetText(ns.L("指给我看", "Show me"))
    -- ⛔ 10-07 国服 Beta：插件调 LearnTalent 弹「GearInsight_Forever 已被禁用，该功能只对暴雪的 UI 开放」——
    --    学天赋是受保护操作，只能玩家自己点。这里只在天赋面板上给下一个要点的格子套绿框（我们自己的框，不改暴雪面板）
    f.learn:SetScript("OnClick", function()
        local step = ns.NextTalentStep(ns.db.talentPlan)
        if step then
            ns.Print(ns.EnSafe(ns.L("按 N 打开天赋面板，在「", "Open talents (N): ") .. step.tree .. ns.L("」第 ", " row ") .. step.row
                .. ns.L(" 行第 ", ", col ") .. step.col .. ns.L(" 列点「", ": ") .. step.name .. ns.L("」（已套绿框）", " (highlighted)")))
            if ns.HighlightTalentStep then ns.HighlightTalentStep() end
        end
        C_Timer.After(0.3, updatePanel)
    end)
    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(90, 22); clear:SetPoint("LEFT", f.learn, "RIGHT", 6, 0); f.clear = clear
    local qr = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    qr:SetSize(80, 22); qr:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    qr:SetText(ns.L("发到手机", "To phone"))
    qr:SetScript("OnClick", function() ns.ShowTalentQR() end)
    clear:SetText(ns.L("放弃计划", "Drop plan"))
    clear:SetScript("OnClick", function() ns.db.talentPlan = nil; f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0); close:SetScale(0.8)
    -- 11-09 用户截图「点了x，为啥重载后又出来了」：× 只藏了框，登录 / 重载又按「有计划就出」弹回来 → 记进存档，重新导入 / 点「按这套逐点学」才再出
    close:SetScript("OnClick", function() if ns.db.talentPlan then ns.db.talentPlan.hidden = true end; f:Hide() end)   -- 10-18 战斗中关不掉：原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    for _, e in ipairs(ns.TALENT_EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- ⛔ 原来先 HookScript 再 SetScript：SetScript 会连 hook 一起换掉，点完一点后绿框不跟着走
    f:SetScript("OnEvent", function()
        C_Timer.After(0.2, updatePanel)
        C_Timer.After(0.3, function() if ns.HighlightTalentStep then ns.HighlightTalentStep() end end)
    end)
    f:SetScript("OnShow", updatePanel)
    f:Hide()
    panel = f
    return f
end

function ns.ApplyTalentCode(code)
    local plan, why = ns.ParseTalentCode(code)
    if not plan then ns.Print(why); return false end
    if plan.cls ~= classKey() then
        ns.Print(ns.L("这是", "This build is for ") .. (ns.L(ns.Data.classCn[plan.cls] or plan.cls, plan.cls))
            .. ns.L("的配点码，当前角色职业不同", ", not your class"))
        return false
    end
    local bad = ns.CheckPlanAgainstGame(plan)
    if #bad > 0 then
        ns.Print(ns.L("注意：这几个天赋和游戏里的位置对不上（Beta 可能改树了）：", "Warning, talents not matching the game: ")
            .. table.concat(bad, "、"))
    end
    ns.db.talentPlan = plan   -- 新计划（hidden 不带过来）→ 小窗重新出
    panel = panel or buildPanel()
    panel:Show(); updatePanel()
    ns.Print(ns.L("已导入配点码，共 ", "Build imported, ") .. plan.total .. ns.L(" 点", " points"))
    return true
end

function ns.ImportTalentDialog()
    ns.ShowBox(ns.L("导入配点码", "Import talent build"),
        ns.L("在网站或小程序「无限 · 天赋模拟」里复制 GIF2 开头的码，粘到这里",
            "Copy a GIF2 build code from the GearInsight site or mini program and paste it here"),
        "", ns.ApplyTalentCode, ns.L("导入", "Import"))
end

table.insert(ns.modules, function()
    if ns.db.talentPlan then
        C_Timer.After(2, function()
            if ns.db.talentPlan and ns.db.talentPlan.cls == classKey() and not ns.db.talentPlan.hidden then
                panel = panel or buildPanel(); panel:Show()
            end
        end)
    end
end)

-- ---------- 天赋面板上的绿框（自己的框，锚在暴雪格子上；⛔不调用 / 不改暴雪天赋面板的任何东西）----------
-- 10-16 用户「天赋可以做到点击直接加点吗？打开天赋页然后高亮」：学天赋插件做不到（见上面 10-07 的注释），
--   改成升级规划天赋行的「去点」：打开天赋面板 + 绿框套这一行的天赋；不在那棵树就给页签套绿框。
--   ⛔ 不替玩家切页签：插件改面板状态会污染它，玩家自己点格子那一下也可能被拦（又弹「已被禁用」）
local glow, tabGlow
-- 10-16 实测：「去点」第一下能打开面板，但插件按 PlayerTalentFrame / TalentFrame 认不出 → 《无限》的天赋面板叫别的名字。
--   候选名挨个试；都不对就扫一遍全局里名字带 Talent 的、正显示着的框体，记下来（/gi talentprobe 能看到）
-- 11-10 用户（装了 EllesmereUI）「点了跳转过来还是没闪光」：talentprobe frame=EUI_TalentsRoute —— 那是 EllesmereUI 的隐形安全按钮
--   （名字带 Talents、挂 UIParent、永远「显示着」），扫全局时被当成天赋面板还记住了，之后真面板开着也去它里面找格子 → btns=0 不闪。
--   → 认面板必须「真有天赋格」（新版按钮池 / EllesmereUI 经典窗的 talents 列表 / 老版 <名>Talent1）；按钮类控件不算；记住的那个每次重新核对。
--   EllesmereUI 开了「经典天赋窗」时天赋面板是 EUI_ClassicTalents（格子是它自己的按钮，带 nodeID / spellID 字段）
local TF_NAMES = { "PlayerTalentFrame", "TalentFrame", "ClassTalentFrame", "PlayerSpellsFrame", "TalentUIFrame", "EUI_ClassicTalents" }
local tfFound
local talentButtons   -- 前向声明（定义在下面）
local function hasCells(f)
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, shown = pcall(f.IsShown, f)
    if not ok or not shown then return false end
    if type(f.GetObjectType) == "function" then
        local okT, ot = pcall(f.GetObjectType, f)
        if okT and (ot == "Button" or ot == "CheckButton") then return false end
    end
    local okN, name = pcall(function() return f:GetName() end)
    if okN and name and _G[name .. "Talent1"] then return true end
    return talentButtons ~= nil and #(talentButtons(f)) > 0
end
local function findTalentFrame(scan)
    if tfFound and hasCells(tfFound) then return tfFound end
    for _, n in ipairs(TF_NAMES) do
        local f = _G[n]
        if hasCells(f) then
            tfFound = f
            if ns.HookTalentFrame then pcall(ns.HookTalentFrame, f) end   -- EllesmereUI 的窗是第一次打开才建的，载入时挂不上
            return f
        end
    end
    if scan then
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("Talent", 1, true) and not k:find("GearInsight", 1, true) and type(v) == "table"
                and type(v.IsShown) == "function" and type(v.GetParent) == "function" then
                local okp, parent = pcall(v.GetParent, v)
                if okp and parent == UIParent and hasCells(v) then tfFound = v; return v end
            end
        end
    end
    return nil
end
ns.FindTalentFrame = findTalentFrame
local target   -- 规划行指定的天赋 { tab, row, col, name, tree }；点掉一点后清掉，回到「计划的下一点」

local function makeGlow()
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(); t:SetTexture("Interface\\Buttons\\CheckButtonHilight"); t:SetBlendMode("ADD")
    t:SetVertexColor(0.2, 1, 0.4)
    g.tex = t
    -- 10-16 用户「有绿框了，可以闪动吗」：亮暗来回呼吸（0.45 秒一程），显示时自动开始
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.2); a:SetDuration(0.45)
    -- 用户「设定个时间吧，比如说10S」：闪 10 秒后停下，变成常亮框（还在指着那一格）；每次重新显示重新计时
    local token = 0
    g:SetScript("OnShow", function()
        token = token + 1
        local my = token
        ag:Play()
        C_Timer.After(10, function() if token == my then ag:Stop(); g:SetAlpha(1) end end)
    end)
    g:SetScript("OnHide", function() token = token + 1; ag:Stop() end)
    g:Hide()
    return g
end

function ns.SetTalentTarget(st)
    target = (st and st.tab) and { tab = st.tab, row = st.row, col = st.col, name = st.name, tree = st.tree } or nil
    ns.HighlightTalentStep()
end

-- 现在要套框的那一点：规划行点过的优先，否则计划（自己导入的 / 默认升级加点）的下一点
local function currentStep()
    if target then
        local cell = gameIndex(target.tab)[target.row .. ":" .. target.col]
        return { tab = target.tab, index = cell and cell.i, node = cell and cell.node, name = target.name, tree = target.tree }
    end
    -- 10-16 用户截图「点完以后开始闪这里了」：点掉凶暴后没点数了，旧逻辑（NextTalentStep 不管行解锁、不管有没有点数）跳去闪第二行。
    --   改成和升级规划「现在就能点」同一把尺：没剩点数就不亮；有点数取规划里第一条现在能点的
    local unspent = ns.UnspentTalentPoints and ns.UnspentTalentPoints() or 0
    if unspent <= 0 then return nil end
    local lv = UnitLevel and UnitLevel("player") or 0
    local steps = ns.PlanTalentSteps and ns.PlanTalentSteps(lv, lv)
    for _, st in ipairs(steps or {}) do
        if st.avail and st.tab then
            local cell = gameIndex(st.tab)[st.row .. ":" .. st.col]
            return { tab = st.tab, index = cell and cell.i, node = cell and cell.node, name = st.name, tree = st.tree }
        end
    end
    return nil
end

-- 10-16 实测：《无限》天赋面板 = 正式服新版 PlayerSpellsFrame（格子是按钮池，没有 Talent1 这种名字，也没有三棵树的页签）
--   → 遍历面板里正在显示的天赋按钮，读按钮上的法术编号 → 法术名，和计划里的天赋名对上。只读字段，不调用暴雪按钮的方法
local function spellNameOf(sid)
    if not sid then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(sid) end
    return GetSpellInfo and (GetSpellInfo(sid)) or nil
end
local function buttonSpellID(b)
    if rawget(b, "spellID") then return rawget(b, "spellID") end   -- EllesmereUI 经典天赋窗
    local d = rawget(b, "definitionInfo")
    if type(d) == "table" and d.spellID then return d.spellID end
    local n = rawget(b, "nodeInfo")
    local e = rawget(b, "entryInfo")
    if type(e) == "table" and e.definitionID and C_Traits and C_Traits.GetDefinitionInfo then
        local ok, di = pcall(C_Traits.GetDefinitionInfo, e.definitionID)
        if ok and type(di) == "table" then return di.spellID end
    end
    return type(n) == "table" and n.spellID or nil
end
talentButtons = function(tf)
    local list = {}
    -- EllesmereUI 经典天赋窗：win.talents = 它自己的格子按钮（b.nodeID / b.spellID）
    local eui = rawget(tf, "talents")
    if type(eui) == "table" then
        for _, b in ipairs(eui) do
            if type(b) == "table" and rawget(b, "nodeID") then list[#list + 1] = b end
        end
        if #list > 0 then return list, tf end
    end
    for _, c in ipairs({ rawget(tf, "TalentsFrame"), rawget(tf, "TalentsTab"), tf }) do
        if type(c) == "table" and type(c.EnumerateAllTalentButtons) == "function" then
            local ok = pcall(function() for b in c:EnumerateAllTalentButtons() do list[#list + 1] = b end end)
            if ok and #list > 0 then return list, c end
        end
    end
    return list
end
ns.TalentButtons = talentButtons
-- 11-10 用户截图「猎人升级规划，点去点天赋，没有高亮」：按法术名对，计划里的中文名和客户端不一样（官方未汉化插件自译 / 改名）就对不上
--   → 先按天赋节点编号对（TraitCells 读到的 node 和面板按钮的 nodeID 是同一个），对不上再按名字
local function buttonNodeID(b)
    local id = rawget(b, "nodeID")
    if not id then local n = rawget(b, "nodeInfo"); id = type(n) == "table" and n.ID or nil end
    return id
end
local function findButtonByName(tf, name, node)
    if not name and not node then return nil end
    if node then
        for _, b in ipairs((talentButtons(tf))) do
            local ok, vis = pcall(b.IsVisible, b)
            if ok and vis and buttonNodeID(b) == node then return b end
        end
    end
    if not name then return nil end
    for _, b in ipairs((talentButtons(tf))) do
        local ok, vis = pcall(b.IsVisible, b)
        if ok and vis and spellNameOf(buttonSpellID(b)) == name then return b end
    end
end

function ns.HighlightTalentStep()
    local tf = findTalentFrame(false) or _G.PlayerTalentFrame or _G.TalentFrame
    if glow then glow:Hide() end
    if tabGlow then tabGlow:Hide() end
    if not tf or not tf:IsShown() then return end
    local ok, step = pcall(currentStep)
    if not ok or not step then return end
    local fname = tf:GetName() or "PlayerTalentFrame"
    if not _G[fname .. "Talent1"] then   -- 新版界面
        local b = findButtonByName(tf, step.name, step.node)
        if not b then return end
        glow = glow or makeGlow()
        -- 10-16 用户截图「关了天赋面板还在闪」：绿框挂在 UIParent 上靠面板 OnHide 收，钩子没收到就留在屏幕上 →
        --   直接挂到格子下面（只是我们自己的框换父级，不改暴雪按钮），面板一关跟着消失
        glow:SetParent(b); glow:SetFrameStrata("TOOLTIP")
        glow:ClearAllPoints()
        glow:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 6); glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -6)
        glow:Show()
        return
    end
    local selTab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(tf)
    if selTab and selTab ~= step.tab then
        local tb = _G[fname .. "Tab" .. step.tab]
        if tb and tb:IsShown() then
            tabGlow = tabGlow or makeGlow()
            tabGlow:SetParent(tb); tabGlow:SetFrameStrata("TOOLTIP")
            tabGlow:ClearAllPoints()
            tabGlow:SetPoint("TOPLEFT", tb, "TOPLEFT", -4, 4); tabGlow:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 4, -4)
            tabGlow:Show()
        end
        return
    end
    local btn = _G[fname .. "Talent" .. step.index]
    if not btn or not btn:IsShown() then return end
    glow = glow or makeGlow()
    glow:SetParent(btn); glow:SetFrameStrata("TOOLTIP")
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6); glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 6, -6)
    glow:Show()
end

-- ---------- 「去点」：安全按钮代点菜单栏的天赋按钮（type=click）打开面板 ----------
-- 插件代码不直接打开天赋面板（ToggleTalentFrame 由插件调，面板 OnShow 里写的状态会被污染 → 玩家自己点格子学天赋也可能被拦）。
-- ⛔ 安全按钮不挂在 / 不锚到 GI 窗口的普通框体（会把 GI 主窗口带成受保护，战斗中关不掉）：
--   顶层框体，鼠标移到规划行的「去点」上时，脱战按屏幕坐标盖过去；移开 / 窗口关了就藏；进战斗由安全状态驱动藏起来。
-- 点击方式：正式服实测 AnyUp+AnyDown 会触发两次（开了又关），默认只认按下；点了没打开就自动换成只认松开（存档记住）。
local opener
local function microButton()
    return _G.TalentMicroButton or _G.PlayerSpellsMicroButton
end

local function talentFrameShown()
    return findTalentFrame(true) ~= nil
end

-- ⛔ 只认按下（10-16《无限》实测：AnyDown 能打开；以前「没检测到就自动换成 AnyUp」反而把按钮弄坏了 —— 检测认错了面板名，
--   换成 AnyUp 后这台客户端根本不触发）。正式服仪表盘同样结论（DashSecure.lua）。
local function setClickMode(b)
    if ns.db.ui then ns.db.ui.talentOpenUp = nil end   -- 清掉 10-16 测试包自动换出来的旧设置
    b:RegisterForClicks("AnyDown")
end

local function buildOpener()
    if opener then return opener end
    if InCombatLockdown() or not microButton() then return nil end
    local b = CreateFrame("Button", "GearInsightForeverTalentOpen", UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up"); b:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down"); b:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD"); b:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    b:SetNormalFontObject("GameFontNormal"); b:SetHighlightFontObject("GameFontHighlight")
    b:SetText(ns.L("去点", "Go"))
    b:SetAttribute("type", "click")
    b:SetAttribute("clickbutton", microButton())
    setClickMode(b)
    RegisterStateDriver(b, "gicombat", "[combat] 1; 0")
    b:SetAttribute("_onstate-gicombat", [[ if newstate == "1" then self:Hide() end ]])
    b:SetScript("PreClick", function(self)
        self.wasShown = talentFrameShown()
        if self.step then target = { tab = self.step.tab, row = self.step.row, col = self.step.col, name = self.step.name, tree = self.step.tree } end
    end)
    b:SetScript("PostClick", function(self)
        local st, was = self.step, self.wasShown
        C_Timer.After(0.4, function()
            local now = talentFrameShown()
            local tf = findTalentFrame(true)
            if tf then pcall(hookOne, tf) end
            ns.probeTalentOpen = (ns.probeTalentOpen or "") .. "D" .. (was and 1 or 0) .. (now and 1 or 0) .. ":" .. tostring(tf and tf:GetName()) .. ","
            if not was and not now then
                ns.Print(ns.L("没认出天赋面板：如果面板其实开了，请输 /gi talentprobe 把结果发给开发者；没开就按 N",
                    "Talent frame not detected: if it did open, run /gi talentprobe; otherwise press N"))
            elseif now and st then
                ns.HighlightTalentStep()
                ns.Print(ns.EnSafe(ns.L("在「", "On the ") .. (st.tree or "") .. ns.L("」页点「", " tab, click ") .. (st.name or "")
                    .. ns.L("」（已套绿框；不在这页就先点套绿框的页签）", " (highlighted; if not on this tab, click the highlighted tab first)")))
            end
        end)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L("打开天赋面板", "Open talents"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.EnSafe(ns.L("给「", "Highlights ") .. ((self.step and self.step.name) or "") .. ns.L("」套绿框，你自己点一下就学会了。暴雪不允许插件替你加点。",
            " - click it yourself to learn; Blizzard does not allow addons to spend talent points.")), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 鼠标移开 / GI 窗口关掉 / 列表滚走：藏起来（只在脱战；战斗中状态驱动已经藏了）
    b:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then return end
        local a = self.anchor
        if not a or not a:IsVisible() or not (self:IsMouseOver() or a:IsMouseOver()) then self:Hide() end
    end)
    b:Hide()
    opener = b
    return b
end

-- 规划行「去点」按钮 OnEnter 调：把安全按钮盖到它上面。返回 false = 盖不了（战斗中 / 找不到菜单栏天赋按钮），行按钮自己的 OnClick 兜底
function ns.TalentOpenerHover(anchor, st)
    if InCombatLockdown() then return false end
    local b = buildOpener()
    if not b then return false end
    local l, btm = anchor:GetLeft(), anchor:GetBottom()
    if not l then return false end
    b:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, btm)
    b:SetSize(anchor:GetWidth(), anchor:GetHeight())
    b.anchor, b.step = anchor, st
    b:Show()
    return true
end

-- 兜底（战斗中 / 客户端没有菜单栏天赋按钮）：只设目标 + 提示按 N
function ns.TalentGoFallback(st)
    ns.SetTalentTarget(st)
    ns.Print(ns.EnSafe(ns.L("按 N 打开天赋面板，在「", "Press N, then on the ") .. (st.tree or "") .. ns.L("」页点「", " tab click ")
        .. (st.name or "") .. ns.L("」（会套绿框）", " (highlighted)")))
end

-- 10-16：《无限》天赋面板名字不在老两个里 → 候选名都挂；「去点」认出真实面板后也会挂上（ns.HookTalentFrame）
local function hookOne(tf)
    if not tf or tf.__gifGlowHook or type(tf.HookScript) ~= "function" then return end
    tf.__gifGlowHook = true
    tf:HookScript("OnShow", function() C_Timer.After(0.1, ns.HighlightTalentStep) end)
    tf:HookScript("OnHide", function() if glow then glow:Hide() end; if tabGlow then tabGlow:Hide() end end)
end
ns.HookTalentFrame = hookOne

local function hookTalentFrame()
    for _, n in ipairs(TF_NAMES) do pcall(hookOne, _G[n]) end
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf or tf.__gifUpdHook then return end
    tf.__gifUpdHook = true
    if type(_G.PlayerTalentFrame_Update) == "function" then
        hooksecurefunc("PlayerTalentFrame_Update", function() ns.HighlightTalentStep() end)
    elseif type(_G.TalentFrame_Update) == "function" then
        hooksecurefunc("TalentFrame_Update", function() ns.HighlightTalentStep() end)
    end
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    for _, e in ipairs(ns.TALENT_EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, ev, name)
        if ns.IsTalentEvent(ev) then
            target = nil   -- 点掉了一点：绿框回到计划的下一点
            C_Timer.After(0.3, ns.HighlightTalentStep)
        elseif type(name) == "string" and name:find("Talent", 1, true) then pcall(hookTalentFrame) end
    end)
    pcall(hookTalentFrame)
end)

-- 10-16 天赋面板探针：/gi talentprobe（打开天赋面板后输）—— 面板叫什么、页签和格子按钮叫什么
function ns.TalentProbe()
    local out = { "GITAL1" }
    local tf = findTalentFrame(true)
    out[#out + 1] = "frame=" .. tostring(tf and tf:GetName())
    local shown = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("Talent", 1, true) or k:find("Spells", 1, true)) and not k:find("GearInsight", 1, true)
            and type(v) == "table" and type(v.IsShown) == "function" then
            local ok, sh = pcall(v.IsShown, v)
            if ok and sh and #shown < 40 then shown[#shown + 1] = k end
        end
    end
    table.sort(shown)
    out[#out + 1] = "shown=" .. table.concat(shown, "/")
    if tf then
        local n = tf:GetName() or "?"
        out[#out + 1] = "tab=" .. tostring(PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(tf))
        out[#out + 1] = "Tab1=" .. tostring(_G[n .. "Tab1"] ~= nil) .. " Talent1=" .. tostring(_G[n .. "Talent1"] ~= nil)
    end
    local ok, step = pcall(currentStep)
    out[#out + 1] = "step=" .. (ok and step and (tostring(step.tab) .. ":" .. tostring(step.index) .. ":" .. tostring(step.name)) or tostring(step))
    out[#out + 1] = "glow=" .. tostring(glow and glow:IsShown()) .. " tabGlow=" .. tostring(tabGlow and tabGlow:IsShown())
    if tf then
        local list, c = talentButtons(tf)
        out[#out + 1] = "btns=" .. #list .. " in=" .. tostring(c and (c.GetName and c:GetName() or "anon"))
        local b = list[1]
        if b then
            local keys = {}
            for k, v in pairs(b) do if type(k) == "string" and type(v) ~= "function" and #keys < 30 then keys[#keys + 1] = k .. ":" .. type(v) end end
            table.sort(keys)
            out[#out + 1] = "b1=" .. table.concat(keys, ",")
            out[#out + 1] = "b1spell=" .. tostring(buttonSpellID(b)) .. ":" .. tostring(spellNameOf(buttonSpellID(b)))
        end
        local names = {}
        for i, x in ipairs(list) do
            if i > 12 then break end
            names[#names + 1] = tostring(spellNameOf(buttonSpellID(x)))
        end
        out[#out + 1] = "names=" .. table.concat(names, "/")
    end
    out[#out + 1] = "api=" .. "GetNumTalents:" .. tostring(GetNumTalents and select(2, pcall(GetNumTalents, 1)))
        .. " GetTalentInfo11:" .. tostring(GetTalentInfo and select(2, pcall(GetTalentInfo, 1, 1)))
        .. " C_ClassTalents:" .. tostring(C_ClassTalents ~= nil) .. " cfg:" .. tostring(C_ClassTalents and C_ClassTalents.GetActiveConfigID and select(2, pcall(C_ClassTalents.GetActiveConfigID)))
        .. " pts:" .. tostring(UnitCharacterPoints and UnitCharacterPoints("player"))
        .. " code:" .. tostring(ns.CurrentTalentCode and ns.CurrentTalentCode())
    -- 11-10 用户「19 级没展示天赋」「点了跳转过来还是没闪光」：把升级规划用的那几个数也带上（未分点数 / 计划 / 第一条待点）
    do
        local lv = UnitLevel and UnitLevel("player") or 0
        local okS, steps, err, plan = pcall(ns.PlanTalentSteps, lv + 1, lv)
        local s1 = okS and type(steps) == "table" and steps[1]
        out[#out + 1] = "lv=" .. lv .. " unspent=" .. tostring(ns.UnspentTalentPoints and ns.UnspentTalentPoints())
            .. " plan=" .. tostring(plan and (plan.key or (plan.default and "default") or "imported")) .. " err=" .. tostring(okS and (err or "nil") or steps)
            .. " n=" .. tostring(okS and type(steps) == "table" and #steps)
            .. " s1=" .. (s1 and (s1.lv .. ":" .. tostring(s1.tab) .. ":" .. s1.row .. ":" .. s1.col .. ":" .. tostring(s1.name) .. ":" .. tostring(s1.avail)) or "nil")
    end
    out[#out + 1] = "micro=" .. tostring(microButton() and microButton():GetName())
    out[#out + 1] = "open=" .. tostring(ns.probeTalentOpen)
    ns.ShowBox(ns.L("天赋面板探针", "Talent probe"), ns.L("Ctrl+C 复制发给开发者", "Ctrl+C to copy"), table.concat(out, ";"))
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.talentprobe = function() ns.TalentProbe() end
