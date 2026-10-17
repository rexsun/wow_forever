--[[
	French Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'frFR')
if not L then return end

--keybindings
L.OpenBags = 'Afficher votre inventaire'
L.OpenBank = 'Afficher votre banque'
L.OpenGuild = 'Afficher votre banque de guilde'
L.OpenVault = 'Afficher votre chambre du Vide'

--terminal
L.Commands = 'Liste des commandes :'
L.CmdShowInventory = 'Affiche ou cache votre inventaire'
L.CmdShowBank = 'Affiche ou cache votre banque'
L.CmdShowGuild = 'Affiche ou cache votre banque de guilde'
L.CmdShowVault = 'Affiche ou cache votre chambre du Vide'
L.CmdShowVersion = 'Affiche la version actuelle'
L.CmdShowOptions = 'Ouvre le menu de configuration'
L.CmdReset = 'Effacer les paramètres et les données en cache'
L.ResetConfirm = 'Êtes-vous sûr de vouloir réinitialiser %s ?|nTous les paramètres et données en cache seront perdus.'
L.SkinError = 'Erreur lors de l’application du thème.'
L.UpgradeError = 'Problème lors de la mise à jour des paramètres. En cas de problème, essayez de réinitialiser vos paramètres.'

--titles
L.TitleBags = 'Inventaire |2 %s'
L.TitleBank = 'Banque |2 %s'
L.TitleVault = 'Chambre du Vide |2 %s'
L.NormalBags = 'Sacs normaux'
L.TradeBags = 'Sacs de métier'
L.AmmoBags = 'Sacs de munitions'

--tooltips
L.Bags = 'Sacs'
L.Drag = '<Saisir>'
L.BrowseItems = 'Parcourir les objets'
L.HideBag = 'Clic pour masquer ce sac.'
L.ShowBag = 'Clic pour afficher ce sac.'
L.GuildFunds = 'Fonds de Guilde'
L.NumAllowed = '%s autorisés'
L.NumWithdraw = '%d |4retrait:retraits;'
L.NumDeposit = '%d |4dépôt:dépôts;'
L.NumRemaining = '%s restants'
L.WarbandMoney = 'Or du bataillon'
L.OfflineViewing = 'Consultation hors ligne'
L.Others = 'Autres'

--menus
L.Characters = 'Personages'
L.Guilds = 'Guildes'
L.Locations = 'Emplacements'
L.EnterDescription = 'Saisir une description :'
L.ServerSorting = 'Tri côté serveur'
L.ReverseSorting = 'Ordre inverse'
L.PartialFirst = 'Piles partielles en premier'
L.CleanupOptions = 'Options de nettoyage'
L.IncludeReagents = 'Inclure les composants'
L.LockItems = 'Verrouiller les emplacements'

--dialogs
L.AskMafia = 'Demander à la Mafia'
L.ConfirmDelete = 'Etes-vous sur de vouloir supprimer le cache de %s ?'
L.ConfirmTransfer = 'Déposer un objet retirera toute modification et le rendra non échangeable et non remboursable.|n|nVoulez-vous continuer?'
L.CannotPurchaseVault = 'Pas assez d\'or pour débloquer la Chambre du Vide|n|n|cffff2020Cost: %s|r'
L.PurchaseVault = 'Souhaitez-vous débloquer la Banque du Chambre?|n|n|cffffd200Cost:|r %s'
L.ConfigurationMode = 'Vous êtes maintenant dans le mode de configuration du tri côté client.|n|nCliquez sur les emplacements d\'objets pour choisir s\'ils doivent être verrouillés pendant le tri.'
L.OutOfDate = 'Votre version de |cffffd200%s|r est peut-être obsolète !|n%s a signalé avoir la version |cff82c5ff%s|r, veuillez mettre à jour si c\'est le cas.'
L.InvalidVersion = 'Votre copie de |cffffd200%s|r est corrompue ou illégale.|nVeuillez télécharger gratuitement une version officielle.'
