-------------------------------------------------------------------------------
-- Portuguese localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "Desativado: Conflito com %s";


l.WHATSNEW = l.YL..l.VERS_TITLE.." -"..l.YLL..l.WHATSNEW;

l.SUBTITLE      = "Assist\195\170ncia de quadros de raide";
l.DESC          = "Melhora os quadros de raide.\n\n"
.." - Destaca o fundo de jogadores com pouca vida\n\n"
.." - Barras invertidas usar\195\163o sua escolha de cores\n\n"
.." - Transpar\195\170ncia de unidades fora de alcance\n\n"
.." - Raide sempre vis\195\173vel\n\n"
.."\n"
.."Melhora os b\195\186fes / debufes (tamanho, m\195\161ximo exibido, ...)\n\n"
.."Coloriza os nomes na barra de informa\195\167\195\182es, com \195\174cones JxJ |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."Exibe os \195\174cones de alvo (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) nos quadros de raide\n\n"
l.OPTIONS_TITLE = format("%s - Op\195\167\195\182es", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s carregado", l.VERS_TITLE);
l.MSG_SDB            = "Kallye menu de Op\195\167\195\182es";

l.INIT_FAILED = format("%s n\195\163o carregado corretamente!", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Grupo / Raide";
l.OPTION_HIGHLIGHTLOWHP = "Destacar pouca vida (cores din\195\162micas)"..required;
l.OPTION_REVERTBAR = "Barras de "..l.YL.."vida invertidas|r (quanto menos vida, maior a barra!) ";
l.OPTION_HEALTH_LOW = "Quase morto!";
l.OPTION_HEALTH_LOW_TOOLTIP = "A cor ser\195\161 aplicada "..l.YLL.."ABAIXO|r deste limite\n\n"
    .."ex: Vermelho abaixo de 25%";
l.OPTION_HEALTH_WARN = "Aten\195\167\195\163o";
l.OPTION_HEALTH_WARN_TOOLTIP = "A cor ser\195\161 aplicada "..l.YLL.."NESTE|r limite\n\n"
    .."ex: Amarelo em 50%";
l.OPTION_HEALTH_OK = "Boa sa\195\186de";
l.OPTION_HEALTH_OK_TOOLTIP = "A cor ser\195\161 aplicada "..l.YLL.."ACIMA|r deste limite\n\n"
    .."ex: Verde ap\195\180s 75%";
l.OPTION_HEALTH_ALPHA = l.WH.."Transpar\195\170ncia"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Transpar\195\170ncia da barra de vida (com a cor da classe)\n"..l.CY.."Padr\195\163o no Wow: 100%"
l.OPTION_MOVEROLEICONS = "\195\174cone de fun\195\167\195\163o no canto superior esquerdo";
l.OPTION_HIDEDAMAGEICONS = "Ocultar o \195\174cone de fun\195\167\195\163o 'dano'";
l.OPTION_HIDEREALM = "Ocultar o reino dos jogadores";
l.OPTION_HIDEREALM_TOOLTIP = "Os nomes dos reinos ser\195\163o ocultados, assim "..l.YLL.."Illidan - Varimathras|r se tornar\195\161 "..l.YLL.."Illidan (*)|r";
l.OPTION_ICONONDEATH = "Adicionar "..l.RT8.." aos nomes dos mortos";
l.OPTION_FRIENDSCLASSCOLOR = "Nomes coloridos por classe";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Nomes dos jogadores coloridos por classe (quadros de grupo/raide)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard : %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s : %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "Textura"
l.OPTION_BAR_TEXTURE_TOOLTIP = "Textura da barra de vida"
l.OPTION_SOLORAID = l.CY.."Exibe os quadros de raide em modo solo "..required;
l.OPTION_SOLORAID_TOOLTIP = "Quadros de grupo/raide sempre vis\195\173veis,\nativar\195\161 "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;

l.OPTION_EDITMODE_PARTY = format("Blizzard : %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! Testar os quadros de raide !";
l.OPTION_DEBUG_ON_MESSAGE = "Teste dos quadros de raide ativado, clique novamente para parar!";
l.OPTION_DEBUG_OFF = "! PARAR O TESTE !";
l.OPTION_DEBUG_OFF_MESSAGE = "Teste parado, voc\195\170 pode retomar a atividade normal";

l.OPTION_ACTIVATE_MODULE = "Ativar / Desativar o m\195\186dulo"
l.OPTION_HIDEDISABLED = l.GYL.."Ocultar m\195\186dulos desativados"

-- KF START
l.OPTION_INRANGE = "Transpar\195\170ncia quando em alcance";
l.OPTION_INRANGE_TOOLTIP = l.CY.."Padr\195\163o no Wow: 100%";
l.OPTION_NOTINRANGE = "Transpar\195\170ncia se fora de alcance";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."Padr\195\163o no Wow: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "Transpar\195\170ncia do raide fora de combate";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."Padr\195\163o no Wow: 100%";
l.OPTION_ALPHADISPELOVERLAY = "Transpar\195\170ncia do Overlay de Dissipa\195\167\195\163o"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."Os b\195\186fes/debuffs da Blizzard ser\195\163o substitu\195\173dos por RaidFrameAuras" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Debufes / B\195\186fes"
l.OPTION_ORIENTATION_LeftThenUp = "\195\128 Esquerda, depois para Cima"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."\195\128 Esquerda, depois para Cima (padr\195\163o)"
l.OPTION_ORIENTATION_UpThenLeft = "Para Cima, depois \195\128 Esquerda"
l.OPTION_ORIENTATION_RightThenUp = "\195\128 Direita, depois para Cima"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."\195\128 Direita, depois para Cima (padr\195\163o)"
l.OPTION_ORIENTATION_UpThenRight = "Para Cima, depois \195\128 Direita"
l.OPTION_BUFFSSCALE = "Tamanho dos b\195\186fes "..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."Padr\195\163o no Wow: 1"
l.OPTION_MAXBUFFS = "Limite de b\195\186fes"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "N\195\186mero m\195\161ximo de b\195\186fes a exibir\n"..l.CY.."Padr\195\163o no Wow: "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4b\195\186fe:b\195\186fes";
l.OPTION_BUFFSPERLINE = "B\195\186fes por linha"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "N\195\186mero de b\195\186fes por linha\n"..l.CY.."Ignorado se superior ao Limite";
l.OPTION_BUFFSPERLINE_FORMAT = "%d por linha";
l.OPTION_BUFFSORIENTATION = "Orienta\195\167\195\163o dos b\195\186fes"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "Escolha o arranjo dos b\195\186fes (suporta m\195\186ltiplas linhas)\n"..l.CY.."Padr\195\163o: "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "Posi\195\167\195\163o horizontal"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Ajuste a posi\195\167\195\163o horizontal relativa dos b\195\186fes";
l.OPTION_BUFFS_RELATIVE_Y = "Posi\195\167\195\163o vertical"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Ajuste a posi\195\167\195\163o vertical relativa dos b\195\186fes";
l.OPTION_DEBUFFSSCALE = "Tamanho dos debufes "..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."Padr\195\163o no Wow: 1"
l.OPTION_MAXDEBUFFS = "Limite de debufes"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "N\195\186mero m\195\161ximo de debufes a exibir\n"..l.CY.."Padr\195\163o no Wow: "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4debufe:debufes";
l.OPTION_DEBUFFSPERLINE = "Debufes por linha"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "N\195\186mero de \195\174cones de debufe por linha\n"..l.CY.."Ignorado se superior ao Limite";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d por linha";
l.OPTION_DEBUFFSORIENTATION = "Orienta\195\167\195\163o dos debufes"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "Escolha o arranjo dos debufes (suporta m\195\186ltiplas linhas)\n"..l.CY.."Padr\195\163o: "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "Posi\195\167\195\163o horizontal"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Ajuste a posi\195\167\195\163o horizontal relativa dos debufes";
l.OPTION_DEBUFFS_RELATIVE_Y = "Posi\195\167\195\163o vertical"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Ajuste a posi\195\167\195\163o vertical relativa dos debufes";
l.OPTION_USETAINTMETHOD = l.CY.."Exibi\195\167\195\163o cl\195\161ssica do Limite de b\195\186fes / debufes"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "Desmarcado, usa a exibi\195\167\195\163o experimental\nMarcado, usa a exibi\195\167\195\163o est\195\161vel, mas com um "..l.RDL.."erro por sess\195\163o|r, n\195\163o t\195\163o grave..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Alterar o Limite causa um "..l.RDL.."erro por sess\195\163o|r, n\195\163o t\195\163o grave..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." O reposicionamento pode ser afetado por alguns segundos ap\195\180s a morte de um chefe"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Ocultar auras da Blizzard"
l.OPTION_BUFFS_RESET = "Cancelar todo o reposicionamento"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Auto — acompanha o combate (padrão)";
l.OPTION_FILTER_RAID = "Sempre a lista fora de combate";
l.OPTION_FILTER_RAID_IN_COMBAT = "Sempre a lista em combate";
l.OPTION_BUFFS_SPACING_X = "Espaçamento horizontal";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Espaço horizontal, em pixels, entre os ícones de bônus\n"..l.CY.."Padrão: 0";
l.OPTION_BUFFS_SPACING_Y = "Espaçamento vertical";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Espaço vertical, em pixels, entre os ícones de bônus\n"..l.CY.."Padrão: 1";
l.OPTION_BUFFSFILTER = "Filtro de bônus";
l.OPTION_BUFFSFILTER_TOOLTIP = "Qual lista de bônus a Blizzard fornece\n"..l.CY.."Auto alterna ao entrar e sair de combate";
l.OPTION_BUFFS_HIDETOOLTIP = "Ocultar dicas dos bônus"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Sem dica ao passar o cursor sobre um ícone de bônus\n"..l.RDL.."Também desativa o clique direito para cancelar um bônus";
l.OPTION_DEBUFFS_SPACING_X = "Espaçamento horizontal";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Espaço horizontal, em pixels, entre os ícones de penalidades\n"..l.CY.."Padrão: 0";
l.OPTION_DEBUFFS_SPACING_Y = "Espaçamento vertical";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Espaço vertical, em pixels, entre os ícones de penalidades\n"..l.CY.."Padrão: 1";
l.OPTION_DEBUFFSFILTER = "Filtro de penalidades";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Qual lista de penalidades a Blizzard fornece\n"..l.CY.."Auto alterna ao entrar e sair de combate";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Ocultar dicas das penalidades"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Sem dica ao passar o cursor sobre um ícone de penalidade\n"..l.RDL.."Também desativa o clique direito para cancelar uma penalidade";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Barras de informa\195\167\195\182es";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Padr\195\163o";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "Cores de classe";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "Sua escolha de cor: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Sem \195\174cone";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "\195\174cone de fac\195\167\195\163o |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "Cor se inferior";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "Selecione a cor do n\195\173vel se for inferior ao seu";
l.OPTION_NAMEPLATES_COLOR_OVER = "Cor se superior";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "Selecione a cor do n\195\173vel se for superior ao seu";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Nunca";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Nunca mostra o n\195\173vel nas barras de informa\195\167\195\182es.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Se diferente do seu";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Se diferente do seu, colorido";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Sempre";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Sempre, colorido";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Nomes aliados";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Cor do nome nas barras de informa\195\167\195\182es aliadas (fora de inst\195\162ncias)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Barras aliadas";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Cor das barras de informa\195\167\195\182es aliadas (fora de inst\195\162ncias)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Textura Barras aliadas"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textura das barras de informa\195\167\195\182es aliadas (fora de inst\195\162ncias)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "\195\174cones JxJ aliados";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Exibe os \195\174cones JxJ nos nomes aliados.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "N\195\173veis aliados";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Exibe o n\195\173vel nas barras de informa\195\167\195\182es aliadas.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Nomes inimigos";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Cor do nome nas barras de informa\195\167\195\182es inimigas (fora de inst\195\162ncias)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Barras inimigas";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Cor das barras de informa\195\167\195\182es inimigas (fora de inst\195\162ncias)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Textura Barras inimigas"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textura das barras de informa\195\167\195\182es inimigas (fora de inst\195\162ncias)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "\195\174cones JxJ inimigos";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Exibe os \195\174cones JxJ nos nomes inimigos.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "N\195\173veis inimigos";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Exibe o n\195\173vel nas barras de informa\195\167\195\182es inimigas.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."Exibe os \195\174cones de alvo (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) nos quadros de raide"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "\195\174cones de raide";
l.OPTION_RAIDICONS_ANCHOR = "Alinhamento dos \195\174cones";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Posi\195\167\195\163o do \195\174cone de alvo no quadro de raide";
l.OPTION_CENTER = "Centro"
l.OPTION_TOPLEFT = "Superior Esquerdo";
l.OPTION_TOPRIGHT = "Superior Direito";
l.OPTION_BOTTOMLEFT = "Inferior Esquerdo";
l.OPTION_BOTTOMRIGHT = "Inferior Direito";
l.OPTION_RAIDICONS_SIZE = "Tamanho dos \195\174cones";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Ajuste o tamanho dos \195\174cones de raide";
l.OPTION_RAIDICONS_RELATIVE_X = "Posi\195\167\195\163o horizontal";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Ajuste a posi\195\167\195\163o horizontal relativa dos \195\174cones de raide";
l.OPTION_RAIDICONS_RELATIVE_Y = "Posi\195\167\195\163o vertical";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Ajuste a posi\195\167\195\163o vertical relativa dos \195\174cones de raide";
-- KRI END

l.OPTION_RESET_OPTIONS = "Redefinir o perfil";
l.OPTION_RELOAD_REQUIRED = "Algumas altera\195\167\195\182es exigem um recarregamento (digite: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Op\195\167\195\182es que exigem um recarregamento";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Exibir mensagens";
l.OPTION_SHOWMSGWARNING = l.GYL.."Exibir alertas";
l.OPTION_SHOWMSGERR = l.GYL.."Exibir erros";
l.OPTION_COMPARTMENT_FILTER = "Exibir no Filtro de Compartimento";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "Na lista de addons no canto superior direito";
l.OPTION_WHATSNEW = "Novidades";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Lembre-se de ativar a op\195\167\195\163o "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Exibir quadros do grupo enquanto solo "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Mostrar tamb\195\169m os quadros do grupo em raide"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Mostrar tanto os quadros do grupo quanto os de raide (enquanto em raide)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s a op\195\167\195\163o %s|r dos %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Nota: Digite "..l.YL.."/reload|r ap\195\180s o "..HUD_EDIT_MODE_MENU..", para evitar qualquer erro";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Ativa o "..l.YL..HUD_EDIT_MODE_MENU.."|r, e exibe diretamente as op\195\167\195\182es de "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "Teste dos quadros de raide ativado (test\195\161vel em "..HUD_EDIT_MODE_MENU..")\n"
                    .."Clique novamente para parar!";
end
