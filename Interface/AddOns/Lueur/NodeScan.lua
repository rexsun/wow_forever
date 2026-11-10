-- Lueur : filons et plantes sur la minimap
-- Avec le pistage des plantes ou des minerais, le jeu pose sur la minimap un point par nœud,
-- tous pareils. Lueur met à la place de chacun l'icône de ce qu'il donne, dans un anneau dont la
-- couleur dit ce qu'il vaut pour la compétence du joueur, et grisée s'il est dans une grotte
-- (Nodes.lua sait ce qu'est un nœud).
--
-- Le jeu ne dit pas à un addon où sont ces points. Son infobulle (C_TooltipInfo.GetMinimapMouseover)
-- donne en revanche le nom des points qui sont sous la souris, en gris pour un nœud dans une grotte.
-- Jusqu'au build 70862 (2026-11-07) elle suivait une souris fictive promenée sur la minimap
-- (Minimap:UpdateMouseoverAtPoint) ; elle ne suit plus que la vraie. C'est donc la minimap qui se
-- déplace : le temps d'un balayage, elle passe sous le pointeur, invisible, un point par image, et
-- le jeu dit à l'image suivante ce qui est sous lui (reader, plus bas). Un point répond dans une
-- zone d'une dizaine d'unités autour de lui. D'où le balayage, un point essayé par image :
--   1. la grille : les points voisins qui ont répondu le même nom forment un groupe ;
--   2. un groupe qui peut être un seul point du jeu est un nœud, dont le centre se trouve en
--      cherchant ses bords par dichotomie, en largeur puis en hauteur ;
--   3. un groupe deux ou trois fois plus long que large est autant de nœuds en ligne ; tout autre
--      groupe garde les nœuds déjà bien placés qui l'expliquent, ou à défaut une place, son milieu.
--      (Le regard de près de Fit coûtait des centaines de points : il n'a plus cours.)
-- Chaque nœud trouvé est rangé par sa place sur la carte de la zone : entre deux balayages son
-- icône suit ainsi le joueur image par image. Un nœud déjà placé garde sa place tant que les
-- balayages le retrouvent là. Un balayage ne relit que ce que le précédent n'a pas vu, plus un point
-- au milieu de chaque nœud connu, sauf un sur quatre, qui relit tout.
--
-- Un nœud connu reste le même d'un balayage à l'autre (Finish) : il garde son icône, ne change de
-- place que pour une mesure meilleure que la sienne, y glisse au lieu d'y sauter, et ne s'en va
-- qu'au second balayage qui ne le retrouve pas. Son icône suit le joueur entre deux pixels, comme
-- les points du jeu, paraît et s'efface en fondu, et s'estompe au bord de la minimap.
--
-- Ce fichier a son propre cadre et ses propres événements. Il lit les réglages par ns.GetOption
-- et n'est connu de Lueur.lua que par des crochets gardés : ns.UpdateNodes, ns.NodesFailure,
-- ns.ScanReport, ns.ScanNow, ns.RedrawNodes. Vu en jeu le 2026-10-13, deux fois : les icônes se posent
-- sur les points (avec la souris fictive).

local ADDON_NAME, ns = ...
local L = ns.L
local SafeCall, IsSecret = ns.SafeCall, ns.IsSecret
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

local STEP = 10           -- unités de minimap entre deux points de la grille : refait à chaque balayage, d'après le rayon de réponse (reader.Step)
local FINE = 3            -- et entre deux points du regard de près
-- La lecture sous la vraie souris (plus bas) : son état et ses constantes, dans une table, le
-- fichier étant à la limite de 200 variables locales
local reader = {
	GRID = 1.35,          -- pas de la grille, en rayons de réponse : un point du jeu, rond ou carré, en touche toujours un
	MIN_STEP = 8, MAX_STEP = 20,
	TRIES = 3,            -- un point que la vraie souris a manqué de plus de MISS unités est reposé, jusqu'à tant de fois
	MISS = 1,
	REST = 20,            -- secondes : à l'arrêt, un balayage de loin en loin
	RETRY = 1,            -- secondes avant de reprendre un balayage interrompu, ou de réessayer d'en commencer un
	POLL = 0.25,          -- secondes entre deux regards sur le chemin parcouru
	RIM = 15,             -- unités : un groupe entendu aussi près du bord de la minimap peut être un point qu'il tronque (AtRim)
	FULL = 4,             -- un balayage sur tant relit toute la minimap
	MEASURES = 12,        -- groupes dont un balayage cherche les bords ; au-delà, ils gardent leur milieu
	LIMIT = 2.6,          -- un bord se cherche jusqu'à tant de rayons de réponse du milieu du groupe
	SPLIT = 1.35,         -- une demi-largeur de tant de rayons de réponse : plusieurs nœuds de front
	STRIDE = 0.4,         -- pas, en rayons de réponse, dont un bord se cherche avant la dichotomie (Edge)
	PRECISION = 0.4,      -- unités : un bord est trouvé à cela près
	stride = 6,
	LEARN = 1.25,         -- un point seul plus grand que tant de fois le rayon de son métier ne le change pas : c'est peut-être une grappe
	ASPECT = 1.3,         -- un groupe tant de fois plus long que large : plusieurs nœuds en ligne, ou un seul point allongé
	TINY = 0.05,          -- taille des points du jeu pendant un balayage : la flèche du joueur disparaît avec eux
	WINDOW_WAIT = 2,      -- secondes : la souris sur une fenêtre en plein balayage, la minimap reste cachée tout ce temps avant de revenir
	CAMERA_WAIT = 1,      -- et la caméra tournée à la souris (un bouton tenu)
	SHRINK = 0.001,       -- échelle d'un cadre de la minimap qui ne doit pas paraître sous la souris
	SETTLE_MIN = 1.5,     -- secondes après un balayage pendant lesquelles il reste ainsi, au moins
	SETTLE_MAX = 3,       -- et au plus
	EMPTY = MEDIA .. "empty",  -- Media\empty.tga, transparent : le masque de la minimap pendant un balayage
	on = false,           -- la minimap est-elle sous la souris ?
	scans = 0, aborts = 0,
}
local WAIT = 0.75         -- secondes entre deux balayages
local MAX_SLOW = 8        -- à l'arrêt, sans rien de neuf, l'attente s'allonge jusqu'à ce multiple
local IDLE_WAIT = 5       -- sans pistage actif : on regarde de loin en loin s'il y en a un
local SWITCH_WAIT = 1     -- après un changement de pistage, le temps que les points du jeu suivent
local SWITCH_RETRY = 1.5  -- secondes au bout desquelles une bascule que le jeu n'a pas faite est redemandée
local SWITCH_TRIES = 3    -- demandes d'une même bascule, la première comprise
local SWITCH_SETTLE = 0.6 -- secondes après un changement de pistage avant lesquelles rien n'est balayé : les points du jeu changent un instant après lui
local SWITCH_POLL = 0.5   -- entre deux pistages, le temps d'un sort : on regarde de nouveau sous peu
local MAX_ICONS = 40
local MAX_FINE = 1000     -- points du regard de près par balayage, sauf pour le premier groupe s'il en demande plus ; au-delà, un groupe garde son centre
local MAX_DISCS = 6       -- nœuds cherchés dans un groupe
local MIN_VOTES = 6       -- points de contour qu'un cercle doit expliquer pour compter
local MIN_LOOSE = 5       -- points d'un groupe qu'aucun nœud trouvé n'explique : ce qu'un nœud de plus doit en expliquer, et à partir de quoi il en manque un
local TOLERANCE = 2       -- écart admis entre un point de contour et son cercle (unités)
local AHEAD, WIDE = 1.75, 3.75  -- le point du regard de près le plus proche d'un centre en est à deux unités au plus : de lui, le contour se tient à ce rayon de plus que la distance au premier point qui ne répond pas, à cela près
local SNUG = 1.5          -- un disque ne contient aucun point qui n'a pas répondu, à cela près (unités)
local TIGHT, HUG = 1.25, 0.6  -- et le contour qui passe à WIDE de son bord s'en tient pour cette part à TIGHT
local SPARE = 3           -- un nœud qui explique moins de points que cela, que les autres n'expliquent pas, est de trop
local SHARE = 0.2         -- groupe relu comme si ses nœuds avaient tous le même rayon : la part de ce qu'explique le premier, que chaque autre doit expliquer
local WELL, CLEARLY = 3, 3  -- ce que cette lecture laisse au plus d'inexpliqué, et ce dont elle doit faire mieux que l'autre, pour être retenue (points)
local RINGS = 24           -- anneaux du quadrillage du regard de près où se cherche le bord d'un groupe : plus de deux fois MAX_REACH
local HALVINGS = 6        -- dichotomies par bord : à un soixante-quatrième de la distance cherchée près, une unité au plus
local ROUND = 2           -- écart admis entre la plus grande et la plus petite largeur d'un disque seul
local MIN_APART = 4.5     -- deux nœuds plus proches que cela ne se séparent pas (unités)
local SQUARE_RATIO, SQUARE_FILL = 1.25, 0.95  -- un groupe dont le rectangle n'est pas plus allongé que cela, et que ses points remplissent pour cette part, est un seul point carré (Fit)
local MIN_SHARED, SHARED_IN = 5, 1  -- points essayés à cela au moins à l'intérieur de deux disques, où le nom écrit une seule fois dit que c'est un seul nœud (Fit)
local MIN_REACH, MAX_REACH = 6, 30  -- bornes du rayon de réponse d'un point du jeu (unités)
local PIN_REACH = 0.6     -- en pas de grille : jusqu'où un groupe est encore le nœud déjà placé là
local REFIT = 10          -- balayages au bout desquels un groupe déjà séparé est regardé de nouveau
local MERGE = 15          -- mètres : en deçà, une place trouvée est celle d'un nœud déjà connu du même nom (ou d'un rayon de disque, s'il fait plus)
local TWIN = 0.6          -- en rayons de disque : un nœud non retrouvé aussi près d'un nœud du même nom que le balayage vient de placer est ce nœud
local AVERAGE = 8         -- balayages sur lesquels une place approchée se moyenne
local STILL = 1.5         -- unités : un nœud placé avec précision ne bouge pas pour une mesure exacte si proche,
local SLACK = 3           -- ni pour une mesure approchée à moins de cela
local MISSES = 2          -- balayages de suite qui ne lisent aucun nom de son métier, au bout desquels un nœud perd son icône
local GLIDE = 0.12        -- secondes : une icône dont la place est corrigée y glisse, de cette constante de temps
local GLIDE_END = 0.3     -- mètres : en deçà, elle y est
local PICK_REACH = 10     -- mètres : l'icône d'un nœud que le joueur vient de récolter s'en va sans attendre
local PICK_TIME = 3       -- secondes entre le dernier regard du jeu sur un nœud et la fin du butin, et de là au balayage
local CAVE_SHADE = 0.55   -- luminosité de l'icône d'un nœud dans une grotte, qui est aussi grisée
local RING = "node"       -- Media\node.tga : l'anneau en relief qui entoure chaque icône, teinté de la difficulté du nœud
local RING_HOLE = 17.5 / 32  -- part du côté de cette image que prend l'icône entourée (Lueur-outils\gen_node.py)
local FLAT_RIM = 3        -- sans cette image, un disque de couleur dépasse l'icône d'autant, de chaque côté
local PLAIN = { 0.32, 0.29, 0.25 }  -- couleur de l'anneau d'un nœud dont la difficulté ne se sait pas
local FADE_IN, FADE_OUT = 0.25, 0.2 -- secondes que met une icône à paraître, puis à s'effacer
local EDGE_IN, EDGE_OUT = 7, 1      -- unités : une icône s'efface de EDGE_IN avant le bord de la minimap à EDGE_OUT après

-- Sorts de pistage, d'après Blizzard_Minimap\Mainline\Minimap.lua (build 1.60.1.70245)
local FINDERS = { [2383] = "herb", [8387] = "herb", [2580] = "ore", [8388] = "ore" }
local OPTION = { herb = "nodeHerbs", ore = "nodeOre" }
-- Image d'un nœud dont l'objet n'est pas connu : celle du bouton de pistage, sinon l'icône du métier
local KIND_ATLAS = { herb = "professions_tracking_herb", ore = "professions_tracking_ore" }
local KIND_ICON = { herb = "Interface\\Icons\\Trade_Herbalism", ore = "Interface\\Icons\\Trade_Mining" }
local CIRCLE = "CircleMask"
local CIRCLE_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- La flèche du joueur au centre de la minimap : l'atlas que le client nomme parmi les flèches de la
-- minimap (WowB.exe, build 70338), sinon l'image des clients d'avant, à une taille estimée
local PLAYER_ARROW = "ui-hud-minimap-arrow-player"
local PLAYER_ARROW_FILE, PLAYER_ARROW_SIZE = "Interface\\Minimap\\MinimapArrow", 24

local driver = CreateFrame("Frame")  -- fait tourner le balayage (OnUpdate) et reçoit les événements
local holder              -- cadre posé sur la minimap, qui porte les icônes
local pointer             -- la flèche du joueur, redessinée par-dessus une icône qui la recouvre
local covering = false    -- une icône recouvre-t-elle la flèche du joueur ?
local spare = {}          -- icônes qu'aucun nœud ne porte plus : le prochain qui en demande une la reprend
local markers = {}        -- nœuds connus : ceux du dernier balayage, ceux qu'il vient de manquer, ceux gardés d'un autre pistage
local ghosts = {}         -- nœuds qui ne le sont plus, le temps que leur icône s'efface
local busy = false        -- une icône au moins glisse vers sa place, paraît ou s'efface : le suivi ne s'arrête pas
local pickedAt            -- quand le butin s'est refermé pour la dernière fois
local probes = 0          -- points essayés depuis le chargement
local last = {}           -- ce qu'a coûté le dernier balayage : points, secondes, groupes regardés de près
local scan                -- balayage en cours
local wait, slow = 0, 1   -- secondes avant le prochain, et de combien l'attente est allongée
-- Rayon courant dans lequel un point du jeu répond (unités), par métier : `value`, ajusté sur les
-- nœuds isolés ; `measured`, s'il l'a été ou n'est encore qu'une estimation. Chaque nœud a le
-- sien (`marker.reach`), lu de son disque : celui-ci ne sert qu'à défaut, et à relire un groupe de
-- nœuds serrés comme s'ils l'avaient tous (Fit). Ni un rayon pour tous les points, ni un rayon par
-- métier n'ont tenu en jeu (2026-10-13 : des nœuds montrés par paires d'icônes, à dix-huit unités
-- l'une de l'autre puis côte à côte, ce que donne un disque cherché avec un rayon trop petit).
local reaches = { herb = { value = 15, measured = false }, ore = { value = 15, measured = false } }
local grid, gridWidth     -- points de la grille, pour cette largeur de minimap
local left, bottom, scale, width  -- place et échelle de la minimap pendant le balayage
local broken              -- erreur levée par le jeu pendant un balayage : il ne reprend pas
local masks               -- nil : pas encore essayé ; false : ce client ne sait pas découper une icône
local lastNames = {}      -- nom lu par le dernier balayage -> { points, gray }
local seen = {}           -- ce d'où le dernier suivi est parti : carte, place, orientation, rayon
local spot = {}           -- où était le joueur à la fin du dernier balayage
-- alternance des pistages : métier actif (kind), lieu de la dernière bascule (map, x, y), balayage fait depuis (scanned),
-- la bascule demandée au jeu tant qu'il ne l'a pas faite : le métier voulu (want), quand (at), combien de fois (tries) ;
-- et quand le jeu a annoncé pour la dernière fois un changement de pistage (changed)
local turn = {}
local looting = false
local refit = false       -- le joueur vient de récolter : les groupes déjà séparés sont à revoir
local hooked = false      -- l'infobulle de la minimap est-elle complétée ?

local function Wanted(kind)
	return ns.GetOption(OPTION[kind])
end

-- Nom du texte qui dit pourquoi ce client ne permet pas le balayage, ou nil
local function Failure()
	if broken then return "FAIL_SCAN_ERROR" end
	-- (la souris fictive ne sert plus, mais son API reste la marque d'un client où l'infobulle de la
	-- minimap nomme les points un à un : Forever. Classic Era ne l'a pas, et rien n'y a été essayé.)
	if not (Minimap and Minimap.UpdateMouseoverAtPoint and Minimap.AdjustPointsOffset and GetCursorPosition
		and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover
		and C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then
		return "FAIL_NO_SCAN"
	end
end

function ns.NodesFailure()
	local failure = Failure()
	return failure and L[failure]
end

local function HasAtlas(atlas)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	return ok and info ~= nil
end

local function Round(value)
	return math.floor(value + 0.5)
end

---------------------------------------------------------------------------
-- Où est le joueur, et ce que montre la minimap
---------------------------------------------------------------------------

-- Carte de la zone, place du joueur sur elle (0 à 1, y vers le sud) et taille de la carte en
-- mètres ; nil quand le jeu ne le dit pas (en instance)
local function MapPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return nil end
	local map = SafeCall(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" then return nil end
	local position = SafeCall(C_Map.GetPlayerMapPosition, map, "player")
	if type(position) ~= "table" or not position.GetXY then return nil end
	local ok, x, y = pcall(position.GetXY, position)
	if not ok or IsSecret(x) or IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
	local sized, wide, tall = pcall(C_Map.GetMapWorldSize, map)
	if not sized or IsSecret(wide) or IsSecret(tall) or type(wide) ~= "number" or type(tall) ~= "number" then return nil end
	if wide <= 0 or tall <= 0 then return nil end
	return map, x, y, wide, tall
end

-- Rayon de la minimap en mètres, si elle tourne avec le joueur, et l'orientation du joueur
-- (radians, sens inverse des aiguilles depuis le nord)
local function View()
	local radius = SafeCall(C_Minimap.GetViewRadius)
	if type(radius) ~= "number" or radius <= 0 then return nil end
	local turning = C_CVar and C_CVar.GetCVar and SafeCall(C_CVar.GetCVar, "rotateMinimap") == "1"
	if turning and C_Minimap.IsRotateMinimapIgnored and SafeCall(C_Minimap.IsRotateMinimapIgnored) == true then turning = false end
	local facing = GetPlayerFacing and SafeCall(GetPlayerFacing)
	if type(facing) ~= "number" then facing = nil end
	return radius, turning or false, facing
end

-- La forme de la minimap : ronde, carrée, ou l'une et l'autre par quart (1 en bas à droite, 2 en bas
-- à gauche, 3 en haut à droite, 4 en haut à gauche). La table et la numérotation sont celles de
-- LibDBIcon-1.0, que suivent les addons de minimap par la globale GetMinimapShape (relevées dans
-- NodeSight 1.9.0, MinimapShape.lua). Un quart rond s'arrête au cercle, un quart carré va jusqu'au
-- coin. EllesmereUI (9.8.3) dit d'abord la sienne, puisque sa minimap remplace celle du jeu, et rogne
-- en haut et en bas sa minimap 4:3 par les retraits de sa zone de clic (SetHitRectInsets).
-- Ronde, rien ne change : les quarts carrés n'ont été essayés que dans le faux client.
reader.SHAPES = {
	ROUND = { true, true, true, true }, SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
reader.ELLESMERE = { circle = "ROUND", textured_circle = "ROUND", square = "SQUARE", rectangular = "SQUARE" }

-- Les quarts de la minimap, et la part de sa demi-largeur jusqu'où va un quart carré en hauteur
-- (`height`, 1 sans rognure). Relus une fois par image au plus.
function reader.Quarters()
	local now = GetTime()
	if reader.quarters and reader.shapeAt == now then return reader.quarters end
	reader.shapeAt = now
	local name
	local module = type(EllesmereUI) == "table" and type(EllesmereUI._ModuleNS) == "table" and EllesmereUI._ModuleNS.EllesmereUIMinimap
	if type(module) == "table" and type(module.MinimapShape) == "function" then
		local ok, shape = pcall(module.MinimapShape)
		if ok and not IsSecret(shape) then name = reader.ELLESMERE[shape] end
	end
	if not name and type(GetMinimapShape) == "function" then
		local ok, shape = pcall(GetMinimapShape)
		if ok and not IsSecret(shape) and reader.SHAPES[shape] then name = shape end
	end
	name = name or "ROUND"
	local height = 1
	if name == "SQUARE" and Minimap.GetHitRectInsets then
		local ok, _, _, top, bottom = pcall(Minimap.GetHitRectInsets, Minimap)
		local full = Minimap:GetWidth()
		if ok and type(top) == "number" and type(bottom) == "number" and not IsSecret(top) and not IsSecret(bottom)
			and top > 0 and bottom > 0 and full > 0 then
			height = math.max(0, math.min(1, 1 - 2 * math.max(top, bottom) / full))
		end
	end
	local key = name .. " " .. height
	if not (reader.quarters and reader.quarters.key == key) then
		local quarters = reader.SHAPES[name]
		reader.quarters = { quarters[1], quarters[2], quarters[3], quarters[4], height = height, key = key, name = name, round = name == "ROUND" }
	end
	return reader.quarters
end

-- De combien le point (dx, dy), compté du milieu de la minimap, est en deçà de son bord (unités ;
-- négatif au-delà)
function reader.Depth(dx, dy, half)
	local quarters = reader.Quarters()
	if quarters.round or quarters[1 + (dx < 0 and 1 or 0) + (dy > 0 and 2 or 0)] then
		return half - math.sqrt(dx * dx + dy * dy)
	end
	return math.min(half - math.abs(dx), half * quarters.height - math.abs(dy))
end

-- Jusqu'où l'on va du point (px, py) dans la direction (dx, dy), de longueur 1, avant d'arriver à
-- `margin` unités du bord ; 0 s'il y est déjà. La minimap est convexe, quelle que soit sa forme :
-- hors du cercle, la distance se trouve par dichotomie.
function reader.Room(px, py, dx, dy, half, margin)
	if reader.Quarters().round then
		local rim = half - margin
		local along = px * dx + py * dy
		local room = along * along - (px * px + py * py - rim * rim)
		if room <= 0 then return 0 end
		return math.max(0, math.sqrt(room) - along)
	end
	if reader.Depth(px, py, half) <= margin then return 0 end
	local inside, outside = 0, 3 * half
	for _ = 1, 24 do
		local middle = (inside + outside) / 2
		if reader.Depth(px + dx * middle, py + dy * middle, half) > margin then inside = middle else outside = middle end
	end
	return inside
end

---------------------------------------------------------------------------
-- Icônes
---------------------------------------------------------------------------

-- Le jeu accroche chaque texture à la grille des pixels. Une icône qui suit le joueur avancerait
-- alors par à-coups d'un pixel, là où les points du jeu glissent : ses textures ne s'y accrochent
-- donc pas, et se posent entre deux pixels comme eux. (Vu en jeu le 2026-10-13, accrochées puis
-- posées par Lueur sur un pixel entier : « se refresh à chaque pas du personnage ».)
local function Loose(region)
	if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
	if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
end

-- Découpe en rond une texture d'une icône ; sans effet sur le client qui ne sait pas
local function Clip(icon, region)
	if masks == false then return end
	local ok, mask = pcall(icon.frame.CreateMaskTexture, icon.frame)
	if ok and mask then
		local set
		if HasAtlas(CIRCLE) then
			set = pcall(mask.SetAtlas, mask, CIRCLE)
		else
			local done, loaded = pcall(mask.SetTexture, mask, CIRCLE_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			set = done and loaded ~= false
		end
		if set and pcall(region.AddMaskTexture, region, mask) then
			mask:SetAllPoints(region)
			Loose(mask)
			masks = true
			return
		end
	end
	masks = false
end

-- Une icône : un cadre (`frame`, par lequel elle se place) qui porte l'image du nœud découpée en
-- rond (`face`) et, par-dessus, l'anneau qui l'entoure (`ring`). Un cadre par icône : deux icônes
-- qui se recouvrent restent chacune d'un seul tenant.
-- Sans l'image de l'anneau (Lueur mis à jour sans relancer le jeu, qui ne charge un nouveau fichier
-- qu'à son démarrage), l'anneau est un disque de couleur sous l'image (`flat`).
local function NewIcon(parent)
	local frame = CreateFrame("Frame", nil, parent)
	local icon = { frame = frame }
	icon.face = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	icon.face:SetAllPoints(frame)
	icon.ring = frame:CreateTexture(nil, "ARTWORK", nil, 2)
	icon.ring:SetPoint("CENTER")
	if icon.ring:SetTexture(MEDIA .. RING .. ".tga") == false then
		icon.flat = true
		icon.ring:SetDrawLayer("ARTWORK", 0)
	end
	Clip(icon, icon.face)
	-- (l'anneau découpé en rond lui aussi : aminci, son image est rognée en carré, voir DrawIcon)
	Clip(icon, icon.ring)
	Loose(icon.face)
	Loose(icon.ring)
	frame:Hide()
	return icon
end

-- Le jeu dessine la flèche du joueur avec la minimap elle-même, sous tout ce qu'un addon y pose : une
-- icône sur laquelle le joueur se tient la cache. Elle est donc redessinée par-dessus les icônes, à
-- la même place et dans le même sens, le temps qu'une icône la recouvre. (Demandé le 2026-10-15 :
-- « l'icone de navigation (le pointeur) sur la minimap qui représente le joueur doit passer
-- au-dessus des icones des ressources ».)
local function Turn()
	local _, turning, facing = View()
	-- (la minimap qui tourne garde la flèche pointée vers le haut)
	if turning then facing = 0 end
	if facing then pointer.texture:SetRotation(facing) end
	pointer.texture:SetShown(facing ~= nil)
end

local function Pointer(shown)
	if not pointer then
		if not shown then return end
		local frame = CreateFrame("Frame", nil, holder)
		frame:SetAllPoints(holder)
		frame:SetFrameLevel(holder:GetFrameLevel() + 10)
		local texture = frame:CreateTexture(nil, "OVERLAY")
		texture:SetPoint("CENTER", holder, "CENTER")
		if HasAtlas(PLAYER_ARROW) then
			texture:SetAtlas(PLAYER_ARROW, true)
		else
			texture:SetTexture(PLAYER_ARROW_FILE)
		end
		if (texture:GetWidth() or 0) <= 0 then texture:SetSize(PLAYER_ARROW_SIZE, PLAYER_ARROW_SIZE) end
		Loose(texture)
		pointer = { frame = frame, texture = texture }
		frame:SetScript("OnUpdate", Turn)
		frame:Hide()
	end
	if shown and not pointer.frame:IsShown() then Turn() end
	pointer.frame:SetShown(shown)
end

-- La moitié de la diagonale de la flèche : une icône plus proche que cela du centre de la minimap,
-- augmenté de son propre rayon, la recouvre
local function PointerReach()
	if not pointer then return PLAYER_ARROW_SIZE / 2 end
	local w, h = pointer.texture:GetWidth() or 0, pointer.texture:GetHeight() or 0
	return math.sqrt(w * w + h * h) / 2
end

-- Image d'un nœud, et si c'est un atlas
local function Picture(node)
	local file = ns.NodeIcon(node)
	if file then return file, false end
	if HasAtlas(KIND_ATLAS[node.kind]) then return KIND_ATLAS[node.kind], true end
	return KIND_ICON[node.kind], false
end

-- Donne à une icône l'image d'un nœud, à son anneau la couleur de sa difficulté (`level`, ou nil :
-- inconnue), et la grise s'il est dans une grotte. `size` est le diamètre de l'image ; l'anneau
-- l'entoure, d'une épaisseur de `ring` (de 0, pas d'anneau, à 1, celle de son image). Rien n'est
-- refait de ce qui n'a pas changé.
-- Aminci, l'anneau garde son trou à la taille de l'icône : son image est rognée de son bord extérieur
-- (SetTexCoord) et découpée en rond. Il perd alors son cerne sombre et son ombre, qui sont sur ce bord.
-- (Demandé le 2026-11-09 : « jouer sur la taille des bordures des icônes, avec 0 pour désactiver ».)
local function DrawIcon(icon, node, level, cave, size, ring)
	local picture, atlas = Picture(node)
	if icon.picture ~= picture then
		icon.picture = picture
		if atlas then
			icon.face:SetAtlas(picture)
		else
			icon.face:SetTexture(picture)
			icon.face:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- sans le bord dessiné dans les icônes du jeu
		end
	end
	if icon.size ~= size or icon.thick ~= ring then
		icon.size, icon.thick = size, ring
		icon.frame:SetSize(size, size)
		icon.ring:SetShown(ring > 0)
		if icon.flat then
			local around = size + 2 * FLAT_RIM * ring
			icon.ring:SetSize(around, around)
		elseif ring > 0 then
			local margin = (1 - RING_HOLE) / 2 * (1 - ring)
			local around = size * (1 - 2 * margin) / RING_HOLE
			icon.ring:SetSize(around, around)
			icon.ring:SetTexCoord(margin, 1 - margin, margin, 1 - margin)
		end
	end
	level = level or false
	if icon.level ~= level then
		icon.level = level
		local r, g, b = PLAIN[1], PLAIN[2], PLAIN[3]
		if level then r, g, b = ns.DifficultyColor(level) end
		-- l'anneau est une image en gris, que la couleur teinte : son cerne et son ombre, noirs, le restent
		if icon.flat then icon.ring:SetColorTexture(r, g, b, 1) else icon.ring:SetVertexColor(r, g, b) end
	end
	cave = cave and true or false
	if icon.cave ~= cave then
		icon.cave = cave
		local shade = cave and CAVE_SHADE or 1
		icon.face:SetDesaturated(cave)
		icon.face:SetVertexColor(shade, shade, shade)
	end
end

-- Icônes témoins, pour la page de la minimap de la fenêtre des réglages (Menu.lua) : les mêmes cadres
-- et le même dessin que sur la minimap. `samples` : { objet donné, métier, difficulté, dans une grotte,
-- x, y } ; les places sont en fractions de `radius`. Renvoie de quoi les redessiner à une taille et une
-- épaisseur d'anneau, celles des plantes ou des filons éteintes si elles ne sont pas montrées.
function ns.NodeSamples(parent, samples, radius)
	local icons = {}
	for index, sample in ipairs(samples) do
		local icon = NewIcon(parent)
		icon.frame:SetPoint("CENTER", parent, "CENTER", sample[5] * radius, sample[6] * radius)
		icon.frame:SetFrameLevel(parent:GetFrameLevel() + 1)
		icon.node = { kind = sample[2], item = sample[1] }
		icons[index] = icon
	end
	return function(size, ring, herbs, ore)
		for index, sample in ipairs(samples) do
			local icon = icons[index]
			DrawIcon(icon, icon.node, sample[3], sample[4], size, ring)
			icon.frame:SetAlpha((sample[2] == "herb" and herbs or sample[2] == "ore" and ore) and 1 or 0.25)
			icon.frame:Show()
		end
	end
end

local function ShowIcon(icon, shown)
	if icon.shown == shown then return end
	icon.shown = shown
	icon.frame:SetShown(shown)
end

-- Rend l'icône d'un nœud, qui servira à un autre
local function Free(marker)
	local icon = marker.icon
	if not icon then return end
	marker.icon = nil
	ShowIcon(icon, false)
	spare[#spare + 1] = icon
end

-- Un nœud n'est plus : son icône s'efface là où elle est, au lieu de disparaître d'un coup
local function Fade(marker)
	if not (marker.icon and marker.icon.shown) then
		Free(marker)
		return
	end
	marker.gone = GetTime()
	ghosts[#ghosts + 1] = marker
	busy = true
end

-- Ce qu'une icône garde d'opacité à cet endroit : elle s'efface en passant le bord de la minimap,
-- au lieu d'en déborder puis de disparaître d'un coup
local function Edge(marker, half)
	if marker.lost or not Wanted(marker.node.kind) then return 0 end
	local x, y = (marker.sx or marker.x) - half, (marker.sy or marker.y) - half
	return math.max(0, math.min(1, (reader.Depth(x, y, half) + EDGE_OUT) / (EDGE_IN + EDGE_OUT)))
end

-- Pose l'icône d'un nœud à sa place, avec cette opacité. Un nœud garde la sienne tant qu'il se
-- montre : aucune ne change d'image parce que la liste des nœuds a changé d'ordre.
local function Paint(marker, alpha, size, ring)
	local icon = marker.icon
	if not icon then
		icon = table.remove(spare) or NewIcon(holder)
		marker.icon = icon
	end
	DrawIcon(icon, marker.node, ns.NodeDifficulty(marker.node), marker.gray, size, ring)
	local x, y = marker.sx or marker.x, marker.sy or marker.y
	icon.frame:SetPoint("CENTER", holder, "BOTTOMLEFT", x, y)
	-- l'anneau déborde l'image : RING_HOLE en dit la part
	local half, reach = Minimap:GetWidth() / 2, size * (1 + (1 / RING_HOLE - 1) * ring) / 2 + PointerReach()
	if alpha > 0 and (x - half) ^ 2 + (y - half) ^ 2 < reach * reach then covering = true end
	if icon.alpha ~= alpha then
		icon.alpha = alpha
		icon.frame:SetAlpha(alpha)
	end
	ShowIcon(icon, true)
end

-- Met les icônes en accord avec les nœuds connus, et avec ceux qui s'en vont
local function Draw()
	if not holder then return end
	local size, shown, now, half = ns.GetOption("nodeSize"), 0, GetTime(), Minimap:GetWidth() / 2
	local ring = (ns.GetOption("nodeRing") or 100) / 100
	covering = false
	for _, marker in ipairs(markers) do
		local edge = Edge(marker, half)
		if shown < MAX_ICONS and edge > 0 then
			shown = shown + 1
			local life = math.min(1, (now - marker.born) / FADE_IN)
			if life < 1 then busy = true end
			Paint(marker, edge * life, size, ring)
		else
			Free(marker)
		end
	end
	for index = #ghosts, 1, -1 do
		local marker = ghosts[index]
		local life = math.min(1, (now - marker.born) / FADE_IN, 1 - (now - marker.gone) / FADE_OUT)
		local edge = Edge(marker, half)
		if marker.icon and life > 0 and edge > 0 then
			busy = true
			Paint(marker, edge * life, size, ring)
		else
			Free(marker)
			table.remove(ghosts, index)
		end
	end
	-- (pendant un balayage, la flèche du jeu est rapetissée avec les points : celle de Lueur la remplace)
	Pointer(covering or reader.on)
end

-- Oublie tous les nœuds, sur-le-champ ; et ce que le dernier balayage a vu, qui n'a plus de nœud pour le dire
local function Clear()
	for _, marker in ipairs(markers) do Free(marker) end
	for _, marker in ipairs(ghosts) do Free(marker) end
	markers, ghosts, reader.cover = {}, {}, nil
	Pointer(false)
end

-- Où le point (mx, my) de la carte de la zone tombe sur la minimap, pour ce que `seen` dit du
-- joueur et d'elle : x, y, sa distance au centre (unités), et en mètres
local function Spot(mx, my)
	local east, north = (mx - seen.x) * seen.wide, (seen.y - my) * seen.tall
	local yards = math.sqrt(east * east + north * north)
	local way = math.atan2(east, north) -- sens des aiguilles depuis le nord
	if seen.turning then way = way + seen.facing end
	local distance = yards / seen.radius * seen.half
	return seen.half + distance * math.sin(way), seen.half + distance * math.cos(way), distance, yards
end

-- Entre deux balayages un nœud ne bouge pas, le joueur si : chaque icône est replacée d'après
-- la place du nœud sur la carte. Sans carte (en instance), elles restent où le balayage les a vues.
-- Un nœud dont un balayage vient de corriger la place (`dmx`, `dmy` : ce qui l'en sépare encore)
-- montre son icône en chemin (`sx`, `sy`).
local function Track(marker, rest)
	if marker.map == seen.map then
		local distance
		marker.x, marker.y, distance, marker.yards = Spot(marker.mx, marker.my)
		marker.far, marker.lost = reader.Depth(marker.x - seen.half, marker.y - seen.half, seen.half) < 0, nil
		if marker.dmx then
			marker.dmx, marker.dmy = marker.dmx * rest, marker.dmy * rest
			if (marker.dmx * seen.wide) ^ 2 + (marker.dmy * seen.tall) ^ 2 < GLIDE_END * GLIDE_END then
				marker.dmx, marker.dmy, marker.sx, marker.sy = nil, nil, nil, nil
			else
				marker.sx, marker.sy = Spot(marker.mx + marker.dmx, marker.my + marker.dmy)
				busy = true
			end
		end
	elseif marker.map then
		-- rangé sur une autre carte que celle où le joueur vient de passer : sa place ne se sait
		-- plus, et le prochain balayage le retrouvera s'il est encore là
		marker.far, marker.lost = true, true
	end
end

local function Follow(elapsed)
	if not (markers[1] or ghosts[1]) then return end
	local map, x, y, wide, tall = MapPosition()
	local radius, turning, facing
	if map then radius, turning, facing = View() end
	if radius and not (turning and not facing) then
		if not busy and map == seen.map and x == seen.x and y == seen.y and radius == seen.radius and turning == seen.turning
			and (not turning or facing == seen.facing) then
			return
		end
		seen.map, seen.x, seen.y, seen.radius, seen.turning, seen.facing = map, x, y, radius, turning, facing
		seen.wide, seen.tall, seen.half = wide, tall, Minimap:GetWidth() / 2
		local rest = math.exp(-(elapsed or 0) / GLIDE)
		busy = false
		for _, marker in ipairs(markers) do Track(marker, rest) end
		for _, marker in ipairs(ghosts) do Track(marker, rest) end
	elseif busy then
		busy = false -- sans carte, rien ne suit le joueur ; les icônes qui paraissent ou s'effacent continuent
	else
		return
	end
	Draw()
end

---------------------------------------------------------------------------
-- Lire la minimap sous la vraie souris
---------------------------------------------------------------------------
-- Depuis la maintenance du 2026-11-07 (build 70862), l'infobulle de la minimap ne suit plus que la
-- vraie souris : la souris fictive ne lit plus rien (LueurDB.coordProbe, le 2026-11-07 : quatorze
-- conventions de coordonnées, aucune réponse). C'est donc la minimap qui vient sous le pointeur : à
-- chaque image, elle se pose de sorte que le point à lire y soit (Minimap:AdjustPointsOffset), et le
-- jeu dit à l'image suivante ce qu'il y a trouvé. L'idée est celle de NodeSight 1.8.0 ; le code est
-- celui de Lueur.
-- Le temps d'un balayage, la minimap est invisible (un masque vide, et ce qu'elle porte à l'opacité
-- 0), ses points du jeu rapetissés (la flèche du joueur avec eux) et rien d'elle ne prend de clic ni
-- de molette. Les icônes de Lueur restent où elle était, sur un fond sombre de sa forme, avec une copie
-- de son cadre doré, de ses coordonnées et la flèche du joueur ; ce qui est ancré à la minimap sans en
-- être un enfant est masqué et ne prend pas la souris (ce que des joueurs de NodeSight 1.8.1 ont vu :
-- un cadre d'un autre addon promené à l'écran, un autre posé sur la minimap qui empêchait tout
-- balayage). Aucun réglage du jeu ne change, sauf la taille des points, rendue après (et au chargement
-- suivant si le jeu s'est arrêté entre-temps). La souris qui tourne la caméra ou passe sur une
-- fenêtre met le balayage en attente, la minimap chez elle et cachée ; au-delà d'une ou deux
-- secondes, il s'arrête, comme quand la minimap zoome, et reprend un peu plus tard. Il n'a pas lieu en
-- vol avec un maître de vol, ni devant la fenêtre d'un PNJ. Le joueur peut marcher et tourner pendant
-- ce temps : chaque point se lit là où il est passé.
;(function() -- une fonction, pas un bloc : le fichier est à la limite de 200 variables locales
	local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
	local DEPTH = 4          -- générations d'enfants de la minimap dont la souris est coupée
	local stand              -- le fond, le cadre, les coordonnées : ce qui tient la place de la minimap
	local ours = false       -- Lueur change-t-il en ce moment la taille des points du jeu ?

	-- La taille que le joueur a donnée aux points du jeu (Edit Mode, ou un addon) : la minimap ne la
	-- dit pas, on la retient quand elle change, sinon on la lit dans le réglage du Mode Édition
	if Minimap and Minimap.SetIconScale and hooksecurefunc then
		hooksecurefunc(Minimap, "SetIconScale", function(_, value)
			if not ours and type(value) == "number" and not IsSecret(value) then reader.iconScale = value end
		end)
	end
	local function IconScale()
		if reader.iconScale then return reader.iconScale end
		local setting = Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.IconScale
		if setting and MinimapCluster and MinimapCluster.GetSettingValue then
			local value = SafeCall(MinimapCluster.GetSettingValue, MinimapCluster, setting)
			if type(value) == "number" and value > 0 then return value / 100 end
		end
		return 1
	end
	local function SetIconScale(value)
		if not Minimap.SetIconScale then return end
		ours = true
		pcall(Minimap.SetIconScale, Minimap, value)
		ours = false
	end

	-- Cacher la minimap. Par un masque vide (reader.EMPTY) plutôt que par son opacité : le jeu redessine
	-- vide le terrain d'une minimap qu'il dessine en deçà d'une opacité de 1 (NodeSight 1.9.0 le dit ;
	-- des joueurs de Lueur 1.5.0 ont vu la minimap scintiller, devenir transparente, perdre son fond, le
	-- 2026-11-09). Le masque ne cache que ce qu'elle dessine elle-même, terrain et points : ce qu'elle
	-- porte (ses boutons, ceux des addons, les textes qu'une interface pose dessus) se cache par sa
	-- propre opacité (Cover). Le masque ne se lit pas : le dernier posé est retenu, sinon un carré pour
	-- une minimap qui se dit carrée, sinon celui de Forever (Blizzard_Minimap\Camelot\Skin.lua, build
	-- 70245). Le vide se pose par la méthode du cadre, sans passer par ce qu'un addon a accroché à la
	-- minimap (Leatrix Plus remet aussitôt son masque carré, d'après NodeSight) ; l'autre se rend par le
	-- chemin ordinaire. Sans l'image vide (une mise à jour faite pendant que le jeu tourne) ou sans
	-- SetMaskTexture, c'est l'opacité de la minimap, comme jusqu'à la 1.5.0.
	if Minimap and Minimap.SetMaskTexture and hooksecurefunc then
		hooksecurefunc(Minimap, "SetMaskTexture", function(_, mask)
			if not reader.maskOurs and not IsSecret(mask) then reader.mask = mask end
		end)
	end
	local FOREVER_MASK = "ui-hud-minimap-frame-generic-mask"
	local function MaskBack()
		if reader.mask ~= nil then return reader.mask end
		if not reader.Quarters().round then return "Interface\\Buttons\\WHITE8X8" end
		if HasAtlas(FOREVER_MASK) then return FOREVER_MASK end
		return "Textures\\MinimapMask"
	end
	local function SetMask(mask, direct)
		local set = Minimap.SetMaskTexture
		if direct then
			local meta = getmetatable(Minimap)
			local methods = type(meta) == "table" and meta.__index
			if type(methods) == "table" and type(methods.SetMaskTexture) == "function" then set = methods.SetMaskTexture end
		end
		reader.maskOurs = true
		pcall(set, Minimap, mask)
		reader.maskOurs = false
	end

	-- L'opacité de la minimap, quand c'est par elle qu'elle se cache : tenue à 0 tant qu'elle est sous la
	-- souris. (Vu en jeu le 2026-11-09 : un essai l'a lue à 1 à chacune de ses 120 images, et le joueur a vu
	-- la carte glisser ; un autre, à 0 partout, et elle n'a pas bougé. Ce qui la remettait n'est pas connu.)
	-- Chaque fois qu'un autre code la change, elle revient à 0, et c'est compté ; ce qu'il voulait lui est
	-- rendu à la fin.
	local function Hide(alpha)
		reader.alphaOurs = true
		pcall(Minimap.SetAlpha, Minimap, alpha)
		reader.alphaOurs = false
	end
	if Minimap and hooksecurefunc then
		hooksecurefunc(Minimap, "SetAlpha", function(_, alpha)
			local s = reader.s
			if s and not s.masked and not reader.alphaOurs then
				if not IsSecret(alpha) then s.wanted = alpha end
				if alpha ~= 0 then
					s.resets = s.resets + 1
					Hide(0)
				end
			end
		end)
	end

	-- Ce cadre est-il la minimap, ou dedans ?
	local function Inside(frame)
		for _ = 1, 20 do
			if frame == nil then return false end
			if frame == Minimap then return true end
			local ok, parent = pcall(frame.GetParent, frame)
			if not ok then return false end
			frame = parent
		end
		return false
	end

	-- Ce cadre suit-il la minimap pendant le balayage en cours, ancré à elle sans être dedans, lui ou l'un
	-- de ses parents ?
	local function Rides(frame)
		local s = reader.s
		if not s then return false end
		for _ = 1, 20 do
			if frame == nil then return false end
			if s.followers[frame] then return true end
			local ok, parent = pcall(frame.GetParent, frame)
			if not ok then return false end
			frame = parent
		end
		return false
	end

	local function Focus()
		if GetMouseFoci then
			local foci = GetMouseFoci()
			local focus = type(foci) == "table" and foci[1] or nil
			if IsSecret(focus) then return nil end
			return focus
		end
		return GetMouseFocus and GetMouseFocus() or nil
	end

	-- Un cadre protégé ne se touche plus en combat
	local function Locked(frame)
		return InCombatLockdown() and frame.IsProtected ~= nil and frame:IsProtected() == true
	end

	-- Un cadre, et ce que sa souris prend, pour le lui rendre. Un balayage qui en tient un protégé
	-- s'arrête quand un combat commence, pendant qu'il peut encore le rendre (PLAYER_REGEN_DISABLED).
	local function Mute(s, frame)
		if s.muted[frame] or Locked(frame) then return end
		local saved = {}
		if frame.IsMouseClickEnabled and frame.IsMouseMotionEnabled then
			saved.click, saved.motion = frame:IsMouseClickEnabled(), frame:IsMouseMotionEnabled()
			if IsSecret(saved.click) or IsSecret(saved.motion) then return end
			if saved.click then pcall(frame.SetMouseClickEnabled, frame, false) end
			if saved.motion then pcall(frame.SetMouseMotionEnabled, frame, false) end
		end
		if frame.IsProtected and frame:IsProtected() then s.protected = true end
		s.muted[frame] = saved
		s.list[#s.list + 1] = frame
	end

	-- Ce que contient ce cadre et qui prend la souris (les boutons de la minimap, ceux des addons) : la
	-- minimap passe sous le pointeur, un clic irait à l'un d'eux, et son infobulle à la place de celle de
	-- la minimap
	local function Children(s, frame, depth)
		local ok, list = pcall(function() return { frame:GetChildren() } end)
		if not ok then return end
		for _, child in ipairs(list) do
			if not IsSecret(child) and child ~= holder and child ~= stand and not (child.IsForbidden and child:IsForbidden()) then
				Mute(s, child)
				if depth < DEPTH then Children(s, child, depth + 1) end
			end
		end
	end

	-- La souris est-elle sur autre chose que le monde, que la minimap posée sous elle ne couvrirait
	-- pas ? Un cadre d'une strate plus basse que la sienne ne compte pas : elle passe par-dessus.
	-- (OPie en pose un sur tout l'écran : le balayage automatique de NodeSight ne partait plus.) Un cadre
	-- qui suit la minimap et prend encore la souris (un bouton posé dans un autre addon en plein
	-- balayage) ne la prend plus.
	local function Covered()
		local focus = Focus()
		if focus == nil or focus == WorldFrame or Inside(focus) then return false end
		if stand and focus == stand then return false end
		if Rides(focus) then
			Mute(reader.s, focus)
			return false
		end
		local ok, strata = pcall(focus.GetFrameStrata, focus)
		local mine = STRATA[Minimap:GetFrameStrata()] or 2
		if ok and STRATA[strata] then
			if STRATA[strata] < mine then return false end
			if STRATA[strata] == mine then
				local fine, level = pcall(focus.GetFrameLevel, focus)
				if fine and type(level) == "number" and not IsSecret(level) and level < Minimap:GetFrameLevel() then return false end
			end
		end
		return true
	end

	-- La souris tourne-t-elle la caméra ? Le jeu cache alors le pointeur et le tient en place.
	local function Camera()
		if IsMouselooking and IsMouselooking() then return true end
		return IsMouseButtonDown ~= nil and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) == true
	end

	-- En combat, la minimap ne se lit que si le joueur le veut (nodeCombat), et si elle n'est pas un
	-- cadre protégé : AdjustPointsOffset est alors interdit à un addon (NodeSight 1.8 fait de même)
	function reader.Fight()
		if not InCombatLockdown() then return false end
		return not ns.GetOption("nodeCombat") or (Minimap.IsProtected and Minimap:IsProtected()) == true
	end

	-- Le joueur vole avec un maître de vol : rien ne se lit (demandé le 2026-11-09). Ni pendant qu'une
	-- fenêtre de PNJ est ouverte (marchand, quêtes, banque, courrier, hôtel des ventes, échange), comme
	-- NodeSight 1.9.0, pour que les addons qui vendent ou rendent les quêtes d'eux-mêmes n'aient pas un
	-- balayage dans les jambes. Les noms sont ceux de PlayerInteractionManagerConstantsDocumentation
	-- (build 70245).
	local NPC_WINDOWS = { "TradePartner", "Gossip", "QuestGiver", "Merchant", "Banker", "MailInfo", "Auctioneer" }
	local function Busy()
		if UnitOnTaxi and SafeCall(UnitOnTaxi, "player") == true then return "taxi" end
		local types, manager = Enum and Enum.PlayerInteractionType, C_PlayerInteractionManager
		if types and manager and manager.IsInteractingWithNpcOfType then
			for _, name in ipairs(NPC_WINDOWS) do
				if types[name] and SafeCall(manager.IsInteractingWithNpcOfType, types[name]) == true then return "npc" end
			end
		end
	end

	-- Pourquoi un balayage ne peut pas commencer maintenant : nil s'il le peut
	function reader.Ready()
		if reader.Fight() then return "combat" end
		local occupied = Busy()
		if occupied then return occupied end
		if not Minimap:IsVisible() then return "hidden" end
		if Minimap:IsMouseOver() or Inside(Focus()) then return "pointer" end
		if Camera() then return "camera" end
		if Covered() then return "window" end
	end

	-- Où est maintenant sur la minimap le point du monde qui était en (x, y) au début du balayage :
	-- le joueur a pu marcher depuis, et la minimap qui tourne avec lui, tourner
	function reader.Now(x, y)
		local view = scan and scan.view
		if not (view and view.map and view.radius) or (view.turning and not view.facing) then return x, y end
		local map, px, py = MapPosition()
		if map ~= view.map then return x, y end
		local half = width / 2
		local dx, dy = x - half, y - half
		local yards = math.sqrt(dx * dx + dy * dy) / half * view.radius
		local way = math.atan2(dx, dy)
		if view.turning then way = way - view.facing end
		local east = yards * math.sin(way) + (view.x - px) * view.wide
		local north = yards * math.cos(way) + (py - view.y) * view.tall
		local units = math.sqrt(east * east + north * north) / view.radius * half
		way = math.atan2(east, north)
		if view.turning then way = way + (select(3, View()) or view.facing) end
		return half + units * math.sin(way), half + units * math.cos(way)
	end

	-- Les nœuds connus là où ils étaient au début du balayage, comme la grille les a vus : le suivi les
	-- remet où ils sont à l'image d'après
	function reader.Freeze()
		local view = scan and scan.view
		if not (view and view.map and view.radius) or (view.turning and not view.facing) then return end
		seen.map, seen.x, seen.y, seen.radius, seen.turning, seen.facing = view.map, view.x, view.y, view.radius, view.turning, view.facing
		seen.wide, seen.tall, seen.half = view.wide, view.tall, width / 2
		for _, marker in ipairs(markers) do Track(marker, 1) end
		seen.map = nil
	end

	-- Ce que la minimap porte, cadres et textures, et ce qui la suit, se cache par son opacité le temps
	-- d'un balayage. Ce qui était déjà caché (des boutons qui ne paraissent qu'au survol de la minimap,
	-- comme elle l'est pendant un balayage) est en plus rapetissé : s'il paraît, c'est hors de vue. Il le
	-- reste un moment après (Settle), sans quoi il se montrerait à la place de la minimap le temps que
	-- l'addon qui le porte voie la souris partir (LibDBIcon les efface une seconde après).
	local function Unseen(frame, alpha)
		if alpha == 0 then return true end
		local ok, shown = pcall(frame.IsShown, frame)
		return ok and not IsSecret(shown) and shown == false
	end
	local function Shrink(part)
		local frame = part.frame
		if part.scale or not frame.SetScale or (frame.IsProtected and frame:IsProtected()) then return end
		local ok, value = pcall(frame.GetScale, frame)
		if ok and type(value) == "number" and not IsSecret(value) and value > 0 then
			part.scale = value
			pcall(frame.SetScale, frame, reader.SHRINK)
		end
	end
	reader.settling = {}      -- cadre rapetissé par un balayage fini -> son échelle
	local function Cover(s, frame)
		if IsSecret(frame) or s.covered[frame] or frame == holder or frame == stand or Locked(frame) then return end
		if frame.IsObjectType and frame:IsObjectType("MaskTexture") then return end
		local ok, alpha = pcall(frame.GetAlpha, frame)
		if not ok or IsSecret(alpha) or type(alpha) ~= "number" then return end
		local part = { frame = frame, alpha = alpha, hidden = Unseen(frame, alpha) }
		-- (encore rapetissé après le balayage d'avant : il l'est déjà)
		if reader.settling[frame] then
			part.scale, part.hidden, reader.settling[frame] = reader.settling[frame], true, nil
		end
		s.covered[frame] = part
		s.parts[#s.parts + 1] = part
		if frame.IsProtected and frame:IsProtected() then s.protected = true end
		pcall(frame.SetAlpha, frame, 0)
		if part.hidden then Shrink(part) end
	end

	-- Les cadres ancrés à la minimap, ou à ce qu'elle contient, sans être dedans : ils la suivraient
	-- sous la souris, à la vue de tous. Ancrés de proche en proche aussi (une bordure d'interface ancrée
	-- à un cadre lui-même ancré à la minimap), et ce qu'ils contiennent ne prend plus la souris. Le nombre
	-- de points d'ancrage d'un cadre peut être une valeur secrète, qui ne se compte pas : ce cadre est
	-- laissé (signalé le 2026-11-09 par sept joueurs, avec EllesmereUI : « NodeScan.lua:784: 'for' limit
	-- must be a number », à chaque balayage).
	local function Anchored(s)
		if not EnumerateFrames then return end
		local answered = {}
		local function Follows(frame, depth)
			if answered[frame] ~= nil then return answered[frame] end
			answered[frame] = false
			if depth > 10 or not frame.GetNumPoints then return false end
			local ok, count = pcall(frame.GetNumPoints, frame)
			if not ok or IsSecret(count) or type(count) ~= "number" then return false end
			for index = 1, count do
				local fine, _, relative = pcall(frame.GetPoint, frame, index)
				if fine and not IsSecret(relative) and type(relative) == "table" and relative ~= frame
					and (Inside(relative) or Follows(relative, depth + 1)) then
					answered[frame] = true
					return true
				end
			end
			return false
		end
		local frame, count = EnumerateFrames(), 0
		while frame and count < 20000 do
			count = count + 1
			if not IsSecret(frame) then
				local forbidden = frame.IsForbidden and frame:IsForbidden()
				if not forbidden and frame ~= stand and frame ~= holder and not Inside(frame) and Follows(frame, 1) and not Locked(frame) then
					s.followers[frame] = true
					Cover(s, frame)
					Mute(s, frame)
					Children(s, frame, 1)
				end
			end
			frame = EnumerateFrames(frame)
		end
	end

	-- À chaque image du balayage : ce qui s'est remontré (un addon qui montre ses boutons quand la souris
	-- est sur la minimap) se cache de nouveau, rapetissé pour le reste du balayage ; ce qu'un addon pose
	-- sur la minimap pendant ce temps (une épingle) se cache et ne prend pas la souris. Et l'opacité de la
	-- minimap elle-même, quand c'est par elle qu'elle se cache.
	function reader.Hold()
		local s = reader.s
		if not s then return end
		if not s.masked and Minimap:GetAlpha() ~= 0 then
			s.resets = s.resets + 1
			Hide(0)
		end
		for _, part in ipairs(s.parts) do
			local frame = part.frame
			local ok, alpha = pcall(frame.GetAlpha, frame)
			if ok and not IsSecret(alpha) and type(alpha) == "number" and alpha > 0 and not Locked(frame) then
				pcall(frame.SetAlpha, frame, 0)
				Shrink(part)
				s.shown = s.shown + 1
			end
		end
		if s.masked and Minimap.GetNumChildren then
			local count = Minimap:GetNumChildren()
			if not IsSecret(count) and count ~= s.children then
				s.children = count
				for _, child in ipairs({ Minimap:GetChildren() }) do
					if not IsSecret(child) and not s.covered[child] and child ~= holder then
						Cover(s, child)
						Mute(s, child)
						Children(s, child, 2)
					end
				end
			end
		end
	end

	-- Après un balayage, les cadres rapetissés reprennent leur taille une fois cachés de nouveau, au bout
	-- de SETTLE_MIN au moins et de SETTLE_MAX au plus, ou dès que la vraie souris est sur la minimap.
	-- `now` : tout de suite (Lueur s'éteint, le joueur s'en va).
	function reader.Settle(now)
		if not next(reader.settling) then return end
		local waited = GetTime() - (reader.settledAt or 0)
		if not now and waited < reader.SETTLE_MIN then return end
		local over = Minimap:IsMouseOver()
		for frame, value in pairs(reader.settling) do
			local ok, alpha = pcall(frame.GetAlpha, frame)
			if now or over or waited > reader.SETTLE_MAX or not ok or IsSecret(alpha) or Unseen(frame, alpha) then
				if not Locked(frame) then
					pcall(frame.SetScale, frame, value)
					reader.settling[frame] = nil
				end
			end
		end
	end

	-- Pose la minimap pour que (x, y) soit sous la souris à l'image suivante, où le jeu regarde : là où
	-- elle sera, si elle bouge comme à la dernière image
	local function Place(s, x, y)
		local cx, cy = GetCursorPosition()
		local px, py = 2 * cx - (s.cx or cx), 2 * cy - (s.cy or cy)
		s.cx, s.cy = cx, cy
		local nx, ny = reader.Now(x, y)
		local ox, oy = px / scale - nx - left, py / scale - ny - bottom
		Minimap:AdjustPointsOffset(ox - s.ox, oy - s.oy)
		reader.Hold()
		s.ox, s.oy, s.px, s.py = ox, oy, px, py
		s.frames = s.frames + 1
	end

	-- Ce que le jeu dit du point (x, y), une image plus tard. Seul le balayage en cours le demande :
	-- ailleurs (la lueur au loin), rien ne répond. Une attente au milieu (reader.Wait) a remis la minimap
	-- chez elle : le point se repose, sans que cela compte pour un essai.
	function reader.Look(x, y)
		local s = reader.s
		if not s or not coroutine.running() or coroutine.running() ~= s.co then return nil end
		local try = 0
		while try < reader.TRIES do
			try = try + 1
			Place(s, x, y)
			coroutine.yield()
			if s.parked then
				s.parked, try = nil, try - 1
			else
				local cx, cy = GetCursorPosition()
				if math.abs(cx - s.px) <= reader.MISS * scale and math.abs(cy - s.py) <= reader.MISS * scale then break end
				if try < reader.TRIES then s.again = s.again + 1 end
			end
		end
		return SafeCall(C_TooltipInfo.GetMinimapMouseover)
	end

	-- La souris passe sur une fenêtre, ou un bouton se tient enfoncé pour tourner la caméra, en plein
	-- balayage : la minimap retourne chez elle et y reste cachée le temps de voir si cela passe
	-- (WINDOW_WAIT, CAMERA_WAIT), au lieu de revenir et de repartir aussitôt, ce qui la ferait clignoter
	-- (NodeSight 1.9.0 fait de même). Rien ne se lit pendant ce temps. Renvoie "wait", ou pourquoi le
	-- balayage s'arrête.
	function reader.Wait(why)
		local s = reader.s
		local now = GetTime()
		s.waitFrom = s.waitFrom or now
		if now - s.waitFrom > (why == "camera" and reader.CAMERA_WAIT or reader.WINDOW_WAIT) then return why end
		if not s.parked then
			pcall(Minimap.AdjustPointsOffset, Minimap, -s.ox, -s.oy)
			s.ox, s.oy, s.cx, s.cy, s.parked, s.parkedFor = 0, 0, nil, nil, true, 0
		end
		s.parkedFor = s.parkedFor + 1
		reader.Hold()
		-- (chez elle et invisible : la souris qui y passe ne doit pas y trouver une minimap qu'elle ne voit pas.
		-- Le jeu le dit à l'image qui suit celle où elle y est revenue)
		if s.parkedFor > 2 and Minimap:IsMouseOver() then return "pointer" end
		return "wait"
	end

	-- La lecture reprend après une attente
	function reader.Resume()
		local s = reader.s
		if s then s.waitFrom = nil end
	end

	-- Le fond, le cadre doré et les coordonnées, à la place de la minimap. Le fond est rond, ou plein
	-- pour une minimap qui ne l'est pas.
	local function Stand()
		if not stand then
			stand = CreateFrame("Frame", nil, UIParent)
			stand.ground = stand:CreateTexture(nil, "BACKGROUND")
			stand.ground:SetAllPoints(stand)
			stand.ground:SetColorTexture(0, 0, 0, 0.35)
			Clip({ frame = stand }, stand.ground)
			stand.plain = stand:CreateTexture(nil, "BACKGROUND")
			stand.plain:SetPoint("CENTER", stand, "CENTER", 0, 0)
			stand.plain:SetColorTexture(0, 0, 0, 0.35)
			stand.ring = stand:CreateTexture(nil, "OVERLAY")
			stand.coords = stand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			-- (l'image vide se charge-t-elle ? Sinon la minimap se cache par son opacité)
			local probe = stand:CreateTexture(nil, "BACKGROUND")
			local ok, loaded = pcall(probe.SetTexture, probe, reader.EMPTY)
			reader.canMask = ok and loaded ~= false
			probe:Hide()
		end
		return stand
	end

	-- Ce qui tient la place de la minimap suit ce qu'elle montrait : ses coordonnées
	function reader.Copy()
		local coords = MinimapCluster and MinimapCluster.PlayerCoords
		local text = coords and coords.CoordText and SafeCall(coords.CoordText.GetText, coords.CoordText)
		if stand and type(text) == "string" and text ~= stand.text then
			stand.text = text
			stand.coords:SetText(text)
		end
	end

	-- La minimap sous la souris, invisible, et ce qui tient sa place
	function reader.Begin(co)
		local s = { co = co, ox = 0, oy = 0, frames = 0, again = 0, resets = 0, shown = 0, muted = {}, list = {},
			covered = {}, parts = {}, followers = {}, alpha = Minimap:GetAlpha() }
		reader.s, reader.on = s, true
		if Minimap.IsMouseWheelEnabled then
			s.wheel = Minimap:IsMouseWheelEnabled()
			Minimap:EnableMouseWheel(false)
		end
		if Minimap.IsMouseClickEnabled then
			s.clicks = Minimap:IsMouseClickEnabled()
			Minimap:SetMouseClickEnabled(false)
		end
		-- les icônes de Lueur restent où était la minimap, à sa taille
		local view = Stand()
		local factor = scale / UIParent:GetEffectiveScale()
		for _, frame in ipairs({ view, holder }) do
			frame:SetParent(UIParent)
			frame:SetScale(factor)
			frame:SetFrameStrata(Minimap:GetFrameStrata())
			frame:ClearAllPoints()
			frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
			frame:SetSize(width, width)
		end
		view:SetFrameLevel(math.max(0, holder:GetFrameLevel() - 1))
		if Minimap.GetChildren then Children(s, Minimap, 1) end
		s.masked = Minimap.SetMaskTexture ~= nil and reader.canMask == true
		if s.masked then
			SetMask(reader.EMPTY, true)
			if Minimap.GetChildren then
				for _, child in ipairs({ Minimap:GetChildren() }) do Cover(s, child) end
			end
			if Minimap.GetRegions then
				for _, region in ipairs({ Minimap:GetRegions() }) do Cover(s, region) end
			end
			s.children = Minimap.GetNumChildren and Minimap:GetNumChildren()
		else
			Hide(0)
		end
		Anchored(s)
		s.scaled = Minimap.SetIconScale ~= nil
		if s.scaled then
			s.iconScale = IconScale()
			if ns.db then ns.db.iconScaleBack = s.iconScale end
			SetIconScale(reader.TINY)
		end
		local quarters = reader.Quarters()
		view.ground:SetShown(quarters.round)
		view.plain:SetShown(not quarters.round)
		view.plain:SetSize(width, width * quarters.height)
		local compass = MinimapCompassTexture
		local atlas = compass and compass:IsVisible() and SafeCall(compass.GetAtlas, compass)
		view.ring:SetShown(type(atlas) == "string")
		if type(atlas) == "string" then
			view.ring:SetAtlas(atlas)
			view.ring:SetSize(compass:GetWidth(), compass:GetHeight())
			view.ring:SetPoint("CENTER", view, "CENTER")
		end
		local coords = MinimapCluster and MinimapCluster.PlayerCoords
		view.coords:SetShown(coords ~= nil and coords.IsVisible ~= nil and coords:IsVisible())
		view.coords:SetPoint("TOP", view, "BOTTOM", 0, -12)
		view.text = nil
		view:Show()
		reader.Copy()
		Pointer(true)
	end

	-- Ce que le combat empêche de rendre à un cadre protégé l'est à sa fin
	reader.later = {}
	function reader.Later()
		if InCombatLockdown() then return end
		for frame, saved in pairs(reader.later) do
			if saved.click then pcall(frame.SetMouseClickEnabled, frame, true) end
			if saved.motion then pcall(frame.SetMouseMotionEnabled, frame, true) end
			reader.later[frame] = nil
		end
	end

	-- La minimap rendue telle qu'elle était
	function reader.End()
		local s = reader.s
		if not s then return end
		reader.s, reader.on = nil, false
		reader.resets, reader.shown, reader.hidden, reader.masked = s.resets, s.shown, #s.parts, s.masked
		pcall(Minimap.AdjustPointsOffset, Minimap, -s.ox, -s.oy)
		if s.masked then SetMask(MaskBack()) else Hide(s.wanted or s.alpha) end
		if s.wheel ~= nil then pcall(Minimap.EnableMouseWheel, Minimap, s.wheel) end
		if s.clicks ~= nil then pcall(Minimap.SetMouseClickEnabled, Minimap, s.clicks) end
		if s.scaled then
			SetIconScale(s.iconScale)
			if ns.db then ns.db.iconScaleBack = nil end
		end
		for _, frame in ipairs(s.list) do
			local saved = s.muted[frame]
			if Locked(frame) then
				reader.later[frame] = saved
			else
				if saved.click then pcall(frame.SetMouseClickEnabled, frame, true) end
				if saved.motion then pcall(frame.SetMouseMotionEnabled, frame, true) end
			end
		end
		for _, part in ipairs(s.parts) do
			local frame = part.frame
			if not Locked(frame) then
				pcall(frame.SetAlpha, frame, part.alpha)
				if part.scale then
					if part.hidden then reader.settling[frame] = part.scale else pcall(frame.SetScale, frame, part.scale) end
				end
			end
		end
		reader.settledAt = GetTime()
		holder:SetParent(Minimap)
		holder:SetScale(1)
		holder:ClearAllPoints()
		holder:SetAllPoints(Minimap)
		if stand then stand:Hide() end
		reader.quiet = GetTime() + 0.25
		covering = false
		Draw()
	end

	-- La taille des points du jeu, si un balayage n'a pas pu la rendre (le jeu arrêté pendant ce temps)
	function reader.Restore()
		local back = ns.db and ns.db.iconScaleBack
		if type(back) == "number" and back > 0 then SetIconScale(back) end
		if ns.db then ns.db.iconScaleBack = nil end
	end

	-- Pourquoi le balayage en cours doit s'arrêter : nil s'il continue
	function reader.Check()
		if reader.Fight() then return "combat" end
		local occupied = Busy()
		if occupied then return occupied end
		if not Minimap:IsVisible() then return "hidden" end
		if Camera() then return "camera" end
		if Covered() then return "window" end
		local view = scan.view
		local radius, turning, facing = View()
		if radius ~= view.radius then return "zoom" end
		-- (la minimap qui tourne avec le joueur : chaque point se lit là où il est passé, reader.Now)
		if turning ~= view.turning or (turning and not facing) then return "turn" end
		if view.map and MapPosition() ~= view.map then return "map" end
	end

	-- Pendant un balayage, et un instant après, aucune infobulle de la minimap ni de ce qu'elle
	-- contient ou de ce qui la suit : elle passe sous la souris sans que le joueur l'y ait mise. Celle de
	-- la minimap a UIParent pour propriétaire (Minimap_OnUpdate, Blizzard_Minimap\Mainline\Minimap.lua,
	-- build 70245 : SetOwner(UIParent, "ANCHOR_CURSOR") puis SetMinimapMouseover à chaque image) : elle se
	-- cache dès qu'elle se remplit, et toute infobulle de UIParent tant que la minimap est sous la
	-- souris. (Vu en jeu le 2026-11-09 : « on voit malgré tout du texte s'afficher sous le pointeur ».)
	local function Quieting() return reader.on or GetTime() < (reader.quiet or 0) end
	local function Quiet(tip)
		if not Quieting() then return end
		local owner = tip.GetOwner and tip:GetOwner()
		if owner ~= nil and (Inside(owner) or Rides(owner) or (owner == UIParent and Minimap:IsMouseOver())) then tip:Hide() end
	end
	if GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript("OnShow", Quiet) end
	if GameTooltip and GameTooltip.SetMinimapMouseover and hooksecurefunc then
		hooksecurefunc(GameTooltip, "SetMinimapMouseover", function(tip)
			if Quieting() then tip:Hide() end
		end)
	end
end)()

---------------------------------------------------------------------------
-- Ce que dit l'infobulle de la minimap
---------------------------------------------------------------------------

-- Le jeu écrit en gris le nom d'un nœud qui est dans une grotte
local function Gray(r, g, b)
	if IsSecret(r) or IsSecret(g) or IsSecret(b) or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
	return math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 and r < 0.9
end

-- Les noms d'une ligne d'infobulle : elle en porte un par rangée, chacun avec ses images
-- (|T…|t, |A…|a) et parfois sa couleur (|cAARRGGBB, |cnNOM:). `gray` vaut nil pour un nom sans
-- couleur à lui : c'est alors celle de la ligne qui compte. `arrow` : le nom vient après la flèche
-- d'un nœud plus haut ou plus bas que le joueur (Minimap-PositionArrows), que le jeu montre au lieu
-- d'un point. Les mêmes lignes reviennent sans cesse : ce qui en a été tiré est gardé.
local parsed, parsedCount = {}, 0

local function Names(text)
	local list = parsed[text]
	if list then return list end
	list = {}
	for row in text:gmatch("[^\n]+") do
		local gray
		local r, g, b = row:match("|c%x%x(%x%x)(%x%x)(%x%x)")
		local named = row:match("|cn([%w_]+):")
		if r then
			gray = Gray(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
		elseif named then
			gray = named:find("GRAY", 1, true) ~= nil or named:find("DISABLED", 1, true) ~= nil
		end
		local name = row:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
		name = name:match("^%s*(.-)%s*$")
		if name ~= "" then list[#list + 1] = { name = name, gray = gray, arrow = row:find("PositionArrows", 1, true) ~= nil } end
	end
	if parsedCount >= 300 then parsed, parsedCount = {}, 0 end
	parsed[text], parsedCount = list, parsedCount + 1
	return list
end

-- Le jeu a-t-il déjà écrit un même nom deux fois en un point, comme il le ferait de deux points du
-- jeu de ce nom qui y répondent ensemble ? Retenu d'une session à l'autre (db.nodeTwice) : rien ne
-- dit d'avance qu'il le fait, et Fit ne se fie qu'alors à un nom écrit une seule fois, sauf
-- après une flèche.
local function Doubled()
	return ns.db ~= nil and ns.db.nodeTwice == true
end

-- Essaie un point de la minimap (x, y en unités depuis son coin bas gauche, là où elle était au
-- début du balayage) et note sous `point`, pour chaque nom que le jeu y donne, 1, ou 2 s'il l'écrit
-- en gris. Un regard de près (`job`) note en plus les noms que le jeu y écrit plus d'une fois
-- (job.many), et ceux qu'il écrit après une flèche (job.arrows). Le balayage attend la réponse à
-- l'image suivante (reader.Look) ; hors de lui, rien ne répond.
local written, writtenCount = {}, 0

local function Probe(x, y, hits, point, job)
	probes = probes + 1
	local data = reader.Look(x, y)
	local lines = type(data) == "table" and data.lines
	if IsSecret(lines) or type(lines) ~= "table" then return end
	writtenCount = 0
	for _, line in ipairs(lines) do
		local text = line.leftText
		if not IsSecret(text) and type(text) == "string" then
			local color = line.leftColor
			local lineGray = not IsSecret(color) and type(color) == "table" and Gray(color.r, color.g, color.b)
			for _, entry in ipairs(Names(text)) do
				local set = hits[entry.name]
				if not set then
					set = {}
					hits[entry.name] = set
				end
				local gray = entry.gray
				if gray == nil then gray = lineGray end
				set[point] = gray and 2 or 1
				local twice = false
				for index = 1, writtenCount do
					if written[index] == entry.name then twice = true end
				end
				writtenCount = writtenCount + 1
				written[writtenCount] = entry.name
				if twice and ns.db and not ns.db.nodeTwice then ns.db.nodeTwice = true end
				if job then
					if twice then
						job.many[entry.name] = job.many[entry.name] or {}
						job.many[entry.name][point] = true
					end
					if entry.arrow then job.arrows[entry.name] = true end
				end
			end
		end
	end
end

local scratch = {}

-- Le jeu nomme-t-il ce point du jeu en (x, y) ?
local function Under(name, x, y)
	for key in pairs(scratch) do scratch[key] = nil end
	Probe(x, y, scratch, 1)
	return scratch[name] ~= nil
end

---------------------------------------------------------------------------
-- Des points de grille aux nœuds
---------------------------------------------------------------------------

-- Un point de grille a pour numéro colonne + 1024 × rangée ; voici ses huit voisins, et les quatre
-- qui le touchent
local ROW = 1024
local AROUND = { -ROW - 1, -ROW, -ROW + 1, -1, 1, ROW - 1, ROW, ROW + 1 }
local BESIDE = { { -1, -1, 0 }, { 1, 1, 0 }, { -ROW, 0, -1 }, { ROW, 0, 1 } }

-- Les groupes de points voisins d'un ensemble : une liste de listes de numéros
local function Groups(set)
	local groups, taken = {}, {}
	for first in pairs(set) do
		if not taken[first] then
			taken[first] = true
			local keys, stack = {}, { first }
			while #stack > 0 do
				local key = table.remove(stack)
				keys[#keys + 1] = key
				for _, step in ipairs(AROUND) do
					local other = key + step
					if set[other] and not taken[other] then
						taken[other] = true
						stack[#stack + 1] = other
					end
				end
			end
			groups[#groups + 1] = keys
		end
	end
	return groups
end

-- Le rectangle qui tient un groupe et son milieu, en unités : gauche, bas, droite, haut, x, y
local function Box(keys)
	local x0, y0, x1, y1, sx, sy = math.huge, math.huge, -math.huge, -math.huge, 0, 0
	for _, key in ipairs(keys) do
		local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
		x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
		sx, sy = sx + x, sy + y
	end
	return x0, y0, x1, y1, sx / #keys, sy / #keys
end

-- Le jeu écrit-il ce nom en gris au point de l'ensemble le plus proche de (x, y) ? nil si ce
-- point n'en fait pas partie
local function GrayAt(set, x, y, step)
	local value = set[Round(x / step) + ROW * Round(y / step)]
	if value then return value == 2 end
end

-- Ce que vaut la place qu'un balayage donne à un nœud. Du pire au meilleur : le milieu d'un groupe
-- que rien n'a séparé ; un disque que le bord de la minimap tronque, dont la place est tirée vers
-- le centre ; un nœud d'un groupe, lu de son contour ; un nœud seul dont les bords ont été trouvés.
local ROUGH, RIM_PLACE, FITTED, SURE = 0, 1, 2, 3

local function Worth(place)
	if place.rim then return RIM_PLACE end
	if place.fitted then return FITTED end
	return place.exact and SURE or ROUGH
end

-- Rayon du disque où répond ce nœud : le sien, s'il a été lu, sinon le rayon courant de son métier
local function Radius(marker)
	return marker.reach or reaches[marker.node.kind].value
end

-- Un nœud seul vient d'être mesuré : le rayon courant de son métier s'en approche, et le premier
-- remplace l'estimation de départ
local function Learn(kind, radius)
	local known = reaches[kind]
	radius = math.max(MIN_REACH, math.min(MAX_REACH, radius))
	-- (le plus petit des derniers points seuls mesurés fait le pas de la grille : un plus petit encore
	-- passerait entre ses points)
	known.recent = known.recent or {}
	table.insert(known.recent, radius)
	if #known.recent > 4 then table.remove(known.recent, 1) end
	known.least = math.min(unpack(known.recent))
	if known.measured and radius > reader.LEARN * known.value then return end
	if known.measured then
		known.value = known.value + (radius - known.value) / 4
	else
		known.value, known.measured = radius, true
	end
end

-- Les nœuds déjà bien placés (un par un, ou lus du contour de leur groupe) dont le disque touche ce
-- groupe, et s'ils l'expliquent en entier. `map` : la carte où est le joueur.
local function Placed(name, keys, map)
	local mine, used, whole = {}, {}, true
	for _, key in ipairs(keys) do
		local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
		local covered = false
		for _, marker in ipairs(markers) do
			if marker.name == name and marker.map == map and marker.worth >= FITTED
				and (marker.x - x) ^ 2 + (marker.y - y) ^ 2 <= (Radius(marker) + STEP / 2 + 1) ^ 2 then
				covered = true
				if not used[marker] then
					used[marker] = true
					mine[#mine + 1] = marker
				end
			end
		end
		whole = whole and covered
	end
	return mine, whole
end

-- Un groupe touche-t-il le bord de la minimap, où le disque d'un nœud est tronqué ?
local function AtRim(keys)
	local half = width / 2
	for _, key in ipairs(keys) do
		if reader.Depth(key % ROW * STEP - half, math.floor(key / ROW) * STEP - half, half) <= reader.RIM then return true end
	end
	return false
end

-- Le nœud isolé déjà placé avec précision à cet endroit, s'il y en a un : il garde sa place.
-- `wide` : la largeur du groupe, qui ne dépasse pas le disque de ce nœud s'il y est seul. Et chaque
-- point du groupe (`keys`) doit tenir dans sa zone, ronde ou carrée : la grille est lâche, son milieu
-- peut tomber à une dizaine d'unités du nœud, mais un point entendu hors de sa zone dit qu'il est ailleurs.
local SQUARE_CORNER = 1.42  -- la zone d'un point carré va jusqu'à ses coins : sa demi-largeur fois racine de deux
local function Pinned(name, x, y, wide, keys)
	local near = (PIN_REACH * STEP) ^ 2
	for _, marker in ipairs(markers) do
		if marker.exact and marker.name == name and not marker.far and (marker.x - x) ^ 2 + (marker.y - y) ^ 2 <= near
			and wide <= 2 * Radius(marker) + 2 then
			local reach, fits = (SQUARE_CORNER * Radius(marker) + 1.5) ^ 2, true
			for _, key in ipairs(keys) do
				if (key % ROW * STEP - marker.x) ^ 2 + (math.floor(key / ROW) * STEP - marker.y) ^ 2 > reach then fits = false end
			end
			if fits then return marker end
		end
	end
end

-- Les nœuds qu'un balayage précédent a déjà séparés dans ce groupe, s'ils l'expliquent encore en
-- entier : les séparer coûte cher, et ils ne bougent pas. Sauf si un seul disque, au milieu d'eux,
-- l'explique aussi bien : c'est peut-être un nœud seul qu'un regard de près a lu comme plusieurs, et
-- les garder le montrerait en double pendant REFIT balayages. Le groupe est alors relu.
-- (Vu en jeu le 2026-10-14 : deux Feuillargent « dans un groupe », à dix unités l'une de l'autre,
-- pour une seule sur la minimap, gardées par le dernier balayage sans regard de près.)
local function Known(name, keys)
	if refit then return nil end
	local inside, mine = {}, {}
	local cx, cy, reach = 0, 0, 0
	for _, key in ipairs(keys) do inside[key] = true end
	for _, marker in ipairs(markers) do
		if marker.fitted and marker.name == name and not marker.far and marker.age < REFIT
			and inside[Round(marker.x / STEP) + ROW * Round(marker.y / STEP)] then
			mine[#mine + 1] = marker
			cx, cy, reach = cx + marker.x, cy + marker.y, math.max(reach, Radius(marker))
		end
	end
	if #mine < 2 then return nil end
	cx, cy = cx / #mine, cy / #mine
	local single = true
	for _, key in ipairs(keys) do
		local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
		local covered = false
		for _, marker in ipairs(mine) do
			if (marker.x - x) ^ 2 + (marker.y - y) ^ 2 <= (Radius(marker) + STEP / 2 + 1) ^ 2 then
				covered = true
				break
			end
		end
		if not covered then return nil end
		if (cx - x) ^ 2 + (cy - y) ^ 2 > (reach + STEP / 2 + 1) ^ 2 then single = false end
	end
	if single then return nil end
	return mine
end

-- Jusqu'où ce nom répond depuis (x, y) dans la direction (dx, dy), cherché jusqu'à `limit` unités.
-- nil s'il répond encore au bout ; le second résultat dit alors si c'est le bord de la minimap
-- qui a arrêté la recherche. Le bord se cherche pas à pas (reader.stride), jusqu'au premier point
-- qui ne répond pas, puis par dichotomie : il est celui de ce point du jeu, pas celui d'un voisin du
-- même nom un peu plus loin (un essai d'emblée au bout de la recherche tombait dans ce voisin).
local function Edge(name, x, y, dx, dy, limit)
	local half = width / 2
	local far, atRim = reader.Room(x - half, y - half, dx, dy, half, 1), true
	if far > limit then far, atRim = limit, false end
	if far <= 0 then return nil, true end
	local near, at = 0, math.min(reader.stride, far)
	while Under(name, x + dx * at, y + dy * at) do
		if at >= far then return nil, atRim end
		near, at = at, math.min(at + reader.stride, far)
	end
	for _ = 1, HALVINGS do
		if at - near <= reader.PRECISION then break end
		local middle = (near + at) / 2
		if Under(name, x + dx * middle, y + dy * middle) then near = middle else at = middle end
	end
	return (near + at) / 2
end

-- Cherche le centre exact d'un groupe qui peut être un seul point du jeu : ses bords par
-- dichotomie, en largeur par son milieu, puis en hauteur par le milieu de cette largeur. À la sortie :
-- place.exact s'il est trouvé (et place.reach, sa demi-largeur), place.rim si le bord de la minimap
-- cache un de ses bords, place.merged si ses bords ne se trouvent pas, et place.split, les nœuds
-- d'un groupe plus large qu'un point du jeu : deux ou trois de front, en ligne ou en carré. Un groupe
-- d'un point est un nœud quel que soit son rayon : rien n'assure que tous répondent d'aussi loin.
-- (Avant la lecture sous la vraie souris, la largeur se mesurait aussi en diagonale, pour dire si le
-- disque était rond : vingt-cinq essais de plus, une image chacun désormais. Et un groupe qui
-- n'était pas un disque seul se regardait de près, ce qui en demandait des centaines.)
local function Refine(place)
	local name, x, y = place.name, place.x, place.y
	local known = reaches[place.node.kind]
	-- un bord se cherche jusqu'un peu au-delà de ce que la grille a vu du groupe
	local box = place.box
	local limit = math.min(2 * MAX_REACH, math.max(box[3] - box[1], box[4] - box[2]) / 2 + 2 * STEP, reader.LIMIT * known.value)
	reader.stride = math.max(2, reader.STRIDE * known.value)
	-- Le jeu écrit-il le nom en (x, y), et deux fois ? Deux points du jeu s'y recouvrent alors.
	local function Twice()
		for key in pairs(scratch) do scratch[key] = nil end
		local here = { many = {}, arrows = {} }
		Probe(x, y, scratch, 1, here)
		return here.many[name] ~= nil, scratch[name] ~= nil
	end
	if not select(2, Twice()) then
		place.merged = true
		return
	end
	-- la demi-largeur du groupe le long d'une droite qui passe par (x, y), ou par (ox, oy), et de
	-- combien son milieu s'écarte de ce point ; nil si un bord manque
	local function Chord(dx, dy, ox, oy)
		ox, oy = ox or x, oy or y
		local back, backRim = Edge(name, ox, oy, -dx, -dy, limit)
		local ahead, aheadRim = Edge(name, ox, oy, dx, dy, limit)
		if back and ahead then return (ahead + back) / 2, (ahead - back) / 2 end
		-- le bord de la minimap cache l'un des deux : le troisième résultat dit où est celui qui se voit,
		-- le long de la droite depuis (ox, oy)
		if (back and aheadRim) or (ahead and backRim) then
			place.rim = true
			return nil, nil, back and -back or ahead
		end
		if backRim or aheadRim then place.rim = true else place.merged = true end
	end
	local wide, shift, edgeX = Chord(1, 0)
	if not (wide or edgeX) then return end
	if wide then x = x + shift end
	local tall, edgeY
	tall, shift, edgeY = Chord(0, 1)
	if not (tall or edgeY) then return end
	if tall then y = y + shift end
	if edgeX or edgeY then
		-- Le bord de la minimap tronque le point dans un sens : son milieu est à une demi-largeur du bord
		-- qui se voit, la demi-largeur de l'autre sens. Elle se remesure à la hauteur de ce milieu, qui
		-- en change (un disque est plus large en son milieu), trois fois au plus.
		if edgeX and edgeY then
			-- (tronqué dans les deux sens, près du bord en biais : le rayon de son métier fait la demi-largeur)
			local reach = known.value
			local sx, sy = edgeX < 0 and 1 or -1, edgeY < 0 and 1 or -1
			x, y = x + edgeX + sx * reach, y + edgeY + sy * reach
			-- (chaque bord qui se voit se retrouve sur la ligne de ce milieu)
			local back = Edge(name, x, y, -sx, 0, limit)
			if back then x = x - sx * back + sx * reach end
			back = Edge(name, x, y, 0, -sy, limit)
			if back then y = y - sy * back + sy * reach end
			place.x, place.y, place.exact, place.reach = x, y, true, reach
			return
		end
		local along = edgeY ~= nil
		local base = along and y + edgeY or x + edgeX
		local sign = (along and edgeY or edgeX) < 0 and 1 or -1
		-- (le bord qui se voit a été trouvé sur la ligne du milieu du groupe : il se retrouve sur celle du point)
		local again = along and Edge(name, x, y, 0, -sign, limit) or not along and Edge(name, x, y, -sign, 0, limit)
		if again then base = (along and y or x) - sign * again end
		local half = along and wide or tall
		for _ = 1, 3 do
			local middle = base + sign * half
			local again, moved
			if along then again, moved = Chord(1, 0, x, middle) else again, moved = Chord(0, 1, middle, y) end
			if not again or math.abs(again - half) < 0.3 then
				if again then half = again end
				if again and along then x = x + moved elseif again then y = y + moved end
				break
			end
			half = again
			if along then x = x + moved else y = y + moved end
		end
		if along then y = base + sign * half else x = base + sign * half end
		place.x, place.y, place.exact, place.reach = x, y, true, half
		return
	end
	local radius = known.measured and known.value or math.min(wide, tall)
	-- De front dans un sens : plus large que le rayon de son métier ne le permet à un point seul, ou
	-- nettement plus long que large (le rayon du métier n'est qu'une moyenne : les points du jeu ne
	-- répondent pas tous d'aussi loin)
	local across = wide > reader.SPLIT * radius or wide > reader.ASPECT * tall
	local down = tall > reader.SPLIT * radius or tall > reader.ASPECT * wide
	if across and down and wide > reader.ASPECT * tall then down = false end
	if across and down and tall > reader.ASPECT * wide then across = false end
	if not (across or down) and Doubled() and Twice() then
		-- Deux points serrés, de biais : le groupe n'est pas assez large pour le dire, mais le jeu y a
		-- écrit le nom deux fois. La plus longue des quatre cordes donne la ligne qui les joint.
		local slant = math.sqrt(0.5)
		local rising = Chord(slant, slant)
		if not rising then return end
		local falling = Chord(slant, -slant)
		if not falling then return end
		local best, bx, by = wide, 1, 0
		for _, way in ipairs({ { tall, 0, 1 }, { rising, slant, slant }, { falling, slant, -slant } }) do
			if way[1] > best then best, bx, by = way[1], way[2], way[3] end
		end
		local apart = best - radius
		if 2 * apart >= MIN_APART then
			place.x, place.y, place.reach = x, y, radius
			place.split = { { x - bx * apart, y - by * apart }, { x + bx * apart, y + by * apart } }
			return
		end
	end
	if not (across or down) then
		place.x, place.y, place.exact, place.reach = x, y, true, (wide + tall) / 2
		-- (seul un point aussi large que haut, et que le bord ne cache pas, dit de combien répondent ceux de son métier)
		if math.abs(wide - tall) <= ROUND and not place.rim then Learn(place.node.kind, place.reach) end
		return
	end
	-- Plusieurs nœuds de front : de demi-largeur `half`, leurs milieux vont d'un rayon en deçà d'un
	-- bord à un rayon en deçà de l'autre. Un écart d'environ un rayon entre deux voisins en fait
	-- 2 × half / rayon - 1 ; deux ou trois.
	local function Spots(half, long)
		if not long then return { 0 } end
		local count, ends, list = math.max(2, math.min(3, Round(2 * half / radius - 1))), half - radius, {}
		for index = 1, count do list[index] = -ends + 2 * ends * (index - 1) / (count - 1) end
		return list
	end
	local columns, rows = Spots(wide, across), Spots(tall, down)
	-- Ou un seul point, qui répond de plus loin que les autres ou pas en rond
	local function Single(round)
		place.x, place.y, place.exact, place.reach = x, y, true, (wide + tall) / 2
		if round and not place.rim then Learn(place.node.kind, place.reach) end
	end
	if across ~= down then
		-- De front dans un seul sens : la zone se mesure aussi en travers, par les deux nœuds des bouts.
		-- Plus étroite là qu'en son milieu, elle est un seul point, plus long que large ; sinon chaque
		-- bout tient un nœud, à sa propre demi-largeur du bord (deux voisins de rayons différents).
		local flags, spots, ends, sides = { place.merged, place.rim }, across and columns or rows, {}, {}
		for index, offset in ipairs({ spots[1], spots[#spots] }) do
			if across then
				ends[index], sides[index] = Chord(0, 1, x + offset, y)
			else
				ends[index], sides[index] = Chord(1, 0, x, y + offset)
			end
		end
		place.merged, place.rim = flags[1], flags[2]
		local middleHalf, long = across and tall or wide, across and wide or tall
		if ends[1] and ends[2] then
			-- Un troisième au milieu, si la zone y est aussi large qu'aux bouts (entre deux nœuds elle se
			-- resserre), si le jeu n'y écrit le nom qu'une fois (le milieu de deux nœuds serrés est dans l'un
			-- et l'autre) et deux fois à mi-chemin de chaque bout. Sans savoir que le jeu écrit un nom par
			-- point, deux : une icône de trop se remarque plus qu'une qui manque.
			spots = { -long + ends[1], long - ends[2] }
			local mid = (spots[1] + spots[2]) / 2
			local function TwiceAt(offset)
				local ox, oy = x, y
				if across then x = x + offset else y = y + offset end
				local twice = Twice()
				x, y = ox, oy
				return twice
			end
			local three = Doubled() and middleHalf >= math.max(ends[1], ends[2]) - 1 and not Twice()
				and TwiceAt((spots[1] + mid) / 2) and TwiceAt((mid + spots[2]) / 2)
			-- Sinon un seul point allongé : plus étroit aux bouts qu'en son milieu, ou, de même largeur aux
			-- deux bouts, sans que le jeu écrive le nom deux fois en son milieu comme il le ferait de deux
			-- nœuds de même taille qui s'y recouvrent
			if not three and not (Doubled() and Twice()) and ((ends[1] < middleHalf - 0.25 and ends[2] < middleHalf - 0.25)
				or (Doubled() and math.abs(ends[1] - ends[2]) <= 1.5)) then
				return Single(false)
			end
			local offsets = { sides[1], sides[2] } -- chacun à sa propre place en travers
			if three then
				table.insert(spots, 2, mid)
				table.insert(offsets, 2, 0)
			end
			local split = {}
			for index, along in ipairs(spots) do
				if across then split[index] = { x + along, y + offsets[index] } else split[index] = { x + offsets[index], y + along } end
			end
			place.x, place.y, place.split, place.reach = x, y, split, radius
			return
		end
	end
	-- Le milieu d'un carré de quatre est dans chacun : le jeu, qui écrit un nom par point (vu ici),
	-- l'y écrirait quatre fois. Écrit une seule fois, ou sans savoir que le jeu le ferait, c'est un seul
	-- gros point : un gros carré et quatre petits qui se recouvrent répondent au même endroit.
	if across and down and not (Doubled() and Twice()) then return Single(false) end
	if across and down then
		-- En carré, les cordes passées par le milieu passent entre deux rangées de nœuds, là où des
		-- disques sont moins larges : chaque sens se remesure par une rangée, puis par une colonne. Plus
		-- étroite par une rangée que par le milieu, la zone est un seul gros point.
		local half, shift = Chord(1, 0, x, y + rows[1])
		if not half then return end
		if half < wide - 1 then return Single(false) end
		local cx = x + shift
		columns = Spots(half, true)
		half, shift = Chord(0, 1, cx + columns[1], y)
		if not half then return end
		y, x = y + shift, cx
		rows = Spots(half, true)
	end
	local split = {}
	for _, dx in ipairs(columns) do
		for _, dy in ipairs(rows) do
			-- (en carré, un coin peut être vide : il ne compte que si le jeu y répond)
			if not (across and down) or Under(name, x + dx, y + dy) then split[#split + 1] = { x + dx, y + dy } end
		end
	end
	place.x, place.y, place.split, place.reach = x, y, split, radius
end

-- Le regard de près sur un groupe : les points, FINE unités d'écart, de son rectangle élargi
-- d'un pas de grille, qui touchent une case de la grille où le groupe a répondu ou sa voisine.
-- (Hors d'usage depuis la lecture sous la vraie souris, avec Fit et EndJob : une image par point.)
local function NewJob(place, x0, y0, x1, y1)
	local half = width / 2
	local nearby, points = {}, {}
	for _, key in ipairs(place.keys) do
		nearby[key] = true
		for _, step in ipairs(AROUND) do nearby[key + step] = true end
	end
	for column = math.max(0, math.ceil((x0 - STEP) / FINE)), math.floor((x1 + STEP) / FINE) do
		for line = math.max(0, math.ceil((y0 - STEP) / FINE)), math.floor((y1 + STEP) / FINE) do
			local x, y = column * FINE, line * FINE
			if nearby[Round(x / STEP) + ROW * Round(y / STEP)] and reader.Depth(x - half, y - half, half) >= 0 then
				points[#points + 1] = column + ROW * line
			end
		end
	end
	return { place = place, points = points, next = 1, hits = {}, many = {}, arrows = {} }
end

-- Le cercle qui passe au plus près de ces points (moindres carrés) : son centre et son rayon, ou
-- nil s'ils sont trop peu ou alignés
local function Circle(points)
	local count = #points
	if count < 3 then return nil end
	local mx, my = 0, 0
	for _, point in ipairs(points) do mx, my = mx + point[1], my + point[2] end
	mx, my = mx / count, my / count
	local uu, uv, vv, uuu, vvv, uvv, vuu = 0, 0, 0, 0, 0, 0, 0
	for _, point in ipairs(points) do
		local u, v = point[1] - mx, point[2] - my
		uu, uv, vv = uu + u * u, uv + u * v, vv + v * v
		uuu, vvv, uvv, vuu = uuu + u * u * u, vvv + v * v * v, uvv + u * v * v, vuu + v * u * u
	end
	local det = uu * vv - uv * uv
	if det < 1e-6 * (uu + vv) ^ 2 then return nil end
	local a, b = (uuu + uvv) / 2, (vvv + vuu) / 2
	local x, y = (a * vv - b * uv) / det, (b * uu - a * uv) / det
	return mx + x, my + y, math.sqrt(x * x + y * y + (uu + vv) / count)
end

-- Le regard de près sur un groupe déborde sur ses voisins : de ses points qui ont répondu, ceux
-- qui tiennent au groupe, de proche en proche depuis un point de la grille où il a répondu. Le reste
-- est le disque d'un nœud d'un autre groupe, qui a son propre regard.
local function Own(job, inside)
	local at, mine, stack = {}, {}, {}
	for _, point in ipairs(inside) do at[point[4]] = point end
	for _, key in ipairs(job.place.keys) do
		local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
		local column, line = Round(x / FINE), Round(y / FINE)
		for dx = -1, 1 do
			for dy = -1, 1 do
				local point = at[column + dx + ROW * (line + dy)]
				if point and not mine[point] and (point[1] - x) ^ 2 + (point[2] - y) ^ 2 <= FINE * FINE then
					mine[point] = true
					stack[#stack + 1] = point
				end
			end
		end
	end
	local list = {}
	while #stack > 0 do
		local point = table.remove(stack)
		list[#list + 1] = point
		for _, step in ipairs(AROUND) do
			local other = at[point[4] + step]
			if other and not mine[other] then
				mine[other] = true
				stack[#stack + 1] = other
			end
		end
	end
	return list
end

-- Les nœuds d'un groupe regardé de près : une liste de { x, y, rayon }.
--
-- Chaque point du jeu a son rayon, que rien ne dit d'avance : il se lit du groupe. Le centre d'un
-- nœud est un point du groupe ; son disque s'arrête au premier point qui n'a pas répondu, et le
-- contour du groupe se tient à cette distance autour de lui. Le point qui voit ainsi le plus de
-- contour donne un nœud, ce contour-là est retiré, et l'on recommence tant qu'il en reste assez. Un
-- nœud de plus n'est admis que s'il explique des points du groupe qu'aucun nœud trouvé n'explique,
-- et celui qui, à la fin, n'explique rien que les autres n'expliquent est retiré : un disque seul,
-- quel que soit son rayon, est un nœud et un seul.
-- (Vu en jeu le 2026-10-13 : les disques y étaient cherchés au rayon mesuré sur d'autres nœuds du
-- même métier, 11,2 unités ce jour-là. Un point qui répondait d'un peu plus loin donnait alors deux
-- icônes côte à côte, « un doublon qui n'existe pas en vrai ».)
--
-- Des nœuds serrés, tous du même rayon, se lisent mal ainsi : quatre en carré passent pour deux ou
-- trois disques plus gros. Le groupe est donc lu une seconde fois au rayon courant du métier, comme
-- si tous ses nœuds l'avaient, et cette lecture n'est retenue que si elle explique nettement mieux
-- le groupe que la première (Misfit).
--
-- Essayé hors jeu sur des grappes tirées au hasard (Lueur-outils\harness\scan.py), de même rayon
-- ou de rayons mêlés, et sur un champ de nœuds traversé en courant (walk.py, MIX=2) : un nœud seul
-- ne donne jamais deux icônes ; il en manque une quand un disque est presque couvert par ses voisins.
local function Fit(job)
	local set = job.hits[job.place.name]
	if not set then return nil end
	local inside, outline, outside = {}, {}, {}
	local asked = {}
	for _, key in ipairs(job.points) do asked[key] = true end
	for _, key in ipairs(job.points) do
		local x, y = key % ROW * FINE, math.floor(key / ROW) * FINE
		if set[key] then
			inside[#inside + 1] = { x, y, 0, key }
		else
			outside[#outside + 1] = { x, y }
		end
	end
	if #inside == 0 or #outside == 0 then return nil end
	inside = Own(job, inside)
	-- Le contour passe à mi-chemin d'un point qui a répondu et d'un voisin qui ne l'a pas fait.
	-- Ce qui sépare chaque point du groupe du plus proche qui n'a pas répondu se cherche d'anneau en
	-- anneau autour de lui, sur le quadrillage du regard de près, et l'on s'arrête dès qu'un anneau
	-- est plus loin que ce qui est trouvé. (Les comparer tous deux à deux prenait des dizaines de
	-- millisecondes sur un gros groupe : une image qui saute.) Un point est un centre possible si un
	-- disque y tient.
	local centers = {}
	for _, point in ipairs(inside) do
		local key, ox, oy = point[4], 0, 0
		for _, side in ipairs(BESIDE) do
			local other = key + side[1]
			if asked[other] and not set[other] then ox, oy = ox + side[2], oy + side[3] end
		end
		if ox ~= 0 or oy ~= 0 then outline[#outline + 1] = { point[1] + ox * FINE / 2, point[2] + oy * FINE / 2 } end
		local nearest, ring = math.huge, 1
		while ring <= RINGS and ((ring - 1) * FINE) ^ 2 < nearest do
			for along = -ring, ring do
				for _, other in ipairs({ key + along + ROW * ring, key + along - ROW * ring, key + ring + ROW * along, key - ring + ROW * along }) do
					if asked[other] and not set[other] then
						local gap = (point[1] - other % ROW * FINE) ^ 2 + (point[2] - math.floor(other / ROW) * FINE) ^ 2
						if gap < nearest then nearest = gap end
					end
				end
			end
			ring = ring + 1
		end
		point[3] = math.sqrt(math.min(nearest, (RINGS * FINE) ^ 2))
		if point[3] >= MIN_REACH and point[3] <= MAX_REACH + FINE then centers[#centers + 1] = point end
	end

	local contour, discs -- le contour que les nœuds trouvés n'expliquent pas encore, et ces nœuds
	-- les points du contour restant qui se tiennent à ce rayon de (x, y), à `slack` près ; et leur nombre
	local function Near(x, y, radius, slack)
		local low, high, list = math.max(0, radius - slack) ^ 2, (radius + slack) ^ 2, {}
		for _, point in ipairs(contour) do
			local gap = (point[1] - x) ^ 2 + (point[2] - y) ^ 2
			if gap >= low and gap <= high then list[#list + 1] = point end
		end
		return list
	end
	local function Votes(x, y, radius, slack)
		local low, high, count = math.max(0, radius - slack) ^ 2, (radius + slack) ^ 2, 0
		for _, point in ipairs(contour) do
			local gap = (point[1] - x) ^ 2 + (point[2] - y) ^ 2
			if gap >= low and gap <= high then count = count + 1 end
		end
		return count
	end
	-- combien de points du groupe, qu'aucun nœud trouvé n'explique (point[6]), sont à ce rayon de (x, y)
	local function Gain(x, y, radius)
		local near, count = radius * radius, 0
		for _, point in ipairs(inside) do
			if not point[6] and (point[1] - x) ^ 2 + (point[2] - y) ^ 2 <= near then count = count + 1 end
		end
		return count
	end
	-- ce qui sépare (x, y) du plus proche point qui n'a pas répondu
	local function Room(x, y)
		local room = math.huge
		for _, point in ipairs(outside) do
			local gap = (point[1] - x) ^ 2 + (point[2] - y) ^ 2
			if gap < room then room = gap end
		end
		return math.sqrt(room)
	end
	local function Apart(x, y)
		for _, disc in ipairs(discs) do
			-- trop près d'un nœud déjà trouvé : ce serait le même
			if (disc[1] - x) ^ 2 + (disc[2] - y) ^ 2 < MIN_APART * MIN_APART then return false end
		end
		return true
	end
	-- Un nœud de plus : les points du groupe que son disque explique, et le contour qu'il explique,
	-- ne compteront plus pour un autre (ni ce qui reste de contour dans son disque)
	local function Add(x, y, radius)
		discs[#discs + 1] = { x, y, radius }
		local cover, high, rest = (radius + 1) ^ 2, (radius + TOLERANCE) ^ 2, {}
		for _, point in ipairs(inside) do
			if (point[1] - x) ^ 2 + (point[2] - y) ^ 2 <= cover then point[6] = true end
		end
		for _, point in ipairs(contour) do
			if (point[1] - x) ^ 2 + (point[2] - y) ^ 2 > high then rest[#rest + 1] = point end
		end
		contour = rest
	end
	-- Le vrai centre est entre les points du regard de près : autour de (x, y), à l'unité près, c'est
	-- le milieu des places qui expliquent le plus de contour à ce rayon
	local function Center(x, y, radius)
		local tries, top = {}, 0
		for dx = -2, 2 do
			for dy = -2, 2 do
				local count = Votes(x + dx, y + dy, radius, TOLERANCE)
				tries[#tries + 1] = { x + dx, y + dy, count }
				if count > top then top = count end
			end
		end
		local sx, sy, count = 0, 0, 0
		for _, try in ipairs(tries) do
			if try[3] >= top - 1 then sx, sy, count = sx + try[1], sy + try[2], count + 1 end
		end
		return sx / count, sy / count
	end
	-- Le centre et le rayon du disque qui passe près de là : le rayon est la distance moyenne à
	-- laquelle le contour se tient du centre. Le contour d'un voisin, là où il rejoint celui-ci, tire
	-- cette moyenne vers le haut : le disque s'arrête pourtant avant le premier point qui n'a pas répondu.
	local function Polish(x, y, radius)
		for _ = 1, 2 do
			x, y = Center(x, y, radius)
			for _ = 1, 2 do
				local list, sum = Near(x, y, radius, TOLERANCE), 0
				for _, point in ipairs(list) do sum = sum + math.sqrt((point[1] - x) ^ 2 + (point[2] - y) ^ 2) end
				if list[1] then radius = sum / #list end
			end
		end
		return x, y, math.min(radius, Room(x, y) + SNUG / 3)
	end
	-- Un disque est-il possible là ? Il ne contient aucun point qui n'a pas répondu, et le contour
	-- qui passe près de son bord le suit : un cercle qui engloberait plusieurs nœuds coupe leur
	-- contour au lieu de le suivre.
	local function Sound(x, y, radius)
		return radius >= MIN_REACH and radius <= MAX_REACH and Room(x, y) >= radius - SNUG
			and Votes(x, y, radius, TIGHT) >= HUG * Votes(x, y, radius, WIDE)
	end
	-- Le disque dont ce point voit le contour : son centre, son rayon, et ce qu'il explique de
	-- contour (0 si aucun disque n'est possible là). Le cercle qui passe au plus près du contour vu
	-- de ce point le donne, d'où que ce point le voie ; vu de trop large, ce contour est parfois
	-- celui de plusieurs nœuds : il est alors repris de plus près, puis de ce point seul.
	local function Disc(center)
		local x, y, radius
		for _, slack in ipairs({ WIDE, TOLERANCE }) do
			x, y, radius = Circle(Near(center[1], center[2], center[3] + (slack == WIDE and AHEAD or 0.5), slack))
			if x then
				x, y, radius = Polish(x, y, radius)
				if Sound(x, y, radius) then return x, y, radius, Votes(x, y, radius, TOLERANCE) end
			end
		end
		x, y, radius = Polish(center[1], center[2], center[3] + 0.5)
		return x, y, radius, Sound(x, y, radius) and Votes(x, y, radius, TOLERANCE) or 0
	end

	-- Lit le groupe : chaque nœud à son rayon, ou tous au rayon `same`
	local function Read(same)
		contour, discs = outline, {}
		for _, point in ipairs(inside) do point[5], point[6] = math.huge, nil end
		local first
		while #discs < MAX_DISCS do
			-- Le meilleur centre : celui autour duquel le plus de contour se tient à distance égale.
			-- Le contour restant ne fait que diminuer : un centre qui n'en expliquait pas assez
			-- (point[5]) n'est pas recompté.
			local best, bestVotes = nil, MIN_VOTES - 1
			for _, center in ipairs(centers) do
				if center[5] > bestVotes then
					local count = 0
					if not Apart(center[1], center[2]) then
						count = 0
					elseif not same then
						count = Votes(center[1], center[2], center[3] + AHEAD, WIDE)
					elseif center[3] >= same - TOLERANCE - 0.5 then
						count = Votes(center[1], center[2], same, TOLERANCE)
					end
					center[5] = count
					if count > bestVotes then best, bestVotes = center, count end
				end
			end
			if not best then break end
			if same then
				-- il faut un arc de contour, et pas des miettes laissées par les nœuds déjà trouvés
				local x, y = Center(best[1], best[2], same)
				local votes = Votes(x, y, same, TOLERANCE)
				first = first or votes
				if votes < MIN_VOTES or votes < first * SHARE or not Apart(x, y) then break end
				Add(x, y, same)
			else
				-- Il faut un arc de contour autour de lui, et, pour un nœud de plus, des points du groupe
				-- qu'aucun nœud trouvé n'explique : sans quoi ce centre est écarté, et l'on passe au suivant.
				local x, y, radius, votes = Disc(best)
				if votes >= MIN_VOTES and Apart(x, y) and (not discs[1] or Gain(x, y, radius) >= MIN_LOOSE) then
					Add(x, y, radius)
				else
					best[5] = 0
				end
			end
		end
		if not discs[1] then return nil end
		-- Un nœud pris entre deux autres ne montre presque rien de son contour. Il reste alors des
		-- points du groupe qu'aucun nœud trouvé n'explique : le point qui en explique le plus en donne
		-- un, du rayon du premier nœud du groupe faute de pouvoir lire le sien.
		local radius = discs[1][3]
		while #discs < MAX_DISCS do
			local best, bestCount, counts = nil, 0, {}
			for index, center in ipairs(centers) do
				local count = (not same or center[3] >= same - TOLERANCE - 0.5) and Apart(center[1], center[2]) and Gain(center[1], center[2], radius) or 0
				counts[index] = count
				if count > bestCount then best, bestCount = center, count end
			end
			if bestCount < MIN_LOOSE then break end
			local sx, sy, count = 0, 0, 0
			for index, center in ipairs(centers) do
				if counts[index] == bestCount and (center[1] - best[1]) ^ 2 + (center[2] - best[2]) ^ 2 <= (2 * FINE) ^ 2 then
					sx, sy, count = sx + center[1], sy + center[2], count + 1
				end
			end
			Add(sx / count, sy / count, radius)
		end
		return discs
	end
	-- Ce qu'une lecture explique mal du groupe : les points de son contour qui ne sont sur le bord
	-- d'aucun de ses disques, ou qui sont dans l'un d'eux ; les points qui n'ont pas répondu et
	-- qu'un disque contient ; et, pour moitié, les points du groupe qu'aucun disque ne contient.
	local function Misfit(list)
		local count = 0
		for _, point in ipairs(outline) do
			local on, within = false, false
			for _, disc in ipairs(list) do
				local gap = math.sqrt((point[1] - disc[1]) ^ 2 + (point[2] - disc[2]) ^ 2) - disc[3]
				if gap < -TOLERANCE then within = true elseif gap <= TOLERANCE then on = true end
			end
			if within or not on then count = count + 1 end
		end
		for _, point in ipairs(outside) do
			for _, disc in ipairs(list) do
				if (point[1] - disc[1]) ^ 2 + (point[2] - disc[2]) ^ 2 < math.max(0, disc[3] - SNUG) ^ 2 then
					count = count + 1
					break
				end
			end
		end
		for _, point in ipairs(inside) do
			local covered = false
			for _, disc in ipairs(list) do
				if (point[1] - disc[1]) ^ 2 + (point[2] - disc[2]) ^ 2 <= (disc[3] + 1) ^ 2 then
					covered = true
					break
				end
			end
			if not covered then count = count + 0.5 end
		end
		return count
	end

	-- Le moins de nœuds possible : celui qui n'explique rien que les autres n'expliquent est de trop,
	-- ni points du groupe ni contour. (Deux nœuds serrés se lisent parfois comme un disque plus gros,
	-- puis chacun pour lui-même : c'est le gros qui s'en va.)
	local function Idle(list, index)
		local disc, own = list[index], 0
		local function Elsewhere(point, slack)
			for other, with in ipairs(list) do
				if other ~= index and (point[1] - with[1]) ^ 2 + (point[2] - with[2]) ^ 2 <= (with[3] + slack) ^ 2 then return true end
			end
			return false
		end
		for _, point in ipairs(inside) do
			if (point[1] - disc[1]) ^ 2 + (point[2] - disc[2]) ^ 2 <= (disc[3] + 1) ^ 2 and not Elsewhere(point, 1) then own = own + 1 end
		end
		for _, point in ipairs(outline) do
			local gap = math.sqrt((point[1] - disc[1]) ^ 2 + (point[2] - disc[2]) ^ 2) - disc[3]
			if gap >= -TOLERANCE and gap <= TOLERANCE and not Elsewhere(point, TOLERANCE) then own = own + 1 end
		end
		return own < SPARE
	end
	local function Prune(list)
		local index = 1
		while list[2] and index <= #list do
			if Idle(list, index) then
				table.remove(list, index)
				index = 1
			else
				index = index + 1
			end
		end
		return list, Misfit(list)
	end

	-- Là où deux points du jeu répondent ensemble, l'infobulle écrit leur nom deux fois, une rangée
	-- chacun. Deux disques dont le recouvrement a été essayé sans que le nom y soit jamais écrit deux
	-- fois sont donc un seul point du jeu, qui ne répond pas en rond : ils n'en font qu'un, entre eux,
	-- assez grand pour couvrir les deux (le quatrième champ le dit : son rayon n'est pas une mesure).
	-- (Vu en jeu le 2026-10-15, deux fois : un Pacifique, puis une Terrestrine, montrés par deux icônes
	-- « dans un groupe », à dix unités l'une de l'autre, du rayon des autres plantes ; chaque fois, le
	-- point sous la souris portait la flèche d'un nœud plus bas que le joueur. Dans le faux client, un
	-- point qui répond 1,2 fois plus loin en largeur qu'en hauteur donne ainsi deux icônes à chaque
	-- balayage : la forme seule du groupe ne les distingue pas de deux points ronds, à la finesse du
	-- regard de près.) Que le jeu écrive deux fois le nom de deux points qui se recouvrent n'a pas été
	-- vu, et s'il ne le faisait pas, deux nœuds proches n'auraient plus qu'une icône (dans le faux
	-- client, plus de la moitié des paires serrées). Lueur ne s'y fie donc qu'une fois qu'il l'a vu faire,
	-- ou pour une flèche : les trois doublons vus en jeu en étaient, et deux flèches du même nom qui se
	-- recouvrent sont rares.
	local twice = job.many[job.place.name] or {}
	local trusted = Doubled() or job.arrows[job.place.name] == true
	local function Alone(a, b)
		local shared = 0
		for _, point in ipairs(inside) do
			if (point[1] - a[1]) ^ 2 + (point[2] - a[2]) ^ 2 <= (a[3] - SHARED_IN) ^ 2
				and (point[1] - b[1]) ^ 2 + (point[2] - b[2]) ^ 2 <= (b[3] - SHARED_IN) ^ 2 then
				if twice[point[4]] then return false end
				shared = shared + 1
			end
		end
		return shared >= MIN_SHARED
	end
	local function Join(list)
		if not list or not trusted then return list end
		local index = 1
		while list[2] and index < #list do
			local a, joined = list[index], false
			for other = index + 1, #list do
				local b = list[other]
				if Alone(a, b) then
					-- son centre est le milieu des points du groupe que ces deux disques couvraient, son
					-- rayon va jusqu'au plus éloigné
					local sx, sy, count, mine = 0, 0, 0, {}
					for _, point in ipairs(inside) do
						if (point[1] - a[1]) ^ 2 + (point[2] - a[2]) ^ 2 <= (a[3] + 1) ^ 2
							or (point[1] - b[1]) ^ 2 + (point[2] - b[2]) ^ 2 <= (b[3] + 1) ^ 2 then
							sx, sy, count = sx + point[1], sy + point[2], count + 1
							mine[#mine + 1] = point
						end
					end
					local x, y, radius = sx / count, sy / count, 0
					for _, point in ipairs(mine) do radius = math.max(radius, math.sqrt((point[1] - x) ^ 2 + (point[2] - y) ^ 2)) end
					list[index] = { x, y, radius + 1, true }
					table.remove(list, other)
					joined = true
					break
				end
			end
			if joined then index = 1 else index = index + 1 end
		end
		return list
	end

	-- Un point du jeu peut répondre dans un carré, et non dans un disque : vu en jeu le 2026-10-15
	-- (/lueur scan, la zone d'une Terrestrine : 22 unités de côté, à bords droits ; les rayons lus de
	-- 11 à 14 unités pour les autres plantes le disent aussi). Un carré seul se lit parfois comme deux
	-- disques côte à côte, à dix unités l'un de l'autre : les doublons de ce jour-là, alignés comme
	-- ceux du faux client (un carré seul sur dix, en largeur ou en hauteur). Les points d'un groupe
	-- qui remplissent leur rectangle, presque carré, sont donc ce seul point : un disque en son milieu,
	-- qui couvre le carré. Deux points ronds qui se recouvrent laissent vides les coins du rectangle,
	-- et deux carrés côte à côte en font un rectangle allongé.
	local function Square(list)
		if not list or not list[2] then return list end
		local x0, y0, x1, y1, mine = math.huge, math.huge, -math.huge, -math.huge, {}
		for _, point in ipairs(inside) do
			x0, y0, x1, y1 = math.min(x0, point[1]), math.min(y0, point[2]), math.max(x1, point[1]), math.max(y1, point[2])
			mine[point[4]] = true
		end
		local wide, tall = x1 - x0 + FINE, y1 - y0 + FINE
		if math.max(wide, tall) > SQUARE_RATIO * math.min(wide, tall) then return list end
		-- ni plus grand qu'un point du jeu : deux carrés serrés en font un rectangle plus large
		if math.max(wide, tall) > 2 * reaches[job.place.node.kind].value + FINE then return list end
		local asked, answered = 0, 0
		for _, key in ipairs(job.points) do
			local x, y = key % ROW * FINE, math.floor(key / ROW) * FINE
			if x >= x0 and x <= x1 and y >= y0 and y <= y1 then
				asked = asked + 1
				if mine[key] then answered = answered + 1 end
			end
		end
		if answered < SQUARE_FILL * asked then return list end
		return { { (x0 + x1) / 2, (y0 + y1) / 2, math.sqrt(wide * wide + tall * tall) / 2, true } }
	end

	-- La seconde lecture ne se fait que si elle peut l'emporter : elle est retenue si elle explique
	-- bien le groupe, et nettement mieux que la première.
	local own, left = Read(), math.huge
	if own then own, left = Prune(own) end
	local known = reaches[job.place.node.kind]
	if known.measured and left >= CLEARLY then
		local same = Read(known.value)
		if same then
			local rest
			same, rest = Prune(same)
			if rest <= WELL and rest + CLEARLY <= left then return Join(Square(same)) end
		end
	end
	return Join(Square(own))
end

-- Un groupe que ce balayage ne regardera pas de près, pour ne pas y passer trop de temps : les nœuds
-- déjà bien placés qui le touchent y restent ; à défaut il a une place, son milieu.
local function Rough(places, place, map)
	local mine = map and Placed(place.name, place.keys, map) or {}
	if not mine[1] then
		places[#places + 1] = place
		return
	end
	for _, marker in ipairs(mine) do
		places[#places + 1] = { name = place.name, node = place.node, set = place.set, pin = marker }
	end
end

-- La grille est faite : chaque groupe de points d'un nœud voulu devient une place, exacte tout
-- de suite si un balayage précédent la connaît, sinon à affiner ou à regarder de près
local function Sort()
	local places, refines, jobs, fine = {}, {}, {}, 0
	local map = scan.view.map -- sans carte, une place ne se garde pas d'un balayage à l'autre

	local heard = {} -- les métiers dont ce balayage a lu au moins un nom
	lastNames = {}
	for name, set in pairs(scan.hits) do
		local points, gray = 0, false
		for _, value in pairs(set) do
			points = points + 1
			if value == 2 then gray = true end
		end
		lastNames[name] = { points = points, gray = gray }
		local node = ns.NodeOf(name)
		if node then heard[node.kind] = true end
		if node and Wanted(node.kind) then
			for _, keys in ipairs(Groups(set)) do
				local x0, y0, x1, y1, x, y = Box(keys)
				local place = { name = name, node = node, set = set, keys = keys, x = x, y = y, box = { x0, y0, x1, y1 } }
				-- ce qu'un disque seul couvre au plus de grille : tout groupe qui pourrait en être un est
				-- essayé comme tel, quel que soit le rayon des nœuds déjà mesurés
				local span = 2 * MAX_REACH + 1
				local single = x1 - x0 <= span and y1 - y0 <= span
				local pin = map and Pinned(name, x, y, math.max(x1 - x0, y1 - y0), keys) or nil
				-- placé quand le bord de la minimap le tronquait, et tout entier dedans désormais :
				-- son centre peut se chercher par ses bords
				if pin and pin.rim and reader.Depth(x - width / 2, y - width / 2, width / 2) > Radius(pin) + STEP then
					pin = nil
				end
				local split = map and not pin and Known(name, keys) or nil
				if map and not pin and not split and AtRim(keys) then
					-- Au bord de la minimap la place d'un nœud se lit mal, et son disque tronqué passe pour
					-- plusieurs : les nœuds déjà bien placés qui expliquent ce groupe à eux seuls y restent.
					local mine, whole = Placed(name, keys, map)
					if whole then split = mine end
				end
				if pin then
					place.pin, place.single = pin, true
					places[#places + 1] = place
				elseif split then
					for _, marker in ipairs(split) do
						places[#places + 1] = { name = name, node = node, set = set, pin = marker }
					end
				elseif single then
					refines[#refines + 1] = place
					places[#places + 1] = place
				else
					-- (trop grand pour des nœuds de front : un regard de près coûterait des centaines d'images)
					Rough(places, place, map)
				end
			end
		end
	end
	scan.places, scan.refines, scan.jobs, scan.fine, scan.map, scan.heard = places, refines, jobs, fine, map, heard
	scan.phase = "refine"
end

-- Un nœud d'un groupe est-il dans une grotte ? Là où plusieurs nœuds du groupe répondent, le jeu
-- écrit leur nom une fois par nœud, en gris ou non, sans dire lequel est lequel : on s'en tient
-- donc aux points où celui-ci répond seul, et à défaut à son centre.
local function GrayOf(job, set, discs, disc)
	local gray, plain = 0, 0
	for _, key in ipairs(job.points) do
		local value = set[key]
		if value then
			local x, y = key % ROW * FINE, math.floor(key / ROW) * FINE
			local alone = (x - disc[1]) ^ 2 + (y - disc[2]) ^ 2 <= disc[3] * disc[3]
			for _, other in ipairs(discs) do
				if other ~= disc and (x - other[1]) ^ 2 + (y - other[2]) ^ 2 <= other[3] * other[3] then alone = false end
			end
			if alone then
				if value == 2 then gray = gray + 1 else plain = plain + 1 end
			end
		end
	end
	if gray + plain == 0 then return GrayAt(set, disc[1], disc[2], FINE) end
	return gray > plain
end

-- Un groupe regardé de près donne ses nœuds, ou à défaut son milieu
local function EndJob(job)
	local place = job.place
	local discs = Fit(job)
	local set = job.hits[place.name]
	scan.looked = scan.looked + 1
	if discs then
		-- un seul nœud, tout entier dans la minimap : son disque dit de combien un point de ce métier répond
		local alone = #discs == 1
		if alone and not discs[1][4] and not place.rim and not AtRim(place.keys) then Learn(place.node.kind, discs[1][3]) end
		for _, disc in ipairs(discs) do
			scan.places[#scan.places + 1] = { name = place.name, node = place.node, set = place.set, keys = place.keys, x = disc[1], y = disc[2],
				fitted = not alone, exact = alone, reach = disc[3], rim = place.rim, gray = GrayOf(job, set, discs, disc) }
		end
	else
		scan.places[#scan.places + 1] = place
	end
end

-- Un point de la grille de cet ensemble est-il à moins de `range` unités de (x, y) ? L'ensemble est
-- ce qu'un nom a répondu (numéro du point -> valeur), ou la liste des points d'un groupe (`list`).
local function Heard(set, x, y, range, list)
	if not set then return false end
	for first, second in pairs(set) do
		local key = list and second or first
		if (key % ROW * STEP - x) ^ 2 + (math.floor(key / ROW) * STEP - y) ^ 2 <= range * range then return true end
	end
	return false
end

-- Le balayage est fait : ses places deviennent les nœuds connus. Chaque place est, dans l'ordre,
-- le nœud déjà placé là (`pin`), sinon le nœud connu du même nom le plus proche d'elle, sinon un
-- nœud nouveau. Un nœud connu reste le même objet d'un balayage à l'autre : il garde son icône,
-- et sa place ne change que pour une mesure meilleure que celle qu'il a.
local function Finish()
	local half = width / 2
	-- (les places sont celles de la minimap au début du balayage : le joueur a pu marcher depuis)
	local view = scan.view
	local radius, turning, facing = view.radius, view.turning, view.facing
	local map, px, py, wide, tall = view.map, view.x, view.y, view.wide, view.tall
	local anchored = map ~= nil and radius ~= nil and not (turning and not facing)
	local found, claimed, loose, fresh, again = {}, {}, {}, false, false
	-- (un balayage dure : le client a pu charger depuis la grille le nom d'une plante, et son image)
	for _, place in ipairs(scan.places) do
		local node = ns.NodeOf(place.name)
		if node and node.kind == place.node.kind then place.node = node end
	end

	local function Keep(marker, place)
		claimed[marker] = true
		-- ce que Lueur sait de ce nom a pu changer depuis : l'objet d'une plante que le client vient de charger
		marker.node, marker.held, marker.missed = place.node, nil, 0
		found[#found + 1] = marker
	end
	for _, place in ipairs(scan.places) do
		local marker = place.pin
		if not marker then
			loose[#loose + 1] = place
		elseif not claimed[marker] then
			Keep(marker, place)
			marker.age = marker.age + 1
			if place.single then marker.fitted = nil end
			-- (un nœud d'un groupe garde ce que le regard de près en a dit : la grille ne sépare pas
			-- le gris de l'un de celui de son voisin)
			if not marker.fitted then
				local gray = GrayAt(place.set, marker.x, marker.y, STEP)
				if gray ~= nil then marker.gray = gray end
			end
		end
	end

	-- Les autres places, chacune avec sa place sur la carte de la zone, et ce qui la sépare de chaque
	-- nœud connu du même nom : en mètres sur la carte, en unités de minimap sans elle
	local perYard = anchored and half / radius or 1 -- unités de minimap par unité d'écart
	local matches = {}
	for _, place in ipairs(loose) do
		-- Deux nœuds du même nom à moins d'un rayon de disque l'un de l'autre répondent ensemble, et un
		-- balayage les place tous les deux : une place seule, aussi près d'un nœud connu, est ce nœud.
		-- Au bord de la minimap le disque d'un nœud est tronqué, sa place mal lue, et son contour passe
		-- parfois pour deux nœuds : c'est de plus loin qu'une place vue là est le nœud que l'on connaît.
		local reach = place.reach or reaches[place.node.kind].value
		local limit = math.max(anchored and MERGE or 0, reach / perYard)
		local rimLimit = limit + 2 * reach / perYard
		place.depth = reader.Depth(place.x - half, place.y - half, half)
		if anchored then
			local dx, dy = place.x - half, place.y - half
			local yards = math.sqrt(dx * dx + dy * dy) / half * radius
			local way = math.atan2(dx, dy) -- sens des aiguilles depuis le haut de la minimap
			if turning then way = way - facing end
			place.yards = yards
			place.mx, place.my = px + yards * math.sin(way) / wide, py - yards * math.cos(way) / tall
		end
		for _, old in ipairs(markers) do
			if not claimed[old] and old.name == place.name and old.map == (anchored and map or nil) then
				local gap
				if anchored then
					gap = math.sqrt(((old.mx - place.mx) * wide) ^ 2 + ((old.my - place.my) * tall) ^ 2)
				else
					gap = math.sqrt((old.x - place.x) ^ 2 + (old.y - place.y) ^ 2)
				end
				-- (de plus loin, seulement si ce nœud peut être ce qui a répondu là : son disque touche le groupe)
				if gap <= limit or ((place.rim or old.rim) and gap <= rimLimit and Heard(place.keys, old.x, old.y, Radius(old) + 6, true)) then
					matches[#matches + 1] = { gap = gap, place = place, marker = old }
				end
			end
		end
	end
	table.sort(matches, function(a, b) return a.gap < b.gap end)

	-- Donne à un nœud la place d'une mesure, `weight` fois moins lourde que celle qu'il avait (0 : elle
	-- la remplace). Son icône part d'où elle était.
	local function Put(marker, place, weight)
		if anchored then
			local mx, my = (marker.mx * weight + place.mx) / (weight + 1), (marker.my * weight + place.my) / (weight + 1)
			marker.dmx, marker.dmy = (marker.dmx or 0) + marker.mx - mx, (marker.dmy or 0) + marker.my - my
			marker.mx, marker.my = mx, my
		else
			marker.x, marker.y = (marker.x * weight + place.x) / (weight + 1), (marker.y * weight + place.y) / (weight + 1)
		end
		marker.count = weight + 1
	end
	for _, match in ipairs(matches) do
		local place, marker = match.place, match.marker
		if not place.marker and not claimed[marker] then
			place.marker = marker
			Keep(marker, place)
			local gray = place.gray
			if gray == nil then gray = GrayAt(place.set, place.x, place.y, STEP) end
			if gray ~= nil then marker.gray = gray end
			local units = match.gap * perYard
			local worth, had = Worth(place), marker.worth
			local weight -- ce que pèse la place connue devant la nouvelle ; nil : elle reste
			if worth > had then
				weight = 0
			elseif worth < had then
				-- une mesure qui vaut moins ne déplace pas un nœud, sauf le regard de près qui trouve loin
				-- de lui un nœud que ses bords disaient seul : c'étaient deux nœuds pris pour un
				if worth == FITTED and units >= SLACK then weight = 0 end
			elseif worth == SURE then
				-- retrouvé là à l'erreur de mesure près : il n'en bouge pas
				if units >= STILL then weight = 0 end
			elseif worth == RIM_PLACE then
				-- au bord, la meilleure des deux est celle qui a vu le plus du disque : la plus à l'intérieur
				if place.depth > marker.depth + 1 then weight = 0 end
			else
				-- deux places approchées changent un peu à chaque balayage : elles se moyennent
				weight = math.min(marker.count, AVERAGE)
			end
			if weight then
				Put(marker, place, weight)
				marker.exact, marker.fitted, marker.rim, marker.worth, marker.depth = place.exact, place.fitted, place.rim, worth, place.depth
				marker.reach = place.reach or marker.reach
			elseif place.fitted then
				marker.fitted = true -- il fait partie d'un groupe séparé : Known s'en servira
			end
			if place.fitted or place.exact then marker.age = 0 end
		end
	end
	for _, place in ipairs(loose) do
		if not place.marker then
			local gray = place.gray
			if gray == nil then gray = GrayAt(place.set, place.x, place.y, STEP) end
			found[#found + 1] = { name = place.name, node = place.node, x = place.x, y = place.y, gray = gray or false,
				exact = place.exact, fitted = place.fitted, rim = place.rim, worth = Worth(place), depth = place.depth, reach = place.reach,
				age = 0, count = 1, missed = 0, far = false, born = GetTime(),
				map = anchored and map or nil, mx = place.mx, my = place.my, yards = place.yards }
			fresh = true
		end
	end

	-- Les nœuds connus que ce balayage n'a pas retrouvés. Aucun ne reste à côté de ce que le balayage a
	-- vu : un nœud ne se montre jamais deux fois. (Vu en jeu le 2026-10-13, avec l'alternance : « la
	-- minimap affiche souvent la même ressource plusieurs fois ». Un nœud non retrouvé restait alors
	-- deux balayages, et sans limite tant que les pistages s'alternaient à moins de trois secondes.)
	local other = turn.kind and anchored and (turn.kind == "herb" and "ore" or "herb") or nil
	local now = GetTime()
	local picked = pickedAt ~= nil and now - pickedAt <= PICK_TIME
	local sighted = #found -- jusque-là, `found` ne tient que ce que ce balayage a vu
	for _, old in ipairs(markers) do
		if not claimed[old] then
			local kind, keep = old.node.kind, false
			local twin = false -- le balayage a-t-il placé un nœud du même nom tout près ? C'est alors lui
			for index = 1, sighted do
				local near = found[index]
				if near.name == old.name and (near.x - old.x) ^ 2 + (near.y - old.y) ^ 2 < (TWIN * Radius(old)) ^ 2 then twin = true end
			end
			if twin or old.map ~= map or not Wanted(kind) or scan.gone[old] then
				-- en double, resté sur une autre carte, plus voulu, ou que le jeu ne nomme plus en son milieu
			elseif kind == other then
				-- Alternance des pistages : le métier éteint n'a pas de points par où le trouver. Ses nœuds
				-- restent donc comme ils étaient jusqu'à son tour. Sauf celui dont le nom a répondu près de
				-- lui : ses points se voyaient encore, et le balayage en a fait un autre nœud que lui.
				keep = not Heard(scan.hits[old.name], old.x, old.y, Radius(old) + STEP)
				old.held = keep or nil
			elseif not old.far and not scan.heard[kind] then
				-- Le balayage n'a lu aucun nom de ce métier : les points du jeu tardent après un changement
				-- de pistage, ou l'infobulle n'a rien répondu. Ses nœuds ne s'en vont qu'au second balayage
				-- de suite dans ce cas. Sauf celui que le joueur vient de récolter, et celui posé faute de
				-- mieux au milieu d'un groupe.
				old.missed = (old.missed or 0) + 1
				keep = old.missed < MISSES and old.worth > ROUGH and not (picked and old.yards ~= nil and old.yards <= PICK_REACH)
				again = again or keep
			end
			-- (dans tout autre cas le balayage a lu des nœuds de ce métier, et pas celui-ci : il n'est plus là)
			if keep then found[#found + 1] = old else Fade(old) end
		end
	end

	turn.scanned = true
	-- À l'arrêt, rien n'entre par le bord de la minimap : sans rien de neuf, le balayage s'espace
	local moved = map ~= spot.map or px ~= spot.x or py ~= spot.y
	spot.map, spot.x, spot.y = map, px, py
	if fresh or moved or again then slow = 1 else slow = math.min(slow * 2, MAX_SLOW) end
	-- (le balayage suivant n'a lieu que s'il y a du neuf, StartScan en juge : l'alternance des pistages,
	-- elle, se surveille de près ; et des nœuds gardés faute d'avoir rien entendu de leur métier se relisent)
	wait = reader.POLL
	if again then reader.due = true end
	last.points, last.seconds, last.jobs = probes - scan.probes, now - scan.started, scan.looked
	last.grid, last.checks, last.measured, last.full = #scan.points, #scan.checks, scan.measured, scan.full
	last.frames, last.again = reader.s and reader.s.frames or 0, reader.s and reader.s.again or 0
	-- ce que ce balayage a vu : le suivant ne relit que le reste
	reader.cover = view.map and view or nil
	reader.last, reader.lastAt = view.map and view or nil, now
	markers, scan, refit = found, nil, false
	seen.map = nil -- le suivi replace tout à la prochaine image
	ns.ForgetSkills()
	Draw()
end

-- Le balayage d'un bout à l'autre, dans une coroutine : chaque essai attend sa réponse à l'image
-- suivante (reader.Look). La grille, là où le balayage précédent n'a pas vu ; un point au milieu de
-- chaque nœud connu ailleurs ; les bords des groupes que la grille a entendus ; puis Finish.
local function Run()
	for _, key in ipairs(scan.points) do
		Probe(key % ROW * STEP, math.floor(key / ROW) * STEP, scan.hits, key)
	end
	local kept = {}
	for _, marker in ipairs(scan.checks) do
		if Under(marker.name, marker.x, marker.y) then kept[#kept + 1] = marker else scan.gone[marker] = true end
	end
	reader.Freeze()
	Sort()
	-- Un balayage de toute la minimap vérifie aussi les nœuds que la grille dit encore là : un point
	-- juste au-delà de chacun de leurs quatre bords ne doit pas répondre. La grille est trop lâche pour
	-- voir un nœud écarté de moins d'un pas.
	if scan.full then
		local checked = {}
		for _, place in ipairs(scan.places) do
			local marker = place.pin
			if marker and place.single and not checked[marker] then
				checked[marker] = true
				local crowded, beyond = false, Radius(marker) + 1.5
				for _, other in ipairs(markers) do
					if other ~= marker and other.name == marker.name and (other.x - marker.x) ^ 2 + (other.y - marker.y) ^ 2 < (2 * beyond) ^ 2 then
						crowded = true
					end
				end
				local moved = false
				for _, way in ipairs(crowded and {} or { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local px, py = marker.x + way[1] * beyond, marker.y + way[2] * beyond
					if not moved and reader.Depth(px - width / 2, py - width / 2, width / 2) > 1 and Under(marker.name, px, py) then moved = true end
				end
				if moved then
					place.pin, place.single = nil, nil
					scan.refines[#scan.refines + 1] = place
				end
			end
		end
	end
	for _, marker in ipairs(kept) do
		scan.places[#scan.places + 1] = { name = marker.name, node = marker.node, set = scan.hits[marker.name] or {}, pin = marker,
			single = marker.exact }
		scan.heard[marker.node.kind] = true
	end
	-- les bords des groupes, un nombre limité par balayage : les autres gardent leur milieu
	local rough = {}
	scan.measured = 0
	-- Un point de la grille est-il déjà expliqué par un nœud que ce balayage a mesuré ?
	local function Explained(name, x, y)
		for _, place in ipairs(scan.places) do
			if place.name == name and (place.exact or place.fitted) and place.x
				and (place.x - x) ^ 2 + (place.y - y) ^ 2 <= (place.reach or reaches[place.node.kind].value) ^ 2 then
				return true
			end
		end
		return false
	end
	local function Remove(place)
		for index, other in ipairs(scan.places) do
			if other == place then
				table.remove(scan.places, index)
				return
			end
		end
	end
	local SEEDS = 3 -- points de la grille d'où se remesure un groupe dont le milieu ne répond pas
	while scan.refines[1] and scan.measured < reader.MEASURES do
		local place = table.remove(scan.refines, 1)
		local parent = place.parent
		if parent and Explained(place.name, place.x, place.y) then
			Remove(place)
		else
			scan.measured = scan.measured + 1
			Refine(place)
			if place.merged and not parent then
				-- Le milieu du groupe ne répond pas, ou ses bords ne se trouvent pas : plusieurs nœuds dont la
				-- grille a joint les réponses. Chacun se cherche depuis un point de la grille qui l'a entendu.
				Remove(place)
				rough[#rough + 1] = place
				for index = 1, math.min(SEEDS, #place.keys) do
					local key = place.keys[index]
					local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
					local seed = { name = place.name, node = place.node, set = place.set, keys = { key }, x = x, y = y, box = { x, y, x, y }, parent = place }
					scan.places[#scan.places + 1] = seed
					table.insert(scan.refines, index, seed)
				end
			elseif place.split or place.merged or (place.rim and not place.exact) then
				Remove(place)
				if place.split then
					for _, spot in ipairs(place.split) do
						scan.places[#scan.places + 1] = { name = place.name, node = place.node, set = place.set, keys = place.keys, x = spot[1], y = spot[2],
							fitted = true, reach = place.reach }
					end
					if parent then parent.found = true end
				elseif not parent then
					rough[#rough + 1] = place
				end
			elseif parent then
				parent.found = true
			end
		end
	end
	-- les graines qui restent faute de temps, ou d'un groupe que rien n'a su lire, ne font pas de places
	for index = #scan.places, 1, -1 do
		local place = scan.places[index]
		if place.parent and not (place.exact or place.fitted) then table.remove(scan.places, index) end
	end
	reader.Freeze()
	for _, place in ipairs(rough) do
		if not place.found then Rough(scan.places, place, scan.map) end
	end
	-- Un nœud retrouvé en son milieu, que la grille a aussi entendu du côté qu'elle a relu, ne fait
	-- pas un second nœud
	for index = #scan.places, 1, -1 do
		local place = scan.places[index]
		if not place.pin then
			for _, marker in ipairs(kept) do
				if marker.name == place.name and (marker.x - place.x) ^ 2 + (marker.y - place.y) ^ 2 <= Radius(marker) ^ 2 then
					table.remove(scan.places, index)
					break
				end
			end
		end
	end
	-- Ni deux places d'un même nom l'une sur l'autre (deux groupes de la grille dont les bords
	-- mènent au même point) : la meilleure reste, un nœud déjà connu avant tout
	local function Rank(place) return place.pin and 9 or Worth(place) end
	local function Where(place) if place.pin then return place.pin.x, place.pin.y end return place.x, place.y end
	for index = #scan.places, 1, -1 do
		local place = scan.places[index]
		local x, y = Where(place)
		for other = 1, index - 1 do
			local near = scan.places[other]
			local ox, oy = Where(near)
			if near.name == place.name and x and ox and (near.pin ~= place.pin or not near.pin)
				and (ox - x) ^ 2 + (oy - y) ^ 2 < (TWIN * (place.reach or reaches[place.node.kind].value)) ^ 2 then
				if Rank(place) > Rank(near) then scan.places[other] = place end
				table.remove(scan.places, index)
				break
			end
		end
	end
	Finish()
end

---------------------------------------------------------------------------
-- Pistages, et leur alternance
---------------------------------------------------------------------------

-- Les métiers dont le pistage est actif, et la place de chaque pistage de récolte dans la liste
-- du jeu ; nil si le jeu ne le dit pas
local function Finders()
	local count = SafeCall(C_Minimap.GetNumTrackingTypes)
	if type(count) ~= "number" then return nil end
	local on, listed = {}, {}
	for index = 1, count do
		local info = SafeCall(C_Minimap.GetTrackingInfo, index)
		if type(info) == "table" then
			local spell, active = info.spellID, info.active
			if IsSecret(spell) or IsSecret(active) then return nil end
			local kind = spell and FINDERS[spell]
			if kind then
				listed[kind] = index
				if active then on[kind] = true end
			end
		end
	end
	return on, listed
end

local function Casting(read)
	if not read then return false end
	local ok, name = pcall(read, "player")
	return ok and (IsSecret(name) or name ~= nil)
end

-- Changer de pistage lance un sort : pas pendant que le joueur récolte, incante ou fouille
local function Busy()
	-- (ni en combat : la minimap peut s'y lire, les pistages n'y changent pas)
	return looting or InCombatLockdown() or Casting(UnitCastingInfo) or Casting(UnitChannelInfo)
end

-- Demande au jeu d'allumer le pistage de ce métier (`index`, dans la liste du jeu). Le jeu lance
-- un sort : le pistage ne change qu'un instant plus tard (Blizzard_Minimap le dit de son propre
-- menu), et pas du tout si le sort n'était pas prêt. Renvoie true si la demande est partie.
-- Le jeu joue un clic d'interface quand un pistage change (uchatscrollbutton.ogg, 567407, d'après
-- NodeSight 1.8.1). Ce son sert à la plupart des boutons : il n'est coupé que le temps de la bascule,
-- SWITCH_MUTE secondes. (Demandé le 2026-11-09 : « retire le son du changement de découverte lors de
-- l'alternance ».)
local SWITCH_SOUND, SWITCH_MUTE = 567407, 0.6

function turn.Unmute()
	if turn.muted and UnmuteSoundFile then pcall(UnmuteSoundFile, SWITCH_SOUND) end
	turn.muted = nil
end

local function Ask(kind, index)
	turn.want, turn.at, turn.tries = kind, GetTime(), (turn.tries or 0) + 1
	if MuteSoundFile and pcall(MuteSoundFile, SWITCH_SOUND) then turn.muted = GetTime() + SWITCH_MUTE end
	return (pcall(C_Minimap.SetTracking, index, true))
end

-- Deux métiers de récolte : le jeu ne montre les points que d'un pistage à la fois. Lueur allume
-- donc l'autre quand le joueur s'est éloigné d'assez du lieu de la dernière bascule, un balayage
-- au moins ayant eu lieu entre-temps. Renvoie true s'il l'a demandé.
local function Switch(kind, index)
	if not C_Minimap.SetTracking or Busy() then return false end
	local map, x, y, wide, tall = MapPosition()
	if not map then return false end
	if map ~= turn.map then -- autre carte : la distance se compte d'ici
		turn.map, turn.x, turn.y = map, x, y
		return false
	end
	local east, north = (x - turn.x) * wide, (y - turn.y) * tall
	local yards = ns.GetOption("nodeSwitchYards")
	if not turn.scanned or east * east + north * north < yards * yards then return false end
	turn.x, turn.y, turn.scanned, turn.tries = x, y, false, 0
	return Ask(kind, index)
end

local function StartScan()
	wait = WAIT * slow
	-- ni en combat (si le joueur ne le veut pas), ni la minimap cachée, ni la vraie souris dessus : le joueur la regarde
	if reader.Fight() or not Minimap:IsVisible() or Minimap:IsMouseOver() then return end
	-- le pistage vient de changer : les points du jeu ne sont pas encore ceux qu'il montre
	local since = turn.changed and GetTime() - turn.changed
	if since and since < SWITCH_SETTLE then
		wait = SWITCH_SETTLE - since
		return
	end
	local on, listed = Finders()
	turn.kind = nil
	if on then
		local alternating = ns.GetOption("nodeSwitch") and Wanted("herb") and Wanted("ore") and listed.herb and listed.ore
		if turn.want then
			if on[turn.want] or not alternating then
				turn.want = nil -- la bascule a eu lieu, ou n'a plus lieu d'être
			elseif GetTime() - turn.at >= SWITCH_RETRY then
				-- Le jeu n'a pas fait la bascule demandée : le sort n'était pas prêt. Elle est redemandée,
				-- quelques fois ; après quoi ce sera pour la prochaine.
				if turn.tries >= SWITCH_TRIES then
					turn.want = nil
				elseif C_Minimap.SetTracking and not Busy() then
					Ask(turn.want, listed[turn.want])
					wait, slow = SWITCH_WAIT, 1
					return
				end
			end
		end
		if alternating and (on.herb == true) ~= (on.ore == true) then
			turn.kind = on.herb and "herb" or "ore"
			local other = on.herb and "ore" or "herb"
			if not turn.want and Switch(other, listed[other]) then
				wait, slow = SWITCH_WAIT, 1
				return
			end
		end
		if not ((on.herb and Wanted("herb")) or (on.ore and Wanted("ore"))) then
			if turn.want then
				-- entre deux pistages, le temps que le sort de la bascule parte : rien ne s'efface
				wait = SWITCH_POLL
				return
			end
			-- rien à trouver sur la minimap
			wait = IDLE_WAIT
			Clear()
			return
		end
	end
	-- Un balayage cache la minimap un instant : il n'a lieu que s'il peut apporter du neuf. Au premier,
	-- après un changement de pistage, de zoom ou de carte, quand le joueur a parcouru une part du rayon
	-- de la minimap depuis le dernier, à l'arrêt de loin en loin, ou quand il le demande.
	local map, px, py, wide, tall = MapPosition()
	local radius, turning, facing = View()
	if not reader.due then
		local last = reader.last
		local yards = ns.GetOption("nodeScanYards") or 35
		local moved = map ~= nil and last ~= nil and map == last.map and ((px - last.x) * wide) ^ 2 + ((py - last.y) * tall) ^ 2 >= yards * yards
		local elsewhere = map ~= nil and not (last and map == last.map)
		if not (moved or elsewhere or GetTime() - (reader.lastAt or 0) >= reader.REST) then
			wait = math.min(wait, reader.POLL)
			return
		end
	end
	-- et seulement quand la minimap peut passer sous la souris sans que rien ne s'en mêle
	local why = reader.Ready()
	reader.waiting = why
	if why then
		wait = math.min(wait, reader.RETRY)
		return
	end
	left, bottom, scale, width = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if not (left and bottom and scale and width) or width <= 0 then return end
	-- le pas de la grille suit le rayon de réponse : un point du jeu en touche toujours un
	local reach = math.huge
	for kind in pairs(OPTION) do
		if Wanted(kind) then reach = math.min(reach, reaches[kind].value, reaches[kind].least or math.huge) end
	end
	STEP = math.max(reader.MIN_STEP, math.min(reader.MAX_STEP, math.floor(reader.GRID * reach)))
	local shape = reader.Quarters().key
	if gridWidth ~= width or reader.gridStep ~= STEP or reader.gridShape ~= shape then
		gridWidth, grid, reader.gridStep, reader.gridShape = width, {}, STEP, shape
		local half = width / 2
		for column = 0, math.floor(width / STEP) do
			for line = 0, math.floor(width / STEP) do
				if reader.Depth(column * STEP - half, line * STEP - half, half) >= 0 then grid[#grid + 1] = column + ROW * line end
			end
		end
	end
	-- Ce que le balayage précédent a vu ne se relit pas, sauf une fois sur FULL : un point au milieu de
	-- chaque nœud bien placé y suffit à dire qu'il est encore là. Autour d'un nœud mal placé, la grille
	-- repasse.
	reader.scans = reader.scans + 1
	local cover = reader.cover
	local full = reader.full or reader.scans % reader.FULL == 0 or not (cover and map and radius and cover.map == map
		and cover.radius == radius and cover.turning == turning and cover.shape == shape and not (turning and not facing))
	local points, checks = grid, {}
	if not full then
		local half = width / 2
		-- (x, y) sur la minimap était-il dans ce que le balayage précédent a vu ? À un demi-pas de grille en
		-- deçà du bord de la minimap d'alors, quelle que soit sa forme
		local function Seen(x, y)
			local dx, dy = x - half, y - half
			local yards = math.sqrt(dx * dx + dy * dy) / half * radius
			local way = math.atan2(dx, dy)
			if turning then way = way - facing end
			local east = yards * math.sin(way) + (px - cover.x) * wide
			local north = yards * math.cos(way) + (cover.y - py) * tall
			-- (là où il était sur la minimap d'alors)
			local old = math.atan2(east, north)
			if cover.turning then old = old + cover.facing end
			local units = math.sqrt(east * east + north * north) / cover.radius * half
			return reader.Depth(units * math.sin(old), units * math.cos(old), half) >= STEP / 2
		end
		-- (un nœud dont un voisin du même nom répond aussi en son milieu ne se vérifie pas d'un seul point :
		-- il y répondrait encore, cueilli)
		local again = {}
		for _, marker in ipairs(markers) do
			if marker.map == map and not marker.held and not marker.far and on and on[marker.node.kind] then
				local crowded = false
				for _, other in ipairs(markers) do
					if other ~= marker and other.name == marker.name and (other.x - marker.x) ^ 2 + (other.y - marker.y) ^ 2 < (Radius(other) + 1) ^ 2 then
						crowded = true
					end
				end
				if marker.worth >= FITTED and not crowded and Seen(marker.x, marker.y) then checks[#checks + 1] = marker else again[#again + 1] = marker end
			end
		end
		points = {}
		for _, key in ipairs(grid) do
			local x, y = key % ROW * STEP, math.floor(key / ROW) * STEP
			local keep = not Seen(x, y)
			for _, marker in ipairs(again) do
				if keep then break end
				keep = (marker.x - x) ^ 2 + (marker.y - y) ^ 2 <= (Radius(marker) + STEP) ^ 2
			end
			if keep then points[#points + 1] = key end
		end
	end
	scan = { hits = {}, probes = probes, started = GetTime(), looked = 0, points = points, checks = checks, gone = {}, full = full,
		view = { map = map, x = px, y = py, wide = wide, tall = tall, radius = radius, turning = turning, facing = facing, shape = shape } }
	scan.co = coroutine.create(Run)
	reader.due, reader.full = nil, nil
	reader.Begin(scan.co)
end

-- Le balayage en cours s'arrête là, la minimap rendue et les nœuds tels qu'ils étaient ; il reprendra
function reader.Stop(why)
	reader.End()
	scan, wait, reader.due = nil, reader.RETRY, true
	reader.aborts, reader.stopped = reader.aborts + 1, why
end

local function OnUpdate(_, elapsed)
	if turn.muted and GetTime() >= turn.muted then turn.Unmute() end
	if scan then
		local why = reader.Check()
		if why == "window" or why == "camera" then why = reader.Wait(why) end
		if why == "wait" then
			-- (la minimap attend chez elle, cachée : rien ne se lit)
		elseif why then
			reader.Stop(why)
		else
			reader.Resume()
			reader.Copy()
			local co = scan.co
			local ok, problem = coroutine.resume(co)
			if not ok then
				-- le jeu refuse : on n'insiste pas, et /lueur scan dit pourquoi
				reader.End()
				broken, scan = tostring(problem), nil
				ns.UpdateNodes()
				if ns.Refresh then ns.Refresh() end -- Menu.lua : la page de la minimap se grise
				return
			end
			if coroutine.status(co) == "dead" then reader.End() end
		end
	else
		reader.Settle()
		wait = wait - elapsed
		if wait <= 0 then StartScan() end
	end
	Follow(elapsed)
end

---------------------------------------------------------------------------
-- Infobulle de la minimap
---------------------------------------------------------------------------

-- La souris sur un nœud que la compétence du joueur ne permet pas de récolter : sous son nom,
-- ce qu'il demande, écrit comme le jeu l'écrit pour un objet inutilisable
local function OnTooltip(tooltip, data)
	if not (ns.db and ns.db.enabled) or IsSecret(data) or type(data) ~= "table" then return end
	local lines = data.lines
	if IsSecret(lines) or type(lines) ~= "table" then return end
	local said
	for _, line in ipairs(lines) do
		local text = line.leftText
		if not IsSecret(text) and type(text) == "string" then
			for _, entry in ipairs(Names(text)) do
				local node = ns.NodeOf(entry.name)
				local needs = node and Wanted(node.kind) and ns.NodeRequirement(node)
				if needs and not (said and said[needs]) then
					said = said or {}
					said[needs] = true
					pcall(tooltip.AddLine, tooltip, needs, ns.DifficultyColor("impossible"))
				end
			end
		end
	end
end

local function HookTooltip()
	if hooked then return end
	local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover
	if kind and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, kind, OnTooltip)
	end
end

---------------------------------------------------------------------------
-- Liens avec Lueur.lua et avec le jeu
---------------------------------------------------------------------------

-- Appelée par Lueur.lua quand la taille ou l'anneau des icônes change : sans relire la minimap
function ns.RedrawNodes()
	Draw()
end

-- Appelée par Lueur.lua quand un réglage des icônes change, et quand Lueur s'allume ou s'éteint :
-- lance ou arrête le balayage, qui repart de zéro
function ns.UpdateNodes()
	if not ns.db then return end
	local on = ns.db.enabled and (Wanted("herb") or Wanted("ore")) and not Failure()
	if scan then reader.End() end
	scan, wait, slow, reader.due, reader.cover = nil, 0, 1, true, nil
	turn.map, turn.kind, turn.want = nil, nil, nil
	if on then
		if not holder then
			holder = CreateFrame("Frame", nil, Minimap)
			holder:SetAllPoints(Minimap)
		end
		HookTooltip()
		-- sans alternance, plus rien ne justifie de garder les nœuds d'un pistage éteint
		if not ns.GetOption("nodeSwitch") then
			for index = #markers, 1, -1 do
				if markers[index].held then Free(table.remove(markers, index)) end
			end
		end
	else
		Clear()
		reader.Settle(true)
	end
	driver:SetScript("OnUpdate", on and OnUpdate or nil)
	Draw()
end

local handlers = {}

function handlers.PLAYER_LOGIN()
	reader.Restore() -- la taille des points du jeu, si le jeu s'est arrêté pendant un balayage
	ns.UpdateNodes()
	if ns.FarRestore then ns.FarRestore() end -- prototype de la lueur au loin : le repère du joueur, s'il ne lui a pas été rendu
end

-- Un écran de chargement : le joueur est peut-être ailleurs
function handlers.PLAYER_ENTERING_WORLD()
	if scan then reader.End() end
	scan, wait, slow, reader.due, reader.cover = nil, 0, 1, true, nil
	Clear()
end

-- Le joueur s'en va pendant un balayage : la taille des points du jeu lui est rendue
function handlers.PLAYER_LOGOUT()
	if scan then reader.End() end
	reader.Settle(true)
	turn.Unmute() -- (un son coupé le reste jusqu'à ce qu'on le rende, même d'une session à l'autre)
end

-- Un combat commence : un balayage qui tient la souris d'un cadre protégé s'arrête pendant qu'il peut
-- encore la lui rendre (le jeu prévient avant d'interdire d'y toucher)
function handlers.PLAYER_REGEN_DISABLED()
	if scan and reader.s and reader.s.protected then reader.Stop("combat") end
end

-- Et ce qui n'a pu être rendu l'est à la fin du combat
function handlers.PLAYER_REGEN_ENABLED()
	reader.Later()
end

-- Le joueur se met en route, zoome la minimap ou change de pistage : le prochain balayage ne tarde pas
local function Hurry(delay)
	slow = 1
	if wait > delay then wait = delay end
end

function handlers.PLAYER_STARTED_MOVING() Hurry(WAIT) end
function handlers.MINIMAP_UPDATE_ZOOM()
	reader.due = true
	Hurry(WAIT)
end
function handlers.MINIMAP_UPDATE_TRACKING()
	-- (les points du jeu ne sont plus les mêmes : ce que le balayage précédent a vu ne vaut plus)
	turn.changed, reader.due, reader.cover = GetTime(), true, nil
	Hurry(SWITCH_WAIT)
end

function handlers.LOOT_OPENED()
	looting = true
end

-- Le butin se referme. Si c'était celui d'un nœud, son point du jeu va disparaître : on balaie
-- sans attendre. Et l'icône gardée d'un pistage éteint, que nul balayage ne verra partir avant
-- son tour, s'en va tout de suite.
function handlers.LOOT_CLOSED()
	looting, refit, pickedAt = false, true, GetTime()
	local kind = ns.LastNodeKind(PICK_TIME)
	if not kind then return end
	-- Un balayage cache la minimap : plutôt que d'en lancer un après chaque récolte, l'icône du nœud
	-- de ce métier le plus proche du joueur s'en va sur-le-champ, et le balayage suivant fera le reste.
	local nearest
	for index = #markers, 1, -1 do
		local marker = markers[index]
		if marker.node.kind == kind and marker.yards and marker.yards <= PICK_REACH then
			if marker.held then
				Fade(table.remove(markers, index))
			elseif not nearest or marker.yards < nearest.yards then
				nearest = marker
			end
		end
	end
	if not nearest or scan then return end
	for index, marker in ipairs(markers) do
		if marker == nearest then
			Fade(table.remove(markers, index))
			break
		end
	end
end

-- Le client vient de charger un objet : une plante dont le nom était inconnu a peut-être maintenant
-- son image (Nodes.lua a complété son index d'abord, ses événements passant avant). Sans attendre le
-- balayage suivant, qui peut tarder : il n'a lieu qu'après quelques dizaines de mètres.
function handlers.GET_ITEM_INFO_RECEIVED()
	local changed = false
	for _, marker in ipairs(markers) do
		local node = ns.NodeOf(marker.name)
		if node and node ~= marker.node and node.kind == marker.node.kind then
			marker.node, changed = node, true
		end
	end
	if changed then Draw() end
end

-- La compétence a changé : les couleurs aussi, peut-être
function handlers.SKILL_LINES_CHANGED()
	ns.ForgetSkills()
	Draw()
end

driver:SetScript("OnEvent", function(_, event)
	if ns.db then handlers[event]() end
end)
for event in pairs(handlers) do
	pcall(driver.RegisterEvent, driver, event)
end

---------------------------------------------------------------------------
-- Diagnostic (/lueur scan)
---------------------------------------------------------------------------

local function SkillText(kind)
	local skill = ns.GatherSkill(kind)
	if not skill then return "?" end
	return skill.total == skill.rank and tostring(skill.rank) or ("%d (%d)"):format(skill.total, skill.rank)
end

-- Les champs d'une table du jeu, sauf ceux de `skip` : « nom = valeur », triés. Pour voir ce que le
-- jeu dit d'un point de la minimap en plus de son nom.
local function Fields(value, skip)
	local parts = {}
	for key, item in pairs(value) do
		if not skip[key] then
			local text = "?"
			if not IsSecret(item) then text = type(item) == "table" and "{…}" or tostring(item) end
			parts[#parts + 1] = tostring(key) .. " = " .. text
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local TEXT_FIELDS = { lines = true, leftText = true, leftColor = true, rightColor = true, args = true }
local SCAN_LINES = 12     -- icônes que /lueur scan détaille

-- Ce que l'infobulle de la minimap dit sous la vraie souris, tel que le jeu l'écrit ; et tout ce que
-- ses données portent d'autre que ce texte. Le jeu ne documente pas ces données : s'il y glissait
-- un identifiant du point, c'est là qu'il se verrait. (Le jeu ne répond que si la vraie souris est
-- sur la minimap : /lueur scan lancé d'une touche ou d'une macro, le pointeur sur un point.)
local function UnderPointer()
	if InCombatLockdown() or scan then return nil end
	local texts, others = {}, {}
	pcall(function()
		local data = SafeCall(C_TooltipInfo.GetMinimapMouseover)
		local lines = type(data) == "table" and data.lines
		if IsSecret(lines) or type(lines) ~= "table" then return end
		others[1] = Fields(data, TEXT_FIELDS)
		for index, line in ipairs(lines) do
			local text = line.leftText
			if not IsSecret(text) and type(text) == "string" then
				texts[#texts + 1] = (text:gsub("|", "||"):gsub("\n", " / "))
			end
			local more = Fields(line, TEXT_FIELDS)
			if type(line.args) == "table" then
				for _, arg in ipairs(line.args) do
					if type(arg) == "table" then more = more .. (more ~= "" and ", " or "") .. "args { " .. Fields(arg, {}) .. " }" end
				end
			end
			if more ~= "" then others[#others + 1] = ("%d { %s }"):format(index, more) end
		end
	end)
	if not texts[1] then return nil end
	return table.concat(texts, " // "), table.concat(others, " ; ")
end

-- Les « vignettes » du jeu : des objets de la minimap qui ont, eux, un identifiant et une place sur
-- la carte. Rien ne dit que les plantes et les filons en soient ; leur nombre et leurs noms le diront.
local function Vignettes()
	if not (C_VignetteInfo and C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignetteInfo) then return "?" end
	local guids = SafeCall(C_VignetteInfo.GetVignettes)
	if type(guids) ~= "table" then return "?" end
	local names = {}
	for index = 1, math.min(#guids, 8) do
		local info = SafeCall(C_VignetteInfo.GetVignetteInfo, guids[index])
		local name = type(info) == "table" and info.name
		names[#names + 1] = (not IsSecret(name) and type(name) == "string") and name or "?"
	end
	return #guids .. (names[1] and " : " .. table.concat(names, ", ") or "")
end

function ns.ScanReport()
	local failure = ns.NodesFailure()
	ns.Print(L.SCAN_HEADER:format(failure or L.SCAN_READY))
	if broken then print("  " .. broken) end
	if failure then return end
	local finders = {}
	for index = 1, SafeCall(C_Minimap.GetNumTrackingTypes) or 0 do
		local info = SafeCall(C_Minimap.GetTrackingInfo, index)
		if type(info) == "table" and not IsSecret(info.spellID) and FINDERS[info.spellID or 0] then
			finders[#finders + 1] = L.SETTING:format(("%s (%s)"):format(tostring(info.name), tostring(info.spellID)),
				ns.Flag(not IsSecret(info.active) and info.active == true))
		end
	end
	print("  " .. L.SCAN_TRACKING:format(#finders > 0 and table.concat(finders, ", ") or L.NAME_NONE))
	ns.ForgetSkills()
	print("  " .. L.SCAN_SKILL:format(SkillText("herb"), SkillText("ore")))
	local radius, turning = View()
	print("  " .. L.SCAN_VIEW:format(radius and ("%.0f"):format(radius) or "?", ns.Flag(turning), ns.Flag(MapPosition() ~= nil),
		("%s %.1f%s, %s %.1f%s"):format(L.NAME_HERB, reaches.herb.value, reaches.herb.measured and "" or " ?",
			L.NAME_ORE, reaches.ore.value, reaches.ore.measured and "" or " ?")))
	print("  " .. L.SCAN_TWICE:format(Doubled() and L.YES or L.STATUS_NOT_YET))
	-- comment chaque nœud connu a été placé, et ce qu'a coûté le dernier balayage
	local exact, fitted, rough, held, missed = 0, 0, 0, 0, 0
	for _, marker in ipairs(markers) do
		if marker.held then held = held + 1
		elseif (marker.missed or 0) > 0 then missed = missed + 1
		elseif marker.worth == SURE then exact = exact + 1
		elseif marker.worth == FITTED then fitted = fitted + 1
		else rough = rough + 1 end
	end
	print("  " .. L.SCAN_PLACED:format(exact, fitted, rough, held, missed, last.points or 0, last.seconds or 0, last.jobs or 0))
	-- comment la minimap passe sous la souris : ce qu'a coûté le dernier balayage, ce qui l'interrompt
	local function Why(code) return code and L["SCAN_WHY_" .. code:upper()] or L.NAME_NONE end
	print("  " .. L.SCAN_READER:format(last.frames or 0, last.grid or 0, last.full and L.SCAN_FULL or "", last.checks or 0,
		last.measured or 0, last.again or 0, reader.aborts, Why(reader.stopped), Why(not scan and reader.Ready() or nil), reader.resets or 0))
	local quarters = reader.Quarters()
	local shape = quarters.height < 1 and ("%s %d%%"):format(quarters.name, Round(quarters.height * 100)) or quarters.name
	local masked = reader.masked
	if masked == nil then masked = reader.canMask ~= false and Minimap.SetMaskTexture ~= nil end
	print("  " .. L.SCAN_HIDE:format(masked and L.SCAN_BY_MASK or L.SCAN_BY_ALPHA, shape, reader.hidden or 0, reader.shown or 0))
	-- puis les icônes une à une, les plus proches du joueur d'abord : deux icônes pour un seul nœud
	-- se voient à leurs places, et le rayon lu pour chacune dit si les points du jeu ont tous le même
	local half, near = Minimap:GetWidth() / 2, {}
	for _, marker in ipairs(markers) do near[#near + 1] = marker end
	table.sort(near, function(a, b) return (a.x - half) ^ 2 + (a.y - half) ^ 2 < (b.x - half) ^ 2 + (b.y - half) ^ 2 end)
	for index = 1, math.min(#near, SCAN_LINES) do
		local marker = near[index]
		local how = marker.held and L.SCAN_HOW_HELD or (marker.missed or 0) > 0 and L.SCAN_HOW_MISSED
			or marker.worth == SURE and L.SCAN_HOW_EXACT or marker.worth == FITTED and L.SCAN_HOW_CLUSTER or L.SCAN_HOW_ROUGH
		print("    " .. L.SCAN_NODE:format(marker.name, how, marker.reach and ("%.1f"):format(marker.reach) or "?", marker.x - half, marker.y - half))
	end
	local names = {}
	for name in pairs(lastNames) do names[#names + 1] = name end
	table.sort(names)
	print("  " .. L.SCAN_FOUND:format(#names, #markers))
	for _, name in ipairs(names) do
		local node = ns.NodeOf(name)
		local text = L.SCAN_NOT_NODE
		if node then
			text = L["NAME_" .. node.kind:upper()]
			if node.skill then text = text .. L.SCAN_NEEDS:format(node.skill) end
			if lastNames[name].gray then text = text .. L.SCAN_CAVE end
		end
		print(("    %s → %s"):format(name, text))
	end
	print("  " .. L.SCAN_VIGNETTES:format(Vignettes()))
	local text, others = UnderPointer()
	if text then print("  " .. L.SCAN_DATA:format(others)) end
	print("  " .. L.SCAN_POINTER:format(text or L.SCAN_NOTHING))
end

-- /lueur scan now : un balayage de toute la minimap, dès qu'elle peut passer sous la souris
function ns.ScanNow()
	local failure = ns.NodesFailure()
	if failure then return L.MSG_NODES_UNAVAILABLE:format(failure) end
	if scan then return L.SCAN_BUSY end
	reader.due, reader.full, wait = true, true, 0
	return L.SCAN_SOON
end

---------------------------------------------------------------------------
-- Lueur au loin (prototype, 2026-10-22) : /lueur scan far
---------------------------------------------------------------------------
-- Au-delà de ce que le jeu désigne (une quinzaine de mètres), la lueur se pose sur le nœud de la
-- minimap qui est droit devant le joueur. Un addon ne sait pas où un point du monde tombe à l'écran,
-- sauf par la nameplate de la cible et par le marqueur de navigation du repère de carte : le repère
-- du joueur est donc posé sur ce nœud, le marqueur du jeu masqué, et la lueur s'accroche à sa place,
-- d'autant plus petite que le nœud est loin. L'idée vient des étincelles lointaines de NodeSight
-- 1.4.1 ; le code est celui de Lueur. Le marqueur est dessiné à la hauteur du joueur quelle que soit
-- l'altitude donnée au repère (sondé le 2026-10-22) : en pente, la lueur flotte au-dessus ou sous le
-- nœud, et c'est ce que le prototype doit montrer en jeu. Le repère, la quête suivie et le réglage
-- de navigation du joueur lui sont rendus quand la lueur s'en va (db.farRestore, repris au
-- chargement suivant si le jeu s'est arrêté avant). Éteint par défaut (db.farGlow) ; Lueur.lua ne le
-- connaît que par ns.FarGlow, demandé quand le jeu ne désigne rien que Lueur éclaire.
-- Seconde version, après le premier essai en jeu : la place du nœud éclairé est mesurée à part, et
-- moyennée (far.Measure) ; le repère ne bouge que d'au moins far.MOVE ; un repère du joueur n'est
-- jamais pris, et s'il en pose un ou suit autre chose, la lueur au loin lui cède (far.Check, far.Yield).

local far = {
	asked = 0,                        -- quand Lueur.lua a demandé la lueur au loin pour la dernière fois
	MIN = 6, MAX = 100,               -- mètres : en deçà, c'est au jeu de désigner le nœud ; au-delà, trop loin
	CONE = math.rad(25),              -- un nœud n'est pris que dans ce cône devant le joueur,
	KEEP = math.rad(40),              -- et gardé tant qu'il est dans celui-ci
	GAIN = 5,                         -- mètres : un autre nœud ne prend sa place que s'il est plus près d'autant
	NEAR = 15,                        -- mètres : la lueur y a sa taille ordinaire, et rétrécit au-delà
	SMALLEST = 0.25,                  -- jusqu'à cette part de sa taille
	LINGER = 0.4,                     -- secondes sans demande de Lueur.lua au bout desquelles elle s'en va
}

-- Rend au joueur son repère, sa quête suivie et son réglage de navigation. Ni en combat ni carte du
-- monde ouverte : la carte construirait le cadre du repère sous la souillure de l'addon. Réessayé ensuite.
function far.Restore()
	local keep = ns.db and ns.db.farRestore
	if not keep or InCombatLockdown() or (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	-- `kept` : le joueur a posé son propre repère entre-temps (far.Yield), il le garde
	if C_Map and not keep.kept then
		if keep.pin and UiMapPoint then
			pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(keep.pin.map, keep.pin.x, keep.pin.y, keep.pin.z))
		else
			pcall(C_Map.ClearUserWaypoint)
		end
	end
	if C_SuperTrack and not keep.kept then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, keep.tracking == true)
		if keep.quest and keep.quest ~= 0 then pcall(C_SuperTrack.SetSuperTrackedQuestID, keep.quest) end
	end
	if keep.nav ~= nil then pcall(C_CVar.SetCVar, "showInGameNavigation", keep.nav) end
	ns.db.farRestore = nil
end
ns.FarRestore = far.Restore

-- Met de côté ce qui sera rendu, une seule fois tant que la lueur au loin tient le repère
function far.Take()
	if ns.db.farRestore then return end
	local pin = SafeCall(C_Map.GetUserWaypoint)
	local keep = { tracking = SafeCall(C_SuperTrack.IsSuperTrackingUserWaypoint) == true,
		quest = SafeCall(C_SuperTrack.GetSuperTrackedQuestID), nav = C_CVar and SafeCall(C_CVar.GetCVar, "showInGameNavigation") }
	if SafeCall(C_Map.HasUserWaypoint) == true and type(pin) == "table" and type(pin.position) == "table" then
		keep.pin = { map = pin.uiMapID, x = pin.position.x, y = pin.position.y, z = pin.z }
	end
	ns.db.farRestore = keep
	if keep.nav ~= "1" then pcall(C_CVar.SetCVar, "showInGameNavigation", "1") end
end

-- Le marqueur du jeu s'efface tant que la lueur le remplace, et tant que le repère n'est pas rendu :
-- Blizzard lui redonne son opacité à chaque image (SuperTrackedFrame:UpdateAlpha), on la lui retire
-- juste après
function far.Mask()
	if far.masked or not (SuperTrackedFrame and SuperTrackedFrame.UpdateAlpha and hooksecurefunc) then return end
	far.masked = true
	hooksecurefunc(SuperTrackedFrame, "UpdateAlpha", function(frame)
		if far.node or (ns.db and ns.db.farRestore and ns.db.farRestore.placed) then frame:SetAlpha(0) end
	end)
end

-- Le nœud à éclairer : le plus proche dans le cône devant le joueur, parmi ceux que la minimap
-- montre et que le joueur peut récolter. Celui qui l'est déjà le reste tant qu'il est devant, sauf
-- si un autre est nettement plus près.
function far.Pick()
	local map, x, y, wide, tall = MapPosition()
	local facing = GetPlayerFacing and SafeCall(GetPlayerFacing)
	if not map or type(facing) ~= "number" then return nil end
	local best, bestYards, kept
	for _, marker in ipairs(markers) do
		local node = marker.node
		if node and marker.map == map and marker.mx and not marker.held and not marker.lost and Wanted(node.kind)
			and ns.IsCategoryShown(node.kind) and ns.NodeDifficulty(node) ~= "impossible" then
			local east, north = (marker.mx - x) * wide, (y - marker.my) * tall
			local yards = math.sqrt(east * east + north * north)
			if yards >= far.MIN and yards <= far.MAX then
				-- écart avec la direction du regard : l'orientation se compte dans l'autre sens que le cap
				local off = math.abs((math.atan2(east, north) + facing + math.pi) % (2 * math.pi) - math.pi)
				if marker == far.node and off <= far.KEEP then kept = yards end
				if off <= far.CONE and (not bestYards or yards < bestYards) then best, bestYards = marker, yards end
			end
		end
	end
	if kept and not (best and best ~= far.node and bestYards < kept - far.GAIN) then return far.node end
	return best
end

-- Le marqueur flotte au-dessus du nœud (vu en jeu le 2026-10-22, premier essai) : la lueur descend
-- de `db.farDrop` mètres, réglable le temps du prototype (/lueur scan far <mètres>). Une hauteur
-- donnée prend à l'écran f / D unités par mètre, f la focale et D la distance de la caméra à l'objet,
-- que l'on prend pour la distance du nœud plus le zoom. Le cadre étant à l'échelle (NEAR + zoom) / D,
-- la descente s'y compte en f / (NEAR + zoom) unités par mètre, quelle que soit la distance.
far.DROP = 1.5

function far.Focal()
	-- cameraFov pris pour l'angle horizontal, comme NodeSight : à vérifier
	local wide, tall = UIParent:GetWidth(), UIParent:GetHeight()
	local fov = math.rad(tonumber(C_CVar and SafeCall(C_CVar.GetCVar, "cameraFov")) or 90)
	local vertical = 2 * math.atan(math.tan(fov / 2) * tall / wide)
	return tall / 2 / math.tan(vertical / 2)
end

-- Accroche le cadre que la lueur prend pour nameplate au marqueur du jeu, à l'échelle de la distance.
-- La lueur se pose à `offsetY` sous sa nameplate : le cadre se met d'autant au-dessus du point visé,
-- et la lueur tombe sur lui. Marqueur hors de l'écran ou pas encore là : le cadre se cache, sans
-- que la lueur le quitte, pour ne pas relancer son arrivée à chaque hoquet du jeu.
function far.Follow()
	local anchor = far.anchor
	if not anchor then
		anchor = CreateFrame("Frame", nil, UIParent)
		anchor:SetFrameStrata("BACKGROUND")
		anchor:SetSize(1, 1)
		far.anchor = anchor
	end
	local nav = SafeCall(C_Navigation.GetFrame)
	if not nav or SafeCall(C_Navigation.HasValidScreenPosition) ~= true or SafeCall(C_Navigation.WasClampedToScreen) == true then
		anchor:Hide()
		return
	end
	-- pendant qu'on cherche la hauteur du nœud, le marqueur saute d'une altitude à l'autre : rien ne s'y montre
	if far.pin then
		anchor:Hide()
		return
	end
	local zoom = GetCameraZoom and SafeCall(GetCameraZoom)
	if type(zoom) ~= "number" then zoom = 0 end
	-- un repère posé à la hauteur du sol (far.Pinpoint) n'a plus à descendre
	local height = far.heights[far.node]
	local drop = (height and height.z and far.PIN_DROP or ns.db.farDrop or far.DROP) * far.Focal() / (far.NEAR + zoom)
	local offset = (ns.GetOption("offsetY", far.node.node.kind) or 0) + drop
	if far.nav ~= nav or far.offset ~= offset then
		anchor:ClearAllPoints()
		if not pcall(anchor.SetPoint, anchor, "CENTER", nav, "CENTER", 0, -offset) then
			anchor:Hide()
			return
		end
		far.nav, far.offset = nav, offset
	end
	local yards = SafeCall(C_Navigation.GetDistance)
	local size = 1
	if type(yards) == "number" and yards > 0 then size = math.max(far.SMALLEST, math.min(1, (far.NEAR + zoom) / (yards + zoom))) end
	anchor:SetScale(size)
	anchor:Show()
end

function far.Stop()
	far.node, far.samples, far.pin = nil, nil, nil
	far.Restore()
end

-- Le joueur a repris la main : il a posé, déplacé ou retiré un repère, ou suivi autre chose. Ce
-- qu'il vient de choisir l'emporte sur ce qui lui aurait été rendu ; la lueur au loin attend un
-- moment avant de reprendre, et ne prend jamais un repère qui est le sien (FarGlow).
function far.Yield(reason)
	local keep = ns.db.farRestore
	if keep then
		keep.placed = nil
		if reason == "waypoint" then
			-- son nouveau repère reste ; sa quête suivie aussi, il la retrouvera en retirant le repère
			ns.db.farRestore = { nav = keep.nav, kept = true }
		else
			keep.tracking, keep.quest = nil, nil
		end
	end
	far.yielded, far.yieldReason = GetTime(), reason
	far.node, far.samples, far.pin = nil, nil, nil
	far.Restore()
end

-- Le repère est-il encore celui que la lueur a posé ? Sinon, le joueur l'a changé.
function far.Check()
	local keep = ns.db.farRestore
	local placed = keep and keep.placed
	if not placed then return end
	if SafeCall(C_Map.HasUserWaypoint) ~= true then return far.Yield("waypoint") end
	local pin = SafeCall(C_Map.GetUserWaypoint)
	if type(pin) ~= "table" or type(pin.position) ~= "table" or pin.uiMapID ~= placed.map
		or math.abs((pin.position.x or 0) - placed.x) > 1e-5 or math.abs((pin.position.y or 0) - placed.y) > 1e-5 then
		return far.Yield("waypoint")
	end
	if SafeCall(C_SuperTrack.IsSuperTrackingUserWaypoint) == false then return far.Yield("tracking") end
end

-- La flèche que le jeu met devant le nom d'un nœud plus haut ou plus bas que le joueur, telle quelle
-- (les coordonnées de Minimap-PositionArrows, qui disent laquelle), « none » sans flèche, nil si le
-- nom n'est pas là. Rien n'en est encore tiré : /lueur scan far status la montre, pour voir en jeu ce
-- qu'elle vaut.
function far.Arrow(name, x, y)
	Minimap:UpdateMouseoverAtPoint((left + x) * scale, (bottom + y) * scale)
	local data = SafeCall(C_TooltipInfo.GetMinimapMouseover)
	local lines = type(data) == "table" and data.lines
	if IsSecret(lines) or type(lines) ~= "table" then return nil end
	for _, line in ipairs(lines) do
		local text = line.leftText
		if not IsSecret(text) and type(text) == "string" then
			for row in text:gmatch("[^\n]+") do
				if row:find(name, 1, true) then return row:match("PositionArrows([^|]*)|t") or "none" end
			end
		end
	end
	return nil
end

-- Place précise du nœud éclairé, mesurée à part : ses quatre bords cherchés par dichotomie depuis sa
-- place connue, comme Refine le fait d'un nœud seul. Le balayage place un nœud à une unité près,
-- quelque 2,4 m quand la minimap montre 233 m ; les mesures, faites tandis que le joueur bouge,
-- tombent chaque fois autrement sur la grille des pixels, et leur moyenne sur la carte gagne d'autant.
function far.Measure()
	local marker = far.node
	if not (marker and marker.x and marker.name) or InCombatLockdown() or not Minimap:IsVisible() or Minimap:IsMouseOver() then return end
	local map, px, py, wide, tall = MapPosition()
	local radius, turning, facing = View()
	if not map or map ~= marker.map or not radius or (turning and not facing) then return end
	left, bottom, scale, width = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetEffectiveScale(), Minimap:GetWidth()
	if not (left and bottom and scale and width) then return end
	local half, name, x, y = width / 2, marker.name, marker.x, marker.y
	local found, arrow
	pcall(function()
		Minimap:SetUsingSoftCursor(true)
		if not Under(name, x, y) then return end
		local east, west = Edge(name, x, y, 1, 0, 30), Edge(name, x, y, -1, 0, 30)
		if not (east and west) then return end
		x = x + (east - west) / 2
		local north, south = Edge(name, x, y, 0, 1, 30), Edge(name, x, y, 0, -1, 30)
		if not (north and south) then return end
		y = y + (north - south) / 2
		found = true
		arrow = far.Arrow(name, x, y)
	end)
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	if not found then return end
	far.arrow = arrow
	-- de la minimap à la carte : l'inverse de Spot
	local dx, dy = x - half, y - half
	local yards = math.sqrt(dx * dx + dy * dy) / half * radius
	local way = math.atan2(dx, dy)
	if turning then way = way - facing end
	local samples = far.samples or {}
	far.samples = samples
	samples[#samples + 1] = { px + yards * math.sin(way) / wide, py - yards * math.cos(way) / tall }
	if #samples > far.SAMPLES then table.remove(samples, 1) end
	far.wide, far.tall = wide, tall
end

-- Où poser le repère : la moyenne des mesures précises, à défaut la place que le balayage connaît.
-- Le second résultat est l'écart des mesures à leur moyenne (mètres), le plus grand.
function far.Place()
	local samples = far.samples
	if not samples or not samples[1] then return far.node.mx, far.node.my, nil end
	local sx, sy = 0, 0
	for _, sample in ipairs(samples) do sx, sy = sx + sample[1], sy + sample[2] end
	local mx, my, spread = sx / #samples, sy / #samples, 0
	for _, sample in ipairs(samples) do
		spread = math.max(spread, math.sqrt(((sample[1] - mx) * far.wide) ^ 2 + ((sample[2] - my) * far.tall) ^ 2))
	end
	return mx, my, spread
end

-- La hauteur du sol sous le nœud, cherchée avec le repère lui-même (2026-10-22, deuxième essai). La
-- sonde du même jour avait conclu que le jeu ignore l'altitude d'un repère, mais chacun de ses essais
-- reposait le repère à la même place, seule l'altitude changeant, et n'attendait que six images : le
-- jeu a pu tenir le repère pour inchangé, ou n'avoir pas fini de le prendre en compte. Ici chaque
-- essai décale le repère d'un rien (JITTER, quelques millimètres) et attend que le jeu dise la même
-- chose plusieurs images de suite. D'abord deux altitudes extrêmes : si le marqueur ne bouge pas à
-- l'écran entre elles, l'altitude est bien ignorée, et c'est fini. Sinon l'état du marqueur sépare
-- le sol du ciel : caché (Occluded) sous terre, visible (InRange) au-dessus. La plus basse altitude
-- visible se cherche par dichotomie, au mètre près, et le repère y reste. Un arbre ou un rocher entre
-- la caméra et le nœud donne un sol trop haut. Les résultats vont aussi dans db.farPins, pour être lus.
far.heights = setmetatable({}, { __mode = "k" })  -- nœud de la minimap -> { z, result, steps, seconds }
far.PIN_LOW, far.PIN_HIGH, far.PIN_STEP = -500, 1500, 1   -- mètres
-- par essai : secondes d'attente au moins, images de suite pareilles ensuite, secondes au plus. Le premier
-- passage en jeu n'attendait que quatre images : le marqueur était encore caché à +1500 m, le jeu n'avait
-- pas encore pris le repère (2026-10-22).
far.PIN_WAIT, far.PIN_STABLE, far.PIN_LONGEST = 0.5, 6, 2.5
far.PIN_DROP, far.JITTER = 0, 1e-6
-- trois essais en jeu (2026-10-22, 22:29 à 22:41) : l'altitude est ignorée. La recherche ne se fait
-- plus d'elle-même ; /lueur scan far pin la relance sur le nœud éclairé.
far.zIgnored = true

-- l'état du marqueur : caché (sous terre ou derrière le décor), ou visible
function far.Hidden(state)
	local states = Enum and Enum.NavigationState
	return state == (states and states.Occluded or 1)
end

function far.PinPlace(z)
	local pin = far.pin
	pin.z, pin.frames, pin.stable, pin.step, pin.placedAt = z, 0, 0, pin.step + 1, GetTime()
	local x = pin.x + (pin.step % 2 == 0 and far.JITTER or -far.JITTER)
	if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(pin.map, x, pin.y, z)) and ns.db.farRestore and ns.db.farRestore.placed then
		ns.db.farRestore.placed.x = x
	end
	pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
end

function far.PinDone(result)
	local pin = far.pin
	local height = { result = result, steps = pin.step, seconds = math.floor((GetTime() - pin.started) * 10 + 0.5) / 10 }
	if result == "found" then height.z = math.floor(pin.hi * 10 + 0.5) / 10 + 0 end
	if result == "z ignored" then far.zIgnored = true end
	far.heights[pin.node] = height
	far.pin, far.forcePlace = nil, true
	local log = ns.db.farPins or {}
	ns.db.farPins = log
	log[#log + 1] = { at = date and date("%H:%M:%S"), node = pin.node.name, result = result, z = height.z, steps = height.steps,
		seconds = height.seconds, lowY = pin.lowY, highY = pin.highY, lowState = pin.lowState, highState = pin.highState, readings = pin.readings }
	if #log > 20 then table.remove(log, 1) end
	ns.Print(("far glow (prototype): %s, %s%s in %d steps, %.1f s ; marker y %s at %d, %s at %d"):format(pin.node.name, result,
		height.z and (" at z %.1f"):format(height.z) or "", height.steps, height.seconds, tostring(pin.lowY), far.PIN_LOW,
		tostring(pin.highY), far.PIN_HIGH))
end

-- Une lecture finie : ce que dit le jeu à cette altitude décide de la suivante
function far.PinStep(state, y)
	local pin = far.pin
	pin.readings[#pin.readings + 1] = { pin.z, state, y and math.floor(y * 10 + 0.5) / 10 + 0, pin.frames }
	if pin.phase == "low" then
		pin.lowY, pin.lowState, pin.phase = y and math.floor(y * 10 + 0.5) / 10 + 0, state, "high"
		far.PinPlace(far.PIN_HIGH)
	elseif pin.phase == "high" then
		pin.highY, pin.highState = y and math.floor(y * 10 + 0.5) / 10 + 0, state
		if not (pin.lowY and pin.highY) or math.abs(pin.highY - pin.lowY) < 2 then return far.PinDone("z ignored") end
		if not far.Hidden(pin.lowState) or far.Hidden(state) then return far.PinDone("no bracket") end
		pin.lo, pin.hi, pin.phase = far.PIN_LOW, far.PIN_HIGH, "search"
		far.PinPlace((pin.lo + pin.hi) / 2)
	else
		if far.Hidden(state) then pin.lo = pin.z else pin.hi = pin.z end
		if pin.hi - pin.lo <= far.PIN_STEP then return far.PinDone("found") end
		far.PinPlace((pin.lo + pin.hi) / 2)
	end
end

-- À chaque image : on attend que le jeu dise la même chose plusieurs images de suite
function far.Pinpoint()
	local pin = far.pin
	pin.frames = pin.frames + 1
	local state = SafeCall(C_Navigation.GetTargetState)
	local nav, y = SafeCall(C_Navigation.GetFrame), nil
	if nav then
		local ok, _, cy = pcall(nav.GetCenter, nav)
		if ok and not IsSecret(cy) and type(cy) == "number" then y = cy end
	end
	if pin.frames > 1 and state == pin.lastState then pin.stable = pin.stable + 1 else pin.stable = 0 end
	pin.lastState = state
	local waited = GetTime() - pin.placedAt
	if waited < far.PIN_WAIT or (pin.stable < far.PIN_STABLE and waited < far.PIN_LONGEST) then return end
	far.PinStep(state, y)
end

-- /lueur scan far pin : cherche de nouveau, pour le nœud éclairé, même si l'altitude a paru ignorée
function ns.FarRepin()
	far.zIgnored = nil
	if far.node then far.heights[far.node] = nil end
	far.pin, far.forcePlace = nil, true
end

-- Sonde de la hauteur (2026-10-22, après les essais de l'altitude et des valeurs secrètes) : trois
-- propriétés du jeu jamais mesurées.
--   1. Le repère relu (far.Readback) : le jeu y inscrit-il de lui-même une altitude, celle du sol ?
--      Elle se lit dans C_Map.GetUserWaypoint, dans son lien texte et dans le repère tiré de ce lien.
--   2. Le marqueur suit-il le joueur en hauteur, ou garde-t-il celle qu'il avait quand le repère a
--      été posé ? /lueur scan far hold empêche le repère de bouger, et /lueur scan far status dit à
--      quelle hauteur des pieds du joueur le marqueur se trouve (far.Height) : stable pendant qu'il
--      monte une pente, le marqueur le suit ; décroissante, il est resté en place.
--   3. La vraie souris sur le nœud éclairé (WORLD_CURSOR_TOOLTIP_UPDATE, far.Hover) donne sa place à
--      l'écran : comparée au marqueur, elle dit de combien le nœud est plus haut ou plus bas que lui.
-- La hauteur se déduit d'une place à l'écran par la caméra : elle vise un point PIVOT au-dessus des
-- pieds du joueur, depuis zoom mètres derrière lui, inclinée vers le bas de cameraSavedPitch degrés
-- (vu en jeu : la valeur suit la caméra), avec la focale de far.Focal. Le point est supposé droit
-- devant. Les hauteurs absolues dépendent de PIVOT et de la focale, que rien n'a mesurés ; leurs
-- différences, d'un instant à l'autre ou entre le nœud et le marqueur, en dépendent bien moins.
far.PIVOT = 1.8

function far.Round(value) return math.floor(value * 10 + 0.5) / 10 + 0 end

function far.Readback(map)
	far.placements = (far.placements or 0) + 1
	local back = { at = date and date("%H:%M:%S") }
	local pin = SafeCall(C_Map.GetUserWaypoint)
	if type(pin) == "table" then
		back.z = IsSecret(pin.z) and "secret" or pin.z
		local keys = {}
		for key in pairs(pin) do keys[#keys + 1] = tostring(key) end
		table.sort(keys)
		back.fields = table.concat(keys, " ")
	end
	local link = C_Map.GetUserWaypointHyperlink and SafeCall(C_Map.GetUserWaypointHyperlink)
	if type(link) == "string" then
		back.link = (link:gsub("|", "||"))
		local point = C_Map.GetUserWaypointFromHyperlink and SafeCall(C_Map.GetUserWaypointFromHyperlink, link)
		if type(point) == "table" then back.linkZ = IsSecret(point.z) and "secret" or point.z end
	end
	local position = C_Map.GetUserWaypointPositionForMap and SafeCall(C_Map.GetUserWaypointPositionForMap, map)
	if type(position) == "table" then back.forMapZ = IsSecret(position.z) and "secret" or position.z end
	far.readback = back
	local log = ns.db.farProbe or {}
	ns.db.farProbe = log
	log.readback = log.readback or {}
	log.readback[#log.readback + 1] = back
	if #log.readback > 10 then table.remove(log.readback, 1) end
	if (far.readbackSaid or 0) < 3 then
		far.readbackSaid = (far.readbackSaid or 0) + 1
		ns.Print(("far glow (prototype): waypoint read back: z %s ; fields %s ; z from its link %s ; link %s"):format(tostring(back.z),
			tostring(back.fields), tostring(back.linkZ), tostring(back.link)))
	end
end

-- Le marqueur du jeu à l'écran, en hauteur, en unités de l'interface ; nil s'il n'y est pas
function far.MarkerY()
	local nav = SafeCall(C_Navigation.GetFrame)
	if not nav then return nil end
	local ok, _, y = pcall(nav.GetCenter, nav)
	local scale = SafeCall(nav.GetEffectiveScale, nav)
	if not ok or IsSecret(y) or type(y) ~= "number" or type(scale) ~= "number" then return nil end
	return y * scale / UIParent:GetEffectiveScale()
end

-- Distance à plat du joueur au point où le repère est posé (mètres)
function far.Yards()
	local placed = ns.db.farRestore and ns.db.farRestore.placed
	local map, x, y, wide, tall = MapPosition()
	if not placed or map ~= placed.map then return nil end
	return math.sqrt(((placed.x - x) * wide) ^ 2 + ((y - placed.y) * tall) ^ 2)
end

-- Hauteur au-dessus des pieds du joueur d'un point vu à `y` à l'écran, à `yards` mètres devant lui
function far.Height(y, yards)
	local pitch = math.rad(tonumber(C_CVar and SafeCall(C_CVar.GetCVar, "cameraSavedPitch")) or 0)
	local zoom = GetCameraZoom and SafeCall(GetCameraZoom) or 0
	local angle = math.atan((y - UIParent:GetHeight() / 2) / far.Focal()) - pitch
	return far.PIVOT + zoom * math.sin(pitch) + (yards + zoom * math.cos(pitch)) * math.tan(angle)
end

-- La souris passe sur un objet du monde : si c'est le nœud éclairé, sa place à l'écran contre celle du marqueur
function far.Hover()
	if not far.node or not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor and GetCursorPosition) then return end
	local data = SafeCall(C_TooltipInfo.GetWorldCursor)
	local lines = type(data) == "table" and data.lines
	local first = type(lines) == "table" and not IsSecret(lines) and lines[1]
	local name = type(first) == "table" and first.leftText
	if IsSecret(name) or type(name) ~= "string" or name ~= far.node.name then return end
	local _, cursor = GetCursorPosition()
	local markerY, yards = far.MarkerY(), far.Yards()
	if type(cursor) ~= "number" or not (markerY and yards) then return end
	cursor = cursor / UIParent:GetEffectiveScale()
	local node, marker = far.Height(cursor, yards), far.Height(markerY, yards)
	local entry = { at = date and date("%H:%M:%S"), name = name, yards = far.Round(yards), node = far.Round(node), marker = far.Round(marker),
		difference = far.Round(node - marker), pixels = far.Round(cursor - markerY), placements = far.placements, held = far.hold }
	local log = ns.db.farProbe or {}
	ns.db.farProbe = log
	log.hovers = log.hovers or {}
	log.hovers[#log.hovers + 1] = entry
	if #log.hovers > 30 then table.remove(log.hovers, 1) end
	ns.Print(("far glow (prototype): mouse on %s at %.0f yd: node %+.1f yd, marker %+.1f yd from your feet (model) ; node minus marker %+.1f yd, %+.0f px"):format(
		name, yards, node, marker, node - marker, cursor - markerY))
end

-- /lueur scan far hold : le repère ne bouge plus que pour un autre nœud
function ns.FarHold()
	far.hold = not far.hold or nil
	return far.hold and "waypoint held: it moves only for another node" or "waypoint free to follow the measures"
end

-- Appelée par Lueur.lua quand le jeu ne désigne rien que Lueur éclaire : le cadre où poser la lueur,
-- le nom du nœud et sa catégorie, ou nil
function ns.FarGlow()
	if not (ns.db and ns.db.farGlow) or InCombatLockdown() or (WorldMapFrame and WorldMapFrame:IsShown()) then return nil end
	if not (C_Map and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap and C_Map.GetUserWaypoint and UiMapPoint and C_SuperTrack
		and C_SuperTrack.SetSuperTrackedUserWaypoint and C_Navigation and C_Navigation.GetFrame) then
		return nil
	end
	far.asked = GetTime()
	if far.yielded and GetTime() - far.yielded < far.PAUSE then return nil end
	local keep = ns.db.farRestore
	-- un repère du joueur n'est jamais pris : la lueur au loin attend qu'il l'ait retiré
	if not (keep and keep.placed) and SafeCall(C_Map.HasUserWaypoint) == true then
		far.waiting = true
		return nil
	end
	far.waiting = nil
	local node = far.Pick()
	local map = node and MapPosition()
	if not map or SafeCall(C_Map.CanSetUserWaypointOnMap, map) ~= true then
		if far.node then far.Stop() end
		return nil
	end
	if node ~= far.node then far.node, far.samples, far.arrow, far.pin = node, nil, nil, nil end
	-- la hauteur se cherche avec le repère : rien d'autre ne le bouge pendant ce temps
	if far.pin then return far.anchor, node.name, node.node.kind end
	local mx, my = far.Place()
	local placed = keep and keep.placed
	local height = far.heights[node]
	-- le repère ne bouge que pour un autre nœud, ou une place corrigée de plus de MOVE mètres
	-- tenu (/lueur scan far hold) : il ne bouge que pour un autre nœud, le temps de voir si le marqueur suit le joueur
	if far.forcePlace or not placed or placed.node ~= node.name or placed.map ~= map
		or not far.hold and (((mx - placed.x) * (far.wide or 0)) ^ 2 + ((my - placed.y) * (far.tall or 0)) ^ 2 > far.MOVE * far.MOVE
		or not far.wide and (mx ~= placed.x or my ~= placed.y)) then
		far.Take()
		far.Mask()
		far.forcePlace = nil
		if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, mx, my, height and height.z)) then
			ns.db.farRestore.placed = { map = map, x = mx, y = my, node = node.name }
			far.Readback(map)
		end
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
		-- la première fois qu'un nœud est éclairé, sa hauteur se cherche à sa place
		if not height and not far.zIgnored and ns.db.farRestore and ns.db.farRestore.placed then
			far.pin = { node = node, map = map, x = mx, y = my, phase = "low", step = 0, started = GetTime(), readings = {} }
			far.PinPlace(far.PIN_LOW)
		end
	end
	far.Follow()
	return far.anchor, node.name, node.node.kind
end

far.SAMPLES, far.MEASURE, far.MOVE, far.PAUSE = 12, 0.5, 0.5, 30

-- Pour régler et juger la lueur au loin en jeu (/lueur scan far status), en anglais : une ligne
function ns.FarStatus()
	local db = ns.db
	local drop = ("drop %.1f yd"):format(db.farDrop or far.DROP)
	if not db.farGlow then return "off ; " .. drop end
	if far.yielded and GetTime() - far.yielded < far.PAUSE then
		return ("paused %.0f s more: the player changed the %s ; %s"):format(far.PAUSE - (GetTime() - far.yielded), far.yieldReason, drop)
	end
	if far.waiting then return "waiting: the player has a waypoint of their own ; " .. drop end
	if not far.node then return "no node in front ; " .. drop end
	local _, _, spread = far.Place()
	local state = SafeCall(C_Navigation.GetTargetState)
	local height = far.heights[far.node]
	local pinned = far.pin and ("finding its height, step %d"):format(far.pin.step)
		or height and (height.z and ("ground at z %.1f"):format(height.z) or height.result)
		or far.zIgnored and "height ignored by the game" or "height not looked for"
	if height and height.z then drop = ("drop %.1f yd, the waypoint being on the ground"):format(far.PIN_DROP) end
	local markerY, yards = far.MarkerY(), far.Yards()
	local model = markerY and yards and ("%+.1f yd"):format(far.Height(markerY, yards)) or "?"
	return ("%s, %.1f yd away, marker state %s, marker %s from your feet (model) ; waypoint placed %d time(s)%s, read back z %s ; %s ; %s ; %d precise measures, spread %s yd ; arrow %s"):format(
		far.node.name, tonumber(SafeCall(C_Navigation.GetDistance)) or -1, tostring(state), model, far.placements or 0,
		far.hold and " (held)" or "", tostring(far.readback and far.readback.z), pinned, drop, far.samples and #far.samples or 0,
		spread and ("%.1f"):format(spread) or "-", tostring(far.arrow))
end

far.frame = CreateFrame("Frame")
far.frame:SetScript("OnUpdate", function()
	local now = GetTime()
	if far.node then
		-- Lueur.lua ne la demande plus : le jeu désigne quelque chose qu'il éclaire, ou la lueur est éteinte ou suspendue
		if now - far.asked > far.LINGER then
			far.Stop()
			return
		end
		if now - (far.checked or 0) > 0.25 then
			far.checked = now
			far.Check()
			if not far.node then return end
		end
		if far.pin then
			far.Pinpoint()
			return
		end
		if now - (far.measured or 0) > far.MEASURE then
			far.measured = now
			far.Measure()
		end
		far.Follow()
	elseif ns.db and ns.db.farRestore then
		far.Restore()
	end
end)
-- en quittant le jeu, le joueur retrouve son repère
far.frame:SetScript("OnEvent", function(_, event)
	if event == "WORLD_CURSOR_TOOLTIP_UPDATE" then
		pcall(far.Hover)
	else
		far.Restore()
	end
end)
pcall(far.frame.RegisterEvent, far.frame, "PLAYER_LOGOUT")
pcall(far.frame.RegisterEvent, far.frame, "WORLD_CURSOR_TOOLTIP_UPDATE")

---------------------------------------------------------------------------
-- Essai des positions secrètes (prototype, 2026-10-22) : /lueur scan far secret
---------------------------------------------------------------------------
-- ClosestGameObjectPosition(numéro) rend la place (x, y) et la distance de l'objet de ce numéro le
-- plus proche, en valeurs secrètes : un addon ne peut ni les comparer ni calculer avec, seulement les
-- passer aux fonctions d'affichage qui les acceptent, dont StatusBar:SetMinMaxValues et SetValue (« vu
-- en jeu » par BlizzThreatPlates sur UnitHealth). Une barre change sa valeur en longueur à l'écran, et
-- un cadre peut s'ancrer au bout de son remplissage : deux barres invisibles le long de la minimap y
-- posent un point magenta à la place secrète de l'objet, sans que Lueur la lise. Une troisième barre
-- montre la distance secrète (orange) au-dessus de la distance à plat du repère (bleue) : plus longue
-- en pente, elle compterait la hauteur. La fonction ne rend aucune altitude, et un addon ne peut rien
-- calculer sur une valeur secrète (Curve:Evaluate la lui refuse) : l'essai dit seulement ce qu'elle
-- rend pour un filon ou une plante, et si le relais par les barres tient. Minimap fixe seulement.
far.test = {}

function far.Count(...) return select("#", ...), ... end

function far.TestBar(parent, wide, tall, r, g, b)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(wide, tall)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(r, g, b)
	return bar
end

function far.TestBuild()
	local test = far.test
	if test.panel then return end
	-- les barres de la minimap : seul compte le bout de leur remplissage, elles restent invisibles
	test.across = far.TestBar(Minimap, 10, 4, 1, 0, 1)
	test.across:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", 0, 8)
	test.up = far.TestBar(Minimap, 4, 10, 1, 0, 1)
	test.up:SetOrientation("VERTICAL")
	test.up:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMRIGHT", 8, 0)
	test.across:SetAlpha(0)
	test.up:SetAlpha(0)
	test.box = CreateFrame("Frame", nil, Minimap)
	test.box:SetFrameLevel(Minimap:GetFrameLevel() + 20)
	test.dot = test.box:CreateTexture(nil, "OVERLAY")
	test.dot:SetColorTexture(1, 0, 1, 1)
	test.dot:SetSize(5, 5)
	test.dot:SetPoint("CENTER", test.box, "BOTTOMLEFT", 0, 0)
	-- les distances, en haut de l'écran
	local panel = CreateFrame("Frame", nil, UIParent)
	panel:SetSize(320, 64)
	panel:SetPoint("TOP", UIParent, "TOP", 0, -110)
	local back = panel:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.6)
	test.panel = panel
	test.secret = far.TestBar(panel, 300, 10, 1, 0.5, 0)
	test.secret:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -26)
	test.secret:SetMinMaxValues(0, 120)
	test.flat = far.TestBar(panel, 300, 10, 0.3, 0.6, 1)
	test.flat:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -42)
	test.flat:SetMinMaxValues(0, 120)
	test.text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	test.text:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
	test.text:SetWidth(304)
	test.text:SetJustifyH("LEFT")
end

-- Quelle valeur de UnitPosition suit l'est, laquelle le nord, et dans quel sens : lu sans secret, de
-- la carte au monde (C_Map.GetWorldPosFromMapPos) puis en comparant au joueur. ClosestGameObjectPosition
-- rend sans doute ses valeurs dans le même ordre que UnitPosition : le point le dira.
function far.TestAxes(map, px, py)
	if not (C_Map.GetWorldPosFromMapPos and CreateVector2D and UnitPosition) then return nil end
	local function World(x, y)
		local ok, _, position = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
		if ok and type(position) == "table" and not IsSecret(position.x) and type(position.x) == "number" then return position.x, position.y end
	end
	local x0, y0 = World(px, py)
	local xe, ye = World(px + 0.001, py)
	local xn, yn = World(px, py - 0.001)
	local ok, a, b = pcall(UnitPosition, "player")
	if not (x0 and xe and xn and ok) or IsSecret(a) or type(a) ~= "number" then return nil end
	-- l'ordre de UnitPosition : (x, y) du monde, ou l'inverse
	local swap = math.abs(a - y0) + math.abs(b - x0) < math.abs(a - x0) + math.abs(b - y0)
	local function Axis(dx, dy)
		local index = math.abs(dx) > math.abs(dy) and 1 or 2
		local sign = (index == 1 and dx or dy) > 0 and 1 or -1
		if swap then index = 3 - index end
		return { index, sign }
	end
	return { east = Axis(xe - x0, ye - y0), north = Axis(xn - x0, yn - y0), swap = swap,
		world = { math.floor(x0 * 10 + 0.5) / 10 + 0, math.floor(y0 * 10 + 0.5) / 10 + 0 },
		unit = { math.floor(a * 10 + 0.5) / 10 + 0, math.floor(b * 10 + 0.5) / 10 + 0 } }
end

-- À chaque image, tant que l'essai est montré
function far.TestUpdate()
	local test = far.test
	local node = far.node
	local ids = node and node.node and node.node.ids
	if not (ids and ids[1]) then
		test.text:SetText(node and (node.name .. ": no object number known for it") or "no node lit by the far glow")
		test.box:Hide()
		return
	end
	local count, ok, x, y, distance, id = 0, false, nil, nil, nil, nil
	for _, candidate in ipairs(ids) do
		local n, answered, a, b, d = far.Count(pcall(ClosestGameObjectPosition, candidate))
		if answered and n >= 4 then
			ok, x, y, distance, id, count = true, a, b, d, candidate, n - 1
			break
		end
	end
	local log = ns.db.farSecret or {}
	ns.db.farSecret = log
	log.node, log.ids = node.name, table.concat(ids, " ")
	if not ok then
		log.result = "nothing for any of its numbers"
		test.text:SetText(("%s (%s): ClosestGameObjectPosition gives nothing"):format(node.name, log.ids))
		test.box:Hide()
		return
	end
	local secret = IsSecret(x) or IsSecret(distance)
	log.result, log.id, log.count, log.secret = "answered", id, count, secret
	if not secret then log.readable = { x, y, distance } end
	test.secret:SetValue(distance)
	test.flat:SetValue(SafeCall(C_Navigation.GetDistance) or 0)
	-- la minimap : fixe seulement, et seulement si l'on sait quelle valeur suit l'est et le nord
	local map, px, py = MapPosition()
	local radius, turning = View()
	if map and map ~= test.map then test.map, test.axes = map, far.TestAxes(map, px, py) end
	log.axes = test.axes
	local ready, a, b = pcall(UnitPosition, "player")
	local axes = test.axes
	if turning or not (axes and radius and ready) or IsSecret(a) or type(a) ~= "number" then
		test.text:SetText(("%s, number %d: %d values%s ; %s"):format(node.name, id, count, secret and ", secret" or "",
			turning and "no dot on a turning minimap" or "minimap axes unknown"))
		test.box:Hide()
		return
	end
	local mine, theirs = { a, b }, { x, y }
	local east, north, size = axes.east, axes.north, Minimap:GetWidth()
	test.across:SetSize(size, 4)
	test.across:SetReverseFill(east[2] < 0)
	test.across:SetMinMaxValues(mine[east[1]] - radius, mine[east[1]] + radius)
	test.across:SetValue(theirs[east[1]])
	test.up:SetSize(4, size)
	test.up:SetReverseFill(north[2] < 0)
	test.up:SetMinMaxValues(mine[north[1]] - radius, mine[north[1]] + radius)
	test.up:SetValue(theirs[north[1]])
	local shape = (east[2] > 0 and "R" or "L") .. (north[2] > 0 and "T" or "B")
	if test.shape ~= shape then
		test.shape = shape
		test.box:ClearAllPoints()
		test.box:SetPoint("TOPLEFT", test.across:GetStatusBarTexture(), east[2] > 0 and "TOPRIGHT" or "TOPLEFT")
		test.box:SetPoint("BOTTOMRIGHT", test.up:GetStatusBarTexture(), north[2] > 0 and "TOPRIGHT" or "BOTTOMRIGHT")
	end
	test.box:Show()
	test.text:SetText(("%s, number %d: %d values%s ; magenta dot on the minimap ; orange: its distance, blue: the waypoint's"):format(
		node.name, id, count, secret and ", secret" or ""))
end

-- /lueur scan far secret : montre ou retire l'essai
function ns.FarSecretTest()
	local test = far.test
	if not ClosestGameObjectPosition then return "ClosestGameObjectPosition is missing" end
	test.on = not test.on
	if test.on then
		far.TestBuild()
		test.panel:Show()
		test.box:Show()
		test.map = nil
	elseif test.panel then
		test.panel:Hide()
		test.box:Hide()
	end
	return test.on and "secret test shown" or "secret test hidden"
end

far.tester = CreateFrame("Frame")
far.tester:SetScript("OnUpdate", function()
	if far.test.on then
		local ok, problem = pcall(far.TestUpdate)
		if not ok then
			far.test.text:SetText("error: " .. tostring(problem))
			if ns.db then ns.db.farSecretError = tostring(problem) end
		end
	end
end)
