local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end
local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local L = YUI.Locale and YUI.Locale:Get("LoginCheck") or nil

local function T(key)
    if L and L[key] then
        return L[key]
    end
    return key
end

local descriptionKey = YUI.IsWrath and "description.wrath"
    or YUI.IsForever and "description.forever" or "description.retail"
local Feature = {
    product = PRODUCT_ID,
    localeNamespace = "LoginCheck",
    nameKey = "name",
    descriptionKey = descriptionKey,
    name = T("name"),
    default = true,
    settingsMode = "inline",
    description = T(descriptionKey),
}

local defaults = YUI.IsWrath and {
    LoadOutdatedAddOns = true,
} or YUI.IsForever and {
    Installer = true,
    EditModeSwitch = true,
} or {
    Welcome = true,
    CVar = true,
    DataVersion = true,
    LoadOutdatedAddOns = true,
    CheckAddonConflict = true,
    AutoMatchProfile = true,
    Installer = true,
    EditModeSwitch = true,
    EncounterJournalItemSets = true,
}

local Flow = YUI.LoginFlow or {}
YUI.LoginFlow = Flow
Flow.eventFired = Flow.eventFired or {}

local function Now()
    if GetTime then
        return GetTime()
    end
    return 0
end

local function DebugLog(message)
    if YUI.Debug then
        YUI:Debug("LoginFlow | " .. tostring(message))
    end
end

local function DebugFormat(formatText, ...)
    DebugLog(string.format(formatText, ...))
end

local function Schedule(delay, callback)
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, callback)
        return
    end
    callback()
end

local function GetDB()
    if Components and Components.EnsureConfig then
        return Components:EnsureConfig("LoginCheck_Config", defaults, PRODUCT_ID) or defaults
    end
    return defaults
end

local function IsTaskEnabled(task)
    if not task.enabledKey then
        return true
    end

    local db = GetDB()
    return db[task.enabledKey] ~= false
end

function Feature.GetOptions(feature)
    local db = GetDB()
    if YUI.IsForever then
        return {
            {
                type = "checkbox", label = T("settings.installer.label"), tooltip = T("settings.installer.tooltip"),
                get = function() return db.Installer end,
                set = function(value) db.Installer = value end,
            },
            {
                type = "checkbox", label = T("settings.edit_mode.label"), tooltip = T("settings.edit_mode.tooltip"),
                get = function() return db.EditModeSwitch end,
                set = function(value) db.EditModeSwitch = value end,
            },
        }
    end
    if YUI.IsWrath then
        return {
            { type = "text", label = T("settings.wrath_intro"), color = YUI.Settings.Colors.text },
            { type = "space", height = 20 },
            {
                type = "row",
                children = {
                    {
                        type = "checkbox",
                        label = T("settings.load_outdated_addons.label"),
                        tooltip = T("settings.load_outdated_addons.tooltip"),
                        get = function() return db.LoadOutdatedAddOns end,
                        set = function(v) db.LoadOutdatedAddOns = v end
                    },
                }
            },
        }
    end

    return {
        { type = "text", label = T("settings.intro"), color = YUI.Settings.Colors.text },
        { type = "space", height = 20 },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = T("settings.welcome.label"),
                    tooltip = T("settings.welcome.tooltip"),
                    get = function() return db.Welcome end,
                    set = function(v) db.Welcome = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.cvar.label"),
                    tooltip = T("settings.cvar.tooltip"),
                    get = function() return db.CVar end,
                    set = function(v) db.CVar = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.load_outdated_addons.label"),
                    tooltip = T("settings.load_outdated_addons.tooltip"),
                    get = function() return db.LoadOutdatedAddOns end,
                    set = function(v) db.LoadOutdatedAddOns = v end
                },
            }
        },
        { type = "space", height = 10 },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = T("settings.conflicts.label"),
                    tooltip = T("settings.conflicts.tooltip"),
                    get = function() return db.CheckAddonConflict end,
                    set = function(v) db.CheckAddonConflict = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.profile_match.label"),
                    tooltip = T("settings.profile_match.tooltip"),
                    get = function() return db.AutoMatchProfile end,
                    set = function(v) db.AutoMatchProfile = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.installer.label"),
                    tooltip = T("settings.installer.tooltip"),
                    get = function() return db.Installer end,
                    set = function(v) db.Installer = v end
                },
            }
        },
        { type = "space", height = 10 },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = T("settings.edit_mode.label"),
                    tooltip = T("settings.edit_mode.tooltip"),
                    get = function() return db.EditModeSwitch end,
                    set = function(v) db.EditModeSwitch = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.data_version.label"),
                    tooltip = T("settings.data_version.tooltip"),
                    get = function() return db.DataVersion end,
                    set = function(v) db.DataVersion = v end
                },
                {
                    type = "checkbox",
                    label = T("settings.encounter_journal_item_sets.label"),
                    tooltip = T("settings.encounter_journal_item_sets.tooltip"),
                    get = function() return db.EncounterJournalItemSets end,
                    set = function(v) db.EncounterJournalItemSets = v end
                },
            }
        },
    }
