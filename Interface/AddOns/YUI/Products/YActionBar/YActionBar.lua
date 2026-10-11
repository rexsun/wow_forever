local ADDON_NAME = ...
local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
YAB.name = "YActionBar"

if YUI.Assets and YUI.Assets.RegisterProductRoot then
    YUI.Assets:RegisterProductRoot(YAB.PRODUCT_ID or "yactionbar", "Interface\\AddOns\\" .. (ADDON_NAME or YUI.AddonName or "YUI") .. "\\Products\\YActionBar\\Media")
end

local function Print(message)
    if YUI.Print then
        YUI:Print(message)
    elseif print then
        print(message)
    end
end

local function InCombat()
    if YAB.Adapter and YAB.Adapter.InCombat then
        return YAB.Adapter:InCombat()
    end
    if type(_G.UnitAffectingCombat) == "function" then
        local ok, affecting = pcall(_G.UnitAffectingCombat, "player")
        if ok and affecting == true then return true end
    end
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true or false
end

local function IsWorldReady(owner)
    if owner and owner.runtimeWorldReady == true then return true end
    local lifecycle = YUI and YUI.Lifecycle
    if lifecycle and lifecycle.IsReady and lifecycle:IsReady("YUI_WORLD_READY") == true then
        if owner then owner.runtimeWorldReady = true end
        return true
    end
    return false
end

function YAB:ShouldDeferRuntimeStartup()
    if not IsWorldReady(self) then
        return true, "world"
    end
    if InCombat() then
        return true, "combat"
    end
    return false, nil
end

local function ClearRuntimeDeferredState(owner)
    owner.runtimeDeferredInCombat = false
    owner.runtimeDeferredWorld = false
    owner.runtimeDeferredReason = nil
    owner.runtimeDeferredMode = nil
    owner.runtimeDeferredOperation = nil
    local frame = owner.runtimeDeferredFrame or owner.combatDeferredFrame
    if frame then
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end
    local db = owner.db
    if db and db.runtime then
        db.runtime.deferredInCombat = false
        db.runtime.deferredWorld = false
        db.runtime.deferredReason = nil
        db.runtime.deferredMode = nil
        db.runtime.deferredOperation = nil
    end
end

local function OnRuntimeDeferredEvent(frame, event)
    if event == "PLAYER_ENTERING_WORLD" then
        YAB.runtimeWorldReady = true
    end

    local reason = YAB.runtimeDeferredReason or event
    local operation = YAB.runtimeDeferredOperation or "enable"
    local shouldDefer, mode = YAB:ShouldDeferRuntimeStartup()
    if shouldDefer then
        YAB:ScheduleRuntimeDeferred(reason, mode, operation)
        return
    end

    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    ClearRuntimeDeferredState(YAB)
    if YAB.ApplyRuntimeOperation then
        YAB:ApplyRuntimeOperation(operation, reason)
    elseif YAB:IsEnabled() and YAB.OnLifecycleEnable then
        YAB:OnLifecycleEnable()
    end
end

function YAB:ScheduleRuntimeDeferred(reason, mode, operation)
    local shouldDefer, deferMode = self:ShouldDeferRuntimeStartup()
    if not shouldDefer then
        ClearRuntimeDeferredState(self)
        return true
    end
    mode = deferMode or mode or "combat"
    reason = reason or (mode == "world" and "world startup" or "combat lockdown")
    operation = operation or "enable"
    self.runtimeDeferredInCombat = mode == "combat"
    self.runtimeDeferredWorld = mode == "world"
    self.runtimeDeferredReason = reason
    self.runtimeDeferredMode = mode
    self.runtimeDeferredOperation = operation
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    local db = self:GetDB()
    if db and db.runtime then
        db.runtime.deferredInCombat = self.runtimeDeferredInCombat == true
        db.runtime.deferredWorld = self.runtimeDeferredWorld == true
        db.runtime.deferredReason = reason
        db.runtime.deferredMode = mode
        db.runtime.deferredOperation = operation
        db.runtime.blocked = false
        db.runtime.blockedReason = nil
    end
    local frame = self.runtimeDeferredFrame or self.combatDeferredFrame
    if not frame then
        frame = CreateFrame("Frame", "YUI_YActionBar_RuntimeDeferredFrame")
        self.runtimeDeferredFrame = frame
        self.combatDeferredFrame = frame
    end
    frame:UnregisterAllEvents()
    if mode == "world" then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    frame:SetScript("OnEvent", OnRuntimeDeferredEvent)
    return false, reason
