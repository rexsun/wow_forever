local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable

if not YUI or not YUI.Components then return end
local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"

local Assets = YUI.Assets
local UnitAPI = (YUI.API and YUI.API.Unit) or YUI.WOW_API
local CombatAPI = (YUI.API and YUI.API.Combat) or YUI.WOW_API
local Bloodlust = YUI.Bloodlust
local CoreLocale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("Core") or {}
local function T(key, fallback)
    return CoreLocale[key] or fallback or key
end
local function MusicPath(fileName)
    return Assets:Component("SXMusic", "sound\\sx_bgm\\" .. fileName)
end

local BUILTIN_MUSIC = {
    { name = "云宫迅音", path = MusicPath("云宫迅音.mp3") },
    { name = "光能使者", path = MusicPath("光能使者.mp3") },
    { name = "动天", path = MusicPath("动天.mp3") },
    { name = "四代目火影", path = MusicPath("四代目火影.mp3") },
    { name = "天马座的幻想", path = MusicPath("天马座的幻想.mp3") },
    { name = "数码宝贝", path = MusicPath("数码宝贝.mp3") },
    { name = "热烈的决斗者", path = MusicPath("热烈的决斗者.mp3") },
    { name = "美少女战士", path = MusicPath("美少女战士.mp3") },
    { name = "路飞猛攻", path = MusicPath("路飞猛攻.mp3") },
    { name = "黑神话广智", path = MusicPath("黑神话广智.mp3") },
}

local CUSTOM_PATH_PREFIX = "Interface\\AddOns\\"
local CUSTOM_EXAMPLE_PATH = CUSTOM_PATH_PREFIX .. "YUI\\Media\\数码宝贝.mp3"
local CUSTOM_RELOAD_WARNING_TEXT = T("sxmusic.custom_reload_warning", "Restart the game after adding new files.")
local MAX_CUSTOM_MUSIC = 24
local PLAY_BUTTON_SIZE = 26
local PLAY_ICON_ATLAS = "common-dropdown-icon-next"
local STOP_ICON_ATLAS = "common-dropdown-icon-stop"
local GetDB
local defaults = {
    builtin = {},
    custom = { "" },
    channel = "Master",
    customRows = 1,
}

local SOUND_CHANNELS = {
    { text = T("sound.channel.master", "Master"), value = "Master" },
    { text = T("sound.channel.sfx", "Sound Effects"), value = "SFX", cvar = "Sound_SFXVolume" },
    { text = T("sound.channel.music", "Music"), value = "Music", cvar = "Sound_MusicVolume" },
    { text = T("sound.channel.ambience", "Ambience"), value = "Ambience", cvar = "Sound_AmbienceVolume" },
    { text = T("sound.channel.dialog", "Dialog"), value = "Dialog", cvar = "Sound_DialogVolume" },
}

local VALID_SOUND_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local function IsValidSoundChannel(channel)
    return VALID_SOUND_CHANNELS[channel] == true
end

local function GetCVarPercent(cvar)
    if type(GetCVar) ~= "function" then return nil end
    local value = tonumber(GetCVar(cvar))
    if not value then return nil end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor(value * 100 + 0.5)
end

local function GetSoundChannelOptions()
    local options = {}
    for i, channel in ipairs(SOUND_CHANNELS) do
        local text = channel.text
        if channel.cvar then
            local percent = GetCVarPercent(channel.cvar)
            if percent then
                text = string.format("%s %d%%", text, percent)
            end
        end
        options[i] = {
            text = text,
            value = channel.value,
        }
    end
    return options
end

local function NormalizeCustomPath(path)
    if type(path) ~= "string" then return "" end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    local prefixLength = #CUSTOM_PATH_PREFIX
    if path:lower():sub(1, prefixLength) == CUSTOM_PATH_PREFIX:lower() then
        path = path:sub(prefixLength + 1)
    end
    return path
end

