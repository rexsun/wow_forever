-- 主界面（v1，10-07）：窗口 + 左外侧竖排图标页签 + 小地图按钮
-- 各页在自己的文件里 ns.RegisterPage{ key, title, order, build(page), refresh(page) }
-- ⛔ 公会 / 组队 / 社交功能不放这里（归 GuildInsight）
local _, ns = ...

local W, H = 690, 586   -- 10-07 页签挪到面板外：内容区仍是 670 × 474（10-19 底部加 22 高页脚：版本 / 数据包日期 / QQ 群，内容区不变）
local FOOT = 22
local GOLD = { 1, 0.82, 0 }
local pages, frame, current = {}, nil, nil

function ns.RegisterPage(p)
    if not ns.db and ns.PageLangPairs then ns.PageLangPairs(p) end   -- 11-09 GI-202：记下页名的中英文，读到存档后按手动选的语言换
    pages[#pages + 1] = p
    table.sort(pages, function(a, b) return (a.order or 99) < (b.order or 99) end)
end
ns._Pages = pages   -- 测试用（左侧页签 / 顶部功能列表都按它画）
-- 10-11 录像用：还没发布的页（RegisterPage 时带 hold = true）在 /gif keys off 后不出页签、不进顶部功能列表
local function visiblePages()
    local t = {}
    for _, p in ipairs(pages) do
        -- 11-10 职业百宝箱：带 class 的页只给这个职业看（猎人弹药商 / 猎人宠物）
        local clsOk = not p.class or (ns.MyClass and ns.MyClass() == p.class)
        if clsOk and not (p.hold and ns.db and ns.db.hideHold) then t[#t + 1] = p end
    end
    return t
end

-- 公共小工具：页头大字 + 分隔线，返回内容区起始 y
function ns.PageHeader(p, title, sub)
    local hd = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hd:SetPoint("TOPLEFT", 12, -10)
    hd:SetText(title)
    hd:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    if sub then
        local s = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetPoint("LEFT", hd, "RIGHT", 10, -1)
        s:SetPoint("RIGHT", p, "RIGHT", -12, 0)
        s:SetJustifyH("LEFT")
        s:SetText(ns.EnSafe(sub))
        s:SetTextColor(0.7, 0.7, 0.7)
        p._sub = s
    end
    local ln = p:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    ln:SetPoint("TOPLEFT", 8, -34); ln:SetPoint("TOPRIGHT", -8, -34)
    ln:SetHeight(1)
    return -42
end

-- 10-18 用户截图「shift 点击发聊天框」：插件里的物品格子和游戏自带的一样 ——
--   Shift + 点 = 把物品链接插进聊天输入框（输入框没开就打开）；Ctrl + 点 = 试穿。处理了返回 true，调用方就不再做自己的点击动作。
--   物品还没缓存（GetItemInfo 回 nil）→ 先向服务器要，提示再点一次（自己拼的链接颜色 / 格式不对会被服务器吞掉）
--   10-18 用户截图：一直「还在加载」—— 旧接口在这个客户端拿不到 → 走 ns.ItemLink（C_Item 优先）；
--   真没缓存：向服务器要，数据一回来自动发（不用再点）；3 秒还没有 → Shift 退成插纯文字「[物品名]」，Ctrl 提示稍后再试
local modPending
-- 往聊天输入框插字：10-18 用户「shift还不行」—— 新客户端聊天函数可能挪进 ChatFrameUtil → 已知写法挨个试，最后直接写输入框
local function fnOr(t, k) return (type(t) == "table" and type(t[k]) == "function") and t[k] or false end
local function insertChat(text)
    for _, f in ipairs({ ChatEdit_InsertLink or false, fnOr(ChatFrameUtil, "InsertLink") }) do
        if type(f) == "function" then local ok, r = pcall(f, text); if ok and r then return "insert" end end
    end
    local eb
    for _, f in ipairs({ ChatEdit_GetActiveWindow or false, fnOr(ChatFrameUtil, "GetActiveWindow") }) do
        if type(f) == "function" then local ok, r = pcall(f); if ok and r then eb = r; break end end
    end
    if eb and eb.Insert then eb:Insert(text); return "active" end
    for _, f in ipairs({ ChatFrame_OpenChat or false, fnOr(ChatFrameUtil, "OpenChat") }) do
        if type(f) == "function" and pcall(f, text) then return "open" end
    end
    local eb2 = _G.ChatFrame1EditBox
    if eb2 and eb2.Insert then
        if eb2.Show then eb2:Show() end
        if eb2.SetFocus then eb2:SetFocus() end
        eb2:Insert(text)
        return "editbox"
    end
    ns.Print(ns.L("没找到聊天输入框，发不了：请把这句截图给我们（/gi itemprobe 可以帮忙查）", "Couldn't find the chat box (try /gi itemprobe and send us a screenshot)"))
    return nil
end
ns.InsertChat = insertChat
local function doMod(p, link)
    if p.shift then
        -- 游戏自带的物品修饰点击（Shift 发聊天 / Ctrl 试穿都管）有就先用它，最贴近原生行为
        if type(HandleModifiedItemClick) == "function" then local ok, r = pcall(HandleModifiedItemClick, link); if ok and r then return end end
        insertChat(link)
    else
        if type(HandleModifiedItemClick) == "function" then local ok, r = pcall(HandleModifiedItemClick, link); if ok and r then return end end
        if DressUpItemLink then pcall(DressUpItemLink, link) end
    end
end
-- 当前聊天输入框（Shift 没缓存时先插了纯文字，数据回来要在这个框里换成链接）
local function activeEditBox()
    for _, f in ipairs({ ChatEdit_GetActiveWindow or false, fnOr(ChatFrameUtil, "GetActiveWindow") }) do
        if type(f) == "function" then local ok, r = pcall(f); if ok and r then return r end end
    end
    local eb = _G.ChatFrame1EditBox
    if eb and eb.IsShown and eb:IsShown() then return eb end
end
local modEv = CreateFrame("Frame")
for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do pcall(modEv.RegisterEvent, modEv, e) end
modEv:SetScript("OnEvent", function(_, _, itemId)
    local p = modPending
    if not p or tonumber(itemId) ~= p.id then return end
    local link = ns.ItemLink(p.id)
    if not link then return end
    modPending = nil
    if p.placeholder then
        -- Shift：输入框里先插的「[名字]」原地换成真链接（玩家已经删掉 / 发出去了就算了）
        local eb = activeEditBox()
        local t = eb and eb.GetText and eb:GetText()
        local s, e
        if type(t) == "string" then s, e = t:find(p.placeholder, 1, true) end   -- ⛔ 别写 x and t:find()：and 只留第一个返回值
        if s and eb.SetText then eb:SetText(t:sub(1, s - 1) .. link .. t:sub(e + 1)) end
    elseif not p.shift then
        doMod(p, link)
    end
end)
ns._modEv = modEv   -- 测试用
-- ⛔ 10-18 用户「点击以后反应时间极慢」：原来没缓存时干等 3 秒才插字 → 现在 Shift 立刻插「[名字]」，数据回来再原地换成链接
function ns.ItemModClick(id, name)
    id = tonumber(id)
    if not id then return false end
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    if not (shift or ctrl) then return false end
    local p = { id = id, name = name, shift = shift and true or false }
    local link = ns.ItemLink(id)
    if link then doMod(p, link); return true end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    if p.shift and name and name ~= "" then
        p.placeholder = "[" .. name .. "]"
        insertChat(p.placeholder)
    elseif not p.shift then
        ns.Print(ns.L("物品信息还没从服务器读到，读到后自动试穿", "Item info not loaded yet; will try on when it arrives"))
    end
    modPending = p
    if C_Timer and C_Timer.After then C_Timer.After(10, function() if modPending == p then modPending = nil end end) end
    return true
end

function ns.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- 分段按钮（10-17 用户截图「按键材质和选择状态优化」：组队顶上 [附近任务][副本组队] 那种红色原生按钮切换项）
--   扁平深底细边：没选 = 深灰底灰边灰白字；选中 = 暗金底金边亮金字 + 底下 2px 金线；悬停 = 淡金光。
--   用法同 ns.Button；选中用 ns.SegSelect(b, on)（PageGroup 的 markSel 认到 b._seg 会转过来）
local SEG_BD = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
function ns.SegSelect(b, on)
    b._segOn = on and true or false
    if b.SetBackdropColor then
        if on then b:SetBackdropColor(0.22, 0.17, 0.04, 0.98); b:SetBackdropBorderColor(1, 0.82, 0, 0.95)
        else b:SetBackdropColor(0.07, 0.08, 0.10, 0.95); b:SetBackdropBorderColor(0.32, 0.32, 0.34, 0.9) end
    end
    if b._segFs then
        if on then b._segFs:SetTextColor(1, 0.86, 0.2) else b._segFs:SetTextColor(0.78, 0.78, 0.78) end
    end
    if b._segLine then b._segLine:SetShown(on and true or false) end
end
function ns.SegButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(w or 90, h or 22)
    if b.SetBackdrop then b:SetBackdrop(SEG_BD) end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", 0, 0)
    if b.SetFontString then b:SetFontString(fs) end
    b._segFs = fs
    b:SetText(text or "")
    local line = b:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 0.82, 0, 1)
    line:SetPoint("BOTTOMLEFT", 1, 1); line:SetPoint("BOTTOMRIGHT", -1, 1); line:SetHeight(2)
    b._segLine = line
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1); hl:SetColorTexture(1, 0.82, 0, 0.10)
    b._seg = true
    if onClick then b:SetScript("OnClick", onClick) end
    if b.HookScript then
        b:HookScript("OnMouseDown", function() fs:SetPoint("CENTER", 1, -1) end)
        b:HookScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
    end
    ns.SegSelect(b, false)
    return b
