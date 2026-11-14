-- 当前等级职业训练师可学的技能（共建看板 GI-224「當前等級訓練師可學技能：在天賦頁面顯示，可能的話進主城提醒去學習技能」）
-- 11-13 做完（原 11-11 版 HOLD 的原因见 _hold.txt）：
--   数据 = TrainNowData.lua（scripts/gi_forever_trainnow_data.py）：开服客户端 DB2 技能表 × 玩家在训练师窗口实测的「技能 + 需要等级 + 原价」，
--     两边对得上才收；不再读升级规划的 ns.Data.spells（那份在按需加载的 _Plan 里，进城提醒一读就把 12 MB 的子插件拉进来，且含任务 / AQ 书技能）
--   会不会 = IsSpellKnown / IsPlayerSpell；同一技能各级分开列（训练师不能跳级学）；天赋 / 种族 / 任务给的技能要先会任意一级才列
--   ① 天赋页右上角「训练师可学 N 个」：点开盖在天赋页上的一层 —— 现在能学（名字 / 需要等级 / 原价）、下一批、本级已学（可折叠）、找最近的训练师
--   ② 进主城（ns.CityPlates.InCity 同一判定）且有能学的：聊天框一行提醒（不弹窗），每次登录每个等级最多一次；设置项「进城提醒可学技能」可关
local _, ns = ...

local TN = {}
ns.TrainNow = TN

local function L(cn, en) return ns.L(cn, en) end

