local YUI = _G.YUI
if not YUI or not YUI.IsForever or YUI.YUnitFrames then return end

-- Source/API baseline: 1.60.1.70009; in-game acceptance is tracked separately.
YUI.YUnitFrames = { Client = {
    id = "forever", verifiedBuild = "1.60.1.70009", bossCount = 5, defaultEnabled = true,
    nativeFrames = {
        player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame", pet = "PetFrame",
        targettarget = "TargetFrameToT", focustarget = "FocusFrameToT", boss = "BossTargetFrameContainer", castbar = "PlayerCastingBarFrame",
    },
    -- Keep native combo-point visibility independent of target-frame suppression.
    preserveNativeChildren = { target = { "ComboFrame" } },
    channelTicks = { [5143] = 3, [5144] = 4, [5145] = 5, [8416] = 5, [8417] = 5,
        [10211] = 5, [10212] = 5, [12051] = 4, [10] = 8, [6141] = 8,
        [8427] = 8, [10185] = 8, [10186] = 8, [10187] = 8 },
    visibilityPrefix = "[petbattle] hide; ",
    auraAddon = "Blizzard_AuraContainer", auraTemplate = "CustomAuraContainerTemplate",
    extraUnitEvents = {
        UNIT_SPELLCAST_EMPOWER_START = "cast", UNIT_SPELLCAST_EMPOWER_UPDATE = "cast", UNIT_SPELLCAST_EMPOWER_STOP = "cast",
    },
} }
