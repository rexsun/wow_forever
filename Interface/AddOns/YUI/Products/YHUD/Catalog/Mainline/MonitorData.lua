local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end
local BLOOD_DEATH_KNIGHT_SPEC_KEY = "DEATHKNIGHT:250"
local SPELL_EVENT_WINDOW_SOURCE_TYPE = YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE or "yhud.spell-event-window"
local QUICK_ITEM_PRESETS = {
    {
        itemID = 5512,
        itemIDs = { 224464, 5512 },
        legacyItemIDs = { [224464] = true },
        preferredItemID = 224464,
        fallbackKey = "designer.quick.healthstone",
        fallback = "治疗石",
        fixedName = "治疗石",
        officialCooldownIDs = { 198699 },
        officialSpellCategoryIDs = { 1711, 2566 },
        legacyOfficialSpellIDs = { 198946 },
    },
    {
        itemID = 241304,
        itemIDs = { 241304, 241305 },
        legacyItemIDs = { [241305] = true },
        fallbackKey = "designer.quick.silvermoon_health",
        fallback = "银月城生命药水",
        officialCooldownIDs = { 198701 },
        officialSpellCategoryIDs = { 30 },
    },
    {
        itemID = 241300,
        itemIDs = { 241300, 241301 },
        legacyItemIDs = { [241301] = true },
        fallbackKey = "designer.quick.lightfused_mana",
        fallback = "光注法力药水",
        officialCooldownIDs = { 198701 },
        officialSpellCategoryIDs = { 30 },
    },
    {
        itemID = 271884,
        itemIDs = { 271884, 271883 },
        legacyItemIDs = { [271883] = true },
        fallbackKey = "designer.quick.condensed_silvermoon_health",
        fallback = "凝缩银月城生命药水",
        officialCooldownIDs = { 198701 },
        officialSpellCategoryIDs = { 30 },
    },
    {
        itemID = 241308,
        itemIDs = { 241308, 241309, 245898, 245897 },
        legacyItemIDs = {
            [241308] = true,
            [241309] = true,
            [245898] = true,
            [245897] = true,
        },
        fallbackKey = "designer.preset.lights_potential",
        fallback = "圣光潜力",
        officialCooldownIDs = { 198700 },
        officialSpellCategoryIDs = { 4 },
        legacyOfficialSpellIDs = { 198700 },
    },
    {
        itemID = 241288,
        itemIDs = { 241288, 241289, 245902, 245903 },
        legacyItemIDs = {
            [241288] = true,
            [241289] = true,
            [245902] = true,
            [245903] = true,
        },
        fallbackKey = "designer.preset.potion_recklessness",
        fallback = "鲁莽药水",
        officialCooldownIDs = { 198700 },
        officialSpellCategoryIDs = { 4 },
        legacyOfficialSpellIDs = { 198700 },
    },
    {
        itemID = 271887,
        itemIDs = { 271887, 271886, 274764, 274763 },
        legacyItemIDs = { [271887] = true, [271886] = true,
            [274764] = true, [274763] = true },
        fallbackKey = "designer.preset.liquid_luster",
        fallback = "液态光泽",
    },
    {
        itemID = 241302,
        itemIDs = { 241302, 241303 },
        legacyItemIDs = { [241303] = true },
        fallbackKey = "designer.preset.invis_potion",
        fallback = "隐形药水",
        officialCooldownIDs = { 198700 },
        officialSpellCategoryIDs = { 4 },
        legacyOfficialSpellIDs = { 198700 },
    },
}

local BLOODLUST_PRESET = YHUD.BLOODLUST_PRESET or {
    entryKey = "buff-aura:bloodlust",
    sourceKey = "aura:preset:bloodlust",
    sourceType = "yhud.player-aura",
    sourceIdentity = "bloodlust-heroism",
    displaySpellID = 2825,
    spellIDs = { 2825, 32182, 80353, 90355, 264667, 390386 },
}

