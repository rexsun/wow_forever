local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ptBR") then return end

YUI.Locale:Register("RightPlus", "ptBR", {
    ["feature.name"] = "Ações do menu de contexto",
    ["feature.description"] = "Adiciona ações de amizade e guilda aos menus de jogadores.",
})
