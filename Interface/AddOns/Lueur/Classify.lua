-- Lueur : ce qu'est la cible
-- Le jeu ne dit pas ce qu'est un objet du décor. Sa catégorie se lit dans le curseur qu'il lui
-- donnerait, dans son numéro (le flotteur), dans les quêtes en cours et dans son nom (objets de
-- quête, coffres) ; son état, dans la portée d'interaction. Ce fichier trouve aussi la cible
-- d'interaction du moment et sa nameplate.

local _, ns = ...
local L = ns.L
local S = ns.state
local SafeCall, IsSecret, Fold = ns.SafeCall, ns.IsSecret, ns.Fold

local db
ns.OnSettings(function(account) db = account end)


local SOFT = "softinteract"
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

local cursorLookup = {}      -- fileID -> { catégorie, grisé }
local activeUnits = {}       -- jeton nameplateN -> true
local probe                  -- texture cachée servant à lire l'icône de curseur

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

-- Au chargement des réglages : la texture de lecture et la table des curseurs
function ns.PrepareCursors()
	probe = UIParent:CreateTexture(nil, "BACKGROUND")
	probe:Hide()
	BuildCursorLookup()
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

-- Le journal de quêtes a changé : ses objectifs seront relus au prochain besoin
function ns.MarkQuests()
	questsDirty = true
end

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
	-- pistage qu'il apprend (Découverte d'herbes, Découverte de gisements), ceux que Tracking.lua alterne
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
		if not S.directWorks and SafeCall(UnitIsGameObject, SOFT) == true then S.directWorks = true end
		return SOFT, plate, L.VIA_DIRECT
	end
	if not S.directWorks then
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

-- Ce dont les fichiers suivants se servent
ns.NameKey, ns.RebuildQuestTexts, ns.questTexts, ns.questTitles = NameKey, RebuildQuestTexts, questTexts, questTitles
ns.MatchQuestObjective, ns.LearnFromTooltip, ns.ReadLine, ns.ReadCursor = MatchQuestObjective, LearnFromTooltip, ReadLine, ReadCursor
ns.ObjectID, ns.MatchContainer, ns.LearnContainers, ns.gathered = ObjectID, MatchContainer, LearnContainers, gathered
ns.Classify, ns.Trained, ns.ReadState = Classify, Trained, ReadState
ns.GetNamePlate, ns.ResolveTarget, ns.activeUnits = GetNamePlate, ResolveTarget, activeUnits
