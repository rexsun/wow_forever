local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI or not (YUI.IsRetail or YUI.IsWrath or YUI.IsForever) then return end
local GUI, API = YUI.GUI2, YUI.API.PaperDoll
local unpack = unpack or table.unpack
local Overlays = {}
YUI.CharacterEquipmentOverlays = Overlays
local records = setmetatable({}, { __mode = "k" })
local flyoutEquipped = {}
local flyoutComparisonActive = false
local hooks = setmetatable({}, { __mode = "k" })
local flyoutHooked = false
local prefixes = { "Character", "Inspect" }
local slots = {
    { "Head", 1 }, { "Neck", 2 }, { "Shoulder", 3 }, { "Back", 15 },
    { "Chest", 5 }, { "Shirt", 4 }, { "Tabard", 19 }, { "Wrist", 9 },
    { "Hands", 10, true }, { "Waist", 6, true }, { "Legs", 7, true },
    { "Feet", 8, true }, { "Finger0", 11, true }, { "Finger1", 12, true },
    { "Trinket0", 13, true }, { "Trinket1", 14, true },
    { "MainHand", 16, true }, { "SecondaryHand", 17 }, { "Ranged", 18 },
}

local STYLE_DEFAULTS = {
    level = { prefix = "slotLevel", size = 14, x = 8, y = -2, mode = "quality" },
    enchant = { prefix = "slotEnchant", size = 12, x = 8, y = -20, mode = "fixed" },
    durability = { prefix = "slotDurability", size = 12, x = 0, y = 2, mode = "gradient" },
}
local styles = { level = {}, enchant = {}, durability = {} }
local preview, previewDB, banner, previewTooltipOwner
local previewItems = {}
local WHITE = { r = 1, g = 1, b = 1 }
local ENCHANT_COLOR = { r = .35, g = 1, b = .35 }
local GEM_GAP = 0
local weaponLayouts = {}
local layoutRestoreOwner = {}
local restorePending = false
local settingsButton, previewButton
local weaponNames = { "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local WEAPON_BOTTOM_INSET = 32

local function SamePoint(button, point)
    if button:GetNumPoints() ~= 1 then return false end
    local a, b, c, x, y = button:GetPoint(1)
    return a == point[1] and b == point[2] and c == point[3] and x == point[4] and y == point[5]
end

local function RestoreLayout(layout)
    for _, entry in ipairs(layout) do
        if SamePoint(entry.button, entry.applied) then
            entry.button:ClearAllPoints()
            for _, point in ipairs(entry.original) do entry.button:SetPoint(unpack(point)) end
        end
    end
end

local function RestoreWeaponLayouts()
    if InCombatLockdown and InCombatLockdown() then
        if YUI.Event and not restorePending and next(weaponLayouts) then
            restorePending = true
            YUI.Event:Once("PLAYER_REGEN_ENABLED", RestoreWeaponLayouts, layoutRestoreOwner)
        end
        return
    end
    if restorePending and YUI.Event then YUI.Event:OffOwner(layoutRestoreOwner) end
    restorePending = false
    for prefix, layout in pairs(weaponLayouts) do
        RestoreLayout(layout)
        weaponLayouts[prefix] = nil
    end
end

local function LayoutWeapons(prefix, db)
    if restorePending and YUI.Event then YUI.Event:OffOwner(layoutRestoreOwner); restorePending = false end
    if InCombatLockdown and InCombatLockdown() then return end
    local gemSize = math.max(8, math.min(24, tonumber(db.slotGemSize) or 16))
    local stride = math.max(80, 40 + gemSize * 2 + GEM_GAP + 8) - gemSize / 2
    local signature = stride * 100
    for index, name in ipairs(weaponNames) do
        local button = _G[prefix .. name .. "Slot"]
        if button and button:IsShown() then signature = signature + 2 ^ index end
    end
    local current = weaponLayouts[prefix]
    if current then
        if current.signature == signature then return end
        RestoreLayout(current)
        weaponLayouts[prefix] = nil
    end
    local first = _G[prefix .. "MainHandSlot"]
    if not first or not first.GetNumPoints or first:GetNumPoints() == 0 then return end
    local left = _G[prefix .. "WristSlot"] or _G[prefix .. "HeadSlot"]
    local right = _G[prefix .. "Trinket1Slot"] or _G[prefix .. "HandsSlot"]
    if not left or not right then return end
    local scale = first:GetEffectiveScale()
    local lx, ly = left:GetCenter()
    local rx, ry = right:GetCenter()
    local _, baseline = first:GetCenter()
    if not lx or not rx or not baseline then return end
    lx, ly = lx * left:GetEffectiveScale() / scale, ly * left:GetEffectiveScale() / scale
    rx, ry = rx * right:GetEffectiveScale() / scale, ry * right:GetEffectiveScale() / scale
    local host = _G[prefix .. "Frame"]
    local bottom = host and host:GetBottom()
    if bottom then
        -- The panel bottom owns this row: the native baseline must not prevent downward placement.
        baseline = bottom * host:GetEffectiveScale() / scale
            + WEAPON_BOTTOM_INSET + first:GetHeight() / 2
    end
    local center = (lx + rx) / 2
    local ranged = _G[prefix .. "RangedSlot"]
    local hasRanged = ranged and ranged:IsShown()
    local layout = { signature = signature }
    for _, name in ipairs(weaponNames) do
        local button = _G[prefix .. name .. "Slot"]
        if button and button:IsShown() and button.GetNumPoints then
            local original = {}
            for i = 1, button:GetNumPoints() do original[i] = {button:GetPoint(i)} end
            layout[#layout + 1] = { button = button, original = original, name = name }
        end
    end
    if #layout == 0 then return end
    for _, entry in ipairs(layout) do
        local point
        if entry.name == "Ammo" then
            point = hasRanged and {"LEFT", ranged, "RIGHT", 19, 0}
                or {"TOPRIGHT", right, "BOTTOMRIGHT", 0, -8}
        else
            local offset = entry.name == "MainHand" and (hasRanged and -stride or -stride / 2)
                or entry.name == "Ranged" and stride or (hasRanged and 0 or stride / 2)
            -- Only the large icons define the row center; sockets and ammo are independent.
            point = {"CENTER", left, "CENTER", center - lx + offset, baseline - ly}
        end
        entry.applied = point
        entry.button:ClearAllPoints()
        entry.button:SetPoint(unpack(point))
    end
    weaponLayouts[prefix] = layout
end
local GOLD_START, GOLD_END = { 1, .50, 0 }, { 1, .90, .35 }
local PREVIEW_GEMS = { "Interface\\Icons\\INV_Misc_Gem_Ruby_01", "Interface\\Icons\\INV_Misc_Gem_Sapphire_01",
    "Interface\\ItemSocketingFrame\\UI-EmptySocket-Blue", "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic" }
local function T(key)
    local locale = YUI.Locale and YUI.Locale:Get("CharacterEquipmentInfo")
    return locale and locale[key] or key
end
local function Number(value, fallback, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value + .5)))
end
local function ReadStyle(db, key, target)
    local defaults = STYLE_DEFAULTS[key]
    local prefix = defaults.prefix
    target = target or {}
    target.font = type(db[prefix .. "Font"]) == "string" and db[prefix .. "Font"] or
        (GUI.GetFont and GUI:GetFont("font.family.body") or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    target.size = Number(db[prefix .. "Size"], defaults.size, 8, 24)
    target.x = Number(db[prefix .. "OffsetX"], defaults.x, -40, 60)
    target.y = Number(db[prefix .. "OffsetY"], defaults.y, -60, 40)
    local outline = db[prefix .. "Outline"] or "outlineShadow"
    target.outline = (outline == "" or outline == "THICKOUTLINE") and outline or "OUTLINE"
    if outline == "shadow" then target.outline = "" end
    target.shadow = outline == "shadow" or outline == "outlineShadow"
    target.mode = db[prefix .. "ColorMode"] or (key == "level" and db.slotColorMode) or defaults.mode
    target.color = db[prefix .. "Color"] or (key == "level" and db.slotColor) or (key == "enchant" and ENCHANT_COLOR) or WHITE
    return target
end

local function SetText(region, text)
    if (region:GetText() or "") ~= text then region:SetText(text) end
end

local function Acquire(button, left, flyout, weapon)
    local record = records[button]
    if record then return record end
    -- Creating a child of a protected slot is deferred until out of combat.
    if InCombatLockdown and InCombatLockdown() then return nil end
    local frame = GUI:CreateFrame(button, { width = 1, height = 1 })
    frame:SetAllPoints(button)
    frame:EnableMouse(false)
    record = { frame = frame, button = button, left = left, flyout = flyout, weapon = weapon, data = {}, gems = {} }
    records[button] = record
    record.level = GUI:CreateText(frame, "", 12, "color.text.primary", left and "RIGHT" or "LEFT")
    record.enchant = GUI:CreateText(frame, "", 10, "color.text.primary", left and "RIGHT" or "LEFT")
    record.durability = GUI:CreateText(frame, "", 11, "color.text.primary", "CENTER")
    record.enchant:SetWordWrap(false)
    record.enchant:SetWidth(0)
    if flyout then
        record.level:SetJustifyH("RIGHT")
        record.level:SetWordWrap(false)
    end
    if weapon then
        record.level:SetJustifyH("CENTER")
        record.level:SetWordWrap(false)
        record.enchant:SetJustifyH("CENTER")
    end
    for index = 1, 4 do
        local gem = GUI:CreateTexture(frame, nil, "ARTWORK")
        record.gems[index] = gem
        gem:Hide()
    end
    if weapon then
        button:HookScript("OnEnter", function()
            local tooltip = _G.GameTooltip
            if not preview or not record.active or record.data.link ~= "preview" or not tooltip then return end
            tooltip:SetOwner(button, "ANCHOR_RIGHT")
            tooltip:SetText(T("preview.active"))
            if record.data.enchant then tooltip:AddLine(record.data.enchant, ENCHANT_COLOR.r, ENCHANT_COLOR.g, ENCHANT_COLOR.b, true) end
            tooltip:Show()
            previewTooltipOwner = button
        end)
        button:HookScript("OnLeave", function()
            if previewTooltipOwner == button then
                if _G.GameTooltip then _G.GameTooltip:Hide() end
                previewTooltipOwner = nil
            end
        end)
    end
    return record
end

local function ApplyTextStyle(region, style, data, cache)
    if cache.font ~= style.font or cache.size ~= style.size or cache.outline ~= style.outline then
        region:SetFont(style.font, style.size, style.outline)
        cache.font, cache.size, cache.outline = style.font, style.size, style.outline
    end
    if cache.shadow ~= style.shadow then
        region:SetShadowColor(0, 0, 0, style.shadow and 1 or 0)
        region:SetShadowOffset(style.shadow and 1 or 0, style.shadow and -1 or 0)
        cache.shadow = style.shadow
    end
    local r, g, b = 1, 1, 1
    if style.mode == "gradient" and data.durability then
        r, g, b = math.min(1, 2 * (1 - data.durability)), math.min(1, 2 * data.durability), 0
    elseif style.mode == "quality" and data.quality then
        r, g, b = YUI.API.Item.GetQualityColor(data.quality)
    elseif type(style.color) == "table" then
        r, g, b = style.color.r or style.color[1] or 1, style.color.g or style.color[2] or 1, style.color.b or style.color[3] or 1
    end
    if cache.r ~= r or cache.g ~= g or cache.b ~= b then
        region:SetTextColor(r, g, b)
        cache.r, cache.g, cache.b = r, g, b
    end
end

local function Place(record, key, style, x, y)
    local cache = record[key .. "Style"]
    if not cache then cache = {}; record[key .. "Style"] = cache end
    local region = record[key]
    ApplyTextStyle(region, style, record.data, cache)
    if cache.x ~= x or cache.y ~= y or cache.anchor ~= record.weaponAnchor then
        region:ClearAllPoints()
        if key == "durability" then
            region:SetPoint("BOTTOM", record.button, "BOTTOM", x, y)
        elseif record.weapon then
            region:SetPoint("TOP", record.button, "BOTTOM", x, y)
        elseif record.flyout then
            region:SetPoint("TOPRIGHT", record.button, "TOPRIGHT", x - 2, y)
        else
            region:SetPoint(record.left and "TOPRIGHT" or "TOPLEFT", record.button,
                record.left and "TOPLEFT" or "TOPRIGHT", (record.left and -1 or 1) * x, y)
        end
        cache.x, cache.y = x, y
        cache.anchor = record.weaponAnchor
    end
end

local function Render(record, db, flyout)
    local data = record.data
    if not data.link then record.frame:Hide(); return end
    local weaponWidth
    local size = Number(db.slotGemSize, 16, 8, 24)
    if record.weapon then
        weaponWidth = 74
        if record.weaponWidth ~= weaponWidth then
            record.level:SetWidth(36)
            record.weaponWidth = weaponWidth
        end
        local levelY = styles.level.y + 2
        Place(record, "level", styles.level, styles.level.x - 8, levelY)
        Place(record, "enchant", styles.enchant, styles.enchant.x - 8,
            styles.enchant.y + 20 + levelY - styles.level.size)
    else
        Place(record, "level", styles.level,
            flyout and Number(db.slotFlyoutOffsetX, 0, -40, 60) or styles.level.x,
            flyout and Number(db.slotFlyoutOffsetY, -3, -60, 40) or styles.level.y)
        Place(record, "enchant", styles.enchant, styles.enchant.x, styles.enchant.y)
    end
    Place(record, "durability", styles.durability, styles.durability.x, styles.durability.y - 2)
    local level = ((flyout and db.slotFlyout ~= false) or (not flyout and db.slotItemLevel ~= false))
        and data.level and tostring(math.floor(data.level + 0.5)) or ""
    if flyout and level ~= "" and flyoutComparisonActive
            and type(flyoutEquipped.level) == "number" and type(data.level) == "number"
            and data.level > flyoutEquipped.level then
        level = "|A:bags-greenarrow:0:0:2:2|a" .. level
    end
    SetText(record.level, level)
    local enchant = not flyout and db.slotEnchant ~= false and data.enchant or ""
    if YUI.IsRetail then
        local _, separatorEnd = enchant:find(" - ", 1, true)
        if separatorEnd and enchant:sub(separatorEnd + 1):find("%S") then
            enchant = enchant:sub(separatorEnd + 1)
        end
    end
    SetText(record.enchant, enchant)
    local count = not flyout and db.slotGems ~= false and #data.gems or 0
    local x, y = Number(db.slotGemOffsetX, 4, -40, 60), Number(db.slotGemOffsetY, 0, -40, 40)
    for index = 1, 4 do
        local gem, icon = record.gems[index], index <= count and data.gems[index] or nil
        if record.gemSize ~= size or record.gemX ~= x or record.gemY ~= y
            or record.gemAnchor ~= record.weaponAnchor or record.gemCount ~= count
            or record.gemAnchorX ~= styles.enchant.x or record.gemAnchorY ~= styles.enchant.y
            or record.gemAnchorSize ~= styles.enchant.size or record.gemLevelSize ~= styles.level.size then
            gem:SetSize(size, size)
            gem:ClearAllPoints()
            if record.weapon then
                gem:SetPoint("RIGHT", record.button, "LEFT", -x,
                    ((count - 1) / 2 - (index - 1)) * (size + GEM_GAP) + y)
            else
                local direction = record.left and -1 or 1
                gem:SetPoint(record.left and "RIGHT" or "LEFT", record.level,
                    record.left and "LEFT" or "RIGHT", direction * (x + (index - 1) * (size + GEM_GAP)), y)
            end
        end
        if record[index] ~= icon then
            gem:SetTexture(icon)
            gem:SetShown(icon ~= nil)
            record[index] = icon
        end
    end
    record.gemSize, record.gemX, record.gemY = size, x, y
    record.gemAnchor, record.gemCount = record.weaponAnchor, count
    record.gemAnchorX, record.gemAnchorY, record.gemAnchorSize = styles.enchant.x, styles.enchant.y, styles.enchant.size
    record.gemLevelSize = styles.level.size
    local durability = db.slotDurability ~= false and data.durability or nil
    SetText(record.durability, durability and durability < 1 and string.format("%d%%", math.floor(durability * 100 + 0.5)) or "")
    record.frame:Show()
end

function Overlays:IsSuppressed()
    local provider = _G.EllesmereUI
    if not provider or type(provider.GetBlizzWindowStyle) ~= "function" then return false end
    local ok, style = pcall(provider.GetBlizzWindowStyle, "charsheet")
    return ok and type(style) == "string" and style ~= "" and style ~= "off"
end

function Overlays:IsPreviewing() return preview == true end

function Overlays:BindPreviewButton(button)
    previewButton = button
    button:SetText(T(preview and "preview.stop" or "preview.random"))
    button:HookScript("OnHide", function()
        if previewButton == button then previewButton = nil end
    end)
end

local function UpdateSettingsButton()
    local host = _G.CharacterFrame
    if not host or not GUI.CreateBlizzardIconButton then return end
    if not settingsButton then
        if InCombatLockdown and InCombatLockdown() then return end
        local atlas = "Warfronts-BaseMapIcons-Empty-Workshop-Minimap"
        local hasAtlas, atlasInfo
        if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
            hasAtlas, atlasInfo = pcall(C_Texture.GetAtlasInfo, atlas)
        end
        settingsButton = GUI:CreateBlizzardIconButton(host, {
            atlas = hasAtlas and atlasInfo and atlas or nil,
            size = 22, texture = GUI:GetSettingsIcon("settings"), crop = false,
            tooltip = T("settings.open"),
            onClick = function()
                if YUI.Settings and YUI.Settings.OpenComponentFeature then
                    YUI.Settings:OpenComponentFeature("CharacterEquipmentInfo")
                end
            end,
        })
        settingsButton.icon:ClearAllPoints()
        settingsButton.icon:SetSize(16, 16)
        settingsButton.icon:SetPoint("CENTER", settingsButton, "CENTER", 0, 0)
        local close = host.CloseButton or _G.CharacterFrameCloseButton
        if close then settingsButton:SetPoint("RIGHT", close, "LEFT", -5, 0)
        else settingsButton:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -6) end
        local border = host.BorderFrame
        settingsButton:SetFrameLevel(math.max(host:GetFrameLevel() + 10,
            close and close:GetFrameLevel() + 1 or 0, border and border:GetFrameLevel() + 1 or 0))
    end
    settingsButton:SetShown(_G.PaperDollFrame and _G.PaperDollFrame:IsShown())
