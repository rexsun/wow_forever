-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v355|forever|e274d85989cea7aa257b176a3bc59407d1e8197ca09049666d158182c31f4119
    {
        version = "v355",
        date = "2026-11-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增系统错误／信息提示的位置编辑，可预览、移动和重置，默认关闭。",
                "自动修理新增等级限制，默认从 10 级开始，支持调整或关闭。",
                "圣印预设扩展至七类圣印的各等级，图标与剩余时间跟随当前圣印。",
                "优化背包附魔助手入口的兼容性。",
                "优化好友添加流程，并停用公会邀请增强。",
                "聊天关键词过滤不再区分英文字母大小写。",
                "修复新版中文技能学习提示的识别异常。",
            },
            enUS = {
                "Added position editing for system error and information messages, with preview, movement, and reset controls; disabled by default.",
                "Added an automatic repair level limit, starting at level 10 by default, with options to adjust or disable it.",
                "Expanded the Seals preset to all ranks of seven seal types, with icons and remaining time following the active seal.",
                "Improved compatibility for the bag disenchanting assistant button.",
                "Improved the add-friend flow and disabled enhanced guild invitations.",
                "Chat keyword filtering now ignores English letter case.",
                "Fixed recognition of updated Chinese skill-training tooltip headings.",
            },
        },
    },
-- YUI-Notes-Record: v354|forever|fc2a704eab7aaa2f2c66e6ee93a65b2d3998f7fc73c2d2f83dc7f6d61cf7274d
    {
        version = "v354",
        date = "2026-11-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增 RXP 龙卷风图钉过滤，加载 RXPGuides 时默认开启。",
                "补全无限服正义圣印 1–8 级监控，并保留已有的自定义图标和条目。",
                "优化新版 EllesmereUI 自定义任务追踪器和自动交接入口的兼容性。",
                "优化无限服训练提示，识别任务奖励技能并显示超出十项的技能数量。",
                "修复目标光环结束时监控可能报错的问题。",
            },
            enUS = {
                "Added an RXP tornado pin filter, enabled by default when RXPGuides is loaded.",
                "Added complete rank 1–8 Seal of Righteousness monitoring on Forever while preserving existing custom icons and entries.",
                "Improved compatibility with the newer EllesmereUI custom quest tracker and auto-handoff controls.",
                "Improved Forever training tooltips to recognize quest-reward spells and indicate how many additional skills are hidden beyond ten.",
                "Fixed possible monitor errors when a target aura expires.",
            },
        },
    },
-- YUI-Notes-Record: v353|forever|6e166a170320ff29361f3c9ca62903b5b93a1649e7795ee243a6398a5aacfdcf
    {
        version = "v353",
        date = "2026-11-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "优化默认聊天屏蔽词，并保留自定义过滤配置。",
                "修复任务分组折叠及 EllesmereUI 解锁模式下的任务追踪滚动异常。",
                "修复动作条使用状态黑块与按压短闪。",
            },
            enUS = {
                "Improved the default chat-blocking word list and preserved custom filter settings.",
                "Fixed quest tracker scrolling when quest groups are collapsed or EllesmereUI unlock mode is active.",
                "Fixed dark blocks on the active-action indicator and brief dark flashes on key presses.",
            },
        },
    },
-- YUI-Notes-Record: v352|forever|4430f2fc89240cf888e5d5c5492da0b5e5e5a8dd616705919832cc575531bdcf
    {
        version = "v352",
        date = "2026-11-05",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增聊天关键词过滤。",
                "远程计时器新增射击停步提示。",
                "优化任务路线收起兼容性。",
                "修复连击点重新显示时残留旧填充。",
            },
            enUS = {
                "Added chat keyword filtering.",
                "Added a stop-moving cue to ranged swing timers.",
                "Improved compatibility for quest guide collapsing.",
                "Fixed stale combo-point fills when the display reappears.",
            },
        },
    },
