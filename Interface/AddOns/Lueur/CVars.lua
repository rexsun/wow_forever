-- Lueur : les CVars du jeu
-- La nameplate où s'accroche la lueur n'existe que si le soft targeting d'interaction est réglé
-- pour : Lueur écrit donc quelques CVars du jeu, garde les valeurs du joueur (db.savedCVars) et
-- les lui rend à /lueur off et à la déconnexion. Rien ne s'écrit en combat : ce qui est demandé
-- alors attend sa fin (S.pendingCVars).

local _, ns = ...
local S, glow = ns.state, ns.glow
local SafeCall = ns.SafeCall
local max = math.max

local db
ns.OnSettings(function(account) db = account end)


-- Pêche : le flotteur tombe souvent au-delà des 15 m où s'arrête le réglage de portée. Tant que
-- la ligne est à l'eau, Lueur demande donc au jeu de chercher jusqu'à LINE_RANGE.
local LINE_RANGE    = 60      -- mètres ; ni 25 ni 40 ne suffisaient toujours

-- CVars que Lueur modifie (valeurs d'origine sauvegardées puis restaurées par /lueur off)
local MANAGED_CVARS = {
	"SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange", "SoftTargetInteractArc",
	"SoftTargetInteractOnlyInRange", "SoftTargetInteractRangeIsHard", "SoftTargetIconInteract", "SoftTargetIconGameObject",
	"nameplateGameObjectMaxDistance",
}
-- Parmi elles, l'icône que le jeu pose sur la cible d'interaction
-- SoftTargetIconGameObject est forcé à 1 quand la gate s'ouvre : sans icône, le jeu ne
-- crée pas de nameplate pour les objets interactibles en soft target (Classic)
local ICON_CVARS = { "SoftTargetIconInteract", "SoftTargetIconGameObject" }
-- CVars que Lueur lit sans y toucher : /lueur status les montre, parce que la nameplate en dépend peut-être
local WATCHED_CVARS = { "nameplateMaxDistance" }

---------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------

local function GetCVarValue(name)
	local ok, value = pcall(C_CVar and C_CVar.GetCVar or GetCVar, name)
	if ok then return value end
end

-- Ne touche qu'aux CVars que ce client connaît (la liste varie d'une version à l'autre)
local function SetCVarValue(name, value)
	if GetCVarValue(name) == nil then return end
	pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end

-- Affichage natif de la cible d'interaction : sa nameplate, où s'accroche la lueur, et son
-- icône. En mode exclusif, Lueur ne l'ouvre que pour une cible mise en lumière : PNJ,
-- cadavres, boîtes aux lettres et autres restent utilisables avec la touche d'interaction,
-- mais le jeu ne les met plus en avant.
local function EnsureIconCVars()
	-- Le client beta écrase SoftTargetIconGameObject à 0 après PLAYER_ENTERING_WORLD
	-- On le répare ici, avant que Evaluate() ne cherche la nameplate
	if S.gateOpen == true then
		local current = GetCVarValue("SoftTargetIconGameObject")
		if current ~= "1" then SetCVarValue("SoftTargetIconGameObject", 1) end
	end
end

local function SetGate(open)
	open = open or not glow.Exclusive()
	if open == S.gateOpen or InCombatLockdown() then
		EnsureIconCVars()
		return
	end
	S.gateOpen = open
	SetCVarValue("SoftTargetNameplateInteract", open and 1 or 0)
	-- SoftTargetIconGameObject doit être 1 pour que le jeu crée des nameplates pour les game objects
	if open then SetCVarValue("SoftTargetIconGameObject", 1) end
	for _, name in ipairs(ICON_CVARS) do
		if name ~= "SoftTargetIconGameObject" then
			local original = db.savedCVars and db.savedCVars[name]
			if original ~= false then SetCVarValue(name, open and original or 0) end
		end
	end
end

-- Portée à demander au jeu : celle du réglage, ou celle qu'il faut pour atteindre le flotteur
local function WantedRange()
	return S.lineOut and LINE_RANGE or db.range
end

-- Le client porte-t-il les valeurs que Lueur applique ? C'est qu'elles ne lui ont pas été rendues.
local function CVarsLookApplied()
	local onlyInRange = GetCVarValue("SoftTargetInteractOnlyInRange")
	local range = tonumber(GetCVarValue("SoftTargetInteractRange"))
	return GetCVarValue("SoftTargetInteract") == "3" and (onlyInRange == nil or onlyInRange == "0")
		and (range == db.range or range == LINE_RANGE)
end

local function ApplyCVars()
	if InCombatLockdown() then S.pendingCVars = "apply" return end
	if db.cvarsReturned then
		-- rendues au jeu à la dernière déconnexion : ce que le client porte maintenant, ce sont les
		-- valeurs du joueur, qu'il a pu changer depuis. On les relit, sauf si ce sont les nôtres.
		db.cvarsReturned = nil
		if not CVarsLookApplied() then db.savedCVars = nil end
	end
	db.savedCVars = db.savedCVars or {}
	for _, name in ipairs(MANAGED_CVARS) do
		if db.savedCVars[name] == nil then
			db.savedCVars[name] = GetCVarValue(name) or false
		end
	end
	SetCVarValue("SoftTargetInteract", 3)          -- soft target d'interaction toujours actif
	SetCVarValue("SoftTargetInteractRange", WantedRange())
	SetCVarValue("SoftTargetInteractArc", db.arc)    -- angle de recherche autour du joueur
	SetCVarValue("SoftTargetInteractOnlyInRange", 0) -- détecter aussi hors de portée d'interaction
	-- la portée demandée ne doit pas écarter ce avec quoi le joueur peut interagir d'où il est,
	-- comme le flotteur de sa ligne de pêche
	SetCVarValue("SoftTargetInteractRangeIsHard", 0)
	-- la lueur s'accroche à la nameplate de l'objet : le jeu doit la montrer aussi loin qu'il le
	-- désigne, donc jusqu'au flotteur. Le joueur qui la montre plus loin encore garde sa valeur.
	SetCVarValue("nameplateGameObjectMaxDistance", max(tonumber(db.savedCVars.nameplateGameObjectMaxDistance) or 0, LINE_RANGE))
	-- la nameplate et l'icône de la cible dépendent de ce qui est visé
	S.gateOpen = nil
	ns.Evaluate() -- (Lueur.lua, chargé après ce fichier)
end

-- La portée seule, quand la ligne de pêche entre dans l'eau ou en sort. Renvoie false quand il
-- n'y a rien à écrire, parce que Lueur ne tient pas les CVars du jeu : désactivé, ou pas encore
-- passé par ApplyCVars.
local function ApplyRange()
	if not db.enabled or not db.savedCVars or db.cvarsReturned then return false end
	if InCombatLockdown() then
		S.pendingCVars = S.pendingCVars or "apply"
	else
		SetCVarValue("SoftTargetInteractRange", WantedRange())
	end
	return true
end

local function RestoreCVars()
	if InCombatLockdown() then S.pendingCVars = "restore" return end
	if not db.savedCVars then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then SetCVarValue(name, value) end
	end
	db.savedCVars = nil
	S.gateOpen = nil
end

-- À la déconnexion, le jeu retrouve ses valeurs d'origine : désactiver ou désinstaller Lueur
-- depuis la liste des addons ne laisse rien derrière lui. Elles restent en mémoire pour le
-- cas où le client ne les enregistrerait pas (fermeture brutale).
local function ReturnCVars()
	if not db.enabled or not db.savedCVars or InCombatLockdown() then return end
	for name, value in pairs(db.savedCVars) do
		if value ~= false then SetCVarValue(name, value) end
	end
	db.cvarsReturned = true
	S.gateOpen = nil
end

-- Les versions 0.1.x pouvaient mémoriser comme valeurs d'origine celles que Lueur venait
-- lui-même d'appliquer : /lueur off ne rendait alors rien. Quand la sauvegarde porte cette
-- signature, on lui substitue les valeurs par défaut du client.
local function RepairSavedCVars()
	local saved = db.savedCVars
	if not saved or not (C_CVar and C_CVar.GetCVarDefault) then return end
	if saved.SoftTargetInteract ~= "3" or saved.SoftTargetNameplateInteract ~= "1" or saved.SoftTargetInteractArc ~= "2"
		or (saved.SoftTargetInteractRange ~= "20" and saved.SoftTargetInteractRange ~= tostring(db.range)) then
		return
	end
	for _, name in ipairs({ "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractArc", "SoftTargetInteractRange" }) do
		local default = SafeCall(C_CVar.GetCVarDefault, name)
		if default ~= nil then saved[name] = default end
	end
end

-- Ce dont les fichiers suivants se servent
ns.MANAGED_CVARS, ns.WATCHED_CVARS = MANAGED_CVARS, WATCHED_CVARS
ns.GetCVarValue, ns.EnsureIconCVars, ns.SetGate, ns.WantedRange = GetCVarValue, EnsureIconCVars, SetGate, WantedRange
ns.ApplyCVars, ns.ApplyRange, ns.RestoreCVars, ns.ReturnCVars, ns.RepairSavedCVars = ApplyCVars, ApplyRange, RestoreCVars, ReturnCVars, RepairSavedCVars
