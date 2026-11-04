local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local GUI = YUI and YUI.GUI2
if not (YHUD and GUI) then return end
local View = YHUD.View
local specs = setmetatable({}, { __mode = "k" })

local function HideEdges(edges)
    for _, edge in pairs(edges or {}) do
        if type(edge) == "table" and edge.Hide then edge:Hide() end
    end
end

local function HideBuiltin(owner)
    local spec = specs[owner]
    if not spec then return end
    local target = spec.target
    if target then
        if target.background then target.background:Hide() end
        if target.shapeBorder then target.shapeBorder:Hide() end
        if target.border and target.border.Hide then target.border:Hide() end
        HideEdges(target.pixelBorder)
        if target.border and not target.border.Hide then HideEdges(target.border) end
    end
    if View.HideIconShadow then View:HideIconShadow(owner) end
end

local function RefreshSlot(owner)
    local spec = specs[owner]
    if spec and spec.runtime then View:ConfigureSlot(owner, spec.runtime, spec.monitor) end
end

local function Effects(owner, spec)
    local highlight = YHUD.AssistedHighlight and YHUD.AssistedHighlight.targets[owner]
    spec.assisted = highlight and highlight.active and highlight.glow or nil
    local layer = YHUD.PressFeedback and YHUD.PressFeedback.layers[owner]
    spec.regions.Pushed = layer and layer.pressState and layer.pressState.pressedOverlay or nil
end

function View:ApplySlotIconSkin(slot, runtime, monitor)
    if not GUI.ApplyIconSkin or not runtime.iconStyle or runtime.view == "ring" then return end
    if runtime.skinId ~= "masque" then
        if specs[slot] then specs[slot].id = runtime.skinId; GUI:ApplyIconSkin(slot, specs[slot]) end
        return
    end
    local spec = specs[slot] or { regions = {} }
    specs[slot] = spec
    spec.id, spec.product, spec.groupId = runtime.skinId, "Halo", runtime.skinGroupId or slot._yhudGroupId or "icons"
    spec.groupLabel = runtime.skinGroupLabel
    spec.runtime, spec.monitor, spec.style = runtime, monitor, runtime.iconStyle
    spec.target = slot._yhudSharedIconTarget
    if not spec.target then return end
    spec.anchor = spec.target.owner
    spec.width, spec.height = runtime.iconWidth or runtime.iconSize or 42, runtime.iconHeight or runtime.iconSize or 42
    local regions = spec.regions
    regions.Icon, regions.Backdrop = spec.target.icon, spec.target.background
    regions.Cooldown = spec.anchor.cooldown or slot.cooldown
    regions.Count = runtime.view == "icon" and (slot.countText or slot.count) or nil
    regions.HotKey = runtime.view == "icon" and slot._yhudKeybindText or nil
    spec.proc = slot._yhudNativeProcGlow
    spec.buttonType = "Aura"
    spec.refresh, spec.hideBuiltin = RefreshSlot, HideBuiltin
    spec.afterApply = function(owner)
        runtime.iconStyle.effectShape = GUI:GetIconSkinEffectShape(owner, runtime.shape)
        if owner.gui2Glow and owner.gui2Glow.SetGlowSkinOwner then owner.gui2Glow:SetGlowSkinOwner(owner) end
        if View.RefreshIconSkinCooldown then View:RefreshIconSkinCooldown(owner, runtime) end
    end
    Effects(slot, spec)
    GUI:ApplyIconSkin(slot, spec)
    runtime.iconStyle.effectShape = GUI:GetIconSkinEffectShape(slot, runtime.shape)
end

function View:ApplyNativeIconSkin(frame, runtime, state, refresh, afterApply)
    if not (GUI.ApplyIconSkin and state.iconTarget) then return end
    state.iconSkinRegistered = runtime.skinId == "masque"
    if runtime.skinId ~= "masque" then
        state.masqueActive = false
        if specs[frame] then specs[frame].id = runtime.skinId; GUI:ApplyIconSkin(frame, specs[frame]) end
        return
    end
    local spec = specs[frame] or { regions = {} }
    specs[frame] = spec
    spec.id, spec.product, spec.groupId = runtime.skinId, "Halo", runtime.skinGroupId or "icons"
    spec.groupLabel = runtime.skinGroupLabel
    spec.style, spec.target = runtime.iconStyle, state.iconTarget
    spec.width, spec.height = runtime.iconWidth or runtime.iconSize or 42, runtime.iconHeight or runtime.iconSize or 42
    spec.regions.Icon, spec.regions.Backdrop = frame.Icon, state.iconTarget.background
    spec.regions.Cooldown, spec.regions.Count = frame.Cooldown, state.countTextRegion
    spec.regions.HotKey = state.keybindText
    spec.buttonType = "Aura"
    if frame.Icon and frame.Icon.Icon then
        spec.anchor, spec.parent = frame.Icon, frame.Icon
        spec.regions.Icon, spec.regions.Cooldown, spec.regions.Count = frame.Icon.Icon, nil, nil
        spec.visible = runtime.showIcon ~= false
    end
    spec.proc = state.nativeProcGlow
    spec.refresh, spec.hideBuiltin = refresh, HideBuiltin
    spec.afterApply = function(owner)
        runtime.iconStyle.effectShape = GUI:GetIconSkinEffectShape(owner, runtime.shape)
        if owner.gui2Glow and owner.gui2Glow.SetGlowSkinOwner then owner.gui2Glow:SetGlowSkinOwner(owner) end
        if afterApply then afterApply(owner) end
    end
    Effects(frame, spec)
    state.masqueActive = GUI:ApplyIconSkin(frame, spec)
    runtime.iconStyle.effectShape = GUI:GetIconSkinEffectShape(frame, runtime.shape)
end

function View:ReleaseIconSkin(owner)
    specs[owner] = nil
    if GUI.ReleaseIconSkin then GUI:ReleaseIconSkin(owner) end
end
