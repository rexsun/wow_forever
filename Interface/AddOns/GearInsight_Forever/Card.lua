-- 游戏里出二维码 → 微信扫 → 小程序（协议：docs/forever-addon-link-protocol.md）
--   战绩卡 + 报到：https://gearinsight.cn/fv/c?d=C1~<uid>~<cid>~<cls>~<race>~<fac>~<hc>~<lvl>~<played>~<thisLvl>~<deaths>~<build>~<lvt>~<top>
--   当前配点：     https://gearinsight.cn/fv/t?c=GIF1.<职业>.<a>-<b>-<c>
-- 小程序后台「扫普通链接二维码打开小程序」把 https://gearinsight.cn/fv/ 开头的链接接到 pages/forever/card；
-- 没配规则 / 用别的扫码软件时打开同一个网址 = 网站落地页（也能看战绩卡、再扫小程序码）。
-- ⛔ 只带随机 uid / cid，不带角色名 / 服务器名；插件不联网，二维码就是唯一出口。
local _, ns = ...

local BASE = "https://gearinsight.cn/fv/"
local FAC = { Alliance = "A", Horde = "H", Neutral = "N" }

local function classKey()
    local _, token = UnitClass("player")
    token = token or ""
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 这个角色每一级用了几分钟：同一 cid 相邻两级的 /played 之差 → "起始级.分-分-分"（1 分钟 ~ 24 小时之外的丢掉，断档就从断档后重新起）
function ns.LevelMinutes(cid, keepLast)
    local lv = {}
    for _, r in ipairs((ns.db and ns.db.lvls) or {}) do
        if r.cid == cid and r.played and r.played > 0 then lv[r.lvl] = r.played end
    end
    local first, mins = nil, {}
    local lvls = {}
    for l in pairs(lv) do lvls[#lvls + 1] = l end
    table.sort(lvls)
    for _, l in ipairs(lvls) do
        local p = lv[l - 1]
        if p and lv[l] > p then
            local m = math.floor((lv[l] - p) / 60 + 0.5)
            if m >= 1 and m <= 1440 then
                if first and l ~= first + #mins then first, mins = nil, {} end   -- 断档：只留最后一段连续的
                first = first or l
                mins[#mins + 1] = m
            end
        end
    end
    if not first then return "" end
    if keepLast and #mins > keepLast then
        local cut = #mins - keepLast
        local t = {}
        for i = cut + 1, #mins do t[#t + 1] = mins[i] end
        first, mins = first + cut, t
    end
    return first .. "." .. table.concat(mins, "-")
end

local function topKiller(c)
    local best, n = nil, 0
    for id, k in pairs(c.kill or {}) do
        if k > n or (k == n and best and id < best) then best, n = id, k end
    end
    return best and (best .. "." .. n) or ""
end

-- 拼战绩卡网址；超长逐步降级（lvt 只留最近 30 级 → 不带 lvt → 不带 top），保证二维码版本 ≤ 13
function ns.CardURL(opt)
    opt = opt or {}
    local c = ns.CurrentChar and ns.CurrentChar()
    if not c then return nil end
    local total, thisLvl = nil, nil
    if ns.PlayedNow then total, thisLvl = ns.PlayedNow() end
    local build = GetBuildInfo and ((select(1, GetBuildInfo()) or "") .. "." .. (select(2, GetBuildInfo()) or "")) or ""
    local hc = (c.hc == 1 and "1") or (c.hc == 0 and "0") or "x"
    local function make(lvt, top)
        return BASE .. "c?d=" .. table.concat({ "C1", ns.db.uid, c.cid, c.cls or "", c.race or "", FAC[c.fac or ""] or "", hc,
            tostring(UnitLevel("player") or c.lvl or 0), tostring(math.floor(total or 0)), tostring(math.floor(thisLvl or 0)),
            tostring(c.nd or 0), build, lvt, top }, "~")
    end
    local cap = ns.QR.ByteCapacity(ns.QR.MAX_VERSION, "M")
    local top = topKiller(c)
    for _, step in ipairs({ { nil, top }, { 30, top }, { 10, top }, { false, top }, { false, "" } }) do
        local lvt = (step[1] == false) and "" or ns.LevelMinutes(c.cid, step[1])
        local url = make(lvt, step[2])
        if #url <= (opt.cap or cap) then return url end
    end
    return nil
end

function ns.ShowCardQR(retry)
    if not retry and not (ns.PlayedNow and ns.PlayedNow()) and RequestTimePlayed then
        -- /played 还没回来：先静默要一次，1 秒后再出码（总时长才准）；还没回来就不带时长照样出
        ns.RequestPlayedSilently()
        C_Timer.After(1, function() ns.ShowCardQR(true) end)
        return
    end
    local url = ns.CardURL()
    if not url then ns.Print(ns.L("还没有角色数据，进游戏后再试", "No character data yet")); return end
    ns.ShowQR(ns.L("战绩卡", "Beta card"),
        ns.L("微信扫码：看你的升级用时、死亡次数、同职业排第几，并计入公测报到\n只带随机编号，不含角色名和服务器",
            "Scan with WeChat: level times, deaths, class rank.\nAnonymous: no character or realm name"), url, "M")
end

-- 当前天赋 → 配点码（顺序 = Data.lua = 小程序模拟器）
function ns.CurrentTalentCode()
    local cls = classKey()
    local trees = ns.Data.talents[cls]
    if not trees or not GetTalentInfo then return nil end
    local parts, total = {}, 0
    for ti, tr in ipairs(trees) do
        local idx = {}
        local n = GetNumTalents and GetNumTalents(ti) or 0
        for i = 1, n do
            local _, _, tier, col, rank = GetTalentInfo(ti, i)
            if tier then idx[tier .. ":" .. col] = rank or 0 end
        end
        local s = {}
        for i, t in ipairs(tr.t) do
            local r = idx[t.r .. ":" .. t.col] or 0
            if r > 9 then r = 9 end
            s[i] = tostring(r)
            total = total + r
        end
        parts[ti] = table.concat(s)
    end
    return "GIF1." .. cls .. "." .. table.concat(parts, "-"), total
end

function ns.ShowTalentQR()
    local code, total = ns.CurrentTalentCode()
    if not code then ns.Print(ns.L("读不到天赋", "Can't read talents")); return end
    if total == 0 then ns.Print(ns.L("还没点天赋", "No talent points spent yet")); return end
    ns.ShowQR(ns.L("把这套配点发到手机", "Send this build to your phone"),
        ns.L("微信扫码：在小程序天赋模拟器里打开，可继续调整、分享", "Scan with WeChat to open it in the talent simulator"),
        BASE .. "t?c=" .. code, "M")
end

-- ---------- 热门配点（数据包 ns.Pack.pop，更新器每天刷新）----------
local popFrame
function ns.ShowPopBuilds()
    local cls = classKey()
    local list = ns.Pack and ns.Pack.pop and ns.Pack.pop[cls]
    if not list or #list == 0 then
        ns.Print(ns.L("还没有热门配点数据：装 GearInsight 更新器后每天自动更新", "No popular builds yet (the GearInsight updater refreshes them daily)"))
        return
    end
    if not popFrame then
        local f = CreateFrame("Frame", "GearInsightForeverPop", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(300, 40); f:SetPoint("CENTER", 0, 80); f:SetFrameStrata("DIALOG")
        f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0, 0, 0, 0.85)
        end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 10, -10)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 0, 0); close:SetScale(0.8)
        f.rows = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverPop") end
        popFrame = f
    end
    local f = popFrame
    f.title:SetText(ns.L("热门配点 · ", "Popular builds · ") .. ns.L(ns.Data.classCn[cls] or cls, cls))
    for _, r in ipairs(f.rows) do r.text:Hide(); r.btn:Hide() end
    for i, b in ipairs(list) do
        if i > 5 then break end
        local r = f.rows[i]
        if not r then
            r = { text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                  btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate") }
            r.btn:SetSize(60, 20); r.btn:SetText(ns.L("套用", "Apply"))
            f.rows[i] = r
        end
        r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", 12, -12 - i * 24)
        r.text:SetText(ns.EnSafe((b.split or "") .. "  |cff999999" .. (b.n or 0) .. ns.L(" 人在用", " players") .. "|r"))
        r.btn:ClearAllPoints(); r.btn:SetPoint("TOPRIGHT", -12, -9 - i * 24)
        r.btn:SetScript("OnClick", function() if ns.ApplyTalentCode(b.code) then f:Hide() end end)
        r.text:Show(); r.btn:Show()
    end
    f:SetHeight(24 + math.min(#list, 5) * 24 + 14)
    f:Show()
end

-- 天赋面板（经典 Blizzard_TalentUI 按需加载）旁边挂两个小按钮：热门配点 / 发到手机
local function attachTalentButtons()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf or tf.__gifBtns then return end
    tf.__gifBtns = true
    local a = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
    a:SetSize(96, 20); a:SetPoint("TOPRIGHT", tf, "BOTTOMRIGHT", -40, 76)
    a:SetText(ns.L("GI 热门配点", "GI builds")); a:SetScript("OnClick", ns.ShowPopBuilds)
    local b = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
    b:SetSize(96, 20); b:SetPoint("RIGHT", a, "LEFT", -4, 0)
    b:SetText(ns.L("发到手机", "To phone")); b:SetScript("OnClick", ns.ShowTalentQR)
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_TalentUI" then pcall(attachTalentButtons) end
    end)
    pcall(attachTalentButtons)
end)
