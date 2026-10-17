--[[
	Chinese Simplified Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'zhCN')
if not L then return end

--keybindings
L.OpenBags = '切换背包'
L.OpenBank = '切换银行'
L.OpenGuild = '切换公会银行'
L.OpenVault = '切换虚空仓库'

--terminal
L.Commands = '命令列表'
L.CmdShowInventory = '切换背包'
L.CmdShowBank = '切换银行'
L.CmdShowGuild = '切换公会银行'
L.CmdShowVault = '切换虚空仓库'
L.CmdShowVersion = '列出当前版本'
L.CmdShowOptions = '打开配置菜单'
L.CmdReset = '清除设置和缓存数据'
L.ResetConfirm = '你确定要重置 %s 吗？|n所有设置和缓存数据都将丢失。'
L.SkinError = '应用外观时发生错误。'
L.UpgradeError = '升级设置时发生问题。如果遇到问题，请尝试重置设置。'

--titles
L.TitleBags = '%s的背包'
L.TitleBank = '%s的银行'
L.TitleVault = '%s的虚空仓库'
L.NormalBags = '普通背包'
L.TradeBags = '专业包'
L.AmmoBags = '弹药袋'

--tooltips
L.Bags = '背包'
L.Drag = '<拖动>'
L.BrowseItems = '浏览物品'
L.HideBag = '点击隐藏此背包。'
L.ShowBag = '点击显示此背包。'
L.GuildFunds = '公会基金'
L.NumAllowed = '%s 允许'
L.NumWithdraw = '%d取出'
L.NumDeposit = '%d存入'
L.NumRemaining = '剩余 %s'
L.WarbandMoney = '战团金币'
L.OfflineViewing = '离线查看'
L.Others = '其他'

--menus
L.Characters = '角色'
L.Guilds = '公会'
L.Locations = '位置'
L.EnterDescription = '输入描述：'
L.ServerSorting = '服务器端排序'
L.ReverseSorting = '反向排序'
L.PartialFirst = '部分堆叠优先'
L.CleanupOptions = '清理选项'
L.IncludeReagents = '包含材料'
L.LockItems = '锁定物品槽'

--dialogs
L.AskMafia = '问问大佬'
L.ConfirmDelete = '确定要删除 %s 的缓存数据？'
L.ConfirmTransfer = '存入任一物品将移除全部修改并使其不可交易和不可退款。|n|n希望继续？'
L.CannotPurchaseVault = '没有足够的货币解锁虚空仓库服务|n|n|cffff2020花费：%s|r'
L.PurchaseVault = '希望解锁虚空仓库？|n|n|cffffd200花费：|r %s'
L.ConfigurationMode = '您现在处于客户端排序配置模式。|n|n点击物品槽来切换它们在排序时是否应该被锁定。'
L.OutOfDate = '你的 |cffffd200%s|r 版本可能已过期！|n%s 报告拥有 |cff82c5ff%s|r，如果是真的，请更新。'
L.InvalidVersion = '你的 |cffffd200%s|r 副本已损坏或非法。|n请免费下载官方版本。'
