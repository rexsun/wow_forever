-- 无限主面板**右侧**「公会」页签（10-11 公会升级二期，docs/guild-growth-2026-10-design.md「插件」第 2 条）
--   装了 GuildInsight（已加载）：点页签打开它的「招募」页
--   装了没加载 / 被禁用：抽屉顶部状态卡给「启用并加载（仅本角色）」/「点击加载」，加载成功直接打开招募页（10-12 晚）
--   没装：右侧抽屉 = 只读招募列表（GuildRecruit.lua，更新器定期刷新）+ 安装引导 + 招募板二维码（带 realm）
-- 控件和抽屉逻辑在 GIWidgets.lua（W.AttachGuildTab，三服共用），这里只接线。
-- ⛔ HOLD 中（_hold.txt：GIWidgets.lua / GuildRecruit.lua / GuildTab.lua），测完用户点头再移出。
local _, ns = ...

-- ── 10-12 按 GuildInsight 的状态给入口（用户「这个也要加载吧」「可以检测是否有 GuildInsight，一键打开」）──────────
-- 抽屉顶部原来那张引导卡 = 状态卡；下面「正在招人的公会」列表照常显示。
--   已加载        → 点页签直接打开 GuildInsight 招募页（W.AttachGuildTab 原逻辑，不弹抽屉）
--   禁用          →「启用并加载（仅本角色）」：EnableAddOn(本角色) → LoadAddOn → 成功直接打开招募页；
--                   加载不了（不是按需加载的插件）→「已启用，/reload 后生效」+ /reload 按钮
--   装了没加载    →「点击加载」（同上）
--   战斗中        → 按钮置灰「脱战后可点」，PLAYER_REGEN_ENABLED 后恢复
--   没安装        → 一两句介绍 + 获取方式；按钮「了解」弹说明 + 招募板二维码
-- ⛔ 不直接调主插件的 GearInsight:ModulePlaceholder：它会把所在页的其它子框全藏起来（这里要留列表），
--    而且无限没有 DataLoader。样式照它：标题行 + 说明 + 金边红底按钮（UIPanelButtonTemplate），按钮文案同它。
-- ⛔ 抽屉排版在 GIWidgets.lua（五份逐字节相同，这里不碰）：只在它填充前换掉引导卡标题 / 正文的文字
--    （高度照常跟着文字走），再把加载按钮放在第一个按钮位、招募板按钮挪到第二个位。
local GINS = "GuildInsight"
local CARD_PAD, CARD_BW = 12, 162   -- 同 GIWidgets 抽屉：PAD = 12，按钮宽 = (356 - 24 - 8) / 2

local function WL(cn, en, tw)
    local W = ns.W or _G.GIWidgets
    if W and W.L then return W.L(cn, en, tw) end
    return cn
end

-- PLAYER_REGEN_DISABLED 触发时 InCombatLockdown 可能还是 false → 自己记一个标记
local combatFlag = nil
local function inCombat()
    if combatFlag then return true end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- 无限客户端可能没有 C_AddOns → 退回老的全局函数
local function addonApi(name)
    local CA = C_AddOns
    if CA and CA[name] then return CA[name] end
    return _G[name]
end

local function textH(fs, fallback)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = fallback end
    return math.ceil(h)
end

-- "loaded" / "missing" / "disabled" / "idle"（装了、启用了、还没加载）
local function ginsState()
    local gi = _G.GuildInsight
    if type(gi) == "table" and gi.UI then return "loaded" end
    local isLoaded = addonApi("IsAddOnLoaded")
    if isLoaded then
        local ok, v = pcall(isLoaded, GINS)
        if ok and v then return "loaded" end
    end
    local exists, reason = nil, nil
    if C_AddOns and C_AddOns.DoesAddOnExist then
        local ok, ex = pcall(C_AddOns.DoesAddOnExist, GINS)
        if ok then exists = ex and true or false end
    end
    local info = addonApi("GetAddOnInfo")
    if info then
        local ok, nm, _, _, _, why = pcall(info, GINS)
        if ok then
            reason = why
            if exists == nil then exists = (nm ~= nil and why ~= "MISSING") end
        end
    end
    -- 两个接口都没有 = 没法判断 → 当没装（同 W.GuildAddonState）
    if not exists then return "missing" end
    local who = UnitName and UnitName("player")
    local st
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local ok, v = pcall(C_AddOns.GetAddOnEnableState, GINS, who)
        if ok then st = v end
    elseif GetAddOnEnableState then
        -- 老的全局接口参数顺序反过来：(角色, 插件)
        local ok, v = pcall(GetAddOnEnableState, who, GINS)
        if ok then st = v end
    end
    if st == 0 or reason == "DISABLED" then return "disabled" end
    return "idle"
