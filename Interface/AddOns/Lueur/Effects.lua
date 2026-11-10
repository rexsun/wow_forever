-- Lueur : les effets
-- Un effet est une façon de dessiner la lueur posée sur l'objet visé. Lueur.lua fait vivre
-- l'état commun à tous (arrivée, à portée, indisponible, couleur) et le passe à chaque image
-- à l'effet choisi, qui ne fait que placer et teinter ses propres couches.
--
-- Un effet déclare :
--   Build(fx, Layer)  crée ses couches dans fx ; Layer(image, couche, sous-couche, mélange)
--   Update(fx, c)     les anime ; c décrit l'image en cours (voir Animate dans Lueur.lua)
--   wave, flat        l'image de ses ondes et leur aplatissement ; sans wave, pas d'ondes
--   waveGain          leur intensité ; ping = false : pas d'onde régulière
--   band              l'image de sa dissipation, quand ce n'est pas une simple lueur
--   icon              son dessin sur son bouton du menu, couche par couche :
--                     { image, largeur, hauteur, x, y, opacité }, en fractions du côté du bouton ;
--                     une septième valeur vraie blanchit la couche, comme le cœur d'une lumière
-- Update peut laisser dans fx.waveSize, fx.waveY et fx.waveAngle la taille de référence des
-- ondes, leur hauteur et leur rotation.

local _, ns = ...

local sin, cos, min, max, sqrt, random, pi, floor = math.sin, math.cos, math.min, math.max, math.sqrt, math.random, math.pi, math.floor
local atan2 = math.atan2
local TWO_PI = 2 * pi

local GROUND     = 0.36   -- aplatissement d'un cercle posé au sol, sous l'angle habituel de la caméra
local RING_ORBIT = 0.37   -- rayon de l'anneau fin, en fraction de la largeur de son image
local FOOT       = -0.12  -- hauteur du sol sous le centre de l'objet, en fraction de la taille de l'effet

local function Lerp(a, b, t)
	return a + (b - a) * t
end

-- Une taille nulle rendrait à la couche les dimensions de son image
local function Sized(texture, width, height)
	texture:SetSize(max(width, 0.01), max(height or width, 0.01))
end

local function Tint(texture, r, g, b, a)
	texture:SetVertexColor(r, g, b, a <= 0 and 0 or a >= 1 and 1 or a)
end

local function Place(texture, frame, x, y)
	texture:SetPoint("CENTER", frame, "CENTER", x, y)
end

-- Voile sombre couché au sol, sous la lumière : sans lui, un effet additif s'efface sur la
-- neige ou le sable. Sa couche porte l'image "glow", dont la tache n'occupe que le centre.
local function GroundShade(texture, c, width, y)
	Sized(texture, width, width * GROUND * 1.3)
	Place(texture, c.frame, 0, y)
	Tint(texture, 0, 0, 0, c.alpha * 0.30)
end

ns.Lerp, ns.Sized, ns.Tint, ns.Place = Lerp, Sized, Tint, Place

local EFFECTS = {}
ns.EFFECTS = EFFECTS

-- Ordre du menu : ceux qui entourent l'objet, puis ceux qui se posent au sol ou s'élèvent
ns.EFFECT_ORDER = { "aura", "subtle", "sigil", "vortex", "rift", "flame", "storm", "beam", "geyser", "beacon", "orbit", "spirit", "ripple",
	"sparkle" }

---------------------------------------------------------------------------
-- Halos : une même construction, dont chaque variante pèse les couches à sa façon
---------------------------------------------------------------------------

local MOTE_COUNT = 3
local LICK_COUNT, EJECTA_COUNT = 7, 5  -- la couronne de l'aura : ses langues de feu, et les escarbilles qu'elle projette