end

function YAB:ScheduleCombatDeferredRuntime(reason, operation)
    return self:ScheduleRuntimeDeferred(reason or "combat lockdown", "combat", operation)
end

local function CleanPersistedRecipeSnapshot(owner, db)
    if type(db) ~= "table" or owner.cleanedRecipeSnapshotDB == db then
        return db
    end
    owner.cleanedRecipeSnapshotDB = db
    local recipes = db.recipes
    if type(recipes) == "table" then
        recipes.snapshot = nil
        recipes.previewing = nil
    end
    return db
end

function YAB:GetProfile()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile(self.PRODUCT_ID)
        if type(profile) == "table" then
            return profile
        end
    end
    return nil
end

function YAB:EnsureDB()
    local profile = self:GetProfile()
    if type(profile) ~= "table" then
        self.db = self.db or self:CopyValue(self.Defaults)
        CleanPersistedRecipeSnapshot(self, self.db)
        return self.db
    end
    if type(profile[self.STORAGE_KEY]) ~= "table" then
        profile[self.STORAGE_KEY] = {}
    end
    self.db = profile[self.STORAGE_KEY]
    self:MergeDefaults(self.db)
    CleanPersistedRecipeSnapshot(self, self.db)
    return self.db
end

function YAB:RecordStartupEnabled()
    if self.sessionStartupEnabledRecorded then return true end
    local profile = self:GetProfile()
    if type(profile) ~= "table" then return false end
    local db = self:EnsureDB()
    self.sessionStartupEnabled = db and db.enabled == true
    self.sessionStartupEnabledRecorded = true
    self.enabledChangedThisSession = false
    return true
end

function YAB:GetDB()
    return self:EnsureDB()
end

function YAB:IsEnabled()
    local db = self:GetDB()
    return db and db.enabled == true
end

function YAB:GetReloadRequiredMessage(reason)
    local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("YActionBar") or nil
    return reason
        or (locale and locale["settings.reload_required_message"])
        or "YActionBar could not safely restore the current action bar state. Use /reload."
end

function YAB:MarkReloadRequired(reason, silent)
    local db = self:GetDB()
    if not db then return false end
    db.runtime = db.runtime or {}
    local message = self:GetReloadRequiredMessage(reason)
    local alreadyReported = db.runtime.reloadRequired == true and db.runtime.reloadRequiredReason == message
    db.runtime.reloadRequired = true
    db.runtime.reloadRequiredReason = message
    db.runtime.takeoverMode = "strong"
    db.runtime.specialButtonMode = YAB.SPECIAL_BUTTON_MODE or "native-reuse"
    self.runtimeReloadRequired = true
    self.runtimeReloadRequiredReason = message
    local manager = self.BarManager
    if manager then
        manager.reloadRequired = true
        manager.reloadRequiredReason = message
    end
    if not silent and not alreadyReported then
        Print("YActionBar: " .. tostring(message))
    end
    return true
end

function YAB:ClearReloadRequired()
    local db = self:GetDB()
    if db and db.runtime then
        db.runtime.reloadRequired = false
        db.runtime.reloadRequiredReason = nil
    end
    self.runtimeReloadRequired = false
    self.runtimeReloadRequiredReason = nil
    local manager = self.BarManager
    if manager then
        manager.reloadRequired = false
        manager.reloadRequiredReason = nil
    end
    return true
end

function YAB:SetEnabled(enabled)
    local db = self:GetDB()
    if not db then return false end
    local nextEnabled = enabled == true
    local wasEnabled = db.enabled == true
    db.enabled = nextEnabled
    if not nextEnabled and self.RankUpgrade then self.RankUpgrade:Stop() end
    db.runtime = db.runtime or {}
    db.runtime.takeoverMode = "strong"
    db.runtime.specialButtonMode = YAB.SPECIAL_BUTTON_MODE or "native-reuse"
    if nextEnabled ~= wasEnabled then
        self.enabledChangedThisSession = true
    end
    return true
end

function YAB:OpenSettings(barId)
    if self.SettingsBridge then
        return self.SettingsBridge:Open(barId)
    end
    return nil
end

function YAB:Initialize()
    self:EnsureDB()
    self:RecordStartupEnabled()
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.externalConflict = nil
    if YUI.Yield then YUI.Yield:Clear("actionbar") end
    self.runtimeDeferredInCombat = false
    self.runtimeDeferredWorld = false
    self.runtimeDeferredReason = nil
    self.runtimeDeferredMode = nil
    self.runtimeDeferredOperation = nil
    self.runtimeWorldReady = IsWorldReady(self)
