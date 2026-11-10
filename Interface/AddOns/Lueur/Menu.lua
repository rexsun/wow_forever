-- Lueur : menu des réglages et bouton de la minimap
-- Le menu ne fait qu'afficher les réglages et demander leur changement : tout passe par les
-- fonctions que Lueur.lua expose dans la table de l'addon, comme pour les commandes /lueur.
-- Un contrôle ne garde pas son texte mais le nom de ce texte : "SIZE" pour son libellé, et
-- d'office "SIZE_TIP" pour son infobulle. La fenêtre change ainsi de langue sans se refaire.
--
-- La fenêtre a l'allure de celle des métiers (Skin.lua) et trois pages, que choisissent les
-- onglets de son bord droit. La première est une cabine d'essayage : en haut les objets que Lueur
-- met en lumière, chacun avec son icône, sa case et sa couleur ; dessous, à gauche l'aperçu de
-- ceux que l'on y choisit (Preview.lua), à droite leur apparence. La deuxième règle les icônes
-- des filons et des plantes sur la minimap (NodeScan.lua). La troisième réunit le reste :
-- détection, réglages généraux, masquage, silhouette.

local ADDON_NAME, ns = ...
local L = ns.L
local Skin = ns.Skin
if not Skin then
	-- Skin.lua est arrivé avec une mise à jour, et le jeu ne charge un nouveau fichier qu'à son
	-- lancement : d'ici là pas de fenêtre, et /lueur dit pourquoi
	function ns.ToggleMenu() ns.Print(L.MSG_RESTART) end
	Lueur_OnAddonCompartmentClick = ns.ToggleMenu
	return
end

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local ICONS = "Interface\\Icons\\"
local FALLBACK_ICON = "Interface\\Cooldown\\star4"

local WIDTH, HEIGHT = 800, 658
local EDGE = 12               -- marge entre le cadre de la fenêtre et ses panneaux
local TOP, FOOT = 62, 42      -- ce que la fenêtre garde au-dessus des panneaux (son portrait) et dessous (ses boutons)
local GAP = 6                 -- espace entre deux panneaux
local PAD = 16                -- marge intérieure d'un panneau
local STRIP = 76              -- hauteur du bandeau des objets, en haut de leur page
local VIEW = 300              -- largeur du panneau de l'aperçu, sous lui
local SLOT = 40               -- côté d'un bouton d'icône : celui des boutons de sort du jeu, dont il porte le liseré
local ROW = 30                -- hauteur d'une ligne de case à cocher (la case en fait 29)
local RADIO_ROW = 22          -- hauteur d'une ligne de boutons radio
local PER_ROW = 5             -- effets par ligne
local VALUE = 46              -- place de la valeur d'un curseur, à sa droite
local CONFIRM_TIME = 4        -- secondes laissées pour confirmer la remise à zéro
local BUTTON_RADIUS = 5       -- écart entre le bord de la minimap et le centre du bouton, comme les autres addons

-- Icône de chaque catégorie dans la liste des objets : des icônes de métier et d'objet du jeu
local CATEGORY_ICONS = {
	ore = "Trade_Mining", herb = "Trade_Herbalism", quest = "INV_Misc_Note_01", chest = "INV_Box_01",
	bobber = "Trade_Fishing", other = "INV_Misc_Gear_01",
}
local SETTINGS_ICON = "Trade_Engineering"
local NODES_ICON = "INV_Misc_Map_01"
local SWITCH_HEIGHT = 160     -- hauteur du panneau de l'alternance des pistages, sur la page de la minimap
local SAMPLE = 190            -- diamètre du disque où cette page montre des icônes témoins

-- Les icônes témoins : objet donné par le nœud, métier, difficulté, dans une grotte ou non, et leur
-- place sur le disque (en fractions de son rayon)
local SAMPLES = {
	{ 2447, "herb", "trivial", false, -0.42, 0.44 }, { 765, "herb", "easy", false, 0.30, 0.52 },
	{ 2770, "ore", "fair", false, 0.58, -0.08 }, { 2771, "ore", "difficult", false, -0.08, -0.02 },
	{ 2772, "ore", "impossible", false, -0.56, -0.30 }, { 2450, "herb", "fair", true, 0.20, -0.56 },
}

-- Titre de chaque page sous la barre de titre ; celle des objets compose le sien (LookTitle)
local PAGE_TITLES = { nodes = "NODES_PAGE", settings = "SETTINGS" }

-- Choix d'un réglage : { valeur, nom du texte } ; ou { valeur, nil, libellé } quand le libellé
-- ne se traduit pas
local ARC_CHOICES = { { 0, "ARC_0" }, { 1, "ARC_1" }, { 2, "ARC_2" } }

local menu                    -- fenêtre des réglages, créée à sa première ouverture
local minimapButton
local pages = {}              -- nom d'une page ("look", "nodes", "settings") -> son cadre
local refreshers = {}         -- une fonction par contrôle, qui le remet en accord avec les réglages
local captions = {}           -- une fonction par texte fixe de la fenêtre, qui le pose dans la langue courante
local refreshing = false      -- pendant ce temps, un curseur qui bouge ne doit rien régler

local blockClick = 0          -- frames pendant lesquelles les clics sur le bouton de touche sont ignorés
local keybindButton           -- référence au bouton de key binding
local openPage = "look"       -- page montrée : "look" (les objets et leur apparence), "nodes" (la minimap) ou "settings"
local effectScope = "all"     -- catégorie dont la page règle l'effet et l'apparence, ou "all" pour tous les objets

-- La catégorie que le menu personnalise ; nil : tous les objets
local function ScopeCategory()
	return effectScope ~= "all" and effectScope or nil
end

-- La lumière seule (Plumber, ou le réglage) : Lueur n'écrit ni nom ni icône
local function Bare()
	return ns.GlowBare ~= nil and ns.GlowBare() == true
end

-- Couleur des dessins d'effet : celle de la catégorie que la page règle, l'or des titres du
-- jeu quand elle règle tous les objets
local function LookColor()
	local category = ScopeCategory()
	if category then return ns.GetColor(category) end
	return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- Contrôles