-- Chaque effet a, en plus de sa forme, quelque chose qui vit : des particules qui naissent, courent et
-- s'éteignent, une danse qui ne se répète pas d'un instant à l'autre (demandé le 2026-11-09 : « plus de
-- folie, trop classique et sans âme »).
local function Halo(weight)
	return {
		band = "halo", wave = "ring", waveGain = weight.waves,

		Build = function(fx, Layer)
			fx.shade = Layer("halo", "BACKGROUND", -1, "BLEND")
			fx.band = Layer("halo", "BACKGROUND")
			fx.wisps = { Layer("wisp", "BACKGROUND", 1), Layer("wisp", "BACKGROUND", 1) }
			fx.ring = Layer("ring", "ARTWORK")
			fx.arcs = Layer("arcs", "ARTWORK", 1)
			fx.motes = {}
			for i = 1, MOTE_COUNT do fx.motes[i] = Layer("glow", "OVERLAY") end
			fx.flare = Layer("flare", "OVERLAY", 1)
			if weight.corona then
				fx.licks, fx.ejecta = {}, {}
				for i = 1, LICK_COUNT do fx.licks[i] = Layer("flame", "BACKGROUND", 2) end
				for i = 1, EJECTA_COUNT do fx.ejecta[i] = Layer("glow", "OVERLAY") end
			end
		end,

		Update = function(fx, c)
			local alpha, ready, locked, flash = c.alpha, c.ready, c.locked, c.flash
			local size = c.size * (1 + 0.45 * (1 - c.arrive))  -- le halo se resserre en arrivant
			fx.waveSize = size

			-- voile sombre sous la lumière : un halo additif s'efface sur la neige ou le sable
			Sized(fx.shade, size * 1.06)
			Tint(fx.shade, 0, 0, 0, alpha * weight.shade * 0.30)

			Sized(fx.band, size * (0.96 + 0.07 * c.breath))
			Tint(fx.band, c.r, c.g, c.b, alpha * weight.band * Lerp(0.50, 0.80, ready) * (0.8 + 0.2 * c.breath))

			-- volutes : deux nappes de filaments tournent en sens contraires dans la bande, qui en paraît vivante
			local wisps = alpha * weight.wisps * (Lerp(0.28, 0.42, ready) + 0.3 * flash) * (1 - 0.6 * locked)
			Sized(fx.wisps[1], size * 1.03)
			fx.wisps[1]:SetRotation(0.22 * c.spin)
			Tint(fx.wisps[1], c.hr, c.hg, c.hb, wisps)
			Sized(fx.wisps[2], size * 0.93)
			fx.wisps[2]:SetRotation(2.1 - 0.31 * c.spin)
			Tint(fx.wisps[2], c.hr, c.hg, c.hb, wisps * 0.8)

			Sized(fx.ring, size)
			Tint(fx.ring, c.hr, c.hg, c.hb, alpha * weight.ring * (Lerp(0.25, 0.75, ready) + 0.25 * flash))

			-- comètes : sens horaire, plus rapides à portée
			Sized(fx.arcs, size)
			fx.arcs:SetRotation(c.spin)
			Tint(fx.arcs, c.hr, c.hg, c.hb, alpha * weight.arcs * Lerp(0.45, 0.95, ready) * (1 - locked))

			Sized(fx.flare, size * (0.34 + 0.10 * ready + 0.04 * c.twinkle + 0.30 * flash + 0.50 * (1 - c.arrive)))
			fx.flare:SetRotation(0.10 * sin(c.phase * 0.5))
			Tint(fx.flare, c.wr, c.wg, c.wb,
				alpha * weight.flare * (Lerp(0.35, 0.90, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))

			-- couronne : des langues de feu lèchent l'anneau vers l'extérieur, chacune à son rythme, et
			-- des escarbilles s'en échappent ; le tout s'embrase au passage à portée
			if fx.licks then
				local time = -c.spin
				for i, lick in ipairs(fx.licks) do
					local angle = 0.12 * c.spin + i * TWO_PI / LICK_COUNT + 0.25 * sin(time * 0.7 + i * 1.7)
					local dance = 0.5 + 0.5 * sin(time * (2.6 + 0.37 * i) + i * 2.1)
					local length = size * (0.20 + 0.16 * dance + 0.10 * ready + 0.30 * flash)
					local radius = size * 0.35 + length * 0.42
					Sized(lick, size * 0.22, length)
					Place(lick, c.frame, cos(angle) * radius, sin(angle) * radius)
					lick:SetRotation(angle - pi / 2)
					Tint(lick, c.r, c.g, c.b, alpha * weight.corona * (Lerp(0.35, 0.70, ready) + 0.3 * flash) * (0.7 + 0.3 * dance) * (1 - locked))
				end
				for i, spark in ipairs(fx.ejecta) do
					local cycle = time * 0.33 + i / EJECTA_COUNT
					local flight = cycle % 1
					local angle = i * 2.4 + floor(cycle) * 1.9 + 0.6 * flight
					local radius = size * (0.37 + 0.45 * flight)
					Place(spark, c.frame, cos(angle) * radius, sin(angle) * radius)
					Sized(spark, size * 0.10 * (1 - 0.6 * flight))
					Tint(spark, c.hr, c.hg, c.hb, alpha * weight.corona * sin(pi * flight) * Lerp(0.40, 1, ready) * (1 - locked))
				end
			end

			-- lucioles : en orbite sur l'anneau, à contresens des comètes, visibles à portée
			local orbit = size * RING_ORBIT
			for i, mote in ipairs(fx.motes) do
				local angle = -0.6 * c.spin + i * TWO_PI / MOTE_COUNT
				local glint = 0.5 + 0.5 * sin(c.phase * 3.1 + i * 2.1)
				Place(mote, c.frame, cos(angle) * orbit, sin(angle) * orbit)
				Sized(mote, size * (0.10 + 0.05 * glint))
				Tint(mote, c.hr, c.hg, c.hb, alpha * weight.motes * ready * (1 - locked) * (0.45 + 0.55 * glint))
			end
		end,
	}
end

EFFECTS.aura   = Halo({ corona = 1, shade = 1.0, band = 0.75, wisps = 1.0, ring = 0.85, arcs = 0.90, flare = 0.90, motes = 1, waves = 1.0 })
EFFECTS.subtle = Halo({ shade = 0.8, band = 0.75, wisps = 0.5, ring = 0.00, arcs = 0.00, flare = 0.45, motes = 0, waves = 0.4 })
EFFECTS.aura.icon = { { "halo", 1, 1, 0, 0, 0.45 }, { "wisp", 1, 1, 0, 0, 0.5 }, { "ring", 1, 1, 0, 0, 1 }, { "flare", 0.6, 0.6, 0, 0, 1, true } }
EFFECTS.subtle.icon = { { "halo", 1, 1, 0, 0, 0.9 }, { "flare", 0.36, 0.36, 0, 0, 0.6, true } }
-- Sert quand les images d'un effet sont introuvables (dossier Media incomplet, ou jeu pas
-- relancé après l'installation) : chaque couche porte alors une texture du jeu.
EFFECTS.fallback = Halo({ shade = 0.0, band = 1.00, wisps = 0.0, ring = 0.00, arcs = 0.00, flare = 1.00, motes = 0, waves = 0.0 })

---------------------------------------------------------------------------
-- Sceau : un cercle de runes et sa figure, qui tournent en sens contraires
---------------------------------------------------------------------------

EFFECTS.sigil = {
	band = "halo", wave = "ring",
	icon = { { "sigil", 1, 1, 0, 0, 1 }, { "glyph", 0.7, 0.7, 0, 0, 0.9, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("halo", "BACKGROUND", -1, "BLEND")
		fx.band = Layer("halo", "BACKGROUND")
		fx.circle = Layer("sigil", "ARTWORK")
		fx.figure = Layer("glyph", "ARTWORK", 1)
		fx.flare = Layer("flare", "OVERLAY")
		fx.turn = 0
	end,

	Update = function(fx, c)
		local alpha, ready, locked, flash = c.alpha, c.ready, c.locked, c.flash
		local size = c.size * (1 + 0.30 * (1 - c.arrive))
		fx.waveSize = size
		-- le sceau s'emballe au passage à portée, et se fige sur un objet indisponible
		fx.turn = fx.turn + c.elapsed * (Lerp(0.22, 0.55, ready) + 2.5 * flash) * (1 - locked)

		Sized(fx.shade, size * 1.10)
		Tint(fx.shade, 0, 0, 0, alpha * 0.34)
		Sized(fx.band, size * (0.94 + 0.05 * c.breath))
		Tint(fx.band, c.r, c.g, c.b, alpha * Lerp(0.28, 0.48, ready) * (0.8 + 0.2 * c.breath))

		local circle = size * 0.94 * (1 + 0.06 * flash)
		Sized(fx.circle, circle)
		fx.circle:SetRotation(fx.turn)
		Tint(fx.circle, c.hr, c.hg, c.hb, alpha * (Lerp(0.55, 0.95, ready) + 0.25 * flash))

		-- les sommets de la figure courent sur le rang de tirets du cercle
		Sized(fx.figure, circle * 0.72)
		fx.figure:SetRotation(-1.6 * fx.turn)
		Tint(fx.figure, c.hr, c.hg, c.hb, alpha * Lerp(0.38, 0.85, ready) * (1 - 0.4 * locked))

		Sized(fx.flare, size * (0.26 + 0.08 * ready + 0.04 * c.twinkle + 0.30 * flash))
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.20, 0.80, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Tourbillon : des bras de lumière s'enroulent autour de l'objet, comme un portail qui s'ouvre
---------------------------------------------------------------------------

EFFECTS.vortex = {
	band = "halo", wave = "ring", waveGain = 0.7,
	icon = { { "halo", 1, 1, 0, 0, 0.4 }, { "swirl", 1.05, 1.05, 0, 0, 1 }, { "flare", 0.4, 0.4, 0, 0, 0.9, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("halo", "BACKGROUND", -1, "BLEND")
		fx.band = Layer("halo", "BACKGROUND")
		fx.outer = Layer("swirl", "ARTWORK")
		fx.inner = Layer("swirl", "ARTWORK", 1)
		fx.motes = {}
		for i = 1, 7 do fx.motes[i] = { Layer("glow", "OVERLAY"), Layer("glow", "OVERLAY") } end
		fx.flare = Layer("flare", "OVERLAY")
		fx.turn = 0
	end,

	Update = function(fx, c)
		local alpha, ready, locked, flash = c.alpha, c.ready, c.locked, c.flash
		local size = c.size * (1 + 0.35 * (1 - c.arrive))
		fx.waveSize = size
		-- le tourbillon s'emballe au passage à portée, et s'arrête presque sur un objet indisponible
		fx.turn = fx.turn + c.elapsed * (Lerp(0.55, 1.15, ready) + 3.0 * flash) * (1 - 0.85 * locked)

		Sized(fx.shade, size * 1.10)
		Tint(fx.shade, 0, 0, 0, alpha * 0.32)
		Sized(fx.band, size * (0.98 + 0.05 * c.breath))
		Tint(fx.band, c.r, c.g, c.b, alpha * Lerp(0.30, 0.50, ready) * (0.8 + 0.2 * c.breath))

		-- deux nappes de bras, la plus petite plus vive : elles tournent dans le sens qui les fait
		-- paraître aspirées vers le centre
		Sized(fx.outer, size * (1.16 + 0.04 * c.breath))
		fx.outer:SetRotation(-fx.turn)
		Tint(fx.outer, c.r, c.g, c.b, alpha * (Lerp(0.60, 0.90, ready) + 0.2 * flash))
		Sized(fx.inner, size * (0.74 - 0.06 * ready))
		fx.inner:SetRotation(1.3 - 1.8 * fx.turn)
		Tint(fx.inner, c.hr, c.hg, c.hb, alpha * Lerp(0.45, 0.95, ready) * (1 - 0.5 * locked))

		-- des éclats sont pris dans le courant : plus ils sont près du centre, plus ils filent
		for i, mote in ipairs(fx.motes) do
			local radius = size * (0.20 + 0.055 * i)
			local angle = i * 1.7 - fx.turn * (3.4 - 0.28 * i)
			for k = 1, 2 do
				local texture, at = mote[k], angle + (k - 1) * 0.16
				Place(texture, c.frame, cos(at) * radius, sin(at) * radius)
				Sized(texture, size * (k == 1 and 0.10 or 0.07))
				Tint(texture, c.wr, c.wg, c.wb, alpha * Lerp(0.45, 1, ready) * (k == 1 and 1 or 0.5) * (1 - locked))
			end
		end

		Sized(fx.flare, size * (0.30 + 0.10 * ready + 0.04 * c.twinkle + 0.30 * flash))
		fx.flare:SetRotation(-0.5 * fx.turn)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.30, 0.90, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Flamme : des langues de feu montent de l'objet, dans sa couleur
---------------------------------------------------------------------------

-- Chaque langue : sa place (en fraction de la largeur du feu), sa hauteur, et de quoi la faire
-- danser à son propre rythme
local TONGUES = {
	{ -0.25, 0.60, 2.9, 0.0 }, { -0.12, 0.88, 3.7, 1.9 }, { 0.01, 1.12, 3.1, 4.1 }, { 0.14, 0.80, 4.3, 2.6 }, { 0.26, 0.54, 3.4, 5.3 },
}
local EMBER_COUNT = 8

EFFECTS.flame = {
	wave = "ring", flat = GROUND, waveGain = 0.6,
	icon = { { "glow", 1, 0.5, 0, -0.32, 0.9 }, { "flame", 0.5, 0.82, -0.17, -0.02, 0.9 }, { "flame", 0.46, 0.7, 0.19, -0.08, 0.9 },
		{ "flame", 0.56, 1, 0.02, 0.07, 1 }, { "flame", 0.3, 0.6, 0.02, -0.13, 1, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.tongues = {}
		for i = 1, #TONGUES do fx.tongues[i] = { Layer("flame", "ARTWORK"), Layer("flame", "ARTWORK", 1) } end
		fx.embers = {}
		for i = 1, EMBER_COUNT do fx.embers[i] = Layer("glow", "OVERLAY") end
		fx.smoke = {}
		for i = 1, 3 do fx.smoke[i] = Layer("glow", "BACKGROUND", -1, "BLEND") end
		fx.flare = Layer("flare", "OVERLAY", 1)
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		-- le feu prend à l'arrivée, monte à portée, et couve sur un objet indisponible
		local vigor = (0.80 + 0.30 * ready + 0.30 * flash) * (0.30 + 0.70 * c.arrive) * (1 - 0.50 * locked)
		local time = -c.spin
		fx.waveSize, fx.waveY = size * 0.95, foot

		-- voile sombre dressé derrière le feu
		Sized(fx.shade, size * 1.7, size * 1.9 * vigor)
		Place(fx.shade, c.frame, 0, foot + size * 0.55 * vigor)
		Tint(fx.shade, 0, 0, 0, alpha * 0.24)

		-- braise au pied
		local pool = size * (1.15 + 0.10 * c.breath)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * Lerp(0.55, 0.95, ready))

		for i, tongue in ipairs(fx.tongues) do
			local shape = TONGUES[i]
			local dance = 0.5 + 0.5 * sin(time * shape[3] + shape[4])
			local flick = 0.5 + 0.5 * sin(time * shape[3] * 2.7 + shape[4] * 1.7)
			local height = size * shape[2] * vigor * (0.74 + 0.20 * dance + 0.10 * flick)
			local width = size * 0.54 * (0.90 + 0.16 * (1 - dance))
			local x = shape[1] * size * 0.80 + sin(time * 1.3 + shape[4]) * size * 0.015
			-- les langues s'ouvrent en éventail, et chacune penche un peu d'un côté puis de l'autre ; une
			-- image tourne autour de son centre : sa base est remise à sa place
			local lean = -0.75 * shape[1] + 0.08 * sin(time * 1.9 + shape[4] * 2.3)
			local outer, core = tongue[1], tongue[2]
			Sized(outer, width, height)
			Place(outer, c.frame, x - sin(lean) * height * 0.46, foot + cos(lean) * height * 0.46)
			outer:SetRotation(lean)
			Tint(outer, c.r, c.g, c.b, alpha * Lerp(0.50, 0.80, ready) * (0.85 + 0.15 * flick))
			-- le cœur de la langue : plus court, plus étroit, presque blanc ; les langues du bord n'en ont guère
			local inner = 1 - 3 * math.abs(shape[1])
			Sized(core, width * 0.60, height * 0.66)
			Place(core, c.frame, x - sin(lean) * height * 0.30, foot + cos(lean) * height * 0.30)
			core:SetRotation(lean)
			Tint(core, c.wr, c.wg, c.wb, alpha * inner * (Lerp(0.35, 0.70, ready) + 0.3 * flash) * (1 - 0.8 * locked))
		end

		-- fumée : des bouffées sombres montent au-dessus du feu et s'y défont
		for i, puff in ipairs(fx.smoke) do
			local climb = (time * 0.16 + i / #fx.smoke) % 1
			Sized(puff, size * (0.55 + 0.60 * climb))
			Place(puff, c.frame, sin(time * 0.6 + i * 2.2) * size * 0.12, foot + size * (0.75 + 0.95 * climb) * vigor)
			Tint(puff, 0, 0, 0, alpha * 0.26 * sin(pi * climb))
		end

		-- escarbilles : elles s'échappent du feu en se balançant
		for i, ember in ipairs(fx.embers) do
			local climb = (time * 0.22 + i / EMBER_COUNT) % 1
			local glint = 0.5 + 0.5 * sin(c.phase * 3.1 + i * 2.1)
			Place(ember, c.frame, (i - 4.5) * size * 0.09 + sin(time * 1.1 + i * 1.9) * size * 0.09, foot + (0.35 + climb * 1.25) * size * vigor)
			Sized(ember, size * (0.10 + 0.04 * glint) * (1 - 0.5 * climb))
			Tint(ember, c.hr, c.hg, c.hb, alpha * sin(pi * climb) * Lerp(0.50, 1, ready) * (1 - locked))
		end

		Sized(fx.flare, size * (0.26 + 0.08 * ready + 0.04 * c.twinkle + 0.30 * flash))
		Place(fx.flare, c.frame, 0, foot + size * 0.05)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.20, 0.70, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Faisceau : une colonne de lumière qui s'élève de l'objet
---------------------------------------------------------------------------

local SPARK_COUNT, HELIX_COUNT = 4, 12

EFFECTS.beam = {
	wave = "ring", flat = GROUND,
	icon = { { "glow", 1, 0.46, 0, -0.3, 0.9 }, { "beam", 0.62, 0.96, 0, 0.02, 1 }, { "beam", 0.3, 0.9, 0, 0.02, 1, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.shaft = Layer("beam", "ARTWORK")
		fx.core = Layer("beam", "ARTWORK", 1)
		fx.sparks = {}
		for i = 1, SPARK_COUNT do fx.sparks[i] = Layer("glow", "OVERLAY") end
		fx.helix = {}
		for i = 1, HELIX_COUNT do fx.helix[i] = Layer("glow", "OVERLAY") end
		fx.fan = Layer("flare", "BACKGROUND", 1)
		fx.flare = Layer("flare", "OVERLAY", 1)
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		-- le faisceau jaillit du sol à l'arrivée, s'allonge à portée, retombe sur un objet indisponible
		local height = size * (1.75 + 0.45 * ready + 0.25 * flash) * (0.25 + 0.75 * c.arrive) * (1 - 0.40 * locked)
		local middle = foot + height / 2
		fx.waveSize, fx.waveY = size * 0.90, foot

		-- voile sombre dressé derrière la colonne, plus large qu'elle
		Sized(fx.shade, size * 1.5, height * 1.5)
		Place(fx.shade, c.frame, 0, middle - height * 0.12)
		Tint(fx.shade, 0, 0, 0, alpha * 0.22)

		-- flaque de lumière au pied
		local pool = size * (1.10 + 0.10 * c.breath)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * Lerp(0.55, 0.90, ready))

		Sized(fx.shaft, size * (0.66 + 0.06 * c.breath + 0.22 * flash), height)
		Place(fx.shaft, c.frame, 0, middle)
		Tint(fx.shaft, c.r, c.g, c.b, alpha * Lerp(0.50, 0.85, ready))

		Sized(fx.core, size * (0.30 + 0.03 * c.breath + 0.14 * flash), height * 0.94)
		Place(fx.core, c.frame, 0, foot + height * 0.47)
		Tint(fx.core, c.wr, c.wg, c.wb, alpha * (Lerp(0.50, 0.95, ready) + 0.3 * flash) * (1 - 0.6 * locked))

		-- étincelles : elles montent le long du faisceau en se balançant, plus vite à portée
		local travel = -c.spin
		for i, spark in ipairs(fx.sparks) do
			local climb = (travel * 0.30 + i / SPARK_COUNT) % 1
			local glint = 0.5 + 0.5 * sin(c.phase * 3.1 + i * 2.1)
			Place(spark, c.frame, sin(travel * 1.3 + i * 1.9) * size * 0.06, foot + climb * height * 0.80)
			Sized(spark, size * (0.13 + 0.05 * glint) * (1 - 0.5 * climb))
			Tint(spark, c.hr, c.hg, c.hb, alpha * sin(pi * climb) * Lerp(0.55, 1, ready) * (1 - locked))
		end

		-- deux brins de lumière s'enroulent autour de la colonne en montant, devant elle puis derrière
		for i, bead in ipairs(fx.helix) do
			local climb = (travel * 0.28 + floor((i + 1) / 2) / (HELIX_COUNT / 2)) % 1
			local angle = climb * TWO_PI * 2.0 + (i % 2) * pi + travel * 1.2
			local depth = sin(angle)
			Place(bead, c.frame, cos(angle) * size * 0.17 * (1 - 0.35 * climb), foot + climb * height * 0.82)
			Sized(bead, size * (0.11 + 0.035 * depth) * (1 - 0.4 * climb))
			Tint(bead, c.wr, c.wg, c.wb, alpha * sin(pi * climb) * (0.55 + 0.45 * depth) * Lerp(0.55, 1, ready) * (1 - locked))
		end
		-- au pied, un éventail de rayons couché sur le sol
		Sized(fx.fan, size * (1.9 + 0.2 * c.breath), size * 0.55)
		Place(fx.fan, c.frame, 0, foot)
		Tint(fx.fan, c.hr, c.hg, c.hb, alpha * Lerp(0.25, 0.60, ready) * (1 - locked))

		Sized(fx.flare, size * (0.30 + 0.08 * ready + 0.04 * c.twinkle + 0.30 * flash))
		Place(fx.flare, c.frame, 0, foot)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.35, 0.90, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Balise : un cristal qui flotte au-dessus de l'objet
---------------------------------------------------------------------------

EFFECTS.beacon = {
	wave = "ring", flat = GROUND,
	icon = { { "glow", 0.9, 0.4, 0, -0.33, 0.8 }, { "beam", 0.2, 0.44, 0, -0.15, 0.8 }, { "glow", 0.85, 0.85, 0, 0.15, 0.6 },
		{ "gem", 0.52, 0.52, 0, 0.15, 1, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.thread = Layer("beam", "BACKGROUND", 1)
		fx.aura = Layer("glow", "ARTWORK")
		fx.gem = Layer("gem", "ARTWORK", 1, "BLEND")
		fx.glint = Layer("flare", "OVERLAY")
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		-- le cristal descend se poser au-dessus de l'objet, y flotte, et s'en rapproche à portée
		local hover = size * (Lerp(0.78, 0.66, ready) + 0.55 * (1 - c.arrive) + 0.035 * sin(c.phase) * (1 - locked))
		local gem = size * (0.52 + 0.06 * flash)
		fx.waveSize, fx.waveY = size * 0.80, foot

		GroundShade(fx.shade, c, size * 1.7, foot)
		local pool = size * (0.95 + 0.10 * c.breath)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * Lerp(0.50, 0.85, ready))

		-- fil de lumière, du sol à la pointe du cristal
		local reach = max(hover - gem * 0.40 - foot, 0.01)
		Sized(fx.thread, size * 0.22, reach)
		Place(fx.thread, c.frame, 0, foot + reach / 2)
		Tint(fx.thread, c.hr, c.hg, c.hb, alpha * Lerp(0.40, 0.75, ready) * (1 - locked))

		Sized(fx.aura, gem * (2.0 + 0.3 * c.breath))
		Place(fx.aura, c.frame, 0, hover)
		Tint(fx.aura, c.r, c.g, c.b, alpha * Lerp(0.50, 0.90, ready))

		Sized(fx.gem, gem)
		Place(fx.gem, c.frame, 0, hover)
		Tint(fx.gem, Lerp(c.r, 1, 0.25), Lerp(c.g, 1, 0.25), Lerp(c.b, 1, 0.25), alpha * Lerp(0.85, 1, ready))

		-- reflet sur la facette la plus claire
		Sized(fx.glint, gem * (0.55 + 0.25 * c.twinkle + 0.60 * flash))
		Place(fx.glint, c.frame, -gem * 0.07, hover + gem * 0.17)
		Tint(fx.glint, c.wr, c.wg, c.wb, alpha * (Lerp(0.30, 0.85, ready) * c.twinkle + 0.5 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Orbite : trois feux follets tournent autour de l'objet, chacun sur son orbite, comme autour d'un noyau
---------------------------------------------------------------------------

-- Chaque orbite : son inclinaison, l'avance de son feu follet, sa vitesse
local ORBITS, TAIL_LENGTH = { { 0, 0.0, 1.00 }, { 1.05, 2.1, 0.86 }, { -1.05, 4.2, 1.14 } }, 8

EFFECTS.orbit = {
	wave = "ring", waveGain = 0.6,
	icon = { { "ring", 1, 0.46, 0, 0, 0.5 }, { "glow", 0.32, 0.32, -0.33, 0.03, 1, true }, { "glow", 0.3, 0.3, 0.3, -0.1, 1, true },
		{ "glow", 0.2, 0.2, 0.12, 0.14, 0.7 }, { "flare", 0.3, 0.3, 0, 0, 0.6, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.core = Layer("glow", "BACKGROUND")
		fx.paths, fx.wisps = {}, {}
		for i = 1, #ORBITS do
			fx.paths[i] = Layer("ring", "BACKGROUND", 1)
			local wisp = {}
			for k = TAIL_LENGTH, 0, -1 do wisp[k] = Layer("glow", "OVERLAY", k == 0 and 1 or 0) end
			fx.wisps[i] = wisp
		end
		fx.flare = Layer("flare", "ARTWORK")
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked = c.size, c.alpha, c.ready, c.locked
		-- les orbites se resserrent en arrivant, puis encore un peu à portée
		local radius = size * Lerp(0.52, 0.44, ready) * (1 + 0.6 * (1 - c.arrive))
		local travel = -2 * c.spin
		fx.waveSize = size

		Sized(fx.shade, size * 1.9)
		Tint(fx.shade, 0, 0, 0, alpha * 0.28)
		Sized(fx.core, size * (0.80 + 0.10 * c.breath))
		Tint(fx.core, c.r, c.g, c.b, alpha * Lerp(0.40, 0.65, ready))

		for i, wisp in ipairs(fx.wisps) do
			local orbit = ORBITS[i]
			-- l'orbite : une ellipse inclinée, qui oscille un peu
			local tilt = orbit[1] + 0.12 * sin(c.phase * 0.5 + i)
			local across, up = cos(tilt), sin(tilt)
			local path = fx.paths[i]
			Sized(path, radius / RING_ORBIT, radius / RING_ORBIT * GROUND)
			path:SetRotation(tilt)
			Tint(path, c.hr, c.hg, c.hb, alpha * Lerp(0.14, 0.30, ready))
			local head = travel * orbit[3] + orbit[2]
			for k = 0, TAIL_LENGTH do
				local angle = head - k * 0.08
				local x, y = cos(angle) * radius, sin(angle) * radius * GROUND
				local depth = -sin(angle)  -- 1 : devant l'objet, -1 : derrière lui, plus petit et plus pâle
				local texture = wisp[k]
				Place(texture, c.frame, x * across - y * up, x * up + y * across)
				Sized(texture, size * (k == 0 and 0.20 or 0.17) * (1 + 0.28 * depth) * 0.90 ^ k)
				if k == 0 then
					Tint(texture, c.wr, c.wg, c.wb, alpha * (0.66 + 0.34 * depth) * Lerp(0.70, 1, ready))
				else
					Tint(texture, c.hr, c.hg, c.hb, alpha * (0.66 + 0.34 * depth) * Lerp(0.50, 0.85, ready) * 0.78 ^ k * (1 - locked))
				end
			end
		end

		-- le noyau
		Sized(fx.flare, size * (0.30 + 0.10 * ready + 0.05 * c.twinkle + 0.30 * c.flash))
		fx.flare:SetRotation(0.2 * travel)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.30, 0.85, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Onde : des rides s'étalent sur le sol autour de l'objet
---------------------------------------------------------------------------

local RIPPLE_COUNT = 3

EFFECTS.ripple = {
	wave = "ring", flat = GROUND, ping = false,
	icon = { { "glow", 1, 0.5, 0, 0, 0.5 }, { "ring", 1, 0.44, 0, 0, 0.7 }, { "ring", 0.62, 0.27, 0, 0, 0.9 },
		{ "ring", 0.28, 0.12, 0, 0, 1, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.rings = {}
		for i = 1, RIPPLE_COUNT do fx.rings[i] = Layer("ring", "ARTWORK") end
		fx.flare = Layer("flare", "OVERLAY")
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked = c.size, c.alpha, c.ready, c.locked
		local foot = FOOT * size
		local travel = -c.spin
		fx.waveSize, fx.waveY = size * 1.10, foot

		GroundShade(fx.shade, c, size * 2.6, foot)
		local pool = size * (1.20 + 0.12 * c.breath)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * Lerp(0.55, 0.90, ready))

		-- chaque ride naît au centre, s'élargit en ralentissant et s'éteint
		for i, ring in ipairs(fx.rings) do
			local spread = (travel * 0.40 + i / RIPPLE_COUNT) % 1
			local width = size * Lerp(0.30, 1.70, 1 - (1 - spread) ^ 2) * (0.6 + 0.4 * c.arrive)
			Sized(ring, width, width * GROUND)
			Place(ring, c.frame, 0, foot)
			Tint(ring, c.hr, c.hg, c.hb, alpha * Lerp(0.60, 1, ready) * min(spread * 6, 1) * (1 - spread) ^ 1.3)
		end

		Sized(fx.flare, size * (0.26 + 0.08 * ready + 0.04 * c.twinkle + 0.30 * c.flash))
		Place(fx.flare, c.frame, 0, foot)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.25, 0.80, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Étincelles : des éclats naissent et s'éteignent autour de l'objet
---------------------------------------------------------------------------

local STAR_COUNT, DUST_COUNT = 6, 3

EFFECTS.sparkle = {
	icon = { { "glow", 1, 1, 0, 0, 0.45 }, { "flare", 0.64, 0.64, -0.12, 0.1, 1, true }, { "flare", 0.42, 0.42, 0.22, -0.2, 0.9, true },
		{ "flare", 0.3, 0.3, 0.2, 0.26, 0.8, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.haze = Layer("glow", "BACKGROUND")
		fx.dust = {}
		for i = 1, DUST_COUNT do fx.dust[i] = Layer("glow", "ARTWORK") end
		fx.stars = {}
		for i = 1, STAR_COUNT do fx.stars[i] = { texture = Layer("flare", "OVERLAY"), age = 0, life = 0 } end
		fx.flash = 0
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked = c.size, c.alpha, c.ready, c.locked

		Sized(fx.shade, size * 1.9)
		Tint(fx.shade, 0, 0, 0, alpha * 0.28)
		Sized(fx.haze, size * (1.55 + 0.12 * c.breath))
		Tint(fx.haze, c.r, c.g, c.b, alpha * Lerp(0.40, 0.62, ready) * (0.85 + 0.15 * c.breath))

		-- poussières : elles montent lentement à travers la lueur
		local travel = -c.spin
		for i, dust in ipairs(fx.dust) do
			local climb = (travel * 0.14 + i / DUST_COUNT) % 1
			Place(dust, c.frame, (i - 2) * size * 0.24 + sin(travel * 0.9 + i * 2.3) * size * 0.05, (climb - 0.45) * size * 0.8)
			Sized(dust, size * 0.11)
			Tint(dust, c.hr, c.hg, c.hb, alpha * sin(pi * climb) * 0.75 * (1 - locked))
		end

		-- éclats : chacun s'allume quelque part dans le disque, s'éteint, puis renaît ailleurs ;
		-- au passage à portée, tous repartent ensemble
		local burst = c.flash > fx.flash
		fx.flash = c.flash
		for _, star in ipairs(fx.stars) do
			star.age = star.age + c.elapsed * Lerp(1, 1.5, ready)
			if burst or star.age >= star.life then
				local angle, reach = random() * TWO_PI, sqrt(random())
				star.x, star.y = cos(angle) * reach, sin(angle) * reach
				star.life = 0.7 + 0.9 * random()
				star.scale = 0.55 + 0.75 * random()
				star.age = burst and 0 or -0.5 * random()  -- hors de ces départs groupés, un temps de noir
			end
			local shine = star.age > 0 and sin(pi * star.age / star.life) or 0
			Place(star.texture, c.frame, star.x * size * 0.40, star.y * size * 0.40)
			Sized(star.texture, size * 0.55 * star.scale * (0.4 + 0.6 * shine) * (1 + 0.25 * ready))
			Tint(star.texture, c.wr, c.wg, c.wb, alpha * shine * Lerp(0.70, 1, ready) * (1 - locked))
		end
	end,
}

---------------------------------------------------------------------------
-- Faille : un trou noir cerclé de lumière, qui aspire des éclats en spirale
---------------------------------------------------------------------------

local SHARD_COUNT = 10

EFFECTS.rift = {
	band = "halo", wave = "ring", waveGain = 0.8,

	Build = function(fx, Layer)
		fx.shade = Layer("halo", "BACKGROUND", -1, "BLEND")
		fx.disc = Layer("swirl", "BACKGROUND")
		fx.inner = Layer("swirl", "ARTWORK")
		fx.hole = Layer("glow", "ARTWORK", 1, "BLEND")
		fx.rim = Layer("ring", "ARTWORK", 2)
		fx.shards = {}
		for i = 1, SHARD_COUNT do
			fx.shards[i] = { head = Layer("flare", "OVERLAY"), tail = Layer("glow", "OVERLAY"), t = i / SHARD_COUNT, angle = i * 2.4 }
		end
		fx.glint = Layer("flare", "OVERLAY", 1)
		fx.turn = 0
	end,

	Update = function(fx, c)
		local alpha, ready, locked, flash = c.alpha, c.ready, c.locked, c.flash
		local size = c.size * (1 + 0.40 * (1 - c.arrive))
		local speed = (Lerp(0.9, 1.9, ready) + 4.0 * flash) * (1 - 0.9 * locked)
		fx.turn = fx.turn + c.elapsed * speed
		fx.waveSize = size

		Sized(fx.shade, size * 1.2)
		Tint(fx.shade, 0, 0, 0, alpha * 0.35)
		-- le disque : deux nappes de bras qui tournent vite, la plus petite presque blanche
		Sized(fx.disc, size * (1.28 + 0.05 * c.breath))
		fx.disc:SetRotation(-fx.turn)
		Tint(fx.disc, c.r, c.g, c.b, alpha * Lerp(0.55, 0.90, ready))
		Sized(fx.inner, size * 0.82)
		fx.inner:SetRotation(1.0 - 2.3 * fx.turn)
		Tint(fx.inner, c.hr, c.hg, c.hb, alpha * Lerp(0.50, 0.95, ready) * (1 - 0.5 * locked))
		-- le trou : un noir plein, qui se contracte au passage à portée, et son anneau de lumière
		local hole = size * (0.66 - 0.14 * flash + 0.03 * c.breath)
		Sized(fx.hole, hole)
		Tint(fx.hole, 0, 0, 0, alpha * 0.97)
		Sized(fx.rim, hole * 0.62 * (1 + 0.03 * c.twinkle))
		Tint(fx.rim, c.wr, c.wg, c.wb, alpha * (Lerp(0.55, 1, ready) + 0.4 * flash) * (1 - 0.7 * locked))

		-- éclats : chacun naît au bord, tombe en spirale vers le trou en accélérant, et y disparaît
		for _, shard in ipairs(fx.shards) do
			shard.t = shard.t + c.elapsed * speed * 0.38
			if shard.t >= 1 then
				shard.t = shard.t - 1
				shard.angle = random() * TWO_PI
			end
			local t = shard.t
			local fall = t * t
			local radius = size * (0.70 * (1 - fall) + 0.10)
			local angle = shard.angle - 5.0 * fall
			local shine = min(t * 6, 1) * (1 - fall) ^ 0.4 * (1 - locked)
			Place(shard.head, c.frame, cos(angle) * radius, sin(angle) * radius)
			Sized(shard.head, size * (0.26 - 0.14 * t))
			shard.head:SetRotation(angle)
			Tint(shard.head, c.wr, c.wg, c.wb, alpha * shine)
			Place(shard.tail, c.frame, cos(angle + 0.22) * radius * 1.04, sin(angle + 0.22) * radius * 1.04)
			Sized(shard.tail, size * (0.16 - 0.08 * t))
			Tint(shard.tail, c.hr, c.hg, c.hb, alpha * shine * 0.7)
		end

		Sized(fx.glint, size * (0.24 + 0.12 * c.twinkle + 0.40 * flash))
		Place(fx.glint, c.frame, -hole * 0.21, hole * 0.21)
		fx.glint:SetRotation(0.4)
		Tint(fx.glint, c.wr, c.wg, c.wb, alpha * (Lerp(0.30, 0.90, ready) * c.twinkle + 0.5 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Foudre : un nuage d'orage se forme au-dessus de l'objet, et la foudre en tombe sur lui
---------------------------------------------------------------------------

-- Le nuage : des masses sombres qui se chevauchent et dérivent ; pour chacune sa place (en fractions de
-- la taille de l'effet, autour du milieu du nuage), sa largeur, sa hauteur
local BOLT_COUNT = 3
local CLOUD = {
	{ -0.36, -0.02, 0.62, 0.36 }, { -0.12, 0.07, 0.74, 0.46 }, { 0.14, 0.04, 0.70, 0.42 }, { 0.38, -0.03, 0.58, 0.34 },
	{ 0.00, -0.08, 0.86, 0.34 },
}

EFFECTS.storm = {
	wave = "ring", flat = GROUND, waveGain = 0.8,

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.core = Layer("glow", "ARTWORK")
		fx.bolts = {}
		for i = 1, BOLT_COUNT do
			fx.bolts[i] = { halo = Layer("bolt", "ARTWORK", 1), line = Layer("bolt", "ARTWORK", 2), age = 0, life = 0, pause = 0.6 + i * 0.9,
				from = 0, to = 0 }
		end
		-- le nuage passe devant le haut des éclairs, qui en sortent
		fx.cloud = {}
		for i = 1, #CLOUD do fx.cloud[i] = { dark = Layer("glow", "OVERLAY", 0, "BLEND"), lit = Layer("glow", "OVERLAY", 1) } end
		fx.flare = Layer("flare", "OVERLAY", 2)
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		local time = -c.spin
		-- le nuage descend se former au-dessus de l'objet
		local ceiling = foot + size * (1.25 + 0.5 * (1 - c.arrive) + 0.02 * sin(c.phase))
		fx.waveSize, fx.waveY = size * 1.0, foot

		-- la foudre : chaque éclair part d'un point du nuage et frappe près de l'objet, brille un instant,
		-- puis se tait un bon moment ; plus souvent à portée, et tous ensemble au passage à portée
		local strike = 0  -- l'éclat du plus vif des éclairs : le nuage, le sol et le cœur s'illuminent avec lui
		for _, bolt in ipairs(fx.bolts) do
			bolt.age = bolt.age + c.elapsed
			if bolt.age >= bolt.life + bolt.pause or flash > 0.92 and bolt.age > 0.05 then
				bolt.age = 0
				bolt.life = 0.16 + 0.14 * random()
				bolt.pause = Lerp(3.2, 1.6, ready) + random() * Lerp(4.0, 2.2, ready)
				bolt.from = (random() - 0.5) * size * 0.60
				bolt.to = (random() - 0.5) * size * 0.30
			end
			local shine = 0
			if bolt.age < bolt.life then
				shine = (1 - bolt.age / bolt.life) ^ 0.5 * (0.80 + 0.20 * random()) * c.arrive * (1 - locked)
			end
			strike = max(strike, shine)
			-- l'image de l'éclair va de son sommet à son pied : elle est tournée et étirée du nuage au sol
			local dx, dy = bolt.from - bolt.to, ceiling - foot
			local length = sqrt(dx * dx + dy * dy)
			local lean = atan2(dy, dx) - pi / 2
			local x, y = (bolt.from + bolt.to) / 2, (ceiling + foot) / 2
			Sized(bolt.halo, length * 0.62, length)
			Place(bolt.halo, c.frame, x, y)
			bolt.halo:SetRotation(lean)
			Tint(bolt.halo, c.r, c.g, c.b, alpha * shine)
			Sized(bolt.line, length * 0.50, length)
			Place(bolt.line, c.frame, x, y)
			bolt.line:SetRotation(lean)
			Tint(bolt.line, c.wr, c.wg, c.wb, alpha * shine)
		end

		-- le nuage : sombre, éclairé de l'intérieur dans la couleur de l'objet, et d'un coup à chaque éclair
		for i, puff in ipairs(fx.cloud) do
			local shape = CLOUD[i]
			local drift = sin(time * 0.35 + i * 1.9)
			local x, y = (shape[1] + 0.04 * drift) * size, ceiling + (shape[2] + 0.015 * sin(time * 0.5 + i)) * size
			-- (la tache de l'image n'en occupe que le centre : elle est donnée deux fois plus grande que la masse voulue)
			local width, height = shape[3] * size * (1.9 + 0.1 * drift), shape[4] * size * 1.9
			Sized(puff.dark, width, height)
			Place(puff.dark, c.frame, x, y)
			Tint(puff.dark, 0.05, 0.05, 0.07, alpha * 0.85 * (1 - 0.4 * locked))
			Sized(puff.lit, width * 0.80, height * 0.75)
			Place(puff.lit, c.frame, x, y - height * 0.05)
			Tint(puff.lit, c.r, c.g, c.b, alpha * (Lerp(0.16, 0.30, ready) * (0.8 + 0.2 * drift) + 0.75 * strike) * (1 - 0.7 * locked))
		end

		GroundShade(fx.shade, c, size * 2.4, foot)
		local pool = size * (1.10 + 0.10 * c.breath + 0.35 * strike)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * (Lerp(0.40, 0.65, ready) + 0.5 * strike))
		Sized(fx.core, size * (0.50 + 0.45 * strike))
		Place(fx.core, c.frame, 0, foot + size * 0.10)
		Tint(fx.core, c.hr, c.hg, c.hb, alpha * (Lerp(0.15, 0.30, ready) + 0.6 * strike) * (1 - 0.6 * locked))
		Sized(fx.flare, size * (0.20 + 0.55 * strike + 0.30 * flash))
		Place(fx.flare, c.frame, 0, foot + size * 0.04)
		Tint(fx.flare, c.wr, c.wg, c.wb, alpha * (0.20 * ready + strike + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Geyser : une fontaine d'éclats jaillit de l'objet et retombe autour de lui
---------------------------------------------------------------------------

local DROP_COUNT = 18

EFFECTS.geyser = {
	wave = "ring", flat = GROUND, waveGain = 0.7,

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.pool = Layer("glow", "BACKGROUND")
		fx.jet = Layer("beam", "ARTWORK")
		fx.core = Layer("beam", "ARTWORK", 1)
		fx.drops = {}
		for i = 1, DROP_COUNT do
			fx.drops[i] = { texture = Layer(i % 3 == 0 and "flare" or "glow", "OVERLAY"), t = i / DROP_COUNT,
				vx = (random() - 0.5) * 2.4, vy = 1.7 + 0.9 * random() }
		end
		fx.flare = Layer("flare", "OVERLAY", 1)
		fx.flash = 0
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		local force = (0.80 + 0.30 * ready + 0.40 * flash) * (0.4 + 0.6 * c.arrive)
		fx.waveSize, fx.waveY = size * 1.0, foot

		GroundShade(fx.shade, c, size * 2.4, foot)
		local pool = size * (1.20 + 0.10 * c.breath)
		Sized(fx.pool, pool, pool * GROUND * 1.3)
		Place(fx.pool, c.frame, 0, foot)
		Tint(fx.pool, c.r, c.g, c.b, alpha * Lerp(0.55, 0.90, ready))

		-- le jet : une colonne courte, qui bat
		local height = size * (0.85 + 0.12 * c.twinkle) * force * (1 - 0.6 * locked)
		Sized(fx.jet, size * 0.75, height)
		Place(fx.jet, c.frame, 0, foot + height / 2)
		Tint(fx.jet, c.r, c.g, c.b, alpha * Lerp(0.55, 0.90, ready))
		Sized(fx.core, size * 0.34, height * 0.9)
		Place(fx.core, c.frame, 0, foot + height * 0.45)
		Tint(fx.core, c.wr, c.wg, c.wb, alpha * Lerp(0.50, 0.95, ready) * (1 - 0.6 * locked))

		-- gouttes de lumière : lancées du pied, elles montent, s'écartent et retombent ; au passage à
		-- portée, toutes repartent ensemble
		local burst = flash > fx.flash
		fx.flash = flash
		for index, drop in ipairs(fx.drops) do
			drop.t = drop.t + c.elapsed / 1.5 * Lerp(0.8, 1.25, ready) * (1 - 0.8 * locked)
			if burst then drop.t = 1 + index / DROP_COUNT * 0.12 end
			if drop.t >= 1 then
				drop.t = drop.t - 1
				drop.vx, drop.vy = (random() - 0.5) * 2.4, 1.7 + 1.0 * random()
			end
			local t = drop.t
			local rise = (drop.vy * t - 2.7 * t * t) * force
			local landed = rise < 0
			Place(drop.texture, c.frame, drop.vx * t * size * 0.95, foot + max(rise, 0) * size * 0.95)
			Sized(drop.texture, size * (index % 3 == 0 and 0.34 or 0.15) * (1 - 0.5 * t))
			Tint(drop.texture, c.wr, c.wg, c.wb, alpha * (landed and 0 or min(t * 10, 1) * (1 - t) ^ 0.6) * (1 - locked))
		end

		Sized(fx.flare, size * (0.30 + 0.08 * ready + 0.05 * c.twinkle + 0.40 * flash))
		Place(fx.flare, c.frame, 0, foot + size * 0.03)
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.35, 0.90, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Esprit : deux feux follets dansent autour de l'objet en traînant un ruban de lumière
---------------------------------------------------------------------------

local SPIRITS, RIBBON = { { 0, 0.0, 1.00 }, { pi, 1.3, 0.72 } }, 24

EFFECTS.spirit = {
	band = "halo", wave = "ring", waveGain = 0.5,

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.haze = Layer("glow", "BACKGROUND")
		fx.spirits = {}
		for i = 1, #SPIRITS do
			local spirit = { ribbon = {} }
			for k = RIBBON, 1, -1 do spirit.ribbon[k] = Layer("glow", "ARTWORK") end
			spirit.body = Layer("glow", "OVERLAY")
			spirit.star = Layer("flare", "OVERLAY", 1)
			fx.spirits[i] = spirit
		end
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked = c.size, c.alpha, c.ready, c.locked
		local time = -c.spin * 1.5
		local reach = size * Lerp(0.66, 0.50, ready) * (1 + 0.6 * (1 - c.arrive)) * (1 - 0.35 * locked)
		fx.waveSize = size

		Sized(fx.shade, size * 2.0)
		Tint(fx.shade, 0, 0, 0, alpha * 0.26)
		Sized(fx.haze, size * (1.30 + 0.10 * c.breath))
		Tint(fx.haze, c.r, c.g, c.b, alpha * Lerp(0.30, 0.50, ready))

		-- chaque feu follet suit un huit couché autour de l'objet, passe devant lui puis derrière ; son
		-- ruban repasse par où il vient de passer
		for i, spirit in ipairs(fx.spirits) do
			local shape = SPIRITS[i]
			local function at(moment)
				local turn = moment + shape[1]
				local depth = cos(turn)
				return sin(turn) * reach * shape[3], (sin(2 * turn + shape[2]) * 0.42 + 0.10 * sin(moment * 0.7 + i)) * reach * shape[3], depth
			end
			local x, y, depth = at(time)
			local near = 1 + 0.25 * depth
			for k, texture in ipairs(spirit.ribbon) do
				local tx, ty, td = at(time - k * 0.04)
				Place(texture, c.frame, tx, ty)
				Sized(texture, size * 0.24 * shape[3] * (1 + 0.25 * td) * 0.95 ^ k)
				Tint(texture, c.hr, c.hg, c.hb, alpha * Lerp(0.50, 0.85, ready) * 0.90 ^ k * (1 - 0.5 * locked))
			end
			Place(spirit.body, c.frame, x, y)
			Sized(spirit.body, size * 0.34 * shape[3] * near)
			Tint(spirit.body, c.wr, c.wg, c.wb, alpha * Lerp(0.75, 1, ready))
			Place(spirit.star, c.frame, x, y)
			Sized(spirit.star, size * (0.46 + 0.14 * c.twinkle + 0.4 * c.flash) * shape[3] * near)
			spirit.star:SetRotation(time * 0.6 + i)
			Tint(spirit.star, c.wr, c.wg, c.wb, alpha * (Lerp(0.55, 1, ready) + 0.4 * c.flash) * (1 - 0.7 * locked))
		end
	end,
}

EFFECTS.rift.icon = { { "swirl", 1.1, 1.1, 0, 0, 1 }, { "ring", 0.5, 0.5, 0, 0, 1, true }, { "flare", 0.3, 0.3, -0.3, 0.26, 0.9, true },
	{ "flare", 0.22, 0.22, 0.3, -0.22, 0.8, true } }
EFFECTS.storm.icon = { { "glow", 1, 0.5, 0, -0.34, 0.8 }, { "bolt", 0.44, 0.8, -0.06, -0.08, 1, true }, { "glow", 0.8, 0.5, -0.14, 0.3, 0.5 },
	{ "glow", 0.8, 0.5, 0.16, 0.32, 0.45 } }
EFFECTS.geyser.icon = { { "glow", 1, 0.5, 0, -0.32, 0.9 }, { "beam", 0.5, 0.7, 0, -0.1, 1 }, { "glow", 0.2, 0.2, -0.26, 0.2, 1, true },
	{ "glow", 0.18, 0.18, 0.28, 0.12, 1, true }, { "flare", 0.34, 0.34, 0.06, 0.3, 1, true }, { "glow", 0.14, 0.14, -0.36, -0.08, 0.8, true } }
EFFECTS.spirit.icon = { { "glow", 0.9, 0.9, 0, 0, 0.35 }, { "arcs", 0.95, 0.95, 0, 0, 1 }, { "flare", 0.42, 0.42, -0.41, 0.03, 1, true },
	{ "flare", 0.36, 0.36, 0.41, -0.03, 1, true } }
