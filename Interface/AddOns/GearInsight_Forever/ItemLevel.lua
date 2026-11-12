-- 11-10 共建看板 GI-213「需要装等插件」：《无限》客户端（经典旧世引擎）鼠标提示不写物品等级，角色面板也没有平均装等 →
--   ① 装备的鼠标提示加一行「物品等级 N」（提示里已经有就不加）
--   ② 角色面板：每个装备格底部写装等（品质色），面板顶上写「平均装等 X」（17 格算：空格算 0，双手武器且副手空 = 主手算两次）
--   ③ 背包：装备格底部写装等（经典背包框 ContainerFrameN / ContainerFrameNItemM）
--   开关 ns.db.ui.ilvl（nil = 开）：设置页「界面」栏 / /gi ilvl on|off
-- ⛔ 不碰暴雪全局、只 HookScript / hooksecurefunc；字是我们自己建的子框（不吃鼠标，不是安全框）
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local IL = {}
ns.ItemLevel = IL

function IL.Enabled() return not (ns.db and ns.db.ui and ns.db.ui.ilvl == false) end
function IL.SetOn(on)
    ns.db.ui = ns.db.ui or {}
    if on then ns.db.ui.ilvl = nil else ns.db.ui.ilvl = false end
    IL.RefreshAll()
end

local function clean(v)
    if v == nil or (ns.Secret and ns.Secret(v)) then return nil end
    return v
end

-- 链接 / ID → 装等, 品质, 装备位（不是装备 → nil）
local NOT_GEAR = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true,
    INVTYPE_AMMO = true, INVTYPE_BODY = true, INVTYPE_TABARD = true }
function IL.Info(item)
    item = clean(item)
    if not item then return nil end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local ok, _, _, q, lv, _, _, _, _, loc = pcall(get, item)
    if not ok then return nil end
    lv, q, loc = tonumber(clean(lv)), tonumber(clean(q)), clean(loc)
    if not lv or lv <= 0 or NOT_GEAR[loc or ""] then return nil end
    return lv, q or 1, loc
end

local function qcolor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- 给一个按钮挂装等字（我们自己的子框，不吃鼠标）
local function label(b)
    local f = rawget(b, "__giIlvl")
    if f then return f end
    f = CreateFrame("Frame", nil, b)
    f:SetAllPoints(b)
    if f.EnableMouse then f:EnableMouse(false) end
    f:SetFrameLevel((b.GetFrameLevel and b:GetFrameLevel() or 0) + 3)
    f.t = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.t:SetPoint("BOTTOM", 0, 2)
    rawset(b, "__giIlvl", f)
    return f
end
IL.Label = label

local function setLabel(b, item)
    if not b then return end
    local lv, q = nil, nil
    if IL.Enabled() then lv, q = IL.Info(item) end
    local f = rawget(b, "__giIlvl")
    if not lv then if f then f:Hide() end return end
    f = label(b)
    f.t:SetText(lv)
    f.t:SetTextColor(qcolor(q))
    f:Show()
end
IL.SetLabel = setLabel

-- ---------- 角色面板 ----------
IL.SLOTS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

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
local function equipped(inv)
    local id = slotId(inv)
    local link = id and GetInventoryItemLink and clean(GetInventoryItemLink("player", id))
    return link
end

-- 平均装等：17 格，空格算 0；双手武器且副手空 → 主手算两次
function IL.Average()
    local sum, n, any = 0, 0, false
    local mainLv, mainLoc, offEmpty
    for _, inv in ipairs(IL.SLOTS) do
        local lv, _, loc = IL.Info(equipped(inv))
        n = n + 1
        if lv then sum = sum + lv; any = true end
        if inv == "MainHandSlot" then mainLv, mainLoc = lv, loc end
        if inv == "SecondaryHandSlot" then offEmpty = (lv == nil) end
    end
    if not any then return nil end
    if offEmpty and mainLv and mainLoc == "INVTYPE_2HWEAPON" then sum = sum + mainLv end
    return sum / n
end

