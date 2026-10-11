local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhCN") then return end

YUI.Locale:Register("MasqueSupport", "zhCN", {
    ["feature.name"] = "Masque支持",
    ["feature.description"] = "为暴雪动作条和光环接入 Masque 皮肤，改动后需要重载界面。",

    ["masque.group.action_bars"] = "动作条",
    ["masque.group.player_auras"] = "玩家光环",
    ["masque.group.target_buffs"] = "目标增益",
    ["masque.group.target_debuffs"] = "目标减益",
    ["masque.group.unit_frame_buffs_debuffs"] = "单位框架增益/减益",

    ["settings.blizzard_action_bars.label"] = "暴雪原生动作条",
    ["settings.blizzard_action_bars.tooltip"] = "开启后，将接管原生动作条的 Masque 皮肤。对应分组：Blizzard > 动作条。",
    ["settings.blizzard_auras.label"] = "暴雪原生光环",
    ["settings.blizzard_auras.tooltip"] = "开启后，将接管原生 Buff/Debuff 的 Masque 皮肤。对应分组：Blizzard > 玩家光环 / 目标增益 / 目标减益；EQoL 单位框架光环对应 EnhanceQoL > 单位框架增益/减益。",
    ["settings.reload_note"] = "提示：勾选/取消勾选后，需要关闭设置并点击重载界面以生效；旧分组皮肤不会迁移，请在新的 Blizzard / EnhanceQoL 分组重新选择。",
})
