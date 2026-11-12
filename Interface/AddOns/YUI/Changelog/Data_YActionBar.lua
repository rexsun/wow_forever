-- Generated from Docs/Products/YUI_YActionBar/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("yactionbar", {
-- YUI-Notes-Record: yactionbar-116|mainline|08ac3bcbcd4968791edded8a0c9e6a8f9f4dc6d819e30919ad971d125fa690a1
    {
        version = "yactionbar-116",
        date = "2026-11-12",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复特殊动作条分组中，已隐藏按钮仍占用空间。",
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Fixed hidden buttons still taking up space in special action-bar groups.",
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-116|forever|5044dd4de9ff1e3cffbc1e2603080e9de7eed17ffda5d93fd3fbed8be8b8106b
    {
        version = "yactionbar-116",
        date = "2026-11-12",
        clients = { "Forever" },
        content = {
            zhCN = {
                "营火工具新增睡袋，可查看增益层数与剩余时间。",
                "修复德鲁伊重复变形后，动作条翻页与按键可能不同步。",
                "修复法师智力与护甲增益计时在战斗中消失或误报缺失。",
                "修复营火工具首次显示时冷却未及时更新。",
                "修复特殊动作条分组中，已隐藏按钮仍占用空间。",
            },
            enUS = {
                "Added a sleeping bag to camp tools, with buff stacks and remaining time.",
                "Fixed action-bar pages and keybindings sometimes becoming unsynchronized after repeated Druid shapeshifts.",
                "Fixed Mage Intellect and armor buff timers disappearing or incorrectly reporting missing buffs in combat.",
                "Fixed camp-tool cooldowns not updating promptly when first shown.",
                "Fixed hidden buttons still taking up space in special action-bar groups.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-115|mainline|d14833809ef49b55e3423b600d88c391e2f0392648716753304e026fe887b462
    {
        version = "yactionbar-115",
        date = "2026-11-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复姿态按钮在公共冷却时错误变灰。",
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Fixed stance icons turning gray during the global cooldown.",
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-115|forever|798bcad2d2b2614b873acb5a63f3c3ab87ce56cc261e6cf43f1ea98b8693ccf5
    {
        version = "yactionbar-115",
        date = "2026-11-11",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增法师卷轴、智力和护甲工具，缺少增益时可发光提醒。",
                "法师、猎人、萨满职业条默认共用布局，也可按职业分别配置。",
                "任务物品条新增营火工具，显示休息计时、营地设施和收益提示。",
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Added Mage scroll, Intellect, and armor tools with missing-buff glow reminders.",
                "Mage, Hunter, and Shaman toolbars share a layout, with per-class options.",
                "Added camp tools showing rest timers, facilities, and benefits on the quest-item bar.",
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-114|mainline|214127418d67be0ffd7284716b66be56da6374b2d8eb38e20e7f05617d24f7be
-- YUI-Notes-Record: yactionbar-114|forever|f2b13e3ace9722d0ba54fc7cdbe43b17c855bd575475f481e7d863f07919acd2
    {
        version = "yactionbar-114",
        date = "2026-11-09",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "修复动作条使用状态黑块与按压短闪。",
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Fixed dark blocks on the active-action indicator and brief dark flashes on key presses.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-113|mainline|d6d44746206c8a2c2a1890906363148ca1dc4a5a258a978d0108ac8c9e6506e2
-- YUI-Notes-Record: yactionbar-113|forever|11c4aadc0e4c6661ea69bbfecdc42f8c89ac4e08ac14ee79ea8adf1185346f58
    {
        version = "yactionbar-113",
        date = "2026-11-05",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-112|mainline|4f46172439532efc3d19b4bdc9dcdbd8a28c3ce2f120255a565a0566bb3fa00e
-- YUI-Notes-Record: yactionbar-112|forever|07ce526f99485677549a3009f8fde7eabc814088c2e91ad1f7332b0d605f7d9f
    {
        version = "yactionbar-112",
        date = "2026-11-04",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "优化动作条性能，减少形态切换时的重复处理。",
                "修复首次导入动作条配置可能失败的问题。",
            },
            enUS = {
                "Improved action bar performance by reducing redundant work when switching forms.",
                "Fixed action bar configuration imports potentially failing on the first attempt.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-111|mainline|b7f045ca829f030ce3cf6351a2d9168056248882d312a8a74a94eb149b37a3c5
-- YUI-Notes-Record: yactionbar-111|forever|0f3b2f1a20a833f6984860c6fcbc968a0f588661259155b272c0eba5f99e0b0d
    {
        version = "yactionbar-111",
        date = "2026-10-31",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "新增统一图标皮肤选择，支持菱形、棱光、墨影及 Masque 外观。",
                "完善异形按钮的冷却、发光与自动施法效果，修复宏名显示层级。",
                "修复宠物技能冷却结束后的变灰残留及自动施法状态显示。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added unified icon skin selection with Diamond, Contour, Shade, and Masque appearances.",
                "Improved cooldown, glow, and autocast effects for shaped buttons; fixed macro name layering.",
                "Fixed lingering desaturation after pet ability cooldowns and incorrect autocast status displays.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-110|mainline|cc0474a348b53f3fc7880c72d4c85d294a3f4623c99d1662c8960da7be9c6a6e
    {
        version = "yactionbar-110",
        date = "2026-10-26",
        clients = { "Retail" },
        content = {
            zhCN = {
                "宠物动作条新增隐藏空槽选项。",
                "修复宠物按钮选中效果与圆角、圆形外观不一致的问题。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added an option to hide empty pet action bar slots.",
                "Fixed pet button selection highlights with rounded and circular icon shapes.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-110|forever|26e765bfe2313a53e956cbf3c2c43702fb612fd8efe7062b2e2bd420f793f742
    {
        version = "yactionbar-110",
        date = "2026-10-26",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增猎人守护条，支持激活效果、顺序调整及未学技能提示。",
                "新增宠物技能折叠菜单，支持拖入食物喂养。",
                "新增宠物快乐状态与食物提示。",
                "新增萨满图腾组合条，支持组合切换和图腾选择。",
                "职业动作条支持布局、展开方向与键位设置。",
                "宠物动作条新增隐藏空槽选项。",
                "修复宠物按钮选中效果与圆角、圆形外观不一致的问题。",
                "修复魔杖恢复期间动作条图标异常变灰的问题。",
            },
            enUS = {
                "Added a hunter aspect bar with activation effects, reordering, and unlearned-spell hints.",
                "Added a collapsible pet utility menu with drag-to-feed support.",
                "Added pet happiness indicators and food tooltips.",
                "Added a shaman totem bar with set switching and totem selection.",
                "Added layout, flyout direction, and keybind settings for class action bars.",
                "Added an option to hide empty pet action bar slots.",
                "Fixed pet button selection highlights with rounded and circular icon shapes.",
                "Fixed incorrect action icon dimming during wand recovery.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-109|mainline|7b993111ad6aa6045fb73de46bc265fb824c87b7cc3ccd4aa9b0e04e769d7fb0
-- YUI-Notes-Record: yactionbar-109|forever|d1128398769c624ddb2ebbd08a1ad2c0a39bb4587d0c58646fc2171b8542fbb7
    {
        version = "yactionbar-109",
        date = "2026-10-23",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "修复多个单体共同加载时的配置导入异常。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Fixed configuration import issues when multiple standalone addons are loaded together.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-108|mainline|78fcb1d2c54cb0e331489430e9e2aecd46ce4920c71f7a60e2f50512f3aa06a0
-- YUI-Notes-Record: yactionbar-108|forever|00a5353bede942d763d9ad0230a74ac3553f04be42165003e1918d12d20985da
    {
        version = "yactionbar-108",
        date = "2026-10-22",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "支持按专精设置隐身、姿态和形态翻页。",
                "充能转圈、边缘和倒计时可分别控制。",
                "统一字体设置，支持样式复制粘贴，并扩大文字偏移范围。",
                "新增使用中状态显示选项。",
                "优化设置项的悬停预览。",
            },
            enUS = {
                "Added per-specialization paging for stealth, stances, and forms.",
                "Added separate controls for charge swipe, edge, and countdown displays.",
                "Unified font settings with style copy and paste, and expanded text offset ranges.",
                "Added an option for displaying active-use states.",
                "Improved hover previews in settings.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-107|mainline|d0a32171634e301b13827db66cd469db0a3ddc87c6d4fa8087049039aad262d0
    {
        version = "yactionbar-107",
        date = "2026-10-16",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增蓝色辅助提示，适配按钮形状，并可与技能触发发光同时显示。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added blue assisted highlights that match button shapes and can appear alongside spell proc glows.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-107|forever|78d6e2b2f36c024f383b7e67804ce3f73aba534970a4d803d59611537cfce9ac
    {
        version = "yactionbar-107",
        date = "2026-10-16",
        clients = { "Forever" },
        content = {
            zhCN = {
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-101|wrath|042d100898b54863506af8fdca6054cf92e8f13e7932d1cb73290690a9d38df8
    {
        version = "yactionbar-101",
        date = "2026-10-06",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "新增按钮形状阴影与背景颜色设置。",
                "预览显示实际动作槽，修复切换按钮形状后的尺寸问题。",
                "修复姿态冷却显示及冷却结束后的灰色残留。",
                "滚轮快捷键缩写统一为 MU、MD。",
                "新增跟随客户端语言的游戏内日志入口，更新插件图标并优化设置导航对齐。",
            },
            enUS = {
                "Added shape-matched button shadows and configurable background colors.",
                "Previews now show actual action slots; fixed sizing when switching button shapes.",
                "Fixed stance cooldown display and gray icons after cooldowns ended.",
                "Shortened mouse wheel binding labels to MU and MD.",
                "Added an in-game release notes entry that follows the client language; updated addon icons and settings navigation alignment.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-100|wrath|b178bb0e631b05475313c146b39e3c14d94c9401e5c105ed0dabfbb0ce3f68e0
    {
        version = "yactionbar-100",
        date = "2026-10-05",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "完善通用设置按钮、下拉选项与字体显示。",
            },
            enUS = {
                "Improved shared settings buttons, dropdowns and font rendering.",
            },
        },
    },
})
