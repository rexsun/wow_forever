-- Lueur : textes en coréen (traduction automatique, non relue)
local _, ns = ...

local L = {}
ns.LOCALES.koKR = L

L.LANGUAGE_NAME = "한국어"
L.PREFIX = "|cffffd200Lueur|r: "
L.YES = "예"
L.NO = "아니요"
L.SETTING = "%s: %s"
L.FORMAT_PERCENT = "%d%%"
L.FORMAT_RANGE = "%d미터"
L.CONFIRM = "확인?"

-- pas de mots de commande coréens : les noms anglais répondent
L.COMMANDS = {}

---------------------------------------------------------------------------
-- Catégories, états, effets
---------------------------------------------------------------------------

L.CATEGORY_ORE = "광석"
L.CATEGORY_ORE_TIP = "광맥과 광물 매장지입니다."
L.CATEGORY_HERB = "약초"
L.CATEGORY_HERB_TIP = "채집할 수 있는 식물입니다."
L.CATEGORY_QUEST = "퀘스트"
L.CATEGORY_QUEST_TIP = "진행 중인 퀘스트와 관련된 사물입니다."
L.CATEGORY_CHEST = "상자"
L.CATEGORY_CHEST_TIP = "전리품을 얻을 수 있는 상자, 궤짝 등의 보관함입니다."
L.CATEGORY_BOBBER = "낚시찌"
L.CATEGORY_BOBBER_TIP = "낚싯줄 끝의 낚시찌입니다."
L.CATEGORY_OTHER = "기타 사물"
L.CATEGORY_OTHER_TIP = "일상적인 사물: 문, 우체통, 레버…"

-- la catégorie d'un objet, dans une phrase du diagnostic
L.NAME_ORE = "광석"
L.NAME_HERB = "약초"
L.NAME_QUEST = "퀘스트"
L.NAME_CHEST = "상자"
L.NAME_BOBBER = "낚시찌"
L.NAME_OTHER = "기타"
L.NAME_NONE = "없음"
L.NAME_UNNAMED = "이름 없는 모든 사물"

-- l'objet que l'aperçu montre pour chaque catégorie
L.SAMPLE_ORE = "구리 광맥"
L.SAMPLE_HERB = "평온초"
L.SAMPLE_QUEST = "보급품 상자"
L.SAMPLE_CHEST = "낡은 상자"
L.SAMPLE_BOBBER = "낚시찌"
L.SAMPLE_OTHER = "우체통"

L.STATE_FAR = "거리 밖"
L.STATE_READY = "거리 안"
L.STATE_LOCKED = "사용 불가"

