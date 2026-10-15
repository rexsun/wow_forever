-- 资讯页（10-07 用户「之前的资讯栏目、群等信息都搬过来」+「板式也变成这种页签的」）：
--   资讯卡两列（开服时间线 / 新内容 / 规则，来自网站 hub.json）→ 插件更新一行 → 关注 GearInsight 三列频道卡 + 微信群二维码
-- 数据：NewsData.lua（scripts/gi_forever_news.py 生成；频道 / 群码和正式服 GearInsight 同一份）
local _, ns = ...

local CH_ICON = "Interface\\AddOns\\GearInsight_Forever\\media\\ch_"

local function daysTo(ymd)
    local y, m, d = (ymd or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not y or not time then return nil end
    local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 7 })
    return math.ceil((t - time()) / 86400)
end

function ns.WxGroupValid()
    local wg = ns.News and ns.News.wx
    if not wg or not wg.rows or #wg.rows == 0 or not wg.expires then return false end
    local y, m, d = wg.expires:match("^(%d+)%-(%d+)%-(%d+)$")
    if not y then return false end
    return time() <= time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, min = 59 })
end

-- 微信群二维码：用色块画模块矩阵，不依赖图片文件（照正式服 GearInsight:ShowWxGroupQR）
local qrF
function ns.ShowWxGroupQR()
    local wg = ns.News and ns.News.wx
    if not wg or not wg.rows then return end
    local n, px, pad = wg.n or #wg.rows, 6, 18
    local size = n * px
    if not qrF then
        qrF = CreateFrame("Frame", "GearInsightForeverWxQR", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        qrF:SetFrameStrata("DIALOG"); qrF:SetFrameLevel(60); qrF:SetPoint("CENTER")
        if qrF.SetBackdrop then
            qrF:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 } })
            qrF:SetBackdropColor(1, 1, 1, 1); qrF:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
        end
        qrF:EnableMouse(true); qrF:SetMovable(true); qrF:RegisterForDrag("LeftButton")
        qrF:SetScript("OnDragStart", qrF.StartMoving); qrF:SetScript("OnDragStop", qrF.StopMovingOrSizing)
        local cb = CreateFrame("Button", nil, qrF, "UIPanelCloseButton"); cb:SetPoint("TOPRIGHT", -2, -2)
        qrF.title = qrF:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); qrF.title:SetPoint("TOP", 0, -pad); qrF.title:SetTextColor(0.1, 0.1, 0.1)
        qrF.foot = qrF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); qrF.foot:SetPoint("BOTTOM", 0, pad - 4); qrF.foot:SetTextColor(0.35, 0.35, 0.35)
        qrF.cells = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverWxQR") end
    end
    qrF:SetSize(size + pad * 2, size + pad * 2 + 52)
    qrF.title:SetText(wg.name or "GearInsight 微信群")
    qrF.foot:SetText("微信扫码入群 · 有效期至 " .. (wg.expires or "") .. "（7 天一换）")
    for _, t in ipairs(qrF.cells) do t:Hide() end
    local k = 0
    for r = 1, n do
        local rowS = wg.rows[r] or ""
        for c = 1, n do
            if rowS:sub(c, c) == "1" then
                k = k + 1
                local t = qrF.cells[k]
                if not t then t = qrF:CreateTexture(nil, "ARTWORK"); t:SetColorTexture(0, 0, 0, 1); qrF.cells[k] = t end
                t:ClearAllPoints(); t:SetPoint("TOPLEFT", qrF, "TOPLEFT", pad + (c - 1) * px, -(pad + 30) - (r - 1) * px)
                t:SetSize(px, px); t:Show()
            end
        end
    end
    qrF:Show()
    ns._wxQrF = qrF   -- 测试用
end

local function bgOf(f, a)
    local t = f:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(1, 1, 1, a or 0.05)
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
end

