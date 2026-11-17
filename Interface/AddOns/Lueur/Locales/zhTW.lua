-- Lueur : textes en chinois traditionnel (traduction automatique, non relue)
local _, ns = ...

local L = {}
ns.LOCALES.zhTW = L

L.LANGUAGE_NAME = "繁體中文"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "是"
L.NO = "否"
L.SETTING = "%s：%s"
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d 碼"
L.CONFIRM = "確定？"

-- pas de mots de commande propres : les noms anglais répondent
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "礦石"
L.CATEGORY_ORE_TIP = "礦脈與礦床。"
L.CATEGORY_HERB = "草藥"
L.CATEGORY_HERB_TIP = "可以採集的植物。"
L.CATEGORY_QUEST = "任務"
L.CATEGORY_QUEST_TIP = "與你目前任務有關的物件。"
L.CATEGORY_CHEST = "寶箱"
L.CATEGORY_CHEST_TIP = "寶箱、木箱等可以拾取的容器。"
L.CATEGORY_BOBBER = "釣魚浮標"
L.CATEGORY_BOBBER_TIP = "你釣魚線上的浮標。"
L.CATEGORY_OTHER = "其他物件"
L.CATEGORY_OTHER_TIP = "日常物件：門、信箱、拉桿…"

-- la catégorie d'un objet, dans une phrase du diagnostic
L.NAME_ORE = "礦石"
L.NAME_HERB = "草藥"
L.NAME_QUEST = "任務"
L.NAME_CHEST = "寶箱"
L.NAME_BOBBER = "浮標"
L.NAME_OTHER = "其他"
L.NAME_NONE = "無"
L.NAME_UNNAMED = "所有無名稱的物件"

-- l'objet que l'aperçu montre pour chaque catégorie
L.SAMPLE_ORE = "銅礦脈"
L.SAMPLE_HERB = "寧神花"
L.SAMPLE_QUEST = "補給箱"
L.SAMPLE_CHEST = "破損的箱子"
L.SAMPLE_BOBBER = "釣魚浮標"
L.SAMPLE_OTHER = "信箱"

L.STATE_FAR = "距離太遠"
L.STATE_READY = "在範圍內"
L.STATE_LOCKED = "無法使用"

L.EFFECT_AURA = "靈光"
L.EFFECT_AURA_TIP = "一圈光暈與流光，帶有光環、彗星和螢火。"
L.EFFECT_SUBTLE = "柔和"
L.EFFECT_SUBTLE_TIP = "柔和的微光，沒有光環和彗星。"
L.EFFECT_SIGIL = "符印"
L.EFFECT_SIGIL_TIP = "一圈符文繞著物件緩緩轉動。"
L.EFFECT_BRACKETS = "鎖定框"
L.EFFECT_BRACKETS_TIP = "四個邊角框住物件，進入範圍後便鎖定它。"
L.EFFECT_VORTEX = "漩渦"
L.EFFECT_VORTEX_TIP = "光之旋臂纏繞物件，有如開啟中的傳送門。"
L.EFFECT_FLAME = "火焰"
L.EFFECT_FLAME_TIP = "與物件同色的火舌從物件上升起。"
L.EFFECT_RIFT = "裂隙"
L.EFFECT_RIFT_TIP = "鑲著光邊的黑洞，將火花捲入螺旋。"
L.EFFECT_STORM = "雷暴"
L.EFFECT_STORM_TIP = "雷雲在物件上方聚集，閃電從中落下。"
L.EFFECT_GEYSER = "噴泉"
L.EFFECT_GEYSER_TIP = "光之噴泉從物件湧出，再灑落在四周。"
L.EFFECT_SPIRIT = "精魂"
L.EFFECT_SPIRIT_TIP = "兩團光靈繞著物件飛舞，拖著一道光帶。"
L.EFFECT_BEAM = "光柱"
L.EFFECT_BEAM_TIP = "一道光柱從物件升起，火花沿著它向上飄。"
L.EFFECT_BEACON = "信標"
L.EFFECT_BEACON_TIP = "一顆水晶浮在物件上方，以一縷光線相連。"
L.EFFECT_ORBIT = "軌道"
L.EFFECT_ORBIT_TIP = "三團光靈各循自己的軌道環繞物件。"
L.EFFECT_RIPPLE = "漣漪"
L.EFFECT_RIPPLE_TIP = "漣漪在物件周圍的地面上擴散。"
L.EFFECT_SPARKLE = "星芒"
L.EFFECT_SPARKLE_TIP = "光點在物件周圍閃爍，完全沒有圓環。"

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "輪廓"
L.HEADER_OBJECTS = "標示的物件"
L.HEADER_HIDE = "隱藏效果"
L.HEADER_DETECTION = "偵測"
L.HEADER_GENERAL = "一般"
L.SETTINGS = "設定"

