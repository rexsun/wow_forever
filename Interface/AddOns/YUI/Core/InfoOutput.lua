local _, namespace = ...
local YUI = _G.YUI or namespace
if not YUI or YUI.InfoOutput then return end

local Service = { API_VERSION = 1 }
YUI.InfoOutput = Service
local MODULE, MOVER = "core.info-output", "yui.core.info-output"
local MIN_HEIGHT, POOL_SIZE, QUEUE_LIMIT, KEY_LIMIT, RECENT_LIMIT = 120, 9, 32, 256, 100
local PAD, GAP, MIN_ROW = 4, 2, 20
local priorityRank = { low = 1, normal = 2, important = 3 }
local maxWait = { low = 18, normal = 45, important = 90 }
local defaults = { font = "", fontSize = 14, fontOutline = "NONE", fontShadow = true, fontMonochrome = false,
    fontColor = { mode = "state" }, align = "CENTER", growth = "down", width = 560, maxRows = 5, duration = 8, interval = .25,
    enterDuration = .12, moveDuration = .10, exitDuration = .10 }
local defaultPlacement = {
    anchor = { point = "BOTTOM", relative = "UIParent", relativePoint = "BOTTOM" },
    offset = { x = 0, y = 160 },
}
if YUI.IsForever and (YUI.ProductId == "suite" or YUI.ProductId == "toolbox") then
    defaults.width, defaults.fontSize, defaults.fontOutline = 450, 16, "OUTLINE"
    defaultPlacement.offset.y = 685
end
local ranges = { fontSize = { 10, 32 }, width = { 260, 900 }, maxRows = { 2, 8 }, duration = { 2, 20 },
    interval = { 0, .75 }, enterDuration = { 0, .6 }, moveDuration = { 0, .6 }, exitDuration = { 0, .6 } }
local queue, live, pool, keys, keyOrder, history = {}, {}, {}, {}, {}, {}
local animationOwner, previewOwner = {}, {}
local settings = defaults
local loaded, loadedProfile
local nextOrdinary, previewSource = 0, nil
local root, preview, initialized, enabled, editing, previewVisible, registered, previewRaised
local timer, timerDeadline, timerGeneration = nil, nil, 0
local sequence, accepted, rejected, duplicates, expired = 0, 0, 0, 0, 0
local merged, overflow, stale = 0, 0, 0
local updating, dirty, expiring = false, false, false
local Refresh, UpdateBounds, ResetRowAnchors

local function Secret(value)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue then return security.IsSecretValue(value) end
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        return not ok or result == true
    end
    return false
end

local function PlainTable(value)
    if Secret(value) or type(value) ~= "table" then return false end
    local security = YUI.API and YUI.API.Security
    if security and security.CanAccessTable and security.CanAccessTable(value) == false then return false end
    return getmetatable(value) == nil
end

local function Number(value)
    return not Secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Owner(value)
    if Secret(value) then return false end
    if type(value) == "string" then return value ~= "" and #value <= 256 end
    if type(value) ~= "table" then return false end
    local security = YUI.API and YUI.API.Security
    return not security or not security.CanAccessTable or security.CanAccessTable(value) ~= false
end

local function Now()
    local combat = YUI.API and YUI.API.Combat
    return combat and combat.GetTime and combat.GetTime() or GetTime()
end

local function GetProfile()
    return YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile(YUI.ProductId)
end

local function NormalizeSetting(key, value, fromProfile)
    if Secret(value) then return nil end
    if key == "font" then
        if type(value) == "string" and not value:find("%c") then
            if #value <= 128 and not value:find("[/\\]") then return value end
            if fromProfile and #value <= 260 then return value end
        end
        return nil
    elseif key == "align" then
        return (value == "LEFT" or value == "CENTER" or value == "RIGHT") and value or nil
    elseif key == "growth" then
        return (value == "up" or value == "down") and value or nil
    elseif key == "fontOutline" then
        return (value == "NONE" or value == "OUTLINE" or value == "THICKOUTLINE") and value or nil
    elseif key == "fontShadow" or key == "fontMonochrome" then
        if type(value) == "boolean" then return value end
        return nil
    elseif key == "fontColor" then
        if not PlainTable(value) then return nil end
        local mode = rawget(value, "mode")
        if Secret(mode) then return nil end
        if mode == "state" then return { mode = "state" } end
        if mode ~= nil and mode ~= "custom" then return nil end
        local color = { mode = "custom" }
        for index = 1, 4 do
            local part = rawget(value, index)
            if not Number(part) then return nil end
            color[index] = math.max(0, math.min(1, part))
        end
        return color
    end
    local range = ranges[key]
    if not range or not Number(value) then return nil end
    if key == "fontSize" or key == "width" or key == "maxRows" then value = math.floor(value + .5) end
    return math.max(range[1], math.min(range[2], value))
