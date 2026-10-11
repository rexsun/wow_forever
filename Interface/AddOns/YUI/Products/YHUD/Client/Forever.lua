local YUI = _G.YUI
if not YUI or YUI.IsForever ~= true then return end
YUI.YHUD = YUI.YHUD or {}
YUI.YHUD.Client = {
    id = "forever",
    soundReminders = false,
    skyriding = false,
    nativeBuffBarSeconds = true,
    retiredPresetKeys = {
        ["bundle:defensive"] = true,
        ["buff-aura:bloodlust"] = true,
        ["bloodlust"] = true,
        ["bloodlust-heroism"] = true,
    },
    -- Stable TraitNodeGroup IDs, ordered by the client's three talent trees.
    fallbackSpecKeys = {
        "SHAMAN:11326", "SHAMAN:11363", "SHAMAN:11362",
        "DRUID:11328", "DRUID:11347", "DRUID:11340",
        "HUNTER:11372", "HUNTER:11371", "HUNTER:11370",
        "PALADIN:11486", "PALADIN:11541", "PALADIN:11559",
        "ROGUE:11580", "ROGUE:11573", "ROGUE:11572",
        "MAGE:11582", "MAGE:11594", "MAGE:11601",
        "PRIEST:11608", "PRIEST:11615", "PRIEST:11622",
        "WARLOCK:11629", "WARLOCK:11636", "WARLOCK:11637",
        "WARRIOR:11650", "WARRIOR:11657", "WARRIOR:11670",
    },
    legacySpecKeyMap = {
        ["SHAMAN:1489"] = { "SHAMAN:11326", "SHAMAN:11363", "SHAMAN:11362" },
        ["DRUID:1484"] = { "DRUID:11328", "DRUID:11347", "DRUID:11340" },
        ["HUNTER:1485"] = { "HUNTER:11372", "HUNTER:11371", "HUNTER:11370" },
        ["PALADIN:1486"] = { "PALADIN:11486", "PALADIN:11541", "PALADIN:11559" },
        ["ROGUE:1488"] = { "ROGUE:11580", "ROGUE:11573", "ROGUE:11572" },
        ["MAGE:1482"] = { "MAGE:11582", "MAGE:11594", "MAGE:11601" },
        ["PRIEST:1487"] = { "PRIEST:11608", "PRIEST:11615", "PRIEST:11622" },
        ["WARLOCK:1490"] = { "WARLOCK:11629", "WARLOCK:11636", "WARLOCK:11637" },
        ["WARRIOR:1491"] = { "WARRIOR:11650", "WARRIOR:11657", "WARRIOR:11670" },
    },
}
