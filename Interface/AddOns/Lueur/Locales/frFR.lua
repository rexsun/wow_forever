-- Lueur : textes en français

local _, ns = ...

local L = {}
ns.LOCALES.frFR = L

L.LANGUAGE_NAME = "Français"
L.PREFIX = "|cffffd200Lueur|r : "
L.YES = "oui"
L.NO = "non"
L.SETTING = "%s : %s"
L.FORMAT_PERCENT = "%d %%"
L.FORMAT_RANGE = "%d m"
L.CONFIRM = "Confirmer ?"

L.COMMANDS = {
	commun = "shared",
	["aperçu"] = "preview", effet = "effect", couleur = "color", ["défaut"] = "default", taille = "size",
	["intensité"] = "intensity", ["décalage"] = "offset", fondu = "fade", nom = "name", ["icône"] = "icon", texte = "text", police = "font", montrer = "show",
	["portée"] = "range", exclusif = "exclusive", indisponible = "unavailable", ["métier"] = "profession", minerai = "ore", herbe = "herb",
	["quête"] = "quest", coffre = "chest", flotteur = "bobber", autre = "other", ignorer = "ignore", liste = "list", vider = "clear",
	objectifs = "objectives", ["état"] = "status", aide = "help", touche = "key", aucune = "none", langue = "language",
	ressources = "nodes", alterner = "switch", balayage = "scan", bordure = "ring",
	seule = "glowonly",
}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Minerais"
L.CATEGORY_ORE_TIP = "Filons de minerai."
L.CATEGORY_HERB = "Herbes"
L.CATEGORY_HERB_TIP = "Plantes à cueillir."
L.CATEGORY_QUEST = "Quêtes"
L.CATEGORY_QUEST_TIP = "Objets liés à l'une de tes quêtes en cours."
L.CATEGORY_CHEST = "Coffres"
L.CATEGORY_CHEST_TIP = "Coffres, caisses et autres contenants à fouiller."
L.CATEGORY_BOBBER = "Flotteur"
L.CATEGORY_BOBBER_TIP = "Le flotteur de ta ligne de pêche."
L.CATEGORY_OTHER = "Autres objets"
L.CATEGORY_OTHER_TIP = "Objets du quotidien : portes, boîtes aux lettres, leviers…"

L.NAME_ORE = "minerai"
L.NAME_HERB = "herbe"
L.NAME_QUEST = "quête"
L.NAME_CHEST = "coffre"
L.NAME_BOBBER = "flotteur"
L.NAME_OTHER = "autre"
L.NAME_NONE = "aucune"

L.SAMPLE_ORE = "Filon de cuivre"
L.SAMPLE_HERB = "Pacifique"
L.SAMPLE_QUEST = "Caisse de ravitaillement"
L.SAMPLE_CHEST = "Coffre cabossé"
L.SAMPLE_BOBBER = "Flotteur"
L.SAMPLE_OTHER = "Boîte aux lettres"

