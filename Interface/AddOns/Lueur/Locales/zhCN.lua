-- Lueur : textes en chinois simplifié (traduction automatique, non relue)
local _, ns = ...

local L = {}
ns.LOCALES.zhCN = L

L.LANGUAGE_NAME = "简体中文"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "是"
L.NO = "否"
L.SETTING = "%s：%s"
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d 码"
L.CONFIRM = "确认？"

-- pas de mots de commande propres : les noms anglais répondent
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "矿石"
L.CATEGORY_ORE_TIP = "矿脉和矿点。"
L.CATEGORY_HERB = "草药"
L.CATEGORY_HERB_TIP = "可以采集的植物。"
L.CATEGORY_QUEST = "任务"
L.CATEGORY_QUEST_TIP = "与你当前任务有关的物体。"
L.CATEGORY_CHEST = "宝箱"
L.CATEGORY_CHEST_TIP = "宝箱、板条箱等可以拾取的容器。"
L.CATEGORY_BOBBER = "鱼漂"
L.CATEGORY_BOBBER_TIP = "你钓鱼时的鱼漂。"
L.CATEGORY_OTHER = "其他物体"
L.CATEGORY_OTHER_TIP = "日常物体：门、邮箱、拉杆…"

L.NAME_ORE = "矿石"
L.NAME_HERB = "草药"
L.NAME_QUEST = "任务"
L.NAME_CHEST = "宝箱"
L.NAME_BOBBER = "鱼漂"
L.NAME_OTHER = "其他"
L.NAME_NONE = "无"
L.NAME_UNNAMED = "所有无名物体"

L.SAMPLE_ORE = "铜矿"
L.SAMPLE_HERB = "宁神花"
L.SAMPLE_QUEST = "补给箱"
L.SAMPLE_CHEST = "破损的箱子"
L.SAMPLE_BOBBER = "鱼漂"
L.SAMPLE_OTHER = "邮箱"

L.STATE_FAR = "距离过远"
L.STATE_READY = "可互动"
L.STATE_LOCKED = "不可用"

L.EFFECT_AURA = "光环"
L.EFFECT_AURA_TIP = "一团光晕和缭绕的光雾，带有光环、彗星和萤火。"
L.EFFECT_SUBTLE = "柔和"
L.EFFECT_SUBTLE_TIP = "柔和的微光，没有光环和彗星。"
L.EFFECT_SIGIL = "符印"
L.EFFECT_SIGIL_TIP = "一圈符文围绕物体缓缓转动。"
L.EFFECT_BRACKETS = "准星"
L.EFFECT_BRACKETS_TIP = "四个角框住物体，进入互动距离后锁定它。"
L.EFFECT_VORTEX = "漩涡"
L.EFFECT_VORTEX_TIP = "光臂盘绕着物体，如同正在开启的传送门。"
L.EFFECT_FLAME = "火焰"
L.EFFECT_FLAME_TIP = "火舌从物体上升起，颜色与其一致。"
L.EFFECT_RIFT = "裂隙"
L.EFFECT_RIFT_TIP = "光环围绕的黑洞将火花螺旋吸入。"
L.EFFECT_STORM = "雷暴"
L.EFFECT_STORM_TIP = "雷云在物体上方聚集，闪电从中落下。"
L.EFFECT_GEYSER = "喷泉"
L.EFFECT_GEYSER_TIP = "光之喷泉从物体中涌出，再洒落在四周。"
L.EFFECT_SPIRIT = "精魂"
L.EFFECT_SPIRIT_TIP = "两团光灵绕着物体飞舞，拖出一条光带。"
L.EFFECT_BEAM = "光柱"
L.EFFECT_BEAM_TIP = "一道光柱从物体上升起，火花沿着它向上飘动。"
L.EFFECT_BEACON = "信标"
L.EFFECT_BEACON_TIP = "一颗水晶悬浮在物体上方，以一缕光线与其相连。"
L.EFFECT_ORBIT = "环绕"
L.EFFECT_ORBIT_TIP = "三团光灵各沿自己的轨道环绕物体。"
L.EFFECT_RIPPLE = "涟漪"
L.EFFECT_RIPPLE_TIP = "涟漪在物体周围的地面上扩散。"
L.EFFECT_SPARKLE = "闪光"
L.EFFECT_SPARKLE_TIP = "点点闪光在物体周围闪烁，没有任何光圈。"

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "轮廓"
L.HEADER_OBJECTS = "高亮的物体"
L.HEADER_HIDE = "隐藏特效"
L.HEADER_DETECTION = "检测"
L.HEADER_GENERAL = "综合"
L.SETTINGS = "设置"

