local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
if not S then return end

-- Fixed notification identities. Availability never changes saved rule identity.
local D = { rows = {}, byID = {}, groups = {'daily','group','combat','explore'} }
S.EventDefinitions = D
local rows = {
    {'quest-complete','daily','VC-324225ee',134939},
    {'mail-received','daily','VC-c2c4ed1b'},
    {'whisper-received','daily','VC-b0712566',133015},
    {'ready-check','group','VC-a07966ee',132333}, {'role-check','group','VC-486c41c4',132333}, {'group-invite','group','VC-4ac726a4',132484},
    {'player-dead','combat','VC-c1e01357',132293}, {'teammate-dead','combat','VC-ce0ccf26',442272},
    {'queue-ready','group','VC-fb686ac3',132161}, {'summon-request','group','VC-63aa2e90',134430},
    {'tank-dead','combat','VC-25cc4feb',134950}, {'healer-dead','combat','VC-77f21d8f',135769},
    {'bags-full','daily','VC-220e25a5',133645}, {'repair-needed','daily','VC-812f045b',132281}, {'rare-found','explore','VC-a8545a7d',135977},
}
for index, row in ipairs(rows) do
    local entry = {id=row[1], group=row[2], voice=row[3], order=index, icon=row[4] or 133471}
    D.rows[index], D.byID[entry.id] = entry, entry
end
function D:Text(id, suffix)
    local L = YUI.Locale and YUI.Locale:Get('Core')
    local key = 'sound.event.'..id..(suffix and '.'..suffix or '')
    return L and L[key] or key
end
function D:Normalize(id, raw)
    if not self.byID[id] or raw ~= nil and type(raw) ~= 'table' then return nil,'invalid-event' end
    raw = raw or {}
    local defaults = {}
    if id=='whisper-received' then defaults={character=true,battleNet=true}
    elseif id=='repair-needed' then defaults={threshold=20}
    elseif id=='rare-found' then defaults={cooldown=600}
    elseif id=='teammate-dead' or id=='tank-dead' or id=='healer-dead' then defaults={scope='all'} end
    for key in pairs(raw) do if defaults[key]==nil then return nil,'invalid-event-parameter' end end
    for key,value in pairs(defaults) do if raw[key]~=nil then defaults[key]=raw[key] end end
    if defaults.scope and defaults.scope~='all' and defaults.scope~='party' and defaults.scope~='raid' then return nil,'invalid-event-parameter' end
    if id=='whisper-received' and (type(defaults.character)~='boolean' or type(defaults.battleNet)~='boolean'
        or not defaults.character and not defaults.battleNet) then return nil,'invalid-event-parameter' end
    if id=='repair-needed' and (type(defaults.threshold)~='number' or defaults.threshold~=defaults.threshold
        or defaults.threshold%1~=0 or defaults.threshold<1 or defaults.threshold>100) then return nil,'invalid-event-parameter' end
    if id=='rare-found' and defaults.cooldown~=0 and defaults.cooldown~=600 and defaults.cooldown~=1800 then return nil,'invalid-event-parameter' end
    return defaults
end
function D:Availability(id)
    if not YUI.IsRetail and not YUI.IsForever then return false,'unsupported-client' end
    local api=YUI.API and YUI.API.SoundEvents
    if not api or not api.Available(id) then return false,'event-unavailable' end
    return true,(id=='rare-found' or YUI.IsForever and (id=='role-check' or id=='queue-ready')) and 'limited' or nil
end
