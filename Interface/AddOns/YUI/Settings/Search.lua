local YUI = _G.YUI
local S = YUI and YUI.Settings
if not S or S.Search then return end
local GUI, Locale = YUI.GUI2, YUI.Locale
local Search = { catalog = {}, routes = {}, rows = {}, page = 1, selected = 1, generation = 0 }
S.Search = Search
local LC = Locale:Get("Core")
local function T(key) return LC["settings.search." .. key] end
local function Normalize(value)
    return tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):lower():match("^%s*(.-)%s*$")
end
Search.Normalize = Normalize

-- Descriptors contain locale keys, not translated copies or live settings/UI state.
function Search:RegisterCatalog(owner, namespace, route, keys)
    self.catalog[#self.catalog + 1] = { owner = owner, namespace = namespace, route = route, keys = keys }
    self.index = nil
end
function Search:RegisterRoute(owner, callback) self.routes[owner] = callback end
function Search:CancelTimer(key)
    local timer = self[key]
    if timer then timer:Cancel(); self[key] = nil end
end
function Search:Later(key, delay, callback)
    self:CancelTimer(key)
    self[key] = C_Timer.NewTimer(delay, function()
        self[key] = nil
        callback()
    end)
end
function Search:StopHighlightAnimation()
    local handle = self.highlightAnimation
    self.highlightAnimation = nil
    if handle then handle:Cancel() end
end
function Search:CancelLocation()
    self:StopHighlightAnimation()
    self.generation = self.generation + 1
    self.pending = nil
    self:CancelTimer("locateTimer")
    self:CancelTimer("expireTimer")
    if self.outline then
        self.outline:Hide()
        self.outline:ClearAllPoints()
        self.outline:SetParent(S.Elements.frame)
    end
end
function Search:Close()
    self:CancelLocation()
    self:CancelTimer("queryTimer")
    if self.input then self.input:SetValue("", true); self.input:ClearFocus() end
    self.active, self.lastQuery, self.page, self.selected = false, "", 1, 1
    self.index, self.results = nil, nil
    for _, row in ipairs(self.rows) do
        row.entry, row.hovered = nil, nil
        row:SetScript("OnClick", nil)
        if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end
    self:Refresh()
end
function Search:HandleEscape()
    if not self.input then return false end
    if self.input.IsInIMECompositionMode and self.input:IsInIMECompositionMode() then return true end
    if self.input:GetText() == "" and not self.active then return false end
    self:Close()
    return true
end
function Search:Invalidate()
    self.index, self.indexLocale, self.indexProduct = nil, nil, nil
    self:CancelLocation()
    if self.input and S:IsOpen() then self:RunQuery() end
end

local function ModuleTitle(module, locale)
    return Locale:Resolve(module.navTitleNamespace or module.titleNamespace or "Core",
        module.navTitleKey or module.titleKey or "", locale) or module.name
end
function Search:ModuleFor(owner)
    if owner:sub(1, 10) == "component:" then
        for _, module in ipairs(S:GetVisibleModules()) do
            if module.id == "suite.settings.general" or module.id == "toolbox.settings" then return module end
        end
        return nil
    end
    local module = S.modulesById[owner]
    return module and S:IsModuleVisible(module) and module or nil
end
function Search:ComponentFor(owner)
    local id = owner:match("^component:(.+)$")
    if not id then return nil end
    local components = YUI.Components
    local component = components and components:Get(id)
    if not component or (component.kind == "product" and component.toolboxManaged ~= true) then return nil end
    local feature = component.feature or component
    if feature.IsVisible then
        local ok, visible = pcall(feature.IsVisible, feature)
        if not ok or visible == false then return nil end
    end
    return component
end
local function AddText(parts, seen, text)
    text = Normalize(text)
    if text ~= "" and not seen[text] then parts[#parts + 1] = text; seen[text] = true end
end
local function RouteTitle(namespace, route)
    if not route or route == "" then return nil end
    local key
    if namespace == "YChat" then key = "settings.page." .. (route == "channelInput" and "channel_input" or route)
    elseif namespace == "YMap" then key = "settings.tab." .. (route == "worldMap" and "world_map" or route == "worldEvents" and "world_events" or route)
    elseif namespace == "YActionBar" then key = "settings.section." .. route
    end
    return key and Locale:Resolve(namespace, key)
end
local function AvailableKey(namespace, key)
    if namespace == "Core" and key == "settings.appearance.tab.plugin_skins" then
        return not YUI.IsForever
    end
    if namespace ~= "NativeInterface" then return true end
    if YUI.IsMists == true then return false end
    if key:sub(1, 5) == "beta." then return YUI.IsForever == true end
    if key:sub(1, 7) == "manage." or key:sub(1, 9) == "tutorial." or key == "hide.buff_collapse" then
        return YUI.IsRetail == true
    end
    return true
end
function Search:BuildIndex()
    local language, product = Locale:Current(), S.ActiveProductId
    if self.index and self.indexLocale == language and self.indexProduct == product then return self.index end
    local index, ids = {}, {}
    local function add(owner, namespace, key, route, module, component)
        if not AvailableKey(namespace, key) then return end
        if route and route:sub(1, 5) == "ybar:" then
            local registered = YUI.YBar and YUI.YBar.RegisteredModules
            if not (registered and registered[route:sub(6)]) then return end
        end
        local id = owner .. ":" .. (route or "") .. ":" .. key
        if ids[id] then return end
        local title = key == "" and (component and YUI.Components:GetDisplayName(component) or ModuleTitle(module))
            or Locale:Resolve(namespace, key)
        if type(title) ~= "string" or title == "" or title == key or title:find("%%") then return end
        local parts, seen = {}, {}
        AddText(parts, seen, title)
        AddText(parts, seen, key ~= "" and Locale:Resolve(namespace, key .. ".search_aliases") or nil)
        if component and key == "" then
            AddText(parts, seen, YUI.Components:GetDisplayName(component))
            AddText(parts, seen, Locale:Resolve("Core", "component." .. component.id .. ".name"))
            AddText(parts, seen, Locale:Resolve(namespace, "feature.name"))
        end
        local path = ModuleTitle(module)
        if component then path = path .. " › " .. YUI.Components:GetDisplayName(component) end
        local routeTitle = RouteTitle(namespace, route)
        if routeTitle then path = path .. " › " .. routeTitle end
        index[#index + 1] = { id = id, owner = owner, namespace = namespace, key = key, route = route,
            module = module, component = component, title = title, path = path,
            text = table.concat(parts, "\n"), normalizedTitle = Normalize(title) }
        ids[id] = true
    end
    for _, module in ipairs(S:GetVisibleModules()) do
        if module.id ~= "core.credits" and not module.id:find("Changelog", 1, true) then
            add(module.id, module.titleNamespace or "Core", "", nil, module)
        end
    end
    for _, descriptor in ipairs(self.catalog) do
        local module = self:ModuleFor(descriptor.owner)
        local component = descriptor.owner:find("component:", 1, true) and self:ComponentFor(descriptor.owner)
        if module and (not descriptor.owner:find("component:", 1, true) or component) then
            if component then add(descriptor.owner, descriptor.namespace, "", nil, module, component) end
            if not component or component.settingsMode ~= "external" then
                for key in descriptor.keys:gmatch("%S+") do
                    add(descriptor.owner, descriptor.namespace, key, descriptor.route, module, component)
                end
            end
        end
    end
    self.index, self.indexLocale, self.indexProduct = index, language, product
    return index
end
function Search:Query(query)
    query = Normalize(query)
    if query == "" then return {} end
    local words, results = {}, {}
    for word in query:gmatch("%S+") do words[#words + 1] = word end
    for _, entry in ipairs(self:BuildIndex()) do
        local matches = true
        for _, word in ipairs(words) do
            if not entry.text:find(word, 1, true) then matches = false; break end
        end
        if matches then results[#results + 1] = entry end
    end
    table.sort(results, function(a, b)
        local function score(entry)
            if entry.normalizedTitle == query then return 3 end
            if entry.normalizedTitle:find(query, 1, true) then return 2 end
            return 1
        end
        local sa, sb = score(a), score(b)
        if sa ~= sb then return sa > sb end
        return a.id < b.id
    end)
    return results
end

-- Called only by the settings renderers while a search navigation is pending.
-- No global frame traversal and no persistent ID -> frame cache.
function Search:Bind(item, widget, label)
    local pending = self.pending
    if not pending or not widget then return end
    local text = item.searchText or item.formLabel or item.label or item.text
    local keyed = item.searchId == pending.entry.id or item.searchKey == pending.entry.key
    if keyed or (not item.searchKey and text and Normalize(text) == pending.label) then
        if pending.keyed and not keyed then return end
        if pending.widget and pending.widget ~= widget and not (keyed and not pending.keyed) then
            local function contains(parent, child)
                while child do
                    if child == parent then return true end
                    child = child:GetParent()
                end
                return false
            end
            if not contains(widget, pending.widget) and not contains(pending.widget, widget) then
                pending.ambiguous = true
                return
            end
        end
        if keyed and not pending.keyed then pending.ambiguous = nil end
        pending.keyed = keyed
        pending.widget, pending.labelRegion = widget, label
        self:Later("locateTimer", 0, function() self:Locate() end)
    end
end
function Search:PrepareConfig(config)
    if not self.pending then return end
    local divider
    local function contains(item)
        if item.searchKey == self.pending.entry.key or item.searchId == self.pending.entry.id then return true end
        if not item.searchKey and Normalize(item.formLabel or item.label or item.text) == self.pending.label then return true end
        for _, child in ipairs(item.children or item.ychatSectionFields or {}) do
            if contains(child) then return true end
        end
        return false
    end
    for _, item in ipairs(config) do
        if item.type == "divider" then divider = item end
        if divider and divider.collapsible and contains(item) then
            local key = divider.collapseKey or divider.key or divider.id or divider.label
            if key then S._dividerCollapseState[key] = false end
        end
    end
end
function Search.ScrollDelta(viewTop, viewBottom, top, bottom, margin)
    if top <= viewTop and bottom >= viewBottom then return 0 end
    if top > viewTop then return viewTop - top - margin end
    return viewBottom - bottom + margin
end
function Search:Locate()
    local pending = self.pending
    if not pending or pending.ambiguous or not S:IsOpen() then return end
    local widget = pending.widget
    if not widget or not widget:IsVisible() then return end
    -- Scroll nested viewports from the innermost to the settings viewport.
    local parent = widget:GetParent()
    while parent do
        if parent.GetVerticalScroll and parent.SetVerticalScroll and parent.GetVerticalScrollRange then
            local top, bottom = widget:GetTop(), widget:GetBottom()
            local viewTop, viewBottom = parent:GetTop(), parent:GetBottom()
            if top and bottom and viewTop and viewBottom then
                local scale = parent:GetEffectiveScale() / widget:GetEffectiveScale()
                local delta = self.ScrollDelta(viewTop * scale, viewBottom * scale, top, bottom, 12) / scale
                if delta ~= 0 then
                    parent:SetVerticalScroll(math.max(0, math.min(parent:GetVerticalScrollRange(), parent:GetVerticalScroll() + delta)))
                end
            end
        end
        parent = parent:GetParent()
    end
    local outline = self.outline
    if not outline then
        outline = GUI:CreateFrame(S.Elements.frame)
        outline:EnableMouse(false)
        local edges = {}
        for i = 1, 4 do
            edges[i] = GUI:CreateTexture(outline, { layer = "OVERLAY" })
            GUI:SetTexturePaintKey(edges[i], "color.state.warning")
        end
        outline.searchEdges = { top = edges[1], bottom = edges[2], left = edges[3], right = edges[4] }
        self.outline = outline
        outline:SetScript("OnHide", function() self:StopHighlightAnimation() end)
    end
    outline:SetParent(widget:GetParent())
    outline:SetFrameLevel((widget.GetFrameLevel and widget:GetFrameLevel() or widget:GetParent():GetFrameLevel()) + 8)
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", pending.labelRegion or widget, "TOPLEFT", -5, 5)
    outline:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 5, -5)
    local width, height = outline:GetWidth(), outline:GetHeight()
    local dx, dy = GUI:GetPixelOriginCorrection(outline)
    local snappedWidth = GUI:SnapLayoutBoundary(outline, width) or width
    local snappedHeight = GUI:SnapLayoutBoundary(outline, height) or height
    outline:ClearAllPoints()
    outline:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 5 + dx + snappedWidth - width, -5 + dy)
    outline:SetSize(snappedWidth, snappedHeight)
    GUI:LayoutPixelBorder(outline.searchEdges, outline, 2)
    outline:Show()
    outline:SetAlpha(0.7)
    self:StopHighlightAnimation()
    if YUI.Animation and YUI.Animation.Tween then
        self.highlightAnimation = YUI.Animation:Tween({
            target = outline, owner = self, key = "search-highlight", duration = 2.5,
            from = 0, to = 1, easing = "linear",
            onUpdate = function(_, _, progress)
                -- Two soft pulses followed by a short fade; no native groups accumulate.
                local elapsed = progress * 2.5
                local alpha = elapsed < 2 and (0.525 + 0.175 * math.cos(elapsed * math.pi * 2))
                    or (0.7 * math.max(0, (2.5 - elapsed) / 0.5))
                outline:SetAlpha(alpha)
            end,
            onFinished = function(handle)
                if self.highlightAnimation == handle then self.highlightAnimation = nil end
            end,
        })
    end
    self.pending = nil
    self:CancelTimer("expireTimer")
    self:Later("expireTimer", 2.5, function() self:CancelLocation() end)
end
function Search:Open(entry)
    if not entry or S:IsCombatBlocked() then return end
    if not self:ModuleFor(entry.owner)
        or (entry.component and not self:ComponentFor(entry.owner)) then self:Invalidate(); return end
    self:CancelLocation()
    self.opening = true
    local enabled
    if S:GetSelectedModule() ~= entry.module or (S.IsSearchModuleDisabled and S:IsSearchModuleDisabled(entry.module)) then
        enabled = S:SelectModule(entry.module)
    end
    if enabled == false then
        if S.ShowSearchDisabledModule then S:ShowSearchDisabledModule(entry.module) end
        self.opening = nil
        self.status:SetText(T("disabled"))
        return
    end
    if entry.key ~= "" then self.pending = { entry = entry, label = Normalize(entry.title) } end
    local route = self.routes[entry.owner]
    if entry.route and entry.route:sub(1, 5) == "ybar:" and YUI.OpenYBarModuleSettings then
        self.pending = nil
        YUI:OpenYBarModuleSettings(entry.route:sub(6))
    elseif entry.component then
        S:OpenComponentFeature(entry.component.id, true)
    elseif route then
        route(entry.route, entry.key)
        S:RefreshSelectedModule()
    elseif entry.key ~= "" then
        S:RefreshSelectedModule()
    end
    self.opening = nil
    if self.pending then
        self:Later("expireTimer", 0.7, function()
            if self.pending then
                self.pending = nil
                if self.status then self.status:SetText(T("conditional")) end
            end
        end)
    end
end

function Search:RunQuery()
    if not self.input then return end
    if self.input.IsInIMECompositionMode and self.input:IsInIMECompositionMode() then return end
    self:CancelTimer("queryTimer")
    local query = self.input:GetText()
    self.lastQuery = query
    self.active = Normalize(query) ~= ""
    self.results = self.active and self:Query(query) or {}
    self.page, self.selected = 1, 1
    self:Refresh()
end
function Search:PaintRow(row)
    local selected = row.entry and row.index == self.selected
    row.fill:SetShown(row.hovered == true or selected == true)
    row.fill:SetAlpha(row.hovered and 1 or 0.5)
    row.marker:SetShown(selected == true)
    GUI:SetTextColorKey(row.title, selected and "color.state.warning" or "color.text.primary")
end
function Search:ChangePage(delta)
    local pages = math.max(1, math.ceil(#(self.results or {}) / (self.pageSize or 1)))
    local page = math.max(1, math.min(pages, self.page + delta))
    if page == self.page then return end
    self.page = page
    self.selected = (page - 1) * self.pageSize + 1
    self:Refresh()
end
function Search:Refresh()
    if not self.panel then return end
    local elements = S.Elements
    elements.navList:SetShown(not self.active)
    self.panel:SetShown(self.active == true)
    self.clear:SetShown(self.active == true)
    if not self.active then return end
    local pageSize = math.max(1, math.min(7, math.floor((self.panel:GetHeight() - 82) / 52)))
    self.pageSize = pageSize
    local results = self.results or {}
    local pages = math.max(1, math.ceil(#results / pageSize))
    self.page = math.min(self.page, pages)
    self.selected = math.max((self.page - 1) * pageSize + 1, math.min(self.selected, self.page * pageSize, #results))
    self.count:SetText(string.format(T("count"), #results))
    self.status:SetText(#results == 0 and T("empty") or T("hint"))
    for i = 1, 7 do
        local row = self.rows[i]
        local index = (self.page - 1) * pageSize + i
        local entry = i <= pageSize and results[index] or nil
        if row.entry ~= entry then
            row.hovered = nil
            if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end
        row.entry, row.index = entry, index
        row:SetShown(entry ~= nil)
        if entry then
            row.title:SetText(entry.title)
            local disabled = entry.component and not YUI.Components:IsEnabled(entry.component)
                or (not entry.component and S.IsSearchModuleDisabled and S:IsSearchModuleDisabled(entry.module))
            row.path:SetText(entry.path .. (disabled and (" · " .. T("not_enabled")) or ""))
            row:SetScript("OnClick", function()
                if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
                self.selected = index; self:Refresh(); self:Open(entry)
            end)
        else
            row:SetScript("OnClick", nil)
        end
        self:PaintRow(row)
    end
    self.pager:SetText(string.format("%d / %d", self.page, pages))
    self.previous:SetDisabled(self.page <= 1)
    self.next:SetDisabled(self.page >= pages)
    self.previous:SetShown(pages > 1); self.next:SetShown(pages > 1); self.pager:SetShown(pages > 1)
end
function Search:Layout()
    if not self.input then return end
    local elements = S.Elements
    local start = elements.navStartOffset
    self.input:ClearAllPoints()
    self.input:SetPoint("TOPLEFT", elements.nav, "TOPLEFT", 10, start + 34)
    self.panel:ClearAllPoints()
    self.panel:SetPoint("TOPLEFT", elements.nav, "TOPLEFT", 10, start)
    self.panel:SetPoint("BOTTOMRIGHT", elements.nav, "BOTTOMRIGHT", -10, 8)
    if self.active and (self.indexProduct ~= S.ActiveProductId or self.indexLocale ~= Locale:Current()) then
        self:RunQuery()
    else
        self:Refresh()
    end
end
function Search:Create()
    if self.input then return end
    local nav = S.Elements.nav
    local width = nav:GetWidth() - 20
    self.input = GUI.Form:CreateEditBox(nav, { width = width, height = 26, placeholder = T("placeholder"), searchPlaceholder = true,
        onChange = function()
            self:Later("queryTimer", 0.12, function() if S:IsOpen() then self:RunQuery() end end)
        end })
    self.input:SetMaxLetters(96)
    self.input:SetTextInsets(8, 30, 0, 0)
    self.clear = GUI:CreateButtonFrame(nav, { width = 24, height = 24, onClick = function()
        self.input:SetValue("", true); self:RunQuery(); self.input:SetFocus()
    end })
    -- Draw the cross directly: narrow text buttons truncate the glyph to dots.
    local clearLines = {}
    for i = 1, 2 do
        local line = GUI:CreateTexture(self.clear, { width = 12, height = 1.5, layer = "OVERLAY" })
        GUI:SetTexturePaintKey(line, "color.text.secondary")
        line:SetPoint("CENTER"); line:SetRotation(i == 1 and math.pi / 4 or -math.pi / 4)
        clearLines[i] = line
    end
    self.clear:SetScript("OnEnter", function()
        for _, line in ipairs(clearLines) do GUI:SetTexturePaintKey(line, "color.text.primary") end
    end)
    self.clear:SetScript("OnLeave", function()
        for _, line in ipairs(clearLines) do GUI:SetTexturePaintKey(line, "color.text.secondary") end
    end)
    self.clear:SetPoint("RIGHT", self.input, "RIGHT", -1, 0)
    self.clear:SetFrameLevel(self.input:GetFrameLevel() + 1)
    self.clear:Hide()
    self.input:SetScript("OnEscapePressed", function()
        local frame = S.Elements.frame
        if frame and frame.gui2EscapeCloseHandler then
            frame.gui2EscapeCloseHandler(frame)
        else
            self:HandleEscape()
        end
    end)
    self.input:SetScript("OnEnterPressed", function()
        if self.input.IsInIMECompositionMode and self.input:IsInIMECompositionMode() then return end
        if self.lastQuery ~= self.input:GetText() then self:RunQuery() end
        if self.results then self:Open(self.results[self.selected]) end
    end)
    self.input:SetScript("OnArrowPressed", function(_, key)
        if self.input.IsInIMECompositionMode and self.input:IsInIMECompositionMode() then return end
        if key ~= "UP" and key ~= "DOWN" then return end
        if self.lastQuery ~= self.input:GetText() then self:RunQuery() end
        local count = #(self.results or {})
        if count == 0 then return end
        self.selected = ((self.selected - 1 + (key == "UP" and -1 or 1)) % count) + 1
        self.page = math.ceil(self.selected / (self.pageSize or 1))
        self:Refresh()
    end)
    self.panel = GUI:CreateFrame(nav)
    local function wheel(_, delta)
        if delta ~= 0 then self:ChangePage(delta > 0 and -1 or 1) end
    end
    self.panel:EnableMouseWheel(true)
    self.panel:SetScript("OnMouseWheel", wheel)
    self.count = GUI:CreateText(self.panel, "", "font.size.sm", "color.text.secondary")
    self.count:SetPoint("TOPLEFT", 2, 0)
    for i = 1, 7 do
        local row = GUI:CreateButtonFrame(self.panel, { width = width, height = 50 })
        row:SetPoint("TOPLEFT", 0, -22 - (i - 1) * 52)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", wheel)
        row.fill = GUI:CreateTexture(row, { layer = "BACKGROUND" })
        GUI:SetTexturePaintKey(row.fill, "color.control.hover")
        row.fill:SetAllPoints(row); row.fill:Hide()
        row.marker = GUI:CreateTexture(row, { width = 2, layer = "ARTWORK" })
        GUI:SetTexturePaintKey(row.marker, "color.state.warning")
        row.marker:SetPoint("TOPLEFT", 0, -5); row.marker:SetPoint("BOTTOMLEFT", 0, 5); row.marker:Hide()
        row.title = GUI:CreateText(row, "", "font.size.md", "color.text.primary", "LEFT")
        row.title:SetPoint("TOPLEFT", 9, -6); row.title:SetWidth(width - 18); row.title:SetHeight(19)
        row.title:SetWordWrap(false)
        row.path = GUI:CreateText(row, "", "font.size.sm", "color.text.secondary", "LEFT")
        row.path:SetPoint("TOPLEFT", 9, -29); row.path:SetWidth(width - 18); row.path:SetHeight(15); row.path:SetWordWrap(false)
        row:SetScript("OnEnter", function()
            row.hovered = true; self:PaintRow(row)
            if row.entry and GameTooltip and (row.title:GetStringWidth() > row.title:GetWidth() or row.path:GetStringWidth() > row.path:GetWidth()) then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(row.entry.title)
                GameTooltip:AddLine(row.entry.path, 1, 1, 1, true); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            row.hovered = nil; self:PaintRow(row)
            if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end)
        self.rows[i] = row
    end
    self.status = GUI:CreateText(self.panel, "", "font.size.sm", "color.text.secondary")
    self.status:SetPoint("BOTTOMLEFT", 0, 28); self.status:SetWidth(width); self.status:SetHeight(32)
    self.previous = GUI.Form:CreateButton(self.panel, { text = "‹", width = 36, height = 24, onClick = function()
        self:ChangePage(-1)
    end })
    self.previous:SetPoint("BOTTOMLEFT", 0, 0)
    self.next = GUI.Form:CreateButton(self.panel, { text = "›", width = 36, height = 24, onClick = function()
        self:ChangePage(1)
    end })
    self.next:SetPoint("BOTTOMRIGHT", 0, 0)
    self.pager = GUI:CreateText(self.panel, "", "font.size.sm", "color.text.secondary")
    self.pager:SetPoint("BOTTOM", 0, 4)
    self:Layout()
end