L.EFFECT_AURA = "오라"
L.EFFECT_AURA_TIP = "빛무리와 아지랑이에 고리, 혜성, 반딧불이가 어우러집니다."
L.EFFECT_SUBTLE = "은은함"
L.EFFECT_SUBTLE_TIP = "고리와 혜성 없이 부드럽게 빛납니다."
L.EFFECT_SIGIL = "인장"
L.EFFECT_SIGIL_TIP = "룬 문양의 원이 사물 주위를 천천히 돕니다."
L.EFFECT_BRACKETS = "조준틀"
L.EFFECT_BRACKETS_TIP = "네 모서리가 사물을 둘러싸고, 거리 안에 들어오면 사물에 고정됩니다."
L.EFFECT_VORTEX = "소용돌이"
L.EFFECT_VORTEX_TIP = "차원문이 열리듯 빛줄기가 사물을 휘감습니다."
L.EFFECT_FLAME = "불꽃"
L.EFFECT_FLAME_TIP = "사물의 색을 띤 불길이 사물에서 피어오릅니다."
L.EFFECT_RIFT = "균열"
L.EFFECT_RIFT_TIP = "빛의 고리를 두른 검은 구멍이 불티를 나선으로 빨아들입니다."
L.EFFECT_STORM = "폭풍"
L.EFFECT_STORM_TIP = "사물 위에 먹구름이 모이고 번개가 내리칩니다."
L.EFFECT_GEYSER = "간헐천"
L.EFFECT_GEYSER_TIP = "빛의 분수가 사물에서 솟아올라 주위로 떨어집니다."
L.EFFECT_SPIRIT = "정령"
L.EFFECT_SPIRIT_TIP = "도깨비불 둘이 빛의 띠를 끌며 사물 주위에서 춤춥니다."
L.EFFECT_BEAM = "빛기둥"
L.EFFECT_BEAM_TIP = "사물에서 빛기둥이 솟고, 불티가 그것을 따라 떠오릅니다."
L.EFFECT_BEACON = "봉화"
L.EFFECT_BEACON_TIP = "빛의 실로 이어진 수정이 사물 위에 떠 있습니다."
L.EFFECT_ORBIT = "궤도"
L.EFFECT_ORBIT_TIP = "도깨비불 셋이 저마다의 궤도로 사물 주위를 돕니다."
L.EFFECT_RIPPLE = "물결"
L.EFFECT_RIPPLE_TIP = "사물 주위의 땅 위로 물결이 퍼져 나갑니다."
L.EFFECT_SPARKLE = "반짝임"
L.EFFECT_SPARKLE_TIP = "원 없이 사물 주위에서 빛이 반짝입니다."

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------

L.HEADER_SILHOUETTE = "실루엣"
L.HEADER_OBJECTS = "강조할 사물"
L.HEADER_HIDE = "효과 숨기기"
L.HEADER_DETECTION = "감지"
L.HEADER_GENERAL = "일반"
L.SETTINGS = "설정"

L.SCOPE_ALL = "전체"
L.SCOPE_ALL_TIP = "여기서 바꾼 설정은 모든 분류에 적용됩니다. 그 설정에 고유한 값을 가졌던 분류는 그 값을 잃습니다."
L.SCOPE_ONE_TIP = "여기서 바꾼 설정은 이 분류에만 적용되며, 다른 분류가 바뀌어도 유지됩니다."
L.EFFECT = "효과"
L.EFFECT_TIP = "빛의 모양입니다."
L.LOOK_OF_ALL = "모든 사물의 모양"
L.LOOK_OF = "모양: %s"
L.OF_CATEGORY = "%s (%s)"
L.SHARED = "모든 사물과 같게"
L.SHARED_TIP = "이 분류의 고유한 효과와 모양을 없애고, 모든 사물의 것을 다시 따르게 합니다."

L.SIZE = "크기"
L.SIZE_TIP = "효과의 크기입니다."
L.INTENSITY = "밝기"
L.INTENSITY_TIP = "효과의 밝기입니다."
L.OFFSET = "세로 위치"
L.OFFSET_TIP = "사물의 이름표를 기준으로 효과를 위아래로 옮깁니다. 미리보기에서 위치를 확인할 수 있습니다."
L.FADE = "이름표와 함께 흐려짐"
L.FADE_TIP = "지형에 가려질 때처럼 사물의 이름표가 흐려지면 효과도 함께 흐려집니다."

L.SILHOUETTE = "내 캐릭터 뒤로 지나가기"
L.SILHOUETTE_TIP = "효과를 캐릭터 둘레로 오려 내어, 캐릭터를 덮지 않고 뒤로 지나가는 것처럼 보이게 합니다."
L.ZONE_SIZE = "오림 영역 크기"
L.ZONE_SIZE_TIP = "효과가 캐릭터를 침범하면 높이고, 너무 멀리 떨어지면 낮추세요. 캐릭터별로 저장됩니다."
L.ZONE_HEIGHT = "오림 영역 높이"
L.ZONE_HEIGHT_TIP = "오림 영역을 위아래로 옮깁니다. 캐릭터별로 저장됩니다."
L.ZONE_SHOW = "오림 영역 표시"
L.ZONE_SHOW_TIP = "오림 영역을 빨간 윤곽선으로 표시합니다. 캐릭터에 꼭 맞아야 합니다. 이 창을 닫으면 사라집니다."

