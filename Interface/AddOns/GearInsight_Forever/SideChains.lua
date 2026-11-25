-- 特殊任务线并进升级规划（10-18 用户转抖音「魔兽无限睡袋任务路线流程」：「把这个安排到升级规划，三端同步」）。
--   数据 SideChainsData.lua ← scripts/forever_side_chains.py（网站 / 小程序导出同一份）。
--   升级规划「地图待办」里：到推荐等级（按阵营）出一行；做完的步骤按任务 ID 查 C_QuestLog.IsQuestFlaggedCompleted 自动打勾。
-- 11-23 门任务（用户「升级规划加入重要的门任务必做的任务，点击可以打开悬浮窗，任务追踪，跟睡袋一样」）：
--   同一套任务线，数据 GateChainsData.lua 在按需加载的 GearInsight_Forever_Gate 里（scripts/forever_gate_chains.py）。
--   内核净减：路线大弹框（SC.Show）整块搬进 _Gate 的 GatePop.lua（睡袋也用它，点了才加载）；规划行怎么画搬进 _Plan 的 PagePlan.lua。
--   这里留：进度判定（+ 并行任务步 doneAll / 物品步 need / 钥匙在身上 = 门已开）、时间轴行、追踪小窗（多条钉住时「‹ ›」切换）、开关。
--   门任务默认不钉（右键 / 弹框按钮手动钉），睡袋照旧到级自动钉。
local _, ns = ...
local L = ns.L

local SC = {}
ns.SideChains = SC

local function faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde") and "Horde" or "Alliance"
end
SC.Faction = faction

local function questDone(id)
    if not id then return false end
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not f then return false end
    local ok, v = pcall(f, id)
    return ok and v and true or false
end
local function onQuest(id)
    if not id then return false end
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, v = pcall(C_QuestLog.IsOnQuest, id)
        if ok and v then return true end
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, v = pcall(C_QuestLog.GetLogIndexForQuestID, id)
        if ok and v and v > 0 then return true end
    end
    return false
end
SC._questDone, SC._onQuest = questDone, onQuest   -- 测试用
-- 背包里有几个（第二个参数 true = 含银行；钥匙环在不在内要游戏实测）
local function bagCount(id)
    if not (id and GetItemCount) then return nil end
    local ok, n = pcall(GetItemCount, id, true)
    if ok and type(n) == "number" then return n end
    return nil
end
SC.ItemCount = bagCount

-- 一步做没做：done 交了 / start 接了或交了 / doneAll 几个并行任务全交了 / 只有 need（没任务）的步：物品都齐了
local function stepDone(s)
    if s.done and questDone(s.done) then return true end
    if s.start and s.start ~= s.done and (onQuest(s.start) or questDone(s.start)) then return true end
    if s.doneAll then
        for _, q in ipairs(s.doneAll) do if not questDone(q) then return false end end
        return true
    end
    if s.need and not s.done and not s.start then
        for _, e in ipairs(s.need) do if (bagCount(e[1]) or 0) < (e[2] or 1) then return false end end
        return true
    end
    return false
end

