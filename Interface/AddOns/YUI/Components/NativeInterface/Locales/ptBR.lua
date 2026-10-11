local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ptBR") then return end

YUI.Locale:Register("NativeInterface", "ptBR", {
    ["name"] = "Blizzard UI",
    ["section.visibility"] = " Elementos nativos",
    ["section.layout"] = "Disposição da interface",
    ["section.enhancements"] = " Melhorias de interface",
    ["hide.status_tracking_bars"] = "Ocultar barras de experiência e reputação",
    ["hide.micro_menu"] = "Ocultar o Menu Micro",
    ["hide.bags_bar"] = "Ocultar automaticamente a barra de bolsas",
    ["hide.bags_bar.tooltip"] = "Oculta a barra quando as bolsas estão fechadas e a mostra ao abrir qualquer bolsa equipada.",
    ["hide.buff_collapse"] = "Ocultar botão de colapso Buff",
    ["hide.buff_collapse.tooltip"] = "Ocultar o botão nativo buff colaps/expand e manter todos os buffs expandidos.",
    ["manage.top_center_widget"] = "Gerencie avisos de Top-Center",
    ["manage.top_center_widget.tooltip"] = " Adicione o recipiente de aviso nativo do topo do centro ao Modo de Edição YUI.",
    ["manage.power_bar_widget"] = "Gerencie a Barra de Energia de Cenário",
    ["manage.power_bar_widget.tooltip"] = " Adicione o cenário nativo e recipiente de barra de energia de evento ao Modo de Edição YUI.",
    ["tutorial.supertrack"] = "Suprimir Quest Supertracking Tutorial",
    ["tutorial.supertrack.tooltip"] = "Reconheça apenas o tutorial de controlo da procura. A desactivação desta opção não devolve um tutorial que já tenha sido completado.",
    ["settings.native_interface.topCenterWidget.tooltip"] = " Adicione o recipiente de aviso nativo do topo do centro ao Modo de Edição YUI.",
    ["settings.native_interface.powerBarWidget.tooltip"] = " Adicione o cenário nativo e recipiente de barra de energia de evento ao Modo de Edição YUI.",
    ["settings.native_interface.managed_by_elvui"] = "Este elemento já é gerido pela ElvUI, por isso a YUI não assume a propriedade.",
    ["settings.native_interface.managed_by_ndui"] = " Esse elemento já é gerenciado pelo NDui, então o YUI não assumirá a posse.",
    ["settings.native_interface.managed_externally"] = " Outro addon já possui a posição deste elemento, assim que YUI não vai tomar posse.",
    ["settings.native_interface.unavailable"] = "O YUI não pôde verificar que este elemento pode ser movido com segurança, por isso a propriedade está indisponível.",
    ["layout.top_center_widget"] = " Avisos Top-Center",
    ["layout.power_bar_widget"] = "Cenário Power Bar",
})
