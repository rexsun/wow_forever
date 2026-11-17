-- Lueur : textes en italien (traduction automatique, non relue)
local _, ns = ...

local L = {}
ns.LOCALES.itIT = L

L.LANGUAGE_NAME = "Italiano"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "sì"
L.NO = "no"
L.SETTING = "%s: %s"
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d m"
L.CONFIRM = "Confermi?"

-- Pas de mots de commande propres à l'italien : les noms anglais répondent.
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Minerali"
L.CATEGORY_ORE_TIP = "Vene di minerale."
L.CATEGORY_HERB = "Erbe"
L.CATEGORY_HERB_TIP = "Piante da cogliere."
L.CATEGORY_QUEST = "Missioni"
L.CATEGORY_QUEST_TIP = "Oggetti legati a una tua missione in corso."
L.CATEGORY_CHEST = "Forzieri"
L.CATEGORY_CHEST_TIP = "Forzieri, casse e altri contenitori da aprire."
L.CATEGORY_BOBBER = "Galleggiante"
L.CATEGORY_BOBBER_TIP = "Il galleggiante della tua lenza."
L.CATEGORY_OTHER = "Altri oggetti"
L.CATEGORY_OTHER_TIP = "Oggetti comuni: porte, cassette della posta, leve…"

-- la catégorie d'un objet, dans une phrase du diagnostic
L.NAME_ORE = "minerale"
L.NAME_HERB = "erba"
L.NAME_QUEST = "missione"
L.NAME_CHEST = "forziere"
L.NAME_BOBBER = "galleggiante"
L.NAME_OTHER = "altro"
L.NAME_NONE = "nessuna"
L.NAME_UNNAMED = "Oggetti senza nome"

-- l'objet que l'aperçu montre pour chaque catégorie
L.SAMPLE_ORE = "Vena di Rame"
L.SAMPLE_HERB = "Fiordipace"
L.SAMPLE_QUEST = "Cassa di Rifornimenti"
L.SAMPLE_CHEST = "Forziere Ammaccato"
L.SAMPLE_BOBBER = "Galleggiante"
L.SAMPLE_OTHER = "Cassetta della Posta"

L.STATE_FAR = "fuori portata"
L.STATE_READY = "a portata"
L.STATE_LOCKED = "indisponibile"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "Un alone di luce con le sue volute, un anello, comete e lucciole."
L.EFFECT_SUBTLE = "Discreto"
L.EFFECT_SUBTLE_TIP = "Un bagliore tenue, senza anello né comete."
L.EFFECT_SIGIL = "Sigillo"
L.EFFECT_SIGIL_TIP = "Un cerchio di rune gira lentamente attorno all'oggetto."
L.EFFECT_BRACKETS = "Mirino"
L.EFFECT_BRACKETS_TIP = "Quattro angoli inquadrano l'oggetto e si agganciano quando è a portata."
L.EFFECT_VORTEX = "Vortice"
L.EFFECT_VORTEX_TIP = "Bracci di luce si avvolgono attorno all'oggetto, come un portale che si apre."
L.EFFECT_FLAME = "Fiamma"
L.EFFECT_FLAME_TIP = "Lingue di fuoco salgono dall'oggetto, nel suo colore."
L.EFFECT_RIFT = "Squarcio"
L.EFFECT_RIFT_TIP = "Un buco nero cinto di luce risucchia scintille a spirale."
L.EFFECT_STORM = "Tempesta"
L.EFFECT_STORM_TIP = "Una nube temporalesca si forma sopra l'oggetto e ne cadono fulmini."
L.EFFECT_GEYSER = "Geyser"
L.EFFECT_GEYSER_TIP = "Una fontana di luce sgorga dall'oggetto e ricade attorno."
L.EFFECT_SPIRIT = "Spirito"
L.EFFECT_SPIRIT_TIP = "Due fuochi fatui danzano attorno all'oggetto con un nastro di luce."
L.EFFECT_BEAM = "Raggio"
L.EFFECT_BEAM_TIP = "Una colonna di luce si alza dall'oggetto, percorsa da scintille."
L.EFFECT_BEACON = "Faro"
L.EFFECT_BEACON_TIP = "Un cristallo fluttua sopra l'oggetto, unito da un filo di luce."
L.EFFECT_ORBIT = "Orbita"
L.EFFECT_ORBIT_TIP = "Tre fuochi fatui girano attorno all'oggetto, ognuno in orbita."
L.EFFECT_RIPPLE = "Onda"
L.EFFECT_RIPPLE_TIP = "Onde si allargano sul suolo attorno all'oggetto."
L.EFFECT_SPARKLE = "Scintille"
L.EFFECT_SPARKLE_TIP = "Luccichii brillano attorno all'oggetto, senza cerchio."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silhouette"
L.HEADER_OBJECTS = "Oggetti evidenziati"
L.HEADER_HIDE = "Nascondi effetto"
L.HEADER_DETECTION = "Rilevamento"
L.HEADER_GENERAL = "Generale"
L.SETTINGS = "Opzioni"

