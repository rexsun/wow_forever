local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("itIT") then return end

YUI.Locale:Register("SocialEnhancement", "itIT", {
    ["feature.name"] = "Funzioni sociali",
    ["feature.description"] = "Migliora il cambio bersaglio con Tab e le azioni opzionali del menu giocatore.",
    ["settings.tab_cycle"] = "Utilizzare scheda / Shift+Tab per cicli obiettivi di chat",
    ["settings.tab_cycle.tooltip"] = "Cicli attraverso gruppi supportati, gilda e obiettivi di chat mondiale senza cambiare il testo di input.",
    ["settings.tab_cycle.ychat"] = "Il commutatore di destinazione di scheda è gestito da YChat.",
    ["settings.right_click"] = "Migliorare i menu di scelta rapida del lettore",
    ["settings.right_click.tooltip"] = "Aggiunge le azioni di amico e gilda-invita a menu di gioco supportati.",
    ["settings.right_click.conflict"] = "Non disponibile perché un'altra interfaccia addon gestisce questi menu.",
    ["menu.add_friend"] = "Aggiungi amico",
    ["menu.invite_guild"] = "Invita a Guild",
})
