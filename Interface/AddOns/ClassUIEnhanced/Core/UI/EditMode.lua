
local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field EditMode editmode

---@class editmode : table
---@field Initialize fun() Registers all component frames with LibEditMode after PLAYER_LOGIN
---@field Refresh fun() Rebuilds Edit Mode settings for all components (call on profile change)
---@field UnregisterAdditionalFrame fun(component: component) Removes an additional frame from LibEditMode

---@type editmode
---@diagnostic disable-next-line: missing-fields
local editmode = {}

local LibEditMode = LibStub("LibEditMode")
local LibSharedMedia = LibStub("LibSharedMedia-3.0")

local L = private.L

---Human-readable display names shown in the LibEditMode dialog for each component.
---@type table<string, string>
local displayNames = {
    CooldownTracker = L["COMP_COOLDOWN_TRACKER"],
    TrinketTracker = L["COMP_TRINKET_TRACKER"],
    RacialTracker = L["COMP_RACIAL_TRACKER"],
    ConsumableTracker = L["COMP_CONSUMABLE_TRACKER"],
    ConsumableBuffTracker = L["COMP_CONSUMABLE_BUFF_TRACKER"],
    RaidBuffTracker = L["COMP_RAID_BUFF_TRACKER"],
    OutboundBuffTracker = L["COMP_OUTBOUND_BUFF_TRACKER"],
    BuffTracker = L["COMP_BUFF_TRACKER"],
    BuffTrackerBars = L["COMP_BUFF_TRACKER_BARS"],
    UtilitiesTracker = L["COMP_UTILITIES_TRACKER"],
    PlayerCastBar = L["COMP_PLAYER_CAST_BAR"],
    TargetCastBar = L["COMP_TARGET_CAST_BAR"],
    FocusCastBar = L["COMP_FOCUS_CAST_BAR"],
    GlobalCooldown = L["COMP_GLOBAL_COOLDOWN"],
    PrimaryResources = L["COMP_PRIMARY_RESOURCES"],
    PlayerHealthBar = L["COMP_PLAYER_HEALTH_BAR"],
    SecondaryResources = L["COMP_SECONDARY_RESOURCES"],
}

---Width slider bounds per component.
---Viewer tracker frames need wider range (icon_size × icon count); cast bars
---and resource bars are kept narrower.
---@type table<string, {widthMin:number, widthMax:number}>
local widthConfig = {
    CooldownTracker = {widthMin = 20, widthMax = 1000},
    ConsumableBuffTracker = {widthMin = 20, widthMax = 1000},
    RaidBuffTracker = {widthMin = 20, widthMax = 1000},
    OutboundBuffTracker = {widthMin = 20, widthMax = 1000},
    BuffTracker = {widthMin = 20, widthMax = 1000},
    BuffTrackerBars = {widthMin = 100, widthMax = 1000},
    UtilitiesTracker = {widthMin = 20, widthMax = 1000},
    PlayerCastBar = {widthMin = 20, widthMax = 1000},
    TargetCastBar = {widthMin = 20, widthMax = 1000},
    FocusCastBar = {widthMin = 20, widthMax = 1000},
    GlobalCooldown = {widthMin = 20, widthMax = 1000},
    PrimaryResources = {widthMin = 20, widthMax = 1000},
    PlayerHealthBar = {widthMin = 20, widthMax = 1000},
    SecondaryResources = {widthMin = 20, widthMax = 1000},
}

---Height slider bounds per component.
---Tall viewer frames (CooldownTracker, BuffTracker) allow a larger range;
---cast bars and resource bars are kept compact.
---@type table<string, {heightMin:number, heightMax:number}>
local heightConfig = {
    CooldownTracker = {heightMin = 25, heightMax = 600},
    ConsumableBuffTracker = {heightMin = 25, heightMax = 600},
    RaidBuffTracker = {heightMin = 25, heightMax = 600},
    OutboundBuffTracker = {heightMin = 25, heightMax = 600},
    BuffTracker = {heightMin = 25, heightMax = 600},
    BuffTrackerBars = {heightMin = 25, heightMax = 300},
    UtilitiesTracker = {heightMin = 25, heightMax = 600},
    PlayerCastBar = {heightMin = 5, heightMax = 50},
    TargetCastBar = {heightMin = 5, heightMax = 50},
    FocusCastBar = {heightMin = 5, heightMax = 50},
    GlobalCooldown = {heightMin = 3, heightMax = 50},
    PrimaryResources = {heightMin = 5, heightMax = 50},
    PlayerHealthBar = {heightMin = 5, heightMax = 50},
    SecondaryResources = {heightMin = 5, heightMax = 50},
}

---Components whose frame height is driven by their icon layout (CooldownTracker / BuffTracker).
---These components skip the Height slider (height is computed) and gain an icon layout section.
---Additional icon-type frames are added dynamically via RegisterAdditionalFrame.
---@type table<string, boolean>
local viewerTrackerComponents = {
    CooldownTracker = true,
    BuffTracker = true,
    UtilitiesTracker = true,
}

---Components whose frame dimensions are driven by bar layout (bar_width × visible count).
---These components skip the generic Width and Height sliders and gain a bar layout section.
---@type table<string, boolean>
local barTrackerComponents = {
    BuffTrackerBars = true,
    OutboundBuffTracker = true,
}

---Components that support the Auto-Hide setting (class/spec-based hiding).
---@type table<string, boolean>
local autoHideComponents = {
    PrimaryResources = true,
    ConsumableTracker = true,
}

---Width % slider bounds for components that support relative sizing against their anchor parent.
---Cast bars: 25–200%, resource bars and viewer trackers: 50–200%.
---Components absent from this table receive no Width % slider.
---@type table<string, {min:number, max:number}>
local widthPctConfig = {
    PlayerCastBar = {min = 25, max = 200},
    TargetCastBar = {min = 25, max = 200},
    FocusCastBar = {min = 25, max = 200},
    PrimaryResources = {min = 50, max = 200},
    PlayerHealthBar = {min = 50, max = 200},
    SecondaryResources = {min = 50, max = 200},
    BuffTracker = {min = 25, max = 200},
    UtilitiesTracker = {min = 25, max = 200},
    OutboundBuffTracker = {min = 25, max = 200},
    BuffTrackerBars = {min = 25, max = 200},
    -- Present in Options' trackerWidthPctConfig; its absence here left Edit Mode
    -- with no width-mode/width-% controls for the GCD bar at all, and left the
    -- absolute Width slider live in percent mode where it does nothing.
    GlobalCooldown = {min = 25, max = 200},
}

---Distance in screen pixels (UIParent-scaled) the user must drag an anchored
---component away from its anchor position before it automatically detaches to
---free-moving mode.
local DETACH_THRESHOLD = 80

---Return the x, y coordinates of a named anchor point within a rectangle.
---@param point string WoW anchor point name (e.g. "CENTER", "TOPLEFT")
---@param left number
---@param right number
---@param top number
---@param bottom number
---@return number x, number y
local function getPointOnRect(point, left, right, top, bottom)
    local cx = (left + right) / 2
    local cy = (top + bottom) / 2
    local coords = {
        CENTER = {cx, cy},
        TOP = {cx, top}, BOTTOM = {cx, bottom},
        LEFT = {left, cy}, RIGHT = {right, cy},
        TOPLEFT = {left, top}, TOPRIGHT = {right, top},
        BOTTOMLEFT = {left, bottom}, BOTTOMRIGHT = {right, bottom},
    }
    local p = coords[point] or coords.CENTER
    return p[1], p[2]
end

---Capture a frame's screen rect into anchor_profile SetPoint fields for free-move mode.
---Enumerates every (frame_point, parent_point) pair permitted by the component's
---layout_alignment / layout_direction constraints and picks the pair whose pivots
---are geometrically closest in screen space. frame_point is never CENTER; cardinal
---frame_points may pair with UIParent CENTER when that is closer than the same-side
---parent point. Compound frame_points always pair same-to-same.
---@param _ any Unused (formerly componentName)
---@param settings component_profile_main
---@param anchorProfile anchor_profile
---@param left number Scaled screen-space left edge (frame:GetLeft() * scale)
---@param right number Scaled screen-space right edge
---@param top number Scaled screen-space top edge
---@param bottom number Scaled screen-space bottom edge
---@param scale number Frame effective scale
local function capturePositionForFreeMove(_, settings, anchorProfile, left, right, top, bottom, scale)
    local parentWidth, parentHeight = UIParent:GetSize()
    local alignment = settings.layout_alignment
    local layoutDir = settings.layout_direction or settings.layout
    local isHorizontal = layoutDir and (layoutDir == "horizontal" or layoutDir == "block")

    local candidates
    if alignment and alignment ~= "center" and layoutDir then
        if isHorizontal then
            if alignment == "left" then
                candidates = {"LEFT", "TOPLEFT", "BOTTOMLEFT"}
            elseif alignment == "right" then
                candidates = {"RIGHT", "TOPRIGHT", "BOTTOMRIGHT"}
            end
        else
            if alignment == "top" then
                candidates = {"TOP", "TOPLEFT", "TOPRIGHT"}
            elseif alignment == "bottom" then
                candidates = {"BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT"}
            end
        end
    elseif layoutDir then
        candidates = isHorizontal and {"TOP", "BOTTOM"} or {"LEFT", "RIGHT"}
    end
    if not candidates then
        candidates = {"TOP", "BOTTOM", "LEFT", "RIGHT",
                      "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
    end

    local bestFrame, bestParent, bestDist = nil, nil, math.huge
    for _, fp in ipairs(candidates) do
        local fx, fy = getPointOnRect(fp, left, right, top, bottom)
        local isCompound = (fp == "TOPLEFT" or fp == "TOPRIGHT"
                         or fp == "BOTTOMLEFT" or fp == "BOTTOMRIGHT")
        local parentOptions = isCompound and {fp} or {fp, "CENTER"}
        for _, pp in ipairs(parentOptions) do
            local px, py = getPointOnRect(pp, 0, parentWidth, parentHeight, 0)
            local dx, dy = fx - px, fy - py
            local dist = dx * dx + dy * dy
            if dist < bestDist then
                bestFrame, bestParent, bestDist = fp, pp, dist
            end
        end
    end

    local fx, fy = getPointOnRect(bestFrame, left, right, top, bottom)
    local px, py = getPointOnRect(bestParent, 0, parentWidth, parentHeight, 0)
    anchorProfile.frame_point = bestFrame
    anchorProfile.parent_point = bestParent
    anchorProfile.frame_point_manual = nil
    anchorProfile.relative_frame = "UIParent"
    anchorProfile.xoff = math.floor((fx - px) / scale)
    anchorProfile.yoff = math.floor((fy - py) / scale)
end

---Write a free-move frame_point or parent_point and recompute xoff/yoff so the
---frame stays where it is. Measured against the frame it is actually anchored
---to (GetPoint), converted into the frame's own units, so any relative_frame
---works. A frame with no rect yet gets the point and keeps its offsets.
---@param frame frame?
---@param anchorProfile anchor_profile
---@param key "frame_point"|"parent_point"
---@param value string
local function setFreeMovePoint(frame, anchorProfile, key, value)
    anchorProfile[key] = value
    if not frame then return end
    local left, bottom, width, height = frame:GetRect()
    if not left then return end
    local _, relativeTo = frame:GetPoint(1)
    relativeTo = relativeTo or UIParent
    local rLeft, rBottom, rWidth, rHeight = relativeTo:GetRect()
    if not rLeft then return end
    local ratio = relativeTo:GetEffectiveScale() / frame:GetEffectiveScale()
    local fx, fy = getPointOnRect(string.upper(anchorProfile.frame_point or "TOP"),
        left, left + width, bottom + height, bottom)
    local px, py = getPointOnRect(string.upper(anchorProfile.parent_point or "CENTER"),
        rLeft * ratio, (rLeft + rWidth) * ratio, (rBottom + rHeight) * ratio, rBottom * ratio)
    anchorProfile.xoff = math.floor(fx - px + 0.5)
    anchorProfile.yoff = math.floor(fy - py + 0.5)
end

---The component's own defaults: its `Profile.lua` entry for a built-in
---component, a freshly made template for an Additional Frame. Read only.
---@param component component
---@return table?
local function getDefaultSettings(component)
    local frameType = component.GetSettings().frame_type
    if frameType then
        return private.AdditionalFrameManager.GetDefaultSettings(frameType)
    end
    return private.defaultSettings.profile.components[component.GetComponentName()]
end

---Default at a reset path: `<key>` or `<table>.<key>` in `defaults`, or
---`profile.<key>` for a profile-level setting.
---@param defaults table?
---@param path string
---@return any
local function readDefault(defaults, path)
    local profileKey = path:match("^profile%.(.+)$")
    if profileKey then
        return private.defaultSettings.profile[profileKey]
    end
    if not defaults then return nil end
    local head, key = path:match("^([^.]+)%.(.+)$")
    if not head then
        return defaults[path]
    end
    local t = defaults[head]
    if type(t) ~= "table" then return nil end
    return t[key]
end

---A default is never handed out by reference: the defaults table would then
---be edited through the live profile.
local function copyDefault(value)
    if type(value) == "table" then return CopyTable(value) end
    return value
end

---Puts the component back on its default anchor: the default anchor_profile,
---copied into the live table in place, since closures and the anchor tree
---hold that table. Refused, with the anchor setters' message, when the
---default parent would close an anchor cycle in the current layout.
---@param component component
---@param defaults table?
---@return boolean restored
local function restoreDefaultAnchor(component, defaults)
    local defaultAnchor = defaults and defaults.anchor_profile
    if not defaultAnchor then return false end
    local componentName = component.GetComponentName()
    local target = defaultAnchor.anchor_parent
    if not target or target == "none" or target == "cursor" then
        target = defaultAnchor.position_reference
    end
    if target and private.Anchor.WouldCreateCycle(componentName, target) then
        private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"],
            displayNames[componentName] or componentName, displayNames[target] or target))
        return false
    end
    local anchorProfile = component.GetSettings().anchor_profile
    wipe(anchorProfile)
    for k, v in pairs(defaultAnchor) do
        anchorProfile[k] = v
    end
    return true