L.SCOPE_ALL = "Tutti"
L.SCOPE_ALL_TIP = "Ciò che imposti vale per ogni categoria. Quella che aveva un valore proprio lo perde."
L.SCOPE_ONE_TIP = "Ciò che imposti vale solo per questa categoria, che lo tiene comunque."
L.EFFECT = "Effetto"
L.EFFECT_TIP = "La forma della luce."
L.LOOK_OF_ALL = "Aspetto di tutti gli oggetti"
L.LOOK_OF = "Aspetto: %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "Come tutti gli oggetti"
L.SHARED_TIP = "Toglie a questa categoria effetto e aspetto propri: riprende quelli di tutti gli oggetti."

L.SIZE = "Dimensione"
L.SIZE_TIP = "Grandezza dell'effetto."
L.INTENSITY = "Intensità"
L.INTENSITY_TIP = "Luminosità dell'effetto."
L.OFFSET = "Scarto verticale"
L.OFFSET_TIP = "Alza o abbassa l'effetto rispetto alla nameplate dell'oggetto. L'anteprima mostra dove va."
L.FADE = "Svanisce con la nameplate"
L.FADE_TIP = "L'effetto svanisce insieme alla nameplate dell'oggetto, ad esempio quando lo scenario lo copre."

L.SILHOUETTE = "Passa dietro al personaggio"
L.SILHOUETTE_TIP = "L'effetto è ritagliato attorno al tuo personaggio e sembra passargli dietro invece di coprirlo."
L.ZONE_SIZE = "Dimensione del ritaglio"
L.ZONE_SIZE_TIP = "Aumenta se l'effetto morde il personaggio, riduci se resta troppo lontano. Ogni personaggio ha la sua."
L.ZONE_HEIGHT = "Altezza del ritaglio"
L.ZONE_HEIGHT_TIP = "Alza o abbassa il ritaglio. Ogni personaggio ha la sua."
L.ZONE_SHOW = "Mostra il ritaglio"
L.ZONE_SHOW_TIP = "Traccia in rosso il ritaglio: deve aderire al tuo personaggio. Sparisce alla chiusura della finestra."

