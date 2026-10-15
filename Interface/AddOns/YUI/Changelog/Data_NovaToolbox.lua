-- Generated from Docs/Products/YUI_NovaToolbox/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("toolbox", {
-- YUI-Notes-Record: nova-125|mainline|1dcb0c44fa018d1636b9243c19797405bd8091b74b49fd7754972d6043287fbb
    {
        version = "nova-125",
        date = "2026-10-15",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增鼠标提示立即隐藏选项，默认启用。",
                "修复角色观察摘要的层级显示，改善 12.1.5 物品计数兼容性。",
                "完善配置导入与失败恢复。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added an instant tooltip hiding option, enabled by default.",
                "Fixed character inspection summary layering and improved 12.1.5 item count compatibility.",
                "Improved configuration imports and recovery after failed imports.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-125|forever|4a9e252f3030f5b5d05bb5c18646032c6baa13ea9da7eab291c765f91b90fe3b
    {
        version = "nova-125",
        date = "2026-10-15",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增鼠标提示立即隐藏选项，默认启用。",
                "地图设置支持随配置导入导出。",
                "完善配置导入与失败恢复。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added an instant tooltip hiding option, enabled by default.",
                "Map settings can now be included in configuration imports and exports.",
                "Improved configuration imports and recovery after failed imports.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-124|mainline|2e5b174ce8e82a0b4c2dc714b7205483cdcf2a9b3b348ee758f5eecf164e2eab
-- YUI-Notes-Record: nova-124|forever|d9e2bd007346e8462758483354bba5b741e2d2fc89c7878bb00048b4730e9ad5
    {
        version = "nova-124",
        date = "2026-10-13",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "新增RXP插件点击缩放功能，界面更清爽；",
                "地图标记按钮支持左键显隐、右键筛选，完善小地图插件按钮收纳。",
                "经验条详情支持背景透明度设置，优化底部提示颜色。",
                "新增屏蔽一些测试服红字",
            },
            enUS = {
                "Added click-to-collapse support for the RXP addon for a cleaner interface.",
                "Map marker buttons now use left-click to toggle markers and right-click for filters; improved minimap addon button collection.",
                "Added background opacity settings for experience details and improved the bottom hint color.",
                "Added filtering for some red beta messages.",
            },
        },
    },
-- YUI-Notes-Record: nova-123|mainline|3b4f0129cb957114bb62a871411ed5d665c38f2b373ecd89130b3c1b83198b73
-- YUI-Notes-Record: nova-123|forever|5e481c35eccaf9215f99b1394a9ae44a2281c92608425af186ef0f2fffd900bb
    {
        version = "nova-123",
        date = "2026-10-12",
        clients = { "Retail", "Forever" },
        content = {
            zhCN = {
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-122|forever|4555f5e33a361167532bd733a9dac9499e446e7f165e3bbd2fee29eae419a0a2
    {
        version = "nova-122",
        date = "2026-10-11",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增无限服支持，工具与地图增强范围和 YUI 整合包保持一致。",
                "提供鼠标跟随提示框、邮箱联系人、私聊提示、焦点助手与战斗工具。",
                "地图支持朝向指示线；小地图支持 FPS／延迟显示及样式、位置设置。",
                "修复小地图系统信息加载问题，以及与 YUI 同时启用时的地图加载警告。",
            },
            enUS = {
                "Added Forever support, with tools and map enhancements matching the YUI suite.",
                "Includes cursor-following tooltips, mail contacts, whisper alerts, focus helpers and combat tools.",
                "Added map facing lines and minimap FPS/latency displays with configurable styles and positions.",
                "Fixed minimap system metrics loading and map loading warnings when Nova and YUI are enabled together.",
            },
        },
    },
-- YUI-Notes-Record: nova-122|mainline|b6084b4621a7454f78b7769715da4d06b11cf02c3a8c89ab126f54f1d5322bda
    {
        version = "nova-122",
        date = "2026-10-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "地图新增朝向指示线；小地图支持 FPS／延迟显示及文字样式、位置设置。",
                "私聊提示音支持共享音频、自定义路径与试听。",
                "优化焦点助手、战斗增强、大秘境工具与职业额外监控的设置布局。",
                "EllesmereUI 增强新增自定义快捷键缩写，完善好友列表美化。",
                "修复小地图系统信息加载问题，以及与 YUI 同时启用时的地图加载警告。",
            },
            enUS = {
                "Added world map facing lines and minimap FPS/latency displays, with configurable text styles and positions.",
                "Whisper alerts now support shared audio, custom sound paths and previews.",
                "Improved settings layouts for Focus Helper, Combat Enhancement, Mythic+ Tools and Class Extra Monitors.",
                "EllesmereUI Enhancement: added customizable hotkey abbreviations and improved friends list styling.",
                "Fixed minimap system metrics loading and map loading warnings when Nova and YUI are enabled together.",
            },
        },
    },
-- YUI-Notes-Record: nova-121|mainline|5dad6bc48e9c46595d2f848162f53e10482e41d99958cfdd9edd22b72a851296
    {
        version = "nova-121",
        date = "2026-10-10",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增提示框跟随鼠标，支持九方位和位置偏移设置。",
                "邮箱助手支持收藏最近收件人和调整联系人顺序，优化窗口交互。",
            },
            enUS = {
                "Added cursor-following tooltips with nine anchor positions and adjustable offsets.",
                "Mail Assistant: added recent-recipient favorites and contact ordering, and improved window interactions.",
            },
        },
    },
