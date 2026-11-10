-- Lueur : textes en espagnol (servent aussi aux clients esMX)

local _, ns = ...

local L = {}
ns.LOCALES.esES = L

L.LANGUAGE_NAME = "Español"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "sí"
L.NO = "no"
L.SETTING = "%s: %s"
L.FORMAT_PERCENT = "%d %%"
L.FORMAT_RANGE = "%d m"
L.CONFIRM = "¿Confirmar?"

L.COMMANDS = {
	["común"] = "shared",
	vista = "preview", efecto = "effect", original = "default", ["tamaño"] = "size",
	intensidad = "intensity", desplazamiento = "offset", desvanecer = "fade", nombre = "name", icono = "icon", texto = "text", fuente = "font", mostrar = "show",
	alcance = "range", exclusivo = "exclusive", combate = "combat", estancia = "instance", bloqueado = "unavailable", ["profesión"] = "profession",
	mineral = "ore", hierba = "herb", ["misión"] = "quest", cofre = "chest", corcho = "bobber", otro = "other", ignorar = "ignore",
	lista = "list", vaciar = "clear", objetivos = "objectives", estado = "status", ayuda = "help", tecla = "key",
	ninguna = "none", idioma = "language",
	recursos = "nodes", alternar = "switch", barrido = "scan", borde = "ring",
	sololuz = "glowonly",
}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Minerales"
L.CATEGORY_ORE_TIP = "Filones y vetas de mineral."
L.CATEGORY_HERB = "Hierbas"
L.CATEGORY_HERB_TIP = "Plantas que puedes recolectar."
L.CATEGORY_QUEST = "Misiones"
L.CATEGORY_QUEST_TIP = "Objetos ligados a una de tus misiones en curso."
L.CATEGORY_CHEST = "Cofres"
L.CATEGORY_CHEST_TIP = "Cofres, cajas y otros contenedores que puedes saquear."
L.CATEGORY_BOBBER = "Corcho de pesca"
L.CATEGORY_BOBBER_TIP = "El corcho de tu sedal de pesca."
L.CATEGORY_OTHER = "Otros objetos"
L.CATEGORY_OTHER_TIP = "Objetos cotidianos: puertas, buzones, palancas…"

L.NAME_ORE = "mineral"
L.NAME_HERB = "hierba"
L.NAME_QUEST = "misión"
L.NAME_CHEST = "cofre"
L.NAME_BOBBER = "corcho"
L.NAME_OTHER = "otro"
L.NAME_NONE = "ninguna"

L.SAMPLE_ORE = "Filón de cobre"
L.SAMPLE_HERB = "Flor de paz"
L.SAMPLE_QUEST = "Caja de suministros"
L.SAMPLE_CHEST = "Cofre maltrecho"
L.SAMPLE_BOBBER = "Corcho de pesca"
L.SAMPLE_OTHER = "Buzón"