end

local function LoadSettings(profile)
    loaded, loadedProfile = true, profile
    local stored = profile and profile.InfoOutput
    local readable = PlainTable(stored)
    settings = {}
    for key, default in pairs(defaults) do
        local value
        if readable then value = NormalizeSetting(key, rawget(stored, key), true) end
        if value == nil then value = default end
        settings[key] = value
    end
end

local function EnsureSettings()
    if initialized then return end
    local profile = GetProfile()
    if not loaded or loadedProfile ~= profile then LoadSettings(profile) end
end

local function GrowthPoint()
    return settings.growth == "up" and "BOTTOMLEFT" or "TOPLEFT"
end

local function ApplyRowColor(row)
    local color = row.record.color
    if not color and settings.fontColor.mode == "custom" then color = settings.fontColor end
    if color then
        row.text.gui2ColorKey = nil
        row.text:SetTextColor(color[1], color[2], color[3], color[4])
    else
        local key = row.record.priority == "important" and "color.text.rewardHeading" or "color.text.primary"
        row.text.gui2ColorKey = key
        row.text:SetTextColor(YUI.GUI2:GetColor(key))
    end
end

local function PaintRow(row)
    local record = row.record
    local text = record.count > 1 and (record.text .. "  ×" .. record.count) or record.text
    local iconSize = 0
    local tooltip = YUI.GUI2.Tooltip
    local position = record.iconPosition
    if position then
        local before, item = text:sub(1, position - 1), text:sub(position)
        if record.icon and tooltip and tooltip.IconText then
            iconSize = math.max(10, settings.fontSize - 2)
            item = tooltip:IconText(item, record.icon, iconSize, true)
        end
        text = before .. item
        local label = row.text
        if position > 1 and label.GetUnboundedStringWidthForText
            and label:GetUnboundedStringWidthForText(text) > label:GetWidth() then
            text = before:gsub("%s+$", "") .. "\n" .. item
        end
    elseif record.icon and tooltip and tooltip.IconText then
        iconSize = settings.fontSize + 4
        text = tooltip:IconText(text, record.icon, iconSize)
    end
    if row.displayText ~= text then
        row.text:SetText(text)
        row.displayText = text
    end
    row.height = math.max(MIN_ROW, iconSize + 4, math.ceil(row.text:GetStringHeight()) + 4)
    row:SetHeight(row.height)
end

local function ApplyAppearance()
    if not root then return end
    local gui = YUI.GUI2
    local fallback = gui.Fonts and gui.Fonts.normal or (gui.GetFont and gui:GetFont("font.family.body")) or STANDARD_TEXT_FONT
    local font = fallback
    if settings.font ~= "" and gui.FontStyle and gui.FontStyle.FontPath then
        font = gui.FontStyle.FontPath(settings.font, font)
    end
    local width = settings.width - PAD * 2
    local flags = settings.fontOutline ~= "NONE" and settings.fontOutline or ""
    if settings.fontMonochrome then flags = flags == "" and "MONOCHROME" or flags .. ",MONOCHROME" end
    root:SetWidth(settings.width)
    local function ApplyText(text)
        text:SetWidth(width)
        text:SetJustifyH(settings.align)
        if font and text:SetFont(font, settings.fontSize, flags) == false and fallback then
            text:SetFont(fallback, settings.fontSize, flags)
        end
        text:SetShadowColor(0, 0, 0, settings.fontShadow and .6 or 0)
        text:SetShadowOffset(settings.fontShadow and 1 or 0, settings.fontShadow and -1 or 0)
    end
    local point = GrowthPoint()
    preview:ClearAllPoints()
    preview:SetPoint(point, root, point, PAD, settings.growth == "up" and PAD or -PAD)
    ApplyText(preview)
    for _, row in ipairs(pool) do
        row:SetWidth(width)
        ApplyText(row.text)
        if row.record then
            ApplyRowColor(row)
            PaintRow(row)
        end
    end
