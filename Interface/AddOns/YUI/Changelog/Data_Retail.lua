-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v338|mainline|ef6fb8d886b668398085b000dd9b5dac312d44fd2bc4c362c76735d9b7f2c878
    {
        version = "v338",
        date = "2026-10-11",
        clients = { "Retail" },
        content = {
            zhCN = {
                "地图新增朝向指示线；小地图支持 FPS／延迟显示及文字样式、位置设置。",
                "信息条支持位置与位面组合显示及自定义格式。",
                "私聊提示音支持多种声音选择与试听。",
                "监控台新增图标分组公共冷却显示开关。",
                "优化焦点助手、战斗增强、大秘境工具与职业额外监控的设置布局。",
                "EllesmereUI 增强新增自定义快捷键缩写，完善好友列表美化。",
                "修复信息条与小地图同时启用时的系统信息加载问题。",
                "修复背包栏自动显隐可能干扰 ESC 关闭窗口的问题。",
            },
            enUS = {
                "Added world map facing lines and minimap FPS/latency displays, with configurable text styles and positions.",
                "InfoBar: added combined location and shard displays with custom formats.",
                "Whisper alerts now support multiple sound choices and previews.",
                "Monitor: added a global cooldown display toggle for icon groups.",
                "Improved settings layouts for Focus Helper, Combat Enhancement, Mythic+ Tools and Class Extra Monitors.",
                "EllesmereUI Enhancement: added customizable hotkey abbreviations and improved friends list styling.",
                "Fixed system metrics loading when the information bar and minimap are both enabled.",
                "Fixed automatic bag bar visibility updates that could interfere with closing windows using ESC.",
            },
        },
    },
-- YUI-Notes-Record: v337|mainline|25be188c3f8939af33f13cb93b5c0e454337705f228a0a413bd60a77b020766c
    {
        version = "v337",
        date = "2026-10-10",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增提示框跟随鼠标，支持九方位和位置偏移设置。",
                "动作条新增直角微扁和圆角微扁外观。",
                "邮箱助手支持收藏最近收件人和调整联系人顺序，优化窗口交互。",
                "背包栏新增自动、隐藏和显示三种模式。",
                "修复主动作条悬停显示时技能提示失效的问题。",
                "修复一键安装中冷却配置的读取与导入问题。",
            },
            enUS = {
                "Added cursor-following tooltips with nine anchor positions and adjustable offsets.",
                "Added slightly wide square and rounded action bar shapes.",
                "Mail Assistant: added recent-recipient favorites and contact ordering, and improved window interactions.",
                "Added automatic, hidden and visible modes for the bag bar.",
                "Fixed missing ability tooltips when the main action bar uses mouseover visibility.",
                "Fixed cooldown configuration reading and importing during one-click setup.",
            },
        },
    },
-- YUI-Notes-Record: v336|mainline|816ebc9e6f63b97c0a02a5b8a80105199dcf2f8bcb619a0fbe61fee2b2158cf3
    {
        version = "v336",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "优化监控台与动作条图标阴影的尺寸适配和宽圆角显示。",
                "修复部分冷却提醒漏播、中断，以及光环提醒导致卡顿的问题。",
            },
            enUS = {
                "Improved monitor and action bar icon shadows when resizing and corrected wide rounded corners.",
                "Fixed missed or interrupted cooldown alerts and stuttering caused by some aura alerts.",
            },
        },
    },
-- YUI-Notes-Record: v335|mainline|cba2c4ffd287a7a01220306286620db35d424685bd2e1b5824404ad4d480e49d
    {
        version = "v335",
        date = "2026-10-09",
        clients = { "Retail" },
        content = {
            zhCN = {
                "信息条：重整传送菜单，支持赛季直达、物品分类和英雄之路分版本展示。",
                "常用工具：新增姓名板文字描边，默认开启。",
                "声音提醒：新增语音包检查与试听，优化语音包选择界面。",
                "监控台：低等级隐藏默认门槛改为10级，新分组默认间距更紧凑。",
                "购物助手：优化物品数量刷新，减少过图时的额外开销。",
                "修复监控台资源组宽度预览和设计模式重叠问题。",
                "修复部分原生光环声音提醒无法绑定或播放的问题。",
            },
            enUS = {
                "InfoBar: redesigned teleport menus with direct seasonal shortcuts, item categories and dungeon teleports grouped by expansion.",
                "Utility Tools: added nameplate text outlines, enabled by default.",
                "Sound Alerts: added voice pack checks and auditions; improved voice pack selection.",
                "Monitor: lowered the default low-level hiding threshold to level 10 and tightened default spacing for new groups.",
                "Auction Helper: optimized item count updates to reduce unnecessary work during zone transitions.",
                "Fixed resource group width previews and overlapping elements in design mode.",
                "Fixed binding and playback failures affecting some native aura sound alerts.",
            },
        },
    },
-- YUI-Notes-Record: v334|mainline|22b7705529b7a915d6683a3a7d5fe6ea573d5e70a4f87c552495da38a036ffb3
    {
        version = "v334",
        date = "2026-10-07",
        clients = { "Retail" },
        content = {
            zhCN = {
                "安装向导：新增应用姓名板配置。",
                "动作条：优化激活高亮，修复高亮残留与圆角显示问题。",
            },
            enUS = {
                "Setup Wizard: added an option to apply a nameplate profile.",
                "Action Bars: improved active highlights and fixed lingering highlights and rounded-corner display.",
            },
        },
    },
