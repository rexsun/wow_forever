-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v341|forever|2243aac63a6335b65b8332b39c02c33c3a2ea3a185f9eddc6e202b25fe0a8e9b
    {
        version = "v341",
        date = "2026-10-15",
        clients = { "Forever" },
        content = {
            zhCN = {
                "监控台新增玩家生命条和施法条，支持独立分组与混排。",
                "信息条时钟新增可配置休息动效。",
                "新增鼠标提示立即隐藏选项，默认启用。",
                "地图设置支持随配置导入导出。",
                "完善配置导入、专精分配提示与失败恢复。",
                "修复聊天字体选择、耐久登录刷新与监控台层级显示问题。",
            },
            enUS = {
                "Added player health and cast bars to the monitor, with separate groups and mixed resource layouts.",
                "Added configurable resting animations to the information bar clock.",
                "Added an instant tooltip hiding option, enabled by default.",
                "Map settings can now be included in configuration imports and exports.",
                "Improved configuration imports, specialization assignment feedback and recovery after failed imports.",
                "Fixed chat font selection, durability updates after login and monitor layering.",
            },
        },
    },
-- YUI-Notes-Record: v340|forever|95c49d46b93dae2d3fe70dade73b2bbebbac92a88c735e674f2b4033cfe1e9a0
    {
        version = "v340",
        date = "2026-10-13",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增任务物体闪光与组队管理面板隐藏选项。",
                "新增RXP插件点击缩放功能，界面更清爽；",
                "地图标记按钮支持左键显隐、右键筛选，完善小地图插件按钮收纳。",
                "经验条详情支持背景透明度设置，优化底部提示颜色。",
                "法师、牧师、术士的默认监控启用魔杖远程计时器。",
                "新增屏蔽一些测试服红字",
                "修复专业制作成品的白色边框与高亮，支持开关控制。",
            },
            enUS = {
                "Added options for quest object sparkles and hiding the group management panel.",
                "Added click-to-collapse support for the RXP addon for a cleaner interface.",
                "Map marker buttons now use left-click to toggle markers and right-click for filters; improved minimap addon button collection.",
                "Added background opacity settings for experience details and improved the bottom hint color.",
                "Default monitors for mages, priests and warlocks now enable wand swing timers.",
                "Added filtering for some red beta messages.",
                "Fixed white borders and highlights on profession crafting output icons, with an optional toggle.",
            },
        },
    },
-- YUI-Notes-Record: v339|forever|6dc852632bcbe84f4e516c163ef6a33dd89db81dd5cf87b3db3a8045393eb454
    {
        version = "v339",
        date = "2026-10-12",
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
-- YUI-Notes-Record: v338|forever|9520d614019a6c82661e678ab108f6f92ab07bf372ef294034f9e04cd69398ff
    {
        version = "v338",
        date = "2026-10-11",
        clients = { "Forever" },
        content = {
            zhCN = {
                "地图新增朝向指示线；小地图支持 FPS／延迟显示及文字样式、位置设置。",
                "原生窗口移动新增拍卖行、银行、飞行地图、设置及插件列表支持，改善银行窗口调整后的背包布局联动。",
                "信息条支持位置与位面组合显示及自定义格式。",
                "私聊提示音支持多种声音选择与试听。",
                "监控台新增图标分组公共冷却显示开关。",
                "优化焦点助手与战斗增强的设置布局。",
                "修复信息条与小地图同时启用时的系统信息加载问题。",
                "修复背包栏自动显隐可能干扰 ESC 关闭窗口的问题。",
            },
            enUS = {
                "Added world map facing lines and minimap FPS/latency displays, with configurable text styles and positions.",
                "Added window movement support for the auction house, bank, flight map, settings and addon list; improved bag layout updates after adjusting the bank window.",
                "InfoBar: added combined location and shard displays with custom formats.",
                "Whisper alerts now support multiple sound choices and previews.",
                "Monitor: added a global cooldown display toggle for icon groups.",
                "Improved settings layouts for Focus Helper and Combat Enhancement.",
                "Fixed system metrics loading when the information bar and minimap are both enabled.",
                "Fixed automatic bag bar visibility updates that could interfere with closing windows using ESC.",
            },
        },
    },
-- YUI-Notes-Record: v337|forever|bce293f099d17911097fab448ec25311c94b206d2822121581f2d6e03f384775
    {
        version = "v337",
        date = "2026-10-10",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增提示框跟随鼠标，支持九方位和位置偏移设置。",
                "动作条新增直角微扁和圆角微扁外观。",
                "背包栏新增自动、隐藏和显示三种模式。",
                "修复背包整理按钮被遮挡、无法点击的问题。",
                "修复主动作条悬停显示时技能提示失效的问题。",
            },
            enUS = {
                "Added cursor-following tooltips with nine anchor positions and adjustable offsets.",
                "Added slightly wide square and rounded action bar shapes.",
                "Added automatic, hidden and visible modes for the bag bar.",
                "Fixed an overlapping button that could prevent clicking the bag sort button.",
                "Fixed missing ability tooltips when the main action bar uses mouseover visibility.",
            },
        },
    },
