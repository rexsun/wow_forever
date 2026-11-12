-- 11-10 用户「无限插件增加正式服那样的版本更新弹窗，每次版本只弹一次」：照正式服 main/WhatsNew.lua。
-- 内容 = WhatsNewData.lua（ns.WhatsNewData，发版前 scripts/gi_forever_whatsnew.py 从 dist/forever_release/changelog_<版本>.md 生成）。
-- 规则：
--   · 登录 / 重载后 4 秒弹（战斗中等脱战）；ns.db.whatsNewSeen == 当前 toc 版本 → 不弹。
--   · 每个版本只弹一次：弹出来就记为看过（和正式服不同：正式服 Esc 关了下次还弹；用户这次要的是「只弹一次」）。
--   · WhatsNewData 的版本和 toc 版本对不上（本地开发版 / 忘了生成）→ 不弹，免得拿旧版本的日志糊弄人。
--   · /gi whatsnew（/gi 更新）随时再看一次（不改看过的记录）。
local _, ns = ...
local L = function(cn, en) return ns.L(cn, en) end

local W = {}
ns.WhatsNew = W
W.DELAY = 4

local frame
local function build()
    if frame then return frame end
    local f = CreateFrame("Frame", "GearInsightForeverWhatsNew", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 420); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    if f.SetToplevel then pcall(f.SetToplevel, f, true) end
    if f.SetBackdrop then
        pcall(f.SetBackdrop, f, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.03, 0.035, 0.05, 0.96); f:SetBackdropBorderColor(0.85, 0.68, 0.25, 0.9)
    end
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -16); f.title:SetJustifyH("CENTER")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4); f.sub:SetJustifyH("CENTER")
    local sf = CreateFrame("ScrollFrame", "GearInsightForeverWhatsNewScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 20, -58); sf:SetPoint("BOTTOMRIGHT", -36, 52)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(456, 10)
    sf:SetScrollChild(child)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 2, -2); fs:SetWidth(452); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
    if fs.SetSpacing then pcall(fs.SetSpacing, fs, 4) end
    f.body, f.child, f.sf = fs, child, sf
    f.ok = ns.Button(f, L("知道了", "Got it"), 120, 24, function() f:Hide() end)
    f.ok:SetPoint("BOTTOMRIGHT", -20, 16)
    f.more = ns.Button(f, L("打开资讯页", "Open News"), 120, 24, function()
        f:Hide()
        if ns.ToggleMain then pcall(ns.ToggleMain, "news") end
    end)
    f.more:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetScript("OnClick", function() f:Hide() end)   -- 原生红叉走 HideUIPanel，战斗中会被拦
    x:SetPoint("TOPRIGHT", 2, 2)
    if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverWhatsNew") end
    f:Hide()
    frame = f
    return f
end

-- 更新日志原文 → 显示文本：「【位面】」/ 英文不带「- 」的行 = 小标题（金色），「- 」开头 = 条目（换成 •）
function W.Format(text)
    local out = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local item = line:match("^[-*]%s*(.+)$")
            if item then
                out[#out + 1] = "• " .. item
            else
                if #out > 0 then out[#out + 1] = "" end
                out[#out + 1] = "|cffffd100" .. line .. "|r"
            end
        end
    end
    return table.concat(out, "\n")
end

-- 当前版本的更新内容；版本对不上返回 nil
function W.Current()
    local ver = ns.AddonVersion and ns.AddonVersion() or ""
    local d = ns.WhatsNewData
    if ver == "" or type(d) ~= "table" or d.v ~= ver then return nil, ver end
    return d, ver
end

-- preview = true：命令行手动看，不检查也不改「看过」
function W.Show(preview)
    local d, ver = W.Current()
    if not d then
        if preview then ns.Print(string.format(L("当前版本 %s 还没有更新说明", "No release notes for version %s yet"), tostring(ver))) end
        return false
    end
    local f = build()
    f.title:SetText(string.format(L("GearInsight 无限版已更新到 %s", "GearInsight Forever updated to %s"), ver))
    f.sub:SetText((d.date and d.date ~= "" and (d.date .. "  ·  ") or "") .. L("这次更新了什么", "What's new"))
    local body = ns.L(d.zh, d.en or d.zh)
    f.body:SetText(ns.EnSafe and ns.EnSafe(W.Format(body)) or W.Format(body))
    local h = (f.body.GetStringHeight and f.body:GetStringHeight()) or 200
    f.child:SetHeight(math.max(10, (h or 200) + 8))
    if f.sf.SetVerticalScroll then pcall(f.sf.SetVerticalScroll, f.sf, 0) end
    if not preview and ns.db then ns.db.whatsNewSeen = ver end
    f:Show()
    return true
end

-- 该不该弹：返回 true = 弹了
function W.Check()
    if not ns.db then return false end
    local d, ver = W.Current()
    if not d or ns.db.whatsNewSeen == ver then return false end
    if InCombatLockdown and InCombatLockdown() then
        W.ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    return W.Show(false)
end

local ev = CreateFrame("Frame")
W.ev = ev
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(W.Check)
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(W.DELAY, function() pcall(W.Check) end)
    else
        pcall(W.Check)
    end
end)
W._event = ev:GetScript("OnEvent")   -- 测试用

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.whatsnew = function() pcall(W.Show, true) end
ns.ExtraSlash["更新"] = ns.ExtraSlash.whatsnew
