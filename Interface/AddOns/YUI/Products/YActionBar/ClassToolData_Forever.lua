local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars) then return end

-- Candidate families from Forever 1.60.1.70938. Runtime still requires a learned spell.
local Data = { build = "1.60.1.70938", catalog = {}, products = {}, reagents = {}, items = {} }
YAB.ClassToolData = Data
local function Family(... ) return { ... } end
Data.manaGemSpells = Family(759,3552,10053,10054)
Data.catalog.mageTools = {
    water = { mode = "select", ranks = true, conjured = true, targetCraft = "water", consumeText = "drink", productText = "selected_water",
        families = { Family(5504,5505,5506,6127,10138,10139,10140,468766) } },
    bread = { mode = "select", ranks = true, conjured = true, targetCraft = "food", consumeText = "eat", productText = "selected_food",
        families = { Family(587,597,990,6129,10144,10145,28612) } },
    teleport = { mode = "cast", travel = true, families = { {3561},{3562},{3565},{3567},{3563},{3566},{1297659} } },
    portal = { mode = "cast", travel = true, families = { {10059},{11416},{11419},{11417},{11418},{11420} } },
}
Data.catalog.totems = {
    imbue = { mode = "cast", hoverMenu = 6, weaponSlot = 16, families = {
        Family(8017,8018,8019,10399,16314,16315,16316), Family(8024,8027,8030,16339,16341,16342),
        Family(8033,8038,10456,16355,16356), Family(8232,8235,10486,16362) } },
    shield = { mode = "cast", hoverMenu = 7, shield = true, families = { Family(324,325,905,945,8134,10431,10432), {408510}, {408514,408519} } },
}
Data.catalog.warlockTools = {
    demon = { mode = "cast", pet = true, counter = 6265, families = { {688},{697},{712},{691} } },
    healthstone = { stone = true, families = { Family(6201,6202,5699,11729,11730) },
        items = {5512,19004,19005,5511,19006,19007,5509,19008,19009,5510,19010,19011,9421,19012,19013} },
    soulstone = { stone = true, friend = true, binding = true, boundAuras = {20707,20762,20763,20764,20765}, families = { Family(693,20752,20755,20756,20757) },
        items = {5232,16892,16893,16895,16896} },
    firestone = { stone = true, weaponSlot = 16, families = { Family(6366,17951,17952,17953) },
        items = {1254,13699,13700,13701} },
    spellstone = { stone = true, weaponSlot = 16, families = { Family(2362,17727,17728) },
        items = {5522,13602,13603} },
    armor = { aura = true, target = "player", families = { Family(687,696,706,1086,11733,11734,11735) } },
    ritual = { counter = 6265, families = { {698} }, right = {437169} },
}
local poisons = {6947,6949,6950,8926,8927,8928,2892,2893,8984,8985,20844,3775,3776,5237,6951,9186,10918,10920,10921,10922}
-- Forever 1.60.1.71037: ItemSparse, ItemXItemEffect, SpellEffect and SpellEquippedItems.
local sharpening = {}
Data.poisonSkillLine, Data.poisonSkillSpell = 40, 2842
Data.catalog.rogueTools = {
    mainhand = { mode = "cast", poison = true, weaponSlot = 16, items = poisons },
    offhand = { mode = "cast", poison = true, weaponSlot = 17, items = poisons },
    mainhandStone = { mode = "cast", sharpening = true, weaponSlot = 16, items = sharpening, previewItem = 2862 },
    offhandStone = { mode = "cast", sharpening = true, weaponSlot = 17, items = sharpening, previewItem = 2862 },
}
Data.catalog.priestTools = {
    fortitude = { friend = true, aura = true, families = { Family(1243,1244,1245,2791,10937,10938) }, right = {21562,21564} },
    spirit = { friend = true, aura = true, families = { Family(14752,14818,14819,27841) }, right = {27681} },
    shadow = { friend = true, aura = true, families = { Family(976,10957,10958) }, right = {27683} },
    innerfire = { target = "player", aura = true, families = { Family(588,7128,602,1006,10951,10952) } },
}
Data.catalog.paladinTools = {
    blessing = { mode = "cast", selectOnRight = true, friend = true, aura = true, auraPriority = true, warnMissing = false, columns = true, families = { Family(19740,19834,19835,19836,19837,19838,25291),
        Family(19742,19850,19852,19853,19854,25290), {20217} },
        greater = { [19740] = {25782,25916}, [19742] = {25894,25918}, [20217] = {25898} } },
    teamBlessing = { team = true, counter = 21177, families = { {25782,25916},{25894,25918},{25898} } },
    righteous = { target = "player", aura = true, cancelAura = true, families = { {25780,407627} } },
    seal = { mode = "cast", target = "player", activeAura = true, families = {
        Family(20154,21084,20287,20288,20289,20290,20291,20292,20293),
        Family(20375,20915,20918,20919,20920), Family(21082,20162,20305,20306,20307,20308),
        Family(20165,20347,20348,20349), Family(20166,20356,20357), {20164},
        Family(20163,20419,20421,20422,20423,1311649,1311656), {407798,407799} } },
}
Data.catalog.druidTools = {
    mark = { friend = true, aura = true, families = { Family(1126,5232,6756,5234,8907,9884,9885) }, right = {21849,21850} },
    thorns = { friend = true, aura = true, warnMissing = false, families = { Family(467,782,1075,8914,9756,9910) } },
}
Data.catalog.warriorTools = {
    battle = { aura = true, families = { Family(6673,5242,6192,11549,11550,11551,25289) } },
}