end

function YAB:RegisterLayoutEditEventListeners(manager)
    local eventBus = YUI.Event
    if not (manager and eventBus and type(eventBus.On) == "function") then return false end
    local opened = eventBus:On(
        "YUI_LAYOUT_EDIT_MODE_OPENED",
        "OnLayoutEditModeChanged",
        manager,
        { moduleId = "yactionbar", traceName = "YActionBar:LayoutEditModeOpened" }
    )
    local closed = eventBus:On(
        "YUI_LAYOUT_EDIT_MODE_CLOSED",
        "OnLayoutEditModeChanged",
        manager,
        { moduleId = "yactionbar", traceName = "YActionBar:LayoutEditModeClosed" }
    )
    if opened and closed then return true end
    if opened and eventBus.Off then eventBus:Off(opened) end
    if closed and eventBus.Off then eventBus:Off(closed) end
    return false
end

function YAB:OnLifecycleEnable()
    local db = self:GetDB()
    if not db or db.enabled ~= true then return end
    self:RecordStartupEnabled()
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.externalConflict = nil

    local conflict = self.ConflictGuard and self.ConflictGuard:Check() or { blocked = false }
    db.conflict.last = conflict
    if conflict.blocked then
        self.externalConflict = conflict
        self.runtimeBlocked = true
        self.runtimeBlockedReason = conflict.reason or "external-actionbar-controller"
        if self.BarManager then
            self.BarManager:ShutdownRuntime()
        end
        if conflict.status == "active" and YUI.Yield then
            YUI.Yield:Set("actionbar", conflict.controller, {
                status = conflict.status,
                matches = conflict.matches,
                enabled = true,
            })
        elseif YUI.Yield then
            YUI.Yield:Clear("actionbar")
        end
        return
    else
        self.externalConflict = nil
        if YUI.Yield then YUI.Yield:Clear("actionbar") end
    end

    if self.BarManager and self.BarManager.runtimeActive == true then
        self:ClearReloadRequired()
        if self.BarManager.QueueRefresh then self.BarManager:QueueRefresh("enable") end
        return true
    end

    if self.Client and self.Client.supported ~= true then
        self.runtimeBlocked = true
        self.runtimeBlockedReason = "Mists 暂不进入 YActionBar 首版运行目标。"
        return
    end

    local shouldDefer, deferMode = self:ShouldDeferRuntimeStartup()
    if shouldDefer then
        return self:ScheduleRuntimeDeferred(deferMode == "world" and "world startup" or "combat startup", deferMode, "enable")
    end

    ClearRuntimeDeferredState(self)

    if self.BarManager then
        local ok, reason = self.BarManager:CreateRuntime()
        if not ok then
            reason = reason or "YActionBar runtime creation failed."
            if db.runtime and db.runtime.reloadRequired == true then
                self.runtimeBlocked = false
                self.runtimeBlockedReason = nil
            else
                self.runtimeBlocked = true
                self.runtimeBlockedReason = reason
                if db.runtime then
                    db.runtime.blocked = true
                    db.runtime.blockedReason = reason
                end
            end
            Print("YActionBar: " .. tostring(reason))
        elseif ok and db.runtime then
            db.runtime.blocked = false
            db.runtime.blockedReason = nil
            if not self.externalConflict then
                self:ClearReloadRequired()
            else
                self:MarkReloadRequired("检测到其他动作条控制器；YActionBar 将保持到 /reload，重载后再让渡。", true)
            end
            db.runtime.takeoverMode = "strong"
            db.runtime.specialButtonMode = YAB.SPECIAL_BUTTON_MODE or "native-reuse"
        end
    end
end

function YAB:ApplyRuntimeDisable(reason)
    if self.CancelBindMode then
        self:CancelBindMode("disable")
    end
    local shouldDefer, deferMode = self:ShouldDeferRuntimeStartup()
    if shouldDefer then
        return self:ScheduleRuntimeDeferred(reason or (deferMode == "world" and "world disable" or "combat disable"), deferMode, "disable")
    end

    ClearRuntimeDeferredState(self)
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.externalConflict = nil

    local ok, shutdownReason = true, nil
    if self.BarManager then
        ok, shutdownReason = self.BarManager:ShutdownRuntime()
    end
    if not ok then
        self:MarkReloadRequired(shutdownReason or "YActionBar 无法安全恢复原生动作条状态，请 /reload。", false)
        return false, shutdownReason
    end

    local db = self:GetDB()
    if db and db.runtime then
        db.runtime.blocked = false
        db.runtime.blockedReason = nil
        db.runtime.reloadRequired = false
        db.runtime.reloadRequiredReason = nil
        db.runtime.takeoverMode = "native"
        db.runtime.specialButtonMode = "native"
    end
    self.runtimeReloadRequired = false
    self.runtimeReloadRequiredReason = nil

    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end
    return true