L.SHOW_NAME = "이름 표시"
L.SHOW_NAME_TIP = "게임이 쓰는 이름 대신 사물 위에 이름을 표시합니다."
L.SHOW_ICON = "아이콘 표시"
L.SHOW_ICON_TIP = "게임이 그리는 아이콘 대신 사물 위에 상호작용 아이콘을 표시합니다."
L.TEXT_SIZE = "글자 크기"
L.TEXT_SIZE_TIP = "게임의 글자 크기를 기준으로 한, 사물 위 이름의 크기입니다."
L.FONT = "글꼴"
L.FONT_TIP = "사물 위에 표시되는 이름의 글꼴입니다."
L.FONT_GAME = "게임 글꼴"
L.COLOR = "색상"
L.COLOR_TIP = "이 사물들에 나타나는 효과의 색상입니다."
L.COLOR_SECOND = "두 번째 색상"
L.COLOR_SECOND_TIP = "이 사물들에 나타나는 효과의 가는 선과 불티의 색상입니다. 따로 고르기 전에는 첫 번째 색상과 같습니다."
L.TIP_COLOR_SAME = "오른쪽 클릭: 첫 번째 색상과 같게"
L.TIP_COLOR_SWAP = "Shift+클릭: 두 색상 맞바꾸기"
L.TIP_COLOR_SET = "왼쪽 클릭: 색상 선택"
L.TIP_COLOR_RESET = "오른쪽 클릭: 원래 색상으로"
L.IGNORED = "무시하는 사물: %d"
L.IGNORED_TIP = "분류와 관계없이 효과가 나타나지 않는 사물입니다. /lueur ignore list 명령어로 목록을 보고, /lueur ignore clear 명령어로 모두 지웁니다."
L.IGNORE_TARGET = "대상 무시"
L.IGNORE_TARGET_TIP = "지금 마주 보고 있는 사물과 같은 이름의 모든 사물을 무시합니다. 이미 무시 중인 사물에서는 두 번 클릭하면 무시를 해제합니다."

L.HIDE_COMBAT = "전투 중"
L.HIDE_COMBAT_TIP = "전투 중에는 효과를 표시하지 않습니다."
L.HIDE_INSTANCE = "인스턴스 안"
L.HIDE_INSTANCE_TIP = "던전, 공격대, 전장에서는 효과를 표시하지 않습니다."
L.HIDE_LOCKED = "사용할 수 없는 사물"
L.HIDE_LOCKED_TIP = "숙련도 부족, 잠긴 사물 등 게임이 지금 사용을 허용하지 않는 사물에서는 효과가 꺼집니다. 게임은 거리 안에 들어와야만 이를 알려 줍니다."
L.HIDE_UNTRAINED = "전문 기술 없는 약초와 광석"
L.HIDE_UNTRAINED_TIP = "이 캐릭터에게 약초채집이 없으면 약초에, 채광이 없으면 광석에 효과를 표시하지 않습니다."

L.RANGE = "거리"
L.RANGE_TIP = "게임이 강조할 사물을 고를 수 있는 최대 거리입니다."
L.DIRECTION = "방향"
L.DIRECTION_TIP = "게임이 사물을 찾는 방향입니다."
L.ARC_0 = "정면"
L.ARC_0_TIP = "바로 앞에 있는 것만 찾습니다."
L.ARC_1 = "앞쪽"
L.ARC_1_TIP = "앞쪽에 있는 모든 것을 찾습니다."
L.ARC_2 = "모든 방향"
L.ARC_2_TIP = "등 뒤를 포함한 모든 방향에서 찾습니다."
L.EXCLUSIVE = "강조된 대상만 표시"
L.EXCLUSIVE_TIP = "NPC, 우체통처럼 효과가 없는 상호작용 대상을 게임이 더 이상 표시하지 않습니다. 선택을 해제하면 모든 대상에 이름과 아이콘이 표시됩니다."
L.GLOW_ONLY = "빛만 표시"
L.GLOW_ONLY_TIP = "Lueur가 사물의 이름과 아이콘을 표시하지 않고, 게임이나 다른 애드온이 표시하는 것을 그대로 둡니다. Plumber의 Soft Target 이름표가 켜져 있으면 항상 적용됩니다."

