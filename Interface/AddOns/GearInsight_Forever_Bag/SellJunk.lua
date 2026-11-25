-- 商人处「卖垃圾」（11-15 用户「卖垃圾的怎么调出来，可以卖的时候自动挂出来吗」）
--   ① 打开商人窗口（MERCHANT_SHOW）→ 在商人窗口右边挂一个「卖垃圾」小面板（父 = UIParent，只用 SetPoint 锚到 MerchantFrame 右上角；
--        ⛔ 不改暴雪 MerchantFrame 的脚本，只 HookScript OnHide 兜底）；关商人（MERCHANT_CLOSED / MerchantFrame 隐藏）面板跟着收起
--        面板：列出可卖的物品（图标 + 名字 ×数量 + 商人回收总价，最贵的在上）、合计、大按钮「一键卖」、刚卖了多少钱
--   ② 列哪些（扫描 / 排除 / 价格复用 Trash.lua 的 T.SlotInfo / T.ItemInfo / T.IsQuestSlot / T.SkipReason）：
--        默认只列灰色（粗糙）且商人回收价 > 0；面板勾「白色装备也卖」→ 再加白色的武器 / 护甲（classID 2 / 4；白色材料、食物、布料不卖）
--        排除：Trash 的全部排除规则（不摧毁名单 / 任务物品 / 炉石 / 工具 / 灵魂碎片 / 背包 / 钥匙 / 施法材料 / 弹药 / 坐骑…）+ 锁定中 + 卖不了钱（hasNoValue / 回收价 0）
--        价格只用商人回收价（GetItemInfo 第 11 个返回值），不用拍卖价 —— 这里是卖给商人
--   ③ 卖：⛔ 只有玩家点「一键卖」才卖（自动卖灰另有开关、默认关）。每次点击最多卖 S.BATCH = 12 件
--        （商人「购回」页正好只保留最近 12 件 → 一批里卖错的都能买回；也避免一次性连发几十个请求被服务器节流）
--        卖 = C_Container.UseContainerItem(bag, slot)（老客户端退回 UseContainerItem）：商人窗口开着时右键背包物品就是卖
--        卖之前重读那一格：物品 / 数量变了、锁着 → 跳过；交易 / 邮箱 / 银行窗口同时开着 → 不卖（UseContainerItem 会变成放进交易栏 / 存银行）；战斗中不卖
--        卖完聊天框 + 面板写「已卖 N 件，获得 X」（金额 = 回收价 × 数量之和）
--   ④ 设置（ns.RegisterSettings，挂在「清背包」页的「本页设置」）存 ns.db.sellJunk（nil = 默认）：
--        panel 打开商人时显示卖垃圾面板（默认开）· auto 打开商人时自动卖灰色（默认关；只卖灰色，一批 12 件、隔 0.6 秒再卖下一批，购回页可撤）· white 白色装备也卖（默认关）
--   ⑤ 清背包页底部加一行说明 + 右上角「卖垃圾」按钮；命令 /gi 卖 | /gi sell（商人开着时打开面板，没开时提示去找商人）
--   ⑥ 11-15 用户实测截图（一键卖了 4 件灰色能用）后「主要是列出来，我点一个卖一个，按照价值从低到高排列，不分品质」：
--        列表改成背包里所有商人肯收钱的物品（不分品质，排除规则照旧），按总价从低到高排，滚轮翻页；点一行卖那一格；
--        绿色及以上点两下才卖（第一下行尾变「再点一次卖」，3 秒内再点）。「一键卖」改成只卖灰色（一批 12 件）；去掉「白色也卖」
--   ⑦ 11-16 用户「AH插件比排序，以及绝对卖价排序两种排序可切换」：面板右上「排序」按钮在两种之间切，记在 ns.db.sellJunk.sort
--        value = 按商人回收总价从低到高（原来的）；ah = 按拍卖比商店从低到高（最该卖商店的在上：拾取绑定 → 拍卖比 % 低 → 高，
--        拍卖插件没数据的排最后、它们之间按总价）；没装 Auctionator / 一件都没数据时提示一行，仍按总价排
--   11-17 用户「模块做好按需加载」：本文件搬进按需加载的子插件 GearInsight_Forever_Bag，登录不加载（主插件 BagStub.lua 放命令占位 / 外壳）：
--        开商人（面板 / 自动卖灰开着）、背包上的「卖垃圾」按钮、/gi 卖 时才加载。商人窗口开关事件、设置描述 + 存档读写（ns.SellCfg）、
--        物品提示上的「拍卖比商店」一行（ns.SellAH）留在 BagStub.lua 常驻；这里不再自己注册 MERCHANT_SHOW / MERCHANT_CLOSED（BagStub 转过来，免得合并包里调两次）
--        ⛔ 这个文件晚于主插件加载：文件头 ns = _G.GearInsightForever or ns
--   11-17 用户截图「重合了，优化一下，是不是应该整合到一个」：面板不再自己当外框，改成主插件「商人助手」（MerchantDock.lua）里的「卖垃圾」页签；
--        标题栏 / × / 「不再弹」/ 位置都归外框，这里只画内容（排序按钮挪到内容第一行右边）。「不再弹」= 关「打开商人时显示卖垃圾面板」（ns.db.sellJunk.panel）
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end

