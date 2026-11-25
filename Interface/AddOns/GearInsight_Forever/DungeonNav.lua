-- 副本导航（11-15 用户「做黑暗深渊的导航样品」→「所有的副本都要安排」：数据在 DungeonNavData.lua，本文件只留引擎）
--   进副本自动弹一个可拖动、可折叠的小面板「副本导航 · XX」，出本收起：
--     首领 / 机制点按推荐路线列成步骤（已击杀打勾、当前高亮、「第 N / M 步」）+ 当前步：怎么走过去 / 注意 / 任务 / 掉落亮点
--   ⛔ 《无限》副本里拿不到坐标 / 朝向 / 地图编号，UnitGUID 是 secret、没有 UNIT_DIED（GIDungeonProbe 实测，
--      记忆 dev-notes/forever-instance-no-position-secret-guid-1115.md）→ 能用的只有：
--      GetInstanceInfo（第 8 个返回 = instanceID，黑暗深渊 48）· GetSubZoneText（很稀疏，多数是空串）·
--      ENCOUNTER_START / ENCOUNTER_END（首领名 + encounterID，ok = 1 击杀）。所有读到的值先过 issecretvalue 再用
--   推进：ENCOUNTER_END 击杀（按 encounterID 或首领名）自动勾掉并跳到它后面第一个没完成的步；越过的机制点（火盆）一并算完成；
--         没击杀的可选首领（稀有 / 召唤）留空不勾；「上一步 / 下一步」手动纠正（下一步 = 把这一步记成「已过」）
--   多翼副本（血色修道院 / 厄运之槌 / 斯坦索姆 / 黑石塔共用一个 instanceID）：子区域名认翼 → 存档里这一趟的翼 → 第一翼；
--         打到别的翼的首领自动切过去；面板上「换一翼」手动切
--   存档 ns.db.dnav.run：同一个副本、开打 2 小时内（重载 / 掉线 / 跑尸）进度不丢；超过 2 小时、最后一个首领打完后出本、
--         系统提示副本已重置、或点「重新开始」→ 下次进本从头开始
--   11-15「永不展示」：面板上「以后不弹」= 关掉「进副本时显示副本导航」（存档 false）+ 收起 + 聊天框说怎么找回；/gi 导航 照样能手动打开
--   没有数据文件（DungeonNavData.lua 在 HOLD 里没进包）→ 一个副本都没有：不弹面板、设置不显示，不报错
--   11-17 用户「加个三条缩放」：右下角三斜线拖拽角 → 按住拖改宽高（地图模式 / 文字模式各记一份，存 ns.db.dnav.size[mode] = { w, h }）；
--         地图按剩下的高度和宽度等比缩放（点位跟着贴图走），文字按新宽度换行，内容放不下时面板自动长高（按钮不被裁）；
--         右键拖拽角 / 设置「面板大小重置」/ /gi 导航 重置大小 → 恢复默认（宽 300 / 地图 440、高度跟内容走）
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end
-- 11-15 GI-266 全量扫描：副本数据里的中文（首领名 / 路线 / 任务）不走 ns.L → 繁体端显示前逐字转繁（简体端原样）
-- 11-15 用户截图「为啥是繁体，要简体」：ns.ToTW 只要繁体表在就转（合并包里繁体表常驻）→ 改用 ns.TD（只在繁体模式下转）
local function TW(s) if type(s) ~= "string" then return s end if ns.TD then return ns.TD(s) end return s end

local DN = { DATA = {}, BYNAME = {}, BYINST = {} }
ns.DungeonNav = DN
DN._TW = TW   -- 11-20 DungeonNavMap.lua 共用
DN.KEEP_SEC = 7200          -- 同一个本 2 小时内重进 / 重载续上
DN.W = 300                  -- 面板宽
DN.ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t"
DN.ICON_PASS = "|TInterface\\Buttons\\UI-CheckBox-Check:13:13|t"
DN.ICON_CUR = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:13:13|t"
-- 11-17 缩放：最小宽高（文字 240 = 上一步 / 下一步 / 重新开始一排放得下；地图 308 ≈ 默认 440 的 70%），地图被压矮时最少留 100 高
DN.MIN = { text = { 240, 160 }, map = { 308, 260 } }
DN.MAPMIN = 100
DN.GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
DN.GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
DN.GRIP_HL = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"

-- ---------- 小工具 ----------
local function secret(v) return issecretvalue and issecretvalue(v) and true or false end
local function clean(v) if v == nil or secret(v) then return nil end return v end
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return pass(pcall(f, ...))
end
local function str(v) v = clean(v); return type(v) == "string" and v or nil end
local function num(v) v = clean(v); return tonumber(v) end
local function now() return (time and time()) or 0 end