end

function Overlays:StopPreview()
    preview, previewDB = false, nil
    if previewButton then previewButton:SetText(T("preview.random")) end
    if previewTooltipOwner then
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        previewTooltipOwner = nil
    end
    if banner then banner:Hide() end
    for key in pairs(previewItems) do previewItems[key] = nil end
end

function Overlays:Preview(db)
    if self:IsSuppressed() then self:Refresh(db); return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (_G.PaperDollFrame and _G.PaperDollFrame:IsShown()) and _G.ToggleCharacter then
        ToggleCharacter("PaperDollFrame")
    end
    if not (_G.PaperDollFrame and _G.PaperDollFrame:IsShown()) then return end
    preview, previewDB = true, db
    if previewButton then previewButton:SetText(T("preview.stop")) end
    for _, slot in ipairs(slots) do
        local data = { link = "preview", level = math.random(100, 300), quality = math.random(2, 5),
            enchant = T("preview.enchant" .. math.random(1, 3)), durability = math.random(0, 100) / 100, gems = {} }
        data.gems[1], data.gems[2] = PREVIEW_GEMS[math.random(1, 2)], PREVIEW_GEMS[math.random(3, 4)]
        for index = 3, math.random(2, 4) do data.gems[index] = PREVIEW_GEMS[math.random(1, 4)] end
        previewItems[slot[2]] = data
    end
    local model = _G.CharacterModelScene or _G.CharacterModelFrame or _G.PaperDollFrame
    if not banner then
        banner = GUI:CreateFrame(_G.PaperDollFrame, { width = 250, height = 50 })
        banner:EnableMouse(false)
        banner.label = GUI:CreateText(banner, "", 32, "color.text.primary", "CENTER")
        banner.label:SetAllPoints(banner)
    end
    banner:SetFrameStrata(_G.PaperDollFrame:GetFrameStrata())
    banner:SetFrameLevel(math.max(_G.PaperDollFrame:GetFrameLevel(), model:GetFrameLevel()) + 20)
    banner:ClearAllPoints()
    banner:SetPoint("CENTER", model, "CENTER", 0, 0)
    local text = T("preview.active")
    if YUI.F and YUI.F.GetGradientText then text = YUI.F:GetGradientText(text, GOLD_START, GOLD_END) end
    banner.label:SetText(text)
    banner:Show()
    self:Refresh(db)
