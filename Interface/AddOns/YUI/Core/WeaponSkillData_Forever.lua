-- YUI 自主采集、整理的数据由作者阿言维护；随 YUI 正常使用无需另行申请。
-- 提取、复制、修改、转载、再分发或用于其他项目之前，须获得作者明确同意。
-- 游戏原有名称、资源及公开数据的权利归原权利人。
local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.IsForever) then return end

-- SkillLine / SkillLineAbility / SkillRaceClassInfo: Forever 1.60.1.70245。
-- 训练列表沿用已有校核资料；位置为玩家在 Forever 的采集坐标。
-- 拳套的学习能力为 473，实际熟练度与徒手战斗 162 共用。
YUI.WeaponSkillData = {
    flavor = "forever", build = "1.60.1.70245",
    skills = {
        { id=43, spellID=201, classMask=399 },
        { id=55, spellID=202, classMask=7 },
        { id=44, spellID=196, classMask=79 },
        { id=172, spellID=197, classMask=71 },
        { id=54, spellID=198, classMask=1115 },
        { id=160, spellID=199, classMask=1091 },
        { id=173, spellID=1180, classMask=1501 },
        { id=136, spellID=227, classMask=1493 },
        { id=229, spellID=200, classMask=1031, minLevel=20 },
        { id=473, rankID=162, spellID=15590, classMask=1101 },
        { id=45, spellID=264, classMask=13 },
        { id=226, spellID=5011, classMask=13 },
        { id=46, spellID=266, classMask=13 },
        { id=176, spellID=2567, classMask=13 },
        { id=228, spellID=5009, classMask=400, sourceKey="weapon_skill.source.class" },
        { id=162, spellID=203, classMask=1535, sourceKey="weapon_skill.source.class" },
        { id=3014, spellID=1306742, classMask=1024, sourceKey="weapon_skill.source.class" },
    },
    sites = {
        { id="stormwind", mapID=1453, faction="Alliance", x=0.63874632120132, y=0.69096398353577,
            trainers = {{ id="woo_ping", skills={173,226,43,55,229,136} }} },
        { id="ironforge", mapID=1455, faction="Alliance", x=0.61759984493256, y=0.89227634668350,
            trainers = {{ id="buliwyf", skills={473,46,44,172,54,160} },
                { id="bixi", skills={173,226,176} }} },
        { id="darnassus", mapID=1457, faction="Alliance", x=0.57510465383530, y=0.46931222081184,
            trainers = {{ id="ilyenia", skills={45,173,473,136,176} }} },
        { id="orgrimmar", mapID=1454, faction="Horde", x=0.81516104936600, y=0.19383578002453,
            trainers = {{ id="sayoc", skills={45,173,473,44,172,176} },
                { id="hanashi", skills={45,44,172,136,176} }} },
        { id="undercity", mapID=1458, faction="Horde", x=0.57175505161285, y=0.32437789440155,
            trainers = {{ id="archibald", skills={226,173,43,55,229} }} },
        { id="thunder_bluff", mapID=1456, faction="Horde", x=0.40920162200928, y=0.62128400802612,
            trainers = {{ id="ansekhwa", skills={46,54,160,136} }} },
    },
}
for _, skill in ipairs(YUI.WeaponSkillData.skills) do skill.nameKey = "weapon_skill.name." .. skill.id end
for _, site in ipairs(YUI.WeaponSkillData.sites) do
    site.cityKey = "weapon_trainer.city." .. site.id
    site.pointID = "forever." .. site.mapID .. ".equipment.weapon_trainer"
    for _, trainer in ipairs(site.trainers) do trainer.nameKey = "weapon_trainer.name." .. trainer.id end
end
