-- 上马自动换饰品（11-20 用户「上马自动换上，下马自动换下，屏幕弹出文字，快速消失」，截图 = 棍子上的胡萝卜 11122「装备：坐骑速度提高3%」）
--   ① 上马（IsMounted 变真）且开关开着（设置 → 功能 → 背包「上马换饰品」/ /gi 上马饰品）：背包里有 ns.MOUNT_TRINKETS 里的饰品
--        （天空破碎者之鞭只在能飞的地方；马鞭 > 胡萝卜）→ 换进饰品栏：有空的饰品栏先用空的，没有就换下栏（14）；记下槽位和原饰品
--        已经戴着任何一件坐骑饰品 = 不动（玩家自己戴的不归我们管）
--   ② 下马：那一格还是我们换上的那件 → 换回原饰品（原来是空的 = 摘回背包）；
--        玩家自己换过那一格 / 原饰品已经不在背包（卖了 / 进银行）→ 放弃换回，只清掉记录
--   ③ 战斗中 / 读条中 / 死亡时一律不动：排队，等脱战（PLAYER_REGEN_ENABLED）/ 读条结束 / 复活时再按当时骑没骑着补做（被打下马 = 脱战后换回）
--   ④ 每次换装屏幕中上方弹一行字（「已换上 …」「已换回 …」），0.7 秒后 0.8 秒淡出；不发聊天、不出声
--   上下马检测：PLAYER_MOUNT_DISPLAY_CHANGED + UNIT_AURA(player) 兜底（⛔ 不注册 COMBAT_LOG_EVENT_UNFILTERED：无限 12.0 引擎会禁用整个插件）
--   主插件 MountStub.lua 是触发桩：第一次上马、背包里有坐骑饰品才加载本子插件，之后这里自己接事件
--   ⛔ 这个文件晚于主插件加载：文件头 ns = _G.GearInsightForever or ns；状态都放在 MT 表上（不放在框体上）
-- 11-23 用户「胡萝卜饰品，下马没换回来，搞个UI，可以随时开启关闭」「让用户直观控制」：
--   ⑤ 换装记录存进存档 ns.db.mtSwap = { 槽位, 原饰品, 换上的 }：骑着马 /reload、掉线、下线再上来，下马照样换回（原来只记在内存里，一重载就丢）
--   ⑥ 屏幕上一个胡萝卜图标（有胡萝卜才出）：左键开 / 关（亮 + 绿字「上马换」/ 灰 + 红字「已关」）、拖动挪位置、右键隐藏（/gi 上马饰品 图标 找回）；
--      骑着马时关掉 = 当场换回原饰品
-- 11-24 GI-351「开关关了还是会换成萝卜」/ GI-350「进战斗下马不会换回银色黎明委任徽章」「设置里找不到选项」：
--   ⑦ 开关只认存档 ns.db.mountTrinket（MT.Off 直接读，不靠功能登记）；关掉时骑着马、在战斗中 = 记着，脱战后当场换回（原来要等下马）
--   ⑧ 换回不再「换一次就清记录」：EquipItemByName 是异步的、刚脱战 / 拾取 / 读条时可能没换成 → 记录留到确认换成（那一格不是胡萝卜了）才清，
--      没换成 1.5 秒后再试，最多 3 次；忙（战斗 / 读条 / 死亡）时也 2 秒后自己再看一眼，不全靠事件（漏一个事件就一直戴着胡萝卜）
--   ⑨ 传送 / 进出副本（PLAYER_ENTERING_WORLD）也重新按骑没骑着补做
--   ⑩ 图标右键 /「窗口与提醒」的「隐藏」只收图标、不关功能 → 提示里写明；「窗口与提醒」那行加「关掉功能 / 打开功能」按钮
-- 11-24 用户「术士，带卫兵队长，下马不换回来」：存档 GearInsightForeverDB 是全账号共用的，换装记录原来只有一份（ns.db.mtSwap）
--   → A 号骑着马下线、B 号上来换过一次就把 A 的记录冲掉（A 再上来戴着胡萝卜、没记录 = 永远不换回）；B 读到 A 的记录也换不回（原饰品不在 B 包里）
--   ⑪ 换装记录按角色分开存：ns.db.mtSwaps[角色-服务器] = { 槽位, 原饰品, 换上的 }；老的 ns.db.mtSwap 只在「这一格正戴着那件胡萝卜」时认领给当前角色
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end

