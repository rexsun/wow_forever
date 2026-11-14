-- 宏库页（10-07 用户：主界面一个标签页，里面是各职业；点职业弹框列出它的技能宏；点「导入」建宏并放到鼠标上，拖到动作条）
-- 数据：MacroData.lua（scripts/gi_forever_macros.py 生成；《无限》宏，技能名用 {{法术ID}}，导入时按客户端语言填名字）
-- ⛔ 只调 CreateMacro / EditMacro / PickupMacro（非受保护，战斗中不做）；不碰暴雪动作条 / 宏界面的任何东西
local _, ns = ...; ns = _G.GearInsightForever or ns

local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local CLASS_COLOR = { Warrior = "c79c6e", Paladin = "f58cba", Hunter = "abd473", Rogue = "fff569", Priest = "ffffff",
    Shaman = "0070de", Mage = "69ccf0", Warlock = "9482c9", Druid = "ff7d0a" }
local CLASS_ICON = { Warrior = "inv_sword_27", Paladin = "spell_holy_holybolt", Hunter = "inv_weapon_bow_07",
    Rogue = "inv_throwingknife_04", Priest = "inv_staff_30", Shaman = "spell_nature_bloodlust",
    Mage = "inv_staff_13", Warlock = "spell_nature_drowsy", Druid = "ability_druid_maul" }

