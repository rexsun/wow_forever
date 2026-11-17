-- Lueur : met en lumière l'objet interactif visé (filons, plantes, objets de quête)
-- Principe : le "soft targeting" officiel de Blizzard désigne à tout instant une seule cible
-- d'interaction (l'unité "softinteract") et lui donne une nameplate. Lueur accroche à cette
-- nameplate une lueur unique, colorée selon le type d'objet (lu depuis son icône de curseur)
-- et animée selon son état : hors de portée, à portée, indisponible. L'effet choisi
-- (Effects.lua) décide de son dessin ; les textes viennent du dossier Locales.
--
-- Le cœur tient en sept fichiers, chargés dans cet ordre : Core.lua (réglages par défaut, état
-- partagé, outils), CVars.lua (ce que Lueur règle dans le jeu), Classify.lua (ce qu'est la cible),
-- Glow.lua (la lueur, son nom, sa découpe), Lueur.lua (de la cible à la lueur, événements),
-- Settings.lua (réglages : chargement, migrations, changements), Commands.lua (/lueur).
-- Ils ne se connaissent que par la table privée de l'addon (ns). Chacun y range ce dont les
-- suivants se servent, et le prend au chargement dans des variables locales ; ce qu'un fichier
-- chargé plus tard définit s'appelle par ns au moment de l'usage (ns.Evaluate, ns.ApplyLanguage…).
-- Ils sont arrivés ensemble après la 1.7.0, et le jeu ne charge un nouveau fichier qu'à son
-- lancement : d'ici là Lueur.lua, seul chargé, ne fait que le dire.

local _, ns = ...
local L = ns.L

-- Réglages communs à tous les personnages du compte (LueurDB)
local DEFAULTS = {
	enabled     = true,
	range       = 15,     -- portée du soft targeting (mètres)
	arc         = 2,      -- 0 = pile devant, 1 = devant, 2 = toutes directions
	offsetY     = -45,    -- décalage vertical de la lueur par rapport à la nameplate (pixels)
	size        = 120,    -- taille de la lueur (pixels, à l'échelle de la nameplate)
	effect      = "aura",
	categorySettings = {}, -- catégorie -> ses réglages de personnalisation propres (voir LOOK)
	colors      = {       -- couleur de la lueur de chaque catégorie
		ore   = { 1.00, 0.60, 0.18 },
		herb  = { 0.40, 1.00, 0.42 },
		quest = { 1.00, 0.84, 0.15 },
		chest = { 0.45, 0.78, 1.00 },
		bobber = { 1.00, 0.45, 0.40 },
		other = { 0.90, 0.90, 0.94 },
	},
	colors2     = {},     -- seconde couleur d'une catégorie, celle des traits fins et des éclats ; faute d'en avoir une, la première
	intensity   = 100,    -- luminosité de la lueur (%)
	followAlpha = false,  -- la lueur s'estompe avec la nameplate (objet masqué par le décor…)
	showName    = true,   -- nom de l'objet au-dessus de lui, écrit par Lueur à la place de celui du jeu
	showIcon    = true,   -- et son icône d'interaction, au-dessus du nom
	textSize    = 100,    -- taille de ce nom (% de celle de la police du jeu)
	textFont    = "game", -- sa police : celle du jeu, ou l'une des autres polices du jeu (Locales.lua)
	silhouette  = true,   -- la lueur passe derrière le personnage au lieu de le recouvrir
	exclusive   = true,   -- le jeu ne met en avant (nameplate, icône) que les cibles mises en lumière
	glowOnly    = false,  -- la lumière seule : ni nom ni icône de Lueur, la nameplate laissée au jeu ou à un autre addon (toujours avec Plumber)
	hideInCombat   = false,  -- pas de lueur en combat
	hideInInstance = false,  -- ni en donjon, en raid ou en champ de bataille
	hideLocked     = false,  -- ni sur un objet que le jeu refuse pour l'instant
	hideUntrained  = true,   -- ni sur une plante ou un filon quand le personnage n'a pas le métier qui les récolte
	debug       = false,
	language    = "auto",   -- langue des textes : "auto" (celle du client) ou le code d'une langue du dossier Locales
	questObjects = {},    -- nom d'objet -> titre de sa quête, appris de son infobulle
	ignored     = {},     -- nom d'objet replié -> son nom : objets que le joueur ne veut jamais voir briller
	containers  = {},     -- numéro d'objet -> true : objets du décor que le joueur a déjà fouillés, rangés depuis parmi les coffres
	minimap     = { hide = false, angle = 205 }, -- bouton de la minimap : masqué ou non, position (degrés)
}

-- Réglages propres à chaque personnage (LueurCharDB) : ce qu'il récolte, et la découpe à sa taille
local CHAR_DEFAULTS = {
	categories  = { ore = true, herb = true, quest = true, chest = true, bobber = true, other = false },
	bodyScale   = 100,    -- taille de la zone découpée autour du personnage (%)
	bodyShift   = 0,      -- décalage vertical de cette zone (% de la hauteur du personnage)
	nodeSwitch  = false,  -- deux métiers de récolte : Lueur allume tour à tour le pistage des plantes et celui des minerais
	nodeSwitchYards = 15, -- distance parcourue entre deux de ces bascules (mètres)
}

-- Réglages de personnalisation : chacun vaut pour tous les objets, sauf pour une catégorie qui
-- a le sien dans db.categorySettings. La couleur, elle, n'existe que par catégorie (db.colors).
local LOOK = { effect = true, size = true, intensity = true, offsetY = true, followAlpha = true, showName = true, showIcon = true, textSize = true, textFont = true,
	silhouette = true }

-- Réglages qui font un profil : ceux de la lueur, de sa détection et de son masquage. Le reste de
-- DEFAULTS vaut pour le compte quel que soit le profil : l'activation, la langue, le diagnostic, le
-- bouton de la minimap, ce que Lueur a appris et ce que le joueur a écarté. (Settings.lua : profils.)
local PROFILE = { range = true, arc = true, offsetY = true, size = true, effect = true, categorySettings = true, colors = true,
	colors2 = true, intensity = true, followAlpha = true, showName = true, showIcon = true, textSize = true, textFont = true, silhouette = true,
	exclusive = true, glowOnly = true, hideInCombat = true, hideInInstance = true, hideLocked = true, hideUntrained = true }

-- Bornes des réglages numériques, communes aux commandes et aux curseurs du menu
local LIMITS = {
	range     = { 5, 15 },  -- mesuré sur Forever 1.60.1 : la cible d'interaction se perd à 15 m, même avec 60 demandés
	arc       = { 0, 2 },
	offsetY   = { -200, 200 },
	size      = { 40, 300 },
	intensity = { 30, 150 },
	textSize  = { 60, 200 },
	bodyScale = { 40, 300 },
	bodyShift = { -100, 100 },
	nodeSwitchYards = { 10, 50 },
}

-- "chest" : ce qui se fouille (coffres, caisses, tonneaux) ; "bobber" : le flotteur de la ligne de pêche ;
-- "other" : le reste (portes, boîtes aux lettres…)
local CATEGORY_ORDER = { "ore", "herb", "quest", "chest", "bobber", "other" }

-- Réglages du compte et du personnage. Ils n'existent qu'une fois chargés (ADDON_LOADED,
-- ns.LoadSettings) : chaque fichier du cœur les tient dans deux variables locales, que
-- ns.BindSettings lui donne à ce moment-là.
local db, cdb
local binders = {}

function ns.OnSettings(bind)
	binders[#binders + 1] = bind
end

function ns.BindSettings(account, character)
	for _, bind in ipairs(binders) do bind(account, character) end
end

ns.OnSettings(function(account, character) db, cdb = account, character end)

-- Ce que plusieurs fichiers du cœur lisent et écrivent
ns.state = {
	gateOpen = nil,       -- l'affichage natif de la cible est-il ouvert ? nil = à réappliquer
	pendingCVars = false, -- "apply" ou "restore" : ce que le combat a fait remettre à sa fin
	lineOut = false,      -- la ligne de pêche du joueur est à l'eau, et son flotteur fait partie des objets mis en lumière
	directWorks = false,  -- GetNamePlateForUnit("softinteract") a déjà abouti pour un objet
	lastReport = nil,     -- dernière ligne de debug affichée (évite les répétitions)
}

ns.glow = { layers = {} }  -- cadre unique de la lueur, état de son animation, couches de tous ses effets

local min, max = math.min, math.max

local function Print(msg)
	print(L.PREFIX .. msg)
end

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function SafeCall(func, ...)
	if not func then return nil end
	local ok, result = pcall(func, ...)
	if not ok or IsSecret(result) then return nil end
	return result
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function Clamp(value, low, high)
	return max(low, min(high, value))
end

local function Approach(value, target, step)
	if value < target then return min(value + step, target) end
	return max(value - step, target)
end

-- Table où vit un réglage : celle du personnage, ou celle du compte
local function Store(key)
	return CHAR_DEFAULTS[key] ~= nil and cdb or db
end

-- Couleur d'une catégorie : trois composantes
local function Color(category)
	local color = db.colors[category] or db.colors.other
	return color[1], color[2], color[3]
end

-- Seconde couleur d'une catégorie : trois composantes, et si elle lui est propre. Tant que le joueur
-- n'en a pas choisi, c'est la première, et l'effet se dessine comme il s'est toujours dessiné.
local function Color2(category)
	local color = db.colors2[category]
	if color then return color[1], color[2], color[3], true end
	local r, g, b = Color(category)
	return r, g, b, false
end

-- Valeur d'un réglage de personnalisation pour une catégorie : la sienne, sinon celle de tous
-- les objets ; sans catégorie, celle de tous les objets
local function Look(category, key)
	local own = category and db.categorySettings[category]
	local value = own and own[key]
	if value == nil then return db[key] end
	return value
end

-- Minuscules sans accents : commandes, noms d'effets et noms d'objets se tapent avec ou sans.
-- string.lower ne connaît que l'ASCII : les majuscules latines accentuées et cyrilliques passent
-- par cette table.
local ACCENTS = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["ú"] = "u", ["ñ"] = "n", ["ß"] = "ss", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Á"] = "a", ["Ç"] = "c", ["É"] = "e",
	["È"] = "e", ["Ê"] = "e", ["Î"] = "i", ["Í"] = "i", ["Ô"] = "o", ["Ö"] = "o", ["Ó"] = "o", ["Ù"] = "u", ["Û"] = "u",
	["Ü"] = "u", ["Ú"] = "u", ["Ñ"] = "n",
}
-- cyrillique : А-П (208 144-159) donnent а-п (208 176-191), Р-Я (208 160-175) donnent р-я
-- (209 128-143) ; Ё et ё s'écrivent е, comme le font souvent les textes du jeu
for byte = 144, 175 do
	ACCENTS["\208" .. string.char(byte)] = byte < 160 and "\208" .. string.char(byte + 32) or "\209" .. string.char(byte - 32)
end
ACCENTS["\208\129"], ACCENTS["\209\145"] = "\208\181", "\208\181"

local function Fold(text)
	return (text:gsub("[\195-\197\208\209][\128-\191]", ACCENTS):lower())
end

-- Noms affichés, relus à chaque usage : la langue peut changer en cours de jeu
local function EffectLabel(key)
	return L["EFFECT_" .. key:upper()]
end

-- Nom d'une catégorie dans le menu
local function CategoryLabel(category)
	return L["CATEGORY_" .. category:upper()]
end

-- Nom d'une catégorie, ou de son absence, dans une phrase du diagnostic
local function CategoryName(category)
	return L["NAME_" .. (category or "none"):upper()]
end

local function StateName(state)
	return L["STATE_" .. state:upper()]
end

-- Coût en temps de calcul. ns.Timed rend une fonction entourée de deux lectures de l'horloge du jeu
-- (debugprofilestop, en millisecondes) ; ns.Cost dit ce qu'elle a coûté depuis la dernière fois qu'on
-- le lui a demandé : nombre d'appels, durée moyenne, durée la plus longue. /lueur status l'affiche.
local costs = {}

function ns.Timed(name, func)
	local clock = debugprofilestop
	if not clock then return func end
	local cost = { calls = 0, total = 0, worst = 0 }
	costs[name] = cost
	return function(...)
		local start = clock()
		func(...)
		local spent = clock() - start
		cost.calls, cost.total = cost.calls + 1, cost.total + spent
		if spent > cost.worst then cost.worst = spent end
	end
end

function ns.Cost(name)
	local cost = costs[name]
	if not cost then return nil end
	local calls, mean, worst = cost.calls, cost.calls > 0 and cost.total / cost.calls or 0, cost.worst
	cost.calls, cost.total, cost.worst = 0, 0, 0
	return calls, mean, worst
end

-- Ce dont les fichiers suivants se servent
ns.PROFILE = PROFILE
ns.DEFAULTS, ns.CHAR_DEFAULTS, ns.LOOK, ns.LIMITS, ns.CATEGORY_ORDER = DEFAULTS, CHAR_DEFAULTS, LOOK, LIMITS, CATEGORY_ORDER
ns.Print, ns.IsSecret, ns.SafeCall, ns.CopyDefaults, ns.Clamp, ns.Approach = Print, IsSecret, SafeCall, CopyDefaults, Clamp, Approach
ns.Store, ns.GetColor, ns.GetColor2, ns.Look, ns.Fold = Store, Color, Color2, Look, Fold
ns.EffectLabel, ns.CategoryLabel, ns.CategoryName, ns.StateName = EffectLabel, CategoryLabel, CategoryName, StateName