-- ---------- 设置（存档键沿用 ui.trainRemind，nil = 开）----------
function TN.RemindOn() return not (ns.db and ns.db.ui and ns.db.ui.trainRemind == false) end
function TN.SetRemindOn(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.trainRemind = on and true or false
end

-- ---------- 数据 ----------
local parsed = {}
-- 某职业的全部行：{ lv, id, c(原价铜 / nil = 没价 / -1 = 前置), r(rank), need, fac, n(简体名) }
function TN.Rows(cls)
    if parsed[cls] then return parsed[cls] end
    local src = ns.TrainNowData and ns.TrainNowData[cls]
    if type(src) ~= "string" or src == "" then return nil end
    local rows = {}
    for rec in src:gmatch("[^;]+") do
        local lv, id, c, r, fl, n = rec:match("^(%d+),(%d+),(%-?%d*),(%d*),(%a*),(.+)$")
        if lv then
            rows[#rows + 1] = { lv = tonumber(lv), id = tonumber(id), c = tonumber(c), r = tonumber(r) or 0,
                need = fl:find("N") ~= nil, fac = fl:match("[AH]"), n = n }
        end
    end
    local cnt = {}
    for _, e in ipairs(rows) do if e.c ~= -1 then cnt[e.n] = (cnt[e.n] or 0) + 1 end end
    for _, e in ipairs(rows) do e.multi = (cnt[e.n] or 0) > 1 end
    parsed[cls] = rows
    return rows
end

local function known(id)
    if not id or id == 0 then return nil end
    local any = false
    if IsSpellKnown then
        any = true
        local ok, v = pcall(IsSpellKnown, id)
        if ok and v then return true end
    end
    if IsPlayerSpell then
        any = true
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v then return true end
    end
    if any then return false end
end
TN.Known = known

local function myFac()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
end

-- 扫一遍：{ now = 现在能学, nextLv, next = 下一批, done = 本级（含上一级）已学, cost = 现在能学的原价合计, noCost = 没价的个数, data = 有没有数据 }
function TN.Scan(cls, lv)
    cls = cls or (ns.MyClass and ns.MyClass())
    lv = lv or (UnitLevel and UnitLevel("player")) or 1
    local res = { now = {}, next = {}, done = {}, cost = 0, noCost = 0, cls = cls, lv = lv }
    local rows = cls and TN.Rows(cls)
    if not rows then return res end
    res.data = true
    local fac = myFac()
    local anyKnown, kc, topKnown = {}, {}, {}
    for _, e in ipairs(rows) do
        local k = known(e.id)
        kc[e] = k
        if k then
            anyKnown[e.n] = true
            if e.lv > (topKnown[e.n] or 0) then topKnown[e.n] = e.lv end
        end
    end
    -- 会了高一级 = 低几级当会了（客户端万一只认最高一级，也不会把低级的当成「没学」列出来）
    for _, e in ipairs(rows) do
        if kc[e] == false and e.lv < (topKnown[e.n] or 0) then kc[e] = true end
    end
    local nextLv
    for _, e in ipairs(rows) do
        local ok = e.c ~= -1 and not (e.fac and fac and e.fac ~= fac) and not (e.need and not anyKnown[e.n])
        if ok then
            local k = kc[e]
            if e.lv <= lv then
                if k == false then
                    res.now[#res.now + 1] = e
                    if e.c then res.cost = res.cost + e.c else res.noCost = res.noCost + 1 end
                elseif k and e.lv >= lv - 1 then
                    res.done[#res.done + 1] = e
                end
            elseif k == false and (not nextLv or e.lv < nextLv) then
                nextLv = e.lv
            end
        end
    end
    if nextLv then
        for _, e in ipairs(rows) do
            if e.lv == nextLv and e.c ~= -1 and not (e.fac and fac and e.fac ~= fac) and not (e.need and not anyKnown[e.n]) and kc[e] == false then
                res.next[#res.next + 1] = e
            end
        end
    end
    res.nextLv = nextLv
    return res
end

-- 兼容 11-11 版的接口：现在能学的列表
function TN.List(cls, lv) return TN.Scan(cls, lv).now end

-- 名字：客户端自己给的官方名（繁体客户端就是繁体）；中文界面配英文客户端时用数据里的简体名；设置选了繁體再转
local function clientLoc() return GetLocale and GetLocale() or "zhCN" end
function TN.Name(e)
    local n
    local loc = clientLoc()
    local wantZh = ns.zh
    local clientZh = loc == "zhCN" or loc == "zhTW"
    if (not wantZh or clientZh) and GetSpellInfo then
        local ok, v = pcall(GetSpellInfo, e.id)
        if ok and type(v) == "string" and v ~= "" then n = v end
    end
    n = n or e.n
    if ns.tw and loc ~= "zhTW" and ns.ToTW then n = ns.ToTW(n) end
    return n
end

function TN.Label(e)
    local n = TN.Name(e)
    if (e.r or 0) > 0 and e.multi then n = n .. string.format(L("（等级%d）", " (Rank %d)"), e.r) end
    return n
end

function TN.Money(c)
    if not c then return L("价钱未知", "price unknown") end
    if c == 0 then return L("免费", "free") end
    if GetCoinTextureString then local ok, s = pcall(GetCoinTextureString, c); if ok and type(s) == "string" and s ~= "" then return s end end
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. L("金", "g") end
    if s > 0 then t[#t + 1] = s .. L("银", "s") end
    if cu > 0 then t[#t + 1] = cu .. L("铜", "c") end
    return table.concat(t, " ")
end

function TN.Names(list, max)
    local t = {}
    for i, e in ipairs(list) do
        if max and i > max then t[#t + 1] = L("等", "...") break end
        t[#t + 1] = TN.Label(e)
    end
    return table.concat(t, L("、", ", "))
end

local function icon(e)
    local tex = GetSpellTexture and select(2, pcall(GetSpellTexture, e.id))
    if type(tex) == "string" or type(tex) == "number" then return tex end
end

-- ---------- ① 天赋页：按钮 + 盖在页面上的一层 ----------
local btn, panel, pageFrame
local showDone = false
local ROW_H, PANEL_W = 18, 646

local function paintBtn()
    if not btn then return end
    local s = TN.Scan()
    btn.scan = s
    if not s.data then
        btn:SetText(L("|cff9a9a9a训练师技能|r", "|cff9a9a9aTrainer spells|r"))
    elseif #s.now > 0 then
        btn:SetText(string.format(L("|cff33ff99训练师可学 %d 个|r", "|cff33ff99%d to train|r"), #s.now))
    else
        btn:SetText(L("|cff9a9a9a本级技能都学了|r", "|cff9a9a9aAll trained|r"))
    end
    if pageFrame and rawget(pageFrame, "_sub") then
        pageFrame._sub:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    end
end
TN.PaintBtn = paintBtn

local function line(i)
    local body = panel.body
    if not rawget(panel, "lines") then panel.lines = {} end
    local r = panel.lines[i]
    if not r then
        r = CreateFrame("Button", nil, body)
        r:SetSize(PANEL_W - 40, ROW_H)
        r:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_H)
        r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(16, 16); r.ic:SetPoint("LEFT", 4, 0)
        r.a = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.a:SetPoint("LEFT", 24, 0); r.a:SetWidth(330); r.a:SetJustifyH("LEFT"); r.a:SetWordWrap(false)
        r.b = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.b:SetPoint("LEFT", 360, 0); r.b:SetWidth(80); r.b:SetJustifyH("LEFT")
        r.c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.c:SetPoint("LEFT", 440, 0); r.c:SetWidth(160); r.c:SetJustifyH("RIGHT")
        r:SetScript("OnEnter", function(self)
            if not self.e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.e.id)
            if not ok then GameTooltip:AddLine(TN.Label(self.e), 1, 1, 1) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.lines[i] = r
    end
    r.e = nil; r:SetScript("OnClick", nil)
    r.ic:Hide(); r.a:SetText(""); r.b:SetText(""); r.c:SetText("")
    r.a:SetTextColor(1, 1, 1); r.b:SetTextColor(0.75, 0.75, 0.75); r.c:SetTextColor(1, 1, 1)
    r:Show()
    return r
end

local function spellLine(i, e, dim)
    local r = line(i)
    r.e = e
    local tex = icon(e)
    if tex then r.ic:SetTexture(tex); r.ic:Show() end
    r.a:SetText(TN.Label(e))
    r.b:SetText(string.format(L("%d 级", "Lv %d"), e.lv))
    r.c:SetText(TN.Money(e.c))
    if dim then r.a:SetTextColor(0.6, 0.6, 0.6); r.c:SetTextColor(0.6, 0.6, 0.6) end
end

local function headLine(i, text, r1, g1, b1)
    local r = line(i)
    r.a:SetWidth(PANEL_W - 60)
    r.a:SetText(text)
    r.a:SetTextColor(r1 or 1, g1 or 0.82, b1 or 0)
    return r
end

-- 画盖层（测试里也直接调）：返回 { 每行文字 }
function TN.PaintPanel()
    if not panel then return nil end
    local s = TN.Scan()
    for _, r in ipairs(rawget(panel, "lines") or {}) do r:Hide(); r.a:SetWidth(330) end
    local i, out = 0, {}
    local function add(fn, ...)
        i = i + 1
        local r = fn(i, ...)
        out[#out + 1] = (panel.lines[i].a:GetText() or "") .. "|" .. (panel.lines[i].b:GetText() or "") .. "|" .. (panel.lines[i].c:GetText() or "")
        return r
    end
    local cc = ns.CLASS_COLOR and ns.CLASS_COLOR[s.cls or ""]
    local cn = type(ns.Data) == "table" and rawget(ns.Data, "classCn")
    local clsName = L(cn and cn[s.cls or ""] or s.cls or "", s.cls or "")
    panel.title:SetText(string.format(L("训练师可学技能 · %s%s|r · %d 级", "Trainable spells · %s%s|r · level %d"),
        cc and ("|cff" .. cc) or "|cffffffff", clsName, s.lv))
    if not s.data then
        add(headLine, L("这个职业还没有训练师技能数据。", "No trainer spell data for this class yet."), 0.8, 0.8, 0.8)
    else
        if #s.now > 0 then
            local tot = TN.Money(s.cost) .. (s.noCost > 0 and string.format(L("（另有 %d 个价钱未知）", " (+%d unknown)"), s.noCost) or "")
            add(headLine, string.format(L("现在就能学 %d 个 · 原价合计 %s", "Learn now: %d · total %s"), #s.now, tot))
            for _, e in ipairs(s.now) do add(spellLine, e) end
        else
            add(headLine, L("这一级能学的都学了", "Everything up to your level is trained"), 0.2, 1, 0.6)
        end
        if s.nextLv then
            add(headLine, string.format(L("下一批：%d 级 · %d 个", "Next: level %d · %d"), s.nextLv, #s.next), 0.8, 0.8, 0.8)
            for _, e in ipairs(s.next) do add(spellLine, e, true) end
        elseif s.lv >= 60 or #s.now == 0 then
            add(headLine, L("后面没有要去训练师那里学的了", "Nothing more to learn from your trainer"), 0.6, 0.6, 0.6)
        end
        if #s.done > 0 then
            local r = add(headLine, string.format(showDone and L("本级已学 %d 个 ▼（点一下收起）", "Learned this level: %d (click to hide)")
                or L("本级已学 %d 个 ▶（点一下展开）", "Learned this level: %d (click to show)"), #s.done), 0.6, 0.6, 0.6)
            r:SetScript("OnClick", function() showDone = not showDone; TN.PaintPanel() end)
            if showDone then for _, e in ipairs(s.done) do add(spellLine, e, true) end end
        end
    end
    panel.body:SetHeight(math.max(10, i * ROW_H))
    panel.note:SetText(string.format(L("数据：开服客户端技能表 × %d 台玩家设备在训练师处实测（%s）；价钱是原价，声望折扣以训练师为准。天赋 / 种族 / 任务给的技能，会了第一级才列后面几级",
        "Data: Forever client spell table x trainer windows seen by %d players (%s). Prices before reputation discount."),
        ns.TrainNowData and ns.TrainNowData.devices or 0, ns.TrainNowData and ns.TrainNowData.built or ""))
    return out, s
end

local function ensurePanel(p)
    if panel then return panel end
    panel = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetPoint("TOPLEFT", 0, -38); panel:SetPoint("BOTTOMRIGHT", 0, 0)
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        panel:SetBackdropColor(0.04, 0.05, 0.07, 0.98); panel:SetBackdropBorderColor(0.2, 1, 0.6, 0.5)
    end
    if panel.SetFrameLevel and p.GetFrameLevel then panel:SetFrameLevel((p:GetFrameLevel() or 1) + 30) end
    panel:EnableMouse(true)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -8)
    panel.scroll, panel.body = ns.Scroll(panel, 4, -28, PANEL_W - 30, 474 - 38 - 92)
    panel.note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.note:SetPoint("BOTTOMLEFT", 12, 34); panel.note:SetPoint("BOTTOMRIGHT", -12, 34)
    panel.note:SetJustifyH("LEFT")
    local go = ns.Button(panel, L("找最近的职业训练师", "Nearest class trainer"), 160, 22, function() if ns.Trainers and ns.Trainers.Go then ns.Trainers.Go() end end)
    go:SetPoint("BOTTOMLEFT", 8, 6)
    panel.go = go
    local close = ns.Button(panel, L("收起", "Close"), 70, 22, function() panel:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -8, 6)
    panel:SetScript("OnShow", function() pcall(TN.PaintPanel) end)
    panel:Hide()
    return panel
end

function TN.TogglePanel(show)
    if not pageFrame then return false end
    ensurePanel(pageFrame)
    if show == nil then show = not panel:IsShown() end
    if show then panel:Show(); pcall(TN.PaintPanel) else panel:Hide() end
    return show
end
TN._Panel = function() return panel end   -- 测试用
TN._Btn = function() return btn end

local function attach(p)
    if not p or (btn and pageFrame == p) then return end
    -- 天赋页框换了（战斗中点开的占位框脱战后按真页重画）：按钮 / 盖层跟着新框重建
    if btn then btn:Hide() end
    if panel then panel:Hide(); panel = nil end
    pageFrame = p
    btn = ns.Button(p, "", 140, 20, function() TN.TogglePanel() end)
    btn:SetPoint("TOPRIGHT", -108, -7)   -- 「本页设置」（92 宽，贴右上角）的左边
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        local s = self.scan or TN.Scan()
        GameTooltip:AddLine(L("当前等级去职业训练师那里能学", "Learnable from your class trainer now"), 1, 0.82, 0)
        if not s.data then
            GameTooltip:AddLine(L("这个职业还没有训练师技能数据", "No trainer spell data for this class yet"), 0.8, 0.8, 0.8)
        elseif #s.now == 0 then
            GameTooltip:AddLine(L("这一级能学的都学了", "Nothing left to train at this level"), 0.8, 0.8, 0.8)
            if s.nextLv then GameTooltip:AddLine(string.format(L("下一批在 %d 级（%d 个）", "Next batch at level %d (%d)"), s.nextLv, #s.next), 0.8, 0.8, 0.8) end
        else
            for k, e in ipairs(s.now) do
                if k > 12 then GameTooltip:AddLine(string.format(L("……还有 %d 个", "...%d more"), #s.now - 12), 0.6, 0.6, 0.6) break end
                GameTooltip:AddDoubleLine(TN.Label(e), string.format(L("%d 级", "Lv %d"), e.lv), 1, 1, 1, 0.6, 0.6, 0.6)
            end
        end
        GameTooltip:AddLine(L("点一下：看完整列表（价钱 / 下一批 / 本级已学）", "Click: full list (prices / next batch / learned)"), 0.2, 1, 0.6, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    paintBtn()
end

-- 包住天赋页的 build / refresh（PageTalent.lua 一行不改）
-- 11-13 重构第 4 期：天赋页在按需加载的 _Class 里 —— 拆分时先是占位页、点开才换成真页；合并打包时天赋页晚于这个文件登记。
--   → 已登记的现在包；以后登记 / 顶替进来的经 UI.lua 的 ns._PageHooks 再包（认 build 换没换，换了才包，attach 本身只建一次按钮）
local function hookOne(pg)
    if pg.key ~= "talent" or pg.lazy or not pg.build or pg.build == pg._giTrainNowB then return end
    pg._giTrainNow = true
    local b, r = pg.build, pg.refresh
    pg.build = function(p, ...) local res = b(p, ...); pcall(attach, p); return res end
    pg.refresh = function(...) if r then r(...) end; pcall(paintBtn); if panel and panel:IsShown() then pcall(TN.PaintPanel) end end
    pg._giTrainNowB = pg.build
end
TN._HookOne = hookOne
for _, pg in ipairs(ns._Pages or {}) do hookOne(pg) end
ns._PageHooks = ns._PageHooks or {}
table.insert(ns._PageHooks, hookOne)

-- ---------- ② 进主城提醒 ----------
local told = {}   -- [等级] = true：这次登录这个等级已经提醒过
function TN._ResetTold() told = {} end   -- 测试用

local LINK_GO = "GIFTN:go"
local LINK_LIST = "GIFTN:list"
local function link(key, text) return "|cff33ff99|Haddon:" .. key .. "|h[" .. text .. "]|h|r" end

function TN.CheckRemind()
    if not TN.RemindOn() then return false end
    local CP = ns.CityPlates
    if not (CP and CP.InCity) then return false end
    local okc, inCity = pcall(CP.InCity)
    if not (okc and inCity) then return false end
    local lv = UnitLevel and UnitLevel("player") or 1
    if told[lv] then return false end
    local s = TN.Scan(nil, lv)
    if #s.now == 0 then return false end
    told[lv] = true
    local cost = s.cost > 0 and string.format(L("，原价合计 %s", ", %s total"), TN.Money(s.cost)) or ""
    ns.Print(string.format(L("到主城了：职业训练师那里有 %d 个技能可以学（%s）%s  ", "In town: %d spells to learn at your class trainer (%s)%s  "),
        #s.now, TN.Names(s.now, 4), cost)
        .. link(LINK_GO, L("找最近的职业训练师", "Nearest class trainer")) .. " "
        .. link(LINK_LIST, L("看列表", "List")))
    return true
end

-- 点聊天里的 [找最近的职业训练师] / [看列表]：新客户端走 EventRegistry「SetItemRef」，老的走 SetItemRef 后钩（同一下两边都到 → 0.3 秒内只认一次）
local lastClick = 0
function TN.Click(l)
    if type(l) ~= "string" then return false end
    local key = l:match("^addon:(GIFTN:%a+)")
    if not key then return false end
    local now = GetTime and GetTime() or 0
    if now - lastClick < 0.3 and now > 0 then return false end
    lastClick = now
    if key == LINK_GO then
        if ns.Trainers and ns.Trainers.Go then ns.Trainers.Go() end
    elseif key == LINK_LIST then
        if ns.OpenPage then ns.OpenPage("talent") end
        TN.TogglePanel(true)
    end
    return true
end
if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, l) pcall(TN.Click, l) end, TN)
end
if hooksecurefunc and SetItemRef then pcall(hooksecurefunc, "SetItemRef", function(l) pcall(TN.Click, l) end) end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript("OnEvent", function(_, e)
    if btn and btn:IsVisible() then pcall(paintBtn) end
    if panel and panel:IsShown() then pcall(TN.PaintPanel) end
    if e == "LEARNED_SPELL_IN_TAB" or e == "SPELLS_CHANGED" then return end
    -- 升级 / 进图后技能书、地图要过一会儿才准；连着来的事件只排一次
    if pending then return end
    pending = true
    local function run() pending = nil; pcall(TN.CheckRemind) end
    if C_Timer and C_Timer.After then C_Timer.After(3, run) else run() end
end)
