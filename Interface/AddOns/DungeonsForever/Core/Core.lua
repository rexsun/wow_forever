-- =============================================================================
-- DungeonsForever · 基础层
-- 客户端判定 / 字体 / 初始化回调 / 音效 / 按钮与输入框工厂 / 下拉菜单入口。
-- 本插件为独立单窗口插件，外观固定 HUI 主题。
-- =============================================================================

local addonName, ns = ...

ns.LibBG = LibStub:GetLibrary("LibUIDropDownMenu-4.0")

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
ns.QUICK_TABS = { "Dungeons", "Raids", "Professions", "Explore", "Collections", "Bis", "Tier", "PvP" } -- ★ 主窗标签页显隐（QB_SET_TABS，2026-10-08 用户；同日 +PvP 第八键，主窗胶囊本就有 PvP）

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

function ns.dropDownToggle(dropDown)
    dropDown:SetScript("OnMouseDown", function(self)
        if self.isDisabled then return end
        ns.LibBG:ToggleDropDownMenu(nil, nil, self)
        ns.PlaySound(1)
    end)
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
