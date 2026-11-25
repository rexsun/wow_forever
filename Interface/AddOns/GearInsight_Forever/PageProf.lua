-- 「专业」页（v2，10-18，docs/forever-profession-v2-design.md 第四节）：选专业 / 我的时刻表 / 冲级路线 / 配方库 / 营地与传承
--   选专业只有一个目标：升级最快（10-18 用户拍板）；选好的专业写进 ns.db.prof.planned，升级规划按它出「去学初级」。
--   10-18 用户「这三个好像点了没区别」：去掉「不耽误升级 / 均衡 / 专业优先」三个策略按钮，目标只有升级最快（P.Strategy 固定 level）
--   我的时刻表：每个专业一条 1-60 级的轴，节点 = 路线上的训练和采集门槛（ProfPlan.lua P.Timeline），点节点跳到升级规划那一级。
--   配方库：ProfRecipes.lua（全部配方），按技能段 / 部位 / 《无限》新增 / 我能穿 / 搜索筛。
--   数据 ProfData.lua / ProfRecipes.lua；推导函数在 Prof.lua / ProfPlan.lua。⛔ 在 HOLD 里，没实测完不进发行包。
local _, ns = ...; ns = _G.GearInsightForever or ns

local page
local tab                   -- pick / time / route / recipes / camp；第一次打开见 refresh()：有专业（学了的或选了的）= 冲级路线，都没有 = 选专业
local routeKey              -- 冲级路线 / 配方库选中的专业
local flt = { range = 0, slot = 1, new = false, mine = false, q = "", src = 1 }   -- 配方库筛选（src = SRC_FILTERS 下标）
local shortSource   -- 配方出处短句（定义在配方库那段，冲级路线也用）
local ROW_H = 36
local TIME_H = 58
local MAX_RECIPES = 120

local function D() return ns.ProfData end
local P = function() return ns.Prof end

