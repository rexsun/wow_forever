local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not Native or YUI.IsForever ~= true then return end

local Security = YUI.API and YUI.API.Security
local Event = YUI.Event
if not Security or not Event then return end

local SOCIAL_ADDON = "Blizzard_SocialUI"
local NATIVE_HEIGHT = 70
local GAP = 5
local owner = {}
local options = { moduleId = Native.MODULE_ID, traceName = "NativeInterface:social-list" }
local pages = {
    { geometry = { "PresenceHolder", "TextHolder", "FriendName", "Location" }, hiddenText = { "Name", "Level", "Class", "Location" } },
    { geometry = { "PresenceHolder", "TextHolder", "Name", "Class" }, recent = true,
        hiddenText = { "Name", "Level", "Class", "Location", "MostRecentInteraction" } },
}
local visuals = setmetatable({}, { __mode = "k" })
local wanted, loadListener, combatListener, enterListener, recoveryTimer
local externallyControlled
local layoutFailures = 0
local hideHookRoot, waitingForClose
local sortWanted
local fontSize, requestedFontSize = 14, 14
local Reconcile

local function Readable(value, valueType)
    return not Security.IsSecretValue(value) and type(value) == valueType
end

local function ReadableTable(value)
    return Readable(value, "table") and Security.CanAccessTable(value) ~= false
end

local function CanEdit(frame)
    if not ReadableTable(frame) or type(frame.IsForbidden) ~= "function" or type(frame.IsProtected) ~= "function" then return false end
    local forbidden = frame:IsForbidden()
    if not Readable(forbidden, "boolean") or forbidden then return false end
    local protected = frame:IsProtected()
    if not Readable(protected, "boolean") or protected then return false end
    if type(frame.HasSecretValues) == "function" then
        local hasSecretValues = frame:HasSecretValues()
        if not Readable(hasSecretValues, "boolean") or hasSecretValues then return false end
    end
    return true
end

local function CharacterForData(page, data)
    if not ReadableTable(data) then return end
    if page.recent then
        if not ReadableTable(data.characterData) or not ReadableTable(data.stateData) then return end
        if Readable(data.stateData.isOnline, "boolean") then return data.characterData, data.stateData.isOnline end
    else
        if not ReadableTable(data.accountInfo) or not ReadableTable(data.accountInfo.gameAccountInfo) then return end
        local game = data.accountInfo.gameAccountInfo
        if Readable(game.isOnline, "boolean") then return game, game.isOnline end
    end
end

local function Anchor(region, relative, offset)
    region:ClearAllPoints()
    region:SetPoint("LEFT", relative, "RIGHT", offset, 0)
end

local function CenterText(text, holder)
    text:ClearAllPoints()
    text:SetPoint("LEFT", holder, "LEFT", 0, 0)
end

-- Read only display strings which the font API exposes as ordinary Lua strings.
-- FriendName is intentionally never read: its native kstring stays on that control.
local function NativeTextParts(region)
    local ok, text = pcall(region.GetText, region)
    if not ok or not Readable(text, "string") or text == "" then return end
    local color, content = text:match("^(|c%x%x%x%x%x%x%x%x)(.*)|r$")
    return content or text, color
end

local function ColorByte(value)
    if Readable(value, "number") and value >= 0 and value <= 1 then return math.floor(value * 255 + 0.5) end
end

local function LevelColor(level, online)
    if not online then return "|cff808080" end
    local getColor = YUI.WOW_API and YUI.WOW_API.GetQuestDifficultyColor
    if type(getColor) == "function" then
        local ok, color = pcall(getColor, level)
        if ok and ReadableTable(color) then
            local r, g, b = ColorByte(color.r), ColorByte(color.g), ColorByte(color.b)
            if r and g and b then return ("|cff%02x%02x%02x"):format(r, g, b) end
        end
    end
    return "|cffffffff"
end

local function CharacterText(frame, level, online)
    local name = NativeTextParts(frame.Name)
    if not name or name == "" then return end
    local _, classColor = NativeTextParts(frame.Class)
    local muted = "|cff808080"
    local levelText = Readable(level, "number") and level > 0 and LevelColor(level, online) .. level .. "|r " or ""
    local nameColor = online and (classColor or "|cffffffff") or muted
    return muted .. "(|r" .. levelText .. nameColor .. name .. "|r" .. muted .. ")|r"