end

function YAB:ApplyRuntimeRebuild(reason, operation)
    if self.CancelBindMode then
        self:CancelBindMode(operation == "profile" and "profile" or "rebuild")
    end
    local shouldDefer, deferMode = self:ShouldDeferRuntimeStartup()
    if shouldDefer then
        return self:ScheduleRuntimeDeferred(reason or (deferMode == "world" and "world rebuild" or "combat rebuild"), deferMode, operation or "rebuild")
    end

    ClearRuntimeDeferredState(self)
    self:EnsureDB()
    if not self:IsEnabled() then
        return self:ApplyRuntimeDisable(reason or "disabled rebuild")
    end

    if self.BarManager and self.BarManager.runtimeActive then
        local ok, shutdownReason = self.BarManager:ShutdownRuntime()
        if not ok then
            self:MarkReloadRequired(shutdownReason or "YActionBar 无法安全重建动作条运行时，请 /reload。", false)
            return false, shutdownReason
        end
    end

    self:OnLifecycleEnable()
    if self.runtimeBlocked == true then
        return false, self.runtimeBlockedReason
    end
    return true
end

function YAB:ApplyRuntimeOperation(operation, reason)
    if operation == "disable" then
        return self:ApplyRuntimeDisable(reason)
    end
    if operation == "rebuild" or operation == "profile" then
        return self:ApplyRuntimeRebuild(reason, operation)
    end
    if self:IsEnabled() then
        return self:OnLifecycleEnable()
    end
    return self:ApplyRuntimeDisable(reason)
end

function YAB:OnLifecycleDisable()
    return self:ApplyRuntimeDisable("disable")
end

function YAB:GetYieldController()
    local conflict = self.externalConflict
    if self.runtimeBlocked == true and type(conflict) == "table"
        and conflict.blocked == true and conflict.status == "active" then
        return type(conflict.controller) == "string" and conflict.controller or nil, true
    end
    return nil, false
end

function YAB:OnLifecycleProfileChanged()
    self:EnsureDB()
    return self:ApplyRuntimeRebuild("profile changed", "profile")
end

function YAB:OnLifecycleConfigChanged(reason)
    self:Refresh(reason or "config")
    if self.ConfigSets and self.ConfigSets.SaveActive then
        self.ConfigSets:SaveActive(reason or "lifecycle-config", self)
    end
end

function YAB:OnLifecycleLayoutChanged()
    self:Refresh("layout")
    if self.ConfigSets and self.ConfigSets.SaveActive then
        self.ConfigSets:SaveActive("lifecycle-layout", self)
    end
end

function YAB:Enable()
    self:SetEnabled(true)
    if YUI.Module and YUI.Module.SetEnabled then
        return YUI.Module:SetEnabled(self.PRODUCT_ID, true)
    end
    self:OnLifecycleEnable()
    return true
end

function YAB:Disable()
    self:SetEnabled(false)
    if YUI.Module and YUI.Module.SetEnabled then
        return YUI.Module:SetEnabled(self.PRODUCT_ID, false)
    end
    self:OnLifecycleDisable()
    return true
end

function YAB:Refresh(reason)
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        for _, id in ipairs(self.BAR_ORDER or {}) do
            YUI.Layout:InvalidateAnchorProvider("yactionbar." .. id)
        end
    end
    if self.BarManager then
        if self:IsEnabled() and not self.BarManager.runtimeActive and self.OnLifecycleEnable then
            local shouldDefer, deferMode = self:ShouldDeferRuntimeStartup()
            if shouldDefer then
                return self:ScheduleRuntimeDeferred(reason or (deferMode == "world" and "world refresh" or "combat refresh"), deferMode, "enable")
            end
            self:OnLifecycleEnable()
            if self.runtimeDeferredInCombat or self.runtimeDeferredWorld then
                return false
            end
        end
        if self.BarManager.runtimeActive then
            self.BarManager:QueueRefresh(reason or "refresh")
            return true
        end
    end
    return false
end

