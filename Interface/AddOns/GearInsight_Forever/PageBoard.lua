-- 共建页（10-20 需求看板）：玩家提、作者做 —— 正在做 / 待排期 / 最近交付 / 共建者，数据 = 全局 GI_BOARD（Board.lua）
--   Board.lua 由 Windows 更新器从共建看板简报接口拉下来写成 Lua（插件自己不联网），/reload 后生效。
--   ⛔ 国服 09-24 付费插件治理：这里不出现金额（¥ / 元）/ 会员 / 徽章 / 「支持作者」按钮 / 打赏链接。
--   10-20 用户实测后明确放开：可以放共建看板的「条目页」和「提交页」链接（复制框，插件不能开浏览器）；
--     ⛔ 仍不许放任何打赏 / 助力 / 会员链接。点任一条 → 复制 /wow/en/board/<id>；顶部「报 BUG」「提需求」→ 复制 /wow/en/board/new?kind=…&realm=forever
--     链接带角色身份参数（&c=角色&r=服务器&g=区域&cls=职业&spec=天赋&v=插件版本&s=addon），网站据此绑定身份。
--   最近交付只留最近 5 条（用户「多了太乱」）。
--   10-20 用户第二轮：人名不打码、按职业色（authorCls / authorServer，名字后「-服务器」暗色）；
--     条目显示助力点数和人次（纯数字，⛔不出现 ¥ / 元）+ 助力人；底部三组：支持最多 / 提需求最多 / 提 BUG 最多（各 3 人）。
--   ⛔ 别给暴雪全局表重新赋值（UISpecialFrames 只 table.insert）。
-- 同文件挂 /gi bug（/gif bug）：弹一个可复制的 BUG 报告小窗，复制后粘到「报 BUG」提交页的「详细说明」里。
local _, ns = ...

local GOLD = { 1, 0.82, 0 }
-- 类型：颜色 + 中英名（bug 红 · 需求金 · 手法迭代绿 · 数据纠错蓝 · 提案灰 · 专精紫）
local KIND = {
    bug = { 1, 0.32, 0.32, "BUG", "Bug" },
    feat = { 1, 0.82, 0, "需求", "Feature" },
    rot = { 0.35, 0.9, 0.45, "手法迭代", "Rotation" },
    data = { 0.35, 0.65, 1, "数据纠错", "Data fix" },
    prop = { 0.65, 0.65, 0.65, "提案", "Proposal" },
    spec = { 0.72, 0.48, 1, "专精", "Spec" },
}
-- 全部服务器视图里每条行首的服务器小标：颜色 + 中英名
local REALM_TAG = {
    retail = { "4fa3ff", "正式服", "Retail" },
    forever = { "33ff99", "无限", "Forever" },
    titan = { "ff9933", "时光服", "Titan" },
    all = { "b0b0b0", "通用", "All" },
}
local CHECK ="|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"   -- ⛔ 别用 ✓ 字符：游戏字体没字形会显示成方框

-- 服务器来的字：| 转义（防颜色码 / 超链接注入），英文客户端换半角标点
local function esc(s)
    if s == nil then return "" end
    s = tostring(s):gsub("|", "||"):gsub("[\r\n]+", " ")
    return ns.EnSafe(s) or s
end
local function str(v) return (type(v) == "string" and v) or (type(v) == "number" and tostring(v)) or "" end
-- "2026-10-20 11:46" / "2026-10-20T11:46:00+08:00" → "10-20 11:46"
local function md(ts)
    ts = str(ts)
    local m, d, H, M = ts:match("^%d+%-(%d+)%-(%d+)[ T](%d+):(%d+)")
    if m then return m .. "-" .. d .. " " .. H .. ":" .. M end
    local m2, d2 = ts:match("^%d+%-(%d+)%-(%d+)")
    if m2 then return m2 .. "-" .. d2 end
    return ts
end
local function fullTime(ts)
    ts = str(ts)
    local a, H, M = ts:match("^(%d+%-%d+%-%d+)[ T](%d+):(%d+)")
    if a then return a .. " " .. H .. ":" .. M end
    return ts
end
local function list(t) return type(t) == "table" and t or {} end
local function hex(r, g, b) return string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

