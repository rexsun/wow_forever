-- 11-06 角色面板当前等级 BiS 角标（照正式服 ui/PaperDollBis.lua / 时光服 Paperdoll.lua）：HOLD，待游戏内验收
--   用户：「当前这个等级的BIS 装备，按照正式服那样做在角落的TOOLTIP小图标」「点击可以指引获取方式」
-- 每个装备格（暴雪 CharacterHeadSlot … CharacterRangedSlot，按名字取，取不到按 GetID 在 PaperDollItemsFrame 里找）角上一个小图标：
--   推荐件 ≠ 身上   → 推荐件图标（16px，右上角内缩 1px，黑边，和正式服同款）
--   已穿 / 身上这件按当前天赋的属性分 ≥ 推荐 → 居中绿勾（图标隐藏）
--   两件都没属性数据、身上装等 ≥ 推荐 → 图标变灰（推荐不一定更好）
--   这格没推荐（副手被双手武器占了 / 数据里没候选）→ 不出
-- ⭐ BiS 规则 = 升级规划「装备」页同一套（PagePlan.lua bestGearBySlot，经 ns.PlanBestGearItems 取，⛔别另抄一份）：
--   候选 = 本职业的地下城掉落 + 职业任务链奖励 + 11-06 起商人出售（ns.Data.gear）里「需要等级 ≤ 角色当前等级」的（不 +2，穿不上的不推），
--   11-06 制造件只当备选：提示里主推荐下面多一行「也可以：<制造件>（<专业> <技能> · 找人做 / 拍卖行，+N%）」（分数比主推荐高才出；
--   拾取绑定 / 装备要求专业的只在角色有这个专业时算，ns.Prof 读角色专业），点击照旧按主推荐走
--   排除服务器没有的（ItemMissing）、只用确认掉过的（ItemRecommendIds）、40 级前不推锁甲 / 板甲；
--   按当前天赋（SpecGear.Current：手动选的 > 点数最多的那系）的属性权重打分，同分按装等 / 物品 ID 定死；
--   戒指 / 饰品两格不重复；双手 vs 单手 + 副手比总分（双持副手秒伤算一半）。网站 / 小程序 gear.json 同一份结果。
-- 悬停：推荐件原生提示（SetItemByID，没缓存用掉落页简版）+ 状态 + 获取方式 + 这件对当前天赋最值钱的属性 + 点击说明
-- 点击：掉落件 → 打开掉落页那个副本（首领 / 入口 / 攻略横幅）；右键 → 地图标副本入口 + 聊天框给路线；
--       任务件 → 地图标接任务的人（副本任务数据 / 职业任务链数据里找得到的）；
--       商人件 → 地图标商人（按阵营挑商人）+ 聊天框给售价；制造件 → 会这个专业打开「专业」页，不会就给「找人做 / 拍卖行」（ns.GearGuide，PagePlan 同一个）；
--       Shift 发聊天 / Ctrl 试穿
-- ⛔ 不碰暴雪全局、只 HookScript；按钮是我们自己建的子框（不是安全框），战斗中不新建（脱战补）
-- ⛔ 只在角色面板开着时算：事件来了面板没开直接返回
local _, ns = ...

local BC = {}
ns.BisCorner = BC

-- 槽位键（和 PagePlan 的 GEAR_* 一致）→ 背包槽名（GetInventorySlotInfo）
local SLOTS = {
    { "head", "HeadSlot" }, { "neck", "NeckSlot" }, { "shoulder", "ShoulderSlot" }, { "back", "BackSlot" },
    { "chest", "ChestSlot" }, { "wrist", "WristSlot" }, { "hands", "HandsSlot" }, { "waist", "WaistSlot" },
    { "legs", "LegsSlot" }, { "feet", "FeetSlot" }, { "finger1", "Finger0Slot" }, { "finger2", "Finger1Slot" },
    { "trinket1", "Trinket0Slot" }, { "trinket2", "Trinket1Slot" }, { "main", "MainHandSlot" },
    { "off", "SecondaryHandSlot" }, { "ranged", "RangedSlot" },
}
BC.SLOTS = SLOTS
local PAIR = { finger1 = "finger2", finger2 = "finger1", trinket1 = "trinket2", trinket2 = "trinket1" }
local INV_OF = {}
for _, s in ipairs(SLOTS) do INV_OF[s[1]] = s[2] end

