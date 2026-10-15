-- 站外引导 + 免费事业支持榜（10-12 用户「聚焦无限服插件的站外引导和打赏排行榜，完全对标正式服」）
--   照正式服 ui/NewsPage.lua 第二段「免费事业支持榜」+ ui/MainTabs.lua「更多功能在站外」，时光服 PageNews.lua 已复刻过一次，这里同一套口径：
--   · 数据 Supporters.lua ← services/wow-agent/build_supporters_lua.py --forever：和正式服同一个榜、同一套「只认 verified=1 到账」规则，
--     费用只给百分比不给金额；插件不联网，面板写「几号几点更新」。
--   · 所有站外链接都落到网站的无限落地页 /wow/forever/go（插件承接页）：带职业 / 等级 / 阵营 / 种族，
--     落地页按这些直接给出这个角色的升级路线；去支持时再带角色名 + 服务器，打赏面板自动弹开、登记名字自动填好（GI_PAY_WHO）。
--   · 网站按客户端语言：简体 / 繁体 → gearinsight.cn（国内直连），其它 → gearinsight.app；小程序只对中文客户端推荐。
-- ⛔ 中文字体没有 ①②③ / ■ 的字形（时光服 10-11 实测变方框）→ 名次用带色数字，图例用带色文字。
local _, ns = ...

local GOLD, DIM, TXT = "|cffffd200", "|cff8a93a6", "|cffe6e0c8"
local CUR = { CNY = "¥", USD = "$", EUR = "€", GBP = "£", TWD = "NT$", HKD = "HK$", KRW = "₩" }
local CLASS_ICON = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue",
    SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior", DEATHKNIGHT = "DeathKnight", DEMONHUNTER = "DemonHunter",
    MONK = "Monk", EVOKER = "Evoker" }
local CLASS_HEX = { DEATHKNIGHT = "C41E3A", DEMONHUNTER = "A330C9", DRUID = "FF7C0A", EVOKER = "33937F", HUNTER = "AAD372", MAGE = "3FC7EB",
    MONK = "00FF98", PALADIN = "F48CBA", PRIEST = "FFFFFF", ROGUE = "FFF468", SHAMAN = "0070DD", WARLOCK = "8788EE", WARRIOR = "C79C6E" }

-- ---------- 网址 ----------
local function site()
    return ns.zh and "https://gearinsight.cn/wow/forever" or "https://gearinsight.app/wow/en/forever"
