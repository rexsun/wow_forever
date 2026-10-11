local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("koKR") then return end

YUI.Locale:Register("NativeInterface", "koKR", {
    ["name"] = "블리자드 UI",
    ["section.visibility"] = "네이티브 요소",
    ["section.layout"] = "인터페이스 레이아웃",
    ["section.enhancements"] = "인터페이스 향상",
    ["hide.status_tracking_bars"] = "Hide Experience와 평판 바",
    ["hide.micro_menu"] = "Micro 메뉴 숨기기",
    ["hide.bags_bar"] = "가방 바 자동 숨기기",
    ["hide.bags_bar.tooltip"] = "가방이 모두 닫혀 있으면 가방 바를 숨기고, 장착한 가방을 하나라도 열면 표시합니다.",
    ["hide.buff_collapse"] = "Buff Collapse 버튼 숨기기",
    ["hide.buff_collapse.tooltip"] = "네이티브 버프 붕괴/expand 버튼을 열고 모든 버프를 확장합니다.",
    ["manage.top_center_widget"] = "Top-Center 공지를 관리합니다",
    ["manage.top_center_widget.tooltip"] = "YUI Edit Mode에 기본 top-center notice container를 추가합니다.",
    ["manage.power_bar_widget"] = "Scenario Power Bar 관리",
    ["manage.power_bar_widget.tooltip"] = "기본 시나리오 및 이벤트 전원 바 컨테이너를 YUI Edit Mode에 추가하십시오.",
    ["tutorial.supertrack"] = "Suppress Quest Supertracking 튜토리얼",
    ["tutorial.supertrack.tooltip"] = "Acknowledge 만 quest-supertracking 튜토리얼. 이 옵션을 비활성화하면 이미 완료 된 튜토리얼을 복원하지 않습니다.",
    ["settings.native_interface.topCenterWidget.tooltip"] = "YUI Edit Mode에 기본 top-center notice container를 추가합니다.",
    ["settings.native_interface.powerBarWidget.tooltip"] = "기본 시나리오 및 이벤트 전원 바 컨테이너를 YUI Edit Mode에 추가하십시오.",
    ["settings.native_interface.managed_by_elvui"] = "이 요소는 이미 ElvUI에 의해 관리됩니다, 그래서 YUI는 소유권을 가지고하지 않습니다.",
    ["settings.native_interface.managed_by_ndui"] = "이 요소는 이미 NDui에 의해 관리됩니다, 그래서 YUI는 소유권을 가지고하지 않습니다.",
    ["settings.native_interface.managed_externally"] = "또 다른 addon은 이미이 요소의 위치를 소유, 그래서 YUI는 소유권을 가지고 있지 않습니다.",
    ["settings.native_interface.unavailable"] = "YUI는이 요소가 안전하게 이동할 수 있음을 확인 할 수 없습니다. 그래서 소유권은 사용할 수 없습니다.",
    ["layout.top_center_widget"] = "Top-Center 공지사항",
    ["layout.power_bar_widget"] = "Scenario 힘 막대기",
})
