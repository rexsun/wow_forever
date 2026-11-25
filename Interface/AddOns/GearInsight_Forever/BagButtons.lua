-- 背包窗口上的「清背包」/「卖垃圾」按钮（11-15 用户截图 EllesmereUI 背包「摧毁助手放到这里」「摧毁+卖助手都可以在这里点」）
--   11-17 用户截图（EUI 整合背包顶栏「锤子、银色圆、金币、橙色圆、锤子」）「摧毁助手咋整」→「附着一个按钮在这里，然后可以不再显示，设置可以重新打开配置」：
--     查实 11-15 那版其实挂上了（顶栏最左边的锤子 + 不在商人处变灰的金币 = 「银色圆」），但是 22 像素的圆图标跟 EUI 自己的锤子（整理）/ 金币（垃圾标记）
--     长得一模一样，认不出是我们的 → 改成带字的小牌子：「[背包图标] 清背包」，GearInsight 绿边绿字；「卖垃圾」只在商人窗口开着时出现（平时点了也只能提示去找商人）
--   ① 左键「清背包」= 打开 / 关闭「装备 → 清背包」页（ns.ToggleMain("trash")，页面在按需加载的子插件 GearInsight_Forever_Bag，第一次点才加载）
--      左键「卖垃圾」= 弹商人旁的卖垃圾面板（ns.SellJunkOpen，同样第一次点才加载）
--      右键任意一个 = 小菜单：打开清背包 / 卖垃圾 / 设置… / 不再显示这个按钮
--      「不再显示」→ 存 ns.db.bagButtons.show = false，所有背包上的这两个按钮都收起，聊天框说一句去哪重新打开
--   ② 认哪些背包框体（按顺序，框体名查不到就跳过、不报错；后建的框体靠 ToggleAllBags 等的 hooksecurefunc + 每 2 秒补扫一次认上）：
--        EllesmereUI 整合背包 EUI_MainBagFrame：放在它顶栏那排圆图标（整理 / 显示背包 / 快捷操作 / 垃圾…）的最左边再往左，
--          锚 EUI_Bags._hdrEdge（它自己算的「最左边那个图标」，只读）；标题「物品栏 59/60 格」的字放不下（窄背包）→ 改放到背包窗口外面右上角
--        暴雪整合背包 ContainerFrameCombinedBags / 分开背包的行囊 ContainerFrame1 / Baganator / Bagnon / AdiBags / ArkInventory：
--          竖着贴在框体外面的左边（顶边往下 40，躲开头像圈），不碰它们自己的标题栏和按钮
--        EUI 把暴雪背包挂到隐藏框体下面 → 挂在暴雪背包上的那对按钮自然看不见，不会两处同时出
--   ③ 挂法：按钮是我们自己 CreateFrame 的普通 Button，父 = 那个背包框体（跟着它显示 / 隐藏 / 缩放 / 层级），只 SetPoint 锚过去；
--        ⛔ 不改别人框体的脚本 / 布局：只 HookScript("OnShow") 重新摆位置；⛔ 战斗中不 SetPoint / 不新挂（暴雪背包战斗中是受保护的），
--        记下来脱战（PLAYER_REGEN_ENABLED）再摆；战斗中照样能显示 / 点（显示是跟着父框体走的）
--   ④ 设置「背包上显示清背包 / 卖垃圾按钮」默认开，存 ns.db.bagButtons.show（nil = 开）：画在两处 ——
--        「设置 → 通用」（找得到的固定位置，「不再显示」后让玩家去这里找回）和「清背包」页的「本页设置」；设置页索引两处都能搜到「背包」
--        命令 /gi 背包按钮 开 | 关
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local BB = { sets = {}, byHost = {} }
ns.BagButtons = BB
BB.H = 20
BB.GAP = 6
BB.SCAN_SEC = 2
BB.DEFAULTS = { show = true }
BB.ICON_TRASH = "Interface\\Icons\\INV_Misc_Bag_07"   -- 和「清背包」页签同一个图标
BB.ICON_SELL = "Interface\\Icons\\INV_Misc_Coin_01"
BB.GREEN = { 0.2, 1, 0.6 }

