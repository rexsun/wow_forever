-- =============================================================================
-- DungeonsForever · HUI 主题适配层
-- 层级色板（L0~L5）/ 圆角描边拼装 / 面板与控件换肤 /
-- 滑动胶囊页签 / 图标圆角蒙版。模块不直接调用 LibHUI，统一经此命名空间创建。
-- 本插件外观固定为 HUI，不保留 classic 双轨。
-- =============================================================================

local _, ns = ...

local LibBG = ns.LibBG

local tinsert = table.insert
local format = format
local wipe = wipe

ns.hui = ns.hui or {}

-- ★★ UTF-8 按「字」估宽 / 截断（双端通用，2026-10-03 从 ProfessionUI 上移）：
--   ProfessionUI 只对无限端加载（ns.LoadForeverPages 守卫），但副本掉落页 4 列卡片
--   的名称截断（DG.FitText）两端都要用 —— 泰坦端取不到 ns.ProfModule 时会退回原串溢出。
--   估宽口径：全角 1.0×字号 / 半角 0.55×字号（与专业页同一套）。
local function HCharStep(text, i)
    local b = text:byte(i)
    local step = 1
    if b >= 0xF0 then step = 4
    elseif b >= 0xE0 then step = 3
    elseif b >= 0xC0 then step = 2 end
    return text:sub(i, i + step - 1), step, ((b >= 0x80) and 1 or 0.55)
end

function ns.hui.TextW(text, fs)
    if type(text) ~= "string" then return 0 end
    local w, i, n = 0, 1, #text
    while i <= n do
        local _, step, k = HCharStep(text, i)
        w = w + k * fs
        i = i + step
    end
    return w
end

function ns.hui.Fit(text, fs, width)
    if type(text) ~= "string" then return "" end
    if ns.hui.TextW(text, fs) <= width then return text end
    local out, w, i, n = "", 0, 1, #text
    while i <= n do
        local ch, step, k = HCharStep(text, i)
        local cw = k * fs
        if w + cw > width - fs then break end
        out = out .. ch
        w = w + cw
        i = i + step
    end
    return out .. "…"
end

ns.hui.CharStep = HCharStep

if BackdropTemplateMixin and BackdropTemplateMixin.SetupTextureCoordinates
        and not BackdropTemplateMixin.__dfSafeTexCoords then
    BackdropTemplateMixin.__dfSafeTexCoords = true
    local origSetupTexCoords = BackdropTemplateMixin.SetupTextureCoordinates
    function BackdropTemplateMixin:SetupTextureCoordinates()
        pcall(origSetupTexCoords, self)
    end
end

