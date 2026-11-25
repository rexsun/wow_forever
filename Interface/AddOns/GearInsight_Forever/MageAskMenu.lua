-- HOLD：右键法师 →「GearInsight」小标题下多一项「找他要水」（11-15 用户截图「右键如果是FS加个要水」）
--   和「邀请入会」（InviteMenu.lua）同一个口子：暴雪新菜单 Menu.ModifyMenu，没这个接口的客户端什么都不做
--   只在：对方是法师、不是自己、我自己不是法师、不是敌对玩家 时出现；战士 / 盗贼（不用蓝）显示「找他要面包」
--   点了 = 加载法师吃喝（GearInsight_Forever_GroupMage）→ 用它的 MW.AskText / MW.AskMage 发私聊：
--   话术、按对方等级报档、10 分钟内同一个法师不重复密，都和野外弹框一样
local _, ns = ...

local MA = {}
ns.MageAskMenu = MA
MA.MENU_TAGS = { "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }
MA.NO_MANA = { WARRIOR = true, ROGUE = true }

local function secret(v) return issecretvalue and issecretvalue(v) end
local function clean(v) if secret(v) then return nil end return v end
local function short(n) return (tostring(n or ""):gsub("%-.*$", "")) end
local function myClass()
    if not UnitClass then return nil end
    local ok, _, c = pcall(UnitClass, "player")
    return ok and clean(c) or nil
end

-- 对方职业（英文）：① 单位 ② 聊天行 / 菜单给的 GUID
function MA.TargetClass(ctx)
    if type(ctx) ~= "table" then return nil end
    if ctx.unit and UnitClass then
        local ok, _, c = pcall(UnitClass, ctx.unit)
        c = ok and clean(c) or nil
        if type(c) == "string" then return c end
    end
    local guid = ctx.guid or (ctx.playerLocation and ctx.playerLocation.GetGUID and ctx.playerLocation:GetGUID())
    if guid and not secret(guid) and GetPlayerInfoByGUID then
        local ok, _, c = pcall(GetPlayerInfoByGUID, guid)
        c = ok and clean(c) or nil
        if type(c) == "string" then return c end
    end
    return nil
end
function MA.TargetLevel(ctx)
    if not (ctx and ctx.unit and UnitLevel) then return nil end
    local ok, lv = pcall(UnitLevel, ctx.unit)
    lv = ok and clean(lv) or nil
    return (type(lv) == "number" and lv > 0) and lv or nil
end
function MA.Name(ctx)
    local IM = ns.InviteMenu
    if IM and IM.Target then return IM.Target(ctx) end
    local n = ctx and ctx.name
    return (type(n) == "string" and not secret(n) and n ~= "") and n or nil
end

-- 开关 ns.db.ui.mageAskMenu（nil = 默认开）
function MA.Enabled() return not (ns.db and ns.db.ui and ns.db.ui.mageAskMenu == false) end
function MA.SetEnabled(on)
    if not ns.db then return end
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.mageAskMenu = on and true or false
end

function MA.CanAsk(ctx)
    if not MA.Enabled() then return false end
    if MA.TargetClass(ctx) ~= "MAGE" then return false end
    if myClass() == "MAGE" then return false end
    if ctx.unit and UnitIsEnemy then
        local ok, v = pcall(UnitIsEnemy, "player", ctx.unit)
        if ok and clean(v) then return false end
    end
    local name = MA.Name(ctx)
    if not name then return false end
    local me = UnitName and UnitName("player")
    if me and not secret(me) and short(name) == short(me) then return false end
    return true
end
function MA.Label()
    return MA.NO_MANA[myClass() or ""] and ns.L("找他要面包", "Ask for food") or ns.L("找他要水", "Ask for water")
end

-- 点了：加载法师吃喝 → 按野外弹框同一套口径发私聊
function MA.Ask(name, mageLv)
    if not name then return false, "name" end
    -- 11-18 用户截图「点要水无效」：下面几种失败原来都静默返回 → 一律在聊天框说原因
    if not (ns.LoadModule and ns.LoadModule("group")) then
        ns.Print(ns.L("要水没发出去：组队模块（GearInsight_Forever_Group）没加载上，看插件列表里有没有勾选", "Water request not sent: group module (GearInsight_Forever_Group) failed to load - check your addon list"))
        return false, "group"
    end
    if not (ns.MageWater or (ns.GroupLoadMage and ns.GroupLoadMage(true))) then
        ns.Print(ns.L("要水没发出去：法师吃喝模块（GearInsight_Forever_GroupMage）没加载上，看插件列表里有没有勾选", "Water request not sent: mage module (GearInsight_Forever_GroupMage) failed to load - check your addon list"))
        return false, "mage"
    end
    local MW = ns.MageWater
    if MW.RecentlyAsked(name) then
        ns.Print(ns.L("10 分钟内已经找 ", "Already asked ") .. short(name) .. ns.L(" 要过了，不重复密", " in the last 10 min - not sending again"))
        return false, "asked"
    end
    if not MW.CanChat() then
        ns.Print(ns.L("现在发不了私聊（战斗中 / 聊天受限），过一会儿再点", "Can't whisper right now (combat / chat locked) - try again in a moment"))
        return false, "chat"
    end
    local kind = MW.WantsWater(myClass()) and MW.DefaultKind() or "food"
    local text = MW.AskText("pick", mageLv, kind, name)
    local sent, why = MW.AskMage(name, text, nil, true)
    if not sent then
        ns.Print(ns.L("要水没发出去（", "Water request not sent (") .. tostring(why or "?") .. (MW.lastSendErr and (": " .. tostring(MW.lastSendErr)) or "")
            .. ns.L("），把这句截图发给我们", ") - please screenshot this"))
        return false, "send"
    end
    ns.Print(ns.L("已密 ", "Whispered ") .. short(name) .. ns.L(" 要吃喝；他开交易给你时，自己点「交易」确认就行", " - when they open a trade, click Trade to accept"))
    return true
end

MA.hooked = false
function MA.Hook()
    if MA.hooked or not (Menu and Menu.ModifyMenu) then return false end
    for _, tag in ipairs(MA.MENU_TAGS) do
        Menu.ModifyMenu(tag, function(_, root, ctx)
            local ok, can = pcall(MA.CanAsk, ctx)
            if not ok or not can then return end
            local name, lv = MA.Name(ctx), MA.TargetLevel(ctx)
            if ns.MenuTitle then ns.MenuTitle(root) end
            root:CreateButton(MA.Label(), function() MA.Ask(name, lv) end)
        end)
    end
    MA.hooked = true
    return true
end
pcall(MA.Hook)