end

local function DoLoginWelcome()
    if YUI.VersionType == "Pro" then
        print(T("welcome.suite"))
    else
        print(T("welcome.base"))
    end
end

local function DoAutoMatchProfile()
    local SAM = _G.SimpleAddonManager
    if not SAM then return end

    local profileModule = SAM:GetModule("Profile")
    if not profileModule then return end

    local targetProfiles = { "YUI-ElvUI", "YUI-NDUI", "YUI-EQoL" }
    local activeProfile = nil

    for _, pName in ipairs(targetProfiles) do
        if profileModule:IsProfileLoaded(pName) then
            activeProfile = pName
            break
        end
    end

    if activeProfile and _G.BLINKIISPORTRAITS and _G.BLINKIISPORTRAITS.db then
        local currentProfile = _G.BLINKIISPORTRAITS.db:GetCurrentProfile()
        local profileExists = false

        if _G.BLINKIISPORTRAITS.db.GetProfiles then
            local profiles = _G.BLINKIISPORTRAITS.db:GetProfiles()
            for _, p in ipairs(profiles) do
                if p == activeProfile then
                    profileExists = true
                    break
                end
            end
        end

        if profileExists and currentProfile ~= activeProfile then
            _G.BLINKIISPORTRAITS.db:SetProfile(activeProfile)
            YUI:Print(string.format(T("message.profile_matched"), activeProfile))
        end
    end
end

local function DoAutoSetCVar()
    -- 团队框架显示职业颜色
    SetCVar("raidFramesDisplayClassColor", 1)
    -- 总是显示装备对比
    SetCVar("alwaysCompareItems", 1)
end

local function ShouldPromptLoadOutdatedAddOns()
    if not (SystemAPI and SystemAPI.IsAddonVersionCheckEnabled and SystemAPI.HasEnabledOutOfDateAddOns) then
        return false
    end

    return SystemAPI.IsAddonVersionCheckEnabled() and SystemAPI.HasEnabledOutOfDateAddOns()
end

local function DoPromptLoadOutdatedAddOns(ctx)
    if not ShouldPromptLoadOutdatedAddOns() then
        ctx:Done()
        return
    end

    local Settings = YUI.Settings
    if not (Settings and Settings.ShowConfirmPopup) then
        ctx:Done()
        return
    end

    Settings:ShowConfirmPopup(
        T("popup.load_outdated_addons.text"),
        function()
            if SystemAPI.SetAddonVersionCheck then
                SystemAPI.SetAddonVersionCheck(false)
            end
            if SystemAPI.SaveAddOns then
                SystemAPI.SaveAddOns()
            end
            local reloading = false
            if FrameAPI and FrameAPI.ReloadUI then
                reloading = true
                FrameAPI.ReloadUI()
            elseif ReloadUI then
                reloading = true
                ReloadUI()
            end
            if not reloading then
                ctx:Done()
            end
        end,
        {
            titleText = T("popup.load_outdated_addons.title"),
            acceptText = T("popup.load_outdated_addons.confirm"),
            cancelText = T("popup.load_outdated_addons.cancel"),
            acceptStyle = "successFilled",
            cancelStyle = "grayFilled",
            acceptWidth = 140,
            cancelWidth = 170,
            buttonGap = 28,
            onCancel = function()
                ctx:Done()
            end,
        }
    )
end