local function BuildCustomMusicPath(path)
    path = NormalizeCustomPath(path)
    if path == "" then return nil end
    return CUSTOM_PATH_PREFIX .. path
end

local customPathStates = {}

local function ResetCustomPathStates()
    for key in pairs(customPathStates) do
        customPathStates[key] = nil
    end
end

local function CompactCustomMusicRows(db)
    if not db or type(db.custom) ~= "table" then return end

    local compacted = {}
    for i = 1, MAX_CUSTOM_MUSIC do
        local path = NormalizeCustomPath(db.custom[i])
        if path ~= "" then
            compacted[#compacted + 1] = path
        end
    end

    for i = 1, MAX_CUSTOM_MUSIC do
        db.custom[i] = compacted[i] or ""
    end
    while #db.custom > MAX_CUSTOM_MUSIC do
        db.custom[#db.custom] = nil
    end

    db.customRows = math.max(1, #compacted)
    ResetCustomPathStates()
end

local activeMusicToast
local function ShowMusicToast(title, body)
    local GUI2 = YUI.GUI2
    if GUI2 and GUI2.Overlay and GUI2.Overlay.CreateToast and UIParent then
        if activeMusicToast and activeMusicToast.Hide then
            activeMusicToast:Hide()
        end

        local toast = GUI2.Overlay:CreateToast(UIParent, {
            width = 430,
            title = title,
            body = body,
            tone = "warning",
        })
        toast:SetFrameStrata("TOOLTIP")
        toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
        activeMusicToast = toast

        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if activeMusicToast == toast then
                    toast:Hide()
                    activeMusicToast = nil
                end
            end)
        end
        return
    end

    if YUI.Print then
        YUI:Print(title .. "：" .. body)
    end
end

local function SetCustomPathEditState(editbox, state)
    if not editbox or not editbox.SetTextColor then return end

    local GUI2 = YUI.GUI2
    if not GUI2 or not GUI2.GetColor then return end

    local colorKey = "color.text.primary"
    if state == "valid" then
        colorKey = "color.state.success"
    elseif state == "invalid" then
        colorKey = "color.state.error"
    end

    editbox:SetTextColor(GUI2:GetColor(colorKey))
end

local function ValidateCustomMusicPath(db, index, editbox)
    local path = BuildCustomMusicPath(db.custom[index])
    if not path then
        customPathStates[index] = nil
        SetCustomPathEditState(editbox, nil)
        return nil, nil
    end

    local willPlay, handle = PlaySoundFile(path, GetDB().channel)
    if willPlay then
        if handle then StopSound(handle) end
        customPathStates[index] = "valid"
        SetCustomPathEditState(editbox, "valid")
    else
        customPathStates[index] = "invalid"
        SetCustomPathEditState(editbox, "invalid")
    end
    return willPlay, path
end

function GetDB()
    local db = (Components and Components.EnsureConfig and Components:EnsureConfig("SXMusic_Config", defaults, PRODUCT_ID)) or defaults
    
    if type(db.builtin) ~= "table" then db.builtin = {} end
    for i = 1, #BUILTIN_MUSIC do
        if db.builtin[i] == nil then db.builtin[i] = true end
    end
    
    if type(db.custom) ~= "table" then db.custom = { "" } end
    local lastCustomRow = 0
    for i = 1, MAX_CUSTOM_MUSIC do
        db.custom[i] = NormalizeCustomPath(db.custom[i])
        if db.custom[i] ~= "" then lastCustomRow = i end
    end
    while #db.custom > MAX_CUSTOM_MUSIC do
        db.custom[#db.custom] = nil
    end

    if not IsValidSoundChannel(db.channel) then db.channel = "Master" end

    local customRows = tonumber(db.customRows)
    if not customRows then customRows = math.max(1, lastCustomRow) end
    customRows = math.floor(customRows)
    if customRows < 1 then customRows = 1 end
    if customRows < lastCustomRow then customRows = lastCustomRow end
    if customRows > MAX_CUSTOM_MUSIC then customRows = MAX_CUSTOM_MUSIC end
    db.customRows = customRows
    
    return db
end

local currentSoundHandle
local currentSoundSource
local Engine = { sxActive = false, lastSXTriggerToken = nil, activeTimer = nil }
local playbackIconButtons = setmetatable({}, { __mode = "k" })
local playbackTextButtons = setmetatable({}, { __mode = "k" })

local function IsMusicPlaying()
    return currentSoundHandle ~= nil
end

local function RefreshPlaybackControls()
    local isPlaying = IsMusicPlaying()
    local atlas = isPlaying and STOP_ICON_ATLAS or PLAY_ICON_ATLAS
    for button in pairs(playbackIconButtons) do
        if button.playbackIcon and button.playbackIcon.SetAtlas then
            button.playbackIcon:SetAtlas(atlas)
        end
    end

    local label = isPlaying and T("sxmusic.stop", "Stop") or T("sxmusic.preview", "Preview")
    for button in pairs(playbackTextButtons) do
        if button.SetText then button:SetText(label) end
    end
end

local function SetCurrentSoundHandle(handle, source)
    currentSoundHandle = handle
    currentSoundSource = source
    RefreshPlaybackControls()
end

local function StopCurrentSound()
    if currentSoundHandle then
        StopSound(currentSoundHandle)
        currentSoundHandle = nil
    end
    currentSoundSource = nil
    RefreshPlaybackControls()
end

local function StopMusic()
    StopCurrentSound()
    if Engine.activeTimer then
        if Engine.activeTimer.Cancel then
            Engine.activeTimer:Cancel()
        end
        Engine.activeTimer = nil
    end
    Engine.sxActive = false
    RefreshPlaybackControls()
end

local function StopPreviewMusic()
    if currentSoundSource == "preview" then
        StopMusic()
    end
end

local function ResetPlaybackButtonRegistry()
    playbackIconButtons = setmetatable({}, { __mode = "k" })
    playbackTextButtons = setmetatable({}, { __mode = "k" })
    RefreshPlaybackControls()
end

-- 播放音乐
local function PlaySXEffect(source)
    StopCurrentSound()
    
    local db = GetDB()
    local playList = {}
    
    -- 收集选中的内置音乐
    for i, music in ipairs(BUILTIN_MUSIC) do
        if db.builtin[i] then
            table.insert(playList, music.path)
        end
    end
    
    -- 收集填写的自定义音乐
    for i = 1, MAX_CUSTOM_MUSIC do
        local path = BuildCustomMusicPath(db.custom[i])
        if path then
            table.insert(playList, path)
        end
    end
    
    while #playList > 0 do
        local index = math.random(1, #playList)
        local soundFile = playList[index]
        table.remove(playList, index)
        local willPlay, handle = PlaySoundFile(soundFile, db.channel)
        if willPlay and handle then
            SetCurrentSoundHandle(handle, source or "auto")
            return true
        end
    end

    StopCurrentSound()
    return false
end

local SX_DEFAULT_DURATION = 40
local SX_BUFF_IDS_WRATH = { [2825]=true, [32182]=true }

local isReady = false 
local bloodlustHandle

local function GetCurrentTime()
    if CombatAPI and CombatAPI.GetTime then
        return CombatAPI.GetTime()
    end
    return GetTime and GetTime() or 0
end

local function GetPlayerAuraBySpellID(spellId)
    if UnitAPI and UnitAPI.GetPlayerAuraBySpellID then
        return UnitAPI.GetPlayerAuraBySpellID(spellId)
    end
    return nil
end

local function ConfirmSX(duration, useStopTimer)
    if Engine.sxActive then return end
    Engine.sxActive = true
    
    if UnitIsDeadOrGhost("player") then
        Engine.sxActive = false
        return
    end

    if not PlaySXEffect("auto") then
        Engine.sxActive = false
        return
    end

    if not useStopTimer then
        return
    end

    local stopAfter = tonumber(duration) or SX_DEFAULT_DURATION
    if stopAfter <= 0 then stopAfter = SX_DEFAULT_DURATION end
    if C_Timer and C_Timer.After then
        Engine.activeTimer = C_Timer.After(stopAfter, function()
            StopMusic()
        end)
    end
end

local function GetWrathSXBuffTrigger()
    local now = GetCurrentTime()
    for id in pairs(SX_BUFF_IDS_WRATH) do
        local aura = GetPlayerAuraBySpellID(id)
        if aura then
            local expirationTime = tonumber(aura.expirationTime)
            local remaining = expirationTime and (expirationTime - now) or nil
            if not remaining or remaining > 0 then
                local token = aura.auraInstanceID or expirationTime or id
                return true, token, remaining
            end
        end
    end
    return false, nil, nil
end

local function RefreshSXMusicState(reason)
    if not isReady then return end
    if not YUI.IsWrath then return end

    local active, token = GetWrathSXBuffTrigger()
    if active and token then
        if Engine.sxActive and currentSoundSource == "auto" then
            Engine.lastSXTriggerToken = token
            return
        end

        if token ~= Engine.lastSXTriggerToken or currentSoundSource ~= "auto" then
            Engine.lastSXTriggerToken = token
            ConfirmSX(nil, false)
        end
        return
    end

    Engine.lastSXTriggerToken = nil
    if Engine.sxActive and currentSoundSource == "auto" then
        StopMusic()
    end
end

local EventOwner = {}
local isHooked = false

local function OnBloodlustWindow(_, state)
    if not isReady or type(state) ~= "table" then return end
    if state.active == true then
        if not Engine.sxActive or currentSoundSource ~= "auto" then
            ConfirmSX(nil, false)
        end
    elseif Engine.sxActive and currentSoundSource == "auto" then
        StopMusic()
    end
end

local function ScheduleReadyCheck()
    local function ready()
        if not isHooked then return end
        isReady = true
        RefreshSXMusicState("ready")
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, ready)
    else
        ready()
    end
end

local function OnSXMusicEvent(event, ...)
    if event == "YUI_WORLD_READY" then
        isReady = false 
        Engine.sxActive = false
        StopMusic()

        if YUI.IsWrath then
            ScheduleReadyCheck()
        else
            isReady = true
        end
    elseif event == "UNIT_AURA" then
        if isReady and YUI.IsWrath then
            RefreshSXMusicState("unit-aura")
        end
    elseif event == "PLAYER_DEAD" then
        if Engine.sxActive then
            StopMusic()
        end
    end
end

local function ToggleSXMusic(enable)
    YUI:Debug(string.format('Components | 嗜血音乐 | %s', enable and '开启' or '关闭'))
    
    if enable then
        if not isHooked then
            YUI.Event:On("YUI_WORLD_READY", OnSXMusicEvent, EventOwner)
            YUI.Event:On("PLAYER_DEAD", OnSXMusicEvent, EventOwner)
            if YUI.IsWrath then
                YUI.Event:On(
                    "UNIT_AURA",
                    OnSXMusicEvent,
                    EventOwner,
                    { unit = "player" }
                )
            elseif Bloodlust and Bloodlust.Acquire then
                bloodlustHandle = Bloodlust:Acquire(
                    EventOwner,
                    OnBloodlustWindow
                )
            end
            
            isHooked = true
            
            -- 如果已经在游戏内（例如登录后手动开启），直接初始化
            if IsLoggedIn() then
                isReady = false 
                Engine.sxActive = false
                StopMusic()

                if YUI.IsWrath then
                    ScheduleReadyCheck()
                else
                    isReady = true
                end
            end
        end
    else
        if isHooked then
            if bloodlustHandle and Bloodlust and Bloodlust.Release then
                Bloodlust:Release(bloodlustHandle)
                bloodlustHandle = nil
            elseif Bloodlust and Bloodlust.ReleaseOwner then
                Bloodlust:ReleaseOwner(EventOwner)
            end
            YUI.Event:OffOwner(EventOwner)
            isReady = false
            Engine.sxActive = false
            StopMusic()
            isHooked = false
        end
    end
end

local function RegisterTopPlaybackButton(button)
    if not button then return end
    playbackTextButtons[button] = true
    RefreshPlaybackControls()
end

local function CreatePlayButton(parent, onPlay)
    local GUI2 = YUI.GUI2
    if not GUI2 or not GUI2.Form then return nil end

    local button = GUI2.Form:CreateButton(parent, {
        text = "",
        width = PLAY_BUTTON_SIZE,
        height = PLAY_BUTTON_SIZE,
        onClick = function()
            if IsMusicPlaying() then
                StopMusic()
                return
            end
            if onPlay then onPlay() end
        end,
    })

    local icon = GUI2:CreateIcon(button, {
        atlas = IsMusicPlaying() and STOP_ICON_ATLAS or PLAY_ICON_ATLAS,
        fillParent = true,
        padding = 6,
    })
    if icon and icon.SetVertexColor and GUI2.GetColor then
        icon:SetVertexColor(GUI2:GetColor("color.text.accent"))
    end
    button.playbackIcon = icon
    playbackIconButtons[button] = true
    RefreshPlaybackControls()

    return button
end

local function CreateTopControlsRow(db)
    return {
        type = "custom",
        render = function(parent, x, y)
            local GUI2 = YUI.GUI2
            if not GUI2 or not GUI2.Form then return 0, 0 end

            local labelWidth = 68
            local labelGap = 10
            local dropdownWidth = 142
            local dropdownTotalWidth = labelWidth + labelGap + dropdownWidth
            local buttonGap = 20
            local buttonWidth = 100
            local rowHeight = 32
            local rowWidth = dropdownTotalWidth + buttonGap + buttonWidth
            local row = GUI2:CreateFrame(parent, { width = rowWidth, height = rowHeight })
            row:SetPoint("TOPLEFT", x, y)

            local label = GUI2:CreateText(row, T("sxmusic.channel", "Channel"), "font.size.md", "color.text.primary")
            label:SetWidth(labelWidth)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetPoint("LEFT", row, "LEFT", 0, 0)

            local dropdown = GUI2.Form:CreateDropdown(row, {
                width = dropdownWidth,
                options = GetSoundChannelOptions,
                get = function() return db.channel end,
                set = function(value)
                    db.channel = IsValidSoundChannel(value) and value or "Master"
                end,
            })
            dropdown:SetPoint("LEFT", row, "LEFT", labelWidth + labelGap, 0)

            local button = GUI2.Form:CreateButton(row, {
                text = IsMusicPlaying() and T("sxmusic.stop", "Stop") or T("sxmusic.preview", "Preview"),
                width = buttonWidth,
                onClick = function()
                    if IsMusicPlaying() then
                        StopMusic()
                    else
                        PlaySXEffect("preview")
                    end
                end,
            })
            button:SetPoint("LEFT", row, "LEFT", dropdownTotalWidth + buttonGap, 0)
            RegisterTopPlaybackButton(button)

            return rowWidth, rowHeight
        end
    }
end

local function CreateBuiltinMusicRow(db, rowIdx, colCnt, total)
    return {
        type = "custom",
        render = function(parent, x, y)
            local GUI2 = YUI.GUI2
            if not GUI2 or not GUI2.Form then return 0, 0 end

            local checkboxWidth = 122
            local buttonWidth = PLAY_BUTTON_SIZE
            local itemGap = 0
            local colGap = 8
            local rowHeight = 32
            local rowWidth = 620
            local row = GUI2:CreateFrame(parent, { width = rowWidth, height = rowHeight })
            row:SetPoint("TOPLEFT", x, y)

            for colIdx = 1, colCnt do
                local musicIndex = rowIdx * colCnt + colIdx
                if musicIndex > total then break end
                local music = BUILTIN_MUSIC[musicIndex]
                if music then
                    local colX = (colIdx - 1) * (checkboxWidth + itemGap + buttonWidth + colGap)
                    local checkbox = GUI2.Form:CreateCheckbox(row, {
                        label = music.name,
                        width = checkboxWidth,
                        get = function() return db.builtin[musicIndex] end,
                        set = function(value) db.builtin[musicIndex] = value end,
                    })
                    checkbox:SetPoint("LEFT", row, "LEFT", colX, 0)

                    local button = CreatePlayButton(row, function()
                        StopCurrentSound()
                        local willPlay, handle = PlaySoundFile(music.path, GetDB().channel)
                        if willPlay and handle then SetCurrentSoundHandle(handle, "preview") end
                    end)
                    button:SetPoint("LEFT", checkbox, "RIGHT", itemGap, 0)
                end
            end

            return rowWidth, rowHeight
        end
    }
end

local function CreateCustomMusicRow(db, index)
    return {
        type = "custom",
        render = function(parent, x, y)
            local GUI2 = YUI.GUI2
            if not GUI2 or not GUI2.Form then return 0, 0 end

            local prefixWidth = 132
            local editWidth = 450
            local buttonWidth = PLAY_BUTTON_SIZE
            local prefixGap = 4
            local buttonGap = 8
            local rowHeight = 26
            local rowWidth = prefixWidth + prefixGap + editWidth + buttonGap + buttonWidth
            local row = GUI2:CreateFrame(parent, { width = rowWidth, height = rowHeight })
            row:SetPoint("TOPLEFT", x, y)

            local prefix = GUI2:CreateText(row, CUSTOM_PATH_PREFIX, "font.size.md", "color.text.secondary")
            prefix:SetWidth(prefixWidth)
            prefix:SetJustifyH("LEFT")
            prefix:SetWordWrap(false)
            prefix:SetPoint("LEFT", row, "LEFT", 0, 0)

            local editbox = GUI2.Form:CreateEditBox(row, {
                width = editWidth,
                get = function() return db.custom[index] end,
                set = function(value) db.custom[index] = NormalizeCustomPath(value) end,
                onChange = function(widget)
                    if widget.HasFocus and widget:HasFocus() then
                        customPathStates[index] = nil
                        SetCustomPathEditState(widget, nil)
                    end
                end,
                onFocusGained = function(widget)
                    customPathStates[index] = nil
                    SetCustomPathEditState(widget, nil)
                end,
                onFocusLost = function(widget)
                    ValidateCustomMusicPath(db, index, widget)
                end,
            })
            editbox:SetPoint("LEFT", row, "LEFT", prefixWidth + prefixGap, 0)
            SetCustomPathEditState(editbox, customPathStates[index])

            local testButton = CreatePlayButton(row, function()
                if editbox.ClearFocus then editbox:ClearFocus() end

                local path = BuildCustomMusicPath(db.custom[index])
                if not path then
                    customPathStates[index] = nil
                    SetCustomPathEditState(editbox, nil)
                    ShowMusicToast(T("sxmusic.custom_failed", "Custom music preview failed"), string.format(T("sxmusic.custom_path_required", "Enter a path after %s."), CUSTOM_PATH_PREFIX))
                    return
                end

                StopCurrentSound()
                local willPlay, handle = PlaySoundFile(path, GetDB().channel)
                if willPlay and handle then
                    SetCurrentSoundHandle(handle, "preview")
                    customPathStates[index] = "valid"
                    SetCustomPathEditState(editbox, "valid")
                else
                    customPathStates[index] = "invalid"
                    SetCustomPathEditState(editbox, "invalid")
                    ShowMusicToast(T("sxmusic.custom_failed", "Custom music preview failed"), path)
                end
            end)
            testButton:SetPoint("LEFT", editbox, "RIGHT", buttonGap, 0)

            return rowWidth, rowHeight
        end
    }
end

local function CreateCustomMusicHintRow()
    return {
        type = "custom",
        render = function(parent, x, y)
            local GUI2 = YUI.GUI2
            if not GUI2 then return 0, 0 end

            local rowWidth = 620
            local rowHeight = 22
            local warningGap = 8
            local row = GUI2:CreateFrame(parent, { width = rowWidth, height = rowHeight })
            row:SetPoint("TOPLEFT", x, y)

            local example = GUI2:CreateText(row, T("sxmusic.example_path", "Example: ") .. CUSTOM_EXAMPLE_PATH, "font.size.md", "color.text.secondary", "LEFT")
            example:SetWidth(rowWidth)
            example:SetJustifyH("LEFT")
            example:SetWordWrap(false)
            example:SetPoint("LEFT", row, "LEFT", 0, 0)

            local warning = GUI2:CreateText(row, CUSTOM_RELOAD_WARNING_TEXT, "font.size.md", "color.state.warning", "LEFT")
            warning:SetWidth(rowWidth)
            warning:SetJustifyH("LEFT")
            warning:SetWordWrap(false)
            warning:SetPoint("LEFT", row, "LEFT", (example:GetStringWidth() or 0) + warningGap, 0)

            return rowWidth, rowHeight
        end
    }
end

local function OnSettingsEnter()
    local db = GetDB()
    CompactCustomMusicRows(db)
    ResetPlaybackButtonRegistry()
end

local function OnSettingsLeave()
    StopPreviewMusic()
    ResetPlaybackButtonRegistry()
end

local function GetOptions(feature)
    local db = GetDB()
    local options = {}
    
    -- 声道选择与试听按钮
    table.insert(options, CreateTopControlsRow(db))
    
    -- 内置音乐区
    table.insert(options, { type = "divider", label = T("sxmusic.builtin", "Built-in Music"), alignLeft = true, width = 620 })
    
    -- 分成三行，每行 4 个选项
    local rowCnt = 3
    local colCnt = 4
    local total = #BUILTIN_MUSIC
    for rowIdx = 0, rowCnt - 1 do
        table.insert(options, CreateBuiltinMusicRow(db, rowIdx, colCnt, total))
    end
    
    -- 自定义音乐区
    table.insert(options, { type = "divider", label = T("sxmusic.custom", "Custom Music"), alignLeft = true, width = 620 })
    table.insert(options, CreateCustomMusicHintRow())
    
    for i = 1, db.customRows do
        table.insert(options, CreateCustomMusicRow(db, i))
    end

    if db.customRows < MAX_CUSTOM_MUSIC then
        table.insert(options, {
            type = "row",
            children = {
                {
                    type = "button",
                    label = T("sxmusic.add_row", "Add Row"),
                    width = 100,
                    onClick = function()
                        db.customRows = math.min(MAX_CUSTOM_MUSIC, db.customRows + 1)
                        if feature and feature.RefreshCurrentModule then
                            feature.RefreshCurrentModule()
                        end
                    end
                }
            }
        })
    end
    
    return options
end

-- 注册到 Components
YUI.Components:RegisterFeature("SXMusic", {
    product = PRODUCT_ID,
    name = "嗜血音乐",
    description = "触发嗜血、英勇等爆发增益时，自动播放你选择的音乐。",
    settingsTitleAside = T("sxmusic.credit", "Original version supported by 田园双皮奶. Thank you!"),
    default = false,
    callback = ToggleSXMusic,
    OnSettingsEnter = OnSettingsEnter,
    OnSettingsLeave = OnSettingsLeave,
    GetOptions = GetOptions
})
