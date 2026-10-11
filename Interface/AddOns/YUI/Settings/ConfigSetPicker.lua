local YUI = _G.YUI
if not YUI then return end

local S = YUI.Settings
local GUI2 = YUI.GUI2
if not S or not GUI2 or not GUI2.Form then return end

S.ConfigSetPicker = S.ConfigSetPicker or {}
local Picker = S.ConfigSetPicker
if Picker._loaded then return end
Picker._loaded = true

local Animation = YUI.Animation
local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local table_concat = table.concat
local tostring = tostring
local type = type

local VALID_FRAME_STRATA = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

local PUBLIC_ERROR_CODES = {
    apply_failed = true,
    busy = true,
    combat = true,
    db_not_ready = true,
    duplicate_name = true,
    incompatible_schema = true,
    immutable_builtin = true,
    invalid_description = true,
    invalid_import_string = true,
    invalid_name = true,
    invalid_payload = true,
    invalid_provider = true,
    invalid_scope = true,
    invalid_storage = true,
    no_undo = true,
    owner_mismatch = true,
    profile_changed = true,
    provider_error = true,
    provider_not_found = true,
    recapture_required = true,
    refresh_failed = true,
    rollback_failed = true,
    set_limit = true,
    set_not_found = true,
    serialization_unavailable = true,
    decode_failed = true,
    default_required = true,
    enabled_required = true,
    unsupported_format = true,
    wrong_provider = true,
}

local function GetManager()
    return S.ConfigSets
end

local function Text(key, fallback)
    local manager = GetManager()
    if manager and manager.GetText then
        local value = manager:GetText(Picker.providerId, key, fallback)
        if value ~= nil and value ~= "" then
            return value
        end
    end
    return fallback or key
end