L.SCOPE_ALL = "全部"
L.SCOPE_ALL_TIP = "你的设置将应用于所有类别。某个类别对该设置的单独取值会被清除。"
L.SCOPE_ONE_TIP = "你的设置只应用于此类别，其他类别如何变化都不会影响它。"
L.EFFECT = "特效"
L.EFFECT_TIP = "光效的形状。"
L.LOOK_OF_ALL = "所有物体的外观"
L.LOOK_OF = "外观：%s"
L.OF_CATEGORY = "%s（%s）"
L.SHARED = "与所有物体相同"
L.SHARED_TIP = "清除此类别单独的特效和外观：恢复为所有物体的设置。"

L.SIZE = "大小"
L.SIZE_TIP = "特效的大小。"
L.INTENSITY = "亮度"
L.INTENSITY_TIP = "特效的明亮程度。"
L.OFFSET = "垂直偏移"
L.OFFSET_TIP = "相对于物体的姓名板上下移动特效。预览会显示它的位置。"
L.FADE = "随姓名板淡出"
L.FADE_TIP = "特效随物体的姓名板一起淡出，例如被场景遮挡时。"

L.SILHOUETTE = "从我的角色身后穿过"
L.SILHOUETTE_TIP = "特效沿你的角色轮廓被裁切，看起来像从你身后穿过，而不是盖住你。"
L.ZONE_SIZE = "裁切大小"
L.ZONE_SIZE_TIP = "特效盖到角色时调大，离角色太远时调小。每个角色单独保存。"
L.ZONE_HEIGHT = "裁切高度"
L.ZONE_HEIGHT_TIP = "上下移动裁切区域。每个角色单独保存。"
L.ZONE_SHOW = "显示裁切区域"
L.ZONE_SHOW_TIP = "用红线勾出裁切区域：它应当贴合你的角色。关闭此窗口后消失。"

L.SHOW_NAME = "显示名称"
L.SHOW_NAME_TIP = "在物体上方显示它的名称，取代游戏自带的名称。"
L.SHOW_ICON = "显示图标"
L.SHOW_ICON_TIP = "在物体上方显示它的互动图标，取代游戏自带的图标。"
L.TEXT_SIZE = "文字大小"
L.TEXT_SIZE_TIP = "物体上方名称的大小，相对于游戏自带的文字。"
L.FONT = "字体"
L.FONT_TIP = "物体上方名称的字体。"
L.FONT_GAME = "游戏字体"
L.COLOR = "颜色"
L.COLOR_TIP = "这些物体上特效的颜色。"
L.COLOR_SECOND = "第二颜色"
L.COLOR_SECOND_TIP = "这些物体上特效的细线和火花的颜色。未选择时与第一颜色相同。"
L.TIP_COLOR_SAME = "右键点击：与第一颜色相同"
L.TIP_COLOR_SWAP = "Shift+点击：交换两种颜色"
L.TIP_COLOR_SET = "左键点击：选择颜色"
L.TIP_COLOR_RESET = "右键点击：恢复原始颜色"
L.IGNORED = "已忽略的物体：%d"
L.IGNORED_TIP = "无论属于哪个类别都不会显示特效的物体。/lueur ignore list 列出它们，/lueur ignore clear 全部清除。"
L.IGNORE_TARGET = "忽略目标"
L.IGNORE_TARGET_TIP = "忽略你当前面对的物体，以及所有同名物体。对已忽略的物体点击两次可取消忽略。"