end

local function Width(value)
    if Readable(value, "number") and value >= 0 then return value end
end

local function FitLabel(label, text, maxWidth)
    if not text or maxWidth < 12 then label:Hide(); return 0 end
    label:SetText(text)
    local width = math.min(Width(label:GetUnboundedStringWidth()) or maxWidth, maxWidth)
    label:SetWidth(math.max(width, 1))
    label:Show()
    return width
end

local function LayoutFriend(frame, label, game, online, width, stateWidth)
    local title, state = frame.FriendName, frame.StateDisplay
    local suffix
    if online and Readable(game.clientProgram, "string") and game.clientProgram == BNET_CLIENT_WOW then
        suffix = CharacterText(frame, game.characterLevel, true)
    end
    local showLocation = not online or (Readable(game.clientProgram, "string") and game.clientProgram == BNET_CLIENT_WOW)
    local hasDetailRoom = (suffix or showLocation) and width >= 72
    CenterText(title, frame.TextHolder)
    -- Let the region measure its native kstring at the body size.
    title:SetWidth(0)
    local titleWidth = math.max(1, math.min(Width(title:GetWidth()) or width, hasDetailRoom and width * 0.62 or width))
    title:SetWidth(titleWidth)
    local relative = stateWidth > 0 and state or title
    local remaining = width - titleWidth - GAP
    Anchor(label, relative, GAP)
    local zoneSpace = online and showLocation and remaining >= 96 and math.min(60, remaining * 0.32) or 0
    local detailWidth = FitLabel(label, suffix, remaining - zoneSpace)
    if showLocation and remaining - detailWidth >= 12 + GAP then
        Anchor(frame.Location, detailWidth > 0 and label or relative, GAP)
        frame.Location:SetPoint("RIGHT", frame.TextHolder)
        return "Location"
    end
end

local function LayoutRecent(frame, label, character, online, width)
    local description, color = NativeTextParts(frame.MostRecentInteraction)
    local text = CharacterText(frame, character.level, online)
    if text and description and description ~= "" then
        text = (color or "|cff808080") .. "【" .. description .. "】|r " .. text
    end
    CenterText(label, frame.TextHolder)
    local labelWidth = FitLabel(label, text, width - 1)
    if labelWidth > 0 then
        Anchor(frame.Class, label, 0)
        frame.Class:SetPoint("RIGHT", label, "RIGHT", 1, 0)
        return
    end

    -- If a value is unavailable, keep the original name region and its text.
    local name = frame.Name
    CenterText(name, frame.TextHolder)
    local nameWidth = Width(name:GetWidth()) or width
    name:SetWidth(math.max(1, math.min(nameWidth, width - 1)))
    Anchor(frame.Class, name, 0)
    frame.Class:SetPoint("RIGHT", name, "RIGHT", 1, 0)
    return "Name"
end

local function ReadFont(region)
    local object = region:GetFontObject()
    local path, size, flags = region:GetFont()
    if Security.IsSecretValue(object) or not Readable(path, "string") or not Readable(size, "number")
        or Security.IsSecretValue(flags) then return end
    return path, size, flags, object
end

local function ApplyRowFont(region, saved, path)
    local current, size, flags, object = ReadFont(region)
    if not current then return end
    if current ~= saved.appliedPath or size ~= saved.appliedSize or flags ~= saved.appliedFlags or object ~= saved.appliedObject then
        saved.path, saved.size, saved.flags, saved.object = current, size, flags, object
        saved.appliedPath = nil
    end
    if current == path and size == fontSize and flags == "OUTLINE" then return end
    region:SetFont(path, fontSize, "OUTLINE")
    saved.appliedPath, saved.appliedSize, saved.appliedFlags, saved.appliedObject = ReadFont(region)
end

local function RestoreFont(region, saved)
    if not saved.appliedPath then return end
    local path, size, flags, object = ReadFont(region)
    local owned = path == saved.appliedPath and size == saved.appliedSize and flags == saved.appliedFlags
        and object == saved.appliedObject
    saved.appliedPath = nil
    if not owned then return end
    if saved.object then
        region:SetFontObject(saved.object)
        path, size, flags = ReadFont(region)
        if path == saved.path and size == saved.size and flags == saved.flags then return end
    end
    region:SetFont(saved.path, saved.size, saved.flags)
