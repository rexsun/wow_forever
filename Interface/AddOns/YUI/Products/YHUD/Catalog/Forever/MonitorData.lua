local YHUD = _G.YUI and _G.YUI.YHUD
if not YHUD then return end
-- Verified spell identities in Forever 1.60.1.70205; spellbook checks still apply.
YHUD.BLOODLUST_PRESET = nil
YHUD.BLOOD_BOIL_WINDOW_PRESET = nil
YHUD.MonitorPresets = {
    quickItems = {
        {
            itemID = 5512,
            itemIDs = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008,
                19007, 19006, 19005, 19004, 5509, 5511, 5512 },
            fallbackKey = "designer.quick.healthstone",
        },
        { itemID = 13446, fallbackKey = "designer.quick.classic_health" },
        { itemID = 13444, fallbackKey = "designer.quick.classic_mana" },
    },
    timedBuffs = {
        -- The 1.60.1.70450 native seal bundle omits this rank 1 aura.
        {
            presetId = "forever-seals",
            classToken = "PALADIN",
            entryKey = "aura:player:helpful:20154",
            sourceKey = "aura:player:helpful:20154",
            sourceIdentity = "aura:player:helpful:20154",
            sourceType = "yhud.player-aura",
            displaySpellID = 20154,
            spellIDs = { 20154 },
            excludeNativeAura = true,
            presetLabelKey = "designer.preset.label.forever_seals",
            tooltipNoteKey = "designer.preset.forever_seals_tooltip",
        },
    },
    timedItems = {},
    defensives = {},
    interrupts = {
        WARRIOR = { class = { 6552 } },
        PALADIN = { class = { 853 } },
        ROGUE = { class = { 1766, 408, 2094 } },
        PRIEST = { class = { 8122 } },
        MAGE = { class = { 2139 } },
    },
}

YHUD.CLASS_EXTRA_PRESETS = nil