L.SHOW_NAME = "Mostra il nome"
L.SHOW_NAME_TIP = "Scrive il nome sopra l'oggetto, al posto di quello del gioco."
L.SHOW_ICON = "Mostra l'icona"
L.SHOW_ICON_TIP = "Mostra sopra l'oggetto la sua icona d'interazione, al posto di quella del gioco."
L.TEXT_SIZE = "Dimensione testo"
L.TEXT_SIZE_TIP = "Dimensione del nome sopra l'oggetto, rispetto al testo del gioco."
L.FONT = "Font"
L.FONT_TIP = "Font del nome sopra l'oggetto."
L.FONT_GAME = "Font del gioco"
L.COLOR = "Colore"
L.COLOR_TIP = "Il colore dell'effetto su questi oggetti."
L.COLOR_SECOND = "Secondo colore"
L.COLOR_SECOND_TIP = "Il colore di linee sottili e scintille dell'effetto su questi oggetti. Uguale al primo finché non ne scegli uno."
L.TIP_COLOR_SAME = "Clic destro: uguale al primo"
L.TIP_COLOR_SWAP = "Maiusc-clic: scambia i due colori"
L.TIP_COLOR_SET = "Clic sinistro: scegli un colore"
L.TIP_COLOR_RESET = "Clic destro: colore originale"
L.IGNORED = "Oggetti ignorati: %d"
L.IGNORED_TIP = "Oggetti che non ricevono mai un effetto, di qualunque categoria. /lueur ignore list li elenca, /lueur ignore clear li dimentica tutti."
L.IGNORE_TARGET = "Ignora bersaglio"
L.IGNORE_TARGET_TIP = "Ignora l'oggetto che hai davanti ora e tutti quelli con lo stesso nome. Su un oggetto già ignorato, clicca due volte per non ignorarlo più."

L.HIDE_COMBAT = "In combattimento"
L.HIDE_COMBAT_TIP = "Nessun effetto in combattimento."
L.HIDE_INSTANCE = "In istanza"
L.HIDE_INSTANCE_TIP = "Nessun effetto in spedizioni, incursioni e campi di battaglia."
L.HIDE_LOCKED = "Su oggetti indisponibili"
L.HIDE_LOCKED_TIP = "L'effetto si spegne su un oggetto che il gioco rifiuta per ora: abilità troppo bassa, oggetto chiuso… Il gioco lo dice solo a portata."
L.HIDE_UNTRAINED = "Erbe e vene senza professione"
L.HIDE_UNTRAINED_TIP = "Nessun effetto sulle erbe se il personaggio non ha Erbalismo, né sulle vene senza Estrazione."

L.RANGE = "Portata"
L.RANGE_TIP = "Fino a che distanza il gioco può scegliere un oggetto da evidenziare."
L.DIRECTION = "Direzione"
L.DIRECTION_TIP = "Dove il gioco cerca l'oggetto."
L.ARC_0 = "Dritto"
L.ARC_0_TIP = "Solo ciò che hai proprio di fronte."
L.ARC_1 = "Davanti"
L.ARC_1_TIP = "Tutto ciò che hai davanti."
L.ARC_2 = "Ovunque"
L.ARC_2_TIP = "In ogni direzione, anche alle spalle."
L.EXCLUSIVE = "Mostra solo i bersagli evidenziati"
L.EXCLUSIVE_TIP = "Il gioco non segnala più i bersagli d'interazione senza effetto: PNG, cassette della posta… Se disattivato, mostra nome e icona su ognuno."
L.GLOW_ONLY = "Solo luce"
L.GLOW_ONLY_TIP = "Lueur non scrive più nome e icona dell'oggetto e lascia ciò che mostrano il gioco o un altro addon. Sempre attivo se lo è la nameplate Soft Target di Plumber."

L.KEY = "Tasto d'interazione"
L.KEY_TIP = "Il tasto che raccoglie, coglie o usa l'oggetto evidenziato quando è a portata. È il tasto d'interazione del gioco: vale anche per i PNG e si cambia anche nelle assegnazioni tasti."
L.KEY_NONE = "Nessuno"
L.KEY_LISTEN = "Premi un tasto"
L.KEY_LISTEN_TIP = "Premi il tasto, il pulsante del mouse o la rotella da usare. Esc annulla."
L.KEY_TAKEN = "%s è già usato per “%s”. Premilo di nuovo per darlo all'interazione, o scegli un altro tasto."
L.TIP_KEY_SET = "Clic sinistro: scegli un tasto"
L.TIP_KEY_CLEAR = "Clic destro: rimuovi il tasto"

