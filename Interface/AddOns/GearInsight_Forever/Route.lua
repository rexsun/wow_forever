-- 升级规划 ·「路线」视图（10-12 用户「增加升级路线规划」）：1–60 每一段去哪个区域、顺路打哪个地下城
--   数据 RouteData.lua ← scripts/gi_forever_route.py（网站 /wow/forever/go 同一份 route.json）。
--   起始区按种族，之后按阵营；等级范围条里的几段正常显示、范围外压暗，当前等级那段标「你在这」。
--   点区域 = 世界地图切到那个区域（不插旗：路线只到区域级，没有具体坐标，插旗会骗人）；点地下城 = 去掉落页看这个本（那里有入口插旗）。
--   每段右侧「约 N 小时」= 公测玩家这几级的升级用时中位数相加（GIF_PACK.lvlMin，更新器下发）；有一级没数据就不写，不拿猜的凑。
local _, ns = ...

local GOLD, DIM, TXT, NEW = "|cffffd200", "|cff8a93a6", "|cffe6e0c8", "|cff33ff99"
local KNOWN = { Human = 1, Dwarf = 1, Gnome = 1, NightElf = 1, Orc = 1, Troll = 1, Scourge = 1, Tauren = 1 }
local RACE_NAME = { Human = { "人类", "Human" }, Dwarf = { "矮人", "Dwarf" }, Gnome = { "侏儒", "Gnome" }, NightElf = { "暗夜精灵", "Night Elf" },
    Orc = { "兽人", "Orc" }, Troll = { "巨魔", "Troll" }, Scourge = { "亡灵", "Undead" }, Tauren = { "牛头人", "Tauren" },
    Skyborne = { "天裔", "Skyborne" } }
local FAC_RACES = { Alliance = { "Human", "Dwarf", "Gnome", "NightElf", "Skyborne" }, Horde = { "Orc", "Troll", "Scourge", "Tauren", "Skyborne" } }

-- 当前角色的起始区键：经典八族按 raceFile；其余（《无限》新种族天裔，raceFile 客户端里没定论）一律算天裔
function ns.RouteRace()
    local rf
    if UnitRace then rf = select(2, UnitRace("player")) end   -- ⛔ `x and f()` 只留第一个返回值
    if not rf or ns.Secret(rf) then return nil end
    return KNOWN[rf] and rf or "Skyborne"
end

local function myFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde") and "Horde" or "Alliance"
end

