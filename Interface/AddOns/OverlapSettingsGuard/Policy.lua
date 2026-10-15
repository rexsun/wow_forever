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
    id = "rxp.yui.autoquests", adapter = "RestedXP", key = "QuestAutomation",
    label = "RestedXP: Quest auto accept/turn in", when = { "RXPGuides", "YUI" },
    reason = "YUI owns quest acceptance and turn-ins, including quests outside the active guide.",
  },
  {
    id = "rxp.yui.autogossip", adapter = "RestedXP", key = "GossipAutomation",
    label = "RestedXP: Gossip automation", when = { "RXPGuides", "YUI" },
    reason = "YUI owns quest gossip; RestedXP retains guide navigation.",
  },
  {
    id = "rxp.yui.questrewards", adapter = "RestedXP", key = "QuestRewardAutomation",
    label = "RestedXP: Quest auto rewards", when = { "RXPGuides", "YUI" },
    reason = "YUI owns turn-ins; RestedXP must not independently select guide rewards.",
  },
  {
    id = "rxp.yui.questchoices", adapter = "RestedXP", key = "QuestChoiceAutomation",
    label = "RestedXP: Calculated reward automation", when = { "RXPGuides", "YUI" },
    reason = "YUI owns turn-ins; calculated RestedXP reward choices must not compete.",
  },
  {
    id = "rxp.yui.selljunk", adapter = "RestedXP", key = "AutoSellJunk",
    label = "RestedXP: Auto Sell Junk", when = { "RXPGuides", "YUI" },
    reason = "YUI owns junk selling; RestedXP's guide-related merchant assistance remains available.",
  },
  {
    id = "rxp.talentguides",
    adapter = "RestedXP",
    key = "TalentGuides",
    label = "RestedXP: Enable Talents Guides",
    when = { "RXPGuides", "TalentsForeverBook" },
    reason = "Talents Forever plans talents for Forever's talent window.",
    needsReload = true,
  },
}
