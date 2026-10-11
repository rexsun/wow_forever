local ADDON_NAME = ...
local YUI = _G.YUI
local S = YUI and YUI.Settings
if not (YUI and S and S.RegisterModule) then return end
if S._soundSettingsRegistered then return end
S._soundSettingsRegistered = true

local LC = YUI.Locale:Get("Core")
local PRODUCT_ID = YUI.GetAddonProductId
    and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local MODULE_ID = PRODUCT_ID .. ".settings.sound"
local MODULE_ICON = 132351
local selectedPreviewKey

local function T(key, fallback)
    return LC[key] or fallback or key
end

local function GetPackOptions(sound)
    local options = {}
    for _, pack in ipairs(sound and sound:GetPacks() or {}) do
        options[#options + 1] = {
            text = pack.name,
            value = pack.id,
        }
    end
    return options
end

local function Render(parent)
    local sound = YUI.Sound
    if sound and sound.Runtime and S.SoundCenter then return S.SoundCenter:Render(parent) end
    if not sound then
        S:RenderConfig(parent, {
            { type = "header", label = T("sound.settings.title", "声音") },
            {
                type = "text",
                label = T("sound.settings.unavailable", "声音服务当前不可用。"),
                colorKey = "color.state.warning",
            },
        })
        return
    end

    local function Refresh()
        if S.RefreshSelectedModule then S:RefreshSelectedModule() end
    end

    local packId = sound:GetActivePackId()
    local pack = sound:GetPack(packId)
    local valid, total = sound:GetPackStats(packId)
    local packOptions = GetPackOptions(sound)
    local soundChoices = sound:GetSoundChoices({ current = selectedPreviewKey })
    local selectedChoice = selectedPreviewKey
        and sound:GetSoundChoice(selectedPreviewKey) or nil
    if not (selectedChoice and selectedChoice.available ~= false) then
        selectedPreviewKey = nil
        for index = 1, #soundChoices do
            if soundChoices[index].available ~= false then
                selectedPreviewKey = soundChoices[index].value
                break
            end
        end
    end

    local config = {
        { type = "header", label = T("sound.settings.title", "声音") },
        {
            type = "divider",
            label = T("sound.settings.pack_section", "语音包"),
            alignLeft = true,
            width = 650,
        },
        {
            type = "dropdown",
            label = T("sound.settings.current_pack", "当前语音包"),
            inlineLabel = true,
            width = 500,
            labelWidth = 150,
            options = packOptions,
            get = function() return sound:GetActivePackId() end,
            set = function(value)
                if sound:SetActivePack(value) then Refresh() end
            end,
        },
        {
            type = "row",
            children = {
                {
                    type = "text",
                    label = T("sound.settings.valid_entries", "有效条目"),
                    width = 150,
                    noWrap = true,
                    colorKey = "color.text.primary",
                },
                {
                    type = "text",
                    label = string.format("|cff32d878%d|r / %d", valid, total),
                    width = 330,
                    noWrap = true,
                    colorKey = "color.text.secondary",
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "text",
                    label = T("sound.settings.author_info", "作者信息"),
                    width = 150,
                    noWrap = true,
                    colorKey = "color.text.primary",
                },
                {
                    type = "text",
                    label = pack and pack.author ~= "" and pack.author
                        or T("sound.settings.author_unknown", "未提供"),
                    width = 330,
                    noWrap = true,
                    colorKey = "color.text.primary",
                },
            },
        },
    }

    if pack and pack.authorInfo ~= "" then
        config[#config + 1] = {
            type = "text",
            label = pack.authorInfo,
            width = 480,
            colorKey = "color.text.secondary",
        }
    end

    config[#config + 1] = { type = "space", height = 8 }
    config[#config + 1] = {
        type = "divider",
        label = T("sound.settings.playback_section", "播放设置"),
        alignLeft = true,
        width = 650,
    }
    config[#config + 1] = {
        type = "dropdown",
        label = T("sound.settings.channel", "播放声道"),
        inlineLabel = true,
        width = 500,
        labelWidth = 150,
        options = {
            { text = T("sound.channel.master", "主声道"), value = "Master" },
            { text = T("sound.channel.sfx", "音效"), value = "SFX" },
            { text = T("sound.channel.dialog", "对话"), value = "Dialog" },
            { text = T("sound.channel.ambience", "环境"), value = "Ambience" },
            { text = T("sound.channel.music", "音乐"), value = "Music" },
        },
        get = function() return sound:GetChannel() end,
        set = function(value) sound:SetChannel(value) end,
    }
    config[#config + 1] = {
        type = "custom",
        render = function(container, x, y)
            local row = YUI.GUI2:CreateFrame(container, {
                width = 650,
                height = 32,
            })
            row:SetPoint("TOPLEFT", x, y)
            local label = YUI.GUI2:CreateText(
                row,
                T("sound.settings.preview_key", "试听声音"),
                "font.size.md",
                "color.text.primary",
                "LEFT"
            )
            label:SetPoint("LEFT", row, "LEFT", 0, 0)
            label:SetWidth(150)
            local preview
            local selector = YUI.GUI2.SoundPicker:CreateSelector(row, {
                width = 350,
                get = function() return selectedPreviewKey end,
                set = function(value)
                    selectedPreviewKey = value
                    if preview then preview:SetDisabled(value == nil, true) end
                end,
            })
            selector:SetPoint("LEFT", row, "LEFT", 160, 0)
            preview = YUI.GUI2.Form:CreateButton(row, {
                text = T("sound.settings.preview", "试听"),
                width = 82,
                tone = "accent",
                disabled = selectedPreviewKey == nil,
                onClick = function()
                    local played = selectedPreviewKey
                        and sound:Play(selectedPreviewKey, nil, 0)
                    if not played and YUI.Print then
                        YUI:Print(T(
                            "sound.settings.preview_failed",
                            "无法播放所选声音。"
                        ))
                    end
                end,
            })
            preview:SetPoint("LEFT", selector, "RIGHT", 10, 0)
            return 650, 32
        end,
    }

    S:RenderConfig(parent, config)
end

S:RegisterModule(T("sound.settings.title", "声音"), MODULE_ICON, Render, {
    id = MODULE_ID,
    product = PRODUCT_ID,
    scope = PRODUCT_ID,
    titleKey = "sound.settings.title",
    titleNamespace = "Core",
    navTitleKey = "sound.settings.nav",
    navTitleNamespace = "Core",
    hidden = false,
})