end

function Overlays:Refresh(db)
    flyoutComparisonActive = false
    UpdateSettingsButton()
    local suppressed = self:IsSuppressed()
    if suppressed then
        self:StopPreview()
        RestoreWeaponLayouts()
    end
    if preview and (db ~= previewDB or not (_G.PaperDollFrame and _G.PaperDollFrame:IsShown())) then self:StopPreview() end
    for key, target in pairs(styles) do ReadStyle(db, key, target) end
    if db.slotItemLevel == false and db.slotFlyout == false and db.slotEnchant == false and db.slotGems == false and db.slotDurability == false then
        self:StopPreview()
        RestoreWeaponLayouts()
        for _, record in pairs(records) do record.active = false; record.frame:Hide() end
        return
    end
    for _, record in pairs(records) do record.active = false end
    for _, prefix in ipairs(prefixes) do
        local host = prefix == "Character" and _G.PaperDollFrame or _G.InspectFrame
        local unit = prefix == "Character" and "player" or (host and host.unit)
        local paperDoll = prefix == "Inspect" and _G.InspectPaperDollFrame or host
        if not suppressed and host and host:IsShown() and paperDoll and paperDoll:IsShown() and unit then
            for _, slot in ipairs(slots) do
                local button = _G[prefix .. slot[1] .. "Slot"]
                if button and button:IsShown() then
                    local record = Acquire(button, slot[3], false, slot[2] >= 16 and slot[2] <= 18 and slot[2])
                    if record then
                        if record.weapon then record.weaponAnchor = button end
                        record.active = true
                        if preview and unit == "player" then
                            record.data = previewItems[slot[2]]
                        else
                            if record.data.link == "preview" then record.data = {} end
                            API.ReadSlotDisplay(unit, slot[2], nil, record.data)
                        end
                        Render(record, db, false)
                    end
                end
            end
            LayoutWeapons(prefix, db)
        end
    end
    local flyout = _G.EquipmentFlyoutFrame
    if db.slotFlyout ~= false and flyout and flyout:IsShown() then
        for _, slot in ipairs(slots) do
            if flyout.button and flyout.button == _G["Character" .. slot[1] .. "Slot"] then
                API.ReadSlotDisplay("player", slot[2], nil, flyoutEquipped)
                flyoutComparisonActive = true
                break
            end
        end
        for _, button in ipairs(flyout.buttons or {}) do
            if button:IsShown() then
                local record = Acquire(button, false, true)
                if record then
                    record.active = true
                    API.ReadFlyoutDisplay(button.location, record.data)
                    Render(record, db, true)
                end
            end
        end
    end
    for _, record in pairs(records) do if not record.active then record.frame:Hide() end end
