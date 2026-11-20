local YUI = _G.YUI
if not YUI or not YUI.IsForever then return end

local words = {
    items = {"Items", "物品", "物品"},
    log = {"Item log", "物品记录", "物品紀錄"},
    moneylog = {"Money log", "金币记录", "金幣紀錄"},
    info = {"Tab info", "库页说明", "分頁說明"},
    permissions = {"Rank permissions", "会阶权限", "會階權限"},
    permissionNext = {"In the roster, click Guild Settings, then select Bank Tab Permissions and the rank to edit.", "在名册右下方点「公会设置」，再选「银行标签许可」和要修改的会阶。", "在名冊右下方點「公會設定」，再選銀行分頁權限及要修改的會階。"},
    permissionRoute = {"Open Guild & Communities, select Roster, then Guild Settings. Choose Bank Tab Permissions and the rank to edit.", "打开「公会与社区」→「名册」→「公会设置」，选择「银行标签许可」，再选要修改的会阶。", "開啟「公會與社群」→「名冊」→「公會設定」，選擇銀行分頁權限，再選要修改的會階。"},
    needsPage = {"Requires a guild bank tab you can view.", "需要至少一个有查看权限的库页。", "需要至少一個有檢視權限的分頁。"},
    withdrawDenied = {"Your rank cannot withdraw guild funds.", "你的会阶没有提取公会金币的权限。", "你的會階沒有提領公會金幣的權限。"},
    quotaUsed = {"You have reached your daily gold withdrawal limit.", "你今天的金币提取额度已用完。", "你今天的金幣提領額度已用完。"},
    emptyVault = {"The guild bank has no funds to withdraw.", "公会银行余额为零。", "公會銀行餘額為零。"},
    emptyWallet = {"You have no money to deposit.", "你身上没有可存入的金币。", "你身上沒有可存入的金幣。"},
    inCombat = {"Available after combat.", "脱离战斗后可用。", "脫離戰鬥後可用。"},
    quickTarget = {"Tab: %s", "当前库页：%s", "目前分頁：%s"},
    depositDenied = {"Your rank cannot deposit items into this tab.", "你的会阶不能向这个库页存放物品。", "你的會階不能在這個分頁存放物品。"},
    quickUnavailable = {"Depositing requires a confirmed tab you can deposit into.", "库页数据确认且有存放权限后可用。", "分頁資料確認且有存放權限後可用。"},
    balance = {"Guild funds  %s", "公会余额  %s", "公會餘額  %s"},
    available = {"Available  %s", "本人可提  %s", "本人可提  %s"},
    deposit = {"Deposit", "存入金币", "存入金幣"},
    withdraw = {"Withdraw", "提取金币", "提取金幣"},
    purchase = {"Buy tab", "购买库页", "購買分頁"},
    first = {"Purchase the first guild bank tab", "购买第一个公会银行库页", "購買第一個公會銀行分頁"},
    next = {"Purchase guild bank tab %d", "购买第 %d 个公会银行库页", "購買第 %d 個公會銀行分頁"},
    purchased = {"%d of %d tabs purchased", "已购 %d / %d 页", "已購 %d / %d 頁"},
    price = {"Tab price  %s", "库页价格  %s", "分頁價格  %s"},
    afterPurchase = {"Guild funds after purchase  %s", "购买后公会余额  %s", "購買後公會餘額  %s"},
    funds = {"The guild needs another %s.", "公会余额还差 %s。", "公會餘額還差 %s。"},
    fundsDeposit = {"Another %s is needed. Use Deposit below to add funds.", "还差 %s，可在下方存入金币。", "還差 %s，可在下方存入金幣。"},
    leaderBuy = {"Only the guild leader can purchase a tab.", "只有会长可以购买库页。", "只有會長可以購買分頁。"},
    unopened = {"Your guild has not bought its first tab yet.", "公会尚未购买首个库页。", "公會尚未購買首個分頁。"},
    full = {"All purchasable tabs are unlocked.", "已购齐所有可购买的库页。", "已購齊所有可購買的分頁。"},
    loading = {"Loading…", "读取中…", "讀取中…"},
    buying = {"Waiting for the new tab…", "等待新库页确认…", "等待新分頁確認…"},
    emptyLog = {"No transactions to display.", "暂无记录", "暫無紀錄"},
    guildScope = {"Entire guild", "全公会", "全公會"},
    logCount = {"Entries: %d", "%d 条记录", "%d 筆紀錄"},
    readOnly = {"Read only", "只读", "唯讀"},
    editable = {"Editable", "可编辑", "可編輯"},
    emptyNote = {"This tab has no description.", "这个库页还没有说明。", "這個分頁還沒有說明。"},
    writeNote = {"Click here to add a tab description.", "点击此处填写库页说明。", "點此填寫分頁說明。"},
    save = {"Save changes", "保存修改", "儲存變更"},
    saving = {"Waiting for confirmation…", "等待保存确认…", "等待儲存確認…"},
    conflict = {"Tab info changed. Cancel to load the latest text.", "库页说明已被修改，点取消可载入最新内容。", "分頁說明已被修改，點取消可載入最新內容。"},
    unlimited = {"Unlimited", "无限", "無限"},
    invalidAmount = {"The amount exceeds the available funds or allowance.", "金额超出当前余额或提取额度。", "金額超出目前餘額或提取額度。"},
    changed = {"The guild bank has changed. Check the current details.", "公会银行状态已变化，请检查当前信息。", "公會銀行狀態已變更，請檢查目前資訊。"},
}
for i, locale in ipairs({"enUS", "zhCN", "zhTW"}) do
    if not YUI.Locale.ShouldLoad or YUI.Locale:ShouldLoad(locale) then
        local entries = {}
        for key, values in pairs(words) do entries["guild.service." .. key] = values[i] end
        YUI.Locale:Register("YBags", locale, entries)
    end
end