local function CheckVersions()
    if not YUI.IsRetail then return end
    if not YUI.Data then return end
    if not YUI.EditMode then return end

    if YUI.CooldownMgr then
        local ok, installedVersions, reason = pcall(YUI.CooldownMgr.GetInstalledVersions, YUI.CooldownMgr)
        if not ok or not installedVersions then
            DebugLog("cooldown versions unavailable: " .. tostring(reason or installedVersions))
            return
        end
        local _, cls = UnitClass("player")
        local cdCfg = YUI.Data:GetData("CooldownMgr", cls and cls:upper())

        local hasUpdate = false
        local newSpecNames = ""
        if cdCfg then
            for specID, info in pairs(cdCfg) do
                local specName = info.Name
                local latestSpecVer = info.Version
                local installedSpecVer = installedVersions[specName]

                if installedSpecVer and installedSpecVer < latestSpecVer then
                    hasUpdate = true
                    newSpecNames = newSpecNames .. specName .. " "
                end
            end
        end

        if hasUpdate then
            local _, classFileName = UnitClass("player")
            local color = RAID_CLASS_COLORS[classFileName]
            local colorStr = color and color.colorStr or "FFFFFFFF"

            YUI:Print(string.format(T("message.cooldown_update"), colorStr, newSpecNames))
        end
    end
end