L.STATE_FAR = "fuera de alcance"
L.STATE_READY = "al alcance"
L.STATE_LOCKED = "no disponible"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "Un halo de luz con sus volutas, un anillo, cometas y luciérnagas."
L.EFFECT_SUBTLE = "Discreto"
L.EFFECT_SUBTLE_TIP = "Un resplandor suave, sin anillo ni cometas."
L.EFFECT_SIGIL = "Sello"
L.EFFECT_SIGIL_TIP = "Un círculo de runas gira despacio alrededor del objeto."
L.EFFECT_VORTEX = "Vórtice"
L.EFFECT_VORTEX_TIP = "Brazos de luz se enroscan alrededor del objeto, como un portal que se abre."
L.EFFECT_FLAME = "Llama"
L.EFFECT_FLAME_TIP = "Lenguas de fuego se alzan del objeto, con su color."
L.EFFECT_RIFT = "Falla"
L.EFFECT_RIFT_TIP = "Un agujero negro rodeado de luz aspira destellos en espiral."
L.EFFECT_STORM = "Tormenta"
L.EFFECT_STORM_TIP = "Una nube de tormenta se forma sobre el objeto, y de ella caen los rayos."
L.EFFECT_GEYSER = "Géiser"
L.EFFECT_GEYSER_TIP = "Una fuente de luz brota del objeto y cae a su alrededor."
L.EFFECT_SPIRIT = "Espíritu"
L.EFFECT_SPIRIT_TIP = "Dos fuegos fatuos bailan alrededor del objeto arrastrando una cinta de luz."
L.EFFECT_BEAM = "Haz"
L.EFFECT_BEAM_TIP = "Una columna de luz se eleva del objeto, recorrida por chispas."
L.EFFECT_BEACON = "Baliza"
L.EFFECT_BEACON_TIP = "Un cristal flota sobre el objeto, unido a él por un hilo de luz."
L.EFFECT_ORBIT = "Órbita"
L.EFFECT_ORBIT_TIP = "Tres fuegos fatuos giran alrededor del objeto, cada uno en su órbita."
L.EFFECT_RIPPLE = "Onda"
L.EFFECT_RIPPLE_TIP = "Unas ondas se extienden por el suelo alrededor del objeto."
L.EFFECT_SPARKLE = "Destellos"
L.EFFECT_SPARKLE_TIP = "Unos destellos centellean alrededor del objeto, sin ningún círculo."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silueta"
L.HEADER_OBJECTS = "Objetos resaltados"
L.HEADER_HIDE = "Ocultar el efecto"
L.HEADER_DETECTION = "Detección"
L.HEADER_GENERAL = "General"
L.SETTINGS = "Ajustes"

L.SCOPE_ALL = "Todos"
L.SCOPE_ALL_TIP = "Lo que ajustes se aplica a todas las categorías. La que tenía su propio valor para ese ajuste lo pierde."
L.SCOPE_ONE_TIP = "Lo que ajustes se aplica solo a esta categoría, que lo conserva pase lo que pase con las demás."
L.EFFECT = "Efecto"
L.EFFECT_TIP = "La forma de la luz."
L.LOOK_OF_ALL = "Apariencia de todos los objetos"
L.LOOK_OF = "Apariencia: %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "Como todos los objetos"
L.SHARED_TIP = "Quita a esta categoría su efecto y su apariencia propios: vuelve a los de todos los objetos."

L.SIZE = "Tamaño"
L.SIZE_TIP = "El tamaño del efecto."
L.INTENSITY = "Intensidad"
L.INTENSITY_TIP = "El brillo del efecto."
L.OFFSET = "Desplazamiento vertical"
L.OFFSET_TIP = "Sube o baja el efecto respecto a la placa de nombre del objeto. La vista previa muestra dónde queda."
L.FADE = "Desvanecer con la placa de nombre"
L.FADE_TIP = "El efecto se desvanece junto con la placa de nombre del objeto, por ejemplo cuando el escenario lo tapa."

L.SILHOUETTE = "Pasar por detrás de mi personaje"
L.SILHOUETTE_TIP = "El efecto se recorta alrededor de tu personaje, de modo que parece pasar por detrás de ti en lugar de taparte."
L.ZONE_SIZE = "Tamaño del recorte"
L.ZONE_SIZE_TIP = "Auméntalo si el efecto muerde a tu personaje, redúcelo si se queda demasiado lejos. Cada personaje guarda el suyo."
L.ZONE_HEIGHT = "Altura del recorte"
L.ZONE_HEIGHT_TIP = "Sube o baja el recorte. Cada personaje guarda la suya."
L.ZONE_SHOW = "Mostrar el recorte"
L.ZONE_SHOW_TIP = "Dibuja en rojo el contorno del recorte: debe ceñirse a tu personaje. Desaparece al cerrar esta ventana."

