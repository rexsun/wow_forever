-- Generated from Docs/Products/YUI_YHUD/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("yhud", {
-- YUI-Notes-Record: halo-116|mainline|ddfaef78487e08a1539efc7e90b747a2fc083b5b4e5313285aa13c91487237ab
    {
        version = "halo-116",
        date = "2026-11-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复目标光环结束时监控可能报错的问题。",
            },
            enUS = {
                "Fixed possible monitor errors when a target aura expires.",
            },
        },
    },
-- YUI-Notes-Record: halo-116|forever|d923388196b3fecfc780a8cc6cb957c44a1825ba5ef65f65e022398177ea6d1e
    {
        version = "halo-116",
        date = "2026-11-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "补全无限服正义圣印 1–8 级监控，并保留已有的自定义图标和条目。",
                "修复目标光环结束时监控可能报错的问题。",
            },
            enUS = {
                "Added complete rank 1–8 Seal of Righteousness monitoring on Forever while preserving existing custom icons and entries.",
                "Fixed possible monitor errors when a target aura expires.",
            },
        },
    },
-- YUI-Notes-Record: halo-115|mainline|e35d071b93b9d1f81f9839b8cb87ec1f87929b61041a2c2d0562c02341efeb41
    {
        version = "halo-115",
        date = "2026-11-05",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复连击点重新显示时残留旧填充。",
            },
            enUS = {
                "Fixed stale combo-point fills when the display reappears.",
            },
        },
    },
-- YUI-Notes-Record: halo-115|forever|2e2c6ed14579e8526d4abbbcc6fb278980d427e3d962400252cdb64642e299c0
    {
        version = "halo-115",
        date = "2026-11-05",
        clients = { "Forever" },
        content = {
            zhCN = {
                "远程计时器新增射击停步提示。",
                "修复连击点重新显示时残留旧填充。",
            },
            enUS = {
                "Added a stop-moving cue to ranged swing timers.",
                "Fixed stale combo-point fills when the display reappears.",
            },
        },
    },
-- YUI-Notes-Record: halo-114|mainline|403fc150def430ce34c1279811da0ebcc42ffb77d1ec4b15ec640f019a9f1281
-- YUI-Notes-Record: halo-114|forever|ed19fac47f875daa2a6ecc9265d43f6a046b4943eaa42afca6882a5175117bf6
    {
        version = "halo-114",
        date = "2026-11-04",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "原生触发发光新增“不发光”选项，可全局或按监控设置。",
                "优化监控台与声音提醒性能，减少重复刷新。",
                "条形监控的原生默认发光仅围绕图标显示，随图标隐藏。",
                "修复资源设置首次打开报错、资源列表显示不全。",
                "离开资源分组编辑后，恢复当前角色的资源预览。",
                "修复字体设置中默认分组名称的语言显示。",
            },
            enUS = {
                "Added a No Glow option for native proc effects, globally or per monitor.",
                "Improved monitor and sound alert performance by reducing redundant updates.",
                "Default native proc glow on bar monitors now surrounds only the icon and hides with it.",
                "Fixed errors when first opening resource settings and incomplete resource lists.",
                "Resource previews now return to the current character after leaving resource group editing.",
                "Fixed localization of default group names in font settings.",
            },
        },
    },
-- YUI-Notes-Record: halo-113|mainline|7a595301b105b5abaf214d67743ce8bd2165dd2c6af40845f3033daa6c23f1a4
    {
        version = "halo-113",
        date = "2026-10-31",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增资源管理，可添加冷却、充能和光环等自定义资源，支持跨专精启停及形态复制。",
                "资源条支持竖向排列、同行等分和几何／原生资源点，新增分组阴影。",
                "新增菱形、棱光与墨影图标外观，支持 Masque 皮肤及斜向排列。",
                "驭龙术新增技能冷却显示样式与倒计时设置。",
                "平衡德鲁伊新增日蚀、月蚀资源预设。",
                "声音提醒列表支持跨类型与专精搜索。",
                "修复资源条倒计时、反向填充和设计拖动异常，改善 ElvUI 按压反馈兼容。",
            },
            enUS = {
                "Added resource management for custom cooldown, charge, and aura resources, with cross-specialization toggles and form copying.",
                "Added vertical resource bars, equal-width rows, geometric or native resource points, and group shadows.",
                "Added Diamond, Contour, and Shade icon appearances, Masque skin support, and diagonal layouts.",
                "Added Skyriding ability cooldown styles and countdown settings.",
                "Added Solar Eclipse and Lunar Eclipse resource presets for Balance Druids.",
                "Sound alert searches now span alert types and specializations.",
                "Fixed resource countdowns, reverse fills, and designer dragging; improved ElvUI press-feedback compatibility.",
            },
        },
    },
