-- GIWidgets：GearInsight 系插件共用的自绘控件（深色底 + 金边，和 GuildInsight / 主插件页签同一套配色）。
-- 10-11 公会升级二期（docs/guild-growth-2026-10-design.md「自绘控件套件替换原生按钮」）。
--
-- ⛔ 本文件在下面四处**逐字节相同**（各插件只能加载自己目录下的文件，没法共享一份）：
--      addon-guild/GuildInsight/GIWidgets.lua
--      addon-forever/GearInsight_Forever/GIWidgets.lua
--      addon-titan/GearInsight_Titan/GIWidgets.lua
--      services/wow-agent/hold_src/GearInsight/core/GIWidgets.lua（正式服，HOLD 源）
--    改这里必须同步拷到另外三处；scripts/gi_guild_recruit_test.py 比对四份 md5。
-- ⛔ 多个插件同时加载：全局 GIWidgets 只保留版本号（MINOR）最高的那份实现（LibStub 式），各插件 ns.W 都指向它。
--    改了行为就把 MINOR + 1，不然先加载的旧版会赢。
-- ⛔ 游戏字体没有 ✓ ✗ 之类的字形（会变方框）：打勾 / 打叉一律用 W.OK / W.NO 贴图。
-- ⛔ 只用 60 级经典客户端也有的贴图（无限 / 时光服客户端里一定存在）。
local _, ns = ...
local MINOR = 2   -- 10-12 公会抽屉改版（不透明底 / 卡片列表 / 精选位 / 自绘关闭 / logo / 页签防出屏）
local W = _G.GIWidgets
if type(W) ~= "table" or (tonumber(W.MINOR) or 0) < MINOR then
    W = type(W) == "table" and W or {}
    W.MINOR = MINOR

    local LOC = GetLocale and GetLocale() or "enUS"
    W.zh = (LOC == "zhCN" or LOC == "zhTW")
    W.tw = (LOC == "zhTW")
    -- 三语：简体 / 英文 / 繁体（繁体不给就退回简体，繁简互通比英文好读）
    function W.L(cn, en, tw)
        if W.tw and tw and tw ~= "" then return tw end
        if W.zh or not en or en == "" then return cn end
        return en
    end

    W.GOLD = { 1, 0.82, 0 }
    W.EDGE_GOLD = { 0.85, 0.68, 0.25, 1 }
    W.OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
    W.NO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"
    W.WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t"

    local BD_BTN = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
    local BD_PANEL = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
    W.BD_BTN, W.BD_PANEL = BD_BTN, BD_PANEL
    local TPL = BackdropTemplateMixin and "BackdropTemplate" or nil

    -- 按钮配色：{ 底色, 边框 }
    local KIND = {
        normal = { { 0.09, 0.09, 0.11, 0.95 }, { 0.62, 0.50, 0.22, 0.90 } },
        primary = { { 0.24, 0.18, 0.04, 0.98 }, { 1.00, 0.82, 0.00, 1.00 } },
        danger = { { 0.20, 0.06, 0.05, 0.95 }, { 0.80, 0.32, 0.25, 0.95 } },
        off = { { 0.06, 0.06, 0.07, 0.80 }, { 0.30, 0.30, 0.30, 0.60 } },
    }

    function W.Paint(t, r, g, b, a)
        if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
    end

    function W.Solid(parent, layer, r, g, b, a)
        local t = parent:CreateTexture(nil, layer or "BACKGROUND")
        W.Paint(t, r, g, b, a)
        return t
    end

    -- 图标：Interface\Icons 下的切掉 7% 黑边；插件自带的 logo 用整张。
    --   SetTexture 明确返回 false（新客户端：文件不存在）→ 换兜底图标（60 级经典客户端就有）
    W.LOGO_FALLBACK = "Interface\\Icons\\INV_Misc_Gear_01"
    function W.SetIcon(tex, path)
        path = path or W.LOGO_FALLBACK
        local ok = tex:SetTexture(path)
        if ok == false and path ~= W.LOGO_FALLBACK then
            path = W.LOGO_FALLBACK
            tex:SetTexture(path)
        end
        if tostring(path):lower():find("interface\\icons\\", 1, true) then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        else tex:SetTexCoord(0, 1, 0, 1) end
    end

    -- 自绘关闭按钮（深底金边 + ASCII「X」，不用原生红叉 UIPanelCloseButton）；默认点了关父框
    function W.CloseButton(parent, onClick)
        local b = CreateFrame("Button", nil, parent, TPL)
        b:SetSize(22, 22)
        if b.SetBackdrop then
            b:SetBackdrop(BD_BTN)
            b:SetBackdropColor(0.09, 0.09, 0.11, 0.95)
            b:SetBackdropBorderColor(0.62, 0.50, 0.22, 0.9)
        end
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 1, 0); fs:SetText("X")
        b.fs = fs
        local hl = W.Solid(b, "HIGHLIGHT", 1, 0.82, 0, 0.15)
        hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
        b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function() fs:SetTextColor(1, 0.82, 0) end)
        b:SetScript("OnClick", onClick or function(self) local p = self:GetParent(); if p then p:Hide() end end)
        return b
    end

    local function num(v, d) return (type(v) == "number" and v > 0) and v or d end
    local function enabled(b) if b.IsEnabled then return b:IsEnabled() and true or false end return true end

    function W.PaintButton(b)
        -- LockHighlight 过的（分段按钮的当前项：日 / 周 / 月、成员 / 装备…）= 金色主按钮样式
        local kind = rawget(b, "_giLocked") and "primary" or (rawget(b, "_giKind") or "normal")
        local k = KIND[enabled(b) and kind or "off"] or KIND.normal
        if b.SetBackdropColor then
            b:SetBackdropColor(k[1][1], k[1][2], k[1][3], k[1][4])
            b:SetBackdropBorderColor(k[2][1], k[2][2], k[2][3], k[2][4])
        end
    end

    function W.SetKind(b, kind) b._giKind = kind; W.PaintButton(b) end

    -- 按钮：接口和 UIPanelButtonTemplate 一样用（SetText / SetSize / Enable / Disable / SetScript("OnClick")）
    --   kind = normal（默认）/ primary（金，主操作）/ danger（红，删除 / 拒绝）
    function W.Button(parent, name, kind)
        local b = CreateFrame("Button", name, parent, TPL)
        b:SetSize(80, 22)
        if b.SetBackdrop then b:SetBackdrop(BD_BTN) end
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 0, 0)
        if b.SetFontString then b:SetFontString(fs) end
        if b.SetNormalFontObject then
            b:SetNormalFontObject("GameFontNormal")
            b:SetHighlightFontObject("GameFontHighlight")
            b:SetDisabledFontObject("GameFontDisable")
        end
        local hl = W.Solid(b, "HIGHLIGHT", 1, 0.82, 0, 0.12)
        hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
        b._giKind = kind or "normal"
        b._giFs = fs
        -- 分段按钮用 LockHighlight 标当前项：原生模板是高亮框，这里换成金底金边（实例字段盖住框的方法，原方法照调）
        local lock, unlock = b.LockHighlight, b.UnlockHighlight
        b.LockHighlight = function(self) self._giLocked = true; W.PaintButton(self); if lock then lock(self) end end
        b.UnlockHighlight = function(self) self._giLocked = false; W.PaintButton(self); if unlock then unlock(self) end end
        W.PaintButton(b)
        if b.HookScript then
            b:HookScript("OnEnable", W.PaintButton)
            b:HookScript("OnDisable", W.PaintButton)
            b:HookScript("OnMouseDown", function(self) if enabled(self) then fs:SetPoint("CENTER", 1, -1) end end)
            b:HookScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
        end
        return b
    end

    -- 竖排大页签（图标 + 名字），和主插件左侧页签同尺寸同配色
    function W.Tab(parent, label, icon, w, h)
        local b = CreateFrame("Button", nil, parent, TPL)
        b:SetSize(w or 96, h or 48)
        if b.SetBackdrop then b:SetBackdrop(BD_BTN) end
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetSize(22, 22); ic:SetPoint("LEFT", 8, 0)
        W.SetIcon(ic, icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 6, 0); fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText(label or "")
        local hl = W.Solid(b, "HIGHLIGHT", 1, 0.82, 0, 0.08); hl:SetAllPoints()
        b.ic, b.fs, b.label = ic, fs, fs
        W.SelectTab(b, false)
        return b
    end

    function W.SelectTab(b, on)
        if b.SetBackdropColor then
            if on then b:SetBackdropColor(0.13, 0.12, 0.07, 0.98); b:SetBackdropBorderColor(1, 0.82, 0, 0.9)
            else b:SetBackdropColor(0.05, 0.05, 0.08, 0.95); b:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8) end
        end
        if b.fs then
            if on then b.fs:SetTextColor(1, 0.82, 0) else b.fs:SetTextColor(0.75, 0.75, 0.75) end
        end
        if b.ic and b.ic.SetDesaturated then pcall(b.ic.SetDesaturated, b.ic, not on) end
    end

    -- 挂在面板**右**外侧的竖排页签（和左侧页签对称）：同一个面板挂几个就往下排
    -- ⛔ 自己挂在框上的字段一律 rawget 读（框的元表会把不认识的键转去方法表）
    function W.SideTab(host, label, icon, top)
        host._giSide = rawget(host, "_giSide") or {}
        local b = W.Tab(host, label, icon)
        local prev = host._giSide[#host._giSide]
        if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
        else b:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, top or -56) end
        host._giSide[#host._giSide + 1] = b
        -- 页签挂在面板外：把夹屏范围往右扩一个页签宽，拖到屏幕边也不会把页签挤出屏（ChatFrame 同款写法：right 正数 = 往外扩）
        if host.SetClampRectInsets then
            local l, r, t, bt
            if host.GetClampRectInsets then l, r, t, bt = host:GetClampRectInsets() end
            local need = num(b.GetWidth and b:GetWidth(), 96) + 2
            if (tonumber(r) or 0) < need then host:SetClampRectInsets(tonumber(l) or 0, need, tonumber(t) or 0, tonumber(bt) or 0) end
        end
        return b
    end

    -- 屏幕右边在 f 坐标系里的 x（缩放不同也对）；取不到返回 nil
    function W.ScreenRight(f)
        local us = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
        local ur = UIParent and UIParent.GetRight and UIParent:GetRight()
        local fs = f and f.GetEffectiveScale and f:GetEffectiveScale()
        if type(us) ~= "number" or type(ur) ~= "number" or type(fs) ~= "number" or fs <= 0 then return nil end
        return ur * us / fs
    end

    -- 右外侧页签被屏幕右边裁掉（主面板贴着右边 / 夹屏只算面板本体）→ 主面板整体左移到页签完整露出
    function W.KeepSideTabsOnScreen(host)
        local side = rawget(host, "_giSide")
        if type(side) ~= "table" or #side == 0 then return end
        local maxR
        for _, b in ipairs(side) do
            local r = b.GetRight and b:GetRight()
            if type(r) == "number" and (not maxR or r > maxR) then maxR = r end
        end
        local sr = W.ScreenRight(host)
        if not maxR or not sr then return end
        local over = maxR - sr + 2
        if over <= 0 or not host.GetPoint then return end
        local p, rel, rp, x, y = host:GetPoint(1)
        if not p then return end
        host:ClearAllPoints()
        host:SetPoint(p, rel, rp, (tonumber(x) or 0) - over, tonumber(y) or 0)
    end

    -- 面板 / 弹窗底（深色 + 金边）
    function W.SkinPanel(f)
        if f.SetBackdrop then
            f:SetBackdrop(BD_PANEL)
            f:SetBackdropColor(0.04, 0.05, 0.07, 0.96)
            f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
        end
        return f
    end

    -- 弹窗：标题 + 关闭 + 可拖动 + Esc 关；name 给了才能进 UISpecialFrames（Esc 关）
    function W.Panel(name, parent, w, h, title)
        local f = CreateFrame("Frame", name, parent or UIParent, TPL)
        f:SetSize(w or 360, h or 300)
        W.SkinPanel(f)
        f:EnableMouse(true)
        if f.SetToplevel then f:SetToplevel(true) end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -34, 0); f.title:SetJustifyH("LEFT")
        if f.title.SetWordWrap then f.title:SetWordWrap(false) end
        f.title:SetText(title or "")
        local close = W.CloseButton(f)
        close:SetPoint("TOPRIGHT", -8, -8)
        f.close = close
        local line = W.Solid(f, "ARTWORK", 0.85, 0.68, 0.25, 0.45)
        line:SetPoint("TOPLEFT", 8, -36); line:SetPoint("TOPRIGHT", -8, -36); line:SetHeight(1)
        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 12, -42); f.body:SetPoint("BOTTOMRIGHT", -12, 12)
        if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
        f:Hide()
        return f
    end

    function W.Draggable(f)
        if f.SetMovable then f:SetMovable(true) end
        if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
        f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    end

    -- 小标题：金字 + 下划线
    function W.Header(parent, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetJustifyH("LEFT")
        fs:SetText(text or "")
        return fs
    end

    -- 数据卡：大数字 + 名称 + 一行小字（比如「上周 12」）
    function W.Stat(parent, w, h)
        local c = CreateFrame("Frame", nil, parent, TPL)
        c:SetSize(w or 150, h or 56)
        if c.SetBackdrop then
            c:SetBackdrop(BD_BTN)
            c:SetBackdropColor(0.07, 0.07, 0.09, 0.95)
            c:SetBackdropBorderColor(0.45, 0.38, 0.17, 0.8)
        end
        c.num = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        c.num:SetPoint("TOPLEFT", 10, -8)
        c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.label:SetPoint("LEFT", c.num, "RIGHT", 6, 0)
        c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        c.sub:SetPoint("BOTTOMLEFT", 10, 8); c.sub:SetPoint("RIGHT", -6, 0); c.sub:SetJustifyH("LEFT")
        function c.Set(_, num, label, sub)
            c.num:SetText(num ~= nil and tostring(num) or "-")
            c.label:SetText(label or "")
            c.sub:SetText(sub or "")
        end
        return c
    end

    -- 进度条（纯贴图）：bar:SetValue(0..1, 文字)
    function W.Bar(parent, w, h)
        local b = CreateFrame("Frame", nil, parent)
        b:SetSize(w or 200, h or 14)
        local bg = W.Solid(b, "BACKGROUND", 1, 1, 1, 0.08); bg:SetAllPoints()
        b.fill = W.Solid(b, "ARTWORK", 0.85, 0.68, 0.25, 0.85)
        b.fill:SetPoint("TOPLEFT"); b.fill:SetPoint("BOTTOMLEFT"); b.fill:SetWidth(1)
        b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.txt:SetPoint("CENTER")
        function b.SetValue(_, v, text)
            v = tonumber(v) or 0
            if v < 0 then v = 0 elseif v > 1 then v = 1 end
            local full = b:GetWidth() or w or 200
            if type(full) ~= "number" or full <= 0 then full = w or 200 end
            b.fill:SetWidth(math.max(1, full * v))
            b.fill:SetShown(v > 0)
            b.txt:SetText(text or "")
        end
        return b
    end

    -- 复制框：Ctrl+C 复制网址（插件不能开浏览器）
    local copyF
    function W.Copy(text, title)
        if not copyF then
            copyF = W.Panel("GIWidgetsCopyFrame", UIParent, 460, 110, "")
            copyF:SetFrameStrata("DIALOG"); copyF:SetPoint("CENTER", 0, 120)
            W.Draggable(copyF)
            copyF.box = CreateFrame("EditBox", nil, copyF.body, "InputBoxTemplate")
            copyF.box:SetSize(410, 24); copyF.box:SetPoint("TOP", 0, -6)
            copyF.box:SetAutoFocus(true)
            copyF.box:SetScript("OnEscapePressed", function() copyF:Hide() end)
            copyF.box:SetScript("OnEnterPressed", function() copyF:Hide() end)
            copyF.hint = copyF.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            copyF.hint:SetPoint("TOP", copyF.box, "BOTTOM", 0, -8)
        end
        copyF.title:SetText(title or "")
        copyF.hint:SetText(W.L("Ctrl+C 复制，到浏览器或微信里打开", "Press Ctrl+C to copy", "Ctrl+C 複製，到瀏覽器或微信裡打開"))
        copyF.box:SetText(text or "")
        copyF:Show()
        copyF.box:SetFocus(); copyF.box:HighlightText()
    end

    -- ---------- 主插件右侧「公会」页签（三服共用）----------
    -- opts：
    --   game     = "retail" / "forever" / "titan"
    --   top      = 页签离面板顶的距离（负数，和左侧第一个页签对齐）
    --   list     = function() return items, updatedAt end   招募列表（GuildRecruit.lua 的 items，见下面 ITEM 字段表）
    --   region   = 只显示这个大区（正式服按客户端大区过滤；nil = 不过滤）
    --   qr       = function(title, foot, url)   弹二维码（各插件自己的 QR.lua；没有就退回复制框）
    --   qrEncode = function(text) return matrix end   内嵌二维码用（各插件 ns.QR.Encode）；不给 = 空态只放按钮
    --   logo     = 插件自带 logo 贴图（页签图标 + 引导卡 + 空态插图）；不给 = W.LOGO_FALLBACK
    -- ITEM（更新器 Guild.cs / scripts/gi_guild_recruit_snapshot.py 写，15 个老字段 + 10-12 追加 4 个尾字段，旧数据没有尾字段也能显示）：
    --   { id, 名字, 阵营, 服务器, 大区, 目标, {职业}, 规模, 拾取, WCL进度, 服务器排名, 团员数, 简介, 已招满, 更新日, 规则集, 活动日("1"=周一…"7"=周日), 活动时段, 热度 }
    --   list 的第 3 个返回值 = featured（精选位，见 W.PickFeatured；可替换的数据来源，插件里没有任何收费逻辑）
    W.SITE = (LOC == "zhCN") and "gearinsight.cn" or "gearinsight.app"
    local GAME_TXT = { retail = { "正式服", "Retail", "正式服" }, forever = { "无限", "Forever", "無限" }, titan = { "时光服", "Titan", "時光服" } }

    -- 阵营：色块标签（部落红 / 联盟蓝）
    local FAC = {
        ["部落"] = "horde", Horde = "horde", HORDE = "horde",
        ["联盟"] = "alliance", ["聯盟"] = "alliance", Alliance = "alliance", ALLIANCE = "alliance",
    }
    local FAC_BG = { horde = { 0.62, 0.12, 0.10 }, alliance = { 0.12, 0.32, 0.68 } }
    local FAC_TXT = { horde = { "部落", "Horde", "部落" }, alliance = { "联盟", "Alliance", "聯盟" } }

    -- 职业色（写死：经典客户端的 RAID_CLASS_COLORS 没有 DH / 唤魔师）；{ 色, 中文短名, 英文 }
    local CLS = {
        ["战士"] = { "c69b6d", "战士", "Warrior" }, ["圣骑士"] = { "f48cba", "圣骑", "Paladin" }, ["聖騎士"] = { "f48cba", "聖騎", "Paladin" },
        ["猎人"] = { "aad372", "猎人", "Hunter" }, ["獵人"] = { "aad372", "獵人", "Hunter" },
        ["盗贼"] = { "fff468", "盗贼", "Rogue" }, ["潜行者"] = { "fff468", "盗贼", "Rogue" }, ["盜賊"] = { "fff468", "盜賊", "Rogue" },
        ["牧师"] = { "ffffff", "牧师", "Priest" }, ["牧師"] = { "ffffff", "牧師", "Priest" },
        ["死亡骑士"] = { "c41e3a", "死骑", "Death Knight" }, ["死亡騎士"] = { "c41e3a", "死騎", "Death Knight" },
        ["萨满祭司"] = { "0070dd", "萨满", "Shaman" }, ["萨满"] = { "0070dd", "萨满", "Shaman" }, ["薩滿"] = { "0070dd", "薩滿", "Shaman" },
        ["法师"] = { "3fc7eb", "法师", "Mage" }, ["法師"] = { "3fc7eb", "法師", "Mage" },
        ["术士"] = { "8788ee", "术士", "Warlock" }, ["術士"] = { "8788ee", "術士", "Warlock" },
        ["武僧"] = { "00ff98", "武僧", "Monk" },
        ["德鲁伊"] = { "ff7c0a", "德鲁伊", "Druid" }, ["德魯伊"] = { "ff7c0a", "德魯伊", "Druid" },
        ["恶魔猎手"] = { "a330c9", "恶魔猎手", "Demon Hunter" }, ["惡魔獵人"] = { "a330c9", "惡魔獵人", "Demon Hunter" },
        ["唤魔师"] = { "33937f", "唤魔师", "Evoker" }, ["喚魔師"] = { "33937f", "喚魔師", "Evoker" },
    }
    function W.ClassText(names, max)
        if type(names) ~= "table" or #names == 0 then return "|cff9a9a9a" .. W.L("职业不限", "Any class", "職業不限") .. "|r" end
        if #names >= 8 then return "|cffffd200" .. W.L("全职业招募", "All classes", "全職業招募") .. "|r" end
        local out = {}
        for i, n in ipairs(names) do
            if i > (max or 6) then out[#out + 1] = "|cff9a9a9a+" .. (#names - i + 1) .. "|r"; break end
            local c = CLS[n]
            out[#out + 1] = c and ("|cff" .. c[1] .. W.L(c[2], c[3], c[2]) .. "|r") or ("|cffbbbbbb" .. tostring(n) .. "|r")
        end
        return table.concat(out, " ")
    end

    -- 活动时间：活动日 "147" + 时段 "20:00-23:00" → 「周一/四/日 20:00-23:00」
    local WD_CN, WD_TW, WD_EN = { "一", "二", "三", "四", "五", "六", "日" }, { "一", "二", "三", "四", "五", "六", "日" }, { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
    function W.FormatSchedule(days, tm)
        days, tm = tostring(days or ""), tostring(tm or "")
        local d = ""
        if days == "1234567" then d = W.L("每天", "Daily", "每天")
        elseif days == "12345" then d = W.L("工作日", "Weekdays", "工作日")
        elseif days == "67" then d = W.L("周末", "Weekends", "週末")
        elseif days ~= "" then
            local cn, tw, en = {}, {}, {}
            for ch in days:gmatch("%d") do
                local i = tonumber(ch)
                if WD_CN[i] then cn[#cn + 1] = WD_CN[i]; tw[#tw + 1] = WD_TW[i]; en[#en + 1] = WD_EN[i] end
            end
            if #cn > 0 then d = W.L("周" .. table.concat(cn, "/"), table.concat(en, "/"), "週" .. table.concat(tw, "/")) end
        end
        if tm ~= "" then d = (d ~= "" and (d .. " ") or "") .. tm end
        return d
    end

    -- ⛔ 不用 %w：字符类随区域设置变，某些环境里中文字节会被当成字母 → 半个汉字没编码
    local function urlEncode(s)
        return (tostring(s or ""):gsub("[^A-Za-z0-9%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
    end
    W.UrlEncode = urlEncode

    -- 招募板网址：带 realm（服务器线 = 小程序 gi_realm）+ server（当前角色所在服务器，招募板按服务器筛）；详情页再带 gid
    function W.GuildBoardUrl(game, gid)
        local server = GetRealmName and GetRealmName() or ""
        local u = "https://" .. W.SITE .. "/wow/guilds" .. (gid and ("/" .. tostring(gid)) or "") .. "?game=" .. game .. "&realm=" .. game
        if server ~= "" and game ~= "titan" then u = u .. "&server=" .. urlEncode(server) end
        if gid then u = u .. "&gid=" .. urlEncode(gid) end
        return u .. "&ref=addon"
    end

    function W.GuildAddonState()
        if _G.GuildInsight and _G.GuildInsight.UI then return "loaded" end
        local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
        if info then
            local ok, name, _, _, _, reason = pcall(info, "GuildInsight")
            if ok and name and reason ~= "MISSING" then return "disabled" end
        end
        return "missing"
    end

    local function showQR(opts, title, foot, url)
        if opts.qr then
            local ok, shown = pcall(opts.qr, title, foot, url)
            if ok and shown ~= false then return end
        end
        W.Copy(url, title)
    end

    -- 内嵌二维码：matrix[行][列] = true(黑)；白底 + 3 格静区，同一行连续黑格合成一块贴图
    function W.DrawQR(box, matrix, px)
        box.cells = rawget(box, "cells") or {}
        for _, t in ipairs(box.cells) do t:Hide() end
        local n = type(matrix) == "table" and #matrix or 0
        if n == 0 then return 0 end
        px = px or 3
        local quiet = 3 * px
        local size = n * px + 2 * quiet
        box:SetSize(size, size)
        if not rawget(box, "bg") then box.bg = W.Solid(box, "BACKGROUND", 1, 1, 1, 1); box.bg:SetAllPoints() end
        local k = 0
        for r = 1, n do
            local row, c = matrix[r], 1
            while c <= n do
                if row[c] then
                    local c2 = c
                    while c2 < n and row[c2 + 1] do c2 = c2 + 1 end
                    k = k + 1
                    local t = box.cells[k]
                    if not t then t = W.Solid(box, "ARTWORK", 0, 0, 0, 1); box.cells[k] = t end
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", box, "TOPLEFT", quiet + (c - 1) * px, -(quiet + (r - 1) * px))
                    t:SetSize((c2 - c + 1) * px, px)
                    t:Show()
                    c = c2 + 1
                else
                    c = c + 1
                end
            end
        end
        return size
    end

    -- 文本块高度：GetStringHeight（宽度已 SetWidth 定死，换行后的真实高度）；取不到（未布局 / 测试桩）用估值
    local function strH(fs, fallback)
        local h = fs.GetStringHeight and fs:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = fallback end
        return math.ceil(h)
    end

    local BD_SOLID = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
    local DR_W, DR_H, PAD = 380, 640, 12
    local INNER = DR_W - PAD * 2            -- 356：内容宽
    local BAR_W = 8                         -- 右侧滚动条占位
    local CARD_W, CARD_H, CARD_GAP = INNER - BAR_W, 62, 6
    local APPLY_W = 76
    local FEAT_H = 96                       -- 精选公会大卡位高
    local BD_FEAT = BD_SOLID
    local ICON = 32
    local MIN_ROWS = 6

    local function makeCard(d, i)
        local r = CreateFrame("Button", nil, d.list, TPL)
        r:SetSize(CARD_W, CARD_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
        if r.SetBackdrop then
            r:SetBackdrop(BD_BTN)
            r:SetBackdropColor(0.075, 0.075, 0.09, 1)
            r:SetBackdropBorderColor(0.42, 0.35, 0.16, 0.85)
        end
        local hl = W.Solid(r, "HIGHLIGHT", 1, 0.82, 0, 0.07)
        hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
        -- 第 1 行：阵营色块 + 公会名
        r.tagBg = W.Solid(r, "ARTWORK", 0.3, 0.3, 0.3, 1)
        r.tagBg:SetSize(36, 16); r.tagBg:SetPoint("TOPLEFT", 10, -9)
        r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.tag:SetPoint("CENTER", r.tagBg, "CENTER", 0, 0)
        r.l = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.l:SetWidth(CARD_W - 10 - 36 - 6 - APPLY_W - 16); r.l:SetJustifyH("LEFT")
        if r.l.SetWordWrap then r.l:SetWordWrap(false) end
        -- 第 2 行：规则集 / 服务器 · 活动时间
        r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.meta:SetPoint("TOPLEFT", 10, -30); r.meta:SetWidth(CARD_W - 20 - APPLY_W - 6); r.meta:SetJustifyH("LEFT")
        if r.meta.SetWordWrap then r.meta:SetWordWrap(false) end
        r.meta:SetTextColor(0.80, 0.80, 0.80)
        -- 第 3 行：缺的职业（职业色）· 规模
        r.need = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.need:SetPoint("TOPLEFT", 10, -45); r.need:SetWidth(CARD_W - 20 - APPLY_W - 6); r.need:SetJustifyH("LEFT")
        if r.need.SetWordWrap then r.need:SetWordWrap(false) end
        -- 右侧：扫码申请
        r.apply = W.Button(r, nil, "primary")
        r.apply:SetSize(APPLY_W, 24); r.apply:SetPoint("RIGHT", -10, 0)
        r:SetScript("OnEnter", function(self)
            if not (GameTooltip and rawget(self, "tip")) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for k, ln in ipairs(self.tip) do
                if k == 1 then GameTooltip:SetText(ln, 1, 0.82, 0, 1, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        if r.EnableMouseWheel then r:EnableMouseWheel(false) end
        r:Hide()
        d.rows[i] = r
        return r
    end

    local function setScroll(d, v)
        local view, total = d._viewH or 0, d._listH or 0
        local maxOff = math.max(0, total - view)
        v = tonumber(v) or 0
        if v < 0 then v = 0 elseif v > maxOff then v = maxOff end
        d._off = v
        if d.scroll.SetVerticalScroll then d.scroll:SetVerticalScroll(v) end
        if maxOff <= 0 then d.track:Hide(); d.thumb:Hide(); return end
        d.track:Show(); d.thumb:Show()
        local th = math.max(24, view * view / total)
        d.thumb:ClearAllPoints(); d.thumb:SetWidth(3); d.thumb:SetHeight(th)
        d.thumb:SetPoint("TOPRIGHT", d.track, "TOPRIGHT", 0, -((view - th) * v / maxOff))
    end

    local function buildDrawer(host, opts, tab)
        local L = W.L
        local d = CreateFrame("Frame", nil, host, TPL)
        d._h = DR_H
        d:SetSize(DR_W, DR_H)
        -- 不透明深色底 + 金边（10-12：半透明底会透出后面的任务追踪）；HIGH 层盖住任务追踪 / 小地图那一列
        if d.SetBackdrop then
            d:SetBackdrop(BD_SOLID)
            d:SetBackdropColor(0.035, 0.04, 0.055, 1)
            d:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
        end
        if d.SetFrameStrata then d:SetFrameStrata("HIGH") end
        if d.SetToplevel then d:SetToplevel(true) end
        if d.SetClampedToScreen then d:SetClampedToScreen(true) end
        d:EnableMouse(true)
        d.logo = opts.logo or W.LOGO_FALLBACK

        -- 标题栏：「公会招募 · 无限」+ 自绘关闭
        local g = GAME_TXT[opts.game] or GAME_TXT.retail
        d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        d.title:SetPoint("TOPLEFT", PAD, -PAD - 2); d.title:SetPoint("RIGHT", -40, 0); d.title:SetJustifyH("LEFT")
        if d.title.SetWordWrap then d.title:SetWordWrap(false) end
        d.title:SetText(L("公会招募", "Guild recruitment", "公會招募") .. "  |cff8a8a8a" .. L("·", "-", "·") .. "  " .. L(g[1], g[2], g[3]) .. "|r")
        d.close = W.CloseButton(d, function() d:Hide(); W.SelectTab(tab, false) end)
        d.close:SetPoint("TOPRIGHT", -8, -8)
        local line = W.Solid(d, "ARTWORK", 0.85, 0.68, 0.25, 0.45)
        line:SetPoint("TOPLEFT", 6, -40); line:SetPoint("TOPRIGHT", -6, -40); line:SetHeight(1)

        -- 精选公会大卡位（引导卡上方）：金边 + 大一号字；字段和列表卡片同名，fillCard 通用
        local f = CreateFrame("Button", nil, d, TPL)
        f:SetSize(INNER, FEAT_H); f:SetPoint("TOPLEFT", PAD, -52)
        if f.SetBackdrop then
            f:SetBackdrop(BD_FEAT)
            f:SetBackdropColor(0.15, 0.115, 0.035, 1)
            f:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        local fhl = W.Solid(f, "HIGHLIGHT", 1, 0.82, 0, 0.07)
        fhl:SetPoint("TOPLEFT", 4, -4); fhl:SetPoint("BOTTOMRIGHT", -4, 4)
        f.badgeBg = W.Solid(f, "ARTWORK", 0.85, 0.68, 0.25, 1)
        f.badgeBg:SetHeight(16); f.badgeBg:SetPoint("TOPLEFT", PAD, -10)
        f.badge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.badge:SetPoint("LEFT", f.badgeBg, "LEFT", 6, 0); f.badge:SetTextColor(0.12, 0.08, 0.01)
        f.tagBg = W.Solid(f, "ARTWORK", 0.3, 0.3, 0.3, 1)
        f.tagBg:SetSize(36, 16); f.tagBg:SetPoint("TOPLEFT", PAD, -34)
        f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.tag:SetPoint("CENTER", f.tagBg, "CENTER", 0, 0)
        f.l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.l:SetWidth(INNER - PAD - 36 - 6 - APPLY_W - PAD - 6); f.l:SetJustifyH("LEFT")
        if f.l.SetWordWrap then f.l:SetWordWrap(false) end
        f.meta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.meta:SetPoint("TOPLEFT", PAD, -58); f.meta:SetWidth(INNER - PAD * 2 - APPLY_W - 6); f.meta:SetJustifyH("LEFT")
        if f.meta.SetWordWrap then f.meta:SetWordWrap(false) end
        f.need = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.need:SetPoint("TOPLEFT", PAD, -76); f.need:SetWidth(INNER - PAD * 2 - APPLY_W - 6); f.need:SetJustifyH("LEFT")
        if f.need.SetWordWrap then f.need:SetWordWrap(false) end
        f.apply = W.Button(f, nil, "primary")
        f.apply:SetSize(APPLY_W, 26); f.apply:SetPoint("RIGHT", -PAD, -6)
        f._padL = PAD
        f:SetScript("OnEnter", function(self)
            if not (GameTooltip and rawget(self, "tip")) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            for k, ln in ipairs(self.tip) do
                if k == 1 then GameTooltip:SetText(ln, 1, 0.82, 0, 1, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f:Hide()
        d.feat = f

        -- 引导卡：logo + 标题 + 正文（高度跟着文字走）+ 两个按钮排在正文下面
        local c = CreateFrame("Frame", nil, d, TPL)
        c:SetPoint("TOPLEFT", PAD, -52); c:SetWidth(INNER); c:SetHeight(120)
        if c.SetBackdrop then
            c:SetBackdrop(BD_BTN)
            c:SetBackdropColor(0.11, 0.10, 0.06, 1)
            c:SetBackdropBorderColor(1, 0.82, 0, 0.6)
        end
        c.ic = c:CreateTexture(nil, "ARTWORK")
        c.ic:SetSize(ICON, ICON); c.ic:SetPoint("TOPLEFT", PAD, -PAD)
        W.SetIcon(c.ic, d.logo)
        c.head = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        c.head:SetWidth(INNER - PAD * 2 - ICON - 10); c.head:SetJustifyH("LEFT")
        c.body = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.body:SetWidth(INNER - PAD * 2); c.body:SetJustifyH("LEFT"); c.body:SetJustifyV("TOP")
        if c.body.SetSpacing then c.body:SetSpacing(3) end
        local bw = math.floor((INNER - PAD * 2 - 8) / 2)
        c.qr = W.Button(c, nil, "primary"); c.qr:SetSize(bw, 24)
        c.copy = W.Button(c); c.copy:SetSize(bw, 24)
        d.cta = c

        -- 列表：小标题 + 更新时间 + 可滚动卡片
        d.listHead = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        d.listHead:SetJustifyH("LEFT")
        d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d.sub:SetJustifyH("RIGHT")
        d.scroll = CreateFrame("ScrollFrame", nil, d)
        d.list = CreateFrame("Frame", nil, d.scroll)
        d.list:SetSize(CARD_W, 10)
        if d.scroll.SetScrollChild then d.scroll:SetScrollChild(d.list) end
        if d.scroll.EnableMouseWheel then d.scroll:EnableMouseWheel(true) end
        d.scroll:SetScript("OnMouseWheel", function(_, delta) setScroll(d, (d._off or 0) - (delta or 0) * (CARD_H + CARD_GAP)) end)
        d.track = W.Solid(d, "ARTWORK", 1, 1, 1, 0.06); d.track:SetWidth(3)
        d.thumb = W.Solid(d, "OVERLAY", 0.85, 0.68, 0.25, 0.85)
        d.rows = {}
        for i = 1, MIN_ROWS do makeCard(d, i) end

        -- 空态：居中 logo + 一句话 + 内嵌招募板二维码
        d.emptyBox = CreateFrame("Frame", nil, d)
        d.emptyIc = d.emptyBox:CreateTexture(nil, "ARTWORK")
        d.emptyIc:SetSize(36, 36)
        W.SetIcon(d.emptyIc, d.logo)
        d.empty = d.emptyBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        d.empty:SetWidth(INNER - 24); d.empty:SetJustifyH("CENTER")
        d.qrBox = CreateFrame("Frame", nil, d.emptyBox)
        d.qrCap = d.emptyBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d.qrCap:SetWidth(INNER - 24); d.qrCap:SetJustifyH("CENTER")
        d.qrBtn = W.Button(d.emptyBox, nil, "primary"); d.qrBtn:SetSize(180, 24)

        d.more = W.Button(d); d.more:SetSize(INNER, 24); d.more:SetPoint("BOTTOM", 0, PAD)
        d:Hide()
        return d
    end

    -- 引导卡排版：图标 32 + 标题（单行时与图标垂直居中）；正文全宽在下面；按钮在正文下面
    local function layoutCta(c)
        local hh = strH(c.head, 14)
        c.head:ClearAllPoints()
        c.head:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + ICON + 10, -(PAD + math.max(0, math.floor((ICON - hh) / 2))))
        local y = PAD + math.max(ICON, hh) + 8
        local body = c.body.GetText and c.body:GetText() or ""
        c.body:ClearAllPoints(); c.body:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        if body ~= "" then y = y + strH(c.body, 42) + 10 end
        c.qr:ClearAllPoints(); c.qr:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
        c.copy:ClearAllPoints(); c.copy:SetPoint("LEFT", c.qr, "RIGHT", 8, 0)
        y = y + 24 + PAD
        c:SetHeight(y)
        return y
    end

    local function boardText() return W.L("微信扫码看招募板", "Guild board (QR)", "微信掃碼看招募板") end

    -- 空态排版：内容整体在列表区里垂直居中
    local function layoutEmpty(d, opts, text, cap, url, btnText)
        local box = d.emptyBox
        d.empty:SetText(text)
        d.qrCap:SetText(cap or "")
        local m
        if opts.qrEncode then
            local ok, mm = pcall(opts.qrEncode, url)
            if ok and type(mm) == "table" and #mm > 0 then m = mm end
        end
        local qs = 0
        if m then
            qs = W.DrawQR(d.qrBox, m, (#m <= 41) and 3 or 2)
            d.qrBox:Show(); d.qrCap:Show(); d.qrBtn:Hide()
        else
            d.qrBox:Hide(); d.qrCap:Hide()
            d.qrBtn:SetText(btnText or boardText())
            d.qrBtn:SetScript("OnClick", function() showQR(opts, cap or "", "", url) end)
            d.qrBtn:Show()
        end
        local th = strH(d.empty, 16)
        local ch = m and strH(d.qrCap, 12) or 0
        local total = 36 + 10 + th + 12 + (m and (qs + 6 + ch) or 24)
        local top = math.max(0, math.floor(((d._viewH or 280) - total) / 2))
        d.emptyIc:ClearAllPoints(); d.emptyIc:SetPoint("TOP", box, "TOP", 0, -top)
        d.empty:ClearAllPoints(); d.empty:SetPoint("TOP", d.emptyIc, "BOTTOM", 0, -10)
        d.qrBox:ClearAllPoints(); d.qrBox:SetPoint("TOP", d.empty, "BOTTOM", 0, -12)
        d.qrCap:ClearAllPoints(); d.qrCap:SetPoint("TOP", d.qrBox, "BOTTOM", 0, -6)
        d.qrBtn:ClearAllPoints(); d.qrBtn:SetPoint("TOP", d.empty, "BOTTOM", 0, -12)
        box:Show()
    end

    local function fillCard(d, opts, r, it)
        local L, game = W.L, opts.game
        local gid, name, fac, server, goal, need, size, loot, prog, rkS, raiders, note, full, day =
            it[1], it[2] or "", it[3] or "", it[4] or "", it[6] or "", it[7] or {}, it[8] or "", it[9] or "", it[10] or "", it[11] or 0, it[12] or 0, it[13] or "", it[14], it[15] or ""
        local rules, days, tm = it[16] or "", it[17] or "", it[18] or ""
        -- 无限没有服务器：老数据（没有尾字段）里「服务器」那格就是规则集（后端 server 空时退回 realm）
        if rules == "" and game == "forever" then rules = server end
        local fk = FAC[fac]
        if fk then
            local bg = FAC_BG[fk]
            W.Paint(r.tagBg, bg[1], bg[2], bg[3], 1)
            r.tag:SetText(L(FAC_TXT[fk][1], FAC_TXT[fk][2], FAC_TXT[fk][3]))
            r.tagBg:Show(); r.tag:Show()
            r.l:ClearAllPoints(); r.l:SetPoint("LEFT", r.tagBg, "RIGHT", 6, 0)
        else
            r.tagBg:Hide(); r.tag:Hide()
            r.l:ClearAllPoints(); r.l:SetPoint("LEFT", r.tagBg, "LEFT", 0, 0)
        end
        r.l:SetText(name)
        -- 第 2 行：无限 = 规则集 · 活动时间；正式服 = 服务器 · 活动时间（没有时间就写目标）
        local parts = {}
        if game == "forever" then
            if rules == "不限" or rules == "" then parts[#parts + 1] = L("规则集不限", "Any ruleset", "規則集不限")
            elseif rules == "普通" then parts[#parts + 1] = L("普通", "Normal", "普通")
            else parts[#parts + 1] = rules end
        elseif server ~= "" then
            parts[#parts + 1] = server
        end
        local when = W.FormatSchedule(days, tm)
        if when ~= "" then parts[#parts + 1] = when elseif goal ~= "" then parts[#parts + 1] = goal end
        r.meta:SetText(table.concat(parts, "  |cff666666" .. L("·", "-", "·") .. "|r  "))
        -- 第 3 行：缺的职业 · 规模
        local nt = L("缺 ", "Need ", "缺 ") .. W.ClassText(need, 6)
        if size ~= "" then nt = nt .. "   |cff9a9a9a" .. size .. "|r" end
        r.need:SetText(nt)
        if full then
            r.apply:SetText(L("已招满", "Full", "已招滿")); W.SetKind(r.apply, "off")
        else
            r.apply:SetText(L("扫码申请", "Apply (QR)", "掃碼申請")); W.SetKind(r.apply, "primary")
        end
        local tip = { "<" .. name .. ">" .. (server ~= "" and game ~= "forever" and ("  " .. server) or "") .. (fac ~= "" and ("  " .. fac) or "") }
        if rules ~= "" and game == "forever" then tip[#tip + 1] = L("规则集：", "Ruleset: ", "規則集：") .. rules end
        if when ~= "" then tip[#tip + 1] = L("活动时间：", "Raid time: ", "活動時間：") .. when end
        if goal ~= "" then tip[#tip + 1] = L("目标：", "Goal: ", "目標：") .. goal end
        if type(need) == "table" and #need > 0 then tip[#tip + 1] = L("招募：", "Need: ", "招募：") .. table.concat(need, L("、", ", ", "、")) end
        if size ~= "" then tip[#tip + 1] = L("规模：", "Size: ", "規模：") .. size end
        if loot ~= "" then tip[#tip + 1] = L("拾取：", "Loot: ", "拾取：") .. loot end
        if prog ~= "" then
            tip[#tip + 1] = L("WCL 进度：", "WCL: ", "WCL 進度：") .. prog
                .. ((tonumber(rkS) or 0) > 0 and ("  " .. string.format(L("服务器第 %d", "realm #%d", "伺服器第 %d"), rkS)) or "")
                .. ((tonumber(raiders) or 0) > 0 and ("  " .. string.format(L("%d 名团员", "%d raiders", "%d 名團員"), raiders)) or "")
        end
        if note ~= "" then tip[#tip + 1] = note end
        if full then tip[#tip + 1] = L("已招满，暂停申请", "Not accepting applications", "已招滿，暫停申請") end
        tip[#tip + 1] = "|cff999999" .. L("点击扫码看详情、申请（联系方式走申请制）", "Click for a QR code to the detail page", "點擊掃碼看詳情、申請（聯繫方式走申請制）")
            .. (day ~= "" and ("  - " .. day) or "") .. "|r"
        r.tip = tip
        local function open()
            showQR(opts, "<" .. name .. ">", L("微信扫一扫看详情、申请", "Scan to view and apply", "微信掃一掃看詳情、申請"), W.GuildBoardUrl(game, gid))
        end
        r:SetScript("OnClick", open)
        r.apply:SetScript("OnClick", open)
        r:Show()
    end

    -- 精选公会：数据给了 featured（{ id = , tag = } 或直接 id，来源可替换）且在列表里 → 用它（tag 不给就写「本周热度第一」）；
    --   没给 → 按热度（第 19 个字段）客观取第一（招满的不算）；数据里没有热度（老格式）→ 不显示，不瞎标
    function W.PickFeatured(list, featured)
        if type(list) ~= "table" then return nil end
        if featured ~= nil then
            local id = featured
            if type(featured) == "table" then id = featured.id or featured[1] end
            for _, it in ipairs(list) do
                if it[1] ~= nil and tostring(it[1]) == tostring(id) then
                    return it, type(featured) == "table" and featured.tag or nil
                end
            end
        end
        local best, bh
        for _, it in ipairs(list) do
            local h = tonumber(it[19])
            if h and h > 0 and not it[14] and (not bh or h > bh) then best, bh = it, h end
        end
        return best, nil
    end

    local function fillDrawer(d, opts)
        local game = opts.game
        local state = W.GuildAddonState()
        local L = W.L
        local c = d.cta
        local H = d._h or DR_H
        -- 引导卡文字
        if game == "titan" then
            c.head:SetText(L("时光服公会招募即将开放", "Titan guild recruitment is coming soon", "時光服公會招募即將開放"))
            c.body:SetText(L("开服后在这里看招募、在游戏里处理申请。会长现在就能扫码预登记，开服第一批上招募板。",
                "Guild masters can pre-register now and be listed first at launch.",
                "開服後在這裡看招募、在遊戲裡處理申請。會長現在就能掃碼預登記，開服第一批上招募板。"))
            c.qr:SetText(L("会长扫码预登记", "Pre-register (QR)", "會長掃碼預登記"))
            c.qr:SetScript("OnClick", function()
                showQR(opts, L("微信扫一扫 · 时光服公会预登记", "Scan · Titan guild pre-registration", "微信掃一掃 · 時光服公會預登記"),
                    L("开服前登记，开服第一批上招募板", "Get listed first at launch", "開服前登記，開服第一批上招募板"), W.GuildBoardUrl("titan"))
            end)
            c.copy:SetText(L("复制网址", "Copy link", "複製網址"))
            c.copy:SetScript("OnClick", function() W.Copy(W.GuildBoardUrl("titan"), L("时光服公会预登记", "Titan guild pre-registration", "時光服公會預登記")) end)
        else
            if state == "disabled" then
                c.head:SetText(L("GuildInsight 公会插件已安装，但没启用", "GuildInsight is installed but disabled", "GuildInsight 公會插件已安裝，但沒啟用"))
                c.body:SetText(L("在角色选择界面左下角「插件」里勾上 GuildInsight，进游戏后这里直接打开招募页：申请在游戏里一键邀请入会。",
                    "Enable GuildInsight in the AddOns list at character select, then this tab opens its recruitment page.",
                    "在角色選擇介面左下角「插件」裡勾上 GuildInsight，進遊戲後這裡直接打開招募頁：申請在遊戲裡一鍵邀請入會。"))
            else
                c.head:SetText(L("装公会插件，申请在游戏里直接处理", "Get GuildInsight: handle applications in game", "裝公會插件，申請在遊戲裡直接處理"))
                c.body:SetText(L("小程序里的入会申请经更新器同步进游戏，会长一键邀请入会；还有日程报名、叫人组队、出货账本。\n安装：GearInsight 更新器「我的插件」里勾上 GuildInsight。",
                    "Applications from the mini program sync into the game; invite with one click. Install: tick GuildInsight in the GearInsight updater.",
                    "小程序裡的入會申請經更新器同步進遊戲，會長一鍵邀請入會；還有日程報名、叫人組隊、出貨帳本。\n安裝：GearInsight 更新器「我的插件」裡勾上 GuildInsight。"))
            end
            c.qr:SetText(boardText())
            c.qr:SetScript("OnClick", function()
                showQR(opts, L("微信扫一扫 · 公会招募板", "Scan · guild board", "微信掃一掃 · 公會招募板"),
                    L("按服务器、阵营、缺的职业筛，一键申请", "Filter by realm, faction and classes, then apply", "按伺服器、陣營、缺的職業篩，一鍵申請"), W.GuildBoardUrl(game))
            end)
            c.copy:SetText(L("复制招募板网址", "Copy board link", "複製招募板網址"))
            c.copy:SetScript("OnClick", function() W.Copy(W.GuildBoardUrl(game), L("公会招募板", "Guild board", "公會招募板")) end)
        end
        c:Show()

        -- 只读招募列表（时光服没有）
        local items, upd, featured = {}, "", nil
        if game ~= "titan" and opts.list then
            local ok, a, b, fe = pcall(opts.list)
            if ok then items, upd, featured = (type(a) == "table" and a or {}), (b or ""), fe end
        end
        local list = {}
        for _, it in ipairs(items) do
            if type(it) == "table" and (not opts.region or not it[5] or it[5] == "" or it[5] == opts.region) then list[#list + 1] = it end
        end

        -- 精选公会大卡位：引导卡上方
        local y = 52
        local fit, ftag = W.PickFeatured(list, featured)
        if fit then
            fillCard(d, opts, d.feat, fit)
            d.feat.badge:SetText(ftag or L("本周热度第一", "Hottest this week", "本週熱度第一"))
            d.feat.badgeBg:SetWidth(num(d.feat.badge.GetStringWidth and d.feat.badge:GetStringWidth(), 72) + 12)
            d.feat:Show()
            y = y + FEAT_H + 10
        else
            d.feat:Hide()
        end
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
        local ctaH = layoutCta(c)

        -- 列表区几何：引导卡下面 → 底部按钮上面
        local yHead = y + ctaH + 14
        local listTop = yHead + 22
        local bottom = (game == "titan") and PAD or (PAD + 24 + 10)
        d._viewH = math.max(80, H - listTop - bottom)
        d.listHead:ClearAllPoints(); d.listHead:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -yHead)
        d.sub:ClearAllPoints(); d.sub:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -(yHead + 2))
        d.scroll:ClearAllPoints(); d.scroll:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -listTop)
        d.scroll:SetSize(CARD_W, d._viewH)
        d.track:ClearAllPoints(); d.track:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -listTop); d.track:SetHeight(d._viewH)
        d.emptyBox:ClearAllPoints(); d.emptyBox:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -listTop)
        d.emptyBox:SetSize(INNER, d._viewH)

        if game == "titan" then
            d.listHead:SetText(""); d.sub:SetText("")
            for _, r in ipairs(d.rows) do r:Hide() end
            d._listH = 0; setScroll(d, 0); d.scroll:Hide()
            layoutEmpty(d, opts, L("开服后这里显示正在招人的公会", "Recruiting guilds will show up here after launch", "開服後這裡顯示正在招人的公會"),
                L("会长微信扫码预登记", "Guild masters: scan to pre-register", "會長微信掃碼預登記"), W.GuildBoardUrl("titan"),
                L("会长扫码预登记", "Pre-register (QR)", "會長掃碼預登記"))
            d.more:Hide()
            return
        end

        d.sub:SetText(upd ~= "" and string.format(L("%s 更新", "updated %s", "%s 更新"), tostring(upd):sub(6, 16)) or "")
        d.listHead:SetText(string.format(L("正在招人的公会（%d）", "Recruiting guilds (%d)", "正在招人的公會（%d）"), #list))
        for i = #d.rows + 1, #list do makeCard(d, i) end
        for i, r in ipairs(d.rows) do
            if list[i] then fillCard(d, opts, r, list[i]) else r:Hide() end
        end
        d._listH = #list > 0 and (#list * (CARD_H + CARD_GAP) - CARD_GAP) or 0
        d.list:SetHeight(math.max(1, d._listH))
        if #list > 0 then
            d.empty:SetText("")
            d.emptyBox:Hide()
            d.scroll:Show()
            setScroll(d, 0)
        else
            d.scroll:Hide(); d._listH = 0; setScroll(d, 0)
            layoutEmpty(d, opts, L("暂时没有招募数据，微信扫码去招募板看", "No data yet - scan to open the guild board", "暫時沒有招募資料，微信掃碼去招募板看"),
                L("微信扫一扫 · 公会招募板（更新器开着会定期刷新这里）", "Scan with WeChat · the updater refreshes this list", "微信掃一掃 · 公會招募板（更新器開著會定期刷新這裡）"),
                W.GuildBoardUrl(game))
        end
        d.more:SetText(L("发布我的公会招募", "List my guild", "發布我的公會招募"))
        d.more:SetScript("OnClick", function()
            showQR(opts, L("微信扫一扫 · 公会招募板", "Scan · guild board", "微信掃一掃 · 公會招募板"),
                L("会长在小程序「社区 · 招募」发布招募卡", "Guild masters list their guild in the mini program", "會長在小程式「社區 · 招募」發布招募卡"), W.GuildBoardUrl(game))
        end)
        d.more:Show()
    end

    -- 抽屉位置：顶边对齐主面板顶、高度 = 主面板高；页签右边放不下（主面板贴屏幕右边）→ 翻到页签左边盖在主面板上
    local function placeDrawer(d, host, tab)
        local hh = host.GetHeight and host:GetHeight()
        -- 至少 DR_H（精选位 + 引导卡 + 三四张卡片），主面板更高就跟主面板齐；不超过屏幕高
        local sh = UIParent and UIParent.GetHeight and UIParent:GetHeight()
        d._h = math.min(math.max(DR_H, (type(hh) == "number" and hh) or 0), 720, (type(sh) == "number" and sh > 200) and (sh - 20) or 720)
        d:SetHeight(d._h)
        local ht, tt = host.GetTop and host:GetTop(), tab.GetTop and tab:GetTop()
        local dy = (type(ht) == "number" and type(tt) == "number") and (ht - tt) or 0
        local tr, sr = tab.GetRight and tab:GetRight(), W.ScreenRight(tab)
        d:ClearAllPoints()
        if type(tr) == "number" and sr and tr + 4 + DR_W > sr then
            d:SetPoint("TOPRIGHT", tab, "TOPLEFT", -4, dy)
        else
            d:SetPoint("TOPLEFT", tab, "TOPRIGHT", 4, dy)
        end
    end

    -- 主插件调用：W.AttachGuildTab(主面板, opts) → 右侧「公会」页签
    --   装了 GuildInsight（已加载）：点页签打开它的招募页；否则：右侧抽屉（只读列表 + 安装引导 + 二维码）
    function W.AttachGuildTab(host, opts)
        if not host then return nil end
        if rawget(host, "_giGuildTab") then return rawget(host, "_giGuildTab") end
        opts = opts or {}
        local tab = W.SideTab(host, W.L("公会", "Guild", "公會"), opts.logo or W.LOGO_FALLBACK, opts.top)
        host._giGuildTab = tab
        tab:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(W.L("公会招募", "Guild recruitment", "公會招募"), 1, 0.82, 0)
            if opts.game == "titan" then
                GameTooltip:AddLine(W.L("即将开放 · 会长可预登记", "Coming soon - pre-register now", "即將開放 · 會長可預登記"), 1, 1, 1, true)
            elseif W.GuildAddonState() == "loaded" then
                GameTooltip:AddLine(W.L("打开 GuildInsight 招募页", "Open GuildInsight recruitment", "打開 GuildInsight 招募頁"), 1, 1, 1, true)
            else
                GameTooltip:AddLine(W.L("正在招人的公会 · 安装公会插件", "Recruiting guilds - get GuildInsight", "正在招人的公會 · 安裝公會插件"), 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        tab:SetScript("OnClick", function()
            if opts.game ~= "titan" and W.GuildAddonState() == "loaded" then
                local gi = _G.GuildInsight
                if gi.UI.OpenRecruit then gi.UI.OpenRecruit()
                elseif gi.UI.Toggle then
                    if not (gi.UI.IsShown and gi.UI.IsShown()) then gi.UI.Toggle() end
                end
                if rawget(tab, "_drawer") then tab._drawer:Hide() end
                W.SelectTab(tab, false)
                return
            end
            tab._drawer = rawget(tab, "_drawer") or buildDrawer(host, opts, tab)
            if tab._drawer:IsShown() then
                tab._drawer:Hide(); W.SelectTab(tab, false)
            else
                placeDrawer(tab._drawer, host, tab)
                fillDrawer(tab._drawer, opts)
                tab._drawer:Show(); W.SelectTab(tab, true)
            end
        end)
        if host.HookScript then
            host:HookScript("OnHide", function() if rawget(tab, "_drawer") then tab._drawer:Hide() end; W.SelectTab(tab, false) end)
            host:HookScript("OnShow", function() W.KeepSideTabsOnScreen(host) end)
        end
        if host.IsShown and host:IsShown() then W.KeepSideTabsOnScreen(host) end
        return tab
    end


    _G.GIWidgets = W
end
if ns then ns.W = W end
