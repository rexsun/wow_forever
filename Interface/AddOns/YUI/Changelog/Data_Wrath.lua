-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v333|wrath|ea66b4109db53c956965e69f28cd28b4d14f908bba059a3ea1425c43e7b480a9
    {
        version = "v333",
        date = "2026-10-06",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "背包栏：关闭背包时自动隐藏，打开时显示，并修复反复开关后的恢复问题。",
                "动作条：滚轮快捷键缩写统一为 MU、MD。",
                "交易增强：批量购买面板跟随商人窗口皮肤设置。",
            },
            enUS = {
                "Bags Bar: automatically hides while bags are closed and appears when a bag opens; fixed restoration after repeated toggling.",
                "Action Bars: shortened mouse wheel binding labels to MU and MD.",
                "Trade Enhancement: bulk purchase panels now follow merchant window skin settings.",
            },
        },
    },
-- YUI-Notes-Record: v331|wrath|1ee5d50235e14bed3a20f0e6c08d6bd7edab5b7515766b848d631bb70e80c29e
    {
        version = "v331",
        date = "2026-10-06",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "动作条：新增形状阴影与背景颜色设置。",
                "优化设置导航图标与文字对齐。",
                "更新日志跟随客户端语言。",
            },
            enUS = {
                "Action Bars: added shape-matched shadows and background color settings.",
                "Improved settings navigation icons and text alignment.",
                "Release notes now follow the client language.",
            },
        },
    },
-- YUI-Notes-Record: v208|wrath|e5f73432008adad4f10919e33906296c63e4efff2c453902aa79c93ff35d6cd2
    {
        version = "v208",
        date = "2026-06-11",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "组件 - 小地图插件收纳：增加多项设置项",
                "全能双栏 - 属性统计：新增“防御属性”显示模式",
                "全能双栏 - 天赋专精：优化战斗中刷新逻辑，避免报错",
                "全能双栏：设置界面微调以匹配多种语言",
                "其他：大量模块实现多语言支持",
            },
            enUS = {
                "Minimap Button Collection: added more settings.",
                "InfoBar Stats: added a defensive-stat display mode.",
                "InfoBar Talents: improved updates in combat to prevent errors.",
                "InfoBar: adjusted settings for different languages.",
                "Added localization for more modules.",
            },
        },
    },
-- YUI-Notes-Record: v206|wrath|885b224120655af4aa97e8c55570ea81fd56acfe64af7c5bd3bdcafb22f7ac4d
    {
        version = "v206",
        date = "2026-06-08",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "集合石：支持4.0之后版本的集结号",
                "商人扩展：修复回购页面重叠问题",
                "密语管家：鼠标悬停视为已读，修复已知BUG",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v203|wrath|62d8259d5739566a72b93649c7eca86d778f806d7cebfb60f7db4a5a217f0197
    {
        version = "v203",
        date = "2026-06-06",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "[新增] 战斗提示升级：新增纯文字模式",
                "[更新] 密语管家升级：点击直接回复、清空按钮外置、增加右键菜单",
                "[更新] 更新致谢名单",
                "[修复] 修复多个已知BUG",
                "[新增] 天赋界面扩展：全新重置版，更漂亮、更清晰",
                "[新增] 商人界面扩展：替换原商人扩展插件功能",
                "[新增] 登录检查：加载过期插件提醒",
                "[修复] ElvUI适配：修复角色面板【宠物】和【声望】重叠问题",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v200|wrath|4c5243cb8214857a8c2b0eb9c1d2000877e0415685cb8b2fcbbc7a7946c56d50
    {
        version = "v200",
        date = "2026-05-29",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "历经180+次迭代，这不是一次普通的更新",
                "而是为YUI未来10年的插件发展打好地基",
                " ",
                "Slow is fast",
                "Less is more",
                " ",
                "【全新功能】",
                "战斗提示：四种风格的进入战斗/离开战斗提醒",
                "延迟容限：可能是全网最强的同类功能",
                "音量控制：微菜单中可以便捷设置音量",
                "全新材质：YUI材质全面更新",
                "幻彩颜色：全职业材质条可升级为幻彩色，更加艳丽（有一定性能开销）",
                "专精图标：原创全职业专精图标",
                "主题外观：外观自定义试验，未来会更加强大",
                "动画系统：统一的动画系统，UI组件小试牛刀，未来会有惊喜",
                "界面重写：UI系统全面升级到2.0时代",
                "插件收纳：全版本统一使用升级版小地图插件收纳",
                "本地语言：实现简中、繁中、英语三种语言，迈向全世界",
                " ",
                "【全面增强】",
                "底层重构：底层代码全部重写",
                "组件管理：全面增强和美化（原功能百宝箱）",
                "全能双栏：几乎所有模块进行了升级和优化（原全能信息条）",
                " ",
                "【其他优化】",
                "正式服：3个版本材质风格和小地图更加统一",
                "正式服：NDUI新增美化 - 单位框架文本添加阴影",
                "正式服：EQoL新增美化 - 强制使用1像素完美边框",
                "传送助手：增加丰饶传送玩具",
                "隐藏错误信息：支持两种不同的隐藏方式",
                "游戏菜单增强：支持隐藏YUI LOGO",
                "嗜血音乐：支持声道选择、更多自定义音乐",
                "60+BUG修复和优化.",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v143|wrath|59d9b903565ec3bbe7c7b1933836b18909970610a9cdb8649ea75dbd82b67db8
    {
        version = "v143",
        date = "2026-05-06",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "信息条：时间模块新增战斗时间显示、颜色与生效场景设置",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v140|wrath|183a4479cc728eb9f879c79cf897a0cb318a1b02e9f5eedca043a04de3b2103f
    {
        version = "v140",
        date = "2026-04-25",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "全能信息条: 兼容按下施法打开或者关闭",
                "属性统计: 坦克职业显示【血量】",
                "移除百宝箱功能: 自动禁用【按下施法】",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v135|wrath|8b675d8fef9535e8e397cc794f4c19c1b11fd9ed9e452029ed17845cad3f9e7b
    {
        version = "v135",
        date = "2026-04-22",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "修复：全能信息条无法打开天赋面板的问题",
            },
            enUS = {
            },
        },
    },
-- YUI-Notes-Record: v134|wrath|2c37ccd46d5582c98a173f6fff38c7c18aa90fe621d07d2adfcccf891c840ab0
    {
        version = "v134",
        date = "2026-04-21",
        clients = { "Wrath" },
        content = {
            zhCN = {
                "耐久与坐骑：新增【显示模式】设置，支持最低值（默认）、平均值或者同时显示",
                "专业技能：点击信息条上的【采矿】现在能正确打开【熔炼】",
            },
            enUS = {
            },
        },
    },
})