end

local function ApplyAlpha(frame, visual, key, factor)
    local region = frame[key]
    local current = region and Width(region:GetAlpha())
    if not current then return false end
    if current ~= visual.appliedAlpha[key] then
        visual.alpha[key], visual.appliedAlpha[key] = current, nil
    end
    local alpha = visual.alpha[key] * factor
    if current ~= alpha then
        region:SetAlpha(alpha)
        visual.appliedAlpha[key] = Width(region:GetAlpha())
    end
    return true
end

-- Save only the visual anchors we move. Restoring them directly avoids entering
-- the native card layout/initialization code from an addon callback.
local function SaveGeometry(region, points)
    local count = region:GetNumPoints()
    if not Readable(count, "number") then error("restricted social row anchor count") end
    for index = 1, count do
        local point = points[index] or {}
        local anchor, relative, relativeAnchor, x, y = region:GetPoint(index)
        if Security.IsSecretValue(anchor) or Security.IsSecretValue(relative) or Security.IsSecretValue(relativeAnchor)
            or Security.IsSecretValue(x) or Security.IsSecretValue(y) then error("restricted social row anchor") end
        point[1], point[2], point[3], point[4], point[5] = anchor, relative, relativeAnchor, x, y
        points[index] = point
    end
    points.count = count
end

local function SameGeometry(region, points)
    if not points or not points.count then return false end
    local count = region:GetNumPoints()
    if not Readable(count, "number") or count ~= points.count then return false end
    for index = 1, points.count do
        local anchor, relative, relativeAnchor, x, y = region:GetPoint(index)
        local point = points[index]
        if Security.IsSecretValue(anchor) or Security.IsSecretValue(relative) or Security.IsSecretValue(relativeAnchor)
            or Security.IsSecretValue(x) or Security.IsSecretValue(y)
            or anchor ~= point[1] or relative ~= point[2] or relativeAnchor ~= point[3]
            or x ~= point[4] or y ~= point[5] then return false end
    end
    return true
end

-- Blizzard or a skin may move a visible row between layout passes, including
-- between two slider values. Take the current baseline before either pass.
local function CaptureRowGeometry(page, frame, visual)
    local title = page.recent and frame.Name or frame.FriendName
    local width = Width(title:GetWidth())
    if not width then return false end
    if not visual.active or width ~= visual.appliedWidth then visual.titleWidth = width end
    for index, key in ipairs(page.geometry) do
        local points = visual.geometry[index] or {}
        if not visual.active or not SameGeometry(frame[key], visual.applied[index]) then
            SaveGeometry(frame[key], points)
        end
        visual.geometry[index] = points
    end
    visual.active = true
    visual.applying = true
    return true
end

local function RememberAppliedGeometry(page, frame, visual)
    for index, key in ipairs(page.geometry) do
        local points = visual.applied[index] or {}
        if SameGeometry(frame[key], visual.geometry[index]) then
            points.count = nil
        else
            SaveGeometry(frame[key], points)
        end
        visual.applied[index] = points
    end
    visual.appliedWidth = Width((page.recent and frame.Name or frame.FriendName):GetWidth())
    visual.applying = false
end

local function RestoreRow(page, frame, visual)
    if not (visual and visual.active and CanEdit(frame)) then return end
    visual.label:Hide()
    for key, applied in pairs(visual.appliedAlpha) do
        if Width(frame[key]:GetAlpha()) == applied then frame[key]:SetAlpha(visual.alpha[key]) end
        visual.appliedAlpha[key] = nil
    end
    local title = page.recent and frame.Name or frame.FriendName
    RestoreFont(title, visual.titleFont)
    if not page.recent then RestoreFont(frame.Location, visual.locationFont) end
    local width = Width(title:GetWidth())
    if width and width ~= visual.titleWidth and (visual.applying or width == visual.appliedWidth) then
        title:SetWidth(visual.titleWidth)
    end
    for index, key in ipairs(page.geometry) do
        local region, points = frame[key], visual.geometry[index]
        if (visual.applying and not SameGeometry(region, points)) or SameGeometry(region, visual.applied[index]) then
            region:ClearAllPoints()
            for i = 1, points.count do
                local point = points[i]
                region:SetPoint(point[1], point[2], point[3], point[4], point[5])
            end
        end
    end
    visual.active = false
