-- 资讯子插件（GearInsight_Forever_Info）在主插件里的「占位」（11-13 重构第 4 期，docs/forever-ui-refactor-design.md 第 4.3 节）
-- 资讯 / 共建 / 进阶 三页、我的升级报告、站外链接 / 支持页、扫码绑定（HOLD）、攻略页（HOLD）登录不加载，第一次用到才 LoadAddOn：
--   · 点这几页的页签 / /gi news（ToggleMain）/ 小地图菜单
--   · /gi report · 报告 · support · 支持 · site · web · bug · 报错 · bind · 绑定 · guide · 攻略（斜杠占位）
--   · 升级路线页底部「复制网页版」（ns.LandingURL 外壳）
-- 留在主插件的：Board.lua / GuideData.lua / GuideLikes.lua —— 更新器按固定路径整份覆盖 GearInsight_Forever/ 下的这几个文件，
--   挪走就收不到更新了（GuideData / GuideLikes 在 HOLD 里；攻略页解除 HOLD 前要先把更新器的覆盖路径改到 _Info，见设计文档 4.2）。
--   位面页 PageLayer.lua 也留在主插件：它是右侧页签（不是左栏页），和位面底座 Layer.lua 的扫描 / 广播共用状态，搬走只省约 60 KB。
local _, ns = ...

local M = ns.LazyModule({ key = "info", addon = "GearInsight_Forever_Info", zh = "资讯", en = "News",
    what = "资讯 / 共建 / 进阶页和升级报告", whatEn = "News / Board / Advanced pages and the leveling report" })
ns._InfoMod = M   -- 测试用

-- ⛔ 页名 / 顺序 / 图标要和各文件里真页的 ns.RegisterPage 一模一样
M:Page({ key = "guide", order = 0.5, title = ns.L("攻略", "Guides"), tabTitle = ns.L("攻略", "Guides"),
    icon = "Interface\\Icons\\INV_Misc_Book_09", hold = true, file = "PageGuide.lua" })
M:Page({ key = "news", order = 3.5, title = ns.L("资讯", "News"), file = "PageNews.lua" })
M:Page({ key = "board", order = 3.55, title = ns.L("共建", "Build Board"), tabTitle = ns.L("共建", "Board"),
    icon = "Interface\\Icons\\Trade_BlackSmithing", hold = true, file = "PageBoard.lua" })
M:Page({ key = "adv", order = 3.7, title = ns.L("进阶 · 网站与小程序", "Advanced · web & app"), tabTitle = ns.L("进阶", "Advanced"),
    icon = "Interface\\Icons\\INV_Misc_Spyglass_02", file = "PageAdvanced.lua" })

-- 斜杠命令（⛔ 名单要和各文件实际登记的 ns.ExtraSlash 键一致，gi_forever_split_p4_test.py 核对）
-- /gi report：主插件 GuildChatLevel.lua 先登记成「公会通报」，拆分前 Report.lua 后加载把它顶成「升级报告」（公会通报另有 greport / 通报）→ force 照样顶
M:Slash({ "report", "报告" }, "Report.lua", true)
M:Slash({ "support", "支持", "site", "web" }, "Offsite.lua")
M:Slash({ "bug", "报错" }, "PageBoard.lua")
M:Slash({ "bind", "绑定" }, "BindQR.lua")
M:Slash({ "guide", "攻略" }, "PageGuide.lua")

-- 主插件里会用到的
M:Shell("LandingURL", { file = "Offsite.lua" })    -- Route.lua：升级路线页底部「复制网页版」
M:Shell("ShowBindQR", { file = "BindQR.lua" })     -- Core.lua：/gi help 里列不列 bind
M:Table("Report", "Report.lua")                    -- Core.lua：/gi help 里列不列 report

function ns.InfoLoad() return M:Load(nil, true) end