L.KEY = "상호작용 단축키"
L.KEY_TIP = "강조된 사물이 거리 안에 들어오면 줍거나 채집하거나 사용하는 단축키입니다. 게임의 상호작용 단축키 그대로이므로 NPC에게도 작동하며, 게임의 단축키 설정에서도 바꿀 수 있습니다."
L.KEY_NONE = "지정 안 됨"
L.KEY_LISTEN = "키를 누르세요"
L.KEY_LISTEN_TIP = "사용할 키, 마우스 버튼 또는 마우스 휠 방향을 누르세요. Esc 키를 누르면 취소합니다."
L.KEY_TAKEN = "%s 키는 이미 “%s”에 사용 중입니다. 상호작용 단축키로 바꾸려면 다시 누르고, 아니면 다른 키를 누르세요."
L.TIP_KEY_SET = "왼쪽 클릭: 단축키 선택"
L.TIP_KEY_CLEAR = "오른쪽 클릭: 단축키 해제"

L.LANGUAGE = "언어"
L.LANGUAGE_TIP = "Lueur의 문구와 명령어에 쓰이는 언어입니다."
L.LANGUAGE_AUTO = "자동"
L.LANGUAGE_AUTO_TIP = "게임의 언어를 따릅니다."

L.ENABLE = "Lueur 사용"
L.ENABLE_TIP = "사용하지 않으면 Lueur가 원래의 대상 지정 설정을 게임에 되돌려 줍니다."
L.MINIMAP = "미니맵 버튼"
L.MINIMAP_TIP = "미니맵 가장자리에 Lueur 버튼을 표시합니다."
L.DEBUG = "대화창에 진단 표시"
L.DEBUG_TIP = "대상이 된 사물과 Lueur가 그것을 어떻게 판단했는지 대화창에 표시합니다."

-- alternance des deux pistages
L.HEADER_SWITCH = "채집 전문 기술 두 가지"
L.NODE_SWITCH = "두 추적 번갈아 켜기"
L.NODE_SWITCH_TIP = "게임은 약초 찾기와 광물 찾기 중 하나의 점만 표시합니다. Lueur가 충분히 이동할 때마다 다른 쪽 추적을 켭니다. 캐릭터별로 설정됩니다."
L.NODE_SWITCH_YARDS = "전환 간격"
L.NODE_SWITCH_YARDS_TIP = "Lueur가 다른 쪽 추적을 켜기까지 이동해야 하는 거리입니다."

L.PREVIEW_NO_MODEL = "이 클라이언트에서는 3D 모델을 쓸 수 없습니다"
L.PREVIEW_HINT = "끌기: 회전  ·  오른쪽 끌기: 이동  ·  휠: 확대/축소"
L.HEADER_PROFILE = "프로필"
L.HEADER_PROFILE_TIP = "효과, 감지, 숨기기 설정을 이름 붙여 묶은 것입니다. 각 캐릭터는 여기서 고른 프로필을 사용합니다."
L.PROFILE_DEFAULT = "기본"
L.PROFILE_NEW = "새로"
L.PROFILE_NEW_TIP = "기본 설정으로 프로필을 만들어 이 캐릭터에 적용합니다."
L.PROFILE_COPY = "복사"
L.PROFILE_COPY_TIP = "이 프로필의 설정으로 새 프로필을 만들어 이 캐릭터에 적용합니다."
L.PROFILE_RENAME = "이름 변경"
L.PROFILE_RENAME_TIP = "이 프로필의 이름을 바꿉니다."
L.PROFILE_DELETE = "삭제"
L.PROFILE_DELETE_TIP = "이 프로필을 삭제합니다. 이 프로필을 쓰던 캐릭터는 첫 번째 프로필로 돌아갑니다. 한 번 더 클릭하면 확정됩니다."
L.PROFILE_OK = "확인"
L.PROFILE_CANCEL = "취소"
L.DEFAULTS = "기본값"
L.DEFAULTS_TIP = "효과와 감지 설정을 원래 값으로 되돌립니다. 한 번 더 클릭하면 확정됩니다."
L.FOOTER = "Lueur %s  ·  /lueur help: 모든 명령어"