end

-- 打开 GuildInsight（= /gins recruit 背后的入口）
local function openGins()
    local gi = _G.GuildInsight
    local ui = (type(gi) == "table") and gi.UI or nil
    if ui and ui.OpenRecruit then ui.OpenRecruit(); return true end
    if ui and ui.Toggle then
        if not (ui.IsShown and ui.IsShown()) then ui.Toggle() end
        return true
    end
    local slash = SlashCmdList and SlashCmdList.GUILDINSIGHT
    if slash then slash("recruit"); return true end
    return false
end

-- 返回 "opened" / "loaded" / "reload" / "fail" / "combat" / "missing"
local function loadGins(tab)
    if inCombat() then return "combat" end
    local s = ginsState()
    if s == "missing" then return "missing" end
    if s ~= "loaded" then
        local enabled = false
        if s == "disabled" then
            local en = addonApi("EnableAddOn")
            if en then
                pcall(en, GINS, UnitName and UnitName("player"))
                enabled = true
            end
        end
        local load = addonApi("LoadAddOn")
        local loaded, why = false, "NO_API"
        if load then
            local okc, a, b = pcall(load, GINS)
            if okc then loaded, why = a, b else why = a end
        end
        if not loaded then
            -- 不是按需加载的插件：启用后要 /reload 才进游戏（NOT_DEMAND_LOADED）
            if enabled or why == "NOT_DEMAND_LOADED" or why == "DISABLED" then
                tab._giNeedReload, tab._giErr = true, nil
                return "reload"
            end
            tab._giErr = tostring(why or "?")
            return "fail"
        end
        tab._giNeedReload, tab._giErr = nil, nil
        -- 进游戏后才加载：它 PLAYER_ENTERING_WORLD 里那一步（拉公会名单）错过了，补一次
        local gi = _G.GuildInsight
        local api = (type(gi) == "table") and gi.API or nil
        if type(api) == "table" and api.requestRoster then pcall(api.requestRoster) end
    end
    return openGins() and "opened" or "loaded"
end

local function showBoardQR(opts, url)
    local W = ns.W or _G.GIWidgets
    local title = WL("微信扫一扫 · 公会招募板", "Scan · guild board", "微信掃一掃 · 公會招募板")
    local shown = false
    if opts.qr then
        local ok, r = pcall(opts.qr, title, WL("按服务器、阵营、缺的职业筛，一键申请", "Filter by realm, faction and classes, then apply", "按伺服器、陣營、缺的職業篩，一鍵申請"), url)
        shown = ok and r ~= false
    end
    if not shown and W and W.Copy then W.Copy(url, title) end
end