local function FormatText(key, ...)
    local template = Text(key)
    local ok, result = pcall(string.format, template, ...)
    if ok then
        return result
    end
    return template
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function CopyArray(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for index = 1, #source do
        result[index] = source[index]
    end
    return result
end

local function ResolveItemName(item)
    if not item then return "" end
    local key = item.nameKey or item.titleKey
    local fallback = item.name or item.title or item.id
    if key then
        return Text(key, fallback)
    end
    return fallback or ""
end

local function ResolveItemDescription(item)
    if not item then return "" end
    local key = item.descriptionKey
    if key then
        return Text(key, item.description)
    end
    return item.description or ""
end

local function ResolveScopeLabel(scope)
    if not scope then return "" end
    if scope.labelKey then
        return Text(scope.labelKey, scope.label or scope.id)
    end
    return scope.label or scope.id or ""
end

local function CreateButton(parent, options)
    return GUI2.Form:CreateButton(parent, options)
end

local function CreateUnifiedModalMask(parent, frameLevelOffset)
    local mask = GUI2:CreateFrame(parent, {
        allPoints = true,
        mouse = true,
        hidden = true,
    })
    mask:SetFrameLevel(parent:GetFrameLevel() + (frameLevelOffset or 20))

    local shade = GUI2:CreateTexture(mask, nil, "BACKGROUND")
    GUI2:SetTexturePaintKey(shade, "color.overlay.shadow")
    shade:SetAllPoints()
    mask.gui2ModalShade = shade
    return mask
end

local function SetTextureSource(texture, source)
    if not texture then return false end
    texture:SetTexture(nil)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetAlpha(1)

    if type(source) ~= "string" or source == "" then
        return false
    end

    if source:sub(1, 6) == "atlas:" and texture.SetAtlas then
        local atlas = source:sub(7)
        if atlas ~= "" then
            local ok, applied = pcall(texture.SetAtlas, texture, atlas, false)
            return ok == true and applied ~= false
        end
        return false
    end

    return texture:SetTexture(source) ~= false
end

local function ReleaseTexture(texture)
    if not texture then return end
    texture:SetTexture(nil)
    texture:SetTexCoord(0, 1, 0, 1)
end

function Picker:SetStatus(message, tone)
    if not self.statusText then return end
    self.statusText:SetText(message or "")
    GUI2:SetTextColorKey(self.statusText, tone or "color.text.muted")
end

local function ErrorText(code)
    if code == "combat-lockdown" then
        code = "combat"
    elseif not PUBLIC_ERROR_CODES[code] then
        code = "provider_error"
    end
    local key = "settings.config_sets.error." .. tostring(code or "provider_error")
    local fallback = code == "default_required"
        and "必须保留一个默认方案，才能修改其他方案的适用专精。"
        or (code == "enabled_required" and "至少需要保留一个已启用的方案。")
        or nil
    return Text(key, fallback)
end

function Picker:SetError(code)
    self:SetStatus(ErrorText(code), "color.state.error")
end

function Picker:ReleaseZoomTexture()
    if not self.zoomTexture then return end
    ReleaseTexture(self.zoomTexture)
    self.zoomBoundPreview = nil
end

function Picker:StopZoomAnimation()
    if Animation and Animation.StopOwner and self.zoomMask then
        Animation:StopOwner(self.zoomMask, false)
    end
end

function Picker:ShowZoomMask()
    local mask = self.zoomMask
    if not mask then return end

    if not self:PrepareUnifiedModal(mask) then return end
    self:StopZoomAnimation()
    mask:SetAlpha(0)
    mask:Show()
    local handle = GUI2:PlayControlMotion(mask, "config-set-zoom-fade", {
        owner = mask,
        key = "config-set-zoom-fade",
        durationKey = "medium",
        from = 0,
        to = 1,
        onUpdate = function(value)
            if Picker.zoomMask and Picker.zoomMask:IsShown() then
                Picker.zoomMask:SetAlpha(value)
            end
        end,
        onFinished = function()
            if Picker.zoomMask and Picker.zoomMask:IsShown() then
                Picker.zoomMask:SetAlpha(1)
            end
        end,
    })
    if not handle or handle.noop then
        mask:SetAlpha(1)
    end
end

function Picker:OpenZoom(item)
    if not self.zoomMask and self.frame then
        local frame = self.frame
        self:BuildZoomOverlay(frame)
        self:RefreshUnifiedFrameLevels()
    end
    if not item or not self.zoomMask then return end
    local source = self:GetPreviewTexture(item)
    if not source then return end

    self:SelectUnifiedItem(item)
    self:ReleaseZoomTexture()
    if not SetTextureSource(self.zoomTexture, source) then
        return
    end

    self.zoomBoundPreview = source
    if self.zoomPanel then
        if self.previewZoomEnabled then
            self.zoomPanel:SetSize(512, 288)
        else
            local preview = type(item.preview) == "table" and item.preview or {}
            self.zoomPanel:SetSize(
                tonumber(preview.width) or 256,
                tonumber(preview.height) or 144
            )
        end
    end
    self.zoomTexture:Show()
    self:ShowZoomMask()
end

function Picker:CloseZoom()
    if not self.zoomMask then return end
    self:StopZoomAnimation()
    self.zoomMask:Hide()
    self.zoomMask:SetAlpha(1)
    if self.activeUnifiedModal == self.zoomMask then
        self.activeUnifiedModal = nil
    end
    self:ReleaseZoomTexture()
    self:ResetUnifiedRowHoverStates()
end

function Picker:OpenEditorSourcePreview()
    local dialog = self.editorDialog
    if self.editorMode ~= "create"
        or not self.editorSourceId
        or not dialog
        or not dialog.previewMask
    then
        return
    end
    for _, item in ipairs(self.builtins or {}) do
        if item.id == self.editorSourceId then
            local source = self:GetPreviewTexture(item)
            if not source then return end
            ReleaseTexture(dialog.previewTexture)
            if not SetTextureSource(dialog.previewTexture, source) then return end
            local preview = type(item.preview) == "table" and item.preview or {}
            dialog.previewPanel:SetSize(
                self.previewZoomEnabled and 512 or tonumber(preview.width) or 256,
                self.previewZoomEnabled and 288 or tonumber(preview.height) or 144
            )
            self.editorPreviewOpen = true
            dialog.previewTexture:Show()
            dialog.previewMask:Show()
            return
        end
    end
end

function Picker:CloseEditorSourcePreview()
    local dialog = self.editorDialog
    if dialog and dialog.previewMask then
        dialog.previewMask:Hide()
        dialog.previewTexture:Hide()
        ReleaseTexture(dialog.previewTexture)
    end
    self.editorPreviewOpen = nil
end

function Picker:GetPreviewTexture(item)
    if not item then return nil end
    if type(item.previewTexture) == "string" and item.previewTexture ~= "" then
        return item.previewTexture
    end
    if type(item.preview) == "table" and type(item.preview.path) == "string" then
        local manager = GetManager()
        if manager and manager.GetPreviewTexture then
            local source = manager:GetPreviewTexture(self.providerId, item.id)
            if type(source) == "string" and source ~= "" then
                return source
            end
        end
        return item.preview.path
    end
    return nil
end

function Picker:RefreshImportButton()
    local dialog = self.importDialog
    if not dialog then return end
    dialog.importButton:SetDisabled(Trim(dialog.importEdit:GetText()) == "")
end

function Picker:OpenImportDialog()
    local yhud = YUI.YHUD
    if yhud and self.providerId == yhud.CONFIG_SET_PROVIDER_ID and yhud.Sharing then
        return yhud.Sharing:ShowImport(nil, { layoutOwner = self.panel, simpleImport = true })
    end
    if not self.importDialog and self.frame then
        local frame = self.frame
        self:BuildImportDialog(frame)
        self:RefreshUnifiedFrameLevels()
        self:RefreshStaticText()
    end
    local dialog = self.importDialog
    if not dialog then return end
    if GUI2.CloseDropdown then GUI2:CloseDropdown(false) end
    dialog.statusText:SetText("")
    dialog.importEdit:SetValue("", true)
    dialog.nameEdit:SetValue("", true)
    self:RefreshImportButton()
    self:ShowUnifiedModal(dialog.mask)
    dialog.importEdit:SetFocus()
end

function Picker:CloseImportDialog()
    local dialog = self.importDialog
    if not dialog then return end
    if dialog.importEdit.ClearFocus then dialog.importEdit:ClearFocus() end
    if dialog.nameEdit.ClearFocus then dialog.nameEdit:ClearFocus() end
    dialog.statusText:SetText("")
    dialog.importEdit:SetValue("", true)
    dialog.nameEdit:SetValue("", true)
    self:HideUnifiedModal(dialog.mask)
end

function Picker:ImportUserSet()
    local dialog = self.importDialog
    local manager = GetManager()
    if not dialog or not manager then return end
    local yhud = YUI.YHUD
    local importValue = Trim(dialog.importEdit:GetText())
    if yhud and self.providerId == yhud.CONFIG_SET_PROVIDER_ID and yhud.Sharing
        and yhud.Sharing.ShowImport and (importValue:find('^!YUI%-CFG:') or importValue:find('^!YUI%-SET:')) then
        local ok, code = yhud.Sharing:ShowImport(importValue, {
            layoutOwner = self.panel,
            name = Trim(dialog.nameEdit:GetText()),
        })
        if ok then self:CloseImportDialog()
        else dialog.statusText:SetText(ErrorText(code)); GUI2:SetTextColorKey(dialog.statusText, 'color.state.error') end
        return
    end
    local providerId = self.providerId
    local sessionToken = self.sessionToken

    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:ImportUserSet(
        providerId,
        dialog.importEdit:GetText(),
        {
            name = dialog.nameEdit:GetText(),
            configurationMode = self.configurationMode,
        }
    )
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog(self.selectedKind, self.selectedId) end
        dialog.statusText:SetText(ErrorText(code))
        GUI2:SetTextColorKey(dialog.statusText, "color.state.error")
        return
    end

    self:CloseImportDialog()
    self:RefreshCatalog("user", result.id)
    self:SetStatus(
        FormatText("settings.config_sets.imported", ResolveItemName(result)),
        "color.state.success"
    )
end

function Picker:BuildZoomOverlay(parent)
    local mask = CreateUnifiedModalMask(parent, 30)
    mask:SetScript("OnMouseUp", function()
        Picker:CloseZoom()
    end)
    self.zoomMask = mask

    local previewPanel = GUI2:CreatePanel(mask, {
        width = 512,
        height = 288,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    previewPanel:SetPoint("CENTER")
    previewPanel:SetFrameLevel(mask:GetFrameLevel() + 2)
    previewPanel:EnableMouse(true)
    previewPanel:SetScript("OnMouseUp", function() end)
    self.zoomPanel = previewPanel

    local texture = GUI2:CreateTexture(previewPanel, { layer = "ARTWORK" })
    texture:SetAllPoints(previewPanel)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Hide()
    self.zoomTexture = texture

    local closeButton = GUI2:CreateCloseButton(previewPanel, function()
        Picker:CloseZoom()
    end)
    closeButton:SetPoint("TOPRIGHT", -10, -10)
    closeButton:SetFrameLevel(previewPanel:GetFrameLevel() + 3)
    self.zoomCloseButton = closeButton
end

function Picker:BuildImportDialog(parent)
    local mask = CreateUnifiedModalMask(parent, 30)

    local panel = GUI2:CreatePanel(mask, {
        width = 560,
        height = 280,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetPoint("CENTER")
    panel:SetFrameLevel(mask:GetFrameLevel() + 2)

    local dialog = {
        mask = mask,
        panel = panel,
    }
    self.importDialog = dialog

    local titleText = GUI2:CreateText(panel, Text("settings.config_sets.import_title"), "font.size.title", "color.text.heading", "LEFT")
    titleText:SetPoint("TOPLEFT", 24, -20)
    titleText:SetPoint("TOPRIGHT", -52, -20)
    dialog.titleText = titleText

    local closeButton = GUI2:CreateCloseButton(panel, function()
        Picker:CloseImportDialog()
    end)
    closeButton:SetPoint("TOPRIGHT", -18, -18)

    local hintText = GUI2:CreateText(panel, Text("settings.config_sets.import_hint"), "font.size.sm", "color.text.secondary", "LEFT")
    hintText:SetPoint("TOPLEFT", 30, -60)
    hintText:SetPoint("TOPRIGHT", -30, -60)
    hintText:SetWordWrap(true)
    dialog.hintText = hintText

    local stringLabel = GUI2:CreateText(panel, Text("settings.config_sets.import_string"), "font.size.sm", "color.text.secondary", "LEFT")
    stringLabel:SetPoint("TOPLEFT", 30, -91)
    dialog.stringLabel = stringLabel

    local importEdit = GUI2.Form:CreateEditBox(panel, {
        width = 500,
        height = 28,
        onChange = function()
            Picker:RefreshImportButton()
        end,
    })
    importEdit:SetPoint("TOPLEFT", 30, -111)
    importEdit:SetScript("OnEscapePressed", function()
        Picker:CloseImportDialog()
    end)
    importEdit:SetScript("OnEnterPressed", function()
        if not dialog.importButton.gui2Disabled then
            Picker:ImportUserSet()
        end
    end)
    dialog.importEdit = importEdit

    local nameLabel = GUI2:CreateText(panel, Text("settings.config_sets.import_name"), "font.size.sm", "color.text.secondary", "LEFT")
    nameLabel:SetPoint("TOPLEFT", 30, -151)
    nameLabel:SetPoint("TOPRIGHT", -30, -151)
    dialog.nameLabel = nameLabel

    local nameEdit = GUI2.Form:CreateEditBox(panel, {
        width = 500,
        height = 28,
    })
    nameEdit:SetPoint("TOPLEFT", 30, -171)
    nameEdit:SetScript("OnEscapePressed", function()
        Picker:CloseImportDialog()
    end)
    nameEdit:SetScript("OnEnterPressed", function()
        if not dialog.importButton.gui2Disabled then
            Picker:ImportUserSet()
        end
    end)
    dialog.nameEdit = nameEdit

    local statusText = GUI2:CreateText(panel, "", "font.size.sm", "color.state.error", "LEFT")
    statusText:SetPoint("BOTTOMLEFT", 30, 66)
    statusText:SetPoint("BOTTOMRIGHT", -30, 66)
    statusText:SetWordWrap(false)
    dialog.statusText = statusText

    local cancelButton = CreateButton(panel, {
        width = 108,
        height = 28,
        text = Text("settings.config_sets.cancel"),
        tone = "default",
        onClick = function()
            Picker:CloseImportDialog()
        end,
    })
    cancelButton:SetPoint("BOTTOMRIGHT", -148, 24)
    dialog.cancelButton = cancelButton

    local importButton = CreateButton(panel, {
        width = 108,
        height = 28,
        text = Text("settings.config_sets.import_apply"),
        tone = "accent",
        onClick = function()
            Picker:ImportUserSet()
        end,
    })
    importButton:SetPoint("BOTTOMRIGHT", -30, 24)
    importButton:SetDisabled(true)
    dialog.importButton = importButton
end

function Picker:HookOwnerFrame(ownerFrame)
    if not ownerFrame or not ownerFrame.HookScript then return end
    self.hookedOwnerFrames = self.hookedOwnerFrames or setmetatable({}, { __mode = "k" })
    if self.hookedOwnerFrames[ownerFrame] then return end
    self.hookedOwnerFrames[ownerFrame] = true
    ownerFrame:HookScript("OnHide", function(hiddenFrame)
        if Picker.ownerFrame == hiddenFrame then
            Picker:Close()
        end
    end)
end

-- Unified list presentation. Public Open/Close/IsOpen/Refresh remains the
-- stable boundary used by settings modules.
local UNIFIED_PANEL_WIDTH = 820
local UNIFIED_PANEL_HEIGHT = 540
local UNIFIED_LIST_WIDTH = 772
local UNIFIED_LIST_HEIGHT = 330
local UNIFIED_ROW_HEIGHT = 64
local UNIFIED_ROW_GAP = 2
local UNIFIED_ROW_STEP = UNIFIED_ROW_HEIGHT + UNIFIED_ROW_GAP
local UNIFIED_ROW_POOL_SIZE = 7
local UNIFIED_VISIBLE_ROW_UNITS = 5
local UNIFIED_SECTION_ROW_HEIGHT = 28
local UNIFIED_SECTION_GAP = 8
local UNIFIED_NAME_WIDTH = 320
local UNIFIED_ASSIGNMENT_WIDTH = 296
local UNIFIED_ACTION_SIZE = 26
local UNIFIED_ACTION_GAP = 6
local UNIFIED_NAME_INSET = 12
local UNIFIED_TAG_GAP = 6
local UNIFIED_YUI_TAG_WIDTH = 34
local UNIFIED_CURRENT_TAG_WIDTH = 78
local UNIFIED_ASSIGNMENT_ICON_SIZE = 18
local UNIFIED_ASSIGNMENT_ICON_GAP = 4
local UNIFIED_ASSIGNMENT_ICON_LIMIT = 9
local UNIFIED_ROW_DETAILS_GAP = 3
local UNIFIED_ROW_MOTION_KEY = "config-set-row-details"
local UNIFIED_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local UNIFIED_SPEC_CARD_WIDTH = 214
local UNIFIED_SPEC_CARD_GAP = 8
local UNIFIED_SPEC_CHECK_WIDTH = 96
local UNIFIED_EDITOR_WIDTH = 560
local UNIFIED_EDITOR_HEIGHT = 500

local function UnifiedReferenceKey(reference)
    if type(reference) ~= "table"
        or (reference.kind ~= "builtin" and reference.kind ~= "user")
        or type(reference.id) ~= "string"
        or reference.id == "" then
        return nil
    end
    return reference.kind .. ":" .. reference.id
end

local function UnifiedReference(value)
    if type(value) ~= "table" then return nil end
    if type(value.reference) == "table" then
        value = value.reference
    end
    if value.kind ~= "builtin" and value.kind ~= "user" then return nil end
    if type(value.id) ~= "string" or value.id == "" then return nil end
    return { kind = value.kind, id = value.id }
end

local function UnifiedReferencesEqual(left, right)
    return UnifiedReferenceKey(left) ~= nil
        and UnifiedReferenceKey(left) == UnifiedReferenceKey(right)
end

local function UnifiedCopyReference(reference)
    reference = UnifiedReference(reference)
    if not reference then return nil end
    return { kind = reference.kind, id = reference.id }
end

local function UnifiedCopySpecKeys(source)
    local result = {}
    local seen = {}
    for _, key in ipairs(source or {}) do
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            result[#result + 1] = key
        end
    end
    return result
end

local function UnifiedAssignment(value)
    if type(value) == "table" and type(value.assignment) == "table" then
        value = value.assignment
    end
    if type(value) ~= "table" then
        return { mode = "none", specKeys = {} }
    end
    local mode = value.mode
    if mode == "selected" then mode = "specs" end
    local specKeys = UnifiedCopySpecKeys(value.specKeys or value.specs)
    if mode ~= "default" and mode ~= "all" and mode ~= "specs" then
        mode = "none"
    end
    if mode == "specs" and #specKeys == 0 then
        mode = "none"
    end
    if mode ~= "specs" and mode ~= "all" then
        specKeys = {}
    end
    return {
        mode = mode,
        specKeys = specKeys,
        enabled = value.enabled ~= false,
    }
end

local function UnifiedLookupAssignment(snapshot, reference)
    if type(snapshot) ~= "table" then return nil end
    local key = UnifiedReferenceKey(reference)
    if not key then return nil end

    local pipeKey = reference.kind .. "|" .. reference.id
    local byReference = snapshot.byReference or snapshot.assignments
    if type(byReference) == "table" then
        local value = byReference[key] or byReference[pipeKey]
        if value == nil
            and type(byReference[reference.kind]) == "table" then
            value = byReference[reference.kind][reference.id]
        end
        if value ~= nil then return value end
        for _, candidate in ipairs(byReference) do
            if type(candidate) == "table"
                and UnifiedReferencesEqual(candidate.reference or candidate, reference) then
                return candidate.assignment or candidate
            end
        end
    end

    local hasServiceSnapshot = snapshot.enabled ~= nil
        or snapshot.default ~= nil
        or snapshot.bySpec ~= nil
        or snapshot.bySpecialization ~= nil
    if hasServiceSnapshot then
        if UnifiedReferencesEqual(UnifiedReference(snapshot.default), reference) then
            return { mode = "default", specKeys = {} }
        end
        local specKeys = {}
        local bySpecialization = snapshot.bySpec or snapshot.bySpecialization
        for specKey, assigned in pairs(
            type(bySpecialization) == "table" and bySpecialization or {}
        ) do
            if type(specKey) == "string"
                and UnifiedReferencesEqual(UnifiedReference(assigned), reference)
            then
                specKeys[#specKeys + 1] = specKey
            end
        end
        if #specKeys > 0 then
            table.sort(specKeys)
            return { mode = "specs", specKeys = specKeys }
        end
        return { mode = "none", specKeys = {} }
    end

    byReference = snapshot
    if type(byReference) == "table" then
        local value = byReference[key] or byReference[pipeKey]
        if value == nil
            and type(byReference[reference.kind]) == "table" then
            value = byReference[reference.kind][reference.id]
        end
        if value ~= nil then return value end
        for _, candidate in ipairs(byReference) do
            if type(candidate) == "table"
                and UnifiedReferencesEqual(candidate.reference or candidate, reference) then
                return candidate.assignment or candidate
            end
        end
    end
    return nil
end

local function UnifiedCoreIcon(name)
    local Assets = YUI.Assets
    if Assets and type(Assets.Core) == "function" then
        return Assets:Core("gui2\\icons\\settings\\" .. tostring(name) .. ".png")
    end
    return "Interface\\AddOns\\"
        .. tostring(YUI.AddonName or "YUI")
        .. "\\Media\\Core\\gui2\\icons\\settings\\"
        .. tostring(name)
        .. ".png"
end

local function UnifiedFormat(key, fallback, ...)
    local template = Text(key, fallback)
    local ok, value = pcall(string.format, template, ...)
    return ok and value or template
end

local function UnifiedUtf8Prefix(value, maxChars)
    value = tostring(value or "")
    local index = 1
    local count = 0
    local endIndex = 0
    while index <= #value and count < maxChars do
        local byte = string.byte(value, index)
        local width = 1
        if byte and byte >= 240 then
            width = 4
        elseif byte and byte >= 224 then
            width = 3
        elseif byte and byte >= 192 then
            width = 2
        end
        if index + width - 1 > #value then break end
        endIndex = index + width - 1
        index = endIndex + 1
        count = count + 1
    end
    return value:sub(1, endIndex), index <= #value
end

local function UnifiedUtf8Length(value)
    value = tostring(value or "")
    local index = 1
    local count = 0
    while index <= #value do
        local byte = string.byte(value, index)
        local width = 1
        if byte and byte >= 240 then
            width = 4
        elseif byte and byte >= 224 then
            width = 3
        elseif byte and byte >= 192 then
            width = 2
        end
        if index + width - 1 > #value then break end
        index = index + width
        count = count + 1
    end
    return count
end

local function UnifiedFontStringIsTruncated(fontString)
    if not fontString then return false end
    if type(fontString.IsTruncated) == "function" then
        local ok, truncated = pcall(fontString.IsTruncated, fontString)
        if ok and truncated == true then return true end
    end

    local width = type(fontString.GetWidth) == "function" and fontString:GetWidth() or 0
    if width <= 0 then return false end
    local measure = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    if type(measure) ~= "function" then return false end
    local ok, textWidth = pcall(measure, fontString)
    return ok and type(textWidth) == "number" and textWidth > width + 0.5
end

local function UnifiedFitFontString(fontString, value)
    value = tostring(value or "")
    fontString:SetText(value)
    if value == "" or not UnifiedFontStringIsTruncated(fontString) then
        return value, false
    end

    local low = 0
    local high = UnifiedUtf8Length(value)
    local best = ""
    while low <= high do
        local middle = math_floor((low + high) / 2)
        local prefix = UnifiedUtf8Prefix(value, middle)
        local candidate = prefix .. "…"
        fontString:SetText(candidate)
        if UnifiedFontStringIsTruncated(fontString) then
            high = middle - 1
        else
            best = candidate
            low = middle + 1
        end
    end
    if best == "" then best = "…" end
    fontString:SetText(best)
    return best, true
end

local function UnifiedMeasureFontStringWidth(fontString)
    if not fontString then return nil end
    local measure = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    if type(measure) ~= "function" then return nil end
    local ok, width = pcall(measure, fontString)
    if not ok or type(width) ~= "number" then return nil end
    return width
end

local function UnifiedGetAssignment(manager, providerId, snapshot, reference)
    local value = UnifiedLookupAssignment(snapshot, reference)
    if value == nil
        and manager
        and type(manager.GetAssignment) == "function"
    then
        value = manager:GetAssignment(providerId, reference)
    end
    return UnifiedAssignment(value)
end

local function UnifiedResolveSpecializationGroups(manager, providerId)
    local options = {
        armorLabels = {
            cloth = Text("settings.config_sets.armor.cloth", "布甲"),
            leather = Text("settings.config_sets.armor.leather", "皮甲"),
            mail = Text("settings.config_sets.armor.mail", "锁甲"),
            plate = Text("settings.config_sets.armor.plate", "板甲"),
        },
    }
    local groups
    if manager and type(manager.GetSpecializationGroups) == "function" then
        groups = manager:GetSpecializationGroups(providerId, options)
    end
    if type(groups) ~= "table" and S.GetSpecSelectionGroups then
        groups = S:GetSpecSelectionGroups(options)
    end
    return type(groups) == "table" and groups or {}
end

local function UnifiedFindSpec(groups, specKey)
    if type(specKey) ~= "string" then return nil end
    for _, group in ipairs(groups or {}) do
        for _, spec in ipairs(group.specs or {}) do
            if spec.key == specKey then return spec end
        end
    end
    return nil
end

local function UnifiedSpecLabel(groups, specKey, includeClass)
    local spec = UnifiedFindSpec(groups, specKey)
    if not spec then return specKey or "" end
    local specName = spec.displayName or spec.name or tostring(spec.specID or specKey)
    if includeClass and spec.classInfo and spec.classInfo.name then
        return tostring(spec.classInfo.name) .. " · " .. tostring(specName)
    end
    return specName
end

local function UnifiedBuildSpecDisplayIndex(groups)
    local order = {}
    local byKey = {}
    for _, group in ipairs(groups or {}) do
        for _, spec in ipairs(group.specs or {}) do
            if type(spec.key) == "string" and spec.key ~= "" and not byKey[spec.key] then
                byKey[spec.key] = spec
                order[#order + 1] = spec
            end
        end
    end
    return order, byKey
end

local function UnifiedOrderAssignmentSpecs(specOrder, specByKey, specKeys)
    local selected = {}
    local ordered = {}
    for _, specKey in ipairs(specKeys or {}) do
        if type(specKey) == "string" and specKey ~= "" then
            selected[specKey] = true
        end
    end
    for _, spec in ipairs(specOrder or {}) do
        if selected[spec.key] then
            ordered[#ordered + 1] = spec
            selected[spec.key] = nil
        end
    end
    for _, specKey in ipairs(specKeys or {}) do
        if selected[specKey] then
            ordered[#ordered + 1] = {
                key = specKey,
                displayName = specKey,
                icon = UNIFIED_FALLBACK_ICON,
            }
            selected[specKey] = nil
        end
    end
    return ordered
end

local function UnifiedApplySpecializationIcon(texture, spec)
    if not texture then return false end

    local nativeIcon = spec and (spec.nativeIcon or spec.icon)
    local Icons = YUI.API and YUI.API.Icons
    if Icons
        and type(Icons.GetScopedSpecIcon) == "function"
        and type(Icons.ApplyIcon) == "function"
    then
        local iconData = Icons.GetScopedSpecIcon(
            spec and spec.specID,
            nativeIcon,
            "settings"
        )
        if iconData and Icons.ApplyIcon(texture, iconData) then
            texture:SetVertexColor(1, 1, 1, 1)
            texture:SetAlpha(1)
            return true
        end
    end

    GUI2:SetIconTexture(texture, nativeIcon, UNIFIED_FALLBACK_ICON)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetAlpha(1)
    return nativeIcon ~= nil
end

local function UnifiedSelectedSpecMap(specKeys)
    local selected = {}
    for _, specKey in ipairs(specKeys or {}) do
        if type(specKey) == "string" and specKey ~= "" then
            selected[specKey] = true
        end
    end
    return selected
end

local function UnifiedCollectSelectedSpecKeys(specOrder, selected)
    local result = {}
    local remaining = {}
    for specKey, isSelected in pairs(type(selected) == "table" and selected or {}) do
        if isSelected == true and type(specKey) == "string" and specKey ~= "" then
            remaining[specKey] = true
        end
    end
    for _, spec in ipairs(specOrder or {}) do
        if spec and remaining[spec.key] then
            result[#result + 1] = spec.key
            remaining[spec.key] = nil
        end
    end
    local unknown = {}
    for specKey in pairs(remaining) do
        unknown[#unknown + 1] = specKey
    end
    table.sort(unknown)
    for _, specKey in ipairs(unknown) do
        result[#result + 1] = specKey
    end
    return result
end

local function UnifiedSetShown(frame, shown)
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end

local function UnifiedSetBorderShown(frame, shown)
    local borders = frame and (frame.gui2Borders or frame.borders)
    if type(borders) ~= "table" then return end
    for _, border in pairs(borders) do
        local borderType = type(border)
        if (borderType == "table" or borderType == "userdata")
            and type(border.Show) == "function"
            and type(border.Hide) == "function"
        then
            UnifiedSetShown(border, shown)
        end
    end
end

function Picker:ShowUnifiedRowContentTooltip(row, owner)
    if not GameTooltip
        or not row
        or not row.contentTextWasTruncated
        or not row.fullContentText
        or row.fullContentText == ""
    then
        return
    end
    GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.fullContentText, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

function Picker:HideUnifiedRowContentTooltip(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) then
        YUI.HideGameTooltip()
    end
end

function Picker:HandleUnifiedRowPointer(row, entered, tooltipOwner)
    if not row or not row.item then return end
    local physicallyOver = entered == true
    if row.IsMouseOver then
        physicallyOver = row:IsMouseOver() == true
    end

    if self.suppressUnifiedHoverUntilMouseMove then
        if not physicallyOver then
            self.suppressUnifiedHoverUntilMouseMove = nil
        end
        self:RefreshUnifiedRowVisual(row, false, false)
        if tooltipOwner then self:HideUnifiedRowContentTooltip(tooltipOwner) end
        return
    end

    local hovered = not self.activeUnifiedModal and physicallyOver
    self:RefreshUnifiedRowVisual(row, hovered, true)
    if tooltipOwner then
        if hovered then
            self:ShowUnifiedRowContentTooltip(row, tooltipOwner)
        else
            self:HideUnifiedRowContentTooltip(tooltipOwner)
        end
    end
end

function Picker:ResetUnifiedRowHoverStates()
    for _, row in ipairs(self.unifiedRows or {}) do
        if row.item then
            self:RefreshUnifiedRowVisual(row, false, false)
        end
    end
    if GameTooltip and GameTooltip.Hide then
        YUI.HideGameTooltip()
    end
end

function Picker:IsMouseOverUnifiedRow()
    for _, row in ipairs(self.unifiedRows or {}) do
        if row.item and row.IsMouseOver and row:IsMouseOver() then
            return true
        end
    end
    return false
end

function Picker:PrepareUnifiedModal(mask)
    if not mask then return false end
    if GUI2.CloseDropdown then GUI2:CloseDropdown(false) end
    if self.unifiedCursorAnchor then self.unifiedCursorAnchor:Hide() end
    if S.CloseSpecMultiSelectDropdown then
        S:CloseSpecMultiSelectDropdown(self)
    end
    local modalMasks = {}
    local function AddModalMask(peerMask)
        if peerMask then modalMasks[#modalMasks + 1] = peerMask end
    end
    AddModalMask(self.zoomMask)
    AddModalMask(self.assignmentDialog and self.assignmentDialog.mask)
    AddModalMask(self.specializationPreviewDialog and self.specializationPreviewDialog.mask)
    AddModalMask(self.editorDialog and self.editorDialog.mask)
    AddModalMask(self.importDialog and self.importDialog.mask)
    for _, peerMask in ipairs(modalMasks) do
        if peerMask and peerMask ~= mask then
            if peerMask == self.zoomMask then
                self:StopZoomAnimation()
                self:ReleaseZoomTexture()
            end
            if self.importDialog and peerMask == self.importDialog.mask then
                if self.importDialog.importEdit.ClearFocus then
                    self.importDialog.importEdit:ClearFocus()
                end
                if self.importDialog.nameEdit.ClearFocus then
                    self.importDialog.nameEdit:ClearFocus()
                end
            end
            if self.editorDialog and peerMask == self.editorDialog.mask then
                if self.editorDialog.nameEdit.ClearFocus then
                    self.editorDialog.nameEdit:ClearFocus()
                end
                if self.editorDialog.descriptionEdit.ClearFocus then
                    self.editorDialog.descriptionEdit:ClearFocus()
                end
            end
            peerMask:Hide()
            peerMask:SetAlpha(1)
        end
    end
    self.activeUnifiedModal = mask
    self.suppressUnifiedHoverUntilMouseMove = true
    self:ResetUnifiedRowHoverStates()
    return true
end

function Picker:ShowUnifiedModal(mask)
    if not self:PrepareUnifiedModal(mask) then return end
    mask:SetAlpha(1)
    mask:Show()
end

function Picker:HideUnifiedModal(mask)
    if mask then
        mask:Hide()
        mask:SetAlpha(1)
    end
    if self.activeUnifiedModal == mask then
        self.activeUnifiedModal = nil
    end
    self.suppressUnifiedHoverUntilMouseMove = self:IsMouseOverUnifiedRow() or nil
    self:ResetUnifiedRowHoverStates()
end

function Picker:GetUnifiedItem(reference)
    reference = UnifiedReference(reference)
    local key = UnifiedReferenceKey(reference)
    if not key then return nil end
    return self.itemByReference and self.itemByReference[key] or nil
end

function Picker:GetSelectedItem()
    return self:GetUnifiedItem({
        kind = self.selectedKind,
        id = self.selectedId,
    })
end

function Picker:GetContentScopeSummary(item)
    local labels = {}
    for _, scopeId in ipairs(item and item.scopeIds or {}) do
        labels[#labels + 1] = ResolveScopeLabel(self.scopeById and self.scopeById[scopeId])
    end
    return table_concat(labels, Text("settings.config_sets.scope_separator", "、"))
end

function Picker:GetAssignmentLabel(assignment)
    assignment = UnifiedAssignment(assignment)
    if assignment.mode == "all" then
        return Text("settings.config_sets.assignment.all", "全部")
    end
    if assignment.mode == "default" then
        return Text("settings.config_sets.assignment.default", "默认")
    end
    if assignment.mode == "none" then
        return Text("settings.config_sets.assignment.none", "无")
    end
    if #assignment.specKeys == 1 then
        return UnifiedSpecLabel(self.specializationGroups, assignment.specKeys[1], false)
    end
    return UnifiedFormat(
        "settings.config_sets.assignment.spec_count",
        "%d 个专精",
        #assignment.specKeys
    )
end

function Picker:RefreshUnifiedAssignmentReference(reference, assignment)
    reference = UnifiedCopyReference(reference)
    assignment = UnifiedAssignment(assignment)
    if not reference then return end

    local item = self:GetUnifiedItem(reference)
    if item then
        item.assignment = assignment
    end
    for _, row in ipairs(self.unifiedRows or {}) do
        if row.item and UnifiedReferencesEqual(row.item, reference) then
            row.item.assignment = assignment
            self:RefreshUnifiedAssignmentVisual(row, assignment)
        end
    end
end

function Picker:RefreshAssignmentsFromSnapshot(snapshot, changeDetail)
    if type(snapshot) ~= "table" then return false end
    self.assignmentSnapshot = snapshot
    self.assignmentRoutingEnabled = snapshot.enabled == true
    self.bySpecialization = {}
    local rawBySpecialization = snapshot.bySpec or snapshot.bySpecialization
    for specKey, reference in pairs(
        type(rawBySpecialization) == "table" and rawBySpecialization or {}
    ) do
        local normalized = UnifiedReference(reference)
        if type(specKey) == "string" and normalized then
            self.bySpecialization[specKey] = normalized
        end
    end

    for _, item in ipairs(self.allItems or {}) do
        item.assignment = UnifiedAssignment(
            UnifiedLookupAssignment(snapshot, item)
        )
        item.enabled = not self.editableUserSets
            or item.assignment.enabled ~= false
    end
    self.hasSpecializationAssignments = next(self.bySpecialization) ~= nil
    self.currentSpecializationReference = nil
    if self.assignmentRoutingEnabled then
        self.currentSpecializationReference = UnifiedReference(
            self.currentSpecializationKey
                and self.bySpecialization[self.currentSpecializationKey]
                or snapshot.default
        )
    end
    if type(changeDetail) == "table" and changeDetail.runtimeChanged == true then
        self.activeReference = UnifiedReference(changeDetail.currentReference)
    end

    self:RebuildUnifiedVisibleItems(self.selectedKind, self.selectedId)
    self:RefreshUnifiedRows()
    self:RefreshFooter()
    return true
end

function Picker:SetUnifiedAssignment(item, mode, specKeys)
    local manager = GetManager()
    local reference = UnifiedCopyReference(item)
    if not manager
        or not reference
        or type(manager.SetAssignment) ~= "function"
        or not self.specializationAssignmentsEnabled
    then
        return nil, "provider_error"
    end

    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local itemName = ResolveItemName(item)
    if not self:BeginSessionMutation(providerId, sessionToken) then
        return nil, "provider_error"
    end
    local assignment, code, changeDetail = manager:SetAssignment(
        providerId,
        reference,
        mode,
        specKeys or {}
    )
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then
        return nil, code
    end
    if not assignment then
        if catalogDirty then
            self:RefreshCatalog(reference.kind, reference.id)
        end
        self:SetError(code)
        return nil, code
    end

    assignment = UnifiedAssignment(assignment)
    local assignmentSnapshot = type(changeDetail) == "table"
        and changeDetail.assignmentSnapshot
        or nil
    if not self:RefreshAssignmentsFromSnapshot(assignmentSnapshot, changeDetail) then
        self:RefreshCatalog(reference.kind, reference.id)
    end
    self:SetStatus(
        UnifiedFormat(
            "settings.config_sets.assignment.saved",
            "已保存「%s」的适用专精设置。",
            itemName
        ),
        "color.state.success"
    )
    return assignment
end

function Picker:SetUnifiedUserSetEnabled(item, enabled)
    local manager = GetManager()
    local reference = UnifiedCopyReference(item)
    if not manager
        or not reference
        or reference.kind ~= "user"
        or type(manager.SetUserSetEnabled) ~= "function"
    then
        return nil, "provider_error"
    end

    local providerId = self.providerId
    local sessionToken = self.sessionToken
    if not self:BeginSessionMutation(providerId, sessionToken) then
        return nil, "provider_error"
    end
    local assignment, code = manager:SetUserSetEnabled(providerId, reference.id, enabled)
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return nil, code end
    if not assignment then
        if catalogDirty then self:RefreshCatalog(reference.kind, reference.id) end
        self:SetError(code)
        return nil, code
    end
    self:RefreshCatalog(reference.kind, reference.id)
    self:SetStatus(
        Text(
            enabled and "settings.config_sets.enable" or "settings.config_sets.disable",
            enabled and "启用" or "禁用"
        ) .. " · " .. ResolveItemName(item),
        "color.state.success"
    )
    return assignment
end

function Picker:ActivateUnifiedItem(item)
    local manager = GetManager()
    if not manager or not item or item.kind ~= "user" then return end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local onApplied = self.onApplied
    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:Apply(
        providerId,
        { kind = "user", id = item.id },
        self.undoOwner,
        {
            recordUndo = false,
            reason = "configuration-mode-select",
            configurationMode = self.configurationMode,
        }
    )
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog(item.kind, item.id) end
        self:SetError(code)
        return
    end
    self:SetStatus(
        UnifiedFormat(
            "settings.config_sets.applied",
            "已应用“%s”。",
            ResolveItemName(item)
        ),
        "color.state.success"
    )
    self.activeReference = {
        kind = item.kind,
        id = item.id,
    }
    self.currentSpecializationReference = {
        kind = item.kind,
        id = item.id,
    }
    for _, catalogItem in ipairs(self.allItems or {}) do
        catalogItem.enabled = UnifiedReferencesEqual(
            catalogItem,
            self.activeReference
        )
    end
    self:RebuildUnifiedVisibleItems(item.kind, item.id)
    self:RefreshUnifiedRows()
    self:RefreshFooter()
    if onApplied then onApplied(result) end
end

function Picker:SetConfigurationMode(mode)
    if not self.configurationModesEnabled or mode == self.configurationMode then
        if self.configurationModeControl then
            self.configurationModeControl:SetValue(self.configurationMode, true)
        end
        return
    end
    local manager = GetManager()
    if not manager or type(manager.SetConfigurationMode) ~= "function" then return end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local previousMode = self.configurationMode
    local onApplied = self.onApplied
    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:SetConfigurationMode(
        providerId,
        mode,
        self.undoOwner
    )
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        self.configurationMode = previousMode
        if self.configurationModeControl then
            self.configurationModeControl:SetValue(previousMode, true)
        end
        if catalogDirty then self:RefreshCatalog() end
        self:SetError(code)
        return
    end
    self.configurationMode = mode
    self.selectedKind = nil
    self.selectedId = nil
    self.listFirstIndex = 1
    self:SetStatus(
        mode == "unified"
            and Text(
                "settings.config_sets.mode.changed_unified",
                "已切换为账号统一配置。"
            )
            or Text(
                "settings.config_sets.mode.changed_specialization",
                "已切换为专精独立配置。"
            ),
        "color.state.success"
    )
    self:RefreshCatalog()
    if onApplied then onApplied(result.applied or result) end
end

function Picker:OpenAssignmentSpecSelector(anchor, item)
    if not anchor
        or not item
        or not self.specializationAssignmentsEnabled
        or type(S.OpenSpecMultiSelectDropdown) ~= "function"
    then
        return nil
    end

    local manager = GetManager()
    local reference = UnifiedCopyReference(item)
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    if not manager
        or not reference
        or not self:IsCurrentSession(providerId, sessionToken)
    then
        return nil
    end

    if S.CloseSpecMultiSelectDropdown then
        S:CloseSpecMultiSelectDropdown(self, "replaced")
    end

    local assignment = UnifiedAssignment(item.assignment)
    local selected = (assignment.mode == "specs" or assignment.mode == "all" or self.profileOwned)
        and UnifiedSelectedSpecMap(assignment.specKeys)
        or {}
    self.assignmentSelectorReference = reference
    self.assignmentSelectorSessionToken = sessionToken
    self.assignmentSelectorDraftSelection = selected
    self.assignmentSelectorDirty = false
    self.suppressUnifiedHoverUntilMouseMove = true
    self:ResetUnifiedRowHoverStates()

    local panel = S:OpenSpecMultiSelectDropdown(anchor, {
        owner = self,
        groups = self.specializationGroups,
        value = selected,
        defaultSelected = false,
        panelTitle = Text("settings.config_sets.assignment.specs", "指定专精")
            .. " · " .. ResolveItemName(item),
        selectAllText = Text("settings.config_sets.assignment.select_all", "全选"),
        clearText = Text("settings.config_sets.assignment.clear", "清空"),
        onChange = function(_, value)
            if not self:IsCurrentSession(providerId, sessionToken)
                or self.assignmentSelectorSessionToken ~= sessionToken
                or not UnifiedReferencesEqual(self.assignmentSelectorReference, reference)
            then
                return
            end

            self.assignmentSelectorDraftSelection = value
            self.assignmentSelectorDirty = true
        end,
        onClose = function()
            if not self:IsCurrentSession(providerId, sessionToken)
                or self.assignmentSelectorSessionToken ~= sessionToken
                or not UnifiedReferencesEqual(self.assignmentSelectorReference, reference)
            then
                return
            end

            local dirty = self.assignmentSelectorDirty == true
            local specKeys = UnifiedCollectSelectedSpecKeys(
                self.specializationSpecOrder,
                self.assignmentSelectorDraftSelection
            )
            local mode
            if self.profileOwned then
                mode = (#specKeys > 0 or assignment.mode == "default") and "specs" or "none"
            elseif self.editableUserSets then
                mode = #specKeys == #(self.specializationSpecOrder or {})
                    and "all"
                    or (#specKeys > 0 and "specs" or "none")
            else
                mode = #specKeys > 0 and "specs" or "none"
            end
            self.assignmentSelectorReference = nil
            self.assignmentSelectorSessionToken = nil
            self.assignmentSelectorDraftSelection = nil
            self.assignmentSelectorDirty = nil
            self.suppressUnifiedHoverUntilMouseMove = self:IsMouseOverUnifiedRow() or nil
            self:ResetUnifiedRowHoverStates()
            if dirty then
                self:SetUnifiedAssignment(item, mode, specKeys)
            end
        end,
    })
    if not panel then
        self.assignmentSelectorReference = nil
        self.assignmentSelectorSessionToken = nil
        self.assignmentSelectorDraftSelection = nil
        self.assignmentSelectorDirty = nil
        self.suppressUnifiedHoverUntilMouseMove = self:IsMouseOverUnifiedRow() or nil
        self:ResetUnifiedRowHoverStates()
    end
    return panel
end

function Picker:PositionUnifiedCursorAnchor(fallbackAnchor)
    if not (UIParent and type(GetCursorPosition) == "function") then
        return fallbackAnchor
    end
    if not self.unifiedCursorAnchor then
        self.unifiedCursorAnchor = GUI2:CreateFrame(UIParent, {
            width = 1,
            height = 1,
            mouse = false,
        })
        self.unifiedCursorAnchor:SetFrameStrata("TOOLTIP")
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not x or not y or not scale or scale <= 0 then return fallbackAnchor end
    local cursorAnchor = self.unifiedCursorAnchor
    cursorAnchor:ClearAllPoints()
    cursorAnchor:SetPoint(
        "BOTTOMLEFT",
        UIParent,
        "BOTTOMLEFT",
        x / scale,
        y / scale
    )
    cursorAnchor:Show()
    return cursorAnchor
end

function Picker:OpenAssignmentMenu(anchor, item)
    if not anchor
        or not item
        or not self.specializationAssignmentsEnabled
        or not GUI2.OpenDropdown
    then
        return
    end

    self:SelectUnifiedItem(item)
    local menuAnchor = self:PositionUnifiedCursorAnchor(anchor)
    local assignment = UnifiedAssignment(item.assignment)
    if self.configurationModesEnabled and self.configurationMode == "unified" then
        return
    elseif self.editableUserSets and not self.profileOwned then
        local options = {
            {
                text = Text("settings.config_sets.assignment.all", "全部"),
                value = "all",
                checked = assignment.mode == "all",
                func = function()
                    Picker:SetUnifiedAssignment(item, "all", {})
                end,
            },
            {
                text = Text("settings.config_sets.assignment.specs", "指定专精"),
                value = "specs",
                checked = assignment.mode == "specs",
                func = function()
                    GUI2:CloseDropdown(false)
                    Picker:OpenAssignmentSpecSelector(
                        Picker:PositionUnifiedCursorAnchor(anchor),
                        item
                    )
                end,
            },
        }
        GUI2:OpenDropdown(menuAnchor, options, nil, assignment.mode, 156)
        return
    end
    local options = {
        {
            text = Text("settings.config_sets.assignment.set_default", "设为默认"),
            value = "default",
            checked = assignment.mode == "default",
            func = function()
                Picker:SetUnifiedAssignment(item, "default", {})
            end,
        },
        {
            text = Text("settings.config_sets.assignment.specs", "指定专精"),
            value = "specs",
            checked = assignment.mode == "specs",
            func = function()
                GUI2:CloseDropdown(false)
                Picker:OpenAssignmentSpecSelector(
                    Picker:PositionUnifiedCursorAnchor(anchor),
                    item
                )
            end,
        },
        {
            text = Text("settings.config_sets.assignment.none", "无"),
            value = "none",
            checked = assignment.mode == "none",
            func = function()
                Picker:SetUnifiedAssignment(item, "none", {})
            end,
        },
    }
    if self.profileOwned then
        options[#options + 1] = {
            text = Text("settings.config_sets.assignment.use_all", "全部使用此方案（清除专用分配）"),
            value = "all",
            func = function() Picker:SetUnifiedAssignment(item, "all", {}) end,
        }
    end
    GUI2:OpenDropdown(menuAnchor, options, nil, assignment.mode, self.profileOwned and 280 or 156)
end

function Picker:GetCurrentSpecializationReference()
    local manager = GetManager()
    if not manager or not self.providerId then return nil end
    local specKey
    if type(manager.GetCurrentSpecializationKey) == "function" then
        specKey = manager:GetCurrentSpecializationKey(self.providerId)
    end
    self.currentSpecializationKey = type(specKey) == "string" and specKey or nil
    if self.assignmentRoutingEnabled
        and type(manager.ResolveAssignment) == "function"
    then
        local reference = manager:ResolveAssignment(self.providerId, self.currentSpecializationKey)
        return UnifiedReference(reference)
    end
    return nil
end

function Picker:RefreshHeaderState()
    if not self.currentSpecText or not self.activeSetText then return end
    if self.configurationModesEnabled then
        UnifiedSetShown(self.configurationModeControl, true)
        if self.configurationModeControl then
            self.configurationModeControl:SetValue(
                self.configurationMode or "specialization",
                true
            )
        end
        UnifiedSetShown(self.currentSpecLabel, false)
        UnifiedSetShown(self.currentSpecText, false)
        UnifiedSetShown(self.contextSeparator, false)
        UnifiedSetShown(self.activeSetLabel, false)
        UnifiedSetShown(self.activeSetText, false)
        UnifiedSetShown(self.specPreviewButton, false)
        return
    end
    UnifiedSetShown(self.configurationModeControl, false)
    local supportsAssignments = self.specializationModeActive == true
    UnifiedSetShown(self.currentSpecLabel, supportsAssignments)
    UnifiedSetShown(self.currentSpecText, supportsAssignments)
    UnifiedSetShown(self.contextSeparator, supportsAssignments)
    if supportsAssignments then
        local spec = UnifiedFindSpec(self.specializationGroups, self.currentSpecializationKey)
        local specName = spec and (spec.displayName or spec.name)
            or Text("settings.config_sets.current_spec.unavailable", "未识别")
        UnifiedFitFontString(self.currentSpecText, specName or "")
    end

    local activeItem = self:GetUnifiedItem(self.activeReference)
    local activeName = activeItem and ResolveItemName(activeItem)
        or Text("settings.config_sets.active.none", "无")
    self.activeSetText:SetWidth(supportsAssignments and 220 or 650)
    UnifiedFitFontString(self.activeSetText, activeName)
    if self.activeSetLabel then
        self.activeSetLabel:ClearAllPoints()
        self.activeSetLabel:SetPoint("LEFT", supportsAssignments and 340 or 14, 0)
    end
    UnifiedSetShown(self.specPreviewButton, self.hasSpecializationAssignments == true)
end

function Picker:RefreshConfigurationModeLayout()
    local dual = self.configurationModesEnabled == true
    if self.contextInfoPanel then
        if dual then
            self.contextInfoPanel:SetBackdropColor(0, 0, 0, 0)
            UnifiedSetBorderShown(self.contextInfoPanel, false)
        else
            GUI2:ApplyBackdrop(
                self.contextInfoPanel,
                "color.surface.sunken"
            )
            UnifiedSetBorderShown(self.contextInfoPanel, true)
        end
    end
    if self.unifiedToolbar then
        self.unifiedToolbar:ClearAllPoints()
        self.unifiedToolbar:SetPoint(
            dual and "BOTTOMLEFT" or "TOPLEFT",
            self.panel,
            dual and "BOTTOMLEFT" or "TOPLEFT",
            24,
            dual and 16 or -96
        )
    end
    if self.unifiedHeaders then
        self.unifiedHeaders:ClearAllPoints()
        self.unifiedHeaders:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 24, dual and -96 or -130)
    end
    if self.listViewport then
        self.listViewport:ClearAllPoints()
        self.listViewport:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 24, dual and -96 or -150)
    end
    UnifiedSetShown(self.unifiedHeaders, not dual)
    UnifiedSetShown(self.schemeTitleText, not dual and not self.editableUserSets)
    UnifiedSetShown(self.totalCountText, not dual and not self.editableUserSets)
    UnifiedSetShown(
        self.assignmentHeaderText,
        self.specializationModeActive == true
    )
    UnifiedSetShown(self.hideUnusedButton, not dual)
    UnifiedSetShown(self.applyButton, not dual)
    UnifiedSetShown(self.undoButton, not dual)
end

function Picker:GetUnifiedSortPriority(item)
    if UnifiedReferencesEqual(item, self.currentSpecializationReference) then
        return 0
    end
    local assignment = item.assignment or { mode = "none", specKeys = {} }
    if assignment.mode == "specs" and #assignment.specKeys > 0 then
        return 1
    end
    if assignment.mode == "default" then
        return 2
    end
    return 3
end

function Picker:RebuildUnifiedVisibleItems(preferredKind, preferredId)
    local allItems = self.allItems or {}
    table.sort(allItems, function(left, right)
        if left.kind ~= right.kind then
            return left.kind == "builtin"
        end
        if left.kind == "builtin" then
            return (left.sourceOrder or 0) < (right.sourceOrder or 0)
        end
        local leftPriority = Picker:GetUnifiedSortPriority(left)
        local rightPriority = Picker:GetUnifiedSortPriority(right)
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        return (left.sourceOrder or 0) < (right.sourceOrder or 0)
    end)

    local visibleItems = {}
    local visibleByReference = {}
    local function AddVisible(item)
        local hiddenUnusedBuiltin = self.specializationAssignmentsEnabled
            and self.hideUnusedBuiltins
            and item.kind == "builtin"
            and item.assignment.mode == "none"
            and not UnifiedReferencesEqual(item, self.currentSpecializationReference)
            and not UnifiedReferencesEqual(item, self.activeReference)
        if not hiddenUnusedBuiltin then
            visibleItems[#visibleItems + 1] = item
            visibleByReference[UnifiedReferenceKey(item)] = item
        end
    end
    if self.configurationModesEnabled and self.configurationMode == "unified" then
        visibleItems[#visibleItems + 1] = {
            sectionHeader = true,
            title = Text(
                "settings.config_sets.mode.in_use",
                "使用中的方案"
            ),
            showAssignmentHeader = false,
        }
        for _, item in ipairs(allItems) do
            if UnifiedReferencesEqual(item, self.activeReference) then
                AddVisible(item)
            end
        end
        visibleItems[#visibleItems + 1] = {
            sectionHeader = true,
            gapBefore = true,
            title = Text(
                "settings.config_sets.mode.not_in_use",
                "未启用的方案"
            ),
            showAssignmentHeader = false,
        }
        for _, item in ipairs(allItems) do
            if not UnifiedReferencesEqual(item, self.activeReference) then
                AddVisible(item)
            end
        end
    elseif self.editableUserSets then
        visibleItems[#visibleItems + 1] = {
            sectionHeader = true,
            title = self.profileOwned and Text("settings.config_sets.assigned", "已分配") or self.configurationModesEnabled
                and Text(
                    "settings.config_sets.mode.enabled",
                    "已启用的方案"
                )
                or Text("settings.config_sets.enabled", "已启用"),
            showAssignmentHeader = self.configurationModesEnabled == true,
        }
        for _, item in ipairs(allItems) do
            if item.enabled then AddVisible(item) end
        end
        visibleItems[#visibleItems + 1] = {
            sectionHeader = true,
            gapBefore = true,
            title = self.profileOwned and Text("settings.config_sets.reserve", "备用方案") or self.configurationModesEnabled
                and Text(
                    "settings.config_sets.mode.disabled",
                    "未启用的方案"
                )
                or Text("settings.config_sets.disabled", "未启用"),
            showAssignmentHeader = self.configurationModesEnabled == true,
        }
        for _, item in ipairs(allItems) do
            if not item.enabled then AddVisible(item) end
        end
    else
        for _, item in ipairs(allItems) do AddVisible(item) end
    end
    self.visibleItems = visibleItems

    local preferred = {
        kind = preferredKind or self.selectedKind,
        id = preferredId or self.selectedId,
    }
    local function GetVisible(reference)
        local key = UnifiedReferenceKey(reference)
        return key and visibleByReference[key] or nil
    end
    local selected = GetVisible(preferred)
        or GetVisible(self.activeReference)
        or GetVisible(self.currentSpecializationReference)
        or allItems[1]
    self.selectedKind = selected and selected.kind or nil
    self.selectedId = selected and selected.id or nil
    self.listFirstIndex = math_max(1, math_min(
        self.listFirstIndex or 1,
        math_max(1, #visibleItems - UNIFIED_VISIBLE_ROW_UNITS + 1)
    ))
    self:EnsureUnifiedSelectionVisible()
end

function Picker:BuildUnifiedCatalog(preferredKind, preferredId)
    local manager = GetManager()
    if not manager or not self.providerId then return false end

    if self.configurationModesEnabled
        and type(manager.GetConfigurationMode) == "function" then
        local mode, modeCode = manager:GetConfigurationMode(self.providerId)
        if not mode then
            self:SetError(modeCode)
            return false
        end
        self.configurationMode = mode
    else
        self.configurationMode = nil
    end
    self.specializationModeActive = self.specializationAssignmentsEnabled
        and (
            not self.configurationModesEnabled
            or self.configurationMode == "specialization"
        )

    local scopes, scopeCode = manager:GetScopes(self.providerId)
    if not scopes then
        self:SetError(scopeCode)
        scopes = {}
    end
    self.scopes = scopes
    self.scopeById = {}
    for _, scope in ipairs(scopes) do
        self.scopeById[scope.id] = scope
    end

    local builtins, builtinCode = manager:ListBuiltins(self.providerId)
    if not builtins then
        self:SetError(builtinCode)
        builtins = {}
    end
    local users, userCode = manager:ListUserSets(
        self.providerId,
        self.configurationModesEnabled and {
            configurationMode = self.configurationMode,
        } or nil
    )
    if not users then
        self:SetError(userCode)
        users = {}
    end
    self.builtins = builtins
    self.userSets = users
    self.specializationGroups = self.specializationModeActive
        and UnifiedResolveSpecializationGroups(manager, self.providerId)
        or {}
    self.specializationSpecOrder, self.specializationSpecByKey =
        UnifiedBuildSpecDisplayIndex(self.specializationGroups)

    local assignmentSnapshot = {}
    if self.specializationModeActive
        and type(manager.GetAssignments) == "function"
    then
        local result, code = manager:GetAssignments(self.providerId)
        if type(result) == "table" then
            assignmentSnapshot = result
        elseif code then
            self:SetError(code)
        end
    end
    self.assignmentSnapshot = assignmentSnapshot
    self.assignmentRoutingEnabled = assignmentSnapshot.enabled == true
    self.bySpecialization = {}
    local rawBySpecialization = assignmentSnapshot.bySpec or assignmentSnapshot.bySpecialization
    if type(rawBySpecialization) == "table" then
        for specKey, reference in pairs(rawBySpecialization) do
            local normalized = UnifiedReference(reference)
            if type(specKey) == "string" and normalized then
                self.bySpecialization[specKey] = normalized
            end
        end
    end

    local allItems = {}
    local itemByReference = {}
    local sourceOrder = 0
    local function AddItems(items, kind)
        for _, item in ipairs(items or {}) do
            sourceOrder = sourceOrder + 1
            item.kind = kind
            item.sourceOrder = sourceOrder
            item.assignment = self.specializationModeActive
                and UnifiedGetAssignment(
                    manager,
                    self.providerId,
                    assignmentSnapshot,
                    { kind = kind, id = item.id }
                )
                or { mode = "none", specKeys = {} }
            item.enabled = self.configurationModesEnabled
                    and self.configurationMode == "unified"
                    and UnifiedReferencesEqual(item, self.activeReference)
                or not self.editableUserSets
                or item.assignment.enabled ~= false
            for _, specKey in ipairs(item.assignment.specKeys) do
                if self.bySpecialization[specKey] == nil then
                    self.bySpecialization[specKey] = { kind = kind, id = item.id }
                end
            end
            allItems[#allItems + 1] = item
            itemByReference[UnifiedReferenceKey(item)] = item
        end
    end
    if not self.editableUserSets then
        AddItems(builtins, "builtin")
    end
    AddItems(users, "user")
    self.allItems = allItems
    self.itemByReference = itemByReference
    self.hasSpecializationAssignments = next(self.bySpecialization) ~= nil

    self.currentSpecializationReference = self:GetCurrentSpecializationReference()
    if type(manager.GetActiveReference) == "function" then
        self.activeReference = UnifiedReference(manager:GetActiveReference(self.providerId))
    else
        self.activeReference = nil
    end
    if self.configurationModesEnabled and self.configurationMode == "unified" then
        for _, item in ipairs(allItems) do
            item.enabled = UnifiedReferencesEqual(item, self.activeReference)
        end
    end

    local preferences = {}
    if type(manager.GetPickerPreferences) == "function" then
        local result = manager:GetPickerPreferences(self.providerId)
        if type(result) == "table" then preferences = result end
    end
    self.pickerPreferences = preferences
    self.hideUnusedBuiltins = not self.editableUserSets
        and self.specializationModeActive
        and preferences.hideUnusedBuiltins == true
        or false

    self:RebuildUnifiedVisibleItems(preferredKind, preferredId)
    return true
end

function Picker:LayoutUnifiedRowTitle(row)
    if not row or not row.title or not row.details then return end
    local reservedWidth = 0
    if row.showYuiTag then
        reservedWidth = reservedWidth
            + (row.yuiTag.GetWidth and row.yuiTag:GetWidth() or UNIFIED_YUI_TAG_WIDTH)
            + UNIFIED_TAG_GAP
    end
    if row.showCurrentTag then
        reservedWidth = reservedWidth
            + (row.currentTag.GetWidth and row.currentTag:GetWidth() or UNIFIED_CURRENT_TAG_WIDTH)
            + UNIFIED_TAG_GAP
    end
    local titleMaxWidth = math_max(
        72,
        (row.nameAreaWidth or UNIFIED_NAME_WIDTH)
            - (UNIFIED_NAME_INSET * 2)
            - reservedWidth
    )
    row.title:SetWidth(titleMaxWidth)
    UnifiedFitFontString(row.title, row.fullTitleText or "")
    local measuredWidth = UnifiedMeasureFontStringWidth(row.title)
    if measuredWidth then
        row.title:SetWidth(math_max(1, math_min(titleMaxWidth, math.ceil(measuredWidth))))
    end

    row.title:ClearAllPoints()
    if row.yuiTag then row.yuiTag:ClearAllPoints() end
    if row.currentTag then row.currentTag:ClearAllPoints() end

    local tagAnchor = row.title
    if row.yuiTag then
        row.yuiTag:SetPoint("LEFT", tagAnchor, "RIGHT", UNIFIED_TAG_GAP, 0)
        if row.showYuiTag then tagAnchor = row.yuiTag end
    end
    if row.currentTag then
        row.currentTag:SetPoint("LEFT", tagAnchor, "RIGHT", UNIFIED_TAG_GAP, 0)
    end
    self:ApplyUnifiedRowExpansionProgress(row, row.expandProgress or 0)
end

function Picker:ApplyUnifiedRowExpansionProgress(row, progress)
    if not row or not row.title or not row.details then return end
    progress = math_max(0, math_min(1, tonumber(progress) or 0))
    row.expandProgress = progress
    row.expanded = progress > 0

    row.title:ClearAllPoints()
    row.title:SetPoint(
        "LEFT",
        row,
        "LEFT",
        UNIFIED_NAME_INSET,
        (row.titleExpandedY or 0) * progress
    )
    if progress > 0 and row.hasDetails then
        row.details:SetAlpha(progress)
        row.details:Show()
    else
        row.details:SetAlpha(0)
        row.details:Hide()
    end
end

function Picker:ResetUnifiedRowMotion(row)
    if not row then return end
    if Animation and Animation.StopTarget then
        Animation:StopTarget(row, UNIFIED_ROW_MOTION_KEY, false)
    end
    row.expansionTarget = 0
    self:ApplyUnifiedRowExpansionProgress(row, 0)
end

function Picker:SetUnifiedRowExpanded(row, expanded, animate)
    if not row or not row.title or not row.details then return end
    local target = expanded == true and row.hasDetails == true and 1 or 0
    local from = row.expandProgress or 0
    if animate ~= false
        and row.expansionTarget == target
        and from ~= target
    then
        return
    end
    row.expansionTarget = target

    if animate == false or from == target or not GUI2.PlayControlMotion then
        if Animation and Animation.StopTarget then
            Animation:StopTarget(row, UNIFIED_ROW_MOTION_KEY, false)
        end
        self:ApplyUnifiedRowExpansionProgress(row, target)
        return
    end

    if target > 0 then
        row.details:Show()
    end
    local handle = GUI2:PlayControlMotion(row, UNIFIED_ROW_MOTION_KEY, {
        owner = self,
        key = UNIFIED_ROW_MOTION_KEY,
        target = row,
        from = from,
        to = target,
        duration = 0.12,
        easing = "sineInOut",
        onUpdate = function(value)
            if row.expansionTarget == target then
                Picker:ApplyUnifiedRowExpansionProgress(row, value)
            end
        end,
        onFinished = function(_, _, finished)
            if finished == true and row.expansionTarget == target then
                Picker:ApplyUnifiedRowExpansionProgress(row, target)
            end
        end,
    })
    if not handle or handle.noop then
        self:ApplyUnifiedRowExpansionProgress(row, target)
    end
end

function Picker:LayoutUnifiedRowDetails(row)
    if not row or not row.details then return end
    local width = math_max(
        72,
        (row.nameAreaWidth or UNIFIED_NAME_WIDTH) - (UNIFIED_NAME_INSET * 2)
    )
    row.details:ClearAllPoints()
    row.details:SetWidth(width)
    row.description:ClearAllPoints()
    row.contentText:ClearAllPoints()

    if row.hasDescription and row.hasContent then
        row.titleExpandedY = 17
        row.details:SetPoint("TOPLEFT", row, "TOPLEFT", UNIFIED_NAME_INSET, -29)
        row.description:SetPoint("TOPLEFT", row.details, "TOPLEFT", 0, 0)
        row.contentText:SetPoint(
            "TOPLEFT",
            row.description,
            "BOTTOMLEFT",
            0,
            -UNIFIED_ROW_DETAILS_GAP
        )
    else
        row.titleExpandedY = 10
        row.details:SetPoint("TOPLEFT", row, "TOPLEFT", UNIFIED_NAME_INSET, -40)
        local detailText = row.hasDescription and row.description or row.contentText
        detailText:SetPoint("TOPLEFT", row.details, "TOPLEFT", 0, 0)
    end

    row.description:SetWidth(width)
    row.contentText:SetWidth(width)
    UnifiedSetShown(row.description, row.hasDescription)
    UnifiedSetShown(row.contentText, row.hasContent)
    self:ApplyUnifiedRowExpansionProgress(row, row.expandProgress or 0)
end

function Picker:RefreshUnifiedRowVisual(row, hovered, animate)
    if not row or not row.item then return end
    local item = row.item
    local selected = item.kind == self.selectedKind and item.id == self.selectedId
    local current = self.configurationModesEnabled
            and self.configurationMode == "unified"
            and UnifiedReferencesEqual(item, self.activeReference)
        or UnifiedReferencesEqual(item, self.currentSpecializationReference)
    local unused = self.editableUserSets and not item.enabled
        or (self.specializationModeActive == true
            and item.assignment
            and item.assignment.mode == "none")
    local surface = current
            and (
                self.configurationModesEnabled
                and "color.configset.current.surface"
                or "color.control.active"
            )
        or (item.enabled and self.configurationModesEnabled
            and "color.configset.enabled.surface")
        or (selected and "color.surface.raised" or "color.surface.panel")
    row.gui2Surface = hovered and "color.control.hover" or surface
    GUI2:ApplyBackdrop(row, row.gui2Surface)
    GUI2:SetBorderColor(
        row,
        current and (
            self.configurationModesEnabled
            and "color.configset.current.border"
            or "color.border.accent"
        )
        or (item.enabled and self.configurationModesEnabled
            and "color.configset.enabled.border")
        or (selected and "color.border.default" or "color.border.subtle")
    )
    row:SetAlpha((unused and not current and not hovered) and 0.68 or 1)
    self:SetUnifiedRowExpanded(row, hovered == true, animate)
end

function Picker:SelectUnifiedItem(item)
    if not item then return end
    self.selectedKind = item.kind
    self.selectedId = item.id
    self:EnsureUnifiedSelectionVisible()
    self:RefreshUnifiedRows()
    self:RefreshFooter()
end

function Picker:CreateUnifiedActionButton(parent, iconName, tooltip, onClick, danger, size)
    size = tonumber(size) or UNIFIED_ACTION_SIZE
    local button = GUI2:CreateIconButton(parent, {
        size = size,
        icon = UnifiedCoreIcon(iconName),
        padding = 5,
        tooltip = tooltip,
        onClick = onClick,
        iconColor = danger and "color.state.error" or "color.text.secondary",
        hoverIconColor = danger and "color.state.error" or "color.text.primary",
        hoverBorder = danger and "color.state.error" or "color.border.accent",
    })
    button.SetDisabled = function(frame, disabled)
        disabled = disabled == true
        if disabled
            and GameTooltip
            and GameTooltip.IsOwned
            and GameTooltip:IsOwned(frame)
        then
            YUI.HideGameTooltip()
        end
        if disabled then
            if frame.Disable then frame:Disable() end
        elseif frame.Enable then
            frame:Enable()
        end
        if frame.SetState then
            frame:SetState(disabled and "disabled" or "normal")
        else
            frame.gui2Disabled = disabled
            if frame.RefreshTheme then frame:RefreshTheme() end
        end
        frame:SetAlpha(disabled and 0.55 or 1)
    end
    button:SetDisabled(false)
    return button
end

function Picker:EnsureUnifiedRows()
    if self.unifiedRows then return end
    self.unifiedRows = {}
    for index = 1, UNIFIED_ROW_POOL_SIZE do
        local row = GUI2:CreateButtonFrame(self.listViewport, {
            template = "BackdropTemplate",
            width = UNIFIED_LIST_WIDTH - 12,
            height = UNIFIED_ROW_HEIGHT,
        })
        row:SetPoint("TOPLEFT", 0, -((index - 1) * UNIFIED_ROW_STEP))
        row:Hide()
        row.poolIndex = index
        GUI2:ApplyBackdrop(row, "color.surface.panel")
        GUI2:CreateBorder(row, "color.border.subtle")

        local title = GUI2:CreateText(row, "", "font.size.md", "color.text.heading", "LEFT")
        title:SetWidth(UNIFIED_NAME_WIDTH - (UNIFIED_NAME_INSET * 2))
        title:SetWordWrap(false)
        row.title = title

        local sectionAssignmentTitle = GUI2:CreateText(
            row,
            "",
            "font.size.sm",
            "color.text.secondary",
            "LEFT"
        )
        sectionAssignmentTitle:SetPoint(
            "LEFT",
            UNIFIED_NAME_WIDTH + 8,
            0
        )
        sectionAssignmentTitle:SetWidth(UNIFIED_ASSIGNMENT_WIDTH)
        sectionAssignmentTitle:SetWordWrap(false)
        sectionAssignmentTitle:Hide()
        row.sectionAssignmentTitle = sectionAssignmentTitle

        local sectionActionTitle = GUI2:CreateText(
            row,
            "",
            "font.size.sm",
            "color.text.secondary",
            "CENTER"
        )
        sectionActionTitle:SetPoint("RIGHT", -8, 0)
        sectionActionTitle:SetWidth(
            (UNIFIED_ACTION_SIZE * 5) + (UNIFIED_ACTION_GAP * 4)
        )
        sectionActionTitle:SetWordWrap(false)
        sectionActionTitle:Hide()
        row.sectionActionTitle = sectionActionTitle

        local details = GUI2:CreateFrame(row, {
            width = UNIFIED_NAME_WIDTH - (UNIFIED_NAME_INSET * 2),
            height = 30,
            hidden = true,
        })
        details:SetAlpha(0)
        row.details = details

        local description = GUI2:CreateText(details, "", "font.size.sm", "color.text.secondary", "LEFT")
        description:SetWidth(UNIFIED_NAME_WIDTH - (UNIFIED_NAME_INSET * 2))
        description:SetWordWrap(false)
        row.description = description

        local contentText = GUI2:CreateText(details, "", "font.size.sm", "color.text.muted", "LEFT")
        contentText:SetWidth(UNIFIED_NAME_WIDTH - (UNIFIED_NAME_INSET * 2))
        contentText:SetWordWrap(false)
        row.contentText = contentText

        local yuiTag = GUI2.Data:CreateBadge(row, {
            text = Text("settings.config_sets.builtin.badge", "预设"),
            variant = "flat",
            tone = "purple",
            surface = "color.badge.purple",
            textColor = "color.badge.text",
            border = false,
            fontSizeKey = "font.size.md",
            height = 22,
            minWidth = UNIFIED_YUI_TAG_WIDTH,
            paddingX = 7,
            autoWidth = true,
        })
        yuiTag:SetPoint("LEFT", title, "RIGHT", UNIFIED_TAG_GAP, 0)
        row.yuiTag = yuiTag

        local currentTag = GUI2.Data:CreateBadge(row, {
            text = Text("settings.config_sets.mode.current_badge", "当前使用"),
            variant = "flat",
            tone = "green",
            surface = "color.badge.green",
            textColor = "color.badge.text",
            border = false,
            fontSizeKey = "font.size.md",
            height = 22,
            minWidth = UNIFIED_CURRENT_TAG_WIDTH,
            paddingX = 8,
            autoWidth = true,
        })
        currentTag:SetPoint("LEFT", yuiTag, "RIGHT", UNIFIED_TAG_GAP, 0)
        row.currentTag = currentTag

        local assignmentButton = GUI2:CreateFrame(row, {
            width = UNIFIED_ASSIGNMENT_WIDTH - 12,
            height = UNIFIED_ROW_HEIGHT,
            mouse = false,
        })
        assignmentButton:SetPoint("LEFT", UNIFIED_NAME_WIDTH + 8, 0)
        assignmentButton.SetDisabled = function(frame, disabled)
            frame.gui2Disabled = disabled == true
        end
        row.assignmentButton = assignmentButton

        local assignmentDefaultTag = GUI2.Data:CreateBadge(assignmentButton, {
            text = Text("settings.config_sets.assignment.default", "默认"),
            variant = "flat",
            tone = "orange",
            surface = "color.badge.orange",
            textColor = "color.badge.text",
            border = false,
            fontSizeKey = "font.size.md",
            height = 22,
            minWidth = 52,
            paddingX = 10,
            autoWidth = true,
        })
        assignmentDefaultTag:SetPoint("LEFT", 0, 0)
        row.assignmentDefaultTag = assignmentDefaultTag

        local assignmentNoneText = GUI2:CreateText(
            assignmentButton,
            Text("settings.config_sets.assignment.none", "无"),
            "font.size.md",
            "color.text.secondary",
            "LEFT"
        )
        assignmentNoneText:SetPoint("LEFT", 0, 0)
        row.assignmentNoneText = assignmentNoneText

        local assignmentOverflowText = GUI2:CreateText(
            assignmentButton,
            "",
            "font.size.sm",
            "color.text.secondary",
            "LEFT"
        )
        assignmentOverflowText:SetPoint("LEFT", 0, -12)
        row.assignmentOverflowText = assignmentOverflowText

        row.assignmentIcons = {}
        for iconIndex = 1, UNIFIED_ASSIGNMENT_ICON_LIMIT do
            local icon = GUI2:CreateIcon(assignmentButton, {
                size = UNIFIED_ASSIGNMENT_ICON_SIZE,
                icon = UNIFIED_FALLBACK_ICON,
                fallbackIcon = UNIFIED_FALLBACK_ICON,
                crop = true,
                allowTiny = true,
            })
            if iconIndex == 1 then
                icon:SetPoint("LEFT", 0, 0)
            else
                icon:SetPoint(
                    "LEFT",
                    row.assignmentIcons[iconIndex - 1],
                    "RIGHT",
                    UNIFIED_ASSIGNMENT_ICON_GAP,
                    0
                )
            end
            icon:Hide()
            row.assignmentIcons[iconIndex] = icon
        end

        local actions = GUI2:CreateFrame(row, {
            width = (UNIFIED_ACTION_SIZE * 5) + (UNIFIED_ACTION_GAP * 4),
            height = UNIFIED_ACTION_SIZE,
        })
        actions:SetPoint("RIGHT", -8, 0)
        row.actions = actions

        local previewButton = self:CreateUnifiedActionButton(
            actions,
            "eye",
            Text("settings.config_sets.zoom_preview", "预览"),
            function(button)
                if button.item then Picker:OpenZoom(button.item) end
            end
        )
        previewButton:SetPoint("LEFT", 0, 0)
        row.previewButton = previewButton

        local editButton = self:CreateUnifiedActionButton(
            actions,
            "pencil",
            Text("settings.config_sets.edit", "编辑"),
            function(button)
                if button.item then
                    Picker:SelectUnifiedItem(button.item)
                    Picker:OpenUnifiedEditor("edit", button.item)
                end
            end
        )
        editButton:SetPoint("LEFT", previewButton, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.editButton = editButton

        local assignmentAction = self:CreateUnifiedActionButton(
            actions,
            "settings",
            Text("settings.config_sets.assignment.title", "适用专精"),
            function(button)
                if button.item then
                    Picker:OpenAssignmentMenu(button, button.item)
                end
            end
        )
        assignmentAction:SetPoint("LEFT", editButton, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.assignmentAction = assignmentAction

        local enableButton = self:CreateUnifiedActionButton(
            actions,
            "play",
            Text("settings.config_sets.enable", "启用"),
            function(button)
                if button.item then
                    Picker:SetUnifiedUserSetEnabled(button.item, true)
                end
            end
        )
        enableButton:SetPoint("LEFT", assignmentAction, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.enableButton = enableButton

        local activateButton = self:CreateUnifiedActionButton(
            actions,
            "play",
            Text("settings.config_sets.mode.activate", "设为当前"),
            function(button)
                if button.item then
                    Picker:ActivateUnifiedItem(button.item)
                end
            end
        )
        activateButton:SetPoint(
            "LEFT",
            assignmentAction,
            "RIGHT",
            UNIFIED_ACTION_GAP,
            0
        )
        row.activateButton = activateButton

        local disableButton = self:CreateUnifiedActionButton(
            actions,
            "square",
            Text("settings.config_sets.disable", "禁用"),
            function(button)
                if button.item then
                    Picker:SetUnifiedUserSetEnabled(button.item, false)
                end
            end
        )
        disableButton:SetPoint("LEFT", assignmentAction, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.disableButton = disableButton

        local exportButton = self:CreateUnifiedActionButton(
            actions,
            "upload",
            Text("settings.config_sets.export", "导出"),
            function(button)
                if button.item then Picker:ExportUnifiedItem(button.item) end
            end
        )
        exportButton:SetPoint("LEFT", assignmentAction, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.exportButton = exportButton

        local deleteButton = self:CreateUnifiedActionButton(
            actions,
            "trash-2",
            Text("settings.config_sets.delete", "删除"),
            function(button)
                if button.item then Picker:DeleteUnifiedItem(button.item) end
            end,
            true
        )
        deleteButton:SetPoint("LEFT", exportButton, "RIGHT", UNIFIED_ACTION_GAP, 0)
        row.deleteButton = deleteButton

        for _, actionButton in ipairs({
            previewButton,
            editButton,
            assignmentAction,
            enableButton,
            activateButton,
            disableButton,
            exportButton,
            deleteButton,
        }) do
            actionButton:HookScript("OnEnter", function()
                Picker:HandleUnifiedRowPointer(row, true)
            end)
            actionButton:HookScript("OnLeave", function()
                Picker:HandleUnifiedRowPointer(row, false)
            end)
        end

        row:SetScript("OnClick", function(button)
            if button.item then Picker:SelectUnifiedItem(button.item) end
        end)
        row:SetScript("OnEnter", function(button)
            Picker:HandleUnifiedRowPointer(button, true, button)
        end)
        row:SetScript("OnLeave", function(button)
            Picker:HandleUnifiedRowPointer(button, false, button)
        end)

        self.unifiedRows[index] = row
    end
end

function Picker:RefreshUnifiedColumnLayout()
    local supportsAssignments = self.specializationModeActive == true
    local nameAreaWidth = UNIFIED_NAME_WIDTH
        + (supportsAssignments and 0 or UNIFIED_ASSIGNMENT_WIDTH)

    UnifiedSetShown(self.assignmentHeaderText, supportsAssignments)

    for _, row in ipairs(self.unifiedRows or {}) do
        row.nameAreaWidth = nameAreaWidth
        row.assignmentButton:ClearAllPoints()
        row.assignmentButton:SetPoint("LEFT", nameAreaWidth + 8, 0)
        row.assignmentButton:SetWidth(UNIFIED_ASSIGNMENT_WIDTH - 12)
        UnifiedSetShown(row.assignmentButton, supportsAssignments)
        self:LayoutUnifiedRowDetails(row)
        self:LayoutUnifiedRowTitle(row)
    end
end

function Picker:RefreshUnifiedAssignmentVisual(row, assignment)
    if not row or not row.assignmentButton then return end
    assignment = UnifiedAssignment(assignment)
    UnifiedSetShown(row.assignmentDefaultTag, false)
    UnifiedSetShown(row.assignmentNoneText, false)
    UnifiedSetShown(row.assignmentOverflowText, false)
    for _, icon in ipairs(row.assignmentIcons or {}) do
        icon:Hide()
    end

    if assignment.mode == "all" then
        row.assignmentDefaultTag:SetText(
            Text("settings.config_sets.assignment.all", "全部")
        )
        row.assignmentDefaultTag:Show()
        return
    end
    if assignment.mode == "default" then
        row.assignmentDefaultTag:SetText(
            Text("settings.config_sets.assignment.default", "默认")
        )
        row.assignmentDefaultTag:Show()
        return
    end
    if assignment.mode == "none" then
        row.assignmentNoneText:SetText(
            Text("settings.config_sets.assignment.none", "无")
        )
        row.assignmentNoneText:Show()
        return
    end

    local specs = UnifiedOrderAssignmentSpecs(
        self.specializationSpecOrder,
        self.specializationSpecByKey,
        assignment.specKeys
    )
    local visibleCount = math_min(#specs, UNIFIED_ASSIGNMENT_ICON_LIMIT)
    local overflowCount = math_max(0, #specs - visibleCount)
    local iconY = overflowCount > 0 and 8 or 0
    local previous
    for index = 1, visibleCount do
        local icon = row.assignmentIcons[index]
        local spec = specs[index]
        UnifiedApplySpecializationIcon(icon, spec)
        icon:ClearAllPoints()
        if previous then
            icon:SetPoint(
                "LEFT",
                previous,
                "RIGHT",
                UNIFIED_ASSIGNMENT_ICON_GAP,
                0
            )
        else
            icon:SetPoint("LEFT", row.assignmentButton, "LEFT", 0, iconY)
        end
        icon:Show()
        previous = icon
    end
    if overflowCount > 0 then
        row.assignmentOverflowText:SetText(
            "…" .. UnifiedFormat(
                "settings.config_sets.assignment.spec_count",
                "%d 个专精",
                overflowCount
            )
        )
        row.assignmentOverflowText:Show()
    end
end

function Picker:BindUnifiedRow(row, item)
    self:ResetUnifiedRowMotion(row)
    if not item then
        row.item = nil
        row.sectionHeader = nil
        row.hasDescription = nil
        row.hasContent = nil
        row.hasDetails = nil
        UnifiedSetShown(row.sectionAssignmentTitle, false)
        UnifiedSetShown(row.sectionActionTitle, false)
        self:RefreshUnifiedAssignmentVisual(row, nil)
        row:Hide()
        return
    end
    if item.sectionHeader then
        row.item = nil
        row.sectionHeader = true
        row:SetHeight(UNIFIED_SECTION_ROW_HEIGHT)
        row.fullTitleText = item.title or ""
        GUI2:SetTextColorKey(row.title, "color.text.secondary")
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", 12, 0)
        row.title:SetWidth(UNIFIED_NAME_WIDTH - 12)
        row.title:SetText(row.fullTitleText)
        row.title:Show()
        row.sectionAssignmentTitle:SetText(
            Text("settings.config_sets.assignment.title", "适用专精")
        )
        row.sectionActionTitle:SetText(
            Text("settings.config_sets.actions", "操作")
        )
        UnifiedSetShown(
            row.sectionAssignmentTitle,
            item.showAssignmentHeader == true
        )
        UnifiedSetShown(row.sectionActionTitle, true)
        row.details:Hide()
        row.yuiTag:Hide()
        row.currentTag:Hide()
        row.assignmentButton:Hide()
        row.actions:Hide()
        GUI2:ApplyBackdrop(row, "color.surface.sunken")
        row.gui2Surface = "color.surface.sunken"
        UnifiedSetBorderShown(row, true)
        row:SetAlpha(1)
        row:Show()
        return
    end

    row.item = item
    row.sectionHeader = nil
    row:SetHeight(UNIFIED_ROW_HEIGHT)
    UnifiedSetShown(row.sectionAssignmentTitle, false)
    UnifiedSetShown(row.sectionActionTitle, false)
    UnifiedSetBorderShown(row, true)
    GUI2:SetTextColorKey(row.title, "color.text.heading")
    row.title:Show()
    row.actions:Show()

    row.fullTitleText = ResolveItemName(item)
    local description = ResolveItemDescription(item)
    row.hasDescription = description ~= ""
    UnifiedFitFontString(row.description, description)
    row.showYuiTag = item.kind == "builtin"
    UnifiedSetShown(row.yuiTag, row.showYuiTag)
    if row.yuiTag.SetText then
        row.yuiTag:SetText(Text("settings.config_sets.builtin.badge", "预设"))
    elseif row.yuiTag.text then
        row.yuiTag.text:SetText(Text("settings.config_sets.builtin.badge", "预设"))
    end
    local current = self.configurationModesEnabled
            and self.configurationMode == "unified"
            and UnifiedReferencesEqual(item, self.activeReference)
        or UnifiedReferencesEqual(item, self.currentSpecializationReference)
    row.showCurrentTag = current
    UnifiedSetShown(row.currentTag, row.showCurrentTag)
    if row.currentTag.SetText then
        row.currentTag:SetText(
            self.configurationModesEnabled
                and Text("settings.config_sets.mode.current_badge", "当前使用")
                or Text("settings.config_sets.mode.current_badge", "当前使用")
        )
    elseif row.currentTag.text then
        row.currentTag.text:SetText(
            self.configurationModesEnabled
                and Text("settings.config_sets.mode.current_badge", "当前使用")
                or Text("settings.config_sets.mode.current_badge", "当前使用")
        )
    end

    row.assignmentButton.item = item
    row.assignmentButton:SetDisabled(false)
    UnifiedSetShown(row.assignmentButton, self.specializationModeActive)
    self:RefreshUnifiedAssignmentVisual(row, item.assignment)

    local fullContent = self.userSetScopePolicy == "all"
        and ""
        or self:GetContentScopeSummary(item)
    row.fullContentText = fullContent
    local contentSummary = fullContent ~= ""
        and Text("settings.config_sets.content_scope", "包含内容") .. " · " .. fullContent
        or ""
    row.hasContent = contentSummary ~= ""
    row.hasDetails = row.hasDescription or row.hasContent
    local _, contentTruncated = UnifiedFitFontString(row.contentText, contentSummary)
    row.contentTextWasTruncated = contentTruncated
    self:LayoutUnifiedRowDetails(row)
    self:LayoutUnifiedRowTitle(row)

    row.previewButton.item = item
    row.editButton.item = item
    row.assignmentAction.item = item
    row.assignmentAction:SetDisabled(false)
    row.enableButton.item = item
    row.activateButton.item = item
    row.disableButton.item = item
    row.exportButton.item = item
    row.deleteButton.item = item

    local canPreview = item.kind == "builtin"
        and self:GetPreviewTexture(item) ~= nil
    UnifiedSetShown(row.previewButton, canPreview)
    UnifiedSetShown(row.editButton, item.kind == "user")
    UnifiedSetShown(row.exportButton, item.kind == "user")
    local unifiedMode = self.configurationModesEnabled
        and self.configurationMode == "unified"
    local canDelete = item.kind == "user"
        and (
            not self.configurationModesEnabled
            or (unifiedMode and not current)
            or (not unifiedMode and not item.enabled)
        )
    UnifiedSetShown(row.deleteButton, canDelete)
    UnifiedSetShown(
        row.assignmentAction,
        self.specializationModeActive
    )
    UnifiedSetShown(
        row.activateButton,
        unifiedMode and item.kind == "user" and not current
    )
    UnifiedSetShown(
        row.enableButton,
        not self.profileOwned and not unifiedMode and self.editableUserSets and not item.enabled
    )
    UnifiedSetShown(
        row.disableButton,
        not self.profileOwned and not unifiedMode and self.editableUserSets and item.enabled
    )

    local shownButtons = {}
    if canPreview then shownButtons[#shownButtons + 1] = row.previewButton end
    if item.kind == "user" then shownButtons[#shownButtons + 1] = row.editButton end
    if self.specializationModeActive then
        shownButtons[#shownButtons + 1] = row.assignmentAction
    end
    if unifiedMode and item.kind == "user" and not current then
        shownButtons[#shownButtons + 1] = row.activateButton
    elseif self.editableUserSets and not unifiedMode and not self.profileOwned then
        shownButtons[#shownButtons + 1] =
            item.enabled and row.disableButton or row.enableButton
    end
    if item.kind == "user" then
        shownButtons[#shownButtons + 1] = row.exportButton
        if canDelete then shownButtons[#shownButtons + 1] = row.deleteButton end
    end
    for index = #shownButtons, 1, -1 do
        local button = shownButtons[index]
        button:ClearAllPoints()
        if index == #shownButtons then
            button:SetPoint("RIGHT", row.actions, "RIGHT", 0, 0)
        else
            button:SetPoint("RIGHT", shownButtons[index + 1], "LEFT", -UNIFIED_ACTION_GAP, 0)
        end
    end

    row:Show()
    local hovered = not self.activeUnifiedModal
        and not self.suppressUnifiedHoverUntilMouseMove
        and row.IsMouseOver
        and row:IsMouseOver()
        or false
    self:RefreshUnifiedRowVisual(row, hovered, false)
end

function Picker:RefreshUnifiedListIndicator()
    if not self.listScrollBar then return end
    local count = #(self.visibleItems or {})
    self.listScrollBar:SetScrollState(
        self.listFirstIndex or 1,
        count,
        UNIFIED_VISIBLE_ROW_UNITS,
        true
    )
end

function Picker:RefreshUnifiedRows()
    self:EnsureUnifiedRows()
    self:RefreshUnifiedColumnLayout()
    local firstIndex = self.listFirstIndex or 1
    local y = 0
    for poolIndex, row in ipairs(self.unifiedRows or {}) do
        local item = self.visibleItems and self.visibleItems[firstIndex + poolIndex - 1]
        local previousItem = poolIndex > 1
            and self.visibleItems
            and self.visibleItems[firstIndex + poolIndex - 2]
            or nil
        if item and item.gapBefore and previousItem and not previousItem.sectionHeader then
            y = y + UNIFIED_SECTION_GAP
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        self:BindUnifiedRow(row, item)
        if item then
            y = y + (item.sectionHeader and UNIFIED_SECTION_ROW_HEIGHT
                or UNIFIED_ROW_HEIGHT) + UNIFIED_ROW_GAP
        end
    end
    if self.totalCountText then
        UnifiedSetShown(self.totalCountText, not self.editableUserSets)
        if not self.editableUserSets then
            self.totalCountText:SetText(
                UnifiedFormat(
                    "settings.config_sets.total_count",
                    "%d 套",
                    #(self.allItems or {})
                )
            )
        end
    end
    if self.schemeTitleText then
        UnifiedSetShown(self.schemeTitleText, not self.editableUserSets)
    end
    if self.hideUnusedButton then
        UnifiedSetShown(
            self.hideUnusedButton,
            self.specializationAssignmentsEnabled and not self.editableUserSets
        )
        self.hideUnusedButton:SetText(
            self.hideUnusedBuiltins
                and Text("settings.config_sets.show_unused_builtins", "显示全部预设方案")
                or Text("settings.config_sets.hide_unused_builtins", "隐藏未使用的预设方案")
        )
    end
    self:RefreshUnifiedListIndicator()
    self:RefreshHeaderState()
end

function Picker:SetUnifiedFirstIndex(index, refresh)
    local count = #(self.visibleItems or {})
    local maxFirst = math_max(1, count - UNIFIED_VISIBLE_ROW_UNITS + 1)
    local nextIndex = math_max(1, math_min(maxFirst, math_floor(tonumber(index) or 1)))
    if nextIndex == (self.listFirstIndex or 1) then return false end
    self.listFirstIndex = nextIndex
    if refresh ~= false then self:RefreshUnifiedRows() end
    return true
end

function Picker:EnsureUnifiedSelectionVisible()
    local selectedIndex
    for index, item in ipairs(self.visibleItems or {}) do
        if item.kind == self.selectedKind and item.id == self.selectedId then
            selectedIndex = index
            break
        end
    end
    if not selectedIndex then return end
    local firstIndex = self.listFirstIndex or 1
    if selectedIndex < firstIndex then
        self:SetUnifiedFirstIndex(selectedIndex, false)
    elseif selectedIndex >= firstIndex + UNIFIED_VISIBLE_ROW_UNITS then
        self:SetUnifiedFirstIndex(
            selectedIndex - UNIFIED_VISIBLE_ROW_UNITS + 1,
            false
        )
    end
end

function Picker:ScrollUnifiedRows(delta)
    self:SetUnifiedFirstIndex((self.listFirstIndex or 1) + delta, true)
end

function Picker:SetHideUnusedBuiltins(hidden)
    if not self.specializationAssignmentsEnabled then
        self.hideUnusedBuiltins = false
        return false
    end
    local previousHidden = self.hideUnusedBuiltins == true
    self.hideUnusedBuiltins = hidden == true
    local manager = GetManager()
    if manager and type(manager.SetPickerPreferences) == "function" then
        local providerId = self.providerId
        local sessionToken = self.sessionToken
        local preferences = {}
        for key, value in pairs(self.pickerPreferences or {}) do
            preferences[key] = value
        end
        preferences.hideUnusedBuiltins = self.hideUnusedBuiltins
        self:BeginSessionMutation(providerId, sessionToken)
        local ok, code = manager:SetPickerPreferences(providerId, preferences)
        local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
        if not self:IsCurrentSession(providerId, sessionToken) then return false end
        if ok == nil or ok == false then
            self.hideUnusedBuiltins = previousHidden
            if catalogDirty then self:RefreshCatalog(self.selectedKind, self.selectedId) end
            self:SetError(code)
            return false
        end
        self.pickerPreferences = preferences
    end
    self.listFirstIndex = 1
    self:RefreshCatalog(self.selectedKind, self.selectedId)
end

function Picker:ExportUnifiedItem(item)
    if not item or item.kind ~= "user" then return end
    local yhud = YUI.YHUD
    if yhud and self.providerId == yhud.CONFIG_SET_PROVIDER_ID and yhud.Sharing then
        local ok, code = yhud.Sharing:ShowExport(item.id, nil, self.panel)
        if not ok then self:SetError(code) end
        return
    end
    local manager = GetManager()
    if not manager or type(manager.ExportUserSet) ~= "function" then return end
    local value, code = manager:ExportUserSet(self.providerId, item.id)
    if not value then
        self:SetError(code)
        return
    end
    if S.ShowCopyPopup then
        S:ShowCopyPopup(FormatText("settings.config_sets.export_title", ResolveItemName(item)), value)
    end
end

function Picker:DeleteUnifiedItem(item)
    if not item or item.kind ~= "user" then return end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local setId = item.id
    local itemName = ResolveItemName(item)
    local function Delete()
        if not Picker:IsCurrentSession(providerId, sessionToken) then return end
        local manager = GetManager()
        if not manager then return end
        Picker:BeginSessionMutation(providerId, sessionToken)
        local ok, code = manager:DeleteUserSet(providerId, setId)
        local catalogDirty = Picker:EndSessionMutation(providerId, sessionToken)
        if not Picker:IsCurrentSession(providerId, sessionToken) then return end
        if not ok then
            if catalogDirty then Picker:RefreshCatalog() end
            Picker:SetError(code)
            return
        end
        Picker:RefreshCatalog()
        Picker:SetStatus(
            FormatText("settings.config_sets.deleted", itemName),
            "color.state.success"
        )
    end
    if S.ShowConfirmPopup then
        S:ShowConfirmPopup(FormatText("settings.config_sets.confirm_delete", itemName), Delete, {
            acceptTone = "danger",
            ownerFrame = self.panel,
            dismissWithOwner = true,
        })
    else
        Delete()
    end
end

function Picker:RefreshAssignmentDialogLayout()
    local dialog = self.assignmentDialog
    if not dialog then return end
    local showSpecs = self.assignmentDraftMode == "specs"
    UnifiedSetShown(dialog.specToolbar, showSpecs)
    UnifiedSetShown(dialog.specScroll, showSpecs)
    dialog.panel:SetHeight(showSpecs and 500 or 194)
    dialog.summaryText:SetText(
        UnifiedFormat(
            "settings.config_sets.assignment.selected_count",
            "已选择 %d 个专精",
            #(self:CollectAssignmentSpecKeys())
        )
    )
end

function Picker:CollectAssignmentSpecKeys()
    local result = {}
    for _, specKey in ipairs(self.assignmentSpecOrder or {}) do
        if self.assignmentDraftSpecs and self.assignmentDraftSpecs[specKey] then
            result[#result + 1] = specKey
        end
    end
    return result
end

function Picker:SetAllAssignmentSpecs(selected)
    for _, specKey in ipairs(self.assignmentSpecOrder or {}) do
        self.assignmentDraftSpecs[specKey] = selected == true or nil
    end
    for _, control in ipairs(self.assignmentSpecControls or {}) do
        control:SetChecked(self.assignmentDraftSpecs[control.specKey] == true, true)
    end
    self:RefreshAssignmentDialogLayout()
end

function Picker:RenderAssignmentSpecs()
    local dialog = self.assignmentDialog
    if not dialog or not dialog.specContent then return end
    dialog.assignmentHeaders = dialog.assignmentHeaders or {}
    dialog.assignmentCards = dialog.assignmentCards or {}
    dialog.assignmentChecks = dialog.assignmentChecks or {}
    for _, header in ipairs(dialog.assignmentHeaders) do header:Hide() end
    for _, card in ipairs(dialog.assignmentCards) do card:Hide() end
    for _, checkbox in ipairs(dialog.assignmentChecks) do checkbox:Hide() end
    self.assignmentSpecControls = {}
    self.assignmentSpecOrder = {}

    local innerWidth = 670
    local cardWidth = UNIFIED_SPEC_CARD_WIDTH
    local y = 0
    local headerIndex = 0
    local cardIndex = 0
    local checkboxIndex = 0
    for _, armorGroup in ipairs(self.specializationGroups or {}) do
        headerIndex = headerIndex + 1
        local header = dialog.assignmentHeaders[headerIndex]
        if not header then
            header = GUI2:CreateText(
                dialog.specContent,
                "",
                "font.size.md",
                "color.text.accent",
                "LEFT"
            )
            dialog.assignmentHeaders[headerIndex] = header
        end
        header:ClearAllPoints()
        header:SetText(armorGroup.label or armorGroup.key or "")
        header:SetPoint("TOPLEFT", 0, y)
        header:SetWidth(innerWidth)
        header:Show()
        y = y - 24

        local classEntries = {}
        local classByToken = {}
        for _, classInfo in ipairs(armorGroup.classes or {}) do
            local entry = { classInfo = classInfo, specs = {} }
            classEntries[#classEntries + 1] = entry
            classByToken[classInfo.token] = entry
        end
        for _, spec in ipairs(armorGroup.specs or {}) do
            local token = spec.classInfo and spec.classInfo.token
            local entry = token and classByToken[token]
            if not entry then
                entry = {
                    classInfo = spec.classInfo or {
                        token = token or "UNKNOWN",
                        name = token or Text("settings.config_sets.spec.unknown_class", "其他"),
                    },
                    specs = {},
                }
                classEntries[#classEntries + 1] = entry
                if token then classByToken[token] = entry end
            end
            entry.specs[#entry.specs + 1] = spec
        end

        local rowHeight = 94
        for classIndex, entry in ipairs(classEntries) do
            local column = (classIndex - 1) % 3
            local rowIndex = math_floor((classIndex - 1) / 3)
            cardIndex = cardIndex + 1
            local card = dialog.assignmentCards[cardIndex]
            if not card then
                card = GUI2:CreatePanel(dialog.specContent, {
                    width = cardWidth,
                    height = rowHeight,
                    surface = "color.surface.panel",
                    border = "color.border.subtle",
                })
                local classTitle = GUI2:CreateText(
                    card,
                    "",
                    "font.size.sm",
                    "color.text.heading",
                    "LEFT"
                )
                classTitle:SetPoint("TOPLEFT", 10, -8)
                classTitle:SetPoint("TOPRIGHT", -10, -8)
                card.classTitle = classTitle
                dialog.assignmentCards[cardIndex] = card
            end
            card:ClearAllPoints()
            card:SetPoint(
                "TOPLEFT",
                column * (cardWidth + UNIFIED_SPEC_CARD_GAP),
                y - rowIndex * (rowHeight + UNIFIED_SPEC_CARD_GAP)
            )
            card.classTitle:SetText(entry.classInfo.name or entry.classInfo.token or "")
            card:Show()

            for specIndex, spec in ipairs(entry.specs) do
                local specColumn = (specIndex - 1) % 2
                local specRow = math_floor((specIndex - 1) / 2)
                local specKey = spec.key
                checkboxIndex = checkboxIndex + 1
                local checkbox = dialog.assignmentChecks[checkboxIndex]
                if not checkbox then
                    checkbox = GUI2.Form:CreateCheckbox(dialog.specContent, {
                        width = UNIFIED_SPEC_CHECK_WIDTH,
                        height = 26,
                        text = "",
                        onClick = function(control, checked)
                            Picker.assignmentDraftSpecs[control.specKey] = checked and true or nil
                            Picker:RefreshAssignmentDialogLayout()
                        end,
                    })
                    dialog.assignmentChecks[checkboxIndex] = checkbox
                end
                checkbox:SetParent(card)
                checkbox:ClearAllPoints()
                checkbox:SetPoint(
                    "TOPLEFT",
                    10 + specColumn * (UNIFIED_SPEC_CHECK_WIDTH + 6),
                    -32 - specRow * 27
                )
                checkbox.specKey = specKey
                checkbox.text:SetText(spec.displayName or spec.name or tostring(spec.specID or ""))
                checkbox:SetChecked(self.assignmentDraftSpecs[specKey] == true, true)
                checkbox:Show()
                self.assignmentSpecControls[#self.assignmentSpecControls + 1] = checkbox
                self.assignmentSpecOrder[#self.assignmentSpecOrder + 1] = specKey
            end
        end
        local classRows = math_max(1, math.ceil(#classEntries / 3))
        y = y - classRows * (rowHeight + UNIFIED_SPEC_CARD_GAP) - 10
    end

    dialog.specContent:SetSize(innerWidth, math_max(math_abs(y) + 12, 300))
    dialog.specScroll:SetVerticalScroll(0)
end

function Picker:BuildAssignmentDialog(parent)
    local mask = CreateUnifiedModalMask(parent, 30)
    mask:SetScript("OnMouseUp", function() end)

    local panel = GUI2:CreatePanel(mask, {
        width = 720,
        height = 500,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetPoint("CENTER")
    panel:SetFrameLevel(mask:GetFrameLevel() + 2)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseUp", function() end)

    local title = GUI2:CreateText(panel, "", "font.size.title", "color.text.heading", "LEFT")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetPoint("TOPRIGHT", -54, -18)

    local close = GUI2:CreateCloseButton(panel, function()
        Picker:CloseAssignmentDialog()
    end)
    close:SetPoint("TOPRIGHT", -18, -18)

    local mode = GUI2.Form:CreateSegmentedControl(panel, {
        width = 680,
        height = 34,
        items = {
            {
                text = Text("settings.config_sets.assignment.default", "默认"),
                value = "default",
            },
            {
                text = Text("settings.config_sets.assignment.specs", "指定专精"),
                value = "specs",
            },
            {
                text = Text("settings.config_sets.assignment.none", "无"),
                value = "none",
            },
        },
        get = function()
            return Picker.assignmentDraftMode or "none"
        end,
        set = function(value)
            Picker.assignmentDraftMode = value
            if Picker.assignmentDialog and Picker.assignmentDialog.statusText then
                Picker.assignmentDialog.statusText:SetText("")
            end
            Picker:RefreshAssignmentDialogLayout()
        end,
    })
    mode:SetPoint("TOPLEFT", 20, -52)

    local toolbar = GUI2:CreateFrame(panel, {
        width = 680,
        height = 30,
    })
    toolbar:SetPoint("TOPLEFT", 20, -98)
    local toolbarTitle = GUI2:CreateText(
        toolbar,
        Text("settings.config_sets.assignment.specs", "指定专精"),
        "font.size.md",
        "color.text.heading",
        "LEFT"
    )
    toolbarTitle:SetPoint("LEFT", 0, 0)
    local summary = GUI2:CreateText(toolbar, "", "font.size.sm", "color.text.secondary", "LEFT")
    summary:SetPoint("LEFT", toolbarTitle, "RIGHT", 10, 0)
    local clear = CreateButton(toolbar, {
        width = 70,
        height = 26,
        text = Text("settings.config_sets.assignment.clear", "清空"),
        tone = "default",
        onClick = function()
            Picker:SetAllAssignmentSpecs(false)
        end,
    })
    clear:SetPoint("RIGHT", -0, 0)
    local selectAll = CreateButton(toolbar, {
        width = 70,
        height = 26,
        text = Text("settings.config_sets.assignment.select_all", "全选"),
        tone = "default",
        onClick = function()
            Picker:SetAllAssignmentSpecs(true)
        end,
    })
    selectAll:SetPoint("RIGHT", clear, "LEFT", -8, 0)

    local scroll = GUI2:CreateScrollFrame(panel, {
        template = "UIPanelScrollFrameTemplate",
        width = 680,
        height = 308,
        childWidth = 670,
        childHeight = 308,
    })
    scroll:SetPoint("TOPLEFT", 20, -132)

    local status = GUI2:CreateText(panel, "", "font.size.sm", "color.state.error", "LEFT")
    status:SetPoint("BOTTOMLEFT", 20, 24)
    status:SetWidth(470)
    status:SetWordWrap(false)

    local cancel = CreateButton(panel, {
        width = 86,
        height = 28,
        text = Text("settings.config_sets.cancel", "取消"),
        tone = "default",
        onClick = function()
            Picker:CloseAssignmentDialog()
        end,
    })
    cancel:SetPoint("BOTTOMRIGHT", -116, 18)
    local save = CreateButton(panel, {
        width = 86,
        height = 28,
        text = Text("settings.config_sets.save", "保存"),
        tone = "accent",
        onClick = function()
            Picker:SaveAssignment()
        end,
    })
    save:SetPoint("BOTTOMRIGHT", -20, 18)

    self.assignmentDialog = {
        mask = mask,
        panel = panel,
        titleText = title,
        modeControl = mode,
        specToolbar = toolbar,
        summaryText = summary,
        specScroll = scroll,
        specContent = scroll.child,
        statusText = status,
        cancelButton = cancel,
        saveButton = save,
    }
end

function Picker:OpenAssignmentDialog(item)
    if not self.specializationAssignmentsEnabled
        or not item
        or not self.assignmentDialog
    then
        return
    end
    if item.assignment and item.assignment.mode == "default" then return end
    self.assignmentReference = { kind = item.kind, id = item.id }
    self.assignmentDraftMode = item.assignment and item.assignment.mode or "none"
    self.assignmentDraftSpecs = {}
    for _, specKey in ipairs(item.assignment and item.assignment.specKeys or {}) do
        self.assignmentDraftSpecs[specKey] = true
    end
    self.assignmentDialog.titleText:SetText(
        Text("settings.config_sets.assignment.title", "适用专精")
            .. " · "
            .. ResolveItemName(item)
    )
    self.assignmentDialog.statusText:SetText("")
    self:RenderAssignmentSpecs()
    self.assignmentDialog.modeControl:SetValue(self.assignmentDraftMode, true)
    self:RefreshAssignmentDialogLayout()
    self:ShowUnifiedModal(self.assignmentDialog.mask)
end

function Picker:CloseAssignmentDialog()
    if self.assignmentDialog then
        self.assignmentDialog.statusText:SetText("")
        self:HideUnifiedModal(self.assignmentDialog.mask)
    end
    self.assignmentReference = nil
    self.assignmentDraftMode = nil
    self.assignmentDraftSpecs = {}
    self.assignmentSpecControls = {}
    self.assignmentSpecOrder = {}
end

function Picker:SaveAssignment()
    local manager = GetManager()
    local reference = UnifiedCopyReference(self.assignmentReference)
    if not manager or not reference or type(manager.SetAssignment) ~= "function" then return end
    local mode = self.assignmentDraftMode or "none"
    local specKeys = mode == "specs" and self:CollectAssignmentSpecKeys() or {}
    if mode == "specs" and #specKeys == 0 then
        self.assignmentDialog.statusText:SetText(
            Text("settings.config_sets.error.spec_required", "请至少选择一个专精，或改为“无”。")
        )
        GUI2:SetTextColorKey(self.assignmentDialog.statusText, "color.state.error")
        return
    end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:SetAssignment(providerId, reference, mode, specKeys)
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog(reference.kind, reference.id) end
        self.assignmentDialog.statusText:SetText(ErrorText(code))
        GUI2:SetTextColorKey(self.assignmentDialog.statusText, "color.state.error")
        return
    end
    self:CloseAssignmentDialog()
    self:RefreshCatalog(reference.kind, reference.id)
    local item = self:GetUnifiedItem(reference)
    self:SetStatus(
        UnifiedFormat(
            "settings.config_sets.assignment.saved",
            "已保存“%s”的适用专精设置。",
            item and ResolveItemName(item) or reference.id
        ),
        "color.state.success"
    )
end

function Picker:BuildSpecializationPreviewDialog(parent)
    local mask = CreateUnifiedModalMask(parent, 30)
    mask:SetScript("OnMouseUp", function()
        Picker:CloseSpecializationPreview()
    end)

    local panel = GUI2:CreatePanel(mask, {
        width = 560,
        height = 420,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetPoint("CENTER")
    panel:SetFrameLevel(mask:GetFrameLevel() + 2)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseUp", function() end)

    local title = GUI2:CreateText(
        panel,
        Text("settings.config_sets.spec_preview.title", "专精预览"),
        "font.size.title",
        "color.text.heading",
        "LEFT"
    )
    title:SetPoint("TOPLEFT", 20, -18)
    local close = GUI2:CreateCloseButton(panel, function()
        Picker:CloseSpecializationPreview()
    end)
    close:SetPoint("TOPRIGHT", -18, -18)

    local scroll = GUI2:CreateScrollFrame(panel, {
        template = "UIPanelScrollFrameTemplate",
        width = 520,
        height = 340,
        childWidth = 510,
        childHeight = 340,
    })
    scroll:SetPoint("TOPLEFT", 20, -58)
    self.specializationPreviewDialog = {
        mask = mask,
        panel = panel,
        scroll = scroll,
        content = scroll.child,
    }
end

function Picker:OpenSpecializationPreview()
    if not self.specializationPreviewDialog and self.frame then
        local frame = self.frame
        self:BuildSpecializationPreviewDialog(frame)
        self:RefreshUnifiedFrameLevels()
    end
    local dialog = self.specializationPreviewDialog
    if not dialog or not self.hasSpecializationAssignments then return end
    dialog.rows = dialog.rows or {}
    for _, row in ipairs(dialog.rows) do row:Hide() end

    local specializationLabels = {}
    for _, armorGroup in ipairs(self.specializationGroups or {}) do
        for _, spec in ipairs(armorGroup.specs or {}) do
            local reference = self.bySpecialization[spec.key]
            local referenceKey = UnifiedReferenceKey(reference)
            if referenceKey then
                specializationLabels[referenceKey] = specializationLabels[referenceKey] or {}
                local labels = specializationLabels[referenceKey]
                labels[#labels + 1] = UnifiedSpecLabel(
                    self.specializationGroups,
                    spec.key,
                    true
                )
            end
        end
    end

    local function AcquireRow()
        local index = (dialog.activeRowCount or 0) + 1
        dialog.activeRowCount = index
        local row = dialog.rows[index]
        if not row then
            row = GUI2:CreatePanel(dialog.content, {
                width = 490,
                height = 36,
                surface = "color.surface.panel",
                border = "color.border.subtle",
            })
            local name = GUI2:CreateText(
                row,
                "",
                "font.size.sm",
                "color.text.accent",
                "LEFT"
            )
            name:SetPoint("TOPLEFT", 10, -10)
            name:SetWidth(150)
            name:SetWordWrap(false)
            row.nameText = name
            local details = GUI2:CreateText(
                row,
                "",
                "font.size.sm",
                "color.text.primary",
                "LEFT"
            )
            details:SetPoint("TOPLEFT", 170, -10)
            details:SetWidth(310)
            details:SetWordWrap(true)
            row.detailsText = details
            dialog.rows[index] = row
        end
        row:Show()
        return row
    end

    local function BindRow(item, details, isDefault, y)
        local row = AcquireRow()
        row.nameText:SetText(ResolveItemName(item))
        row.detailsText:SetText(details)
        local textHeight = type(row.detailsText.GetStringHeight) == "function"
            and row.detailsText:GetStringHeight()
            or 16
        local rowHeight = math_max(36, math.ceil(textHeight or 16) + 20)
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, y)
        GUI2:ApplyBackdrop(
            row,
            isDefault and "color.control.active" or "color.surface.panel"
        )
        GUI2:SetBorderColor(
            row,
            isDefault and "color.border.accent" or "color.border.subtle"
        )
        return rowHeight
    end

    dialog.activeRowCount = 0
    local y = 0
    for _, item in ipairs(self.allItems or {}) do
        local labels = specializationLabels[UnifiedReferenceKey(item)]
        if labels and #labels > 0 then
            local rowHeight = BindRow(
                item,
                table_concat(labels, Text("settings.config_sets.scope_separator", "、")),
                false,
                y
            )
            y = y - rowHeight - 6
        end
    end

    local defaultReference = self.assignmentSnapshot
        and (self.assignmentSnapshot.defaultReference or self.assignmentSnapshot.default)
    local defaultItem = self:GetUnifiedItem(defaultReference)
    if defaultItem then
        local rowHeight = BindRow(
            defaultItem,
            Text("settings.config_sets.assignment.default_fallback", "默认（未匹配指定专精时使用）"),
            true,
            y
        )
        y = y - rowHeight - 6
    end

    local contentHeight = math_max(1, math_abs(y) + 6)
    dialog.content:SetSize(510, contentHeight)
    dialog.scroll:SetVerticalScroll(0)
    local scrollBar = dialog.scroll.ScrollBar
    if scrollBar then
        local overflow = contentHeight > dialog.scroll:GetHeight()
        UnifiedSetShown(scrollBar, overflow)
        UnifiedSetShown(scrollBar.gui2TrackLine, overflow)
        UnifiedSetShown(scrollBar.visualThumb, overflow)
        if overflow and scrollBar.UpdateVisualThumb then
            scrollBar:UpdateVisualThumb()
        end
    end
    self:ShowUnifiedModal(dialog.mask)
end

function Picker:CloseSpecializationPreview()
    if self.specializationPreviewDialog then
        self:HideUnifiedModal(self.specializationPreviewDialog.mask)
    end
end

function Picker:GetEditorSourceItems(mode)
    if mode == "builtin" then return self.builtins or {} end
    if mode == "user" then return self.userSets or {} end
    return {}
end

function Picker:ApplyEditorSourceSelection(sourceId)
    self.editorSourceId = sourceId
    if self.editorMode ~= "create" or self.editorSourceMode == "current" then return end
    if self.userSetScopePolicy == "all" then return end

    local sourceItem
    for _, item in ipairs(self:GetEditorSourceItems(self.editorSourceMode)) do
        if item.id == sourceId then
            sourceItem = item
            break
        end
    end
    self.editorScopeSelection = {}
    if sourceItem then
        for _, scopeId in ipairs(sourceItem.scopeIds or {}) do
            self.editorScopeSelection[scopeId] = true
        end
    end
    self:RenderEditorScopes()
end

function Picker:RefreshEditorSourceState()
    local dialog = self.editorDialog
    if not dialog then return end
    local creating = self.editorMode == "create"
    UnifiedSetShown(dialog.sourceLabel, creating)
    UnifiedSetShown(
        dialog.sourceModeControl,
        creating and not self.editableUserSets
    )
    UnifiedSetShown(
        dialog.sourceDropdown,
        creating and (self.editableUserSets or self.editorSourceMode ~= "current")
    )
    UnifiedSetShown(
        dialog.sourcePreviewButton,
        creating and self.editableUserSets
    )
    if creating and self.editableUserSets then
        dialog.sourceLabel:SetText(
            Text("settings.config_sets.create.builtin", "预设方案")
        )
        dialog.sourceDropdown:ClearAllPoints()
        dialog.sourceDropdown:SetPoint("TOPLEFT", 24, -204)
        dialog.sourceDropdown:SetWidth(474)
    else
        dialog.sourceLabel:SetText(
            Text("settings.config_sets.create.source", "创建来源")
        )
        dialog.sourceDropdown:ClearAllPoints()
        dialog.sourceDropdown:SetPoint("TOPLEFT", 24, -240)
        dialog.sourceDropdown:SetWidth(512)
    end

    local sourceItems = self:GetEditorSourceItems(self.editorSourceMode)
    self.editorSourceOptions = {}
    for _, item in ipairs(sourceItems) do
        self.editorSourceOptions[#self.editorSourceOptions + 1] = {
            text = ResolveItemName(item),
            value = item.id,
        }
    end
    local validSource = false
    for _, option in ipairs(self.editorSourceOptions) do
        if option.value == self.editorSourceId then
            validSource = true
            break
        end
    end
    local previousSourceId = self.editorSourceId
    if not validSource then
        local defaultSourceId = self.editorSourceOptions[1]
            and self.editorSourceOptions[1].value
            or nil
        self.editorSourceId = defaultSourceId
    end
    dialog.sourceDropdown:SetValue(self.editorSourceId, true)
    dialog.sourceDropdown:SetDisabled(#self.editorSourceOptions == 0)
    if dialog.sourcePreviewButton then
        local hasPreview = false
        for _, item in ipairs(sourceItems) do
            if item.id == self.editorSourceId and self:GetPreviewTexture(item) then
                hasPreview = true
                break
            end
        end
        UnifiedSetShown(dialog.sourcePreviewButton, creating and self.editableUserSets and hasPreview)
        dialog.sourcePreviewButton:SetDisabled(not hasPreview)
        if creating and self.editableUserSets then
            dialog.sourceDropdown:SetWidth(hasPreview and 474 or 512)
        end
        if not hasPreview then self:CloseEditorSourcePreview() end
    end
    if creating
        and self.editorSourceMode ~= "current"
        and previousSourceId ~= self.editorSourceId
    then
        self:ApplyEditorSourceSelection(self.editorSourceId)
    end
end

function Picker:RenderEditorScopes()
    local dialog = self.editorDialog
    if not dialog then return end
    dialog.scopeControls = dialog.scopeControls or {}
    for _, control in ipairs(dialog.scopeControls) do control:Hide() end
    local hideScopes = self.userSetScopePolicy == "all"
        or (self.editorMode == "create" and self.editableUserSets)
    UnifiedSetShown(dialog.scopeLabel, not hideScopes)
    UnifiedSetShown(dialog.scopeContent, not hideScopes)
    if hideScopes then return end
    local restrictToSource = self.editorMode == "create"
        and self.editorSourceMode ~= "current"
    local sourceScopeIds = {}
    if restrictToSource then
        for _, item in ipairs(self:GetEditorSourceItems(self.editorSourceMode)) do
            if item.id == self.editorSourceId then
                for _, scopeId in ipairs(item.scopeIds or {}) do
                    sourceScopeIds[scopeId] = true
                end
                break
            end
        end
    end
    for index, scope in ipairs(self.scopes or {}) do
        local column = (index - 1) % 2
        local row = math_floor((index - 1) / 2)
        local sourceAllowsScope = not restrictToSource or sourceScopeIds[scope.id] == true
        local control = dialog.scopeControls[index]
        if not control then
            control = GUI2.Form:CreateCheckbox(dialog.scopeContent, {
                width = 225,
                height = 28,
                text = "",
                onClick = function(checkbox, checked)
                    if checkbox.sourceAllowsScope == false then return end
                    Picker.editorScopeSelection[checkbox.scopeId] = checked and true or nil
                end,
            })
            dialog.scopeControls[index] = control
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", column * 238, -(row * 30))
        control.scopeId = scope.id
        control.sourceAllowsScope = sourceAllowsScope
        control.text:SetText(ResolveScopeLabel(scope))
        control:SetChecked(
            sourceAllowsScope and self.editorScopeSelection[scope.id] == true,
            true
        )
        control:SetDisabled(not sourceAllowsScope)
        control:Show()
    end
end

function Picker:BuildUnifiedEditorDialog(parent)
    local mask = CreateUnifiedModalMask(parent, 30)
    mask:SetScript("OnMouseUp", function() end)

    local panel = GUI2:CreatePanel(mask, {
        width = UNIFIED_EDITOR_WIDTH,
        height = UNIFIED_EDITOR_HEIGHT,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetPoint("CENTER")
    panel:SetFrameLevel(mask:GetFrameLevel() + 2)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseUp", function() end)

    local title = GUI2:CreateText(panel, "", "font.size.title", "color.text.heading", "LEFT")
    title:SetPoint("TOPLEFT", 24, -20)
    local close = GUI2:CreateCloseButton(panel, function()
        Picker:CloseUnifiedEditor()
    end)
    close:SetPoint("TOPRIGHT", -18, -18)

    local nameLabel = GUI2:CreateText(
        panel,
        Text("settings.config_sets.name", "名称"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    nameLabel:SetPoint("TOPLEFT", 24, -62)
    local nameEdit = GUI2.Form:CreateEditBox(panel, {
        width = 512,
        height = 30,
        text = "",
        autoFocus = false,
    })
    nameEdit:SetPoint("TOPLEFT", 24, -82)

    local descriptionLabel = GUI2:CreateText(
        panel,
        Text("settings.config_sets.description", "说明"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    descriptionLabel:SetPoint("TOPLEFT", 24, -122)
    local descriptionEdit = GUI2.Form:CreateEditBox(panel, {
        width = 512,
        height = 30,
        text = "",
        autoFocus = false,
    })
    descriptionEdit:SetPoint("TOPLEFT", 24, -142)

    local sourceLabel = GUI2:CreateText(
        panel,
        Text("settings.config_sets.create.source", "创建来源"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    sourceLabel:SetPoint("TOPLEFT", 24, -184)
    local sourceMode = GUI2.Form:CreateSegmentedControl(panel, {
        width = 512,
        height = 30,
        items = {
            {
                text = Text("settings.config_sets.create.current", "当前配置"),
                value = "current",
            },
            {
                text = Text("settings.config_sets.create.builtin", "内置方案"),
                value = "builtin",
            },
            {
                text = Text("settings.config_sets.create.personal", "个人方案"),
                value = "user",
            },
        },
        get = function()
            return Picker.editorSourceMode or "current"
        end,
        set = function(value)
            Picker.editorSourceMode = value
            Picker.editorSourceId = nil
            if value == "current" then
                Picker.editorScopeSelection = {}
                for _, scope in ipairs(Picker.scopes or {}) do
                    Picker.editorScopeSelection[scope.id] = true
                end
                Picker:RenderEditorScopes()
            end
            Picker:RefreshEditorSourceState()
        end,
    })
    sourceMode:SetPoint("TOPLEFT", 24, -204)

    local sourceDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 512,
        height = 30,
        placeholder = Text("settings.config_sets.create.select_source", "选择要复制的方案"),
        options = function()
            return Picker.editorSourceOptions or {}
        end,
        get = function()
            return Picker.editorSourceId
        end,
        set = function(value)
            Picker:ApplyEditorSourceSelection(value)
        end,
    })
    sourceDropdown:SetPoint("TOPLEFT", 24, -240)
    local sourcePreview = self:CreateUnifiedActionButton(
        panel,
        "eye",
        Text("settings.config_sets.zoom_preview", "预览"),
        function()
            Picker:OpenEditorSourcePreview()
        end,
        false,
        30
    )
    sourcePreview:SetPoint("TOPRIGHT", -24, -204)
    sourcePreview:Hide()

    local scopeLabel = GUI2:CreateText(
        panel,
        Text("settings.config_sets.content_scope", "包含内容"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    scopeLabel:SetPoint("TOPLEFT", 24, -284)
    local scopeContent = GUI2:CreateFrame(panel, {
        width = 490,
        height = 96,
    })
    scopeContent:SetPoint("TOPLEFT", 24, -306)

    local status = GUI2:CreateText(panel, "", "font.size.sm", "color.state.error", "LEFT")
    status:SetPoint("BOTTOMLEFT", 24, 24)
    status:SetWidth(330)

    local cancel = CreateButton(panel, {
        width = 86,
        height = 28,
        text = Text("settings.config_sets.cancel", "取消"),
        tone = "default",
        onClick = function()
            Picker:CloseUnifiedEditor()
        end,
    })
    cancel:SetPoint("BOTTOMRIGHT", -118, 18)
    local save = CreateButton(panel, {
        width = 86,
        height = 28,
        text = Text("settings.config_sets.save", "保存"),
        tone = "accent",
        onClick = function()
            Picker:SaveUnifiedEditor()
        end,
    })
    save:SetPoint("BOTTOMRIGHT", -22, 18)

    local previewMask = GUI2:CreateFrame(mask, {
        allPoints = true,
        mouse = true,
        hidden = true,
    })
    previewMask:SetFrameLevel(panel:GetFrameLevel() + 10)
    previewMask:SetScript("OnMouseUp", function()
        Picker:CloseEditorSourcePreview()
    end)
    local previewShade = GUI2:CreateTexture(previewMask, nil, "BACKGROUND")
    GUI2:SetTexturePaintKey(previewShade, "color.overlay.shadow")
    previewShade:SetAllPoints()
    local previewPanel = GUI2:CreatePanel(previewMask, {
        width = 512,
        height = 288,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    previewPanel:SetPoint("CENTER")
    previewPanel:SetFrameLevel(previewMask:GetFrameLevel() + 2)
    previewPanel:EnableMouse(true)
    previewPanel:SetScript("OnMouseUp", function() end)
    local previewTexture = GUI2:CreateTexture(previewPanel, { layer = "ARTWORK" })
    previewTexture:SetAllPoints(previewPanel)
    previewTexture:SetTexCoord(0, 1, 0, 1)
    previewTexture:Hide()
    local previewClose = GUI2:CreateCloseButton(previewPanel, function()
        Picker:CloseEditorSourcePreview()
    end)
    previewClose:SetPoint("TOPRIGHT", -10, -10)
    previewClose:SetFrameLevel(previewPanel:GetFrameLevel() + 3)

    self.editorDialog = {
        mask = mask,
        panel = panel,
        titleText = title,
        nameEdit = nameEdit,
        descriptionEdit = descriptionEdit,
        sourceLabel = sourceLabel,
        sourceModeControl = sourceMode,
        sourceDropdown = sourceDropdown,
        sourcePreviewButton = sourcePreview,
        previewMask = previewMask,
        previewPanel = previewPanel,
        previewTexture = previewTexture,
        previewCloseButton = previewClose,
        scopeLabel = scopeLabel,
        scopeContent = scopeContent,
        scopeControls = {},
        statusText = status,
        cancelButton = cancel,
        saveButton = save,
    }
end

function Picker:OpenUnifiedEditor(mode, item)
    if not self.editorDialog and self.frame then
        local frame = self.frame
        self:BuildUnifiedEditorDialog(frame)
        self:RefreshUnifiedFrameLevels()
        self:RefreshStaticText()
    end
    local dialog = self.editorDialog
    if not dialog then return end
    self.editorMode = mode == "edit" and "edit" or "create"
    self.editorReference = item and { kind = item.kind, id = item.id } or nil
    self.editorSourceMode = self.editorMode == "create" and self.editableUserSets
        and "builtin"
        or "current"
    self.editorSourceId = nil
    self.editorScopeSelection = {}
    self:CloseEditorSourcePreview()
    dialog.panel:SetHeight(
        self.userSetScopePolicy == "all"
            and (self.editorMode == "create" and 350 or 260)
            or (self.editorMode == "create" and self.editableUserSets and 350 or 460)
    )

    if self.editorMode == "edit" and item then
        dialog.titleText:SetText(Text("settings.config_sets.edit", "编辑"))
        dialog.nameEdit:SetValue(item.name or "", true)
        dialog.descriptionEdit:SetValue(item.description or "", true)
        for _, scopeId in ipairs(item.scopeIds or {}) do
            self.editorScopeSelection[scopeId] = true
        end
        self.editorOriginalScopeIds = CopyArray(item.scopeIds)
    else
        dialog.titleText:SetText(Text("settings.config_sets.create", "新建方案"))
        dialog.nameEdit:SetValue("", true)
        dialog.descriptionEdit:SetValue("", true)
        for _, scope in ipairs(self.scopes or {}) do
            self.editorScopeSelection[scope.id] = true
        end
        self.editorOriginalScopeIds = nil
    end

    dialog.statusText:SetText("")
    dialog.sourceModeControl:SetValue(self.editorSourceMode, true)
    self:RefreshEditorSourceState()
    self:RenderEditorScopes()
    self:ShowUnifiedModal(dialog.mask)
    dialog.nameEdit:SetFocus()
    dialog.nameEdit:HighlightText()
end

function Picker:CloseUnifiedEditor()
    local dialog = self.editorDialog
    if dialog then
        self:CloseEditorSourcePreview()
        if dialog.nameEdit.ClearFocus then dialog.nameEdit:ClearFocus() end
        if dialog.descriptionEdit.ClearFocus then dialog.descriptionEdit:ClearFocus() end
        self:HideUnifiedModal(dialog.mask)
    end
    self.editorMode = nil
    self.editorReference = nil
    self.editorSourceMode = nil
    self.editorSourceId = nil
    self.editorSourceOptions = {}
    self.editorScopeSelection = {}
    self.editorOriginalScopeIds = nil
    self.editorPreviewOpen = nil
end

function Picker:SaveUnifiedEditor()
    local dialog = self.editorDialog
    local manager = GetManager()
    if not dialog or not manager then return end
    local name = Trim(dialog.nameEdit:GetText())
    if name == "" then
        dialog.statusText:SetText(Text("settings.config_sets.error.name_required", "请输入方案名称。"))
        return
    end
    if self.editorMode == "create"
        and self.editorSourceMode ~= "current"
        and not self.editorSourceId
    then
        dialog.statusText:SetText(
            Text("settings.config_sets.error.source_required", "请选择一个要复制的方案。")
        )
        return
    end

    local scopeIds
    if self.userSetScopePolicy ~= "all" then
        scopeIds = {}
        for _, scope in ipairs(self.scopes or {}) do
            if self.editorScopeSelection[scope.id] then
                scopeIds[#scopeIds + 1] = scope.id
            end
        end
        if #scopeIds == 0 then
            dialog.statusText:SetText(
                Text("settings.config_sets.error.scope_required", "请至少选择一项包含内容。")
            )
            return
        end
    end

    local payload = {
        name = name,
        description = Trim(dialog.descriptionEdit:GetText()),
        owner = self.undoOwner,
        configurationMode = self.configurationMode,
    }
    if scopeIds then payload.scopeIds = scopeIds end
    local wasEditing = self.editorMode == "edit" and self.editorReference ~= nil
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local result, code
    if not wasEditing and (self.editableUserSets or self.editorSourceMode ~= "current") then
        local sourceKind = self.editableUserSets
            and "builtin"
            or self.editorSourceMode == "builtin" and "builtin"
            or "user"
        payload.source = {
            kind = sourceKind,
            id = self.editorSourceId,
        }
    end
    self:BeginSessionMutation(providerId, sessionToken)
    if wasEditing then
        local recapture = scopeIds
            and #scopeIds ~= #(self.editorOriginalScopeIds or {})
            or false
        if not recapture then
            for index, scopeId in ipairs(scopeIds or {}) do
                if scopeId ~= self.editorOriginalScopeIds[index] then
                    recapture = true
                    break
                end
            end
        end
        result, code = manager:UpdateUserSet(
            providerId,
            self.editorReference.id,
            payload,
            recapture
        )
    else
        result, code = manager:CreateUserSet(providerId, payload)
    end
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)

    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog(self.selectedKind, self.selectedId) end
        dialog.statusText:SetText(ErrorText(code))
        return
    end
    self:CloseUnifiedEditor()
    self:RefreshCatalog("user", result.id)
    self:SetStatus(
        UnifiedFormat(
            wasEditing
                and "settings.config_sets.updated"
                or "settings.config_sets.saved",
            wasEditing and "已更新“%s”。" or "已保存“%s”。",
            ResolveItemName(result)
        ),
        "color.state.success"
    )
end

function Picker:BuildUnifiedListPage(parent)
    local info = GUI2:CreatePanel(parent, {
        width = UNIFIED_LIST_WIDTH,
        height = 42,
        surface = "color.surface.sunken",
        border = "color.border.subtle",
    })
    info:SetPoint("TOPLEFT", 24, -50)
    self.contextInfoPanel = info

    local configurationModeControl = GUI2.Form:CreateSegmentedControl(info, {
        width = 220,
        height = 28,
        items = {
            {
                text = Text(
                    "settings.config_sets.mode.unified",
                    "账号统一配置"
                ),
                value = "unified",
            },
            {
                text = Text(
                    "settings.config_sets.mode.specialization",
                    "专精独立配置"
                ),
                value = "specialization",
            },
        },
        value = "specialization",
        set = function(value)
            Picker:SetConfigurationMode(value)
        end,
    })
    configurationModeControl:SetPoint("CENTER")
    configurationModeControl:Hide()
    self.configurationModeControl = configurationModeControl

    local currentLabel = GUI2:CreateText(
        info,
        Text("settings.config_sets.current_spec", "当前专精："),
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    currentLabel:SetPoint("LEFT", 14, 0)
    self.currentSpecLabel = currentLabel
    local currentValue = GUI2:CreateText(info, "", "font.size.md", "color.text.accent", "LEFT")
    currentValue:SetPoint("LEFT", currentLabel, "RIGHT", 5, 0)
    currentValue:SetWidth(130)
    currentValue:SetWordWrap(false)
    self.currentSpecText = currentValue

    local separator = GUI2:CreateTexture(info, "color.border.subtle", "ARTWORK")
    separator:SetPoint("TOPLEFT", 320, -8)
    separator:SetPoint("BOTTOMLEFT", 320, 8)
    separator:SetWidth(GUI2:GetPixelSize(info, 1, 1))
    self.contextSeparator = separator

    local activeLabel = GUI2:CreateText(
        info,
        Text("settings.config_sets.active", "正在使用："),
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    activeLabel:SetPoint("LEFT", 340, 0)
    self.activeSetLabel = activeLabel
    local activeValue = GUI2:CreateText(info, "", "font.size.md", "color.text.accent", "LEFT")
    activeValue:SetPoint("LEFT", activeLabel, "RIGHT", 5, 0)
    activeValue:SetWidth(220)
    activeValue:SetWordWrap(false)
    self.activeSetText = activeValue

    local preview = CreateButton(info, {
        width = 104,
        height = 26,
        text = Text("settings.config_sets.spec_preview", "专精预览"),
        tone = "default",
        onClick = function()
            Picker:OpenSpecializationPreview()
        end,
    })
    preview:SetPoint("RIGHT", -8, 0)
    self.specPreviewButton = preview

    local toolbar = GUI2:CreateFrame(parent, {
        width = UNIFIED_LIST_WIDTH,
        height = 30,
    })
    toolbar:SetPoint("TOPLEFT", 24, -96)
    self.unifiedToolbar = toolbar
    local schemeTitle = GUI2:CreateText(
        toolbar,
        Text("settings.config_sets.scheme", "方案"),
        "font.size.md",
        "color.text.accent",
        "LEFT"
    )
    schemeTitle:SetPoint("LEFT", 0, 0)
    self.schemeTitleText = schemeTitle
    if self.totalCountText then
        self.totalCountText:ClearAllPoints()
        self.totalCountText:SetPoint("LEFT", schemeTitle, "RIGHT", 8, 0)
    end

    local hideUnused = CreateButton(toolbar, {
        width = 174,
        height = 28,
        text = Text("settings.config_sets.hide_unused_builtins", "隐藏未使用的预设方案"),
        tone = "default",
        onClick = function()
            Picker:SetHideUnusedBuiltins(not Picker.hideUnusedBuiltins)
        end,
    })
    self.hideUnusedButton = hideUnused

    local import = CreateButton(toolbar, {
        width = 76,
        height = 28,
        text = Text("settings.config_sets.import", "导入"),
        tone = "default",
        onClick = function()
            Picker:OpenImportDialog()
        end,
    })
    import:SetPoint("RIGHT", -0, 0)
    self.importButton = import

    local create = CreateButton(toolbar, {
        width = 76,
        height = 28,
        text = Text("settings.config_sets.create", "新建"),
        tone = "default",
        onClick = function()
            Picker:OpenUnifiedEditor("create")
        end,
    })
    create:SetPoint("RIGHT", import, "LEFT", -8, 0)
    self.createButton = create
    hideUnused:SetPoint("RIGHT", create, "LEFT", -8, 0)

    local headers = GUI2:CreateFrame(parent, {
        width = UNIFIED_LIST_WIDTH - 12,
        height = 20,
    })
    headers:SetPoint("TOPLEFT", 24, -130)
    self.unifiedHeaders = headers
    local nameHeader = GUI2:CreateText(
        headers,
        Text("settings.config_sets.scheme", "方案"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    nameHeader:SetPoint("LEFT", 12, 0)
    nameHeader:SetWidth(UNIFIED_NAME_WIDTH)
    local assignmentHeader = GUI2:CreateText(
        headers,
        Text("settings.config_sets.assignment.title", "适用专精"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    assignmentHeader:SetPoint("LEFT", UNIFIED_NAME_WIDTH + 8, 0)
    assignmentHeader:SetWidth(UNIFIED_ASSIGNMENT_WIDTH)
    self.assignmentHeaderText = assignmentHeader
    local actionHeader = GUI2:CreateText(
        headers,
        Text("settings.config_sets.actions", "操作"),
        "font.size.sm",
        "color.text.secondary",
        "CENTER"
    )
    actionHeader:SetPoint("RIGHT", -8, 0)
    actionHeader:SetWidth(
        (UNIFIED_ACTION_SIZE * 5) + (UNIFIED_ACTION_GAP * 4)
    )

    local viewport = GUI2:CreateFrame(parent, {
        width = UNIFIED_LIST_WIDTH,
        height = UNIFIED_LIST_HEIGHT,
        mouse = true,
        mouseWheel = true,
    })
    viewport:SetPoint("TOPLEFT", 24, -150)
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    viewport:SetScript("OnMouseWheel", function(_, delta)
        Picker:ScrollUnifiedRows(delta > 0 and -1 or 1)
    end)
    self.listViewport = viewport

    local listScrollBar = GUI2:CreateVirtualScrollBar(parent, {
        width = 12,
        height = UNIFIED_LIST_HEIGHT,
        trackPixels = 1,
        thumbPixels = 4,
        minThumbPixels = 20,
        onFirstIndexChanged = function(firstIndex)
            Picker:SetUnifiedFirstIndex(firstIndex, true)
        end,
    })
    listScrollBar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 2, 0)
    self.listScrollBar = listScrollBar
end

function Picker:RefreshUnifiedFrameLevels()
    local frame = self.frame
    if not frame then return end
    local host = frame:GetParent()
    local frameLevel = self.sessionFrameLevel
        or (((host and host.GetFrameLevel) and host:GetFrameLevel() or 0) + 60)
    local frameStrata = self.sessionFrameStrata
        or (host and host.GetFrameStrata and host:GetFrameStrata())
        or self.defaultFrameStrata
    local toplevel = self.sessionToplevel
    if toplevel == nil then toplevel = self.defaultToplevel end
    if frameStrata and frame.SetFrameStrata then
        frame:SetFrameStrata(frameStrata)
    end
    if frame.SetToplevel then frame:SetToplevel(toplevel == true) end
    frame:SetFrameLevel(frameLevel)
    if self.panel then
        if frameStrata and self.panel.SetFrameStrata then
            self.panel:SetFrameStrata(frameStrata)
        end
        self.panel:SetFrameLevel(frameLevel + 2)
    end

    local function RefreshModal(mask, panel)
        if not mask then return end
        if frameStrata and mask.SetFrameStrata then
            mask:SetFrameStrata(frameStrata)
        end
        mask:SetFrameLevel(frameLevel + 30)
        if panel then
            if frameStrata and panel.SetFrameStrata then
                panel:SetFrameStrata(frameStrata)
            end
            panel:SetFrameLevel(mask:GetFrameLevel() + 2)
        end
    end
    RefreshModal(self.zoomMask, self.zoomPanel)
    RefreshModal(
        self.assignmentDialog and self.assignmentDialog.mask,
        self.assignmentDialog and self.assignmentDialog.panel
    )
    RefreshModal(
        self.specializationPreviewDialog and self.specializationPreviewDialog.mask,
        self.specializationPreviewDialog and self.specializationPreviewDialog.panel
    )
    RefreshModal(
        self.editorDialog and self.editorDialog.mask,
        self.editorDialog and self.editorDialog.panel
    )
    if self.editorDialog and self.editorDialog.previewMask then
        if frameStrata and self.editorDialog.previewMask.SetFrameStrata then
            self.editorDialog.previewMask:SetFrameStrata(frameStrata)
        end
        self.editorDialog.previewMask:SetFrameLevel(
            self.editorDialog.panel:GetFrameLevel() + 10
        )
        if frameStrata and self.editorDialog.previewPanel.SetFrameStrata then
            self.editorDialog.previewPanel:SetFrameStrata(frameStrata)
        end
        self.editorDialog.previewPanel:SetFrameLevel(
            self.editorDialog.previewMask:GetFrameLevel() + 2
        )
        self.editorDialog.previewCloseButton:SetFrameLevel(
            self.editorDialog.previewPanel:GetFrameLevel() + 3
        )
    end
    RefreshModal(
        self.importDialog and self.importDialog.mask,
        self.importDialog and self.importDialog.panel
    )
    if self.zoomCloseButton and self.zoomPanel then
        self.zoomCloseButton:SetFrameLevel(self.zoomPanel:GetFrameLevel() + 3)
    end
end

function Picker:EnsureFrame(host)
    if self.frame then
        if host and self.frame:GetParent() ~= host then
            self.frame:SetParent(host)
            self.frame:ClearAllPoints()
            self.frame:SetAllPoints(host)
        end
        self:RefreshUnifiedFrameLevels()
        return self.frame
    end

    host = host or _G.YUI_SettingsFrame or UIParent
    local frame = GUI2:CreateFrame(host, {
        allPoints = true,
        mouse = true,
        hidden = true,
    })
    self.defaultFrameStrata = frame.GetFrameStrata
        and frame:GetFrameStrata() or nil
    self.defaultToplevel = frame.IsToplevel
        and frame:IsToplevel() or false
    frame:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 0) + 60)
    self.frame = frame

    local shade = GUI2:CreateTexture(frame, nil, "BACKGROUND")
    GUI2:SetTexturePaintKey(shade, "color.overlay.shadow")
    shade:SetAllPoints()
    shade:SetAlpha(0.7)
    frame.gui2ModalShade = shade

    local panel = GUI2:CreatePanel(frame, {
        width = UNIFIED_PANEL_WIDTH,
        height = UNIFIED_PANEL_HEIGHT,
        surface = "color.surface.window",
        border = "color.border.default",
        shadow = true,
    })
    panel:SetPoint("CENTER")
    panel:SetFrameLevel(frame:GetFrameLevel() + 2)
    self.panel = panel

    local title = GUI2:CreateText(
        panel,
        Text("settings.config_sets.title", "配置方案"),
        "font.size.title",
        "color.text.heading",
        "LEFT"
    )
    title:SetPoint("TOPLEFT", 24, -18)
    self.titleText = title

    local total = GUI2:CreateText(panel, "", "font.size.sm", "color.text.secondary", "LEFT")
    self.totalCountText = total

    local close = GUI2:CreateCloseButton(panel, function()
        Picker:Close()
    end)
    close:SetPoint("TOPRIGHT", -18, -18)
    self.closeButton = close

    self:BuildUnifiedListPage(panel)

    local footerLine = GUI2:CreateTexture(panel, "color.border.subtle", "ARTWORK")
    footerLine:SetPoint("BOTTOMLEFT", 20, 60)
    footerLine:SetPoint("BOTTOMRIGHT", -20, 60)
    footerLine:SetHeight(GUI2:GetPixelSize(panel, 1, 1))
    self.footerLine = footerLine

    local status = GUI2:CreateText(panel, "", "font.size.sm", "color.text.muted", "LEFT")
    status:SetPoint("BOTTOMLEFT", 24, 20)
    status:SetWidth(510)
    status:SetWordWrap(false)
    self.statusText = status

    local undo = CreateButton(panel, {
        width = 108,
        height = 28,
        text = Text("settings.config_sets.undo", "撤销"),
        tone = "default",
        onClick = function()
            Picker:Undo()
        end,
    })
    undo:SetPoint("BOTTOMRIGHT", -144, 16)
    self.undoButton = undo

    local apply = CreateButton(panel, {
        width = 108,
        height = 28,
        text = Text("settings.config_sets.apply", "应用"),
        tone = "accent",
        onClick = function()
            Picker:ApplySelection()
        end,
    })
    apply:SetPoint("BOTTOMRIGHT", -24, 16)
    self.applyButton = apply

    self:RefreshUnifiedFrameLevels()

    frame:SetScript("OnHide", function()
        Picker:Cleanup()
    end)
    return frame
end

function Picker:RefreshStaticText()
    if not self.frame then return end
    self.titleText:SetText(
        self.windowTitle or Text("settings.config_sets.title", "配置方案")
    )
    if self.schemeTitleText then
        self.schemeTitleText:SetText(Text("settings.config_sets.scheme", "方案"))
    end
    if self.assignmentHeaderText then
        self.assignmentHeaderText:SetText(
            Text("settings.config_sets.assignment.title", "适用专精")
        )
    end
    self.createButton:SetText(Text("settings.config_sets.create", "新建"))
    self.importButton:SetText(Text("settings.config_sets.import", "导入"))
    if self.configurationModeControl and self.configurationModeControl.buttons then
        self.configurationModeControl.buttons[1]:SetText(
            Text("settings.config_sets.mode.unified", "账号统一配置")
        )
        self.configurationModeControl.buttons[2]:SetText(
            Text("settings.config_sets.mode.specialization", "专精独立配置")
        )
    end
    self.applyButton:SetText(Text("settings.config_sets.apply", "应用"))
    self.undoButton:SetText(Text("settings.config_sets.undo", "撤销"))
    if self.assignmentDialog then
        self.assignmentDialog.cancelButton:SetText(Text("settings.config_sets.cancel", "取消"))
        self.assignmentDialog.saveButton:SetText(Text("settings.config_sets.save", "保存"))
    end
    if self.editorDialog then
        self.editorDialog.cancelButton:SetText(Text("settings.config_sets.cancel", "取消"))
        self.editorDialog.saveButton:SetText(Text("settings.config_sets.save", "保存"))
    end
    if self.importDialog then
        self.importDialog.titleText:SetText(Text("settings.config_sets.import_title", "导入配置方案"))
        self.importDialog.hintText:SetText(Text("settings.config_sets.import_hint", "粘贴配置方案字符串。"))
        self.importDialog.stringLabel:SetText(Text("settings.config_sets.import_string", "配置方案字符串"))
        self.importDialog.nameLabel:SetText(Text("settings.config_sets.import_name", "导入名称（可选）"))
        self.importDialog.cancelButton:SetText(Text("settings.config_sets.cancel", "取消"))
        self.importDialog.importButton:SetText(Text("settings.config_sets.import_apply", "导入"))
    end
end

function Picker:RefreshCatalog(preferredKind, preferredId)
    if not self:BuildUnifiedCatalog(preferredKind, preferredId) then return false end
    self:RefreshConfigurationModeLayout()
    self:RefreshUnifiedRows()
    self:RefreshFooter()
    return true
end

function Picker:RefreshFooter()
    if not self.applyButton or not self.undoButton then return end
    if self.configurationModesEnabled then
        self.applyButton:Hide()
        self.undoButton:Hide()
        return
    end
    self.applyButton:Show()
    self.undoButton:Show()
    local selected = self:GetSelectedItem()
    self.applyButton:SetDisabled(not selected or selected.compatible == false)
    local manager = GetManager()
    local canUndo = manager and manager.CanUndo
        and manager:CanUndo(self.providerId, self.undoOwner)
    self.undoButton:SetDisabled(canUndo ~= true)
end

function Picker:ApplySelection()
    local manager = GetManager()
    local selected = self:GetSelectedItem()
    if not manager or not selected then return end
    if selected.compatible == false then
        self:SetError("incompatible_schema")
        return
    end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local undoOwner = self.undoOwner
    local onApplied = self.onApplied
    local selectedKind = selected.kind
    local selectedId = selected.id
    local selectedName = ResolveItemName(selected)
    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:Apply(
        providerId,
        { kind = selectedKind, id = selectedId },
        undoOwner
    )
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog(selectedKind, selectedId) end
        self:SetError(code)
        self:RefreshFooter()
        return
    end
    self:SetStatus(
        UnifiedFormat(
            "settings.config_sets.applied",
            "已应用“%s”。",
            selectedName
        ),
        "color.state.success"
    )
    self:RefreshCatalog(selectedKind, selectedId)
    if onApplied then onApplied(result) end
end

function Picker:Undo()
    local manager = GetManager()
    if not manager or not self.providerId then return end
    local providerId = self.providerId
    local sessionToken = self.sessionToken
    local undoOwner = self.undoOwner
    local onApplied = self.onApplied
    self:BeginSessionMutation(providerId, sessionToken)
    local result, code = manager:Undo(providerId, undoOwner)
    local catalogDirty = self:EndSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return end
    if not result then
        if catalogDirty then self:RefreshCatalog() end
        self:SetError(code)
        self:RefreshFooter()
        return
    end
    self:SetStatus(
        Text("settings.config_sets.undone", "已恢复应用前的设置。"),
        "color.state.success"
    )
    self:RefreshCatalog()
    if onApplied then onApplied(result) end
end

function Picker:Cleanup()
    if self.cleaning then return end
    self.cleaning = true
    local onClosed = self.onClosed

    if YUI.Event and type(YUI.Event.OffOwner) == "function" then
        YUI.Event:OffOwner(self)
    end
    if Animation and Animation.StopOwner then
        Animation:StopOwner(self, false)
    end
    self:ReleaseZoomTexture()
    if self.zoomMask then
        self:StopZoomAnimation()
        self.zoomMask:Hide()
        self.zoomMask:SetAlpha(1)
    end
    if GUI2.CloseDropdown then GUI2:CloseDropdown(false) end
    if S.CloseSpecMultiSelectDropdown then
        S:CloseSpecMultiSelectDropdown(self)
    end
    self:CloseAssignmentDialog()
    self:CloseSpecializationPreview()
    self:CloseUnifiedEditor()
    if self.importDialog then
        self:CloseImportDialog()
    end

    local manager = GetManager()
    if manager and manager.CancelOwner and self.undoOwner then
        manager:CancelOwner(self.undoOwner)
    end

    self.providerId = nil
    self.windowTitle = nil
    self.undoOwner = nil
    self.ownerFrame = nil
    self.onApplied = nil
    self.onClosed = nil
    self.previewZoomEnabled = nil
    self.specializationAssignmentsEnabled = nil
    self.specializationModeActive = nil
    self.editableUserSets = nil
    self.userSetScopePolicy = nil
    self.configurationModesEnabled = nil
    self.profileOwned = nil
    self.configurationMode = nil
    self.builtins = {}
    self.userSets = {}
    self.scopes = {}
    self.scopeById = {}
    self.allItems = {}
    self.visibleItems = {}
    self.itemByReference = {}
    self.assignmentSnapshot = {}
    self.assignmentRoutingEnabled = nil
    self.bySpecialization = {}
    self.specializationGroups = {}
    self.specializationSpecOrder = {}
    self.specializationSpecByKey = {}
    self.pickerPreferences = {}
    self.hideUnusedBuiltins = nil
    self.catalogMutationProviderId = nil
    self.catalogMutationSessionToken = nil
    self.catalogMutationDepth = nil
    self.catalogMutationDirty = nil
    self.assignmentSelectorReference = nil
    self.assignmentSelectorSessionToken = nil
    self.assignmentSelectorDraftSelection = nil
    self.assignmentSelectorDirty = nil
    self.currentSpecializationKey = nil
    self.currentSpecializationReference = nil
    self.activeReference = nil
    self.hasSpecializationAssignments = nil
    self.selectedKind = nil
    self.selectedId = nil
    self.listFirstIndex = 1
    self.activeUnifiedModal = nil
    self.suppressUnifiedHoverUntilMouseMove = nil
    self.sessionFrameStrata = nil
    self.sessionFrameLevel = nil
    self.sessionToplevel = nil
    self:RefreshUnifiedFrameLevels()
    for _, row in ipairs(self.unifiedRows or {}) do
        self:ResetUnifiedRowMotion(row)
        row.item = nil
        row:Hide()
    end
    self.cleaning = nil
    if type(onClosed) == "function" then onClosed() end
end

function Picker:Close()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Cleanup()
    end
end

function Picker:IsOpen()
    return self.frame and self.frame:IsShown() or false
end

function Picker:IsCurrentSession(providerId, sessionToken)
    return self:IsOpen()
        and self.providerId == providerId
        and self.sessionToken == sessionToken
end

function Picker:BeginSessionMutation(providerId, sessionToken)
    if not self:IsCurrentSession(providerId, sessionToken) then return false end
    if self.catalogMutationProviderId ~= providerId
        or self.catalogMutationSessionToken ~= sessionToken
    then
        self.catalogMutationProviderId = providerId
        self.catalogMutationSessionToken = sessionToken
        self.catalogMutationDepth = 0
        self.catalogMutationDirty = false
    end
    self.catalogMutationDepth = (self.catalogMutationDepth or 0) + 1
    return true
end

function Picker:EndSessionMutation(providerId, sessionToken)
    if self.catalogMutationProviderId ~= providerId
        or self.catalogMutationSessionToken ~= sessionToken
    then
        return
    end
    local depth = math_max(0, (self.catalogMutationDepth or 1) - 1)
    self.catalogMutationDepth = depth
    if depth > 0 then return false end
    local dirty = self.catalogMutationDirty == true
    self.catalogMutationProviderId = nil
    self.catalogMutationSessionToken = nil
    self.catalogMutationDepth = nil
    self.catalogMutationDirty = nil
    return dirty
end

function Picker:Refresh()
    if not self:IsOpen() then return false end
    self:RefreshStaticText()
    return self:RefreshCatalog(self.selectedKind, self.selectedId)
end

function Picker:OnCatalogEvent(_, providerId, changeKind)
    if not self:IsOpen() or providerId ~= self.providerId then return end
    if changeKind == "data-patch" then return end
    if self.catalogMutationProviderId == providerId
        and self.catalogMutationSessionToken == self.sessionToken
        and (self.catalogMutationDepth or 0) > 0
    then
        self.catalogMutationDirty = true
        return
    end
    self:RefreshCatalog(self.selectedKind, self.selectedId)
end

function Picker:OnSpecializationEvent(_, unit)
    if not self:IsOpen() then return end
    if type(unit) == "string" and unit ~= "player" then return end
    self:RefreshCatalog(self.selectedKind, self.selectedId)
end

function Picker:RefreshVisibleSpecializationIcons()
    if not self:IsOpen() then return end
    for _, row in ipairs(self.unifiedRows or {}) do
        if row.item then
            self:RefreshUnifiedAssignmentVisual(row, row.item.assignment)
        end
    end
end

function Picker:OnAppearanceIconSetChanged()
    self:RefreshVisibleSpecializationIcons()
end

function Picker:OnAppearanceIconScopeChanged(_, scopeId)
    if scopeId == "settings" then
        self:RefreshVisibleSpecializationIcons()
    end
end

function Picker:RegisterEvents()
    local Event = YUI.Event
    if not (Event and type(Event.On) == "function") then return false end
    if type(Event.OffOwner) == "function" then Event:OffOwner(self) end
    Event:On("YUI_CONFIG_SETS_CHANGED", "OnCatalogEvent", self)
    Event:On("YUI_CONFIG_SET_MODE_CHANGED", "OnCatalogEvent", self)
    Event:On("YUI_CONFIG_SET_ACTIVE_CHANGED", "OnCatalogEvent", self)
    Event:On("PLAYER_SPECIALIZATION_CHANGED", "OnSpecializationEvent", self)
    Event:On("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "OnSpecializationEvent", self)
    Event:On("ACTIVE_TALENT_GROUP_CHANGED", "OnSpecializationEvent", self)
    Event:On("CHARACTER_POINTS_CHANGED", "OnSpecializationEvent", self)
    Event:On("PLAYER_TALENT_UPDATE", "OnSpecializationEvent", self)
    Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", "OnSpecializationEvent", self)
    Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", "OnAppearanceIconSetChanged", self)
    Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", "OnAppearanceIconScopeChanged", self)
    return true
end

function Picker:Open(owner, options)
    if type(owner) == "table" and owner.providerId and options == nil then
        options = owner
        owner = options.owner
    elseif type(owner) == "string" then
        options = options or {}
        options.providerId = owner
        owner = options.owner
    else
        options = options or {}
    end

    local manager = GetManager()
    local providerId = options.providerId
    if not manager or not providerId then
        return nil, "provider_not_found"
    end
    local provider, code = manager:GetProvider(providerId)
    if not provider then
        return nil, code or "provider_not_found"
    end
    if self:IsOpen() then self:Close() end

    self.sessionFrameStrata = VALID_FRAME_STRATA[options.frameStrata]
            and options.frameStrata or nil
    local requestedFrameLevel = tonumber(options.frameLevel)
    self.sessionFrameLevel = requestedFrameLevel
            and requestedFrameLevel >= 0
            and math_floor(requestedFrameLevel) or nil
    self.sessionToplevel = type(options.toplevel) == "boolean"
            and options.toplevel or nil
    local host = options.host or options.parent or _G.YUI_SettingsFrame or UIParent
    local frame = self:EnsureFrame(host)
    self.providerId = providerId
    self.windowTitle = type(options.title) == "string"
            and options.title ~= ""
            and options.title
        or nil
    self.previewZoomEnabled = provider.previewZoom == true
    self.specializationAssignmentsEnabled = provider.specializationAssignments == true
    self.editableUserSets = provider.editableUserSets == true
    self.profileOwned = GetManager().ProfileOwnership ~= nil and self.editableUserSets
    self.userSetScopePolicy = provider.userSetScopePolicy
    self.configurationModesEnabled = type(provider.configurationModes) == "table"
        and provider.configurationModes.isolatedLibraries == true
    UnifiedSetShown(
        self.assignmentHeaderText,
        self.specializationAssignmentsEnabled and not self.configurationModesEnabled
    )
    UnifiedSetShown(self.schemeTitleText, not self.editableUserSets)
    UnifiedSetShown(self.totalCountText, not self.editableUserSets)
    self.undoOwner = options.undoOwner or owner or self
    self.ownerFrame = options.ownerFrame or owner
    self.onApplied = options.onApplied
    self.onClosed = options.onClosed
    self.selectedKind = options.kind
    self.selectedId = options.setId
    self.listFirstIndex = 1
    self.sessionToken = (self.sessionToken or 0) + 1

    self:HookOwnerFrame(self.ownerFrame)
    self:RegisterEvents()
    frame:Show()
    self:RefreshStaticText()
    self:SetStatus("")
    self:RefreshCatalog(options.kind, options.setId)
    return true
end
