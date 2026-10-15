-- 成就 · 传承页（10-10 四期）：《无限》客户端 211 个成就，131 个给传承点数 —— 一眼看出「还有哪些成就能拿传承点」
-- 数据 = 网站 / 小程序同一份 achievements.json（bis_wow tools/build_forever_achievements.py，客户端 DB2）
-- 完成状态用 GetAchievementInfo（查不了就只列不打勾）；奖励里写着「N 点传承点数」的单独筛
local _, ns = ...

local page
local mode = "legacy"          -- legacy = 只看给传承点数的 / todo = 只看没完成的 / all
local ROW_H = 34

local function done(id)
    if not GetAchievementInfo then return nil end
    local ok, _, _, _, completed = pcall(GetAchievementInfo, id)
    if not ok then return nil end
    return completed and true or false
end

local function list()
    local out = {}
    for _, a in ipairs(ns.Data.achievements or {}) do
        local d = done(a.id)
        if (mode == "all") or (mode == "legacy" and (a.lg or 0) > 0) or (mode == "todo" and d ~= true) then
            out[#out + 1] = { a = a, d = d }
        end
    end
    return out
end

local function getRow(i)
    local r = page.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.child)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(26, 26); r.ic:SetPoint("LEFT", 4, 0); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.t:SetPoint("TOPLEFT", 36, -3); r.t:SetPoint("RIGHT", -96, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.s:SetPoint("BOTTOMLEFT", 36, 4); r.s:SetPoint("RIGHT", -96, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    r.lg = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.lg:SetPoint("RIGHT", -30, 0)
    r.ok = r:CreateTexture(nil, "OVERLAY"); r.ok:SetSize(18, 18); r.ok:SetPoint("RIGHT", -6, 0)
    r.ok:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.head:SetPoint("LEFT", 6, 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    -- 描述常被截 → 悬停看全（用户硬规定：显示不全一律有 tooltip）
    r:SetScript("OnEnter", function(self)
        local a = self.a
        if not a then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L(a.t, a.tEn), 1, 0.82, 0)
        GameTooltip:AddLine(ns.EnSafe(ns.L(a.d, a.dEn)), 1, 1, 1, true)
        GameTooltip:AddLine(ns.EnSafe(ns.L(a.top .. " · " .. a.cat, a.topEn .. " - " .. a.catEn)), 0.6, 0.6, 0.6)
        if (a.lg or 0) > 0 then GameTooltip:AddLine(ns.L("奖励：", "Reward: ") .. a.lg .. ns.L(" 点传承点数", " Legacy point(s)"), 0.2, 1, 0.6) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.rows[i] = r
    return r
end

local function refresh()
    if not page then return end
    for k, b in pairs(page.modeBtns) do b:SetEnabled(k ~= mode) end
    for _, r in ipairs(page.rows) do r:Hide() end
    local L = list()
    -- 统计：传承点数 已拿 / 总共
    local got, total, known = 0, 0, false
    for _, a in ipairs(ns.Data.achievements or {}) do
        if (a.lg or 0) > 0 then
            total = total + a.lg
            local d = done(a.id)
            if d ~= nil then known = true end
            if d then got = got + a.lg end
        end
    end
    page.stat:SetText(known and string.format(ns.L("传承点数：已拿 %d / 共 %d", "Legacy points: %d / %d earned"), got, total)
        or string.format(ns.L("成就能拿 %d 点传承点数", "%d Legacy points available from achievements"), total))
    local y, n, lastTop = -2, 0, nil
    for _, e in ipairs(L) do
        local a = e.a
        if a.top ~= lastTop then   -- 大类标题行
            n = n + 1
            local h = getRow(n)
            h.a = nil; h.ic:Hide(); h.t:SetText(""); h.s:SetText(""); h.lg:SetText(""); h.ok:Hide(); h.bg:Hide()
            h.head:SetText("|cffffd100" .. ns.L(a.top, a.topEn) .. "|r")
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, y); h:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); h:SetHeight(22); h:Show()
            y = y - 24
            lastTop = a.top
        end
        n = n + 1
        local r = getRow(n)
        r.a = a; r.head:SetText(""); r.bg:Show(); r:SetHeight(ROW_H)
        r.ic:SetTexture("Interface\\Icons\\" .. ((a.i or "") ~= "" and a.i or "INV_Misc_QuestionMark")); r.ic:Show()
        r.t:SetText((e.d and "|cff9d9d9d" or "|cffffffff") .. ns.L(a.t, a.tEn) .. "|r")
        r.s:SetText(ns.EnSafe(ns.L(a.d, a.dEn)))
        r.lg:SetText((a.lg or 0) > 0 and ("|cff33ff99+" .. a.lg .. ns.L(" 传承", " Legacy") .. "|r") or "")
        r.ok:SetShown(e.d == true)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:Show()
        y = y - ROW_H - 2
    end
    if #L == 0 then
        n = n + 1
        local r = getRow(n)
        r.a = nil; r.ic:Hide(); r.t:SetText(""); r.s:SetText(""); r.lg:SetText(""); r.ok:Hide(); r.bg:Hide()
        r.head:SetText(ns.L("|cff888888这一栏都完成了|r", "|cff888888All done here|r"))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:Show()
        y = y - ROW_H
    end
    page.child:SetHeight(-y + 4)
end

local function build(p)
    page = p
    ns.AchPage = p   -- 测试用（同 ns.LootPage）
    p.rows = {}
    ns.PageHeader(p, ns.L("成就 · 传承", "Achievements"),
        ns.L("《无限》成就里有一大半奖励传承点数 —— 看看还有哪些没拿", "Most Forever achievements award Legacy points - see what's left"))
    p.modeBtns = {}
    local x = 12
    for _, m in ipairs({ { "legacy", ns.L("给传承点数的", "Legacy rewards") }, { "todo", ns.L("还没完成", "Not done") }, { "all", ns.L("全部", "All") } }) do
        local b = ns.Button(p, m[2], 110, 22, function() mode = m[1]; refresh() end)
        b:SetPoint("TOPLEFT", x, -42)
        p.modeBtns[m[1]] = b
        x = x + 114
    end
    p.stat = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.stat:SetPoint("LEFT", p.modeBtns.all, "RIGHT", 12, 0); p.stat:SetPoint("RIGHT", p, "RIGHT", -12, 0); p.stat:SetJustifyH("LEFT")
    local _, c = ns.Scroll(p, 6, -72, 616, 474 - 72 - 12)
    p.child = c
end

-- 成就完成时刷新（页开着的时候）
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "ACHIEVEMENT_EARNED")   -- 《无限》客户端缺事件时别报错（同 TRADE_SKILL_UPDATE 的坑）
ev:SetScript("OnEvent", function() if page and page:IsShown() then refresh() end end)

ns.RegisterPage({ key = "ach", order = 3.2, title = ns.L("成就 · 传承", "Achievements"), tabTitle = ns.L("成就", "Achieve"),
    icon = "Interface\\Icons\\Achievement_Zone_Ashenvale_01", build = build, refresh = refresh })