L.SCOPE_ALL = "全部"
L.SCOPE_ALL_TIP = "你的設定會套用到所有類別。原本對該設定有自訂值的類別會失去自訂值。"
L.SCOPE_ONE_TIP = "你的設定只套用到這個類別，其他類別怎麼變動都不影響它。"
L.EFFECT = "效果"
L.EFFECT_TIP = "光效的形狀。"
L.LOOK_OF_ALL = "所有物件的外觀"
L.LOOK_OF = "外觀：%s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "與所有物件相同"
L.SHARED_TIP = "移除這個類別自訂的效果與外觀，改回所有物件的設定。"

L.SIZE = "大小"
L.SIZE_TIP = "效果的大小。"
L.INTENSITY = "強度"
L.INTENSITY_TIP = "效果的亮度。"
L.OFFSET = "垂直位移"
L.OFFSET_TIP = "以物件的名條為基準，將效果上移或下移。預覽會顯示實際位置。"
L.FADE = "隨名條淡出"
L.FADE_TIP = "效果會隨物件的名條一起淡出，例如被場景遮住時。"

L.SILHOUETTE = "從我的角色後方經過"
L.SILHOUETTE_TIP = "效果會沿著你的角色裁切，看起來像從你身後經過，而不是蓋住你。"
L.ZONE_SIZE = "裁切區大小"
L.ZONE_SIZE_TIP = "效果壓到角色時調高，離角色太遠時調低。每個角色各自保存。"
L.ZONE_HEIGHT = "裁切區高度"
L.ZONE_HEIGHT_TIP = "將裁切區上移或下移。每個角色各自保存。"
L.ZONE_SHOW = "顯示裁切區"
L.ZONE_SHOW_TIP = "以紅線描出裁切區：它應該貼合你的角色。關閉此視窗後消失。"

L.SHOW_NAME = "顯示名稱"
L.SHOW_NAME_TIP = "在物件上方顯示名稱，取代遊戲顯示的名稱。"
L.SHOW_ICON = "顯示圖示"
L.SHOW_ICON_TIP = "在物件上方顯示互動圖示，取代遊戲繪製的圖示。"
L.TEXT_SIZE = "文字大小"
L.TEXT_SIZE_TIP = "物件上方名稱的大小，相對於遊戲本身的文字。"
L.FONT = "字型"
L.FONT_TIP = "物件上方名稱的字型。"
L.FONT_GAME = "遊戲字型"
L.COLOR = "顏色"
L.COLOR_TIP = "這些物件上效果的顏色。"
L.COLOR_SECOND = "第二顏色"
L.COLOR_SECOND_TIP = "這些物件上效果的細線與火花的顏色。未選擇前與第一顏色相同。"
L.TIP_COLOR_SAME = "右鍵：與第一顏色相同"
L.TIP_COLOR_SWAP = "Shift+點擊：交換兩個顏色"
L.TIP_COLOR_SET = "左鍵：選擇顏色"
L.TIP_COLOR_RESET = "右鍵：恢復原始顏色"
L.IGNORED = "已忽略的物件：%d"
L.IGNORED_TIP = "不論類別，永遠不會有效果的物件。/lueur ignore list 列出它們，/lueur ignore clear 全部清除。"
L.IGNORE_TARGET = "忽略目標"
L.IGNORE_TARGET_TIP = "忽略你現在面對的物件，以及所有同名的物件。對已忽略的物件點擊兩次即可取消忽略。"

