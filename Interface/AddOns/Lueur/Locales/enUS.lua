-- Lueur : textes en anglais
-- C'est la langue de repli : un texte absent d'une autre langue s'affiche en anglais, et un
-- client dont la langue n'a pas de fichier ici reçoit l'anglais.

local _, ns = ...

local L = {}
ns.LOCALES.enUS = L

L.LANGUAGE_NAME = "English"   -- le nom que cette langue se donne : c'est ainsi que le menu la propose
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "yes"
L.NO = "no"
L.SETTING = "%s: %s"          -- un réglage et sa valeur
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d yd"
L.CONFIRM = "Confirm?"       -- sur un bouton qui attend un second geste

-- Mots de commande propres à cette langue -> nom anglais de la commande. Les noms anglais
-- répondent partout ; les accents sont facultatifs.
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Ore"
L.CATEGORY_ORE_TIP = "Mineral veins and deposits."
L.CATEGORY_HERB = "Herbs"
L.CATEGORY_HERB_TIP = "Plants you can gather."
L.CATEGORY_QUEST = "Quests"
L.CATEGORY_QUEST_TIP = "Objects tied to one of your current quests."
L.CATEGORY_CHEST = "Chests"
L.CATEGORY_CHEST_TIP = "Chests, crates and other containers you can loot."
L.CATEGORY_BOBBER = "Fishing bobber"
L.CATEGORY_BOBBER_TIP = "The bobber of your fishing line."
L.CATEGORY_OTHER = "Other objects"
L.CATEGORY_OTHER_TIP = "Everyday objects: doors, mailboxes, levers…"

-- la catégorie d'un objet, dans une phrase du diagnostic
L.NAME_ORE = "ore"
L.NAME_HERB = "herb"
L.NAME_QUEST = "quest"
L.NAME_CHEST = "chest"
L.NAME_BOBBER = "bobber"
L.NAME_OTHER = "other"
L.NAME_NONE = "none"

-- l'objet que l'aperçu montre pour chaque catégorie
L.SAMPLE_ORE = "Copper Vein"
L.SAMPLE_HERB = "Peacebloom"
L.SAMPLE_QUEST = "Supply Crate"
L.SAMPLE_CHEST = "Battered Chest"
L.SAMPLE_BOBBER = "Fishing Bobber"
L.SAMPLE_OTHER = "Mailbox"

L.STATE_FAR = "out of reach"
L.STATE_READY = "within reach"
L.STATE_LOCKED = "unavailable"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "A halo of light and its wisps, with a ring, comets and fireflies."
L.EFFECT_SUBTLE = "Subtle"
L.EFFECT_SUBTLE_TIP = "A soft glow, with no ring or comets."
L.EFFECT_SIGIL = "Sigil"
L.EFFECT_SIGIL_TIP = "A circle of runes turns slowly around the object."
L.EFFECT_VORTEX = "Vortex"
L.EFFECT_VORTEX_TIP = "Arms of light coil around the object, like a portal opening."
L.EFFECT_FLAME = "Flame"
L.EFFECT_FLAME_TIP = "Tongues of fire rise from the object, in its color."
L.EFFECT_RIFT = "Rift"
L.EFFECT_RIFT_TIP = "A black hole ringed with light pulls sparks into a spiral."
L.EFFECT_STORM = "Storm"
L.EFFECT_STORM_TIP = "A storm cloud gathers above the object, and lightning falls from it."
L.EFFECT_GEYSER = "Geyser"
L.EFFECT_GEYSER_TIP = "A fountain of light bursts from the object and falls back around it."
L.EFFECT_SPIRIT = "Spirit"
L.EFFECT_SPIRIT_TIP = "Two wisps dance around the object, trailing a ribbon of light."
L.EFFECT_BEAM = "Beam"
L.EFFECT_BEAM_TIP = "A column of light rises from the object, sparks drifting up along it."
L.EFFECT_BEACON = "Beacon"
L.EFFECT_BEACON_TIP = "A crystal hovers above the object, tied to it by a thread of light."
L.EFFECT_ORBIT = "Orbit"
L.EFFECT_ORBIT_TIP = "Three wisps circle the object, each on its own orbit."
L.EFFECT_RIPPLE = "Ripple"
L.EFFECT_RIPPLE_TIP = "Ripples spread across the ground around the object."
L.EFFECT_SPARKLE = "Sparkles"
L.EFFECT_SPARKLE_TIP = "Glints twinkle around the object, with no circle at all."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silhouette"
L.HEADER_OBJECTS = "Highlighted objects"
L.HEADER_HIDE = "Hide the effect"
L.HEADER_DETECTION = "Detection"
L.HEADER_GENERAL = "General"
L.SETTINGS = "Settings"