end
-- 网址里的空格 / & / # / ? / % / = / + 转义；中文原样（粘到浏览器能认）
-- ⛔ 别用 %s：按 C 库 isspace 判断，某些环境下会把中文 UTF-8 的续字节（0x85 / 0xA0）当空白拆掉，名字就乱码了
local function enc(s)
    return (tostring(s or ""):gsub("[%%&#%? =+	]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local FAC = { Alliance = "A", Horde = "H" }
-- to = "home" | "route" | "support"；只有去支持时才带角色名和服务器（登记表要用），其它链接只带职业 / 等级 / 阵营 / 种族
function ns.LandingURL(to)
    local q = { "from=addon" }
    local cls
    if UnitClass then cls = select(2, UnitClass("player")) end   -- ⛔ 别写 `UnitClass and UnitClass()`：and 只留第一个返回值
    if cls then q[#q + 1] = "cls=" .. cls end
    local lv = UnitLevel and UnitLevel("player")
    if lv and lv > 0 then q[#q + 1] = "lv=" .. lv end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    if FAC[fac or ""] then q[#q + 1] = "f=" .. FAC[fac] end
    local race = ns.RouteRace and ns.RouteRace()
    if race then q[#q + 1] = "race=" .. race end
    if to and to ~= "home" then q[#q + 1] = "to=" .. to end
    if to == "support" then
        local name = UnitName and UnitName("player")
        local realm = GetRealmName and GetRealmName() or ""
        if name and not ns.Secret(name) then q[#q + 1] = "c=" .. enc(name) end
        if realm ~= "" then q[#q + 1] = "r=" .. enc(realm) end
        local regionMap = { "us", "kr", "eu", "tw", "cn" }
        q[#q + 1] = "g=" .. (regionMap[(GetCurrentRegion and GetCurrentRegion()) or 0] or "cn")
    end
    return site() .. "/go?" .. table.concat(q, "&") .. (to == "support" and "#tip" or "")
end

local function copy(title, url)
    ns.ShowBox(title, ns.L("Ctrl+C 复制，到浏览器打开", "Ctrl+C, then open it in your browser"), url)
end

function ns.ShowSupportLink()
    copy(ns.L("免费事业支持榜", "Supporters"), ns.LandingURL("support"))
end

-- ---------- 资讯页：免费事业支持榜 ----------
local function trunc(s, n)
    s = s or ""
    local out, cnt, i = {}, 0, 1
    while i <= #s do
        if cnt >= n then return table.concat(out) .. "…" end
        local c = s:byte(i)
        local w = (c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1
        out[#out + 1] = s:sub(i, i + w - 1); i = i + w; cnt = cnt + 1
    end
    return s
end
local function money(amt, cur)
    local v = math.floor((amt or 0) * 100 + 0.5) / 100
    -- 自报登记没填金额的条目：别印成 ¥0（正式服 09-15 用户以为数据错了）
    if v <= 0 then return "—" end
    local sym = CUR[cur or "CNY"] or ((cur or "") .. " ")
    return sym .. ((v % 1 == 0) and tostring(math.floor(v)) or string.format("%.2f", v))
end
local function classHex(cls)
    local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    if c and c.GenerateHexColor then return c:GenerateHexColor():sub(3) end
    return (cls and CLASS_HEX[cls]) or "e6e0c8"
end
local function classIcon(cls)
    if not cls or not CLASS_ICON[cls] then return "" end
    return "|TInterface\\Icons\\ClassIcon_" .. CLASS_ICON[cls] .. ":11:11:0:-1:64:64:4:60:4:60|t "
end

-- 一行：文字 + 右侧小字；可点 / 可悬停。返回新的 y
local function line(c, y, w, text, opts)
    opts = opts or {}
    local r = CreateFrame("Button", nil, c)
    r:SetPoint("TOPLEFT", opts.x or 0, y); r:SetWidth(opts.w or w)
    if opts.cta or opts.hdr then
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 0.82, 0, opts.cta and 0.16 or 0.08)
    end
    if opts.hdr then
        local ac = r:CreateTexture(nil, "BORDER"); ac:SetWidth(3); ac:SetPoint("TOPLEFT", 0, -3); ac:SetPoint("BOTTOMLEFT", 0, 3)
        ac:SetColorTexture(1, 0.82, 0, 0.9)
    end
    local t = r:CreateFontString(nil, "OVERLAY", opts.font or "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 8, -4); t:SetJustifyH("LEFT")
    t:SetWidth((opts.w or w) - 16 - (opts.right and 90 or 0))
    if opts.oneline then t:SetWordWrap(false) end
    t:SetText(ns.EnSafe(text))
    if opts.right then
        local t2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t2:SetPoint("TOPRIGHT", -6, -4); t2:SetJustifyH("RIGHT"); t2:SetText(ns.EnSafe(opts.right))
    end
    local h = math.max(opts.h or 0, (t:GetStringHeight() or 12) + 8)
    r:SetHeight(h)
    if opts.click then
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
        r:SetScript("OnClick", opts.click)
    end
    if opts.tip then
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if opts.tipTitle then GameTooltip:AddLine(opts.tipTitle, 1, 0.82, 0) end
            GameTooltip:AddLine(ns.EnSafe(opts.tip), 1, 1, 1, true); GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        r:EnableMouse(opts.click ~= nil)
    end
    return y - h - 1, r
end

function ns.NewsSupport(c, y, W)
    local S = ns.SUPPORTERS
    if not S then return y end
    y = y - 10
    local pct = math.floor((S.pct or 0) + 0.5)
    local title = ns.L("免费事业支持榜", "Supporters")
    y = line(c, y, W, GOLD .. title .. "|r", { hdr = true, font = "GameFontNormal", h = 22,
        right = DIM .. ((S.updatedAt or ""):sub(6, 16)) .. ns.L(" 更新", " updated") .. "|r" })
    y = line(c, y, W, TXT .. ns.L("GearInsight 永久免费，靠玩家一起托着。每一笔支持都直接变成服务器时长和 AI 分析次数——这面墙记着每一位让它继续免费的人。",
        "GearInsight is free forever, carried by players. Every bit of support becomes server time and AI analysis — this wall remembers everyone who keeps it free.") .. "|r")
    y = line(c, y, W, TXT .. ns.L("本周运营费", "This week's running costs") .. "|r  " .. DIM .. ns.L("每周四 0 点重置，累计不清零", "resets Thursday 00:00 (UTC+8)") .. "|r",
        { right = GOLD .. string.format(ns.L("已覆盖 %d%%", "%d%% covered"), pct) .. "|r" })
    -- 进度条：服务器（金）+ AI（蓝）
    local barW = W - 20
    local function bar(x, w, r, g, b, a)
        local t = c:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", x, y); t:SetSize(w, 6); t:SetColorTexture(r, g, b, a)
    end
    bar(8, barW, 1, 1, 1, 0.08)
    local ws = math.min(barW, barW * (S.serverPct or 0) / 100)
    local wl = math.min(barW - ws, barW * (S.llmPct or 0) / 100)
    if ws > 0.5 then bar(8, ws, 0.91, 0.78, 0.42, 1) end
    if wl > 0.5 then bar(8 + ws, wl, 0.43, 0.65, 0.97, 1) end
    y = y - 10
    y = line(c, y, W, GOLD .. ((pct < 100) and string.format(ns.L("还差 %d%%，就能让 GearInsight 免费再撑一周", "%d%% to go to keep GearInsight free for another week"), 100 - pct)
        or ns.L("本周的服务器和 AI 费用已经有人替大家付了", "This week's server and AI costs are covered")) .. "|r")
    y = line(c, y, W, DIM .. ns.L("|cffe8c86a金色|r = 服务器（网站、镜像、数据更新）  |cff6ea6f7蓝色|r = AI 分析用的大模型 Token。支持只花在这两样上。",
        "|cffe8c86aGold|r = servers (site, mirror, data updates)  |cff6ea6f7Blue|r = AI analysis tokens. Support is spent on these two only.") .. "|r")
    -- 两列：金额最高 10 人 / 最近支持者（名字职业色 + 职业图标；留言放悬停）
    local colW = math.floor((W - 12) / 2)
    local RANKC = { "|cffffd700", "|cffc0c0c0", "|cffcd7f32" }
    local function col(x0, head, rows, byRank)
        local yy = line(c, y, W, GOLD .. head .. "|r", { x = x0, w = colW, font = "GameFontNormalSmall", oneline = true })
        local rank, lastA, lastC = 0, nil, nil
        for i, rw in ipairs(rows or {}) do
            if i > 10 then break end
            local name, realm, amt, msg, n, cur, cls, ts = rw[1], rw[2], rw[3], rw[4], rw[5], rw[7], rw[8], rw[9]
            if amt ~= lastA or (cur or "CNY") ~= lastC then rank = i end
            lastA, lastC = amt, cur or "CNY"
            local lead = byRank and ((RANKC[rank] or DIM) .. rank .. "|r") or (DIM .. ((ts or ""):sub(6, 10):gsub("-", "/")) .. "|r")
            local who = classIcon(cls ~= "" and cls or nil) .. "|cff" .. classHex(cls ~= "" and cls or nil) .. (name or "?") .. "|r"
                .. ((realm and realm ~= "") and (" " .. DIM .. trunc(realm, 5) .. "|r") or "")
            local tip = ((msg and msg ~= "") and ("“" .. msg .. "”\n") or "") .. (name or "")
                .. ((realm and realm ~= "") and (" · " .. realm) or "") .. ((ts and ts ~= "") and ("\n" .. ts) or "")
            yy = line(c, yy, W, lead .. "  " .. who, { x = x0, w = colW, oneline = true, tip = tip,
                right = GOLD .. money(amt, cur) .. "|r" .. (((n or 1) > 1) and (DIM .. " " .. n .. ns.L("笔", "x") .. "|r") or "") })
        end
        return yy
    end
    local yl = col(0, ns.L("金额最高 10 人", "Top 10"), S.top, true)
    local yr = col(colW + 8, ns.L("最近支持者", "Recent supporters"), S.recent or S.top, false)
    y = math.min(yl, yr) - 4
    local url = ns.LandingURL("support")
    y = line(c, y, W, GOLD .. ns.L("去支持 / 上榜登记", "Support / get on the wall") .. "|r  " .. DIM
        .. ns.L("（点击复制网址，打开后支付面板自动弹出，登记时角色名和服务器已填好）", "(click to copy — the page opens the support panel with your character filled in)") .. "|r", {
        cta = true, h = 22, tipTitle = title,
        tip = ns.L("微信 / 支付宝 / Ko-fi 都在这一页。登记后名字进榜，插件下一版一起带进来。", "WeChat / Alipay / Ko-fi on one page. Your name joins the wall and ships with the next addon version.") .. "\n\n" .. url,
        click = function() copy(title, url) end })
    return y - 6
end

-- ---------- 资讯页：更多功能在站外 ----------
function ns.NewsOffsite(c, y, W)
    y = y - 10
    y = line(c, y, W, GOLD .. ns.L("更多功能在站外", "More on the website") .. "|r", { hdr = true, font = "GameFontNormal", h = 22 })
    local function link(label, url, hint, shown)
        y = line(c, y, W, TXT .. label .. "|r  |cff66ccff" .. (shown or url) .. "|r  " .. DIM .. hint .. "|r", {
            oneline = true, tip = hint .. "\n\n" .. url, tipTitle = ns.L("点击复制地址", "Click to copy"),
            click = function() copy(label, url) end })
    end
    link(ns.L("无限专区", "Forever hub"), ns.LandingURL("home"),
        ns.L("你这个角色的升级路线 · 天赋模拟 · 掉落表 · 宏库 · 公测数据", "Your character's route · talent sim · loot · macros · beta data"),
        ns.zh and "gearinsight.cn/wow/forever" or "gearinsight.app/wow/en/forever")
    link(ns.L("升级路线网页版", "Leveling route (web)"), ns.LandingURL("route"),
        ns.L("按你的阵营 / 种族 / 等级排好，手机上也能看", "Laid out for your faction, race and level — works on phones too"),
        ns.zh and "gearinsight.cn/wow/forever/go" or "gearinsight.app/wow/en/forever/go")
    if ns.zh then
        y = line(c, y, W, TXT .. "微信小程序|r  |cff66ccff微信搜「GearInsight」|r  " .. DIM .. "无限天赋模拟 · 掉落 · 公测数据 · 战绩卡，手机随时看|r", {
            oneline = true, tip = "微信里搜「GearInsight」打开小程序；" .. (ns.SlashHint or "/gif") .. " card 出战绩卡二维码，扫码直接进小程序",
            click = function() copy("微信小程序", "GearInsight") end })
    end
    return y - 4
end

-- ---------- 斜杠：/gi support · /gi site ----------
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.support = ns.ShowSupportLink
ns.ExtraSlash["支持"] = ns.ShowSupportLink
ns.ExtraSlash.site = function() copy(ns.L("无限专区", "Forever hub"), ns.LandingURL("home")) end
ns.ExtraSlash.web = ns.ExtraSlash.site
