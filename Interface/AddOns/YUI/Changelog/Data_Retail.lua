-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v359|mainline|bc7a896bfc5bf783e7db2d6841830e314bda051d3b63c2c3955529060eb1abe3
    {
        version = "v359",
        date = "2026-11-13",
        clients = { "Retail" },
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
-- YUI-Notes-Record: v358|mainline|e336065ff1ca9f08ce6a9c5464a3b4a594adbbade2e536785e83d272fc14af86
    {
        version = "v358",
        date = "2026-11-13",
        clients = { "Retail" },
        content = {
            zhCN = {
                "Halo 光环监控支持按可读取的层数匹配发光规则。",
                "修复 Halo 发光规则取色时选择器意外关闭。",
                "修复插件助手原生样式的标题装饰被裁剪。",
            },
            enUS = {
                "Halo aura monitors now match glow rules against readable stack counts.",
                "Fixed Halo's color picker closing unexpectedly while editing glow rules.",
                "Fixed clipped title decorations in Addon Assistant's native style.",
            },
        },
    },
-- YUI-Notes-Record: v357|mainline|1ba3518e62846ead56c8d7945b5c641a6f39779634268de9f0814590b9b6ebc9
    {
        version = "v357",
        date = "2026-11-12",
        clients = { "Retail" },
        content = {
            zhCN = {
                "安装向导完善插件方案检查和不可用提示。",
                "优化购物助手原生边框和标题按钮位置。",
                "优化插件助手与其他插件管理器的共存，避免重复自动切换方案。",
                "修复头像方案自动匹配后，重载可能未保留的问题。",
                "修复特殊动作条分组中，已隐藏按钮仍占用空间。",
            },
            enUS = {
                "Improved addon-profile checks and unavailable-profile messages in the setup wizard.",
                "Improved Auction Helper's native borders and header button placement.",
                "Prevented competing addon managers from automatically switching profiles at the same time.",
                "Fixed automatically matched portrait profiles sometimes not persisting after a reload.",
                "Fixed hidden buttons still taking up space in special action-bar groups.",
            },
        },
    },
-- YUI-Notes-Record: v356|mainline|a5face94b6d35af737046cc5357b1ddb989166d3f918d7e38b30b909295b91c4
    {
        version = "v356",
        date = "2026-11-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增内置报错记录，支持历史查看和完整复制。",
                "Orbit 位面编号可调整间距，并按编号显示不同颜色。",
                "修复切换小区域时，位面编号反复变为“待识别”。",
                "Halo 添加监控的入口改为“自身增益、目标减益、施法计时”。",
                "修复 Halo 首次登录时，部分已学技能监控不显示。",
                "修复 Halo 计时条图标大小和切换形态后的监控发光异常。",
                "修复邮件助手收件记录核对异常，并保存历史记录中的职业配色。",
                "修复小队与宠物框架左右侧不同步。",
                "修复聊天窗口鼠标移出后不再渐隐。",
                "修复 Orbit 时钟隐藏后，鼠标移入仍不显示。",
                "修复动作条姿态按钮在公共冷却时错误变灰。",
            },
            enUS = {
                "Added built-in error logs with history and full-report copying.",
                "Orbit shard IDs now support label spacing and ID-based colors.",
                "Fixed shard IDs repeatedly becoming unknown when moving between subzones.",
                "Halo's monitor picker now shows Self Buff, Target Debuff, and Cast Timer.",
                "Fixed some Halo learned-skill monitors not appearing after login.",
                "Fixed Halo bar-icon sizes and monitor glow issues after changing forms.",
                "Fixed Mail Assistant receipt checks and preserved class colors in history.",
                "Fixed party pet frames appearing on the wrong side.",
                "Fixed chat windows not fading after the mouse leaves.",
                "Fixed hidden Orbit clocks not reappearing on hover.",
                "Fixed action-bar stance icons turning gray during the global cooldown.",
            },
        },
    },
-- YUI-Notes-Record: v355|mainline|5671b06e0550424e2cb08fbef277f87139f453a090bea4c7a248ae5e3dc3b160
    {
        version = "v355",
        date = "2026-11-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "自动修理新增等级限制，默认从 10 级开始，支持调整或关闭。",
                "聊天关键词过滤不再区分英文字母大小写。",
            },
            enUS = {
                "Added an automatic repair level limit, starting at level 10 by default, with options to adjust or disable it.",
                "Chat keyword filtering now ignores English letter case.",
            },
        },
    },
