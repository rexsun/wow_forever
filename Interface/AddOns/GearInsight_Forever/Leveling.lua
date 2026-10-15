-- 升级指引：按当前等级显示该去的地图（本阵营 + 争夺 + 《无限》新增）、能打的地下城、下一个里程碑
local _, ns = ...

local frame

local function range(s)
    s = tostring(s or ""):gsub("–", "-")
    local a, b = s:match("(%d+)%s*%-%s*(%d+)")
    if a then return tonumber(a), tonumber(b) end
    local x = tonumber(s:match("(%d+)"))
    return x, x
end

local function join(t) return table.concat(t or {}, "、") end

function ns.LevelingText(level, faction)
    local D = ns.Data.leveling
    local L = ns.L
    local out = {}
    local horde = (faction == "Horde")
    for _, z in ipairs(D.zones) do
        local lo, hi = range(z.lv)
        if lo and level >= lo and level < (hi == 60 and 61 or hi) then
            out[#out + 1] = "|cffffd100" .. L("推荐地图", "Zones") .. "（" .. z.lv .. "）|r"
            local own = horde and L(join(z.h), join(z.hEn)) or L(join(z.a), join(z.aEn))
            if own ~= "" then out[#out + 1] = "  " .. own end
            local c = L(join(z.c), join(z.cEn))
            if c ~= "" then out[#out + 1] = "  " .. L("争夺：", "Contested: ") .. c end
            for _, f in ipairs(z.fv or {}) do
                out[#out + 1] = "  |cff33ff99" .. L("《无限》新增", "New") .. "|r " .. L(f.n, f.nEn) .. "（" .. f.lv .. "）" .. L(f.d, f.dEn)
            end
            break
        end
    end
    local ds = {}
    for _, d in ipairs(D.dungeons) do
        local lo, hi = range(d.lv)
        if lo and level >= lo - 2 and level <= hi then
            ds[#ds + 1] = L(d.n, d.nEn) .. "（" .. d.lv .. "）"
        end
    end
    if #ds > 0 then
        out[#out + 1] = "|cffffd100" .. L("能打的地下城", "Dungeons") .. "|r"
        out[#out + 1] = "  " .. table.concat(ds, "、")
    end
    for _, m in ipairs(D.milestones) do
        if m.lv > level then
            out[#out + 1] = "|cffffd100" .. L("下一站", "Next") .. "：" .. m.lv .. L(" 级 ", " ") .. L(m.t, m.tEn) .. "|r"
            out[#out + 1] = "  " .. L(m.d, m.dEn)
            break
        end
    end
    if level >= 60 then
        for _, r in ipairs(D.raids) do
            out[#out + 1] = "|cffffd100" .. L("团本", "Raid") .. "|r " .. L(r.n, r.nEn) .. " · " .. r.size .. " · " .. r.open
        end
    end
    return ns.EnSafe(table.concat(out, "\n"))
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    frame.title:SetText(ns.EnSafe(ns.L("升级指引 · ", "Leveling · ") .. level .. ns.L(" 级", "")))
    local text = ns.LevelingText(level, faction)
    local pace = ns.LevelPaceLine and ns.LevelPaceLine(level)     -- 众包升级用时（数据包）
    if pace then text = "|cff99ccff" .. ns.EnSafe(pace) .. "|r\n" .. text end
    frame.body:SetText(text)
    frame:SetHeight(frame.body:GetStringHeight() + 70)
end

local function build()
    local f = CreateFrame("Frame", "GearInsightForeverLeveling", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(340, 160); f:SetPoint("TOPRIGHT", -220, -220)
    f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.leveling.pos = { p, rp, x, y }
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.75)
    end
    local pos = ns.db.leveling.pos
    if pos then f:ClearAllPoints(); f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", 12, -30); f.body:SetWidth(316)
    f.body:SetJustifyH("LEFT"); f.body:SetSpacing(2)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0); close:SetScale(0.8)
    close:SetScript("OnClick", function() ns.db.leveling.shown = false; f:Hide() end)
    local card = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    card:SetSize(120, 20); card:SetPoint("BOTTOMLEFT", 10, 8)
    card:SetText(ns.L("战绩卡", "Beta card"))
    card:SetScript("OnClick", function() ns.ShowCardQR() end)
    f:SetScript("OnShow", refresh)
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() C_Timer.After(0.5, refresh) end)
    f:Hide()
    frame = f
    return f
end

function ns.ToggleLeveling()
    frame = frame or build()
    if frame:IsShown() then
        frame:Hide(); ns.db.leveling.shown = false
    else
        ns.db.leveling.shown = true; frame:Show(); refresh()
    end
end

table.insert(ns.modules, function()
    -- 满级以下默认显示；关掉后记住
    if ns.db.leveling.shown and (UnitLevel("player") or 1) < 60 then
        build():Show()
    end
end)