L.STATE_FAR = "hors de portée"
L.STATE_READY = "à portée"
L.STATE_LOCKED = "indisponible"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "Un halo de lumière et ses volutes, son anneau, ses comètes et ses lucioles."
L.EFFECT_SUBTLE = "Discret"
L.EFFECT_SUBTLE_TIP = "Une lueur douce, sans anneau ni comètes."
L.EFFECT_SIGIL = "Sceau"
L.EFFECT_SIGIL_TIP = "Un cercle de runes tourne lentement autour de l'objet."
L.EFFECT_VORTEX = "Tourbillon"
L.EFFECT_VORTEX_TIP = "Des bras de lumière s'enroulent autour de l'objet, comme un portail qui s'ouvre."
L.EFFECT_FLAME = "Flamme"
L.EFFECT_FLAME_TIP = "Des langues de feu montent de l'objet, dans sa couleur."
L.EFFECT_RIFT = "Faille"
L.EFFECT_RIFT_TIP = "Un trou noir cerclé de lumière aspire des éclats en spirale."
L.EFFECT_STORM = "Foudre"
L.EFFECT_STORM_TIP = "Un nuage d'orage se forme au-dessus de l'objet, et la foudre en tombe sur lui."
L.EFFECT_GEYSER = "Geyser"
L.EFFECT_GEYSER_TIP = "Une fontaine de lumière jaillit de l'objet et retombe autour de lui."
L.EFFECT_SPIRIT = "Esprit"
L.EFFECT_SPIRIT_TIP = "Deux feux follets dansent autour de l'objet en traînant un ruban de lumière."
L.EFFECT_BEAM = "Faisceau"
L.EFFECT_BEAM_TIP = "Une colonne de lumière s'élève de l'objet, parcourue d'étincelles."
L.EFFECT_BEACON = "Balise"
L.EFFECT_BEACON_TIP = "Un cristal flotte au-dessus de l'objet, relié à lui par un fil de lumière."
L.EFFECT_ORBIT = "Orbite"
L.EFFECT_ORBIT_TIP = "Trois feux follets tournent autour de l'objet, chacun sur son orbite."
L.EFFECT_RIPPLE = "Onde"
L.EFFECT_RIPPLE_TIP = "Des ondes s'étalent sur le sol autour de l'objet."
L.EFFECT_SPARKLE = "Étincelles"
L.EFFECT_SPARKLE_TIP = "Des éclats scintillent autour de l'objet, sans aucun cercle."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silhouette"
L.HEADER_OBJECTS = "Objets mis en lumière"
L.HEADER_HIDE = "Masquer l'effet"
L.HEADER_DETECTION = "Détection"
L.HEADER_GENERAL = "Général"
L.SETTINGS = "Réglages"

L.SCOPE_ALL = "Tous"
L.SCOPE_ALL_TIP = "Ce que tu règles va à toutes les catégories. Celle qui avait sa propre valeur pour ce réglage la perd."
L.SCOPE_ONE_TIP = "Ce que tu règles ne va qu'à cette catégorie, qui le garde quoi que deviennent les autres."
L.EFFECT = "Effet"
L.EFFECT_TIP = "Le dessin de la lumière."
L.LOOK_OF_ALL = "Apparence de tous les objets"
L.LOOK_OF = "Apparence : %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "Comme tous les objets"
L.SHARED_TIP = "Retire à cette catégorie son effet et son apparence propres : elle reprend ceux de tous les objets."

L.SIZE = "Taille"
L.SIZE_TIP = "Taille de l'effet."
L.INTENSITY = "Intensité"
L.INTENSITY_TIP = "Luminosité de l'effet."
L.OFFSET = "Décalage vertical"
L.OFFSET_TIP = "Monte ou descend l'effet par rapport à la nameplate de l'objet. L'aperçu montre où il se pose."
L.FADE = "S'estompe avec la nameplate"
L.FADE_TIP = "L'effet s'efface en même temps que la nameplate de l'objet, par exemple quand le décor le masque."

L.SILHOUETTE = "Passe derrière mon personnage"
L.SILHOUETTE_TIP = "L'effet est découpé autour de ton personnage, et semble passer derrière lui au lieu de le recouvrir."
L.ZONE_SIZE = "Taille de la zone découpée"
L.ZONE_SIZE_TIP = "À agrandir si l'effet mord sur ton personnage, à réduire s'il s'en tient trop loin. Chaque personnage garde la sienne."
L.ZONE_HEIGHT = "Hauteur de la zone découpée"
L.ZONE_HEIGHT_TIP = "Monte ou descend la zone découpée. Chaque personnage garde la sienne."
L.ZONE_SHOW = "Montrer la zone découpée"
L.ZONE_SHOW_TIP = "Trace en rouge le contour de la zone découpée : il doit épouser ton personnage. Disparaît à la fermeture de cette fenêtre."

