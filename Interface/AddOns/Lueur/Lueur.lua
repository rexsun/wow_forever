-- Lueur : de la cible à la lueur
-- Evaluate() est le point d'entrée : à chaque événement qui change la cible et toutes les
-- POLL_INTERVAL secondes, il met en accord avec la cible d'interaction du moment l'affichage
-- natif du jeu et la lueur. Ce fichier tient aussi le déroulé de l'aperçu et les événements du jeu.
-- (Le reste du cœur est décrit en tête de Core.lua.)

local ADDON_NAME, ns = ...
local L = ns.L

if not ns.state then
	-- Core.lua et les autres fichiers du cœur sont arrivés avec une mise à jour, et le jeu ne charge
	-- un nouveau fichier qu'à son lancement : d'ici là Lueur ne fait rien, ne touche à aucune CVar
	-- ni aux réglages sauvegardés, et dit pourquoi à la connexion et à chaque /lueur
	local function Restart()
		print(L.PREFIX .. L.MSG_RESTART)
	end
	SLASH_LUEUR1 = "/lueur"
	SlashCmdList.LUEUR = Restart
	Lueur_OnAddonCompartmentClick = Restart
	local waiting = CreateFrame("Frame")
	waiting:RegisterEvent("PLAYER_LOGIN")
	waiting:SetScript("OnEvent", function()
		if type(LueurDB) == "table" then ns.UseLanguage(LueurDB.language) end -- dans la langue que le joueur a choisie
		Restart()
	end)
	return
end

local S, glow = ns.state, ns.glow
local Print, SafeCall, IsSecret, CategoryName, StateName = ns.Print, ns.SafeCall, ns.IsSecret, ns.CategoryName, ns.StateName
local GetCVarValue, EnsureIconCVars, SetGate, WantedRange = ns.GetCVarValue, ns.EnsureIconCVars, ns.SetGate, ns.WantedRange
local ApplyCVars, ApplyRange, RestoreCVars, ReturnCVars = ns.ApplyCVars, ns.ApplyRange, ns.RestoreCVars, ns.ReturnCVars
local NameKey, questTexts, MatchQuestObjective, LearnFromTooltip = ns.NameKey, ns.questTexts, ns.MatchQuestObjective, ns.LearnFromTooltip
local ReadLine, ReadCursor, ObjectID, MatchContainer, LearnContainers = ns.ReadLine, ns.ReadCursor, ns.ObjectID, ns.MatchContainer, ns.LearnContainers
local Classify, Trained, ReadState, gathered = ns.Classify, ns.Trained, ns.ReadState, ns.gathered
local GetNamePlate, ResolveTarget, activeUnits = ns.GetNamePlate, ns.ResolveTarget, ns.activeUnits
local SetState, ShowLabel, Release, Attach, Present, Mute, Unmute, Shut = ns.SetState, ns.ShowLabel, ns.Release, ns.Attach, ns.Present, ns.Mute, ns.Unmute, ns.Shut

local db, cdb
ns.OnSettings(function(account, character) db, cdb = account, character end)


local POLL_INTERVAL = 0.12   -- réévaluation de la cible et de son état (secondes)

local inCombat = false       -- entre PLAYER_REGEN_DISABLED et PLAYER_REGEN_ENABLED
local leaving = false        -- déconnexion en cours : les CVars sont rendues, plus rien ne doit y toucher

---------------------------------------------------------------------------
-- Évaluation
---------------------------------------------------------------------------

local function Flag(value)
	if value == nil then return "?" end
	return value and L.YES or L.NO
end

local function Report(line, detail)
	if not db.debug or line == S.lastReport then return end
	S.lastReport = line
	Print(line)
	local text = detail and detail()
	if text and text ~= "" then print("    " .. text) end
end

