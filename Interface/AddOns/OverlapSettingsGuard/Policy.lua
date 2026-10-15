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
