-- Lueur : textes en allemand

local _, ns = ...

local L = {}
ns.LOCALES.deDE = L

L.LANGUAGE_NAME = "Deutsch"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "ja"
L.NO = "nein"
L.SETTING = "%s: %s"
L.FORMAT_PERCENT = "%d %%"
L.FORMAT_RANGE = "%d m"
L.CONFIRM = "Bestätigen?"

L.COMMANDS = {
	gemeinsam = "shared",
	vorschau = "preview", effekt = "effect", farbe = "color", standard = "default", ["größe"] = "size",
	["intensität"] = "intensity", versatz = "offset", verblassen = "fade", symbol = "icon", schrift = "font", zeigen = "show",
	reichweite = "range", exklusiv = "exclusive", kampf = "combat", instanz = "instance", gesperrt = "unavailable", beruf = "profession",
	erz = "ore", kraut = "herb", truhe = "chest", schwimmer = "bobber", sonstiges = "other", ignorieren = "ignore", liste = "list",
	leeren = "clear", ziele = "objectives", hilfe = "help", taste = "key", keine = "none", sprache = "language",
	sammelpunkte = "nodes", wechseln = "switch", abtasten = "scan", rand = "ring",
	nurlicht = "glowonly",
}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Erze"
L.CATEGORY_ORE_TIP = "Erzadern und Erzvorkommen."
L.CATEGORY_HERB = "Kräuter"
L.CATEGORY_HERB_TIP = "Pflanzen, die du sammeln kannst."
L.CATEGORY_QUEST = "Quests"
L.CATEGORY_QUEST_TIP = "Objekte, die zu einer deiner laufenden Quests gehören."
L.CATEGORY_CHEST = "Truhen"
L.CATEGORY_CHEST_TIP = "Truhen, Kisten und andere Behälter, die du plündern kannst."
L.CATEGORY_BOBBER = "Schwimmer"
L.CATEGORY_BOBBER_TIP = "Der Schwimmer deiner Angelschnur."
L.CATEGORY_OTHER = "Andere Objekte"
L.CATEGORY_OTHER_TIP = "Alltägliche Objekte: Türen, Briefkästen, Hebel…"

L.NAME_ORE = "Erz"
L.NAME_HERB = "Kraut"
L.NAME_QUEST = "Quest"
L.NAME_CHEST = "Truhe"
L.NAME_BOBBER = "Schwimmer"
L.NAME_OTHER = "Sonstiges"
L.NAME_NONE = "keine"

L.SAMPLE_ORE = "Kupferader"
L.SAMPLE_HERB = "Friedensblume"
L.SAMPLE_QUEST = "Vorratskiste"
L.SAMPLE_CHEST = "Ramponierte Truhe"
L.SAMPLE_BOBBER = "Schwimmer"
L.SAMPLE_OTHER = "Briefkasten"

L.STATE_FAR = "außer Reichweite"
L.STATE_READY = "in Reichweite"
L.STATE_LOCKED = "nicht verfügbar"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "Ein Lichthof mit Schwaden, Ring, Kometen und Glühwürmchen."
L.EFFECT_SUBTLE = "Dezent"
L.EFFECT_SUBTLE_TIP = "Ein sanfter Schein, ohne Ring und ohne Kometen."
L.EFFECT_SIGIL = "Siegel"
L.EFFECT_SIGIL_TIP = "Ein Runenkreis dreht sich langsam um das Objekt."
L.EFFECT_VORTEX = "Wirbel"
L.EFFECT_VORTEX_TIP = "Lichtarme winden sich um das Objekt, wie ein Portal, das sich öffnet."
L.EFFECT_FLAME = "Flamme"
L.EFFECT_FLAME_TIP = "Feuerzungen steigen vom Objekt auf, in seiner Farbe."
L.EFFECT_RIFT = "Riss"
L.EFFECT_RIFT_TIP = "Ein von Licht umringtes schwarzes Loch saugt Funken in eine Spirale."
L.EFFECT_STORM = "Gewitter"
L.EFFECT_STORM_TIP = "Über dem Objekt ballt sich eine Gewitterwolke, aus der Blitze einschlagen."
L.EFFECT_GEYSER = "Geysir"
L.EFFECT_GEYSER_TIP = "Eine Lichtfontäne schießt aus dem Objekt und fällt um es herum zurück."
L.EFFECT_SPIRIT = "Geist"
L.EFFECT_SPIRIT_TIP = "Zwei Irrlichter tanzen um das Objekt und ziehen ein Lichtband hinter sich her."
L.EFFECT_BEAM = "Lichtsäule"
L.EFFECT_BEAM_TIP = "Eine Lichtsäule steigt vom Objekt auf, Funken ziehen an ihr empor."
L.EFFECT_BEACON = "Leuchtfeuer"
L.EFFECT_BEACON_TIP = "Ein Kristall schwebt über dem Objekt, durch einen Lichtfaden mit ihm verbunden."
L.EFFECT_ORBIT = "Umlaufbahn"
L.EFFECT_ORBIT_TIP = "Drei Irrlichter kreisen um das Objekt, jedes auf seiner eigenen Bahn."
L.EFFECT_RIPPLE = "Wellen"
L.EFFECT_RIPPLE_TIP = "Wellen breiten sich auf dem Boden um das Objekt aus."
L.EFFECT_SPARKLE = "Funkeln"
L.EFFECT_SPARKLE_TIP = "Lichtpunkte funkeln um das Objekt, ganz ohne Kreis."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silhouette"
L.HEADER_OBJECTS = "Hervorgehobene Objekte"
L.HEADER_HIDE = "Effekt ausblenden"
L.HEADER_DETECTION = "Erkennung"
L.HEADER_GENERAL = "Allgemein"
L.SETTINGS = "Einstellungen"

