-- Lueur : textes en portugais du Brésil (traduction automatique, non relue)
local _, ns = ...

local L = {}
ns.LOCALES.ptBR = L

L.LANGUAGE_NAME = "Português"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "sim"
L.NO = "não"
L.SETTING = "%s: %s"
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d m"
L.CONFIRM = "Confirmar?"

-- pas de mots de commande propres : les noms anglais répondent
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "Minérios"
L.CATEGORY_ORE_TIP = "Veios de minério."
L.CATEGORY_HERB = "Ervas"
L.CATEGORY_HERB_TIP = "Plantas coletáveis."
L.CATEGORY_QUEST = "Missões"
L.CATEGORY_QUEST_TIP = "Objetos ligados a uma missão em andamento."
L.CATEGORY_CHEST = "Baús"
L.CATEGORY_CHEST_TIP = "Baús, caixas e outros recipientes para saquear."
L.CATEGORY_BOBBER = "Boia"
L.CATEGORY_BOBBER_TIP = "A boia da sua linha de pesca."
L.CATEGORY_OTHER = "Outros"
L.CATEGORY_OTHER_TIP = "Objetos do dia a dia: portas, caixas de correio, alavancas…"

-- la catégorie d'un objet, dans une phrase du diagnostic
L.NAME_ORE = "minério"
L.NAME_HERB = "erva"
L.NAME_QUEST = "missão"
L.NAME_CHEST = "baú"
L.NAME_BOBBER = "boia"
L.NAME_OTHER = "outro"
L.NAME_NONE = "nenhuma"
L.NAME_UNNAMED = "Objetos sem nome"

-- l'objet que l'aperçu montre pour chaque catégorie
L.SAMPLE_ORE = "Veio de Cobre"
L.SAMPLE_HERB = "Botão-da-paz"
L.SAMPLE_QUEST = "Caixa de Suprimentos"
L.SAMPLE_CHEST = "Baú Surrado"
L.SAMPLE_BOBBER = "Boia"
L.SAMPLE_OTHER = "Caixa de Correio"

L.STATE_FAR = "fora de alcance"
L.STATE_READY = "ao alcance"
L.STATE_LOCKED = "indisponível"

L.EFFECT_AURA = "Aura"
L.EFFECT_AURA_TIP = "Um halo de luz e suas volutas, com anel, cometas e vaga-lumes."
L.EFFECT_SUBTLE = "Sutil"
L.EFFECT_SUBTLE_TIP = "Um brilho suave, sem anel nem cometas."
L.EFFECT_SIGIL = "Selo"
L.EFFECT_SIGIL_TIP = "Um círculo de runas gira devagar em volta do objeto."
L.EFFECT_BRACKETS = "Mira"
L.EFFECT_BRACKETS_TIP = "Quatro cantos cercam o objeto e travam nele quando fica ao alcance."
L.EFFECT_VORTEX = "Vórtice"
L.EFFECT_VORTEX_TIP = "Braços de luz se enrolam no objeto, como um portal se abrindo."
L.EFFECT_FLAME = "Chama"
L.EFFECT_FLAME_TIP = "Línguas de fogo sobem do objeto, na cor dele."
L.EFFECT_RIFT = "Fenda"
L.EFFECT_RIFT_TIP = "Um buraco negro cercado de luz suga faíscas em espiral."
L.EFFECT_STORM = "Raio"
L.EFFECT_STORM_TIP = "Uma nuvem de tempestade se forma sobre o objeto, e raios caem dela."
L.EFFECT_GEYSER = "Gêiser"
L.EFFECT_GEYSER_TIP = "Uma fonte de luz jorra do objeto e cai em volta dele."
L.EFFECT_SPIRIT = "Alma"
L.EFFECT_SPIRIT_TIP = "Dois fogos-fátuos dançam em volta do objeto, puxando uma fita de luz."
L.EFFECT_BEAM = "Feixe"
L.EFFECT_BEAM_TIP = "Uma coluna de luz sobe do objeto, percorrida por faíscas."
L.EFFECT_BEACON = "Farol"
L.EFFECT_BEACON_TIP = "Um cristal flutua sobre o objeto, ligado a ele por um fio de luz."
L.EFFECT_ORBIT = "Órbita"
L.EFFECT_ORBIT_TIP = "Três fogos-fátuos giram em volta do objeto, cada um na sua órbita."
L.EFFECT_RIPPLE = "Onda"
L.EFFECT_RIPPLE_TIP = "Ondas se espalham pelo chão em volta do objeto."
L.EFFECT_SPARKLE = "Centelhas"
L.EFFECT_SPARKLE_TIP = "Brilhos cintilam em volta do objeto, sem círculo algum."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "Silhueta"
L.HEADER_OBJECTS = "Objetos destacados"
L.HEADER_HIDE = "Ocultar efeito"
L.HEADER_DETECTION = "Detecção"
L.HEADER_GENERAL = "Geral"
L.SETTINGS = "Opções"

