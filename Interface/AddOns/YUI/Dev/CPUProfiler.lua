local YUI = _G.YUI
if not YUI then return end

YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev

local CPUProfiler = Dev.CPUProfiler or {}
Dev.CPUProfiler = CPUProfiler

local WARMUP_SECONDS = 10
local SAMPLE_SECONDS = 60
local TOP_ADDON_LIMIT = 8
local PRODUCT_ID = YUI.ProductId or "suite"
local ADDON_NAME = YUI.AddonName or "YUI"

local sort = table.sort
local insert = table.insert
local format = string.format

CPUProfiler.enabled = CPUProfiler.enabled == true
CPUProfiler.runToken = CPUProfiler.runToken or 0
CPUProfiler.running = CPUProfiler.running == true
CPUProfiler.startSnapshot = CPUProfiler.startSnapshot or nil
CPUProfiler.startTime = CPUProfiler.startTime or nil
CPUProfiler.startLabel = CPUProfiler.startLabel or nil
CPUProfiler.startSource = CPUProfiler.startSource or nil

local function Trim(text)
    if strtrim then
        return strtrim(text or "")
    end
    return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

local function Print(...)
    if YUI.Print then
        YUI:Print(...)
    elseif print then
        print(...)
    end
end

local function GetSystemAPI()
    return YUI.API and YUI.API.System or YUI.WOW_API
end

local function GetGlobalDB()
    if YUI.DB and YUI.DB.GetGlobal and YUI.DB.IsReady and YUI.DB:IsReady() then
        local global = YUI.DB:GetGlobal(PRODUCT_ID)
        if type(global) == "table" then
            return global
        end
    end
    return type(YUI.global) == "table" and YUI.global or nil
end

local function GetConfig(create)
    local global = GetGlobalDB()
    if type(global) ~= "table" then
        return nil
    end

    if type(global.devCpuProfile) ~= "table" then
        if not create then
            return nil
        end
        global.devCpuProfile = {}
    end

    return global.devCpuProfile
end

local function GetTimeNow()
    return GetTime and GetTime() or 0
end

local function IsScriptProfileEnabled()
    local SystemAPI = GetSystemAPI()
    if SystemAPI and SystemAPI.GetCVarBool then
        return SystemAPI.GetCVarBool("scriptProfile") == true
    end
    if GetCVarBool then
        return GetCVarBool("scriptProfile") == true
    end
    local value = SystemAPI and SystemAPI.GetCVar and SystemAPI.GetCVar("scriptProfile") or (GetCVar and GetCVar("scriptProfile"))
    return value == true or value == 1 or value == "1" or value == "true"
end

local function EnableScriptProfile()
    local SystemAPI = GetSystemAPI()
    if SystemAPI and SystemAPI.SetCVar then
        return SystemAPI.SetCVar("scriptProfile", 1)
    end
    if SetCVar then
        SetCVar("scriptProfile", 1)
        return true
    end
    return false
end

local function GetNumAddOns()
    local SystemAPI = GetSystemAPI()
    if SystemAPI and SystemAPI.GetNumAddOns then
        return SystemAPI.GetNumAddOns() or 0
    end
    if C_AddOns and C_AddOns.GetNumAddOns then
        local ok, count = pcall(C_AddOns.GetNumAddOns)
        if ok then return count or 0 end
    end
    if GetNumAddOns then
        return GetNumAddOns() or 0
    end
    return 0
end

local function GetAddOnInfo(index)
    local SystemAPI = GetSystemAPI()
    if SystemAPI and SystemAPI.GetAddOnInfo then
        local ok, name, title = pcall(SystemAPI.GetAddOnInfo, index)
        if ok then
            return name, title or name
        end
    end
    if C_AddOns and C_AddOns.GetAddOnInfo then
        local ok, name, title = pcall(C_AddOns.GetAddOnInfo, index)
        if ok then
            return name, title or name
        end
    end
    if GetAddOnInfo then
        local name, title = GetAddOnInfo(index)
        return name, title or name
    end
    return nil, nil
end

local function IsAddOnLoaded(index, name)
    local SystemAPI = GetSystemAPI()
    if SystemAPI and SystemAPI.IsAddOnLoaded then
        local ok, loaded = pcall(SystemAPI.IsAddOnLoaded, index)
        if ok and loaded then return true end
        if name then
            ok, loaded = pcall(SystemAPI.IsAddOnLoaded, name)
            if ok and loaded then return true end
        end
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, index)
        if ok and loaded then return true end
        if name then
            ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
            if ok and loaded then return true end
        end
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, index)
        if ok and loaded then return true end
        if name then
            ok, loaded = pcall(IsAddOnLoaded, name)
            if ok and loaded then return true end
        end
    end
    return false
end

local function UpdateCPUUsage()
    if UpdateAddOnCPUUsage then
        UpdateAddOnCPUUsage()
        return true
    end
    return false
end

local function GetCPUUsage(index)
    if GetAddOnCPUUsage then
        return GetAddOnCPUUsage(index) or 0
    end
    return 0
