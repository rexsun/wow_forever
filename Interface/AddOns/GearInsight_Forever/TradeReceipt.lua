-- 11-15 用户截图（别人的插件交易完私聊「与<枫叶-洞察>的交易成功了。给予[魔法纯净水](20)等1件物品。」）「这个功能也加到插件」：
--   交易成功后自动私聊交易对象一条「交易回执」：和谁交易成功、我给了什么（物品链接 + 数量，多件写「等 N 件物品」，有金币写金币）、
--   我收到了什么（子开关，默认开）。例：「与<名字>的交易成功了。给予[魔法纯净水]x20，收到 1金20银。」
--   · ⛔ 不带插件名（11-13 网易DD合规：自动发言不带插件名）
--   · 255 字节上限：物品链接整条保留或整条换成「等 N 件物品」，绝不把链接切一半（半截链接服务器会吞掉整句）；最后兜底按 UTF-8 字符边界裁
--   · 判定交易成功照抄法师吃喝 ⑥ 道谢（MageWater.lua MW.OnThankEvent，1.0.1 起线上在用）：
--       系统提示「交易完成」（UI_INFO_MESSAGE / CHAT_MSG_SYSTEM 里 = ERR_TRADE_COMPLETE）→ 成功；
--       或双方都点了交易后窗口关上（TRADE_CLOSED）→ 等 0.5 秒，期间没报背包满 / 取消之类的错 → 成功（「交易完成」有时比关窗晚到）
--       取消 / 失败（ERR_TRADE_CANCELLED / 背包满 / 唯一物品超量）不发
--   · 快照：交易中每次栏位 / 金币 / 确认状态变化都重拍双方栏位（1~6 格；第 7 格「不会被交易」不算）；
--       任一方已点交易后只在 TRADE_ACCEPT_UPDATE 重拍（交易成交那一下栏位会先被清空，别拿空栏位覆盖掉）
--   · 和法师吃喝 ⑥ 道谢的配合：同一笔交易两条都可能发 → 回执晚 1 秒发，保证在道谢之后；
--       道谢已经发了、而我这边什么都没给（只是收了水 / 面包）→ 回执不发（道谢就是回执，免得同一个法师连收两条）
--   · 战斗中 / 聊天受限（C_ChatInfo.InChatMessagingLockdown）不发；保密值先 issecretvalue（ns.Secret）判断再用
--   · 登录就加载；平时只注册 TRADE_SHOW，开交易到交易结束这段才注册其余几个事件
--   开关：设置 → 通用「交易回执」（ns.db.ui.tradeReceipt = false 关；ns.db.ui.tradeReceiptGot = false 不写收到了什么）
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end
local CL = function(cn, en) return ns.ChatL(cn, en) end   -- 11-19 回执是发给交易对象的：走对外说话语言

local TR = {}
ns.TradeReceipt = TR
TR.MAX_BYTES = 255
TR.SLOTS = 6            -- MAX_TRADABLE_ITEMS；第 7 格 = 「不会被交易」
TR.DELAY = 1            -- 判定成功后晚 1 秒发（排在法师道谢后面）
TR.THANK_WIN = 5        -- 法师道谢在这几秒内发过 = 同一笔交易
TR.SHOW_GIVE = 3        -- 给予最多列几个链接（放不下再减）
TR.SHOW_GOT = 2         -- 收到最多列几个链接

-- ---------- 小工具 ----------
local function secret(v) return ns.Secret and ns.Secret(v) or false end
local function clean(v)
    if v == nil or secret(v) then return nil end
    return v