do
    local HUI_L1 = {0x2b / 255, 0x2b / 255, 0x2b / 255, 0.95}
    local HUI_ACCENT = {0x46 / 255, 0xbf / 255, 0x72 / 255, 0.95}
    local ACCENT_GREEN = {0x46 / 255, 0xbf / 255, 0x72 / 255}
    local HUI_CORNER_TL = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFill"
    local HUI_CORNER_TR = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFillTR"
    local HUI_CORNER_BL = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFillBL"
    local HUI_CORNER_BR = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFillBR"
    local HUI_CIRCLE = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUICircle"
    local C_TRACKOFF = {0x4a / 255, 0x4d / 255, 0x52 / 255}
    local C_KNOB = {0x17 / 255, 0x18 / 255, 0x1c / 255}
    local C_TOGGLE_BORDER = {0.42, 0.42, 0.46}
    local HUI_PILL_L = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIPillL"
    local HUI_PILL_R = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIPillR"
    local HUI_CORNER = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCornerFill"
    local C_GRAY = {0.63, 0.63, 0.63}
    local C_RED = {0xf2 / 255, 0x53 / 255, 0x4e / 255}
    local C_CARD_BORDER = {1, 1, 1, 0.10}

    ns.hui.palette = {
        default        = { name = "灰",      deep = {0.63, 0.63, 0.63}, hue = 0,   sat = 0,    gray = true, order = 0 },
        pink           = { name = "暗粉",       deep = {0xDC / 255, 0xBC / 255, 0xC8 / 255}, hue = 338, sat = 0.38, lum = 1.5,  accent = {0xF0 / 255, 0xA8 / 255, 0xBC / 255}, order = 1 },
        orange         = { name = "橙",         deep = {0xDE / 255, 0xCB / 255, 0xBA / 255}, hue = 28,  sat = 0.42, lum = 1.3,  accent = {0xEE / 255, 0xA4 / 255, 0x63 / 255}, order = 2 },
        orangered      = { name = "橙红",       deep = {0xDD / 255, 0xC3 / 255, 0xBB / 255}, hue = 14,  sat = 0.40, lum = 1.3,  accent = {0xE9 / 255, 0x7E / 255, 0x5D / 255}, order = 3 },
        red            = { name = "红",         deep = {0xDC / 255, 0xBD / 255, 0xBC / 255}, hue = 2,   sat = 0.38, lum = 1.3,  accent = {0xE4 / 255, 0x5D / 255, 0x58 / 255}, order = 4 },
        qq             = { name = "湖蓝",       deep = {0xB1 / 255, 0xDA / 255, 0xF6 / 255}, hue = 204, sat = 0.34, accent = {0x71 / 255, 0xB3 / 255, 0xE0 / 255}, order = 5 },
        qqbright       = { name = "湖蓝亮",     deep = {0xC6 / 255, 0xE6 / 255, 0xF9 / 255}, hue = 204, sat = 0.30, lum = 1.35, accent = {0x8C / 255, 0xC6 / 255, 0xEC / 255}, order = 6 },
        zhangliangying = { name = "金棕",       deep = {0xD6 / 255, 0xB6 / 255, 0x65 / 255}, hue = 43,  sat = 0.42, accent = {0xE2 / 255, 0xBB / 255, 0x5A / 255}, order = 7 },
        graybright     = { name = "亮灰",       deep = {0.78, 0.78, 0.78}, hue = 0, sat = 0, lum = 1.5, order = 8 },
        youfeng        = { name = "青绿",       deep = {0xC3 / 255, 0xDC / 255, 0xC6 / 255}, hue = 135, sat = 0.22, accent = {0x61 / 255, 0xD1 / 255, 0x7D / 255}, order = 9 },
        tonghang       = { name = "青蓝",       deep = {0xB8 / 255, 0xE0 / 255, 0xE8 / 255}, hue = 190, sat = 0.30, accent = {0x70 / 255, 0xC9 / 255, 0xDB / 255}, order = 10 },
        youfengbright  = { name = "青绿亮",     deep = {0xD8 / 255, 0xEC / 255, 0xDA / 255}, hue = 135, sat = 0.18, lum = 1.35, accent = {0x86 / 255, 0xE0 / 255, 0x9C / 255}, order = 11 },
        tonghangbright = { name = "青蓝亮",     deep = {0xD2 / 255, 0xEE / 255, 0xF3 / 255}, hue = 190, sat = 0.26, lum = 1.35, accent = {0x97 / 255, 0xDC / 255, 0xEA / 255}, order = 12 },
        lianyi         = { name = "水蓝",       deep = {0xA1 / 255, 0xC3 / 255, 0xF6 / 255}, hue = 216, sat = 0.36, accent = {0x7F / 255, 0xA6 / 255, 0xE1 / 255}, order = 13 },
        lianyibright   = { name = "水蓝亮",     deep = {0xC0 / 255, 0xDC / 255, 0xF8 / 255}, hue = 216, sat = 0.32, lum = 1.35, accent = {0x9C / 255, 0xC0 / 255, 0xEC / 255}, order = 14 },
        black          = { name = "黑", deep = {0x46 / 255, 0xbf / 255, 0x72 / 255}, hue = 0, sat = 0, accent = {0x46 / 255, 0xbf / 255, 0x72 / 255}, order = 15,
                            blackBase = { L0 = 0x0A / 255, L1 = 0x12 / 255, L2 = 0x1A / 255, L3 = 0x24 / 255, DIV = 0x20 / 255, L4 = 0x2E / 255, L5 = 0x38 / 255 } },
    }
    local L0_GRAY = {0x16 / 255, 0x16 / 255, 0x16 / 255, 0.95}
    local L1_GRAY = {0x2b / 255, 0x2b / 255, 0x2b / 255, 0.95}
    local L2_GRAY = {0x36 / 255, 0x36 / 255, 0x36 / 255, 1}
    local L2_GRAY095 = {0x36 / 255, 0x36 / 255, 0x36 / 255, 0.95}
    local L3_GRAY = {0x40 / 255, 0x40 / 255, 0x40 / 255, 0.95}
    local DIV_GRAY = {0x3a / 255, 0x3a / 255, 0x3a / 255, 1}
    local L4_GRAY = {0x4a / 255, 0x4a / 255, 0x4a / 255, 0.95}
    local L5_GRAY = {0x54 / 255, 0x54 / 255, 0x54 / 255, 0.95}
    local LV = { L0 = 0x16 / 255, L1 = 0x2b / 255, L2 = 0x36 / 255, L3 = 0x40 / 255, DIV = 0x3a / 255, L4 = 0x4a / 255, L5 = 0x54 / 255 }
    ns.hui.layer = {
        L0 = {L0_GRAY[1], L0_GRAY[2], L0_GRAY[3], L0_GRAY[4]},
        L1 = {L1_GRAY[1], L1_GRAY[2], L1_GRAY[3], L1_GRAY[4]},
        L2 = {L2_GRAY[1], L2_GRAY[2], L2_GRAY[3], L2_GRAY[4]},
        L3 = {L3_GRAY[1], L3_GRAY[2], L3_GRAY[3], L3_GRAY[4]},
        L4 = {L4_GRAY[1], L4_GRAY[2], L4_GRAY[3], L4_GRAY[4]},
        L5 = {L5_GRAY[1], L5_GRAY[2], L5_GRAY[3], L5_GRAY[4]},
        DIV = {DIV_GRAY[1], DIV_GRAY[2], DIV_GRAY[3], DIV_GRAY[4]},
        ACCENT = {0x46 / 255, 0xbf / 255, 0x72 / 255},
    }
    ns.hui.L1_GRAY, ns.hui.L2_GRAY, ns.hui.L2_GRAY095 = L1_GRAY, L2_GRAY, L2_GRAY095
    local function hsl2rgb(h, s, l)
        h = h / 360
        local r, g, b
        if s <= 0 then
            r, g, b = l, l, l
        else
            local q = l < 0.5 and l * (1 + s) or l + s - l * s
            local p = 2 * l - q
            local function hue2rgb(t)
                if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
                if t < 1 / 6 then return p + (q - p) * 6 * t
                elseif t < 1 / 2 then return q
                elseif t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6
                else return p end
            end
            r = hue2rgb(h + 1 / 3); g = hue2rgb(h); b = hue2rgb(h - 1 / 3)
        end
        return r, g, b
    end
    local function sameGray(c, g)
        if not c or not g then return false end
        local tol = 0.004
        return math.abs((c[1] or 0) - g[1]) < tol and math.abs((c[2] or 0) - g[2]) < tol and math.abs((c[3] or 0) - g[3]) < tol
    end
    local function DeriveLayerColors(key)
        local p = key and ns.hui.palette[key]
        local out = {}
        local function emit(name, rgb)
            local dst = ns.hui.layer and ns.hui.layer[name]
            out[name] = { rgb[1], rgb[2], rgb[3], dst and dst[4] or 1 }
        end
        if not p then
            emit("L0", L0_GRAY)
            emit("L1", L1_GRAY)
            emit("L2", L2_GRAY)
            emit("L3", L3_GRAY)
            emit("L4", L4_GRAY)
            emit("L5", L5_GRAY)
            emit("DIV", DIV_GRAY)
        else
            local hue, sat = p.hue, p.sat
            local function tint(lvKey, lv)
                if p.blackBase then
                    local v = p.blackBase[lvKey]
                    if v then return { v, v, v } end
                end
                local r, g, b = hsl2rgb(hue, sat, math.min(1, lv * (p.lum or 1)))
                return { r, g, b }
            end
            emit("L0", tint("L0", LV.L0)); emit("L1", tint("L1", LV.L1))
            emit("L2", tint("L2", LV.L2)); emit("L3", tint("L3", LV.L3))
            emit("L4", tint("L4", LV.L4)); emit("L5", tint("L5", LV.L5))
            emit("DIV", tint("DIV", LV.DIV))
        end
        local ac = (p and p.accent) or ACCENT_GREEN
        out.ACCENT = { ac[1], ac[2], ac[3] }
        return out
    end
    local function ApplyLayerTheme(key)
        local snap = DeriveLayerColors(key)
        for _, name in ipairs({ "L0", "L1", "L2", "L3", "L4", "L5", "DIV", "ACCENT" }) do
            local dst = ns.hui.layer[name]
            local v = snap[name]
            dst[1], dst[2], dst[3] = v[1], v[2], v[3]
        end
        local ac = snap.ACCENT
        ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3] = ac[1], ac[2], ac[3]
        ns.hui.layer.ACCENT[1], ns.hui.layer.ACCENT[2], ns.hui.layer.ACCENT[3] = ac[1], ac[2], ac[3]
        HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3] = ac[1], ac[2], ac[3]
    end
    local __layerSnapshots = {}
    function ns.hui.LayerSnapshotOf(key)
        local ck = key or "_default"
        local snap = __layerSnapshots[ck]
        if not snap then
            snap = DeriveLayerColors(key)
            __layerSnapshots[ck] = snap
        end
        return snap
    end
    local function ScopeKeyForScope(scope)
        if not (ns.options and ns.options.perWindowColorTheme == 1) then return nil end
        if ns.GetWindowTheme and ns.GetWindowTheme(scope) ~= "hui" then return nil end
        local gk = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme or nil
        local key = ns.GetWindowColorTheme and ns.GetWindowColorTheme(scope) or nil
        if key == nil or key == gk then return nil end
        if not (ns.hui.palette and ns.hui.palette[key]) then return nil end
        return key
    end
    function ns.hui.ScopeLayerForScope(scope)
        local key = ScopeKeyForScope(scope)
        return key and ns.hui.LayerSnapshotOf(key) or nil
    end
    function ns.hui.ScopeAccentRGBForScope(scope)
        local key = ScopeKeyForScope(scope)
        if not key then return nil end
        local p = key and ns.hui.palette and ns.hui.palette[key]
        local ac = (p and p.accent) or ACCENT_GREEN
        return { ac[1], ac[2], ac[3] }
    end

    function ns.hui.ApplyColorTheme(key)
        local prevAccentHex = ns.hui.TextHex(ns.g1 or "00FF00", "accent")
        local prevR, prevG, prevB = ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3]
        ApplyLayerTheme(key)
        if DungeonsForeverDB.libHUI then DungeonsForeverDB.libHUI.colorTheme = key end
        ns.hui.RefreshSkin()
        if ns.hui.RefreshFontObjects then ns.hui.RefreshFontObjects() end
        for _, fn in ipairs(ns.hui.__themeListeners) do pcall(fn) end
        local newAccentHex = ns.hui.TextHex(ns.g1 or "00FF00", "accent")
        ns.hui.RecolorAllThemeText(prevAccentHex, newAccentHex, prevR, prevG, prevB)
    end

    ns.hui.__scopeAccentHex = ns.hui.__scopeAccentHex or {}
    ns.hui.__scopeAccentRGB = ns.hui.__scopeAccentRGB or {}
    local function ScopeAccentOf(key)
        local p = key and ns.hui.palette and ns.hui.palette[key]
        local ac = (p and p.accent) or ACCENT_GREEN
        return format("%02x%02x%02x", ac[1] * 255 + 0.5, ac[2] * 255 + 0.5, ac[3] * 255 + 0.5),
            { ac[1], ac[2], ac[3] }
    end
    local function CollectSkinFrames(root, out)
        if not root or not root.GetChildren then return end
        if root.__huiRepaints or root.__huiRepaint then out[#out + 1] = root end
        local children = { root:GetChildren() }
        for i = 1, #children do CollectSkinFrames(children[i], out) end
    end
    local function InFrameTree(f, root)
        while f do
            if f == root then return true end
            f = f.GetParent and f:GetParent() or nil
        end
        return false
    end
    local function RecolorTextUnder(root, prevList, prevRGBs, newHex)
        if not root or not root.GetRegions then return end
        local function walk(f)
            if not f or not f.GetRegions then return end
            local regions = { f:GetRegions() }
            for i = 1, #regions do
                local r = regions[i]
                if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                    local t = r:GetText()
                    if t then
                        local changed
                        for _, prevHex in ipairs(prevList) do
                            if prevHex ~= newHex and t:lower():find("|cff" .. prevHex, 1, true) then
                                local hexClass = ""
                                for j = 1, #prevHex do
                                    local ch = prevHex:sub(j, j)
                                    hexClass = hexClass .. "[" .. ch:upper() .. ch:lower() .. "]"
                                end
                                t = t:gsub("%|c[fF][fF]" .. hexClass, "|cff" .. newHex)
                                changed = true
                            end
                        end
                        if changed then r:SetText(t) end
                    end
                    if prevRGBs then
                        local cr, cg, cb = r:GetTextColor()
                        if cr then
                            for _, pc in ipairs(prevRGBs) do
                                local near = math.abs(cr - pc[1]) < 0.02
                                    and math.abs(cg - pc[2]) < 0.02 and math.abs(cb - pc[3]) < 0.02
                                if pc and near then
                                    r:SetTextColor(ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3])
                                    break
                                end
                            end
                        end
                    end
                end
            end
            local children = { f:GetChildren() }
            for i = 1, #children do walk(children[i]) end
        end
        walk(root)
    end

    function ns.WithColorThemeScope(scope, fn, ...)
        local global = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme or nil
        local key = ns.GetWindowColorTheme and ns.GetWindowColorTheme(scope) or global
        if key == global then return fn(...) end
        if key ~= nil and not (ns.hui.palette and ns.hui.palette[key]) then return fn(...) end
        if ns.GetWindowTheme and ns.GetWindowTheme(scope) ~= "hui" then return fn(...) end
        local saved = {}
        for k, v in pairs(ns.hui.layer) do
            saved[k] = { v[1], v[2], v[3], v[4] }
        end
        local savedAccent = { ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3] }
        local savedHuiAccent = { HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3] }
        local savedKey = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme or nil
        if DungeonsForeverDB.libHUI then DungeonsForeverDB.libHUI.colorTheme = key end
        ApplyLayerTheme(key)
        local scopeHex, scopeRGB = ScopeAccentOf(key)
        ns.hui.__scopeAccentHex[scope] = scopeHex
        ns.hui.__scopeAccentRGB[scope] = scopeRGB
        local ok, result = pcall(fn, ...)
        for k, v in pairs(saved) do
            local dst = ns.hui.layer[k]
            dst[1], dst[2], dst[3], dst[4] = v[1], v[2], v[3], v[4]
        end
        ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3] = savedAccent[1], savedAccent[2], savedAccent[3]
        HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3] = savedHuiAccent[1], savedHuiAccent[2], savedHuiAccent[3]
        if DungeonsForeverDB.libHUI then DungeonsForeverDB.libHUI.colorTheme = savedKey end
        if not ok then
            error(result, 0)
        end
        return result
    end

    function ns.hui.RefreshColorThemeScope(scope, ...)
        local roots = {}
        for i = 1, select("#", ...) do
            local r = select(i, ...)
            if r and r.GetChildren then roots[#roots + 1] = r end
        end
        if #roots == 0 then return end
        if not ns.GetWindowColorTheme then return end
        if ns.GetWindowTheme and ns.GetWindowTheme(scope) ~= "hui" then return end
        local globalKey = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme or nil
        local key = ns.GetWindowColorTheme(scope)
        if key ~= nil and not (ns.hui.palette and ns.hui.palette[key]) then return end
        local prevGlobalHex, prevGlobalRGB = ScopeAccentOf(globalKey)
        local prevScopeHex, prevScopeRGB = ns.hui.__scopeAccentHex[scope], ns.hui.__scopeAccentRGB[scope]
        local needSwap = key ~= globalKey
        local saved, savedAccent, savedHuiAccent, savedKey
        if needSwap then
            saved = {}
            for k, v in pairs(ns.hui.layer) do
                saved[k] = { v[1], v[2], v[3], v[4] }
            end
            savedAccent = { ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3] }
            savedHuiAccent = { HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3] }
            savedKey = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme or nil
            if DungeonsForeverDB.libHUI then DungeonsForeverDB.libHUI.colorTheme = key end
            ApplyLayerTheme(key)
        end
        for _, root in ipairs(roots) do
            local frames = {}
            CollectSkinFrames(root, frames)
            for _, f in ipairs(frames) do
                if f.__huiRepaints then
                    for _, fn in ipairs(f.__huiRepaints) do pcall(fn) end
                elseif f.__huiRepaint then
                    pcall(f.__huiRepaint, f)
                end
            end
            for fs, list in pairs(ns.hui.__textRepaints) do
                if fs and InFrameTree(fs, root) then
                    for _, apply in ipairs(list) do pcall(apply) end
                end
            end
        end
        if needSwap then
            for k, v in pairs(saved) do
                local dst = ns.hui.layer[k]
                dst[1], dst[2], dst[3], dst[4] = v[1], v[2], v[3], v[4]
            end
            ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3] = savedAccent[1], savedAccent[2], savedAccent[3]
            HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3] = savedHuiAccent[1], savedHuiAccent[2], savedHuiAccent[3]
            if DungeonsForeverDB.libHUI then DungeonsForeverDB.libHUI.colorTheme = savedKey end
        end
        local newHex, newRGB = ScopeAccentOf(key)
        local prevList = { prevGlobalHex }
        local prevRGBs = { prevGlobalRGB }
        if prevScopeHex and prevScopeHex ~= prevGlobalHex then
            prevList[#prevList + 1] = prevScopeHex
            prevRGBs[#prevRGBs + 1] = prevScopeRGB
        end
        for _, root in ipairs(roots) do
            RecolorTextUnder(root, prevList, prevRGBs, newHex)
        end
        ns.hui.__scopeAccentHex[scope] = newHex
        ns.hui.__scopeAccentRGB[scope] = newRGB
    end
    ns.hui.__skinRegistry = ns.hui.__skinRegistry or {}
    function ns.hui.AddRepaint(f, fn)
        if not f then return end
        f.__huiRepaints = f.__huiRepaints or {}
        tinsert(f.__huiRepaints, fn)
        ns.hui.__skinRegistry[f] = true
    end
    function ns.hui.RefreshSkin()
        for f in pairs(ns.hui.__skinRegistry) do
            local reps = f.__huiRepaints
            if reps then
                local alive = true
                for _, fn in ipairs(reps) do
                    local ok, _ = pcall(fn)
                    if not ok then alive = false; break end
                end
                if not alive then ns.hui.__skinRegistry[f] = nil end
            elseif f.__huiRepaint then
                local ok, _ = pcall(f.__huiRepaint, f)
                if not ok then ns.hui.__skinRegistry[f] = nil end
            end
        end
        for fs, list in pairs(ns.hui.__textRepaints) do
            for _, apply in ipairs(list) do pcall(apply) end
        end
    end

    ns.hui.__textRepaints = ns.hui.__textRepaints or setmetatable({}, { __mode = "k" })
    local function themeTextRegister(fs, apply)
        apply()
        local list = ns.hui.__textRepaints[fs] or {}
        list[#list + 1] = apply
        ns.hui.__textRepaints[fs] = list
    end
    function ns.hui.SetThemeText(fs, fn)
        if not fs then return end
        themeTextRegister(fs, function() fs:SetText(fn()) end)
    end
    function ns.hui.SetThemeTextColor(fs, level)
        if not fs then return end
        themeTextRegister(fs, function()
            local c = (level == "accent") and ns.hui.ACCENT or ns.hui.TEXT[level or 1]
            fs:SetTextColor(c[1], c[2], c[3])
        end)
    end

    ns.hui.__themeRecolorRoots = ns.hui.__themeRecolorRoots or {}
    function ns.hui.AddRecolorRoot(f)
        if f then ns.hui.__themeRecolorRoots[f] = true end
    end
    function ns.hui.RecolorAllThemeText(prevHex, newHex, prevR, prevG, prevB)
        if not prevHex or not newHex or prevHex == newHex then return end
        prevHex = prevHex:lower()
        local hexClass = ""
        for i = 1, #prevHex do
            local ch = prevHex:sub(i, i)
            hexClass = hexClass .. "[" .. ch:upper() .. ch:lower() .. "]"
        end
        local ph = "%|c[fF][fF]" .. hexClass
        local function walk(f)
            if not f or not f.GetRegions then return end
            local regions = { f:GetRegions() }
            for i = 1, #regions do
                local r = regions[i]
                if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                    local t = r:GetText()
                    if t and t:lower():find("|cff" .. prevHex, 1, true) then
                        r:SetText(t:gsub(ph, "|cff" .. newHex))
                    end
                    if prevR then
                        local cr, cg, cb = r:GetTextColor()
                        if cr and math.abs(cr - prevR) < 0.02 and math.abs(cg - prevG) < 0.02 and math.abs(cb - prevB) < 0.02 then
                            r:SetTextColor(ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3])
                        end
                    end
                end
            end
            local children = { f:GetChildren() }
            for i = 1, #children do walk(children[i]) end
        end
        local roots = {}
        if ns.MainFrame then roots[#roots + 1] = ns.MainFrame end
        if ns.FBMainFrame and ns.FBMainFrame ~= ns.MainFrame then roots[#roots + 1] = ns.FBMainFrame end
        for f in pairs(ns.hui.__themeRecolorRoots) do roots[#roots + 1] = f end
        for i = 1, #roots do walk(roots[i]) end
    end

    ns.hui.__themeListeners = ns.hui.__themeListeners or {}
    function ns.hui.OnThemeChange(fn)
        if type(fn) == "function" then tinsert(ns.hui.__themeListeners, fn) end
    end

    local function Paint(tex, color)
        tex:SetVertexColor(color[1], color[2], color[3])
        tex:SetAlpha(color[4] or 1)
    end

    local function BuildCapsule(f, cornerSize, color)

        local tl = f:CreateTexture(nil, "BACKGROUND")
        tl:SetTexture(HUI_CORNER_TL)
        tl:SetSize(cornerSize, cornerSize)
        tl:SetPoint("TOPLEFT")
        Paint(tl, color)

        local tr = f:CreateTexture(nil, "BACKGROUND")
        tr:SetTexture(HUI_CORNER_TR)
        tr:SetSize(cornerSize, cornerSize)
        tr:SetPoint("TOPRIGHT")
        Paint(tr, color)

        local bl = f:CreateTexture(nil, "BACKGROUND")
        bl:SetTexture(HUI_CORNER_BL)
        bl:SetSize(cornerSize, cornerSize)
        bl:SetPoint("BOTTOMLEFT")
        Paint(bl, color)

        local br = f:CreateTexture(nil, "BACKGROUND")
        br:SetTexture(HUI_CORNER_BR)
        br:SetSize(cornerSize, cornerSize)
        br:SetPoint("BOTTOMRIGHT")
        Paint(br, color)

        local top = f:CreateTexture(nil, "BACKGROUND")
        top:SetTexture("Interface/Buttons/WHITE8X8")
        Paint(top, color)
        top:SetPoint("TOPLEFT", f, "TOPLEFT", cornerSize, 0)
        top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -cornerSize, -cornerSize)
        local bottom = f:CreateTexture(nil, "BACKGROUND")
        bottom:SetTexture("Interface/Buttons/WHITE8X8")
        Paint(bottom, color)
        bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", cornerSize, cornerSize)
        bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -cornerSize, 0)
        local mid = f:CreateTexture(nil, "BACKGROUND")
        mid:SetTexture("Interface/Buttons/WHITE8X8")
        Paint(mid, color)
        mid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cornerSize)
        mid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, cornerSize)

        local pieces = {tl, tr, bl, br, top, bottom, mid}
        ns.hui.AddRepaint(f, function()
            for _, tex in ipairs(pieces) do
                tex:SetVertexColor(color[1], color[2], color[3])
                tex:SetAlpha(color[4] or 1)
            end
        end)
        return pieces
    end

    local pixelStrips = setmetatable({}, { __mode = "k" })
    local pixelShowHooks = setmetatable({}, { __mode = "k" })
    local function PixelStripSize(f)
        local ok, _, h = pcall(GetPhysicalScreenSize)
        if not ok or not h or h <= 0 then return 1 end
        local k = (f and f.GetEffectiveScale and f:GetEffectiveScale() or 1) * h / 768
        if not k or k <= 0 then return 1 end
        return math.max(1, math.floor(k + 0.5)) / k
    end
    local function ReapplyStripPixels(frame)
        for tex in pairs(pixelStrips) do
            local p = tex:GetParent()
            if p and (not frame or p == frame) then
                local s = PixelStripSize(p)
                if tex.__huiStripAxis == "h" then tex:SetHeight(s) else tex:SetWidth(s) end
            end
        end
    end
    local function RegisterPixelStrip(tex, axis)
        tex.__huiStripAxis = axis
        pixelStrips[tex] = true
        local p = tex:GetParent()
        if p then
            local s = PixelStripSize(p)
            if axis == "h" then tex:SetHeight(s) else tex:SetWidth(s) end
            if not pixelShowHooks[p] then
                pixelShowHooks[p] = true
                p:HookScript("OnShow", function(self) ReapplyStripPixels(self) end)
            end
        end
    end
    do
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_LOGIN")
        ev:SetScript("OnEvent", function() ReapplyStripPixels(nil) end)
        pcall(function() ev:RegisterEvent("UI_SCALE_CHANGED") end)
    end
    local BORDER_UV = {
        TOPLEFT     = { 0, 0,  0, 1,  1, 0,  1, 1 },
        TOPRIGHT    = { 1, 0,  1, 1,  0, 0,  0, 1 },
        BOTTOMLEFT  = { 0, 1,  0, 0,  1, 1,  1, 0 },
        BOTTOMRIGHT = { 1, 1,  1, 0,  0, 1,  0, 0 },
    }
    local function DrawRoundBorder(f, r, color, owner, layer, rounding, thickness, fillColor, outside, outExtra, expand)
        local ex = expand or 0
        local p = owner or f
        local alpha = color[4] or 1
        local thick = thickness or 1
        local ext = thick + (outside and (outExtra or 0) or 0)
        local CORNER_TEX = {
            TOPLEFT = HUI_CORNER_TL, TOPRIGHT = HUI_CORNER_TR,
            BOTTOMLEFT = HUI_CORNER_BL, BOTTOMRIGHT = HUI_CORNER_BR,
        }
        local pieces = {}
        local covers = {}
        local function corner(point)
            local insetSide = point:find("LEFT") and 1 or -1
            local insetVert = point:find("TOP") and -1 or 1
            local shift = (outside and ext or 0) + ex
            local ox = -shift * insetSide
            local oy = -shift * insetVert
            if thick > 1 then
                local tex = CORNER_TEX[point]
                local outer = p:CreateTexture(nil, layer or "BORDER")
                outer:SetTexture(tex)
                outer:SetSize(r, r)
                outer:SetPoint(point, f, point, ox, oy)
                outer:SetVertexColor(color[1], color[2], color[3])
                outer:SetAlpha(alpha)
                pieces[#pieces + 1] = outer
                if r > thick then
                    local inner = p:CreateTexture(nil, layer or "BORDER")
                    inner:SetTexture(tex)
                    inner:SetSize(r - thick, r - thick)
                    inner:SetPoint(point, f, point, ox, oy)
                    local fc = fillColor or color
                    inner:SetVertexColor(fc[1], fc[2], fc[3])
                    inner:SetAlpha(fc[4] or 1)
                    covers[#covers + 1] = inner
                end
                return
            end
            local t = p:CreateTexture(nil, layer or "BORDER")
            t:SetTexture("Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCorner")
            t:SetSize(r, r)
            t:SetPoint(point, f, point, ox, oy)
            local uv = BORDER_UV[point]
            t:SetTexCoord(uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8])
            t:SetVertexColor(color[1], color[2], color[3])
            t:SetAlpha(alpha)
            pieces[#pieces + 1] = t
        end
        local sL = not rounding or rounding == "both" or rounding == "left"
        local sR = not rounding or rounding == "both" or rounding == "right"
        local sT = rounding == "top"
        local sB = rounding == "bottom"
        local arcTL = sL or sT
        local arcTR = sR or sT
        local arcBL = sL or sB
        local arcBR = sR or sB
        if arcTL then corner("TOPLEFT") end
        if arcTR then corner("TOPRIGHT") end
        if arcBL then corner("BOTTOMLEFT") end
        if arcBR then corner("BOTTOMRIGHT") end
        local arcInset = r - thick - (outside and (outExtra or 0) or 0) - ex
        local function hstrip(top)
            local t = p:CreateTexture(nil, layer or "BORDER")
            t:SetColorTexture(color[1], color[2], color[3], 1)
            t:SetAlpha(alpha)
            t.__huiBorderStrip = true
            local vp = top and "TOP" or "BOTTOM"
            local oy = (top and 1 or -1) * ((outside and ext or 0) + ex)
            t:SetPoint(vp .. "LEFT", f, vp .. "LEFT", (top and arcTL or arcBL) and arcInset or 0, oy)
            t:SetPoint(vp .. "RIGHT", f, vp .. "RIGHT", (top and arcTR or arcBR) and -arcInset or 0, oy)
            if thick == 1 then
                RegisterPixelStrip(t, "h")
            else
                t:SetHeight(thick)
            end
            pieces[#pieces + 1] = t
        end
        local function vstrip(left)
            local t = p:CreateTexture(nil, layer or "BORDER")
            t:SetColorTexture(color[1], color[2], color[3], 1)
            t:SetAlpha(alpha)
            t.__huiBorderStrip = true
            local hp = left and "LEFT" or "RIGHT"
            local ox = (left and -1 or 1) * ((outside and ext or 0) + ex)
            t:SetPoint("TOP" .. hp, f, "TOP" .. hp, ox, (left and arcTL or arcTR) and -arcInset or 0)
            t:SetPoint("BOTTOM" .. hp, f, "BOTTOM" .. hp, ox, (left and arcBL or arcBR) and arcInset or 0)
            if thick == 1 then
                RegisterPixelStrip(t, "w")
            else
                t:SetWidth(thick)
            end
            pieces[#pieces + 1] = t
        end
        hstrip(true)
        hstrip(false)
        if sL or arcTL or arcBL then vstrip(true) end
        if sR or arcTR or arcBR then vstrip(false) end
        return pieces, covers
    end

    local function BuildRoundedBG(f, cr, color, rounding, withBorder, borderThickness, noRepaint, borderOutside, borderOutExtra, expand)
        local e = expand or 0
        if color == nil then color = ns.hui.layer.L1
        elseif sameGray(color, L0_GRAY) then color = ns.hui.layer.L0
        elseif sameGray(color, L1_GRAY) then color = ns.hui.layer.L1
        elseif sameGray(color, L2_GRAY) or sameGray(color, L2_GRAY095) then color = ns.hui.layer.L2
        elseif sameGray(color, L3_GRAY) then color = ns.hui.layer.L3 end
        local sL = not rounding or rounding == "both" or rounding == "left"
        local sR = not rounding or rounding == "both" or rounding == "right"
        local sT = rounding == "top"
        local sB = rounding == "bottom"
        local arcTL = sL or sT
        local arcTR = sR or sT
        local arcBL = sL or sB
        local arcBR = sR or sB
        local pieces = {}
        local function add(texPath, w, h)
            local tex = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            tex:SetTexture(texPath)
            tex:SetSize(w or cr, h or cr)
            tex:SetVertexColor(color[1], color[2], color[3])
            tex:SetAlpha(color[4] or 1)
            pieces[#pieces + 1] = tex
            return tex
        end
        if arcTL then add(HUI_CORNER_TL):SetPoint("TOPLEFT", f, "TOPLEFT", -e, e) end
        if arcTR then add(HUI_CORNER_TR):SetPoint("TOPRIGHT", f, "TOPRIGHT", e, e) end
        if arcBL then add(HUI_CORNER_BL):SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -e, -e) end
        if arcBR then add(HUI_CORNER_BR):SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", e, -e) end
        if arcTL or arcTR then
            local ts = add("Interface/Buttons/WHITE8X8")
            ts:SetPoint("TOPLEFT", f, "TOPLEFT", (arcTL and cr or 0) - e, e)
            ts:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", (arcTR and -cr or 0) + e, -cr + e)
        end
        if arcBL or arcBR then
            local bs = add("Interface/Buttons/WHITE8X8")
            bs:SetPoint("TOPLEFT", f, "BOTTOMLEFT", (arcBL and cr or 0) - e, cr - e)
            bs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", (arcBR and -cr or 0) + e, -e)
        end
        if arcTL or arcBL then
            local ls = add("Interface/Buttons/WHITE8X8")
            ls:SetPoint("TOPLEFT", f, "TOPLEFT", -e, (arcTL and -cr or 0) + e)
            ls:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", cr - e, (arcBL and cr or 0) - e)
        end
        if arcTR or arcBR then
            local rs = add("Interface/Buttons/WHITE8X8")
            rs:SetPoint("TOPRIGHT", f, "TOPRIGHT", e, (arcTR and -cr or 0) + e)
            rs:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -cr + e, (arcBR and cr or 0) - e)
        end
        local insetL = (arcTL or arcBL) and cr or 0
        local insetR = (arcTR or arcBR) and cr or 0
        local insetT = (arcTL or arcTR) and cr or 0
        local insetB = (arcBL or arcBR) and cr or 0
        local rect = add("Interface/Buttons/WHITE8X8")
        rect:SetPoint("TOPLEFT", f, "TOPLEFT", insetL - e, -insetT + e)
        rect:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR + e, insetB - e)
        if not noRepaint then
            ns.hui.AddRepaint(f, function()
                for _, tex in ipairs(pieces) do
                    tex:SetVertexColor(color[1], color[2], color[3])
                    tex:SetAlpha(color[4] or 1)
                end
            end)
        end
        if not noRepaint and ns.huiTheme == "hui" and ns.hui.RegisterMainAlphaSurface and ns.hui.IsMainUIFrame(f) then
            ns.hui.RegisterMainAlphaSurface(f, pieces)
        end
        if withBorder then
            local border, covers = DrawRoundBorder(f, cr, C_CARD_BORDER, f, "BORDER", rounding, borderThickness, color, borderOutside, borderOutExtra, expand)
            return pieces, border, covers
        end
        return pieces
    end
    ns.hui.BuildRoundedBG = BuildRoundedBG

    function ns.hui.GetMainAlpha()
        local v = tonumber(ns.options and ns.options.huiAlpha)
        if not v or v < 0 or v > 1 then v = 0.95 end
        return v
    end

    function ns.hui.MainAlphaK()
        if ns.huiTheme ~= "hui" then return 1 end
        return ns.hui.GetMainAlpha() / 0.95
    end

    local mainAlphaSurfaces = {}

    function ns.hui.IsMainUIFrame(f)
        if not f then return false end
        local main = ns.MainFrame
        if not main then return false end
        local cur = f
        while cur do
            if cur == main then return true end
            if cur == ns.auctionLogFrame or cur == ns.itemGuoQiFrame then return true end
            cur = cur:GetParent()
        end
        return false
    end

    function ns.hui.ApplyMainAlpha()
        local k = ns.hui.GetMainAlpha() / 0.95
        for _, entry in pairs(mainAlphaSurfaces) do
            for _, pieces in ipairs(entry.pieces) do
                for _, tex in ipairs(pieces) do
                    tex:SetAlpha((tex.__huiMainBaseA or 1) * k)
                end
            end
            for _, fn in ipairs(entry.multipliers or {}) do
                fn(k)
            end
        end
    end

    function ns.hui.RegisterMainAlphaSurface(frame, pieces)
        if not frame or not pieces or not ns.hui.AddRepaint then return end
        local entry = mainAlphaSurfaces[frame]
        if not entry then
            entry = { pieces = {}, multipliers = {} }
            mainAlphaSurfaces[frame] = entry
            function entry.Reassert()
                local k = ns.hui.GetMainAlpha() / 0.95
                for _, pl in ipairs(entry.pieces) do
                    for _, tex in ipairs(pl) do
                        tex:SetAlpha((tex.__huiMainBaseA or 1) * k)
                    end
                end
                for _, fn in ipairs(entry.multipliers) do
                    fn(k)
                end
            end
            ns.hui.AddRepaint(frame, entry.Reassert)
            frame:HookScript("OnShow", entry.Reassert)
        end
        entry.pieces[#entry.pieces + 1] = pieces
        for _, tex in ipairs(pieces) do
            if not tex.__huiMainBaseA then
                tex.__huiMainBaseA = tex:GetAlpha() or 1
            end
        end
        entry.Reassert()
    end

    function ns.hui.RegisterMainAlphaMultiplier(frame, fn)
        if not frame or not fn then return end
        local entry = mainAlphaSurfaces[frame]
        if not entry then
            entry = { pieces = {}, multipliers = {} }
            mainAlphaSurfaces[frame] = entry
            function entry.Reassert()
                local k = ns.hui.GetMainAlpha() / 0.95
                for _, pl in ipairs(entry.pieces) do
                    for _, tex in ipairs(pl) do
                        tex:SetAlpha((tex.__huiMainBaseA or 1) * k)
                    end
                end
                for _, f2 in ipairs(entry.multipliers) do
                    f2(k)
                end
            end
            ns.hui.AddRepaint(frame, entry.Reassert)
            frame:HookScript("OnShow", entry.Reassert)
        end
        entry.multipliers[#entry.multipliers + 1] = fn
        entry.Reassert()
    end

    function ns.hui.SkinPopup(f, cr, rounding, color, borderThickness, noBorder, borderOutside, borderOutExtra, expand, noAlpha)
        if ns.huiTheme ~= "hui" or not f then return end
        color = color or ns.hui.layer.L1
        if sameGray(color, L1_GRAY) then color = ns.hui.layer.L1
        elseif sameGray(color, L2_GRAY) or sameGray(color, L2_GRAY095) then color = ns.hui.layer.L2
        elseif sameGray(color, L3_GRAY) then color = ns.hui.layer.L3 end
        if f.SetBackdropColor then
            f:SetBackdropColor(0, 0, 0, 0)
        end
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(0, 0, 0, 0)
        end
        local pieces, borderPieces, coverPieces = BuildRoundedBG(f, cr or 8, color, rounding or "both", not noBorder, borderThickness, nil, borderOutside, borderOutExtra, expand)
        f.__huiBorderPieces = borderPieces
        local function repaintFill()
            for _, tex in ipairs(pieces) do
                tex:SetShown(true)
                tex:SetVertexColor(color[1], color[2], color[3])
                tex:SetAlpha(color[4])
            end
            for _, tex in ipairs(coverPieces or {}) do
                tex:SetShown(true)
                tex:SetVertexColor(color[1], color[2], color[3])
                tex:SetAlpha(color[4])
            end
        end
        local function repaintBorder()
            if not borderPieces then return end
            for _, tex in ipairs(borderPieces) do
                tex:SetShown(true)
                tex:SetVertexColor(C_CARD_BORDER[1], C_CARD_BORDER[2], C_CARD_BORDER[3])
                tex:SetAlpha(C_CARD_BORDER[4])
            end
        end
        ns.hui.AddRepaint(f, repaintFill)
        ns.hui.AddRepaint(f, repaintBorder)
        f:HookScript("OnShow", function(frame)
            repaintFill()
            repaintBorder()
        end)
        if not noAlpha and ns.hui.RegisterMainAlphaSurface then
            local reg = { unpack(pieces) }
            for _, tex in ipairs(coverPieces or {}) do
                reg[#reg + 1] = tex
            end
            ns.hui.RegisterMainAlphaSurface(f, reg)
            local entry = mainAlphaSurfaces[f]
            if entry then
                tinsert(f.__huiRepaints, entry.Reassert)
                f:HookScript("OnShow", entry.Reassert)
            end
        end
        return pieces
    end

    local dropdownSkinSeen = {}
    local function ApplyDropDownListSkin(f, on)
        local s = f.__huiDropDownSkin
        if not s then return end
        for _, tex in ipairs(s.pieces) do tex:SetShown(on) end
        for _, tex in ipairs(s.border) do tex:SetShown(on) end
        for _, bd in ipairs(s.libBackdrops) do
            if bd then bd:SetShown(not on) end
        end
    end
    local function SkinDropDownList(f)
        if not f or dropdownSkinSeen[f] then return end
        dropdownSkinSeen[f] = true
        local pieces = BuildRoundedBG(f, 8, ns.hui.layer.L1, "both")
        local border = DrawRoundBorder(f, 8, ns.hui.layer.DIV) or {}
        for _, tex in ipairs(border) do
            tex:SetDrawLayer("OVERLAY")
        end
        f.__huiDropDownSkin = { pieces = pieces, border = border, libBackdrops = { f.Backdrop, f.MenuBackdrop } }
        ns.hui.AddRepaint(f, function()
            local DIV = ns.hui.layer.DIV
            for _, tex in ipairs(border) do
                if tex.__huiBorderStrip then
                    tex:SetColorTexture(DIV[1], DIV[2], DIV[3], 1)
                    tex:SetAlpha(DIV[4] or 1)
                else
                    tex:SetVertexColor(DIV[1], DIV[2], DIV[3])
                    tex:SetAlpha(DIV[4] or 1)
                end
            end
        end)
        ns.hui.AddRepaint(f, function()
            if ns.huiTheme ~= "hui" then return end
            local L3 = ns.hui.layer.L3
            for _, bt in ipairs({ f:GetChildren() }) do
                if bt.Highlight then
                    bt.Highlight:SetColorTexture(L3[1], L3[2], L3[3], 1)
                end
            end
        end)
        f:HookScript("OnShow", function(frame)
            ApplyDropDownListSkin(frame, ns.huiTheme == "hui")
        end)
    end
    for i = 1, 3 do
        SkinDropDownList(_G["L_DropDownList" .. i])
    end
    local LibBG = ns.LibBG
    if LibBG and LibBG.UIDropDownMenu_CreateFrames then
        hooksecurefunc(LibBG, "UIDropDownMenu_CreateFrames", function()
            for i = 4, 20 do
                SkinDropDownList(_G["L_DropDownList" .. i])
            end
        end)
    end
    if LibBG and LibBG.UIDropDownMenu_InitializeHelper then
        hooksecurefunc(LibBG, "UIDropDownMenu_InitializeHelper", function(_, frame)
            if frame and frame.__huiDDH then frame:SetHeight(frame.__huiDDH) end
        end)
    end

    function ns.hui.AttachContentPanel(page, anchor, topInset, bottomInset, sideInset)
        if not page or not anchor then return end
        local s = sideInset or 6
        local t = topInset or 32
        local b = bottomInset or 26
        local cr = 8
        local L1 = ns.hui.layer.L1
        local function tex(path)
            local x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
            x:SetTexture(path)
            x:SetSize(cr, cr)
            return x
        end
        local tl = tex(HUI_CORNER_TL)
        tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", s, -t)
        local tr = tex(HUI_CORNER_TR)
        tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -s, -t)
        local bl = tex(HUI_CORNER_BL)
        bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", s, b)
        local br = tex(HUI_CORNER_BR)
        br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -s, b)
        local ls = tex("Interface/Buttons/WHITE8X8")
        ls:SetPoint("TOPLEFT", anchor, "TOPLEFT", s, -t - cr)
        ls:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", s + cr, b + cr)
        local rs = tex("Interface/Buttons/WHITE8X8")
        rs:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -s, -t - cr)
        rs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", -s - cr, b + cr)
        local mid = tex("Interface/Buttons/WHITE8X8")
        mid:SetPoint("TOPLEFT", anchor, "TOPLEFT", s + cr, -t)
        mid:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -s - cr, b)
        Paint(tl, L1)
        Paint(tr, L1)
        Paint(bl, L1)
        Paint(br, L1)
        Paint(ls, L1)
        Paint(rs, L1)
        Paint(mid, L1)

        local l1texs = {tl, tr, bl, br, ls, rs, mid}
        ns.hui.AddRepaint(page, function()
            for _, tex in ipairs(l1texs) do Paint(tex, ns.hui.layer.L1) end
        end)

        ns.hui.RegisterMainAlphaSurface(page, l1texs)

        local BC = "Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCorner"
        local function btex(path, w, h)
            local x = page:CreateTexture(nil, "BORDER", nil, -8)
            x:SetTexture(path)
            if w then x:SetSize(w, h) end
            x:SetVertexColor(C_CARD_BORDER[1], C_CARD_BORDER[2], C_CARD_BORDER[3])
            x:SetAlpha(C_CARD_BORDER[4])
            return x
        end
        local bcorners = {
            { "TOPLEFT",     s, -t },
            { "TOPRIGHT",   -s, -t },
            { "BOTTOMLEFT",  s,  b },
            { "BOTTOMRIGHT", -s,  b },
        }
        for _, c in ipairs(bcorners) do
            local x = btex(BC, cr, cr)
            x:SetPoint(c[1], anchor, c[1], c[2], c[3])
            local uv = BORDER_UV[c[1]]
            x:SetTexCoord(uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8])
        end
        local x = btex("Interface/Buttons/WHITE8X8")
        x:SetPoint("TOPLEFT", anchor, "TOPLEFT", s + cr - 1, -t)
        x:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -s - cr + 1, -t)
        RegisterPixelStrip(x, "h")
        x = btex("Interface/Buttons/WHITE8X8")
        x:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", s + cr - 1, b)
        x:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -s - cr + 1, b)
        RegisterPixelStrip(x, "h")
        x = btex("Interface/Buttons/WHITE8X8")
        x:SetPoint("TOPLEFT", anchor, "TOPLEFT", s, -t - cr + 1)
        x:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", s, b + cr - 1)
        RegisterPixelStrip(x, "w")
        x = btex("Interface/Buttons/WHITE8X8")
        x:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -s, -t - cr + 1)
        x:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -s, b + cr - 1)
        RegisterPixelStrip(x, "w")
    end

    function ns.hui.AttachBossCard(page, tlWidget, brWidget, l, t, r, b, cr, color, bottomWidget, topWidget)
        cr = cr or 6
        local L2 = color or ns.hui.layer.L2
        local bb = bottomWidget or brWidget
        local tt = topWidget or tlWidget
        local cardTexs = {}
        local x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture(HUI_CORNER_TL)
        x:SetSize(cr, cr)
        x:SetPoint("LEFT", tlWidget, "LEFT", l, 0)
        x:SetPoint("TOP", tt, "TOP", 0, t)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture(HUI_CORNER_TR)
        x:SetSize(cr, cr)
        x:SetPoint("RIGHT", brWidget, "RIGHT", r, 0)
        x:SetPoint("TOP", tt, "TOP", 0, t)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture(HUI_CORNER_BL)
        x:SetSize(cr, cr)
        x:SetPoint("LEFT", tlWidget, "LEFT", l, 0)
        x:SetPoint("BOTTOM", bb, "BOTTOM", 0, b)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture(HUI_CORNER_BR)
        x:SetSize(cr, cr)
        x:SetPoint("RIGHT", brWidget, "RIGHT", r, 0)
        x:SetPoint("BOTTOM", bb, "BOTTOM", 0, b)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture("Interface/Buttons/WHITE8X8")
        x:SetPoint("LEFT", tlWidget, "LEFT", l, 0)
        x:SetPoint("TOP", tt, "TOP", 0, t - cr)
        x:SetPoint("BOTTOM", bb, "BOTTOM", 0, b + cr)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture("Interface/Buttons/WHITE8X8")
        x:SetPoint("RIGHT", brWidget, "RIGHT", r, 0)
        x:SetPoint("TOP", tt, "TOP", 0, t - cr)
        x:SetPoint("BOTTOM", bb, "BOTTOM", 0, b + cr)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x
        x = page:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture("Interface/Buttons/WHITE8X8")
        x:SetPoint("LEFT", tlWidget, "LEFT", l + cr, 0)
        x:SetPoint("RIGHT", brWidget, "RIGHT", r - cr, 0)
        x:SetPoint("TOP", tt, "TOP", 0, t)
        x:SetPoint("BOTTOM", bb, "BOTTOM", 0, b)
        Paint(x, L2); cardTexs[#cardTexs + 1] = x

        ns.hui.AddRepaint(page, function()
            for _, tex in ipairs(cardTexs) do Paint(tex, ns.hui.layer.L2) end
        end)

        ns.hui.RegisterMainAlphaSurface(page, cardTexs)

        local function btex(path)
            local bx = page:CreateTexture(nil, "BORDER", nil, -8)
            bx:SetTexture(path)
            bx:SetVertexColor(C_CARD_BORDER[1], C_CARD_BORDER[2], C_CARD_BORDER[3])
            bx:SetAlpha(C_CARD_BORDER[4])
            return bx
        end
        local bcorners = {
            { "TOPLEFT",     { "LEFT", tlWidget, "LEFT", l, 0 },  { "TOP", tt, "TOP", 0, t } },
            { "TOPRIGHT",    { "RIGHT", brWidget, "RIGHT", r, 0 }, { "TOP", tt, "TOP", 0, t } },
            { "BOTTOMLEFT",  { "LEFT", tlWidget, "LEFT", l, 0 },  { "BOTTOM", bb, "BOTTOM", 0, b } },
            { "BOTTOMRIGHT", { "RIGHT", brWidget, "RIGHT", r, 0 }, { "BOTTOM", bb, "BOTTOM", 0, b } },
        }
        for _, c in ipairs(bcorners) do
            local bx = btex("Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundCorner")
            bx:SetSize(cr, cr)
            bx:SetPoint(unpack(c[2]))
            bx:SetPoint(unpack(c[3]))
            local uv = BORDER_UV[c[1]]
            bx:SetTexCoord(uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8])
        end
        local bx = btex("Interface/Buttons/WHITE8X8")
        bx:SetPoint("LEFT", tlWidget, "LEFT", l, 0)
        bx:SetPoint("TOP", tt, "TOP", 0, t - cr + 1)
        bx:SetPoint("BOTTOM", bb, "BOTTOM", 0, b + cr - 1)
        RegisterPixelStrip(bx, "w")
        bx = btex("Interface/Buttons/WHITE8X8")
        bx:SetPoint("RIGHT", brWidget, "RIGHT", r, 0)
        bx:SetPoint("TOP", tt, "TOP", 0, t - cr + 1)
        bx:SetPoint("BOTTOM", bb, "BOTTOM", 0, b + cr - 1)
        RegisterPixelStrip(bx, "w")
        bx = btex("Interface/Buttons/WHITE8X8")
        bx:SetPoint("LEFT", tlWidget, "LEFT", l + cr - 1, 0)
        bx:SetPoint("RIGHT", brWidget, "RIGHT", r - cr + 1, 0)
        bx:SetPoint("TOP", tt, "TOP", 0, t)
        RegisterPixelStrip(bx, "h")
        bx = btex("Interface/Buttons/WHITE8X8")
        bx:SetPoint("LEFT", tlWidget, "LEFT", l + cr - 1, 0)
        bx:SetPoint("RIGHT", brWidget, "RIGHT", r - cr + 1, 0)
        bx:SetPoint("BOTTOM", bb, "BOTTOM", 0, b)
        RegisterPixelStrip(bx, "h")
    end

    function ns.hui.CreateSegmentedControl(host)
        local padX, padY = 3, 2
        local trackH = host:GetHeight() + padY * 2

        local track = CreateFrame("Frame", nil, host)
        track:SetPoint("TOPLEFT", host, "TOPLEFT", -padX, padY)
        track:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", padX, -padY)
        local trackPieces = BuildCapsule(track, trackH / 2, ns.hui.layer.L1)
        if ns.hui.RegisterMainAlphaSurface and ns.hui.IsMainUIFrame(host) then
            ns.hui.RegisterMainAlphaSurface(track, trackPieces)
        end

        local sliderH = host:GetHeight() + 2
        local sliderY = (sliderH - host:GetHeight()) / 2
        local slider = CreateFrame("Frame", nil, host)
        slider:SetHeight(sliderH)
        local capW = sliderH / 2
        local capL = slider:CreateTexture(nil, "BORDER")
        capL:SetTexture(HUI_PILL_L)
        capL:SetSize(capW, sliderH)
        capL:SetPoint("TOPLEFT")
        Paint(capL, HUI_ACCENT)
        local capR = slider:CreateTexture(nil, "BORDER")
        capR:SetTexture(HUI_PILL_R)
        capR:SetSize(capW, sliderH)
        capR:SetPoint("TOPRIGHT")
        Paint(capR, HUI_ACCENT)
        local mid = slider:CreateTexture(nil, "BORDER")
        mid:SetTexture("Interface/Buttons/WHITE8X8")
        Paint(mid, HUI_ACCENT)
        mid:SetPoint("TOPLEFT", capL, "TOPRIGHT", 0, 0)
        mid:SetPoint("BOTTOMRIGHT", capR, "BOTTOMLEFT", 0, 0)
        slider:Hide()

        local ctrl = {buttons = {}, offsets = {}, slider = slider}

        function ctrl:AttachButtons(buttons)
            ctrl.buttonList = buttons
            local acc = 0
            for _, bt in ipairs(buttons) do
                ctrl.buttons[bt] = true
                ctrl.offsets[bt] = acc
                acc = acc + bt:GetWidth()
            end
        end

        local DURATION = 0.25
        local function ApplyThumb(x, w)
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", host, "TOPLEFT", x, sliderY)
            slider:SetWidth(w)
        end

        function ctrl:SetSelected(bt, animate)
            local toX = ctrl.offsets[bt]
            if not toX then return end
            local toW = bt:GetWidth()
            local fromX = ctrl.vx or toX
            local fromW = ctrl.vw or toW
            ctrl.x = toX
            ctrl.current = bt
            slider:Show()
            if animate and (fromX ~= toX or fromW ~= toW) then
                ctrl.animFromX, ctrl.animFromW = fromX, fromW
                ctrl.animToX, ctrl.animToW = toX, toW
                ctrl.animT = 0
                slider:SetScript("OnUpdate", function(s, elapsed)
                    ctrl.animT = ctrl.animT + elapsed
                    local p = ctrl.animT / DURATION
                    if p >= 1 then
                        s:SetScript("OnUpdate", nil)
                        ctrl.vx, ctrl.vw = ctrl.animToX, ctrl.animToW
                        ApplyThumb(ctrl.vx, ctrl.vw)
                        return
                    end
                    local e = 1 - (1 - p) * (1 - p)
                    ctrl.vx = ctrl.animFromX + (ctrl.animToX - ctrl.animFromX) * e
                    ctrl.vw = ctrl.animFromW + (ctrl.animToW - ctrl.animFromW) * e
                    ApplyThumb(ctrl.vx, ctrl.vw)
                end)
            else
                slider:SetScript("OnUpdate", nil)
                ctrl.vx, ctrl.vw = toX, toW
                ApplyThumb(toX, toW)
            end
        end

        function ctrl:HasButton(bt)
            return ctrl.buttons[bt] == true
        end

        function ctrl:ClearSelection()
            ctrl.current = nil
            ctrl.x = nil
            ctrl.vx, ctrl.vw = nil, nil
            slider:SetScript("OnUpdate", nil)
            slider:Hide()
        end

        ns.hui.AddRepaint(host, function()
            Paint(capL, HUI_ACCENT)
            Paint(capR, HUI_ACCENT)
            Paint(mid, HUI_ACCENT)
        end)

        return ctrl
    end

    function ns.hui.BuildRoundBorder(f, r, color, owner, layer, rounding, thickness, fillColor, outside, outExtra, expand)
        return DrawRoundBorder(f, r, color, owner, layer, rounding, thickness, fillColor, outside, outExtra, expand)
    end
    ns.hui.PixelStripSize = PixelStripSize

    local C_TEXT = {
        [1] = {0.95, 0.96, 0.98},
        [2] = {0xd4 / 255, 0xd4 / 255, 0xd4 / 255},
        [3] = {0xa0 / 255, 0xa0 / 255, 0xa0 / 255},
        [4] = {0x88 / 255, 0x88 / 255, 0x88 / 255},
    }
    local C_ACCENT = {0x46 / 255, 0xbf / 255, 0x72 / 255, 1}
    ns.hui.TEXT = C_TEXT
    ns.hui.ACCENT = C_ACCENT
    ns.hui.CARD_BORDER = C_CARD_BORDER

    function ns.hui.GetThemeBorderColor()
        local key = DungeonsForeverDB.libHUI and DungeonsForeverDB.libHUI.colorTheme
        local p = key and ns.hui.palette and ns.hui.palette[key]
        if p and p.deep then
            return { p.deep[1], p.deep[2], p.deep[3], 1 }
        end
        return C_CARD_BORDER
    end

    function ns.hui.TextColor(classic, level)
        if ns.huiTheme == "hui" then
            local c = (level == "accent") and ns.hui.ACCENT or C_TEXT[level or 1]
            return c[1], c[2], c[3]
        end
        if type(classic) == "table" then
            return classic[1], classic[2], classic[3]
        end
        return tonumber(classic:sub(1, 2), 16) / 255, tonumber(classic:sub(3, 4), 16) / 255, tonumber(classic:sub(5, 6), 16) / 255
    end

    function ns.hui.TextHex(classic, level)
        if ns.huiTheme ~= "hui" then return classic end
        local c = (level == "accent") and ns.hui.ACCENT or C_TEXT[level or 1]
        return format("%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
    end

    function ns.hui.FontFlags(classic)
        if ns.huiTheme == "hui" then return "" end
        return classic or "OUTLINE"
    end

    function ns.hui.BidOutlineFlags(classic, key)
        local flags = classic or "OUTLINE"
        if ns.huiTheme ~= "hui" then
            return flags
        end
        local v = ns.options and ns.options[key]
        if v == nil then
            v = 1
        end
        if v == 1 then
            return flags
        end
        return ""
    end

    function ns.hui.CountFlags(fallback, key)
        key = key or "itemCountOutline"
        if ns.options and ns.options[key] == 0 then
            return ns.hui.FontFlags(fallback)
        end
        return "OUTLINE"
    end

    local countFontRefresh = {}
    function ns.hui.RegisterItemCountFontRefresh(key, fn)
        if type(fn) == "function" then
            countFontRefresh[key or "itemCountOutline"] = fn
        end
    end
    function ns.hui.RefreshItemCountFonts(key)
        key = key or "itemCountOutline"
        local fn = countFontRefresh[key]
        if fn then pcall(fn) end
    end

    local huiFontObjs = {}
    function ns.hui.FontObject(level, size)
        local key = level .. "_" .. size
        if not huiFontObjs[key] then
            local c = (level == "accent") and ns.hui.ACCENT or C_TEXT[level]
            local f = CreateFont("ns.hui.FontText_" .. key)
            f:SetFont(ns.FONT, size, "")
            f:SetTextColor(c[1], c[2], c[3])
            f.__huiLevel = level
            huiFontObjs[key] = f
        end
        return huiFontObjs[key]
    end
    function ns.hui.RefreshFontObjects()
        for _, f in pairs(huiFontObjs) do
            local level = f.__huiLevel
            if level then
                local c = (level == "accent") and ns.hui.ACCENT or C_TEXT[level]
                f:SetTextColor(c[1], c[2], c[3])
            end
        end
    end

    local tooltipSkins = {}

    local function IsOwnedFrame(f)
        if not f or not f.GetName then return false end
        local ok, name = pcall(f.GetName, f)
        if not ok or not name then return false end
        return name:sub(1, 15) == "DungeonsForever"
    end

    local function TooltipOwnerIsMine(tt)
        if not tt or not tt.GetOwner then return false end
        local ok, owner = pcall(tt.GetOwner, tt)
        if not ok or not owner then return false end
        local roots = ns.hui.__ttRoots
        local f = owner
        while f and f ~= UIParent do
            if IsOwnedFrame(f) then return true end
            if roots and roots[f] then return true end
            f = f.GetParent and f:GetParent() or nil
        end
        if f == UIParent and (IsOwnedFrame(owner) or (roots and roots[owner])) then return true end
        return false
    end

    function ns.hui.RegisterTooltipRoot(f)
        if not f then return end
        ns.hui.__ttRoots = ns.hui.__ttRoots or {}
        ns.hui.__ttRoots[f] = true
    end

    local function AddonLoaded(name)
        local fn = IsAddOnLoaded
        if type(fn) ~= "function" then return false end
        local ok, loaded = pcall(fn, name)
        return ok and loaded and true or false
    end

    local function HasExternalTooltipSkin()
        if AddonLoaded("NDui") then return true end
        if not AddonLoaded("ElvUI") then return false end
        local ok, E = pcall(unpack, ElvUI)
        local skins = ok and E and E.private and E.private.skins
        if not (skins and skins.blizzard) then return true end
        return (skins.blizzard.enable and skins.blizzard.tooltip) and true or false
    end

    local ttItemMark = {}
    function ns.hui.MarkTipItem(tt, on)
        if tt then ttItemMark[tt] = on and true or nil end
    end
    do
        hooksecurefunc(GameTooltip, "SetOwner", function(tt) ttItemMark[tt] = nil end)
        hooksecurefunc(GameTooltip, "SetHyperlink", function(tt) ttItemMark[tt] = true end)
    end

    local function TooltipHasItemContent(tt)
        if ttItemMark[tt] then return true end
        local fn = tt and tt.GetItem
        if type(fn) ~= "function" then return false end
        local ok, _, link = pcall(fn, tt)
        return ok and link ~= nil
    end

    local function ApplyTooltipSkin(tt, on)
        local s = tooltipSkins[tt]
        if not s then return end
        s.on = on
        local FILL = ns.hui.layer.L3 or ns.hui.layer.L2 or ns.hui.layer.L1
        for _, tex in ipairs(s.fill) do
            tex:SetShown(on)
            if on then
                tex:SetVertexColor(FILL[1], FILL[2], FILL[3])
                tex:SetAlpha(FILL[4])
            end
        end
        for _, tex in ipairs(s.border) do tex:SetShown(on) end
        if tt.NineSlice then
            if on then
                tt.NineSlice:SetAlpha(0)
            elseif not (s.ownScoped and HasExternalTooltipSkin()) then
                tt.NineSlice:SetAlpha(s.nineAlpha or 1)
            end
        end
    end

    local function UnskinItemTooltip(tt)
        ttItemMark[tt] = true
        local s2 = tooltipSkins[tt]
        if s2 and s2.on then ApplyTooltipSkin(tt, false) end
    end

    local itemPostCallDone = false
    local function HookItemUnskin(tt)
        if tt.HasScript then
            local ok, has = pcall(tt.HasScript, tt, "OnTooltipSetItem")
            if ok and has then
                if pcall(tt.HookScript, tt, "OnTooltipSetItem", function() UnskinItemTooltip(tt) end) then return end
            end
        end
        if itemPostCallDone then return end
        if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end
        local td = Enum and Enum.TooltipDataType
        if not (td and td.Item ~= nil) then return end
        itemPostCallDone = true
        pcall(TooltipDataProcessor.AddTooltipPostCall, td.Item, UnskinItemTooltip)
    end

    function ns.hui.SkinGameTooltip(tt)
        if not tt or tt.__huiSkinned then return end
        tt.__huiSkinned = true
        local FILL = ns.hui.layer.L3 or ns.hui.layer.L2 or ns.hui.layer.L1
        local EDGE = ns.hui.layer.L5 or ns.hui.layer.DIV
        local s = {
            fill = BuildRoundedBG(tt, 8, FILL, "both"),
            border = ns.hui.BuildRoundBorder(tt, 8, EDGE) or {},
            ownScoped = true,
        }
        s.nineAlpha = tt.NineSlice and tt.NineSlice:GetAlpha() or 1
        tooltipSkins[tt] = s
        tt:HookScript("OnShow", function()
            local on = ns.huiTheme == "hui"
            if on and s.ownScoped then
                on = TooltipOwnerIsMine(tt)
                if on and TooltipHasItemContent(tt) then on = false end
            end
            if on ~= s.on then ApplyTooltipSkin(tt, on) end
        end)
        HookItemUnskin(tt)
        ApplyTooltipSkin(tt, false)
    end

    function ns.hui.RefreshGameTooltipSkin()
        if not ns.hui.__tooltipStyleHooked then
            ns.hui.__tooltipStyleHooked = true
            if SharedTooltip_SetBackdropStyle then
                hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
                    local s = tooltip and tooltipSkins[tooltip]
                    if s and s.on and tooltip.NineSlice then
                        tooltip.NineSlice:SetAlpha(0)
                    end
                end)
            end
        end
        local themeOn = ns.huiTheme == "hui"
        for tt, s in pairs(tooltipSkins) do
            local on = themeOn
            if s.ownScoped then
                if tt:IsShown() then
                    on = on and TooltipOwnerIsMine(tt) and not TooltipHasItemContent(tt)
                else
                    on = false
                end
            end
            if s.on ~= on then ApplyTooltipSkin(tt, on) end
        end
    end

    pcall(ns.hui.SkinGameTooltip, GameTooltip)
    pcall(ns.hui.SkinGameTooltip, ItemRefTooltip)
    pcall(ns.hui.RefreshGameTooltipSkin)
    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            ns.hui.RefreshGameTooltipSkin()
        end)
    end

    local HUI_EDIT_BORDER_NORMAL = {0.30, 0.30, 0.28, 0.85}
    function ns.hui.SetEditBorder(edit, r, g, b, a)
        if not edit then return end
        if edit.HUIEdgeTop then
            for _, key in ipairs({ "HUIEdgeTop", "HUIEdgeBottom", "HUIEdgeLeft", "HUIEdgeRight",
                "HUICornerTL", "HUICornerTR", "HUICornerBL", "HUICornerBR" }) do
                local tex = edit[key]
                if tex then
                    if r == 1 and g == 1 and b == 1 then
                        tex:SetVertexColor(HUI_EDIT_BORDER_NORMAL[1], HUI_EDIT_BORDER_NORMAL[2], HUI_EDIT_BORDER_NORMAL[3])
                        tex:SetAlpha(HUI_EDIT_BORDER_NORMAL[4])
                    else
                        tex:SetVertexColor(r, g, b)
                        tex:SetAlpha(a or 1)
                    end
                end
            end
        elseif edit.Left then
            edit.Left:SetVertexColor(r, g, b, a or 1)
            edit.Right:SetVertexColor(r, g, b, a or 1)
            edit.Middle:SetVertexColor(r, g, b, a or 1)
        end
    end

    function ns.hui.SkinDropDown(dd)
        if not dd or dd.__huiDropDown or ns.huiTheme ~= "hui" then return end
        dd.__huiDropDown = true
        dd:EnableMouse(true)
        dd.__huiDDH = dd:GetHeight()

        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local tex = dd[key]
            if tex then tex:Hide() end
        end

        local ARROW_GRAY = { 0.62, 0.64, 0.67 }
        local btn = dd.Button
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", dd, "RIGHT", -2, 0)
            btn:SetSize(18, 18)
            local function HideNativeArrow()
                for _, reg in ipairs({ btn:GetRegions() }) do
                    if reg:GetObjectType() == "Texture" then
                        reg:SetAlpha(0)
                        reg:Hide()
                    end
                end
            end
            HideNativeArrow()
            for _, m in ipairs({ "Enable", "Disable", "SetEnabled" }) do
                hooksecurefunc(btn, m, HideNativeArrow)
            end
            dd:HookScript("OnShow", HideNativeArrow)
        end

        local arrow = dd.__huiArrow
        if not arrow then
            arrow = dd:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
            arrow:SetTexture("Interface/AddOns/DungeonsForever/Media/textures/arrow.tga")
            arrow:SetRotation(math.pi)
            arrow:SetVertexColor(ARROW_GRAY[1], ARROW_GRAY[2], ARROW_GRAY[3])
            dd.__huiArrow = arrow
        end

        local text = dd.Text
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", dd, "LEFT", 10, 0)
            text:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
            text:SetJustifyH("CENTER")
            text:SetFont(ns.FONT, 13, "")
            text:SetTextColor(0.92, 0.93, 0.95)
        end

        ns.hui.BuildRoundedBG(dd, 6, { 0x2a / 255, 0x2d / 255, 0x31 / 255, 0.5 }, "both")
        local NORMAL = { 0x55 / 255, 0x58 / 255, 0x5e / 255 }
        local border = ns.hui.BuildRoundBorder(dd, 6, NORMAL, dd, "OVERLAY", "both", 1) or {}
        local function Paint(c)
            for _, tex in ipairs(border) do
                if tex.__huiBorderStrip then
                    tex:SetColorTexture(c[1], c[2], c[3], 1)
                    tex:SetAlpha(c[4] or 1)
                else
                    tex:SetVertexColor(c[1], c[2], c[3])
                    tex:SetAlpha(c[4] or 1)
                end
            end
        end
        for _, tex in ipairs(border) do tex:SetShown(true) end
        dd:HookScript("OnEnter", function() Paint(ns.hui.ACCENT) end)
        dd:HookScript("OnLeave", function() Paint(NORMAL) end)
    end

    function ns.hui.SkinButton(bt)
        if not bt or bt.__huiAction or not bt.SetBackdropBorderColor then return end
        if ns.huiTheme ~= "hui" then return end
        bt.__huiAction = true
        local C_BORDER = {0x55 / 255, 0x58 / 255, 0x5e / 255}
        local C_BG = {0x2a / 255, 0x2d / 255, 0x31 / 255}
        bt:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 1,
        })
        local bodyK = 1
        local function ApplyBody(base)
            bt:SetBackdropColor(C_BG[1], C_BG[2], C_BG[3], base * bodyK)
        end
        ApplyBody(0.5)
        bt:SetBackdropBorderColor(0, 0, 0, 0)
        if bt.bg then bt.bg:SetColorTexture(0, 0, 0, 0) end
        local fs = bt:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", 0, -1)
            fs:SetJustifyH("CENTER")
            fs:SetTextColor(1, 1, 1)
            fs:SetFont(ns.FONT, 15, "")
        end

        local borderFrame, hoverFrame
        local function BuildBorderFrame()
            if borderFrame then borderFrame:Hide(); borderFrame:SetParent(nil) end
            borderFrame = CreateFrame("Frame", nil, bt)
            borderFrame:SetAllPoints()
            ns.hui.BuildRoundBorder(borderFrame, 6, C_BORDER)
            if hoverFrame then hoverFrame:SetParent(borderFrame) end
        end
        local function BuildHoverFrame()
            if hoverFrame then hoverFrame:Hide(); hoverFrame:SetParent(nil) end
            hoverFrame = CreateFrame("Frame", nil, borderFrame or bt)
            hoverFrame:SetAllPoints()
            hoverFrame:Hide()
            ns.hui.BuildRoundBorder(hoverFrame, 6, ns.hui.ACCENT)
        end
        local function TryBuild()
            local w, h = bt:GetWidth() or 0, bt:GetHeight() or 0
            if w > 0 and h > 0 then
                BuildBorderFrame()
                BuildHoverFrame()
            end
        end
        TryBuild()
        if not borderFrame then
            local function tryBuildOnce()
                if not borderFrame then TryBuild() end
            end
            bt:HookScript("OnSizeChanged", tryBuildOnce)
            hooksecurefunc(bt, "SetSize", tryBuildOnce)
            hooksecurefunc(bt, "SetWidth", tryBuildOnce)
            hooksecurefunc(bt, "SetHeight", tryBuildOnce)
        end

        local function huiOnEnter()
            if not bt:IsEnabled() then return end
            if hoverFrame then hoverFrame:Show() end
        end
        local function huiOnLeave()
            ApplyBody(0.5)
            if hoverFrame then hoverFrame:Hide() end
            if fs and bt:IsEnabled() and not bt.__huiKeepTextColor then fs:SetTextColor(1, 1, 1) end
        end
        hooksecurefunc(bt, "SetScript", function(_, scriptType, ...)
            if scriptType == "OnEnter" then bt:HookScript("OnEnter", huiOnEnter) end
            if scriptType == "OnLeave" then bt:HookScript("OnLeave", huiOnLeave) end
        end)
        bt:HookScript("OnEnter", huiOnEnter)
        bt:HookScript("OnLeave", huiOnLeave)
        hooksecurefunc(bt, "SetEnabled", function(_, enabled)
            ApplyBody(enabled and 0.5 or 0.25)
            if fs then
                if enabled then
                    fs:SetTextColor(1, 1, 1)
                else
                    fs:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end)
        if ns.hui.IsMainUIFrame(bt) then
            ns.hui.RegisterMainAlphaMultiplier(bt, function(k)
                bodyK = k
                ApplyBody(bt:IsEnabled() and 0.5 or 0.25)
            end)
        end
        ns.hui.AddRepaint(bt, function()
            if borderFrame then BuildHoverFrame() end
        end)
    end

    function ns.hui.MakeDangerButton(bt)
        if not bt or bt.__huiDanger or not bt.SetBackdropBorderColor then return end
        if ns.huiTheme ~= "hui" then return end
        ns.hui.SkinButton(bt)
        bt.__huiDanger = true
        local texs = BuildCapsule(bt, 6, C_RED)
        for _, tex in ipairs(texs) do
            tex:SetDrawLayer("BACKGROUND", -8)
        end
        local capsuleK = 1
        local function ApplyCapsule(base)
            for _, tex in ipairs(texs) do
                tex:SetAlpha(base * capsuleK)
            end
        end
        hooksecurefunc(bt, "SetEnabled", function(_, enabled)
            ApplyCapsule(enabled and 1 or 0.25)
        end)
        if ns.hui.IsMainUIFrame(bt) then
            ns.hui.RegisterMainAlphaMultiplier(bt, function(k)
                capsuleK = k
                ApplyCapsule(bt:IsEnabled() and 1 or 0.25)
            end)
        end
    end

    function ns.hui.MakeAccentButton(bt)
        if not bt or bt.__huiAccent or not bt.SetBackdropBorderColor then return end
        if ns.huiTheme ~= "hui" then return end
        ns.hui.SkinButton(bt)
        bt.__huiAccent = true
        local texs = BuildCapsule(bt, 6, ns.hui.ACCENT)
        for _, tex in ipairs(texs) do
            tex:SetDrawLayer("BACKGROUND", -8)
        end
        local capsuleK = 1
        local function ApplyCapsule(base)
            for _, tex in ipairs(texs) do
                tex:SetAlpha(base * capsuleK)
            end
        end
        bt:HookScript("OnEnter", function()
            if bt:IsEnabled() then
                local h1 = math.min(ns.hui.ACCENT[1] + 0.10, 1)
                local h2 = math.min(ns.hui.ACCENT[2] + 0.10, 1)
                local h3 = math.min(ns.hui.ACCENT[3] + 0.10, 1)
                for _, tex in ipairs(texs) do
                    tex:SetVertexColor(h1, h2, h3)
                end
            end
        end)
        bt:HookScript("OnLeave", function()
            for _, tex in ipairs(texs) do
                tex:SetVertexColor(ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3])
            end
        end)
        hooksecurefunc(bt, "SetEnabled", function(_, enabled)
            ApplyCapsule(enabled and 1 or 0.25)
        end)
        if ns.hui.IsMainUIFrame(bt) then
            ns.hui.RegisterMainAlphaMultiplier(bt, function(k)
                capsuleK = k
                ApplyCapsule(bt:IsEnabled() and 1 or 0.25)
            end)
        end
        ns.hui.AddRepaint(bt, function()
            for _, tex in ipairs(texs) do
                tex:SetVertexColor(ns.hui.ACCENT[1], ns.hui.ACCENT[2], ns.hui.ACCENT[3])
            end
        end)
    end

    local function ToggleKnobX(on, bt)
        local W = (bt and bt.__huiW) or 36
        local K = (bt and bt.__huiKnob) or 14
        return on and (W - K - 3) or 3
    end
    local function PaintTrack(texs, c)
        for _, tex in ipairs(texs) do
            if tex.__isColor then
                tex:SetColorTexture(c[1], c[2], c[3], 1)
            else
                tex:SetVertexColor(c[1], c[2], c[3])
            end
        end
    end
    local function ApplyToggleState(bt, texs, knob, animate)
        animate = animate and true or false
        local on = bt.__huiOn
        if on == nil then on = bt:GetChecked() and true or false end
        bt.__huiOn = on
        local toX = ToggleKnobX(on, bt)
        local toC = on and HUI_ACCENT or ns.hui.layer.L4
        bt.__huiAnim = false
        if not animate then
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", bt, "LEFT", toX, 0)
            knob:SetSize(bt.__huiKnob or 14, bt.__huiKnob or 14)
            PaintTrack(texs, toC)
            bt.__huiKnobX = toX
            bt.__huiColor = toC
            return
        end
        bt.__huiAnimFromX = bt.__huiKnobX or toX
        bt.__huiAnimToX = toX
        bt.__huiAnimFromC = bt.__huiColor or toC
        bt.__huiAnimToC = toC
        bt.__huiAnimEl = 0
        bt.__huiAnimDur = 0.14
        bt.__huiAnim = true
    end

    function ns.hui.ReskinToggle(bt, w, h)
        if bt.__huiToggle then return end
        local TW, TH = w or 36, h or 20
        local KNOB = TH - 6
        bt.__huiW, bt.__huiKnob = TW, KNOB
        bt.__huiToggle = true
        local ours = {}
        local border = CreateFrame("Frame", nil, bt)
        border:SetPoint("TOPLEFT", 1, -1)
        border:SetPoint("BOTTOMRIGHT", -1, 1)
        local borderTexs = BuildCapsule(border, KNOB / 2 + 1, C_TOGGLE_BORDER)
        for _, t in ipairs(borderTexs) do
            ours[t] = true
        end
        ours[border] = true
        local track = CreateFrame("Frame", nil, bt)
        track:SetPoint("TOPLEFT", 2, -2)
        track:SetPoint("BOTTOMRIGHT", -2, 2)
        local texs = BuildCapsule(track, KNOB / 2 + 1, ns.hui.layer.L1)
        for _, t in ipairs(texs) do
            t:SetDrawLayer("BORDER")
            ours[t] = true
        end
        ours[track] = true
        local knob = CreateFrame("Frame", nil, bt)
        knob:SetSize(KNOB, KNOB)
        local knobTex = knob:CreateTexture(nil, "ARTWORK")
        knobTex:SetTexture(HUI_CIRCLE)
        knobTex:SetAllPoints()
        local lum0 = (ns.hui.layer.L0[1] + ns.hui.layer.L0[2] + ns.hui.layer.L0[3]) / 3
        local kc0 = lum0 > 0.5 and {1, 1, 1} or C_KNOB
        knobTex:SetVertexColor(kc0[1], kc0[2], kc0[3])
        ours[knobTex] = true
        ours[knob] = true
        ns.hui.__skinRegistry[track] = nil
        track.__huiRepaints = nil
        ns.hui.AddRepaint(bt, function()
            ApplyToggleState(bt, texs, knob, false)
            local lum = (ns.hui.layer.L0[1] + ns.hui.layer.L0[2] + ns.hui.layer.L0[3]) / 3
            local kc = lum > 0.5 and {1, 1, 1} or C_KNOB
            knobTex:SetVertexColor(kc[1], kc[2], kc[3])
        end)
        local TEX_SETTERS = {
            "SetNormalTexture", "SetPushedTexture", "SetCheckedTexture",
            "SetHighlightTexture", "SetDisabledTexture",
        }
        local purging = false
        local function PurgeNative()
            if purging then return end
            purging = true
            for _, m in ipairs(TEX_SETTERS) do
                if bt[m] then
                    if not pcall(bt[m], bt, "") then
                        local getter = m:gsub("^Set", "Get")
                        if bt[getter] then
                            local ok, tex = pcall(bt[getter], bt)
                            if ok and tex then
                                tex:SetAlpha(0)
                                tex:Hide()
                            end
                        end
                    end
                end
            end
            if bt.SetBackdrop then
                pcall(bt.SetBackdrop, bt, nil)
            end
            for _, reg in ipairs({ bt:GetRegions() }) do
                if reg:GetObjectType() == "Texture" and not ours[reg] then
                    reg:SetAlpha(0)
                    reg:Hide()
                end
            end
            for _, ch in ipairs({ bt:GetChildren() }) do
                if not ours[ch] and not ch.__huiToggleKeep then
                    ch:Hide()
                end
            end
            purging = false
        end
        local function SafePurge()
            pcall(PurgeNative)
        end
        PurgeNative()
        for _, m in ipairs(TEX_SETTERS) do
            if bt[m] then
                hooksecurefunc(bt, m, SafePurge)
            end
        end
        if bt.SetBackdrop then
            hooksecurefunc(bt, "SetBackdrop", SafePurge)
        end
        bt:SetSize(TW, TH)
        if bt.Text then
            bt.Text:ClearAllPoints()
            bt.Text:SetPoint("LEFT", bt, "LEFT", TW + 2, 0)
            bt:SetHitRectInsets(0, -(bt.Text:GetWidth() or 60), 0, 0)
        end
        local origSetChecked = bt.SetChecked
        bt.SetChecked = function(self, v)
            self.__huiOn = not not v
            origSetChecked(self, v)
            SafePurge()
            ApplyToggleState(self, texs, knob, false)
        end
        local function ToggleOnUpdate(_, d)
            if not bt.__huiAnim then return end
            bt.__huiAnimEl = bt.__huiAnimEl + d
            local t = bt.__huiAnimEl >= bt.__huiAnimDur and 1 or bt.__huiAnimEl / bt.__huiAnimDur
            local e = 1 - (1 - t) * (1 - t)
            local x = bt.__huiAnimFromX + (bt.__huiAnimToX - bt.__huiAnimFromX) * e
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", bt, "LEFT", x, 0)
            knob:SetSize(KNOB, KNOB)
            local fc, tc = bt.__huiAnimFromC, bt.__huiAnimToC
            PaintTrack(texs, {
                fc[1] + (tc[1] - fc[1]) * e,
                fc[2] + (tc[2] - fc[2]) * e,
                fc[3] + (tc[3] - fc[3]) * e,
            })
            if t >= 1 then
                bt.__huiAnim = false
                bt.__huiKnobX = bt.__huiAnimToX
                bt.__huiColor = bt.__huiAnimToC
            end
        end
        bt:HookScript("OnUpdate", ToggleOnUpdate)
        bt:HookScript("OnClick", function()
            SafePurge()
            bt.__huiOn = bt:GetChecked() and true or false
            ApplyToggleState(bt, texs, knob, true)
            if bt.__huiClickTimer then
                pcall(bt.__huiClickTimer.Cancel, bt.__huiClickTimer)
            end
            bt.__huiClickTimer = ns.After(0.16, function()
                bt.__huiClickTimer = nil
                if not bt:IsShown() then return end
                bt.__huiOn = bt:GetChecked() and true or false
                ApplyToggleState(bt, texs, knob, false)
            end)
        end)
        local C_ACCENT_HOVER = { math.min(ns.hui.ACCENT[1] + 0.10, 1), math.min(ns.hui.ACCENT[2] + 0.10, 1), math.min(ns.hui.ACCENT[3] + 0.10, 1) }
        bt:HookScript("OnEnter", function()
            if not bt:IsEnabled() then return end
            bt.__huiAnim = false
            local c = bt.__huiOn and C_ACCENT_HOVER or ns.hui.layer.L5
            PaintTrack(texs, c)
            bt.__huiColor = c
        end)
        bt:HookScript("OnLeave", function()
            ApplyToggleState(bt, texs, knob, true)
        end)
        local function SyncOnShow()
            SafePurge()
            bt.__huiOn = bt:GetChecked() and true or false
            ApplyToggleState(bt, texs, knob, false)
        end
        bt:HookScript("OnShow", SyncOnShow)
        bt:HookScript("OnEnable", SyncOnShow)
        bt:HookScript("OnDisable", SyncOnShow)
        SafePurge()
        ApplyToggleState(bt, texs, knob, false)
    end

    function ns.hui.ReskinSlider(s, noWheel)
        if not s or s.__huiSlider then return end
        if ns.huiTheme ~= "hui" then return end
        s.__huiSlider = true
        for _, reg in ipairs({ s:GetRegions() }) do
            if reg:GetObjectType() == "Texture" then
                reg:Hide()
            end
        end
        if s.SetBackdrop then
            pcall(function() s:SetBackdrop(nil) end)
        end
        local function HideForeign()
            for _, ch in ipairs({ s:GetChildren() }) do
                if ch ~= s.edit and ch ~= s.button then
                    ch:Hide()
                end
            end
        end
        HideForeign()
        s:HookScript("OnShow", function()
            if s.SetBackdrop then pcall(function() s:SetBackdrop(nil) end) end
            HideForeign()
        end)
        s:SetThumbTexture(HUI_CIRCLE)
        local thumb = s:GetThumbTexture()
        if thumb then
            thumb:SetTexture(HUI_CIRCLE)
            thumb:SetSize(16, 16)
            thumb:SetVertexColor(1, 1, 1)
            thumb:Show()
        end
        local trackBg = s:CreateTexture(nil, "BACKGROUND")
        trackBg:SetColorTexture(ns.hui.layer.L1[1], ns.hui.layer.L1[2], ns.hui.layer.L1[3], 1)
        trackBg:SetPoint("LEFT", 6, 0)
        trackBg:SetPoint("RIGHT", -6, 0)
        trackBg:SetHeight(6)
        ns.hui.AddRepaint(s, function()
            trackBg:SetColorTexture(ns.hui.layer.L1[1], ns.hui.layer.L1[2], ns.hui.layer.L1[3], 1)
        end)
        local trackFill = s:CreateTexture(nil, "BORDER")
        trackFill:SetColorTexture(HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3], 1)
        trackFill:SetPoint("LEFT", 6, 0)
        trackFill:SetHeight(6)
        local function UpdateFill()
            local mn, mx = s:GetMinMaxValues()
            local v = s:GetValue()
            local ratio = 0
            if mx and mn and mx > mn then
                ratio = (v - mn) / (mx - mn)
            end
            trackFill:SetWidth((s:GetWidth() - 12) * ratio)
        end
        s:HookScript("OnValueChanged", UpdateFill)
        s:HookScript("OnSizeChanged", UpdateFill)
        if not noWheel then
            s:EnableMouseWheel(true)
            s:HookScript("OnMouseWheel", function(self, delta)
                local step = self:GetValueStep() or 1
                self:SetValue(self:GetValue() + (delta > 0 and step or -step))
            end)
        end
        if s.Text and type(s.Text) ~= "function" then s.Text:SetTextColor(1, 1, 1) end
        if s.Low and type(s.Low) ~= "function" then s.Low:SetTextColor(C_GRAY[1], C_GRAY[2], C_GRAY[3]) end
        if s.High and type(s.High) ~= "function" then s.High:SetTextColor(C_GRAY[1], C_GRAY[2], C_GRAY[3]) end
        UpdateFill()
        ns.hui.AddRepaint(s, function()
            trackFill:SetColorTexture(HUI_ACCENT[1], HUI_ACCENT[2], HUI_ACCENT[3], 1)
        end)
    end

    function ns.hui.RoundIcon(tex)
        if not tex or tex.__huiRounded then return end
        if ns.huiTheme ~= "hui" then return end
        if not tex.AddMaskTexture then return end
        local f = tex:GetParent()
        if not f then return end
        tex.__huiRounded = true
        local mask = f:CreateMaskTexture(nil, "OVERLAY")
        -- ★★ 蒙版必须按**贴图**的尺寸裁，不是父帧的尺寸。
        --    图标贴在「行 / 卡片 / 按钮」上时父帧远大于图标 —— 蒙版挂父帧的话圆角落在父帧四个角上，
        --    图标看上去就是「没倒圆角」（用户 2026-09-30 实机截图报的正是这个）。
        --    锚到贴图与官方 XML 同构（Blizzard_AzeriteEssenceUI 的 CircleMask 用
        --    TOPLEFT / BOTTOMRIGHT 锚 relativeKey="$parent.Icon"；动作条 IconMask 用 CENTER）。
        mask:SetAllPoints(tex)
        mask:SetTexture("Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundRectMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        tex:AddMaskTexture(mask)
    end

    function ns.hui.RoundImage(tex, radiusFrac)
        if not tex or tex.__huiRoundImage then return end
        if ns.huiTheme ~= "hui" then return end
        if not tex.AddMaskTexture then return end
        local f = tex:GetParent()
        if not f then return end
        tex.__huiRoundImage = true
        radiusFrac = radiusFrac or 0.02
        local mask = f:CreateMaskTexture(nil, "OVERLAY")
        mask:SetAllPoints(f)
        mask:SetTexture("Interface/AddOns/DungeonsForever/Media/LibHUI/HUIRoundImageMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        tex:AddMaskTexture(mask)
        local border = nil
        local function RebuildBorder()
            if border then
                for _, t in ipairs(border) do t:Hide() end
            end
            local w = f:GetWidth()
            if w and w > 0 then
                border = ns.hui.BuildRoundBorder(f, w * radiusFrac, ns.hui.CARD_BORDER, nil, "OVERLAY")
                for _, t in ipairs(border) do t:SetShown(true) end
            end
        end
        RebuildBorder()
        f:HookScript("OnSizeChanged", RebuildBorder)
        return mask
    end

end
