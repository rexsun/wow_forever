-- 专业冲级（10-16，docs/forever-profession-leveling-design.md）：读角色专业 + 给「专业」页和升级规划用的推导函数 + P0 探针
--   数据 ProfData.lua ← scripts/gi_forever_prof.py（小程序 prof_route.json 同一份）。
--   技能读取按顺序试：GetProfessions（新接口）→ GetSkillLineInfo（经典接口）→ 打开专业窗口时 C_TradeSkillUI 记下的缓存。
--   ⛔ 读不到就说读不到，不拿猜的技能值算颜色；⛔ 事件注册一律容错（无限客户端没有 TRADE_SKILL_UPDATE）。
--   ⛔ 在 HOLD（_hold.txt）里：没在游戏里实测完不进发行包。
local _, ns = ...

local P = {}
ns.Prof = P

-- 11-13 重构第 4 期：内核里只留登录就要用的「小核」（读角色专业 / 专业名 / 材料名 / 营地设施 / 探针 / 事件），数据用 ProfCoreData.lua 的精简表；
--   专业页、冲级路线、升级规划里的专业行、专业助手和大数据表（ProfData / ProfRecipes …）在按需加载的 GearInsight_Forever_Prof（ProfLib.lua 接着往 ns.Prof 上挂函数）
local function D() return ns.ProfCore end
local charKey = ns._CharKey   -- Leveling.lua
local function store()
    ns.db.prof = ns.db.prof or {}
    local s = ns.db.prof
    s.chars = s.chars or {}
    return s
end

-- ---------- 名字 / 编号 → 专业键 ----------
local KEY_BY_SKILL, KEY_BY_NAME = {}, {}
local ORDER = { "herbalism", "mining", "skinning", "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking",
    "tailoring", "cooking", "firstaid", "fishing" }
P.ORDER = ORDER
local function index()
    if next(KEY_BY_SKILL) or not D() then return end
    for key, p in pairs(D().profs) do
        KEY_BY_SKILL[p.skill] = key
        KEY_BY_NAME[p.zh] = key; KEY_BY_NAME[p.en] = key
    end
    KEY_BY_NAME["草药采集"] = "herbalism"; KEY_BY_NAME["Herb Gathering"] = "herbalism"
end
function P.KeyOf(nameOrId)
    index()
    return KEY_BY_SKILL[tonumber(nameOrId) or -1] or KEY_BY_NAME[nameOrId]
end
function P.Name(key)
    local p = D() and D().profs[key]
    return p and ns.L(p.zh, p.en) or key
end

-- ---------- 读技能 ----------
local function clean(v) if v == nil or ns.Secret(v) then return nil end return tonumber(v) end

local function readLive()
    index()
    local out, src = {}, nil
    if GetProfessions and GetProfessionInfo then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        if ok then
            for _, idx in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
                if idx then
                    local ok2, name, _, rank, maxR, _, _, skillLine = pcall(GetProfessionInfo, idx)
                    local key = ok2 and (KEY_BY_SKILL[clean(skillLine) or -1] or KEY_BY_NAME[name])
                    if key and clean(rank) then out[key] = { r = clean(rank), m = clean(maxR) or 0 }; src = "GetProfessions" end
                end
            end
        end
    end
    if not src and GetNumSkillLines and GetSkillLineInfo then
        local ok, n = pcall(GetNumSkillLines)
        for i = 1, (ok and tonumber(n) or 0) do
            local ok2, name, header, _, rank, _, _, maxR = pcall(GetSkillLineInfo, i)
            local key = ok2 and not header and KEY_BY_NAME[name]
            if key and clean(rank) then out[key] = { r = clean(rank), m = clean(maxR) or 0 }; src = "GetSkillLineInfo" end
        end
    end
    return out, src
end

-- 打开专业窗口时：新界面（无限客户端）C_TradeSkillUI 能读到当前这个专业的等级 → 记缓存
local function readTradeWindow()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not ok or type(info) ~= "table" then return end
    local key = P.KeyOf(info.professionID) or P.KeyOf(info.professionName)
    local r, m = clean(info.skillLevel), clean(info.maxSkillLevel)
    if key and r then
        local c = store().chars[charKey()] or {}
        c.window = c.window or {}
        c.window[key] = { r = r, m = m or 0, at = time and time() or 0 }
        store().chars[charKey()] = c
    end
end

-- 当前角色的专业：{ key = {r=技能, m=上限} }, 来源（nil = 读不到）
function P.Skills()
    local live, src = readLive()
    local c = store().chars[charKey()] or {}
    if src then
        c.skills, c.src, c.at = live, src, time and time() or 0
        store().chars[charKey()] = c
        return live, src
    end
    if c.window and next(c.window) then return c.window, "window" end
    return {}, nil
end

