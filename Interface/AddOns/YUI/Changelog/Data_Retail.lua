-- Generated from Docs/Products/YUI/CHANGELOG.md; do not edit. Latest 10 versions per client.
local CL = _G.YUI.Changelog
CL:Register("suite", {
-- YUI-Notes-Record: v366|mainline|8a4778a810356834d8c4915228d1396403a02a915856f01b59661914371eafa4
    {
        version = "v366",
        date = "2026-11-24",
        clients = { "Retail" },
        content = {
            zhCN = {
                "Orbit 好友提示显示魔兽角色等级，好友和公会弹层不再遮挡中文选字框。",
                "修复 Flare 载具退出按钮偏离设定位置。",
            },
            enUS = {
                "Orbit’s friends tooltip shows WoW character levels. Friends and guild popups stay clear of Chinese input suggestions.",
                "Fixed Flare’s Leave Vehicle button moving away from its set position.",
            },
        },
    },
-- YUI-Notes-Record: v365|mainline|7416ed90c82e5fa7cbadebede05719da405243cc5af0584c8d785704540b7712
    {
        version = "v365",
        date = "2026-11-22",
        clients = { "Retail" },
        content = {
            zhCN = {
                "Halo 支持设置倒计时从几秒开始显示小数。",
                "修复 Halo 部分光环结束后仍然发光的问题。",
            },
            enUS = {
                "Halo lets you choose when countdowns start showing decimals.",
                "Fixed lingering Halo glows after some auras ended.",
            },
        },
    },
-- YUI-Notes-Record: v364|mainline|381f0d3cc8b0a37b858fb8e0ee7bf7d8672e53d228ba401efc7d2b9e2df6d4c6
    {
        version = "v364",
        date = "2026-11-22",
        clients = { "Retail" },
        content = {
            zhCN = {
                "修复战斗中地图标记消失。",
                "修复 Halo 常驻减益图标不亮。",
            },
            enUS = {
                "Fixed map markers disappearing in combat.",
                "Fixed Halo’s always-visible debuff icons staying dim.",
            },
        },
    },
-- YUI-Notes-Record: v363|mainline|769ca756513c5592e0031b1bbca3e66c08e9bc09cc9d2af74793cdf9abfe7aed
    {
        version = "v363",
        date = "2026-11-21",
        clients = { "Retail" },
        content = {
            zhCN = {
                "暂停 YUI 背包，恢复游戏原生背包。",
            },
            enUS = {
                "Temporarily restored the default bag interface.",
            },
        },
    },
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
})