L.HIDE_COMBAT = "战斗中"
L.HIDE_COMBAT_TIP = "战斗中不显示特效。"
L.HIDE_INSTANCE = "副本中"
L.HIDE_INSTANCE_TIP = "在地下城、团队副本和战场中不显示特效。"
L.HIDE_LOCKED = "无法使用的物体"
L.HIDE_LOCKED_TIP = "游戏暂时不允许使用的物体不显示特效：技能太低、物体已上锁…游戏只有在你进入互动距离后才会给出提示。"
L.HIDE_UNTRAINED = "未学专业的草药和矿石"
L.HIDE_UNTRAINED_TIP = "此角色未学草药学时草药不显示特效，未学采矿时矿石不显示特效。"

L.RANGE = "距离"
L.RANGE_TIP = "游戏可以在多远的距离内选取要高亮的物体。"
L.DIRECTION = "方向"
L.DIRECTION_TIP = "游戏在哪个方向寻找要选取的物体。"
L.ARC_0 = "正前方"
L.ARC_0_TIP = "只选取正对着你的物体。"
L.ARC_1 = "前方"
L.ARC_1_TIP = "你前方的所有物体。"
L.ARC_2 = "所有方向"
L.ARC_2_TIP = "任何方向，包括你的背后。"
L.EXCLUSIVE = "只显示高亮的目标"
L.EXCLUSIVE_TIP = "游戏不再标出没有特效的互动目标：NPC、邮箱…取消勾选后，游戏会在每个互动目标上显示名称和图标。"
L.GLOW_ONLY = "仅光效"
L.GLOW_ONLY_TIP = "Lueur 不再显示物体的名称和图标，保留游戏或其他插件在那里显示的内容。启用 Plumber 的 Soft Target 姓名板时始终生效。"

L.KEY = "互动键"
L.KEY_TIP = "高亮的物体进入互动距离后，用来拾取、采集或使用它的按键。这就是游戏自带的互动键：对 NPC 同样有效，也可以在游戏的按键设置中修改。"
L.KEY_NONE = "未绑定"
L.KEY_LISTEN = "请按键"
L.KEY_LISTEN_TIP = "按下要使用的按键、鼠标按键或滚动鼠标滚轮。按 Esc 取消。"
L.KEY_TAKEN = "%s 已用于“%s”。再按一次将它改为互动键，或按其他按键。"
L.TIP_KEY_SET = "左键点击：选择按键"
L.TIP_KEY_CLEAR = "右键点击：清除按键"

L.LANGUAGE = "语言"
L.LANGUAGE_TIP = "Lueur 的文本和命令使用的语言。"
L.LANGUAGE_AUTO = "自动"
L.LANGUAGE_AUTO_TIP = "跟随游戏的语言。"

L.ENABLE = "启用 Lueur"
L.ENABLE_TIP = "禁用后，Lueur 会把你原来的目标选取设置还给游戏。"
L.MINIMAP = "小地图按钮"
L.MINIMAP_TIP = "在小地图边缘显示 Lueur 的按钮。"
L.DEBUG = "在聊天窗口显示诊断"
L.DEBUG_TIP = "在聊天窗口中说明每个被选取的物体，以及 Lueur 对它的判断。"

L.HEADER_SWITCH = "两个采集专业"
L.NODE_SWITCH = "交替切换两种追踪"
L.NODE_SWITCH_TIP = "游戏只显示寻找草药或寻找矿物的标记，不能同时显示。每当你移动了足够的距离，Lueur 就会切换到另一种追踪。每个角色单独设置。"
L.NODE_SWITCH_YARDS = "切换间隔距离"
L.NODE_SWITCH_YARDS_TIP = "你移动多远后 Lueur 切换到另一种追踪。"

L.PREVIEW_NO_MODEL = "此客户端无法显示 3D 模型"
L.PREVIEW_HINT = "拖动：旋转  ·  右键拖动：移动  ·  滚轮：缩放"
L.HEADER_PROFILE = "配置文件"
L.HEADER_PROFILE_TIP = "一组带名称的特效、检测和隐藏设置。每个角色使用在此选择的配置文件。"
L.PROFILE_DEFAULT = "默认"
L.PROFILE_NEW = "新建"
L.PROFILE_NEW_TIP = "以原始设置创建一个配置文件，并交给此角色使用。"
L.PROFILE_COPY = "复制"
L.PROFILE_COPY_TIP = "以当前配置文件的设置创建一个新的，并交给此角色使用。"
L.PROFILE_RENAME = "重命名"
L.PROFILE_RENAME_TIP = "为此配置文件另取一个名称。"
L.PROFILE_DELETE = "删除"
L.PROFILE_DELETE_TIP = "删除此配置文件。使用它的角色将改用第一个配置文件。再次点击以确认。"
L.PROFILE_OK = "确定"
L.PROFILE_CANCEL = "取消"
L.DEFAULTS = "默认设置"
L.DEFAULTS_TIP = "将特效和检测设置恢复为原始值。再次点击以确认。"
L.FOOTER = "Lueur %s  ·  /lueur help：全部命令"

