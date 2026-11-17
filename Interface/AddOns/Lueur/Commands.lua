-- Lueur : les commandes /lueur
-- Chaque commande règle par les mêmes fonctions que le menu (Settings.lua) et annonce ce
-- qu'elle a fait. Les noms anglais répondent partout ; ceux de la langue affichée et les noms
-- affichés des effets et des polices s'y ajoutent (ALIASES).

local _, ns = ...
local L = ns.L
local EFFECTS = ns.EFFECTS
local S, glow, silhouette = ns.state, ns.glow, ns.silhouette
local DEFAULTS, CHAR_DEFAULTS, LIMITS, CATEGORY_ORDER = ns.DEFAULTS, ns.CHAR_DEFAULTS, ns.LIMITS, ns.CATEGORY_ORDER
local Print, SafeCall, Fold, Color, Look = ns.Print, ns.SafeCall, ns.Fold, ns.GetColor, ns.Look
local EffectLabel, CategoryLabel, CategoryName = ns.EffectLabel, ns.CategoryLabel, ns.CategoryName
local MANAGED_CVARS, WATCHED_CVARS, GetCVarValue, WantedRange = ns.MANAGED_CVARS, ns.WATCHED_CVARS, ns.GetCVarValue, ns.WantedRange
local NameKey, RebuildQuestTexts, questTexts, questTitles, ReadLine, Trained = ns.NameKey, ns.RebuildQuestTexts, ns.questTexts, ns.questTitles, ns.ReadLine, ns.Trained
local Evaluate, Flag, Paused = ns.Evaluate, ns.Flag, ns.Paused
local Notify, GetOption, SetOption, IsCategoryShown, SetCategory = ns.Notify, ns.GetOption, ns.SetOption, ns.IsCategoryShown, ns.SetCategory
local HasOwnSettings, ClearOwnSettings = ns.HasOwnSettings, ns.ClearOwnSettings
local IgnoreTarget, IgnoredNames, ToggleIgnored = ns.IgnoreTarget, ns.IgnoredNames, ns.ToggleIgnored
local Toggle, ShowZone, SilhouetteFailure = ns.Toggle, ns.ShowZone, ns.SilhouetteFailure
local GetInteractKey, SetInteractKey, KeyOwner, KeyText = ns.GetInteractKey, ns.SetInteractKey, ns.KeyOwner, ns.KeyText

local db, cdb
ns.OnSettings(function(account, character) db, cdb = account, character end)


---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

-- Mot tapé -> nom anglais de la commande ou de l'effet : ceux de la langue affichée, et le
-- nom affiché de chaque effet. Les noms anglais répondent toujours.
local ALIASES = {}

local function UseLanguage()
	ns.UseLanguage(db.language)
	for word in pairs(ALIASES) do ALIASES[word] = nil end
	for word, command in pairs(L.COMMANDS) do ALIASES[Fold(word)] = command end
	for _, key in ipairs(ns.EFFECT_ORDER) do ALIASES[Fold(EffectLabel(key))] = key end
	for _, key in ipairs(ns.FontChoices()) do ALIASES[Fold(ns.FontName(key) or L.FONT_GAME)] = key end
end
ns.ApplyLanguage = UseLanguage -- Settings.lua : au chargement des réglages, et quand la langue change

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