L.SCOPE_ALL = "Alle"
L.SCOPE_ALL_TIP = "Was du einstellst, gilt für alle Kategorien. Eine Kategorie mit eigenem Wert für diese Einstellung verliert ihn."
L.SCOPE_ONE_TIP = "Was du einstellst, gilt nur für diese Kategorie; sie behält es, was auch immer mit den anderen geschieht."
L.EFFECT = "Effekt"
L.EFFECT_TIP = "Die Form des Lichts."
L.LOOK_OF_ALL = "Aussehen aller Objekte"
L.LOOK_OF = "Aussehen: %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "Wie alle Objekte"
L.SHARED_TIP = "Nimmt dieser Kategorie ihren eigenen Effekt und ihr eigenes Aussehen: Sie übernimmt wieder die aller Objekte."

L.SIZE = "Größe"
L.SIZE_TIP = "Wie groß der Effekt ist."
L.INTENSITY = "Intensität"
L.INTENSITY_TIP = "Wie hell der Effekt ist."
L.OFFSET = "Vertikaler Versatz"
L.OFFSET_TIP = "Verschiebt den Effekt gegenüber der Namensplakette des Objekts nach oben oder unten. Die Vorschau zeigt, wo er landet."
L.FADE = "Mit der Namensplakette verblassen"
L.FADE_TIP = "Der Effekt verblasst zusammen mit der Namensplakette des Objekts, etwa wenn die Umgebung es verdeckt."

L.SILHOUETTE = "Hinter meinem Charakter"
L.SILHOUETTE_TIP = "Der Effekt wird um deinen Charakter herum ausgeschnitten: Er scheint hinter dir zu liegen, statt dich zu überdecken."
L.ZONE_SIZE = "Größe des Ausschnitts"
L.ZONE_SIZE_TIP = "Vergrößern, wenn der Effekt in deinen Charakter hineinragt; verkleinern, wenn er zu viel Abstand hält. Jeder Charakter behält seinen eigenen Wert."
L.ZONE_HEIGHT = "Höhe des Ausschnitts"
L.ZONE_HEIGHT_TIP = "Verschiebt den Ausschnitt nach oben oder unten. Jeder Charakter behält seinen eigenen Wert."
L.ZONE_SHOW = "Ausschnitt anzeigen"
L.ZONE_SHOW_TIP = "Zeichnet den Umriss des Ausschnitts in Rot: Er soll deinen Charakter eng umschließen. Verschwindet, wenn dieses Fenster geschlossen wird."

