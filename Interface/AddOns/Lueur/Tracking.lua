-- Lueur : alternance des deux pistages de récolte
-- Un personnage qui a les deux métiers de récolte ne voit sur la minimap que les points d'un pistage
-- à la fois (Découverte d'herbes, Découverte de gisements). Avec le réglage nodeSwitch, Lueur allume
-- l'autre chaque fois que le joueur s'est éloigné d'assez du lieu de la dernière bascule.
--
-- Ce fichier a son propre cadre et ses propres événements. Il lit les réglages par ns.GetOption
-- et n'est connu du cœur de l'addon que par des crochets gardés : ns.UpdateTracking, ns.CanSwitch.
-- (Jusqu'à la 1.7.0 ce code vivait dans NodeScan.lua, avec les icônes de la minimap, retirées le
-- 2026-11-16 : le jeu avait fermé toutes les façons de lire ses points.)

local _, ns = ...
local SafeCall, IsSecret = ns.SafeCall, ns.IsSecret

local SWITCH_RETRY = 1.5  -- secondes au bout desquelles une bascule que le jeu n'a pas faite est redemandée
local SWITCH_TRIES = 3    -- demandes d'une même bascule, la première comprise
local SWITCH_POLL = 0.5   -- entre deux regards sur l'alternance des pistages

-- Sorts de pistage, d'après Blizzard_Minimap\Mainline\Minimap.lua (build 1.60.1.70245)
local FINDERS = { [2383] = "herb", [8387] = "herb", [2580] = "ore", [8388] = "ore" }

-- Le jeu joue un clic d'interface quand un pistage change (uchatscrollbutton.ogg, 567407, d'après
-- NodeSight 1.8.1). Ce son sert à la plupart des boutons : il n'est coupé que le temps de la bascule,
-- SWITCH_MUTE secondes. (Demandé le 2026-11-09 : « retire le son du changement de découverte lors de
-- l'alternance ».)
local SWITCH_SOUND, SWITCH_MUTE = 567407, 0.6

-- lieu de la dernière bascule (map, x, y), la bascule demandée au jeu tant qu'il ne l'a pas faite :
-- le métier voulu (want), quand (at), combien de fois (tries) ; et jusqu'à quand le clic est coupé (muted)
local turn = { elapsed = 0 }
local looting = false

-- L'alternance ne demande que la liste des pistages du jeu
function ns.CanSwitch()
	return C_Minimap ~= nil and C_Minimap.SetTracking ~= nil and C_Minimap.GetNumTrackingTypes ~= nil
		and C_Minimap.GetTrackingInfo ~= nil
end

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
	-- (ni en combat : les pistages n'y changent pas)
	return looting or InCombatLockdown() or Casting(UnitCastingInfo) or Casting(UnitChannelInfo)
end

local function Unmute()
	if turn.muted and UnmuteSoundFile then pcall(UnmuteSoundFile, SWITCH_SOUND) end
	turn.muted = nil
end

-- Demande au jeu d'allumer le pistage de ce métier (`index`, dans la liste du jeu). Le jeu lance
-- un sort : le pistage ne change qu'un instant plus tard (Blizzard_Minimap le dit de son propre
-- menu), et pas du tout si le sort n'était pas prêt. Renvoie true si la demande est partie.
local function Ask(kind, index)
	turn.want, turn.at, turn.tries = kind, GetTime(), (turn.tries or 0) + 1
	if MuteSoundFile and pcall(MuteSoundFile, SWITCH_SOUND) then turn.muted = GetTime() + SWITCH_MUTE end
	return (pcall(C_Minimap.SetTracking, index, true))
end

-- Allume l'autre pistage quand le joueur s'est éloigné d'assez du lieu de la dernière bascule.
-- Renvoie true s'il l'a demandé.
local function Switch(kind, index)
	if Busy() then return false end
	local map, x, y, wide, tall = MapPosition()
	if not map then return false end
	if map ~= turn.map then -- autre carte : la distance se compte d'ici
		turn.map, turn.x, turn.y = map, x, y
		return false
	end
	local east, north = (x - turn.x) * wide, (y - turn.y) * tall
	local yards = ns.GetOption("nodeSwitchYards")
	if east * east + north * north < yards * yards then return false end
	turn.x, turn.y, turn.tries = x, y, 0
	return Ask(kind, index)
end

local function Wanted()
	return ns.db.enabled and ns.GetOption("nodeSwitch") and ns.CanSwitch()
end

-- Renvoie true si une bascule vient d'être demandée
local function Tick()
	local on, listed = Finders()
	if not on then return false end
	local alternating = listed.herb and listed.ore
	if turn.want then
		if on[turn.want] or not alternating then
			turn.want = nil -- la bascule a eu lieu, ou n'a plus lieu d'être
		elseif GetTime() - turn.at >= SWITCH_RETRY then
			-- Le jeu n'a pas fait la bascule demandée : le sort n'était pas prêt. Elle est redemandée,
			-- quelques fois ; après quoi ce sera pour la prochaine.
			if turn.tries >= SWITCH_TRIES then
				turn.want = nil
			elseif not Busy() then
				return Ask(turn.want, listed[turn.want])
			end
		end
		if turn.want then return false end
	end
	if not alternating or (on.herb == true) == (on.ore == true) then return false end
	local other = on.herb and "ore" or "herb"
	return Switch(other, listed[other])
end

local frame = CreateFrame("Frame")

local function OnUpdate(_, elapsed)
	if turn.muted and GetTime() >= turn.muted then Unmute() end
	turn.elapsed = turn.elapsed + elapsed
	if turn.elapsed < SWITCH_POLL then return end
	turn.elapsed = 0
	Tick()
end

-- Appelée par Settings.lua quand un réglage de l'alternance change, et quand Lueur s'allume ou
-- s'éteint : lance ou arrête la surveillance des pistages
function ns.UpdateTracking()
	if not ns.db then return end
	turn.map, turn.want, turn.elapsed = nil, nil, 0
	local switching = Wanted()
	if not switching then Unmute() end
	frame:SetScript("OnUpdate", switching and OnUpdate or nil)
end

local handlers = {}

function handlers.PLAYER_LOGIN()
	ns.UpdateTracking()
end

function handlers.PLAYER_LOGOUT()
	Unmute() -- (un son coupé le reste jusqu'à ce qu'on le rende, même d'une session à l'autre)
end

function handlers.LOOT_OPENED()
	looting = true
end

function handlers.LOOT_CLOSED()
	looting = false
end

frame:SetScript("OnEvent", function(_, event)
	if ns.db then handlers[event]() end
end)
for event in pairs(handlers) do
	pcall(frame.RegisterEvent, frame, event)
end
