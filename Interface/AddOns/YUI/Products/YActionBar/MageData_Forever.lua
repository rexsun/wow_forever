local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end

-- wowf zhCN 1.60.1.70862: ItemSparse.RequiredSkill=3012; decoded items are
-- Mage-only consumable scrolls in Item/ItemSparse, excluding the skill manual.
YAB.MageData = {
    build = "1.60.1.70862", skillLineID = 3012, comprehendSpellID = 1296017,
    comprehendIcon = 8188276, powderItemID = 17020, powderIcon = 133848,
    untranslated = {
        [211780] = 1, [211784] = 15, [211785] = 1, [211786] = 1, [211787] = 1,
        [211853] = 15, [211854] = 15, [211855] = 15,
        [213543] = 50, [213544] = 50, [213545] = 50, [213546] = 50, [213547] = 50,
        [281015] = 175, [281016] = 175, [281017] = 175, [281018] = 175,
    },
    decoded = {
        [211800] = 12, [211953] = 20, [211954] = 20, [211955] = 20, [211956] = 20,
        [211957] = 20, [213548] = 0, [213549] = 12, [213550] = 16, [213551] = 12,
        [213564] = 0, [216879] = 1, [217495] = 16, [217496] = 0, [223171] = 1,
        [274947] = 5, [275067] = 5, [275069] = 5, [277483] = 16, [277484] = 16,
        [277485] = 16, [277486] = 16, [277487] = 16, [277488] = 16, [277489] = 16,
        [277490] = 0, [277491] = 25, [277492] = 25, [277493] = 25, [277494] = 25,
        [277495] = 25, [277496] = 25, [277497] = 25, [277498] = 25,
        [277499] = 46, [277500] = 46, [277501] = 46, [277502] = 46,
        [277503] = 46, [277504] = 0,
    },
    armorSpells = { mage = 6117, ice = 7302, frost = 168 },
    intellectSpellID = 1459, brillianceSpellID = 23028,
}