L.SHOW_NAME = "Namen anzeigen"
L.SHOW_NAME_TIP = "Schreibt den Namen des Objekts über es, anstelle dessen, den das Spiel schreibt."
L.SHOW_ICON = "Symbol anzeigen"
L.SHOW_ICON_TIP = "Zeigt das Interaktionssymbol des Objekts über ihm, anstelle dessen, das das Spiel zeichnet."
L.TEXT_SIZE = "Textgröße"
L.TEXT_SIZE_TIP = "Größe des Namens über dem Objekt, gemessen am Text des Spiels."
L.FONT = "Schriftart"
L.FONT_TIP = "Schriftart des Namens über dem Objekt."
L.FONT_GAME = "Spielschrift"
L.COLOR = "Farbe"
L.COLOR_TIP = "Die Farbe des Effekts auf diesen Objekten."
L.TIP_COLOR_SET = "Linksklick: Farbe wählen"
L.TIP_COLOR_RESET = "Rechtsklick: zurück zur ursprünglichen Farbe"
L.IGNORED = "Ignorierte Objekte: %d"
L.IGNORED_TIP = "Objekte, die nie einen Effekt erhalten, gleich welcher Kategorie. /lueur ignorieren liste nennt sie, /lueur ignorieren leeren vergisst sie alle."
L.IGNORE_TARGET = "Ziel ignorieren"
L.IGNORE_TARGET_TIP = "Ignoriert das Objekt, vor dem du gerade stehst, oder hebt das wieder auf."

L.HIDE_COMBAT = "Im Kampf"
L.HIDE_COMBAT_TIP = "Kein Effekt, solange du im Kampf bist."
L.HIDE_INSTANCE = "In Instanzen"
L.HIDE_INSTANCE_TIP = "Kein Effekt in Dungeons, Schlachtzügen und auf Schlachtfeldern."
L.HIDE_LOCKED = "Auf nicht nutzbaren Objekten"
L.HIDE_LOCKED_TIP = "Der Effekt erlischt auf einem Objekt, das das Spiel dir vorerst verweigert: Fertigkeit zu niedrig, Objekt verschlossen… Das Spiel verrät es erst, wenn du in Reichweite bist."
L.HIDE_UNTRAINED = "Kräuter und Erz ohne den Beruf"
L.HIDE_UNTRAINED_TIP = "Kein Effekt auf Kräutern, wenn dieser Charakter keine Kräuterkunde hat, und keiner auf Erz ohne Bergbau."

L.RANGE = "Reichweite"
L.RANGE_TIP = "Bis zu welcher Entfernung das Spiel ein Objekt zum Hervorheben auswählen darf."
L.DIRECTION = "Richtung"
L.DIRECTION_TIP = "Wo das Spiel nach einem Objekt sucht."
L.ARC_0 = "Geradeaus"
L.ARC_0_TIP = "Nur was direkt vor dir steht."
L.ARC_1 = "Vor mir"
L.ARC_1_TIP = "Alles, was vor dir liegt."
L.ARC_2 = "Überall"
L.ARC_2_TIP = "In jeder Richtung, auch hinter deinem Rücken."
L.EXCLUSIVE = "Nur hervorgehobene Ziele zeigen"
L.EXCLUSIVE_TIP = "Das Spiel weist nicht mehr auf Interaktionsziele hin, die keinen Effekt erhalten: NSCs, Briefkästen… Ohne Haken zeigt es auf jedem davon einen Namen und ein Symbol."
L.GLOW_ONLY = "Nur das Leuchten"
L.GLOW_ONLY_TIP = "Lueur schreibt Namen und Symbol des Objekts nicht mehr und lässt, was das Spiel oder ein anderes Addon dort zeigt. Immer aktiv, solange Plumbers Soft-Target-Namensplakette eingeschaltet ist."

L.KEY = "Interaktionstaste"
L.KEY_TIP = "Die Taste, die das hervorgehobene Objekt aufhebt, sammelt oder benutzt, sobald es in Reichweite ist. Es ist die Interaktionstaste des Spiels: Sie funktioniert auch bei NSCs und lässt sich ebenso in der Tastaturbelegung des Spiels ändern."
L.KEY_NONE = "Nicht belegt"
L.KEY_LISTEN = "Taste drücken"
L.KEY_LISTEN_TIP = "Drücke die gewünschte Taste, Maustaste oder Mausradrichtung. Escape bricht ab."
L.KEY_TAKEN = "%s wird bereits für „%s“ verwendet. Drücke sie erneut, um sie stattdessen der Interaktion zu geben, oder wähle eine andere Taste."
L.TIP_KEY_SET = "Linksklick: Taste wählen"
L.TIP_KEY_CLEAR = "Rechtsklick: Taste entfernen"

L.LANGUAGE = "Sprache"
L.LANGUAGE_TIP = "Die Sprache der Texte und Befehle von Lueur."
L.LANGUAGE_AUTO = "Automatisch"
L.LANGUAGE_AUTO_TIP = "Folgt der Sprache des Spiels."

