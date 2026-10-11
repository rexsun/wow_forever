local _, YUI = ...
YUI = YUI or _G.YUI
if not YUI or not YUI.IsForever then return end
YUI.API = YUI.API or {}
YUI.API.Talent = YUI.API.Talent or {}
-- Forever 1.60.1.70205: TraitNodeGroupDisplayInfo joined to SkillLine.
-- These IDs identify talent trees for configuration; they are not native spec IDs.
YUI.API.Talent.ConfigurationCatalog = {
    SHAMAN = { classID = 7, nativeSpecID = 1489, treeID = 1082, trees = {
        { specID = 11326, icon = 136048, nameKey = "talent.configuration.shaman.1", name = "Elemental" },
        { specID = 11363, icon = 136051, nameKey = "talent.configuration.shaman.2", name = "Enhancement" },
        { specID = 11362, icon = 136052, nameKey = "talent.configuration.shaman.3", name = "Restoration" },
    } },
    DRUID = { classID = 11, nativeSpecID = 1484, treeID = 1089, trees = {
        { specID = 11328, icon = 136096, nameKey = "talent.configuration.druid.1", name = "Balance" },
        { specID = 11347, icon = 132276, nameKey = "talent.configuration.druid.2", name = "Feral Combat" },
        { specID = 11340, icon = 136041, nameKey = "talent.configuration.druid.3", name = "Restoration" },
    } },
    HUNTER = { classID = 3, nativeSpecID = 1485, treeID = 1091, trees = {
        { specID = 11372, icon = 132164, nameKey = "talent.configuration.hunter.1", name = "Beast Mastery" },
        { specID = 11371, icon = 132222, nameKey = "talent.configuration.hunter.2", name = "Marksmanship" },
        { specID = 11370, icon = 132215, nameKey = "talent.configuration.hunter.3", name = "Survival" },
    } },
    PALADIN = { classID = 2, nativeSpecID = 1486, treeID = 1100, trees = {
        { specID = 11486, icon = 135920, nameKey = "talent.configuration.paladin.1", name = "Holy" },
        { specID = 11541, icon = 135893, nameKey = "talent.configuration.paladin.2", name = "Protection" },
        { specID = 11559, icon = 135873, nameKey = "talent.configuration.paladin.3", name = "Retribution" },
    } },
    ROGUE = { classID = 4, nativeSpecID = 1488, treeID = 1111, trees = {
        { specID = 11580, icon = 132292, nameKey = "talent.configuration.rogue.1", name = "Assassination" },
        { specID = 11573, icon = 132090, nameKey = "talent.configuration.rogue.2", name = "Combat" },
        { specID = 11572, icon = 132320, nameKey = "talent.configuration.rogue.3", name = "Subtlety" },
    } },
    MAGE = { classID = 8, nativeSpecID = 1482, treeID = 1112, trees = {
        { specID = 11582, icon = 135932, nameKey = "talent.configuration.mage.1", name = "Arcane" },
        { specID = 11594, icon = 135810, nameKey = "talent.configuration.mage.2", name = "Fire" },
        { specID = 11601, icon = 135846, nameKey = "talent.configuration.mage.3", name = "Frost" },
    } },
    PRIEST = { classID = 5, nativeSpecID = 1487, treeID = 1114, trees = {
        { specID = 11608, icon = 135987, nameKey = "talent.configuration.priest.1", name = "Discipline" },
        { specID = 11615, icon = 135920, nameKey = "talent.configuration.priest.2", name = "Holy" },
        { specID = 11622, icon = 136207, nameKey = "talent.configuration.priest.3", name = "Shadow" },
    } },
    WARLOCK = { classID = 9, nativeSpecID = 1490, treeID = 1116, trees = {
        { specID = 11629, icon = 136145, nameKey = "talent.configuration.warlock.1", name = "Affliction" },
        { specID = 11636, icon = 136172, nameKey = "talent.configuration.warlock.2", name = "Demonology" },
        { specID = 11637, icon = 136186, nameKey = "talent.configuration.warlock.3", name = "Destruction" },
    } },
    WARRIOR = { classID = 1, nativeSpecID = 1491, treeID = 1117, trees = {
        { specID = 11650, icon = 132292, nameKey = "talent.configuration.warrior.1", name = "Arms" },
        { specID = 11657, icon = 132347, nameKey = "talent.configuration.warrior.2", name = "Fury" },
        { specID = 11670, icon = 132341, nameKey = "talent.configuration.warrior.3", name = "Protection" },
    } },
}