---------------------------------------------------------------------------

-- Donne à une région le texte de ce nom, maintenant et à chaque changement de langue.
-- `after` est appelée ensuite, pour ce qui dépend de la place que prend le texte.
local function Caption(region, name, after)
	local function Apply()
		region:SetText(L[name])
		if after then after() end
	end
	captions[#captions + 1] = Apply
	Apply()
end

-- Infobulle d'un contrôle : le texte de ce nom et, dessous, son explication, relus à chaque
-- survol. Un titre donné tel quel, parce qu'il ne se traduit pas, vient sans explication.
local function SetTooltip(frame, name, title)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, title or L[name])
		if not title then GameTooltip_AddNormalLine(GameTooltip, L[name .. "_TIP"]) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function Dim(fontString, available, r, g, b)
	if available then fontString:SetTextColor(r, g, b) else fontString:SetTextColor(0.5, 0.5, 0.5) end
end

-- Lecture et écriture d'un réglage de Lueur, pour un contrôle
local function Getter(key)
	return function() return ns.GetOption(key) end
end

local function Setter(key)
	return function(value) ns.SetOption(key, value) end
end

-- Les mêmes pour un réglage de personnalisation : il se lit et se change pour les objets que
-- désigne le menu, tous ou une catégorie
local function ScopedGetter(key)
	return function() return ns.GetOption(key, ScopeCategory()) end
end

local function ScopedSetter(key)
	return function(value) ns.SetOption(key, value, ScopeCategory()) end
end

-- Pose un panneau sur une page. Renvoie la colonne où se rangent ses contrôles : chacun se
-- pose en `y`, puis l'abaisse. `name` nomme le titre du panneau, s'il en a un.
local function NewCard(page, x, y, width, height, name)
	local card = Skin.Card(page, width, height)
	card:SetPoint("TOPLEFT", x, y)
	local column = { parent = card, x = PAD, width = width - 2 * PAD, y = -14 }
	if name then
		local title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		title:SetPoint("TOPLEFT", column.x, column.y)
		Caption(title, name)
		column.y = column.y - 26
	end
	return column
end

