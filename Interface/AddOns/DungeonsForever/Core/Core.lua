-- =============================================================================
-- DungeonsForever · 基础层
-- 客户端判定 / 字体 / 初始化回调 / 音效 / 按钮与输入框工厂 / 下拉菜单入口。
-- 本插件为独立单窗口插件，外观固定 HUI 主题。
-- =============================================================================

local addonName, ns = ...

local ver = select(4, GetBuildInfo())
ns.version = ver
local function IsSupportedClient(v)
    if v >= 38000 and v < 40000 then return true end
    if v >= 16000 and v < 17000 then return true end
    if v >= 120000 and v < 130000 then return true end
    return false
end
ns.IsTitan = IsSupportedClient(ver)
ns.IsSupportedClient = IsSupportedClient
ns.IsForever = (ver >= 16000 and ver < 17000)
ns.IsRetail = (ver >= 120000 and ver < 130000)
ns.LoadForeverPages = ns.IsForever or ns.IsRetail
_G.DF_NS = ns

ns.huiTheme = "hui"

ns.CONTENT_TOP = 46

-- 自绘「设置」图标（Media/textures/DF_Settings.tga）：透明底 + 纯白形状。
-- 白色贴图去饱和仍是白色 → 状态切换一律走 SetVertexColor 染色，不用 SetDesaturated。
ns.SET_ICON = "Interface\\AddOns\\DungeonsForever\\Media\\textures\\DF_Settings"
ns.SET_ICON_IDLE = { 0.55, 0.62, 0.70 }
ns.SET_ICON_ON = { 1, 1, 1 }

local function DB()
    DungeonsForeverDB = DungeonsForeverDB or {}
    DungeonsForeverDB.ui = DungeonsForeverDB.ui or {}
    return DungeonsForeverDB
end
ns.DB = DB

ns.options = ns.options or {}
if ns.options.buttonSound == nil then ns.options.buttonSound = true end

-- 快捷按钮栏（贴主窗右侧第二槽）配置：缺失补默认；版本不符整档重置。
-- 键名即中文文案（zhTW / enUS 走 L 回退），无需另行登记词条。
ns.QUICK_VER = 1
ns.QUICK_GROUPS = { "dungeon", "prof", "explore" }
ns.QUICK_EXPLORE = { "books", "rewards", "bag", "bm" }
ns.QUICK_TABS = { "Dungeons", "Raids", "Professions", "Explore", "Collections", "Factions", "Bis", "Tier", "PvP", "Gear" } -- ★ 主窗标签页显隐（QB_SET_TABS，2026-10-08 用户；同日 +PvP 第八键，主窗胶囊本就有 PvP；2026-10-11 +Factions / +Gear 至第十键）

function ns.QuickCfg()
    local ui = DB().ui
    local q = ui.quick
    if type(q) ~= "table" or q.ver ~= ns.QUICK_VER then
        q = { ver = ns.QUICK_VER }
        ui.quick = q
    end
    if q.on == nil then q.on = true end
    if type(q.groups) ~= "table" then q.groups = {} end
    for _, k in ipairs(ns.QUICK_GROUPS) do
        if q.groups[k] == nil then q.groups[k] = true end
    end
    if q.profMode ~= "all" then q.profMode = "learned" end
    if type(q.expl) ~= "table" then q.expl = {} end
    for _, k in ipairs(ns.QUICK_EXPLORE) do
        if q.expl[k] == nil then q.expl[k] = true end
    end
    -- ★ 标签页显隐（QB_SET_TABS）：缺省全开（false = 隐藏该页签）
    if type(q.tabs) ~= "table" then q.tabs = {} end
    for _, k in ipairs(ns.QUICK_TABS) do
        if q.tabs[k] == nil then q.tabs[k] = true end
    end
    return q
end

do
    local candidates = { "ARKai_T.ttf", "ARHei.TTF", "FRIZQT__.TTF" }
    local probe = UIParent:CreateFontString()
    probe:Hide()
    for _, name in ipairs(candidates) do
        local path = format("Fonts\\%s", name)
        probe:SetFont(path, 15, "OUTLINE")
        if probe:GetFont() then
            ns.FONT = path
            break
        end
    end
    ns.FONT = ns.FONT or "Fonts\\FRIZQT__.TTF"
end