-- 一条完整路线：起始区（按种族）+ 阵营主路线 + 60 级
function ns.RouteLegs(fac, race)
    local D = ns.RouteData
    if not D then return {} end
    local out = {}
    for _, s in ipairs((D.starts or {})[race or ""] or {}) do out[#out + 1] = s end
    for _, s in ipairs(D[fac] or {}) do out[#out + 1] = s end
    if D.cap then out[#out + 1] = D.cap end
    return out
end

-- 公测玩家这几级的升级用时中位数相加（分钟）；任何一级没数据 → nil
local function legMinutes(lo, hi)
    local P = _G.GIF_PACK
    local M = P and P.lvlMin
    if not M or hi <= lo then return nil end
    local sum = 0
    for lv = lo + 1, hi do
        local v = M[lv]
        if not v then return nil end
        sum = sum + v
    end
    return sum
end

local function zname(z) return ns.L(z.zh, z.en) end

local function openZone(m)
    if not m or m == 0 then ns.Print(ns.L("该区域暂缺地图定位", "Map location unavailable")); return false end
    if InCombatLockdown and InCombatLockdown() then ns.Print(ns.L("战斗中不能打开地图，请脱战后重试", "Open the map after combat")); return false end
    if OpenWorldMap then local ok=pcall(OpenWorldMap, m);return ok
    elseif WorldMapFrame then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, m) end
    end
end
ns.OpenRouteMap = openZone

local sel = { fac = nil, race = nil, mode = "zones", level = nil }   -- nil level follows the player
function ns.RouteSetMode(mode)
    sel.mode = mode == "all" and "all" or "zones"
    if ns.PlanPage then ns.PlanPage.needScroll=true end
    if ns.RefreshPlanPage then ns.RefreshPlanPage() end
end
function ns.RouteIsFocused()return sel.mode=="zones"end
function ns.RouteSetLevel(level)
    if level~=nil and (not tonumber(level) or tonumber(level)%1~=0 or tonumber(level)<1 or tonumber(level)>60) then
        ns.Print(ns.L("请输入 1-60 的整数等级", "Enter a whole level from 1 to 60"));return false
    end
    sel.level=level and tonumber(level) or nil
    if ns.RefreshPlanPage then ns.RefreshPlanPage() end
    return true
end

-- Derive recommendations from the existing route; do not invent zone ranges.
function ns.RouteZones(fac,race,level)
    local lv=tonumber(level)
    if not lv or lv%1~=0 or lv<1 or lv>60 or (fac~="Alliance" and fac~="Horde") then return {current={},upcoming={}} end
    local result={current={},upcoming={}}
    local legs=ns.RouteLegs(fac,race);local nextLo
    local hasStrict=false
    for _,s in ipairs(legs)do if lv>=s.lo and lv<s.hi then hasStrict=true end end
    for _,s in ipairs(legs)do if s.lo>lv and (not nextLo or s.lo<nextLo)then nextLo=s.lo end end
    local seen={current={},upcoming={}}
    for _,s in ipairs(legs)do
        local bucket
        if lv==60 then if s.lo==60 then bucket="current" end
        elseif lv>=s.lo and lv<s.hi then bucket="current"
        elseif not hasStrict and lv==s.hi then bucket="current"
        elseif s.lo==nextLo then bucket="upcoming" end
        if bucket then
            local candidates={{z=s.main,primary=true}}
            for _,z in ipairs(s.alt or {})do candidates[#candidates+1]={z=z,primary=false}end
            for _,candidate in ipairs(candidates)do
                local z=candidate.z;local key=z.m and z.m~=0 and tostring(z.m) or z.en
                local previous=seen[bucket][key]
                if not previous then
                    local entry={zone=z,lo=s.lo,hi=s.hi,primary=candidate.primary,stage=s,cap=lv==60}
                    seen[bucket][key]=entry;result[bucket][#result[bucket]+1]=entry
                elseif candidate.primary and not previous.primary then
                    previous.primary=true;previous.stage=s;previous.lo=s.lo;previous.hi=s.hi
                end
            end
        end
    end
    for _,bucket in ipairs({"current","upcoming"})do table.sort(result[bucket],function(a,b)
        if a.primary~=b.primary then return a.primary end
        if a.lo~=b.lo then return a.lo<b.lo end
        return a.zone.en<b.zone.en
    end)end
    return result
end

local function ensure(page)
    local R0 = rawget(page, "route")   -- ⛔ rawget：测试 mock 的 __index 对没有的字段返回函数
    if type(R0) == "table" then return R0 end
    local R = {}
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", page.sfX or 4, page.sfY or -100); f:SetSize(page.sfW or 646, page.sfH or 366)
    R.frame = f
    -- 顶部一行：阵营 + 种族按钮
    R.facBtns, R.raceBtns = {}, {}
    local x = 0
    for _, fac in ipairs({ "Alliance", "Horde" }) do
        local b = ns.Button(f, fac == "Alliance" and ns.L("联盟", "Alliance") or ns.L("部落", "Horde"), 56, 20, function()
            sel.fac = fac
            sel.race = sel.race or ns.RouteRace()
            if sel.race and sel.race ~= "Skyborne" then
                local ok = false
                for _, r in ipairs(FAC_RACES[fac]) do if r == sel.race then ok = true end end
                if not ok then sel.race = FAC_RACES[fac][1] end
            end
            ns.RefreshPlanPage()
        end)
        b:SetPoint("TOPLEFT", x, 0); x = x + 58
        R.facBtns[fac] = b
    end
    x = x + 10
    for i = 1, 5 do
        local b = ns.Button(f, "", 72, 20)
        b:SetPoint("TOPLEFT", x, 0); x = x + 74
        R.raceBtns[i] = b
    end
    R.levelLabel=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");R.levelLabel:SetPoint("TOPLEFT",0,-31)
    R.levelLabel:SetWidth(86);R.levelLabel:SetJustifyH("LEFT")
    R.minus=ns.Button(f,"-",24,20,function()ns.RouteSetLevel(math.max(1,(sel.level or UnitLevel("player"))-1))end);R.minus:SetPoint("TOPLEFT",88,-26)
    R.level=CreateFrame("EditBox",nil,f,"InputBoxTemplate");R.level:SetSize(36,20);R.level:SetPoint("TOPLEFT",120,-26)
    R.level:SetAutoFocus(false);R.level:SetMaxLetters(2)
    R.level:SetScript("OnEnterPressed",function(self)ns.RouteSetLevel(self:GetText());self:ClearFocus();ns.RefreshPlanPage()end)
    R.level:SetScript("OnEscapePressed",function(self)self:ClearFocus();ns.RefreshPlanPage()end)
    R.plus=ns.Button(f,"+",24,20,function()ns.RouteSetLevel(math.min(60,(sel.level or UnitLevel("player"))+1))end);R.plus:SetPoint("TOPLEFT",164,-26)
    R.mine=ns.Button(f,ns.L("当前角色","My character"),110,20,function()sel.fac=nil;sel.race=nil;ns.RouteSetLevel(nil)end);R.mine:SetPoint("TOPLEFT",196,-26)
    R.focus=ns.Button(f,ns.L("按等级找地图","Zones by level"),136,20,function()ns.RouteSetMode("zones")end);R.focus:SetPoint("TOPLEFT",314,-26)
    R.all=ns.Button(f,ns.L("完整路线","Full route"),120,20,function()ns.RouteSetMode("all")end);R.all:SetPoint("TOPLEFT",458,-26)
    local sf, c = ns.Scroll(f, 0, -55, (page.sfW or 646), (page.sfH or 366) - 55)
    R.sf, R.child, R.rows = sf, c, {}
    page.route = R
    return R
end

local function renderZones(R,fac,race,level,W)
    for _,r in ipairs(R.rows)do r:Hide()end
    if R.foot then R.foot:Hide()end
    R.zoneRows=R.zoneRows or {}
    for _,r in ipairs(R.zoneRows)do r:Hide()end
    local result=ns.RouteZones(fac,race,level);local index,y=0,0
    local function card(entry,label)
        index=index+1;local r=R.zoneRows[index]
        if not r then
            r=CreateFrame("Button",nil,R.child);R.zoneRows[index]=r
            r.bg=r:CreateTexture(nil,"BACKGROUND");r.bg:SetAllPoints();r.bg:SetColorTexture(1,1,1,0.045)
            r.heading=r:CreateFontString(nil,"OVERLAY","GameFontNormal");r.heading:SetPoint("TOPLEFT",10,-7);r.heading:SetWidth(W-20);r.heading:SetJustifyH("LEFT")
            r.body=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.body:SetPoint("TOPLEFT",r.heading,"BOTTOMLEFT",0,-5);r.body:SetWidth(W-20);r.body:SetJustifyH("LEFT");r.body:SetWordWrap(true)
        end
        local heading,body
        if entry then
            local z,s=entry.zone,entry.stage
            heading=label.."  "..entry.lo.."-"..entry.hi..ns.L(" 级  ","  ")..zname(z)..(z.fv and ns.L("  [无限新区域]","  [New zone]") or "")
            body=(entry.primary and ns.L(s.zh,s.en) or ns.L("同等级备选区域，按手头任务和所在位置选择；不需要把所有区域跑一遍。","Alternative for this level; choose by your quests and location, not every zone."))..
                "\n"..(s.src=="fv" and ns.L("公开升级路线建议", "Published route recommendation") or ns.L("经典基线参考，Beta 可能调整", "Classic baseline; beta may change"))..
                ns.L("；点击打开地图（不表示可直接传送）。", "; click to open map, not teleport.")
            r:SetScript("OnClick",function()openZone(z.m)end)
        else heading=label;body=ns.L("路线建议等级，不是地图准入限制。可选区域并非必须依次完成；当前角色会随升级更新，手动查询不会改变角色或装备规划。","Suggested route levels, not entry restrictions. Alternatives are optional. Live level follows your character; manual lookup does not alter gear planning.")
            r:SetScript("OnClick",nil)
        end
        r.heading:SetText(ns.EnSafe(heading));r.body:SetText(ns.EnSafe(body))
        local h=math.max(62,(r.heading:GetStringHeight() or 16)+(r.body:GetStringHeight() or 30)+23)
        r:ClearAllPoints();r:SetPoint("TOPLEFT",0,-y);r:SetSize(W,h);r:Show();y=y+h+5
    end
    if #result.current==0 then card(nil,ns.L("该等级暂缺路线建议，请查看完整路线", "No recommendation for this level; check the full route"))end
    for _,e in ipairs(result.current)do card(e,e.cap and ns.L("满级内容参考","At level cap") or (e.primary and ns.L("当前可选","For this level") or ns.L("备选","Alternative")))end
    for _,e in ipairs(result.upcoming)do card(e,ns.L("接下来","Next"))end
    card(nil,ns.L("等级口径与使用说明","How to use these levels"))
    R.child:SetHeight(y);local key=fac..race..level
    if R.zoneKey~=key then R.sf:SetVerticalScroll(0);R.zoneKey=key end
end

local function row(R, i)
    local r = R.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, R.child)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.accent = r:CreateTexture(nil, "BORDER"); r.accent:SetWidth(3); r.accent:SetPoint("TOPLEFT", 0, -2); r.accent:SetPoint("BOTTOMLEFT", 0, 2)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.08)
    r.lv = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.lv:SetPoint("TOPLEFT", 10, -6); r.lv:SetWidth(54); r.lv:SetJustifyH("LEFT")
    r.zone = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.zone:SetPoint("TOPLEFT", 68, -6); r.zone:SetJustifyH("LEFT")
    r.zone:SetWidth(440); r.zone:SetWordWrap(false)
    r.eta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.eta:SetPoint("TOPRIGHT", -24, -7); r.eta:SetJustifyH("RIGHT")
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.note:SetPoint("TOPLEFT", r.zone, "BOTTOMLEFT", 0, -3)
    r.note:SetWidth(540); r.note:SetJustifyH("LEFT"); r.note:SetWordWrap(true)
    r.dun = {}
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    R.rows[i] = r
    return r
end

local function dunBtn(r, k)
    local b = r.dun[k]
    if b then return b end
    b = CreateFrame("Button", nil, r)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.t:SetPoint("LEFT"); b.t:SetWordWrap(false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.dun[k] = b
    return b
end

function ns.HideRouteView(page)
    local R = page and rawget(page, "route")
    if type(R) == "table" then R.frame:Hide() end
end

function ns.RefreshRouteView(page, lo, hi)
    local R = ensure(page)
    R.frame:Show()
    local fac = sel.fac or myFaction()
    local race = sel.race or ns.RouteRace() or FAC_RACES[fac][1]
    local query=sel.level or (UnitLevel and UnitLevel("player")) or 1
    R.levelLabel:SetText(sel.level and ns.L("查询等级","Look up level") or ns.L("当前等级","Your level"))
    if not R.level:HasFocus() then R.level:SetText(tostring(query)) end
    R.minus:SetEnabled(query>1);R.plus:SetEnabled(query<60)
    R.focus:SetEnabled(sel.mode~="zones");R.all:SetEnabled(sel.mode~="all")
    for k, b in pairs(R.facBtns) do b:SetEnabled(k ~= fac) end
    for i, b in ipairs(R.raceBtns) do
        local rk = FAC_RACES[fac][i]
        b:SetText(ns.L(RACE_NAME[rk][1], RACE_NAME[rk][2]))
        b:SetEnabled(rk ~= race)
        b:SetScript("OnClick", function() sel.race = rk; ns.RefreshPlanPage() end)
    end
    if sel.mode=="zones" then renderZones(R,fac,race,query,(page.sfW or 646)-24);return end
    for _,r in ipairs(R.zoneRows or {})do r:Hide()end
    if R.foot then R.foot:Show()end
    local cur = UnitLevel and UnitLevel("player") or 1
    local mine = (fac == myFaction()) and (race == (ns.RouteRace() or race))
    local legs = ns.RouteLegs(fac, race)
    local y, W = 0, (page.sfW or 646) - 24
    for _, r in ipairs(R.rows) do r:Hide() end
    -- 「你在这」只标一段：段与段有重叠（13-15 / 14-19），取第一段 lo ≤ 等级 < hi 的；都没有再取 hi = 等级的
    local hereIdx
    if mine then
        for i, s in ipairs(legs) do if cur >= s.lo and cur < s.hi then hereIdx = i; break end end
        if not hereIdx then for i, s in ipairs(legs) do if cur == s.hi then hereIdx = i; break end end end
    end
    local scrollTo
    for i, s in ipairs(legs) do
        local r = row(R, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(W)
        local here = (i == hereIdx)
        local inRange = s.hi >= lo and s.lo <= hi
        r.lv:SetText((s.lo == s.hi) and tostring(s.lo) or (s.lo .. "-" .. s.hi))
        local z = s.main
        local alts = {}
        for _, a in ipairs(s.alt or {}) do alts[#alts + 1] = (a.fv and NEW or TXT) .. zname(a) .. "|r" end
        r.zone:SetText(ns.EnSafe((z.fv and NEW or GOLD) .. zname(z) .. "|r"
            .. (z.fv and (" " .. NEW .. ns.L("《无限》新区域", "new zone") .. "|r") or "")
            .. (#alts > 0 and ("  " .. DIM .. ns.L("也可以：", "or: ") .. "|r" .. table.concat(alts, DIM .. " / |r")) or "")
            .. (here and ("  |cff33ff99" .. ns.L("你在这", "you are here") .. "|r") or "")))
        local mins = legMinutes(s.lo, s.hi)
        r.eta:SetText(mins and (DIM .. string.format(ns.L("公测约 %.1f 小时", "beta ~%.1fh"), mins / 60) .. "|r") or "")
        r.note:SetText(ns.EnSafe(DIM .. ns.L(s.zh, s.en) .. "|r"))
        local h = 6 + 16 + 3 + (r.note:GetStringHeight() or 12) + 4
        -- 地下城一行（可点：去掉落页看这个本）
        for _, b in ipairs(r.dun) do b:Hide() end
        if s.dun and #s.dun > 0 then
            local dx, dy = 68, -(h + 1)
            for k, d in ipairs(s.dun) do
                local b = dunBtn(r, k)
                b.t:SetText(ns.EnSafe((k == 1 and (DIM .. ns.L("地下城 ", "Dungeons ") .. "|r") or "")
                    .. (d.fv and NEW or "|cff66ccff") .. ns.L(d.zh, d.en) .. "|r" .. DIM .. " " .. d.lv .. "|r"))
                local bw = (b.t:GetStringWidth() or 80) + 6
                if dx + bw > W - 8 then dx = 68; dy = dy - 16; h = h + 16 end
                b:ClearAllPoints(); b:SetPoint("TOPLEFT", dx, dy); b:SetSize(bw, 15); b:Show()
                dx = dx + bw + 10
                b:SetScript("OnClick", function() if ns.LootShowDungeon then ns.LootShowDungeon(d.zh) end end)
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(ns.L(d.zh, d.en), 1, 0.82, 0)
                    GameTooltip:AddLine(ns.EnSafe(ns.L("等级 ", "Level ") .. d.lv .. (d.fv and ns.L(" ·《无限》新地下城", " - new in Forever") or "")), 1, 1, 1)
                    GameTooltip:AddLine(ns.L("点击：去掉落页看这个本（那里能在地图上标入口）", "Click: open it on the Loot page (entrance pin there)"), 0.6, 0.6, 0.6, true)
                    GameTooltip:Show()
                end)
            end
            h = h + 18
        end
        r:SetHeight(h)
        r.bg:SetColorTexture(1, 1, 1, here and 0.10 or ((i % 2 == 0) and 0.03 or 0.05))
        r.accent:SetColorTexture(here and 0.2 or 1, here and 1 or 0.82, here and 0.6 or 0, 0.9)
        r.accent:SetShown(here or z.fv)
        r:SetAlpha(inRange and 1 or 0.45)
        r:SetScript("OnClick", function() openZone(z.m) end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(zname(z) .. "  " .. s.lo .. "-" .. s.hi, 1, 0.82, 0)
            GameTooltip:AddLine(ns.EnSafe(ns.L(s.zh, s.en)), 1, 1, 1, true)
            if mins then GameTooltip:AddLine(ns.EnSafe(string.format(ns.L("公测玩家这几级的升级用时中位数相加：约 %d 分钟", "Sum of beta players' median time for these levels: ~%d min"), math.floor(mins + 0.5))), 0.7, 0.9, 0.7, true) end
            GameTooltip:AddLine(s.src == "fv" and ns.L("区域顺序：《无限》公开升级指南", "Zone order: published Forever leveling guides")
                or ns.L("等级段：经典旧世基线 + 官方公布的《无限》新内容，Beta 可能微调", "Level band: Classic baseline + announced Forever content; may shift in beta"), 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine(ns.L("点击：世界地图打开这个区域", "Click: open this zone on the world map"), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:Show()
        if (here or (not scrollTo and inRange)) and not (scrollTo and scrollTo.here) then scrollTo = { y = y, here = here } end
        y = y + h + 3
    end
    -- 末尾：口径说明 + 网页版
    local foot = rawget(R, "foot")
    if not foot then
        foot = CreateFrame("Button", nil, R.child)
        foot.t = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); foot.t:SetPoint("TOPLEFT", 8, -4); foot.t:SetJustifyH("LEFT")
        local hl = foot:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.08)
        R.foot = foot
    end
    foot.t:SetWidth(W - 16)
    foot.t:SetText(ns.EnSafe(ns.L((ns.RouteData and ns.RouteData.note.zh) or "", (ns.RouteData and ns.RouteData.note.en) or "")
        .. (ns.LandingURL and ("\n|cff66ccff" .. ns.L("点这里复制网页版（手机上也能看，按你的角色排好）", "Click to copy the web version (laid out for your character)") .. "|r") or "")))
    local fh = (foot.t:GetStringHeight() or 24) + 10
    foot:ClearAllPoints(); foot:SetPoint("TOPLEFT", 0, -y - 4); foot:SetSize(W, fh)
    foot:SetScript("OnClick", ns.LandingURL and function()
        ns.ShowBox(ns.L("升级路线网页版", "Leveling route (web)"), ns.L("Ctrl+C 复制，到浏览器打开", "Ctrl+C, then open it in your browser"), ns.LandingURL("route"))
    end or nil)
    R.child:SetHeight(y + 14 + fh)
    if page.needScroll then
        page.needScroll = false
        local want = scrollTo and math.max(0, scrollTo.y - 6) or 0
        if R.sf.UpdateScrollChildRect then R.sf:UpdateScrollChildRect() end
        local maxR = tonumber(R.sf.GetVerticalScrollRange and R.sf:GetVerticalScrollRange()) or 0
        R.sf:SetVerticalScroll(math.max(0, math.min(want, maxR)))
    end
end

ns.ExtraSlash = ns.ExtraSlash or {}
ns.ExtraSlash.route = function()
    if ns.PlanSetView then ns.PlanSetView("route") end
    ns.ToggleMain("plan")
end
ns.ExtraSlash["路线"] = ns.ExtraSlash.route
ns.ExtraSlash.zones = function(rest)
    if rest and rest~="" and not ns.RouteSetLevel(rest) then return end
    if not rest or rest=="" then ns.RouteSetLevel(nil) end
    local level = sel.level or UnitLevel("player")
    if ns.SetPlanRange then ns.SetPlanRange(level, level) end
    if ns.PlanSetView then ns.PlanSetView("timeline") end
    ns.ToggleMain("plan")
end
ns.ExtraSlash["地图"] = ns.ExtraSlash.zones

local zoneEvents=CreateFrame("Frame")
zoneEvents:RegisterEvent("PLAYER_LEVEL_UP")
zoneEvents:SetScript("OnEvent",function()if not sel.level and C_Timer and C_Timer.After then C_Timer.After(0.2,function()if ns.RefreshPlanPage then ns.RefreshPlanPage()end end)end end)