function YAB:RebuildRuntime(reason)
    if not self.BarManager then return false end
    if self:IsEnabled() or (self.BarManager and self.BarManager.runtimeActive) then
        return self:ApplyRuntimeRebuild(reason or "rebuild", "rebuild")
    end
    return false
end

function YAB:ApplyRecipe(id)
    return self.Recipes and self.Recipes:Apply(id, false)
end

function YAB:SetSkin(skin)
    local db = self:GetDB()
    if not db then return false end
    db.appearance = db.appearance or {}
    db.appearance.skin = self.Skins and self.Skins:Normalize(skin) or "default"
    self:Refresh("skin")
    return true
end

function YAB:PrintDiagnosticVisualMode()
    local mode = self.Visuals and self.Visuals.GetDiagnosticVisualMode and self.Visuals:GetDiagnosticVisualMode() or "enhanced"
    local stats = self:GetStats()
    Print(string.format(
        "YActionBar: visual mode=%s sessionOnly=true visualExtra=%d",
        tostring(mode),
        stats.visualExtraHidden or 0
    ))
end

function YAB:SetDiagnosticVisualMode(mode)
    mode = tostring(mode or ""):lower()
    if mode ~= "native" and mode ~= "enhanced" then
        Print("YActionBar: usage /yab visual native|enhanced|status")
        return false
    end
    local inCombat = (self.Adapter and self.Adapter.InCombat and self.Adapter:InCombat()) or (_G.InCombatLockdown and _G.InCombatLockdown())
    if inCombat then
        Print("YActionBar: visual mode can only be changed out of combat.")
        return false
    end
    if not (self.Visuals and self.Visuals.SetDiagnosticVisualMode) then
        Print("YActionBar: visual mode unavailable.")
        return false
    end
    local ok, current, writes = self.Visuals:SetDiagnosticVisualMode(mode)
    if not ok then
        Print("YActionBar: usage /yab visual native|enhanced|status")
        return false
    end
    self:Refresh("visual:" .. tostring(current))
    Print(string.format(
        "YActionBar: visual mode %s (session-only, writes=%d)",
        tostring(current),
        writes or 0
    ))
    return true
end

function YAB:EnterBindMode(source, barId)
    return self.KeybindMode and self.KeybindMode:Enter(source, barId) or false
end

function YAB:ToggleBindMode(source, barId)
    return self.KeybindMode and self.KeybindMode:Toggle(source, barId) or false
end

function YAB:CommitBindMode()
    return self.KeybindMode and self.KeybindMode:Commit() or false
end

function YAB:CancelBindMode(reason)
    return self.KeybindMode and self.KeybindMode:Cancel(reason or "cancel") or true
end

function YAB:ExitBindMode(reason)
    return self:CancelBindMode(reason or "cancel")
end