local loadedFuncs = {}
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    C_Timer.After(0, function()
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    DB()
    for _, fn in ipairs(loadedFuncs) do
        local ok, err = xpcall(fn, function(e)
            return tostring(e) .. "\n" .. debugstack(2)
        end)
        if not ok then
            print("|cffff5040[无限副本手册] 初始化回调出错（已跳过，不影响后续模块）：|r\n" .. tostring(err))
        end
    end
    end)
end)

-- ★★ 手柄模式自救 v2（2026-10-07 重做，v1 有时序空档）
--
-- 【定责】刷屏的 `ADDON_ACTION_FORBIDDEN 插件 'X' 调用保护功能 SetPreferredGamepadInteractTarget()`
-- 是**引擎归因误伤**，与本插件无关。硬证据：本机 !BugGrabber 存档里同一条报错先后点名过
-- 一串互不相关的插件（含本插件）挨个背锅；调用点 100% 在暴雪帧
-- （Blizzard_GamepadActionBars/MainActionBarFrame.lua:255 UpdateInteractIcons，经 RunNextFrame
--  = C_Timer.After(0) 的延时回调触发），本插件全仓零手柄 API。
-- 机制：这些调用跑在暴雪事件分发栈里，引擎把「最近执行过 OnEvent 的插件」记为肇事者，
-- 登录期事件交错，谁排在附近谁背锅 ⇒ 出补丁改代码 = 瞎改。
--
-- 【真正要命的是弹窗】ADDON_ACTION_FORBIDDEN 对话框 `exclusive = 1`
-- （Blizzard_StaticPopup_Game/GameDialogDefs.lua:714）+ GamepadMode.PopupHandler 抢焦点，
-- 手柄模式下弹窗一出现就整机假死（用户实报 + 10-05 现场）。所以对策只有一个：
-- **手柄 UI 生效期间摘掉系统对 FORBIDDEN 的监听**（纯「闭嘴」，零改动我方行为；手柄关则完全不干预）。
--
-- 【v1 的坑】v1 只挂 `PLAYER_ENTERING_WORLD` 一次性，且首触发时若手柄还没开就早退、之后
-- 永久失效 —— 「先键盘登录、后按手柄/进设置开手柄」这条最常见的路径完全没盖住。
-- 【v2 的解法】用官方手柄切换钩子 `InputUtil.RegisterGamepadInit`：
--   · RegisterInit 在「当前风格已是 Gamepad」时会**同步立即回调**（InputUtil.lua:105-110）
--     ⇒ 登录即手柄 也覆盖；
--   · 每次 INPUT_DEVICE_INTERFACE_TRANSITION 进手柄风格都会重放
--     ⇒ 中途开手柄 也覆盖。
-- 注意契约：必须先 `RegisterForInterfaceTransitions(subscriber)` 建好回调表，
-- 否则 ConstructTransitionStyle 会去索引 nil（InputUtil.lua:91，暴雪自己的用法同此）。
do
    local function UnregisterForbidden()
        if UIParent and UIParent.UnregisterEvent then
            pcall(UIParent.UnregisterEvent, UIParent, "ADDON_ACTION_FORBIDDEN")
        end
        if GameEvent and GameEvent.UnregisterInternalEvent then
            pcall(GameEvent.UnregisterInternalEvent, "ADDON_ACTION_FORBIDDEN")
        end
    end

    local function GamepadUIEnabled()
        local ok, enabled = pcall(function()
            return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
        end)
        return (ok and enabled) and true or false
    end

    local function TrySilence()
        if not GamepadUIEnabled() then return false end
        UnregisterForbidden()
        return true
    end

    local guard = CreateFrame("Frame")

    -- 手柄模式初始化/切换钩子（手柄已开时这里会立刻回调一次）
    if InputUtil and InputUtil.RegisterForInterfaceTransitions and InputUtil.RegisterGamepadInit then
        pcall(function()
            InputUtil.RegisterForInterfaceTransitions(guard)
            InputUtil.RegisterGamepadInit(guard, function()
                UnregisterForbidden()
            end)
        end)
    end

    -- 兜底：登录时若已是手柄 UI 立刻摘；否则等进世界再补一次（有些端风格登录期才定）
    guard:RegisterEvent("PLAYER_LOGIN")
    guard:SetScript("OnEvent", function(self, event)
        C_Timer.After(0, function()
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            if not TrySilence() then
                self:RegisterEvent("PLAYER_ENTERING_WORLD")
            end
        else
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            TrySilence()
        end
        end)
    end)
