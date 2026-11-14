-- GearInsight_Forever_Plan 的最后一个文件：前面的页面 / 数据都加载完了，告诉主插件「可以用了」（UI.lua 的 MODS.plan.ready、PlanStub.lua 的 ns.PlanLoad 认这个标记）
-- 合并打包时这个文件排在主插件 toc 最后，同样把标记置上（那时没有子插件文件夹，PlanStub.lua 不放占位页）
local _, ns = ...; ns = _G.GearInsightForever or ns
ns._planReady = true