L.SCOPE_ALL = "All"
L.SCOPE_ALL_TIP = "What you set goes to every category. A category that had its own value for that setting loses it."
L.SCOPE_ONE_TIP = "What you set goes to this category only, which keeps it whatever happens to the others."
L.EFFECT = "Effect"
L.EFFECT_TIP = "The shape of the light."
L.LOOK_OF_ALL = "Appearance of all objects"
L.LOOK_OF = "Appearance: %s"
L.OF_CATEGORY = "%s (%s)"     -- un réglage, et la catégorie pour laquelle il vient de changer
L.SHARED = "Same as all objects"
L.SHARED_TIP = "Takes away this category's own effect and appearance: it goes back to those of all objects."

L.SIZE = "Size"
L.SIZE_TIP = "How large the effect is."
L.INTENSITY = "Intensity"
L.INTENSITY_TIP = "How bright the effect is."
L.OFFSET = "Vertical offset"
L.OFFSET_TIP = "Moves the effect up or down from the object's nameplate. The preview shows where it lands."
L.FADE = "Fade with the nameplate"
L.FADE_TIP = "The effect fades along with the object's nameplate, for instance when the scenery hides it."

L.SILHOUETTE = "Pass behind my character"
L.SILHOUETTE_TIP = "The effect is cut out around your character, so it seems to pass behind you instead of covering you."
L.ZONE_SIZE = "Cut-out size"
L.ZONE_SIZE_TIP = "Raise it if the effect bites into your character, lower it if the effect stays too far away. Each character keeps its own."
L.ZONE_HEIGHT = "Cut-out height"
L.ZONE_HEIGHT_TIP = "Moves the cut-out up or down. Each character keeps its own."
L.ZONE_SHOW = "Show the cut-out"
L.ZONE_SHOW_TIP = "Outlines the cut-out in red: it should hug your character. It goes away when this window closes."

L.SHOW_NAME = "Show the name"
L.SHOW_NAME_TIP = "Writes the object's name above it, in place of the one the game writes."
L.SHOW_ICON = "Show the icon"
L.SHOW_ICON_TIP = "Shows the object's interaction icon above it, in place of the one the game draws."
L.TEXT_SIZE = "Text size"
L.TEXT_SIZE_TIP = "Size of the name written above the object, compared with the game's own text."
L.FONT = "Font"
L.FONT_TIP = "Font of the name written above the object."
L.FONT_GAME = "Game font"
L.COLOR = "Color"
L.COLOR_TIP = "The color of the effect on these objects."
L.TIP_COLOR_SET = "Left-click: choose a color"
L.TIP_COLOR_RESET = "Right-click: back to the original color"
L.IGNORED = "Ignored objects: %d"
L.IGNORED_TIP = "Objects that never get an effect, whatever their category. /lueur ignore list names them, /lueur ignore clear forgets them all."
L.IGNORE_TARGET = "Ignore target"
L.IGNORE_TARGET_TIP = "Ignores the object you are facing right now, or stops ignoring it."

L.HIDE_COMBAT = "In combat"
L.HIDE_COMBAT_TIP = "No effect while you are in combat."
L.HIDE_INSTANCE = "In instances"
L.HIDE_INSTANCE_TIP = "No effect in dungeons, raids and battlegrounds."
L.HIDE_LOCKED = "On objects I cannot use"
L.HIDE_LOCKED_TIP = "The effect goes out on an object the game refuses for now: skill too low, object locked… The game only says so once you are within reach."
L.HIDE_UNTRAINED = "Herbs and ore without the profession"
L.HIDE_UNTRAINED_TIP = "No effect on herbs if this character does not have Herbalism, nor on ore without Mining."

L.RANGE = "Range"
L.RANGE_TIP = "How far away the game may pick an object to highlight."
L.DIRECTION = "Direction"
L.DIRECTION_TIP = "Where the game looks for an object to pick."
L.ARC_0 = "Dead ahead"
L.ARC_0_TIP = "Only what stands right in front of you."
L.ARC_1 = "In front"
L.ARC_1_TIP = "Anything in front of you."
L.ARC_2 = "Everywhere"
L.ARC_2_TIP = "In every direction, even behind your back."
L.EXCLUSIVE = "Only show highlighted targets"
L.EXCLUSIVE_TIP = "The game no longer points out interaction targets that get no effect: NPCs, mailboxes… Unchecked, it shows a name and an icon on every one of them."
L.GLOW_ONLY = "Glow only"
L.GLOW_ONLY_TIP = "Lueur no longer writes the object's name and icon, and leaves what the game or another addon shows there. Always on while Plumber's Soft Target nameplate is enabled."

