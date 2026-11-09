-- Lueur : choix de la langue
-- Chaque autre fichier de ce dossier range ses textes dans ns.LOCALES, sous le code de sa
-- langue. ns.L les sert dans la langue choisie (celle du client tant que rien n'est choisi),
-- à défaut en anglais ; une clé qui manquerait partout s'affiche telle quelle plutôt que de
-- lever une erreur. Les textes sont relus à chaque usage : la langue se change en cours de jeu.

local _, ns = ...

local LOCALES = {}
ns.LOCALES = LOCALES

-- Clients qui se servent des textes d'une autre langue
local SAME_AS = { esMX = "esES", enGB = "enUS" }

local chosen  -- textes de la langue choisie ; nil : ceux de la langue du client

local function ClientLocale()
	local code = GetLocale()
	return SAME_AS[code] or code
end

-- Textes de la langue du client, ou de l'anglais s'il n'a pas de fichier ici
local function ClientTexts()
	return LOCALES[ClientLocale()] or LOCALES.enUS
end

ns.L = setmetatable({}, { __index = function(_, key)
	local text = (chosen or ClientTexts())[key]
	if text == nil then text = LOCALES.enUS[key] end
	if text == nil then return key end
	return text
end })

-- Sert désormais les textes de cette langue ; "auto", ou un code inconnu : celle du client
function ns.UseLanguage(code)
	chosen = LOCALES[code]
end

-- Adjectifs trop répandus pour rapprocher à eux seuls un objet d'un objectif de quête. Ils sont
-- rangés par langue de client, et non avec les textes : noms d'objets et objectifs viennent du
-- client, dans sa langue, quelle que soit la langue affichée et même si elle n'a pas de fichier ici.
local COMMON_WORDS = {
	enUS = "small little large great giant ancient",
	frFR = "petit petite grand grande vieux vieille ancien ancienne",
	deDE = "klein kleine kleiner kleines kleinen groß große großer großes großen alte alter altes alten uralt uralte uralter",
	esES = "pequeño pequeña pequeños pequeñas grande grandes viejo vieja viejos viejas antiguo antigua antiguos antiguas",
	ptBR = "pequeno pequena pequenos pequenas grande grandes velho velha velhos velhas antigo antiga antigos antigas",
	itIT = "piccolo piccola piccoli piccole grande grandi vecchio vecchia vecchi vecchie antico antica antichi antiche",
	ruRU = "маленький маленькая маленькое маленькие большой большая большое большие старый старая старое старые древний древняя древнее древние",
}

function ns.CommonWords()
	return COMMON_WORDS[ClientLocale()] or COMMON_WORDS.enUS
end

-- Ce qu'un coffre s'appelle. Le jeu lui donne le curseur de n'importe quel objet (une roue
-- dentée, comme à un levier) : c'est son nom qui le range parmi les coffres, quand un de ses mots
-- commence ou finit par l'un de ceux-ci (« Coffre endommagé », « Schatztruhe »). Par langue de
-- client, pour la même raison que les adjectifs. Le français est recoupé avec le cache du client
-- (« Coffre endommagé », objet 106318) ; les autres langues ne le sont avec rien.
local CHEST_WORDS = {
	enUS = "chest footlocker strongbox lockbox coffer",
	frFR = "coffre cantine malle",
	deDE = "truhe schließkassette geldkassette",
	esES = "cofre arcón baúl",
	ptBR = "baú cofre arca",
	itIT = "forziere scrigno baule",
	ruRU = "сундук ларец",
	koKR = "상자 궤짝",
	zhCN = "箱子 宝箱",
	zhTW = "箱子 寶箱",
}

function ns.ChestWords()
	return CHEST_WORDS[ClientLocale()] or CHEST_WORDS.enUS
end

-- Polices du jeu que le nom des objets peut prendre, en plus de la sienne ("game"), par alphabet
-- du client : le russe a les siennes ; le coréen et le chinois n'en ont pas qui sachent écrire
-- leurs noms, ils gardent la police du jeu. Fichiers lus dans
-- Blizzard_Fonts_Shared\Shared\GameFonts.xml (build 70245).
local FONT_ORDER = { "game", "arial", "morpheus", "skurri" }
local FONT_NAMES = { arial = "Arial Narrow", morpheus = "Morpheus", skurri = "Skurri" }
local FONT_FILES = {
	arial    = { roman = "Fonts\\ARIALN.TTF", russian = "Fonts\\ARIALN.TTF" },
	morpheus = { roman = "Fonts\\MORPHEUS.ttf", russian = "Fonts\\MORPHEUS_CYR.TTF" },
	skurri   = { roman = "Fonts\\skurri.ttf", russian = "Fonts\\SKURRI_CYR.TTF" },
}
local ALPHABETS = { ruRU = "russian", koKR = false, zhCN = false, zhTW = false }

-- Une police que Lueur connaît, que ce client l'ait ou non
function ns.IsFont(key)
	return key == "game" or FONT_FILES[key] ~= nil
end

-- Fichier d'une police pour l'alphabet du client ; nil pour celle du jeu, ou pour une police
-- qu'il n'a pas
function ns.FontFile(key)
	local alphabet = ALPHABETS[GetLocale()]
	if alphabet == nil then alphabet = "roman" end
	return alphabet and FONT_FILES[key] and FONT_FILES[key][alphabet] or nil
end

-- Polices que ce client propose, dans l'ordre du menu
function ns.FontChoices()
	local list = {}
	for _, key in ipairs(FONT_ORDER) do
		if key == "game" or ns.FontFile(key) then list[#list + 1] = key end
	end
	return list
end

-- Nom d'une police ; nil pour celle du jeu, qui se nomme dans la langue affichée (L.FONT_GAME)
function ns.FontName(key)
	return FONT_NAMES[key]
end
