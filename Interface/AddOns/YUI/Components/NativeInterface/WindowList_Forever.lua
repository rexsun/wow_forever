local _, YUI = ...
local Native = YUI and YUI.NativeInterface
if not (Native and YUI.IsForever) then return end

-- Title strips exclude the portrait and close button. Only verified native roots belong here.
Native.MovableWindows = {
    { id = "CharacterFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "PlayerSpellsFrame", addon = "Blizzard_PlayerSpells" },
    { id = "LegacySystemFrame", addon = "Blizzard_LegacySystem" },
    { id = "MerchantFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "AuctionHouseFrame", addon = "Blizzard_AuctionHouseUI" },
    { id = "BankFrame", addon = "Blizzard_UIPanels_Game", bank = true },
    { id = "TaxiFrame", addon = "Blizzard_UIPanels_Game", titleLeft = 20 },
    { id = "SettingsPanel", addon = "Blizzard_Settings_Shared", titleLeft = 20 },
    { id = "AddonList", addon = "Blizzard_AddOnList" },
    { id = "MailFrame", addon = "Blizzard_MailFrame" },
    { id = "TradeFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "QuestFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "GossipFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "MacroFrame", addon = "Blizzard_MacroUI" },
    { id = "ProfessionsFrame", addon = "Blizzard_Professions" },
    { id = "CollectionsJournal", addon = "Blizzard_Collections" },
    { id = "FriendsFrame", addon = "Blizzard_FriendsFrame" },
    { id = "DressUpFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "InspectFrame", addon = "Blizzard_InspectUI" },
    { id = "ClassTrainerFrame", addon = "Blizzard_TrainerUI" },
    { id = "ItemTextFrame", addon = "Blizzard_UIPanels_Game" },
    { id = "ItemSocketingFrame", addon = "Blizzard_ItemSocketingUI" },
    { id = "PetStableFrame", addon = "Blizzard_StableUI" },
    { id = "CommunitiesFrame", addon = "Blizzard_Communities", titleRight = 65 },
    { id = "LFGParentFrame", addon = "Blizzard_GroupFinder_VanillaStyle" },
    { id = "AchievementFrame", addon = "Blizzard_AchievementUI", titleKey = "Header" },
    { id = "ContainerFrameCombinedBags", addon = "Blizzard_UIPanels_Game", bag = true },
}

-- Separate bags use the same native layout as the combined backpack.
for index = 1, 6 do
    Native.MovableWindows[#Native.MovableWindows + 1] = {
        id = "ContainerFrame" .. index, addon = "Blizzard_UIPanels_Game",
        titleLeft = 40, titleRight = 35, bag = true,
    }
end