L.SHOW_NAME = "Afficher le nom"
L.SHOW_NAME_TIP = "Écrit au-dessus de l'objet son nom, à la place de celui qu'écrit le jeu."
L.SHOW_ICON = "Afficher l'icône"
L.SHOW_ICON_TIP = "Affiche au-dessus de l'objet son icône d'interaction, à la place de celle que dessine le jeu."
L.TEXT_SIZE = "Taille du texte"
L.TEXT_SIZE_TIP = "Taille du nom écrit au-dessus de l'objet, par rapport au texte du jeu."
L.FONT = "Police"
L.FONT_TIP = "Police du nom écrit au-dessus de l'objet."
L.FONT_GAME = "Police du jeu"
L.COLOR = "Couleur"
L.COLOR_TIP = "La couleur de l'effet sur ces objets."
L.TIP_COLOR_SET = "Clic gauche : choisir une couleur"
L.TIP_COLOR_RESET = "Clic droit : revenir à la couleur d'origine"
L.IGNORED = "Objets ignorés : %d"
L.IGNORED_TIP = "Objets qui ne reçoivent jamais d'effet, quelle que soit leur catégorie. /lueur ignorer liste les nomme, /lueur ignorer vider les oublie tous."
L.IGNORE_TARGET = "Ignorer la cible"
L.IGNORE_TARGET_TIP = "Ignore l'objet qui se trouve devant toi en ce moment, ou cesse de l'ignorer."

L.HIDE_COMBAT = "En combat"
L.HIDE_COMBAT_TIP = "Pas d'effet tant que tu es en combat."
L.HIDE_INSTANCE = "En instance"
L.HIDE_INSTANCE_TIP = "Pas d'effet en donjon, en raid ni en champ de bataille."
L.HIDE_LOCKED = "Sur un objet indisponible"
L.HIDE_LOCKED_TIP = "L'effet s'éteint sur un objet que le jeu refuse pour l'instant : compétence trop faible, objet verrouillé… Le jeu ne le dit qu'une fois l'objet à portée."
L.HIDE_UNTRAINED = "Plantes et filons sans le métier"
L.HIDE_UNTRAINED_TIP = "Pas d'effet sur les plantes si ce personnage n'a pas l'Herboristerie, ni sur les filons sans le Minage."

L.RANGE = "Portée"
L.RANGE_TIP = "Distance jusqu'à laquelle le jeu peut désigner un objet à mettre en lumière."
L.DIRECTION = "Direction"
L.DIRECTION_TIP = "Où le jeu cherche l'objet à désigner."
L.ARC_0 = "Pile devant"
L.ARC_0_TIP = "Seulement ce qui se trouve juste en face de toi."
L.ARC_1 = "Devant"
L.ARC_1_TIP = "Tout ce qui se trouve devant toi."
L.ARC_2 = "Partout"
L.ARC_2_TIP = "Dans toutes les directions, même dans ton dos."
L.EXCLUSIVE = "Ne montrer que les cibles éclairées"
L.EXCLUSIVE_TIP = "Le jeu ne signale plus les cibles d'interaction qui ne reçoivent pas d'effet : PNJ, boîtes aux lettres… Décoché, il affiche un nom et une icône sur chacune."
L.GLOW_ONLY = "Lueur seule"
L.GLOW_ONLY_TIP = "Lueur n'écrit plus le nom ni l'icône de l'objet, et laisse ce que le jeu ou un autre addon y montre. Toujours actif quand la nameplate Soft Target de Plumber l'est."

L.KEY = "Touche d'interaction"
L.KEY_TIP = "La touche qui ramasse, cueille ou active l'objet mis en lumière dès qu'il est à portée. C'est la touche d'interaction du jeu : elle sert aussi avec les PNJ, et se change également dans les raccourcis du jeu."
L.KEY_NONE = "Non assignée"
L.KEY_LISTEN = "Presse une touche"
L.KEY_LISTEN_TIP = "Appuie sur la touche, le bouton de souris ou le cran de molette à utiliser. Échap annule."
L.KEY_TAKEN = "%s sert déjà à « %s ». Appuie de nouveau dessus pour la donner à l'interaction, ou choisis une autre touche."
L.TIP_KEY_SET = "Clic gauche : choisir une touche"
L.TIP_KEY_CLEAR = "Clic droit : retirer la touche"