end

-- ---------- 职业：公共常量 + 职业按钮条（10-07 用户：职业加图标、本职业高亮）----------
ns.CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
ns.CLASS_COLOR = { Warrior = "c79c6e", Paladin = "f58cba", Hunter = "abd473", Rogue = "fff569", Priest = "ffffff",
    Shaman = "0070de", Mage = "69ccf0", Warlock = "9482c9", Druid = "ff7d0a" }
ns.CLASS_ICON = { Warrior = "inv_sword_27", Paladin = "spell_holy_holybolt", Hunter = "inv_weapon_bow_07",
    Rogue = "inv_throwingknife_04", Priest = "inv_staff_30", Shaman = "spell_nature_bloodlust",
    Mage = "inv_staff_13", Warlock = "spell_nature_drowsy", Druid = "ability_druid_maul" }

function ns.MyClass()
    local _, token = UnitClass("player")
    token = token or "Warrior"
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 本职业：金色描边（四条边）；返回描边容器，调用方不用管
function ns.MarkMine(b)
    local c = { 1, 0.82, 0, 0.95 }
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c[1], c[2], c[3], c[4])
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- 一排 9 个职业按钮（图标 + 职业色名字；本职业金框）；返回按钮表，每个有 .cls / .sel
local SHORT_CN = { Paladin = "圣骑", Shaman = "萨满", Druid = "德鲁伊" }
function ns.ClassBar(p, y, onClick)
    local btns, mine = {}, ns.MyClass()
    local x = 8
    for k, cls in ipairs(ns.CLASSES) do
        local b = CreateFrame("Button", nil, p)
        -- 10-07 用户「优化UI」：9 × 73 超出页面、长名字被截成「圣骑…」→ 短名
        -- 10-08 用户截图「最边上的德鲁伊展示全」：等宽 68 放不下三个字 → 按名字长短给宽度（两字 64 / 三字 78，合计 622 < 646）
        local label = ns.L(SHORT_CN[cls] or ns.Data.classCn[cls] or cls, cls)
        local zh = ns.zh
        local w = zh and ((#label > 6) and 78 or 64) or 68   -- UTF-8 中文一字 3 字节：>6 = 三个字；英文统一 68
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", x, y); x = x + w + 4
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local sel = b:CreateTexture(nil, "BACKGROUND", nil, 1); sel:SetAllPoints(); sel:SetColorTexture(0.2, 0.8, 0.6, 0.3); sel:Hide()
        -- 选中：底下一条职业色粗线（比整块染色清楚，也不和本职业金框打架）
        local r, g, bb = tonumber(ns.CLASS_COLOR[cls]:sub(1, 2), 16) / 255, tonumber(ns.CLASS_COLOR[cls]:sub(3, 4), 16) / 255, tonumber(ns.CLASS_COLOR[cls]:sub(5, 6), 16) / 255
        local line = b:CreateTexture(nil, "ARTWORK", nil, 2); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(3)
        line:SetColorTexture(r, g, bb, 1)
        sel:SetColorTexture(r, g, bb, 0.22)
        line:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("LEFT", 3, 0)
        ic:SetTexture("Interface\\Icons\\" .. ns.CLASS_ICON[cls]); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", ic, "RIGHT", 3, 0); fs:SetPoint("RIGHT", -2, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:SetText("|cff" .. ns.CLASS_COLOR[cls] .. label .. "|r")
        if cls == mine then ns.MarkMine(b) end
        -- .sel 是个小代理：底色和底线一起开关（页面里只调 b.sel:SetShown）
        b.sel = { SetShown = function(_, v) sel:SetShown(v); line:SetShown(v) end, IsShown = function() return sel:IsShown() end }
        b.cls = cls
        b:SetScript("OnClick", function() onClick(cls) end)
        b:SetScript("OnEnter", function(self)   -- 名字万一被截也能看全（用户硬规定：显示不全一律挂 tooltip）
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("|cff" .. ns.CLASS_COLOR[cls] .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r")
            if cls == mine then GameTooltip:AddLine(ns.L("你的职业", "Your class"), 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btns[k] = b
    end
    return btns
end

-- 可滚动内容：返回 scroll, child（child 宽度跟随）
function ns.Scroll(parent, x, y, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", x, y)
    sf:SetSize(w, h)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(w, 10)
    sf:SetScrollChild(c)
    return sf, c
end

-- 10-07 用户「板式也变成这种页签的」（GuildInsight 改版那张图）：标题栏 logo 色带 + 挂在面板左外侧的竖排大图标页签，
--   选中 = 金边；页面内容区宽高不变（页签挪出去后面板窄 118px，标题栏多出来 44px）
-- ⛔ 图标只用 60 级经典就有的游戏图标（无限客户端里一定存在）
local TAB_ICON = {
    talent = "Interface\\Icons\\INV_Misc_Book_11",
    macro = "Interface\\Icons\\INV_Scroll_05",
    loot = "Interface\\Icons\\INV_Misc_Bag_10",
    tier = "Interface\\Icons\\INV_Chest_Plate03",
    news = "Interface\\Icons\\INV_Letter_15",
    data = "Interface\\Icons\\INV_Misc_Note_01",
}
local LOGO = "Interface\\AddOns\\GearInsight_Forever\\media\\logo"
local HEAD = 80    -- 标题栏高度（内容区从这里往下）

local function setTabSel(b, on)
    if b.SetBackdropColor then
        if on then b:SetBackdropColor(0.13, 0.12, 0.07, 0.98); b:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        else b:SetBackdropColor(0.05, 0.06, 0.08, 0.92); b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8) end
    end
    if on then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.82, 0.82, 0.82) end
end

-- ---------- 页签大类（10-18 用户「按正式服方式…优化页签，看看有没有可以合并一个类目下的」+「资讯分类下面有猎人宠物攻略」）----------
-- 照正式服 MainTabs.lua 的 grp_*：成员页 key 不变（命令 / 别的页 ShowPage 照旧能跳），左栏只出大类；
-- 点大类 = 打开这组上次看的那页（没有就第一页），这组的成员在大类页签正下方展开成缩进小按钮。
-- 没有可用成员的大类不出（HOLD 隐藏 / hiddenTab 的成员不算）。
local GROUPS = ns.LateL({   -- 11-09 GI-202：手动切语言后跟着换
    -- 11-10 用户「游戏里弄个职业百宝箱页签…根据当前职业推职业特有工具」「之前猎人宠物也挪过来」「可以考虑和手法，宏合并」：
    --   原「手法」大类改名「职业百宝箱」，职业专属页（带 class 字段，别的职业看不到）排最前
    { key = "grp_rot", order = 1.5, title = ns.L("职业百宝箱", "Class toolkit"), icon = "Interface\\Icons\\INV_Misc_Bag_10", members = { "ammo", "pet", "rot", "macro", "keys" } },
    { key = "grp_up", order = 1.8, title = ns.L("升级", "Leveling"), icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", members = { "plan", "prof", "xp", "ach" } },   -- 11-09 xp = 经验加成（XpCheck.lua，HOLD）
    { key = "grp_gear", order = 2, title = ns.L("装备", "Gear"), icon = "Interface\\Icons\\INV_Chest_Plate03", members = { "gear", "loot", "tier" } },
    { key = "grp_info", order = 3.5, title = ns.L("资讯攻略", "News & Guides"), icon = "Interface\\Icons\\INV_Letter_15", members = { "news" } },   -- 11-10 用户「改成资讯攻略」；猎人宠物 11-10 挪去职业百宝箱
    -- 10-19 用户「进阶就放最外面一级目录」：adv（进阶 · 网站与小程序，PageAdvanced.lua，HOLD）不进资讯组，单独一个左栏页签
})
ns._TabGroups = GROUPS   -- 测试用
-- ---------- 10-18 公会 / 组队拆成按需加载的子插件（用户「工会和组队都单拆子模块，默认不加载」→ 选「页签照常显示，点了才加载」）----------
--   主插件只在右侧放占位页签；第一次点 = LoadAddOn → 子插件挂真页签 → 换到占位的位置 → 替玩家点开。
--   公会频道等级 / 升级播报 10-19 用户「拿到主插件，不要放子插件了」搬回主插件（GuildChatLevel.lua / LevelShare.lua），不点公会页签也照常运行。
--   组队 10-18 改成登录就加载（见下面 GroupAutoLoad），设置里可改回点了才加载。
local MODS = {
    guild = { addon = "GearInsight_Forever_Guild", stub = "_giGuildStub", real = "_giGuildTab", zh = "公会", en = "Guild",
        icon = "Interface\\AddOns\\GearInsight_Forever\\media\\logo",
        tipZh = "本公会会员的专业 · 正在招人的公会", tipEn = "Your guild's professions - recruiting guilds",
        ready = function() return ns.GuildTabAttach ~= nil end,
        attach = function() if ns.GuildTabAttach then pcall(ns.GuildTabAttach) end; if ns.GuildHome and ns.GuildHome.Wire then pcall(ns.GuildHome.Wire) end end },
    group = { addon = "GearInsight_Forever_Group", stub = "_giGroupStub", real = "_giQmTab", zh = "组队", en = "Group up",
        icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        tipZh = "附近同任务的人 · 副本组队", tipEn = "Players on your quests nearby - dungeon groups",
        ready = function() return ns.QMAttach ~= nil end,
        attach = function() if ns.QMAttach then pcall(ns.QMAttach) end end },
}
local MOD_ORDER = { "guild", "group" }
ns._Modules = MODS   -- 测试用

local function addonInfo(name)
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not f then return nil end
    local ok, n, _, _, loadable, reason = pcall(f, name)
    if not ok then return nil end
    return n, loadable, reason
end
function ns.ModuleLoaded(key) local m = MODS[key]; return m and m.ready() or false end
-- 子插件文件夹在不在（没装 / 被删 → 不出占位页签）
function ns.ModuleAvailable(key)
    local m = MODS[key]
    if not m then return false end
    if m.ready() then return true end
    local n, _, reason = addonInfo(m.addon)
    return n ~= nil and reason ~= "MISSING"
end
-- 让真页签顶替占位页签的位置（主面板还没建 = 什么都不做，等主面板建好时子插件自己挂、占位也不会建）
local function swapIn(key)
    local m = MODS[key]
    local host = _G.GearInsightForeverMain
    if not (m and host) then return end
    m.attach()
    local real, stub, side = rawget(host, m.real), rawget(host, m.stub), rawget(host, "_giSide")
    if real and stub and type(side) == "table" then
        local si, ri
        for i, b in ipairs(side) do if b == stub then si = i elseif b == real then ri = i end end
        if ri then table.remove(side, ri); if si and ri < si then si = si - 1 end end
        if si then side[si] = real else side[#side + 1] = real end
        stub:Hide(); host[m.stub] = nil
        if ns.LayoutSideTabs then ns.LayoutSideTabs(host) end
    end
end

function ns.LoadModule(key)
    local m = MODS[key]
    if not m then return false end
    if m.ready() then return true end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not load then return false end
    local ok, loaded, reason = pcall(load, m.addon)
    if ok and not loaded and reason == "DISABLED" then   -- 插件列表里被关了：这个角色启用一下再加载
        local en = (C_AddOns and C_AddOns.EnableAddOn) or EnableAddOn
        if en then pcall(en, m.addon, UnitName and UnitName("player")) end
        ok, loaded, reason = pcall(load, m.addon)
    end
    if ok and loaded and m.ready() then
        pcall(swapIn, key)   -- 不管从哪加载（页签 / 斜杠命令 / 小地图菜单），占位页签都立刻换成真的，不会出两个
        return true
    end
    ns.Print(string.format(ns.L("%s模块加载失败（%s）：插件列表里看看 %s 是不是没装 / 被关了", "Couldn't load the %s module (%s): check %s in your AddOns list"),
        ns.L(m.zh, m.en), tostring(ok and reason or loaded), m.addon))
    return false
end

-- 11-10 用户「组队完退队没有弹出感谢框」：道谢在组队子插件（按需加载）里，没点过「组队」页签它根本没加载，进队 / 退队都没人记
--   → 进了队伍（脱战时）就悄悄把组队子插件加载上，开始记同队时长；道谢关掉了（/gi 感谢 关）就不加载
local thLoader = CreateFrame("Frame")
thLoader:RegisterEvent("GROUP_ROSTER_UPDATE")
thLoader:RegisterEvent("PLAYER_REGEN_ENABLED")
thLoader:SetScript("OnEvent", function(self)
    if MODS.group.ready() then self:UnregisterAllEvents(); return end
    if not (IsInGroup and IsInGroup()) or (InCombatLockdown and InCombatLockdown()) then return end
    if ns.db and ns.db.qm and ns.db.qm.thanks == false then return end
    if ns.LoadModule("group") then
        self:UnregisterAllEvents()
        local QM = ns.QM
        if QM and QM.Thanks and QM.Thanks.Roster then pcall(QM.Thanks.Roster) end
    end
end)
ns._thLoader = thLoader

function ns.OpenModule(key)
    if not ns.LoadModule(key) then return false end
    local host = _G.GearInsightForeverMain
    if not host then return true end
    pcall(swapIn, key)
    return true, rawget(host, MODS[key].real)
end

local function clickTab(b)
    if not b then return end
    local pre, on = b:GetScript("PreClick"), b:GetScript("OnClick")
    if pre then pre(b) end
    if on then on(b) end
end
ns.ClickSideTab = clickTab

local function ensureStubs()
    local host = _G.GearInsightForeverMain
    local W = ns.W or _G.GIWidgets
    if not (host and W and W.SideTab) then return end
    host._giSideTop = -80
    for _, key in ipairs(MOD_ORDER) do
        local m = MODS[key]
        if not m.ready() and not rawget(host, m.stub) and not rawget(host, m.real) and ns.ModuleAvailable(key) then
            local b = W.SideTab(host, ns.L(m.zh, m.en), m.icon, -80)
            host[m.stub] = b
            b:SetScript("OnClick", function()
                local ok, real = ns.OpenModule(key)
                if ok and real then clickTab(real) end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(ns.L(m.zh, m.en), 1, 0.82, 0)
                GameTooltip:AddLine(ns.L(m.tipZh, m.tipEn), 1, 1, 1, true)
                GameTooltip:AddLine(ns.L("第一次点开时才加载这个模块，不点不占资源", "This module loads the first time you open it"), 0.6, 0.6, 0.6, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    if W.KeepSideTabsOnScreen then W.KeepSideTabsOnScreen(host) end
end
ns.EnsureModuleStubs = ensureStubs

-- 模块的斜杠命令：没加载时先加载再执行（加载后子插件会用真函数盖掉这里的占位）
ns.ExtraSlash = ns.ExtraSlash or {}
for key, cmds in pairs({ group = { "qm", "感谢", "thanks", "组队", "lfg", "lfg2", "lfgprobe" }, guild = { "guildprobe" } }) do   -- 升级播报 / lvlshare 10-19 随 LevelShare.lua 搬回主插件，不再是占位
    for _, c in ipairs(cmds) do
        local stub
        stub = function(rest, rawRest)
            if not ns.LoadModule(key) then return end
            local f = ns.ExtraSlash[c]
            if f and f ~= stub then return f(rest, rawRest) end
            if key == "group" and ns.OpenGroupDrawer then ns.OpenGroupDrawer(c == "组队" and "dungeon" or nil) end
        end
        ns.ExtraSlash[c] = stub
    end
end

-- 10-18 用户「组队是不是应该默认加载」：是 —— 附近任务靠每个人把自己的进度发出去，不加载 = 别人看不到你。
--   组队仍是单独的子插件文件夹，但登录就加载（设置里可关：ns.db.ui.groupLazy = true 时改回点了才加载）；
--   关了也照旧：组队抽屉上次钉着开着 → 登录就加载（不然钉住的抽屉不会自己回来）。公会仍是点了才加载
function ns.GroupAutoLoad() return not (ns.db and ns.db.ui and ns.db.ui.groupLazy) end
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if not ns.ModuleAvailable("group") then return end
        local q = ns.db and ns.db.qm
        if ns.GroupAutoLoad() or (q and q.pinned and q.open) then pcall(ns.LoadModule, "group") end
    end)
    ns._LoginLoad = ev:GetScript("OnEvent")   -- 测试用
end

-- 10-18 右侧页签统一排位：上一个页签有展开的子页签（公会：本公会 / 公会招募；组队：附近任务 / 副本组队）→ 下一个往下让出高度
function ns.LayoutSideTabs(host)
    local side = host and rawget(host, "_giSide")
    if type(side) ~= "table" then return end
    -- 第一个页签贴主面板右上（公会 / 组队按需加载后真页签换下占位页签，可能换到第一个位置）
    if side[1] then side[1]:ClearAllPoints(); side[1]:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, rawget(host, "_giSideTop") or -80) end
    for i = 2, #side do
        local prev, b = side[i - 1], side[i]
        local n = 0
        for _, sb in ipairs(rawget(prev, "_giSubs") or {}) do if sb:IsShown() then n = n + 1 end end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6 - n * (24 + 4))
    end
end
local grpOf = {}
for _, g in ipairs(GROUPS) do for _, k in ipairs(g.members) do grpOf[k] = g end end

local function groupMembers(g)
    local byKey = {}
    for _, p in ipairs(visiblePages()) do if not p.hiddenTab then byKey[p.key] = p end end
    local t = {}
    for _, k in ipairs(g.members) do if byKey[k] then t[#t + 1] = byKey[k] end end
    return t
end

-- 左栏条目：不属于任何大类的页 + 至少有一个可用成员的大类，按 order 排
local function navEntries()
    local t = {}
    for _, p in ipairs(visiblePages()) do
        if not p.hiddenTab and not grpOf[p.key] then t[#t + 1] = { order = p.order or 99, page = p } end
    end
    for _, g in ipairs(GROUPS) do
        if #groupMembers(g) > 0 then t[#t + 1] = { order = g.order, grp = g } end
    end
    table.sort(t, function(a, b) return a.order < b.order end)
    return t
end
ns._NavEntries = navEntries

local layoutNav   -- build() 里赋值（要用到 frame 上建好的按钮）

local function showPage(key)
    local vis = visiblePages()
    local okKey = false
    for _, p in ipairs(vis) do if p.key == key then okKey = true end end
    if not okKey and vis[1] then key = vis[1].key end   -- 记住的页被隐藏了 → 退回第一页
    for _, p in ipairs(pages) do
        if p.frame then p.frame:Hide() end
    end
    for _, p in ipairs(pages) do
        if p.key == key then
            if not p.frame then
                local f = CreateFrame("Frame", nil, frame)
                f:SetPoint("TOPLEFT", 10, -HEAD)
                f:SetPoint("BOTTOMRIGHT", -10, 10 + FOOT)
                local ok, err = pcall(p.build, f)
                if not ok then ns.Print("页面出错 " .. p.key .. ": " .. tostring(err)) end
                p.frame = f
            end
            p.frame:Show()
            if p.refresh then pcall(p.refresh, p.frame) end
            current = key
            ns.db.ui = ns.db.ui or {}
            ns.db.ui.page = key
            local g = grpOf[key]
            if g then
                ns.db.ui.grpLast = ns.db.ui.grpLast or {}
                ns.db.ui.grpLast[g.key] = key
            end
        end
    end
    if layoutNav then layoutNav() end
end
ns.ShowPage = showPage

-- 11-09 GI-196「界面加个窗口放大吧，默认界面太小了眼都要瞎了」：主窗口整体缩放（存 ns.db.ui.scale，nil = 100%）
--   设置页单选 / 主窗口上 Ctrl + 滚轮 / /gi scale 120；放大后超出屏幕高度就压到刚好放得下
ns.SCALES = { 0.9, 1, 1.1, 1.2, 1.3, 1.4 }
function ns.UIScale() return (ns.db and ns.db.ui and ns.db.ui.scale) or 1 end
local function fitScale(s)
    s = math.max(0.7, math.min(1.6, s or 1))
    local sh = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if sh and sh > 0 then s = math.min(s, (sh - 20) / H) end
    return s
end
function ns.ApplyUIScale()
    if frame and frame.SetScale then frame:SetScale(fitScale(ns.UIScale())) end
end
function ns.SetUIScale(s)
    s = tonumber(s)
    if not s then return end
    if s > 3 then s = s / 100 end   -- /gi scale 120
    s = math.floor(math.max(0.7, math.min(1.6, s)) * 100 + 0.5) / 100
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.scale = (s ~= 1) and s or nil
    ns.ApplyUIScale()
    local real = fitScale(s)
    if real < s - 0.001 then
        ns.Print(string.format(ns.L("屏幕高度放不下 %d%%，先按 %d%% 显示（把游戏「界面缩放」调小就能再放大）",
            "%d%% doesn't fit your screen height - showing %d%% (lower the game's UI Scale to go bigger)"), math.floor(s * 100 + 0.5), math.floor(real * 100)))
    end
    return s
end

local function build()
    local f = CreateFrame("Frame", "GearInsightForeverMain", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 50, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- GI-196：Ctrl + 滚轮缩放（滚动列表上的滚轮照旧给列表）
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, d)
        if not (IsControlKeyDown and IsControlKeyDown()) then return end
        local s = ns.SetUIScale(ns.UIScale() + (d > 0 and 0.05 or -0.05))
        if s and UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(string.format(ns.L("GearInsight 窗口大小 %d%%", "GearInsight window size %d%%"), math.floor(s * 100 + 0.5)), 1, 0.82, 0)
        end
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.04, 0.05, 0.07, 0.96); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end

    -- 标题栏：logo + 名字 + 版本；下一行 = 角色 / 开服提示
    local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("TOPLEFT", 5, -5); band:SetPoint("TOPRIGHT", -5, -5); band:SetHeight(68)
    band:SetColorTexture(0.10, 0.20, 0.16, 0.55)
    local logo = f:CreateTexture(nil, "ARTWORK"); logo:SetSize(58, 58); logo:SetPoint("TOPLEFT", 12, -10); logo:SetTexture(LOGO)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GearInsight_Forever", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("GearInsight_Forever", "Version")) or ""
    title:SetText("|cff33ff99Gear|r|cffffd200Insight|r " .. ns.L("无限版", "Forever") .. "  |cff888888" .. ver .. "|r")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    -- Keep long localized page lists inside the header, including added pages.
    f.sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.sub:SetHeight(28)
    f.sub:SetJustifyH("LEFT"); f.sub:SetJustifyV("TOP")
    f.sub:SetWordWrap(true)
    if f.sub.SetMaxLines then f.sub:SetMaxLines(2) end
    local subHit = CreateFrame("Frame", nil, f)
    subHit:SetAllPoints(f.sub); subHit:EnableMouse(true)
    subHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(f.sub:GetText() or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    subHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local cmd = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); cmd:SetPoint("TOPRIGHT", -40, -22)
    cmd:SetText(ns.SlashHint or "/gif")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    f.closeBtn = close; ns._MainFrame = f   -- 测试用
    close:SetScript("OnClick", function() f:Hide() end)   -- 10-18 战斗中关不掉：原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    local line = f:CreateTexture(nil, "ARTWORK"); line:SetPoint("TOPLEFT", 6, -73); line:SetPoint("TOPRIGHT", -6, -73); line:SetHeight(1)
    line:SetColorTexture(0.85, 0.68, 0.25, 0.45)
    -- 页脚（10-19 用户「无限也加一行页脚，显示版本号和数据日期」「还有QQ群」）：
    --   左 = QQ 群（中文客户端，点击弹复制框）/ 英文 = 网站；右 = 插件版本 · 数据包日期（GIF_PACK.version = YYYYMMDD.HHMM，更新器下载；没装 = 提示）
    local fsep = f:CreateTexture(nil, "ARTWORK")
    fsep:SetPoint("BOTTOMLEFT", 10, 10 + FOOT - 2); fsep:SetPoint("BOTTOMRIGHT", -10, 10 + FOOT - 2); fsep:SetHeight(1)
    fsep:SetColorTexture(0.85, 0.68, 0.25, 0.3)
    local fRight = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fRight:SetPoint("BOTTOMRIGHT", -14, 13); fRight:SetJustifyH("RIGHT")
    f.footRight = fRight
    local fLeft = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fLeft:SetPoint("BOTTOMLEFT", 14, 13); fLeft:SetJustifyH("LEFT")
    local qq = ns.zh and "152706590" or nil
    local link = qq or "gearinsight.app/wow/forever"
    fLeft:SetText(qq and ("QQ群 |cff66ccff" .. qq .. "|r |cff888888（点击复制）|r") or ("|cff66ccff" .. link .. "|r |cff888888(click to copy)|r"))
    local fHit = CreateFrame("Button", nil, f)
    fHit:SetPoint("TOPLEFT", fLeft, "TOPLEFT", -2, 3); fHit:SetPoint("BOTTOMRIGHT", fLeft, "BOTTOMRIGHT", 2, -3)
    fHit:SetScript("OnClick", function()
        local Wd = ns.W or _G.GIWidgets
        if Wd and Wd.Copy then Wd.Copy(link, qq and ns.L("无限服 QQ 群", "QQ group") or "GearInsight Forever") end
    end)
    fHit:SetScript("OnEnter", function() fLeft:SetAlpha(0.75) end)
    fHit:SetScript("OnLeave", function() fLeft:SetAlpha(1) end)
    function ns.FooterText()
        local pk = rawget(_G, "GIF_PACK")
        local pv = type(pk) == "table" and tostring(pk.version or "") or ""
        local y, mo, d, hh, mi = pv:match("^(%d%d%d%d)(%d%d)(%d%d)%.?(%d?%d?)(%d?%d?)")
        local data
        if y then
            data = ns.L("数据 ", "data ") .. y .. "-" .. mo .. "-" .. d .. ((hh ~= "" and mi ~= "") and (" " .. hh .. ":" .. mi) or "")
        else
            -- 11-06 玩家（网易 DD 下载）「为什么显示数据包未下载」：大部分玩家不装更新器，插件内置数据照常能用 → 别写得像故障
            data = "|cff9d9d9d" .. ns.L("内置数据", "built-in data") .. "|r"
        end
        return "v" .. (ver ~= "" and ver or "?") .. "  ·  " .. data
    end
    fRight:SetText(ns.FooterText())
    f:SetScript("OnShow", function(self)
        local lv = UnitLevel and UnitLevel("player") or 0
        local cls = ns.MyClass()
        -- 页签名现查 pages 表拼，⛔别手写死list：新加页会漏（10-07 升级规划/资讯两页上线时就漏过一次）
        -- 10-18 页签分大类后：顶部列的是左栏大类（和左栏一一对应）
        local names = {}
        for _, e in ipairs(navEntries()) do names[#names + 1] = e.grp and e.grp.title or (e.page.tabTitle or e.page.title) end
        self.sub:SetText("|cff" .. (ns.CLASS_COLOR[cls] or "ffffff") .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r  "
            .. ns.L("等级 ", "level ") .. lv .. "   |cff888888" .. table.concat(names, " · ") .. "|r")
    end)

    -- 页签：挂在面板左外侧的竖排大标签（图标 + 名字），点标签换整页
    -- hiddenTab = 页还在（命令 / 别的页能跳过去），只是左侧不出页签（10-16 用户「先隐藏这个 TAB」：手法页）
    -- 10-18 分大类（照正式服）：10 个页签 → 6 个大类，大类下的成员页在它正下方展开成缩进小按钮
    --   高度：6 大类 × 48 + 5 × 6 = 318，加最长一组展开 3 × 28 = 84 → 402 + 起点 80 = 482 < 面板 564
    local TH, TG, SUB_H, SUB_STEP = 48, 6, 24, 28
    -- 10-21 左栏加「攻略」后 9 个大类：9 × 48 + 8 × 6 + 最长一组展开 88 = 568 → 起点 80 超出面板 → 9 个及以上时大标签压到 42 高、间距 5（9 × 42 + 8 × 5 + 88 + 80 = 586 = 面板高）
    if #navEntries() >= 9 then TH, TG = 42, 5 end
    local function bigTab(label, icon)
        local b = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        b:SetSize(100, TH)
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        end
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(24, 24); ic:SetPoint("LEFT", 9, 0)
        ic:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark"); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.label:SetPoint("LEFT", ic, "RIGHT", 7, 0)
        b.label:SetPoint("RIGHT", -4, 0); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
        b.label:SetText(label)
        -- 11-11 用户截图「职业百...」被截：字放不下就逐号缩小字号（最小 10），不省略
        local font, size, flags = b.label:GetFont()
        if type(font) == "string" and type(size) == "number" and b.label.GetStringWidth then
            local room = 100 - 9 - 24 - 7 - 4
            while size > 10 and (tonumber(b.label:GetStringWidth()) or 0) > room do
                size = size - 1
                b.label:SetFont(font, size, flags)
            end
        end
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
        setTabSel(b, false)
        return b
    end
    -- 成员小按钮：纯文字、比大标签窄 14（右对齐 = 往里缩进），选中金边金字（和 ns.SegButton 一个配色）
    local function subTab(p)
        local b = ns.SegButton(f, p.tabTitle or p.title, 86, SUB_H, function() showPage(p.key) end)
        b:Hide()
        return b
    end
    local entries = navEntries()
    for _, e in ipairs(entries) do
        if e.grp then
            local g = e.grp
            e.btn = bigTab(g.title, g.icon)
            e.btn:SetScript("OnClick", function()
                local mem = groupMembers(g)
                local last = ns.db.ui and ns.db.ui.grpLast and ns.db.ui.grpLast[g.key]
                local to = mem[1] and mem[1].key
                for _, p in ipairs(mem) do if p.key == last then to = last end end
                if to then showPage(to) end
            end)
            g.tab = e.btn
            e.subs = {}
            for _, p in ipairs(groupMembers(g)) do
                local sb = subTab(p)
                e.subs[#e.subs + 1] = { page = p, btn = sb }
                p.subTab = sb
            end
        else
            local p = e.page
            e.btn = bigTab(p.tabTitle or p.title, p.icon or TAB_ICON[p.key])
            e.btn:SetScript("OnClick", function() showPage(p.key) end)
            p.tab = e.btn
        end
    end
    f.navEntries = entries
    -- 每次换页重新排：当前页所在大类展开，别的组收起
    layoutNav = function()
        local y = -80
        for _, e in ipairs(entries) do
            e.btn:ClearAllPoints()
            e.btn:SetPoint("TOPRIGHT", f, "TOPLEFT", 3, y)
            y = y - TH - TG
            local open = e.grp and grpOf[current or ""] == e.grp
            setTabSel(e.btn, (e.page and e.page.key == current) or open)
            for _, s in ipairs(e.subs or {}) do
                if open then
                    s.btn:ClearAllPoints()
                    s.btn:SetPoint("TOPRIGHT", f, "TOPLEFT", 3, y + TG - 2)
                    s.btn:Show()
                    ns.SegSelect(s.btn, s.page.key == current)
                    y = y - SUB_STEP
                else
                    s.btn:Hide()
                end
            end
            if open and e.subs and #e.subs > 0 then y = y - 4 end
        end
    end
    layoutNav()

    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverMain") end
    f:Hide()
    return f
end

function ns.ToggleMain(key)
    if not frame then frame = build(); ns.ApplyUIScale() end
    if frame:IsShown() and (not key or key == current) then frame:Hide(); return end
    frame:Show()
    pcall(ensureStubs)   -- 10-18 公会 / 组队占位页签（模块没加载时）；先于子插件挂在 ToggleMain 后面的真页签，保证顺序
    showPage(key or (ns.db.ui and ns.db.ui.page) or (pages[1] and pages[1].key))
end

-- ---------- 小地图按钮 ----------
-- 10-16 用户「小地图的按钮设置下，方便用户点，你设计好」：
--   左键 = 开 / 关主面板；右键 = 快捷菜单（升级规划 / 专业 / 组队 / 副本组队 / 找训练师 / 公会招募 / 天赋 / 键位 / 隐藏按钮）；
--   按住拖 = 沿小地图边挪位置（拖完不算点击）；/gi 小地图 找回。菜单自绘（不用 EasyMenu / UIDropDownMenu，《无限》客户端没验过）
-- 11-06 玩家反馈「小地图上的图标点不开」（装了收纳插件）→ 用户「无限的小地图按钮好好修复下」：
--   ① 位置照时光服 MinimapButton.lua / LibDBIcon：半径跟小地图实际大小走、方形小地图钳到矩形边（原来写死半径 80，新版大地图上按钮缩在地图里面）；
--   ② 被收纳插件（SexyMap / ElvUI / MBB 之类）接管后不再自己摆回去（钩自己的 SetPoint 判断），玩家亲手拖例外；
--   ③ 别的插件带了 LibDataBroker / LibDBIcon 就同时注册：信息条 / 收纳插件按标准方式收我们，LibDBIcon 在就由它出按钮、我们自己的藏起来；
--   ④ 小地图上的「插件」总按钮（AddonCompartment，toc 里登记）也能点开，收纳插件再怎么藏都有入口。
local SHAPES = {
    ["ROUND"] = { true, true, true, true }, ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function placeButton(b)
    if rawget(b, "takenOver") and not rawget(b, "dragging") then return end
    local a = math.rad(tonumber(ns.db.minimap.angle) or 210)
    local x, y = math.cos(a), math.sin(a)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = "ROUND"
    if GetMinimapShape then
        local ok, s = pcall(GetMinimapShape)
        if ok and type(s) == "string" then shape = s end
    end
    local w = (tonumber(Minimap:GetWidth()) or 140) / 2 + 5
    local h = (tonumber(Minimap:GetHeight()) or 140) / 2 + 5
    if (SHAPES[shape] or SHAPES.ROUND)[q] then
        x, y = x * w, y * h
    else
        local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    b.selfPlacing = true
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
    b.selfPlacing = nil
end

local function hasPage(key)
    for _, p in ipairs(pages) do if p.key == key then return true end end
    return false
end

-- 主面板开着、停在这一页：不要被 ToggleMain(key) 关掉
local function openPage(key)
    if frame and frame:IsShown() and current == key then return end
    ns.ToggleMain(key)
end

local function openGuild()
    if not (frame and frame:IsShown()) then ns.ToggleMain() end
    if not ns.OpenModule("guild") then return end   -- 10-18 公会模块按需加载
    if ns.db and ns.db.ui then ns.db.ui.guildSub = "recruit" end
    local host = _G.GearInsightForeverMain
    local tab = host and rawget(host, "_giGuildTab")
    local click = tab and tab.GetScript and tab:GetScript("OnClick")
    if click then
        local d = rawget(tab, "_drawer")
        if not (d and d:IsShown()) then click(tab) end
    end
end

-- 菜单项：入口不在（HOLD 没装）就不出
function ns.MinimapMenuItems()
    local L = ns.L
    local items = {}
    local function add(text, fn) items[#items + 1] = { text = text, fn = fn } end
    if hasPage("plan") then add(L("升级规划", "Leveling plan"), function() openPage("plan") end) end
    if hasPage("prof") then add(L("专业", "Professions"), function() openPage("prof") end) end
    -- 10-18 组队模块按需加载：没加载 = 子插件在就出（点了再加载）；已加载 = 要有打开抽屉的入口才出
    if (ns.ModuleLoaded("group") and ns.OpenGroupDrawer) or (not ns.ModuleLoaded("group") and ns.ModuleAvailable("group")) then
        local function og(m) return function() if ns.LoadModule("group") and ns.OpenGroupDrawer then ns.OpenGroupDrawer(m) end end end
        add(L("组队 · 附近任务", "Group up - nearby quests"), og("quest"))
        -- 10-19 用户「副本组队暂时标记为测试状态，不对外放出，只有我自己能看到」：PageGroup / GroupLFG 回 HOLD（发行包里没有），
        --   菜单只在模块真加载出副本组队（= 开发安装）时才出，没加载前不再预先挂这一项
        if ns.BuildGroupPanel then add(L("副本组队 · 测试", "Dungeon group finder (test)"), og("dungeon")) end
    end
    if ns.Trainers and ns.Trainers.Go then add(L("找最近的职业训练师", "Nearest class trainer"), function() ns.Trainers.Go() end) end
    local W = ns.W or _G.GIWidgets
    if W and W.AttachGuildTab and ns.ModuleAvailable("guild") then add(L("公会招募", "Guild recruitment"), openGuild) end
    if hasPage("talent") then add(L("天赋", "Talents"), function() openPage("talent") end) end
    if hasPage("keys") then add(L("键位", "Keys"), function() openPage("keys") end) end
    if hasPage("data") then add(L("设置", "Settings"), function() openPage("data") end) end
    items[#items + 1] = { sep = true }
    add("|cffaaaaaa" .. L("隐藏小地图按钮", "Hide minimap button") .. "|r", function()
        ns.SetMinimapShown(false)
        ns.Print(L("小地图按钮已隐藏：输入 /gi 小地图 找回", "Minimap button hidden: type /gi minimap to bring it back"))
    end)
    return items
end

local mmMenu
local function showMenu(anchor)
    if not mmMenu then
        mmMenu = CreateFrame("Frame", "GearInsightForeverMinimapMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        mmMenu:SetFrameStrata("FULLSCREEN_DIALOG"); mmMenu:SetClampedToScreen(true); mmMenu:EnableMouse(true)
        if mmMenu.SetBackdrop then
            mmMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            mmMenu:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
        end
        mmMenu.t = mmMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); mmMenu.t:SetPoint("TOPLEFT", 10, -8)
        mmMenu.t:SetText("GearInsight " .. ns.L("无限版", "Forever"))
        mmMenu.rows = {}
        -- 鼠标离开菜单和按钮 2 秒自动收起
        mmMenu:SetScript("OnUpdate", function(self, el)
            local an = rawget(self, "anchor")
            if self:IsMouseOver() or (an and an:IsMouseOver()) then self.idle = 0; return end
            self.idle = (self.idle or 0) + (el or 0)
            if self.idle > 2 then self:Hide() end
        end)
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverMinimapMenu") end
    end
    mmMenu.anchor = anchor
    local items = ns.MinimapMenuItems()
    for _, r in ipairs(mmMenu.rows) do r:Hide() end
    local y = -24
    for i, it in ipairs(items) do
        local r = mmMenu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, mmMenu)
            r:SetSize(170, 20)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.t:SetPoint("LEFT", 8, 0); r.t:SetJustifyH("LEFT")
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.14)
            r.line = r:CreateTexture(nil, "ARTWORK"); r.line:SetHeight(1)
            r.line:SetPoint("LEFT", 6, 0); r.line:SetPoint("RIGHT", -6, 0); r.line:SetColorTexture(1, 1, 1, 0.15)
            mmMenu.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 6, y)
        if it.sep then
            r:SetHeight(8); r.t:SetText(""); r.line:Show(); r.hl:Hide(); r:EnableMouse(false); r:SetScript("OnClick", nil)
            y = y - 8
        else
            r:SetHeight(20); r.t:SetText(it.text); r.line:Hide(); r.hl:Show(); r:EnableMouse(true)
            r:SetScript("OnClick", function() mmMenu:Hide(); pcall(it.fn) end)
            y = y - 20
        end
        r.item = it
        r:Show()
    end
    mmMenu:SetSize(182, -y + 8)
    mmMenu:ClearAllPoints()
    -- 按钮在屏幕右半边：菜单往左开；下半边：往上开
    local cx, cy = anchor:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local right = (tonumber(cx) or 0) > (tonumber(sw) or 0) / 2
    local low = (tonumber(cy) or 0) < (tonumber(sh) or 0) / 2
    mmMenu:SetPoint((low and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT"), anchor,
        (low and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT"), 0, 0)
    mmMenu.idle = 0
    mmMenu:Show()
    ns.MinimapMenu = mmMenu   -- 测试用
end

-- 左键 = 开关主面板；右键 = 快捷菜单（小地图按钮 / LibDBIcon 按钮 / 信息条 / 插件总按钮共用）
local function clickButton(anchor, btn)
    GameTooltip:Hide()
    if btn == "RightButton" then
        if mmMenu and mmMenu:IsShown() then mmMenu:Hide() else showMenu(anchor) end
    else
        if mmMenu then mmMenu:Hide() end
        ns.ToggleMain()
    end
end

local function fillTooltip(tt)
    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GearInsight_Forever", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("GearInsight_Forever", "Version")) or ""
    tt:AddLine("|cff33ff99GearInsight|r " .. ns.L("无限版", "Forever") .. " " .. tostring(ver or ""))
    tt:AddLine(ns.L("左键：打开 / 关闭主面板", "Left-click: open / close"), 1, 1, 1)
    tt:AddLine(ns.L("右键：快捷菜单（升级规划、组队、训练师等）", "Right-click: quick menu"), 1, 1, 1)
    tt:AddLine(ns.L("按住拖动：沿小地图边挪位置", "Drag: move around the minimap"), 0.7, 0.7, 0.7)
    -- 状态：还有没点的天赋点
    local pts = ns.UnspentTalentPoints and ns.UnspentTalentPoints() or 0
    if type(pts) == "number" and pts > 0 then
        tt:AddLine(string.format(ns.L("有 %d 个天赋点没点（升级规划里点「去点」）", "%d unspent talent point(s)"), pts), 0.2, 1, 0.6)
    end
end

-- 别的插件带了 LibDataBroker（信息条 / 收纳插件都认它）→ 注册启动器；再有 LibDBIcon → 由它出小地图按钮，我们自己的藏起来
--   我们不内嵌这些库：没有就只用自己的按钮。LibDBIcon 用 ns.db.minimap 存 hide / minimapPos（和我们的 hide 同一个键）
local function registerBroker(b)
    local LS = _G.LibStub
    local LDB = LS and LS("LibDataBroker-1.1", true)
    if not LDB then return end
    local ok, obj = pcall(LDB.NewDataObject, LDB, "GearInsight_Forever", {
        type = "launcher", label = "GearInsight " .. ns.L("无限版", "Forever"),
        icon = "Interface\\AddOns\\GearInsight_Forever\\media\\logo",
        OnClick = function(frame, btn) clickButton(frame or b, btn) end,
        OnTooltipShow = function(tt) if tt and tt.AddLine then fillTooltip(tt) end end,
    })
    if not (ok and obj) then return end
    ns.Broker = obj
    local DBI = LS("LibDBIcon-1.0", true)
    if DBI and DBI.Register then
        local db = ns.db.minimap
        if db.minimapPos == nil then db.minimapPos = tonumber(db.angle) or 210 end
        if pcall(DBI.Register, DBI, "GearInsight_Forever", obj, db) then b.viaDBIcon = true end
    end
end

local function buildMinimap()
    if not Minimap then return end
    ns.db.minimap = ns.db.minimap or { angle = 210 }
    local b = CreateFrame("Button", "GearInsightForeverMinimap", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\GearInsight_Forever\\media\\logo")
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- 按下时图标往右下沉一点（点的手感）
    b:SetScript("OnMouseDown", function() icon:ClearAllPoints(); icon:SetPoint("CENTER", 1, 0) end)
    b:SetScript("OnMouseUp", function() icon:ClearAllPoints(); icon:SetPoint("CENTER", 0, 1) end)
    b:SetScript("OnClick", function(self, btn)
        -- 刚拖完松手不算点击
        local t = GetTime and GetTime() or 0
        local de = rawget(self, "dragEnd")
        if rawget(self, "dragging") or (de and t - de < 0.25) then return end
        clickButton(self, btn)
    end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        if mmMenu then mmMenu:Hide() end
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(py / s - my, px / s - mx))
            placeButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragging = nil
        self.dragEnd = GetTime and GetTime() or 0
    end)
    b:SetScript("OnEnter", function(self)
        if rawget(self, "dragging") then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        fillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 收纳插件挪了我们（不是自己摆的 SetPoint）→ 记成被接管，之后不再摆回小地图边；玩家亲手拖时照常摆
    hooksecurefunc(b, "SetPoint", function(self)
        if not rawget(self, "selfPlacing") and not rawget(self, "dragging") then self.takenOver = true end
    end)
    placeButton(b)
    -- 小地图改大小（新版小地图可调尺寸 / 换形状插件）后重新摆
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", function() placeButton(b) end) end
    ns.MinimapButton = b
    registerBroker(b)
    if ns.db.minimap.hide or rawget(b, "viaDBIcon") then b:Hide() end
end

function ns.SetMinimapShown(on)
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.hide = not on
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if ns.MinimapButton and rawget(ns.MinimapButton, "viaDBIcon") and DBI then
        if on then DBI:Show("GearInsight_Forever") else DBI:Hide("GearInsight_Forever") end
        return
    end
    if ns.MinimapButton then
        if on then ns.MinimapButton.takenOver = nil; placeButton(ns.MinimapButton) end   -- 找回 = 复位到小地图边
        ns.MinimapButton:SetShown(on)
    end
end

-- 小地图「插件」总按钮（toc ## AddonCompartmentFunc）：左键开关面板，右键快捷菜单
function GearInsightForever_OnAddonCompartmentClick(_, btn)
    local anchor = (ns.MinimapButton and ns.MinimapButton:IsVisible() and ns.MinimapButton) or AddonCompartmentFrame or Minimap
    clickButton(anchor, btn == "RightButton" and "RightButton" or "LeftButton")
end
function GearInsightForever_OnAddonCompartmentEnter(_, frame)
    if not frame then return end
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    fillTooltip(GameTooltip)
    GameTooltip:Show()
end
function GearInsightForever_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- /gi 小地图（/gi minimap）：显示 / 隐藏小地图按钮
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["小地图"] = function()
    local on = (ns.db.minimap or {}).hide and true or false
    ns.SetMinimapShown(on)
    ns.Print(on and ns.L("小地图按钮已显示", "Minimap button shown")
        or ns.L("小地图按钮已隐藏：再输一次 /gi 小地图 找回", "Minimap button hidden: type /gi minimap again to show it"))
end
ns.ExtraSlash.minimap = ns.ExtraSlash["小地图"]

table.insert(ns.modules, function() pcall(buildMinimap) end)
