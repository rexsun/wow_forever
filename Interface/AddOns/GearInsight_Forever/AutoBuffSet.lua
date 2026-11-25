-- HOLD：GI-303 一键给路人上BUFF 的组队设置项（和 GearInsight_Forever_Class/AutoBuff.lua 一起解除 HOLD）
--   组队抽屉齿轮「组队设置」→「一键给路人上 BUFF（按钮 + 快捷键）」+「设置快捷键」；法师 / 牧师 / 德鲁伊才出。
--   放主插件：开关默认关时 _Class 不加载，设置项也要看得到；单独一个 HOLD 文件 = 发行包登录内存一点不涨（11-20 内核预算已满）。
--   勾上 = 功能中心同一个开关（ns.SetFeature("autobuff")，存 ns.db.autoBuff.on，加载 _Class）；「设置快捷键」先加载 _Class 再弹抓键框（战斗中排到脱战）
local _, ns = ...
local M = ns._ClassMod
local L = ns.L
local BIND = "CLICK GearInsightForeverAutoBuffBtn:LeftButton"   -- ⛔ 和 AutoBuff.lua 的 AB.BTN 一致
local function keyNow()
    if not GetBindingKey then return nil end
    local ok, k = pcall(GetBindingKey, BIND)
    if ok and type(k) == "string" and not (ns.Secret and ns.Secret(k)) then return k end
    return nil
end
local function bind()
    local function go() if ns.AutoBuff and ns.AutoBuff.BeginBind then ns.AutoBuff.BeginBind() end end
    if M:Load(go) then go() end
end
-- ⛔ 合并布局（发行包把 _Class 并进主插件）里 ModHas 要等 ClassInit.lua 跑完才认 → 排进 ns.modules（ADDON_LOADED 时）再判断、再登记
table.insert(ns.modules, function()
if not (ns.RegisterSettings and M and M:Has("AutoBuff.lua")) then return end
ns.RegisterSettings({ key = "buffgive", order = 96.5, drawer = "group",
    avail = function() return ns.MyClass ~= nil and ns.AUTOBUFF_CLS ~= nil and ns.AUTOBUFF_CLS[ns.MyClass()] == true end,
    title = function() return L("一键给路人上 BUFF", "One-key buffing") end, short = function() return L("上BUFF", "Give buffs") end,
    items = {
        { type = "check", id = "buffgive.on", text = function() return L("一键给路人上 BUFF（按钮 + 快捷键）", "One-key buffing for nearby players (button + key)") end,
          get = function() local t = ns.db and ns.db.autoBuff; return type(t) == "table" and t.on == true end,
          set = function(v) if ns.SetFeature then ns.SetFeature("autobuff", v) end end },
        { type = "button", id = "buffgive.key", indent = 18, w = 220, dyn = true,
          text = function() local k = keyNow(); return k and string.format(L("快捷键：%s（点了改）", "Key: %s (change)"), k) or L("设置快捷键（还没设）", "Set a key (none yet)") end,
          click = bind },
        { type = "note", indent = 18, text = function() return L("插件挑附近缺 BUFF 的玩家（目标 / 鼠标指向 / 队友 / 友方姓名板，近的先），你每按一下按钮或快捷键给一个人上（暴雪规定每次施法都要按键，插件不会自己放）。看附近路人要开友方姓名板（Shift+V）。战斗中只能给当前目标。法师奥术智慧 / 牧师真言术：韧 / 德鲁伊野性印记；圣骑士用「职业 → 一键祝福」。命令 /gi buff give on | off | key",
              "Picks nearby players missing your buff (target / mouseover / party / friendly nameplates, nearest first); each press of the button or key buffs one (Blizzard requires a key press per cast). Friendly nameplates (Shift+V) are needed to see strangers. In combat: current target only. Paladins: Class > Blessings. /gi buff give on | off | key") end },
    } })
end)
-- /gi buff give on|off|key → 一键给路人上BUFF（= /gi 上buff 开|关|键）。「/gi buff」本身是 _Group 要 BUFF 的命令：
--   这里包一层我们自己的 /gi 处理函数（Core.lua 的 SlashCmdList.GEARINSIGHTFOREVER，不碰 BuffAsk.lua、不给暴雪表整表赋值），只截「buff give …」，其余原样交回
local orig = SlashCmdList and SlashCmdList.GEARINSIGHTFOREVER
if orig then
    SlashCmdList.GEARINSIGHTFOREVER = function(msg, ...)
        local m = (msg or ""):gsub("[A-Z]", function(ch) return string.char(ch:byte() + 32) end)
        local r2 = m:match("^%s*buff%s+give%s*(.-)%s*$")
        local f = r2 and ns.ExtraSlash and rawget(ns.ExtraSlash, "autobuff")
        if f then return f(r2, r2) end
        return orig(msg, ...)
    end
end
