local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local GUI2 = YUI.GUI2
local InputSkin = {}
YChat.InputSkin = InputSkin

local pcall = pcall
local type = type
local pairs = pairs
local stateByFrame = setmetatable({}, { __mode = "k" })
local stateByEditBox = setmetatable({}, { __mode = "k" })
local stateByLanguageButton = setmetatable({}, { __mode = "k" })

InputSkin.enabled = false
InputSkin.managedFrames = 0
InputSkin.lastReason = "not-started"
InputSkin.allocatedTextures = 0

local function StatIncrement(field)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field) end
end

local function StatSet(field, value)
    local stats = YChat.Stats
    if stats and stats.Set then stats:Set(field, value) end
end

local function CallMethod(target, method, ...)
    local callback = target and target[method]
    if type(callback) ~= "function" then return false end
    local ok, result = pcall(callback, target, ...)
    return ok and result ~= false
end

local function ReadColor(key, fallbackR, fallbackG, fallbackB, fallbackA)
    if GUI2 and type(GUI2.GetColor) == "function" then
        local ok, r, g, b, a = pcall(GUI2.GetColor, GUI2, key)
        if ok and type(r) == "number" and type(g) == "number"
            and type(b) == "number"
        then
            return r, g, b, type(a) == "number" and a or fallbackA
        end
    end
    return fallbackR, fallbackG, fallbackB, fallbackA
end

local function CaptureNativeRegions(regions, minimumCount)
    minimumCount = type(minimumCount) == "number" and minimumCount or 3
    if type(regions) ~= "table" or #regions < minimumCount then
        return nil, "input-skin-native-regions-missing"
    end
    local snapshot = {}
    for index = 1, #regions do
        local region = regions[index]
        if Adapter:CanCallProtected(region) ~= true
            or type(region.GetAlpha) ~= "function"
            or type(region.IsShown) ~= "function"
        then
            return nil, "input-skin-native-region-unsafe"
        end
        local alphaOK, alpha = pcall(region.GetAlpha, region)
        local shownOK, shown = pcall(region.IsShown, region)
        if not alphaOK or not shownOK or type(alpha) ~= "number"
            or type(shown) ~= "boolean"
        then
            return nil, "input-skin-native-region-capture-failed"
        end
        local texture
        if type(region.GetTexture) == "function" then
            local textureOK
            textureOK, texture = pcall(region.GetTexture, region)
            if not textureOK then
                return nil, "input-skin-native-texture-capture-failed"
            end
        end
        local atlas
        if type(region.GetAtlas) == "function" then
            local atlasOK
            atlasOK, atlas = pcall(region.GetAtlas, region)
            if not atlasOK then
                return nil, "input-skin-native-atlas-capture-failed"
            end
        end
        snapshot[index] = {
            region = region,
            alpha = alpha,
            shown = shown,
            texture = texture,
            atlas = atlas,
        }
    end
    return snapshot
end

local function SuppressNativeRegions(snapshot)
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local region = entry.region
        if Adapter:CanCallProtected(region) ~= true
            or not CallMethod(region, "SetAlpha", 0)
            or not CallMethod(region, "Hide")
        then
            return false
        end
    end
    return true
end

local function RestoreNativeRegions(snapshot)
    local restored = true
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local region = entry.region
        if Adapter:CanCallProtected(region) ~= true then
            restored = false
        else
            local textureOK = true
            if entry.atlas ~= nil and type(region.SetAtlas) == "function" then
                textureOK = CallMethod(region, "SetAtlas", entry.atlas, true)
            elseif type(region.SetTexture) == "function" then
                textureOK = CallMethod(region, "SetTexture", entry.texture)
            end
            restored = textureOK
                and CallMethod(region, "SetAlpha", entry.alpha)
                and CallMethod(region, entry.shown and "Show" or "Hide")
                and restored
        end
    end
    return restored
end

local function CreateFlatTexture(editBox, layer, subLevel)
    if Adapter:CanCallProtected(editBox) ~= true
        or type(editBox.CreateTexture) ~= "function"
    then
        return nil
    end
    local ok, texture = pcall(editBox.CreateTexture, editBox, nil, layer, nil, subLevel)
    if not ok or not texture
        or not CallMethod(texture, "SetTexture", "Interface\\Buttons\\WHITE8X8")
        or not CallMethod(texture, "Hide")
    then
        return nil
    end
    InputSkin.allocatedTextures = InputSkin.allocatedTextures + 1
    return texture