L.OPTIONS_NOTE = "광맥, 약초, 퀘스트 사물, 상자에 다가가면 빛나게 합니다."
L.OPTIONS_OPEN = "Lueur 설정 열기"

L.TIP_ENABLED = "사용 중"
L.TIP_DISABLED = "사용 안 함"
L.TIP_LEFT_CLICK = "왼쪽 클릭: 설정 열기"
L.TIP_RIGHT_CLICK = "오른쪽 클릭: 켜기 또는 끄기"
L.TIP_DRAG = "끌기: 이 버튼 이동"

---------------------------------------------------------------------------
-- Messages des commandes
---------------------------------------------------------------------------

L.MSG_ENABLED = "사용합니다."
L.MSG_DISABLED = "사용하지 않습니다. 원래 설정을 복원했습니다."
L.MSG_RESTART = "Lueur 업데이트를 마치려면 게임을 완전히 다시 시작하세요."
L.MSG_EXCLUSIVE_ON = "효과가 없는 대상은 게임이 더 이상 표시하지 않습니다."
L.MSG_EXCLUSIVE_OFF = "게임이 모든 상호작용 대상(NPC, 사물…)의 이름과 아이콘을 표시합니다."
L.MSG_SILHOUETTE_ON = "효과가 캐릭터 뒤로 지나갑니다."
L.MSG_SILHOUETTE_OFF = "효과가 캐릭터를 덮습니다."
L.MSG_CUTOUT_UNAVAILABLE = "오림을 쓸 수 없습니다: %s."
L.MSG_ZONE_SHOWN = "오림 영역을 빨간 윤곽선으로 표시했습니다. 캐릭터에 꼭 맞아야 합니다."
L.MSG_ZONE_HIDDEN = "오림 영역 윤곽선을 숨겼습니다."
L.MSG_SILHOUETTE_VALUES = "실루엣: 크기 %d%%, 높이 %d%%"
L.MSG_SILHOUETTE_USAGE = "사용법: /lueur silhouette | show | <크기 {bodyScale}> [높이 {bodyShift}]"
L.MSG_EFFECTS = "사용 가능한 효과: %s (현재: %s)"
L.MSG_FONTS = "사용 가능한 글꼴: %s (현재: %s)"
L.MSG_COLOR_TWO = "%s: 색상 %s, %s"
L.MSG_COLOR = "%s: 색상 %s"
L.MSG_NO_PICKER = "이 클라이언트에는 색상 선택 창이 없습니다. /lueur color <분류> <rrggbb> 명령어를 입력하세요."
L.MSG_SHARED = "%s: 모든 사물의 효과와 모양을 다시 따릅니다."
L.MSG_HIDE_COMBAT = "전투 중 효과 숨김: %s"
L.MSG_HIDE_INSTANCE = "인스턴스 안에서 효과 숨김: %s"
L.MSG_HIDE_LOCKED = "사용할 수 없는 사물에서 효과 숨김: %s"
L.MSG_HIDE_UNTRAINED = "전문 기술 없는 약초와 광석에서 효과 숨김: %s"
L.MSG_GLOW_ONLY = "빛만 표시, 이름표는 게임이나 다른 애드온에 맡김: %s"
L.MSG_IGNORED = "%s: 더 이상 효과를 표시하지 않습니다."
L.MSG_UNIGNORED = "%s: 더 이상 무시하지 않습니다."
L.MSG_IGNORED_ALREADY = "%s: 같은 이름의 모든 사물과 함께 이미 무시 중입니다. 무시를 해제하려면 한 번 더 요청하세요."
L.MSG_IGNORE_NO_TARGET = "앞에 무시할 사물이 없습니다."
L.MSG_IGNORE_LIST = "무시하는 사물: %s"
L.MSG_IGNORE_EMPTY = "무시하는 사물이 없습니다."
L.MSG_RANGE = "거리: %d미터"
L.MSG_RANGE_COMBAT = "거리: %d미터, 전투가 끝나면 적용됩니다."
L.MSG_RANGE_CLIENT = "거리: %d미터를 요청했으나 클라이언트가 적용한 값은 %s입니다."
L.MSG_KEY_COMBAT = "전투 중에는 단축키를 바꿀 수 없습니다."
L.MSG_KEY_REFUSED = "게임이 “%s” 키를 거부했습니다."
L.MSG_KEY_REPLACED = "%s 키는 더 이상 “%s”에 쓰이지 않습니다."