L.LANGUAGE = "Langue"
L.LANGUAGE_TIP = "La langue des textes et des commandes de Lueur."
L.LANGUAGE_AUTO = "Automatique"
L.LANGUAGE_AUTO_TIP = "Suit la langue du jeu."

L.ENABLE = "Activer Lueur"
L.ENABLE_TIP = "Désactivé, Lueur rend au jeu tes réglages de ciblage d'origine."
L.MINIMAP = "Bouton de la minimap"
L.MINIMAP_TIP = "Affiche le bouton de Lueur au bord de la minimap."
L.DEBUG = "Diagnostic dans la discussion"
L.DEBUG_TIP = "Décrit dans la fenêtre de discussion chaque objet ciblé et ce que Lueur en déduit."

L.NODES_PAGE = "Plantes et filons sur la minimap"
L.HEADER_NODES = "Icônes de la minimap"
L.HEADER_SWITCH = "Deux métiers de récolte"
L.NODE_HERBS = "Icônes des plantes"
L.NODE_HERBS_TIP = "Chaque plante que ton pistage pose sur la minimap y prend l'icône de cette plante, au lieu d'un simple point."
L.NODE_ORE = "Icônes des filons"
L.NODE_ORE_TIP = "Chaque filon que ton pistage pose sur la minimap y prend l'icône de son minerai, au lieu d'un simple point."
L.NODE_SIZE = "Taille des icônes"
L.NODE_SIZE_TIP = "Taille des icônes sur la minimap."
L.NODE_RING = "Épaisseur de l'anneau"
L.NODE_RING_TIP = "Épaisseur de l'anneau coloré autour de chaque icône, qui dit ce que vaut le nœud pour ta compétence. À 0 %, pas d'anneau."
L.NODE_COMBAT = "Lire la minimap en combat"
L.NODE_COMBAT_TIP = "Lueur continue de lire la minimap pendant un combat. Décoche pour la laisser tranquille jusqu'à la fin du combat."
L.HEADER_SCANNING = "Lecture de la minimap"
L.NODE_SCAN_YARDS = "Distance entre deux balayages"
L.NODE_SCAN_YARDS_TIP = "Distance parcourue avant que Lueur relise la minimap. Chaque balayage la cache un instant : plus espacés, elle se cache moins souvent, et les nouveaux nœuds apparaissent plus tard."
L.NODE_SWITCH = "Alterner les deux pistages"
L.NODE_SWITCH_TIP = "Le jeu montre les points des plantes ou ceux des minerais, jamais les deux. Lueur allume l'autre pistage chaque fois que tu t'es assez déplacé, et garde les icônes des deux sur la minimap. Chaque personnage a son réglage."
L.NODE_SWITCH_YARDS = "Distance entre deux bascules"
L.NODE_SWITCH_YARDS_TIP = "Distance que tu parcours avant que Lueur allume l'autre pistage."

L.PREVIEW_NO_MODEL = "Modèle 3D indisponible sur ce client"
L.PREVIEW_HINT = "Glisser : tourner  ·  clic droit : déplacer  ·  molette : zoomer"
L.DEFAULTS = "Par défaut"
L.DEFAULTS_TIP = "Remet les réglages de l'effet et de la détection à leurs valeurs d'origine. Un second clic le confirme."
L.FOOTER = "Lueur %s  ·  /lueur aide : toutes les commandes"

L.OPTIONS_NOTE = "Fait briller les filons, les plantes, les objets de quête et les coffres à ton approche."
L.OPTIONS_OPEN = "Ouvrir les réglages de Lueur"

