local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI or (YUI.IsRetail ~= true and YUI.IsForever ~= true) then return end

-- Recipient aura identities for Retail 12.1.5. Display spells are kept separate
-- from their recipient effects; this catalog never requires a learned spell.
local Buffs = { entries = {}, byID = {}, soundEntries = {} }
YUI.HelpfulBuffs = Buffs
local definitions = {
    {10060}, {29166},
    {33206}, {47788}, {102342}, {116849}, {357170}, {1022},
    {6940}, {204018}, {147833}, {53480}, {387804},
    {81782}, {145629}, {209426}, {97463}, {374227},
    {31821, 412629}, {325174},
    {1044}, {116841}, {106898}, {192082, 192082, 192077}, {406789}, {375234}, {1244157},
    {395152}, {410089}, {360827}, {34477}, {57934},
}
for index, definition in ipairs(definitions) do
    local entry = { id = definition[1], displaySpellID = definition[3] or definition[1],
        spellIDs = { definition[2] or definition[1] } }
    Buffs.entries[index], Buffs.soundEntries[index], Buffs.byID[entry.id] = entry, entry, entry
end
if YUI.IsForever then
    Buffs.entries, Buffs.byID, Buffs.soundEntries = {}, {}, {}
    for index, definition in ipairs(YUI.API.ForeverAuraIdentities and YUI.API.ForeverAuraIdentities.received or {}) do
        local entry = {id=definition.id,displaySpellID=definition.id,spellIDs=definition.spellIDs}
        Buffs.entries[index],Buffs.soundEntries[index],Buffs.byID[entry.id]=entry,entry,entry
    end
end
local heroism = { id = 32182, nameKey = 'sound.center.heroismBuff',
    spellIDs = {2825, 32182, 80353, 90355, 264667, 390386} }
if YUI.IsRetail then
    Buffs.byID[heroism.id] = heroism
    Buffs.soundEntries[#Buffs.soundEntries + 1] = heroism
end

-- The engine owns aura detection and playback. This source only holds the
-- registration's lifetime, with no aura polling or combat-state inspection.
function Buffs:DescribeSound(id, event)
    local entry = self.byID[id]
    if not entry or (event ~= 'auraAdded' and event ~= 'auraRemoved') then return end
    local monitor = YUI.Monitor
    if not monitor then return nil, 'source-unavailable' end
    if not self.soundRegistered then
        local ok, code = monitor:RegisterSourceType('received-aura-sound', {
            createState = function() return {} end,
            read = function() return false end,
        })
        if not ok and code ~= 'source-type-exists' then return nil, code end
        self.soundRegistered = true
    end
    return { key = 'received-aura-sound:' .. id, type = 'received-aura-sound',
        params = { spellID = id, unit = 'player' },
        nativeAuraUnit = 'player', nativeAuraID = entry.spellIDs[1],
        nativeAuraIDs = entry.spellIDs }
end
