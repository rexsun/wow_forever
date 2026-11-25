-- GearInsight_Forever_Xp 的最后一个文件：经验加成页 / 出发前清单 / 物资检查都加载完了，告诉主插件「可以用了」（ModStub.lua 的 ns.ModLoad 认这个标记）
-- 网易DD 包把这个子插件并进主文件夹（登录加载）时同样把标记置上（那时没有子插件文件夹，XpCheck.lua 不放占位）
local _, ns = ...; ns = _G.GearInsightForever or ns
ns._modReady = ns._modReady or {}
ns._modReady.xp = true
if ns.FlushInits then ns.FlushInits() end
