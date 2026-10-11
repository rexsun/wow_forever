-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
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
-- YUI-Notes-Record: v331|forever|cffe2a0f7540f8883a898ef27df2e184818caf2d0f67afa1a2ddab90d9102d51
    {
        version = "v331",
        date = "2026-10-06",
        clients = { "Forever" },
        content = {
            zhCN = {
                "接入监控台，提供三系独立方案与专用预设；声音提醒暂未开放。",
                "新增独立资源组及主手、副手、远程攻击计时器，支持主副手合并并自动隐藏原生计时条。",
                "监控台：新增低等级仅显示资源，等级门槛默认 20，可调整。",
                "接入自定义动作条、图标阴影和背景颜色，修复姿态冷却与灰色残留。",
                "新增安装向导，支持布局、可选 YUI-Beta 配置与常用设置，包含漂浮文字及关闭死亡灰白特效。",
                "完善监控与战斗工具的天赋配置识别和切换。",
                "地图：修复标记保护调用报错，新增右键追踪提示，默认关闭。",
                "新增颜色选择器与双语日志，优化设置显示及经验条默认配色。",
            },
            enUS = {
                "Added Halo with separate presets for all three talent trees; sound reminders remain unavailable.",
                "Added independent resource groups and main-hand, off-hand and ranged swing timers, with combined hand layouts and automatic native timer hiding.",
                "Halo: added resource-only display below a configurable level, defaulting to 20.",
                "Added custom Action Bars, icon shadows and background colors; fixed stance cooldowns and lingering gray icons.",
                "Added an installation wizard for layouts, optional YUI-Beta profiles and common settings, including floating combat text and disabling the grayscale death effect.",
                "Improved talent-based configuration switching for monitoring and combat tools.",
                "Map: fixed protected-call errors on markers; added a right-click tracking hint, off by default.",
                "Added a color picker and bilingual release notes; improved settings display and Experience Bar default colors.",
            },
        },
    },
-- YUI-Notes-Record: v328|forever|81709d5d5c9b97b449eb9f33a21c27cde77fed9fd8266449738d4d06b89100c6
    {
        version = "v328",
        date = "2026-09-27",
        clients = { "Forever" },
        content = {
            zhCN = {
                "整合包：改为多客户端通用包，统一版本号，保留各版本独立加载与更新日志",
                "地图：新增地点标记，支持职业与专业筛选、合集展开和点击导航",
                "地图：补充主城、新手区域与飞行点，支持航点开启状态记录",
                "地图：新增移动时半透明与不透明度设置，支持标记按钮位置调整",
                "专业助手：新增附魔分解面板，支持装备筛选、待分解队列与结果显示",
                "工具箱：接入战斗增强、焦点助手、法术警报和鼠标增强",
                "工具箱：新增友方姓名板联动，修复施法序列布局与图标尺寸",
                "原生界面：支持窗口移动与缩放，更新编辑模式布局至 v3",
                "装备观察：优化摘要与属性汇总，完善宝石、附魔和耐久显示",
                "信息条：修复组队入口，补回集合石与团队标记，完善天赋点数与图标显示",
                "聊天条：【掉】按钮支持打开无限副本手册",
                "升级经验条：新增等级文字 X / Y 偏移设置",
                "界面：修复布局导入与人物面板入口问题，支持非战斗点击按钮直接重载",
            },
            enUS = {
                "Suite: unified the release version across clients while keeping separate loading and release notes.",
                "Map: added location markers with class and profession filters, expandable groups and click navigation.",
                "Map: added city, starting-zone and flight-point locations with waypoint unlock tracking.",
                "Map: added fading while moving, opacity settings and marker button positioning.",
                "Profession Assistant: added a disenchanting panel with equipment filters, a queue and results.",
                "Toolbox: added Combat Enhancement, Focus Assistant, Spell Alert and Mouse Enhancement.",
                "Toolbox: added friendly nameplate synchronization and fixed cast sequence layout and icon sizing.",
                "Native UI: added window movement and scaling; updated the edit-mode layout to v3.",
                "Equipment Info: improved the summary, stat totals, gems, enchants and durability display.",
                "InfoBar: fixed group access and restored group-finder and raid markers; improved talent points and icons.",
                "Chat Bar: the Loot button now opens the Forever dungeon journal.",
                "Experience Bar: added X / Y offsets for level text.",
                "UI: fixed layout import and character-panel access; buttons can reload the UI out of combat.",
            },
        },
    },
-- YUI-Notes-Record: v102|forever|b4c90d19ae11b9860c5e3dd3d209928d56ead7319a93ed0e6b43443d598ce60e
    {
        version = "v102",
        date = "2026-09-25",
        clients = { "Forever" },
        content = {
            zhCN = {
                "装备观察：新增装等、附魔、宝石与耐久显示，支持外观调整和预览。",
                "装备观察：完善 ALT 换装信息与装备槽布局。",
                "编辑模式：更新 YUI v2 布局，新增切换提醒。",
                "商人：改善自动出售垃圾的兼容性。",
                "设置：修复部分按钮报错，优化字体显示。",
                "邮件助手：完善窗口皮肤适配。",
                "默认配置：取消专用配置自动套用与姓名板预设自动导入，保留已有设置。",
            },
            enUS = {
            },
        },
    },
})
