--[[
	Dutch Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'nlNL')
if not L then return end

--keybindings
L.OpenBags = 'Inventaris Wisselen'
L.OpenBank = 'Bank Wisselen'
L.OpenGuild = 'Gildebank Wisselen'
L.OpenVault = 'Lege Opslag Wisselen'

--terminal
L.Commands = 'commandolijst'
L.CmdShowInventory = 'Schakelt je inventaris'
L.CmdShowBank = 'Schakelt je bank'
L.CmdShowGuild = 'Schakelt je gildebank'
L.CmdShowVault = 'Schakelt je lege opslag'
L.CmdShowVersion = 'Toont de huidige versie'
L.CmdShowOptions = 'Opent het configuratiemenu'
L.CmdReset = 'Instellingen en cachegegevens wissen'
L.ResetConfirm = 'Weet je zeker dat je %s wilt resetten?|nAlle instellingen en gecachte gegevens gaan verloren.'
L.SkinError = 'Fout bij het toepassen van skin.'
L.UpgradeError = 'Probleem bij het upgraden van instellingen. Als je problemen ondervindt, probeer dan je instellingen te resetten.'

--titles
L.TitleBags = 'Inventaris van %s'
L.TitleBank = 'Bank van %s'
L.TitleVault = 'Lege Opslag van %s'
L.NormalBags = 'Normale tassen'
L.TradeBags = 'Beroepstassen'
L.AmmoBags = 'Munitietassen'

--tooltips
L.Bags = 'Tassen'
L.Drag = '<Slepen>'
L.BrowseItems = 'Bladeren door items'
L.HideBag = 'Klik om deze tas te verbergen.'
L.ShowBag = 'Klik om deze tas te tonen.'
L.GuildFunds = 'Gilde Fonds'
L.NumAllowed = '%s Toegestaan'
L.NumWithdraw = '%s Opname'
L.NumDeposit = '%s Storting'
L.NumRemaining = '%s Resterende'
L.WarbandMoney = 'Warband-goud'
L.OfflineViewing = 'Offline bekijken'
L.Others = 'Anderen'

--menus
L.Characters = 'Personages'
L.Guilds = 'Gilden'
L.Locations = 'Locaties'
L.EnterDescription = 'Voer beschrijving in:'
L.ServerSorting = 'Sorteren aan serverzijde'
L.ReverseSorting = 'Omgekeerde volgorde'
L.PartialFirst = 'Gedeeltelijke stapels eerst'
L.CleanupOptions = 'Opschoonopties'
L.IncludeReagents = 'Inclusief componenten'
L.LockItems = 'Itemvakken vergrendelen'

--dialogs
L.AskMafia = 'Vraag de Maffia'
L.ConfirmDelete = 'Weet je zeker dat je de cachegegevens van %s wilt verwijderen?'
L.ConfirmTransfer = 'Door items te storten worden alle aanpassingen verwijderd en worden ze niet-verhandelbaar en niet-terugbetaalbaar.|n|nWilt u doorgaan?'
L.CannotPurchaseVault = 'Je hebt niet genoeg geld om de Lege Opslagdienst te ontgrendelen|n|n|cffff2020Kosten: %s|r'
L.PurchaseVault = 'Wilt u de Lege Opslagdienst ontgrendelen?|n|n|cffffd200Kosten:|r %s'
L.ConfigurationMode = 'Je bevindt je nu in de configuratiemodus voor sorteren aan de clientzijde.|n|nKlik op itemvakken om te schakelen of ze moeten worden vergrendeld tijdens het sorteren.'
L.OutOfDate = 'Je |cffffd200%s|r versie is mogelijk verouderd!|n%s rapporteerde versie |cff82c5ff%s|r te hebben, update indien dit klopt.'
L.InvalidVersion = 'Je kopie van |cffffd200%s|r is beschadigd of illegaal.|nDownload gratis een officiële build.'
