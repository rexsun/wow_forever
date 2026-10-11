local YUI = _G.YUI
if not YUI or not YUI.IsRetail or YUI.YUnitFrames then return end

-- Verified against 12.1.0.69875; this descriptor is loaded only by the Mainline entry.
YUI.YUnitFrames = { Client = {
    id = "mainline", verifiedBuild = "12.1.0.69875", bossCount = 5,
    nativeFrames = {
        player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame", pet = "PetFrame",
        targettarget = "TargetFrameToT", focustarget = "FocusFrameToT", boss = "BossTargetFrameContainer", castbar = "PlayerCastingBarFrame",
    },
    visibilityPrefix = "[petbattle] hide; ",
    auraAddon = "Blizzard_AuraContainer", auraTemplate = "CustomAuraContainerTemplate",
    extraUnitEvents = {
        UNIT_SPELLCAST_EMPOWER_START = "cast", UNIT_SPELLCAST_EMPOWER_UPDATE = "cast", UNIT_SPELLCAST_EMPOWER_STOP = "cast",
    },
} }
