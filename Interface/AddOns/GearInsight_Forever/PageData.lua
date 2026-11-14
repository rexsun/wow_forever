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


-- 11-12 界面重构第 2 期「菜单合并 + 设置就近」：设置页从一张 77 项的长页改成 4 个子页：
--   通用（语言 / 窗口大小 / 小地图按钮）· 窗口与提醒（第 1 期的找回中心）· 性能 · 全部设置（索引 + 搜索，点「前往」跳到功能页）。
--   各功能自己的开关搬到功能页右上角「本页设置」（描述表在 Settings.lua，⛔ 存档键不变）；公会 / 组队的在抽屉齿轮里；
--   法师吃喝在组队抽屉第三个子页签（决定 4：总设置页不放它的开关，只在索引里有、能跳过去）。
--   p.checks = 设置页上画出来的全部勾选框（通用 → 性能 → 索引）；p.modChecks = 索引里公会 / 组队那两组（模块加载状态一变就重画）
local SUBS = {
    { key = "general", zh = "通用", en = "General" },
    { key = "windows", zh = "窗口与提醒", en = "Windows" },
    { key = "perf", zh = "性能", en = "Performance" },
    { key = "all", zh = "全部设置", en = "All settings" },
}
local TOC_COLS = 7

-- 「窗口与提醒」：每扇浮窗 / 提醒条一行（名字 · 现在什么状态 · 最多 3 个按钮），内容来自 ns.WindowList()（各模块自己登记，见 Core.lua）
local WIN_BTNS = 3
local function refreshWins(p)
    local rows = rawget(p, "winRows")
    if not rows then return end
    local list = ns.WindowList and ns.WindowList() or {}
    for i, r in ipairs(rows) do
        local w = list[i]
        r.win = w
        if w then
            r.name:SetText(ns.WindowTitle(w))
            local okS, st = true, nil
            if w.state then okS, st = pcall(w.state) end
            r.state:SetText("|cff999999" .. tostring(okS and st or "") .. "|r")
            local okA, acts = false, nil
            if w.actions then okA, acts = pcall(w.actions) end
            r.acts = (okA and type(acts) == "table") and acts or {}
            for j = 1, WIN_BTNS do
                local a = r.acts[j]
                if a then r.btns[j]:SetText(tostring(a.text or "")); r.btns[j]:Show() else r.btns[j]:Hide() end
            end
            r.name:Show(); r.state:Show()
        else
            r.acts = {}
            r.name:Hide(); r.state:Hide()
            for j = 1, WIN_BTNS do r.btns[j]:Hide() end
        end
    end
end

-- 滚动框滚到 y（y 是负数）；滚到哪了记在 page.scrollTo（离线测试看这个）
local function scrollTo(p, sf, y)
    local v = ns._SettingsScrollSF and ns._SettingsScrollSF(sf, y) or 0
    p.scrollTo = v
    return v
end

