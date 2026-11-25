-- HOLD：猎人助手 · 箭 / 子弹补充提醒（11-11 用户「猎人助手添加箭和子弹补充提醒，你好好设计下」）
--   ① 两档：少于 warn（默认 400 发）= 黄，少于 urgent（默认 150）= 红 + 闪；弹药栏空 / 弹药和武器不配（弓配子弹）单独说
--   ② 浮动小图标：只在少的时候出来，显示发数 + 「约够打 N 分钟」（按你最近战斗里的消耗算）；
--      左键 = 最近的弹药商插旗，右键 = 这一档先别提醒（补上或掉到下一档再说），按住拖 = 挪位置
--   ③ 聊天框 + 屏幕中间：每档只说一次，战斗中先攒着、脱战再说；补到 warn 以上重新计
--   ④ 进图：弹药不到「补满」的一半、这张图上有卖你这种弹药的商人 → 说一次在哪、多远
--   ⑤ 打开卖你这种弹药的商人：商人窗口上一个「补到 1000 发（买 N 组 · 价钱）」按钮，⛔ 点了才买，不自动花钱；
--      优先买你弹药栏里那种，没有就买你等级能用的最好的
--   ⑥ 11-12 用户「进主城箭袋不满直接提醒加满」：进六大主城（每次进城一次，10 分钟冷却，战斗中攒着脱战再说），
--      箭袋 / 弹药袋本身没装满（只数袋子里的，格数 × 每组上限；背包别处的不算）→ 屏幕中间 + 聊天框「箭袋没满（x/y）」+ 最近的弹药商；
--      没背箭袋 / 弹药袋 → 少于「补满」线（默认 1000）就提醒；商人按钮也改成补到箭袋装满
--   ⑦ 11-17 用户截图「锯齿箭 · 40 以后要买这个了」「现在提示不对」：最近的弹药商只找卖得到你这个等级那档的（40 级 = 卖锯齿箭的），
--      弹药栏是旧档（40 级还装着锐锋箭）→ 提醒该换哪种、商人按钮改买新档；升到 10 / 25 / 40 级说一次能买新箭了
--   ⑧ 11-17 用户截图（圆形浮标）「做个类似这个的放到桌面，右键永久关闭，给 GI 入口」：浮标改成圆形图标 + 角标发数；
--      右键 = 永久关闭浮标（聊天框 / 屏幕中间的提醒照旧），从 GI 菜单「窗口与提醒 → 弹药浮标」或 /gi ammo orb on 找回
local _, ns = ...; ns = _G.GearInsightForever or ns

local R = {}
ns.AmmoRemind = R
local L = function(zh, en) return ns.L(zh, en) end
local ARROW, BULLET = 1, 2
local ICON = { [ARROW] = "Interface\\Icons\\INV_Ammo_Arrow_02", [BULLET] = "Interface\\Icons\\INV_Ammo_Bullet_02" }
R.DEF = { warn = 400, urgent = 150, full = 1000 }

function R.DB()
    ns.db.ammoRemind = ns.db.ammoRemind or {}
    return ns.db.ammoRemind
end
function R.On() return ns.db ~= nil and R.DB().on ~= false end
function R.SetOn(v) R.DB().on = v and true or false; R.Update() end
function R.Get(k) return tonumber(R.DB()[k]) or R.DEF[k] end

local function now() return GetTime and GetTime() or 0 end
local function isHunter() return ns.MyClass and ns.MyClass() == "Hunter" end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function A() return ns.Ammo or {} end

