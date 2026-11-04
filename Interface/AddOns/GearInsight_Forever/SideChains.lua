-- HOLD：特殊任务线并进升级规划（10-18 用户转抖音「魔兽无限睡袋任务路线流程」：「把这个安排到升级规划，三端同步」）。
--   数据 SideChainsData.lua ← scripts/forever_side_chains.py（网站 / 小程序导出同一份）。
--   升级规划「地图待办」里：到推荐等级（按阵营）出一行；做完的步骤按任务 ID 查 C_QuestLog.IsQuestFlaggedCompleted 自动打勾。
--   点这一行 = 弹框：效果 / 推荐等级 / 逐步（地图 · 坐标 · 点什么 · 怎么走 · 对应任务）+ 每步「地图」按钮标点（ns.ShowOnMap）+ 奖励 + 避坑。
local _, ns = ...
local L = ns.L

local SC = {}
ns.SideChains = SC

local function faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde") and "Horde" or "Alliance"
end
SC.Faction = faction

local function questDone(id)
    if not id then return false end
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not f then return false end
    local ok, v = pcall(f, id)
    return ok and v and true or false
end
local function onQuest(id)
    if not id then return false end
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, v = pcall(C_QuestLog.IsOnQuest, id)
        if ok and v then return true end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, v = pcall(C_QuestLog.GetLogIndexForQuestID, id)
        if ok and v and v > 0 then return true end
    end
    return false
end
SC._questDone, SC._onQuest = questDone, onQuest   -- 测试用

-- 每一步状态：done（这步交的任务已完成，或接到的下一个任务已在日志 / 已完成）· next（第一个没做的）· todo
function SC.Progress(c, fac)
    local steps = c.steps[fac or faction()] or {}
    local st, n, nextI = {}, 0, nil
    for i, s in ipairs(steps) do
        local d = (s.done and questDone(s.done)) or (s.start and s.start ~= s.done and (onQuest(s.start) or questDone(s.start)))
        st[i] = d and "done" or "todo"
        if d then n = n + 1 end
    end
    -- 后面的步做了，前面的一定也做了（任务线是串的；有的步只看「接没接」）
    local last = 0
    for i = #st, 1, -1 do if st[i] == "done" then last = i; break end end
    for i = 1, last do if st[i] ~= "done" then st[i] = "done"; n = n + 1 end end
    for i = 1, #st do if st[i] ~= "done" then nextI = i; st[i] = "next"; break end end
    return st, n, #steps, nextI
end

-- 升级规划用：推荐等级（按阵营）那一级出一行；没做完且已经过了推荐等级 → 挪到当前等级（别让它掉进「已过去」）
function ns.SideChainItems(lo, hi, cur)
    local out = {}
    local fac = faction()
    for _, c in ipairs(ns.SideChainsData or {}) do
        local _, n, total = SC.Progress(c, fac)
        local rec = (c.rec and c.rec[fac]) or c.minLv or 1
        local finished = total > 0 and n >= total
        local lv = rec
        if not finished and cur > rec then lv = cur end
        if lv >= lo and lv <= hi then
            out[#out + 1] = { lv = lv, kind = "chain", c = c, n = n, total = total, st = finished and "done" or (lv <= cur and "now" or "future") }
        end
    end
    return out
end

-- ---------- 弹框 ----------
local pop
local function buildPop()
    local f = CreateFrame("Frame", "GearInsightForeverSideChain", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(620, 470); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.045, 0.06, 0.97); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverSideChain") end   -- ESC 关
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -40, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    local sf, c = ns.Scroll(f, 8, -40, 604, 470 - 48)
    f.sf, f.child, f.rows, f.texts = sf, c, {}, {}
    f:Hide()
    return f
end

local function text(i, tpl)
    local t = pop.texts[i]
    if not t then
        t = pop.child:CreateFontString(nil, "OVERLAY", tpl or "GameFontHighlight")
        t:SetJustifyH("LEFT"); t:SetSpacing(3)
        pop.texts[i] = t
    end
    return t
end

local function stepRow(i)
    local r = pop.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pop.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("TOPLEFT", 6, -6)
    r.no = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.no:SetPoint("CENTER", r.ic, "CENTER")
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.t:SetPoint("TOPLEFT", 32, -6); r.t:SetPoint("RIGHT", -78, 0); r.t:SetJustifyH("LEFT")
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -3); r.s:SetPoint("RIGHT", -78, 0)
    r.s:SetJustifyH("LEFT"); r.s:SetSpacing(2)
    r.map = ns.Button(r, L("地图", "Map"), 66, 22); r.map:SetPoint("TOPRIGHT", -6, -6)
    pop.rows[i] = r
    return r
end