-- 人名：职业色（RAID_CLASS_COLORS[职业 token]，客户端没有这张表 / 不认识的职业 → 浅色）+ 「-服务器」暗色
local function nameC(name, cls, server)
    name = str(name)
    if name == "" then return "" end
    local col = "e6e6e6"
    local rc = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[str(cls):upper()]
    if type(rc) == "table" then
        if type(rc.colorStr) == "string" and #rc.colorStr == 8 then col = rc.colorStr:sub(3)
        elseif rc.r then col = hex(rc.r, rc.g or 1, rc.b or 1) end
    end
    local s = "|cff" .. col .. esc(name) .. "|r"
    if str(server) ~= "" then s = s .. "|cff808080-" .. esc(server) .. "|r" end
    return s
end
ns._BoardNameC = nameC   -- 测试用

-- 第二行的「谁提的」：作者自排 / 首报人（bug）/ 提议人；手法共建（kind=spec）没有提议人 → nil
local function whoText(it)
    if it.byDev then return ns.L("作者自排", "Picked by the author") end
    if it.kind == "spec" then return nil end
    local a = str(it.author)
    local lab = (it.kind == "bug") and ns.L("首报人 ", "Reported by ") or ns.L("提议人 ", "Proposed by ")
    return lab .. (a ~= "" and nameC(a, it.authorCls, it.authorServer) or ns.L("玩家", "a player"))
end
-- 助力：「助力 40 · 2 人次」（纯数字）+ 「助力人：A、B、C」（职业色，最多 3 个）
local function powerLines(it)
    local pt, bt
    local pw, pn = tonumber(it.power) or 0, tonumber(it.powerN) or 0
    if pw > 0 then
        pt = ns.L("助力 ", "Boost ") .. pw .. (pn > 0 and (" · " .. string.format(ns.L("%d 人次", "%d backers"), pn)) or "")
    end
    local names = {}
    for _, b in ipairs(list(it.backers)) do
        if type(b) == "table" and str(b.name) ~= "" and #names < 3 then names[#names + 1] = nameC(b.name, b.cls, b.server) end
    end
    if #names > 0 then bt = ns.L("助力人：", "Backers: ") .. table.concat(names, ns.L("、", ", ")) end
    return pt, bt
end

-- ---------- 链接复制框（插件不能开浏览器 → 弹单行复制框，已全选，Ctrl+C，Esc 关）----------
local SITE = "https://gearinsight.cn"
local REALM = "forever"
local linkF
function ns.ShowBoardLink(titleText, url, hint)
    if not linkF then
        local f = CreateFrame("Frame", "GearInsightForeverBoardLink", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(520, 140); f:SetPoint("CENTER", 0, 120); f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetClampedToScreen then f:SetClampedToScreen(true) end
        f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -30, 0); f.title:SetJustifyH("LEFT")
        local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        e:SetPoint("TOPLEFT", 20, -40); e:SetPoint("RIGHT", -18, 0); e:SetHeight(26)
        e:SetAutoFocus(true); e:SetMaxLetters(0)
        e:SetScript("OnEscapePressed", function(s) s:ClearFocus(); f:Hide() end)
        e:SetScript("OnEnterPressed", function() f:Hide() end)
        -- 只读：玩家改了字就还原成链接，并重新全选
        e:SetScript("OnTextChanged", function(s, user) if user and f.url and s:GetText() ~= f.url then s:SetText(f.url); s:HighlightText() end end)
        e:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
        f.edit = e
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.hint:SetPoint("TOPLEFT", 16, -74); f.hint:SetPoint("RIGHT", -16, 0); f.hint:SetJustifyH("LEFT")
        f.hint:SetTextColor(0.7, 0.7, 0.7)
        local foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        foot:SetPoint("BOTTOM", 0, 12)
        foot:SetText(ns.L("已全选：Ctrl+C 复制，Esc 关闭", "Selected - Ctrl+C to copy, Esc to close"))
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)   -- 战斗中原生红叉走 HideUIPanel 会被拦 → 直接 Hide
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GearInsightForeverBoardLink") end   -- ⛔只 insert，不重新赋值
        linkF = f
    end
    linkF.url = url
    linkF.title:SetText(ns.EnSafe(titleText or ""))
    linkF.hint:SetText(hint and ns.EnSafe(hint) or "")
    linkF.edit:SetText(url or "")
    linkF:Show()
    linkF.edit:SetFocus(); linkF.edit:HighlightText()
    ns._boardLinkF = linkF   -- 测试用