function YAB:PrintStats()
    local stats = self:GetStats()
    Print(string.format(
        "YActionBar: enabled=%s runtime=%s takeoverMode=%s specialButtonMode=%s impl=%s visualMode=%s visualExtra=%d hot=%s broadcaster=%s broadcasterActual=%s broadcasterRegistered=%d broadcasterButton=%d broadcasterAction=%d broadcasterRereg=%d broadcasterMismatch=%d broadcasterOff=%d broadcasterOn=%d broadcasterRestores=%d broadcasterFallbacks=%d nativeMode=%s specialNative=%s specialChanged=%s specialFailures=%d nativeSpecialButtons=%d reload=%s reloadReason=%s deferredOp=%s deferredMode=%s disposed=%d bars=%d visible=%d buttons=%d directList=%d directRebuilds=%d directFallbacks=%d binds=%d bindSuppress=%s bindReason=%s queue=%d native=%d stripped=%d reason=%s fullRefreshes=%d fullReason=%s usableFallbacks=%d slotFallbacks=%d assistedTicker=%s assistedInterval=%s assistedStarts=%d assistedStops=%d assistedTicks=%d assistedPolls=%d assistedChanges=%d assistedFailures=%d assistedForce=%d assistedQueues=%d assistedVisible=%d rangeReconciles=%d driverFlush=%d driverErrors=%d procIndexMode=%s actionGen=%d procCompleteGen=%d procShadow=%d procMismatch=%d procRebuilds=%d procFallbacks=%d procIndexedShows=%d procLegalEmpty=%d",
        tostring(stats.enabled),
        tostring(stats.runtime),
        tostring(stats.takeoverMode or "strong"),
        tostring(stats.specialButtonMode or YAB.SPECIAL_BUTTON_MODE or "native-reuse"),
        tostring(stats.visualImplementationType or "unknown"),
        tostring(stats.visualMode or "enhanced"),
        stats.visualExtraHidden or 0,
        tostring(stats.hotEventBackend or "unknown"),
        tostring(stats.broadcaster or stats.broadcasterMode or "unknown"),
        tostring(stats.broadcasterActual or "unknown"),
        stats.broadcasterRegistered or 0,
        stats.broadcasterButtonRegistered or 0,
        stats.broadcasterActionRegistered or 0,
        stats.broadcasterReregisters or 0,
        stats.broadcasterMismatch or 0,
        stats.broadcasterOff or 0,
        stats.broadcasterOn or 0,
        stats.broadcasterRestores or 0,
        stats.broadcasterFallbacks or 0,
        tostring(stats.nativeSuppressionMode or "none"),
        tostring(stats.specialNativeSuppressionMode or "unknown"),
        tostring(stats.specialNativeSuppressionChanged),
        stats.specialNativeSuppressionFailures or 0,
        stats.nativeSpecialButtons or 0,
        tostring(stats.reloadRequired),
        tostring(stats.reloadRequiredReason or "none"),
        tostring(stats.runtimeDeferredOperation or "none"),
        tostring(stats.runtimeDeferredMode or "none"),
        stats.nativeDisposedButtons or 0,
        stats.activeBars or 0,
        stats.visibleBars or 0,
        stats.buttonCount or 0,
        stats.directActionButtonCount or 0,
        stats.directActionListRebuilds or 0,
        stats.directActionListFallbacks or 0,
        stats.activeBindings or 0,
        tostring(stats.bindingSuppressed),
        tostring(stats.bindingSuppressReason or "none"),
        stats.queuedSecureUpdates or 0,
        stats.nativeFrames or 0,
        stats.strippedButtons or 0,
        tostring(stats.lastRefreshReason or "none"),
        stats.fullRefreshCount or 0,
        tostring(stats.lastFullRefreshReason or "none"),
        stats.usablePayloadFallbacks or 0,
        stats.slotGlobalFallbacks or 0,
        tostring(stats.assistedCombatTickerActive),
        tostring(stats.assistedCombatTickerInterval or "none"),
        stats.assistedCombatTickerStarts or 0,
        stats.assistedCombatTickerStops or 0,
        stats.assistedCombatTickerTicks or 0,
        stats.assistedCombatNextSpellPolls or 0,
        stats.assistedCombatNextSpellChanges or 0,
        stats.assistedCombatNextSpellFailures or 0,
        stats.assistedCombatForceUpdates or 0,
        stats.assistedCombatRefreshQueues or 0,
        stats.assistedCombatVisibleSlotChecks or 0,
        stats.rangeMapReconciles or 0,
        stats.driverFlushExecuted or 0,
        stats.driverFlushErrors or 0,
        tostring(stats.procIndexMode or "shadow"),
        stats.actionIdentityGeneration or 0,
        stats.procIndexCompleteGeneration or 0,
        stats.procIndexShadowComparisons or 0,
        stats.procIndexMismatches or 0,
        stats.procIndexRebuilds or 0,
        stats.procIndexFallbacks or 0,
        stats.procIndexIndexedShows or 0,
        stats.procIndexLegalEmptyShows or 0
    ))
end

function YAB:PrintCooldownDiagnostic(msg)
    if not (self.BarManager and self.BarManager.GetCooldownDiagnosticLines) then
        Print("YActionBar: cooldown diagnostic unavailable.")
        return false
    end
    local rest = tostring(msg or ""):match("^diag%s+cooldown%s*(.-)%s*$") or ""
    local barId, index, limit
    if rest ~= "" then
        barId, index, limit = rest:match("^(%S+)%s*(%S*)%s*(%S*)$")
        if index == "" then index = nil end
        if limit == "" then limit = nil end
    end
    local lines = self.BarManager:GetCooldownDiagnosticLines(barId, index, limit)
    for lineIndex = 1, #(lines or {}) do
        Print(lines[lineIndex])
    end
    return true
end

function YAB:PrintHotDiagnostics()
    local diagnostics = self.HotDiagnostics
    if not (diagnostics and diagnostics.GetLines) then
        Print("YActionBar: hot diagnostics unavailable.")
        return false
    end
    local lines = diagnostics:GetLines()
    for index = 1, #(lines or {}) do
        Print(lines[index])
    end
    if self.BarManager and self.BarManager.GetSlotIdentityDiagnosticLine then
        Print(self.BarManager:GetSlotIdentityDiagnosticLine())
    end
    return true
