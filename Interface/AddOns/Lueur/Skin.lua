-- Lueur : habillage des fenêtres
-- Les fenêtres de Lueur (réglages, aperçu) ont l'allure des écrans du jeu, celle de la fenêtre
-- des métiers : le cadre à portrait, des panneaux sombres au filet arrondi, des onglets
-- d'icône sur le côté, des boutons d'icône comme ceux des sorts. Ce fichier les construit avec
-- les gabarits et les images de Blizzard, donc avec le dessin du client qui tourne. Le client
-- qui n'a pas un gabarit ou un atlas reçoit à sa place un équivalent fait d'images présentes
-- partout. Menu.lua et Preview.lua assemblent ces pièces ; rien ici ne connaît les réglages.

local ADDON_NAME, ns = ...

local Skin = {}
ns.Skin = Skin

local PORTRAIT = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\portrait.tga"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SLOT_INSET = 3  -- l'image d'un emplacement d'icône s'arrête avant son liseré
Skin.PORTRAIT = PORTRAIT

-- Panneau : le fond et le filet arrondi des infobulles du jeu, assombris
local CARD = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Crée un cadre d'après un gabarit du jeu ; nil sur le client qui n'a pas ce gabarit
local function FromTemplate(kind, name, parent, template)
	local ok, frame = pcall(CreateFrame, kind, name, parent, template)
	return ok and frame or nil
end

local function HasAtlas(atlas)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	return ok and info ~= nil
end

-- Donne son image à une icône ; faute de la trouver, le point d'interrogation du jeu
local function SetIcon(texture, file)
	if texture:SetTexture(file) == false then texture:SetTexture(UNKNOWN_ICON) end
end
Skin.SetIcon = SetIcon

-- Fenêtre : le cadre à portrait du jeu, avec l'icône de Lueur pour portrait. La souris la
-- déplace, Échap et sa croix la ferment. `frame.title` est son titre, `frame.close` sa croix.
function Skin.Window(name, width, height)
	local frame = FromTemplate("Frame", name, UIParent, "PortraitFrameTemplate")
	if frame then
		-- le titre et le portrait ont changé de place d'une version du cadre à l'autre
		frame.title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
		frame.close = frame.CloseButton
		local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait or frame.portrait
		if portrait then SetIcon(portrait, PORTRAIT) end
	else
		frame = CreateFrame("Frame", name, UIParent)
		local back = frame:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.07, 0.06, 0.05, 0.95)
	end
	if not frame.title then
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", 0, -6)
	end
	if not frame.close then
		frame.close = FromTemplate("Button", nil, frame, "UIPanelCloseButton") or CreateFrame("Button", nil, frame)
		frame.close:SetSize(24, 24)
		frame.close:SetPoint("TOPRIGHT", -2, -2)
	end
	frame.close:SetScript("OnClick", function() frame:Hide() end)

	frame:Hide()
	frame:SetSize(width, height)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, name) -- se ferme avec Échap
	return frame
end

-- Panneau sombre au filet arrondi, comme ceux où la fenêtre des métiers range chaque métier
function Skin.Card(parent, width, height)
	local card = FromTemplate("Frame", nil, parent, "BackdropTemplate")
	if card and card.SetBackdrop then
		card:SetBackdrop(CARD)
		card:SetBackdropColor(0.03, 0.03, 0.03, 0.72)
		card:SetBackdropBorderColor(0.62, 0.56, 0.46, 0.9)
	else
		card = card or CreateFrame("Frame", nil, parent)
		local back = card:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.55)
	end
	card:SetSize(width, height)
	return card
end

-- Onglet d'icône sur le bord droit d'une fenêtre, sous `previous` s'il y en a un avant lui.
-- `tab.tooltipText` est son infobulle, SetChecked le montre choisi ou non.
function Skin.SideTab(window, previous, icon, onClick)
	local tab = FromTemplate("Frame", nil, window, "LargeSideTabButtonTemplate")
	if tab and tab.Icon and tab.SetChecked and tab.SetCustomOnMouseUpHandler then
		-- l'onglet des fenêtres du jeu : il s'enfonce, sonne et montre son infobulle de lui-même
		SetIcon(tab.Icon, icon)
		if tab.SetFillToInterior then tab:SetFillToInterior(true) end
		tab:SetCustomOnMouseUpHandler(function(_, mouseButton, inside)
			if mouseButton == "LeftButton" and inside then onClick() end
		end)
		if previous then
			tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
		else
			tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -60)
		end
		return tab
	end
	if tab then tab:Hide() end
	-- à défaut, l'onglet du grimoire de Classic
	tab = CreateFrame("CheckButton", nil, window)
	tab:SetSize(32, 32)
	local back = tab:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	back:SetSize(64, 64)
	back:SetPoint("TOPLEFT", -3, 11)
	local face = tab:CreateTexture(nil, "ARTWORK")
	face:SetAllPoints()
	SetIcon(face, icon)
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	local glow = tab:GetCheckedTexture()
	if glow then glow:SetBlendMode("ADD") end
	tab:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		onClick() -- la fenêtre recoche ensuite l'onglet de la page qu'elle montre
	end)
	tab:SetScript("OnEnter", function(self)
		if not self.tooltipText then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, self.tooltipText)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if previous then
		tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -17)
	else
		tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -66)
	end
	return tab
end

-- Emplacement d'icône dessiné sur `frame` : un fond noir, l'image, et le liseré des boutons de
-- sort. Renvoie la texture de l'image, et l'emplacement lui-même pour y ancrer autre chose.
function Skin.Slot(frame, size, point, x, y)
	local back = frame:CreateTexture(nil, "BACKGROUND")
	back:SetSize(size - 2 * SLOT_INSET, size - 2 * SLOT_INSET)
	back:SetPoint(point, x + (point == "LEFT" and SLOT_INSET or 0), y)
	back:SetColorTexture(0, 0, 0, 0.85)
	local icon = frame:CreateTexture(nil, "BORDER")
	icon:SetAllPoints(back)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- sans le bord dessiné dans les icônes du jeu
	local rim = frame:CreateTexture(nil, "OVERLAY")
	rim:SetPoint("CENTER", back, "CENTER", 0, 0)
	if HasAtlas("Profession-square-frame") then
		rim:SetAtlas("Profession-square-frame", true) -- le liseré des boutons de la fenêtre des métiers
	else
		rim:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		rim:SetSize(size * 1.7, size * 1.7)
	end
	return icon, back
end

-- Bouton d'icône, comme ceux des sorts dans la fenêtre des métiers : il s'éclaire au survol,
-- s'enfonce sous le clic et garde un liseré doré tant qu'il est coché. `button.icon` est son image.
function Skin.IconButton(parent, size)
	local button = CreateFrame("CheckButton", nil, parent)
	button:SetSize(size, size)
	button.icon = Skin.Slot(button, size, "CENTER", 0, 0)
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	local glow = button:GetCheckedTexture()
	if glow then glow:SetBlendMode("ADD") end
	return button
end