-- YUI-Notes-Record: nova-120|mainline|8a58d713b1fadca523fdda14932e57e1f2ee017fa6a3584d012abc330f7fdbf9
    {
        version = "nova-120",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "同步核心版本，避免与新版 YUI 插件共同加载时的版本冲突。",
            },
            enUS = {
                "Updated the shared core to avoid version conflicts when loaded alongside newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-119|mainline|ed87357e37808196d65e4745d8a787470f5a48d0e05fc985e92f5a41ced1d472
    {
        version = "nova-119",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增姓名板文字描边，默认开启。",
                "优化购物助手物品数量刷新，减少过图及面板隐藏时的额外开销。",
            },
            enUS = {
                "Added nameplate text outlines, enabled by default.",
                "Optimized Auction Helper item count updates to reduce unnecessary work during zone transitions and while hidden.",
            },
        },
    },
-- YUI-Notes-Record: nova-118|mainline|e2f27955ffc900f05fa78bdccfb95031a8b166c26c51c33c646ad67826cbe66f
    {
        version = "nova-118",
        date = "2026-10-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "小地图：新增右键追踪提示，默认关闭。",
                "经验条：默认改用紫、蓝、橙纯色配色。",
                "装备信息：新建或编辑装备方案时隐藏摘要，避免遮挡弹窗。",
                "交易增强：批量购买面板跟随商人窗口皮肤设置。",
                "新增跟随客户端语言的游戏内日志入口，更新插件图标并优化设置导航对齐。",
            },
            enUS = {
                "Minimap: added a right-click tracking hint, off by default.",
                "Experience Bar: changed default colors to solid purple, blue and orange.",
                "Character Equipment: hides the summary while creating or editing equipment sets to avoid overlap.",
                "Trade Enhancement: bulk purchase panels now follow merchant window skin settings.",
                "Added an in-game release notes entry that follows the client language; updated addon icons and settings navigation alignment.",
            },
        },
    },
-- YUI-Notes-Record: nova-117|mainline|88317fadcced55a688292d95b482c319022eb2b8d7b1c9052c3e353a2f0970ae
    {
        version = "nova-117",
        date = "2026-09-28",
        clients = { "Retail" },
        content = {
            zhCN = {
                "优化地图标记与导航，新增移动时半透明。",
                "新增装备装等、附魔、宝石和耐久显示，完善换装提示与界面兼容。",
                "新增颜色选择器，支持收藏、最近颜色与恢复默认。",
                "升级经验条支持调整等级文字位置。",
                "优化友方姓名板设置，修复施法序列与窗口皮肤适配问题。",
                "更新大秘境评分数据。",
            },
            enUS = {
                "Improved map markers and navigation; added map fading while moving.",
                "Added equipment item levels, enchants, gems and durability, with improved upgrade hints and UI compatibility.",
                "Added a color picker with favorites, recent colors and default color restore.",
                "Added level text positioning for the experience bar.",
                "Improved friendly nameplate settings, cast sequence layout and window skin compatibility.",
                "Updated Mythic+ rating data.",
            },
        },
    },
-- YUI-Notes-Record: nova-116|mainline|2f9a26f32c5f4121f903ac627ff7f57882decb9fee9222b04d9203f816d1f5fa
    {
        version = "nova-116",
        date = "2026-09-23",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增升级经验条，支持多种外观和经验详情。",
                "新增设置搜索与窗口缩放。",
                "新增子功能状态提示，支持右键打开设置。",
                "自动对话：新增自动交接任务，默认关闭。",
                "聊天条：新增【退】按钮，支持退队和重置副本，默认关闭。",
                "地图增强：支持显示未探索区域。",
                "玩家属性：新增副属性显示格式，改善刷新。",
                "交易增强：支持物品兑换批量购买。",
                "修复密语记录、提示音和距离提示刷新问题。",
                "更新大秘境评分数据及共享核心。",
            },
            enUS = {
                "Added an experience bar with multiple styles and detailed progress.",
                "Added settings search and window scaling.",
                "Added sub-feature status hints and right-click settings access.",
                "Auto Dialogue: added automatic quest acceptance and turn-in, off by default.",
                "Chat Bar: added a Leave button for leaving groups and resetting instances, off by default.",
                "Map Enhancement: added unexplored area display.",
                "Character Stats: added secondary stat formats and improved refresh timing.",
                "Trade Enhancement: bulk buying now supports item exchanges.",
                "Fixed whisper history, notification sounds and distance indicator refresh.",
                "Updated Mythic+ rating data and shared Core.",
            },
        },
    },
})