-- 通用系统宏（10-10 用户转抖音「无限服实用的宏命令」：「这个是不是可以在宏库增加系统宏中？」）
-- 不分职业、谁都能导；只改画面 / 视角设置（/console 改的是客户端设置，账号共用，下次登录还在）。
-- 6 个设置名都在《无限》客户端 Wow.exe 里核对过存在（volumeFog / volumeFogLevel / ffxDeath / ffxGlow / giQuality / cameraDistanceMaxZoomFactor）。
local SYS_KEY = "System"
local SYS_MACROS = {
    { key = "sys-clear-view", no = 1, g = "画面与视角", gEn = "Graphics and camera", icon = "INV_Misc_Spyglass_02",
      t = "Clear view: no haze, no grey death screen, no glow, far camera", tc = "清爽画面一键",
      n = "Removes the distance haze, keeps the screen in colour when you die, turns off the full-screen glow and lets the camera zoom out much further. Settings stay after relog.",
      nc = "去掉远景灰雾、死后画面不变灰、关掉全屏泛光、视角能拉得更远；改的是游戏设置，下次登录还在",
      b = "/console volumeFog 0\n/console volumeFogLevel 1\n/console ffxDeath 0\n/console ffxGlow 0\n/console giQuality 0\n/console cameraDistanceMaxZoomFactor 2.6" },
    { key = "sys-far-camera", no = 2, g = "画面与视角", gEn = "Graphics and camera", icon = "Ability_EyeOfTheOwl",
      t = "Far camera only", tc = "只拉远视角",
      n = "Only raises the maximum camera distance. Scroll out after pressing it.",
      nc = "只把最远视角调大，画面别的都不动；按完滚轮往外拉",
      b = "/console cameraDistanceMaxZoomFactor 2.6" },
    { key = "sys-restore-view", no = 3, g = "画面与视角", gEn = "Graphics and camera", icon = "INV_Misc_Gear_01",
      t = "Restore those settings to game defaults", tc = "恢复默认画面",
      n = "Puts the six settings above back to the game's defaults (not to what you had before).",
      nc = "把上面改过的 6 项设置恢复成游戏默认值（不是你改之前的值）",
      b = "/run local D=C_CVar and C_CVar.GetCVarDefault or GetCVarDefault for _,v in ipairs({\"volumeFog\",\"volumeFogLevel\",\"ffxDeath\",\"ffxGlow\",\"giQuality\",\"cameraDistanceMaxZoomFactor\"}) do SetCVar(v,D(v)) end" },
    { key = "sys-fps", no = 4, g = "画面与视角", gEn = "Graphics and camera", icon = "Spell_Nature_Cyclone",
      t = "Lighter graphics: no weather, shadows or ground clutter", tc = "低配提帧",
      n = "Turns off weather, shadows, ambient occlusion and ground clutter for more frames in busy areas.",
      nc = "关天气、关阴影、关环境光遮蔽、关地面植被，人多的地方更不卡；画面会变素",
      b = "/console weatherDensity 0\n/console shadowMode 0\n/console SSAO 0\n/console groundEffectDensity 0" },
    { key = "sys-no-shake", no = 5, g = "画面与视角", gEn = "Graphics and camera", icon = "Spell_Nature_EarthQuake",
      t = "No screen shake", tc = "关屏幕震动",
      n = "Stops the camera and screen from shaking.",
      nc = "关掉镜头和画面震动，跑图打本更稳",
      b = "/console ShakeStrengthCamera 0\n/console ShakeStrengthUI 0" },
    -- 10-18 用户转抖音「喵先生·练级宏命令」+「法师闪现撞墙·控制台设置指南」：重复的跳过、能用的加进来。
    -- 设置名逐个在《无限》客户端 Wow.exe 里核过；攻略里的 ShowClassColorInNameplate / targetNearestDistanceRadius
    -- 客户端里根本没有（写错了），不收。WorldTextScale 和 _v2 两个名字客户端都有、攻略两家说法相反 → 两个一起写。
    { key = "sys-loot", no = 6, g = "练级便利", gEn = "Leveling comfort", icon = "INV_Misc_Bag_10",
      t = "Auto loot with no delay", tc = "自动拾取 + 零延迟",
      n = "Turns on auto loot and removes the loot window delay. Hold Shift while looting to pick items one by one.",
      nc = "打开自动拾取、去掉拾取等待；想逐件捡就按住 Shift 再右键",
      b = "/console autoLootDefault 1\n/console autoLootRate 0" },
    { key = "sys-enemy-plates", no = 7, g = "练级便利", gEn = "Leveling comfort", icon = "Ability_Hunter_SniperShot",
      t = "Enemy nameplates, seen from further", tc = "敌人血条 + 看得更远",
      n = "Shows health bars over every enemy and raises the nameplate distance to 41 yards.",
      nc = "所有敌人头顶挂血条，血条显示距离拉到 41 码，混战一眼看清谁残血",
      b = "/console nameplateShowEnemies 1\n/console nameplateMaxDistance 41" },
    { key = "sys-compare", no = 8, g = "练级便利", gEn = "Leveling comfort", icon = "INV_Chest_Chain_05",
      t = "Always compare items", tc = "装备自动对比",
      n = "Hovering an item compares it with what you wear without holding Shift.",
      nc = "鼠标悬停就和身上装备对比，不用按 Shift",
      b = "/console alwaysCompareItems 1" },
    { key = "sys-big-numbers", no = 9, g = "练级便利", gEn = "Leveling comfort", icon = "Spell_Fire_Fireball02",
      t = "Bigger damage numbers", tc = "伤害数字调大",
      n = "Doubles the size of floating damage numbers (1 is the default).",
      nc = "伤害数字放大一倍（1 是默认，1-3 可调）",
      b = "/console WorldTextScale 2\n/console WorldTextScale_v2 2" },
    { key = "sys-red-errors", no = 10, g = "练级便利", gEn = "Leveling comfort", icon = "INV_Misc_Note_01",
      t = "Hide or show the red error text", tc = "隐藏 / 恢复错误红字",
      n = "Press to hide the red \"Not enough rage\" style messages, press again to bring them back. Resets on relog.",
      nc = "按一下隐藏屏幕中间的红字报错（怒气不足之类），再按一下恢复；重新登录会恢复显示",
      b = "/run if UIErrorsFrame:IsShown() then UIErrorsFrame:Hide() else UIErrorsFrame:Show() end" },
    { key = "sys-key-down", no = 11, g = "练级便利", gEn = "Leveling comfort", icon = "Spell_Nature_Lightning",
      t = "Cast on key press", tc = "按下即施法",
      n = "Spells go off when you press the key instead of when you release it.",
      nc = "技能在按下按键时就放出，不用等松手",
      b = "/console ActionButtonUseKeyDown 1" },
}
for _, m in ipairs(SYS_MACROS) do m.lv = 0; m.spells = {}; m.acct = true end
ns.SysMacros = SYS_MACROS
-- GI 快捷宏（10-18）：宏库页「GI 快捷宏」按钮导入；正文在导入时取 ns.SlashHint（/gi 被占时是 /gif）
ns.GIOpenMacro = setmetatable({ key = "gi-open", no = 99, icon = "INV_Misc_Map_01", t = "Open", tc = "打开面板", lv = 0, spells = {}, acct = true },
    { __index = function(_, k) if k == "b" then return ns.SlashHint or "/gif" end end })