L.FAIL_NO_MASK = "이 클라이언트는 마스크를 지원하지 않습니다"
L.FAIL_MASK_TEXTURE = "마스크 텍스처를 찾을 수 없습니다 (게임을 완전히 다시 시작하세요)"
L.FAIL_MASK_REFUSED = "클라이언트가 마스크를 거부했습니다"

L.STATUS_CLIENT = "클라이언트 %s (%s), 언어 %s; Lueur 문구: %s. 적용 중인 값:"
L.STATUS_CVAR_UNKNOWN = "이 클라이언트에 없음"
L.STATUS_CVAR_DEFAULT = " (기본값 %s)"
L.STATUS_EXPECTED = "Lueur가 기대하는 값: 거리 %d, 방향 %d"
L.STATUS_GATE = "강조된 대상만 표시: %s | 현재 게임 기본 표시: %s"
L.STATUS_GLOW_ONLY = "빛만 표시: %s | Plumber의 대상 이름: %s"
L.GATE_OPEN = "열림"
L.GATE_CLOSED = "닫힘"
L.STATUS_SILHOUETTE = "캐릭터 뒤로 지나가는 효과: %s"
L.STATUS_UNAVAILABLE = "사용 불가, %s"
L.STATUS_DIRECT = "“softinteract”에서 대상을 직접 읽음: %s"
L.STATUS_NOT_YET = "아직 확인되지 않음"
L.STATUS_RANGE_API = "상호작용 거리 읽기 가능: %s"
L.STATUS_LINE = "낚싯줄 던짐: %s | 정신 집중 중인 주문: %s"
L.STATUS_HIDE = "전투 중 숨김: %s | 인스턴스 안: %s | 사용할 수 없는 사물: %s | 현재 일시 중지: %s"
L.STATUS_SWITCH = "추적 번갈아 켜기: %s | 사용 가능: %s"
L.MSG_PROFILES = "프로필: %s. 이 캐릭터가 사용하는 프로필: %s."
L.MSG_PROFILE_UNNAMED = "프로필에는 이름이 필요합니다."
L.MSG_PROFILE_TAKEN = "같은 이름의 프로필이 이미 있습니다: %s."
L.STATUS_PROFILE = "프로필: %s | 프로필 수: %d"
L.STATUS_COST = "지난 status 이후 CPU: 대상 %d회 호출, 회당 %.3f ms (최장 %.2f) | 애니메이션 %d프레임, 프레임당 %.3f ms (최장 %.2f)"
L.STATUS_TRAINED = "전문 기술 없는 약초와 광석에 효과 없음: %s | 약초채집: %s, 채광: %s"
L.STATUS_OBJECTS = "이 캐릭터에 표시되는 분류: %s | 무시하는 사물: %d"
L.STATUS_OWN = "고유한 설정을 가진 분류: %s"
L.STATUS_EFFECT = "효과: %s | 텍스처: %s"
L.STATUS_KEY = "상호작용 단축키: %s"
L.TEXTURES_PENDING = "아직 불러오지 않음"
L.TEXTURES_MISSING = "없음, 대체 효과 표시 중 (게임을 완전히 다시 시작하세요)"
L.TEXTURES_LOADED = "불러옴"

