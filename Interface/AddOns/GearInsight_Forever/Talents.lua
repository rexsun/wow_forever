-- 配点码导入：GIF1.<职业>.<树1>-<树2>-<树3>，每位数字 = 该树第 i 个天赋的点数
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
    local cls, body = code:match("^GIF1%.(%a+)%.(.+)$")
    if not cls then return nil, ns.L("不是配点码（应以 GIF1. 开头）", "Not a build code (should start with GIF1.)") end
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
    return { cls = cls, pts = pts, total = total }
end

-- 游戏里的天赋格：按 行:列 建索引
local function gameIndex(tab)
    local idx = {}
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
function ns.ActivePlan()
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
                    d = ns.L(t.d, t.dEn), icon = t.i, row = t.r, col = t.col, rank = used[ti][i], rankMax = t.m }
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
                            d = ns.L(t.d, t.dEn), icon = t.i, row = t.r, col = t.col }
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

local panel
local function updatePanel()
    if not panel or not panel:IsShown() or not ns.db.talentPlan then return end
    local plan = ns.db.talentPlan
    local unspent = (UnitCharacterPoints and UnitCharacterPoints("player")) or 0
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
    f:RegisterEvent("CHARACTER_POINTS_CHANGED")
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
    ns.db.talentPlan = plan
    panel = panel or buildPanel()
    panel:Show(); updatePanel()
    ns.Print(ns.L("已导入配点码，共 ", "Build imported, ") .. plan.total .. ns.L(" 点", " points"))
    return true
end

function ns.ImportTalentDialog()
    ns.ShowBox(ns.L("导入配点码", "Import talent build"),
        ns.L("在网站或小程序「无限 · 天赋模拟」里复制 GIF1 开头的码，粘到这里",
            "Copy a GIF1 build code from the GearInsight site or mini program and paste it here"),
        "", ns.ApplyTalentCode, ns.L("导入", "Import"))
end

table.insert(ns.modules, function()
    if ns.db.talentPlan then
        C_Timer.After(2, function()
            if ns.db.talentPlan and ns.db.talentPlan.cls == classKey() then
                panel = panel or buildPanel(); panel:Show()
            end
        end)
    end
end)

-- ---------- 天赋面板上的绿框（自己的框，锚在暴雪格子上；⛔不调用 / 不改暴雪天赋面板的任何东西）----------
local glow
function ns.HighlightTalentStep()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    local step = ns.db and ns.db.talentPlan and ns.NextTalentStep(ns.db.talentPlan)
    if glow then glow:Hide() end
    if not tf or not tf:IsShown() or not step then return end
    local selTab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(tf)
    if selTab and selTab ~= step.tab then return end
    local btn = _G[(tf:GetName() or "PlayerTalentFrame") .. "Talent" .. step.index]
    if not btn or not btn:IsShown() then return end
    if not glow then
        glow = CreateFrame("Frame", nil, UIParent)
        glow:SetFrameStrata("TOOLTIP")
        local t = glow:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(); t:SetTexture("Interface\\Buttons\\CheckButtonHilight"); t:SetBlendMode("ADD")
        t:SetVertexColor(0.2, 1, 0.4)
        glow.tex = t
    end
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -6, 6); glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 6, -6)
    glow:Show()
end

local function hookTalentFrame()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf or tf.__gifGlowHook then return end
    tf.__gifGlowHook = true
    tf:HookScript("OnShow", function() C_Timer.After(0.1, ns.HighlightTalentStep) end)
    tf:HookScript("OnHide", function() if glow then glow:Hide() end end)
    if type(_G.PlayerTalentFrame_Update) == "function" then
        hooksecurefunc("PlayerTalentFrame_Update", function() ns.HighlightTalentStep() end)
    elseif type(_G.TalentFrame_Update) == "function" then
        hooksecurefunc("TalentFrame_Update", function() ns.HighlightTalentStep() end)
    end
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_TalentUI" then pcall(hookTalentFrame) end
    end)
    pcall(hookTalentFrame)
end)