L.ENABLE = "Lueur aktivieren"
L.ENABLE_TIP = "Ist Lueur deaktiviert, erhält das Spiel deine ursprünglichen Zieleinstellungen zurück."
L.MINIMAP = "Minikartenknopf"
L.MINIMAP_TIP = "Zeigt den Knopf von Lueur am Rand der Minikarte."
L.DEBUG = "Diagnose im Chat"
L.DEBUG_TIP = "Beschreibt im Chatfenster jedes anvisierte Objekt und was Lueur daraus schließt."

L.NODES_PAGE = "Kräuter und Erze auf der Minikarte"
L.HEADER_NODES = "Symbole auf der Minikarte"
L.HEADER_SWITCH = "Zwei Sammelberufe"
L.NODE_HERBS = "Kräutersymbole"
L.NODE_HERBS_TIP = "Jedes Kraut, das deine Suche auf der Minikarte anzeigt, erscheint dort mit seinem eigenen Symbol statt als einfacher Punkt."
L.NODE_ORE = "Erzsymbole"
L.NODE_ORE_TIP = "Jedes Erzvorkommen, das deine Suche auf der Minikarte anzeigt, erscheint dort mit dem Symbol seines Erzes statt als einfacher Punkt."
L.NODE_SIZE = "Symbolgröße"
L.NODE_SIZE_TIP = "Wie groß die Symbole auf der Minikarte sind."
L.NODE_RING = "Ringstärke"
L.NODE_RING_TIP = "Wie dick der farbige Ring um jedes Symbol ist, der zeigt, wie schwer das Vorkommen für deine Fertigkeit ist. Bei 0 % kein Ring."
L.NODE_COMBAT = "Minikarte im Kampf lesen"
L.NODE_COMBAT_TIP = "Lueur liest die Minikarte auch während eines Kampfes. Abwählen, um sie bis zum Ende des Kampfes in Ruhe zu lassen."
L.HEADER_SCANNING = "Lesen der Minikarte"
L.NODE_SCAN_YARDS = "Abstand zwischen zwei Scans"
L.NODE_SCAN_YARDS_TIP = "Wie weit du gehst, bevor Lueur die Minikarte erneut liest. Jeder Scan blendet sie kurz aus: weiter auseinander seltener, neue Vorkommen erscheinen dafür später."
L.NODE_SWITCH = "Beide Suchen abwechseln"
L.NODE_SWITCH_TIP = "Das Spiel zeigt die Punkte der Kräutersuche oder die der Mineraliensuche, nie beide. Lueur schaltet die andere Suche ein, sobald du dich weit genug bewegt hast, und behält die Symbole beider auf der Minikarte. Jeder Charakter hat seine eigene Einstellung."
L.NODE_SWITCH_YARDS = "Strecke zwischen zwei Wechseln"
L.NODE_SWITCH_YARDS_TIP = "Wie weit du läufst, bevor Lueur die andere Suche einschaltet."

L.PREVIEW_NO_MODEL = "3D-Modell auf diesem Client nicht verfügbar"
L.PREVIEW_HINT = "Ziehen: drehen  ·  Rechtsklick: verschieben  ·  Mausrad: zoomen"
L.DEFAULTS = "Standard"
L.DEFAULTS_TIP = "Setzt die Einstellungen von Effekt und Erkennung auf ihre ursprünglichen Werte zurück. Ein zweiter Klick bestätigt."
L.FOOTER = "Lueur %s  ·  /lueur hilfe: alle Befehle"

L.OPTIONS_NOTE = "Lässt Erzadern, Kräuter, Questobjekte und Truhen aufleuchten, wenn du dich ihnen näherst."
L.OPTIONS_OPEN = "Einstellungen von Lueur öffnen"

