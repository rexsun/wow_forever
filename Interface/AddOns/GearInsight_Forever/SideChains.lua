-- HOLD：特殊任务线并进升级规划（10-18 用户转抖音「魔兽无限睡袋任务路线流程」：「把这个安排到升级规划，三端同步」）。
--   数据 SideChainsData.lua ← scripts/forever_side_chains.py（网站 / 小程序导出同一份）。
--   升级规划「地图待办」里：到推荐等级（按阵营）出一行；做完的步骤按任务 ID 查 C_QuestLog.IsQuestFlaggedCompleted 自动打勾。
--   点这一行 = 弹框：效果 / 推荐等级 / 逐步（地图 · 坐标 · 点什么 · 怎么走 · 对应任务）+ 每步「地图」按钮标点（ns.ShowOnMap）+ 奖励 + 避坑。
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

-- 每一步状态：done（这步交的任务已完成，或接到的下一个任务已在日志 / 已完成）· next（第一个没做的）· todo
function SC.Progress(c, fac)
    local steps = c.steps[fac or faction()] or {}
    local st, n, nextI = {}, 0, nil
    for i, s in ipairs(steps) do
        local d = (s.done and questDone(s.done)) or (s.start and s.start ~= s.done and (onQuest(s.start) or questDone(s.start)))
        st[i] = d and "done" or "todo"
        if d then n = n + 1 end
    end
    -- 后面的步做了，前面的一定也做了（任务线是串的；有的步只看「接没接」）
    local last = 0
    for i = #st, 1, -1 do if st[i] == "done" then last = i; break end end
    for i = 1, last do if st[i] ~= "done" then st[i] = "done"; n = n + 1 end end
    -- 11-07 用户截图「睡袋任务咋没了，做到这步」：第 6 步的任务一拿到信使背包就被游戏标成完成 → 7 步全打勾、任务线判成做完、
    --   从升级规划里消失，其实还差交任务。奖励物品（c.item）不在背包里就不算做完：最后一步留着当「下一步」
    if #steps > 0 and n >= #steps and c.item and GetItemCount then
        local ok, cnt = pcall(GetItemCount, c.item, true)
        if ok and type(cnt) == "number" and cnt == 0 then
            st[#steps] = "todo"; n = #steps - 1
        end
    end
    for i = 1, #st do if st[i] ~= "done" then nextI = i; st[i] = "next"; break end end
    return st, n, #steps, nextI
end

-- 升级规划用：推荐等级（按阵营）那一级出一行；没做完且已经过了推荐等级 → 挪到当前等级（别让它掉进「已过去」）
function ns.SideChainItems(lo, hi, cur)
    local out = {}
    local fac = faction()
    for _, c in ipairs(ns.SideChainsData or {}) do
        local _, n, total = SC.Progress(c, fac)
        local rec = (c.rec and c.rec[fac]) or c.minLv or 1
        local finished = total > 0 and n >= total
        local lv = rec
        if not finished and cur > rec then lv = cur end
        if lv >= lo and lv <= hi then
            out[#out + 1] = { lv = lv, kind = "chain", c = c, n = n, total = total, st = finished and "done" or (lv <= cur and "now" or "future") }
        end
    end
    return out
end

-- ---------- 11-07 追踪 / 视频 / 地图 公用（弹框和追踪小窗都用）----------
local DOUYIN_ICON = "Interface\\AddOns\\GearInsight_Forever\\media\\ch_douyin"

local function ui() ns.db.ui = ns.db.ui or {}; return ns.db.ui end
function SC.TrackerEnabled() return not (ns.db and ns.db.ui and ns.db.ui.scTracker == false) end
function SC.SetTrackerEnabled(on) ui().scTracker = on and true or false; SC.UpdateTracker() end
function SC.Tracking(c)
    if not (c and ns.db) then return false end
    local t = ns.db.ui and ns.db.ui.scTrack
    return not (t and t[c.key] == false)
end
function SC.SetTracking(c, on)
    if not (c and ns.db) then return end
    local u = ui(); u.scTrack = u.scTrack or {}
    u.scTrack[c.key] = on and true or false
    SC.UpdateTracker()
end

local function copyVideo(vd)
    if not (vd and vd.url) then return end
    local W = ns.W or _G.GIWidgets
    if W and W.Copy then W.Copy(vd.url, L("抖音视频链接：复制后发到手机，用抖音打开", "Douyin link - open it on your phone"))
    elseif ns.Print then ns.Print(vd.url) end
end
SC.CopyVideo = copyVideo

local function showStepOnMap(s)
    local pts = { { s.x, s.y } }
    if s.via then pts = { { s.x, s.y }, { s.via[1], s.via[2] } } end
    if ns.ShowOnMap then ns.ShowOnMap(s.map, pts, L(s.obj, s.objEn)) end
end
SC.ShowStepOnMap = showStepOnMap

-- ---------- 弹框 ----------
local pop
local function buildPop()
    local f = CreateFrame("Frame", "GearInsightForeverSideChain", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(620, 470); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.04, 0.045, 0.06, 0.97); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverSideChain") end   -- ESC 关
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOPLEFT", 14, -12); f.title:SetPoint("RIGHT", -170, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中被拦 → 直接 Hide
    -- 11-07 「钉到界面上追踪」开关（这条线的追踪；小窗 × 也是关这个）
    f.track = ns.Button(f, L("钉到界面追踪", "Pin tracker"), 124, 22); f.track:SetPoint("TOPRIGHT", -34, -10)
    local sf, c = ns.Scroll(f, 8, -40, 604, 470 - 48)
    f.sf, f.child, f.rows, f.texts = sf, c, {}, {}
    f:Hide()
    return f
end

local function text(i, tpl)
    local t = pop.texts[i]
    if not t then
        t = pop.child:CreateFontString(nil, "OVERLAY", tpl or "GameFontHighlight")
        t:SetJustifyH("LEFT"); t:SetSpacing(3)
        pop.texts[i] = t
    end
    return t
end

local function stepRow(i)
    local r = pop.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pop.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("TOPLEFT", 6, -6)
    r.no = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.no:SetPoint("CENTER", r.ic, "CENTER")
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.t:SetPoint("TOPLEFT", 32, -6); r.t:SetPoint("RIGHT", -78, 0); r.t:SetJustifyH("LEFT")
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -3); r.s:SetPoint("RIGHT", -78, 0)
    r.s:SetJustifyH("LEFT"); r.s:SetSpacing(2)
    r.map = ns.Button(r, L("地图", "Map"), 66, 22); r.map:SetPoint("TOPRIGHT", -6, -6)
    -- 11-07 这一步有视频（step.video）→ 地图按钮下面一个抖音小图标，点了弹复制框
    r.vb = CreateFrame("Button", nil, r); r.vb:SetSize(66, 18); r.vb:SetPoint("TOPRIGHT", r.map, "BOTTOMRIGHT", 0, -3)
    r.vb.ic = r.vb:CreateTexture(nil, "ARTWORK"); r.vb.ic:SetSize(16, 16); r.vb.ic:SetPoint("LEFT", 6, 0); r.vb.ic:SetTexture(DOUYIN_ICON)
    r.vb.t = r.vb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.vb.t:SetPoint("LEFT", r.vb.ic, "RIGHT", 3, 0)
    r.vb.t:SetText("|cffff5ea8" .. L("视频", "Video") .. "|r")
    r.vb:Hide()
    pop.rows[i] = r
    return r
end

function SC.Show(c)
    pop = pop or buildPop()
    SC.pop = pop
    local fac = faction()
    local st, n, total = SC.Progress(c, fac)
    pop.title:SetText("|cff33ff99" .. L("任务线：", "Quest line: ") .. "|r" .. L(c.t, c.tEn) .. "  |cff888888" .. n .. "/" .. total .. "|r")
    pop.track:SetText(SC.Tracking(c) and SC.TrackerEnabled() and L("取消追踪", "Unpin tracker") or L("钉到界面追踪", "Pin tracker"))
    pop.track:SetScript("OnClick", function()
        local on = not (SC.Tracking(c) and SC.TrackerEnabled())
        if on and not SC.TrackerEnabled() then SC.SetTrackerEnabled(true) end
        SC.SetTracking(c, on)
        SC.Show(c)
    end)
    for _, r in ipairs(pop.rows) do r:Hide() end
    for _, t in ipairs(pop.texts) do t:Hide() end
    local y, ti = -4, 0
    local function para(s, tpl, color)
        ti = ti + 1
        local t = text(ti, tpl)
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 6, y); t:SetWidth(580)
        t:SetText(ns.EnSafe((color or "") .. s .. (color and "|r" or ""))); t:Show()
        y = y - (tonumber(t:GetStringHeight()) or 14) - 8
    end
    local rec = (c.rec and c.rec[fac]) or c.minLv
    -- 11-07 用户「加到这里！」「能弄个抖音的标志吗？」：顶上一行视频攻略（抖音图标 + 标题 +「复制链接」，游戏里打不开网页 → 弹复制框）
    if not rawget(pop, "vid") then   -- 框的元表会把不认识的键转去方法表 → rawget
        local v = CreateFrame("Button", nil, pop.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
        v:SetSize(580, 30)
        if v.SetBackdrop then
            pcall(v.SetBackdrop, v, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            v:SetBackdropColor(0.10, 0.06, 0.10, 0.9); v:SetBackdropBorderColor(0.55, 0.25, 0.45, 0.9)
        end
        v.ic = v:CreateTexture(nil, "ARTWORK"); v.ic:SetSize(20, 20); v.ic:SetPoint("LEFT", 6, 0)
        v.ic:SetTexture("Interface\\AddOns\\GearInsight_Forever\\media\\ch_douyin")
        v.t = v:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); v.t:SetPoint("LEFT", v.ic, "RIGHT", 6, 0); v.t:SetPoint("RIGHT", -96, 0); v.t:SetJustifyH("LEFT")
        v.b = ns.Button(v, L("复制链接", "Copy link"), 84, 22); v.b:SetPoint("RIGHT", -4, 0)
        local hl = v:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.4, 0.7, 0.08)
        pop.vid = v
    end
    local vd = c.video
    if vd and vd.url then
        local function copy()
            local W = ns.W or _G.GIWidgets
            if W and W.Copy then W.Copy(vd.url, L("抖音视频链接：复制后发到手机，用抖音打开", "Douyin link - open it on your phone"))
            elseif ns.Print then ns.Print(vd.url) end
        end
        pop.vid.t:SetText("|cffff5ea8" .. L("视频攻略", "Video") .. "|r  " .. L(vd.t, vd.tEn))
        pop.vid:SetScript("OnClick", copy); pop.vid.b:SetScript("OnClick", copy)
        pop.vid:ClearAllPoints(); pop.vid:SetPoint("TOPLEFT", 6, y); pop.vid:Show()
        y = y - 38
    else
        pop.vid:Hide()
    end
    para(L(c.gist, c.gistEn), "GameFontNormal", "|cffffd100")
    for _, e in ipairs(c.effect or {}) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    para(string.format(L("%d 级能接 · 推荐 %d 级（%s）", "Level %d to start · recommended %d (%s)"), c.minLv or 1, rec,
        fac == "Horde" and L("部落", "Horde") or L("联盟", "Alliance")) .. "  |cff888888" .. L(c.recWhy, c.recWhyEn) .. "|r", "GameFontHighlightSmall")
    y = y - 4
    for i, s in ipairs(c.steps[fac] or {}) do
        local r = stepRow(i)
        local done, isNext = st[i] == "done", st[i] == "next"
        r.bg:SetColorTexture(isNext and 0.2 or 1, isNext and 1 or 1, isNext and 0.4 or 1, isNext and 0.10 or 0.04)
        if done then r.ic:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); r.ic:Show(); r.no:SetText("")
        else r.ic:SetTexture(nil); r.no:SetText((isNext and "|cff33ff99" or "|cffffd100") .. i .. "|r") end
        r.t:SetText((done and "|cff808080" or "") .. L(s.z, s.zEn) .. string.format("  (%.1f, %.1f)", s.x, s.y)
            .. "  " .. (done and "" or "|cffffffff") .. L(s.obj, s.objEn) .. "|r")
        local sub = "|cffcccccc" .. L(s.act, s.actEn) .. "|r"
        if s.q then sub = sub .. "\n|cff888888" .. L("任务：", "Quest: ") .. L(s.q, s.qEn) .. "|r" end
        -- 11-05 用户「信息详实」：怎么去 / 奖励 / 危险各一行
        if s.note then sub = sub .. "\n|cffd8c79a" .. L("怎么去：", "Getting there: ") .. L(s.note, s.noteEn) .. "|r" end
        if s.reward then sub = sub .. "\n|cff33ff99" .. L("奖励：", "Reward: ") .. L(s.reward, s.rewardEn) .. "|r" end
        if s.warn then sub = sub .. "\n|cffff7f50" .. L("注意：", "Watch out: ") .. L(s.warn, s.warnEn) .. "|r" end
        r.s:SetText(ns.EnSafe(sub))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", 0, 0)
        r:SetHeight(math.max(44, 12 + (tonumber(r.t:GetStringHeight()) or 14) + 3 + (tonumber(r.s:GetStringHeight()) or 24)))
        -- 11-06 用户截图「睡袋石爪山的坐标不对啊」：游戏标记打目的地，路口放第二个（SC.ShowStepOnMap）
        r.map:SetScript("OnClick", function() showStepOnMap(s) end)
        if s.video and s.video.url then
            r.vb:Show(); r.vb:SetScript("OnClick", function() copyVideo(s.video) end)
            r:SetHeight(math.max(tonumber(r:GetHeight()) or 44, 54))
        else r.vb:Hide() end
        r:Show()
        y = y - (tonumber(r:GetHeight()) or 44) - 4
    end
    y = y - 6
    local rw = {}
    for _, e in ipairs(c.reward or {}) do rw[#rw + 1] = L(e[1], e[2]) end
    para(L("奖励：", "Rewards: ") .. table.concat(rw, L("、", ", ")), "GameFontHighlightSmall", "|cff33ff99")
    for _, o in ipairs(c.optional or {}) do
        para(L("可选任务：", "Optional quest: ") .. L(o.q, o.qEn) .. "（" .. L(o.z, o.zEn) .. "）", "GameFontNormal", "|cffffd100")
        para(L(o.t, o.tEn), "GameFontHighlightSmall")
    end
    para(L("避坑", "Tips"), "GameFontNormal", "|cffffd100")
    for _, e in ipairs(c.tips or {}) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    if c.sources then para(L("资料：", "Sources: ") .. table.concat(c.sources, " · "), "GameFontDisableSmall") end
    pop.child:SetHeight(-y + 6)
    pop:Show()
end

-- ---------- 11-07 全程追踪小窗 ----------
-- 用户「睡袋加一个全追踪的窗口吧，14级开始一直到做完，都能看到，开启追踪以后，钉在界面上，可以展示当前第几步了」：
--   到 c.minLv（14）级、没做完（SC.Progress，含「背包里没睡袋不算做完」）、追踪开着 → 屏幕上钉一个小窗：
--   标题「舒适的睡袋 3/7」+ 最小化 / 关闭（× = 关这条线的追踪）；当前步（第 N 步 · 地图 (x, y) + 点什么 +「地图」）；下一步灰字预告；
--   这一步有视频（step.video）→ 抖音小图标「视频」点了弹复制框；点小窗主体 = 打开完整路线弹框。可拖动，位置存档。
--   开关：全局 ns.db.ui.scTracker（设置页「睡袋任务线追踪窗」，nil = 开）+ 每条线 ns.db.ui.scTrack[key]（弹框按钮 / 规划行右键 / 小窗 ×，nil = 开）
-- 现在该追踪哪条线：到级、没做完、两层开关都开；返回 c, st, n, total, nextI
function SC.TrackTarget()
    if not ns.db or not SC.TrackerEnabled() then return nil end
    local lv = UnitLevel and tonumber(UnitLevel("player")) or 0
    local fac = faction()
    for _, c in ipairs(ns.SideChainsData or {}) do
        if lv >= (c.minLv or 1) and SC.Tracking(c) then
            local st, n, total, nextI = SC.Progress(c, fac)
            if total > 0 and n < total and nextI then return c, st, n, total, nextI end
        end
    end
    return nil
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
        GameTooltip:AddLine(L("点击打开完整路线 · 按住拖动 · × 关掉追踪（路线弹框 / 设置页能再打开）", "Click for the full route · drag to move · × stops tracking"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 8, -6); f.title:SetPoint("RIGHT", -44, 0); f.title:SetJustifyH("LEFT")
    local xb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); xb:SetSize(20, 20); xb:SetPoint("TOPRIGHT", 0, 0)
    xb:SetScript("OnClick", function() local c = rawget(f, "chain"); if c then SC.SetTracking(c, false) end end)   -- × = 关这条线的追踪
    f.x = xb
    f.min = ns.Button(f, "-", 18, 16); f.min:SetPoint("RIGHT", f.x, "LEFT", 0, 0)
    f.min:SetScript("OnClick", function() local u = ui(); u.scTrackMin = not u.scTrackMin; SC.UpdateTracker() end)
    f.cur = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.cur:SetWidth(TW - 16); f.cur:SetJustifyH("LEFT")
    f.obj = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.obj:SetWidth(TW - 16); f.obj:SetJustifyH("LEFT")
    f.nxt = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.nxt:SetWidth(TW - 16); f.nxt:SetJustifyH("LEFT")
    f.map = ns.Button(f, L("地图", "Map"), 52, 18)
    f.vid = CreateFrame("Button", nil, f); f.vid:SetSize(64, 18)
    f.vid.ic = f.vid:CreateTexture(nil, "ARTWORK"); f.vid.ic:SetSize(16, 16); f.vid.ic:SetPoint("LEFT", 0, 0); f.vid.ic:SetTexture(DOUYIN_ICON)
    f.vid.t = f.vid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.vid.t:SetPoint("LEFT", f.vid.ic, "RIGHT", 3, 0)
    f.vid.t:SetText("|cffff5ea8" .. L("视频", "Video") .. "|r")
    -- 11-07 用户「加上，追踪小窗也显示」：整条任务线的抖音攻略（c.video）一直显示一个「全程攻略」，这一步自己有视频再多一个「本步视频」
    f.gvid = CreateFrame("Button", nil, f); f.gvid:SetSize(84, 18)
    f.gvid.ic = f.gvid:CreateTexture(nil, "ARTWORK"); f.gvid.ic:SetSize(16, 16); f.gvid.ic:SetPoint("LEFT", 0, 0); f.gvid.ic:SetTexture(DOUYIN_ICON)
    f.gvid.t = f.gvid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.gvid.t:SetPoint("LEFT", f.gvid.ic, "RIGHT", 3, 0)
    f.gvid.t:SetText("|cffff5ea8" .. L("全程攻略", "Full guide") .. "|r")
    f.gvid:Hide()
    local pos = ns.db and ns.db.ui and ns.db.ui.scTrackPos
    f:ClearAllPoints()
    if type(pos) == "table" and pos[1] then f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -260) end
    f:Hide()
    return f
