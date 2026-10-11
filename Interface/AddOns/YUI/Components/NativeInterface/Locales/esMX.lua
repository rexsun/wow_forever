local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("esMX") then return end

YUI.Locale:Register("NativeInterface", "esMX", {
    ["name"] = "Blizzard UI",
    ["section.visibility"] = "Elementos nativos",
    ["section.layout"] = "Interfaz Layout",
    ["section.enhancements"] = "Mejoras de la interfaz",
    ["hide.status_tracking_bars"] = "Ocultar las barras de experiencia y reputación",
    ["hide.micro_menu"] = "Ocultar Micro Menu",
    ["hide.bags_bar"] = "Ocultar automáticamente la barra de bolsas",
    ["hide.bags_bar.tooltip"] = "Oculta la barra cuando las bolsas están cerradas y la muestra al abrir cualquier bolsa equipada.",
    ["hide.buff_collapse"] = "Oculta Buff Collapse Button",
    ["hide.buff_collapse.tooltip"] = "Ocultar el botón Buff nativo/expand y mantener todos los Buffs expandidos.",
    ["manage.top_center_widget"] = "Administrar Avisos de Top-Center",
    ["manage.top_center_widget.tooltip"] = "Agregue el contenedor de aviso nativo de primer centro a YUI Mod Mode.",
    ["manage.power_bar_widget"] = "Manage Scenario Power Bar",
    ["manage.power_bar_widget.tooltip"] = "Agregue el escenario nativo y el contenedor de barras de eventos a YUI Edit Mode.",
    ["tutorial.supertrack"] = "Suppress Quest Supertracking Tutorial",
    ["tutorial.supertrack.tooltip"] = "Reconocer sólo el tutorial de supertección de misiones. Desactivar esta opción no restaura un tutorial que ya ha sido completado.",
    ["settings.native_interface.topCenterWidget.tooltip"] = "Agregue el contenedor de aviso nativo de primer centro a YUI Mod Mode.",
    ["settings.native_interface.powerBarWidget.tooltip"] = "Agregue el escenario nativo y el contenedor de barras de eventos a YUI Edit Mode.",
    ["settings.native_interface.managed_by_elvui"] = "Este elemento ya es gestionado por ElvUI, por lo que YUI no tomará propiedad.",
    ["settings.native_interface.managed_by_ndui"] = "Este elemento ya es gestionado por NDui, por lo que YUI no tomará propiedad.",
    ["settings.native_interface.managed_externally"] = "Otro addon ya posee la posición de este elemento, por lo que YUI no tomará propiedad.",
    ["settings.native_interface.unavailable"] = "YUI no pudo verificar que este elemento puede ser movido con seguridad, así que la propiedad no está disponible.",
    ["layout.top_center_widget"] = "Top-Center Avisos",
    ["layout.power_bar_widget"] = "Scenario Power Bar",
})