-- YUI-Notes-Record: v351|forever|7c0c75ff7393ad33404657273c73a4490aaefba1062501fc064bbdbe6f1f9799
    {
        version = "v351",
        date = "2026-11-04",
        clients = { "Forever" },
        content = {
            zhCN = {
                "监控台原生触发发光新增“不发光”选项。",
                "条形监控的原生默认发光仅围绕图标显示。",
                "优化监控台、动作条和声音提醒性能，减少重复刷新。",
                "修复资源设置首次打开报错、资源列表显示不全。",
                "离开资源分组编辑后，恢复当前角色的资源预览。",
                "插件助手支持分别勾选插件，并提示依赖异常。",
                "修复首次导入动作条配置失败及延迟容限刷新干扰。",
            },
            enUS = {
                "Added a No Glow option for native proc effects in monitors.",
                "Default native proc glow on bar monitors now surrounds only the icon.",
                "Improved monitor, action bar, and sound alert performance by reducing redundant updates.",
                "Fixed errors when first opening resource settings and incomplete resource lists.",
                "Resource previews now return to the current character after leaving resource group editing.",
                "Addon Assistant now toggles each addon separately and warns about dependency issues.",
                "Fixed initial action bar import failures and interference from latency-tolerance updates.",
            },
        },
    },
-- YUI-Notes-Record: v350|forever|a8d065694369b3b734535683c3414217b763bd04bd29e0c578ad9dde482224b0
    {
        version = "v350",
        date = "2026-10-31",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增资源管理，支持自定义资源条、竖向排列、同行等分及几何／原生资源点。",
                "监控台和动作条新增菱形、棱光与墨影外观，支持 Masque 皮肤。",
                "新增插件助手独立窗口与游戏菜单入口，支持按场景和专精管理插件方案。",
                "聊天条支持独立调整文字字号，并同步调整鼠标悬停区域。",
                "声音提醒列表支持跨类型与专精搜索。",
                "修复资源条刷新与设计拖动异常、宠物技能状态显示及自动修理启停问题。",
            },
            enUS = {
                "Added resource management with custom resource bars, vertical layouts, equal-width rows, and geometric or native resource points.",
                "Added Diamond, Contour, and Shade appearances for monitors and action bars, with Masque skin support.",
                "Added a dedicated Addon Assistant window and game menu entry, with addon profiles by activity and specialization.",
                "Chat bar text now has an independent font size, with matching mouseover areas.",
                "Sound alert searches now span alert types and specializations.",
                "Fixed resource updates and designer dragging, pet ability status displays, and automatic repair activation.",
            },
        },
    },
-- YUI-Notes-Record: v349|forever|830bd34b1b34efe4516763ded7eacf38db2de60b39569480cc0f6609c253ee24
    {
        version = "v349",
        date = "2026-10-26",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增勾选收件、只收金币和批量删除空信。",
                "新增邮件收发记录。",
                "发件联系人支持搜索和最近寄送快捷收藏。",
                "优化侧栏布局及其他邮件插件的兼容处理。",
                "新增猎人守护条，支持激活效果、顺序调整及未学技能提示。",
                "新增宠物技能折叠菜单，支持拖入食物喂养。",
                "新增宠物快乐状态与食物提示。",
                "新增萨满图腾组合条，支持组合切换和图腾选择。",
                "职业动作条支持布局、展开方向与键位设置。",
                "法师传送菜单新增未学技能、学习等级和训练地点提示。",
                "法师传送菜单新增传送材料数量显示。",
                "好友通知框支持单独移动并保存位置。",
                "宠物动作条新增隐藏空槽选项。",
                "原生界面新增背包栏控制开关，可关闭接管并保留显示模式。",
                "监控进度条和资源条高度支持调整至 2–128。",
                "优化法术警报预览及布局占位提示。",
                "新建圆环分组默认关闭鼠标提示，保留已有设置。",
                "优化音频同步，限制异常频繁重启并保留开关状态。",
                "战斗中的地图标记刷新延至脱战后执行。",
                "修复邮件联系人完整姓名与服务器信息处理。",
                "修复图腾类监控圆环与进度条的持续时间显示。",
                "修复魔杖恢复期间动作条图标异常变灰的问题。",
                "修复窗口拖动条被手柄导航扫描时引发的污染问题。",
                "修复背包栏隐藏可能引发的战斗中 ESC 报错。",
            },
            enUS = {
                "Added selected-mail collection, gold-only collection, and bulk empty-mail deletion.",
                "Added mail history for sent and received messages.",
                "Added contact search and quick favorites for recent recipients.",
                "Improved sidebar layout and compatibility with other mail addons.",
                "Added a hunter aspect bar with activation effects, reordering, and unlearned-spell hints.",
                "Added a collapsible pet utility menu with drag-to-feed support.",
                "Added pet happiness indicators and food tooltips.",
                "Added a shaman totem bar with set switching and totem selection.",
                "Added layout, flyout direction, and keybind settings for class action bars.",
                "Mage teleport menus now show unlearned spells, learning levels, and trainer hints.",
                "Mage teleport menus now show reagent counts.",
                "Friend notifications can now be moved independently with their position saved.",
                "Added an option to hide empty pet action bar slots.",
                "Added a bag bar control toggle that releases control while retaining the selected display mode.",
                "Monitor progress and resource bar heights can now be adjusted from 2 to 128.",
                "Improved spell alert previews and layout placeholder hints.",
                "New ring groups now default to disabled tooltips, preserving existing settings.",
                "Improved audio synchronization to limit excessive restarts while preserving the toggle state.",
                "Map marker refreshes requested during combat now wait until combat ends.",
                "Fixed full-name and realm information handling for mail contacts.",
                "Fixed duration displays for totem-based monitor rings and bars.",
                "Fixed incorrect action icon dimming during wand recovery.",
                "Fixed taint caused by gamepad navigation scanning window drag handles.",
                "Fixed potential ESC errors in combat caused by bag bar hiding.",
            },
        },
    },
