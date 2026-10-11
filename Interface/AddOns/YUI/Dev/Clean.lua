local YUI = _G.YUI
YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev

local function Print(...)
    if YUI.Print then YUI:Print(...) else print(...) end
end
local function NewWeakRuntimeCache()
    return setmetatable({}, { __mode = "k" })
end

local function GetGlobalDB()
    if YUI.DB and YUI.DB.GetGlobal then
        local global = YUI.DB:GetGlobal(YUI.ProductId or "suite")
        if type(global) == "table" then
            return global
        end
    end
    return type(YUI.global) == "table" and YUI.global or nil
end

local function ClearWhisperManagerRuntime()
    local manager = YUI.WhisperManager
    if type(manager) ~= "table" then
        return false
    end

    manager.headerCache = NewWeakRuntimeCache()
    manager.messageCache = NewWeakRuntimeCache()
    manager.playerInfoCache = {}
    manager.pendingWhoNames = {}
    manager.pendingWhoLookup = {}
    manager.pendingWhoQueryLookup = {}
    manager.whoQueue = {}
    manager.whoQueued = {}
    manager.whoCooldown = {}
    manager.whoQueueTimer = nil
    manager.nextWhoQueryAt = nil
    manager.unfavoritedVisibleKeys = {}
    manager.currentPage = 1

    if type(manager.ClearCurrentSelection) == "function" then
        manager:ClearCurrentSelection()
    else
        manager.selectedKey = nil
        manager.selectedStore = nil
        manager.selectedToken = nil
        manager.selectionLocked = false
        manager.pendingUnreadDividerKey = nil
        manager.pendingUnreadDividerToken = nil
        manager.pendingUnreadDividerIndex = nil
    end

    if type(manager.HideCopyEditBox) == "function" then
        manager:HideCopyEditBox(true)
    end
    if type(manager.RefreshFrame) == "function" then
        manager:RefreshFrame()
    end

    return true
end

local function ClearLegacyWhisperProfileHistory()
    local aceDB = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB("whisper_manager")
    local profiles = aceDB and aceDB.profiles
    local cleared = 0

    if type(profiles) ~= "table" then
        return cleared
    end

    for _, profile in pairs(profiles) do
        local components = type(profile) == "table" and profile.Components or nil
        local config = type(components) == "table" and components.WhisperManager_Config or nil
        if type(config) == "table" and config.history ~= nil then
            config.history = nil
            cleared = cleared + 1
        end
    end

    return cleared
end

local function ClearLocaleOverride(global)
    local cleared = type(global) == "table" and global.localeOverride ~= nil
    local locale = YUI.Locale

    if type(locale) == "table" then
        if type(locale.GetOverride) == "function" and locale:GetOverride() ~= nil then
            cleared = true
        end
        if type(locale.GetPersistedOverride) == "function" and locale:GetPersistedOverride() ~= nil then
            cleared = true
        end

        if type(locale.ClearOverride) == "function" then
            locale:ClearOverride()
        else
            locale.overrideLocale = nil
            locale.pendingPersistedOverride = false
        end
    end

    if type(global) == "table" then
        global.localeOverride = nil
    end

    return cleared
end

local function CleanSpellAlertPreviewMaterials()
    local spellAlert = YUI.SpellAlert
    if type(spellAlert) == "table" and type(spellAlert.CleanPreviewMaterials) == "function" then
        return spellAlert:CleanPreviewMaterials()
    end
    return nil
end

local function ClearYChatHistory()
    if YUI.IsRetail ~= true and YUI.IsForever ~= true then return nil end
    local ychat = YUI.YChat
    if type(ychat) == "table" and type(ychat.ClearAllHistory) == "function" then
        local ok, cleared = pcall(ychat.ClearAllHistory, ychat, true)
        if ok and cleared == true then return true end
    end

    local db = YUI.DB
    if type(db) ~= "table" or type(db.GetGlobal) ~= "function" then
        return false
    end
    local ok, ychatGlobal = pcall(db.GetGlobal, db, "ychat")
    if not ok or type(ychatGlobal) ~= "table" then return false end
    ychatGlobal.historyByCharacter = {}
    return true
end

local function ClearMailAssistantPersonalData()
    local assistant = YUI.MailAssistant
    if type(assistant) ~= "table" or type(assistant.ClearPersonalData) ~= "function" then
        return nil
    end
    local ok, cleared = pcall(assistant.ClearPersonalData, assistant, true)
    return ok and cleared == true
end

function Dev:CleanSavedCharacterData()
    local global = GetGlobalDB()
    if type(global) ~= "table" then
        Print("清理失败：全局 DB 尚未就绪。")
        return false
    end

    global.installedChars = {}
    global.installedCharsByClient = {}
    global.Gold = {}
    global.ignoreYUISwitchPrompt = false
    global.lastChangelogVersion = nil
    global.devCpuProfile = nil

    if type(global.WhisperManager) == "table" then
        global.WhisperManager.history = {}
    end

    local legacyProfiles = ClearLegacyWhisperProfileHistory()
    ClearWhisperManagerRuntime()
    local localeOverrideCleared = ClearLocaleOverride(global)

    if YUI.SetPersistedDevMode then
        YUI:SetPersistedDevMode(false)
    else
        YUI.IsDev = false
        global.devMode = false
    end
    if self.CPUProfiler and type(self.CPUProfiler.CancelRun) == "function" then
        self.CPUProfiler.enabled = false
        self.CPUProfiler:CancelRun(true)
    end
    if self.HideButtons then self:HideButtons() end

    Print("开发者角色数据已清理，Profile 绑定已保留；正在清理 YChat 全角色聊天记录和邮箱助手个人数据。")
    if legacyProfiles > 0 then
        Print("已从 Profile 清理旧 WhisperManager 历史：", legacyProfiles)
    end
    if localeOverrideCleared then
        Print("Locale 覆盖已清理。")
    end
    CleanSpellAlertPreviewMaterials()
    local ychatHistoryCleared = ClearYChatHistory()
    if ychatHistoryCleared == false then
        Print("YChat 全部角色聊天记录清理失败。")
    end
    local mailAssistantCleared = ClearMailAssistantPersonalData()
    if mailAssistantCleared == false then
        Print("邮箱助手个人数据清理失败。")
    end
    return ychatHistoryCleared ~= false and mailAssistantCleared ~= false
end