L.KEY = "Interact key"
L.KEY_TIP = "The key that picks up, gathers or uses the highlighted object once it is within reach. It is the game's own interact key: it works on NPCs too, and can also be changed in the game's key bindings."
L.KEY_NONE = "Not bound"
L.KEY_LISTEN = "Press a key"
L.KEY_LISTEN_TIP = "Press the key, mouse button or mouse wheel direction to use. Escape cancels."
L.KEY_TAKEN = "%s is already used for “%s”. Press it again to give it to the interact key instead, or press another key."
L.TIP_KEY_SET = "Left-click: choose a key"
L.TIP_KEY_CLEAR = "Right-click: remove the key"

L.LANGUAGE = "Language"
L.LANGUAGE_TIP = "The language of Lueur's texts and commands."
L.LANGUAGE_AUTO = "Automatic"
L.LANGUAGE_AUTO_TIP = "Follows the language of the game."

L.ENABLE = "Enable Lueur"
L.ENABLE_TIP = "When disabled, Lueur hands your original targeting settings back to the game."
L.MINIMAP = "Minimap button"
L.MINIMAP_TIP = "Shows Lueur's button on the edge of the minimap."
L.DEBUG = "Diagnostics in chat"
L.DEBUG_TIP = "Describes in the chat window each object targeted and what Lueur makes of it."

-- page de la minimap
L.NODES_PAGE = "Herbs and ore on the minimap"
L.HEADER_NODES = "Minimap icons"
L.HEADER_SWITCH = "Two gathering professions"
L.NODE_HERBS = "Herb icons"
L.NODE_HERBS_TIP = "Each herb your tracking puts on the minimap shows as that herb's own icon instead of a plain dot."
L.NODE_ORE = "Ore icons"
L.NODE_ORE_TIP = "Each mineral vein your tracking puts on the minimap shows as the icon of its ore instead of a plain dot."
L.NODE_SIZE = "Icon size"
L.NODE_SIZE_TIP = "How large the icons are on the minimap."
L.NODE_RING = "Ring thickness"
L.NODE_RING_TIP = "How thick the coloured ring around each icon is, which tells how hard the node is for your skill. At 0 %, no ring."
L.NODE_COMBAT = "Read the minimap in combat"
L.NODE_COMBAT_TIP = "Lueur keeps reading the minimap during a fight. Untick it to leave the minimap alone until the fight is over."
L.HEADER_SCANNING = "Reading the minimap"
L.NODE_SCAN_YARDS = "Distance between scans"
L.NODE_SCAN_YARDS_TIP = "How far you travel before Lueur reads the minimap again. Each scan hides the minimap for a moment: further apart, it hides less often, and new nodes show up later."
L.NODE_SWITCH = "Alternate the two trackings"
L.NODE_SWITCH_TIP = "The game shows the dots of Find Herbs or those of Find Minerals, never both. Lueur turns the other one on each time you have moved far enough, and keeps the icons of both on the minimap. Each character has its own setting."
L.NODE_SWITCH_YARDS = "Distance between switches"
L.NODE_SWITCH_YARDS_TIP = "How far you travel before Lueur turns the other tracking on."

L.PREVIEW_NO_MODEL = "3D model unavailable on this client"
L.PREVIEW_HINT = "Drag: turn  ·  right-drag: move  ·  wheel: zoom"
L.DEFAULTS = "Defaults"
L.DEFAULTS_TIP = "Puts the effect and detection settings back to their original values. A second click confirms."
L.FOOTER = "Lueur %s  ·  /lueur help: all commands"

L.OPTIONS_NOTE = "Makes ore veins, herbs, quest objects and chests glow as you approach them."
L.OPTIONS_OPEN = "Open Lueur's settings"