local avgFrame
local function panel() return _G.PaperDollFrame or _G.CharacterFrame end
function IL.UpdatePanel()
    local p = panel()
    if not (p and p.IsShown and p:IsShown()) then return end
    for _, inv in ipairs(IL.SLOTS) do setLabel(slotButton(inv), equipped(inv)) end
    if not avgFrame then
        avgFrame = CreateFrame("Frame", nil, p)
        avgFrame:SetSize(160, 16)
        avgFrame:SetPoint("TOP", p, "TOP", 0, -56)
        avgFrame.t = avgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avgFrame.t:SetPoint("CENTER")
    end
    local a = IL.Enabled() and IL.Average()
    if a then
        avgFrame.t:SetText(string.format(L("平均装等 %.1f", "Avg iLvl %.1f"), a))
        avgFrame:Show()
    else
        avgFrame:Hide()
    end
end

-- ---------- 背包 ----------
local function containerLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then return clean(C_Container.GetContainerItemLink(bag, slot)) end
    if GetContainerItemLink then return clean(GetContainerItemLink(bag, slot)) end
end
function IL.UpdateBags()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf.IsShown and cf:IsShown() then
            local bag = cf.GetID and cf:GetID()
            local size = tonumber(rawget(cf, "size")) or 36
            for j = 1, size do
                local b = _G["ContainerFrame" .. i .. "Item" .. j]
                if b and b.GetID and bag then setLabel(b, containerLink(bag, b:GetID())) end
            end
        end
    end
end

function IL.RefreshAll()
    pcall(IL.UpdatePanel)
    pcall(IL.UpdateBags)
end

-- ---------- 鼠标提示 ----------
local function hasIlvlLine(tt)
    local name = tt.GetName and tt:GetName()
    if not name then return false end
    for i = 2, math.min(tt.NumLines and tt:NumLines() or 0, 8) do
        local fs = _G[name .. "TextLeft" .. i]
        local t = fs and clean(fs:GetText())
        if type(t) == "string" and (t:find("物品等级", 1, true) or t:find("Item Level", 1, true) or t:find("物品等級", 1, true)) then return true end
    end
    return false
end
function IL.AddToTooltip(tt, item)
    if not IL.Enabled() or not item or rawget(tt, "__giIlvlDone") == item then return false end
    local lv = IL.Info(item)
    if not lv or hasIlvlLine(tt) then return false end
    rawset(tt, "__giIlvlDone", item)
    tt:AddLine(string.format(L("物品等级 %d", "Item Level %d"), lv), 1, 0.82, 0)
    tt:Show()
    return true
end

local function hook()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, d)
            local item = d and (clean(d.hyperlink) or clean(d.id))
            if item then pcall(IL.AddToTooltip, tt, item) end
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then
            tt:HookScript("OnTooltipCleared", function(self) rawset(self, "__giIlvlDone", nil) end)
            if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) and tt:HasScript("OnTooltipSetItem") then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if link then pcall(IL.AddToTooltip, self, link) end
                end)
            end
        end
    end
    local p = panel()
    if p and p.HookScript then
        p:HookScript("OnShow", function()
            pcall(IL.UpdatePanel)
            if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(IL.UpdatePanel) end) end
        end)
    end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf.HookScript then cf:HookScript("OnShow", function() pcall(IL.UpdateBags) end) end
    end
    if hooksecurefunc and type(_G.ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", function() pcall(IL.UpdateBags) end)
    end
end
table.insert(ns.modules, function() pcall(hook) end)

local ev = CreateFrame("Frame")
IL.ev = ev
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do pcall(ev.RegisterEvent, ev, e) end
local pending = false
ev:SetScript("OnEvent", function()
    if pending then return end
    pending = true
    local function run() pending = false; IL.RefreshAll() end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end)
IL._event = ev:GetScript("OnEvent")   -- 测试用

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.ilvl = function(rest)
    local a = tostring(rest or ""):lower()
    if a == "on" or a == "off" then IL.SetOn(a == "on") end
    local avg = IL.Average()
    ns.Print((IL.Enabled() and L("装等显示开着（/gi ilvl off 关掉）", "Item level display on (/gi ilvl off)")
        or L("装等显示关了（/gi ilvl on 打开）", "Item level display off (/gi ilvl on)"))
        .. (avg and string.format(L("；你现在平均装等 %.1f", "; your average item level is %.1f"), avg) or ""))
end
ns.ExtraSlash["装等"] = ns.ExtraSlash.ilvl