L.TIP_ENABLED = "Activé"
L.TIP_DISABLED = "Désactivé"
L.TIP_LEFT_CLICK = "Clic gauche : ouvrir les réglages"
L.TIP_RIGHT_CLICK = "Clic droit : activer ou désactiver"
L.TIP_DRAG = "Glisser : déplacer ce bouton"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "activé."
L.MSG_DISABLED = "désactivé, tes réglages d'origine sont restaurés."
L.MSG_RESTART = "relance complètement le jeu pour terminer la mise à jour de Lueur."
L.MSG_NODES_OFF = "les icônes des plantes et des filons sur la minimap sont désormais désactivées par défaut, et cette mise à jour les a désactivées. Réactive-les dans les réglages (/lueur) ou avec /lueur nodes."
L.MSG_EXCLUSIVE_ON = "le jeu ne signale plus les cibles qui ne reçoivent pas d'effet."
L.MSG_EXCLUSIVE_OFF = "le jeu affiche le nom et l'icône de toutes les cibles d'interaction (PNJ, objets du décor…)."
L.MSG_SILHOUETTE_ON = "l'effet passe derrière ton personnage."
L.MSG_SILHOUETTE_OFF = "l'effet recouvre ton personnage."
L.MSG_CUTOUT_UNAVAILABLE = "découpe indisponible : %s."
L.MSG_ZONE_SHOWN = "zone découpée tracée en rouge : elle doit épouser ton personnage."
L.MSG_ZONE_HIDDEN = "contour de la zone découpée masqué."
L.MSG_SILHOUETTE_VALUES = "silhouette : taille %d %%, hauteur %d %%"
L.MSG_SILHOUETTE_USAGE = "usage : /lueur silhouette | montrer | <taille {bodyScale}> [hauteur {bodyShift}]"
L.MSG_EFFECTS = "effets disponibles : %s (actuel : %s)"
L.MSG_FONTS = "polices disponibles : %s (actuelle : %s)"
L.MSG_COLOR = "%s : couleur %s"
L.MSG_NO_PICKER = "ce client n'a pas de sélecteur de couleur : tape /lueur couleur <catégorie> <rrvvbb>."
L.MSG_SHARED = "%s : de nouveau l'effet et l'apparence de tous les objets."
L.MSG_HIDE_COMBAT = "effet masqué en combat : %s"
L.MSG_HIDE_INSTANCE = "effet masqué en instance : %s"
L.MSG_HIDE_LOCKED = "effet masqué sur les objets indisponibles : %s"
L.MSG_HIDE_UNTRAINED = "effet masqué sur les plantes et filons sans le métier : %s"
L.MSG_GLOW_ONLY = "lueur seule, la nameplate laissée au jeu ou à un autre addon : %s"
L.MSG_IGNORED = "%s ne recevra plus d'effet."
L.MSG_UNIGNORED = "%s n'est plus ignoré."
L.MSG_IGNORE_NO_TARGET = "aucun objet devant toi à ignorer."
L.MSG_IGNORE_LIST = "objets ignorés : %s"
L.MSG_IGNORE_EMPTY = "aucun objet n'est ignoré."
L.MSG_RANGE = "portée : %d m"
L.MSG_RANGE_COMBAT = "portée : %d m, appliquée à la sortie du combat."
L.MSG_RANGE_CLIENT = "portée : %d m demandés, le client a retenu %s."
L.MSG_KEY_COMBAT = "les raccourcis ne se changent pas en combat."
L.MSG_KEY_REFUSED = "le jeu a refusé la touche « %s »."
L.MSG_KEY_REPLACED = "%s ne sert plus à « %s »."
L.MSG_NODES_UNAVAILABLE = "icônes de la minimap indisponibles : %s."

L.FAIL_NO_MASK = "ce client ne gère pas les masques"
L.FAIL_MASK_TEXTURE = "texture du masque introuvable (relance complètement le jeu)"
L.FAIL_MASK_REFUSED = "masque refusé par le client"
L.FAIL_NO_SCAN = "ce client ne laisse pas un addon lire les points de la minimap"
L.FAIL_SCAN_ERROR = "le jeu a refusé le balayage de la minimap (/lueur balayage dit pourquoi)"

