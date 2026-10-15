-- 用数据包（ns.Pack，DataPack.lua，更新器每天刷新）的三处：
--   ① 技能 / 天赋鼠标提示：Beta 最新一版改了什么（Tooltip.lua 的静态说明之外再加一行）
--   ② 怪物鼠标提示：「已杀死 N 名公测玩家」（众包死亡记录）
--   ③ 升级小窗：「这一级大家平均 X 分钟，你已用 Y 分钟」（众包升级用时中位数）
-- GIF_PACK 字段见 docs/forever-addon-link-protocol.md ⑤；缺哪块就不显示哪块。
local _, ns = ...

local MIN_KILLS = 3          -- 少于 3 次的不显示（样本太少像在吓人）
ns.Pack = _G.GIF_PACK        -- DataPack.lua 在 toc 里排在本文件前面（全局表 GIF_PACK）

function ns.PackNote(name)
    local P = ns.Pack
    if not P or not P.notes or not name or name == "" then return nil end
    local n = P.notes[name] or P.notes[name:lower()]
    if not n then return nil end
    local text = ns.L(n.cn, n.en)
    if not text or text == "" then return nil end
    return ns.EnSafe(ns.L("Beta 最新改动", "Latest beta change") .. (n.d and ("（" .. n.d .. "）") or "") .. "：" .. text)
end

function ns.KillerLine(npcId)
    local P = ns.Pack
    local k = P and P.killers and P.killers[npcId]
    if not k or (k.n or 0) < MIN_KILLS then return nil end
    return ns.L("已杀死 ", "Has killed ") .. k.n .. ns.L(" 名公测玩家", " beta players")
end

-- 升级小窗附加行：level = 当前等级；比的是「从 level 升到 level+1」
function ns.LevelPaceLine(level)
    local P = ns.Pack
    local med = P and P.lvlMin and P.lvlMin[level + 1]
    if not med then return nil end
    local line = ns.L("这一级大家平均 ", "Players take ") .. med .. ns.L(" 分钟", " min for this level")
    local _, thisLvl = nil, nil
    if ns.PlayedNow then _, thisLvl = ns.PlayedNow() end
    if thisLvl then line = line .. ns.L("，你已用 ", ", you: ") .. math.floor(thisLvl / 60) .. ns.L(" 分钟", " min") end
    return line
end

local function npcFromGUID(guid)
    if not guid or ns.Secret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

local function onUnit(tt)
    if tt.__gifUnit then return end
    local unit
    if tt.GetUnit then unit = select(2, tt:GetUnit()) end
    local guid = unit and UnitGUID and UnitGUID(unit)
    local npc = npcFromGUID(guid)
    local line = ns.KillerLine(npc)
    local rare = ns.RareLines and ns.RareLines(npc)   -- 10-10 野外稀有：刷新 + 掉落
    if not line and not rare then return end
    tt.__gifUnit = true
    if line then tt:AddLine("|cffff5555" .. line .. "|r") end
    for _, l in ipairs(rare or {}) do tt:AddLine(l, 1, 1, 1, true) end
    tt:Show()
end

table.insert(ns.modules, function()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(onUnit, tt) end)
    elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(onUnit, tt) end)
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipCleared", function(self) self.__gifUnit = nil end)
    end
end)
