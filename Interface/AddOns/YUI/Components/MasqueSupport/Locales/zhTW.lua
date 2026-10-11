local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhTW") then return end

YUI.Locale:Register("MasqueSupport", "zhTW", {
    ["feature.name"] = "Masque 支援",
    ["feature.description"] = "為暴雪動作列和光環接入 Masque 外觀，變更後需要重載介面。",

    ["masque.group.action_bars"] = "動作列",
    ["masque.group.player_auras"] = "玩家光環",
    ["masque.group.target_buffs"] = "目標增益",
    ["masque.group.target_debuffs"] = "目標減益",
    ["masque.group.unit_frame_buffs_debuffs"] = "單位框架增益/減益",

    ["settings.blizzard_action_bars.label"] = "暴雪原生動作列",
    ["settings.blizzard_action_bars.tooltip"] = "啟用後，會接管原生動作列的 Masque 外觀。對應分組：Blizzard > 動作列。",
    ["settings.blizzard_auras.label"] = "暴雪原生光環",
    ["settings.blizzard_auras.tooltip"] = "啟用後，會接管原生 Buff/Debuff 的 Masque 外觀。對應分組：Blizzard > 玩家光環 / 目標增益 / 目標減益；EQoL 單位框架光環對應 EnhanceQoL > 單位框架增益/減益。",
    ["settings.reload_note"] = "提示：勾選/取消勾選後，需要關閉設定並點擊重載介面才會生效；舊分組外觀不會遷移，請在新的 Blizzard / EnhanceQoL 分組重新選擇。",
})
