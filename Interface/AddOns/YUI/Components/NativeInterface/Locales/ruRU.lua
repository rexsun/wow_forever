local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ruRU") then return end

YUI.Locale:Register("NativeInterface", "ruRU", {
    ["name"] = "Blizzard UI",
    ["section.visibility"] = "Родные стихии",
    ["section.layout"] = "Интерфейсный план",
    ["section.enhancements"] = "Улучшение интерфейса",
    ["hide.status_tracking_bars"] = "Скрыть опыт и репутационные бары",
    ["hide.micro_menu"] = "Спрячь микроменю",
    ["hide.bags_bar"] = "Автоматически скрывать панель сумок",
    ["hide.bags_bar.tooltip"] = "Скрывает панель, когда все сумки закрыты, и показывает её при открытии любой надетой сумки.",
    ["hide.buff_collapse"] = "Спрячь пуговицу Баффа",
    ["hide.buff_collapse.tooltip"] = "Hide the native buff collapse/expand button and keep all buffs expanded.",
    ["manage.top_center_widget"] = "Управляйте уведомлениями топ-центра",
    ["manage.top_center_widget.tooltip"] = "Добавьте контейнер уведомлений в верхнем центре в режим редактирования YUI.",
    ["manage.power_bar_widget"] = "Управлять сценарием Power Bar",
    ["manage.power_bar_widget.tooltip"] = "Добавьте нативный сценарий и контейнер блоков питания событий в режим редактирования YUI.",
    ["tutorial.supertrack"] = "Скачать Suppress Quest Supertracking",
    ["tutorial.supertrack.tooltip"] = "Признайте только учебник по квест-супертрекингам. Отключение этого варианта не восстанавливает уже завершенный учебник.",
    ["settings.native_interface.topCenterWidget.tooltip"] = "Добавьте контейнер уведомлений в верхнем центре в режим редактирования YUI.",
    ["settings.native_interface.powerBarWidget.tooltip"] = "Добавьте нативный сценарий и контейнер блоков питания событий в режим редактирования YUI.",
    ["settings.native_interface.managed_by_elvui"] = "Этот элемент уже управляется ElvUI, поэтому YUI не возьмет на себя управление.",
    ["settings.native_interface.managed_by_ndui"] = "Этот элемент уже управляется NDui, поэтому YUI не возьмет на себя ответственность.",
    ["settings.native_interface.managed_externally"] = "Еще один аддон уже владеет позицией этого элемента, поэтому YUI не возьмет на себя ответственность.",
    ["settings.native_interface.unavailable"] = "YUI не может проверить, что этот элемент может быть безопасно перемещен, поэтому владение недоступно.",
    ["layout.top_center_widget"] = "Уведомления высшего центра",
    ["layout.power_bar_widget"] = "Сценарий Power Bar",
})