end

function SC.UpdateTracker()
    if not ns.db then return end
    local c, st, n, total, i = SC.TrackTarget()
    if not c then if trk then trk:Hide() end; return end
    trk = trk or buildTracker()
    SC.tracker = trk
    trk.chain = c
    local fac = faction()
    local steps = c.steps[fac] or {}
    local s, nx = steps[i], steps[i + 1]
    local mini = ns.db.ui and ns.db.ui.scTrackMin
    trk.title:SetText("|cff33ff99" .. L(c.t, c.tEn) .. "|r  |cffcccccc" .. n .. "/" .. total .. "|r"
        .. (mini and ("  |cffffd100" .. string.format(L("第 %d 步", "Step %d"), i) .. "|r") or ""))
    trk.min:SetText(mini and "+" or "-")
    local h = 26
    if mini or not s then
        trk.cur:Hide(); trk.obj:Hide(); trk.nxt:Hide(); trk.map:Hide(); trk.vid:Hide(); trk.gvid:Hide()
    else
        trk.cur:SetText(ns.EnSafe(string.format("|cffffd100" .. L("第 %d 步", "Step %d") .. "|r · %s (%.1f, %.1f)", i, L(s.z, s.zEn), s.x, s.y)))
        trk.cur:ClearAllPoints(); trk.cur:SetPoint("TOPLEFT", 8, -h); trk.cur:Show()
        h = h + (tonumber(trk.cur:GetStringHeight()) or 12) + 3
        trk.obj:SetText(ns.EnSafe(L(s.obj, s.objEn)))
        trk.obj:ClearAllPoints(); trk.obj:SetPoint("TOPLEFT", 8, -h); trk.obj:Show()
        h = h + (tonumber(trk.obj:GetStringHeight()) or 12) + 4
        trk.map:ClearAllPoints(); trk.map:SetPoint("TOPLEFT", 8, -h); trk.map:Show()
        trk.map:SetScript("OnClick", function() showStepOnMap(s) end)
        local vd = s.video
        local anchor = trk.map
        if vd and vd.url then
            trk.vid.t:SetText("|cffff5ea8" .. L("本步视频", "This step") .. "|r"); trk.vid:SetWidth(84)
            trk.vid:ClearAllPoints(); trk.vid:SetPoint("LEFT", trk.map, "RIGHT", 10, 0); trk.vid:Show()
            trk.vid:SetScript("OnClick", function() copyVideo(vd) end)
            anchor = trk.vid
        else trk.vid:Hide() end
        local cv = c.video
        if cv and cv.url then
            trk.gvid:ClearAllPoints(); trk.gvid:SetPoint("LEFT", anchor, "RIGHT", 10, 0); trk.gvid:Show()
            trk.gvid:SetScript("OnClick", function() copyVideo(cv) end)
        else trk.gvid:Hide() end
        h = h + 22
        if nx then
            trk.nxt:SetText(ns.EnSafe(string.format(L("下一步：%s · %s", "Next: %s - %s"), L(nx.z, nx.zEn), L(nx.obj, nx.objEn))))
            trk.nxt:ClearAllPoints(); trk.nxt:SetPoint("TOPLEFT", 8, -h); trk.nxt:Show()
            h = h + (tonumber(trk.nxt:GetStringHeight()) or 12) + 4
        else
            trk.nxt:SetText(L("下一步：交任务拿睡袋", "Next: turn in for the bag")); trk.nxt:ClearAllPoints(); trk.nxt:SetPoint("TOPLEFT", 8, -h); trk.nxt:Show()
            h = h + 16
        end
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

