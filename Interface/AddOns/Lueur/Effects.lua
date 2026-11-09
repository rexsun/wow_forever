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

local sin, cos, min, max, sqrt, random, pi = math.sin, math.cos, math.min, math.max, math.sqrt, math.random, math.pi
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
ns.EFFECT_ORDER = { "aura", "reticle", "subtle", "sigil", "brackets", "beam", "beacon", "orbit", "ripple", "sparkle" }

---------------------------------------------------------------------------
-- Halos : une même construction, dont chaque variante pèse les couches à sa façon
---------------------------------------------------------------------------

local MOTE_COUNT = 3

local function Halo(weight)
	return {
		band = "halo", wave = "ring", waveGain = weight.waves,

		Build = function(fx, Layer)
			fx.shade = Layer("halo", "BACKGROUND", -1, "BLEND")
			fx.band = Layer("halo", "BACKGROUND")
			fx.ring = Layer("ring", "ARTWORK")
			fx.arcs = Layer("arcs", "ARTWORK", 1)
			fx.motes = {}
			for i = 1, MOTE_COUNT do fx.motes[i] = Layer("glow", "OVERLAY") end
			fx.flare = Layer("flare", "OVERLAY", 1)
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

EFFECTS.aura    = Halo({ shade = 1.0, band = 1.00, ring = 0.80, arcs = 0.90, flare = 0.90, motes = 1, waves = 1.0 })
EFFECTS.reticle = Halo({ shade = 0.6, band = 0.35, ring = 1.00, arcs = 1.00, flare = 0.00, motes = 0, waves = 1.0 })
EFFECTS.subtle  = Halo({ shade = 0.8, band = 0.80, ring = 0.00, arcs = 0.00, flare = 0.50, motes = 0, waves = 0.4 })
EFFECTS.aura.icon = { { "halo", 1, 1, 0, 0, 0.9 }, { "ring", 1, 1, 0, 0, 0.9 }, { "flare", 0.55, 0.55, 0, 0, 1, true } }
EFFECTS.reticle.icon = { { "halo", 1, 1, 0, 0, 0.3 }, { "ring", 1, 1, 0, 0, 1 }, { "arcs", 1, 1, 0, 0, 1, true } }
EFFECTS.subtle.icon = { { "halo", 1, 1, 0, 0, 0.9 }, { "flare", 0.32, 0.32, 0, 0, 0.6, true } }
-- Sert quand les images d'un effet sont introuvables (dossier Media incomplet, ou jeu pas
-- relancé après l'installation) : chaque couche porte alors une texture du jeu.
EFFECTS.fallback = Halo({ shade = 0.0, band = 1.00, ring = 0.00, arcs = 0.00, flare = 1.00, motes = 0, waves = 0.0 })

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
-- Viseur : quatre coins en losange, qui pivotent et se referment en cadre à portée
---------------------------------------------------------------------------

EFFECTS.brackets = {
	wave = "brackets", waveGain = 0.7,
	icon = { { "glow", 1, 1, 0, 0, 0.45 }, { "brackets", 0.92, 0.92, 0, 0, 1 }, { "flare", 0.34, 0.34, 0, 0, 0.9, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.haze = Layer("glow", "BACKGROUND")
		fx.corners = Layer("brackets", "ARTWORK")
		fx.ring = Layer("ring", "ARTWORK", 1)
		fx.flare = Layer("flare", "OVERLAY")
	end,

	Update = function(fx, c)
		local alpha, ready, locked, flash = c.alpha, c.ready, c.locked, c.flash
		local lock = ready * ready * (3 - 2 * ready)
		local angle = (1 - lock) * pi / 4
		local size = c.size * (Lerp(0.92, 0.86, lock) + 0.03 * c.breath * (1 - lock) + 0.40 * (1 - c.arrive))
		fx.waveSize, fx.waveAngle = size, angle

		Sized(fx.shade, size * 2.0)
		Tint(fx.shade, 0, 0, 0, alpha * 0.30)
		Sized(fx.haze, size * (1.5 + 0.1 * c.breath))
		Tint(fx.haze, c.r, c.g, c.b, alpha * Lerp(0.30, 0.50, ready))

		Sized(fx.corners, size)
		fx.corners:SetRotation(angle)
		Tint(fx.corners, c.hr, c.hg, c.hb, alpha * (Lerp(0.60, 0.95, ready) + 0.25 * flash))

		-- la mise au point : un anneau fin et un éclat, qui n'apparaissent qu'à portée
		Sized(fx.ring, size * Lerp(0.90, 0.58, lock))
		Tint(fx.ring, c.hr, c.hg, c.hb, alpha * 0.55 * ready * (1 - locked))
		Sized(fx.flare, size * (0.22 + 0.10 * ready + 0.04 * c.twinkle + 0.30 * flash))
		Tint(fx.flare, c.wr, c.wg, c.wb, alpha * (0.85 * ready * (0.7 + 0.3 * c.twinkle) + 0.4 * flash) * (1 - locked))
	end,
}

---------------------------------------------------------------------------
-- Faisceau : une colonne de lumière qui s'élève de l'objet
---------------------------------------------------------------------------

local SPARK_COUNT = 4

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
		fx.flare = Layer("flare", "OVERLAY", 1)
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked, flash = c.size, c.alpha, c.ready, c.locked, c.flash
		local foot = FOOT * size
		-- le faisceau jaillit du sol à l'arrivée, s'allonge à portée, retombe sur un objet indisponible
		local height = size * (1.30 + 0.30 * ready + 0.20 * flash) * (0.25 + 0.75 * c.arrive) * (1 - 0.40 * locked)
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
-- Orbite : des feux follets tournent autour de l'objet, au ras du sol
---------------------------------------------------------------------------

local WISP_COUNT, TAIL_LENGTH = 3, 8

EFFECTS.orbit = {
	wave = "ring", flat = GROUND, waveGain = 0.6,
	icon = { { "ring", 1, 0.46, 0, 0, 0.5 }, { "glow", 0.32, 0.32, -0.33, 0.03, 1, true }, { "glow", 0.3, 0.3, 0.3, -0.1, 1, true },
		{ "glow", 0.2, 0.2, 0.12, 0.14, 0.7 }, { "flare", 0.3, 0.3, 0, 0, 0.6, true } },

	Build = function(fx, Layer)
		fx.shade = Layer("glow", "BACKGROUND", -1, "BLEND")
		fx.core = Layer("glow", "BACKGROUND")
		fx.path = Layer("ring", "BACKGROUND", 1)
		fx.wisps = {}
		for i = 1, WISP_COUNT do
			local wisp = {}
			for k = TAIL_LENGTH, 0, -1 do wisp[k] = Layer("glow", "OVERLAY", k == 0 and 1 or 0) end
			fx.wisps[i] = wisp
		end
		fx.flare = Layer("flare", "ARTWORK")
	end,

	Update = function(fx, c)
		local size, alpha, ready, locked = c.size, c.alpha, c.ready, c.locked
		-- l'orbite se resserre en arrivant, puis encore un peu à portée
		local radius = size * Lerp(0.46, 0.40, ready) * (1 + 0.6 * (1 - c.arrive))
		local travel = -2 * c.spin
		fx.waveSize = radius / RING_ORBIT

		GroundShade(fx.shade, c, radius * 4.6, 0)
		Sized(fx.core, size * (0.95 + 0.08 * c.breath))
		Tint(fx.core, c.r, c.g, c.b, alpha * Lerp(0.35, 0.60, ready))
		Sized(fx.path, radius / RING_ORBIT, radius / RING_ORBIT * GROUND)
		Tint(fx.path, c.hr, c.hg, c.hb, alpha * Lerp(0.16, 0.30, ready))

		for i, wisp in ipairs(fx.wisps) do
			local head = travel + i * TWO_PI / WISP_COUNT
			local lift = size * 0.03 * sin(c.phase + i * 2.1)
			for k = 0, TAIL_LENGTH do
				local angle = head - k * 0.07
				local depth = -sin(angle)  -- 1 : devant l'objet, -1 : derrière lui, plus petit et plus pâle
				local texture = wisp[k]
				Place(texture, c.frame, cos(angle) * radius, sin(angle) * radius * GROUND + lift)
				Sized(texture, size * (k == 0 and 0.20 or 0.17) * (1 + 0.28 * depth) * 0.90 ^ k)
				if k == 0 then
					Tint(texture, c.wr, c.wg, c.wb, alpha * (0.66 + 0.34 * depth) * Lerp(0.70, 1, ready))
				else
					Tint(texture, c.hr, c.hg, c.hb, alpha * (0.66 + 0.34 * depth) * Lerp(0.50, 0.85, ready) * 0.78 ^ k * (1 - locked))
				end
			end
		end

		Sized(fx.flare, size * (0.22 + 0.08 * ready + 0.04 * c.twinkle + 0.30 * c.flash))
		Tint(fx.flare, c.wr, c.wg, c.wb,
			alpha * (Lerp(0.15, 0.70, ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash) * (1 - locked))
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