L.OPTIONS_NOTE = "当你靠近矿脉、草药、任务物体和宝箱时，让它们发光。"
L.OPTIONS_OPEN = "打开 Lueur 的设置"

L.TIP_ENABLED = "已启用"
L.TIP_DISABLED = "已禁用"
L.TIP_LEFT_CLICK = "左键点击：打开设置"
L.TIP_RIGHT_CLICK = "右键点击：启用或禁用"
L.TIP_DRAG = "拖动：移动此按钮"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "已启用。"
L.MSG_DISABLED = "已禁用，你原来的设置已恢复。"
L.MSG_RESTART = "请完全重启游戏以完成 Lueur 的更新。"
L.MSG_EXCLUSIVE_ON = "游戏不再标出没有特效的目标。"
L.MSG_EXCLUSIVE_OFF = "游戏会显示每个互动目标（NPC、场景物体…）的名称和图标。"
L.MSG_SILHOUETTE_ON = "特效从你的角色身后穿过。"
L.MSG_SILHOUETTE_OFF = "特效盖住你的角色。"
L.MSG_CUTOUT_UNAVAILABLE = "裁切不可用：%s。"
L.MSG_ZONE_SHOWN = "裁切区域已用红线勾出：它应当贴合你的角色。"
L.MSG_ZONE_HIDDEN = "裁切区域的轮廓已隐藏。"
L.MSG_SILHOUETTE_VALUES = "轮廓：大小 %d%%，高度 %d%%"
L.MSG_SILHOUETTE_USAGE = "用法：/lueur silhouette | show | <大小 {bodyScale}> [高度 {bodyShift}]"
L.MSG_EFFECTS = "可用特效：%s（当前：%s）"
L.MSG_FONTS = "可用字体：%s（当前：%s）"
L.MSG_COLOR_TWO = "%s：颜色 %s 和 %s"
L.MSG_COLOR = "%s：颜色 %s"
L.MSG_NO_PICKER = "此客户端没有颜色选择器：请输入 /lueur color <类别> <rrggbb>。"
L.MSG_SHARED = "%s：恢复为所有物体的特效和外观。"
L.MSG_HIDE_COMBAT = "战斗中隐藏特效：%s"
L.MSG_HIDE_INSTANCE = "副本中隐藏特效：%s"
L.MSG_HIDE_LOCKED = "在无法使用的物体上隐藏特效：%s"
L.MSG_HIDE_UNTRAINED = "在未学专业的草药和矿石上隐藏特效：%s"
L.MSG_GLOW_ONLY = "仅光效，姓名板交给游戏或其他插件：%s"
L.MSG_IGNORED = "%s 不再显示特效。"
L.MSG_UNIGNORED = "%s 不再被忽略。"
L.MSG_IGNORED_ALREADY = "%s 已被忽略，所有同名物体也是如此。再执行一次可取消忽略。"
L.MSG_IGNORE_NO_TARGET = "你面前没有可忽略的物体。"
L.MSG_IGNORE_LIST = "已忽略的物体：%s"
L.MSG_IGNORE_EMPTY = "没有被忽略的物体。"
L.MSG_RANGE = "距离：%d 码"
L.MSG_RANGE_COMBAT = "距离：%d 码，脱离战斗后生效。"
L.MSG_RANGE_CLIENT = "距离：请求 %d 码，客户端保留了 %s。"
L.MSG_KEY_COMBAT = "战斗中无法更改按键绑定。"
L.MSG_KEY_REFUSED = "游戏拒绝了按键“%s”。"
L.MSG_KEY_REPLACED = "%s 不再触发“%s”。"