L.TIP_ENABLED = "Aktiviert"
L.TIP_DISABLED = "Deaktiviert"
L.TIP_LEFT_CLICK = "Linksklick: Einstellungen öffnen"
L.TIP_RIGHT_CLICK = "Rechtsklick: aktivieren oder deaktivieren"
L.TIP_DRAG = "Ziehen: diesen Knopf verschieben"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "aktiviert."
L.MSG_DISABLED = "deaktiviert, deine ursprünglichen Einstellungen sind wiederhergestellt."
L.MSG_RESTART = "starte das Spiel vollständig neu, um die Aktualisierung von Lueur abzuschließen."
L.MSG_NODES_OFF = "die Minikartensymbole für Kräuter und Erze sind jetzt standardmäßig aus, und dieses Update hat sie ausgeschaltet. Schalte sie in den Einstellungen (/lueur) oder mit /lueur nodes wieder ein."
L.MSG_EXCLUSIVE_ON = "das Spiel weist nicht mehr auf Ziele hin, die keinen Effekt erhalten."
L.MSG_EXCLUSIVE_OFF = "das Spiel zeigt Namen und Symbol aller Interaktionsziele (NSCs, Objekte der Spielwelt…)."
L.MSG_SILHOUETTE_ON = "der Effekt liegt hinter deinem Charakter."
L.MSG_SILHOUETTE_OFF = "der Effekt überdeckt deinen Charakter."
L.MSG_CUTOUT_UNAVAILABLE = "Ausschnitt nicht verfügbar: %s."
L.MSG_ZONE_SHOWN = "Ausschnitt in Rot umrissen: Er soll deinen Charakter eng umschließen."
L.MSG_ZONE_HIDDEN = "Umriss des Ausschnitts ausgeblendet."
L.MSG_SILHOUETTE_VALUES = "Silhouette: Größe %d %%, Höhe %d %%"
L.MSG_SILHOUETTE_USAGE = "Verwendung: /lueur silhouette | zeigen | <Größe {bodyScale}> [Höhe {bodyShift}]"
L.MSG_EFFECTS = "verfügbare Effekte: %s (aktuell: %s)"
L.MSG_FONTS = "verfügbare Schriftarten: %s (aktuell: %s)"
L.MSG_COLOR = "%s: Farbe %s"
L.MSG_NO_PICKER = "dieser Client hat keine Farbauswahl: Tippe /lueur farbe <Kategorie> <rrggbb>."
L.MSG_SHARED = "%s: wieder Effekt und Aussehen aller Objekte."
L.MSG_HIDE_COMBAT = "Effekt im Kampf ausgeblendet: %s"
L.MSG_HIDE_INSTANCE = "Effekt in Instanzen ausgeblendet: %s"
L.MSG_HIDE_LOCKED = "Effekt auf nicht nutzbaren Objekten ausgeblendet: %s"
L.MSG_HIDE_UNTRAINED = "Effekt auf Kräutern und Erz ohne den Beruf ausgeblendet: %s"
L.MSG_GLOW_ONLY = "nur das Leuchten, die Namensplakette bleibt dem Spiel oder einem anderen Addon: %s"
L.MSG_IGNORED = "%s erhält keinen Effekt mehr."
L.MSG_UNIGNORED = "%s wird nicht mehr ignoriert."
L.MSG_IGNORE_NO_TARGET = "kein Objekt vor dir, das ignoriert werden könnte."
L.MSG_IGNORE_LIST = "ignorierte Objekte: %s"
L.MSG_IGNORE_EMPTY = "kein Objekt wird ignoriert."
L.MSG_RANGE = "Reichweite: %d m"
L.MSG_RANGE_COMBAT = "Reichweite: %d m, wird nach dem Kampf angewendet."
L.MSG_RANGE_CLIENT = "Reichweite: %d m angefordert, der Client hat %s behalten."
L.MSG_KEY_COMBAT = "die Tastaturbelegung lässt sich im Kampf nicht ändern."
L.MSG_KEY_REFUSED = "das Spiel hat die Taste „%s“ abgelehnt."
L.MSG_KEY_REPLACED = "%s löst nicht mehr „%s“ aus."
L.MSG_NODES_UNAVAILABLE = "Symbole auf der Minikarte nicht verfügbar: %s."

L.FAIL_NO_MASK = "dieser Client unterstützt keine Masken"
L.FAIL_MASK_TEXTURE = "Maskentextur nicht gefunden (Spiel vollständig neu starten)"
L.FAIL_MASK_REFUSED = "der Client hat die Maske abgelehnt"
L.FAIL_NO_SCAN = "dieser Client lässt ein Addon die Punkte der Minikarte nicht lesen"
L.FAIL_SCAN_ERROR = "das Spiel hat das Abtasten der Minikarte verweigert (/lueur abtasten sagt, warum)"