end
local function idOf(it) return tonumber(str(it and it.no):match("(%d+)")) end
-- URL 编码：显式 ASCII 字符集（只留 A-Z a-z 0-9 - _ . ~，其余每个字节 %XX；中文名 / 服务器按 UTF-8 字节编码）
local function urlenc(s)
    return (str(s):gsub("[^A-Za-z0-9%-_%.~]", function(ch) return string.format("%%%02X", ch:byte()) end))
end
-- 区域：GetCurrentRegionName 优先，没有就按 GetCurrentRegion 编号（1 美 2 韩 3 欧 4 台 5 国服）
local function regionCode()
    if type(GetCurrentRegionName) == "function" then
        local ok, n = pcall(GetCurrentRegionName)
        if ok and type(n) == "string" and n ~= "" then return n:lower() end
    end
    if type(GetCurrentRegion) == "function" then
        local ok, n = pcall(GetCurrentRegion)
        local map = { "us", "kr", "eu", "tw", "cn" }
        if ok and map[tonumber(n) or 0] then return map[tonumber(n)] end
    end
    return ""
end
-- 角色身份参数（网站据此把提交绑定到角色）；拿不到的留空
local function idParams()
    local function safe(f, ...) if type(f) ~= "function" then return nil end; local r = { pcall(f, ...) }; if r[1] then return (unpack or table.unpack)(r, 2) end end
    local name = safe(UnitName, "player")
    local realm = safe(GetRealmName) or ""
    local _, cls = safe(UnitClass, "player")
    if ns.Secret(name) then name = nil end
    local spec = ns.BoardSpecName and ns.BoardSpecName() or ""
    return "&c=" .. urlenc(name) .. "&r=" .. urlenc(realm) .. "&g=" .. urlenc(regionCode()) .. "&cls=" .. urlenc(cls)
        .. "&spec=" .. urlenc(spec) .. "&v=" .. urlenc(ns.AddonVersion and ns.AddonVersion() or "") .. "&s=addon"
end
ns._BoardIdParams = idParams   -- 测试用
local function openItem(id)
    ns.ShowBoardLink(ns.L("复制链接，用浏览器打开看这一条的进度", "Copy this link to open the item on the website"),
        SITE .. "/wow/en/board/" .. id .. "?" .. idParams():sub(2))
end
local function openNew(kind)
    ns.ShowBoardLink(kind == "bug" and ns.L("报 BUG：复制链接，用浏览器打开（可附截图 / 视频）", "Report a bug: copy this link and open it in your browser")
            or ns.L("提需求：复制链接，用浏览器打开", "Request a feature: copy this link and open it in your browser"),
        SITE .. "/wow/en/board/new?kind=" .. kind .. "&realm=" .. REALM .. idParams(),
        kind == "bug" and ns.L("提示：先输入 " .. (ns.SlashHint or "/gi") .. " bug 复制报告，粘到页面的「详细说明」里。",
            "Tip: type " .. (ns.SlashHint or "/gi") .. " bug first and paste the report into the details box.") or nil)
end

