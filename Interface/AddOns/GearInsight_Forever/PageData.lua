-- 数据页：公测数据（死亡 / 升级 / 报到）、掉落记录、战绩卡二维码、开关
-- 插件不联网：导出串 / 二维码是唯一出口；不记角色名、服务器名
-- 10-07 用户「没用的按钮太多了」：8 个按钮 → 2 个按钮 + 2 个勾选框
--   · 「导出」一个按钮管两种串：先公测数据（GIFS1）再掉落（GIFD1），框里的确认键 =「已贴好，清掉已导出」，不再单独放清空按钮
--     （⛔两种串别拼进一个框：网站粘贴框一次只认一种前缀，同时带两种时只收掉落那段）
--   · 记录开关 / 小地图按钮 = 勾选框；升级指引走 /gif lv
local _, ns = ...

local page

local function count(list, sentKey)
    local d = ns.db
    local all = #(d[list] or {})
    return all, math.max(0, all - (d[sentKey] or 0))
end

-- 依次弹导出框：公测数据 → 掉落；最后一步的确认键清掉这次导出过的
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
                C_Timer.After(0.1, function() if page and page:IsShown() then ns.ShowPage("data") end end)
            else
                C_Timer.After(0.05, function() show(i + 1) end)
            end
        end, last and ns.L("已贴好，清掉已导出", "Pasted, clear exported") or ns.L("已贴好，下一段 →", "Pasted, next →"))
    end
    show(1)
end
ns.ExportAll = exportAll

local function check(p, text, y, get, set)
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(24, 24); c:SetPoint("TOPLEFT", 10, y)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 4, 0); fs:SetText(text)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    c.get = get
    return c
end

local function refresh()
    if not page then return end
    local dAll, dNew = count("deaths", "deathsSent")
    local lAll, lNew = count("lvls", "lvlsSent")
    local rAll, rNew = count("loot", "lootSent")
    local function line(name, all, new)
        return name .. "  |cffffffff" .. all .. "|r" .. (new > 0 and ("  |cff33ff99" .. ns.L("（", "(") .. new .. ns.L(" 条没导出）", " new)") .. "|r") or "")
    end
    page.body:SetText(ns.EnSafe(table.concat({
        line(ns.L("死亡记录", "Deaths"), dAll, dNew),
        line(ns.L("升级记录", "Level-ups"), lAll, lNew),
        line(ns.L("掉落记录", "Loot records"), rAll, rNew),
    }, "\n")))
    local n = dNew + lNew + rNew
    page.export:SetText(n > 0 and (ns.L("导出数据（", "Export (") .. n .. ns.L("）", ")")) or ns.L("导出数据", "Export"))
    for _, c in ipairs(page.checks) do c:SetChecked(c.get()) end
end

local function build(p)
    page = p
    ns.PageHeader(p, ns.L("公测数据", "Beta data"), ns.L("死亡 / 升级 / 掉落，导出后一起补全数据", "Deaths / levels / loot, pooled to help everyone"))
    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetPoint("TOPLEFT", 14, -54); p.body:SetWidth(600)
    p.body:SetJustifyH("LEFT"); p.body:SetSpacing(6)

    p.export = ns.Button(p, "", 140, 26, function() exportAll() end)
    p.export:SetPoint("TOPLEFT", 12, -130)
    local qr = ns.Button(p, ns.L("战绩卡二维码", "Beta card QR"), 120, 26, function() ns.ShowCardQR() end)
    qr:SetPoint("LEFT", p.export, "RIGHT", 8, 0)

    p.checks = {
        check(p, ns.L("记录公测数据（死亡 / 升级 / 掉落）", "Record beta data (deaths / levels / drops)"), -172,
            function() return ns.db.collect ~= false end, function(v) ns.SetCollect(v) end),
        check(p, ns.L("显示小地图按钮", "Show minimap button"), -200,
            function() return not (ns.db.minimap and ns.db.minimap.hide) end, function(v) ns.SetMinimapShown(v) end),
    }

    local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 14, -244); note:SetWidth(600); note:SetJustifyH("LEFT"); note:SetSpacing(4)
    note:SetText(ns.EnSafe(ns.L(
        "只带随机编号，不带角色名、服务器名；插件自己不联网。\n大家的数据汇总后会出现在鼠标提示里：怪物杀过多少公测玩家、每一级平均用时。\n战绩卡：微信扫码进小程序，看这个角色的升级用时 / 死亡 / 配点。",
        "Only a random id, no character or realm name; the addon never goes online by itself.\nPooled data shows up in tooltips.\nBeta card: scan with WeChat to see this character in the mini program.")))
end

ns.RegisterPage({ key = "data", order = 4, title = ns.L("公测数据", "Beta data"), build = build, refresh = refresh })
