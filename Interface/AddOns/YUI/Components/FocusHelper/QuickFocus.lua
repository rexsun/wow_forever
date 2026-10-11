local _, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.FocusHelper) then
    YUI = addonTable
end
if not (YUI and YUI.FocusHelper and YUI.FocusHelper.RegisterSubFeature) then return end

local FocusHelper = YUI.FocusHelper
local Event = YUI.Event
local cpuWatchdog = YUI.CPUWatchdog

local function Perf()
    local state = cpuWatchdog and (cpuWatchdog.sceneCapture or cpuWatchdog.autoCapture)
    if not (state and (cpuWatchdog.timingActive or cpuWatchdog.autoCapture)) then return nil end
    state.quickFocus = state.quickFocus or { reasons = {} }
    return state.quickFocus
end

local AUTO_COUNTS = { requests = true, merged = true, executions = true, scans = true, candidates = true }
local function Count(key, amount)
    if cpuWatchdog and cpuWatchdog.autoCapture and not AUTO_COUNTS[key] then return end
    local perf = Perf()
    if perf then perf[key] = (perf[key] or 0) + (amount or 1) end
end

local queuedPerf, queuedReasons, queuedAt
local function RequestReason(reason, merged)
    local perf = Perf()
    if not perf then return end
    Count("requests")
    if merged then
        Count("merged")
        perf.mergedReasons = perf.mergedReasons or {}
        perf.mergedReasons[reason] = (perf.mergedReasons[reason] or 0) + 1
    end
    perf.reasons[reason] = (perf.reasons[reason] or 0) + 1
    if queuedPerf ~= perf then
        queuedPerf, queuedReasons = perf, {}
        queuedAt = not cpuWatchdog.autoCapture and not merged and debugprofilestop() or nil
        if merged then queuedReasons.preCapture = true end
    end
    queuedReasons[reason] = true
end

local function Executed(reason)
    local perf = Perf()
    if not perf then return end
    Count("executions")
    if cpuWatchdog.autoCapture then
        perf.currentReasons = perf.currentReasons or {}
        for key in pairs(perf.currentReasons) do perf.currentReasons[key] = nil end
        if reason then perf.currentReasons[reason] = true
        elseif queuedPerf == perf then
            for key in pairs(queuedReasons) do perf.currentReasons[key] = true end
        else perf.currentReasons.preCapture = true end
    end
    perf.executedReasons = perf.executedReasons or {}
    if reason then
        perf.executedReasons[reason] = (perf.executedReasons[reason] or 0) + 1
    elseif queuedPerf == perf then
        for key in pairs(queuedReasons) do
            perf.executedReasons[key] = (perf.executedReasons[key] or 0) + 1
        end
        if queuedAt then
            local wait = debugprofilestop() - queuedAt
            Count("waitCalls")
            Count("waitMs", wait)
            perf.waitMaxMs = math.max(perf.waitMaxMs or 0, wait)
        end
    else
        perf.executedReasons.preCapture = (perf.executedReasons.preCapture or 0) + 1
    end
end

local function HasFrameScope(db)
    return db.quickFocusScopeUnitFrames or db.quickFocusScopePartyFrames
        or db.quickFocusScopeRaidFrames or db.quickFocusScopeBossFrames
end

local QuickFocus = {
    id = "quickFocus",
    order = 10,
}

QuickFocus.defaults = {
    quickFocusEnabled = true,
    quickFocusModifier = "SHIFT",
    quickFocusButton = "BUTTON1",
    quickFocusClearBlank = true,
    quickFocusScopeWorld = true,
    quickFocusScopeUnitFrames = true,
    quickFocusScopePartyFrames = true,
    quickFocusScopeRaidFrames = true,
    quickFocusScopeBossFrames = true,
}