local MT = { HOLD = 0.7, FADE = 0.8, t = 0 }   -- slot / orig / id：我们换上的那一格、原来那件（nil = 原来是空的）、换上的坐骑饰品
ns.MountTrinket = MT
-- 天空破碎者之鞭（只在能飞的地方）> 马鞭 > 棍子上的胡萝卜。11-20 查无限客户端 DB2（1.60.1.70532 Item.csv）只有 11122，另两件留着不碍事
--   （主插件触发桩 MountStub.lua 只认 11122）
local IDS = { 32863, 25653, 11122 }
MT.IDS = IDS
local FLY = { [32863] = true }
local NAMES = { [11122] = { "棍子上的胡萝卜", "Carrot on a Stick" }, [25653] = { "马鞭", "Riding Crop" }, [32863] = { "天空破碎者之鞭", "Skybreaker Whip" } }

local function inv(slot) return GetInventoryItemID("player", slot) end
local function me() return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
-- ⑪ 本角色的换装记录（nil = 清掉；表空了整个删掉，触发桩靠它有没有决定加载）
function MT.SaveRec(r)
    if not ns.db then return end
    local t = ns.db.mtSwaps or {}
    t[me()] = r
    ns.db.mtSwaps = next(t) and t or nil
end
function MT.Rec() return ns.db and ns.db.mtSwaps and ns.db.mtSwaps[me()] end
local function cfn(k)
    local C = rawget(_G, "C_Container")
    return (type(C) == "table" and C[k]) or rawget(_G, k)
end
-- 那一格是什么物品：新接口 GetContainerItemID，没有就读 GetContainerItemInfo（新客户端返回表 .itemID）
local function slotID(bag, s)
    local f = cfn("GetContainerItemID")
    if f then return f(bag, s) end
    f = cfn("GetContainerItemInfo")
    local a = f and f(bag, s)
    if type(a) == "table" then return a.itemID end
    return nil
end
local function cont()
    return cfn("GetContainerNumSlots"), slotID, cfn("GetContainerNumFreeSlots"), cfn("PickupContainerItem")
end
local function equip(id, slot)
    local C = rawget(_G, "C_Item")
    local f = (type(C) == "table" and C.EquipItemByName) or rawget(_G, "EquipItemByName")
    if f then pcall(f, id, slot) end
end

function MT.Name(id)
    local C = rawget(_G, "C_Item")
    local ok, n = pcall((type(C) == "table" and C.GetItemNameByID) or GetItemInfo, id)
    if ok and type(n) == "string" and n ~= "" then return n end
    local t = NAMES[id]
    return t and L(t[1], t[2]) or ("#" .. tostring(id))
end

-- 背包里找这件 → bag, slot
function MT.Find(id)
    local num, get = cont()
    if not (num and get) then return nil end
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        for s = 1, tonumber(num(bag)) or 0 do
            if get(bag, s) == id then return bag, s end
        end
    end
end

-- 普通背包里的一个空格（特殊背包放不进饰品）→ bag, slot
function MT.FreeSlot()
    local num, get, free = cont()
    if not (num and get) then return nil end
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local fam = 0
        if free then fam = select(2, free(bag)) or 0 end
        if fam == 0 then
            for s = 1, tonumber(num(bag)) or 0 do
                if get(bag, s) == nil then return bag, s end
            end
        end
    end
end

