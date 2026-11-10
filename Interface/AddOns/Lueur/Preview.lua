-- Lueur : aperçu
-- Comme la cabine d'essayage du jeu montre un équipement sur le personnage, l'aperçu montre
-- l'effet sur un objet du décor : son modèle 3D, que la souris fait tourner, déplace et
-- rapproche, la nameplate que le jeu lui donnerait, et la lueur qui s'y accroche. Il occupe un
-- panneau de la page des objets, dans la fenêtre des réglages (Menu.lua le pose : ns.PreviewPane).
-- Lueur.lua anime la lueur comme sur une vraie cible ; ce fichier lui dit seulement où se
-- poser (ns.StartPreview) et choisit la catégorie montrée.
--
-- Il n'y a qu'une lueur. L'aperçu la prend quand son panneau se montre, et la cède dès que le
-- jeu désigne un objet à éclairer : les réglages se jugent alors sur lui, et l'aperçu attend.
--
-- La lueur ne se pose pas sur l'objet mais sous sa nameplate, à un nombre fixe de pixels.
-- Pour la montrer au même endroit qu'en jeu, l'aperçu reproduit donc la géométrie du jeu :
-- la nameplate flotte à hauteur fixe au-dessus du pied de l'objet, et sa place à l'écran est
-- celle de ce point vu par la caméra. Rapprocher l'objet l'écarte de sa nameplate, donc de sa
-- lueur, exactement comme lorsqu'on marche vers lui.

local _, ns = ...
local L = ns.L
local Skin = ns.Skin
if not Skin then return end -- jeu pas relancé depuis la mise à jour qui a apporté Skin.lua : Menu.lua le dit

local FOV = math.rad(30)         -- champ de vision de la caméra
local PITCH = math.asin(0.36)    -- la caméra plonge sous l'angle habituel du jeu : celui de GROUND, dans Effects.lua
local START_YAW = math.pi - 0.5  -- elle regarde l'objet de trois quarts face
local TURN_SPEED = 0.012         -- rotation autour de l'objet, en radians par pixel de glissement
local ZOOM_STEP = 0.88           -- distance multipliée par ce facteur à chaque cran de molette
local ZOOM_NEAR, ZOOM_FAR = 0.2, 2.5  -- bornes de la distance, en fractions de celle de départ
local PAN_REACH = 4              -- distance dont la caméra peut s'écarter de l'objet, en mètres du jeu
local TRIAL_DISTANCE = 10        -- distance à laquelle se mesure la taille d'un mètre à l'écran
local PLATE_DEFAULT = 45         -- hauteur de la nameplate au-dessus du centre de la vue, sans modèle

-- Mesuré sur des captures du jeu (7 octobre 2026 : un coffre et deux plantes, à une dizaine de
-- mètres puis de près). La nameplate d'un objet flotte à environ deux mètres au-dessus de son
-- pied, quelle que soit sa hauteur ; et à la distance des premières captures, un mètre du jeu
-- occupe une quarantaine d'unités de l'interface.
local PLATE_HEIGHT = 2.0
local UNITS_PER_YARD = 40
-- Le fichier d'un modèle n'a pas la taille de l'objet du jeu, que le serveur réduit à sa guise : le filon
-- de cuivre, tel quel, emplissait la vue, sa nameplate au milieu de la roche et la lueur à son pied (vu en
-- jeu le 2026-11-09), alors qu'en jeu il fait la taille de sa lueur et porte son nom juste au-dessus de lui.
-- Un modèle plus grand que cela est donc réduit, et la nameplate ne descend jamais dans le modèle.
local MAX_HEIGHT, MAX_WIDTH = 1.8, 2.4  -- taille que garde au plus un modèle, en mètres du jeu
local PLATE_CLEAR = 0.2                 -- la nameplate flotte au moins à cela au-dessus du sommet du modèle