-- YUI-Notes-Record: halo-113|forever|900a9611b1109eded5caf3d1e77b20fffb591379fc2c1a5d7b485b2f2ba09109
    {
        version = "halo-113",
        date = "2026-10-31",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增资源管理，可添加冷却、充能和光环等自定义资源，支持跨专精启停及形态复制。",
                "资源条支持竖向排列、同行等分和几何／原生资源点，新增分组阴影。",
                "新增菱形、棱光与墨影图标外观，支持 Masque 皮肤及斜向排列。",
                "声音提醒列表支持跨类型与专精搜索。",
                "修复资源条倒计时、反向填充和设计拖动异常，改善 ElvUI 按压反馈兼容。",
            },
            enUS = {
                "Added resource management for custom cooldown, charge, and aura resources, with cross-specialization toggles and form copying.",
                "Added vertical resource bars, equal-width rows, geometric or native resource points, and group shadows.",
                "Added Diamond, Contour, and Shade icon appearances, Masque skin support, and diagonal layouts.",
                "Sound alert searches now span alert types and specializations.",
                "Fixed resource countdowns, reverse fills, and designer dragging; improved ElvUI press-feedback compatibility.",
            },
        },
    },
-- YUI-Notes-Record: halo-112|mainline|6cbafc441ebed26d69a7862e6b60c0de8dd224410cad2a86177605d4fe200e5c
-- YUI-Notes-Record: halo-112|forever|58326e70bf346cb926ecafb58ac6e8d89546accf0c034cb8630cb9c3b75bf371
    {
        version = "halo-112",
        date = "2026-10-26",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "进度条和资源条分组高度支持调整至 2–128。",
                "优化法术警报预览及布局占位提示。",
                "新建圆环分组默认关闭鼠标提示，保留已有设置。",
                "修复图腾类监控圆环与进度条的持续时间显示。",
            },
            enUS = {
                "Progress and resource group bar heights can now be adjusted from 2 to 128.",
                "Improved spell alert previews and layout placeholder hints.",
                "New ring groups now default to disabled tooltips, preserving existing settings.",
                "Fixed duration displays for totem-based monitor rings and bars.",
            },
        },
    },
-- YUI-Notes-Record: halo-111|mainline|cbf0d063cf1752d422eb5937676f52836fc8959d00b665f30f3d91fe2365bec1
-- YUI-Notes-Record: halo-111|forever|c616fb1e1e19bf026be8a4c3f28fdf11d8242cc778e0fe0d7c0d0f2244cdf870
    {
        version = "halo-111",
        date = "2026-10-23",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "监控图标按键支持药水与饰品，改善技能和宏的按键识别。",
                "修复切图后的技能就绪声音误报与监控图标恢复异常。",
                "修复增益监控倒计时和层数文字被遮挡的问题。",
                "修复位置修改保存后被覆盖，以及预览遮挡位置编辑界面的问题。",
                "修复多个单体共同加载时的配置导入与按键文字异常。",
            },
            enUS = {
                "Added potion and trinket keybind text to monitor icons and improved spell and macro binding detection.",
                "Fixed false ability-ready sound alerts and monitor icon recovery after zone transitions.",
                "Fixed obscured countdown and stack text on buff monitors.",
                "Fixed position changes being overwritten on save and previews overlapping the position editor.",
                "Fixed configuration import and keybind text issues when multiple standalone addons are loaded together.",
            },
        },
    },
