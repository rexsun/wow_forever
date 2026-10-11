local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("itIT") then return end

YUI.Locale:Register("NativeInterface", "itIT", {
    ["name"] = "Blizzard UI",
    ["section.visibility"] = "Elementi nativi",
    ["section.layout"] = "Interface Layout",
    ["section.enhancements"] = "Rialzi di interfaccia",
    ["hide.status_tracking_bars"] = "Nascondi Esperienza e Barre di reputazione",
    ["hide.micro_menu"] = "Nascondi Micro Menu",
    ["hide.bags_bar"] = "Nascondi automaticamente la barra delle borse",
    ["hide.bags_bar.tooltip"] = "Nasconde la barra quando le borse sono chiuse e la mostra quando apri una qualsiasi borsa equipaggiata.",
    ["hide.buff_collapse"] = "Nascondi il pulsante del collo della manna",
    ["hide.buff_collapse.tooltip"] = "Nascondere il pulsante nativo buff crollo/expand e mantenere tutti i buff espansi.",
    ["manage.top_center_widget"] = "Gestisci le notifiche dei clienti",
    ["manage.top_center_widget.tooltip"] = "Aggiungi il contenitore di avviso top-center nativo a YUI Modifica Mode.",
    ["manage.power_bar_widget"] = "Gestisci Scenario Power Bar",
    ["manage.power_bar_widget.tooltip"] = "Aggiungi lo scenario nativo e il contenitore della barra eventi a YUI Modifica Mode.",
    ["tutorial.supertrack"] = "Suppress Quest Supertracking Tutorial",
    ["tutorial.supertrack.tooltip"] = "Riconoscere solo il tutorial di ricerca-supertracking. Disabilitare questa opzione non ripristina un tutorial che è già stato completato.",
    ["settings.native_interface.topCenterWidget.tooltip"] = "Aggiungi il contenitore di avviso top-center nativo a YUI Modifica Mode.",
    ["settings.native_interface.powerBarWidget.tooltip"] = "Aggiungi lo scenario nativo e il contenitore della barra eventi a YUI Modifica Mode.",
    ["settings.native_interface.managed_by_elvui"] = "Questo elemento è già gestito da ElvUI, così YUI non prenderà la proprietà.",
    ["settings.native_interface.managed_by_ndui"] = "Questo elemento è già gestito da NDui, così YUI non prenderà la proprietà.",
    ["settings.native_interface.managed_externally"] = "Un altro addon possiede già la posizione di questo elemento, così YUI non prenderà la proprietà.",
    ["settings.native_interface.unavailable"] = "YUI non poteva verificare che questo elemento può essere spostato in modo sicuro, così la proprietà non è disponibile.",
    ["layout.top_center_widget"] = "Avviso di apertura",
    ["layout.power_bar_widget"] = "Scenario Power Bar",
})