L.SHOW_NAME = "Mostrar el nombre"
L.SHOW_NAME_TIP = "Escribe el nombre del objeto sobre él, en lugar del que escribe el juego."
L.SHOW_ICON = "Mostrar el icono"
L.SHOW_ICON_TIP = "Muestra el icono de interacción del objeto sobre él, en lugar del que dibuja el juego."
L.TEXT_SIZE = "Tamaño del texto"
L.TEXT_SIZE_TIP = "Tamaño del nombre escrito sobre el objeto, respecto al texto del juego."
L.FONT = "Fuente"
L.FONT_TIP = "Fuente del nombre escrito sobre el objeto."
L.FONT_GAME = "Fuente del juego"
L.COLOR = "Color"
L.COLOR_TIP = "El color del efecto en estos objetos."
L.TIP_COLOR_SET = "Clic izquierdo: elegir un color"
L.TIP_COLOR_RESET = "Clic derecho: volver al color original"
L.IGNORED = "Objetos ignorados: %d"
L.IGNORED_TIP = "Objetos que nunca reciben efecto, sea cual sea su categoría. /lueur ignorar lista los nombra, /lueur ignorar vaciar los olvida todos."
L.IGNORE_TARGET = "Ignorar objetivo"
L.IGNORE_TARGET_TIP = "Ignora el objeto que tienes delante ahora mismo, o deja de ignorarlo."

L.HIDE_COMBAT = "En combate"
L.HIDE_COMBAT_TIP = "Sin efecto mientras estés en combate."
L.HIDE_INSTANCE = "En estancias"
L.HIDE_INSTANCE_TIP = "Sin efecto en mazmorras, bandas y campos de batalla."
L.HIDE_LOCKED = "En objetos que no puedo usar"
L.HIDE_LOCKED_TIP = "El efecto se apaga en un objeto que el juego te niega por ahora: habilidad insuficiente, objeto cerrado… El juego solo lo indica cuando el objeto está al alcance."
L.HIDE_UNTRAINED = "Hierbas y minerales sin la profesión"
L.HIDE_UNTRAINED_TIP = "Sin efecto en las hierbas si este personaje no tiene Herboristería, ni en los minerales sin Minería."

L.RANGE = "Alcance"
L.RANGE_TIP = "Hasta qué distancia puede el juego elegir un objeto para resaltarlo."
L.DIRECTION = "Dirección"
L.DIRECTION_TIP = "Dónde busca el juego el objeto que elige."
L.ARC_0 = "Al frente"
L.ARC_0_TIP = "Solo lo que tienes justo enfrente."
L.ARC_1 = "Delante"
L.ARC_1_TIP = "Todo lo que tienes delante."
L.ARC_2 = "Alrededor"
L.ARC_2_TIP = "En todas las direcciones, incluso a tu espalda."
L.EXCLUSIVE = "Mostrar solo los objetivos resaltados"
L.EXCLUSIVE_TIP = "El juego deja de señalar los objetivos de interacción que no reciben efecto: PNJ, buzones… Sin marcar, muestra un nombre y un icono en cada uno de ellos."
L.GLOW_ONLY = "Solo el brillo"
L.GLOW_ONLY_TIP = "Lueur deja de escribir el nombre y el icono del objeto, y deja lo que el juego u otro addon muestra ahí. Siempre activo mientras la placa de nombre Soft Target de Plumber lo esté."

L.KEY = "Tecla de interacción"
L.KEY_TIP = "La tecla que recoge, recolecta o usa el objeto resaltado en cuanto está al alcance. Es la tecla de interacción del juego: también sirve con los PNJ y se puede cambiar igualmente en las teclas del juego."
L.KEY_NONE = "Sin asignar"
L.KEY_LISTEN = "Pulsa una tecla"
L.KEY_LISTEN_TIP = "Pulsa la tecla, el botón del ratón o el sentido de la rueda que quieras usar. Escape cancela."
L.KEY_TAKEN = "%s ya se usa para «%s». Púlsala otra vez para dársela a la interacción, o elige otra tecla."
L.TIP_KEY_SET = "Clic izquierdo: elegir una tecla"
L.TIP_KEY_CLEAR = "Clic derecho: quitar la tecla"