end

function Service:GetSetting(key)
    if Secret(key) or type(key) ~= "string" then return nil end
    EnsureSettings()
    if key == "fontColor" then return NormalizeSetting(key, settings[key]) end
    return settings[key]
end

local function SaveSettings()
    local profile = GetProfile()
    if profile then
        local stored = {}
        for key in pairs(defaults) do stored[key] = settings[key] end
        stored.fontColor = NormalizeSetting("fontColor", settings.fontColor)
        profile.InfoOutput = stored
    end
end

local function RefreshAppearance()
    ApplyAppearance()
    if registered and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(MOVER) end
end

function Service:SetSetting(key, value)
    if Secret(key) or type(key) ~= "string" then return false end
    value = NormalizeSetting(key, value)
    if value == nil then return false end
    EnsureSettings()
    if settings[key] == value then return true end
    settings[key] = value
    SaveSettings()
    if key == "growth" then ResetRowAnchors() end
    if key:sub(1, 4) == "font" or key == "align" or key == "growth" or key == "width" then
        RefreshAppearance()
    elseif key == "interval" then
        nextOrdinary = math.min(nextOrdinary, Now() + value)
    end
    Refresh()
    return true
end

function Service:ResetSettings()
    EnsureSettings()
    local growthChanged = settings.growth ~= defaults.growth
    settings = {}
    for key, value in pairs(defaults) do settings[key] = value end
    SaveSettings()
    nextOrdinary = math.min(nextOrdinary, Now() + defaults.interval)
    if growthChanged then ResetRowAnchors() end
    RefreshAppearance()
    Refresh()
end

local function CancelTimer()
    timerGeneration = timerGeneration + 1
    if timer then timer:Cancel(); timer = nil end
    timerDeadline = nil
end

local function Anchor(row, y)
    if row.baseY == y then return end
    row:ClearAllPoints()
    local point = GrowthPoint()
    row:SetPoint(point, root, point, PAD, y)
    row.baseY = y
end

local function Alpha(row, value)
    if row.currentAlpha == value then return end
    row.currentAlpha = value
    row:SetAlpha(value)
end

local function StopMotion(row, settle)
    row.generation = (row.generation or 0) + 1
    local handle = row.motion
    row.motion, row.phase = nil, nil
    if handle then handle:Cancel() end
    if settle then
        if row.goalY then Anchor(row, row.goalY) end
        Alpha(row, 1)
    end
end

local function StopAnimationOwner()
    local animation = YUI.Animation
    if animation and animation.StopOwner then animation:StopOwner(animationOwner, false) end
end

local function Animate(row, phase, duration, y, alpha, done)
    row.generation = (row.generation or 0) + 1
    local generation, completed = row.generation, false
    local fromY, fromAlpha = row.baseY or y, row.currentAlpha or 1
    row.phase = phase
    local function Step(progress)
        if row.generation ~= generation then return end
        Anchor(row, fromY + (y - fromY) * progress)
        Alpha(row, fromAlpha + (alpha - fromAlpha) * progress)
    end
    local function Finish()
        if completed or row.generation ~= generation then return end
        completed = true
        row.motion, row.phase = nil, nil
        Step(1)
        done()
    end
    local animation = YUI.Animation
    local spec = { target = row, owner = animationOwner, key = MODULE, duration = duration,
        easing = "out", mode = "replace", from = 0, to = 1, onUpdate = Step, onFinished = Finish }
    -- Reuse the shared bounded tween driver; never allocate native groups per message.
    if duration > 0 and not editing and animation and animation.Tween and animation.TweenDriver and animation.TweenDriver.Play then
        local handle = animation:Tween(spec)
        if handle and not handle.noop and handle.IsPlaying and handle:IsPlaying() then
            row.motion = handle
            return
        end
    end
    Finish()