L.STATUS_CLIENT = "client %s (%s), langue %s ; textes de Lueur : %s. Valeurs effectives :"
L.STATUS_CVAR_UNKNOWN = "inconnue de ce client"
L.STATUS_CVAR_DEFAULT = " (défaut %s)"
L.STATUS_EXPECTED = "attendu par Lueur : portée %d, arc %d"
L.STATUS_GATE = "seules les cibles éclairées sont signalées : %s | affichage natif en ce moment : %s"
L.STATUS_GLOW_ONLY = "lueur seule : %s | nom de la cible de Plumber : %s"
L.GATE_OPEN = "ouvert"
L.GATE_CLOSED = "fermé"
L.STATUS_SILHOUETTE = "effet derrière le personnage : %s"
L.STATUS_UNAVAILABLE = "indisponible, %s"
L.STATUS_DIRECT = "cible lue directement via « softinteract » : %s"
L.STATUS_NOT_YET = "pas encore observé"
L.STATUS_RANGE_API = "portée d'interaction lisible : %s"
L.STATUS_LINE = "ligne de pêche à l'eau : %s | canalisation en cours : %s"
L.STATUS_NODES = "icônes de la minimap : %s"
L.STATUS_NODES_SHOWN = "plantes %s, filons %s, pistages alternés %s"
L.STATUS_HIDE = "masqué en combat : %s | en instance : %s | sur les objets indisponibles : %s | en pause en ce moment : %s"
L.STATUS_TRAINED = "pas d'effet sur les plantes et filons sans le métier : %s | herboristerie : %s, minage : %s"
L.STATUS_OBJECTS = "catégories affichées sur ce personnage : %s | objets ignorés : %d"
L.STATUS_OWN = "catégories aux réglages propres : %s"
L.STATUS_EFFECT = "effet : %s | textures : %s"
L.STATUS_KEY = "touche d'interaction : %s"
L.TEXTURES_PENDING = "pas encore chargées"
L.TEXTURES_MISSING = "introuvables, effet de secours affiché (relance complètement le jeu)"
L.TEXTURES_LOADED = "chargées"

L.OBJECTIVES_HEADER = "%d objectif(s) de quête en cours :"
L.OBJECTIVES_NOT_ITEM = "  (pas un objet : comparé au nom entier seulement)"
L.OBJECTIVES_LEARNED = "appris d'une infobulle : %s (%s)"

L.SCAN_HEADER = "balayage de la minimap : %s"
L.SCAN_READY = "disponible"
L.SCAN_TRACKING = "pistages de récolte : %s"
L.SCAN_SKILL = "compétence lue : herboristerie %s, minage %s"
L.SCAN_VIEW = "rayon de la minimap : %s m | elle tourne avec toi : %s | position connue sur la carte : %s | un point répond à %s unités"
L.SCAN_TWICE = "un nom écrit deux fois là où deux points se recouvrent : %s"
L.SCAN_PLACED = "icônes : %d placées exactement, %d dans un groupe, %d à peu près, %d gardées du pistage éteint, %d non retrouvées | dernier balayage : %d points en %.2f s, %d groupe(s) regardé(s) de près"
L.SCAN_NODE = "%s : %s, répond à %s unités, à (%+.0f, %+.0f) du centre de la minimap"
L.SCAN_HOW_EXACT = "placée exactement"
L.SCAN_HOW_CLUSTER = "dans un groupe"
L.SCAN_HOW_ROUGH = "à peu près"
L.SCAN_HOW_HELD = "gardée du pistage éteint"
L.SCAN_HOW_MISSED = "non retrouvée"
L.SCAN_FOUND = "%d nom(s) lu(s) au dernier balayage, %d icône(s) :"
L.SCAN_NOT_NODE = "ni une plante ni un filon que Lueur connaît"
L.SCAN_NEEDS = ", demande %d"
L.SCAN_CAVE = ", dans une grotte"
L.SCAN_VIGNETTES = "vignettes que le jeu liste : %s"
L.SCAN_DATA = "données du point sous le pointeur, hors son texte : %s"
L.SCAN_POINTER = "sous le pointeur : %s"
L.SCAN_READER = "minimap sous la souris | dernier balayage : %d images, %d points de grille%s, %d nœuds connus vérifiés, %d groupes mesurés, %d points reposés | interrompu %d fois, la dernière : %s | en attente de : %s | opacité remise à 0 après qu'un autre code l'a changée : %d fois"
L.SCAN_HIDE = "cachée par son %s | forme : %s | %d de ses cadres cachés avec elle, %d remontrés entre-temps et cachés de nouveau"
L.SCAN_BY_MASK = "masque"
L.SCAN_BY_ALPHA = "opacité"
L.SCAN_FULL = " (toute la minimap)"
L.SCAN_SOON = "la minimap sera balayée dès qu'elle pourra passer sous la souris"
L.SCAN_BUSY = "un balayage de la minimap est en cours"
L.SCAN_WHY_COMBAT = "le combat"
L.SCAN_WHY_HIDDEN = "la minimap cachée"
L.SCAN_WHY_POINTER = "la souris sur la minimap"
L.SCAN_WHY_CAMERA = "la caméra tournée à la souris"
L.SCAN_WHY_WINDOW = "la souris sur une fenêtre"
L.SCAN_WHY_ZOOM = "le zoom de la minimap"
L.SCAN_WHY_TURN = "la minimap tournée"
L.SCAN_WHY_MAP = "une autre carte"
L.SCAN_WHY_TAXI = "un vol"
L.SCAN_WHY_NPC = "une fenêtre de PNJ ouverte"
L.SCAN_NOTHING = "rien (pose le pointeur sur un point de la minimap et retape la commande)"