L.LANGUAGE = "Idioma"
L.LANGUAGE_TIP = "El idioma de los textos y comandos de Lueur."
L.LANGUAGE_AUTO = "Automático"
L.LANGUAGE_AUTO_TIP = "Sigue el idioma del juego."

L.ENABLE = "Activar Lueur"
L.ENABLE_TIP = "Desactivado, Lueur devuelve al juego tus ajustes de selección originales."
L.MINIMAP = "Botón del minimapa"
L.MINIMAP_TIP = "Muestra el botón de Lueur en el borde del minimapa."
L.DEBUG = "Diagnóstico en el chat"
L.DEBUG_TIP = "Describe en la ventana de chat cada objeto apuntado y lo que Lueur deduce de él."

L.NODES_PAGE = "Hierbas y filones en el minimapa"
L.HEADER_NODES = "Iconos del minimapa"
L.HEADER_SWITCH = "Dos profesiones de recolección"
L.NODE_HERBS = "Iconos de las hierbas"
L.NODE_HERBS_TIP = "Cada hierba que tu rastreo pone en el minimapa aparece con el icono de esa hierba, en lugar de un simple punto."
L.NODE_ORE = "Iconos de los filones"
L.NODE_ORE_TIP = "Cada filón que tu rastreo pone en el minimapa aparece con el icono de su mineral, en lugar de un simple punto."
L.NODE_SIZE = "Tamaño de los iconos"
L.NODE_SIZE_TIP = "Tamaño de los iconos en el minimapa."
L.NODE_RING = "Grosor del anillo"
L.NODE_RING_TIP = "Grosor del anillo de color alrededor de cada icono, que indica lo difícil que es el nodo para tu habilidad. Al 0 %, sin anillo."
L.NODE_COMBAT = "Leer el minimapa en combate"
L.NODE_COMBAT_TIP = "Lueur sigue leyendo el minimapa durante un combate. Desmárcalo para dejarlo tranquilo hasta que acabe."
L.HEADER_SCANNING = "Lectura del minimapa"
L.NODE_SCAN_YARDS = "Distancia entre escaneos"
L.NODE_SCAN_YARDS_TIP = "Distancia que recorres antes de que Lueur vuelva a leer el minimapa. Cada escaneo lo oculta un instante: más espaciados, se oculta menos y los nuevos nodos aparecen más tarde."
L.NODE_SWITCH = "Alternar los dos rastreos"
L.NODE_SWITCH_TIP = "El juego muestra los puntos de las hierbas o los de los minerales, nunca ambos. Lueur activa el otro rastreo cada vez que te has desplazado lo suficiente, y conserva los iconos de los dos en el minimapa. Cada personaje tiene su ajuste."
L.NODE_SWITCH_YARDS = "Distancia entre dos cambios"
L.NODE_SWITCH_YARDS_TIP = "Distancia que recorres antes de que Lueur active el otro rastreo."

L.PREVIEW_NO_MODEL = "Modelo 3D no disponible en este cliente"
L.PREVIEW_HINT = "Arrastrar: girar  ·  clic derecho: mover  ·  rueda: zoom"
L.DEFAULTS = "Por defecto"
L.DEFAULTS_TIP = "Devuelve los ajustes del efecto y de la detección a sus valores originales. Un segundo clic lo confirma."
L.FOOTER = "Lueur %s  ·  /lueur ayuda: todos los comandos"

L.OPTIONS_NOTE = "Hace brillar los filones, las hierbas, los objetos de misión y los cofres cuando te acercas."
L.OPTIONS_OPEN = "Abrir los ajustes de Lueur"