-- YUI-Notes-Record: halo-110|mainline|f8a0e7470d18931babc41a27c8e6ac59292fddea4d3f1bb88414c8d1f3a66e6a
    {
        version = "halo-110",
        date = "2026-10-22",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增外部增益监控集合，便于添加队友提供的常用增益。",
                "新增层数条和充能条，支持分段、阈值颜色及充能恢复显示设置。",
                "支持跨组拖动，新增按行和按列布局。",
                "监控图标新增可选的按下反馈。",
                "新增15类事件声音提醒，并配套新增12条事件录音。",
                "新增251条可选标准语音。",
                "新增批量声音预设，快速添加提醒。",
                "声音提醒支持增益分类与跨分类搜索。",
                "统一字体设置，支持样式复制粘贴。",
                "辅助高亮改为按角色统一设置，默认关闭。",
                "修复监控台图标激活发光残留。",
                "修复监控台冷却结束后未按设置隐藏的问题。",
                "修复监控台引导施法被后续按键误判为中断的问题。",
            },
            enUS = {
                "Added a monitor collection for buffs received from other players.",
                "Added stack and charge bars with segment, threshold color, and recharge display settings.",
                "Added cross-group dragging and row/column layouts.",
                "Added optional press feedback for monitor icons.",
                "Added 15 event sound reminders, including 12 new event recordings.",
                "Added 251 selectable standard voice entries.",
                "Added batch sound presets to quickly add reminders.",
                "Added buff categories and cross-category search to sound reminders.",
                "Unified font settings with style copy and paste.",
                "Assisted highlighting now uses character-wide settings and is disabled by default.",
                "Fixed lingering activation glows on monitor icons.",
                "Fixed monitors failing to hide as configured when cooldowns finish.",
                "Fixed cast monitoring incorrectly treating channels as interrupted by subsequent key presses.",
            },
        },
    },
-- YUI-Notes-Record: halo-110|forever|157e9dca3eff54931f4f39d4690cd191488ef949a7f0f9201dac33ee14c2a56a
    {
        version = "halo-110",
        date = "2026-10-22",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增声音提醒（测试版），支持技能、光环与事件提醒。",
                "提供197条可选标准语音，其中137条为职业语音。",
                "新增15类事件声音提醒，并配套新增12条事件录音。",
                "新增批量声音预设，快速添加提醒。",
                "声音提醒支持增益分类与跨分类搜索。",
                "新增外部增益监控集合，便于添加队友提供的常用增益。",
                "新增层数条和充能条，支持分段、阈值颜色及充能恢复显示设置。",
                "支持跨组拖动，新增按行和按列布局。",
                "监控图标新增可选的按下反馈。",
                "统一字体设置，支持样式复制粘贴。",
                "补充圣印默认监控。",
                "修复监控台资源监控的连击点残留问题。",
                "修复监控台图标激活发光残留。",
                "修复监控台冷却结束后未按设置隐藏的问题。",
                "修复监控台引导施法被后续按键误判为中断的问题。",
            },
            enUS = {
                "Added sound reminders (Beta) for abilities, auras, and events.",
                "Provided 197 selectable standard voice entries, including 137 class voice entries.",
                "Added 15 event sound reminders, including 12 new event recordings.",
                "Added batch sound presets to quickly add reminders.",
                "Added buff categories and cross-category search to sound reminders.",
                "Added a monitor collection for buffs received from other players.",
                "Added stack and charge bars with segment, threshold color, and recharge display settings.",
                "Added cross-group dragging and row/column layouts.",
                "Added optional press feedback for monitor icons.",
                "Unified font settings with style copy and paste.",
                "Expanded default seal monitoring.",
                "Fixed lingering combo points in resource monitors.",
                "Fixed lingering activation glows on monitor icons.",
                "Fixed monitors failing to hide as configured when cooldowns finish.",
                "Fixed cast monitoring incorrectly treating channels as interrupted by subsequent key presses.",
            },
        },
    },
-- YUI-Notes-Record: halo-109|mainline|70993537f9f6b28b43995279f73b2f85a793dc83a9d224f043add368877d9eab
    {
        version = "halo-109",
        date = "2026-10-16",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增蓝色辅助提示。",
                "新增增益层数发光规则。",
                "发光外观支持保存、复用与复制粘贴。",
                "液态光泽支持真实层数显示及层数发光。",
                "新增噬灭变身和明志灵药预设，优化监控预览。",
                "施法条支持图标内外放置与四种计时格式。",
                "优化方案管理，新增独立的全局设置面板。",
                "声音提醒支持多语音包排序和标准语音补缺，优化特别语音选择与试听。",
                "修复资源条初始化与锚点定位问题。",
                "修复原生冷却窗口越界与显隐避让问题。",
                "圆环监控暂时关闭自定义发光，保留原有配置。",
            },
            enUS = {
                "Added blue assisted highlights.",
                "Added buff-stack glow rules.",
                "Added reusable glow appearance presets and copy/paste.",
                "Added live Liquid Radiance stack counts and stack-based glows.",
                "Added Devourer transformation and Brewmaster elixir presets, with improved monitor previews.",
                "Added internal/external cast-bar icons and four time formats.",
                "Improved profile management and added a separate global settings panel.",
                "Added voice pack ordering and standard-voice fallback, with improved special-voice selection and previews.",
                "Fixed resource initialization and anchoring.",
                "Fixed native cooldown window overflow and visibility-related layout conflicts.",
                "Temporarily disabled custom glows for ring monitors while preserving saved settings.",
            },
        },
    },