-- 开关关着没有（直接读存档键：功能登记没有 / 子插件先于开关加载时也算数）
function MT.Off() return ns.db ~= nil and ns.db.mountTrinket == false end
-- 忙 / 没换成：过一会儿自己再看一眼（同一时间只排一个）
function MT.Later(sec)
    if MT.later then return end
    MT.later = true
    local f = function() MT.later = nil; if MT.wait or MT.slot then MT.wait = true; pcall(MT.Sync) end end
    if C_Timer and C_Timer.After then C_Timer.After(sec or 2, f) end
end

function MT.Busy()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    for _, f in ipairs({ UnitCastingInfo or false, UnitChannelInfo or false }) do   -- ⛔ 别放 nil：ipairs 遇到 nil 就停
        if f then
            local ok, v = pcall(function() return f("player") ~= nil end)   -- 12.0 引擎的秘密值只许判空，出错当没在读条
            if ok and v then return true end
        end
    end
    return false
end

-- 背包里该换上哪件（已经戴着任意一件坐骑饰品 = nil）
function MT.Pick()
    for _, id in ipairs(IDS) do
        if inv(13) == id or inv(14) == id then return nil end
    end
    local fly = IsFlyableArea and IsFlyableArea()
    for _, id in ipairs(IDS) do
        if (fly or not FLY[id]) and MT.Find(id) then return id end
    end
end

-- ---------- 屏幕中上方一行字，快速淡出 ----------
function MT.Fade(self, el)
    MT.t = MT.t + (tonumber(el) or 0)
    if MT.t >= MT.HOLD + MT.FADE then
        self:Hide()
    elseif MT.t > MT.HOLD then
        self:SetAlpha(1 - (MT.t - MT.HOLD) / MT.FADE)
    end
end
function MT.Say(msg)
    MT.msg = msg
    if not MT.tip then
        local t = CreateFrame("Frame", nil, UIParent)
        t:SetSize(640, 40)
        t:SetPoint("TOP", UIParent, "TOP", 0, -160)
        t:SetFrameStrata("HIGH")
        local fs = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("CENTER")
        t:SetScript("OnUpdate", MT.Fade)
        MT.tip, MT.fs = t, fs
    end
    MT.fs:SetText("|cff33ff99" .. msg .. "|r")
    MT.t = 0
    MT.tip:SetAlpha(1)
    MT.tip:Show()
end

-- ---------- 换上 / 换回 ----------
function MT.Equip()
    if MT.Off() then return false end
    local id = MT.Pick()
    if not id then return false end
    local slot = (inv(13) == nil and 13) or (inv(14) == nil and 14) or 14
    MT.slot, MT.orig, MT.id = slot, inv(slot), id
    MT.SaveRec({ slot, MT.orig or false, id })   -- 11-23 ⑤ 存档里也记一份（11-24 ⑪ 按角色）
    equip(id, slot)
    MT.Say(L("已换上 ", "Equipped ") .. MT.Name(id))
    return true
end

function MT.Clear()
    MT.slot, MT.orig, MT.id, MT.tries = nil, nil, nil, nil
    MT.SaveRec(nil)
    return false
end
MT.TRIES = 3
function MT.Restore()
    local slot, orig, id = MT.slot, MT.orig, MT.id
    if not slot or inv(slot) ~= id then return MT.Clear() end   -- 已经换成了 / 玩家自己换过这一格（或还没换上）：不覆盖，清记录
    if orig then
        if not MT.Find(orig) then return MT.Clear() end         -- 原饰品已经不在背包：放弃
        MT.tries = (MT.tries or 0) + 1
        if MT.tries > MT.TRIES then
            MT.Say(L("没换回 ", "Could not swap back ") .. MT.Name(orig) .. L("，请手动换", " - please swap it manually"))
            return MT.Clear()
        end
        equip(orig, slot)
        MT.Say(L("已换回 ", "Swapped back ") .. MT.Name(orig))
        if inv(slot) == orig then MT.Clear() else MT.Later(1.5) end   -- ⑧ 异步：记录留着，1.5 秒后确认（换成了 = 清记录，没换成 = 再换）
        return true
    end
    MT.Clear()
    -- 原来这一格是空的：摘回背包（背包满就不动）
    local _, _, _, pick = cont()
    local bag, s = MT.FreeSlot()
    if not (bag and pick and PickupInventoryItem) then return false end
    PickupInventoryItem(slot)
    pick(bag, s)
    if ClearCursor then ClearCursor() end
    MT.Say(L("已摘下 ", "Unequipped ") .. MT.Name(id))
    return true