-- Product use level, not the level at which the spell is learned.
local products = {
    {5504,5350,1},{5505,2288,5},{5506,2136,15},{6127,3772,25},{10138,8077,35},
    {10139,8078,45},{10140,8079,55},{468766,231778,55},
    {587,5349,1},{597,1113,5},{990,1114,15},{6129,1487,25},{10144,8075,35},{10145,8076,45},{28612,22895,55},
    {759,5514,23},{3552,5513,38},{10053,8007,48},{10054,8008,58},
}
for _, row in ipairs(products) do Data.products[row[1]] = { itemID = row[2], level = row[3] } end

-- Forever 1.60.1.70888/70938: SpellEffect, SpellLevels and ItemSparse.
-- All listed consumables stack to 20. The usual starting count and growth are both 2.
Data.conjureStackSize = 20
Data.conjureScaling = {
    [5504] = { level = 4, maxLevel = 13 },
    [5505] = { level = 10, maxLevel = 19 },
    [5506] = { level = 20, maxLevel = 29 },
    [6127] = { level = 30, maxLevel = 39 },
    [10138] = { level = 40, maxLevel = 49 },
    [10139] = { level = 50, maxLevel = 59 },
    [10140] = { level = 60, maxLevel = 65, baseCount = 10 },
    [468766] = { level = 60, maxLevel = 65, baseCount = 20 },
    [587] = { level = 6, maxLevel = 15 },
    [597] = { level = 12, maxLevel = 21 },
    [990] = { level = 22, maxLevel = 31 },
    [6129] = { level = 32, maxLevel = 41 },
    [10144] = { level = 42, maxLevel = 51 },
    [10145] = { level = 52, maxLevel = 61, perLevel = 2.25 },
    [28612] = { level = 60, maxLevel = 65, baseCount = 10 },
}

Data.cityKeys = { [3561] = "stormwind", [10059] = "stormwind", [3562] = "ironforge", [11416] = "ironforge",
    [3565] = "darnassus", [11419] = "darnassus", [3567] = "orgrimmar", [11417] = "orgrimmar",
    [3563] = "undercity", [11418] = "undercity", [3566] = "thunderbluff", [11420] = "thunderbluff",
    [1297659] = "dalaran" }
for spell, key in pairs(Data.cityKeys) do Data.reagents[spell] = { itemID = key and (spell < 10000 or spell == 1297659) and 17031 or 17032, count = 1 } end
for _, spell in ipairs({693,697,698,691,712,5699,6201,6202,11730,11729,20752,20755,20756,20757,
    6366,17951,17952,17953,2362,17727,17728}) do
    Data.reagents[spell] = { itemID = 6265, count = 1 }
end
Data.reagents[437169] = { itemID = 6265, count = 5 }
for _, row in ipairs({{21562,17028},{21564,17029},{27681,17029},{27683,17029},{21849,17021},{21850,17026},
    {25782,21177},{25916,21177},{25894,21177},{25918,21177},{25898,21177}}) do
    Data.reagents[row[1]] = { itemID = row[2], count = 1 }
end
local poisonLevels = {20,28,36,44,52,60,30,38,46,54,60,20,50,24,38,52,32,40,48,56}
local poisonEnchants = {323,324,325,623,624,625,7,8,626,627,2630,22,603,35,23,643,703,704,705,706}
-- Forever ItemXItemEffect / ItemEffect: use spell for each exact item rank.
local poisonUseSpells = {
    [6947]=8679, [6949]=8686, [6950]=8688, [8926]=11338, [8927]=11339, [8928]=11340,
    [2892]=2823, [2893]=2824, [8984]=11355, [8985]=11356, [20844]=25351,
    [3775]=3408, [3776]=11202, [5237]=5761, [6951]=8693, [9186]=11399,
    [10918]=13219, [10920]=13225, [10921]=13226, [10922]=13227,
}
Data.poisonByEnchant = {}
for index, item in ipairs(poisons) do
    Data.items[item] = { level = poisonLevels[index], enchantID = poisonEnchants[index], useSpellID = poisonUseSpells[item] }
    Data.poisonByEnchant[poisonEnchants[index]] = item