-- YUI-Notes-Record: halo-109|forever|0d2422ec8c12d7c36af22945945bc76eeef630076693a1ff562795bc268103f1
    {
        version = "halo-109",
        date = "2026-10-16",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增发光外观保存、复用与复制粘贴，优化编辑预览。",
                "施法条支持图标内外放置与四种计时格式。",
                "优化方案管理，新增独立的全局设置面板。",
                "修复资源条初始化与锚点定位问题。",
                "圆环监控暂时关闭自定义发光，保留原有配置。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added reusable glow appearance presets and copy/paste, with improved editing previews.",
                "Added internal/external cast-bar icons and four time formats.",
                "Improved profile management and added a separate global settings panel.",
                "Fixed resource initialization and anchoring.",
                "Temporarily disabled custom glows for ring monitors while preserving saved settings.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: halo-108|mainline|a48c6ddcaf4594b0cd0380a61ce590c5b761df63f56630c7c7ddec1ff99411fe
    {
        version = "halo-108",
        date = "2026-10-15",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复资源条可能报错并中断刷新的问题。",
                "修复旧配置升级、复制和导入时的个人方案保留与失败恢复问题。",
            },
            enUS = {
                "Fixed errors that could interrupt resource bar updates.",
                "Fixed personal configuration preservation and recovery during legacy upgrades, profile copying and imports.",
            },
        },
    },
-- YUI-Notes-Record: halo-108|forever|a656abfeb1f5e76ee3695c47224201cc2691e2ba309fcbbf6a9263bd5849ee20
    {
        version = "halo-108",
        date = "2026-10-15",
        clients = { "Forever" },
        content = {
            zhCN = {
                "修复旧配置升级、复制和导入时的个人方案保留与失败恢复问题。",
            },
            enUS = {
                "Fixed personal configuration preservation and recovery during legacy upgrades, profile copying and imports.",
            },
        },
    },
-- YUI-Notes-Record: halo-107|mainline|d6db2e9de496741c0040ad0857c4b2c3723e8c50d19e82e6d10eb0c05ae80e71
    {
        version = "halo-107",
        date = "2026-10-15",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增玩家生命条和施法条，支持独立分组、资源混排及文字样式设置。",
                "完善驭龙术的材质、边框、颜色与速度文字设置。",
                "导入预览更清楚地展示专精分配与默认方案的影响。",
                "修复配置导入与原生分类同步，完善失败提示与恢复。",
                "修复监控台及编辑面板的层级显示问题。",
            },
            enUS = {
                "Added player health and cast bars, with separate groups, mixed resource layouts and text styling.",
                "Expanded skyriding texture, border, color and speed text settings.",
                "Import previews now show specialization assignments and default configuration impact more clearly.",
                "Fixed configuration imports and native category synchronization, with clearer failure messages and recovery.",
                "Fixed monitor and editor panel layering.",
            },
        },
    },
-- YUI-Notes-Record: halo-107|forever|15c6299a83b777a048f0fff0d8f45ce6d6fc0379bc240d4e6e8a21c3a9611f89
    {
        version = "halo-107",
        date = "2026-10-15",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增玩家生命条和施法条，支持独立分组、资源混排及文字样式设置。",
                "导入预览更清楚地展示专精分配与默认方案的影响。",
                "修复纯图形配置与旧方案字符串的导入，完善失败提示与恢复。",
                "修复监控台及编辑面板的层级显示问题。",
            },
            enUS = {
                "Added player health and cast bars, with separate groups, mixed resource layouts and text styling.",
                "Import previews now show specialization assignments and default configuration impact more clearly.",
                "Fixed imports of graphics-only configurations and legacy configuration strings, with clearer failure messages and recovery.",
                "Fixed monitor and editor panel layering.",
            },
        },
    },
})
