local _, OSG = ...

OSG.policy = {
  {
    id = "yui.nameplateoutline", adapter = "YUI", key = "NameplateOutline",
    label = "YUI: Nameplate font outline", when = { "YUI", "EllesmereUINameplates" },
    reason = "EllesmereUI owns nameplate fonts and styling.",
  },
  {
    id = "yui.friendlynameplates", adapter = "YUI", key = "FriendlyNameplates",
    label = "YUI: Linked friendly nameplates", when = { "YUI", "EllesmereUINameplates" },
    reason = "EllesmereUI owns friendly nameplate visibility; YUI must not synchronize its CVars.",
  },
  {
    id = "eui.classpower", adapter = "EllesmereUI", key = "ClassPower",
    label = "EllesmereUI: Player frame combo points", when = { "EllesmereUIUnitFrames", "YUI" },
    reason = "YUI's HUD owns combo points in the middle of the screen; do not duplicate them on the player or target frame.",
  },
  {
    id = "yui.playerhealth", adapter = "YUI", key = "PlayerHealth",
    label = "YUI: Player health HUD bar", when = { "YUI", "EllesmereUIUnitFrames" },
    reason = "EllesmereUI unit frames own player health; do not duplicate it in YHUD.",
  },
  {
    id = "yui.playercast", adapter = "YUI", key = "PlayerCast",
    label = "YUI: Player cast HUD bars", when = { "YUI", "EllesmereUIUnitFrames" },
    reason = "EllesmereUI owns the player castbar; YHUD cast selections, cast-only groups and native castbar suppression stay off.",
  },
  {
    id = "yui.chatkeywordfilter", adapter = "YUI", key = "ChatKeywordFilter",
    label = "YUI: Chat keyword filter", when = { "YUI", "GearInsight_Forever" },
    reason = "GearInsight owns level-up announcement filtering (/gi lvlmute); YChat must not also hide player messages by keyword.",
  },
  {
    id = "eui.nameplatepower", adapter = "EllesmereUI", key = "NameplatePower",
    label = "EllesmereUI: Nameplate class power", when = { "EllesmereUINameplates", "EllesmereUIUnitFrames" },
    reason = "Combo points already show on the YUI HUD or the EllesmereUI player frame; do not duplicate them on the target nameplate.",
  },
  {
    id = "eui.itemleveltip", adapter = "EllesmereUI", key = "ItemLevelTooltip",
    label = "EllesmereUI: Item level on item tooltips", when = { "EllesmereUI", "YUI" },
    reason = "YUI's item tooltips already show the item level.",
  },
  {
    id = "gi.friendlynameplates", adapter = "GearInsight", key = "FriendlyNameplates",
    label = "GearInsight: Automatic friendly nameplates", when = { "GearInsight_Forever", "EllesmereUINameplates" },
    reason = "EllesmereUI owns friendly nameplate visibility; GearInsight must not change its CVars.",
  },
  {
    id = "gi.combathud", adapter = "GearInsight", key = "CombatHUD",
    label = "GearInsight: Cooldown, DoT and proc HUD", when = { "GearInsight_Forever", "YUI" },
    reason = "YUI owns cooldown and combat HUD tracking; GearInsight rotation advice remains available.",
  },
  {
    id = "gi.resources", adapter = "GearInsight", key = "CombatHUD",
    label = "GearInsight: Power and combo-point HUD", when = { "GearInsight_Forever", "EllesmereUIUnitFrames" },
    reason = "EllesmereUI's player frame and YUI's HUD already show player power and combo points; the combined GearInsight HUD stays off.",
  },
  {
    id = "gi.levelingstats", adapter = "GearInsight", key = "LevelingStats",
    label = "GearInsight: Floating leveling statistics", when = { "GearInsight_Forever", "YUI" },
    reason = "YUI owns the experience display; GearInsight's main leveling plan remains available.",
  },
  {
    id = "gi.actionbaredits", adapter = "GearInsight", key = "ActionBarEditing",
    label = "GearInsight: Action-bar and keybinding edits", when = { "GearInsight_Forever", "YUI" },
    reason = "YUI owns action bars and bindings; GearInsight's key display is read-only and macro import remains available.",
  },
  {
    id = "gi.guildchatlevel", adapter = "GearInsight", key = "GuildChatLevel",
    label = "GearInsight: Guild, officer, whisper and party chat level prefixes", when = { "GearInsight_Forever", "YUI" },
    reason = "YUI owns chat; GearInsight must not rewrite guild, officer, whisper or party messages.",
  },
  {
    id = "gi.cityplates", adapter = "GearInsight", key = "CityPlates",
    label = "GearInsight: Friendly nameplates hidden in capitals", when = { "GearInsight_Forever", "EllesmereUINameplates" },
    reason = "EllesmereUI owns friendly nameplate visibility; GearInsight must not change its CVars.",
    early = true,
  },
  {
    id = "gi.itemlevel", adapter = "GearInsight", key = "ItemLevel",
    label = "GearInsight: Item level on the character panel, bags and tooltips", when = { "GearInsight_Forever", "YUI" },
    reason = "YUI's equipment info owns item level display.",
  },
  {
    id = "yui.flightmarkers", adapter = "YUI", key = "FlightMarkers",
    label = "YUI: World map flight-point markers", when = { "YUI", "MapUtils" },
    reason = "MapUtils owns flight-point pins and greys out undiscovered ones; YUI's other map markers stay on.",
  },
  {
    id = "yui.mapreveal", adapter = "YUI", key = "MapReveal",
    label = "YUI: World map unexplored area reveal", when = { "YUI", "MapUtils" },
    reason = "MapUtils owns unexplored areas: its One Map view hides the layer YUI's reveal draws on.",
  },
  {
    id = "yui.auctionhelper", adapter = "YUI", key = "AuctionHelper",
    label = "YUI: Auction house shopping panel", when = { "YUI", "Auctionator" },
    reason = "Auctionator owns auction shopping lists and searches; YUI must not dock a second shopping panel.",
  },
}

