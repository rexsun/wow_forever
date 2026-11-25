-- 上马自动换饰品的触发桩（11-20 用户「上马自动换上，下马自动换下，屏幕弹出文字，快速消失」，截图 = 棍子上的胡萝卜 11122）
--   换装逻辑、/gi 上马饰品 的真处理都在按需加载的 GearInsight_Forever_Bag / MountTrinket.lua；这里只有：
--     功能开关（设置 → 功能 → 背包「上马换饰品」，默认开）· 命令占位 · 上马时开关开着、背包里有胡萝卜才加载子插件（加载后子插件自己接事件）
--   ⛔ 内核只剩约 1 KB：不另建框体（离线一个框 ≈ 3 KB），借 BagStub.lua 的事件框（ns._BagStubEv）多挂两个事件 + 一个钩子；
--     数胡萝卜用 ns.Prof.BagCount（无限客户端老接口 GetItemCount 读不到，它先走 C_Item.GetItemCount）；
--     无限客户端 DB2（1.60.1.70532 Item.csv）只有胡萝卜，马鞭 25653 / 天空破碎者之鞭 32863 不存在 → 这里只认 11122（子插件里三件都认）
--   ⛔ 不注册 COMBAT_LOG_EVENT_UNFILTERED；排在 BagStub.lua / Features.lua 后面；所有职业都有
local _, ns = ...
-- 存档 ns.db.mountTrinket（false = 关，nil = 默认开）
-- 11-24 GI-350「设置里找不到对应选项」：去掉 hold（原来 _Bag 不在 / 没就绪时功能页不出这一条）；设置 → 通用 常驻一组「上马自动换胡萝卜」（PageData.lua general 块）
--   GI-351「开关关了还是会换」：开关只有这一个存档键；所有入口（功能页勾选 / 设置 → 通用 / 屏幕图标 / 命令）都走这里的 set，
--   子插件已加载就当场按新开关补做（关掉时骑着马 = 当场换回；战斗中 = 脱战后换回）；子插件 MT.Equip 自己也直接读这个键（不靠功能登记）
local function mtGet() return ns.db.mountTrinket ~= false end
local function mtSet(v)
    if v then ns.db.mountTrinket = nil else ns.db.mountTrinket = false end
    local MT = ns.MountTrinket
    if MT then MT.wait = true; pcall(MT.Sync); pcall(MT.BtnUpdate) end
end
ns.Feature({ key = "mounttrinket", cat = "bag", zh = "上马换饰品", en = "Mount trinket swap", def = true, cfg = "mounttrinket",
    get = mtGet, set = mtSet,
    dzh = "上马换上胡萝卜，下马换回", den = "Carrot on a Stick while mounted" })
if ns.RegisterSettings then
    local function tt() return ns.L("上马自动换胡萝卜", "Mount trinket swap") end
    ns.RegisterSettings({ key = "mounttrinket", order = 25.5, data = "general", title = tt,
        items = { { type = "check", id = "mounttrinket.on", keys = "饰品 carrot trinket",
            text = tt,
            get = mtGet, set = mtSet } } })
end
local ev = ns._BagStubEv
if ev then
    ev:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")   -- 上马 = 身上多一个光环：显示事件不来时兜底
    -- 11-23 用户「胡萝卜饰品，下马没换回来，搞个UI，可以随时开启关闭」：有胡萝卜（背包里）或存档里记着没换回的（ns.db.mtSwap）就加载子插件
    --   （不再等上马 / 开关开着：子插件要摆开关图标、/reload 后下马也要换回）
    ev:HookScript("OnEvent", function()
        if not ns.MountTrinket and ns.db and (ns.db.mtSwap or ns.db.mtSwaps or (ns.Prof.BagCount(11122) or 0) > 0) and ns.BagLoad(true) and ns.MountTrinket then
            ns.MountTrinket.Sync()
        end
    end)
end
if ns._BagMod then ns._BagMod:Slash({ "上马饰品", "mounttrinket" }, "MountTrinket.lua") end