local function build(p)
    local y0 = ns.PageHeader(p, ns.L("共建", "Build Board"),
        ns.L("玩家提、作者做——正在做什么、接下来做什么、谁提的。", "Players suggest, the author builds - what's in progress, what's next, and who asked for it."))
    -- 最上面两个按钮：点了弹出对应提交页链接（⛔ 按钮文字别放 emoji，游戏字体显示成方框）
    local bBug = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    bBug:SetSize(120, 24); bBug:SetPoint("TOPLEFT", 12, y0); bBug:SetText(ns.L("报 BUG", "Report a bug"))
    bBug:SetScript("OnClick", function() openNew("bug") end)
    local bReq = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    bReq:SetSize(140, 24); bReq:SetPoint("LEFT", bBug, "RIGHT", 8, 0); bReq:SetText(ns.L("提需求", "Request a feature"))
    bReq:SetScript("OnClick", function() openNew("feat") end)
    -- 10-20 用户「加一个按钮看作者全部排期（包括无限和正式服）」：全部服务器 ↔ 本服；
    --   更新器还没写 GI_BOARD.everyone（0.2.49 及以前）→ 按钮改成弹网站看板链接
    local bAll = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    bAll:SetSize(130, 24); bAll:SetPoint("LEFT", bReq, "RIGHT", 8, 0)
    p._bdBug, p._bdReq, p._bdAll = bBug, bReq, bAll
    local top = y0 - 30
    local CW = 620
    local sf = ns.Scroll(p, 4, top, 646, 474 + top - 6)
    p.sf = sf
    local c, y, firstSection   -- render() 每次换一张新的滚动内容（切视图时旧的整张藏掉）

    local function text(parent, font, str_, x, w, r, g, b, maxLines, yy)
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", x, -(yy or y)); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        if maxLines and fs.SetMaxLines then fs:SetMaxLines(maxLines) end
        fs:SetText(str_)
        if r then fs:SetTextColor(r, g, b) end
        return fs, math.max(12, math.ceil(fs:GetStringHeight() or 12))
    end
    -- 板块标题（10-20 用户「不同板块加分隔符，要醒目、一眼能分清」，照正式服 sepLine / hdr）：
    --   板块之间：留 16px → 整宽 2px 金线（alpha 0.55）→ 留 10px；标题行高 28、GameFontNormalLarge、金色底 0.16 + 左侧 5px 金条，右侧「N 条」
    --   （条目行每次新建、色条固定 3px，不复用标题行，不会把 5px 带过去）
    local function section(title, n)
        if firstSection then
            firstSection = false
            y = y + 8
        else
            y = y + 16
            local sep = c:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
            sep:SetPoint("TOPLEFT", 0, -y); sep:SetSize(CW, 2)
            y = y + 2 + 10
        end
        local hr = CreateFrame("Frame", nil, c)
        hr:SetPoint("TOPLEFT", 0, -y); hr:SetSize(CW, 28)
        local bg = hr:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
        local bar = hr:CreateTexture(nil, "BORDER"); bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
        bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetWidth(5)
        local t = hr:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("LEFT", 12, 0); t:SetText(title); t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if n then
            local r = hr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r:SetPoint("RIGHT", -10, 0); r:SetTextColor(0.75, 0.75, 0.75)
            r:SetText(string.format(ns.L("%d 条", "%d items"), n))
        end
        y = y + 28 + 6
    end
    local function none(msg)
        local _, h = text(c, "GameFontDisableSmall", msg or ns.L("暂无", "Nothing here yet"), 10, CW - 10)
        y = y + h + 6
    end
    -- 一条：第一行（大一号字）类型 · GI 编号 · 标题；第二行（小字灰）提议人 · 开工 · 版本跨度。整条可点 → 复制网站链接
    local function itemRow(it, line1, sub)
        if type(it) ~= "table" then return end
        local k = KIND[str(it.kind)] or KIND.prop
        local row = CreateFrame("Frame", nil, c)
        row:SetPoint("TOPLEFT", 0, -y); row:SetWidth(CW)
        local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(k[1], k[2], k[3], 0.06)
        local sw = row:CreateTexture(nil, "BORDER"); sw:SetColorTexture(k[1], k[2], k[3], 0.95)
        sw:SetPoint("TOPLEFT", 0, -3); sw:SetPoint("BOTTOMLEFT", 0, 3); sw:SetWidth(3)
        local ry = 7
        local _, h1 = text(row, "GameFontHighlight", line1, 12, CW - 20, nil, nil, nil, 2, ry)
        ry = ry + h1
        if sub and sub ~= "" then
            ry = ry + 4
            local _, h2 = text(row, "GameFontHighlightSmall", sub, 12, CW - 20, 0.62, 0.62, 0.62, 5, ry)
            ry = ry + h2
        end
        ry = ry + 7
        row:SetHeight(ry)
        local id = idOf(it)
        if id then
            local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function() openItem(id) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(ns.L("点击：复制这一条的网站链接", "Click: copy the website link for this item"), 1, 0.82, 0)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        y = y + ry + 5
    end
    local function kindHead(it, prefix, realmTag)
        local k = KIND[str(it.kind)] or KIND.prop
        local rt = ""
        if realmTag then
            local R = REALM_TAG[str(it.realm)] or REALM_TAG.all
            rt = "|cff" .. R[1] .. "[" .. ns.L(R[2], R[3]) .. "]|r "
        end
        return rt .. "|cff" .. hex(k[1], k[2], k[3]) .. ns.L(k[4], k[5]) .. "|r  "
            .. (prefix and ("|cffffd200" .. prefix .. "|r  ") or "")
            .. "|cff999999" .. esc(it.no) .. "|r  " .. esc(it.title)
    end
    local function verSpan(it)
        if it.kind == "rot" and (str(it.verFrom) ~= "" or str(it.verTo) ~= "") then
            return esc(str(it.verFrom) ~= "" and it.verFrom or "?") .. " → " .. esc(str(it.verTo) ~= "" and it.verTo or "?")
        end
        return ""
    end
    -- 第二行：提议人 · 开工 · 版本跨度 · 助力 N · M 人次；有助力人再换一行「助力人：…」
    -- 手法共建（kind=spec）没有提议人：只显示助力信息，连助力人都没有时写「手法共建」
    local function subOf(it, lead)
        local parts = {}
        for _, x in ipairs(lead or {}) do parts[#parts + 1] = x end
        local who = whoText(it)
        if who then parts[#parts + 1] = who end
        if not lead and str(it.started) ~= "" then parts[#parts + 1] = ns.L("开工 ", "started ") .. md(it.started) end
        local v = verSpan(it)
        if v ~= "" then parts[#parts + 1] = v end
        local pt, backers = powerLines(it)
        if pt then parts[#parts + 1] = pt end
        if it.kind == "spec" and not who and not backers then parts[#parts + 1] = ns.L("手法共建", "Rotation co-build") end
        local s = table.concat(parts, " · ")
        if backers then s = (s ~= "" and (s .. "\n") or "") .. backers end
        return ns.EnSafe(s)
    end

    local function itemsOf(t, sec, realmTag, posPrefix)
        if #list(t) == 0 then none() end
        for i, it in ipairs(list(t)) do
            if type(it) == "table" then
                local pre = posPrefix and string.format(ns.L("第 %d 位", "#%d"), tonumber(it.pos) or i) or nil
                itemRow(it, kindHead(it, pre, realmTag), subOf(it))
            end
        end
    end

    local function render(view)
    local old = c
    c = CreateFrame("Frame", nil, sf); c:SetSize(646, 10)
    sf:SetScrollChild(c)
    if old then old:Hide() end
    p.c = c
    y, firstSection = 4, true
    if sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
    local B = _G.GI_BOARD
    local E = type(B) == "table" and type(B.everyone) == "table" and B.everyone or nil
    if view == "all" and E then
        -- 全部服务器：正在做 / 待做 / 待排期，每条行首带服务器小标
        local _, hc = text(c, "GameFontNormal", ns.L("作者全部排期（正式服 · 无限 · 时光服 · 通用）", "All of the author's schedule (Retail - Forever - Titan - All)"), 2, CW)
        y = y + hc + 2
        section(ns.L("正在做", "In progress"), #list(E.doing)); itemsOf(E.doing, "doing", true)
        section(ns.L("待做", "To do"), #list(E.todo)); itemsOf(E.todo, "todo", true)
        section(ns.L("待排期", "Up next"), #list(E.next)); itemsOf(E.next, "next", true, true)
    elseif type(B) ~= "table" then
        y = y + 10
        local _, h = text(c, "GameFontHighlight", ns.L("还没有同步到共建数据，稍后自动同步（每 10 分钟最多一次）。",
            "No build board data yet - it syncs automatically (at most once every 10 minutes)."), 2, CW)
        y = y + h + 12
    else
        local C = type(B.counts) == "table" and B.counts or {}
        local function cnt(k, t) return tonumber(C[k]) or #list(t) end
        local nDoing, nNext, nTodo, nWeek = cnt("doing", B.doing), cnt("next", B.next), cnt("todo", B.todo), tonumber(C.week) or 0
        -- 1. 计数行
        local _, hc = text(c, "GameFontNormal", ns.EnSafe(string.format(ns.L("正在做 %s · 待排期 %s · 待做 %s · 本周交付 %s", "In progress %s - Up next %s - To do %s - Shipped this week %s"),
            "|cffffffff" .. nDoing .. "|r", "|cffffffff" .. nNext .. "|r", "|cffffffff" .. nTodo .. "|r", "|cff33ff99" .. nWeek .. "|r")), 2, CW)
        y = y + hc + 2
        -- 2. 正在做
        section(ns.L("正在做", "In progress"), #list(B.doing))
        if #list(B.doing) == 0 then none() end
        for _, it in ipairs(list(B.doing)) do
            if type(it) == "table" then itemRow(it, kindHead(it), subOf(it)) end
        end
        -- 3. 待排期（第 n 位）
        section(ns.L("待排期", "Up next"), #list(B.next))
        if #list(B.next) == 0 then none() end
        for i, it in ipairs(list(B.next)) do
            if type(it) == "table" then
                itemRow(it, kindHead(it, string.format(ns.L("第 %d 位", "#%d"), tonumber(it.pos) or i)), subOf(it))
            end
        end
        -- 待做（10-20 服务端分成 池子 / 待排期 / 待做 / 正在做 / 交付：todo = 有人投票或作者钉选的条目，常驻显示）
        section(ns.L("待做", "To do"), #list(B.todo))
        itemsOf(B.todo, "todo")
        -- 4. 最近交付（只留最近 5 条 —— 10-20 用户「多了太乱」）：第一行 ✓ 类型 · 编号 · 标题；第二行 时间 · 版本 · 提议人
        local nShipShow = 0
        for _, it in ipairs(list(B.shipped)) do if type(it) == "table" then nShipShow = nShipShow + 1 end end
        section(ns.L("最近交付", "Recently shipped"), math.min(5, nShipShow))
        if #list(B.shipped) == 0 then none() end
        local nShip = 0
        for _, it in ipairs(list(B.shipped)) do
            if nShip >= 5 then break end
            if type(it) == "table" then
                nShip = nShip + 1
                local lead = { md(it.shipped) }
                if str(it.version) ~= "" then lead[#lead + 1] = "|cff33ff99" .. esc(it.version) .. "|r" end
                itemRow(it, CHECK .. " " .. kindHead(it), subOf(it, lead))
            end
        end
        -- 5. 共建者：三小组（10-20 用户要：支持最多 3 人（原叫打赏最多，已统一改名）、提需求最多 3 人、提 BUG 最多 3 人），名字职业色，空组写「暂无」
        section(ns.L("共建者", "Builders"), nil)
        local T = type(B.tops) == "table" and B.tops or {}
        local GROUPS = {
            { "tip", ns.L("支持最多", "Top supporters"), false },
            { "feat", ns.L("提需求最多", "Most requests"), true },
            { "bug", ns.L("提 BUG 最多", "Most bug reports"), true },
        }
        for _, g in ipairs(GROUPS) do
            local names = {}
            for _, pp in ipairs(list(T[g[1]])) do
                if type(pp) == "table" and str(pp.name) ~= "" and #names < 3 then
                    local s = nameC(pp.name, pp.cls, pp.server)
                    if g[3] and tonumber(pp.n) then s = s .. "|cff999999 · " .. string.format(ns.L("%d 条", "%d"), tonumber(pp.n)) .. "|r" end
                    names[#names + 1] = s
                end
            end
            local line = "|cffffd200" .. g[2] .. "|r  " .. (#names > 0 and table.concat(names, "   ") or ("|cff808080" .. ns.L("暂无", "None yet") .. "|r"))
            local _, h = text(c, "GameFontHighlightSmall", ns.EnSafe(line), 10, CW - 14)
            y = y + h + 6
        end
    end
    -- 6. 底部说明
    y = y + 10
    local S = ns.SlashHint or "/gi"
    local _, hf = text(c, "GameFontHighlightSmall", ns.EnSafe(ns.L(
        "点任意一条可复制它在网站上的链接。想提需求 / 报 BUG：点最上面的按钮；报 BUG 前可以先输入 " .. S .. " bug 生成报告。被采纳上线后，这里会写上你的名字。",
        "Click any item to copy its website link. To request a feature or report a bug, use the buttons at the top (type " .. S .. " bug first for a bug report). Once it ships, your name shows up here.")),
        2, CW, 0.8, 0.8, 0.8)
    y = y + hf + 6
    if type(B) == "table" and str(B.updated) ~= "" then
        local _, hu = text(c, "GameFontDisableSmall", ns.L("数据更新于 ", "Data updated ") .. fullTime(B.updated), 2, CW)
        y = y + hu + 4
    end
    c:SetHeight(y + 12)
    end   -- render

    local view = "local"
    local function syncAllBtn()
        bAll:SetText(view == "all" and ns.L("本服", "This realm") or ns.L("全部服务器", "All realms"))
    end
    bAll:SetScript("OnClick", function()
        local B = _G.GI_BOARD
        if not (type(B) == "table" and type(B.everyone) == "table") then
            ns.ShowBoardLink(ns.L("在网站看三个服的全部排期：复制链接，用浏览器打开", "See the full schedule for all three realms: copy this link and open it in your browser"),
                SITE .. "/wow/en/board?" .. idParams():sub(2),
                ns.L("同步后，这里可以直接看全部服务器的排期。", "Once synced, you can see every realm's schedule right here."))
            return
        end
        view = (view == "all") and "local" or "all"
        syncAllBtn(); render(view)
    end)
    bAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ns.L("作者全部排期（包括无限、正式服、时光服）", "The author's full schedule (Forever, Retail, Titan)"), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    bAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncAllBtn()
    render(view)
    p._bdRender = render   -- 测试用
end

ns.RegisterPage({ key = "board", order = 3.55, title = ns.L("共建", "Build Board"), tabTitle = ns.L("共建", "Board"),
    icon = "Interface\\Icons\\Trade_BlackSmithing", hold = true, build = build })

-- ---------- /gi bug：可复制的 BUG 报告 ----------
local bugF
-- UTF-8 安全截前 n 个字
local function cut(s, n)
    local out, k = {}, 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        k = k + 1
        if k > n then out[#out + 1] = "..."; break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end
-- BugGrabber（BugSack 的底层）最近一条错误；没装 = nil
local function lastError()
    local bg = _G.BugGrabber
    local db
    if type(bg) == "table" and type(bg.GetDB) == "function" then
        local ok, r = pcall(bg.GetDB, bg)
        if ok and type(r) == "table" then db = r end
    end
    if not db and type(_G.BugGrabberDB) == "table" and type(_G.BugGrabberDB.errors) == "table" then db = _G.BugGrabberDB.errors end
    if not db then return nil end
    local e = db[#db]
    if e == nil then return ns.L("无（BugGrabber 里没有记录）", "none (BugGrabber is empty)") end
    local m = type(e) == "table" and e.message or e
    if type(m) ~= "string" or ns.Secret(m) or m == "" then return ns.L("无", "none") end
    m = m:gsub("[\r\n]+", " "):gsub("|", "||")
    return cut(m, 300)
end
-- 职业 + 天赋（投点最多的那系）+ 各系点数
local function classSpec()
    local cls = UnitClass and select(1, UnitClass("player")) or "?"
    local spec, bare
    if GetSpecialization and GetSpecializationInfo then
        local ok, i = pcall(GetSpecialization)
        if ok and i then local ok2, _, name = pcall(GetSpecializationInfo, i); if ok2 and type(name) == "string" then spec, bare = name, name end end
    end
    if not spec and GetTalentTabInfo then
        local best, bp, pts = nil, -1, {}
        for i = 1, 3 do
            local r = { pcall(GetTalentTabInfo, i) }
            if r[1] then
                local name, n
                for j = 2, #r do   -- 不同客户端返回位置不同：第一个字符串当系名，第一个像投点数的整数当点数
                    local v = r[j]
                    if not name and type(v) == "string" and v ~= "" and not v:find("\\", 1, true) and not tonumber(v) then name = v end
                    if not n and type(v) == "number" and v >= 0 and v <= 61 and v == math.floor(v) and v ~= i then n = v end
                end
                pts[#pts + 1] = n or 0
                if (n or 0) > bp then best, bp = name, n or 0 end
            end
        end
        if bp > 0 and best then bare = best end
        if #pts > 0 then spec = ((bp > 0 and best) or ns.L("未分配天赋", "no talents")) .. " (" .. table.concat(pts, "/") .. ")" end
    end
    return cls or "?", spec or "?", bare or ""
end
-- 链接身份参数用：当前天赋 / 专精名（拿不到 = 空串）
function ns.BoardSpecName() local _, _, b = classSpec(); return b end

local function reportText()
    local ver, build = "?", "?"
    if GetBuildInfo then local a, b = GetBuildInfo(); ver, build = a or "?", b or "?" end
    local cls, spec = classSpec()
    local err = lastError()
    local L = {
        "GearInsight BUG 报告",
        string.format("插件：GearInsight_Forever %s   客户端：%s %s   语言：%s", ns.AddonVersion and ns.AddonVersion() or "?", ver, build, GetLocale and GetLocale() or "?"),
        string.format("服务器类型：无限   角色：%s %s   等级 %s", cls, spec, tostring(UnitLevel and UnitLevel("player") or "?")),
        "时间：" .. (date and date("%Y-%m-%d %H:%M") or "?"),
        "最近一条错误：" .. (err or "无"),
        "问题描述：（在这里写发生了什么、怎么复现）",
    }
    return table.concat(L, "\n")
end

local function makeBugFrame()
    local f = CreateFrame("Frame", "GearInsightForeverBugReport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(600, 300); f:SetPoint("CENTER", 0, 60); f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -30, 0); f.title:SetJustifyH("LEFT")
    f.title:SetText(ns.EnSafe(ns.L("复制这段，到 GearInsight 网站或小程序「共建看板 → 报 BUG」粘贴",
        "Copy this and paste it on the GearInsight website or mini program: Build Board → Report a bug")))
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", 14, -32); f.hint:SetTextColor(0.7, 0.7, 0.7)
    f.hint:SetText(ns.L("已全选：Ctrl+C 复制 · 可以先在最后一行写上问题描述 · Esc 关闭", "Selected: Ctrl+C to copy - add your description on the last line - Esc to close"))
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -52); sf:SetPoint("BOTTOMRIGHT", -32, 48)
    local bg = f:CreateTexture(nil, "ARTWORK"); bg:SetColorTexture(0, 0, 0, 0.35)
    bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4); bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true); e:SetAutoFocus(false); e:SetMaxLetters(0)
    e:SetFontObject(ChatFontNormal or GameFontHighlight); e:SetWidth(540)
    e:SetScript("OnEscapePressed", function() f:Hide() end)
    e:SetScript("OnTextChanged", function(self) local p = self:GetParent(); if p and p.UpdateScrollChildRect then p:UpdateScrollChildRect() end end)
    e:SetScript("OnCursorChanged", function(self, _, cy, _, ch)   -- 光标跟着滚
        local p = self:GetParent()
        if not (p and p.GetVerticalScroll) then return end
        local top, h = p:GetVerticalScroll(), p:GetHeight()
        cy = -(cy or 0)
        if cy < top then p:SetVerticalScroll(cy) elseif cy + (ch or 0) > top + h then p:SetVerticalScroll(cy + (ch or 0) - h) end
    end)
    sf:SetScrollChild(e)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() e:SetFocus() end)
    f.edit = e
    local sel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sel:SetSize(110, 24); sel:SetPoint("BOTTOMLEFT", 14, 14); sel:SetText(ns.L("重新全选", "Select all"))
    sel:SetScript("OnClick", function() e:SetFocus(); e:HighlightText() end)
    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetSize(90, 24); ok:SetPoint("BOTTOMRIGHT", -14, 14); ok:SetText(ns.L("关闭", "Close"))
    ok:SetScript("OnClick", function() f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)   -- 战斗中原生红叉走 HideUIPanel 会被拦 → 直接 Hide
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GearInsightForeverBugReport") end   -- Esc 关；⛔只 insert，不重新赋值
    return f
end

function ns.ShowBugReport()
    bugF = bugF or makeBugFrame()
    bugF.edit:SetText(reportText())
    bugF:Show()
    bugF.edit:SetFocus(); bugF.edit:SetCursorPosition(0); bugF.edit:HighlightText()
    ns._bugF = bugF   -- 测试用
end

ns.ExtraSlash = ns.ExtraSlash or {}
if not ns.ExtraSlash.bug then ns.ExtraSlash.bug = ns.ShowBugReport end
if not ns.ExtraSlash["报错"] then ns.ExtraSlash["报错"] = ns.ShowBugReport end