local BLOOD_BOIL_WINDOW_PRESET = YHUD.BLOOD_BOIL_WINDOW_PRESET or {
    presetId = "blood-boil-window",
    specKey = BLOOD_DEATH_KNIGHT_SPEC_KEY,
    entryKey = "spell-event-window:1265982",
    sourceKey = "spell-event-window:1265982",
    sourceType = SPELL_EVENT_WINDOW_SOURCE_TYPE,
    displaySpellID = 50842,
    triggerSpellIDs = { 1265982 },
    durationSeconds = 3,
    nameKey = "designer.preset.blood_boil_window",
    fallbackName = "沸点",
    presetLabelKey = nil,
    fallbackPresetLabel = nil,
}

local TIMED_BUFF_SPELL_PRESETS = {
    BLOOD_BOIL_WINDOW_PRESET,
    {
        presetId = "bloodlust",
        entryKey = BLOODLUST_PRESET.entryKey,
        sourceKey = BLOODLUST_PRESET.sourceKey,
        sourceType = BLOODLUST_PRESET.sourceType,
        sourceIdentity = BLOODLUST_PRESET.sourceIdentity,
        displaySpellID = BLOODLUST_PRESET.displaySpellID,
        spellIDs = BLOODLUST_PRESET.spellIDs,
        nameKey = "designer.preset.bloodlust",
        fallbackName = "嗜血/英勇",
    },
    {
        presetId = "power-infusion",
        entryKey = "buff-aura:power-infusion",
        sourceKey = "aura:preset:power-infusion",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 10060,
        spellIDs = { 10060 },
    },
    {
        presetId = "innervate",
        entryKey = "buff-aura:innervate",
        sourceKey = "aura:preset:innervate",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 29166,
        spellIDs = { 29166 },
    },
    {
        presetId = "dawnlight-self",
        specKey = "PALADIN:70",
        entryKey = "buff-aura:dawnlight-self",
        sourceKey = "aura:preset:dawnlight-self",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        sourceIdentity = "dawnlight-self",
        displaySpellID = 431522,
        spellIDs = { 431522 },
        presetLabelKey = "designer.preset.label.self",
        tooltipNoteKey = "designer.preset.dawnlight_self_tooltip",
    },
    {
        presetId = "season-passive-one",
        entryKey = "buff-aura:season-passive-one",
        sourceKey = "aura:preset:season-passive-one",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1263318,
        spellIDs = { 1263318 },
    },
    {
        presetId = "season-passive-two",
        entryKey = "buff-aura:season-passive-two",
        sourceKey = "aura:preset:season-passive-two",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1266687,
        spellIDs = { 1266687 },
    },
}