-- 「了解」弹窗：说明 + 招募板二维码（画不出来 → 按钮弹二维码 / 复制框）
local function showAbout(tab, opts)
    local W = ns.W or _G.GIWidgets
    if not (W and W.Panel) then return end
    local p = rawget(tab, "_giAbout")
    if p and p:IsShown() then p:Hide(); return end
    local game = opts.game or "retail"
    local url = W.GuildBoardUrl and W.GuildBoardUrl(game) or ""
    if not p then
        p = W.Panel("GearInsightGuildAbout_" .. game, UIParent, 340, 420, WL("GuildInsight 公会插件", "GuildInsight guild addon", "GuildInsight 公會插件"))
        if W.Draggable then W.Draggable(p) end
        if p.SetFrameStrata then p:SetFrameStrata("DIALOG") end
        if p.SetClampedToScreen then p:SetClampedToScreen(true) end
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        p.txt = p.body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        p.txt:SetPoint("TOPLEFT", p.body, "TOPLEFT", 4, -4)
        p.txt:SetWidth(308); p.txt:SetJustifyH("LEFT")
        if p.txt.SetSpacing then p.txt:SetSpacing(3) end
        p.qrBox = CreateFrame("Frame", nil, p.body)
        p.cap = p.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p.cap:SetWidth(308); p.cap:SetJustifyH("CENTER")
        p.btn = CreateFrame("Button", nil, p.body, "UIPanelButtonTemplate")
        p.btn:SetSize(200, 24)
        tab._giAbout = p
    end
    p.txt:SetText(WL(
        "GuildInsight 是 GearInsight 出的公会插件：小程序里的入会申请经更新器同步进游戏，会长在游戏里一键邀请入会；还有日程报名、叫人组队、出货账本。\n\n获取方式：\n· GearInsight 更新器「我的插件」里勾选 GuildInsight\n· 或在 CurseForge 搜 GuildInsight\n\n装好后 /reload，点「公会」页签直接打开招募页。",
        "GuildInsight is the GearInsight guild addon: applications from the mini program sync into the game and officers invite with one click; it also has event signups, group calls and a loot ledger.\n\nHow to get it:\n· Tick GuildInsight under \"My addons\" in the GearInsight updater\n· Or search GuildInsight on CurseForge\n\nAfter installing, /reload and this tab opens its recruitment page.",
        "GuildInsight 是 GearInsight 出的公會插件：小程式裡的入會申請經更新器同步進遊戲，會長在遊戲裡一鍵邀請入會；還有日程報名、叫人組隊、出貨帳本。\n\n取得方式：\n· GearInsight 更新器「我的插件」裡勾選 GuildInsight\n· 或在 CurseForge 搜 GuildInsight\n\n裝好後 /reload，點「公會」頁籤直接打開招募頁。"))
    local y = 4 + textH(p.txt, 170) + 14
    local m
    if opts.qrEncode then
        local ok, mm = pcall(opts.qrEncode, url)
        if ok and type(mm) == "table" and #mm > 0 then m = mm end
    end
    p.qrBox:ClearAllPoints(); p.qrBox:SetPoint("TOP", p.body, "TOP", 0, -y)
    if m and W.DrawQR then
        local qs = W.DrawQR(p.qrBox, m, (#m <= 41) and 3 or 2)
        p.qrBox:Show()
        p.cap:SetText(WL("微信扫一扫 · 公会招募板", "Scan with WeChat · guild board", "微信掃一掃 · 公會招募板"))
        p.cap:ClearAllPoints(); p.cap:SetPoint("TOP", p.qrBox, "BOTTOM", 0, -6)
        p.cap:Show(); p.btn:Hide()
        y = y + (tonumber(qs) or 0) + 6 + 14
    else
        p.qrBox:Hide(); p.cap:Hide()
        p.btn:SetText(WL("微信扫码看招募板", "Guild board (QR)", "微信掃碼看招募板"))
        p.btn:SetScript("OnClick", function() showBoardQR(opts, url) end)
        p.btn:ClearAllPoints(); p.btn:SetPoint("TOP", p.body, "TOP", 0, -y)
        p.btn:Show()
        y = y + 24
    end
    p:SetHeight(42 + y + 16)
    p:Show()
end

-- 状态卡内容：head / body / 按钮文字 act / 能不能点 on / 点了干什么 fn / 第二个位留哪个按钮 keep（qr | copy）
local function cardFor(tab, opts)
    local W = ns.W or _G.GIWidgets
    local s = ginsState()
    if s ~= "loaded" and s ~= "missing" and rawget(tab, "_giNeedReload") then s = "reload" end
    local card = { state = s, on = true, keep = "qr" }
    local function loadClick()
        local r = loadGins(tab)
        if r == "opened" then
            local d = rawget(tab, "_drawer")
            if d then d:Hide() end
            if W and W.SelectTab then W.SelectTab(tab, false) end
            return
        end
        if tab._giRefresh then tab._giRefresh() end
    end
    if s == "missing" then
        card.head = WL("GuildInsight 公会插件", "GuildInsight guild addon", "GuildInsight 公會插件")
        card.body = WL("GearInsight 出的公会插件：小程序里的入会申请同步进游戏，会长一键邀请入会。\n获取：GearInsight 更新器「我的插件」里勾选，或在 CurseForge 搜 GuildInsight。",
            "The GearInsight guild addon: applications from the mini program sync into the game, invite with one click.\nGet it: tick it under \"My addons\" in the GearInsight updater, or search GuildInsight on CurseForge.",
            "GearInsight 出的公會插件：小程式裡的入會申請同步進遊戲，會長一鍵邀請入會。\n取得：GearInsight 更新器「我的插件」裡勾選，或在 CurseForge 搜 GuildInsight。")
        card.act = WL("了解", "Learn more", "了解")
        card.fn = function() showAbout(tab, opts) end
        card.keep = "copy"
        return card
    end
    if s == "reload" then
        card.head = WL("GuildInsight 公会插件已启用", "GuildInsight is enabled", "GuildInsight 公會插件已啟用")
        card.body = WL("|cff66ff66已启用，/reload 后生效。|r\n重载界面后，点「公会」页签直接打开招募页。",
            "|cff66ff66Enabled - takes effect after /reload.|r\nAfter reloading, this tab opens its recruitment page.",
            "|cff66ff66已啟用，/reload 後生效。|r\n重載介面後，點「公會」頁籤直接打開招募頁。")
        card.act = WL("/reload", "/reload", "/reload")
        card.fn = function() if ReloadUI then ReloadUI() end end
        return card
    end
    if s == "loaded" then
        card.head = WL("GuildInsight 公会插件已加载", "GuildInsight is loaded", "GuildInsight 公會插件已載入")
        card.body = WL("点下面的按钮打开招募页：申请在游戏里一键邀请入会。", "Open its recruitment page: invite applicants with one click.", "點下面的按鈕打開招募頁：申請在遊戲裡一鍵邀請入會。")
        card.act = WL("打开 GuildInsight", "Open GuildInsight", "打開 GuildInsight")
        card.fn = loadClick
        return card
    end
    if s == "disabled" then
        card.head = WL("GuildInsight 公会插件已安装，但没启用", "GuildInsight is installed but disabled", "GuildInsight 公會插件已安裝，但沒啟用")
        card.body = WL("不用回角色选择界面：点下面的按钮启用（仅本角色）并加载，成功后直接打开招募页，申请在游戏里一键邀请入会。",
            "No need to go back to character select: enable it for this character and load it now - its recruitment page opens right away.",
            "不用回角色選擇介面：點下面的按鈕啟用（僅本角色）並載入，成功後直接打開招募頁，申請在遊戲裡一鍵邀請入會。")
        card.act = WL("启用并加载（仅本角色）", "Enable and load (this character)", "啟用並載入（僅本角色）")
    else
        card.head = WL("GuildInsight 公会插件已安装，还没加载", "GuildInsight is installed but not loaded", "GuildInsight 公會插件已安裝，還沒載入")
        card.body = WL("点下面的按钮加载，加载后直接打开招募页，申请在游戏里一键邀请入会。",
            "Load it now - its recruitment page opens right away.",
            "點下面的按鈕載入，載入後直接打開招募頁，申請在遊戲裡一鍵邀請入會。")
        card.act = WL("点击加载", "Load now", "點擊載入")
    end
    card.fn = loadClick
    if inCombat() then
        card.body = card.body .. "\n|cffff6666" .. WL("战斗中先不加载插件，脱战后可点。", "Not while in combat - available after combat.", "戰鬥中先不載入插件，脫戰後可點。") .. "|r"
        card.act = WL("脱战后可点", "After combat", "脫戰後可點")
        card.on = false
    end
    local err = rawget(tab, "_giErr")
    if err then
        card.body = card.body .. "\n|cffff6666" .. string.format(WL("加载失败：%s", "Load failed: %s", "載入失敗：%s"), err) .. "|r"
    end
    return card
end

-- 第一次弹抽屉后：引导卡标题 / 正文的 SetText 换成状态卡文字；建加载按钮
local function patchDrawer(tab, d)
    if rawget(d, "_giPatched") then return end
    d._giPatched = true
    local c = d.cta
    if not c then return end
    for _, k in ipairs({ "head", "body" }) do
        local fs = c[k]
        local origSet = fs and fs.SetText
        if origSet then
            fs.SetText = function(self, t)
                local card = rawget(tab, "_giCard")
                if card and card[k] then t = card[k] end
                return origSet(self, t)
            end
        end
    end
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetHeight(24)
    b:SetScript("OnClick", function()
        local card = rawget(tab, "_giCard")
        if card and card.on and card.fn then card.fn() end
    end)
    c._giAct = b
end

-- 抽屉填好后：加载按钮放第一个按钮位，第二个位留招募板二维码（没安装时留「复制网址」，「了解」里已有二维码）
local function placeButtons(tab, d)
    local c = d.cta
    local card = rawget(tab, "_giCard")
    local b = c and rawget(c, "_giAct")
    if not (b and card) then return end
    local qw = c.qr.GetWidth and c.qr:GetWidth()
    local bw = (type(qw) == "number" and qw > 0) and qw or CARD_BW
    local h = c.GetHeight and c:GetHeight()
    local y = (type(h) == "number" and h > 24 + CARD_PAD) and (h - 24 - CARD_PAD) or 0
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -y)
    b:SetWidth(bw)
    b:SetText(card.act)
    if b.SetEnabled then b:SetEnabled(card.on) elseif card.on then b:Enable() else b:Disable() end
    b:Show()
    local keep, drop = c.qr, c.copy
    if card.keep == "copy" then keep, drop = c.copy, c.qr end
    keep:ClearAllPoints(); keep:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + bw + 8, -y)
    keep:Show(); drop:Hide()