end

local function CardMatches(page, frame)
    if not CanEdit(frame) then return false end
    local layout = frame.LayoutScaledContent
    return Readable(layout, "function") and layout == page.cardMixin.LayoutScaledContent
        and CanEdit(frame.TextHolder) and CanEdit(frame.PresenceHolder) and CanEdit(frame.StateDisplay) and CanEdit(frame.PartyButton)
        and (page.recent or type(frame.GetBestRightAnchorForTextHolder) == "function")
        and type(frame.CreateFontString) == "function" and (page.recent or frame.FriendName ~= nil)
end

local function LayoutRowText(page, frame, visual, character, online)
    local holderWidth = Width(frame.TextHolder:GetWidth())
    local stateWidth = Width(frame.StateDisplay:GetWidth())
    if not holderWidth or not stateWidth or holderWidth <= stateWidth + 2 * GAP then return false end
    local width = holderWidth - stateWidth - (stateWidth > 0 and GAP or 0)

    local visibleText
    -- Match the Micro Menu friends list's face and outline while retaining native text regions.
    local path = GameFontHighlightSmall:GetFont()
    visual.label:SetFont(path, fontSize, "OUTLINE")
    if page.recent then
        ApplyRowFont(frame.Name, visual.titleFont, path)
        visibleText = LayoutRecent(frame, visual.label, character, online, width)
    else
        ApplyRowFont(frame.FriendName, visual.titleFont, path)
        ApplyRowFont(frame.Location, visual.locationFont, path)
        visibleText = LayoutFriend(frame, visual.label, character, online, width, stateWidth)
    end
    for _, key in ipairs(page.hiddenText) do
        if not ApplyAlpha(frame, visual, key, key == visibleText and 1 or 0) then return false end
    end
    return true
end

local function LayoutRow(page, frame)
    if not ReadableTable(frame) then return false end
    local visual = visuals[frame]
    if not CardMatches(page, frame) then return end
    local height = Width(frame:GetHeight())
    local character, online = CharacterForData(page, frame.elementData)
    -- The native ScrollBox owns extent, scroll offsets and the complete hit area.
    -- Leave expanded accessibility layouts alone, allowing for UI scale rounding.
    if not character or not height or height <= 0 or height > NATIVE_HEIGHT + 0.01 then
        RestoreRow(page, frame, visual)
        return
    end

    if not visual then
        local label = frame:CreateFontString(nil, "ARTWORK", "UserScaledFontBody")
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        label:SetMaxLines(1)
        label:SetWordWrap(false)
        visual = { label = label, alpha = {}, appliedAlpha = {}, geometry = {}, applied = {}, titleFont = {}, locationFont = {} }
        visuals[frame] = visual
    end
    if not CaptureRowGeometry(page, frame, visual) then return false end
    local presence, holder = frame.PresenceHolder, frame.TextHolder
    presence:ClearAllPoints()
    presence:SetPoint("CENTER", frame, "LEFT", 7, 0)
    local right = page.recent and frame.PartyButton or frame:GetBestRightAnchorForTextHolder()
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, 0)
    holder:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    holder:SetPoint("RIGHT", right, "LEFT", -4, 0)
    if not ApplyAlpha(frame, visual, "Background", 0.25) then return false end
    local result = LayoutRowText(page, frame, visual, character, online)
    RememberAppliedGeometry(page, frame, visual)
    return result
end

local function OnRecovery()
    recoveryTimer = nil
    Reconcile()
end

local function FlagFailure(page, reason)
    if page.failed then return end
    layoutFailures = layoutFailures + 1
    page.failed = true
    page.reason = reason
    page.layerVisible = nil
    -- The view is locked inside initialization. Roll it back after the callback unwinds.
    if not recoveryTimer then recoveryTimer = C_Timer.NewTimer(0, OnRecovery) end
end

local function OnInitialized(page, frame)
    if externallyControlled then return end
    local ok, result = pcall(LayoutRow, page, frame)
    if not ok or result == false then FlagFailure(page, "row-layout") end