L.HIDE_COMBAT = "戰鬥中"
L.HIDE_COMBAT_TIP = "戰鬥中不顯示效果。"
L.HIDE_INSTANCE = "副本中"
L.HIDE_INSTANCE_TIP = "在地城、團隊副本和戰場中不顯示效果。"
L.HIDE_LOCKED = "我無法使用的物件"
L.HIDE_LOCKED_TIP = "遊戲暫時不允許使用的物件上，效果會熄滅：技能太低、物件上鎖…要進入範圍後遊戲才會告知。"
L.HIDE_UNTRAINED = "未學專業的草藥和礦石"
L.HIDE_UNTRAINED_TIP = "此角色沒有草藥學時草藥不顯示效果，沒有採礦時礦石不顯示效果。"

L.RANGE = "範圍"
L.RANGE_TIP = "遊戲可以選取物件來標示的最遠距離。"
L.DIRECTION = "方向"
L.DIRECTION_TIP = "遊戲往哪裡尋找要選取的物件。"
L.ARC_0 = "正前方"
L.ARC_0_TIP = "只有你正前方的東西。"
L.ARC_1 = "前方"
L.ARC_1_TIP = "你前方的所有東西。"
L.ARC_2 = "四周"
L.ARC_2_TIP = "所有方向，包括你的背後。"
L.EXCLUSIVE = "只顯示有標示的目標"
L.EXCLUSIVE_TIP = "遊戲不再指出沒有效果的互動目標：NPC、信箱…取消勾選時，遊戲會在每個目標上顯示名稱和圖示。"
L.GLOW_ONLY = "僅光效"
L.GLOW_ONLY_TIP = "Lueur 不再顯示物件的名稱和圖示，保留遊戲或其他插件在該處顯示的內容。啟用 Plumber 的 Soft Target 名條時一律開啟。"

L.KEY = "互動鍵"
L.KEY_TIP = "標示的物件進入範圍後，用來拾取、採集或使用它的按鍵。這是遊戲本身的互動鍵：對 NPC 也有效，也可以在遊戲的按鍵設定中更改。"
L.KEY_NONE = "未設定"
L.KEY_LISTEN = "請按下按鍵"
L.KEY_LISTEN_TIP = "按下要使用的按鍵、滑鼠按鍵或滾輪方向。Esc 取消。"
L.KEY_TAKEN = "%s 已用於「%s」。再按一次即可改給互動鍵，或按其他按鍵。"
L.TIP_KEY_SET = "左鍵：選擇按鍵"
L.TIP_KEY_CLEAR = "右鍵：移除按鍵"

L.LANGUAGE = "語言"
L.LANGUAGE_TIP = "Lueur 文字與指令的語言。"
L.LANGUAGE_AUTO = "自動"
L.LANGUAGE_AUTO_TIP = "跟隨遊戲的語言。"

L.ENABLE = "啟用 Lueur"
L.ENABLE_TIP = "停用時，Lueur 會把你原本的選取目標設定還給遊戲。"
L.MINIMAP = "小地圖按鈕"
L.MINIMAP_TIP = "在小地圖邊緣顯示 Lueur 的按鈕。"
L.DEBUG = "在聊天中顯示診斷"
L.DEBUG_TIP = "在聊天視窗中說明每個被選取的物件，以及 Lueur 如何判斷它。"

L.HEADER_SWITCH = "兩種採集專業"
L.NODE_SWITCH = "輪流切換兩種追蹤"
L.NODE_SWITCH_TIP = "遊戲只顯示尋找草藥或尋找礦物的光點，不會同時顯示。每當你移動得夠遠，Lueur 就會開啟另一種。每個角色各自設定。"
L.NODE_SWITCH_YARDS = "切換間隔距離"
L.NODE_SWITCH_YARDS_TIP = "移動多遠之後 Lueur 才開啟另一種追蹤。"

L.PREVIEW_NO_MODEL = "此用戶端無法顯示 3D 模型"
L.PREVIEW_HINT = "拖曳：旋轉  ·  右鍵拖曳：移動  ·  滾輪：縮放"
L.HEADER_PROFILE = "設定檔"
L.HEADER_PROFILE_TIP = "一組有名稱的效果、偵測與隱藏設定。每個角色使用在這裡選擇的設定檔。"
L.PROFILE_DEFAULT = "預設"
L.PROFILE_NEW = "新增"
L.PROFILE_NEW_TIP = "以原始設定建立設定檔，並指定給此角色。"
L.PROFILE_COPY = "複製"
L.PROFILE_COPY_TIP = "以目前設定檔的設定建立新設定檔，並指定給此角色。"
L.PROFILE_RENAME = "重新命名"
L.PROFILE_RENAME_TIP = "為此設定檔取另一個名稱。"
L.PROFILE_DELETE = "刪除"
L.PROFILE_DELETE_TIP = "刪除此設定檔。原本使用它的角色會改用第一個設定檔。再點一次確認。"
L.PROFILE_OK = "確定"
L.PROFILE_CANCEL = "取消"
L.DEFAULTS = "預設值"
L.DEFAULTS_TIP = "將效果與偵測設定恢復為原始值。再點一次確認。"
L.FOOTER = "Lueur %s  ·  /lueur help：所有指令"