-- YUI-Notes-Record: v333|mainline|bf0ffe2bd00456c7365728862eb7b8342f58298dc0b2e8f5bd5234df22664a39
    {
        version = "v333",
        date = "2026-10-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "监控台：低等级隐藏新增所有分组、资源条以外分组、仅原生分组三种范围。",
                "背包栏：关闭背包时自动隐藏，打开时显示，并修复反复开关后的恢复问题。",
                "装备信息：新建或编辑装备方案时隐藏摘要，避免遮挡弹窗。",
                "动作条：滚轮快捷键缩写统一为 MU、MD。",
                "交易增强：批量购买面板跟随商人窗口皮肤设置。",
            },
            enUS = {
                "Halo: added three low-level hiding options: all groups, non-resource groups, or native groups only.",
                "Bags Bar: automatically hides while bags are closed and appears when a bag opens; fixed restoration after repeated toggling.",
                "Character Equipment: hides the summary while creating or editing equipment sets to avoid overlap.",
                "Action Bars: shortened mouse wheel binding labels to MU and MD.",
                "Trade Enhancement: bulk purchase panels now follow merchant window skin settings.",
            },
        },
    },
-- YUI-Notes-Record: v332|mainline|664412c890297532be3f00f53d4ee5d95f092bc835029f8e088bf9e8cc669310
    {
        version = "v332",
        date = "2026-10-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "安装向导：新增切换到已有 YUI 配置的选项，并保存当前角色绑定。",
            },
            enUS = {
                "Setup Wizard: added an option to switch the current character to the existing YUI profile.",
            },
        },
    },
-- YUI-Notes-Record: v331|mainline|d8c3aa85a2816c3e1eb5f2590fcba54f16f98373f994d86e7d7e259e089a539e
    {
        version = "v331",
        date = "2026-10-06",
        clients = { "Retail" },
        content = {
            zhCN = {
                "监控台：新增独立资源组与低等级仅显示资源，等级门槛默认 20，可调整。",
                "监控台与动作条：新增形状阴影，动作条支持背景颜色设置。",
                "修复姿态冷却显示及冷却结束后的灰色残留。",
                "小地图：新增右键追踪提示，默认关闭。",
                "经验条：默认改用紫、蓝、橙纯色配色。",
                "更新日志跟随客户端语言，优化设置导航图标与对齐。",
            },
            enUS = {
                "Halo: added independent resource groups and resource-only display below a configurable level, defaulting to 20.",
                "Halo and Action Bars: added shape-matched icon shadows and configurable action button backgrounds.",
                "Fixed stance cooldown display and gray icons after cooldowns ended.",
                "Minimap: added a right-click tracking hint, off by default.",
                "Experience Bar: changed default colors to solid purple, blue and orange.",
                "Release notes follow the client language; improved settings navigation icons and alignment.",
            },
        },
    },
-- YUI-Notes-Record: v330|mainline|1d517dc4b40f50fea97c32c96bb572d74d2a104c8b7e26e0cd529ccf68ba6a4f
    {
        version = "v330",
        date = "2026-10-04",
        clients = { "Retail" },
        content = {
            zhCN = {
                "法术警报：完善增益倒计时，修复文字显示与动画问题。",
                "法术警报：新增牧师警报自动避让，减少重叠。",
                "优化内存占用。",
                "聊天条：默认使用游戏字体，保留自定义设置。",
                "插件语言跟随游戏客户端，取消手动切换。",
                "更新大秘境评分数据。",
            },
            enUS = {
                "Spell Alert: improved buff countdowns and fixed text and animation issues.",
                "Spell Alert: added automatic spacing for priest alerts to reduce overlap.",
                "Optimized memory usage.",
                "Chat Bar: use the game font by default while keeping custom settings.",
                "Addon language now follows the game client; manual switching has been removed.",
                "Updated Mythic+ rating data.",
            },
        },
    },
-- YUI-Notes-Record: v329|mainline|88fcd89810d7b1d274486340860f39dfc9e84d6f0fad7ed26ec970b6ea8a6cb7
    {
        version = "v329",
        date = "2026-09-28",
        clients = { "Retail" },
        content = {
            zhCN = {
                "整合包：统一多客户端版本号，保留独立加载与更新日志。",
                "界面：新增颜色选择器，支持收藏、最近颜色与恢复默认。",
                "地图：优化地点标记与导航，新增移动时半透明。",
                "装备观察：新增装等、附魔、宝石和耐久显示，完善换装提示与界面兼容。",
                "监控台：修复登录饰品图标漏刷、设计模式层级及分页按钮问题。",
                "升级经验条：支持调整等级文字位置。",
                "声音提醒：补充盗贼、战士、死亡骑士及焦点打断语音。",
                "修复部分界面、施法序列与皮肤适配问题。",
                "更新大秘境评分数据。",
            },
            enUS = {
            },
        },
    },
})