L.OBJECTIVES_HEADER = "진행 중인 퀘스트 목표 %d개:"
L.OBJECTIVES_NOT_ITEM = "  (사물이 아님: 전체 이름과만 비교)"
L.OBJECTIVES_LEARNED = "툴팁에서 알아냄: %s (%s)"


---------------------------------------------------------------------------
-- Diagnostic (/lueur debug)
---------------------------------------------------------------------------

L.DEBUG_NO_TARGET = "상호작용 대상이 없어졌습니다"
L.DEBUG_PAUSED = "일시 중지 (전투 또는 인스턴스)"
L.DEBUG_LINE_OUT = "낚싯줄 던짐: %d미터 요청, 클라이언트 적용 값 %s"
L.DEBUG_LINE_IN = "낚싯줄 거둠: %d미터 요청, 클라이언트 적용 값 %s"
L.DEBUG_IGNORED = "%s 무시됨 (게임 세계의 사물이 아님)"
L.DEBUG_SKIPPED = "%s 무시됨 (무시하는 사물 목록에 있음)"
L.DEBUG_HIDDEN = "%s → %s, 효과 없음 (분류가 숨겨졌거나 알 수 없음)"
L.DEBUG_UNTRAINED = "%s → %s, 효과 없음 (이 캐릭터에게 전문 기술이 없음)"
L.DEBUG_NO_PLATE = "%s → %s, 감지했으나 이름표가 없음: 효과를 표시할 수 없음"
L.DEBUG_SHOWN = "%s → %s, %s"
L.DEBUG_CURSOR = "커서: %s"
L.DEBUG_VIA = "대상: %s"
L.VIA_DIRECT = "직접"
L.VIA_SWEEP = "훑기"
L.DEBUG_RANGE = "상호작용 거리 안: %s"
L.DEBUG_OBJECT = "사물 ID: %s"
L.DEBUG_FISHING = "낚시 중: %s"
L.DEBUG_QUEST = "퀘스트 관련: %s"
L.DEBUG_MATCH = "목표와 연결된 근거: %s (진행 중인 목표 %d개)"
L.MATCH_NONE = "없음"
L.MATCH_CURSOR = "없음, 커서가 무엇인지 알려 줌"
L.MATCH_TOOLTIP = "툴팁"
L.MATCH_NAME = "이름"
L.MATCH_WORD = "단어 “%s”"
L.MATCH_LOOT = "전에 획득한 전리품"
L.DEBUG_CHEST = "보관함으로 인식된 근거: %s"
L.DEBUG_SECRET = "비공개 정보: %s"
L.DEBUG_BEHIND = "카메라 뒤: %s"

---------------------------------------------------------------------------
-- Aide (/lueur help). {réglage} : ses bornes ; {réglage=} : sa valeur par défaut
---------------------------------------------------------------------------

