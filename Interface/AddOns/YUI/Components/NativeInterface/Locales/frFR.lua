local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("frFR") then return end

YUI.Locale:Register("NativeInterface", "frFR", {
    ["name"] = "L'assurance-chômage Blizzard",
    ["section.visibility"] = " Éléments indigènes",
    ["section.layout"] = " Mise en page d'interface",
    ["section.enhancements"] = " Améliorations d'interface",
    ["hide.status_tracking_bars"] = "Cacher les barres d'expérience et de réputation",
    ["hide.micro_menu"] = "Cacher Micro Menu",
    ["hide.bags_bar"] = "Masquer automatiquement la barre des sacs",
    ["hide.bags_bar.tooltip"] = "Masque la barre lorsque les sacs sont fermés et l'affiche dès qu'un sac équipé est ouvert.",
    ["hide.buff_collapse"] = "Cacher le bouton d'effondrement de Buff",
    ["hide.buff_collapse.tooltip"] = "Cacher le bouton Native Buff collant/expand et garder tous les buffs élargi.",
    ["manage.top_center_widget"] = " Gérer les avis Top-Center",
    ["manage.top_center_widget.tooltip"] = " Ajouter le conteneur d'avis du centre supérieur natif au mode édition YUI.",
    ["manage.power_bar_widget"] = " Gérer Scénario Power Bar",
    ["manage.power_bar_widget.tooltip"] = " Ajouter le conteneur de la barre de puissance de scénario et d'événement natif au mode édition YUI.",
    ["tutorial.supertrack"] = "Tutoriel Supprimé Quest Supertracking",
    ["tutorial.supertrack.tooltip"] = " Reconnaître seulement le tutoriel de quest-supertracking. Désactiver cette option ne restaure pas un tutoriel qui a déjà été terminé.",
    ["settings.native_interface.topCenterWidget.tooltip"] = " Ajouter le conteneur d'avis du centre supérieur natif au mode édition YUI.",
    ["settings.native_interface.powerBarWidget.tooltip"] = " Ajouter le conteneur de la barre de puissance de scénario et d'événement natif au mode édition YUI.",
    ["settings.native_interface.managed_by_elvui"] = " Cet élément est déjà géré par ElvUI, donc YUI ne prendra pas en charge.",
    ["settings.native_interface.managed_by_ndui"] = " Cet élément est déjà géré par NDui, donc YUI ne prendra pas en charge.",
    ["settings.native_interface.managed_externally"] = "Un autre addon possède déjà la position de cet élément, donc YUI ne prendra pas en charge.",
    ["settings.native_interface.unavailable"] = "YUI n'a pas pu vérifier que cet élément peut être déplacé en toute sécurité, donc la propriété est indisponible.",
    ["layout.top_center_widget"] = "Avis du centre supérieur",
    ["layout.power_bar_widget"] = " Barre de puissance du scénario",
})
