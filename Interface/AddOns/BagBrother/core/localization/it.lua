--[[
	Italian Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'itIT')
if not L then return end

--keybindings
L.OpenBags = "Attiva l'Inventario"
L.OpenBank = 'Attiva la Banca'
L.OpenGuild = 'Attiva la Banca di Gilda'
L.OpenVault = 'Attiva la Banca Eterea'

--terminal
L.Commands = 'lista comandi:'
L.CmdShowInventory = 'Mostra il tuo Inventario'
L.CmdShowBank = 'Mostra la tua Banca'
L.CmdShowGuild = 'Mostra la tua Banca di Gilda'
L.CmdShowVault = 'Mostra la tua Banca Eterea'
L.CmdShowVersion = 'Mostra la versione attuale'
L.CmdShowOptions = 'Apri il menù di configurazione'
L.CmdReset = 'Cancella impostazioni e dati memorizzati nella cache'
L.ResetConfirm = 'Sei sicuro di voler reimpostare %s?|nTutte le impostazioni e i dati memorizzati nella cache andranno persi.'
L.SkinError = 'Errore durante l’applicazione della skin.'
L.UpgradeError = 'Problema durante l’aggiornamento delle impostazioni. Se riscontri problemi, prova a reimpostare le tue impostazioni.'

--titles
L.TitleBags = 'Inventario di %s'
L.TitleBank = 'Banca di %s'
L.TitleVault = 'Banca Eterea di %s'
L.NormalBags = 'Borse Normali'
L.TradeBags = 'Borse dei Mestieri'
L.AmmoBags = 'Borse per Munizioni'

--tooltips
L.Bags = 'Borse'
L.Drag = '<Trascina>'
L.BrowseItems = 'Sfoglia Oggetti'
L.HideBag = 'Clicca per nascondere questa borsa.'
L.ShowBag = 'Clicca per mostrare questa borsa.'
L.GuildFunds = 'Fondi di Gilda'
L.NumAllowed = '%s Consentito'
L.NumWithdraw = '%d Prelevati'
L.NumDeposit = '%d Depositati'
L.NumRemaining = '%s Rimanenti'
L.WarbandMoney = 'Fondi della Brigata'
L.OfflineViewing = 'Visualizzazione Offline'
L.Others = 'Altri'

--menus
L.Characters = 'Personaggi'
L.Guilds = 'Gilde'
L.Locations = 'Posizioni'
L.EnterDescription = 'Inserisci Descrizione:'
L.ServerSorting = 'Ordinamento Lato Server'
L.ReverseSorting = 'Ordine Inverso'
L.PartialFirst = 'Pile parziali prima'
L.CleanupOptions = 'Opzioni di Pulizia'
L.IncludeReagents = 'Includi Reagenti'
L.LockItems = 'Blocca Slot Oggetti'

--dialogs
L.AskMafia = 'Chiedi alla Mafia'
L.ConfirmDelete = 'Sei sicuro di voler eliminare i dati di %s presenti nella cache?'
L.ConfirmTransfer = 'Depositare qualsiasi oggetto rimuoverà qualsiasi modifica e/o incantamento e lo renderà non scambiabile e non rimborsabile.|n|nVuoi continuare?'
L.CannotPurchaseVault = 'Non hai abbastasnza soldi per sbloccare il servizio di Banca Eterea|n|n|cffff2020Costo: %s|r'
L.PurchaseVault = 'Vuoi sbloccare il servizio di Banca Eterea?|n|n|cffffd200Costo:|r %s'
L.ConfigurationMode = 'Sei ora nella modalità di configurazione dell\'ordinamento lato client.|n|nClicca sugli slot degli oggetti per decidere se bloccarli durante il riordinamento.'
L.OutOfDate = 'La tua copia di |cffffd200%s|r potrebbe essere obsoleta!|n%s ha riferito di avere la |cff82c5ff%s|r, si prega di aggiornare se è vero.'
L.InvalidVersion = 'La tua copia di |cffffd200%s|r è corrotta o illegale.|nSi prega di scaricare una versione ufficiale gratuita.'