-- No other addon offers these, so they follow the guard's chat and group owner, YUI. Early,
-- because GearInsight sends its first layer heartbeat on the first frame after loading.
local gearInsightGroup = {
  { id = "layernetwork", key = "LayerNetwork", label = "Layer network heartbeats, public per-map channel and hop helper",
    reason = "GearInsight must not broadcast your level, class, map, layer and quests to guild and hidden public channels." },
  { id = "layerautoaccept", key = "LayerAutoAccept", label = "Auto-accept guild officers' party invites",
    reason = "Party invites stay with the normal accept dialog." },
  { id = "layerautoinvite", key = "LayerAutoInvite", label = "Auto-invite guildmates who ask for your layer",
    reason = "Invites stay manual; YUI keeps its own optional keyword auto-invite." },
  { id = "layerautoleave", key = "LayerAutoLeave", label = "Auto-leave the party after a layer change",
    reason = "Leaving a party stays manual." },
  { id = "groupautoload", key = "GroupAutoLoad", label = "Group module auto-load at login and in any group, with the thank-you popup",
    reason = "The Group module loads only when its tab, slash command or minimap entry is used." },
  { id = "questshare", key = "QuestShare", label = "Quest-progress sharing to guild and nearby players",
    reason = "GearInsight must not send your level, class, map position and quest progress every 30 seconds." },
  { id = "magewater", key = "MageWater", label = "Mage water helpers: thank-you whisper after trades and nearby-Mage popup",
    reason = "YUI owns chat; GearInsight must not whisper on its own, and its Mage module loads only when used." },
  { id = "lowrank", key = "LowRank", label = "Low-rank spell checker: whispers and party/raid call-outs to groupmates",
    reason = "YUI owns chat and spell ranks; GearInsight must not whisper or name groupmates in group chat on its own." },
  { id = "buffask", key = "BuffAsk", label = "Buff requests: dungeon ask or auto-post, soulstone reminder and nearby-player popup",
    reason = "YUI owns chat; GearInsight must not post buff requests to group chat on its own." },
  { id = "pallyfloat", key = "PallyFloat", label = "Floating one-click Paladin blessing button",
    reason = "YUI owns action bars and bindings and has its own raid blessing bar; GearInsight's Blessings page stays available." },
  { id = "tradereceipt", key = "TradeReceipt", label = "Trade receipt whisper after every trade",
    reason = "YUI owns chat; GearInsight must not whisper your trade partner on its own." },
  { id = "mounttrinket", key = "MountTrinket", label = "Carrot on a Stick swap on mount and its screen icon",
    reason = "Equipment changes stay manual; GearInsight must not swap trinkets when you mount or dismount." },
  { id = "auraremind", key = "AuraRemind", label = "Paladin no-aura reminder bar",
    reason = "YUI owns action bars and class tool bars; GearInsight must not add a cast bar of its own." },
  { id = "ammoremind", key = "AmmoRemind", label = "Hunter ammo reminder: icon, city alerts and vendor button",
    reason = "YUI's HUD shows the equipped ammo count; GearInsight's Ammo page stays available." },
  { id = "xpprep", key = "XpPrep", label = "Departure checklist that opens in cities and inns",
    reason = "YUI owns the experience display; GearInsight's checklist page stays available." },
  { id = "selljunk", key = "SellJunk", label = "Sell-junk panel at every merchant and automatic grey selling",
    reason = "YUI owns junk selling at merchants." },
}