local function instant(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (f and link) then return nil end
    local ok, _, _, _, _, _, classID, subID = pcall(f, link)
    if ok then return classID, subID end
end
local function ammoSlot()
    if not GetInventorySlotInfo then return 0 end
    local ok, s = pcall(GetInventorySlotInfo, "AmmoSlot")
    return ok and s or 0
end
-- 弹药栏里装的是箭(1) / 子弹(2) / 空(nil)，以及物品 ID
local function loadedKind()
    local link = GetInventoryItemLink and GetInventoryItemLink("player", ammoSlot())
    local classID, subID = instant(link)
    local id = GetInventoryItemID and GetInventoryItemID("player", ammoSlot())
    if classID == 6 and subID == 2 then return ARROW, id end
    if classID == 6 and subID == 3 then return BULLET, id end
    return nil, id
end

-- ---------- 消耗速度（只算战斗里的）----------
local rate = { used = 0, secs = 0, fightAt = nil, last = nil }
function R.Sample(count)
    if rate.last and count < rate.last and count > rate.last - 60 and rate.fightAt then
        rate.used = rate.used + (rate.last - count)
    end
    rate.last = count
end
function R.FightStart() rate.fightAt = now() end
function R.FightEnd()
    if rate.fightAt then rate.secs = rate.secs + math.max(0, now() - rate.fightAt) end
    rate.fightAt = nil
    -- 只留最近的量：超过 20 分钟战斗就按比例缩，让新打法（换枪 / 换本）快点体现出来
    if rate.secs > 1200 then rate.used, rate.secs = rate.used * 0.5, rate.secs * 0.5 end
end
-- 约够打几分钟战斗（样本不够 50 发 / 60 秒就不猜）
function R.Minutes(count)
    local secs = rate.secs + (rate.fightAt and math.max(0, now() - rate.fightAt) or 0)
    if rate.used < 50 or secs < 60 then return nil end
    return math.floor(count / (rate.used / secs) / 60 + 0.5)
end

-- ---------- 现在什么状态 ----------
-- { want, loaded, count, level = "ok" / "warn" / "urgent" / "empty", mismatch }，不是猎人 / 没装要弹药的武器 → nil
function R.State()
    if not isHunter() or not A().WantKind then return nil end
    local want = A().WantKind()
    local loaded, loadedID = loadedKind()
    if not want and not loaded then return nil end
    want = want or loaded
    local count = (A().AmmoCount and A().AmmoCount()) or 0
    local st = { want = want, loaded = loaded, loadedID = loadedID, count = count }
    st.mismatch = loaded ~= nil and loaded ~= want
    -- 11-12 用户截图「1512 发也亮红框」「不到报警的数量，不展示」：有的客户端读不出弹药栏装了啥（loaded = nil）
    --   → 以前当成「弹药栏空了」；现在只看数量，读不到装的什么不算空
    if count <= 0 then st.level = "empty"
    elseif count < R.Get("urgent") then st.level = "urgent"
    elseif count < R.Get("warn") then st.level = "warn"
    else st.level = "ok" end
    st.upgrade = R.Upgrade(st)
    return st
end
local RANK = { ok = 0, warn = 1, urgent = 2, empty = 3 }

local function kindName(k) return k == BULLET and L("子弹", "bullets") or L("箭", "arrows") end
local function zoneOf(ui0) return ns.Trainers and ns.Trainers.ZoneName and ns.Trainers.ZoneName(ui0) or "" end

-- ⑦ 你这个等级该用的那档（{ lv, id, zh, en, dps }）和按它筛的最近商人
local function tierOf(kind, lv) return A().Tier and A().Tier(kind, lv) or nil end
local function tierName(t) return A().TierName and A().TierName(t) or "" end
local function nearest(kind, n)
    if not A().Nearest then return {} end
    local t = tierOf(kind)
    return A().Nearest(kind, n, t and t[1]) or {}
end
-- 弹药栏里那种比你能买的最好那档低 → 那一档；读不出装的什么 / 已经是最好的 → nil
function R.Upgrade(st, lv)
    if not st or st.mismatch or not st.loadedID then return nil end
    local t = tierOf(st.want, lv)
    if not t or t[2] == st.loadedID then return nil end
    local req = A().ReqOf and A().ReqOf(st.loadedID)
    if req and req < t[1] then return t end
    return nil
end
local function upgradeText(t, lv)
    return string.format(L("你 %d 级了，弹药商能买「%s」（每秒伤害 +%d）了", "You're level %d - vendors now sell %s (+%d DPS)"),
        lv or (UnitLevel and UnitLevel("player")) or t[1], tierName(t), t[5])
end

-- 最近的卖这种弹药的商人一句话：「XXX（地区 约 N 码）」
local function nearestText(kind)
    local r = nearest(kind, 1)[1]
    if not r then return nil end
    local z = ns.Trainers and ns.Trainers.ZoneName and ns.Trainers.ZoneName(r.t.ui) or ""
    return r.t.name .. "|cffaaaaaa（" .. z .. (r.d and string.format(L(" 约 %d 码", " ~%d yd"), r.d) or "") .. "）|r", r
end

-- ---------- 提醒同时出一个「导航到最近的弹药商」按钮（11-15 用户截图「出来同时给个按钮，点击可以直接导航最近的」）----------
--   屏幕上方中间（团队警告文字下面）一个按钮：写着最近的商人和距离，点了 = 世界地图插旗 + 小地图箭头指路；20 秒没点自己收起，进战斗 / 开商人收起
R.NAV_TTL = 20
local navBtn
-- 11-17 用户「这些弹出的功能都确保能永久关闭」：按钮右键 = 以后不出导航按钮（存档 ammoRemind.nav = false；聊天框提醒照旧）
function R.NavOn() return R.DB().nav ~= false end
function R.NavNever()
    R.DB().nav = false
    R.HideNav()
    if ns.CloseHint then
        ns.CloseHint("ammoNav", L("弹药商导航按钮已永久关闭（聊天框提醒照旧）。找回：GI 菜单 → 设置 → 窗口与提醒「弹药商导航按钮」点「打开」，或 /gi ammo nav on",
            "Ammo vendor button closed for good (chat alerts stay). Bring it back: GI menu > Settings > Windows & alerts, or /gi ammo nav on"))
    end
end
function R.ShowNav(kind)
    if not R.NavOn() then return false end
    local r = nearest(kind, 1)[1]
    if not (r and r.t) then return false end
    if not navBtn then
        local b = CreateFrame("Button", "GearInsightForeverAmmoNav", UIParent, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(300, 26); b:SetFrameStrata("HIGH")
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        if RaidWarningFrame then b:SetPoint("TOP", RaidWarningFrame, "BOTTOM", 0, -6) else b:SetPoint("TOP", UIParent, "TOP", 0, -210) end
        b:SetScript("OnUpdate", function(self, el)
            self.age = (self.age or 0) + (el or 0)
            if self.age >= R.NAV_TTL then self:Hide() end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        navBtn = b
        R.navBtn = b
    end
    local t = r.t
    local zn = ns.Trainers and ns.Trainers.ZoneName and ns.Trainers.ZoneName(t.ui) or ""
    navBtn:SetText(string.format(L("导航到最近的弹药商：%s", "Go to nearest ammo vendor: %s"), t.name or "")
        .. (r.d and string.format(L("（约 %d 码）", " (~%d yd)"), r.d) or ""))
    local fs = navBtn.GetFontString and navBtn:GetFontString()
    local w = fs and fs.GetStringWidth and tonumber(fs:GetStringWidth())
    if w then navBtn:SetWidth(math.max(220, w + 30)) end
    navBtn:SetScript("OnClick", function(self, mb)
        if mb == "RightButton" then R.NavNever(); return end
        self:Hide()
        if ns.ShowOnMap then ns.ShowOnMap(t.ui, { { t.x, t.y } }, t.name) end
        ns.Print(string.format(L("已插旗：%s（%s %.1f, %.1f）—— 小地图边上有箭头指路", "Waypoint: %s (%s %.1f, %.1f) - follow the minimap arrow"),
            t.name or "", zn, t.x or 0, t.y or 0))
    end)
    navBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L("点一下在地图上插旗，跟着小地图箭头走", "Click to set a waypoint and follow the minimap arrow"), 1, 1, 1, true)
        GameTooltip:AddLine(zn .. string.format(" %.1f, %.1f", t.x or 0, t.y or 0), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L("左键插旗导航  ·  右键永久关闭", "Left: set waypoint  ·  Right: close for good"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    navBtn.age = 0
    navBtn:Show()
    return true
end
function R.HideNav() if navBtn then navBtn:Hide() end end

-- ---------- ③ 聊天框 / 屏幕中间（每档一次，战斗中攒着）----------
local told, toldKey, snooze, pending = 0, nil, 0, nil
local function say(st)
    local msg
    if st.mismatch then
        msg = string.format(L("弹药栏装的是%s，可你的远程武器要%s —— 打不出去！", "Your ammo slot has %s but your weapon needs %s!"), kindName(st.loaded), kindName(st.want))
    elseif st.level == "empty" then
        msg = string.format(L("弹药栏空了：你的远程武器要%s", "Ammo slot is empty: your weapon needs %s"), kindName(st.want))
    elseif st.level == "urgent" then
        msg = string.format(L("%s只剩 |cffff4040%d|r 发了，赶紧补", "Only |cffff4040%d|r %s left - restock now"), kindName(st.want), st.count)
    else
        msg = string.format(L("%s还剩 |cffffd100%d|r 发，该补了", "%s: |cffffd100%d|r left - time to restock"), kindName(st.want), st.count)
    end
    local m = R.Minutes(st.count)
    if m and st.level ~= "empty" and not st.mismatch then msg = msg .. string.format(L("（按你最近的打法约够打 %d 分钟）", " (~%d min of combat at your pace)"), m) end
    if st.upgrade then msg = msg .. "  |cff40ff40" .. upgradeText(st.upgrade) .. "|r" end
    local near = nearestText(st.want)
    if near then msg = msg .. L("  最近的：", "  Nearest: ") .. near end
    ns.Print(msg .. L("  |cff9a9a9a/gi ammo 插旗；设置页可关|r", "  |cff9a9a9a/gi ammo sets a waypoint; turn off in Settings|r"))
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local short = st.mismatch and L("弹药和武器不配", "Wrong ammo type")
            or st.level == "empty" and L("没有弹药了", "Out of ammo")
            or string.format(L("%s剩 %d 发", "%d %s left"), kindName(st.want), st.count)
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, short, 1, st.level == "warn" and 0.82 or 0.25, 0.1)
    end
    if R.DB().sound and PlaySound then pcall(PlaySound, 8959) end
    if not st.mismatch then pcall(R.ShowNav, st.want) end
end
function R.Alert(st)
    if not st then return end
    local lv = st.mismatch and 3 or RANK[st.level]
    local key = st.mismatch and "mismatch" or st.level
    if lv == 0 then told, toldKey, snooze, pending = 0, nil, 0, nil; return end   -- 补上了：重新计
    -- 更严重才说；「空了」和「不配」同一档但是两回事，换了也说
    if lv < told or (lv == told and key == toldKey) then return end
    if inCombat() then pending = st; return end
    told, toldKey = lv, key
    pending = nil
    say(st)
end
function R.Flush()
    if pending then local st = R.State(); pending = nil; if st then R.Alert(st) end end
end

-- ---------- ② 浮动小图标 ----------
local win, ui = nil, {}
-- 11-12 用户「点击弹窗直接可以选择找到最近的商人」：左键弹出小窗，列最近几位卖这种弹药的商人（地区 / 距离），点哪位就插旗到哪位
local pick
local PICK_ROWS = 5
local function buildPick()
    local f = CreateFrame("Frame", "GearInsightForeverAmmoPick", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(280, 40); f:SetFrameStrata("MEDIUM"); f:SetToplevel(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.92); f:SetBackdropBorderColor(1, 0.82, 0.1, 0.8)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 10, -8)
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cb:SetScript("OnClick", function() f:Hide() end)   -- 直接 Hide：战斗中也能关
    cb:SetSize(22, 22); cb:SetPoint("TOPRIGHT", -2, -2)
    f.rows = {}
    for i = 1, PICK_ROWS + 1 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(260, 20); b:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 22)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 0.82, 0.1, 0.15)
        b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT", 2, 0); b.t:SetPoint("RIGHT", -2, 0)
        b.t:SetJustifyH("LEFT"); b.t:SetWordWrap(false)
        f.rows[i] = b
    end
    -- ESC 关：登记到 UISpecialFrames（往表里追加，不重新赋值暴雪全局）
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GearInsightForeverAmmoPick") end
    f:Hide()
    return f
end
function R.ShowPick(anchor, kind)
    pick = pick or buildPick()
    if pick:IsShown() then pick:Hide(); return end
    local res = nearest(kind, PICK_ROWS)
    local tt = tierOf(kind)
    pick.title:SetText(tt and tt[1] > 1 and string.format(L("去哪儿买「%s」？", "Where to buy %s?"), tierName(tt))
        or string.format(L("去哪儿补%s？", "Where to buy %s?"), kindName(kind)))
    local n = 0
    for i, r in ipairs(res) do
        local b = pick.rows[i]
        n = i
        local d = r.d and string.format(L("约 %d 码", "~%d yd"), r.d) or L("别的大陆", "other continent")
        b.t:SetText((i == 1 and r.d and "|cffffd100" or "|cffffffff") .. r.t.name .. "|r  |cffaaaaaa" .. zoneOf(r.t.ui) .. " · " .. d .. "|r")
        b:SetScript("OnClick", function()
            pick:Hide()
            if ns.ShowOnMap then ns.ShowOnMap(r.t.ui, { { r.t.x, r.t.y } }, r.t.name) end
            ns.Print(string.format(L("已插旗：%s（%s %.1f, %.1f）—— 小地图边上有箭头指路", "Waypoint: %s (%s %.1f, %.1f) - follow the minimap arrow"),
                r.t.name, zoneOf(r.t.ui), r.t.x or 0, r.t.y or 0))
        end)
        b:Show()
    end
    for i = n + 1, PICK_ROWS do pick.rows[i]:Hide() end
    local more = pick.rows[PICK_ROWS + 1]
    more:ClearAllPoints(); more:SetPoint("TOPLEFT", 10, -28 - n * 22)
    more.t:SetText(n == 0 and L("|cffff8080还没有你这个阵营的弹药商资料|r  |cff66ccff打开弹药商页 ›|r", "|cffff8080No ammo vendors known yet|r  |cff66ccffOpen Ammo page ›|r")
        or L("|cff66ccff打开弹药商页（全部商人）›|r", "|cff66ccffOpen the Ammo page (all vendors) ›|r"))
    more:SetScript("OnClick", function()
        pick:Hide()
        if ns.ShowPage and _G.GearInsightForeverMain and _G.GearInsightForeverMain:IsShown() then ns.ShowPage("ammo")
        elseif ns.ToggleMain then ns.ToggleMain("ammo") end
    end)
    more:Show()
    pick:SetHeight(28 + (n + 1) * 22 + 8)
    pick:ClearAllPoints()
    pick:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    pick:Show()
end
local function savePos()
    local p, _, _, x, y = win:GetPoint()
    R.DB().pos = { p or "CENTER", x or 0, y or 0 }
end
-- ⑧ 圆形浮标：深色圆底 + 圆形弹药图标 + 金边 + 右上角标（发数）；悬停说明，左键选商人、右键永久关闭、拖拽移动
function R.OrbOn() return R.DB().orb ~= false end
function R.SetOrb(v)
    R.DB().orb = v and true or false
    if v then snooze = 0 end
    R.Update()
end
function R.ResetPos()
    R.DB().pos = nil
    if win then win:ClearAllPoints(); win:SetPoint("CENTER", UIParent, "CENTER", 120, -150) end
end
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function circle(owner, tex)
    if not (tex.AddMaskTexture and owner.CreateMaskTexture) then return end
    local m = owner:CreateMaskTexture()
    if not m then return end
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)
    tex:AddMaskTexture(m)