-- YUI-Notes-Record: v354|mainline|e5a5e59c2f43ef8e0f2627cf51bf710e0ea23ab374f117043f1fc25113ab9551
    {
        version = "v354",
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
-- YUI-Notes-Record: v353|mainline|20384615d0a8c59fdc84a2f816806f6685c059893ad678e8e0969b5a7e7e12a6
    {
        version = "v353",
        date = "2026-11-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "优化默认聊天屏蔽词，并保留自定义过滤配置。",
                "修复动作条使用状态黑块与按压短闪。",
            },
            enUS = {
                "Improved the default chat-blocking word list and preserved custom filter settings.",
                "Fixed dark blocks on the active-action indicator and brief dark flashes on key presses.",
            },
        },
    },
-- YUI-Notes-Record: v352|mainline|ef71ca70ca3fdce3ae1d12524eb2d63e67754b5b925e3052dc57d877c65415c3
    {
        version = "v352",
        date = "2026-11-05",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增聊天关键词过滤。",
                "优化任务路线收起兼容性。",
                "修复连击点重新显示时残留旧填充。",
            },
            enUS = {
                "Added chat keyword filtering.",
                "Improved compatibility for quest guide collapsing.",
                "Fixed stale combo-point fills when the display reappears.",
            },
        },
    },
-- YUI-Notes-Record: v351|mainline|efc63523a06f6db692adac8a61d8c9579eec5126e713e9e3b573835a4d74dbe2
    {
        version = "v351",
        date = "2026-11-04",
        clients = { "Retail" },
        content = {
            zhCN = {
                "监控台原生触发发光新增“不发光”选项。",
                "条形监控的原生默认发光仅围绕图标显示。",
                "优化监控台、动作条和声音提醒性能，减少重复刷新。",
                "修复资源设置首次打开报错、资源列表显示不全。",
                "离开资源分组编辑后，恢复当前角色的资源预览。",
                "插件助手支持分别勾选插件，并提示依赖异常。",
                "修复首次导入动作条配置失败及延迟容限刷新干扰。",
                "修复过场动画后小地图偏移、遮挡鼠标操作。",
            },
            enUS = {
                "Added a No Glow option for native proc effects in monitors.",
                "Default native proc glow on bar monitors now surrounds only the icon.",
                "Improved monitor, action bar, and sound alert performance by reducing redundant updates.",
                "Fixed errors when first opening resource settings and incomplete resource lists.",
                "Resource previews now return to the current character after leaving resource group editing.",
                "Addon Assistant now toggles each addon separately and warns about dependency issues.",
                "Fixed initial action bar import failures and interference from latency-tolerance updates.",
                "Fixed minimap displacement and blocked mouse interactions after cinematics.",
            },
        },
    },
-- YUI-Notes-Record: v350|mainline|bae1adb1e99379e513613cbdf40844d19f3d50ce9b6ffd2d40049d7a9683a370
    {
        version = "v350",
        date = "2026-10-31",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增资源管理，支持自定义资源条、竖向排列、同行等分及几何／原生资源点。",
                "监控台和动作条新增菱形、棱光与墨影外观，支持 Masque 皮肤。",
                "新增插件助手独立窗口与游戏菜单入口，支持按场景和专精管理插件方案。",
                "驭龙术新增技能冷却显示样式，平衡德鲁伊新增日月蚀资源预设。",
                "完善 PVE 图标文字样式与位置设置，聊天条支持独立调整字号。",
                "声音提醒列表支持跨类型与专精搜索。",
                "修复资源条刷新与设计拖动异常、宠物技能状态显示及自动修理启停问题。",
            },
            enUS = {
                "Added resource management with custom resource bars, vertical layouts, equal-width rows, and geometric or native resource points.",
                "Added Diamond, Contour, and Shade appearances for monitors and action bars, with Masque skin support.",
                "Added a dedicated Addon Assistant window and game menu entry, with addon profiles by activity and specialization.",
                "Added Skyriding ability cooldown styles and Solar/Lunar Eclipse resource presets for Balance Druids.",
                "Improved PVE icon text styling and positioning; chat bar text now has an independent font size.",
                "Sound alert searches now span alert types and specializations.",
                "Fixed resource updates and designer dragging, pet ability status displays, and automatic repair activation.",
            },
        },
    },
})