end

local function Release(row)
    StopMotion(row)
    row:Hide()
    row.text:SetText("")
    row.displayText = nil
    row.record, row.exiting, row.fresh, row.goalY, row.baseY, row.currentAlpha = nil, nil, nil, nil, nil, nil
    for i = #live, 1, -1 do if live[i] == row then table.remove(live, i); break end end
end

ResetRowAnchors = function()
    -- Keep message lifetimes when the growth edge changes.
    for index = #live, 1, -1 do
        local row = live[index]
        if row.exiting then
            Release(row)
        else
            StopMotion(row)
            row.baseY, row.goalY = nil, nil
            Alpha(row, 1)
        end
    end
end

local function Exit(row)
    if row.exiting then return end
    StopMotion(row)
    row.exiting = true
    row.goalY = row.baseY
    Animate(row, "exit", settings.exitDuration, row.baseY, 0, function()
        Release(row)
        Refresh()
    end)
end

local function SetStatus(record, status)
    if record.history then record.history.status = status end
end

local function PruneQueue(now)
    for index = #queue, 1, -1 do
        local record = queue[index]
        if record.waitUntil <= now then
            table.remove(queue, index)
            SetStatus(record, "expired")
            stale = stale + 1
        end
    end
end

local function NextIndex(now)
    if #live > settings.maxRows then return nil end
    local reserveOnly = #live == settings.maxRows
    local best, rank
    for index, record in ipairs(queue) do
        local important = record.priority == "important"
        if important or (not reserveOnly and now >= nextOrdinary) then
            local score = now - record.time >= 10 and 3 or priorityRank[record.priority]
            if not rank or score > rank then best, rank = index, score end
        end
    end
    return best
end

local function Schedule()
    local deadline
    for _, row in ipairs(live) do
        if not row.exiting and (not deadline or row.record.expires < deadline) then deadline = row.record.expires end
    end
    for _, record in ipairs(queue) do
        if not deadline or record.waitUntil < deadline then deadline = record.waitUntil end
    end
    local now = Now()
    if #queue > 0 and #live < settings.maxRows and nextOrdinary > now and (not deadline or nextOrdinary < deadline) then
        deadline = nextOrdinary
    end
    if deadline == timerDeadline then return end
    CancelTimer()
    if not deadline then return end
    timerDeadline = deadline
    local generation = timerGeneration
    timer = C_Timer.NewTimer(math.max(0.01, deadline - now), function()
        if generation ~= timerGeneration then return end
        timer, timerDeadline = nil, nil
        local now = Now()
        expiring = true
        -- Exit may finish synchronously when the shared tween driver is unavailable.
        for i = #live, 1, -1 do
            local row = live[i]
            if row and not row.exiting and row.record.expires <= now then
                expired = expired + 1
                Exit(row)
            end
        end
        expiring = false
        Refresh()
    end)
end

UpdateBounds = function()
    if not root then return end
    local height = MIN_HEIGHT
    for _, row in ipairs(live) do
        height = math.max(height, math.abs(row.baseY or PAD) + row.height + PAD,
            math.abs(row.goalY or PAD) + row.height + PAD)
    end
    if root:GetHeight() ~= height then
        root:SetHeight(height)
        if registered and YUI.Layout and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(MOVER) end
    end
end