local combat = ns._InCombat   -- ModStub.lua
local after = ns._After   -- BagStub.lua
local function rg(t, k) return type(t) == "table" and rawget(t, k) or nil end
local function num(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end
local function isFrame(f) return type(f) == "table" and type(f.HookScript) == "function" and type(f.IsShown) == "function" end
local function call(obj, m, ...)
    local fn = obj and obj[m]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if ok then return a, b end
    return nil
end

-- ---------- 设置（ns.db.bagButtons；nil = 默认值）----------
function BB.DB()
    ns.db.bagButtons = ns.db.bagButtons or {}
    return ns.db.bagButtons
end
function BB.Opt(k)
    if not ns.db then return BB.DEFAULTS[k] end
    local v = rawget(BB.DB(), k)
    if v == nil then return BB.DEFAULTS[k] end
    return v
end
function BB.SetOpt(k, v)
    if not ns.db then return end
    v = v and true or false
    if v == BB.DEFAULTS[k] then BB.DB()[k] = nil else BB.DB()[k] = v end
    if v and k == "show" then BB.Scan() end
    BB.ApplyAll()
    if ns.RefreshSettings then pcall(ns.RefreshSettings) end
end
-- 去哪重新打开（聊天框 / 菜单 / 测试共用一句）
function BB.WhereText()
    return L("设置 → 通用 →「背包上显示清背包 / 卖垃圾按钮」打勾（清背包页的「本页设置」里也有），或输入 /gi 背包按钮 开",
        "Settings → General → tick \"Show Bag cleanup / Sell junk buttons on the bag window\" (also in the Bag cleanup page settings), or type /gi bagbuttons on")
end
-- 右键菜单「不再显示这个按钮」
function BB.HideForever()
    BB.SetOpt("show", false)
    ns.Print(L("已隐藏背包上的 GearInsight「清背包」按钮。要找回：", "Hid the GearInsight Bag cleanup button on your bags. To bring it back: ") .. BB.WhereText())
end

-- ---------- 有没有这两块功能（子插件文件夹在 / 已加载；BagStub.lua）----------
function BB.HasTrash() return ns.BagHas ~= nil and ns.BagHas("Trash.lua") or false end
function BB.HasSell() return ns.BagHas ~= nil and ns.BagHas("SellJunk.lua") or false end
function BB.AtMerchant() return ns.BagAtMerchant ~= nil and ns.BagAtMerchant() or false end

-- ---------- 点了做什么 ----------
function BB.ClickTrash()
    if combat() then
        ns.Print(L("战斗中不能清背包，脱战后再点", "Not in combat - try again after the fight"))
        return false
    end
    if ns.ToggleMain then ns.ToggleMain("trash") end   -- 清背包页在子插件里：占位页第一次打开时加载
    return true
end
function BB.ClickSell()
    local f = ns.SellJunkOpen
    local ok = type(f) == "function" and f() or false   -- 商人开着 → 弹面板；没开 → 它自己在聊天框提示去找商人
    if not ok then
        local ef = rawget(_G, "UIErrorsFrame")
        if ef and type(ef.AddMessage) == "function" then
            pcall(ef.AddMessage, ef, L("卖垃圾：先跟商人对话", "Sell junk: talk to a merchant first"), 1, 0.82, 0)
        end
    end
    return ok and true or false
end
function BB.OpenSettings()
    if ns.JumpToSetting and ns.JumpToSetting("bagbtn.gen") then return true end
    if ns.OpenSettingsSub then return ns.OpenSettingsSub("general") end
    return false
end
function BB.MenuItems()
    local items = {}
    if BB.HasTrash() then items[#items + 1] = { text = L("打开清背包（按价值从低到高摧毁）", "Open Bag cleanup"), fn = BB.ClickTrash } end
    if BB.HasSell() then items[#items + 1] = { text = L("卖垃圾（要在商人处）", "Sell junk (at a merchant)"), fn = BB.ClickSell } end
    items[#items + 1] = { text = L("设置…", "Settings…"), fn = BB.OpenSettings }
    items[#items + 1] = { text = "|cffff8060" .. L("不再显示这个按钮", "Don't show this button") .. "|r", fn = BB.HideForever }
    return items
end
function BB.ShowMenu(anchor)
    if GameTooltip then GameTooltip:Hide() end
    if not ns.PopMenu then BB.HideForever(); return nil end
    return ns.PopMenu(anchor, "|cff33ff99GearInsight|r " .. L("清背包", "Bag cleanup"), BB.MenuItems())
end

-- ---------- 按钮（带字的小牌子：[图标] 清背包，GearInsight 绿边绿字，和 EUI 自己的圆图标一眼分得开）----------
local function tip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if rg(self, "kind") == "trash" then
        GameTooltip:SetText("GearInsight · " .. L("清背包（摧毁助手）", "Bag cleanup"), 0.2, 1, 0.6)
        GameTooltip:AddLine(L("按价值从低到高列出背包里的东西，一键摧毁最便宜的", "Lists your bag items cheapest first; destroy the cheapest in one click"), 1, 1, 1, true)
    else
        GameTooltip:SetText("GearInsight · " .. L("卖垃圾", "Sell junk"), 0.2, 1, 0.6)
        GameTooltip:AddLine(L("在商人那里点：列出可卖的东西（按价值从低到高，点一行卖一格，可一键卖灰色）",
            "Click at a merchant: lists what you can sell (cheapest first, click a row to sell, or sell all grey)"), 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(rg(self, "kind") == "trash" and L("左键：打开 / 关闭清背包（/gi 摧毁）", "Left-click: open / close Bag cleanup (/gi trash)")
        or L("左键：打开卖垃圾面板（/gi 卖）", "Left-click: open the Sell junk panel (/gi sell)"), 1, 0.82, 0, true)
    GameTooltip:AddLine(L("右键：菜单 · 设置 · 不再显示这个按钮", "Right-click: menu · settings · hide this button"), 1, 0.82, 0, true)
    GameTooltip:Show()
end
local function setHover(b, on)
    local c = BB.GREEN
    if rg(b, "brd") then call(b.brd, "SetColorTexture", c[1], c[2], c[3], on and 1 or 0.7) end
    if rg(b, "label") then
        if on then call(b.label, "SetTextColor", 0.75, 1, 0.85) else call(b.label, "SetTextColor", c[1], c[2], c[3]) end
    end
end

function BB.MakeButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b.kind = kind
    b:SetHeight(BB.H)
    b:Hide()
    local c = BB.GREEN
    b.brd = b:CreateTexture(nil, "BACKGROUND")   -- 1 像素绿边 = 外层绿色 + 里层黑底往里缩 1
    if b.brd then call(b.brd, "SetAllPoints"); call(b.brd, "SetColorTexture", c[1], c[2], c[3], 0.7) end
    b.bg = b:CreateTexture(nil, "BORDER")
    if b.bg then
        call(b.bg, "SetPoint", "TOPLEFT", 1, -1); call(b.bg, "SetPoint", "BOTTOMRIGHT", -1, 1)
        call(b.bg, "SetColorTexture", 0.03, 0.04, 0.05, 0.85)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    if b.icon then
        call(b.icon, "SetSize", BB.H - 6, BB.H - 6)
        call(b.icon, "SetPoint", "LEFT", 3, 0)
        call(b.icon, "SetTexture", kind == "trash" and BB.ICON_TRASH or BB.ICON_SELL)
        call(b.icon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if b.label then
        call(b.label, "SetPoint", "LEFT", BB.H - 1, 0)
        call(b.label, "SetText", kind == "trash" and L("清背包", "Cleanup") or L("卖垃圾", "Sell junk"))
        call(b.label, "SetTextColor", c[1], c[2], c[3])
        if b.label.SetWordWrap then call(b.label, "SetWordWrap", false) end
    end
    local w = num(b.label and call(b.label, "GetStringWidth"))
    if not w or w <= 0 then w = 40 end
    b:SetWidth(math.ceil(BB.H - 1 + w + 7))
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then BB.ShowMenu(self); return end
        if rg(self, "kind") == "trash" then BB.ClickTrash() else BB.ClickSell() end
    end)
    b:SetScript("OnEnter", function(self) setHover(self, true); tip(self) end)
    b:SetScript("OnLeave", function(self)
        setHover(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end
local function width(b) return num(b and call(b, "GetWidth")) or 60 end

-- ---------- 摆位置 ----------
-- EllesmereUI：顶栏图标排的最左边再往左（右起：EUI 图标 ← 清背包 ← 卖垃圾）；字放不下 → 窗口外面右上角
local function textRight(hdr)
    local title, count = rg(hdr, "title"), rg(hdr, "itemCount")
    local tl = title and num(call(title, "GetLeft"))
    if not tl then return nil end
    local w = num(call(title, "GetUnboundedStringWidth")) or num(call(title, "GetStringWidth")) or 0
    local r = tl + w
    local cw = count and (num(call(count, "GetUnboundedStringWidth")) or num(call(count, "GetStringWidth")))
    if cw and cw > 0 then r = r + 8 + cw end
    return r
end
-- 现在该显示几个（「卖垃圾」只在商人处）→ 量放不放得下用
function BB.NeedWidth(set)
    local w = 0
    if set.trash and BB.HasTrash() then w = w + width(set.trash) + BB.GAP end
    if set.sell and BB.HasSell() and BB.AtMerchant() then w = w + width(set.sell) + BB.GAP end
    return w
end
function BB.PlaceEUI(set)
    local host, t, s = set.host, set.trash, set.sell
    local hdr = rg(host, "Header")
    local edge = rg(host, "_hdrEdge") or rg(host, "_sortBtn") or rawget(_G, "EUI_BagSearchBox")
    local inside = hdr ~= nil and isFrame(edge)
    if inside then
        local el, tr = num(call(edge, "GetLeft")), textRight(hdr)
        if el and tr and el - BB.NeedWidth(set) - tr < 6 then inside = false end   -- 量得到且放不下（窄背包 / 名字长）
    end
    local first, second = t or s, t and s or nil
    if inside then
        first:SetPoint("RIGHT", edge, "LEFT", -BB.GAP, 0)
        local lv = num(call(hdr, "GetFrameLevel"))
        if lv then call(first, "SetFrameLevel", lv + 5); if second then call(second, "SetFrameLevel", lv + 5) end end
    else
        first:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", -4, 3)
    end
    if second then second:SetPoint("RIGHT", first, "LEFT", -BB.GAP, 0) end
    set.mode = inside and "header" or "above"
end
-- 暴雪 / 其它背包插件：竖着贴在框体外面左边
function BB.PlaceSide(set)
    local host, t, s = set.host, set.trash, set.sell
    local first, second = t or s, t and s or nil
    first:SetPoint("TOPRIGHT", host, "TOPLEFT", -2, -40)
    if second then second:SetPoint("TOPRIGHT", first, "BOTTOMRIGHT", 0, -4) end
    set.mode = "side"
end

local function baganatorNames()
    local out = {}
    for _, view in ipairs({ "Single", "Category" }) do
        for _, skin in ipairs({ "", "blizzard", "dark", "elvui", "gw2", "ndui" }) do
            out[#out + 1] = "Baganator_" .. view .. "ViewBackpackViewFrame" .. skin
        end
    end
    return out
end
BB.HOSTS = {
    { key = "eui", names = { "EUI_MainBagFrame" }, place = BB.PlaceEUI },
    { key = "blizzard_combined", names = { "ContainerFrameCombinedBags" }, place = BB.PlaceSide },
    { key = "blizzard", names = { "ContainerFrame1" }, place = BB.PlaceSide },
    { key = "baganator", names = baganatorNames(), place = BB.PlaceSide },
    { key = "bagnon", names = { "BagnonInventory1", "BagnonInventoryFrame1", "BagnonFrameinventory" }, place = BB.PlaceSide },
    { key = "adibags", names = { "AdiBagsContainer1" }, place = BB.PlaceSide },
    { key = "arkinventory", names = { "ARKINV_Frame1" }, place = BB.PlaceSide },
}

function BB.Place(set)
    if combat() then set.needPlace = true; return false end   -- ⛔ 战斗中不重新锚定，脱战再摆
    set.needPlace = false
    for _, b in ipairs({ set.trash, set.sell }) do if b then b:ClearAllPoints() end end
    local ok = pcall(set.def.place, set)
    set.placed = ok and true or set.placed
    BB.Apply(set)
    return ok
end
function BB.Apply(set)
    local on = BB.Opt("show") and set.placed and true or false
    if set.trash then set.trash:SetShown(on and BB.HasTrash()) end
    if set.sell then set.sell:SetShown(on and BB.HasSell() and BB.AtMerchant()) end   -- 「卖垃圾」只在商人窗口开着时出现
end
function BB.ApplyAll() for _, set in ipairs(BB.sets) do BB.Apply(set) end end
function BB.Visible(set)
    local h = set and set.host
    if not h then return false end
    if type(h.IsVisible) == "function" then local v = call(h, "IsVisible"); if v ~= nil then return v and true or false end end
    return h:IsShown() and true or false
end

function BB.Attach(host, def)
    if BB.byHost[host] then return BB.byHost[host] end
    if not (BB.HasTrash() or BB.HasSell()) then return nil end
    if combat() then BB.pending = true; return nil end   -- 战斗中不新挂
    local set = { host = host, def = def, key = def.key }
    set.trash = BB.HasTrash() and BB.MakeButton(host, "trash") or nil
    set.sell = BB.HasSell() and BB.MakeButton(host, "sell") or nil
    BB.byHost[host] = set
    BB.sets[#BB.sets + 1] = set
    pcall(host.HookScript, host, "OnShow", function() BB.OnHostShow(set) end)
    BB.Place(set)
    return set
end
function BB.OnHostShow(set)
    BB.Place(set)
    if set.def.key == "eui" then
        after(0.05, function() if BB.Visible(set) then BB.Place(set) end end)   -- 它的顶栏图标在 OnShow 后面才排好
    end
end

function BB.Scan()
    if not BB.Opt("show") then return 0 end
    if combat() then BB.pending = true; return 0 end
    local n = 0
    for _, def in ipairs(BB.HOSTS) do
        for _, name in ipairs(def.names) do
            local f = rawget(_G, name)
            if isFrame(f) and not BB.byHost[f] then
                if BB.Attach(f, def) then n = n + 1 end
            end
        end
    end
    return n
end
function BB.Replace(onlyKey)
    for _, set in ipairs(BB.sets) do
        if (not onlyKey or set.def.key == onlyKey) and (set.needPlace or BB.Visible(set)) then BB.Place(set) end
    end
end
function BB.Find(key)
    for _, set in ipairs(BB.sets) do if set.def.key == key then return set end end
    return nil
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
BB.ev = ev
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        BB.loggedIn = true
        pcall(BB.Scan)
        for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag" }) do
            if type(rawget(_G, fn)) == "function" and hooksecurefunc then
                pcall(hooksecurefunc, fn, function() after(0, function() pcall(BB.Scan) end) end)
            end
        end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if BB.pending then BB.pending = false; pcall(BB.Scan) end
        for _, set in ipairs(BB.sets) do if set.needPlace then pcall(BB.Place, set) end end
    elseif e == "MERCHANT_SHOW" or e == "MERCHANT_CLOSED" then
        BB.ApplyAll()
        after(0.1, function() pcall(BB.Replace, "eui"); BB.ApplyAll() end)   -- EUI 开商人时会多出「卖垃圾」图标 → 最左边变了；我们的「卖垃圾」也要出 / 收
    elseif e == "BAG_UPDATE_DELAYED" then
        pcall(BB.Replace, "eui")   -- 「59/60 格」字数变了 → 重新看放不放得下
    end
end)
local acc = 0
ev:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < BB.SCAN_SEC then return end
    acc = 0
    if BB.loggedIn and #BB.sets < #BB.HOSTS then pcall(BB.Scan) end   -- 背包插件的框体常常第一次开包才建
end)
BB._event = ev:GetScript("OnEvent")   -- 测试用
BB._update = ev:GetScript("OnUpdate")

-- ---------- 设置 / 命令 ----------
if ns.RegisterSettings then
    local function avail() return BB.HasTrash() or BB.HasSell() end
    local function txt() return L("背包上显示「清背包」/「卖垃圾」按钮（右键按钮可选「不再显示」）", "Show Bag cleanup / Sell junk buttons on the bag window (right-click a button to hide it)") end
    -- 「设置 → 通用」：固定位置，「不再显示」以后让玩家来这里找回
    ns.RegisterSettings({ key = "bagbuttons_gen", order = 26, data = "general", avail = avail,
        title = function() return L("背包上的按钮（清背包 / 卖垃圾）", "Bag window buttons (cleanup / sell junk)") end, short = function() return L("背包按钮（通用）", "Bag buttons (general)") end,   -- 目录里两组名字不能重复（gi_forever_ui_refactor_p1_test）
        items = {
            { type = "check", id = "bagbtn.gen", text = txt,
              get = function() return BB.Opt("show") and true or false end, set = function(v) BB.SetOpt("show", v) end },
        } })
    -- 「清背包」页的「本页设置」
    ns.RegisterSettings({ key = "bagbuttons", order = 47.6, page = "trash", avail = avail,
        title = function() return L("背包上的按钮", "Bag window buttons") end, short = function() return L("背包按钮", "Bag buttons") end,
        items = {
            { type = "check", id = "bagbtn.show", text = txt,
              get = function() return BB.Opt("show") and true or false end, set = function(v) BB.SetOpt("show", v) end },
            { type = "note", text = function() return L("支持 EllesmereUI 背包、暴雪自带背包、Baganator / Bagnon / AdiBags / ArkInventory；认不出的背包不挂，照样可以用 /gi 摧毁、/gi 卖。「卖垃圾」只在商人窗口开着时出现",
                "Works with EllesmereUI, Blizzard bags, Baganator / Bagnon / AdiBags / ArkInventory; otherwise use /gi trash and /gi sell. Sell junk only shows while a merchant is open") end },
        } })
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["背包按钮"] = function(rest, rawRest)
    local r = (rawRest or ""):gsub("[ \t]+", "")
    local low = (rest or ""):gsub("[ \t]+", "")
    if r == "关" or low == "off" then
        BB.SetOpt("show", false)
        ns.Print(L("背包上的清背包 / 卖垃圾按钮：关（/gi 背包按钮 开 恢复）", "Bag buttons: off (/gi bagbuttons on)"))
    else
        BB.SetOpt("show", true)
        ns.Print(L("背包上的清背包 / 卖垃圾按钮：开", "Bag buttons: on"))
    end
end
ns.ExtraSlash.bagbuttons = ns.ExtraSlash["背包按钮"]
