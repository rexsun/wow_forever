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
    id = "yui.resources", adapter = "YUI", key = "Resources",
    label = "YUI: Mana, rage, energy and combo-point HUD bars", when = { "YUI", "EllesmereUIUnitFrames" },
    reason = "EllesmereUI unit frames own player power and class resources; YUI swing timers remain available.",
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
    id = "eui.nameplatepower", adapter = "EllesmereUI", key = "NameplatePower",
    label = "EllesmereUI: Nameplate class power", when = { "EllesmereUINameplates", "EllesmereUIUnitFrames" },
    reason = "EllesmereUI unit frames own class resources; do not duplicate them on the target nameplate.",
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
    reason = "EllesmereUI owns player power and combo points; the combined GearInsight HUD stays off.",
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
}

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