-- 设置页上所有勾选框按子页顺序收一份（测试 / 别的模块按文字找控件用）
local function collect(p)
    local all, mods = {}, {}
    for _, s in ipairs(SUBS) do
        local b = p.subs and p.subs[s.key] and p.subs[s.key].block
        if b then
            for _, c in ipairs(b.checks or {}) do all[#all + 1] = c end
            for _, c in ipairs(b.modChecks or {}) do mods[#mods + 1] = c end
        end
    end
    p.checks, p.modChecks = all, mods
end

local function selectSub(p, key)
    if not (p.subs and p.subs[key]) then key = "general" end
    for _, s in ipairs(SUBS) do
        local e = p.subs[s.key]
        local on = s.key == key
        e.sf:SetShown(on)
        if ns.SegSelect then ns.SegSelect(e.btn, on) end
    end
    p.sub = key
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.setSub = (key ~= "general") and key or nil
    p.scroll = p.subs[key].sf
end

local function refresh()
    if not page then return end
    for _, s in ipairs(SUBS) do
        local b = page.subs and page.subs[s.key] and page.subs[s.key].block
        if b and (not b.frame or b.sig ~= b:Sig()) then b:Render() end
    end
    collect(page)
    if ns.RefreshSettings then ns.RefreshSettings() end
    refreshWins(page)
    local idx = page.subs and page.subs.all
    if idx and idx.relayoutToc then idx.relayoutToc() end
end

local function build(p)
    page = p
    p.refresh = refresh
    -- 10-30 四端统一用户规模事实陈述（插件内只写事实，不带任何引流/渠道字样）
    -- 10-31 改成本服自己的下载数（CurseForge + 新手盒子 + 网易 DD + 自己站点合计，见网站 brand_stats.json games.*）；原先写的 24 万是正式服 CF 单一项目，日活是小程序全端，都不是本服的
    ns.PageHeader(p, ns.L("设置", "Settings"),
        ns.L("无限版插件累计下载 6.7 万+ 次", "67K+ downloads of the Forever addon"))
    p.subs = {}
    for i, s in ipairs(SUBS) do
        local b = (ns.SegButton or ns.Button)(p, ns.L(s.zh, s.en), 104, 22, function() selectSub(p, s.key); refresh() end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 108, -40)
        local sf, body = ns.Scroll(p, 0, -68, 646, 474 - 68 - 6)
        sf:Hide()
        p.subs[s.key] = { btn = b, sf = sf, body = body }
    end
    local function mkBlock(key, keys, opts)
        local e = p.subs[key]
        opts = opts or {}
        opts.width = opts.width or 630
        local holder = { checks = {}, modChecks = {} }
        opts.onRender = function(b) b.checks, b.modChecks = {}, {}; holder.cur = b end
        opts.onCheck = function(c, it)
            local b = holder.cur
            if not b then return end
            if it.group and it.group.mods then b.modChecks[#b.modChecks + 1] = c else b.checks[#b.checks + 1] = c end
        end
        local prev = opts.onLayout
        opts.onLayout = function(b)
            e.body:SetHeight(-(b.top or 0) + (b.height or 10) + 16)
            if prev then prev(b) end
        end
        e.block = ns.SettingsBlock(e.body, keys, opts)
        return e.block
    end

    -- ① 通用
    mkBlock("general", { "lang", "ui" })

    -- ② 窗口与提醒（第 1 期「找得回」：所有浮窗 / 提醒条集中一处 —— 现在开没开、怎么再打开、位置拖丢了怎么重置）
    do
        local body = p.subs.windows.body
        local y = -4
        local fs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 12, y); fs:SetText(ns.L("窗口与提醒（小窗关了从这里找回）", "Windows & reminders (reopen closed pop-ups here)"))
        y = y - 22
        local tip = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("TOPLEFT", 18, y); tip:SetPoint("RIGHT", body, "RIGHT", -12, 0); tip:SetJustifyH("LEFT")
        tip:SetText(string.format(ns.L("小窗点 × 关掉后都能在这里再打开；位置拖丢了点「重置位置」。命令：%s win", "Reopen any closed pop-up here; \"Reset position\" brings a lost one back. Command: %s win"), ns.SlashHint))
        y = y - 18
        p.winY = 0
        p.winRows = {}
        local list = ns.WindowList and ns.WindowList() or {}
        for i = 1, #list do
            local r = { btns = {}, acts = {} }
            r.name = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.name:SetPoint("TOPLEFT", 18, y - 5); r.name:SetWidth(150); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
            r.state = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.state:SetPoint("TOPLEFT", 172, y - 6); r.state:SetWidth(186); r.state:SetJustifyH("LEFT"); r.state:SetWordWrap(false)
            for j = 1, WIN_BTNS do
                local b = ns.Button(body, "", 86, 20, function()
                    local a = r.acts[j]
                    if a and a.fn then
                        local ok, err = pcall(a.fn)
                        if not ok and ns.Print then ns.Print(tostring(err)) end
                    end
                    if page then page.refresh() end
                end)
                b:SetPoint("TOPLEFT", 362 + (j - 1) * 89, y - 1)
                r.btns[j] = b
            end
            p.winRows[i] = r
            y = y - 24
        end
        body:SetHeight(-y + 16)
        refreshWins(p)
    end

    -- ③ 性能
    mkBlock("perf", { "perf" })
    p.perfLast, p.perfLastHit = p.subs.perf.block.perfLast, p.subs.perf.block.perfLastHit   -- 10-23「上次：…」那行（悬停看全部结论）

    -- ④ 全部设置：搜索框 + 分组目录按钮 + 按功能分组的全部开关（每组标题右边「前往 ›」跳到功能页并展开「本页设置」）
    do
        local e = p.subs.all
        local body = e.body
        local lbl = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", 14, -9); lbl:SetText(ns.L("搜索：", "Search:"))
        local sb = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
        sb:SetSize(300, 20); sb:SetPoint("TOPLEFT", ns.zh and 62 or 70, -6)
        sb:SetAutoFocus(false); sb:SetMaxLetters(40)
        p.search = sb
        local clr = ns.Button(body, ns.L("清空", "Clear"), 60, 20, function() sb:SetText(""); if e.block then e.block:SetFilter("", nil) end end)
        clr:SetPoint("LEFT", sb, "RIGHT", 8, 0)
        local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", clr, "RIGHT", 8, 0); hint:SetText(string.format(ns.L("也可以输入 %s set 关键词", "or type %s set <words>"), ns.SlashHint))
        sb:SetScript("OnTextChanged", function(self)
            if e.block then e.block:SetFilter(self:GetText() or "", nil) end
        end)
        sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- 目录按钮：窗口与提醒（换到那个子页）· 自动私信（只看各功能的自动私信内容）· 每个功能组一个
        local tocDefs = { { key = "_windows", text = function() return ns.L("窗口与提醒", "Windows") end },
            { key = "_whisper", text = function() return ns.L("自动私信", "Whispers") end } }
        for _, g in ipairs(ns._SettingsGroups or {}) do
            tocDefs[#tocDefs + 1] = { key = g.key, text = function() return ns.SettingText(g.short or g.title) end }
        end
        p.tocBtns = {}
        for i, d in ipairs(tocDefs) do
            local b = ns.Button(body, ns.SettingText(d.text), 86, 20, function()
                if d.key == "_windows" then selectSub(p, "windows"); refresh(); return end
                local blk = e.block
                if not blk then return end
                sb:SetText("")
                if d.key == "_whisper" then
                    blk:SetFilter("", (blk.tag ~= "whisper") and "whisper" or nil)
                    scrollTo(p, e.sf, 0)
                    return
                end
                blk:SetFilter("", nil)
                local y = blk.gpos[d.key]
                if y then scrollTo(p, e.sf, y + (blk.top or 0)) end
            end)
            b.def = d
            p.tocBtns[i] = b
        end
        local tocTop = -34
        e.relayoutToc = function()
            local n = 0
            local blk = e.block
            for _, b in ipairs(p.tocBtns) do
                local k = b.def.key
                local ok = k:sub(1, 1) == "_"
                if not ok and blk then
                    local g = ns.SettingsGroup(k)
                    for _, ent in ipairs(blk.entries or {}) do if ent.group == g then ok = true end end
                end
                if ok then
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 12 + (n % TOC_COLS) * 89, tocTop - math.floor(n / TOC_COLS) * 23)
                    b:SetText(ns.SettingText(b.def.text))
                    b:Show()
                    n = n + 1
                else
                    b:Hide()
                end
            end
            local top = tocTop - math.ceil(n / TOC_COLS) * 23 - 6
            if blk and blk.top ~= top then
                blk.top = top
                if blk.frame then blk.frame:ClearAllPoints(); blk.frame:SetPoint("TOPLEFT", 0, top) end
                body:SetHeight(-top + (blk.height or 10) + 16)
            end
            return top
        end
        local top = e.relayoutToc()
        mkBlock("all", function()
            local keys = {}
            for _, g in ipairs(ns._SettingsGroups or {}) do keys[#keys + 1] = g.key end
            return keys
        end, { jump = true, index = true, top = top })
        e.relayoutToc()
    end

    collect(p)
    selectSub(p, (ns.db.ui and ns.db.ui.setSub) or "general")
end

-- 子页切换 + 滚到某项（全部设置 / 跳转用）
local function openData()
    if ns.OpenPage then ns.OpenPage("data") end
    return page
end
function ns.OpenSettingsSub(sub, id)
    local p = openData()
    if not p then return false end
    selectSub(p, sub)
    refresh()
    local e = p.subs[sub]
    if id and e and e.block and e.block.pos[id] then
        scrollTo(p, e.sf, e.block.pos[id] + (e.block.top or 0))
        e.block:Flash(id)
    else
        scrollTo(p, e.sf, 0)
    end
    return true
end
function ns.OpenSettingsSearch(q)
    local p = openData()
    if not p then return false end
    selectSub(p, "all")
    refresh()
    q = tostring(q or "")
    p.search:SetText(q)
    local blk = p.subs.all.block
    blk:SetFilter(q, nil)
    scrollTo(p, p.subs.all.sf, 0)
    return true, blk
end

-- 11-12 界面重构第 1 期：/gi win（/gi 窗口）= 打开设置页「窗口与提醒」；小地图右键菜单同一个入口（第 2 期起是单独的子页）
function ns.OpenWindows()
    local p = openData()
    if not p then return false end
    selectSub(p, "windows")
    refresh()
    scrollTo(p, p.subs.windows.sf, 0)
    return true
end
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.win = function() ns.OpenWindows() end
ns.ExtraSlash["窗口"] = ns.ExtraSlash.win
ns._SettingsScrollTo = function(y) if page then return scrollTo(page, page.scroll, y) end end   -- 测试用
ns._SettingsSelectSub = function(k) if page then selectSub(page, k); refresh() end end   -- 测试用

-- 法师吃喝的两扇窗登记在这里（它们在组队子插件里，子插件按需加载；状态直接读存档，要动窗体时才加载子插件）
local function mwSaved() return ns.db and ns.db.dchat and ns.db.dchat.mw end
-- 野外弹框今天被「今天别再提示」静音了没有（组队子插件加载了问它，没加载看存档）
function ns.MageFieldMutedToday()
    local MW = ns.MageWater
    if MW and MW.FieldMuted then return MW.FieldMuted() and true or false end
    local f = ns.db and ns.db.dchat and ns.db.dchat.mwField
    local d = date or (os and os.date)
    return (f and f.off ~= nil and d and f.off == d("%Y-%m-%d")) and true or false
end
local function groupThere() return ns.ModuleAvailable and (ns.ModuleAvailable("group") or ns.ModuleLoaded("group")) and true or false end
local function iAmMage() return select(2, UnitClass("player")) == "MAGE" end
-- 11-13 第 5 期：法师吃喝搬进单独的按需加载子插件 GearInsight_Forever_GroupMage → 先加载组队信标，再加载法师吃喝
local function mw()
    if not (ns.LoadModule and ns.LoadModule("group")) then return nil end
    if not ns.MageWater and ns.GroupLoadMage then ns.GroupLoadMage(true) end
    return ns.MageWater
end
local function setMwOpt(k, v)   -- 默认都是开：开 = 存 nil，关 = 存 false（和 MW.SetOpt 一个口径）
    local MW = ns.MageWater
    if MW and MW.SetOpt then MW.SetOpt(k, v); return end
    ns.db.dchat = ns.db.dchat or {}; ns.db.dchat.mw = ns.db.dchat.mw or {}
    if v then ns.db.dchat.mw[k] = nil else ns.db.dchat.mw[k] = false end
    if ns.GroupSync then pcall(ns.GroupSync) end   -- 11-13 第 5 期：法师吃喝没加载时打开了开关 → 现在加载（组队信标在才有）
end
local function combatSay(ok, why)
    if not ok and why == "combat" then ns.Print(ns.L("战斗中动不了这个提醒条，脱战后再点", "Can't touch this bar in combat; try again after")) end
    return ok
end
ns.RegisterWindow({ key = "mageBar", order = 60, title = function() return ns.L("法师发水提醒条", "Mage request bar") end,
    avail = function() return groupThere() and iAmMage() end,
    state = function()
        local m = mwSaved()
        if m and m.bar == false then return ns.L("已关闭", "Off") end
        local rec = ns.db.dchat and ns.db.dchat.rec
        if not (rec and rec.mageAsk) then return ns.L("招人页「法师吃喝」总开关没开", "Master switch (Mage food) is off") end
        return ns.L("有人要水时弹出", "Pops up when someone asks")
    end,
    actions = function()
        local m = mwSaved()
        local on = not (m and m.bar == false)
        return {
            { text = on and ns.L("关闭", "Hide") or ns.L("打开", "Show"), fn = function()
                setMwOpt("bar", not on)
                local MW = ns.MageWater
                if MW and MW.RefreshBar then MW.barPreview = nil; pcall(MW.RefreshBar) end
            end },
            { text = ns.L("摆出来", "Preview"), fn = function()
                local MW = mw()
                if MW and MW.PreviewBar then combatSay(MW.PreviewBar()) end
            end },
            { text = ns.L("重置位置", "Reset position"), fn = function()
                local MW = mw()
                if MW and MW.ResetBarPos then combatSay(MW.ResetBarPos()) end
            end },
        }
    end })
ns.RegisterWindow({ key = "mageField", order = 61, title = function() return ns.L("野外找法师要水弹框", "Ask-a-mage prompt") end,
    avail = function() return groupThere() and not iAmMage() end,
    state = function()
        local m = mwSaved()
        if m and m.fieldAsk == false then return ns.L("已关闭", "Off") end
        if ns.MageFieldMutedToday() then return ns.L("今天已静音（明天自动恢复）", "Muted for today") end
        return ns.L("碰到法师、水不够时弹出", "Pops up near a mage when low on water")
    end,
    actions = function()
        local m = mwSaved()
        local on = not (m and m.fieldAsk == false)
        local muted = on and ns.MageFieldMutedToday()
        local function unmute()
            local MW = ns.MageWater
            if MW and MW.FieldMute then MW.FieldMute(false)
            elseif ns.db.dchat and ns.db.dchat.mwField then ns.db.dchat.mwField.off = nil end
        end
        if muted then
            return { { text = ns.L("解除静音", "Unmute"), fn = unmute } }
        end
        return {
            { text = on and ns.L("关闭", "Turn off") or ns.L("打开", "Turn on"), fn = function()
                setMwOpt("fieldAsk", not on)
                if on then
                    local MW = ns.MageWater
                    if MW and MW.HideField then pcall(MW.HideField) end
                else
                    unmute()
                end
            end },
        }
    end })

-- 11-09 GI-196：/gi scale 120（70-160）
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.scale = function(rest)
    local v = ns.SetUIScale(rest)
    if v then
        ns.Print(string.format(ns.L("窗口大小：%d%%", "Window size: %d%%"), math.floor(v * 100 + 0.5)))
        if page then page.refresh() end
    else
        ns.Print(string.format(ns.L("窗口大小：%d%%（%s scale 70-160）", "Window size: %d%% (%s scale 70-160)"), math.floor(ns.UIScale() * 100 + 0.5), ns.SlashHint))
    end
end

-- 11-09 GI-202：/gi lang zh|en|auto
ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.lang = function(rest)
    rest = (rest or ""):lower()
    if rest == "zh" or rest == "cn" or rest == "中文" or rest == "简体" then ns.SetLang("zh")
    elseif rest == "tw" or rest == "繁体" or rest == "繁體" then ns.SetLang("tw")   -- 11-10 GI-216
    elseif rest == "en" or rest == "english" then ns.SetLang("en")
    elseif rest == "auto" then ns.SetLang(nil)
    else
        ns.Print(ns.L("语言：", "Language: ") .. (ns.tw and "繁體中文" or ns.zh and "简体中文" or "English") .. "  (" .. ns.SlashHint .. " lang zh | tw | en | auto)")
        return
    end
    if page then page.refresh() end
end

ns.RegisterPage({ key = "data", order = 4, title = ns.L("设置", "Settings"), icon = "Interface\\Icons\\INV_Misc_Gear_01",
    build = build, refresh = refresh })