end

-- 按现在骑没骑着补做；战斗中 / 读条 / 死亡 = 先不动（MT.wait 记着），等下面那几个事件再来
--   只在上下马状态变了 / 有排队时才干活（UNIT_AURA 很频繁，骑着马时别每次都扫背包）
function MT.Sync()
    local m = (IsMounted and IsMounted()) and true or false
    if m == MT.was and not MT.wait then return false end
    if MT.Busy() then MT.wait = true; MT.Later(); return false end
    MT.was, MT.wait = m, nil
    if m and not MT.Off() then
        if not MT.slot then return MT.Equip() end
    elseif MT.slot then   -- 下马 / 骑着马但开关关了：换回
        return MT.Restore()
    end
    return false
end

-- ---------- 11-23 ⑥ 开关图标 ----------
local CARROT = 11122
function MT.Owned() return MT.Find(CARROT) ~= nil or inv(13) == CARROT or inv(14) == CARROT end
function MT.BtnDB() ns.db.mtBtn = ns.db.mtBtn or {}; return ns.db.mtBtn end
function MT.BtnUpdate()
    local b = MT.btn
    if not b or not ns.db then return end
    if MT.BtnDB().hide or not MT.Owned() then b:Hide(); return end
    local on = not MT.Off()
    if b.icon.SetDesaturated then b.icon:SetDesaturated(not on) end
    b.icon:SetAlpha(on and 1 or 0.55)
    b.txt:SetText(on and ("|cff33ff99" .. L("上马换", "Auto") .. "|r") or ("|cffff5555" .. L("已关", "Off") .. "|r"))
    b:Show()
end
-- 开 / 关（v = nil 切换）：开着骑着马 = 当场换上；关掉时戴着我们换上的 = 当场换回
function MT.Toggle(v)
    if v == nil then v = MT.Off() end
    ns.SetFeature("mounttrinket", v and true or false)   -- 主插件 MountStub.lua 的 set 会当场补做（换上 / 换回）
    MT.BtnUpdate()
    MT.Say(v and L("上马自动换胡萝卜：开", "Mount trinket swap: on") or L("上马自动换胡萝卜：关", "Mount trinket swap: off"))
    return v