local function Visibility()
    if not root then return end
    local showPreview = enabled and editing and previewVisible ~= false and #live == 0
    if showPreview then preview:Show() else preview:Hide() end
    if #live == 0 then
        StopAnimationOwner()
        if #queue == 0 then nextOrdinary, previewSource = 0, nil end
    end
    local raised = previewSource ~= nil
    if previewRaised ~= raised then
        previewRaised = raised
        root:SetFrameStrata(previewRaised and "TOOLTIP" or "MEDIUM")
    end
    if enabled and (#live > 0 or showPreview) then root:Show() else root:Hide() end
end

local function ActivateRow(row, record, now)
    row.record = record
    record.expires = now + record.duration
    SetStatus(record, "shown")
    ApplyRowColor(row)
    PaintRow(row)
    row.fresh = true
    if record.priority == "important" then
        local index = 1
        while live[index] and live[index].record.priority == "important" do index = index + 1 end
        table.insert(live, index, row)
    else
        nextOrdinary = now + settings.interval
        live[#live + 1] = row
    end
    row:Show()
end

Refresh = function()
    if not initialized then return end
    if updating or expiring then dirty = true; return end
    repeat
        dirty, updating = false, true
        local now = Now()
        PruneQueue(now)
        for _, row in ipairs(pool) do
            if not row.record and #queue > 0 then
                local index = NextIndex(now)
                if not index then break end
                ActivateRow(row, table.remove(queue, index), now)
            end
        end
        local direction = settings.growth == "up" and 1 or -1
        local y = direction * PAD
        for _, row in ipairs(live) do
            if not row.exiting then
                if row.fresh then
                    row.goalY, row.fresh = y, nil
                    Anchor(row, y)
                    Alpha(row, 0)
                    Animate(row, "enter", settings.enterDuration, y, 1, function()
                        UpdateBounds()
                    end)
                elseif row.goalY ~= y then
                    StopMotion(row)
                    row.goalY = y
                    if row.baseY == nil then
                        Anchor(row, y)
                    else
                        Animate(row, "move", settings.moveDuration, y, 1, function()
                            UpdateBounds()
                        end)
                    end
                end
                y = y + direction * (row.height + GAP)
            end
        end
        UpdateBounds()
        Visibility()
        Schedule()
        updating = false
    until not dirty
end

local function Edit(value)
    editing, previewVisible = value, true
    if value then Service:StopPreview() end
    -- All preview content stays still and below the HIGH-strata mover.
    for i = #live, 1, -1 do
        local row = live[i]
        if row.exiting then Release(row) else StopMotion(row, true) end
    end
    StopAnimationOwner()
    Refresh()
end

local function RegisterLayout()
    if registered or not YUI.Layout or not YUI.Layout.RegisterFrame then return end
    local L = YUI.Locale:Get("Core")
    registered = YUI.Layout:RegisterFrame(MOVER, {
        frame = root, title = L["info_output.name"], category = "core", editModeCategory = "information",
        movable = true, snap = true, exactMoverBounds = true, anchorTargets = { "UIParent" },
        defaultPlacement = defaultPlacement,
        isEnabled = function() return enabled == true end,
        onEnterEditMode = function() Edit(true) end,
        onExitEditMode = function() Edit(false) end,
        onEditModeFilterChanged = function(_, visible) previewVisible = visible; Visibility() end,
        openPluginSettings = function()
            if Service.OpenSettings then return Service:OpenSettings() end
            return false
        end,
    }) ~= false
    if registered and YUI.Layout.IsEditing and YUI.Layout:IsEditing() and YUI.Layout.RefreshEditSessionEntry then
        YUI.Layout:RefreshEditSessionEntry(MOVER)
    end
end

function Service:Initialize()
    local wasEnabled = enabled
    if not initialized then
        if not YUI.GUI2 or not YUI.Locale or not YUI.API or not YUI.API.Security then return false, "missing-core-services" end
        if not C_Timer or type(C_Timer.NewTimer) ~= "function" or not GetTime and not (YUI.API.Combat and YUI.API.Combat.GetTime) then
            return false, "missing-clock"
        end
        if YUI.DB and YUI.DB.IsReady and not YUI.DB:IsReady() then return false, "not-ready" end
        local GUI, L = YUI.GUI2, YUI.Locale:Get("Core")
        LoadSettings(GetProfile())
        root = GUI:CreateFrame(UIParent, { name = "YUIInfoOutput", width = settings.width, height = MIN_HEIGHT,
            strata = "MEDIUM", mouse = false, clamped = true, hidden = true })
        local anchor, offset = defaultPlacement.anchor, defaultPlacement.offset
        root:SetPoint(anchor.point, UIParent, anchor.relativePoint, offset.x, offset.y)
        preview = GUI:CreateText(root, L["info_output.preview"], settings.fontSize, "color.text.secondary", "LEFT")
        preview:SetWordWrap(true)
        preview:Hide()
        for i = 1, POOL_SIZE do
            local row = GUI:CreateFrame(root, { width = settings.width - PAD * 2, height = MIN_ROW, mouse = false, hidden = true })
            row.text = GUI:CreateText(row, "", settings.fontSize, "color.text.primary", "LEFT")
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.text:SetWordWrap(true)
            row.text:SetNonSpaceWrap(true)
            pool[i] = row
        end
        ApplyAppearance()
        initialized = true
    end
    enabled = true
    RegisterLayout()
    if not wasEnabled and registered and YUI.Layout and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(MOVER) end
    Visibility()
    return true
end

local function Reject(reason)
    rejected = rejected + 1
    return false, reason
end

local function ValidKey(key)
    return not Secret(key) and (key == nil or type(key) == "string" and key ~= "" and #key <= 256 or Number(key))
end

local function RememberKey(owner, key, id)
    if key == nil then return end
    if #keyOrder == KEY_LIMIT then
        local old = table.remove(keyOrder, 1)
        local bucket = keys[old.owner]
        bucket[old.key] = nil
        if next(bucket) == nil then keys[old.owner] = nil end
    end
    if not keys[owner] then keys[owner] = {} end
    keys[owner][key] = id
    keyOrder[#keyOrder + 1] = { owner = owner, key = key }
end

local function Remember(record, status)
    if rawequal(record.owner, previewOwner) then return end
    if #history == RECENT_LIMIT then table.remove(history, 1) end
    local entry = { text = record.text, time = record.time, priority = record.priority, status = status, count = 1 }
    history[#history + 1] = entry
    record.history = entry
end

local function FindMerge(owner, mergeKey, text, icon, iconPosition, priority, now)
    local function Matches(record)
        return rawequal(record.owner, owner) and record.mergeKey == mergeKey and record.text == text
            and record.icon == icon and record.iconPosition == iconPosition
            and record.priority == priority and now - record.time <= 2
    end
    for _, row in ipairs(live) do
        if not row.exiting and Matches(row.record) then return row.record, row end
    end
    for _, record in ipairs(queue) do if Matches(record) then return record end end
end

local function MakeRoom(priority)
    if #queue < QUEUE_LIMIT then return true end
    local discard, rank = nil, priorityRank[priority]
    for index, record in ipairs(queue) do
        local candidate = priorityRank[record.priority]
        if candidate < rank then discard, rank = index, candidate end
        if rank == 1 and discard then break end
    end
    if not discard then return false end
    SetStatus(table.remove(queue, discard), "overflow")
    overflow = overflow + 1
    return true
end

function Service:Push(owner, text, opts)
    if not Owner(owner) then return Reject("invalid-owner") end
    if Secret(text) or type(text) ~= "string" or #text > 1024 or not text:find("%S") then return Reject("invalid-text") end
    if Secret(opts) or opts ~= nil and not PlainTable(opts) then return Reject("invalid-options") end
    local key = opts and rawget(opts, "key")
    if not ValidKey(key) then return Reject("invalid-key") end
    local mergeKey = opts and rawget(opts, "mergeKey")
    if not ValidKey(mergeKey) then return Reject("invalid-merge-key") end
    local icon = opts and rawget(opts, "icon")
    if not (Number(icon) and icon > 0 and icon <= 4294967295 and icon % 1 == 0)
        and not (not Secret(icon) and type(icon) == "string" and #icon <= 260
            and icon:lower():match("^interface[/\\]") and not icon:find("[:|%c]")) then
        icon = nil
    end
    local iconBefore = opts and rawget(opts, "iconBefore")
    local iconPosition
    if not Secret(iconBefore) and type(iconBefore) == "string" and #iconBefore > 0 and #iconBefore <= #text then
        iconPosition = text:find(iconBefore, 1, true)
    end
    local priority = opts and rawget(opts, "priority")
    if Secret(priority) or priority ~= nil and (type(priority) ~= "string" or not priorityRank[priority]) then
        return Reject("invalid-priority")
    end
    priority = priority or "normal"
    local duration = opts and rawget(opts, "duration")
    if Secret(duration) or duration ~= nil and not Number(duration) then return Reject("invalid-duration") end
    local inputColor = opts and rawget(opts, "color")
    local color
    if Secret(inputColor) then return Reject("invalid-color") end
    if inputColor ~= nil then
        if not PlainTable(inputColor) then return Reject("invalid-color") end
        color = {}
        for i, field in ipairs({ "r", "g", "b", "a" }) do
            local value = rawget(inputColor, i)
            if Secret(value) then return Reject("invalid-color") end
            if value == nil then value = rawget(inputColor, field) end
            if Secret(value) then return Reject("invalid-color") end
            if i == 4 and value == nil then value = 1 end
            if not Number(value) then return Reject("invalid-color") end
            color[i] = math.max(0, math.min(1, value))
        end
    end
    if initialized and not enabled then return Reject("disabled") end
    if not initialized then
        local ok, reason = self:Initialize()
        if not ok then return Reject(reason) end
    end
    duration = math.max(0.5, math.min(30, duration or settings.duration))
    if key ~= nil and keys[owner] and keys[owner][key] then
        duplicates = duplicates + 1
        return Reject("duplicate")
    end
    if previewSource and not rawequal(owner, previewOwner) then self:StopPreview() end
    local now = Now()
    PruneQueue(now)
    if mergeKey ~= nil then
        local record, row = FindMerge(owner, mergeKey, text, icon, iconPosition, priority, now)
        if record then
            record.count = record.count + 1
            if record.history then record.history.count = record.count end
            RememberKey(owner, key, record.id)
            accepted, merged = accepted + 1, merged + 1
            if row then PaintRow(row) end
            Refresh()
            return true, record.id
        end
    end
    local record = { owner = owner, text = text, icon = icon, iconPosition = iconPosition, duration = duration, color = color, priority = priority,
        time = now, waitUntil = now + maxWait[priority], mergeKey = mergeKey, count = 1 }
    if (priority ~= "important" or #live > settings.maxRows) and not MakeRoom(priority) then
        overflow = overflow + 1
        Remember(record, "overflow")
        Refresh()
        return Reject("queue-full")
    end
    sequence, accepted = sequence + 1, accepted + 1
    record.id = sequence
    queue[#queue + 1] = record
    Remember(record, "queued")
    RememberKey(owner, key, sequence)
    Refresh()
    return true, sequence
end

function Service:ClearOwner(owner)
    if not Owner(owner) then return 0, "invalid-owner" end
    local removed = 0
    for i = #queue, 1, -1 do
        if rawequal(queue[i].owner, owner) then
            SetStatus(table.remove(queue, i), "cancelled")
            removed = removed + 1
        end
    end
    for i = #live, 1, -1 do
        if rawequal(live[i].record.owner, owner) then Release(live[i]); removed = removed + 1 end
    end
    for i = #keyOrder, 1, -1 do if rawequal(keyOrder[i].owner, owner) then table.remove(keyOrder, i) end end
    keys[owner] = nil
    Refresh()
    return removed
end

function Service:Clear()
    local removed = #queue + #live
    CancelTimer()
    for i = #live, 1, -1 do Release(live[i]) end
    StopAnimationOwner()
    queue, keyOrder, keys, history = {}, {}, {}, {}
    nextOrdinary, previewSource = 0, nil
    UpdateBounds()
    Visibility()
    return removed
end

function Service:GetRecent()
    local result = {}
    for index = #history, 1, -1 do
        local entry = history[index]
        result[#result + 1] = { text = entry.text, time = entry.time, status = entry.status,
            priority = entry.priority, count = entry.count }
    end
    return result
end

function Service:StopPreview(source)
    if not previewSource or Secret(source) or source ~= nil and not rawequal(source, previewSource) then return end
    previewSource = nil
    self:ClearOwner(previewOwner)
end

local function BeginPreview(self, source)
    if editing or (YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()) then return false, "editing" end
    if initialized and not enabled then return false, "disabled" end
    if not initialized then
        local ok, reason = self:Initialize()
        if not ok then return false, reason end
    end
    self:StopPreview()
    if #live > 0 or #queue > 0 then return false, "busy" end
    previewSource = source
    return true
end

function Service:PlayPreviewMessage(source, text, opts)
    if not Owner(source) then return false, "invalid-owner" end
    local starting = not rawequal(source, previewSource)
    if starting then
        local ok, reason = BeginPreview(self, source)
        if not ok then return false, reason end
    end
    local accepted, result = self:Push(previewOwner, text, opts)
    if starting and not accepted then self:StopPreview(source) end
    return accepted, result
end

function Service:PlayPreview(mode)
    if Secret(mode) then return false, "invalid-mode" end
    mode = mode or "normal"
    if mode ~= "normal" and mode ~= "burst" and mode ~= "priority" then return false, "invalid-mode" end
    local ok, reason = BeginPreview(self, previewOwner)
    if not ok then return false, reason end
    local L = YUI.Locale:Get("Core")
    local count = mode == "priority" and settings.maxRows + 2 or mode == "burst" and 12 or 3
    for index = 1, count do
        local duration = math.min(settings.duration, 3) + (index % 3) * .5
        if mode == "normal" then duration = settings.duration - (3 - index) * .6 end
        self:Push(previewOwner, L["info_output.preview_sample"]:format(index), { duration = duration, icon = index == 1 and 134400 or nil })
    end
    if mode == "priority" then
        self:Push(previewOwner, L["info_output.preview_important"], { priority = "important", duration = math.min(settings.duration, 5) })
    elseif mode == "burst" then
        for _ = 1, 4 do
            self:Push(previewOwner, L["info_output.preview_sample"]:format(count + 1), { mergeKey = "burst", duration = 3 })
        end
    end
    return true
end

function Service:GetStats()
    local visible, exiting, animations = 0, 0, 0
    for _, row in ipairs(live) do
        if row.exiting then exiting = exiting + 1 else visible = visible + 1 end
        if row.motion then animations = animations + 1 end
    end
    return { apiVersion = 1, initialized = initialized == true, enabled = enabled == true,
        visible = visible, exiting = exiting, queued = #queue, messages = #queue + #live,
        pool = #pool, capacity = settings.maxRows, queueLimit = QUEUE_LIMIT, keyCache = #keyOrder, keyLimit = KEY_LIMIT,
        timerPending = timer and 1 or 0, animations = animations, editing = editing == true,
        accepted = accepted, rejected = rejected, duplicates = duplicates, expired = expired,
        merged = merged, overflow = overflow, stale = stale, recent = #history, preview = previewSource ~= nil }
end

local fontStyle = YUI.GUI2 and YUI.GUI2.FontStyle
if fontStyle and fontStyle.RegisterConfig then
    fontStyle:RegisterConfig(MODULE, {
        label = function() return YUI.Locale:Get("Core")["info_output.name"] end,
        get = function() EnsureSettings(); return settings, GetProfile() end,
        refresh = function()
            settings.fontColor = NormalizeSetting("fontColor", settings.fontColor) or defaults.fontColor
            SaveSettings()
            RefreshAppearance()
            Refresh()
        end,
        targets = { {
            id = "text", label = function() return YUI.Locale:Get("Core")["info_output.field.textStyle"] end,
            defaults = defaults, minSize = ranges.fontSize[1], maxSize = ranges.fontSize[2],
            fields = { font = "font", size = "fontSize", outline = "fontOutline",
                shadow = "fontShadow", monochrome = "fontMonochrome", color = "fontColor" },
            fontPath = function(value)
                return fontStyle.FontPath(value, YUI.GUI2:GetFont("font.family.body"))
            end,
            colorModes = { state = true }, dynamicColor = true, hasAlpha = true,
            moduleColor = "color.text.primary",
        } },
    })
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({ id = MODULE, name = MODULE, owner = Service, scope = "core", defaultEnabled = true,
        dependencies = { "core.db", "core.locale", "core.event", "gui" },
        getEnabled = function() return true end,
        OnEnable = function() Service:Initialize() end,
        OnDisable = function()
            enabled, editing = false, false
            Service:Clear()
            if registered and YUI.Layout and YUI.Layout.RefreshFrame then YUI.Layout:RefreshFrame(MOVER) end
        end,
        OnProfileChanged = function()
            Service:Clear()
            LoadSettings(GetProfile())
            RefreshAppearance()
        end,
    })
end
