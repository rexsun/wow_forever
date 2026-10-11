local YUI = _G.YUI
if not YUI or YUI.IsRetail == false then return end
YUI.YHUD = YUI.YHUD or {}
YUI.YHUD.Client = {
    id = "retail",
    soundReminders = true,
    skyriding = true,
    fallbackSpecKeys = {
    "MAGE:62", "MAGE:63", "MAGE:64",
    "WARRIOR:71", "WARRIOR:72", "WARRIOR:73",
    "DRUID:102", "DRUID:103", "DRUID:104", "DRUID:105",
    "PRIEST:256", "PRIEST:257", "PRIEST:258",
    "ROGUE:259", "ROGUE:260", "ROGUE:261",
    "HUNTER:253", "HUNTER:254", "HUNTER:255",
    "PALADIN:65", "PALADIN:66", "PALADIN:70",
    "WARLOCK:265", "WARLOCK:266", "WARLOCK:267",
    "DEATHKNIGHT:250", "DEATHKNIGHT:251", "DEATHKNIGHT:252",
    "DEMONHUNTER:577", "DEMONHUNTER:581", "DEMONHUNTER:1480",
    "EVOKER:1467", "EVOKER:1468", "EVOKER:1473",
    "MONK:268", "MONK:269", "MONK:270",
    "SHAMAN:262", "SHAMAN:263", "SHAMAN:264",
},
}
