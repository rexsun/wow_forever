local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("frFR") then return end

YUI.Locale:Register("SocialEnhancement", "frFR", {
    ["feature.name"] = "Fonctions sociales",
    ["feature.description"] = "Améliore le ciblage par Tab et ajoute des actions aux menus des joueurs.",
    ["settings.tab_cycle"] = " Utilisez Tab / Maj+Tab pour cycler les cibles de chat",
    ["settings.tab_cycle.tooltip"] = "Cycles à travers des cibles de groupe, guilde et chat mondial supportés sans changer le texte d'entrée.",
    ["settings.tab_cycle.ychat"] = "Le changement de cible est géré par YChat.",
    ["settings.right_click"] = " Améliorez les menus de clic droit du joueur",
    ["settings.right_click.tooltip"] = " Ajoute des actions d'ami et de guild-invite aux menus de joueurs supportés.",
    ["settings.right_click.conflict"] = "Indisponible parce qu'un autre addon d'interface gère ces menus",
    ["menu.add_friend"] = " Ajouter Ami",
    ["menu.invite_guild"] = "Invitez à Guild",
})
