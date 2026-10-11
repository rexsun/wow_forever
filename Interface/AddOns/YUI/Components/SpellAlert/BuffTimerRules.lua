local _, addon = ...
local YUI = _G.YUI or addon
if not (YUI and YUI.Components) then return end
YUI.SpellAlert = YUI.SpellAlert or {}

-- Evidence IDs refer to Docs/Components/SpellAlert/evidence. No exclusion list.
local rules = {
    -- SA-20260930-MAGE-02
    [62] = { [1277420] = 263725, [1277421] = 263725, [1277422] = 263725 },
    [64] = { [126084] = 44544 },
    -- SA-20260930-PRIEST-01
    [258] = { [409129] = 391401 },
    [256] = { [128654] = 114255 }, [257] = { [128654] = 114255 },
    -- SA-20261004-HUNTER-01
    [254] = { [270436] = 260242 },
    -- SA-20261004-EVOKER-01: one public alert, one buff per specialization.
    [1467] = { [361519] = 359618 }, [1468] = { [361519] = 369299 },
    [1473] = { [361519] = 392268 },
    -- SA-20261004-SHAMAN-01: 1 / 2 / 3 / 4 / 5-9 / 10 stacks.
    [263] = { [170588] = 344179, [170587] = 344179, [170586] = 344179,
        [170585] = 344179, [187890] = 344179, [467442] = 344179 },
    -- SA-20261004-PALADIN-01
    [65] = { [458213] = 54149 }, [70] = { [1299636] = 406086 },
    -- SA-20261004-DEATHKNIGHT-01 / -02
    [251] = { [438833] = 51124 }, [252] = { [461135] = 81340 },
}
YUI.SpellAlert.BuffTimerRules = {
    Resolve = function(specID, alertID)
        local spec = rules[specID]
        return spec and spec[alertID] or alertID
    end,
}