L.TIP_ENABLED = "Activado"
L.TIP_DISABLED = "Desactivado"
L.TIP_LEFT_CLICK = "Clic izquierdo: abrir los ajustes"
L.TIP_RIGHT_CLICK = "Clic derecho: activar o desactivar"
L.TIP_DRAG = "Arrastrar: mover este botón"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "activado."
L.MSG_DISABLED = "desactivado, tus ajustes originales quedan restaurados."
L.MSG_RESTART = "reinicia el juego por completo para terminar de actualizar Lueur."
L.MSG_NODES_OFF = "los iconos de hierbas y filones en el minimapa ahora están desactivados por defecto, y esta actualización los ha desactivado. Vuelve a activarlos en los ajustes (/lueur) o con /lueur nodes."
L.MSG_EXCLUSIVE_ON = "el juego deja de señalar los objetivos que no reciben efecto."
L.MSG_EXCLUSIVE_OFF = "el juego muestra el nombre y el icono de todos los objetivos de interacción (PNJ, objetos del mundo…)."
L.MSG_SILHOUETTE_ON = "el efecto pasa por detrás de tu personaje."
L.MSG_SILHOUETTE_OFF = "el efecto tapa a tu personaje."
L.MSG_CUTOUT_UNAVAILABLE = "recorte no disponible: %s."
L.MSG_ZONE_SHOWN = "recorte dibujado en rojo: debe ceñirse a tu personaje."
L.MSG_ZONE_HIDDEN = "contorno del recorte oculto."
L.MSG_SILHOUETTE_VALUES = "silueta: tamaño %d %%, altura %d %%"
L.MSG_SILHOUETTE_USAGE = "uso: /lueur silhouette | mostrar | <tamaño {bodyScale}> [altura {bodyShift}]"
L.MSG_EFFECTS = "efectos disponibles: %s (actual: %s)"
L.MSG_FONTS = "fuentes disponibles: %s (actual: %s)"
L.MSG_COLOR = "%s: color %s"
L.MSG_NO_PICKER = "este cliente no tiene selector de color: escribe /lueur color <categoría> <rrggbb>."
L.MSG_SHARED = "%s: de nuevo el efecto y la apariencia de todos los objetos."
L.MSG_HIDE_COMBAT = "efecto oculto en combate: %s"
L.MSG_HIDE_INSTANCE = "efecto oculto en estancias: %s"
L.MSG_HIDE_LOCKED = "efecto oculto en los objetos que no puedes usar: %s"
L.MSG_HIDE_UNTRAINED = "efecto oculto en hierbas y minerales sin la profesión: %s"
L.MSG_GLOW_ONLY = "solo el brillo, la placa de nombre queda para el juego u otro addon: %s"
L.MSG_IGNORED = "%s ya no recibirá efecto."
L.MSG_UNIGNORED = "%s deja de estar ignorado."
L.MSG_IGNORE_NO_TARGET = "no tienes delante ningún objeto que ignorar."
L.MSG_IGNORE_LIST = "objetos ignorados: %s"
L.MSG_IGNORE_EMPTY = "no hay ningún objeto ignorado."
L.MSG_RANGE = "alcance: %d m"
L.MSG_RANGE_COMBAT = "alcance: %d m, se aplicará al salir del combate."
L.MSG_RANGE_CLIENT = "alcance: %d m pedidos, el cliente se ha quedado con %s."
L.MSG_KEY_COMBAT = "las teclas no se pueden cambiar en combate."
L.MSG_KEY_REFUSED = "el juego ha rechazado la tecla «%s»."
L.MSG_KEY_REPLACED = "%s ya no sirve para «%s»."
L.MSG_NODES_UNAVAILABLE = "iconos del minimapa no disponibles: %s."

L.FAIL_NO_MASK = "este cliente no admite máscaras"
L.FAIL_MASK_TEXTURE = "no se encuentra la textura de la máscara (reinicia el juego por completo)"
L.FAIL_MASK_REFUSED = "el cliente ha rechazado la máscara"
L.FAIL_NO_SCAN = "este cliente no deja que un addon lea los puntos del minimapa"
L.FAIL_SCAN_ERROR = "el juego ha rechazado el barrido del minimapa (/lueur barrido dice por qué)"