local SIZE = 16
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local QM = "Interface\\Icons\\INV_Misc_QuestionMark"

local marks = {}
BC.marks = marks   -- 测试用

function BC.Enabled() return not (ns.db and ns.db.ui and ns.db.ui.bisCorner == false) end
function BC.SetEnabled(v)
    ns.db.ui = ns.db.ui or {}
    if v then ns.db.ui.bisCorner = nil else ns.db.ui.bisCorner = false end   -- ⛔ 别写 (not v) and false or nil：恒为 nil
    BC.Update()
end

local function slotId(inv)
    if not GetInventorySlotInfo then return nil end
    local ok, id = pcall(GetInventorySlotInfo, inv)
    return ok and id or nil
end

local function slotButton(inv)
    local b = _G["Character" .. inv]
    if b then return b end
    local id = slotId(inv)
    local parent = _G.PaperDollItemsFrame or _G.PaperDollFrame
    if id and parent and parent.GetChildren then
        for _, k in ipairs({ parent:GetChildren() }) do
            if k.GetID and k:GetID() == id then return k end
        end
    end
end

local function equippedId(inv)
    local id = slotId(inv)
    if not id then return nil end
    local v
    if GetInventoryItemID then v = GetInventoryItemID("player", id) end
    if not v and GetInventoryItemLink then
        local link = GetInventoryItemLink("player", id)
        v = link and tonumber(link:match("item:(%d+)"))
    end
    if ns.Secret(v) then return nil end
    return tonumber(v)
end

local function itemIlvl(id)
    if not id then return nil end
    local ok, _, _, _, lv = pcall(GetItemInfo or function() end, id)
    return ok and tonumber(lv) or nil
end

local function playerLevel(override)
    return math.max(1, math.min(60, tonumber(override) or (UnitLevel and UnitLevel("player")) or 1))
end

-- 这一格：推荐件 + 状态（"check" / "icon" / "down"）+ 判据（"worn" / "spec" / "ilvl"）
-- 戒指 / 饰品：推荐件戴在另一格也算已穿（两格互换不该提示）
function BC.Compute(lvOverride)
    local cls = ns.MyClass and ns.MyClass()
    if not (cls and ns.PlanBestGearItems) then return {}, nil, nil end
    local lv = playerLevel(lvOverride)
    local ok, best, spec, alts = pcall(ns.PlanBestGearItems, lv, cls)
    if not ok or type(best) ~= "table" then return {}, nil, lv end
    local SG = ns.SpecGear
    local eq = {}
    for _, s in ipairs(SLOTS) do eq[s[1]] = equippedId(s[2]) end
    local out = {}
    for _, s in ipairs(SLOTS) do
        local key, it = s[1], best[s[1]]
        if it then
            local e = { it = it, eq = eq[key], key = key, inv = s[2], alt = alts and alts[key] or nil }
            local scoreSlot = (key == "off") and "副手" or it.slot
            if e.eq == it.id or (PAIR[key] and eq[PAIR[key]] == it.id) then
                e.state, e.why = "check", "worn"
            else
                local sNew = spec and e.eq and SG and SG.Score(it.id, scoreSlot, cls, spec, lv) or nil
                local sOld = sNew and SG.Score(e.eq, scoreSlot, cls, spec, lv) or nil
                if sNew and sOld then
                    e.why = "spec"
                    e.state = (sOld >= sNew - 1e-6) and "check" or "icon"
                else
                    local il = e.eq and itemIlvl(e.eq)
                    if il and il >= (it.ilvl or 0) then e.state, e.why = "down", "ilvl" else e.state = "icon" end
                end
            end
            out[key] = e
        end
    end
    return out, spec, lv
end

-- ---------- 获取方式 ----------
-- 地名 → 地图编号（副本任务数据里入口 / 接任务的人都带 ui；职业任务链只给地名）
local zoneUi
local function zoneIndex()
    if zoneUi then return zoneUi end
    zoneUi = {}
    for _, d in ipairs(ns.DQ and ns.DQ.dungeons or {}) do
        local e = d.ent
        if e and e.zc and e.zc ~= "" and (e.ui or 0) > 0 then zoneUi[e.zc] = zoneUi[e.zc] or e.ui end
        for _, o in ipairs(d.off or {}) do
            if o.z and o.z ~= "" and (o.ui or 0) > 0 then zoneUi[o.z] = zoneUi[o.z] or o.ui end
        end
    end
    return zoneUi