L.STATUS_CLIENT = "Client %s (%s), Sprache %s; Texte von Lueur: %s. Geltende Werte:"
L.STATUS_CVAR_UNKNOWN = "diesem Client unbekannt"
L.STATUS_CVAR_DEFAULT = " (Standard %s)"
L.STATUS_EXPECTED = "von Lueur erwartet: Reichweite %d, Bogen %d"
L.STATUS_GATE = "nur auf hervorgehobene Ziele wird hingewiesen: %s | native Anzeige im Moment: %s"
L.STATUS_GLOW_ONLY = "nur das Leuchten: %s | Plumbers Name des Soft-Ziels: %s"
L.GATE_OPEN = "offen"
L.GATE_CLOSED = "geschlossen"
L.STATUS_SILHOUETTE = "Effekt hinter dem Charakter: %s"
L.STATUS_UNAVAILABLE = "nicht verfügbar, %s"
L.STATUS_DIRECT = "Ziel direkt über „softinteract“ gelesen: %s"
L.STATUS_NOT_YET = "noch nicht beobachtet"
L.STATUS_RANGE_API = "Interaktionsreichweite lesbar: %s"
L.STATUS_LINE = "Angelschnur im Wasser: %s | laufende Kanalisierung: %s"
L.STATUS_NODES = "Symbole auf der Minikarte: %s"
L.STATUS_NODES_SHOWN = "Kräuter %s, Erze %s, Suchen abgewechselt %s"
L.STATUS_HIDE = "im Kampf ausgeblendet: %s | in Instanzen: %s | auf nicht nutzbaren Objekten: %s | im Moment pausiert: %s"
L.STATUS_TRAINED = "kein Effekt auf Kräutern und Erz ohne den Beruf: %s | Kräuterkunde: %s, Bergbau: %s"
L.STATUS_OBJECTS = "auf diesem Charakter angezeigte Kategorien: %s | ignorierte Objekte: %d"
L.STATUS_OWN = "Kategorien mit eigenen Einstellungen: %s"
L.STATUS_EFFECT = "Effekt: %s | Texturen: %s"
L.STATUS_KEY = "Interaktionstaste: %s"
L.TEXTURES_PENDING = "noch nicht geladen"
L.TEXTURES_MISSING = "nicht gefunden, Ersatzeffekt wird gezeigt (Spiel vollständig neu starten)"
L.TEXTURES_LOADED = "geladen"

L.OBJECTIVES_HEADER = "%d laufende(s) Questziel(e):"
L.OBJECTIVES_NOT_ITEM = "  (kein Objekt: nur mit dem ganzen Namen verglichen)"
L.OBJECTIVES_LEARNED = "aus einem Tooltip gelernt: %s (%s)"

L.SCAN_HEADER = "Abtasten der Minikarte: %s"
L.SCAN_READY = "verfügbar"
L.SCAN_TRACKING = "Suchen der Sammelberufe: %s"
L.SCAN_SKILL = "gelesene Fertigkeit: Kräuterkunde %s, Bergbau %s"
L.SCAN_VIEW = "Radius der Minikarte: %s m | dreht sich mit dir: %s | Position auf der Karte bekannt: %s | ein Punkt antwortet im Umkreis von %s Einheiten"
L.SCAN_TWICE = "ein Name doppelt geschrieben, wo sich zwei Punkte überlagern: %s"
L.SCAN_PLACED = "Symbole: %d genau platziert, %d in einer Gruppe, %d ungefähr, %d von der ausgeschalteten Suche behalten, %d nicht wiedergefunden | letztes Abtasten: %d Punkte in %.2f s, %d Gruppe(n) genauer betrachtet"
L.SCAN_NODE = "%s: %s, antwortet im Umkreis von %s Einheiten, bei (%+.0f, %+.0f) von der Mitte der Minikarte"
L.SCAN_HOW_EXACT = "genau platziert"
L.SCAN_HOW_CLUSTER = "in einer Gruppe"
L.SCAN_HOW_ROUGH = "ungefähr"
L.SCAN_HOW_HELD = "von der ausgeschalteten Suche behalten"
L.SCAN_HOW_MISSED = "nicht wiedergefunden"
L.SCAN_FOUND = "%d Name(n) beim letzten Abtasten gelesen, %d Symbol(e):"
L.SCAN_NOT_NODE = "weder ein Kraut noch ein Vorkommen, das Lueur kennt"
L.SCAN_NEEDS = ", benötigt %d"
L.SCAN_CAVE = ", in einer Höhle"
L.SCAN_VIGNETTES = "Vignetten, die das Spiel auflistet: %s"
L.SCAN_DATA = "Daten des Punkts unter dem Zeiger, außer seinem Text: %s"
L.SCAN_POINTER = "unter dem Zeiger: %s"
L.SCAN_READER = "Minikarte unter der Maus | letzter Scan: %d Bilder, %d Rasterpunkte%s, %d bekannte Vorkommen geprüft, %d Gruppen vermessen, %d Punkte neu gesetzt | %d-mal unterbrochen, zuletzt: %s | wartet auf: %s | Deckkraft nach Änderung durch anderen Code auf 0 zurückgesetzt: %d-mal"
L.SCAN_HIDE = "verborgen durch ihre %s | Form: %s | %d ihrer Rahmen mit ihr verborgen, %d inzwischen wieder gezeigt und erneut verborgen"
L.SCAN_BY_MASK = "Maske"
L.SCAN_BY_ALPHA = "Deckkraft"
L.SCAN_FULL = " (ganze Minikarte)"
L.SCAN_SOON = "die Minikarte wird gescannt, sobald sie unter die Maus kann"
L.SCAN_BUSY = "ein Scan der Minikarte läuft"
L.SCAN_WHY_COMBAT = "Kampf"
L.SCAN_WHY_HIDDEN = "Minikarte ausgeblendet"
L.SCAN_WHY_POINTER = "Maus auf der Minikarte"
L.SCAN_WHY_CAMERA = "Kamera mit der Maus gedreht"
L.SCAN_WHY_WINDOW = "Maus über einem Fenster"
L.SCAN_WHY_ZOOM = "Minikarte gezoomt"
L.SCAN_WHY_TURN = "Minikarte gedreht"
L.SCAN_WHY_MAP = "andere Karte"
L.SCAN_WHY_TAXI = "ein Flug"
L.SCAN_WHY_NPC = "ein offenes NSC-Fenster"
L.SCAN_NOTHING = "nichts (setze den Zeiger auf einen Punkt der Minikarte und gib den Befehl erneut ein)"