L.STATUS_CLIENT = "cliente %s (%s), idioma %s; textos de Lueur: %s. Valores vigentes:"
L.STATUS_CVAR_UNKNOWN = "desconocida para este cliente"
L.STATUS_CVAR_DEFAULT = " (por defecto %s)"
L.STATUS_EXPECTED = "esperado por Lueur: alcance %d, arco %d"
L.STATUS_GATE = "solo se señalan los objetivos resaltados: %s | visualización nativa ahora mismo: %s"
L.STATUS_GLOW_ONLY = "solo el brillo: %s | nombre del objetivo de Plumber: %s"
L.GATE_OPEN = "abierta"
L.GATE_CLOSED = "cerrada"
L.STATUS_SILHOUETTE = "efecto por detrás del personaje: %s"
L.STATUS_UNAVAILABLE = "no disponible, %s"
L.STATUS_DIRECT = "objetivo leído directamente de «softinteract»: %s"
L.STATUS_NOT_YET = "aún no observado"
L.STATUS_RANGE_API = "alcance de interacción legible: %s"
L.STATUS_LINE = "sedal en el agua: %s | canalización en curso: %s"
L.STATUS_NODES = "iconos del minimapa: %s"
L.STATUS_NODES_SHOWN = "hierbas %s, filones %s, rastreos alternados %s"
L.STATUS_HIDE = "oculto en combate: %s | en estancias: %s | en objetos no disponibles: %s | en pausa ahora mismo: %s"
L.STATUS_TRAINED = "sin efecto en hierbas y minerales sin la profesión: %s | herboristería: %s, minería: %s"
L.STATUS_OBJECTS = "categorías mostradas en este personaje: %s | objetos ignorados: %d"
L.STATUS_OWN = "categorías con ajustes propios: %s"
L.STATUS_EFFECT = "efecto: %s | texturas: %s"
L.STATUS_KEY = "tecla de interacción: %s"
L.TEXTURES_PENDING = "aún sin cargar"
L.TEXTURES_MISSING = "no encontradas, se muestra el efecto de reserva (reinicia el juego por completo)"
L.TEXTURES_LOADED = "cargadas"

L.OBJECTIVES_HEADER = "%d objetivo(s) de misión en curso:"
L.OBJECTIVES_NOT_ITEM = "  (no es un objeto: solo se compara con el nombre entero)"
L.OBJECTIVES_LEARNED = "aprendido de una descripción emergente: %s (%s)"

L.SCAN_HEADER = "barrido del minimapa: %s"
L.SCAN_READY = "disponible"
L.SCAN_TRACKING = "rastreos de recolección: %s"
L.SCAN_SKILL = "habilidad leída: herboristería %s, minería %s"
L.SCAN_VIEW = "radio del minimapa: %s m | gira contigo: %s | posición conocida en el mapa: %s | un punto responde a %s unidades"
L.SCAN_TWICE = "un nombre escrito dos veces donde se solapan dos puntos: %s"
L.SCAN_PLACED = "iconos: %d colocados con exactitud, %d en un grupo, %d aproximados, %d conservados del rastreo apagado, %d no encontrados de nuevo | último barrido: %d puntos en %.2f s, %d grupo(s) mirado(s) de cerca"
L.SCAN_NODE = "%s: %s, responde a %s unidades, en (%+.0f, %+.0f) desde el centro del minimapa"
L.SCAN_HOW_EXACT = "colocado con exactitud"
L.SCAN_HOW_CLUSTER = "en un grupo"
L.SCAN_HOW_ROUGH = "aproximado"
L.SCAN_HOW_HELD = "conservado del rastreo apagado"
L.SCAN_HOW_MISSED = "no encontrado de nuevo"
L.SCAN_FOUND = "%d nombre(s) leído(s) en el último barrido, %d icono(s):"
L.SCAN_NOT_NODE = "ni una hierba ni un filón que Lueur conozca"
L.SCAN_NEEDS = ", requiere %d"
L.SCAN_CAVE = ", en una cueva"
L.SCAN_VIGNETTES = "viñetas que lista el juego: %s"
L.SCAN_DATA = "datos del punto bajo el puntero, aparte de su texto: %s"
L.SCAN_POINTER = "bajo el puntero: %s"
L.SCAN_READER = "minimapa bajo el ratón | último escaneo: %d fotogramas, %d puntos de cuadrícula%s, %d nodos conocidos comprobados, %d grupos medidos, %d puntos recolocados | interrumpido %d veces, la última: %s | esperando: %s | opacidad devuelta a 0 tras cambiarla otro código: %d veces"
L.SCAN_HIDE = "oculto por su %s | forma: %s | %d de sus marcos ocultos con él, %d mostrados de nuevo entretanto y ocultados otra vez"
L.SCAN_BY_MASK = "máscara"
L.SCAN_BY_ALPHA = "opacidad"
L.SCAN_FULL = " (todo el minimapa)"
L.SCAN_SOON = "el minimapa se escaneará en cuanto pueda pasar bajo el ratón"
L.SCAN_BUSY = "hay un escaneo del minimapa en curso"
L.SCAN_WHY_COMBAT = "combate"
L.SCAN_WHY_HIDDEN = "minimapa oculto"
L.SCAN_WHY_POINTER = "ratón sobre el minimapa"
L.SCAN_WHY_CAMERA = "cámara girada con el ratón"
L.SCAN_WHY_WINDOW = "ratón sobre una ventana"
L.SCAN_WHY_ZOOM = "zoom del minimapa"
L.SCAN_WHY_TURN = "minimapa girado"
L.SCAN_WHY_MAP = "otro mapa"
L.SCAN_WHY_TAXI = "un vuelo"
L.SCAN_WHY_NPC = "una ventana de PNJ abierta"
L.SCAN_NOTHING = "nada (pon el puntero sobre un punto del minimapa y vuelve a escribir el comando)"

