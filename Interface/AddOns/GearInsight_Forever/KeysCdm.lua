-- 官方冷却管理器上印快捷键（10-17 用户「官方冷却器上印快捷键」）：HOLD
-- 暴雪冷却管理器（EssentialCooldownViewer / UtilityCooldownViewer / BuffIconCooldownViewer）每个图标右上角叠一个小字 = 这个技能在动作条上的键。
--   键按「当前实际形态」算：变熊后槌击显示熊形态页那格的键（形态页用主条同位键 1 至 =）。
--   ⛔ 只在图标上挂我们自己的 FontString（自己的子对象），不改暴雪图标的属性、不调它的方法（读字段 / 读 C_CooldownViewer 而已），避免污染。
--   《无限》客户端有没有冷却管理器不确定：全部判空 + pcall；没有就什么都不做。/gi keys cdm 诊断。
local _, ns = ...; ns = _G.GearInsightForever or ns

local KC = {}
ns.KeysCdm = KC
KC.VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }

local overlays = setmetatable({}, { __mode = "k" })   -- 图标帧 → 我们的 FontString（不往暴雪帧上挂字段）
KC._ov = overlays   -- 测试用

function KC.Enabled()
    local ui = ns.db and ns.db.ui
    return not (ui and ui.cdmKeys == false)   -- 默认开
end
function KC.SetEnabled(on)
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.cdmKeys = on and true or false
    KC.Refresh()
end

-- 这个客户端有没有冷却管理器
function KC.Available()
    for _, n in ipairs(KC.VIEWERS) do if _G[n] then return true end end
    return false
end

