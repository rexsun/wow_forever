--[[
    Spanish Localization (Credits/Blame: Phanx, Woopy, Jaliborc)
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'esES')
if not L then return end

--keybindings
L.OpenBags = 'Mostrar inventario'
L.OpenBank = 'Mostrar banco'
L.OpenGuild = 'Mostrar banco de hermandad'
L.OpenVault = 'Mostrar depósito del vacío'

--terminal
L.Commands = 'Lista de comandos'
L.CmdShowInventory = 'Muestra u oculta tu inventario'
L.CmdShowBank = 'Muestra u oculta tu banco'
L.CmdShowGuild = 'Muestra u oculta el banco de hermandad'
L.CmdShowVault = 'Muestra u oculta la cámara del vacío'
L.CmdShowVersion = 'Muestra la versión actual'
L.CmdShowOptions = 'Abre el menú de configuración'
L.CmdReset = 'Borrar la configuración y los datos en caché'
L.ResetConfirm = '¿Seguro que quieres restablecer %s?|nSe perderán todos los ajustes y datos en caché.'
L.SkinError = 'Error al aplicar la apariencia.'
L.UpgradeError = 'Problema al actualizar la configuración. Si tienes problemas, intenta restablecer la configuración.'

--titles
L.TitleBags = 'Inventario de %s'
L.TitleBank = 'Banco de %s'
L.TitleVault = 'Depósito del Vacío de %s'
L.NormalBags = 'Bolsas normales'
L.TradeBags = 'Bolsas de profesión'
L.AmmoBags = 'Bolsas de munición'

--tooltips
L.Bags = 'Bolsas'
L.Drag = 'Arrastrar'
L.BrowseItems = 'Navegar objetos'
L.HideBag = 'Haz clic para ocultar esta bolsa.'
L.ShowBag = 'Haz clic para mostrar esta bolsa.'
L.GuildFunds = 'Fondos de la hermandad'
L.NumAllowed = '%s permitido'
L.NumWithdraw = 'Retirar %s'
L.NumDeposit = 'Depositar %s'
L.NumRemaining = '%s Restantes'
L.WarbandMoney = 'Dinero de la banda de guerra'
L.OfflineViewing = 'Visualización sin conexión'
L.Others = 'Otros'

--menus
L.Characters = 'Personajes'
L.Guilds = 'Hermandad'
L.Locations = 'Ubicación'
L.EnterDescription = 'Introducir descripción:'
L.ServerSorting = 'Reordenamiento al lado del servidor'
L.ReverseSorting = 'Orden inverso'
L.PartialFirst = 'Pilas parciales primero'
L.CleanupOptions = 'Opciones de limpieza'
L.IncludeReagents = 'Incluir componentes'
L.LockItems = 'Bloquear ranuras'

--dialogs
L.AskMafia = 'Pregunta a La Mafia'
L.ConfirmDelete = '¿Estás seguro de querer eliminar los datos guardados de %s?'
L.ConfirmTransfer = 'Depositar estos objetos eliminará todas las modificaciones y las hará no intercambiables y no reembolsables.|n|n¿Quieres continuar?'
L.CannotPurchaseVault = 'No tienes suficiente dinero para desbloquear el servicio de Depósito del Vacío|n|n|cffff2020Precio: %s|r'
L.PurchaseVault = '¿Quieres desbloquear el servicio de Depósito del Vacío?|n|n|cffffd200Precio: |r %s'
L.ConfigurationMode = 'Ahora estás en el modo de configuración de reordenamiento al lado del cliente.|n|nHaz clic en las ranuras de objetos para alternar si deben bloquearse mientras se reordenan.'
L.OutOfDate = 'Tu versión de |cffffd200%s|r podría ser desactualizada!|n%s informó haber|n|cff82c5ff%s|r, actualice si es cierto.'
L.InvalidVersion = 'Tu copia de |cffffd200%s|r está corrupta o es ilegal..|nDescarga una versión oficial de forma gratuita.'
