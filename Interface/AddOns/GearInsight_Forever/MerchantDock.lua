-- 商人助手面板宿主（11-17 用户截图「重合了，优化一下，是不是应该整合到一个」）
--   以前跟商人对话会同时弹两个框：卖垃圾面板（子插件 GearInsight_Forever_Bag 的 SellJunk.lua）和专业材料快捷窗
--   （子插件 GearInsight_Forever_Prof 的 PageProf.lua → ns.ProfShop），都锚在商人窗口右上角，标题和第一行叠在一起。
--   现在合成一个「GearInsight 商人助手」面板（一个外框：标题栏 / 一个 × / 一个「不再弹」/ 页签 / 位置），两块内容各自注册进来。
--   布局选「页签」而不是上下排：卖垃圾一屏 14 行（约 360 高）+ 材料最多 10 行（约 270 高），上下排要 650+，
--     1366×768 / UI 缩放大的屏幕放不下，还会盖到聊天框；页签面板高度 ≈ 商人窗口，切页不跳位置
--   · 两块都有内容 → 顶上两个页签「买材料 N」「卖垃圾 N」；有材料可买时默认先显示材料页（这次开商人点过页签就记住点的那页）
--   · 只有一块 → 不出页签、不占位，标题写「GearInsight 商人助手 · 卖垃圾」
--   · 两块都没有（都关了 / 都没东西）→ 整个面板不出
--   · ×：这次开商人两块都收起（下次开商人照常弹）
--   · 「不再弹」：只关当前页那一块（各自原来的开关：卖垃圾 = 设置「打开商人时显示卖垃圾面板」ns.db.sellJunk.panel；
--       材料 = ns.db.prof.quick，/gi 专业购买 重新打开），另一块照常；两块都关了面板就不出
--   · 位置：默认贴商人窗口右边；右边放不下 → 商人窗口下方（让开下沿的「GearInsight 冲专业」按钮）→ 再放不下 → 左边。
--       拖标题栏可以挪（存 ns.db.merchantDock，一份位置两块共用），右键标题栏回到商人窗口旁
--   ⛔ 内存：主插件这里只放「登记 / 开关状态」的小核（登录不建框、不建事件框）；外框 / 排版 / 位置的代码在子插件
--     GearInsight_Forever_Bag 的 MerchantDockUI.lua（卖垃圾本来就在那，默认第一次开商人就加载）。材料那块要弹时 D.UI() 经 ns.BagLoad 加载它；
--     清背包子插件没装 → D.UI() 返回 false，材料退回自己的独立小窗。主插件不 require 任何按需子插件
--   ⛔ 不改暴雪 MerchantFrame 的脚本，只 HookScript OnHide 兜底（在 MerchantDockUI.lua）
local _, ns = ...

local D = { W = 370, PAD = 8, HEAD = 24, TABH = 22, GAP = 4, HOLD_SEC = 0.45, secs = {}, list = {}, on = {} }
ns.MerchantDock = D

-- ---------- 注册 ----------
-- def = { order = 小的排前面, tab = function() 页签名, count = function() 件数（页签上的数字，nil = 不标）,
--         never = function() 关掉这一块的自动弹（存它自己的开关、聊天框说一声）, neverTip = function() 「不再弹」按钮的鼠标提示,
--         onClose = function() 玩家点了 ×（这次不弹）}
function D.Register(key, def)
    def.key = key
    if not D.secs[key] then D.list[#D.list + 1] = key end
    D.secs[key] = def
    table.sort(D.list, function(a, b) return (D.secs[a].order or 9) < (D.secs[b].order or 9) end)
    return def
end
function D.IsOn(key) return D.on[key] == true end
function D.Active()
    local t = {}
    for _, k in ipairs(D.list) do if D.on[k] then t[#t + 1] = k end end
    return t
end

-- 外框代码（D.Build / D.Body / D.Show / D.Hide / D.Layout / D.Place …）在不在；不在就加载清背包子插件（它带着外框）
function D.UI()
    if D.Build then return true end
    if type(ns.BagLoad) == "function" then pcall(ns.BagLoad, true) end
    return D.Build ~= nil
end