end

function ns.Init(fn)
    loadedFuncs[#loadedFuncs + 1] = fn
    local sink = rawget(ns, "__inits")
    if sink then sink[#sink + 1] = fn end
end

function ns.PlaySound(id)
    if type(id) ~= "number" or ns.options.buttonSound == false then return end
    local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    if kit then
        PlaySound(kit)
    else
        PlaySound(856)
    end
end

function ns.CreateButton(parent)
    local bt = CreateFrame("Button", nil, parent, "BackdropTemplate")
    bt:SetBackdrop({
        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeSize = 1,
    })
    bt:SetBackdropBorderColor(0, 0, 0, 1)
    local t = bt:CreateFontString()
    t:SetAllPoints()
    t:SetTextColor(1, 1, 1)
    t:SetFont(ns.FONT, 15, "OUTLINE")
    bt:SetFontString(t)
    ns.hui.SkinButton(bt)
    function bt:Disable() self:SetEnabled(false) end
    function bt:Enable() self:SetEnabled(true) end
    bt:SetScript("OnEnter", nil)
    bt:SetScript("OnLeave", nil)
    return bt
end

local EDIT_BG = { 0x0a / 255, 0x0a / 255, 0x0d / 255, 0.55 }
local EDIT_BORDER = { 0.30, 0.30, 0.28, 0.85 }
local EDIT_BORDER_FOCUS = { 0x46 / 255, 0xbf / 255, 0x72 / 255, 1 }
local CORNER_FILL = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFill"
local CORNER_INSET = 8

function ns.CreateEditBox(parent, size)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(size or 140, 22)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetFont(ns.FONT, 12, "")

    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(eb, CORNER_INSET, EDIT_BG, "both", false)
    else
        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(EDIT_BG[1], EDIT_BG[2], EDIT_BG[3], EDIT_BG[4])
        bg:SetPoint("TOPLEFT", eb, "TOPLEFT", CORNER_INSET, -CORNER_INSET)
        bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -CORNER_INSET, CORNER_INSET)

        local edges = {
            { "TOPLEFT", CORNER_INSET, 0, "TOPRIGHT", -CORNER_INSET, 0, nil, CORNER_INSET },
            { "BOTTOMLEFT", CORNER_INSET, 0, "BOTTOMRIGHT", -CORNER_INSET, 0, nil, CORNER_INSET },
            { "TOPLEFT", 0, -CORNER_INSET, "BOTTOMLEFT", 0, CORNER_INSET, CORNER_INSET, nil },
            { "TOPRIGHT", 0, -CORNER_INSET, "BOTTOMRIGHT", 0, CORNER_INSET, CORNER_INSET, nil },
        }
        for _, e in ipairs(edges) do
            local tex = eb:CreateTexture(nil, "BACKGROUND")
            tex:SetColorTexture(EDIT_BG[1], EDIT_BG[2], EDIT_BG[3], EDIT_BG[4])
            tex:SetPoint(e[1], eb, e[1], e[2], e[3])
            tex:SetPoint(e[4], eb, e[4], e[5], e[6])
            if e[7] then tex:SetWidth(e[7]) end
            if e[8] then tex:SetHeight(e[8]) end
        end
        for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
            local corner = eb:CreateTexture(nil, "BACKGROUND")
            corner:SetTexture(CORNER_FILL)
            corner:SetSize(CORNER_INSET, CORNER_INSET)
            corner:SetPoint(point, eb, point, 0, 0)
            corner:SetVertexColor(EDIT_BG[1], EDIT_BG[2], EDIT_BG[3])
            corner:SetAlpha(EDIT_BG[4])
        end
    end

    local border = ns.hui.BuildRoundBorder(eb, CORNER_INSET, EDIT_BORDER, nil, "OVERLAY", "both", 1) or {}
    for _, tex in ipairs(border) do tex:SetShown(true) end
    local function Paint(color)
        for _, tex in ipairs(border) do
            if tex.__huiBorderStrip then
                tex:SetColorTexture(color[1], color[2], color[3], 1)
                tex:SetAlpha(color[4] or 1)
            else
                tex:SetVertexColor(color[1], color[2], color[3])
                tex:SetAlpha(color[4] or 1)
            end
        end
    end
    eb:HookScript("OnEditFocusGained", function() Paint(EDIT_BORDER_FOCUS) end)
    eb:HookScript("OnEditFocusLost", function() Paint(EDIT_BORDER) end)
    eb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

function ns.GetWindowTheme() return "hui" end
function ns.GetWindowColorTheme() return nil end
function ns.WithColorThemeScope(_, fn) if fn then return fn() end end
function ns.WithThemeScope(_, fn) if fn then return fn() end end
function ns.After(_, fn) if fn then fn() end end
function ns.UpdateItemLib() end

do
    local gcGuard = CreateFrame("Frame")
    gcGuard:RegisterEvent("PLAYER_LOGIN")
    gcGuard:SetScript("OnEvent", function(self)
        C_Timer.After(0, function()
        self:UnregisterEvent("PLAYER_LOGIN")
        local run = function()
            collectgarbage("collect")
            collectgarbage("collect")
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(5, run)
        else
            run()
        end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.3, function()
                        local J = ns.IdleJobs
                        if not J then return end
                        local probe = DungeonsForeverDB and DungeonsForeverDB.dfMemProbe
                        local gear = ns.GearModule
                        local ensure = ns.EnsureGearData
                        if type(ensure) == "function" then
                J.Add(function()
                    if gear and gear.built then return true end
                    ensure()
                    if probe then ns.MemMark("gearData") end
                    if gear and type(gear.BuildCatalog) == "function"
                       and not gear.built and not gear.catalog then
                        pcall(gear.BuildCatalog, gear)
                    end
                    if probe then ns.MemMark("catalog") end
                    if gear and type(gear.StartTexWarm) == "function" then
                        pcall(gear.StartTexWarm)
                    end
                    if gear and type(gear.StartIconWarm) == "function" then
                        pcall(gear.StartIconWarm)
                    end
                    if gear and type(gear.StartGlyphWarm) == "function" then
                        pcall(gear.StartGlyphWarm)
                    end
                    if gear and type(gear.StartDataWarm) == "function" then
                        pcall(gear.StartDataWarm)
                    end
                    return true
                end)
                J.Add(function()
                    if gear and gear.built then return true end
                    local mf = _G.DungeonsForever_MainFrame
                    if mf and mf.IsShown and mf:IsShown() then return false end
                    if gear and type(gear.Build) == "function" then
                        pcall(gear.Build, gear)
                        gear.__lastRefreshT = nil
                        if type(gear.Refresh) == "function" then
                            pcall(gear.Refresh, gear, true)
                        end
                        local pool = gear.rowPool
                        if pool then
                            for i = 1, #pool do
                                local r = pool[i]
                                if r and r.Hide then r:Hide() end
                            end
                        end
                    end
                    if DungeonsForeverDB and DungeonsForeverDB.dfMemProbe then
                        ns.MemMark("gearSkel")
                    end
                    return true
                end)
                end
                local profEnsure = ns.EnsureProfRecipes
                if type(profEnsure) == "function" then
                    J.Add(function()
                        local mf = _G.DungeonsForever_MainFrame
                        if mf and mf.IsShown and mf:IsShown() then return false end
                        profEnsure()
                        if DungeonsForeverDB and DungeonsForeverDB.dfMemProbe then
                            ns.MemMark("profData")
                        end
                        return true
                    end)
                end
                local UD = ns.DungeonUI
                if UD and type(UD.EnsureBuilt) == "function"
                   and type(C_Timer) == "table" and C_Timer.After then
                    local pages = { "Raids", "Professions", "Explore",
                        "Collections", "Factions", "Bis", "Tier", "PvP" }
                    C_Timer.After(0.6, function()
                        pcall(function()
                            if not UD.built and type(UD.Build) == "function" then
                                UD:Build()
                            end
                        end)
                        if not (DungeonsForeverDB and DungeonsForeverDB.dfPrebuild) then return end
                        local probeUD = DungeonsForeverDB and DungeonsForeverDB.dfMemProbe
                        local pb = { pages = {} }
                        local i = 0
                        local function step()
                            local mf = _G.DungeonsForever_MainFrame
                            if mf and mf.IsShown and mf:IsShown() then
                                C_Timer.After(0.5, step)
                                return
                            end
                            i = i + 1
                            local k = pages[i]
                            if not k then
                                if DungeonsForeverDB then
                                    DungeonsForeverDB.dfPbLog = table.concat(pb.pages, " ")
                                end
                                return
                            end
                            pcall(UD.EnsureBuilt, UD, k)
                            if probeUD then ns.MemMark("pb_" .. k) end
                            pb.pages[#pb.pages + 1] = k .. ":" .. tostring(UD.subBuilt and UD.subBuilt[k] == true and 1 or 0)
                            if ns.IdleJobs then ns.IdleJobs.Urgent(step) end
                        end
                        if ns.IdleJobs then ns.IdleJobs.Urgent(step) end
                    end)
                end
            end)
        end
        if DungeonsForeverDB and DungeonsForeverDB.dfAutoTest
           and C_Timer and C_Timer.After then
            DungeonsForeverDB.dfAutoTest = nil
            pcall(function()
                if io and io.open then
                    local f = io.open("DF_AUTOTEST_RESULT.txt", "w")
                    if f then f:write("running") f:close() end
                end
            end)
            C_Timer.After(1, function()
                local f = CreateFrame("Frame")
                f.samples = {}
                f.last = debugprofilestop()
                f:SetScript("OnUpdate", function(self)
                    local now = debugprofilestop()
                    local d = now - self.last
                    self.last = now
                    if d > 0 and d < 5000 then
                        self.samples[#self.samples + 1] = d
                    end
                end)
                local wlog = {}
                local cfOrig = CreateFrame
                local cfN, cfT, cfMax = 0, 0, 0
                CreateFrame = function(...)
                    local s = debugprofilestop()
                    local r = cfOrig(...)
                    local d = debugprofilestop() - s
                    cfT = cfT + d
                    if d > cfMax then cfMax = d end
                    cfN = cfN + 1
                    return r
                end
                local function wrapw(tbl, fn, label)
                    local orig = tbl[fn]
                    if type(orig) ~= "function" then return end
                    tbl[fn] = function(...)
                        local s = debugprofilestop()
                        local r1, r2, r3, r4 = orig(...)
                        wlog[#wlog + 1] = string.format("%.2fs %s %.0fms",
                            (debugprofilestop() - f.last0) / 1000, label, debugprofilestop() - s)
                        return r1, r2, r3, r4
                    end
                end
                C_Timer.After(DungeonsForeverDB.dfAutoTestDelay or 0.5, function()
                    f.samples = {}
                    f.last = debugprofilestop()
                    f.last0 = debugprofilestop()
                    local mf = _G.DungeonsForever_MainFrame
                    if ns.GearModule then wrapw(ns.GearModule, "Refresh", "GRefresh") end
                    if ns.GearModule then wrapw(ns.GearModule, "BuildCatalog", "BuildCatalog") end
                    wrapw(ns, "EnsureGearData", "GearEnsure")
                    wrapw(ns, "EnsureProfRecipes", "ProfEnsure")
                    local preCatalog = (ns.GearModule and ns.GearModule.catalog ~= nil) or false
                    local white
                    if DungeonsForeverDB.dfWhite then
                        white = CreateFrame("Frame", nil, UIParent)
                        white:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                        white:SetBackdropColor(0.06, 0.07, 0.10, 0.95)
                        if mf and mf.GetWidth and mf:GetWidth() > 0 then
                            white:SetSize(mf:GetWidth(), mf:GetHeight())
                        else
                            white:SetSize(900, 560)
                        end
                        white:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                        white:SetFrameStrata("HIGH")
                    end
                    local t0 = debugprofilestop()
                    if white then
                        white:Show()
                    elseif ns.Open then ns.Open() elseif mf then mf:Show() end
                    if not white and ns.DungeonUI then ns.DungeonUI:SwitchSub("Gear") end
                    local openMs = debugprofilestop() - t0
                    wlog[#wlog + 1] = string.format("%.2fs icons %s/%s",
                        (debugprofilestop() - f.last0) / 1000,
                        tostring(ns.GearModule and ns.GearModule.__iconWarmN or "?"),
                        tostring(ns.GearModule and ns.GearModule.__iconWarmTotal or "?"))
                    C_Timer.After(5, function()
                        local n1 = #f.samples
                        local t1 = debugprofilestop()
                        if white then white:Hide() elseif mf then mf:Hide() end
                        local closeMs = debugprofilestop() - t1
                        C_Timer.After(0.5, function()
                            local n2 = #f.samples
                            local t2 = debugprofilestop()
                            if white then
                                white:Show()
                            elseif ns.Open then ns.Open() elseif mf then mf:Show() end
                            if not white and ns.DungeonUI then ns.DungeonUI:SwitchSub("Gear") end
                            local reopenMs = debugprofilestop() - t2
                            C_Timer.After(4, function()
                                f:SetScript("OnUpdate", nil)
                                if white then white:Hide() end
                                CreateFrame = cfOrig
                                wlog[#wlog + 1] = string.format("cf=%d %.0fms max%.1f", cfN, cfT, cfMax)
                                local function seg(a, b)
                                    local mx, c40 = 0, 0
                                    local top = {}
                                    for i = a, b do
                                        local v = f.samples[i]
                                        if v then
                                            if v > mx then mx = v end
                                            if v > 40 and #top < 24 then
                                                c40 = c40 + 1
                                                top[#top + 1] = string.format("%.2fs:%.0f", (i - a) * 0.0167, v)
                                            end
                                        end
                                    end
                                    return mx, c40, table.concat(top, " ")
                                end
                                local m1, c1, s1 = seg(1, n1)
                                local m2, c2, s2 = seg(n1 + 1, n2)
                                local m3, c3, s3 = seg(n2 + 1, #f.samples)
                                DungeonsForeverDB.dfAutoTestResult = {
                                    t = type(date) == "function" and date("%H:%M:%S") or "",
                                    prime = "none",
                                    openMs = openMs, closeMs = closeMs, reopenMs = reopenMs,
                                    preCatalog = preCatalog,
                                    segOpen = { max = m1, c40 = c1, spikes = s1 },
                                    segClosed = { max = m2, c40 = c2, spikes = s2 },
                                    segReopen = { max = m3, c40 = c3, spikes = s3 },
                                    paintMs = (ns.GearModule and ns.GearModule.__paintMs) or "",
                                    diag = table.concat(wlog, " | "),
                                }
                                pcall(function()
                                    if not (io and io.open) then return end
                                    local r = DungeonsForeverDB.dfAutoTestResult
                                    local fh = io.open("DF_AUTOTEST_RESULT.txt", "w")
                                    if not fh then return end
                                    fh:write(string.format(
                                        "t=%s prime=%s openMs=%.1f closeMs=%.1f reopenMs=%.1f Omax=%.1f Oc40=%d Ospk=[%s] Cmax=%.1f Cc40=%d Rmax=%.1f Rc40=%d Rspk=[%s] diag=%s",
                                        r.t or "", r.prime or "none",
                                        r.openMs or 0, r.closeMs or 0, r.reopenMs or 0,
                                        r.segOpen.max or 0, r.segOpen.c40 or 0, r.segOpen.spikes or "",
                                        r.segClosed.max or 0, r.segClosed.c40 or 0,
                                        r.segReopen.max or 0, r.segReopen.c40 or 0, r.segReopen.spikes or "",
                                        r.diag or ""))
                                    fh:close()
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end
        end)
    end)
end

ns.IdleJobs = nil
do
    local J = {}
    ns.IdleJobs = J
    local qNorm, qUrg = {}, {}
    local function inCombat()
        return InCombatLockdown and InCombatLockdown() or false
    end
    local function pump(q, t0, budget, deferred)
        while #q > 0 do
            if debugprofilestop() - t0 > budget then return end
            local fn = table.remove(q, 1)
            local ok, done = pcall(fn)
            if ok and done ~= true then
                deferred[#deferred + 1] = fn
            end
        end
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function()
        local urgent = #qUrg > 0
        if not urgent and inCombat() then return end
        local budget = urgent and 12 or 6
        local t0 = debugprofilestop()
        local dUrg, dNorm = {}, {}
        pump(qUrg, t0, budget, dUrg)
        if #qUrg == 0 then
            pump(qNorm, t0, budget, dNorm)
        end
        for i = 1, #dUrg do qUrg[#qUrg + 1] = dUrg[i] end
        for i = 1, #dNorm do qNorm[#qNorm + 1] = dNorm[i] end
    end)
    function J.Add(fn)
        if type(fn) == "function" then qNorm[#qNorm + 1] = fn end
    end
    function J.Urgent(fn)
        if type(fn) == "function" then qUrg[#qUrg + 1] = fn end
    end
    function J.StepGC(frames, kb)
        local left = frames or 120
        J.Add(function()
            if left <= 0 then return true end
            left = left - 1
            collectgarbage("step", kb or 512)
            return false
        end)
    end
end

SLASH_DFMEMLUA1 = "/dfmem"
SlashCmdList["DFMEMLUA"] = function()
    if type(UpdateAddOnMemoryUsage) == "function" then UpdateAddOnMemoryUsage() end
    local mem1 = type(GetAddOnMemoryUsage) == "function"
        and GetAddOnMemoryUsage("DungeonsForever") or 0
    local heap1 = collectgarbage("count")
    collectgarbage("collect")
    collectgarbage("collect")
    local mem2 = type(GetAddOnMemoryUsage) == "function"
        and GetAddOnMemoryUsage("DungeonsForever") or 0
    local heap2 = collectgarbage("count")
    DungeonsForeverDB = DungeonsForeverDB or {}
    DungeonsForeverDB.memProbe = DungeonsForeverDB.memProbe or {}
    local log = DungeonsForeverDB.memProbe
    log[#log + 1] = {
        t = date("%m-%d %H:%M:%S"),
        ver = GetAddOnMetadata and GetAddOnMetadata("DungeonsForever", "Version") or "?",
        mem = mem1, heap = heap1,
        memAfterGC = mem2, heapAfterGC = heap2,
    }
    if #log > 50 then table.remove(log, 1) end
    print(format("[DFMem] %.2f MB -> GC后 %.2f MB (Lua堆 %.2f -> %.2f MB)",
        mem1 / 1024, mem2 / 1024, heap1 / 1024, heap2 / 1024))
end

function ns.MemMark(label)
    collectgarbage("collect")
    DungeonsForeverDB = DungeonsForeverDB or {}
    local m = DungeonsForeverDB.memMarks
    if not m then
        m = {}
        DungeonsForeverDB.memMarks = m
    end
    local ts = ""
    if type(date) == "function" then ts = date("%H:%M:%S") end
    m[#m + 1] = {
        t = ts,
        label = label,
        heap = collectgarbage("count"),
    }
    if #m > 80 then table.remove(m, 1) end
end

ns.OpenPerf = nil
do
    local OP = {}
    ns.OpenPerf = OP
    local function commit(s, altTotal)
        local total
        if #s > 0 then
            total = s[#s][2]
        elseif altTotal then
            total = altTotal
        else
            total = debugprofilestop and (debugprofilestop() - s.t0) or 0
        end
        local ms = math.floor(total + 0.5)
        local parts = {}
        for i = 1, #s do
            parts[#parts + 1] = s[i][1] .. " " .. math.floor(s[i][2] + 0.5)
        end
        local marks = table.concat(parts, ", ")
        DungeonsForeverDB = DungeonsForeverDB or {}
        local arr = DungeonsForeverDB.openPerf
        if not arr then
            arr = {}
            DungeonsForeverDB.openPerf = arr
        end
        local ts = ""
        if type(date) == "function" then ts = date("%H:%M:%S") end
        arr[#arr + 1] = { t = ts, page = s.label, ms = ms, marks = marks }
        if #arr > 50 then table.remove(arr, 1) end
    end

    function OP.Begin(label)
        if not (debugprofilestop and C_Timer and C_Timer.After) then return end
        local now = debugprofilestop()
        if OP.__cur then
            local prev = OP.__cur
            OP.__cur = nil
            commit(prev, now - prev.t0)
        end
        local s = { label = tostring(label), t0 = now }
        OP.__cur = s
        C_Timer.After(0.75, function()
            if OP.__cur == s then
                OP.__cur = nil
                commit(s, now - s.t0 + 0.75)
            end
        end)
    end

    function OP.Mark(name)
        local s = OP.__cur
        if s and debugprofilestop then
            s[#s + 1] = { tostring(name), debugprofilestop() - s.t0 }
            if name == "就绪" then
                OP.__cur = nil
                commit(s)
            end
        end
    end
end