end

-- 接到 W.AttachGuildTab 返回的页签上：点页签前先算状态卡，抽屉填好后放按钮；进 / 出战斗时抽屉开着就重排
local function wireTab(tab, opts)
    if not tab or rawget(tab, "_giLoadWired") then return tab end
    local orig = tab.GetScript and tab:GetScript("OnClick")
    if not orig then return tab end
    tab._giLoadWired = true
    local function click()
        tab._giCard = cardFor(tab, opts)
        orig(tab)
        local d = rawget(tab, "_drawer")
        if d and d:IsShown() and not rawget(d, "_giPatched") then
            patchDrawer(tab, d)
            -- 第一次：抽屉刚建好、已经按老文案排过 → 收起再打开，按状态卡文字重排
            orig(tab); orig(tab)
            d = rawget(tab, "_drawer")
        end
        if d and d:IsShown() then placeButtons(tab, d) end
    end
    tab:SetScript("OnClick", click)
    tab._giRefresh = function()
        local d = rawget(tab, "_drawer")
        if d and d:IsShown() then click(); click() end
    end
    tab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(WL("公会招募", "Guild recruitment", "公會招募"), 1, 0.82, 0)
        local s = ginsState()
        local line
        if s == "loaded" then
            line = WL("打开 GuildInsight 招募页", "Open GuildInsight recruitment", "打開 GuildInsight 招募頁")
        elseif s == "disabled" then
            line = WL("GuildInsight 已安装没启用 · 点开一键启用并加载", "GuildInsight is disabled - click to enable and load", "GuildInsight 已安裝沒啟用 · 點開一鍵啟用並載入")
        elseif s == "idle" then
            line = WL("GuildInsight 还没加载 · 点开一键加载", "GuildInsight is not loaded - click to load", "GuildInsight 還沒載入 · 點開一鍵載入")
        else
            line = WL("正在招人的公会 · 了解公会插件", "Recruiting guilds - about GuildInsight", "正在招人的公會 · 了解公會插件")
        end
        GameTooltip:AddLine(line, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then combatFlag = true else combatFlag = nil end
        pcall(tab._giRefresh)
    end)
    tab._giEv = ev
    return tab