-- Case à cocher, suivie de son nom, qui se clique aussi
local function AddCheckbox(column, name, get, set)
	local check = CreateFrame("CheckButton", nil, column.parent, "MinimalCheckboxTemplate")
	check:SetPoint("TOPLEFT", column.x - 3, column.y + 1)
	column.y = column.y - ROW
	local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 1, 0)
	Caption(label, name, function()
		check:SetHitRectInsets(0, -(label:GetStringWidth() + 3), 0, 0)
	end)
	check:SetScript("OnClick", function(self)
		local checked = self:GetChecked()
		PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		set(checked)
	end)
	SetTooltip(check, name)
	local available = true
	function check:SetAvailable(value)
		if value == available then return end
		available = value
		self:SetEnabled(value)
		Dim(label, available, 1, 1, 1)
	end
	refreshers[#refreshers + 1] = function() check:SetChecked(get()) end
	return check
end

-- Case à cocher d'un réglage oui/non de Lueur ; `scoped` : un réglage de personnalisation
local function AddOption(column, name, key, scoped)
	return AddCheckbox(column, name, (scoped and ScopedGetter or Getter)(key), (scoped and ScopedSetter or Setter)(key))
end

-- Curseur d'un réglage numérique : son nom et sa valeur sur une ligne, le curseur dessous ;
-- avec `inline`, largeur donnée au curseur, tout tient sur une ligne, le curseur entre le nom
-- et la valeur, et ces lignes se touchent dans un panneau `tight`. `pattern` nomme le format
-- de la valeur, qui dépend de la langue ; sans lui, le nombre seul. `scoped` : un réglage de
-- personnalisation.
local function AddSlider(column, name, key, pattern, scoped, inline)
	local limits = ns.LIMITS[key]
	local get, set = (scoped and ScopedGetter or Getter)(key), (scoped and ScopedSetter or Setter)(key)
	local function Format(number)
		return (pattern and L[pattern] or "%d"):format(number)
	end
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, inline and 28 or 40)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - (inline and (column.tight and 28 or 32) or 44)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	local value = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	if inline then
		label:SetPoint("LEFT", 0, 0)
		value:SetPoint("RIGHT", 0, 0)
		slider:SetSize(inline, 20)
		slider:SetPoint("RIGHT", -VALUE, 0)
	else
		label:SetPoint("TOPLEFT", 0, -3)
		value:SetPoint("TOPRIGHT", 0, -3)
		slider:SetSize(column.width, 20)
		slider:SetPoint("BOTTOMLEFT", 0, 0)
	end
	Caption(label, name)
	slider:Init(get(), limits[1], limits[2], limits[2] - limits[1])
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, number)
		number = math.floor(number + 0.5)
		value:SetText(Format(number))
		if not refreshing and number ~= get() then set(number) end
	end, row)
	SetTooltip(row, name)
	SetTooltip(slider.Slider, name)
	row.slider = slider
	local wasAvailable
	function row:SetAvailable(available)
		if available == wasAvailable then return end -- ne pas toucher à un curseur en cours de glissement
		wasAvailable = available
		slider:SetEnabled(available)
		Dim(label, available, 1, 1, 1)
		Dim(value, available, 1, 0.82, 0)
	end
	refreshers[#refreshers + 1] = function()
		slider:SetValue(get())
		value:SetText(Format(get()))
	end
	return row
end

-- Police du nom des objets, une à la fois, entre les flèches d'un curseur du jeu dont la barre
-- est cachée : son nom s'y écrit dans la police même. Sur la ligne, comme un curseur `inline`.
local function AddFont(column, name, width)
	local get, set = ScopedGetter("textFont"), ScopedSetter("textFont")
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 28)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - (column.tight and 28 or 32)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", 0, 0)
	Caption(label, name)
	local stepper = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	stepper:SetSize(width, 20)
	stepper:SetPoint("RIGHT", -VALUE, 0)
	stepper.Slider:Hide()
	local text = stepper:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("CENTER", stepper.Slider, "CENTER", 0, 0)
	local font, height, flags = text:GetFont()
	local list = ns.FontChoices()
	local function Show(key)
		text:SetText(ns.FontName(key) or L.FONT_GAME)
		local file, ok, done = ns.FontFile(key)
		if file then ok, done = pcall(text.SetFont, text, file, height, flags) end
		if not (ok and done ~= false) and font then text:SetFont(font, height, flags) end
	end
	-- un client qui n'a que la police du jeu garde deux crans, et la ligne grisée
	stepper:Init(1, 1, math.max(#list, 2), math.max(#list, 2) - 1)
	stepper:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, number)
		local key = list[math.floor(number + 0.5)]
		if not key then return end
		Show(key)
		if not refreshing and key ~= get() then set(key) end
	end, row)
	SetTooltip(row, name)
	row.slider = stepper
	local wasAvailable
	function row:SetAvailable(available)
		if available == wasAvailable then return end
		wasAvailable = available
		stepper:SetEnabled(available)
		Dim(label, available, 1, 1, 1)
		Dim(text, available, 1, 0.82, 0)
	end
	refreshers[#refreshers + 1] = function()
		local key = get()
		for index, choice in ipairs(list) do
			if choice == key then stepper:SetValue(index) end
		end
		Show(key)
		row:SetAvailable(#list > 1 and ns.GetOption("showName", ScopeCategory()) and not Bare())
	end
	return row
end

-- Choix entre quelques valeurs, par des boutons radio rangés `perRow` par ligne sous le nom
-- du choix ; `get` donne la valeur en place, `set` reçoit celle qui est choisie
local function AddChoice(column, name, choices, get, set, perRow)
	local top = 22
	local height = top + math.ceil(#choices / perRow) * RADIO_ROW
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, height - 4)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - height
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 0, -3)
	Caption(label, name)
	SetTooltip(row, name)
	local radios = {}
	for index, choice in ipairs(choices) do
		local radio = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
		radio:SetPoint("TOPLEFT", (index - 1) % perRow * column.width / perRow + 2, -top - math.floor((index - 1) / perRow) * RADIO_ROW)
		radio.text:SetFontObject(GameFontHighlight)
		local function Fit()
			radio:SetHitRectInsets(0, -(radio.text:GetStringWidth() + 5), 0, 0) -- le texte se clique aussi
		end
		if choice[2] then
			Caption(radio.text, choice[2], Fit)
			SetTooltip(radio, choice[2])
		else
			radio.text:SetText(choice[3])
			Fit()
			SetTooltip(radio, nil, choice[3])
		end
		radio:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			set(choice[1]) -- le rafraîchissement qui suit coche le bon bouton
		end)
		radios[index] = radio
	end
	refreshers[#refreshers + 1] = function()
		local current = get()
		for index, choice in ipairs(choices) do radios[index]:SetChecked(current == choice[1]) end
	end
	return row
end

-- Choix de l'effet : un bouton d'icône par effet, qui en porte le dessin (`icon`, dans
-- Effects.lua) dans la couleur des objets que la page règle, et son nom dessous
local function AddEffects(column)
	local cell = column.width / PER_ROW
	local lines = math.ceil(#ns.EFFECT_ORDER / PER_ROW)
	local top, pitch = 24, SLOT + 18
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, top + lines * pitch - 4)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - top - lines * pitch
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", 0, -2)
	Caption(label, "EFFECT")
	SetTooltip(row, "EFFECT")
	local get, set = ScopedGetter("effect"), ScopedSetter("effect")
	local buttons, layers = {}, {}
	for index, key in ipairs(ns.EFFECT_ORDER) do
		local name = "EFFECT_" .. key:upper()
		local button = Skin.IconButton(row, SLOT)
		button:SetPoint("TOP", row, "TOPLEFT", ((index - 1) % PER_ROW + 0.5) * cell, -top - math.floor((index - 1) / PER_ROW) * pitch)
		button.effect = key
		local side = SLOT - 8 -- le dessin tient dans l'emplacement, à l'écart de son liseré
		for depth, layer in ipairs(ns.EFFECTS[key].icon or {}) do
			local texture = button:CreateTexture(nil, "ARTWORK", nil, depth)
			if texture:SetTexture(MEDIA .. layer[1] .. ".tga") == false then texture:Hide() end
			texture:SetBlendMode("ADD")
			texture:SetSize(layer[2] * side, layer[3] * side)
			texture:SetPoint("CENTER", layer[4] * side, layer[5] * side)
			layers[#layers + 1] = { texture = texture, alpha = layer[6], hot = layer[7] }
		end
		local title = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		title:SetPoint("TOP", button, "BOTTOM", 0, 0)
		Caption(title, name)
		button:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			set(key) -- le rafraîchissement qui suit coche le bon bouton
		end)
		SetTooltip(button, name)
		buttons[key] = button
	end
	refreshers[#refreshers + 1] = function()
		local current = get()
		for key, button in pairs(buttons) do button:SetChecked(key == current) end
		local r, g, b = LookColor()
		for _, layer in ipairs(layers) do
			if layer.hot then
				layer.texture:SetVertexColor(0.5 + 0.5 * r, 0.5 + 0.5 * g, 0.5 + 0.5 * b, layer.alpha)
			else
				layer.texture:SetVertexColor(r, g, b, layer.alpha)
			end
		end
	end
end

-- Filet entre deux groupes de contrôles d'un panneau : celui des infobulles du jeu
local function AddDivider(column)
	local line = column.parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
	line:SetSize(column.width, 8)
	line:SetPoint("TOPLEFT", column.x, column.y)
	line:SetAlpha(0.7)
	column.y = column.y - 8
end

local function AddButton(parent, name, onClick, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 130, 22)
	Caption(button, name)
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		onClick()
	end)
	SetTooltip(button, name)
	return button
end


-- Change le texte d'un bouton, sans y toucher quand il est déjà le bon
local function SetLabel(button, text)
	if button:GetText() ~= text then button:SetText(text) end
end

-- Ouvre le sélecteur de couleur du jeu sur la couleur d'une catégorie : elle suit le sélecteur
-- en direct, et lui revient s'il est annulé
local function PickColor(key)
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
		ns.Print(L.MSG_NO_PICKER)
		return
	end
	local r, g, b = ns.GetColor(key)
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, hasOpacity = false,
		swatchFunc = function() ns.SetColor(key, ColorPickerFrame:GetColorRGB()) end,
		cancelFunc = function(previous) ns.SetColor(key, previous.r, previous.g, previous.b) end,
	})