end

---Reset To Default: every setting the component's Edit Mode panel shows goes
---back to the component's default, then the layout runs once. A dotted path
---restores one key of a nested table in place, so the Options-only keys beside
---it (a keybind font's face, a glow's colours) are left alone.
---@param component component
---@param paths string[]  the panel's reset paths (buildFrameSettings' `def` / `track`)
local function resetToDefaults(component, paths)
    local defaults = getDefaultSettings(component)
    if not defaults then return end
    local settings = component.GetSettings()
    local anchorShown, glowTurnedOff = false, false
    for _, path in ipairs(paths) do
        local profileKey = path:match("^profile%.(.+)$")
        local head, key = path:match("^([^.]+)%.(.+)$")
        if profileKey then
            private.profile[profileKey] = copyDefault(readDefault(defaults, path))
        elseif path == "anchor_profile" or head == "anchor_profile" then
            anchorShown = true
        elseif head then
            local t = settings[head]
            if type(t) == "table" then
                local value = readDefault(defaults, path)
                if head == "glow" and t[key] == true and value == false then
                    glowTurnedOff = true
                end
                t[key] = copyDefault(value)
            end
        else
            settings[path] = copyDefault(defaults[path])
        end
    end
    if anchorShown then
        restoreDefaultAnchor(component, defaults)
    end
    -- The glow setters stop running glows when one is switched off; a Refresh
    -- does not.
    if glowTurnedOff and component.StopAllGlows then
        component.StopAllGlows()
    end
    private.Anchor.InvalidateTargetRuleCache()
    private.Anchor.RebuildAnchorTree()
    -- Fonts, icon geometry and bar layout are applied in the font pass, which a
    -- Refresh runs only with the flag up (.context/patterns.md, fontsDirty).
    private.fontsDirty = true
    if component.RefreshAndRelayout then
        component.RefreshAndRelayout()
    else
        component.Refresh()
    end
    private.fontsDirty = false
    private.ComponentManager.RefreshAllComponents()
    private.Anchor.Refresh()
end

---LibEditMode's registered default position, and the Reset Position button's
---signature: the dialog moves the frame here and fires the position callback
---with these exact values. No layout pass writes these offsets and a drag
---will not land on them exactly, so the callback can tell a reset from a move.
local RESET_POSITION = {point = "CENTER", x = 0.123, y = 0.456}