end
local function buildWin()
    local f = CreateFrame("Button", "GearInsightForeverAmmoAlert", UIParent)
    f:SetSize(44, 44); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)   -- 11-12 用户「图层降到地图以下」：世界地图是 HIGH 起
    local pos = R.DB().pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("CENTER", UIParent, "CENTER", 120, -150) end
    f:SetMovable(true)
    if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    -- 呼吸光在最底下（金色，红档闪得快；该换新箭 = 绿色）
    ui.glow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    ui.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if ui.glow.SetBlendMode then ui.glow:SetBlendMode("ADD") end
    ui.glow:SetPoint("CENTER"); ui.glow:SetSize(84, 84)
    ui.disc = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    ui.disc:SetPoint("CENTER"); ui.disc:SetSize(40, 40); ui.disc:SetColorTexture(0.06, 0.05, 0.04, 0.95)
    circle(f, ui.disc)
    ui.ic = f:CreateTexture(nil, "ARTWORK")
    ui.ic:SetPoint("CENTER"); ui.ic:SetSize(32, 32); ui.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    circle(f, ui.ic)
    -- 金边：小地图追踪按钮那张圆框（圆在贴图左上约 58% 的位置）
    ui.ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
    ui.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ui.ring:SetSize(76, 76); ui.ring:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    ui.ring:SetVertexColor(1, 0.82, 0.35)
    -- 右上角标：发数（红 / 黄底），该换新箭时绿底「↑」
    local badge = CreateFrame("Frame", nil, f)
    badge:SetFrameLevel((tonumber(f:GetFrameLevel()) or 1) + 3); badge:SetSize(20, 18); badge:SetPoint("CENTER", f, "TOPRIGHT", -5, -5)
    ui.badgeBg = badge:CreateTexture(nil, "ARTWORK")
    ui.badgeBg:SetAllPoints(); ui.badgeBg:SetColorTexture(0.78, 0.1, 0.1, 1)
    circle(badge, ui.badgeBg)
    ui.cnt = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.cnt:SetPoint("CENTER", 0, 0)
    ui.badge = badge
    ui.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.time:SetPoint("TOP", f, "BOTTOM", 0, -2)
    for _, fs in ipairs({ ui.cnt, ui.time }) do
        local font, sz = fs:GetFont()
        if font then pcall(fs.SetFont, fs, font, math.max(11, tonumber(sz) or 11), "OUTLINE") end
    end
    local acc = 0
    f:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if ui.glow:IsShown() then ui.glow:SetAlpha(0.35 + 0.5 * math.abs(math.sin(acc * (rawget(ui, "fast") and 5 or 2.5)))) end
    end)
    f:SetScript("OnEnter", function(self)
        local st = R.State()
        if not st or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(string.format(L("%s：%d 发", "%s: %d"), kindName(st.want), st.count), 1, 1, 1)
        if st.mismatch then GameTooltip:AddLine(string.format(L("弹药栏装的是%s，打不出去", "Ammo slot has %s - won't fire"), kindName(st.loaded)), 1, 0.3, 0.3, true) end
        if st.upgrade then GameTooltip:AddLine(upgradeText(st.upgrade), 0.25, 1, 0.25, true) end
        local m = R.Minutes(st.count)
        if m then GameTooltip:AddLine(string.format(L("按你最近的打法约够打 %d 分钟战斗", "~%d min of combat at your pace"), m), 1, 1, 1) end
        GameTooltip:AddLine(string.format(L("提醒线：少于 %d 黄、少于 %d 红；商人那里一键补到 %d", "Warn under %d, urgent under %d; top up to %d at vendors"),
            R.Get("warn"), R.Get("urgent"), R.Get("full")), 0.75, 0.75, 0.75, true)
        local near = nearestText(st.want)
        if near then GameTooltip:AddLine(L("最近的：", "Nearest: ") .. near, 1, 1, 1, true) end
        GameTooltip:AddLine(L("左键选商人插旗  ·  右键永久关闭  ·  拖拽移动", "Left: pick a vendor  ·  Right: close for good  ·  Drag: move"), 0.25, 0.9, 0.35, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f:SetScript("OnClick", function(_, mb)
        if GameTooltip then GameTooltip:Hide() end
        if mb == "RightButton" then
            if pick then pick:Hide() end
            R.SetOrb(false)
            ns.Print(L("弹药浮标已永久关闭（聊天框提醒照旧）。找回：GI 菜单 → 窗口与提醒 → 弹药浮标，或 /gi ammo orb on",
                "Ammo icon closed for good (chat alerts stay). Bring it back: GI menu > Windows & alerts > Ammo icon, or /gi ammo orb on"))
            return
        end
        local st = R.State()
        R.ShowPick(f, (st and st.want) or (A().WantKind and A().WantKind()) or ARROW)
    end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    return f
end
function R.Draw(st)
    local lv = st and (st.mismatch and 3 or RANK[st.level]) or 0
    -- 不到提醒线也出：弹药栏是旧档（该换新箭了）
    local up = st and st.upgrade and lv == 0
    if not R.On() or not R.OrbOn() or (lv == 0 and not up) or (lv > 0 and lv <= snooze) then if win then win:Hide() end; return end
    win = win or buildWin()
    R.win = win
    ui.ic:SetTexture(ICON[st.want] or ICON[ARROW])
    local red = lv >= 2
    if up then ui.badgeBg:SetColorTexture(0.1, 0.6, 0.15, 1)
    elseif red then ui.badgeBg:SetColorTexture(0.78, 0.1, 0.1, 1)
    else ui.badgeBg:SetColorTexture(0.85, 0.6, 0.05, 1) end
    if ui.glow.SetVertexColor then
        if up then ui.glow:SetVertexColor(0.3, 1, 0.3) else ui.glow:SetVertexColor(1, 0.82, 0.1) end
    end
    ui.glow:Show()
    rawset(ui, "fast", red)
    ui.cnt:SetText(up and "↑" or (st.count > 0 and tostring(st.count) or "0"))
    local w = ui.cnt.GetStringWidth and tonumber(ui.cnt:GetStringWidth())
    ui.badge:SetWidth(math.max(18, (w or 8) + 8))
    local m = R.Minutes(st.count)
    ui.time:SetText(st.mismatch and L("不配", "wrong") or (up and tierName(st.upgrade)) or (m and string.format("%dm", m)) or kindName(st.want))
    if up then ui.time:SetTextColor(0.3, 1, 0.3) elseif red then ui.time:SetTextColor(1, 0.3, 0.25) else ui.time:SetTextColor(1, 0.82, 0) end
    win:Show()
end

function R.Update()
    if not ns.db then return end
    local st = R.On() and R.State() or nil
    if st and st.loaded and st.loaded == st.want then R.Sample(st.count) end
    R.Draw(st)
    if st then R.Alert(st) end
end

-- ---------- ⑥ 箭袋 / 弹药袋容量（背包里和远程武器配套的弹药总数 vs 能装多少）----------
local function bagInvID(bag)
    local f = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if f then local ok, id = pcall(f, bag); if ok and id then return id end end
    return 19 + bag   -- 怀旧版：1~4 号包 = 20~23 格
end
local function bagSlots(bag)
    local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not f then return 0 end
    local ok, n = pcall(f, bag)
    if not ok or ns.Secret(n) then return 0 end
    return tonumber(n) or 0
end
-- 一格里的东西：链接、数量（读不出 / 保密值 → nil）
local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if not ok then return nil end
        if type(info) ~= "table" then return nil end
        local link, cnt = info.hyperlink, info.stackCount
        if ns.Secret(link) or ns.Secret(cnt) then return nil end
        return link, tonumber(cnt) or 0, info.itemID
    elseif GetContainerItemInfo then
        local ok, _, cnt, _, _, _, _, link = pcall(GetContainerItemInfo, bag, slot)
        if not ok or ns.Secret(link) or ns.Secret(cnt) then return nil end
        return link, tonumber(cnt) or 0
    end
end
local function stackOf(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local ok, n = pcall(C_Item.GetItemMaxStackSizeByID, id)
        if ok and tonumber(n) and n > 1 then return n end
    end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then
        local ok, _, _, _, _, _, _, _, n = pcall(f, id)
        if ok and tonumber(n) and n > 1 then return n end
    end
end
-- 背包里某种弹药一共多少发
function R.CountItem(id)
    local n = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for s = 1, bagSlots(bag) do
            local link, cnt, iid = slotItem(bag, s)
            if link and (iid or tonumber(link:match("item:(%d+)"))) == id then n = n + (cnt or 0) end
        end
    end
    return n
end
-- { want, count, max, quiver(有没有配套的箭袋/弹药袋), slots }；不是猎人 / 没装要弹药的武器 / 读不出 → nil
function R.Capacity()
    local st = R.State()
    if not st or not st.want then return nil end
    local want = st.want
    -- 11-12 用户拍板「只看箭袋本身满没满」：背着配套箭袋 / 弹药袋 → 只数袋子里的配套弹药（背包别处的不算），
    --   容量 = 袋子格数 × 每组上限；有空格 / 有格子不满一组都算没满。没背 → 数整个背包，对比 full（默认 1000）
    local total, inQuiver, slots, sampleID = 0, 0, 0, nil
    local nBags = NUM_BAG_SLOTS or 4
    for bag = 0, nBags do
        local n = bagSlots(bag)
        local isQuiver = false
        if bag > 0 and n > 0 then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", bagInvID(bag))
            if link and not ns.Secret(link) then
                local classID, subID = instant(link)
                -- 11 = 箭袋类：2 箭袋（装箭）· 3 弹药袋（装子弹）
                if classID == 11 and ((want == ARROW and subID == 2) or (want == BULLET and subID == 3)) then
                    slots = slots + n; isQuiver = true
                end
            end
        end
        for s = 1, n do
            local link, cnt, id = slotItem(bag, s)
            if link then
                local classID, subID = instant(link)
                if classID == 6 and ((want == ARROW and subID == 2) or (want == BULLET and subID == 3)) then
                    total = total + (cnt or 0)
                    if isQuiver then inQuiver = inQuiver + (cnt or 0) end
                    sampleID = sampleID or id or tonumber(link:match("item:(%d+)"))
                end
            end
        end
    end
    local _, loadedID = loadedKind()
    local per = stackOf(loadedID) or stackOf(sampleID) or 200
    local cap = { want = want, quiver = slots > 0, slots = slots, total = total }
    if slots > 0 then
        -- 背包一发都没读到、弹药栏却有数 → 刚上线背包还没加载，先不判（别把满箭袋说成 0）
        if total == 0 and not st.mismatch and (st.count or 0) > 0 then return nil end
        cap.count, cap.max = inQuiver, slots * per
    else
        -- 刚上线背包还没读到 → 至少按弹药栏那组的数算，别把够用说成 0
        cap.count, cap.max = math.max(total, st.mismatch and 0 or (st.count or 0)), R.Get("full")
    end
    return cap
end

-- ---------- ④ 进图提醒 ----------
local mapTold = {}
function R.CheckMap()
    if not R.On() or inCombat() then return false end
    local st = R.State()
    if not st or st.count >= R.Get("full") * 0.5 then return false end
    local ui0 = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not ui0 or mapTold[ui0] or not A().Nearest then return false end
    local r = nearest(st.want, 1)[1]
    if not (r and r.t.ui == ui0) then return false end
    mapTold[ui0] = true
    ns.Print(string.format(L("这张图上就有%s商：%s，你身上还剩 %d 发  |cff9a9a9a（/gi ammo 插旗）|r", "There's a %s vendor on this map: %s - you have %d left  |cff9a9a9a(/gi ammo)|r"),
        kindName(st.want), (nearestText(st.want)), st.count))
    return true
end

-- ---------- ⑤ 商人窗口「补满」按钮 ----------
local function itemInfo(link)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not (f and link) then return nil end
    local ok, _, _, _, ilvl, minLv = pcall(f, link)
    if ok then return tonumber(ilvl) or 0, tonumber(minLv) or 0 end
end
-- 商人货架上该买哪一格：{ i, name, price, per(每次买到几发), maxStack }
function R.PickMerchantItem(want)
    if not (GetMerchantNumItems and GetMerchantItemLink and GetMerchantItemInfo) then return nil end
    local _, curID = loadedKind()
    local myLv = UnitLevel and UnitLevel("player") or 1
    -- 优先弹药栏里那种；⑦ 但它比你能买的最好那档低（40 级还装锐锋箭）→ 买等级能用的最好的
    local tt = tierOf(want, myLv)
    local curReq = curID and A().ReqOf and A().ReqOf(curID)
    local keepCur = not (tt and curReq and curReq < tt[1])
    local best, bestScore
    for i = 1, GetMerchantNumItems() do
        local link = GetMerchantItemLink(i)
        local classID, subID = instant(link)
        if classID == 6 and ((want == ARROW and subID == 2) or (want == BULLET and subID == 3)) then
            local name, _, price, qty, numAvail, purchasable, usable = GetMerchantItemInfo(i)
            local ilvl, minLv = itemInfo(link)
            local id = tonumber(link:match("item:(%d+)"))
            if purchasable ~= false and usable ~= false and numAvail ~= 0 and (minLv or 0) <= myLv then
                local score = (keepCur and id and id == curID) and 1e6 or ((minLv or 0) * 1000 + (ilvl or 0))
                if not bestScore or score > bestScore then
                    bestScore = score
                    local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 200
                    best = { i = i, id = id, name = name, price = price or 0, per = math.max(1, tonumber(qty) or 1), maxStack = math.max(1, tonumber(maxStack) or 200) }
                end
            end
        end
    end
    return best
end
-- 补到 full 要买几次、多少钱：{ item, units(点几次 / 买几发), shots, cost }
function R.Plan(st)
    st = st or R.State()
    if not st then return nil end
    -- ⑥ 背着箭袋 / 弹药袋：补到装满（格数 × 每组上限）；没背：补到 full
    local target, have = R.Get("full"), (st.mismatch and 0 or st.count)
    local okc, cap = pcall(R.Capacity)
    if okc and cap and cap.want == st.want then
        have = cap.count
        if cap.quiver then target = cap.max end
    end
    local it = R.PickMerchantItem(st.want)
    if not it then return nil end
    -- ⑦ 换新档：旧箭不算数，按新箭补到满（箭袋装满旧箭时也给按钮）
    local switch = it.id ~= nil and st.loadedID ~= nil and it.id ~= st.loadedID and st.upgrade ~= nil
    if switch then have = R.CountItem(it.id) end
    local need = target - have
    if need <= 0 then return nil end
    local plan = { item = it, target = target, switch = switch }
    if it.per > 1 then            -- 老式货架：一次买一组（price 是一组的钱）
        plan.units = math.min(40, math.ceil(need / it.per))
        plan.shots = plan.units * it.per
        plan.cost = plan.units * it.price
    else                          -- 按发卖：price 是一发的钱
        plan.units = need
        plan.shots = need
        plan.cost = need * it.price
    end
    return plan
end
local function money(c)
    if GetCoinTextureString then local ok, s = pcall(GetCoinTextureString, c); if ok and s then return s end end
    return string.format("%d.%02d.%02d", math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end
function R.Buy()
    local st = R.State()
    local plan = R.Plan(st)
    if not plan then return false end
    if GetMoney and GetMoney() < plan.cost then
        ns.Print(string.format(L("钱不够：补到 %d 发要 %s", "Not enough money: %s needed"), plan.target or R.Get("full"), money(plan.cost)))
        return false
    end
    local it = plan.item
    if it.per > 1 then
        for _ = 1, plan.units do BuyMerchantItem(it.i) end
    else
        local left = plan.units
        while left > 0 do
            local q = math.min(left, it.maxStack)
            BuyMerchantItem(it.i, q)
            left = left - q
        end
    end
    ns.Print(string.format(L("已买 %d 发「%s」，花了 %s", "Bought %d x %s for %s"), plan.shots, it.name or "?", money(plan.cost)))
    return true
end
local buyBtn
function R.OnMerchant()
    if not R.On() then if buyBtn then buyBtn:Hide() end; return end
    local plan = R.Plan()
    if not plan then if buyBtn then buyBtn:Hide() end; return end
    if not buyBtn and MerchantFrame then
        buyBtn = ns.Button(MerchantFrame, "", 230, 24, function() R.Buy(); if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(R.OnMerchant) end) end end)
        buyBtn:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 4, -4)
        buyBtn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L("GearInsight · 补弹药", "GearInsight - restock ammo"), 1, 0.82, 0)
            GameTooltip:AddLine(L("点了才买；补到多少发：/gi ammo full 数字", "Only buys when clicked; change target with /gi ammo full <n>"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        buyBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    if not buyBtn then return end
    R.buyBtn = buyBtn
    if plan.switch then
        buyBtn:SetText(string.format(L("换「%s」：买 %d 发 · %s", "Switch to %s: %d · %s"), plan.item.name or "?", plan.shots, money(plan.cost)))
    else
        buyBtn:SetText(string.format(L("补到 %d 发（买 %d 发 · %s）", "Top up to %d (%d · %s)"), plan.target or R.Get("full"), plan.shots, money(plan.cost)))
    end
    local bfs = buyBtn.GetFontString and buyBtn:GetFontString()
    local bw = bfs and bfs.GetStringWidth and tonumber(bfs:GetStringWidth())
    if bw then buyBtn:SetWidth(math.max(230, bw + 24)) end
    buyBtn:Show()
end

-- ---------- ⑥ 进主城：箭袋没满就提醒加满 ----------
-- 暴风城 / 奥格瑞玛 / 铁炉堡 / 雷霆崖 / 达纳苏斯 / 幽暗城（同 CityPlates.lua）；
-- 《无限》弹药商数据（AmmoVendorData.lua）里中立的都在野外地图（藏宝海湾 / 加基森…），没有单独的中立主城地图 ID，不带
R.CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
R.CITY_CD = 600   -- 同一提醒 10 分钟内不重复（城里传送 / 进出银行别刷屏）
local visitCity, cityToldAt, cityPending = nil, nil, false
function R.CityMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not id or ns.Secret(id) then return nil end
    for _ = 1, 4 do                                  -- 城里的小地图（建筑内）往上找父地图
        if R.CITIES[id] then return id end
        local ok2, info = false, nil
        if C_Map.GetMapInfo then ok2, info = pcall(C_Map.GetMapInfo, id) end
        if not ok2 or type(info) ~= "table" or not info.parentMapID or info.parentMapID == 0 or (tonumber(info.mapType) or 0) <= 3 then return nil end
        id = info.parentMapID
    end
    return nil
end
local function center(msg)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] then
        if pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"]) then return end
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0.1) end
end
local function bagName(k) return k == BULLET and L("弹药袋", "ammo pouch") or L("箭袋", "quiver") end
function R.CityText(cap)
    if cap.quiver then
        return string.format(L("%s没满（%d/%d），去最近的弹药商补满", "%s not full (%d/%d) - top up at the nearest ammo vendor"), bagName(cap.want), cap.count, cap.max)
    end
    return L(string.format("%s只有 %d 发（不到 %d），去最近的弹药商补满", kindName(cap.want), cap.count, cap.max),
        string.format("Only %d %s (under %d) - top up at the nearest ammo vendor", cap.count, kindName(cap.want), cap.max))
end
function R.CheckCity()
    local city = R.CityMap()
    if not city then visitCity, cityPending = nil, false; return false end
    if city == visitCity and not cityPending then return false end   -- 这次进城已经处理过
    visitCity = city
    if not (isHunter() and R.On() and R.DB().city ~= false) then cityPending = false; return false end
    if inCombat() then cityPending = true; return false end          -- 战斗中不弹，脱战再看
    cityPending = false
    if cityToldAt and now() - cityToldAt < R.CITY_CD then return false end
    local ok, cap = pcall(R.Capacity)
    local notFull = ok and cap and cap.max and cap.count < cap.max
    local st = R.State()
    local up = st and st.upgrade
    if not notFull and not up then return false end
    cityToldAt = now()
    mapTold[city] = true   -- 同一张图「这张图上就有弹药商」那句不再重复说
    local short = notFull and R.CityText(cap) or nil
    if up then short = short and (short .. L("；", "; ") .. upgradeText(up)) or upgradeText(up) end
    local want = (st and st.want) or cap.want
    center(short)
    pcall(R.ShowNav, want)
    local msg = short
    local near = nearestText(want)
    if near then msg = msg .. L("  最近的：", "  Nearest: ") .. near end
    ns.Print(msg .. L("  |cff9a9a9a商人窗口下面有「补到 N 发」按钮；/gi ammo 插旗；/gi ammo city off 关|r",
        "  |cff9a9a9aUse the top-up button at the vendor; /gi ammo sets a waypoint; /gi ammo city off to disable|r"))
    if PlaySound then pcall(PlaySound, 8959) end
    return true
end

-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "PLAYER_LEVEL_UP" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued = false
local function soon()
    if queued then return end
    queued = true
    local run = function() queued = false; pcall(R.Update) end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
-- ⑦ 升到 10 / 25 / 40 级：能买新一档了，说一次 + 导航按钮（UnitLevel 这时可能还是旧的，用事件给的新等级）
function R.OnLevel(lv)
    lv = tonumber(lv)
    if not (lv and lv > 1 and R.On()) then return false end
    local st = R.State()
    if not st then return false end
    local t = tierOf(st.want, lv)
    if not (t and t[1] == lv) or st.loadedID == t[2] then return false end
    local res = A().Nearest and A().Nearest(st.want, 1, lv) or {}
    local r = res[1]
    local msg = "|cff40ff40" .. upgradeText(t, lv) .. "|r"
    if r then msg = msg .. L("  最近卖的：", "  Nearest: ") .. r.t.name .. "|cffaaaaaa（" .. zoneOf(r.t.ui) .. "）|r" end
    ns.Print(msg .. L("  |cff9a9a9a商人窗口下面的按钮会直接买新的|r", "  |cff9a9a9aThe vendor button buys the new one|r"))
    center(upgradeText(t, lv))
    pcall(R.ShowNav, st.want)
    return true
end
function R.OnEvent(e, a1)
    if not isHunter() then return end
    if e == "PLAYER_LEVEL_UP" then
        local lv = a1
        if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(R.OnLevel, lv); pcall(R.Update) end) else pcall(R.OnLevel, lv) end
        return
    end
    if e == "PLAYER_REGEN_DISABLED" then R.FightStart(); return end
    if e == "PLAYER_REGEN_ENABLED" then
        R.FightEnd(); pcall(R.Update); R.Flush()
        if cityPending then pcall(R.CheckCity) end
        return
    end
    if e == "UNIT_INVENTORY_CHANGED" and a1 ~= "player" then return end
    if e == "MERCHANT_CLOSED" then if buyBtn then buyBtn:Hide() end; soon(); return end
    if e == "MERCHANT_SHOW" or e == "MERCHANT_UPDATE" then pcall(R.OnMerchant); soon(); return end
    if e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_ENTERING_WORLD" then
        -- ⑥ 先看进主城（说过的话 ④ 就不重复），再看这张图上有没有弹药商
        if C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(R.CheckCity); pcall(R.CheckMap) end) end
    end
    soon()