local S = { sold = {}, list = {}, hidden = {} }
ns.SellJunk = S
S.BATCH = 12          -- 每次点击最多卖几件（= 商人购回页的格数）
S.MAX_ROWS = 14       -- 面板上一屏列几行（滚轮翻页）
S.CONFIRM_SEC = 3     -- 绿色及以上：两次点击间隔不超过几秒才算确认
S.GONE_SEC = 3        -- 刚卖掉的格子：背包事件还没到时别再列出来
S.AUTO_GAP = 0.6      -- 自动卖灰：两批之间隔多久
S.AUTO_MAX = 10       -- 自动卖灰：一次开商人最多卖几批
S.WHITE_CLASS = { [2] = true, [4] = true }   -- 白色只卖武器 / 护甲
S.BLOCK_FRAMES = { "TradeFrame", "SendMailFrame", "MailFrame", "BankFrame", "GuildBankFrame" }
S.VERIFY_SEC = 1.0    -- 11-20 卖完隔多久回头看那一格：东西还在、没锁 = 游戏没接受这次出售 → 聊天框说原因
S.VERIFY_MAX = 3      -- 那一格还锁着（服务器还没回话）最多再看几次
S.OUR_ADDONS = { GearInsight_Forever_Bag = true, GearInsight_Forever = true }   -- 合并包 / 网易DD 包里本文件折进主文件夹