L.OPTIONS_NOTE = "靠近礦脈、草藥、任務物件和寶箱時讓它們發光。"
L.OPTIONS_OPEN = "開啟 Lueur 設定"

L.TIP_ENABLED = "已啟用"
L.TIP_DISABLED = "已停用"
L.TIP_LEFT_CLICK = "左鍵：開啟設定"
L.TIP_RIGHT_CLICK = "右鍵：啟用或停用"
L.TIP_DRAG = "拖曳：移動此按鈕"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "已啟用。"
L.MSG_DISABLED = "已停用，你原本的設定已恢復。"
L.MSG_RESTART = "請完全重新啟動遊戲，以完成 Lueur 的更新。"
L.MSG_EXCLUSIVE_ON = "遊戲不再指出沒有效果的目標。"
L.MSG_EXCLUSIVE_OFF = "遊戲會顯示每個互動目標的名稱和圖示 (NPC、世界物件…)。"
L.MSG_SILHOUETTE_ON = "效果從你的角色後方經過。"
L.MSG_SILHOUETTE_OFF = "效果蓋住你的角色。"
L.MSG_CUTOUT_UNAVAILABLE = "無法裁切：%s。"
L.MSG_ZONE_SHOWN = "裁切區已用紅線描出：它應該貼合你的角色。"
L.MSG_ZONE_HIDDEN = "裁切區輪廓已隱藏。"
L.MSG_SILHOUETTE_VALUES = "輪廓：大小 %d%%，高度 %d%%"
L.MSG_SILHOUETTE_USAGE = "用法：/lueur silhouette | show | <大小 {bodyScale}> [高度 {bodyShift}]"
L.MSG_EFFECTS = "可用效果：%s (目前：%s)"
L.MSG_FONTS = "可用字型：%s (目前：%s)"
L.MSG_COLOR_TWO = "%s：顏色 %s 和 %s"
L.MSG_COLOR = "%s：顏色 %s"
L.MSG_NO_PICKER = "此用戶端沒有顏色選擇器：請輸入 /lueur color <類別> <rrggbb>。"
L.MSG_SHARED = "%s：已改回所有物件的效果與外觀。"
L.MSG_HIDE_COMBAT = "戰鬥中隱藏效果：%s"
L.MSG_HIDE_INSTANCE = "副本中隱藏效果：%s"
L.MSG_HIDE_LOCKED = "在你無法使用的物件上隱藏效果：%s"
L.MSG_HIDE_UNTRAINED = "在未學專業的草藥和礦石上隱藏效果：%s"
L.MSG_GLOW_ONLY = "僅光效，名條交給遊戲或其他插件：%s"
L.MSG_IGNORED = "%s 不會再有效果。"
L.MSG_UNIGNORED = "%s 已不再忽略。"
L.MSG_IGNORED_ALREADY = "%s 已被忽略，所有同名物件也是。再要求一次即可取消忽略。"
L.MSG_IGNORE_NO_TARGET = "你面前沒有可忽略的物件。"
L.MSG_IGNORE_LIST = "已忽略的物件：%s"
L.MSG_IGNORE_EMPTY = "沒有忽略任何物件。"
L.MSG_RANGE = "範圍：%d 碼"
L.MSG_RANGE_COMBAT = "範圍：%d 碼，脫離戰鬥後套用。"
L.MSG_RANGE_CLIENT = "範圍：要求 %d 碼，用戶端採用 %s。"
L.MSG_KEY_COMBAT = "戰鬥中無法更改按鍵設定。"
L.MSG_KEY_REFUSED = "遊戲拒絕了按鍵「%s」。"
L.MSG_KEY_REPLACED = "%s 不再觸發「%s」。"