end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local function now() return tonumber(call(GetTime)) or 0 end
local function combat() return InCombatLockdown and call(InCombatLockdown) and true or false end
local function after(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
-- 按 UTF-8 字符边界裁到 n 字节以内（别把中文切成半个字）
local function cutBytes(s, n)
    if #s <= n then return s end
    if n <= 0 then return "" end
    local i = n
    while i > 0 do
        local b = s:byte(i + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i)
end
TR.CutBytes = cutBytes

-- ---------- 开关 ----------
local function ui() return ns.db and ns.db.ui end
function TR.On() local u = ui(); return u ~= nil and u.tradeReceipt ~= false end
function TR.GotOn() local u = ui(); return not (u and u.tradeReceiptGot == false) end
function TR.SetOn(v)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.tradeReceipt = nil
    if not v then ns.db.ui.tradeReceipt = false end
end
function TR.SetGot(v)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.tradeReceiptGot = nil
    if not v then ns.db.ui.tradeReceiptGot = false end
end

-- ---------- 交易对象 ----------
--   和法师吃喝 MW.TradeTarget 同一口径：GetUnitName("NPC", true) 回全名（《无限》「名 姓」），去掉「-服务器」；拿不到读交易窗标题
function TR.Target()
    local who
    if GetUnitName then
        who = clean(call(GetUnitName, "NPC", true))
        if type(who) == "string" then who = who:match("^[^-]+") end
    end
    if (not who or who == "") and UnitName then who = clean(call(UnitName, "NPC")) end
    if (not who or who == "") and _G.TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        who = clean(call(TradeFrameRecipientNameText.GetText, TradeFrameRecipientNameText))
    end
    if type(who) ~= "string" or who == "" then return nil end
    return who
end

-- ---------- 快照 ----------
local function readSide(infoF, linkF)
    local list = {}
    for i = 1, TR.SLOTS do
        local name, _, num = call(infoF, i)
        name, num = clean(name), tonumber(clean(num))
        if type(name) == "string" and name ~= "" then
            local link = clean(call(linkF, i))
            if type(link) ~= "string" or not link:find("|H", 1, true) then link = nil end
            list[#list + 1] = { name = name, link = link, n = (num and num > 0) and num or 1 }
        end
    end
    return list
end
function TR.Snap()
    local c = TR.ctx
    if not c or c.closed then return end
    c.give = readSide(GetTradePlayerItemInfo, GetTradePlayerItemLink)
    c.got = readSide(GetTradeTargetItemInfo, GetTradeTargetItemLink)
    c.giveMoney = tonumber(clean(call(GetPlayerTradeMoney))) or 0
    c.gotMoney = tonumber(clean(call(GetTargetTradeMoney))) or 0
end

-- ---------- 话术 ----------
function TR.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return nil end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = ""
    if g > 0 then out = out .. g .. CL("金", "g") end
    if s > 0 then out = out .. (out ~= "" and CL("", " ") or "") .. s .. CL("银", "s") end
    if c > 0 then out = out .. (out ~= "" and CL("", " ") or "") .. c .. CL("铜", "c") end
    return out
end
-- 一边的描述：show = 列几个链接（0 = 只写件数）
local function sideText(list, money, show)
    local parts = {}
    local n = #list
    if n > 0 then
        show = math.min(show, n)
        if show <= 0 then
            parts[1] = string.format(CL("%d 件物品", "%d item(s)"), n)
        else
            local items = {}
            for i = 1, show do
                local it = list[i]
                items[#items + 1] = (it.link or ("[" .. it.name .. "]")) .. (it.n > 1 and ("x" .. it.n) or "")
            end
            local s = table.concat(items, CL("、", ", "))
            if n > 1 then s = s .. string.format(CL(" 等 %d 件物品", " (%d items)"), n) end
            parts[1] = s
        end
    end
    local m = TR.Money(money)
    if m then parts[#parts + 1] = m end
    if #parts == 0 then return nil end
    return table.concat(parts, CL("，", ", "))
end
function TR.Build(c, gs, rs)
    local give = sideText(c.give or {}, c.giveMoney, gs)
    local got = TR.GotOn() and sideText(c.got or {}, c.gotMoney, rs) or nil
    if not give and not got then return nil end
    local s = string.format(CL("与<%s>的交易成功了。", "Trade with <%s> complete. "), c.who)
    if give then s = s .. CL("给予", "Gave ") .. give end
    if got then s = s .. (give and CL("；收到 ", "; got ") or CL("收到 ", "Got ")) .. got end
    return s .. CL("。", ".")
end
-- 在 255 字节内尽量多列链接：先减「收到」那边，再减「给予」那边；都只写件数还超 → 按字符边界裁（这时已经没有链接了）
function TR.Text(c)
    if not c or not c.who then return nil end
    local gs = math.min(TR.SHOW_GIVE, #(c.give or {}))
    local rs = math.min(TR.SHOW_GOT, #(c.got or {}))
    while true do
        local s = TR.Build(c, gs, rs)
        if not s then return nil end
        if #s <= TR.MAX_BYTES then return s end
        if rs > 1 then rs = rs - 1
        elseif gs > 1 then gs = gs - 1
        elseif rs > 0 then rs = 0
        elseif gs > 0 then gs = 0
        else return cutBytes(s, TR.MAX_BYTES) end
    end
end

-- ---------- 发 ----------
function TR.CanChat()
    if combat() then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and call(C_ChatInfo.InChatMessagingLockdown) then return false end
    return true
end
-- 法师吃喝 ⑥ 刚给这个人道过谢（同一笔交易）
function TR.ThankedJustNow(who)
    local MW = ns.MageWater
    local t = MW and type(MW.thanked) == "table" and MW.thanked[who]
    if type(t) ~= "number" then return false end
    local d = now() - t
    return d >= 0 and d <= TR.THANK_WIN
end
function TR.Send(c)
    if not TR.On() then return false end
    -- 道谢已经发了、我这边什么都没给 → 道谢就是回执
    local gave = #(c.give or {}) > 0 or (c.giveMoney or 0) > 0
    if not gave and TR.ThankedJustNow(c.who) then return false end
    local text = TR.Text(c)
    if not text or not TR.CanChat() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    if not pcall(send, text, "WHISPER", nil, c.who) then return false end
    TR.lastSent = text
    if not TR.told then
        TR.told = true
        if ns.Print then ns.Print(L("已私聊交易对象一条交易回执（设置 → 通用「交易回执」可关）", "Sent a trade receipt to your trade partner (Settings -> General to turn off)")) end
    end
    return true
end
-- 交易成功：先收尾事件，晚 1 秒再发（排在法师道谢后面）
function TR.Done(c)
    if not c or c.done or c.err then return false end
    c.done = true
    if TR.ctx == c then TR.ctx = nil; TR.Sync() end
    if not TR.On() then return false end
    local gave = #(c.give or {}) > 0 or (c.giveMoney or 0) > 0
    local got = #(c.got or {}) > 0 or (c.gotMoney or 0) > 0
    if not gave and not got then return false end
    after(TR.DELAY, function() pcall(TR.Send, c) end)
    return true
end

-- ---------- 事件 ----------
local FAIL_KEYS = { "ERR_TRADE_BAG_FULL", "ERR_TRADE_TARGET_BAG_FULL", "ERR_TRADE_CANCELLED", "ERR_TRADE_MAX_COUNT_EXCEEDED",
    "ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED", "ERR_TRADE_TARGET_DEAD", "ERR_TRADE_TOO_FAR", "ERR_TRADE_WRONG_REALM", "ERR_TRADE_QUEST_ITEM" }
TR.FAIL_KEYS = FAIL_KEYS
local function isFail(msg)
    for _, k in ipairs(FAIL_KEYS) do
        local v = _G[k]
        if type(v) == "string" and msg == v then return true end
    end
    return false
end
TR.TRADE_EVENTS = { "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE",
    "TRADE_CLOSED", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM" }
function TR.OnTradeShow()
    if not TR.On() then TR.ctx = nil; TR.Sync(); return false end
    local who = TR.Target()
    if not who then TR.ctx = nil; TR.Sync(); return false end
    TR.ctx = { who = who, give = {}, got = {}, giveMoney = 0, gotMoney = 0 }
    TR.Sync()
    TR.Snap()
    return true
end
function TR.OnEvent(e, a1, a2)
    if e == "TRADE_SHOW" then return TR.OnTradeShow() end
    local c = TR.ctx
    if not c then return end
    if e == "TRADE_PLAYER_ITEM_CHANGED" or e == "TRADE_TARGET_ITEM_CHANGED" or e == "TRADE_MONEY_CHANGED" then
        -- 任一方点了交易后栏位不再跟着变（成交那一下栏位会先清空）：有真改动对方 / 我的确认会被重置，TRADE_ACCEPT_UPDATE 那里重拍
        if not c.accepted then TR.Snap() end
    elseif e == "TRADE_ACCEPT_UPDATE" then
        TR.Snap()
        local p, t = tonumber(clean(a1)), tonumber(clean(a2))
        c.accepted = (p == 1 or t == 1) or nil
        c.both = (p == 1 and t == 1) or nil
    elseif e == "UI_INFO_MESSAGE" or e == "CHAT_MSG_SYSTEM" or e == "UI_ERROR_MESSAGE" then
        local msg = clean((e == "CHAT_MSG_SYSTEM") and a1 or a2)
        if type(msg) ~= "string" then return end
        if e ~= "UI_ERROR_MESSAGE" and _G.ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
            TR.Done(c)
        elseif isFail(msg) then
            c.err = true
        end
    elseif e == "TRADE_CLOSED" then
        if c.closed then return end
        c.closed = true
        if c.both then
            -- 双方都点了交易 → 关窗 = 成交；「交易完成」可能比关窗晚到：等 0.5 秒，期间报错就不算
            after(0.5, function() if TR.ctx == c then pcall(TR.Done, c) end end)
        else
            -- 没双方确认就关了 = 多半取消；留 1 秒给晚到的「交易完成」
            after(1, function() if TR.ctx == c then TR.ctx = nil; TR.Sync() end end)
        end
    end
end

local ev = CreateFrame("Frame")
TR.ev = ev
-- 平时只听 TRADE_SHOW；交易进行中 / 等结果时才听其余几个
function TR.Sync()
    local busy = TR.ctx ~= nil
    for _, e in ipairs(TR.TRADE_EVENTS) do
        if busy then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    TR.busy = busy
end
pcall(ev.RegisterEvent, ev, "TRADE_SHOW")
ev:SetScript("OnEvent", function(_, e, a1, a2) pcall(TR.OnEvent, e, a1, a2) end)
