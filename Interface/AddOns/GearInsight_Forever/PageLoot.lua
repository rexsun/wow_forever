-- 掉落页 + 心愿单（v1）：地下城 → 首领 → 装备（数据 = 小程序掉落页同一份 forever_loot）
-- 心愿单：点星标收藏 → 进副本 / 开打首领 / 拾取窗口出现时提醒
-- 物品鼠标提示：加一行「掉落：副本 · 首领」和心愿单标记
local _, ns = ...

local QCOLOR = { q1 = "ffffff", q2 = "1eff00", q3 = "0070dd", q4 = "a335ee", q5 = "ff8000" }
local idx = {}          -- itemId → { d=, b=, it= }

-- 10-10 三期：掉落页列表 = 地下城 + 末尾一个「野外稀有」虚拟条目（ns.Data.rares，有掉落的才列，按等级排）。
--   ⛔ 只在掉落页 / 物品提示里拼，不写回 ns.Data.loot：那张表是升级规划装备候选的来源，世界稀有掉落不该进 BiS 现算
local lootCache
local function lootList()
    if lootCache then return lootCache end
    local out = {}
    for _, d in ipairs(ns.Data.loot.dungeons or {}) do out[#out + 1] = d end
    local rs = {}
    for _, r in ipairs(ns.Data.rares or {}) do if #(r.items or {}) > 0 then rs[#rs + 1] = r end end
    table.sort(rs, function(a, b) return (a.lv[1] or 0) < (b.lv[1] or 0) end)
    if #rs > 0 then out[#out + 1] = { n = "野外稀有", nEn = "World Rares", virtual = true, bosses = rs } end
    lootCache = out
    return out
end
ns.LootList = lootList

local function rareLoc(b)   -- 「暮色森林 18.0,37.9 · 刷新约 5 小时」
    if not b.z then return nil end
    local t = ns.L(b.z, b.zEn or b.z)
    if (b.x or 0) > 0 then t = t .. string.format(" %.1f,%.1f", b.x, b.y) end
    if (b.np or 0) > 1 then t = t .. ns.L("（" .. b.np .. " 个刷新点）", " (" .. b.np .. " spawns)") end
    local rs = b.rs or 0
    if rs >= 60 then
        t = t .. ns.L(" · 刷新约 ", " - respawn ~") .. (rs >= 3600 and (string.format("%g", math.floor(rs / 360) / 10) .. ns.L(" 小时", "h"))
            or (math.floor(rs / 60) .. ns.L(" 分钟", "m")))
    end
    return t
end

-- 世界地图插旗（C_Map.SetUserWaypoint，地图上点不了就只在聊天框给坐标）
function ns.MarkEntrance(e)
    if not e or (e.ui or 0) == 0 then return end
    local where = ns.EnSafe(ns.L(e.zc or "", e.ze or "") .. string.format(" %.1f, %.1f", e.x or 0, e.y or 0))
    local ok = ns.ShowOnMap(e.ui, { { e.x or 0, e.y or 0 } }, ns.L("副本入口", "Dungeon entrance"))
    ns.Print(ns.L("副本入口：", "Dungeon entrance: ") .. where .. (ok and ns.L("（已在地图上标记）", " (pinned on the map)") or ""))
    return ok
end

-- 10-11 野外稀有打标：装了 TomTom 就用 TomTom 打点（多个刷新点全打），没装用游戏地图标记（只能一个点）；
--   聊天框同时给一行 /way（TomTom 语法 /way #地图编号 x y 名字），没装插件也能抄坐标
function ns.MarkRare(b)
    if not b or (b.ui or 0) == 0 or (b.x or 0) == 0 then return false end
    local name = ns.L(b.n, b.nEn or b.n)
    local pts = (b.pts and #b.pts > 0) and b.pts or { { b.x, b.y } }
    local ok, tomtom = ns.ShowOnMap(b.ui, pts, name)
    local how = tomtom and "TomTom" or (ok and ns.L("地图标记", "map pin")) or nil
    ns.Print(string.format(ns.L("%s：%s %.1f, %.1f%s%s", "%s: %s %.1f, %.1f%s%s"), name, ns.L(b.z or "", b.zEn or b.z or ""), pts[1][1], pts[1][2],
        #pts > 1 and string.format(ns.L("（共 %d 个刷新点%s）", " (%d spawns%s)"), #pts, how == "TomTom" and ns.L("，已全部打点", ", all marked") or ns.L("，标的是第一个", ", first one marked")) or "",
        how and (ns.L(" · 已用", " - marked with ") .. how) or ""))
    ns.Print(string.format("/way #%d %.1f %.1f %s", b.ui, pts[1][1], pts[1][2], name))
    return how ~= nil
end

-- 鼠标指向稀有怪：一行刷新 + 专属 / 高掉率装备（Pack.lua 的单位提示钩子调用）
local rareById
function ns.RareLines(npcId)
    if not npcId then return nil end
    if not rareById then
        rareById = {}
        for _, r in ipairs(ns.Data.rares or {}) do rareById[r.npc] = r end
    end
    local r = rareById[npcId]
    if not r then return nil end
    local lines = { "|cff33ff99GI|r " .. ns.L(r.rare == 2 and "稀有精英" or "稀有", r.rare == 2 and "Rare Elite" or "Rare") .. (rareLoc(r) and (" · " .. rareLoc(r)) or "") }
    local names = {}
    for i, it in ipairs(r.items or {}) do
        if i > 4 then break end
        names[#names + 1] = "|cff" .. (QCOLOR[it.q] or "ffffff") .. ns.L(it.n, it.nEn) .. "|r" .. (it.p and (" " .. ns.PctText(it.p)) or "")
    end
    if #names > 0 then lines[#lines + 1] = ns.L("掉落：", "Drops: ") .. table.concat(names, ns.L("、", ", ")) end
    return lines
end

local function buildIndex()
    for _, d in ipairs(lootList()) do
        for _, b in ipairs(d.bosses) do
            for _, it in ipairs(b.items) do idx[it.id] = { d = d, b = b, it = it } end
        end
    end
end

local function wish() ns.db.wish = ns.db.wish or {}; return ns.db.wish end
local function isWished(id) return wish()[id] and true or false end
local function nm(x) return ns.L(x.n, x.nEn) end


-- ---------- 副本图（10-07 用户截图「这里副本加副本图片是不是更加美观」）----------
-- 用客户端自带的图（不打包）：冒险手册的副本按钮图 / 地下城查找器背景 / 地下城图标，按顺序找第一张客户端里真的有的
--   （GetFileIDFromPath 查得到才用，免得出绿块）；《无限》新副本客户端没图 → 按地区挑一个经典游戏图标
-- 键：英文名 → { 冒险手册键, 查找器键 }
local ART_KEYS = {
    ["The Deadmines"] = { "TheDeadmines", "Deadmines" }, ["Wailing Caverns"] = { "WailingCaverns", "WailingCaverns" },
    ["Shadowfang Keep"] = { "ShadowfangKeep", "ShadowfangKeep" }, ["The Stockade"] = { "TheStockade", "StormwindStockades" },
    ["Razorfen Kraul"] = { "RazorfenKraul", "RazorfenKraul" }, ["Blackfathom Deeps"] = { "BlackfathomDeeps", "BlackfathomDeeps" },
    ["Razorfen Downs"] = { "RazorfenDowns", "RazorfenDowns" }, ["Gnomeregan"] = { "Gnomeregan", "Gnomeregan" },
    ["Scarlet Monastery"] = { "ScarletMonastery", "ScarletMonastery" }, ["Sunken Temple"] = { "TheTempleOfAtalHakkar", "SunkenTemple" },
    ["Uldaman"] = { "Uldaman", "Uldaman" }, ["Zul'Farrak"] = { "ZulFarrak", "ZulFarak" }, ["Maraudon"] = { "Maraudon", "Maraudon" },
    ["Ragefire Chasm"] = { "RagefireChasm", "RagefireChasm" }, ["Dire Maul"] = { "DireMaul", "DireMaul" },
    ["Scholomance"] = { "Scholomance", "Scholomance" }, ["Stratholme"] = { "Stratholme", "Stratholme" },
    ["Blackrock Depths"] = { "BlackrockDepths", "BlackrockDepths" }, ["Lower Blackrock Spire"] = { "LowerBlackrockSpire", "BlackrockSpire" },
    ["Upper Blackrock Spire"] = { "UpperBlackrockSpire", "BlackrockSpire" },
}
-- 《无限》新副本：客户端没有专门的图，挑一个贴主题的经典图标
local NEW_ICON = {
    ["Halls of Thane"] = "INV_Hammer_05", ["Ruins of Lordaeron"] = "Spell_Shadow_RaiseDead", ["Wetlands Excavation"] = "INV_Pick_02",
    ["City of Dalaran"] = "Spell_Holy_MagicalSentry", ["The Sunken City"] = "Spell_Frost_SummonWaterElemental", ["Crodok Hold"] = "INV_Axe_09",
    ["Alcaz Island Prison"] = "INV_Misc_Key_03", ["Blackthroat Keep"] = "INV_Misc_Head_Orc_01", ["The Shaper's Terrace"] = "INV_Misc_Gem_Diamond_01",
}
local function hasFile(path)
    if GetFileIDFromPath then return GetFileIDFromPath(path) ~= nil end
    return nil   -- 查不了：不确定
end
local artCache = {}
function ns.DungeonArtClear() artCache = {} end   -- 测试用
-- → { banner = 路径, bannerCoord = {…}, icon = 路径, iconCoord = {…}, round = 图标是圆的 }
function ns.DungeonArt(d)
    local key = d and d.nEn or ""
    if artCache[key] then return artCache[key] end
    local k = ART_KEYS[key]
    if not k then
        for prefix, v in pairs(ART_KEYS) do if key:sub(1, #prefix) == prefix then k = v; break end end   -- 血色 / 厄运 / 斯坦索姆分区
    end
    local a = {}
    -- 10-10 经典加载画面（2048 方图，游戏里按 4:3 拉伸显示）：顶部 WoW 标志、上下花边 → 只取中间画面带；
    --   比冒险手册按钮图（174×96）清楚得多 → 有就优先当横幅和整页大背景。键来自 Data（gi_forever_ej_art.py）
    if d and d.ls then
        local ls = "Interface\\Glues\\LoadingScreens\\" .. d.ls
        if hasFile(ls) then   -- 查得到才用（和下面冒险手册图一样，免得出绿块）
            -- lsr = 《无限》新副本的新加载画面（2992×1684 上下透明带）：{ 上, 下, 宽高比[, 左, 右] }；经典方图固定裁中间带
            --   带左右的 = 还没专属图的 5 个新本，从大陆原画里按所在地区裁一块（10-10）
            local r = d.lsr
            a.region = r and { r[4] or 0, r[5] or 1, r[1], r[2], r[3] } or { 0, 1, 0.245, 0.80, (4 / 3) / 0.555 }
            a.banner = ls
            a.bannerCoord = { a.region[1], a.region[2], a.region[3], a.region[4] }
            a.big, a.bigRegion = ls, a.region
        end
    end
    if k and not a.banner then
        local ej = "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-" .. k[1]
        local bg = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. k[2]
        -- region = 图里有画面的那块（贴图坐标）+ 那块的宽高比（像素）：冒险手册按钮图 174×96 在 256×128 里，查找器背景 512×256 全是画面
        if hasFile(ej) then a.banner, a.region = ej, { 0, 0.68, 0, 0.75, 174 / 96 }
        elseif hasFile(bg) then a.banner, a.region = bg, { 0, 1, 0, 1, 2 } end
        if a.region then a.bannerCoord = { a.region[1], a.region[2], a.region[3], a.region[4] } end
        -- 整页大背景（升级规划 · 装备页，10-08）：优先查找器背景 512×256（冒险手册按钮图只有 174×96，铺满会糊）
        if hasFile(bg) then a.big, a.bigRegion = bg, { 0, 1, 0, 1, 2 }
        elseif a.banner then a.big, a.bigRegion = a.banner, a.region end
    end
    if k then
        local ic = "Interface\\LFGFrame\\LFGIcon-" .. k[2]
        if hasFile(ic) ~= false then a.icon, a.iconCoord, a.round = ic, { 0, 1, 0, 1 }, true end   -- 查不了时也试（经典图标基本都在）
    end
    if not a.icon then
        a.icon, a.iconCoord = "Interface\\Icons\\" .. (NEW_ICON[key] or "INV_Misc_Map_01"), { 0.07, 0.93, 0.07, 0.93 }
    end
    artCache[key] = a
    return a
end
-- 10-07 用户截图「这个图片丑了点」：原来把 2:1 的副本图压进 20:1 的长条 → 又糊又变形。
--   按显示框的宽高比从画面中间裁一块（只裁不拉伸）：框更扁 → 上下裁；框更方 → 左右裁
function ns.ArtCoord(art, w, h)
    local g = art and art.region
    if not g or not w or not h or h <= 0 then return 0, 1, 0, 1 end
    local l, r, t, b, src = g[1], g[2], g[3], g[4], g[5]
    local want = w / h
    if want > src then
        local f = src / want                      -- 只要画面高度的这么多
        local mid, half = (t + b) / 2, (b - t) * f / 2
        return l, r, mid - half, mid + half
    else
        local f = want / src
        local mid, half = (l + r) / 2, (r - l) * f / 2
        return mid - half, mid + half, t, b
    end
end

-- 10-10 首领头像：冒险手册 UI-EJ-BOSS-*（128×64，半身像居中偏左，内容约 4–107px）；客户端里没有就不画
local bossCache = {}
function ns.BossPortrait(b)
    local k = b and b.ej
    if not k then return nil end
    if bossCache[k] == nil then
        local p = "Interface\\EncounterJournal\\UI-EJ-BOSS-" .. k
        bossCache[k] = hasFile(p) and p or false
    end
    return bossCache[k] or nil
end

-- 10-10 二期：掉率（经典理论值，《无限》可能调过）→ "33%" / "0.5%" / "0.03%"
local function pctText(p)
    if not p then return nil end
    if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
    if p >= 1 then return (string.format("%.1f%%", p):gsub("%.0%%", "%%")) end
    return (string.format("%.2f%%", p):gsub("0%%$", "%%"))
end
ns.PctText = pctText
-- 精英 / 稀有（首领名单之外有专属掉落的）
local RARE_TAG = { [1] = { "精英", "Elite" }, [2] = { "稀有精英", "Rare Elite" }, [3] = { "首领", "Boss" }, [4] = { "稀有", "Rare" } }
local function rareTag(b)
    local t = b.rare and RARE_TAG[b.rare]
    return t and ("|cffc0a060[" .. ns.L(t[1], t[2]) .. "]|r ") or ""
end

local function dungeonInfo(d)   -- 等级段 / 地点（Data.dungeons 里按名字找）
    for _, x in ipairs(ns.Data.dungeons or {}) do
        if x.n == d.n or x.nEn == d.nEn or (d.nEn or ""):find(x.nEn or "\001", 1, true) then return x end
    end
end

-- ---------- 页面 ----------
local page, selD, selB = nil, 1, nil

-- 《无限》新物品是新编号（25xxxx+），经典旧世原有物品编号小 —— 「客户端挖掘」标签只对新物品有意义
local function isForeverNew(it) return (it.id or 0) >= 200000 end

-- ⛔ 10-07 用户截图（通灵学院「惊骇之爪」悬停只有名字和等级）「客户端属性呢」：
--   先用游戏原生的物品提示（带服务器下发的真实属性）；第一次悬停时客户端常常还没缓存这件 →
--   以前直接退回我们自己的简版、之后再也不刷新。现在退回时顺手向服务器要数据，
--   GET_ITEM_INFO_RECEIVED 回来且鼠标还停在这一行 → 换成原生提示。
local hoverRow
local reqAt = {}   -- 物品 ID → 第一次向服务器要数据的时间（超过 3 秒没回就不再说「正在读取」）
local function itemTooltip(row)
    local hd = row.headE
    if hd and type(row.it) ~= "table" then   -- 10-11 用户截图「没显示全，不行加 TOOLTIP」：首领 / 稀有标题行悬停看全
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(hd.head, 1, 0.82, 0)
        if hd.sub then GameTooltip:AddLine(ns.EnSafe(hd.sub), 1, 1, 1, true) end
        local b = hd.rareB
        if b and (b.ui or 0) > 0 then
            GameTooltip:AddLine(_G.TomTom and ns.L("点击：用 TomTom 打点（所有刷新点）", "Click: TomTom waypoints (all spawns)")
                or ns.L("点击：在地图上标记 · 聊天框给 /way 坐标", "Click: map pin + /way in chat"), 0.2, 1, 0.6, true)
        end
        GameTooltip:Show()
        return
    end
    local it = row.it
    if not it then return end
    hoverRow = row
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
    local name = (GameTooltip:NumLines() or 0) > 0 and _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
    if not ok or not name or name == "" or name == RETRIEVING_ITEM_INFO then
        ns.ItemFallbackTip(it)
    end
    GameTooltip:Show()
end
-- 物品没缓存时的简版提示（三处共用）：名字 / 部位 / 我们数据里的属性（经典原版的注明）/ 装等需要等级 / 读取状态
function ns.ItemFallbackTip(it0)
    local it = (it0 and idx[it0.id] and idx[it0.id].it) or it0     -- 升级规划那边的条目没属性 → 用掉落数据里同一件
    do
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, it.id)
        elseif GetItemInfo then pcall(GetItemInfo, it.id) end
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff" .. (QCOLOR[it.q] or "ffffff") .. nm(it) .. "|r")
        -- 10-07 用户截图：中文界面不再附英文原名（「Horned Viking Helmet」）
        GameTooltip:AddLine((it.slot or "") .. " " .. (it.type or ""), 1, 1, 1)
        for k, s in ipairs(ns.zh and it.st or it.stEn or {}) do GameTooltip:AddLine(s, 1, 1, 1) end
        GameTooltip:AddLine(ns.L("物品等级 ", "Item level ") .. (it.ilvl or 0) .. ns.L("　需要等级 ", "  Requires level ") .. (it.req or 0), 1, 0.82, 0)
        local st = ns.zh and it.st or it.stEn or {}
        -- 10-07 用户截图「都拿不到数据？」：以前一直写「正在读取」，可《无限》服务器上有些经典编号根本没有 → 永远读不到。
        --   客户端说没有这件 → 直说；问了 3 秒还没回 → 改口「服务器没给」；经典原版数值要注明可能已调整
        local now = GetTime and GetTime() or 0
        reqAt[it.id] = reqAt[it.id] or now
        local exists = true
        if C_Item and C_Item.DoesItemExistByID then local okE, v = pcall(C_Item.DoesItemExistByID, it.id); if okE then exists = v and true or false end end
        if it.stSrc == "classic" and #st > 0 then
            GameTooltip:AddLine(ns.L("经典旧世原版属性（《无限》可能已调整）", "Classic Era values (may differ in Forever)"), 0.6, 0.6, 0.6, true)
        end
        if not exists then
            GameTooltip:AddLine(ns.L("《无限》客户端里没有这件（可能已移除或换了编号）", "Not in the Forever client (removed or renumbered?)"), 1, 0.5, 0.3, true)
        elseif now - reqAt[it.id] > 3 then
            if #st == 0 then GameTooltip:AddLine(ns.L("服务器暂时没给这件的属性", "The server hasn't sent stats for this item"), 0.6, 0.6, 0.6, true) end
        else
            GameTooltip:AddLine(ns.L("正在向服务器读取实时属性…", "Loading live stats from the server…"), 0.6, 0.6, 0.6)
        end
        if not it.seen and isForeverNew(it) then GameTooltip:AddLine(ns.L("客户端里挖到，还没人实际掉过", "Datamined, not yet seen dropping"), 0.6, 0.6, 0.6) end
    end
end
local function tipLeave() hoverRow = nil; GameTooltip:Hide() end
local tipEv = CreateFrame("Frame")
tipEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local function onTipEvent(_, _, itemID)
    local r = hoverRow
    if r and r.it and r.it.id == itemID and GameTooltip:IsOwned(r) then pcall(itemTooltip, r) end
end
tipEv:SetScript("OnEvent", onTipEvent)
ns._lootTipEvent, ns._lootTipLeave = onTipEvent, tipLeave   -- 测试用（照 ns._wishEvent 先例）

local function refresh()
    if not page then return end
    local D = lootList()
    -- 左：副本 + 首领
    local y, n = -2, 0
    for _, r in ipairs(page.left.rows) do r:Hide() end
    local function leftRow()
        n = n + 1
        local r = page.left.rows[n]
        if not r then
            r = CreateFrame("Button", nil, page.left.child)
            r:SetHeight(20)
            r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(18, 18); r.ic:SetPoint("LEFT", 2, 0)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.t:SetPoint("LEFT", 24, 0); r.t:SetPoint("RIGHT", -34, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.c:SetPoint("RIGHT", -6, 0); r.c:SetJustifyH("RIGHT")
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.2, 0.8, 0.6, 0.25)
            page.left.rows[n] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.left.child, "RIGHT", 0, 0)
        r:SetHeight(22)
        y = y - 23
        r:Show()
        return r
    end
    -- 10-07 用户截图「大一点，背景图是不是更好看，那种形式」：副本改成冒险手册那样的大卡片 ——
    --   44 高，铺客户端副本大图（没有就深色底 + 右侧放大的半透明主题图标），左侧暗渐变上压名字 / 等级段 / 件数，选中描金边
    local nc = 0
    local function card()
        nc = nc + 1
        local r = page.left.cards[nc]
        if not r then
            r = CreateFrame("Button", nil, page.left.child)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.10, 0.09, 0.07, 1)
            r.img = r:CreateTexture(nil, "BORDER"); r.img:SetAllPoints()
            r.big = r:CreateTexture(nil, "BORDER"); r.big:SetSize(40, 40); r.big:SetPoint("RIGHT", -4, 0); r.big:SetAlpha(0.55)
            r.shade = r:CreateTexture(nil, "ARTWORK"); r.shade:SetAllPoints(); r.shade:SetColorTexture(1, 1, 1, 1)
            if r.shade.SetGradient and CreateColor then
                r.shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.9), CreateColor(0, 0, 0, 0.15))
            else r.shade:SetColorTexture(0, 0, 0, 0.5) end
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.t:SetPoint("TOPLEFT", 8, -6); r.t:SetPoint("RIGHT", -40, 0); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.lv = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.lv:SetPoint("BOTTOMLEFT", 8, 6); r.lv:SetPoint("RIGHT", -40, 0); r.lv:SetJustifyH("LEFT"); r.lv:SetWordWrap(false)
            r.c = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.c:SetPoint("BOTTOMRIGHT", -6, 6); r.c:SetJustifyH("RIGHT")
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.10)
            -- 选中：金边（四条细线）
            r.sel = {}
            for i, pt in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2 }, { "TOPRIGHT", "BOTTOMRIGHT", 2 } }) do
                local l = r:CreateTexture(nil, "OVERLAY"); l:SetColorTexture(1, 0.82, 0, 0.9)
                l:SetPoint(pt[1]); l:SetPoint(pt[2])
                if pt[3] then l:SetWidth(pt[3]) else l:SetHeight(pt[4]) end
                r.sel[i] = l
            end
            page.left.cards[nc] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y); r:SetPoint("RIGHT", page.left.child, "RIGHT", -2, 0)
        r:SetHeight(44)
        y = y - 47
        r:Show()
        return r
    end
    for _, r in ipairs(page.left.cards) do r:Hide() end
    for di, d in ipairs(D) do
        local cnt = 0
        for _, b in ipairs(d.bosses) do cnt = cnt + #b.items end
        local r = card()
        local art, info = ns.DungeonArt(d), dungeonInfo(d)
        if art.banner then
            r.img:SetTexture(art.banner); r.img:SetTexCoord(ns.ArtCoord(art, (r:GetWidth() or 0) > 50 and r:GetWidth() or 186, 44)); r.img:Show(); r.big:Hide()
        else
            r.img:Hide(); r.big:SetTexture(art.icon); r.big:SetTexCoord(unpack(art.iconCoord)); r.big:Show()
        end
        r.img:SetDesaturated(cnt == 0); r.big:SetDesaturated(cnt == 0)
        -- 还没掉落数据的副本灰掉
        r.t:SetText((cnt > 0 and "|cffffd100" or "|cff8a8a8a") .. nm(d) .. "|r")
        r.lv:SetText(ns.EnSafe((info and (info.lv or "") ~= "") and (ns.L("等级 ", "Lv ") .. info.lv) or ""))
        r.c:SetText(cnt > 0 and ("|cffffffff" .. cnt .. "|r") or ("|cff777777" .. ns.L("待补", "tbd") .. "|r"))
        local on = selD == di
        for _, l in ipairs(r.sel) do l:SetShown(on) end
        r:SetScript("OnClick", function() selD, selB = di, nil; refresh() end)
        r:SetScript("OnEnter", function(self)   -- 名字长被截 → 悬停看全（用户硬规定）
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(nm(d), 1, 0.82, 0)
            if info then GameTooltip:AddLine(ns.EnSafe(ns.L("等级 ", "Level ") .. (info.lv or "?") .. ns.L(" · ", " - ") .. ns.L(info.where or "", info.whereEn or "")), 1, 1, 1) end
            GameTooltip:AddLine(string.format(d.virtual and ns.L("%d 个稀有 · %d 件掉落", "%d rares · %d items") or ns.L("%d 个首领 · %d 件掉落", "%d bosses · %d items"), #d.bosses, cnt), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if selD == di then
            for bi, b in ipairs(d.bosses) do
                local rb = leftRow()
                local bp = ns.BossPortrait(b)
                if bp then   -- 正方形取头部那块：x 23–87 / 128（半身像中心约在 55px）
                    rb.ic:SetTexture(bp); rb.ic:SetTexCoord(0.18, 0.68, 0, 1); rb.ic:Show()
                    rb.t:SetPoint("LEFT", rb.ic, "RIGHT", 4, 0)
                else
                    rb.ic:Hide(); rb.t:SetPoint("LEFT", 14, 0)
                end
                rb.t:SetText(rareTag(b) .. "|cffdddddd" .. nm(b) .. "|r")
                rb.c:SetText(#b.items > 0 and ("|cff888888" .. #b.items .. "|r") or "")
                rb.sel:SetShown(selB == bi)
                rb:SetScript("OnClick", function() selB = bi; refresh() end)
            end
        end
    end
    page.left.child:SetHeight(-y + 4)

    -- 右上：副本横幅（大图 + 名字 + 等级段 / 地点 / 件数）
    local d = D[selD]
    if d then
        local art, info = ns.DungeonArt(d), dungeonInfo(d)
        local bn = page.banner
        if art.banner then
            bn.img:SetTexture(art.banner); bn.img:SetTexCoord(ns.ArtCoord(art, 420, 66)); bn.img:Show(); bn.big:Hide()
        else
            bn.img:Hide(); bn.big:SetTexture(art.icon); bn.big:SetTexCoord(unpack(art.iconCoord)); bn.big:Show()
        end
        local cnt = 0
        for _, b in ipairs(d.bosses) do cnt = cnt + #b.items end
        bn.name:SetText(nm(d))
        local sub = {}
        if info and (info.lv or "") ~= "" then sub[#sub + 1] = ns.L("等级 ", "Level ") .. info.lv end
        if info and (info.where or "") ~= "" then sub[#sub + 1] = ns.L(info.where, info.whereEn or info.where) end
        sub[#sub + 1] = string.format(d.virtual and ns.L("%d 个稀有 · %d 件掉落", "%d rares · %d items") or ns.L("%d 个首领 · %d 件掉落", "%d bosses · %d items"), #d.bosses, cnt)
        bn.sub:SetText(ns.EnSafe(table.concat(sub, ns.L(" · ", " - "))))
        -- 10-10「主要是副本任务」：横幅右侧「副本任务 N」→ 弹框列出这个副本该提前接的任务
        local dq = ns.DQForDungeon and ns.DQForDungeon(d.n, d.nEn)
        local nq = 0
        if dq then for _, e in ipairs(ns.DQList(dq)) do if e.s ~= "done" then nq = nq + 1 end end end
        bn.dq:SetText(ns.L("副本任务 ", "Quests ") .. nq)
        bn.dq:SetShown(dq ~= nil)
        bn.dq.d = dq
        local ent = dq and dq.ent
        bn.ent.e = (ent and (ent.ui or 0) > 0 and (ent.x or 0) > 0) and ent or nil
        bn.ent:SetShown(bn.ent.e ~= nil)
        bn:Show()
    else
        page.banner:Hide()
    end
    -- 右：装备列表（选了首领只看该首领，否则整本）
    for _, r in ipairs(page.right.rows) do r:Hide() end
    local list = {}
    if d then
        for bi, b in ipairs(d.bosses) do
            if not selB or selB == bi then
                list[#list + 1] = { head = nm(b), tag = rareTag(b), sub = d.virtual and rareLoc(b) or nil, portrait = ns.BossPortrait(b),
                    rareB = d.virtual and b or nil }
                for _, it in ipairs(b.items) do list[#list + 1] = { it = it } end
                if #b.items == 0 then list[#list + 1] = { empty = true } end
            end
        end
    end
    -- 10-07 用户「优化」：一行挤「名字 部位 类型 装等 需要」对不齐 → 图标 + 两行（名字 / 灰色小字属性）
    local ry = -2
    for k, e in ipairs(list) do
        local r = page.right.rows[k]
        if not r then
            r = CreateFrame("Button", nil, page.right.child)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 0.82, 0, 0.07)
            r.star = CreateFrame("Button", nil, r)
            r.star:SetSize(18, 18); r.star:SetPoint("LEFT", 2, 0)
            r.star.tex = r.star:CreateTexture(nil, "ARTWORK"); r.star.tex:SetAllPoints()
            r.star.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            r.pt = r:CreateTexture(nil, "ARTWORK"); r.pt:SetSize(56, 32); r.pt:SetPoint("LEFT", 2, 0)   -- 首领头像（冒险手册 128×64，取左 112px）
            r.pt:SetTexCoord(0, 0.875, 0, 1)
            r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(28, 28); r.ic:SetPoint("LEFT", 24, 0)
            r.ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
            r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.s:SetPoint("BOTTOMLEFT", 58, 3); r.s:SetPoint("RIGHT", -6, 0); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
            r.s:SetTextColor(0.6, 0.6, 0.6)
            r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.tag:SetPoint("TOPRIGHT", -6, -4)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            r:SetScript("OnEnter", itemTooltip)
            r:SetScript("OnClick", function(self) if self.headE and self.headE.rareB and type(self.it) ~= "table" then ns.MarkRare(self.headE.rareB) end end)
            r:SetScript("OnLeave", tipLeave)
            page.right.rows[k] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, ry); r:SetPoint("RIGHT", page.right.child, "RIGHT", 0, 0)
        r.it = e.it
        r.t:ClearAllPoints(); r.s:SetText(""); r.tag:SetText(""); r.bg:Hide()
        local h
        r.pt:SetShown(e.portrait ~= nil)
        r.headE = e.head and e or nil
        if e.head or e.empty then
            h = e.head and (e.portrait and 36 or 24) or 20
            r.ic:Hide(); r.star:Hide()
            if e.portrait then r.pt:SetTexture(e.portrait) end
            r.t:SetPoint("LEFT", e.portrait and 62 or 4, (e.head and not e.portrait) and -2 or 0); r.t:SetPoint("RIGHT", -6, 0)
            r.t:SetText(e.head and ((e.tag or "") .. "|cffffd100" .. e.head .. "|r" .. (e.sub and ("  |cff999999" .. ns.EnSafe(e.sub) .. "|r") or "")) or ("|cff777777" .. ns.L("还没有掉落数据", "No drop data yet") .. "|r"))
        else
            h = 34
            local it = e.it
            -- 10-11《无限》新物品没有图标名：先问客户端（GetItemIconByID），再用数据里的 FileDataID，最后问号
            local icon = (it.i and it.i ~= "") and ("Interface\\Icons\\" .. it.i) or nil
            if not icon and C_Item and C_Item.GetItemIconByID then local okI, v = pcall(C_Item.GetItemIconByID, it.id); if okI and v then icon = v end end
            r.ic:SetTexture(icon or it.ic or "Interface\\Icons\\inv_misc_questionmark"); r.ic:Show()
            r.t:SetPoint("TOPLEFT", 58, -3); r.t:SetPoint("RIGHT", -60, 0)
            r.t:SetText("|cff" .. (QCOLOR[it.q] or "ffffff") .. nm(it) .. "|r")
            local slot = it.slot or ""
            if it.type and it.type ~= "" and it.type ~= slot then slot = slot .. " · " .. it.type end
            local pt = pctText(it.p)
            r.s:SetText(ns.EnSafe(slot .. "　" .. ns.L("装等 ", "ilvl ") .. (it.ilvl or 0) .. ns.L(" · 需要 ", " · req ") .. (it.req or 0)
                .. (pt and (ns.L(" · 掉率约 ", " · drop ~") .. pt) or "")))
            -- 10-11 玩家实测过的《无限》新掉落（seen）标「无限新增」；客户端挖到但没人确认的照旧「客户端挖掘」
            if isForeverNew(it) then r.tag:SetText(it.seen and ("|cffe8b04a" .. ns.L("无限新增", "Forever") .. "|r") or ns.L("客户端挖掘", "datamined")) end
            r.star:Show()
            local on = isWished(it.id)
            r.bg:SetShown(on)
            r.star.tex:SetDesaturated(not on)
            r.star.tex:SetAlpha(on and 1 or 0.35)
            r.star:SetScript("OnClick", function()
                wish()[it.id] = (not on) or nil
                refresh()
            end)
        end
        r:SetHeight(h)
        r:Show()
        ry = ry - h - 2
    end
    page.right.child:SetHeight(-ry + 4)

    local nw = 0
    for _ in pairs(wish()) do nw = nw + 1 end
    page.foot:SetText(ns.L("心愿单 ", "Wishlist: ") .. "|cffffd100" .. nw .. "|r" .. ns.L(" 件 · 进副本 / 开打首领 / 拾取时提醒", " · alerts on entering / pull / loot"))
    page.clearWish:SetEnabled(nw > 0)
end

local function build(p)
    page = p
    ns.LootPage = p   -- 测试 / 调试用（照 ns.PlanPage 先例）
    ns.PageHeader(p, ns.L("掉落 · 心愿单", "Loot · Wishlist"), ns.L("点星标加入心愿单", "Star an item to add it to your wishlist"))
    -- 底部只留一行：心愿单件数 + 清空；掉落记录导出统一走「公测数据」页（10-07「没用的按钮太多了」）
    local h = 474 - 42 - 40
    local sf, c = ns.Scroll(p, 8, -42, 190, h)
    p.left = { sf = sf, child = c, rows = {}, cards = {} }
    local lbg = p:CreateTexture(nil, "BACKGROUND"); lbg:SetPoint("TOPLEFT", sf, -2, 2); lbg:SetPoint("BOTTOMRIGHT", sf, 2, -2)
    lbg:SetColorTexture(1, 1, 1, 0.03)
    -- 右上副本横幅：有客户端副本图就铺满，没有就左边放大图标；文字压在左侧暗渐变上
    local bn = CreateFrame("Frame", nil, p); bn:SetPoint("TOPLEFT", 226, -42); bn:SetSize(420, 66)
    bn.bg = bn:CreateTexture(nil, "BACKGROUND"); bn.bg:SetAllPoints(); bn.bg:SetColorTexture(0.08, 0.07, 0.05, 0.9)
    bn.img = bn:CreateTexture(nil, "BORDER"); bn.img:SetAllPoints()
    bn.big = bn:CreateTexture(nil, "ARTWORK"); bn.big:SetSize(52, 52); bn.big:SetPoint("RIGHT", -10, 0)
    bn.shade = bn:CreateTexture(nil, "ARTWORK"); bn.shade:SetAllPoints()
    bn.shade:SetColorTexture(1, 1, 1, 1)
    if bn.shade.SetGradient and CreateColor then
        bn.shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0.05))
    else bn.shade:SetColorTexture(0, 0, 0, 0.45) end
    bn.edge = bn:CreateTexture(nil, "OVERLAY"); bn.edge:SetPoint("BOTTOMLEFT"); bn.edge:SetPoint("BOTTOMRIGHT"); bn.edge:SetHeight(1)
    bn.edge:SetColorTexture(1, 0.82, 0, 0.6)
    bn.name = bn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); bn.name:SetPoint("TOPLEFT", 12, -12)
    bn.name:SetPoint("RIGHT", -236, 0); bn.name:SetJustifyH("LEFT"); bn.name:SetWordWrap(false)
    bn.sub = bn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bn.sub:SetPoint("TOPLEFT", bn.name, "BOTTOMLEFT", 0, -6)
    bn.sub:SetPoint("RIGHT", -236, 0); bn.sub:SetJustifyH("LEFT"); bn.sub:SetWordWrap(false)
    bn.dq = ns.Button(bn, "", 100, 22, function(self) if self.d then ns.ShowDungeonQuests(self.d, page) end end)
    bn.dq:SetPoint("RIGHT", -70, 0)
    bn.dq:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("这个副本的任务", "Quests for this dungeon"), 1, 0.82, 0)
        GameTooltip:AddLine(ns.L("数字 = 你还没做的（能接 / 已接 / 先做前置 / 等级不够）。进本前先接好，经验和装备多拿一截", "Number = not yet done. Pick them up before you go in"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bn.dq:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 10-10 四期「入口」：《无限》客户端没有副本地图（UiMap 只有大陆 / 地区）→ 改成在世界地图上给副本入口插旗
    bn.ent = ns.Button(bn, ns.L("入口", "Entrance"), 56, 22, function(self) ns.MarkEntrance(self.e) end)
    bn.ent:SetPoint("RIGHT", bn.dq, "LEFT", -4, 0)
    bn.ent:SetScript("OnEnter", function(self)
        local e = self.e
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("副本入口", "Dungeon entrance"), 1, 0.82, 0)
        if e then GameTooltip:AddLine(ns.EnSafe(ns.L(e.zc or "", e.ze or "") .. string.format(" %.1f, %.1f", e.x or 0, e.y or 0)), 1, 1, 1) end
        GameTooltip:AddLine(ns.L("点一下在世界地图上标记", "Click to pin it on the world map"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    bn.ent:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bn:EnableMouse(true)
    bn:SetScript("OnEnter", function(self)   -- 显示不全 → 悬停看全（用户硬规定）
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(self.name:GetText() or "", 1, 0.82, 0)
        GameTooltip:AddLine(self.sub:GetText() or "", 1, 1, 1, true); GameTooltip:Show()
    end)
    bn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.banner = bn
    local sf2, c2 = ns.Scroll(p, 226, -42 - 72, 400, h - 72)
    p.right = { sf = sf2, child = c2, rows = {} }
    p.foot = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.foot:SetPoint("BOTTOMLEFT", 12, 12); p.foot:SetJustifyH("LEFT")
    p.clearWish = ns.Button(p, ns.L("清空心愿单", "Clear wishlist"), 96, 22, function() ns.db.wish = {}; refresh() end)
    p.clearWish:SetPoint("BOTTOMRIGHT", -10, 6)
    local src = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    src:SetPoint("RIGHT", p.clearWish, "LEFT", -10, 0); src:SetJustifyH("RIGHT")
    src:SetText(ns.L("数据：foreverchanges.pro", "Data: foreverchanges.pro"))
end

-- 升级规划「装备」格子点一下 → 跳到掉落页那个副本（10-07 用户「装备像 C 键角色栏」，插件-工会会话转达）
function ns.LootShowDungeon(name)
    for i, d in ipairs(lootList()) do
        if d.n == name then selD, selB = i, nil; break end
    end
    ns.ToggleMain("loot")
    refresh()
end

ns.RegisterPage({ key = "loot", order = 2, title = ns.L("掉落 · 心愿单", "Loot"), tabTitle = ns.L("掉落", "Loot"), build = build, refresh = refresh })

-- ---------- 提醒 ----------
local function notice(msg)
    ns.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function sameName(a, x)
    if not a or a == "" then return false end
    return a == x.n or a:lower() == (x.nEn or ""):lower()
end

local function wishedIn(boss)
    local out = {}
    for _, it in ipairs(boss.items) do if isWished(it.id) then out[#out + 1] = nm(it) end end
    return out
end

local function onEnterInstance()
    if not IsInInstance or not IsInInstance() then return end
    local name = GetInstanceInfo and GetInstanceInfo()
    for _, d in ipairs(ns.Data.loot.dungeons or {}) do
        if sameName(name, d) then
            local all = {}
            for _, b in ipairs(d.bosses) do
                local w = wishedIn(b)
                if #w > 0 then all[#all + 1] = nm(b) .. "：" .. table.concat(w, "、") end
            end
            if #all > 0 then notice(ns.EnSafe(ns.L("心愿单 · 本副本能掉 → ", "Wishlist in this dungeon -> ") .. table.concat(all, "；"))) end
            return
        end
    end
end

local function onEncounter(encName)
    for _, d in ipairs(ns.Data.loot.dungeons or {}) do
        for _, b in ipairs(d.bosses) do
            if sameName(encName, b) then
                local w = wishedIn(b)
                if #w > 0 then notice(ns.EnSafe(ns.L("心愿单 · 这个首领掉 ", "Wishlist: this boss drops ") .. table.concat(w, "、"))) end
                return
            end
        end
    end
end

local function onLoot()
    if not GetNumLootItems then return end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and isWished(id) then notice(ns.L("心愿单装备掉了：", "Wishlist item dropped: ") .. link) end
    end
end

-- ---------- 物品鼠标提示 ----------
local function addItemLine(tt, id)
    if not id or tt.__gifItem == id then return end
    local e = idx[id]
    if not e then return end
    tt.__gifItem = id
    tt:AddLine("|cff33ff99GI|r " .. ns.L("掉落：", "Drops: ") .. nm(e.d) .. " · " .. nm(e.b), 1, 0.82, 0.4)
    if isWished(id) then tt:AddLine("|cff33ff99GI|r " .. ns.L("在你的心愿单里", "On your wishlist"), 1, 0.82, 0) end
    tt:Show()
end

local function hookItems()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            local id = data and data.id
            if ns.Secret(id) or not id then return end
            if ns.TranslateTip then pcall(ns.TranslateTip, tt, id and idx[id] and idx[id].it.n) end
            pcall(addItemLine, tt, id)
        end)
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt then
            tt:HookScript("OnTooltipCleared", function(self) self.__gifItem = nil end)
            if tt:HasScript("OnTooltipSetItem") then
                tt:HookScript("OnTooltipSetItem", function(self)
                    local _, link = self:GetItem()
                    if ns.Secret(link) then return end
                    local id = link and tonumber(link:match("item:(%d+)"))
                    if ns.TranslateTip and not (TooltipDataProcessor and Enum and Enum.TooltipDataType) then
                        pcall(ns.TranslateTip, self, id and idx[id] and idx[id].it.n)
                    end
                    addItemLine(self, id)
                end)
            end
        end
    end
end

table.insert(ns.modules, function()
    buildIndex()
    pcall(hookItems)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("LOOT_OPENED")
    local function onEvent(_, e, a, b)
        if e == "ENCOUNTER_START" then pcall(onEncounter, b)
        elseif e == "LOOT_OPENED" then pcall(onLoot)
        else C_Timer.After(2, function() pcall(onEnterInstance) end) end
    end
    f:SetScript("OnEvent", onEvent)
    ns._wishEvent = onEvent
end)

ns.LootIndex = idx