---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "ya no hay objetivo de interacción"
L.DEBUG_PAUSED = "en pausa (combate o estancia)"
L.DEBUG_LINE_OUT = "sedal en el agua: %d m pedidos, el cliente se ha quedado con %s"
L.DEBUG_LINE_IN = "sedal recogido: %d m pedidos, el cliente se ha quedado con %s"
L.DEBUG_IGNORED = "%s ignorado (no es un objeto del mundo)"
L.DEBUG_SKIPPED = "%s ignorado (está en tu lista de objetos ignorados)"
L.DEBUG_HIDDEN = "%s → %s, sin efecto (categoría oculta o desconocida)"
L.DEBUG_UNTRAINED = "%s → %s, sin efecto (este personaje no tiene la profesión)"
L.DEBUG_NO_PLATE = "%s → %s, detectado pero sin placa de nombre: no hay efecto posible"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "cursor: %s"
L.DEBUG_VIA = "objetivo: %s"
L.VIA_DIRECT = "directo"
L.VIA_SWEEP = "barrido"
L.DEBUG_RANGE = "al alcance de interacción: %s"
L.DEBUG_OBJECT = "objeto n.º %s"
L.DEBUG_FISHING = "pescando: %s"
L.DEBUG_QUEST = "ligado a una misión: %s"
L.DEBUG_MATCH = "asociado a un objetivo por: %s (%d objetivos en curso)"
L.MATCH_NONE = "nada"
L.MATCH_CURSOR = "nada, su cursor dice lo que es"
L.MATCH_TOOLTIP = "su descripción emergente"
L.MATCH_NAME = "su nombre"
L.MATCH_WORD = "la palabra «%s»"
L.MATCH_LOOT = "su botín, ya recogido una vez"
L.DEBUG_CHEST = "reconocido como contenedor por: %s"
L.DEBUG_SECRET = "identidad secreta: %s"
L.DEBUG_BEHIND = "detrás de la cámara: %s"

---------------------------------------------------------------------------
-- Aide (/lueur ayuda)
---------------------------------------------------------------------------

