-- 组队子插件的「按需加载调度」（11-13 界面重构第 5 期）：
--   GearInsight_Forever_Group（登录加载）= 信标 QuestMates.lua + 副本组队小核 DungeonChatCore.lua + 本文件
--   GearInsight_Forever_GroupUI（按需）  = 任务组队抽屉 QuestMatesUI.lua + 副本组队面板 DungeonChat.lua（+ HOLD 的 GroupLFG / PageGroup / LfgProbe）
--   GearInsight_Forever_GroupMage（按开关）= 法师吃喝 MageWater.lua
-- 法师吃喝什么时候登录就加载（GroupMageWanted）：招人页「法师吃喝」总开关开着；或者不是法师、且「野外碰到法师弹框」/「交易完成道谢」有一个开着（两个默认都开）。
--   是法师但总开关关着：法师那一半（自动回话 / 提醒条 / 一键放入）全挂在总开关上，登录不加载，打开「法师吃喝」子页签 / /gi 吃喝 时再加载。
--   加载以后由 MageWater.lua 的 MW.SyncEvents 按同样的开关只注册用得上的那一半事件；开关一改（细项面板 / 招人页按钮 / 窗口与提醒）就调 ns.GroupSync 重算。
local _, ns = ...; ns = _G.GearInsightForever or ns
local QM, DC = ns.QM, ns.DungeonChat
if not (QM and DC) then return end

local function myClass()
    if not UnitClass then return nil end
    local ok, _, cls = pcall(UnitClass, "player")
    if not ok or (ns.Secret and ns.Secret(cls)) then return nil end
    return cls
end
-- 只看存档（法师吃喝没加载时也能判断）；口径和 MageWater.lua 的 MW.DEFAULTS / MW.Opt 一致：nil = 默认开，false = 关
function ns.GroupMageWanted()
    local d = ns.db and ns.db.dchat
    if d and d.rec and d.rec.mageAsk then return true end
    if myClass() == "MAGE" then return false end
    local o = d and d.mw
    return not (o and o.fieldAsk == false) or not (o and o.thank == false)
end
-- force = 玩家要用（子页签 / 命令 / 设置里点「摆出来」）：不管开关都加载
function ns.GroupLoadMage(force)
    if ns.MageWater then return true end
    if not ns.LoadModule then return false end
    if not force then
        if not ns.db or not ns.GroupMageWanted() then return false end
        if not (ns.ModuleAvailable and ns.ModuleAvailable("mage")) then return false end
    end
    local ok, loaded = pcall(ns.LoadModule, "mage", not force)   -- 自动加载：插件列表里关了就静默跳过
    return (ok and loaded and ns.MageWater ~= nil) and true or false
end
-- 开关变了 / 登录：该加载的加载上，事件按开关重注册
function ns.GroupSync()
    if not ns.db then return end
    if not ns.MageWater then ns.GroupLoadMage(false) end
    local MW = ns.MageWater
    if MW and MW.SyncEvents then pcall(MW.SyncEvents) end
    if DC.SyncCore then pcall(DC.SyncCore) end
end

-- 斜杠命令占位：命令在按需加载的那两个子插件里注册，没加载时先加载再转过去
--   （主插件 UI.lua 也有一层占位：先加载本子插件 → 转到这里 → 再加载对应的那一块）
ns.ExtraSlash = ns.ExtraSlash or {}
local function slashStub(c, part, fallback)
    local stub
    stub = function(rest, rawRest)
        if part == "mage" then ns.GroupLoadMage(true) else QM.EnsureUI() end
        local f = ns.ExtraSlash[c]
        if f and f ~= stub then return f(rest, rawRest) end
        if fallback then return fallback() end
    end
    ns.ExtraSlash[c] = stub
end
for _, c in ipairs({ "吃喝", "water", "mw" }) do slashStub(c, "mage") end
slashStub("组队", "ui", function() return ns.OpenGroupDrawer("dungeon") end)
-- /gi lfg 不在这里挂：没有真处理函数，主插件 UI.lua 的占位直接 ns.OpenGroupDrawer()（信标会先加载界面）
for _, c in ipairs({ "lfg2", "lfgprobe" }) do slashStub(c, "ui", function() return ns.OpenGroupDrawer(nil) end) end

-- 登录：本子插件整个载完（ADDON_LOADED）再按开关加载法师吃喝、注册副本组队小核的事件
--   ⛔ 别在文件执行中途 LoadAddOn 依赖本插件的子插件（那时本插件还不算「已加载」）
local pev = CreateFrame("Frame")
pcall(pev.RegisterEvent, pev, "ADDON_LOADED")
pev:SetScript("OnEvent", function(self, _, name)
    if name ~= "GearInsight_Forever_Group" then return end
    pcall(self.UnregisterEvent, self, "ADDON_LOADED")
    pcall(ns.GroupSync)
end)
ns._GroupPartsEvent = pev:GetScript("OnEvent")   -- 测试用
-- 兜底：个别情况下没收到自己的 ADDON_LOADED（按需加载已经在登录之后）→ 1 秒后再同步一次（重复调用无害：已加载就直接返回）
local function selfLoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return false end
    local ok, yes = pcall(f, "GearInsight_Forever_Group")
    return ok and yes and true or false
end
if IsLoggedIn and IsLoggedIn() and C_Timer and C_Timer.After then C_Timer.After(1, function() if selfLoaded() then pcall(ns.GroupSync) end end) end
