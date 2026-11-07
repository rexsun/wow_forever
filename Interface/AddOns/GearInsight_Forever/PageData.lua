-- 设置页（10-17 用户「公测数据这个里面都改造成设置吧，用齿轮标志」+ 截图「都没有用了，删了」）
--   原来的记录条数 / 导出数据 / 战绩卡二维码 / 「记录公测数据」勾全部拿掉；这页只放开关。
--   导出还在命令里：/gi data（ns.ExportAll）、/gi card；记录照旧默认开，/gi data off 关。
--   页 key 仍叫 "data"（老存档记住的页、/gi 跳页都不用改）。
-- 插件不联网：导出串 / 二维码是唯一出口；不记角色名、服务器名
local _, ns = ...

local page

-- 依次弹导出框：公测数据 → 掉落；最后一步的确认键清掉这次导出过的
--   ⛔两种串别拼进一个框：网站粘贴框一次只认一种前缀，同时带两种时只收掉落那段
local function exportAll()
    local steps = {}
    local s1, nd, nl = ns.StatsExportString()
    if s1 then
        steps[#steps + 1] = { s = s1, title = ns.L("① 公测数据（死亡 ", "Beta data (deaths ") .. nd .. ns.L(" · 升级 ", ", levels ") .. nl .. ns.L("）", ")"),
            mark = function() ns.db.deathsPending, ns.db.lvlsPending = #ns.db.deaths, #ns.db.lvls end,
            clear = ns.ClearExportedStats }
    end
    local s2, n2 = ns.LootExportString()
    if s2 then
        steps[#steps + 1] = { s = s2, title = ns.L("② 掉落记录（", "Drops (") .. n2 .. ns.L(" 条）", ")"),
            mark = function() ns.db.lootPending = #ns.db.loot end, clear = ns.ClearExportedLoot }
    end
    if #steps == 0 then ns.Print(ns.L("还没有可导出的数据", "Nothing to export yet")); return end
    local hint = ns.L(ns.UPLOAD_HINT_ZH, ns.UPLOAD_HINT_EN)
    local function show(i)
        local st = steps[i]
        st.mark()
        local last = (i == #steps)
        ns.ShowBox(st.title, hint, ns.UploadURL(st.s), function()
            if last then
                for _, x in ipairs(steps) do x.clear() end
            else
                C_Timer.After(0.05, function() show(i + 1) end)
            end
        end, last and ns.L("已贴好，清掉已导出", "Pasted, clear exported") or ns.L("已贴好，下一段 →", "Pasted, next →"))
    end
    show(1)
end
ns.ExportAll = exportAll

local function check(p, text, x, y, get, set)
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(24, 24); c:SetPoint("TOPLEFT", x, y)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(text)
    c.text = fs
    c:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if page then page.refresh() end   -- 单选组：点一个，同组其他的跟着刷
    end)
    c.get = get
    return c
end

local function section(p, text, y)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 12, y); fs:SetText(text)
    local ln = p:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(1, 0.82, 0, 0.18)
    ln:SetPoint("LEFT", fs, "RIGHT", 8, 0); ln:SetPoint("RIGHT", p, "RIGHT", -12, 0); ln:SetHeight(1)
    return fs
end

-- 10-18 公会 / 组队拆成按需加载的子插件：它们的开关画在一块单独的区域里，模块加载状态一变（点了右侧页签）就重画这块
local function modSig() return tostring(ns.GuildChatLevel ~= nil) .. tostring(ns.LevelShare ~= nil) .. tostring(ns.LevelMute ~= nil) .. tostring(ns.QM ~= nil) end