-- 宏列表图标：技能宏用第一个技能的图标，系统宏用自带图标名
local function macroIconTex(m, spellIconFn)
    if m.spells[1] then return spellIconFn(m.spells[1]) end
    if m.icon then return "Interface\\Icons\\" .. m.icon end
end

local function myClass()
    local _, token = UnitClass("player")
    token = token or "Warrior"
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- 法术 ID → 客户端语言的名字（拿不到就用数据里的中 / 英文名兜底）
local function spellName(id)
    local n
    if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
    if (not n or n == "") and GetSpellInfo then n = GetSpellInfo(id) end
    if n and n ~= "" then return n end
    local f = ns.MacroSpellNames and ns.MacroSpellNames[id]
    if f then return (ns.zh and f[1] ~= "" and f[1]) or (f[2] ~= "" and f[2]) or f[1] end
    return "?"
end

local function spellIcon(id)
    local t
    if C_Spell and C_Spell.GetSpellTexture then t = C_Spell.GetSpellTexture(id) end
    if not t and GetSpellTexture then t = GetSpellTexture(id) end
    return t
end
ns.SpellIcon = spellIcon   -- 升级规划页的宏行也要用同一个取法

function ns.MacroBody(m)
    local body = (ns.zh and m.bc) or m.b
    body = body:gsub("{{(%d+)}}", function(id) return spellName(tonumber(id)) end)
    -- 指定等级「技能(Rank 2)」：中文客户端写「(等级 2)」，用客户端自己的 RANK 全局串
    local rank = _G.RANK
    if rank and rank ~= "" and rank ~= "Rank" then
        body = body:gsub("%(Rank (%d+)%)", function(n) return "(" .. rank .. " " .. n .. ")" end)
    end
    return body
end

-- 宏名 ≤ 16 字节（UTF-8 中文 3 字节一个）：「GI」+ 标题截断到字符边界
-- 10-07 用户截图（动作条三个宏挤成「GI10...」看不出区别）：「宏开头两个字最好是高度标识，GI放在后面可以」——
-- 原来「GI + 两位序号」固定吃掉前 4 字节，中文标题从第 5 字节才开始，16 字节预算下动作条上基本只剩「GI10」能看见。
-- 改成标题在前、「GI」缩成 2 字节尾标；真撞名了才在尾标里加数字进一步区分（多数宏不需要，省下的字节都给标题）。
local function macroName(m)
    local base = ns.L(m.tc, m.t)
    -- ⛔ 别把中文标点放进 [] 字符类：Lua 模式按字节匹配，会把别的汉字的字节也删掉
    for _, s in ipairs({ " ", "(", ")", "/", ":", "+", "（", "）", "、", "：", "·", "→" }) do
        base = base:gsub(s:gsub("%p", "%%%0"), "")
    end
    local taken = {}
    for k, v in pairs(ns.db.macroNames or {}) do if k ~= m.key then taken[v] = true end end
    local num = m.no or tonumber((m.key or ""):match("#(%d+)$")) or 0
    local attempt, out = 0, nil
    repeat
        local tag = attempt == 0 and "GI" or ("GI" .. tostring(num))
        local budget = 16 - #tag
        local title, bytes = "", 0
        for ch in base:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            if bytes + #ch > budget then break end
            title = title .. ch
            bytes = bytes + #ch
        end
        out = title .. tag
        num = num + 100
        attempt = attempt + 1
    until not taken[out]
    return out