-- ---------- 点一下就买（11-15 用户截图「如何点击就能买材料和配方」）----------
--   开着商人窗口：点配方行 = 买这一步的图纸（这个商人卖、你还没学）+ 商人卖的材料（只补背包里缺的）；
--     这一次要花超过 1 金 → 先在聊天框报总价，3 秒内再点一次才买（同卖垃圾的两下确认）
--   开着拍卖行：点一下 = 在拍卖行搜这一行缺的材料（再点搜下一样）；材料都够了就搜图纸
--   都没开：照旧在地图上标出图纸出处
--   ⛔ 只在玩家点击里调 BuyMerchantItem / 拍卖行搜索（暴雪要求硬件点击）；不自动下单拍卖行（一口价要玩家自己点）
local Shop = { CONFIRM_COPPER = 10000, CONFIRM_SEC = 3 }
ns.ProfShop = Shop
local function scall(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if r[1] then return unpack(r, 2) end
    return nil
end
local function shown(f) return f and f.IsShown and f:IsShown() and true or false end
function Shop.MerchantOpen() return shown(_G.MerchantFrame) end
function Shop.AHOpen() return shown(_G.AuctionFrame) or shown(_G.AuctionHouseFrame) end
local function linkId(l) return type(l) == "string" and tonumber(l:match("item:(%d+)")) or nil end
function Shop.Have(id) return (P().BagCount and P().BagCount(id)) or scall(_G.GetItemCount, id) or 0 end
function Shop.Known(sp)
    if not sp then return false end
    return (scall(_G.IsPlayerSpell, sp) or scall(_G.IsSpellKnown, sp)) and true or false
end
-- 11-15 用户截图「烹饪书点击为啥是数字」：物品信息没缓存时 A.ItemName 退回物品编号 → 拿编号去拍卖行搜。
--   改成：游戏物品信息 > 调用方给的名字（教材名）> 数据里的中文名（不是纯数字）；都没有 = 请求加载，Shop.SearchName 返回 nil
local function isNum(s) return type(s) ~= "string" or s == "" or s:match("^#?%d+$") ~= nil end
function Shop.SearchName(id, hint)
    local n = scall(_G.GetItemInfo, id)
    if not isNum(n) then return n end
    if not isNum(hint) then return hint end
    local a = ns.ProfAssist and ns.ProfAssist.ItemName and ns.ProfAssist.ItemName(id)
    if not isNum(a) then return a end
    local C = _G.C_Item
    if C and C.RequestLoadItemDataByID then pcall(C.RequestLoadItemDataByID, id) end
    return nil
end
function Shop.Name(id, hint) return Shop.SearchName(id, hint) or ("#" .. id) end
-- 商人这一页卖的：{ [物品] = { i, price, stack, avail } }
function Shop.MerchantGoods()
    local out = {}
    local n = tonumber(scall(_G.GetMerchantNumItems)) or 0
    for i = 1, n do
        local id = linkId(scall(_G.GetMerchantItemLink, i))
        if id then
            local price, stack, avail
            local C = _G.C_MerchantFrame
            local info = C and C.GetItemInfo and scall(C.GetItemInfo, i)
            if type(info) == "table" then
                price, stack, avail = info.price, info.stackCount, info.numAvailable
            else
                local _, _, p, q, a = scall(_G.GetMerchantItemInfo, i)
                price, stack, avail = p, q, a
            end
            out[id] = { i = i, price = tonumber(price) or 0, stack = math.max(1, tonumber(stack) or 1), avail = tonumber(avail) or -1 }
        end
    end
    return out
end
-- 这一行在这个商人能买的：{ { id, n(件), cost, recipe = true? } }
function Shop.MerchantPlan(link, part)
    local goods, plan, cost = Shop.MerchantGoods(), {}, 0
    local r = part ~= "mats" and link.recipe or nil
    local rid = r and tonumber(r[18])
    if rid and goods[rid] and not Shop.Known(link.spell or r[1]) and Shop.Have(rid) == 0 then
        local g = goods[rid]
        plan[#plan + 1] = { id = rid, n = g.stack, buys = 1, g = g, recipe = true }
        cost = cost + g.price
    end
    for _, mt in ipairs(part ~= "recipe" and link.mats or {}) do
        local id, need = mt[1], mt[2]
        local g = goods[id]
        local lack = need - Shop.Have(id)
        if g and lack > 0 then
            local buys = math.ceil(lack / g.stack)
            if g.avail >= 0 then buys = math.min(buys, g.avail) end
            if buys > 0 then
                plan[#plan + 1] = { id = id, n = buys * g.stack, buys = buys, g = g }
                cost = cost + buys * g.price
            end
        end
    end
    return plan, cost
end
local function money(c)
    if ns.Prices and ns.Prices.Money then return ns.Prices.Money(c) end
    local s = scall(_G.GetCoinTextureString, c)
    return s or (math.floor(c / 10000) .. "g")
end
function Shop.Buy(plan)
    local done = {}
    for _, p in ipairs(plan) do
        local g = p.g
        if g.stack > 1 then
            for _ = 1, p.buys do scall(_G.BuyMerchantItem, g.i, 1) end
        else
            local left, cap = p.buys, tonumber(scall(_G.GetMerchantItemMaxStack, g.i)) or 20
            if cap < 1 then cap = 1 end
            while left > 0 do
                local k = math.min(left, cap)
                scall(_G.BuyMerchantItem, g.i, k)
                left = left - k
            end
        end
        done[#done + 1] = Shop.Name(p.id, p.hint) .. "×" .. p.n
    end
    return done
end
function Shop.AtMerchant(link, row, part)
    local plan, cost = Shop.MerchantPlan(link, part)
    for _, p in ipairs(plan) do if link.book and p.id == link.item then p.hint = link.book end end
    if #plan == 0 then
        ns.Print(part == "recipe" and ns.L("这个商人没卖这张图纸（或者你已经学会 / 包里有了）", "This vendor doesn't sell this recipe")
            or ns.L("这个商人没卖这一步要的材料（或者背包里已经够了）", "This vendor sells nothing this step still needs"))
        return false
    end
    local t = GetTime and GetTime() or 0
    local key = tostring(row) .. (part or "")
    if cost >= Shop.CONFIRM_COPPER and not (Shop.armed == key and Shop.armedAt and t - Shop.armedAt <= Shop.CONFIRM_SEC) then
        Shop.armed, Shop.armedAt = key, t
        local names = {}
        for _, p in ipairs(plan) do names[#names + 1] = Shop.Name(p.id, p.hint) .. "×" .. p.n end
        ns.Print(ns.L("要买：", "Will buy: ") .. table.concat(names, ns.L("、", ", ")) .. ns.L("，共 ", " for ") .. money(cost)
            .. ns.L("。3 秒内再点一次确认", ". Click again within 3s to confirm"))
        return false
    end
    Shop.armed, Shop.armedAt = nil, nil
    local done = Shop.Buy(plan)
    ns.Print(ns.L("已买：", "Bought: ") .. table.concat(done, ns.L("、", ", ")) .. ns.L("（", " (") .. money(cost) .. ns.L("）", ")"))
    return true
end
-- 拍卖行搜一个名字：旧版拍卖行（BrowseName + QueryAuctionItems）/ 新版（AuctionHouseFrame.SearchBar）
function Shop.AHSearch(name)
    if shown(_G.AuctionHouseFrame) then
        local bar = _G.AuctionHouseFrame.SearchBar
        local box = bar and bar.SearchBox
        if box and box.SetText then box:SetText(name) end
        if bar and bar.StartSearch then return pcall(bar.StartSearch, bar) end
        return false
    end
    if shown(_G.AuctionFrame) then
        if _G.AuctionFrameTab1 and _G.AuctionFrameTab_OnClick and _G.PanelTemplates_GetSelectedTab
            and _G.PanelTemplates_GetSelectedTab(_G.AuctionFrame) ~= 1 then
            pcall(_G.AuctionFrameTab_OnClick, _G.AuctionFrameTab1)
        end
        if _G.BrowseName and _G.BrowseName.SetText then _G.BrowseName:SetText(name) end
        if _G.AuctionFrameBrowse_Search then return pcall(_G.AuctionFrameBrowse_Search) end
        if _G.QueryAuctionItems then return pcall(_G.QueryAuctionItems, name) end
    end
    return false
end
-- 这一行要在拍卖行找的：缺的材料（没缺的就全部材料）→ 再没有就图纸
function Shop.AHList(link, part)
    local lack, all = {}, {}
    for _, mt in ipairs(part ~= "recipe" and link.mats or {}) do
        local miss = mt[2] - Shop.Have(mt[1])
        all[#all + 1] = { id = mt[1], miss = miss }
        if miss > 0 then lack[#lack + 1] = { id = mt[1], miss = miss } end
    end
    local list = #lack > 0 and lack or {}
    local r = part ~= "mats" and link.recipe or nil
    local rid = r and tonumber(r[18])
    if rid and (part == "recipe" or (not Shop.Known(link.spell or r[1]) and Shop.Have(rid) == 0)) then list[#list + 1] = { id = rid, recipe = true } end
    if #list == 0 then list = all end
    for _, e in ipairs(list) do if link.book and e.id == link.item then e.hint = link.book end end
    return list
end
function Shop.AtAH(link, row, part)
    local list = Shop.AHList(link, part)
    if #list == 0 then return false end
    if rawget(row, "shopLink") ~= link or rawget(row, "shopPart") ~= part then row.shopK, row.shopLink, row.shopPart = 0, link, part end
    local k = (rawget(row, "shopK") or 0) % #list + 1
    row.shopK = k
    local e = list[k]
    local name = Shop.SearchName(e.id, e.hint)
    if not name then
        ns.Print(ns.L("这件东西的名字游戏还没读到，过一秒再点一次", "Item info is still loading - click again in a second"))
        row.shopK = k - 1
        return true
    end
    Shop.AHSearch(name)
    ns.Print(ns.L("拍卖行搜：", "AH search: ") .. name .. (e.recipe and ns.L("（图纸）", " (recipe)") or (e.miss and e.miss > 0 and string.format(ns.L("（缺 %d）", " (need %d)"), e.miss) or ""))
        .. (#list > 1 and string.format(ns.L("  · 再点搜下一样（%d/%d）", "  - click again for the next (%d/%d)"), k, #list) or ""))
    return true
end
-- ---------- 专业购买快捷窗口（11-15 用户「专业购买的快捷窗口」）----------
--   开商人 / 拍卖行时，贴在它右边：列出你学了的专业「现在这一段」还要买的 —— 图纸（没学的）、缺的材料、下一档的教材；
--   商人：只列这个商人卖的，每行「买」+ 底下「全部买」（超过 1 金两下确认，同 Shop.AtMerchant）；拍卖行：每行「搜」
--   这一段什么都不用买 / 这个商人什么都不卖 → 不弹。× 关掉 = 这次不弹；「不再弹」= 存档关掉（/gi 专业购买 重新打开）
Shop.QMAX = 10
local function profDB() ns.db.prof = ns.db.prof or {}; return ns.db.prof end
function Shop.QuickOn() return ns.db and profDB().quick ~= false end
-- ⛔ 11-16 GI-272「点了不再弹，重新开商店还是弹」：原来写 (not v) and false or nil —— Lua 里 false or nil = nil，存不进 false
function Shop.SetQuick(v)
    if v then profDB().quick = nil else profDB().quick = false end
end
-- 11-17 用户「这些弹出的功能都确保能永久关闭」：「不再弹」之后再说一次「窗口与提醒」里能找回（同一扇最多 3 次）
function Shop.NeverHint()
    if ns.CloseHint then
        ns.CloseHint("profShop", ns.L("也能在 GI 菜单的「设置 · 窗口与提醒」里，「专业购买窗口」那一行点「打开」", "Also: GI menu > Settings > Windows & alerts > Profession shopping window"))
    end
end
-- 现在要买的：{ { id, need, recipe = rr?, book = name?, key, why } }（按 物品 去重，数量取大）
function Shop.Needs()
    local A, PP = ns.ProfAssist, ns.Prof
    if not (A and A.CraftPlan and PP and PP.Skills) then return {} end
    local skills = PP.Skills() or {}
    local out, byId = {}, {}
    local function add(e)
        local o = byId[e.id]
        if o then if (e.need or 0) > (o.need or 0) then o.need = e.need end return end
        byId[e.id] = e; out[#out + 1] = e
    end
    local lv = UnitLevel and UnitLevel("player") or 1
    for key, s in pairs(skills) do
        local rank = type(s) == "table" and tonumber(s.r)
        if rank and rank < 300 then
            local plan = A.CraftPlan(key, rank)
            for _, seg in ipairs(plan and plan.segs or {}) do
                if seg.state == "here" then
                    for _, e in ipairs(seg.steps) do
                        if e.rem then
                            local rr = ns.ProfRecipeBySpell and ns.ProfRecipeBySpell(e.st.sp)
                            local rid = rr and rr[14] ~= 1 and tonumber(rr[18])
                            if rid and not Shop.Known(e.st.sp) and Shop.Have(rid) == 0 then add({ id = rid, need = 1, recipe = rr, key = key, f = seg.f or seg[1], t = seg.t or seg[2] }) end
                        end
                    end
                    for _, m in ipairs(seg.total or {}) do
                        local lack = (m.need or 0) - Shop.Have(m.item)
                        if lack > 0 then add({ id = m.item, need = lack, key = key, f = seg.f or seg[1], t = seg.t or seg[2] }) end
                    end
                end
            end
            local nt = A.NextTier and A.NextTier(key, s, lv)
            local b = nt and A.BookOf and A.BookOf(nt.tier)
            if b and Shop.Have(b.item) == 0 then add({ id = b.item, need = 1, book = b.book, key = key, tier = nt.tier }) end
        end
    end
    return out
end
-- 商人：这一页卖的里面有哪些是要的 → { { e, g, buys, n, cost } }, 总价
function Shop.QuickMerchantRows()
    local goods, rows, total = Shop.MerchantGoods(), {}, 0
    for _, e in ipairs(Shop.Needs()) do
        local g = goods[e.id]
        if g then
            local buys = math.ceil(e.need / g.stack)
            if g.avail >= 0 then buys = math.min(buys, g.avail) end
            if buys > 0 then
                rows[#rows + 1] = { e = e, g = g, buys = buys, n = buys * g.stack, cost = buys * g.price }
                total = total + buys * g.price
            end
        end
    end
    return rows, total
end
-- 拍卖行：要的里面能上拍卖行的（物品信息没缓存 = 先列上）
function Shop.QuickAHRows()
    local rows = {}
    for _, e in ipairs(Shop.Needs()) do
        if Shop.CanAH(e.id) ~= false then rows[#rows + 1] = { e = e, n = e.need } end
    end
    return rows
end
-- 11-15 用户截图「数量」：写清楚 要买几个（商人按组凑整后的件数）+ 包里已有几个
-- 11-16 用户截图「这里标记出来是什么专业，多少-多少的，对应好」：每行右边写哪个专业、哪一段技能
function Shop.RangeTag(e)
    if not (e and e.key) then return "" end
    local P = ns.Prof
    local nm = (P and P.Name and P.Name(e.key)) or e.key
    if e.tier then return nm .. " " .. ns.L("学", "train ") .. ns.L(e.tier.zh or "", e.tier.en or e.tier.zh or "") end
    if e.f and e.t then return nm .. " " .. e.f .. "-" .. e.t end
    return nm
end
local function qrowLabel(r)
    local e = r.e
    local kind = e.recipe and ns.L("图纸 ", "Recipe ") or e.book and ns.L("教材 ", "Book ") or ""
    local have = Shop.Have(e.id)
    local n = r.n or e.need
    local q = (e.recipe or e.book) and "" or ("  |cffff7070" .. ns.L("缺 ", "need ") .. e.need .. "|r"
        .. ((r.n and r.n ~= e.need) and ("|cff999999" .. string.format(ns.L("（买 %d）", " (buy %d)"), r.n) .. "|r") or "")
        .. (have > 0 and ("|cff999999" .. string.format(ns.L(" · 包里 %d", " - have %d"), have) .. "|r") or ""))
    return "|cffffd100" .. kind .. "|r" .. Shop.Name(e.id, e.book) .. ((e.recipe or e.book) and (" ×" .. n) or "") .. q
end
-- 11-15 用户截图「图标」：GetItemIcon 在《无限》客户端拿不到 → 问号；C_Item.GetItemIconByID / GetItemInfoInstant 不用等物品缓存
function Shop.Icon(id)
    local C = _G.C_Item
    local ic = C and C.GetItemIconByID and scall(C.GetItemIconByID, id)
    if not ic and _G.GetItemInfoInstant then ic = select(5, scall(_G.GetItemInfoInstant, id)) end
    if not ic and _G.GetItemIcon then ic = scall(_G.GetItemIcon, id) end
    return ic or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- 11-17 用户截图「重合了，优化一下，是不是应该整合到一个」：商人处不再单独弹框 —— 变成主插件「商人助手」（MerchantDock.lua）里的「买材料」页签，
--   和卖垃圾共用一个标题栏 / × / 「不再弹」/ 位置；页签上标件数，有材料可买时默认先显示这一页。拍卖行那边照旧是自己的小窗（下面 qf）
--   「不再弹」= 原来的 ns.db.prof.quick = false（只关这一块，卖垃圾照常）；/gi 专业购买 重新打开
local function Dock() return ns.MerchantDock end
function Shop.RegisterDock()
    local DK = Dock()
    if Shop.docked then return DK end
    if not (DK and DK.UI and DK.UI()) then return nil end   -- 外框在清背包子插件（MerchantDockUI.lua）；没装 = 退回独立小窗
    Shop.docked = true
    DK.Register("shop", { order = 1,
        tab = function() return ns.L("买材料", "Buy mats") end,
        count = function() return Shop.qmN end,
        never = function()
            Shop.SetQuick(false)
            ns.Print(ns.L("专业购买窗口不再自动弹；想重新打开：/gi 专业购买", "Profession shopping window turned off - /gi profshop to turn it back on"))
            Shop.NeverHint()
        end,
        neverTip = function() return ns.L("/gi 专业购买 重新打开", "/gi profshop turns it back on") end })
    return DK
end
-- 行 + 「全部买」按钮（商人助手页签里和拍卖行小窗共用）；x0 / y0 = 第一行左上角
local function qBuildRows(f, x0, y0)
    f.x0, f.y0 = x0, y0
    f.rows = {}
    for i = 1, Shop.QMAX do
        local r = CreateFrame("Frame", nil, f); r:SetSize(354, 20); r:SetPoint("TOPLEFT", x0, y0 - (i - 1) * 22)
        r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("LEFT", 0, 0)
        r.cnt = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); r.cnt:SetPoint("BOTTOMRIGHT", r.ic, "BOTTOMRIGHT", 2, -1)
        r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", r.ic, "RIGHT", 4, 0)
        r.t:SetPoint("RIGHT", -142, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
        r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.tag:SetPoint("RIGHT", -50, 0); r.tag:SetWidth(90)
        r.tag:SetJustifyH("RIGHT"); r.tag:SetWordWrap(false); r.tag:SetTextColor(0.55, 0.8, 1)
        r.b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.b:SetSize(46, 18); r.b:SetPoint("RIGHT", 0, 0)
        if ns.SkinButton then ns.SkinButton(r.b) end
        r:Hide()
        f.rows[i] = r
    end
    f.all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.all:SetSize(160, 20)
    if ns.SkinButton then ns.SkinButton(f.all) end
end
-- kind = "merchant"：商人助手里的「买材料」页（没有商人助手 = 退回独立小窗）；"ah"：拍卖行旁边的独立小窗
function Shop.QuickBuild(kind)
    local DK = kind == "merchant" and Shop.RegisterDock() or nil
    if DK then
        if Shop.qm then return Shop.qm end
        local f = DK.Body("shop")
        f.docked = true
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.title:SetPoint("TOPLEFT", 0, -1)
        qBuildRows(f, 0, -16)
        Shop.qm = f
        return f
    end
    if Shop.qf then return Shop.qf end
    local f = CreateFrame("Frame", "GearInsightForeverProfQuick", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(370, 80); f:SetFrameStrata("HIGH")
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95); f:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -7)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.off = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.off:SetSize(56, 16); f.off:SetPoint("RIGHT", close, "LEFT", -2, 0)
    if ns.SkinButton then ns.SkinButton(f.off) end
    f.off:SetText(ns.L("不再弹", "Never"))
    f.off:SetScript("OnClick", function()
        Shop.SetQuick(false); f:Hide()
        ns.Print(ns.L("专业购买窗口不再自动弹；想重新打开：/gi 专业购买", "Profession shopping window turned off - /gi profshop to turn it back on"))
        Shop.NeverHint()
    end)
    qBuildRows(f, 8, -26)
    f:Hide()
    Shop.qf = f
    return f
end
-- 这一块现在开着没（商人助手里 = 「买材料」页开着，切到卖垃圾页签也算；拍卖行小窗 = 显示着）
function Shop.QuickVisible(kind)
    local DK = Dock()
    if kind == "merchant" and DK and Shop.qm then return DK.IsOn("shop") end
    local f = Shop.qf
    return f ~= nil and f:IsShown() and true or false
end
local function qhide(f)
    if f and rawget(f, "docked") then
        Shop.qmN = 0
        local DK = Dock()
        if DK then DK.Hide("shop") end
    elseif f then f:Hide() end
end
-- kind = "merchant" / "ah"；force = 手动打开（/gi 专业购买），没东西也弹出来说一声
function Shop.QuickShow(kind, force)
    if not force and not Shop.QuickOn() then return false end
    local rows, total
    if kind == "merchant" then rows, total = Shop.QuickMerchantRows() else rows = Shop.QuickAHRows() end
    local f = Shop.QuickBuild(kind)
    local docked = rawget(f, "docked") and true or false
    if #rows == 0 then
        qhide(f)
        if force then ns.Print(ns.L("现在这一段专业路线没有要在这里买的", "Nothing on your current profession route to buy here")) end
        return false
    end
    if not docked then
        local host = (kind == "merchant") and _G.MerchantFrame or (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown() and _G.AuctionHouseFrame) or _G.AuctionFrame
        f:ClearAllPoints()
        if host then f:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, -24) else f:SetPoint("CENTER") end
    end
    f.kind = kind
    f.title:SetText(kind == "merchant" and ns.L("专业路线 · 这个商人有卖", "Your profession route - sold here") or ns.L("专业路线 · 拍卖行找", "Your profession route - on the AH"))
    local shown = math.min(#rows, Shop.QMAX)
    for i = 1, Shop.QMAX do
        local r, d = f.rows[i], rows[i]
        if d and i <= shown then
            r.ic:SetTexture(Shop.Icon(d.e.id))
            r.cnt:SetText((d.n or d.e.need or 0) > 1 and tostring(d.n or d.e.need) or "")
            r.tag:SetText(Shop.RangeTag(d.e))
            r.t:SetText(qrowLabel(d) .. ((kind == "merchant") and ("  |cff999999" .. money(d.cost) .. "|r") or ""))
            r.b:SetText(kind == "merchant" and ns.L("买", "Buy") or ns.L("搜", "Search"))
            r.b:SetScript("OnClick", function()
                if kind == "merchant" then
                    -- ⛔ 就在这次点击里买（硬件事件），不挪到计时器里
                    local done = Shop.Buy({ { id = d.e.id, n = d.n, buys = d.buys, g = d.g } })
                    ns.Print(ns.L("已买：", "Bought: ") .. table.concat(done, ns.L("、", ", ")))
                    if C_Timer and C_Timer.After then C_Timer.After(0.6, function() if Shop.QuickVisible("merchant") then Shop.QuickShow("merchant", true) end end) end
                else
                    local nm = Shop.SearchName(d.e.id, d.e.book)
                    if nm then Shop.AHSearch(nm) else ns.Print(ns.L("这件东西的名字游戏还没读到，过一秒再点一次", "Item info is still loading - click again in a second")) end
                end
            end)
            r:Show()
        else
            r:Hide()
        end
    end
    local h = -f.y0 + shown * 22
    if kind == "merchant" and #rows > 1 then
        f.all:ClearAllPoints(); f.all:SetPoint("TOPLEFT", f.x0, -h - 2)
        f.all:SetText(ns.L("全部买 ", "Buy all ") .. money(total))
        f.all:SetScript("OnClick", function()
            local t = GetTime and GetTime() or 0
            if total >= Shop.CONFIRM_COPPER and not (Shop.qArmed and t - Shop.qArmed <= Shop.CONFIRM_SEC) then
                Shop.qArmed = t
                ns.Print(ns.L("全部买要花 ", "Buying everything costs ") .. money(total) .. ns.L("，3 秒内再点一次确认", " - click again within 3s to confirm"))
                return
            end
            Shop.qArmed = nil
            local plan = {}
            for _, d in ipairs(rows) do plan[#plan + 1] = { id = d.e.id, n = d.n, buys = d.buys, g = d.g } end
            local done = Shop.Buy(plan)
            ns.Print(ns.L("已买：", "Bought: ") .. table.concat(done, ns.L("、", ", ")) .. ns.L("（", " (") .. money(total) .. ns.L("）", ")"))
            if C_Timer and C_Timer.After then C_Timer.After(0.6, function() if Shop.QuickVisible("merchant") then Shop.QuickShow("merchant", true) end end) end
        end)
        f.all:Show()
        h = h + 26
    else
        f.all:Hide()
    end
    if #rows > shown then h = h + 4 end
    if docked then
        Shop.qmN = #rows
        local DK = Dock()
        f:SetHeight(h)
        DK.SetHeight("shop", h)
        DK.Show("shop", force and { focus = true } or nil)
    else
        f:SetHeight(h + 8)
        f:Show()
    end
    return true
end
function Shop.QuickHide()
    if Shop.qf then Shop.qf:Hide() end
    if Shop.qm then qhide(Shop.qm) end
end
-- 行点击总入口：返回 true = 已处理（不再打地图标记）
function Shop.Click(link, row, part)
    if type(link) ~= "table" then return false end
    if Shop.MerchantOpen() then Shop.AtMerchant(link, row, part); return true end
    if Shop.AHOpen() then return Shop.AtAH(link, row, part) end
    return false
end
-- 能不能上拍卖行：物品信息里的绑定类型（1 = 拾取绑定 / 4 = 任务物品 → 不能）；物品信息还没缓存 = nil（不标）
function Shop.CanAH(id)
    if not id then return nil end
    local r = { pcall(_G.GetItemInfo, id) }
    if not r[1] or r[2] == nil then return nil end
    local bind = r[15]
    if bind == nil then return nil end
    return not (bind == 1 or bind == 4)
end
function Shop.AHTag(id)
    local ok = Shop.CanAH(id)
    if ok == nil then return "" end
    return ok and ("|cff33ff99" .. ns.L("可拍卖", "AH ok") .. "|r") or ("|cff808080" .. ns.L("拾取绑定·不能拍卖", "BoP - not on AH") .. "|r")
end
-- 行右边「买 / 搜」按钮的文字：开着商人 = 买，开着拍卖行 = 搜，都没开 = 出处
function Shop.BtnText(link, part)
    local what = part == "recipe" and ns.L("图纸", " recipe") or (link and link.book) and ns.L("书", " book") or (part == "mats" and ns.L("材料", " mats")) or ""
    if Shop.MerchantOpen() then return ns.L("买", "Buy") .. what end
    if Shop.AHOpen() then return ns.L("搜", "Find") .. what end
    return part == "recipe" and ns.L("图纸在哪", "Recipe?") or ns.L("在哪买", "Where")
end
-- 这一行有没有能单独买 / 搜的图纸（训练师学的不算）
function Shop.HasRecipe(link) return type(link) == "table" and link.recipe and tonumber(link.recipe[18]) and true or false end
function Shop.TipLine(link)
    if type(link) ~= "table" or not (link.mats or link.recipe) then return nil end
    return ns.L("开着商人窗口点一下：买图纸和商人卖的材料（只补缺的）· 开着拍卖行点一下：搜缺的材料（再点搜下一样）",
        "With a vendor open: click to buy the recipe and vendor mats you lack - with the AH open: click to search missing mats")
end

local function getRow(i)
    local r = page.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, page.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.03)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(24, 24); r.ic:SetPoint("TOPLEFT", 4, -5); r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.t:SetPoint("TOPLEFT", 34, -3); r.t:SetPoint("RIGHT", -8, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.s:SetPoint("TOPLEFT", 34, -20); r.s:SetPoint("RIGHT", -8, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
    r.s:SetTextColor(0.7, 0.7, 0.7)
    r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.head:SetPoint("LEFT", 6, 0)
    r.head:SetPoint("RIGHT", -8, 0); r.head:SetJustifyH("LEFT")
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
    -- 显示不全一律能悬停看全文（用户硬规定）；配方行先出游戏自己的物品 / 法术说明
    r:SetScript("OnEnter", function(self)
        local link = rawget(self, "link")
        if not rawget(self, "tip") and not link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if link then
            if link.item and link.item > 0 and GameTooltip.SetItemByID then
                shown = pcall(GameTooltip.SetItemByID, GameTooltip, link.item)
            elseif link.spell and GameTooltip.SetSpellByID then
                shown = pcall(GameTooltip.SetSpellByID, GameTooltip, link.spell)
            end
        end
        for i, ln in ipairs(self.tip or {}) do
            if i == 1 and not shown then GameTooltip:AddLine(ln, 1, 0.82, 0, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        local sl = Shop.TipLine(link)
        if sl then GameTooltip:AddLine(sl, 0.4, 0.8, 1, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 11-15 用户「配方购买也要一个按钮」：带图纸 / 材料的行右边一个「买 / 搜 / 在哪买」小按钮（和点整行一样）
    -- 11-15 用户截图「材料和图纸是两个按钮搜索」：右边两个按钮 —— 材料（r.buy）/ 图纸（r.buy2，只在要买图纸的配方行出）
    --   开商人 = 买，开拍卖行 = 搜，都没开 = 图纸 / 教材打地图标记
    local function mk(part, x)
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(62, 18); b:SetPoint("TOPRIGHT", r, "TOPRIGHT", x, -4); b:Hide()
        b.part = part
        b:SetScript("OnClick", function(self)
            local row = self:GetParent()
            local link = rawget(row, "link")
            if Shop.Click(link, row, self.part) then return end
            if self.part == "recipe" and link and link.recipe and ns.ProfPinRecipeSource then ns.ProfPinRecipeSource(link.recipe); return end
            if link and link.book and ns.ProfPinBook then ns.ProfPinBook(link); return end
            ns.Print(ns.L("打开商人窗口点这个按钮就买、打开拍卖行就搜", "Open a vendor to buy, or the auction house to search"))
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Shop.TipLine(rawget(self:GetParent(), "link")) or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    r.buy = mk("mats", -6)
    r.buy2 = mk("recipe", -72)
    -- 配方库：点一下 = 出处打地图标记 + 聊天框列全部出处（10-20 GI-22）
    r:SetScript("OnClick", function(self)
        local link = rawget(self, "link")
        -- 11-18 任务档（专业助手「先学 大师级 · 任务：蚌肉大餐」）：点了追踪任务 / 标出接任务的人
        if type(link) == "table" and link.quest and ns.ProfPinQuest then ns.ProfPinQuest(link); return end
        if Shop.Click(link, self) then return end
        if link and link.recipe and ns.ProfPinRecipeSource then ns.ProfPinRecipeSource(link.recipe) end
        if link and link.book and not link.recipe and ns.ProfPinBook then ns.ProfPinBook(link) end
    end)
    page.rows[i] = r
    return r
end

-- 时刻表那条轴（第一次用时才建）
local function getBar(r)
    local have = rawget(r, "bar")
    if have then return have end
    local b = CreateFrame("Frame", nil, r)
    b:SetPoint("TOPLEFT", 34, -24); b:SetPoint("RIGHT", -12, 0); b:SetHeight(8)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.10)
    b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT"); b.fill:SetPoint("BOTTOMLEFT"); b.fill:SetColorTexture(0.2, 0.8, 0.4, 0.55)
    b.ticks = {}
    r.bar = b
    return b
end

local function getTick(bar, i)
    local t = bar.ticks[i]
    if t then return t end
    t = CreateFrame("Button", nil, bar)
    t:SetSize(9, 16)
    t.tx = t:CreateTexture(nil, "OVERLAY"); t.tx:SetPoint("CENTER"); t.tx:SetSize(4, 14)
    t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for j, ln in ipairs(self.lines or {}) do
            if j == 1 then GameTooltip:AddLine(ln, 1, 0.82, 0, true) else GameTooltip:AddLine(ln, 1, 1, 1, true) end
        end
        GameTooltip:AddLine(ns.L("点一下：在升级规划里看这一级", "Click: open the leveling plan at this level"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() GameTooltip:Hide() end)
    t:SetScript("OnClick", function(self) if ns.PlanShowLevel then ns.PlanShowLevel(self.lv) end end)
    bar.ticks[i] = t
    return t
end

-- 写行的小工具：head 标题行 / item 普通行 / timeRow 带轴的行
local y, n
local function reset(r, h)
    r.tip, r.link = nil, nil
    local bb = rawget(r, "buy")
    if bb then bb:Hide(); r.buy2:Hide() end
    local bar = rawget(r, "bar")
    if bar then bar:Hide() end
    r.s:ClearAllPoints(); r.s:SetPoint("TOPLEFT", 34, -20); r.s:SetPoint("RIGHT", -8, 0)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.child, "RIGHT", 0, 0); r:SetHeight(h); r:Show()
end
local function head(text)
    n = n + 1
    local r = getRow(n)
    reset(r, 22)
    r.ic:Hide(); r.t:SetText(""); r.s:SetText(""); r.bg:Hide()
    r.head:SetText("|cffffd100" .. text .. "|r")
    y = y - 24
end
local function item(icon, title, sub, tip, link)
    n = n + 1
    local r = getRow(n)
    reset(r, ROW_H)
    r.head:SetText(""); r.bg:Show()
    if icon then r.ic:SetTexture(icon); r.ic:Show() else r.ic:Hide() end
    r.t:SetText(title or ""); r.s:SetText(sub or "")
    r.tip = tip or { title or "", sub or "" }
    r.link = link
    -- 带图纸 / 材料 / 教材的行：右边出「买 / 搜 / 在哪买」，标题让出按钮的位置
    local hasMats = type(link) == "table" and link.mats and #link.mats > 0
    local hasRec = Shop.HasRecipe(link)
    local nb = 0
    if hasMats then
        -- 都没开：材料按钮没东西可买 → 只在教材行留「在哪买」，配方行交给图纸按钮
        if Shop.MerchantOpen() or Shop.AHOpen() or link.book then r.buy:SetText(Shop.BtnText(link, "mats")); r.buy:Show(); nb = 1 end
    end
    if hasRec then
        r.buy2:ClearAllPoints(); r.buy2:SetPoint("TOPRIGHT", r, "TOPRIGHT", nb == 1 and -72 or -6, -4)
        r.buy2:SetText(Shop.BtnText(link, "recipe")); r.buy2:Show(); nb = nb + 1
    end
    r.t:SetPoint("RIGHT", nb == 2 and -140 or nb == 1 and -74 or -8, 0)
    y = y - ROW_H - 2
    return r
end

local PICON = { alchemy = "trade_alchemy", blacksmithing = "trade_blacksmithing", enchanting = "trade_engraving",
    engineering = "trade_engineering", leatherworking = "inv_misc_armorkit_17", tailoring = "trade_tailoring",
    herbalism = "spell_nature_naturetouchgrow", mining = "trade_mining", skinning = "inv_misc_pelt_wolf_01",
    cooking = "inv_misc_food_15", firstaid = "spell_holy_sealofsacrifice", fishing = "trade_fishing" }
local function icon(key) return "Interface\\Icons\\" .. (PICON[key] or "inv_misc_questionmark") end

local function myClass()
    local _, c = UnitClass and UnitClass("player")
    return c
end
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_ZH = { WARRIOR = "战士", PALADIN = "圣骑士", HUNTER = "猎人", ROGUE = "潜行者", PRIEST = "牧师", SHAMAN = "萨满祭司",
    MAGE = "法师", WARLOCK = "术士", DRUID = "德鲁伊" }
local function className(c)
    local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]
    return loc or ns.L(CLASS_ZH[c] or c, c:sub(1, 1) .. c:sub(2):lower())
end

-- ---------- 选专业（升级最快） ----------
local function campLine(key)
    local c = P().Camp(key)[1]
    if not c then return "" end
    -- 游戏里的说明带数值（2% / 8% / 56 点）优先；没有（帐篷）再用我们的一句话
    return ns.L(c.zh, c.en) .. "：" .. ns.TD(ns.EnSafe((c.tx and c.tx ~= "") and c.tx or c.fn))   -- GI-253：设施说明（数据中文）繁体端也转
end

local function renderPick()
    local skills = P().Skills()
    local cls = myClass()
    local note = P().PICK_NOTE[cls or ""]
    head(ns.L("升级最快的专业", "Fastest-leveling professions") .. (cls and ("  |cffc8c8c8" .. className(cls) .. "|r") or ""))
    item(icon("leatherworking"), "|cff33ff99" .. ns.L("主专业：剥皮 + 制皮", "Primary: Skinning + Leatherworking") .. "|r",
        note and ns.L(note[1], note[2]) or ns.L("两个都先冲到 20：营地第一档设施就是练级最值的两件", "Get both to 20 first: their first camp objects help leveling most"),
        { ns.L("剥皮 + 制皮", "Skinning + Leatherworking"), ns.L("两个都先冲到 20：营地第一档设施就是练级最值的两件", "Get both to 20 first: their first camp objects are the best for leveling"),
          note and ns.L(note[1], note[2]) or nil })
    item(icon("leatherworking"), ns.L("制皮 20 · ", "Leatherworking 20 - ") .. campLine("leatherworking"), ns.L("每小时一次的休息经验，不占团队增益位", "Rested XP once an hour; takes no buff slot"))
    item(icon("skinning"), ns.L("剥皮 20 · ", "Skinning 20 - ") .. campLine("skinning"), ns.L("全队就座的人都吃", "Everyone seated gets it"))
    head(ns.L("副专业：三个都学（不占主专业栏位）", "Secondary: learn all three (no profession slot)"))
    item(icon("cooking"), ns.L("烹饪：自制食物击杀经验 +", "Cooking: crafted food gives +") .. (D().xpPct or 5) .. ns.L("%", "% kill XP"),
        ns.L("吃饱 15 分钟；营火也是摆营地设施的前提", "Well Fed for 15 min; the campfire is what every camp object needs"))
    item(icon("fishing"), ns.L("钓鱼到 20 · ", "Fishing to 20 - ") .. campLine("fishing"), ns.L("20 点就能学，门槛最低的一件营地设施", "Only 20 skill: the cheapest camp object"))
    item(icon("firstaid"), ns.L("急救 · ", "First Aid - ") .. campLine("firstaid"), ns.L("绷带回血，少坐下吃喝", "Bandages mean less time sitting to eat"))
    -- 你现在
    head(ns.L("你现在", "You now"))
    local have = {}
    for _, key in ipairs(P().ORDER) do
        if skills[key] then have[#have + 1] = P().Name(key) .. " " .. skills[key].r end
    end
    local planned = P().Planned()
    item(nil, #have > 0 and table.concat(have, ns.L("、", ", ")) or ns.L("还没学专业", "No professions yet"),
        planned and (ns.L("已按这套规划：", "Planned: ") .. (function()
            local t = {}
            for _, k in ipairs(planned) do t[#t + 1] = P().Name(k) end
            return table.concat(t, ns.L("、", ", "))
        end)()) or ns.L("点上面「按这套规划」，升级规划会在路过的城里提醒你去学", "Press 'Plan these' above; the leveling plan will remind you where to learn them"),
        { ns.L("你现在", "You now"), ns.L("已经学了别的也没关系：规划照样按你学的专业出", "Already learned others? The plan follows whatever you have"),
          ns.L("主专业只能学两个：两个都满了，选的主专业不会再加进规划", "Only two primary professions: if both slots are used, planned primaries are skipped") })
    head(ns.L("各职业一览", "All classes"))
    for _, c in ipairs(CLASSES) do
        local nt = P().PICK_NOTE[c]
        item(nil, (c == cls and "|cff33ff99" or "") .. className(c) .. (c == cls and "|r" or "") .. ns.L("：剥皮 + 制皮", ": Skinning + Leatherworking"),
            nt and ns.L(nt[1], nt[2]) or "")
    end
end

-- ---------- 我的时刻表 ----------
local KCOL = { train = { 0.4, 0.8, 1 }, gate = { 1, 0.82, 0 }, done = { 0.2, 0.9, 0.4 }, far = { 1, 0.4, 0.3 } }
local function timeRow(key, s, nodes, cur)
    n = n + 1
    local r = getRow(n)
    reset(r, TIME_H)
    r.head:SetText(""); r.bg:Show()
    r.ic:SetTexture(icon(key)); r.ic:Show()
    local cap = s.plan and ns.L("选了还没学", "planned, not learned") or (s.r .. "/" .. (s.m or "?"))
    r.t:SetText(P().Name(key) .. "  |cffffd100" .. cap .. "|r")
    local bar = getBar(r)
    bar:Show()
    local w = (page.child:GetWidth() or 600) - 46
    local function xOf(lv) return math.max(0, math.min(1, ((lv or 1) - 1) / 59)) * w end
    bar.fill:SetWidth(math.max(1, xOf(cur)))
    for _, t in ipairs(bar.ticks) do t:Hide() end
    local upcoming = {}
    for i, nd in ipairs(nodes) do
        local t = getTick(bar, i)
        local col = nd.done and KCOL.done or nd.far and KCOL.far or KCOL[nd.kind] or KCOL.gate
        t.tx:SetColorTexture(col[1], col[2], col[3], 1)
        t:ClearAllPoints(); t:SetPoint("CENTER", bar, "LEFT", xOf(nd.lv), 0)
        t.lv = nd.lv
        t.lines = { P().Name(key), nd.text }
        t:Show()
        if not nd.done and #upcoming < 2 then upcoming[#upcoming + 1] = nd.text end
    end
    r.s:ClearAllPoints(); r.s:SetPoint("TOPLEFT", 34, -38); r.s:SetPoint("RIGHT", -8, 0)
    r.s:SetText(#upcoming > 0 and (ns.L("接下来：", "Next: ") .. table.concat(upcoming, ns.L("；", "; "))) or ns.L("路线上没有要办的了", "Nothing left on the route"))
    local tip = { P().Name(key) .. "  " .. cap }
    for _, nd in ipairs(nodes) do tip[#tip + 1] = (nd.done and "|cff33ff99" or "") .. nd.text .. (nd.done and "|r" or "") end
    local camp = P().Camp(key)
    for _, c in ipairs(camp) do
        tip[#tip + 1] = "|cffc8c8c8" .. ns.L("营地 ", "Camp ") .. c.sk .. ns.L(" 点：", ": ") .. ns.L(c.zh, c.en) .. "|r"
    end
    r.tip = tip
    y = y - TIME_H - 2
end

local function renderTime()
    local skills = P().Skills()
    local plan = P().PlanSkills(skills)
    local cur = UnitLevel and UnitLevel("player") or 1
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    local race = ns.RouteRace and ns.RouteRace()
    head(ns.L("我的时刻表（1-60 级；蓝 = 训练，黄 = 离开前采集门槛，绿 = 已达成）", "My timeline (1-60; blue = training, yellow = gather target, green = done)"))
    local any = false
    for _, key in ipairs(P().ORDER) do
        local s = plan[key]
        if s then
            any = true
            timeRow(key, s, P().Timeline(key, s, fac, race, cur), cur)
        end
    end
    if not any then
        item(nil, ns.L("还没有专业", "No professions yet"),
            ns.L("去「选专业」选一套，或者学了以后打开一次专业窗口", "Pick a set in 'Choose', or open your profession window once after learning"))
    end
    item(nil, "|cff888888" .. ns.L("节点按升级路线和训练师位置排（经典基线）；点节点跳到升级规划那一级", "Nodes follow your leveling route and trainer locations (Classic baseline); click one to jump to that level") .. "|r", "")
end

-- ---------- 冲级路线 ----------
-- 10-16 用户截图「选中的状态不明显，优化」：选中的保持可点，加金色粗边框 + 金色底光 + 白字
local SEL = setmetatable({}, { __mode = "k" })
local function markSel(b, on)
    -- 11-14 用户截图专业页「按键美化」：按钮换成扁平分段样式（同组队顶上那种），选中 = 暗金底金边金线
    if rawget(b, "_seg") and ns.SegSelect then ns.SegSelect(b, on); return end
    local box = SEL[b]
    if not box then
        box = {}
        SEL[b] = box
        local glowTex = b:CreateTexture(nil, "OVERLAY")
        glowTex:SetPoint("TOPLEFT", 3, -3); glowTex:SetPoint("BOTTOMRIGHT", -3, 3)
        glowTex:SetColorTexture(1, 0.82, 0, 0.28); glowTex:SetBlendMode("ADD")
        box[1] = glowTex
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
            { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
            local t = b:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.85, 0.1, 1)
            t:SetPoint(side[1]); t:SetPoint(side[2])
            if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
            box[#box + 1] = t
        end
    end
    b:SetEnabled(true)
    for _, t in ipairs(box) do t:SetShown(on) end
    if b.SetNormalFontObject then b:SetNormalFontObject(on and "GameFontHighlight" or "GameFontNormal") end
end

local ROUTE_KEYS = { "firstaid", "cooking", "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring" }
-- 11-09 GI-204「比如剥皮，多少技能点可以剥什么地方的皮」：冲级路线第二排放三个采集专业，点了出「技能多少去哪张图」总表
local GATHER_KEYS = { "skinning", "herbalism", "mining" }
local IS_GATHER = { skinning = true, herbalism = true, mining = true }
-- 11-12 专业助手（ProfAssist.lua，HOLD 时不在包里）：在的话第二排多一个钓鱼，冲级路线子页改叫「专业助手」
if ns.ProfAssist then GATHER_KEYS[#GATHER_KEYS + 1] = "fishing"; IS_GATHER.fishing = true end
-- 11-14 用户「专业快速冲级整理的更加容易找到」：冲级路线默认选哪个专业
--   ① 角色已经学了的主制造专业（P.CRAFT；没在「选专业」里规划也直接用，玩家不用先去选一遍）
--   ② 冲级路线页：角色已经学了的采集专业（原来纯采集角色默认落在急救；配方库没有采集专业，不认这一档）
--   ③ 「选专业」里规划了、还没学的主专业（制造优先，冲级路线页再认采集）
--   ④ 角色学了的副专业（烹饪 / 急救，按 ROUTE_KEYS 顺序）
--   ⑤ 都没有 = 急救（谁都能学）
local function pickRouteKey(skills, gatherOk)
    if routeKey then return end
    skills = skills or {}
    for _, k in ipairs(ROUTE_KEYS) do if skills[k] and P().CRAFT[k] then routeKey = k return end end
    if gatherOk then for _, k in ipairs(GATHER_KEYS) do if skills[k] then routeKey = k return end end end
    local planned = {}
    for _, k in ipairs((P().Planned and P().Planned()) or {}) do planned[k] = true end
    for _, k in ipairs(ROUTE_KEYS) do if planned[k] then routeKey = k return end end
    if gatherOk then for _, k in ipairs(GATHER_KEYS) do if planned[k] then routeKey = k return end end end
    for _, k in ipairs(ROUTE_KEYS) do if skills[k] then routeKey = k return end end
    routeKey = "firstaid"
end

-- 地图名：猎宠数据里有中英文名；没有的几张补上；再没有就问客户端
local ZONE_EXTRA = { [1449] = { "安戈洛环形山", "Un'Goro Crater" }, [1450] = { "月光林地", "Moonglade" }, [1459] = { "奥特兰克山谷", "Alterac Valley" } }
local function zoneName(m)
    local t = (ns.PetTameData and ns.PetTameData.zones and ns.PetTameData.zones[m]) or ZONE_EXTRA[m]
    if t and t[1] then return ns.L(t[1], t[2] or t[1]) end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, m)
        if ok and type(info) == "table" and info.name then return info.name end
    end
    return tostring(m)
end
ns._ProfZoneName = zoneName   -- 测试用

local function renderGather(key, rank)
    local G = P().GatherColor
    local function col(need) local c = rank and G(need, rank); return c and P().HEX[c] or "ffffff" end
    local zones = D().zones or {}
    local ms = {}
    for m in pairs(zones) do ms[#ms + 1] = m end
    head(P().Name(key) .. ns.L("：技能多少去哪张图", ": where to go at each skill")
        .. (rank and ("   |cff33ff99" .. ns.L("你现在 ", "you: ") .. rank .. "|r") or ""))
    if key == "skinning" then
        item(icon("skinning"), ns.L("剥皮要求 = 野兽等级：10 级及以下 1 点；11-20 级 =（等级 - 10）× 10；20 级以上 = 等级 × 5",
            "Skill needed by beast level: up to 10 = 1; 11-20 = (level - 10) x 10; above 20 = level x 5"),
            ns.L("比要求高 100 点就不再涨点（变灰）。颜色按你现在的技能：红 = 剥不了，橙 / 黄 / 绿 = 会涨，灰 = 不涨",
                "No more skill-ups 100 points above. Colors use your skill: red = can't, orange/yellow/green = skill-ups, grey = none"))
        local list = {}
        for _, m in ipairs(ms) do if zones[m].sk then list[#list + 1] = m end end
        table.sort(list, function(a, b)
            local x, z = zones[a].sk, zones[b].sk
            if x[3] ~= z[3] then return x[3] < z[3] end
            if x[4] ~= z[4] then return x[4] < z[4] end
            return a < b
        end)
        for _, m in ipairs(list) do
            local sk = zones[m].sk
            local need = sk[3] == sk[4] and tostring(sk[3]) or (sk[3] .. "-" .. sk[4])
            item(nil, "|cff" .. col(sk[3]) .. need .. "|r  " .. zoneName(m),
                string.format(ns.L("%d-%d 级野兽 · 技能 %d 起能剥这里的全部 · 练到 %d 不再涨", "Lv %d-%d beasts - all skinnable from %d - grey at %d"),
                    sk[1], sk[2], sk[4], sk[4] + 100))
        end
        return
    end
    -- 草药 / 矿：按种类列，每种写要求 + 最多的几张图
    local field = key == "herbalism" and "h" or "o"
    local by, order = {}, {}
    for _, m in ipairs(ms) do
        for _, nd in ipairs(zones[m][field] or {}) do
            local nm = nd[4] or nd[1]
            local e = by[nm]
            if not e then e = { zh = nd[1], en = nd[4] or nd[1], need = nd[2], at = {} }; by[nm] = e; order[#order + 1] = e end
            e.at[#e.at + 1] = { m = m, n = nd[3] or 0 }
        end
    end
    table.sort(order, function(a, b) if a.need ~= b.need then return a.need < b.need end return a.en < b.en end)
    item(icon(key), ns.L("每种按要求从低到高；后面是这种点最多的地图（数据库刷新点数）", "Sorted by skill needed; zones with the most spawns follow"),
        ns.L("颜色按你现在的技能：红 = 采不了，橙 / 黄 / 绿 = 会涨，灰 = 不涨", "Colors use your skill: red = can't, orange/yellow/green = skill-ups, grey = none"))
    for _, e in ipairs(order) do
        table.sort(e.at, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.m < b.m end)
        local names = {}
        for i = 1, math.min(5, #e.at) do names[#names + 1] = zoneName(e.at[i].m) end
        item(nil, "|cff" .. col(e.need) .. e.need .. "|r  " .. ns.L(e.zh, e.en),
            table.concat(names, ns.L("、", ", ")) .. (#e.at > 5 and ns.L(" 等 ", " +") .. #e.at .. ns.L(" 张图", " zones") or ""))
    end
end

-- 专业助手用同一套行 / 标题（PageProfAssist.lua）
ns._ProfUI = { head = head, item = item, icon = icon, zoneName = zoneName, renderGather = renderGather,
    shortSource = function(r) return shortSource(r) end }

local function renderRoute()
    local skills = P().Skills()
    pickRouteKey(skills, true)
    -- 11-12 专业助手在包里就交给它画（分段 / 只列接下来的 / 合计材料 / 钓鱼 / 烹饪推荐）；不在就还是下面原来的路线
    if ns.ProfAssistRender and ns.ProfAssistRender(routeKey, skills) then return end
    if IS_GATHER[routeKey] then
        return renderGather(routeKey, skills[routeKey] and skills[routeKey].r)
    end
    local p = D().profs[routeKey]
    local rank = skills[routeKey] and skills[routeKey].r
    head(P().Name(routeKey) .. ns.L(" 1 至 300（最省材料）", " 1 to 300 (cheapest mats)")
        .. (rank and ("   |cff33ff99" .. ns.L("你现在 ", "you: ") .. rank .. "|r") or ""))
    for _, st in ipairs(p.route or {}) do
        if st.train then
            local t = p.tiers[st.train + 1]
            local via = t.via == "book" and (ns.L("买书：", "Book: ") .. (t.name or "")) or t.via == "quest" and (ns.L("任务：", "Quest: ") .. (t.name or ""))
                or ns.L("找训练师", "Trainer")
            item("Interface\\Icons\\INV_Misc_Book_11", "|cff66ccff" .. ns.L("学 ", "Train ") .. ns.L(t.zh, t.en) .. "|r"
                .. ns.L("  技能 ", "  skill ") .. (st.at or "?") .. (((st.lv or 0) > 0) and (ns.L("、角色 ", ", Lv ") .. st.lv .. ns.L(" 级", "")) or ""), via)
        else
            local here = rank and rank >= st.f and rank < st.t
            local col = rank and P().HEX[P().RecipeColor(st, rank)] or "ffffff"
            local mats = {}
            for _, mt in ipairs(st.m) do
                -- v2：背包里有多少（拿不到背包就只写需要）
                local have = P().BagCount and P().BagCount(mt[1])
                mats[#mats + 1] = P().ItemName(mt[1]) .. ((have and have > 0) and (" |cff33ff99" .. have .. "|r/" .. mt[2]) or ("×" .. mt[2]))
            end
            -- 10-20 GI-22：不是训练师教的配方，写上去哪儿弄（本阵营第一个出处的短句）
            local rr = ns.ProfRecipeBySpell and ns.ProfRecipeBySpell(st.sp)
            local srcTxt = ""
            if rr and rr[14] ~= 1 and (rr[16] or 0) > 0 then
                srcTxt = "  " .. shortSource(rr)
            elseif st.src == "vendor" then
                srcTxt = ns.L("（配方商人卖）", " (recipe from a vendor)")
            end
            local where = st.fo == 1 and ns.L("  要铁砧", "  needs anvil") or st.fo == 3 and ns.L("  要熔炉", "  needs forge") or ""
            local tip = { ns.L(st.zh, st.en), string.format(ns.L("黄 %d · 绿 %d · 灰 %d", "Yellow %d, green %d, grey %d"), st.y, st.g, st.gr),
                ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", ")),
                ns.L("次数是期望值；材料价值按商人价估算，不是拍卖行价格", "Counts are expected values; mat value uses vendor prices, not the auction house") }
            if rr and rr[14] ~= 1 then ns.ProfSourceTip(tip, rr) end
            item(nil, (here and "|cff33ff99> |r" or "") .. "|cffffd100" .. st.f .. "-" .. st.t .. "|r  |cff" .. col .. ns.L(st.zh, st.en) .. "|r ×" .. st.c .. "|cff888888" .. where .. "|r",
                (srcTxt ~= "" and (srcTxt:gsub("^%s+", "") .. "  ") or "") .. ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", ")),
                tip, { spell = st.sp, recipe = rr and rr[14] ~= 1 and rr or nil })
        end
    end
    if not p.route or #p.route == 0 then
        item(nil, ns.L("这个专业没有制作路线", "No crafting route"), ns.L("采集 / 钓鱼按地图练，看升级规划里的「顺路采集」", "Gather along your leveling route"))
    end
end

-- ---------- 配方库 ----------
local RANGES = ns.LateL({ { 0, 300, ns.L("全部", "All") }, { 1, 75, "1-75" }, { 76, 150, "76-150" }, { 151, 225, "151-225" }, { 226, 300, "226-300" } })   -- 11-09 GI-202：ns.LateL = 手动切语言后跟着换
-- 部位：InventoryType → 分组
local SLOTS = ns.LateL({
    { ns.L("全部部位", "All slots") },
    { ns.L("头", "Head"), { [1] = true } }, { ns.L("肩", "Shoulder"), { [3] = true } },
    { ns.L("胸", "Chest"), { [5] = true, [20] = true } }, { ns.L("手腕", "Wrist"), { [9] = true } },
    { ns.L("手", "Hands"), { [10] = true } }, { ns.L("腰", "Waist"), { [6] = true } },
    { ns.L("腿", "Legs"), { [7] = true } }, { ns.L("脚", "Feet"), { [8] = true } },
    { ns.L("背", "Back"), { [16] = true } },
    { ns.L("武器盾", "Weapons"), { [13] = true, [14] = true, [15] = true, [17] = true, [21] = true, [22] = true, [23] = true, [25] = true, [26] = true } },
    { ns.L("饰品戒指", "Trinket/ring"), { [2] = true, [11] = true, [12] = true } },
    { ns.L("背包", "Bags"), { [18] = true } },
    { ns.L("消耗品材料", "Non-gear"), { [0] = true } },
})
-- 能穿什么材质（5 锁 6 板 7 布 8 皮）；非护甲谁都能用
local ARMOR = { WARRIOR = { [5] = 1, [6] = 1, [7] = 1, [8] = 1 }, PALADIN = { [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
    HUNTER = { [5] = 1, [7] = 1, [8] = 1 }, SHAMAN = { [5] = 1, [7] = 1, [8] = 1 }, ROGUE = { [7] = 1, [8] = 1 },
    DRUID = { [7] = 1, [8] = 1 }, MAGE = { [7] = 1 }, PRIEST = { [7] = 1 }, WARLOCK = { [7] = 1 } }
local ARM_NAME = { [5] = { "锁甲", "Mail" }, [6] = { "板甲", "Plate" }, [7] = { "布甲", "Cloth" }, [8] = { "皮甲", "Leather" } }
local QHEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local SRC_NAME = { [1] = { "训练师", "trainer" }, [2] = { "商人卖配方", "vendor" }, [3] = { "掉落配方", "drop" }, [4] = { "声望", "reputation" },
    [5] = { "任务奖励", "quest" }, [6] = { "商人青睐兑换", "Merchant's Favor" } }
local SRC_TAG = { [1] = "c8c8c8", [2] = "33ff99", [3] = "ff8040", [4] = "c080ff", [5] = "ffd100", [6] = "66ccff" }

-- 10-20 共建 GI-22「补全图纸出处（哪个商人出售）」：每条配方挂 r[16] 出处位 + r[17] 出处（ProfRecipes.src 池下标）
-- 筛选位：1 训练师 2 商人 4 掉落 8 声望 16 任务 32 商人青睐 64 箱子；-1 = 出处未记录
local SRC_FILTERS = ns.LateL({
    { ns.L("全部出处", "Any source"), 0 }, { ns.L("商人", "Vendor"), 2 }, { ns.L("商人青睐", "Favor"), 32 },
    { ns.L("掉落", "Drop"), 4 + 64 }, { ns.L("任务", "Quest"), 16 }, { ns.L("声望", "Reputation"), 8 },
    { ns.L("训练师", "Trainer"), 1 }, { ns.L("出处未记录", "Unknown"), -1 },
})
local function hasBit(m, b)   -- 不依赖 bit 库：b 可以是几个位的和
    m = m or 0
    local p = 1
    while p <= b do
        if b % (p * 2) >= p and m % (p * 2) >= p then return true end
        p = p * 2
    end
    return false
end
local function mySide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end
-- 一条配方的出处，本阵营 / 中立在前、对面阵营在后（other = true，显示成灰色）
function ns.ProfRecipeSources(r)
    local R = ns.ProfRecipes
    local out = {}
    if not R or not R.src or type(r[17]) ~= "table" then return out end
    local side = mySide()
    for pass = 1, 2 do
        for _, ix in ipairs(r[17]) do
            local e = R.src[ix]
            local other = e and side and (e[8] == "A" or e[8] == "H") and e[8] ~= side or false
            if e and (pass == 1) ~= other then out[#out + 1] = { e = e, other = other } end
        end
    end
    return out
end
-- 法术 → 配方（冲级路线那一步要找它的出处）
local bySpell
function ns.ProfRecipeBySpell(spell)
    if not ns.ProfRecipes then return nil end
    if not bySpell then
        bySpell = {}
        for _, lst in pairs(ns.ProfRecipes.profs) do
            for _, r in ipairs(lst) do bySpell[r[1]] = r end
        end
    end
    return bySpell[spell]
end
-- 出处里第一个有坐标的（本阵营优先）→ 地图打标 + 聊天框给全部出处
function ns.ProfPinRecipeSource(r)
    local list = ns.ProfRecipeSources(r)
    local name = ns.L(r[2], r[3])
    ns.Print(ns.L("「", "") .. name .. ns.L("」出处：", " - where to get it:"))
    if #list == 0 then ns.Print(ns.L("  出处未记录", "  no source recorded")) return false end
    for _, s in ipairs(list) do ns.Print("  " .. (s.other and "|cff808080" or "") .. ns.EnSafe(ns.L(s.e[1], s.e[2])) .. (s.other and "|r" or "")) end
    for _, s in ipairs(list) do
        local e = s.e
        if not s.other and (e[5] or 0) > 0 and (e[6] or 0) > 0 then
            local ok = ns.ShowOnMap(e[5], { { e[6], e[7] } }, name)
            ns.Print(string.format("/way #%d %.1f %.1f %s", e[5], e[6], e[7], name))
            return ok
        end
    end
    return false
end
-- 11-15 教材出处：本阵营第一个有坐标的商人打地图标记，聊天框列全部（ns.ProfBooks 没收录 = 提示去拍卖行搜）
function ns.ProfPinBook(link)
    local name = link.book or ""
    local vs = link.vendors or {}
    local side = UnitFactionGroup and UnitFactionGroup("player")
    side = side == "Alliance" and "A" or side == "Horde" and "H" or nil
    ns.Print(ns.L("「", "") .. name .. ns.L("」在哪买：", " - where to buy:"))
    if #vs == 0 then ns.Print(ns.L("  出处还没收录：打开拍卖行点「搜」", "  no vendor recorded yet - try the AH")) return false end
    local pinned
    for _, v in ipairs(vs) do
        local other = side and v.side and v.side ~= "N" and v.side ~= side
        ns.Print("  " .. (other and "|cff808080" or "") .. ns.L(v.n, v.ne or v.n) .. " · " .. ns.L(v.z or "", v.ze or v.z or "")
            .. string.format(" %.1f, %.1f", v.x or 0, v.y or 0) .. (other and ns.L("（对方阵营）|r", " (other faction)|r") or ""))
        if not pinned and not other and (v.um or 0) > 0 and ns.ShowOnMap then
            pinned = ns.ShowOnMap(v.um, { { v.x, v.y } }, name) or true
        end
    end
    return pinned and true or false
end
-- 配方行副标题用的短出处（本阵营第一条；只有训练师就写训练师）
-- 鼠标提示里的「出处」段：全部出处（对方阵营灰色）+ 能打标时提示点一下
function ns.ProfSourceTip(tip, r)
    local list, pin = ns.ProfRecipeSources(r), false
    tip[#tip + 1] = "|cffffd100" .. ns.L("出处", "Where to get it") .. "|r"
    if #list == 0 then
        tip[#tip + 1] = "|cff808080" .. ns.L("出处未记录：foreverchanges 和经典数据库都没有这张图纸的来源", "No source recorded yet") .. "|r"
    end
    for _, s in ipairs(list) do
        tip[#tip + 1] = (s.other and "|cff808080" or "") .. ns.EnSafe(ns.L(s.e[1], s.e[2])) .. (s.other and (ns.L("（对方阵营）", " (other faction)") .. "|r") or "")
        if not s.other and (s.e[5] or 0) > 0 then pin = true end
    end
    -- 游戏内自己见过的（ProfSeen.lua：开商人窗口 / 拾取时记下）
    if ns.ProfSeenFor then
        for _, v in ipairs(ns.ProfSeenFor(r)) do tip[#tip + 1] = "|cff33ff99" .. ns.EnSafe(ns.ProfSeenLine(v)) .. "|r" end
    end
    if pin then tip[#tip + 1] = "|cff999999" .. ns.L("点一下：在地图上标出最近的出处，聊天框列出全部", "Click: pin the source on the map and list all in chat") .. "|r" end
    return tip
end
shortSource = function(r)
    local list = ns.ProfRecipeSources(r)
    local s = list[1]
    if not s then
        local seen = ns.ProfSeenFor and ns.ProfSeenFor(r)[1]
        if seen then return "|cff33ff99" .. ns.EnSafe(ns.ProfSeenLine(seen)) .. "|r" end
        return "|cff808080" .. ns.L("出处未记录", "source unknown") .. "|r"
    end
    local more = #list > 1 and ns.L(" 等" .. #list .. "处", " +" .. (#list - 1)) or ""
    return "|cff" .. (SRC_TAG[r[14]] or "c8c8c8") .. ns.EnSafe(ns.L(s.e[3], s.e[4])) .. more .. "|r"
end

function ns.ProfRecipeFilter(key, f, cls)
    local R = ns.ProfRecipes
    if not R or not R.profs[key] then return {}, 0 end
    local rg = RANGES[(f.range or 0) + 1] or RANGES[1]
    local slot = SLOTS[f.slot or 1] or SLOTS[1]
    local allow = ARMOR[cls or ""]
    local q = (f.q or ""):lower()
    local out, total = {}, 0
    for _, r in ipairs(R.profs[key]) do
        local sk = r[4] or r[5]
        local ok = sk >= rg[1] and sk <= rg[2]
        if ok and slot[2] then ok = slot[2][r[9]] or false end
        if ok and f.new then ok = r[13] end
        if ok and f.mine and r[10] > 0 then ok = allow == nil or allow[r[10]] ~= nil end
        local sb = SRC_FILTERS[f.src or 1] and SRC_FILTERS[f.src or 1][2] or 0
        if ok and sb ~= 0 then
            if sb == -1 then ok = (r[16] or 0) == 0 else ok = hasBit(r[16], sb) end
        end
        if ok and q ~= "" then
            ok = (r[2]:lower():find(q, 1, true) or r[3]:lower():find(q, 1, true)) and true or false
            if not ok then
                for _, mt in ipairs(r[15]) do
                    local nm = R.items[mt[1]]
                    if nm and ((nm[1] or ""):lower():find(q, 1, true) or (nm[2] or ""):lower():find(q, 1, true)) then ok = true; break end
                end
            end
            -- 出处也能搜：商人名 / 地区名（「暴风城」「塔纳利斯」→ 在那儿能买 / 能打到的图纸）
            if not ok and R.src and type(r[17]) == "table" then
                for _, ix in ipairs(r[17]) do
                    local e = R.src[ix]
                    if e and ((e[1] or ""):lower():find(q, 1, true) or (e[2] or ""):lower():find(q, 1, true)) then ok = true; break end
                end
            end
        end
        if ok then
            total = total + 1
            if #out < MAX_RECIPES then out[#out + 1] = r end
        end
    end
    return out, total
end

local function matName(id)
    local nm = ns.ProfRecipes.items[id]
    return nm and ns.L(nm[1] ~= "" and nm[1] or nm[2], nm[2] ~= "" and nm[2] or nm[1]) or tostring(id)
end

local function renderRecipes()
    local skills = P().Skills()
    pickRouteKey(skills)
    if not ns.ProfRecipes then
        item(nil, ns.L("配方库数据没加载", "Recipe data not loaded"), "")
        return
    end
    local cls = myClass()
    local lv = UnitLevel and UnitLevel("player") or 1
    local rank = skills[routeKey] and skills[routeKey].r
    local list, total = ns.ProfRecipeFilter(routeKey, flt, cls)
    local all = #(ns.ProfRecipes.profs[routeKey] or {})
    local nNew = 0
    for _, r in ipairs(ns.ProfRecipes.profs[routeKey] or {}) do if r[13] then nNew = nNew + 1 end end
    head(string.format(ns.L("%s：%d 个配方，其中《无限》新增 %d 个 · 符合筛选 %d 个", "%s: %d recipes, %d new in Forever - %d match"),
        P().Name(routeKey), all, nNew, total))
    for _, r in ipairs(list) do
        local name = ns.L(r[2], r[3])
        local col = QHEX[r[12]] or "ffffff"
        local tags = {}
        if r[13] then tags[#tags + 1] = "|cff66ccff" .. ns.L("新增", "New") .. "|r" end
        if r[11] > 0 then tags[#tags + 1] = "|cffffd100" .. ns.L("套装", "Set") .. "|r" end
        if r[10] > 0 then
            local an = ARM_NAME[r[10]]
            local wear = not ARMOR[cls or ""] or ARMOR[cls][r[10]]
            tags[#tags + 1] = (wear and "|cffc8c8c8" or "|cff808080") .. ns.L(an[1], an[2]) .. (wear and "" or ns.L("·穿不了", " (can't wear)")) .. "|r"
        end
        local learn = r[4] and string.format(ns.L("学 %d", "learn %d"), r[4]) or ns.L("学习技能未知", "learn ?")
        local here = rank and (rank >= r[6] and "808080" or rank >= r[5] and "ffff00" or rank >= (r[4] or r[5]) and "ff8040" or "c8c8c8") or "c8c8c8"
        local mats = {}
        for _, mt in ipairs(r[15]) do mats[#mats + 1] = matName(mt[1]) .. "×" .. mt[2] end
        local use = r[8] > 0 and ((r[8] <= lv and "|cff33ff99" or "|cffc8c8c8") .. string.format(ns.L("使用 %d 级", "use Lv %d"), r[8]) .. "|r") or ""
        local src = SRC_NAME[r[14]]
        if src and r[14] ~= 1 then tags[#tags + 1] = "|cff" .. (SRC_TAG[r[14]] or "c8c8c8") .. ns.L(src[1], src[2]) .. "|r" end
        local title = "|cff" .. here .. "[" .. learn .. "]|r |cff" .. col .. name .. "|r  " .. table.concat(tags, " ")
        local matTxt = ns.L("材料：", "Mats: ") .. table.concat(mats, ns.L("、", ", "))
        local colors = string.format(ns.L("黄 %d · 灰 %d", "yellow %d, grey %d"), r[5], r[6]) .. (use ~= "" and ("  " .. use) or "")
        -- 10-20 GI-22：副标题先写出处（玩家最想知道去哪儿弄图纸），材料放后面，全文在鼠标提示里
        local sub = shortSource(r) .. "  " .. matTxt
        local tip = { name, learn .. (src and ("（" .. ns.L(src[1], src[2]) .. "）") or ""), colors, matTxt,
            r[13] and ns.L("《无限》新增：经典旧世没有这个配方", "New in Forever: not in Classic") or nil }
        ns.ProfSourceTip(tip, r)
        -- 11-10 GI-218：每种材料写一句从哪来（ReagentSrc.lua，HOLD 期间没有就跳过）
        if ns.ReagentSrcTip and ns.ReagentSrcTip.Enabled() then
            local head
            for _, mt in ipairs(r[15]) do
                local s = ns.ReagentSrcTip.Short(mt[1])
                if s then
                    if not head then tip[#tip + 1] = ns.L("材料从哪来（经典旧世参考）：", "Where to get mats (Classic reference):"); head = true end
                    tip[#tip + 1] = "  " .. matName(mt[1]) .. ns.L("：", ": ") .. s
                end
            end
        end
        local ic
        if r[7] > 0 and C_Item and C_Item.GetItemIconByID then
            local ok, v = pcall(C_Item.GetItemIconByID, r[7])
            if ok then ic = v end
        end
        item(ic or icon(routeKey), title, sub, tip, { item = r[7], spell = r[1], recipe = r })
    end
    if total > #list then
        item(nil, string.format(ns.L("还有 %d 个没列出来：用上面的技能段 / 部位 / 搜索缩小范围", "%d more: narrow down with the filters above"), total - #list), "")
    end
    if total == 0 then item(nil, ns.L("没有符合的配方", "No matching recipes"), ns.L("换个筛选或搜索词", "Try other filters")) end
end

-- ---------- 营地与传承 ----------
local function renderCamp()
    local skills = P().Skills()
    local C = D().camp
    head(ns.L("营火（烹饪）", "Campfires (Cooking)"))
    for _, f in ipairs(C.fires or {}) do
        -- 10-16 实测：基础营火学初级烹饪就会，要带「燧石和火绒」+ 普通木柴；中级 / 高级营火的要求还没实测
        local need = f.tool and (ns.L("要带 ", "needs ") .. ns.L(f.tool, f.toolEn) .. (f.mat and (ns.L(" + ", " + ") .. ns.L(f.mat, f.matEn)) or "")) or ""
        -- 10-22 GI-14：中级 / 高级营火 学会 95 / 205、放下要 140 / 220（客户端 70532 物品技能要求），两个都写
        local skTx = f.use and string.format(ns.L("  烹饪 %d 学 · %d 放", "  Cooking %d learn · %d place"), f.sk, f.use) or (ns.L("  烹饪 ", "  Cooking ") .. f.sk)
        local tip = { ns.L(f.zh, f.en), string.format(ns.L("可摆 %d 件设施", "Holds %d objects"), f.cap) .. (need ~= "" and ("；" .. need) or "") }
        if f.use then tip[#tip + 1] = string.format(ns.L("烹饪 %d 点能学会，%d 点才能放下", "Learnable at Cooking %d, placeable at %d"), f.sk, f.use) end
        tip[#tip + 1] = f.ok and ns.L("已在游戏里核对过", "Verified in game") or ns.L("数值来自客户端数据，还没在游戏里核对", "From client data, not yet checked in game")
        item(icon("cooking"), ns.L(f.zh, f.en) .. skTx,
            string.format(ns.L("可摆 %d 件设施", "holds %d objects"), f.cap) .. (need ~= "" and ("　" .. need) or ""), tip)
    end
    head(ns.L("各专业的营地设施（20 / 140 / 300）", "Camp objects by profession"))
    for _, key in ipairs(P().ORDER) do
        local tiers = P().Camp(key)
        if #tiers > 0 then
            local parts = {}
            local s = skills[key]
            for _, c in ipairs(tiers) do
                parts[#parts + 1] = ((s and s.r >= c.sk) and "|cff33ff99" or "|cffc8c8c8") .. ns.L(c.zh, c.en) .. "(" .. c.sk .. ")|r"
            end
            local tip = { P().Name(key) }
            for _, c in ipairs(tiers) do tip[#tip + 1] = ns.L(c.zh, c.en) .. " " .. c.sk .. ": " .. ns.TD(ns.EnSafe(c.tx)) end
            item(icon(key), P().Name(key) .. (s and ("  |cff888888" .. s.r .. "|r") or ""), table.concat(parts, "  "), tip)
        end
    end
    head(ns.L("营地升级图纸（Beta 实测掉落）", "Camp blueprints (seen in Beta)"))
    for _, bp in ipairs(D().blueprints or {}) do
        local key = P().BlueprintProf(bp)
        local mine = key and skills[key]
        item("Interface\\Icons\\INV_Scroll_03", (mine and "|cff33ff99" or "") .. ns.L(bp.zh or bp.en, bp.en) .. (mine and "|r" or ""),
            ns.TD(bp.dun or "") .. " · " .. ns.TD(bp.boss or "") .. (key and (ns.L("  （", "  (") .. P().Name(key) .. ns.L("）", ")")) or ""))
    end
    -- 传承
    head(ns.L("传承 · 制造专业里程碑：每档账号首次 1 点", "Legacy - crafting milestones: 1 point each, once per account"))
    local got, how = 0, "ach"
    for _, key in ipairs(P().ORDER) do
        if P().CRAFT[key] then
            local parts = {}
            for _, at in ipairs({ 150, 225, 300 }) do
                local ok, h = P().LegacyClaimed(key, at)
                if h == "guess" then how = "guess" end
                if ok then got = got + 1 end
                parts[#parts + 1] = (ok and "|cff33ff99" or "|cff808080") .. at .. (ok and ns.L(" 已领", " done") or ns.L(" 未领", " open")) .. "|r"
            end
            local s = skills[key]
            item(icon(key), P().Name(key) .. (s and ("  |cffffd100" .. s.r .. "|r") or ""), table.concat(parts, "   "))
        end
    end
    item(nil, string.format(ns.L("已领 %d / 18", "%d of 18 claimed"), got),
        how == "guess" and ns.L("查不到成就时按本账号装了插件的角色技能推算", "Estimated from characters with this addon when achievements are unavailable")
        or ns.L("按成就完成状态", "From achievement status"))
    head(ns.L("传承 · 专业树（括号里是满级效果）", "Legacy - Professions tree (max rank shown)"))
    for _, pk in ipairs(D().legacy or {}) do
        item("Interface\\Icons\\INV_Misc_Book_09", ns.L(pk.zh, pk.en) .. "  |cff888888" .. ns.L("共 ", "") .. (pk.max or "?") .. ns.L(" 级", " ranks") .. "|r",
            ns.EnSafe(ns.L(pk.d or "", pk.dEn or pk.d or "")))
    end
end

-- ---------- 页面 ----------
local TOP = { pick = -98, time = -74, route = -124, recipes = -124, camp = -74 }   -- 11-09 GI-204 冲级路线多一排采集按钮
local function refresh()
    if not page or not D() then return end
    -- ⛔ P().Skills() 返回两个值，直接塞进 next() 会把第二个当成 key 报错（10-18 整页空白、按钮全叠在一起）
    -- 11-14 用户「专业快速冲级整理的更加容易找到」：第一次打开（本次登录还没点过子页）默认落在「冲级路线」（专业助手在包里时叫「专业助手」）——
    --   原来是「有专业 = 我的时刻表」。角色学了专业、或在「选专业」里规划过 → 冲级路线（专业按 pickRouteKey 挑，角色现有专业优先）；
    --   两样都没有 → 还是「选专业」（没有可冲的专业，先给建议）。时刻表 / 选专业 / 配方库 / 营地都还在，按钮一个没删，
    --   外面指定子页（ns.ProfOpenTab("recipes") 等）照旧优先
    if not tab then
        local sk = P().Skills()
        tab = next(P().PlanSkills(sk)) and "route" or "pick"
    end
    for k, b in pairs(page.tabBtns) do markSel(b, k == tab) end
    page.pickBtn:SetShown(tab == "pick"); page.unpickBtn:SetShown(tab == "pick" and P().Planned() ~= nil)
    local rk = tab == "route" or tab == "recipes"
    if rk then pickRouteKey(P().Skills(), tab == "route") end
    for k, b in pairs(page.routeBtns) do b:SetShown(rk and not (IS_GATHER[k] and tab ~= "route")); markSel(b, k == routeKey) end
    if tab == "recipes" and IS_GATHER[routeKey] then routeKey = nil; pickRouteKey(P().Skills(), false); for k, b in pairs(page.routeBtns) do markSel(b, k == routeKey) end end
    for i, b in ipairs(page.rangeBtns) do b:SetShown(tab == "recipes"); markSel(b, i - 1 == flt.range) end
    page.slotBtn:SetShown(tab == "recipes"); page.slotBtn:SetText(SLOTS[flt.slot][1])
    page.newBtn:SetShown(tab == "recipes"); markSel(page.newBtn, flt.new)
    page.mineBtn:SetShown(tab == "recipes"); markSel(page.mineBtn, flt.mine)
    page.srcBtn:SetShown(tab == "recipes"); page.srcBtn:SetText(SRC_FILTERS[flt.src or 1][1]); markSel(page.srcBtn, (flt.src or 1) ~= 1)
    page.search:SetShown(tab == "recipes")
    if ns.ProfAssistRefresh then ns.ProfAssistRefresh(page, tab) end
    local top = TOP[tab] or -98
    -- 11-12 GI-238「滚动到下面 每隔一秒就会自动重置回到顶部」：Prof.lua 的 SKILL_LINES_CHANGED / TRADE_SKILL_LIST_UPDATE
    --   一来就整页重画，以前每次都把滚动条拉回 0。现在只有换了子页 / 专业 / 筛选才回顶部，同一视图重画保住位置（夹在新内容高度内）
    local vk = table.concat({ tostring(tab), tostring(routeKey), tostring(flt.range), tostring(flt.slot), tostring(flt.new),
        tostring(flt.mine), tostring(flt.q or ""), tostring(flt.src or 1) }, "\1")
    local keep = 0
    if vk == page.viewKey and page.sf.GetVerticalScroll then keep = tonumber(page.sf:GetVerticalScroll()) or 0 end
    page.viewKey = vk
    local sfH = 474 + top - 12
    page.sf:ClearAllPoints()
    page.sf:SetPoint("TOPLEFT", 6, top)
    page.sf:SetSize(616, sfH)
    for _, r in ipairs(page.rows) do r:Hide() end
    y, n = -2, 0
    if tab == "pick" then renderPick() elseif tab == "time" then renderTime() elseif tab == "route" then renderRoute()
    elseif tab == "recipes" then renderRecipes() else renderCamp() end
    page.child:SetHeight(-y + 4)
    if page.sf.UpdateScrollChildRect then page.sf:UpdateScrollChildRect() end
    if page.sf.SetVerticalScroll then page.sf:SetVerticalScroll(math.max(0, math.min(keep, (-y + 4) - sfH))) end
end
ns.RefreshProfPage = refresh

-- 11-14「按键美化」：页面里的按钮一律扁平分段样式；20 高的筛选行用小一号字（「151-225」这种原来被挤出按钮）
local function pbtn(parent, text, w, h, onClick)
    local b = (ns.SegButton or ns.Button)(parent, text, w, h, onClick)
    if h and h <= 20 and rawget(b, "_segFs") and b._segFs.SetFontObject then b._segFs:SetFontObject("GameFontNormalSmall") end
    return b
end

local function build(p)
    page = p
    ns.ProfPage = p   -- 测试用
    p.rows = {}
    ns.PageHeader(p, ns.L("专业", "Professions"),
        ns.L("边练级边练专业：选专业、路线上的训练和采集门槛、配方库", "Level your professions while you level: picks, route timeline, recipes"))
    p.tabBtns = {}
    local x = 12
    -- 11-14 用户「专业快速冲级整理的更加容易找到」：「冲级路线 / 专业助手」挪到第一个、按钮加宽，左边多一个路线地图小图标 + 悬停说明
    --   （不管选没选中都比别的显眼；按钮文字本身不加颜色码，别处 / 测试按 text 认这个按钮）；
    --   其余四个照原顺序排在后面、各窄 6（5 个总宽 132 + 4 × 106 + 间距 = 572，仍在 616 内容区里）。子页一个没删
    for _, t in ipairs({ { "route", ns.ProfAssist and ns.L("专业助手", "Assistant") or ns.L("冲级路线", "Route"), 132, true },
        { "pick", ns.L("选专业", "Choose") }, { "time", ns.L("我的时刻表", "Timeline") },
        { "recipes", ns.L("配方库", "Recipes") }, { "camp", ns.L("营地与传承", "Camp & Legacy") } }) do
        local w = t[3] or 106
        local b = pbtn(p, t[2], w, 22, function() tab = t[1]; refresh() end)
        b:SetPoint("TOPLEFT", x, -42); x = x + w + 4
        if t[4] then
            local ic = b:CreateTexture(nil, "OVERLAY")
            ic:SetSize(16, 16); ic:SetPoint("LEFT", 6, 0)
            ic:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
            if ic.SetTexCoord then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            b._giIcon = ic   -- 测试用
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(t[2], 1, 0.82, 0)
                GameTooltip:AddLine(ns.L("从你现在的技能等级一路冲到 300：每一段做什么、要多少材料、去哪学",
                    "Your route to 300 from where you are: what to craft, mats needed, where to train"), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        p.tabBtns[t[1]] = b
    end
    -- 选专业：按这套规划 / 取消
    p.pickBtn = pbtn(p, ns.L("按这套规划", "Plan these"), 120, 22, function()
        local list = {}
        for _, k in ipairs(P().PICK) do list[#list + 1] = k end
        P().SetPlanned(list); refresh()
    end)
    p.pickBtn:SetPoint("TOPLEFT", 12, -70)
    p.unpickBtn = pbtn(p, ns.L("取消规划", "Clear plan"), 100, 22, function() P().SetPlanned(nil); refresh() end)
    p.unpickBtn:SetPoint("LEFT", p.pickBtn, "RIGHT", 6, 0)
    -- 冲级路线 / 配方库：专业
    p.routeBtns = {}
    -- 11-15 用户截图「加上专业图标」「注意对齐」：按钮左边加专业图标（14px），文字跟着右挪；两排同一套 76px 格子，上下列对齐
    local function withIcon(b, k)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(14, 14); t:SetPoint("LEFT", b, "LEFT", 5, 0)
        t:SetTexture(icon(k)); t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.pic = t
        -- 文字整体右挪 8px 给图标让位（扁平按钮按下时自己把文字设回正中 +1/-1，这里跟在它后面再挪回来）
        local fs = rawget(b, "_segFs") or (b.GetFontString and b:GetFontString())
        if fs then
            fs:ClearAllPoints(); fs:SetPoint("CENTER", 8, 0)
            if b.HookScript then
                b:HookScript("OnMouseDown", function() fs:ClearAllPoints(); fs:SetPoint("CENTER", 9, -1) end)
                b:HookScript("OnMouseUp", function() fs:ClearAllPoints(); fs:SetPoint("CENTER", 8, 0) end)
            end
        end
        return b
    end
    local function row(keys, yy)
        for i, k in ipairs(keys) do
            local b = withIcon(pbtn(p, P().Name(k), 74, 20, function() routeKey = k; refresh() end), k)
            b:SetPoint("TOPLEFT", 12 + (i - 1) * 76, yy)
            p.routeBtns[k] = b
        end
    end
    row(ROUTE_KEYS, -70)
    row(GATHER_KEYS, -96)
    -- 配方库筛选：技能段 / 部位 / 只看新增 / 我能穿 / 搜索
    p.rangeBtns = {}
    x = 12
    for i, rg in ipairs(RANGES) do
        local b = pbtn(p, rg[3], i == 1 and 40 or 58, 20, function() flt.range = i - 1; refresh() end)
        b:SetPoint("TOPLEFT", x, -96); x = x + (i == 1 and 42 or 60)
        p.rangeBtns[i] = b
    end
    p.slotBtn = pbtn(p, SLOTS[1][1], 70, 20, function() flt.slot = flt.slot % #SLOTS + 1; refresh() end)
    p.slotBtn:SetPoint("TOPLEFT", x + 2, -96); x = x + 74
    p.slotBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("部位：点一下换下一个", "Slot: click to cycle"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.slotBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.newBtn = pbtn(p, ns.L("新增", "New"), 46, 20, function() flt.new = not flt.new; refresh() end)
    p.newBtn:SetPoint("TOPLEFT", x, -96); x = x + 48
    p.newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("只看《无限》新增的配方", "Only recipes new in Forever"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.mineBtn = pbtn(p, ns.L("我能穿", "Wearable"), 56, 20, function() flt.mine = not flt.mine; refresh() end)
    p.mineBtn:SetPoint("TOPLEFT", x, -96); x = x + 58
    -- 10-20 GI-22：按出处筛（商人 / 商人青睐 / 掉落 / 任务 / 声望 / 训练师 / 未记录），点一下换下一个，右键回到全部
    p.srcBtn = pbtn(p, SRC_FILTERS[1][1], 76, 20, function() flt.src = (flt.src or 1) % #SRC_FILTERS + 1; refresh() end)
    p.srcBtn:SetPoint("TOPLEFT", x, -96); x = x + 78
    if p.srcBtn.RegisterForClicks then p.srcBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local leftClick = p.srcBtn:GetScript("OnClick")
    p.srcBtn:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then flt.src = 1; refresh() elseif leftClick then leftClick(self, btn) end
    end)
    p.srcBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L("出处：点一下换下一个，右键回到全部", "Source: click to cycle, right-click to reset"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("搜索框也能搜商人名 / 地区名", "The search box also matches vendor and zone names"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.srcBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.search:SetSize(612 - x, 20); p.search:SetPoint("TOPLEFT", x + 6, -96); p.search:SetAutoFocus(false)
    p.search:SetScript("OnTextChanged", function(self, user)
        if user == false then return end
        flt.q = self:GetText() or ""
        refresh()
    end)
    p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L("搜配方名、材料名、商人名或地区", "Search recipe, material, vendor or zone"), 1, 0.82, 0); GameTooltip:Show()
    end)
    p.search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if ns.ProfAssistBuild then ns.ProfAssistBuild(p, refresh) end
    local sf, c = ns.Scroll(p, 6, -98, 616, 474 - 98 - 12)
    p.sf, p.child = sf, c
end

-- 外面跳进来：/gi prof 选专业 等
-- 11-15 行上「买 / 搜 / 在哪」按钮的文字跟着商人 / 拍卖行开关变：开关时页面开着就重画一次
do
    local sev = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(sev.RegisterEvent, sev, e) end
    sev:SetScript("OnEvent", function()
        if page and page.IsVisible and page:IsVisible() and C_Timer and C_Timer.After then
            C_Timer.After(0.2, function() if page:IsVisible() then pcall(refresh) end end)
        end
    end)
end
function ns.ProfOpenTab(t)
    tab = t
    if page and page.IsVisible and page:IsVisible() then refresh(); return end
    if ns.ToggleMain then ns.ToggleMain("prof") end
    refresh()
end
-- 11-23 用户「制造的也直接打开专业配方」：成品物品 → 配方库，切到那个专业、清筛选、搜索框填配方名；返回 专业键, 配方法术（找不到 nil）
function ns.ProfOpenRecipe(id)
    for k, lst in pairs(ns.ProfRecipes and ns.ProfRecipes.profs or {}) do
        for _, r in ipairs(lst) do
            if r[7] == id then
                routeKey = k
                flt.range, flt.slot, flt.new, flt.mine, flt.src, flt.q = 0, 1, false, false, 1, ns.L(r[2], r[3])
                ns.ProfOpenTab("recipes")
                if page and page.search then page.search:SetText(flt.q) end
                return k, r[1]
            end
        end
    end
end

-- 11-14 order 1.85 → 1.15：专业成了左栏独立一级，排在「升级」(1.1) 后、「装备」(1.2) 前（UI.lua GROUPS）；⛔ 和 ProfStub.lua 的占位页一致
ns.RegisterPage({ key = "prof", order = 1.15, title = ns.L("专业", "Professions"), tabTitle = ns.L("专业", "Profs"),
    icon = "Interface\\Icons\\Trade_BlackSmithing", hold = true, build = build, refresh = refresh })

-- 「窗口与提醒」（11-17）：开商人 / 拍卖行自己弹的专业购买窗口，「不再弹」关掉的从这里找回
--   ⛔ 本子插件按需加载 → 没加载时主插件 ProfStub.lua 要有同 key 占位（见回报）
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "profShop", order = 71, title = function() return ns.L("专业购买窗口（开商人 / 拍卖行时）", "Profession shopping window") end,
        state = function() return Shop.QuickOn() and ns.L("开商人 / 拍卖行时弹出", "Pops up at merchants / the AH") or ns.L("已关闭（/gi 专业购买 仍能打开）", "Closed") end,
        actions = function()
            local on = Shop.QuickOn() and true or false
            return { { text = on and ns.L("关闭", "Turn off") or ns.L("打开", "Turn on"), fn = function()
                Shop.SetQuick(not on)
                if on then
                    if Shop.qf then Shop.qf:Hide() end
                    Shop.NeverHint()
                end
            end } }
        end })
end