L.FAIL_NO_MASK = "此客户端不支持遮罩"
L.FAIL_MASK_TEXTURE = "找不到遮罩材质（请完全重启游戏）"
L.FAIL_MASK_REFUSED = "客户端拒绝了遮罩"

L.STATUS_CLIENT = "客户端 %s（%s），语言 %s；Lueur 的文本：%s。当前生效的值："
L.STATUS_CVAR_UNKNOWN = "此客户端没有该项"
L.STATUS_CVAR_DEFAULT = " （默认 %s）"
L.STATUS_EXPECTED = "Lueur 期望的值：距离 %d，范围 %d"
L.STATUS_GATE = "只标出高亮的目标：%s | 游戏原生显示当前：%s"
L.STATUS_GLOW_ONLY = "仅光效：%s | Plumber 的软目标名称：%s"
L.GATE_OPEN = "开启"
L.GATE_CLOSED = "关闭"
L.STATUS_SILHOUETTE = "特效在角色身后：%s"
L.STATUS_UNAVAILABLE = "不可用，%s"
L.STATUS_DIRECT = "直接从“softinteract”读取目标：%s"
L.STATUS_NOT_YET = "尚未观察到"
L.STATUS_RANGE_API = "可读取互动距离：%s"
L.STATUS_LINE = "鱼线已抛出：%s | 正在引导：%s"
L.STATUS_HIDE = "战斗中隐藏：%s | 副本中：%s | 不可用的物体上：%s | 当前暂停：%s"
L.STATUS_SWITCH = "交替切换追踪：%s | 可用：%s"
L.MSG_PROFILES = "配置文件：%s。此角色使用：%s。"
L.MSG_PROFILE_UNNAMED = "配置文件需要一个名称。"
L.MSG_PROFILE_TAKEN = "已有另一个配置文件名为 %s。"
L.STATUS_PROFILE = "配置文件：%s | 配置文件数：%d"
L.STATUS_COST = "自上次 status 以来的 CPU：目标 %d 次调用，每次 %.3f 毫秒（最长 %.2f）| 动画 %d 帧，每帧 %.3f 毫秒（最长 %.2f）"
L.STATUS_TRAINED = "未学专业的草药和矿石不显示特效：%s | 草药学：%s，采矿：%s"
L.STATUS_OBJECTS = "此角色显示的类别：%s | 已忽略的物体：%d"
L.STATUS_OWN = "有单独设置的类别：%s"
L.STATUS_EFFECT = "特效：%s | 材质：%s"
L.STATUS_KEY = "互动键：%s"
L.TEXTURES_PENDING = "尚未加载"
L.TEXTURES_MISSING = "缺失，显示备用特效（请完全重启游戏）"
L.TEXTURES_LOADED = "已加载"

L.OBJECTIVES_HEADER = "%d 个进行中的任务目标："
L.OBJECTIVES_NOT_ITEM = "  （不是物体：只与完整名称比较）"
L.OBJECTIVES_LEARNED = "从鼠标提示中学到：%s（%s）"