end

local function attach()
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    if not host or not W or not W.AttachGuildTab or rawget(host, "_giGuildTab") then return end
    local opts = {
        game = "forever",
        top = -80,     -- 和左侧第一个页签同高（UI.lua：TOPRIGHT f TOPLEFT 3, -80）
        list = function()
            local d = _G.GearInsightForeverRecruit
            if type(d) ~= "table" then return {}, "" end
            return d.items or {}, d.updatedAt or "", d.featured
        end,
        logo = "Interface\\AddOns\\GearInsight_Forever\\media\\logo",   -- 页签 / 引导卡 / 空态插图都用插件自带 logo（不是原生白长袍图标）
        -- 空态内嵌二维码（只要矩阵，QR.Encode 的其余返回值丢掉）
        qrEncode = function(text) if ns.QR and ns.QR.Encode then local m = ns.QR.Encode(text, "M"); return m end end,
        qr = function(title, foot, url) if ns.ShowQR then return ns.ShowQR(title, foot, url) end return false end,
    }
    wireTab(W.AttachGuildTab(host, opts), opts)
end

-- 主面板第一次打开时才建（UI.lua build）→ 挂在 ns.ToggleMain 后面
if hooksecurefunc and type(ns.ToggleMain) == "function" then
    hooksecurefunc(ns, "ToggleMain", function() pcall(attach) end)
end