local function build(p)
    local N = ns.News or {}
    local sf, c = ns.Scroll(p, 4, -4, 646, 466)
    local y = 0
    -- 资讯卡：两列
    local cw = 312
    for i, cd in ipairs(N.cards or {}) do
        local card = CreateFrame("Button", nil, c)
        card:SetSize(cw, 74); card:SetPoint("TOPLEFT", ((i - 1) % 2) * (cw + 10), -math.floor((i - 1) / 2) * 80)
        bgOf(card)
        local ic = card:CreateTexture(nil, "ARTWORK"); ic:SetSize(30, 30); ic:SetPoint("TOPLEFT", 8, -8)
        ic:SetTexture("Interface\\Icons\\" .. cd.i); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local t = card:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, 0)
        t:SetPoint("RIGHT", -8, 0); t:SetJustifyH("LEFT"); t:SetWordWrap(false)
        local title = ns.L(cd.t, cd.tEn)
        local left = cd.launch and daysTo(cd.launch)
        if left and left > 0 then title = title .. "  |cff33ff99" .. ns.L("还有 " .. left .. " 天", left .. " days left") .. "|r" end
        t:SetText(title)
        local b = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
        b:SetPoint("RIGHT", -8, 0); b:SetJustifyH("LEFT"); b:SetJustifyV("TOP"); b:SetHeight(40)
        b:SetText(ns.EnSafe(ns.L(cd.d, cd.dEn)))
        card:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L(cd.t, cd.tEn), 1, 0.82, 0)
            GameTooltip:AddLine(ns.EnSafe(ns.L(cd.d, cd.dEn)), 1, 1, 1, true); GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = math.floor((i - 1) / 2) * 80 + 80
    end
    -- 插件更新：一行
    -- 10-12 用户：标题 0.4.26、这行还写 0.2.0 → 版本号一律读 toc（和 UI.lua 标题同一个来源），摘要取 releases 里同版本那条
    --   ⛔ 别再写死版本号；发版时 scripts/gi_forever_news.py 的 RELEASES 加一条（新的在前）再重跑生成 NewsData.lua
    local cur = ns.AddonVersion and ns.AddonVersion() or ""
    local rel
    for _, r in ipairs(N.releases or {}) do
        if cur == "" or r.v == cur then rel = r; break end
    end
    if cur ~= "" or rel then
        local up = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); up:SetPoint("TOPLEFT", 2, -y - 4); up:SetWidth(634)
        up:SetJustifyH("LEFT")
        local ver = (cur ~= "" and cur) or rel.v
        local txt = rel and ns.L(rel.zh, rel.en) or ns.L("更新内容见 CurseForge / 网站更新日志", "See the changelog on CurseForge / the website")
        up:SetText(ns.EnSafe(string.format("|cffffd200GearInsight %s %s|r  %s", ns.L("无限版", "Forever"), ver, txt)))
        y = y + 8 + up:GetStringHeight()
    end
    -- 10-12 支持榜 + 更多功能在站外（Offsite.lua，照正式服资讯页第二段 / 工具页「更多功能在站外」；HOLD 期间没有这两个函数就跳过）
    if ns.NewsSupport then y = -ns.NewsSupport(c, -y, 634) end   -- 这页 y 往下为正，Offsite.lua 往下为负
    if ns.NewsOffsite then y = -ns.NewsOffsite(c, -y, 634) end
    -- 关注 / 频道：三列卡片
    local hd = c:CreateFontString(nil, "OVERLAY", "GameFontNormal"); hd:SetPoint("TOPLEFT", 2, -y - 10)
    hd:SetText(ns.L("关注 GearInsight · 找组织、问问题、看更新", "Follow GearInsight"))
    y = y + 32
    local list = {}
    for _, x in ipairs((ns.zh and N.channels_cn) or N.channels_en or {}) do list[#list + 1] = x end
    -- 微信群（只简体；群码 7 天一换，过期自动隐藏；点击弹二维码）
    if ns.zh and ns.WxGroupValid() then
        list[#list + 1] = { "微信群", (N.wx.name or "GearInsight交流群"), "", "wechat", qr = true }
    end
    local w3 = 205
    for i, ch in ipairs(list) do
        local b = CreateFrame("Button", nil, c)
        b:SetSize(w3, 36); b:SetPoint("TOPLEFT", ((i - 1) % 3) * (w3 + 9), -y - math.floor((i - 1) / 3) * 40)
        bgOf(b)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(26, 26); ic:SetPoint("LEFT", 6, 0)
        if ch[4] == "web" then ic:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02"); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        else ic:SetTexture(CH_ICON .. ch[4]) end
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t:SetPoint("TOPLEFT", ic, "TOPRIGHT", 6, -1); t:SetText(ch[1])
        local v = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); v:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        v:SetPoint("RIGHT", -4, 0); v:SetJustifyH("LEFT"); v:SetWordWrap(false)
        v:SetText(ch.qr and ("|cff33ff99" .. ns.L("点击弹出二维码", "Click for QR") .. "|r") or ch[2])
        b:SetScript("OnClick", function()
            if ch.qr then ns.ShowWxGroupQR()
            else ns.ShowBox(ch[1] .. " · " .. ch[2], ns.L("Ctrl+C 复制，去对应 App 搜索 / 打开", "Ctrl+C, then search / open it"), ch[3]) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(ch[1], 1, 0.82, 0)
            GameTooltip:AddLine(ch.qr and ("微信扫码入群 · 有效至 " .. (N.wx.expires or "")) or ch[3], 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    y = y + math.ceil(#list / 3) * 40 + 8
    local foot = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); foot:SetPoint("TOPLEFT", 2, -y)
    foot:SetText(ns.L("数据随插件版本一起更新 · 点卡片可复制账号", "Updated with each addon version · click to copy"))
    c:SetHeight(y + 24)
end

ns.RegisterPage({ key = "news", order = 3.5, title = ns.L("资讯", "News"), build = build })