local function drawMods(p)
    if rawget(p, "modBox") then p.modBox:Hide() end
    local host = rawget(p, "body") or p   -- 11-06 设置页可滚动：画在滚动内容里
    local box = CreateFrame("Frame", nil, host)
    box:SetPoint("TOPLEFT", 0, rawget(p, "modY") or -110); box:SetPoint("RIGHT", host, "RIGHT", 0, 0); box:SetHeight(300)
    p.modBox, p.modChecks, p.modSigNow = box, {}, modSig()
    local function add(c) p.modChecks[#p.modChecks + 1] = c; return c end
    local y = 0
    local function notLoaded(key, zh, en)
        if not (ns.ModuleAvailable and ns.ModuleAvailable(key)) then return end
        local fs = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", 16, y); fs:SetPoint("RIGHT", box, "RIGHT", -12, 0); fs:SetJustifyH("LEFT")
        fs:SetText(string.format(ns.L("%s模块还没加载（默认不加载）：点右侧「%s」页签后，这里出现它的设置", "The %s module isn't loaded yet: open the %s tab on the right and its settings appear here"),
            ns.L(zh, en), ns.L(zh, en)))
        y = y - 22
    end

    -- 公会（GuildChatLevel / LevelShare）：10-19 用户「拿到主插件，不要放子插件了」搬回主插件 → 登录就有，这两项一直出
    local GCL, LS, LM = ns.GuildChatLevel, ns.LevelShare, ns.LevelMute
    if GCL and GCL.Paused then GCL = nil end   -- 10-25 0.5.5：公会频道等级暂停（换聊天框 AddMessage 污染暴雪聊天，见 GuildChatLevel.lua），开关不出
    if GCL or LS or LM then
        section(box, ns.L("公会", "Guild"), y); y = y - 24
        if GCL then
            add(check(box, ns.L("公会频道消息前显示说话人的当前等级", "Show the speaker's level in guild chat"), 14, y,
                function() return GCL.Enabled() end, function(v) GCL.SetEnabled(v) end))
            y = y - 30
            if GCL.ZoneEnabled then   -- 11-06 用户「这里可以加上地区吗」
                add(check(box, ns.L("等级后面再加上所在地区（[24·贫瘠之地]）", "Also show their zone ([24·Barrens])"), 34, y,
                    function() return GCL.ZoneEnabled() end, function(v) GCL.SetZoneEnabled(v) end))
                y = y - 30
            end
        end
        if LS then
            local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("TOPLEFT", 16, y)
            fs:SetText(ns.L("升级播报（发到公会频道，6 级起）", "Level-up shout (guild chat, from level 6)")); y = y - 20
            local modes = {
                { "off", ns.L("关", "Off") }, { "ask", ns.L("逢5级发，其他弹框问", "Every 5 auto, ask others") },
                { "five", ns.L("每 5 级", "Every 5 levels") }, { "milestone", ns.L("只在 10·20·30·40·50·60 级", "Milestones only") },
            }
            local x = 14
            for _, m in ipairs(modes) do
                local key = m[1]
                -- 11-06 五档放不下一行：估算宽度，超出就换行
                local est = 30 + math.max(60, #m[2] * 5) + 18
                if x > 14 and x + est > 630 then x, y = 14, y - 26 end
                local c = add(check(box, m[2], x, y,
                    function() return (ns.db.lvlShare or "ask") == key end,
                    function() LS.SetMode(key) end))
                x = x + 30 + math.max(60, (c.text:GetStringWidth() or 60)) + 18
            end
            y = y - 30
        end
        if LM then   -- 10-26 玩家「公会里全是各家插件升级提醒」
            add(check(box, ns.L("屏蔽别人的升级 / 入会欢迎播报（各家插件在公会 / 队伍里刷的「升到 N 级」「欢迎 XX 加入」）", "Hide other players' level-up / guild-welcome shouts (addon spam in guild / group chat)"), 14, y,
                function() return LM.Enabled() end, function(v) LM.SetEnabled(v) end))
            y = y - 30
        end
        local GL = ns.GuildChatLevel
        if GL and GL.SetReport then   -- 11-06 直播「公会频道定时通报」：默认关（全会都开会刷屏），会长 / 主播自己开
            add(check(box, ns.L("每 10 分钟在公会频道通报人数 / 在线（招人用，默认关；会长自己开）", "Post guild size / online to guild chat every 10 min (recruiting; off by default)"), 14, y,
                function() return GL.ReportOn() end, function(v) GL.SetReport(v) end))
            y = y - 30
        end
        if ns.InviteMenu and ns.InviteMenu.Enabled then   -- 11-06 用户「这些都是设置，有设置，默认打开」
            add(check(box, ns.L("右键玩家菜单里加「邀请入会」", "Add \"Invite to guild\" to the player right-click menu"), 14, y,
                function() return ns.InviteMenu.Enabled() end, function(v) ns.InviteMenu.SetEnabled(v) end))
            y = y - 30
        end
        if ns.PvPShout then   -- 11-06 野外荣誉击杀 / 被杀报公会；每项一个开关 + 「最多多久报一次」（1 / 5 / 10 / 30 分钟，默认 5）
            local PSh = ns.PvPShout
            local rows = {
                { "kill", ns.L("野外荣誉击杀弹炫耀框（公会 / 小队 / 团队，写出对方阵营 / 等级 / 种族 / 职业 / 名字和坐标）", "Offer to show off world honorable kills (guild / party / raid; victim's faction / level / race / class / name and map pin)") },
                { "death", ns.L("野外被玩家击杀弹求助框（公会 / 小队 / 团队，写出对方阵营 / 等级 / 种族 / 职业 / 名字和坐标）", "Ask for help when killed by a player in the world (guild / party / raid; killer's faction / level / race / class / name and map pin)") },
            }
            for _, r in ipairs(rows) do
                local kind = r[1]
                add(check(box, r[2], 14, y, function() return PSh.On(kind) end, function(v) PSh.Set(kind, v) end))
                y = y - 26
                local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("TOPLEFT", 36, y - 4)
                fs:SetText(ns.L("最多多久报一次：", "At most once per:"))
                local x = 36 + math.max(90, (fs.GetStringWidth and fs:GetStringWidth() or 90)) + 8
                for _, sec in ipairs(PSh.CD_CHOICES or { 300 }) do
                    local c = add(check(box, ns.L((sec / 60) .. " 分钟", (sec / 60) .. " min"), x, y,
                        function() return PSh.GetCD(kind) == sec end, function() PSh.SetCD(kind, sec) end))
                    x = x + 30 + math.max(40, (c.text and c.text.GetStringWidth and c.text:GetStringWidth() or 40)) + 10
                end
                y = y - 30
            end
        end
    end   -- 两个都没有（只可能是被 HOLD 剔掉）= 整栏不出；⛔别再提示「点公会页签后出现」，它们已不在公会子插件里

    local QM = ns.QM
    section(box, ns.L("组队", "Group up"), y); y = y - 24
    if ns.GroupAutoLoad and ns.ModuleAvailable and ns.ModuleAvailable("group") then   -- 10-18 组队默认登录就加载
        add(check(box, ns.L("登录时加载组队模块（不加载 = 附近的人看不到你的任务进度）", "Load the group module at login (otherwise nearby players can't see your quests)"), 14, y,
            function() return ns.GroupAutoLoad() end, function(v) ns.db.ui = ns.db.ui or {}; ns.db.ui.groupLazy = (not v) or nil; if v and ns.PerfGuard then ns.PerfGuard.UserOpened() end end))
        y = y - 28
    end
    if QM then
        add(check(box, ns.L("和附近玩家共享任务进度（组队页「附近任务」靠它）", "Share quest progress with nearby players"), 14, y,
            function() return not (ns.db.qm and ns.db.qm.share == false) end, function(v) QM.SetSharing(v) end))
        y = y - 28
        -- 10-18 觉得卡的玩家能在这里关，不用去翻命令 / 删插件（组队抽屉「身边玩家」标题右边也有同一个勾）
        if QM.AutoPlatesOn then
            add(check(box, ns.L("打开组队窗口时自动开友方姓名板（认出身边没装插件的人；觉得卡可以先关掉）", "Auto friendly nameplates while the group window is open (try off if it feels laggy)"), 14, y,
                function() return QM.AutoPlatesOn() end, function(v) QM.SetAutoPlates(v) end))
            y = y - 28
        end
        if QM.Thanks then
            add(check(box, ns.L("队伍解散后提示向队友道谢", "Offer to thank teammates when a group ends"), 14, y,
                function() return QM.Thanks.On() end, function(v) QM.Thanks.Set(v) end))
            y = y - 28
        end
        if QM.AutoFFAOn and QM.SetAutoFFA then   -- 11-06 用户「这些都是设置，有设置，默认打开」
            add(check(box, ns.L("用组队工具组的队自动改成自由拾取（副本里不改）", "Groups formed with Group up switch to free-for-all loot (not in dungeons)"), 14, y,
                function() return QM.AutoFFAOn() end, function(v) QM.SetAutoFFA(v) end))
            y = y - 28
        end
    else
        y = y + 2
        notLoaded("group", "组队", "Group up")
    end
    box:SetHeight(math.max(20, -y + 10))
    if host ~= p and host.SetHeight then host:SetHeight(-(rawget(p, "modY") or -110) - y + 16) end   -- 滚动内容总高
end

local function refresh()
    if not page then return end
    if rawget(page, "modY") and rawget(page, "modSigNow") ~= modSig() then drawMods(page) end
    for _, c in ipairs(page.checks) do c:SetChecked(c.get() and true or false) end
    for _, c in ipairs(rawget(page, "modChecks") or {}) do c:SetChecked(c.get() and true or false) end
end

local function build(p)
    page = p
    p.refresh = refresh
    -- 10-30 四端统一用户规模事实陈述（插件内只写事实，不带任何引流/渠道字样）
    -- 10-31 改成本服自己的下载数（CurseForge + 新手盒子 + 网易 DD + 自己站点合计，见网站 brand_stats.json games.*）；原先写的 24 万是正式服 CF 单一项目，日活是小程序全端，都不是本服的
    ns.PageHeader(p, ns.L("设置", "Settings"),
        ns.L("无限版插件累计下载 6.7 万+ 次", "67K+ downloads of the Forever addon"))
    -- 11-06 公会栏加了邀请入会 / 野外击杀播报（开关 + 间隔）后整页约 720 高，内容区只有 474 → 设置页改成可滚动（组队那栏原来就会被切掉一截）
    local _, body = ns.Scroll(p, 0, -46, 646, 474 - 46 - 6)
    p.body = body
    p.checks = {}
    local function add(c) p.checks[#p.checks + 1] = c; return c end
    local y = -4

    section(body, ns.L("界面", "Interface"), y); y = y - 24
    add(check(body, ns.L("显示小地图按钮", "Show minimap button"), 14, y,
        function() return not (ns.db.minimap and ns.db.minimap.hide) end, function(v) ns.SetMinimapShown(v) end))
    y = y - 30
    -- 11-06 角色面板当前等级 BiS 角标（BisCorner.lua，HOLD）：默认开
    local BCo = ns.BisCorner
    if BCo then
        add(check(body, ns.L("角色面板装备格角上显示当前等级推荐装备（悬停看来源，点击指引获取）", "Show the current-level pick on character panel slots (hover for source, click for directions)"), 14, y,
            function() return BCo.Enabled() end, function(v) BCo.SetEnabled(v) end))
        y = y - 30
    end

    -- 11-07 用户「睡袋加一个全追踪的窗口吧，14级开始一直到做完」：追踪小窗总开关（默认开）
    local SCh = ns.SideChains
    if SCh and SCh.TrackerEnabled then
        add(check(body, ns.L("睡袋任务线追踪窗（14 级起钉在屏幕上显示当前第几步，做完自动消失）", "Sleeping bag quest line tracker (pinned from level 14 until done)"), 14, y,
            function() return SCh.TrackerEnabled() end, function(v) SCh.SetTrackerEnabled(v) end))
        y = y - 30
    end

    -- 10-18 卡顿自查（Perf.lua，HOLD）：玩家觉得卡 → 一键测，用大白话告诉他是谁卡的，别直接把插件删了
    if ns.Perf and ns.Perf.Plates then
        local b = ns.Button(body, ns.L("卡顿自查（约 2 分钟）", "Lag check (~2 min)"), 150, 22, function() ns.Perf.Plates() end)
        b:SetPoint("TOPLEFT", 18, y)
        -- 10-23 用户截图「悬停没TOOLTIPS」：右边那行「上次：…（悬停看全部）」是纯文字，悬停没反应 → 按钮和这行共用一份提示
        local function perfTip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L("卡顿自查", "Lag check"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("站着别动约 2 分钟：自动切换几种姓名板设置各测一遍，测完全部还原，然后告诉你卡在哪（GearInsight 自己占多少、友方姓名板有没有影响、哪个插件最占时间）。进战斗会自动停。",
                "Stand still for ~2 minutes: tries a few nameplate settings, restores them all, then tells you what is slow (GearInsight itself, friendly nameplates, the heaviest addons). Stops if you enter combat."), 1, 1, 1, true)
            local last = ns.db.perfPlates and ns.db.perfPlates[#ns.db.perfPlates]
            if last and last.verdict then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.L("上次自查（", "Last check (") .. (last.at or "") .. ns.L("）：", "):"), 1, 0.82, 0)
                for _, v in ipairs(last.verdict) do GameTooltip:AddLine(ns.L(v[1], v[2]), 0.85, 0.85, 0.85, true) end
            end
            GameTooltip:Show()
        end
        b:SetScript("OnEnter", perfTip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", b, "RIGHT", 10, 0); fs:SetPoint("RIGHT", body, "RIGHT", -12, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        p.perfLast = fs
        local hit = CreateFrame("Frame", nil, body)
        hit:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 4); hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, -4)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", perfTip)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.perfLastHit = hit
        ns.RefreshPerfVerdict = function()
            local last = ns.db.perfPlates and ns.db.perfPlates[#ns.db.perfPlates]
            local first = last and last.verdict and last.verdict[2] or (last and last.verdict and last.verdict[1])
            fs:SetText(first and ("|cff999999" .. ns.L("上次：", "Last: ") .. "|r" .. ns.L(first[1], first[2]) .. "|cff777777" .. ns.L("（悬停看全部）", " (hover for all)") .. "|r")
                or ("|cff777777" .. ns.L("觉得卡？点这里测一下是不是 GearInsight 的问题", "Feels laggy? Check whether GearInsight is the cause") .. "|r"))
        end
        ns.RefreshPerfVerdict()
        y = y - 30
    end

    -- 10-22 自动卡顿检测（PerfGuard.lua，HOLD）
    local PG = ns.PerfGuard
    if PG then
        local c = add(check(body, ns.L("自动检测卡顿（如果是组队引起的，自动关掉组队）", "Auto lag detection (turns Group off if Group is the cause)"), 14, y,
            function() return PG.On() end, function(v) PG.Set(v) end))
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L("自动检测卡顿", "Auto lag detection"), 1, 0.82, 0)
            GameTooltip:AddLine(ns.L("一直量帧率：连续卡 30 秒，先把组队暂停 30 秒对照，明显变顺才关掉组队，没变顺就原样恢复。每次卡顿都记日志（/gi perf log 查看）。",
                "Watches frame times: after 30s of lag, pauses Group for 30s; turns it off only if that clearly helps, otherwise resumes. Every lag event is logged (/gi perf log)."), 1, 1, 1, true)
            local line = PG.LastLine()
            if line then GameTooltip:AddLine(" "); GameTooltip:AddLine(ns.L("最近一次：", "Last: ") .. line, 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - 30
    end

    -- 10-17 官方冷却管理器印快捷键（KeysCdm.lua，HOLD）
    local KC = ns.KeysCdm
    if KC then
        section(body, ns.L("键位", "Keys"), y); y = y - 24
        add(check(body, ns.L("官方冷却管理器图标上显示快捷键", "Show keybinds on the Cooldown Manager"), 14, y,
            function() return KC.Enabled() end, function(v) KC.SetEnabled(v) end))
        y = y - 30
    end

    p.modY = y
    drawMods(p)
end

ns.RegisterPage({ key = "data", order = 4, title = ns.L("设置", "Settings"), icon = "Interface\\Icons\\INV_Misc_Gear_01",
    build = build, refresh = refresh })