end

local function OnReleased(page, frame)
    if Security.IsSecretValue(frame) then return end
    if (externallyControlled or not wanted) and Security.InCombatLockdown() then
        local visual = visuals[frame]
        if visual and visual.active then
            page.deferredRestore = page.deferredRestore or {}
            page.deferredRestore[frame] = visual
        end
        return
    end
    if not pcall(RestoreRow, page, frame, visuals[frame]) then FlagFailure(page, "row-release") end
end

-- Observe notifications after native dispatch. The two boxes keep their native
-- callback registries, factories, extent caches and button initializers.
local observedBoxes = setmetatable({}, { __mode = "k" })

local function CanSort(page)
    return sortWanted and not page.recent
end

local function PageEnabled(page)
    return (wanted and not page.failed) or CanSort(page)
end

local function HideCompactView(page)
    if page.layer then page.layer:Hide() end
    page.layerVisible = nil
end

local function RefreshCompactView(page, provider, retain)
    local box = page.box
    local compact, sorted = wanted and not page.failed, CanSort(page)
    if not (compact or sorted) or Security.InCombatLockdown() or not box or not box:IsVisible() then return end
    if not Native.CreateSocialCompactView or not box.GetDataProvider then
        page.reason = "view-unavailable"
        return
    end
    if Security.IsSecretValue(provider) then
        page.reason = "provider-restricted"
        HideCompactView(page)
        return
    end
    if provider == nil then provider = box:GetDataProvider() end
    if not ReadableTable(provider) then
        page.reason = Readable(provider, "nil") and "no-provider" or "provider-restricted"
        HideCompactView(page)
        return
    end
    page.reason = nil
    if not page.layer then
        page.layer = Native:CreateSocialCompactView(page.pane, page.recent == true,
            function(frame)
                OnInitialized(page, frame)
                local visual = visuals[frame]
                return not page.failed and visual ~= nil and visual.active == true
            end,
            function(frame) OnReleased(page, frame) end)
    end
    if page.layer then
        page.layerVisible = page.layer:Refresh(provider, retain, compact, sorted)
    else
        page.reason = "view-create"
    end
end

local function OnNativeDataChanged(box, provider, retain)
    local page = observedBoxes[box]
    if not page or page.box ~= box then return end
    if Security.InCombatLockdown() then
        if not Security.IsSecretValue(retain) and not retain then page.resumeScroll = nil end
        return
    end
    RefreshCompactView(page, provider, retain)
end

local function OnBoxShow(box)
    local page = observedBoxes[box]
    if page and page.box == box then RefreshCompactView(page) end
end

local function OnBoxHide(box)
    local page = observedBoxes[box]
    if page and page.box == box then
        page.resumeScroll = nil
        HideCompactView(page)
    end
end

local function AfterBoxEvent(box, event, frame)
    local page = observedBoxes[box]
    if not page or page.box ~= box then return end
    if event == box.Event.OnReleasedFrame then
        OnReleased(page, frame)
    elseif event == box.Event.OnInitializedFrame and wanted and not page.failed then
        page.nativeStyled = true
        OnInitialized(page, frame)
    end
end

local function Attach(page, pane, cardMixin)
    if page.box or not PageEnabled(page) or not CanEdit(pane) or not CanEdit(pane.ScrollBox) then return end
    local box = pane.ScrollBox
    if not C_Timer or type(C_Timer.NewTimer) ~= "function" or not cardMixin
        or type(cardMixin.LayoutScaledContent) ~= "function" or type(box.GetFrames) ~= "function"
        or type(box.TriggerEvent) ~= "function" or type(hooksecurefunc) ~= "function"
        or not box.Event or not box.Event.OnInitializedFrame or not box.Event.OnReleasedFrame then return end
    if not observedBoxes[box] then
        hooksecurefunc(box, "TriggerEvent", AfterBoxEvent)
        if box.SetDataProvider and box.HookScript then
            hooksecurefunc(box, "SetDataProvider", OnNativeDataChanged)
            box:HookScript("OnShow", OnBoxShow)
            box:HookScript("OnHide", OnBoxHide)
        end
        observedBoxes[box] = page
    end
    if page.pane ~= pane then page.layer = nil end
    page.pane, page.box, page.cardMixin = pane, box, cardMixin