local function CheckAddonConflict()
    local isElvuiLoaded = C_AddOns.IsAddOnLoaded("ElvUI")
    local isNduiLoaded = C_AddOns.IsAddOnLoaded("NDui")
    local isEQoLLoaded = C_AddOns.IsAddOnLoaded("EnhanceQoL")

    local loadedUIs = {}
    if isElvuiLoaded then table.insert(loadedUIs, "ElvUI") end
    if isNduiLoaded then table.insert(loadedUIs, "NDUI") end
    if isEQoLLoaded then table.insert(loadedUIs, "EQoL") end

    if #loadedUIs >= 2 then
        local SAM = _G.SimpleAddonManager
        local switchAddons = function(profileName)
            if SAM then
                local profileModule = SAM:GetModule("Profile")
                if profileModule then
                    profileModule:LoadAddonsFromProfile(profileName, false)
                    ReloadUI()
                end
            else
                print(T("message.sam_missing"))
            end
        end

        local Settings = YUI.Settings
        if Settings and Settings.ShowConfirmPopup then
            local buttons = {}
            for index = 1, math.min(#loadedUIs, 3) do
                local uiName = loadedUIs[index]
                buttons[#buttons + 1] = {
                    text = string.format(T("popup.addon_conflict.use"), uiName),
                    tone = "warning",
                    callback = function()
                        switchAddons("YUI-" .. uiName)
                    end,
                }
            end
            if #buttons < 3 then
                buttons[#buttons + 1] = {
                    text = T("popup.addon_conflict.later"),
                    tone = "default",
                }
            end

            Settings:ShowConfirmPopup(
                string.format(T("popup.addon_conflict.text"), table.concat(loadedUIs, ", ")),
                nil,
                {
                    titleText = T("popup.addon_conflict.title"),
                    buttons = buttons,
                    buttonGap = 10,
                    height = 180,
                }
            )
        end
    end

    -- =============================================
    -- 永久保留以下注释代码，以告诫自己做人不能傲慢
    -- =============================================
    -- local isDBMLoaded = C_AddOns.IsAddOnLoaded("DBM-Core")
    -- local isEXBossLoaded = C_AddOns.IsAddOnLoaded("EXBoss")

    -- if isDBMLoaded and isEXBossLoaded then
    --     StaticPopupDialogs["YUI_ADDON_CONFLICT_BOSSMOD"] = {
    --         text = "|cFFFF0000警告|r：检测到 DBM 和 EXBoss 同时加载！\n这会导致屏幕上出现重复的提示条和声音，影响战斗体验。\n\n请选择你需要保留的首领模块：",
    --         button1 = "保留 DBM",
    --         button2 = "保留 EXBoss",
    --         button3 = "稍后处理",
    --         OnAccept = function()
    --             C_AddOns.DisableAddOn("EXBoss")
    --             C_AddOns.DisableAddOn("EXBossData")
    --             for i = 1, C_AddOns.GetNumAddOns() do
    --                 local name = C_AddOns.GetAddOnInfo(i)
    --                 if name:match("^EXBOSS%-") then
    --                     C_AddOns.DisableAddOn(name)
    --                 end
    --             end
    --             ReloadUI()
    --         end,
    --         OnCancel = function()
    --             C_AddOns.DisableAddOn("DBM-Core")
    --             for i = 1, C_AddOns.GetNumAddOns() do
    --                 local name = C_AddOns.GetAddOnInfo(i)
    --                 if name:match("^DBM%-") then
    --                     C_AddOns.DisableAddOn(name)
    --                 end
    --             end
    --             ReloadUI()
    --         end,
    --         OnAlt = function() end,
    --         timeout = 0,
    --         whileDead = true,
    --         hideOnEscape = true,
    --         preferredIndex = 3,
    --     }

    --     StaticPopup_Show("YUI_ADDON_CONFLICT_BOSSMOD")
    -- end

    -- if isEXBossLoaded and not isDBMLoaded then
    --     if C_CVar.GetCVar("combatWarningsEnabled") == "1" then
    --         SetCVar("combatWarningsEnabled", 0)
    --         YUI:Print("检测加载了 EXBoss，已自动关闭【启用首领预警】")
    --     end
    -- elseif isDBMLoaded and not isEXBossLoaded then
    --     if C_CVar.GetCVar("combatWarningsEnabled") == "0" then
    --         SetCVar("combatWarningsEnabled", 1)
    --         YUI:Print("检测加载了 DBM，已自动开启【启用首领预警】")
    --     end
    -- end
end

local function CheckEditModeSwitch()
    if YUI.EditMode and YUI.EditMode.CheckAndPromptSwitchToYUI then
        YUI.EditMode:CheckAndPromptSwitchToYUI()
    end
end

local encounterJournalItemSetsQueued = false
local encounterJournalItemSetsHooked = false

local function ApplyEncounterJournalItemSets(frame)
    local ok, err = pcall(function()
        PanelTemplates_SetAllTabsShown(frame, true)
        PanelTemplates_SetNumTabs(frame, #frame.Tabs)
    end)
    if not ok then
        DebugFormat("EncounterJournal item sets apply failed: %s", tostring(err))
    end
    return ok
end

local function InstallEncounterJournalItemSetsHook()
    if encounterJournalItemSetsHooked then return true end

    local ok, err = pcall(function()
        EncounterJournal:HookScript("OnShow", ApplyEncounterJournalItemSets)
    end)
    if not ok then
        DebugFormat("EncounterJournal item sets hook failed: %s", tostring(err))
        return false
    end

    encounterJournalItemSetsHooked = true
    return true
end

local function QueueEncounterJournalItemSetsHook()
    if encounterJournalItemSetsHooked or encounterJournalItemSetsQueued then return true end

    encounterJournalItemSetsQueued = true
    local ok, err = pcall(function()
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EncounterJournal", function()
            encounterJournalItemSetsQueued = false
            InstallEncounterJournalItemSetsHook()
        end)
    end)
    if not ok then
        encounterJournalItemSetsQueued = false
        DebugFormat("EncounterJournal item sets queue failed: %s", tostring(err))
        return false
    end

    return true
end

local function BuildTasks()
    if YUI.IsForever then
        return {
            {
                id = "Installer", label = T("task.installer"), enabledKey = "Installer",
                event = "YUI_LOGIN_READY", delay = 1,
                run = function(ctx)
                    if YUI.Installer and YUI.Installer.CheckInstall then
                        YUI.Installer:CheckInstall(function() ctx:Done() end)
                    else ctx:Done() end
                end,
            },
            {
                id = "EditModeSwitch", label = T("task.edit_mode"), enabledKey = "EditModeSwitch",
                event = "YUI_WORLD_READY", delay = 0,
                run = function(ctx) CheckEditModeSwitch(); ctx:Done() end,
            },
        }
    end
    local loadOutdatedTask = {
        id = "LoadOutdatedAddOns",
        label = T("task.load_outdated_addons"),
        enabledKey = "LoadOutdatedAddOns",
        event = "YUI_LOGIN_READY",
        delay = 0,
        run = function(ctx)
            DoPromptLoadOutdatedAddOns(ctx)
        end,
    }

    if YUI.IsWrath then
        return {
            loadOutdatedTask,
        }
    end

    return {
        {
            id = "Welcome",
            label = T("task.welcome"),
            enabledKey = "Welcome",
            event = "YUI_LOGIN_READY",
            delay = 0,
            run = function(ctx)
                DoLoginWelcome()
                ctx:Done()
            end,
        },
        {
            id = "CVar",
            label = T("task.cvar"),
            enabledKey = "CVar",
            event = "YUI_LOGIN_READY",
            delay = 0,
            run = function(ctx)
                DoAutoSetCVar()
                ctx:Done()
            end,
        },
        {
            id = "EncounterJournalItemSets",
            label = T("task.encounter_journal_item_sets"),
            enabledKey = "EncounterJournalItemSets",
            event = "YUI_LOGIN_READY",
            delay = 0,
            run = function(ctx)
                QueueEncounterJournalItemSetsHook()
                ctx:Done()
            end,
        },
        loadOutdatedTask,
        {
            id = "CheckAddonConflict",
            label = T("task.conflicts"),
            enabledKey = "CheckAddonConflict",
            event = "YUI_LOGIN_READY",
            delay = 0,
            run = function(ctx)
                CheckAddonConflict()
                ctx:Done()
            end,
        },
        {
            id = "Installer",
            label = T("task.installer"),
            enabledKey = "Installer",
            event = "YUI_LOGIN_READY",
            delay = 1,
            run = function(ctx)
                if YUI.Installer and YUI.Installer.CheckInstall then
                    YUI.Installer:CheckInstall(function()
                        ctx:Done()
                    end)
                else
                    ctx:Done()
                end
            end,
        },
        {
            id = "EditModeSwitch",
            label = T("task.edit_mode"),
            enabledKey = "EditModeSwitch",
            event = "YUI_WORLD_READY",
            delay = 0,
            run = function(ctx)
                CheckEditModeSwitch()
                ctx:Done()
            end,
        },
        {
            id = "AutoMatchProfile",
            label = T("task.profile_match"),
            enabledKey = "AutoMatchProfile",
            event = "YUI_WORLD_READY",
            delay = 0,
            run = function(ctx)
                DoAutoMatchProfile()
                ctx:Done()
            end,
        },
        {
            id = "DataVersion",
            label = T("task.data_version"),
            enabledKey = "DataVersion",
            event = "YUI_WORLD_READY",
            delay = 0,
            run = function(ctx)
                CheckVersions()
                ctx:Done()
            end,
        },
    }
end

local function FinishTask(state, detail)
    local current = Flow.current
    if not current or current.finished then
        return
    end

    current.finished = true
    if current.timeoutTimer and current.timeoutTimer.Cancel then
        current.timeoutTimer:Cancel()
    end

    local elapsed = Now() - (current.startedAt or Now())
    local task = current.task
    Flow.current = nil

    if state == "fail" then
        print("|cffff0000YUI LoginFlow Error:|r " .. tostring(task.label or task.id) .. " - " .. tostring(detail))
    end

    DebugFormat("%s %s elapsed=%.3f%s", state, task.id or "unknown", elapsed, detail and (" detail=" .. tostring(detail)) or "")
    if current.traceRecord and YUI.Trace and YUI.Trace.Finish then
        local status = (state == "fail" or state == "timeout") and "error" or "ok"
        current.traceRecord.result = state
        if detail then
            current.traceRecord.resultDetail = tostring(detail)
        end
        YUI.Trace:Finish(current.traceRecord, status, detail)
    end
    if Flow.executingTask == current then
        Flow.pendingRunNext = true
    else
        Flow:RunNext()
    end
end

function Flow:RunTask(task)
    local blocking = task.blocking ~= false
    local startedAt = Now()
    local traceRecord
    if YUI.Trace and YUI.Trace.Begin then
        traceRecord = YUI.Trace:Begin("Login", "LoginFlow:" .. tostring(task.id or "unknown"), task.label, {
            moduleId = "loginflow:" .. tostring(task.id or "unknown"),
            phase = tostring(task.id or "unknown"),
            durationKind = "async",
            blocking = false,
        })
    end

    self.current = {
        task = task,
        startedAt = startedAt,
        finished = false,
        traceRecord = traceRecord,
    }

    DebugFormat("start %s blocking=%s", task.id or "unknown", tostring(blocking))

    local ctx = {}
    function ctx:Done()
        FinishTask("done")
    end
    function ctx:Fail(reason)
        FinishTask("fail", reason)
    end

    local timeout = tonumber(task.timeout)
    if blocking and timeout and timeout > 0 and C_Timer then
        local onTimeout = function()
            FinishTask("timeout", "timeout=" .. tostring(timeout))
        end
        if C_Timer.NewTimer then
            self.current.timeoutTimer = C_Timer.NewTimer(timeout, onTimeout)
        elseif C_Timer.After then
            C_Timer.After(timeout, onTimeout)
        end
    end

    local executingTask = self.current
    self.executingTask = executingTask
    local ok, err = pcall(task.run, ctx)
    if self.executingTask == executingTask then
        self.executingTask = nil
    end

    if not ok then
        FinishTask("fail", err)
    elseif not blocking then
        FinishTask("done", "nonblocking")
    end

    if self.pendingRunNext then
        self.pendingRunNext = nil
        self:RunNext()
    end
end

function Flow:QueueTask(task)
    local delay = tonumber(task.delay) or 0
    DebugFormat("queued %s delay=%.3f blocking=%s timeout=%s", task.id or "unknown", delay, tostring(task.blocking ~= false), tostring(task.timeout or "none"))

    if delay <= 0 then
        self:RunTask(task)
        return
    end

    local delayTrace
    if delay > 0 and YUI.Trace and YUI.Trace.Begin then
        local taskId = tostring(task.id or "unknown")
        local taskLabel = tostring(task.label or taskId)
        delayTrace = YUI.Trace:Begin("Login", "LoginFlow:" .. taskId .. ":Delay", string.format("等待 %.2fs 后执行 %s", delay, taskLabel), {
            moduleId = "loginflow:" .. taskId,
            phase = taskId .. ":delay",
            durationKind = "delay",
            blocking = false,
            traceName = string.format("等待 %.2fs", delay),
            delaySeconds = delay,
            nextAction = taskLabel,
        })
    end

    Schedule(delay, function()
        if delayTrace and YUI.Trace and YUI.Trace.Finish then
            YUI.Trace:Finish(delayTrace, "ok")
        end
        Flow:RunTask(task)
    end)
end

function Flow:RunNext()
    if not self.running then
        return
    end

    self.index = (self.index or 0) + 1
    local task = self.tasks and self.tasks[self.index]
    if not task then
        self.running = false
        DebugLog("complete")
        return
    end

    if not IsTaskEnabled(task) then
        DebugFormat("skip %s disabled", task.id or "unknown")
        self:RunNext()
        return
    end

    local eventName = task.event
    if eventName and not self.eventFired[eventName] then
        DebugFormat("wait %s event=%s", task.id or "unknown", eventName)
        self.waitingEvent = eventName
        self.waitingTask = task
        return
    end

    self:QueueTask(task)
end

function Flow:ResumeEvent(eventName)
    self.eventFired[eventName] = true
    if self.waitingEvent ~= eventName then
        return
    end

    local task = self.waitingTask
    self.waitingEvent = nil
    self.waitingTask = nil
    self:QueueTask(task)
end

function Flow:Start()
    if self.running or self.started then
        return
    end

    local isEnabled = Components and Components.IsEnabled and Components:IsEnabled("LoginCheck")
    if not isEnabled then
        DebugLog("disabled")
        return
    end

    self.started = true
    self.running = true
    self.index = 0
    self.current = nil
    self.waitingEvent = nil
    self.waitingTask = nil
    self.tasks = BuildTasks()

    DebugFormat("start tasks=%d", #self.tasks)
    self:RunNext()
end

if YUI.Event then
    YUI.Event:Once("YUI_LOGIN_READY", function(event)
        Flow.eventFired[event] = true
        Flow:Start()
    end, Flow, {
        priority = -100,
        traceName = "LoginFlow:Start",
        moduleId = "YUI.LoginFlow",
        phase = "YUI_LOGIN_READY",
    })

    YUI.Event:Once("YUI_WORLD_READY", function(event)
        Flow:ResumeEvent(event)
    end, Flow, {
        priority = -100,
        traceName = "LoginFlow:ResumeWorld",
        moduleId = "YUI.LoginFlow",
        phase = "YUI_WORLD_READY",
    })
end

function Feature.callback(enable)
    -- 登录流程只在登录阶段自动执行，手动切换总开关不立即补跑。
end

YUI.Components:RegisterFeature("LoginCheck", Feature)