end

function Overlays:HasPending(itemID)
    if flyoutComparisonActive and flyoutEquipped.pending and flyoutEquipped.itemID == itemID then return true end
    for button, record in pairs(records) do
        if record.active and button:IsShown() and record.data.pending
            and (record.data.itemID == itemID or (record.data.pendingItems and record.data.pendingItems[itemID])) then return true end
    end
    return false
end

function Overlays:Hook(refresh)
    local host = _G.PaperDollFrame
    if host and not hooks[host] then
        hooks[host] = true
        host:HookScript("OnHide", function() self:StopPreview(); refresh() end)
    end
    if not flyoutHooked and type(EquipmentFlyout_UpdateItems) == "function" and hooksecurefunc then
        hooksecurefunc("EquipmentFlyout_UpdateItems", refresh)
        flyoutHooked = true
    end
    local flyout = _G.EquipmentFlyoutFrame
    if flyout and not hooks[flyout] then
        hooks[flyout] = true
        flyout:HookScript("OnShow", refresh)
        flyout:HookScript("OnHide", refresh)
    end
end

function Overlays:Hide(keepSettingsButton)
    flyoutComparisonActive = false
    self:StopPreview()
    if settingsButton and not keepSettingsButton then settingsButton:Hide() end
    RestoreWeaponLayouts()
    for _, record in pairs(records) do record.active = false; record.frame:Hide() end
