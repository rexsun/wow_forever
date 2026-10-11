local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not (YUI and YUI.IsWrath == true and S and S.RegisterPack
    and S.RegisterKeys and type(S.BuiltinVoiceCommon) == "table") then
    return
end

local function Voice(path)
    return YUI.Assets:Bundle("voice-wyjj-wrath", path)
end

local sounds = {}
for key, file in pairs(S.BuiltinVoiceCommon) do sounds[key] = file end
local versionSounds = {

    -- 通用
    ["饰品触发"] = Voice("饰品触发.ogg"),
    ["特效触发"] = Voice("特效触发.ogg"),
    ["附魔触发"] = Voice("附魔触发.ogg"),
    ["橙杖触发"] = Voice("橙杖触发.ogg"),
    ["宝石触发"] = Voice("宝石触发.ogg"),
    ["饰品就绪"] = Voice("饰品就绪.ogg"),
    ["手套就绪"] = Voice("手套就绪.ogg"),

    ["伟大"] = Voice("伟大.ogg"),
    ["死钟"] = Voice("死钟.ogg"),
    ["节能"] = Voice("节能.ogg"),
    ["十字军"] = Voice("十字军.ogg"),

    -- 队友
    ["激活"] = Voice("激活.ogg"),

    ["集结"] = Voice("集结.ogg"),
    ["保护"] = Voice("保护.ogg"),
    ["牺牲"] = Voice("牺牲.ogg"),
    ["盾墙"] = Voice("盾墙.ogg"),
    ["破釜"] = Voice("破釜.ogg"),
    ["圣佑"] = Voice("圣佑.ogg"),
    ["神圣牺牲"] = Voice("神圣牺牲.ogg"),
    ["树皮"] = Voice("树皮.ogg"),
    ["宁静"] = Voice("宁静.ogg"),
    ["冰封"] = Voice("冰封.ogg"),
    ["吸血鬼"] = Voice("吸血鬼.ogg"),
    ["天使"] = Voice("天使.ogg"),
    ["干涉"] = Voice("干涉.ogg"),
    ["无敌"] = Voice("无敌.ogg"),

    -- 职业
    ["奥强就绪"] = Voice("奥强就绪.ogg"),
    ["压制就绪"] = Voice("压制就绪.ogg"),
    ["赞美诗就绪"] = Voice("赞美诗就绪.ogg"),
    ["圣歌就绪"] = Voice("圣歌就绪.ogg"),
    ["暗影魔就绪"] = Voice("暗影魔就绪.ogg"),
    ["根除"] = Voice("根除.ogg"),
    ["流星"] = Voice("流星.ogg"),

    ["剑舞就绪"] = Voice("剑舞就绪.ogg"),
    ["杀戮就绪"] = Voice("杀戮就绪.ogg"),
    ["嫁祸就绪"] = Voice("嫁祸就绪.ogg"),
    ["切割"] = Voice("切割.ogg"),
    ["割裂"] = Voice("割裂.ogg"),

    ["激活就绪"] = Voice("激活就绪.ogg"),
    ["宁静就绪"] = Voice("宁静就绪.ogg"),
    ["猛虎就绪"] = Voice("猛虎就绪.ogg"),

    ["急射就绪"] = Voice("急射就绪.ogg"),
    ["钉刺"] = Voice("钉刺.ogg"),
    ["陷阱"] = Voice("陷阱.ogg"),
    ["biubiubiu"] = Voice("biubiubiu.ogg"),

    ["补盾"] = Voice("补盾.ogg"),
    ["法潮就绪"] = Voice("法潮就绪.ogg"),
    ["掌握就绪"] = Voice("掌握就绪.ogg"),
    ["狼魂就绪"] = Voice("狼魂就绪.ogg"),
    ["土爹就绪"] = Voice("土爹就绪.ogg"),
    ["火爹就绪"] = Voice("火爹就绪.ogg"),

    ["死愿就绪"] = Voice("死愿就绪.ogg"),
    ["撕裂"] = Voice("撕裂.ogg"),

    ["圣印"] = Voice("圣印.ogg"),
    ["道标"] = Voice("道标.ogg"),
    ["神启就绪"] = Voice("神启就绪.ogg"),
    ["翅膀就绪"] = Voice("翅膀就绪.ogg"),
    ["无敌就绪"] = Voice("无敌就绪.ogg"),
    ["圣佑就绪"] = Voice("圣佑就绪.ogg"),
    ["圣疗就绪"] = Voice("圣疗就绪.ogg"),
    ["春哥"] = Voice("春哥.ogg"),

    ["冰封就绪"] = Voice("冰封就绪.ogg"),
    ["铜墙铁壁就绪"] = Voice("铜墙铁壁就绪.ogg"),
    ["天鬼就绪"] = Voice("天鬼就绪.ogg"),
    ["符文武器就绪"] = Voice("符文武器就绪.ogg"),
    ["大军就绪"] = Voice("大军就绪.ogg"),
    ["骨盾"] = Voice("骨盾.ogg"),
    ["天鬼飞走了"] = Voice("天鬼飞走了.ogg"),

    -- 团本
    ["快跑开"] = Voice("Runaway.ogg"),
    ["解诅咒"] = Voice("Curse.ogg"),
    ["解魔法"] = Voice("Magic.ogg"),
    ["解疾病"] = Voice("Disease.ogg"),
    ["解毒"] = Voice("解毒.ogg"),
    ["进攻驱散"] = Voice("Spellsteal.ogg"),
    ["远离BOSS"] = Voice("AwayBoss.ogg"),
    ["小怪快打"] = Voice("Adds.ogg"),
    ["远离小怪"] = Voice("AwayAdds.ogg"),
    ["远离人群"] = Voice("AwayCrowed.ogg"),
    ["击飞"] = Voice("Knock.ogg"),
    ["反射"] = Voice("Reflect.ogg"),
    ["快打断"] = Voice("Kick.ogg"),
    ["跳"] = Voice("Jump.ogg"),
    ["分散"] = Voice("Spread.ogg"),

}
for key, file in pairs(versionSounds) do sounds[key] = file end

S:RegisterKeys("yui.voice.wrath.wyjj", sounds)
S:RegisterPack("yui.voice.wrath.wyjj", {
    name = "YUI 时光服语音包",
    author = "忘忧景久",
    authorInfo = "YUI 内置中文语音包 · Wrath/Classic Titan",
    version = "2.3",
    clientVersion = "wrath",
    isDefault = true,
    sounds = sounds,
})

S.Sounds = sounds
