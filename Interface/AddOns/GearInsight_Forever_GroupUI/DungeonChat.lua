-- 11-10 用户（截图右侧「组队」抽屉）：「组队」下面两个子页签：任务组队（原来的附近同任务）+ 副本组队（这里）。
--   副本组队 = 读聊天频道（综合 / 交易 / 寻求组队 / 大脚世界频道……所有加入的频道）里的组队消息：
--   求组：最上面选我的职责（坦克 / 治疗 / 伤害输出；只能打输出的职业另外两个置灰、自动选输出）→
--         下面列出识别到的组队消息：副本名 + 建议等级 + 缺什么职责（没写就写「没写职责」）+ 谁 · 多久前 → 「申请」=
--         自动私聊队长（带我的职业 / 等级 / 职责）；之后 10 分钟内只自动接受这个队长的组队邀请（用户 11-10 选「只自动接我密过的队长」）
--   招人：选副本（显示建议等级）+ 等级范围拖动条（最低 / 最高）+ 需要的职责多选 + 发到哪些频道 → 一键发到勾选的频道；
--         发完 15 分钟内密我的人列在下面，点「邀请」；11-13 起这份名单存进存档一直留着（重新喊话 / 重载不清），「清空」/ 行尾 × 才删
--   ⛔ 发频道 / 私聊 / 邀请都只在按钮点击里调（硬件事件）；读聊天只注册 CHAT_MSG_CHANNEL / CHAT_MSG_WHISPER，不碰暴雪聊天框
--   界面挂进 QuestMates 抽屉的 d.lfg 盖板（ns.BuildDungeonPanel），没加载这个文件 = 抽屉和以前一样
local _, ns = ...; ns = _G.GearInsightForever or ns
local L = function(cn, en) return ns.L(cn, en) end

-- 11-13 界面重构第 5 期：DC 表本身、存档、前缀、名字 / 人数小工具、满员通知、交易法师要吃喝搬进登录加载的
--   GearInsight_Forever_Group/DungeonChatCore.lua（法师吃喝也要用）；这里是面板 + 读频道 + 来密我的人 + 自动反问，打开副本组队才加载
local DC = ns.DungeonChat
if not DC then return end
local now, clean, short, lowerAscii = DC._now, DC._clean, DC.Short, DC.LowerAscii
local me, fullName, isMe = DC._me, DC.FullName, DC._isMe

-- ---------- 副本表：名字 + 建议等级（ns.Data.leveling.dungeons）+ 常用叫法 ----------
-- 叫法照国服聊天习惯；英文缩写按整词认（%f 边界；⛔ 用 a-z0-9 字节范围，别用 %a / %w：跟区域设置走，中文字节可能被当成字母），「DM」死亡矿井 / 厄运之槌两边都有人叫，不认
local ALIAS = {
    ["怒焰裂谷"] = { "怒焰", "rfc" }, ["哀嚎洞穴"] = { "哀嚎", "wc", "哀嚎洞" }, ["死亡矿井"] = { "死矿", "死亡矿井", "vc" },
    ["影牙城堡"] = { "影牙", "sfk", "sk" }, ["黑暗深渊"] = { "黑暗深渊", "黑暗", "深渊", "bfd" }, ["暴风城监狱"] = { "监狱", "stockade", "stocks" },
    ["血色修道院"] = { "血色", "sm", "smgy", "smlib", "smarm", "smcath", "墓地", "图书馆", "军械库", "武器库", "大教堂", "教堂" },
    ["诺莫瑞根"] = { "诺莫瑞根", "诺莫", "矮子", "gnomer", "gnome" }, ["剃刀沼泽"] = { "剃刀沼泽", "沼泽", "rfk" }, ["剃刀高地"] = { "剃刀高地", "高地", "rfd" },
    ["奥达曼"] = { "奥达曼", "uld", "ulda" }, ["祖尔法拉克"] = { "祖尔", "zf", "zul" }, ["玛拉顿"] = { "玛拉顿", "玛拉", "mara" },
    ["沉没的神庙"] = { "神庙", "阿塔哈卡", "st" }, ["黑石深渊"] = { "黑石深渊", "brd" },
    ["厄运之槌"] = { "厄运", "dme", "dmw", "dmn" }, ["黑石塔下层"] = { "黑下", "黑石塔下", "lbrs" },
    ["黑石塔上层"] = { "黑上", "黑石塔上", "ubrs" }, ["通灵学院"] = { "通灵", "scholo", "scholomance", "通灵学院" },
    ["斯坦索姆"] = { "斯坦索姆", "斯坦", "stsm", "strat", "strath" },
}
local WINGS = { "墓地", "图书馆", "军械库", "武器库", "大教堂", "东区", "西区", "北区", "正门", "主门", "侧门", "后门" }

local function range(s)
    local a, b = tostring(s or ""):match("(%d+)%D+(%d+)")
    if a then return tonumber(a), tonumber(b) end
    local x = tonumber(tostring(s or ""):match("(%d+)"))
    return x, x
end

