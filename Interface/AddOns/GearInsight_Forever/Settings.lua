-- 设置描述表 + 渲染器（11-12 界面重构第 2 期「菜单合并 + 设置就近」）
--   用户「目的是用户可以更快找到自己要用的功能和配置，功能和配置关联到一起」：
--   原来 80 来个开关手写在设置页一张长页上（PageData.lua），和它们控制的功能分开。现在每个功能登记一份描述（ns.RegisterSettings），
--   同一份描述渲染到三处：功能页右上角「本页设置」、公会 / 组队抽屉的齿轮、设置页「全部设置」索引（带搜索，点「前往」跳到功能页）。
--   ⛔ 存档键一个都不许变：get / set 都是从原 PageData.lua 原样搬过来的（读写逻辑不变），这里只换了「画在哪」。
--   ⛔ 描述放内核、不随子插件：索引和搜索不需要加载任何子插件；要模块配合的项（组队）模块没加载时这一组写明「点了才加载」。
--   item.type：check（勾选，radio = 单选组）· label（单选组 / 输入的标签）· button · edit（自动私信）· note（灰色小字）· head（组内小标题）· custom
--   inline = 和上一项同一行；x = 行内绝对横坐标；step = 画完往右挪多少（数字或函数）
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local GROUPS, BYKEY, ITEMS = {}, {}, {}
ns._SettingsGroups = GROUPS   -- 测试 / 清单脚本用
ns._SettingsItems = ITEMS

local function txt(v)
    if type(v) == "function" then
        local ok, s = pcall(v)
        return ok and tostring(s or "") or ""
    end
    return tostring(v or "")
end
ns.SettingText = txt