L.SCOPE_ALL = "Todos"
L.SCOPE_ALL_TIP = "O que você ajustar vale para todas as categorias. A que tinha um valor próprio nesse ajuste o perde."
L.SCOPE_ONE_TIP = "O que você ajustar vale só para esta categoria, que o mantém seja o que for das outras."
L.EFFECT = "Efeito"
L.EFFECT_TIP = "O desenho da luz."
L.LOOK_OF_ALL = "Aparência de todos"
L.LOOK_OF = "Aparência: %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "Como todos os objetos"
L.SHARED_TIP = "Tira desta categoria o efeito e a aparência próprios: ela volta aos de todos os objetos."

L.SIZE = "Tamanho"
L.SIZE_TIP = "Tamanho do efeito."
L.INTENSITY = "Intensidade"
L.INTENSITY_TIP = "Brilho do efeito."
L.OFFSET = "Ajuste vertical"
L.OFFSET_TIP = "Sobe ou desce o efeito em relação à placa do objeto. A prévia mostra onde ele fica."
L.FADE = "Esmaece com a placa"
L.FADE_TIP = "O efeito some junto com a placa do objeto, por exemplo quando o cenário o esconde."

L.SILHOUETTE = "Passa atrás do personagem"
L.SILHOUETTE_TIP = "O efeito é recortado em volta do seu personagem e parece passar atrás dele em vez de cobri-lo."
L.ZONE_SIZE = "Tamanho do recorte"
L.ZONE_SIZE_TIP = "Aumente se o efeito invadir seu personagem, diminua se ficar longe demais. Cada personagem guarda o seu."
L.ZONE_HEIGHT = "Altura do recorte"
L.ZONE_HEIGHT_TIP = "Sobe ou desce o recorte. Cada personagem guarda a sua."
L.ZONE_SHOW = "Mostrar o recorte"
L.ZONE_SHOW_TIP = "Contorna o recorte em vermelho: ele deve acompanhar seu personagem. Some ao fechar esta janela."

L.SHOW_NAME = "Mostrar o nome"
L.SHOW_NAME_TIP = "Escreve o nome do objeto acima dele, no lugar do que o jogo escreve."
L.SHOW_ICON = "Mostrar o ícone"
L.SHOW_ICON_TIP = "Mostra o ícone de interação acima do objeto, no lugar do que o jogo desenha."
L.TEXT_SIZE = "Tamanho do nome"
L.TEXT_SIZE_TIP = "Tamanho do nome escrito acima do objeto, comparado ao texto do jogo."
L.FONT = "Fonte"
L.FONT_TIP = "Fonte do nome escrito acima do objeto."
L.FONT_GAME = "Fonte do jogo"
L.COLOR = "Cor"
L.COLOR_TIP = "A cor do efeito nesses objetos."
L.COLOR_SECOND = "Segunda cor"
L.COLOR_SECOND_TIP = "A cor dos traços finos e das faíscas do efeito nesses objetos. Igual à primeira até você escolher uma."
L.TIP_COLOR_SAME = "Botão direito: igual à primeira"
L.TIP_COLOR_SWAP = "Shift-clique: trocar as duas cores"
L.TIP_COLOR_SET = "Clique: escolher uma cor"
L.TIP_COLOR_RESET = "Botão direito: voltar à cor original"
L.IGNORED = "Ignorados: %d"
L.IGNORED_TIP = "Objetos que nunca recebem efeito, seja qual for a categoria. /lueur ignore list mostra os nomes, /lueur ignore clear esquece todos."
L.IGNORE_TARGET = "Ignorar alvo"
L.IGNORE_TARGET_TIP = "Ignora o objeto à sua frente agora e todos os de mesmo nome. Num objeto já ignorado, clique duas vezes para deixar de ignorá-lo."

