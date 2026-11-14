-- GearInsight_Forever_Prof 的最后一个文件：前面的页面 / 数据都加载完了，告诉主插件「可以用了」（ModStub.lua 的 ns.ModLoad / UI.lua 的 MODS.prof.ready 认这个标记）
-- 合并打包时这个文件排在主插件 toc 最后，同样把标记置上（那时没有子插件文件夹，ProfStub.lua 不放占位）
local _, ns = ...; ns = _G.GearInsightForever or ns
ns._modReady = ns._modReady or {}
ns._modReady.prof = true
if ns.FlushInits then ns.FlushInits() end   -- 这个子插件里用 ns.AddInit 登记的初始化（晚于登录加载时）现在跑
