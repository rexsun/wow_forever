-- 无限主面板**右侧**「公会」页签（10-11 公会升级二期，docs/guild-growth-2026-10-design.md「插件」第 2 条）
--   装了 GuildInsight（已加载）：点页签打开它的「招募」页
--   装了没加载 / 被禁用：抽屉顶部状态卡给「启用并加载（仅本角色）」/「点击加载」，加载成功直接打开招募页（10-12 晚）
--   没装：右侧抽屉 = 只读招募列表（GuildRecruit.lua，更新器定期刷新）+ 安装引导 + 招募板二维码（带 realm）
-- 控件和抽屉逻辑在 GIWidgets.lua（W.AttachGuildTab，三服共用），这里只接线。
-- ⛔ HOLD 中（_hold.txt：GIWidgets.lua / GuildRecruit.lua / GuildTab.lua），测完用户点头再移出。
local _, ns = ...; ns = _G.GearInsightForever or ns  -- 10-18 拆成按需加载的子插件：用主插件的命名空间（_G.GearInsightForever），子插件自己的 ... 是张新表

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
    local title = WL("复制网址 · 公会招募板", "Copy URL · guild board", "複製網址 · 公會招募板")
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
        p.cap:SetText(WL("复制网址 · 公会招募板", "Scan with WeChat · guild board", "複製網址 · 公會招募板"))
        p.cap:ClearAllPoints(); p.cap:SetPoint("TOP", p.qrBox, "BOTTOM", 0, -6)
        p.cap:Show(); p.btn:Hide()
        y = y + (tonumber(qs) or 0) + 6 + 14
    else
        p.qrBox:Hide(); p.cap:Hide()
        p.btn:SetText(WL("复制招募板网址", "Copy guild board URL", "複製招募板網址"))
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
    -- 10-16 用户：「先不要跟 GuildInsight 关联」→「应该是有个面板，陈列登记了的公会，点击生成二维码导入网站再引导到小程序，上方有保留位置」
    --   = 抽屉照常（上方精选位 + 正在招人的公会卡片，点卡片出这家公会的二维码），但不认 GuildInsight：
    --   点页签时临时把 W.GuildAddonState 当成「没装」走抽屉，引导卡换成「置顶我的公会」。
    --   以后要恢复 GuildInsight 联动：ns.db.ui.guildLinkGins = true
    local function linkGins() return ns.db and ns.db.ui and ns.db.ui.guildLinkGins end
    local function boardCard()
        local feat = ns.GuildPinUrl()
        return { state = "board", on = true, keep = "qr",
            head = WL("让更多玩家看到你的公会", "Get your guild seen", "讓更多玩家看到你的公會"),
            body = WL("会长打开网站进招募板发布招募卡，登记后就出现在下面的列表里。\n想排到最上面：点「置顶我的公会」到网站查看置顶方式。",
                "Guild masters: open the website to list your guild on the board - it then shows up below.\nTo be on top: click 'Pin my guild' and open the website.",
                "會長開啟網站進招募板發布招募卡，登記後就出現在下面的列表裡。\n想排到最上面：點「置頂我的公會」到網站查看置頂方式。"),
            act = WL("置顶我的公会", "Pin my guild", "置頂我的公會"),
            fn = function() showBoardQR(opts, feat) end }
    end
    local function callOrig()
        local W = ns.W or _G.GIWidgets
        if linkGins() or not W then return orig(tab) end
        local saved = W.GuildAddonState
        W.GuildAddonState = function() return "missing" end
        local ok, e = pcall(orig, tab)
        W.GuildAddonState = saved
        if not ok then error(e) end
    end
    local function click()
        tab._giCard = linkGins() and cardFor(tab, opts) or boardCard()
        callOrig()
        local d = rawget(tab, "_drawer")
        if d and d:IsShown() and not rawget(d, "_giPatched") then
            patchDrawer(tab, d)
            -- 第一次：抽屉刚建好、已经按老文案排过 → 收起再打开，按状态卡文字重排
            callOrig(); callOrig()
            d = rawget(tab, "_drawer")
        end
        if d and d:IsShown() then placeButtons(tab, d) end
        if d and d:IsShown() and not linkGins() and ns.GuildTopLayout then pcall(ns.GuildTopLayout, tab, opts) end
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
        if not linkGins() then
            line = WL("正在招人的公会 · 点公会复制网址，在浏览器查看详情、申请", "Recruiting guilds - click to copy a web link", "正在招人的公會 · 點公會複製網址，在瀏覽器查看詳情、申請")
        elseif s == "loaded" then
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