end

-- 任务件：接任务的人 { n=, z=, x=, y=, ui= }（找不到 → nil）
function BC.QuestGiver(title)
    if not title or title == "" then return nil end
    for _, d in ipairs(ns.DQ and ns.DQ.dungeons or {}) do
        for _, o in ipairs(d.off or {}) do
            if o.c == title and o.g and (o.ui or 0) > 0 and (o.x or 0) > 0 then
                return { n = o.g, z = o.z, x = o.x, y = o.y, ui = o.ui }
            end
        end
    end
    local cls = ns.MyClass and ns.MyClass()
    for _, info in pairs(((ns.Data and ns.Data.questSeries) or {})[cls] or {}) do
        for _, v in ipairs(info.variants or {}) do
            for _, q in ipairs(v.q or {}) do
                local g = q.t == title and q.g and q.g[1]
                if g then
                    return { n = g.n, z = g.z, x = g.x, y = g.y, ui = (g.z and zoneIndex()[g.z]) or nil }
                end
            end
        end
    end
end

local function reqLv(it) return (it.req and it.req > 0) and it.req or (it.min or 0) end

-- 获取方式一行（悬停 / 聊天框共用）
function BC.SourceText(it)
    if (it.src == "craft" or it.src == "vendor") and ns.GearSourceText then return ns.GearSourceText(it) end
    if it.src == "quest" then
        local t = ns.L("任务「", "Quest \"") .. (it.srcName or "?") .. ns.L("」", "\"")
        local g = BC.QuestGiver(it.srcName)
        if g then
            t = t .. ns.L(" · 找 ", " - from ") .. (g.n or "?") .. (g.z and g.z ~= "" and (" @ " .. g.z) or "")
                .. (((g.x or 0) > 0) and string.format(" (%.0f, %.0f)", g.x, g.y) or "")
        end
        return t
    end
    return ns.L("地下城掉落：", "Dungeon drop: ") .. (it.srcName or it.dn or "?")
end

local function openLoot(dn)
    if not ns.LootShowDungeon then return false end
    ns.LootShowDungeon(dn)
    -- 主面板本来就停在掉落页 → ToggleMain 会把它关掉，再开一次
    local f = _G.GearInsightForeverMain
    if f and f.IsShown and not f:IsShown() then ns.LootShowDungeon(dn) end
    return true
end

-- 点击指引：button = "LeftButton" / "RightButton"
function BC.Guide(it, button)
    if not it then return end
    if ns.ItemModClick and ns.ItemModClick(it.id, it.n) then return "mod" end   -- Shift 发聊天 / Ctrl 试穿
    if (it.src == "craft" or it.src == "vendor") and ns.GearGuide then return ns.GearGuide(it) end
    if it.src == "quest" then
        local g = BC.QuestGiver(it.srcName)
        ns.Print(BC.SourceText(it) .. ns.L("（", " (") .. reqLv(it) .. ns.L(" 级可接）", "+)"))
        if g and g.ui and (g.x or 0) > 0 and ns.ShowOnMap then
            ns.ShowOnMap(g.ui, { { g.x, g.y } }, g.n)
            return "questmap"
        end
        return "questtext"
    end
    if button == "RightButton" then
        local d = ns.DQForDungeon and ns.DQForDungeon(it.dn)
        if d and ns.DQEntrance and ns.DQEntrance(d) then ns.DQPinEntrance(d); return "entrance" end
        ns.Print(BC.SourceText(it))
        return "droptext"
    end
    if it.dn and openLoot(it.dn) then return "loot" end
    ns.Print(BC.SourceText(it))
    return "droptext"
end

-- ---------- 悬停 ----------
local function eqName(id)
    if not id then return "|cffff5555" .. ns.L("（空）", "(empty)") .. "|r" end
    local ok, name, _, q = pcall(GetItemInfo or function() end, id)
    if ok and name then
        local c = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
        return (c and c.hex or "|cffffffff") .. name .. "|r"
    end
    return "item:" .. id
end

