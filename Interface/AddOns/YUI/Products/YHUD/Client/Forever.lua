local YUI = _G.YUI
if not YUI or YUI.IsForever ~= true then return end
YUI.YHUD = YUI.YHUD or {}
YUI.YHUD.Client = {
    id = "forever",
    soundReminders = true,
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

-- Keep the original entry identity so saved placements and overrides survive.
YUI.YHUD.FOREVER_SEAL_PRESET = {
    entryKey = "aura:player:helpful:20154",
    nativeCooldownID = 200340,
    nameKey = "designer.preset.label.forever_seals",
    -- Native seal summary icon, verified in Forever 1.60.1.70862.
    icon = 1030100,
    spellIDs = {
        20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,
        21082, 20162, 20305, 20306, 20307, 20308,
        20164,
        20375, 20915, 20918, 20919, 20920,
        20165, 20347, 20348, 20349,
        20166, 20356, 20357,
        1311649, 1311656, 20163, 20419, 20421, 20422, 20423,
    },
}