---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "plus de cible d'interaction"
L.DEBUG_PAUSED = "en pause (combat ou instance)"
L.DEBUG_LINE_OUT = "ligne de pêche à l'eau : %d m demandés, le client a retenu %s"
L.DEBUG_LINE_IN = "ligne de pêche relevée : %d m demandés, le client a retenu %s"
L.DEBUG_IGNORED = "%s ignoré (pas un objet du décor)"
L.DEBUG_SKIPPED = "%s ignoré (dans ta liste d'objets ignorés)"
L.DEBUG_HIDDEN = "%s → %s, pas d'effet (catégorie masquée ou inconnue)"
L.DEBUG_UNTRAINED = "%s → %s, pas d'effet (ce personnage n'a pas le métier)"
L.DEBUG_NO_PLATE = "%s → %s, détecté mais sans nameplate : pas d'effet possible"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "curseur : %s"
L.DEBUG_VIA = "cible : %s"
L.VIA_DIRECT = "direct"
L.VIA_SWEEP = "balayage"
L.DEBUG_RANGE = "portée d'interaction : %s"
L.DEBUG_OBJECT = "objet n° %s"
L.DEBUG_FISHING = "pêche en cours : %s"
L.DEBUG_QUEST = "quête liée : %s"
L.DEBUG_MATCH = "rattaché à un objectif par : %s (%d objectifs en cours)"
L.MATCH_NONE = "rien"
L.MATCH_CURSOR = "rien, son curseur dit ce qu'il est"
L.MATCH_TOOLTIP = "son infobulle"
L.MATCH_NAME = "son nom"
L.MATCH_WORD = "le mot « %s »"
L.MATCH_LOOT = "son butin, déjà pris une fois"
L.DEBUG_CHEST = "reconnu comme contenant par : %s"
L.DEBUG_SECRET = "identité secrète : %s"
L.DEBUG_BEHIND = "derrière la caméra : %s"

---------------------------------------------------------------------------
-- Aide (/lueur aide)
---------------------------------------------------------------------------