L.LANGUAGE = "Lingua"
L.LANGUAGE_TIP = "La lingua dei testi e dei comandi di Lueur."
L.LANGUAGE_AUTO = "Automatica"
L.LANGUAGE_AUTO_TIP = "Segue la lingua del gioco."

L.ENABLE = "Attiva Lueur"
L.ENABLE_TIP = "Se disattivato, Lueur rende al gioco le tue impostazioni di mira."
L.MINIMAP = "Pulsante minimappa"
L.MINIMAP_TIP = "Mostra il pulsante di Lueur sul bordo della minimappa."
L.DEBUG = "Diagnostica in chat"
L.DEBUG_TIP = "Descrive in chat ogni oggetto mirato e ciò che Lueur ne deduce."

-- alternance des deux pistages
L.HEADER_SWITCH = "Due professioni di raccolta"
L.NODE_SWITCH = "Alterna i tracciamenti"
L.NODE_SWITCH_TIP = "Il gioco mostra i punti di Individuazione Erbe o di Individuazione Minerali, mai entrambi. Lueur attiva l'altro ogni volta che ti sei spostato abbastanza. Ogni personaggio ha la sua."
L.NODE_SWITCH_YARDS = "Distanza tra due cambi"
L.NODE_SWITCH_YARDS_TIP = "Quanto percorri prima che Lueur attivi l'altro tracciamento."

L.PREVIEW_NO_MODEL = "Modello 3D non disponibile qui"
L.PREVIEW_HINT = "Trascina: ruota  ·  clic destro: sposta  ·  rotella: zoom"
L.HEADER_PROFILE = "Profilo"
L.HEADER_PROFILE_TIP = "Un insieme di impostazioni di effetto, rilevamento e occultamento, con un nome. Ogni personaggio usa il profilo scelto qui."
L.PROFILE_DEFAULT = "Predefinito"
L.PROFILE_NEW = "Nuovo"
L.PROFILE_NEW_TIP = "Crea un profilo con le impostazioni originali e lo dà a questo personaggio."
L.PROFILE_COPY = "Copia"
L.PROFILE_COPY_TIP = "Crea un profilo con le impostazioni di questo e lo dà a questo personaggio."
L.PROFILE_RENAME = "Rinomina"
L.PROFILE_RENAME_TIP = "Dà un altro nome al profilo."
L.PROFILE_DELETE = "Elimina"
L.PROFILE_DELETE_TIP = "Elimina questo profilo. I personaggi che lo usavano tornano al primo. Un secondo clic conferma."
L.PROFILE_OK = "OK"
L.PROFILE_CANCEL = "Annulla"
L.DEFAULTS = "Predefiniti"
L.DEFAULTS_TIP = "Riporta effetto e rilevamento ai valori originali. Un secondo clic conferma."
L.FOOTER = "Lueur %s  ·  /lueur help: tutti i comandi"

L.OPTIONS_NOTE = "Fa brillare vene, erbe, oggetti di missione e forzieri quando ti avvicini."
L.OPTIONS_OPEN = "Apri le opzioni di Lueur"