end

function YAB:HandleHotDiagnosticsCommand(msg)
    local diagnostics = self.HotDiagnostics
    if not diagnostics then
        Print("YActionBar: hot diagnostics unavailable.")
        return false
    end
    local rest = tostring(msg or ""):match("^diag%s+perf%s*(.-)%s*$") or ""
    if rest == "" or rest == "report" or rest == "status" then
        return self:PrintHotDiagnostics()
    end
    local sampleEvery = rest:match("^start%s*(%d*)$")
    if sampleEvery ~= nil then
        if self.BarManager and self.BarManager.ResetSlotIdentityDiagnostics then
            self.BarManager:ResetSlotIdentityDiagnostics()
        end
        local period = diagnostics:Start(sampleEvery ~= "" and tonumber(sampleEvery) or nil)
        Print(string.format("YActionBar: hot diagnostics started (sampleEvery=%d).", period or 32))
        return true
    end
    if rest == "stop" then
        diagnostics:Stop()
        Print("YActionBar: hot diagnostics stopped; counters preserved.")
        return true
    end
    if rest == "reset" then
        diagnostics:Reset()
        Print("YActionBar: hot diagnostics counters reset.")
        return true
    end
    Print("YActionBar: usage /yab diag perf start [sampleEvery]|stop|reset|report")
    return false
end

function YAB:HandleProcDiagnosticsCommand(msg)
    local diagnostics = self.HotDiagnostics
    if not diagnostics then
        Print("YActionBar: proc diagnostics unavailable.")
        return false
    end
    local rest = tostring(msg or ""):match("^diag%s+proc%s*(.-)%s*$") or ""
    if rest == "capture" then
        if not (self.BarManager and self.BarManager.runtimeActive == true) then
            Print("YActionBar: proc capture requires an active YActionBar runtime.")
            return false
        end
        diagnostics:StartProcCapture()
        Print("YActionBar: proc capture armed. Fight normally; the report will print after combat.")
        return true
    end
    if rest == "cancel" then
        diagnostics:CancelProcCapture("command")
        Print("YActionBar: proc capture cancelled.")
        return true
    end
    if rest == "report" or rest == "status" or rest == "" then
        return diagnostics:PrintProcCaptureReport()
    end
    Print("YActionBar: usage /yab diag proc capture|cancel|report")
    return false
end