end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "PLAYER_REGEN_DISABLED" or e == "MERCHANT_SHOW" then R.HideNav() end   -- 11-15 导航按钮：进战斗 / 已经到商人了就收起
    R.OnEvent(e, a1)
end)
-- 11-13 第 4 期：_Class 晚于进世界才加载（存档开着钉板 / HUD 等，登录后条件加载）→ 进世界那一下错过了，补跑一次
ns.AddInit(function()
    if IsLoggedIn and IsLoggedIn() then pcall(R.OnEvent, "PLAYER_ENTERING_WORLD") end
end)

-- ---------- 命令：/gi ammo（插旗） · /gi ammo warn|urgent|full 数字 · /gi ammo remind on|off ----------
-- 11-13 第 4 期理顺双注册：原来先抓 PageAmmo.lua 登记的 ns.ExtraSlash.ammo 当兜底（local go = …），
--   拆成子插件后主插件先放了一个「加载 _Class 再转发」的占位，抓到它就会自己转给自己、转个不停。
--   → /gi ammo、/gi 弹药 归这里一家：自己认的子命令处理完，其余（插旗找最近的弹药商）直接调弹药商页的 ns.Ammo.Go
ns.ExtraSlash = ns.ExtraSlash or {}
local function go()
    local A0 = ns.Ammo
    if A0 and A0.Go then A0.Go() end