-- Modèle montré pour chaque catégorie : identifiants de fichier du client, relevés dans la
-- liste communautaire wow-listfile
local MODELS = {
	ore   = 219514,  -- world/skillactivated/tradeskillnodes/copper_miningnode_01.m2
	herb  = 219481,  -- world/skillactivated/tradeskillnodes/bush_peacebloom01.m2
	quest = 198168,  -- world/generic/human/passive doodads/crates/stormwindcrate01.m2
	chest = 219372,  -- world/skillactivated/containers/treasurechest01.m2
	bobber = 201000, -- world/goober/g_fishingbobber.m2
	other = 199999,  -- world/generic/passivedoodads/postboxes/postboxhuman.m2
}

local view, plate             -- la vue où se dessine l'objet, créée avec la page ; le cadre qui y tient lieu de nameplate
local scene, actor            -- la scène 3D et son modèle ; nil sur un client qui n'en a pas
local caption, notice, hint   -- textes : état montré, absence de modèle, mode d'emploi
local category = ns.CATEGORY_ORDER[1]
local fitted = true           -- le modèle chargé a été cadré

-- La caméra tourne autour du point qu'elle vise, à une distance que règle la molette
local foot = { 0, 0, 0 }      -- pied de l'objet : le centre de sa base
local plateHeight = PLATE_HEIGHT  -- hauteur de sa nameplate au-dessus de ce pied
local target = { 0, 0, 0 }    -- point visé ; il part du milieu entre le pied et la nameplate
local yaw, distance, fitDistance = START_YAW, TRIAL_DISTANCE, TRIAL_DISTANCE
local signX, signY = 1, 1     -- sens des axes « droite » et « haut » de la caméra à l'écran
local drag                    -- glissement en cours : { x, y, pan }, nil sinon

-- Change le texte d'une région, sans y toucher quand il est déjà le bon
local function SetText(region, text)
	if region:GetText() ~= text then region:SetText(text) end
end

-- Position à l'écran d'un point de la scène, en unités de l'interface depuis le coin bas
-- gauche de la vue ; rien si la caméra ne le voit pas. Le client la donne en pixels.
local function Project(x, y, z)
	local px, py = scene:Project3DPointTo2D(x, y, z)
	if not px or not py then return nil end
	local scale = scene:GetEffectiveScale()
	return px / scale, py / scale
end

-- Place la caméra : en plongée, tournée de `yaw` autour du point visé, à `distance` de lui.
-- La direction du regard suit la convention des caméras du jeu (Vector3D.lua).
local function PlaceCamera()
	local flat = math.cos(-PITCH)
	local x, y, z = flat * math.cos(yaw), flat * math.sin(yaw), math.sin(-PITCH)
	scene:SetCameraPosition(target[1] - x * distance, target[2] - y * distance, target[3] - z * distance)
	scene:SetCameraOrientationByYawPitchRoll(yaw, PITCH, 0)
	scene:SetLightDirection(x, y, z)
end

-- Met la vue en accord avec la caméra, et la nameplate là où cette caméra la verrait
local function UpdateView()
	PlaceCamera()
	local x, y = Project(foot[1], foot[2], foot[3] + plateHeight)
	if x then plate:SetPoint("CENTER", view, "BOTTOMLEFT", x, y) end
end