local function shortKey(k)
    if ns.KeysShortKey then return ns.KeysShortKey(k) end
    if not k then return nil end
    return (k:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"))
end

-- 图标帧列表：优先 viewer:GetItemFrames()，没有就退回子帧
local function itemFrames(v)
    local out = {}
    if type(v.GetItemFrames) == "function" then
        local ok, list = pcall(v.GetItemFrames, v)
        if ok and type(list) == "table" then
            for _, f in ipairs(list) do out[#out + 1] = f end
            if #out > 0 then return out end
        end
    end
    if type(v.GetChildren) == "function" then
        local kids = { pcall(v.GetChildren, v) }
        for i = 2, #kids do
            local f = kids[i]
            if type(f) == "table" and (rawget(f, "cooldownID") or rawget(f, "Icon") or rawget(f, "spellID")) then out[#out + 1] = f end
        end
    end
    return out
end

-- 图标 → 技能编号：字段 spellID / cooldownInfo，再按 cooldownID 查 C_CooldownViewer
local function iconSpell(f)
    local sid = rawget(f, "overrideSpellID") or rawget(f, "spellID")
    local info = rawget(f, "cooldownInfo")
    if not sid and type(info) == "table" then sid = info.overrideSpellID or info.spellID end
    local cid = rawget(f, "cooldownID")
    if not sid and cid and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, ci = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
        if ok and type(ci) == "table" then sid = ci.overrideSpellID or ci.spellID end
    end
    return sid, cid
end

local function spellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then return n end
    end
end

-- 当前实际形态的视图（不看键位页手动选的那个）
local function actualView()
    local K = ns.Keys
    if not (K and K.Forms and K.Forms()) then return nil end
    local f = K.FormByKey and K.CurrentFormKey and K.FormByKey(K.CurrentFormKey())
    return f and { key = f.key, page = f.page } or nil
end

-- 技能名 → 键（当前形态）
function KC.KeyOfSpell(name, live)
    if not name then return nil end
    local l = live and live[name]
    return l and l.key or nil
end

local function overlay(f)
    local fs = overlays[f]
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        fs:SetJustifyH("RIGHT")
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        overlays[f] = fs
    end
    -- 字号随图标大小（读尺寸是安全的）
    local okw, w = pcall(f.GetWidth, f)
    local size = (okw and type(w) == "number" and w > 0) and math.max(9, math.min(16, math.floor(w * 0.30))) or 12
    if fs.SetFont then
        local font = (fs.GetFont and select(1, fs:GetFont())) or "Fonts\\ARIALN.TTF"
        pcall(fs.SetFont, fs, font, size, "OUTLINE")
    end
    return fs
end

local last = {}   -- 诊断用：上一次刷新的结果
function KC.Refresh()
    last = { viewers = {}, icons = {} }
    local K = ns.Keys
    local on = KC.Enabled()
    local live = {}
    local view = actualView()
    if on and K and K.LiveMap then
        local ok, m = pcall(K.LiveMap, view)
        if ok and type(m) == "table" then live = m end
        -- 变身中：形态页那 12 格（用主条同位键 1 至 =）优先 —— 变熊后槌击显示熊页那格的键
        if view and view.page and K.MainPosSlot and K.SlotInfo and K.SlotKey then
            for n = 1, 12 do
                local okp, sl = pcall(K.MainPosSlot, n, view)
                local info = okp and sl and K.SlotInfo(sl)
                local k = info and info.name and K.SlotKey(sl)
                if k then live[info.name] = { slot = sl, key = k } end
            end
        end
    end
    for _, vn in ipairs(KC.VIEWERS) do
        local v = _G[vn]
        if v then
            local frames = itemFrames(v)
            last.viewers[#last.viewers + 1] = vn .. ":" .. #frames
            for _, f in ipairs(frames) do
                local sid, cid = iconSpell(f)
                local name = spellName(sid)
                local key = on and KC.KeyOfSpell(name, live) or nil
                last.icons[#last.icons + 1] = string.format("%s>%s>%s>%s", tostring(cid), tostring(sid), tostring(name), tostring(key))
                if key then
                    local fs = overlay(f)
                    fs:SetText(shortKey(key))
                    fs:Show()
                elseif overlays[f] then
                    overlays[f]:Hide()
                end
            end
        end
    end
end

-- 节流 0.2 秒
local pending = false
function KC.Queue()
    if pending then return end
    pending = true
    local function run() pending = false; pcall(KC.Refresh) end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end

-- 冷却管理器重排 / 显示时刷新（只 hook，不改它）
local hooked = {}
local function hookViewers()
    for _, vn in ipairs(KC.VIEWERS) do
        local v = _G[vn]
        if v and not hooked[vn] then
            hooked[vn] = true
            if hooksecurefunc then
                for _, m in ipairs({ "RefreshLayout", "RefreshData", "Layout" }) do
                    if type(v[m]) == "function" then pcall(hooksecurefunc, v, m, KC.Queue) end
                end
            end
            if v.HookScript then pcall(v.HookScript, v, "OnShow", KC.Queue) end
        end
    end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR", "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED", "ADDON_LOADED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
    hookViewers()
    KC.Queue()
end)
-- 11-13 第 4 期：_Class 晚于进世界才加载（存档开着钉板 / HUD 等，登录后条件加载）→ 进世界那一下错过了，补跑一次
ns.AddInit(function()
    if IsLoggedIn and IsLoggedIn() then hookViewers(); KC.Queue() end
end)

-- /gi keys cdm 诊断
function KC.Diag()
    hookViewers()
    pcall(KC.Refresh)
    local out = { "GICDM1", "on=" .. tostring(KC.Enabled()), "has=" .. tostring(KC.Available()),
        "form=" .. tostring((actualView() or {}).key), "viewers=" .. table.concat(last.viewers or {}, "/") }
    out[#out + 1] = "icons=" .. table.concat(last.icons or {}, ",")
    if ns.ShowBox then
        ns.ShowBox(ns.L("冷却管理器快捷键诊断", "Cooldown manager keys diag"), ns.L("Ctrl+C 复制发给开发者", "Ctrl+C to copy"), table.concat(out, ";"))
    end
    return table.concat(out, ";")
end