---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "不再有互动目标"
L.DEBUG_PAUSED = "已暂停（战斗或副本）"
L.DEBUG_LINE_OUT = "鱼线已抛出：请求 %d 码，客户端保留了 %s"
L.DEBUG_LINE_IN = "鱼线已收回：请求 %d 码，客户端保留了 %s"
L.DEBUG_IGNORED = "%s 已忽略（不是场景物体）"
L.DEBUG_SKIPPED = "%s 已忽略（在你的忽略列表中）"
L.DEBUG_HIDDEN = "%s → %s，无特效（类别已隐藏或未知）"
L.DEBUG_UNTRAINED = "%s → %s，无特效（此角色未学该专业）"
L.DEBUG_NO_PLATE = "%s → %s，已检测到但没有姓名板：无法显示特效"
L.DEBUG_SHOWN = "%s → %s，%s"
L.DEBUG_CURSOR = "鼠标指针：%s"
L.DEBUG_VIA = "目标：%s"
L.VIA_DIRECT = "直接"
L.VIA_SWEEP = "扫描"
L.DEBUG_RANGE = "在互动距离内：%s"
L.DEBUG_OBJECT = "物体 ID：%s"
L.DEBUG_FISHING = "钓鱼：%s"
L.DEBUG_QUEST = "与任务相关：%s"
L.DEBUG_MATCH = "关联到任务目标的依据：%s（进行中的目标 %d 个）"
L.MATCH_NONE = "无"
L.MATCH_CURSOR = "无，鼠标指针已说明它是什么"
L.MATCH_TOOLTIP = "它的鼠标提示"
L.MATCH_NAME = "它的名称"
L.MATCH_WORD = "词语“%s”"
L.MATCH_LOOT = "它的战利品，之前拾取过"
L.DEBUG_CHEST = "识别为容器的依据：%s"
L.DEBUG_SECRET = "身份保密：%s"
L.DEBUG_BEHIND = "在镜头后方：%s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "命令："
L.HELP = {
	"/lueur — 打开或关闭设置窗口（等同于点击小地图按钮）",
	"/lueur minimap — 显示或隐藏小地图按钮",
	"/lueur on | off — 启用或禁用 Lueur（off 会恢复你的设置）",
	"/lueur preview — 打开设置窗口的预览，在 3D 物体上展示特效",
	"/lueur effect [类别] <名称> — 将此特效用于所有类别，或其中一个（ore, herb, quest, chest, bobber, other）；不带名称时列出全部特效",
	"/lueur color <类别> <rrggbb> [<rrggbb>] | swap | default — 某类别特效的颜色，以及细线和火花用的第二颜色；swap 交换两者；不带颜色时显示当前颜色",
	"/lueur shared <类别> — 让某类别恢复为所有物体的特效和外观",
	"/lueur size [类别] <{size}> — 特效的大小（默认 {size=}）",
	"/lueur intensity [类别] <{intensity}> — 特效的亮度，单位 %（默认 {intensity=}）",
	"/lueur offset [类别] <{offsetY}> — 特效的垂直偏移（默认 {offsetY=}）",
	"/lueur fade [类别] — 特效是否随姓名板淡出（物体被场景遮挡时）",
	"/lueur name | icon [类别] — 是否在物体上方显示名称或图标；text [类别] <{textSize}> 设置名称的大小，单位 %（默认 {textSize=}）",
	"/lueur font [类别] <名称> | default — 物体名称的字体；不带名称时列出全部字体",
	"/lueur silhouette [类别] — 特效是否从你的角色身后穿过，而不是盖住角色",
	"/lueur silhouette show | <大小 %> [高度 %] — 显示并调整裁切区域",
	"/lueur range <{range}> — 游戏选取物体的距离，单位为码（默认 {range=}）",
	"/lueur arc <{arc}> — 0 正前方，1 前方，2 所有方向（默认 {arc=}）",
	"/lueur exclusive — 游戏是否只标出有特效的目标",
	"/lueur glowonly — Lueur 是否只绘制光效，把目标的姓名板（名称、图标）交给游戏或其他插件",
	"/lueur combat | instance | unavailable | profession — 是否在战斗中、副本中、无法使用的物体上、未学专业的草药和矿石上隐藏特效",
	"/lueur key <按键> | none — 绑定用来拾取高亮物体的按键（F, SHIFT-E, BUTTON4…）；不带按键时显示当前按键",
	"/lueur ore | herb | quest | chest | bobber | other — 为此角色显示或隐藏某个类别",
	"/lueur profile [<名称>] — 列出配置文件，或让此角色使用该名称的配置文件",
	"/lueur switch [<{nodeSwitchYards}>] — 同时拥有两个采集专业时：随着你的移动交替切换寻找草药和寻找矿物；数字用来设置切换间隔，单位为码（默认 {nodeSwitchYards=}）",
	"/lueur ignore — 忽略你面对的物体及同名物体（对已忽略的物体执行两次：取消忽略）；ignore list, ignore clear, ignore <名称>",
	"/lueur language <auto | de | en | es | fr | it | ko | pt | ru | zhCN | zhTW> — Lueur 的文本和命令使用的语言",
	"/lueur debug — 说明每个被选取的物体，以及 Lueur 对它的判断",
	"/lueur objectives — 列出用来与物体名称比较的任务目标",
	"/lueur status — 显示客户端实际采用的值",
	"/lueur help — 显示此列表",
}