end

local function RestoreNativeRows(page, box)
    if page.nativeStyled and CanEdit(box) then
        for _, frame in ipairs(box:GetFrames()) do
            RestoreRow(page, frame, visuals[frame])
        end
        page.nativeStyled = nil
    end
end

local function Detach(page)
    local box = page.box
    if not box then return end
    HideCompactView(page)
    page.box, page.cardMixin = nil, nil
    RestoreNativeRows(page, box)
end

local function AfterCombat()
    combatListener = nil
    Reconcile()
end

local function OnEnterCombat()
    for _, page in ipairs(pages) do
        page.resumeScroll = page.layerVisible
        HideCompactView(page)
    end
    if not combatListener then
        combatListener = Event:Once("PLAYER_REGEN_ENABLED", AfterCombat, owner, options)
    end
end

local function OnAddonLoaded(_, name)
    if Readable(name, "string") and name == SOCIAL_ADDON then Reconcile() end
end

local function RefreshVisibleRowText(page, frame)
    local visual = visuals[frame]
    if not visual or not visual.active or not CardMatches(page, frame) or not frame:IsVisible() then return end
    local character, online = CharacterForData(page, frame.elementData)
    if character then
        if not CaptureRowGeometry(page, frame, visual) then return false end
        local result = LayoutRowText(page, frame, visual, character, online)
        RememberAppliedGeometry(page, frame, visual)
        return result
    end
end

local function OnSocialHide()
    if waitingForClose then Reconcile() end
end

local function RefreshFont(page, box)
    if not box or not box:IsVisible() then return end
    for _, frame in ipairs(box:GetFrames()) do
        local ok, result = pcall(RefreshVisibleRowText, page, frame)
        if not ok or result == false then FlagFailure(page, "row-font"); break end
    end
end

Reconcile = function()
    local root = _G.SocialUIFrame
    local enabled = wanted or sortWanted
    if loadListener and (not enabled or root) then
        Event:Off(loadListener)
        loadListener = nil
    end
    if enabled and not root and not loadListener then
        loadListener = Event:On("ADDON_LOADED", OnAddonLoaded, owner, options)
    end
    if Security.InCombatLockdown() then
        local needsRecovery = enabled or pages[1].box or pages[2].box
        if needsRecovery and not combatListener then
            combatListener = Event:Once("PLAYER_REGEN_ENABLED", AfterCombat, owner, options)
        elseif not needsRecovery and combatListener then
            Event:Off(combatListener)
            combatListener = nil
        end
        return
    end

    if combatListener then Event:Off(combatListener); combatListener = nil end
    for _, page in ipairs(pages) do
        if page.deferredRestore then
            for frame, visual in pairs(page.deferredRestore) do RestoreRow(page, frame, visual) end
            page.deferredRestore = nil
        end
    end
    if recoveryTimer then recoveryTimer:Cancel(); recoveryTimer = nil end
    if enabled and CanEdit(root) and not enterListener then
        enterListener = Event:On("PLAYER_REGEN_DISABLED", OnEnterCombat, owner, options)
    elseif not enabled and enterListener then
        Event:Off(enterListener)
        enterListener = nil
    end
    if externallyControlled then
        waitingForClose = nil
        for _, page in ipairs(pages) do
            Detach(page)
            page.failed, page.resumeScroll = nil, nil
        end
        return
    end
    local friends = pages[1]
    if sortWanted and (not wanted or friends.failed) then RestoreNativeRows(friends, friends.box) end
    if CanEdit(root) and root:IsVisible() then
        -- Settings and combat recovery can both enable an already open pane.
        -- Attach before reading its current provider; OnShow has already run.
        if enabled then Attach(pages[1], root.FriendsList, _G.FriendsListSocialCardMixin) end
        if wanted then Attach(pages[2], root.RecentAlliesList, _G.RecentAlliesSocialCardMixin) end
        if fontSize ~= requestedFontSize then
            fontSize = requestedFontSize
            if wanted then
                for _, page in ipairs(pages) do
                    local box = page.box
                    if not page.failed and CanEdit(box) and box:IsVisible() then
                        RefreshFont(page, box)
                        if page.layerVisible then RefreshFont(page, page.layer.ScrollBox) end
                    end
                end
            end
        end
        for _, page in ipairs(pages) do
            if not PageEnabled(page) then
                HideCompactView(page)
            elseif not page.layerVisible then
                RefreshCompactView(page, nil, page.resumeScroll)
            end
            page.resumeScroll = nil
        end
        waitingForClose = PageEnabled(pages[1]) ~= (pages[1].box ~= nil)
            or PageEnabled(pages[2]) ~= (pages[2].box ~= nil)
        if waitingForClose and hideHookRoot ~= root then
            root:HookScript("OnHide", OnSocialHide)
            hideHookRoot = root
        end
        return
    end
    waitingForClose = nil
    fontSize = requestedFontSize
    for _, page in ipairs(pages) do
        if not PageEnabled(page) then Detach(page) end
    end
    if not enabled then Event:OffOwner(owner); return end
    if not CanEdit(root) then return end
    Attach(pages[1], root.FriendsList, _G.FriendsListSocialCardMixin)
    if wanted then Attach(pages[2], root.RecentAlliesList, _G.RecentAlliesSocialCardMixin) end