-- YUI-Notes-Record: v348|forever|260c33c1fbeee03d95e546c77a5daead2b4ab3987054b1b0cc5294a090a92500
    {
        version = "v348",
        date = "2026-10-23",
        clients = { "Forever" },
        content = {
            zhCN = {
                "任务追踪新增自动接交任务开关，可统一关闭已加载插件的自动接交。",
                "Polestar 路线支持进入副本自动收起，离开后恢复。",
                "监控图标按键支持药水与饰品，改善技能和宏的按键识别。",
                "游戏菜单新增头像插件设置入口。",
                "修复切图后的技能就绪声音误报与监控图标恢复异常。",
                "修复增益监控倒计时和层数文字被遮挡的问题。",
            },
            enUS = {
                "Added a quest tracker toggle that can disable quest automation across loaded addons.",
                "Polestar guides now collapse automatically on entering an instance and restore on leaving.",
                "Added potion and trinket keybind text to monitor icons and improved spell and macro binding detection.",
                "Added a portrait addon settings shortcut to the game menu.",
                "Fixed false ability-ready sound alerts and monitor icon recovery after zone transitions.",
                "Fixed obscured countdown and stack text on buff monitors.",
            },
        },
    },
-- YUI-Notes-Record: v347|forever|6d23151395b489f7eac8b0611ad3999553f63cae5fe27ab2e1d980595c0834ff
    {
        version = "v347",
        date = "2026-10-22",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增 Bagnon 背包附魔助手入口，可独立关闭。",
                "新增 Polestar 任务路线收起，支持调整折叠标签尺寸。",
                "补充莫高雷与泽风岛双向飞艇标记及离岛阵营提示。",
                "修复旧配置导入报错，以及导入失败后的延迟容限恢复异常。",
            },
            enUS = {
                "Added an Enchanting Assistant entry to Bagnon bags with a separate toggle.",
                "Added collapsible Polestar quest guides with adjustable collapsed-label size.",
                "Added zeppelin markers between Mulgore and Zephras Isle, with faction departure hints.",
                "Fixed errors when importing older configurations and incorrect lag tolerance restoration after failed imports.",
            },
        },
    },
-- YUI-Notes-Record: v346|forever|502ca5e07063bef6ad4d533d40c25ce3c4ddd57f8fb4cad185b936da68bc7d6e
    {
        version = "v346",
        date = "2026-10-22",
        clients = { "Forever" },
        content = {
            zhCN = {
                "修复监控台位置修改在保存时被覆盖，以及预览遮挡位置编辑界面的问题。",
                "修复界面美化阴影在部分窗口触发报错的问题。",
            },
            enUS = {
                "Fixed monitor position edits being overwritten on save and previews overlapping the position editor.",
                "Fixed errors caused by window shadows in UI enhancements.",
            },
        },
    },
})