local MODULE_ID = "component:FocusHelper:QuickFocus"
local BUTTON_NAME = "YUIFocusHelperQuickFocusButton"
local DRIVER_NAME = "YUIFocusHelperQuickFocusDriver"
local DRIVER_STATE = "yuiquickfocus"
local FOCUS_MACRO_NAME = "YUIQFocus"
local CLEAR_MACRO_NAME = "YUIQFClear"
local MACRO_ICON = "INV_Misc_QuestionMark"
local SETTINGS_WIDTH = 620
local FIELD_GAP = 16
local FIELD_WIDTH = math.floor((SETTINGS_WIDTH - FIELD_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local CONTROL_WIDTH = FIELD_WIDTH - LABEL_WIDTH - LABEL_GAP
local VALUE_WIDTH = 56

local VALID_MODIFIERS = {
    SHIFT = true,
    ALT = true,
    CTRL = true,
}

local VALID_BUTTONS = {
    BUTTON1 = true,
    BUTTON2 = true,
    BUTTON3 = true,
}

local SCOPE_UNIT = "unit"
local SCOPE_PARTY = "party"
local SCOPE_RAID = "raid"
local SCOPE_BOSS = "boss"

local eventOwner = {}
local disableCleanupOwner = {}
local boundFrames = setmetatable({}, { __mode = "k" })
local runtimeActive = false
local featureActive = false
local refreshQueued = false
local refreshTimer
local refreshGeneration = 0
local queuedRefreshMode
local refreshRosterTransaction = false
local pendingRefresh = false
local createFrameHooked = false
local dandersCallbackRegistered = false
local candidateCache
local candidateCacheDirty = true
local lastMacroFailure

local function T(key, fallback)
    return FocusHelper:T(key, fallback)
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then return false end
    local ok, result = pcall(func, ...)
    return ok, result
end

local function NormalizeModifier(value)
    value = type(value) == "string" and value:upper() or nil
    if VALID_MODIFIERS[value] then
        return value
    end
    return QuickFocus.defaults.quickFocusModifier
end

local function NormalizeButton(value)
    value = type(value) == "string" and value:upper() or nil
    if VALID_BUTTONS[value] then
        return value
    end
    return QuickFocus.defaults.quickFocusButton
end

local function NormalizeBinding(value)
    value = type(value) == "string" and value:upper() or ""
    local modifier, button = value:match("^([A-Z]+)%-(BUTTON[123])$")
    return NormalizeModifier(modifier or value), NormalizeButton(button)
end

local function ClampMarker(value)
    value = tonumber(value)
    if not value then return 1 end
    value = math.floor(value + 0.5)
    if value < 1 then return 1 end
    if value > 8 then return 8 end
    return value
end

local function GetBindingChord(db)
    return NormalizeModifier(db and db.quickFocusModifier) .. "-" .. NormalizeButton(db and db.quickFocusButton)
end

local function GetAttributePrefix(db)
    return NormalizeModifier(db and db.quickFocusModifier):lower()
end

local function GetAttributeButtonSuffix(db)
    return NormalizeButton(db and db.quickFocusButton):sub(-1)
end

local function ShouldFocusWorld(db)
    return db and db.quickFocusScopeWorld == true
end

local function ShouldEnableGlobalBinding(db)
    return ShouldFocusWorld(db) or (db and db.quickFocusClearBlank == true)
end

local function IsScopeEnabled(db, scope)
    if scope == SCOPE_PARTY then return db.quickFocusScopePartyFrames == true end
    if scope == SCOPE_RAID then return db.quickFocusScopeRaidFrames == true end
    if scope == SCOPE_BOSS then return db.quickFocusScopeBossFrames == true end
    return db.quickFocusScopeUnitFrames == true
end

local function ShouldUseMarkerMacro(db)
    return db and db.focusMarkerEnabled == true
end

local function ShouldUseAnnounceMacro(db)
    return db and db.focusAnnounceEnabled == true
end

local function ShouldOverwriteMarker(db)
    return db and db.focusMarkerOverwrite == true
end

local function SupportsNonOverwriteMarkerMacro()
    return YUI and (YUI.IsRetail == true or YUI.IsForever == true)
end

local function ShouldClearMarkerOnBlank(db)
    return db and db.quickFocusClearBlank == true and ShouldUseMarkerMacro(db)
end

local function PrintMacroFailure(status)
    status = status or "FAILED"
    if lastMacroFailure == status then return end
    lastMacroFailure = status
    if not (YUI and YUI.Print) then return end

    if status == "TOO_LONG" then
        YUI:Print(T("message.quick_focus_macro_too_long", "Quick Focus reserved macro is longer than 255 bytes. Shorten the announcement template."))
    elseif status == "NO_SLOT" then
        YUI:Print(T("message.quick_focus_macro_no_slot", "Quick Focus needs a free macro slot for its reserved macro. No duplicate macros were created."))
    elseif status == "CLEANUP_FAILED" then
        YUI:Print(T("message.quick_focus_macro_cleanup_failed", "Quick Focus could not clean duplicate reserved macros. No new macro was created."))
    else
        YUI:Print(T("message.quick_focus_macro_create_failed", "Quick Focus could not create or update its reserved macro."))
    end
end

local function PrintMacroCleanup()
    if not (YUI and YUI.Print) then return end
    YUI:Print(T("message.quick_focus_macro_cleanup_done", "Quick Focus cleaned duplicate reserved macros."))
end

local function ClearMacroFailure()
    lastMacroFailure = nil
end

local function GetAnnounceMacroLine(db)
    if not ShouldUseAnnounceMacro(db) then return nil end
    if FocusHelper.GetFocusAnnounceMacroLine then
        return FocusHelper:GetFocusAnnounceMacroLine(db)
    end
    return nil
end

local function BuildSetMacroBody(db, includeAnnounce)
    local lines = { "/focus [@mouseover,exists,nodead]" }
    if ShouldUseMarkerMacro(db) then
        if ShouldOverwriteMarker(db) then
            lines[#lines + 1] = "/tm [@mouseover,exists,nodead] " .. tostring(ClampMarker(db.focusMarkerIndex))
        elseif SupportsNonOverwriteMarkerMacro() then
            lines[#lines + 1] = "/tm [@mouseover,exists,nodead] ~" .. tostring(ClampMarker(db.focusMarkerIndex))
        end
    end
    if includeAnnounce then
        local announceLine = GetAnnounceMacroLine(db)
        if announceLine then
            lines[#lines + 1] = announceLine
        end
    end
    return table.concat(lines, "\n")
end

local function BuildClickMacroBody(db, includeAnnounce)
    local body = ShouldFocusWorld(db) and BuildSetMacroBody(db, includeAnnounce) or ""
    if db.quickFocusClearBlank ~= true then
        return body
    end

    if body ~= "" then body = body .. "\n" end
    body = body .. "/stopmacro [@mouseover,exists]"
    if ShouldClearMarkerOnBlank(db) then
        body = body .. "\n/tm [@focus,exists] 0"
    end
    body = body .. "\n/clearfocus [@focus,exists]"
    return body
end

local function BuildClearMacroBody(db)
    local lines = {}
    if ShouldClearMarkerOnBlank(db) then
        lines[#lines + 1] = "/tm [@focus,exists] 0"
    end
    lines[#lines + 1] = "/clearfocus [@focus,exists]"
    return table.concat(lines, "\n")
end

local function NormalizeMacroBody(body)
    if type(body) ~= "string" then return nil end
    body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    while body:sub(-1) == "\n" do
        body = body:sub(1, -2)
    end
    return body
end

local function MacroBodyMatches(actual, expected)
    local normalizedActual = NormalizeMacroBody(actual)
    local normalizedExpected = NormalizeMacroBody(expected)
    return normalizedActual ~= nil and normalizedActual == normalizedExpected
end

local function HasMacroAPI()
    return type(GetMacroIndexByName) == "function"
        and type(GetMacroInfo) == "function"
        and type(GetNumMacros) == "function"
        and type(CreateMacro) == "function"
        and type(EditMacro) == "function"
end

local function CollectStoredMacrosByName(name)
    local matches = {}
    local generalCount, characterCount = GetNumMacros()
    generalCount = tonumber(generalCount) or 0
    characterCount = tonumber(characterCount) or 0

    local maxGeneral = MAX_ACCOUNT_MACROS or 120
    for index = 1, generalCount do
        local macroName = GetMacroInfo(index)
        if macroName == name then
            matches[#matches + 1] = { index = index, slot = index, character = false }
        end
    end
    for slot = 1, characterCount do
        local index = maxGeneral + slot
        local macroName = GetMacroInfo(index)
        if macroName == name then
            matches[#matches + 1] = { index = index, slot = slot, character = true }
        end
    end
    return matches
end

local function SelectStoredMacroToKeep(matches)
    local keep
    for _, match in ipairs(matches) do
        if match.character and (not keep or not keep.character or match.slot < keep.slot) then
            keep = match
        end
    end
    if keep then return keep end

    for _, match in ipairs(matches) do
        if not keep or match.slot < keep.slot then
            keep = match
        end
    end
    return keep
end

local function SortMacroIndexDescending(left, right)
    return left.index > right.index
end

local function DeduplicateStoredMacro(name)
    local matches = CollectStoredMacrosByName(name)
    if #matches <= 1 then
        return true, matches[1] and matches[1].index or nil, 0
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false, nil, "PENDING"
    end
    if type(DeleteMacro) ~= "function" then
        return false, nil, "CLEANUP_FAILED"
    end

    local keep = SelectStoredMacroToKeep(matches)
    if not keep then
        return false, nil, "CLEANUP_FAILED"
    end

    local deletes = {}
    for _, match in ipairs(matches) do
        if match.index ~= keep.index then
            deletes[#deletes + 1] = match
        end
    end
    table.sort(deletes, SortMacroIndexDescending)

    for _, match in ipairs(deletes) do
        local ok = pcall(DeleteMacro, match.index)
        if not ok then
            return false, nil, "CLEANUP_FAILED"
        end
    end

    matches = CollectStoredMacrosByName(name)
    if #matches ~= 1 then
        return false, nil, "CLEANUP_FAILED"
    end
    return true, matches[1].index, #deletes
end

local function EnsureStoredMacro(name, body, allowCreate)
    if type(name) ~= "string" or name == "" or type(body) ~= "string" then
        return nil, "FAILED"
    end
    if not HasMacroAPI() then
        return nil, "FAILED"
    end

    local cleanupOk, cleanupIndex, cleanedCountOrStatus = DeduplicateStoredMacro(name)
    if not cleanupOk then
        return nil, cleanedCountOrStatus or "CLEANUP_FAILED"
    end
    if cleanedCountOrStatus and cleanedCountOrStatus > 0 then
        PrintMacroCleanup()
    end
    if #body > 255 then
        return nil, "TOO_LONG"
    end

    local macroIndex = cleanupIndex or GetMacroIndexByName(name)
    if macroIndex and macroIndex > 0 then
        local _, _, existingBody = GetMacroInfo(macroIndex)
        if not MacroBodyMatches(existingBody, body) then
            local ok = pcall(EditMacro, macroIndex, name, MACRO_ICON, body)
            if not ok then return nil, "FAILED" end
        end
        return name
    end

    if allowCreate ~= true then
        return nil, "MISSING"
    end

    local generalCount, characterCount = GetNumMacros()
    local maxGeneral = MAX_ACCOUNT_MACROS or 120
    local maxCharacter = MAX_CHARACTER_MACROS or 18
    local ok
    if (characterCount or 0) < maxCharacter then
        ok = pcall(CreateMacro, name, MACRO_ICON, body, true)
    elseif (generalCount or 0) < maxGeneral then
        ok = pcall(CreateMacro, name, MACRO_ICON, body)
    else
        return nil, "NO_SLOT"
    end

    local createdIndex = GetMacroIndexByName(name)
    if ok and createdIndex and createdIndex > 0 then
        return name
    end
    return nil, "FAILED"
end

local function RefreshExistingReservedMacros(db)
    local _, focusStatus = EnsureStoredMacro(FOCUS_MACRO_NAME, BuildSetMacroBody(db, false), false)
    if focusStatus and focusStatus ~= "MISSING" and focusStatus ~= "PENDING" then
        PrintMacroFailure(focusStatus)
        return false
    end
    if db and db.quickFocusClearBlank == true then
        local _, clearStatus = EnsureStoredMacro(CLEAR_MACRO_NAME, BuildClearMacroBody(db), false)
        if clearStatus and clearStatus ~= "MISSING" and clearStatus ~= "PENDING" then
            PrintMacroFailure(clearStatus)
            return false
        end
    end
    return true
end

local function EnsureReservedMacros(db)
    local state = {}
    if not ShouldUseAnnounceMacro(db) then
        if RefreshExistingReservedMacros(db) then
            ClearMacroFailure()
        end
        return state
    end

    local focusName, focusStatus = EnsureStoredMacro(FOCUS_MACRO_NAME, BuildSetMacroBody(db, true), true)
    if not focusName then
        if focusStatus ~= "PENDING" then
            PrintMacroFailure(focusStatus)
        end
        return state
    end

    state.focusMacroName = focusName
    if db.quickFocusClearBlank == true then
        local clearName, clearStatus = EnsureStoredMacro(CLEAR_MACRO_NAME, BuildClearMacroBody(db), true)
        if clearName then
            state.clearMacroName = clearName
        elseif clearStatus ~= "MISSING" then
            if clearStatus ~= "PENDING" then
                PrintMacroFailure(clearStatus)
            end
            return {}
        end
    end

    if state.focusMacroName and (db.quickFocusClearBlank ~= true or state.clearMacroName) then
        ClearMacroFailure()
    end
    return state
end

local function RegisterBindingButtonClicks(button)
    if not button then return end
    local secure = YUI and YUI.GUI2 and YUI.GUI2.Secure
    if secure and secure.RegisterActionClicks then
        secure:RegisterActionClicks(button)
    elseif button.RegisterForClicks then
        button:RegisterForClicks("AnyUp", "AnyDown")
    end
end

local function EnsureBindingButton()
    if QuickFocus.button then
        RegisterBindingButtonClicks(QuickFocus.button)
        return QuickFocus.button
    end
    local button = _G[BUTTON_NAME]
    if not button then
        button = CreateFrame("CheckButton", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    end
    RegisterBindingButtonClicks(button)
    QuickFocus.button = button
    return button
end

local function ClearLegacyButtonBinding()
    if not QuickFocus.button then return end
    ClearOverrideBindings(QuickFocus.button)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "type", nil)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "type1", nil)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "macro", nil)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "macro1", nil)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "macrotext", nil)
    pcall(QuickFocus.button.SetAttribute, QuickFocus.button, "macrotext1", nil)
end

local function EnsureBindingDriver()
    if QuickFocus.bindingDriver then
        return QuickFocus.bindingDriver
    end
    if not (CreateFrame and UIParent) then return nil end
    local driver = _G[DRIVER_NAME]
    if not driver then
        driver = CreateFrame("Frame", DRIVER_NAME, UIParent, "SecureHandlerStateTemplate")
    end
    driver:SetAttribute("_onstate-" .. DRIVER_STATE, [[
        self:ClearBindings();
        local bindingChord = self:GetAttribute("bindingChord");
        local macroName = nil;
        if newstate == "focus" then
            macroName = self:GetAttribute("focusMacroName");
        elseif newstate == "clear" then
            macroName = self:GetAttribute("clearMacroName");
        end
        if macroName and bindingChord then
            self:SetBindingMacro(true, bindingChord, macroName);
        end
    ]])
    QuickFocus.bindingDriver = driver
    return driver
end

local function DisableBindingDriver()
    if not QuickFocus.bindingDriver then return end
    if UnregisterStateDriver then
        pcall(UnregisterStateDriver, QuickFocus.bindingDriver, DRIVER_STATE)
    end
    ClearOverrideBindings(QuickFocus.bindingDriver)
end

local function GetDriverCondition(db, macroState)
    if ShouldFocusWorld(db) and db.quickFocusClearBlank == true and macroState and macroState.clearMacroName then
        return "[@mouseover,exists,nodead] focus; [@mouseover,noexists] clear; off"
    end
    if ShouldFocusWorld(db) then
        return "[@mouseover,exists,nodead] focus; off"
    end
    if db and db.quickFocusClearBlank == true and macroState and macroState.clearMacroName then
        return "[@mouseover,noexists] clear; off"
    end
    return "off"
end

local function EnableMacroBindingDriver(db, macroState)
    if not (macroState and macroState.focusMacroName and RegisterStateDriver and ClearOverrideBindings) then
        return false
    end
    local driver = EnsureBindingDriver()
    if not driver then return false end

    ClearLegacyButtonBinding()
    pcall(UnregisterStateDriver, driver, DRIVER_STATE)
    ClearOverrideBindings(driver)
    driver:SetAttribute("focusMacroName", macroState.focusMacroName)
    driver:SetAttribute("clearMacroName", macroState.clearMacroName)
    driver:SetAttribute("bindingChord", GetBindingChord(db))
    local ok = pcall(RegisterStateDriver, driver, DRIVER_STATE, GetDriverCondition(db, macroState))
    return ok == true
end

local function EnableLegacyGlobalBinding(db)
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end

    DisableBindingDriver()
    local button = EnsureBindingButton()
    if not button then return false end

    ClearOverrideBindings(button)
    local macroBody = BuildClickMacroBody(db, false)
    pcall(button.SetAttribute, button, "type", "macro")
    pcall(button.SetAttribute, button, "type1", "macro")
    pcall(button.SetAttribute, button, "macrotext", macroBody)
    pcall(button.SetAttribute, button, "macrotext1", macroBody)
    SetOverrideBindingClick(button, true, GetBindingChord(db), BUTTON_NAME, "LeftButton")
    return true
end

local function EnableGlobalBinding(db, macroState)
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end

    if macroState and macroState.focusMacroName and EnableMacroBindingDriver(db, macroState) then
        return true
    end
    return EnableLegacyGlobalBinding(db)
end

local function DisableGlobalBinding()
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end
    DisableBindingDriver()
    ClearLegacyButtonBinding()
    return true
end

local function FrameAttributeEquals(frame, attribute, expected)
    if not frame or type(frame.GetAttribute) ~= "function" then return false end
    local ok, value = pcall(frame.GetAttribute, frame, attribute)
    return ok and value == expected
end

local function RestoreFrameBinding(frame, record)
    if frame and record then Count("restores") end
    if frame and record and type(frame.SetAttribute) == "function" then
        if record.typeAttr and FrameAttributeEquals(frame, record.typeAttr, record.typeValue or "focus") then
            pcall(frame.SetAttribute, frame, record.typeAttr, record.previousType)
        end
        if record.unitAttr and FrameAttributeEquals(frame, record.unitAttr, record.unitValue) then
            pcall(frame.SetAttribute, frame, record.unitAttr, record.previousUnit)
        end
        if record.macroAttr and FrameAttributeEquals(frame, record.macroAttr, record.macroValue) then
            pcall(frame.SetAttribute, frame, record.macroAttr, record.previousMacro)
        end
    end
    boundFrames[frame] = nil
end

local function RestoreFrameBindings()
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end
    for frame, record in pairs(boundFrames) do
        RestoreFrameBinding(frame, record)
    end
    return true
end

local function GetFrameName(frame)
    if frame and type(frame.GetName) == "function" then
        local ok, name = pcall(frame.GetName, frame)
        if ok then return name end
    end
    return nil
end

local function GetFrameUnit(frame)
    if not frame then return nil end
    if type(frame.unit) == "string" then return frame.unit end
    if type(frame.GetAttribute) == "function" then
        local ok, unit = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(unit) == "string" then return unit end
    end
    return nil
end

local function ResolveBindableUnit(frame, explicitUnit)
    if not frame
        or type(frame.SetAttribute) ~= "function"
        or type(frame.GetAttribute) ~= "function"
        or type(frame.RegisterForClicks) ~= "function" then
        return nil
    end
    local name = GetFrameName(frame)
    if name and name:find("oUF_NPs", 1, true) then return nil end

    local unit = explicitUnit or GetFrameUnit(frame)
    if type(unit) ~= "string" or unit == "" or unit == "none" then return nil end
    return unit
end

local function BindFrame(frame, db, explicitUnit)
    Count("bindingChecks")
    if not frame then return false end
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end

    local unit = ResolveBindableUnit(frame, explicitUnit)
    if not unit then
        local record = boundFrames[frame]
        if record then RestoreFrameBinding(frame, record) end
        return false
    end

    local prefix = GetAttributePrefix(db)
    local buttonSuffix = GetAttributeButtonSuffix(db)
    local typeAttr = prefix .. "-type" .. buttonSuffix
    local unitAttr = prefix .. "-unit" .. buttonSuffix
    local namedMacro = QuickFocus.activeMacroState and QuickFocus.activeMacroState.focusMacroName
    local useNamedMacro = ShouldUseAnnounceMacro(db) and namedMacro
    local useMacroText = (not useNamedMacro) and ShouldUseMarkerMacro(db)
    local useMacro = useNamedMacro or useMacroText
    local typeValue = useMacro and "macro" or "focus"
    local macroAttr = useNamedMacro and (prefix .. "-macro" .. buttonSuffix)
        or (useMacroText and (prefix .. "-macrotext" .. buttonSuffix) or nil)
    local macroValue = useNamedMacro and namedMacro or (useMacroText and BuildSetMacroBody(db, false) or nil)
    local desiredUnitAttr = (not useMacro and unit) and unitAttr or nil
    local desiredMacroAttr = useMacro and macroAttr or nil

    local record = boundFrames[frame]
    if record
        and record.typeAttr == typeAttr
        and record.typeValue == typeValue
        and record.unitAttr == desiredUnitAttr
        and record.unitValue == unit
        and record.macroAttr == desiredMacroAttr
        and record.macroValue == macroValue
        and FrameAttributeEquals(frame, typeAttr, typeValue)
        and (not desiredUnitAttr or FrameAttributeEquals(frame, desiredUnitAttr, unit))
        and (not desiredMacroAttr or FrameAttributeEquals(frame, desiredMacroAttr, macroValue)) then
        return true
    end
    if record then RestoreFrameBinding(frame, record) end
    local okType, previousType = pcall(frame.GetAttribute, frame, typeAttr)
    local okUnit, previousUnit = pcall(frame.GetAttribute, frame, unitAttr)
    local okMacro, previousMacro = false, nil
    if macroAttr then
        okMacro, previousMacro = pcall(frame.GetAttribute, frame, macroAttr)
    end
    boundFrames[frame] = {
        typeAttr = typeAttr,
        typeValue = typeValue,
        unitAttr = desiredUnitAttr,
        macroAttr = desiredMacroAttr,
        previousType = okType and previousType or nil,
        previousUnit = okUnit and previousUnit or nil,
        previousMacro = okMacro and previousMacro or nil,
        unitValue = unit,
        macroValue = macroValue,
    }

    if pcall(frame.SetAttribute, frame, typeAttr, typeValue) then Count("bindingWrites") end
    if useMacro then
        if pcall(frame.SetAttribute, frame, macroAttr, macroValue) then Count("bindingWrites") end
    elseif unit then
        if pcall(frame.SetAttribute, frame, unitAttr, unit) then Count("bindingWrites") end
    end
    return true
end

local function InvalidateCandidateCache()
    candidateCacheDirty = true
    candidateCache = nil
end

local function ClassifyScope(value, fallback)
    value = type(value) == "string" and value:lower() or ""
    if value:find("party", 1, true) then return SCOPE_PARTY end
    if value:find("raid", 1, true) then return SCOPE_RAID end
    if value:find("boss", 1, true) or value:find("arena", 1, true) or value:find("extra", 1, true) then
        return SCOPE_BOSS
    end
    return fallback
end

local function AddCandidate(list, seen, frame, unit, scanChildren, depth, scope)
    if type(frame) == "string" then frame = _G[frame] end
    if not frame then return end

    local candidateScope = scope or ClassifyScope(unit or GetFrameUnit(frame), SCOPE_UNIT)
    local existing = seen[frame]
    if existing then
        if unit and not existing.unit then existing.unit = unit end
        if scope then existing.scope = scope end
        return
    end

    local candidate = { frame = frame, unit = unit, scope = candidateScope }
    seen[frame] = candidate
    list[#list + 1] = candidate

    if not scanChildren or depth == 0 or type(frame.GetChildren) ~= "function" then return end
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        AddCandidate(list, seen, child, nil, true, (depth or 1) - 1, scope)
    end
end

local function AddFrameTableCandidates(list, seen, frames, scanChildren, depth, scope)
    if type(frames) ~= "table" then return end
    for key, frame in pairs(frames) do
        local candidateScope = scope or ClassifyScope(key)
        AddCandidate(list, seen, frame, nil, scanChildren, depth, candidateScope)
    end
end

local function AddUnitMapCandidates(list, seen, frames)
    if type(frames) ~= "table" then return end
    for unit, frame in pairs(frames) do
        local explicitUnit = type(unit) == "string" and unit or nil
        AddCandidate(list, seen, frame, explicitUnit, nil, nil, ClassifyScope(explicitUnit))
    end
end

local function AddHeaderButtonCandidates(list, seen, header, maxButtons, scope)
    if type(header) == "string" then header = _G[header] end
    if not header then return end

    AddCandidate(list, seen, header, nil, true, 1, scope)
    maxButtons = maxButtons or 40

    for index = 1, maxButtons do
        AddCandidate(list, seen, header[index], nil, nil, nil, scope)

        if type(header.GetAttribute) == "function" then
            local ok, child = pcall(header.GetAttribute, header, "child" .. index)
            if ok then AddCandidate(list, seen, child, nil, nil, nil, scope) end
        end
    end
end

local function AddNativeCandidates(list, seen)
    AddCandidate(list, seen, "PlayerFrame", "player", nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "PetFrame", "pet", nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "TargetFrame", "target", nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "TargetFrameToT", "targettarget", nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "FocusFrame", "focus", nil, nil, SCOPE_UNIT)

    for index = 1, 5 do
        AddCandidate(list, seen, "PartyMemberFrame" .. index, "party" .. index, nil, nil, SCOPE_PARTY)
        AddCandidate(list, seen, "CompactPartyFrameMember" .. index, "party" .. index, nil, nil, SCOPE_PARTY)
        AddCandidate(list, seen, "Boss" .. index .. "TargetFrame", "boss" .. index, nil, nil, SCOPE_BOSS)
        AddCandidate(list, seen, "BossTargetFrame" .. index, "boss" .. index, nil, nil, SCOPE_BOSS)
    end
    for index = 1, 40 do
        AddCandidate(list, seen, "CompactRaidFrame" .. index, "raid" .. index, nil, nil, SCOPE_RAID)
    end
    AddCandidate(list, seen, "CompactPartyFrame", nil, true, 3, SCOPE_PARTY)
    AddCandidate(list, seen, "CompactRaidFrameContainer", nil, true, 3, SCOPE_RAID)
end

local function AddElvUICandidates(list, seen)
    AddCandidate(list, seen, "ElvUF_Player", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "ElvUF_Target", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "ElvUF_TargetTarget", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "ElvUF_Focus", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "ElvUF_Party", nil, true, 3, SCOPE_PARTY)
    AddCandidate(list, seen, "ElvUF_Raid", nil, true, 3, SCOPE_RAID)

    local ns = _G.ElvUI
    local core = type(ns) == "table" and ns[1] or nil
    local uf
    if core and type(core.GetModule) == "function" then
        local ok, module = pcall(core.GetModule, core, "UnitFrames", true)
        if ok and type(module) == "table" then uf = module end
    end
    if not uf then return end
    for key, frame in pairs(uf.units or {}) do
        AddCandidate(list, seen, frame, nil, nil, nil, ClassifyScope(key))
    end
    for key, frame in pairs(uf.groupunits or {}) do
        AddCandidate(list, seen, frame, nil, true, 3, ClassifyScope(key))
    end
    for key, frame in pairs(uf.headers or {}) do
        AddCandidate(list, seen, frame, nil, true, 3, ClassifyScope(key))
    end
end

local function AddNDuiCandidates(list, seen)
    AddCandidate(list, seen, "oUF_Player", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "oUF_Target", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "oUF_ToT", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "oUF_Focus", nil, nil, nil, SCOPE_UNIT)
    AddCandidate(list, seen, "oUF_Party", nil, true, 3, SCOPE_PARTY)
    AddCandidate(list, seen, "oUF_Raid", nil, true, 3, SCOPE_RAID)
    for group = 1, 8 do
        AddCandidate(list, seen, "oUF_Raid" .. group, nil, true, 3, SCOPE_RAID)
        AddCandidate(list, seen, "oUF_Raid" .. group .. "UnitButton1", nil, true, 2, SCOPE_RAID)
    end

    local ns = _G.NDui or _G.NDUI
    local oUF = type(ns) == "table" and ns.oUF or nil
    local objects = oUF and oUF.objects
    if type(objects) == "table" then
        for key, frame in pairs(objects) do
            AddCandidate(list, seen, frame, nil, nil, nil, ClassifyScope(key))
        end
    end
end

local function AddEQoLCandidates(list, seen)
    local unitNames = {
        "EQOLUFPlayerFrame", "EQOLUFPetFrame", "EQOLUFTargetFrame", "EQOLUFToTFrame", "EQOLUFFocusFrame",
        "EQOLUFPartyFrame", "EQOLUFPartyHeaderUnitButton1", "EQOLUFRaidFrame", "EQOLUFRaidHeader1",
    }
    local headerNames = {
        "EQOLUFPartyHeader", "EQOLUFRaidHeader",
    }
    local anchorNames = {
        "EQOLUFPartyAnchor", "EQOLUFRaidAnchor",
    }
    for _, name in ipairs(unitNames) do
        AddCandidate(list, seen, name, nil, nil, nil, ClassifyScope(name, SCOPE_UNIT))
    end
    for _, name in ipairs(headerNames) do
        AddHeaderButtonCandidates(list, seen, name, 40, ClassifyScope(name, SCOPE_UNIT))
    end
    for _, name in ipairs(anchorNames) do
        AddCandidate(list, seen, name, nil, true, 2, ClassifyScope(name, SCOPE_UNIT))
    end
    for index = 1, 5 do
        AddCandidate(list, seen, "EQOLUFBoss" .. index .. "Frame", "boss" .. index, nil, nil, SCOPE_BOSS)
    end
    for index = 1, 8 do
        AddHeaderButtonCandidates(list, seen, "EQOLUFRaidGroupHeader" .. index, 5, SCOPE_RAID)
    end

    local groupFrames = _G.EnhanceQoL
        and _G.EnhanceQoL.Aura
        and _G.EnhanceQoL.Aura.UF
        and _G.EnhanceQoL.Aura.UF.GroupFrames
    if type(groupFrames) ~= "table" then return end

    AddFrameTableCandidates(list, seen, groupFrames.anchors, true, 2)
    AddFrameTableCandidates(list, seen, groupFrames.headers, true, 1)
    AddFrameTableCandidates(list, seen, groupFrames._raidGroupHeaders, true, 1, SCOPE_RAID)

    if type(groupFrames.headers) == "table" then
        for key, header in pairs(groupFrames.headers) do
            AddHeaderButtonCandidates(list, seen, header, 40, ClassifyScope(key))
        end
    end
    if type(groupFrames._raidGroupHeaders) == "table" then
        for _, header in pairs(groupFrames._raidGroupHeaders) do
            AddHeaderButtonCandidates(list, seen, header, 5, SCOPE_RAID)
        end
    end
end

local function AddCellCandidates(list, seen)
    local cell = _G.Cell
    local frames = type(cell) == "table" and cell.frames or nil
    if type(frames) == "table" then
        for key, frame in pairs(frames) do
            AddCandidate(list, seen, frame, nil, true, 4, ClassifyScope(key))
        end
    end
    AddCandidate(list, seen, "CellPartyFrame", nil, true, 4, SCOPE_PARTY)
    AddCandidate(list, seen, "CellRaidFrame", nil, true, 4, SCOPE_RAID)
    AddCandidate(list, seen, "CellMainFrame", nil, true, 4)
end

local function AddDandersCandidates(list, seen)
    local api = _G.DandersFrames

    local function AddDandersUnit(unit, kind)
        if type(_G.DandersFrames_GetFrameForUnit) == "function" then
            local ok, frame = SafeCall(_G.DandersFrames_GetFrameForUnit, unit)
            if ok then AddCandidate(list, seen, frame, unit, nil, nil, ClassifyScope(unit, SCOPE_UNIT)) end
        end
        if type(api) == "table" then
            if type(api.GetFrameForUnit) == "function" then
                local ok, frame = SafeCall(api.GetFrameForUnit, api, unit)
                if ok then AddCandidate(list, seen, frame, unit, nil, nil, ClassifyScope(unit, SCOPE_UNIT)) end
            end
            if type(api.Api) == "table" and type(api.Api.GetFrameForUnit) == "function" then
                local ok, frame = SafeCall(api.Api.GetFrameForUnit, unit, kind)
                if ok then AddCandidate(list, seen, frame, unit, nil, nil, ClassifyScope(unit, SCOPE_UNIT)) end
            end
        end
    end

    AddDandersUnit("player", "party")
    for index = 1, 4 do
        AddDandersUnit("party" .. index, "party")
    end
    for index = 1, 40 do
        AddDandersUnit("raid" .. index, "raid")
    end

    if type(api) == "table" then
        AddUnitMapCandidates(list, seen, api.unitFrameMap)
        AddCandidate(list, seen, api.playerFrame, "player", nil, nil, SCOPE_UNIT)
        AddCandidate(list, seen, api.partyContainer, nil, true, 2, SCOPE_PARTY)
        AddCandidate(list, seen, api.container, nil, true, 2)
        AddHeaderButtonCandidates(list, seen, api.partyHeader, 5, SCOPE_PARTY)

        if type(api.IteratePartyFrames) == "function" then
            SafeCall(api.IteratePartyFrames, api, function(frame, _, unit)
                local explicitUnit = type(unit) == "string" and unit or nil
                AddCandidate(list, seen, frame, explicitUnit, nil, nil, ClassifyScope(explicitUnit, SCOPE_PARTY))
            end)
        end
        if type(api.IterateRaidFrames) == "function" then
            SafeCall(api.IterateRaidFrames, api, function(frame, _, unit)
                local explicitUnit = type(unit) == "string" and unit or nil
                AddCandidate(list, seen, frame, explicitUnit, nil, nil, ClassifyScope(explicitUnit, SCOPE_RAID))
            end)
        end
        if type(api.IterateCompactFrames) == "function" then
            SafeCall(api.IterateCompactFrames, api, function(frame)
                AddCandidate(list, seen, frame)
            end)
        end
        if type(api.GetPlayerFrame) == "function" then
            local ok, frame = SafeCall(api.GetPlayerFrame, api)
            if ok then AddCandidate(list, seen, frame, "player", nil, nil, SCOPE_UNIT) end
        end
        if type(api.GetPartyFrame) == "function" then
            for index = 1, 4 do
                local ok, frame = SafeCall(api.GetPartyFrame, api, index)
                if ok then AddCandidate(list, seen, frame, "party" .. index, nil, nil, SCOPE_PARTY) end
            end
        end
        if type(api.GetRaidFrame) == "function" then
            for index = 1, 40 do
                local ok, frame = SafeCall(api.GetRaidFrame, api, index)
                if ok then AddCandidate(list, seen, frame, "raid" .. index, nil, nil, SCOPE_RAID) end
            end
        end
        if type(api.GetAllFrames) == "function" then
            local ok, frames = SafeCall(api.GetAllFrames, api)
            if ok then AddFrameTableCandidates(list, seen, frames) end
        end
    end

    if type(_G.DandersFrames_GetAllFrames) == "function" then
        local ok, frames = SafeCall(_G.DandersFrames_GetAllFrames)
        if ok and type(frames) == "table" then
            for _, frame in pairs(frames) do
                AddCandidate(list, seen, frame)
            end
        end
    end
    if type(_G.DandersFrames_IterateFrames) == "function" then
        SafeCall(_G.DandersFrames_IterateFrames, function(frame)
            AddCandidate(list, seen, frame)
        end)
    end
    if type(_G.DandersFrames_GetPlayerFrame) == "function" then
        local ok, frame = SafeCall(_G.DandersFrames_GetPlayerFrame)
        if ok then AddCandidate(list, seen, frame, "player", nil, nil, SCOPE_UNIT) end
    end
    if type(_G.DandersFrames_GetPartyFrame) == "function" then
        for index = 1, 4 do
            local ok, frame = SafeCall(_G.DandersFrames_GetPartyFrame, index)
            if ok then AddCandidate(list, seen, frame, "party" .. index, nil, nil, SCOPE_PARTY) end
        end
    end
    if type(_G.DandersFrames_GetRaidFrame) == "function" then
        for index = 1, 40 do
            local ok, frame = SafeCall(_G.DandersFrames_GetRaidFrame, index)
            if ok then AddCandidate(list, seen, frame, "raid" .. index, nil, nil, SCOPE_RAID) end
        end
    end
    AddCandidate(list, seen, "DandersFrames_Player", "player", nil, nil, SCOPE_UNIT)
    local partyHeader
    if type(_G.DandersFrames_GetPartyHeader) == "function" then
        local ok, result = SafeCall(_G.DandersFrames_GetPartyHeader)
        if ok then partyHeader = result end
    end
    AddHeaderButtonCandidates(list, seen, partyHeader, 5, SCOPE_PARTY)
    AddHeaderButtonCandidates(list, seen, "DandersPartyHeader", 5, SCOPE_PARTY)
    AddCandidate(list, seen, "DandersRaidFrame", nil, true, 4, SCOPE_RAID)
    for group = 1, 8 do
        local header
        if type(_G.DandersFrames_GetRaidGroupHeader) == "function" then
            local ok, result = SafeCall(_G.DandersFrames_GetRaidGroupHeader, group)
            if ok then header = result end
        end
        AddHeaderButtonCandidates(list, seen, header, 5, SCOPE_RAID)
        AddHeaderButtonCandidates(list, seen, "DandersRaidGroup" .. group .. "Header", 5, SCOPE_RAID)
    end
end

local function AddEllesmereCandidates(list, seen)
    AddCandidate(list, seen, "EllesmereUIRaidFrameContainer", nil, true, 2, SCOPE_RAID)
    AddHeaderButtonCandidates(list, seen, "ERFFlatHeader", 40, SCOPE_RAID)
    AddHeaderButtonCandidates(list, seen, "ERFPartyHeader", 5, SCOPE_PARTY)
    AddCandidate(list, seen, "ERFPartySelfButton", "player", nil, nil, SCOPE_PARTY)
    AddCandidate(list, seen, "ERFFriendlyBossContainer", nil, true, 1, SCOPE_BOSS)
    AddCandidate(list, seen, "ERFExtraFramesContainer", nil, true, 1, SCOPE_BOSS)

    for index = 1, 8 do
        AddHeaderButtonCandidates(list, seen, "ERFGroupHeader" .. index, 5, SCOPE_RAID)
    end
    for index = 1, 5 do
        AddCandidate(list, seen, "ERFFriendlyBoss" .. index, "boss" .. index, nil, nil, SCOPE_BOSS)
        AddCandidate(list, seen, "ERFExtraFrame" .. index, nil, nil, nil, SCOPE_BOSS)
    end

    local erf = _G.EllesmereUIRaidFrames
    if type(erf) == "table" then
        AddFrameTableCandidates(list, seen, erf._allButtons, nil, nil, SCOPE_RAID)
        AddFrameTableCandidates(list, seen, erf._partyAllButtons, nil, nil, SCOPE_PARTY)
        AddUnitMapCandidates(list, seen, erf._raidUnitToButton)
        AddUnitMapCandidates(list, seen, erf._partyUnitToButton)
        AddUnitMapCandidates(list, seen, erf._xfUnitToButton)
    end

    local perf = cpuWatchdog and cpuWatchdog.sceneCapture and Perf()
    local startedAt = perf and cpuWatchdog:BeginProbeTiming()
    for name, frame in pairs(_G) do
        if perf then perf.globalsVisited = (perf.globalsVisited or 0) + 1 end
        if type(name) == "string" and name:find("Ellesmere", 1, true) and type(frame) == "table" and type(frame.SetAttribute) == "function" then
            AddCandidate(list, seen, frame, nil, true, 2, ClassifyScope(name))
        end
    end
    if startedAt then cpuWatchdog:EndProbeTiming("quick-focus.global-scan", startedAt, nil, "quick-focus.collect.7") end
end

local function ScanCandidates()
    if not candidateCacheDirty and candidateCache then
        Count("cacheHits")
        return candidateCache
    end

    Count("scans")
    local list, seen = {}, {}
    local scanNative = Perf() and cpuWatchdog:BeginProbeTiming()
    AddNativeCandidates(list, seen)
    if scanNative then cpuWatchdog:EndProbeTiming("quick-focus.collect.1", scanNative, nil, "quick-focus.scan-candidates") end
    local scanElvUI = Perf() and cpuWatchdog:BeginProbeTiming()
    AddElvUICandidates(list, seen)
    if scanElvUI then cpuWatchdog:EndProbeTiming("quick-focus.collect.2", scanElvUI, nil, "quick-focus.scan-candidates") end
    local scanNDui = Perf() and cpuWatchdog:BeginProbeTiming()
    AddNDuiCandidates(list, seen)
    if scanNDui then cpuWatchdog:EndProbeTiming("quick-focus.collect.3", scanNDui, nil, "quick-focus.scan-candidates") end
    local scanEQoL = Perf() and cpuWatchdog:BeginProbeTiming()
    AddEQoLCandidates(list, seen)
    if scanEQoL then cpuWatchdog:EndProbeTiming("quick-focus.collect.4", scanEQoL, nil, "quick-focus.scan-candidates") end
    local scanCell = Perf() and cpuWatchdog:BeginProbeTiming()
    AddCellCandidates(list, seen)
    if scanCell then cpuWatchdog:EndProbeTiming("quick-focus.collect.5", scanCell, nil, "quick-focus.scan-candidates") end
    local scanDanders = Perf() and cpuWatchdog:BeginProbeTiming()
    AddDandersCandidates(list, seen)
    if scanDanders then cpuWatchdog:EndProbeTiming("quick-focus.collect.6", scanDanders, nil, "quick-focus.scan-candidates") end
    local scanEllesmere = Perf() and cpuWatchdog:BeginProbeTiming()
    AddEllesmereCandidates(list, seen)
    if scanEllesmere then cpuWatchdog:EndProbeTiming("quick-focus.collect.7", scanEllesmere, nil, "quick-focus.scan-candidates") end
    Count("candidates", #list)
    local perf = Perf()
    if perf then perf.candidateMax = math.max(perf.candidateMax or 0, #list) end
    candidateCache = list
    candidateCacheDirty = false
    return candidateCache
end

local bindingGeneration = 0
local function BindUnitFrames(db, macroState)
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end
    if not HasFrameScope(db) then
        RestoreFrameBindings()
        InvalidateCandidateCache()
        Count("scopeSkips")
        return true
    end
    QuickFocus.activeMacroState = macroState or {}
    bindingGeneration = bindingGeneration + 1
    local watchdog = YUI.CPUWatchdog
    local startedAt = watchdog and watchdog.sceneCapture and watchdog:BeginProbeTiming()
    local candidates = ScanCandidates()
    if startedAt then
        watchdog:EndProbeTiming("quick-focus.scan-candidates", startedAt)
        startedAt = watchdog:BeginProbeTiming()
    end
    for _, candidate in ipairs(candidates) do
        if IsScopeEnabled(db, candidate.scope) then
            BindFrame(candidate.frame, db, candidate.unit)
            local record = boundFrames[candidate.frame]
            if record then record.generation = bindingGeneration end
        end
    end
    for frame, record in pairs(boundFrames) do
        if record.generation ~= bindingGeneration then RestoreFrameBinding(frame, record) end
    end
    if startedAt then watchdog:EndProbeTiming("quick-focus.reconcile-bindings", startedAt) end
    return true
end

local function CancelQueuedRefresh()
    queuedPerf, queuedReasons, queuedAt = nil, nil, nil
    refreshQueued = false
    refreshGeneration = refreshGeneration + 1
    queuedRefreshMode = nil
    refreshRosterTransaction = false
    if refreshTimer and refreshTimer.Cancel then
        pcall(refreshTimer.Cancel, refreshTimer)
    end
    refreshTimer = nil
end

local function RunQueuedRefresh(generation)
    if generation ~= refreshGeneration then return end
    Executed()
    queuedPerf, queuedReasons, queuedAt = nil, nil, nil
    local mode = queuedRefreshMode
    local rosterTransaction = refreshRosterTransaction
    refreshQueued = false
    refreshTimer = nil
    queuedRefreshMode = nil
    refreshRosterTransaction = false
    if not featureActive then return end
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    if mode == "roster" then
        QuickFocus:RefreshRosterRuntime()
    else
        QuickFocus:RefreshRuntime()
    end
    if startedAt then
        local diagnosticID = mode == "roster"
            and "component.quick-focus.roster-batch"
            or "component.quick-focus.full-refresh"
        local diagnosticLabel = mode == "roster"
            and "QuickFocus roster batch"
            or "QuickFocus full refresh"
        cpuWatchdog:EndProbeTiming(
            diagnosticID,
            startedAt,
            diagnosticLabel,
            nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
        )
    end
end

local function QueueRefresh(delay, mode, reason)
    RequestReason(reason or "enable", refreshQueued)
    mode = mode == "roster" and "roster" or "full"
    if mode == "roster" then refreshRosterTransaction = true end
    if refreshQueued then
        if mode == "full" and queuedRefreshMode == "roster" and (tonumber(delay) or 0) > 0 then
            if refreshTimer and refreshTimer.Cancel then pcall(refreshTimer.Cancel, refreshTimer) end
        else
            if mode == "full" then queuedRefreshMode = "full" end
            return
        end
    end
    refreshQueued = true
    queuedRefreshMode = mode
    refreshGeneration = refreshGeneration + 1
    local generation = refreshGeneration
    local delaySeconds = tonumber(delay) or 0

    if C_Timer and C_Timer.NewTimer then
        refreshTimer = C_Timer.NewTimer(delaySeconds, function()
            RunQueuedRefresh(generation)
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delaySeconds, function()
            RunQueuedRefresh(generation)
        end)
    else
        RunQueuedRefresh(generation)
    end
end

local RegisterDisableCleanupEvent

local function ClearDisableCleanupEvent()
    if Event and Event.OffOwner then
        Event:OffOwner(disableCleanupOwner)
    end
end

local function OnDisableCleanupEvent(event)
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    ClearDisableCleanupEvent()
    pendingRefresh = false
    local cleaned = QuickFocus:DisableRuntime()
    if cleaned == false and RegisterDisableCleanupEvent then
        RegisterDisableCleanupEvent()
    end
end

RegisterDisableCleanupEvent = function()
    if not (Event and Event.On) then return end
    Event:OffOwner(disableCleanupOwner)
    Event:On("PLAYER_REGEN_ENABLED", OnDisableCleanupEvent, disableCleanupOwner, {
        traceName = "FocusHelper:QuickFocus:disable-cleanup",
        moduleId = MODULE_ID,
    })
end

local function OnRuntimeEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingRefresh then
            pendingRefresh = false
            QueueRefresh(0, nil, "postCombat")
        end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        QueueRefresh(0, "roster", "roster")
        return
    end
    InvalidateCandidateCache()
    QueueRefresh(event == "ADDON_LOADED" and 0.5 or 0, nil, event == "ADDON_LOADED" and "addon" or "world")
end

local function HookCreateFrame()
    if createFrameHooked or type(hooksecurefunc) ~= "function" then return end
    local ok = pcall(hooksecurefunc, "CreateFrame", function(_, name, _, template)
        if not runtimeActive then return end
        if type(template) ~= "string" or not template:find("SecureUnitButtonTemplate", 1, true) then return end
        InvalidateCandidateCache()
        QueueRefresh(0.1, nil, "created")
    end)
    createFrameHooked = ok == true
end

local function RegisterRuntimeEvents()
    if not (Event and Event.On) then return end
    Event:OffOwner(eventOwner)
    Event:On("PLAYER_ENTERING_WORLD", OnRuntimeEvent, eventOwner, { moduleId = MODULE_ID })
    Event:On("GROUP_ROSTER_UPDATE", OnRuntimeEvent, eventOwner, {
        moduleId = MODULE_ID,
        traceName = "FocusHelper:QuickFocus:GROUP_ROSTER_UPDATE",
        throttle = 0.1,
    })
    Event:On("PLAYER_REGEN_ENABLED", OnRuntimeEvent, eventOwner, { moduleId = MODULE_ID })
    Event:On("ADDON_LOADED", OnRuntimeEvent, eventOwner, { moduleId = MODULE_ID })
end

local function RegisterDandersCallback()
    if dandersCallbackRegistered then return end
    local api = _G.DandersFrames
    if type(api) ~= "table" or type(api.RegisterCallback) ~= "function" then return end
    local ok = pcall(api.RegisterCallback, QuickFocus, "OnFramesSorted", function()
        InvalidateCandidateCache()
        QueueRefresh(0.1, nil, "sorted")
    end)
    dandersCallbackRegistered = ok == true
end

local function UnregisterDandersCallback()
    if not dandersCallbackRegistered then return end
    local api = _G.DandersFrames
    if type(api) == "table" and type(api.UnregisterCallback) == "function" then
        pcall(api.UnregisterCallback, QuickFocus, "OnFramesSorted")
    end
    dandersCallbackRegistered = false
end

function QuickFocus:NormalizeDB(db)
    if type(db) ~= "table" then return db end
    db.quickFocusEnabled = db.quickFocusEnabled ~= false
    local modifier, button = NormalizeBinding(db.quickFocusModifier)
    if VALID_BUTTONS[type(db.quickFocusButton) == "string" and db.quickFocusButton:upper() or ""] then
        button = NormalizeButton(db.quickFocusButton)
    end
    db.quickFocusModifier = modifier
    db.quickFocusButton = button
    db.quickFocusClearBlank = db.quickFocusClearBlank ~= false
    db.quickFocusScopeWorld = db.quickFocusScopeWorld ~= false
    db.quickFocusScopeUnitFrames = db.quickFocusScopeUnitFrames ~= false
    db.quickFocusScopePartyFrames = db.quickFocusScopePartyFrames ~= false
    db.quickFocusScopeRaidFrames = db.quickFocusScopeRaidFrames ~= false
    db.quickFocusScopeBossFrames = db.quickFocusScopeBossFrames ~= false
    return db
end

function QuickFocus:RefreshRuntime(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())
    if not featureActive or db.quickFocusEnabled ~= true then
        self:DisableRuntime()
        return
    end
    ClearDisableCleanupEvent()
    if InCombatLockdown and InCombatLockdown() then
        Count("combatDeferred")
        pendingRefresh = true
        return
    end

    if runtimeActive ~= true then
        InvalidateCandidateCache()
    end
    runtimeActive = true
    pendingRefresh = false
    local watchdog = YUI.CPUWatchdog
    local startedAt = watchdog and watchdog.sceneCapture and watchdog:BeginProbeTiming()
    local macroState = EnsureReservedMacros(db)
    if startedAt then
        watchdog:EndProbeTiming("quick-focus.ensure-macros", startedAt)
        startedAt = watchdog:BeginProbeTiming()
    end
    self.activeMacroState = macroState
    if ShouldEnableGlobalBinding(db) then
        EnableGlobalBinding(db, macroState)
    else
        DisableGlobalBinding()
    end
    if startedAt then watchdog:EndProbeTiming("quick-focus.global-binding", startedAt) end
    BindUnitFrames(db, macroState)
end

function QuickFocus:RefreshRosterRuntime(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())
    if not featureActive or db.quickFocusEnabled ~= true then return end
    if InCombatLockdown and InCombatLockdown() then
        Count("combatDeferred")
        pendingRefresh = true
        return
    end
    if not HasFrameScope(db) then
        RestoreFrameBindings()
        InvalidateCandidateCache()
        Count("scopeSkips")
        return
    end
    if candidateCacheDirty or type(candidateCache) ~= "table" then
        self:RefreshRuntime(db)
        return
    end

    Count("cacheHits")
    pendingRefresh = false
    for _, candidate in ipairs(candidateCache) do
        if IsScopeEnabled(db, candidate.scope) then
            BindFrame(candidate.frame, db, candidate.unit)
        end
    end
end

local function MeasureAutomaticRefresh(callback, id)
    return function(self, ...)
        if cpuWatchdog and cpuWatchdog.autoCapture then
            local perf = Perf()
            perf.pointReasons = perf.pointReasons or {}
            local reasons = perf.pointReasons[id]
            if not reasons then reasons = {}; perf.pointReasons[id] = reasons end
            if perf.currentReasons then
                for reason in pairs(perf.currentReasons) do reasons[reason] = (reasons[reason] or 0) + 1 end
            end
            return cpuWatchdog:MeasureTargetTask(id, callback, self, ...)
        end
        return callback(self, ...)
    end
end
QuickFocus.RefreshRuntime = MeasureAutomaticRefresh(QuickFocus.RefreshRuntime, "component.quick-focus.full-refresh")
QuickFocus.RefreshRosterRuntime = MeasureAutomaticRefresh(QuickFocus.RefreshRosterRuntime, "component.quick-focus.roster-batch")

function QuickFocus:DisableRuntime()
    InvalidateCandidateCache()
    CancelQueuedRefresh()
    runtimeActive = false
    self.activeMacroState = nil
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        return false
    end
    pendingRefresh = false
    DisableGlobalBinding()
    RestoreFrameBindings()
    return true
end

function QuickFocus:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    if featureActive then
        ClearDisableCleanupEvent()
        InvalidateCandidateCache()
        RegisterRuntimeEvents()
        RegisterDandersCallback()
        HookCreateFrame()
        Count("requests")
        local perf = Perf()
        if perf then perf.reasons.enable = (perf.reasons.enable or 0) + 1 end
        Executed("enable")
        self:RefreshRuntime(db)
        InvalidateCandidateCache()
        QueueRefresh(1)
        QueueRefresh(3)
    else
        CancelQueuedRefresh()
        if Event and Event.OffOwner then
            Event:OffOwner(eventOwner)
        end
        UnregisterDandersCallback()
        local cleaned = self:DisableRuntime()
        if cleaned == false then
            RegisterDisableCleanupEvent()
        else
            ClearDisableCleanupEvent()
        end
    end
end

local function BuildBindingOptions()
    return {
        { text = T("settings.quick_focus_modifier_shift", "Shift + Left Click"), value = "SHIFT-BUTTON1" },
        { text = T("settings.quick_focus_modifier_alt", "Alt + Left Click"), value = "ALT-BUTTON1" },
        { text = T("settings.quick_focus_modifier_ctrl", "Ctrl + Left Click"), value = "CTRL-BUTTON1" },
        { text = T("settings.quick_focus_modifier_shift_middle", "Shift + Middle Click"), value = "SHIFT-BUTTON3" },
        { text = T("settings.quick_focus_modifier_alt_middle", "Alt + Middle Click"), value = "ALT-BUTTON3" },
        { text = T("settings.quick_focus_modifier_ctrl_middle", "Ctrl + Middle Click"), value = "CTRL-BUTTON3" },
        { text = T("settings.quick_focus_modifier_shift_right", "Shift + Right Click"), value = "SHIFT-BUTTON2" },
        { text = T("settings.quick_focus_modifier_alt_right", "Alt + Right Click"), value = "ALT-BUTTON2" },
        { text = T("settings.quick_focus_modifier_ctrl_right", "Ctrl + Right Click"), value = "CTRL-BUTTON2" },
    }
end

local function RefreshSettings(db)
    Count("requests")
    local perf = Perf()
    if perf then perf.reasons.settings = (perf.reasons.settings or 0) + 1 end
    Executed("settings")
    QuickFocus:RefreshRuntime(db)
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SETTINGS_WIDTH }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SETTINGS_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SETTINGS_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SETTINGS_WIDTH, SETTINGS_WIDTH),
                columns = 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = FIELD_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = CONTROL_WIDTH,
                valueWidth = VALUE_WIDTH,
                valueGap = LABEL_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function QuickFocus:BuildOptions(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())

    local options = {}
    AddAlignedFieldGroup(options, T("settings.quick_focus", "Quick Focus"), {
        {
            type = "checkbox",
            label = T("settings.quick_focus_enable", "Enable quick focus"),
            settingsToggle = "quickFocus",
            searchKey = "settings.quick_focus_enable",
            get = function() return db.quickFocusEnabled == true end,
            set = function(value)
                db.quickFocusEnabled = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.quick_focus_clear_blank", "Clear focus on blank click"),
            get = function() return db.quickFocusClearBlank == true end,
            set = function(value)
                db.quickFocusClearBlank = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.quick_focus_modifier", "Modifier"),
            options = BuildBindingOptions,
            default = GetBindingChord(QuickFocus.defaults),
            get = function() return GetBindingChord(db) end,
            set = function(value)
                db.quickFocusModifier, db.quickFocusButton = NormalizeBinding(value)
                RefreshSettings(db)
            end,
        },
    }, { hideDivider = true })

    AddAlignedFieldGroup(options, T("settings.quick_focus_scope", "Scope"), {
        {
            type = "checkbox",
            label = T("settings.quick_focus_scope_world", "World units"),
            get = function() return db.quickFocusScopeWorld == true end,
            set = function(value)
                db.quickFocusScopeWorld = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.quick_focus_scope_unit_frames", "Unit frames"),
            get = function() return db.quickFocusScopeUnitFrames == true end,
            set = function(value)
                db.quickFocusScopeUnitFrames = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.quick_focus_scope_party_frames", "Party frames"),
            get = function() return db.quickFocusScopePartyFrames == true end,
            set = function(value)
                db.quickFocusScopePartyFrames = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.quick_focus_scope_raid_frames", "Raid frames"),
            get = function() return db.quickFocusScopeRaidFrames == true end,
            set = function(value)
                db.quickFocusScopeRaidFrames = value == true
                RefreshSettings(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.quick_focus_scope_boss_frames", "Boss and extra frames"),
            get = function() return db.quickFocusScopeBossFrames == true end,
            set = function(value)
                db.quickFocusScopeBossFrames = value == true
                RefreshSettings(db)
            end,
        },
    })

    return options
end

FocusHelper:RegisterSubFeature(QuickFocus)