-- 每一步状态：done · next（第一个没做的）· todo
function SC.Progress(c, fac)
    local steps = (c.steps and c.steps[fac or faction()]) or {}
    local st, n, nextI = {}, 0, nil
    for i, s in ipairs(steps) do
        local d = stepDone(s)
        st[i] = d and "done" or "todo"
        if d then n = n + 1 end
    end
    -- 后面的步做了，前面的一定也做了（任务线是串的；有的步只看「接没接」）
    local last = 0
    for i = #st, 1, -1 do if st[i] == "done" then last = i; break end end
    for i = 1, last do if st[i] ~= "done" then st[i] = "done"; n = n + 1 end end
    if #steps > 0 and c.item then
        local cnt = bagCount(c.item)
        if c.gate then
            -- 门任务：钥匙在身上 = 门已开（终点任务在《无限》里改了名也不卡）；任务做完但钥匙不在身上不回退（SC.KeyMissing 提示）
            if cnt and cnt > 0 then for i = 1, #steps do st[i] = "done" end; n = #steps end
        elseif n >= #steps and cnt == 0 then
            -- 11-07 用户截图「睡袋任务咋没了，做到这步」：第 6 步一拿到信使背包就被标完成 → 奖励物品不在背包里就不算做完，最后一步留着当「下一步」
            st[#steps] = "todo"; n = #steps - 1
        end
    end
    for i = 1, #st do if st[i] ~= "done" then nextI = i; st[i] = "next"; break end end
    return st, n, #steps, nextI
end

-- 门任务做完了但钥匙不在身上（扔了 / 放银行以外的地方）
function SC.KeyMissing(c, fac)
    if not (c and c.gate and c.item) then return false end
    local _, n, total = SC.Progress(c, fac)
    return total > 0 and n >= total and bagCount(c.item) == 0
end

-- 物品步的计数文字「熔火碎片 0/1 · 瑟银锭 2/2」
function SC.NeedText(s)
    if not s.need then return nil end
    local t = {}
    for _, e in ipairs(s.need) do
        local have, want = bagCount(e[1]) or 0, e[2] or 1
        t[#t + 1] = (have >= want and "|cff33ff99" or "|cffff7f50") .. L(e[3] or "?", e[4] or e[3] or "?") .. " " .. math.min(have, want) .. "/" .. want .. "|r"
    end
    return table.concat(t, " · ")
end

-- 升级规划用：推荐等级（按阵营）那一级出一行；没做完且已经过了推荐等级 → 挪到当前等级（别让它掉进「已过去」）
--   门任务：rec 里没有本阵营 = 本阵营不显示；提示行（hint，没有步骤）按钥匙在不在身上算做没做
local function chainItems(list, lo, hi, cur, gate)
    local out = {}
    local fac = faction()
    for _, c in ipairs(list or {}) do
        local rec = c.rec and c.rec[fac]
        if rec or not gate then
            local _, n, total = SC.Progress(c, fac)
            rec = rec or c.minLv or 1
            local finished = total > 0 and n >= total
            if c.hint then finished = (bagCount(c.item) or 0) > 0 end
            local lv = rec
            if not finished and cur > rec then lv = cur end
            if lv >= lo and lv <= hi and (total > 0 or c.hint or not gate) then
                out[#out + 1] = { lv = lv, kind = "chain", c = c, n = n, total = total, gate = gate, st = finished and "done" or (lv <= cur and "now" or "future") }
            end
        end
    end
    return out
end
function ns.SideChainItems(lo, hi, cur) return chainItems(ns.SideChainsData, lo, hi, cur) end
function ns.GateChainItems(lo, hi, cur) return chainItems(ns.GateChainsData, lo, hi, cur, true) end

-- ---------- 追踪 / 视频 / 地图 公用（追踪小窗和 _Gate 的路线弹框都用）----------
local DOUYIN_ICON = "Interface\\AddOns\\GearInsight_Forever\\media\\ch_douyin"
-- 11-09 用户截图「做的更像按钮一点，抖音也写全吧」：抖音入口统一成按钮（粉边深底 + 悬停变亮 + 按下下沉），文字「抖音 · xx」，宽度跟字走
local function dyButton(parent, h)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetHeight(h or 20)
    if b.SetBackdrop then
        pcall(b.SetBackdrop, b, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b:SetBackdropColor(0.22, 0.05, 0.14, 0.95); b:SetBackdropBorderColor(1, 0.37, 0.66, 0.9)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.37, 0.66, 0.22)
    b.ic = b:CreateTexture(nil, "ARTWORK"); b.ic:SetSize(14, 14); b.ic:SetPoint("LEFT", 5, 0); b.ic:SetTexture(DOUYIN_ICON)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", b.ic, "RIGHT", 4, 0)
    b:SetScript("OnMouseDown", function(self) self.ic:SetPoint("LEFT", 6, -1); self.t:SetPoint("LEFT", self.ic, "RIGHT", 4, 0) end)
    b:SetScript("OnMouseUp", function(self) self.ic:SetPoint("LEFT", 5, 0) end)
    function b.SetLabel(self, s)
        self.t:SetText(L("抖音", "Douyin") .. " · " .. s)
        local w = tonumber(self.t:GetStringWidth()) or 0
        self:SetWidth(math.max(60, math.floor(w + 30)))
    end
    return b
end
SC.DyButton = dyButton

local function ui() ns.db.ui = ns.db.ui or {}; return ns.db.ui end
function SC.TrackerEnabled() return not (ns.db and ns.db.ui and ns.db.ui.scTracker == false) end
-- 11-09 / 11-12 玩家「关了怎么再开」：小窗 × 按角色记（scTrackBy[角色][线]，false = 关、门任务 true = 钉了），设置页总开关 scTracker 账号级。
--   老存档账号级 scTrack 第一次读到时并到当前登录的角色头上。_focus = 多条钉住时小窗显示哪一条
local charKey = ns._CharKey   -- Leveling.lua
local function trackMap()
    local u = ui()
    u.scTrackBy = u.scTrackBy or {}
    local k = charKey()
    if u.scTrack then
        if not u.scTrackBy[k] then u.scTrackBy[k] = u.scTrack end
        u.scTrack = nil
    end
    u.scTrackBy[k] = u.scTrackBy[k] or {}
    return u.scTrackBy[k]
end
-- 设置页勾选 = 总开关开 + 把被 × 关掉的线一起清掉（门任务手动钉的保留）
function SC.SetTrackerEnabled(on)
    local u = ui()
    u.scTracker = on and true or false
    if on then
        local m = trackMap()
        for k, v in pairs(m) do if v == false then m[k] = nil end end
    end
    SC.UpdateTracker()
end
function SC.TrackerAllOn()
    if not SC.TrackerEnabled() then return false end
    for _, v in pairs(trackMap()) do if v == false then return false end end
    return true
end
-- 睡袋：没被 × 关就追踪；门任务：手动钉了才追踪
function SC.Tracking(c)
    if not (c and ns.db) then return false end
    local v = trackMap()[c.key]
    if c.gate then return v == true end
    return v ~= false
end
function SC.SetTracking(c, on)
    if not (c and ns.db) then return end
    local m = trackMap()
    m[c.key] = on and true or false
    if on then m._focus = c.key end   -- 刚钉上的那条直接显示在小窗里
    SC.UpdateTracker()
end
-- 规划行右键 / 弹框按钮：钉上 / 取消（总开关关着时顺手打开）
function SC.TogglePin(c)
    local on = not (SC.Tracking(c) and SC.TrackerEnabled())
    if on and not SC.TrackerEnabled() then SC.SetTrackerEnabled(true) end
    SC.SetTracking(c, on)
    return on
end

local function copyVideo(vd)
    if not (vd and vd.url) then return end
    local W = ns.W or _G.GIWidgets
    if W and W.Copy then W.Copy(vd.url, L("抖音视频链接：复制后发到手机，用抖音打开", "Douyin link - open it on your phone"))
    elseif ns.Print then ns.Print(vd.url) end
end
SC.CopyVideo = copyVideo

local function showStepOnMap(s)
    if not s.map then return end
    local pts = { { s.x, s.y } }
    if s.via then pts = { { s.x, s.y }, { s.via[1], s.via[2] } } end
    if ns.ShowOnMap then ns.ShowOnMap(s.map, pts, L(s.obj, s.objEn)) end
end
SC.ShowStepOnMap = showStepOnMap
-- 「第 N 步 · 地图 (x, y)」；副本里的步没有坐标
function SC.StepWhere(s)
    if s.x and s.y then return string.format("%s (%.1f, %.1f)", L(s.z, s.zEn), s.x, s.y) end
    return L(s.z or "副本内", s.zEn or "Instance")
end

-- ---------- 路线大弹框：11-23 搬进按需加载的 GearInsight_Forever_Gate（GatePop.lua），点了才加载 ----------
local GM = ns.LazyModule and ns.LazyModule({ key = "gate", addon = "GearInsight_Forever_Gate", zh = "任务线路线", en = "Quest line routes",
    what = "任务线路线弹框 / 门任务", whatEn = "Quest line routes / Gate quests" }) or nil
local stub
stub = function(c)
    if GM and GM:Load() and SC.Show ~= stub then return SC.Show(c) end
end
SC.Show = stub

-- ---------- 11-07 全程追踪小窗 ----------
-- 用户「睡袋加一个全追踪的窗口吧，14级开始一直到做完，都能看到…可以展示当前第几步了」：到级、没做完、追踪开着 → 屏幕上钉一个小窗。
-- 11-23 多条钉住（睡袋 + 门任务）：一个小窗显示「焦点」那条，标题右边「‹ 2/3 ›」切换；焦点那条做完自动换下一条，全做完小窗隐藏
local lastN = {}
function SC.TrackList()
    local out = {}
    if not ns.db or not SC.TrackerEnabled() then return out end
    local lv = UnitLevel and tonumber(UnitLevel("player")) or 0
    local fac = faction()
    local function scan(list)
        for _, c in ipairs(list or {}) do
            if lv >= (c.minLv or 1) and not c.hint and SC.Tracking(c) then
                local st, n, total, nextI = SC.Progress(c, fac)
                if c.gate and total > 0 then
                    -- 门任务推进到下一步 / 做完：聊天框说一句
                    local was = lastN[c.key]
                    if was and n > was and ns.Print then
                        if n >= total then ns.Print(string.format(L("门任务完成：%s（已开门：%s）", "Gate quest done: %s (%s unlocked)"), L(c.t, c.tEn), L(c.door, c.doorEn)))
                        else ns.Print(string.format(L("%s：第 %d 步完成，下一步看追踪小窗", "%s: step %d done"), L(c.t, c.tEn), n)) end
                    end
                    lastN[c.key] = n
                end
                if total > 0 and n < total and nextI then out[#out + 1] = { c, st, n, total, nextI } end
            end
        end
    end
    scan(ns.SideChainsData)
    scan(ns.GateChainsData)
    return out
end
-- 现在小窗显示哪条：返回 c, st, n, total, nextI, 第几条, 共几条
function SC.TrackTarget()
    local list = SC.TrackList()
    if #list == 0 then return nil end
    local f, idx = trackMap()._focus, 1
    for i, e in ipairs(list) do if e[1].key == f then idx = i end end
    local e = list[idx]
    return e[1], e[2], e[3], e[4], e[5], idx, #list
end
function SC.FocusStep(d)
    local list = SC.TrackList()
    if #list < 2 then return end
    local _, _, _, _, _, idx = SC.TrackTarget()
    idx = ((idx or 1) - 1 + d) % #list + 1
    trackMap()._focus = list[idx][1].key
    SC.UpdateTracker()
end

local trk
local TW = 260
local function buildTracker()
    local f = CreateFrame("Button", "GearInsightForeverChainTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(TW, 80); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.05, 0.78); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.85)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self._moved = true; self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        ui().scTrackPos = { p or "TOPRIGHT", rp or "TOPRIGHT", math.floor((tonumber(x) or 0) + 0.5), math.floor((tonumber(y) or 0) + 0.5) }
    end)
    f:SetScript("OnClick", function(self)
        if rawget(self, "_moved") then self._moved = false; return end   -- 刚拖完不算点击
        local c = rawget(self, "chain"); if c then SC.Show(c) end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L("任务线追踪", "Quest line tracker"), 1, 0.82, 0)
        GameTooltip:AddLine(L("点击打开完整路线 · 按住拖动 · × 关掉追踪（路线弹框 / 设置页能再打开）· 钉了几条时点「‹ ›」切换", "Click for the full route · drag to move · × stops tracking · ‹ › switches lines"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -6); f.title:SetPoint("RIGHT", -44, 0); f.title:SetJustifyH("LEFT")
    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); xb:SetSize(20, 20); xb:SetPoint("TOPRIGHT", 0, 0)
    xb:SetScript("OnClick", function()   -- × = 关这条线的追踪（只对这个角色）+ 聊天框告诉怎么找回
        local c = rawget(f, "chain"); if not c then return end
        SC.SetTracking(c, false)
        if ns.Print then
            local t = L(c.t, c.tEn)
            ns.Print(c.gate and L("已取消「" .. t .. "」追踪（只对这个角色）：升级规划里右键那一行可以重新钉上", "Unpinned " .. t .. ": right-click its row in the leveling plan to pin it again")
                or L("已关掉「" .. t .. "」追踪小窗（只对这个角色）：右键小地图按钮 →「" .. t .. "追踪」，或设置页勾「睡袋任务线追踪窗」重新打开",
                "Closed the " .. t .. " tracker for this character: right-click the minimap button or tick it in Settings to reopen"))
        end
    end)
    f.x = xb
    f.min = ns.Button(f, "-", 18, 16); f.min:SetPoint("RIGHT", f.x, "LEFT", 0, 0)
    f.min:SetScript("OnClick", function() local u = ui(); u.scTrackMin = not u.scTrackMin; SC.UpdateTracker() end)
    f.cur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.cur:SetWidth(TW - 16); f.cur:SetJustifyH("LEFT")
    f.obj = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.obj:SetWidth(TW - 16); f.obj:SetJustifyH("LEFT")
    f.nxt = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.nxt:SetWidth(TW - 16); f.nxt:SetJustifyH("LEFT")
    f.map = ns.Button(f, L("地图", "Map"), 52, 20)
    f.vid = dyButton(f, 20); f.vid:SetLabel(L("本步视频", "This step")); f.vid:Hide()
    -- 11-07 用户「加上，追踪小窗也显示」：整条任务线的抖音攻略（c.video）一直显示一个「全程攻略」，这一步自己有视频再多一个「本步视频」
    f.gvid = dyButton(f, 20); f.gvid:SetLabel(L("全程攻略", "Full guide")); f.gvid:Hide()
    local pos = ns.db and ns.db.ui and ns.db.ui.scTrackPos
    f:ClearAllPoints()
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -260) end
    f:Hide()
    return f
end

-- 11-12 重构第 1 期：追踪窗放回默认位置（存的位置一起清）
function SC.ResetTrackerPos()
    if ns.db and ns.db.ui then ns.db.ui.scTrackPos = nil end
    if trk then trk:ClearAllPoints(); trk:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -260) end
end

-- 这个角色钉了门任务、门任务数据还没加载 → 静默加载 _Gate（只试一次；HOLD 没进包时 ModHas 为假，不加载）
local gateTried = false
local function gateNeeded()
    if gateTried or ns.GateChainsData or not (ns.ModHas and ns.ModHas("gate", "GateChainsData.lua")) then return end
    for k, v in pairs(trackMap()) do
        if v == true and type(k) == "string" and k:sub(1, 5) == "gate-" then
            gateTried = true
            if GM then GM:Load(nil, true) end
            return
        end
    end
end

function SC.UpdateTracker()
    if not ns.db then return end
    gateNeeded()
    local c, st, n, total, i, idx, cnt = SC.TrackTarget()
    if not c then if trk then trk:Hide() end; return end
    trk = trk or buildTracker()
    SC.tracker = trk
    trk.chain = c
    local steps = c.steps[faction()] or {}
    local s, nx = steps[i], steps[i + 1]
    local mini = ns.db.ui and ns.db.ui.scTrackMin
    trk.title:SetText((c.gate and ("|cffff9933" .. L("门任务：", "Gate: ") .. "|r") or "") .. "|cff33ff99" .. L(c.t, c.tEn) .. "|r  |cffcccccc" .. n .. "/" .. total .. "|r"
        .. (mini and ("  |cffffd100" .. string.format(L("第 %d 步", "Step %d"), i) .. "|r") or ""))
    trk.min:SetText(mini and "+" or "-")
    -- 11-23 多条钉住时的「‹ 2/3 ›」（第一次用到才建，只钉一条时不占内存）
    local many = (cnt or 1) > 1
    if many and not rawget(trk, "nx") then
        trk.nx = ns.Button(trk, ">", 16, 16); trk.nx:SetPoint("RIGHT", trk.min, "LEFT", -2, 0); trk.nx:SetScript("OnClick", function() SC.FocusStep(1) end)
        trk.idx = trk:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); trk.idx:SetPoint("RIGHT", trk.nx, "LEFT", -2, 0)
        trk.pv = ns.Button(trk, "<", 16, 16); trk.pv:SetPoint("RIGHT", trk.idx, "LEFT", -2, 0); trk.pv:SetScript("OnClick", function() SC.FocusStep(-1) end)
    end
    if rawget(trk, "nx") then
        trk.idx:SetText(many and (idx .. "/" .. cnt) or "")
        if many then trk.pv:Show(); trk.nx:Show() else trk.pv:Hide(); trk.nx:Hide() end
    end
    trk.title:SetPoint("RIGHT", many and -100 or -44, 0)
    local h = 26
    if mini or not s then
        trk.cur:Hide(); trk.obj:Hide(); trk.nxt:Hide(); trk.map:Hide(); trk.vid:Hide(); trk.gvid:Hide()
    else
        trk.cur:SetText(ns.EnSafe("|cffffd100" .. string.format(L("第 %d 步", "Step %d"), i) .. "|r · " .. SC.StepWhere(s)))
        trk.cur:ClearAllPoints(); trk.cur:SetPoint("TOPLEFT", 8, -h); trk.cur:Show()
        h = h + (tonumber(trk.cur:GetStringHeight()) or 12) + 3
        local need = SC.NeedText(s)
        trk.obj:SetText(ns.EnSafe(L(s.obj, s.objEn) .. (need and ("\n" .. need) or "")))
        trk.obj:ClearAllPoints(); trk.obj:SetPoint("TOPLEFT", 8, -h); trk.obj:Show()
        h = h + (tonumber(trk.obj:GetStringHeight()) or 12) + 4
        local anchor, used = nil, 8
        if s.map then   -- 副本里的步没有坐标：不给「地图」
            trk.map:ClearAllPoints(); trk.map:SetPoint("TOPLEFT", 8, -h); trk.map:Show()
            trk.map:SetScript("OnClick", function() showStepOnMap(s) end)
            anchor, used = trk.map, 8 + (tonumber(trk.map:GetWidth()) or 52)
        else trk.map:Hide() end
        local function place(b, w)
            b:ClearAllPoints()
            if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", 8, -h) end
            b:Show(); anchor = b; used = used + 8 + w
        end
        local vd = s.video
        if vd and vd.url then
            place(trk.vid, tonumber(trk.vid:GetWidth()) or 90)
            trk.vid:SetScript("OnClick", function() copyVideo(vd) end)
        else trk.vid:Hide() end
        local cv = c.video
        if cv and cv.url then
            local w = tonumber(trk.gvid:GetWidth()) or 90
            if anchor and used + 8 + w > TW - 8 then   -- 一行放不下（本步 + 全程都有）→ 换到下一行
                h = h + 24; anchor = nil
            end
            place(trk.gvid, w)
            trk.gvid:SetScript("OnClick", function() copyVideo(cv) end)
        else trk.gvid:Hide() end
        if anchor then h = h + 24 end
        if nx then
            trk.nxt:SetText(ns.EnSafe(string.format(L("下一步：%s · %s", "Next: %s - %s"), L(nx.z, nx.zEn), L(nx.obj, nx.objEn))))
        else
            trk.nxt:SetText(c.finalTxt and ns.EnSafe(L("下一步：", "Next: ") .. L(c.finalTxt, c.finalTxtEn)) or L("下一步：交任务拿睡袋", "Next: turn in for the bag"))
        end
        trk.nxt:ClearAllPoints(); trk.nxt:SetPoint("TOPLEFT", 8, -h); trk.nxt:Show()
        h = h + (tonumber(trk.nxt:GetStringHeight()) or 12) + 4
    end
    trk:SetHeight(h + 6)
    trk:Show()
end

do
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
                         "BAG_UPDATE_DELAYED", "BAG_UPDATE", "NEUTRAL_FACTION_SELECT_RESULT" }) do
        local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e)
        if valid then pcall(ev.RegisterEvent, ev, e) end
    end
    local pending = false
    ev:SetScript("OnEvent", function()
        if pending then return end   -- 任务日志 / 背包事件一来一大串：0.5 秒内只刷一次
        pending = true
        local function run() pending = false; pcall(SC.UpdateTracker) end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
    end)
    SC._trackerEvent = ev:GetScript("OnEvent")   -- 测试用