L.HIDE_COMBAT = "Em combate"
L.HIDE_COMBAT_TIP = "Sem efeito enquanto você está em combate."
L.HIDE_INSTANCE = "Em instância"
L.HIDE_INSTANCE_TIP = "Sem efeito em masmorras, raides e campos de batalha."
L.HIDE_LOCKED = "Em objeto indisponível"
L.HIDE_LOCKED_TIP = "O efeito se apaga num objeto que o jogo recusa por enquanto: perícia baixa demais, objeto trancado… O jogo só avisa quando o objeto está ao alcance."
L.HIDE_UNTRAINED = "Ervas e veios sem a profissão"
L.HIDE_UNTRAINED_TIP = "Sem efeito em ervas se este personagem não tem Herborismo, nem em veios sem Mineração."

L.RANGE = "Alcance"
L.RANGE_TIP = "Até que distância o jogo pode escolher um objeto para destacar."
L.DIRECTION = "Direção"
L.DIRECTION_TIP = "Onde o jogo procura o objeto a escolher."
L.ARC_0 = "Reto"
L.ARC_0_TIP = "Só o que está bem na sua frente."
L.ARC_1 = "Frente"
L.ARC_1_TIP = "Tudo o que está à sua frente."
L.ARC_2 = "Todas"
L.ARC_2_TIP = "Em todas as direções, até atrás de você."
L.EXCLUSIVE = "Mostrar só os alvos iluminados"
L.EXCLUSIVE_TIP = "O jogo deixa de indicar os alvos de interação que não recebem efeito: PNJs, caixas de correio… Desmarcado, mostra nome e ícone em todos eles."
L.GLOW_ONLY = "Só o brilho"
L.GLOW_ONLY_TIP = "Lueur não escreve mais o nome nem o ícone do objeto e deixa o que o jogo ou outro addon mostra ali. Sempre ativo quando a placa Soft Target do Plumber está ligada."

L.KEY = "Tecla de Interação"
L.KEY_TIP = "A tecla que pega, coleta ou usa o objeto destacado quando ele está ao alcance. É a tecla de interação do jogo: serve também para PNJs e pode ser mudada nas teclas de atalho do jogo."
L.KEY_NONE = "Sem tecla"
L.KEY_LISTEN = "Aperte uma tecla"
L.KEY_LISTEN_TIP = "Aperte a tecla, o botão do mouse ou gire a roda para o lado a usar. Esc cancela."
L.KEY_TAKEN = "%s já serve para “%s”. Aperte de novo para dá-la à interação, ou escolha outra tecla."
L.TIP_KEY_SET = "Clique: escolher uma tecla"
L.TIP_KEY_CLEAR = "Botão direito: tirar a tecla"

L.LANGUAGE = "Idioma"
L.LANGUAGE_TIP = "O idioma dos textos e comandos de Lueur."
L.LANGUAGE_AUTO = "Automático"
L.LANGUAGE_AUTO_TIP = "Segue o idioma do jogo."

L.ENABLE = "Ativar Lueur"
L.ENABLE_TIP = "Desativado, Lueur devolve ao jogo suas opções de mira originais."
L.MINIMAP = "Botão do minimapa"
L.MINIMAP_TIP = "Mostra o botão de Lueur na borda do minimapa."
L.DEBUG = "Diagnóstico no bate-papo"
L.DEBUG_TIP = "Descreve no bate-papo cada objeto mirado e o que Lueur conclui dele."

-- alternance des deux pistages
L.HEADER_SWITCH = "Profissões de coleta"
L.NODE_SWITCH = "Alternar os rastreamentos"
L.NODE_SWITCH_TIP = "O jogo mostra os pontos de Encontrar Ervas ou os de Encontrar Minérios, nunca os dois. Lueur liga o outro cada vez que você se deslocou o bastante. Cada personagem tem sua opção."
L.NODE_SWITCH_YARDS = "Distância entre trocas"
L.NODE_SWITCH_YARDS_TIP = "Distância que você percorre antes de Lueur ligar o outro rastreamento."