end

function Native:ApplySocialListCompact(enabled, size, currentGameFirst, yieldToController)
    local wasWanted, wasSorted = wanted, sortWanted
    externallyControlled = yieldToController == true
    wanted = not externallyControlled and enabled == true
    sortWanted = not externallyControlled and currentGameFirst == true
    for _, page in ipairs(pages) do
        if wanted ~= wasWanted or (not page.recent and sortWanted ~= wasSorted) then
            if page.layerVisible then page.resumeScroll = true end
            page.layerVisible = nil
        end
        if not wanted then page.failed = nil end
    end
    if externallyControlled and Security.InCombatLockdown() then
        for _, page in ipairs(pages) do HideCompactView(page) end
    end
    requestedFontSize = size or 14
    Reconcile()
end

-- Sample only on request. The scroll box can hide itself during recycling
-- after a successful Refresh, so the last refresh result is not visibility.
local function InspectCompactPage(page, status)
    local layer = page.layer
    local box = layer and layer.ScrollBox
    local visible = false
    if box then visible = box:IsVisible() end
    if not Readable(visible, "boolean") then return end
    status.visible = visible
    if visible then
        status.reason = "no-visible-card"
        for _, frame in ipairs(box:GetFrames()) do
            if frame.LayoutScaledContent == page.cardMixin.LayoutScaledContent and frame:IsVisible() then
                local height = frame:GetHeight()
                if not Readable(height, "number") then
                    status.rowHeight, status.reason = nil, "height-unavailable"
                    return
                end
                status.rowHeight = height
                if layer.compact == false then
                    status.reason = "sorted"
                    return
                end
                if math.abs(height - 24) > 0.01 then
                    status.reason = "row-height"
                    return
                end
                status.reason = "compact"
            end
        end
    elseif externallyControlled then status.reason = "external-control"
    elseif not (wanted or CanSort(page)) then status.reason = "disabled"
    elseif Security.InCombatLockdown() then status.reason = "combat"
    elseif page.failed and not CanSort(page) then status.reason = page.reason or "row-layout"
    elseif not page.box then status.reason = loadListener and "waiting-addon" or "not-attached"
    elseif not page.box:IsVisible() then status.reason = "pane-hidden"
    else status.reason = page.reason or (layer and layer.reason) or "layer-hidden" end
end

local function CompactPageStatus(page)
    local status = { reason = "visibility-unavailable" }
    if not pcall(InspectCompactPage, page, status) then
        status.rowHeight = nil
        status.reason = status.visible and "height-unavailable" or "visibility-unavailable"
    end
    return status
end

function Native:GetSocialListCompactDiagnostics()
    return {
        requested = wanted == true,
        friendsAttached = pages[1].box ~= nil,
        recentAlliesAttached = pages[2].box ~= nil,
        friends = CompactPageStatus(pages[1]),
        recentAllies = CompactPageStatus(pages[2]),
        waitingForAddon = loadListener ~= nil,
        waitingForClose = waitingForClose == true,
        recoveryPending = combatListener ~= nil or recoveryTimer ~= nil,
        layoutFailures = layoutFailures,
    }
end