-- "/lueur color ore ff8800" colore une catégorie, "/lueur color ore ff8800 00ffcc" lui donne aussi une
-- seconde couleur, "swap" échange les deux, "default" lui rend sa couleur d'origine, seule ; sans
-- couleur, la commande rappelle celles en place
function COMMANDS.color(arg)
	local category, rest = Scoped(arg)
	if not category then return false end
	local function Parse(hex)
		return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
	end
	local function Sample(r, g, b)
		local hex = ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
		return "|cff" .. hex .. hex .. "|r"
	end
	local first, second = rest:match("^#?(%x%x%x%x%x%x)%s*#?(%x*)$")
	local word = ALIASES[rest] or rest
	if first and (second == "" or #second == 6) then
		ns.SetColor(category, Parse(first))
		if second ~= "" then ns.SetColor2(category, Parse(second)) end
	elseif word == "swap" then
		ns.SwapColors(category)
	elseif word == "default" then
		ns.SetColor(category)
		ns.SetColor2(category)
	elseif rest ~= "" then
		return false
	end
	local r, g, b, own = ns.GetColor2(category)
	if own then
		Print(L.MSG_COLOR_TWO:format(CategoryLabel(category), Sample(Color(category)), Sample(r, g, b)))
	else
		Print(L.MSG_COLOR:format(CategoryLabel(category), Sample(Color(category))))
	end
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
		S.lastReport = nil
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
	if S.pendingCVars == "apply" then
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

-- Deux métiers de récolte : sans argument, lance ou arrête l'alternance des deux pistages ; un
-- nombre règle la distance parcourue entre deux bascules
function COMMANDS.switch(arg, number)
	if not ns.UpdateTracking then Print(L.MSG_RESTART) return end
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

-- Sans nom, liste les profils et rappelle celui du personnage ; avec un nom, le lui donne. (Un nom
-- arrive ici en minuscules sans accents, et remplacé par son mot anglais s'il est aussi un mot de commande.)
function COMMANDS.profile(arg)
	local list = ns.Profiles()
	if arg ~= "" then
		for _, profile in ipairs(list) do
			local key = NameKey(profile.name)
			if key == arg or ALIASES[key] == arg then
				ns.UseProfile(profile.id)
				Print(L.SETTING:format(L.HEADER_PROFILE, profile.name))
				return
			end
		end
	end
	local names = {}
	for index, profile in ipairs(list) do names[index] = profile.name end
	Print(L.MSG_PROFILES:format(table.concat(names, ", "), ns.ProfileName(ns.ActiveProfile())))
end

-- Nom de la langue réglée, tel que le menu le montre
local function LanguageName()
	return db.language == "auto" and L.LANGUAGE_AUTO or ns.LOCALES[db.language].LANGUAGE_NAME
end

-- La langue se désigne par "auto", par son code ("frFR"), ses deux premières lettres ou son nom. Deux
-- langues ont les mêmes premières lettres ("zh") : c'est alors celle du client, sinon la première par
-- ordre de code ; le code entier désigne toujours la sienne.
function COMMANDS.language(arg)
	local choice, short
	if arg == "auto" or arg == Fold(L.LANGUAGE_AUTO) then choice = "auto" end
	local codes = {}
	for code in pairs(ns.LOCALES) do codes[#codes + 1] = code end
	table.sort(codes)
	for _, code in ipairs(codes) do
		local texts = ns.LOCALES[code]
		if arg == code:lower() or arg == Fold(texts.LANGUAGE_NAME) then choice = code end
		if arg == code:sub(1, 2) and (not short or code == GetLocale()) then short = code end
	end
	choice = choice or short
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
	print("  " .. L.STATUS_GATE:format(Flag(db.exclusive), S.gateOpen == nil and "?" or S.gateOpen and L.GATE_OPEN or L.GATE_CLOSED))
	print("  " .. L.STATUS_GLOW_ONLY:format(Flag(db.glowOnly), Flag(glow.Plumber())))
	print("  " .. L.STATUS_SILHOUETTE:format(silhouette.failed and L.STATUS_UNAVAILABLE:format(SilhouetteFailure())
		or Flag(db.silhouette)))
	print("  " .. L.STATUS_DIRECT:format(S.directWorks and L.YES or L.STATUS_NOT_YET))
	print("  " .. L.STATUS_RANGE_API:format(Flag(UnitIsInInteractRange ~= nil)))
	local fishing, channel, icon = ReadLine()
	print("  " .. L.STATUS_LINE:format(Flag(fishing), channel and ("%s, %s"):format(channel, tostring(icon)) or L.NAME_NONE))
	print("  " .. L.STATUS_SWITCH:format(Flag(cdb.nodeSwitch), Flag(ns.CanSwitch and ns.CanSwitch())))
	print("  " .. L.STATUS_TRAINED:format(Flag(db.hideUntrained), Flag(Trained("herb")), Flag(Trained("ore"))))
	print("  " .. L.STATUS_PROFILE:format(ns.ProfileName(ns.ActiveProfile()), #ns.Profiles()))
	-- ce qu'ont coûté la recherche de la cible et l'animation de la lueur depuis le dernier /lueur status
	local polls, pollMean, pollWorst = ns.Cost("evaluate")
	local frames, frameMean, frameWorst = ns.Cost("animate")
	if polls and frames then print("  " .. L.STATUS_COST:format(polls, pollMean, pollWorst, frames, frameMean, frameWorst)) end
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