-- 升级规划那一行怎么画（PagePlan.lua 的 kind == "chain" 交给这里）
function ns.SideChainRenderRow(r, it, suffix)
    local c = it.c
    r.ic:SetTexture("Interface\\Icons\\" .. (c.icon or "INV_Misc_Note_01"))
    r.ic:SetDesaturated(it.st == "done")
    r.t:SetText((it.st == "done" and "|cff808080" or "|cffff9933") .. L("任务线：", "Quest line: ") .. L(c.t, c.tEn) .. "|r  |cff888888"
        .. it.n .. "/" .. it.total .. "|r")
    r.s:SetText(L(c.gist, c.gistEn) .. (suffix or ""))
    if r.RegisterForClicks then pcall(r.RegisterForClicks, r, "LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then   -- 11-07 右键 = 钉到界面追踪 / 取消
            local on = not (SC.Tracking(c) and SC.TrackerEnabled())
            if on and not SC.TrackerEnabled() then SC.SetTrackerEnabled(true) end
            SC.SetTracking(c, on)
            if ns.Print then ns.Print(on and L("已钉到界面上追踪（右键再点取消）", "Tracker pinned") or L("已取消追踪", "Tracker unpinned")) end
            return
        end
        SC.Show(c)
    end)
    r.btn:SetText(L("路线", "Route")); r.btn:Show()
    r.btn:SetScript("OnClick", function() SC.Show(c) end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L(c.t, c.tEn), 1, 0.82, 0)
        GameTooltip:AddLine(L(c.gist, c.gistEn), 1, 1, 1, true)
        GameTooltip:AddLine(string.format(L("已做 %d / %d 步 · 点击看逐步路线和坐标", "%d / %d steps done · click for the route"), it.n, it.total), 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(L("右键：钉到界面上追踪 / 取消", "Right-click: pin / unpin the tracker"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
end
