-- 11-10 用户「无限插件增加正式服那样的版本更新弹窗，每次版本只弹一次」：照正式服 main/WhatsNew.lua。
-- 内容 = WhatsNewData.lua（ns.WhatsNewData，发版前 scripts/gi_forever_whatsnew.py 从 dist/forever_release/changelog_<版本>.md 生成）。
-- 规则：
--   · 登录 / 重载后 4 秒弹（战斗中等脱战）；ns.db.whatsNewSeen == 当前 toc 版本 → 不弹。
--   · 每个版本只弹一次：弹出来就记为看过（和正式服不同：正式服 Esc 关了下次还弹；用户这次要的是「只弹一次」）。
--   · WhatsNewData 的版本和 toc 版本对不上（本地开发版 / 忘了生成）→ 不弹，免得拿旧版本的日志糊弄人。
--   · /gi whatsnew（/gi 更新）随时再看一次（不改看过的记录）。
--   · 11-16 GI-286 用户「默认开，更新后弹框可一键关」：WhatsNewData.toggles = { { id = 设置项 id, zh, en }, ... } 时，
--     正文下面画一排「新功能开关」勾选框，绑同一个设置项（ns.SettingItem → get / set，点了 ns.RefreshSettings），
--     和设置页写的是同一份存档；没登记 / 不可用（子插件没加载、HOLD、职业专属）的项不画；没有 toggles = 弹窗和以前一样。
local _, ns = ...
-- 11-17 界面重构第 6a 期：功能开关「whatsnew」—— 正文包成函数，读完存档关着就不跑（见 Features.lua 的 ns.FeatureDefer；正文没缩进是为了不动原有行）
local function body()
local L = function(cn, en) return ns.L(cn, en) end

local W = {}
ns.WhatsNew = W
W.DELAY = 4
W.BASE_H = 420
W.TOGGLE_ROW_H = 26

