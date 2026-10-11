local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("deDE") then return end

YUI.Locale:Register("NativeInterface", "deDE", {
    ["name"] = "Blizzard UI",
    ["section.visibility"] = "Native Elements",
    ["section.layout"] = "Schnittstellenaufbau",
    ["section.enhancements"] = "Interface Enhancements",
    ["hide.status_tracking_bars"] = "Hide Erfahrung und Reputation Bars",
    ["hide.micro_menu"] = "Mikromenü ausblenden",
    ["hide.bags_bar"] = "Taschenleiste automatisch ausblenden",
    ["hide.bags_bar.tooltip"] = "Blendet die Taschenleiste aus, wenn alle Taschen geschlossen sind, und zeigt sie beim Öffnen einer ausgerüsteten Tasche an.",
    ["hide.buff_collapse"] = "Hide Buff Collapse Button",
    ["hide.buff_collapse.tooltip"] = "Verstecke den nativen buff collapse/expand-Button und halte alle buffs erweitert.",
    ["manage.top_center_widget"] = "Verwalten Sie Top-Center-Notizen",
    ["manage.top_center_widget.tooltip"] = "Fügen Sie den nativen Top-Center-Hinweiscontainer zum YUI Edit Mode hinzu.",
    ["manage.power_bar_widget"] = "Verwalten Sie Szenario Power Bar",
    ["manage.power_bar_widget.tooltip"] = "Fügen Sie den nativen Szenario- und Ereignis-Powerbar-Container in den YUI Edit-Modus ein.",
    ["tutorial.supertrack"] = "Suppress Quest Supertracking Tutorial",
    ["tutorial.supertrack.tooltip"] = "Bestätigen Sie nur das Quest-Supertracking-Tutorial. Deaktivieren dieser Option stellt kein bereits abgeschlossenes Tutorial wieder her.",
    ["settings.native_interface.topCenterWidget.tooltip"] = "Fügen Sie den nativen Top-Center-Hinweiscontainer zum YUI Edit Mode hinzu.",
    ["settings.native_interface.powerBarWidget.tooltip"] = "Fügen Sie den nativen Szenario- und Ereignis-Powerbar-Container in den YUI Edit-Modus ein.",
    ["settings.native_interface.managed_by_elvui"] = "Dieses Element wird bereits von ElvUI verwaltet, so dass YUI kein Eigentum übernimmt.",
    ["settings.native_interface.managed_by_ndui"] = "Dieses Element wird bereits von NDui verwaltet, so dass YUI kein Eigentum übernimmt.",
    ["settings.native_interface.managed_externally"] = "Ein anderes Addon besitzt bereits die Position dieses Elements, so dass YUI kein Eigentum übernimmt.",
    ["settings.native_interface.unavailable"] = "YUI konnte nicht überprüfen, ob dieses Element sicher bewegt werden kann, so dass der Besitz nicht verfügbar ist.",
    ["layout.top_center_widget"] = "Top-Center-Hinweise",
    ["layout.power_bar_widget"] = "Szenario Power Bar",
})
