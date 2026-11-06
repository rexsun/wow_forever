-- Generated from Docs/Products/YUI_NovaToolbox/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("toolbox", {
-- YUI-Notes-Record: nova-134|mainline|e85e3fb9312ca93bf0b294f010ee341a91b86aafcd5451d2605c6a6974355ebf
    {
        version = "nova-134",
        date = "2026-11-05",
        clients = { "Retail" },
        content = {
            zhCN = {
                "优化任务路线收起兼容性。",
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Improved compatibility for quest guide collapsing.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-134|forever|6843b3599b60c167be6087d0b807728c721c43d08a44e1e4bc63551c28a1c938
    {
        version = "nova-134",
        date = "2026-11-05",
        clients = { "Forever" },
        content = {
            zhCN = {
                "同步共享核心，兼容新版 YUI 系列插件。",
            },
            enUS = {
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-133|mainline|5128f2381bcbc1731da35f3c78f1e79bfba13e164cc86f121224b65ec73b94ed
    {
        version = "nova-133",
        date = "2026-11-04",
        clients = { "Retail" },
        content = {
            zhCN = {
                "插件助手支持分别勾选插件，并提示依赖异常。",
                "插件性能监控窗口不再随 Esc 关闭。",
                "修复延迟容限后台刷新干扰配置导入。",
                "修复过场动画后小地图偏移、遮挡鼠标操作。",
            },
            enUS = {
                "Addon Assistant now toggles each addon separately and warns about dependency issues.",
                "The addon performance monitor now stays open when pressing Escape.",
                "Fixed background latency-tolerance updates interfering with configuration imports.",
                "Fixed minimap displacement and blocked mouse interactions after cinematics.",
            },
        },
    },
-- YUI-Notes-Record: nova-133|forever|8847e1c4ebaae43f62bfce79de05b1b556c6cffb4be42f9bad631f0fdbf0da2e
    {
        version = "nova-133",
        date = "2026-11-04",
        clients = { "Forever" },
        content = {
            zhCN = {
                "插件助手支持分别勾选插件，并提示依赖异常。",
                "插件性能监控窗口不再随 Esc 关闭。",
                "修复延迟容限后台刷新干扰配置导入。",
            },
            enUS = {
                "Addon Assistant now toggles each addon separately and warns about dependency issues.",
                "The addon performance monitor now stays open when pressing Escape.",
                "Fixed background latency-tolerance updates interfering with configuration imports.",
            },
        },
    },
-- YUI-Notes-Record: nova-132|mainline|ffd1c5081d2b24aec28444492c5a382291780abdf07523abda17f1d367d8ae21
    {
        version = "nova-132",
        date = "2026-10-31",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增插件助手独立窗口与游戏菜单入口，支持按场景和专精管理插件方案。",
                "PVE 图标文字支持独立样式与位置设置，并新增设置快捷入口。",
                "聊天条支持独立调整文字字号，并同步调整鼠标悬停区域。",
                "修复关闭交易增强后自动修理仍可能执行的问题。",
            },
            enUS = {
                "Added a dedicated Addon Assistant window and game menu entry, with addon profiles by activity and specialization.",
                "Added independent PVE icon text styling and positioning, plus a settings shortcut.",
                "Chat bar text now has an independent font size, with matching mouseover areas.",
                "Fixed automatic repair potentially remaining active after Trade Enhancement was disabled.",
            },
        },
    },
-- YUI-Notes-Record: nova-132|forever|15beb72a97c812155975e085dc184d575acd28fb7f261885da19a588003f3bc2
    {
        version = "nova-132",
        date = "2026-10-31",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增插件助手独立窗口与游戏菜单入口，支持按场景和专精管理插件方案。",
                "聊天条支持独立调整文字字号，并同步调整鼠标悬停区域。",
                "修复关闭交易增强后自动修理仍可能执行的问题。",
            },
            enUS = {
                "Added a dedicated Addon Assistant window and game menu entry, with addon profiles by activity and specialization.",
                "Chat bar text now has an independent font size, with matching mouseover areas.",
                "Fixed automatic repair potentially remaining active after Trade Enhancement was disabled.",
            },
        },
    },
-- YUI-Notes-Record: nova-131|mainline|73d96d02e77732d3d25b8e6b36818fe520a3dd6dde5b28e950ba336f917c60c9
    {
        version = "nova-131",
        date = "2026-10-26",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增勾选收件、只收金币和批量删除空信。",
                "新增邮件收发记录。",
                "发件联系人支持搜索和最近寄送快捷收藏。",
                "优化侧栏布局及其他邮件插件的兼容处理。",
                "优化法术警报预览，按专精展示固定图案并标注布局占位。",
                "战斗中的地图标记刷新延至脱战后执行。",
            },
            enUS = {
                "Added selected-mail collection, gold-only collection, and bulk empty-mail deletion.",
                "Added mail history for sent and received messages.",
                "Added contact search and quick favorites for recent recipients.",
                "Improved sidebar layout and compatibility with other mail addons.",
                "Improved spell alert previews with fixed specialization layouts and labeled placeholders.",
                "Map marker refreshes requested during combat now wait until combat ends.",
            },
        },
    },
-- YUI-Notes-Record: nova-131|forever|28e5ba87ffa09c3fb8b16161e5732aa643092c8159daaf975f301be782e59b7a
    {
        version = "nova-131",
        date = "2026-10-26",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增邮件助手，支持勾选收件、只收金币和批量删除空信。",
                "新增邮件收发记录。",
                "发件联系人支持搜索和最近寄送快捷收藏。",
                "优化侧栏布局及其他邮件插件的兼容处理。",
                "优化法术警报预览及布局占位提示。",
                "战斗中的地图标记刷新延至脱战后执行。",
                "修复邮件联系人完整姓名与服务器信息处理。",
            },
            enUS = {
                "Added Mail Assistant with selected-mail collection, gold-only collection, and bulk empty-mail deletion.",
                "Added mail history for sent and received messages.",
                "Added contact search and quick favorites for recent recipients.",
                "Improved sidebar layout and compatibility with other mail addons.",
                "Improved spell alert previews and layout placeholder hints.",
                "Map marker refreshes requested during combat now wait until combat ends.",
                "Fixed full-name and realm information handling for mail contacts.",
            },
        },
    },