end
ns.ExtraSlash.ammo = function(rest)
    rest = (rest or ""):lower()
    local k, v = rest:match("^(%a+)%s+(%S+)")
    if k == "remind" and (v == "on" or v == "off") then
        R.SetOn(v == "on")
        ns.Print(v == "on" and L("弹药补充提醒：已开", "Ammo reminder: on") or L("弹药补充提醒：已关", "Ammo reminder: off"))
        return
    end
    if k == "orb" and (v == "on" or v == "off") then
        R.SetOrb(v == "on")
        ns.Print(v == "on" and L("弹药浮标：已开（少了 / 该换新箭时出来）", "Ammo icon: on (shows when low / better ammo available)") or L("弹药浮标：已关", "Ammo icon: off"))
        return
    end
    if k == "nav" and (v == "on" or v == "off") then
        R.DB().nav = (v == "on")
        if v == "off" then R.HideNav() end
        ns.Print(v == "on" and L("弹药商导航按钮：已开", "Ammo vendor button: on") or L("弹药商导航按钮：已关", "Ammo vendor button: off"))
        return
    end
    if k == "city" and (v == "on" or v == "off") then
        R.DB().city = (v == "on")
        ns.Print(v == "on" and L("进主城箭袋没满提醒：已开", "City quiver reminder: on") or L("进主城箭袋没满提醒：已关", "City quiver reminder: off"))
        return
    end
    if rest == "city" then   -- 不管冷却，立刻按进城算一次（测试用）
        visitCity, cityToldAt = nil, nil
        if not R.CheckCity() then
            local ok, cap = pcall(R.Capacity)
            ns.Print(R.CityMap() == nil and L("你现在不在主城", "You're not in a capital city")
                or (cityPending and L("战斗中，脱战后再提醒", "In combat - will remind after combat"))
                or (ok and cap and string.format(L("箭袋 / 弹药：%d/%d，已满，不用补", "Ammo: %d/%d - full"), cap.count, cap.max))
                or L("读不出弹药（不是猎人 / 没装远程武器）", "Can't read ammo (not a hunter / no ranged weapon)"))
        end
        return
    end
    if k and R.DEF[k] and tonumber(v) then
        R.DB()[k] = math.max(0, math.floor(tonumber(v)))
        told, toldKey, snooze = 0, nil, 0
        R.Update()
        ns.Print(string.format(L("弹药提醒：少于 %d 黄、少于 %d 红；商人那里补到 %d", "Ammo: warn < %d, urgent < %d, top up to %d"), R.Get("warn"), R.Get("urgent"), R.Get("full")))
        return
    end
    if go then go(rest) end