-- Early, because each is read when its window, tooltip or button first appears after login.
local gearInsightOwned = {
  { id = "dungeonnav", key = "DungeonNav", owner = "MapUtils", label = "Dungeon guide that opens in every dungeon",
    reason = "MapUtils owns dungeon maps with boss pins; /gi 导航 still opens GearInsight's guide." },
  { id = "auctionpricetip", key = "AuctionPriceTip", owner = "Auctionator", label = "Auction-versus-vendor line in item tooltips",
    reason = "Auctionator owns auction prices in tooltips." },
  { id = "profshopping", key = "ProfShopping", owner = "Auctionator", label = "Profession shopping list and button at merchants and the auction house",
    reason = "Auctionator owns auction shopping lists and searches; GearInsight's profession pages stay available." },
  { id = "bagbuttons", key = "BagButtons", owner = "Bagnon", label = "Clean-up and sell-junk buttons on bag windows",
    reason = "Bagnon owns the bag windows and YUI owns junk selling; GearInsight's Bag page stays available." },
}

for _, setting in ipairs(gearInsightOwned) do
  OSG.policy[#OSG.policy + 1] = {
    id = "gi." .. setting.id, adapter = "GearInsight", key = setting.key,
    label = "GearInsight: " .. setting.label, reason = setting.reason,
    when = { "GearInsight_Forever", setting.owner }, early = true,
  }
end

for _, setting in ipairs(gearInsightGroup) do
  OSG.policy[#OSG.policy + 1] = {
    id = "gi." .. setting.id, adapter = "GearInsight", key = setting.key,
    label = "GearInsight: " .. setting.label, reason = setting.reason,
    when = { "GearInsight_Forever", "YUI" }, early = true,
  }
end

local foreverEssentials = {
  { id = "spelluprank", key = "SpellUprank", owner = "YUI", label = "Spell uprank", reason = "YUI owns action bars and upgrades spell ranks on them." },
  { id = "mapreveal", key = "MapReveal", owner = "YUI", label = "World map reveal", reason = "YUI or MapUtils already reveals unexplored areas." },
  { id = "mapfade", key = "MapFade", owner = "YUI", label = "World map fade", reason = "YUI owns world map fading while moving." },
  { id = "junkitems", key = "JunkItems", owner = "YUI", label = "Junk items window", reason = "YUI owns junk selling at merchants." },
  { id = "classicspellbook", key = "ClassicSpellbook", owner = "YUI", label = "Classic spellbook", reason = "YUI owns the spellbook and talent window handling." },
  { id = "classictalents", key = "ClassicTalents", owner = "YUI", label = "Classic talents", reason = "YUI owns the spellbook and talent window handling; GearInsight plans talents." },
  { id = "maptravel", key = "MapTravel", owner = "YUI", label = "World map travel markers", reason = "YUI's map markers already show portals, transports and points of interest." },
  { id = "threatmeter", key = "ThreatMeter", owner = "Details_TinyThreat", label = "Threat meter", reason = "Details owns threat display through Details_TinyThreat." },
  { id = "zonelevels", key = "ZoneLevels", owner = "MapUtils", label = "World map zone levels and fishing skill", reason = "MapUtils owns zone level and fishing skill labels on the world map." },
  { id = "gatherskill", key = "GatherSkill", owner = "GatherLite", label = "Gathering skill in tooltips", reason = "GatherLite always adds the skill a herb or ore node needs to its tooltip." },
  { id = "skinningskill", key = "GatherSkinning", owner = "GearInsight_Forever", label = "Skinning skill on corpse tooltips", reason = "GearInsight adds the skill a skinnable creature needs to its tooltip by default." },
  { id = "ingamenav", key = "InGameNavigation", owner = "WaypointUI", label = "Show Waypoints in the World", reason = "Waypoint UI owns the in-world waypoint, distance and edge arrow on the game's navigation frame." },
}

for _, setting in ipairs(foreverEssentials) do
  OSG.policy[#OSG.policy + 1] = {
    id = "euife." .. setting.id, adapter = "ForeverEssentials", key = setting.key,
    label = "EllesmereUI Forever Essentials: " .. setting.label, reason = setting.reason,
    when = { "EllesmereUIForeverEssentials", setting.owner },
  }
end

