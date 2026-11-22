local YUI = _G.YUI
YUI.Dev = YUI.Dev or {}

function YUI.Dev:HandleBagSortSlash(args)
    local command, rest = args:match("^(%S+)%s*(.*)$")
    if not command or command:lower() ~= "bagsort" then return false end

    if not self.BagSortBenchmark and not YUI.API.Bags.InCombat() then
        local loadAddon = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if loadAddon then loadAddon("YUI_BagsDev") end
    end
    if self.BagSortBenchmark then
        self.BagSortBenchmark:Command(rest)
    else
        local message = "背包测速不可用，请在脱战后确认已安装并启用 YUI_BagsDev。"
        if YUI.Print then YUI:Print(message) else print(message) end
    end
    return true
end