L.HELP_HEADER = "명령어:"
L.HELP = {
	"/lueur — 설정 창을 열거나 닫습니다 (미니맵 버튼 클릭과 같음)",
	"/lueur minimap — 미니맵 버튼을 표시하거나 숨깁니다",
	"/lueur on | off — Lueur를 켜거나 끕니다 (off는 원래 설정을 복원함)",
	"/lueur preview — 3D 사물에 효과를 보여 주는 미리보기로 설정 창을 엽니다",
	"/lueur effect [분류] <이름> — 이 효과를 모든 분류 또는 한 분류(ore, herb, quest, chest, bobber, other)에 적용합니다; 이름이 없으면 목록을 표시",
	"/lueur color <분류> <rrggbb> [<rrggbb>] | swap | default — 분류의 효과 색상과, 가는 선과 불티에 쓰는 두 번째 색상; swap은 둘을 맞바꿈; 색상이 없으면 현재 값을 표시",
	"/lueur shared <분류> — 분류가 모든 사물의 효과와 모양을 다시 따르게 합니다",
	"/lueur size [분류] <{size}> — 효과의 크기 (기본값 {size=})",
	"/lueur intensity [분류] <{intensity}> — 효과의 밝기, % 단위 (기본값 {intensity=})",
	"/lueur offset [분류] <{offsetY}> — 효과의 세로 위치 (기본값 {offsetY=})",
	"/lueur fade [분류] — 효과가 이름표와 함께 흐려질지 여부 (지형에 가려진 사물)",
	"/lueur name | icon [분류] — 사물 위에 이름 또는 아이콘을 표시할지 여부; text [분류] <{textSize}> 는 이름의 크기를 % 단위로 설정 (기본값 {textSize=})",
	"/lueur font [분류] <이름> | default — 사물 이름의 글꼴; 이름이 없으면 목록을 표시",
	"/lueur silhouette [분류] — 효과가 캐릭터를 덮지 않고 뒤로 지나갈지 여부",
	"/lueur silhouette show | <크기 %> [높이 %] — 오림 영역을 표시하고 조정합니다",
	"/lueur range <{range}> — 게임이 사물을 고르는 거리, 미터 단위 (기본값 {range=})",
	"/lueur arc <{arc}> — 0 정면, 1 앞쪽, 2 모든 방향 (기본값 {arc=})",
	"/lueur exclusive — 효과가 있는 대상만 게임이 표시할지 여부",
	"/lueur glowonly — Lueur가 빛만 그리고 대상의 이름표(이름, 아이콘)는 게임이나 다른 애드온에 맡길지 여부",
	"/lueur combat | instance | unavailable | profession — 전투 중, 인스턴스 안, 사용할 수 없는 사물, 전문 기술 없는 약초와 광석에서 효과를 숨길지 여부",
	"/lueur key <키> | none — 강조된 사물을 줍는 단축키를 지정합니다 (F, SHIFT-E, BUTTON4…); 키가 없으면 현재 단축키를 표시",
	"/lueur ore | herb | quest | chest | bobber | other — 이 캐릭터에서 분류를 표시하거나 숨깁니다",
	"/lueur profile [<이름>] — 프로필 목록을 표시하거나, 그 이름의 프로필을 이 캐릭터에 적용합니다",
	"/lueur switch [<{nodeSwitchYards}>] — 채집 전문 기술이 둘일 때: 이동하는 동안 약초 찾기와 광물 찾기를 번갈아 켭니다; 숫자는 전환 간격을 미터 단위로 설정 (기본값 {nodeSwitchYards=})",
	"/lueur ignore — 마주 보고 있는 사물과 같은 이름의 사물을 무시합니다 (무시 중인 사물에서 두 번: 무시 해제); ignore list, ignore clear, ignore <이름>",
	"/lueur language <auto | de | en | es | fr | it | ko | pt | ru | zhCN | zhTW> — Lueur의 문구와 명령어에 쓰이는 언어",
	"/lueur debug — 대상이 된 사물과 Lueur가 그것을 어떻게 판단했는지 표시합니다",
	"/lueur objectives — 사물 이름과 비교하는 퀘스트 목표의 목록을 표시합니다",
	"/lueur status — 클라이언트가 실제로 적용한 값을 표시합니다",
	"/lueur help — 이 목록을 표시합니다",
}