end

-- 一键清空所有导入过的 GI 宏（10-07 用户要求）：按 ns.db.macroNames 记的真实宏名删，
-- ⛔别按「GI」前缀模糊匹配——玩家自己手打的宏万一也叫 GI 开头，模糊匹配会把它也删了
function ns.ClearAllMacros()
    if InCombatLockdown and InCombatLockdown() then
        return false, ns.L("战斗中不能删宏，脱战后再点", "Can't delete macros in combat")
    end
    if not DeleteMacro then return false, "DeleteMacro?" end
    local names = ns.db.macroNames or {}
    local n = 0
    for _, name in pairs(names) do
        local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
        if idx and idx > 0 then
            DeleteMacro(idx)
            n = n + 1
        end
    end
    ns.db.macroNames = {}
    return true, n
end

-- 建 / 更新宏 → 放到鼠标上；返回 true / false, 原因
function ns.ImportMacro(m)
    if InCombatLockdown and InCombatLockdown() then
        return false, ns.L("战斗中不能建宏，脱战后再点", "Can't create macros in combat")
    end
    if not CreateMacro then return false, "CreateMacro?" end
    ns.db.macroNames = ns.db.macroNames or {}
    local name = ns.db.macroNames[m.key] or macroName(m)
    local body = ns.MacroBody(m)
    -- 10-07 用户截图：动作条上三个宏全是「?」——原来 CreateMacro/EditMacro 的图标参数写死了问号，
    -- 没有用这条宏真正的技能图标（弹框列表里那个图标是对的，建宏时没传同一个值）
    local icon = (m.spells[1] and spellIcon(m.spells[1])) or m.icon or "INV_Misc_QuestionMark"
    local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
    if idx and idx > 0 then
        EditMacro(idx, name, icon, body)
    else
        local nGlobal, nChar = GetNumMacros()
        local maxG, maxC = MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
        local perChar = (nChar or 0) < maxC
        -- 系统宏不分职业：优先建在「通用宏」里，所有角色都能用；通用宏满了再退回角色专用
        if m.acct and (nGlobal or 0) < maxG then perChar = false end
        if not perChar and (nGlobal or 0) >= maxG then
            return false, ns.L("宏位满了（角色和通用都满），先删几个", "Macro slots are full")
        end
        idx = CreateMacro(name, icon, body, perChar)
    end
    if not idx or idx == 0 then return false, ns.L("建宏失败", "Failed to create the macro") end
    ns.db.macroNames[m.key] = name
    if PickupMacro then PickupMacro(idx) end
    return true, name
end

-- ---------- 宏现在的状态：以「在不在动作条上」为准（10-07 用户截图「宏显示不显示是不是应该以是否在动作条判断？」）----------
-- 以前只看「点过导入」（ns.db.macroNames 记了名字）：导入只是建宏 + 拿到鼠标上，没放下 / 后来拖掉了都算「做完了」；
-- 而且 macroNames 是账号共用的存档，小号会把大号导入过的当成自己的。
--   "none"    游戏里没有这个宏（没导入，或删了）
--   "created" 宏建好了，但哪个动作条格子上都没有
--   "onbar"   在动作条上（返回第几格）
function ns.MacrosOnBars()
    local on = {}
    if not GetActionInfo then return on end
    for slot = 1, 180 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "macro" and id then on[id] = on[id] or slot end
    end
    return on
end
function ns.MacroState(m, onBars)
    local name = (ns.db.macroNames and ns.db.macroNames[m.key]) or macroName(m)
    local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
    if not idx or idx == 0 then return "none" end
    onBars = onBars or ns.MacrosOnBars()
    if onBars[idx] then return "onbar", onBars[idx], idx end
    return "created", nil, idx
end

-- ---------- 弹框：某职业的宏 ----------
local pop
local function buildPop(parent)
    local f = CreateFrame("Frame", "GearInsightForeverMacroPop", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -64)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel(parent:GetFrameLevel() + 20)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("LEFT", f.title, "RIGHT", 12, -1)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -34, 0); f.hint:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)   -- 10-18 战斗中关不掉：原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    local sf, c = ns.Scroll(f, 10, -40, 600, 330)
    f.child, f.rows = c, {}
    f:Hide()
    return f
