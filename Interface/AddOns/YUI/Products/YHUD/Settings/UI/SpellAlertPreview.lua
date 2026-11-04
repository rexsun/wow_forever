local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
local UI = HUD and HUD.DesignerUI
if not UI then return end
local GUI, Defaults = YUI.GUI2, YUI.SpellAlertPreviewDefaults

function UI:GetSpellAlertPreviewSourceText()
    local session = HUD.Designer:GetSession()
    local classic = HUD.Client and HUD.Client.id == 'forever'
    local _, placeholder = Defaults:GetLayout(session and session.viewSpecKey, classic)
    return HUD:T('designer.toolbar.spell_alert_' .. (classic and 'classic' or placeholder and 'placeholder' or 'sample'))
end

function UI:HideSpellAlertPreview()
    self.spellAlertPreviewEnabled = false
    if self.spellAlertPreviewButton then self.spellAlertPreviewButton:SetSelected(false) end
    local frame = self.spellAlertPreview
    if not frame then return end
    YUI.Event:OffOwner(frame)
    YUI.Animation:StopOwner(frame, false)
    frame:Hide()
end

function UI:RefreshSpellAlertPreview()
    if not self.spellAlertPreviewEnabled then return end
    local session = HUD.Designer:GetSession()
    if self.busyKind or not self.toolbar:IsShown() or not session or InCombatLockdown() then
        self:HideSpellAlertPreview()
        return
    end
    local frame = self.spellAlertPreview
    if not frame then
        frame = GUI:CreateFrame(self.dimmer, {strata='LOW', level=102, mouse=false})
        frame.slots = {}
        for _, slot in ipairs(Defaults.slots) do
            frame.slots[slot] = GUI:CreateTexture(frame, nil, 'ARTWORK')
        end
        function frame:StopPreview() UI:HideSpellAlertPreview() end
        self.spellAlertPreview = frame
    end
    -- Read only the public layout of the native host; never show/hide it or set CVars.
    local native = _G.SpellActivationOverlayFrame
    if native and native.IsForbidden and native:IsForbidden() then native = nil end
    local longSide = native and native:GetWidth() or 204.8
    if longSide <= 0 then longSide = 204.8 end
    frame:SetSize(longSide, longSide)
    frame:SetScale(native and native:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1)
    frame:ClearAllPoints()
    frame:SetPoint('CENTER', native or UIParent, 'CENTER')
    local classic = HUD.Client and HUD.Client.id == 'forever'
    local state = Defaults:GetLayout(session.viewSpecKey, classic)
    local function Place(slot, textureID, point, relative, relativePoint, horizontal, mirror, offsetX)
        local texture = frame.slots[slot]
        if not textureID then texture:Hide(); return end
        texture:SetTexture(textureID)
        texture:SetTexCoord(mirror and 1 or 0, mirror and 0 or 1, 0, 1)
        texture:SetSize(horizontal and longSide or longSide * 0.5, horizontal and longSide * 0.5 or longSide)
        texture:ClearAllPoints()
        texture:SetPoint(point, relative, relativePoint, offsetX or 0, 0)
        texture:Show()
    end
    Place('left', state.left, 'RIGHT', frame, 'LEFT')
    Place('right', state.right, 'LEFT', frame, 'RIGHT', false, true)
    Place('top', state.top, 'BOTTOM', frame, 'TOP', true)
    Place('extraLeft', state.extraLeft, 'RIGHT', frame, 'LEFT', false, false, -longSide * 0.5)
    Place('extraRight', state.extraRight, 'LEFT', frame, 'RIGHT', false, true, longSide * 0.5)
    frame:Show()
end

function UI:ToggleSpellAlertPreview()
    if self.busyKind then return end
    if self.spellAlertPreviewEnabled then self:HideSpellAlertPreview(); return end
    if InCombatLockdown() or not self.toolbar:IsShown() then return end
    self.spellAlertPreviewEnabled = true
    self:RefreshSpellAlertPreview()
    if not self.spellAlertPreviewEnabled then return end
    local frame = self.spellAlertPreview
    self.spellAlertPreviewButton:SetSelected(true)
    YUI.Event:On('PLAYER_REGEN_DISABLED', 'StopPreview', frame)
    frame:SetAlpha(1)
    GUI:Animate(frame, {owner=frame, key='spell-alert-preview', driver='native', easing='out',
        effects={{type='alpha', from=0, to=1, duration=0.2}}})
end
