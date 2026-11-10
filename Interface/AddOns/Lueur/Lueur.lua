-- Lueur : met en lumière l'objet interactif visé (filons, plantes, objets de quête)
-- Principe : le "soft targeting" officiel de Blizzard désigne à tout instant une seule cible
-- d'interaction (l'unité "softinteract") et lui donne une nameplate. Lueur accroche à cette
-- nameplate une lueur unique, colorée selon le type d'objet (lu depuis son icône de curseur)
-- et animée selon son état : hors de portée, à portée, indisponible. L'effet choisi
-- (Effects.lua) décide de son dessin ; les textes viennent du dossier Locales.

local ADDON_NAME, ns = ...
local L = ns.L
local EFFECTS = ns.EFFECTS
local Lerp, Sized, Tint, Place = ns.Lerp, ns.Sized, ns.Tint, ns.Place

local SOFT = "softinteract"
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local CURSORS = "Interface\\Cursor\\"
local FALLBACK_TEXTURE = "Interface\\Cooldown\\star4"
local SCHEMA = 10 -- version des réglages sauvegardés

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
	-- Éteintes d'office depuis la 1.6.1 : les lire demande de balayer la minimap, ce qui la cache et gêne
	-- trop de joueurs (à-coups, clics perdus, autres interfaces) pour l'imposer à qui n'a rien demandé.
	nodeHerbs   = false,  -- sur la minimap, l'icône de chaque plante que le pistage du jeu y montre (NodeScan.lua)
	nodeOre     = false,  -- et celle de chaque filon
	nodeSize    = 12,     -- côté de ces icônes (unités de la minimap)
	nodeRing    = 100,    -- épaisseur de l'anneau coloré qui les entoure (% de celle de l'image) ; 0 : pas d'anneau
	nodeCombat  = true,   -- la minimap se lit aussi en combat
	nodeScanYards = 35,   -- distance parcourue entre deux balayages de la minimap (mètres) : chacun la cache un instant
	nodeNames   = {},     -- langue du client -> nom replié d'un filon ou d'une plante -> { kind, id }, appris en s'en approchant
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
	nodeSize  = { 8, 24 },
	nodeRing  = { 0, 100 },
	nodeScanYards = { 10, 100 },
	nodeSwitchYards = { 10, 50 },
}

-- "chest" : ce qui se fouille (coffres, caisses, tonneaux) ; "bobber" : le flotteur de la ligne de pêche ;
-- "other" : le reste (portes, boîtes aux lettres…)
local CATEGORY_ORDER = { "ore", "herb", "quest", "chest", "bobber", "other" }

-- Styles du halo d'avant la version 0.5 -> effet qui les remplace
local LEGACY_STYLES = { aura = "aura", reticule = "aura", discret = "subtle" }

local POLL_INTERVAL = 0.12   -- réévaluation de la cible et de son état (secondes)
local APPEAR_TIME   = 0.45   -- la lueur arrive
local BLEND_TIME    = 0.30   -- fondu entre deux états
local FLASH_TIME    = 0.50   -- éclair du passage "à portée"
local GHOST_TIME    = 0.40   -- dissipation quand la cible disparaît
local STATE_DELAY   = 0.15   -- un état doit tenir ce temps avant d'être affiché (anti-scintillement)
local LOCK_DELAY    = 0.60   -- idem pour "indisponible", confirmé plus prudemment

-- Pêche : le flotteur tombe souvent au-delà des 15 m où s'arrête le réglage de portée. Tant que
-- la ligne est à l'eau, Lueur demande donc au jeu de chercher jusqu'à LINE_RANGE.
local LINE_RANGE    = 60      -- mètres ; ni 25 ni 40 ne suffisaient toujours
local FISHING_ICON  = 136245  -- Interface\Icons\Trade_Fishing : l'icône du sort de pêche, dans toutes les langues
-- Numéro du flotteur dans les données du jeu (son GUID le porte) : le même pour toutes les lignes
local BOBBER_IDS    = { [35591] = true }

-- Fichiers de curseur du jeu (Interface\Cursor\*.blp) -> catégorie. Les noms sont ceux que le
-- client de Forever connaît (lus dans WowB.exe, build 70338), plus Fishing, qu'il n'a pas.
-- Un coffre n'a pas de curseur à lui : voir MatchContainer.
-- "service" : le curseur dit lui-même ce qu'est l'objet (une boîte aux lettres, et ce que le jeu
-- montre d'ordinaire sur un PNJ). C'est un autre objet, que son nom ne range nulle part ailleurs :
-- voir Classify.
local CURSOR_CATEGORY = {
	Mine = "ore",
	GatherHerbs = "herb",
	Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest", QuestInteract = "quest",
	CampaignQuest = "quest", CampaignQuestTurnIn = "quest", LegendaryQuest = "quest", LegendaryQuestTurnIn = "quest",
	Important = "quest", ImportantTurnIn = "quest", Recurring = "quest", Recurringturnin = "quest",
	Wrapper = "quest", Wrapperturnin = "quest",
	PickLock = "chest", LootAll = "chest", Pickup = "chest",
	Fishing = "bobber", FishingCursor = "bobber",
	Interact = "other", GamepadInteract = "other", Inspect = "other",
	Mail = "service", Speak = "service", Buy = "service", Trainer = "service", Taxi = "service", Innkeeper = "service",
	Repair = "service", RepairNPC = "service", Stablemaster = "service",
}

-- Curseur que l'aperçu montre pour chaque catégorie, faute d'objet à qui le demander
local SAMPLE_CURSOR = { ore = "Mine", herb = "GatherHerbs", quest = "Quest", chest = "Pickup", bobber = "Fishing", other = "Interact" }

-- CVars que Lueur modifie (valeurs d'origine sauvegardées puis restaurées par /lueur off)
local MANAGED_CVARS = {
	"SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
	"SoftTargetInteractOnlyInRange", "SoftTargetInteractRangeIsHard", "SoftTargetIconInteract", "SoftTargetIconGameObject",
	"nameplateGameObjectMaxDistance",
}
-- Parmi elles, l'icône que le jeu pose sur la cible d'interaction
-- SoftTargetIconGameObject est forcé à 1 quand la gate s'ouvre : sans icône, le jeu ne
-- crée pas de nameplate pour les objets interactibles en soft target (Classic)
local ICON_CVARS = { "SoftTargetIconInteract", "SoftTargetIconGameObject" }
-- CVars que Lueur lit sans y toucher : /lueur status les montre, parce que la nameplate en dépend peut-être
local WATCHED_CVARS = { "nameplateMaxDistance" }

local db, cdb                -- réglages du compte, réglages du personnage
local Evaluate               -- défini plus bas : met la lueur en accord avec la cible courante
local UseLanguage            -- défini plus bas : sert textes et commandes dans la langue réglée
local gateOpen               -- l'affichage natif de la cible est-il ouvert ? nil = à réappliquer
local inCombat = false       -- entre PLAYER_REGEN_DISABLED et PLAYER_REGEN_ENABLED
local cursorLookup = {}      -- fileID -> { catégorie, grisé }
local activeUnits = {}       -- jeton nameplateN -> true
local probe                  -- texture cachée servant à lire l'icône de curseur
local pendingCVars = false
local leaving = false        -- déconnexion en cours : les CVars sont rendues, plus rien ne doit y toucher
local directWorks = false    -- GetNamePlateForUnit("softinteract") a déjà abouti pour un objet
local lineOut = false        -- la ligne de pêche du joueur est à l'eau, et son flotteur fait partie des objets mis en lumière
local lastReport             -- dernière ligne de debug affichée (évite les répétitions)

local glow = { layers = {} }  -- cadre unique de la lueur, état de son animation, couches de tous ses effets
local ghost                   -- cadre de dissipation
local label                   -- nom et icône de l'objet, au-dessus de la lueur

local sin, min, max = math.sin, math.min, math.max
local TWO_PI = 2 * math.pi

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

---------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------

local function GetCVarValue(name)
	local ok, value = pcall(C_CVar and C_CVar.GetCVar or GetCVar, name)
	if ok then return value end
end

-- Ne touche qu'aux CVars que ce client connaît (la liste varie d'une version à l'autre)
local function SetCVarValue(name, value)
	if GetCVarValue(name) == nil then return end
	pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end

-- Affichage natif de la cible d'interaction : sa nameplate, où s'accroche la lueur, et son
-- icône. En mode exclusif, Lueur ne l'ouvre que pour une cible mise en lumière : PNJ,
-- cadavres, boîtes aux lettres et autres restent utilisables avec la touche d'interaction,
-- mais le jeu ne les met plus en avant.
local function EnsureIconCVars()
	-- Le client beta écrase SoftTargetIconGameObject à 0 après PLAYER_ENTERING_WORLD
	-- On le répare ici, avant que Evaluate() ne cherche la nameplate
	if gateOpen == true then
		local current = GetCVarValue("SoftTargetIconGameObject")
		if current ~= "1" then SetCVarValue("SoftTargetIconGameObject", 1) end
	end
end

local function SetGate(open)
	open = open or not glow.Exclusive()
	if open == gateOpen or InCombatLockdown() then
		EnsureIconCVars()
		return
	end
	gateOpen = open
	SetCVarValue("SoftTargetNameplateInteract", open and 1 or 0)
	-- SoftTargetIconGameObject doit être 1 pour que le jeu crée des nameplates pour les game objects
	if open then SetCVarValue("SoftTargetIconGameObject", 1) end
	for _, name in ipairs(ICON_CVARS) do
		if name ~= "SoftTargetIconGameObject" then
			local original = db.savedCVars and db.savedCVars[name]
			if original ~= false then SetCVarValue(name, open and original or 0) end
		end
	end
end

-- Portée à demander au jeu : celle du réglage, ou celle qu'il faut pour atteindre le flotteur
local function WantedRange()
	return lineOut and LINE_RANGE or db.range
end

-- Le client porte-t-il les valeurs que Lueur applique ? C'est qu'elles ne lui ont pas été rendues.
local function CVarsLookApplied()
	local onlyInRange = GetCVarValue("SoftTargetInteractOnlyInRange")
	local range = tonumber(GetCVarValue("SoftTargetInteractRange"))
	return GetCVarValue("SoftTargetInteract") == "3" and (onlyInRange == nil or onlyInRange == "0")
		and (range == db.range or range == LINE_RANGE)
end

local function ApplyCVars()
	if InCombatLockdown() then pendingCVars = "apply" return end
	if db.cvarsReturned then
		-- rendues au jeu à la dernière déconnexion : ce que le client porte maintenant, ce sont les
		-- valeurs du joueur, qu'il a pu changer depuis. On les relit, sauf si ce sont les nôtres.
		db.cvarsReturned = nil
		if not CVarsLookApplied() then db.savedCVars = nil end
	end
	db.savedCVars = db.savedCVars or {}
	for _, name in ipairs(MANAGED_CVARS) do
		if db.savedCVars[name] == nil then
			db.savedCVars[name] = GetCVarValue(name) or false
		end
	end
	SetCVarValue("SoftTargetInteract", 3)          -- soft target d'interaction toujours actif
	SetCVarValue("SoftTargetInteractRange", WantedRange())
	SetCVarValue("SoftTargetInteractArc", db.arc)    -- angle de recherche autour du joueur
	SetCVarValue("SoftTargetInteractOnlyInRange", 0) -- détecter aussi hors de portée d'interaction
	-- la portée demandée ne doit pas écarter ce avec quoi le joueur peut interagir d'où il est,
	-- comme le flotteur de sa ligne de pêche
	SetCVarValue("SoftTargetInteractRangeIsHard", 0)
	-- la lueur s'accroche à la nameplate de l'objet : le jeu doit la montrer aussi loin qu'il le
	-- désigne, donc jusqu'au flotteur. Le joueur qui la montre plus loin encore garde sa valeur.
	SetCVarValue("nameplateGameObjectMaxDistance", max(tonumber(db.savedCVars.nameplateGameObjectMaxDistance) or 0, LINE_RANGE))
	-- la nameplate et l'icône de la cible dépendent de ce qui est visé
	gateOpen = nil
	Evaluate()
end

-- La portée seule, quand la ligne de pêche entre dans l'eau ou en sort. Renvoie false quand il
-- n'y a rien à écrire, parce que Lueur ne tient pas les CVars du jeu : désactivé, ou pas encore
-- passé par ApplyCVars.
local function ApplyRange()
	if not db.enabled or not db.savedCVars or db.cvarsReturned then return false end
	if InCombatLockdown() then
		pendingCVars = pendingCVars or "apply"
	else
		SetCVarValue("SoftTargetInteractRange", WantedRange())
	end
	return true
end

local function RestoreCVars()
	if InCombatLockdown() then pendingCVars = "restore" return end
	if not db.savedCVars then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then SetCVarValue(name, value) end
	end
	db.savedCVars = nil
	gateOpen = nil
end

-- À la déconnexion, le jeu retrouve ses valeurs d'origine : désactiver ou désinstaller Lueur
-- depuis la liste des addons ne laisse rien derrière lui. Elles restent en mémoire pour le
-- cas où le client ne les enregistrerait pas (fermeture brutale).
local function ReturnCVars()
	if not db.enabled or not db.savedCVars or InCombatLockdown() then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then SetCVarValue(name, value) end
	end
	db.cvarsReturned = true
	gateOpen = nil
end

-- Les versions 0.1.x pouvaient mémoriser comme valeurs d'origine celles que Lueur venait
-- lui-même d'appliquer : /lueur off ne rendait alors rien. Quand la sauvegarde porte cette
-- signature, on lui substitue les valeurs par défaut du client.
local function RepairSavedCVars()
	local saved = db.savedCVars
	if not saved or not (C_CVar and C_CVar.GetCVarDefault) then return end
	if saved.SoftTargetInteract ~= "3" or saved.SoftTargetNameplateInteract ~= "1" or saved.SoftTargetInteractArc ~= "2"
		or (saved.SoftTargetInteractRange ~= "20" and saved.SoftTargetInteractRange ~= tostring(db.range)) then
		return
	end
	for _, name in ipairs({ "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractArc", "SoftTargetInteractRange" }) do
		local default = SafeCall(C_CVar.GetCVarDefault, name)
		if default ~= nil then saved[name] = default end
	end
end

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------

local function BuildCursorLookup()
	if not GetFileIDFromPath then return end
	for name, category in pairs(CURSOR_CATEGORY) do
		for _, prefix in ipairs({ "", "Unable" }) do
			local path = "Interface\\Cursor\\" .. prefix .. name
			local id = SafeCall(GetFileIDFromPath, path) or SafeCall(GetFileIDFromPath, path .. ".blp")
			if id then cursorLookup[id] = { category, prefix ~= "" } end
		end
	end
end

local QUEST_LINE_TYPE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

-- Un objet à ramasser pour une quête porte un curseur générique, et l'API de quête par unité
-- ne les reconnaît pas tous. On le rattache donc à une quête en cours par, dans l'ordre : ce
-- que son infobulle a déjà révélé, son nom dans le texte d'un objectif ("Scie détrempée :
-- 0/1"), ou un mot marquant en commun avec un objet à ramasser ("Tas de camelote" pour
-- "Camelote rutilante"). Noms et objectifs sont ceux du client, dans sa langue.
local questTexts = {}      -- objectifs inachevés : { text = minuscules sans compteur, pickable = objet à ramasser ou à utiliser }
local questTitles = {}     -- titre normalisé de chaque quête en cours -> true
local questsDirty = true

local function NormalizeText(text)
	text = text:lower():gsub("\194\160", " ")  -- espace insécable (typographie française)
	text = text:gsub("\226\128\153", "'")      -- apostrophe typographique
	text = text:gsub("%d+%s*/%s*%d+", "")
	text = text:gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "")
	return text
