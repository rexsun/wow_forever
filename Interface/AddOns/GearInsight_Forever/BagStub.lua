-- 清背包 / 卖垃圾子插件（GearInsight_Forever_Bag）在主插件里的「占位」（11-17 用户「模块做好按需加载」）
--   清背包页（Trash.lua：扫描 / 排序 / 摧毁 / 大列表）和卖垃圾面板（SellJunk.lua：面板 / 卖出逻辑）登录不加载，第一次用到才 LoadAddOn：
--     · 点「装备 → 清背包」页签 / 背包上的「清背包」按钮 / /gi 摧毁 | trash
--     · 背包上的「卖垃圾」按钮 / /gi 卖 | sell | 卖垃圾
--     · 打开商人窗口且「打开商人时显示卖垃圾面板」或「自动卖灰」开着（默认面板开 → 第一次开商人时加载）
--     · 背包满了且「背包满时提示」开着（提示里要写当前最便宜的那件，要用扫描）
--   留在主插件（这里，都很轻）：
--     · 三组设置（清背包 / 卖垃圾 / 背包按钮在 BagButtons.lua）的描述 + 存档读写：设置页索引 / 搜索 / 「本页设置」不用加载子插件就能显示和改
--     · 背包空格计数（背包满提示的判断）、商人窗口开没开（背包按钮「卖垃圾」显不显示要用）
--     · 物品鼠标提示上的「拍卖比商店 ±N%」一行（11-16 加的，所有物品提示都有，不能等开过商人才出现）
--   和组队界面 / 法师吃喝一样：两种包（合并 / 拆分）里都是独立文件夹；网易DD 包并进主文件夹（DD_FOLD）→ 登录全加载，这里不放占位
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local M = ns.LazyModule and ns.LazyModule({ key = "bag", addon = "GearInsight_Forever_Bag", zh = "清背包", en = "Bag cleanup",
    what = "清背包 / 卖垃圾", whatEn = "Bag cleanup / Sell junk" }) or nil
ns._BagMod = M   -- 测试用