---Build the LibEditMode settings array for one component.
---All get/set callbacks read from and write to private.profile via component.GetSettings().
---
---Section order: Enabled → Anchoring and Size → (Icon Layout) → (Font).
---Anchor Side, Anchor Offset, and Width % are hidden when the component is free-moving.
---The Width slider is disabled when anchored and Width % is available.
---@param component component
---@return table settings array for LibEditMode:AddFrameSettings()
local function buildFrameSettings(component)
    local componentName = component.GetComponentName()
    local wc = widthConfig[componentName] or {widthMin = 20, widthMax = 1000}
    local hc = heightConfig[componentName] or {heightMin = 5, heightMax = 150}
    local wpc = widthPctConfig[componentName]
    local ST = LibEditMode.SettingType

    -- Every widget names the setting it shows, through `def` (which also hands
    -- it the component's default to display) or `track`. Reset To Default
    -- restores exactly that list -- see the wrap at the end of this function.
    local defaults = getDefaultSettings(component)
    local resetPaths = {}
    local function track(path)
        resetPaths[#resetPaths + 1] = path
    end
    local function def(path, fallback)
        track(path)
        local value = readDefault(defaults, path)
        if value == nil then return fallback end
        return value
    end

    -- Shared predicate: true when the component has no anchor parent (free-moving).
    -- Used as the hidden callback for anchoring-only settings.
    -- Secure components (position_reference only) are always free-moving.
    -- secureCLICK, not secure: only SecureActionButton chains cascade blocked
    -- ops, so only those two components are steered onto position_reference.
    -- The AuraContainer trackers ship real anchor_parent chains (Anchoring.lua).
    local isSecure = private.Anchor.secureClickComponents[componentName]
    local isAdditionalFrame = component.GetSettings().frame_type ~= nil
    local function isFreeMoving(_)
        if isSecure then
            -- A secure component positions by following a reference frame's
            -- screen rect, so it is free only while no reference is set.
            -- Hardcoding `true` here hid the width controls even once one was
            -- chosen — Options.buildAnchoringWidgets has always read the
            -- reference, and this is the copy that drifted.
            local pr = component.GetSettings().anchor_profile.position_reference
            return not pr or pr == "none"
        end
        -- A cursor-following Additional Frame is anchored -- to the cursor, by
        -- Anchor Side and the anchor offsets -- as the Options panel reads it.
        local ap = component.GetSettings().anchor_profile.anchor_parent
        return not ap or ap == "none"
    end

    -- anchor_parent dropdown: "none" + every other registered component + external anchors.
    -- Non-anchorable components (e.g. BuffTracker) are excluded because their dynamic
    -- content makes them unreliable layout parents (see Anchoring.lua nonAnchorableComponents).
    -- Returns a fresh table each call so external anchors added via AddAnchors() after init
    -- appear immediately without needing an EditMode.Refresh().
    local function anchorParentValues()
        local values = {{text = L["ANCHOR_NONE"], value = "none"}}
        -- Additional frames can follow the mouse cursor as an anchor mode.
        if isAdditionalFrame then
            values[#values + 1] = {text = L["ANCHOR_CURSOR"], value = "cursor"}
        end
        local iAmSecure = private.Anchor.secureClickComponents[componentName]
        for _, other in ipairs(private.ComponentManager.GetAllComponents()) do
            local otherName = other.GetComponentName()
            if otherName ~= componentName and not private.Anchor.nonAnchorable[otherName] then
                -- Skip cursor-following frames: they reposition every frame
                -- via OnUpdate, making them unsuitable as anchor parents.
                local otherAP = other.GetSettings and other.GetSettings()
                local otherCursorFollow = otherAP and otherAP.anchor_profile
                    and otherAP.anchor_profile.anchor_parent == "cursor"
                -- Prevent cross-chain anchoring between secure and non-secure
                -- components: SecureActionButton protection cascades through
                -- the entire anchor chain, blocking combat-time frame operations.
                local otherSecure = private.Anchor.secureClickComponents[otherName]
                local crossChain = (iAmSecure and not otherSecure) or (not iAmSecure and otherSecure)
                if not otherCursorFollow and not crossChain then
                    local displayLabel = displayNames[otherName]
                    if not displayLabel then
                        local otherComp = private.ComponentManager.GetComponent(otherName)
                        if otherComp then
                            local os = otherComp.GetSettings and otherComp.GetSettings()
                            displayLabel = os and os.name
                        end
                        displayLabel = displayLabel or otherName
                    end
                    values[#values + 1] = {
                        text = displayLabel,
                        value = otherName,
                    }
                end
            end
        end
        for frameKey, info in pairs(private.externalAnchors) do
            values[#values + 1] = {
                text = info.displayName,
                value = frameKey,
            }
        end
        return values
    end

    local anchorSideValues = {
        {text = L["ANCHOR_BOTTOM"], value = "bottom"},
        {text = L["ANCHOR_TOP"], value = "top"},
        {text = L["ANCHOR_LEFT"], value = "left"},
        {text = L["ANCHOR_RIGHT"], value = "right"},
        {text = L["ANCHOR_TOPLEFT"], value = "topleft"},
        {text = L["ANCHOR_TOPRIGHT"], value = "topright"},
        {text = L["ANCHOR_BOTTOMLEFT"], value = "bottomleft"},
        {text = L["ANCHOR_BOTTOMRIGHT"], value = "bottomright"},
    }

    local anchorPointValues = {
        {text = L["ANCHOR_CENTER"], value = "CENTER"},
        {text = L["ANCHOR_TOP"], value = "TOP"},
        {text = L["ANCHOR_BOTTOM"], value = "BOTTOM"},
        {text = L["ANCHOR_LEFT"], value = "LEFT"},
        {text = L["ANCHOR_RIGHT"], value = "RIGHT"},
        {text = L["ANCHOR_TOPLEFT"], value = "TOPLEFT"},
        {text = L["ANCHOR_TOPRIGHT"], value = "TOPRIGHT"},
        {text = L["ANCHOR_BOTTOMLEFT"], value = "BOTTOMLEFT"},
        {text = L["ANCHOR_BOTTOMRIGHT"], value = "BOTTOMRIGHT"},
    }

    -- ===== 1. ENABLED (always first, no section header) =====

    local result = {
        {
            kind = ST.Checkbox,
            name = L["SETTING_ENABLED"],
            desc = L["SETTING_ENABLED_DESC"],
            -- Not `def`: Reset To Default leaves the enabled state alone (user
            -- decision 2026-09-23), and six components ship disabled.
            default = component.GetSettings().enabled,
            get = function(_) return component.GetSettings().enabled end,
            set = function(_, value)
                if value then
                    private.ComponentManager.EnableComponent(componentName)
                else
                    private.ComponentManager.DisableComponent(componentName)
                end
            end,
        },
    }

    -- Visibility mode dropdown: controls the base visibility behavior.
    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["SETTING_VISIBILITY"],
        desc = L["SETTING_VISIBILITY_DESC"],
        default = def("visibility", "inherit"),
        get = function(_)
            local vis = component.GetSettings().visibility or "inherit"
            if vis == "hide_when_mounted" then return "auto"
            elseif vis == "only_in_combat" then return "always" end
            return vis
        end,
        set = function(_, value)
            component.GetSettings().visibility = value
            -- The rule scan skips a "hidden" component's rules.
            private.Anchor.InvalidateTargetRuleCache()
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end,
        values = {
            {text = L["VISIBILITY_INHERIT"], value = "inherit"},
            {text = L["VISIBILITY_ALWAYS"], value = "always"},
            {text = L["VISIBILITY_AUTO"], value = "auto"},
            {text = L["VISIBILITY_HIDDEN"], value = "hidden"},
        },
    }

    -- Visibility Rules dropdown: additive conditions that hide or fade the component.
    -- Uses generator for grouped radio sections (Off/Hide/Fade per condition).
    local ruleConditions = {
        {key = "mounted", label = L["VISIBILITY_RULE_MOUNTED"]},
        {key = "out_of_combat", label = L["VISIBILITY_RULE_OUT_OF_COMBAT"]},
        {key = "no_target", label = L["VISIBILITY_RULE_NO_TARGET"]},
    }
    local ruleActions = {
        {label = L["VISIBILITY_RULE_OFF"], value = false},
        {label = L["VISIBILITY_RULE_HIDE"], value = "hide"},
        {label = L["VISIBILITY_RULE_FADE"], value = "fade"},
    }
    track("visibility_rules")
    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["VISIBILITY_RULES"],
        desc = L["VISIBILITY_RULES_DESC"],
        default = false,
        get = function(_) return false end,
        set = function() end,
        generator = function(_, rootDescription, _)
            for i, cond in ipairs(ruleConditions) do
                if i > 1 then
                    rootDescription:CreateDivider()
                end
                rootDescription:CreateTitle(cond.label)
                for _, action in ipairs(ruleActions) do
                    rootDescription:CreateRadio(action.label, function()
                        local rules = component.GetSettings().visibility_rules
                        local current = rules and rules[cond.key]
                        return (current or false) == action.value
                    end, function()
                        local settings = component.GetSettings()
                        if not settings.visibility_rules then
                            settings.visibility_rules = {fade_alpha = 30}
                        end
                        settings.visibility_rules[cond.key] = action.value
                        private.Anchor.InvalidateTargetRuleCache()
                        private.ComponentManager.RefreshAllComponents()
                        private.Anchor.Refresh()
                    end)
                end
            end
        end,
    }

    -- Fade Opacity slider: controls transparency when a fade rule is active.
    result[#result + 1] = {
        kind = ST.Slider,
        name = L["VISIBILITY_FADE_OPACITY"],
        desc = L["VISIBILITY_FADE_OPACITY_DESC"],
        default = def("visibility_rules.fade_alpha", 30),
        get = function(_)
            local rules = component.GetSettings().visibility_rules
            return (rules and rules.fade_alpha) or 30
        end,
        set = function(_, value)
            local settings = component.GetSettings()
            if not settings.visibility_rules then
                settings.visibility_rules = {fade_alpha = 30}
            end
            settings.visibility_rules.fade_alpha = value
            private.Anchor.Refresh()
        end,
        minValue = 10,
        maxValue = 90,
        valueStep = 5,
        disabled = function()
            local rules = component.GetSettings().visibility_rules
            if not rules then return true end
            return rules.mounted ~= "fade" and rules.out_of_combat ~= "fade" and rules.no_target ~= "fade"
        end,
    }

    -- Opacity slider: controls the transparency of this component.
    -- Value stored as 0.1–1.0 in settings.alpha; displayed as 10–100%.
    result[#result + 1] = {
        kind = ST.Slider,
        name = L["SETTING_OPACITY"],
        desc = L["SETTING_OPACITY_DESC"],
        default = math.floor(def("alpha", 1) * 100 + 0.5),
        get = function(_) return math.floor((component.GetSettings().alpha or 1) * 100 + 0.5) end,
        set = function(_, value)
            component.GetSettings().alpha = value / 100
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end,
        minValue = 10,
        maxValue = 100,
        valueStep = 5,
    }

    -- Auto-Hide checkbox: shown only for resource components (PrimaryResources, SecondaryResources).
    -- Controls whether the component auto-hides for classes/specs that do not use it.
    if autoHideComponents[componentName] then
        local autoHideKey = componentName == "ConsumableTracker"
            and "consumable_auto_hide" or "auto_hide"
        local autoHideDesc = componentName == "ConsumableTracker"
            and L["AUTO_HIDE_MANA_POTIONS_DESC"]
            or L["AUTO_HIDE_EDIT_DESC"]
        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["AUTO_HIDE"],
            desc = autoHideDesc,
            default = def("profile." .. autoHideKey, true),
            get = function(_) return private.profile[autoHideKey] end,
            set = function(_, value)
                private.profile[autoHideKey] = value
                private.ComponentManager.RefreshAllComponents()
                private.Anchor.Refresh()
            end,
        }
    end

    -- ===== 2. ANCHORING AND SIZE SECTION =====

    result[#result + 1] = {kind = ST.Divider, hideLabel = true}
    result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ANCHORING"]}

    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["SETTING_ANCHOR_FRAME"],
        desc = L["SETTING_ANCHOR_FRAME_DESC"],
        default = def("anchor_profile.anchor_parent", "none"),
        get = function(_) return component.GetSettings().anchor_profile.anchor_parent or "none" end,
        set = function(_, value)
            if private.Anchor.WouldCreateCycle(componentName, value) then
                local selfName = displayNames[componentName] or componentName
                local targetName = displayNames[value] or value
                private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"], selfName, targetName))
                return
            end
            -- When switching from anchored to free-moving, capture the frame's
            -- current on-screen position so the component stays in place instead
            -- of jumping to a stale/default 0,0 position.
            local settings = component.GetSettings()
            local wasAnchored = settings.anchor_profile.anchor_parent ~= "none"
            if value == "none" and wasAnchored then
                local f = component.GetFrame()
                if f and f:GetLeft() then
                    local scale = f:GetScale()
                    capturePositionForFreeMove(componentName, settings, settings.anchor_profile,
                        f:GetLeft() * scale, f:GetRight() * scale, f:GetTop() * scale, f:GetBottom() * scale, scale)
                end
            end
            settings.anchor_profile.anchor_parent = value
            private.Anchor.RebuildAnchorTree()
            private.Anchor.Refresh()
        end,
        values = anchorParentValues,
        hidden = isSecure and function() return true end or nil,
    }

    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["SETTING_ANCHOR_SIDE"],
        desc = L["SETTING_ANCHOR_SIDE_DESC"],
        default = def("anchor_profile.anchor_side"),
        get = function(_) return component.GetSettings().anchor_profile.anchor_side end,
        set = function(_, value)
            component.GetSettings().anchor_profile.anchor_side = value
            private.Anchor.Refresh()
        end,
        values = anchorSideValues,
        hidden = function() return component.GetSettings().anchor_profile.anchor_parent == "none" end,
    }

    result[#result + 1] = {
        kind = ST.Slider,
        name = L["SETTING_ANCHOR_OFFSET_X"],
        desc = L["SETTING_ANCHOR_OFFSET_X_DESC"],
        default = def("anchor_profile.anchor_offset_x", 0),
        get = function(_) return component.GetSettings().anchor_profile.anchor_offset_x or 0 end,
        set = function(_, value)
            component.GetSettings().anchor_profile.anchor_offset_x = value
            private.Anchor.Refresh()
        end,
        minValue = -1000,
        maxValue = 1000,
        valueStep = 1,
        hidden = function() return component.GetSettings().anchor_profile.anchor_parent == "none" end,
    }

    result[#result + 1] = {
        kind = ST.Slider,
        name = L["SETTING_ANCHOR_OFFSET_Y"],
        desc = L["SETTING_ANCHOR_OFFSET_Y_DESC"],
        default = def("anchor_profile.anchor_offset_y", 0),
        get = function(_) return component.GetSettings().anchor_profile.anchor_offset_y or 0 end,
        set = function(_, value)
            component.GetSettings().anchor_profile.anchor_offset_y = value
            private.Anchor.Refresh()
        end,
        minValue = -1000,
        maxValue = 1000,
        valueStep = 1,
        hidden = function() return component.GetSettings().anchor_profile.anchor_parent == "none" end,
    }

    -- Free-move anchor point and offset controls (shown only when free-moving).
    -- Routed through isFreeMoving so this agrees with the Options twin on both
    -- counts it used to miss: a secure component following a reference is NOT
    -- free-moving (these four then have no effect), and an ABSENT anchor_parent
    -- is free-moving rather than anchored.
    local function isNotFreeMoving()
        return not isFreeMoving()
    end

    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["SETTING_ANCHOR_POINT"],
        desc = L["SETTING_ANCHOR_POINT_DESC"],
        default = string.upper(def("anchor_profile.parent_point", "CENTER")),
        get = function(_)
            return string.upper(component.GetSettings().anchor_profile.parent_point or "CENTER")
        end,
        set = function(_, value)
            setFreeMovePoint(component.GetFrame(), component.GetSettings().anchor_profile, "parent_point", value)
            private.Anchor.Refresh()
            LibEditMode:RefreshFrameSettings(component.GetFrame())
        end,
        values = anchorPointValues,
        hidden = isNotFreeMoving,
    }

    result[#result + 1] = {
        kind = ST.Dropdown,
        name = L["SETTING_FRAME_POINT"],
        desc = L["SETTING_FRAME_POINT_DESC"],
        default = string.upper(def("anchor_profile.frame_point", "TOP")),
        get = function(_)
            return string.upper(component.GetSettings().anchor_profile.frame_point or "TOP")
        end,
        set = function(_, value)
            local ap = component.GetSettings().anchor_profile
            setFreeMovePoint(component.GetFrame(), ap, "frame_point", value)
            ap.frame_point_manual = true
            private.Anchor.Refresh()
            LibEditMode:RefreshFrameSettings(component.GetFrame())
        end,
        values = anchorPointValues,
        hidden = isNotFreeMoving,
    }

    result[#result + 1] = {
        kind = ST.Slider,
        name = L["SETTING_FREE_OFFSET_X"],
        desc = L["SETTING_FREE_OFFSET_X_DESC"],
        default = def("anchor_profile.xoff", 0),
        get = function(_) return component.GetSettings().anchor_profile.xoff or 0 end,
        set = function(_, value)
            component.GetSettings().anchor_profile.xoff = value
            private.Anchor.Refresh()
        end,
        minValue = -3000,
        maxValue = 3000,
        valueStep = 1,
        hidden = isNotFreeMoving,
    }

    result[#result + 1] = {
        kind = ST.Slider,
        name = L["SETTING_FREE_OFFSET_Y"],
        desc = L["SETTING_FREE_OFFSET_Y_DESC"],
        default = def("anchor_profile.yoff", 0),
        get = function(_) return component.GetSettings().anchor_profile.yoff or 0 end,
        set = function(_, value)
            component.GetSettings().anchor_profile.yoff = value
            private.Anchor.Refresh()
        end,
        minValue = -3000,
        maxValue = 3000,
        valueStep = 1,
        hidden = isNotFreeMoving,
    }

    -- Position reference: screen-position-based following for secure components.
    -- Secure components never use anchor_parent; they follow a reference frame
    -- via absolute screen coordinates, updated out of combat only.
    if isSecure then
        local function posRefValues()
            local vals = {{text = L["ANCHOR_NONE"], value = "none"}}
            for _, other in ipairs(private.ComponentManager.GetAllComponents()) do
                local otherName = other.GetComponentName()
                if otherName ~= componentName then
                    local dl = displayNames[otherName] or otherName
                    vals[#vals + 1] = {text = dl, value = otherName}
                end
            end
            return vals
        end

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_POSITION_REFERENCE"],
            desc = L["SETTING_POSITION_REFERENCE_DESC"],
            default = def("anchor_profile.position_reference", "none"),
            get = function(_) return component.GetSettings().anchor_profile.position_reference or "none" end,
            set = function(_, value)
                if private.Anchor.WouldCreateCycle(componentName, value) then
                    private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"],
                        displayNames[componentName] or componentName,
                        displayNames[value] or value))
                    return
                end
                local settings = component.GetSettings()
                local ap = settings.anchor_profile
                local wasFollowing = ap.position_reference and ap.position_reference ~= "none"
                if value == "none" and wasFollowing then
                    local f = component.GetFrame()
                    if f and f:GetLeft() then
                        local scale = f:GetScale()
                        capturePositionForFreeMove(componentName, settings, ap,
                            f:GetLeft() * scale, f:GetRight() * scale,
                            f:GetTop() * scale, f:GetBottom() * scale, scale)
                    end
                end
                ap.position_reference = value
                private.Anchor.Refresh()
            end,
            values = posRefValues,
        }

        local positionSideValues = {
            {text = L["ANCHOR_BOTTOM"], value = "bottom"},
            {text = L["ANCHOR_TOP"], value = "top"},
            {text = L["ANCHOR_LEFT"], value = "left"},
            {text = L["ANCHOR_RIGHT"], value = "right"},
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_POSITION_SIDE"],
            desc = L["SETTING_POSITION_SIDE_DESC"],
            default = def("anchor_profile.position_side", "bottom"),
            get = function(_) return component.GetSettings().anchor_profile.position_side or "bottom" end,
            set = function(_, value)
                component.GetSettings().anchor_profile.position_side = value
                private.Anchor.Refresh()
            end,
            values = positionSideValues,
            hidden = function()
                local pr = component.GetSettings().anchor_profile.position_reference
                return not pr or pr == "none"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_POSITION_OFFSET"],
            desc = L["SETTING_POSITION_OFFSET_DESC"],
            default = def("anchor_profile.position_offset", 30),
            get = function(_) return component.GetSettings().anchor_profile.position_offset or 30 end,
            set = function(_, value)
                component.GetSettings().anchor_profile.position_offset = value
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 200,
            valueStep = 1,
            hidden = function()
                local pr = component.GetSettings().anchor_profile.position_reference
                return not pr or pr == "none"
            end,
        }
    end

    if wpc then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_WIDTH_MODE"],
            desc = L["SETTING_WIDTH_MODE_DESC"],
            default = def("anchor_profile.anchor_width_mode", "percent"),
            get = function(_) return component.GetSettings().anchor_profile.anchor_width_mode or "percent" end,
            set = function(_, value)
                component.GetSettings().anchor_profile.anchor_width_mode = value
                private.Anchor.Refresh()
                if viewerTrackerComponents[componentName] or barTrackerComponents[componentName] then
                    component.Refresh()
                end
            end,
            values = {
                {text = L["WIDTH_MODE_PERCENT"], value = "percent"},
                {text = L["WIDTH_MODE_ABSOLUTE"], value = "absolute"},
            },
            -- The cursor has no width to inherit.
            hidden = function()
                return isFreeMoving() or component.GetSettings().anchor_profile.anchor_parent == "cursor"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_WIDTH_PCT"],
            desc = L["SETTING_WIDTH_PCT_DESC"],
            default = def("anchor_profile.anchor_width_pct"),
            get = function(_) return component.GetSettings().anchor_profile.anchor_width_pct end,
            set = function(_, value)
                component.GetSettings().anchor_profile.anchor_width_pct = value
                private.Anchor.Refresh()
                -- Viewer/bar tracker layout uses the frame's GetWidth() (anchor-controlled).
                -- Refresh() re-runs applyLayout so content immediately adapts to the new frame width.
                if viewerTrackerComponents[componentName] or barTrackerComponents[componentName] then
                    component.Refresh()
                end
            end,
            minValue = wpc.min,
            maxValue = wpc.max,
            valueStep = 1,
            hidden = function(_)
                local ap = component.GetSettings().anchor_profile
                return ap.anchor_parent == "none" or ap.anchor_parent == "cursor"
                    or (ap.anchor_width_mode or "percent") == "absolute"
            end,
        }
    end

    -- ===== SIZE SETTINGS (part of Anchoring and Size section) =====
    -- TrinketTracker and ConsumableTracker derive width and height from icon_size
    -- and layout; they have their own dedicated sections below, so skip the
    -- generic size settings entirely.

    local isTrinketTracker = componentName == "TrinketTracker"
    local isConsumableTracker = componentName == "ConsumableTracker"
    local isConsumableBuffTracker = componentName == "ConsumableBuffTracker"
    local isRaidBuffTracker = componentName == "RaidBuffTracker"
    local isRacialTracker = componentName == "RacialTracker"

    local isBarTracker = barTrackerComponents[componentName]

    if not isTrinketTracker and not isConsumableTracker and not isConsumableBuffTracker and not isRaidBuffTracker and not isRacialTracker and not isBarTracker then
        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_WIDTH"],
            desc = L["SETTING_WIDTH_DESC"],
            default = def("width", wc.widthMin),
            get = function(_) return component.GetSettings().width or wc.widthMin end,
            set = function(_, value)
                component.GetSettings().width = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = wc.widthMin,
            maxValue = wc.widthMax,
            valueStep = 1,
            -- Hidden when anchored in percentage width mode (parent controls effective width),
            -- or when a viewer tracker is in "max_per_row" mode (icon count drives frame width).
            hidden = (wpc or viewerTrackerComponents[componentName]) and function(_)
                local settings = component.GetSettings()
                local isAnchored = settings.anchor_profile.anchor_parent ~= "none"
                local isPercentMode = (settings.anchor_profile.anchor_width_mode or "percent") == "percent"
                return (wpc ~= nil and isAnchored and isPercentMode)
                    or (viewerTrackerComponents[componentName] and settings.frame_size_mode == "max_per_row")
            end or nil,
        }

        -- Height slider: omitted for viewer tracker components because their height is
        -- computed from the icon layout (icon_size, overflow_icon_size, iconLimit).
        -- Also omitted when the component has no height field (e.g. additional frames).
        if not viewerTrackerComponents[componentName] and component.GetSettings().height ~= nil then
            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_HEIGHT"],
                desc = L["SETTING_HEIGHT_DESC"],
                default = def("height", hc.heightMin),
                get = function(_) return component.GetSettings().height or hc.heightMin end,
                set = function(_, value)
                    component.GetSettings().height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                minValue = hc.heightMin,
                maxValue = hc.heightMax,
                valueStep = 1,
            }
        end

        -- Extra-row height. Only SecondaryResources carries the key, so its
        -- presence is the gate — same idiom as the height slider above. Paired
        -- with the Options widget; see .context/patterns.md on auditing the two
        -- surfaces together.
        if component.GetSettings().extra_row_height ~= nil then
            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_EXTRA_ROW_HEIGHT"],
                desc = L["SETTING_EXTRA_ROW_HEIGHT_DESC"],
                default = def("extra_row_height", hc.heightMin),
                get = function(_) return component.GetSettings().extra_row_height or hc.heightMin end,
                set = function(_, value)
                    component.GetSettings().extra_row_height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                minValue = hc.heightMin,
                maxValue = hc.heightMax,
                valueStep = 1,
            }
        end

        -- Height slider for viewer tracker components: shown only in vertical
        -- fixed-height modes where settings.height acts as the constraint axis.
        if viewerTrackerComponents[componentName] then
            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_HEIGHT"],
                desc = L["SETTING_HEIGHT_DESC"],
                default = def("height", hc.heightMin),
                get = function(_) return component.GetSettings().height or hc.heightMin end,
                set = function(_, value)
                    component.GetSettings().height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                minValue = hc.heightMin,
                maxValue = hc.heightMax,
                valueStep = 1,
                hidden = function(_)
                    return (component.GetSettings().layout_direction or "horizontal") ~= "vertical"
                end,
            }
        end

        -- Orientation dropdown for bar components that support vertical fill
        if component.GetSettings().orientation ~= nil then
            result[#result + 1] = {
                kind = ST.Dropdown,
                name = L["SETTING_ORIENTATION"],
                desc = L["SETTING_ORIENTATION_DESC"],
                default = def("orientation", "horizontal"),
                get = function(_) return component.GetSettings().orientation or "horizontal" end,
                set = function(_, value)
                    component.GetSettings().orientation = value
                    -- fontsDirty gate: value/cast text rotation lives in the
                    -- font pass, which Refresh only runs when fontsDirty is set.
                    private.fontsDirty = true
                    component.Refresh()
                    private.fontsDirty = false
                    private.Anchor.Refresh()
                    LibEditMode:RefreshFrameSettings(component.GetFrame())
                end,
                values = {
                    {text = L["SETTING_ORIENTATION_HORIZONTAL"], value = "horizontal"},
                    {text = L["SETTING_ORIENTATION_VERTICAL"], value = "vertical"},
                },
            }
        end

        if componentName == "SecondaryResources" then
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_SHOW_VALUE"],
                desc = L["SETTING_SHOW_VALUE_DESC"],
                default = def("show_value", false),
                get = function(_) return component.GetSettings().show_value end,
                set = function(_, value)
                    component.GetSettings().show_value = value
                    component.Refresh()
                end,
            }
            if select(2, UnitClass("player")) == "DEATHKNIGHT" then
                result[#result + 1] = {
                    kind = ST.Checkbox,
                    name = L["SETTING_SORT_RUNES"],
                    desc = L["SETTING_SORT_RUNES_DESC"],
                    default = def("sort_runes", false),
                    get = function(_) return component.GetSettings().sort_runes end,
                    set = function(_, value)
                        component.GetSettings().sort_runes = value
                        component.Refresh()
                    end,
                }
            end
            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_BAR_SPACING"],
                desc = L["SETTING_BAR_SPACING_DESC"],
                default = def("bar_spacing", 2),
                get = function(_) return component.GetSettings().bar_spacing or 2 end,
                set = function(_, value)
                    component.GetSettings().bar_spacing = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                minValue = -5,
                maxValue = 20,
                valueStep = 1,
            }
        end

        if componentName == "PlayerHealthBar" then
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_INTERACTABLE"],
                desc = L["SETTING_INTERACTABLE_DESC"],
                default = def("interactable", false),
                get = function(_) return component.GetSettings().interactable end,
                set = function(_, value)
                    component.GetSettings().interactable = value
                    component.Refresh()
                end,
            }
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_SHOW_SHIELDS"],
                desc = L["SETTING_SHOW_SHIELDS_DESC"],
                default = def("show_shields", true),
                get = function(_) return component.GetSettings().show_shields end,
                set = function(_, value)
                    component.GetSettings().show_shields = value
                    component.Refresh()
                end,
            }
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_SHOW_HEALING_PREDICTION"],
                desc = L["SETTING_SHOW_HEALING_PREDICTION_DESC"],
                default = def("show_healing_prediction", true),
                get = function(_) return component.GetSettings().show_healing_prediction end,
                set = function(_, value)
                    component.GetSettings().show_healing_prediction = value
                    component.Refresh()
                end,
            }
        end
    end

    -- ===== TEXTURE SECTION (components with texture field) =====

    local isCastBar = component.GetSettings().cast_name_font ~= nil
    if component.GetSettings().texture ~= nil then
        local textureValues = {{text = L["SETTING_TEXTURE_DEFAULT"], value = ""}}
        for _, key in ipairs(LibSharedMedia:List("statusbar") or {}) do
            textureValues[#textureValues + 1] = {text = key, value = key}
        end

        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_TEXTURE"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = isCastBar and L["SETTING_CAST_TEXTURE"] or L["SETTING_TEXTURE"],
            desc = isCastBar and L["SETTING_CAST_TEXTURE_DESC"] or L["SETTING_TEXTURE_DESC"],
            default = def("texture"),
            get = function(_) return component.GetSettings().texture end,
            set = function(_, value)
                component.GetSettings().texture = value
                component.Refresh()
            end,
            values = textureValues,
            height = 400,
        }
    end

    -- ===== 4. ICON LAYOUT SECTION (viewer trackers only) =====

    if viewerTrackerComponents[componentName] then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_DIRECTION"],
            desc = L["SETTING_LAYOUT_DIRECTION_DESC"],
            default = def("layout_direction", "horizontal"),
            get = function(_) return component.GetSettings().layout_direction or "horizontal" end,
            set = function(_, value)
                local s = component.GetSettings()
                s.layout_direction = value
                -- Reset alignment to "center" when switching direction (values differ).
                s.layout_alignment = "center"
                -- Reset overflow_direction to a valid value for the new direction.
                if value == "vertical" then
                    if s.overflow_direction ~= "left" and s.overflow_direction ~= "right" then
                        s.overflow_direction = "right"
                    end
                else
                    if s.overflow_direction ~= "top" and s.overflow_direction ~= "bottom" then
                        s.overflow_direction = "top"
                    end
                end
                component.Refresh()
                private.Anchor.Refresh()
                LibEditMode:RefreshFrameSettings(component.GetFrame())
            end,
            values = {
                {text = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal"},
                {text = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical"},
            },
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            default = def("layout_alignment", "center"),
            get = function(_) return component.GetSettings().layout_alignment or "center" end,
            set = function(_, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if (component.GetSettings().layout_direction or "horizontal") == "vertical" then
                    return {
                        {text = L["LAYOUT_ALIGNMENT_TOP"], value = "top"},
                        {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                        {text = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom"},
                    }
                end
                return {
                    {text = L["LAYOUT_ALIGNMENT_LEFT"], value = "left"},
                    {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                    {text = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right"},
                }
            end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_SIZE_MODE"],
            desc = L["SETTING_SIZE_MODE_DESC"],
            default = def("frame_size_mode"),
            get = function(_) return component.GetSettings().frame_size_mode end,
            set = function(_, value)
                component.GetSettings().frame_size_mode = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function(_)
                local isVertical = (component.GetSettings().layout_direction or "horizontal") == "vertical"
                return {
                    {text = L["SETTING_MAX_WIDTH"], value = "max_width"},
                    {text = L["SETTING_MAX_PER_ROW"], value = "max_per_row"},
                    {text = isVertical and L["SETTING_FIXED_HEIGHT"] or L["SETTING_FIXED_WIDTH"], value = "fixed_width"},
                    {text = isVertical and L["SETTING_FIXED_HEIGHT_SPREAD"] or L["SETTING_FIXED_WIDTH_SPREAD"], value = "fixed_width_spread"},
                    {text = isVertical and L["SETTING_FIXED_HEIGHT_STRETCH"] or L["SETTING_FIXED_WIDTH_STRETCH"], value = "fixed_width_stretch"},
                }
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_MAX_PER_ROW"],
            desc = L["SETTING_MAX_PER_ROW_DESC"],
            default = def("max_icons_per_row", 8),
            get = function(_) return component.GetSettings().max_icons_per_row or 8 end,
            set = function(_, value)
                component.GetSettings().max_icons_per_row = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 1,
            maxValue = 20,
            valueStep = 1,
            hidden = function(_)
                local m = component.GetSettings().frame_size_mode or "max_width"
                return m ~= "max_per_row"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_MIN_WIDTH"],
            desc = L["SETTING_MIN_WIDTH_DESC"],
            default = def("min_width", 0),
            get = function(_) return component.GetSettings().min_width or 0 end,
            set = function(_, value)
                component.GetSettings().min_width = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 1000,
            valueStep = 1,
            hidden = function(_)
                local s = component.GetSettings()
                if (s.layout_direction or "horizontal") == "vertical" then return false end
                -- Mirrors computeGridGeometry's isContentWidth, same as the
                -- Options twin: min_width floors only a width the frame derived
                -- from its icons.  Gating on max_per_row alone hid the slider
                -- outright in the DEFAULT mode, where it is shaping the frame.
                local m = s.frame_size_mode or "max_width"
                if m == "fixed_width" or m == "fixed_width_spread"
                    or m == "fixed_width_stretch" then
                    return true
                end
                return not (m == "max_per_row" or (s.icon_size and s.icon_size > 0))
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size", 40),
            get = function(_) return component.GetSettings().icon_size or 40 end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
            hidden = function(_)
                return component.GetSettings().frame_size_mode == "fixed_width"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            default = def("icon_height", 0),
            get = function(_) return component.GetSettings().icon_height or 0 end,
            set = function(_, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 80,
            valueStep = 1,
            hidden = function(_)
                return component.GetSettings().frame_size_mode == "fixed_width_stretch"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_OVERFLOW_ICON_SIZE"],
            desc = L["SETTING_OVERFLOW_ICON_SIZE_DESC"],
            default = def("overflow_icon_size", 20),
            get = function(_) return component.GetSettings().overflow_icon_size or 20 end,
            set = function(_, value)
                component.GetSettings().overflow_icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
            hidden = function(_)
                -- Which icons landed on an overflow row is only knowable under
                -- slots; under either groups engine Blizzard owns the flow.
                -- Options hides it for that reason too (its own
                -- `hidden = groupsEngine`) and this twin did not -- the
                -- Options/EditMode predicate drift patterns.md documents.  It
                -- matters more since per-spell groups became the default engine.
                -- An Additional Frame's IsUsingSlots lives on its aura tracker,
                -- not on the instance.component wrapper -- Options reads it there.
                local afId = componentName:match("^AdditionalFrame_(.+)$")
                local afInstance = afId and private.AdditionalFrameManager.GetInstance(afId)
                local tracker = afInstance and afInstance.auraTracker or component
                if tracker.IsUsingSlots ~= nil and not tracker.IsUsingSlots() then
                    return true
                end
                local m = component.GetSettings().frame_size_mode or "max_width"
                return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
            end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_OVERFLOW_DIRECTION"],
            desc = L["SETTING_OVERFLOW_DIRECTION_DESC"],
            default = def("overflow_direction"),
            get = function(_) return component.GetSettings().overflow_direction end,
            set = function(_, value)
                component.GetSettings().overflow_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if (component.GetSettings().layout_direction or "horizontal") == "vertical" then
                    return {
                        {text = L["OVERFLOW_LEFT"], value = "left"},
                        {text = L["OVERFLOW_RIGHT"], value = "right"},
                    }
                end
                return {
                    {text = L["ANCHOR_TOP"], value = "top"},
                    {text = L["ANCHOR_BOTTOM"], value = "bottom"},
                }
            end,
            hidden = function(_)
                local s = component.GetSettings()
                local m = s.frame_size_mode or "max_width"
                return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        -- The icon twin of the bar section's Track Totems (BuffTracker is the
        -- only viewer tracker carrying the key); same gate and setter as Options.
        if component.GetSettings().show_totems ~= nil then
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_SHOW_TOTEMS"],
                desc = L["SETTING_SHOW_TOTEMS_DESC"],
                default = def("show_totems"),
                get = function(_) return component.GetSettings().show_totems end,
                set = function(_, value)
                    component.GetSettings().show_totems = value
                    component.Refresh()
                    -- The reserved line changes the reported size.
                    private.Anchor.Refresh()
                end,
            }
        end
    end

    -- ===== 4a-bar. BAR TRACKER SECTION =====
    -- BuffTrackerBars has its own layout settings: bar width, icon size, bar height,
    -- bar spacing, growth direction, bar content mode, and show timer.

    if isBarTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_BAR_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_DIRECTION"],
            desc = L["SETTING_LAYOUT_DIRECTION_DESC"],
            default = def("layout_direction", "vertical"),
            get = function(_) return component.GetSettings().layout_direction or "vertical" end,
            set = function(_, value)
                local s = component.GetSettings()
                s.layout_direction = value
                s.layout_alignment = "center"
                -- Reset growth_direction to a valid value for the new direction.
                if value == "horizontal" then
                    if s.growth_direction ~= "left" and s.growth_direction ~= "right" then
                        s.growth_direction = "right"
                    end
                else
                    if s.growth_direction ~= "up" and s.growth_direction ~= "down" then
                        s.growth_direction = "up"
                    end
                end
                component.Refresh()
                private.Anchor.Refresh()
                LibEditMode:RefreshFrameSettings(component.GetFrame())
            end,
            values = {
                {text = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal"},
                {text = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical"},
            },
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            default = def("layout_alignment", "center"),
            get = function(_) return component.GetSettings().layout_alignment or "center" end,
            set = function(_, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if (component.GetSettings().layout_direction or "vertical") == "vertical" then
                    return {
                        {text = L["LAYOUT_ALIGNMENT_TOP"], value = "top"},
                        {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                        {text = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom"},
                    }
                end
                return {
                    {text = L["LAYOUT_ALIGNMENT_LEFT"], value = "left"},
                    {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                    {text = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right"},
                }
            end,
        }

        -- Size Mode: only shown for additional frame bar types (not built-in BuffTrackerBars)
        if isAdditionalFrame then
            result[#result + 1] = {
                kind = ST.Dropdown,
                name = L["SETTING_BAR_SIZE_MODE"],
                desc = L["SETTING_BAR_SIZE_MODE_DESC"],
                default = def("bar_size_mode", "fixed"),
                get = function(_) return component.GetSettings().bar_size_mode or "fixed" end,
                set = function(_, value)
                    component.GetSettings().bar_size_mode = value
                    component.Refresh()
                    private.Anchor.Refresh()
                    LibEditMode:RefreshFrameSettings(component.GetFrame())
                end,
                values = {
                    {text = L["SETTING_BAR_SIZE_FIXED"], value = "fixed"},
                    {text = L["SETTING_BAR_SIZE_FILL"], value = "fill"},
                },
            }

            -- Width slider: visible in fill mode (controls container fill width)
            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_WIDTH"],
                desc = L["SETTING_WIDTH_DESC"],
                default = def("width", 220),
                get = function(_) return component.GetSettings().width or 220 end,
                set = function(_, value)
                    component.GetSettings().width = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                minValue = 20,
                maxValue = 1000,
                valueStep = 1,
                hidden = function(_)
                    return (component.GetSettings().bar_size_mode or "fixed") ~= "fill"
                end,
            }
        end

        -- Bar Width slider: hidden in fill mode for additional frames
        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_BAR_WIDTH"],
            desc = L["SETTING_BAR_WIDTH_DESC"],
            default = def("bar_width", 220),
            get = function(_) return component.GetSettings().bar_width or 220 end,
            set = function(_, value)
                component.GetSettings().bar_width = value
                -- fontsDirty gate: bar name truncation width lives in the font pass,
                -- which Refresh only runs when fontsDirty is set.
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
                private.Anchor.Refresh()
            end,
            minValue = 20,
            maxValue = 1000,
            valueStep = 1,
            hidden = isAdditionalFrame and function(_)
                return (component.GetSettings().bar_size_mode or "fixed") == "fill"
            end or nil,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size", 30),
            get = function(_) return component.GetSettings().icon_size or 30 end,
            -- fontsDirty gate: bar name truncation width depends on icon size and
            -- is applied in the font pass, which needs fontsDirty set.
            set = function(_, value)
                component.GetSettings().icon_size = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 60,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_BAR_HEIGHT"],
            desc = L["SETTING_BAR_HEIGHT_DESC"],
            default = def("bar_height", 30),
            get = function(_) return component.GetSettings().bar_height or 30 end,
            set = function(_, value)
                component.GetSettings().bar_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 5,
            maxValue = 60,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_BAR_SPACING"],
            desc = L["SETTING_BAR_SPACING_DESC"],
            default = def("bar_spacing", 2),
            get = function(_) return component.GetSettings().bar_spacing or 2 end,
            set = function(_, value)
                component.GetSettings().bar_spacing = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_BAR_ICON_OFFSET_X"],
            desc = L["SETTING_BAR_ICON_OFFSET_X_DESC"],
            default = def("icon_offset_x", 0),
            get = function(_) return component.GetSettings().icon_offset_x or 0 end,
            set = function(_, value)
                component.GetSettings().icon_offset_x = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -50,
            maxValue = 50,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_BAR_ICON_OFFSET_Y"],
            desc = L["SETTING_BAR_ICON_OFFSET_Y_DESC"],
            default = def("icon_offset_y", 0),
            get = function(_) return component.GetSettings().icon_offset_y or 0 end,
            set = function(_, value)
                component.GetSettings().icon_offset_y = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -50,
            maxValue = 50,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_GROWTH_DIRECTION"],
            desc = L["SETTING_GROWTH_DIRECTION_DESC"],
            default = def("growth_direction"),
            get = function(_) return component.GetSettings().growth_direction end,
            set = function(_, value)
                component.GetSettings().growth_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if (component.GetSettings().layout_direction or "vertical") == "horizontal" then
                    return {
                        {text = L["SETTING_GROWTH_LEFT"], value = "left"},
                        {text = L["SETTING_GROWTH_RIGHT"], value = "right"},
                    }
                end
                return {
                    {text = L["SETTING_GROWTH_UP"], value = "up"},
                    {text = L["SETTING_GROWTH_DOWN"], value = "down"},
                }
            end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_BAR_CONTENT"],
            desc = L["SETTING_BAR_CONTENT_DESC"],
            default = def("bar_content"),
            get = function(_) return component.GetSettings().bar_content end,
            set = function(_, value)
                component.GetSettings().bar_content = value
                -- fontsDirty gate: bar name truncation width (and whether the name
                -- shows at all) is applied in the font pass, which needs fontsDirty set.
                private.fontsDirty = true
                if component.RefreshAndRelayout then
                    component.RefreshAndRelayout()
                else
                    component.Refresh()
                end
                private.fontsDirty = false
            end,
            values = {
                {text = L["SETTING_BAR_CONTENT_ICON_AND_BAR"], value = "IconAndName"},
                {text = L["SETTING_BAR_CONTENT_ICON_ONLY"], value = "IconOnly"},
                {text = L["SETTING_BAR_CONTENT_BAR_ONLY"], value = "NameOnly"},
                {text = L["SETTING_BAR_CONTENT_BAR_ONLY_NO_NAME"], value = "BarOnlyNoName"},
                {text = L["SETTING_BAR_CONTENT_ICON_AND_BAR_NO_NAME"], value = "IconAndBarNoName"},
            },
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_BAR_COLLAPSE"],
            desc = L["SETTING_BAR_COLLAPSE_DESC"],
            default = def("collapse"),
            get = function(_) return component.GetSettings().collapse end,
            set = function(_, value)
                component.GetSettings().collapse = value
                if component.RefreshAndRelayout then
                    component.RefreshAndRelayout()
                else
                    component.Refresh()
                end
            end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_TIMER"],
            desc = L["SETTING_SHOW_TIMER_DESC"],
            default = def("show_timer"),
            get = function(_) return component.GetSettings().show_timer end,
            set = function(_, value)
                component.GetSettings().show_timer = value
                component.Refresh()
            end,
        }

        -- Options' twin of this widget (SETTING_SHOW_TOTEMS) gates on the key
        -- alone too.  Both engines render the rows: they live in a container of
        -- their own, anchored onto the trailing edge of whichever engine drew
        -- the run, so they never need the aura block's (secret) extent.
        if component.GetSettings().show_totems ~= nil then
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_SHOW_TOTEMS"],
                desc = L["SETTING_SHOW_TOTEMS_DESC"],
                default = def("show_totems"),
                get = function(_) return component.GetSettings().show_totems end,
                set = function(_, value)
                    component.GetSettings().show_totems = value
                    component.Refresh()
                    -- Reserved rows change the reported size, so the anchor
                    -- chain re-derives rather than waiting on a spell count.
                    private.Anchor.Refresh()
                end,
            }
        end
    end

    -- ===== 4b. TRINKET TRACKER SECTION =====
    -- TrinketTracker has its own simplified layout settings: layout direction,
    -- icon size, icon offset, and reserve slots.

    if isTrinketTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            default = def("layout"),
            get = function(_) return component.GetSettings().layout end,
            set = function(_, value)
                local s = component.GetSettings()
                s.layout = value
                s.layout_alignment = "center"
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal"},
                {text = L["SETTING_LAYOUT_VERTICAL"], value = "vertical"},
            },
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            default = def("layout_alignment", "center"),
            get = function(_) return component.GetSettings().layout_alignment or "center" end,
            set = function(_, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if component.GetSettings().layout == "vertical" then
                    return {
                        {text = L["LAYOUT_ALIGNMENT_TOP"], value = "top"},
                        {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                        {text = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom"},
                    }
                end
                return {
                    {text = L["LAYOUT_ALIGNMENT_LEFT"], value = "left"},
                    {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                    {text = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right"},
                }
            end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size"),
            get = function(_) return component.GetSettings().icon_size end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            default = def("icon_height", 0),
            get = function(_) return component.GetSettings().icon_height or 0 end,
            set = function(_, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_RESERVE_SLOTS"],
            desc = L["SETTING_RESERVE_SLOTS_DESC"],
            default = def("reserve_slots"),
            get = function(_) return component.GetSettings().reserve_slots end,
            set = function(_, value)
                component.GetSettings().reserve_slots = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_PASSIVE_TRINKETS"],
            desc = L["SETTING_SHOW_PASSIVE_TRINKETS_DESC"],
            default = def("show_passive"),
            get = function(_) return component.GetSettings().show_passive end,
            set = function(_, value)
                component.GetSettings().show_passive = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    -- Trinket-only, as in 2.13.4 and as Options.lua gates it: on the cooldown
    -- trackers `hide_active_swipe` alone controls the buff takeover, and a key a
    -- 3.0 profile saved there would otherwise surface as a dead checkbox.
    if isTrinketTracker and component.GetSettings().show_active_duration ~= nil then
        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_ACTIVE_DURATION"],
            desc = L["SETTING_SHOW_ACTIVE_DURATION_DESC"],
            default = def("show_active_duration"),
            get = function(_) return component.GetSettings().show_active_duration end,
            set = function(_, value)
                component.GetSettings().show_active_duration = value
                component.Refresh()
            end,
        }
    end

    -- ===== 4b-glow. TRINKET TRACKER GLOW SECTION =====
    if isTrinketTracker then
        local glowSettings = component.GetSettings().glow
        if glowSettings then
            result[#result + 1] = {kind = ST.Divider, hideLabel = true}
            result[#result + 1] = {kind = ST.Divider, name = L["SETTING_GLOW_EFFECTS"]}

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_ENABLED"],
                desc = L["SETTING_GLOW_ENABLED_DESC"],
                default = def("glow.enabled"),
                get = function(_) return component.GetSettings().glow.enabled end,
                set = function(_, value)
                    component.GetSettings().glow.enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_FLASH"],
                desc = L["SETTING_GLOW_FLASH_DESC"],
                default = def("glow.flash_enabled"),
                get = function(_) return component.GetSettings().glow.flash_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.flash_enabled = value
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_PULSE"],
                desc = L["SETTING_GLOW_PULSE_DESC"],
                default = def("glow.pulse_enabled"),
                get = function(_) return component.GetSettings().glow.pulse_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.pulse_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_GLOW_DURATION"],
                desc = L["SETTING_GLOW_DURATION_DESC"],
                default = def("glow.pulse_duration"),
                get = function(_) return component.GetSettings().glow.pulse_duration end,
                set = function(_, value)
                    component.GetSettings().glow.pulse_duration = value
                end,
                minValue = 0,
                maxValue = 30,
                valueStep = 1,
                hidden = function(_)
                    local glow = component.GetSettings().glow
                    return not glow.enabled or not glow.pulse_enabled
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_APPROACHING"],
                desc = L["SETTING_GLOW_APPROACHING_DESC"],
                default = def("glow.approaching_enabled"),
                get = function(_) return component.GetSettings().glow.approaching_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.approaching_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_GLOW_APPROACHING_TIME"],
                desc = L["SETTING_GLOW_APPROACHING_TIME_DESC"],
                default = def("glow.approaching_time"),
                get = function(_) return component.GetSettings().glow.approaching_time end,
                set = function(_, value)
                    component.GetSettings().glow.approaching_time = value
                end,
                minValue = 0,
                maxValue = 15,
                valueStep = 1,
                hidden = function(_)
                    local glow = component.GetSettings().glow
                    return not glow.enabled or not glow.approaching_enabled
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_ACTIVE"],
                desc = L["SETTING_GLOW_ACTIVE_DESC"],
                default = def("glow.active_enabled"),
                get = function(_) return component.GetSettings().glow.active_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.active_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }
        end
    end

    -- ===== 4b2. RACIAL TRACKER SECTION =====
    -- RacialTracker has the same simplified layout settings as TrinketTracker:
    -- layout direction, icon size, icon height, and icon offset.

    if isRacialTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            default = def("layout"),
            get = function(_) return component.GetSettings().layout end,
            set = function(_, value)
                component.GetSettings().layout = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal"},
                {text = L["SETTING_LAYOUT_VERTICAL"], value = "vertical"},
            },
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size"),
            get = function(_) return component.GetSettings().icon_size end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            default = def("icon_height", 0),
            get = function(_) return component.GetSettings().icon_height or 0 end,
            set = function(_, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }
    end

    -- ===== 4b-pandemic. BUFF TRACKER PANDEMIC GLOW SECTION =====
    if componentName == "BuffTracker" or componentName == "BuffTrackerBars" then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_GLOW_EFFECTS"]}

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_PANDEMIC_GLOW"],
            desc = L["SETTING_PANDEMIC_GLOW_DESC"],
            default = def("pandemic_glow"),
            get = function(_) return component.GetSettings().pandemic_glow end,
            set = function(_, value)
                component.GetSettings().pandemic_glow = value
                component.Refresh()
            end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_PANDEMIC_GLOW_STYLE"],
            desc = L["SETTING_PANDEMIC_GLOW_STYLE_DESC"],
            default = def("pandemic_glow_style", "border") == "border_inside" and "border_inside" or "border",
            -- The cue is a static border (Core/AuraContainer.lua): the style
            -- picks which side of the edge it draws on, nothing more. A profile
            -- carrying one of the retired animated styles reads back as the
            -- outside border, which is what it renders as.
            get = function(_)
                local st = component.GetSettings().pandemic_glow_style
                return st == "border_inside" and "border_inside" or "border"
            end,
            set = function(_, value)
                component.GetSettings().pandemic_glow_style = value
                component.Refresh()
            end,
            values = {
                {text = L["PANDEMIC_STYLE_BORDER"], value = "border"},
                {text = L["PANDEMIC_STYLE_BORDER_INSIDE"], value = "border_inside"},
            },
        }

        result[#result + 1] = {
            kind = ST.ColorPicker,
            name = L["SETTING_PANDEMIC_GLOW_COLOR"],
            desc = L["SETTING_PANDEMIC_GLOW_COLOR_DESC"],
            hasOpacity = false,
            default = CreateColor(private.Util.Color(
                def("pandemic_glow_color", component.GetSettings().pandemic_glow_color))),
            get = function(_)
                local c = component.GetSettings().pandemic_glow_color
                return CreateColor(private.Util.Color(c))
            end,
            set = function(_, value)
                component.GetSettings().pandemic_glow_color = {value.r, value.g, value.b, value.a}
                component.Refresh()
            end,
        }
    end

    -- ===== 4c. CONSUMABLE TRACKER SECTION =====
    -- ConsumableTracker has icon layout settings (like TrinketTracker) plus
    -- per-family tracked-item checkboxes grouped by category.

    if isConsumableTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            default = def("layout"),
            get = function(_) return component.GetSettings().layout end,
            set = function(_, value)
                component.GetSettings().layout = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal"},
                {text = L["SETTING_LAYOUT_VERTICAL"], value = "vertical"},
                {text = L["SETTING_LAYOUT_BLOCK"], value = "block"},
            },
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            default = def("layout_alignment", "left"),
            get = function(_) return component.GetSettings().layout_alignment or "left" end,
            set = function(_, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if component.GetSettings().layout == "vertical" then
                    return {
                        {text = L["LAYOUT_ALIGNMENT_TOP"], value = "top"},
                        {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                        {text = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom"},
                    }
                end
                return {
                    {text = L["LAYOUT_ALIGNMENT_LEFT"], value = "left"},
                    {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                    {text = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right"},
                }
            end,
            hidden = function(_) return component.GetSettings().layout == "block" end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_BLOCK_DIRECTION"],
            desc = L["SETTING_BLOCK_DIRECTION_DESC"],
            default = def("block_direction", "horizontal"),
            get = function(_) return component.GetSettings().block_direction or "horizontal" end,
            set = function(_, value)
                component.GetSettings().block_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal"},
                {text = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical"},
            },
            hidden = function(_) return component.GetSettings().layout ~= "block" end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size"),
            get = function(_) return component.GetSettings().icon_size end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            default = def("icon_height", 0),
            get = function(_) return component.GetSettings().icon_height or 0 end,
            set = function(_, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_COUNT"],
            desc = L["SETTING_SHOW_COUNT_DESC"],
            default = def("show_count"),
            get = function(_) return component.GetSettings().show_count end,
            set = function(_, value)
                component.GetSettings().show_count = value
                component.Refresh()
            end,
        }

    end

    -- ===== 4c-glow. CONSUMABLE TRACKER GLOW SECTION =====
    if isConsumableTracker then
        local glowSettings = component.GetSettings().glow
        if glowSettings then
            result[#result + 1] = {kind = ST.Divider, hideLabel = true}
            result[#result + 1] = {kind = ST.Divider, name = L["SETTING_GLOW_EFFECTS"]}

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_ENABLED"],
                desc = L["SETTING_GLOW_ENABLED_DESC"],
                default = def("glow.enabled"),
                get = function(_) return component.GetSettings().glow.enabled end,
                set = function(_, value)
                    component.GetSettings().glow.enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_COMBAT_POTIONS_ONLY"],
                desc = L["SETTING_GLOW_COMBAT_POTIONS_ONLY_DESC"],
                default = def("glow.combat_potions_only"),
                get = function(_) return component.GetSettings().glow.combat_potions_only end,
                set = function(_, value)
                    component.GetSettings().glow.combat_potions_only = value
                    if value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_FLASH"],
                desc = L["SETTING_GLOW_FLASH_DESC"],
                default = def("glow.flash_enabled"),
                get = function(_) return component.GetSettings().glow.flash_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.flash_enabled = value
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_PULSE"],
                desc = L["SETTING_GLOW_PULSE_DESC"],
                default = def("glow.pulse_enabled"),
                get = function(_) return component.GetSettings().glow.pulse_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.pulse_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_GLOW_DURATION"],
                desc = L["SETTING_GLOW_DURATION_DESC"],
                default = def("glow.pulse_duration"),
                get = function(_) return component.GetSettings().glow.pulse_duration end,
                set = function(_, value)
                    component.GetSettings().glow.pulse_duration = value
                end,
                minValue = 0,
                maxValue = 30,
                valueStep = 1,
                hidden = function(_)
                    local glow = component.GetSettings().glow
                    return not glow.enabled or not glow.pulse_enabled
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_APPROACHING"],
                desc = L["SETTING_GLOW_APPROACHING_DESC"],
                default = def("glow.approaching_enabled"),
                get = function(_) return component.GetSettings().glow.approaching_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.approaching_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }

            result[#result + 1] = {
                kind = ST.Slider,
                name = L["SETTING_GLOW_APPROACHING_TIME"],
                desc = L["SETTING_GLOW_APPROACHING_TIME_DESC"],
                default = def("glow.approaching_time"),
                get = function(_) return component.GetSettings().glow.approaching_time end,
                set = function(_, value)
                    component.GetSettings().glow.approaching_time = value
                end,
                minValue = 0,
                maxValue = 15,
                valueStep = 1,
                hidden = function(_)
                    local glow = component.GetSettings().glow
                    return not glow.enabled or not glow.approaching_enabled
                end,
            }

            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L["SETTING_GLOW_ACTIVE"],
                desc = L["SETTING_GLOW_ACTIVE_DESC"],
                default = def("glow.active_enabled"),
                get = function(_) return component.GetSettings().glow.active_enabled end,
                set = function(_, value)
                    component.GetSettings().glow.active_enabled = value
                    if not value and component.StopAllGlows then
                        component.StopAllGlows()
                    end
                end,
                hidden = function(_) return not component.GetSettings().glow.enabled end,
            }
        end
    end

    -- ===== 4d. CONSUMABLE BUFF TRACKER SECTION =====
    if isConsumableBuffTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            default = def("layout"),
            get = function(_) return component.GetSettings().layout end,
            set = function(_, value)
                component.GetSettings().layout = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal"},
                {text = L["SETTING_LAYOUT_VERTICAL"], value = "vertical"},
                {text = L["SETTING_LAYOUT_BLOCK"], value = "block"},
            },
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            default = def("layout_alignment", "left"),
            get = function(_) return component.GetSettings().layout_alignment or "left" end,
            set = function(_, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                if component.GetSettings().layout == "vertical" then
                    return {
                        {text = L["LAYOUT_ALIGNMENT_TOP"], value = "top"},
                        {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                        {text = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom"},
                    }
                end
                return {
                    {text = L["LAYOUT_ALIGNMENT_LEFT"], value = "left"},
                    {text = L["LAYOUT_ALIGNMENT_CENTER"], value = "center"},
                    {text = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right"},
                }
            end,
            hidden = function(_) return component.GetSettings().layout == "block" end,
        }

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_BLOCK_DIRECTION"],
            desc = L["SETTING_BLOCK_DIRECTION_DESC"],
            default = def("block_direction", "horizontal"),
            get = function(_) return component.GetSettings().block_direction or "horizontal" end,
            set = function(_, value)
                component.GetSettings().block_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal"},
                {text = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical"},
            },
            hidden = function(_) return component.GetSettings().layout ~= "block" end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size"),
            get = function(_) return component.GetSettings().icon_size end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            default = def("icon_height", 0),
            get = function(_) return component.GetSettings().icon_height or 0 end,
            set = function(_, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 0,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_HIDE_WHEN_APPLIED"],
            desc = L["SETTING_HIDE_WHEN_APPLIED_DESC"],
            default = def("hide_when_applied"),
            get = function(_) return component.GetSettings().hide_when_applied end,
            set = function(_, value)
                component.GetSettings().hide_when_applied = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }

        -- Category toggles
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_TRACKED_ITEMS"]}

        track("tracked_categories")
        local categoryOrder = private.ConsumableBuffTracker.GetCategoryOrder()
        for _, category in ipairs(categoryOrder) do
            local labelKey = private.ConsumableBuffTracker.GetCategoryLabel(category)
            result[#result + 1] = {
                kind = ST.Checkbox,
                name = L[labelKey],
                default = true,
                get = function(_)
                    local val = component.GetSettings().tracked_categories[category]
                    if val == nil then return true end
                    return val
                end,
                set = function(_, value)
                    component.GetSettings().tracked_categories[category] = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
            }
        end

        -- Glow settings
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_GLOW_EFFECTS"]}

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_GLOW_ENABLED"],
            desc = L["SETTING_GLOW_ENABLED_DESC"],
            default = def("glow.enabled"),
            get = function(_) return component.GetSettings().glow.enabled end,
            set = function(_, value)
                component.GetSettings().glow.enabled = value
                if not value and component.StopAllGlows then
                    component.StopAllGlows()
                end
                component.Refresh()
            end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_GLOW_MISSING"],
            desc = L["SETTING_GLOW_MISSING_DESC"],
            default = def("glow.missing_enabled"),
            get = function(_) return component.GetSettings().glow.missing_enabled end,
            set = function(_, value)
                component.GetSettings().glow.missing_enabled = value
                component.Refresh()
            end,
            hidden = function(_) return not component.GetSettings().glow.enabled end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_GLOW_EXPIRING"],
            desc = L["SETTING_GLOW_EXPIRING_DESC"],
            default = def("glow.expiring_enabled"),
            get = function(_) return component.GetSettings().glow.expiring_enabled end,
            set = function(_, value)
                component.GetSettings().glow.expiring_enabled = value
                component.Refresh()
            end,
            hidden = function(_) return not component.GetSettings().glow.enabled end,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_EXPIRING_TIME"],
            desc = L["SETTING_EXPIRING_TIME_DESC"],
            default = def("glow.expiring_time"),
            get = function(_) return component.GetSettings().glow.expiring_time end,
            set = function(_, value)
                component.GetSettings().glow.expiring_time = value
            end,
            minValue = 30,
            maxValue = 900,
            valueStep = 30,
            hidden = function(_) return not component.GetSettings().glow.expiring_enabled end,
        }
    end

    -- ===== 4e. RAID BUFF TRACKER SECTION =====
    if isRaidBuffTracker then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_ICON_LAYOUT"]}

        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            default = def("layout"),
            get = function(_) return component.GetSettings().layout end,
            set = function(_, value)
                component.GetSettings().layout = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = {
                {text = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal"},
                {text = L["SETTING_LAYOUT_VERTICAL"], value = "vertical"},
                {text = L["SETTING_LAYOUT_BLOCK"], value = "block"},
            },
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            default = def("icon_size"),
            get = function(_) return component.GetSettings().icon_size end,
            set = function(_, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = 8,
            maxValue = 80,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Slider,
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            default = def("icon_offset"),
            get = function(_) return component.GetSettings().icon_offset end,
            set = function(_, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            minValue = -5,
            maxValue = 20,
            valueStep = 1,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_HIDE_WHEN_APPLIED"],
            desc = L["SETTING_HIDE_WHEN_APPLIED_DESC"],
            default = def("hide_when_applied"),
            get = function(_) return component.GetSettings().hide_when_applied end,
            set = function(_, value)
                component.GetSettings().hide_when_applied = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_ALL_BUFFS"],
            desc = L["SETTING_SHOW_ALL_BUFFS_DESC"],
            default = def("show_all_buffs"),
            get = function(_) return component.GetSettings().show_all_buffs end,
            set = function(_, value)
                component.GetSettings().show_all_buffs = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }

        -- Glow settings
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {kind = ST.Divider, name = L["SETTING_GLOW_EFFECTS"]}

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_GLOW_ENABLED"],
            desc = L["SETTING_GLOW_ENABLED_DESC"],
            default = def("glow.enabled"),
            get = function(_) return component.GetSettings().glow.enabled end,
            set = function(_, value)
                component.GetSettings().glow.enabled = value
                if not value and component.StopAllGlows then
                    component.StopAllGlows()
                end
                component.Refresh()
            end,
        }

        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_GLOW_MISSING"],
            desc = L["SETTING_GLOW_MISSING_DESC"],
            default = def("glow.missing_enabled"),
            get = function(_) return component.GetSettings().glow.missing_enabled end,
            set = function(_, value)
                component.GetSettings().glow.missing_enabled = value
                component.Refresh()
            end,
            hidden = function(_) return not component.GetSettings().glow.enabled end,
        }
    end

    -- ===== KEYBIND TEXT =====
    -- Generic keybind toggle for any component with a keybind_font setting.
    if component.GetSettings().keybind_font ~= nil then
        result[#result + 1] = {kind = ST.Divider, hideLabel = true}
        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_SHOW_KEYBIND"],
            desc = L["SETTING_SHOW_KEYBIND_DESC"],
            default = def("keybind_font.enabled"),
            get = function(_) return component.GetSettings().keybind_font.enabled end,
            set = function(_, value)
                component.GetSettings().keybind_font.enabled = value
                component.Refresh()
            end,
        }
    end

    -- Color mode option for health bar (detected via color_mode field).
    if component.GetSettings().color_mode ~= nil then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_COLOR_MODE"],
            desc = L["SETTING_COLOR_MODE_DESC"],
            default = def("color_mode"),
            get = function(_) return component.GetSettings().color_mode end,
            set = function(_, value)
                component.GetSettings().color_mode = value
                component.Refresh()
            end,
            values = {
                {text = L["COLOR_MODE_CLASS"], value = "class"},
                {text = L["COLOR_MODE_GRADIENT"], value = "gradient"},
            },
        }
    end

    -- Text format option for health bar (detected via text_format field).
    if component.GetSettings().text_format ~= nil then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_TEXT_FORMAT"],
            desc = L["SETTING_TEXT_FORMAT_DESC"],
            default = def("text_format"),
            get = function(_) return component.GetSettings().text_format end,
            set = function(_, value)
                component.GetSettings().text_format = value
                component.Refresh()
            end,
            values = {
                {text = L["TEXT_FORMAT_PERCENT"], value = "percent"},
                {text = L["TEXT_FORMAT_CURRENT"], value = "current"},
                {text = L["TEXT_FORMAT_BOTH"], value = "both"},
                {text = L["TEXT_FORMAT_NONE"], value = "none"},
            },
        }
    end

    -- Cast bar text display (detected via cast_text_format field).
    if component.GetSettings().cast_text_format ~= nil then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_CAST_TEXT_FORMAT"],
            desc = L["SETTING_CAST_TEXT_FORMAT_DESC"],
            default = def("cast_text_format"),
            get = function(_) return component.GetSettings().cast_text_format end,
            set = function(_, value)
                component.GetSettings().cast_text_format = value
                -- fontsDirty gate: name/time show-hide lives in ApplyFonts,
                -- which Refresh only runs when fontsDirty is set.
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
            values = {
                {text = L["CAST_TEXT_FORMAT_BOTH"], value = "both"},
                {text = L["CAST_TEXT_FORMAT_NAME"], value = "name"},
                {text = L["CAST_TEXT_FORMAT_TIME"], value = "time"},
                {text = L["CAST_TEXT_FORMAT_NONE"], value = "none"},
            },
        }
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_CAST_TIME_STYLE"],
            desc = L["SETTING_CAST_TIME_STYLE_DESC"],
            default = def("cast_time_style"),
            get = function(_) return component.GetSettings().cast_time_style end,
            set = function(_, value)
                component.GetSettings().cast_time_style = value
                -- fontsDirty gate: cueTimeStyle is written by ApplyFonts, which
                -- Refresh only runs when fontsDirty is set.
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
            values = {
                {text = L["CAST_TIME_STYLE_REMAINING"], value = "remaining"},
                {text = L["CAST_TIME_STYLE_ELAPSED_TOTAL"], value = "elapsed_total"},
                {text = L["CAST_TIME_STYLE_REMAINING_TOTAL"], value = "remaining_total"},
            },
        }
    end

    -- Text format options for power bar — separate settings for mana vs other resources.
    local textFormatValues = {
        {text = L["TEXT_FORMAT_PERCENT"], value = "percent"},
        {text = L["TEXT_FORMAT_CURRENT"], value = "current"},
        {text = L["TEXT_FORMAT_BOTH"], value = "both"},
        {text = L["TEXT_FORMAT_NONE"], value = "none"},
    }
    if component.GetSettings().text_format_mana ~= nil then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_TEXT_FORMAT_MANA"],
            desc = L["SETTING_TEXT_FORMAT_MANA_DESC"],
            default = def("text_format_mana"),
            get = function(_) return component.GetSettings().text_format_mana end,
            set = function(_, value)
                component.GetSettings().text_format_mana = value
                component.Refresh()
            end,
            values = textFormatValues,
        }
    end
    if component.GetSettings().text_format_other ~= nil then
        result[#result + 1] = {
            kind = ST.Dropdown,
            name = L["SETTING_TEXT_FORMAT_OTHER"],
            desc = L["SETTING_TEXT_FORMAT_OTHER_DESC"],
            default = def("text_format_other"),
            get = function(_) return component.GetSettings().text_format_other end,
            set = function(_, value)
                component.GetSettings().text_format_other = value
                component.Refresh()
            end,
            values = textFormatValues,
        }
    end

    -- Track instant casts (PlayerCastBar only)
    if componentName == "PlayerCastBar" and component.GetSettings().track_instant_casts ~= nil then
        result[#result + 1] = {
            kind = ST.Checkbox,
            name = L["SETTING_TRACK_INSTANT_CASTS"],
            desc = L["SETTING_TRACK_INSTANT_CASTS_DESC"],
            default = def("track_instant_casts"),
            get = function(_) return component.GetSettings().track_instant_casts end,
            set = function(_, value)
                component.GetSettings().track_instant_casts = value
                component.Refresh()
            end,
        }
    end

    -- LibEditMode's Reset To Default calls every widget's set with the widget's
    -- `default` and a third argument, true. The first widget takes the whole
    -- click instead and the rest ignore it: a set per widget would run the full
    -- layout once per widget, and several setters do more than store a value
    -- (a Frame Point pick marks the point manual, an anchor pick captures the
    -- current position) -- right for an edit, wrong for a reset.
    local resetOwner
    for i, entry in ipairs(result) do
        local set = entry.set
        if set then
            resetOwner = resetOwner or i
            entry.set = function(layoutName, value, isReset)
                if isReset ~= true then return set(layoutName, value) end
                if i ~= resetOwner then return end
                resetToDefaults(component, resetPaths)
                LibEditMode:AddFrameSettings(component.GetFrame(), buildFrameSettings(component))
                private.Options.RefreshAll()
            end
        end
    end

    return result
end

---Components that should show a "Cooldown Manager Settings" button in their Edit Mode panel.
---@type table<string, boolean>
local cooldownViewerButtonComponents = {
    CooldownTracker = true,
    BuffTracker = true,
    BuffTrackerBars = true,
    UtilitiesTracker = true,
}


---Register a single component frame with LibEditMode.
---
---Free-moving components (anchor_parent = "none") are draggable in edit mode.
---The dropped position is persisted into anchor_profile using the raw SetPoint fields
---(frame_point, parent_point, relative_frame, xoff, yoff) so Anchor.Refresh() picks
---it up immediately and the position survives a reload.
---
---Anchored components (anchor_parent = some component) snap back to their computed
---position on small drags.  If dragged beyond DETACH_THRESHOLD pixels from the
---anchor position, the component automatically switches to free-moving mode.
---
---@param component component
local function registerComponent(component)
    local frame = component.GetFrame()
    if not frame then return end

    local componentName = component.GetComponentName()

    -- LibEditMode callback signature: (frame, layoutName, point, x, y)
    -- point is the frame's own anchor point; x, y are UIParent offsets.
    -- This maps to: frame:SetPoint(point, UIParent, point, x, y)
    local callback = function(_, _, point, x, y)
        private.Anchor.draggingFrame = nil
        -- Reset Position: back to the component's default anchor, not to
        -- wherever it sat at login (which is all LibEditMode's registered
        -- default position could express, and which detached an anchored
        -- component, since its drag path read the jump as a detach).
        if point == RESET_POSITION.point and x == RESET_POSITION.x and y == RESET_POSITION.y then
            restoreDefaultAnchor(component, getDefaultSettings(component))
            private.Anchor.RebuildAnchorTree()
            private.Anchor.Refresh()
            LibEditMode:AddFrameSettings(frame, buildFrameSettings(component))
            LibEditMode:RefreshFrameSettings(frame)
            private.Options.RefreshAll()
            return
        end
        local settings = component.GetSettings()
        -- An absent anchor_parent is free-moving, and "cursor" takes the same
        -- branch here although the panels treat it as anchored.  Reading it as
        -- anchored sent this drag down the detach path, which overwrites
        -- anchor_parent with "none" -- silently ending an AF's cursor-following.
        local ap = settings.anchor_profile.anchor_parent
        local isFreeMoving = not ap or ap == "none" or ap == "cursor"
        if isFreeMoving then
            local scale = frame:GetScale()
            capturePositionForFreeMove(componentName, settings, settings.anchor_profile,
                frame:GetLeft() * scale, frame:GetRight() * scale,
                frame:GetTop() * scale, frame:GetBottom() * scale, scale)
            -- Re-apply layout so free-moving frames land at the saved position.
            private.Anchor.Refresh()
            -- Defer panel refresh so LibEditMode's selection state settles after
            -- Anchor.Refresh repositions the frame.
            C_Timer.After(0, function()
                LibEditMode:RefreshFrameSettings(frame)
                private.Options.RefreshAll()
            end)
        else
            -- Anchored component: check if it was dragged far enough to detach.
            local scale = frame:GetScale()
            local dragLeft = frame:GetLeft() * scale
            local dragRight = frame:GetRight() * scale
            local dragBottom = frame:GetBottom() * scale
            local dragTop = frame:GetTop() * scale
            local dragCX = (dragLeft + dragRight) / 2
            local dragCY = (dragBottom + dragTop) / 2

            -- Snap back to the computed anchor position.
            private.Anchor.Refresh()

            -- Compare dragged center to snapped anchor center.
            local snapLeft = frame:GetLeft()
            if snapLeft then
                local snapRight = frame:GetRight()
                local snapCX = (snapLeft + snapRight) / 2 * scale
                local snapCY = (frame:GetBottom() + frame:GetTop()) / 2 * scale
                local dx = dragCX - snapCX
                local dy = dragCY - snapCY
                local distance = math.sqrt(dx * dx + dy * dy)

                if distance > DETACH_THRESHOLD then
                    capturePositionForFreeMove(componentName, settings, settings.anchor_profile,
                        dragLeft, dragRight, dragTop, dragBottom, scale)
                    settings.anchor_profile.anchor_parent = "none"
                    private.Anchor.RebuildAnchorTree()
                    private.Anchor.Refresh()
                    LibEditMode:AddFrameSettings(frame, buildFrameSettings(component))
                    C_Timer.After(0, function()
                        LibEditMode:RefreshFrameSettings(frame)
                        private.Options.RefreshAll()
                    end)
                    local name = displayNames[componentName] or componentName
                    private.print(string.format(L["DETACH_ON_DRAG"], name))
                end
            end
        end
    end

    -- For additional frames, read the user-set name from profile settings.
    -- AF names can change (user rename), so store on frame.editModeName for
    -- dynamic lookup by LibEditMode's GetSystemName closure instead of passing
    -- a static string that would be captured by value.
    local displayName = displayNames[componentName]
    if not displayName then
        local s = component.GetSettings()
        displayName = (s and s.name) or componentName
        frame.editModeName = displayName
        LibEditMode:AddFrame(frame, callback, RESET_POSITION, nil)
    else
        LibEditMode:AddFrame(frame, callback, RESET_POSITION, displayName)
    end
    LibEditMode:AddFrameSettings(frame, buildFrameSettings(component))

    -- Prevent deferred layout refreshes from cancelling the native WoW drag.
    -- OnDragStart sets draggingFrame; the position callback clears it on stop.
    local selection = LibEditMode.frameSelections[frame]
    if selection then
        selection:HookScript("OnDragStart", function()
            private.Anchor.draggingFrame = frame
        end)
    end

    if cooldownViewerButtonComponents[componentName] and private.compat.HasCooldownManager() then
        LibEditMode:AddFrameSettingsButtons(frame, {
            {
                text = L["COOLDOWN_MANAGER_SETTINGS"],
                click = function()
                    _G["CooldownViewerSettings"]:Show()
                end,
            },
        })
    end

    -- Unified "Component Settings" button opens Trackers tab with this component pre-selected
    LibEditMode:AddFrameSettingsButtons(frame, {
        {
            text = L["OPEN_COMPONENT_SETTINGS"],
            click = function()
                private.Options.OpenOptionsPanel(private.Options.TRACKERS_TAB_INDEX, componentName)
            end,
        },
    })
end

---Rebuild and re-register Edit Mode settings for all components.
---Called on profile change so closures read from the new profile.
---Additional frames created by a profile switch may not yet be registered
---with LibEditMode; register them on the fly so AddFrameSettings succeeds.
editmode.Refresh = function()
    for _, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local frame = component.GetFrame()
        if frame then
            if not LibEditMode.frameSelections[frame] then
                -- Frame exists but isn't registered — additional frame from a
                -- profile switch.  Run the full registration path first.
                local settings = component.GetSettings()
                if settings and settings.frame_type then
                    editmode.RegisterAdditionalFrame(component)
                else
                    registerComponent(component)
                end
            end
            if LibEditMode.frameSelections[frame] then
                LibEditMode:AddFrameSettings(frame, buildFrameSettings(component))
            end
        end
    end
end

---True when a component sits where its own xoff/yoff put it — the panels'
---isFreeMoving rule. An ABSENT anchor_parent counts, and a secure-click tracker
---is free exactly when it follows no position_reference: both ship with no
---anchor_parent, so an `anchor_parent == "none"` test never clamped them.
---A cursor-following Additional Frame is left out: Anchoring never places it by
---its offsets, and in Edit Mode it stays where the cursor last put it.
---@param component component
---@param anchorProfile anchor_profile
---@return boolean
local function isPlacedByFreeMoveOffsets(component, anchorProfile)
    if private.Anchor.secureClickComponents[component.GetComponentName()] then
        local pr = anchorProfile.position_reference
        return not pr or pr == "none"
    end
    local ap = anchorProfile.anchor_parent
    return not ap or ap == "none"
end

---Clamp any free-moving component that is even partially off-screen back onto the
---screen. Called on Edit Mode enter so the user never finds a component unreachable.
---Additional Frames are registered components, so this walk covers them too.
local clampFreeMovingComponentsToScreen = function()
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local anyChanged = false

    for _, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local settings = component.GetSettings()
        local anchorProfile = settings.anchor_profile
        if isPlacedByFreeMoveOffsets(component, anchorProfile) then
            local frame = component.GetFrame()
            if frame then
                local left = frame:GetLeft()
                local right = frame:GetRight()
                local top = frame:GetTop()
                local bottom = frame:GetBottom()

                if left and right and top and bottom then
                    local dx = 0
                    local dy = 0
                    local frameWidth = right - left
                    local frameHeight = top - bottom

                    if frameWidth >= screenWidth then
                        dx = (screenWidth / 2) - (left + right) / 2
                    elseif left < 0 then
                        dx = -left
                    elseif right > screenWidth then
                        dx = screenWidth - right
                    end

                    if frameHeight >= screenHeight then
                        dy = (screenHeight / 2) - (bottom + top) / 2
                    elseif bottom < 0 then
                        dy = -bottom
                    elseif top > screenHeight then
                        dy = screenHeight - top
                    end

                    if dx ~= 0 or dy ~= 0 then
                        anchorProfile.xoff = (anchorProfile.xoff or 0) + dx
                        anchorProfile.yoff = (anchorProfile.yoff or 0) + dy
                        anyChanged = true
                    end
                end
            end
        end
    end

    if anyChanged then
        private.Anchor.Refresh()
    end
end

---Register a dynamically created additional frame with EditMode.
---Adds it to the viewerTrackerComponents or barTrackerComponents lookup
---based on frame_type, sets width config, marks as non-anchorable, then
---registers with LibEditMode.
---@param component component
editmode.RegisterAdditionalFrame = function(component)
    local componentName = component.GetComponentName()
    local settings = component.GetSettings()
    if not settings then return end

    -- Add to the appropriate layout type table
    if settings.frame_type == "bar" then
        barTrackerComponents[componentName] = true
    else
        viewerTrackerComponents[componentName] = true
        widthConfig[componentName] = {widthMin = 20, widthMax = 1000}
    end
    widthPctConfig[componentName] = {min = 25, max = 200}

    -- Register with LibEditMode
    registerComponent(component)

    -- If EditMode is already active, show the new selection overlay immediately.
    -- Normally selections are shown via resetSelection() on EditMode enter, but
    -- that already fired before this frame existed.
    if LibEditMode.isEditing then
        local frame = component.GetFrame()
        local selection = frame and LibEditMode.frameSelections[frame]
        if selection then
            selection:ShowHighlighted()
        end
    end
end

---Remove an additional frame from LibEditMode and internal tracking tables.
---Called when an additional frame is destroyed (profile switch, user delete).
---LibEditMode has no public RemoveFrame API, so we clean its internal tables
---directly; the selection child frame stays parented but hidden forever (WoW
---never garbage-collects frames).
---@param component component
editmode.UnregisterAdditionalFrame = function(component)
    local frame = component.GetFrame()
    local componentName = component.GetComponentName()

    barTrackerComponents[componentName] = nil
    viewerTrackerComponents[componentName] = nil
    widthConfig[componentName] = nil
    widthPctConfig[componentName] = nil

    if frame then
        local selection = LibEditMode.frameSelections[frame]
        if selection then
            selection:Hide()
        end
        LibEditMode.frameSelections[frame] = nil
        LibEditMode.frameCallbacks[frame] = nil
        LibEditMode.frameDefaults[frame] = nil
        LibEditMode.frameSettings[frame] = nil
        LibEditMode.frameButtons[frame] = nil
    end
end

editmode.Initialize = function()
    for _, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local settings = component.GetSettings()
        if settings and settings.frame_type then
            -- Additional frames need RegisterAdditionalFrame to set up
            -- viewerTrackerComponents/barTrackerComponents before building
            -- EditMode settings (otherwise height slider is shown with nil).
            editmode.RegisterAdditionalFrame(component)
        else
            registerComponent(component)
        end
    end

    -- Re-anchor all components whenever the active Edit Mode layout changes.
    LibEditMode:RegisterCallback('layout', function()
        private.Anchor.Refresh()
    end)

    -- When Edit Mode opens: set the flag, refresh all components so they can
    -- activate edit mode previews (health bar keeps unit, cast bars show dummy cast),
    -- then re-anchor so disabled frames become visible and are positioned correctly.
    -- Finally clamp any free-moving components that ended up off-screen back into view.
    LibEditMode:RegisterCallback('enter', function()
        if InCombatLockdown() then return end
        private.isEditMode = true
        private.AdditionalFrameManager.RebuildRouting()
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
        clampFreeMovingComponentsToScreen()
    end)

    -- When Edit Mode closes: clear the flag, refresh all components to restore their
    -- normal visibility (disabled frames are re-hidden by their own Refresh logic),
    -- then re-anchor so only enabled components are positioned.
    -- A deferred C_Timer.After(0, …) re-anchor handles the case where Blizzard repositions
    -- native viewer frames (EssentialCooldownViewer, etc.) synchronously after our exit
    -- callback returns, overwriting the positions we just set.
    LibEditMode:RegisterCallback('exit', function()
        private.isEditMode = false
        private.AdditionalFrameManager.RebuildRouting()
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
        C_Timer.After(0, function()
            private.Anchor.Refresh()
        end)
    end)
end

editmode.CapturePositionForFreeMove = capturePositionForFreeMove
editmode.SetFreeMovePoint = setFreeMovePoint
editmode.BuildFrameSettings = buildFrameSettings

private.EditMode = editmode