local function DescribeTarget(unit, name, via, cursor, inRange)
	local parts = { L.DEBUG_CURSOR:format(tostring(cursor)), L.DEBUG_VIA:format(via), L.DEBUG_RANGE:format(Flag(inRange)),
		L.DEBUG_OBJECT:format(tostring(ObjectID(unit) or "?")), L.DEBUG_FISHING:format(Flag(ReadLine())) }
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		parts[#parts + 1] = L.DEBUG_QUEST:format(Flag(SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)))
	end
	-- (un curseur de service : le nom de l'objet n'est pas regardé, et le détail le dit)
	local _, kind = ReadCursor(unit)
	local service = kind == "service" and L.MATCH_CURSOR
	parts[#parts + 1] = L.DEBUG_MATCH:format(service or MatchQuestObjective(name) or L.MATCH_NONE, #questTexts)
	parts[#parts + 1] = L.DEBUG_CHEST:format(service or MatchContainer(ObjectID(unit), name) or L.MATCH_NONE)
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		parts[#parts + 1] = L.DEBUG_SECRET:format(Flag(SafeCall(C_Secrets.ShouldUnitIdentityBeSecret, unit)))
	end
	if C_NamePlateManager and C_NamePlateManager.IsNamePlateUnitBehindCamera then
		parts[#parts + 1] = L.DEBUG_BEHIND:format(Flag(SafeCall(C_NamePlateManager.IsNamePlateUnitBehindCamera, unit)))
	end
	return table.concat(parts, " | ")
end

-- La lueur est-elle suspendue par le contexte : en combat, ou en instance, si le joueur l'a demandé
local function Paused()
	if db.hideInCombat and (inCombat or InCombatLockdown()) then return true end
	return db.hideInInstance and IsInInstance ~= nil and SafeCall(IsInInstance) == true
end

-- Détermine la cible d'interaction courante, puis met en accord avec elle l'affichage natif
-- du jeu (ouvert seulement si elle mérite d'être mise en lumière) et la lueur elle-même.
-- Renvoie la nameplate d'une cible sans lueur que le jeu montre quand même, faute de pouvoir
-- refermer son affichage : Evaluate la masque.
local function Decide()
	if leaving or glow.preview and not glow.preview.soft then return end
	if not db.enabled then Release() return end
	if Paused() then
		Report(L.DEBUG_PAUSED)
		Release()
		local unit, plate = ResolveTarget()
		if unit then return Shut(unit, plate) end
		SetGate(false)
		return
	end

	local unit, plate, via, unknown = ResolveTarget()
	if plate or not unit then glow.plateMissingSince = nil end
	if not unit then
		if S.lastReport then Report(L.DEBUG_NO_TARGET) end
		SetGate(unknown == true) -- faute de savoir, on laisse le jeu montrer sa cible
		Release()
		return
	end
	local name = SafeCall(UnitName, unit)
	local label = name or "?"
	-- seuls les objets du décor sont mis en lumière : ni PNJ, ni cadavres
	if SafeCall(UnitIsGameObject, unit) ~= true then
		Report(L.DEBUG_IGNORED:format(label))
		Release()
		return Shut(unit, plate)
	end
	-- ni les objets que le joueur a écartés par leur nom ; ceux que le jeu ne nomme pas (une chaise,
	-- un banc) s'écartent tous ensemble, sous le nom vide
	local known = glow.NameOf(unit)
	if known and db.ignored[NameKey(known)] then
		Report(L.DEBUG_SKIPPED:format(known == "" and L.NAME_UNNAMED or label))
		Release()
		return Shut(unit, plate)
	end

	local category, blocked, cursor, id = Classify(unit, name)
	if id and (category == "ore" or category == "herb") then gathered[id] = true end
	local state, inRange = ReadState(unit, blocked)
	local wanted = category and cdb.categories[category] or false
	if not wanted then
		Report(L.DEBUG_HIDDEN:format(label, CategoryName(category)),
			function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		Release()
		return Shut(unit, plate)
	end
	-- ni une plante ou un filon que ce personnage ne sait pas récolter (demandé par des joueurs le 2026-10-14)
	if db.hideUntrained and Trained(category) == false then
		Report(L.DEBUG_UNTRAINED:format(label, CategoryName(category)),
			function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		Release()
		return Shut(unit, plate)
	end
	SetGate(true)
	if not plate then
		-- la nameplate vient d'être demandée au jeu : la lueur s'y posera à son arrivée.
		-- Si elle tarde, c'est que le jeu connaît la cible sans vouloir l'afficher.
		Release()
		local now = GetTime()
		glow.plateMissingSince = glow.plateMissingSince or now
		if now - glow.plateMissingSince > 0.5 then
			Report(L.DEBUG_NO_PLATE:format(label, CategoryName(category)),
				function() return DescribeTarget(unit, name, via, cursor, inRange) end)
		end
		return
	end

	Present(plate, unit, name, category, state)
	Report(L.DEBUG_SHOWN:format(label, CategoryName(category), StateName(glow.state)),
		function() return DescribeTarget(unit, name, via, cursor, inRange) end)
end

-- L'aperçu de la fenêtre des réglages (`soft`) ne retient pas la lueur : dès que le jeu désigne un objet
-- à éclairer, elle va sur lui, et les réglages se jugent sur lui. D'ici là rien de ce que Decide relâche
-- ne la lui prend (`glow.held`, que Release regarde).
local function Evaluate()
	glow.held = glow.preview and glow.preview.soft or nil
	local plate = Decide()
	glow.held = nil
	if plate then Mute(plate) else Unmute() end
end
Evaluate = ns.Timed("evaluate", Evaluate) -- (son coût, pour /lueur status)

-- Tant que la ligne de pêche est à l'eau, le jeu cherche le flotteur plus loin que la portée du réglage
local function WatchLine()
	local out = db.enabled and cdb.categories.bobber and ReadLine() or false
	if out == S.lineOut then return end
	S.lineOut = out
	if ApplyRange() and db.debug then
		Print((out and L.DEBUG_LINE_OUT or L.DEBUG_LINE_IN):format(WantedRange(), tostring(GetCVarValue("SoftTargetInteractRange"))))
	end
end

---------------------------------------------------------------------------
-- Aperçu
---------------------------------------------------------------------------

-- Déroulé de l'aperçu : chaque état, en boucle
local PREVIEW_STAGES = { { "far", 3.0 }, { "ready", 4.5 }, { "locked", 2.5 } }

-- Nom d'objet que l'aperçu montre pour une catégorie
local function SampleName(category)
	return L["SAMPLE_" .. category:upper()]
end

-- Montre la lueur d'une catégorie sur `anchor`, le cadre que l'aperçu place là où le jeu mettrait
-- la nameplate de l'objet, et enchaîne ses états en boucle jusqu'à StopPreview. `soft` : l'aperçu
-- cède la lueur à la première vraie cible (voir Evaluate).
local function StartPreview(anchor, category, soft)
	glow.held = nil
	Release()
	if not soft then Unmute() end
	Attach(anchor, category, "far")
	glow.preview = { stage = 1, left = PREVIEW_STAGES[1][2], soft = soft or nil }
	ShowLabel(nil, SampleName(category), category)
end

local function StopPreview()
	glow.held = nil
	if glow.preview then Release() end
end

local function UpdatePreview(elapsed)
	local preview = glow.preview
	preview.left = preview.left - elapsed
	if preview.left > 0 then return end
	preview.stage = preview.stage + 1
	local stage = PREVIEW_STAGES[preview.stage]
	if not stage then
		StartPreview(glow.anchor, glow.category, preview.soft)
		return
	end
	SetState(stage[1])
	preview.left = stage[2]
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local sincePoll = 0

events:SetScript("OnUpdate", function(_, elapsed)
	if not db or leaving then return end
	if glow.preview then
		UpdatePreview(elapsed)
		if not (glow.preview and glow.preview.soft) then return end
	end
	sincePoll = sincePoll + elapsed
	if sincePoll >= POLL_INTERVAL then
		sincePoll = 0
		WatchLine()
		EnsureIconCVars()
		Evaluate()
	end
end)

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	ns.LoadSettings() -- Settings.lua : LueurDB et LueurCharDB, migrés et bornés ; db et cdb sont là désormais
	ns.PrepareCursors()
	events:UnregisterEvent("ADDON_LOADED")
	ns.db = db
	if ns.SetupInterface then ns.SetupInterface() end -- Menu.lua : bouton de la minimap
end

function handlers.PLAYER_LOGIN()
	if db.enabled then ApplyCVars() end
	-- Menu.lua : le bouton de la minimap, maintenant que tous les addons sont chargés (LibDBIcon le fait s'il est là)
	if ns.SetupMinimapButton then ns.SetupMinimapButton() end
	-- Ce qu'une version d'avant le 2026-11-16 avait pris au joueur et pas encore rendu, le jeu s'étant
	-- arrêté entre-temps : la taille des points de la minimap, qu'un balayage (1.5 à 1.7) rapetissait ;
	-- et le repère de carte, la quête suivie et le réglage de navigation que le prototype de la lueur au
	-- loin empruntait. Le repère attend la fin du combat et la carte du monde fermée (elle construirait
	-- son cadre sous la souillure de l'addon) : sinon, à la prochaine connexion.
	local back = db.iconScaleBack
	if type(back) == "number" and back > 0 and Minimap and Minimap.SetIconScale then pcall(Minimap.SetIconScale, Minimap, back) end
	db.iconScaleBack = nil
	local keep = db.farRestore
	if type(keep) ~= "table" then
		db.farRestore = nil
	elseif not (InCombatLockdown() or (WorldMapFrame and WorldMapFrame:IsShown())) then
		if C_Map and not keep.kept then
			if type(keep.pin) == "table" and UiMapPoint then
				pcall(function() C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(keep.pin.map, keep.pin.x, keep.pin.y, keep.pin.z)) end)
			else
				pcall(C_Map.ClearUserWaypoint)
			end
		end
		if C_SuperTrack and not keep.kept then
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, keep.tracking == true)
			if keep.quest and keep.quest ~= 0 then pcall(C_SuperTrack.SetSuperTrackedQuestID, keep.quest) end
		end
		if keep.nav ~= nil and C_CVar then pcall(C_CVar.SetCVar, "showInGameNavigation", keep.nav) end
		db.farRestore = nil
	end
end

-- Les réglages synchronisés avec le compte peuvent arriver après PLAYER_LOGIN et
-- écraser nos valeurs : on les réapplique à ces moments-là.
function handlers.VARIABLES_LOADED()
	if db.enabled then ApplyCVars() end
end

function handlers.PLAYER_ENTERING_WORLD()
	if db.enabled then ApplyCVars() end
end

function handlers.PLAYER_LOGOUT()
	Release()
	Unmute()
	ReturnCVars()
	leaving = true
end

-- Les CVars ne se touchent plus une fois en combat : juste avant, on rouvre l'affichage
-- natif pour que la lueur continue d'apparaître sur les objets croisés pendant le combat,
-- ou on le referme si le joueur ne veut pas de lueur en combat.
function handlers.PLAYER_REGEN_DISABLED()
	if db.enabled then SetGate(not db.hideInCombat) end
	inCombat = true
end

function handlers.PLAYER_REGEN_ENABLED()
	inCombat = false
	if S.pendingCVars == "apply" then ApplyCVars()
	elseif S.pendingCVars == "restore" then RestoreCVars() end
	S.pendingCVars = false
	Evaluate()
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
	activeUnits[unit] = true
	Evaluate()
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
	activeUnits[unit] = nil
	-- la nameplate de la lueur s'en va : on la dissipe tout de suite, là où elle était
	local plate = GetNamePlate(unit)
	if plate and plate == glow.anchor then Release() end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED(oldTarget, newTarget)
	-- une nameplate recyclée d'une cible à l'autre ne suffit pas à voir le changement
	if not IsSecret(oldTarget) and not IsSecret(newTarget) and oldTarget and newTarget and oldTarget ~= newTarget then
		glow.retarget = glow.anchor ~= nil and not glow.preview
	end
	Evaluate()
end

function handlers.QUEST_LOG_UPDATE()
	ns.MarkQuests()
end

function handlers.WORLD_CURSOR_TOOLTIP_UPDATE()
	if LearnFromTooltip() then Evaluate() end
end

function handlers.LOOT_READY()
	LearnContainers()
end
handlers.LOOT_OPENED = handlers.LOOT_READY

events:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler and not leaving and (db or event == "ADDON_LOADED") then handler(...) end
end)
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event)
end

-- Ce dont les fichiers suivants se servent
ns.Evaluate, ns.Flag, ns.Paused, ns.SampleName = Evaluate, Flag, Paused, SampleName
ns.StartPreview, ns.StopPreview = StartPreview, StopPreview

function ns.IsPreviewing()
	return glow.preview ~= nil
end

-- La lueur est-elle sur une vraie cible ? L'aperçu de la fenêtre des réglages attend alors son tour.
function ns.GlowTaken()
	return glow.anchor ~= nil and not glow.preview
end

-- État que montre l'aperçu en cours, ou nil
function ns.PreviewState()
	return glow.preview and glow.state
end