end
function MT.BtnTip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("上马自动换胡萝卜", "Mount trinket swap"), 1, 0.82, 0)
    if MT.Off() then
        GameTooltip:AddLine(L("已关：上马不换", "Off: no swap when mounting"), 1, 0.4, 0.4, true)
    else
        GameTooltip:AddLine(L("开着：上马换上胡萝卜，下马换回原饰品", "On: Carrot on a Stick while mounted, original trinket back on dismount"), 0.4, 1, 0.6, true)
    end
    if MT.slot then
        GameTooltip:AddLine(L("下马会换回：", "Will swap back to: ") .. (MT.orig and MT.Name(MT.orig) or L("（摘回背包）", "(unequip)")), 1, 1, 1, true)
    end
    GameTooltip:AddLine(L("左键：开 / 关　按住左键拖：挪位置　右键点两下：隐藏图标（设置 → 窗口与提醒 找回）", "Left: on/off · Drag: move · Right-click twice: hide (Settings > Windows & alerts)"), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end
function MT.BtnHide(hide)
    MT.BtnDB().hide = hide and true or nil
    if not hide then MT.Btn() end
    MT.BtnUpdate()
    if hide then
        ns.Print(L("胡萝卜开关图标已隐藏。找回：GI 菜单 → 设置 → 窗口与提醒「胡萝卜开关图标」点「显示」，或 /gi 上马饰品 图标",
            "Carrot icon hidden. Bring it back: GI menu > Settings > Windows & alerts > Carrot icon, or /gi mounttrinket icon"))
        ns.Print(L("（只收起图标，上马换胡萝卜照常；要关掉功能：设置 → 通用「上马自动换胡萝卜」取消勾选）",
            "(Only the icon is hidden - the swap stays on. To turn it off: Settings > General > Mount trinket swap)"))
    end
end
-- 11-23 GI-340「上马自动切换饰品图标误关之后无法打开，没有打开的选项」：右键要 3 秒内点两下才隐藏（防手滑），「窗口与提醒」里能找回
MT.HIDE_CONFIRM = 3
function MT.BtnRight()
    local t = (GetTime and GetTime()) or 0
    if MT.hideAsk and t - MT.hideAsk <= MT.HIDE_CONFIRM then
        MT.hideAsk = nil
        return MT.BtnHide(true)
    end
    MT.hideAsk = t
    MT.Say(L("再点一次右键 = 隐藏图标（误点不用管）", "Right-click again to hide the icon"))
end
if ns.RegisterWindow then
    ns.RegisterWindow({ key = "mtBtn", order = 33, title = function() return L("胡萝卜开关图标（上马换饰品）", "Carrot icon (mount trinket)") end,
        state = function()
            if not ns.db then return "" end
            if MT.BtnDB().hide then return L("已隐藏", "Hidden") end
            if not MT.Owned() then return L("背包里没有胡萝卜（有了才显示）", "No Carrot on a Stick in bags") end
            return L("显示中（左键开关、按住拖动）", "Shown (left-click on/off, drag to move)")
        end,
        actions = function()
            local hidden = ns.db and MT.BtnDB().hide
            local off = MT.Off()
            return {
                { text = hidden and L("显示", "Show") or L("隐藏", "Hide"), fn = function() MT.BtnHide(not hidden) end },
                { text = L("复位位置", "Reset position"), fn = function() MT.BtnReset() end },
                { text = off and L("打开功能", "Turn on") or L("关掉功能", "Turn off"), fn = function() MT.Toggle(off) end },   -- 11-24 ⑩ 图标隐藏 ≠ 功能关
            }
        end })
end
MT.BTN_X, MT.BTN_Y = 220, -120   -- 默认位置（屏幕中间偏右下，避开头像框 / 目标框）
-- 位置复原（/gi 上马饰品 图标 复位）
function MT.BtnReset()
    MT.BtnDB().pos, MT.BtnDB().hide = nil, nil
    MT.Btn()
    local b = MT.btn
    if b then b:ClearAllPoints(); b:SetPoint("CENTER", UIParent, "CENTER", MT.BTN_X, MT.BTN_Y) end
    MT.BtnUpdate()
end
function MT.Btn()
    if MT.btn then return MT.BtnUpdate() end
    local b = CreateFrame("Button", "GearInsightForeverCarrotBtn", UIParent)
    b:SetSize(34, 34)
    -- 11-23 用户截图「这个移动不了吗」：默认位置压在头像框底下（MEDIUM 层比头像框低，鼠标点到的是头像框）→ 提到 HIGH、换到屏幕中间偏右下
    b:SetFrameStrata("HIGH")
    if b.SetToplevel then b:SetToplevel(true) end
    if b.SetClampedToScreen then b:SetClampedToScreen(true) end
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local p = MT.BtnDB().pos
    if type(p) == "table" and p[1] then b:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
    else b:SetPoint("CENTER", UIParent, "CENTER", MT.BTN_X, MT.BTN_Y) end
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetAllPoints()
    local C = rawget(_G, "C_Item")
    local okI, tex = pcall((type(C) == "table" and C.GetItemIconByID) or GetItemIcon or function() end, CARROT)
    ic:SetTexture(okI and tex or "Interface\\Icons\\INV_Misc_Food_54")
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.icon, b.txt = ic, txt
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rp, x, y = self:GetPoint()
        MT.BtnDB().pos = { pt, rp, x, y }
    end)
    b:SetScript("OnClick", function(_, btn) if btn == "RightButton" then MT.BtnRight() else MT.Toggle() end end)
    b:SetScript("OnEnter", MT.BtnTip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    MT.btn = b
    MT.BtnUpdate()
end

-- 读回存档里没换回的那一格（骑着马 /reload / 下线过）
do
    local old = ns.db and ns.db.mtSwap   -- ⑪ 老版本那一份（不知道是哪个角色的）：这一格正戴着那件才认领
    if ns.db then ns.db.mtSwap = nil end
    if type(old) == "table" and old[1] and not MT.Rec() and inv(old[1]) == old[3] then MT.SaveRec({ old[1], old[2], old[3] }) end
    local r = MT.Rec()
    if type(r) == "table" and r[1] then MT.slot, MT.orig, MT.id = r[1], r[2] or nil, r[3] end
end
if ns.db then pcall(MT.Btn) end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)   -- ⛔ 容错注册：客户端没有的事件名会报错
end
for _, e in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
end
pcall(ev.RegisterEvent, ev, "COMPANION_UPDATE")
ev:SetScript("OnEvent", function(_, e)
    if e == "BAG_UPDATE_DELAYED" or e == "PLAYER_EQUIPMENT_CHANGED" then if MT.btn then pcall(MT.BtnUpdate) else pcall(MT.Btn) end return end   -- 11-23 有没有胡萝卜变了：图标出 / 收
    if e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_ENTERING_WORLD" then MT.wait = true end   -- 11-24 ⑨ 脱战 / 传送 / 进出副本：不管上下马状态记没记错，都按现在补做一遍
    pcall(MT.Sync)
end)
MT.ev = ev   -- 测试用