-- ── 10-16 公会面板（无限，做法 B：只在本文件里画，⛔ 共享的 GIWidgets.lua 不改，五份逐字节相同）──────────────
--   用户第二轮：「上面模块太占地方，重新设计」「下面列表要筛选」「没有人置顶的情况下热度前 3 放这里」
--   「GearInsight 公会暂时也算置顶的」→ 不单独做一块，它就是置顶位第 1 格，和别的置顶公会一样标「置顶中」。
--   自上而下：① 一排三个小格：置顶（GearInsight 在前，再是 pins）→ 不够用热度前几补（标「热度 N」，不算置顶的 / 招满的）→ 还不够画「槽位空缺」
--      ⛔ 11-05 用户「跟小程序对齐，不要缩略的小图标，都是大图标」：三个小格作废 → 置顶 / 热度这几家改成和列表一样的大卡，
--         排在最上面、右上角标「置顶中」/「热度 N」（不受筛选影响，和以前小格一样）；下面列表去掉这几家不重复；空位不再画「槽位空缺」
--             ② 一行引导：「会长：让更多人看到你的公会」+「置顶我的公会」
--             ③ 筛选：阵营 / 规则 / 缺我的职业 / 隐藏已招满（存 ns.db.ui）④ 列表（标题写「N / 总数」）
--             ⑤ 底部：「发布我的公会招募」+「复制招募板网址」并排（招募板二维码只留这一个入口）
--   抽屉自带的大卡位 / 引导卡藏起来；列表区按这里算好的位置绝对摆放（每次重填都从头算，不会越挪越下）
--   ⛔ 国服插件治理：这里的字不出现任何和钱有关的字样；置顶只写「置顶中」
local OFFICIAL_ID = 11
local function linkGinsGlobal() return ns.db and ns.db.ui and ns.db.ui.guildLinkGins end
local function isOfficial(it) return type(it) == "table" and it[1] == OFFICIAL_ID and type(it[2]) == "string" and it[2]:lower() == "gearinsight" end
local function enc(v)
    return (tostring(v or ""):gsub("[^A-Za-z0-9%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end
-- 置顶落地页：带服务器 / 公会名 / 阵营，网站打开直接认出是哪家（只用来预选，下单仍要登录校验管理权限）
function ns.GuildPinUrl()
    local W = ns.W or _G.GIWidgets
    local site = (W and W.SITE) or "gearinsight.app"
    local realm = GetRealmName and GetRealmName() or ""
    local gname = GetGuildInfo and GetGuildInfo("player") or ""
    local fac = UnitFactionGroup and UnitFactionGroup("player") or ""
    return "https://" .. site .. "/wow/guild/feature?game=forever&server=" .. enc(realm) .. "&guild=" .. enc(gname)
        .. "&faction=" .. enc(fac) .. "&ref=addon"
end

-- 三格：{ it = 公会, kind = "pin" | "heat", rank = 热度名次 } 或 nil（空缺）
local function slotData()
    local d = _G.GearInsightForeverRecruit
    local items = (type(d) == "table" and type(d.items) == "table") and d.items or {}
    local byId, used, out = {}, {}, {}
    for _, it in ipairs(items) do if type(it) == "table" and it[1] then byId[it[1]] = it end end
    local function add(it, kind, rank)
        if it and not used[it[1]] and #out < 3 then used[it[1]] = true; out[#out + 1] = { it = it, kind = kind, rank = rank } end
    end
    for _, it in ipairs(items) do if isOfficial(it) then add(it, "pin") end end
    for _, id in ipairs((type(d) == "table" and type(d.pins) == "table") and d.pins or {}) do add(byId[id], "pin") end
    local hot = {}
    for _, it in ipairs(items) do
        if type(it) == "table" and not used[it[1]] and not isOfficial(it) and not it[14] and (tonumber(it[19]) or 0) > 0 then hot[#hot + 1] = it end
    end
    table.sort(hot, function(a, b) return (tonumber(a[19]) or 0) > (tonumber(b[19]) or 0) end)
    for i, it in ipairs(hot) do add(it, "heat", i) end
    return out
end
ns.GuildSlotData = slotData   -- 测试用

-- ---------- 筛选（存 ns.db.ui.gf = { fac, rule, mine, hideFull }）----------
local FAC_ZH = { Alliance = "联盟", Horde = "部落" }
local function gf()
    ns.db = ns.db or {}
    ns.db.ui = ns.db.ui or {}
    local f = ns.db.ui.gf
    if type(f) ~= "table" then
        local mine = FAC_ZH[UnitFactionGroup and UnitFactionGroup("player") or ""]
        f = { fac = mine or "all", rule = "all", mine = false, hideFull = true }
        ns.db.ui.gf = f
    end
    return f
end
local function ruleOf(it)
    local r = it[16] or ""
    if r == "" then r = it[4] or "" end   -- 老数据：服务器那格就是规则集
    return r
end
local function myClassCn()
    local cls = ns.MyClass and ns.MyClass()
    return cls and ns.Data and ns.Data.classCn and ns.Data.classCn[cls] or nil
end
-- 过滤后的列表 + 总数
function ns.GuildFilter(items)
    local f = gf()
    local cn = myClassCn()
    local out = {}
    for _, it in ipairs(items or {}) do
        if type(it) == "table" then
            local ok = true
            if f.fac ~= "all" and it[3] ~= f.fac then ok = false end
            if ok and f.rule ~= "all" then
                local r = ruleOf(it)
                if r ~= f.rule and r ~= "不限" and r ~= "" then ok = false end
            end
            if ok and f.mine and cn then
                local need = it[7]
                if type(need) == "table" and #need > 0 then
                    local hit = false
                    for _, x in ipairs(need) do if x == cn then hit = true; break end end
                    ok = hit
                end
            end
            if ok and f.hideFull and it[14] then ok = false end
            if ok then out[#out + 1] = it end
        end
    end
    return out, #(items or {})
end
local function rulesPresent(items)
    local seen, out = {}, {}
    for _, it in ipairs(items or {}) do
        local r = type(it) == "table" and ruleOf(it) or ""
        if r ~= "" and r ~= "不限" and not seen[r] then seen[r] = true; out[#out + 1] = r end
    end
    table.sort(out)
    return out
end

-- ---------- 小控件 ----------
local PAD, INNER = 12, 356
local GUIDE_H, CHIP_H, GAP = 24, 20, 6
local function bd(f, r, g, b, a, er, eg, eb, ea)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(er, eg, eb, ea)
end
local function tipScripts(b)
    b:SetScript("OnEnter", function(self)
        if not (GameTooltip and rawget(self, "tip")) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for k, ln in ipairs(self.tip) do
            if k == 1 then GameTooltip:SetText(ln, 1, 0.82, 0, 1, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
-- 筛选小格：选中 = 金框 + 金色底光 + 白字（同 PageProf 的 markSel；⛔ 不用禁用变灰）
local function chip(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(w, CHIP_H)
    bd(b, 0.10, 0.09, 0.07, 1, 0.42, 0.35, 0.16, 0.8)
    b.glow = b:CreateTexture(nil, "ARTWORK"); b.glow:SetPoint("TOPLEFT", 3, -3); b.glow:SetPoint("BOTTOMRIGHT", -3, 3)
    b.glow:SetColorTexture(1, 0.82, 0, 0.22); b.glow:Hide()
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.t:SetPoint("CENTER", 0, 0); b.t:SetText(text)
    b:SetScript("OnClick", onClick)
    b.SetSel = function(self, on)
        self._sel = on and true or false
        self.glow:SetShown(self._sel)
        if self.SetBackdropBorderColor then
            if self._sel then self:SetBackdropBorderColor(1, 0.85, 0.1, 1) else self:SetBackdropBorderColor(0.42, 0.35, 0.16, 0.8) end
        end
        if self._sel then self.t:SetTextColor(1, 1, 1) else self.t:SetTextColor(1, 0.82, 0) end
    end
    return b
end
local function facTxt(f)
    if f == "联盟" or f == "Alliance" then return "|cff4a8cff" .. WL("联盟", "Alliance", "聯盟") .. "|r" end
    if f == "部落" or f == "Horde" then return "|cffff4a4a" .. WL("部落", "Horde", "部落") .. "|r" end
    return ""
end
local function showQR(opts, title, foot, url)
    local W = ns.W or _G.GIWidgets
    local ok, r = false, nil
    if opts.qr then ok, r = pcall(opts.qr, title, foot, url) end
    if not (ok and r ~= false) and W and W.Copy then W.Copy(url, title) end
end
local function guildQR(opts, it)
    local W = ns.W or _G.GIWidgets
    local url = W and W.GuildBoardUrl and W.GuildBoardUrl("forever", it[1])
    if url then showQR(opts, "<" .. tostring(it[2] or "") .. ">", WL("复制网址看详情、申请", "Copy URL to view and apply", "複製網址看詳情、申請"), url) end
end
local function pinQR(opts)
    showQR(opts, WL("复制网址 · 置顶我的公会", "Copy URL · pin my guild", "複製網址 · 置頂我的公會"),
        WL("打开后按页面说明操作", "Follow the page to pin", "打開後按頁面說明操作"), ns.GuildPinUrl())
end

-- ---------- 建一次：三格 / 引导行 / 筛选 / 底部招募板按钮 ----------
local function build(d, opts, refill)
    local box = CreateFrame("Frame", nil, d)
    box:SetSize(INNER, 10)
    -- 引导：一行字 + 按钮（11-05 起上面不再有三个小格，置顶 / 热度大卡在 box 之上，由 GuildTopLayout 摆）
    local gy = 0
    box.guide = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.guide:SetPoint("TOPLEFT", 2, -(gy + 5)); box.guide:SetJustifyH("LEFT")
    box.guide:SetText(WL("会长：让更多人看到你的公会", "Guild masters: get your guild seen", "會長：讓更多人看到你的公會"))
    box.pinBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.pinBtn:SetSize(110, GUIDE_H); box.pinBtn:SetPoint("TOPRIGHT", 0, -gy)
    box.pinBtn:SetText(WL("置顶我的公会", "Pin my guild", "置頂我的公會"))
    box.pinBtn:SetScript("OnClick", function() pinQR(opts) end)
    -- 筛选第 1 行：阵营 + 两个开关
    local fy = gy + GUIDE_H + GAP + 2
    box.facLbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); box.facLbl:SetPoint("TOPLEFT", 2, -(fy + 4))
    box.facLbl:SetText(WL("阵营", "Faction", "陣營"))
    box.fac = {}
    local x = 30
    for _, v in ipairs({ { "all", WL("全部", "All", "全部") }, { "联盟", WL("联盟", "Alliance", "聯盟") }, { "部落", WL("部落", "Horde", "部落") } }) do
        local b = chip(box, v[2], 44, function() gf().fac = v[1]; refill() end)
        b:SetPoint("TOPLEFT", x, -fy); x = x + 47
        box.fac[v[1]] = b
    end
    box.mine = chip(box, WL("缺我的职业", "Needs my class", "缺我的職業"), 82, function() local f = gf(); f.mine = not f.mine; refill() end)
    box.mine:SetPoint("TOPLEFT", x + 6, -fy)
    box.full = chip(box, WL("隐藏已招满", "Hide full", "隱藏已招滿"), 82, function() local f = gf(); f.hideFull = not f.hideFull; refill() end)
    box.full:SetPoint("TOPLEFT", box.mine, "TOPRIGHT", 4, 0)
    -- 筛选第 2 行：规则（数据里有哪些就出哪些）
    box.ruleY = fy + CHIP_H + 4
    box.ruleLbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); box.ruleLbl:SetPoint("TOPLEFT", 2, -(box.ruleY + 4))
    box.ruleLbl:SetText(WL("规则", "Rules", "規則"))
    box.rules = {}
    box._h = box.ruleY + CHIP_H
    box:SetHeight(box._h)
    -- 底部：「发布我的公会招募」缩成半宽，旁边放「复制招募板网址」
    box.board = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    box.board:SetText(WL("复制招募板网址", "Copy guild board URL", "複製招募板網址"))
    box.board:SetScript("OnClick", function()
        local W = ns.W or _G.GIWidgets
        local url = W and W.GuildBoardUrl and W.GuildBoardUrl("forever")
        if url then showQR(opts, WL("复制网址 · 公会招募板", "Copy URL · guild board", "複製網址 · 公會招募板"),
            WL("按服务器、阵营、缺的职业筛，一键申请", "Filter by realm, faction and classes, then apply", "按伺服器、陣營、缺的職業篩，一鍵申請"), url) end
    end)
    d._fvTop = box
    return box
end

-- 置顶 / 热度大卡：右上角标「置顶中」/「热度 N」+ 换边框色；别的卡（行会复用）还原
local CARD_EDGE = { 0.42, 0.35, 0.16, 0.85 }
local function markCard(r, sl)
    local b = rawget(r, "_fvBadge")
    if not b and sl then
        b = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b:SetPoint("TOPRIGHT", -10, -7); b:SetJustifyH("RIGHT")
        r._fvBadge = b
    end
    if not sl then
        if b then b:SetText(""); b:Hide() end
        if r.SetBackdropBorderColor then r:SetBackdropBorderColor(CARD_EDGE[1], CARD_EDGE[2], CARD_EDGE[3], CARD_EDGE[4]) end
        return
    end
    if sl.kind == "pin" then
        b:SetText("|cff33ff99" .. WL("置顶中", "Pinned", "置頂中") .. "|r")
        if r.SetBackdropBorderColor then r:SetBackdropBorderColor(0.2, 0.9, 0.5, 0.9) end
    else
        b:SetText("|cffffd100" .. string.format(WL("热度 %d", "Hot #%d", "熱度 %d"), sl.rank) .. "|r")
        if r.SetBackdropBorderColor then r:SetBackdropBorderColor(1, 0.82, 0, 0.75) end
    end
    b:Show()
end
ns.GuildMarkCard = markCard   -- 测试用

-- 11-05 用户「职业也换成图标」：卡片第 3 行「缺 …」把职业名换成职业图标（游戏自带的圆形职业图标），名字留在悬停提示里
--   不限 / 全职业（≥8）照旧写字；⛔ 共享的 GIWidgets.lua 不改，抽屉填完后在这里重写这一行
local CLASS_TOKEN = {
    ["战士"] = "WARRIOR", ["圣骑士"] = "PALADIN", ["聖騎士"] = "PALADIN", ["猎人"] = "HUNTER", ["獵人"] = "HUNTER",
    ["盗贼"] = "ROGUE", ["潜行者"] = "ROGUE", ["盜賊"] = "ROGUE", ["牧师"] = "PRIEST", ["牧師"] = "PRIEST",
    ["萨满祭司"] = "SHAMAN", ["萨满"] = "SHAMAN", ["薩滿"] = "SHAMAN", ["法师"] = "MAGE", ["法師"] = "MAGE",
    ["术士"] = "WARLOCK", ["術士"] = "WARLOCK", ["德鲁伊"] = "DRUID", ["德魯伊"] = "DRUID",
}
-- UI-Classes-Circles 256×256 里的位置（客户端没给 CLASS_ICON_TCOORDS 时用）
local TC = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local ICON_SZ = 16
local function classIcon(name)
    local tok = CLASS_TOKEN[name]
    local t = tok and ((type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[tok]) or TC[tok])
    if not t then return nil end
    return string.format("|TInterface\TargetingFrame\UI-Classes-Circles:%d:%d:0:0:256:256:%d:%d:%d:%d|t", ICON_SZ, ICON_SZ,
        math.floor(t[1] * 256 + 0.5), math.floor(t[2] * 256 + 0.5), math.floor(t[3] * 256 + 0.5), math.floor(t[4] * 256 + 0.5))
end
ns.GuildClassIcon = classIcon   -- 测试用
-- 第 3 行：「缺 [图标][图标]…   规模」；认不出的职业照旧写字
local function needLine(it)
    local W = ns.W or _G.GIWidgets
    local need, size = it[7], tostring(it[8] or "")
    local body
    if type(need) ~= "table" or #need == 0 or #need >= 8 then
        body = (W and W.ClassText) and W.ClassText(need, 6) or ""
    else
        local out = {}
        for _, n in ipairs(need) do out[#out + 1] = classIcon(n) or ("|cffbbbbbb" .. tostring(n) .. "|r") end
        body = table.concat(out, " ")
    end
    local t = WL("缺 ", "Need ", "缺 ") .. body
    if size ~= "" then t = t .. "   |cff9a9a9a" .. size .. "|r" end
    return t
end
ns.GuildNeedLine = needLine   -- 测试用

local function fillFilters(box, refill)
    local f = gf()
    for k, b in pairs(box.fac) do b:SetSel(f.fac == k) end
    box.mine:SetSel(f.mine)
    box.full:SetSel(f.hideFull)
    local d = _G.GearInsightForeverRecruit
    local present = rulesPresent(type(d) == "table" and d.items or {})
    local list = { "all" }
    for _, r in ipairs(present) do list[#list + 1] = r end
    if f.rule ~= "all" then   -- 存着的规则这次数据里没有了：退回全部
        local hit = false
        for _, r in ipairs(present) do if r == f.rule then hit = true end end
        if not hit then f.rule = "all" end
    end
    for _, b in pairs(box.rules) do b:Hide() end
    local x = 30
    for i, r in ipairs(list) do
        local b = box.rules[i]
        if not b then
            b = chip(box, "", 44, nil)
            box.rules[i] = b
        end
        local label = r == "all" and WL("全部", "All", "全部") or r
        b.t:SetText(label)
        local w = math.max(40, math.floor((b.t.GetStringWidth and b.t:GetStringWidth() or 24) + 16))
        b:SetWidth(w)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -box.ruleY); x = x + w + 3
        b:SetScript("OnClick", function() gf().rule = r; refill() end)
        b:SetSel(f.rule == r)
        b:SetShown(x <= INNER + 3)
    end
end

-- 抽屉每次填完：藏掉大卡位 / 引导卡 / 自带的列表滚动区，三格 + 引导 + 筛选 + 列表放进**同一个**滚动区
--   10-16 用户「滚动的时候整体滚动上下」：滚轮滚的是整块内容（三格、引导、筛选、列表一起动），只有标题栏和底部按钮不动。
--   列表卡片还是抽屉填的（d.rows，内容 / 点击都不改），这里只把显示着的卡片挂到滚动区里按顺序摆
local CARD_H, CARD_GAP, WHEEL = 62, 6, 40
local function setOff(vp, v)
    local maxOff = math.max(0, (rawget(vp, "_contentH") or 0) - (rawget(vp, "_viewH") or 0))
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > maxOff then v = maxOff end
    vp._off = v
    if vp.SetVerticalScroll then vp:SetVerticalScroll(v) end
    local th = vp.thumb
    if maxOff <= 0 then th:Hide(); return end
    local view = vp._viewH
    local h = math.max(24, view * view / vp._contentH)
    th:ClearAllPoints(); th:SetWidth(3); th:SetHeight(h)
    th:SetPoint("TOPRIGHT", vp, "TOPRIGHT", 6, -((view - h) * v / maxOff))
    th:Show()
end
local function ensureView(d)
    local vp = rawget(d, "_fvVp")
    if vp then return vp end
    vp = CreateFrame("ScrollFrame", nil, d)
    local c = CreateFrame("Frame", nil, vp)
    c:SetSize(INNER, 10)
    if vp.SetScrollChild then vp:SetScrollChild(c) end
    vp.content = c
    if vp.EnableMouseWheel then vp:EnableMouseWheel(true) end
    vp:SetScript("OnMouseWheel", function(self, delta) setOff(self, (rawget(self, "_off") or 0) - (delta or 0) * WHEEL) end)
    vp.thumb = d:CreateTexture(nil, "OVERLAY")
    vp.thumb:SetColorTexture(0.85, 0.68, 0.25, 0.85)
    vp.thumb:Hide()
    vp.head = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); vp.head:SetJustifyH("LEFT")
    vp.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); vp.sub:SetJustifyH("RIGHT")
    vp.empty = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); vp.empty:SetWidth(INNER - 20); vp.empty:SetJustifyH("CENTER")
    d._fvVp = vp
    return vp
end
function ns.GuildTopLayout(tab, opts)
    local d = rawget(tab, "_drawer")
    if not (d and d.IsShown and d:IsShown()) then return end
    if rawget(d, "_fvFillGen") == rawget(d, "_fvDoneGen") then return end   -- 这一轮已经摆过
    d._fvDoneGen = rawget(d, "_fvFillGen")
    local vp = ensureView(d)
    local keepOff = rawget(d, "_fvKeepOff")
    d._fvKeepOff = nil
    local function refill()
        d._fvKeepOff = rawget(vp, "_off") or 0   -- 点筛选：滚动位置别跳回顶
        if tab._giRefresh then tab._giRefresh() end
    end
    local box = rawget(d, "_fvTop") or build(d, opts, refill)
    fillFilters(box, refill)
    -- 抽屉自带的大卡位 / 引导卡 / 列表滚动区 / 空态都不用了
    for _, f in ipairs({ d.feat, d.cta, d.scroll, d.track, d.thumb, d.emptyBox }) do if f and f.Hide then f:Hide() end end
    if d.listHead then d.listHead:SetText("") end
    if d.sub then d.sub:SetText("") end
    -- 滚动区：标题栏下面 → 底部按钮上面
    local top, bottom = 50, PAD + 24 + 10
    local H = rawget(d, "_h") or (d.GetHeight and d:GetHeight()) or 640
    local viewH = math.max(80, H - top - bottom)
    vp:ClearAllPoints(); vp:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -top)
    vp:SetSize(INNER, viewH); vp:Show()
    vp._viewH = viewH
    local c = vp.content
    -- 抽屉填好的、显示着的卡片：前 topN 张 = 置顶 / 热度大卡（opts.list 排在最前面），放最上面
    local top = ns._fvTopSlots or {}
    local shownRows = {}
    for _, r in ipairs(d.rows or {}) do if r.IsShown and r:IsShown() then shownRows[#shownRows + 1] = r end end
    local y, nTop = 0, 0
    local listed = ns._fvList or {}
    for k, r in ipairs(shownRows) do
        local sl = top[k]
        markCard(r, sl)
        local it = listed[k]
        if it and r.need and r.l and r.l.GetText and r.l:GetText() == it[2] then r.need:SetText(needLine(it)) end   -- 名字对得上才改（行和数据对齐）
        if sl then
            r:SetParent(c); r:ClearAllPoints(); r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
            y = y + CARD_H + CARD_GAP
            nTop = nTop + 1
        end
    end
    if nTop > 0 then y = y + 4 end
    box:SetParent(c); box:ClearAllPoints(); box:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y); box:Show()
    y = y + (rawget(box, "_h") or 0) + 10
    -- 列表标题：「正在招人的公会  N / 总数」+ 更新时间
    local rd = _G.GearInsightForeverRecruit
    local shown, total = ns.GuildFilter(type(rd) == "table" and rd.items or {})
    vp.head:ClearAllPoints(); vp.head:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
    local nShown = #shown
    if nTop > 0 then   -- 置顶 / 热度那几家已在上面，列表里去掉了，不算进「N」
        local topId = {}
        for k = 1, nTop do topId[top[k].it[1]] = true end
        nShown = 0
        for _, it in ipairs(shown) do if not topId[it[1]] then nShown = nShown + 1 end end
    end
    vp.head:SetText(string.format(WL("正在招人的公会  %d / %d", "Recruiting guilds  %d / %d", "正在招人的公會  %d / %d"), nShown, total))
    local upd = type(rd) == "table" and tostring(rd.updatedAt or "") or ""
    vp.sub:ClearAllPoints(); vp.sub:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -(y + 2))
    vp.sub:SetText(upd ~= "" and string.format(WL("%s 更新", "updated %s", "%s 更新"), upd:sub(6, 16)) or "")
    y = y + 22
    -- 卡片：抽屉填好的、显示着的那些，按顺序挂进来
    local n = 0
    for k = nTop + 1, #shownRows do
        local r = shownRows[k]
        r:SetParent(c); r:ClearAllPoints(); r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(y + n * (CARD_H + CARD_GAP)))
        n = n + 1
    end
    if n == 0 then
        vp.empty:ClearAllPoints(); vp.empty:SetPoint("TOP", c, "TOP", 0, -(y + 20))
        vp.empty:SetText(WL("没有符合筛选的公会，换个条件试试", "No guilds match - try other filters", "沒有符合篩選的公會，換個條件試試"))
        vp.empty:Show()
        y = y + 60
    else
        vp.empty:SetText(""); vp.empty:Hide()
        y = y + n * (CARD_H + CARD_GAP) - CARD_GAP
    end
    vp._contentH = y + 6
    c:SetHeight(vp._contentH)
    setOff(vp, keepOff or 0)
    -- 底部两个按钮并排（不滚）
    local half = math.floor((INNER - 8) / 2)
    if d.more then d.more:ClearAllPoints(); d.more:SetSize(half, 24); d.more:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", PAD, PAD) end
    box.board:ClearAllPoints(); box.board:SetSize(half, 24); box.board:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -PAD, PAD); box.board:Show()
