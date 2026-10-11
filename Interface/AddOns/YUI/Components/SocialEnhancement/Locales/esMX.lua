local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("esMX") then return end

YUI.Locale:Register("SocialEnhancement", "esMX", {
    ["feature.name"] = "Mejoras sociales",
    ["feature.description"] = "Amplía el cambio de objetivo con Tab y las acciones opcionales del menú de jugador.",
    ["settings.tab_cycle"] = "Use Tab / Shift+Tab para ciclar objetivos de chat",
    ["settings.tab_cycle.tooltip"] = "Ciclos a través de objetivos de grupo, gremio y chat mundial sin cambiar el texto de entrada.",
    ["settings.tab_cycle.ychat"] = "El cambio de objetivo de pestaña es gestionado por YChat.",
    ["settings.right_click"] = "Mejore los menús de clic derecho del jugador",
    ["settings.right_click.tooltip"] = "Añade acciones de amigo e invite de gremio a menús de reproductor compatibles.",
    ["settings.right_click.conflict"] = "No disponible porque otro addon de interfaz gestiona estos menús.",
    ["menu.add_friend"] = "Añadir Amigo",
    ["menu.invite_guild"] = "Invita a Guild",
})