-- 账号里所有角色记下的专业（推算传承里程碑用）
function P.AccountSkills()
    local out = {}
    for ck, c in pairs(store().chars) do
        for key, s in pairs(c.skills or c.window or {}) do out[#out + 1] = { char = ck, key = key, r = s.r } end
    end
    return out
end

-- ---------- 小核里的其它查询 ----------
function P.ItemName(id)
    local it = D().items[id]
    return it and ns.L(it[1] ~= "" and it[1] or it[2], it[2] ~= "" and it[2] or it[1]) or tostring(id)
end

-- 营地设施：这个专业第 1 / 2 / 3 档
function P.Camp(key) return (D().camp.profs or {})[key] or {} end

-- 背包里有几个（原在 ProfPlan.lua，11-13 挪进小核：经验加成检查 XpCheck.lua 登录就用）
-- 11-18 GI-302：《无限》客户端老接口 GetItemCount 读不到 → 新接口 C_Item.GetItemCount 优先，两个取大的（含银行，和原来一样）
function P.BagCount(item)
    local best
    for _, f in ipairs({ C_Item and C_Item.GetItemCount or false, GetItemCount or false }) do   -- ⛔ 别放 nil：ipairs 遇到 nil 就停
        if f then
            local ok, n = pcall(f, item, true)
            if ok and n ~= nil and not (ns.Secret and ns.Secret(n)) then
                n = tonumber(n)
                if n and (not best or n > best) then best = n end
            end
        end
    end
    return best
end

-- 经验食物的成品物品（配方库第 7 格；ProfCoreData.lua 的精简表，不用加载整个配方库）
function ns.ProfFoodItem(spell)
    local C = ns.ProfCore
    return C and C.foodItem and C.foodItem[spell] or nil
end

-- ---------- P0 探针：/gi profprobe ----------
-- 记下：哪些读专业的接口能用、读到了什么、训练师窗口里每一项的技能 / 等级需求（补《无限》新配方的学习技能）
local probe
local function probeDB()
    store().probe = store().probe or { trainers = {} }
    return store().probe
end
local function apiReport()
    local rep = {}
    local function has(name, f) rep[#rep + 1] = name .. "=" .. (f and "y" or "n") end
    has("GetProfessions", GetProfessions); has("GetProfessionInfo", GetProfessionInfo)
    has("GetSkillLineInfo", GetSkillLineInfo); has("GetNumSkillLines", GetNumSkillLines)
    has("C_TradeSkillUI.GetBaseProfessionInfo", C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo)
    has("GetTrainerServiceSkillReq", GetTrainerServiceSkillReq); has("GetTrainerServiceLevelReq", GetTrainerServiceLevelReq)
    local live, src = readLive()
    local sk = {}
    for k, s in pairs(live) do sk[#sk + 1] = k .. ":" .. s.r .. "/" .. s.m end
    table.sort(sk)
    rep[#rep + 1] = "src=" .. tostring(src)
    rep[#rep + 1] = "skills=" .. table.concat(sk, ",")
    rep[#rep + 1] = "lv=" .. tostring(UnitLevel and UnitLevel("player"))
    rep[#rep + 1] = "build=" .. tostring(GetBuildInfo and select(2, GetBuildInfo()))
    return rep
end

local function scanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    local ok, n = pcall(GetNumTrainerServices)
    n = ok and tonumber(n) or 0
    if n == 0 then return end
    local npc = (UnitName and UnitName("npc")) or "?"
    local list = {}
    for i = 1, n do
        local _, name, sub = pcall(GetTrainerServiceInfo, i)
        local sname, srank = nil, nil
        if GetTrainerServiceSkillReq then local _, a, b = pcall(GetTrainerServiceSkillReq, i); sname, srank = a, b end
        local lv = GetTrainerServiceLevelReq and select(2, pcall(GetTrainerServiceLevelReq, i))
        local cost = GetTrainerServiceCost and select(2, pcall(GetTrainerServiceCost, i))
        list[#list + 1] = table.concat({ tostring(name), tostring(sub or ""), tostring(sname or ""), tostring(srank or ""),
            tostring(lv or ""), tostring(cost or "") }, "|")
    end
    probeDB().trainers[npc] = list
    if probe then ns.Print(string.format(ns.L("探针：记下训练师 %s 的 %d 项", "Probe: recorded %d services from %s"), npc, #list)) end
end

function P.ProbeToggle()
    probe = not probe
    local db = probeDB()
    db.api = apiReport()
    if probe then
        ns.Print(ns.L("专业探针已开：去找专业训练师打开训练窗口、打开一次专业窗口，然后再输 /gi profprobe 看结果",
            "Profession probe on: open a profession trainer and your profession window, then /gi profprobe again"))
        return
    end
    local out = { "GIPROF1" }
    for _, l in ipairs(db.api) do out[#out + 1] = l end
    for npc, list in pairs(db.trainers or {}) do out[#out + 1] = "T:" .. npc .. "=" .. #list end
    local text = table.concat(out, ";")
    if ns.ShowBox then
        ns.ShowBox(ns.L("专业探针结果", "Profession probe"), ns.L("Ctrl+C 复制整行发给开发者（训练师明细存在 GearInsightForeverDB.prof.probe）",
            "Ctrl+C to copy (trainer details are saved in GearInsightForeverDB.prof.probe)"), text)
    else
        ns.Print(text)
    end
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.prof = function(rest)
    if rest == "probe" then P.ProbeToggle() else ns.ToggleMain("prof") end
end
ns.ExtraSlash["专业"] = ns.ExtraSlash.prof
ns.ExtraSlash.profprobe = function() P.ProbeToggle() end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
    local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
    if valid then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, e)
    if not ns.db or not D() then return end
    if e == "TRAINER_SHOW" or e == "TRAINER_UPDATE" then scanTrainer(); return end
    if e:find("^TRADE_SKILL") then readTradeWindow() end
    P.Skills()
    if ns.ProfPage and ns.ProfPage.IsShown and ns.ProfPage:IsShown() and ns.RefreshProfPage then ns.RefreshProfPage() end
end)

-- ---------- 11-14 用户截图「学了剥皮的这里提醒多少技能可以剥，前面加 GI: 前缀」----------
--   鼠标指到「可剥皮」的怪 / 尸体：学了剥皮的角色在提示里多一行「GI: 剥皮需要 N 技能（你现在 M）」，够了绿字、不够红字。
--   技能要求按经典公式：怪 ≤10 级 = 1；11~20 级 = (等级-10)×10；20 级以上 = 等级×5（首领「??」级读不到等级 → 11-23 起整行不写）
--   「可剥皮」这一行用客户端全局串 UNIT_SKINNABLE_LEATHER 认（繁体 / 英文客户端自动对上）；没学剥皮 / 不是可剥皮的怪不加
function P.SkinReq(level)
    level = tonumber(level)
    if not level or level < 1 then return nil end
    if level <= 10 then return 1 elseif level <= 20 then return (level - 10) * 10 end
    return level * 5
end
local skinCache, skinAt = nil, -1e9
local function mySkinning()
    local t = GetTime and GetTime() or 0
    if t - skinAt > 5 then
        local ok, s = pcall(P.Skills)
        skinCache, skinAt = ok and type(s) == "table" and s.skinning or nil, t
    end
    return skinCache
end
P._skinReset = function() skinAt = -1e9 end   -- 离线测试用
-- 11-23 玩家「这行信息怎么关掉」：设置 → 专业 →「材料来源提示」里可关（ns.db.ui.skinTip = false；nil = 开）
--   P.SkinTipOn() = 开着没；P.SkinTipOn(true / false) = 设（设置页 get / set 共用这一个，省内核内存）
function P.SkinTipOn(v)
    -- ⛔ 11-23 玩家截图「这个勾选没作用，取消不了」：原来写 (not v) and false or nil，恒为 nil → 关不掉
    if v ~= nil then ns.db.ui = ns.db.ui or {}; if v then ns.db.ui.skinTip = nil else ns.db.ui.skinTip = false end end
    return not (ns.db and ns.db.ui and ns.db.ui.skinTip == false)
end
function P.SkinTip(tt)
    if not tt or tt.__gifSkin or not tt.GetUnit or not P.SkinTipOn() then return false end
    local _, unit = tt:GetUnit()
    if not unit or ns.Secret(unit) or (UnitIsPlayer and UnitIsPlayer(unit)) then return false end
    local sk = mySkinning()
    if not sk then return false end
    local want = (type(UNIT_SKINNABLE_LEATHER) == "string" and UNIT_SKINNABLE_LEATHER ~= "") and UNIT_SKINNABLE_LEATHER or ns.L("可剥皮", "Skinnable")
    local name, found = tt.GetName and tt:GetName(), false
    for i = 2, (tt.NumLines and tt:NumLines() or 0) do
        local fs = name and _G[name .. "TextLeft" .. i]
        local s = fs and fs:GetText()
        if type(s) == "string" and not ns.Secret(s) and s:find(want, 1, true) then found = true; break end
    end
    if not found then return false end
    local lv = UnitLevel and UnitLevel(unit)
    if ns.Secret(lv) then lv = nil end
    local req, r = P.SkinReq(lv), tonumber(sk.r)
    if not req then return false end   -- 11-23 ?? 级（首领）读不到等级：不写（原来写「读不到」，给设置开关腾内核内存）
    local line = string.format(ns.L("GI: 剥皮需要 %d 技能", "GI: Skinning %d required"), req)
        .. (r and string.format(ns.L("（你现在 %d）", " (you: %d)"), r) or "")
    if not r then tt:AddLine(line, 1, 0.82, 0)
    elseif r >= req then tt:AddLine(line, 0.25, 1, 0.4)
    else tt:AddLine(line, 1, 0.35, 0.3) end
    tt.__gifSkin = true
    if tt.Show then tt:Show() end
    return true, line
end
table.insert(ns.modules, function()
    local tt = GameTooltip
    if not tt then return end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(t) if t == GameTooltip then pcall(P.SkinTip, t) end end)
    elseif tt.HasScript and tt:HasScript("OnTooltipSetUnit") then
        tt:HookScript("OnTooltipSetUnit", function(self) pcall(P.SkinTip, self) end)
    end
    if tt.HookScript then tt:HookScript("OnTooltipCleared", function(self) self.__gifSkin = nil end) end
end)