L.PREVIEW_NO_MODEL = "Modelo 3D indisponível neste cliente"
L.PREVIEW_HINT = "Arrastar: girar  ·  botão direito: mover  ·  roda: zoom"
L.HEADER_PROFILE = "Perfil"
L.HEADER_PROFILE_TIP = "Um conjunto de opções de efeito, detecção e ocultação, com um nome. Cada personagem usa o perfil escolhido aqui."
L.PROFILE_DEFAULT = "Padrão"
L.PROFILE_NEW = "Novo"
L.PROFILE_NEW_TIP = "Cria um perfil com as opções originais e o dá a este personagem."
L.PROFILE_COPY = "Copiar"
L.PROFILE_COPY_TIP = "Cria um perfil com as opções deste e o dá a este personagem."
L.PROFILE_RENAME = "Renomear"
L.PROFILE_RENAME_TIP = "Dá outro nome a este perfil."
L.PROFILE_DELETE = "Excluir"
L.PROFILE_DELETE_TIP = "Exclui este perfil. Os personagens que o usavam voltam ao primeiro. Um segundo clique confirma."
L.PROFILE_OK = "OK"
L.PROFILE_CANCEL = "Cancelar"
L.DEFAULTS = "Padrões"
L.DEFAULTS_TIP = "Devolve as opções de efeito e detecção aos valores originais. Um segundo clique confirma."
L.FOOTER = "Lueur %s  ·  /lueur help: todos os comandos"

L.OPTIONS_NOTE = "Faz veios, ervas, objetos de missão e baús brilharem quando você se aproxima."
L.OPTIONS_OPEN = "Abrir as opções de Lueur"

L.TIP_ENABLED = "Ativado"
L.TIP_DISABLED = "Desativado"
L.TIP_LEFT_CLICK = "Clique: abrir as opções"
L.TIP_RIGHT_CLICK = "Botão direito: ativar ou desativar"
L.TIP_DRAG = "Arrastar: mover este botão"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "ativado."
L.MSG_DISABLED = "desativado, suas opções originais voltaram."
L.MSG_RESTART = "reinicie o jogo por completo para terminar de atualizar Lueur."
L.MSG_EXCLUSIVE_ON = "o jogo deixa de indicar os alvos que não recebem efeito."
L.MSG_EXCLUSIVE_OFF = "o jogo mostra nome e ícone de todo alvo de interação (PNJs, objetos do mundo…)."
L.MSG_SILHOUETTE_ON = "o efeito passa atrás do seu personagem."
L.MSG_SILHOUETTE_OFF = "o efeito cobre seu personagem."
L.MSG_CUTOUT_UNAVAILABLE = "recorte indisponível: %s."
L.MSG_ZONE_SHOWN = "recorte contornado em vermelho: deve acompanhar seu personagem."
L.MSG_ZONE_HIDDEN = "contorno do recorte oculto."
L.MSG_SILHOUETTE_VALUES = "silhueta: tamanho %d%%, altura %d%%"
L.MSG_SILHOUETTE_USAGE = "uso: /lueur silhouette | show | <tamanho {bodyScale}> [altura {bodyShift}]"
L.MSG_EFFECTS = "efeitos disponíveis: %s (atual: %s)"
L.MSG_FONTS = "fontes disponíveis: %s (atual: %s)"
L.MSG_COLOR_TWO = "%s: cores %s e %s"
L.MSG_COLOR = "%s: cor %s"
L.MSG_NO_PICKER = "este cliente não tem seletor de cor: digite /lueur color <categoria> <rrggbb>."
L.MSG_SHARED = "%s: de volta ao efeito e à aparência de todos os objetos."
L.MSG_HIDE_COMBAT = "efeito oculto em combate: %s"
L.MSG_HIDE_INSTANCE = "efeito oculto em instância: %s"
L.MSG_HIDE_LOCKED = "efeito oculto em objetos indisponíveis: %s"
L.MSG_HIDE_UNTRAINED = "efeito oculto em ervas e veios sem a profissão: %s"
L.MSG_GLOW_ONLY = "só o brilho, a placa fica com o jogo ou outro addon: %s"
L.MSG_IGNORED = "%s não receberá mais efeito."
L.MSG_UNIGNORED = "%s não é mais ignorado."
L.MSG_IGNORED_ALREADY = "%s já é ignorado, como todo objeto com esse nome. Peça de novo para deixar de ignorá-lo."
L.MSG_IGNORE_NO_TARGET = "nenhum objeto à sua frente para ignorar."
L.MSG_IGNORE_LIST = "objetos ignorados: %s"
L.MSG_IGNORE_EMPTY = "nenhum objeto é ignorado."
L.MSG_RANGE = "alcance: %d m"
L.MSG_RANGE_COMBAT = "alcance: %d m, aplicado ao sair do combate."
L.MSG_RANGE_CLIENT = "alcance: %d m pedidos, o cliente manteve %s."
L.MSG_KEY_COMBAT = "as teclas de atalho não mudam em combate."
L.MSG_KEY_REFUSED = "o jogo recusou a tecla “%s”."
L.MSG_KEY_REPLACED = "%s não serve mais para “%s”."