L.FAIL_NO_MASK = "此用戶端不支援遮罩"
L.FAIL_MASK_TEXTURE = "找不到遮罩材質 (請完全重新啟動遊戲)"
L.FAIL_MASK_REFUSED = "用戶端拒絕了遮罩"

L.STATUS_CLIENT = "用戶端 %s (%s)，語言 %s；Lueur 的文字：%s。目前生效的值："
L.STATUS_CVAR_UNKNOWN = "此用戶端沒有這個設定"
L.STATUS_CVAR_DEFAULT = " (預設 %s)"
L.STATUS_EXPECTED = "Lueur 預期：範圍 %d，方向 %d"
L.STATUS_GATE = "只指出有標示的目標：%s | 目前的原生顯示：%s"
L.STATUS_GLOW_ONLY = "僅光效：%s | Plumber 的軟目標名稱：%s"
L.GATE_OPEN = "開啟"
L.GATE_CLOSED = "關閉"
L.STATUS_SILHOUETTE = "效果在角色後方：%s"
L.STATUS_UNAVAILABLE = "無法使用，%s"
L.STATUS_DIRECT = "直接從「softinteract」讀取目標：%s"
L.STATUS_NOT_YET = "尚未出現"
L.STATUS_RANGE_API = "可讀取互動範圍：%s"
L.STATUS_LINE = "釣魚線已拋出：%s | 引導中的法術：%s"
L.STATUS_HIDE = "戰鬥中隱藏：%s | 副本中：%s | 無法使用的物件：%s | 目前暫停：%s"
L.STATUS_SWITCH = "輪流切換追蹤：%s | 可用：%s"
L.MSG_PROFILES = "設定檔：%s。此角色使用：%s。"
L.MSG_PROFILE_UNNAMED = "設定檔需要名稱。"
L.MSG_PROFILE_TAKEN = "已有另一個設定檔叫做 %s。"
L.STATUS_PROFILE = "設定檔：%s | 設定檔數量：%d"
L.STATUS_COST = "上次 status 以來的 CPU：目標 %d 次呼叫，每次 %.3f ms (最長 %.2f) | 動畫 %d 幀，每幀 %.3f ms (最長 %.2f)"
L.STATUS_TRAINED = "未學專業的草藥和礦石不顯示效果：%s | 草藥學：%s，採礦：%s"
L.STATUS_OBJECTS = "此角色顯示的類別：%s | 已忽略的物件：%d"
L.STATUS_OWN = "有自訂設定的類別：%s"
L.STATUS_EFFECT = "效果：%s | 材質：%s"
L.STATUS_KEY = "互動鍵：%s"
L.TEXTURES_PENDING = "尚未載入"
L.TEXTURES_MISSING = "找不到，顯示替代效果 (請完全重新啟動遊戲)"
L.TEXTURES_LOADED = "已載入"

L.OBJECTIVES_HEADER = "進行中的任務目標 %d 個："
L.OBJECTIVES_NOT_ITEM = "  (不是物件：只與完整名稱比對)"
L.OBJECTIVES_LEARNED = "從滑鼠提示得知：%s (%s)"


