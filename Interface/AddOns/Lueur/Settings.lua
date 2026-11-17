-- Lueur : les réglages
-- Leur chargement (ns.LoadSettings : migrations d'un schéma au suivant, valeurs par défaut,
-- bornes) et tout ce qui les change : SetOption, pour le menu comme pour les commandes, les
-- catégories, les couleurs, les objets écartés, la remise à zéro, et la touche d'interaction,
-- qui est un raccourci du jeu.

local _, ns = ...
local L = ns.L
local EFFECTS = ns.EFFECTS
local S, glow, silhouette = ns.state, ns.glow, ns.silhouette
local DEFAULTS, CHAR_DEFAULTS, LOOK, LIMITS, PROFILE = ns.DEFAULTS, ns.CHAR_DEFAULTS, ns.LOOK, ns.LIMITS, ns.PROFILE
local Print, IsSecret, SafeCall, CopyDefaults, Clamp = ns.Print, ns.IsSecret, ns.SafeCall, ns.CopyDefaults, ns.Clamp
local Store, Color, Look = ns.Store, ns.GetColor, ns.Look
local ApplyCVars, RestoreCVars, RepairSavedCVars = ns.ApplyCVars, ns.RestoreCVars, ns.RepairSavedCVars
local NameKey, ResolveTarget = ns.NameKey, ns.ResolveTarget
local ApplySilhouette, ShowLabel, Release, Unmute = ns.ApplySilhouette, ns.ShowLabel, ns.Release, ns.Unmute
local Evaluate, SampleName = ns.Evaluate, ns.SampleName

local db, cdb
ns.OnSettings(function(account, character) db, cdb = account, character end)


local SCHEMA = 11 -- version des réglages sauvegardés

-- Styles du halo d'avant la version 0.5 -> effet qui les remplace
local LEGACY_STYLES = { aura = "aura", reticule = "aura", discret = "subtle" }

---------------------------------------------------------------------------
-- Profils
---------------------------------------------------------------------------

