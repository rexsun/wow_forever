-- GearInsight_Forever_Gate 的最后一个文件：路线弹框（+ 门任务数据 / 清单，进了包的话）都加载完了，告诉主插件「可以用了」（ModStub.lua 的 ns.ModLoad 认这个标记）
-- 网易DD 包把这个子插件并进主文件夹（登录加载）时同样把标记置上（那时没有子插件文件夹）
local _, ns = ...; ns = _G.GearInsightForever or ns
ns._modReady = ns._modReady or {}
ns._modReady.gate = true
if ns.SideChains and ns.SideChains.UpdateTracker and ns.db then pcall(ns.SideChains.UpdateTracker) end