end

-- Settings are cold-built. Each field applies only the visible overlay state.
function Overlays:BuildOptions(db, fonts, refresh)
    local options = {}
    local function Section(key, fields, expanded)
        options[#options + 1] = { type = "divider", label = T("section." .. key), width = 560,
            alignLeft = true, collapsible = true, collapseKey = "equipment." .. key, collapsed = not expanded }
        options[#options + 1] = { type = "custom", width = 560, fields = fields,
            render = function(parent, x, y, width)
                local settings = YUI.Settings
                if not settings or not settings.RenderAlignedFields then return 560, 1 end
                local _, w, h = settings:RenderAlignedFields(parent, {
                    x = x, y = y, width = math.min(width or 560, 560), columns = 2, columnGap = 24,
                    labelWidth = 88, labelGap = 8, bodyWidth = 160, valueWidth = 44, valueGap = 8,
                    rowHeight = 30, rowGap = 8, fields = fields,
                })
                for _, field in ipairs(fields) do
                    if field.updateVisibility then field.updateVisibility() end
                end
                return w, h
            end }
    end
    local function Toggle(key, label)
        return { type = "checkbox", label = T(label or "settings.enabled"), labelPosition = "left",
            get = function() return db[key] ~= false end,
            set = function(value) db[key] = value == true; refresh() end }
    end
    local function Slider(key, label, default, minimum, maximum)
        return { type = "slider", label = T("settings." .. label), min = minimum, max = maximum, step = 1,
            get = function() return Number(db[key], default, minimum, maximum) end,
            set = function(value) db[key] = Number(value, default, minimum, maximum); refresh() end }
    end
    local function TextFields(key, enabled)
        local default = STYLE_DEFAULTS[key]
        local prefix = default.prefix
        local colorField
        local function UpdateColorVisibility()
            local shown = ReadStyle(db, key).mode == "fixed"
            if colorField.widget then colorField.widget:SetShown(shown) end
            if colorField.labelRegion then colorField.labelRegion:SetShown(shown) end
        end
        local modes = { { text = T("settings.color_quality"), value = "quality" }, { text = T("settings.color_fixed"), value = "fixed" } }
        if key == "durability" then table.insert(modes, 1, { text = T("settings.color_gradient"), value = "gradient" }) end
        local fields = { Toggle(enabled),
            { type = "dropdown", label = T("settings.font"), options = fonts,
                get = function() return ReadStyle(db, key).font end,
                set = function(value) db[prefix .. "Font"] = value; refresh() end },
            Slider(prefix .. "Size", "size", default.size, 8, 24),
            { type = "dropdown", label = T("settings.outline"), options = GUI.Form:BuildFontOutlineOptions({
                values = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" },
            }),
                get = function()
                    local style = ReadStyle(db, key)
                    return style.shadow and (style.outline == "" and "shadow" or "outlineShadow") or style.outline
                end,
                set = function(value) db[prefix .. "Outline"] = value; refresh() end },
            { type = "dropdown", label = T("settings.color_mode"), options = modes,
                get = function() return ReadStyle(db, key).mode end,
                set = function(value) db[prefix .. "ColorMode"] = value; refresh(); UpdateColorVisibility() end },
            { type = "color", label = T("settings.slotColor"), hasAlpha = false,
                default = key == "enchant" and ENCHANT_COLOR or WHITE,
                get = function() return ReadStyle(db, key).color end,
                set = function(value) db[prefix .. "Color"] = value; refresh() end },
            Slider(prefix .. "OffsetX", key == "durability" and "offset_x" or "distance", default.x, -40, 60),
            Slider(prefix .. "OffsetY", "offset_y", default.y, -60, 40),
        }
        colorField = fields[6]
        colorField.updateVisibility = UpdateColorVisibility
        return fields
    end
    local fields = TextFields("level", "slotItemLevel")
    fields[#fields + 1] = Toggle("slotFlyout", "settings.flyout")
    fields[#fields + 1] = { type = "custom", render = function() return nil end }
    fields[#fields + 1] = Slider("slotFlyoutOffsetX", "flyout_x", 0, -40, 60)
    fields[#fields + 1] = Slider("slotFlyoutOffsetY", "flyout_y", -3, -60, 40)
    Section("level", fields, true)
    if self:IsSuppressed() then
        table.insert(options, 2, { type = "text", label = T("settings.compatibility_active") })
    end
    Section("enchant", TextFields("enchant", "slotEnchant"))
    Section("gems", { Toggle("slotGems"), Slider("slotGemSize", "icon_size", 16, 8, 24),
        Slider("slotGemOffsetX", "gem_distance", 4, -40, 60), Slider("slotGemOffsetY", "offset_y", 0, -40, 40) })
    Section("durability", TextFields("durability", "slotDurability"))
    return options
end
