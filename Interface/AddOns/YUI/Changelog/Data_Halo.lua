-- Generated from Docs/Products/YUI_YHUD/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("yhud", {
-- YUI-Notes-Record: halo-104|forever|039e2991f501b3d8f1a2243efbd85111cf60d9e0470047458013c50a99f030bb
    {
        version = "halo-104",
        date = "2026-10-11",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增无限服监控台与设计器支持，功能范围和 YUI 整合包保持一致；无限服暂不提供声音提醒。",
                "新增图标分组公共冷却显示开关。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added Forever support for the monitor and designer, matching the YUI suite. Sound reminders remain unavailable on Forever.",
                "Added a global cooldown display toggle for icon groups.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: halo-104|mainline|2d4c18e7ffd5a60e7a0b374caf42f80866660d56e720f98702249c4839d88e52
    {
        version = "halo-104",
        date = "2026-10-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增图标分组公共冷却显示开关。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added a global cooldown display toggle for icon groups.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: halo-103|mainline|da654ddb282c92056a688fec5f99e9a098414ec0da66aab2542447959c1ececb
    {
        version = "halo-103",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "优化图标阴影的尺寸适配和宽圆角显示。",
                "修复部分冷却提醒漏播、中断，以及光环提醒导致卡顿的问题。",
            },
            enUS = {
                "Improved icon shadows when resizing and corrected wide rounded corners.",
                "Fixed missed or interrupted cooldown alerts and stuttering caused by some aura alerts.",
            },
        },
    },
-- YUI-Notes-Record: halo-103|forever|15d1ffecdd4e5de8d6e5886c1fca83fd6a283a390e5735badbf16af622505503
    {
        version = "halo-103",
        date = "2026-10-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "优化图标阴影的尺寸适配和宽圆角显示。",
            },
            enUS = {
                "Improved icon shadows when resizing and corrected wide rounded corners.",
            },
        },
    },
-- YUI-Notes-Record: halo-102|mainline|daa2b03af6f8bc56255ad1f309c7403a1662c301c2f1e5cf23445a90b7eab88f
    {
        version = "halo-102",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "低等级隐藏默认门槛改为10级，新分组默认间距更紧凑。",
                "新增语音包检查与试听，优化语音包选择界面。",
                "修复资源组宽度预览和设计模式重叠问题。",
                "修复与其他单体插件共同加载时可能无法启用的问题。",
                "修复部分原生光环声音提醒无法绑定或播放的问题。",
            },
            enUS = {
                "Lowered the default low-level hiding threshold to level 10 and tightened default spacing for new groups.",
                "Added voice pack checks and auditions; improved voice pack selection.",
                "Fixed resource group width previews and overlapping elements in design mode.",
                "Fixed initialization failures when loaded alongside other standalone addons.",
                "Fixed binding and playback failures affecting some native aura sound alerts.",
            },
        },
    },
-- YUI-Notes-Record: halo-102|forever|ff69276c04f4c07077973c8078dfd9319ef0c0ae61d6cb248013299e54473517
    {
        version = "halo-102",
        date = "2026-10-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "低等级隐藏默认门槛改为10级，新分组默认间距更紧凑。",
                "修复资源组宽度预览和设计模式重叠问题。",
            },
            enUS = {
                "Lowered the default low-level hiding threshold to level 10 and tightened default spacing for new groups.",
                "Fixed resource group width previews and overlapping elements in design mode.",
            },
        },
    },
-- YUI-Notes-Record: halo-101|mainline|b799d18f8cc81fccf86778f6f2fe73ef540a3a96f4111fe574344febc6a31929
    {
        version = "halo-101",
        date = "2026-10-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增独立资源组，修复保存后重新进入设计模式时资源组不显示的问题。",
                "新增低等级隐藏与三种隐藏范围，默认低于 20 级仅显示资源，等级门槛可调整。",
                "新增图标形状阴影，优化外观选项与全局设置布局。",
                "新增跟随客户端语言的游戏内日志入口，更新插件图标并优化设置导航对齐。",
            },
            enUS = {
                "Added independent resource groups; fixed saved resource groups disappearing when reopening design mode.",
                "Added low-level group hiding with three scope options; defaults to showing only resources below level 20, with a configurable threshold.",
                "Added shape-matched icon shadows and improved appearance controls and global settings layout.",
                "Added an in-game release notes entry that follows the client language; updated addon icons and settings navigation alignment.",
            },
        },
    },
-- YUI-Notes-Record: halo-100|mainline|1034c5e70ed8522dce2b2d14cebb5ae7bbcd48db08741f0f8eded1bd1383b3c1
    {
        version = "halo-100",
        date = "2026-09-28",
        clients = { "Retail" },
        content = {
            zhCN = {
                "准备正式服单体首发，包含监控台与声音提醒。",
                "输入 /halo 打开设置，保留 /yhud 兼容。",
                "新增颜色选择器，支持收藏、最近颜色与恢复默认。",
                "修复登录饰品图标漏刷、设计模式层级及分页按钮显示问题。",
                "升级提示：旧目录测试版需先导出配置，再导入新版；配置键与分享格式保持兼容。",
            },
            enUS = {
                "Prepared the first Retail standalone release with monitoring and sound reminders.",
                "Use /halo to open settings; /yhud remains supported.",
                "Added a color picker with favorites, recent colors and default color restore.",
                "Fixed missing trinket icons after login, design mode layers and clipped page buttons.",
                "Upgrade note: Export settings from older test folders before importing into the new release; configuration keys and share formats remain compatible.",
            },
        },
    },
})