-- YUI-Notes-Record: nova-130|mainline|96c2f7f58060ed80c6a151923c17b211fe3a84a2e7d87bdd7ef7bb23e7212f19
    {
        version = "nova-130",
        date = "2026-10-23",
        clients = { "Retail" },
        content = {
            zhCN = {
                "购物助手新增物品加载提示，修复物品信息未就绪时点击搜索无响应的问题。",
                "修复多个单体共同加载时的配置导入与部分界面初始化异常。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added item-loading feedback to Auction Helper and fixed unresponsive searches when item information is unavailable.",
                "Fixed configuration import and some UI initialization issues when multiple standalone addons are loaded together.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-130|forever|637a6ce336e98c8ae393e0b635ce1f4d949a5000dc3d0833e799a7cb9d8f7954
    {
        version = "nova-130",
        date = "2026-10-23",
        clients = { "Forever" },
        content = {
            zhCN = {
                "任务追踪新增自动接交任务开关，可统一关闭已加载插件的自动接交。",
                "Polestar 路线支持进入副本自动收起，离开后恢复。",
                "修复多个单体共同加载时的配置导入与部分界面初始化异常。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added a quest tracker toggle that can disable quest automation across loaded addons.",
                "Polestar guides now collapse automatically on entering an instance and restore on leaving.",
                "Fixed configuration import and some UI initialization issues when multiple standalone addons are loaded together.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-129|mainline|1a3857d37a30e10dc732d1670a731f1979e81e299e579ed1228f742addddcd33
    {
        version = "nova-129",
        date = "2026-10-22",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复配置导入失败后的延迟容限恢复异常。",
            },
            enUS = {
                "Fixed incorrect lag tolerance restoration after failed configuration imports.",
            },
        },
    },
-- YUI-Notes-Record: nova-129|forever|83339f2fa5037647d85c69f3d38f3342db7b746932e6685d687e9ea54f851a33
    {
        version = "nova-129",
        date = "2026-10-22",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增 Polestar 任务路线收起，支持调整折叠标签尺寸。",
                "补充莫高雷与泽风岛双向飞艇标记及离岛阵营提示。",
                "修复配置导入失败后的延迟容限恢复异常。",
            },
            enUS = {
                "Added collapsible Polestar quest guides with adjustable collapsed-label size.",
                "Added zeppelin markers between Mulgore and Zephras Isle, with faction departure hints.",
                "Fixed incorrect lag tolerance restoration after failed configuration imports.",
            },
        },
    },
-- YUI-Notes-Record: nova-128|mainline|9ba190554b64ec94594944b4806d0cb643675c2cbab00a0af4ff001ed1d3a7e5
    {
        version = "nova-128",
        date = "2026-10-22",
        clients = { "Retail" },
        content = {
            zhCN = {
                "焦点施法条新增重要施法发光等条件。",
                "角色属性面板支持战斗中固定显示项目与排列，数值仍实时更新。",
                "装备摘要支持临时关闭，并补充附魔图标。",
                "统一组件字体设置，支持样式复制粘贴。",
                "界面美化新增蓝灰与炭黑主题，支持阴影和透明度设置。",
                "优化任务追踪滚动体验。",
                "改善与Shifter共同使用时的世界地图窗口兼容性。",
                "优化邮件收件人筛选，减少其他游戏版本角色混入。",
            },
            enUS = {
                "Added glow conditions to the focus cast bar, including important casts.",
                "The character stats panel can now keep pre-combat items and their arrangement during combat while continuing to update values.",
                "Added temporary dismissal and enchantment icons to equipment summaries.",
                "Unified component font settings with style copy and paste.",
                "Added blue-gray and charcoal themes to UI enhancements, with shadow and opacity settings.",
                "Improved quest tracker scrolling.",
                "Improved world map window compatibility with Shifter.",
                "Improved mail recipient filtering to reduce entries from other game versions.",
            },
        },
    },
-- YUI-Notes-Record: nova-128|forever|b307c2fdc83069d66cd9168acf081451c68fdd6e2ee2ad3280d4d097eb98e627
    {
        version = "nova-128",
        date = "2026-10-22",
        clients = { "Forever" },
        content = {
            zhCN = {
                "焦点施法条新增重要施法发光等条件。",
                "装备摘要支持临时关闭，并补充附魔图标。",
                "统一组件字体设置，支持样式复制粘贴。",
                "界面美化新增蓝灰与炭黑主题，支持阴影和透明度设置。",
                "优化任务追踪滚动体验。",
                "地图新增敌对阵营NPC标记。",
                "新增进入非团本副本时的伤害统计重置询问，可按需启用。",
                "改善与Shifter共同使用时的世界地图窗口兼容性。",
                "优化邮件收件人筛选及完整角色名处理。",
                "修复战斗增强中的目标与焦点距离显示异常。",
            },
            enUS = {
                "Added glow conditions to the focus cast bar, including important casts.",
                "Added temporary dismissal and enchantment icons to equipment summaries.",
                "Unified component font settings with style copy and paste.",
                "Added blue-gray and charcoal themes to UI enhancements, with shadow and opacity settings.",
                "Improved quest tracker scrolling.",
                "Added opposing-faction NPC markers to the map.",
                "Added an optional damage-meter reset prompt on non-raid dungeon entry.",
                "Improved world map window compatibility with Shifter.",
                "Improved mail recipient filtering and full-character-name handling.",
                "Fixed target and focus distance displays in Combat Enhancement.",
            },
        },
    },
-- YUI-Notes-Record: nova-127|mainline|a3004b3909c9c65e3d5d48fb4de5b10314a36e1b87d7b72ddbfa1a91ed7b26dd
    {
        version = "nova-127",
        date = "2026-10-16",
        clients = { "Retail" },
        content = {
            zhCN = {
                "职业额外提醒新增自动血沸，统一声音选择并支持明确静音。",
                "自动对话支持按住暂停或按住启用，并可选择控制按键。",
                "购物助手支持按材料缺口预填购买数量，新增满星材料统计。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added automatic Blood Boil monitoring and unified sound selection with an explicit silent option.",
                "Added hold-to-pause and hold-to-enable controls for automatic dialogue, with a selectable modifier key.",
                "Added purchase quantities based on material shortages and highest-quality material tracking.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-127|forever|68b7e6a4c5bf5aa3694a0441e595f0f053d918050106998d3de2dc82522c958a
    {
        version = "nova-127",
        date = "2026-10-16",
        clients = { "Forever" },
        content = {
            zhCN = {
                "新增无限服 EllesmereUI 美化支持，适配相关窗口与字体。",
                "自动对话支持按住暂停或按住启用，并可选择控制按键。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Added EllesmereUI enhancement support for Forever, including window and font adaptations.",
                "Added hold-to-pause and hold-to-enable controls for automatic dialogue, with a selectable modifier key.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-126|mainline|e631fe504e973a9670d05bf784393ae1c7bec99468c1a97d1ca32da8f30b02d3
    {
        version = "nova-126",
        date = "2026-10-15",
        clients = { "Retail" },
        content = {
            zhCN = {
                "改善法术警报倒计时对正式服更新的兼容性。",
                "同步共享核心，保持与新版 YUI 系列插件的兼容。",
            },
            enUS = {
                "Improved spell alert countdown compatibility with Retail updates.",
                "Updated the shared core for compatibility with newer YUI addons.",
            },
        },
    },
-- YUI-Notes-Record: nova-126|forever|4459c1317dda688391bf6c393b455275571925ae9dd3a335761f858b8e48dea7
    {
        version = "nova-126",
        date = "2026-10-15",
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
})