end

-- 11-12 重构第 1 期「找得回」：追踪窗以前没有命令 → /gi 睡袋（/gi chain）开 / 关；登记进设置页「窗口与提醒」
function SC.ToggleTracker()
    local on = not SC.TrackerAllOn()
    SC.SetTrackerEnabled(on)
    if ns.Print then
        local C = ns.SlashHint or "/gif"
        ns.Print(on and L("任务线追踪窗已打开：等级到了、任务线没做完时会钉在屏幕上（再输一次 " .. C .. " 睡袋 关闭）",
                "Quest line tracker on: it shows while a quest line is in progress (" .. C .. " chain again to turn off)")
            or L("任务线追踪窗已关闭：输入 " .. C .. " 睡袋，或设置页「窗口与提醒」重新打开",
                "Quest line tracker off: type " .. C .. " chain or use Settings > Windows & alerts to turn it back on"))
    end
    return on
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash["睡袋"] = function() SC.ToggleTracker() end
ns.ExtraSlash.chain = ns.ExtraSlash["睡袋"]

ns.RegisterWindow({ key = "chainTracker", order = 20, title = function() return L("任务线追踪窗（睡袋 / 门任务）", "Quest line tracker") end,
    state = function()
        if trk and trk:IsShown() then return L("显示中", "Shown") end
        if not SC.TrackerEnabled() then return L("已关闭", "Closed") end
        if not SC.TrackerAllOn() then return L("有任务线被 × 关掉了", "Some lines were closed") end
        return L("已开（现在没有要追踪的任务线）", "On (nothing to track right now)")
    end,
    actions = function()
        local on = SC.TrackerAllOn()
        return {
            { text = on and L("关闭", "Hide") or L("打开", "Show"), fn = function() SC.SetTrackerEnabled(not on) end },
            { text = L("重置位置", "Reset position"), fn = function() SC.ResetTrackerPos() end },
        }
    end })