local mapUtilsSettings = {
  { id = "worldmapmove", key = "WorldMapMove", label = "World map moving", reason = "YUI owns the world map position." },
  { id = "worldmapscale", key = "WorldMapScale", label = "World map scaling", reason = "YUI owns the world map scale." },
  { id = "worldmapfade", key = "WorldMapFade", label = "World map fade while moving", reason = "YUI owns world map fading while moving." },
  { id = "pierpins", key = "PierPins", label = "World map pier, zeppelin and tram pins", reason = "YUI's map markers already show docks, zeppelin towers and the tram." },
  -- 1.7.15: no other addon shows friends, but either switch greets every online friend with hidden
  -- addon whispers at login, and sharing then sends them your map position; YUI owns chat.
  { id = "friendshare", key = "FriendShare", label = "Share my position with friends", reason = "YUI owns chat; MapUtils must not send your map position to friends by hidden whispers." },
  { id = "friendpins", key = "FriendPins", label = "Friends on the map", reason = "YUI owns chat; showing friends greets every online friend with hidden addon whispers at each login." },
  -- 1.9.x: a groupmate's open dungeon map asks for positions, which starts this client's flight-point
  -- scan (moving Waypoint UI's marker) and hidden position messages to the group, with no click.
  { id = "instancegrouppos", key = "InstanceGroupPos", label = "Group positions on dungeon maps", reason = "YUI owns chat and group; MapUtils must not send your dungeon position to the group by hidden addon messages whenever a groupmate opens a dungeon map." },
  -- Not guarded since 0.27.0: 1.8.4's player position on dungeon maps (INSTANCEPLAYERPOS) is a chosen
  -- feature; its flight-point super-tracking moves Waypoint UI's marker only while that map is open.
}

-- Early, because MapUtils applies its map window and fade settings at PLAYER_LOGIN.
for _, setting in ipairs(mapUtilsSettings) do
  OSG.policy[#OSG.policy + 1] = {
    id = "mu." .. setting.id, adapter = "MapUtils", key = setting.key,
    label = "MapUtils: " .. setting.label, reason = setting.reason,
    when = { "MapUtils", "YUI" }, early = true, needsReload = true,
  }
end

local skinnerSettings = {
  { key = "unitframes", namespace = "UnitFrames", fields = { "player", "target", "focus", "pet", "petlvl", "arena" }, owner = "EllesmereUIUnitFrames", label = "Individual unit frames", reason = "EllesmereUI owns individual unit frames." },
  { key = "partyframes", namespace = "UnitFrames", fields = { "party" }, owner = "EllesmereUIRaidFrames", label = "Party unit frames", reason = "EllesmereUI owns party frames." },
  { key = "castingbar", root = "CastingBar", fields = { "skin", "glaze" }, owner = "EllesmereUIUnitFrames", label = "Castbar skin and texture", reason = "EllesmereUI owns the player castbar." },
  { key = "compactframes", root = "CompactFrames", fields = { "skin", "sbars" }, owner = "EllesmereUIRaidFrames", label = "Compact party/raid skins and bars", reason = "EllesmereUI owns party and raid frames." },
  { key = "nameplates", fields = { "Nameplates" }, owner = "EllesmereUINameplates", label = "Nameplate skin", reason = "EllesmereUI owns nameplates." },
  { key = "actionbars", root = "MainMenuBar", fields = { "skin", "glazesb", "altpowerbar", "actbtns", "extraab" }, owner = "YUI", label = "Action and status bar skins", reason = "YUI owns action bars and their supporting displays." },
  { key = "minimap", fields = { "Minimap.skin", "Minimap.gloss", "MinimapButtons.skin", "MinimapButtons.style" }, owner = "YUI", label = "Minimap and button skins", reason = "YUI owns the minimap and its buttons." },
  { key = "worldmap", root = "WorldMap", fields = { "skin" }, owner = "YUI", label = "World map skin", reason = "YUI owns the world map appearance and layout." },
  { key = "chat", fields = { "ChatBubbles.skin", "ChatButtons", "ChatConfig", "ChatEditBox.skin", "ChatFrames", "ChatTabs", "ChatTabsFade", "CombatLogQBF" }, owner = "YUI", label = "Chat window, input, tab and bubble skins", reason = "YUI owns chat appearance and behavior." },
  { key = "tooltips", root = "Tooltips", fields = { "skin", "glazesb" }, owner = "YUI", label = "Tooltip skin and health-bar texture", reason = "YUI retains tooltip appearance and behavior." },
  { key = "details", root = "DisabledSkins", fields = { "Details" }, value = true, owner = "Details", label = "Details skin", reason = "Details retains its own meter appearance." },
  { key = "detailsframework", root = "DisabledSkins", fields = { "DetailsFramework-1.0 (Lib)" }, value = true, owner = "Details", label = "Details framework skin", reason = "Details retains its own framework widget appearance." },
}

for _, setting in ipairs(skinnerSettings) do
  OSG.policy[#OSG.policy + 1] = {
    id = "skinner." .. setting.key, adapter = "Skinner", key = setting.key,
    label = "Skinner: " .. setting.label, reason = setting.reason,
    when = { "Skinner", setting.owner }, early = true, needsReload = true,
    namespace = setting.namespace, root = setting.root, fields = setting.fields,
    value = setting.value == true,
  }
end
