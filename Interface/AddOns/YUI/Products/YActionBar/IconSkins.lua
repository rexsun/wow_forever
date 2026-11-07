local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
local GUI = YUI and YUI.GUI2
if not (YAB and GUI) then return end
local Adapter = {}
YAB.IconSkinAdapter = Adapter

local function HideBuiltin(button)
    local visual = YAB.Visuals.buttons[button]
    if not visual then return end
    if visual.bg then visual.bg:Hide() end
    for _, edge in pairs(visual.border or {}) do edge:Hide() end
    if visual.shapeBorder then visual.shapeBorder:Hide() end
    if visual.bgSlotArt then visual.bgSlotArt:Hide() end
    if visual.checkedRing then visual.checkedRing:Hide() end
    if visual.actionStateFrame then visual.actionStateFrame:Hide() end
    GUI:HideShapeShadow(visual.shadowHandle)
end

local function Refresh(button)
    YAB.Visuals:RefreshIconSkin(button)
end

local function AfterApply(button)
    local visual = YAB.Visuals.buttons[button]
    if not visual then return end
    if visual.pressedOverlay then visual.pressedOverlay:SetShown(visual.pressed == true) end
    if visual.checkedOverlay then visual.checkedOverlay:SetShown(visual.checked == true) end
    -- 充能边缘是否显示属于业务策略，皮肤只提供边缘材质。
    if visual.chargeCooldown then
        YAB.Visuals:ApplyChargeCooldownPresentation(visual.chargeCooldown, visual.runtimeSnapshot)
    end
end

function Adapter:Apply(button, visual, snapshot)
    if snapshot.skinId ~= "masque" then
        visual.masqueActive = false
        if visual.iconSkinSpec then
            visual.iconSkinSpec.id = snapshot.skinId
            GUI:ApplyIconSkin(button, visual.iconSkinSpec)
        end
        return
    end
    local spec = visual.iconSkinSpec or {}
    visual.iconSkinSpec = spec
    spec.id, spec.product = snapshot.skinId, "Flare"
    spec.groupId = snapshot.barId or button.yabBarId or "actions"
    local labelKey = "bar." .. spec.groupId
    if spec.groupId == "stance" and YAB.Client and YAB.Client.ownedStanceButtons then
        labelKey = "bar.stance.retail"
    end
    local locale = YUI.Locale and YUI.Locale:Get("YActionBar")
    local label = locale and locale[labelKey]
    spec.groupLabel = type(label) == "string" and label ~= "" and label ~= labelKey and label or nil
    -- 预览复用真实条的皮肤设置，不使用临时按钮身份创建配置组。
    spec.width, spec.height = visual.visualWidth or snapshot.size or 36, visual.visualHeight or snapshot.size or 36
    spec.style = visual.sharedIconSnapshot
    spec.regions = spec.regions or {}
    local regions = spec.regions
    regions.Icon, regions.Backdrop = visual.icon, visual.bg
    regions.Highlight, regions.Pushed, regions.Checked = visual.hover, visual.pressedOverlay, visual.checkedOverlay
    regions.Cooldown, regions.ChargeCooldown = visual.cooldown, visual.chargeCooldown
    regions.CooldownLoC = button.lossOfControlCooldown
    regions.Count, regions.HotKey, regions.Name = visual.count, visual.hotkey, visual.name
    spec.autoCast = visual.autoCastOverlay
    spec.extraRegions = {}
    if spec.autoCast then
        for _, region in pairs({ spec.autoCast, spec.autoCast.Shine, spec.autoCast.Mask, spec.autoCast.Corners }) do
            spec.extraRegions[#spec.extraRegions + 1] = region
        end
    end
    spec.proc, spec.assisted = visual.procGlowFrame, visual.assistedHighlightGlowFrame
    spec.refresh, spec.hideBuiltin, spec.afterApply = Refresh, HideBuiltin, AfterApply
    visual.masqueActive = GUI:ApplyIconSkin(button, spec)
end
