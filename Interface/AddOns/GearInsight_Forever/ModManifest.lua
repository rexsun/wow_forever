-- 自动生成：scripts/gi_forever_tocfiles.py（⛔ 别手改；改了子插件 toc 后跑 python scripts/gi_forever_tocfiles.py）。
-- 按需加载的子插件里有哪些文件（ModStub.lua 的 ns.ModHas 认它）：占位页 / 命令 / 设置项只给「真在包里」的功能放，
--   HOLD 的文件发版时不进包 —— 发版脚本按实际进包的文件重写这一份，所以包里这份没有 HOLD 的文件。
local _, ns = ...
ns._ModFiles = {
  prof = { ["ProfData.lua"] = true, ["ProfLib.lua"] = true, ["ProfPlan.lua"] = true, ["ProfRecipes.lua"] = true, ["PageProf.lua"] = true, ["ProfInit.lua"] = true },
  class = { ["DataClass.lua"] = true, ["DefaultBuildsData.lua"] = true, ["DefaultBuilds.lua"] = true, ["Talents.lua"] = true, ["PageTalent.lua"] = true, ["MacroData.lua"] = true, ["PageMacro.lua"] = true, ["PetData.lua"] = true, ["PagePet.lua"] = true, ["PetTameData.lua"] = true, ["PetTameObsData.lua"] = true, ["PetTame.lua"] = true, ["KeysFormData.lua"] = true, ["Keys.lua"] = true, ["KeysCdm.lua"] = true, ["KeysRotData.lua"] = true, ["KeysRot.lua"] = true, ["KeysCast.lua"] = true, ["KeysHud.lua"] = true, ["KeysKb.lua"] = true, ["PageKeys.lua"] = true, ["PageRot.lua"] = true, ["KeysProbe.lua"] = true, ["ClassInit.lua"] = true },
  info = { ["NewsData.lua"] = true, ["PageNews.lua"] = true, ["PageAdvanced.lua"] = true, ["Supporters.lua"] = true, ["Offsite.lua"] = true, ["Report.lua"] = true, ["PageBoard.lua"] = true, ["InfoInit.lua"] = true },
  groupui = { ["QuestMatesUI.lua"] = true, ["DungeonChat.lua"] = true },
  mage = { ["MageWater.lua"] = true },
}
