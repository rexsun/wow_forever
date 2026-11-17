-- Lueur : la lueur
-- Un seul cadre (glow.frame), accroché à la nameplate de la cible ou à celle que simule l'aperçu.
-- Ce fichier l'anime et confie son dessin à l'effet de la catégorie (Effects.lua) ; il écrit le
-- nom et l'icône de l'objet à la place de ceux du jeu, masque ce que le jeu dessine sur la
-- nameplate, dissipe la lueur sur place quand la cible s'en va, et la découpe autour du
-- personnage (silhouette).

local ADDON_NAME, ns = ...
local EFFECTS = ns.EFFECTS
local Lerp, Sized, Tint, Place = ns.Lerp, ns.Sized, ns.Tint, ns.Place
local S, glow = ns.state, ns.glow
local SafeCall, IsSecret, Clamp, Approach, Look, Color, Color2 = ns.SafeCall, ns.IsSecret, ns.Clamp, ns.Approach, ns.Look, ns.GetColor, ns.GetColor2
local GetCVarValue, SetGate = ns.GetCVarValue, ns.SetGate

local db, cdb
ns.OnSettings(function(account, character) db, cdb = account, character end)


local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local CURSORS = "Interface\\Cursor\\"
local FALLBACK_TEXTURE = "Interface\\Cooldown\\star4"