end

local function rowTooltip(row)
    local m = row.m
    if not m then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.L(m.tc, m.t), 1, 0.82, 0)
    GameTooltip:AddLine(ns.EnSafe(ns.L(m.nc, m.n)), 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    for ln in (ns.MacroBody(m) .. "\n"):gmatch("(.-)\n") do GameTooltip:AddLine(ln, 0.6, 0.9, 1) end
    if m.lv and m.lv > 1 then GameTooltip:AddLine(ns.L("需要 ", "Requires level ") .. m.lv .. ns.L(" 级学会相关技能", ""), 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

local function showClass(page, cls)
    pop = pop or buildPop(page)
    local sys = (cls == SYS_KEY)
    local list = sys and SYS_MACROS or (ns.Macros and ns.Macros[cls]) or {}
    local mine = sys or (cls == myClass())
    if sys then
        pop.title:SetText("|cffffd100" .. ns.L("通用 · 系统宏", "General · system macros") .. "|r  |cff888888" .. #list .. "|r")
    else
        pop.title:SetText("|cff" .. CLASS_COLOR[cls] .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r " .. ns.L("宏", "macros") .. "  |cff888888" .. #list .. "|r")
    end
    pop.hint:SetText(sys and ns.L("所有职业都能用；点「导入」放到鼠标上，拖到动作条点一下就生效", "Any class; import, place on a bar and click it once")
        or mine and ns.L("点「导入」：建好宏并放到鼠标上，点一下动作条格子放下", "Import: creates the macro and puts it on your cursor; click an action bar slot")
        or ns.L("不是你当前角色的职业：只能看，导入请登录该职业角色", "Not your class: view only"))
    for _, r in ipairs(pop.rows) do r:Hide() end
    pop.heads = pop.heads or {}
    for _, h in ipairs(pop.heads) do h:Hide() end
    local y, lastG, nh = -2, nil, 0
    for i, m in ipairs(list) do
        -- 分组小标题（foreverdb 的分组；classicwowforever 补的进「更多」）
        local g = ns.L(m.g, m.gEn)
        if g and g ~= "" and g ~= lastG then
            lastG, nh = g, nh + 1
            local h = pop.heads[nh]
            if not h then
                h = pop.child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                h:SetJustifyH("LEFT")
                pop.heads[nh] = h
            end
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", 4, y - (nh > 1 and 6 or 0))
            h:SetText("|cffffd100" .. g .. "|r")
            h:Show()
            y = y - (nh > 1 and 24 or 18)
        end
        local r = pop.rows[i]
        if not r then
            r = CreateFrame("Button", nil, pop.child)
            r:SetHeight(44)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(34, 34); r.icon:SetPoint("LEFT", 4, 0)
            r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.t:SetPoint("TOPLEFT", 46, -5); r.t:SetPoint("RIGHT", -90, 0); r.t:SetJustifyH("LEFT")
            r.n = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.n:SetPoint("TOPLEFT", 46, -24); r.n:SetPoint("RIGHT", -90, 0); r.n:SetJustifyH("LEFT"); r.n:SetWordWrap(false)
            r.n:SetTextColor(0.75, 0.75, 0.75)
            r.btn = ns.Button(r, ns.L("导入", "Import"), 72, 24)
            r.btn:SetPoint("RIGHT", -6, 0)
            r:SetScript("OnEnter", rowTooltip)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            pop.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", -4, 0)
        r.m = m
        r.icon:SetTexture(macroIconTex(m, spellIcon) or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.t:SetText(ns.L(m.tc, m.t) .. (m.fv and ns.L("  |cff33ff99《无限》新|r", "  |cff33ff99Forever|r") or ""))
        r.n:SetText(ns.EnSafe(ns.L(m.nc, m.n)))
        r.btn:SetEnabled(mine)
        r.btn:SetScript("OnClick", function()
            local ok, msg = ns.ImportMacro(m)
            if ok then
                ns.Print(ns.L("宏「", "Macro \"") .. msg .. ns.L("」已在鼠标上：点一下动作条格子放下（宏界面 / 角色专用宏里也能找到）",
                    "\" is on your cursor: click an action bar slot to place it"))
                if ns.RefreshMacroPage then ns.RefreshMacroPage() end   -- 一键清空按钮的条数跟着实时更新
            else
                ns.Print(msg)
            end
        end)
        r:Show()
        y = y - 46
    end
    pop.child:SetHeight(-y + 4)
    pop:Show()
end
ns.ShowMacroClass = function(cls) if ns.MacroPage then showClass(ns.MacroPage, cls) end end

local function build(p)
    ns.MacroPage = p
    local n = 0
    for _, l in pairs(ns.Macros or {}) do n = n + #l end
    -- 11-10 用户「宏只给当前职业的」（随职业百宝箱合并）：九个职业格子只留自己这一格，和通用 / GI 快捷宏排一行
    local mineN = #((ns.Macros and ns.Macros[myClass()]) or {})
    ns.PageHeader(p, ns.L("宏库", "Macros"), ns.L("你的职业常用宏 " .. mineN .. " 条，点开导入", "Macros for your class: " .. mineN))
    for _, cls in ipairs(CLASSES) do if cls == myClass() then
        local b = CreateFrame("Button", nil, p)
        b:SetSize(200, 46)
        b:SetPoint("TOPLEFT", 12, -48)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("LEFT", 5, 0)
        ic:SetTexture("Interface\\Icons\\" .. CLASS_ICON[cls]); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("LEFT", 50, 6)
        fs:SetText("|cff" .. CLASS_COLOR[cls] .. ns.L(ns.Data.classCn[cls] or cls, cls) .. "|r")
        local cnt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); cnt:SetPoint("LEFT", 50, -11)
        cnt:SetText(#((ns.Macros and ns.Macros[cls]) or {}) .. ns.L(" 条宏", " macros") .. (cls == myClass() and ns.L("  · 你的职业", "  · your class") or ""))
        if cls == myClass() then
            ns.MarkMine(b)
            local glow = b:CreateTexture(nil, "BACKGROUND", nil, 1); glow:SetAllPoints(); glow:SetColorTexture(1, 0.82, 0, 0.1)
        end
        b:SetScript("OnClick", function() showClass(p, cls) end)
    end end
    do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(200, 46)
        b:SetPoint("TOPLEFT", 12 + 206, -48)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 0.82, 0, 0.06)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("LEFT", 5, 0)
        ic:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("LEFT", 50, 6)
        fs:SetText("|cffffd100" .. ns.L("通用 · 系统宏", "General") .. "|r")
        local cnt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); cnt:SetPoint("LEFT", 50, -11)
        cnt:SetText(#SYS_MACROS .. ns.L(" 条宏  · 所有职业", " macros  · any class"))
        b:SetScript("OnClick", function() showClass(p, SYS_KEY) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L("通用 · 系统宏", "General · system macros"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("画面 / 视角设置宏：去远景灰雾、死后不灰屏、关泛光、视角拉远，以及一键恢复默认", "Graphics / camera: no haze, no grey death screen, no glow, far camera, and restore defaults"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.sysTile = b
    end
    -- 一键清空所有已导入的 GI 宏（10-07 用户要求）；数量跟着 refresh() 走，⛔别指望 OnShow 自动触发——
    -- 子框架随父框架一起显示时不一定会补发自己的 OnShow，数量在别的职业弹框里导完宏后会跟着过期
    p.clearAll = ns.Button(p, "", 170, 24, function()
        local ok, result = ns.ClearAllMacros()
        if not ok then ns.Print(result); return end
        ns.Print(result > 0 and (ns.L("已清空 ", "Cleared ") .. result .. ns.L(" 条 GI 宏", " GI macros"))
            or ns.L("没有已导入的 GI 宏", "No GI macros to clear"))
        ns.RefreshMacroPage()
    end)
    -- ⛔ 11-10 起第 1 排：你的职业 · 通用系统宏 · GI 快捷宏（y=-48..-94）；清空按钮在第 2 排 y=-104
    p.clearAll:SetPoint("TOPLEFT", 12, -104)
    p.clearAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.L("删掉这台角色所有已导入的 GI 宏（动作条格子要自己清）", "Deletes every GI macro you've imported on this character (you still need to clear the action bar slots yourself)"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.clearAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 10-18 用户截图「这里加上GI快捷宏」「效果就是/gi」：一个宏 = 打开 / 关闭 GI 主面板，点了建好放到鼠标上，拖到动作条
    --   /gi 被别的插件占了时 Core 只注册 /gif → 宏正文跟着 ns.SlashHint 走。建在通用宏（所有角色共用），一键清空也会删它
    --   10-18 用户截图「加个图标，跟通用那个并列」：和「通用 · 系统宏」同款卡片，放第 4 排第 2 格
    do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(200, 46)
        b:SetPoint("TOPLEFT", 12 + 412, -48)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.2, 1, 0.6, 0.06)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetPoint("LEFT", 5, 0)
        ic:SetTexture("Interface\\AddOns\\GearInsight_Forever\\media\\logo")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("LEFT", 50, 6)
        fs:SetText("|cff33ff99" .. ns.L("GI 快捷宏", "GI macro") .. "|r")
        local cnt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); cnt:SetPoint("LEFT", 50, -11)
        cnt:SetText(ns.L("点一下拿到鼠标上  · ", "Click to pick up  - ") .. (ns.SlashHint or "/gif"))
        b:SetScript("OnClick", function()
            local ok, result = ns.ImportMacro(ns.GIOpenMacro)
            if not ok then ns.Print(result); return end
            ns.Print(ns.L("宏「", "Macro \"") .. result .. ns.L("」已拿到鼠标上：放到动作条任意格子，点一下 = ", "\" is on your cursor: drop it on an action bar; clicking it = ")
                .. (ns.SlashHint or "/gif"))
            ns.RefreshMacroPage()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L("GI 快捷宏", "GI macro"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("建一个宏，效果 = 输入 ", "Creates a macro that does the same as typing ") .. (ns.SlashHint or "/gif")
                .. ns.L("：打开 / 关闭 GI 主面板。点了宏会拿到鼠标上，放到动作条上就能一键打开。", ": opens / closes the GI window. It lands on your cursor - drop it on an action bar."), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.giMacro = b
    end
    local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 14, -140); note:SetWidth(600); note:SetJustifyH("LEFT"); note:SetSpacing(3)
    note:SetText(ns.EnSafe(ns.L(
        "· 技能名按你的客户端语言自动填（中文客户端就是中文技能名）\n· 导入的宏建在「角色专用宏」里，名字以 GI 开头；再导入同一条会覆盖更新，不会重复\n· 鼠标指向 = 对鼠标下的单位施放，不用切目标；Shift / Ctrl / Alt 切换的写在每条说明里\n· 宏来自《无限》宏站（classicwowforever.com），Beta 期间技能可能还会改",
        "- Spell names fill in for your client language\n- Imported macros go to character macros, named GI...; importing again updates instead of duplicating\n- Mouseover = cast on the unit under your cursor; modifiers are in each description\n- Source: classicwowforever.com; spells may still change during the Beta")))
end

local macroPage
local function refresh(p)
    macroPage = p
    if not p.clearAll then return end
    local n = 0
    for _ in pairs(ns.db.macroNames or {}) do n = n + 1 end
    p.clearAll:SetText(ns.L("一键清空全部 GI 宏", "Clear all GI macros") .. (n > 0 and ("（" .. n .. "）") or ""))
    p.clearAll:SetEnabled(n > 0)
end
ns.RefreshMacroPage = function() if macroPage then refresh(macroPage) end end

ns.RegisterPage({ key = "macro", order = 1.5, title = ns.L("宏库", "Macros"), build = build, refresh = refresh })