function DC.Dungeons()
    if DC._dungeons then return DC._dungeons end
    local out = {}
    local src = ns.Data and ns.Data.leveling and ns.Data.leveling.dungeons or {}
    for _, d in ipairs(src) do
        local lo, hi = range(d.lv)
        local keys = { d.n }
        for _, a in ipairs(ALIAS[d.n] or {}) do keys[#keys + 1] = a end
        if d.nEn and d.nEn ~= "" then keys[#keys + 1] = lowerAscii(d.nEn) end
        out[#out + 1] = { n = d.n, en = d.nEn or d.n, lo = lo or 1, hi = hi or 60, keys = keys }
    end
    DC._dungeons = out
    return out
end

-- ---------- 识别一条聊天 ----------
-- 11-10 用户截图「SK 有吗」：「有吗 / 有没有」也算求组（问有没有队）
local LFG_WORDS = { "求组", "求带", "求队", "找队", "有队吗", "带一个", "带个", "有吗", "有没有", "组我", "带我", "算我", "lfg" }
local LFM_WORDS = { "缺", "差", "来个", "来一个", "来位", "招", "速来", "组人", "密我", "m我", "lfm", "+1", "来人",
    -- 11-10 用户截图「大脚和组队频道都要看啊」：大脚世界频道常见「黑暗深渊来T奶」「深渊任务队来TN」「血色4本 清任务来DPS」「N4=1」
    "来t", "来n", "来奶", "来坦", "来d", "来治疗", "来输出", "来法", "来猎", "来战", "来骑", "来牧", "来萨", "来术", "来贼", "来德", "来aa",
    "来两", "来俩", "来三", "来1", "来2", "来3", "任务队", "队来", "清任务" }
-- 职责词 / 去颜色码 / 认词：11-13 搬进小核（DungeonChatCore.lua，来密我的人在那边收），这里照旧用
local ROLE_WORDS, strip, has = DC.ROLE_WORDS, DC.StripCodes, DC.HasWord

local function matchDungeon(lower)
    local best, bestLen, bestKey
    for i, d in ipairs(DC.Dungeons()) do
        for _, k in ipairs(d.keys) do
            local hit
            if k:find("^[a-z0-9 ']+$") then
                hit = lower:find("%f[a-z0-9]" .. k:gsub("([^a-z0-9])", "%%%1") .. "%f[^a-z0-9]")
            else
                hit = lower:find(k, 1, true)
            end
            if hit and (not bestLen or #k > bestLen) then best, bestLen, bestKey = i, #k, k end
        end
    end
    return best, bestKey
end

-- → { d = 副本序号, wing, lfg = 是不是求组（不是招人）, roles = { TANK = true… }, lo, hi } 或 nil（不是组队消息）
-- 「适合我等级」：低 2 级以内可以跟着去；超过建议上限就不算（11-10 用户「我20级了，为啥还有13-18的」）
function DC.FitsLevel(d, lv)
    return lv >= d.lo - 2 and lv <= d.hi
end

function DC.Parse(msg)
    msg = clean(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    -- 别人的 GI 插件喊的话照样认（那是真组队消息），只是先去掉前缀再识别
    local text = DC.StripTag(strip(msg))
    local lower = lowerAscii(text)
    local di, key = matchDungeon(lower)
    if not di then return nil end
    -- 认职责前先去掉副本名：「斯坦索姆」里的「坦」不是缺坦克
    local roleText = lower:gsub(key:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"), " ")
    -- 去空格再认（「来 T奶」）；「4=1」「N4==1」「3=2」这种人数也算招人
    local tight = lower:gsub("%s+", "")
    local lfg, lfm = has(tight, LFG_WORDS), has(tight, LFM_WORDS) or tight:find("%d=+%d") ~= nil
    if not lfg and not lfm then return nil end
    local p = { d = di, lfg = lfg and not lfm, roles = {}, text = text }
    for _, w in ipairs(WINGS) do if text:find(w, 1, true) then p.wing = w; break end end
    for role, words in pairs(ROLE_WORDS) do
        if has(roleText, words) then p.roles[role] = true end
    end
    local a, b = text:match("(%d%d?)%s*[%-~到]%s*(%d%d?)")
    if a then p.lo, p.hi = tonumber(a), tonumber(b)
    else
        local x = text:match("(%d%d?)%s*级") or text:match("(%d%d?)%+")
        if x then p.lo = tonumber(x) end
    end
    return p
end


-- 11-10 用户截图「人的等级职业列出来」：职业从聊天事件带的 GUID 读（GetPlayerInfoByGUID，陌生人也有）；
--   等级聊天里没有 → 公会名单 / 同队 / 好友能查到就显示（GuildChatLevel.Info），查不到不写
--   DC.WhoOf / DC.TextLevel 11-13 搬进小核（DungeonChatCore.lua）
-- 11-11 用户截图「来密我的人」「这里为啥没显示等级」：陌生人不在公会 / 队伍 / 好友里，聊天事件不带等级 →
--   ① 附近能看到的（目标 / 鼠标 / 焦点 / 姓名板）直接读 UnitLevel；② 他话里写了等级（「20 LR求组」「25级」）就用；都没有才空着
local function nearbyLevel(s)
    if not (s and UnitExists and UnitName and UnitLevel) then return nil end
    local units = { "target", "mouseover", "focus" }
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, u in ipairs(units) do
        if UnitExists(u) and (not UnitIsPlayer or UnitIsPlayer(u)) then
            local n = clean(UnitName(u))
            if n and (n == s or fullName(u) == s) then
                local l = tonumber(clean(UnitLevel(u)))
                if l and l > 0 then return l end
            end
        end
    end
end
DC.NearbyLevel = nearbyLevel
function DC.LevelOf(p)
    local GL = ns.GuildChatLevel
    local lv
    if GL and GL.Info then local ok, l = pcall(GL.Info, p.author); if ok then lv = l end end
    -- 文字里的等级只认私聊（频道招人消息里的「18-25级」是招人范围，不是他自己的等级）
    lv = lv or nearbyLevel(p.short) or rawget(p, "lv") or (not p.ch and DC.TextLevel(p.text)) or nil
    if lv then rawset(p, "lv", lv) end   -- 看到过一次就记住（走远了也还显示）
    return lv
end
-- 私聊的人的职责：他说了的（蓝）> 纯输出职业推出来的（灰，法师 / 术士 / 盗贼 / 猎人只能输出）
local PURE_DPS = { MAGE = true, WARLOCK = true, ROGUE = true, HUNTER = true }
function DC.RolesOf(p)
    local rs = {}
    for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do if p.roles and p.roles[r] then rs[#rs + 1] = r end end
    if #rs > 0 then return rs, false end
    if p.cls and PURE_DPS[p.cls] then return { "DAMAGER" }, true end
    return rs, false
end
function DC.WhoText(p)
    local lv = DC.LevelOf(p)
    local col = p.cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.cls]
    local hex = col and (col.colorStr or (col.r and string.format("ff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255))) or nil
    local name = hex and ("|c" .. hex .. p.short .. "|r") or p.short
    local extra = {}
    if lv then extra[#extra + 1] = string.format(L("%d级", "Lv%d"), lv) end
    if p.clsName then extra[#extra + 1] = p.clsName end
    -- 11-12 私聊里说了职责（「奶」「T」「dps」）→ 标出来；职业是招人时选了「要 / 不要」的也标
    if p.reply then
        local rs = {}
        for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do if p.roles and p.roles[r] then rs[#rs + 1] = DC.RoleName(r) end end
        if #rs > 0 then extra[#extra + 1] = "|cff66ccff" .. table.concat(rs, "/") .. "|r" end
        local pick = p.cls and DC.ClsPick(p.cls)
        if pick == "want" then extra[#extra + 1] = "|cff33ff99" .. L("要的职业", "wanted") .. "|r"
        elseif pick == "no" then extra[#extra + 1] = "|cffff5555" .. L("不要的职业", "not wanted") .. "|r" end
    end
    return name .. (#extra > 0 and (" " .. table.concat(extra, " ")) or "")
end

function DC.OnChannel(msg, author, channelBase, guid)
    author = clean(author)
    if not author or isMe(author) then return false end
    local p = DC.Parse(msg)
    if not p then return false end
    p.author, p.short, p.t, p.ch = author, short(author), now(), clean(channelBase)
    p.cls, p.clsName = DC.WhoOf(guid)
    -- 同一个人只留最新一条
    for i = #DC.posts, 1, -1 do if DC.posts[i].short == p.short then table.remove(DC.posts, i) end end
    table.insert(DC.posts, 1, p)
    while #DC.posts > DC.MAX_POSTS do table.remove(DC.posts) end
    DC.dirty = true
    return true
end

-- 11-12 用户截图（招人页「来密」列表）「公会的在这里打个标记」：跟我同公会的人（不含自己）。
--   名单走 GuildChatLevel 的缓存（GUILD_ROSTER_UPDATE 只记脏、最多 5 秒重建一次，按短名比 → 「名字-服务器」也认）；不在公会 = 恒 false
function DC.IsGuild(name)
    local GL = ns.GuildChatLevel
    if type(name) ~= "string" or not (GL and GL.IsGuildmate) then return false end
    local ok, yes = pcall(GL.IsGuildmate, name)
    return ok and yes == true
end
-- 列表里统一的绿色「[公会]」标签 + 悬停提示那一行（求组列表 / 来密我的人 共用）
function DC.GuildTag() return "|cff40ff40[" .. L("公会", "Guild") .. "]|r" end
function DC.GuildTip() return "|cff40ff40" .. L("同公会", "Guildmate") .. "|r" end

function DC.Live()
    local out, t = {}, now()
    for _, p in ipairs(DC.posts) do
        if t - p.t <= DC.TTL then
            p.guild = DC.IsGuild(p.author)
            out[#out + 1] = p
        end
    end
    -- 11-10 用户「公会的人，特别标注」：公会的排前面，其余照新到旧
    local ord = {}
    for i, p in ipairs(out) do ord[p] = i end
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild end
        return ord[a] < ord[b]
    end)
    return out
end

-- ---------- 求组页：按副本筛选（11-13 用户截图「怎么加按副本筛选」）----------
--   存档 DC.DB().dgFilter = { [副本名] = true, … }；nil = 全部副本（一个都没选也存 nil）。按副本名存（数据表顺序变了也不串）
--   分区（血色修道院·图书馆 / 墓地…）不单独筛：识别时 p.d 就是大副本，选「血色修道院」= 所有分区都算
--   「招人」页下面「来密我的人」是密我的玩家、不分副本 → 不共用这个筛选
function DC.DgFilter()
    local f = DC.DB().dgFilter
    if type(f) == "table" and next(f) ~= nil then return f end
    return nil
end
function DC.DgOn(name) local f = DC.DgFilter(); return f ~= nil and f[name] == true end
function DC.SetDg(name, on)
    local db = DC.DB()
    local f = type(db.dgFilter) == "table" and db.dgFilter or {}
    if on then f[name] = true else f[name] = nil end
    if next(f) ~= nil then db.dgFilter = f else db.dgFilter = nil end
end
function DC.ClearDg() DC.DB().dgFilter = nil end
function DC.DgCount()
    local n, f = 0, DC.DgFilter()
    for _ in pairs(f or {}) do n = n + 1 end
    return n
end
function DC.DgPass(p)
    local f = DC.DgFilter()
    if not f then return true end
    local d = DC.Dungeons()[p.d]
    return d ~= nil and f[d.n] == true
end
-- 按钮上的字：全部副本 / 血色修道院 / 已选 3 个副本
function DC.DgLabel()
    local f = DC.DgFilter()
    if not f then return L("全部副本", "All dungeons") end
    local n = DC.DgCount()
    if n == 1 then return (next(f)) end
    return string.format(L("已选 %d 个副本", "%d dungeons"), n)
end
-- 求组列表：先「适合我等级」再按副本 → 列出的, 全部, 等级筛掉几条, 副本筛掉几条
function DC.SeekList(lv)
    local all = DC.Live()
    local onlyMine = DC.DB().fitLv ~= false
    local out, lvOut, dgOut = {}, 0, 0
    for _, p in ipairs(all) do
        local d = DC.Dungeons()[p.d]
        if d then
            if onlyMine and not DC.FitsLevel(d, lv) then lvOut = lvOut + 1
            elseif not DC.DgPass(p) then dgOut = dgOut + 1
            else out[#out + 1] = p end
        end
    end
    return out, all, lvOut, dgOut
end
-- 下拉里的副本 → seen（频道里有人组的，条数多的在前）, idle（适合我等级但暂时没人组的 + 选了但现在没消息的，条数 0 灰显）
--   条数跟着「适合我等级」走：开着时只数等级合适的（= 选上后列表里真能看到几条）
--   每项 { n, lo, hi, cnt, on, fit }
function DC.DgMenu(lv)
    local onlyMine = DC.DB().fitLv ~= false
    local cnt = {}
    for _, p in ipairs(DC.Live()) do
        local d = DC.Dungeons()[p.d]
        if d and (not onlyMine or DC.FitsLevel(d, lv)) then cnt[d.n] = (cnt[d.n] or 0) + 1 end
    end
    local seen, idle, order = {}, {}, {}
    for i, d in ipairs(DC.Dungeons()) do
        local it = { n = d.n, lo = d.lo, hi = d.hi, cnt = cnt[d.n] or 0, on = DC.DgOn(d.n), fit = DC.FitsLevel(d, lv) }
        order[it] = i
        if it.cnt > 0 then seen[#seen + 1] = it elseif it.fit or it.on then idle[#idle + 1] = it end
    end
    table.sort(seen, function(a, b)
        if a.cnt ~= b.cnt then return a.cnt > b.cnt end
        return order[a] < order[b]
    end)
    return seen, idle
end

-- ---------- 我的职责（职业能打什么）----------
local CAN = { TANK = { WARRIOR = true, PALADIN = true, DRUID = true }, HEALER = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true } }
function DC.MyClass()
    if not UnitClass then return nil end
    local _, c = UnitClass("player")   -- ⛔ 别写 UnitClass and UnitClass(...)：and 只留第一个返回值，职业英文名就丢了
    return clean(c)
end
function DC.CanRole(role, cls)
    cls = cls or DC.MyClass()
    if role == "DAMAGER" then return true end
    return CAN[role] and CAN[role][cls or ""] or false
end
function DC.MyRole()
    local r = DC.DB().role
    if r and DC.CanRole(r) then return r end
    return "DAMAGER"
end
function DC.SetRole(r) if DC.CanRole(r) then DC.DB().role = r end end

local ROLE_NAME = { TANK = { "坦克", "Tank" }, HEALER = { "治疗", "Healer" }, DAMAGER = { "伤害输出", "Damage" } }
function DC.RoleName(r) local t = ROLE_NAME[r] or ROLE_NAME.DAMAGER; return L(t[1], t[2]) end

-- 这条消息缺的职责 → 「缺 坦克、治疗」/「没写职责」
function DC.NeedText(p)
    local n = {}
    for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do if p.roles[r] then n[#n + 1] = DC.RoleName(r) end end
    if #n == 0 then return L("没写职责", "roles not stated") end
    return L("缺 ", "needs ") .. table.concat(n, L("、", ", "))
end

-- ---------- 申请：私聊队长 + 记下来（这个队长 10 分钟内邀请自动接）----------
-- 11-10 用户「不像真人」「直接说 20 LR求组 【副本名】」：职业用玩家打字的拼音缩写
local CLS_ABBR = { HUNTER = "LR", PALADIN = "QS", DRUID = "XD", WARRIOR = "ZS", PRIEST = "MS", MAGE = "FS",
    WARLOCK = "SS", ROGUE = "DZ", SHAMAN = "SM" }
DC.CLS_ABBR = CLS_ABBR
-- 11-12 用户「职业要啥不要啥，也可以选」：招人时每个职业点一下切 不限 → 要 → 不要（存 rec.cls[职业] = "want" / "no"）
DC.CLS_TC = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
DC.CLS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLS_CN = { WARRIOR = { "战士", "Warrior", "战" }, PALADIN = { "圣骑士", "Paladin", "骑" }, HUNTER = { "猎人", "Hunter", "猎" },
    ROGUE = { "盗贼", "Rogue", "贼" }, PRIEST = { "牧师", "Priest", "牧" }, SHAMAN = { "萨满", "Shaman", "萨" },
    MAGE = { "法师", "Mage", "法" }, WARLOCK = { "术士", "Warlock", "术" }, DRUID = { "德鲁伊", "Druid", "德" } }
function DC.ClsName(c, shortOne)
    local t = CLS_CN[c or ""]
    if not t then return c or "?" end
    if shortOne then return L(t[3], t[2]:sub(1, 3)) end
    return L(t[1], t[2])
end
function DC.ClsPick(c) local r = DC.DB().rec; return r.cls and r.cls[c] or nil end
function DC.CycleCls(c)
    local r = DC.DB().rec
    r.cls = r.cls or {}
    local cur = r.cls[c]
    r.cls[c] = (cur == nil and "want") or (cur == "want" and "no") or nil
end
-- 11-12 用户「加一个简称选项，T N DPS这样，职业也可以加」：勾上「简称」喊话里职责写 T / N / DPS、职业写 ZS / FS 这类拼音缩写（记住选择）
local ROLE_ABBR = { TANK = "T", HEALER = "N", DAMAGER = "DPS" }
function DC.AbbrOn() return DC.DB().rec.abbr and true or false end
function DC.RoleShout(r) return DC.AbbrOn() and (ROLE_ABBR[r] or "DPS") or DC.RoleName(r) end
function DC.ClsShout(c) return DC.AbbrOn() and (CLS_ABBR[c] or DC.ClsName(c)) or DC.ClsName(c) end
-- 「要法师、牧师 不要盗贼」；都没选 = 空
function DC.ClsText()
    local want, no = {}, {}
    for _, c in ipairs(DC.CLS_ORDER) do
        local v = DC.ClsPick(c)
        if v == "want" then want[#want + 1] = DC.ClsShout(c) elseif v == "no" then no[#no + 1] = DC.ClsShout(c) end
    end
    local out = {}
    if #want > 0 then out[#out + 1] = L("要", "want ") .. table.concat(want, L("、", "/")) end
    if #no > 0 then out[#out + 1] = L("不要", "no ") .. table.concat(no, L("、", "/")) end
    return table.concat(out, " ")
end

function DC.ApplyText(p)
    local d = DC.Dungeons()[p.d] or {}
    local lv = tonumber(clean(UnitLevel and UnitLevel("player"))) or 0
    local cls = clean(UnitClass and UnitClass("player")) or ""
    local mine = ns.MyWhisper and ns.MyWhisper("lfg", { ["活动"] = d.n, ["职业"] = cls, ["等级"] = lv > 0 and lv or nil })
    if mine then return mine end
    return string.format(L("%d %s求组 %s", "%d %s LFG %s"), lv, CLS_ABBR[DC.MyClass() or ""] or cls, d.n or "?")
end

function DC.Apply(p)
    if not p or not p.author then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    local ok = pcall(send, DC.Tagged(DC.ApplyText(p), DC.MAX_BYTES), "WHISPER", nil, p.author)
    if ok then
        DC.applied[p.short] = { t = now(), d = p.d }
        local d = DC.Dungeons()[p.d] or {}
        ns.Print(string.format(L("已密 %s 申请「%s」：他 10 分钟内邀请你会自动进队", "Whispered %s for %s - their invite within 10 min is auto-accepted"), p.short, d.n or "?"))
    end
    return ok
end

function DC.Applied(name)
    local a = DC.applied[short(name) or ""]
    return a and now() - a.t <= DC.APPLY_WIN and a or nil
end

-- 收到邀请：只接我申请过、10 分钟内的那个队长（别人的邀请照常弹框）
function DC.OnInvite(inviter)
    inviter = clean(inviter)
    local a = inviter and DC.Applied(inviter)
    if not a or not AcceptGroup then return false end
    local ok = pcall(AcceptGroup)
    if ok and StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    if ok then
        DC.applied[short(inviter)] = nil
        local d = DC.Dungeons()[a.d] or {}
        ns.Print(string.format(L("已自动进 %s 的队（你申请了「%s」）", "Auto-joined %s's group (you applied for %s)"), short(inviter), d.n or "?"))
    end
    return ok
end

-- ---------- 招人 ----------
function DC.RecDungeon()
    local list, r = DC.Dungeons(), DC.DB().rec
    for i, d in ipairs(list) do if d.n == r.dungeon then return d, i end end
    local lv = tonumber(clean(UnitLevel and UnitLevel("player"))) or 1
    for i, d in ipairs(list) do if lv >= d.lo and lv <= d.hi then return d, i end end
    return list[1], 1
end
function DC.SetRecDungeon(i)
    local list = DC.Dungeons()
    local d = list[((i - 1) % #list) + 1]
    if not d then return end
    local r = DC.DB().rec
    r.dungeon, r.lo, r.hi = d.n, d.lo, d.hi   -- 换副本：等级范围跟着换成建议等级
end
function DC.RecRange()
    local d, r = DC.RecDungeon(), DC.DB().rec
    local lo, hi = r.lo or (d and d.lo) or 1, r.hi or (d and d.hi) or 60
    if lo > hi then lo, hi = hi, lo end
    return lo, hi
end
function DC.SetRange(lo, hi)
    local r = DC.DB().rec
    lo, hi = math.max(1, math.min(60, math.floor(lo or 1))), math.max(1, math.min(60, math.floor(hi or 60)))
    if lo > hi then if r.lo ~= lo then hi = lo else lo = hi end end
    r.lo, r.hi = lo, hi
end

function DC.CountText()
    local cnt = DC.PartyCount()
    return (cnt > DC.CNT_MIN and cnt < 5) and (cnt .. "=" .. (5 - cnt)) or ""
end
function DC.Custom()
    local d = DC.RecDungeon()
    local c = DC.DB().rec.custom
    return d and c and c[d.n] or nil
end
function DC.SaveCustom(text)
    local d = DC.RecDungeon()
    if not d then return false end
    local r = DC.DB().rec
    -- 编辑框里显示的是带前缀的最终文字：存之前去掉前缀（前缀由开关管，不进话术）
    text = type(text) == "string" and DC.StripTag(text):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local def = DC.RecDefaultText()
    if text == "" or text == def then
        if r.custom then r.custom[d.n] = nil end
        return false
    end
    local ct = DC.CountText()
    if ct ~= "" then
        local a, b = text:find(ct, 1, true)
        if a then text = text:sub(1, a - 1) .. "{人数}" .. text:sub(b + 1) end
    end
    r.custom = r.custom or {}
    r.custom[d.n] = text
    return true
end
function DC.RecText()
    local c = DC.Custom()
    if c then
        local ct = DC.CountText()
        local t = c:gsub("{人数}", ct):gsub("  +", " "):gsub("】 ", "】")
        return (t:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return DC.RecDefaultText()
end
-- 招人喊话真正发出去的（带前缀、裁到 255 字节）；「会发」框里显示的也是这个
function DC.SendText() return DC.Tagged(DC.RecText(), DC.MAX_BYTES) end
-- 11-12 用户「加一个默认关闭当前平均等级报告」：自己 + 队友的平均等级（四舍五入）；读不到等级的队友不算
function DC.AvgLevel()
    local sum, n = 0, 0
    local function add(u)
        if not UnitLevel then return end
        local ok, v = pcall(UnitLevel, u)
        v = ok and tonumber(clean(v)) or nil
        if v and v > 0 then sum = sum + v; n = n + 1 end
    end
    add("player")
    for i = 1, 4 do
        local ok, e = pcall(UnitExists or function() end, "party" .. i)
        if ok and clean(e) then add("party" .. i) end
    end
    if n == 0 then return nil end
    return math.floor(sum / n + 0.5), n
end
function DC.RecDefaultText()
    local d = DC.RecDungeon()
    local lo, hi = DC.RecRange()
    local r = DC.DB().rec
    local need = {}
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do if r.roles[role] then need[#need + 1] = DC.RoleShout(role) end end
    local lv = lo == hi and string.format(L("%d级", "Lv%d"), lo) or string.format(L("%d-%d级", "Lv%d-%d"), lo, hi)
    local needTxt = #need > 0 and (L("缺", "LF ") .. table.concat(need, L("、", "/"))) or L("缺人", "LF more")
    -- 11-10 用户「？=？也说一下，注意是超过3个人发」：队里超过 3 人（4 人）才带「4=1」（有几个 = 还差几个，按 5 人本）
    local cnt = DC.PartyCount()
    local head = L("【", "[") .. (d and d.n or "?") .. L("】", "] ") .. ((cnt > DC.CNT_MIN and cnt < 5) and (cnt .. "=" .. (5 - cnt) .. " ") or "")
    -- 11-10 用户截图「等级可以不喊」：关了「喊等级」就不带等级范围
    -- 11-11 用户「加一个选项，有SS可拉」：队里有术士能拉人，勾上就带一句（记住选择）
    -- 11-12 用户「带职责等级M，加这个」：结尾改「M我带职责等级」（回的人写上职责 / 等级，下面「来密我的人」直接认出来）
    local ct = DC.ClsText()
    return head .. (r.noLv and "" or (lv .. " ")) .. needTxt .. (ct ~= "" and (" " .. ct) or "") .. (r.ss and L("，有SS可拉", ", warlock summons") or "")
        .. ((r.avg and DC.AvgLevel()) and string.format(L("，当前平均%d级", ", avg Lv%d"), (DC.AvgLevel())) or "")
        .. L("，M我带职责等级", " - whisper me your role & level")
end

-- 加入的频道（去掉插件自己的隐藏频道）：{ { id, name } … }
function DC.Channels()
    local out = {}
    if not GetChannelList then return out end
    local t = { GetChannelList() }
    local step = (type(t[3]) == "boolean") and 3 or 2
    for i = 1, #t, step do
        local id, name = tonumber(t[i]), clean(t[i + 1])
        local ours = name and ns.Layer and ns.Layer.IsOurChannel and ns.Layer.IsOurChannel(name)
        if id and type(name) == "string" and not ours then out[#out + 1] = { id = id, name = name } end
    end
    -- 11-10 用户截图「发到」一排后写「公会」：有公会就多一个「公会」（走 GUILD，不是编号频道）
    if IsInGuild and IsInGuild() then out[#out + 1] = { name = L("公会", "Guild"), guild = true } end
    return out
end
function DC.ChanOn(name) return DC.DB().rec.chans[name] ~= false end
function DC.SetChan(name, on) if on then DC.DB().rec.chans[name] = nil else DC.DB().rec.chans[name] = false end end

function DC.ShoutLeft() return math.max(0, math.ceil(DC.SHOUT_CD - (now() - DC.lastShout))) end
function DC.Shout()
    if DC.ShoutLeft() > 0 then return 0, "cooldown" end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return 0, "nosend" end
    local text, n = DC.SendText(), 0
    for _, c in ipairs(DC.Channels()) do
        local ok = DC.ChanOn(c.name) and (c.guild and pcall(send, text, "GUILD") or (not c.guild and pcall(send, text, "CHANNEL", nil, c.id)))
        if ok then n = n + 1 end
    end
    -- 11-13 用户「记录在这里不要老清除」：重新喊话不再清空「来密我的人」（DC.MarkShout 只记时刻，存档里也记一份）
    if n > 0 then DC.MarkShout() end
    return n, n == 0 and "nochan" or nil
end

-- 喊完 15 分钟内密我的人：DC.OnWhisper 11-13 搬进小核（DungeonChatCore.lua）——面板没加载也收、记进存档、不再被清掉

-- 自动反问：没报等级 / 职责 → 密他一句（每人一次；开关在「来密我的人」右边，默认开）
DC.ASK_TAG = "报下"
function DC.AskOn() return DC.DB().rec.autoAsk ~= false end
function DC.AskText(p)
    local noLv = not DC.LevelOf(p)
    local rs = DC.RolesOf(p)
    local noRole = #rs == 0
    if noLv and noRole then return L("老哥报下等级和职责哈（比如 25奶 / 28T / 30输出）", "Hi, what's your level and role? (e.g. 25 healer / 28 tank / 30 dps)") end
    if noLv then return L("老哥报下等级哈", "Hi, what's your level?") end
    if noRole then return L("老哥报下职责哈（T / 奶 / 输出）", "Hi, what's your role? (tank / healer / dps)") end
    return nil
end
function DC.MaybeAsk(p)
    if not DC.AskOn() or rawget(p, "asked") then return false end
    -- 对方也是插件自动发的（「报下……」/ 招人喊话）就不回，免得两边插件来回问
    if p.text:find(DC.ASK_TAG, 1, true) or p.text:find("M我", 1, true) then return false end
    -- 11-12 对方插件发来的「[GI组队助手]…」：上面已按去掉前缀后的文字判过（反问里有「报下」不回）；
    --   带前缀的申请私聊（「20 QS求组」没职责）照常问一次——那是真人点的申请，对方插件收到「报下…」不会再回，不会来回刷
    if not DC.AskText(p) then return false end
    p.asked = true
    local function go()
        -- 这一会儿他可能已经补上了：发之前再看一眼（用最新那一行）
        local cur
        for _, x in ipairs(DC.replies) do if x.short == p.short then cur = x; break end end
        local t = DC.AskText(cur or p)
        if not t then return end
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        if send then pcall(send, DC.Tagged(t, DC.MAX_BYTES), "WHISPER", nil, p.author) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(2, go) else go() end
    return true
end

-- 打开对这个人的私聊输入框（玩家自己写、自己按回车；插件不代发）
function DC.Tell(name)
    if not name then return false end
    if ChatFrame_SendTell then return (pcall(ChatFrame_SendTell, name)) end
    if ChatFrameUtil and ChatFrameUtil.SendTell then return (pcall(ChatFrameUtil.SendTell, name)) end
    return false
end

function DC.Invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn or not name then return false end
    return (pcall(fn, name))
end


-- ---------- 事件 ----------
local ev = CreateFrame("Frame")
DC.ev = ev
-- 11-13 第 5 期：TRADE_SHOW 挪到小核的事件框（DC.SyncCore，用得上才注册），这里不注册（下面那行处理留着给测试直接喂）
for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER", "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1, a2, _, a4, _, _, _, _, a9, _, _, a12)
    if e == "CHAT_MSG_CHANNEL" then pcall(DC.OnChannel, a1, a2, a9 or a4, a12)
    elseif e == "CHAT_MSG_GUILD" then pcall(DC.OnChannel, a1, a2, L("公会", "Guild"), a12)
    elseif e == "CHAT_MSG_WHISPER" then pcall(DC.OnWhisper, a1, a2, a12)
    elseif e == "PARTY_INVITE_REQUEST" then pcall(DC.OnInvite, a1)
    elseif e == "TRADE_SHOW" then pcall(DC.OnTradeShow)
    elseif e == "GROUP_ROSTER_UPDATE" then   -- 人数变了：招人预览的「4=1」跟着变
        DC.dirty = true
        if not DC.coreFull then pcall(DC.CheckFull) end   -- 满员通知开着时小核的事件框已经在管（别算两遍）
    end
    if DC.dirty and DC.panel and DC.panel:IsShown() then DC.dirty = false; pcall(DC.Render) end
end)
DC._event = ev:GetScript("OnEvent")   -- 测试用
-- 11-13 面板加载了：私聊由这里的事件框收，小核那边（喊完 /reload 时临时注册的）注销掉，别记两遍
if DC.SyncWhisper then pcall(DC.SyncWhisper) end

-- ---------- 界面（QuestMates 抽屉 d.lfg 盖板里）----------
local GOLD, DIM = "|cffffd100", "|cff9a9a9a"
local function ago(t)
    local s = math.max(0, math.floor(now() - t))
    if s < 60 then return string.format(L("%d 秒前", "%ds ago"), s) end
    return string.format(L("%d 分钟前", "%dm ago"), math.floor(s / 60))
end

-- 11-12 用户截图「优化展示」：表格里时间列太窄，「10 秒前」折成三行 → 表格用短写「10秒」「3分」，不换行
local function agoShort(t)
    local s = math.max(0, math.floor(now() - t))
    if s < 60 then return string.format(L("%d秒", "%ds"), s) end
    if s < 3600 then return string.format(L("%d分", "%dm"), math.floor(s / 60)) end
    return string.format(L("%d时", "%dh"), math.floor(s / 3600))
end
DC.AgoShort = agoShort
-- 11-13「来密我的人」留到下次登录：行上「多久前」按 time() 秒算（存档里的 at），写全「3分钟前 / 2小时前」
function DC.AgoAt(at)
    local s = math.max(0, math.floor((DC._epoch() - (tonumber(at) or 0))))
    if s < 60 then return L("刚刚", "now") end
    if s < 3600 then return string.format(L("%d分钟前", "%dm ago"), math.floor(s / 60)) end
    if s < 86400 then return string.format(L("%d小时前", "%dh ago"), math.floor(s / 3600)) end
    return string.format(L("%d天前", "%dd ago"), math.floor(s / 86400))
end
-- 表格里的短写（按存档时间）：「刚刚」「3分」「2时」「1天」
function DC.AgoShortAt(at)
    local s = math.max(0, math.floor((DC._epoch() - (tonumber(at) or 0))))
    if s < 60 then return L("刚刚", "now") end
    if s < 3600 then return string.format(L("%d分", "%dm"), math.floor(s / 60)) end
    if s < 86400 then return string.format(L("%d时", "%dh"), math.floor(s / 3600)) end
    return string.format(L("%d天", "%dd"), math.floor(s / 86400))
end
-- 这人已经在我队伍里（标「已在队」，不删）
function DC.InMyGroup(name)
    local s = short(name)
    if not s or not UnitExists then return false end
    local raid = false
    if IsInRaid then local ok, v = pcall(IsInRaid); raid = ok and clean(v) and true or false end
    local n = raid and 40 or 4
    for i = 1, n do
        local u = (raid and "raid" or "party") .. i
        local ok, e = pcall(UnitExists, u)
        if ok and clean(e) then
            local okN, un = pcall(UnitName or function() end, u)
            un = okN and short(clean(un)) or nil
            if un == s or fullName(u) == s then return true end
        end
    end
    return false
end

local function seg(parent, text, w, fn)
    local b = (ns.SegButton or ns.Button)(parent, text, w, 22, fn)
    return b
end
local function sel(b, on) if ns.SegSelect and rawget(b, "_segFs") then ns.SegSelect(b, on) end end

local function slider(parent, w)
    local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetSize(w, 16)
    if s.SetOrientation then s:SetOrientation("HORIZONTAL") end
    if s.SetBackdrop then
        pcall(s.SetBackdrop, s, { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        s:SetBackdropColor(0.08, 0.08, 0.1, 1); s:SetBackdropBorderColor(0.4, 0.4, 0.42, 1)
    end
    if s.SetThumbTexture then s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal") end
    s:SetMinMaxValues(1, 60)
    if s.SetValueStep then s:SetValueStep(1) end
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    return s
end

local function rowFrame(parent, i, w)
    local rows = rawget(parent, "_rows")   -- ⛔ 懒建的字段一律 rawget：框体的元表可能给没设过的键返回方法
    if not rows then rows = {}; rawset(parent, "_rows", rows) end
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetSize(w, 40)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
    local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.t:SetPoint("TOPLEFT", 6, -4); r.t:SetPoint("RIGHT", -134, 0); r.t:SetJustifyH("LEFT")
    r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("TOPLEFT", 6, -22); r.s:SetPoint("RIGHT", -134, 0); r.s:SetJustifyH("LEFT")
    if r.t.SetWordWrap then r.t:SetWordWrap(false); r.s:SetWordWrap(false) end
    r.b = ns.Button(r, "", 64, 22); r.b:SetPoint("RIGHT", -4, 0)
    -- 11-10 用户「可以私聊，可以邀请」：每行都多一个「私聊」（打开对他的私聊输入框，自己写）
    r.w = ns.Button(r, L("私聊", "Whisper"), 56, 22); r.w:SetPoint("RIGHT", r.b, "LEFT", -4, 0)
    r:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.tip[1], 1, 0.82, 0)
        for k = 2, #self.tip do GameTooltip:AddLine(self.tip[k], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

-- 11-12 「来密我的人」表格：名字 | 职业 | 等级 | 职责 | 说的话 | 多久前 | 私聊 / 邀请（一人一行，悬停看他说过的全部）
-- 11-13 用户截图「这里有一些信息被缩略掉了，可以展开点不」：「说的话」只露两三个字 → 列宽重分（378 宽的表）：
--   名字列带职业图标（职业名进悬停 / 展开），等级职责合成一列（「25 奶」「30 坦/奶」），时间短写（「3分」），按钮收窄；
--   说的话还放不下 → 点这一行展开成多行完整原文（全名-服务器 + 他说过的每一句），再点收起；悬停也给全文
DC.TCOL = { { "name", 4, 82 }, { "lr", 90, 46 }, { "txt", 140, 0 } }
DC.ROW_H, DC.ROW_GAP, DC.LINE_H, DC.AGO_W = 22, 1, 13, 26
DC.expanded = DC.expanded or {}
local function smallFont(b)
    if b.SetNormalFontObject then pcall(b.SetNormalFontObject, b, "GameFontNormalSmall") end
    if b.SetHighlightFontObject then pcall(b.SetHighlightFontObject, b, "GameFontHighlightSmall") end
    if b.SetDisabledFontObject then pcall(b.SetDisabledFontObject, b, "GameFontDisableSmall") end
end
local function repRow(parent, i, w)
    local rows = rawget(parent, "_trows")
    if not rows then rows = {}; rawset(parent, "_trows", rows) end
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetSize(w, DC.ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * (DC.ROW_H + DC.ROW_GAP))
    local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.07)
    r.bg, r.alt = bg, i % 2 == 0 and 0.03 or 0.07
    -- 11-13 行尾「×」= 只删这一个人（列表不再自己清，用户自己删）；按钮都钉在第一行高度（展开后不跟着往下跑）
    r.x = ns.Button(r, "×", 16, 20, function(self) local s = rawget(self, "who"); if s then DC.RemoveReply(s); DC.Render() end end); r.x:SetPoint("TOPRIGHT", -2, -1)
    r.b = ns.Button(r, L("邀请", "Inv"), 40, 20); r.b:SetPoint("RIGHT", r.x, "LEFT", -2, 0)
    r.w = ns.Button(r, L("私聊", "Tell"), 32, 20); r.w:SetPoint("RIGHT", r.b, "LEFT", -2, 0)
    smallFont(r.x); smallFont(r.b); smallFont(r.w)
    r.ago = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.ago:SetPoint("RIGHT", r.w, "LEFT", -3, 0); r.ago:SetWidth(DC.AGO_W); r.ago:SetJustifyH("RIGHT")
    if r.ago.SetWordWrap then r.ago:SetWordWrap(false) end
    r.c = {}
    for _, col in ipairs(DC.TCOL) do
        local fs = r:CreateFontString(nil, "OVERLAY", col[1] == "name" and "GameFontNormalSmall" or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", col[2], -5); fs:SetJustifyH("LEFT")
        if col[3] > 0 then fs:SetWidth(col[3]) else fs:SetPoint("RIGHT", r.ago, "LEFT", -4, 0) end
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        r.c[col[1]] = fs
    end
    -- 展开后的完整原文（整行宽，按钮下面）
    r.full = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.full:SetPoint("TOPLEFT", 6, -DC.ROW_H); r.full:SetWidth(w - 12); r.full:SetJustifyH("LEFT")
    if r.full.SetJustifyV then r.full:SetJustifyV("TOP") end
    if r.full.SetWordWrap then r.full:SetWordWrap(true) end
    r.full:Hide()
    r:SetScript("OnClick", function(self)
        local s = rawget(self, "who")
        if not s then return end
        DC.expanded[s] = (not DC.expanded[s]) or nil
        DC.Render()
    end)
    r:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.tip[1], 1, 0.82, 0)
        for k = 2, #self.tip do GameTooltip:AddLine(self.tip[k], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end
-- 展开那几行的文字：全名-服务器 · 职业，下面他说过的每一句
function DC.ReplyFullText(p)
    local lines = { "|cffffd100" .. tostring(p.author or p.short) .. "|r" .. (p.clsName and ("  " .. p.clsName) or "") }
    for _, t in ipairs(p.hist or { p.text }) do lines[#lines + 1] = "· " .. tostring(t) end
    return table.concat(lines, "\n"), #lines
end
function DC.LvRoleText(lv, rs, guessed, asked)
    local ONE = { TANK = L("坦", "T"), HEALER = L("奶", "H"), DAMAGER = L("输", "D") }
    local rn = {}
    for _, r in ipairs(rs or {}) do rn[#rn + 1] = ONE[r] end
    local role = #rn > 0 and ((guessed and "|cff9a9a9a" or "|cff66ccff") .. table.concat(rn, "/") .. "|r") or nil
    if lv and role then return tostring(lv) .. " " .. role end
    if lv then return tostring(lv) end
    if role then return role end
    return asked and ("|cffffaa33" .. L("问了", "asked") .. "|r") or "|cff777777-|r"
end
function DC.ReplyCells(p)
    local col = p.cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.cls]
    local hex = col and (col.colorStr or (col.r and string.format("ff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255))) or "ffffffff"
    local lv = DC.LevelOf(p)
    local rs, guessed = DC.RolesOf(p)
    local rn = {}
    -- 一个职责写全（坦克 / 治疗 / 输出）；能打多个就用单字（坦/奶/输），不然这一列被截成「坦克/…」
    local ONE = { TANK = L("坦", "T"), HEALER = L("奶", "H"), DAMAGER = L("输", "D") }
    for _, r in ipairs(rs) do rn[#rn + 1] = #rs > 1 and ONE[r] or DC.RoleName(r):gsub(L("伤害输出", "Damage"), L("输出", "DPS")) end
    local pick = p.cls and DC.ClsPick(p.cls)
    local clsTxt = p.cls and DC.ClsName(p.cls, true) or (p.clsName or "?")
    local tc = p.cls and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.cls]) or DC.CLS_TC[p.cls])
    local icon = tc and string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:14:14:0:0:256:256:%d:%d:%d:%d|t",
        tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256) or ""
    if pick == "no" then clsTxt = "|cffff5555×" .. clsTxt .. "|r" elseif pick == "want" then clsTxt = "|cff33ff99" .. clsTxt .. "|r"
    else clsTxt = "|c" .. hex .. clsTxt .. "|r" end
    local guild = DC.IsGuild(p.author)
    return {
        guild = guild,
        name = icon .. "|c" .. hex .. p.short .. "|r",
        cls = icon .. clsTxt,
        lv = lv and tostring(lv) or (rawget(p, "asked") and "|cffffaa33" .. L("问了", "asked") .. "|r" or "|cff777777-|r"),
        role = #rn > 0 and ((guessed and "|cff9a9a9a" or "|cff66ccff") .. table.concat(rn, "/") .. "|r")
            or (rawget(p, "asked") and "|cffffaa33" .. L("问了", "asked") .. "|r" or "|cff777777-|r"),
        -- 11-13 等级职责合成一列：「25 奶」「30 坦/奶」（职责一律单字），都没有「问了」/「-」
        lr = DC.LvRoleText(lv, rs, guessed, rawget(p, "asked")),
        -- 名字列只有 92 宽，标签放「说的话」开头（一直看得见，不挤名字）
        txt = guild and (DC.GuildTag() .. " " .. p.text) or p.text,
    }
end

-- 「副本：」下拉弹层（插件没有通用下拉控件 → 简单的弹出按钮列表）：顶上「全部副本」，
--   下面两段两列按钮：「频道里有人组」（带条数）/「适合你等级 · 暂时没人组」（条数 0 灰显，也能先选上等人）；点一下选上 / 取消，可多选
local function dgPop()
    local S = DC.panel and DC.panel.seek
    if not S then return nil end
    local f = rawget(S, "dgPop")
    if f then return f end
    f = CreateFrame("Frame", nil, S, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetPoint("TOPLEFT", 0, -50)
    f:SetWidth(rawget(S, "w") or 380)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.04, 0.045, 0.06, 0.98); f:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 8, -8)
    t:SetText(L("按副本筛选（可多选）", "Filter by dungeon (multi-select)"))
    f.close = ns.Button(f, L("关闭", "Close"), 52, 20, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -5)
    f.all = seg(f, L("全部副本", "All dungeons"), 120, function() DC.ClearDg(); DC.Render() end)
    f.all:SetPoint("TOPLEFT", 8, -30)
    f.h1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.h2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.none = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.none:SetText(L("还没识别到组队消息，也没有适合你等级的副本", "No group posts yet and no dungeon fits your level"))
    rawset(f, "_btns", {})
    rawset(S, "dgPop", f)
    f:Hide()
    return f
end
function DC.RenderDgMenu(lv)
    local f = dgPop()
    if not f then return end
    lv = lv or tonumber(clean(UnitLevel and UnitLevel("player"))) or 0
    local seen, idle = DC.DgMenu(lv)
    sel(f.all, DC.DgFilter() == nil)
    local btns = rawget(f, "_btns")
    local W = (rawget(DC.panel.seek, "w") or 380) - 16
    local colW = math.floor((W - 6) / 2)
    local y, k = -58, 0
    local items = {}   -- 测试用：这一次画出来的 { n, cnt, on, idle }
    local function section(head, list, isIdle)
        if #list == 0 then head:Hide(); return end
        head:ClearAllPoints(); head:SetPoint("TOPLEFT", 8, y); head:Show()
        y = y - 16
        for i, it in ipairs(list) do
            k = k + 1
            local b = btns[k]
            if not b then b = seg(f, "", colW, nil); b:SetHeight(20); btns[k] = b end
            local col = (i - 1) % 2
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8 + col * (colW + 6), y); b:Show()
            if col == 1 or i == #list then y = y - 22 end
            local txt = it.n .. " (" .. it.cnt .. ")"
            if it.cnt == 0 and not it.on then txt = "|cff808080" .. txt .. "|r" end
            b:SetText(txt)
            sel(b, it.on)
            local name, lo, hi = it.n, it.lo, it.hi
            b:SetScript("OnClick", function() DC.SetDg(name, not DC.DgOn(name)); DC.Render() end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(name, 1, 0.82, 0)
                GameTooltip:AddLine(string.format(L("建议 %d-%d 级", "Lv %d-%d"), lo, hi), 1, 1, 1)
                GameTooltip:AddLine(L("点一下选上 / 取消，可多选；副本里的各个区（如图书馆 / 墓地）都算在这个副本里", "Click to toggle (multi-select); all wings count"), 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            items[#items + 1] = { n = it.n, cnt = it.cnt, on = it.on, idle = isIdle }
        end
        y = y - 4
    end
    f.h1:SetText(L("频道里有人组", "Posted in channels"))
    f.h2:SetText(L("适合你等级 · 暂时没人组", "Fits your level - no posts yet"))
    section(f.h1, seen, false)
    section(f.h2, idle, true)
    for i = k + 1, #btns do btns[i]:Hide() end
    if #seen == 0 and #idle == 0 then
        f.none:ClearAllPoints(); f.none:SetPoint("TOPLEFT", 8, y); f.none:Show(); y = y - 18
    else f.none:Hide() end
    f:SetHeight(-y + 6)
    rawset(f, "items", items)
end
function DC.ToggleDgMenu()
    local f = dgPop()
    if not f then return end
    if f:IsShown() then f:Hide(); return end
    f:Show()
    DC.RenderDgMenu()
end

local function renderSeek(P)
    local my = DC.MyRole()
    for role, b in pairs(P.roleBtns) do
        local can = DC.CanRole(role)
        sel(b, role == my)
        if b.SetEnabled then b:SetEnabled(can) end
        b:SetAlpha(can and 1 or 0.4)
    end
    local lv = tonumber(clean(UnitLevel and UnitLevel("player"))) or 0
    local onlyMine = DC.DB().fitLv ~= false
    sel(P.fit, onlyMine)
    local picked, list, lvOut, dgOut = DC.SeekList(lv)
    local shown = 0
    local filtered = DC.DgFilter() ~= nil
    if rawget(P, "dgBtn") then
        P.dgBtn:SetText(DC.DgLabel() .. " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t")
        sel(P.dgBtn, filtered)
        sel(P.dgAll, not filtered)
        local pop = rawget(P, "dgPop")
        if pop and pop:IsShown() then DC.RenderDgMenu(lv) end
    end
    for _, p in ipairs(picked) do
        local d = DC.Dungeons()[p.d]
        do
            shown = shown + 1
            local r = rowFrame(P.list, shown, P.listW)
            r:Show()
            -- 11-10 用户「区分是求组，还是组人」：开头标签，组人（队长在招人）橙色、求组（散人找队）蓝色
            r.t:SetText((p.lfg and ("|cff66ccff[" .. L("求组", "LFG") .. "]|r ") or ("|cffff9933[" .. L("组人", "LFM") .. "]|r "))
                .. GOLD .. d.n .. (p.wing and ("·" .. p.wing) or "") .. "|r  " .. DIM .. string.format(L("建议 %d-%d 级", "Lv %d-%d"), d.lo, d.hi) .. "|r")
            r.w:SetScript("OnClick", function() DC.Tell(p.author) end)
            -- 11-10 用户「公会的人，特别标注」：名字后绿色「公会」，排在前面
            r.s:SetText(DC.NeedText(p) .. "  ·  " .. DC.WhoText(p) .. (p.guild and (" " .. DC.GuildTag()) or "") .. "  ·  " .. ago(p.t))
            r.tip = { p.short .. (p.ch and ("（" .. p.ch .. "）") or ""), p.text }
            if p.guild then r.tip[3] = DC.GuildTip() end
            local applied = DC.Applied(p.author)
            if p.lfg then
                r.b:SetText(L("邀请", "Invite")); r.b:SetEnabled(true)
                r.b:SetScript("OnClick", function() DC.Invite(p.author) end)
            else
                r.b:SetText(applied and L("已申请", "Applied") or L("申请", "Apply")); r.b:SetEnabled(not applied)
                r.b:SetScript("OnClick", function() DC.Apply(p); DC.Render() end)
            end
        end
    end
    local rows = rawget(P.list, "_rows") or {}
    for i = shown + 1, #rows do rows[i]:Hide() end
    P.list:SetHeight(math.max(10, shown * 42))
    -- 选了副本却一条都没有：空态写明是筛选筛的，别让人以为插件没读到
    if filtered and shown == 0 then
        P.empty:SetText(L("选的副本暂时没人组，点「全部副本」看其它", "Nobody is grouping for the picked dungeons yet - click All dungeons to see the rest"))
    else
        P.empty:SetText(rawget(P, "emptyDef") or "")
    end
    P.empty:SetShown(shown == 0)
    local st = string.format(L("10 分钟内从各频道识别到 %d 条组队消息，列出 %d 条", "%d group posts from channels in the last 10 min, %d shown"), #list, shown)
    if onlyMine and lvOut > 0 then
        st = st .. string.format(L("（另 %d 条不在你的等级，点「适合我等级」看全部）", " (%d more outside your level: untick My level)"), lvOut)
    end
    if filtered then
        st = st .. string.format(L("；已按副本筛选，筛掉 %d 条（点「全部副本」看全部）", "; dungeon filter on, %d hidden (click All dungeons)"), dgOut)
    end
    P.status:SetText(st)
end

local function renderRecruit(P)
    local d = DC.RecDungeon()
    local lo, hi = DC.RecRange()
    P.dname:SetText(GOLD .. (d and d.n or "?") .. "|r  " .. DIM .. string.format(L("建议 %d-%d 级", "suggested Lv %d-%d"), d and d.lo or 0, d and d.hi or 0) .. "|r")
    rawset(P, "busy", true)
    P.sLo:SetValue(lo); P.sHi:SetValue(hi)
    rawset(P, "busy", false)
    P.loTxt:SetText(string.format(L("最低 %d 级", "Min Lv %d"), lo)); P.hiTxt:SetText(string.format(L("最高 %d 级", "Max Lv %d"), hi))
    local r = DC.DB().rec
    for role, b in pairs(P.needBtns) do sel(b, r.roles[role] and true or false) end
    sel(P.lvBtn, not r.noLv)
    sel(P.ssBtn, r.ss and true or false)
    if P.abbrBtn then sel(P.abbrBtn, r.abbr and true or false) end
    if P.avgBtn then sel(P.avgBtn, r.avg and true or false) end
    for c, b in pairs(P.clsBtns or {}) do
        local v = DC.ClsPick(c)
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
        local hex = col and (col.colorStr or (col.r and string.format("ff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255))) or "ffffffff"
        local ic, no = rawget(b, "_ic"), rawget(b, "_no")
        if ic then
            b:SetText("")
            if ic.SetDesaturated then ic:SetDesaturated(v ~= "want") end
            ic:SetAlpha(v == "want" and 1 or (v == "no" and 0.45 or 0.6))
            no:SetShown(v == "no")
        else
            b:SetText(v == "no" and ("|cffff5555×" .. DC.ClsName(c, true) .. "|r") or ("|c" .. hex .. DC.ClsName(c, true) .. "|r"))
        end
        sel(b, v == "want")
    end
    for _, w in ipairs({ P.sLo, P.sHi, P.loTxt, P.hiTxt }) do w:SetAlpha(r.noLv and 0.35 or 1) end
    -- 频道按钮：按当前加入的频道重排
    local chans = DC.Channels()
    if not rawget(P, "chanBtns") then rawset(P, "chanBtns", {}) end
    local x, y = 0, 0
    for i, c in ipairs(chans) do
        local b = P.chanBtns[i]
        if not b then
            b = seg(P.chanBox, "", 96, nil)
            P.chanBtns[i] = b
        end
        local label = c.name:gsub("%s*%-.*$", "")
        b:SetText(label)
        b:SetScript("OnClick", function() DC.SetChan(c.name, not DC.ChanOn(c.name)); DC.Render() end)
        sel(b, DC.ChanOn(c.name))
        if x + 100 > P.w - 24 then x, y = 0, y - 26 end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, y); b:Show()
        x = x + 100
    end
    for i = #chans + 1, #P.chanBtns do P.chanBtns[i]:Hide() end
    if ns.LfgListAuto then x, y = ns.LfgListAuto.Place(P, x, y) end   -- 11-13 集合石（LfgListAuto.lua，HOLD）：「发到」那排最后一个 +「下架」
    local extra = math.max(0, math.floor(-y / 26 + 0.5) - 1) * 26   -- 第 3 行起每多一行往下挪 26
    if rawget(P, "lower") then P.lower:ClearAllPoints(); P.lower:SetPoint("TOPLEFT", 0, -(P.lowY + extra)) end
    DC.FitRepList(P, extra)
    P.noChan:SetShown(#chans == 0)
    if not P.edit:HasFocus() then P.edit:SetText(DC.SendText()); P.edit:SetCursorPosition(0) end
    if rawget(P, "tagBtn") then sel(P.tagBtn, DC.TagOn()) end
    if rawget(P, "fullSayBtn") then sel(P.fullSayBtn, r.fullSay and true or false) end
    if rawget(P, "fullTellBtn") then sel(P.fullTellBtn, r.fullTell and true or false) end
    if rawget(P, "mageBtn") then sel(P.mageBtn, r.mageAsk and true or false) end
    P.def:SetEnabled(DC.Custom() ~= nil)
    local left = DC.ShoutLeft()
    P.send:SetText(left > 0 and string.format(L("%d 秒后可再发", "Wait %ds"), left) or L("一键发到勾选的频道", "Send to ticked channels"))
    P.send:SetEnabled(left == 0)
    local shown, y = 0, 0
    for _, p in ipairs(DC.PruneReplies()) do
        shown = shown + 1
        local row = repRow(P.rep, shown, P.listW)
        row:Show()
        local cells = DC.ReplyCells(p)
        for k, fs in pairs(row.c) do fs:SetText(cells[k] or "") end
        -- 时间列短写（「3分」「2时」），悬停给「3分钟前」
        row.ago:SetText(p.at and DC.AgoShortAt(p.at) or agoShort(p.t))
        rawset(row, "who", p.short)
        -- 点行展开 / 收起
        local open = DC.expanded[p.short] and true or false
        local hh = DC.ROW_H
        if open then
            local txt, n = DC.ReplyFullText(p)
            row.full:SetText(txt); row.full:Show()
            local sh = row.full.GetStringHeight and tonumber(row.full:GetStringHeight()) or nil
            local est = n * DC.LINE_H
            if not sh or sh <= 0 or sh > est * 4 then sh = est end   -- 量不到（或量出离谱的数）按行数估
            hh = DC.ROW_H + math.ceil(sh) + 4
        else
            row.full:Hide()
        end
        rawset(row, "open", open)
        row:SetHeight(hh)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
        y = y + hh + DC.ROW_GAP
        -- 同公会：整行淡绿底 + 「说的话」开头绿色 [公会] + 悬停第二行「同公会」
        rawset(row, "guild", cells.guild)
        if row.bg then
            if cells.guild then row.bg:SetColorTexture(0.25, 1, 0.25, 0.14) else row.bg:SetColorTexture(1, 1, 1, row.alt or 0.05) end
        end
        -- 悬停：全名-服务器 · 职业、他说过的每一句（全文，自动换行）、多久前；点一下展开 / 收起
        local tip = { tostring(p.author or p.short) .. (p.clsName and (" · " .. p.clsName) or "") }
        if cells.guild then tip[#tip + 1] = DC.GuildTip() end
        for _, t in ipairs(p.hist or { p.text }) do tip[#tip + 1] = t end
        if p.at then tip[#tip + 1] = "|cff9a9a9a" .. DC.AgoAt(p.at) .. "|r" end
        row.tip = tip
        -- 11-13 已经进了我的队：按钮写「已在队」、点不了（不删这一行）
        local inGrp = DC.InMyGroup(p.author)
        row.b:SetText(inGrp and L("已在队", "In group") or L("邀请", "Inv"))
        if row.b.SetEnabled then row.b:SetEnabled(not inGrp) end
        rawset(row, "inGroup", inGrp)
        rawset(row.x, "who", p.short)
        if p.firstAt and p.at and p.at - p.firstAt >= 60 then tip[#tip + 1] = "|cff9a9a9a" .. L("第一次密你：", "First whispered: ") .. DC.AgoAt(p.firstAt) .. "|r" end
        tip[#tip + 1] = "|cff9a9a9a" .. (open and L("点一下收起", "Click to collapse") or L("点一下展开完整的话", "Click to expand")) .. "|r"
        row.b:SetScript("OnClick", function() DC.Invite(p.author) end)
        row.w:SetScript("OnClick", function() DC.Tell(p.author) end)
    end
    local rrows = rawget(P.rep, "_trows") or {}
    for i = shown + 1, #rrows do rrows[i]:Hide() end
    P.rep:SetHeight(math.max(10, y))
    P.repEmpty:SetShown(shown == 0)
    P.repHead:SetShown(shown > 0)
    if rawget(P, "clearBtn") then P.clearBtn:SetShown(shown > 0) end
    sel(P.askBtn, DC.AskOn())
end

-- 11-13 用户「只露 5 行就要滚」：列表高度 = 面板底边到表头下面剩下的全部（组队窗口跟着主面板变高时也吃满），上面的控件不动
function DC.FitRepList(R, extra)
    if not (rawget(R, "rsf") and rawget(R, "h")) then return end
    local ph = DC.panel and DC.panel.GetHeight and tonumber(DC.panel:GetHeight()) or nil
    if not ph or ph < R.h then ph = R.h end
    local hh = math.floor(ph - 40 - (R.lowY + (extra or 0)) - 96 - 6)
    hh = math.max(DC.ROW_H * 3, hh)
    R.rsf:SetHeight(hh)
    rawset(R, "repH", hh)
    return hh
end

function DC.Render()
    local P = DC.panel
    if not P then return end
    sel(P.vSeek, DC.view == "seek"); sel(P.vRec, DC.view == "recruit")
    P.seek:SetShown(DC.view == "seek"); P.rec:SetShown(DC.view == "recruit")
    if DC.view == "seek" then renderSeek(P.seek) else renderRecruit(P.rec) end
end

-- ---------- 复制到聊天群（11-10 用户「有个可以发到聊天群的功能，弹出来直接复制，可以介绍目前队伍情况（可勾选）」
--   「职业，等级，位置情况都行」「弹出可复制框」）：生成一段文字，弹框 Ctrl+C，贴到 QQ / 微信群 ----------
DC.COPY_OPTS = {
    { "cnt", L("人数", "Count") }, { "lv", L("招人等级", "Level range") }, { "need", L("缺什么", "Needs") },
    { "cls", L("队员职业", "Classes") }, { "mlv", L("队员等级", "Levels") }, { "zone", L("队员位置", "Zones") },
    { "tell", L("密我名字", "Whisper me") },
}
function DC.CopyOpts()
    local r = DC.DB().rec
    r.cp = r.cp or {}
    return r.cp
end
function DC.CopyOn(k) return DC.CopyOpts()[k] ~= false end
function DC.SetCopyOn(k, on) if on then DC.CopyOpts()[k] = nil else DC.CopyOpts()[k] = false end end   -- ⛔ 别写 (not on) and false or nil：恒为 nil

local function zoneOfUnit(u)
    if u == "player" then
        local z = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
        return clean(z) ~= "" and clean(z) or nil
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local ok, mid = pcall(C_Map.GetBestMapForUnit, u)
    mid = ok and clean(mid) or nil
    if not mid then return nil end
    local ok2, mi = pcall(C_Map.GetMapInfo, mid)
    return ok2 and type(mi) == "table" and clean(mi.name) or nil
end

-- 自己 + 队友：{ name, cls（本地化职业名）, lv, zone }
function DC.Members()
    local out = {}
    local units = { "player" }
    if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        if u == "player" or (UnitExists and UnitExists(u)) then
            local name = fullName(u)
            if name then
                local cls = UnitClass and select(1, UnitClass(u))
                out[#out + 1] = { name = name, cls = clean(cls), lv = tonumber(clean(UnitLevel and UnitLevel(u))), zone = zoneOfUnit(u) }
            end
        end
    end
    return out
end

function DC.CopyText()
    local d = DC.RecDungeon()
    local lo, hi = DC.RecRange()
    local r = DC.DB().rec
    local mem = DC.Members()
    local cnt = #mem
    local head = L("【无限·", "[Forever ") .. (d and d.n or "?") .. L("】", "] ")
    if DC.CopyOn("cnt") then head = head .. cnt .. "=" .. math.max(0, 5 - cnt) .. " " end
    if DC.CopyOn("lv") then head = head .. (lo == hi and string.format(L("%d级", "Lv%d"), lo) or string.format(L("%d-%d级", "Lv%d-%d"), lo, hi)) .. " " end
    if DC.CopyOn("need") then
        local need = {}
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do if r.roles[role] then need[#need + 1] = DC.RoleShout(role) end end
        head = head .. (#need > 0 and (L("缺", "LF ") .. table.concat(need, L("、", "/"))) or L("缺人", "LF more"))
    end
    local lines = { (head:gsub("%s+$", "")) }
    if DC.CopyOn("cls") or DC.CopyOn("mlv") or DC.CopyOn("zone") then
        lines[#lines + 1] = L("队伍：", "Party:")
        for i, m in ipairs(mem) do
            local parts = { i .. ". " .. m.name }
            if DC.CopyOn("cls") and m.cls then parts[#parts + 1] = m.cls end
            if DC.CopyOn("mlv") and m.lv then parts[#parts + 1] = string.format(L("%d级", "Lv%d"), m.lv) end
            if DC.CopyOn("zone") and m.zone then parts[#parts + 1] = m.zone end
            lines[#lines + 1] = table.concat(parts, " ")
        end
    end
    if DC.CopyOn("tell") and mem[1] then lines[#lines + 1] = L("游戏里密我：", "Whisper in game: ") .. mem[1].name end
    -- 贴到 QQ / 微信群，不受 255 字节限制：只加前缀不裁
    return DC.Tagged(table.concat(lines, "\n"), nil)
end

local copyBox
function DC.ShowCopy()
    if not copyBox then
        local f = CreateFrame("Frame", "GearInsightForeverDCCopy", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(440, 330); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            f:SetBackdropColor(0.04, 0.045, 0.06, 0.97); f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
        end
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -10)
        t:SetText(L("复制到聊天群", "Copy for group chat"))
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("TOPRIGHT", -12, -12)
        hint:SetText(L("Ctrl+C 复制，粘到 QQ / 微信群", "Ctrl+C to copy"))
        f.opts = {}
        local x, y = 12, -34
        for _, o in ipairs(DC.COPY_OPTS) do
            local key = o[1]
            local b = seg(f, o[2], 96, function() DC.SetCopyOn(key, not DC.CopyOn(key)); DC.RefreshCopy() end)
            if x + 100 > 430 then x, y = 12, y - 26 end
            b:SetPoint("TOPLEFT", x, y); x = x + 102
            f.opts[key] = b
        end
        local bg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        bg:SetPoint("TOPLEFT", 12, -92); bg:SetPoint("BOTTOMRIGHT", -12, 44)
        if bg.SetBackdrop then
            bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            bg:SetBackdropColor(0, 0, 0, 0.6); bg:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
        end
        local e = CreateFrame("EditBox", nil, bg)
        e:SetPoint("TOPLEFT", 6, -6); e:SetPoint("BOTTOMRIGHT", -6, 6)
        if e.SetMultiLine then e:SetMultiLine(true) end
        e:SetAutoFocus(false); e:SetFontObject(ChatFontNormal or GameFontHighlight)
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        -- 只给复制：改了就还原
        e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(rawget(f, "text") or ""); self:HighlightText() end end)
        e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        f.edit = e
        local close = ns.Button(f, L("关闭", "Close"), 90, 24, function() f:Hide() end)
        close:SetPoint("BOTTOMRIGHT", -12, 12)
        local again = ns.Button(f, L("刷新队伍", "Refresh"), 90, 24, function() DC.RefreshCopy() end)
        again:SetPoint("RIGHT", close, "LEFT", -8, 0)
        if UISpecialFrames then table.insert(UISpecialFrames, "GearInsightForeverDCCopy") end
        copyBox = f
        DC.copyBox = f
    end
    copyBox:Show()
    DC.RefreshCopy()
end
function DC.RefreshCopy()
    local f = copyBox
    if not f then return end
    for k, b in pairs(f.opts) do sel(b, DC.CopyOn(k)) end
    local text = DC.CopyText()
    rawset(f, "text", text)
    f.edit:SetText(text)
    f.edit:SetFocus(); f.edit:HighlightText()
end

function ns.BuildDungeonPanel(host, w, h)
    local P = CreateFrame("Frame", nil, host)
    P:SetAllPoints(host)
    DC.panel = P
    P.vSeek = seg(P, L("求组", "Find group"), 96, function() DC.view = "seek"; DC.Render() end)
    P.vSeek:SetPoint("TOPLEFT", 10, -6)
    P.vRec = seg(P, L("招人", "Recruit"), 96, function() DC.view = "recruit"; DC.Render() end)
    P.vRec:SetPoint("LEFT", P.vSeek, "RIGHT", 6, 0)
    local innerW = w - 20

    -- 求组
    local S = CreateFrame("Frame", nil, P); S:SetPoint("TOPLEFT", 10, -34); S:SetSize(innerW, h - 40)
    P.seek = S
    local lab = S:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lab:SetPoint("TOPLEFT", 0, -4); lab:SetText(L("我的职责：", "My role: "))
    S.roleBtns = {}
    local x = 74
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local b = seg(S, DC.RoleName(role), role == "DAMAGER" and 84 or 64, function() DC.SetRole(role); DC.Render() end)
        b:SetPoint("TOPLEFT", x, 0); x = x + (role == "DAMAGER" and 88 or 68)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(DC.RoleName(role), 1, 0.82, 0)
            GameTooltip:AddLine(DC.CanRole(role) and L("申请时私聊里写这个职责", "Sent in your apply whisper") or L("你的职业只能打伤害输出", "Your class can only deal damage"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        S.roleBtns[role] = b
    end
    S.fit = seg(S, L("适合我等级", "My level"), 92, function() local d = DC.DB(); d.fitLv = (d.fitLv == false); DC.Render() end)
    S.fit:SetPoint("TOPRIGHT", 0, 0)
    -- 11-13 第二行「副本：」[全部副本 ▼] 下拉（多选，记存档 dgFilter）……[全部副本] 一键清空（没筛选时亮金）
    rawset(S, "w", innerW)
    local dl = S:CreateFontString(nil, "OVERLAY", "GameFontNormal"); dl:SetPoint("TOPLEFT", 0, -30); dl:SetText(L("副本：", "Dungeon: "))
    S.dgBtn = seg(S, "", innerW - 74 - 98, function() DC.ToggleDgMenu() end)
    S.dgBtn:SetPoint("TOPLEFT", 74, -26)
    S.dgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("按副本筛选", "Filter by dungeon"), 1, 0.82, 0)
        GameTooltip:AddLine(L("点开选副本（可多选）：列出频道里有人组的副本（带条数）和适合你等级的副本；只看选上的副本，副本里的各个区都算", "Pick dungeons (multi-select); wings count as their dungeon"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    S.dgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    S.dgAll = seg(S, L("全部副本", "All"), 92, function() DC.ClearDg(); DC.Render() end)
    S.dgAll:SetPoint("TOPRIGHT", 0, -26)
    if S.HookScript then S:HookScript("OnHide", function() local f = rawget(S, "dgPop"); if f then f:Hide() end end) end
    S.listW = innerW - 24
    local sf, child = ns.Scroll(S, 0, -56, innerW - 24, h - 40 - 56 - 26)
    S.sf, S.list = sf, child
    S.empty = S:CreateFontString(nil, "OVERLAY", "GameFontDisable"); S.empty:SetPoint("TOPLEFT", 4, -66); S.empty:SetWidth(innerW - 30)
    S.empty:SetJustifyH("LEFT")
    rawset(S, "emptyDef", L("还没识别到组队消息：插件会读你加入的所有频道（综合 / 交易 / 寻求组队 / 大脚世界频道……），有人喊「死矿缺T」这类就会列在这里",
        "No group posts yet: the addon reads every channel you're in and lists posts like 'Deadmines LF tank' here"))
    S.empty:SetText(rawget(S, "emptyDef"))
    S.status = S:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); S.status:SetPoint("BOTTOMLEFT", 0, 4); S.status:SetWidth(innerW)
    S.status:SetJustifyH("LEFT")

    -- 招人
    local R = CreateFrame("Frame", nil, P); R:SetPoint("TOPLEFT", 10, -34); R:SetSize(innerW, h - 40)
    P.rec, R.w, R.listW = R, innerW, innerW - 24
    local prev = ns.Button(R, "<", 26, 22, function() local _, i = DC.RecDungeon(); DC.SetRecDungeon(i - 1); DC.Render() end)
    prev:SetPoint("TOPLEFT", 0, 0)
    local nxt = ns.Button(R, ">", 26, 22, function() local _, i = DC.RecDungeon(); DC.SetRecDungeon(i + 1); DC.Render() end)
    nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    R.dname = R:CreateFontString(nil, "OVERLAY", "GameFontNormal"); R.dname:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
    R.lvBtn = seg(R, L("喊等级", "Say level"), 80, function() local rr = DC.DB().rec; rr.noLv = not rr.noLv or nil; DC.Render() end)
    R.lvBtn:SetPoint("TOPRIGHT", 0, 0)
    R.ssBtn = seg(R, L("有SS可拉", "Warlock summon"), 80, function() local rr = DC.DB().rec; rr.ss = not rr.ss or nil; DC.Render() end)
    R.ssBtn:SetPoint("RIGHT", R.lvBtn, "LEFT", -4, 0)
    R.loTxt = R:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); R.loTxt:SetPoint("TOPLEFT", 0, -34)
    R.sLo = slider(R, innerW - 90); R.sLo:SetPoint("TOPLEFT", 80, -32)
    R.hiTxt = R:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); R.hiTxt:SetPoint("TOPLEFT", 0, -58)
    R.sHi = slider(R, innerW - 90); R.sHi:SetPoint("TOPLEFT", 80, -56)
    R.sLo:SetScript("OnValueChanged", function(_, v) if rawget(R, "busy") then return end local _, hi = DC.RecRange(); DC.SetRange(v, math.max(hi, v)); DC.Render() end)
    R.sHi:SetScript("OnValueChanged", function(_, v) if rawget(R, "busy") then return end local lo = DC.RecRange(); DC.SetRange(math.min(lo, v), v); DC.Render() end)
    local nl = R:CreateFontString(nil, "OVERLAY", "GameFontNormal"); nl:SetPoint("TOPLEFT", 0, -86); nl:SetText(L("需要：", "Need: "))
    R.needBtns = {}
    x = 50
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local b = seg(R, DC.RoleName(role), role == "DAMAGER" and 84 or 64, function()
            local rr = DC.DB().rec.roles; rr[role] = not rr[role] or nil; DC.Render()
        end)
        b:SetPoint("TOPLEFT", x, -82); x = x + (role == "DAMAGER" and 88 or 68)
        R.needBtns[role] = b
    end
    R.abbrBtn = seg(R, L("简称", "Short"), 60, function() local rr = DC.DB().rec; rr.abbr = not rr.abbr or nil; DC.Render() end)
    R.abbrBtn:SetPoint("TOPRIGHT", 0, -82)
    R.abbrBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("简称", "Short names"), 1, 0.82, 0)
        GameTooltip:AddLine(L("勾上后喊话里职责写 T / N / DPS，职业写 ZS、FS、MS 这类缩写", "Shout roles as T / N / DPS and classes as short codes"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    R.abbrBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    R.avgBtn = seg(R, L("报均级", "Avg lvl"), 64, function() local rr = DC.DB().rec; rr.avg = not rr.avg or nil; DC.Render() end)
    R.avgBtn:SetPoint("RIGHT", R.abbrBtn, "LEFT", -4, 0)
    R.avgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("报当前平均等级", "Report average level"), 1, 0.82, 0)
        GameTooltip:AddLine(L("勾上后喊话里带一句「当前平均××级」（你和队友的平均等级）。默认不带。", "Adds your party's current average level to the shout. Off by default."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    R.avgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local kl = R:CreateFontString(nil, "OVERLAY", "GameFontNormal"); kl:SetPoint("TOPLEFT", 0, -114); kl:SetText(L("职业：", "Class: "))
    R.clsBtns = {}
    x = 50
    for _, c in ipairs(DC.CLS_ORDER) do
        local b = seg(R, "", 36, function() DC.CycleCls(c); DC.Render() end)
        b:SetPoint("TOPLEFT", x, -110); x = x + 38
        -- 11-12 用户「换成职业图标」：职业图标图集（CLASS_ICON_TCOORDS，没有就用内置坐标）+ 「不要」叠红 ×
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); ic:SetPoint("CENTER")
        ic:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local tc = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c]) or DC.CLS_TC[c]
        if tc then ic:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        local no = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); no:SetPoint("CENTER", 0, 0); no:SetText("|cffff3333×|r")
        rawset(b, "_ic", ic); rawset(b, "_no", no)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(DC.ClsName(c), 1, 0.82, 0)
            GameTooltip:AddLine(L("点一下切换：不限 → 要 → 不要（会写进喊话；来密你的人里也会标出来）", "Click: any -> wanted -> not wanted"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        R.clsBtns[c] = b
    end
    local cl = R:CreateFontString(nil, "OVERLAY", "GameFontNormal"); cl:SetPoint("TOPLEFT", 0, -142); cl:SetText(L("发到：", "Send to: "))
    R.chanBox = CreateFrame("Frame", nil, R); R.chanBox:SetPoint("TOPLEFT", 50, -138); R.chanBox:SetSize(innerW - 50, 52)
    R.noChan = R:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); R.noChan:SetPoint("TOPLEFT", 50, -142)
    R.noChan:SetText(L("还没加入任何频道", "Not in any channel"))
    -- 11-10 用户截图：频道多（加了「公会」）换到第三行压住「会发」→ 下半截装进 R.lower，按频道行数往下挪
    local LOW = 196   -- 11-12 多了「职业」一排 +28
    R.lower = CreateFrame("Frame", nil, R); R.lower:SetPoint("TOPLEFT", 0, -LOW); R.lower:SetSize(innerW, h - 40 - LOW)
    R.lowY = LOW
    local LR = R.lower
    local pl = LR:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); pl:SetPoint("TOPLEFT", 0, -3); pl:SetText(L("会发：", "Will send: "))
    local ebg = CreateFrame("Frame", nil, LR, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ebg:SetPoint("TOPLEFT", 40, 2); ebg:SetSize(innerW - 40 - 58, 20)
    if ebg.SetBackdrop then
        ebg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        ebg:SetBackdropColor(0, 0, 0, 0.5); ebg:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
    end
    local e = CreateFrame("EditBox", nil, ebg)
    e:SetPoint("TOPLEFT", 4, 0); e:SetPoint("BOTTOMRIGHT", -4, 0)
    e:SetAutoFocus(false); e:SetFontObject(GameFontHighlightSmall); e:SetMaxLetters(255)
    local function save(self)
        DC.SaveCustom(self:GetText())
        self:ClearFocus(); DC.Render()
    end
    e:SetScript("OnEnterPressed", save)
    e:SetScript("OnEditFocusLost", function(self) DC.SaveCustom(self:GetText()); DC.Render() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); DC.Render() end)
    e:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- 11-13 用户「信息被缩略掉了」：框里一行放不下 → 悬停先给完整一句
        GameTooltip:AddLine(L("会发：", "Will send: "), 1, 0.82, 0)
        GameTooltip:AddLine(DC.SendText(), 1, 1, 1, true)
        GameTooltip:AddLine(L("点进去改，回车保存（每个副本各存一句）", "Click to edit, Enter to save (one per dungeon)"), 1, 0.82, 0)
        GameTooltip:AddLine(L("队伍人数「4=1」会跟着队伍自动变", "The party count (4=1) keeps updating"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
    R.edit = e
    R.def = ns.Button(LR, L("默认", "Reset"), 52, 20, function()
        local d = DC.RecDungeon(); local rr = DC.DB().rec
        if d and rr.custom then rr.custom[d.n] = nil end
        e:ClearFocus(); DC.Render()
    end)
    R.def:SetPoint("TOPRIGHT", 0, 2)
    R.send = ns.Button(LR, "", 200, 26, function()
        local n, why = DC.Shout()
        if n > 0 then ns.Print(string.format(L("已发到 %d 个频道：%s", "Sent to %d channel(s): %s"), n, DC.SendText())) end
        local lfg = ns.LfgListAuto and ns.LfgListAuto.OnSend(n)   -- 11-13 同一次点击里顺带挂集合石（LfgListAuto.lua，HOLD）
        if n == 0 and why == "nochan" and not lfg then ns.Print(L("没有勾选的频道", "No channel ticked")) end
        DC.Render()
    end)
    R.send:SetPoint("TOPLEFT", 0, -22)
    R.copy = ns.Button(LR, L("复制到聊天群", "Copy for chat"), 130, 26, function() DC.ShowCopy() end)
    R.copy:SetPoint("LEFT", R.send, "RIGHT", 8, 0)
    local rl = LR:CreateFontString(nil, "OVERLAY", "GameFontNormal"); rl:SetPoint("TOPLEFT", 0, -58); rl:SetText(L("来密我的人", "Whispers to me"))
    R.askBtn = seg(LR, L("自动反问", "Auto-ask"), 80, function() local rr = DC.DB().rec; if rr.autoAsk == false then rr.autoAsk = nil else rr.autoAsk = false end; DC.Render() end)
    R.askBtn:SetPoint("TOPRIGHT", 0, -54)
    R.askBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("自动反问", "Auto-ask"), 1, 0.82, 0)
        GameTooltip:AddLine(L("密你的人没报等级或职责，插件过 2 秒自动密他「老哥报下等级和职责哈」，每人只问一次；他补的会合进同一行", "Whisper back once asking for level / role if missing"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    R.askBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 11-12 前缀开关（默认开）：管招人喊话 / 申请私聊 / 自动反问 / 复制到聊天群
    R.tagBtn = seg(LR, L("带标识", "Tag"), 64, function() local rr = DC.DB().rec; rr.noTag = (not rr.noTag) or nil; DC.Render(); if DC.copyBox and DC.copyBox:IsShown() then DC.RefreshCopy() end end)
    R.tagBtn:SetPoint("RIGHT", R.askBtn, "LEFT", -4, 0)
    R.tagBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("带标识 ", "Tag ") .. DC.TAG, 1, 0.82, 0)
        GameTooltip:AddLine(L("插件发出去的话开头加「", "Prefix everything the addon sends with \"") .. DC.TAG
            .. L("」：招人喊话、申请私聊、自动反问、复制到聊天群", "\": recruit shouts, apply whispers, auto-ask, chat copy"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    R.tagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- 11-12 满员自动通知（两个都默认关）
    local function fullBtn(key, zh, en, w, tipZh, tipEn, anchor)
        local b = seg(LR, L(zh, en), w, function()
            local rr = DC.DB().rec; rr[key] = (not rr[key]) or nil
            if ns.GroupSync then pcall(ns.GroupSync) end   -- 11-13 第 5 期：满员通知 / 法师吃喝总开关一改，重算该加载的、该注册的
            DC.Render()
        end)
        b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L(zh, en), 1, 0.82, 0)
            GameTooltip:AddLine(L(tipZh, tipEn), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    R.fullTellBtn = fullBtn("fullTell", "满员私聊", "Full: tell", 72,
        "队伍满 5 人的那一下，自动分别私聊另外四个人「人员已满，立刻发车」（你是队长才发，每次满员只发一次）",
        "When the party hits 5, whisper each member once (leader only)", R.tagBtn)
    R.fullSayBtn = fullBtn("fullSay", "满员喊话", "Full: party", 72,
        "队伍满 5 人的那一下，自动在队伍频道说「人员已满，立刻发车」（你是队长才发，每次满员只发一次）",
        "When the party hits 5, say it once in party chat (leader only)", R.fullTellBtn)
    -- 11-12 副本里跟法师交易自动要吃喝（默认关）
    R.mageBtn = fullBtn("mageAsk", "法师吃喝", "Mage food", 72,
        "在副本里跟法师一打开交易窗，自动密他「求水和面包，谢谢」（没蓝的职业只要面包；同一个法师 3 分钟内只密一次）",
        "Inside a dungeon, opening a trade with a mage whispers them asking for water / food (once per 3 min per mage)", R.fullSayBtn)
    -- 11-12 自动要水 / 自动发水（MageWater.lua，HOLD）：右键 = 细项设置，鼠标提示换成完整说明；不在就跟 1.0.0 一样
    if R.mageBtn.RegisterForClicks then R.mageBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local mageClick, mageTip = R.mageBtn:GetScript("OnClick"), R.mageBtn:GetScript("OnEnter")
    R.mageBtn:SetScript("OnClick", function(self, btn, ...)
        if btn == "RightButton" and ns.MageWater and ns.MageWater.OpenSettings then ns.MageWater.OpenSettings(self); return end
        if mageClick then mageClick(self, btn, ...) end
        if ns.MageWater and ns.MageWater.RefreshSettings then pcall(ns.MageWater.RefreshSettings) end
    end)
    R.mageBtn:SetScript("OnEnter", function(self)
        if ns.MageWater and ns.MageWater.Tip then ns.MageWater.Tip(self) elseif mageTip then mageTip(self) end
    end)
    -- 表头
    local hd = CreateFrame("Frame", nil, LR); hd:SetPoint("TOPLEFT", 0, -78); hd:SetSize(innerW - 24, 16)
    for _, col in ipairs({ { L("名字", "Name"), 4 }, { L("等级职责", "Lv/Role"), 90 }, { L("说的话（点行展开）", "Said (click a row)"), 140 } }) do
        local fs = hd:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); fs:SetPoint("LEFT", col[2], 0); fs:SetText(col[1])
    end
    R.repHead = hd
    -- 11-13 用户「记录在这里不要老清除」：列表不再自己清，表头这一行最右边给个「清空」
    R.clearBtn = ns.Button(hd, L("清空", "Clear"), 44, 16, function() DC.ClearReplies(); DC.Render() end)
    R.clearBtn:SetPoint("RIGHT", hd, "RIGHT", 0, 0)
    R.clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("清空「来密我的人」", "Clear the list"), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L("列表不会自己清：重新喊话、/reload、重新登录都还在；最多留 %d 人、%d 小时，超出丢最旧的。只删一个人点那一行最右边的 ×", "The list is kept across shouts, /reload and relogs (max %d people, %d h; oldest dropped). Use x on a row to remove one"), DC.REC_MAX, math.floor(DC.REC_AGE / 3600)), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    R.clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local rsf, rchild = ns.Scroll(LR, 0, -96, innerW - 24, h - 40 - 246 - 6 - 52 - 28 - 18)
    R.rsf, R.rep = rsf, rchild
    R.h = h
    R.repEmpty = LR:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); R.repEmpty:SetPoint("TOPLEFT", 4, -84)
    R.repEmpty:SetWidth(innerW - 32); R.repEmpty:SetJustifyH("LEFT")
    R.repEmpty:SetText(L("喊完 15 分钟内密你的人会一直列在这里（/reload、重新登录也在），点「邀请」拉进队，点「清空」清掉",
        "Anyone who whispers you within 15 min of a shout stays listed here (even after /reload). Invite them, or Clear the list"))

    -- 开着时每 5 秒刷一下「多久前」/ 冷却
    local acc = 0
    P:SetScript("OnUpdate", function(_, el) acc = acc + (el or 0); if acc >= 5 then acc = 0; pcall(DC.Render) end end)
    P:SetScript("OnShow", function() pcall(DC.Render) end)
    DC.Render()
    return true
end
function ns.RefreshDungeonPanel() pcall(DC.Render) end