end

-- Adjectifs trop répandus pour rapprocher à eux seuls un objet d'un objectif : ceux de la
-- langue du client, qui est celle des noms et des objectifs, pas ceux de la langue affichée.
-- Ils passent par la même mise en forme que les noms auxquels ils seront comparés.
local COMMON_WORDS = {}
for word in NormalizeText(ns.CommonWords()):gmatch("%S+") do COMMON_WORDS[word] = true end

-- Clé d'un nom d'objet dans la liste des objets ignorés : il s'y retrouve tapé avec ou sans
-- accents. Les accents se replient avant le passage en minuscules, qui ne sait rien d'eux.
local function NameKey(name)
	name = name:gsub("\194\160", " "):gsub("\226\128\153", "'")
	return (Fold(name):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function RebuildQuestTexts()
	questsDirty = false
	for i = #questTexts, 1, -1 do questTexts[i] = nil end
	for title in pairs(questTitles) do questTitles[title] = nil end
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
	local modern = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestIDForLogIndex
	for index = 1, SafeCall(modern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries) or 0 do
		local questID, title
		if modern then
			questID = SafeCall(C_QuestLog.GetQuestIDForLogIndex, index)
			title = type(questID) == "number" and SafeCall(C_QuestLog.GetTitleForQuestID, questID)
		elseif GetQuestLogTitle then
			local ok, name, _, _, isHeader, _, _, _, id = pcall(GetQuestLogTitle, index)
			if ok and not isHeader then questID, title = id, name end
		end
		if type(title) == "string" then questTitles[NormalizeText(title)] = true end
		local objectives = type(questID) == "number" and SafeCall(C_QuestLog.GetQuestObjectives, questID)
		if type(objectives) == "table" then
			for _, objective in ipairs(objectives) do
				local text = objective.text
				if not objective.finished and type(text) == "string" and not IsSecret(text) then
					text = NormalizeText(text)
					if #text >= 4 then
						local kind = objective.type
						questTexts[#questTexts + 1] = { text = text, pickable = kind == nil or kind == "item" or kind == "object" }
					end
				end
			end
		end
	end
end

-- Renvoie un mot marquant de `source` qui commence aussi un mot de `target`
local function SharedWord(source, target)
	target = " " .. target:gsub("%p", " ")
	for word in source:gmatch("[^%s%p]+") do
		if #word >= 5 and not COMMON_WORDS[word] and target:find(" " .. word, 1, true) then return word end
	end
end

-- Renvoie ce qui rattache ce nom d'objet à une quête en cours (affiché par le debug), ou nil
local function MatchQuestObjective(name)
	if type(name) ~= "string" or #name < 4 then return nil end
	if questsDirty then RebuildQuestTexts() end
	name = NormalizeText(name)
	if questTitles[db.questObjects[name]] then return L.MATCH_TOOLTIP end
	for _, objective in ipairs(questTexts) do
		local text = objective.text
		-- "scie détrempée" dans l'objectif, ou l'objectif ("fournitures") dans le nom de l'objet
		if text:find(name, 1, true) or (#text >= 5 and name:find(text, 1, true)) then return L.MATCH_NAME end
	end
	for _, objective in ipairs(questTexts) do
		-- jamais avec un objectif d'élimination : "Hutte murloc" n'est pas un "Murloc tué"
		if objective.pickable then
			local word = SharedWord(name, objective.text) or SharedWord(objective.text, name)
			if word then return L.MATCH_WORD:format(word) end
		end
	end
end

-- L'infobulle d'un objet de quête nomme sa quête. Quand le jeu en montre une (survol à la
-- souris, ou infobulle de la cible d'interaction si tu l'as activée), on retient le nom de
-- l'objet : c'est le seul lien sûr quand ce nom n'a rien de commun avec l'objectif.
local function LearnFromTooltip()
	if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return false end
	local data = SafeCall(C_TooltipInfo.GetWorldCursor)
	local lines = type(data) == "table" and data.lines
	if type(lines) ~= "table" or not lines[1] then return false end
	if Enum and Enum.TooltipDataType and data.type == Enum.TooltipDataType.Unit then return false end
	local name = lines[1].leftText
	if IsSecret(name) or type(name) ~= "string" then return false end
	if questsDirty then RebuildQuestTexts() end
	for index = 2, #lines do
		local text = lines[index].leftText
		if not IsSecret(text) and type(text) == "string" then
			local title = NormalizeText(text)
			if questTitles[title] then
				name = NormalizeText(name)
				if db.questObjects[name] == title then return false end
				db.questObjects[name] = title
				return true
			end
		end
	end
	return false
end

-- Le jeu lui-même rattache-t-il cet objet à une quête en cours ?
local function IsQuestUnit(unit)
	-- API ajoutées dans Forever ; absentes de Classic Era (restent alors le curseur et le nom)
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		if SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then return true end
	end
	if QUEST_LINE_TYPE and C_TooltipInfo and C_TooltipInfo.GetUnit then
		local data = SafeCall(C_TooltipInfo.GetUnit, unit)
		if data and data.lines then
			for _, line in ipairs(data.lines) do
				if line.type == QUEST_LINE_TYPE then return true end
			end
		end
	end
	return false
end

-- Le joueur pêche-t-il ? La pêche est une canalisation, reconnue à l'icône de son sort, sinon à
-- son nom, qui est celui du métier. Renvoie aussi le nom et l'icône de la canalisation en
-- cours, pour le diagnostic.
local function ReadLine()
	if not UnitChannelInfo then return false end
	local ok, name, _, icon = pcall(UnitChannelInfo, "player")
	if not ok then return false end
	if IsSecret(name) then name = nil end
	if IsSecret(icon) then icon = nil end
	if name == nil and icon == nil then return false end
	local fishing = icon == FISHING_ICON
		or (type(icon) == "string" and icon:lower():find("trade_fishing", 1, true) ~= nil)
		or (name ~= nil and name == PROFESSIONS_FISHING)
	return fishing, name, icon
end

-- Le client renvoie selon les cas un fileID, un chemin (Interface\Cursor\Mine) ou un nom
-- d'atlas (Cursor_Crosshair_UnableMine_64) : on cherche donc des mots-clés dans la chaîne.
-- Le premier qui s'y trouve l'emporte : « questinteract » est une quête avant d'être une interaction.
local CURSOR_KEYWORDS = {
	{ "gather",    "herb" },
	{ "mine",      "ore" },
	{ "quest",     "quest" },
	{ "important", "quest" },  -- les quêtes que le jeu distingue ont leur curseur, sans le mot « quest »
	{ "recurring", "quest" },
	{ "wrapper",   "quest" },
	{ "lootall",   "chest" },
	{ "pickup",    "chest" },
	{ "picklock",  "chest" },
	{ "fishing",   "bobber" },
	{ "mail",      "service" },
	{ "speak",     "service" },
	{ "buy",       "service" },
	{ "trainer",   "service" },
	{ "taxi",      "service" },
	{ "innkeeper", "service" },
	{ "repair",    "service" },
	{ "stable",    "service" },
	{ "interact",  "other" },
	{ "inspect",   "other" },  -- la loupe : un écriteau, un livre
}

-- Renvoie la catégorie et l'indicateur "grisé" (variante Unable : interaction impossible
-- pour l'instant) lus dans un nom de curseur
local function ReadCursorName(name)
	if type(name) ~= "string" then return nil end
	name = name:lower()
	local blocked = name:find("unable", 1, true) ~= nil
	for _, entry in ipairs(CURSOR_KEYWORDS) do
		if name:find(entry[1], 1, true) then return entry[2], blocked end
	end
	return nil, blocked
end

-- Renvoie : l'objet a-t-il une icône de curseur, sa catégorie, grisée ou non, et le nom
-- brut du curseur (pour le debug)
local function ReadCursor(unit)
	if not SafeCall(SetUnitCursorTexture, probe, unit, nil, true) then return false end
	local texture = probe:GetTexture()
	local atlas = probe.GetAtlas and probe:GetAtlas()
	if IsSecret(texture) then texture = nil end
	if IsSecret(atlas) then atlas = nil end

	local category, blocked
	local known = type(texture) == "number" and cursorLookup[texture]
	if known then
		category, blocked = known[1], known[2]
	else
		category, blocked = ReadCursorName(texture)
		if not category then
			local fromAtlas, atlasBlocked = ReadCursorName(atlas)
			category, blocked = fromAtlas, blocked or atlasBlocked
		end
	end
	return true, category, blocked or false, atlas or texture
end

-- Numéro de l'objet dans les données du jeu, le même pour tous les objets d'une sorte. Il se lit
-- dans son GUID (GameObject-0-serveur-instance-zone-numéro-exemplaire) ; nil si le jeu ne le donne pas.
local function GUIDObject(guid)
	return type(guid) == "string" and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

local function ObjectID(unit)
	return GUIDObject(SafeCall(UnitGUID, unit))
end

-- Un coffre n'a pas de curseur à lui : le jeu lui donne celui d'un levier (vu en jeu le
-- 2026-10-13 : « Coffre endommagé → autre »). Deux choses le rangent parmi les contenants : le
-- joueur a déjà fouillé un objet de ce numéro (LearnContainers), ou un mot de son nom commence ou
-- finit comme un nom de coffre dans la langue du client. Renvoie ce qui l'y range (affiché par le
-- debug), ou nil.
local CHEST_WORDS = {}
for word in ns.ChestWords():gmatch("%S+") do CHEST_WORDS[#CHEST_WORDS + 1] = Fold(word) end

local function MatchContainer(id, name)
	if id and db.containers[id] then return L.MATCH_LOOT end
	if type(name) ~= "string" then return nil end
	for word in NameKey(name):gmatch("[^%s%p]+") do
		for _, chest in ipairs(CHEST_WORDS) do
			if word:sub(1, #chest) == chest or word:sub(-#chest) == chest then return L.MATCH_NAME end
		end
	end
end

-- Le butin s'ouvre : le jeu dit de quel objet vient chaque part (son GUID). Le numéro d'un objet
-- du décor que le joueur fouille est retenu : c'est ce qui range parmi les coffres une caisse ou
-- un tonneau, dont le nom ne dit rien, et tout coffre dans une langue que CHEST_WORDS n'a pas.
-- Ni le flotteur, ni les filons et les plantes, que leur curseur désigne.
local gathered = {}  -- numéro des filons et des plantes que le jeu a désignés depuis le chargement

local function LearnContainers()
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	for slot = 1, SafeCall(GetNumLootItems) or 0 do
		local id = GUIDObject(SafeCall(GetLootSourceInfo, slot))
		if id and not BOBBER_IDS[id] and not gathered[id] then db.containers[id] = true end
	end
end

-- Renvoie la catégorie de l'objet, l'indicateur "grisé", le nom de curseur brut et le numéro de
-- l'objet, si le jeu le donne
local function Classify(unit, name)
	local hasCursor, category, blocked, cursor = ReadCursor(unit)
	-- Un curseur de service dit ce qu'est l'objet : ni son nom ni la pêche n'en font autre chose.
	-- (Vu en jeu le 2026-10-13 : « Boîte aux lettres → quête », par le mot « boîte » d'un objectif.)
	-- Seul le jeu peut encore le rattacher à une quête.
	local service = category == "service"
	if service then category = "other" end
	-- le jeu n'a pas de curseur pour le flotteur, qui porte celui de n'importe quel objet : c'est
	-- son numéro qui le désigne
	local id = ObjectID(unit)
	if id and BOBBER_IDS[id] then
		category = "bobber"
	elseif category ~= "ore" and category ~= "herb" and category ~= "bobber" then
		if IsQuestUnit(unit) then
			category = "quest"
		elseif service then
			-- un autre objet, sans plus
		elseif not id and (category == nil or category == "other") and ReadLine() then
			-- faute de numéro lisible : un objet sans curseur à lui, désigné pendant que le
			-- joueur pêche, est pris pour son flotteur
			category = "bobber"
		elseif MatchQuestObjective(name) ~= nil then
			category = "quest"
		elseif (category == nil or category == "other") and MatchContainer(id, name) ~= nil then
			category = "chest"
		end
	end
	if not category and (hasCursor or (UnitIsInteractable and SafeCall(UnitIsInteractable, unit) == true)) then
		category = "other"
	end
	return category, blocked, cursor, id
end

-- Le personnage a-t-il le métier qui récolte cette catégorie ? true, false, ou nil quand le jeu ne le
-- dit pas (client sans ces API, compétences pas encore chargées). Le sort de pistage connu ou la
-- compétence lue suffisent l'un comme l'autre ; il faut que tout ce qui sait répondre dise non.
local Trained
do
	-- pour chaque catégorie, la ligne de compétence du métier dans les données du jeu, et les sorts de
	-- pistage qu'il apprend (Découverte d'herbes, Découverte de gisements), ceux que NodeScan.lua reconnaît
	local PROFESSIONS = { herb = { line = 182, finders = { 2383, 8387 } }, ore = { line = 186, finders = { 2580, 8388 } } }

	function Trained(category)
		local profession = PROFESSIONS[category]
		if not profession then return nil end
		local answered = false
		local IsKnown = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell
		if IsKnown then
			for _, spell in ipairs(profession.finders) do
				local known = SafeCall(IsKnown, spell)
				if known == true then return true end
				answered = answered or known == false
			end
		end
		if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
			-- aucune ligne : le jeu ne les a pas encore données (juste après la connexion)
			if (SafeCall(C_SkillInfo.GetNumSkillLines) or 0) == 0 then return nil end
			local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, profession.line)
			if not ok or IsSecret(info) then return nil end
			if type(info) == "table" then
				local most = info.maxRank
				if IsSecret(most) or type(most) ~= "number" or most > 0 then return true end
			end
			answered = true
		end
		if answered then return false end
		return nil
	end
end

-- "ready" : on peut interagir ; "far" : trop loin ; "locked" : à portée mais le jeu refuse
-- (compétence insuffisante, objet verrouillé…). Sans l'API de portée (Classic Era), un
-- curseur grisé est simplement considéré comme trop loin.
local function ReadState(unit, blocked)
	local inRange
	if UnitIsInInteractRange then inRange = SafeCall(UnitIsInInteractRange, unit) end
	if inRange == false then return "far", inRange end
	if blocked then return inRange == true and "locked" or "far", inRange end
	return "ready", inRange
end

---------------------------------------------------------------------------
-- Cible
---------------------------------------------------------------------------

local function GetNamePlate(unit)
	return C_NamePlate and SafeCall(C_NamePlate.GetNamePlateForUnit, unit)
end

-- Y a-t-il une cible d'interaction ? true, false, ou nil si le client ne le dit pas
-- (valeurs secrètes). Un objet du décor n'"existe" pas au sens de UnitExists.
local function SoftTargetExists()
	local isUnit, isObject = SafeCall(UnitExists, SOFT), SafeCall(UnitIsGameObject, SOFT)
	if isUnit == true or isObject == true then return true end
	if isUnit == false and isObject == false then return false end
	return nil
end

-- Renvoie le jeton d'unité à interroger, sa nameplate (nil si le jeu ne l'affiche pas, ou
-- pas encore) et le chemin suivi (pour le debug). Le jeton "softinteract" suffit en général ;
-- tant qu'il n'a jamais donné la nameplate d'un objet du décor sur ce client, on la cherche
-- aussi en balayant les nameplates visibles. Sans cible lisible, la quatrième valeur dit si
-- c'est faute de le savoir.
local function ResolveTarget()
	local exists = SoftTargetExists()
	if exists == false then return nil end
	local plate = GetNamePlate(SOFT)
	if plate then
		if not directWorks and SafeCall(UnitIsGameObject, SOFT) == true then directWorks = true end
		return SOFT, plate, L.VIA_DIRECT
	end
	if not directWorks then
		for unit in pairs(activeUnits) do
			if SafeCall(UnitIsGameObject, unit) == true or SafeCall(UnitIsUnit, unit, SOFT) == true then
				plate = GetNamePlate(unit)
				if plate then return unit, plate, L.VIA_SWEEP end
			end
		end
	end
	if exists then return SOFT, nil, L.VIA_DIRECT end
	return nil, nil, nil, true
end

---------------------------------------------------------------------------
-- Lueur
---------------------------------------------------------------------------

-- Donne à une couche une image de l'addon ; à défaut, une texture du jeu. Renvoie false si
-- l'image manque.
local function LoadImage(texture, file)
	if texture:SetTexture(MEDIA .. file .. ".tga") == false then
		texture:SetTexture(FALLBACK_TEXTURE)
		return false
	end
	return true
end

-- Renvoie la couche, et si son image a été trouvée
local function NewLayer(parent, file, drawLayer, subLevel, blendMode)
	local texture = parent:CreateTexture(nil, drawLayer, nil, subLevel)
	local found = LoadImage(texture, file)
	texture:SetBlendMode(blendMode or "ADD")
	texture:SetPoint("CENTER")
	texture:SetVertexColor(1, 1, 1, 0)
	-- positions et tailles animées au sous-pixel : pas d'accrochage à la grille
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
	return texture, found
end

local silhouette = {}     -- owner, mask, outline, applied, show, failed (nom du texte qui dit pourquoi elle est indisponible)

-- Crée les couches d'un effet, et celles de ses ondes
local function BuildEffect(effect)
	local fx = { waves = {} }
	effect.fx, effect.layers = fx, {}
	local function Layer(...)
		local texture, found = NewLayer(glow.frame, ...)
		if not found then effect.missing = true end
		effect.layers[#effect.layers + 1] = texture
		glow.layers[#glow.layers + 1] = texture
		if silhouette.applied then pcall(texture.AddMaskTexture, texture, silhouette.mask) end
		return texture
	end
	effect.Build(fx, Layer)
	if effect.wave then
		for i = 1, 2 do fx.waves[i] = { texture = Layer(effect.wave, "BORDER") } end
	end
end

-- Renvoie l'effet à dessiner : celui de la catégorie de l'objet, construit à son premier usage,
-- ou l'effet de secours si ses images manquent. Quand il change, ses couches remplacent celles
-- du précédent.
local function UseEffect()
	local effect = EFFECTS[Look(glow.category, "effect")]
	if not effect.fx then BuildEffect(effect) end
	if effect.missing then
		effect = EFFECTS.fallback
		if not effect.fx then BuildEffect(effect) end
	end
	if effect ~= glow.effect then
		if glow.effect then
			for _, texture in ipairs(glow.effect.layers) do texture:Hide() end
		end
		for _, texture in ipairs(effect.layers) do texture:Show() end
		for _, wave in ipairs(effect.fx.waves) do
			wave.age = nil
			Tint(wave.texture, 1, 1, 1, 0)
		end
		glow.effect = effect
	end
	return effect
end

-- Lance une onde : un anneau qui s'élargit en s'éteignant, ou qui se resserre sur la lueur
local function StartWave(from, to, duration, peak, inward)
	local chosen
	for _, wave in ipairs(glow.effect.fx.waves) do
		if not wave.age then chosen = wave break end
		if not chosen or wave.age > chosen.age then chosen = wave end
	end
	if not chosen then return end
	chosen.age, chosen.from, chosen.to = 0, from, to
	chosen.duration, chosen.peak, chosen.inward = duration, peak, inward
end

local function SetState(state)
	if state == glow.state then return end
	if state == "ready" then
		-- verrouillage : un anneau se resserre sur la lueur, qui s'illumine un instant
		glow.flash = 1
		StartWave(1.50, 1.00, 0.35, 0.9, true)
	end
	glow.state = state
end

-- Mémorise la position de la lueur à l'écran, pour pouvoir la dissiper sur place quand sa
-- nameplate disparaît. Certaines mesures sont interdites ou secrètes selon le contexte.
local function CachePosition(frame)
	glow.gx = nil
	if glow.measureFailed then return end
	local ok, x, y = pcall(frame.GetCenter, frame)
	local okScale, scale = pcall(frame.GetEffectiveScale, frame)
	if not ok or not okScale then glow.measureFailed = true return end
	local uiScale = UIParent:GetEffectiveScale()
	-- une valeur secrète ne se teste même pas : on l'écarte avant tout autre examen
	if IsSecret(x) or IsSecret(y) or IsSecret(scale) or IsSecret(uiScale) then return end
	if not x or not y or not scale or uiScale == 0 then return end
	local ratio = scale / uiScale
	glow.gx, glow.gy, glow.gscale = x * ratio, y * ratio, ratio
end

local context = {}  -- ce que l'effet reçoit à chaque image, réutilisé de l'une à l'autre

local function Animate(self, elapsed)
	if elapsed > 0.1 then elapsed = 0.1 end -- pas de saut après un gel d'image
	local effect = UseEffect()
	local fx, c = effect.fx, context

	glow.appear = Approach(glow.appear, 1, elapsed / APPEAR_TIME)
	glow.ready  = Approach(glow.ready, glow.state == "ready" and 1 or 0, elapsed / BLEND_TIME)
	glow.locked = Approach(glow.locked, glow.state == "locked" and 1 or 0, elapsed / BLEND_TIME)
	glow.flash  = max(glow.flash - elapsed / FLASH_TIME, 0)
	local blend = min(elapsed * 8, 1)
	glow.r = Lerp(glow.r, glow.targetR, blend)
	glow.g = Lerp(glow.g, glow.targetG, blend)
	glow.b = Lerp(glow.b, glow.targetB, blend)

	local ready, locked = glow.ready, glow.locked
	-- respiration et mouvement, plus vifs à portée, ralentis sur un objet indisponible
	glow.phase = glow.phase + elapsed * TWO_PI / Lerp(3.4, 1.7, ready)
	glow.spin = glow.spin - elapsed * Lerp(0.55, 1.6, ready) * (1 - 0.7 * locked)

	c.frame, c.elapsed, c.size = self, elapsed, Look(glow.category, "size")
	c.arrive = 1 - (1 - glow.appear) ^ 3            -- 0 -> 1 en décélérant
	-- sur un objet indisponible la lueur faiblit de moitié, ou s'éteint si le joueur l'a demandé
	local dim = db.hideLocked and 1 or 0.5
	c.alpha = c.arrive * Look(glow.category, "intensity") / 100 * (1 - dim * locked)
	c.ready, c.locked, c.flash, c.phase, c.spin = ready, locked, glow.flash, glow.phase, glow.spin
	c.breath = 0.5 + 0.5 * sin(glow.phase)
	c.twinkle = 0.5 + 0.5 * sin(glow.phase * 2.3 + 1.3)
	-- couleur : éteinte vers le gris sur un objet indisponible, tirée vers le blanc pour les
	-- traits fins (h) et plus encore pour le cœur des éclats (w)
	local r = Lerp(glow.r, 0.62, 0.75 * locked)
	local g = Lerp(glow.g, 0.62, 0.75 * locked)
	local b = Lerp(glow.b, 0.62, 0.75 * locked)
	c.r, c.g, c.b = r, g, b
	c.hr, c.hg, c.hb = Lerp(r, 1, 0.55), Lerp(g, 1, 0.55), Lerp(b, 1, 0.55)
	c.wr, c.wg, c.wb = Lerp(r, 1, 0.75), Lerp(g, 1, 0.75), Lerp(b, 1, 0.75)

	effect.Update(fx, c)

	-- ondes : un "ping" régulier vers l'extérieur, qui se tait sur un objet indisponible
	glow.nextPing = glow.nextPing - elapsed
	if glow.nextPing <= 0 then
		glow.nextPing = Lerp(2.4, 3.8, ready)
		if glow.state ~= "locked" and effect.ping ~= false then StartWave(0.55, 1.45, 1.0, 0.55) end
	end
	local base, flat, gain = fx.waveSize or c.size, effect.flat or 1, c.alpha * (effect.waveGain or 1)
	for _, wave in ipairs(fx.waves) do
		if wave.age then
			wave.age = wave.age + elapsed
			local progress = wave.age / wave.duration
			if progress >= 1 then
				wave.age = nil
				Tint(wave.texture, 1, 1, 1, 0)
			else
				local fade
				if wave.inward then
					fade = progress < 0.7 and progress / 0.7 or (1 - progress) / 0.3
				else
					fade = (1 - progress) ^ 1.5
				end
				local width = base * Lerp(wave.from, wave.to, 1 - (1 - progress) ^ 2)
				Sized(wave.texture, width, width * flat)
				if fx.waveY then Place(wave.texture, self, 0, fx.waveY) end
				if fx.waveAngle then wave.texture:SetRotation(fx.waveAngle) end
				Tint(wave.texture, c.hr, c.hg, c.hb, gain * wave.peak * fade)
			end
		end
	end

	if label and label:IsShown() then
		-- le nom reste lisible quelle que soit l'intensité : il ne suit que l'arrivée et l'état
		label:SetAlpha(c.arrive * (1 - (db.hideLocked and 1 or 0.4) * locked))
		label.name:SetTextColor(c.hr, c.hg, c.hb)
	end

	CachePosition(self)
end

local function CreateGlow()
	local frame = CreateFrame("Frame")
	frame:SetSize(1, 1)
	frame:Hide()
	frame:SetScript("OnUpdate", Animate)
	glow.frame = frame
	return frame
end

---------------------------------------------------------------------------
-- Nom et icône de l'objet
---------------------------------------------------------------------------

-- Le jeu écrit le nom de sa cible d'interaction sur sa nameplate, sous une icône. Sur la
-- nameplate qui porte la lueur, Lueur les masque et dessine les siens à la même place : ils
-- se règlent, prennent la couleur de la catégorie, et l'aperçu les montre tels quels.
local function CreateLabel()
	label = CreateFrame("Frame", nil, glow.frame)
	label:SetSize(1, 1)
	label.icon = label:CreateTexture(nil, "OVERLAY")
	label.icon:SetSize(22, 22)
	label.name = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label.name:SetPoint("CENTER", label, "CENTER", 0, 0)
	-- la police du jeu : la taille du texte se règle à partir de la sienne
	label.font, label.height, label.flags = label.name:GetFont()
	return label
end

-- Montre le nom et l'icône de l'objet à l'endroit de sa nameplate, ou les retire selon les
-- réglages. L'icône est celle que le jeu donne à l'unité ; sans unité (aperçu), celle de la
-- catégorie. Elle se pose sur le nom, ou à sa place quand il n'est pas écrit.
local function ShowLabel(unit, name, category)
	local showName, showIcon = Look(category, "showName"), Look(category, "showIcon")
	if not glow.anchor or not (showName or showIcon) or glow.Bare() then
		if label then label:Hide() end
		return
	end
	local frame = label or CreateLabel()
	local hasIcon = false
	if showIcon and unit then
		hasIcon = SafeCall(SetUnitCursorTexture, frame.icon, unit, nil, true) == true
	elseif showIcon then
		hasIcon = frame.icon:SetTexture(CURSORS .. (SAMPLE_CURSOR[category] or SAMPLE_CURSOR.other)) ~= false
	end
	frame.icon:SetShown(hasIcon)
	frame.name:SetText(name or "")
	frame.name:SetShown(showName)
	frame.icon:ClearAllPoints()
	if showName then
		local height = frame.height or 12
		if frame.font then
			height = height * Look(category, "textSize") / 100
			-- une police que le client refuserait laisse place à celle du jeu
			local file, ok, done = ns.FontFile(Look(category, "textFont"))
			if file then ok, done = pcall(frame.name.SetFont, frame.name, file, height, frame.flags) end
			if not (ok and done ~= false) then frame.name:SetFont(frame.font, height, frame.flags) end
		end
		frame.icon:SetPoint("BOTTOM", frame, "CENTER", 0, height / 2 + 2)
	else
		frame.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end
	if frame.anchor ~= glow.anchor then
		frame.anchor = glow.anchor
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", glow.anchor, "CENTER", 0, 0)
	end
	frame:Show()
end

-- L'icône d'interaction du jeu (SoftTargetFrame) quand une interface l'a sortie du cadre de la
-- nameplate pour la poser sur la nameplate même : masquer ce cadre ne la masque plus. EllesmereUI
-- (9.8.3, EllesmereUINameplatesFriendly.lua) le fait pour les PNJ amicaux et les objets du décor quand
-- ses nameplates de PNJ amicaux sont allumées. Rangée dans `glow` : ce fichier est à la limite de
-- Lua 5.1 en variables locales.
function glow.Detached(unitFrame)
	local ok, icon = pcall(function() return unitFrame.SoftTargetFrame end)
	if not ok or type(icon) ~= "table" or IsSecret(icon) then return nil end
	-- (dans le jeu, elle est un enfant du cadre : Blizzard_NamePlates.xml, build 70245)
	local frame = icon
	for _ = 1, 6 do
		local fine, parent = pcall(frame.GetParent, frame)
		if not fine or IsSecret(parent) then return nil end
		if parent == nil then return icon end
		if parent == unitFrame then return nil end
		frame = parent
	end
	return icon
end

-- Masque un cadre de la nameplate et le retient dans glow[field], avec son opacité ; rend celui qui y
-- était s'il en change (rien, faute de cadre)
function glow.Veil(field, frame)
	local held = glow[field]
	if held and held.frame ~= frame then
		pcall(held.frame.SetAlpha, held.frame, held.alpha)
		glow[field] = nil
	end
	if not frame or glow[field] then return end
	local ok, alpha = pcall(frame.GetAlpha, frame)
	if not ok or IsSecret(alpha) or type(alpha) ~= "number" or alpha == 0 then alpha = 1 end
	if pcall(frame.SetAlpha, frame, 0) then glow[field] = { frame = frame, alpha = alpha } end
end

-- Rend au jeu l'affichage de la nameplate que la lueur vient de quitter
local function RestoreNative()
	if glow.native then
		pcall(glow.native.SetAlpha, glow.native, 1)
		glow.native = nil
	end
	glow.Veil("nativeIcon", nil)
end

-- Masque ce que le jeu dessine sur la nameplate qui porte la lueur. Le cadre masqué est gardé :
-- le jeu le recycle pour d'autres unités, et c'est lui qu'il faudra rétablir.
local function HideNative(plate)
	local ok, unitFrame = pcall(function() return plate.UnitFrame end)
	if not ok or type(unitFrame) ~= "table" then unitFrame = nil end
	if unitFrame ~= glow.native then RestoreNative() end
	if unitFrame and pcall(unitFrame.SetAlpha, unitFrame, 0) then glow.native = unitFrame end
	glow.Veil("nativeIcon", unitFrame and glow.Detached(unitFrame))
end

-- Plumber (1.9.7, Modules\SoftTargetName.lua) écrit lui-même le nom de la cible d'interaction, avec
-- l'objectif de quête et une barre d'incantation, dans un cadre posé sur sa nameplate sous l'icône du
-- jeu, quand son module « Nameplate: Soft Target » est allumé ; et rien quand le jeu ne donne pas de
-- nameplate. Avec lui, Lueur ne met que sa lumière (glow.Bare) et laisse le jeu montrer toutes les
-- cibles (glow.Exclusive). Signalé le 2026-11-09 (Threed : « Perhaps an option to only use the shiny
-- part and nothing else? »). Son module se lit dans PlumberDB, que Plumber lit lui-même (GetDBBool).
-- (Plumber se charge après Lueur : seul un oui se retient.)
function glow.Plumber()
	if not glow.plumber then
		glow.plumber = C_AddOns ~= nil and C_AddOns.IsAddOnLoaded ~= nil and SafeCall(C_AddOns.IsAddOnLoaded, "Plumber") == true
	end
	return glow.plumber and type(PlumberDB) == "table" and PlumberDB.SoftTargetName == true
end

-- La lumière seule : ni le nom ni l'icône de Lueur, et ce que le jeu ou un autre addon met sur la
-- nameplate reste
function glow.Bare()
	return db.glowOnly == true or glow.Plumber()
end

-- Le jeu ne montre-t-il que les cibles mises en lumière ?
function glow.Exclusive()
	return db.exclusive and not glow.Plumber()
end

-- En combat le jeu ne laisse plus toucher aux CVars, et l'affichage natif a été ouvert juste avant
-- pour que la lueur y paraisse encore (PLAYER_REGEN_DISABLED) : le jeu donne alors une nameplate à
-- toute cible d'interaction, PNJ et cadavres compris, avec leur barre de vie. Celle d'une cible que
-- Lueur n'éclaire pas est donc masquée de la même façon, le temps qu'elle est la cible (`muted`).
-- (Signalé le 2026-10-13 : « certains nameplates de pnj apparaissent en combat avec l'addon, des
-- barres de vies notamment, cela ne devrait pas ».)
local muted

local function Unmute()
	-- (l'icône sortie du cadre que la lueur porte désormais : c'est HideNative qui la tient masquée)
	if glow.mutedIcon and not (glow.nativeIcon and glow.nativeIcon.frame == glow.mutedIcon.frame) then glow.Veil("mutedIcon", nil) end
	glow.mutedIcon = nil
	if not muted then return end
	-- (le même cadre porte la lueur désormais : c'est HideNative qui le tient masqué)
	if muted ~= glow.native then pcall(muted.SetAlpha, muted, 1) end
	muted = nil
end

local function Mute(plate)
	local ok, unitFrame = pcall(function() return plate.UnitFrame end)
	if not ok or type(unitFrame) ~= "table" then unitFrame = nil end
	if unitFrame ~= muted then Unmute() end
	if unitFrame and pcall(unitFrame.SetAlpha, unitFrame, 0) then muted = unitFrame end
	glow.Veil("mutedIcon", unitFrame and glow.Detached(unitFrame))
end

-- Les réglages du joueur montreraient-ils la nameplate de cette unité sans qu'elle soit la cible
-- d'interaction ? Celle d'un objet du décor ou d'un mort, jamais. Pour les autres, c'est la CVar de
-- leur camp qui le dit ; faute de pouvoir la lire, ou de savoir le camp, la nameplate est laissée.
local PLATE_CVARS = {
	enemy = { "nameplateShowEnemies" },
	player = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" },
	npc = { "nameplateShowFriendlyNpcs", "nameplateShowFriends" },
}

local function PlateOwed(unit)
	if SafeCall(UnitIsGameObject, unit) == true then return false end
	if UnitIsDead and SafeCall(UnitIsDead, unit) == true then return false end
	local hostile = UnitCanAttack and SafeCall(UnitCanAttack, "player", unit)
	if hostile == nil then return true end
	local names = PLATE_CVARS[hostile and "enemy" or (UnitIsPlayer and SafeCall(UnitIsPlayer, unit) == true) and "player" or "npc"]
	local known = false
	for _, name in ipairs(names) do
		local value = GetCVarValue(name)
		if value == "1" then return true end
		known = known or value ~= nil
	end
	return not known
end

-- La cible n'est pas mise en lumière : l'affichage natif se referme. S'il ne le peut pas (en
-- combat), renvoie la nameplate à masquer, sauf en mode non exclusif ou si le joueur la montre de
-- toute façon.
local function Shut(unit, plate)
	SetGate(false)
	if plate and glow.Exclusive() and gateOpen ~= false and not PlateOwed(unit) then return plate end
end

local function CreateGhost()
	ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("BACKGROUND")
	ghost:SetSize(1, 1)
	ghost:Hide()
	ghost.band = NewLayer(ghost, "halo", "BACKGROUND")
	ghost.ring = NewLayer(ghost, "ring", "BORDER")
	ghost:SetScript("OnUpdate", function(self, elapsed)
		self.age = self.age + elapsed
		local progress = self.age / GHOST_TIME
		if progress >= 1 then self:Hide() return end
		local size = self.size * (1 + 0.35 * (1 - (1 - progress) ^ 3))
		local fade = self.alpha * (1 - progress) ^ 2
		Sized(self.band, size * self.spread, size * self.spread * self.flat)
		Tint(self.band, self.r, self.g, self.b, 0.7 * fade)
		Sized(self.ring, size, size * self.flat)
		Tint(self.ring, Lerp(self.r, 1, 0.55), Lerp(self.g, 1, 0.55), Lerp(self.b, 1, 0.55), self.ringed and fade or 0)
	end)
	return ghost
end

-- Dissipation sur place : la lueur s'élargit et s'éteint là où elle se trouvait, sous les
-- traits de son effet (sa lueur, l'anneau de ses ondes)
local function PlayGhost()
	local effect = glow.effect
	-- pas dans l'aperçu : la dissipation se joue sur l'écran, sous la fenêtre qui le montre
	if not glow.gx or glow.preview or effect == EFFECTS.fallback or glow.appear < 0.3 then return end
	local frame = ghost or CreateGhost()
	if frame.effect ~= effect then
		frame.effect = effect
		LoadImage(frame.band, effect.band or "glow")
		LoadImage(frame.ring, effect.wave or "ring")
	end
	local fx = effect.fx
	frame.spread = effect.band and 1 or 1.5  -- une simple lueur n'occupe que le centre de son image
	frame.flat, frame.ringed = effect.flat or 1, effect.wave ~= nil
	frame.ring:SetRotation(fx.waveAngle or 0)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", glow.gx, glow.gy + (fx.waveY or 0) * glow.gscale)
	frame.size = (fx.waveSize or Look(glow.category, "size")) * glow.gscale
	frame.r, frame.g, frame.b = glow.r, glow.g, glow.b
	frame.alpha = Look(glow.category, "intensity") / 100 * (1 - (db.hideLocked and 1 or 0.5) * glow.locked)
	frame.age = 0
	frame:Show()
end

---------------------------------------------------------------------------
-- Silhouette
---------------------------------------------------------------------------

-- L'interface se dessine toujours par-dessus le monde : un addon ne peut rien faire passer
-- derrière un modèle 3D. On triche pour le personnage du joueur, seul modèle dont la place
-- à l'écran se déduit sans mesure : la caméra vise sa tête, et sa taille ne dépend que du
-- zoom. Un masque en ellipse y découpe la lueur, qui semble alors passer derrière lui.
local BODY_HEIGHT = 1.9   -- hauteur du personnage en hauteurs d'écran, caméra à 1 m, champ de vision par défaut

local function Smoothstep(low, high, value)
	local t = Clamp((value - low) / (high - low), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Renvoie la largeur et la hauteur du personnage à l'écran, et la position de ses pieds par
-- rapport au centre de l'écran (unités de l'interface) ; nil en vue subjective
local function MeasureBody()
	local zoom = GetCameraZoom and SafeCall(GetCameraZoom)
	if not zoom or zoom < 2 then return nil end
	local fov = tonumber(GetCVarValue("cameraFov")) or 90
	local height = BODY_HEIGHT * UIParent:GetHeight() / zoom / math.tan(math.rad(fov / 2)) * cdb.bodyScale / 100
	local width = height * 0.45
	if IsMounted and SafeCall(IsMounted) == true then
		height = height * 1.3
		width = height * 0.8
	end
	-- vu d'en haut, le corps paraît raccourci et tient presque entier sous le centre de l'écran
	height = height * 0.9
	return width, height, (cdb.bodyShift / 100 - 0.92) * height
end

local function UpdateSilhouette()
	local mask, outline = silhouette.mask, silhouette.outline
	local width, height, feet = MeasureBody()
	if not width then
		mask:SetSize(0.01, 0.01)
		outline:Hide()
		return
	end
	-- la découpe ne vaut que si l'objet est plus loin que le personnage, donc plus haut à
	-- l'écran que ses pieds ; plus près de la caméra, c'est à la lueur de le recouvrir
	local strength = 1
	if glow.preview then
		strength = 0 -- l'aperçu se joue dans sa fenêtre, où le personnage n'est pas
	elseif glow.anchor and glow.gx then
		strength = Smoothstep(feet - 0.10 * height, feet + 0.20 * height, glow.gy - UIParent:GetHeight() / 2)
	end
	local centerY = feet + height / 2
	local maskWidth, maskHeight = width * 1.9, height * 1.5
	mask:SetSize(max(maskWidth * strength, 0.01), max(maskHeight * strength, 0.01))
	mask:SetPoint("CENTER", silhouette.owner, "CENTER", 0, centerY)
	if silhouette.show then
		-- contour de la zone entièrement masquée : le cœur du masque en occupe 55 %, et
		-- l'anneau qui le dessine est à 74 % de sa texture
		outline:SetSize(maskWidth * 0.55 / 0.74, maskHeight * 0.55 / 0.74)
		outline:SetPoint("CENTER", silhouette.owner, "CENTER", 0, centerY)
		outline:Show()
	else
		outline:Hide()
	end
end

local function CreateSilhouette()
	local owner = CreateFrame("Frame", nil, UIParent)
	owner:SetSize(1, 1)
	owner:SetPoint("CENTER", WorldFrame or UIParent, "CENTER", 0, 0)
	owner:Hide()
	local ok, mask = pcall(owner.CreateMaskTexture, owner)
	if not ok or not mask then
		silhouette.failed = "FAIL_NO_MASK"
		return
	end
	-- hors du masque, "blanc" : la lueur n'est entamée que dans l'ellipse
	local set, loaded = pcall(mask.SetTexture, mask, MEDIA .. "hole.tga", "CLAMPTOWHITE", "CLAMPTOWHITE")
	if not set or loaded == false then
		silhouette.failed = "FAIL_MASK_TEXTURE"
		return
	end
	mask:SetSize(0.01, 0.01)
	mask:SetPoint("CENTER", owner, "CENTER", 0, 0)
	local outline = owner:CreateTexture(nil, "OVERLAY")
	outline:SetTexture(MEDIA .. "ring.tga")
	outline:SetVertexColor(1, 0.25, 0.25, 0.9)
	outline:Hide()
	silhouette.owner, silhouette.mask, silhouette.outline = owner, mask, outline
	owner:SetScript("OnUpdate", UpdateSilhouette)
end

-- Pose ou retire la découpe sur les couches de la lueur, selon le réglage et son état
local function ApplySilhouette()
	-- la découpe se règle par catégorie : c'est celle de l'objet que porte la lueur qui compte
	local wanted = Look(glow.anchor and glow.category, "silhouette") and not silhouette.failed
	if not (wanted or silhouette.show or silhouette.applied) then return end
	if not silhouette.owner and not silhouette.failed then CreateSilhouette() end
	if not silhouette.owner then return end
	if glow.frame and wanted ~= (silhouette.applied == true) then
		local method = wanted and "AddMaskTexture" or "RemoveMaskTexture"
		for _, texture in ipairs(glow.layers) do
			if not pcall(texture[method], texture, silhouette.mask) then
				silhouette.failed = "FAIL_MASK_REFUSED"
				break
			end
		end
		if silhouette.failed then
			for _, texture in ipairs(glow.layers) do pcall(texture.RemoveMaskTexture, texture, silhouette.mask) end
			wanted = false
		end
		silhouette.applied = wanted
	end
	if (silhouette.applied and glow.anchor) or silhouette.show then
		silhouette.owner:Show()
	else
		silhouette.owner:Hide()
	end
end

local function Release()
	RestoreNative()
	if not glow.anchor then return end
	-- (l'aperçu de la fenêtre des réglages garde la lueur tant que le jeu ne désigne rien à éclairer : voir Evaluate)
	if glow.held and glow.preview then return end
	PlayGhost()
	glow.frame:Hide()
	glow.frame:ClearAllPoints()
	glow.frame:SetParent(nil)
	if label then
		label:Hide()
		label:ClearAllPoints()
		label.anchor = nil
	end
	glow.anchor, glow.preview, glow.retarget, glow.gx = nil, nil, nil, nil
	ApplySilhouette()
end

-- Accroche la lueur à un cadre (la nameplate de la cible, ou celle que simule l'aperçu), au
-- décalage réglé, et relance son animation d'arrivée
local function Attach(anchor, category, state)
	local frame = glow.frame or CreateGlow()
	frame:SetParent(anchor)
	-- sous le contenu de la nameplate, pour ne pas laver son texte
	local ok, level = pcall(anchor.GetFrameLevel, anchor)
	if ok and not IsSecret(level) and level then frame:SetFrameLevel(max(level - 1, 0)) end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", anchor, "CENTER", 0, Look(category, "offsetY"))
	frame:SetIgnoreParentAlpha(not Look(category, "followAlpha"))

	glow.anchor, glow.category = anchor, category
	glow.state, glow.pending = state, nil
	glow.ready  = state == "ready" and 1 or 0
	glow.locked = state == "locked" and 1 or 0
	glow.r, glow.g, glow.b = Color(category)
	glow.targetR, glow.targetG, glow.targetB = glow.r, glow.g, glow.b
	glow.appear, glow.flash, glow.phase, glow.nextPing = 0, 0, 0, 1.6
	glow.spin = math.random() * TWO_PI
	for _, wave in ipairs(UseEffect().fx.waves) do
		wave.age = nil
		Tint(wave.texture, 1, 1, 1, 0)
	end
	StartWave(0.50, 1.50, 0.9, 0.8)
	frame:Show()
	ApplySilhouette()
end

-- Un nouvel état n'est affiché qu'une fois stable, pour ne pas scintiller à la limite de portée
local function ProposeState(state)
	if state == glow.state then glow.pending = nil return end
	local now = GetTime()
	if glow.pending ~= state then
		glow.pending, glow.pendingSince = state, now
	elseif now - glow.pendingSince >= (state == "locked" and LOCK_DELAY or STATE_DELAY) then
		glow.pending = nil
		SetState(state)
	end
end

local function Present(plate, unit, name, category, state)
	-- une nameplate qui change de catégorie se traite comme une autre cible : effet, taille,
	-- décalage et couleur peuvent tous changer avec elle
	if glow.anchor ~= plate or glow.retarget or glow.category ~= category then
		glow.held = nil -- une vraie cible : l'aperçu de la fenêtre des réglages lui cède la lueur
		Release()
		Attach(plate, category, state)
	else
		glow.targetR, glow.targetG, glow.targetB = Color(category)
		ProposeState(state)
	end
	-- (la lumière seule : ce que le jeu ou un autre addon met sur la nameplate y reste)
	if glow.Bare() then RestoreNative() else HideNative(plate) end
	ShowLabel(unit, name, category)
end

-- Prototype de la lueur au loin (NodeScan.lua, fin du fichier) : quand le jeu ne désigne rien que
-- Lueur éclaire (rien, un PNJ, le familier, un objet écarté), la lueur se pose sur un nœud de la
-- minimap droit devant, sinon elle s'en va. Rangée dans `glow` : ce fichier est à la limite de Lua 5.1
-- en variables locales. Une cible du jeu qui change ne la relance pas : elle n'en dépend pas.
function glow.Elsewhere()
	local anchor, name, kind = ns.FarGlow and ns.FarGlow()
	if not anchor then
		Release()
		return
	end
	if glow.anchor == anchor then glow.retarget = nil end
	Present(anchor, nil, name, kind, "far")
end

---------------------------------------------------------------------------
-- Évaluation
---------------------------------------------------------------------------

local function Flag(value)
	if value == nil then return "?" end
	return value and L.YES or L.NO
end

local function Report(line, detail)
	if not db.debug or line == lastReport then return end
	lastReport = line
	Print(line)
	local text = detail and detail()
	if text and text ~= "" then print("    " .. text) end
end

local function DescribeTarget(unit, name, via, cursor, inRange)
	local parts = { L.DEBUG_CURSOR:format(tostring(cursor)), L.DEBUG_VIA:format(via), L.DEBUG_RANGE:format(Flag(inRange)),
		L.DEBUG_OBJECT:format(tostring(ObjectID(unit) or "?")), L.DEBUG_FISHING:format(Flag(ReadLine())) }
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		parts[#parts + 1] = L.DEBUG_QUEST:format(Flag(SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)))
	end
	-- (un curseur de service : le nom de l'objet n'est pas regardé, et le détail le dit)
	local _, kind = ReadCursor(unit)
	local service = kind == "service" and L.MATCH_CURSOR
	parts[#parts + 1] = L.DEBUG_MATCH:format(service or MatchQuestObjective(name) or L.MATCH_NONE, #questTexts)
	parts[#parts + 1] = L.DEBUG_CHEST:format(service or MatchContainer(ObjectID(unit), name) or L.MATCH_NONE)
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		parts[#parts + 1] = L.DEBUG_SECRET:format(Flag(SafeCall(C_Secrets.ShouldUnitIdentityBeSecret, unit)))
	end
	if C_NamePlateManager and C_NamePlateManager.IsNamePlateUnitBehindCamera then
		parts[#parts + 1] = L.DEBUG_BEHIND:format(Flag(SafeCall(C_NamePlateManager.IsNamePlateUnitBehindCamera, unit)))
	end
	return table.concat(parts, " | ")
end

-- La lueur est-elle suspendue par le contexte : en combat, ou en instance, si le joueur l'a demandé
local function Paused()
	if db.hideInCombat and (inCombat or InCombatLockdown()) then return true end
	return db.hideInInstance and IsInInstance ~= nil and SafeCall(IsInInstance) == true
end

-- Détermine la cible d'interaction courante, puis met en accord avec elle l'affichage natif
-- du jeu (ouvert seulement si elle mérite d'être mise en lumière) et la lueur elle-même.
-- Renvoie la nameplate d'une cible sans lueur que le jeu montre quand même, faute de pouvoir
-- refermer son affichage : Evaluate la masque.
local function Decide()
	if leaving or glow.preview and not glow.preview.soft then return end
	if not db.enabled then Release() return end
	if Paused() then
		Report(L.DEBUG_PAUSED)
		Release()
		local unit, plate = ResolveTarget()
		if unit then return Shut(unit, plate) end
		SetGate(false)
		return
	end

	local unit, plate, via, unknown = ResolveTarget()
	if plate or not unit then glow.plateMissingSince = nil end
	if not unit then
		if lastReport then Report(L.DEBUG_NO_TARGET) end
		SetGate(unknown == true) -- faute de savoir, on laisse le jeu montrer sa cible
		glow.Elsewhere()
		return
	end
	local name = SafeCall(UnitName, unit)
	local label = name or "?"
	-- seuls les objets du décor sont mis en lumière : ni PNJ, ni cadavres
	if SafeCall(UnitIsGameObject, unit) ~= true then
		Report(L.DEBUG_IGNORED:format(label))
		glow.Elsewhere()
		return Shut(unit, plate)
	end
	-- ni les objets que le joueur a écartés par leur nom
	if name and db.ignored[NameKey(name)] then
		Report(L.DEBUG_SKIPPED:format(label))
		glow.Elsewhere()
		return Shut(unit, plate)
	end

	local category, blocked, cursor, id = Classify(unit, name)
	-- un filon ou une plante que le jeu désigne : Nodes.lua en retient le nom, pour le reconnaître sur la minimap
	if name and ns.LearnNode and (category == "ore" or category == "herb") then ns.LearnNode(name, id, category) end
	if id and (category == "ore" or category == "herb") then gathered[id] = true end
	local state, inRange = ReadState(unit, blocked)
	local wanted = category and cdb.categories[category] or false
	if not wanted then
		Report(L.DEBUG_HIDDEN:format(label, CategoryName(category)),
			function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		glow.Elsewhere()
		return Shut(unit, plate)
	end
	-- ni une plante ou un filon que ce personnage ne sait pas récolter (demandé par des joueurs le 2026-10-14)
	if db.hideUntrained and Trained(category) == false then
		Report(L.DEBUG_UNTRAINED:format(label, CategoryName(category)),
			function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		glow.Elsewhere()
		return Shut(unit, plate)
	end
	SetGate(true)
	if not plate then
		-- la nameplate vient d'être demandée au jeu : la lueur s'y posera à son arrivée.
		-- Si elle tarde, c'est que le jeu connaît la cible sans vouloir l'afficher.
		Release()
		local now = GetTime()
		glow.plateMissingSince = glow.plateMissingSince or now
		if now - glow.plateMissingSince > 0.5 then
			Report(L.DEBUG_NO_PLATE:format(label, CategoryName(category)),
				function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		end
		return
	end

	Present(plate, unit, name, category, state)
	Report(L.DEBUG_SHOWN:format(label, CategoryName(category), StateName(glow.state)),
		function() return DescribeTarget(unit, name, via, cursor, inRange) end)
end

-- L'aperçu de la fenêtre des réglages (`soft`) ne retient pas la lueur : dès que le jeu désigne un objet
-- à éclairer, elle va sur lui, et les réglages se jugent sur lui. D'ici là rien de ce que Decide relâche
-- ne la lui prend (`glow.held`, que Release regarde).
function Evaluate()
	glow.held = glow.preview and glow.preview.soft or nil
	local plate = Decide()
	glow.held = nil
	if plate then Mute(plate) else Unmute() end
end

-- Tant que la ligne de pêche est à l'eau, le jeu cherche le flotteur plus loin que la portée du réglage
local function WatchLine()
	local out = db.enabled and cdb.categories.bobber and ReadLine() or false
	if out == lineOut then return end
	lineOut = out
	if ApplyRange() and db.debug then
		Print((out and L.DEBUG_LINE_OUT or L.DEBUG_LINE_IN):format(WantedRange(), tostring(GetCVarValue("SoftTargetInteractRange"))))
	end
end

---------------------------------------------------------------------------
-- Aperçu
---------------------------------------------------------------------------

-- Déroulé de l'aperçu : chaque état, en boucle
local PREVIEW_STAGES = { { "far", 3.0 }, { "ready", 4.5 }, { "locked", 2.5 } }

-- Nom d'objet que l'aperçu montre pour une catégorie
local function SampleName(category)
	return L["SAMPLE_" .. category:upper()]
end

-- Montre la lueur d'une catégorie sur `anchor`, le cadre que l'aperçu place là où le jeu mettrait
-- la nameplate de l'objet, et enchaîne ses états en boucle jusqu'à StopPreview. `soft` : l'aperçu
-- cède la lueur à la première vraie cible (voir Evaluate).
local function StartPreview(anchor, category, soft)
	glow.held = nil
	Release()
	if not soft then Unmute() end
	Attach(anchor, category, "far")
	glow.preview = { stage = 1, left = PREVIEW_STAGES[1][2], soft = soft or nil }
	ShowLabel(nil, SampleName(category), category)
end

local function StopPreview()
	glow.held = nil
	if glow.preview then Release() end
end

local function UpdatePreview(elapsed)
	local preview = glow.preview
	preview.left = preview.left - elapsed
	if preview.left > 0 then return end
	preview.stage = preview.stage + 1
	local stage = PREVIEW_STAGES[preview.stage]
	if not stage then
		StartPreview(glow.anchor, glow.category, preview.soft)
		return
	end
	SetState(stage[1])
	preview.left = stage[2]
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local sincePoll = 0

events:SetScript("OnUpdate", function(_, elapsed)
	if not db or leaving then return end
	if glow.preview then
		UpdatePreview(elapsed)
		if not (glow.preview and glow.preview.soft) then return end
	end
	sincePoll = sincePoll + elapsed
	if sincePoll >= POLL_INTERVAL then
		sincePoll = 0
		WatchLine()
		EnsureIconCVars()
		Evaluate()
	end
end)

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	LueurDB = LueurDB or {}
	db = LueurDB
	if db.schema ~= SCHEMA then
		local from = db.schema or 1
		if from < 2 then db.size = nil end -- le halo a changé de nature : l'ancienne taille n'a plus le même sens
		if from < 3 then RepairSavedCVars() end
		if from < 4 then
			-- les styles du halo sont devenus des effets parmi d'autres ; cadavres à dépecer et
			-- butin ne sont plus mis en lumière
			db.effect, db.style = db.effect or LEGACY_STYLES[db.style], nil
			if type(db.categories) == "table" then db.categories.skin, db.categories.loot = nil, nil end
		end
		if from < 5 then
			-- catégories et découpe deviennent propres à chaque personnage : celles du compte sont
			-- mises de côté, et chaque personnage en hérite à sa première connexion. Les coffres,
			-- jusque-là rangés parmi les autres objets, les suivent.
			if type(db.categories) == "table" then
				db.inherited = { categories = db.categories, bodyScale = db.bodyScale, bodyShift = db.bodyShift }
				db.inherited.categories.chest = db.showOther == true
				db.inherited.categories.other = db.showOther == true
			end
			db.categories, db.showOther, db.bodyScale, db.bodyShift = nil, nil, nil, nil
		end
		if from < 6 and type(db.categoryEffects) == "table" then
			-- l'effet propre à une catégorie n'est plus qu'un de ses réglages de personnalisation
			db.categorySettings = type(db.categorySettings) == "table" and db.categorySettings or {}
			for category, effect in pairs(db.categoryEffects) do
				if type(db.categorySettings[category]) ~= "table" then db.categorySettings[category] = {} end
				db.categorySettings[category].effect = effect
			end
		end
		db.categoryEffects = nil
		if from < 7 then
			-- le nom et l'icône de l'objet, d'abord réglés ensemble, se règlent chacun à part
			local function Split(store)
				if type(store) ~= "table" then return end
				if type(store.showLabel) == "boolean" then store.showName, store.showIcon = store.showLabel, store.showLabel end
				store.showLabel = nil
			end
			Split(db)
			if type(db.categorySettings) == "table" then
				for _, own in pairs(db.categorySettings) do Split(own) end
			end
		end
		if from < 8 then
			-- les majuscules cyrilliques se replient désormais en minuscules : les noms retenus sous
			-- leur ancienne clé passent sous la nouvelle
			local function Rekey(store)
				if type(store) ~= "table" then return end
				local moved = {}
				for key, value in pairs(store) do
					if type(key) == "string" and NameKey(key) ~= key then moved[key] = value end
				end
				for key, value in pairs(moved) do
					store[key] = nil
					if store[NameKey(key)] == nil then store[NameKey(key)] = value end
				end
			end
			Rekey(db.ignored)
			if type(db.nodeNames) == "table" then
				for _, names in pairs(db.nodeNames) do Rekey(names) end
			end
		end
		if from < 9 then
			-- deux effets s'en vont (2026-11-09) : le Réticule, un dosage de l'Aura, et le Viseur, que
			-- remplace le Tourbillon ; qui les portait reçoit ce qui leur ressemble le plus
			local retired = { reticle = "aura", brackets = "sigil" }
			local function Replace(store)
				if type(store) ~= "table" then return end
				store.effect = retired[store.effect] or store.effect
			end
			Replace(db)
			if type(db.categorySettings) == "table" then
				for _, own in pairs(db.categorySettings) do Replace(own) end
			end
		end
		if from < 10 then
			-- les icônes de la minimap s'éteignent d'office (1.6.1) : celles qu'une version d'avant avait
			-- allumées sans qu'on le lui demande s'éteignent une fois, et le joueur en est prévenu à la
			-- connexion ; qui les veut les rallume, et elles restent
			if db.nodeHerbs or db.nodeOre then db.nodesOffNotice = true end
			if db.nodeHerbs ~= nil then db.nodeHerbs = false end
			if db.nodeOre ~= nil then db.nodeOre = false end
		end
		db.schema = SCHEMA
	end
	CopyDefaults(DEFAULTS, db)
	LueurCharDB = LueurCharDB or {}
	cdb = LueurCharDB
	if next(cdb) == nil and type(db.inherited) == "table" then CopyDefaults(db.inherited, cdb) end
	CopyDefaults(CHAR_DEFAULTS, cdb)

	if not EFFECTS[db.effect] or db.effect == "fallback" then db.effect = DEFAULTS.effect end
	if not ns.IsFont(db.textFont) then db.textFont = DEFAULTS.textFont end
	-- réglages propres aux catégories : seuls restent ceux qui ont un sens
	for category, own in pairs(db.categorySettings) do
		if not DEFAULTS.colors[category] or type(own) ~= "table" then
			db.categorySettings[category] = nil
		else
			for key, value in pairs(own) do
				local limits = LIMITS[key]
				if not LOOK[key] or type(value) ~= type(DEFAULTS[key]) or (key == "effect" and (not EFFECTS[value] or value == "fallback"))
					or (key == "textFont" and not ns.IsFont(value)) then
					own[key] = nil
				elseif limits then
					own[key] = Clamp(value, limits[1], limits[2]) + 0
				end
			end
			if next(own) == nil then db.categorySettings[category] = nil end
		end
	end
	for category, default in pairs(DEFAULTS.colors) do
		local color = db.colors[category]
		for index = 1, 3 do
			color[index] = type(color[index]) == "number" and Clamp(color[index], 0, 1) or default[index]
		end
	end
	if not ns.LOCALES[db.language] then db.language = DEFAULTS.language end
	UseLanguage()
	for key, limits in pairs(LIMITS) do
		local store = Store(key)
		if type(store[key]) == "number" then
			-- "+ 0" : Lua 5.1 relit en -0 les zéros d'un fichier de réglages qui contient un -0, et l'afficherait tel quel
			store[key] = Clamp(store[key], limits[1], limits[2]) + 0
		else
			store[key] = DEFAULTS[key] or CHAR_DEFAULTS[key]
		end
	end
	probe = UIParent:CreateTexture(nil, "BACKGROUND")
	probe:Hide()
	BuildCursorLookup()
	events:UnregisterEvent("ADDON_LOADED")
	ns.db = db
	if ns.SetupInterface then ns.SetupInterface() end -- Menu.lua : bouton de la minimap
end

function handlers.PLAYER_LOGIN()
	if db.enabled then ApplyCVars() end
	if db.nodesOffNotice then
		db.nodesOffNotice = nil
		Print(L.MSG_NODES_OFF)
	end
end

-- Les réglages synchronisés avec le compte peuvent arriver après PLAYER_LOGIN et
-- écraser nos valeurs : on les réapplique à ces moments-là.
function handlers.VARIABLES_LOADED()
	if db.enabled then ApplyCVars() end
end

function handlers.PLAYER_ENTERING_WORLD()
	if db.enabled then ApplyCVars() end
end

function handlers.PLAYER_LOGOUT()
	Release()
	Unmute()
	ReturnCVars()
	leaving = true
end

-- Les CVars ne se touchent plus une fois en combat : juste avant, on rouvre l'affichage
-- natif pour que la lueur continue d'apparaître sur les objets croisés pendant le combat,
-- ou on le referme si le joueur ne veut pas de lueur en combat.
function handlers.PLAYER_REGEN_DISABLED()
	if db.enabled then SetGate(not db.hideInCombat) end
	inCombat = true
end

function handlers.PLAYER_REGEN_ENABLED()
	inCombat = false
	if pendingCVars == "apply" then ApplyCVars()
	elseif pendingCVars == "restore" then RestoreCVars() end
	pendingCVars = false
	Evaluate()
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
	activeUnits[unit] = true
	Evaluate()
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
	activeUnits[unit] = nil
	-- la nameplate de la lueur s'en va : on la dissipe tout de suite, là où elle était
	local plate = GetNamePlate(unit)
	if plate and plate == glow.anchor then Release() end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED(oldTarget, newTarget)
	-- une nameplate recyclée d'une cible à l'autre ne suffit pas à voir le changement
	if not IsSecret(oldTarget) and not IsSecret(newTarget) and oldTarget and newTarget and oldTarget ~= newTarget then
		glow.retarget = glow.anchor ~= nil and not glow.preview
	end
	Evaluate()
end

function handlers.QUEST_LOG_UPDATE()
	questsDirty = true
end

function handlers.WORLD_CURSOR_TOOLTIP_UPDATE()
	if LearnFromTooltip() then Evaluate() end
end

function handlers.LOOT_READY()
	LearnContainers()
end
handlers.LOOT_OPENED = handlers.LOOT_READY

events:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler and not leaving and (db or event == "ADDON_LOADED") then handler(...) end
end)
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event)
end

---------------------------------------------------------------------------
-- Réglages
---------------------------------------------------------------------------

-- Replace la lueur après un changement de réglage qui touche son accroche
local function Reattach()
	if glow.preview then
		glow.frame:ClearAllPoints()
		glow.frame:SetPoint("CENTER", glow.anchor, "CENTER", 0, Look(glow.category, "offsetY"))
	elseif glow.anchor then
		glow.retarget = true
		Evaluate()
	end
end

-- Remet le nom et l'icône de l'objet en accord avec les réglages
local function RefreshLabel()
	if glow.preview then
		ShowLabel(nil, SampleName(glow.category), glow.category)
	else
		Evaluate()
	end
end

-- Ce qu'un réglage oblige à refaire quand il change ; ceux qui n'y figurent pas sont relus
-- à chaque image par l'animation
-- Remet les icônes de la minimap (NodeScan.lua) en accord avec les réglages
local function UpdateNodes()
	if ns.UpdateNodes then ns.UpdateNodes() end
end

local APPLY = {
	offsetY = Reattach, followAlpha = Reattach, silhouette = ApplySilhouette, showName = RefreshLabel, showIcon = RefreshLabel, textSize = RefreshLabel,
	textFont = RefreshLabel,
	hideInCombat = Evaluate, hideInInstance = Evaluate, hideUntrained = Evaluate,
	nodeHerbs = UpdateNodes, nodeOre = UpdateNodes, nodeSwitch = UpdateNodes, nodeSwitchYards = UpdateNodes,
	-- (la taille et l'anneau des icônes se redessinent sans relire la minimap : un balayage la cache un instant)
	nodeSize = function() if ns.RedrawNodes then ns.RedrawNodes() end end,
	nodeRing = function() if ns.RedrawNodes then ns.RedrawNodes() end end,
}

function APPLY.enabled()
	if db.enabled then
		ApplyCVars()
		Evaluate()
	else
		Release()
		Unmute()
		RestoreCVars()
	end
	UpdateNodes()
end

function APPLY.range()
	if db.enabled then ApplyCVars() end
end
APPLY.arc = APPLY.range

function APPLY.exclusive()
	gateOpen = nil
	Evaluate()
end

-- (le nom et l'icône de Lueur, sur la cible comme dans l'aperçu)
APPLY.glowOnly = RefreshLabel

function APPLY.debug()
	lastReport = nil
end

function APPLY.language()
	UseLanguage()
	lastReport = nil
	if glow.preview then RefreshLabel() end
	if ns.Retext then ns.Retext() end -- Menu.lua : les textes de la fenêtre
end

-- Prévient Menu.lua qu'un réglage a changé, que ce soit par le menu ou par une commande
local function Notify()
	if ns.Refresh then ns.Refresh() end
end

-- Valeur d'un réglage ; pour un réglage de personnalisation, celle qui vaut pour cette
-- catégorie, ou pour tous les objets si aucune n'est donnée
local function GetOption(key, category)
	if LOOK[key] then return Look(category, key) end
	return Store(key)[key]
end

-- Change un réglage, borné s'il est numérique, et en applique les conséquences. Un réglage de
-- personnalisation se change pour une catégorie, qui en a alors un qui lui est propre, ou pour
-- tous les objets : les catégories qui avaient le leur le perdent, pour que « tous » dise vrai.
local function SetOption(key, value, category)
	local limits = LIMITS[key]
	if limits then value = Clamp(math.floor(value + 0.5), limits[1], limits[2]) end
	if not LOOK[key] then
		Store(key)[key] = value
	elseif category then
		local own = db.categorySettings[category] or {}
		-- la valeur de tous les objets n'est pas une valeur propre
		if value == db[key] then own[key] = nil else own[key] = value end
		db.categorySettings[category] = next(own) ~= nil and own or nil
	else
		db[key] = value
		for name, own in pairs(db.categorySettings) do
			own[key] = nil
			if next(own) == nil then db.categorySettings[name] = nil end
		end
	end
	if APPLY[key] then APPLY[key]() end
	Notify()
end

-- Une catégorie a-t-elle des réglages de personnalisation qui lui sont propres ?
local function HasOwnSettings(category)
	return db.categorySettings[category] ~= nil
end

-- Retire à une catégorie ses réglages propres : elle reprend ceux de tous les objets
local function ClearOwnSettings(category)
	db.categorySettings[category] = nil
	ApplySilhouette()
	Reattach()
	if glow.preview then ShowLabel(nil, SampleName(glow.category), glow.category) end
	Notify()
end

local function IsCategoryShown(key)
	return cdb.categories[key]
end

local function SetCategory(key, shown)
	cdb.categories[key] = shown
	Evaluate()
	Notify()
end

-- Change la couleur d'une catégorie ; sans couleur, lui rend celle d'origine. La lueur en cours
-- y vient en fondu.
local function SetColor(category, r, g, b)
	local color, default = db.colors[category], DEFAULTS.colors[category]
	color[1] = Clamp(r or default[1], 0, 1)
	color[2] = Clamp(g or default[2], 0, 1)
	color[3] = Clamp(b or default[3], 0, 1)
	if glow.anchor and glow.category == category then glow.targetR, glow.targetG, glow.targetB = Color(category) end
	Notify()
end

-- Affiche ou masque le contour de la zone découpée autour du personnage (jamais sauvegardé)
local function ShowZone(shown)
	silhouette.show = shown
	ApplySilhouette()
	Notify()
end

-- Nom de l'objet du décor visé en ce moment, mis en lumière ou non
local function TargetName()
	local unit = ResolveTarget()
	if unit and SafeCall(UnitIsGameObject, unit) == true then return SafeCall(UnitName, unit) end
end

-- Écarte un objet par son nom, ou cesse de l'écarter. Renvoie true s'il est désormais écarté,
-- false s'il ne l'est plus, nil si ce n'est pas un nom.
local function ToggleIgnored(name)
	local key = type(name) == "string" and NameKey(name) or ""
	if key == "" then return nil end
	db.ignored[key] = not db.ignored[key] and name or nil
	lastReport = nil
	Evaluate()
	Notify()
	return db.ignored[key] ~= nil
end

-- Écarte l'objet visé, ou cesse de l'écarter, en l'annonçant
local function IgnoreTarget()
	local name = TargetName()
	if not name then
		Print(L.MSG_IGNORE_NO_TARGET)
	else
		Print((ToggleIgnored(name) and L.MSG_IGNORED or L.MSG_UNIGNORED):format(name))
	end
end

-- Noms des objets écartés, par ordre alphabétique
local function IgnoredNames()
	local names = {}
	for _, name in pairs(db.ignored) do names[#names + 1] = name end
	table.sort(names)
	return names
end

-- L'activation, la langue, le bouton de la minimap, ce que Lueur a appris des infobulles et des
-- objets approchés et les objets écartés ne sont pas des réglages de la lueur : la remise à zéro
-- n'y touche pas
local KEPT_ON_RESET = { enabled = true, language = true, minimap = true, questObjects = true, ignored = true, nodeNames = true,
	containers = true }

local function ResetTo(defaults, store)
	for key, value in pairs(defaults) do
		if not KEPT_ON_RESET[key] then
			if type(value) == "table" then
				store[key] = {}
				CopyDefaults(value, store[key])
			else
				store[key] = value
			end
		end
	end
end

-- Remet les réglages du compte et ceux de ce personnage à leurs valeurs d'origine
local function ResetOptions()
	ResetTo(DEFAULTS, db)
	ResetTo(CHAR_DEFAULTS, cdb)
	silhouette.show = false
	ApplySilhouette()
	gateOpen, lastReport = nil, nil
	if db.enabled then ApplyCVars() end
	Reattach()
	RefreshLabel()
	UpdateNodes()
	Notify()
end

-- Active ou désactive Lueur en l'annonçant : sans le menu sous les yeux, rien d'autre ne le dit
local function Toggle(enabled)
	SetOption("enabled", enabled)
	Print(enabled and L.MSG_ENABLED or L.MSG_DISABLED)
end

-- Ce dont les fichiers suivants se servent
ns.SafeCall, ns.IsSecret, ns.NameKey, ns.Flag = SafeCall, IsSecret, NameKey, Flag
ns.LIMITS, ns.CATEGORY_ORDER, ns.Print = LIMITS, CATEGORY_ORDER, Print
ns.GetOption, ns.SetOption, ns.IsCategoryShown, ns.SetCategory = GetOption, SetOption, IsCategoryShown, SetCategory
ns.HasOwnSettings, ns.ClearOwnSettings, ns.GetColor, ns.SetColor = HasOwnSettings, ClearOwnSettings, Color, SetColor
ns.IgnoreTarget, ns.IgnoredNames = IgnoreTarget, IgnoredNames
ns.Toggle, ns.ResetOptions, ns.ShowZone = Toggle, ResetOptions, ShowZone
ns.StartPreview, ns.StopPreview = StartPreview, StopPreview

function ns.IsPreviewing()
	return glow.preview ~= nil
end

-- La lueur est-elle sur une vraie cible ? L'aperçu de la fenêtre des réglages attend alors son tour.
function ns.GlowTaken()
	return glow.anchor ~= nil and not glow.preview
end

-- État que montre l'aperçu en cours, ou nil
function ns.PreviewState()
	return glow.preview and glow.state
end

function ns.IsZoneShown()
	return silhouette.show == true
end

-- Raison pour laquelle la découpe est indisponible sur ce client, ou nil
local function SilhouetteFailure()
	return silhouette.failed and L[silhouette.failed]
end
ns.SilhouetteFailure = SilhouetteFailure
-- Menu.lua : le nom et l'icône de Lueur ne s'écrivent pas quand la lumière est seule (Plumber, ou le réglage)
ns.GlowBare = glow.Bare

---------------------------------------------------------------------------
-- Touche d'interaction
---------------------------------------------------------------------------

-- Ramasser, cueillir ou activer l'objet visé est une action protégée : seul un raccourci du
-- jeu peut la déclencher, pas le code d'un addon. Lueur n'a donc pas de raccourci à lui : il
-- donne accès à celui du jeu, "Interagir avec la cible", qui agit sur la cible d'interaction.
local INTERACT = "INTERACTTARGET"

local function BindingContext()
	return C_KeyBindings and C_KeyBindings.GetBindingContextForAction
		and SafeCall(C_KeyBindings.GetBindingContextForAction, INTERACT)
end

-- Renvoie la touche principale du raccourci d'interaction, ou nil
local function GetInteractKey()
	return (GetBindingKey(INTERACT, nil, BindingContext()))
end

-- Nom d'une touche tel que le jeu l'affiche
local function KeyText(key)
	return GetBindingText and GetBindingText(key) or key
end

-- Renvoie le nom du raccourci, autre que celui d'interaction, auquel cette touche sert déjà
local function KeyOwner(key)
	local action = GetBindingAction(key, nil, BindingContext())
	if type(action) ~= "string" or action == "" or action == INTERACT then return nil end
	return _G["BINDING_NAME_" .. action] or action
end

-- Donne cette touche au raccourci d'interaction, à la place de sa touche principale ; nil la
-- lui retire. Le raccourci qui s'en servait la perd. Renvoie false et la raison quand rien
-- n'a pu changer.
local function SetInteractKey(key)
	if InCombatLockdown() then return false, L.MSG_KEY_COMBAT end
	local context = BindingContext()
	local first, second = GetBindingKey(INTERACT, nil, context)
	-- comme le fait le jeu : tout retirer, puis remettre les touches dans l'ordre
	if first then SetBinding(first, nil, context) end
	if second then SetBinding(second, nil, context) end
	local bound = key == nil or SetBinding(key, INTERACT, context)
	if not bound and first then SetBinding(first, INTERACT, context) end
	if second and second ~= key then SetBinding(second, INTERACT, context) end
	local save = SaveBindings or AttemptToSaveBindings
	if save and GetCurrentBindingSet then pcall(save, GetCurrentBindingSet()) end
	Notify()
	if not bound then return false, L.MSG_KEY_REFUSED:format(key) end
	return true
end

ns.GetInteractKey, ns.SetInteractKey, ns.KeyOwner, ns.KeyText = GetInteractKey, SetInteractKey, KeyOwner, KeyText

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

-- Mot tapé -> nom anglais de la commande ou de l'effet : ceux de la langue affichée, et le
-- nom affiché de chaque effet. Les noms anglais répondent toujours.
local ALIASES = {}

function UseLanguage()
	ns.UseLanguage(db.language)
	for word in pairs(ALIASES) do ALIASES[word] = nil end
	for word, command in pairs(L.COMMANDS) do ALIASES[Fold(word)] = command end
	for _, key in ipairs(ns.EFFECT_ORDER) do ALIASES[Fold(EffectLabel(key))] = key end
	for _, key in ipairs(ns.FontChoices()) do ALIASES[Fold(ns.FontName(key) or L.FONT_GAME)] = key end
end

-- Remplace {réglage} par ses bornes et {réglage=} par sa valeur par défaut
local function Fill(text)
	return (text:gsub("{(%w+)(=?)}", function(key, default)
		if default == "=" then
			if DEFAULTS[key] ~= nil then return tostring(DEFAULTS[key]) end
			return tostring(CHAR_DEFAULTS[key])
		end
		return LIMITS[key][1] .. ".." .. LIMITS[key][2]
	end))
end

local function ShowHelp()
	Print(L.HELP_HEADER)
	for _, line in ipairs(L.HELP) do print("  " .. Fill(line)) end
end

-- Chaque commande reçoit son argument, et le nombre qu'il représente s'il en est un. Celle
-- qui renvoie false n'a pas su quoi en faire : l'aide s'affiche à sa place.
local COMMANDS = {}

function COMMANDS.menu()
	if ns.ToggleMenu then ns.ToggleMenu() end
end
COMMANDS[""] = COMMANDS.menu

function COMMANDS.minimap()
	if not ns.ShowMinimapButton then return end
	ns.ShowMinimapButton(db.minimap.hide)
	Print(L.SETTING:format(L.MINIMAP, Flag(not db.minimap.hide)))
end

function COMMANDS.on() Toggle(true) end
function COMMANDS.off() Toggle(false) end

-- Ouvre la fenêtre des réglages sur l'aperçu, ou la ferme (Menu.lua, Preview.lua)
function COMMANDS.preview()
	if ns.TogglePreview then ns.TogglePreview() end
end

-- Un mot tapé désigne-t-il une catégorie ? Renvoie son nom anglais.
local function CategoryArg(word)
	local category = ALIASES[word] or word
	return DEFAULTS.colors[category] and category
end

-- Les réglages de personnalisation se donnent à tous les objets ("/lueur size 150") ou à une
-- catégorie nommée d'abord ("/lueur size ore 150"). Renvoie cette catégorie, ou nil, et le
-- reste de l'argument.
local function Scoped(arg)
	local first, rest = arg:match("^(%S*)%s*(.-)$")
	local category = CategoryArg(first)
	if category then return category, rest end
	return nil, arg
end

-- Nom d'un réglage dans une annonce, suivi de la catégorie pour laquelle il vient de changer
local function Named(text, category)
	return category and L.OF_CATEGORY:format(text, CategoryLabel(category)) or text
end

-- Sans effet reconnu, la commande liste les effets et rappelle celui en place
function COMMANDS.effect(arg)
	local category, rest = Scoped(arg)
	local key = ALIASES[rest] or rest
	if key ~= "fallback" and EFFECTS[key] then
		SetOption("effect", key, category)
		Print(L.SETTING:format(Named(L.EFFECT, category), EffectLabel(key)))
	else
		local names = {}
		for index, name in ipairs(ns.EFFECT_ORDER) do names[index] = EffectLabel(name) end
		Print(L.MSG_EFFECTS:format(table.concat(names, ", "), EffectLabel(Look(category, "effect"))))
	end
end

-- "/lueur color ore ff8800" colore une catégorie, "/lueur color ore default" lui rend sa couleur
-- d'origine ; sans couleur, la commande rappelle celle en place
function COMMANDS.color(arg)
	local category, rest = Scoped(arg)
	if not category then return false end
	local r, g, b = rest:match("^#?(%x%x)(%x%x)(%x%x)$")
	if r then
		SetColor(category, tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
	elseif (ALIASES[rest] or rest) == "default" then
		SetColor(category)
	elseif rest ~= "" then
		return false
	end
	r, g, b = Color(category)
	local hex = ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	Print(L.MSG_COLOR:format(CategoryLabel(category), "|cff" .. hex .. hex .. "|r"))
end

-- "/lueur shared ore" retire à une catégorie ses réglages propres
function COMMANDS.shared(arg)
	local category = CategoryArg(arg)
	if not category then return false end
	ClearOwnSettings(category)
	Print(L.MSG_SHARED:format(CategoryLabel(category)))
end

-- Commande d'un réglage numérique, annoncé sous le nom et le format qu'il a dans le menu :
-- `name` et `pattern` nomment des textes ("%d" à défaut de format)
local function NumberCommand(key, name, pattern)
	return function(arg)
		local category, rest = Scoped(arg)
		local number = tonumber(rest)
		if not number then return false end
		SetOption(key, number, category)
		Print(L.SETTING:format(Named(L[name], category), (pattern and L[pattern] or "%d"):format(GetOption(key, category))))
	end
end

COMMANDS.size = NumberCommand("size", "SIZE")
COMMANDS.intensity = NumberCommand("intensity", "INTENSITY", "FORMAT_PERCENT")
COMMANDS.offset = NumberCommand("offsetY", "OFFSET")
COMMANDS.text = NumberCommand("textSize", "TEXT_SIZE", "FORMAT_PERCENT")

-- "/lueur font morpheus", "/lueur font ore default" ; sans police reconnue, la commande liste
-- celles que le client propose et rappelle celle en place
function COMMANDS.font(arg)
	local category, rest = Scoped(arg)
	local key = ALIASES[rest] or rest
	if key == "default" then key = "game" end
	local choices = ns.FontChoices()
	for _, choice in ipairs(choices) do
		if choice == key then
			SetOption("textFont", key, category)
			Print(L.SETTING:format(Named(L.FONT, category), ns.FontName(key) or L.FONT_GAME))
			return
		end
	end
	local names = {}
	for index, choice in ipairs(choices) do names[index] = ns.FontName(choice) or L.FONT_GAME end
	Print(L.MSG_FONTS:format(table.concat(names, ", "), ns.FontName(Look(category, "textFont")) or L.FONT_GAME))
end

-- Commande d'un réglage oui/non de personnalisation, annoncé sous le nom qu'il a dans le menu
local function LookToggle(key, name)
	return function(arg)
		local category, rest = Scoped(arg)
		if rest ~= "" then return false end
		SetOption(key, not Look(category, key), category)
		Print(L.SETTING:format(Named(L[name], category), Flag(Look(category, key))))
	end
end

COMMANDS.fade = LookToggle("followAlpha", "FADE")
COMMANDS.name = LookToggle("showName", "SHOW_NAME")
COMMANDS.icon = LookToggle("showIcon", "SHOW_ICON")

-- Commande d'un réglage oui/non, annoncé par le texte de ce nom, où s'insère "oui" ou "non"
local function ToggleCommand(key, message)
	return function()
		SetOption(key, not GetOption(key))
		Print(L[message]:format(Flag(GetOption(key))))
	end
end

COMMANDS.combat = ToggleCommand("hideInCombat", "MSG_HIDE_COMBAT")
COMMANDS.instance = ToggleCommand("hideInInstance", "MSG_HIDE_INSTANCE")
COMMANDS.unavailable = ToggleCommand("hideLocked", "MSG_HIDE_LOCKED")
COMMANDS.profession = ToggleCommand("hideUntrained", "MSG_HIDE_UNTRAINED")
COMMANDS.glowonly = ToggleCommand("glowOnly", "MSG_GLOW_ONLY")

-- Sans argument, écarte l'objet visé (ou cesse de l'écarter) ; "list" donne les objets écartés,
-- "clear" les oublie tous ; tout autre argument est le nom d'un objet
function COMMANDS.ignore(arg)
	if arg == "" then
		IgnoreTarget()
	elseif arg == "list" then
		local names = IgnoredNames()
		Print(#names > 0 and L.MSG_IGNORE_LIST:format(table.concat(names, ", ")) or L.MSG_IGNORE_EMPTY)
	elseif arg == "clear" then
		for key in pairs(db.ignored) do db.ignored[key] = nil end
		lastReport = nil
		Evaluate()
		Notify()
		Print(L.MSG_IGNORE_EMPTY)
	else
		local known = db.ignored[NameKey(arg)]
		local ignored = ToggleIgnored(arg)
		if ignored == nil then return false end
		Print((ignored and L.MSG_IGNORED or L.MSG_UNIGNORED):format(known or arg))
	end
end

function COMMANDS.exclusive()
	SetOption("exclusive", not db.exclusive)
	Print(db.exclusive and L.MSG_EXCLUSIVE_ON or L.MSG_EXCLUSIVE_OFF)
end

function COMMANDS.silhouette(arg)
	local size, shift = arg:match("^(%d+)%s*(%-?%d*)$")
	local category = CategoryArg(arg)
	if arg == "" or category then
		SetOption("silhouette", not Look(category, "silhouette"), category)
		local on = Look(category, "silhouette")
		if category then
			Print(L.SETTING:format(Named(L.SILHOUETTE, category), Flag(on)))
		else
			Print(on and L.MSG_SILHOUETTE_ON or L.MSG_SILHOUETTE_OFF)
		end
		if on and silhouette.failed then Print(L.MSG_CUTOUT_UNAVAILABLE:format(SilhouetteFailure())) end
	elseif arg == "show" then
		ShowZone(not silhouette.show)
		Print(silhouette.failed and L.MSG_CUTOUT_UNAVAILABLE:format(SilhouetteFailure())
			or silhouette.show and L.MSG_ZONE_SHOWN or L.MSG_ZONE_HIDDEN)
	elseif size then
		SetOption("bodyScale", tonumber(size))
		if shift ~= "" and shift ~= "-" then SetOption("bodyShift", tonumber(shift)) end
		Print(L.MSG_SILHOUETTE_VALUES:format(cdb.bodyScale, cdb.bodyShift))
	else
		Print(Fill(L.MSG_SILHOUETTE_USAGE))
	end
end

function COMMANDS.range(_, number)
	if not number then return false end
	SetOption("range", number)
	local applied = tonumber(GetCVarValue("SoftTargetInteractRange"))
	if pendingCVars == "apply" then
		Print(L.MSG_RANGE_COMBAT:format(db.range))
	elseif db.enabled and applied and applied ~= WantedRange() then
		Print(L.MSG_RANGE_CLIENT:format(db.range, tostring(applied)))
	else
		Print(L.MSG_RANGE:format(db.range))
	end
end

function COMMANDS.arc(_, number)
	if not number then return false end
	SetOption("arc", number)
	Print(L.SETTING:format(L.DIRECTION, L["ARC_" .. db.arc]))
end

-- Sans argument, montre la touche d'interaction ; sinon l'assigne ("SHIFT-E"), ou la retire
function COMMANDS.key(arg)
	if arg ~= "" then
		local key
		if arg ~= "none" then key = arg:upper() end
		local owner = key and KeyOwner(key)
		local changed, reason = SetInteractKey(key)
		if not changed then Print(reason) return end
		if owner then Print(L.MSG_KEY_REPLACED:format(KeyText(key), owner)) end
	end
	local key = GetInteractKey()
	Print(L.SETTING:format(L.KEY, key and KeyText(key) or L.KEY_NONE))
end

for _, category in ipairs(CATEGORY_ORDER) do
	COMMANDS[category] = function()
		SetCategory(category, not IsCategoryShown(category))
		Print(L.SETTING:format(CategoryLabel(category), Flag(IsCategoryShown(category))))
	end
end

-- Icônes des plantes et des filons sur la minimap (NodeScan.lua). Sans argument, les montre ou
-- les retire toutes ; "ore" ou "herb", celles d'un métier ; "size 14" règle leur taille, "ring 50"
-- l'épaisseur de leur anneau ; "combat", si la minimap se lit en combat.
local NODE_KEYS = { herb = "nodeHerbs", ore = "nodeOre" }
local NODE_TEXTS = { herb = "NODE_HERBS", ore = "NODE_ORE" }

function COMMANDS.nodes(arg)
	if not ns.UpdateNodes then Print(L.MSG_RESTART) return end
	local first, rest = arg:match("^(%S*)%s*(.-)$")
	first = ALIASES[first] or first
	if first == "size" then
		local number = tonumber(rest)
		if not number then return false end
		SetOption("nodeSize", number)
		Print(L.SETTING:format(L.NODE_SIZE, tostring(db.nodeSize)))
		return
	end
	if first == "ring" then
		local number = tonumber(rest)
		if not number then return false end
		SetOption("nodeRing", number)
		Print(L.SETTING:format(L.NODE_RING, L.FORMAT_PERCENT:format(db.nodeRing)))
		return
	end
	if first == "combat" and rest == "" then
		SetOption("nodeCombat", not db.nodeCombat)
		Print(L.SETTING:format(L.NODE_COMBAT, Flag(db.nodeCombat)))
		return
	end
	if rest ~= "" or (first ~= "" and not NODE_KEYS[first]) then return false end
	local shown
	if first == "" then shown = not (db.nodeHerbs or db.nodeOre) else shown = not db[NODE_KEYS[first]] end
	for _, kind in ipairs({ "herb", "ore" }) do
		if first == "" or first == kind then
			SetOption(NODE_KEYS[kind], shown)
			Print(L.SETTING:format(L[NODE_TEXTS[kind]], Flag(shown)))
		end
	end
	local failure = ns.NodesFailure()
	if shown and failure then Print(L.MSG_NODES_UNAVAILABLE:format(failure)) end
end

-- Deux métiers de récolte : sans argument, lance ou arrête l'alternance des deux pistages ; un
-- nombre règle la distance parcourue entre deux bascules
function COMMANDS.switch(arg, number)
	if not ns.UpdateNodes then Print(L.MSG_RESTART) return end
	if number then
		SetOption("nodeSwitchYards", number)
		Print(L.SETTING:format(L.NODE_SWITCH_YARDS, L.FORMAT_RANGE:format(cdb.nodeSwitchYards)))
	elseif arg == "" then
		SetOption("nodeSwitch", not cdb.nodeSwitch)
		Print(L.SETTING:format(L.NODE_SWITCH, Flag(cdb.nodeSwitch)))
	else
		return false
	end
end

-- Ce que le dernier balayage de la minimap a lu, et ce que Lueur en a fait
function COMMANDS.scan(arg)
	-- un nombre : la distance parcourue entre deux balayages
	local yards = tonumber(arg)
	if yards and ns.UpdateNodes then
		SetOption("nodeScanYards", yards)
		Print(L.SETTING:format(L.NODE_SCAN_YARDS, L.FORMAT_RANGE:format(db.nodeScanYards)))
		return
	end
	-- un balayage tout de suite, sans attendre que le joueur ait marché assez
	if arg == "now" then
		Print(ns.ScanNow and ns.ScanNow() or L.MSG_RESTART)
		return
	end
	-- prototype de la lueur au loin (NodeScan.lua, fin du fichier), éteint par défaut
	if arg == "far" then
		db.farGlow = not db.farGlow or nil
		Print("far glow (prototype): " .. (db.farGlow and "on" or "off"))
		Evaluate()
		return
	end
	-- et de combien la lueur descend sous le marqueur du jeu, en mètres
	local drop = tonumber(arg:match("^far%s+(%-?[%d.]+)$") or "")
	-- le repère tenu en place, pour voir si le marqueur suit le joueur en hauteur
	if arg == "far hold" then
		Print("far glow (prototype): " .. (ns.FarHold and ns.FarHold() or "?"))
		return
	end
	-- l'essai des positions secrètes
	if arg == "far secret" then
		Print("far glow (prototype): " .. (ns.FarSecretTest and ns.FarSecretTest() or "?"))
		return
	end
	-- et cherche de nouveau la hauteur du nœud éclairé
	if arg == "far pin" and ns.FarRepin then ns.FarRepin() end
	if drop then db.farDrop = drop + 0 end
	if drop or arg == "far status" or arg == "far pin" then
		Print("far glow (prototype): " .. (ns.FarStatus and ns.FarStatus() or "?"))
		return
	end
	if ns.ScanReport then ns.ScanReport() else Print(L.MSG_RESTART) end
end

-- Nom de la langue réglée, tel que le menu le montre
local function LanguageName()
	return db.language == "auto" and L.LANGUAGE_AUTO or ns.LOCALES[db.language].LANGUAGE_NAME
end

-- La langue se désigne par "auto", par son code ("frFR"), ses deux premières lettres ou son nom
function COMMANDS.language(arg)
	local choice
	if arg == "auto" or arg == Fold(L.LANGUAGE_AUTO) then choice = "auto" end
	for code, texts in pairs(ns.LOCALES) do
		if arg == code:lower() or arg == code:sub(1, 2) or arg == Fold(texts.LANGUAGE_NAME) then choice = code end
	end
	if choice then SetOption("language", choice) end
	Print(L.SETTING:format(L.LANGUAGE, LanguageName()))
end

function COMMANDS.debug()
	SetOption("debug", not db.debug)
	Print(L.SETTING:format(L.DEBUG, Flag(db.debug)))
end

-- Ce à quoi le nom d'un objet est comparé pour le reconnaître comme objet de quête
function COMMANDS.objectives()
	RebuildQuestTexts()
	Print(L.OBJECTIVES_HEADER:format(#questTexts))
	for _, objective in ipairs(questTexts) do
		print("  " .. objective.text .. (objective.pickable and "" or L.OBJECTIVES_NOT_ITEM))
	end
	for name, title in pairs(db.questObjects) do
		if questTitles[title] then print("  " .. L.OBJECTIVES_LEARNED:format(name, title)) end
	end
end

function COMMANDS.status()
	local version, build = GetBuildInfo()
	Print(L.STATUS_CLIENT:format(tostring(version), tostring(build), tostring(GetLocale()), LanguageName()))
	for _, names in ipairs({ MANAGED_CVARS, WATCHED_CVARS }) do
		for _, name in ipairs(names) do
			local value = GetCVarValue(name)
			local default
			if C_CVar and C_CVar.GetCVarDefault then default = SafeCall(C_CVar.GetCVarDefault, name) end
			print(("  %s = %s%s"):format(name, value == nil and L.STATUS_CVAR_UNKNOWN or tostring(value),
				default and L.STATUS_CVAR_DEFAULT:format(tostring(default)) or ""))
		end
	end
	print("  " .. L.STATUS_EXPECTED:format(WantedRange(), db.arc))
	print("  " .. L.STATUS_GATE:format(Flag(db.exclusive), gateOpen == nil and "?" or gateOpen and L.GATE_OPEN or L.GATE_CLOSED))
	print("  " .. L.STATUS_GLOW_ONLY:format(Flag(db.glowOnly), Flag(glow.Plumber())))
	print("  " .. L.STATUS_SILHOUETTE:format(silhouette.failed and L.STATUS_UNAVAILABLE:format(SilhouetteFailure())
		or Flag(db.silhouette)))
	print("  " .. L.STATUS_DIRECT:format(directWorks and L.YES or L.STATUS_NOT_YET))
	print("  " .. L.STATUS_RANGE_API:format(Flag(UnitIsInInteractRange ~= nil)))
	local fishing, channel, icon = ReadLine()
	print("  " .. L.STATUS_LINE:format(Flag(fishing), channel and ("%s, %s"):format(channel, tostring(icon)) or L.NAME_NONE))
	if ns.NodesFailure then
		local failure = ns.NodesFailure()
		print("  " .. L.STATUS_NODES:format(failure and L.STATUS_UNAVAILABLE:format(failure)
			or L.STATUS_NODES_SHOWN:format(Flag(db.nodeHerbs), Flag(db.nodeOre), Flag(cdb.nodeSwitch))))
	end
	print("  " .. L.STATUS_TRAINED:format(Flag(db.hideUntrained), Flag(Trained("herb")), Flag(Trained("ore"))))
	print("  " .. L.STATUS_HIDE:format(Flag(db.hideInCombat), Flag(db.hideInInstance), Flag(db.hideLocked), Flag(Paused())))
	local shown = {}
	for _, category in ipairs(CATEGORY_ORDER) do
		if cdb.categories[category] then shown[#shown + 1] = CategoryName(category) end
	end
	print("  " .. L.STATUS_OBJECTS:format(#shown > 0 and table.concat(shown, ", ") or L.NAME_NONE, #IgnoredNames()))
	local own = {}
	for _, category in ipairs(CATEGORY_ORDER) do
		if HasOwnSettings(category) then own[#own + 1] = CategoryName(category) end
	end
	print("  " .. L.STATUS_OWN:format(#own > 0 and table.concat(own, ", ") or L.NAME_NONE))
	local key = GetInteractKey()
	print("  " .. L.STATUS_KEY:format(key and KeyText(key) or L.KEY_NONE))
	local effect = EFFECTS[db.effect]
	print("  " .. L.STATUS_EFFECT:format(EffectLabel(db.effect),
		effect.missing and L.TEXTURES_MISSING or effect.fx and L.TEXTURES_LOADED or L.TEXTURES_PENDING))
end

COMMANDS.help = ShowHelp

SLASH_LUEUR1 = "/lueur"
SlashCmdList.LUEUR = function(input)
	local cmd, arg = Fold(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local command = COMMANDS[ALIASES[cmd] or cmd]
	if not command or command(ALIASES[arg] or arg, tonumber(arg)) == false then ShowHelp() end
end