end
Data.warlockStoneByEnchant = {}
for _, row in ipairs({{1254,1803,758},{13699,1823,17945},{13700,1824,17947},{13701,1825,17949},
    {5522,8059,1237152},{13602,8060,1237156},{13603,8061,1237159}}) do
    Data.items[row[1]] = {level=0, useSpellID=row[3]}
    Data.warlockStoneByEnchant[row[2]] = row[1]
end
Data.sharpeningByEnchant = {}
Data.sharpeningAlternates = {}
for _, row in ipairs({{2862,1,40,2828,33219},{287978,1,40,2828,33219},{3239,1,19,3112,9264},
    {2863,5,13,2829,33219},{3240,5,20,3113,9264},{2871,15,14,2830,33219},{3241,15,21,3114,9264},
    {7964,25,483,9900,33219},{7965,25,484,9903,9264},{12404,35,1643,16138,33219},{12643,35,1703,16622,9264},
    {18262,50,2506,22756,42483},{287980,1,2506,22756,42483},{23122,50,2684,28891,1097203},{211845,0,7098,430392,42483}}) do
    local item, level, enchant, spell, mask = row[1], row[2], row[3], row[4], row[5]
    sharpening[#sharpening + 1] = item
    Data.items[item] = {level=level, useSpellID=spell, weaponMask=mask}
    local original = Data.sharpeningByEnchant[enchant]
    if original then Data.sharpeningAlternates[original] = item
    else Data.sharpeningByEnchant[enchant] = item end
end
Data.enchants = {}
for _, row in ipairs({{8017,29},{8018,6},{8019,1},{10399,503},{16314,1663},{16315,683},{16316,1664},
    {8024,5},{8027,4},{8030,3},{16339,523},{16341,1665},{16342,1666},{8033,2},{8038,12},
    {10456,524},{16355,1667},{16356,1668},{8232,283},{8235,284},{10486,525},{16362,1669}}) do Data.enchants[row[1]] = row[2] end
local stoneLevels = { [5512]=1,[19004]=1,[19005]=1,[5511]=12,[19006]=12,[19007]=12,
    [5509]=24,[19008]=24,[19009]=24,[5510]=36,[19010]=36,[19011]=36,[9421]=48,[19012]=48,[19013]=48 }
for item, level in pairs(stoneLevels) do Data.items[item] = { level = level } end
for _, item in ipairs({5232,16892,16893,16895,16896}) do Data.items[item] = { level = 0 } end

Data.preview = {
    mageTools = { scroll=1296017, intellect=1459, armor=6117, water=10140, bread=28612, teleport=3561, portal=10059 },
    aspects = { aspect1=13163,aspect2=13165,aspect3=5118,aspect4=13161,aspect5=13159,aspect6=20043,
        aspect7=415423,aspect8=469145,pet=883 },
    totems = { summon=66842,earth=8071,fire=3599,water=5394,air=8512,recall=36936,imbue=8232,shield=324 },
    warlockTools = { demon=688,healthstone=6201,soulstone=693,firestone=6366,spellstone=2362,armor=706,ritual=698 },
    rogueTools = { mainhand=8679,mainhandStone=2828,offhand=2823,offhandStone=2828 }, priestTools={fortitude=1243,spirit=14752,shadow=976,innerfire=588},
    paladinBlessings={manage=25898,MAGE=25894,HUNTER=25782,SHAMAN=25894,WARLOCK=25894,ROGUE=25782,PRIEST=25894,PALADIN=25898,DRUID=25898,WARRIOR=25782},
    paladinTools={blessing=19740,teamBlessing=25898,righteous=25780,seal=20154},druidTools={mark=1126,thorns=467},warriorTools={battle=6673},
}

for slot, key in ipairs(YAB.ClassTools.manaGemKeys) do
    Data.catalog.mageTools[key] = {manaGemSlot=slot, conjured=true, hideCount=true, consumeText="use",
        productText="selected_gem", families={Data.manaGemSpells}}
    Data.preview.mageTools[key] = Data.manaGemSpells[#Data.manaGemSpells - slot + 1]
end

function Data:SupportsSelection(id, key, value)
    local definition = self.catalog[id] and self.catalog[id][key]
    if not definition then return false end
    for _, item in ipairs(definition.items or {}) do if item == value then return true end end
    for _, family in ipairs(definition.families or {}) do
        for _, spell in ipairs(family) do if spell == value then return true end end
    end
    for _, family in pairs(definition.greater or {}) do
        for _, spell in ipairs(family) do if spell == value then return true end end
    end
    return false
end