L.FAIL_NO_MASK = "este cliente não aceita máscaras"
L.FAIL_MASK_TEXTURE = "textura da máscara não achada (reinicie o jogo por completo)"
L.FAIL_MASK_REFUSED = "máscara recusada pelo cliente"

L.STATUS_CLIENT = "cliente %s (%s), idioma %s; textos de Lueur: %s. Valores em vigor:"
L.STATUS_CVAR_UNKNOWN = "desconhecida deste cliente"
L.STATUS_CVAR_DEFAULT = " (padrão %s)"
L.STATUS_EXPECTED = "esperado por Lueur: alcance %d, arco %d"
L.STATUS_GATE = "só os alvos iluminados são indicados: %s | exibição nativa agora: %s"
L.STATUS_GLOW_ONLY = "só o brilho: %s | nome do alvo do Plumber: %s"
L.GATE_OPEN = "aberta"
L.GATE_CLOSED = "fechada"
L.STATUS_SILHOUETTE = "efeito atrás do personagem: %s"
L.STATUS_UNAVAILABLE = "indisponível, %s"
L.STATUS_DIRECT = "alvo lido direto de “softinteract”: %s"
L.STATUS_NOT_YET = "ainda não visto"
L.STATUS_RANGE_API = "alcance de interação legível: %s"
L.STATUS_LINE = "linha de pesca na água: %s | canalização em curso: %s"
L.STATUS_HIDE = "oculto em combate: %s | em instância: %s | em objetos indisponíveis: %s | em pausa agora: %s"
L.STATUS_SWITCH = "rastreamentos alternados: %s | disponível: %s"
L.MSG_PROFILES = "perfis: %s. Este personagem usa: %s."
L.MSG_PROFILE_UNNAMED = "o perfil precisa de um nome."
L.MSG_PROFILE_TAKEN = "outro perfil já se chama %s."
L.STATUS_PROFILE = "perfil: %s | perfis: %d"
L.STATUS_COST = "custo desde o último status: alvo %d chamadas, %.3f ms cada (a mais longa %.2f) | animação %d quadros, %.3f ms cada (o mais longo %.2f)"
L.STATUS_TRAINED = "sem efeito em ervas e veios sem a profissão: %s | herborismo: %s, mineração: %s"
L.STATUS_OBJECTS = "categorias mostradas neste personagem: %s | objetos ignorados: %d"
L.STATUS_OWN = "categorias com opções próprias: %s"
L.STATUS_EFFECT = "efeito: %s | texturas: %s"
L.STATUS_KEY = "tecla de interação: %s"
L.TEXTURES_PENDING = "ainda não carregadas"
L.TEXTURES_MISSING = "ausentes, efeito reserva mostrado (reinicie o jogo por completo)"
L.TEXTURES_LOADED = "carregadas"

L.OBJECTIVES_HEADER = "%d objetivo(s) de missão em andamento:"
L.OBJECTIVES_NOT_ITEM = "  (não é objeto: comparado só ao nome inteiro)"
L.OBJECTIVES_LEARNED = "aprendido de uma dica: %s (%s)"


