-- Generated from Docs/Products/YUI_YActionBar/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("yactionbar", {
-- YUI-Notes-Record: yactionbar-120|mainline|2b78e9e0e1dbb8d10e801edd5d41a762087bd549e7d3dc51abeb19d334d789c9
    {
        version = "yactionbar-120",
        date = "2026-11-21",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增「主题外观」设置页。",
                "修复宠物动作条键位缩写被覆盖和文字裁切。",
                "修复初学姿态后未刷新、公共冷却时图标误变灰。",
                "修复换角色后动作条方案偶尔漏应用。",
            },
            enUS = {
                "Added a Theme & Appearance settings page.",
                "Fixed pet bar keybind abbreviations being overwritten and text clipping.",
                "Fixed stance buttons failing to refresh when first learned or dimming during the global cooldown.",
                "Fixed action bar profiles sometimes failing to apply after switching characters.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-120|forever|f46e4bf684dd56f40d8ce17381bde6dfbe528354f6ee67d303d019c96591d620
    {
        version = "yactionbar-120",
        date = "2026-11-21",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增骑士团队祝福管理条，支持按职业分配、查缺与补施，并调整了默认位置与外观。",
                "职业条扩展至 9 个职业，布局编辑可调整其他职业已单独摆放的工具条。",
                "法师支持造食造水、法力宝石与传送增强。",
                "圣骑士可设置常用祝福。",
                "猎人支持宠物技能菜单与拖放喂养。",
                "萨满支持图腾计时、护盾切换与武器附魔显示。",
                "术士支持恶魔召唤、治疗石与灵魂石工具。",
                "潜行者可查看主副手毒药库存与计时。",
                "牧师可用左右键分别施放单体与群体增益。",
                "德鲁伊支持野性印记、野性赐福与荆棘术。",
                "战士支持战斗怒吼与增益计时。",
                "新增「主题外观」设置页。",
                "修复宠物动作条键位缩写被覆盖和文字裁切。",
                "修复初学姿态后未刷新、公共冷却时图标误变灰。",
                "修复任务物品漏显、换角色后方案漏应用和旧方案职业条错位。",
            },
            enUS = {
                "Added a Paladin group blessing bar for assigning blessings by class, checking who needs them, and refreshing them, with an updated default position and appearance.",
                "Expanded class tools to all nine classes. Layout editing can also reposition detached toolbars for other classes.",
                "Mage: Improved food and water conjuring, mana gems, and teleport tools.",
                "Paladin: Set a preferred blessing.",
                "Hunter: Pet skills menu and drag-to-feed.",
                "Shaman: Totem timers, shield switching, and weapon imbue display.",
                "Warlock: Demon summons, Healthstones, and Soulstones.",
                "Rogue: Track main-hand and off-hand poisons, stock, and remaining time.",
                "Priest: Use left and right clicks for single-target and group buffs.",
                "Druid: Mark of the Wild, Gift of the Wild, and Thorns.",
                "Warrior: Battle Shout and its remaining duration.",
                "Added a Theme & Appearance settings page.",
                "Fixed pet bar keybind abbreviations being overwritten and text clipping.",
                "Fixed stance buttons failing to refresh when first learned or dimming during the global cooldown.",
                "Fixed missing quest items, profiles failing to apply after switching characters, and class bars moving out of place after importing older profiles.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-119|mainline|a58052a3318f749d2d1820babe4783cd81f1f928e741a1fd09ce691d32df2239
    {
        version = "yactionbar-119",
        date = "2026-11-14",
        clients = { "Retail" },
        content = {
            zhCN = {
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-119|forever|fdf0b12771bedb03b6d2a771db2105ef8288b0b469a02d2b68659843e53831cf
    {
        version = "yactionbar-119",
        date = "2026-11-14",
        clients = { "Forever" },
        content = {
            zhCN = {
                "修复法师智力与护甲增益图标在战斗中的彩色与灰色显示。",
                "修复营火限制图标在战斗中消失或移除后残留的问题。",
            },
            enUS = {
                "Fixed colored and grayscale displays of Mage Intellect and armor buff icons in combat.",
                "Fixed campfire-restriction icons disappearing in combat or lingering after removal.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-118|mainline|7a644f1dff492ea5df5b6674d93126401304c95d46cbd8539c6a786d9514769a
-- YUI-Notes-Record: yactionbar-118|forever|7627ed35dc7c0c204988e8894bdd61213303d6d25aa77bb541efa65420dfca89
    {
        version = "yactionbar-118",
        date = "2026-11-13",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "修复动作条图标偶尔消失或残留旧图标的问题。",
                "修复技能变化后宏名称和冷却显示未及时同步的问题。",
            },
            enUS = {
                "Fixed action bar icons occasionally disappearing or displaying an outdated image.",
                "Fixed macro names and cooldown displays failing to update when actions change.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-117|mainline|319992e04187267d2ad10cd9c480185c574ba79a7a72344c1d7a8cc54b2826d2
    {
        version = "yactionbar-117",
        date = "2026-11-13",
        clients = { "Retail" },
        content = {
            zhCN = {
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: yactionbar-117|forever|248beb3ab1742cc6801bb5fae40df299c54c7a9cc299af9683412da0e84ad4ec
    {
        version = "yactionbar-117",
        date = "2026-11-13",
        clients = { "Forever" },
        content = {
            zhCN = {
                "修复法师智力与护甲增益在战斗中的倒计时和缺失提示。",
                "适配新版 YUI 系列插件。",
            },
            enUS = {
                "Fixed combat countdowns and missing-buff alerts for Mage Intellect and armor buffs.",
                "Updated compatibility with newer YUI addons.",
            },
        },
    },
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
