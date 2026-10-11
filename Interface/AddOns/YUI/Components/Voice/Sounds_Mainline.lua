local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not (YUI and YUI.IsRetail == true and S and S.RegisterPack
    and S.RegisterKeys and type(S.BuiltinVoiceCommon) == "table") then
    return
end

local function Voice(path)
    return YUI.Assets:Bundle("voice-wyjj-mainline", path)
end

local sounds = {}
for key, file in pairs(S.BuiltinVoiceCommon) do sounds[key] = file end
local versionSounds = {
    ["暗刃就绪"] = Voice("暗刃就绪.ogg"),
    ["奥术之魂"] = Voice("奥术之魂.ogg"),
    ["白虎就绪"] = Voice("白虎就绪.ogg"),
    ["百发就绪"] = Voice("百发就绪.ogg"),
    ["暴君就绪"] = Voice("暴君就绪.ogg"),
    ["爆发就绪"] = Voice("爆发就绪.ogg"),
    ["崩摧10层"] = Voice("崩摧10层.ogg"),
    ["崩摧就绪"] = Voice("崩摧就绪.ogg"),
    ["冰柱就绪"] = Voice("冰柱就绪.ogg"),
    ["补地毯"] = Voice("补地毯.ogg"),
    ["补黑檀"] = Voice("补黑檀.ogg"),
    ["补疾病"] = Voice("补疾病.ogg"),
    ["补铁鬃"] = Voice("补铁鬃.ogg"),
    ["补绽放"] = Voice("补绽放.ogg"),
    ["打单体"] = Voice("打单体.ogg"),
    ["打风暴"] = Voice("打风暴.ogg"),
    ["大狗熊"] = Voice("大狗熊.ogg"),
    ["大龙"] = Voice("大龙.ogg"),
    ["地狱火就绪"] = Voice("地狱火就绪.ogg"),
    ["凋零"] = Voice("凋零.ogg"),
    ["毒镰"] = Voice("毒镰.ogg"),
    ["二号机就绪"] = Voice("二号机就绪.ogg"),
    ["过热高温"] = Voice("过热高温.ogg"),
    ["黑眼就绪"] = Voice("黑眼就绪.ogg"),
    ["横扫就绪"] = Voice("横扫就绪.ogg"),
    ["化身就绪"] = Voice("化身就绪.ogg"),
    ["幻能就绪"] = Voice("幻能就绪.ogg"),
    ["灰烬就绪"] = Voice("灰烬就绪.ogg"),
    ["毁灭之风就绪"] = Voice("毁灭之风就绪.ogg"),
    ["假死触发"] = Voice("假死触发.ogg"),
    ["精兵就绪"] = Voice("精兵就绪.ogg"),
    ["静滞激活"] = Voice("静滞激活.ogg"),
    ["静滞就绪"] = Voice("静滞就绪.ogg"),
    ["君王就绪"] = Voice("君王就绪.ogg"),
    ["考验10层"] = Voice("考验10层.ogg"),
    ["快补奉献"] = Voice("快补奉献.ogg"),
    ["快打焚身"] = Voice("快打焚身.ogg"),
    ["快打顺劈"] = Voice("快打顺劈.ogg"),
    ["快翻书"] = Voice("快翻书.ogg"),
    ["狂龙就绪"] = Voice("狂龙就绪.ogg"),
    ["黎明两层"] = Voice("黎明两层.ogg"),
    ["链接就绪"] = Voice("链接就绪.ogg"),
    ["灵魂腐化就绪"] = Voice("灵魂腐化就绪.ogg"),
    ["龙吼就绪"] = Voice("龙吼就绪.ogg"),
    ["龙喷就绪"] = Voice("龙喷就绪.ogg"),
    ["玛胖"] = Voice("玛胖.ogg"),
    ["免费圣令"] = Voice("免费圣令.ogg"),
    ["灭战就绪"] = Voice("灭战就绪.ogg"),
    ["明月就绪"] = Voice("明月就绪.ogg"),
    ["青龙就绪"] = Voice("青龙就绪.ogg"),
    ["深呼吸就绪"] = Voice("深呼吸就绪.ogg"),
    ["神器就绪"] = Voice("神器就绪.ogg"),
    ["升华就绪"] = Voice("升华就绪.ogg"),
    ["升腾就绪"] = Voice("升腾就绪.ogg"),
    ["死印就绪"] = Voice("死印就绪.ogg"),
    ["天启就绪"] = Voice("天启就绪.ogg"),
    ["天神就绪"] = Voice("天神就绪.ogg"),
    ["停"] = Voice("停.ogg"),
    ["突变就绪"] = Voice("突变就绪.ogg"),
    ["突袭就绪"] = Voice("突袭就绪.ogg"),
    ["吞病"] = Voice("吞病.ogg"),
    ["万灵就绪"] = Voice("万灵就绪.ogg"),
    ["消失就绪"] = Voice("消失就绪.ogg"),
    ["协同就绪"] = Voice("协同就绪.ogg"),
    ["亵渎"] = Voice("亵渎.ogg"),
    ["玄牛就绪"] = Voice("玄牛就绪.ogg"),
    ["血兽降临"] = Voice("血兽降临.ogg"),
    ["印记就绪"] = Voice("印记就绪.ogg"),
    ["涌动就绪"] = Voice("涌动就绪.ogg"),
    ["预兆加盾"] = Voice("预兆加盾.ogg"),
    ["预兆减CD"] = Voice("预兆减CD.ogg"),
    ["预兆全开"] = Voice("预兆全开.ogg"),
    ["预兆增疗"] = Voice("预兆增疗.ogg"),
    ["怨毒就绪"] = Voice("怨毒就绪.ogg"),
    ["扎昆"] = Voice("扎昆.ogg"),
    ["朱鹤就绪"] = Voice("朱鹤就绪.ogg"),
    ["主母"] = Voice("主母.ogg"),
    ["转转锤就绪"] = Voice("转转锤就绪.ogg"),
    ["壮胆酒就绪"] = Voice("壮胆酒就绪.ogg"),
    ["追击就绪"] = Voice("追击就绪.ogg"),
    ["准备大锤"] = Voice("准备大锤.ogg"),
    ["准备皎月"] = Voice("准备皎月.ogg"),
}
for key, file in pairs(versionSounds) do sounds[key] = file end

S:RegisterKeys("yui.voice.mainline.wyjj", sounds)
S:RegisterPack("yui.voice.mainline.wyjj", {
    name = "YUI 正式服语音包",
    author = "忘忧景久",
    authorInfo = "YUI 内置中文语音包 · Mainline",
    version = "2.3",
    clientVersion = "mainline",
    isDefault = true,
    sounds = sounds,
})

S.Sounds = sounds
