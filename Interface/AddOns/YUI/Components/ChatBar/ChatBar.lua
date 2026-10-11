local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end
local GUI2 = YUI.GUI2
local F = YUI.F
local L = YUI.Locale or {}
local CoreLocale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("Core") or {}
local Assets = YUI.Assets
local CombatAPI = YUI.API and YUI.API.Combat
local SystemAPI = YUI.API and YUI.API.System
local FrameAPI = YUI.API and YUI.API.Frame
local ChatInput = YUI.API and YUI.API.ChatInput
local DefaultChatFrame = _G.DEFAULT_CHAT_FRAME

-- 确保 Components 存在
if not YUI.Components then return end
local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"

-- 引入 LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0")
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded

local ChatBar = {}
YUI.ChatBar = ChatBar
local frame
local buttons = {}
local isCollapsed = false
local chatBarActive = false
local channelRequestSerial = 0
local WhisperNotifyEventOwner = {}
local ChatFadeEventOwner = {}
local ChatFadeAnimationOwner = {}
local linkedFadeHidden = false
local CHATBAR_LAYOUT_ID = "yui.component.chatbar"
local CHATBAR_PLACEMENT_VERSION = 2
local MAX_CUSTOM_BUTTONS = 8
local MAX_CUSTOM_COMMAND_BYTES = 255
local MAX_CUSTOM_TEXT_CHARACTERS = 6
local MAX_CUSTOM_TITLE_CHARACTERS = 80
local CUSTOM_BUTTON_PREFIX = "CUSTOM:"
local GetChatBarGeometry
local PointCoordinates
local OnButtonRightClick

local function ChatBarText(key, fallback)
    return CoreLocale[key] or fallback
end

-- 默认配置
local defaults = {
    style = "TEXT",
    direction = "RIGHT",
    reverse = false,
    width = 20,
    height = 20,
    spacing = 5,
    autoHide = false,
    -- 新增配置
    blockTexture = "Interface\\Buttons\\WHITE8x8",
    blockShadow = true,
    notifyPosition = "RIGHT",
    notifyTextOffsetX = 0,
    notifyTextOffsetY = 0,
    maskWhisperName = true,
    iconOffsetX = 0,
    iconOffsetY = 0,
    font = "默认",
    locked = false,
    channelColors = {},
    channelOrder = {},
    customButtonSerial = 0,
    customButtons = {},
    channels = {
        SAY = true,
        YELL = true,
        PARTY = true,
        INSTANCE_CHAT = true,
        RAID = true,
        RAID_WARNING = true,
        GUILD = true,
        WORLD = true,
        ROLL = true,
        RL = false,
        LEAVE = false,
    },
    pos = {"LEFT", "UIParent", "LEFT", 100, 0}
}

if not YUI.IsRetail then
    defaults.channels.LFG = true
    defaults.channels.ATLASLOOT = true
    defaults.channels.BIAOGE = true
else
    defaults.channels.KEYSTONELOOT = true
end

-- 获取配置表 (处理与 Components 开关状态的冲突)
local function GetDB()
    if not Components or not Components.GetStore then return {} end
    local store = Components:GetStore(PRODUCT_ID)
    if type(store) ~= "table" then return {} end

    if type(store.ChatBar) == "table" then
        if type(store.ChatBar_Config) ~= "table" then
            store.ChatBar_Config = {}
        end
        for k, v in pairs(store.ChatBar) do
            if store.ChatBar_Config[k] == nil then
                store.ChatBar_Config[k] = v
            end
        end
        store.ChatBar = true
    end

    if Components.EnsureConfig then
        return Components:EnsureConfig("ChatBar_Config", defaults, PRODUCT_ID) or {}
    end
    return store.ChatBar_Config or {}
end

-- 频道定义
local CHANNELS = {
    { key = "SAY", name = ChatBarText("chatbar.channel.say.short", "S"), tooltip = ChatBarText("chatbar.channel.say", "Say"), color = {1, 1, 1}, command = "/s ", icon = Assets:Core("images\\icons\\chat\\say") },
    { key = "YELL", name = ChatBarText("chatbar.channel.yell.short", "Y"), tooltip = ChatBarText("chatbar.channel.yell", "Yell"), color = {1, 0.25, 0.25}, command = "/y ", icon = Assets:Core("images\\icons\\chat\\yell") },
    { key = "PARTY", name = ChatBarText("chatbar.channel.party.short", "P"), tooltip = ChatBarText("chatbar.channel.party", "Party"), color = {0.67, 0.67, 1}, command = "/p ", icon = Assets:Core("images\\icons\\chat\\party") },
    { key = "INSTANCE_CHAT", name = ChatBarText("chatbar.channel.instance.short", "I"), tooltip = ChatBarText("chatbar.channel.instance", "Instance"), color = {1, 0.7, 0.2}, command = "/i ", icon = Assets:Core("images\\icons\\chat\\raid") },
    { key = "RAID", name = ChatBarText("chatbar.channel.raid.short", "R"), tooltip = ChatBarText("chatbar.channel.raid", "Raid"), color = {1, 0.5, 0}, command = "/raid ", icon = Assets:Core("images\\icons\\chat\\raid") },
    { key = "RAID_WARNING", name = ChatBarText("chatbar.channel.raid_warning.short", "RW"), tooltip = ChatBarText("chatbar.channel.raid_warning", "Raid Warning"), color = {1, 0.28, 0}, command = "/rw ", icon = Assets:Core("images\\icons\\chat\\raid") },
    { key = "GUILD", name = ChatBarText("chatbar.channel.guild.short", "G"), tooltip = ChatBarText("chatbar.channel.guild", "Guild"), color = {0.25, 1, 0.25}, command = "/g ", icon = Assets:Core("images\\icons\\chat\\guild") },
}