end

-- Pastille de la couleur d'une catégorie. Un clic gauche ouvre le sélecteur de couleur, un clic
-- droit rend la couleur d'origine. `swatch.fill` est son aplat.
local function AddSwatch(parent, key)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)
	swatch:RegisterForClicks("AnyUp")
	-- un liseré de bronze, un filet noir, puis l'aplat : comme sertie
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.62, 0.56, 0.46, 1)
	local groove = swatch:CreateTexture(nil, "BORDER")
	groove:SetPoint("TOPLEFT", 1, -1)
	groove:SetSize(16, 16)
	groove:SetColorTexture(0, 0, 0, 1)
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetSize(14, 14)
	swatch.fill = fill
	swatch:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	swatch:SetScript("OnClick", function(_, mouseButton)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if mouseButton == "RightButton" then ns.SetColor(key) else PickColor(key) end
	end)
	swatch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.COLOR)
		GameTooltip_AddNormalLine(GameTooltip, L.COLOR_TIP)
		GameTooltip_AddInstructionLine(GameTooltip, L.TIP_COLOR_SET)
		GameTooltip_AddInstructionLine(GameTooltip, L.TIP_COLOR_RESET)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
	refreshers[#refreshers + 1] = function() fill:SetColorTexture(ns.GetColor(key)) end
	return swatch
end

-- Objets écartés par leur nom : leur nombre à gauche et, à son survol, leurs noms ; à droite, le
-- bouton qui écarte l'objet visé en ce moment, ou cesse de l'écarter
local function AddIgnore(column)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 26)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - ROW
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", 0, 0)
	row:SetScript("OnEnter", function(self)
		local names = ns.IgnoredNames()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.IGNORED:format(#names))
		GameTooltip_AddNormalLine(GameTooltip, L.IGNORED_TIP)
		for index = 1, math.min(#names, 12) do GameTooltip_AddInstructionLine(GameTooltip, names[index]) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local button = AddButton(row, "IGNORE_TARGET", ns.IgnoreTarget, 150)
	button:SetPoint("RIGHT", 0, 0)
	refreshers[#refreshers + 1] = function() label:SetText(L.IGNORED:format(#ns.IgnoredNames())) end
end

-- Touches qui ne font pas un raccourci à elles seules
local MODIFIER_KEYS = {
	LALT = true, RALT = true, ALT = true, LCTRL = true, RCTRL = true, CTRL = true, LSHIFT = true, RSHIFT = true, SHIFT = true,
	LMETA = true, RMETA = true, META = true, UNKNOWN = true,
}

-- Renvoie la touche précédée des touches de modification tenues ("SHIFT-E"), dans l'ordre
-- qu'attend le jeu ; nil pour une touche de modification seule
local function KeyChord(key)
	if MODIFIER_KEYS[key] then return nil end
	local chord = ""
	if IsAltKeyDown() then chord = chord .. "ALT-" end
	if IsControlKeyDown() then chord = chord .. "CTRL-" end
	if IsShiftKeyDown() then chord = chord .. "SHIFT-" end
	if IsMetaKeyDown and IsMetaKeyDown() then chord = chord .. "META-" end
	return chord .. key
end

-- Renvoie le nom que porte dans un raccourci un bouton de souris reçu par OnClick, hors
-- boutons gauche et droit, qui ne s'assignent pas
local function MouseKey(mouseButton)
	if mouseButton == "MiddleButton" then return "BUTTON3" end
	local number = mouseButton:match("^Button(%d+)$")
	return number and "BUTTON" .. number
end

-- Touche d'interaction : son nom à gauche, à droite un bouton qui l'affiche. Un clic gauche
-- sur le bouton attend la prochaine touche (ou bouton de souris, ou cran de molette), Échap
-- annule ; un clic droit retire la touche. Une touche qui sert déjà à un autre raccourci du
-- jeu doit être pressée une seconde fois pour lui être prise. Renvoie de quoi interrompre
-- l'attente d'une touche.
local function AddKeybind(column, name)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 26)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - ROW
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", 0, 0)
	Caption(label, name)
	SetTooltip(row, name)

	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(150, 22)
	button:SetPoint("RIGHT", 0, 0)
	button:RegisterForClicks("AnyUp")
	button:EnableKeyboard(false) -- ne pas capter de touches tant qu'on n'écoute pas
	keybindButton = button
	local listening = false  -- le bouton attend une touche
	local contested          -- touche qui sert déjà ailleurs, en attente d'une seconde pression

	local function ShowTooltip()
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L[name])
		if contested then
			GameTooltip_AddNormalLine(GameTooltip, L.KEY_TAKEN:format(ns.KeyText(contested), ns.KeyOwner(contested) or "?"))
		elseif listening then
			GameTooltip_AddNormalLine(GameTooltip, L.KEY_LISTEN_TIP)
		else
			GameTooltip_AddNormalLine(GameTooltip, L[name .. "_TIP"])
			GameTooltip_AddInstructionLine(GameTooltip, L.TIP_KEY_SET)
			GameTooltip_AddInstructionLine(GameTooltip, L.TIP_KEY_CLEAR)
		end
		GameTooltip:Show()
	end

	local function Update()
		local key = ns.GetInteractKey()
		SetLabel(button, contested and L.CONFIRM or listening and L.KEY_LISTEN or key and ns.KeyText(key) or L.KEY_NONE)
		if button:IsMouseOver() then ShowTooltip() end
	end

	-- Tant qu'il attend une touche, le bouton garde pour lui le clavier et la molette
	local function Listen(on)
		listening, contested = on, nil
		button:EnableKeyboard(on)
		button:EnableMouseWheel(on)
		Update()
	end

	local function Assign(key)
		local owner = key and ns.KeyOwner(key)
		local changed, reason = ns.SetInteractKey(key)
		if not changed then
			ns.Print(reason)
		elseif owner then
			ns.Print(L.MSG_KEY_REPLACED:format(ns.KeyText(key), owner))
		end
	end

	local function Press(key)
		if key == "ESCAPE" then Listen(false) return end
		local chord = KeyChord(key)
		if not chord then return end
		if chord ~= contested and ns.KeyOwner(chord) then
			contested = chord
			ns.Print(L.KEY_TAKEN:format(ns.KeyText(chord), ns.KeyOwner(chord)))
			Update()
			return
		end
		Listen(false)
		Assign(chord)
	end

	button:SetScript("OnKeyDown", function(_, key) Press(key) end)
	button:SetScript("OnMouseWheel", function(_, delta) Press(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
	button:SetScript("OnClick", function(self, mouseButton)
		if blockClick > 0 or not self:IsMouseOver() then return end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		local mouseKey = MouseKey(mouseButton)
		if listening then
			if mouseKey then Press(mouseKey) else Listen(false) end
		elseif mouseButton == "RightButton" then
			Assign(nil)
		elseif mouseButton == "LeftButton" then
			if InCombatLockdown() then ns.Print(L.MSG_KEY_COMBAT) else Listen(true) end
		end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnEvent", Update) -- raccourcis changés ailleurs, dans les options du jeu par exemple
	button:RegisterEvent("UPDATE_BINDINGS")
	refreshers[#refreshers + 1] = Update
	-- pour la fermeture de la fenêtre : rend le clavier si le bouton attendait une touche
	return function()
		if listening then Listen(false) end
	end
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------

local function RefreshMenu()
	refreshing = true
	for _, refresh in ipairs(refreshers) do refresh() end
	refreshing = false
end

-- Montre une page : "settings", "nodes", ou "look", avec les objets dont elle règle l'apparence
-- s'ils sont donnés ("all", ou une catégorie, que l'aperçu montre alors)
local function Open(name, scope)
	openPage, effectScope = name, scope or effectScope
	for key, page in pairs(pages) do page:SetShown(key == name) end
	RefreshMenu()
	if scope and scope ~= "all" and ns.ShowPreviewCategory then ns.ShowPreviewCategory(scope) end
end

-- Titre de la page des objets : il dit pour lesquels elle règle l'apparence
local function LookTitle()
	local category = ScopeCategory()
	return category and L.LOOK_OF:format(L["CATEGORY_" .. category:upper()]) or L.LOOK_OF_ALL
end

-- Case du bandeau des objets, à `x` et large de `width` : une icône et, dessous, un nom. La cliquer
-- règle la page sur ces objets, et l'aperçu les montre. Pour une catégorie (`key`), elle porte aussi,
-- à droite de l'icône, la case qui la met ou non en lumière et sa couleur. Son infobulle dit ce
-- qu'il advient des autres objets quand on règle ceux-là.
local function AddEntry(parent, x, width, name, icon, key)
	local scope = key or "all"
	local row = CreateFrame("CheckButton", nil, parent)
	row:SetSize(width - 2, STRIP - 10)
	row:SetPoint("TOPLEFT", x, -5)
	row.scope = scope
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	-- l'icône, la case et la pastille tiennent ensemble au milieu de la case
	local content = SLOT + (key and 52 or 0)
	local image, slot = Skin.Slot(row, SLOT, "TOPLEFT", (width - 2 - content) / 2 + 3, -6)
	Skin.SetIcon(image, icon)
	-- la case choisie : une lueur dorée derrière son icône (vu en jeu le 2026-11-09, un aplat sur toute
	-- la case faisait un pavé terne) ; sans l'image de Lueur, le surlignage des listes du jeu
	local chosen = row:CreateTexture(nil, "BACKGROUND")
	chosen:SetBlendMode("ADD")
	if chosen:SetTexture(MEDIA .. "glow.tga") == false then
		chosen:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
		chosen:SetAllPoints()
		chosen:SetVertexColor(1, 0.82, 0, 0.45)
	else
		chosen:SetSize(SLOT * 3.2, SLOT * 2.3)
		chosen:SetPoint("CENTER", slot, "CENTER", 0, -4)
		chosen:SetVertexColor(1, 0.74, 0.2, 0.85)
	end
	local ring = row:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	ring:SetBlendMode("ADD")
	ring:SetSize(SLOT, SLOT)
	ring:SetPoint("CENTER", slot, "CENTER", 0, 0)
	local title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("BOTTOM", row, "BOTTOM", 0, 4)
	Caption(title, name)
	row:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Open("look", scope)
	end)
	row:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L[name])
		GameTooltip_AddNormalLine(GameTooltip, key and L.SCOPE_ONE_TIP or L.SCOPE_ALL_TIP)
		GameTooltip:Show()
	end)
	row:HookScript("OnLeave", function() GameTooltip:Hide() end)

	if key then
		local toggle = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
		toggle:SetPoint("LEFT", slot, "RIGHT", 5, 0)
		toggle:SetScript("OnClick", function(self)
			local checked = self:GetChecked()
			PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			ns.SetCategory(key, checked)
		end)
		SetTooltip(toggle, name)
		local swatch = AddSwatch(row, key)
		swatch:SetPoint("LEFT", toggle, "RIGHT", 1, 0)
		row.toggle, row.swatch = toggle, swatch
	end
	refreshers[#refreshers + 1] = function()
		local selected = effectScope == scope
		local shown = not key or ns.IsCategoryShown(key) and true or false
		row:SetChecked(selected)
		chosen:SetShown(selected)
		ring:SetShown(selected)
		image:SetDesaturated(not shown)
		Dim(title, shown, 1, 0.82, 0)
		if key then row.toggle:SetChecked(shown) end
	end
	return row
end

-- Icônes témoins de la page de la minimap : sur un disque sombre, des icônes telles que la minimap
-- les montre, à la taille et à l'épaisseur d'anneau réglées (NodeScan.lua les dessine)
local function AddSamples(column)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, SAMPLE + 8)
	row:SetPoint("TOPLEFT", column.x, column.y - 6)
	column.y = column.y - SAMPLE - 14
	for index, tone in ipairs({ { 0.62, 0.56, 0.46, 0.9 }, { 0.09, 0.11, 0.08, 1 } }) do
		local disc = row:CreateTexture(nil, "BACKGROUND", nil, index)
		disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		disc:SetVertexColor(tone[1], tone[2], tone[3], tone[4])
		disc:SetSize(SAMPLE + 6 - 4 * index, SAMPLE + 6 - 4 * index)
		disc:SetPoint("CENTER")
	end
	if not ns.NodeSamples then return row end
	local draw = ns.NodeSamples(row, SAMPLES, SAMPLE / 2)
	refreshers[#refreshers + 1] = function()
		draw(ns.GetOption("nodeSize"), ns.GetOption("nodeRing") / 100, ns.GetOption("nodeHerbs"), ns.GetOption("nodeOre"))
	end
	return row
end

local function CreateMenu()
	local frame = Skin.Window("LueurMenu", WIDTH, HEIGHT)
	menu = frame
	frame.title:SetText("Lueur")
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint(1)
		-- "+ 0" : pas de -0 dans les réglages sauvegardés, Lua 5.1 y relirait tous les zéros en -0
		ns.db.menuPoint = { point, relativePoint, x + 0, y + 0 }
	end)
	local saved = ns.db.menuPoint
	frame:ClearAllPoints()
	if saved then
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		frame:SetPoint("LEFT", UIParent, "LEFT", 30, 20) -- à gauche : le personnage reste visible
	end

	-- Sous la barre de titre, à droite du portrait : le nom de la page
	local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 68, -33)
	refreshers[#refreshers + 1] = function()
		heading:SetText(openPage == "look" and LookTitle() or L[PAGE_TITLES[openPage]])
	end

	-- Les onglets du bord droit : un par page. Celle de la minimap n'existe qu'avec NodeScan.lua,
	-- qu'une mise à jour faite pendant que le jeu tourne n'a pas encore chargé.
	local list = { { "look", Skin.PORTRAIT, "HEADER_OBJECTS" } }
	if ns.UpdateNodes then list[#list + 1] = { "nodes", ICONS .. NODES_ICON, "NODES_PAGE" } end
	list[#list + 1] = { "settings", ICONS .. SETTINGS_ICON, "SETTINGS" }
	frame.tabs = {}
	local previous
	for _, tab in ipairs(list) do
		local name, text = tab[1], tab[3]
		local button = Skin.SideTab(frame, previous, tab[2], function() Open(name) end)
		captions[#captions + 1] = function() button.tooltipText = L[text] end
		button.tooltipText = L[text]
		refreshers[#refreshers + 1] = function() button:SetChecked(openPage == name) end
		frame.tabs[name], previous = button, button
	end

	local height = HEIGHT - TOP - FOOT
	for _, tab in ipairs(list) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetSize(WIDTH - 2 * EDGE, height)
		page:SetPoint("TOPLEFT", EDGE, -TOP)
		pages[tab[1]] = page
	end

	-- Page des objets. En haut leur bandeau : tous, puis chaque catégorie.
	local page = pages.look
	local strip = Skin.Card(page, page:GetWidth(), STRIP)
	strip:SetPoint("TOPLEFT", 0, 0)
	local cell = (page:GetWidth() - 12) / (#ns.CATEGORY_ORDER + 1)
	AddEntry(strip, 6, cell, "SCOPE_ALL", Skin.PORTRAIT)
	for index, key in ipairs(ns.CATEGORY_ORDER) do
		AddEntry(strip, 6 + index * cell, cell, "CATEGORY_" .. key:upper(), ICONS .. (CATEGORY_ICONS[key] or "INV_Misc_QuestionMark"), key)
	end

	-- Dessous, à gauche : l'aperçu, sur le modèle d'un objet de la catégorie choisie (Preview.lua)
	local lower = height - STRIP - GAP
	local stage = Skin.Card(page, VIEW, lower)
	stage:SetPoint("TOPLEFT", 0, -STRIP - GAP)
	if ns.PreviewPane then ns.PreviewPane(stage, VIEW - 12, lower - 44):SetPoint("TOPLEFT", 6, -6) end

	-- À droite, leur apparence : l'effet et ses réglages. Tout s'applique aussitôt à la lueur en
	-- cours, celle de l'aperçu ou celle de l'objet que le jeu désigne.
	local column = NewCard(page, VIEW + GAP, -STRIP - GAP, page:GetWidth() - VIEW - GAP, lower)
	column.tight = true
	local shared = AddButton(frame, "SHARED", function() ns.ClearOwnSettings(ScopeCategory()) end, 190)
	shared:SetPoint("TOPRIGHT", -EDGE - 2, -30)
	refreshers[#refreshers + 1] = function()
		local category = ScopeCategory()
		-- le bouton n'a de sens que pour une catégorie qui a des réglages à elle
		local own = openPage == "look" and category ~= nil and ns.HasOwnSettings(category)
		shared:SetEnabled(own)
		shared:SetShown(own)
	end
	AddEffects(column)
	AddDivider(column)
	AddSlider(column, "SIZE", "size", nil, true, 200)
	AddSlider(column, "INTENSITY", "intensity", "FORMAT_PERCENT", true, 200)
	AddSlider(column, "OFFSET", "offsetY", nil, true, 200)
	AddDivider(column)
	-- les deux cases de la lueur l'une sous l'autre : leurs noms sont longs, et côte à côte le premier
	-- passait sous la seconde case (vu en jeu le 2026-11-09) ; celles du nom et de l'icône, courtes, côte à côte
	AddCheckbox(column, "SILHOUETTE", ScopedGetter("silhouette"), function(checked)
		ns.SetOption("silhouette", checked, ScopeCategory())
		local failure = ns.SilhouetteFailure()
		if checked and failure then ns.Print(L.MSG_CUTOUT_UNAVAILABLE:format(failure)) end
	end)
	AddOption(column, "FADE", "followAlpha", true)
	local left = column.x
	local showName = AddOption(column, "SHOW_NAME", "showName", true)
	column.x, column.y = left + column.width / 2, column.y + ROW
	local showIcon = AddOption(column, "SHOW_ICON", "showIcon", true)
	column.x = left
	local textSize = AddSlider(column, "TEXT_SIZE", "textSize", "FORMAT_PERCENT", true, 200)
	-- (la lumière seule, avec Plumber ou par le réglage : Lueur n'écrit ni nom ni icône)
	refreshers[#refreshers + 1] = function()
		local bare = Bare()
		showName:SetAvailable(not bare)
		showIcon:SetAvailable(not bare)
		textSize:SetAvailable(not bare and ns.GetOption("showName", ScopeCategory()))
	end
	AddFont(column, "FONT", 200)

	-- Page de la minimap : à gauche les icônes des filons et des plantes, et des icônes témoins qui
	-- suivent leurs réglages ; à droite l'alternance des deux pistages, pour qui a les deux métiers,
	-- puis la lecture de la minimap. Rien n'y explique les couleurs des anneaux : une légende y
	-- était, que le joueur a fait retirer.
	local half = (page:GetWidth() - GAP) / 2
	page = pages.nodes
	if page then
		column = NewCard(page, 0, 0, half, height, "HEADER_NODES")
		local controls = {
			AddOption(column, "NODE_HERBS", "nodeHerbs"),
			AddOption(column, "NODE_ORE", "nodeOre"),
			AddSlider(column, "NODE_SIZE", "nodeSize"),
			AddSlider(column, "NODE_RING", "nodeRing", "FORMAT_PERCENT"),
		}
		AddSamples(column)
		-- sur un client qui ne sait pas lire les points de la minimap : pourquoi tout est grisé
		local reason = column.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		reason:SetPoint("TOPLEFT", column.x, column.y - 4)
		reason:SetWidth(column.width)
		reason:SetJustifyH("LEFT")
		reason:SetTextColor(1, 0.5, 0.25)

		column = NewCard(page, half + GAP, 0, half, SWITCH_HEIGHT, "HEADER_SWITCH")
		controls[#controls + 1] = AddOption(column, "NODE_SWITCH", "nodeSwitch")
		controls[#controls + 1] = AddSlider(column, "NODE_SWITCH_YARDS", "nodeSwitchYards", "FORMAT_RANGE")

		-- dessous : quand la minimap se lit (chaque balayage la cache un instant)
		column = NewCard(page, half + GAP, -(SWITCH_HEIGHT + GAP), half, height - SWITCH_HEIGHT - GAP, "HEADER_SCANNING")
		controls[#controls + 1] = AddSlider(column, "NODE_SCAN_YARDS", "nodeScanYards", "FORMAT_RANGE")
		controls[#controls + 1] = AddOption(column, "NODE_COMBAT", "nodeCombat")
		refreshers[#refreshers + 1] = function()
			local failure = ns.NodesFailure()
			for _, control in ipairs(controls) do control:SetAvailable(not failure) end
			reason:SetText(failure and L.MSG_NODES_UNAVAILABLE:format(failure) or "")
		end
	end

	-- Page des réglages : quatre panneaux, qui valent pour tous les objets
	page = pages.settings
	local upper = 214
	column = NewCard(page, 0, 0, half, upper, "HEADER_DETECTION")
	AddSlider(column, "RANGE", "range", "FORMAT_RANGE", false, 170)
	AddChoice(column, "DIRECTION", ARC_CHOICES, Getter("arc"), Setter("arc"), 3)
	AddOption(column, "EXCLUSIVE", "exclusive")
	local stopListening = AddKeybind(column, "KEY")
	AddIgnore(column)

	column = NewCard(page, half + GAP, 0, half, upper, "HEADER_GENERAL")
	AddOption(column, "ENABLE", "enabled")
	-- (à côté : la lumière seule, la nameplate laissée au jeu ou à Plumber ; les deux noms sont courts)
	column.x, column.y = column.x + column.width / 2, column.y + ROW
	AddOption(column, "GLOW_ONLY", "glowOnly")
	column.x = column.x - column.width / 2
	AddCheckbox(column, "MINIMAP", function() return not ns.db.minimap.hide end, ns.ShowMinimapButton)
	AddOption(column, "DEBUG", "debug")
	-- chaque langue se présente sous le nom qu'elle se donne, pour rester reconnaissable depuis
	-- n'importe quelle autre
	local languages, codes = { { "auto", "LANGUAGE_AUTO" } }, {}
	for code in pairs(ns.LOCALES) do codes[#codes + 1] = code end
	table.sort(codes)
	for _, code in ipairs(codes) do languages[#languages + 1] = { code, nil, ns.LOCALES[code].LANGUAGE_NAME } end
	AddChoice(column, "LANGUAGE", languages, Getter("language"), Setter("language"), 3)

	column = NewCard(page, 0, -upper - GAP, half, height - upper - GAP, "HEADER_HIDE")
	AddOption(column, "HIDE_COMBAT", "hideInCombat")
	AddOption(column, "HIDE_INSTANCE", "hideInInstance")
	AddOption(column, "HIDE_LOCKED", "hideLocked")
	AddOption(column, "HIDE_UNTRAINED", "hideUntrained")

	column = NewCard(page, half + GAP, -upper - GAP, half, height - upper - GAP, "HEADER_SILHOUETTE")
	local zoneScale = AddSlider(column, "ZONE_SIZE", "bodyScale", "FORMAT_PERCENT")
	local zoneShift = AddSlider(column, "ZONE_HEIGHT", "bodyShift", "FORMAT_PERCENT")
	local zoneShown = AddCheckbox(column, "ZONE_SHOW", ns.IsZoneShown, ns.ShowZone)
	refreshers[#refreshers + 1] = function()
		-- sur un client qui ne sait pas découper, il n'y a rien à régler
		local available = not ns.SilhouetteFailure()
		zoneScale:SetAvailable(available)
		zoneShift:SetAvailable(available)
		zoneShown:SetAvailable(available)
	end

	for name, shown in pairs(pages) do shown:SetShown(name == openPage) end

	-- Au pied de la fenêtre : la version, et la remise à zéro
	local confirmLeft -- secondes qui restent pour confirmer la remise à zéro, nil hors confirmation
	local reset = AddButton(frame, "DEFAULTS", function()
		if confirmLeft then
			confirmLeft = nil
			ns.ResetOptions()
		else
			confirmLeft = CONFIRM_TIME
		end
	end)
	reset:SetPoint("BOTTOMRIGHT", -EDGE, 12)

	local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", EDGE + 4, 17)
	local function Sign()
		version:SetText(L.FOOTER:format(C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or ""))
	end
	captions[#captions + 1] = Sign
	Sign()

	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		RefreshMenu()
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		confirmLeft = nil
		if ns.IsZoneShown() then ns.ShowZone(false) end
		stopListening()
	end)
	frame:SetScript("OnUpdate", function(_, elapsed)
		if blockClick > 0 then blockClick = blockClick - 1 end
		if confirmLeft then
			confirmLeft = confirmLeft - elapsed
			if confirmLeft <= 0 then confirmLeft = nil end
		end
		SetLabel(reset, confirmLeft and L.CONFIRM or L.DEFAULTS)
	end)
	return frame
end

function ns.ToggleMenu()
	local frame = menu or CreateMenu()
	if not frame:IsShown() then
		blockClick = 4
		if keybindButton then keybindButton:EnableKeyboard(false) end
	end
	frame:SetShown(not frame:IsShown())
end

-- /lueur preview : la fenêtre s'ouvre sur la page des objets, où se tient l'aperçu ; elle s'y
-- trouvait déjà : elle se ferme. Renvoie true si l'aperçu est désormais montré.
function ns.TogglePreview()
	if menu and menu:IsShown() and openPage == "look" then
		menu:Hide()
		return false
	end
	if not (menu and menu:IsShown()) then ns.ToggleMenu() end
	Open("look")
	return true
end

---------------------------------------------------------------------------
-- Bouton de la minimap
---------------------------------------------------------------------------

local function PlaceMinimapButton()
	local angle = math.rad(ns.db.minimap.angle)
	local radius = Minimap:GetWidth() / 2 + BUTTON_RADIUS
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Pendant qu'on le fait glisser, le bouton suit le curseur autour de la minimap
local function DragMinimapButton()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimap.angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
	PlaceMinimapButton()
end

local function ShowMinimapTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, "Lueur")
	GameTooltip_AddNormalLine(GameTooltip, ns.db.enabled and L.TIP_ENABLED or L.TIP_DISABLED)
	GameTooltip_AddInstructionLine(GameTooltip, L.TIP_LEFT_CLICK)
	GameTooltip_AddInstructionLine(GameTooltip, L.TIP_RIGHT_CLICK)
	GameTooltip_AddInstructionLine(GameTooltip, L.TIP_DRAG)
	GameTooltip:Show()
end

-- Mêmes textures et mêmes cotes que les boutons des autres addons, pour s'aligner sur eux
local function CreateMinimapButton()
	local button = CreateFrame("Button", "LueurMinimapButton", Minimap)
	minimapButton = button
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(8)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	if icon:SetTexture(MEDIA .. "icon.tga") == false then icon:SetTexture(FALLBACK_ICON) end
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ns.Toggle(not ns.db.enabled)
			if self:IsMouseOver() then ShowMinimapTooltip(self) end
		else
			ns.ToggleMenu()
		end
	end)
	button:SetScript("OnEnter", ShowMinimapTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", DragMinimapButton)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	PlaceMinimapButton()
end

---------------------------------------------------------------------------
-- Entrée dans les options du jeu
---------------------------------------------------------------------------

-- Les joueurs cherchent les réglages d'un addon dans Options > AddOns : Lueur y pose une page
-- qui mène à sa fenêtre. Le jeu la reparente quand il l'affiche.
local function RegisterOptionsPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local page = CreateFrame("Frame", nil, UIParent)
	page:Hide()
	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Lueur")
	local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	note:SetPoint("TOPLEFT", 16, -44)
	Caption(note, "OPTIONS_NOTE")
	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetSize(240, 22)
	open:SetPoint("TOPLEFT", 16, -72)
	Caption(open, "OPTIONS_OPEN")
	open:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		-- la fenêtre d'options du jeu recouvrirait celle de Lueur
		if SettingsPanel and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
		if not (menu and menu:IsShown()) then ns.ToggleMenu() end
	end)
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, page, "Lueur")
	if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

---------------------------------------------------------------------------
-- Liens avec Lueur.lua et avec le jeu
---------------------------------------------------------------------------

-- Appelée par Lueur.lua à chaque changement de réglage, d'où qu'il vienne
function ns.Refresh()
	if minimapButton then
		minimapButton:SetShown(not ns.db.minimap.hide)
		minimapButton.icon:SetDesaturated(not ns.db.enabled) -- gris quand Lueur est désactivé
	end
	if menu and menu:IsShown() then RefreshMenu() end
end

-- Appelée par Lueur.lua quand la langue change : repose les textes fixes de la fenêtre. Les
-- valeurs suivent avec le rafraîchissement qui accompagne tout changement de réglage.
function ns.Retext()
	for _, apply in ipairs(captions) do apply() end
end


-- Affiche ou masque le bouton de la minimap (case du menu, /lueur minimap)
function ns.ShowMinimapButton(shown)
	ns.db.minimap.hide = not shown
	ns.Refresh()
end

-- Appelée par Lueur.lua une fois les réglages chargés
function ns.SetupInterface()
	CreateMinimapButton()
	RegisterOptionsPage()
	ns.Refresh()
end

-- Entrée de Lueur dans le menu des addons de la minimap (déclarée dans le .toc)
function Lueur_OnAddonCompartmentClick()
	ns.ToggleMenu()
end
