-- 升级指引：按当前等级显示该去的地图（本阵营 + 争夺 + 《无限》新增）、能打的地下城、下一个里程碑
local _, ns = ...

local frame

-- 11-12 玩家 Eason「左上角的推荐升级路线和睡袋任务流程，关闭后怎么再开启」：
--   ① 开关按角色存（leveling.hide[角色]），关一次不再连坐小号 / 新角色；老存档账号级 shown=false 只算到第一个登录的角色头上
--   ② × 关掉时聊天框告诉玩家怎么找回；③ 小窗里带上当前该做的任务线（睡袋）+「升级规划」「路线」两个按钮
local function charKey() return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?") end
local function lvdb()
    ns.db.leveling = ns.db.leveling or {}
    local d = ns.db.leveling
    d.hide = d.hide or {}
    if d.shown == false then d.hide[charKey()] = true end
    d.shown = nil
    return d
end
function ns.LevelingShown() return not lvdb().hide[charKey()] end
local function setShown(on) lvdb().hide[charKey()] = (not on) and true or nil end

local function closedHint()
    local C = ns.SlashHint or "/gif"
    ns.Print(ns.L("升级指引已关闭（只对这个角色）：输入 " .. C .. " lv，或右键小地图按钮 →「升级指引小窗」重新打开",
        "Leveling guide closed for this character: type " .. C .. " lv or right-click the minimap button to reopen"))
end

-- 当前等级该做 / 快能做的任务线（没做完；提前 4 级预告）：返回 c, n, total
function ns.LevelingChain()
    local SC = ns.SideChains
    if not (SC and SC.Progress and ns.SideChainsData) then return nil end
    local lv = tonumber(UnitLevel and UnitLevel("player")) or 1
    local fac = SC.Faction and SC.Faction() or "Alliance"
    for _, c in ipairs(ns.SideChainsData) do
        if lv >= (c.minLv or 1) - 4 then
            local ok, _, n, total = pcall(SC.Progress, c, fac)
            if ok and type(total) == "number" and total > 0 and (tonumber(n) or 0) < total then return c, n, total end
        end
    end
    return nil
end

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
    local c, n, total = ns.LevelingChain()
    if c then
        local L = ns.L
        local lvTip = (level < (c.minLv or 1)) and string.format(L("（%d 级能接）", " (from level %d)"), c.minLv) or ""
        text = text .. "\n|cffffd100" .. L("任务线", "Quest line") .. "|r  |cffff9933" .. ns.EnSafe(L(c.t, c.tEn)) .. "|r  |cff888888"
            .. (n or 0) .. "/" .. total .. lvTip .. "|r\n  " .. ns.EnSafe(L(c.gist, c.gistEn))
        frame.chainBtn.chain = c
        frame.chainBtn:SetText(L("路线：", "Route: ") .. L(c.t, c.tEn))
        frame.chainBtn:Show()
    else
        frame.chainBtn.chain = nil
        frame.chainBtn:Hide()
    end
    frame.body:SetText(text)
    frame:SetHeight(frame.body:GetStringHeight() + 70)
end

local function build()
    local f = CreateFrame("Frame", "GearInsightForeverLeveling", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    -- 11-07 玩家截图（升级指引小窗压在右边的任务追踪上）：默认位置从右上 -220 挪到屏幕左侧中上，不挡任务追踪 / 小地图；拖过的照旧用存的位置
    f:SetSize(340, 160); f:SetPoint("TOPLEFT", 30, -260)
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
    close:SetScript("OnClick", function() setShown(false); f:Hide(); closedHint() end)
    -- 底部两个按钮：升级规划页（睡袋等任务线、逐级待办都在那）· 当前任务线的逐步路线弹框
    f.planBtn = ns.Button(f, ns.L("升级规划", "Leveling plan"), 96, 22, function()
        if ns.OpenPage then ns.OpenPage("plan") elseif ns.ToggleMain then ns.ToggleMain("plan") end
    end)
    f.planBtn:SetPoint("BOTTOMLEFT", 10, 8)
    f.chainBtn = ns.Button(f, "", 200, 22, function(self)
        local c = rawget(self, "chain")
        if c and ns.SideChains and ns.SideChains.Show then ns.SideChains.Show(c) end
    end)
    f.chainBtn:SetPoint("LEFT", f.planBtn, "RIGHT", 6, 0); f.chainBtn:Hide()
    -- 11-05 战绩卡二维码下线：小窗底部的「战绩卡」按钮去掉
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
        frame:Hide(); setShown(false); closedHint()
    else
        setShown(true); frame:Show(); refresh()
    end
end

-- 设置页勾选框：直接设成开 / 关（不打找回提示，勾选框本身就是找回入口）
function ns.SetLevelingShown(on)
    setShown(on)
    if on then frame = frame or build(); frame:Show(); refresh()
    elseif frame then frame:Hide() end
end

-- 11-12 重构第 1 期：拖到屏幕外 / 找不着时放回默认位置（存的位置一起清）
function ns.ResetLevelingPos()
    lvdb().pos = nil
    if frame then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", 30, -260) end
end

ns.RegisterWindow({ key = "leveling", order = 10, title = function() return ns.L("升级指引小窗", "Leveling guide") end,
    state = function()
        if frame and frame:IsShown() then return ns.L("显示中", "Shown") end
        return ns.LevelingShown() and ns.L("已开（满级后登录不自动弹）", "On (not auto-shown at 60)") or ns.L("已关闭", "Closed")
    end,
    actions = function()
        local on = frame and frame:IsShown()
        return {
            { text = on and ns.L("关闭", "Hide") or ns.L("打开", "Show"), fn = function() ns.SetLevelingShown(not on) end },
            { text = ns.L("重置位置", "Reset position"), fn = function() ns.ResetLevelingPos() end },
        }
    end })

table.insert(ns.modules, function()
    -- 满级以下默认显示；关掉后按角色记住
    if ns.LevelingShown() and (UnitLevel("player") or 1) < 60 then
        build():Show()
    end
end)