-- Cadre le modèle une fois chargé : la caméra vise le milieu entre son pied et sa nameplate,
-- d'assez loin pour qu'il ait la taille qu'il a en jeu
local function Fit()
	fitted = true
	local x1, y1, z1, x2, y2, z2 = actor:GetActiveBoundingBox()
	local scale = 1
	plateHeight = PLATE_HEIGHT
	if x1 and z2 then
		-- la boîte est celle du modèle à l'échelle 1 : Blizzard la multiplie lui-même par l'échelle de
		-- l'acteur (Blizzard_CatalogShop_Model.lua, build 70245)
		local height, width = z2 - z1, math.max(x2 - x1, y2 - y1)
		if height > 0 and width > 0 then scale = math.min(1, MAX_HEIGHT / height, MAX_WIDTH / width) end
		foot[1], foot[2], foot[3] = (x1 + x2) / 2 * scale, (y1 + y2) / 2 * scale, z1 * scale
		plateHeight = math.max(PLATE_HEIGHT, height * scale + PLATE_CLEAR)
	else
		foot[1], foot[2], foot[3] = 0, 0, 0 -- modèle sans volume mesurable
	end
	if actor.SetScale then pcall(actor.SetScale, actor, scale) end
	target[1], target[2], target[3] = foot[1], foot[2], foot[3] + plateHeight / 2
	yaw, distance = START_YAW, TRIAL_DISTANCE
	PlaceCamera()
	-- La distance de départ se mesure plutôt qu'elle ne se calcule : on regarde ce qu'occupe à
	-- l'écran un mètre posé au point visé, vu de la distance d'essai. Les mêmes mesures disent
	-- dans quel sens vont, à l'écran, les axes de la caméra.
	fitDistance = view:GetHeight() / (2 * math.tan(FOV / 2) * UNITS_PER_YARD)
	signX, signY = 1, 1
	local rightX, rightY, rightZ = scene:GetCameraRight()
	local upX, upY, upZ = scene:GetCameraUp()
	local x, y = Project(target[1], target[2], target[3])
	local alongRight = Project(target[1] + rightX, target[2] + rightY, target[3] + rightZ)
	local _, alongUp = Project(target[1] + upX, target[2] + upY, target[3] + upZ)
	if x and alongRight and alongUp and alongRight ~= x and alongUp ~= y then
		fitDistance = TRIAL_DISTANCE * math.abs(alongRight - x) / UNITS_PER_YARD
		signX, signY = alongRight > x and 1 or -1, alongUp > y and 1 or -1
	end
	distance = fitDistance
	UpdateView()
	actor:Show()
end

-- Suit la souris pendant un glissement : le bouton gauche tourne autour de l'objet, le droit
-- le déplace
local function Drag()
	local scale = view:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	local moveX, moveY = x - drag.x, y - drag.y
	drag.x, drag.y = x, y
	if not drag.pan then
		yaw = yaw - moveX * TURN_SPEED
		return
	end
	-- l'objet suit le curseur : c'est le point visé qui glisse, en sens inverse
	local perYard = UNITS_PER_YARD * fitDistance / distance
	local right, up = -moveX / perYard * signX, -moveY / perYard * signY
	local rightX, rightY, rightZ = scene:GetCameraRight()
	local upX, upY, upZ = scene:GetCameraUp()
	local home = { foot[1], foot[2], foot[3] + plateHeight / 2 }
	local away = 0
	for index, axis in ipairs({ { rightX, upX }, { rightY, upY }, { rightZ, upZ } }) do
		target[index] = target[index] + axis[1] * right + axis[2] * up
		away = away + (target[index] - home[index]) ^ 2
	end
	-- pas plus loin que de quoi sortir l'objet de la vue
	away = math.sqrt(away)
	if away > PAN_REACH then
		for index = 1, 3 do target[index] = home[index] + (target[index] - home[index]) * PAN_REACH / away end
	end
end

-- Rapproche ou éloigne la caméra d'un cran de molette
local function Zoom(delta)
	if not scene or not fitted then return end
	distance = math.max(fitDistance * ZOOM_NEAR, math.min(fitDistance * ZOOM_FAR, distance * ZOOM_STEP ^ delta))
end

-- Crée la scène 3D et son modèle. Ces cadres n'existent pas sur tous les clients : sans eux,
-- la fenêtre montre la lueur seule.
local function CreateScene()
	local ok, frame = pcall(CreateFrame, "ModelScene", nil, view)
	if not ok or not frame then return end
	local made
	ok = pcall(function()
		frame:SetAllPoints()
		frame:SetCameraFieldOfView(FOV)
		frame:SetCameraNearClip(0.05)
		frame:SetCameraFarClip(500)
		frame:SetLightVisible(true)
		frame:SetLightAmbientColor(0.75, 0.75, 0.75)
		frame:SetLightDiffuseColor(1, 1, 1)
		made = frame:CreateActor(nil, "ModelSceneActorTemplate")
	end)
	if ok and made then
		scene, actor = frame, made
	else
		frame:Hide()
	end
end

