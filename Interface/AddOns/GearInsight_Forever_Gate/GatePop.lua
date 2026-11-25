-- 任务线路线大弹框（11-23 从主插件 SideChains.lua 原样搬来 + 门任务字段；⛔ 这个文件不 HOLD：睡袋的路线弹框也是它，已发布的功能）。
--   主插件 SideChains.lua 的 SC.Show 是个桩：第一次点规划行 / 追踪小窗 / 升级指引按钮时加载这个子插件，这里把 SC.Show 换成真的。
--   门任务多出来的：标题「门任务：」、开什么门、开放日期、钥匙在不在身上、物品步计数（need）、并行任务步（doneAll）、副本内的步（inst，不给「地图」）
local _, ns = ...; ns = _G.GearInsightForever or ns
local SC = ns.SideChains
if not SC then return end
local L = ns.L
local faction, dyButton, copyVideo, showStepOnMap = SC.Faction, SC.DyButton, SC.CopyVideo, SC.ShowStepOnMap

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
    r.vb = dyButton(r, 20); r.vb:SetPoint("TOPRIGHT", r.map, "BOTTOMRIGHT", 0, -3)
    r.vb:SetLabel(L("视频", "Video"))
    r.vb:Hide()
    pop.rows[i] = r
    return r
end

function SC.Show(c)
    pop = pop or buildPop()
    SC.pop = pop
    local fac = faction()
    local st, n, total = SC.Progress(c, fac)
    pop.title:SetText((c.gate and ("|cffff9933" .. L("门任务：", "Gate quest: ")) or ("|cff33ff99" .. L("任务线：", "Quest line: "))) .. "|r" .. L(c.t, c.tEn)
        .. (c.hint and "" or ("  |cff888888" .. n .. "/" .. total .. "|r")))
    pop.track:SetText(SC.Tracking(c) and SC.TrackerEnabled() and L("取消追踪", "Unpin tracker") or L("钉到界面追踪", "Pin tracker"))
    pop.track:SetScript("OnClick", function() SC.TogglePin(c); SC.Show(c) end)
    if c.hint then pop.track:Hide() else pop.track:Show() end
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
        local function copy() copyVideo(vd) end
        pop.vid.t:SetText("|cffff5ea8" .. L("抖音视频攻略", "Douyin guide") .. "|r  " .. L(vd.t, vd.tEn))
        pop.vid:SetScript("OnClick", copy); pop.vid.b:SetScript("OnClick", copy)
        pop.vid:ClearAllPoints(); pop.vid:SetPoint("TOPLEFT", 6, y); pop.vid:Show()
        y = y - 38
    else
        pop.vid:Hide()
    end
    para(L(c.gist, c.gistEn), "GameFontNormal", "|cffffd100")
    -- 11-23 门任务：开什么门 / 开放日期 / 钥匙在不在身上
    if c.door then para(L("开门：", "Unlocks: ") .. L(c.door, c.doorEn) .. ((c.optFac and c.optFac[fac]) and L("（本阵营可选）", " (optional for your faction)") or ""), "GameFontHighlight", "|cffff9933") end
    if c.opens and ns.GateOpensText then para(ns.GateOpensText(c), "GameFontHighlightSmall", "|cffd8c79a") end
    if c.item and c.keyName then
        local have = SC.ItemCount(c.item)
        if have and have > 0 then para(L("身上有「", "You have ") .. L(c.keyName, c.keyNameEn) .. L("」：门已开", " - unlocked"), "GameFontHighlightSmall", "|cff33ff99")
        elseif SC.KeyMissing(c, fac) then para(L("任务已完成，但身上没有「", "Quest done, but no ") .. L(c.keyName, c.keyNameEn) .. L("」（扔了 / 放仓库了？）", " on you"), "GameFontHighlightSmall", "|cffff7f50") end
    end
    if c.hint then para(L("谁掉：", "Drops from: ") .. L(c.src, c.srcEn), "GameFontHighlightSmall") end
    for _, e in ipairs(c.effect or {}) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    para(string.format(L("%d 级能接 · 推荐 %d 级（%s）", "Level %d to start · recommended %d (%s)"), c.minLv or 1, rec or 1,
        fac == "Horde" and L("部落", "Horde") or L("联盟", "Alliance")) .. (c.recWhy and ("  |cff888888" .. L(c.recWhy, c.recWhyEn) .. "|r") or ""), "GameFontHighlightSmall")
    y = y - 4
    for i, s in ipairs((c.steps and c.steps[fac]) or {}) do
        local r = stepRow(i)
        local done, isNext = st[i] == "done", st[i] == "next"
        r.bg:SetColorTexture(isNext and 0.2 or 1, isNext and 1 or 1, isNext and 0.4 or 1, isNext and 0.10 or 0.04)
        if done then r.ic:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); r.ic:Show(); r.no:SetText("")
        else r.ic:SetTexture(nil); r.no:SetText((isNext and "|cff33ff99" or "|cffffd100") .. i .. "|r") end
        r.t:SetText((done and "|cff808080" or "") .. SC.StepWhere(s) .. "  " .. (done and "" or "|cffffffff") .. L(s.obj, s.objEn) .. "|r")
        local sub = s.act and s.act ~= "" and ("|cffcccccc" .. L(s.act, s.actEn) .. "|r") or ""
        local function add(line) sub = (sub ~= "" and (sub .. "\n") or "") .. line end
        if s.q then add("|cff888888" .. L("任务：", "Quest: ") .. L(s.q, s.qEn) .. "|r") end
        local need = SC.NeedText(s)
        if need then add(L("需要：", "Needs: ") .. need) end
        -- 11-05 用户「信息详实」：怎么去 / 奖励 / 危险各一行
        if s.note then add("|cffd8c79a" .. L("怎么去：", "Getting there: ") .. L(s.note, s.noteEn) .. "|r") end
        if s.reward then add("|cff33ff99" .. L("奖励：", "Reward: ") .. L(s.reward, s.rewardEn) .. "|r") end
        if s.warn then add("|cffff7f50" .. L("注意：", "Watch out: ") .. L(s.warn, s.warnEn) .. "|r") end
        r.s:SetText(ns.EnSafe(sub))
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", pop.child, "RIGHT", 0, 0)
        r:SetHeight(math.max(44, 12 + (tonumber(r.t:GetStringHeight()) or 14) + 3 + (tonumber(r.s:GetStringHeight()) or 24)))
        -- 11-06 用户截图「睡袋石爪山的坐标不对啊」：游戏标记打目的地，路口放第二个（SC.ShowStepOnMap）；副本里的步没坐标 → 不给「地图」
        if s.map then r.map:Show(); r.map:SetScript("OnClick", function() showStepOnMap(s) end) else r.map:Hide() end
        if s.video and s.video.url then
            r.vb:Show(); r.vb:SetScript("OnClick", function() copyVideo(s.video) end)
            r:SetHeight(math.max(tonumber(r:GetHeight()) or 44, 54))
        else r.vb:Hide() end
        r:Show()
        y = y - (tonumber(r:GetHeight()) or 44) - 4
    end
    y = y - 6
    if c.reward then
        local rw = {}
        for _, e in ipairs(c.reward) do rw[#rw + 1] = L(e[1], e[2]) end
        para(L("奖励：", "Rewards: ") .. table.concat(rw, L("、", ", ")), "GameFontHighlightSmall", "|cff33ff99")
    end
    for _, o in ipairs(c.optional or {}) do
        para(L("可选任务：", "Optional quest: ") .. L(o.q, o.qEn) .. "（" .. L(o.z, o.zEn) .. "）", "GameFontNormal", "|cffffd100")
        para(L(o.t, o.tEn), "GameFontHighlightSmall")
    end
    if c.tips then
        para(L("避坑", "Tips"), "GameFontNormal", "|cffffd100")
        for _, e in ipairs(c.tips) do para("· " .. L(e[1], e[2]), "GameFontHighlightSmall") end
    end
    if c.sources then para(L("资料：", "Sources: ") .. table.concat(c.sources, " · "), "GameFontDisableSmall") end
    pop.child:SetHeight(-y + 6)
    pop:Show()
end