local APPEAR_TIME   = 0.45   -- la lueur arrive
local BLEND_TIME    = 0.30   -- fondu entre deux états
local FLASH_TIME    = 0.65   -- éclair du passage "à portée" (il retombe vite puis s'attarde : voir Animate)
local GHOST_TIME    = 0.40   -- dissipation quand la cible disparaît
local STATE_DELAY   = 0.15   -- un état doit tenir ce temps avant d'être affiché (anti-scintillement)
local LOCK_DELAY    = 0.60   -- idem pour "indisponible", confirmé plus prudemment

-- Curseur que l'aperçu montre pour chaque catégorie, faute d'objet à qui le demander
local SAMPLE_CURSOR = { ore = "Mine", herb = "GatherHerbs", quest = "Quest", chest = "Pickup", bobber = "Fishing", other = "Interact" }

local ghost                   -- cadre de dissipation
local label                   -- nom et icône de l'objet, au-dessus de la lueur

local sin, min, max = math.sin, math.min, math.max
local TWO_PI = 2 * math.pi

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

-- Un fondu qui part et arrive en douceur : 0 -> 1, sans à-coup aux deux bouts
local function Ease(t)
	return t * t * (3 - 2 * t)
end

local function Animate(self, elapsed)
	if elapsed > 0.1 then elapsed = 0.1 end -- pas de saut après un gel d'image
	local effect = UseEffect()
	local fx, c = effect.fx, context

	glow.appear = Approach(glow.appear, 1, elapsed / APPEAR_TIME)
	glow.ready  = Approach(glow.ready, glow.state == "ready" and 1 or 0, elapsed / BLEND_TIME)
	glow.locked = Approach(glow.locked, glow.state == "locked" and 1 or 0, elapsed / BLEND_TIME)
	glow.flash  = max(glow.flash - elapsed / FLASH_TIME, 0)
	-- (la même vitesse de fondu quel que soit le nombre d'images par seconde)
	local blend = 1 - math.exp(-8 * elapsed)
	glow.r = Lerp(glow.r, glow.targetR, blend)
	glow.g = Lerp(glow.g, glow.targetG, blend)
	glow.b = Lerp(glow.b, glow.targetB, blend)
	-- la seconde couleur de la catégorie, et à quel point elle lui est propre (0 : c'est la première)
	local r2, g2, b2, own = Color2(glow.category)
	glow.r2, glow.g2, glow.b2 = Lerp(glow.r2, r2, blend), Lerp(glow.g2, g2, blend), Lerp(glow.b2, b2, blend)
	glow.dual = Lerp(glow.dual, own and 1 or 0, blend)

	-- les passages d'un état à l'autre avancent à vitesse constante (glow.ready, glow.locked) ; ce que
	-- les effets en reçoivent part et arrive en douceur
	local ready, locked = Ease(glow.ready), Ease(glow.locked)
	-- respiration et mouvement, plus vifs à portée, ralentis sur un objet indisponible
	glow.phase = glow.phase + elapsed * TWO_PI / Lerp(3.4, 1.7, ready)
	glow.spin = glow.spin - elapsed * Lerp(0.55, 1.6, ready) * (1 - 0.7 * locked)

	c.frame, c.elapsed, c.size = self, elapsed, Look(glow.category, "size")
	c.arrive = 1 - (1 - glow.appear) ^ 3            -- 0 -> 1 en décélérant
	-- sur un objet indisponible la lueur faiblit de moitié, ou s'éteint si le joueur l'a demandé
	local dim = db.hideLocked and 1 or 0.5
	c.alpha = c.arrive * Look(glow.category, "intensity") / 100 * (1 - dim * locked)
	-- l'éclair retombe vite, puis s'attarde : il ne s'arrête pas net
	c.ready, c.locked, c.flash, c.phase, c.spin = ready, locked, glow.flash * glow.flash, glow.phase, glow.spin
	c.breath = 0.5 + 0.5 * sin(glow.phase)
	c.twinkle = 0.5 + 0.5 * sin(glow.phase * 2.3 + 1.3)
	-- couleur : éteinte vers le gris sur un objet indisponible. Les traits fins (h) et le cœur des
	-- éclats (w) prennent la seconde couleur, tirée vers le blanc ; moins quand elle est propre à la
	-- catégorie, pour qu'elle se voie
	local r = Lerp(glow.r, 0.62, 0.75 * locked)
	local g = Lerp(glow.g, 0.62, 0.75 * locked)
	local b = Lerp(glow.b, 0.62, 0.75 * locked)
	c.r, c.g, c.b = r, g, b
	r2, g2, b2 = Lerp(glow.r2, 0.62, 0.75 * locked), Lerp(glow.g2, 0.62, 0.75 * locked), Lerp(glow.b2, 0.62, 0.75 * locked)
	local fine, core = 0.55 - 0.35 * glow.dual, 0.75 - 0.35 * glow.dual
	c.hr, c.hg, c.hb = Lerp(r2, 1, fine), Lerp(g2, 1, fine), Lerp(b2, 1, fine)
	c.wr, c.wg, c.wb = Lerp(r2, 1, core), Lerp(g2, 1, core), Lerp(b2, 1, core)

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
					-- (monte jusqu'aux deux tiers de sa course, puis s'éteint, sans angle)
					fade = sin(math.pi * progress ^ 1.5)
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
Animate = ns.Timed("animate", Animate) -- (son coût, pour /lueur status)

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
-- ses nameplates de PNJ amicaux sont allumées. Rangée dans `glow` depuis le
-- temps où tout le cœur tenait dans Lueur.lua, alors à la limite de Lua 5.1 en variables locales.
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
	if plate and glow.Exclusive() and S.gateOpen ~= false and not PlateOwed(unit) then return plate end
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
		Tint(self.ring, Lerp(self.r2, 1, self.fine), Lerp(self.g2, 1, self.fine), Lerp(self.b2, 1, self.fine), self.ringed and fade or 0)
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
	frame.r2, frame.g2, frame.b2, frame.fine = glow.r2, glow.g2, glow.b2, 0.55 - 0.35 * glow.dual
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
	local r2, g2, b2, own = Color2(category)
	glow.r2, glow.g2, glow.b2, glow.dual = r2, g2, b2, own and 1 or 0
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

-- Ce dont les fichiers suivants se servent
ns.silhouette, ns.ApplySilhouette, ns.SetState, ns.ShowLabel = silhouette, ApplySilhouette, SetState, ShowLabel
ns.Release, ns.Attach, ns.Present, ns.Mute, ns.Unmute, ns.Shut = Release, Attach, Present, Mute, Unmute, Shut