L.TIP_ENABLED = "Enabled"
L.TIP_DISABLED = "Disabled"
L.TIP_LEFT_CLICK = "Left-click: open the settings"
L.TIP_RIGHT_CLICK = "Right-click: enable or disable"
L.TIP_DRAG = "Drag: move this button"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "enabled."
L.MSG_DISABLED = "disabled, your original settings are restored."
L.MSG_RESTART = "restart the game completely to finish updating Lueur."
L.MSG_NODES_OFF = "the minimap icons for herbs and ore are now off by default, and this update turned them off. Turn them back on in the settings (/lueur) or with /lueur nodes."
L.MSG_EXCLUSIVE_ON = "the game no longer points out targets that get no effect."
L.MSG_EXCLUSIVE_OFF = "the game shows the name and icon of every interaction target (NPCs, world objects…)."
L.MSG_SILHOUETTE_ON = "the effect passes behind your character."
L.MSG_SILHOUETTE_OFF = "the effect covers your character."
L.MSG_CUTOUT_UNAVAILABLE = "cut-out unavailable: %s."
L.MSG_ZONE_SHOWN = "cut-out outlined in red: it should hug your character."
L.MSG_ZONE_HIDDEN = "cut-out outline hidden."
L.MSG_SILHOUETTE_VALUES = "silhouette: size %d%%, height %d%%"
L.MSG_SILHOUETTE_USAGE = "usage: /lueur silhouette | show | <size {bodyScale}> [height {bodyShift}]"
L.MSG_EFFECTS = "available effects: %s (current: %s)"
L.MSG_FONTS = "available fonts: %s (current: %s)"
L.MSG_COLOR = "%s: color %s"
L.MSG_NO_PICKER = "this client has no color picker: type /lueur color <category> <rrggbb>."
L.MSG_SHARED = "%s: back to the effect and appearance of all objects."
L.MSG_HIDE_COMBAT = "effect hidden in combat: %s"
L.MSG_HIDE_INSTANCE = "effect hidden in instances: %s"
L.MSG_HIDE_LOCKED = "effect hidden on objects you cannot use: %s"
L.MSG_HIDE_UNTRAINED = "effect hidden on herbs and ore without the profession: %s"
L.MSG_GLOW_ONLY = "glow only, the nameplate left to the game or another addon: %s"
L.MSG_IGNORED = "%s will no longer get an effect."
L.MSG_UNIGNORED = "%s is no longer ignored."
L.MSG_IGNORE_NO_TARGET = "no object in front of you to ignore."
L.MSG_IGNORE_LIST = "ignored objects: %s"
L.MSG_IGNORE_EMPTY = "no object is ignored."
L.MSG_RANGE = "range: %d yd"
L.MSG_RANGE_COMBAT = "range: %d yd, applied once you leave combat."
L.MSG_RANGE_CLIENT = "range: %d yd requested, the client kept %s."
L.MSG_KEY_COMBAT = "key bindings cannot be changed in combat."
L.MSG_KEY_REFUSED = "the game refused the key “%s”."
L.MSG_KEY_REPLACED = "%s no longer triggers “%s”."
L.MSG_NODES_UNAVAILABLE = "minimap icons unavailable: %s."

L.FAIL_NO_MASK = "this client does not support masks"
L.FAIL_MASK_TEXTURE = "mask texture not found (fully restart the game)"
L.FAIL_MASK_REFUSED = "the client refused the mask"
L.FAIL_NO_SCAN = "this client does not let an addon read the dots of the minimap"
L.FAIL_SCAN_ERROR = "the game refused the minimap scan (/lueur scan says why)"

L.STATUS_CLIENT = "client %s (%s), language %s; Lueur's texts: %s. Values in effect:"
L.STATUS_CVAR_UNKNOWN = "unknown to this client"
L.STATUS_CVAR_DEFAULT = " (default %s)"
L.STATUS_EXPECTED = "expected by Lueur: range %d, arc %d"
L.STATUS_GATE = "only highlighted targets pointed out: %s | native display right now: %s"
L.STATUS_GLOW_ONLY = "glow only: %s | Plumber's soft target name: %s"
L.GATE_OPEN = "open"
L.GATE_CLOSED = "closed"
L.STATUS_SILHOUETTE = "effect behind the character: %s"
L.STATUS_UNAVAILABLE = "unavailable, %s"
L.STATUS_DIRECT = "target read straight from “softinteract”: %s"
L.STATUS_NOT_YET = "not seen yet"
L.STATUS_RANGE_API = "interaction range readable: %s"
L.STATUS_LINE = "fishing line out: %s | channel in progress: %s"
L.STATUS_NODES = "minimap icons: %s"
L.STATUS_NODES_SHOWN = "herbs %s, ore %s, trackings alternated %s"
L.STATUS_HIDE = "hidden in combat: %s | in instances: %s | on unavailable objects: %s | paused right now: %s"
L.STATUS_TRAINED = "no effect on herbs and ore without the profession: %s | herbalism: %s, mining: %s"
L.STATUS_OBJECTS = "categories shown on this character: %s | ignored objects: %d"
L.STATUS_OWN = "categories with settings of their own: %s"
L.STATUS_EFFECT = "effect: %s | textures: %s"
L.STATUS_KEY = "interact key: %s"
L.TEXTURES_PENDING = "not loaded yet"
L.TEXTURES_MISSING = "missing, fallback effect shown (fully restart the game)"
L.TEXTURES_LOADED = "loaded"

