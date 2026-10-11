local _, namespace = ...
local YUI = _G.YUI or namespace
local S = YUI and YUI.Sound
local System = YUI and YUI.API and YUI.API.System
if not (S and System and System.IsAddOnLoadedSafe) or S.PackAdapter then return end
local Adapter = {}
S.PackAdapter = Adapter

function Adapter:Register()
    if S.voicePacks['wyjjdb'] then return true end
    if not System.IsAddOnLoadedSafe('WYJJDB') then return false end
    local entries = {}
    for id, recording in pairs(S.WYJJDBRecordings or {}) do
        entries[id] = { file = 'Interface\\AddOns\\WYJJDB\\Media\\Sound\\' .. recording.file,
            duration = recording.duration }
    end
    local ok = S:RegisterVoicePack('wyjjdb', { protocolVersion = 1, language = 'zhCN',
        names = { enUS = 'WYJJDB', zhCN = 'WYJJDB', zhTW = 'WYJJDB' }, entries = entries })
    if ok and YUI.Event then YUI.Event:OffOwner(self) end
    return ok
end

function Adapter:OnAddonLoaded(_, name)
    if name == 'WYJJDB' then self:Register() end
end

if not Adapter:Register() and YUI.Event then
    YUI.Event:On('ADDON_LOADED', 'OnAddonLoaded', Adapter, { moduleId = 'sound.pack-adapter' })
end
