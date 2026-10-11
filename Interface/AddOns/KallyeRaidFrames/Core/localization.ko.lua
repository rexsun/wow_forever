-------------------------------------------------------------------------------
-- Korean localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "비활성화됨: %s와 충돌";


l.SUBTITLE      = "공격대 프레임 지원";
l.DESC          = "공격대 프레임을 개선합니다.\n\n"
.." - 생명력이 부족한 플레이어의 배경을 강조합니다.\n\n"
.." - 역전된 생명력 바는 선택한 색상을 사용합니다.\n\n"
.." - 사거리 밖 유닛의 투명도\n\n"
.." - 공격대 항상 표시\n\n"
.."\n"
.."버프/디버프 개선 (크기, 최대 표시 개수 등)\n\n"
.."정보 바의 이름을 PvP 아이콘과 함께 색상화합니다 |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."공격대 프레임에 대상 아이콘을 표시합니다 (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...)\n\n"
l.OPTIONS_TITLE = format("%s - 설정", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s 로드됨", l.VERS_TITLE);
l.MSG_SDB            = "Kallye 설정 메뉴";

l.INIT_FAILED = format("%s이(가) 올바르게 로드되지 않았습니다!", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "파티 / 공격대";
l.OPTION_HIGHLIGHTLOWHP = "생명력 부족 강조 (동적 색상)"..required;
l.OPTION_REVERTBAR = "생명력 바 "..l.YL.."역전|r (생명력이 적을수록 바가 커집니다!) ";
l.OPTION_HEALTH_LOW = "거의 죽음!";
l.OPTION_HEALTH_LOW_TOOLTIP = "이 색상은 이 한도 "..l.YLL.."미만|r일 때 적용됩니다.\n\n"
    .."예: 25% 미만일 때 빨간색";
l.OPTION_HEALTH_WARN = "경고";
l.OPTION_HEALTH_WARN_TOOLTIP = "이 색상은 이 한도 "..l.YLL.."에서|r 적용됩니다.\n\n"
    .."예: 50%일 때 노란색";
l.OPTION_HEALTH_OK = "양호한 상태";
l.OPTION_HEALTH_OK_TOOLTIP = "이 색상은 이 한도 "..l.YLL.."이상|r일 때 적용됩니다.\n\n"
    .."예: 75% 이상일 때 녹색";
l.OPTION_HEALTH_ALPHA = l.WH.."투명도"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "생명력 바 투명도 (직업 색상 포함)\n"..l.CY.."WoW 기본값: 100%"
l.OPTION_MOVEROLEICONS = "역할 아이콘을 왼쪽 상단으로 이동";
l.OPTION_HIDEDAMAGEICONS = "'피해' 역할 아이콘 숨기기";
l.OPTION_HIDEREALM = "플레이어의 서버 숨기기";
l.OPTION_HIDEREALM_TOOLTIP = "서버 이름이 숨겨져 "..l.YLL.."일리단 - 바리마트라스|r가 "..l.YLL.."일리단 (*)|r로 표시됩니다.";
l.OPTION_ICONONDEATH = "사망한 플레이어 이름에 "..l.RT8.." 추가";
l.OPTION_FRIENDSCLASSCOLOR = "직업별 이름 색상";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "플레이어 이름 직업별 색상 (파티/공격대 프레임)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s : %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "텍스처"
l.OPTION_BAR_TEXTURE_TOOLTIP = "생명력 바 텍스처"
l.OPTION_SOLORAID = l.CY.."솔로 모드에서 공격대 프레임 표시 "..required;
l.OPTION_SOLORAID_TOOLTIP = "파티/공격대 프레임 항상 표시,\n"..l.YLL..USE_RAID_STYLE_PARTY_FRAMES.." 활성화";

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! 공격대 프레임 테스트 !";
l.OPTION_DEBUG_ON_MESSAGE = "공격대 프레임 테스트 활성화됨, 다시 클릭하여 중지!";
l.OPTION_DEBUG_OFF = "! 테스트 중지 !";
l.OPTION_DEBUG_OFF_MESSAGE = "테스트 중지됨, 정상적인 활동을 재개할 수 있습니다.";

l.OPTION_ACTIVATE_MODULE = "모듈 활성화 / 비활성화"
l.OPTION_HIDEDISABLED = l.GYL.."비활성화된 모듈 숨기기"

-- KF START
l.OPTION_INRANGE = "사거리 내일 때 투명도";
l.OPTION_INRANGE_TOOLTIP = l.CY.."WoW 기본값: 100%";
l.OPTION_NOTINRANGE = "사거리 밖일 때 투명도";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."WoW 기본값: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "비전투 시 공격대 투명도";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."WoW 기본값: 100%";
l.OPTION_ALPHADISPELOVERLAY = "해제 오버레이 투명도"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."블리자드 버프/디버프가 RaidFrameAuras로 대체됩니다" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "디버프 / 버프"
l.OPTION_ORIENTATION_LeftThenUp = "왼쪽에서 위로"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."왼쪽에서 위로 (기본값)"
l.OPTION_ORIENTATION_UpThenLeft = "위에서 왼쪽으로"
l.OPTION_ORIENTATION_RightThenUp = "오른쪽에서 위로"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."오른쪽에서 위로 (기본값)"
l.OPTION_ORIENTATION_UpThenRight = "위에서 오른쪽으로"
l.OPTION_BUFFSSCALE = "버프 크기 "..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."WoW 기본값: 1"
l.OPTION_MAXBUFFS = "버프 제한"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "표시할 버프의 최대 개수\n"..l.CY.."WoW 기본값: "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4버프:버프";
l.OPTION_BUFFSPERLINE = "줄당 버프 개수"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "줄당 버프 개수\n"..l.CY.."제한보다 많으면 무시됩니다.";
l.OPTION_BUFFSPERLINE_FORMAT = "줄당 %d개";
l.OPTION_BUFFSORIENTATION = "버프 정렬"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "버프 배열을 선택하세요 (여러 줄 지원)\n"..l.CY.."기본값: "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "가로 위치"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "버프의 상대적인 가로 위치를 조정합니다.";
l.OPTION_BUFFS_RELATIVE_Y = "세로 위치"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "버프의 상대적인 세로 위치를 조정합니다.";
l.OPTION_DEBUFFSSCALE = "디버프 크기 "..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."WoW 기본값: 1"
l.OPTION_MAXDEBUFFS = "디버프 제한"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "표시할 디버프의 최대 개수\n"..l.CY.."WoW 기본값: "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4디버프:디버프";
l.OPTION_DEBUFFSPERLINE = "줄당 디버프 개수"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "줄당 디버프 아이콘 개수\n"..l.CY.."제한보다 많으면 무시됩니다.";
l.OPTION_DEBUFFSPERLINE_FORMAT = "줄당 %d개";
l.OPTION_DEBUFFSORIENTATION = "디버프 정렬"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "디버프 배열을 선택하세요 (여러 줄 지원)\n"..l.CY.."기본값: "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "가로 위치"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "디버프의 상대적인 가로 위치를 조정합니다.";
l.OPTION_DEBUFFS_RELATIVE_Y = "세로 위치"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "디버프의 상대적인 세로 위치를 조정합니다.";
l.OPTION_USETAINTMETHOD = l.CY.."버프/디버프 제한의 고전적인 표시"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "체크 해제 시, 실험적인 표시를 사용합니다.\n체크 시, 안정적인 표시를 사용하지만 "..l.RDL.."세션당 오류|r가 발생할 수 있습니다. 심각하지 않습니다..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." 제한을 변경하면 "..l.RDL.."세션당 오류|r가 발생할 수 있습니다. 심각하지 않습니다..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." 보스 사망 시 몇 초 동안 재배치에 영향을 받을 수 있습니다."
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " 블리자드 오라 숨기기"
l.OPTION_BUFFS_RESET = "모든 재배치 취소"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."자동 — 전투 상태에 따름 (기본값)";
l.OPTION_FILTER_RAID = "항상 비전투 목록";
l.OPTION_FILTER_RAID_IN_COMBAT = "항상 전투 목록";
l.OPTION_BUFFS_SPACING_X = "가로 간격";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "버프 아이콘 사이의 가로 간격 (픽셀)\n"..l.CY.."기본값: 0";
l.OPTION_BUFFS_SPACING_Y = "세로 간격";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "버프 아이콘 사이의 세로 간격 (픽셀)\n"..l.CY.."기본값: 1";
l.OPTION_BUFFSFILTER = "버프 필터";
l.OPTION_BUFFSFILTER_TOOLTIP = "블리자드가 제공하는 버프 목록 선택\n"..l.CY.."자동은 전투 진입/이탈 시 전환됩니다";
l.OPTION_BUFFS_HIDETOOLTIP = "버프 툴팁 숨기기"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "버프 아이콘에 마우스를 올려도 툴팁이 표시되지 않습니다\n"..l.RDL.."우클릭으로 버프를 취소하는 기능도 비활성화됩니다";
l.OPTION_DEBUFFS_SPACING_X = "가로 간격";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "디버프 아이콘 사이의 가로 간격 (픽셀)\n"..l.CY.."기본값: 0";
l.OPTION_DEBUFFS_SPACING_Y = "세로 간격";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "디버프 아이콘 사이의 세로 간격 (픽셀)\n"..l.CY.."기본값: 1";
l.OPTION_DEBUFFSFILTER = "디버프 필터";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "블리자드가 제공하는 디버프 목록 선택\n"..l.CY.."자동은 전투 진입/이탈 시 전환됩니다";
l.OPTION_DEBUFFS_HIDETOOLTIP = "디버프 툴팁 숨기기"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "디버프 아이콘에 마우스를 올려도 툴팁이 표시되지 않습니다\n"..l.RDL.."우클릭으로 디버프를 취소하는 기능도 비활성화됩니다";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "정보 바";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."기본값";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "직업 색상";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "선택한 색상: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."아이콘 없음";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "진영 아이콘 |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "레벨이 낮을 때 색상";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "자신보다 레벨이 낮을 때의 색상을 선택하세요.";
l.OPTION_NAMEPLATES_COLOR_OVER = "레벨이 높을 때 색상";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "자신보다 레벨이 높을 때의 색상을 선택하세요.";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."절대 안 함";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "정보 바에 레벨을 절대 표시하지 않습니다.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "자신과 다를 경우";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "자신과 다를 경우, 색상화";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "항상";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "항상, 색상화";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "아군 이름";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "아군 정보 바의 이름 색상 (인스턴스 외부)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "아군 바";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "아군 정보 바의 색상 (인스턴스 외부)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "아군 바 텍스처"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "아군 정보 바의 텍스처 (인스턴스 외부)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "아군 PvP 아이콘";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "아군 이름에 PvP 아이콘을 표시합니다.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "아군 레벨";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "아군 정보 바에 레벨을 표시합니다.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "적 이름";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "적 정보 바의 이름 색상 (인스턴스 외부)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "적 바";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "적 정보 바의 색상 (인스턴스 외부)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "적 바 텍스처"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "적 정보 바의 텍스처 (인스턴스 외부)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "적 PvP 아이콘";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "적 이름에 PvP 아이콘을 표시합니다.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "적 레벨";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "적 정보 바에 레벨을 표시합니다.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."공격대 프레임에 대상 아이콘을 표시합니다 (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...)"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "공격대 아이콘";
l.OPTION_RAIDICONS_ANCHOR = "아이콘 정렬";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "공격대 프레임 내 대상 아이콘 위치";
l.OPTION_CENTER = "중앙"
l.OPTION_TOPLEFT = "왼쪽 상단";
l.OPTION_TOPRIGHT = "오른쪽 상단";
l.OPTION_BOTTOMLEFT = "왼쪽 하단";
l.OPTION_BOTTOMRIGHT = "오른쪽 하단";
l.OPTION_RAIDICONS_SIZE = "아이콘 크기";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "공격대 아이콘 크기를 조정합니다.";
l.OPTION_RAIDICONS_RELATIVE_X = "가로 위치";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "공격대 아이콘의 상대적인 가로 위치를 조정합니다.";
l.OPTION_RAIDICONS_RELATIVE_Y = "세로 위치";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "공격대 아이콘의 상대적인 세로 위치를 조정합니다.";
-- KRI END

l.OPTION_RESET_OPTIONS = "프로필 초기화";
l.OPTION_RELOAD_REQUIRED = "일부 변경 사항은 다시 로드해야 적용됩니다 (입력: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": 다시 로드해야 하는 설정";

l.OPTION_SHOWMSGNORMAL = l.GYL.."메시지 표시";
l.OPTION_SHOWMSGWARNING = l.GYL.."경고 표시";
l.OPTION_SHOWMSGERR = l.GYL.."오류 표시";
l.OPTION_COMPARTMENT_FILTER = "칸 필터에 표시";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "오른쪽 상단 애드온 목록에";
l.OPTION_WHATSNEW = "새로운 기능";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r 옵션을 활성화하는 것을 고려하세요 ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."솔로 시 파티 프레임 표시 "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "공격대에서 파티 프레임도 표시"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "공격대 안에서도 파티와 공격대 프레임 둘 다 표시합니다 (추천)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s %s|r 옵션 %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "참고: "..HUD_EDIT_MODE_MENU.." 후 "..l.YL.."/reload|r를 입력하여 오류를 방지하세요.";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = l.YL..HUD_EDIT_MODE_MENU.."|r를 활성화하고 "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r 옵션을 직접 표시합니다.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "공격대 프레임 테스트 활성화됨 ("..HUD_EDIT_MODE_MENU.."에서 테스트 가능)\n"
                    .."다시 클릭하여 중지!";
end