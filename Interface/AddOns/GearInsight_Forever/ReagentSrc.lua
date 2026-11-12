-- 11-10 共建看板 GI-218「练制皮想做个包，不知道科多兽皮具体来源在哪里…能不能加一个功能，方便看制造材料获取来源」：
--   鼠标指到配方材料（背包 / 商人 / 拍卖 / 配方库）→ 提示里加「从哪来」：采集点 / 剥皮地区 / 掉落的怪（掉率）/ 卖的商人（坐标）；
--   专业页「配方库」每条配方的鼠标提示也按材料逐个写一句。
--   数据 ReagentSrcData.lua（scripts/gi_forever_reagent_src.py，经典旧世库，《无限》可能调整 → 提示里写「经典旧世参考」）。
--   开关 ns.db.ui.matSrc（nil = 开）：设置页「界面」栏 / /gi matsrc on|off
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local M = {}
ns.ReagentSrcTip = M
M.MAX_LINES = 5

function M.Enabled() return not (ns.db and ns.db.ui and ns.db.ui.matSrc == false) end
function M.SetOn(on)
    ns.db.ui = ns.db.ui or {}
    if on then ns.db.ui.matSrc = nil else ns.db.ui.matSrc = false end
end

local function data(id)
    local R = ns.ReagentSrc
    return R and R.items and id and R.items[tonumber(id)] or nil
end
M.Data = data

local function lv(a, b)
    if not a or a == 0 then return "" end
    return (a == b or not b) and string.format(L("%d级", "Lv%d"), a) or string.format(L("%d-%d级", "Lv%d-%d"), a, b)
end
local function pct(p)
    if not p then return "" end
    return (p >= 10 and string.format("%d%%", math.floor(p + 0.5))) or string.format("%.1f%%", p)
end

-- 一种材料 → 提示行（{ "采集：银叶草（泰达希尔、丹莫罗）", … }），按「最好弄」的顺序：采集 → 剥皮 → 商人 → 掉落
function M.Lines(id, max)
    local d = data(id)
    if not d then return nil end
    max = max or M.MAX_LINES
    local out = {}
    local function push(s) if #out < max then out[#out + 1] = s end end
    for _, n in ipairs(d.n or {}) do
        push(L("采集：", "Gather: ") .. L(n[1], n[2]) .. "（" .. L(n[3], n[4]) .. "）")
    end
    if d.s then
        local zs = {}
        for _, s in ipairs(d.s) do zs[#zs + 1] = L(s[1], s[2]) .. " " .. lv(s[3], s[4]) end
        local more = (d.sn or #d.s) > #d.s and string.format(L(" 等 %d 个地区", " +%d more zones"), (d.sn or #d.s) - #d.s) or ""
        push(L("剥皮：", "Skinning: ") .. table.concat(zs, L("、", ", ")) .. more)
    end
    if d.v then
        local v = d.v[1]
        local at = (v[5] and v[5] > 0) and string.format(" (%.1f, %.1f)", v[5], v[6]) or ""
        local more = (d.vn or #d.v) > 1 and string.format(L(" 等 %d 个商人", " +%d more vendors"), (d.vn or #d.v) - 1) or ""
        push(L("商人：", "Vendor: ") .. L(v[1], v[2]) .. "（" .. L(v[3], v[4]) .. at .. "）" .. more)
    end
    -- 有采集点 / 剥皮时，掉率低的怪只是顺带（3% 的林精碎木者），不列
    local minDrop = (d.n or d.s) and 20 or 0
    for _, x in ipairs(d.d or {}) do
        if (x[7] or 0) >= minDrop then push(L("掉落：", "Drop: ") .. L(x[1], x[2]) .. " " .. lv(x[3], x[4]) .. "（" .. L(x[5], x[6]) .. "）" .. pct(x[7])) end
    end
    return out
end

-- 一句话（配方提示里每种材料一行）：最好弄的那一个来源
function M.Short(id)
    local ls = M.Lines(id, 1)
    return ls and ls[1] or nil
end

function M.AddToTooltip(tt, id)
    if not M.Enabled() or not id or tt.__gifMat == id then return false end
    local ls = M.Lines(id)
    if not ls or #ls == 0 then return false end
    tt.__gifMat = id
    tt:AddLine("|cff33ff99GI|r " .. L("从哪来（经典旧世参考）", "Where to get it (Classic reference)"), 1, 0.82, 0.4)
    for _, s in ipairs(ls) do tt:AddLine("  " .. (ns.EnSafe and ns.EnSafe(s) or s), 0.85, 0.85, 0.85, true) end
    tt:Show()
    return true
end

local function hook()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, d)
            local id = d and d.id
            if not id or (ns.Secret and ns.Secret(id)) then return end
            pcall(M.AddToTooltip, tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then
            tt:HookScript("OnTooltipCleared", function(self) self.__gifMat = nil end)
            if not (TooltipDataProcessor and Enum and Enum.TooltipDataType) and tt:HasScript("OnTooltipSetItem") then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if not link or (ns.Secret and ns.Secret(link)) then return end
                    pcall(M.AddToTooltip, self, tonumber(link:match("item:(%d+)")))
                end)
            end
        end
    end
end
table.insert(ns.modules, function() pcall(hook) end)

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.matsrc = function(rest)
    local a = tostring(rest or ""):lower()
    if a == "on" or a == "off" then M.SetOn(a == "on") end
    ns.Print(M.Enabled() and L("材料鼠标提示会写从哪来（/gi matsrc off 关掉）", "Material tooltips show sources (/gi matsrc off)")
        or L("材料来源提示已关（/gi matsrc on 打开）", "Material source tooltips off (/gi matsrc on)"))
end
