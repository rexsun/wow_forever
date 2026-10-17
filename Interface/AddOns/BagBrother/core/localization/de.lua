--[[
	German Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'deDE')
if not L then return end

--keybindings
L.OpenBags = 'Inventar umschalten'
L.OpenBank = 'Bank umschalten'
L.OpenGuild = 'Gildenbank umschalten'
L.OpenVault = 'Leerenlager umschalten'

--terminal
L.Commands = 'Befehlsliste'
L.CmdShowInventory = 'Schaltet das Inventar um'
L.CmdShowBank = 'Schaltet die Bank um'
L.CmdShowGuild = 'Schaltet die Gildenbank um'
L.CmdShowVault = 'Schaltet das Leerenlager um'
L.CmdShowVersion = 'Zeigt die aktuelle Version an'
L.CmdShowOptions = 'Öffnet das Konfigurationsmenü'
L.CmdReset = 'Einstellungen und zwischengespeicherte Daten löschen'
L.ResetConfirm = 'Bist du sicher, dass du %s zurücksetzen möchtest?|nAlle Einstellungen und zwischengespeicherten Daten gehen verloren.'
L.SkinError = 'Fehler beim Anwenden des Skins.'
L.UpgradeError = 'Problem beim Aktualisieren der Einstellungen. Falls Probleme auftreten, versuche, deine Einstellungen zurückzusetzen.'

--titles
L.TitleBags = 'Inventar von %s'
L.TitleBank = 'Bank von %s'
L.TitleVault = 'Leerenlager von %s'
L.NormalBags = 'Normale Taschen'
L.TradeBags = 'Berufstaschen'
L.AmmoBags = 'Munitionstaschen'

--tooltips
L.Bags = 'Taschen'
L.Drag = '<Ziehen>'
L.BrowseItems = 'Gegenstände durchsuchen'
L.HideBag = 'Klicken, um diese Tasche auszublenden.'
L.ShowBag = 'Klicken, um diese Tasche einzublenden.'
L.GuildFunds = 'Gildenkasse'
L.NumAllowed = '%s erlaubt'
L.NumWithdraw = '%d abheben'
L.NumDeposit = '%d einzahlen'
L.NumRemaining = '%s verbleibend'
L.WarbandMoney = 'Kriegsmeutengold'
L.OfflineViewing = 'Offline-Ansicht'
L.Others = 'Andere'

--menus
L.Characters = 'Charaktere'
L.Guilds = 'Gilden'
L.Locations = 'Bereiche'
L.EnterDescription = 'Beschreibung eingeben:'
L.ServerSorting = 'Serverseitige Sortierung'
L.ReverseSorting = 'Reihenfolge umkehren'
L.PartialFirst = 'Teilstapel zuerst'
L.CleanupOptions = 'Aufräumoptionen'
L.IncludeReagents = 'Handwerksmaterialien einbeziehen'
L.LockItems = 'Gegenstandsplätze sperren'

--dialogs
L.AskMafia = 'Mafia fragen'
L.ConfirmDelete = 'Sind Sie sicher, dass Sie die zwischengespeicherten Daten von %s löschen möchten?'
L.ConfirmTransfer = 'Einlagern von Gegenständen wird alle Modifikationen entfernen und sie nicht handelbar und nicht rückgängig machbar machen.|n|nMöchten Sie fortfahren?'
L.CannotPurchaseVault = 'Sie haben nicht genug Geld, um den Leerenlager-Service freizuschalten|n|n|cffff2020Kosten: %s|r'
L.PurchaseVault = 'Möchten Sie den Leerenlager-Service freischalten?|n|n|cffffd200Kosten:|r %s'
L.ConfigurationMode = 'Du befindest dich nun im Konfigurationsmodus für das clientseitige Sortieren.|n|nKlicke auf Gegenstandsplätze, um festzulegen, ob sie beim Sortieren gesperrt werden sollen.'
L.OutOfDate = 'Deine Version von |cffffd200%s|r ist möglicherweise veraltet!|n%s hat Version |cff82c5ff%s|r gemeldet. Bitte aktualisiere, falls dies zutrifft.'
L.InvalidVersion = 'Deine Kopie von |cffffd200%s|r ist entweder beschädigt oder illegal.|nBitte lade kostenlos eine offizielle Version herunter.'