local frame
local function build()
    if frame then return frame end
    local f = CreateFrame("Frame", "GearInsightForeverWhatsNew", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, W.BASE_H); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    if f.SetToplevel then pcall(f.SetToplevel, f, true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.05, 0.96); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.9)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16); f.title:SetJustifyH("CENTER")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4); f.sub:SetJustifyH("CENTER")
    local sf = CreateFrame("ScrollFrame", "GearInsightForeverWhatsNewScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -58); sf:SetPoint("BOTTOMRIGHT", -36, 52)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(456, 10)
    sf:SetScrollChild(child)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 2, -2); fs:SetWidth(452); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    if fs.SetSpacing then pcall(fs.SetSpacing, fs, 4) end
    f.body, f.child, f.sf = fs, child, sf
    -- 新功能开关区（正文和底部按钮之间；没有 toggles 时隐藏）
    local tg = CreateFrame("Frame", nil, f)
    tg:SetPoint("BOTTOMLEFT", 20, 50); tg:SetPoint("BOTTOMRIGHT", -20, 50); tg:SetHeight(10)
    tg.head = tg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tg.head:SetPoint("TOPLEFT", 2, 0); tg.head:SetJustifyH("LEFT")
    tg.checks, tg.list = {}, {}
    tg:Hide()
    f.tg = tg
    if ns.OnSettingsRefresh then ns.OnSettingsRefresh(function() W.RefreshToggles() end) end   -- 设置页那边改了，弹窗这边跟着变
    f.ok = ns.Button(f, L("知道了", "Got it"), 120, 24, function() f:Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", -20, 16)
    f.more = ns.Button(f, L("打开资讯页", "Open News"), 120, 24, function()
        f:Hide()
        if ns.ToggleMain then pcall(ns.ToggleMain, "news") end
    end)
    f.more:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    -- 11-17 用户「这些弹出的功能都确保能永久关闭」：左下「以后不弹」= 关掉功能中心「新版说明」（存档 ns.db.feat.whatsnew = false，同一个键），
    --   以后发新版也不弹；聊天框说一次怎么找回（窗口与提醒 / 功能中心）。/gi 更新 要等重新打开、重载后才有
    f.never = ns.Button(f, L("以后不弹", "Don't show again"), 110, 24, function() W.Never() end)
    f.never:SetPoint("BOTTOMLEFT", 20, 16)
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中会被拦
    x:SetPoint("TOPRIGHT", 2, 2)
    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverWhatsNew") end
    f:Hide()
    frame = f
    return f
end

-- 弹窗里的勾选框跟着设置刷新
function W.RefreshToggles()
    local tg = frame and frame.tg
    if not tg then return end
    for _, r in ipairs(tg.list) do
        local ok, v = pcall(r.it.get)
        r.c:SetChecked(ok and v and true or false)
    end
end

local function toggleCheck(tg, i)
    local c = tg.checks[i]
    if c then return c end
    c = CreateFrame("CheckButton", nil, tg, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0); c.label:SetJustifyH("LEFT"); c.label:SetWidth(196)
    if c.label.SetWordWrap then c.label:SetWordWrap(false) end
    c:SetScript("OnClick", function(self)
        local r = tg.list[i]
        if not r then return end
        local ok, err = pcall(r.it.set, self:GetChecked() and true or false)
        if not ok and ns.Print then ns.Print(tostring(err)) end
        if ns.RefreshSettings then pcall(ns.RefreshSettings) end   -- 设置页 / 抽屉齿轮画着的同一个开关跟着刷（也会回调 W.RefreshToggles）
    end)
    tg.checks[i] = c
    return c
end

-- 按 d.toggles 画开关，返回开关区占的高度（0 = 没有）
function W.LayoutToggles(f, d)
    local tg = f.tg
    local list = {}
    local src = type(d) == "table" and type(d.toggles) == "table" and d.toggles or {}
    for _, t in ipairs(src) do
        local it = type(t) == "table" and ns.SettingItem and ns.SettingItem(t.id)
        if it then list[#list + 1] = { it = it, t = t } end
    end
    for _, c in ipairs(tg.checks) do c:Hide() end
    local h = 0
    if #list > 0 then
        tg.head:SetText(L("新功能开关（不想要的直接取消）", "New features (untick to turn off)"))
        local rows = math.ceil(#list / 2)
        h = 20 + rows * W.TOGGLE_ROW_H
        for i, r in ipairs(list) do
            local c = toggleCheck(tg, i)
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", tg, "TOPLEFT", col * 236, -18 - row * W.TOGGLE_ROW_H)
            local name = ns.L(r.t.zh or "", r.t.en or r.t.zh or "")
            if name == "" then name = ns.SettingText and ns.SettingText(r.it.text) or tostring(r.t.id) end
            c.label:SetText(name)
            r.c = c
            c:Show()
        end
    end
    tg.list = list
    tg:SetHeight(math.max(10, h))
    if h > 0 then tg:Show() else tg:Hide() end
    W.RefreshToggles()
    f.sf:ClearAllPoints()
    f.sf:SetPoint("TOPLEFT", 20, -58); f.sf:SetPoint("BOTTOMRIGHT", -36, 52 + h)
    f:SetHeight(W.BASE_H + h)
    return h
end

-- 更新日志原文 → 显示文本：「【位面】」/ 英文不带「- 」的行 = 小标题（金色），「- 」开头 = 条目（换成 •）
function W.Format(text)
    local out = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local item = line:match("^[-*]%s*(.+)$")
            if item then
                out[#out + 1] = "• " .. item
            else
                if #out > 0 then out[#out + 1] = "" end
                out[#out + 1] = "|cffffd100" .. line .. "|r"
            end
        end
    end
    return table.concat(out, "\n")
end

-- 当前版本的更新内容；版本对不上返回 nil
function W.Current()
    local ver = ns.AddonVersion and ns.AddonVersion() or ""
    local d = ns.WhatsNewData
    if ver == "" or type(d) ~= "table" or d.v ~= ver then return nil, ver end
    return d, ver
end

-- preview = true：命令行手动看，不检查也不改「看过」
function W.Show(preview)
    local d, ver = W.Current()
    if not d then
        if preview then ns.Print(string.format(L("当前版本 %s 还没有更新说明", "No release notes for version %s yet"), tostring(ver))) end
        return false
    end
    local f = build()
    f.title:SetText(string.format(L("GearInsight 无限版已更新到 %s", "GearInsight Forever updated to %s"), ver))
    f.sub:SetText((d.date and d.date ~= "" and (d.date .. "  ·  ") or "") .. L("这次更新了什么", "What's new"))
    local body = ns.L(d.zh, d.en or d.zh)
    f.body:SetText(ns.EnSafe and ns.EnSafe(W.Format(body)) or W.Format(body))
    local h = (f.body.GetStringHeight and f.body:GetStringHeight()) or 200
    f.child:SetHeight(math.max(10, (h or 200) + 8))
    W.LayoutToggles(f, d)
    if f.sf.SetVerticalScroll then pcall(f.sf.SetVerticalScroll, f.sf, 0) end
    if not preview and ns.db then ns.db.whatsNewSeen = ver end
    f:Show()
    return true
end

function W.Never()
    if frame then frame:Hide() end
    if ns.SetFeature then ns.SetFeature("whatsnew", false) elseif ns.db then ns.db.feat = ns.db.feat or {}; ns.db.feat.whatsnew = false end
    if ns.CloseHint then
        ns.CloseHint("whatsnew", L("新版说明弹窗已永久关闭，以后更新也不弹。找回：GI 菜单 → 窗口与提醒 → 新版说明弹窗，或设置 → 功能 → 新版说明",
            "Update notes closed for good. Bring them back: GI menu > Windows & alerts > Update notes, or Settings > Features > What's new"))
    end
end

-- 该不该弹：返回 true = 弹了
function W.Check()
    if not ns.db then return false end
    local d, ver = W.Current()
    if not d or ns.db.whatsNewSeen == ver then return false end
    if InCombatLockdown and InCombatLockdown() then
        W.ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    return W.Show(false)
end

local ev = CreateFrame("Frame")
W.ev = ev
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(W.Check)
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(W.DELAY, function() pcall(W.Check) end)
    else
        pcall(W.Check)
    end
end)
W._event = ev:GetScript("OnEvent")   -- 测试用

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.whatsnew = function() pcall(W.Show, true) end
ns.ExtraSlash["更新"] = ns.ExtraSlash.whatsnew
end
if ns.FeatureDefer then ns.FeatureDefer("whatsnew", body) else body() end