end

local function attach()
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    if not host or not W or not W.AttachGuildTab or rawget(host, "_giGuildTab") then return end
    local opts = {
        game = "forever",
        top = -80,     -- 和左侧第一个页签同高（UI.lua：TOPRIGHT f TOPLEFT 3, -80）
        list = function()
            local tab = rawget(host, "_giGuildTab")
            local dr = tab and rawget(tab, "_drawer")
            if dr then dr._fvFillGen = (rawget(dr, "_fvFillGen") or 0) + 1 end   -- 抽屉重填了一次：顶部区块要重新摆
            local d = _G.GearInsightForeverRecruit
            if type(d) ~= "table" then return {}, "" end
            ns._fvTopSlots = {}   -- 抽屉第一次填时 _drawer 可能还没挂上 → 记在 ns 上
            ns._fvList = {}
            if linkGinsGlobal() then return d.items or {}, d.updatedAt or "", d.featured end
            local list = ns.GuildFilter(d.items or {})   -- 10-16 筛选：阵营 / 规则 / 缺我的职业 / 隐藏已招满
            ns._fvList = list
            -- 11-05 置顶 / 热度大卡：排在最前面（不受筛选影响），筛选后的列表去掉这几家
            local top = slotData()
            if #top == 0 then return list, d.updatedAt or "" end
            local out, used = {}, {}
            for _, sl in ipairs(top) do out[#out + 1] = sl.it; used[sl.it[1]] = true end
            for _, it in ipairs(list) do if not used[it[1]] then out[#out + 1] = it end end
            ns._fvTopSlots = top
            ns._fvList = out
            return out, d.updatedAt or ""
        end,
        logo = "Interface\\AddOns\\GearInsight_Forever\\media\\logo",   -- 页签 / 引导卡 / 空态插图都用插件自带 logo（不是原生白长袍图标）
        -- 空态内嵌二维码（只要矩阵，QR.Encode 的其余返回值丢掉）
        qrEncode = nil, -- Guild QR codes belong on the website.
        qr = function(title, foot, url) if W and W.Copy then W.Copy(url, title); return true end return false end,
    }
    wireTab(W.AttachGuildTab(host, opts), opts)
end

ns.GuildTabAttach = attach   -- 10-18 按需加载：主插件 UI.lua ns.OpenModule 调

-- 主面板第一次打开时才建（UI.lua build）→ 挂在 ns.ToggleMain 后面
if hooksecurefunc and type(ns.ToggleMain) == "function" then
    hooksecurefunc(ns, "ToggleMain", function() pcall(attach) end)
end