---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "sem alvo de interação agora"
L.DEBUG_PAUSED = "em pausa (combate ou instância)"
L.DEBUG_LINE_OUT = "linha de pesca na água: %d m pedidos, o cliente manteve %s"
L.DEBUG_LINE_IN = "linha de pesca recolhida: %d m pedidos, o cliente manteve %s"
L.DEBUG_IGNORED = "%s ignorado (não é objeto do mundo)"
L.DEBUG_SKIPPED = "%s ignorado (na sua lista de ignorados)"
L.DEBUG_HIDDEN = "%s → %s, sem efeito (categoria oculta ou desconhecida)"
L.DEBUG_UNTRAINED = "%s → %s, sem efeito (o personagem não tem a profissão)"
L.DEBUG_NO_PLATE = "%s → %s, detectado mas sem placa: efeito impossível"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "cursor: %s"
L.DEBUG_VIA = "alvo: %s"
L.VIA_DIRECT = "direto"
L.VIA_SWEEP = "varredura"
L.DEBUG_RANGE = "ao alcance: %s"
L.DEBUG_OBJECT = "objeto nº %s"
L.DEBUG_FISHING = "pescando: %s"
L.DEBUG_QUEST = "de missão: %s"
L.DEBUG_MATCH = "ligado a um objetivo por: %s (%d objetivos em andamento)"
L.MATCH_NONE = "nada"
L.MATCH_CURSOR = "nada, o cursor diz o que ele é"
L.MATCH_TOOLTIP = "sua dica"
L.MATCH_NAME = "seu nome"
L.MATCH_WORD = "a palavra “%s”"
L.MATCH_LOOT = "seu saque, já pego antes"
L.DEBUG_CHEST = "tido como recipiente por: %s"
L.DEBUG_SECRET = "identidade secreta: %s"
L.DEBUG_BEHIND = "atrás da câmera: %s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "comandos:"
L.HELP = {
	"/lueur — abre ou fecha a janela de opções (como um clique no botão do minimapa)",
	"/lueur minimap — mostra ou oculta o botão do minimapa",
	"/lueur on | off — ativa ou desativa Lueur (off devolve suas opções)",
	"/lueur preview — abre a janela de opções na prévia, que mostra o efeito num objeto 3D",
	"/lueur effect [categoria] <nome> — dá este efeito a todas as categorias, ou a uma só (ore, herb, quest, chest, bobber, other); sem nome, lista os efeitos",
	"/lueur color <categoria> <rrggbb> [<rrggbb>] | swap | default — cor do efeito de uma categoria, e segunda cor para os traços finos e faíscas; swap troca as duas; sem cor, mostra as atuais",
	"/lueur shared <categoria> — devolve a uma categoria o efeito e a aparência de todos os objetos",
	"/lueur size [categoria] <{size}> — tamanho do efeito (padrão {size=})",
	"/lueur intensity [categoria] <{intensity}> — brilho do efeito, em % (padrão {intensity=})",
	"/lueur offset [categoria] <{offsetY}> — ajuste vertical do efeito (padrão {offsetY=})",
	"/lueur fade [categoria] — se o efeito esmaece com a placa (objeto escondido pelo cenário)",
	"/lueur name | icon [categoria] — se o nome do objeto, ou seu ícone, aparece acima dele; text [categoria] <{textSize}> define o tamanho do nome, em % (padrão {textSize=})",
	"/lueur font [categoria] <nome> | default — fonte do nome do objeto; sem nome, lista as fontes",
	"/lueur silhouette [categoria] — se o efeito passa atrás do seu personagem em vez de cobri-lo",
	"/lueur silhouette show | <tamanho %> [altura %] — mostra e ajusta o recorte",
	"/lueur range <{range}> — até onde o jogo escolhe objetos, em metros (padrão {range=})",
	"/lueur arc <{arc}> — 0 reto, 1 à frente, 2 todas as direções (padrão {arc=})",
	"/lueur exclusive — se o jogo só indica os alvos que recebem efeito",
	"/lueur glowonly — se Lueur só desenha a luz e deixa a placa do alvo (nome, ícone) com o jogo ou outro addon",
	"/lueur combat | instance | unavailable | profession — se o efeito some em combate, em instância, em objetos indisponíveis, em ervas e veios sem a profissão",
	"/lueur key <TECLA> | none — define a tecla que pega o objeto destacado (F, SHIFT-E, BUTTON4…); sem tecla, mostra a atual",
	"/lueur ore | herb | quest | chest | bobber | other — mostra ou oculta uma categoria, para este personagem",
	"/lueur profile [<nome>] — lista os perfis, ou dá a este personagem o que tem esse nome",
	"/lueur switch [<{nodeSwitchYards}>] — com as duas profissões de coleta: alterna Encontrar Ervas e Encontrar Minérios conforme você anda; um número define a distância entre trocas, em metros (padrão {nodeSwitchYards=})",
	"/lueur ignore — ignora o objeto à sua frente e os de mesmo nome (duas vezes num objeto ignorado: deixa de ignorá-lo); ignore list, ignore clear, ignore <nome>",
	"/lueur language <auto | de | en | es | fr | it | ko | pt | ru | zhCN | zhTW> — idioma dos textos e comandos de Lueur",
	"/lueur debug — descreve cada objeto mirado e o que Lueur conclui dele",
	"/lueur objectives — lista os objetivos de missão aos quais o nome dos objetos é comparado",
	"/lueur status — mostra os valores que o cliente realmente aplica",
	"/lueur help — mostra esta lista",
}