L.TIP_ENABLED = "Attivo"
L.TIP_DISABLED = "Disattivo"
L.TIP_LEFT_CLICK = "Clic sinistro: apri le opzioni"
L.TIP_RIGHT_CLICK = "Clic destro: attiva o disattiva"
L.TIP_DRAG = "Trascina: sposta il pulsante"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "attivato."
L.MSG_DISABLED = "disattivato, le tue impostazioni originali sono ripristinate."
L.MSG_RESTART = "riavvia del tutto il gioco per completare l'aggiornamento di Lueur."
L.MSG_EXCLUSIVE_ON = "il gioco non segnala più i bersagli senza effetto."
L.MSG_EXCLUSIVE_OFF = "il gioco mostra nome e icona di ogni bersaglio d'interazione (PNG, oggetti del mondo…)."
L.MSG_SILHOUETTE_ON = "l'effetto passa dietro al tuo personaggio."
L.MSG_SILHOUETTE_OFF = "l'effetto copre il tuo personaggio."
L.MSG_CUTOUT_UNAVAILABLE = "ritaglio non disponibile: %s."
L.MSG_ZONE_SHOWN = "ritaglio tracciato in rosso: deve aderire al tuo personaggio."
L.MSG_ZONE_HIDDEN = "contorno del ritaglio nascosto."
L.MSG_SILHOUETTE_VALUES = "silhouette: dimensione %d%%, altezza %d%%"
L.MSG_SILHOUETTE_USAGE = "uso: /lueur silhouette | show | <dimensione {bodyScale}> [altezza {bodyShift}]"
L.MSG_EFFECTS = "effetti disponibili: %s (attuale: %s)"
L.MSG_FONTS = "font disponibili: %s (attuale: %s)"
L.MSG_COLOR_TWO = "%s: colori %s e %s"
L.MSG_COLOR = "%s: colore %s"
L.MSG_NO_PICKER = "questo client non ha un selettore di colori: scrivi /lueur color <categoria> <rrggbb>."
L.MSG_SHARED = "%s: di nuovo effetto e aspetto di tutti gli oggetti."
L.MSG_HIDE_COMBAT = "effetto nascosto in combattimento: %s"
L.MSG_HIDE_INSTANCE = "effetto nascosto in istanza: %s"
L.MSG_HIDE_LOCKED = "effetto nascosto sugli oggetti indisponibili: %s"
L.MSG_HIDE_UNTRAINED = "effetto nascosto su erbe e vene senza professione: %s"
L.MSG_GLOW_ONLY = "solo luce, la nameplate lasciata al gioco o a un altro addon: %s"
L.MSG_IGNORED = "%s non riceverà più alcun effetto."
L.MSG_UNIGNORED = "%s non è più ignorato."
L.MSG_IGNORED_ALREADY = "%s è già ignorato, come ogni oggetto con quel nome. Chiedilo di nuovo per non ignorarlo più."
L.MSG_IGNORE_NO_TARGET = "nessun oggetto davanti a te da ignorare."
L.MSG_IGNORE_LIST = "oggetti ignorati: %s"
L.MSG_IGNORE_EMPTY = "nessun oggetto è ignorato."
L.MSG_RANGE = "portata: %d m"
L.MSG_RANGE_COMBAT = "portata: %d m, applicata a fine combattimento."
L.MSG_RANGE_CLIENT = "portata: %d m richiesti, il client ha tenuto %s."
L.MSG_KEY_COMBAT = "le assegnazioni tasti non si cambiano in combattimento."
L.MSG_KEY_REFUSED = "il gioco ha rifiutato il tasto “%s”."
L.MSG_KEY_REPLACED = "%s non attiva più “%s”."

L.FAIL_NO_MASK = "questo client non supporta le maschere"
L.FAIL_MASK_TEXTURE = "texture della maschera non trovata (riavvia del tutto il gioco)"
L.FAIL_MASK_REFUSED = "maschera rifiutata dal client"