L.HELP_HEADER = "commandes :"
L.HELP = {
	"/lueur — ouvre ou ferme la fenêtre des réglages (comme un clic sur le bouton de la minimap)",
	"/lueur minimap — affiche ou masque le bouton de la minimap",
	"/lueur on | off — active ou désactive Lueur (off restaure tes réglages)",
	"/lueur aperçu — ouvre la fenêtre des réglages sur l'aperçu, qui montre l'effet sur un objet en 3D",
	"/lueur effet [catégorie] <nom> — donne cet effet à toutes les catégories, ou à une seule (minerai, herbe, quête, coffre, flotteur, autre) ; sans nom, en donne la liste",
	"/lueur couleur <catégorie> <rrvvbb> | défaut — couleur de l'effet d'une catégorie ; sans couleur, l'affiche",
	"/lueur commun <catégorie> — rend à une catégorie l'effet et l'apparence de tous les objets",
	"/lueur taille [catégorie] <{size}> — taille de l'effet (défaut {size=})",
	"/lueur intensité [catégorie] <{intensity}> — luminosité de l'effet, en % (défaut {intensity=})",
	"/lueur décalage [catégorie] <{offsetY}> — décalage vertical de l'effet (défaut {offsetY=})",
	"/lueur fondu [catégorie] — l'effet s'estompe ou non avec la nameplate (objet masqué par le décor)",
	"/lueur nom | icône [catégorie] — affiche ou non le nom de l'objet, ou son icône, au-dessus de lui ; texte [catégorie] <{textSize}> règle la taille du nom, en % (défaut {textSize=})",
	"/lueur police [catégorie] <nom> | défaut — police du nom de l'objet ; sans nom, les liste",
	"/lueur silhouette [catégorie] — l'effet passe derrière ton personnage au lieu de le recouvrir, ou non",
	"/lueur silhouette montrer | <taille %> [hauteur %] — affiche et ajuste la zone découpée",
	"/lueur portée <{range}> — distance jusqu'à laquelle le jeu désigne un objet, en mètres (défaut {range=})",
	"/lueur arc <{arc}> — 0 pile devant, 1 devant, 2 toutes directions (défaut {arc=})",
	"/lueur exclusif — le jeu ne signale que les cibles qui reçoivent un effet, ou toutes",
	"/lueur seule — Lueur ne dessine que la lumière et laisse la nameplate de la cible (nom, icône) au jeu ou à un autre addon, ou non",
	"/lueur combat | instance | indisponible | métier — masque ou non l'effet en combat, en instance, sur les objets indisponibles, sur les plantes et filons sans le métier",
	"/lueur touche <TOUCHE> | aucune — assigne la touche qui ramasse l'objet mis en lumière (F, SHIFT-E, BUTTON4…) ; sans touche, l'affiche",
	"/lueur minerai | herbe | quête | coffre | flotteur | autre — affiche ou masque une catégorie, pour ce personnage",
	"/lueur ressources [minerai | herbe] — affiche ou masque sur la minimap les icônes des plantes et des filons ; ressources taille <{nodeSize}> règle leur taille (défaut {nodeSize=}) ; ressources bordure <{nodeRing}> règle l'épaisseur de leur anneau coloré, 0 pour aucun (défaut {nodeRing=}) ; ressources combat : si la minimap se lit en combat",
	"/lueur alterner [<{nodeSwitchYards}>] — avec les deux métiers de récolte : alterne le pistage des plantes et celui des minerais au fil de tes déplacements ; un nombre règle la distance entre deux bascules, en mètres (défaut {nodeSwitchYards=})",
	"/lueur balayage — affiche ce que le dernier balayage de la minimap a lu, et ce que Lueur en a fait ; balayage <{nodeScanYards}> règle l'espacement des balayages, en mètres (défaut {nodeScanYards=})",
	"/lueur ignorer — ignore l'objet qui se trouve devant toi, ou cesse de l'ignorer ; ignorer liste, ignorer vider, ignorer <nom>",
	"/lueur langue <auto | de | en | es | fr | ru> — langue des textes et des commandes de Lueur",
	"/lueur debug — décrit chaque objet ciblé et ce que Lueur en déduit",
	"/lueur objectifs — liste les objectifs de quête auxquels le nom des objets est comparé",
	"/lueur état — affiche les valeurs réellement appliquées par le client",
	"/lueur aide — affiche cette liste",
}