-- /gi 上马饰品 [开|关] · /gi mounttrinket [on|off]：不带参数 = 切换（主插件 MountStub.lua 放的是占位：先加载本子插件再转过来）
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["上马饰品"] = function(rest, raw)
    local r, c = (rest or ""):gsub("%s", ""), (raw or ""):gsub("%s", "")   -- rest 已转小写；中文按原样（raw）认
    if r:find("reset", 1, true) or (raw or ""):find("复位", 1, true) then   -- 11-23 图标拖丢了 / 被挡住：回到默认位置
        MT.BtnReset()
        ns.Print(L("胡萝卜开关图标：已回到默认位置（屏幕中间偏右下），按住左键可以拖", "Carrot icon reset to the default position - drag with the left button"))
        return
    end
    if r == "icon" or (raw or ""):find("图标", 1, true) then   -- 11-23 开关图标隐藏 / 找回（中文按字面找：%s 在某些区域设置下会吃掉中文字节）
        MT.BtnHide(not MT.BtnDB().hide)
        if not MT.BtnDB().hide then ns.Print(L("胡萝卜开关图标：已显示（右键隐藏）", "Carrot icon shown (right-click to hide)")) end
        return
    end
    local on = not MT.Off()
    local v = r == "on" or c == "开" or (r ~= "off" and c ~= "关" and not on)
    ns.SetFeature("mounttrinket", v)   -- 11-24 换上 / 换回都由 MountStub.lua 的 set 当场补做（战斗中 = 脱战后）
    on = not MT.Off()
    ns.Print(L("上马自动换饰品：", "Mount trinket swap: ") .. (on and L("开", "on") or L("关", "off"))
        .. L("（上马换上棍子上的胡萝卜，下马换回原饰品；屏幕上的胡萝卜图标左键也能开关；设置 → 通用「上马自动换胡萝卜」）", " (Carrot on a Stick while mounted, original trinket back on dismount; also the carrot icon on screen; Settings > General > Mount trinket swap)"))
end
ns.ExtraSlash.mounttrinket = ns.ExtraSlash["上马饰品"]