-- ---------- 小工具 ----------
local function now() return (GetTime and GetTime()) or 0 end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local function combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function after(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
local function rg(t, k) return type(t) == "table" and rawget(t, k) or nil end
local function shown(name)
    local f = rawget(_G, name)
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, v = pcall(f.IsShown, f)
    return ok and v and true or false
end
local function T() return ns.Trash end
local function money(c)
    local t = T()
    if t and t.Money then return t.Money(c) end
    return tostring(math.floor(tonumber(c) or 0)) .. L("铜", "c")
end
S.Money = money

-- ---------- 设置（ns.db.sellJunk；nil = 默认值）：读写在主插件 BagStub.lua 的 ns.SellCfg ----------
local C = ns.SellCfg
S.DEFAULTS = C.DEFAULTS
S.DB = C.DB
S.Opt = C.Opt
function S.Sort()
    return S.Opt("sort") == "ah" and "ah" or "value"
end
function S.SetSort(m)
    if not ns.db then return end
    m = (m == "ah") and "ah" or "value"
    S.DB().sort = (m ~= S.DEFAULTS.sort) and m or nil
    S.off = 0
    if S.PanelShown() then S.Refresh() end
end
function S.ToggleSort() S.SetSort(S.Sort() == "ah" and "value" or "ah") end
function S.SetOpt(k, v) C.SetOpt(k, v) end   -- 关面板 → 收起、刷新：BagStub.lua 的 onSet 做

-- ---------- 商人窗口状态 ----------
-- 11-20 用户截图「点了为啥卖不掉」：原来「在商人处」必须 MerchantFrame:IsShown()，商人窗口被别的插件换掉 / 藏起来时就成了「没开商人」。
--   现在三路任一说开着就算：游戏的交互状态（C_PlayerInteractionManager，有就问）· MERCHANT_SHOW / CLOSED 事件记的（本文件 + BagStub）· MerchantFrame 显示着；
--   ⛔ 防误用：游戏明说没在跟商人交互、MerchantFrame 也没显示 → 记的状态过期了，不卖（不在商人处 UseContainerItem = 吃掉 / 用掉物品）
function S.Interacting()
    local pim, en = rawget(_G, "C_PlayerInteractionManager"), rawget(_G, "Enum")
    local kind = type(en) == "table" and type(en.PlayerInteractionType) == "table" and en.PlayerInteractionType.Merchant or nil
    if type(pim) ~= "table" or type(pim.IsInteractingWithNpcOfType) ~= "function" or kind == nil then return nil end
    local ok, v = pcall(pim.IsInteractingWithNpcOfType, kind)
    if not ok or v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v and true or false
end
function S.AtMerchant()
    local im = S.Interacting()
    if im then return true end
    -- 面板 / 自动卖都关着时开商人不加载本文件 → 看 BagStub 记的（它要求 MerchantFrame 显示着）
    local flag = S.merchant or S.evOpen or (ns.BagAtMerchant and ns.BagAtMerchant()) or false
    if not flag then return false end
    if im == false and not shown("MerchantFrame") then return false end
    return true
end
function S.Blocked()
    for _, n in ipairs(S.BLOCK_FRAMES) do
        if shown(n) then return n end
    end
    return nil
end

-- ---------- 扫描 ----------
-- grayOnly = true：只看灰色（自动卖灰用，不管「白色也卖」）
function S.Eligible(q, classID, grayOnly)
    q = q or 1
    if grayOnly then return q == 0 end
    return true   -- 11-15 不分品质：商人肯收钱的都列（排除规则在 Scan 里照旧）
end
-- 拍卖比排序的键：拾取绑定 = 最该卖商店（-inf）；没数据 = 排最后（nil）
function S.AHKey(e)
    local c = e.cmp
    if not c then return nil end
    if c.bop then return -math.huge end
    return c.pct
end
function S.LessAH(a, b)
    local ka, kb = S.AHKey(a), S.AHKey(b)
    if ka ~= kb then
        if ka == nil then return false end
        if kb == nil then return true end
        return ka < kb
    end
    return S.Less(a, b)
end
function S.Less(a, b)
    if a.total ~= b.total then return a.total < b.total end   -- 11-15 按价值从低到高
    if a.q ~= b.q then return (a.q or 0) < (b.q or 0) end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end
function S.Scan(grayOnly)
    local list, hidden = {}, {}
    local tr = T()
    S.loading = 0
    if not tr then S.list, S.hidden = list, hidden; return list, hidden end
    local t = now()
    for bag = 0, tr.NumBags() do
        for slot = 1, tr.NumSlots(bag) do
            local s = tr.SlotInfo(bag, slot)
            local g = S.sold[bag .. ":" .. slot]
            if s and g and g.id == s.id and t - g.t < S.GONE_SEC then s = nil end   -- 刚卖掉，背包事件还没到
            if s then
                local info = tr.ItemInfo(s.id)
                local q = s.q
                if not q or q < 0 then q = info.q end
                if not info.known then
                    S.loading = S.loading + 1
                elseif S.Eligible(q, info.classID, grayOnly) then
                    local unit = s.noValue and 0 or (tonumber(info.sell) or 0)
                    local e = { bag = bag, slot = slot, id = s.id, count = s.count or 1, locked = s.locked, link = s.link or info.link,
                        name = info.name, q = q, icon = s.icon or info.icon, classID = info.classID, subID = info.subID, known = true,
                        quest = tr.IsQuestSlot(bag, slot), unit = unit, src = "v" }
                    e.total = unit * e.count
                    e.cmp = S.Compare and S.Compare(e.id) or nil
                    local why = tr.SkipReason(e)
                    if not why and unit <= 0 then why = "novalue" end
                    if why then hidden[why] = (hidden[why] or 0) + 1 else list[#list + 1] = e end
                end
            end
        end
    end
    S.ahN = 0
    for _, e in ipairs(list) do if e.cmp and not e.cmp.bop then S.ahN = S.ahN + 1 end end
    table.sort(list, (S.Sort() == "ah" and S.ahN > 0) and S.LessAH or S.Less)
    S.list, S.hidden = list, hidden
    return list, hidden
end
function S.Total(list)
    local n, c = 0, 0
    for _, e in ipairs(list or S.list) do n = n + 1; c = c + (e.total or 0) end
    return n, c
end
function S.HiddenText()
    local n, parts = 0, {}
    local tr = T()
    for k, c in pairs(S.hidden) do
        n = n + c
        local txt = (k == "novalue") and L("卖不了钱", "no value") or (tr and tr.ReasonText and tr.ReasonText(k)) or k
        parts[#parts + 1] = txt .. " " .. c
    end
    if n == 0 then return "" end
    table.sort(parts)
    return string.format(L("没列出 %d 件：", "%d not listed: "), n) .. table.concat(parts, L("、", ", "))
end

-- ---------- 卖 ----------
function S.UseFunc()
    local C = rawget(_G, "C_Container")
    if type(C) == "table" and type(C.UseContainerItem) == "function" then return C.UseContainerItem, "C_Container.UseContainerItem" end
    local f = rawget(_G, "UseContainerItem")
    if type(f) == "function" then return f, "UseContainerItem" end
    return nil, nil
end
local function useItem(bag, slot)
    local f = S.UseFunc()
    if type(f) ~= "function" then return false, "nofunc" end
    local ok, err = pcall(f, bag, slot)
    return ok, err
end
-- 卖一格；返回 true / false, 原因（none / changed / locked / api / protected）
--   11-20：卖的那一下游戏要是发了 ADDON_ACTION_BLOCKED / FORBIDDEN（同步发，见 S.ev）→ 算没卖（protected），不再当成卖掉了
function S.SellOne(e)
    local tr = T()
    if not (tr and e) then return false, "none" end
    local s = tr.SlotInfo(e.bag, e.slot)
    if not s or s.id ~= e.id or (s.count or 1) ~= (e.count or 1) then return false, "changed" end
    if s.locked then return false, "locked" end
    S.selling, S.blockedNow = true, nil
    local ok, err = useItem(e.bag, e.slot)
    S.selling = false
    if not ok then S.apiErr = err and tostring(err) or nil; return false, "api" end
    if S.blockedNow then return false, "protected" end
    S.sold[e.bag .. ":" .. e.slot] = { id = e.id, t = now() }
    return true
end
-- 11-20 用户截图「点了为啥卖不掉」：原来 SellOne 没卖成时什么都不说，玩家只看到「点了没反应」→ 每种原因一句人话
local FAIL = {
    none = { "这一行没有物品了，列表已刷新", "Nothing in that row - list refreshed" },
    changed = { "这一格物品变了，列表已刷新，再点一次", "That slot changed - list refreshed, click again" },
    locked = { "物品被锁定（可能正在移动 / 交易，或上一下还在卖），稍等再点", "Item is locked (moving / trading / still selling) - wait a moment and click again" },
    api = { "游戏的出售接口调用失败，这次没卖：请直接右键背包里的这件物品卖", "The sell call failed - right-click the item in your bags to sell it" },
    protected = { "游戏把这次出售当成插件越权操作拦下了，这次没卖：请直接右键背包里的这件物品卖", "The game blocked the addon's sell call - right-click the item in your bags to sell it" },
}
S.DIAG_HINT = { "（还不行：输入 /gi 卖 诊断 ，把聊天框截图发我们）", " (still stuck? type /gi sell diag and send us a screenshot)" }
function S.FailText(r, e)
    local t = FAIL[r]
    local txt = t and L(t[1], t[2]) or tostring(r)
    local name = e and (e.link or e.name)
    if name then txt = tostring(name) .. L(" 没卖掉：", " not sold: ") .. txt end
    if r == "api" or r == "protected" then txt = txt .. L(S.DIAG_HINT[1], S.DIAG_HINT[2]) end
    return "|cffff8040" .. txt .. "|r"
end
-- 卖完回头看：那一格东西还在、数量没变、也没锁着 = 游戏没接受（服务器拒了 / 被别的插件或客户端拦了）→ 说原因、撤掉「已卖」的金额
--   还锁着 = 服务器还没回话，过一会儿再看（最多 S.VERIFY_MAX 次）
function S.Verify(list, tries)
    if not list or #list == 0 then return end
    tries = tries or 1
    local tok, at = S.visit, now()
    after(S.VERIFY_SEC, function()
        if S.visit ~= tok then return end   -- 商人关了 / 又开了一次：不管了
        local tr = T()
        if not tr then return end
        local fail, pending = {}, {}
        for _, e in ipairs(list) do
            local s = tr.SlotInfo(e.bag, e.slot)
            if s and s.id == e.id and (s.count or 1) == (e.count or 1) then
                if s.locked then pending[#pending + 1] = e else fail[#fail + 1] = e end
            end
        end
        if #pending > 0 and tries < S.VERIFY_MAX then S.Verify(pending, tries + 1) end
        if #fail == 0 then return end
        local c = 0
        for _, e in ipairs(fail) do S.sold[e.bag .. ":" .. e.slot] = nil; c = c + (e.total or 0) end
        S.visitN = math.max(0, (S.visitN or 0) - #fail)
        S.visitMoney = math.max(0, (S.visitMoney or 0) - c)
        S.last = nil
        local why = (S.uiErr and S.uiErr.t >= at - 0.05) and S.uiErr.msg or nil
        why = why and string.format(L("（游戏提示：%s）", " (game says: %s)"), why) or L("（游戏没给原因）", " (no reason given)")
        local what = (#fail == 1) and tostring(fail[1].link or fail[1].name) or string.format(L("%d 件物品", "%d item(s)"), #fail)
        S.lastFail = "verify" .. why
        ns.Print("|cffff6060" .. string.format(L("%s 没卖掉：游戏没有接受这次出售%s。可以直接右键背包里的物品卖", "%s not sold: the game didn't accept the sale%s. Right-click it in your bags to sell"),
            what, why) .. "|r" .. L(S.DIAG_HINT[1], S.DIAG_HINT[2]))
        S.Refresh()
    end)
end
-- 能不能卖：返回 nil = 能 / 原因（merchant / combat / blocked）
function S.CanSell()
    if not S.AtMerchant() then return "merchant" end
    if combat() then return "combat" end
    if S.Blocked() then return "blocked" end
    return nil
end
local WHY = {
    merchant = { "先打开商人窗口再卖（跟任意商人对话）；商人窗口明明开着还这样：输入 /gi 卖 诊断 截图发我们", "Open a merchant first (it is open? type /gi sell diag and send us a screenshot)" },
    combat = { "战斗中不卖，脱战再来", "Not in combat" },
    blocked = { "交易 / 邮箱 / 银行窗口开着，先关掉再卖（不然物品会被放进那些窗口）", "Close trade / mail / bank first" },
}
function S.WhyText(k) local t = WHY[k]; return t and L(t[1], t[2]) or tostring(k) end
-- 卖一批（最多 n 件）；返回 卖掉的件数, 获得的铜
function S.SellBatch(n, grayOnly, quiet)
    local why = S.CanSell()
    if why then
        if not quiet then ns.Print(S.WhyText(why)) end
        return 0, 0, why
    end
    S.Scan(grayOnly)
    local cnt, got, fails, firstFail, firstE = 0, 0, 0, nil, nil
    local soldList = {}
    if ClearCursor and CursorHasItem and CursorHasItem() then ClearCursor() end   -- 光标上拿着东西时右键会变成交换
    for _, e in ipairs(S.list) do
        if cnt >= (n or S.BATCH) then break end
        local ok, r = S.SellOne(e)
        if ok then cnt = cnt + 1; got = got + (e.total or 0); soldList[#soldList + 1] = e
        else
            fails = fails + 1
            if not firstFail then firstFail, firstE = r, e end
            if r == "protected" or r == "api" then break end   -- 游戏拦了 / 接口坏了：后面的也一样，别连发
        end
    end
    S.visitN, S.visitMoney = (S.visitN or 0) + cnt, (S.visitMoney or 0) + got
    if cnt > 0 then S.last = { n = cnt, c = got } end
    if firstFail then S.lastFail = firstFail end
    -- 11-20：一件都没卖成且有原因 → 说出来（自动卖灰 quiet 时也说：游戏拦了玩家得知道）
    if cnt == 0 and firstFail then ns.Print(S.FailText(firstFail, firstE)) end
    S.Verify(soldList)
    local left = #(S.Scan(grayOnly))   -- 卖完还剩几件（刚卖掉的按 S.sold 不再列）
    S.Refresh()
    return cnt, got, nil, left, firstFail, fails
end
function S.ClickSell()
    local cnt, got, why, left, fail = S.SellBatch(S.BATCH, true)   -- 11-15 一键只卖灰色
    if why then return cnt, got, why end
    if cnt == 0 and fail then return cnt, got, fail end   -- 原因 SellBatch 已经打印
    if cnt == 0 then
        ns.Print(L("没有灰色物品可以一键卖了", "No grey items left"))
    else
        ns.Print(string.format(L("已卖 %d 件，获得 %s%s（卖错了：商人窗口「购回」页可买回最近 12 件）", "Sold %d item(s) for %s%s (buy back from the merchant's Buyback tab)"),
            cnt, money(got), left > 0 and string.format(L("，还剩 %d 件，再点一次继续", ", %d left - click again"), left) or ""))
    end
    return cnt, got
end

-- 11-15 点一行卖那一格：绿色及以上要点两下（3 秒内）
function S.ConfirmKey(e) return e and (e.bag .. ":" .. e.slot .. ":" .. tostring(e.id)) or nil end
function S.Confirming(e)
    local c = S.confirm
    return c ~= nil and c.key == S.ConfirmKey(e) and now() - c.t <= S.CONFIRM_SEC
end
function S.ClickRow(e)
    if not e then return false, "none" end
    local why = S.CanSell()
    if why then ns.Print(S.WhyText(why)); return false, why end
    if (e.q or 1) >= 2 and not S.Confirming(e) then
        S.confirm = { key = S.ConfirmKey(e), t = now() }
        S.RefreshUI()
        return false, "confirm"
    end
    S.confirm = nil
    if ClearCursor and CursorHasItem and CursorHasItem() then ClearCursor() end
    local ok, r = S.SellOne(e)
    if not ok then
        S.lastFail = r
        ns.Print(S.FailText(r, e))   -- 11-20 原来这里不说话 → 玩家只看到「点了没反应」
        S.Refresh()
        return false, r
    end
    S.visitN, S.visitMoney = (S.visitN or 0) + 1, (S.visitMoney or 0) + (e.total or 0)
    S.last = { n = 1, c = e.total or 0, link = e.link or e.name, count = e.count or 1 }
    ns.Print(string.format(L("已卖 %s%s，获得 %s", "Sold %s%s for %s"), tostring(e.link or e.name), (e.count or 1) > 1 and (" ×" .. e.count) or "", money(e.total)))
    S.Verify({ e })
    S.Refresh()
    return true
end
function S.Scroll(delta)
    local n = #S.list
    local maxOff = math.max(0, n - S.MAX_ROWS)
    S.off = math.max(0, math.min(maxOff, (S.off or 0) + (delta or 0) * 3))
    S.RefreshUI()
end
function S.GreyTotal()
    local n, c = 0, 0
    for _, e in ipairs(S.list) do if (e.q or 1) == 0 then n = n + 1; c = c + (e.total or 0) end end
    return n, c
end

-- 自动卖灰（开关默认关）：一批 12 件，还有就隔 0.6 秒再卖下一批；只卖灰色
function S.AutoSell(round)
    round = round or 1
    if not S.Opt("auto") or not S.AtMerchant() or round > S.AUTO_MAX then return end
    local cnt, got, _, left = S.SellBatch(S.BATCH, true, true)
    S.autoN, S.autoMoney = (S.autoN or 0) + cnt, (S.autoMoney or 0) + got
    if cnt > 0 and (left or 0) > 0 and S.AtMerchant() then
        local tok = S.visit
        after(S.AUTO_GAP, function() if S.visit == tok then S.AutoSell(round + 1) end end)
        return
    end
    if (S.autoN or 0) > 0 then
        ns.Print(string.format(L("自动卖灰：%d 件，获得 %s（商人「购回」页可买回最近 12 件；设置里可关）", "Auto-sold %d grey item(s) for %s (Buyback tab to undo)"),
            S.autoN, money(S.autoMoney)))
    end
end

-- ================= 面板（11-17 起是商人助手外框里的「卖垃圾」页）=================
local ROW_H = 18
local DOCK = ns.MerchantDock   -- 外框（MerchantDockUI.lua，本子插件里排在前面）
if DOCK and not DOCK.Build then DOCK = nil end
local PW = DOCK and (DOCK.W - 2 * DOCK.PAD) or 250   -- 内容宽（外框宽 370 - 两边 8）
local function fs(p, font, justify)
    local t = p:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetJustifyH(justify or "LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
end
S.PANEL_H = 22 + S.MAX_ROWS * ROW_H + 92
function S.RegisterDock()
    if not DOCK or S.docked then return end
    S.docked = true
    DOCK.Register("sell", { order = 2,
        tab = function() return L("卖垃圾", "Sell junk") end,
        count = function() return #S.list end,
        never = function()
            S.SetOpt("panel", false)
            ns.Print(L("卖垃圾面板不再自动弹；想用：/gi 卖、背包上的「卖垃圾」按钮，或设置里重新勾上", "Sell junk panel won't pop up any more - /gi sell, the bag button or Settings to bring it back"))
            if ns.CloseHint then   -- 11-17：再说一次「窗口与提醒」里能找回（同一扇最多 3 次）
                ns.CloseHint("sellJunk", L("也能在 GI 菜单 → 设置 → 窗口与提醒「卖垃圾面板」点「打开」", "Also: GI menu > Settings > Windows & alerts > Sell junk panel"))
            end
        end,
        neverTip = function() return L("= 关掉设置「打开商人时在商人窗口旁显示卖垃圾面板」；/gi 卖 仍能打开", "= turns off \"Show the Sell junk panel next to merchants\"; /gi sell still opens it") end,
        onClose = function() S.dismissed = true end })
end
function S.Build()
    if S.panel then return S.panel end
    S.RegisterDock()
    local f = DOCK and DOCK.Body("sell") or CreateFrame("Frame", "GearInsightForeverSellJunk", UIParent)
    S.panel = f
    f:SetSize(PW, S.PANEL_H)
    if DOCK then DOCK.SetHeight("sell", S.PANEL_H) end
    f:EnableMouse(true)
    -- 11-16 排序切换：卖价（绝对回收价）⇄ 拍卖比（Auctionator 拍卖价 / 商人价）；说明行在 RefreshUI 里按排序写
    f.sortBtn = ns.Button(f, "", 80, 18, function() S.ToggleSort() end)
    f.sortBtn:SetPoint("TOPRIGHT", 0, 0)
    if f.sortBtn.HookScript then
        f.sortBtn:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L("点一下切换排序", "Click to switch sorting"), 1, 0.82, 0)
            GameTooltip:AddLine(L("卖价：按商人回收总价从低到高", "Price: vendor total, low to high"), 1, 1, 1, true)
            GameTooltip:AddLine(L("拍卖比：按拍卖价比商店高多少从低到高，最该卖商店的在上（拍卖价读 Auctionator，没数据的排最后）",
                "AH ratio: AH vs vendor, low to high - best to vendor on top (AH prices from Auctionator; no data goes last)"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        f.sortBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    f.tip = fs(f, "GameFontDisableSmall")
    f.tip:SetPoint("TOPLEFT", 0, -3); f.tip:SetWidth(PW - 86)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d) S.Scroll(-(d or 0)) end)
    f.rows = {}
    local top = -22
    for i = 1, S.MAX_ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(PW, ROW_H - 1)
        r:SetPoint("TOPLEFT", 0, top - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:SetScript("OnClick", function(self) S.ClickRow(rg(self, "e")) end)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(15, 15); r.icon:SetPoint("LEFT", 0, 0)
        r.name = fs(r, "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 19, 0); r.name:SetWidth(PW - 19 - 72 - 52 - 6)
        r.price = fs(r, "GameFontHighlightSmall", "RIGHT"); r.price:SetPoint("RIGHT", 0, 0); r.price:SetWidth(72)
        -- 11-16 拍卖对比小标（卖商店 / 拍+N%），在名字和价钱之间
        r.tag = fs(r, "GameFontHighlightSmall", "RIGHT"); r.tag:SetPoint("RIGHT", r.price, "LEFT", -2, 0); r.tag:SetWidth(52)
        r:SetScript("OnEnter", function(self)
            local e = rg(self, "e")
            if e and T() and T().ShowTip then T().ShowTip(self, e) end
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.rows[i] = r
    end
    local by = top - S.MAX_ROWS * ROW_H
    f.more = fs(f, "GameFontDisableSmall"); f.more:SetPoint("TOPLEFT", 0, by - 1); f.more:SetWidth(PW)
    f.sum = fs(f, "GameFontNormalSmall"); f.sum:SetPoint("TOPLEFT", 0, by - 14); f.sum:SetWidth(PW)
    f.sell = ns.Button(f, "", PW, 28, function() S.ClickSell() end)
    f.sell:SetPoint("TOPLEFT", 0, by - 30)
    f.last = fs(f, "GameFontHighlightSmall"); f.last:SetPoint("TOPLEFT", 0, by - 62); f.last:SetWidth(PW)
    f.hid = fs(f, "GameFontDisableSmall"); f.hid:SetPoint("TOPLEFT", 0, by - 76); f.hid:SetWidth(PW)
    f.empty = fs(f, "GameFontDisable"); f.empty:SetPoint("TOPLEFT", 0, top - 10); f.empty:SetWidth(PW)
    if not DOCK then f:Hide() end
    return f
end
-- ---------- 拍卖价对比（11-16 用户截图「标记AH比商店贵的百分比+ -」「把值得卖商店的标记出来」）----------
--   算法 + 物品提示那一行在主插件 BagStub.lua（ns.SellAH，常驻：所有物品提示都要有）；这里只借用
local A = ns.SellAH
S.AH_CUT, S.VENDOR_OK = A.AH_CUT, A.VENDOR_OK
function S.AHPrice(id) return A.AHPrice(id) end
function S.VendorPrice(id) return A.VendorPrice(id) end
function S.Compare(id) return A.Compare(id) end
function S.Tag(id) return A.Tag(id) end
function S.TipLine(id) return A.TipLine(id) end

-- 「面板开着」= 商人助手里卖垃圾这一页是开的（切到「买材料」页签时内容框藏着，但仍算开着：要照常刷新件数）
function S.PanelShown()
    if DOCK then return S.panel ~= nil and DOCK.IsOn("sell") end
    return S.panel ~= nil and S.panel:IsShown() and true or false
end
function S.Place()   -- 位置归商人助手外框（贴商人窗口右边，放不下换下方 / 左边；可拖）
    if DOCK then return DOCK.Place() end
    local f = S.panel
    if not f then return end
    f:ClearAllPoints()
    local mf = rawget(_G, "MerchantFrame")
    if type(mf) == "table" then f:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, -2)
    else f:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
end
-- opts.auto = 开商人自动弹；opts.focus = 玩家点的（切到卖垃圾页）
function S.Show(opts)
    local f = S.Build()
    if DOCK then
        DOCK.Show("sell", opts)
    else
        S.Place()
        f:Show()
    end
    S.Refresh()
end
function S.Hide()
    if DOCK then DOCK.Hide("sell") elseif S.panel then S.panel:Hide() end
end
function S.SellText()
    if combat() then return L("战斗中不能卖", "Not in combat") end
    local n, c = S.GreyTotal()
    if n == 0 then return L("没有灰色物品", "No grey items") end
    local k = math.min(n, S.BATCH)
    if n <= S.BATCH then return string.format(L("一键卖灰色 %d 件（%s）", "Sell %d grey (%s)"), n, money(c)) end
    return string.format(L("一键卖灰色 %d 件 · 共 %d 件", "Sell %d grey · %d total"), k, n)
end
function S.RefreshUI()
    local f = S.panel
    if not f or not rg(f, "rows") then return end
    local off = math.max(0, math.min(S.off or 0, math.max(0, #S.list - S.MAX_ROWS)))
    S.off = off
    for i, r in ipairs(f.rows) do
        local e = S.list[off + i]
        r.e = e
        if e then
            r:Show()
            r.icon:SetTexture(e.icon)
            local tr = T()
            r.name:SetText(((tr and tr.Colored) and tr.Colored(e) or tostring(e.name)) .. ((e.count or 1) > 1 and (" ×" .. e.count) or ""))
            r.tag:SetText(S.Tag(e.id))
            r.price:SetText(S.Confirming(e) and ("|cffff5555" .. L("再点一次卖", "Click again") .. "|r") or money(e.total))
        else
            r:Hide()
        end
    end
    local ah = S.Sort() == "ah"
    if rg(f, "sortBtn") then f.sortBtn:SetText(ah and L("排序：拍卖比", "Sort: AH %") or L("排序：卖价", "Sort: price")) end
    if not ah then
        f.tip:SetText(L("按卖价从低到高 · 点一行卖一格 · 绿色以上点两下", "Cheapest first · click a row to sell · green+ needs two clicks"))
    elseif (S.ahN or 0) == 0 and #S.list > 0 then
        f.tip:SetText(L("|cffff8040没有拍卖价数据（装 Auctionator 并扫一次拍卖行），先按卖价排|r", "|cffff8040No AH prices (install Auctionator and scan), sorted by price|r"))
    else
        f.tip:SetText(L("按拍卖比从低到高：最该卖商店的在上 · 点一行卖一格", "AH ratio low to high: best to vendor on top · click to sell"))
    end
    local n, c = S.Total()
    if n == 0 then
        f.empty:SetText((S.loading or 0) > 0 and L("物品信息读取中…", "Loading item info…") or L("背包里没有商人肯收的东西", "Nothing a merchant will buy"))
        f.empty:Show()
    else f.empty:Hide() end
    f.more:SetText(n > S.MAX_ROWS and string.format(L("第 %d-%d 件 · 共 %d 件 · 滚轮翻页", "%d-%d of %d · scroll for more"), off + 1, math.min(n, off + S.MAX_ROWS), n) or "")
    f.sum:SetText(n > 0 and string.format(L("共 %d 件 · 合计 %s", "%d item(s) · total %s"), n, money(c)) or "")
    f.sell:SetText(S.SellText())
    if f.sell.SetEnabled then f.sell:SetEnabled((S.GreyTotal()) > 0 and not combat()) end
    local last = S.last
    if last and last.link and (S.visitN or 0) > 0 then
        f.last:SetText(string.format(L("|cff33ff99刚卖了 %s，获得 %s|r · 本次共 %s", "|cff33ff99Sold %s for %s|r · this visit %s"), tostring(last.link), money(last.c), money(S.visitMoney)))
    elseif last and (S.visitN or 0) > 0 then
        f.last:SetText(string.format(L("|cff33ff99刚卖了 %d 件，获得 %s|r · 本次共 %s", "|cff33ff99Sold %d for %s|r · this visit %s"), last.n, money(last.c), money(S.visitMoney)))
    else
        f.last:SetText(L("卖错了可以在商人「购回」页买回最近 12 件", "Mistake? Buyback tab keeps the last 12"))
    end
    f.hid:SetText(S.HiddenText())
    if DOCK and DOCK.IsOn("sell") then DOCK.Update() end   -- 页签上的件数
end
function S.Refresh()
    if not S.PanelShown() then return end
    S.Scan()
    S.RefreshUI()
end
-- /gi 卖：商人开着 → 打开面板（就算之前点了 × 或设置关了面板）；没开 → 提示
function S.Open()
    if S.AtMerchant() and not S.merchant then S.merchant = true; S.HookMerchant() end   -- 开商人时本文件还没加载（面板关着）
    if not S.AtMerchant() then
        ns.Print(L("卖垃圾要在商人那里用：跟任意商人对话，商人窗口右边会自动弹出「卖垃圾」面板", "Talk to any merchant - the Sell junk panel pops up next to the merchant window"))
        return false
    end
    S.dismissed = false
    S.Show({ focus = true })
    return true
end
ns.SellJunkOpen = S.Open   -- 背包上的「卖垃圾」按钮（BagButtons.lua）

-- ---------- 清背包页：说明 + 入口 ----------
function S.DecorateTrash(p)
    if not p or rawget(p, "sellNote") then return end
    p.sellNote = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- 11-17 用户「下方UI收拾好一点」：单行不折（原来折成两行压住下面的操作说明）
    p.sellNote:SetPoint("BOTTOMLEFT", 12, 22); p.sellNote:SetWidth(646); p.sellNote:SetJustifyH("LEFT")
    if p.sellNote.SetWordWrap then p.sellNote:SetWordWrap(false) end
    p.sellNote:SetText(L("想卖钱而不是摧毁？跟任意商人对话会自动弹出「卖垃圾」面板（/gi 卖）",
        "Rather sell? Talk to any merchant - the Sell junk panel pops up (/gi sell)"))
    p.sellBtn = ns.Button(p, L("卖垃圾", "Sell junk"), 80, 18, function() S.Open() end)
    p.sellBtn:SetPoint("TOPRIGHT", -12, -66)
end
do
    local tr = ns.Trash
    if tr and type(tr.BuildPage) == "function" then
        local orig = tr.BuildPage
        tr.BuildPage = function(p, ...)   -- ns.Trash 是自己的表（不是暴雪全局），包一层加说明
            orig(p, ...)
            pcall(S.DecorateTrash, p)
        end
    end
end

-- ---------- 事件 ----------
function S.OnShowMerchant()
    S.merchant = true
    S.visit = (S.visit or 0) + 1
    S.dismissed, S.visitN, S.visitMoney, S.last, S.autoN, S.autoMoney = false, 0, 0, nil, 0, 0
    S.HookMerchant()
    if S.Opt("panel") then S.Show({ auto = true }) end
    if S.Opt("auto") then
        local tok = S.visit
        after(0.2, function() if S.visit == tok then pcall(S.AutoSell, 1) end end)
    end
end
-- 开商人：BagStub.lua 收到 MERCHANT_SHOW 转过来（ns.SellJunkMerchant）
ns.SellJunkMerchant = function() S.OnShowMerchant(); return true end
function S.OnCloseMerchant()
    S.merchant = false
    S.visit = (S.visit or 0) + 1
    S.Hide()
end
function S.HookMerchant()
    if S.hooked then return end
    local mf = rawget(_G, "MerchantFrame")
    if type(mf) == "table" and type(mf.HookScript) == "function" then
        S.hooked = true
        -- 11-20：游戏说还在跟商人交互（商人窗口只是被别的插件藏了 / 换了）→ 不当成关商人
        pcall(mf.HookScript, mf, "OnHide", function() if S.merchant and not S.Interacting() then S.OnCloseMerchant() end end)
    end
end

local ev = CreateFrame("Frame")
S.ev = ev
-- 11-20：MERCHANT_SHOW / CLOSED 这里只记「商人开着没」（S.evOpen，给 S.AtMerchant 用）；弹面板 / 自动卖照旧由 BagStub 转过来，不会调两次
--   ADDON_ACTION_BLOCKED / FORBIDDEN：卖的那一下（S.selling）游戏拦了我们 → SellOne 算没卖；UI_ERROR_MESSAGE：记最近一条，卖完回头看没卖掉时告诉玩家
for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE" }) do
    pcall(ev.RegisterEvent, ev, e)   -- ⛔ 容错注册：客户端没有的事件名会报错
end
ev:SetScript("OnUpdate", function()
    if S.dirty and now() >= (S.dirtyAt or 0) then S.dirty = false; S.Refresh() end
end)
local function plainStr(v)
    if type(v) ~= "string" or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end
function S.OnMetaEvent(e, a1, a2)
    if e == "MERCHANT_SHOW" then S.evOpen = true
    elseif e == "MERCHANT_CLOSED" then S.evOpen = false
    elseif e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN" then
        local who = plainStr(a1)
        if S.selling and who and S.OUR_ADDONS[who] then
            S.blockedNow = true
            S.blocked = { t = now(), e = e, fn = plainStr(a2) or "?" }
        end
    elseif e == "UI_ERROR_MESSAGE" then
        local msg = plainStr(a2) or plainStr(a1)   -- 新客户端 (errorType, message)；老客户端 (message)
        if msg then S.uiErr = { t = now(), msg = msg } end
    else return false end
    return true
end
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if S.OnMetaEvent(e, a1, a2) then return
    elseif not S.PanelShown() then return
    elseif e == "BAG_UPDATE" or e == "GET_ITEM_INFO_RECEIVED" then S.dirty, S.dirtyAt = true, now() + 0.3
    elseif e == "BAG_UPDATE_DELAYED" or e == "PLAYER_REGEN_DISABLED" or e == "PLAYER_REGEN_ENABLED" then S.dirty = false; S.Refresh()
    end
end)

-- ---------- 设置 / 命令 ----------
-- 设置描述在主插件 BagStub.lua（索引 / 搜索 / 本页设置不用加载这个子插件）

ns.ExtraSlash = ns.ExtraSlash or {}
-- 11-20 /gi 卖 诊断（/gi sell diag）：卖不掉时让玩家自己看到卡在哪（商人状态三路 / 挡着的窗口 / 战斗 / 光标 / 出售接口 / 上次失败原因）
local function yn(v) if v == nil then return L("没有这个接口", "n/a") end return v and L("是", "yes") or L("否", "no") end
function S.Diag()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(L("卖垃圾诊断：", "Sell junk diagnostics:"))
    add(string.format(L("  在商人处 = %s（游戏交互状态 %s · 开商人事件 %s / %s · MerchantFrame 显示 %s）", "  At merchant = %s (interaction %s · events %s / %s · MerchantFrame shown %s)"),
        yn(S.AtMerchant()), yn(S.Interacting()), yn(S.merchant or S.evOpen or false), yn(ns.BagAtMerchant and ns.BagAtMerchant() or false),
        (rawget(_G, "MerchantFrame") == nil) and L("没有这个框体", "missing") or yn(shown("MerchantFrame"))))
    add(string.format(L("  挡着的窗口 = %s · 战斗中 = %s · 光标上拿着东西 = %s", "  Blocking window = %s · in combat = %s · cursor holds item = %s"),
        S.Blocked() or L("无", "none"), yn(combat()), yn(CursorHasItem and CursorHasItem() and true or false)))
    local _, fname = S.UseFunc()
    add(string.format(L("  出售接口 = %s", "  Sell API = %s"), fname or L("没有（这个客户端不能用插件卖）", "none")))
    local why = S.CanSell()
    add(string.format(L("  现在能卖 = %s", "  Can sell now = %s"), why and (L("否：", "no: ") .. S.WhyText(why)) or L("是", "yes")))
    if S.lastFail then add(string.format(L("  上次没卖成的原因 = %s", "  Last failure = %s"), tostring(S.lastFail))) end
    if S.apiErr then add(string.format(L("  接口报错 = %s", "  API error = %s"), S.apiErr)) end
    if S.blocked then add(string.format(L("  被游戏拦截 = %s %s", "  Blocked by game = %s %s"), S.blocked.e, S.blocked.fn)) end
    if S.uiErr then add(string.format(L("  游戏最近一条红字提示 = %s", "  Last game error = %s"), S.uiErr.msg)) end
    for _, s in ipairs(lines) do ns.Print(s) end
    return lines
end
ns.ExtraSlash["卖"] = function(rest, rawRest)
    local r = ((rawRest or rest or "") .. ""):gsub("[ \t]+", "")
    if r == "诊断" or r:lower() == "diag" then return S.Diag() end
    S.Open()
end
ns.ExtraSlash.sell = ns.ExtraSlash["卖"]
ns.ExtraSlash["卖垃圾"] = ns.ExtraSlash["卖"]

-- 「窗口与提醒」（11-17 用户「这些弹出的功能都确保能永久关闭」）：开商人自己弹的卖垃圾面板，「不再弹」关掉的从这里找回
--   ⛔ 本子插件按需加载（开商人才加载）→ 没加载时主插件 BagStub.lua 要有同 key 占位（见回报）
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "sellJunk", order = 70, title = function() return L("卖垃圾面板（开商人时）", "Sell junk panel (at merchants)") end,
        state = function() return S.Opt("panel") and L("开商人时出在旁边", "Shows next to merchants") or L("已关闭（/gi 卖 仍能打开）", "Closed (/gi sell still opens it)") end,
        actions = function()
            local on = S.Opt("panel") and true or false
            return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() S.SetOpt("panel", not on) end } }
        end })
end