-- YUI-Notes-Record: v336|forever|80a333d1cf0a01ed1705a56f56b2a1db84d19040ac0e72254f744156c32676cd
    {
        version = "v336",
        date = "2026-10-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "优化监控台与动作条图标阴影的尺寸适配和宽圆角显示。",
            },
            enUS = {
                "Improved monitor and action bar icon shadows when resizing and corrected wide rounded corners.",
            },
        },
    },
-- YUI-Notes-Record: v335|forever|f30274d71371cd7107ad2dcea3f9436b182de667a9faf4c3cc0ff553cb1566ff
    {
        version = "v335",
        date = "2026-10-09",
        clients = { "Forever" },
        content = {
            zhCN = {
                "常用工具：新增姓名板文字描边，默认开启。",
                "监控台：低等级隐藏默认门槛改为10级，新分组默认间距更紧凑。",
                "修复监控台资源组宽度预览和设计模式重叠问题。",
            },
            enUS = {
                "Utility Tools: added nameplate text outlines, enabled by default.",
                "Monitor: lowered the default low-level hiding threshold to level 10 and tightened default spacing for new groups.",
                "Fixed resource group width previews and overlapping elements in design mode.",
            },
        },
    },
-- YUI-Notes-Record: v334|forever|a391867ff731c442e8622b103e5a5f35c39d0e3895b4dafab72c3ac5b2d49b6a
    {
        version = "v334",
        date = "2026-10-07",
        clients = { "Forever" },
        content = {
            zhCN = {
                "动作条：新增任务物品条，支持自动显示、固定与收起。",
                "动作条：新增技能自动升级与升级提示。",
                "信息条：新增武器熟练度、学习地点与技能训练提示。",
                "安装向导：新增应用姓名板配置。",
                "动作条：优化激活高亮与圆角显示。",
                "修复头像配置保存、开场动画期间的安装向导及目标标记问题。",
            },
            enUS = {
                "Action Bars: added a quest item bar with automatic display, pinning and collapsing.",
                "Action Bars: added automatic spell rank upgrades and notifications.",
                "InfoBar: added weapon skill, training location and spell training tooltips.",
                "Setup Wizard: added an option to apply a nameplate profile.",
                "Action Bars: improved active highlights and rounded-corner display.",
                "Fixed portrait profile saving, setup wizard behavior during intro cinematics and target markers.",
            },
        },
    },
-- YUI-Notes-Record: v333|forever|cc9b2624231c1e510069847392818ed66cf78bb65e49bae7da9cf6b75e1607eb
    {
        version = "v333",
        date = "2026-10-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "监控台：新增弹药数量监控，完善种族技能与图标显示。",
                "监控台：低等级隐藏新增所有分组、资源条以外分组、仅原生分组三种范围。",
                "背包栏：关闭背包时自动隐藏，打开时显示，并修复反复开关后的恢复问题。",
                "装备信息：新建或编辑装备方案时隐藏摘要，避免遮挡弹窗。",
                "动作条：滚轮快捷键缩写统一为 MU、MD。",
                "信息条：未分配天赋时显示职业名称。",
                "修复设置页、聊天条与信息条的重载界面点击调用。",
                "交易增强：批量购买面板跟随商人窗口皮肤设置。",
            },
            enUS = {
                "Halo: added ammo count monitoring and improved racial ability and icon display.",
                "Halo: added three low-level hiding options: all groups, non-resource groups, or native groups only.",
                "Bags Bar: automatically hides while bags are closed and appears when a bag opens; fixed restoration after repeated toggling.",
                "Character Equipment: hides the summary while creating or editing equipment sets to avoid overlap.",
                "Action Bars: shortened mouse wheel binding labels to MU and MD.",
                "InfoBar: shows the class name when no talent points are assigned.",
                "Fixed direct reload clicks from settings, the chat bar and the InfoBar.",
                "Trade Enhancement: bulk purchase panels now follow merchant window skin settings.",
            },
        },
    },
-- YUI-Notes-Record: v332|forever|5752792f34fdaa6816978b888fbe50bd8744701872dc782d09ec3e2ce9618227
    {
        version = "v332",
        date = "2026-10-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "安装向导：新增切换到已有 YUI 配置的选项，并保存当前角色绑定。",
                "移除第一步的布局图标，修复说明文字被遮挡的问题。",
            },
            enUS = {
                "Setup Wizard: added an option to switch to the existing YUI profile and save the current character's assignment.",
                "Removed the layout icon from the first step to prevent it from overlapping the description.",
            },
        },
    },
})