end
ns.ExtraSlash["弹药"] = ns.ExtraSlash.ammo

-- ⑧ 「窗口与提醒」：右键关掉的浮标从这里找回（猎人提醒开着 _Class 登录就加载，入口就在；提醒整个关了从设置页「弹药」开）
ns.RegisterWindow({ key = "ammoOrb", order = 55, title = function() return L("弹药浮标（猎人）", "Ammo icon (Hunter)") end,
    avail = function() return isHunter() end,
    state = function()
        if not R.On() then return L("弹药提醒已关", "Ammo reminder is off") end
        if not R.OrbOn() then return L("已关闭", "Closed") end
        return L("开着（少了 / 该换新箭时出来）", "On (shows when low / better ammo available)")
    end,
    actions = function()
        local on = R.On() and R.OrbOn()
        return {
            { text = on and L("关闭", "Hide") or L("打开", "Show"), fn = function()
                if on then R.SetOrb(false) else R.DB().on = true; R.SetOrb(true) end
            end },
            { text = L("重置位置", "Reset position"), fn = function() R.ResetPos() end },
        }
    end })
-- 11-17「确保能永久关闭」：提醒时屏幕上方那颗「导航到最近的弹药商」按钮、进主城时屏幕中间那句，各自一个永久开关
ns.RegisterWindow({ key = "ammoNav", order = 55.1, title = function() return L("弹药商导航按钮（猎人）", "Ammo vendor button (Hunter)") end,
    avail = function() return isHunter() end,
    state = function()
        if not R.On() then return L("弹药提醒已关", "Ammo reminder is off") end
        return R.NavOn() and L("提醒时出在屏幕上方", "Shows at the top with alerts") or L("已关闭", "Closed")
    end,
    actions = function()
        local on = R.On() and R.NavOn()
        return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
            if on then R.NavNever() else R.DB().on = true; R.DB().nav = true; R.Update() end
        end } }
    end })
ns.RegisterWindow({ key = "ammoCity", order = 55.2, title = function() return L("进主城补箭提醒（屏幕中间）", "City ammo reminder (screen center)") end,
    avail = function() return isHunter() end,
    state = function()
        if not R.On() then return L("弹药提醒已关", "Ammo reminder is off") end
        return R.DB().city ~= false and L("进主城箭袋没满时出", "Shows on entering a city if not full") or L("已关闭", "Closed")
    end,
    actions = function()
        local on = R.On() and R.DB().city ~= false
        return { { text = on and L("关闭", "Turn off") or L("打开", "Turn on"), fn = function()
            if on then
                R.DB().city = false
                if ns.CloseHint then
                    ns.CloseHint("ammoCity", L("进主城补箭提醒已关闭：在这里重新打开，或 /gi ammo city on", "City ammo reminder off: turn it back on here or /gi ammo city on"))
                end
            else R.DB().on = true; R.DB().city = true; R.Update() end
        end } }
    end })
