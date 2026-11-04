local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.IsForever == true and YUI.Components) then return end
if YUI._EllesmereUIQuestTrackerScroll then return end

local Security = YUI.API and YUI.API.Security
local System = YUI.API and YUI.API.System
local Event, GUI2 = YUI.Event, YUI.GUI2
local Scroll = { enabled = false, status = "disabled", failures = 0 }
YUI._EllesmereUIQuestTrackerScroll = Scroll

local CONTENT_HEIGHT, SIDE_PADDING, WHEEL_STEP = 65536, 36, 42
local states = setmetatable({}, { __mode = "k" })
local pendingTimer, current
local Discover, Refresh, Restore, LayoutBody

local function Secret(value)
    return Security and Security.IsSecretValue and Security.IsSecretValue(value)
end

local function EnableQuestIcons()
    if not (System and System.GetCVarSafe and System.SetCVarSafe) then return end
    local value = System.GetCVarSafe("questPOI")
    if Secret(value) or type(value) ~= "string" or value == "1" then return end
    -- 原生 CVar 回调负责刷新图标；停用滚动不关闭已经打开的图标。
    if not System.SetCVarSafe("questPOI", "1") then Scroll.failures = Scroll.failures + 1 end
end

local function ReadField(object, key)
    return object[key]
end

local function Field(object, key)
    if Secret(object) or type(object) ~= "table" then return nil end
    if Security.CanAccessTable and not Security.CanAccessTable(object) then return nil end
    local ok, value = pcall(ReadField, object, key)
    if ok and not Secret(value) then return value end
end