L.OBJECTIVES_HEADER = "%d quest objective(s) in progress:"
L.OBJECTIVES_NOT_ITEM = "  (not an object: only compared to the whole name)"
L.OBJECTIVES_LEARNED = "learned from a tooltip: %s (%s)"

-- /lueur scan
L.SCAN_HEADER = "minimap scan: %s"
L.SCAN_READY = "available"
L.SCAN_TRACKING = "gathering trackings: %s"
L.SCAN_SKILL = "skill read: herbalism %s, mining %s"
L.SCAN_VIEW = "minimap radius: %s yd | turns with you: %s | position on the map known: %s | a dot answers within %s units"
L.SCAN_TWICE = "a name written twice where two dots overlap: %s"
L.SCAN_PLACED = "icons: %d placed exactly, %d in a cluster, %d roughly, %d kept from the tracking that is off, %d not found again | last scan: %d points in %.2f s, %d cluster(s) looked at closely"
L.SCAN_NODE = "%s: %s, answers within %s units, at (%+.0f, %+.0f) from the middle of the minimap"
L.SCAN_HOW_EXACT = "placed exactly"
L.SCAN_HOW_CLUSTER = "in a cluster"
L.SCAN_HOW_ROUGH = "roughly"
L.SCAN_HOW_HELD = "kept from the tracking that is off"
L.SCAN_HOW_MISSED = "not found again"
L.SCAN_FOUND = "%d name(s) read at the last scan, %d icon(s):"
L.SCAN_NOT_NODE = "neither a herb nor a vein Lueur knows"
L.SCAN_NEEDS = ", requires %d"
L.SCAN_CAVE = ", in a cave"
L.SCAN_VIGNETTES = "vignettes the game lists: %s"
L.SCAN_DATA = "data of the dot under the pointer, besides its text: %s"
L.SCAN_POINTER = "under the pointer: %s"
L.SCAN_READER = "minimap under the mouse | last scan: %d frames, %d grid points%s, %d known nodes checked, %d groups measured, %d points placed again | interrupted %d times, last: %s | waiting for: %s | its opacity put back to 0 after another code changed it: %d times"
L.SCAN_HIDE = "hidden by its %s | shape: %s | %d of its frames hidden with it, %d shown again meanwhile and hidden anew"
L.SCAN_BY_MASK = "mask"
L.SCAN_BY_ALPHA = "opacity"
L.SCAN_FULL = " (whole minimap)"
L.SCAN_SOON = "the minimap will be scanned as soon as it can go under the mouse"
L.SCAN_BUSY = "a scan of the minimap is running"
L.SCAN_WHY_COMBAT = "combat"
L.SCAN_WHY_HIDDEN = "the minimap hidden"
L.SCAN_WHY_POINTER = "the mouse on the minimap"
L.SCAN_WHY_CAMERA = "the camera turned with the mouse"
L.SCAN_WHY_WINDOW = "the mouse over a window"
L.SCAN_WHY_ZOOM = "the minimap zoomed"
L.SCAN_WHY_TURN = "the minimap turned"
L.SCAN_WHY_MAP = "another map"
L.SCAN_WHY_TAXI = "a flight path"
L.SCAN_WHY_NPC = "an NPC window open"
L.SCAN_NOTHING = "nothing (put the pointer on a dot of the minimap and type the command again)"

