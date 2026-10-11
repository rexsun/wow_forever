local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("koKR") then return end

YUI.Locale:Register("SocialEnhancement", "koKR", {
    ["feature.name"] = "소셜 기능 개선",
    ["feature.description"] = "Tab 대상 전환과 플레이어 메뉴의 선택 기능을 개선합니다.",
    ["settings.tab_cycle"] = "탭 / Shift+Tab을 사용하여 채팅 대상을 주기합니다",
    ["settings.tab_cycle.tooltip"] = "지원된 그룹, guild 및 입력 텍스트를 변경하지 않고 세계 채팅 대상을 통해 사이클.",
    ["settings.tab_cycle.ychat"] = "탭 대상 전환은 YChat에 의해 관리됩니다.",
    ["settings.right_click"] = "플레이어 오른쪽 클릭 메뉴를 강화합니다",
    ["settings.right_click.tooltip"] = "지원되는 플레이어 메뉴에 친구 및 guild-invite 작업을 추가하십시오.",
    ["settings.right_click.conflict"] = "다른 인터페이스 애드온이 이러한 메뉴를 관리하기 때문에 사용할 수 없음.",
    ["menu.add_friend"] = "친구 추가",
    ["menu.invite_guild"] = "Guild로 향합니다",
})
