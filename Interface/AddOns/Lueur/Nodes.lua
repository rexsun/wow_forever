-- Lueur : filons et plantes
-- Ce que Lueur sait des nœuds de récolte, pour les montrer sur la minimap (NodeScan.lua) : le
-- métier de chacun, la compétence qu'il demande et l'objet qu'il donne, dont l'icône sert
-- d'image. La minimap ne donne d'un point que son nom, dans la langue du client : il faut donc
-- aller du nom au nœud, sans liste de noms anglais. Dans l'ordre :
--   1. le nom d'un objet que le jeu a déjà désigné comme filon ou plante (Lueur.lua le signale
--      par ns.LearnNode, avec son numéro quand le jeu le donne) ;
--   2. le nom d'une plante, qui est celui de l'objet qu'elle donne : le client le fournit ;
--   3. le nom d'un filon, écrit ici pour les langues que Lueur traduit ;
--   4. le nom d'un nœud connu en tête ou en queue du nom lu (« Filon d'argent couvert de
--      limon ») : pour un filon, ou pour une plante que la règle 1 a confirmée ;
--   5. à défaut, ce que la règle 1 a retenu : le métier seul, sans compétence ni objet.
-- Les numéros d'objet et les compétences sont ceux de Classic ; le cache du client de Forever
-- (build 70338) en confirme trois : 1731, 1618 et 1617. Les noms de filons allemands et espagnols
-- n'ont été recoupés avec aucun client. Un numéro ou un nom faux ne coûte qu'un nœud reconnu plus
-- tard, à la première approche ; un nœud absent d'ici (ceux que Forever ajoute) a alors l'icône
-- de son métier, sans couleur.

local _, ns = ...
local SafeCall, IsSecret, NameKey = ns.SafeCall, ns.IsSecret, ns.NameKey

-- Plantes : compétence requise, objet donné, numéros du nœud
local HERBS = {
	{ 1, 2447, 1618, 3724 },       -- Pacifique
	{ 1, 765, 1617, 3725 },        -- Feuillargent
	{ 15, 2449, 1619, 3726 },      -- Terrestrine
	{ 50, 785, 1620, 3727 },       -- Mage royal
	{ 70, 2450, 1621, 3729 },      -- Églantine
	{ 85, 3820, 2045 },            -- Étouffante
	{ 100, 2453, 1622, 3730 },     -- Doulourante
	{ 115, 3355, 1623 },           -- Aciérite sauvage
	{ 120, 3369, 1628 },           -- Tombeline
	{ 125, 3356, 1624 },           -- Sang-royal
	{ 150, 3357, 2041 },           -- Vietérule
	{ 160, 3818, 2042 },           -- Pâlerette
	{ 170, 3821, 2046 },           -- Dorépine
	{ 185, 3358, 2043 },           -- Moustache de Khadgar
	{ 195, 3819, 2044 },           -- Hivernale
	{ 205, 4625, 2866 },           -- Fleur de feu
	{ 210, 8831, 142140 },         -- Lotus pourpre
	{ 220, 8836, 142141, 176642 }, -- Larmes d'Arthas
	{ 230, 8838, 142142, 176636 }, -- Soleillette
	{ 235, 8839, 142143, 183046 }, -- Aveuglette
	{ 245, 8845, 142144 },         -- Champignon fantôme
	{ 250, 8846, 142145, 176637 }, -- Gromsang
	{ 260, 13464, 176583, 176638 }, -- Sansam doré
	{ 270, 13463, 176584, 176639 }, -- Feuillerêve
	{ 280, 13465, 176586, 176640 }, -- Sauge-argent des montagnes
	{ 285, 13466, 176587, 176641 }, -- Fleur de peste
	{ 290, 13467, 176588 },        -- Calot de glace
	{ 300, 13468, 176589 },        -- Lotus noir
}

-- Filons : compétence requise, objet donné, nom du filon dans VEIN_NAMES, numéros du nœud
local VEINS = {
	{ 1, 2770, "copper", 1731, 2055, 3763, 103713 },
	{ 65, 2771, "tin", 1732, 2054, 3764, 103711 },
	{ 65, 3340, "incendicite", 1610 },
	{ 75, 2775, "silver", 1733, 73940, 105569 },
	{ 75, 4278, "bloodstone", 2653 },
	{ 125, 2772, "iron", 1735 },
	{ 150, 5833, "indurium", 19903 },
	{ 155, 2776, "gold", 1734, 73941 },
	{ 175, 3858, "mithril", 2040, 123310 },
	{ 230, 7911, "truesilver", 2047, 123309 },
	{ 230, 11370, "darkiron", 165658 },
	{ 245, 10620, "thorium", 324, 123848, 150082, 176643 },
	{ 275, 10620, "richthorium", 175404, 177388 },
}