function YAB:HandleSlash(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if self.QuestItems and (msg == "questtest" or msg:match("^questtest%s+")) then
        return self.QuestItems:HandleTestCommand(msg:match("^questtest%s+(.*)$") or "")
    elseif msg == "bind" then
        self:EnterBindMode("command")
    elseif msg == "stats" or msg == "status" then
        self:PrintStats()
    elseif msg == "diag cooldown" or msg:match("^diag%s+cooldown%s+") then
        self:PrintCooldownDiagnostic(msg)
    elseif msg == "diag perf" or msg:match("^diag%s+perf%s+") then
        self:HandleHotDiagnosticsCommand(msg)
    elseif msg == "diag proc" or msg:match("^diag%s+proc%s+") then
        self:HandleProcDiagnosticsCommand(msg)
    elseif msg == "visual" or msg == "visual status" then
        self:PrintDiagnosticVisualMode()
    elseif msg == "visual native" then
        self:SetDiagnosticVisualMode("native")
    elseif msg == "visual enhanced" then
        self:SetDiagnosticVisualMode("enhanced")
    else
        self:OpenSettings()
    end
end

local function RegisterSlashCommands()
    if not (YUI.Commands and YUI.Commands.Register) then return end
    YUI.Commands:Register({
        id = "yactionbar",
        productId = YUI.CoreMode == "suite" and "suite" or YAB.PRODUCT_ID,
        aliases = { "/yab", "/yactionbar" },
        handler = function(msg)
            YAB:HandleSlash(msg)
        end,
    })
    YUI.Commands:Register({
        id = "yactionbar-keybind",
        productId = YUI.CoreMode == "suite" and "suite" or YAB.PRODUCT_ID,
        aliases = { "/ykb" },
        handler = function()
            YAB:ToggleBindMode("command")
        end,
    })
end

RegisterSlashCommands()

if YUI.RegisterProduct then
    YUI:RegisterProduct({
        id = YAB.PRODUCT_ID,
        title = "Flare Action Bar · YanForge",
        titleKey = "product.title",
        titleNamespace = "YActionBar",
        shortTitle = "Flare Action Bar",
        shortTitleKey = "product.short_title",
        shortTitleNamespace = "YActionBar",
        logo = "icons\\logo_32.png",
        smallLogo = "icons\\logo_32.png",
        logoCrop = false,
        notes = "Flare Action Bar · YanForge",
        notesKey = "product.notes",
        notesNamespace = "YActionBar",
        author = "阿言",
        addonName = ADDON_NAME or YUI.AddonName,
        profileExportPrefix = "!YUI-YActionBar-v1:",
        settingsScope = "yactionbar",
        settings = {
            enabled = true,
            entry = YAB.SETTINGS_ENTRY,
            commonPages = { "core.profiles", "core.about" },
            minimapIcon = true,
        },
        db = {
            enabled = true,
            savedVariable = YUI.CoreMode == "suite" and "YUI_DB" or "YUI_YActionBar_DB",
            storageKey = YAB.STORAGE_KEY,
        },
        transfer = {
            beforeCapture = function()
                local configSets = YAB.ConfigSets
                if not (configSets and configSets.SyncReadableActivePlacements) then
                    return false, "config-sets-service-unavailable"
                end
                return configSets:SyncReadableActivePlacements(
                    "config-transfer-export",
                    YAB
                )
            end,
        },
        commands = {
            { alias = "/yab", action = "openSettings", entry = YAB.SETTINGS_ENTRY },
            { alias = "/yactionbar", action = "openSettings", entry = YAB.SETTINGS_ENTRY },
        },
    })
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = YAB.PRODUCT_ID,
        name = "YActionBar",
        product = YAB.PRODUCT_ID,
        scope = "yactionbar",
        defaultEnabled = false,
        owner = YAB,
        dependencies = { "core.db", "core.event", "core.api", "settings" },
        getEnabled = function(owner)
            return owner:IsEnabled()
        end,
        setEnabled = function(owner, enabled)
            return owner:SetEnabled(enabled)
        end,
        OnInitialize = "Initialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
        OnConfigChanged = "OnLifecycleConfigChanged",
        OnLayoutChanged = "OnLifecycleLayoutChanged",
    })
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        YAB:EnsureDB()
        YAB:RecordStartupEnabled()
    end, YAB, {
        priority = 4000,
        traceName = "YActionBar:EnsureDB",
        moduleId = "yactionbar",
        phase = "YUI_DB_READY",
    })
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        if not YAB:IsEnabled() then return end
        local conflict = YAB.ConflictGuard and YAB.ConflictGuard:Check()
        if type(conflict) ~= "table" then return end
        local wasYielded = type(YAB.externalConflict) == "table" and YAB.externalConflict.blocked == true
        if conflict.blocked == true then
            if not wasYielded or YAB.externalConflict.controller ~= conflict.controller then
                YAB:OnLifecycleEnable()
            end
        elseif wasYielded then
            YAB:OnLifecycleEnable()
        end
    end, YAB, { moduleId = "yactionbar", traceName = "YActionBar:ExternalStateChanged" })
end

if YUI.Components and YUI.Components.Register then
    YUI.Components:Register({
        id = YAB.PRODUCT_ID,
        kind = "product",
        displayName = "Flare Action Bar",
        description = "动作条替代产品，覆盖主动作条、多动作条、宠物条、姿态条、载具和额外动作按钮。",
        tags = { "美化皮肤", "实用功能" },
        settingsMode = "external",
        standalone = true,
        order = 910,
        storageKey = YAB.STORAGE_KEY,
        sourceRoot = "Products\\YActionBar",
        versions = { "mainline", "wrath", "forever" },
        getEnabled = function()
            return YAB:IsEnabled()
        end,
        setEnabled = function(_, enabled)
            if enabled then
                return YAB:Enable()
            end
            return YAB:Disable()
        end,
        openSettings = function()
            YAB:OpenSettings()
        end,
        getEffectiveState = function()
            if YAB.runtimeBlocked then
                local controller, yielded = YAB:GetYieldController()
                if yielded then
                    return {
                        effective = false,
                        kind = "yield",
                        controller = controller,
                        featureKey = "actionbar",
                        status = YAB.externalConflict and YAB.externalConflict.status,
                        tone = "warning",
                    }
                end
                return { effective = false, reason = YAB.runtimeBlockedReason, tone = "danger" }
            end
            return { effective = true }
        end,
    })
end