---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "no interaction target any more"
L.DEBUG_PAUSED = "paused (combat or instance)"
L.DEBUG_LINE_OUT = "fishing line out: %d yd requested, the client kept %s"
L.DEBUG_LINE_IN = "fishing line reeled in: %d yd requested, the client kept %s"
L.DEBUG_IGNORED = "%s ignored (not a world object)"
L.DEBUG_SKIPPED = "%s ignored (on your list of ignored objects)"
L.DEBUG_HIDDEN = "%s → %s, no effect (category hidden or unknown)"
L.DEBUG_UNTRAINED = "%s → %s, no effect (this character does not have the profession)"
L.DEBUG_NO_PLATE = "%s → %s, detected but without a nameplate: no effect possible"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "cursor: %s"
L.DEBUG_VIA = "target: %s"
L.VIA_DIRECT = "direct"
L.VIA_SWEEP = "sweep"
L.DEBUG_RANGE = "in interaction range: %s"
L.DEBUG_OBJECT = "object ID: %s"
L.DEBUG_FISHING = "fishing: %s"
L.DEBUG_QUEST = "quest-related: %s"
L.DEBUG_MATCH = "tied to an objective by: %s (%d objectives in progress)"
L.MATCH_NONE = "nothing"
L.MATCH_CURSOR = "nothing, its cursor says what it is"
L.MATCH_TOOLTIP = "its tooltip"
L.MATCH_NAME = "its name"
L.MATCH_WORD = "the word “%s”"
L.MATCH_LOOT = "its loot, taken before"
L.DEBUG_CHEST = "known as a container by: %s"
L.DEBUG_SECRET = "secret identity: %s"
L.DEBUG_BEHIND = "behind the camera: %s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "commands:"
L.HELP = {
	"/lueur — opens or closes the settings window (like a click on the minimap button)",
	"/lueur minimap — shows or hides the minimap button",
	"/lueur on | off — enables or disables Lueur (off restores your settings)",
	"/lueur preview — opens the settings window on the preview, which shows the effect on a 3D object",
	"/lueur effect [category] <name> — gives this effect to every category, or to one of them (ore, herb, quest, chest, bobber, other); without a name, lists them",
	"/lueur color <category> <rrggbb> | default — color of a category's effect; without a color, shows it",
	"/lueur shared <category> — gives a category back the effect and appearance of all objects",
	"/lueur size [category] <{size}> — size of the effect (default {size=})",
	"/lueur intensity [category] <{intensity}> — brightness of the effect, in % (default {intensity=})",
	"/lueur offset [category] <{offsetY}> — vertical offset of the effect (default {offsetY=})",
	"/lueur fade [category] — whether the effect fades with the nameplate (object hidden by the scenery)",
	"/lueur name | icon [category] — whether the object's name, or its icon, shows above it; text [category] <{textSize}> sets the size of the name, in % (default {textSize=})",
	"/lueur font [category] <name> | default — font of the object's name; without a name, lists them",
	"/lueur silhouette [category] — whether the effect passes behind your character instead of covering it",
	"/lueur silhouette show | <size %> [height %] — shows and adjusts the cut-out",
	"/lueur range <{range}> — how far the game picks objects, in yards (default {range=})",
	"/lueur arc <{arc}> — 0 dead ahead, 1 in front, 2 every direction (default {arc=})",
	"/lueur exclusive — whether the game only points out the targets that get an effect",
	"/lueur glowonly — whether Lueur only draws the light, leaving the target's nameplate (name, icon) to the game or another addon",
	"/lueur combat | instance | unavailable | profession — whether the effect hides in combat, in instances, on objects you cannot use, on herbs and ore without the profession",
	"/lueur key <KEY> | none — binds the key that picks up the highlighted object (F, SHIFT-E, BUTTON4…); without a key, shows it",
	"/lueur ore | herb | quest | chest | bobber | other — shows or hides a category, for this character",
	"/lueur nodes [ore | herb] — shows or hides the icons of herbs and veins on the minimap; nodes size <{nodeSize}> sets their size (default {nodeSize=}); nodes ring <{nodeRing}> sets the thickness of their coloured ring, 0 for none (default {nodeRing=}); nodes combat: whether the minimap is read in combat",
	"/lueur switch [<{nodeSwitchYards}>] — with both gathering professions: alternates Find Herbs and Find Minerals as you move; a number sets how far apart, in yards (default {nodeSwitchYards=})",
	"/lueur scan — shows what the last scan of the minimap read, and what Lueur made of it; scan <{nodeScanYards}> sets how far apart scans are, in yards (default {nodeScanYards=})",
	"/lueur ignore — ignores the object you are facing, or stops ignoring it; ignore list, ignore clear, ignore <name>",
	"/lueur language <auto | de | en | es | fr | ru> — language of Lueur's texts and commands",
	"/lueur debug — describes each object targeted and what Lueur makes of it",
	"/lueur objectives — lists the quest objectives that object names are compared to",
	"/lueur status — shows the values the client actually applies",
	"/lueur help — shows this list",
}
