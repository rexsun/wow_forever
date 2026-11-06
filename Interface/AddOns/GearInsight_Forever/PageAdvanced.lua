-- 进阶 · 网站与小程序（10-19；用户「进阶就放最外面一级目录」→ 左栏单独一个页签；设计稿 https://claude.ai/artifact/2anETTfTW9YD5km4idQ6cp）
--   上半：我的升级报告 —— 一键生成 GIFP1 链接（Report.lua，协议 docs/forever-report-protocol.md），网站按天赋 / 升级节奏 / 专业 /
--         装备 / 公会 / 小队出定制路线；公会名和自己的角色名一律带（10-19「默认直接带，不要选项」，原来两个勾已去掉）。
--   下半：站外还能做的 —— 把散在资讯页 / 天赋页 / 斜杠命令里的站外入口收到一处，⛔只复用现成的函数和网址（Offsite.lua / Card.lua / Stats.lua），不新造网址。
--   英文客户端不出微信 / 小程序那几项。
-- 三期再做：「网站回执」粘贴框（网站算完把建议串回贴进插件）—— 这一期不做。
-- 10-19 0.5.1 解除 HOLD 随包发布（用户「这次一起发」）。
local _, ns = ...

local GOLD, DIM, TXT = "|cffffd200", "|cff8a93a6", "|cffe6e0c8"
local W = 626

local page

local function fs(parent, tpl, x, y, w, text)
    local f = parent:CreateFontString(nil, "OVERLAY", tpl)
    f:SetPoint("TOPLEFT", x, y)
    if w then f:SetWidth(w) end
    f:SetJustifyH("LEFT")
    f:SetText(ns.EnSafe(text or ""))
    return f
end

-- 小标签（预览：这串里带了什么）
local CHIP_BD = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local function chip(parent, text)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop(CHIP_BD)
        f:SetBackdropColor(0.10, 0.10, 0.12, 0.95); f:SetBackdropBorderColor(0.45, 0.40, 0.20, 0.9)
    end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("CENTER", 0, 0); t:SetText(ns.EnSafe(text))
    local w = (t.GetStringWidth and t:GetStringWidth()) or 60
    if type(w) ~= "number" or w <= 0 then w = 60 end
    f:SetSize(math.min(300, w + 16), 20)
    f.label = t
    return f
end

