--[[
	Russian Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'ruRU')
if not L then return end

--keybindings
L.OpenBags = 'Переключить инвентарь'
L.OpenBank = 'Переключить банк'
L.OpenGuild = 'Переключить банк гильдии'
L.OpenVault = 'Переключить Хранилище Бездны'

--terminal
L.Commands = 'Команды:'
L.CmdShowInventory = 'открыть/закрыть инвентарь'
L.CmdShowBank = 'открыть/закрыть банк'
L.CmdShowGuild = 'открыть/закрыть банк гильдии'
L.CmdShowVault = 'открыть/закрыть Хранилище Бездны'
L.CmdShowVersion = 'сообщить текущую версию модификации'
L.CmdShowOptions = 'открыть меню настроек'
L.CmdReset = 'Стереть настройки и кэшированные данные'
L.ResetConfirm = 'Вы уверены, что хотите сбросить %s?|nВсе настройки и кэшированные данные будут потеряны.'
L.SkinError = 'Ошибка при применении скина.'
L.UpgradeError = 'Проблема при обновлении настроек. Если возникнут проблемы, попробуйте сбросить настройки.'

--titles
L.TitleBags = 'Инвентарь |3-1(%s)'
L.TitleBank = 'Банк |3-1(%s)'
L.TitleVault = 'Хранилище Бездны |3-1(%s)'
L.NormalBags = 'Обычные сумки'
L.TradeBags = 'Ремесленные сумки'
L.AmmoBags = 'Сумки для боеприпасов'

--tooltips
L.Bags = 'Сумки'
L.Drag = '<Двигать>'
L.BrowseItems = 'Просмотр предметов'
L.HideBag = 'Нажмите, чтобы скрыть эту сумку.'
L.ShowBag = 'Нажмите, чтобы показать эту сумку.'
L.GuildFunds = 'Золото гильдии'
L.NumAllowed = 'Разрешено: %s'
L.NumWithdraw = '%d снять'
L.NumDeposit = '%d внести'
L.NumRemaining = 'Осталось: %s'
L.WarbandMoney = 'Золото отряда'
L.OfflineViewing = 'Offline-просмотр'
L.Others = 'Другие'

--menus
L.Characters = 'Персонажи'
L.Guilds = 'Гильдии'
L.Locations = 'Места'
L.EnterDescription = 'Введите описание:'
L.ServerSorting = 'Сортировка на сервере'
L.ReverseSorting = 'Обратный порядок'
L.PartialFirst = 'Сначала неполные стопки'
L.CleanupOptions = 'Параметры очистки'
L.IncludeReagents = 'Включая реагенты'
L.LockItems = 'Заблокировать ячейки'

--dialogs
L.AskMafia = 'Взять в долг у мафии'
L.ConfirmDelete = 'Удалить кэшированные данные %s?'
L.ConfirmTransfer = 'Предметы будут лишены всех модификаций. Их нельзя будет вернуть торговцу или выставить на аукцион.|n|nПродолжить?'
L.CannotPurchaseVault = 'У вас недостаточно золота для открытия доступа к Хранилищу Бездны|n|n|cffff2020Стоимость: %s|r'
L.PurchaseVault = 'Хотите открыть доступ к Хранилищу Бездны?|n|n|cffffd200Стоимость:|r %s'
L.ConfigurationMode = 'Вы находитесь в режиме настройки сортировки на стороне клиента.|n|nНажмите на ячейку предмета, чтобы заблокировать/разблокировать её при сортировке.'
L.OutOfDate = 'Ваша версия |cffffd200%s|r может быть устаревшей!|nУ %s обнаружена версия |cff82c5ff%s|r, пожалуйста, обновите свою.'
L.InvalidVersion = 'Ваша копия |cffffd200%s|r повреждена или получена незаконно.|nПожалуйста, скачайте официальную сборку бесплатно.'