function ns.RegisterSettings(g)
    if not (g and g.key) or BYKEY[g.key] then return end
    BYKEY[g.key] = g
    for i, it in ipairs(g.items or {}) do
        it.group = g
        it.id = it.id or (g.key .. "." .. i)
        ITEMS[it.id] = it
    end
    GROUPS[#GROUPS + 1] = g
    table.sort(GROUPS, function(a, b) return (a.order or 99) < (b.order or 99) end)
end
function ns.SettingsGroup(key) return BYKEY[key] end

local function avail(t)
    if not t.avail then return true end
    local ok, v = pcall(t.avail)
    return ok and v and true or false
end

-- 全部设置项（扁平），给搜索 / 清单脚本 / 测试用：{ id, group, type, text, where }
function ns.SettingsList(all)
    local out = {}
    for _, g in ipairs(GROUPS) do
        if all or avail(g) then
            for _, it in ipairs(g.items) do
                if (all or avail(it)) and it.type ~= "note" then
                    out[#out + 1] = { id = it.id, group = g.key, type = it.type, text = txt(it.text), where = g.page or g.data or g.drawer, jumpOnly = g.jumpOnly and true or false, tag = it.tag }
                end
            end
        end
    end
    return out
end

-- 搜索：只把 ASCII 大写转小写（⛔ 中文字节别过 lower()，见 Core.lua 斜杠命令的注释）
local function norm(s) return (tostring(s or ""):gsub("[A-Z]", function(c) return c:lower() end)) end
local function hit(s, q) return q == "" or norm(s):find(q, 1, true) ~= nil end
function ns.SettingsSearch(q)
    q = norm(q)
    local out = {}
    for _, r in ipairs(ns.SettingsList()) do
        local g = BYKEY[r.group]
        if r.type ~= "head" and (hit(r.text, q) or hit(txt(g.title), q)) then out[#out + 1] = r end
    end
    return out
end

-- ---------- 渲染 ----------
-- 所有画出来的勾选框都记一份（弱表）：任何一处点了，别处同一个开关跟着刷新（功能页 / 索引 / 抽屉齿轮显示永远一致）
local LIVE = setmetatable({}, { __mode = "k" })
local DYN = setmetatable({}, { __mode = "k" })   -- 文字会变的按钮（「移动提醒条」↔「锁定位置」）
local HOOKS = {}
function ns.OnSettingsRefresh(fn) HOOKS[#HOOKS + 1] = fn end
function ns.RefreshSettings()
    for c in pairs(LIVE) do
        local ok, v = pcall(c.get)
        c:SetChecked(ok and v and true or false)
        local it = rawget(c, "item")
        if it and it.label then c.text:SetText(txt(it.label)) end
    end
    for b, fn in pairs(DYN) do b:SetText(txt(fn)) end
    for _, fn in ipairs(HOOKS) do pcall(fn) end
end

local H = { check = 28, label = 28, button = 30, edit = 26, note = 22, head = 22 }

local function estW(fs, minW)
    local w = fs and fs.GetStringWidth and tonumber(fs:GetStringWidth()) or 60
    return math.max(minW or 60, w or 60)
end

local function makeCheck(row, it, x)
    local c = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    c:SetSize(24, 24); c:SetPoint("TOPLEFT", x, 0)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(txt(it.label or it.text))
    c.text, c.get, c.item = fs, it.get, it
    if it.radio then c.radio = true end
    c:SetScript("OnClick", function(self)
        it.set(self:GetChecked() and true or false)
        ns.RefreshSettings()   -- 单选组：点一个，同组其他的跟着刷；别处画的同一个开关也跟着刷
    end)
    if it.tip then
        c:SetScript("OnEnter", function(self) it.tip(self) end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    LIVE[c] = true
    local ok, v = pcall(it.get)
    c:SetChecked(ok and v and true or false)
    return c, 30 + estW(fs, it.minW or 60) + (it.gap or 18)
end

-- 画一项，返回 控件、往右挪多少
local function drawItem(row, it, x, ctx)
    local t = it.type
    if t == "check" then
        local c, w = makeCheck(row, it, x)
        if ctx.onCheck then ctx.onCheck(c, it) end
        return c, w
    elseif t == "label" then
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", x + 4, -5); fs:SetText(txt(it.text))
        return fs, (it.w or (estW(fs, 40) + 10))
    elseif t == "head" then
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x + 2, -2); fs:SetText(txt(it.text))
        return fs, estW(fs, 40) + 10
    elseif t == "note" then
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", x + 6, it.inline and -7 or -2); fs:SetText(txt(it.text))
        if not it.inline then fs:SetPoint("RIGHT", row, "RIGHT", -12, 0); fs:SetJustifyH("LEFT") end
        return fs, estW(fs, 40) + 10
    elseif t == "button" then
        local w = it.w or 120
        local b = ns.Button(row, txt(it.text), w, 22, function(self)
            local ok, err = pcall(it.click, self)
            if not ok and ns.Print then ns.Print(tostring(err)) end
            ns.RefreshSettings()
        end)
        b:SetPoint("TOPLEFT", x + 4, 0)
        if it.dyn then DYN[b] = it.text end
        if it.tip then
            b:SetScript("OnEnter", function(self) it.tip(self) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b, w + 8
    elseif t == "edit" then
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", x + 4, -5); fs:SetText(txt(it.text))
        local e = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        e:SetSize(it.w or 360, 20); e:SetPoint("TOPLEFT", x + (ns.zh and 126 or 156), -2)
        e:SetAutoFocus(false); e:SetMaxLetters(200)
        local function save(self)
            local v = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            it.set(v ~= "" and v or nil)
        end
        e:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(self) self:SetText(it.get() or ""); self:ClearFocus() end)
        e:SetScript("OnEditFocusLost", save)
        e:SetScript("OnShow", function(self) self:SetText(it.get() or "") end)
        e:SetText(it.get() or "")
        e.item = it
        if ctx.onEdit then ctx.onEdit(e, it) end
        return e, 0
    elseif t == "custom" and it.build then
        local ok, ctrl, w = pcall(it.build, row, x, ctx)
        if ok then return ctrl, w or 0 end
        if ns.Print then ns.Print(tostring(ctrl)) end
    end
    return nil, 0
end

local function rowsOf(g)
    local rows, cur = {}, nil
    for _, it in ipairs(g.items) do
        if avail(it) then
            if not cur or not it.inline then cur = { items = {}, h = 0 }; rows[#rows + 1] = cur end
            cur.items[#cur.items + 1] = it
            cur.h = math.max(cur.h, it.h or H[it.type] or 28)
        end
    end
    return rows
end

-- 一块设置区：parent 里按 groups 画（keys = 组 key 列表或返回列表的函数）
--   opts.width · opts.heading（画组标题，默认 true）· opts.jump（组标题右边「前往 ›」）· opts.index（索引模式：jumpOnly 组只列文字）
--   opts.onCheck(c, item) / opts.onEdit(e, item)：调用方收集控件（设置页的 p.checks / p.modChecks）
local Block = {}
Block.__index = Block

local function groupKeys(b)
    local keys = b.keys
    if type(keys) == "function" then keys = keys() end
    local out = {}
    for _, k in ipairs(keys or {}) do if BYKEY[k] then out[#out + 1] = BYKEY[k] end end
    return out
end

function Block:Sig()
    local t = {}
    for _, g in ipairs(groupKeys(self)) do
        t[#t + 1] = avail(g) and "1" or "0"
        for _, it in ipairs(g.items) do t[#t + 1] = avail(it) and "1" or "0" end
    end
    return table.concat(t)
end

function Block:Render()
    if self.frame then self.frame:Hide() end
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetPoint("TOPLEFT", 0, self.top or 0); f:SetWidth(self.opts.width or 640); f:SetHeight(10)
    self.frame, self.sig, self.entries, self.pos, self.gpos = f, self:Sig(), {}, {}, {}
    if self.opts.onRender then self.opts.onRender(self) end
    local ctx = { onCheck = self.opts.onCheck, onEdit = self.opts.onEdit, block = self }
    local W = self.opts.width or 640
    for _, g in ipairs(groupKeys(self)) do
        local ok = avail(g)
        local missing = (not ok) and g.missing and txt(g.missing) or nil
        if ok or (missing and missing ~= "") then
            local hd
            if self.opts.heading ~= false then
                hd = CreateFrame("Frame", nil, f); hd:SetSize(W, 24)
                local fs = hd:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetPoint("TOPLEFT", 12, -2); fs:SetText(txt(g.title))
                local ln = hd:CreateTexture(nil, "ARTWORK"); ln:SetColorTexture(1, 0.82, 0, 0.18)
                ln:SetPoint("LEFT", fs, "RIGHT", 8, 0); ln:SetPoint("RIGHT", hd, "RIGHT", -12, 0); ln:SetHeight(1)
                hd.title = fs
                if self.opts.jump and (g.page or g.drawer) then
                    local jb = ns.Button(hd, L("前往 ›", "Go ›"), 64, 18, function()
                        ns.JumpToSetting(rawget(hd, "jumpTo") or g.key)
                    end)
                    jb:SetPoint("RIGHT", hd, "RIGHT", -14, 0)
                    ln:SetPoint("RIGHT", jb, "LEFT", -6, 0)
                    jb:SetScript("OnEnter", function(self2)
                        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(ns.SettingWhere(g), 1, 0.82, 0)
                        GameTooltip:Show()
                    end)
                    jb:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    hd.jump = jb
                end
            end
            local ent = { group = g, head = hd, rows = {} }
            self.entries[#self.entries + 1] = ent
            if not ok then
                local r = CreateFrame("Frame", nil, f); r:SetSize(W, 22)
                local fs = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                fs:SetPoint("TOPLEFT", 16, -2); fs:SetPoint("RIGHT", r, "RIGHT", -12, 0); fs:SetJustifyH("LEFT"); fs:SetText(missing)
                ent.rows[1] = { frame = r, h = 22, items = {}, missing = true }
            elseif self.opts.index and g.jumpOnly then
                -- 决定 4：法师吃喝的开关只在组队抽屉的子页签里；索引只列名字，点「前往」过去（手法 / 位面同理：开关本来就画在那一页上）
                for _, it in ipairs(g.items) do
                    if avail(it) and it.type ~= "note" then
                        local r = CreateFrame("Frame", nil, f); r:SetSize(W, 20)
                        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        fs:SetPoint("TOPLEFT", it.type == "head" and 18 or 30, -3); fs:SetPoint("RIGHT", r, "RIGHT", -12, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
                        fs:SetText((it.type == "head" and "" or "· ") .. txt(it.text))
                        ent.rows[#ent.rows + 1] = { frame = r, h = 20, items = { it } }
                    end
                end
            else
                for _, rw in ipairs(rowsOf(g)) do
                    local r = CreateFrame("Frame", nil, f); r:SetSize(W, rw.h)
                    local hl = r:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.16); hl:Hide()
                    r.flash = hl
                    local x = 14
                    for i, it in ipairs(rw.items) do
                        if it.x then x = it.x elseif i == 1 and it.indent then x = 14 + it.indent end
                        local ctrl, w = drawItem(r, it, x, ctx)
                        it._ctrl = ctrl
                        local st = it.step
                        if type(st) == "function" then st = st() end
                        x = x + (st or w or 0)
                    end
                    ent.rows[#ent.rows + 1] = { frame = r, h = rw.h, items = rw.items }
                end
            end
        end
    end
    self:Layout()
    return self
end

-- 按过滤条件摆位置（不重建控件：⛔ WoW 的框体建了就删不掉，搜索每敲一个字都重建会一直涨内存）
function Block:Layout()
    local q = norm(self.filter or "")
    local tag = self.tag
    local y = -(self.opts.pad or 4)
    local W = self.opts.width or 640
    for _, ent in ipairs(self.entries or {}) do
        local g = ent.group
        local gHit = (q ~= "" and (hit(txt(g.title), q) or hit(txt(g.short), q))) and not tag
        local shown = {}
        for _, r in ipairs(ent.rows) do
            local ok = true
            if tag then
                ok = false
                for _, it in ipairs(r.items) do if it.tag == tag then ok = true end end
            elseif q ~= "" and not gHit then
                ok = false
                for _, it in ipairs(r.items) do
                    if hit(txt(it.text), q) or (it.label and hit(txt(it.label), q)) or (it.keys and hit(it.keys, q)) then ok = true end
                end
            end
            if ok then shown[#shown + 1] = r else r.frame:Hide() end
        end
        if #shown == 0 then
            if ent.head then ent.head:Hide() end
            ent.y = nil
        else
            if ent.head then
                y = y - 2
                ent.head:ClearAllPoints(); ent.head:SetPoint("TOPLEFT", 0, y); ent.head:Show()
                ent.head.jumpTo = nil
                ent.y = y
                self.gpos[g.key] = y
                y = y - 24
            end
            for _, r in ipairs(shown) do
                r.frame:ClearAllPoints(); r.frame:SetPoint("TOPLEFT", 0, y); r.frame:SetWidth(W); r.frame:Show()
                for _, it in ipairs(r.items) do
                    self.pos[it.id] = y
                    -- 搜索命中：「前往」直接跳到第一条命中的那项（同一行好几项时挑真正命中的那项）
                    if ent.head and q ~= "" and not rawget(ent.head, "jumpTo") and it.type ~= "label" and it.type ~= "note"
                        and (gHit or hit(txt(it.text), q) or (it.label and hit(txt(it.label), q))) then ent.head.jumpTo = it.id end
                end
                y = y - r.h
            end
            y = y - 6
        end
    end
    self.height = -y + 4
    if self.frame then self.frame:SetHeight(self.height) end
    if self.opts.onLayout then self.opts.onLayout(self) end
end

function Block:SetFilter(q, tag)
    self.filter, self.tag = q, tag
    self:Layout()
end

function Block:Refresh()
    if not self.frame or self.sig ~= self:Sig() then self:Render() end
    ns.RefreshSettings()
end

-- 闪一下目标那行（跳转过来时让人一眼看到是哪项）
function Block:Flash(id)
    for _, ent in ipairs(self.entries or {}) do
        for _, r in ipairs(ent.rows) do
            for _, it in ipairs(r.items) do
                if it.id == id and r.frame.flash then
                    r.frame.flash:Show()
                    if C_Timer and C_Timer.After then C_Timer.After(1.6, function() r.frame.flash:Hide() end) end
                    self.flashed = id
                    return true
                end
            end
        end
    end
end

function ns.SettingsBlock(parent, keys, opts)
    local b = setmetatable({ parent = parent, keys = keys, opts = opts or {}, top = (opts or {}).top }, Block)
    b:Render()
    return b
end

-- ---------- 在哪 / 跳转 ----------
local PAGE_NAME = {
    plan = function() return L("升级 → 升级规划", "Leveling → Plan") end,
    prof = function() return L("升级 → 专业", "Leveling → Professions") end,
    xp = function() return L("升级 → 经验加成", "Leveling → XP bonuses") end,
    gear = function() return L("装备 → 推荐装备", "Gear → Gear picks") end,
    talent = function() return L("职业 → 天赋", "Class → Talents") end,
    rot = function() return L("职业 → 手法", "Class → Rotation") end,
    keys = function() return L("职业 → 键位", "Class → Keys") end,
    ammo = function() return L("职业 → 弹药商", "Class → Ammo") end,
    layer = function() return L("右侧「位面」页签", "Layers tab (right side)") end,
}
local DRAWER_NAME = {
    guild = function() return L("右侧「公会」页签 → 公会设置", "Guild tab → Guild settings") end,
    group = function() return L("右侧「组队」页签 → 组队设置", "Group tab → Group settings") end,
    mage = function() return L("右侧「组队」页签 → 法师吃喝", "Group tab → Mage food") end,
}
local SUB_NAME = {
    general = function() return L("设置 → 通用", "Settings → General") end,
    perf = function() return L("设置 → 性能", "Settings → Performance") end,
}
function ns.SettingWhere(g)
    if type(g) == "string" then g = BYKEY[g] or (ITEMS[g] and ITEMS[g].group) end
    if not g then return "" end
    local f = (g.page and PAGE_NAME[g.page]) or (g.drawer and DRAWER_NAME[g.drawer]) or (g.data and SUB_NAME[g.data])
    return f and f() or ""
end

local function pageObj(key)
    for _, p in ipairs(ns._Pages or {}) do if p.key == key then return p end end
end

-- 功能页的「本页设置」：页头右上角一个按钮，点开是盖在页面上的一层（可滚动），收起回到功能本身
local PANEL_W = 646
function ns.PageSettingsGroups(key)
    local out = {}
    for _, g in ipairs(GROUPS) do if g.page == key and not g.jumpOnly then out[#out + 1] = g.key end end
    return out
end

-- 盖在页面上的那层第一次点开才建（不点不占内存）
local function ensurePanel(p)
    local f = p.frame
    local panel = rawget(f, "_setPanel")
    if panel then return panel end
    local keys = ns.PageSettingsGroups(p.key)
    panel = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetPoint("TOPLEFT", 0, -38); panel:SetPoint("BOTTOMRIGHT", 0, 0)
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        panel:SetBackdropColor(0.04, 0.05, 0.07, 0.98); panel:SetBackdropBorderColor(1, 0.82, 0, 0.5)
    end
    if panel.SetFrameLevel and f.GetFrameLevel then panel:SetFrameLevel((f:GetFrameLevel() or 1) + 40) end
    panel:EnableMouse(true)
    local hd = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hd:SetPoint("TOPLEFT", 12, -8)
    hd:SetText(L("本页设置：只影响这一页的功能，改了立刻生效（设置 → 全部设置 里也能搜到）", "Settings for this page - changes apply right away (also searchable under Settings → All settings)"))
    local sf, body = ns.Scroll(panel, 4, -26, PANEL_W - 30, 474 - 38 - 32)
    panel.scroll, panel.body = sf, body
    panel.block = ns.SettingsBlock(body, keys, { width = PANEL_W - 34, onLayout = function(bk) body:SetHeight(bk.height or 10) end })
    panel:Hide()
    f._setPanel = panel
    return panel
end

function ns.AttachPageSettings(p)
    if not (p and p.frame) or rawget(p.frame, "_setBtn") then return end
    local keys = ns.PageSettingsGroups(p.key)
    if #keys == 0 then return end
    local f = p.frame
    local btn = ns.Button(f, L("本页设置", "Page settings"), 92, 20)
    btn:SetPoint("TOPRIGHT", -8, -7)
    if rawget(f, "_sub") then f._sub:SetPoint("RIGHT", btn, "LEFT", -8, 0) end
    btn:SetScript("OnClick", function() ns.TogglePageSettings(p.key) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("本页设置", "Page settings"), 1, 0.82, 0)
        for _, k in ipairs(keys) do GameTooltip:AddLine("· " .. txt(BYKEY[k].title), 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f._setBtn = btn
    return btn
end

local function setBtnText(f)
    local b = rawget(f, "_setBtn")
    local pn = rawget(f, "_setPanel")
    if b then b:SetText((pn and pn:IsShown()) and L("收起设置", "Close settings") or L("本页设置", "Page settings")) end
end
function ns.TogglePageSettings(key, show)
    local p = pageObj(key)
    if not (p and p.frame) then return false end
    ns.AttachPageSettings(p)
    if not rawget(p.frame, "_setBtn") then return false end
    local panel = ensurePanel(p)
    if show == nil then show = not panel:IsShown() end
    if show then panel.block:Refresh(); panel:Show() else panel:Hide() end
    setBtnText(p.frame)
    return show, panel
end

local function scrollTo(sf, y)
    if not (sf and sf.SetVerticalScroll) then return end
    local v = math.max(0, -(tonumber(y) or 0) - 4)
    local ok, range = pcall(sf.GetVerticalScrollRange, sf)
    if ok and type(range) == "number" and range > 0 and v > range then v = range end
    pcall(sf.SetVerticalScroll, sf, v)
    return v
end
ns._SettingsScrollSF = scrollTo

function ns.OpenPageSettings(key, id)
    if ns.OpenPage then ns.OpenPage(key) end
    local cur = ns.db and ns.db.ui and ns.db.ui.page
    if cur ~= key then return false end   -- 这一页对当前角色不可见（比如弹药页只给猎人）
    local shown, panel = ns.TogglePageSettings(key, true)
    if not shown then return false end
    if id and panel.block.pos[id] then scrollTo(panel.scroll, panel.block.pos[id]); panel.block:Flash(id) end
    return true
end

-- 公会 / 组队抽屉的齿轮：一个浮在抽屉上的设置小面板
local pop
local function buildPop()
    local f = CreateFrame("Frame", "GearInsightForeverSettingsPop", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(500, 440)
    f:SetFrameStrata("DIALOG"); if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.04, 0.05, 0.07, 0.98); f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    end
    f:EnableMouse(true); f:SetMovable(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 12, -10)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.scroll, f.body = ns.Scroll(f, 4, -36, 470, 440 - 44)
    f.blocks = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverSettingsPop") end
    f:Hide()
    return f
end
local POP_TITLE = {
    guild = function() return L("公会设置", "Guild settings") end,
    group = function() return L("组队设置", "Group settings") end,
}
function ns.OpenSettingsPopup(which, anchor, id)
    pop = pop or buildPop()
    for _, b in pairs(pop.blocks) do b.frame:Hide() end
    local b = pop.blocks[which]
    if not b then
        local keys = {}
        for _, g in ipairs(GROUPS) do if g.drawer == which and not g.jumpOnly then keys[#keys + 1] = g.key end end
        b = ns.SettingsBlock(pop.body, keys, { width = 460, heading = true, onLayout = function(bb) pop.body:SetHeight(bb.height or 10) end })
        pop.blocks[which] = b
    end
    b:Refresh(); b.frame:Show()
    pop.body:SetHeight(b.height or 10)
    pop.title:SetText((POP_TITLE[which] or POP_TITLE.guild)())
    pop.which = which
    pop:ClearAllPoints()
    if anchor and anchor.GetCenter then pop:SetPoint("TOP", anchor, "TOP", 0, -36) else pop:SetPoint("CENTER", UIParent, "CENTER", 0, 60) end
    pop:Show()
    scrollTo(pop.scroll, (id and b.pos[id]) or 0)
    if id then b:Flash(id) end
    return pop, b
end
ns._SettingsPop = function() return pop end   -- 测试用

-- 抽屉标题栏上的「公会设置 / 组队设置」按钮（子插件建抽屉时调）
--   small = 只出齿轮图标（组队抽屉标题栏挤：子页签按钮 + 外观 + 钉住）
function ns.SettingsGearButton(parent, which, small)
    local b
    if small then
        b = CreateFrame("Button", nil, parent)
        b:SetSize(22, 22)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetAllPoints(); ic:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
        b:SetScript("OnClick", function() ns.OpenSettingsPopup(which, parent) end)
    else
        b = ns.Button(parent, (POP_TITLE[which] or POP_TITLE.guild)(), 76, 22, function() ns.OpenSettingsPopup(which, parent) end)
    end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((POP_TITLE[which] or POP_TITLE.guild)(), 1, 0.82, 0)
        for _, g in ipairs(GROUPS) do if g.drawer == which and not g.jumpOnly then
            for _, it in ipairs(g.items) do if it.type == "head" then GameTooltip:AddLine("· " .. txt(it.text), 1, 1, 1, true) end end
        end end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- 打开公会抽屉（按需加载公会子插件）；子插件不在就只开主面板
local function openGuildDrawer()
    local host = _G.GearInsightForeverMain
    if not (host and host:IsShown()) and ns.ToggleMain then ns.ToggleMain() end
    if not (ns.ModuleAvailable and ns.ModuleAvailable("guild")) then return _G.GearInsightForeverMain end
    if not (ns.OpenModule and ns.OpenModule("guild")) then return _G.GearInsightForeverMain end
    local gh = ns.GuildHome
    if gh and gh.drawer and gh.drawer:IsShown() then return gh.drawer end
    host = _G.GearInsightForeverMain
    local tab = host and rawget(host, "_giGuildTab")
    local d = tab and rawget(tab, "_drawer")
    if d and d:IsShown() then return d end
    if tab and ns.ClickSideTab then pcall(ns.ClickSideTab, tab) end
    if gh and gh.drawer and gh.drawer:IsShown() then return gh.drawer end
    d = tab and rawget(tab, "_drawer")
    return (d and d:IsShown() and d) or host
end

function ns.OpenMageSettings()
    -- 11-13 第 5 期：法师吃喝在单独的按需加载子插件里（组队信标加载后再加载它）
    if ns.LoadModule and ns.LoadModule("group") and not ns.MageWater and ns.GroupLoadMage then ns.GroupLoadMage(true) end
    if ns.LoadModule and ns.LoadModule("group") and ns.MageWater and ns.MageWater.OpenSettings then
        return ns.MageWater.OpenSettings()
    end
end

function ns.JumpToSetting(target)
    local it = ITEMS[target]
    local g = (it and it.group) or BYKEY[target]
    if not g then return false end
    local id = it and it.id or nil
    ns._lastJump = { group = g.key, item = id }
    if g.page and g.jumpOnly then   -- 手法 / 位面：开关本来就画在页面上，打开那一页就行
        if ns.OpenPage then ns.OpenPage(g.page) end
        return (ns.db and ns.db.ui and ns.db.ui.page) == g.page
    end
    if g.page then return ns.OpenPageSettings(g.page, id) end
    if g.data and ns.OpenSettingsSub then return ns.OpenSettingsSub(g.data, id) end
    if g.drawer == "mage" then return ns.OpenMageSettings() and true or false end
    if g.drawer == "guild" then
        local a = openGuildDrawer()
        ns.OpenSettingsPopup("guild", a, id)
        return true
    end
    if g.drawer == "group" then
        if ns.LoadModule and ns.ModuleAvailable and ns.ModuleAvailable("group") then ns.LoadModule("group") end
        if ns.OpenGroupDrawer then pcall(ns.OpenGroupDrawer) end
        local QM = ns.QM
        ns.OpenSettingsPopup("group", (QM and QM.drawer and QM.drawer:IsShown() and QM.drawer) or _G.GearInsightForeverMain, id)
        return true
    end
    return false
end

-- /gi set 关键词（/gi 设置 关键词）：打开「全部设置」并搜索
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.set = function(rest, rawRest)
    local q = rawRest or rest or ""
    if ns.OpenSettingsSearch then ns.OpenSettingsSearch(q) end
end
ns.ExtraSlash["设置"] = ns.ExtraSlash.set

-- ================= 描述表（get / set 原样搬自 PageData.lua，存档键不变）=================
local function mod(key) return ns.ModuleAvailable and ns.ModuleAvailable(key) or false end

-- ---------- 设置 → 通用 ----------
local langItems = {}
for i, lg in ipairs(ns.LANGS or {}) do
    local code = lg[1]
    langItems[#langItems + 1] = { type = "check", radio = true, inline = i > 1, id = "lang." .. tostring(code or "auto"),
        -- 繁体对照表（ZhTW.lua）用不上（11-13 第 4 期起在按需加载的 GearInsight_Forever_LocaleTW，简体客户端没加载但文件夹在也算能用）：不给这个选项
        avail = function() return not (code == "tw" and not (ns.TW_CHAR or (ns.TWAvailable and ns.TWAvailable()))) end,
        text = function() return code and lg[2] or ns.L(lg[2], lg[3]) end,
        step = function() return code == "en" and 96 or code and 112 or 150 end,
        get = function() return ns.Lang() == code end, set = function() ns.SetLang(code) end }
end
langItems[#langItems + 1] = { type = "button", inline = true, id = "lang.reload", w = 110, text = function() return L("重载界面生效", "Reload to apply") end, click = function() ReloadUI() end }
ns.RegisterSettings({ key = "lang", order = 10, data = "general",
    title = "语言 / Language", short = function() return L("语言", "Language") end,
    items = langItems })

local scaleItems = {
    { type = "label", id = "ui.scaleLabel", text = function() return L("窗口大小：", "Window size:") end, w = 72,
      avail = function() return ns.SetUIScale ~= nil end },
}
for _, sc in ipairs(ns.SCALES or { 0.9, 1, 1.1, 1.2, 1.3, 1.4 }) do
    scaleItems[#scaleItems + 1] = { type = "check", radio = true, inline = true, id = "ui.scale" .. math.floor(sc * 100 + 0.5), step = 70,
        avail = function() return ns.SetUIScale ~= nil end,
        text = function() return math.floor(sc * 100 + 0.5) .. "%" end,
        get = function() return math.abs(ns.UIScale() - sc) < 0.001 end, set = function() ns.SetUIScale(sc) end }
end
scaleItems[#scaleItems + 1] = { type = "note", indent = 28, avail = function() return ns.SetUIScale ~= nil end,
    text = function() return L("也可以在主窗口上按住 Ctrl 滚滚轮微调，或输入 /gi scale 125", "Or hold Ctrl and scroll over the window, or type /gi scale 125") end }
scaleItems[#scaleItems + 1] = { type = "check", id = "ui.minimap", text = function() return L("显示小地图按钮", "Show minimap button") end,
    get = function() return not (ns.db.minimap and ns.db.minimap.hide) end, set = function(v) ns.SetMinimapShown(v) end }
ns.RegisterSettings({ key = "ui", order = 20, data = "general",
    title = function() return L("界面", "Interface") end, short = function() return L("界面", "Interface") end,
    items = scaleItems })

-- ---------- 设置 → 性能 ----------
local function perfTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("卡顿自查", "Lag check"), 1, 0.82, 0)
    GameTooltip:AddLine(L("站着别动约 2 分钟：自动切换几种姓名板设置各测一遍，测完全部还原，然后告诉你卡在哪（GearInsight 自己占多少、友方姓名板有没有影响、哪个插件最占时间）。进战斗会自动停。",
        "Stand still for ~2 minutes: tries a few nameplate settings, restores them all, then tells you what is slow (GearInsight itself, friendly nameplates, the heaviest addons). Stops if you enter combat."), 1, 1, 1, true)
    local last = ns.db.perfPlates and ns.db.perfPlates[#ns.db.perfPlates]
    if last and last.verdict then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("上次自查（", "Last check (") .. (last.at or "") .. L("）：", "):"), 1, 0.82, 0)
        for _, v in ipairs(last.verdict) do GameTooltip:AddLine(ns.L(v[1], v[2]), 0.85, 0.85, 0.85, true) end
    end
    GameTooltip:Show()
end
local groupLoadItem = { type = "check", text = function() return L("登录时加载组队模块（不加载 = 附近的人看不到你的任务进度）", "Load the group module at login (otherwise nearby players can't see your quests)") end,
    avail = function() return ns.GroupAutoLoad ~= nil and mod("group") end,
    get = function() return ns.GroupAutoLoad() end,
    set = function(v) ns.db.ui = ns.db.ui or {}; ns.db.ui.groupLazy = (not v) or nil; if v and ns.PerfGuard then ns.PerfGuard.UserOpened() end end }
local function copyItem(src, id) local t = {}; for k, v in pairs(src) do t[k] = v end; t.id = id; return t end
ns.RegisterSettings({ key = "perf", order = 30, data = "perf",
    title = function() return L("性能（觉得卡先看这里）", "Performance (feels laggy? start here)") end, short = function() return L("性能", "Performance") end,
    items = {
        { type = "check", id = "perf.cityPlates", avail = function() return ns.CityPlates ~= nil end,
          text = function() return L("进主城自动隐藏友方玩家姓名板和头顶名字，出城恢复（城里人多会卡）", "Hide friendly player nameplates and names in capitals, restore outside (saves FPS)") end,
          get = function() return ns.CityPlates.Enabled() end, set = function(v) ns.CityPlates.SetOn(v) end },
        -- 11-13 GI-244 玩家「是否还有别的地方需要设置」：默认就开着，不用再设置；城里自己按 Shift+V / 界面里打开 = 这次不再替你关
        { type = "note", id = "perf.cityPlatesNote", indent = 28, avail = function() return ns.CityPlates ~= nil end,
          text = function() return L("默认开着，不用另外设置；在城里自己打开了，插件就不再替你关", "On by default, nothing else to set; if you turn them back on in town, the addon leaves them alone") end },
        -- 10-18 卡顿自查（Perf.lua）：玩家觉得卡 → 一键测，用大白话告诉他是谁卡的，别直接把插件删了
        { type = "button", id = "perf.check", w = 150, avail = function() return ns.Perf ~= nil and ns.Perf.Plates ~= nil end,
          text = function() return L("卡顿自查（约 2 分钟）", "Lag check (~2 min)") end, click = function() ns.Perf.Plates() end, tip = perfTip },
        { type = "custom", inline = true, id = "perf.last", avail = function() return ns.Perf ~= nil and ns.Perf.Plates ~= nil end,
          text = function() return L("上次：", "Last: ") end,
          build = function(row, x, ctx)
              local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
              fs:SetPoint("TOPLEFT", x + 6, -5); fs:SetPoint("RIGHT", row, "RIGHT", -12, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
              local hitF = CreateFrame("Frame", nil, row)
              hitF:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 4); hitF:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, -4)
              hitF:EnableMouse(true)
              hitF:SetScript("OnEnter", perfTip)
              hitF:SetScript("OnLeave", function() GameTooltip:Hide() end)
              if ctx and ctx.block then ctx.block.perfLast, ctx.block.perfLastHit = fs, hitF end   -- 设置页记一份（测试 / 刷新用）
              local function paint()
                  local last = ns.db.perfPlates and ns.db.perfPlates[#ns.db.perfPlates]
                  local first = last and last.verdict and last.verdict[2] or (last and last.verdict and last.verdict[1])
                  fs:SetText(first and ("|cff999999" .. L("上次：", "Last: ") .. "|r" .. ns.L(first[1], first[2]) .. "|cff777777" .. L("（悬停看全部）", " (hover for all)") .. "|r")
                      or ("|cff777777" .. L("觉得卡？点这里测一下是不是 GearInsight 的问题", "Feels laggy? Check whether GearInsight is the cause") .. "|r"))
              end
              local prev = ns.RefreshPerfVerdict
              ns.RefreshPerfVerdict = function() if prev then pcall(prev) end; paint() end
              paint()
              return fs, 0
          end },
        -- 10-22 自动卡顿检测（PerfGuard.lua）
        { type = "check", id = "perf.guard", avail = function() return ns.PerfGuard ~= nil end,
          text = function() return L("自动检测卡顿（如果是组队引起的，自动关掉组队）", "Auto lag detection (turns Group off if Group is the cause)") end,
          get = function() return ns.PerfGuard.On() end, set = function(v) ns.PerfGuard.Set(v) end,
          tip = function(self)
              GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
              GameTooltip:AddLine(L("自动检测卡顿", "Auto lag detection"), 1, 0.82, 0)
              GameTooltip:AddLine(L("一直量帧率：连续卡 30 秒，先把组队暂停 30 秒对照，明显变顺才关掉组队，没变顺就原样恢复。每次卡顿都记日志（/gi perf log 查看）。",
                  "Watches frame times: after 30s of lag, pauses Group for 30s; turns it off only if that clearly helps, otherwise resumes. Every lag event is logged (/gi perf log)."), 1, 1, 1, true)
              local line = ns.PerfGuard.LastLine()
              if line then GameTooltip:AddLine(" "); GameTooltip:AddLine(L("最近一次：", "Last: ") .. line, 0.85, 0.85, 0.85, true) end
              GameTooltip:Show()
          end },
        copyItem(groupLoadItem, "perf.groupLoad"),
    } })

-- ---------- 装备 → 推荐装备 ----------
local bisItems = {
    { type = "check", id = "bis.on", text = function() return L("显示角标（悬停看来源，点击指引获取）", "Show icons (hover for source, click for directions)") end,
      get = function() return ns.BisCorner.Enabled() end, set = function(v) ns.BisCorner.SetEnabled(v) end },
    { type = "label", id = "bis.posLabel", w = 50, avail = function() return ns.BisCorner.SetPos ~= nil end, text = function() return L("位置：", "Position:") end },
}
for i = 1, 4 do
    bisItems[#bisItems + 1] = { type = "check", radio = true, inline = true, id = "bis.pos" .. i, step = 92,
        avail = function() return ns.BisCorner.SetPos ~= nil and ns.BisCorner.POS and ns.BisCorner.POS[i] ~= nil end,
        text = function() return ns.BisCorner.PosName(ns.BisCorner.POS[i]) end,
        get = function() return ns.BisCorner.Pos() == ns.BisCorner.POS[i] end, set = function() ns.BisCorner.SetPos(ns.BisCorner.POS[i]) end }
end
bisItems[#bisItems + 1] = { type = "note", inline = true, avail = function() return ns.BisCorner.SetPos ~= nil end, text = function() return L("角标上 Alt + 点击也能换", "or Alt-click an icon") end }
ns.RegisterSettings({ key = "bis", order = 40, page = "gear", avail = function() return ns.BisCorner ~= nil end,
    title = function() return L("装备角标（角色面板装备格上的推荐装备小图标）", "BiS corner icons (character panel)") end, short = function() return L("装备角标", "BiS icons") end,
    items = bisItems })
ns.RegisterSettings({ key = "ilvl", order = 45, page = "gear", avail = function() return ns.ItemLevel ~= nil end,
    title = function() return L("装等", "Item level") end, short = function() return L("装等", "Item level") end,
    items = {
        { type = "check", id = "ilvl.on", text = function() return L("显示装等（鼠标提示 / 角色面板每格 + 平均装等 / 背包）", "Show item levels (tooltips, character panel + average, bags)") end,
          get = function() return ns.ItemLevel.Enabled() end, set = function(v) ns.ItemLevel.SetOn(v) end },
    } })

-- ---------- 升级 → 专业 ----------
ns.RegisterSettings({ key = "reagent", order = 50, page = "prof", avail = function() return ns.ReagentSrcTip ~= nil end,
    title = function() return L("材料来源提示", "Material sources") end, short = function() return L("材料来源", "Materials") end,
    items = {
        { type = "check", id = "reagent.on", text = function() return L("材料鼠标提示写从哪来（采集点 / 剥皮地区 / 掉落的怪 / 商人）", "Show where crafting materials come from in tooltips") end,
          get = function() return ns.ReagentSrcTip.Enabled() end, set = function(v) ns.ReagentSrcTip.SetOn(v) end },
    } })

-- ---------- 职业 → 天赋 ----------
ns.RegisterSettings({ key = "trainnow", order = 55, page = "talent", avail = function() return ns.TrainNow ~= nil or (ns.Trainers ~= nil and ns.Trainers.Go ~= nil) end,
    title = function() return L("技能与训练师", "Skills & trainers") end, short = function() return L("训练师", "Trainer") end,
    items = {
        { type = "check", id = "trainnow.remind", avail = function() return ns.TrainNow ~= nil end,
          text = function() return L("进有职业训练师的城镇时，提醒这一级能学的技能", "Remind me of trainable spells when I enter a town with my class trainer") end,
          get = function() return ns.TrainNow.RemindOn() end, set = function(v) ns.TrainNow.SetRemindOn(v) end },
        { type = "button", id = "trainnow.go", w = 160, avail = function() return ns.Trainers ~= nil and ns.Trainers.Go ~= nil end,
          text = function() return L("找最近的职业训练师", "Nearest class trainer") end, click = function() ns.Trainers.Go() end },
    } })

-- ---------- 职业 → 弹药商（猎人）----------
-- 11-13 重构第 4 期：弹药提醒 / 冷却管理器键位 / 手法钉板在按需加载的 _Class 里 —— 没加载时设置项照常出（按「包里有没有这个文件」），
--   读开关直接读存档（同一个键），改开关才加载 _Class 再调真函数（战斗中排到脱战后）
local function classHas(file, name) return ns[name] ~= nil or (ns.ModHas ~= nil and ns.ModHas("class", file)) end
local function classDo(name, fn)
    local t = ns[name]
    if t then return fn(t) end
    if ns.ModLoad and ns.ModLoad("class", function() if ns[name] then fn(ns[name]) end end) and ns[name] then return fn(ns[name]) end
end
local function ammoDB() return (ns.db and type(ns.db.ammoRemind) == "table") and ns.db.ammoRemind or {} end
local AMMO_DEF = { warn = 400, urgent = 150, full = 1000 }   -- ⛔ 和 AmmoRemind.lua 的 R.DEF 一致（没加载时说明文字用）
ns.RegisterSettings({ key = "ammo", order = 58, page = "ammo", avail = function() return classHas("AmmoRemind.lua", "AmmoRemind") and ns.MyClass ~= nil and ns.MyClass() == "Hunter" end,
    title = function() return L("箭 / 子弹提醒", "Ammo reminder") end, short = function() return L("弹药提醒", "Ammo") end,
    items = {
        { type = "check", id = "ammo.on", text = function() return L("箭 / 子弹快没了提醒（浮动图标 + 聊天框；商人那里一键补满）", "Ammo running-low reminder (icon + chat; one-click top-up at vendors)") end,
          get = function() return ns.db ~= nil and ammoDB().on ~= false end, set = function(v) classDo("AmmoRemind", function(AR) AR.SetOn(v) end) end },
        { type = "check", id = "ammo.sound", x = 520, inline = true, text = function() return L("提醒音效", "Sound") end,
          get = function() return ammoDB().sound == true end, set = function(v) ns.db.ammoRemind = ns.db.ammoRemind or {}; ns.db.ammoRemind.sound = v and true or nil end },
        { type = "note", indent = 26, text = function()
              local function get(k) return tonumber(ammoDB()[k]) or AMMO_DEF[k] end
              return string.format(L("少于 %d 发黄、少于 %d 发红，商人那里补到 %d 发；改：/gi ammo warn 400 · urgent 150 · full 1000", "Warn < %d, urgent < %d, top up to %d; change: /gi ammo warn 400 / urgent 150 / full 1000"),
                  get("warn"), get("urgent"), get("full"))
          end },
    } })

-- ---------- 升级 → 经验加成：帐篷蹭露营 ----------
local function CP() return ns.Camp end
ns.RegisterSettings({ key = "camp", order = 60, page = "xp", avail = function() return ns.Camp ~= nil and ns.Camp.Enabled ~= nil end,
    title = function() return L("帐篷蹭露营", "Tent sharing") end, short = function() return L("帐篷", "Tent") end,
    items = {
        { type = "check", id = "camp.on", text = function() return L("指到别人的帐篷时弹窗问要不要密他求组蹭露营", "Offer to whisper the owner when you mouse over someone's tent") end,
          get = function() return CP().Enabled() end, set = function(v) CP().SetOn(v) end },
        -- 11-10 用户「主动发私聊就行，申请加入功能放到设置，默认关闭」
        { type = "check", id = "camp.reqJoin", indent = 18, text = function() return L("求组时同时发系统入队申请（对方会弹「申请加入」框）", "Also send a system join request") end,
          get = function() return CP().DB().reqJoin == true end, set = function(v) CP().DB().reqJoin = v or nil end },
        { type = "label", id = "camp.reqLabel", h = 26, text = function() return L("别人申请加入我的队伍时：", "When others ask to join my group:") end },
        { type = "check", id = "camp.acceptSolo", indent = 18, text = function() return L("单人（没组队）时自动同意", "Auto-accept when solo") end,
          get = function() return CP().DB().reqAcceptSolo == true end, set = function(v) CP().DB().reqAcceptSolo = v or nil end },
        { type = "check", id = "camp.decline", indent = 18, text = function() return L("自动拒绝来蹭露营的（对方密语提到帐篷 / 露营，或用本插件申请的）", "Decline tent requests (they whispered about a tent, or asked via this addon)") end,
          get = function() return CP().DB().reqDecline == true end, set = function(v) CP().DB().reqDecline = v or nil end },
        -- 11-09 GI-212「蹭帐篷自己设置密聊内容」：存 camp.msg / camp.thankMsg（和 /gi camp msg、/gi camp thanks 同一份）
        { type = "edit", id = "camp.msg", tag = "whisper", avail = function() return CP().DB ~= nil end, text = function() return L("蹭帐篷求组：", "Tent ask:") end,
          get = function() return CP().DB().msg end, set = function(v) CP().DB().msg = v end },
        { type = "edit", id = "camp.thankMsg", tag = "whisper", avail = function() return CP().DB ~= nil end, text = function() return L("蹭完帐篷感谢：", "Tent thanks:") end,
          get = function() return CP().DB().thankMsg end, set = function(v) CP().DB().thankMsg = v end },
        { type = "note", tag = "whisper", indent = 28, text = function() return L("留空 = 用插件默认话术（每次随机一句）；改完按回车保存", "Leave empty for the default; press Enter to save") end },
    } })

-- ---------- 升级 → 经验加成：检查 ----------
local function XC() return ns.XpCheck end
local xpItems = {
    { type = "check", id = "xp.on", text = function() return L("开启（有没有、还剩多久、缺了怎么补）", "On (what you have, time left, how to get the rest)") end,
      get = function() return XC().Enabled() end, set = function(v) XC().Set("on", v) end },
    { type = "check", id = "xp.win", text = function() return L("显示提醒条（平时隐藏，快没了浮出来、再近一点高亮）", "Show the reminder bar (hidden until a bonus is ending)") end,
      get = function() return XC().DB().win ~= false end, set = function(v) XC().Set("win", v) end },
    { type = "check", id = "xp.always", inline = true, x = 380, text = function() return L("生效中也半透明显示", "Always show (faded)") end,
      get = function() return XC().DB().always == true end, set = function(v) XC().Set("always", v) end },
    { type = "check", id = "xp.warn", text = function() return L("聊天框提醒（浮出来 / 高亮 / 掉了各一次）", "Chat alerts (ending / urgent / ended)") end,
      get = function() return XC().DB().warn ~= false end, set = function(v) XC().Set("warn", v) end },
    { type = "check", id = "xp.sound", inline = true, x = 380, text = function() return L("提醒音效", "Alert sound") end,
      get = function() return XC().DB().sound == true end, set = function(v) XC().Set("sound", v) end },
    -- GI-225「提醒条可以移动」：平时没东西可拖 → 点「移动提醒条」五项全摆出来拖，再点锁定
    { type = "button", id = "xp.move", dyn = true, text = function() return (XC() and XC().moving) and L("锁定位置", "Lock position") or L("移动提醒条", "Move reminder bar") end,
      click = function() XC().SetMoving(not XC().moving) end },
    { type = "button", id = "xp.reset", inline = true, w = 90, text = function() return L("重置位置", "Reset position") end, click = function() XC().ResetPos() end },
    { type = "note", inline = true, text = function() return L("提醒条出来时也能直接按住拖", "You can also just drag the bar when it shows") end },
    { type = "label", id = "xp.checkLabel", w = 60, text = function() return L("查哪些：", "Check:") end },
}
for i = 1, 5 do
    xpItems[#xpItems + 1] = { type = "check", inline = true, id = "xp.item" .. i, step = function() return ns.zh and 104 or 112 end,
        avail = function() return XC().KEYS and XC().KEYS[i] ~= nil end,
        text = function() local t = XC().TITLE[XC().KEYS[i]]; return ns.L(t[1], t[2]) end,
        get = function() return XC().ItemOn(XC().KEYS[i]) end, set = function(v) XC().SetItem(XC().KEYS[i], v) end }
end
ns.RegisterSettings({ key = "xp", order = 70, page = "xp", avail = function() return ns.XpCheck ~= nil end,
    title = function() return L("经验加成检查（帐篷 / 营火 / 睡袋 / 经验食物 / 休息经验）", "XP bonus check (tent / campfire / bag / food / rested)") end, short = function() return L("经验加成", "XP check") end,
    items = xpItems })

-- ---------- 升级 → 升级规划：两扇小窗 ----------
ns.RegisterSettings({ key = "plan", order = 75, page = "plan",
    avail = function() return (ns.SetLevelingShown ~= nil and ns.LevelingShown ~= nil) or (ns.SideChains ~= nil and ns.SideChains.TrackerEnabled ~= nil) end,
    title = function() return L("升级指引 / 任务线追踪", "Leveling guide / quest line tracker") end, short = function() return L("升级指引", "Guide") end,
    items = {
        -- 11-12 玩家「升级指引关闭后怎么再开启」（只对当前角色）
        { type = "check", id = "plan.leveling", avail = function() return ns.SetLevelingShown ~= nil and ns.LevelingShown ~= nil end,
          text = function() return L("升级指引小窗（推荐地图 / 地下城 / 任务线，满 60 级前登录自动显示）", "Leveling guide window (shown on login until level 60)") end,
          get = function() return ns.LevelingShown() end, set = function(v) ns.SetLevelingShown(v) end },
        -- 11-07 用户「睡袋加一个全追踪的窗口吧，14级开始一直到做完」
        { type = "check", id = "plan.chain", avail = function() return ns.SideChains ~= nil and ns.SideChains.TrackerEnabled ~= nil end,
          text = function() return L("睡袋任务线追踪窗（14 级起钉在屏幕上显示当前第几步，做完自动消失）", "Sleeping bag quest line tracker (pinned from level 14 until done)") end,
          get = function() local SCh = ns.SideChains; return SCh.TrackerAllOn and SCh.TrackerAllOn() or SCh.TrackerEnabled() end,
          set = function(v) ns.SideChains.SetTrackerEnabled(v) end },
    } })

-- ---------- 职业 → 键位 ----------
ns.RegisterSettings({ key = "keys", order = 80, page = "keys", avail = function() return classHas("KeysCdm.lua", "KeysCdm") end,
    title = function() return L("键位", "Keys") end, short = function() return L("键位", "Keys") end,
    items = {
        { type = "check", id = "keys.cdm", text = function() return L("官方冷却管理器图标上显示快捷键", "Show keybinds on the Cooldown Manager") end,
          get = function() return not (ns.db and ns.db.ui and ns.db.ui.cdmKeys == false) end,   -- = KeysCdm.lua 的 KC.Enabled（默认开）
          set = function(v) classDo("KeysCdm", function(KC) KC.SetEnabled(v) end) end },
    } })

-- ---------- 职业 → 手法 / 右侧位面：开关本来就画在那一页上，这里只进索引（jumpOnly）----------
ns.RegisterSettings({ key = "rot", order = 82, page = "rot", jumpOnly = true, avail = function() return classHas("KeysRot.lua", "KeysRot") end,
    title = function() return L("手法（钉板 / 决策 HUD）", "Rotation (board / HUD)") end, short = function() return L("手法", "Rotation") end,
    items = {
        { type = "check", id = "rot.board", text = function() return L("屏幕上显示 GI 循环助手（钉板）", "Show the GI rotation helper on screen") end },
        { type = "check", id = "rot.hud", text = function() return L("钉板下挂决策 HUD（训练模式）", "Decision HUD under the helper (training)") end },
        { type = "check", id = "rot.share", text = function() return L("贡献我的施法频率（匿名，用来做「顶尖手法 · 公测版」）", "Share my cast frequency (anonymous, builds the beta rotation)") end },
    } })
ns.RegisterSettings({ key = "layer", order = 84, page = "layer", jumpOnly = true, avail = function() return ns.Layer ~= nil or ns.LayerGuild ~= nil end,
    title = function() return L("位面", "Layers") end, short = function() return L("位面", "Layers") end,
    items = {
        { type = "check", id = "layer.on", text = function() return L("开启位面识别（关了就不扫描、不发布）", "Layer detection on (off = no scanning, no broadcasting)") end },
        { type = "check", id = "layer.helper", text = function() return L("我愿意帮公会会员换层", "Help guildmates switch layers") end },
        { type = "check", id = "layer.autoHelp", text = function() return L("公会会员求助自动拉（不弹框）", "Auto-invite guildmates (no prompt)") end },
        { type = "check", id = "layer.autoLeave", text = function() return L("换过去后自动退队（换过去的层会留下）", "Leave the group after the move") end },
        { type = "check", id = "layer.autoAccept", text = function() return L("会长 / 官员的组队邀请自动接受", "Auto-accept leader / officer invites") end },
        { type = "check", id = "layer.pub", text = function() return L("加入公共频道（关了只和公会会员互通）", "Join public channel (off = guild only)") end },
    } })

-- ---------- 组队 → 法师吃喝（决定 4：开关只在组队抽屉第三个子页签里；索引只列名字能跳转）----------
--   文字和 MageWater.lua 的 OPT_ROWS 一致（gi_forever_ui_refactor_p2_test.py 核对两边一字不差）
ns.RegisterSettings({ key = "mage", order = 86, drawer = "mage", jumpOnly = true, avail = function() return mod("group") or (ns.ModuleLoaded and ns.ModuleLoaded("group")) end,
    title = function() return L("法师吃喝（找法师要水 / 法师发水）", "Mage food & water") end, short = function() return L("法师吃喝", "Mage food") end,
    items = {
        { type = "check", id = "mage.on", text = function() return L("总开关（和招人页「法师吃喝」按钮是同一个）", "Master switch (same as the Mage food button)") end },
        { type = "head", id = "mage.headAsk", text = function() return L("不是法师：帮你要", "Not a mage: ask for it") end },
        { type = "check", id = "mage.askTrade", text = function() return L("副本里跟法师开交易时，私聊他要", "Whisper the mage when you open a trade (in dungeons)") end },
        { type = "check", id = "mage.askAuto", text = function() return L("进副本 / 队伍满 5 人时自动要（队里有法师、背包不到一组才要）", "Ask automatically on entering a dungeon / full party (only if you're short)") end },
        { type = "check", id = "mage.askParty", text = function() return L("自动要改发队伍频道（默认私聊法师）", "Ask in party chat instead of whispering") end },
        { type = "check", id = "mage.thank", text = function() return L("法师给了水 / 面包、交易完成后自动私聊道谢", "Whisper thanks after a mage trades you food / water") end },
        { type = "check", id = "mage.fieldAsk", text = function() return L("野外 / 主城碰到法师、背包水不够时弹框问要不要密他（点了才发）", "Pop a prompt when a mage is nearby and you're low on water (only sends if you click)") end },
        { type = "head", id = "mage.headGive", text = function() return L("是法师：帮你发", "Mage: hand it out") end },
        { type = "check", id = "mage.reply", text = function() return L("队友要水时自动回一句", "Auto-reply when a party member asks") end },
        { type = "check", id = "mage.giveBtn", text = function() return L("交易窗下面出「一键放入」按钮", "Show a one-click \"put in\" button under the trade window") end },
        { type = "check", id = "mage.bar", text = function() return L("有人要时弹提醒条（带造水 / 造食按钮）", "Pop a request bar (with Conjure buttons) when someone asks") end },
        { type = "edit", id = "mage.whisper", tag = "whisper", text = function() return L("法师给水后道谢：", "Thanks to mage:") end },
    } })

-- ---------- 公会 → 公会设置（齿轮）：聊天里显示等级 / 升级播报 / 邀请入会 / 野外 PvP 通报 ----------
--   代码在内核（登录就要工作），界面在公会抽屉的齿轮里，也在「全部设置」索引里（不用加载公会子插件）
local function GCL()
    local g = ns.GuildChatLevel
    if g and g.Paused then return nil end   -- 10-25 0.5.5：公会频道等级暂停时开关不出
    return g
end
local guildItems = {
    { type = "head", id = "guild.headChat", avail = function() return GCL() ~= nil end, text = function() return L("聊天里显示等级", "Levels in chat") end },
    { type = "check", id = "guild.chat", avail = function() return GCL() ~= nil end, text = function() return L("公会频道消息前显示说话人的当前等级", "Show the speaker's level in guild chat") end,
      get = function() return GCL().Enabled() end, set = function(v) GCL().SetEnabled(v) end },
    { type = "check", id = "guild.zone", indent = 20, avail = function() return GCL() ~= nil and GCL().ZoneEnabled ~= nil end,   -- 11-06 用户「这里可以加上地区吗」
      text = function() return L("等级后面再加上所在地区（[24·贫瘠之地]）", "Also show their zone ([24·Barrens])") end,
      get = function() return GCL().ZoneEnabled() end, set = function(v) GCL().SetZoneEnabled(v) end },
    -- 11-10 用户「密语和小队都带上…都可以在设置关闭」
    { type = "check", id = "guild.whisper", avail = function() return GCL() ~= nil and GCL().WhisperOn ~= nil end,
      text = function() return L("密语消息前也显示对方等级（·地区）", "Also in whispers") end,
      get = function() return GCL().WhisperOn() end, set = function(v) GCL().SetWhisperOn(v) end },
    { type = "check", id = "guild.party", avail = function() return GCL() ~= nil and GCL().WhisperOn ~= nil end,
      text = function() return L("小队频道消息前也显示等级（·地区）", "Also in party chat") end,
      get = function() return GCL().PartyOn() end, set = function(v) GCL().SetPartyOn(v) end },
    { type = "head", id = "guild.headShout", avail = function() return ns.LevelShare ~= nil or ns.LevelMute ~= nil end, text = function() return L("升级播报（发到公会频道，6 级起）", "Level-up shout (guild chat, from level 6)") end },
}
for i, m in ipairs({ { "off", function() return L("关", "Off") end }, { "ask", function() return L("逢5级发，其他弹框问", "Every 5 auto, ask others") end },
    { "five", function() return L("每 5 级", "Every 5 levels") end }, { "milestone", function() return L("只在 10·20·30·40·50·60 级", "Milestones only") end } }) do
    local key = m[1]
    guildItems[#guildItems + 1] = { type = "check", radio = true, inline = i > 1, id = "guild.shout." .. key, avail = function() return ns.LevelShare ~= nil end,
        text = m[2],
        get = function() return (ns.db.lvlShare or "ask") == key end, set = function() ns.LevelShare.SetMode(key) end }
end
-- 10-26 玩家「公会里全是各家插件升级提醒」
guildItems[#guildItems + 1] = { type = "check", id = "guild.mute", avail = function() return ns.LevelMute ~= nil end,
    text = function() return L("屏蔽别人的升级 / 入会欢迎播报（各家插件在公会 / 队伍里刷的「升到 N 级」「欢迎 XX 加入」）", "Hide other players' level-up / guild-welcome shouts (addon spam in guild / group chat)") end,
    get = function() return ns.LevelMute.Enabled() end, set = function(v) ns.LevelMute.SetEnabled(v) end }
-- 11-06 用户「这些都是设置，有设置，默认打开」
guildItems[#guildItems + 1] = { type = "check", id = "guild.invite", avail = function() return ns.InviteMenu ~= nil and ns.InviteMenu.Enabled ~= nil end,
    text = function() return L("右键玩家菜单里加「邀请入会」", "Add \"Invite to guild\" to the player right-click menu") end,
    get = function() return ns.InviteMenu.Enabled() end, set = function(v) ns.InviteMenu.SetEnabled(v) end }
-- 11-06 野外荣誉击杀 / 被杀报公会；每项一个开关 + 「最多多久报一次」（1 / 5 / 10 / 30 分钟，默认 5）
guildItems[#guildItems + 1] = { type = "head", id = "guild.headPvp", avail = function() return ns.PvPShout ~= nil end, text = function() return L("野外 PvP 通报", "World PvP alerts") end }
for _, r in ipairs({
    { "kill", function() return L("野外荣誉击杀弹炫耀框（公会 / 小队 / 团队，写出对方阵营 / 等级 / 种族 / 职业 / 名字和坐标）", "Offer to show off world honorable kills (guild / party / raid; victim's faction / level / race / class / name and map pin)") end },
    { "death", function() return L("野外被玩家击杀弹求助框（公会 / 小队 / 团队，写出对方阵营 / 等级 / 种族 / 职业 / 名字和坐标）", "Ask for help when killed by a player in the world (guild / party / raid; killer's faction / level / race / class / name and map pin)") end },
}) do
    local kind = r[1]
    guildItems[#guildItems + 1] = { type = "check", id = "guild.pvp." .. kind, avail = function() return ns.PvPShout ~= nil end, h = 26,
        text = r[2],
        get = function() return ns.PvPShout.On(kind) end, set = function(v) ns.PvPShout.Set(kind, v) end }
    guildItems[#guildItems + 1] = { type = "label", id = "guild.pvp." .. kind .. ".cdLabel", indent = 18, w = 100, avail = function() return ns.PvPShout ~= nil end,
        text = function() return L("最多多久报一次：", "At most once per:") end }
    for ci, sec in ipairs({ 60, 300, 600, 1800 }) do
        guildItems[#guildItems + 1] = { type = "check", radio = true, inline = true, id = "guild.pvp." .. kind .. ".cd" .. sec,
            avail = function() local c = ns.PvPShout and (ns.PvPShout.CD_CHOICES or { 300 }); return c ~= nil and c[ci] ~= nil end,
            minW = 40, gap = 10,
            text = function() local s = (ns.PvPShout.CD_CHOICES or { 300 })[ci]; return ns.L((s / 60) .. " 分钟", (s / 60) .. " min") end,
            get = function() return ns.PvPShout.GetCD(kind) == (ns.PvPShout.CD_CHOICES or { 300 })[ci] end,
            set = function() ns.PvPShout.SetCD(kind, (ns.PvPShout.CD_CHOICES or { 300 })[ci]) end }
    end
end
ns.RegisterSettings({ key = "guild", order = 90, drawer = "guild", mods = true,
    avail = function() return GCL() ~= nil or ns.LevelShare ~= nil or ns.LevelMute ~= nil or ns.InviteMenu ~= nil or ns.PvPShout ~= nil end,
    title = function() return L("公会", "Guild") end, short = function() return L("公会", "Guild") end,
    items = guildItems })

-- ---------- 组队 → 组队设置（齿轮）----------
local function QM() return ns.QM end
local function wdb() ns.db.whispers = ns.db.whispers or {}; return ns.db.whispers end
local function whisperItem(k, text, id)
    return { type = "edit", id = id, tag = "whisper", text = text,
        get = function() return ns.db.whispers and ns.db.whispers[k] end, set = function(v) wdb()[k] = v end }
end
ns.RegisterSettings({ key = "group", order = 95, drawer = "group", mods = true,
    avail = function() return mod("group") or (ns.ModuleLoaded and ns.ModuleLoaded("group")) end,
    title = function() return L("组队", "Group up") end, short = function() return L("组队", "Group up") end,
    items = {
        copyItem(groupLoadItem, "group.load"),   -- 10-18 组队默认登录就加载（性能页也有同一个开关）
        { type = "note", id = "group.notLoaded", avail = function() return not QM() end,
          text = function() return string.format(L("%s模块还没加载（默认不加载）：点右侧「%s」页签后，这里出现它的设置", "The %s module isn't loaded yet: open the %s tab on the right and its settings appear here"),
              L("组队", "Group up"), L("组队", "Group up")) end },
        { type = "check", id = "group.share", avail = function() return QM() ~= nil end,
          text = function() return L("和附近玩家共享任务进度（组队页「附近任务」靠它）", "Share quest progress with nearby players") end,
          get = function() return not (ns.db.qm and ns.db.qm.share == false) end, set = function(v) QM().SetSharing(v) end },
        -- 11-12 用户「到主城关闭任务组队功能 / 停止扫描」
        { type = "check", id = "group.cityPause", avail = function() return QM() ~= nil and QM().SetCityPause ~= nil end,
          text = function() return L("进主城暂停任务共享和身边玩家扫描，出城自动恢复（城里人多会卡）", "Pause quest sharing and nearby scanning in capitals (saves FPS)") end,
          get = function() return QM().CityPauseOn() end, set = function(v) QM().SetCityPause(v) end },
        -- 10-18 觉得卡的玩家能在这里关（组队抽屉「身边玩家」标题右边也有同一个勾）
        { type = "check", id = "group.autoPlates", avail = function() return QM() ~= nil and QM().AutoPlatesOn ~= nil end,
          text = function() return L("打开组队窗口时自动开友方姓名板（认出身边没装插件的人；觉得卡可以先关掉）", "Auto friendly nameplates while the group window is open (try off if it feels laggy)") end,
          get = function() return QM().AutoPlatesOn() end, set = function(v) QM().SetAutoPlates(v) end },
        { type = "check", id = "group.thanks", avail = function() return QM() ~= nil and QM().Thanks ~= nil end,
          text = function() return L("队伍解散后提示向队友道谢", "Offer to thank teammates when a group ends") end,
          get = function() return QM().Thanks.On() end, set = function(v) QM().Thanks.Set(v) end },
        { type = "check", id = "group.ffa", avail = function() return QM() ~= nil and QM().AutoFFAOn ~= nil and QM().SetAutoFFA ~= nil end,
          text = function() return L("用组队工具组的队自动改成自由拾取（副本里不改）", "Groups formed with Group up switch to free-for-all loot (not in dungeons)") end,
          get = function() return QM().AutoFFAOn() end, set = function(v) QM().SetAutoFFA(v) end },
        -- GI-210「各种自动私信内容编辑」：存 ns.db.whispers[key]，留空 = 插件默认话术
        whisperItem("qm", function() return L("邀请一起做任务：", "Quest invite:") end, "group.wQm"),
        whisperItem("thanks", function() return L("退队感谢队友：", "Thanks on leave:") end, "group.wThanks"),
        whisperItem("lfg", function() return L("申请活动后私信：", "After applying:") end, "group.wLfg"),
        { type = "note", tag = "whisper", indent = 28, text = function() return L("留空 = 用插件默认话术；可用 {任务} {职业} {活动} {等级} {人数}；改完按回车保存",
              "Leave empty for the default; placeholders {任务} {职业} {活动} {等级} {人数}; press Enter to save") end },
    } })