-- ---------- 数据登记 ----------
--   d = { iid = 导航键（单翼 = instanceID；多翼 = instanceID × 10 + 翼号）, inst = instanceID, wing = 翼号, name = 中文名,
--         names = { 兜底匹配的名字 }, lv = "24-32", zones = { 认翼用的子区域名 },
--         body = "return { src = 来源, more = 其他掉落, steps = {…}, map = 地图（DungeonNavMap.lua 用）, mmp = 小地图首领点 }"（Lua 源码字符串或函数，按需展开）,
--         mm = "return { w, h, layers }"（11-16 小地图，按需展开成 d.minimap，points = body 里的 mmp）
--   steps[i] = { k = "boss" | "point", title = 显示名, boss = 首领名（和掉落表一致）, eid = encounterID, alias = { 事件里可能出现的别名 },
--       opt = true（可选：稀有 / 召唤）, final = true（最后一个首领）, zone = 实测子区域,
--       route = { 怎么走（字符串，或 { s = "A"|"H", t = 文字 } 分阵营）}, ref = true（经典旧世参考）, tips = { 注意 },
--       quests = { { s = "A"|"H"|nil, t = 文字 } }, loot = 掉落亮点 }
function DN.Register(d)
    if type(d) ~= "table" or not d.iid or (type(d.steps) ~= "table" and type(d.body) ~= "function" and type(d.body) ~= "string") then return end
    d.inst = d.inst or d.iid
    DN.DATA[d.iid] = d
    local list = DN.BYINST[d.inst] or {}
    local dup = false
    for k, x in ipairs(list) do if x.iid == d.iid then list[k] = d; dup = true end end
    if not dup then list[#list + 1] = d end
    table.sort(list, function(a, b) return (a.wing or 0) < (b.wing or 0) end)
    DN.BYINST[d.inst] = list
    for _, n in ipairs(d.names or { d.name }) do if not DN.BYNAME[n] then DN.BYNAME[n] = d.inst end end
end
-- 展开步骤 / 地图（body 只跑一次；出错 → 这个副本当没有数据）
function DN.Get(key)
    local d = key and DN.DATA[key]
    if not d then return nil end
    if d.body ~= nil then
        local f = d.body
        d.body = nil
        if type(f) == "string" then f = loadstring and call(loadstring, f) end   -- 数据文件里是源码字符串（省内存），用到才编译
        local b = call(f)
        if type(b) ~= "table" or type(b.steps) ~= "table" then DN.DATA[key] = nil; return nil end
        for k, v in pairs(b) do d[k] = v end
    end
    -- 11-16 小地图：d.mm = 小地图源码（几翼共用一张图时是同一个字符串），首领点在 body 的 mmp（各翼不同）
    if d.mm ~= nil then
        local f = d.mm
        d.mm = nil
        if type(f) == "string" then f = loadstring and call(loadstring, f) end
        local m = call(f)
        if type(m) == "table" then m.points = type(d.mmp) == "table" and d.mmp or {}; d.minimap = m end
        d.mmp = nil
    end
    if type(d.steps) ~= "table" or #d.steps == 0 then return nil end
    return d
end
-- 同一个 instanceID 下的各翼（单翼 = 只有自己）
function DN.Wings(d)
    return (d and DN.BYINST[d.inst]) or {}
end
function DN.Count() local n = 0; for _ in pairs(DN.DATA) do n = n + 1 end; return n end

-- ---------- 设置（ns.db.dnav；on = nil 默认开）----------
function DN.DB()
    ns.db.dnav = ns.db.dnav or {}
    return ns.db.dnav
end
function DN.Enabled() return not (ns.db and ns.db.dnav and ns.db.dnav.on == false) end
function DN.SetEnabled(v)
    if not ns.db then return end
    if v then DN.DB().on = nil else DN.DB().on = false end   -- ⛔ 11-16 原来 (not v) and false or nil 恒为 nil：关不掉
    if not v and DN.frame and not DN.preview then DN.frame:Hide() end
    if v then
        local run = DN.Run()
        if run then run.closed = nil end
        DN.Check()
    end
end
-- 「以后不弹」：关自动弹出 + 收起 + 聊天框说怎么找回（/gi 导航 照样能打开）
function DN.NeverShow()
    if not ns.db then return end
    DN.DB().on = false
    if DN.frame then DN.frame:Hide() end
    DN.preview = nil; DN.previewRun = nil
    -- 11-17「永久关闭」：找回提示走 ns.CloseHint（同一句最多说 3 次），多给一条「窗口与提醒」的路
    local msg = L("以后进副本不再自动弹出导航；想要回来：GI 菜单 → 窗口与提醒 → 副本导航，或设置 → 通用 → 进副本时显示副本导航，或输入 /gi 导航 手动打开",
        "The dungeon guide will no longer pop up; to bring it back: GI menu - Windows & alerts - Dungeon guide, Settings - General - show the dungeon guide, or type /gi dnav")
    if ns.CloseHint then call(ns.CloseHint, "dnav", msg) elseif ns.Print then call(ns.Print, msg) end
end

-- ---------- 在哪 ----------
-- 多翼：子区域名认翼 → 存档里这一趟的翼（2 小时内）→ 第一翼
function DN.PickWing(list)
    if #list <= 1 then return list[1] end
    local sub = DN.SubZone()
    if sub then
        for _, d in ipairs(list) do
            for _, z in ipairs(d.zones or {}) do if z == sub then return d end end
        end
    end
    local run = DN.Run()
    if run then for _, d in ipairs(list) do if DN.Valid(run, d.iid) then return d end end end
    return list[1]
end
-- 当前所在副本的数据表（不在副本 / 没数据 → nil）
function DN.Here()
    if not GetInstanceInfo then return nil end
    local r = { call(GetInstanceInfo) }
    local name, itype, iid = str(r[1]), str(r[2]), num(r[8])
    if itype and itype ~= "party" and itype ~= "raid" then return nil end
    local list = iid and DN.BYINST[iid]
    if not list and name and DN.BYNAME[name] then list = DN.BYINST[DN.BYNAME[name]] end
    if not list or #list == 0 then return nil end
    local pick = DN.PickWing(list)
    local d = pick and DN.Get(pick.iid)
    if d then return d, d.iid end
    return nil
end
function DN.SubZone()
    local s = str(GetSubZoneText and call(GetSubZoneText))
    if s and s ~= "" then return s end
    return nil
end
function DN.Faction()
    local f = str(UnitFactionGroup and call(UnitFactionGroup, "player"))
    return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

-- ---------- 进度 ----------
--   run = { iid = 导航键, t0 = 开打时间, cur = 当前步, done = { [i] = "kill" | "pass" }, left = 出本时间, stale = true（下次重开）, closed = true（这一趟手动关了面板） }
local function newRun(iid) return { iid = iid, t0 = now(), cur = 1, done = {} } end
function DN.Run() return ns.db and ns.db.dnav and ns.db.dnav.run or nil end
function DN.Valid(run, iid)
    return type(run) == "table" and run.iid == iid and not run.stale and (now() - (tonumber(run.t0) or 0)) < DN.KEEP_SEC
end
-- 进本：续上还是新开
function DN.Begin(iid)
    local db = DN.DB()
    if not DN.Valid(db.run, iid) then
        local closed = type(db.run) == "table" and db.run.closed and DN.DATA[db.run.iid] and DN.DATA[iid]
            and DN.DATA[db.run.iid].inst == DN.DATA[iid].inst and not db.run.stale or nil
        db.run = newRun(iid)
        db.run.closed = closed   -- 同一趟里换翼：手动关过面板的照样不弹
    end
    db.run.left = nil
    if type(db.run.done) ~= "table" then db.run.done = {} end
    return db.run
end
function DN.Steps(run)
    local d = run and DN.Get(run.iid)
    return d and d.steps or {}
end
-- 从 i 起第一个没完成的步（都完成了 → 最后一步之后 = #steps + 1）
local function firstOpen(run, i)
    local steps = DN.Steps(run)
    for j = math.max(1, i), #steps do if not run.done[j] then return j end end
    return #steps + 1
end
function DN.Finished(run)
    if not run then return false end
    for i, s in ipairs(DN.Steps(run)) do if s.final and run.done[i] == "kill" then return true end end
    return false
end

-- 首领事件 → 第几步（先认 encounterID，再认名字 / 别名）
function DN.Match(d, eid, name)
    if not d then return nil end
    eid, name = num(eid), str(name)
    if eid and eid > 0 then for i, s in ipairs(d.steps) do if s.eid and s.eid == eid then return i end end end
    if name and name ~= "" then
        for i, s in ipairs(d.steps) do
            if s.boss == name then return i end
            for _, a in ipairs(s.alias or {}) do if a == name then return i end end
        end
        for i, s in ipairs(d.steps) do   -- 事件名带前后缀时兜底（「萨利维丝女士」↔「萨利维丝」）
            if s.boss and (name:find(s.boss, 1, true) or s.boss:find(name, 1, true)) then return i end
        end
    end
    return nil
end
-- 当前翼对不上 → 看同副本别的翼（打到别的翼的首领 = 换翼了）
function DN.MatchAny(d, eid, name)
    local i = DN.Match(d, eid, name)
    if i then return d, i end
    for _, w in ipairs(DN.Wings(d)) do
        if w.iid ~= d.iid then
            local wd = DN.Get(w.iid)
            local j = wd and DN.Match(wd, eid, name)
            if j then return wd, j end
        end
    end
    return d, nil
end

function DN.OnEncounterStart(eid, name)
    local d0 = DN.Here()
    if not d0 then return end
    local d, i = DN.MatchAny(d0, eid, name)
    local run = DN.Begin(d.iid)
    if i and not run.done[i] then run.cur = i end
    run.fight = i
    DN.Refresh()
end
function DN.OnEncounterEnd(eid, name, ok)
    local d0 = DN.Here()
    if not d0 then return end
    local d, i = DN.MatchAny(d0, eid, name)
    local run = DN.Begin(d.iid)
    run.fight = nil
    if not i or num(ok) ~= 1 then DN.Refresh(); return end
    run.done[i] = "kill"
    -- 越过的机制点（火盆）算完成；没打的可选首领留空
    for j = 1, i - 1 do
        local s = d.steps[j]
        if s.k == "point" and not run.done[j] then run.done[j] = "pass" end
    end
    if (run.cur or 1) <= i then run.cur = firstOpen(run, i + 1) end
    DN.Refresh()
end

-- 手动：下一步 = 这一步记「已过」（击杀的保留击杀）→ 往后；上一步 = 退一步，退到的那步是手动「已过」的就取消
function DN.Next()
    local run = DN.CurRun()
    if not run then return end
    local n = #DN.Steps(run)
    local c = run.cur or 1
    if c > n then return end
    if not run.done[c] then run.done[c] = "pass" end
    run.cur = c + 1
    DN.Refresh()
end
function DN.Prev()
    local run = DN.CurRun()
    if not run then return end
    local c = math.max(1, (run.cur or 1) - 1)
    run.cur = c
    if run.done[c] == "pass" then run.done[c] = nil end
    DN.Refresh()
end
function DN.Restart()
    local run = DN.CurRun()
    if not run then return end
    local fresh = newRun(run.iid)
    if DN.preview then DN.previewRun = fresh else DN.DB().run = fresh end
    DN.Refresh()
end
-- 换一翼：同副本的下一翼，从头开始
function DN.NextWing()
    local run = DN.CurRun()
    local d = run and DN.DATA[run.iid]
    local list = DN.Wings(d)
    if #list <= 1 then return end
    local k = 1
    for j, w in ipairs(list) do if w.iid == d.iid then k = j end end
    local nx = list[k % #list + 1]
    if not DN.Get(nx.iid) then return end
    local fresh = newRun(nx.iid)
    if DN.preview then DN.previewRun = fresh else DN.DB().run = fresh end
    DN.Refresh()
end
-- 面板显示的是哪份进度：本里 = 存档；本外预览 = 一份临时的（不写存档）
function DN.CurRun()
    if DN.preview then return DN.previewRun end
    return DN.Run()
end

-- ---------- 面板 ----------
local function fs(parent, font, w)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    f:SetJustifyH("LEFT"); f:SetJustifyV("TOP")
    if w then f:SetWidth(w) end
    if f.SetWordWrap then f:SetWordWrap(true) end
    return f
end
local function btn(parent, w, text, click)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    b:SetSize(w, 20); b:SetText(text)
    b:SetScript("OnClick", click)
    return b
end
local function hgt(f)
    local h = f.GetStringHeight and f:GetStringHeight() or 12
    return math.max(tonumber(h) or 12, 12)
end

function DN.Build()
    if DN.frame then return DN.frame end
    local W = DN.W
    local f = CreateFrame("Frame", "GearInsightForeverDungeonNav", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(W, 200)
    f:SetFrameStrata("HIGH")   -- 11-15 用户「图层放到上面」：原 MEDIUM 被增益图标 / 活动目标等压住
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        pcall(f.SetBackdropColor, f, 0.05, 0.06, 0.08, 0.92); pcall(f.SetBackdropBorderColor, f, 0.41, 0.8, 0.94, 0.9)
    end
    local pos = ns.db and DN.DB().pos
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200) end
    f:SetMovable(true); f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        if p and ns.db then DN.DB().pos = { p, x, y } end
    end)
    f.title = fs(f, "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -7); f.title:SetWidth(W - 60)
    if f.title.SetWordWrap then f.title:SetWordWrap(false) end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() DN.Close() end)   -- 直接 Hide（原生红叉默认走 HideUIPanel，战斗中被拦）
    f.close = close
    f.fold = btn(f, 20, "-", function() DN.ToggleFold() end); f.fold:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    -- 11-15「需要可视化地图」：地图 / 文字切换（DungeonNavMap.lua 加载了、这个本有地图数据才显示）
    f.view = btn(f, 44, L("文字", "Text"), function() DN.ToggleView() end); f.view:SetPoint("RIGHT", f.fold, "LEFT", -2, 0); f.view:Hide()
    -- 11-16「小地图和羊皮纸地图都要，可以切换」：羊皮纸 / 小地图（地图模式、这个本两种都有才显示）
    f.kind = btn(f, 56, "", function() DN.ToggleKind() end); f.kind:SetPoint("RIGHT", f.view, "LEFT", -2, 0); f.kind:Hide()
    -- 折叠时的一行：第 N / M 步：XX
    f.mini = fs(f, "GameFontHighlightSmall", W - 16); f.mini:SetPoint("TOPLEFT", 8, -26)
    -- 展开时的内容
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -24); body:SetPoint("TOPRIGHT", 0, -24); body:SetHeight(100)
    f.body = body
    f.where = fs(body, "GameFontDisableSmall", W - 16)
    f.list = fs(body, "GameFontHighlightSmall", W - 16)
    f.step = fs(body, "GameFontNormal", W - 16)
    f.text = fs(body, "GameFontHighlightSmall", W - 16)
    f.foot = fs(body, "GameFontDisableSmall", W - 16)
    f.prev = btn(body, 70, L("上一步", "Prev"), function() DN.Prev() end)
    f.next = btn(body, 70, L("下一步", "Next"), function() DN.Next() end)
    f.reset = btn(body, 76, L("重新开始", "Restart"), function() DN.Restart() end)
    -- 第二排：以后不弹（11-15「有个按钮是永不展示，以后可以去设置重新拿出来」）· 换一翼（多翼副本才有）
    f.never = btn(body, 90, L("以后不弹", "Don't pop up"), function() DN.NeverShow() end)
    f.wing = btn(body, 90, L("换一翼", "Next wing"), function() DN.NextWing() end)
    f.wing:Hide()
    DN.BuildGrip(f)
    f:Hide()
    DN.frame = f
    return f
end

-- ---------- 11-17 缩放（右下角三斜线）----------
local function uiSize()
    local w = num(UIParent and call(UIParent.GetWidth, UIParent))
    local h = num(UIParent and call(UIParent.GetHeight, UIParent))
    return (w and w > 0) and w or 1920, (h and h > 0) and h or 1080
end
function DN.DefW(mode)
    if mode == "map" then return (DN.Map and DN.Map.W) or 440 end
    return DN.W
end
-- 最小 / 最大：最大 = 整个屏幕（UI 坐标）
function DN.Bounds(mode)
    local mn = DN.MIN[mode] or DN.MIN.text
    local sw, sh = uiSize()
    return mn[1], mn[2], math.max(mn[1], math.floor(sw)), math.max(mn[2], math.floor(sh))
end
function DN.Clamp(mode, w, h)
    local a, b, c, e = DN.Bounds(mode)
    w = math.floor(math.max(a, math.min(c, tonumber(w) or a)) + 0.5)
    h = math.floor(math.max(b, math.min(e, tonumber(h) or b)) + 0.5)
    return w, h
end
-- 玩家拖过的大小（没拖过 → nil = 默认：宽按模式、高跟内容）
function DN.UserSize(mode)
    local sz = ns.db and ns.db.dnav and ns.db.dnav.size
    local v = type(sz) == "table" and sz[mode]
    if type(v) ~= "table" or not tonumber(v[1]) or not tonumber(v[2]) then return nil end
    return DN.Clamp(mode, v[1], v[2])
end
function DN.SaveSize(mode, w, h)
    if not ns.db then return end
    local db = DN.DB()
    if type(db.size) ~= "table" then db.size = {} end
    w, h = DN.Clamp(mode, w, h)
    db.size[mode] = { w, h }
end
-- 现在这一帧该用的宽、高（高 nil = 跟内容走）：拖动中 → 实时值；拖过 → 存档；否则默认
function DN.SizeFor(f, mode)
    if rawget(f, "sizing") and rawget(f, "liveW") then return f.liveW, f.liveH end
    local w, h = DN.UserSize(mode)
    if w then return w, h end
    return DN.DefW(mode), nil
end
function DN.ApplyBounds(f, mode)
    if rawget(f, "boundsMode") == mode then return end
    f.boundsMode = mode
    if f.SetResizable then pcall(f.SetResizable, f, true) end
    local a, b, c, e = DN.Bounds(mode)
    if f.SetResizeBounds then
        pcall(f.SetResizeBounds, f, a, b, c, e)
    else   -- 旧客户端
        if f.SetMinResize then pcall(f.SetMinResize, f, a, b) end
        if f.SetMaxResize then pcall(f.SetMaxResize, f, c, e) end
    end
end
-- 恢复默认大小（两种模式都清）
function DN.ResetSize(quiet)
    if not ns.db then return end
    DN.DB().size = nil
    local f = DN.frame
    if f then f.liveW, f.liveH, f.sizing, f.drag = nil, nil, nil, nil; f.curW = nil; DN.Refresh() end
    if not quiet and ns.Print then call(ns.Print, L("副本导航面板已恢复默认大小", "Dungeon guide size reset")) end
end
-- 按下：先把面板改成左上角定位（拖右下角时左上不动），记下起点
function DN.SizeStart(f)
    if rawget(f, "sizing") or DN.Folded() then return end
    local l, t = num(call(f.GetLeft, f)), num(call(f.GetTop, f))
    local cx, cy = call(GetCursorPosition)
    cx, cy = num(cx), num(cy)
    if not (l and t and cx and cy) then return end
    local _, sh = uiSize()
    local top = num(UIParent and call(UIParent.GetTop, UIParent)) or sh
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", l, t - top)
    if ns.db then DN.DB().pos = { "TOPLEFT", l, t - top } end
    local es = num(call(f.GetEffectiveScale, f)) or 1
    if es <= 0 then es = 1 end
    local w0 = num(call(f.GetWidth, f)) or rawget(f, "curW") or DN.W
    local h0 = num(call(f.GetHeight, f)) or 200
    f.drag = { cx = cx, cy = cy, es = es, w = w0, h = h0, mode = rawget(f, "curMode") or "text" }
    f.liveW, f.liveH = DN.Clamp(f.drag.mode, w0, h0)
    f.sizing = true
    if f.grip then f.grip:SetScript("OnUpdate", function() DN.SizeTick(f) end) end
end
function DN.SizeTick(f)
    local dr = rawget(f, "drag")
    if not dr then return end
    local x, y = call(GetCursorPosition)
    x, y = num(x), num(y)
    if not (x and y) then return end
    local w, h = DN.Clamp(dr.mode, dr.w + (x - dr.cx) / dr.es, dr.h + (dr.cy - y) / dr.es)
    if w == rawget(f, "liveW") and h == rawget(f, "liveH") then return end
    f.liveW, f.liveH = w, h
    DN.Refresh()
end
function DN.SizeStop(f)
    if f.grip then f.grip:SetScript("OnUpdate", nil) end
    if not rawget(f, "sizing") then return end
    local dr = rawget(f, "drag")
    if dr and rawget(f, "liveW") then DN.SaveSize(dr.mode, f.liveW, f.liveH) end
    f.sizing, f.drag, f.liveW, f.liveH = nil, nil, nil, nil
    DN.Refresh()
end
function DN.BuildGrip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(16, 16); g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    if g.SetNormalTexture then g:SetNormalTexture(DN.GRIP_UP) end
    if g.SetPushedTexture then g:SetPushedTexture(DN.GRIP_DOWN) end
    if g.SetHighlightTexture then g:SetHighlightTexture(DN.GRIP_HL) end
    local lv = num(call(f.GetFrameLevel, f))
    if lv and g.SetFrameLevel then g:SetFrameLevel(lv + 20) end   -- 压过地图画布上的圆点
    g:SetScript("OnMouseDown", function(_, b) if b == nil or b == "LeftButton" then DN.SizeStart(f) end end)
    g:SetScript("OnMouseUp", function(_, b)
        if b == "RightButton" then DN.ResetSize(); return end
        DN.SizeStop(f)
    end)
    g:SetScript("OnHide", function() if rawget(f, "sizing") then DN.SizeStop(f) end end)
    g:SetScript("OnEnter", function(self)
        local tt = rawget(_G, "GameTooltip")
        if not tt then return end
        call(tt.SetOwner, tt, self, "ANCHOR_RIGHT")
        call(tt.SetText, tt, L("调整大小", "Resize"), 1, 0.82, 0)
        call(tt.AddLine, tt, L("按住左键拖：改变面板宽高（地图跟着放大缩小）", "Drag: resize the panel (the map scales with it)"), 1, 1, 1, true)
        call(tt.AddLine, tt, L("右键：恢复默认大小", "Right-click: reset to default size"), 0.6, 0.85, 1, true)
        call(tt.Show, tt)
    end)
    g:SetScript("OnLeave", function() local tt = rawget(_G, "GameTooltip"); if tt then call(tt.Hide, tt) end end)
    f.grip = g
    return g
end

-- 地图：DungeonNavMap.lua（HOLD）加载了 + 这个本有地图数据（羊皮纸 map / 小地图 minimap 任一）+ 贴图没坏 → 可用；玩家点「文字」后 db.dnav.view = "text"
function DN.MapUsable(d)
    local M = DN.Map
    if not (M and type(d) == "table" and (d.map or d.minimap)) then return false end
    return call(M.Usable, d) == true
end
function DN.MapOn(d)
    return DN.MapUsable(d) and not (ns.db and ns.db.dnav and ns.db.dnav.view == "text")
end
function DN.ToggleView()
    if not ns.db then return end
    DN.DB().view = (DN.DB().view ~= "text") and "text" or nil
    DN.Refresh()
end
-- 羊皮纸 / 小地图切换（DungeonNavMap.lua 记 db.dnav.kind）
function DN.ToggleKind()
    local run = DN.CurRun()
    local d = run and DN.Get(run.iid)
    if d and DN.Map and DN.Map.ToggleKind then call(DN.Map.ToggleKind, d) end
end
-- 面板宽度（地图模式更宽）
function DN.SetWidth(f, W)
    if rawget(f, "curW") == W then return end
    f.curW = W
    f:SetWidth(W)
    f.title:SetWidth(W - 100)
    for _, k in ipairs({ "mini", "where", "list", "step", "text" }) do f[k]:SetWidth(W - 16) end
    f.foot:SetWidth(W - 30)   -- 11-17 右下角让出拖拽角

end

function DN.Folded() return ns.db and ns.db.dnav and ns.db.dnav.fold == true or false end
function DN.ToggleFold()
    if not ns.db then return end
    DN.DB().fold = (not DN.Folded()) or nil
    DN.Refresh()
end

-- 步骤列表的一行
function DN.StepLine(run, i, s)
    local d = run.done[i]
    local cur = (run.cur or 1) == i
    local mark = (d == "kill" and DN.ICON_DONE) or (d == "pass" and DN.ICON_PASS) or (cur and DN.ICON_CUR) or "|cff666666·|r"
    local name = s.title
    if cur then name = "|cffffd100" .. name .. "|r"
    elseif d then name = "|cff8c8c8c" .. name .. "|r"
    elseif s.opt then name = "|cffa0a0a0" .. name .. "|r" end
    if run.fight == i then name = name .. L(" |cffff4040战斗中|r", " |cffff4040in combat|r") end
    return mark .. " " .. name
end
-- 当前步的正文（d 给了、又是第一步 → 带上「其他掉落」）
function DN.StepBody(s, side, d, i)
    local out = {}
    local rs = {}
    for _, t in ipairs(s.route or {}) do
        if type(t) == "table" then
            if t.t and (not t.s or not side or t.s == side) then
                rs[#rs + 1] = ((not side and t.s) and ((t.s == "A" and L("[联盟] ", "[A] ")) or L("[部落] ", "[H] ")) or "") .. t.t
            end
        elseif type(t) == "string" then
            rs[#rs + 1] = t
        end
    end
    if #rs > 0 then
        out[#out + 1] = "|cff69ccf0" .. L("怎么走", "Route") .. "|r" .. (s.ref and ("|cff8c8c8c" .. L("（经典参考）", " (classic ref)") .. "|r") or "")
        for _, t in ipairs(rs) do out[#out + 1] = t end
    end
    if s.tips and #s.tips > 0 then
        out[#out + 1] = "|cffff9933" .. L("注意", "Notes") .. "|r"
        for _, t in ipairs(s.tips) do out[#out + 1] = t end
    end
    local qs = {}
    for _, q in ipairs(s.quests or {}) do
        if not q.s or not side or q.s == side then qs[#qs + 1] = q end
    end
    if #qs > 0 then
        out[#out + 1] = "|cffffd100" .. L("任务", "Quests") .. "|r"
        for _, q in ipairs(qs) do
            local tag = (not side and q.s) and ((q.s == "A" and L("[联盟] ", "[A] ")) or L("[部落] ", "[H] ")) or ""
            out[#out + 1] = tag .. q.t
        end
    end
    if s.loot then out[#out + 1] = "|cffa335ee" .. L("掉落", "Loot") .. "|r " .. s.loot end
    if d and i == 1 and type(d.more) == "string" and d.more ~= "" then
        out[#out + 1] = "|cff8c8c8c" .. L("其他掉落（稀有 / 宝箱等）：", "Other loot (rares / chests): ") .. d.more .. "|r"
    end
    return table.concat(out, "\n")
end

-- 面板最下面一行说明（11-18 用户「字太多没必要」：只留一行，详细说明在地图右上「?」）
function DN.Foot(m)
    if m and DN.Map and DN.Map.Legend then return call(DN.Map.Legend) or "" end
    return L("首领击杀自动打勾；机制点 / 没刷的稀有点「下一步」", "Boss kills tick automatically; use Next for mechanics / missing rares")
end

function DN.Refresh()
    local f = DN.frame
    if not (f and f:IsShown()) then return false end
    if not DN._lv then DN._lv = true; call(ns.DnavLootAttach, f) end   -- 11-18 掉落点击展开 / 精简正文（资讯子插件 DnavLoot.lua，HOLD，按需加载）
    local run = DN.CurRun()
    local d = run and DN.Get(run.iid)
    if not d then f:Hide(); return false end
    local steps = d.steps
    local n = #steps
    local c = math.min(run.cur or 1, n + 1)
    local cs = steps[c]
    f.title:SetText(TW(L("副本导航 · ", "Dungeon guide - ") .. d.name .. (DN.preview and L("（预览）", " (preview)") or "")))
    local stepTxt = (c <= n) and string.format(L("第 %d / %d 步：%s", "Step %d / %d: %s"), c, n, cs.title)
        or L("全部完成，辛苦了！", "All done!")
    local folded = DN.Folded()
    f.fold:SetText(folded and "+" or "-")
    local mapUsable = DN.MapUsable(d)
    local mapOn = mapUsable and DN.MapOn(d)
    if mapUsable then f.view:Show(); f.view:SetText(mapOn and L("文字", "Text") or L("地图", "Map")) else f.view:Hide() end
    local kindOn = mapOn and call(DN.Map.KindButton, f.kind, d) == true
    if not kindOn then f.kind:Hide() end
    -- 11-17 缩放：宽 = 拖动中 / 存档 / 默认；高 H = 玩家拖的高度（nil = 跟内容走）
    local mode = mapOn and "map" or "text"
    f.curMode = mode
    DN.ApplyBounds(f, mode)
    local W, H = DN.SizeFor(f, mode)
    DN.SetWidth(f, W)
    f.title:SetWidth((rawget(f, "curW") or DN.W) - (mapUsable and 106 or 60) - (kindOn and 58 or 0))
    if folded then
        f.body:Hide(); f.mini:Show()
        if f.grip then f.grip:Hide() end
        f.mini:SetText(TW(stepTxt))
        f:SetHeight(26 + hgt(f.mini) + 8)
        return true
    end
    f.mini:Hide(); f.body:Show()
    if f.grip then f.grip:Show() end
    local y = -2
    local sub = (not DN.preview) and DN.SubZone() or nil
    local lvTxt = d.lv and (L("推荐等级 ", "Level ") .. d.lv) or nil
    if sub or lvTxt then
        local w = {}
        if sub then w[#w + 1] = L("你现在在：", "You are in: ") .. "|cffffffff" .. sub .. "|r" end
        if lvTxt then w[#w + 1] = lvTxt end
        f.where:Show(); f.where:SetText(TW(table.concat(w, "　")))
        f.where:ClearAllPoints(); f.where:SetPoint("TOPLEFT", 8, y); y = y - hgt(f.where) - 4
    else
        f.where:Hide()
    end
    -- 11-17 拖过高度：地图高度 = 面板高 − 地图下面的内容（当前步 / 正文 / 两排按钮 / 说明），先量下面的
    local maxH
    if mapOn and H then
        f.step:SetText(TW(stepTxt))
        local below = hgt(f.step) + 3 + 48
        local body = cs and DN.StepBody(cs, DN.Faction(), d, c) or ""
        if body ~= "" then f.text:SetText(TW(body)); below = below + hgt(f.text) + 6 end
        f.foot:SetText(DN.Foot(true))
        below = below + hgt(f.foot) + 6 + (DN.AfterText and 20 or 0)
        maxH = math.max(DN.MAPMIN, math.floor(H - 26 + y - 6 - below))
    end
    -- 地图模式：地图代替步骤列表（画不了 / 出错 → 退回列表）
    local mh = mapOn and call(DN.Map.Draw, f.body, (rawget(f, "curW") or DN.W) - 16, run, d, c, 8, y, maxH) or nil
    if mh then
        f.list:Hide()
        y = y - mh - 6
        if kindOn and call(DN.Map.KindButton, f.kind, d) ~= true then f.title:SetWidth((rawget(f, "curW") or DN.W) - 106) end   -- 画的时候一种贴图坏了 → 只剩一种
    else
        if DN.Map and DN.Map.Hide then call(DN.Map.Hide, f.body) end
        if mapOn then   -- 本来要画地图但没画成（贴图缺失）→ 宽度 / 切换按钮也退回文字（大小按文字模式那一份）
            mode = "text"
            f.curMode = mode
            DN.ApplyBounds(f, mode)
            W, H = DN.SizeFor(f, mode)
            DN.SetWidth(f, W)
            f.kind:Hide()
            if not DN.MapUsable(d) then f.view:Hide(); f.title:SetWidth((rawget(f, "curW") or DN.W) - 60) end
        end
        local lines = {}
        for i, s in ipairs(steps) do lines[#lines + 1] = DN.StepLine(run, i, s) end
        f.list:Show()
        f.list:SetText(TW(table.concat(lines, "\n")))
        f.list:ClearAllPoints(); f.list:SetPoint("TOPLEFT", 8, y); y = y - hgt(f.list) - 6
    end
    f.step:SetText(TW(stepTxt))
    f.step:ClearAllPoints(); f.step:SetPoint("TOPLEFT", 8, y); y = y - hgt(f.step) - 3
    -- 11-21「UI优化下」：正文精简后常是空串（掉落挪进按钮、路线有地图就省），空串也占 12 高 → 步骤名和掉落中间一块空白；空了就不摆
    local body = cs and DN.StepBody(cs, DN.Faction(), d, c) or ""
    if body ~= "" then
        f.text:Show(); f.text:SetText(TW(body))
        f.text:ClearAllPoints(); f.text:SetPoint("TOPLEFT", 8, y); y = y - hgt(f.text) - 6
    else
        f.text:Hide()
    end
    if DN.AfterText then y = call(DN.AfterText, f, cs, d, c, y) or y end
    f.prev:ClearAllPoints(); f.prev:SetPoint("TOPLEFT", 8, y)
    f.next:ClearAllPoints(); f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.reset:ClearAllPoints(); f.reset:SetPoint("TOPRIGHT", -8, y)
    if f.prev.SetEnabled then f.prev:SetEnabled(c > 1); f.next:SetEnabled(c <= n) end
    y = y - 24
    f.never:ClearAllPoints(); f.never:SetPoint("TOPLEFT", 8, y)
    if #DN.Wings(d) > 1 then
        f.wing:Show(); f.wing:ClearAllPoints(); f.wing:SetPoint("TOPRIGHT", -8, y)
    else
        f.wing:Hide()
    end
    y = y - 24
    f.foot:SetText(DN.Foot(mh))
    f.foot:ClearAllPoints(); f.foot:SetPoint("TOPLEFT", 8, y); y = y - hgt(f.foot) - 6
    f.body:SetHeight(-y)
    local need = 24 - y + 2   -- 内容放不下拖的高度 → 面板长高（按钮 / 说明不被裁）
    f:SetHeight((H and H > need) and H or need)
    return true
end

function DN.Show()
    local f = DN.Build()
    f:Show()
    DN.Refresh()
end
function DN.Close()
    if DN.frame then DN.frame:Hide() end
    if DN.preview then DN.preview = nil; DN.previewRun = nil; return end
    local run = DN.Run()
    if run and DN.Here() then run.closed = true end   -- 这一趟不再自动弹（/gi 导航 再打开）
end
function DN.Shown() return DN.frame ~= nil and DN.frame:IsShown() and true or false end

-- 进出副本 / 换区：在有数据的本里 → 续上或新开进度，按开关弹；出本 → 收起（预览不收）
function DN.Check()
    if not ns.db then return end
    local d, iid = DN.Here()
    local db = DN.DB()
    if d then
        if DN.preview then DN.preview = nil; DN.previewRun = nil end
        DN.lastIn = true
        local run = DN.Begin(iid)
        if DN.Enabled() and not run.closed then DN.Show() else DN.Refresh() end
        return
    end
    local run = db.run
    if type(run) == "table" and not run.left and DN.lastIn then
        run.left = now()
        if DN.Finished(run) then run.stale = true end   -- 打完尾王出本 = 下次进来是新的一趟
    end
    DN.lastIn = nil
    if not DN.preview and DN.frame then DN.frame:Hide() end
end

-- 系统提示「XX 已被重置」→ 这一趟作废
function DN.OnSystem(msg)
    msg = str(msg)
    local run = DN.Run()
    if not (msg and run) then return end
    local d = DN.DATA[run.iid]
    if not d then return end
    local names = {}
    for _, w in ipairs(DN.Wings(d)) do for _, nm in ipairs(w.names or { w.name }) do names[#names + 1] = nm end end
    local hit = false
    local fmt = str(rawget(_G, "INSTANCE_RESET_SUCCESS"))
    if fmt then
        local pat = "^" .. fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
        local who = msg:match(pat)
        if who then for _, nm in ipairs(names) do if who == nm then hit = true end end end
    end
    if not hit and (msg:find("重置", 1, true) or msg:find("reset", 1, true)) then
        for _, nm in ipairs(names) do if msg:find(nm, 1, true) then hit = true end end
    end
    if hit then run.stale = true end
end

-- 按名字找副本（/gi 导航 黑石 → 名字里带「黑石」的第一个）
function DN.Find(q)
    q = type(q) == "string" and q:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if q == "" then return nil end
    local best
    for k, d in pairs(DN.DATA) do
        for _, nm in ipairs(d.names or { d.name }) do
            if nm == q then return k end
            if nm:lower():find(q:lower(), 1, true) and (not best or k < best) then best = k end
        end
    end
    return best
end
-- /gi 导航：开着就关；本里没开 → 打开；本外 → 预览（不写存档；/gi 导航 名字 = 预览那个副本，默认黑暗深渊）
function DN.Toggle(arg)
    local want = DN.Find(arg)
    if DN.Shown() and not want then DN.Close(); return end
    local d, iid = DN.Here()
    if d and ns.db and not want then
        local run = DN.Begin(iid)
        run.closed = nil
        DN.preview = nil
        DN.Show()
        return
    end
    local pick = want or (DN.DATA[48] and 48)
    if not (pick and DN.Get(pick)) then
        pick = nil
        for k in pairs(DN.DATA) do if DN.Get(k) and (not pick or k < pick) then pick = k end end
    end
    if not pick then return end
    DN.preview = true
    DN.previewRun = newRun(pick)
    DN.Show()
end

-- ---------- 事件 ----------
DN.EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_SYSTEM" }
local ev = CreateFrame("Frame")
DN.ev = ev
for _, e in ipairs(DN.EVENTS) do pcall(ev.RegisterEvent, ev, e) end
function DN.OnEvent(_, e, a1, a2, a3, a4, a5)
    if not ns.db then return end
    if e == "ENCOUNTER_START" then pcall(DN.OnEncounterStart, a1, a2); return end
    if e == "ENCOUNTER_END" then pcall(DN.OnEncounterEnd, a1, a2, a5); return end
    if e == "CHAT_MSG_SYSTEM" then pcall(DN.OnSystem, a1); return end
    if e == "ZONE_CHANGED" or e == "ZONE_CHANGED_INDOORS" then
        local run = DN.Run()
        local d = run and DN.DATA[run.iid]
        if d and #DN.Wings(d) > 1 and not DN.preview then pcall(DN.Check); return end   -- 多翼：子区域换了可能是换翼
        if DN.Shown() and not DN.preview then pcall(DN.Refresh) end
        return
    end
    pcall(DN.Check)
end
ev:SetScript("OnEvent", DN.OnEvent)
table.insert(ns.modules, function() pcall(DN.Check) end)

-- ---------- 设置 / 命令 ----------
if ns.RegisterSettings then
    ns.RegisterSettings({ key = "dnav", order = 25, data = "general", avail = function() return ns.DungeonNav ~= nil and next(DN.DATA) ~= nil end,
        title = function() return L("副本导航", "Dungeon guide") end, short = function() return L("副本导航", "Dungeon guide") end,
        items = {
            { type = "check", id = "dnav.on", text = function() return L("进副本时显示副本导航（首领顺序、怎么走、注意事项）", "Show the dungeon guide when entering a dungeon") end,
              get = function() return DN.Enabled() end, set = function(v) DN.SetEnabled(v) end },
            { type = "button", id = "dnav.preview", w = 140, text = function() return L("打开 / 关闭面板", "Toggle panel") end, click = function() DN.Toggle() end },
            { type = "button", id = "dnav.resetpos", w = 120, inline = true, x = 160, text = function() return L("面板位置重置", "Reset position") end,
              click = function()
                  DN.DB().pos = nil
                  if DN.frame then DN.frame:ClearAllPoints(); DN.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200) end
              end },
            -- 11-17 右下角三斜线拖过大小 → 这里一键恢复默认（右键拖拽角 / /gi 导航 重置大小 同效）
            { type = "button", id = "dnav.resetsize", w = 140, text = function() return L("面板大小重置", "Reset size") end,
              click = function() DN.ResetSize() end },
            { type = "note", text = function() return L("也可以输入 /gi 导航（本外预览，/gi 导航 副本名 看指定副本）；副本里拿不到坐标，只按首领击杀推进，机制点请手动点「下一步」",
                "Or type /gi dnav (outside: preview; /gi dnav <name> for a dungeon); no positions in dungeons, so it advances on boss kills - press Next for mechanics") end },
        } })
end

ns.ExtraSlash = ns.ExtraSlash or {}
-- 11-17 /gi 导航 重置大小（/gi dnav resetsize）= 恢复默认大小
DN.RESET_ARGS = { ["重置大小"] = true, ["大小重置"] = true, ["重置"] = true, resetsize = true, reset = true, size = true }
ns.ExtraSlash["导航"] = function(rest, raw)
    local a = raw or rest
    local q = type(a) == "string" and a:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
    if DN.RESET_ARGS[q] then DN.ResetSize(); return end
    DN.Toggle(a)
end
ns.ExtraSlash.dnav = ns.ExtraSlash["导航"]

-- 11-17「这些弹出的功能都确保能永久关闭」：面板上「以后不弹」关掉的从设置页「窗口与提醒」找回（存档 dnav.on，和功能中心「副本导航」同一个键）
if ns.RegisterWindow then ns.RegisterWindow({ key = "dnav", order = 25, title = function() return L("副本导航", "Dungeon guide") end,
    avail = function() return DN.Count() > 0 end,
    state = function()
        if DN.Shown() then return L("显示中", "Shown") end
        if not DN.Enabled() then return L("已关闭（/gi 导航 照样能手动打开）", "Off (/gi dnav still opens it)") end
        return L("进副本时自动弹出", "Pops up when you enter a dungeon")
    end,
    actions = function()
        local on = DN.Enabled()
        return {
            { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function() DN.SetEnabled(not on) end },
            { text = L("现在看看", "Show now"), fn = function() DN.Toggle() end },
        }
    end }) end
