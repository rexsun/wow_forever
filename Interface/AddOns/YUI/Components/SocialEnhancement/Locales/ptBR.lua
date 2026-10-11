local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ptBR") then return end

YUI.Locale:Register("SocialEnhancement", "ptBR", {
    ["feature.name"] = "Recursos sociais",
    ["feature.description"] = "Melhora a troca de alvo com Tab e as ações opcionais do menu de jogador.",
    ["settings.tab_cycle"] = "Use Tab / Shift+Tab para cycle chat alvo",
    ["settings.tab_cycle.tooltip"] = " Ciclos através de grupos, guild e alvos de bate-papo mundiais suportados sem alterar o texto de entrada.",
    ["settings.tab_cycle.ychat"] = "A mudança de alvo da aba é gerenciada pelo YChat.",
    ["settings.right_click"] = " Melhore os menus do jogador com o botão direito",
    ["settings.right_click.tooltip"] = " Adiciona ações de amigos e guild-invite aos menus do jogador suportados.",
    ["settings.right_click.conflict"] = "Indisponível porque outro addon interface gerencia estes menus.",
    ["menu.add_friend"] = " Adicionar amigo",
    ["menu.invite_guild"] = "Convite para Guild",
})