-- Le nom d'un filon n'est pas celui de son minerai, et le client ne le donne à un addon que devant
-- le filon. Ils sont rangés par langue de client, comme les adjectifs de Locales.lua : ce sont des
-- noms du jeu, pas des textes de Lueur.
local VEIN_NAMES = {
	enUS = {
		copper = "Copper Vein", tin = "Tin Vein", incendicite = "Incendicite Mineral Vein", silver = "Silver Vein",
		bloodstone = "Lesser Bloodstone Deposit", iron = "Iron Deposit", indurium = "Indurium Mineral Vein",
		gold = "Gold Vein", mithril = "Mithril Deposit", truesilver = "Truesilver Deposit",
		darkiron = "Dark Iron Deposit", thorium = "Small Thorium Vein", richthorium = "Rich Thorium Vein",
	},
	frFR = {
		copper = "Filon de cuivre", tin = "Filon d'étain", incendicite = "Filon d'incendicite", silver = "Filon d'argent",
		bloodstone = "Gisement de pierre de sang inférieure", iron = "Gisement de fer", indurium = "Filon d'indurium",
		gold = "Filon d'or", mithril = "Gisement de mithril", truesilver = "Gisement de vrai-argent",
		darkiron = "Gisement de sombrefer", thorium = "Petit filon de thorium", richthorium = "Riche filon de thorium",
	},
	deDE = {
		copper = "Kupfervorkommen", tin = "Zinnvorkommen", silver = "Silbervorkommen", iron = "Eisenvorkommen",
		gold = "Goldvorkommen", mithril = "Mithrilablagerung", truesilver = "Echtsilberablagerung",
		darkiron = "Dunkeleisenablagerung", thorium = "Kleines Thoriumvorkommen", richthorium = "Reiches Thoriumvorkommen",
	},
	esES = {
		copper = "Filón de cobre", tin = "Filón de estaño", silver = "Filón de plata", iron = "Depósito de hierro",
		gold = "Filón de oro", mithril = "Depósito de mitril", truesilver = "Depósito de veraplata",
		darkiron = "Depósito de hierro negro", thorium = "Filón pequeño de torio", richthorium = "Filón de torio enriquecido",
	},
	-- noms de la base russe de Wowhead Classic (www.wowhead.com/classic/ru/object=<numéro>), le 2026-10-21
	ruRU = {
		copper = "Медная жила", tin = "Оловянная жила", incendicite = "Ароматитовая жила", silver = "Серебряная жила",
		bloodstone = "Малое месторождение кровавого камня", iron = "Залежи железа", indurium = "Индарилиевая жила",
		gold = "Золотая жила", mithril = "Мифриловые залежи", truesilver = "Залежи истинного серебра",
		darkiron = "Залежи черного железа", thorium = "Малая ториевая жила", richthorium = "Богатая ториевая жила",
	},
}
local SAME_AS = { enGB = "enUS", esMX = "esES" }

local SKILL_LINE = { herb = 182, ore = 186 }  -- Herboristerie et Minage dans les données du jeu
local MAX_AFFIX = 28      -- ce qu'un nom peut porter de lettres en plus de celui du nœud qu'il contient
local MAX_RESOLVED = 400  -- noms dont la réponse est gardée ; au-delà, on repart de zéro

-- Couleurs de difficulté : celles du jeu quand il les expose, sinon leurs valeurs habituelles
local COLORS = {
	impossible = { "IMPOSSIBLE_DIFFICULTY_COLOR", 1, 0.1, 0.1 },
	difficult = { "DIFFICULT_DIFFICULTY_COLOR", 1, 0.5, 0.25 },
	fair = { "FAIR_DIFFICULTY_COLOR", 1, 1, 0 },
	easy = { "EASY_DIFFICULTY_COLOR", 0.25, 0.75, 0.25 },
	trivial = { "TRIVIAL_DIFFICULTY_COLOR", 0.5, 0.5, 0.5 },
}