---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "kein Interaktionsziel mehr"
L.DEBUG_PAUSED = "pausiert (Kampf oder Instanz)"
L.DEBUG_LINE_OUT = "Angelschnur im Wasser: %d m angefordert, der Client hat %s behalten"
L.DEBUG_LINE_IN = "Angelschnur eingeholt: %d m angefordert, der Client hat %s behalten"
L.DEBUG_IGNORED = "%s ignoriert (kein Objekt der Spielwelt)"
L.DEBUG_SKIPPED = "%s ignoriert (steht auf deiner Liste ignorierter Objekte)"
L.DEBUG_HIDDEN = "%s → %s, kein Effekt (Kategorie ausgeblendet oder unbekannt)"
L.DEBUG_UNTRAINED = "%s → %s, kein Effekt (dieser Charakter hat den Beruf nicht)"
L.DEBUG_NO_PLATE = "%s → %s, erkannt, aber ohne Namensplakette: kein Effekt möglich"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "Mauszeiger: %s"
L.DEBUG_VIA = "Ziel: %s"
L.VIA_DIRECT = "direkt"
L.VIA_SWEEP = "Durchlauf"
L.DEBUG_RANGE = "in Interaktionsreichweite: %s"
L.DEBUG_OBJECT = "Objekt-ID: %s"
L.DEBUG_FISHING = "beim Angeln: %s"
L.DEBUG_QUEST = "questbezogen: %s"
L.DEBUG_MATCH = "einem Questziel zugeordnet durch: %s (%d laufende Questziele)"
L.MATCH_NONE = "nichts"
L.MATCH_CURSOR = "nichts, sein Mauszeiger sagt, was es ist"
L.MATCH_TOOLTIP = "seinen Tooltip"
L.MATCH_NAME = "seinen Namen"
L.MATCH_WORD = "das Wort „%s“"
L.MATCH_LOOT = "seine Beute, schon einmal genommen"
L.DEBUG_CHEST = "als Behälter erkannt durch: %s"
L.DEBUG_SECRET = "geheime Identität: %s"
L.DEBUG_BEHIND = "hinter der Kamera: %s"

---------------------------------------------------------------------------
-- Aide (/lueur hilfe)
---------------------------------------------------------------------------

