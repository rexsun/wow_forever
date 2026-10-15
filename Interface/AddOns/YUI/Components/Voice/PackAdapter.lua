local _, namespace = ...
local YUI = _G.YUI or namespace
local S = YUI and YUI.Sound
local System = YUI and YUI.API and YUI.API.System
if not (S and System and System.IsAddOnLoadedSafe) or S.PackAdapter then return end
local Adapter = {}
S.PackAdapter = Adapter

-- Reviewed [i9] recordings from the 1.0.1 catalog; complete Vorbis file durations.
-- IDs were assigned from normalized file paths and remain fixed if labels change.
local SpecialRecordings = {
    { id='SP-f4bf73a3fd246d53e7cc67f3', name='BiuBiuBiu', file='SFX\\BiuBiuBiu.ogg', duration=1.233741497 },
    { id='SP-e84cec7c1fb62c7407fc5e0e', name='嘎', file='SFX\\Duck.ogg', duration=0.447097506 },
    { id='SP-fdbc028143b29aa962ae94d9', name='我剑也未尝不利！', nameTW='我劍也未嘗不利！', file='SFX\\MySword.ogg', duration=1.685941043 },
    { id='SP-d7b2809f04cb89ac32251d42', name='咻咻', file='SFX\\XiuXiu.ogg', duration=0.707278912 },
    { id='SP-3ca20e2e8511abdf9f4d75ba', name='叮咚', file='SFX\\DingDong.ogg', duration=0.747845805 },
    { id='SP-ef7d5a50ca55c946f0bb2aaa', name='嘀嘀', file='SFX\\DiDi.ogg', duration=0.800000000 },
    { id='SP-20c98b436f83bc9e7c62ed2c', name='啊？', file='SFX\\Ah.ogg', duration=0.738526077 },
    { id='SP-c83c52aa83c6d366d3bb9165', name='oi！', file='SFX\\Oi.ogg', duration=0.400000000 },
    { id='SP-8cd86d8609513a321c10eefd', name='晚安玛卡巴卡', nameTW='晚安瑪卡巴卡', file='SFX\\Makabaka.ogg', duration=2.030385488 },
    { id='SP-262abd9ff3ab191adb4e78ae', name='歪比巴卜', file='SFX\\Waibibabu.ogg', duration=1.033310658 },
    { id='SP-92d90501e63e04e8d273858e', name='眼睛闭上咯', nameTW='眼睛閉上咯', file='SFX\\EyesClosed.ogg', duration=1.348208617 },
}

function Adapter:Register()
    if S.voicePacks['wyjjdb'] then return true end
    if not System.IsAddOnLoadedSafe('WYJJDB') then return false end
    local entries, specialEntries = {}, {}
    local soundPath = 'Interface\\AddOns\\WYJJDB\\Media\\Sound\\'
    for id, recording in pairs(S.WYJJDBRecordings or {}) do
        entries[id] = { file = soundPath .. recording.file,
            duration = recording.duration }
    end
    for index, recording in ipairs(SpecialRecordings) do
        specialEntries[recording.id] = { file=soundPath .. recording.file, duration=recording.duration,
            names={enUS=recording.name,zhCN=recording.name,zhTW=recording.nameTW or recording.name},listOrder=index }
    end
    local ok = S:RegisterVoicePack('wyjjdb', { protocolVersion = 1, language = 'zhCN',
        names = { enUS = '忘忧景久', zhCN = '忘忧景久', zhTW = '忘憂景久' }, entries = entries, specialEntries = specialEntries })
    if ok and YUI.Event then YUI.Event:OffOwner(self) end
    return ok
end

function Adapter:OnAddonLoaded(_, name)
    if name == 'WYJJDB' then self:Register() end
end

if not Adapter:Register() and YUI.Event then
    YUI.Event:On('ADDON_LOADED', 'OnAddonLoaded', Adapter, { moduleId = 'sound.pack-adapter' })
end
