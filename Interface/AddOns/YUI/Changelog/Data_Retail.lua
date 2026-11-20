-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v362|mainline|ec50b3b1da1f9a700e8dae768f090dc293c975696e1aea8b0bb0e1e0bb22b59a
    {
        version = "v362",
        date = "2026-11-21",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复物品补入已有堆叠后，背包满时无法拖动该堆物品的问题。",
                "修复背包装备升级箭头误提示角色当前无法穿戴的装备。",
                "修复分类布局下配方染色偶尔未更新的问题。",
                "修复 Halo 部分增益计时条刷新时的报错。",
            },
            enUS = {
                "Fixed stacks becoming undraggable after receiving more items when bags are full.",
                "Fixed upgrade arrows appearing on gear your character cannot currently equip.",
                "Fixed recipe colors sometimes failing to refresh in the category layout.",
                "Fixed an error when refreshing some Halo buff timers.",
            },
        },
    },
-- YUI-Notes-Record: v361|mainline|4babaa83f56ea54d7a5748c833824c7b127261fbf7f9e92c5b05f007356c680c
    {
        version = "v361",
        date = "2026-11-20",
        clients = { "Retail" },
        content = {
            zhCN = {
                "新增 YUI 背包（分类整理、跨角色离线库存）。",
                "Halo 新增吃喝倒计时。",
                "修复宠物条键位裁切、换角色方案漏应用和长报错复制。",
                "减少地图标记重复刷新。",
            },
            enUS = {
                "Added YUI Bags with item categories and offline inventory across characters.",
                "Halo now tracks eating and drinking timers.",
                "Fixed clipped pet bar keybinds, profiles failing to apply after switching characters, and copying long error reports.",
                "Reduced duplicate map marker refreshes.",
            },
        },
    },
-- YUI-Notes-Record: v360|mainline|802709cb8ab85bcf325574067aee959393ddc5b01954d12e41fb453b12e76258
    {
        version = "v360",
        date = "2026-11-14",
        clients = { "Retail" },
        content = {
            zhCN = {
                "插件助手支持清理未安装记录，并修复“新”标记和分组状态显示。",
                "优化信息条专业等级配色，未满级不再显示为错误色。",
                "修复隐藏地图标记后，筛选按钮未同步灰显的问题。",
            },
            enUS = {
                "Addon Assistant can now remove uninstalled addon records, with fixes to “New” markers and group-status displays.",
                "Improved profession-rank colors so ranks below the cap no longer use an error color.",
                "Fixed the filter button not turning gray when map markers are hidden.",
            },
        },
    },
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
})
