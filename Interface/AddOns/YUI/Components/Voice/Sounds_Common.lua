local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not (YUI and S) then return end

local function Voice(path)
    return YUI.Assets:Bundle("voice-wyjj", path)
end

S.BuiltinVoiceCommon = {
    ["变身"] = Voice("变身.ogg"),
    ["变身就绪"] = Voice("变身就绪.ogg"),
    ["冰脉就绪"] = Voice("冰脉就绪.ogg"),
    ["冲动就绪"] = Voice("冲动就绪.ogg"),
    ["大风车就绪"] = Voice("大风车就绪.ogg"),
    ["灌注"] = Voice("灌注.ogg"),
    ["灌注就绪"] = Voice("灌注就绪.ogg"),
    ["红人就绪"] = Voice("红人就绪.ogg"),
    ["狂暴就绪"] = Voice("狂暴就绪.ogg"),
    ["鲁莽就绪"] = Voice("鲁莽就绪.ogg"),
    ["燃烧就绪"] = Voice("燃烧就绪.ogg"),
    ["刃舞就绪"] = Voice("刃舞就绪.ogg"),
    ["嗜血就绪"] = Voice("嗜血就绪.ogg"),
    ["小猪"] = Voice("小猪.ogg"),
    ["压制"] = Voice("压制.ogg"),
    ["影舞就绪"] = Voice("影舞就绪.ogg"),
}