L.HELP_HEADER = "Befehle:"
L.HELP = {
	"/lueur — öffnet oder schließt das Einstellungsfenster (wie ein Klick auf den Minikartenknopf)",
	"/lueur minimap — zeigt oder verbirgt den Minikartenknopf",
	"/lueur on | off — aktiviert oder deaktiviert Lueur (off stellt deine Einstellungen wieder her)",
	"/lueur vorschau — öffnet das Einstellungsfenster mit der Vorschau, die den Effekt auf einem 3D-Objekt zeigt",
	"/lueur effekt [Kategorie] <Name> — gibt diesen Effekt allen Kategorien oder nur einer (erz, kraut, quest, truhe, schwimmer, sonstiges); ohne Namen werden die Effekte aufgelistet",
	"/lueur farbe <Kategorie> <rrggbb> | standard — Farbe des Effekts einer Kategorie; ohne Farbe wird sie angezeigt",
	"/lueur gemeinsam <Kategorie> — gibt einer Kategorie wieder Effekt und Aussehen aller Objekte",
	"/lueur größe [Kategorie] <{size}> — Größe des Effekts (Standard {size=})",
	"/lueur intensität [Kategorie] <{intensity}> — Helligkeit des Effekts, in % (Standard {intensity=})",
	"/lueur versatz [Kategorie] <{offsetY}> — vertikaler Versatz des Effekts (Standard {offsetY=})",
	"/lueur verblassen [Kategorie] — ob der Effekt mit der Namensplakette verblasst (Objekt von der Umgebung verdeckt)",
	"/lueur name | symbol [Kategorie] — ob der Name des Objekts oder sein Symbol über ihm angezeigt wird; text [Kategorie] <{textSize}> stellt die Größe des Namens ein, in % (Standard {textSize=})",
	"/lueur schrift [Kategorie] <Name> | standard — Schriftart des Objektnamens; ohne Namen werden sie aufgelistet",
	"/lueur silhouette [Kategorie] — ob der Effekt hinter deinem Charakter liegt, statt ihn zu überdecken",
	"/lueur silhouette zeigen | <Größe %> [Höhe %] — zeigt den Ausschnitt und passt ihn an",
	"/lueur reichweite <{range}> — bis wohin das Spiel Objekte auswählt, in Metern (Standard {range=})",
	"/lueur arc <{arc}> — 0 genau voraus, 1 vor mir, 2 alle Richtungen (Standard {arc=})",
	"/lueur exklusiv — ob das Spiel nur auf Ziele hinweist, die einen Effekt erhalten",
	"/lueur nurlicht — ob Lueur nur das Licht zeichnet und die Namensplakette des Ziels (Name, Symbol) dem Spiel oder einem anderen Addon überlässt",
	"/lueur kampf | instanz | gesperrt | beruf — ob der Effekt im Kampf, in Instanzen, auf nicht nutzbaren Objekten, auf Kräutern und Erz ohne den Beruf ausgeblendet wird",
	"/lueur taste <TASTE> | keine — belegt die Taste, die das hervorgehobene Objekt aufhebt (F, SHIFT-E, BUTTON4…); ohne Taste wird sie angezeigt",
	"/lueur erz | kraut | quest | truhe | schwimmer | sonstiges — zeigt oder verbirgt eine Kategorie, für diesen Charakter",
	"/lueur sammelpunkte [erz | kraut] — zeigt oder verbirgt die Symbole der Kräuter und Erzvorkommen auf der Minikarte; sammelpunkte größe <{nodeSize}> stellt ihre Größe ein (Standard {nodeSize=}); sammelpunkte rand <{nodeRing}> stellt die Stärke ihres farbigen Rings ein, 0 für keinen (Standard {nodeRing=}); sammelpunkte kampf: ob die Minikarte im Kampf gelesen wird",
	"/lueur wechseln [<{nodeSwitchYards}>] — mit beiden Sammelberufen: wechselt beim Laufen zwischen Kräutersuche und Mineraliensuche; eine Zahl stellt die Strecke zwischen zwei Wechseln ein, in Metern (Standard {nodeSwitchYards=})",
	"/lueur abtasten — zeigt, was das letzte Abtasten der Minikarte gelesen hat und was Lueur daraus gemacht hat; abtasten <{nodeScanYards}> stellt den Abstand zwischen zwei Scans in Metern ein (Standard {nodeScanYards=})",
	"/lueur ignorieren — ignoriert das Objekt, vor dem du stehst, oder hebt das auf; ignorieren liste, ignorieren leeren, ignorieren <Name>",
	"/lueur sprache <auto | de | en | es | fr | ru> — Sprache der Texte und Befehle von Lueur",
	"/lueur debug — beschreibt jedes anvisierte Objekt und was Lueur daraus schließt",
	"/lueur ziele — listet die Questziele auf, mit denen Objektnamen verglichen werden",
	"/lueur status — zeigt die Werte, die der Client tatsächlich anwendet",
	"/lueur hilfe — zeigt diese Liste",
}