local TIER_SET_AURA_PRESETS = {
    {
        presetId = "tier-set-aura-1310372",
        specKey = "DEATHKNIGHT:250",
        entryKey = "buff-aura:tier-set:1310372",
        sourceKey = "aura:preset:tier-set:1310372",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1310372,
        spellIDs = { 1310372 },
    },
    {
        presetId = "tier-set-aura-1300369",
        specKey = "DEATHKNIGHT:250",
        entryKey = "buff-aura:tier-set:1300369",
        sourceKey = "aura:preset:tier-set:1300369",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1300369,
        spellIDs = { 1300369 },
    },
    {
        presetId = "tier-set-aura-1297365",
        specKey = "DEATHKNIGHT:251",
        entryKey = "buff-aura:tier-set:1297365",
        sourceKey = "aura:preset:tier-set:1297365",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1297365,
        spellIDs = { 1297365 },
    },
    {
        presetId = "tier-set-aura-1301768",
        specKey = "DRUID:102",
        entryKey = "buff-aura:tier-set:1301768",
        sourceKey = "aura:preset:tier-set:1301768",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1301768,
        spellIDs = { 1301768 },
    },
    {
        presetId = "tier-set-aura-1301600",
        specKey = "DRUID:103",
        entryKey = "buff-aura:tier-set:1301600",
        sourceKey = "aura:preset:tier-set:1301600",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1301600,
        spellIDs = { 1301600 },
    },
    {
        presetId = "tier-set-aura-1297728",
        specKey = "EVOKER:1473",
        entryKey = "buff-aura:tier-set:1297728",
        sourceKey = "aura:preset:tier-set:1297728",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1297728,
        spellIDs = { 1297728 },
    },
    {
        presetId = "tier-set-aura-1299389",
        specKey = "HUNTER:253",
        entryKey = "buff-aura:tier-set:1299389",
        sourceKey = "aura:preset:tier-set:1299389",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1299389,
        spellIDs = { 1299389 },
    },
    {
        presetId = "tier-set-aura-1296930",
        specKey = "MAGE:62",
        entryKey = "buff-aura:tier-set:1296930",
        sourceKey = "aura:preset:tier-set:1296930",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1296930,
        spellIDs = { 1296930 },
    },
    {
        presetId = "tier-set-aura-1310248",
        specKey = "MAGE:64",
        entryKey = "buff-aura:tier-set:1310248",
        sourceKey = "aura:preset:tier-set:1310248",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1310248,
        spellIDs = { 1310248 },
    },
    {
        presetId = "tier-set-aura-1300219",
        specKey = "SHAMAN:262",
        entryKey = "buff-aura:tier-set:1300219",
        sourceKey = "aura:preset:tier-set:1300219",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1300219,
        spellIDs = { 1300219 },
    },
    {
        presetId = "tier-set-aura-1300222",
        specKey = "SHAMAN:262",
        entryKey = "buff-aura:tier-set:1300222",
        sourceKey = "aura:preset:tier-set:1300222",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1300222,
        spellIDs = { 1300222 },
    },
    {
        presetId = "tier-set-aura-1299991",
        specKey = "SHAMAN:263",
        entryKey = "buff-aura:tier-set:1299991",
        sourceKey = "aura:preset:tier-set:1299991",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1299991,
        spellIDs = { 1299991 },
    },
    {
        presetId = "tier-set-aura-1300670",
        specKey = "WARRIOR:71",
        entryKey = "buff-aura:tier-set:1300670",
        sourceKey = "aura:preset:tier-set:1300670",
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
        displaySpellID = 1300670,
        spellIDs = { 1300670 },
    },
}

for index = 1, #TIER_SET_AURA_PRESETS do
    local preset = TIER_SET_AURA_PRESETS[index]
    preset.section = "tier-set"
    preset.presetLabelKey = "designer.preset.label.tier_set"
    preset.verificationStatus = "candidate"
    preset.contentScope = YHUD.CONTENT_SCOPE_SPEC
end

local QUICK_TIMED_BUFF_PRESETS = {
    {
        presetId = "burst-potion",
        entryKey = "buff-timer:burst-potion",
        sourceKey = "buff-timer:burst-potion",
        sourceIdentity = "buff-timer:burst-potion",
        itemID = 241308,
        itemIDs = { 241309, 241308, 245897, 245898, 241289, 241288, 245902, 245903, 271886, 271887, 274763, 274764, 241293, 241292, 245910, 245911, 241297, 241296, 245900, 245901, 271889, 271890, 274765 },
        displaySpellID = 1236616,
        triggerSpellIDs = { 1236616, 1236994, 1295132, 1236998, 1238443, 1295015 },
        durationSeconds = 30,
        nameKey = "designer.preset.burst_potion_buff",
        fallbackName = "爆发药水增益",
        icon = 7548911,
        presetLabelKey = "designer.preset.label.burst_potion",
        tooltipItemIDs = { 241308, 241288, 271887, 241292, 241296, 271890 },
        -- This new group does not adopt existing single-potion timers.
    },
    {
        presetId = "invis-potion",
        entryKey = "buff-timer:invis-potion",
        sourceKey = "buff-timer:invis-potion",
        sourceIdentity = "buff-timer:invis-potion",
        itemID = 241302,
        itemIDs = { 241302, 241303 },
        displaySpellID = 1236551,
        triggerSpellIDs = { 371125, 431424, 371133, 371134, 1236551 },
        durationSeconds = 18,
        nameKey = "designer.preset.invis_potion",
        fallbackName = "隐形药水",
        legacyItemIDs = {
            [241302] = true,
            [241303] = true,
        },
        legacySpellIDs = {
            [371125] = true,
            [431424] = true,
            [371133] = true,
            [371134] = true,
            [1236551] = true,
        },
    },
}