---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "已沒有互動目標"
L.DEBUG_PAUSED = "暫停中 (戰鬥或副本)"
L.DEBUG_LINE_OUT = "釣魚線已拋出：要求 %d 碼，用戶端採用 %s"
L.DEBUG_LINE_IN = "釣魚線已收回：要求 %d 碼，用戶端採用 %s"
L.DEBUG_IGNORED = "%s 已略過 (不是世界物件)"
L.DEBUG_SKIPPED = "%s 已略過 (在你的忽略清單中)"
L.DEBUG_HIDDEN = "%s → %s，無效果 (類別已隱藏或不明)"
L.DEBUG_UNTRAINED = "%s → %s，無效果 (此角色沒有該專業)"
L.DEBUG_NO_PLATE = "%s → %s，已偵測到但沒有名條：無法顯示效果"
L.DEBUG_SHOWN = "%s → %s，%s"
L.DEBUG_CURSOR = "游標：%s"
L.DEBUG_VIA = "目標：%s"
L.VIA_DIRECT = "直接"
L.VIA_SWEEP = "掃描"
L.DEBUG_RANGE = "在互動範圍內：%s"
L.DEBUG_OBJECT = "物件 ID：%s"
L.DEBUG_FISHING = "釣魚中：%s"
L.DEBUG_QUEST = "與任務有關：%s"
L.DEBUG_MATCH = "與目標關聯的依據：%s (進行中的目標 %d 個)"
L.MATCH_NONE = "無"
L.MATCH_CURSOR = "無，它的游標已說明它是什麼"
L.MATCH_TOOLTIP = "它的滑鼠提示"
L.MATCH_NAME = "它的名稱"
L.MATCH_WORD = "字詞「%s」"
L.MATCH_LOOT = "它的戰利品，先前拾取過"
L.DEBUG_CHEST = "判定為容器的依據：%s"
L.DEBUG_SECRET = "身分為機密值：%s"
L.DEBUG_BEHIND = "在鏡頭後方：%s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "指令："
L.HELP = {
	"/lueur — 開啟或關閉設定視窗 (等同點擊小地圖按鈕)",
	"/lueur minimap — 顯示或隱藏小地圖按鈕",
	"/lueur on | off — 啟用或停用 Lueur (off 會恢復你的設定)",
	"/lueur preview — 開啟設定視窗的預覽，在 3D 物件上顯示效果",
	"/lueur effect [類別] <名稱> — 將此效果套用到所有類別，或其中一個 (ore, herb, quest, chest, bobber, other)；不加名稱則列出效果",
	"/lueur color <類別> <rrggbb> [<rrggbb>] | swap | default — 類別效果的顏色，以及細線與火花用的第二顏色；swap 交換兩者；不加顏色則顯示目前顏色",
	"/lueur shared <類別> — 讓類別改回所有物件的效果與外觀",
	"/lueur size [類別] <{size}> — 效果的大小 (預設 {size=})",
	"/lueur intensity [類別] <{intensity}> — 效果的亮度，單位為 % (預設 {intensity=})",
	"/lueur offset [類別] <{offsetY}> — 效果的垂直位移 (預設 {offsetY=})",
	"/lueur fade [類別] — 效果是否隨名條淡出 (物件被場景遮住時)",
	"/lueur name | icon [類別] — 是否在物件上方顯示名稱或圖示；text [類別] <{textSize}> 設定名稱的大小，單位為 % (預設 {textSize=})",
	"/lueur font [類別] <名稱> | default — 物件名稱的字型；不加名稱則列出字型",
	"/lueur silhouette [類別] — 效果是否從你的角色後方經過，而不是蓋住角色",
	"/lueur silhouette show | <大小 %> [高度 %] — 顯示並調整裁切區",
	"/lueur range <{range}> — 遊戲選取物件的最遠距離，單位為碼 (預設 {range=})",
	"/lueur arc <{arc}> — 0 正前方，1 前方，2 所有方向 (預設 {arc=})",
	"/lueur exclusive — 遊戲是否只指出有效果的目標",
	"/lueur glowonly — Lueur 是否只繪製光效，把目標的名條 (名稱、圖示) 交給遊戲或其他插件",
	"/lueur combat | instance | unavailable | profession — 是否在戰鬥中、副本中、你無法使用的物件上、未學專業的草藥和礦石上隱藏效果",
	"/lueur key <按鍵> | none — 設定拾取標示物件的按鍵 (F, SHIFT-E, BUTTON4…)；不加按鍵則顯示目前按鍵",
	"/lueur ore | herb | quest | chest | bobber | other — 顯示或隱藏某個類別，僅限此角色",
	"/lueur profile [<名稱>] — 列出設定檔，或讓此角色使用該名稱的設定檔",
	"/lueur switch [<{nodeSwitchYards}>] — 同時有兩種採集專業時：隨著移動輪流切換尋找草藥和尋找礦物；數字設定間隔距離，單位為碼 (預設 {nodeSwitchYards=})",
	"/lueur ignore — 忽略你面對的物件及同名物件 (對已忽略的物件執行兩次：取消忽略)；ignore list, ignore clear, ignore <名稱>",
	"/lueur language <auto | de | en | es | fr | it | ko | pt | ru | zhCN | zhTW> — Lueur 文字與指令的語言",
	"/lueur debug — 說明每個被選取的物件，以及 Lueur 如何判斷它",
	"/lueur objectives — 列出用來與物件名稱比對的任務目標",
	"/lueur status — 顯示用戶端實際套用的值",
	"/lueur help — 顯示此清單",
}