-- 一行站外入口：标题 + 说明（灰），点击 = 执行；返回新 y
local function entry(parent, y, title, desc, onClick)
    local r = CreateFrame("Button", nil, parent)
    r:SetPoint("TOPLEFT", 0, y); r:SetSize(W, 36)
    local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
    local t = fs(r, "GameFontNormal", 10, -4, W - 20, TXT .. title .. "|r")
    t:SetWordWrap(false)
    local d = fs(r, "GameFontHighlightSmall", 10, -20, W - 20, DIM .. desc .. "|r")
    d:SetWordWrap(false)
    r:SetScript("OnClick", function() pcall(onClick) end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.EnSafe(title), 1, 0.82, 0)
        GameTooltip:AddLine(ns.EnSafe(desc), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return y - 40, r
end

local function copy(title, url)
    ns.ShowBox(title, ns.L("Ctrl+C 复制，到浏览器打开", "Ctrl+C, then open it in your browser"), url)
end

-- 站外入口清单（⛔ 只用现成函数；没有的函数 = 那一项不出）
local function offsiteItems()
    local C = ns.SlashHint or "/gi"
    local out = {}
    local function add(cond, t, d, fn) if cond then out[#out + 1] = { t, d, fn } end end
    add(ns.LandingURL, ns.L("网站 · 无限专区", "Website · Forever hub"),
        ns.L("你这个角色的升级路线 · 天赋模拟 · 掉落表 · 宏库 · 公测数据", "Your character's route · talent sim · loot · macros · beta data"),
        function() copy(ns.L("无限专区", "Forever hub"), ns.LandingURL("home")) end)
    add(ns.LandingURL, ns.L("升级路线网页版", "Leveling route (web)"),
        ns.L("按你的阵营 / 种族 / 等级排好，手机上也能看", "Laid out for your faction, race and level - works on phones too"),
        function() copy(ns.L("升级路线网页版", "Leveling route (web)"), ns.LandingURL("route")) end)
    add(ns.zh and ns.ShowTalentQR, "天赋发到手机", "当前配点出二维码，微信扫码在小程序天赋模拟器里打开（" .. C .. " talent qr）",
        function() ns.ShowTalentQR() end)
    add(ns.ExportAll or ns.ExportStats, ns.L("公测数据上传", "Upload beta data"),
        ns.L("升级用时 / 死亡 / 掉落导出成链接，到网站对比你排第几（" .. C .. " data）",
            "Export level times / deaths / loot and compare on the website (" .. C .. " data)"),
        function() if ns.ExportAll then ns.ExportAll() else ns.ExportStats() end end)
    add(ns.zh, "微信小程序", "微信搜「GearInsight」：无限天赋模拟 · 掉落 · 公测数据，手机随时看",
        function() copy("微信小程序", "GearInsight") end)
    add(ns.ShowSupportLink, ns.L("支持与上榜", "Support / get on the wall"),
        ns.L("GearInsight 永久免费；打开后支付面板自动弹出，角色名和服务器已填好（" .. C .. " support）",
            "GearInsight is free forever; opens the support panel with your character filled in (" .. C .. " support)"),
        function() ns.ShowSupportLink() end)
    return out
end

local GUILD_TXT = { none = { "没有公会", "No guild" }, member = { "公会成员", "Guild member" }, leader = { "公会会长", "Guild leader" } }

local function build(p)
    page = p
    local y0 = ns.PageHeader(p, ns.L("进阶 · 网站与小程序", "Advanced · web & app"),
        ns.L("插件里放不下的，到网站和小程序看", "What doesn't fit in the addon lives on the web"))
    local sf, c = ns.Scroll(p, 8, y0 - 4, W, 474 - 42 - 12)
    p.sf, p.c = sf, c
    local y = 0

    -- ---------- 我的升级报告 ----------
    fs(c, "GameFontNormalLarge", 0, y, W, GOLD .. ns.L("我的升级报告", "My leveling report") .. "|r")
    y = y - 24
    local ex = fs(c, "GameFontHighlightSmall", 0, y, W, ns.L("按你的天赋、升级节奏、专业、装备、公会和小队，网站出一份定制升级路线",
        "The website builds a custom leveling route from your talents, leveling pace, professions, gear, guild and group"))
    ex:SetWordWrap(true)
    y = y - 20
    -- 10-19 用户「手机可查看，等等，广告语，比如说上班可以摸鱼看啥的」：⛔只写已上线的（报告页手机能看 / 分享链接 / 和朋友比）；小程序存报告没上线别写；不用 emoji（游戏字体显示不出）
    p.adLine = fs(c, "GameFontNormal", 0, y, W, GOLD .. ns.L("手机也能看：链接发到微信，上班摸鱼、通勤路上随时翻，还能发给朋友比一比",
        "Works on your phone too: send the link to yourself and check your route on a break or on the bus - or challenge a friend.") .. "|r")
    p.adLine:SetWordWrap(true)
    y = y - 24
    local btn = ns.Button(c, ns.L("生成报告链接", "Get report link"), 180, 28, function()
        if ns.Report then ns.Report.Show() end
        if p.refreshAll then p.refreshAll() end
    end)
    btn:SetPoint("TOPLEFT", 0, y)
    p.genBtn = btn
    y = y - 36
    p.chipY = y
    p.chips = {}
    y = y - 28
    -- 10-19 用户「默认直接带，不要选项」：「带上公会名 / 带上角色名」两个勾去掉，报告一律带公会名和自己的角色名（Report.lua）
    p.lenLine = fs(c, "GameFontDisableSmall", 4, y, W - 8, "")
    y = y - 26

    -- ---------- 站外还能做的 ----------
    local hd = fs(c, "GameFontNormal", 0, y, W, GOLD .. ns.L("站外还能做的", "More outside the game") .. "|r")
    p.offHeader = hd
    y = y - 22
    p.offRows = {}
    for _, it in ipairs(offsiteItems()) do
        local r
        y, r = entry(c, y, it[1], it[2], it[3])
        p.offRows[#p.offRows + 1] = r
        r.title = it[1]
    end
    c:SetHeight(-y + 8)

    -- 标签 + 长度一起刷（打开页面 / 生成后）
    p.refreshAll = function()
        for _, ch in ipairs(p.chips) do ch:Hide() end
        p.chips = {}
        if not ns.Report then return end
        local ok, s = pcall(ns.Report.Summary)
        if ok and s then
            local list = {
                (s.cls ~= "" and s.cls or "?") .. (s.spec and (" · " .. s.spec) or ""),
                ns.L(s.level .. " 级", "Lv " .. s.level),
                ns.L("升级记录 " .. s.nLv .. " 条", s.nLv .. " level records"),
                ns.L("专业 " .. s.nProf, s.nProf .. " professions"),
                ns.L("心愿单 " .. s.nWish, s.nWish .. " wishlist"),
                ns.L(GUILD_TXT[s.guild][1], GUILD_TXT[s.guild][2]),
                s.party > 0 and ns.L("小队 " .. (s.party + 1) .. " 人", "Party of " .. (s.party + 1)) or ns.L("单刷", "Solo"),
            }
            local x, yy = 0, p.chipY
            for _, t in ipairs(list) do
                local ch = chip(c, t)
                local w = ch.GetWidth and ch:GetWidth() or 60
                if type(w) ~= "number" then w = 60 end
                if x > 0 and x + w > W then x = 0; yy = yy - 24 end
                ch:SetPoint("TOPLEFT", x, yy)
                x = x + w + 6
                p.chips[#p.chips + 1] = ch
            end
            p.summary = s
        end
        local ok2, url, n = pcall(ns.Report.URL)
        if ok2 and url then
            p.url, p.codeLen = url, n
            p.lenLine:SetText(DIM .. string.format(ns.L("报告串长度 %d 字符（上限 %d）· 只在你的电脑上生成，插件不联网", "Report code %d chars (max %d) - built locally, the addon never goes online"),
                n or 0, ns.Report.MAX_LEN) .. "|r")
        else
            p.lenLine:SetText(DIM .. ns.L("还读不到角色数据，进游戏后再打开这页", "No character data yet") .. "|r")
        end
    end
    ns.AdvPage = p   -- 测试用
end

local function refresh(p)
    if p and p.refreshAll then p.refreshAll() end
end

ns.RegisterPage({ key = "adv", order = 3.7, title = ns.L("进阶 · 网站与小程序", "Advanced · web & app"), tabTitle = ns.L("进阶", "Advanced"),
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02", build = build, refresh = refresh })