local DEFENSIVE_SPELLS = {
    WARRIOR = {
        class = { 23920, 97462 },
        [71] = { 118038 },
        [72] = { 184364 },
        [73] = { 871 },
    },
    PALADIN = {
        class = { 642 },
        [65] = { 498 },
        [66] = { 31850, 86659 },
        [70] = { 498 },
    },
    HUNTER = { class = { 109304, 186265, 264735 } },
    ROGUE = { class = { 1966, 5277, 31224, 185311 } },
    PRIEST = {
        class = { 586, 19236 },
        [258] = { 47585 },
    },
    DEATHKNIGHT = {
        class = { 48707, 48792, 49039, 51052 },
        [250] = { 55233 },
    },
    SHAMAN = { class = { 108271 } },
    MAGE = {
        class = {
            { spellID = 45438, aliases = { 414658 } },
            342245,
        },
        [62] = { 235450 },
        [63] = { 235313 },
        [64] = { 11426 },
    },
    WARLOCK = { class = { 104773, 108416 } },
    MONK = { class = { 115203 } },
    DRUID = {
        class = { 22812 },
        [103] = { 61336 },
        [104] = { 61336 },
        [105] = { 102342 },
    },
    DEMONHUNTER = {
        class = { 196718 },
        [577] = { 198589 },
        [581] = { 204021 },
        [1480] = { 198589 },
    },
    EVOKER = { class = { 363916 } },
}

local INTERRUPT_CONTROL_SPELLS = {
    WARRIOR = {
        class = { 6552, 107570, 46968, 5246 },
        [73] = { 386071 },
    },
    PALADIN = {
        class = { 96231, 853, 115750, 20066 },
    },
    HUNTER = {
        class = { 19577, 109248, 213691, 187650 },
        [253] = { 147362 },
        [254] = { 147362 },
        [255] = { 187707 },
    },
    ROGUE = { class = { 1766, 408, 2094 } },
    PRIEST = {
        class = { 8122 },
        [256] = { 64044 },
        [257] = { 88625 },
        [258] = { 15487, 64044 },
    },
    DEATHKNIGHT = {
        class = { 47528, 221562, 207167, 49576 },
        [250] = { 108199 },
    },
    SHAMAN = { class = { 57994, 192058, 51514, 51490 } },
    MAGE = { class = { 2139, 31661, 113724, 157980 } },
    WARLOCK = { class = { 89766, 30283, 5484 } },
    MONK = { class = { 116705, 119381, 115078, 116844 } },
    DRUID = {
        class = { 132469 },
        [102] = { 78675 },
        [103] = { 106839 },
        [104] = { 106839 },
    },
    DEMONHUNTER = { class = { 183752, 202137, 179057, 217832, 211881 } },
    EVOKER = { class = { 351338, 358385 } },
}

YHUD.BLOODLUST_PRESET = BLOODLUST_PRESET
YHUD.BLOOD_BOIL_WINDOW_PRESET = BLOOD_BOIL_WINDOW_PRESET
YHUD.MonitorPresets = {
    quickItems = QUICK_ITEM_PRESETS,
    timedBuffs = TIMED_BUFF_SPELL_PRESETS,
    tierSetAuras = TIER_SET_AURA_PRESETS,
    timedItems = QUICK_TIMED_BUFF_PRESETS,
    defensives = DEFENSIVE_SPELLS,
    interrupts = INTERRUPT_CONTROL_SPELLS,
}
