local YHUD = _G.YUI and _G.YUI.YHUD
if not YHUD then return end
local PowerType = Enum and Enum.PowerType or {}
local function Power(name, fallback)
    local value = PowerType[name]
    return type(value) == "number" and value or fallback
end
YHUD.ResourceDefinitions = {
    mana = {
        id = "mana",
        powerType = Power("Mana", 0),
        powerToken = "MANA",
        nameKey = "resource.mana",
        valueKind = "continuous",
        defaultValueText = true,
        color = { 0.20, 0.55, 1.00, 1 },
    },
    rage = {
        id = "rage",
        powerType = Power("Rage", 1),
        powerToken = "RAGE",
        nameKey = "resource.rage",
        valueKind = "continuous",
        defaultValueText = true,
        defaultValueFormat = "value",
        color = { 0.90, 0.20, 0.20, 1 },
    },
    energy = {
        id = "energy",
        powerType = Power("Energy", 3),
        powerToken = "ENERGY",
        nameKey = "resource.energy",
        valueKind = "continuous",
        defaultValueText = true,
        defaultValueFormat = "value",
        color = { 1.00, 0.85, 0.20, 1 },
    },
    comboPoints = {
        id = "comboPoints",
        powerType = Power("ComboPoints", 4),
        powerToken = "COMBO_POINTS",
        nameKey = "resource.combo_points",
        valueKind = "discrete",
        previewMax = 5,
        segmentCountFallback = 5,
        defaultValueText = false,
        color = { 1.00, 0.85, 0.20, 1 },
        provider = {
            kind = "unit-power",
            chargedPowerPoints = false,
            chargedColor = { 0.44, 0.77, 1.00, 1 },
        },
    },
}
YHUD.ResourceDefinitions.mana.defaultValueText = false
YHUD.ResourceDefinitions.mana.defaultValueFormat = "percent"
YHUD.ResourceDefinitionIds = { "mana", "rage", "energy", "comboPoints" }
YHUD.ResourceCommonCandidateIds = { "swingMainHand", "swingOffHand", "swingRanged" }
for _, hand in ipairs({
    { "swingMainHand", "mainhand", "resource.swing_main_hand" },
    { "swingOffHand", "offhand", "resource.swing_off_hand" },
    { "swingRanged", "ranged", "resource.swing_ranged" },
}) do
    YHUD.ResourceDefinitions[hand[1]] = {
        id = hand[1], nameKey = hand[3], valueKind = "continuous",
        provider = { kind = "swing-timer", swingHand = hand[2] },
        defaultEnabled = false, defaultValueText = true,
        defaultValueFormat = "duration", previewMax = 3,
        defaultSettings = { heightOverride = 7, visibilityMode = "nonzero" },
        color = hand[2] == "ranged"
            and { 239 / 255, 136 / 255, 43 / 255, 1 }
            or { 236 / 255, 223 / 255, 112 / 255, 1 },
    }
    YHUD.ResourceDefinitionIds[#YHUD.ResourceDefinitionIds + 1] = hand[1]
end