local function Number(value)
    if not Secret(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge then return value end
end

local function Read(frame, method)
    local fn = Field(frame, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame)
    if ok and not Secret(value) then return value end
end

local function Write(frame, method, ...)
    if current and frame == current.frame and (method == "SetPoint" or method == "ClearAllPoints" or method == "SetScale") then
        -- 编辑模式同名 Lua 包装器会修改吸附状态，SetScale 还可能调用 Update。
        -- 只调用原生保存的 C 方法，不进入包装器。
        method = method .. "Base"
    end
    local ok = Security.SafeMethod("EllesmereUIEnhancement:quest-scroll", frame, method, ...)
    if not ok then Scroll.failures = Scroll.failures + 1 end
    return ok
end

local function Combat()
    return Security.InCombatLockdown()
end

local function Points(frame, exclude)
    local result = {}
    local count = Number(Read(frame, "GetNumPoints"))
    if not count or count > 8 then return nil end
    for index = 1, count do
        local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
        if not ok or Secret(point) or type(point) ~= "string" or Secret(relative) or Secret(relativePoint) or type(relativePoint) ~= "string"
            or not Number(x) or not Number(y) then return nil end
        if relative ~= exclude then result[#result + 1] = { point, relative, relativePoint, x, y } end
    end
    return #result > 0 and result or nil
end

local function ApplyPoints(frame, points, padded)
    if not Write(frame, "ClearAllPoints") then return false end
    for _, point in ipairs(points) do
        local offset = 0
        if padded then
            if point[1]:find("LEFT", 1, true) then offset = -SIDE_PADDING
            elseif point[1]:find("RIGHT", 1, true) then offset = SIDE_PADDING end
        end
        if not Write(frame, "SetPoint", point[1], point[2], point[3], point[4] + offset, point[5]) then return false end
    end
    return true
end

local function CancelPending()
    if pendingTimer then pendingTimer:Cancel(); pendingTimer = nil end
end

local function RunPending()
    pendingTimer = nil
    if Scroll.enabled then Discover() end
end

local function Queue()
    if not Scroll.enabled or pendingTimer then return end
    if C_Timer and C_Timer.NewTimer then pendingTimer = C_Timer.NewTimer(0, RunPending) end
end

local function Editing()
    return Read(_G.EditModeManagerFrame, "IsEditModeActive") == true
end

local function ProviderEnabled()
    local provider = _G.EllesmereUIQuestTracker
    local cfg = Field(provider, "Cfg")
    if type(cfg) ~= "function" then return nil end
    local ok, enabled = pcall(cfg, "enabled")
    if ok and not Secret(enabled) and enabled ~= false then return provider end
end

local function SetOffset(state, offset)
    offset = math.max(0, math.min(state.range or 0, offset))
    if offset ~= state.offset or Number(Read(state.viewport, "GetVerticalScroll")) ~= offset then
        if Write(state.viewport, "SetVerticalScroll", offset) then state.offset = offset end
    end
end

local function UpdateWheel(state)
    if not state.mounted or Combat() then return end
    local alpha = Number(Read(state.frame, "GetEffectiveAlpha"))
    Write(state.viewport, "EnableMouseWheel", Scroll.enabled and state.range > 0
        and Read(state.frame, "IsVisible") == true and alpha ~= nil and alpha > 0)
end

-- 只读任务模块的既有块；不进入场景或 UIWidget 的共享池。
local function FindAnchor(state, keep)
    local module = _G.QuestObjectiveTracker
    local used = Field(module, "usedBlocks")
    if not used or (Security.CanAccessTable and not Security.CanAccessTable(used)) then return end
    local contentTop = Number(Read(state.content, "GetTop"))
    if not contentTop then return end
    local bestID, bestTop, bestDistance
    local count, templates = 0, 0
    for _, blocks in pairs(used) do
        templates = templates + 1
        if templates > 8 then return end
        if not Secret(blocks) and type(blocks) == "table" and (not Security.CanAccessTable or Security.CanAccessTable(blocks)) then
            for id, block in pairs(blocks) do
                count = count + 1
                if count > 256 then return end
                if Number(id) and Read(block, "IsShown") == true then
                    local top = Number(Read(block, "GetTop"))
                    if top then
                        top = contentTop - top
                        if keep and id == state.anchorID then return id, top end
                        local distance = math.abs(top - state.offset)
                        if not bestDistance or distance < bestDistance then
                            bestID, bestTop, bestDistance = id, top, distance
                        end
                    end
                end
            end
        end
    end
    if not keep then return bestID, bestTop end
end

local function RememberAnchor(state)
    local id, top = FindAnchor(state, false)
    state.anchorID, state.anchorScreenTop = id, top and top - state.offset or nil
end

local function FitBackground(state, capture)
    local bg = _G.EllesmereUIQTBackground
    if not state.mounted or not bg or Read(bg, "IsShown") ~= true then return end
    if Combat() then
        state.bgCapturePending = state.bgCapturePending or capture
        Scroll.deferred = true
        return
    end
    local scale = Number(Read(bg, "GetEffectiveScale"))
    local rootScale = Number(Read(state.frame, "GetEffectiveScale"))
    local left, top = Number(Read(bg, "GetLeft")), Number(Read(bg, "GetTop"))
    local bottom, width = Number(Read(bg, "GetBottom")), Number(Read(bg, "GetWidth"))
    local rootLeft, rootTop = Number(Read(state.frame, "GetLeft")), Number(Read(state.frame, "GetTop"))
    if not (scale and scale > 0 and rootScale and rootScale > 0 and left and top and bottom and width and rootLeft and rootTop) then return end
    -- 所有偏移转回背景自身单位；透明容器不改变背景材质、颜色或顶线。
    local ratio = rootScale / scale
    if capture or state.bgCapturePending or state.background ~= bg then
        state.background, state.bgX, state.bgY = bg, left - rootLeft * ratio, top - rootTop * ratio
        state.bgWidth, state.bgHeight = width, top - bottom
        state.bgCapturePending = nil
    end
    local x, y = state.bgX, state.bgY
    local height = math.max(0, math.min(state.bgHeight, state.height * ratio + y))
    Write(bg, "ClearAllPoints")
    Write(bg, "SetPoint", "TOPLEFT", state.host, "TOPLEFT", SIDE_PADDING * ratio + x, y)
    Write(bg, "SetPoint", "BOTTOMRIGHT", state.host, "TOPLEFT", SIDE_PADDING * ratio + x + state.bgWidth, y - height)
    local divider = Field(bg, "_divider")
    if divider then
        Write(divider, "ClearAllPoints")
        Write(divider, "SetPoint", "TOPLEFT", bg, "TOPLEFT", 0, 0)
        Write(divider, "SetPoint", "TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    end
end

Refresh = function(state)
    if not state.mounted or state.writing then return end
    if Combat() then Scroll.deferred = true; return end
    if not ProviderEnabled() or Editing() then Restore(state); return end
    if Read(state.module, "IsShown") ~= true then
        Restore(state)
        Scroll.status = "waiting-quests"
        return
    end
    local rootTop = Number(Read(state.frame, "GetTop"))
    local bottom = Number(Read(Field(state.frame, "NineSlice"), "GetBottom"))
    if not rootTop or not bottom then
        Scroll.status = "geometry-unavailable"
        state.blocked = true
        Restore(state)
        return
    end
    if not LayoutBody(state, rootTop, bottom) then
        Scroll.status = "geometry-unavailable"
        state.blocked = true
        Restore(state)
        return
    end
    local _, anchorTop = FindAnchor(state, true)
    SetOffset(state, anchorTop and state.anchorScreenTop and anchorTop - state.anchorScreenTop or state.offset)
    RememberAnchor(state)
    FitBackground(state)
    UpdateWheel(state)
    Scroll.status = "mounted"
end

-- 标题仍属于原生模块。只移动正文容器，不重挂任务块或改写按钮脚本。
LayoutBody = function(state, rootTop, bottom)
    local module, viewport = state.module, state.viewport
    local moduleTop = Number(Read(module, "GetTop"))
    local headerBottom = Number(Read(state.header, "GetBottom"))
    local moduleHeight = Number(Read(module, "GetHeight"))
    local width = Number(Read(module, "GetWidth"))
    if not (moduleTop and headerBottom and moduleHeight and width and width > 0 and state.fullHeight) then return false end
    local inset = math.max(0, moduleTop - headerBottom)
    -- NineSlice 底边沿用原生模块链。扣除当前任务模块后，得到其他模块和原生留白的预算。
    local otherHeight = math.max(0, rootTop - bottom - moduleHeight)
    local visibleHeight = math.min(state.fullHeight, math.max(inset, state.height - otherHeight))
    local bodyHeight = math.max(0, visibleHeight - inset)
    local contentHeight = math.max(0, state.fullHeight - inset)
    state.writing = true
    local ok = Write(viewport, "SetSize", width + SIDE_PADDING * 2, math.max(1, bodyHeight))
    ok = Write(viewport, "ClearAllPoints") and ok
    ok = Write(viewport, "SetPoint", "TOPLEFT", module, "TOPLEFT", -SIDE_PADDING, -inset) and ok
    ok = Write(state.carrier, "SetSize", width + SIDE_PADDING * 2, math.max(1, contentHeight)) and ok
    ok = Write(state.content, "SetParent", state.carrier) and ok
    ok = Write(state.content, "ClearAllPoints") and ok
    ok = Write(state.content, "SetPoint", "TOPLEFT", state.carrier, "TOPLEFT", SIDE_PADDING, 0) and ok
    ok = Write(state.content, "SetSize", width, math.max(1, contentHeight)) and ok
    -- 后续原生模块仍锚在任务模块底部，缩短它的可见高度即可继续保持原生排列。
    ok = Write(module, "SetHeight", visibleHeight) and ok
    local shown = bodyHeight > 0 and Read(state.content, "IsShown") == true
        and Read(state.frame, "IsCollapsed") ~= true and Read(state.frame, "IsShown") == true
    ok = Write(viewport, shown and "Show" or "Hide") and ok
    state.writing = false
    state.bodyHeight, state.contentHeight = bodyHeight, contentHeight
    state.range = shown and math.max(0, contentHeight - bodyHeight) or 0
    return ok
end

local function Layout(state)
    if not state.mounted or state.writing then return end
    if Combat() then Scroll.deferred = true; return end
    state.writing = true
    local frame, host = state.frame, state.host
    local ok = Write(host, "SetParent", state.parent)
    ok = Write(host, "SetClipsChildren", true) and ok
    ok = Write(host, "SetScale", state.scale) and ok
    ok = Write(host, "SetSize", state.width + SIDE_PADDING * 2, state.height) and ok
    ok = ApplyPoints(host, state.points, true) and ok
    local inset = state.insets
    ok = Write(host, "SetClampRectInsets", inset[1] + SIDE_PADDING, inset[2] - SIDE_PADDING, inset[3], inset[4]) and ok
    ok = Write(host, "SetClampedToScreen", state.clamped) and ok
    ok = Write(frame, "SetClampedToScreen", false) and ok
    ok = Write(frame, "SetParent", host) and ok
    ok = Write(frame, "SetScale", 1) and ok
    ok = Write(frame, "ClearAllPoints") and ok
    ok = Write(frame, "SetPoint", "TOPLEFT", host, "TOPLEFT", SIDE_PADDING, 0) and ok
    ok = Write(frame, "SetSize", state.width, CONTENT_HEIGHT) and ok
    state.writing = false
    if not ok then state.blocked = true; Scroll.status = "mount-failed"; Restore(state) end
end

Restore = function(state)
    if not state or not state.mounted then return true end
    if Combat() then Scroll.restorePending = true; return false end
    state.writing = true
    local frame = state.frame
    local ok = Write(state.content, "SetParent", state.contentParent)
    ok = Write(state.content, "SetSize", state.contentWidth, state.contentHeightBefore) and ok
    ok = ApplyPoints(state.content, state.contentPoints) and ok
    ok = Write(state.module, "SetHeight", state.fullHeight) and ok
    ok = Write(frame, "SetParent", state.parent) and ok
    ok = Write(frame, "SetScale", state.scale) and ok
    ok = ApplyPoints(frame, state.points) and ok
    ok = Write(frame, "SetSize", state.width, state.height) and ok
    ok = Write(frame, "SetClampedToScreen", state.clamped) and ok
    ok = Write(state.viewport, "EnableMouseWheel", false) and ok
    ok = Write(state.viewport, "SetVerticalScroll", 0) and ok
    ok = Write(state.viewport, "Hide") and ok
    ok = Write(state.host, "Hide") and ok
    if ok then
        state.mounted = false
        state.offset, state.range, state.anchorID, state.anchorScreenTop = 0, 0, nil, nil
        state.background, state.bgCapturePending = nil, nil
    end
    state.writing = false
    Scroll.restorePending = not ok
    local provider = _G.EllesmereUIQuestTracker
    if ok and type(Field(provider, "ResizeBGToContent")) == "function" then
        Security.SafeCall("EllesmereUIEnhancement:quest-scroll-background", provider.ResizeBGToContent)
    end
    return ok
end

local function Changed(state, kind, ...)
    if not state.mounted or state.writing then return end
    if kind == "point" then
        local points = Points(state.frame, state.host)
        if points then state.points = points end
    elseif kind == "parent" then state.parent = ...
    elseif kind == "scale" then
        local scale = Number(...)
        if scale and scale > 0 then
            local ratio = state.scale / scale
            for _, point in ipairs(state.points) do point[4], point[5] = point[4] * ratio, point[5] * ratio end
            state.scale = scale
        end
    elseif kind == "height" then
        local height = Number(...)
        if height and height ~= CONTENT_HEIGHT then state.height = height end
    elseif kind == "width" then state.width = Number(...) or state.width
    elseif kind == "size" then
        local width, height = ...
        state.width = Number(width) or state.width
        if Number(height) and height ~= CONTENT_HEIGHT then state.height = height end
    elseif kind == "clamp" then state.clamped = (...) == true
    elseif kind == "insets" then
        local left, right, top, bottom = ...
        if Number(left) and Number(right) and Number(top) and Number(bottom) then
            state.insets[1], state.insets[2], state.insets[3], state.insets[4] = left, right, top, bottom
        end
    elseif kind == "native-height" then
        if Read(state.frame, "IsInDefaultPosition") ~= true then return end
        local parentHeight = Number(Read(state.parent, "GetHeight"))
        if not parentHeight then return end
        -- 原生默认位置按父容器高度计算，不能把透明窗口当成原来的 UIParent。
        state.height = math.max(parentHeight + state.points[1][5], 20)
    end
    if Combat() then Scroll.deferred = true; return end
    if not Scroll.enabled then Restore(state); return end
    Layout(state)
    Queue()
end

local function Hook(state, object, method, callback)
    if type(Field(object, method)) ~= "function" then return false end
    local ok = Security.SafeHook("EllesmereUIEnhancement:quest-scroll-" .. method, object, method, callback)
    if ok then state.physicalHooks = (state.physicalHooks or 0) + 1 end
    return ok
end

local function Install(state)
    if state.hooked then return state.hookOK end
    local frame = state.frame
    local ok = Hook(state, frame, "Update", function() if Scroll.enabled then Refresh(state) end end)
    -- 原生 dirty closure 可能保留旧的容器 Update 引用；任务模块在容器内动态调用。
    ok = Hook(state, _G.QuestObjectiveTracker, "Update", function()
        if Scroll.enabled then Queue() end
    end) and ok
    ok = Hook(state, state.module, "SetHeight", function(_, height)
        if not state.mounted or state.writing then return end
        state.fullHeight = Number(height) or state.fullHeight
        Queue()
    end) and ok
    ok = Hook(state, frame, "UpdateHeight", function() Changed(state, "native-height") end) and ok
    for _, method in ipairs({ "Show", "Hide", "SetAlpha" }) do
        ok = Hook(state, frame, method, function() if Scroll.enabled then UpdateWheel(state) end end) and ok
    end
    for method, kind in pairs({ SetPoint = "point", SetParent = "parent", SetScale = "scale", SetHeight = "height", SetWidth = "width", SetSize = "size", SetClampedToScreen = "clamp", SetClampRectInsets = "insets" }) do
        local changeKind = kind
        ok = Hook(state, frame, method, function(_, ...) Changed(state, changeKind, ...) end) and ok
    end
    ok = Hook(state, frame, "OnEditModeEnter", function() if state.mounted then Restore(state) end end) and ok
    ok = Hook(state, frame, "OnEditModeExit", function() if Scroll.enabled then Queue() end end) and ok
    local provider = ProviderEnabled()
    if provider then
        ok = Hook(state, provider, "ResizeBGToContent", function()
            if Scroll.enabled and state.mounted then FitBackground(state, true); Refresh(state) end
        end) and ok
    end
    state.hooked = true
    state.hookOK = ok
    return ok
end

Discover = function()
    if not Scroll.enabled then return end
    if Combat() then Scroll.deferred = true; return end
    Scroll.deferred = false
    if Editing() then Scroll.status = "edit-mode"; return end
    if not ProviderEnabled() then if current then Restore(current) end; Scroll.status = "waiting-provider"; return end
    local frame = _G.ObjectiveTrackerFrame
    if not frame then Scroll.status = "waiting-tracker"; return end
    local state = states[frame]
    if not state then state = { frame = frame }; states[frame] = state end
    current = state
    if state.blocked then return end
    if type(Field(frame, "SetPointBase")) ~= "function" or type(Field(frame, "ClearAllPointsBase")) ~= "function"
        or type(Field(frame, "SetScaleBase")) ~= "function" then Scroll.status = "unsupported"; return end
    if state.mounted then Layout(state); Refresh(state); return end
    state.module = _G.QuestObjectiveTracker
    state.header, state.content = Field(state.module, "Header"), Field(state.module, "ContentsFrame")
    if not (state.header and state.content) then Scroll.status = "unsupported"; return end
    if not Install(state) then Scroll.status = "unsupported"; return end
    if Read(state.module, "IsShown") ~= true then Scroll.status = "waiting-quests"; return end
    state.parent, state.points = Read(frame, "GetParent"), Points(frame)
    state.width, state.height = Number(Read(frame, "GetWidth")), Number(Read(frame, "GetHeight"))
    state.scale, state.clamped = Number(Read(frame, "GetScale")), Read(frame, "IsClampedToScreen") == true
    state.contentParent, state.contentPoints = Read(state.content, "GetParent"), Points(state.content)
    state.contentWidth, state.contentHeightBefore = Number(Read(state.content, "GetWidth")), Number(Read(state.content, "GetHeight"))
    state.fullHeight = Number(Read(state.module, "GetHeight"))
    local ok, left, right, top, bottom = Security.SafeMethod("EllesmereUIEnhancement:quest-scroll-insets", frame, "GetClampRectInsets")
    if not (ok and Number(left) and Number(right) and Number(top) and Number(bottom)) then Scroll.status = "geometry-unavailable"; return end
    state.insets = { left, right, top, bottom }
    if not (state.parent and state.points and state.width and state.width > 0 and state.height and state.height > 0 and state.scale and state.scale > 0
        and state.contentParent and state.contentPoints and state.contentWidth and state.contentHeightBefore and state.fullHeight) then Scroll.status = "geometry-unavailable"; return end
    if not state.viewport then
        state.host = GUI2:CreateFrame(state.parent, { width = state.width, height = state.height })
        state.host:EnableMouse(false)
        state.viewport = GUI2:CreateScrollFrame(state.module, { template = false, child = false, mouseWheel = true })
        state.carrier = GUI2:CreateFrame(state.viewport, { width = 1, height = 1 })
        -- ScrollFrame 只定位自有承载层；不手动设置它的锚点，留白属于内部正文。
        local attached = Write(state.viewport, "SetScrollChild", state.carrier)
        if not attached then
            Write(state.viewport, "Hide")
            Write(state.host, "Hide")
            state.blocked = true
            Scroll.status = "mount-failed"
            return
        end
        state.viewport:EnableMouse(false)
        state.viewport:SetScript("OnMouseWheel", function(_, delta)
            if not Scroll.enabled or not state.mounted or Combat() or not Number(delta) then return end
            local alpha = Number(Read(frame, "GetEffectiveAlpha"))
            if Read(frame, "IsVisible") ~= true or not alpha or alpha <= 0 then return end
            SetOffset(state, state.offset - delta * WHEEL_STEP)
            RememberAnchor(state)
        end)
    end
    state.offset, state.range, state.mounted = 0, 0, true
    Write(state.host, "Show")
    Layout(state)
    -- 尺寸变化走原生 OnSizeChanged/MarkDirty；不从插件调用原生 Update。
    if state.mounted then Scroll.status = "awaiting-native-layout"; Queue() end
end

function Scroll:OnEvent(_, addonName)
    if addonName == nil or addonName == "Blizzard_ObjectiveTracker" or addonName == "EllesmereUIQuestTracker" then Queue() end
end

function Scroll:OnRegenEnabled()
    if self.restorePending and current then Restore(current) end
    if self.enabled then Discover()
    elseif not self.restorePending then Event:OffOwner(self); self.listeners = 0 end
end

function Scroll:SetEnabled(enabled, config)
    enabled = enabled == true and type(config) == "table" and config.questTrackerScroll == true
    if not enabled then
        self.enabled, self.deferred, self.status = false, false, "disabled"
        CancelPending()
        if Event and Event.OffOwner then Event:OffOwner(self) end
        self.listeners = 0
        if current then Restore(current) end
        if self.restorePending then
            Event:On("PLAYER_REGEN_ENABLED", "OnRegenEnabled", self, { moduleId = "component:EllesmereUIEnhancement" })
            self.listeners = 1
        end
        return
    end
    if not (Security and Security.SafeHook and Security.SafeMethod and Security.SafeCall and Security.InCombatLockdown
        and Event and Event.On and Event.OffOwner and GUI2 and GUI2.CreateScrollFrame and GUI2.CreateFrame
        and C_Timer and C_Timer.NewTimer) then self.status = "unsupported"; return end
    if not self.enabled then
        Event:OffOwner(self)
        self.enabled = true
        if current then current.blocked = nil end
        EnableQuestIcons()
        Event:On("ADDON_LOADED", "OnEvent", self, { moduleId = "component:EllesmereUIEnhancement" })
        Event:On("YUI_LOGIN_READY", Queue, self, { moduleId = "component:EllesmereUIEnhancement" })
        Event:On("PLAYER_REGEN_ENABLED", "OnRegenEnabled", self, { moduleId = "component:EllesmereUIEnhancement" })
        self.listeners = 3
    end
    Discover()
end

function Scroll:GetStats()
    return {
        enabled = self.enabled, status = self.status, listeners = self.listeners or 0,
        pendingTimers = pendingTimer and 1 or 0, restorePending = self.restorePending == true,
        deferred = self.deferred == true, mounted = current and current.mounted == true or false,
        offset = current and current.offset or 0, range = current and current.range or 0,
        bodyHeight = current and current.bodyHeight or 0, contentHeight = current and current.contentHeight or 0,
        windowTop = current and Number(Read(current.host, "GetTop")),
        windowLeft = current and Number(Read(current.host, "GetLeft")),
        bodyTop = current and Number(Read(current.viewport, "GetTop")),
        bodyLeft = current and Number(Read(current.viewport, "GetLeft")),
        headerTop = current and Number(Read(current.header, "GetTop")),
        contentLeft = current and Number(Read(current.content, "GetLeft")),
        actualOffset = current and Number(Read(current.viewport, "GetVerticalScroll")),
        physicalHooks = current and current.physicalHooks or 0,
        activeHooks = self.enabled and current and current.mounted and current.physicalHooks or 0, failures = self.failures,
    }
end
