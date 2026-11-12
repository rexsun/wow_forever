-- Generated from Docs/Products/YUI_YHUD/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("yhud", {
-- YUI-Notes-Record: halo-119|mainline|ba2763fa2e5cb215c0c433457fd5ab1ac39476f782660fb0b3087b8bc3004702
-- YUI-Notes-Record: halo-119|forever|03e8ffe81800c063af0b1a9fbf6a232d2a6dfeb86e8ecae759eae2ddc29e929b
    {
        version = "halo-119",
        date = "2026-11-12",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: halo-118|mainline|5fbcb22341877fc1e2a21ee9b2cdc222ec84217845edcb0a0a4fa44640c6c5b8
    {
        version = "halo-118",
        date = "2026-11-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "添加监控的入口改为“自身增益、目标减益、施法计时”。",
                "添加监控的选择面板会为长名称调整排列，避免文字重叠。",
                "修复首次登录时，部分已学技能监控不显示。",
                "修复计时条旁的图标套用皮肤后大小异常。",
                "修复切换形态后的监控遮挡顺序和发光异常。",
            },
            enUS = {
                "The monitor picker now shows Self Buff, Target Debuff, and Cast Timer.",
                "The monitor picker gives long labels more room to prevent overlaps.",
                "Fixed some learned-skill monitors not appearing after login.",
                "Fixed incorrect sizes for skinned icons next to bars.",
                "Fixed monitor stacking and glow issues after changing forms.",
            },
        },
    },
-- YUI-Notes-Record: halo-118|forever|ba732b7e54d46a007eb6dc7d2d50982e8a2905d10638b551a2804c69bfeb894a
    {
        version = "halo-118",
        date = "2026-11-11",
        clients = { "Forever" },
        content = {
            zhCN = {
                "添加监控的入口改为“自身增益、目标减益、施法计时”。",
                "添加监控的选择面板会为长名称调整排列，避免文字重叠。",
                "修复计时条旁的图标套用皮肤后大小异常。",
                "修复切换形态后的监控遮挡顺序和发光异常。",
            },
            enUS = {
                "The monitor picker now shows Self Buff, Target Debuff, and Cast Timer.",
                "The monitor picker gives long labels more room to prevent overlaps.",
                "Fixed incorrect sizes for skinned icons next to bars.",
                "Fixed monitor stacking and glow issues after changing forms.",
            },
        },
    },
-- YUI-Notes-Record: halo-117|mainline|9c7562bbfc3ba4af518cb2d5b55dd724b51e5904b7660cd8262e5aa225341a07
    {
        version = "halo-117",
        date = "2026-11-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: halo-117|forever|ec41c9ec9dff972a5694df5f8ea1d3841f767d4e04caadf9f3ec1d6ff24f5fee
    {
        version = "halo-117",
        date = "2026-11-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "圣印预设扩展至七类圣印的各等级，图标与剩余时间跟随当前圣印。",
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Expanded the Seals preset to all ranks of seven seal types, with icons and remaining time following the active seal.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
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
})