if not YUI.IsRetail then
    table.insert(CHANNELS, { key = "LFG", name = ChatBarText("chatbar.channel.lfg.short", "LFG"), tooltip = ChatBarText("chatbar.channel.lfg", "Looking For Group"), color = {0.5, 0.5, 1}, command = "LFG", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" })
end

table.insert(CHANNELS, { key = "WORLD", name = ChatBarText("chatbar.channel.world.short", "W"), tooltip = ChatBarText("chatbar.channel.world", "World Channel"), color = {1, 0.75, 0.75}, command = "WORLD", icon = Assets:Core("images\\icons\\chat\\world") })
table.insert(CHANNELS, { key = "ROLL", name = ChatBarText("chatbar.channel.roll.short", "D"), tooltip = ChatBarText("chatbar.channel.roll", "Roll"), color = {1, 1, 0}, command = "ROLL", icon = Assets:Core("images\\icons\\chat\\roll") })

if not YUI.IsRetail then
    table.insert(CHANNELS, { key = "ATLASLOOT", name = ChatBarText("chatbar.channel.loot.short", "L"), tooltip = ChatBarText("chatbar.channel.loot", "Loot Browser"), color = {0, 1, 0}, command = "/atlasloot", execute = true, icon = "Interface\\Icons\\INV_Box_01" })
    table.insert(CHANNELS, { key = "BIAOGE", name = ChatBarText("chatbar.channel.ledger.short", "G"), tooltip = ChatBarText("chatbar.channel.ledger", "Raid Ledger"), color = {1, 1, 0}, command = "/biaoge", execute = true, icon = "Interface\\Icons\\INV_Misc_Coin_02" })
else
    table.insert(CHANNELS, { key = "KEYSTONELOOT", name = ChatBarText("chatbar.channel.vault.short", "V"), tooltip = ChatBarText("chatbar.channel.loot", "Loot Browser"), color = {0.64, 0.21, 0.93}, icon = "Interface\\Icons\\INV_Relics_Hourglass_02" })
end

if YUI.IsForever then
    defaults.channels.ATLASLOOT = nil
    defaults.channels.BIAOGE = nil
    defaults.channels.DUNGEONSFOREVER = true
    for index = #CHANNELS, 1, -1 do
        local key = CHANNELS[index].key
        if key == "ATLASLOOT" or key == "BIAOGE" or key == "KEYSTONELOOT" then
            table.remove(CHANNELS, index)
        end
    end
    table.insert(CHANNELS, { key = "DUNGEONSFOREVER", name = ChatBarText("chatbar.channel.loot.short", "L"), tooltip = ChatBarText("chatbar.dungeons_forever.title", "DungeonsForever"), color = {0, 1, 0}, icon = "Interface\\Icons\\INV_Box_01" })
end

table.insert(CHANNELS, {
    key = "RL",
    name = "RL",
    tooltip = ChatBarText("chatbar.reload.title", "Reload UI"),
    color = { 1, 0.35, 0.1 },
    systemAction = "RELOAD",
})

local CHANNELS_BY_KEY = {}
table.insert(CHANNELS, {
    key = "LEAVE",
    name = ChatBarText("chatbar.leave.short", "Leave"),
    tooltip = ChatBarText("chatbar.leave.title", "Leave Group and Reset"),
    color = { 1, 0.2, 0.2 },
    systemAction = "LEAVE",
})
for _, info in ipairs(CHANNELS) do
    CHANNELS_BY_KEY[info.key] = info
end

local BLOCKED_SLASH_COMMAND_GROUPS = {
    "SCRIPT",
    "DUMP",
}

local BLOCKED_SLASH_COMMAND_LITERALS = {
    ["/RUN"] = true,
    ["/SCRIPT"] = true,
    ["/DUMP"] = true,
}

local function TrimString(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
end

local function Utf8Length(value)
    if type(value) ~= "string" then return 0 end
    if type(_G.strlenutf8) == "function" then
        local ok, length = pcall(_G.strlenutf8, value)
        if ok and type(length) == "number" then return length end
    end
    local length = 0
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 128 or byte >= 192 then length = length + 1 end
    end
    return length
end

local function HasControlCharacter(value)
    if type(value) ~= "string" then return true end
    for index = 1, #value do
        if value:byte(index) < 32 then return true end
    end
    return false
end

local function IsBlockedSlashCommand(command)
    local slash = type(command) == "string" and command:match("^(%S+)") or nil
    if not slash then return false end
    slash = slash:upper()
    if BLOCKED_SLASH_COMMAND_LITERALS[slash] then return true end
    for _, commandGroup in ipairs(BLOCKED_SLASH_COMMAND_GROUPS) do
        local index = 1
        while true do
            local alias = _G["SLASH_" .. commandGroup .. index]
            if not alias then break end
            if type(alias) == "string" and alias:upper() == slash then return true end
            index = index + 1
        end
    end
    return false
end

local function NormalizeCustomCommand(value)
    if value == nil or value == "" then return "" end
    if type(value) ~= "string" then return nil, "invalid_type" end
    if #value > MAX_CUSTOM_COMMAND_BYTES or HasControlCharacter(value) then
        return nil, "invalid_string"
    end
    value = TrimString(value)
    if value == "" then return "" end
    if value:sub(1, 1) ~= "/" then return nil, "missing_slash" end
    if IsBlockedSlashCommand(value) then return nil, "blocked_command" end
    return value
end

local function ClampColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function CopyCustomButton(source)
    source = type(source) == "table" and source or {}
    local color = type(source.color) == "table" and source.color or {}
    local actions = type(source.actions) == "table" and source.actions or {}
    return {
        id = source.id,
        enabled = source.enabled == true,
        text = source.text or "",
        title = source.title or "",
        color = { color[1] or 1, color[2] or 0.82, color[3] or 0 },
        actions = {
            LeftButton = actions.LeftButton or "",
            RightButton = actions.RightButton or "",
            MiddleButton = actions.MiddleButton or "",
        },
    }
end

local CUSTOM_BUTTON_FIELDS = {
    id = true,
    enabled = true,
    text = true,
    title = true,
    color = true,
    actions = true,
}

local CUSTOM_ACTION_FIELDS = {
    LeftButton = true,
    RightButton = true,
    MiddleButton = true,
}

local function NormalizeCustomButton(source, strict, seenIds, nextId)
    if type(source) ~= "table" then return nil, "invalid_custom_button" end
    if strict then
        for key in pairs(source) do
            if not CUSTOM_BUTTON_FIELDS[key] then return nil, "unexpected_custom_field" end
        end
    end

    local id = tonumber(source.id)
    if id then id = math.floor(id) end
    if not id or id < 1 or seenIds[id] then
        if strict then return nil, "invalid_custom_id" end
        repeat
            nextId = nextId + 1
            id = nextId
        until not seenIds[id]
    end
    seenIds[id] = true
    if id > nextId then nextId = id end

    if strict and type(source.enabled) ~= "boolean" then return nil, "invalid_custom_enabled" end
    local text = TrimString(source.text)
    local title = TrimString(source.title)
    if not text or text == "" or HasControlCharacter(text)
        or Utf8Length(text) > MAX_CUSTOM_TEXT_CHARACTERS then
        if strict then return nil, "invalid_custom_text" end
        text = ChatBarText("chatbar.custom.default_text", "BTN")
    end
    if not title or title == "" or HasControlCharacter(title)
        or Utf8Length(title) > MAX_CUSTOM_TITLE_CHARACTERS then
        if strict then return nil, "invalid_custom_title" end
        title = text
    end

    local sourceColor = source.color
    if strict and (type(sourceColor) ~= "table"
        or tonumber(sourceColor[1]) == nil or tonumber(sourceColor[2]) == nil or tonumber(sourceColor[3]) == nil
        or tonumber(sourceColor[1]) < 0 or tonumber(sourceColor[1]) > 1
        or tonumber(sourceColor[2]) < 0 or tonumber(sourceColor[2]) > 1
        or tonumber(sourceColor[3]) < 0 or tonumber(sourceColor[3]) > 1) then
        return nil, "invalid_custom_color"
    end
    sourceColor = type(sourceColor) == "table" and sourceColor or {}
    local color = {
        ClampColorComponent(sourceColor[1], 1),
        ClampColorComponent(sourceColor[2], 0.82),
        ClampColorComponent(sourceColor[3], 0),
    }

    local sourceActions = source.actions
    if strict and type(sourceActions) ~= "table" then return nil, "invalid_custom_actions" end
    sourceActions = type(sourceActions) == "table" and sourceActions or {}
    if strict then
        for key in pairs(sourceActions) do
            if not CUSTOM_ACTION_FIELDS[key] then return nil, "unexpected_custom_action" end
        end
    end
    local actions = {}
    local hasAction = false
    for _, mouseButton in ipairs({ "LeftButton", "RightButton", "MiddleButton" }) do
        local command, code = NormalizeCustomCommand(sourceActions[mouseButton])
        if not command then
            if strict then return nil, code end
            command = ""
        end
        actions[mouseButton] = command
        hasAction = hasAction or command ~= ""
    end
    if strict and not hasAction then return nil, "missing_custom_action" end

    return {
        id = id,
        enabled = source.enabled == true,
        text = text,
        title = title,
        color = color,
        actions = actions,
    }, nil, nextId
end

local function NormalizeCustomButtons(db, strict)
    if type(db) ~= "table" then return nil, "invalid_custom_buttons" end
    local source = db.customButtons
    if source == nil then source = {} end
    if type(source) ~= "table" then return nil, "invalid_custom_buttons" end
    if strict and #source > MAX_CUSTOM_BUTTONS then return nil, "too_many_custom_buttons" end

    local normalized = {}
    local seenIds = {}
    local nextId = math.max(0, math.floor(tonumber(db.customButtonSerial) or 0))
    local limit = math.min(#source, MAX_CUSTOM_BUTTONS)
    for index = 1, limit do
        local item, code, updatedId = NormalizeCustomButton(source[index], strict, seenIds, nextId)
        if not item then return nil, code end
        nextId = updatedId
        normalized[#normalized + 1] = item
    end
    if strict then
        local denseCount = 0
        for key in pairs(source) do
            if type(key) ~= "number" or key < 1 or key > #source or key ~= math.floor(key) then
                return nil, "invalid_custom_buttons"
            end
            denseCount = denseCount + 1
        end
        if denseCount ~= #source then return nil, "invalid_custom_buttons" end
    end
    db.customButtons = normalized
    db.customButtonSerial = nextId
    return db
end

local function ClampChannelColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function GetCustomButtonKey(id)
    return CUSTOM_BUTTON_PREFIX .. tostring(id)
end

local function GetCustomButtonByKey(db, key)
    if type(key) ~= "string" or key:sub(1, #CUSTOM_BUTTON_PREFIX) ~= CUSTOM_BUTTON_PREFIX then
        return nil
    end
    local id = tonumber(key:sub(#CUSTOM_BUTTON_PREFIX + 1))
    if not id then return nil end
    for _, customButton in ipairs(db.customButtons or {}) do
        if customButton.id == id then return customButton end
    end
    return nil
end

local function GetCustomButtonInfo(customButton)
    return {
        key = GetCustomButtonKey(customButton.id),
        name = customButton.text,
        tooltip = customButton.title,
        color = customButton.color,
        customButton = customButton,
    }
end

local function GetDefaultChannelOrder(db)
    local order = {}
    for _, info in ipairs(CHANNELS) do
        order[#order + 1] = info.key
    end
    for _, customButton in ipairs((db and db.customButtons) or {}) do
        order[#order + 1] = GetCustomButtonKey(customButton.id)
    end
    return order
end

local function EnsureChannelSettings(db)
    if type(db) ~= "table" then return db end

    NormalizeCustomButtons(db, false)

    if type(db.channels) ~= "table" then db.channels = {} end
    if YUI.IsRetail and db.channels.LOOT ~= nil then
        if db.channels.ROLL == nil then
            db.channels.ROLL = db.channels.LOOT == true
        end
        db.channels.LOOT = nil
    end
    for key, value in pairs(defaults.channels) do
        if db.channels[key] == nil then db.channels[key] = value end
    end

    if type(db.channelColors) ~= "table" then db.channelColors = {} end
    if YUI.IsRetail and db.channelColors.LOOT ~= nil then
        if db.channelColors.ROLL == nil then
            db.channelColors.ROLL = db.channelColors.LOOT
        end
        db.channelColors.LOOT = nil
    end
    for key, value in pairs(db.channelColors) do
        local info = CHANNELS_BY_KEY[key]
        if not info or type(value) ~= "table" then
            db.channelColors[key] = nil
        else
            local r = value[1] or value.r
            local g = value[2] or value.g
            local b = value[3] or value.b
            r, g, b = tonumber(r), tonumber(g), tonumber(b)
            if not (r and g and b) then
                db.channelColors[key] = nil
            else
                value[1] = ClampChannelColorComponent(r, info.color[1])
                value[2] = ClampChannelColorComponent(g, info.color[2])
                value[3] = ClampChannelColorComponent(b, info.color[3])
                value[4] = nil
            end
        end
    end

    local order = {}
    local seen = {}
    if type(db.channelOrder) == "table" then
        for _, savedKey in ipairs(db.channelOrder) do
            local key = YUI.IsRetail and savedKey == "LOOT" and "ROLL" or savedKey
            if (CHANNELS_BY_KEY[key] or GetCustomButtonByKey(db, key)) and not seen[key] then
                order[#order + 1] = key
                seen[key] = true
            end
        end
    end
    for _, info in ipairs(CHANNELS) do
        if not seen[info.key] then
            order[#order + 1] = info.key
            seen[info.key] = true
        end
    end
    for _, customButton in ipairs(db.customButtons) do
        local key = GetCustomButtonKey(customButton.id)
        if not seen[key] then
            order[#order + 1] = key
            seen[key] = true
        end
    end
    db.channelOrder = order
    return db
end

local function GetOrderedChannels(db)
    EnsureChannelSettings(db)
    local ordered = {}
    for _, key in ipairs(db.channelOrder) do
        local info = CHANNELS_BY_KEY[key]
        if not info then
            local customButton = GetCustomButtonByKey(db, key)
            if customButton then info = GetCustomButtonInfo(customButton) end
        end
        if info then ordered[#ordered + 1] = info end
    end
    return ordered
end

local function IsButtonEnabled(db, info)
    if info and info.customButton then return info.customButton.enabled == true end
    return info and db.channels and db.channels[info.key] == true
end

local function GetChannelColor(db, info)
    if info and info.customButton then return info.customButton.color end
    local custom = db and db.channelColors and db.channelColors[info.key]
    return type(custom) == "table" and custom or info.color
end

local function SetChannelColor(db, key, value)
    local info = CHANNELS_BY_KEY[key]
    if not info or type(value) ~= "table" then return false end
    local r = tonumber(value[1] or value.r)
    local g = tonumber(value[2] or value.g)
    local b = tonumber(value[3] or value.b)
    if not (r and g and b) then return false end
    if type(db.channelColors) ~= "table" then db.channelColors = {} end
    db.channelColors[key] = {
        ClampChannelColorComponent(r, info.color[1]),
        ClampChannelColorComponent(g, info.color[2]),
        ClampChannelColorComponent(b, info.color[3]),
    }
    return true
end

local function CopyChannelOrder(order)
    local copy = {}
    for index, key in ipairs(order or {}) do copy[index] = key end
    return copy
end

local function PrintChatBarMessage(message)
    local chatFrame = DefaultChatFrame or _G.DEFAULT_CHAT_FRAME
    if chatFrame and type(chatFrame.AddMessage) == "function" then
        chatFrame:AddMessage(message)
    end
end

local function PrintCommandMessage(key, fallback, command)
    local formatText = ChatBarText(key, fallback)
    local ok, message = pcall(string.format, formatText, tostring(command or ""))
    PrintChatBarMessage(ok and message or formatText)
end

local function ExecuteCustomCommand(command)
    local normalized, code = NormalizeCustomCommand(command)
    if not normalized or normalized == "" then
        if code == "blocked_command" then
            PrintCommandMessage("chatbar.command.blocked", "Blocked unsafe command: %s", command)
        end
        return false, code or "empty_command"
    end

    if YUI.IsForever and (normalized:lower():match("^/reload%s*$") or normalized:lower():match("^/rl%s*$")) then
        if FrameAPI and FrameAPI.ReloadUI then return FrameAPI.ReloadUI() end
        if type(_G.ReloadUI) == "function" then return _G.ReloadUI() end
        return false, "reload-unavailable"
    end

    local activeEditBox
    if type(_G.ChatEdit_GetActiveWindow) == "function" then
        local ok, value = pcall(_G.ChatEdit_GetActiveWindow)
        if ok then activeEditBox = value end
    end
    activeEditBox = activeEditBox or (DefaultChatFrame and DefaultChatFrame.editBox)
        or _G.ChatFrame1EditBox
    if not activeEditBox or type(activeEditBox.SetText) ~= "function"
        or type(_G.ChatEdit_SendText) ~= "function" then
        PrintCommandMessage("chatbar.command.failed", "Command failed: %s", normalized)
        return false, "chat_dispatch_unavailable"
    end
    local ok = pcall(function()
        activeEditBox:SetText(normalized)
        _G.ChatEdit_SendText(activeEditBox)
    end)
    if not ok then
        PrintCommandMessage("chatbar.command.failed", "Command failed: %s", normalized)
        return false, "command_failed"
    end
    return true
end

local function ReloadChatBarUI()
    if FrameAPI and type(FrameAPI.ReloadUI) == "function" then
        FrameAPI.ReloadUI()
        return true
    end
    if type(_G.ReloadUI) == "function" then
        _G.ReloadUI()
        return true
    end
    return false
end

local function IsKeystoneLootInstalled()
    local getInfo = SystemAPI and SystemAPI.GetAddOnInfo
    if type(getInfo) ~= "function" then return false end
    local ok, name = pcall(getInfo, "KeystoneLoot")
    return ok and type(name) == "string" and name ~= ""
end

local function OpenKeystoneLoot()
    if not IsKeystoneLootInstalled() then
        PrintChatBarMessage(ChatBarText("chatbar.keystone_loot.missing", "KeystoneLoot is not installed."))
        return false
    end

    local loaded = SystemAPI and SystemAPI.IsAddOnLoadedSafe
        and SystemAPI.IsAddOnLoadedSafe("KeystoneLoot") == true
    if not loaded and SystemAPI and type(SystemAPI.LoadAddOn) == "function" then
        pcall(SystemAPI.LoadAddOn, "KeystoneLoot")
        loaded = SystemAPI.IsAddOnLoadedSafe
            and SystemAPI.IsAddOnLoadedSafe("KeystoneLoot") == true
    end
    if not loaded then
        PrintChatBarMessage(ChatBarText("chatbar.keystone_loot.disabled", "KeystoneLoot is disabled."))
        return false
    end

    local slash = _G.SlashCmdList and _G.SlashCmdList.KEYSTONELOOT
    if type(slash) == "function" then
        local ok = pcall(slash, "")
        if ok then return true end
    end
    local keystoneLootFrame = _G.KeystoneLootFrame
    if keystoneLootFrame
        and type(keystoneLootFrame.IsShown) == "function"
        and type(keystoneLootFrame.SetShown) == "function"
    then
        local ok, shown = pcall(keystoneLootFrame.IsShown, keystoneLootFrame)
        if ok and type(shown) == "boolean" then
            return pcall(keystoneLootFrame.SetShown, keystoneLootFrame, not shown)
        end
    end
    return false
end

-- 设置 Tooltip 锚点 (智能判断位置与展开方向结合)
local function SetTooltipAnchor(self)
    local db = GetDB()
    local dir = db.direction
    
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    
    local x, y = self:GetCenter()
    if not x or not y then return end
    
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    
    if dir == "LEFT" or dir == "RIGHT" then
        if y > screenHeight / 2 then
            GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -4)
        else
            GameTooltip:SetPoint("BOTTOM", self, "TOP", 0, 4)
        end
    else
        if x > screenWidth / 2 then
            GameTooltip:SetPoint("RIGHT", self, "LEFT", -4, 0)
        else
            GameTooltip:SetPoint("LEFT", self, "RIGHT", 4, 0)
        end
    end
end

local function AddChatChannel(chatFrame, channelName)
    if chatFrame.AddChannel then
        chatFrame:AddChannel(channelName)
    else
        ChatFrame_AddChannel(chatFrame, channelName)
    end
end

-- 按钮点击处理
local function GetChannelEditBox()
    local function IsSafeBox(box)
        if type(_G.issecretvalue) == "function" then
            local ok, secret = pcall(_G.issecretvalue, box)
            if not ok or secret then return false end
        end
        return type(box) == "table" or type(box) == "userdata"
    end
    local util = _G.ChatFrameUtil
    local active = util and util.GetActiveWindow or _G.ChatEdit_GetActiveWindow
    if type(active) == "function" then
        local ok, box = pcall(active)
        if not ok then return nil end
        if IsSafeBox(box) then return box end
        if type(box) ~= "nil" then return nil end
    end
    local choose = util and util.ChooseBoxForSend or _G.ChatEdit_ChooseBoxForSend
    if type(choose) == "function" then
        local ok, box = pcall(choose)
        if ok and IsSafeBox(box) then return box end
    end
end

local function SwitchChatBarChannel(key)
    if not ChatInput or type(ChatInput.SwitchChannel) ~= "function" then return false end
    local editBox = GetChannelEditBox()
    if not editBox then return false end
    if key ~= "WORLD" and key ~= "LFG" then
        return ChatInput.SwitchChannel(editBox, key, nil, true)
    end
    local name = key == "WORLD" and "大脚世界频道" or "寻求组队"
    local function GetJoinedChannel()
        local ok, id = pcall(GetChannelName, name)
        if not ok or (_G.issecretvalue and _G.issecretvalue(id))
            or type(id) ~= "number" or id <= 0 then return nil end
        return id
    end
    local id = GetJoinedChannel()
    if id then return ChatInput.SwitchChannel(editBox, "CHANNEL", id, true) end
    local serial = channelRequestSerial
    JoinPermanentChannel(name)
    AddChatChannel(DefaultChatFrame, name)
    C_Timer.After(0.5, function()
        if not chatBarActive or serial ~= channelRequestSerial or GetChannelEditBox() ~= editBox then return end
        local joinedId = GetJoinedChannel()
        if joinedId then ChatInput.SwitchChannel(editBox, "CHANNEL", joinedId, true) end
    end)
    return false
end

local function OnButtonClick(key)
    local channel = CHANNELS_BY_KEY[key]
    if (YUI.IsRetail or YUI.IsForever) and (key == "WORLD" or key == "LFG"
        or (channel and channel.command and not channel.execute
            and key ~= "ROLL")) then
        return SwitchChatBarChannel(key)
    end
    if key == "ROLL" then
        RandomRoll(1, 100)
    elseif key == "RL" then
        ReloadChatBarUI()
    elseif key == "KEYSTONELOOT" then
        OpenKeystoneLoot()
    elseif key == "DUNGEONSFOREVER" and YUI.IsForever then
        local slash = _G.SlashCmdList and _G.SlashCmdList.DUNGEONSFOREVER
        if type(slash) == "function" then
            local ok = pcall(slash, "")
            if not ok then
                PrintChatBarMessage(ChatBarText("chatbar.dungeons_forever.failed", "Unable to open DungeonsForever."))
            end
        else
            PrintChatBarMessage(ChatBarText("chatbar.dungeons_forever.unavailable", "Please install and enable DungeonsForever."))
        end
    elseif key == "WORLD" then
        local channelID = GetChannelName("大脚世界频道")
        local autoJoined = false
        if channelID == 0 then
            JoinPermanentChannel("大脚世界频道")
            AddChatChannel(DefaultChatFrame, "大脚世界频道")
            channelID = GetChannelName("大脚世界频道")
            autoJoined = true
        end
        
        if channelID == 0 then return end
        
        local currentText = DEFAULT_CHAT_FRAME.editBox:GetText()
        local command = "/%s "
        if autoJoined then
            -- 延迟执行以等待频道加入完成
            C_Timer.After(0.5, function()
                local id = GetChannelName("大脚世界频道")
                if id > 0 then
                    ChatFrame_OpenChat(string.format(command, id) .. currentText, DEFAULT_CHAT_FRAME)
                end
            end)
        else
            ChatFrame_OpenChat(string.format(command, channelID) .. currentText, DEFAULT_CHAT_FRAME)
        end
    elseif key == "LFG" then
        local channelID = GetChannelName("寻求组队")
        local autoJoined = false
        if channelID == 0 then
            JoinPermanentChannel("寻求组队")
            AddChatChannel(DefaultChatFrame, "寻求组队")
            channelID = GetChannelName("寻求组队")
            autoJoined = true
        end
        
        if channelID == 0 then return end
        
        local currentText = DEFAULT_CHAT_FRAME.editBox:GetText()
        local command = "/%s "
        if autoJoined then
            -- 延迟执行以等待频道加入完成
            C_Timer.After(0.5, function()
                local id = GetChannelName("寻求组队")
                if id > 0 then
                    ChatFrame_OpenChat(string.format(command, id) .. currentText, DEFAULT_CHAT_FRAME)
                end
            end)
        else
            ChatFrame_OpenChat(string.format(command, channelID) .. currentText, DEFAULT_CHAT_FRAME)
        end
    else
        for _, info in ipairs(CHANNELS) do
            if info.key == key then
                if info.execute then
                    local editBox = DEFAULT_CHAT_FRAME.editBox
                    editBox:SetText(info.command)
                    ChatEdit_SendText(editBox)
                else
                    ChatFrame_OpenChat(info.command)
                end
                break
            end
        end
    end
end

local function OnRuntimeButtonClick(info, mouseButton)
    channelRequestSerial = channelRequestSerial + 1
    if not info then return false end
    if info.key == "LEAVE" then
        local social = YUI.API and YUI.API.Social
        local action = social and (mouseButton == "LeftButton" and social.LeaveGroupOrDelve
            or mouseButton == "RightButton" and social.ResetInstances)
        if type(action) ~= "function" then return false end
        local ok = action()
        if not ok then
            PrintChatBarMessage(ChatBarText("chatbar.leave.failed", "Unable to leave or reset right now."))
        end
        return ok
    end
    if info.customButton then
        local actions = info.customButton.actions
        local command = type(actions) == "table" and actions[mouseButton] or nil
        if command and command ~= "" then return ExecuteCustomCommand(command) end
        return false, "empty_command"
    end
    if mouseButton == "RightButton" then
        OnButtonRightClick(info.key)
        return true
    end
    if mouseButton == "MiddleButton" then return false, "empty_command" end
    OnButtonClick(info.key)
    return true
end

local function IsGreatVaultAvailable()
    return SystemAPI
        and type(SystemAPI.IsGreatVaultAvailable) == "function"
        and SystemAPI.IsGreatVaultAvailable() == true
end

local function OpenGreatVault()
    if not IsGreatVaultAvailable()
        or not SystemAPI
        or type(SystemAPI.OpenGreatVault) ~= "function"
    then
        return false
    end
    return SystemAPI.OpenGreatVault() == true
end

function ChatBar:SetLinkedFadeHidden(hidden, duration)
    linkedFadeHidden = hidden == true
    if frame and type(frame.SetAlpha) == "function" then
        local targetAlpha = linkedFadeHidden and 0 or 1
        local animation = YUI.Animation
        local currentAlpha = type(frame.GetAlpha) == "function" and frame:GetAlpha() or nil
        if animation
            and type(animation.Fade) == "function"
            and type(currentAlpha) == "number"
            and type(duration) == "number"
            and duration > 0
        then
            animation:Fade(frame, currentAlpha, targetAlpha, {
                duration = duration,
                easing = "linear",
                owner = ChatFadeAnimationOwner,
                key = "ychat-linked-fade",
            })
        else
            if animation and type(animation.StopOwner) == "function" then
                animation:StopOwner(ChatFadeAnimationOwner, false)
            end
            frame:SetAlpha(targetAlpha)
        end
    end
    return true
end

function ChatBar:IsLinkedFadeHidden()
    return linkedFadeHidden == true
end

local function OnYChatElementFade(_, hidden, duration)
    ChatBar:SetLinkedFadeHidden(hidden, duration)
end

local function AttachChatFadeRuntime()
    if not (YUI.Event and type(YUI.Event.On) == "function") then return end
    YUI.Event:OffOwner(ChatFadeEventOwner)
    YUI.Event:On("YUI_CHAT_ELEMENT_FADE", OnYChatElementFade, ChatFadeEventOwner, {
        moduleId = "component:ChatBar",
    })
    local elementFade = YUI.YChat and YUI.YChat.ElementFade
    if elementFade and type(elementFade.IsLinkedHidden) == "function" then
        ChatBar:SetLinkedFadeHidden(elementFade:IsLinkedHidden())
    end
end

local function DetachChatFadeRuntime()
    if YUI.Event and type(YUI.Event.OffOwner) == "function" then
        YUI.Event:OffOwner(ChatFadeEventOwner)
    end
    if YUI.Animation and type(YUI.Animation.StopOwner) == "function" then
        YUI.Animation:StopOwner(ChatFadeAnimationOwner, false)
    end
    ChatBar:SetLinkedFadeHidden(false)
end

-- 按钮右键点击处理 (World Channel)
OnButtonRightClick = function(key)
    if key == "ROLL" and YUI.IsRetail then
        ExecuteCustomCommand("/loot")
    elseif key == "KEYSTONELOOT" then
        OpenGreatVault()
    elseif key == "WORLD" then
        local channelID = GetChannelName("大脚世界频道")
        if channelID > 0 then
            LeaveChannelByName("大脚世界频道")
            YUI:Print("|cffff0000已离开|r |cffffc0c0大脚世界频道")
        else
            JoinPermanentChannel("大脚世界频道")
            AddChatChannel(DefaultChatFrame, "大脚世界频道")

            C_Timer.After(0.5, function()
                local id = GetChannelName("大脚世界频道")
                if id > 0 then
                    YUI:Print("|cff00ff00已加入|r |cffffc0c0大脚世界频道")
                end
            end)
        end
    elseif key == "LFG" then
        local channelID = GetChannelName("寻求组队")
        if channelID > 0 then
            LeaveChannelByName("寻求组队")
            YUI:Print("|cffff0000已离开|r |cffffc0c0寻求组队")
        else
            JoinPermanentChannel("寻求组队")
            AddChatChannel(DefaultChatFrame, "寻求组队")

            C_Timer.After(0.5, function()
                local id = GetChannelName("寻求组队")
                if id > 0 then
                    YUI:Print("|cff00ff00已加入|r |cffffc0c0寻求组队")
                end
            end)
        end
    end
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y, version)
    return {
        version = version or CHATBAR_PLACEMENT_VERSION,
        anchor = {
            point = point or "BOTTOMLEFT",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "BOTTOMLEFT",
        },
        offset = { x = Round(x), y = Round(y) },
    }
end

local function ConvertLegacyRootPlacement(placement)
    if type(placement) ~= "table"
        or type(placement.anchor) ~= "table"
        or (tonumber(placement.version) or 0) >= CHATBAR_PLACEMENT_VERSION
        or type(GetChatBarGeometry) ~= "function"
    then
        return placement
    end

    local geometry = GetChatBarGeometry()
    if type(geometry) ~= "table" then return placement end
    local point = placement.anchor.point or "BOTTOMLEFT"
    local collapseSize = geometry.collapseSize or 0
    local rootX, rootY = PointCoordinates(
        -collapseSize / 2,
        -collapseSize / 2,
        collapseSize,
        collapseSize,
        point
    )
    local boundsX, boundsY = PointCoordinates(
        -(geometry.width or 0) / 2,
        -(geometry.height or 0) / 2,
        geometry.width or 0,
        geometry.height or 0,
        point
    )
    local offset = placement.offset or {}
    return ToLayoutPlacement(
        point,
        placement.anchor.relative or "UIParent",
        placement.anchor.relativePoint or point,
        (offset.x or 0) + (geometry.offsetX or 0) + boundsX - rootX,
        (offset.y or 0) + (geometry.offsetY or 0) + boundsY - rootY
    )
end

local function PointHas(point, token)
    return string.find(point or "", token, 1, true) ~= nil
end

PointCoordinates = function(left, bottom, width, height, point)
    local x
    if PointHas(point, "LEFT") then
        x = left
    elseif PointHas(point, "RIGHT") then
        x = left + width
    else
        x = left + width / 2
    end

    local y
    if PointHas(point, "BOTTOM") then
        y = bottom
    elseif PointHas(point, "TOP") then
        y = bottom + height
    else
        y = bottom + height / 2
    end
    return x, y
end

local function CaptureAgainstPlacement(target, placement)
    if not target or not placement or not placement.anchor then return nil end
    local anchor = placement.anchor
    local point = anchor.point or "BOTTOMLEFT"
    local relativePoint = anchor.relativePoint or point
    local relativeName = anchor.relative or "UIParent"
    local relativeTo = relativeName == "UIParent" and UIParent or _G[relativeName]
    if not relativeTo or relativeTo == target or not relativeTo.GetLeft then return nil end

    local fL, fB = target:GetLeft(), target:GetBottom()
    local fW, fH = target:GetWidth() or 0, target:GetHeight() or 0
    local rL, rB = relativeTo:GetLeft(), relativeTo:GetBottom()
    local rW, rH = relativeTo:GetWidth() or 0, relativeTo:GetHeight() or 0
    if relativeTo == UIParent then
        rL = rL or 0
        rB = rB or 0
    end
    if not fL or not fB or not rL or not rB then return nil end

    local frameX, frameY = PointCoordinates(fL, fB, fW, fH, point)
    local relativeX, relativeY = PointCoordinates(rL, rB, rW, rH, relativePoint)
    return ToLayoutPlacement(point, relativeName, relativePoint, frameX - relativeX, frameY - relativeY)
end

local function LegacyPosToPlacement(pos)
    if type(pos) ~= "table" or not pos[1] then return nil end
    return ConvertLegacyRootPlacement(ToLayoutPlacement(
        pos[1],
        pos[2] or "UIParent",
        pos[3] or pos[1],
        pos[4] or 0,
        pos[5] or 0,
        1
    ))
end

local function GetLegacyDefaultPlacement()
    if DEFAULT_CHAT_FRAME then
        return ToLayoutPlacement("BOTTOMLEFT", "ChatFrame1", "TOPLEFT", 0, 20, 1)
    end
    return ToLayoutPlacement("LEFT", "UIParent", "LEFT", 100, 0, 1)
end

local function GetDefaultPlacement()
    return ConvertLegacyRootPlacement(GetLegacyDefaultPlacement())
end

local function CaptureChatBarPlacement(_, sourceFrame)
    local target = sourceFrame or frame
    if not target then return GetDefaultPlacement() end

    if YUI.Layout and YUI.Layout.GetPlacement then
        local current = YUI.Layout:GetPlacement(CHATBAR_LAYOUT_ID)
        local captured = CaptureAgainstPlacement(target, current)
        if captured then return captured end
    end

    local chatFrame = DEFAULT_CHAT_FRAME
    if chatFrame and chatFrame:IsShown() then
        local fL, fB = target:GetLeft(), target:GetBottom()
        local cL, cB = chatFrame:GetLeft(), chatFrame:GetBottom()
        if fL and fB and cL and cB then
            return ToLayoutPlacement("BOTTOMLEFT", "ChatFrame1", "BOTTOMLEFT", fL - cL, fB - cB)
        end
    end

    return ToLayoutPlacement("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", target:GetLeft() or 100, target:GetBottom() or 0)
end

local function ApplyChatBarPlacement(placement)
    if not frame then return end
    placement = placement or GetDefaultPlacement()
    local anchor = placement.anchor or {}
    local relativeName = anchor.relative or "UIParent"
    local relativeTo = relativeName == "UIParent" and UIParent or _G[relativeName]
    if not relativeTo then relativeTo = UIParent end

    frame:ClearAllPoints()
    frame:SetPoint(anchor.point or "BOTTOMLEFT", relativeTo, anchor.relativePoint or anchor.point or "BOTTOMLEFT", placement.offset and placement.offset.x or 0, placement.offset and placement.offset.y or 0)
end

local function IsBrokenChatBarPlacement(placement)
    if type(placement) ~= "table" or type(placement.anchor) ~= "table" then return false end
    local relativeName = placement.anchor.relative or "UIParent"
    if relativeName == "UIParent" then return false end
    if relativeName == "YUI_ChatBar" then return true end
    if not _G[relativeName] then return true end
    if YUI.Layout and YUI.Layout.WouldCreateAnchorCycle and YUI.Layout:WouldCreateAnchorCycle(CHATBAR_LAYOUT_ID, relativeName) then
        return true
    end
    return false
end

-- 保存位置
local function SavePosition()
    if not frame then return end
    if YUI.Layout and YUI.Layout.SetPlacement then
        YUI.Layout:SetPlacement(CHATBAR_LAYOUT_ID, CaptureChatBarPlacement(frame, frame), true)
        return
    end

    local db = GetDB()
    local placement = CaptureChatBarPlacement(frame, frame)
    db.pos = {
        placement.anchor.point,
        placement.anchor.relative,
        placement.anchor.relativePoint,
        placement.offset.x,
        placement.offset.y,
    }
end

-- 恢复位置
local function RestorePosition()
    if not frame then return end
    local db = GetDB()

    if YUI.Layout and YUI.Layout.GetPlacement then
        ApplyChatBarPlacement(YUI.Layout:GetPlacement(CHATBAR_LAYOUT_ID) or LegacyPosToPlacement(db.pos) or GetDefaultPlacement())
    else
        ApplyChatBarPlacement(LegacyPosToPlacement(db.pos) or GetDefaultPlacement())
    end
end

-- 创建动画组
local function CreateButtonAnimation(btn)
    if btn.animGroup then return btn.animGroup end
    
    local group = btn:CreateAnimationGroup()
    
    local trans = group:CreateAnimation("Translation")
    trans:SetDuration(0.2)
    trans:SetSmoothing("OUT")
    group.trans = trans
    
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetDuration(0.2)
    alpha:SetSmoothing("OUT")
    group.alpha = alpha
    
    btn.animGroup = group
    return group
end

local function HideButtonBorder(btn)
    if not btn or not btn.gui2Borders then return end

    btn.chatBarBorders = btn.gui2Borders
    btn.chatBarBorderTextures = btn.borders

    btn.gui2Borders.top:Hide()
    btn.gui2Borders.bottom:Hide()
    btn.gui2Borders.left:Hide()
    btn.gui2Borders.right:Hide()

    btn.gui2Borders = nil
    btn.borders = nil

    if btn.SetBackdropBorderColor then
        btn:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if btn.gui2NativeBorder then btn.gui2NativeBorder:Hide() end
    if btn.gui2NativeFallbackBorder then btn.gui2NativeFallbackBorder:Hide() end
    btn.gui2NativeBorderActive = false
    btn.gui2NativeFallbackBorderActive = false
end

local function ShowButtonBorder(btn)
    if not btn then return end

    if not btn.gui2Borders then
        if btn.chatBarBorders then
            btn.gui2Borders = btn.chatBarBorders
            btn.borders = btn.chatBarBorderTextures
        else
            GUI2:CreateBorder(btn, "color.border.default")
        end
    end

    if btn.gui2Borders then
        if btn.UpdateGUI2PixelScale then
            btn:UpdateGUI2PixelScale()
        end
        btn.gui2Borders.top:Show()
        btn.gui2Borders.bottom:Show()
        btn.gui2Borders.left:Show()
        btn.gui2Borders.right:Show()
        GUI2:SetBorderColor(btn, "color.border.default")
    end
end

local function MaskWhisperName(name)
    return ChatBarText("chatbar.whisper.new", "New whisper")
end

local WHISPER_NOTIFY_BLINK_KEY = "chatbar-whisper-notify-blink"
local WHISPER_NOTIFY_BLINK_DURATION = 0.9
local WHISPER_NOTIFY_ALPHA_MAX = 1
local WHISPER_NOTIFY_ALPHA_MIN = 0.25

local function IsInCombatLockdownSafe()
    local api = CombatAPI or (YUI.API and YUI.API.Combat)
    if api and api.InCombatLockdown then
        return api.InCombatLockdown() and true or false
    end

    if InCombatLockdown then
        return InCombatLockdown() and true or false
    end

    return false
end

local function StopNotifyTextBlink(btn, keepCombatPause)
    if not btn then return end

    btn.notifyBlinkActive = false
    btn.notifyBlinkPauseAfterVisible = false
    btn.notifyBlinkSerial = (btn.notifyBlinkSerial or 0) + 1
    if not keepCombatPause then
        btn.notifyBlinkPausedForCombat = false
    end
    if btn.SetScript then
        btn:SetScript("OnUpdate", nil)
    end

    local text = btn.notifyText
    local Animation = YUI.Animation
    if text and Animation and Animation.StopTarget then
        Animation:StopTarget(text, WHISPER_NOTIFY_BLINK_KEY, false)
    end
    if text and text.SetAlpha then
        text:SetAlpha(WHISPER_NOTIFY_ALPHA_MAX)
    end
end

local PlayNotifyTextBlink
PlayNotifyTextBlink = function(btn, fadeOut, serial)
    if not btn or not btn.notifyBlinkActive or btn.notifyBlinkSerial ~= serial then return end

    local text = btn.notifyText
    local Animation = YUI.Animation
    if not text or not Animation or not Animation.Tween then
        if text and text.SetAlpha then
            text:SetAlpha(WHISPER_NOTIFY_ALPHA_MAX)
        end
        return
    end

    local fromAlpha = fadeOut and WHISPER_NOTIFY_ALPHA_MAX or WHISPER_NOTIFY_ALPHA_MIN
    if text.GetAlpha then
        fromAlpha = text:GetAlpha()
    end
    local toAlpha = fadeOut and WHISPER_NOTIFY_ALPHA_MIN or WHISPER_NOTIFY_ALPHA_MAX

    Animation:Tween({
        target = text,
        owner = btn,
        key = WHISPER_NOTIFY_BLINK_KEY,
        from = fromAlpha,
        to = toAlpha,
        duration = WHISPER_NOTIFY_BLINK_DURATION,
        easing = "sineInOut",
        onUpdate = function(alpha)
            if text and text.SetAlpha then
                text:SetAlpha(alpha)
            end
        end,
        onFinished = function(_, _, finished)
            if not finished then return end
            if not btn.notifyBlinkActive or btn.notifyBlinkSerial ~= serial or btn.notifyText ~= text then return end
            if btn.notifyBlinkPauseAfterVisible then
                if fadeOut then
                    PlayNotifyTextBlink(btn, false, serial)
                else
                    StopNotifyTextBlink(btn, true)
                end
                return
            end
            PlayNotifyTextBlink(btn, not fadeOut, serial)
        end,
    })
end

local function StartNotifyTextBlink(btn)
    if not btn or not btn.notifyText then return end

    StopNotifyTextBlink(btn)
    if IsInCombatLockdownSafe() then
        btn.notifyBlinkPausedForCombat = true
        if btn.notifyText.SetAlpha then
            btn.notifyText:SetAlpha(WHISPER_NOTIFY_ALPHA_MAX)
        end
        return
    end

    btn.notifyBlinkActive = true
    btn.notifyBlinkSerial = (btn.notifyBlinkSerial or 0) + 1
    if btn.notifyText.SetAlpha then
        btn.notifyText:SetAlpha(WHISPER_NOTIFY_ALPHA_MAX)
    end
    PlayNotifyTextBlink(btn, true, btn.notifyBlinkSerial)
end

local function PauseNotifyTextBlinkForCombat(btn)
    if not btn or not btn.notifyText then return end

    btn.notifyBlinkPausedForCombat = btn.wpName ~= nil
    if not btn.notifyBlinkActive then
        if btn.notifyText.SetAlpha then
            btn.notifyText:SetAlpha(WHISPER_NOTIFY_ALPHA_MAX)
        end
        return
    end

    btn.notifyBlinkPauseAfterVisible = true
end

local function ResumeNotifyTextBlinkAfterCombat(btn)
    if not btn or not btn.notifyText then return end

    local shouldResume = btn.notifyBlinkPausedForCombat and btn.wpName ~= nil
    btn.notifyBlinkPausedForCombat = false
    if btn.notifyBlinkActive then
        btn.notifyBlinkPauseAfterVisible = false
        return
    end

    btn.notifyBlinkPauseAfterVisible = false
    if shouldResume then
        StartNotifyTextBlink(btn)
    end
end

local function SetWhisperNotifyText(btn, name)
    if not btn or not btn.notifyText then return end

    if name then
        local db = GetDB()
        btn.notifyText:SetText((db.maskWhisperName and MaskWhisperName(name)) or name)
    else
        btn.notifyText:SetText()
    end
end

-- 更新密语提示文字位置
local function UpdateNotifyTextPosition()
    if not frame or not frame.collapseBtn or not frame.collapseBtn.notifyText then return end
    local db = GetDB()
    local pos = db.notifyPosition or "RIGHT"
    local dir = db.direction or "RIGHT"
    local offsetX = tonumber(db.notifyTextOffsetX) or 0
    local offsetY = tonumber(db.notifyTextOffsetY) or 0
    local text = frame.collapseBtn.notifyText
    
    text:ClearAllPoints()
    -- 根据设置的方位进行定位
    if pos == "RIGHT" then
        text:SetPoint("LEFT", frame.collapseBtn, "RIGHT", 2 + offsetX, offsetY)
    elseif pos == "LEFT" then
        text:SetPoint("RIGHT", frame.collapseBtn, "LEFT", -2 + offsetX, offsetY)
    elseif pos == "UP" then
        if dir == "RIGHT" then
            text:SetPoint("BOTTOMLEFT", frame.collapseBtn, "TOPLEFT", offsetX, 2 + offsetY)
        elseif dir == "LEFT" then
            text:SetPoint("BOTTOMRIGHT", frame.collapseBtn, "TOPRIGHT", offsetX, 2 + offsetY)
        else
            text:SetPoint("BOTTOM", frame.collapseBtn, "TOP", offsetX, 2 + offsetY)
        end
    elseif pos == "DOWN" then
        if dir == "RIGHT" then
            text:SetPoint("TOPLEFT", frame.collapseBtn, "BOTTOMLEFT", offsetX, -2 + offsetY)
        elseif dir == "LEFT" then
            text:SetPoint("TOPRIGHT", frame.collapseBtn, "BOTTOMRIGHT", offsetX, -2 + offsetY)
        else
            text:SetPoint("TOP", frame.collapseBtn, "BOTTOM", offsetX, -2 + offsetY)
        end
    end
end

-- 更新收纳图标（信封）位置
local function UpdateIconPosition()
    if not frame or not frame.collapseBtn or not frame.collapseBtn.arrow then return end
    local db = GetDB()
    local arrow = frame.collapseBtn.arrow
    
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", db.iconOffsetX or 0, db.iconOffsetY or 0)
end

local function GetWhisperProvider()
    local manager = YUI.WhisperManager
    if manager and manager.ToggleFrame and (not manager.IsEnabled or manager:IsEnabled()) then
        return manager
    end

    if _G.WhisperPop and _G.WhisperPop.ToggleFrame then
        return _G.WhisperPop
    end
end

local whisperProviderErrorKeys = {}

local function CallWhisperProvider(provider, methodName, ...)
    if not provider or type(methodName) ~= "string" then
        return nil
    end

    local method = provider[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, value1, value2, value3, value4 = pcall(method, provider, ...)
    if ok then
        return value1, value2, value3, value4
    end

    local key = tostring(provider) .. ":" .. methodName
    if not whisperProviderErrorKeys[key] then
        whisperProviderErrorKeys[key] = true
        if type(YUI.Debug) == "function" then
            YUI:Debug(string.format("ChatBar | Whisper provider %s failed: %s", methodName, tostring(value1)))
        end
    end
    return nil
end

local function HasWhisperPop()
    return GetWhisperProvider() ~= nil
end

local function UnregisterWhisperNotifyProvider(btn)
    if not btn then return end
    local provider = btn.whisperNotifyProvider
    local callback = btn.RefreshWhisperNotify
    if not (provider and callback) then
        btn.whisperNotifyProvider = nil
        return
    end

    local unregistered = false
    if provider.UnregisterEventCallback then
        CallWhisperProvider(provider, "UnregisterEventCallback", "OnListUpdate", callback)
        unregistered = true
    elseif provider.UnregisterCallback then
        CallWhisperProvider(provider, "UnregisterCallback", "OnListUpdate", callback)
        unregistered = true
    end

    if unregistered then
        btn.whisperNotifyProvider = nil
    end
end

local function DetachWhisperNotifyRuntime(btn)
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(WhisperNotifyEventOwner)
    end
    UnregisterWhisperNotifyProvider(btn)
    if btn then
        btn.whisperNotifyRuntimeAttached = false
    end
end

local function AttachWhisperNotifyRuntime(btn)
    if not (btn and btn.RefreshWhisperNotify) then return end

    if YUI.Event and YUI.Event.On then
        YUI.Event:OffOwner(WhisperNotifyEventOwner)
        YUI.Event:On("YUI_WHISPER_MANAGER_UPDATE", btn.RefreshWhisperNotify, WhisperNotifyEventOwner, {
            moduleId = "component:ChatBar",
        })
        if btn.OnWhisperNotifyCombatEvent then
            YUI.Event:On("PLAYER_REGEN_DISABLED", btn.OnWhisperNotifyCombatEvent, WhisperNotifyEventOwner, {
                traceName = "ChatBar:whisper-notify-combat-start",
                moduleId = "component:ChatBar",
            })
            YUI.Event:On("PLAYER_REGEN_ENABLED", btn.OnWhisperNotifyCombatEvent, WhisperNotifyEventOwner, {
                traceName = "ChatBar:whisper-notify-combat-end",
                moduleId = "component:ChatBar",
            })
        end
    end

    local whisperProvider = GetWhisperProvider()
    if whisperProvider and whisperProvider ~= YUI.WhisperManager and whisperProvider.RegisterEventCallback then
        if btn.whisperNotifyProvider ~= whisperProvider then
            UnregisterWhisperNotifyProvider(btn)
            CallWhisperProvider(whisperProvider, "RegisterEventCallback", "OnListUpdate", btn.RefreshWhisperNotify)
            btn.whisperNotifyProvider = whisperProvider
        end
    end
    btn.whisperNotifyRuntimeAttached = true
end

local function HasTradeLog()
    return IsAddOnLoaded and IsAddOnLoaded("OrangeUITradeLog")
end

local function GetFontPath()
    local db = GetDB()
    local fontPath = db.font == "默认" and STANDARD_TEXT_FONT
        or (db.font and LSM:Fetch("font", db.font))
    if not fontPath or fontPath == "" then
        fontPath = STANDARD_TEXT_FONT
    end
    return fontPath
end

local function UpdateCollapseFont()
    if not frame or not frame.collapseBtn or not frame.collapseBtn.notifyText then return end
    frame.collapseBtn.notifyText:SetFont(GetFontPath(), 13, "OUTLINE")
end

local function RefreshTooltipIfOwned()
    if not frame or not frame.collapseBtn then return end
    if not GameTooltip or not GameTooltip.IsOwned then return end
    if GameTooltip:IsOwned(frame.collapseBtn) then
        local onEnter = frame.collapseBtn:GetScript("OnEnter")
        if onEnter then
            onEnter(frame.collapseBtn)
        end
    end
end

local function GetActiveChannelCount(db)
    local count = 0
    db = db or GetDB()
    for _, info in ipairs(CHANNELS) do
        if db.channels and db.channels[info.key] == true then count = count + 1 end
    end
    for _, customButton in ipairs(db.customButtons or {}) do
        if customButton.enabled == true then count = count + 1 end
    end
    return count
end

GetChatBarGeometry = function()
    local db = GetDB()
    local width = tonumber(db.width) or defaults.width
    local height = tonumber(db.height) or defaults.height
    local spacing = tonumber(db.spacing) or defaults.spacing
    local dir = db.direction or defaults.direction
    local barThickness = height
    if dir == "UP" or dir == "DOWN" then
        barThickness = width
    end
    local collapseSize = math.min(32, math.max(16, barThickness))
    local minX, maxX = -collapseSize / 2, collapseSize / 2
    local minY, maxY = -collapseSize / 2, collapseSize / 2
    local currentOffset = collapseSize + spacing

    for i = 1, GetActiveChannelCount(db) do
        local centerX, centerY = 0, 0
        if dir == "RIGHT" then
            centerX = currentOffset + (width - collapseSize) / 2
        elseif dir == "LEFT" then
            centerX = -currentOffset - (width - collapseSize) / 2
        elseif dir == "UP" then
            centerY = currentOffset + (height - collapseSize) / 2
        elseif dir == "DOWN" then
            centerY = -currentOffset - (height - collapseSize) / 2
        end

        minX = math.min(minX, centerX - width / 2)
        maxX = math.max(maxX, centerX + width / 2)
        minY = math.min(minY, centerY - height / 2)
        maxY = math.max(maxY, centerY + height / 2)

        if dir == "RIGHT" or dir == "LEFT" then
            currentOffset = currentOffset + width + spacing
        else
            currentOffset = currentOffset + height + spacing
        end
    end

    return {
        width = maxX - minX,
        height = maxY - minY,
        offsetX = (minX + maxX) / 2,
        offsetY = (minY + maxY) / 2,
        collapseSize = collapseSize,
    }
end

local function GetChatBarMoverBounds()
    local geometry = GetChatBarGeometry()
    return {
        width = geometry.width,
        height = geometry.height,
        offsetX = 0,
        offsetY = 0,
    }
end

local function UpdateChatBarFrameGeometry(geometry)
    if not frame or not frame.collapseBtn then return end
    geometry = geometry or GetChatBarGeometry()
    frame:SetSize(geometry.width, geometry.height)
    frame.collapseBtn:SetSize(geometry.collapseSize, geometry.collapseSize)
    frame.collapseBtn:ClearAllPoints()
    frame.collapseBtn:SetPoint(
        "CENTER",
        frame,
        "CENTER",
        -(geometry.offsetX or 0),
        -(geometry.offsetY or 0)
    )
end

local function RefreshLayoutMover()
    if YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(CHATBAR_LAYOUT_ID)
    end
end

local function AddCustomActionTooltipLine(mouseButton, command)
    if not command or command == "" then return end
    local labelKeys = {
        LeftButton = { "chatbar.mouse.left", "Left click" },
        RightButton = { "chatbar.mouse.right", "Right click" },
        MiddleButton = { "chatbar.mouse.middle", "Middle click" },
    }
    local label = labelKeys[mouseButton]
    GameTooltip:AddDoubleLine(
        (label and ChatBarText(label[1], label[2]) or mouseButton) .. ":",
        command,
        1, 1, 1,
        1, 0.82, 0
    )
end

local function ShowRuntimeButtonTooltip(btn)
    local info = btn and btn.info
    if not info then return end
    SetTooltipAnchor(btn)
    if info.customButton then
        local customButton = info.customButton
        GameTooltip:SetText(customButton.title or customButton.text, 1, 0.82, 0, 1, true)
        GameTooltip:AddLine(" ")
        AddCustomActionTooltipLine("LeftButton", customButton.actions.LeftButton)
        AddCustomActionTooltipLine("RightButton", customButton.actions.RightButton)
        AddCustomActionTooltipLine("MiddleButton", customButton.actions.MiddleButton)
    elseif info.key == "LEAVE" then
        GameTooltip:SetText(info.tooltip, 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        if YUI.IsRetail then
            GameTooltip:AddLine(ChatBarText("chatbar.leave.delve", "|cffffffffLeft Click:|r Leave group/Delve"))
        else
            GameTooltip:AddLine(ChatBarText("chatbar.leave.left", "|cffffffffLeft Click:|r Leave group"))
        end
        GameTooltip:AddLine(ChatBarText("chatbar.leave.right", "|cffffffffRight Click:|r Reset instances"))
    elseif info.key == "RL" then
        GameTooltip:SetText(ChatBarText("chatbar.reload.title", "Reload UI"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.reload.tooltip", "Left click: reload the UI immediately."), 1, 1, 1, true)
    elseif info.key == "ROLL" then
        GameTooltip:AddLine(ChatBarText("chatbar.channel.roll", "Roll"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.tooltip.roll_left", "|cffffffffLeft Click:|r Roll"))
        if YUI.IsRetail then
            GameTooltip:AddLine(ChatBarText("chatbar.tooltip.roll_right", "|cffffffffRight Click:|r Loot rolls"))
        end
    elseif info.key == "WORLD" then
        GameTooltip:AddLine(ChatBarText("chatbar.channel.world", "World Channel"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.tooltip.world_toggle", "|cffffffffRight Click:|r Join/leave World Channel"))
    elseif info.key == "LFG" then
        GameTooltip:AddLine(ChatBarText("chatbar.channel.lfg", "Looking For Group"), 0.5, 0.5, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.tooltip.lfg_toggle", "|cffffffffRight Click:|r Join/leave Looking For Group"))
    elseif info.key == "DUNGEONSFOREVER" then
        GameTooltip:AddLine(ChatBarText("chatbar.dungeons_forever.title", "DungeonsForever"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.dungeons_forever.left", "|cffffffffLeft Click:|r Open / close DungeonsForever"))
    elseif info.key == "KEYSTONELOOT" then
        GameTooltip:AddLine(ChatBarText("chatbar.channel.loot", "Loot Browser"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ChatBarText("chatbar.tooltip.loot_left", "|cffffffffLeft Click:|r Loot browser"))
        if IsGreatVaultAvailable() then
            GameTooltip:AddLine(ChatBarText("chatbar.tooltip.vault_right", "|cffffffffRight Click:|r Great Vault"))
        end
    else
        GameTooltip:SetText(info.tooltip or info.name)
    end
    GameTooltip:Show()
    btn:SetAlpha(1)
end

-- 更新布局
-- @param skipAnim boolean 是否跳过动画
local function UpdateLayout(skipAnim)
    if not frame then return end
    local db = GetDB()
    EnsureChannelSettings(db)
    local orderedChannels = GetOrderedChannels(db)
    
    local width = db.width
    local height = db.height
    local spacing = db.spacing
    local dir = db.direction
    local style = db.style
    local fontPath = GetFontPath()
    
    local geometry = GetChatBarGeometry()
    local collapseSize = geometry.collapseSize
    UpdateChatBarFrameGeometry(geometry)
    
    -- 图标随尺寸变化
    if frame.collapseBtn.arrow then
        local iconSize = math.max(18, math.floor(collapseSize * 0.8))
        frame.collapseBtn.arrow:SetSize(iconSize, iconSize)
    end
    
    UpdateNotifyTextPosition()
    UpdateIconPosition()
    UpdateCollapseFont()
    
    -- 准备按钮
    local activeButtons = {}
    local currentButtonKeys = {}
    
    -- 动态获取聊天框高度，用于自动对齐
    -- 我们需要根据聊天框的 TOP/BOTTOM 来决定对齐方式
    -- 如果在下半屏，默认吸附在聊天框上方；上半屏则下方
    -- 目前 YUI_ChatBar 是自由移动的，这里暂时只处理自己的布局方向
    -- 如果需要跟随聊天框，需要额外的逻辑。
    -- 但这里只处理 Bar 内部的按钮布局
    
    for _, info in ipairs(orderedChannels) do
        currentButtonKeys[info.key] = true
        if IsButtonEnabled(db, info) then
            local btn = buttons[info.key]
            if not btn then
                -- 创建按钮
                btn = GUI2:CreateButtonFrame(frame, { template = "BackdropTemplate" })
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
                
                -- 样式设置
            btn.text = GUI2:CreateText(btn, "", "font.size.md", "color.text.primary")
            btn.text.gui2ColorKey = nil
            btn.text.gui2ColorFallback = nil
                -- 字体大小自动适配高度 (高度的 60%)
                local fontSize = math.max(8, math.floor(height * 0.6))
                btn.text:SetFont(fontPath, fontSize, "OUTLINE")
                btn.text:SetPoint("CENTER")
                -- 添加文字阴影
                btn.text:SetShadowColor(0, 0, 0, 1)
                btn.text:SetShadowOffset(1, -1)
                
                btn.icon = GUI2:CreateTexture(btn, { layer = "ARTWORK" })
                btn.icon:SetAllPoints()
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                
                -- 创建背景纹理 (用于 Block 模式)
                btn.bgTex = GUI2:CreateTexture(btn, { layer = "BACKGROUND" })
                btn.bgTex:SetAllPoints()
                btn.bgTex:Hide()

                -- 设置高亮材质
                btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
                local hl = btn:GetHighlightTexture()
                hl:SetVertexColor(1, 1, 1, 0.2)
                hl:SetBlendMode("ADD")
                hl:SetAllPoints()

                -- 创建阴影 (使用 GUI 统一阴影)
                GUI2:CreateShadow(btn)
                btn.shadow = btn.gui2Shadow
                if btn.shadow then btn.shadow:Hide() end
                
                btn:SetScript("OnClick", function(self, button)
                    OnRuntimeButtonClick(self.info, button)
                end)
                
                btn:SetScript("OnEnter", function(self)
                    ShowRuntimeButtonTooltip(self)
                end)
                
                btn:SetScript("OnLeave", function(self)
                    YUI.HideGameTooltip()
                    if db.autoHide then self:SetAlpha(0) end
                end)
                
                CreateButtonAnimation(btn)
                
                buttons[info.key] = btn
            end
            btn.info = info
            
            -- 强制重置 Alpha 为 1
            if not db.autoHide then
                btn:SetAlpha(1)
            end
            
            -- 更新样式和尺寸
            btn:SetSize(width, height)
            
            -- 更新字体大小
            local fontSize = math.max(8, math.floor(height * 0.6))
            btn.text:SetFont(fontPath, fontSize, "OUTLINE")
            
            if style == "TEXT" then
                local channelColor = GetChannelColor(db, info)
                btn.icon:Hide()
                btn.bgTex:Hide()
                btn.text:Show()
                btn.text:SetText(info.name)
                btn.text:SetTextColor(unpack(channelColor))
                -- 文字模式背景全透明但保留交互
                btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                btn:SetBackdropColor(0, 0, 0, 0)
                HideButtonBorder(btn)
                
                if btn.shadow then btn.shadow:Hide() end
            else -- BLOCK
                local channelColor = GetChannelColor(db, info)
                btn.text:Hide()
                btn.icon:Hide()
                
                -- 使用 LSM 解析纹理路径
                local texPath = LSM:Fetch("statusbar", db.blockTexture) or "Interface\\Buttons\\WHITE8x8"
                
                -- 使用 bgTex 显示材质，以便控制旋转
                btn:SetBackdrop({bgFile = nil}) -- 清空 Backdrop 背景
                btn.bgTex:Show()
                btn.bgTex:SetTexture(texPath)
                btn.bgTex:SetVertexColor(unpack(channelColor))
                
                -- 根据方向旋转材质
                if dir == "UP" or dir == "DOWN" then
                    btn.bgTex:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) -- 旋转 90 度
                else
                    btn.bgTex:SetTexCoord(0, 1, 0, 1) -- 正常
                end
                
                ShowButtonBorder(btn)
                
                -- 处理阴影
                if db.blockShadow and btn.shadow then
                    btn.shadow:Show()
                    local shadowSize = 3
                    btn.shadow:SetPoint("TOPLEFT", -shadowSize, shadowSize)
                    btn.shadow:SetPoint("BOTTOMRIGHT", shadowSize, -shadowSize)
                    btn.shadow:SetBackdrop({
                        edgeFile = Assets:Core("images\\GlowTex.tga"),
                        edgeSize = shadowSize,
                        insets = { left = shadowSize, right = shadowSize, top = shadowSize, bottom = shadowSize }
                    })
                    btn.shadow:SetBackdropBorderColor(0, 0, 0, 0.7)
                elseif btn.shadow then
                    btn.shadow:Hide()
                end
            end
            
            table.insert(activeButtons, btn)
        else
            if buttons[info.key] then buttons[info.key]:Hide() end
        end
    end
    for key, buttonFrame in pairs(buttons) do
        if not currentButtonKeys[key] then
            buttonFrame.info = nil
            buttonFrame:Hide()
        end
    end
    
    if db.reverse then
        local reversed = {}
        for i = #activeButtons, 1, -1 do
            table.insert(reversed, activeButtons[i])
        end
        activeButtons = reversed
    end
    
    -- 如果是收起状态且不需要动画，隐藏所有
    if isCollapsed and skipAnim then
        for _, btn in ipairs(activeButtons) do btn:Hide() end
        RefreshLayoutMover()
        return
    end
    
    -- 计算布局位置
    local currentOffset = collapseSize + spacing
    
    for _, btn in ipairs(activeButtons) do
        btn:ClearAllPoints()
        local x, y = 0, 0
        local animX, animY = 0, 0
        
        -- 计算位移量：从 0 (中心) 到 目标位置
        -- 注意：不同方向时，按钮排列的维度不同
        if dir == "RIGHT" then
            x = currentOffset + (width - collapseSize) / 2 -- 修正中心对齐
            animX = -currentOffset 
        elseif dir == "LEFT" then
            x = -currentOffset - (width - collapseSize) / 2
            animX = currentOffset
        elseif dir == "UP" then
            y = currentOffset + (height - collapseSize) / 2
            animY = -currentOffset
        elseif dir == "DOWN" then
            y = -currentOffset - (height - collapseSize) / 2
            animY = currentOffset
        end
        x = x - (geometry.offsetX or 0)
        y = y - (geometry.offsetY or 0)
        
        -- 修正：currentOffset 应该累加的是按钮在该方向上的尺寸
        if dir == "RIGHT" or dir == "LEFT" then
            currentOffset = currentOffset + width + spacing
        else
            currentOffset = currentOffset + height + spacing
        end
        
        -- 设置最终位置
        btn:SetPoint("CENTER", frame, "CENTER", x, y)
        btn:Show()
        if not db.autoHide then btn:SetAlpha(1) end
        
        btn.animOffset = {x = animX, y = animY}
    end
    RefreshLayoutMover()
end

-- 切换展开/收起 (带动画)
local function ToggleChatBar()
    isCollapsed = not isCollapsed
    local db = GetDB()
    EnsureChannelSettings(db)
    local orderedChannels = GetOrderedChannels(db)
    
    local activeButtons = {}
    for _, info in ipairs(orderedChannels) do
        if IsButtonEnabled(db, info) and buttons[info.key] then
            table.insert(activeButtons, buttons[info.key])
        end
    end
    
    if db.reverse then
        local reversed = {}
        for i = #activeButtons, 1, -1 do
            table.insert(reversed, activeButtons[i])
        end
        activeButtons = reversed
    end
    
    for _, btn in ipairs(activeButtons) do
        local group = btn.animGroup
        group:Stop()
        group:SetScript("OnFinished", nil)
        
        local offsetX = btn.animOffset.x
        local offsetY = btn.animOffset.y
        
        if isCollapsed then
            btn:Show()
            group.trans:SetOffset(offsetX, offsetY)
            group.alpha:SetFromAlpha(btn:GetAlpha())
            group.alpha:SetToAlpha(0)
            
            group:SetScript("OnFinished", function()
                btn:Hide()
            end)
            group:Play()
        else
            btn:Show()
            btn:ClearAllPoints()
            local geometry = GetChatBarGeometry()
            btn:SetPoint(
                "CENTER",
                frame,
                "CENTER",
                -(geometry.offsetX or 0),
                -(geometry.offsetY or 0)
            )
            
            group.trans:SetOffset(-offsetX, -offsetY)
            group.alpha:SetFromAlpha(0)
            group.alpha:SetToAlpha(1)
            
            group:SetScript("OnFinished", function()
                if btn == activeButtons[#activeButtons] then
                     UpdateLayout(true)
                end
            end)
            group:Play()
        end
    end
end

local function OpenChatBarSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature("ChatBar")
        return true
    end
    if YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings("ChatBar")
        return true
    end
    return false
end

local function OpenTradeLog()
    if HasTradeLog() then
        local editBox = DefaultChatFrame and DefaultChatFrame.editBox
        if editBox then
            editBox:SetText("/tradelog")
            ChatEdit_SendText(editBox)
            return true
        end
    end
    return false
end

local function RegisterLayout()
    if not frame or not YUI.Layout or not YUI.Layout.RegisterFrame then return false end
    local legacyPlacement = LegacyPosToPlacement(GetDB().pos)
    local hasLayoutPlacement = YUI.Layout.HasPlacement and YUI.Layout:HasPlacement(CHATBAR_LAYOUT_ID)
    local currentPlacement = hasLayoutPlacement and YUI.Layout.GetPlacement
        and YUI.Layout:GetPlacement(CHATBAR_LAYOUT_ID) or nil
    YUI.Layout:RegisterFrame(CHATBAR_LAYOUT_ID, {
        frame = frame,
        title = "聊天条",
        category = "component",
        defaultPlacement = GetDefaultPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent", "ChatFrame1" },
        minWidth = 20,
        minHeight = 20,
        nudgeStep = 1,
        getMoverBounds = GetChatBarMoverBounds,
        capturePlacement = CaptureChatBarPlacement,
        openPluginSettings = function()
            if not OpenTradeLog() then
                OpenChatBarSettings()
            end
        end,
    })
    if legacyPlacement and not hasLayoutPlacement and YUI.Layout.SetPlacement then
        YUI.Layout:SetPlacement(CHATBAR_LAYOUT_ID, IsBrokenChatBarPlacement(legacyPlacement) and GetDefaultPlacement() or legacyPlacement, true)
    elseif currentPlacement and YUI.Layout.SetPlacement then
        if IsBrokenChatBarPlacement(currentPlacement) then
            YUI.Layout:SetPlacement(CHATBAR_LAYOUT_ID, GetDefaultPlacement(), true)
        elseif (tonumber(currentPlacement.version) or 0) < CHATBAR_PLACEMENT_VERSION then
            YUI.Layout:SetPlacement(
                CHATBAR_LAYOUT_ID,
                ConvertLegacyRootPlacement(currentPlacement),
                true
            )
        end
    end
    return true
end

-- 初始化 UI
local function InitUI()
    if frame then return end
    
    frame = GUI2:CreateFrame(UIParent, { name = "YUI_ChatBar", template = "BackdropTemplate", clamped = true, movable = true, frameStrata = "MEDIUM" })
    
    -- Collapse 按钮
    local collapseBtn = GUI2:CreateButtonFrame(frame, { template = "BackdropTemplate" })
    collapseBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    collapseBtn:RegisterForDrag("LeftButton")
    
    collapseBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    collapseBtn:SetBackdropColor(0.2, 0.2, 0.2, 0) -- 全透明
    local arrow = GUI2:CreateTexture(collapseBtn, { layer = "OVERLAY" })
    arrow:SetPoint("CENTER")
    -- arrow:SetTexture(Assets:Core("images\\icons\\chat.png")) 
    arrow:SetAtlas("Mailbox") 
    if not arrow:GetTexture() then
        arrow:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    collapseBtn.arrow = arrow
    
    -- 添加 WhisperPop 提示文本
    local notifyText = GUI2:CreateText(collapseBtn, "", 13, "color.state.success")
    collapseBtn.notifyText = notifyText
    UpdateCollapseFont()
    
    collapseBtn:SetScript("OnDragStart", function()
        if YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() then return end
        if GetDB().locked then return end
        frame:StartMoving()
    end)
    
    collapseBtn:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
        
        -- 拖动结束后，检查是否需要吸附到左侧/右侧/顶部/底部
        -- 并自动设置方向
        -- 这是一个高级功能，暂时保留现状，只保存位置
    end)
    
    collapseBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if IsAltKeyDown() then
                OpenChatBarSettings()
            else
                local whisperProvider = GetWhisperProvider()
                if whisperProvider then
                    CallWhisperProvider(whisperProvider, "ToggleFrame")
                    if GameTooltip:IsOwned(self) then
                        self:GetScript("OnEnter")(self)
                    end
                end
            end
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                ToggleChatBar()
            else
                OpenTradeLog()
            end
            -- 刷新鼠标提示
            if GameTooltip:IsOwned(self) then
                self:GetScript("OnEnter")(self)
            end
        end
    end)
    
    collapseBtn:SetScript("OnEnter", function(self)
        SetTooltipAnchor(self)
        local action = isCollapsed and ChatBarText("chatbar.tooltip.expand", "Expand chat bar") or ChatBarText("chatbar.tooltip.collapse", "Collapse chat bar")
        local db = GetDB()
        local hasWP = HasWhisperPop()
        local hasTL = HasTradeLog()
        local moveText = ChatBarText("chatbar.tooltip.move", "Move chat bar")
        if db.locked then
            moveText = YUI.F:GetAtlasString("AdventureMapIcon-Lock", 14, 18, 0, 2) .. " ".. moveText
        end

        GameTooltip:AddLine("|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r " .. ChatBarText("component.ChatBar.name", "Chat Bar"))
        GameTooltip:AddLine(" ")

        if hasWP then
            GameTooltip:AddLine(ChatBarText("chatbar.tooltip.open_whispers", "|cffffffffLeft Click:|r Open %s"):format(F:GetGradientText(ChatBarText("chatbar.whisper_history", "Whisper History"), {0.84, 0.41, 1}, {0.64, 0.21, 0.93})))
            if hasTL then
                GameTooltip:AddLine(ChatBarText("chatbar.tooltip.open_trades", "|cffffffffRight Click:|r Open %s"):format(F:GetGradientText(ChatBarText("chatbar.trade_history", "Trade History"), {1, 1, 0}, {1, 0.27, 0})))
            end
            
            -- 加入 WhisperPop 原生提示
            local whisperProvider = GetWhisperProvider()
            if whisperProvider and whisperProvider.AddTooltipText then
                GameTooltip:AddLine(" ")
                CallWhisperProvider(whisperProvider, "AddTooltipText", GameTooltip)
            end
        else
            if hasTL then
                GameTooltip:AddLine(ChatBarText("chatbar.tooltip.open_trades", "|cffffffffRight Click:|r Open %s"):format(ChatBarText("chatbar.trade_history", "Trade History")))
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(ChatBarText("chatbar.mouse.drag", "|cff999999Left Drag:|r"), moveText)
        GameTooltip:AddDoubleLine(ChatBarText("chatbar.mouse.shift_right", "|cff999999Shift+Right Click:|r"), action)
        GameTooltip:AddDoubleLine(ChatBarText("chatbar.mouse.alt_left", "|cff999999Alt+Left Click:|r"), ChatBarText("common.open_settings", "Open settings"))
        GameTooltip:Show()
    end)
    
    collapseBtn:SetScript("OnLeave", function(self)
        YUI.HideGameTooltip()
    end)
    
    local function RefreshWhisperNotify()
        if not chatBarActive then return end
        local whisperProvider = GetWhisperProvider()
        local name = CallWhisperProvider(whisperProvider, "GetNewMessage")
        if name == collapseBtn.wpName then
            if name and not collapseBtn.notifyBlinkActive then
                StartNotifyTextBlink(collapseBtn)
            elseif not name and collapseBtn.notifyBlinkActive then
                StopNotifyTextBlink(collapseBtn)
            end
            return
        end

        collapseBtn.wpName = name
        collapseBtn.arrow:Show()
        if name then
            collapseBtn.arrow:SetDesaturated(false)
            SetWhisperNotifyText(collapseBtn, name)
            StartNotifyTextBlink(collapseBtn)
        else
            StopNotifyTextBlink(collapseBtn)
            collapseBtn.arrow:SetDesaturated(true)
            SetWhisperNotifyText(collapseBtn)
            collapseBtn.arrow:Show()
        end
    end
    collapseBtn.RefreshWhisperNotify = RefreshWhisperNotify

    local function OnWhisperNotifyCombatEvent(event)
        if event == "PLAYER_REGEN_DISABLED" then
            PauseNotifyTextBlinkForCombat(collapseBtn)
        elseif event == "PLAYER_REGEN_ENABLED" then
            ResumeNotifyTextBlinkAfterCombat(collapseBtn)
        end
    end
    collapseBtn.OnWhisperNotifyCombatEvent = OnWhisperNotifyCombatEvent

    frame.collapseBtn = collapseBtn
    UpdateChatBarFrameGeometry(GetChatBarGeometry())

    if not RegisterLayout() then
        RestorePosition()
    end
    UpdateLayout(true) -- 初始布局
end

local channelOrderPopup
local customButtonEditor

local function CloseChannelOrderPopup()
    if channelOrderPopup and channelOrderPopup.Hide then
        channelOrderPopup:Hide()
    end
end

local function RefreshChannelOrderPopup(popup)
    if not popup or not popup.rows then return end
    local db = GetDB()
    EnsureChannelSettings(db)
    local draftOrder = popup.draftOrder or {}
    if popup.SetHeight then popup:SetHeight(48 + (math.max(1, #draftOrder) * 26) + 58) end
    for index, row in ipairs(popup.rows) do
        local key = draftOrder[index]
        local info = CHANNELS_BY_KEY[key]
        if not info then
            local customButton = GetCustomButtonByKey(db, key)
            if customButton then info = GetCustomButtonInfo(customButton) end
        end
        if info then
            local color = GetChannelColor(db, info)
            row.rank:SetText(tostring(index))
            row.name:SetText(info.name)
            row.name.gui2ColorKey = nil
            row.name.gui2ColorFallback = nil
            row.name:SetTextColor(color[1], color[2], color[3], 1)
            row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
            row:SetAlpha(IsButtonEnabled(db, info) and 1 or 0.45)
            row.up:SetDisabled(index <= 1)
            row.down:SetDisabled(index >= #draftOrder)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function EnsureChannelOrderPopup(owner, onCommit)
    if channelOrderPopup then
        channelOrderPopup.owner = owner or channelOrderPopup.owner
        channelOrderPopup.onCommit = onCommit or channelOrderPopup.onCommit
        return channelOrderPopup
    end
    if not (GUI2 and GUI2.CreatePanel and GUI2.Form and GUI2.Form.CreateButton and UIParent) then
        return nil
    end

    local maxRows = #CHANNELS + MAX_CUSTOM_BUTTONS
    local popup = GUI2:CreatePanel(UIParent, {
        width = 344,
        height = 48 + (maxRows * 26) + 58,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
        shadowKey = "shadow.popup.size",
    })
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    if popup.SetFrameStrata then popup:SetFrameStrata("FULLSCREEN_DIALOG") end
    if popup.SetFrameLevel then popup:SetFrameLevel(9000) end
    if popup.EnableMouse then popup:EnableMouse(true) end
    popup:Hide()

    local title = GUI2:CreateText(popup, ChatBarText("chatbar.button_order", "Button order"), "font.size.lg", "color.text.heading")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -16)

    popup.rows = {}
    local rowHeight = 26
    for index = 1, maxRows do
        local rowIndex = index
        local row = GUI2:CreateFrame(popup, { width = 312, height = rowHeight })
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -48 - (index - 1) * rowHeight)

        row.rank = GUI2:CreateText(row, "", "font.size.sm", "color.text.secondary", "CENTER")
        row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.rank:SetWidth(22)

        row.swatch = GUI2:CreateTexture(row, { layer = "ARTWORK" })
        row.swatch:SetSize(14, 14)
        row.swatch:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)

        row.name = GUI2:CreateText(row, "", "font.size.md", "color.text.primary", "LEFT")
        row.name:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
        row.name:SetWidth(154)
        row.name:SetWordWrap(false)

        row.up = GUI2.Form:CreateButton(row, {
            text = "↑",
            width = 28,
            height = 24,
            onClick = function()
                local draft = popup.draftOrder
                if not draft or rowIndex <= 1 then return end
                draft[rowIndex], draft[rowIndex - 1] = draft[rowIndex - 1], draft[rowIndex]
                RefreshChannelOrderPopup(popup)
            end,
        })
        row.up:SetPoint("RIGHT", row, "RIGHT", -34, 0)

        row.down = GUI2.Form:CreateButton(row, {
            text = "↓",
            width = 28,
            height = 24,
            onClick = function()
                local draft = popup.draftOrder
                if not draft or rowIndex >= #draft then return end
                draft[rowIndex], draft[rowIndex + 1] = draft[rowIndex + 1], draft[rowIndex]
                RefreshChannelOrderPopup(popup)
            end,
        })
        row.down:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        popup.rows[index] = row
    end

    local restore = GUI2.Form:CreateButton(popup, {
        text = ChatBarText("chatbar.restore_default_order", "恢复默认顺序"),
        width = 118,
        height = 30,
        tone = "default",
        onClick = function()
            popup.draftOrder = GetDefaultChannelOrder(GetDB())
            RefreshChannelOrderPopup(popup)
        end,
    })
    restore:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 16)

    local cancel = GUI2.Form:CreateButton(popup, {
        text = ChatBarText("common.cancel", "取消"),
        width = 70,
        height = 30,
        onClick = CloseChannelOrderPopup,
    })
    cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 16)

    local save = GUI2.Form:CreateButton(popup, {
        text = ChatBarText("chatbar.save", "保存"),
        width = 70,
        height = 30,
        state = "selected",
        onClick = function()
            local db = GetDB()
            EnsureChannelSettings(db)
            db.channelOrder = CopyChannelOrder(popup.draftOrder)
            EnsureChannelSettings(db)
            popup:Hide()
            if popup.onCommit then popup.onCommit() end
        end,
    })
    save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)

    popup.owner = owner
    popup.onCommit = onCommit
    channelOrderPopup = popup
    return popup
end

local function OpenChannelOrderPopup(owner, onCommit)
    local popup = EnsureChannelOrderPopup(owner, onCommit)
    if not popup then return end
    local db = GetDB()
    EnsureChannelSettings(db)
    popup.owner = owner or popup.owner
    popup.onCommit = onCommit or popup.onCommit
    popup.draftOrder = CopyChannelOrder(db.channelOrder)
    RefreshChannelOrderPopup(popup)
    if popup.SetFrameLevel then
        local ownerLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel() or 0
        popup:SetFrameLevel(math.max(9000, ownerLevel + 20))
    end
    popup:Show()
    if popup.Raise then popup:Raise() end
    if owner and owner.HookScript and not owner.yuiChatBarOrderPopupHideHook then
        owner:HookScript("OnHide", CloseChannelOrderPopup)
        owner.yuiChatBarOrderPopupHideHook = true
    end
end

local function CloseCustomButtonEditor()
    if customButtonEditor and customButtonEditor.Hide then customButtonEditor:Hide() end
end

local function GetCustomValidationText(code)
    local keys = {
        invalid_custom_text = { "chatbar.custom.error.text", "Button text must contain 1-6 characters." },
        invalid_custom_title = { "chatbar.custom.error.title", "Title must contain 1-80 characters." },
        invalid_custom_color = { "chatbar.custom.error.color", "Choose a valid button color." },
        missing_custom_action = { "chatbar.custom.error.action_required", "Configure at least one mouse action." },
        missing_slash = { "chatbar.custom.error.missing_slash", "Commands must begin with /." },
        invalid_string = { "chatbar.custom.error.invalid_command", "Commands must be one line and no longer than 255 bytes." },
        blocked_command = { "chatbar.custom.error.blocked", "Lua execution commands are not allowed." },
    }
    local value = keys[code]
    return value and ChatBarText(value[1], value[2])
        or ChatBarText("chatbar.custom.error.invalid", "The custom button is invalid.")
end

local function RefreshCustomButtonEditor(editor)
    if not editor or not editor.draft then return end
    local draft = editor.draft
    local normalized, code = NormalizeCustomButton(draft, true, {}, tonumber(draft.id) or 0)
    editor.normalizedDraft = normalized
    if editor.save and editor.save.SetDisabled then editor.save:SetDisabled(normalized == nil) end
    if editor.status then
        editor.status:SetText(normalized and ChatBarText("chatbar.custom.valid", "Ready to save")
            or GetCustomValidationText(code))
        if GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(editor.status, normalized and "color.state.success" or "color.state.danger")
        end
    end

    if editor.preview and editor.previewText then
        local color = draft.color or { 1, 0.82, 0 }
        local db = GetDB()
        local previewWidth = math.max(40, math.min(100, tonumber(db.width) or defaults.width))
        local previewHeight = math.max(20, math.min(50, tonumber(db.height) or defaults.height))
        editor.preview:SetSize(previewWidth, previewHeight)
        if db.style == "BLOCK" then
            editor.preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            editor.preview:SetBackdropColor(color[1] or 1, color[2] or 0.82, color[3] or 0, 1)
            editor.previewText:Hide()
        else
            editor.preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            editor.preview:SetBackdropColor(0, 0, 0, 0)
            editor.previewText:Show()
            editor.previewText:SetText(draft.text or "")
            editor.previewText:SetTextColor(color[1] or 1, color[2] or 0.82, color[3] or 0, 1)
        end
    end

    for mouseButton, counter in pairs(editor.commandCounters or {}) do
        local value = draft.actions and draft.actions[mouseButton] or ""
        counter:SetText(string.format("%d/%d", #value, MAX_CUSTOM_COMMAND_BYTES))
    end
end

local function EnsureCustomButtonEditor()
    if customButtonEditor then return customButtonEditor end
    if not (GUI2 and GUI2.CreatePanel and GUI2.Form and GUI2.Form.CreateEditBox
        and GUI2.Form.CreateButton and GUI2.Form.CreateCheckbox and GUI2.Form.CreateColorPicker) then
        return nil
    end

    local editor = GUI2:CreatePanel(UIParent, {
        width = 560,
        height = 420,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
        shadowKey = "shadow.popup.size",
    })
    editor:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    if editor.SetFrameStrata then editor:SetFrameStrata("FULLSCREEN_DIALOG") end
    if editor.SetFrameLevel then editor:SetFrameLevel(9100) end
    if editor.EnableMouse then editor:EnableMouse(true) end
    editor:Hide()

    editor.heading = GUI2:CreateText(editor, "", "font.size.lg", "color.text.heading")
    editor.heading:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, -18)

    editor.preview = GUI2:CreateButtonFrame(editor, { template = "BackdropTemplate" })
    editor.preview:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -24, -46)
    editor.preview:EnableMouse(false)
    editor.previewText = GUI2:CreateText(editor.preview, "", "font.size.md", "color.text.primary")
    editor.previewText:SetPoint("CENTER")

    editor.enabled = GUI2.Form:CreateCheckbox(editor, {
        label = ChatBarText("chatbar.custom.enabled", "Enabled"),
        width = 160,
        get = function() return editor.draft and editor.draft.enabled == true end,
        set = function(value)
            if editor.draft then editor.draft.enabled = value == true; RefreshCustomButtonEditor(editor) end
        end,
    })
    editor.enabled:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, -54)

    local function AddEditRow(labelKey, fallback, y, width, onChange)
        local label = GUI2:CreateText(editor, ChatBarText(labelKey, fallback), "font.size.md", "color.text.primary")
        label:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, y)
        label:SetWidth(92)
        label:SetJustifyH("LEFT")
        local input = GUI2.Form:CreateEditBox(editor, {
            width = width,
            height = 28,
            autoFocus = false,
            set = onChange,
        })
        input:SetPoint("LEFT", label, "RIGHT", 8, 0)
        return input
    end

    editor.textInput = AddEditRow("chatbar.custom.text", "Button text", -96, 250, function(value)
        if editor.draft then editor.draft.text = value; RefreshCustomButtonEditor(editor) end
    end)
    editor.titleInput = AddEditRow("chatbar.custom.title", "Tooltip title", -132, 404, function(value)
        if editor.draft then editor.draft.title = value; RefreshCustomButtonEditor(editor) end
    end)

    local colorLabel = GUI2:CreateText(editor, ChatBarText("chatbar.custom.color", "Color"), "font.size.md", "color.text.primary")
    colorLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, -168)
    colorLabel:SetWidth(92)
    colorLabel:SetJustifyH("LEFT")
    editor.color = GUI2.Form:CreateColorPicker(editor, {
        width = 44,
        height = 26,
        hasAlpha = false,
        get = function() return editor.draft and editor.draft.color or { 1, 0.82, 0 } end,
        default = { 1, 0.82, 0 },
        set = function(value)
            if editor.draft then
                editor.draft.color = { value[1] or 1, value[2] or 0.82, value[3] or 0 }
                RefreshCustomButtonEditor(editor)
            end
        end,
    })
    editor.color:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)

    editor.commandInputs = {}
    editor.commandCounters = {}
    local commandRows = {
        { "LeftButton", "chatbar.mouse.left", "Left click", -214 },
        { "RightButton", "chatbar.mouse.right", "Right click", -250 },
        { "MiddleButton", "chatbar.mouse.middle", "Middle click", -286 },
    }
    for _, definition in ipairs(commandRows) do
        local mouseButton, key, fallback, y = unpack(definition)
        local input = AddEditRow(key, fallback, y, 360, function(value)
            if editor.draft then
                editor.draft.actions[mouseButton] = value
                RefreshCustomButtonEditor(editor)
            end
        end)
        input:SetMaxLetters(MAX_CUSTOM_COMMAND_BYTES)
        editor.commandInputs[mouseButton] = input
        local counter = GUI2:CreateText(editor, "", "font.size.sm", "color.text.secondary", "RIGHT")
        counter:SetPoint("LEFT", input, "RIGHT", 8, 0)
        counter:SetWidth(54)
        editor.commandCounters[mouseButton] = counter
    end

    editor.status = GUI2:CreateText(editor, "", "font.size.sm", "color.text.secondary")
    editor.status:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 20, 62)
    editor.status:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -20, 62)
    editor.status:SetJustifyH("LEFT")
    editor.status:SetWordWrap(false)

    local cancel = GUI2.Form:CreateButton(editor, {
        text = ChatBarText("common.cancel", "Cancel"),
        width = 84,
        height = 30,
        onClick = CloseCustomButtonEditor,
    })
    cancel:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -20, 18)

    editor.save = GUI2.Form:CreateButton(editor, {
        text = ChatBarText("chatbar.save", "Save"),
        width = 84,
        height = 30,
        state = "selected",
        onClick = function()
            if not editor.normalizedDraft then return end
            local db = GetDB()
            EnsureChannelSettings(db)
            local saved = CopyCustomButton(editor.normalizedDraft)
            local replaced = false
            for index, customButton in ipairs(db.customButtons) do
                if customButton.id == saved.id then
                    db.customButtons[index] = saved
                    replaced = true
                    break
                end
            end
            if not replaced and #db.customButtons >= MAX_CUSTOM_BUTTONS then
                editor.status:SetText(ChatBarText("chatbar.custom.error.limit", "You can create up to 8 custom buttons."))
                if GUI2.SetTextColorKey then GUI2:SetTextColorKey(editor.status, "color.state.danger") end
                return
            end
            if not replaced then db.customButtons[#db.customButtons + 1] = saved end
            db.customButtonSerial = math.max(tonumber(db.customButtonSerial) or 0, saved.id)
            EnsureChannelSettings(db)
            editor:Hide()
            if editor.onCommit then editor.onCommit() end
        end,
    })
    editor.save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)

    customButtonEditor = editor
    return editor
end

local function OpenCustomButtonEditor(owner, customButton, onCommit)
    local editor = EnsureCustomButtonEditor()
    if not editor then return end
    local db = GetDB()
    EnsureChannelSettings(db)
    local isNew = customButton == nil
    if isNew then
        local id = math.max(0, tonumber(db.customButtonSerial) or 0) + 1
        editor.draft = {
            id = id,
            enabled = true,
            text = ChatBarText("chatbar.custom.default_text", "BTN"),
            title = ChatBarText("chatbar.custom.default_title", "Custom button"),
            color = { 1, 0.82, 0 },
            actions = { LeftButton = "", RightButton = "", MiddleButton = "" },
        }
    else
        editor.draft = CopyCustomButton(customButton)
    end
    editor.onCommit = onCommit
    editor.owner = owner
    editor.heading:SetText(isNew and ChatBarText("chatbar.custom.add_title", "Add custom button")
        or ChatBarText("chatbar.custom.edit_title", "Edit custom button"))
    editor.enabled:SetValue(editor.draft.enabled, true)
    editor.textInput:SetValue(editor.draft.text, true)
    editor.titleInput:SetValue(editor.draft.title, true)
    if editor.color.SetValue then editor.color:SetValue(editor.draft.color, true) end
    for mouseButton, input in pairs(editor.commandInputs) do
        input:SetValue(editor.draft.actions[mouseButton], true)
    end
    RefreshCustomButtonEditor(editor)
    if editor.SetFrameLevel then
        local ownerLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel() or 0
        editor:SetFrameLevel(math.max(9100, ownerLevel + 30))
    end
    editor:Show()
    if editor.Raise then editor:Raise() end
    if owner and owner.HookScript and not owner.yuiChatBarCustomEditorHideHook then
        owner:HookScript("OnHide", CloseCustomButtonEditor)
        owner.yuiChatBarCustomEditorHideHook = true
    end
end

-- 获取配置
local function GetOptions(feature)
    local db = GetDB()
    if db.font == nil then db.font = defaults.font end
    if db.locked == nil then db.locked = defaults.locked end
    EnsureChannelSettings(db)
    
    -- 动态刷新函数：重新获取 options
    local function Refresh()
        if feature and feature.RefreshCurrentModule then
            feature:RefreshCurrentModule()
        end
    end

    local function BuildStatusbarOptions()
        local options = {}
        local texList = LSM:HashTable("statusbar")
        for name in pairs(texList) do
            options[#options + 1] = { text = name, value = name }
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        return options
    end

    local function BuildFontOptions()
        local options = {}
        local fontList = LSM:HashTable("font")
        for name, path in pairs(fontList) do
            local fontPath = path
            options[#options + 1] = {
                text = name,
                value = name,
                render = function(button)
                    if button and button.text and fontPath then
                        button.text:SetFont(fontPath, GUI2.Fonts.size_normal)
                    end
                end,
            }
        end
        table.sort(options, function(a, b) return a.text < b.text end)
        return options
    end

    local function ToggleTestNotify()
        if not frame or not frame.collapseBtn then return end
        local btn = frame.collapseBtn
        -- 如果正在测试中（名字为测试员），则隐藏
        if btn.wpName == "勇敢测试员" then
            btn.wpName = nil
            StopNotifyTextBlink(btn)
            SetWhisperNotifyText(btn)
            btn.arrow:Show()
            btn.arrow:SetDesaturated(true)
        else
            btn.wpName = "勇敢测试员"
            btn.arrow:Show()
            btn.arrow:SetDesaturated(false)
            SetWhisperNotifyText(btn, "勇敢测试员")
            StartNotifyTextBlink(btn)
        end
    end

    return {
        {
            type = "custom",
            render = function(parent, x, y, availableWidth)
                local pageWidth = math.min(availableWidth or 620, 620)
                local rowHeight = 32
                local rowGap = 10
                local sectionGap = 14
                local fieldGap = 20
                local labelWidth = 74
                local sliderValueWidth = 44
                local colWidth = math.floor((pageWidth - fieldGap * 2) / 3)
                local controlWidth = colWidth - labelWidth
                local cursorY = 0

                local root = GUI2:CreateFrame(parent, { width = pageWidth, height = 1 })
                root:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

                local function Advance(amount)
                    cursorY = cursorY - amount
                end

                local function AddSection(label)
                    local divider = GUI2:CreateDivider(root, pageWidth, nil, label, true)
                    divider:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY)
                    Advance((divider:GetHeight() or 16) + sectionGap)
                end

                local function AddRow(height, gap)
                    local row = GUI2:CreateFrame(root, { width = pageWidth, height = height or rowHeight })
                    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY)
                    Advance((height or rowHeight) + (gap or rowGap))
                    return row
                end

                local function AddLabel(row, text, xOffset, width)
                    local label = GUI2:CreateText(row, text, "font.size.md", "color.text.primary")
                    label:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                    label:SetWidth(width or labelWidth)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    return label
                end

                local function ColX(index)
                    return (index - 1) * (colWidth + fieldGap)
                end

                local function AddDropdown(row, colIndex, label, opts)
                    local xOffset = ColX(colIndex)
                    AddLabel(row, label, xOffset, labelWidth)
                    local dropdown = GUI2.Form:CreateDropdown(row, {
                        width = controlWidth,
                        options = opts.options,
                        get = opts.get,
                        set = opts.set,
                    })
                    dropdown:SetPoint("LEFT", row, "LEFT", xOffset + labelWidth, 0)
                    return dropdown
                end

                local function AddSlider(row, colIndex, label, opts)
                    local slider = GUI2.Form:CreateSlider(row, {
                        label = label,
                        inline = true,
                        width = colWidth,
                        labelWidth = labelWidth,
                        inputWidth = sliderValueWidth,
                        min = opts.min,
                        max = opts.max,
                        step = opts.step,
                        get = opts.get,
                        set = opts.set,
                    })
                    slider:SetPoint("LEFT", row, "LEFT", ColX(colIndex), 0)
                    return slider
                end

                local function AddCheckbox(row, colIndex, label, opts)
                    local checkbox = GUI2.Form:CreateCheckbox(row, {
                        label = label,
                        width = colWidth,
                        get = opts.get,
                        set = opts.set,
                    })
                    checkbox:SetPoint("LEFT", row, "LEFT", ColX(colIndex), 0)
                    return checkbox
                end

                local function AddButton(row, colIndex, label, onClick, buttonOptions)
                    buttonOptions = buttonOptions or {}
                    local button = GUI2.Form:CreateButton(row, {
                        text = label,
                        width = buttonOptions.width or colWidth,
                        height = buttonOptions.height or rowHeight,
                        onClick = onClick,
                    })
                    button:SetPoint("LEFT", row, "LEFT", ColX(colIndex), 0)
                    return button
                end

                local function AddSimpleTooltip(widget, text)
                    if not widget or not text or text == "" then return end
                    local originalOnEnter = widget:GetScript("OnEnter")
                    local originalOnLeave = widget:GetScript("OnLeave")
                    widget:SetScript("OnEnter", function(self)
                        if originalOnEnter then originalOnEnter(self) end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(text, 1, 0.82, 0, 1, true)
                        GameTooltip:Show()
                    end)
                    widget:SetScript("OnLeave", function(self)
                        if originalOnLeave then originalOnLeave(self) end
                        YUI.HideGameTooltip()
                    end)
                end

                AddSection(ChatBarText("chatbar.settings.style_section", "Style"))
                local basicRow = AddRow(rowHeight)
                AddDropdown(basicRow, 1, ChatBarText("chatbar.settings.style", "Style"), {
                    options = {
                        { text = ChatBarText("chatbar.settings.style.text", "Text"), value = "TEXT" },
                        { text = ChatBarText("chatbar.settings.style.block", "Block"), value = "BLOCK" },
                    },
                    get = function() return db.style end,
                    set = function(v)
                        db.style = v
                        UpdateLayout(true)
                        Refresh()
                    end,
                })
                AddDropdown(basicRow, 2, ChatBarText("common.font", "Font"), {
                    options = BuildFontOptions,
                    get = function() return db.font end,
                    set = function(v)
                        db.font = v
                        UpdateLayout(true)
                        UpdateCollapseFont()
                    end,
                })
                AddCheckbox(basicRow, 3, ChatBarText("chatbar.settings.lock", "Lock"), {
                    get = function() return db.locked end,
                    set = function(v)
                        db.locked = v
                        RefreshTooltipIfOwned()
                    end,
                })

                if db.style == "BLOCK" then
                    local blockRow = AddRow(rowHeight)
                    AddDropdown(blockRow, 1, ChatBarText("chatbar.settings.block_texture", "Block Texture"), {
                        options = BuildStatusbarOptions,
                        get = function() return db.blockTexture or "Solid" end,
                        set = function(v) db.blockTexture = v; UpdateLayout(true) end,
                    })
                    AddCheckbox(blockRow, 2, ChatBarText("chatbar.settings.block_shadow", "Block Shadow"), {
                        get = function() return db.blockShadow end,
                        set = function(v) db.blockShadow = v; UpdateLayout(true) end,
                    })
                end

                AddSection(ChatBarText("chatbar.settings.layout_section", "Button Layout"))
                local sizeRow = AddRow(rowHeight)
                AddSlider(sizeRow, 1, ChatBarText("chatbar.settings.button_width", "Button Width"), {
                    min = 10, max = 100, step = 1,
                    get = function() return db.width end,
                    set = function(v) db.width = v; UpdateLayout(true) end,
                })
                AddSlider(sizeRow, 2, ChatBarText("chatbar.settings.button_height", "Button Height"), {
                    min = 10, max = 50, step = 1,
                    get = function() return db.height end,
                    set = function(v) db.height = v; UpdateLayout(true) end,
                })
                AddSlider(sizeRow, 3, ChatBarText("chatbar.settings.button_spacing", "Button Spacing"), {
                    min = -20, max = 20, step = 1,
                    get = function() return db.spacing end,
                    set = function(v) db.spacing = v; UpdateLayout(true) end,
                })

                local directionRow = AddRow(rowHeight)
                AddDropdown(directionRow, 1, ChatBarText("chatbar.settings.direction", "Open Direction"), {
                    options = {
                        { text = ChatBarText("common.right", "Right"), value = "RIGHT" },
                        { text = ChatBarText("common.left", "Left"), value = "LEFT" },
                        { text = ChatBarText("common.top", "Up"), value = "UP" },
                        { text = ChatBarText("common.bottom", "Down"), value = "DOWN" },
                    },
                    get = function() return db.direction end,
                    set = function(v) db.direction = v; UpdateLayout(true) end,
                })
                AddCheckbox(directionRow, 2, ChatBarText("chatbar.settings.reverse", "Reverse"), {
                    get = function() return db.reverse end,
                    set = function(v) db.reverse = v; UpdateLayout(true) end,
                })

                AddSection(ChatBarText("chatbar.settings.whisper_section", "Whisper Alert"))
                local notifyRow = AddRow(rowHeight)
                AddDropdown(notifyRow, 1, ChatBarText("chatbar.settings.notify_position", "Alert Position"), {
                    options = {
                        { text = ChatBarText("common.right", "Right"), value = "RIGHT" },
                        { text = ChatBarText("common.left", "Left"), value = "LEFT" },
                        { text = ChatBarText("common.top", "Top"), value = "UP" },
                        { text = ChatBarText("common.bottom", "Bottom"), value = "DOWN" },
                    },
                    get = function() return db.notifyPosition or "RIGHT" end,
                    set = function(v) db.notifyPosition = v; UpdateNotifyTextPosition() end,
                })
                AddSlider(notifyRow, 2, ChatBarText("chatbar.settings.icon_x", "Icon X"), {
                    min = -50, max = 50, step = 1,
                    get = function() return db.iconOffsetX or 0 end,
                    set = function(v) db.iconOffsetX = v; UpdateIconPosition() end,
                })
                AddSlider(notifyRow, 3, ChatBarText("chatbar.settings.icon_y", "Icon Y"), {
                    min = -50, max = 50, step = 1,
                    get = function() return db.iconOffsetY or 0 end,
                    set = function(v) db.iconOffsetY = v; UpdateIconPosition() end,
                })

                local notifyTextOffsetRow = AddRow(rowHeight)
                AddSlider(notifyTextOffsetRow, 1, ChatBarText("chatbar.settings.text_x", "Text X"), {
                    min = -100, max = 100, step = 1,
                    get = function() return db.notifyTextOffsetX or 0 end,
                    set = function(v) db.notifyTextOffsetX = v; UpdateNotifyTextPosition() end,
                })
                AddSlider(notifyTextOffsetRow, 2, ChatBarText("chatbar.settings.text_y", "Text Y"), {
                    min = -100, max = 100, step = 1,
                    get = function() return db.notifyTextOffsetY or 0 end,
                    set = function(v) db.notifyTextOffsetY = v; UpdateNotifyTextPosition() end,
                })

                local notifyActionRow = AddRow(rowHeight)
                AddCheckbox(notifyActionRow, 1, ChatBarText("chatbar.settings.mask_name", "Mask Name"), {
                    get = function() return db.maskWhisperName end,
                    set = function(v)
                        db.maskWhisperName = v
                        if frame and frame.collapseBtn and frame.collapseBtn.wpName then
                            SetWhisperNotifyText(frame.collapseBtn, frame.collapseBtn.wpName)
                        end
                    end,
                })
                AddButton(notifyActionRow, 2, ChatBarText("chatbar.settings.test_alert", "Test Alert"), ToggleTestNotify)

                AddSection(ChatBarText("chatbar.quick_buttons", "Quick buttons"))
                local channelActionRow = AddRow(rowHeight)
                local editOrderButton = AddButton(channelActionRow, 1, ChatBarText("chatbar.edit_order", "编辑顺序"), function()
                    OpenChannelOrderPopup(root, function()
                        UpdateLayout(true)
                        Refresh()
                    end)
                end, { width = 112, height = 26 })
                local restoreColorsButton = AddButton(channelActionRow, 2, ChatBarText("chatbar.restore_default_colors", "恢复默认颜色"), function()
                    db.channelColors = {}
                    UpdateLayout(true)
                    Refresh()
                end, { width = 130, height = 26 })
                restoreColorsButton:ClearAllPoints()
                restoreColorsButton:SetPoint("LEFT", editOrderButton, "RIGHT", 8, 0)

                local orderedChannels = {}
                for _, info in ipairs(GetOrderedChannels(db)) do
                    if not info.customButton then orderedChannels[#orderedChannels + 1] = info end
                end
                local channelColumns = 6
                local channelGap = 8
                local channelCellWidth = math.floor((pageWidth - channelGap * (channelColumns - 1)) / channelColumns)
                local channelRows = math.ceil(#orderedChannels / channelColumns)
                if channelRows < 1 then channelRows = 1 end
                local channelHeight = (channelRows * rowHeight) + ((channelRows - 1) * channelGap)
                local channelGrid = AddRow(channelHeight, 0)
                for index, info in ipairs(orderedChannels) do
                    local channel = info
                    local rowIndex = math.floor((index - 1) / channelColumns)
                    local colIndex = (index - 1) % channelColumns
                    local cellX = colIndex * (channelCellWidth + channelGap)
                    local cellY = -(rowIndex * (rowHeight + channelGap))
                    local checkbox = GUI2.Form:CreateCheckbox(channelGrid, {
                        label = "",
                        width = 20,
                        get = function() return db.channels[channel.key] end,
                        set = function(v) db.channels[channel.key] = v; UpdateLayout(true) end,
                    })
                    checkbox:SetPoint("TOPLEFT", channelGrid, "TOPLEFT", cellX, cellY)
                    AddSimpleTooltip(checkbox, channel.tooltip or channel.name)

                    local colorPicker
                    local colorLink = GUI2.Form:CreateTextLink(channelGrid, {
                        text = channel.name,
                        width = math.max(48, channelCellWidth - 30),
                        height = rowHeight,
                        onClick = function()
                            if colorPicker and colorPicker.GetScript then
                                local onClick = colorPicker:GetScript("OnClick")
                                if onClick then onClick(colorPicker) end
                            end
                        end,
                    })
                    if colorLink.underline then colorLink.underline:Hide() end
                    colorLink:SetPoint("TOPLEFT", channelGrid, "TOPLEFT", cellX + 26, cellY)
                    if colorLink.text then
                        colorLink.text:ClearAllPoints()
                        colorLink.text:SetPoint("LEFT", colorLink, "LEFT", 0, 1)
                        colorLink.text:SetWidth(colorLink:GetWidth())
                        colorLink.text:SetJustifyH("LEFT")
                    end

                    local function ApplyChannelTextColor()
                        local color = GetChannelColor(db, channel)
                        if colorLink.text then
                            colorLink.text.gui2ColorKey = nil
                            colorLink.text.gui2ColorFallback = nil
                            colorLink.text:SetTextColor(color[1], color[2], color[3], 1)
                        end
                    end
                    ApplyChannelTextColor()
                    local originalLinkRefreshTheme = colorLink.RefreshTheme
                    colorLink.RefreshTheme = function(self)
                        if originalLinkRefreshTheme then originalLinkRefreshTheme(self) end
                        ApplyChannelTextColor()
                    end
                    local originalLinkOnEnter = colorLink:GetScript("OnEnter")
                    local originalLinkOnLeave = colorLink:GetScript("OnLeave")
                    colorLink:SetScript("OnEnter", function(self)
                        if originalLinkOnEnter then originalLinkOnEnter(self) end
                        ApplyChannelTextColor()
                    end)
                    colorLink:SetScript("OnLeave", function(self)
                        if originalLinkOnLeave then originalLinkOnLeave(self) end
                        ApplyChannelTextColor()
                    end)
                    AddSimpleTooltip(colorLink, ChatBarText("chatbar.channel_color_tooltip", "点击频道文字修改颜色"))

                    local originalColor = GetChannelColor(db, channel)
                    originalColor = { originalColor[1], originalColor[2], originalColor[3] }
                    colorPicker = GUI2.Form:CreateColorPicker(channelGrid, {
                        width = 1,
                        height = 1,
                        hasAlpha = false,
                        default = channel.color,
                        get = function() return GetChannelColor(db, channel) end,
                        set = function(value)
                            SetChannelColor(db, channel.key, value)
                            UpdateLayout(true)
                            Refresh()
                        end,
                    })
                    if colorPicker.SetColorLifecycle then
                        colorPicker:SetColorLifecycle(
                            function(value)
                                SetChannelColor(db, channel.key, value)
                                ApplyChannelTextColor()
                                UpdateLayout(true)
                            end,
                            function(value)
                                SetChannelColor(db, channel.key, value)
                                ApplyChannelTextColor()
                                UpdateLayout(true)
                                Refresh()
                            end,
                            function()
                                SetChannelColor(db, channel.key, originalColor)
                                ApplyChannelTextColor()
                                UpdateLayout(true)
                            end
                        )
                    end
                    colorPicker:Hide()
                end

                AddSection(ChatBarText("chatbar.custom.section", "Custom buttons"))
                local customActionRow = AddRow(rowHeight)
                local addCustomButton = AddButton(customActionRow, 1,
                    ChatBarText("chatbar.custom.add", "Add custom button"),
                    function()
                        OpenCustomButtonEditor(root, nil, function()
                            UpdateLayout(true)
                            Refresh()
                        end)
                    end,
                    { width = 150, height = 26 })
                if addCustomButton.SetDisabled then
                    addCustomButton:SetDisabled(#db.customButtons >= MAX_CUSTOM_BUTTONS)
                end
                local countText = GUI2:CreateText(
                    customActionRow,
                    string.format(ChatBarText("chatbar.custom.count", "%d/%d buttons"), #db.customButtons, MAX_CUSTOM_BUTTONS),
                    "font.size.sm",
                    #db.customButtons >= MAX_CUSTOM_BUTTONS and "color.state.warning" or "color.text.secondary"
                )
                countText:SetPoint("LEFT", addCustomButton, "RIGHT", 12, 0)

                for _, customButton in ipairs(db.customButtons) do
                    local item = customButton
                    local row = AddRow(34, 6)
                    local enabled = GUI2.Form:CreateCheckbox(row, {
                        label = "",
                        width = 20,
                        get = function() return item.enabled == true end,
                        set = function(value)
                            item.enabled = value == true
                            UpdateLayout(true)
                        end,
                    })
                    enabled:SetPoint("LEFT", row, "LEFT", 0, 0)

                    local swatch = GUI2:CreateTexture(row, { layer = "ARTWORK" })
                    swatch:SetSize(16, 16)
                    swatch:SetPoint("LEFT", enabled, "RIGHT", 8, 0)
                    swatch:SetColorTexture(item.color[1], item.color[2], item.color[3], 1)

                    local name = GUI2:CreateText(row, item.text, "font.size.md", "color.text.primary")
                    name.gui2ColorKey = nil
                    name.gui2ColorFallback = nil
                    name:SetTextColor(item.color[1], item.color[2], item.color[3], 1)
                    name:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
                    name:SetWidth(64)
                    name:SetWordWrap(false)

                    local titleText = GUI2:CreateText(row, item.title, "font.size.sm", "color.text.secondary")
                    titleText:SetPoint("LEFT", name, "RIGHT", 8, 0)
                    titleText:SetWidth(206)
                    titleText:SetWordWrap(false)

                    local actions = GUI2:CreateText(row, "", "font.size.sm", "color.text.secondary", "CENTER")
                    local actionLabels = {}
                    if item.actions.LeftButton ~= "" then actionLabels[#actionLabels + 1] = "L" end
                    if item.actions.RightButton ~= "" then actionLabels[#actionLabels + 1] = "R" end
                    if item.actions.MiddleButton ~= "" then actionLabels[#actionLabels + 1] = "M" end
                    actions:SetText(table.concat(actionLabels, "/"))
                    actions:SetPoint("LEFT", titleText, "RIGHT", 8, 0)
                    actions:SetWidth(48)

                    local edit = GUI2.Form:CreateButton(row, {
                        text = ChatBarText("chatbar.custom.edit", "Edit"),
                        width = 62,
                        height = 26,
                        onClick = function()
                            OpenCustomButtonEditor(root, item, function()
                                UpdateLayout(true)
                                Refresh()
                            end)
                        end,
                    })
                    edit:SetPoint("RIGHT", row, "RIGHT", -70, 0)

                    local deleteButton = GUI2.Form:CreateButton(row, {
                        text = ChatBarText("chatbar.custom.delete", "Delete"),
                        width = 62,
                        height = 26,
                        tone = "warning",
                        onClick = function()
                            local function DeleteCustomButton()
                                for index, current in ipairs(db.customButtons) do
                                    if current.id == item.id then
                                        table.remove(db.customButtons, index)
                                        break
                                    end
                                end
                                EnsureChannelSettings(db)
                                UpdateLayout(true)
                                Refresh()
                            end
                            local Settings = YUI.Settings
                            if Settings and type(Settings.ShowConfirmPopup) == "function" then
                                Settings:ShowConfirmPopup(
                                    string.format(
                                        ChatBarText("chatbar.custom.delete_confirm", "Delete custom button [%s]?"),
                                        item.title
                                    ),
                                    DeleteCustomButton,
                                    { titleText = ChatBarText("chatbar.custom.delete_title", "Delete custom button") }
                                )
                            else
                                DeleteCustomButton()
                            end
                        end,
                    })
                    deleteButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                end

                local totalHeight = math.abs(cursorY) + 4
                root:SetHeight(totalHeight)
                return pageWidth, totalHeight
            end,
        },
    }
end

local CHATBAR_TRANSFER_FIELDS = {
    style = true,
    direction = true,
    reverse = true,
    width = true,
    height = true,
    spacing = true,
    autoHide = true,
    blockTexture = true,
    blockShadow = true,
    notifyPosition = true,
    notifyTextOffsetX = true,
    notifyTextOffsetY = true,
    maskWhisperName = true,
    iconOffsetX = true,
    iconOffsetY = true,
    font = true,
    locked = true,
    channelColors = true,
    channelOrder = true,
    customButtonSerial = true,
    customButtons = true,
    channels = true,
    pos = true,
    size = true,
}

local function NormalizeChatBarTransferPayload(payload)
    if type(payload) ~= "table" then return nil, "invalid_module_payload" end
    for key in pairs(payload) do
        if key ~= "data" and key ~= "present" and key ~= "layouts"
            and key ~= "layoutPresent" and key ~= "enabled" then
            return nil, "invalid_module_payload"
        end
    end
    if type(payload.data) ~= "table" or type(payload.present) ~= "table"
        or type(payload.layouts) ~= "table" or type(payload.layoutPresent) ~= "table"
        or type(payload.enabled) ~= "boolean" then
        return nil, "invalid_module_payload"
    end

    local configPath = "ChatBar_Config"
    for path in pairs(payload.data) do
        if path ~= configPath then return nil, "unexpected_data_path" end
    end
    for path, present in pairs(payload.present) do
        if path ~= configPath or type(present) ~= "boolean" then
            return nil, "unexpected_data_path"
        end
    end
    if type(payload.present[configPath]) ~= "boolean"
        or (payload.present[configPath] and type(payload.data[configPath]) ~= "table")
        or (not payload.present[configPath] and payload.data[configPath] ~= nil) then
        return nil, "invalid_module_payload"
    end

    for layoutId in pairs(payload.layouts) do
        if layoutId ~= CHATBAR_LAYOUT_ID then return nil, "unexpected_layout" end
    end
    for layoutId, present in pairs(payload.layoutPresent) do
        if layoutId ~= CHATBAR_LAYOUT_ID or type(present) ~= "boolean" then
            return nil, "unexpected_layout"
        end
    end
    if type(payload.layoutPresent[CHATBAR_LAYOUT_ID]) ~= "boolean" then
        return nil, "unexpected_layout"
    end

    local config = payload.data[configPath]
    if config then
        for key in pairs(config) do
            if not CHATBAR_TRANSFER_FIELDS[key] then return nil, "unexpected_data_field" end
        end
        if config.customButtonSerial ~= nil then
            local serial = tonumber(config.customButtonSerial)
            if not serial or serial < 0 or serial ~= math.floor(serial) then
                return nil, "invalid_custom_id"
            end
        end
        local normalized, code = NormalizeCustomButtons(config, true)
        if not normalized then return nil, code end
        EnsureChannelSettings(config)
    end
    return payload
end

-- 注册功能
YUI.Components:RegisterFeature("ChatBar", {
    product = PRODUCT_ID,
    name = "聊天条",
    default = true,
    description = "提供频道快捷按钮，并集成密语、交易记录和常用聊天操作。",
    callback = function(enable)
        local db = GetDB()
        
        -- 合并默认配置
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        -- 兼容旧数据: size -> width/height
        if db.size then
            if not db.width then db.width = db.size end
            if not db.height then db.height = db.size end
            db.size = nil -- 清理旧字段
        end
        
        EnsureChannelSettings(db)
        
        chatBarActive = enable == true
        channelRequestSerial = channelRequestSerial + 1

        if enable then
            InitUI()
            if frame then
                AttachWhisperNotifyRuntime(frame.collapseBtn)
                AttachChatFadeRuntime()
                frame:Show()
                if frame.collapseBtn and frame.collapseBtn.RefreshWhisperNotify then
                    frame.collapseBtn:RefreshWhisperNotify()
                end
            end
        else
            if frame then
                if frame.collapseBtn then
                    DetachWhisperNotifyRuntime(frame.collapseBtn)
                    StopNotifyTextBlink(frame.collapseBtn)
                end
                DetachChatFadeRuntime()
                frame:Hide()
            end
        end
    end,
    GetOptions = GetOptions,
    transfer = {
        dataPaths = { "ChatBar_Config" },
        fieldWhitelists = {
            ChatBar_Config = CHATBAR_TRANSFER_FIELDS,
        },
        normalize = NormalizeChatBarTransferPayload,
    },
})