function BC.OnEnter(m)
    local e = m._e
    if not e then return end
    local it = e.it
    GameTooltip:SetOwner(m, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
    local fs = _G.GameTooltipTextLeft1
    local first = (GameTooltip:NumLines() or 0) > 0 and fs and fs:GetText()
    if not ok or not first or first == "" or first == RETRIEVING_ITEM_INFO then
        if ns.ItemFallbackTip then ns.ItemFallbackTip(it)
        else GameTooltip:ClearLines(); GameTooltip:AddLine(it.n or "?") end
    end
    GameTooltip:AddLine(" ")
    local cls = ns.MyClass and ns.MyClass()
    local SG = ns.SpecGear
    local si = BC.spec and SG and SG.SpecInfo(cls, BC.spec)
    GameTooltip:AddLine("|cff33ff99GearInsight " .. ns.L("无限", "Forever") .. "|r  |cff888888"
        .. string.format(ns.L("%d 级推荐", "Pick for level %d"), BC.lv or 0)
        .. (si and (ns.L(" · 天赋「", " - ") .. ns.L(si.s or si.zh, si.sEn or si.en) .. ns.L("」", "")) or "") .. "|r", 1, 1, 1)
    if e.state == "check" and e.why == "worn" then
        GameTooltip:AddLine("|T" .. CHECK .. ":12:12|t " .. ns.L("你已经穿着这件", "You're wearing this"), 0.2, 0.9, 0.2, true)
    elseif e.state == "check" then
        GameTooltip:AddLine("|T" .. CHECK .. ":12:12|t " .. ns.L("你身上这件按当前天赋的属性算不比推荐差：", "What you wear already scores at least as well: ") .. eqName(e.eq), 0.2, 0.9, 0.2, true)
    elseif e.state == "down" then
        GameTooltip:AddLine(ns.L("你现在：", "You wear: ") .. eqName(e.eq) .. ns.L("（装等不低于推荐，两件都没属性数据，推荐不一定更好）", " (ilvl not lower; no stat data to compare)"), 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(ns.L("你现在：", "You wear: ") .. eqName(e.eq), 1, 1, 1, true)
    end
    -- 获取方式：掉落那行全局物品提示（PageLoot）已经加了就不重复（10-07 用户嫌重复）
    if it.src == "quest" or it.src == "craft" or it.src == "vendor" or rawget(GameTooltip, "__gifItem") ~= it.id then
        GameTooltip:AddLine("|cff33ff99GI|r " .. ns.L("获取：", "Source: ") .. BC.SourceText(it) .. ns.L("（需要 ", " (req ") .. reqLv(it) .. ns.L(" 级）", ")"), 1, 0.82, 0.4, true)
    end
    if e.alt and ns.GearAltText then
        GameTooltip:AddLine("|cff33ff99GI|r " .. ns.GearAltText(e.alt), 0.4, 0.8, 1, true)
    end
    if si then
        local top = SG.TopStats(it.id, it.slot, cls, BC.spec, BC.lv, 3)
        if #top > 0 then GameTooltip:AddLine(ns.L("对这个天赋最值钱：", "Best stats for this spec: ") .. table.concat(top, " · "), 0.8, 0.8, 0.8, true) end
    end
    if it.src == "quest" then
        GameTooltip:AddLine(ns.L("点击：在地图上标出接任务的人", "Click: pin the quest giver on the map"), 0.55, 0.55, 0.55)
    elseif it.src == "vendor" then
        GameTooltip:AddLine(ns.L("点击：在地图上标出商人", "Click: pin the vendor on the map"), 0.55, 0.55, 0.55)
    elseif it.src == "craft" then
        local mine = ns.PlanPlayerProfs and ns.PlanPlayerProfs()[it.pf]
        GameTooltip:AddLine(mine and ns.L("点击：打开「专业」页找这个配方", "Click: open the Professions page")
            or ns.L("点击：聊天框给出制作信息（找人做 / 拍卖行）", "Click: print crafting info (crafter / AH)"), 0.55, 0.55, 0.55)
    else
        GameTooltip:AddLine(ns.L("点击：打开掉落页「", "Click: open \"") .. (it.dn or "") .. ns.L("」（首领 / 入口 / 攻略）", "\" on the Loot page"), 0.55, 0.55, 0.55)
        GameTooltip:AddLine(ns.L("右键：在地图上标出副本入口", "Right-click: pin the dungeon entrance"), 0.55, 0.55, 0.55)
    end
    GameTooltip:AddLine(ns.L("Shift + 点击：发到聊天框 · Ctrl + 点击：试穿", "Shift-click: link in chat - Ctrl-click: try on"), 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

-- ---------- 角标 ----------
local function mark(inv)
    if marks[inv] then return marks[inv] end
    if InCombatLockdown and InCombatLockdown() then BC.pendingCombat = true; return nil end
    local host = slotButton(inv)
    if not host then return nil end
    local m = CreateFrame("Button", nil, host)
    m.host = host
    m:SetFrameLevel((host.GetFrameLevel and host:GetFrameLevel() or 1) + 5)
    m:SetSize(SIZE, SIZE)
    m:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
    m.border = m:CreateTexture(nil, "BACKGROUND")
    m.border:SetPoint("TOPLEFT", -1, 1); m.border:SetPoint("BOTTOMRIGHT", 1, -1)
    m.border:SetColorTexture(0, 0, 0, 0.9)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    m.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    m.check = m:CreateTexture(nil, "OVERLAY")
    m.check:SetPoint("CENTER")
    m.check:SetSize(SIZE * 0.85, SIZE * 0.85)
    m.check:SetTexture(CHECK)
    m.check:Hide()
    if m.RegisterForClicks then m:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    m:SetScript("OnEnter", function(s) local ok, err = pcall(BC.OnEnter, s); if not ok then BC.lastErr = err end end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnClick", function(s, button) local e = s._e; if e then pcall(BC.Guide, e.it, button) end end)
    marks[inv] = m
    return m
end

local function hideAll() for _, m in pairs(marks) do m:Hide() end end

local function panelShown()
    local f = _G.PaperDollFrame or _G.CharacterFrame
    return f and f.IsShown and f:IsShown()
end

function BC.Update(lvOverride)
    if not (BC.Enabled() and panelShown()) then hideAll(); return end
    local list, spec, lv = BC.Compute(lvOverride)
    BC.spec, BC.lv = spec, lv
    local seen = {}
    for _, s in ipairs(SLOTS) do
        local e = list[s[1]]
        local m = e and mark(s[2])
        if m then
            seen[s[2]] = true
            m._e = e
            local check = e.state == "check"
            m.icon:SetShown(not check); m.border:SetShown(not check); m.check:SetShown(check)
            if not check then
                m.icon:SetTexture((e.it.i and e.it.i ~= "") and ("Interface\\Icons\\" .. e.it.i) or QM)
                m.icon:SetDesaturated(e.state == "down")
            end
            m:Show()
        end
    end
    for inv, m in pairs(marks) do if not seen[inv] then m:Hide(); m._e = nil end end
end

local function safeUpdate(lv) local ok, err = pcall(BC.Update, lv); if not ok then BC.lastErr = err end end

function BC.Hook()
    if BC.hooked then return end
    local f = _G.PaperDollFrame or _G.CharacterFrame
    if not (f and f.HookScript) then return end
    BC.hooked = true
    f:HookScript("OnShow", function()
        safeUpdate()
        -- 等一帧：OnShow 时装备信息 / 槽按钮布局可能还没就绪
        if C_Timer and C_Timer.After then C_Timer.After(0, function() safeUpdate() end) end
    end)
    f:HookScript("OnHide", hideAll)
end

local ev = CreateFrame("Frame")
BC.ev = ev
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "PLAYER_ENTERING_WORLD" then BC.Hook(); return end
    if e == "PLAYER_REGEN_ENABLED" then
        if not BC.pendingCombat then return end
        BC.pendingCombat = nil
    end
    -- 升级事件里 UnitLevel 可能还是旧的 → 用事件给的新等级
    safeUpdate(e == "PLAYER_LEVEL_UP" and a1 or nil)
end)

table.insert(ns.modules, function() BC.Hook() end)

-- /gi bis：开 / 关
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.bis = function()
    BC.SetEnabled(not BC.Enabled())
    ns.Print(BC.Enabled() and ns.L("角色面板推荐装备角标：已开", "Character panel BiS corner icons: on")
        or ns.L("角色面板推荐装备角标：已关", "Character panel BiS corner icons: off"))
end