end

local function HasCPUUsageAPI()
    return UpdateAddOnCPUUsage ~= nil and GetAddOnCPUUsage ~= nil
end

local function ResetCPUUsageBaseline()
    if ResetCPUUsage then
        pcall(ResetCPUUsage)
    end
end

local function CaptureSnapshot()
    UpdateCPUUsage()

    local snapshot = {
        addons = {},
        byName = {},
        time = GetTimeNow(),
    }
    local count = GetNumAddOns()
    for index = 1, count do
        local name, title = GetAddOnInfo(index)
        if name and IsAddOnLoaded(index, name) then
            local data = {
                index = index,
                name = name,
                title = title or name,
                cpu = GetCPUUsage(index),
            }
            snapshot.addons[#snapshot.addons + 1] = data
            snapshot.byName[name] = data
        end
    end

    return snapshot
end

local function FormatMs(value)
    value = tonumber(value) or 0
    if value >= 100 then
        return format("%.0fms", value)
    end
    if value >= 10 then
        return format("%.1fms", value)
    end
    return format("%.3fms", value)
end

local function FindYUIDelta(startSnapshot, finishSnapshot)
    local startData = startSnapshot and startSnapshot.byName and startSnapshot.byName[ADDON_NAME]
    local finishData = finishSnapshot and finishSnapshot.byName and finishSnapshot.byName[ADDON_NAME]
    if not finishData then
        return 0
    end
    return math.max((finishData.cpu or 0) - (startData and startData.cpu or 0), 0)
end

local function BuildTopDeltas(startSnapshot, finishSnapshot)
    local rows = {}
    if not finishSnapshot or type(finishSnapshot.addons) ~= "table" then
        return rows
    end

    for _, finishData in ipairs(finishSnapshot.addons) do
        local startData = startSnapshot and startSnapshot.byName and startSnapshot.byName[finishData.name]
        local delta = math.max((finishData.cpu or 0) - (startData and startData.cpu or 0), 0)
        if delta > 0 then
            insert(rows, {
                name = finishData.name,
                title = finishData.title or finishData.name,
                delta = delta,
            })
        end
    end

    sort(rows, function(a, b)
        return a.delta > b.delta
    end)
    return rows
end

local function PrintTopDeltas(rows, title)
    if #rows == 0 then
        Print((title or "YUI CPU Test top addons:") .. " no CPU delta.")
        return
    end

    local limit = math.min(#rows, TOP_ADDON_LIMIT)
    Print(title or "YUI CPU Test top addons:")
    for index = 1, limit do
        local row = rows[index]
        Print(format("  #%d %s: %s", index, tostring(row.title or row.name), FormatMs(row.delta)))
    end
end

local function GetDefaultLabel()
    local config = GetConfig(false)
    return config and config.label or nil
end

function CPUProfiler:SaveConfig(enabled, label)
    local config = GetConfig(true)
    if not config then
        Print("YUI CPU Test: global DB is not ready.")
        return false
    end

    config.enabled = enabled == true
    if label and label ~= "" then
        config.label = label
    elseif enabled ~= true then
        config.label = nil
    end
    self.enabled = config.enabled
    return true
end

function CPUProfiler:LoadConfig()
    local config = GetConfig(false)
    self.enabled = config and config.enabled == true or false
    return config
end

function CPUProfiler:CancelRun(silent)
    if self.running or self.startSnapshot then
        self.runToken = self.runToken + 1
        self.running = false
        self.startSnapshot = nil
        self.startTime = nil
        self.startLabel = nil
        self.startSource = nil
        if not silent then
            Print("YUI CPU Test: current run cancelled.")
        end
    end
end

function CPUProfiler:EnsureScriptProfile()
    if IsScriptProfileEnabled() then
        return true
    end

    local ok = EnableScriptProfile()
    if ok then
        Print(format(
            "YUI CPU Test: scriptProfile enabled. Please /reload, then the %ds + %ds test will start automatically.",
            WARMUP_SECONDS,
            SAMPLE_SECONDS
        ))
    else
        Print("YUI CPU Test: scriptProfile is off and could not be enabled. Please enable script profiling, then /reload.")
    end
    return false
end

function CPUProfiler:StartRun(label, source)
    if self.running then
        Print("YUI CPU Test: already running. Use /yui dev cpu off to cancel.")
        return false
    end

    if not self:EnsureScriptProfile() then
        return false
    end

    if not (C_Timer and C_Timer.After) then
        Print("YUI CPU Test: C_Timer.After is unavailable.")
        return false
    end

    if not HasCPUUsageAPI() then
        Print("YUI CPU Test: addon CPU usage APIs are unavailable on this client.")
        return false
    end

    self.runToken = self.runToken + 1
    local token = self.runToken
    self.running = true
    self.startSnapshot = nil
    self.startTime = nil
    self.startLabel = Trim(label or GetDefaultLabel() or source or "manual")
    self.startSource = source or "manual"

    Print(format(
        "YUI CPU Test queued: label=%s warmup=%ds sample=%ds.",
        self.startLabel ~= "" and self.startLabel or "-",
        WARMUP_SECONDS,
        SAMPLE_SECONDS
    ))

    C_Timer.After(WARMUP_SECONDS, function()
        if self.runToken ~= token or not self.running then
            return
        end

        local warmupSnapshot = CaptureSnapshot()
        local labelText = self.startLabel ~= "" and self.startLabel or "-"
        local initYUI = FindYUIDelta(nil, warmupSnapshot)
        Print(format(
            "YUI_CPU_INIT label=%s source=%s window=load_to_%ds_after_world YUI=%s",
            labelText,
            tostring(self.startSource or "unknown"),
            WARMUP_SECONDS,
            FormatMs(initYUI)
        ))
        PrintTopDeltas(BuildTopDeltas(nil, warmupSnapshot), "YUI CPU Test init top addons:")

        ResetCPUUsageBaseline()
        self.startSnapshot = CaptureSnapshot()
        self.startTime = self.startSnapshot.time
        Print(format("YUI CPU Test steady started: label=%s.", labelText))

        C_Timer.After(SAMPLE_SECONDS, function()
            if self.runToken ~= token or not self.running then
                return
            end

            local finishSnapshot = CaptureSnapshot()
            local elapsed = math.max((finishSnapshot.time or GetTimeNow()) - (self.startTime or finishSnapshot.time or 0), 0.001)
            local yuiDelta = FindYUIDelta(self.startSnapshot, finishSnapshot)
            local per60 = yuiDelta * 60 / elapsed
            local labelText = self.startLabel ~= "" and self.startLabel or "-"

            Print(format(
                "YUI_CPU_TEST label=%s elapsed=%.1fs YUI=%s per60=%s",
                labelText,
                elapsed,
                FormatMs(yuiDelta),
                FormatMs(per60)
            ))
            PrintTopDeltas(BuildTopDeltas(self.startSnapshot, finishSnapshot), "YUI CPU Test steady top addons:")

            self.running = false
            self.startSnapshot = nil
            self.startTime = nil
            self.startLabel = nil
            self.startSource = nil
        end)
    end)

    return true
end

function CPUProfiler:Enable(label)
    if not self:SaveConfig(true, Trim(label or "")) then
        return true
    end

    Print("YUI CPU Test: auto run enabled.")
    if not self:EnsureScriptProfile() then
        return true
    end

    Print("YUI CPU Test: it will start after the next login or /reload. Use /yui dev cpu run [label] to run now.")
    return true
end

function CPUProfiler:Disable()
    self:SaveConfig(false)
    self:CancelRun(true)
    Print("YUI CPU Test: auto run disabled.")
    return true
end

function CPUProfiler:PrintStatus()
    local config = self:LoadConfig()
    local label = config and config.label or nil
    Print("YUI CPU Test:", self.enabled and "on" or "off")
    Print("scriptProfile:", IsScriptProfileEnabled() and "on" or "off")
    Print("running:", self.running and "yes" or "no")
    Print("label:", label and label ~= "" and label or "-")
    Print(format("window: warmup=%ds sample=%ds", WARMUP_SECONDS, SAMPLE_SECONDS))
    Print("output: YUI_CPU_INIT before reset, then YUI_CPU_TEST steady sample")
end

function CPUProfiler:PrintHelp()
    Print("YUI CPU Test commands:")
    Print("/yui dev cpu on [label]")
    Print("/yui dev cpu off")
    Print("/yui dev cpu status")
    Print("/yui dev cpu run [label]")
end

function CPUProfiler:HandleSlash(args)
    args = Trim(args)
    local command, rest = args:match("^(%S+)%s*(.*)$")
    command = command and command:lower() or "help"
    rest = Trim(rest or "")

    if command == "on" or command == "enable" then
        return self:Enable(rest)
    elseif command == "off" or command == "disable" then
        return self:Disable()
    elseif command == "status" then
        self:PrintStatus()
        return true
    elseif command == "run" or command == "start" then
        self:StartRun(rest, "manual")
        return true
    end

    self:PrintHelp()
    return true
end

local function OnWorldReady(_, isInitialLogin, isReloadingUi)
    CPUProfiler.worldReadyCount = (CPUProfiler.worldReadyCount or 0) + 1
    if isInitialLogin == false and isReloadingUi == false then
        return
    end
    if isInitialLogin == nil and isReloadingUi == nil and CPUProfiler.worldReadyCount > 1 then
        return
    end

    local config = CPUProfiler:LoadConfig()
    if config and config.enabled == true then
        CPUProfiler:StartRun(config.label, "world")
    end
end

if YUI.Event and YUI.Event.On and not CPUProfiler.worldReadyHandle then
    CPUProfiler.worldReadyHandle = YUI.Event:On("YUI_WORLD_READY", OnWorldReady, CPUProfiler, {
        moduleId = "dev.cpu_profiler",
        traceName = "DevCPUProfiler:WorldReady",
        phase = "YUI_WORLD_READY",
    })
end
