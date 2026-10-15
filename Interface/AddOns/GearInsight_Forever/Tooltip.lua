-- 鼠标提示：技能 / 天赋 / 种族天赋 上加一行「《无限》改了什么」
-- 按名字查（数据里没有《无限》的法术 ID）：中文客户端用中文名，其它用英文名（小写）
local _, ns = ...

local function lookup(name)
    if ns.Secret(name) or type(name) ~= "string" or name == "" then return nil end
    local notes = ns.Data.notes
    return notes[name] or notes[name:lower()]
end

local function firstLine(tt)
    local fs = _G[(tt:GetName() or "") .. "TextLeft1"]
    local t = fs and fs:GetText()
    if ns.Secret(t) then return nil end
    return t
end

local function addNote(tt, name)
    if tt.__gifDone then return end
    if ns.Secret(name) then return end
    name = name or firstLine(tt)
    if not name then return end
    local n = lookup(name)
    local text = n and ns.L(n.cn, n.en)
    if text == "" then text = nil end
    local latest = ns.PackNote and ns.PackNote(name)      -- 数据包：Beta 最新一版改了什么（更新器每天刷新）
    if not text and not latest then return end
    tt.__gifDone = true
    tt:AddLine(" ")
    if text then tt:AddLine("|cff33ff99GI 无限|r " .. text, 1, 0.82, 0.4, true) end
    if latest then tt:AddLine("|cff33ff99GI|r " .. latest, 0.6, 0.9, 1, true) end
    tt:Show()
end

local function onSpell(tt)
    local name
    if tt.GetSpell then
        local a, b = tt:GetSpell()
        if ns.Secret(a) or ns.Secret(b) then return end
        name = type(a) == "string" and a or nil
        if not name and type(b) == "number" and GetSpellInfo then name = GetSpellInfo(b) end
    end
    addNote(tt, name)
end

local function hook(tt)
    if not tt or tt.__gifHooked then return end
    tt.__gifHooked = true
    tt:HookScript("OnTooltipCleared", function(self) self.__gifDone = nil end)
    if tt:HasScript("OnTooltipSetSpell") then
        tt:HookScript("OnTooltipSetSpell", function(self) pcall(onSpell, self) end)
    end
    -- 天赋面板：SetTalent 不一定触发 OnTooltipSetSpell，按天赋名查
    if tt.SetTalent then
        hooksecurefunc(tt, "SetTalent", function(self, tab, idx)
            local name = GetTalentInfo and GetTalentInfo(tab, idx)
            addNote(self, name)
        end)
    end
end

table.insert(ns.modules, function()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
            local id = data and data.id
            if ns.Secret(id) or not id then return end
            pcall(function() addNote(tt, GetSpellInfo and GetSpellInfo(id)) end)
        end)
        GameTooltip:HookScript("OnTooltipCleared", function(self) self.__gifDone = nil end)
        if GameTooltip.SetTalent then
            hooksecurefunc(GameTooltip, "SetTalent", function(self, tab, idx)
                addNote(self, GetTalentInfo and GetTalentInfo(tab, idx))
            end)
        end
    else
        hook(GameTooltip)
    end
    hook(ItemRefTooltip)
end)

ns.TooltipLookup = lookup

-- ---------- 客户端没汉化的物品效果英文 → 中文（10-07 用户截图「确保都翻译」）----------
-- 句式模板 ns.TipZh（TooltipZh.lua，gi_forever_tooltip_zh.py 从掉落数据的中英对照生成）：英文里的数字抠成占位，
-- 套中了就**原地**把这一行换成中文，数字用客户端这一行的（客户端数值常和我们数据不同，例：我们 174 / 客户端 803 法力）
local PREFIX = { { "使用：", "使用：" }, { "装备：", "装备：" }, { "击中时可能：", "击中时可能：" },
    { "Use: ", "使用：" }, { "Equip: ", "装备：" }, { "Chance on hit: ", "击中时可能：" }, { "Chance On Hit: ", "击中时可能：" } }
local function normEn(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("(%d)%s*秒", "%1 sec"):gsub("(%d)%s*分钟", "%1 min")
    s = s:gsub("%f[A-Za-z]secs?%f[^A-Za-z]%.?", "sec"):gsub("%f[A-Za-z]mins?%f[^A-Za-z]%.?", "min")
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end
function ns.TranslateLine(text)
    if not text or not ns.TipZh then return nil end
    if not text:find("[A-Za-z][A-Za-z]+ [A-Za-z][A-Za-z]+") then return nil end
    local pre, body = "", text
    for _, p in ipairs(PREFIX) do
        if text:sub(1, #p[1]) == p[1] then pre, body = p[2], text:sub(#p[1] + 1); break end
    end
    body = normEn(body)
    local cd = ""
    local cdn, cdu = body:match("%s*%(([%d%.]+) ([A-Za-z]+)%.? Cooldown%)$")
    if cdn then
        body = body:gsub("%s*%([%d%.]+ [A-Za-z]+%.? Cooldown%)$", "")
        local u = cdu:lower()
        cd = "（" .. cdn .. ((u:find("^min") and "分钟") or (u:find("^sec") and "秒") or (u:find("^hour") and "小时") or (u:find("^day") and "天") or cdu) .. "冷却）"
    end
    for _, t in ipairs(ns.TipZh) do
        local caps = { body:match(t[1]) }
        if caps[1] then
            local zh = t[2]:gsub("%%(.)", function(c)
                if c == "%" then return "%" end
                local v = caps[tonumber(c) or 0]
                return v or ""
            end)
            return pre .. zh .. "。" .. cd
        end
    end
end
-- 一个物品提示：逐行看，有成句英文的套模板；第一行（物品名）是英文且我们有中文名 → 换中文名
function ns.TranslateTip(tt, zhName)
    if not ns.zh or not tt or not tt.GetName then return 0 end
    local name, n = tt:GetName(), 0
    if not name then return 0 end
    for i = 1, (tt.NumLines and tt:NumLines() or 0) do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            if i == 1 and zhName and zhName ~= "" and text:find("^[%w%s'%-:,%.]+$") and text:find("[A-Za-z]") then
                fs:SetText(zhName); n = n + 1
            else
                local zh = ns.TranslateLine(text)
                if zh then fs:SetText(zh); n = n + 1 end
            end
        end
    end
    if n > 0 and tt.Show then tt:Show() end
    return n
end
