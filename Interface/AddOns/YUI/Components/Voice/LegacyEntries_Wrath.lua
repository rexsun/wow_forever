local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not (YUI and YUI.IsWrath and S and S.ResolveEntry) or S.legacyWrathEntries then return end

-- Explicit compatibility aliases; never infer an identity from a display name at playback time.
local aliases = {
    ["切割"] = "VC-41e122ba",
    ["割裂"] = "VC-55609a67",
    ["撕裂"] = "VC-7924a697",
    ["骨盾"] = "VC-4ea21340",
    ["猛虎就绪"] = "VC-c6c46533",
    ["春哥"] = "VC-63a8c0bd",
    ["变身"] = "VC-4ba7c753",
    ["变身就绪"] = "VC-412deadd",
    ["冰脉就绪"] = "VC-dffc949d",
    ["冲动就绪"] = "VC-a505a348",
    ["大风车就绪"] = "VC-7b1a45c6",
    ["灌注"] = "VC-57573b5d",
    ["灌注就绪"] = "VC-b69326b5",
    ["红人就绪"] = "VC-bce745ee",
    ["狂暴就绪"] = "VC-0afc661a",
    ["鲁莽就绪"] = "VC-47f45d56",
    ["燃烧就绪"] = "VC-acf05bbe",
    ["刃舞就绪"] = "VC-70937006",
    ["嗜血就绪"] = "VC-8700efce",
    ["小猪"] = "VC-12726233",
    ["压制"] = "VC-ee9c3c19",
    ["影舞就绪"] = "VC-4bf87d3d",
    ["饰品触发"] = "VC-88657dc3",
    ["特效触发"] = "VC-bb97a9c4",
    ["附魔触发"] = "VC-270525ce",
    ["橙杖触发"] = "VC-77a83b42",
    ["宝石触发"] = "VC-29d58b33",
    ["饰品就绪"] = "VC-4d2915ad",
    ["手套就绪"] = "VC-17517752",
    ["伟大"] = "VC-1545d75b",
    ["死钟"] = "VC-dac00d98",
    ["节能"] = "VC-758d05bf",
    ["十字军"] = "VC-e9046bbd",
    ["激活"] = "VC-dd1286c2",
    ["集结"] = "VC-083bfd8f",
    ["保护"] = "VC-0f810a79",
    ["牺牲"] = "VC-193c786c",
    ["盾墙"] = "VC-9bfe5155",
    ["破釜"] = "VC-cf5e7540",
    ["圣佑"] = "VC-ca23a878",
    ["神圣牺牲"] = "VC-5928f3df",
    ["树皮"] = "VC-156ad159",
    ["宁静"] = "VC-510ccc24",
    ["冰封"] = "VC-d3fe820f",
    ["吸血鬼"] = "VC-0c6918a0",
    ["天使"] = "VC-970d69ad",
    ["干涉"] = "VC-74b29571",
    ["无敌"] = "VC-78af2f47",
    ["奥强就绪"] = "VC-47a828c1",
    ["压制就绪"] = "VC-964365c3",
    ["赞美诗就绪"] = "VC-69420449",
    ["圣歌就绪"] = "VC-916a79a2",
    ["暗影魔就绪"] = "VC-1503504d",
    ["根除"] = "VC-a3b61ae2",
    ["流星"] = "VC-b80b2398",
    ["剑舞就绪"] = "VC-7fa6a05b",
    ["杀戮就绪"] = "VC-b7a29ff0",
    ["嫁祸就绪"] = "VC-8f3b43e7",
    ["激活就绪"] = "VC-215f1f39",
    ["宁静就绪"] = "VC-551f0075",
    ["急射就绪"] = "VC-75b7c5ca",
    ["钉刺"] = "VC-0a7cfb7d",
    ["陷阱"] = "VC-e70e9164",
    ["biubiubiu"] = "VC-768a552a",
    ["补盾"] = "VC-cf5a8162",
    ["法潮就绪"] = "VC-ff5ea538",
    ["掌握就绪"] = "VC-96b01ec9",
    ["狼魂就绪"] = "VC-49a4c0e0",
    ["土爹就绪"] = "VC-8eba7c6c",
    ["火爹就绪"] = "VC-16b10e98",
    ["死愿就绪"] = "VC-00d2ce68",
    ["圣印"] = "VC-7eb5ab59",
    ["道标"] = "VC-98f5991b",
    ["神启就绪"] = "VC-7ec7cd1d",
    ["翅膀就绪"] = "VC-299a54c9",
    ["无敌就绪"] = "VC-4ccd0b37",
    ["圣佑就绪"] = "VC-b5b2f81d",
    ["圣疗就绪"] = "VC-50ae8d58",
    ["冰封就绪"] = "VC-fcbdde80",
    ["铜墙铁壁就绪"] = "VC-b5ab8489",
    ["天鬼就绪"] = "VC-e09b3463",
    ["符文武器就绪"] = "VC-d667e6b8",
    ["大军就绪"] = "VC-9e6b5f49",
    ["天鬼飞走了"] = "VC-7ae621c1",
    ["快跑开"] = "VC-0ec430f5",
    ["解诅咒"] = "VC-34231d5b",
    ["解魔法"] = "VC-9d592d2b",
    ["解疾病"] = "VC-769bb619",
    ["解毒"] = "VC-021c2534",
    ["进攻驱散"] = "VC-14f7092a",
    ["远离BOSS"] = "VC-b9d78dc8",
    ["小怪快打"] = "VC-95ae29fc",
    ["远离小怪"] = "VC-ceee2b0c",
    ["远离人群"] = "VC-22f7fd38",
    ["击飞"] = "VC-e49941ad",
    ["反射"] = "VC-8a8f1a0c",
    ["快打断"] = "VC-fcf275ef",
    ["跳"] = "VC-d659bfa6",
    ["分散"] = "VC-e5c5028b",
}
S.legacyWrathEntries = aliases
local BUILTIN = 'yui.voice.wrath.wyjj'
local SoundAPI = YUI.API and YUI.API.Sound

function S:ResolveLegacyEntry(key, legacyPackId, failedPackId)
    local id = aliases[key]
    if legacyPackId ~= BUILTIN or not id or self:GetActivePackId() ~= BUILTIN then return end
    local prefs = self.GetPreferences and self:GetPreferences()
    local selected = prefs and prefs.voicePackId or 'yui.default'
    if failedPackId then
        if failedPackId == 'yui.default' or prefs and prefs.fallbackDefault == false then return end
        selected = 'yui.default'
    end
    local resource = self:ResolveEntry(id, {
        packId = selected, fallbackDefault = not prefs or prefs.fallbackDefault ~= false,
        fallbackTTS = false,
    })
    if resource and resource.kind == 'file' then return resource end
end

function S:PlayLegacyFallback(reference, failedPackId, failedFile, channel)
    local key = type(reference) == 'string' and reference:match('^voice:(.+)$')
    if not (key and aliases[key] and SoundAPI and SoundAPI.PlayFile) then return false end
    local pack = self:GetActivePack()
    if not pack or pack.id ~= BUILTIN then return false end
    local resource = self:ResolveLegacyEntry(key, pack.id, failedPackId)
    if resource and resource.value ~= failedFile then
        local played, handle = SoundAPI.PlayFile(resource.value, channel)
        if played then return true, handle end
    end
    local file = pack.sounds[key]
    if file and file ~= failedFile and (not resource or file ~= resource.value) then
        return SoundAPI.PlayFile(file, channel)
    end
    return false
end