function SC.Show(c)
    pop = pop or buildPop()
    SC.pop = pop
    local fac = faction()
    local st, n, total = SC.Progress(c, fac)
    pop.title:SetText("|cff33ff99" .. L("任务线：", "Quest line: ") .. "|r" .. L(c.t, c.tEn) .. "  |cff888888" .. n .. "/" .. total .. "|r")
    for _, r in ipairs(pop.rows) do r:Hide() end
    for _, t in ipairs(pop.texts) do t:Hide() end
    local y, ti = -4, 0
    local function para(s, tpl, color)
        ti = ti + 1
        local t = text(ti, tpl)
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 6, y); t:SetWidth(580)
        t:SetText(ns.EnSafe((color or "") .. s .. (color and "|r" or ""))); t:Show()
        y = y - (tonumber(t:GetStringHeight()) or 14) - 8
    end
    local rec = (c.rec and c.rec[fac]) or c.minLv
    para(L(c.gist, c.gistEn), "GameFontNormal", "|cffffd100")
    for _, e in ipairs(c.effect or {}) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    para(string.format(L("%d 级能接 · 推荐 %d 级（%s）", "Level %d to start · recommended %d (%s)"), c.minLv or 1, rec,
        fac == "Horde" and L("部落", "Horde") or L("联盟", "Alliance")) .. "  |cff888888" .. L(c.recWhy, c.recWhyEn) .. "|r", "GameFontHighlightSmall")
    y = y - 4
    for i, s in ipairs(c.steps[fac] or {}) do
        local r = stepRow(i)
        local done, isNext = st[i] == "done", st[i] == "next"
        r.bg:SetColorTexture(isNext and 0.2 or 1, isNext and 1 or 1, isNext and 0.4 or 1, isNext and 0.10 or 0.04)
        if done then r.ic:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); r.ic:Show(); r.no:SetText("")
        else r.ic:SetTexture(nil); r.no:SetText((isNext and "|cff33ff99" or "|cffffd100") .. i .. "|r") end
        r.t:SetText((done and "|cff808080" or "") .. L(s.z, s.zEn) .. string.format("  (%.1f, %.1f)", s.x, s.y)
            .. "  " .. (done and "" or "|cffffffff") .. L(s.obj, s.objEn) .. "|r")
        local sub = "|cffcccccc" .. L(s.act, s.actEn) .. "|r"
        if s.q then sub = sub .. "\n|cff888888" .. L("任务：", "Quest: ") .. L(s.q, s.qEn) .. "|r" end
        if s.note then sub = sub .. "  |cffd8c79a" .. L(s.note, s.noteEn) .. "|r" end
        r.s:SetText(ns.EnSafe(sub))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", 0, 0)
        r:SetHeight(math.max(44, 12 + (tonumber(r.t:GetStringHeight()) or 14) + 3 + (tonumber(r.s:GetStringHeight()) or 24)))
        r.map:SetScript("OnClick", function()
            local pts = { { s.x, s.y } }
            if s.via then pts = { { s.via[1], s.via[2] }, { s.x, s.y } } end   -- 先标路口（石爪山营地要从山路上去）
            if ns.ShowOnMap then ns.ShowOnMap(s.map, pts, L(s.obj, s.objEn)) end
        end)
        r:Show()
        y = y - (tonumber(r:GetHeight()) or 44) - 4
    end
    y = y - 6
    local rw = {}
    for _, e in ipairs(c.reward or {}) do rw[#rw + 1] = L(e[1], e[2]) end
    para(L("奖励：", "Rewards: ") .. table.concat(rw, L("、", ", ")), "GameFontHighlightSmall", "|cff33ff99")
    para(L("避坑", "Tips"), "GameFontNormal", "|cffffd100")
    for _, e in ipairs(c.tips or {}) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    pop.child:SetHeight(-y + 6)
    pop:Show()
end

-- 升级规划那一行怎么画（PagePlan.lua 的 kind == "chain" 交给这里）
function ns.SideChainRenderRow(r, it, suffix)
    local c = it.c
    r.ic:SetTexture("Interface\\Icons\\" .. (c.icon or "INV_Misc_Note_01"))
    r.ic:SetDesaturated(it.st == "done")
    r.t:SetText((it.st == "done" and "|cff808080" or "|cffff9933") .. L("任务线：", "Quest line: ") .. L(c.t, c.tEn) .. "|r  |cff888888"
        .. it.n .. "/" .. it.total .. "|r")
    r.s:SetText(L(c.gist, c.gistEn) .. (suffix or ""))
    r:SetScript("OnClick", function() SC.Show(c) end)
    r.btn:SetText(L("路线", "Route")); r.btn:Show()
    r.btn:SetScript("OnClick", function() SC.Show(c) end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L(c.t, c.tEn), 1, 0.82, 0)
        GameTooltip:AddLine(L(c.gist, c.gistEn), 1, 1, 1, true)
        GameTooltip:AddLine(string.format(L("已做 %d / %d 步 · 点击看逐步路线和坐标", "%d / %d steps done · click for the route"), it.n, it.total), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
end