L.STATUS_CLIENT = "client %s (%s), lingua %s; testi di Lueur: %s. Valori effettivi:"
L.STATUS_CVAR_UNKNOWN = "sconosciuta a questo client"
L.STATUS_CVAR_DEFAULT = " (predefinito %s)"
L.STATUS_EXPECTED = "atteso da Lueur: portata %d, arco %d"
L.STATUS_GATE = "solo i bersagli evidenziati sono segnalati: %s | visualizzazione nativa ora: %s"
L.STATUS_GLOW_ONLY = "solo luce: %s | nome del bersaglio di Plumber: %s"
L.GATE_OPEN = "aperto"
L.GATE_CLOSED = "chiuso"
L.STATUS_SILHOUETTE = "effetto dietro al personaggio: %s"
L.STATUS_UNAVAILABLE = "non disponibile, %s"
L.STATUS_DIRECT = "bersaglio letto direttamente da “softinteract”: %s"
L.STATUS_NOT_YET = "non ancora visto"
L.STATUS_RANGE_API = "portata d'interazione leggibile: %s"
L.STATUS_LINE = "lenza in acqua: %s | canalizzazione in corso: %s"
L.STATUS_HIDE = "nascosto in combattimento: %s | in istanza: %s | sugli oggetti indisponibili: %s | in pausa ora: %s"
L.STATUS_SWITCH = "tracciamenti alternati: %s | disponibile: %s"
L.MSG_PROFILES = "profili: %s. Questo personaggio usa: %s."
L.MSG_PROFILE_UNNAMED = "al profilo serve un nome."
L.MSG_PROFILE_TAKEN = "un altro profilo si chiama già %s."
L.STATUS_PROFILE = "profilo: %s | profili: %d"
L.STATUS_COST = "CPU dall'ultimo status: bersaglio %d chiamate, %.3f ms ciascuna (la più lunga %.2f) | animazione %d fotogrammi, %.3f ms ciascuno (il più lungo %.2f)"
L.STATUS_TRAINED = "nessun effetto su erbe e vene senza professione: %s | erbalismo: %s, estrazione: %s"
L.STATUS_OBJECTS = "categorie mostrate su questo personaggio: %s | oggetti ignorati: %d"
L.STATUS_OWN = "categorie con impostazioni proprie: %s"
L.STATUS_EFFECT = "effetto: %s | texture: %s"
L.STATUS_KEY = "tasto d'interazione: %s"
L.TEXTURES_PENDING = "non ancora caricate"
L.TEXTURES_MISSING = "mancanti, effetto di riserva mostrato (riavvia del tutto il gioco)"
L.TEXTURES_LOADED = "caricate"

L.OBJECTIVES_HEADER = "%d obiettivo/i di missione in corso:"
L.OBJECTIVES_NOT_ITEM = "  (non è un oggetto: confrontato solo col nome intero)"
L.OBJECTIVES_LEARNED = "appreso da un tooltip: %s (%s)"