L.HELP_HEADER = "comandos:"
L.HELP = {
	"/lueur — abre o cierra la ventana de ajustes (como un clic en el botón del minimapa)",
	"/lueur minimap — muestra u oculta el botón del minimapa",
	"/lueur on | off — activa o desactiva Lueur (off restaura tus ajustes)",
	"/lueur vista — abre la ventana de ajustes en la vista previa, que muestra el efecto sobre un objeto en 3D",
	"/lueur efecto [categoría] <nombre> — da este efecto a todas las categorías, o a una sola (mineral, hierba, misión, cofre, corcho, otro); sin nombre, los enumera",
	"/lueur color <categoría> <rrggbb> | original — color del efecto de una categoría; sin color, lo muestra",
	"/lueur común <categoría> — devuelve a una categoría el efecto y la apariencia de todos los objetos",
	"/lueur tamaño [categoría] <{size}> — tamaño del efecto (por defecto {size=})",
	"/lueur intensidad [categoría] <{intensity}> — brillo del efecto, en % (por defecto {intensity=})",
	"/lueur desplazamiento [categoría] <{offsetY}> — desplazamiento vertical del efecto (por defecto {offsetY=})",
	"/lueur desvanecer [categoría] — si el efecto se desvanece con la placa de nombre (objeto tapado por el escenario)",
	"/lueur nombre | icono [categoría] — si el nombre del objeto, o su icono, se muestra sobre él; texto [categoría] <{textSize}> ajusta el tamaño del nombre, en % (por defecto {textSize=})",
	"/lueur fuente [categoría] <nombre> | original — fuente del nombre del objeto; sin nombre, las enumera",
	"/lueur silhouette [categoría] — si el efecto pasa por detrás de tu personaje en lugar de taparlo",
	"/lueur silhouette mostrar | <tamaño %> [altura %] — muestra y ajusta el recorte",
	"/lueur alcance <{range}> — hasta dónde elige objetos el juego, en metros (por defecto {range=})",
	"/lueur arc <{arc}> — 0 justo delante, 1 delante, 2 todas las direcciones (por defecto {arc=})",
	"/lueur exclusivo — si el juego solo señala los objetivos que reciben efecto",
	"/lueur sololuz — si Lueur solo dibuja la luz y deja la placa de nombre del objetivo (nombre, icono) al juego o a otro addon",
	"/lueur combate | estancia | bloqueado | profesión — si el efecto se oculta en combate, en estancias, en objetos que no puedes usar, en hierbas y minerales sin la profesión",
	"/lueur tecla <TECLA> | ninguna — asigna la tecla que recoge el objeto resaltado (F, SHIFT-E, BUTTON4…); sin tecla, la muestra",
	"/lueur mineral | hierba | misión | cofre | corcho | otro — muestra u oculta una categoría, para este personaje",
	"/lueur recursos [mineral | hierba] — muestra u oculta en el minimapa los iconos de las hierbas y los filones; recursos tamaño <{nodeSize}> ajusta su tamaño (original {nodeSize=}); recursos borde <{nodeRing}> ajusta el grosor de su anillo de color, 0 para ninguno (original {nodeRing=}); recursos combate: si el minimapa se lee en combate",
	"/lueur alternar [<{nodeSwitchYards}>] — con las dos profesiones de recolección: alterna el rastreo de hierbas y el de minerales mientras te desplazas; un número ajusta la distancia entre dos cambios, en metros (original {nodeSwitchYards=})",
	"/lueur barrido — muestra lo que leyó el último barrido del minimapa, y lo que Lueur hizo con ello; barrido <{nodeScanYards}> ajusta la separación entre escaneos, en metros (original {nodeScanYards=})",
	"/lueur ignorar — ignora el objeto que tienes delante, o deja de ignorarlo; ignorar lista, ignorar vaciar, ignorar <nombre>",
	"/lueur idioma <auto | de | en | es | fr | ru> — idioma de los textos y comandos de Lueur",
	"/lueur debug — describe cada objeto apuntado y lo que Lueur deduce de él",
	"/lueur objetivos — enumera los objetivos de misión con los que se comparan los nombres de objeto",
	"/lueur estado — muestra los valores que el cliente aplica de verdad",
	"/lueur ayuda — muestra esta lista",
}
