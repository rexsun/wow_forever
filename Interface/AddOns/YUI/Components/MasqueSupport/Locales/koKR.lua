local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("koKR") then return end

YUI.Locale:Register("MasqueSupport", "koKR", {
    ["feature.name"] = "Masque 지원",
    ["feature.description"] = "블리자드 행동 단축바와 오라에 Masque 스킨을 적용합니다.",
    ["masque.group.action_bars"] = "행동 단축바",
    ["masque.group.player_auras"] = "플레이어 Auras",
    ["masque.group.target_buffs"] = "대상 버프",
    ["masque.group.target_debuffs"] = "대상 Debuffs",
    ["masque.group.unit_frame_buffs_debuffs"] = "단위 프레임 Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard 활동 막대기",
    ["settings.blizzard_action_bars.tooltip"] = "Blizzard 액션 바에 대한 Enable Masque skinning. 그룹 : Blizzard > 액션 바.",
    ["settings.blizzard_auras.label"] = "블리자드 아우라",
    ["settings.blizzard_auras.tooltip"] = "Blizzard buffs/debuffs에 대한 Enable Masque skinning. 그룹 : Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL 단위 프레임 auras 사용 EnhanceQoL > 단위 프레임 Buffs/Debuffs.",
    ["settings.reload_note"] = "팁: 검사 또는 확인 후, 닫기 설정 및 변경에 대한 UI를 다시로드 효과; 이전 그룹에서 스킨은 마이그레이션되지 않습니다, 그래서 새로운 Blizzard / EnhanceQoL 그룹 아래에 그들을 다시 선택.",
})
