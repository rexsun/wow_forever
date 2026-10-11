local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local Sharing = YHUD and YHUD.Sharing
local Settings, GUI = YUI and YUI.Settings, YUI and YUI.GUI2
if not (Sharing and Settings and GUI) then return end
local function T(key, ...)
    local text = YUI.Locale:Get('Core')['sound.share.' .. key]
    return select('#', ...) > 0 and string.format(text, ...) or text
end

function Sharing:PreviewLines(prepared)
    local labels, names, lines = {}, {}, {}
    local catalog = YHUD.ResourceCatalog
    for _, class in ipairs(catalog and catalog:GetClasses() or {}) do
        for _, spec in ipairs(catalog:GetSpecializations(class.classFile) or {}) do
            local key = class.classFile .. ':' .. tostring(spec.specID)
            labels[key] = (class.name or class.className or class.classFile) .. ' · ' .. (spec.name or key)
        end
    end
    local sets = Settings.ConfigSets
    for _, item in ipairs(sets:ListUserSets(YHUD.CONFIG_SET_PROVIDER_ID) or {}) do names['user:' .. item.id] = item.name end
    for _, item in ipairs(sets:ListBuiltins(YHUD.CONFIG_SET_PROVIDER_ID) or {}) do names['builtin:' .. item.id] = item.name end
    local hasSound = false
    for _, entry in ipairs(prepared.entries) do
        local snapshot = entry.snapshot
        if entry.id == self.MODULE_ID then
            lines[#lines + 1] = T('new_set', snapshot.report.name)
            lines[#lines + 1] = snapshot.scope.kind == 'full' and T('full_graph') or T('partial_graph', #snapshot.scope.specs)
            if snapshot.report.mode == 'none' then lines[#lines + 1] = T('reserve_effect') end
            for _, route in ipairs(snapshot.routes or {}) do
                local reference = route.before
                lines[#lines + 1] = string.format('%s：%s → %s', labels[route.spec] or route.spec,
                    names[reference.kind .. ':' .. reference.id] or reference.id, snapshot.report.name)
            end
        elseif entry.id == 'core.sound.legacy' then
            hasSound = true
            lines[#lines + 1] = T('legacy_counts', snapshot.converted, snapshot.pending, snapshot.unchanged)
            lines[#lines + 1] = T('legacy_recovery')
        elseif entry.id == 'core.sound' then
            hasSound = true
            local counts = snapshot.counts
            lines[#lines + 1] = snapshot.mode == 'replace' and T('replace_effect', counts.removed or 0)
                or T('incremental_effect')
            lines[#lines + 1] = T('counts', counts.added or 0, counts.updated or 0, counts.preserved or 0, counts.unchanged or 0)
            lines[#lines + 1] = (snapshot.scope.kind == 'profile' or snapshot.scope.includeGeneral)
                and T('has_general') or T('no_general')
        end
    end
    if not hasSound then lines[#lines + 1] = T('no_sound') end
    lines[#lines + 1] = T('preferences_kept')
    return lines
end

function Sharing:ReviewPrepared(prepared, accept, cancel, owner)
    return Settings:ShowConfigTransferReview(self:PreviewLines(prepared), accept, cancel, owner)
end

function Sharing:ShowImport(value, options)
    options = options or {}
    if type(value) == 'string' and value:find('^!YUI%-SET:') then
        local converted, code = self:ConvertLegacyString(value)
        if not converted then return nil, code end
        value = converted
    end
    Settings:ShowConfigTransferImport({ localShare = true, initialString = value,
        simpleImport = options.simpleImport,
        convertImportString = function(text)
            if text:find('^!YUI%-SET:') then return self:ConvertLegacyString(text) end
            return text
        end,
        refreshImportUI = options.simpleImport and function(owner) self:RefreshSimpleImport(owner) end or nil,
        profileName = options.name ~= '' and options.name or YUI.Locale:Get('Core')['sound.center.graphical_share'],
        layoutOwner = options.layoutOwner, onComplete = options.onComplete, onClosed = options.onClosed,
        context = { moduleIds = { self.MODULE_ID, 'core.sound', 'core.sound.legacy' }, yhudReserve = false,
            yhudImportName = options.name, soundImportMode = 'incremental' },
        configureImport = function(owner, parsed) self:ConfigureImport(owner, parsed) end,
        reviewPrepared = function(prepared, accept, cancel, owner)
            local lines = self:PreviewLines(prepared)
            if options.independentNotice then lines[#lines+1] = options.independentNotice end
            return Settings:ShowConfigTransferReview(lines, accept, cancel, owner)
        end })
    return true
end

function Sharing:ConfigureImport(owner, parsed)
    if parsed.byId and parsed.byId['core.sound.legacy'] then owner.soundShareMode:Hide() end
    local item = parsed.byId and parsed.byId[self.MODULE_ID]
    local button = owner.yhudImportSpecs
    if not button then
        button = GUI.Form:CreateButton(owner.importTargetArea, { width = 140, height = 28, text = T('assign_specs'),
            onClick = function()
                local payload = button.payload
                if not payload or not owner.options or not owner.options.context then return end
                local context = owner.options.context
                local selected, allowed, groups = {}, {}, {}
                for _, key in ipairs(context.yhudAssignmentSpecs or payload.recommendedSpecs or {}) do selected[key] = true end
                for _, key in ipairs(payload.scope and payload.scope.specs or {}) do allowed[key] = true end
                for _, group in ipairs(Settings:GetSpecSelectionGroups()) do
                    local copy = {}; for key, value in pairs(group) do copy[key] = value end
                    copy.specs = {}
                    for _, spec in ipairs(group.specs or {}) do
                        if payload.scope.kind == 'full' or allowed[spec.key] then copy.specs[#copy.specs + 1] = spec end
                    end
                    if #copy.specs > 0 then groups[#groups + 1] = copy end
                end
                local panel = Settings:OpenSpecMultiSelectDropdown(button, { owner = button, groups = groups,
                    value = selected, defaultSelected = false, panelTitle = T('assign_specs'),
                    panelWidth = math.min(620, owner:GetWidth() - 32), panelHeight = math.min(420, owner:GetHeight() - 60),
                    onChange = function(_, values)
                        if owner.options and owner.options.context == context then
                            local specs = {}; for key, enabled in pairs(values) do if enabled then specs[#specs + 1] = key end end
                            table.sort(specs); context.yhudAssignmentSpecs = specs
                            if owner.options.refreshImportUI then owner.options.refreshImportUI(owner) end
                        end
                    end })
                if panel then
                    panel:ClearAllPoints(); panel:SetPoint('CENTER', owner)
                end
            end })
        owner.yhudImportSpecs = button
        button:SetPoint('LEFT', 256, 0)
        owner:HookScript('OnHide', function()
            Settings:CloseSpecMultiSelectDropdown(button, 'owner-hidden'); button:Hide(); button.payload = nil
        end)
    end
    local payload = item and item.status == 'ready' and item.rawPayload or nil
    if type(payload) ~= 'table' or type(payload.scope) ~= 'table' or type(payload.recommendedSpecs) ~= 'table'
        or (payload.scope.kind ~= 'full' and (payload.scope.kind ~= 'specs' or type(payload.scope.specs) ~= 'table')) then payload = nil end
    button.payload = payload
    button:SetShown(button.payload ~= nil)
    owner.reserveShare:SetDisabled(payload == nil, true)
    owner.reserveShare:SetWidth(240); owner.soundShareMode:SetWidth(250)
    owner.options.context.yhudAssignmentSpecs = nil
    if owner.options.simpleImport then self:ConfigureSimpleImport(owner, payload) end
end

function Sharing:RefreshSimpleImport(owner)
    local panel = owner.yhudSimpleImport
    if not panel or not panel:IsShown() or not owner.parsed then return end
    local context = owner.options.context
    local specs = context.yhudAssignmentSpecs or {}
    local reserve = context.yhudReserve == true
    owner.scopeInvalid = not panel.payload or (not reserve and #specs == 0)
    panel.specs:SetDisabled(reserve)
    panel.soundMode:SetShown(owner.selection['core.sound'] == true)
    local names = {}
    for _, group in ipairs(Settings:GetSpecSelectionGroups()) do
        for _, spec in ipairs(group.specs) do names[spec.key] = spec.name end
    end
    local selected = {}
    for _, key in ipairs(specs) do selected[#selected + 1] = names[key] or key end
    panel.effect:SetText(reserve and T('simple_saved')
        or (#selected > 0 and T('simple_used', table.concat(selected, '、')) or T('simple_choose')))
    owner.count:SetText('')
    owner.primary:SetDisabled(owner.scopeInvalid or owner.parseState ~= 'ready'
        or owner.importState == 'preparing' or owner.importState == 'review' or owner.importState == 'committing'
        or (InCombatLockdown and InCombatLockdown()))
end

function Sharing:ConfigureSimpleImport(owner, payload)
    local panel = owner.yhudSimpleImport
    if not panel then
        panel = GUI:CreateFrame(owner.moduleArea, { allPoints = true })
        owner.yhudSimpleImport = panel
        local nameLabel = GUI:CreateText(panel, T('simple_name'), 'font.size.md', 'color.text.primary')
        nameLabel:SetPoint('TOPLEFT', 16, -16)
        panel.name = GUI.Form:CreateEditBox(panel, { width = 400, height = 28 })
        panel.name:SetPoint('TOPLEFT', 16, -42)
        panel.name:SetMaxLetters(128)
        panel.name:SetScript('OnTextChanged', function(edit) owner.options.context.yhudImportName = edit:GetText() end)
        panel.reserve = GUI.Form:CreateCheckbox(panel, { width = 280, height = 28, text = T('simple_reserve'),
            set = function(value)
                owner.options.context.yhudReserve = value == true
                Sharing:RefreshSimpleImport(owner)
            end })
        panel.reserve:SetPoint('TOPLEFT', 16, -86)
        panel.specs = GUI.Form:CreateButton(panel, { width = 150, height = 28, text = T('simple_specs'),
            onClick = function() owner.yhudImportSpecs:Click() end })
        panel.specs:SetPoint('TOPRIGHT', -16, -86)
        panel.effect = GUI:CreateText(panel, '', 'font.size.md', 'color.text.primary')
        panel.effect:SetPoint('TOPLEFT', 16, -126); panel.effect:SetPoint('TOPRIGHT', -16, -126)
        panel.effect:SetWordWrap(true)
        panel.sound = GUI.Form:CreateCheckbox(panel, { width = 280, height = 28, text = T('simple_sound'),
            set = function(value)
                for _, id in ipairs({'core.sound', 'core.sound.legacy'}) do
                    local item = owner.parsed.byId[id]
                    owner.selection[id] = value == true and item ~= nil and item.status == 'ready'
                end
                Sharing:RefreshSimpleImport(owner)
            end })
        panel.sound:SetPoint('TOPLEFT', 16, -180)
        panel.soundMode = GUI.Form:CreateDropdown(panel, { width = 260, height = 28,
            options = { { text = T('incremental'), value = 'incremental' }, { text = T('replace'), value = 'replace' } },
            set = function(value) owner.options.context.soundImportMode = value end })
        panel.soundMode:SetPoint('TOPLEFT', 16, -220)
        owner:HookScript('OnHide', function()
            panel.name:ClearFocus(); panel:Hide(); panel.payload = nil
        end)
    end
    panel.payload = payload
    owner.importTargetArea:Hide(); owner.scroll:Hide()
    owner.moduleArea:Show(); panel:Show()
    local name = payload and payload.item.name or T('simple_name')
    owner.summaryText:SetText(payload and payload.scope.kind == 'full'
        and T('simple_received_full', name)
        or T('simple_received_partial', name, #(payload and payload.scope.specs or {})))
    panel.name:SetText(owner.options.context.yhudImportName or (payload and payload.item.name) or '')
    panel.reserve:SetChecked(false, true)
    owner.options.context.yhudReserve = false
    local current = Settings.ConfigSets:GetCurrentSpecializationKey()
    local allowed = payload and payload.scope.kind == 'full'
    for _, key in ipairs(payload and payload.scope.specs or {}) do if key == current then allowed = true end end
    owner.options.context.yhudAssignmentSpecs = current and allowed and {current} or {}
    local hasSound, readySound = false, false
    for _, id in ipairs({'core.sound', 'core.sound.legacy'}) do
        local item = owner.parsed.byId[id]
        local ready = item ~= nil and item.status == 'ready'
        owner.selection[id] = ready
        hasSound = hasSound or item ~= nil
        readySound = readySound or ready
    end
    panel.sound:SetShown(hasSound); panel.sound:SetDisabled(not readySound, true)
    panel.sound:SetChecked(readySound, true); panel.soundMode:SetValue('incremental', true)
    owner.options.context.soundImportMode = 'incremental'
    owner.selection[self.MODULE_ID] = payload ~= nil
    Sharing:RefreshSimpleImport(owner)
end

function Sharing:ConfigureExport(owner, setId, specs)
    local bar = owner.yhudExportScope
    if not bar then
        bar = GUI:CreatePanel(owner, { width = owner:GetWidth() - 44, height = 48,
            surface = 'color.surface.sunken', border = 'color.border.subtle' })
        owner.yhudExportScope = bar; bar:SetPoint('TOPLEFT', 22, -58)
        bar.full = GUI.Form:CreateCheckbox(bar, { width = 270, height = 28, text = T('full_scope'),
            set = function(value) if value then bar:UpdateScope(nil) else bar:ChooseSpecs() end end })
        bar.full:SetPoint('LEFT', 12, 0)
        bar.choose = GUI.Form:CreateButton(bar, { width = 300, height = 28, text = T('choose_specs'),
            onClick = function() bar:ChooseSpecs() end })
        bar.choose:SetPoint('RIGHT', -12, 0)
        function bar:UpdateScope(selected)
            local payload = Sharing:Capture(self.setId, selected)
            owner.options.context.yhudShare = payload
            owner.options.context.soundSpecs = payload and (selected or payload.recommendedSpecs) or {}
            owner.scopeInvalid = payload == nil
            self.full:SetChecked(selected == nil, true)
            self.choose:SetText(selected and T('selected_specs', #selected) or T('choose_specs'))
            local anySelected = false
            for _, enabled in pairs(owner.selection or {}) do if enabled then anySelected = true; break end end
            owner.primary:SetDisabled(owner.scopeInvalid or not anySelected)
            if selected then self.specs = selected end
        end
        function bar:ChooseSpecs()
            self.full:SetChecked(owner.options.context.yhudShare and owner.options.context.yhudShare.scope.kind == 'full', true)
            self.pendingSpecs = nil
            local selected = {}
            for _, spec in ipairs(self.specs or {}) do selected[spec] = true end
            local panel = Settings:OpenSpecMultiSelectDropdown(self.choose, { owner = self, value = selected,
                defaultSelected = false, panelTitle = T('choose_specs'),
                panelWidth = math.min(620, owner:GetWidth() - 32), panelHeight = math.min(420, owner:GetHeight() - 60),
                onChange = function(_, values)
                    local result = {}; for key, enabled in pairs(values) do if enabled then result[#result + 1] = key end end
                    table.sort(result); self.pendingSpecs = result
                end,
                onClose = function()
                    local result = self.pendingSpecs; self.pendingSpecs = nil
                    if result and owner:IsShown() and owner.options and owner.options.context then self:UpdateScope(result) end
                end })
            if panel then
                panel:ClearAllPoints(); panel:SetPoint('CENTER', owner)
            end
        end
        owner:HookScript('OnHide', function()
            Settings:CloseSpecMultiSelectDropdown(bar, 'owner-hidden'); bar:Hide(); bar.setId, bar.specs = nil, nil
        end)
    end
    bar.setId, bar.specs = setId, specs or owner.options.context.yhudShare.recommendedSpecs
    bar:UpdateScope(specs); bar:Show()
end