---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "nessun bersaglio d'interazione"
L.DEBUG_PAUSED = "in pausa (combattimento o istanza)"
L.DEBUG_LINE_OUT = "lenza in acqua: %d m richiesti, il client ha tenuto %s"
L.DEBUG_LINE_IN = "lenza ritirata: %d m richiesti, il client ha tenuto %s"
L.DEBUG_IGNORED = "%s ignorato (non è un oggetto del mondo)"
L.DEBUG_SKIPPED = "%s ignorato (nella tua lista di oggetti ignorati)"
L.DEBUG_HIDDEN = "%s → %s, nessun effetto (categoria nascosta o sconosciuta)"
L.DEBUG_UNTRAINED = "%s → %s, nessun effetto (questo personaggio non ha la professione)"
L.DEBUG_NO_PLATE = "%s → %s, rilevato ma senza nameplate: nessun effetto possibile"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "cursore: %s"
L.DEBUG_VIA = "bersaglio: %s"
L.VIA_DIRECT = "diretto"
L.VIA_SWEEP = "scansione"
L.DEBUG_RANGE = "a portata d'interazione: %s"
L.DEBUG_OBJECT = "ID oggetto: %s"
L.DEBUG_FISHING = "pesca in corso: %s"
L.DEBUG_QUEST = "legato a una missione: %s"
L.DEBUG_MATCH = "legato a un obiettivo da: %s (%d obiettivi in corso)"
L.MATCH_NONE = "niente"
L.MATCH_CURSOR = "niente, il cursore dice cos'è"
L.MATCH_TOOLTIP = "il suo tooltip"
L.MATCH_NAME = "il suo nome"
L.MATCH_WORD = "la parola “%s”"
L.MATCH_LOOT = "il suo bottino, già preso una volta"
L.DEBUG_CHEST = "riconosciuto come contenitore da: %s"
L.DEBUG_SECRET = "identità segreta: %s"
L.DEBUG_BEHIND = "dietro la telecamera: %s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "comandi:"
L.HELP = {
	"/lueur — apre o chiude la finestra delle opzioni (come un clic sul pulsante della minimappa)",
	"/lueur minimap — mostra o nasconde il pulsante della minimappa",
	"/lueur on | off — attiva o disattiva Lueur (off ripristina le tue impostazioni)",
	"/lueur preview — apre la finestra delle opzioni sull'anteprima, che mostra l'effetto su un oggetto 3D",
	"/lueur effect [categoria] <nome> — dà questo effetto a tutte le categorie, o a una sola (ore, herb, quest, chest, bobber, other); senza nome, li elenca",
	"/lueur color <categoria> <rrggbb> [<rrggbb>] | swap | default — colore dell'effetto di una categoria, e secondo colore per linee sottili e scintille; swap li scambia; senza colore, li mostra",
	"/lueur shared <categoria> — ridà a una categoria effetto e aspetto di tutti gli oggetti",
	"/lueur size [categoria] <{size}> — dimensione dell'effetto (predefinito {size=})",
	"/lueur intensity [categoria] <{intensity}> — luminosità dell'effetto, in % (predefinito {intensity=})",
	"/lueur offset [categoria] <{offsetY}> — scarto verticale dell'effetto (predefinito {offsetY=})",
	"/lueur fade [categoria] — se l'effetto svanisce con la nameplate (oggetto coperto dallo scenario)",
	"/lueur name | icon [categoria] — se il nome dell'oggetto, o la sua icona, appare sopra di esso; text [categoria] <{textSize}> imposta la dimensione del nome, in % (predefinito {textSize=})",
	"/lueur font [categoria] <nome> | default — font del nome dell'oggetto; senza nome, li elenca",
	"/lueur silhouette [categoria] — se l'effetto passa dietro al tuo personaggio invece di coprirlo",
	"/lueur silhouette show | <dimensione %> [altezza %] — mostra e regola il ritaglio",
	"/lueur range <{range}> — fino a che distanza il gioco sceglie gli oggetti, in metri (predefinito {range=})",
	"/lueur arc <{arc}> — 0 dritto, 1 davanti, 2 ogni direzione (predefinito {arc=})",
	"/lueur exclusive — se il gioco segnala solo i bersagli che ricevono un effetto",
	"/lueur glowonly — se Lueur disegna solo la luce, lasciando la nameplate del bersaglio (nome, icona) al gioco o a un altro addon",
	"/lueur combat | instance | unavailable | profession — se l'effetto si nasconde in combattimento, in istanza, sugli oggetti indisponibili, su erbe e vene senza professione",
	"/lueur key <TASTO> | none — assegna il tasto che raccoglie l'oggetto evidenziato (F, SHIFT-E, BUTTON4…); senza tasto, lo mostra",
	"/lueur ore | herb | quest | chest | bobber | other — mostra o nasconde una categoria, per questo personaggio",
	"/lueur profile [<nome>] — elenca i profili, o dà a questo personaggio quello con quel nome",
	"/lueur switch [<{nodeSwitchYards}>] — con entrambe le professioni di raccolta: alterna Individuazione Erbe e Individuazione Minerali mentre ti sposti; un numero imposta la distanza tra due cambi, in metri (predefinito {nodeSwitchYards=})",
	"/lueur ignore — ignora l'oggetto che hai davanti e quelli con lo stesso nome (due volte su un oggetto ignorato: smette di ignorarlo); ignore list, ignore clear, ignore <nome>",
	"/lueur language <auto | de | en | es | fr | it | ko | pt | ru | zhCN | zhTW> — lingua dei testi e dei comandi di Lueur",
	"/lueur debug — descrive ogni oggetto mirato e ciò che Lueur ne deduce",
	"/lueur objectives — elenca gli obiettivi di missione a cui sono confrontati i nomi degli oggetti",
	"/lueur status — mostra i valori realmente applicati dal client",
	"/lueur help — mostra questa lista",
}