local byId = {}           -- numéro d'objet -> nœud
local byName = {}         -- nom replié -> nœud
local pending = {}        -- objet dont le client n'a pas encore donné le nom -> la plante qui le donne
local generic = { herb = { kind = "herb" }, ore = { kind = "ore" } }  -- nœud dont seul le métier est connu
local resolved, resolvedCount = {}, 0  -- nom replié -> nœud, ou false : la réponse déjà trouvée
local built = false       -- les noms ont-ils été demandés au client ?
local skills = {}         -- métier -> { rank, total, name }, false si le jeu ne le dit pas ; vidé pour le relire
local lastKind, lastTime  -- métier du dernier nœud que le jeu a désigné, et quand

local nodes = {}
for _, entry in ipairs(HERBS) do
	local node = { kind = "herb", skill = entry[1], item = entry[2] }
	node.ids = {}
	for index = 3, #entry do
		byId[entry[index]] = node
		node.ids[#node.ids + 1] = entry[index]
	end
	nodes[#nodes + 1] = node
end
for _, entry in ipairs(VEINS) do
	local node = { kind = "ore", skill = entry[1], item = entry[2], vein = entry[3] }
	node.ids = {}
	for index = 4, #entry do
		byId[entry[index]] = node
		node.ids[#node.ids + 1] = entry[index]
	end
	nodes[#nodes + 1] = node
end

local function ClientLocale()
	local code = GetLocale()
	return SAME_AS[code] or code
end

local function Forget()
	resolved, resolvedCount = {}, 0
end

local function Index(name, node)
	if type(name) ~= "string" or name == "" then return end
	byName[NameKey(name)] = node
	Forget()
end

-- Nom d'un objet dans la langue du client ; nil tant que le client ne l'a pas en mémoire
local function ItemName(item)
	local name
	if C_Item and C_Item.GetItemNameByID then
		name = SafeCall(C_Item.GetItemNameByID, item)
	elseif GetItemInfo then
		name = SafeCall(GetItemInfo, item)
	end
	return type(name) == "string" and name ~= "" and name or nil
end

-- Demande au client le nom de chaque nœud. Celui d'une plante peut manquer encore : le client le
-- charge alors, et prévient par GET_ITEM_INFO_RECEIVED.
local function Build()
	built = true
	local veins = VEIN_NAMES[ClientLocale()] or {}
	for _, node in ipairs(nodes) do
		if node.kind == "ore" then
			Index(veins[node.vein], node)
		else
			local name = ItemName(node.item)
			if name then
				Index(name, node)
			else
				pending[node.item] = node
				if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, node.item) end
			end
		end
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, item)
	if event == "SKILL_LINES_CHANGED" then
		skills = {}
		return
	end
	local node = type(item) == "number" and pending[item]
	local name = node and ItemName(item)
	if name then
		pending[item] = nil
		Index(name, node)
	end
end)
pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")

-- Noms appris dans la langue de ce client
local function Learned(create)
	local db = ns.db
	if not db then return nil end
	local code = ClientLocale()
	if create and type(db.nodeNames[code]) ~= "table" then db.nodeNames[code] = {} end
	return db.nodeNames[code]
end

-- Le nœud connu dont le nom ouvre ou ferme celui-ci, pour ce métier ; le plus long l'emporte
local function Variant(key, kind)
	local best, length = nil, 0
	-- l'ajout se compte en lettres : une lettre cyrillique tient deux octets
	local letters = select(2, key:gsub("[^\128-\191]", ""))
	for known, node in pairs(byName) do
		local size = #known
		if node.kind == kind and size > length and #key > size + 1
			and letters - select(2, known:gsub("[^\128-\191]", "")) <= MAX_AFFIX
			and (key:sub(-size - 1) == " " .. known or key:sub(1, size + 1) == known .. " ") then
			best, length = node, size
		end
	end
	return best
end

local function Resolve(key)
	local names = Learned()
	local learned = names and names[key]
	if type(learned) ~= "table" then learned = nil end
	local node = learned and learned.id and byId[learned.id] or byName[key]
	if node then return node end
	-- le nom d'une plante est souvent un mot de tous les jours (« Pacifique ») : sa variante n'est
	-- admise que si le jeu a déjà désigné cet objet comme une plante
	node = Variant(key, learned and learned.kind or "ore")
	if node then return node end
	return learned and generic[learned.kind] or nil
end

-- Le nœud que désigne ce nom lu sur la minimap, ou nil si ce n'en est pas un. Un nœud a un
-- métier (`kind`), et le plus souvent une compétence requise (`skill`) et un objet (`item`).
function ns.NodeOf(name)
	if IsSecret(name) or type(name) ~= "string" then return nil end
	if not built then Build() end
	local key = NameKey(name)
	local node = resolved[key]
	if node == nil then
		if resolvedCount >= MAX_RESOLVED then Forget() end
		node = Resolve(key) or false
		resolved[key], resolvedCount = node, resolvedCount + 1
	end
	return node or nil
end

-- Le jeu vient de désigner cet objet comme un filon ou une plante (Lueur.lua) : son nom est
-- retenu, avec son numéro s'il est lisible
function ns.LearnNode(name, id, category)
	if not generic[category] or IsSecret(name) or type(name) ~= "string" then return end
	lastKind, lastTime = category, GetTime()
	local names = Learned(true)
	local key = NameKey(name)
	if not names or key == "" then return end
	local known = names[key]
	if type(known) ~= "table" then known = nil end
	if known and known.kind == category and (not id or known.id == id) then return end
	names[key] = { kind = category, id = id or (known and known.kind == category and known.id) or nil }
	Forget()
end

-- Métier du nœud que le jeu désignait il y a moins de `seconds` : celui que le joueur vient de récolter
function ns.LastNodeKind(seconds)
	if lastTime and GetTime() - lastTime <= seconds then return lastKind end
end

-- Image d'un nœud : l'icône de l'objet qu'il donne (un numéro de fichier), ou nil
function ns.NodeIcon(node)
	if not node.icon and node.item then
		local icon
		if C_Item and C_Item.GetItemIconByID then icon = SafeCall(C_Item.GetItemIconByID, node.item) end
		if not icon and GetItemInfoInstant then
			local ok, _, _, _, _, file = pcall(GetItemInfoInstant, node.item)
			if ok and not IsSecret(file) then icon = file end
		end
		node.icon = icon or nil
	end
	return node.icon
end

-- Compétence du joueur dans un métier de récolte : la sienne (`rank`), celle que lui donnent en
-- plus sa race et son équipement (`total`), et le nom du métier ; nil si le jeu ne la dit pas
local function Skill(kind)
	local skill = skills[kind]
	if skill == nil then
		skill = false
		local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and SafeCall(C_SkillInfo.GetSkillLineInfoByID, SKILL_LINE[kind])
		if type(info) == "table" then
			local rank, bonus, most, name = info.rank, info.modifier, info.maxRank, info.name
			if not IsSecret(rank) and not IsSecret(bonus) and not IsSecret(most) and type(rank) == "number"
				and (type(most) ~= "number" or most > 0) then
				skill = { rank = rank, total = rank + (type(bonus) == "number" and bonus or 0),
					name = not IsSecret(name) and type(name) == "string" and name or nil }
			end
		end
		skills[kind] = skill
	end
	return skill or nil
end
ns.GatherSkill = Skill

-- Fait relire la compétence au prochain besoin
function ns.ForgetSkills()
	skills = {}
end

-- Difficulté d'un nœud pour le joueur, du nom des couleurs du jeu : "impossible" (compétence
-- insuffisante), "difficult", "fair", "easy", "trivial" ; nil si elle ne se sait pas. Les seuils
-- des quatre dernières sont ceux de la récolte dans Classic (requis, +25, +50, +100).
function ns.NodeDifficulty(node)
	if not node.skill then return nil end
	local skill = Skill(node.kind)
	if not skill then return nil end
	if skill.total < node.skill then return "impossible" end
	local margin = skill.rank - node.skill
	if margin < 25 then return "difficult" end
	if margin < 50 then return "fair" end
	if margin < 100 then return "easy" end
	return "trivial"
end

function ns.DifficultyColor(level)
	local entry = COLORS[level]
	local color = _G[entry[1]]
	if type(color) == "table" and color.GetRGB then
		local ok, r, g, b = pcall(color.GetRGB, color)
		if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	end
	return entry[2], entry[3], entry[4]
end

-- Ce que le jeu écrirait d'un objet que le joueur ne peut pas utiliser (« Requiert Herboristerie
-- (70) »), pour un nœud au-dessus de sa compétence ; nil pour tout autre
function ns.NodeRequirement(node)
	if ns.NodeDifficulty(node) ~= "impossible" then return nil end
	local skill = Skill(node.kind)
	if not skill.name or type(ITEM_MIN_SKILL) ~= "string" then return nil end
	local ok, text = pcall(string.format, ITEM_MIN_SKILL, skill.name, node.skill)
	return ok and text or nil
end