local function loaded(name) return rawget(ns, name) end
local function after(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
ns._After = after   -- 11-20 BagButtons 共用
local call = ns._Call   -- MageConjure.lua

-- 加载子插件（合并 / DD 包里文件已经在了 → ModLoad 认就绪标记直接返回真）
function ns.BagLoad(quiet)
    if loaded("Trash") and loaded("SellJunk") then return true end
    if not M then return false end
    return M:Load(nil, quiet ~= false) and true or false
end
-- 这一块功能在不在（子插件文件夹在 + 文件进了包；或者已经加载了）
function ns.BagHas(file)
    if file == "Trash.lua" and loaded("Trash") then return true end
    if file == "SellJunk.lua" and loaded("SellJunk") then return true end
    if not M then return false end
    return M:Active(file) and true or false
end

-- ---------- 占位：页 / 命令 / 外壳 ----------
if M then
    -- ⛔ 页名 / 顺序 / 图标要和 Trash.lua 里真页的 ns.RegisterPage 一模一样
    M:Page({ key = "trash", order = 3.1, title = L("清背包", "Bag cleanup"), tabTitle = L("清背包", "Cleanup"),
        icon = "Interface\\Icons\\INV_Misc_Bag_07", file = "Trash.lua" })
    M:Slash({ "摧毁", "trash" }, "Trash.lua")
    M:Slash({ "卖", "sell", "卖垃圾" }, "SellJunk.lua")
    M:Shell("SellJunkOpen", { file = "SellJunk.lua" })   -- 背包上的「卖垃圾」按钮
    M:Shell("TrashFullTip", { file = "Trash.lua" })      -- 背包满提示（要扫背包找最便宜的那件）
    M:Shell("SellJunkMerchant", { file = "SellJunk.lua" })   -- 开商人：弹面板 / 自动卖灰
end

-- ---------- 设置读写（存档键和拆分前一样：ns.db.trash / ns.db.sellJunk；nil = 默认值）----------
local function cfg(dbKey, defaults, onSet)
    local C = { DEFAULTS = defaults }
    function C.DB()
        ns.db[dbKey] = ns.db[dbKey] or {}
        return ns.db[dbKey]
    end
    function C.Opt(k)
        if not ns.db then return defaults[k] end
        local v = rawget(C.DB(), k)
        if v == nil then return defaults[k] end
        return v
    end
    function C.SetOpt(k, v)
        if not ns.db then return end
        v = v and true or false
        if v == defaults[k] then C.DB()[k] = nil else C.DB()[k] = v end
        if onSet then pcall(onSet, k, v) end
    end
    return C
end

ns.TrashCfg = cfg("trash", { fullTip = true, epic = false, skipConj = true }, function()
    local T = loaded("Trash")
    if T and T.PageShown and T.PageShown() then T.Refresh() end
end)
do
    local C = ns.TrashCfg
    local _db = C.DB
    function C.DB()
        local d = _db()
        if type(d.keep) ~= "table" then d.keep = {} end
        return d
    end
    function C.KeepCount()
        if not ns.db then return 0 end
        local n = 0
        for _ in pairs(C.DB().keep) do n = n + 1 end
        return n
    end
    function C.ClearKeep()
        if not ns.db then return 0 end
        local n = C.KeepCount()
        C.DB().keep = {}
        local T = loaded("Trash")
        if T and T.PageShown and T.PageShown() then T.Refresh() end
        return n
    end
end

-- 11-24 GI-349「装备和材料都提示拍卖比卖店贵多少，想把这个提示关掉」：ahTip = 物品鼠标提示里那行「拍卖比商店 ±N%」（nil = 开，false = 关）
ns.SellCfg = cfg("sellJunk", { panel = true, auto = false, white = false, sort = "value", ahTip = true }, function(k, v)
    local S = loaded("SellJunk")
    if not S then return end
    if k == "panel" and not v and S.Hide then S.Hide() end
    if S.PanelShown and S.PanelShown() then S.Refresh() end
end)

-- ---------- 商人窗口开没开（背包按钮 / 卖垃圾面板都认这个）----------
local merchant = false
function ns.BagAtMerchant()
    if not merchant then return false end
    local mf = rawget(_G, "MerchantFrame")
    if type(mf) == "table" and type(mf.IsShown) == "function" then
        local ok, v = pcall(mf.IsShown, mf)
        return ok and v and true or false
    end
    return true
end

-- ---------- 背包满提示（只数空格；满了才加载子插件写最便宜的那件）----------
local full = { tipped = false, ready = false }
ns._BagFull = full   -- 测试用
function ns.BagFreeSlots()
    local C = rawget(_G, "C_Container")
    local numSlots = (type(C) == "table" and C.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    local numFree = (type(C) == "table" and C.GetContainerNumFreeSlots) or rawget(_G, "GetContainerNumFreeSlots")
    local free, total = 0, 0
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local n = tonumber(call(numSlots, bag)) or 0
        if n > 0 then
            local nf, fam = call(numFree, bag)
            if (tonumber(fam) or 0) == 0 then
                total = total + n
                free = free + (tonumber(nf) or 0)
            end
        end
    end
    return free, total
end
function ns.BagCheckFull()
    if full.tipped or not full.ready or not ns.db or not ns.TrashCfg.Opt("fullTip") then return false end
    if not ns.BagHas("Trash.lua") then return false end
    local free, total = ns.BagFreeSlots()
    if total == 0 or free > 0 then return false end
    full.tipped = true
    local f = ns.TrashFullTip
    if not (type(f) == "function" and f()) then
        ns.Print(L("背包满了：/gi 摧毁 打开「装备 → 清背包」，按价值从低到高一键摧毁", "Bags full: /gi trash opens Gear > Bag cleanup, cheapest first, one click to destroy")
            .. L("。每次登录最多提示一次，/gi 摧毁 提示关", ". Once per login; /gi trash tipoff"))
    end
    return true
end

-- ---------- 物品提示上的「拍卖比商店」（11-16；拍卖价读 Auctionator，没装 / 没扫过 = 不标）----------
--   拍卖比商店 = (拍卖单价 - 商人收购价) / 商人收购价；拍卖到手按扣 5% 手续费算：到手 ≤ 商人价 × 1.1 → 「值得卖商店」
--   拾取绑定 / 任务物品（上不了拍卖）也算「值得卖商店」。卖垃圾面板（SellJunk.lua）的小标 / 拍卖比排序也用这一份
local A = { AH_CUT = 0.95, VENDOR_OK = 1.1 }
ns.SellAH = A
function A.AHPrice(id)
    local Au = rawget(_G, "Auctionator")
    local api = type(Au) == "table" and Au.API and Au.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, p = pcall(api.GetAuctionPriceByItemID, "GearInsight", id)
        p = ok and tonumber(p) or nil
        if p and p > 0 then return p end
    end
    return nil
end
function A.VendorPrice(id)
    local r = { pcall(GetItemInfo, id) }
    if not r[1] then return nil end
    return tonumber(r[12]), r[15]   -- 商人收购价（单个）, 绑定类型
end
-- 返回 { pct = 拍卖比商店 %, ah, vendor, shop = 值得卖商店 }；没数据 = nil
function A.Compare(id)
    if not id then return nil end
    local v, bind = A.VendorPrice(id)
    if not (v and v > 0) then return nil end
    if bind == 1 or bind == 4 then return { vendor = v, shop = true, bop = true } end
    local a = A.AHPrice(id)
    if not a then return nil end
    local pct = math.floor((a - v) / v * 100 + 0.5)
    return { pct = pct, ah = a, vendor = v, shop = a * A.AH_CUT <= v * A.VENDOR_OK }
end
function A.Tag(id)
    local c = A.Compare(id)
    if not c then return "" end
    if c.shop then return "|cff33ff99" .. L("卖商店", "Vendor") .. "|r" end
    return "|cffffa040" .. string.format(L("拍+%d%%", "AH+%d%%"), c.pct) .. "|r"
end
function A.TipLine(id)
    local c = A.Compare(id)
    if not c then return nil end
    if c.bop then return "|cff33ff99GI|r " .. L("拾取绑定上不了拍卖：值得卖商店", "Soulbound - sell it to a vendor") end
    local sign = c.pct >= 0 and "+" or ""
    local head = "|cff33ff99GI|r " .. string.format(L("拍卖比商店 %s%d%%", "AH vs vendor %s%d%%"), sign, c.pct)
    if c.shop then return head .. L("（扣掉拍卖手续费不划算：值得卖商店）", " (not worth the AH cut - vendor it)") end
    return head .. L("（拿去拍卖更值）", " (worth more on the AH)")
end
local tipHooked
function A.HookTooltip()
    if tipHooked or not ns.BagHas("SellJunk.lua") then return end
    tipHooked = true
    local function add(tt, id)
        if not id or tt.__gifAH == id or not ns.SellCfg.Opt("ahTip") then return end
        local ln = A.TipLine(id)
        if not ln then return end
        tt.__gifAH = id
        tt:AddLine(ln, 1, 0.82, 0.4, true)
        tt:Show()
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, d)
            local id = d and d.id
            if not id or (ns.Secret and ns.Secret(id)) then return end
            pcall(add, tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then tt:HookScript("OnTooltipCleared", function(self) self.__gifAH = nil end) end
    end
end
table.insert(ns.modules, function() pcall(A.HookTooltip) end)

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
ns._BagStubEv = ev   -- 测试用
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED" }) do
    pcall(ev.RegisterEvent, ev, e)   -- ⛔ 容错注册：客户端没有的事件名会报错
end
local dirtyAt
ev:SetScript("OnUpdate", function()
    if dirtyAt and ((GetTime and GetTime()) or 0) >= dirtyAt then dirtyAt = nil; pcall(ns.BagCheckFull) end
end)
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        after(5, function() full.ready = true; pcall(ns.BagCheckFull) end)   -- 登录后 5 秒才开始看背包满
    elseif e == "BAG_UPDATE" then
        if full.ready and not full.tipped then dirtyAt = ((GetTime and GetTime()) or 0) + 0.3 end
    elseif e == "BAG_UPDATE_DELAYED" then
        dirtyAt = nil
        pcall(ns.BagCheckFull)
    elseif e == "MERCHANT_SHOW" then
        merchant = true
        -- 卖垃圾面板（默认开）/ 自动卖灰开着才加载；都关着 = 不加载，背包上的「卖垃圾」按钮点了再加载
        if loaded("SellJunk") or ns.SellCfg.Opt("panel") or ns.SellCfg.Opt("auto") then
            if ns.BagHas("SellJunk.lua") and type(ns.SellJunkMerchant) == "function" then pcall(ns.SellJunkMerchant, true) end
        end
    elseif e == "MERCHANT_CLOSED" then
        merchant = false
        local S = loaded("SellJunk")
        if S and S.OnCloseMerchant then pcall(S.OnCloseMerchant) end
    end
end)
ns._BagStubEvent = ev:GetScript("OnEvent")   -- 测试用

-- ---------- 设置描述（索引 / 搜索 / 清背包页「本页设置」都画这一份；改了立刻生效，不用加载子插件）----------
if ns.RegisterSettings then
    local T = ns.TrashCfg
    ns.RegisterSettings({ key = "trash", order = 47, page = "trash", avail = function() return ns.BagHas("Trash.lua") end,
        title = function() return L("清背包（物品摧毁助手）", "Bag cleanup") end, short = function() return L("清背包", "Cleanup") end,
        items = {
            { type = "check", id = "trash.full", text = function() return L("背包满时在聊天框提示一次可以用「清背包」（每次登录最多一次）", "When bags are full, mention Bag cleanup in chat (once per login)") end,
              get = function() return T.Opt("fullTip") and true or false end, set = function(v) T.SetOpt("fullTip", v) end },
            { type = "check", id = "trash.epic", text = function() return L("列出紫色（史诗）及以上物品（默认不列）", "List epic and better items (off by default)") end,
              get = function() return T.Opt("epic") and true or false end, set = function(v) T.SetOpt("epic", v) end },
            { type = "check", id = "trash.conj", text = function() return L("不列出魔法造的食物和水（含法力宝石 / 治疗石 / 灵魂石）", "Hide conjured food / water (and mana gems / healthstones / soulstones)") end,
              get = function() return T.Opt("skipConj") and true or false end, set = function(v) T.SetOpt("skipConj", v) end },
            { type = "button", id = "trash.clear", w = 200, text = function() return string.format(L("清空不摧毁名单（%d 件）", "Clear keep list (%d)"), T.KeepCount()) end,
              click = function()
                  local n = T.ClearKeep()
                  ns.Print(string.format(L("不摧毁名单已清空（%d 件）", "Keep list cleared (%d)"), n))
                  if ns.RefreshSettings then ns.RefreshSettings() end
              end },
            { type = "note", text = function() return L("右键「清背包」页上的一行 = 加入不摧毁名单。任务物品、炉石、专业工具、灵魂碎片、施法材料、弹药永远不列出",
                "Right-click a row on the Bag cleanup page to keep that item. Quest items, hearthstone, tools, soul shards, reagents and ammo are never listed") end },
        } })
    local S = ns.SellCfg
    ns.RegisterSettings({ key = "selljunk", order = 47.5, page = "trash", avail = function() return ns.BagHas("SellJunk.lua") end,
        title = function() return L("卖垃圾（商人处）", "Sell junk (merchant)") end, short = function() return L("卖垃圾", "Sell junk") end,
        items = {
            { type = "check", id = "sell.panel", text = function() return L("打开商人时在商人窗口旁显示「卖垃圾」面板", "Show the Sell junk panel next to merchants") end,
              get = function() return S.Opt("panel") and true or false end, set = function(v) S.SetOpt("panel", v) end },
            { type = "check", id = "sell.auto", text = function() return L("打开商人时自动卖灰色物品（默认关；只卖灰色，购回页可买回）", "Auto-sell grey items at merchants (off by default; grey only, buy back to undo)") end,
              get = function() return S.Opt("auto") and true or false end, set = function(v) S.SetOpt("auto", v) end },
            { type = "check", id = "sell.ahtip", text = function() return L("物品鼠标提示里显示「拍卖比商店 +N%」（拍卖价读 Auctionator）", "Show \"AH vs vendor +N%\" in item tooltips (AH price from Auctionator)") end,
              get = function() return S.Opt("ahTip") and true or false end, set = function(v) S.SetOpt("ahTip", v) end },
            { type = "note", text = function() return L("面板按价值从低到高列出商人肯收钱的东西（不分品质），点一行卖一格，绿色以上点两下；任务物品、炉石、工具、施法材料、弹药、不摧毁名单里的永远不列。「一键卖」只卖灰色，每次最多 12 件（= 购回页格数）",
                "Lists everything merchants pay for, cheapest first; click a row to sell (green+ needs two clicks). Quest items, hearthstone, tools, reagents, ammo and the keep list are never listed. One-click sells grey only, up to 12 (= buyback slots)") end },
        } })
end

-- 命令占位之外：子插件没装（或者包里没有这两个文件）时 /gi 摧毁 提示开 | 提示关 照样能改开关
ns.ExtraSlash = ns.ExtraSlash or {}
if rawget(ns.ExtraSlash, "摧毁") == nil then
    ns.ExtraSlash["摧毁"] = function(rest, rawRest)
        local r = (rawRest or ""):gsub("[ \t]+", "")
        local low = (rest or ""):gsub("[ \t]+", "")
        if r == "提示关" or low == "tipoff" then ns.TrashCfg.SetOpt("fullTip", false); ns.Print(L("背包满提示：关", "Full-bag tip: off"))
        elseif r == "提示开" or low == "tipon" then ns.TrashCfg.SetOpt("fullTip", true); ns.Print(L("背包满提示：开", "Full-bag tip: on"))
        else ns.Print(L("清背包模块没装上：请重新安装插件（把压缩包里的文件夹全部放进 AddOns）", "Bag cleanup isn't installed: reinstall the addon (copy every folder from the zip into AddOns)")) end
    end
    ns.ExtraSlash.trash = ns.ExtraSlash["摧毁"]
end

-- 11-17 用户「这些弹出的功能都确保能永久关闭」：按需加载的子插件里会自己弹出来的东西，关掉后这个子插件登录时可能就不加载了，
--   真模块的「窗口与提醒」条目也就没了 → 这里放同 key 的占位：读存档显示状态，点「打开」写回存档再加载子插件（真模块加载后用同一个 key 顶替）
if M and ns.SellCfg then
    M:Window({ key = "sellJunk", order = 70, title = function() return L("卖垃圾面板（开商人时）", "Sell junk panel (at merchants)") end,
        state = function() return ns.SellCfg.Opt("panel") and L("开商人时出在旁边", "Shows next to merchants") or L("已关闭（/gi 卖 仍能打开）", "Closed (/gi sell still opens it)") end,
        actions = function()
            local on = ns.SellCfg.Opt("panel") and true or false
            return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() ns.SellCfg.SetOpt("panel", not on) end } }
        end }, "SellJunk.lua")
end
