local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end
local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"

-- 检查 EnhanceQoL 是否启用
if not C_AddOns.IsAddOnLoaded("EnhanceQoL") then return end

local channels = {
    { type = "SAY", check = function() return true end },
    { type = "PARTY", check = function() return IsInGroup() end },
    { type = "RAID", check = function() return IsInRaid() end },
    { type = "INSTANCE_CHAT", check = function() return select(2, IsInInstance()) == "pvp" end },
    { type = "GUILD", check = function() return IsInGuild() end },
}

local orig_ChatEdit_CustomTabPressed = nil

local function ChatEdit_CustomTabPressed_Inner(self)
    -- 如果输入框以 "/" 开头（正在输入命令），则不处理，交给系统默认逻辑（命令补全）
    if string.sub(tostring(self:GetText()), 1, 1) == "/" then
        if orig_ChatEdit_CustomTabPressed then
            return orig_ChatEdit_CustomTabPressed(self)
        end
        return false
    end

    local currChatType = self:GetAttribute("chatType")
    
    -- 密语目标循环由 Blizzard 原生输入框处理
    if (currChatType == "WHISPER" or currChatType == "BN_WHISPER") then
        if orig_ChatEdit_CustomTabPressed then
            return orig_ChatEdit_CustomTabPressed(self)
        end
        return false
    end

    -- 找到当前频道的索引
    local currIndex = 1
    for i, ch in ipairs(channels) do
        if ch.type == currChatType then
            currIndex = i
            break
        end
    end

    -- 决定步长
    local step = IsShiftKeyDown() and -1 or 1
    local numChannels = #channels

    -- 循环寻找下一个可用的频道
    for i = 1, numChannels do
        currIndex = (currIndex + step - 1) % numChannels + 1
        if channels[currIndex].check() then
            self:SetAttribute("chatType", channels[currIndex].type)
            ChatEdit_UpdateHeader(self)
            return true
        end
    end

    if orig_ChatEdit_CustomTabPressed then
        return orig_ChatEdit_CustomTabPressed(self)
    end
    
    return false
end

local function OnEnable(enable)
    if enable then
        if not orig_ChatEdit_CustomTabPressed and _G.ChatEdit_CustomTabPressed ~= ChatEdit_CustomTabPressed_Inner then
            orig_ChatEdit_CustomTabPressed = _G.ChatEdit_CustomTabPressed
        end
        _G.ChatEdit_CustomTabPressed = ChatEdit_CustomTabPressed_Inner
    else
        if _G.ChatEdit_CustomTabPressed == ChatEdit_CustomTabPressed_Inner then
            _G.ChatEdit_CustomTabPressed = orig_ChatEdit_CustomTabPressed
        end
    end
end

Components:RegisterFeature("TabChat", {
    product = PRODUCT_ID,
    name = "Tab键切换频道",
    description = "使用 Tab 键在 说、队伍、团队、副本、公会 频道之间快速切换。按住 Shift+Tab 可反向切换。",
    default = true,
    callback = OnEnable,
})
