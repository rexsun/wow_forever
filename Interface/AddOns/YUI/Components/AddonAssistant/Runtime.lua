local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end
local M, C = A.Model, A.Client
local R = { metrics = {}, expanded = {}, sortKey = "default", descending = false }
A.Runtime = R

function R:Notify(mode)
    if mode ~= false and A.View then A.View:Refresh(mode == "state") end
end

function R:Error(key, detail)
    self.error = A.L[key] or key
    if detail then self.error = self.error .. ": " .. detail end
    self:Notify()
    if not (A.View and A.View.window and A.View.window:IsShown()) then
        print(A.L.title .. ": " .. self.error)
    end
    return false
end

function R:Init()
    if self.db then return true end
    local global, character = YUI.DB:GetGlobal(A.product), C.Character()
    if not global or not character then return false end
    local records, enabled = C.Scan()
    if not records then return self:Error(enabled) end
    global.AddonAssistant = global.AddonAssistant or {}
    local root = global.AddonAssistant
    root[A.flavor] = root[A.flavor] or { version = 3, profiles = {}, rules = {}, exceptions = {}, seen = {}, tags = {}, chars = {}, sequence = 0, automatic = false }
    self.db = root[A.flavor]
    local db = self.db
    for _, key in ipairs({"profiles", "rules", "exceptions", "seen", "tags", "chars"}) do db[key] = db[key] or {} end
    -- Keep old fine-grained bindings recoverable while adopting five scene entries.
    if (db.version or 1) < 2 then
        db.legacySceneRules = M.Copy(db.rules)
        db.legacyExceptions = M.Copy(db.exceptions)
        db.rules.dungeon = db.rules.dungeon or db.rules.mythic
        db.rules.world = db.rules.world or db.rules.delve or db.rules.scenario
        for _, old in ipairs(db.legacyExceptions) do
            local scene = old.scene == "mythic" and "dungeon" or (old.scene == "delve" or old.scene == "scenario") and "world" or old.scene
            if scene ~= old.scene then
                local migrated = M.Copy(old); migrated.scene = scene
                if not M.RuleDuplicate(db.exceptions, migrated) then db.exceptions[#db.exceptions+1] = migrated end
            end
        end
        local visible = {world=true,dungeon=true,raid=true,battleground=true,arena=true}
        for i=#db.exceptions,1,-1 do if not visible[db.exceptions[i].scene] then table.remove(db.exceptions,i) end end
        db.version = 2
    end
    db.chars[character] = db.chars[character] or { locks = {} }
    self.char = db.chars[character]
    if self.char.skin~="native" and self.char.skin~="dark" then self.char.skin="native" end
    self.char.locks = self.char.locks or {}
    self.records, self.baseline = records, enabled
    self.byName, self.reverse = M.Index(records)
    self.rows = M.Rows(records, self.byName)
    if not self.char.selfLocksInitialized then
        for _, name in ipairs({A.addonName, YUI.AddonName or A.addonName}) do
            if self.byName[name] then self.char.locks[name] = true end
        end
        self.char.selfLocksInitialized = true
    end
    if not db.initialized then
        for _, record in ipairs(records) do db.seen[record.name] = true end
        db.initialized = true
    end
    for _, record in ipairs(records) do
        if db.tags[record.name] then record.tags = M.Copy(db.tags[record.name]) end
    end
    if not next(db.profiles) then
        db.sequence = 1
        db.profiles.p1 = { name = A.L.daily, addons = M.Copy(enabled) }
        self.char.active = "p1"
    end
    self.editing = db.profiles[self.char.active] and self.char.active or self:ProfileOptions()[1].value
    self.draft = M.Copy(enabled)
    self.editBaseline = M.Copy(enabled)
    self.selected = self.editing
    if (db.version or 1) < 3 then
        db.legacySceneRulesV2, db.legacyExceptionsV2 = M.Copy(db.rules), M.Copy(db.exceptions)
        db.rules.default = db.rules.default or db.rules.world
        db.rules.world = nil
        for _, rule in ipairs(db.exceptions) do if rule.scene == "world" then rule.scene = "default" end end
        db.version = 3
    end
    if db.automatic == nil then db.automatic = false end
    if not db.rules.default or not db.profiles[db.rules.default.profile] then db.rules.default = {profile=self.editing,mode="prompt"} end
    for scene, rule in pairs(db.rules) do
        rule.mode="prompt"
        if scene ~= "default" and not db.profiles[rule.profile] then db.rules[scene] = nil end
    end
    for index=#db.exceptions,1,-1 do
        local rule=db.exceptions[index]
        if not db.rules[rule.scene] or not db.profiles[rule.profile] then
            db.retiredExceptions=db.retiredExceptions or {}; db.retiredExceptions[#db.retiredExceptions+1]=M.Copy(rule)
            table.remove(db.exceptions,index)
        end
    end
    -- Manual overrides protect this UI session, never the next reload.
    self.manualContext, self.manualPending = nil, nil
    self.char.manualContext, self.char.manualPending, self.char.paused = nil, nil, nil
    if not db.profiles[self.editing].groups then self:RememberGroups() end
    self:Resort()
    return true
end

function R:ProfileOptions(keep, status)
    local options = {}
    if keep then options[1] = { value = "", text = A.L.keep } end
    local sorted = {}
    for id, profile in pairs(self.db.profiles) do sorted[#sorted + 1] = { value = id, text = profile.name } end
    table.sort(sorted, function(a, b) return a.text == b.text and a.value < b.value or a.text < b.text end)
    for _, entry in ipairs(sorted) do
        entry.text = string.format("%s (%d)", entry.text, M.Total(self.db.profiles[entry.value].addons))
        if status then
            if entry.value==self.editing then entry.description=self:Unsaved() and A.L.modified or (self.reloadRequired or not M.Same(self.draft,self.baseline)) and A.L.pendingReload or A.L.applied
            elseif entry.value==self.char.active then entry.description=self.reloadRequired and A.L.pendingReload or A.L.applied end
        end
        options[#options + 1] = entry
    end
    return options
end

function R:Dirty() return self.draft and not M.Same(self.draft, self.editBaseline) end
function R:Unsaved()
    local profile = self.db and self.db.profiles[self.editing]
    return profile and not M.Same(self.draft, M.Selection(profile.addons, self.char.locks, self.byName))
end

function R:Resort(key)
    if key then
        if self.sortKey == key then
            if self.descending then self.sortKey, self.descending = "default", false else self.descending = true end
        else self.sortKey, self.descending = key, false end
    end
    self.order = M.Sort(self.rows, self.sortKey, self.descending, self.draft, self.baseline, self.char.locks, self.metrics, self.db.seen)
    self:Notify()
end

function R:CancelCountdown()
    self.remaining = nil
    if A.View then A.View:StopPrompt() end
end

function R:Edit(selection, quiet)
    self.draft = selection
    self.error = nil
    self:HoldManualSelection()
    self.pending = nil
    self:CancelCountdown()
    if not quiet then self:Notify() end
end

function R:Toggle(names, enabled, preserveGroups, cascade)
    local selected
    if enabled then
        local requested = {}
        for _, name in ipairs(names) do requested[name] = true end
        local enabledSelection, missing
        if cascade then enabledSelection, missing = M.Resolve(requested, self.char.locks, self.byName)
        else enabledSelection, missing = M.Selection(requested, self.char.locks, self.byName) end
        if next(missing) then return self:Error("missing", table.concat(self:Names(missing), ", ")) end
        selected = M.Copy(self.draft)
        for name in pairs(enabledSelection) do selected[name] = true end
    else
        -- Only explicit group actions cascade to other addon selections.
        selected = M.Disable(self.draft, names, self.char.locks, self.byName, self.reverse, cascade == true)
        if not selected then return self:Error("lockedHint") end
    end
    self:Edit(selected)
    if not preserveGroups then self:RememberGroups(names) end
    return true
end

function R:RememberGroups(changed)
    local profile = self.db.profiles[self.editing]
    if not profile then return end
    profile.groups = profile.groups or {}
    local queue = {}; for _, row in ipairs(self.rows) do queue[#queue+1] = row end
    local cursor = 1
    while cursor <= #queue do
        local row = queue[cursor]; cursor = cursor + 1
        for _, child in ipairs(row.children) do queue[#queue+1] = child end
        if #row.children > 0 then
            local subset = {}
            local affected = not changed
            for _, name in ipairs(row.members) do
                if self.draft[name] then subset[name] = true end
                for _, modified in ipairs(changed or {}) do if modified == name then affected = true end end
            end
            if affected and next(subset) then profile.groups[row.name] = subset end
        end
    end
end

function R:Group(row, action, enableParent)
    local profile = self.db.profiles[self.editing]
    profile.groups = profile.groups or {}
    if action == "all" then return self:Toggle(row.members, true, true, true) end
    local protected = M.Resolve({}, self.char.locks, self.byName)
    local removable = {}
    for _, name in ipairs(row.members) do if not protected[name] then removable[#removable+1] = name end end
    if action == "none" then return self:Toggle(removable, false, true, true) end
    local subset = profile.groups[row.name] or profile.addons
    local requested = M.Copy(self.draft)
    -- First remove the family and dependent selections; restore only the remembered subset.
    requested = M.Disable(requested, removable, self.char.locks, self.byName, self.reverse)
    local any
    for _, name in ipairs(row.members) do if subset[name] then requested[name]=true; any=true end end
    if enableParent or not any then requested[row.name] = true end
    local selected, missing = M.Selection(requested, self.char.locks, self.byName)
    if next(missing) then return self:Error("missing",table.concat(self:Names(missing),", ")) end
    self:Edit(selected)
    return true
end

function R:Names(set)
    local names = {}; for name in pairs(set) do names[#names + 1] = self.byName[name] and self.byName[name].title or name end
    table.sort(names); return names
end

function R:Bulk(enabled)
    local selected = {}
    if enabled then
        for _, record in ipairs(self.records) do
            local resolved, missing = M.Resolve({[record.name] = true}, nil, self.byName)
            if not next(missing) then for name in pairs(resolved) do selected[name] = true end end
        end
    end
    selected = M.Resolve(selected, self.char.locks, self.byName)
    self:Edit(selected)
end

function R:Lock(names)
    local any = false
    for _, name in ipairs(names) do if self.char.locks[name] then any = true end end
    for _, name in ipairs(names) do
        self.char.locks[name] = not any and self.draft[name] or nil
    end
    self.draft = M.Selection(self.draft, self.char.locks, self.byName)
    self:Evaluate(false)
    self:Notify()
end

function R:FindProfileByName(name)
    if not self.active or not self.db then return nil, "unavailable" end
    if type(name) ~= "string" or name == "" then return nil, "profileMissing" end
    local found
    for id, profile in pairs(self.db.profiles) do
        if type(profile) == "table" and profile.name == name then
            if found then return nil, "profileDuplicate" end
            if type(profile.addons) ~= "table" then return nil, "profileInvalid" end
            for addon, enabled in pairs(profile.addons) do
                if type(addon) ~= "string" or addon == "" or type(enabled) ~= "boolean" then
                    return nil, "profileInvalid"
                end
            end
            found = id
        end
    end
    return found, not found and "profileMissing" or nil
end

function R:GetActiveProfileName()
    if not self.active or not self.db or not self.char then return nil end
    local profile = self.db.profiles[self.char.active]
    return type(profile) == "table" and profile.name or nil
end

-- Apply a saved selection for an enclosing workflow; that workflow owns reload.
function R:ApplyProfile(id)
    if not self.active or not self.db then return false, "unavailable" end
    local profile = self.db.profiles[id]
    if type(profile) ~= "table" or type(profile.addons) ~= "table" then return false, "profileMissing" end
    local found, reason = self:FindProfileByName(profile.name)
    if found ~= id then return false, reason or "profileMissing" end
    if not C.Safe() then return false, "unsafe" end
    local target, missing = M.Selection(profile.addons, self.char.locks, self.byName)
    if next(missing) then return false, "missing" end
    local ok, previous = C.Apply(target, self.records)
    if not ok then return false, previous end
    self.char.active = id
    if not M.Same(previous, target) then
        self.char.previous = previous
        self.reloadRequired = true
    end
    self.editing, self.selected = id, id
    self.baseline, self.draft, self.editBaseline = M.Copy(target), M.Copy(target), M.Copy(target)
    self:HoldManualSelection()
    self.pending = nil
    self:CancelCountdown()
    self:Notify()
    return true
end

function R:SelectProfile(id)
    if not self.db.profiles[id] then return false end
    local selection, missing = M.Selection(self.db.profiles[id].addons, self.char.locks, self.byName)
    if next(missing) then return self:Error("missing", table.concat(self:Names(missing), ", ")) end
    self.editing = id
    self.selected = id
    self:Edit(selection, true)
    self.editBaseline = M.Copy(selection)
    local profile = self.db.profiles[id]
    if not profile.groups then self:RememberGroups() end
    if M.Same(selection,self.baseline) then self.char.active=id end
    self:Notify()
    return true
end

function R:SaveProfile(name, create)
    local id = self.editing
    if name then
        local normalized, err = M.ValidName(name, self.db.profiles, not create and id or nil)
        if not normalized then return self:Error(err) end
        name = normalized
    end
    if create then
        self.db.sequence = (self.db.sequence or 0) + 1
        id = "p" .. self.db.sequence
        while self.db.profiles[id] do self.db.sequence = self.db.sequence + 1; id = "p" .. self.db.sequence end
    end
    local previous = self.db.profiles[id]
    local addons = M.Copy(self.draft)
    -- Saving an existing profile retains missing entries; a new profile uses current choices only.
    if previous then
        for key, value in pairs(previous.addons) do if not self.byName[key] then addons[key] = value end end
    end
    self.db.profiles[id] = { name = name or previous.name, addons = addons,
        groups = M.Copy((previous or self.db.profiles[self.editing] or {}).groups or {}) }
    self.editing, self.editBaseline, self.error = id, M.Copy(self.draft), nil
    self.selected = id
    if M.Same(self.draft,self.baseline) then self.char.active=id end
    self:Evaluate(false); self:Notify()
    return true
end

function R:DeleteProfile(id)
    local count = 0; for _ in pairs(self.db.profiles) do count = count + 1 end
    if count <= 1 then return self:Error("lastProfile") end
    self.db.profiles[id] = nil
    local fallback = self:ProfileOptions()[1].value
    for _, rule in pairs(self.db.rules) do if rule.profile == id then rule.profile = fallback end end
    for _, rule in ipairs(self.db.exceptions) do if rule.profile == id then rule.profile = fallback end end
    for _, character in pairs(self.db.chars) do if character.active == id then character.active = nil end end
    self.editing = self:ProfileOptions()[1].value
    self.selected = self.editing
    self:SelectProfile(self.editing)
end

function R:SetRule(scene, profile, mode)
    local valid=false; for _, key in ipairs(A.SceneOrder) do valid=valid or key==scene end
    if not valid or not self.db.profiles[profile] or (mode and mode~="prompt" and mode~="auto") then return self:Error("invalidRule") end
    self.db.rules[scene] = { profile = profile, mode = "prompt" }
    self.skipped = nil; self:CancelCountdown(); self:Evaluate(false); self:Notify()
    return true
end

function R:SceneOptions(available)
    local options={}
    for _, scene in ipairs(A.SceneOrder) do
        if (available and scene~="default" and not self.db.rules[scene]) or (not available and self.db.rules[scene]) then
            options[#options+1]={value=scene,text=A.L["scene."..scene],atlas=A.SceneAtlas[scene]}
        end
    end
    return options
end

function R:RemoveRule(scene, confirmed)
    if scene=="default" or not self.db.rules[scene] then return false end
    for _, rule in ipairs(self.db.exceptions) do if rule.scene==scene and not confirmed then return self:Error("confirmRemoveScene") end end
    self.db.rules[scene]=nil
    for index=#self.db.exceptions,1,-1 do if self.db.exceptions[index].scene==scene then table.remove(self.db.exceptions,index) end end
    self.skipped=nil; self:CancelCountdown(); self:Evaluate(false); self:Notify(); return true
end

function R:CheckException(index, rule)
    local result=M.CheckException(self.db.exceptions,rule,index,self.db.rules,self.db.profiles)
    if result.error then return result end
    local classValid, specValid=false,rule.spec==0
    for _, class in ipairs(YUI.API.Unit.GetClassInfos()) do classValid=classValid or class.classID==rule.class end
    if classValid and not specValid then
        for _, spec in ipairs(YUI.API.Talent.GetClassConfigurationSpecializations(rule.class)) do specValid=specValid or spec.specID==rule.spec end
    end
    if not classValid or not specValid then result.error="invalidRule" end
    return result
end

function R:SetException(index, rule, confirmed)
    if index and not self.db.exceptions[index] then return self:Error("invalidRule") end
    local review=self:CheckException(index,rule)
    if review.error then return self:Error(review.error) end
    if #review.merge>0 and not confirmed then return self:Error("confirmMergeRules") end
    local merged={}; for _, entry in ipairs(review.merge) do merged[entry]=true end
    local nextRules={}
    for i, existing in ipairs(self.db.exceptions) do
        if i==index then nextRules[#nextRules+1]={class=rule.class,spec=rule.spec,scene=rule.scene,profile=rule.profile}
        elseif not merged[i] then nextRules[#nextRules+1]=existing end
    end
    if not index then nextRules[#nextRules+1]={class=rule.class,spec=rule.spec,scene=rule.scene,profile=rule.profile} end
    self.db.exceptions=nextRules
    self.skipped = nil; self:CancelCountdown(); self:Evaluate(false); self:Notify()
    return true
end

function R:RemoveException(index)
    if not self.db.exceptions[index] then return false end
    table.remove(self.db.exceptions,index); self.skipped=nil; self:CancelCountdown(); self:Evaluate(false); self:Notify(); return true
end

function R:SetAutomatic(enabled)
    self.db.automatic=enabled==true
    self.manualContext,self.manualPending=nil,nil; self.skipped=nil; self.char.lastAttempt=nil
    self:UpdateEvents()
    self:CancelCountdown(); self:Evaluate(false); self:Notify()
end

function R:HoldManualSelection()
    local context=C.Context()
    if context then
        self.manualContext=M.RuleContext(context,M.Rule(self.db.rules,self.db.exceptions,context)); self.manualPending=nil
    else self.manualContext=nil; self.manualPending=true end
end

function R:Skip()
    self.skipped = self.pending and self.pending.key
    self.pending = nil; self:CancelCountdown(); self:Notify()
end

function R:Resume()
    self.manualContext, self.skipped, self.char.lastAttempt = nil, nil, nil
    self:Evaluate(false); self:Notify()
end

function R:Interacting()
    return A.View and A.View.window and A.View.window:IsShown()
end

function R:Evaluate(mode)
    self:CancelEvaluation()
    if not self.active or not self.db then return end
    if not self.db.automatic or A.GameMenu:HasPriorityManager() then
        self.pending = nil; self:CancelCountdown(); self:Notify(mode); return
    end
    local context = C.Context()
    if not context then self.pending = nil; self:CancelCountdown(); self:Notify(mode); return end
    local rule = M.Rule(self.db.rules, self.db.exceptions, context)
    local stamp=M.RuleContext(context,rule)
    if self.manualPending then self.manualContext=stamp; self.manualPending=nil end
    if self.ruleContextKey ~= stamp then self.skipped, self.char.lastAttempt = nil, nil end
    self.ruleContextKey=stamp
    self.contextKey = context.key
    if self.manualContext and self.manualContext~=stamp then self.manualContext=nil end
    local profile = rule and self.db.profiles[rule.profile]
    -- A rule selects a named profile, not an exact plugin set to enforce after every reload.
    -- Retain manual deviations while that profile is active, even when edited outside this UI.
    local blocked = self.manualContext==stamp or self.skipped==stamp
        or (rule and self.char.active==rule.profile)
    if blocked or not profile then self.pending = nil; self:CancelCountdown(); self:Notify(mode); return end
    local target, missing = M.Selection(profile.addons, self.char.locks, self.byName)
    local current = C.Read(self.records)
    if not current or next(missing) or M.Same(target, current) then
        if current and not next(missing) and M.Same(target,current) then
            self.char.active=rule.profile
            if not self:Interacting() then
                self.editing,self.selected=rule.profile,rule.profile
                self.baseline,self.draft,self.editBaseline=M.Copy(current),M.Copy(current),M.Copy(current)
            end
        end
        self.pending = nil; self:CancelCountdown(); self:Notify(mode); return
    end
    local key = stamp
    if self.pending and (self.pending.key~=key or not M.Same(self.pending.target,target)) then
        self:CancelCountdown(); self.pending=nil
    end
    self.pending = self.pending or {key=key,context=context.key,profile=rule.profile,target=target,mode="prompt"}
    self.pending.context=context.key
    if not C.Safe() or self:Interacting() then self:CancelCountdown()
    elseif not self.remaining and self.char.lastAttempt~=key then self:Countdown() end
    self:Notify(mode)
end

function R:Countdown()
    if not self.pending then return end
    self.remaining=60
    A.View:StartPrompt(self.pending)
end

function R:Apply(automatic, expected)
    if not C.Safe() then return self:Error("unsafe") end
    if self.reloadRequired and not automatic and M.Same(self.draft, self.baseline) then
        local ok = pcall(C.Reload)
        if not ok then return self:Error("reloadFailed") end
        self.reloadRequired = nil
        return true
    end
    local pending = self.pending
    if automatic then
        if A.GameMenu:HasPriorityManager() then self:Evaluate(); return false end
        if expected and (expected~=pending or not self.remaining or self.remaining<=0) then return false end
        local context = C.Context()
        if not pending or not context or context.key ~= pending.context or not self.db.automatic or self.manualContext==pending.key then self:Evaluate(); return false end
        local rule = M.Rule(self.db.rules, self.db.exceptions, context)
        if not rule or M.RuleContext(context,rule)~=pending.key then self:Evaluate(); return false end
    end
    local target, missing = M.Selection(automatic and pending.target or self.draft, self.char.locks, self.byName)
    if next(missing) then return self:Error("missing", table.concat(self:Names(missing), ", ")) end
    local ok, previous = C.Apply(target, self.records)
    if not ok then
        if automatic then self.char.lastAttempt = pending.key end
        self:CancelCountdown(); return self:Error(previous)
    end
    self.char.previous = previous
    local id = automatic and pending.profile or self.editing
    local saved = self.db.profiles[id]
    self.char.active = saved and id or nil
    if not automatic then self:HoldManualSelection() end
    self.char.lastAttempt = automatic and pending.key or nil
    self.baseline, self.draft, self.editBaseline = M.Copy(target), M.Copy(target), M.Copy(target)
    self.editing,self.selected=id,id
    -- Keep the clicked confirmation visible until the direct reload call returns.
    local reloaded = pcall(C.Reload)
    self.pending = nil; self:CancelCountdown()
    if not reloaded then
        self.reloadRequired = true
        return self:Error("reloadFailed")
    end
    self.reloadRequired = nil
    self:Notify()
    return true
end

function R:StartMetrics()
    local view=A.View
    local monitoring=view.monitor and view.monitor:IsVisible()
    local listing=view.window and view.window:IsVisible() and view.tab=="addons"
    if not self.active or not (listing or monitoring) then self:StopMetrics(); return false end
    local mode=listing and "both" or self.char.monitorMetric=="memory" and "memory" or "cpu"
    if self.metricTimer then
        if self.metricMode==mode then return false end
        self:StopMetrics()
    end
    self.metricMode=mode
    self.metrics, self.metricContext = C.Metrics(self.records,mode)
    if listing then view:RefreshMetrics() end
    if monitoring then view:RefreshMonitor() end
    self.metricTimer = C_Timer.NewTimer(2, function() self.metricTimer = nil; self:StartMetrics() end)
    return true
end

function R:StopMetrics()
    if self.metricTimer then self.metricTimer:Cancel(); self.metricTimer = nil end
    self.metricMode=nil
end

function R:CancelEvaluation()
    if self.evaluationTimer then self.evaluationTimer:Cancel(); self.evaluationTimer=nil end
end

function R:QueueEvaluation()
    if self.evaluationTimer then return end
    self.evaluationTimer=C_Timer.NewTimer(0,function()
        self.evaluationTimer=nil
        self:Evaluate("state")
    end)
end

local function onContextEvent()
    R:Evaluate("state")
end

local function onTalentEvent(event,unit)
    if event=="PLAYER_SPECIALIZATION_CHANGED" and unit and unit~="player" then return end
    YUI.API.Talent.ClearCurrentSpecializationInfoCache()
    R:QueueEvaluation()
end

function R:UpdateEvents()
    local view=A.View
    local watching=self.active and (self.db.automatic or (view.window and view.window:IsVisible())) or false
    if self.watching==watching then return end
    self.watching=watching
    YUI.Event:OffOwner(self)
    self:CancelEvaluation()
    if not watching then return end
    -- Identity may have changed while no consumer needed rule events.
    YUI.API.Talent.ClearCurrentSpecializationInfoCache()
    local events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
        "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "ENCOUNTER_END", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PVP_MATCH_STATE_CHANGED" }
    for _, event in ipairs(events) do YUI.Event:On(event,onContextEvent,self) end
    local talentEvents = { "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED" }
    if A.flavor == "forever" then talentEvents[#talentEvents+1] = "TRAIT_CONFIG_UPDATED" end
    for _, event in ipairs(talentEvents) do YUI.Event:On(event,onTalentEvent,self) end
end

function R:Enable()
    if self.active then return end
    if not self:Init() then return end
    self.active = true
    A.GameMenu:Enable()
    self:UpdateEvents()
    self:Evaluate()
end

function R:Disable()
    self.active = false
    A.GameMenu:Disable()
    self:UpdateEvents()
    self:CancelCountdown(); self:StopMetrics()
    self.pending = nil
    if A.View then A.View:Hide() end
end