end

local function AllocateArt(target, inset)
    local background = CreateFlatTexture(target, "BACKGROUND", -8)
    local top = CreateFlatTexture(target, "BORDER", 2)
    local bottom = CreateFlatTexture(target, "BORDER", 2)
    local left = CreateFlatTexture(target, "BORDER", 2)
    local right = CreateFlatTexture(target, "BORDER", 2)
    if not background or not top or not bottom or not left or not right then
        return nil, "input-skin-art-allocation-failed"
    end

    local pixel = GUI2 and type(GUI2.GetPixelSize) == "function"
        and GUI2:GetPixelSize(target, 1, 1)
        or 1
    inset = GUI2 and type(GUI2.GetPixelSize) == "function"
        and GUI2:GetPixelSize(target, type(inset) == "number" and inset or 2, 1)
        or (type(inset) == "number" and inset or 2)
    if not CallMethod(background, "ClearAllPoints")
        or not CallMethod(background, "SetPoint", "TOPLEFT", target, "TOPLEFT", inset, -inset)
        or not CallMethod(background, "SetPoint", "BOTTOMRIGHT", target, "BOTTOMRIGHT", -inset, inset)
        or not CallMethod(top, "ClearAllPoints")
        or not CallMethod(top, "SetPoint", "TOPLEFT", background, "TOPLEFT", 0, 0)
        or not CallMethod(top, "SetPoint", "TOPRIGHT", background, "TOPRIGHT", 0, 0)
        or not CallMethod(top, "SetHeight", pixel)
        or not CallMethod(bottom, "ClearAllPoints")
        or not CallMethod(bottom, "SetPoint", "BOTTOMLEFT", background, "BOTTOMLEFT", 0, 0)
        or not CallMethod(bottom, "SetPoint", "BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, 0)
        or not CallMethod(bottom, "SetHeight", pixel)
        or not CallMethod(left, "ClearAllPoints")
        or not CallMethod(left, "SetPoint", "TOPLEFT", background, "TOPLEFT", 0, 0)
        or not CallMethod(left, "SetPoint", "BOTTOMLEFT", background, "BOTTOMLEFT", 0, 0)
        or not CallMethod(left, "SetWidth", pixel)
        or not CallMethod(right, "ClearAllPoints")
        or not CallMethod(right, "SetPoint", "TOPRIGHT", background, "TOPRIGHT", 0, 0)
        or not CallMethod(right, "SetPoint", "BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, 0)
        or not CallMethod(right, "SetWidth", pixel)
    then
        return nil, "input-skin-art-anchor-failed"
    end
    return {
        target = target,
        background = background,
        top = top,
        bottom = bottom,
        left = left,
        right = right,
        pixel = pixel,
        inset = inset,
    }
end

local function JoinInputAndLanguageArt(editArt, languageArt)
    if not editArt or not languageArt then return true end
    local background = editArt.background
    local languageBackground = languageArt.background
    return CallMethod(background, "ClearAllPoints")
        and CallMethod(
            background,
            "SetPoint",
            "TOPLEFT",
            editArt.target,
            "TOPLEFT",
            editArt.inset,
            -editArt.inset
        )
        and CallMethod(
            background,
            "SetPoint",
            "BOTTOMRIGHT",
            languageBackground,
            "BOTTOMLEFT",
            0,
            0
        )
end

local function HideArt(art)
    if not art then return true end
    return CallMethod(art.background, "Hide")
        and CallMethod(art.top, "Hide")
        and CallMethod(art.bottom, "Hide")
        and CallMethod(art.left, "Hide")
        and CallMethod(art.right, "Hide")
end

local function RefreshSafeFocus(state)
    local editBox = state and state.editBox
    if not editBox or type(editBox.HasFocus) ~= "function" then return end
    local ok, focused = pcall(editBox.HasFocus, editBox)
    if not ok
        or type(Adapter.IsExplicitlySafeValue) ~= "function"
        or Adapter:IsExplicitlySafeValue(focused) ~= true
        or type(focused) ~= "boolean"
    then
        return
    end
    state.focused = focused
end

local function IsFocused(state)
    return state and state.focused == true
end

local function ReadVisibilityValue(target, method, expectedType)
    if type(target[method]) ~= "function" then return nil end
    local ok, value = pcall(target[method], target)
    if not ok or Adapter:IsExplicitlySafeValue(value) ~= true
        or type(value) ~= expectedType
    then
        return nil
    end
    return value
end

local function SetInputVisibility(state, target, snapshot, visible)
    if visible and not snapshot.hidden then return true end
    if Adapter:CanCallProtected(target) ~= true then return false end
    if not visible and snapshot.hidden and not snapshot.pending then return true end
    if not visible and not snapshot.hidden then
        local alpha = ReadVisibilityValue(target, "GetAlpha", "number")
        local clicks = ReadVisibilityValue(target, "IsMouseClickEnabled", "boolean")
        local motion = ReadVisibilityValue(target, "IsMouseMotionEnabled", "boolean")
        if alpha == nil or clicks == nil or motion == nil
            or type(target.SetAlpha) ~= "function"
            or type(target.SetMouseClickEnabled) ~= "function"
            or type(target.SetMouseMotionEnabled) ~= "function"
        then
            return false
        end
        snapshot.alpha, snapshot.clicks, snapshot.motion = alpha, clicks, motion
        snapshot.hidden = true
    end
    -- 不隐藏或停用原生 EditBox，避免触发 OnHide 清空草稿。
    state.visibilityWriting = true
    local alphaOK = CallMethod(target, "SetAlpha", visible and snapshot.alpha or 0)
    local clickOK = CallMethod(target, "SetMouseClickEnabled", visible and snapshot.clicks or false)
    local motionOK = CallMethod(target, "SetMouseMotionEnabled", visible and snapshot.motion or false)
    state.visibilityWriting = false
    local ok = alphaOK and clickOK and motionOK
    snapshot.pending = not ok
    if visible and ok then snapshot.hidden = false end
    return ok
end

local function ApplyInputVisibility(state, visible)
    local ok = SetInputVisibility(state, state.editBox, state.visibility, visible)
    local language = state.language
    if language then
        ok = SetInputVisibility(state, language.button, language.visibility, visible) and ok
    end
    return ok
end

local function ApplyVisuals(state)
    if not state or not state.applied then return false end
    local art = state.art
    local focused = IsFocused(state)
    local ok = SuppressNativeRegions(state.nativeSnapshot)
    if not focused then return HideArt(art) and ok end
    local backgroundR, backgroundG, backgroundB =
        ReadColor("color.surface.panel", 0.035, 0.045, 0.055, 1)
    local borderR, borderG, borderB, borderA
    borderR, borderG, borderB = Adapter:ReadInputChatColor(
        state.frame,
        state.editBox
    )
    if borderR ~= nil then
        borderA = 0.95
    else
        borderR, borderG, borderB, borderA =
            ReadColor("color.border.focus", 0.18, 0.72, 0.96, 0.95)
    end
    ok = CallMethod(art.background, "SetColorTexture", backgroundR, backgroundG, backgroundB, 0.96)
        and CallMethod(art.background, "Show")
        and ok
    ok = CallMethod(art.top, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.top, "Show")
        and ok
    ok = CallMethod(art.bottom, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.bottom, "SetHeight", art.pixel)
        and CallMethod(art.bottom, "Show")
        and ok
    ok = CallMethod(art.left, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.left, "Show")
        and ok
    ok = CallMethod(art.right, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.right, "Show")
        and ok
    return ok
end

local function CaptureLanguageButton(button)
    if not button then return nil end
    local normalOK, normal = pcall(button.GetNormalTexture, button)
    if not normalOK then return nil, "input-skin-language-texture-read-failed" end
    local normalSnapshot
    if normal then
        local snapshot, reason = CaptureNativeRegions({ normal }, 1)
        if not snapshot then return nil, reason end
        normalSnapshot = snapshot
    end
    local fontOK, fontString = pcall(button.GetFontString, button)
    if not fontOK then return nil, "input-skin-language-font-read-failed" end
    local textColor
    if fontString and type(fontString.GetTextColor) == "function"
        and type(fontString.SetTextColor) == "function"
    then
        local ok, r, g, b, a = pcall(fontString.GetTextColor, fontString)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            textColor = { r, g, b, type(a) == "number" and a or 1 }
        end
    end
    return {
        button = button,
        visibility = {},
        normalSnapshot = normalSnapshot,
        fontString = fontString,
        textColor = textColor,
        hovered = false,
    }
end

local function RefreshLanguageText(state)
    local language = state and state.language
    if not language then return true end
    local label = Adapter:ReadInputLanguageLabel(state.frame, state.editBox)
    if label == nil then return true end
    return CallMethod(language.button, "SetText", label)
end

local function ApplyLanguageVisuals(state)
    local language = state and state.language
    if not language then return true end
    if not RefreshLanguageText(state) then return false end
    if language.normalSnapshot and not SuppressNativeRegions(language.normalSnapshot) then
        return false
    end
    if not IsFocused(state) then return HideArt(language.art) end
    local backgroundR, backgroundG, backgroundB =
        ReadColor(language.hovered and "color.control.hover" or "color.surface.panel", 0.035, 0.045, 0.055, 1)
    local borderR, borderG, borderB, borderA = ReadColor(
        language.hovered and "color.border.focus" or "color.border.subtle",
        0.22, 0.26, 0.31, language.hovered and 0.95 or 0.72
    )
    local textR, textG, textB, textA = ReadColor(
        language.hovered and "color.text.accent" or "color.text.primary",
        0.92, 0.94, 0.98, 1
    )
    local art = language.art
    local ok = CallMethod(art.background, "SetColorTexture", backgroundR, backgroundG, backgroundB, 0.96)
        and CallMethod(art.background, "Show")
    ok = CallMethod(art.top, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.top, "Show") and ok
    ok = CallMethod(art.bottom, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.bottom, "Show") and ok
    ok = CallMethod(art.left, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.left, "Show") and ok
    ok = CallMethod(art.right, "SetColorTexture", borderR, borderG, borderB, borderA)
        and CallMethod(art.right, "Show") and ok
    if language.fontString and type(language.fontString.SetTextColor) == "function" then
        ok = CallMethod(language.fontString, "SetTextColor", textR, textG, textB, textA) and ok
    end
    return ok
end

local function NativeEditStateChanged(editBox)
    local state = stateByEditBox[editBox]
    if InputSkin.enabled and state and state.applied then
        if not ApplyInputVisibility(state, IsFocused(state))
            or not ApplyVisuals(state) or not ApplyLanguageVisuals(state)
        then
            InputSkin.lastReason = "input-skin-native-refresh-failed"
            StatIncrement("inputSkinFailures")
        end
    end
end

local function NativeInputAlphaChanged(target, alpha)
    local state = stateByEditBox[target] or stateByLanguageButton[target]
    if not InputSkin.enabled or not state or not state.applied or state.visibilityWriting then return end
    local snapshot = state.editBox == target and state.visibility or state.language.visibility
    if not snapshot.hidden or Adapter:IsExplicitlySafeValue(alpha) ~= true
        or type(alpha) ~= "number" or Adapter:CanCallProtected(target) ~= true
    then
        return
    end
    snapshot.alpha = alpha
    state.visibilityWriting = true
    CallMethod(target, "SetAlpha", 0)
    state.visibilityWriting = false
end

local function NativeEditFocusGained(editBox)
    local state = stateByEditBox[editBox]
    if state then state.focused = true end
    NativeEditStateChanged(editBox)
end

local function NativeEditFocusLost(editBox)
    local state = stateByEditBox[editBox]
    if state then state.focused = false end
    NativeEditStateChanged(editBox)
end

local function NativeLanguageStateChanged(button)
    local state = stateByLanguageButton[button]
    if InputSkin.enabled and state and state.applied then
        ApplyLanguageVisuals(state)
    end
end

local function LanguageButtonEntered(button)
    local state = stateByLanguageButton[button]
    if not state or not state.language then return end
    state.language.hovered = true
    NativeLanguageStateChanged(button)
end

local function LanguageButtonLeft(button)
    local state = stateByLanguageButton[button]
    if not state or not state.language then return end
    state.language.hovered = false
    NativeLanguageStateChanged(button)
end

local function InstallHooks(state)
    if state.hooked then return true end
    local editBox = state.editBox
    if type(editBox.HookScript) ~= "function"
        or not pcall(editBox.HookScript, editBox, "OnEditFocusGained", NativeEditFocusGained)
        or not pcall(editBox.HookScript, editBox, "OnEditFocusLost", NativeEditFocusLost)
        or not pcall(editBox.HookScript, editBox, "OnInputLanguageChanged", NativeEditStateChanged)
    then
        return false
    end
    if type(_G.hooksecurefunc) == "function" then
        if not pcall(_G.hooksecurefunc, editBox, "SetAlpha", NativeInputAlphaChanged) then return false end
        if type(editBox.UpdateHeader) == "function" then
            pcall(_G.hooksecurefunc, editBox, "UpdateHeader", NativeEditStateChanged)
        end
        if type(editBox.SetTextColor) == "function" then
            pcall(_G.hooksecurefunc, editBox, "SetTextColor", NativeEditStateChanged)
        end
        if type(editBox.SetFocusRegionsShown) == "function" then
            pcall(_G.hooksecurefunc, editBox, "SetFocusRegionsShown", NativeEditStateChanged)
        end
    end
    local language = state.language
    if language then
        local button = language.button
        if type(_G.hooksecurefunc) ~= "function"
            or not pcall(_G.hooksecurefunc, button, "SetAlpha", NativeInputAlphaChanged)
        then
            return false
        end
        if not pcall(button.HookScript, button, "OnEnter", LanguageButtonEntered)
            or not pcall(button.HookScript, button, "OnLeave", LanguageButtonLeft)
            or not pcall(button.HookScript, button, "OnShow", NativeLanguageStateChanged)
        then
            return false
        end
    end
    state.hooked = true
    return true
end

local function RestoreState(state)
    if not state then return true end
    state.applied = false
    local visibilityOK = ApplyInputVisibility(state, true)
    local artOK = HideArt(state.art)
    local nativeOK = RestoreNativeRegions(state.nativeSnapshot)
    local languageOK = true
    if state.language then
        languageOK = HideArt(state.language.art)
        if state.language.normalSnapshot then
            languageOK = RestoreNativeRegions(state.language.normalSnapshot) and languageOK
        end
        local color = state.language.textColor
        if color and state.language.fontString then
            languageOK = CallMethod(state.language.fontString, "SetTextColor", color[1], color[2], color[3], color[4])
                and languageOK
        end
    end
    return visibilityOK and artOK and nativeOK and languageOK
end

local function TargetsMatch(state, targets)
    if not state or not targets or state.editBox ~= targets.editBox
        or (state.language and state.language.button or nil) ~= targets.inputLanguageButton
    then
        return false
    end
    local regions = targets.editBoxRegions
    if type(regions) ~= "table" or #regions ~= #state.nativeSnapshot then return false end
    for index = 1, #regions do
        if state.nativeSnapshot[index].region ~= regions[index] then return false end
    end
    return true
end

local function EnsureState(frame)
    local targets, reason = Adapter:GetAppearanceTargets(frame)
    if not targets or not targets.editBox then
        return nil, reason or "input-skin-editbox-unavailable"
    end
    local state = stateByFrame[frame]
    if state and not TargetsMatch(state, targets) then
        if not RestoreState(state) then return nil, "input-skin-restore-pending" end
        stateByEditBox[state.editBox] = nil
        if state.language then stateByLanguageButton[state.language.button] = nil end
        stateByFrame[frame] = nil
        state = nil
    end
    if state then
        if not state.applied then
            if not ApplyInputVisibility(state, true) then return nil, "input-skin-restore-pending" end
            local snapshot, captureReason = CaptureNativeRegions(targets.editBoxRegions)
            if not snapshot then return nil, captureReason end
            state.nativeSnapshot = snapshot
            if state.language then
                local language, languageReason = CaptureLanguageButton(targets.inputLanguageButton)
                if not language then return nil, languageReason end
                language.art = state.language.art
                state.language = language
            end
        end
        return state
    end

    local snapshot, captureReason = CaptureNativeRegions(targets.editBoxRegions)
    if not snapshot then return nil, captureReason end
    local art, artReason = AllocateArt(targets.editBox, 3)
    if not art then return nil, artReason end
    local language, languageReason = CaptureLanguageButton(targets.inputLanguageButton)
    if targets.inputLanguageButton and not language then
        HideArt(art)
        return nil, languageReason
    end
    if language then
        language.art, languageReason = AllocateArt(language.button, 3)
        if not language.art then
            HideArt(art)
            return nil, languageReason
        end
        if not JoinInputAndLanguageArt(art, language.art) then
            HideArt(art)
            HideArt(language.art)
            return nil, "input-skin-language-join-failed"
        end
    end
    state = {
        frame = frame,
        editBox = targets.editBox,
        visibility = {},
        nativeSnapshot = snapshot,
        art = art,
        language = language,
        focused = false,
        applied = false,
        hooked = false,
    }
    stateByFrame[frame] = state
    stateByEditBox[state.editBox] = state
    if language then stateByLanguageButton[language.button] = state end
    if not InstallHooks(state) then
        stateByFrame[frame] = nil
        stateByEditBox[state.editBox] = nil
        if language then stateByLanguageButton[language.button] = nil end
        HideArt(art)
        if language then HideArt(language.art) end
        return nil, "input-skin-hook-install-failed"
    end
    return state
end

local function ReconcileFrame(frame)
    local state, reason = EnsureState(frame)
    if not state then
        InputSkin.lastReason = reason
        StatIncrement("inputSkinFailures")
        return false
    end
    RefreshSafeFocus(state)
    state.applied = true
    if not ApplyInputVisibility(state, IsFocused(state))
        or not ApplyVisuals(state) or not ApplyLanguageVisuals(state)
    then
        RestoreState(state)
        InputSkin.lastReason = "input-skin-apply-failed"
        StatIncrement("inputSkinFailures")
        return false
    end
    return true
end

local function NativeReplyRequested(editBox)
    if not InputSkin.enabled then return end
    local state = stateByEditBox[editBox]
    if not state or not state.applied or not state.visibility.hidden or state.focused then return end
    Adapter:ActivateInputForReply(editBox)
end

function InputSkin:SetEnabled(enabled, reason)
    enabled = enabled == true
    self.enabled = enabled
    if enabled then
        local installed, installReason = Adapter:SetInputReplyCallback(NativeReplyRequested)
        if not installed then
            self:SetEnabled(false, installReason)
            return false, installReason
        end
        Adapter:ForEachSupportedFrame(ReconcileFrame)
    else
        Adapter:SetInputReplyCallback(nil)
        local restored = true
        for _, state in pairs(stateByFrame) do
            if not RestoreState(state) then restored = false end
        end
        if not restored then
            self.lastReason = "input-skin-restore-pending"
            self:GetRuntimeGauges()
            return false, self.lastReason
        end
    end
    self.lastReason = reason or (enabled and "input-skin-enabled" or "input-skin-disabled")
    self:GetRuntimeGauges()
    return true
end

function InputSkin:OnFrameDiscovered(frame, valid)
    if valid ~= true then
        local state = stateByFrame[frame]
        if state then return RestoreState(state) end
        return true
    end
    if not self.enabled then return true end
    return ReconcileFrame(frame)
end

function InputSkin:OnWindowsChanged()
    if not self.enabled then return true end
    Adapter:ForEachSupportedFrame(ReconcileFrame)
    return true
end

function InputSkin:RestoreAll(reason)
    return self:SetEnabled(false, reason or "input-skin-restore")
end

function InputSkin:GetRuntimeGauges(target)
    target = target or {}
    local managed = 0
    for _, state in pairs(stateByFrame) do
        if state.applied then managed = managed + 1 end
    end
    self.managedFrames = managed
    target.inputSkinManagedFrames = managed
    target.inputSkinAllocatedTextures = self.allocatedTextures
    target.inputSkinEnabled = self.enabled == true
    target.inputSkinLastFailure = self.lastReason
    StatSet("inputSkinManagedFrames", managed)
    StatSet("inputSkinAllocatedTextures", self.allocatedTextures)
    return target
end