-- Montre une catégorie : son modèle, puis la lueur sur la nameplate qu'il aurait
local function ShowCategory(shown)
	category = shown
	drag = nil
	plate:SetPoint("CENTER", view, "CENTER", 0, PLATE_DEFAULT)
	local loaded = false
	if actor then
		actor:Hide() -- le temps qu'il se charge et soit cadré
		if actor.SetScale then pcall(actor.SetScale, actor, 1) end
		local ok, success = pcall(actor.SetModelByFileID, actor, MODELS[category])
		loaded = ok and success == true
		scene:SetShown(loaded)
	end
	fitted = not loaded
	notice:SetShown(not loaded)
	hint:SetShown(loaded)
	if not ns.GlowTaken() then ns.StartPreview(plate, category, true) end
end

local function Update()
	-- la lueur a pu être reprise entre-temps (une vraie cible, Lueur désactivé, une remise à zéro) :
	-- l'aperçu la redemande dès qu'elle est libre
	if not ns.IsPreviewing() and not ns.GlowTaken() then ns.StartPreview(plate, category, true) end
	local state = ns.PreviewState()
	SetText(caption, state and L["STATE_" .. state:upper()] or "")
	SetText(notice, L.PREVIEW_NO_MODEL)
	SetText(hint, L.PREVIEW_HINT)
	if not fitted then
		if actor:IsLoaded() then Fit() end
	elseif scene and scene:IsShown() then
		if drag then Drag() end
		UpdateView()
	end
end

-- Pose l'aperçu dans `parent` (un panneau de la page des objets), à la taille donnée : la vue, et
-- sous elle son mode d'emploi. Renvoie la vue. Elle prend la lueur quand elle se montre, la rend
-- quand elle se cache.
function ns.PreviewPane(parent, width, height)
	-- la vue : rien de ce qu'elle contient n'en déborde, pas même une lueur réglée très grande
	view = CreateFrame("Frame", "LueurPreview", parent)
	view:SetSize(width, height)
	view:SetClipsChildren(true)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseDown", function(_, button)
		if not scene or not fitted then return end
		local scale = view:GetEffectiveScale()
		local x, y = GetCursorPosition()
		drag = { x = x / scale, y = y / scale, pan = button == "RightButton" }
	end)
	view:SetScript("OnMouseUp", function() drag = nil end)
	view:SetScript("OnMouseWheel", function(_, delta) Zoom(delta) end)
	local background = view:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.07, 1)
	-- le décor de la cabine d'essayage, sur les clients qui l'ont
	local class = UnitClass and select(2, UnitClass("player"))
	local atlas = type(class) == "string" and "dressingroom-background-" .. class
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then background:SetAtlas(atlas) end

	CreateScene()
	-- la nameplate de l'objet : la lueur s'y accroche juste sous elle, donc au-dessus du modèle
	plate = CreateFrame("Frame", nil, view)
	plate:SetSize(1, 1)
	plate:SetFrameLevel(view:GetFrameLevel() + 5)

	-- par-dessus la scène : l'état que joue l'aperçu, en bas de la vue
	local texts = CreateFrame("Frame", nil, view)
	texts:SetAllPoints()
	texts:SetFrameLevel(view:GetFrameLevel() + 8)
	caption = texts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("BOTTOM", view, "BOTTOM", 0, 8)
	notice = texts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	notice:SetPoint("TOP", view, "TOP", 0, -8)
	-- (sur deux lignes au besoin : d'une traite, il débordait du panneau en jeu, le 2026-11-09)
	hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOP", view, "BOTTOM", 0, -5)
	hint:SetWidth(width - 8)
	hint:SetJustifyH("CENTER")

	view:SetScript("OnShow", function() ShowCategory(category) end)
	view:SetScript("OnHide", function()
		drag = nil
		ns.StopPreview()
		-- (la langue peut changer pendant que la vue est cachée : ses textes se reposent quand elle revient)
		caption:SetText("")
		notice:SetText("")
		hint:SetText("")
	end)
	view:SetScript("OnUpdate", Update)
	if view:IsVisible() then ShowCategory(category) end
	return view
end

-- Montre cette catégorie dans l'aperçu : le menu l'appelle quand on y choisit celle à personnaliser
function ns.ShowPreviewCategory(shown)
	if shown == category then return end
	category = shown
	if view and view:IsVisible() then ShowCategory(shown) end
end