-- Un profil est un jeu de réglages de la lueur (PROFILE, dans Core.lua) que le joueur nomme ; chaque
-- personnage a le sien (cdb.profile), le premier faute d'en avoir choisi un. Les réglages du profil en
-- service restent là où ils ont toujours été, au premier niveau de db : le reste de l'addon les y lit
-- sans rien savoir des profils. db.profiles garde, par numéro, le nom de chaque profil (nil : le profil
-- d'origine, nommé dans la langue affichée) et, tant qu'il n'est pas en service, ses réglages
-- (settings) ; db.liveProfile dit lequel est en service, db.profileSeq le dernier numéro donné.
-- (Demandé le 2026-11-16 ; schéma et panneau approuvés le 2026-11-17.)
local profiles = { NAME_MAX = 24 }

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = Copy(item) end
	return copy
end

-- Les réglages en service, tels qu'un profil les garde
function profiles.Snapshot()
	local settings = {}
	for key in pairs(PROFILE) do settings[key] = Copy(db[key]) end
	return settings
end

-- Met en service les réglages d'un profil ; ceux qu'il n'a pas, ou pas de la bonne nature, sont ceux
-- d'origine. Ils quittent le profil : tant qu'il est en service, c'est db qui les tient.
function profiles.Load(id)
	local settings = db.profiles[id].settings
	if type(settings) ~= "table" then settings = {} end
	for key in pairs(PROFILE) do
		local value = settings[key]
		if type(value) ~= type(DEFAULTS[key]) then value = DEFAULTS[key] end
		db[key] = Copy(value)
		if type(db[key]) == "table" then CopyDefaults(DEFAULTS[key], db[key]) end
	end
	db.profiles[id].settings = nil
	db.liveProfile = id
end

-- Numéros des profils, dans l'ordre de leur création
function profiles.Ids()
	local ids = {}
	for id in pairs(db.profiles) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

-- Au chargement : des profils bien formés, et celui du personnage en service. Les réglages d'avant
-- les profils deviennent le profil d'origine, celui de tous les personnages.
function profiles.Setup()
	local list = db.profiles
	if type(list) ~= "table" then
		list = {}
		db.profiles = list
	end
	for id, profile in pairs(list) do
		if type(id) ~= "number" or type(profile) ~= "table" then
			list[id] = nil
		else
			if type(profile.name) ~= "string" or profile.name == "" then profile.name = nil end
			if type(profile.settings) ~= "table" then profile.settings = nil end
		end
	end
	if next(list) == nil then
		list[1] = {}
		db.liveProfile = 1
	end
	local ids = profiles.Ids()
	if not list[db.liveProfile] then
		-- (un fichier abîmé : les réglages en service reviennent au premier profil)
		db.liveProfile = ids[1]
		list[ids[1]].settings = nil
	end
	db.profileSeq = math.max(type(db.profileSeq) == "number" and db.profileSeq or 0, ids[#ids])
	-- un personnage neuf, ou dont le profil a été supprimé depuis un autre personnage : le premier
	if not list[cdb.profile] then cdb.profile = ids[1] end
	if cdb.profile ~= db.liveProfile then
		list[db.liveProfile].settings = profiles.Snapshot()
		profiles.Load(cdb.profile)
	end
end

-- Les réglages de personnalisation qui n'ont plus de sens reprennent leur valeur d'origine : un effet
-- ou une police que cette version n'a pas, une catégorie disparue, une couleur abîmée
local function SanitizeLook()
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
	-- une seconde couleur : celle d'une catégorie connue, en trois nombres, ou rien
	for category, color in pairs(db.colors2) do
		local fine = DEFAULTS.colors[category] ~= nil and type(color) == "table"
		for index = 1, 3 do fine = fine and type(color[index]) == "number" end
		if fine then
			for index = 1, 3 do color[index] = Clamp(color[index], 0, 1) end
		else
			db.colors2[category] = nil
		end
	end
end

-- Les réglages numériques restent dans leurs bornes
local function ClampAll()
	for key, limits in pairs(LIMITS) do
		local store = Store(key)
		if type(store[key]) == "number" then
			-- "+ 0" : Lua 5.1 relit en -0 les zéros d'un fichier de réglages qui contient un -0, et l'afficherait tel quel
			store[key] = Clamp(store[key], limits[1], limits[2]) + 0
		else
			store[key] = DEFAULTS[key] or CHAR_DEFAULTS[key]
		end
	end
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------

-- Les réglages sauvegardés viennent d'être lus par le jeu (ADDON_LOADED) : les met au schéma
-- courant, les complète de leurs valeurs par défaut et écarte ce qui n'a plus de sens
function ns.LoadSettings()
	LueurDB = LueurDB or {}
	LueurCharDB = LueurCharDB or {}
	ns.BindSettings(LueurDB, LueurCharDB) -- db et cdb, dans chaque fichier du cœur
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
		end
		if from < 9 then
			-- le Réticule, un dosage de l'Aura, s'en va (2026-11-09) : qui le portait reçoit l'Aura. Le
			-- Viseur, parti avec lui, est revenu le 2026-11-10 : qui vient d'avant le schéma 9 le garde
			local retired = { reticle = "aura" }
			local function Replace(store)
				if type(store) ~= "table" then return end
				store.effect = retired[store.effect] or store.effect
			end
			Replace(db)
			if type(db.categorySettings) == "table" then
				for _, own in pairs(db.categorySettings) do Replace(own) end
			end
		end
		if from < 11 then
			-- les icônes de la minimap et le prototype de la lueur au loin sont partis (2026-11-16) : le jeu
			-- a fermé toutes les façons de lire les points de sa minimap. Leurs réglages et ce que leurs
			-- sondes avaient noté s'en vont ; iconScaleBack et farRestore, eux, sont d'abord rendus au
			-- joueur, à la connexion (PLAYER_LOGIN)
			for _, key in ipairs({ "nodeHerbs", "nodeOre", "nodeSize", "nodeRing", "nodeNames", "nodeCombat", "nodeScanYards",
				"nodesOffNotice", "farGlow", "farDrop", "farPins", "farProbe", "farSecret", "farSecretError", "scanTest", "scanCopy",
				"scanClip", "scanLab", "coordProbe" }) do
				db[key] = nil
			end
		end
		db.schema = SCHEMA
	end
	CopyDefaults(DEFAULTS, db)
	if next(cdb) == nil and type(db.inherited) == "table" then CopyDefaults(db.inherited, cdb) end
	CopyDefaults(CHAR_DEFAULTS, cdb)
	profiles.Setup()

	SanitizeLook()
	if not ns.LOCALES[db.language] then db.language = DEFAULTS.language end
	ns.ApplyLanguage() -- (Commands.lua, chargé après ce fichier)
	ClampAll()
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
-- Remet l'alternance des pistages (Tracking.lua) en accord avec les réglages
local function UpdateTracking()
	if ns.UpdateTracking then ns.UpdateTracking() end
end

local APPLY = {
	offsetY = Reattach, followAlpha = Reattach, silhouette = ApplySilhouette, showName = RefreshLabel, showIcon = RefreshLabel, textSize = RefreshLabel,
	textFont = RefreshLabel,
	hideInCombat = Evaluate, hideInInstance = Evaluate, hideUntrained = Evaluate,
	nodeSwitch = UpdateTracking, nodeSwitchYards = UpdateTracking,
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
	UpdateTracking()
end

function APPLY.range()
	if db.enabled then ApplyCVars() end
end
APPLY.arc = APPLY.range

function APPLY.exclusive()
	S.gateOpen = nil
	Evaluate()
end

-- (le nom et l'icône de Lueur, sur la cible comme dans l'aperçu)
APPLY.glowOnly = RefreshLabel

function APPLY.debug()
	S.lastReport = nil
end

function APPLY.language()
	ns.ApplyLanguage() -- (Commands.lua, chargé après ce fichier)
	S.lastReport = nil
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

-- Donne à une catégorie une seconde couleur, celle des traits fins et des éclats de son effet ; sans
-- couleur, la lui retire : elle reprend la première. La lueur en cours la lit à chaque image.
local function SetColor2(category, r, g, b)
	if not DEFAULTS.colors[category] then return end
	db.colors2[category] = r and { Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1) } or nil
	Notify()
end

-- Échange les deux couleurs d'une catégorie ; rien à faire tant qu'elle n'en a qu'une
local function SwapColors(category)
	local first, second = db.colors[category], db.colors2[category]
	if not (first and second) then return end
	for index = 1, 3 do first[index], second[index] = second[index], first[index] end
	if glow.anchor and glow.category == category then glow.targetR, glow.targetG, glow.targetB = Color(category) end
	Notify()
end

-- Affiche ou masque le contour de la zone découpée autour du personnage (jamais sauvegardé)
local function ShowZone(shown)
	silhouette.show = shown
	ApplySilhouette()
	Notify()
end

-- Nom d'une unité pour la liste des objets écartés : "" quand le jeu ne lui en donne pas (signalé
-- le 2026-11-10 : une chaise sans nom ne pouvait pas être écartée), nil quand il ne se lit pas
-- (valeur secrète), ce qui n'est pas la même chose. Dans `glow` : Decide (Lueur.lua, chargé avant ce fichier) s'en sert aussi.
function glow.NameOf(unit)
	local ok, name = pcall(UnitName, unit)
	if not ok or IsSecret(name) then return nil end
	if type(name) ~= "string" or NameKey(name) == "" then return "" end
	return name
end

-- Nom de l'objet du décor visé en ce moment, mis en lumière ou non ; "" s'il n'en a pas
local function TargetName()
	local unit = ResolveTarget()
	if unit and SafeCall(UnitIsGameObject, unit) == true then return glow.NameOf(unit) end
end

-- Écarte un objet par son nom, ou cesse de l'écarter. Renvoie true s'il est désormais écarté,
-- false s'il ne l'est plus, nil si ce n'est pas un nom. `unnamed` : les objets sans nom, rangés
-- sous le nom vide.
local function ToggleIgnored(name, unnamed)
	local key = type(name) == "string" and NameKey(name) or ""
	if key == "" and not unnamed then return nil end
	if unnamed then key, name = "", "" end
	db.ignored[key] = not db.ignored[key] and name or nil
	S.lastReport = nil
	Evaluate()
	Notify()
	return db.ignored[key] ~= nil
end

-- Écarte l'objet visé, ou cesse de l'écarter, en l'annonçant. Un objet est écarté par son nom,
-- donc avec tous ses pareils : devant un objet déjà écarté, la première demande le dit seulement,
-- et il faut la refaire dans les UNIGNORE_DELAY secondes pour cesser de l'écarter. Sans cela,
-- vouloir écarter le deuxième d'une rangée de chaises les faisait toutes briller de nouveau.
-- (La demande en attente est dans `glow.unignore`.)
local function IgnoreTarget()
	local name = TargetName()
	if not name then
		Print(L.MSG_IGNORE_NO_TARGET)
		return
	end
	local key, now = NameKey(name), GetTime()
	local unnamed = key == ""
	if unnamed then name = L.NAME_UNNAMED end
	local asked = glow.unignore
	glow.unignore = nil
	if db.ignored[key] and not (asked and asked.key == key and now - asked.at <= glow.UNIGNORE_DELAY) then
		glow.unignore = { key = key, at = now }
		Print(L.MSG_IGNORED_ALREADY:format(name))
		return
	end
	Print((ToggleIgnored(name, unnamed) and L.MSG_IGNORED or L.MSG_UNIGNORED):format(name))
end
glow.UNIGNORE_DELAY = 10

-- Noms des objets écartés, par ordre alphabétique
local function IgnoredNames()
	local names = {}
	for _, name in pairs(db.ignored) do names[#names + 1] = name == "" and L.NAME_UNNAMED or name end
	table.sort(names)
	return names
end

-- L'activation, la langue, le bouton de la minimap, ce que Lueur a appris des infobulles et des
-- objets fouillés et les objets écartés ne sont pas des réglages de la lueur : la remise à zéro
-- n'y touche pas
local KEPT_ON_RESET = { enabled = true, language = true, minimap = true, questObjects = true, ignored = true, containers = true }

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
	S.gateOpen, S.lastReport = nil, nil
	if db.enabled then ApplyCVars() end
	Reattach()
	RefreshLabel()
	UpdateTracking()
	Notify()
end

-- Active ou désactive Lueur en l'annonçant : sans le menu sous les yeux, rien d'autre ne le dit
local function Toggle(enabled)
	SetOption("enabled", enabled)
	Print(enabled and L.MSG_ENABLED or L.MSG_DISABLED)
end

-- Nom d'un profil tel qu'il s'affiche
function profiles.Name(id)
	local profile = db.profiles[id]
	return profile and (profile.name or L.PROFILE_DEFAULT)
end

-- Nom tapé par le joueur, mis au propre : sans les séquences du jeu (|c, |T, |H…) ni caractères de
-- contrôle, sans espaces autour, de NAME_MAX lettres au plus. Renvoie nil et la raison quand il ne
-- convient pas : vide, ou porté par un autre profil que `except` (à la casse et aux accents près).
function profiles.Clean(name, except)
	if type(name) ~= "string" then return nil, L.MSG_PROFILE_UNNAMED end
	name = name:gsub("|", ""):gsub("%c", "")
	local letters = {}
	for letter in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if #letters == profiles.NAME_MAX then break end
		letters[#letters + 1] = letter
	end
	name = table.concat(letters):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil, L.MSG_PROFILE_UNNAMED end
	for id in pairs(db.profiles) do
		if id ~= except and NameKey(profiles.Name(id)) == NameKey(name) then return nil, L.MSG_PROFILE_TAKEN:format(profiles.Name(id)) end
	end
	return name
end

-- Donne un profil au personnage, et met ses réglages en service
function profiles.Use(id)
	if not db.profiles[id] then return false end
	cdb.profile = id
	if id ~= db.liveProfile then
		db.profiles[db.liveProfile].settings = profiles.Snapshot()
		profiles.Load(id)
		SanitizeLook()
		ClampAll()
		ApplySilhouette()
		S.gateOpen, S.lastReport = nil, nil
		if db.enabled then ApplyCVars() end
		if glow.anchor then glow.targetR, glow.targetG, glow.targetB = Color(glow.category) end
		Reattach()
		RefreshLabel()
	end
	Notify()
	return true
end

-- Crée un profil et le donne au personnage : aux réglages d'origine, ou avec ceux du profil en service
-- (`copy`). Renvoie false et la raison quand le nom ne convient pas.
function profiles.New(name, copy)
	local clean, reason = profiles.Clean(name)
	if not clean then return false, reason end
	db.profileSeq = db.profileSeq + 1
	db.profiles[db.profileSeq] = { name = clean, settings = copy and profiles.Snapshot() or nil }
	profiles.Use(db.profileSeq)
	return true
end

-- Renomme le profil du personnage
function profiles.Rename(name)
	local clean, reason = profiles.Clean(name, db.liveProfile)
	if not clean then return false, reason end
	db.profiles[db.liveProfile].name = clean
	Notify()
	return true
end

-- Supprime le profil du personnage, qui reprend le premier des autres ; jamais le dernier profil. Les
-- autres personnages qui l'utilisaient reprendront le premier à leur connexion (profiles.Setup).
function profiles.Delete()
	local ids, id = profiles.Ids(), db.liveProfile
	if #ids < 2 then return false end
	profiles.Use(ids[1] ~= id and ids[1] or ids[2])
	db.profiles[id] = nil
	Notify()
	return true
end

-- Les profils, dans l'ordre de leur création : { id, name }
function ns.Profiles()
	local list = {}
	for index, id in ipairs(profiles.Ids()) do list[index] = { id = id, name = profiles.Name(id) } end
	return list
end

function ns.ActiveProfile()
	return db.liveProfile
end

ns.ProfileName, ns.UseProfile, ns.NewProfile, ns.RenameProfile, ns.DeleteProfile = profiles.Name, profiles.Use, profiles.New, profiles.Rename, profiles.Delete

-- Ce dont les fichiers suivants se servent
ns.Notify, ns.GetOption, ns.SetOption, ns.IsCategoryShown, ns.SetCategory = Notify, GetOption, SetOption, IsCategoryShown, SetCategory
ns.HasOwnSettings, ns.ClearOwnSettings, ns.SetColor, ns.SetColor2, ns.SwapColors = HasOwnSettings, ClearOwnSettings, SetColor, SetColor2, SwapColors
ns.IgnoreTarget, ns.IgnoredNames, ns.ToggleIgnored = IgnoreTarget, IgnoredNames, ToggleIgnored
ns.Toggle, ns.ResetOptions, ns.ShowZone = Toggle, ResetOptions, ShowZone

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
