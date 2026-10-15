-- 掉落记录 + 导出（众包掉落表）
-- 只在副本里记：打开拾取窗口时读每格物品 + 来源（首领战结束 60 秒内 = 首领；GameObject = 箱子；其它 = 小怪）
-- 导出串 "GIFD1:" + base64url(JSON)，格式见 10-04 发给网站会话的约定：
-- {v,build,region,uid,lvl,cls,recs:[{t,inst,diff,src,enc,npc,items,gs}]}
-- 不记角色名、服务器名；uid 是随机串，只用来去重
local _, ns = ...

local MAX_RECS = 500
local BOSS_WINDOW = 60
local lastEnc = { id = 0, t = 0 }

local function npcFromGUID(guid)
    if not guid then return "trash", 0 end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "GameObject" then return "chest", tonumber(id) or 0 end
    if kind == "Creature" or kind == "Vehicle" then return "trash", tonumber(id) or 0 end
    return "trash", 0
end

-- 名字表（10-04 网站会话：Beta 没有手册，串里只有 ID 网站显示不了名字）→ 导出时带 names，取客户端当前语言
local function remember(kind, id, name)
    if not id or id == 0 or not name or name == "" then return end
    local N = ns.db.lootNames
    N[kind] = N[kind] or {}
    N[kind][tostring(id)] = name
end

-- 拾取窗口开着时，来源通常就是当前目标 / 鼠标指向
local function unitNameForGUID(guid)
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if UnitGUID and UnitGUID(u) == guid then return UnitName(u) end
    end
end

local function itemIdFromLink(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

function ns.RecordLoot(now)
    local inInst, itype = IsInInstance()
    if not inInst or (itype ~= "party" and itype ~= "raid") then return 0 end
    local instName, _, diff, _, _, _, _, instID = GetInstanceInfo()
    ns.db.lootNames = ns.db.lootNames or {}
    remember("inst", instID, instName)
    local db = ns.db
    local bySrc = {}
    local n = GetNumLootItems and GetNumLootItems() or 0
    for slot = 1, n do
        local link = GetLootSlotLink(slot)
        local id = itemIdFromLink(link)
        if id then
            remember("items", id, link:match("%[(.-)%]"))
            local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
            local key = guid or "?"
            if not db.lootSeen[key] then
                bySrc[key] = bySrc[key] or { guid = guid, items = {} }
                table.insert(bySrc[key].items, id)
            end
        end
    end
    local added = 0
    now = now or time()
    for key, b in pairs(bySrc) do
        local src, npc = npcFromGUID(b.guid)
        if src == "trash" and b.guid then remember("npc", npc, unitNameForGUID(b.guid)) end
        local enc = 0
        if src == "trash" and lastEnc.id > 0 and now - lastEnc.t <= BOSS_WINDOW then
            src, enc = "boss", lastEnc.id
            lastEnc.id = 0   -- 只算首领战后第一个拾取的怪；之后再摸的小怪不算首领掉落
        end
        if #db.loot >= MAX_RECS then table.remove(db.loot, 1); db.lootSent = math.max(0, db.lootSent - 1) end
        table.insert(db.loot, { t = now, inst = instID or 0, diff = diff or 0, src = src, enc = enc, npc = npc,
            items = b.items, gs = (GetNumGroupMembers and GetNumGroupMembers()) or 1 })
        if b.guid then db.lootSeen[key] = now end
        added = added + 1
    end
    -- 已拾取的来源只留 2 小时，防止存档越积越大
    for k, t in pairs(db.lootSeen) do if now - t > 7200 then db.lootSeen[k] = nil end end
    return added
end

-- all=true：连已导出过的一起（登出时写进存档给更新器自动上传用；服务端按 (uid, t, enc, npc) 去重）
function ns.LootExportString(all)
    local db = ns.db
    local recs = {}
    for i = all and 1 or (db.lootSent + 1), #db.loot do recs[#recs + 1] = db.loot[i] end
    if #recs == 0 then return nil, 0 end
    local _, token = UnitClass("player")
    local build = GetBuildInfo and select(1, GetBuildInfo()) or ""
    local bnum = GetBuildInfo and select(2, GetBuildInfo()) or ""
    local region = GetCurrentRegionName and GetCurrentRegionName() or ""
    local doc = { v = 1, build = build .. "." .. bnum, region = string.lower(region or ""), uid = db.uid,
        lvl = UnitLevel("player") or 0, cls = token or "", recs = recs }
    -- 只带这批记录用到的名字
    local N, used = db.lootNames or {}, { items = {}, enc = {}, npc = {}, inst = {} }
    local function pick(kind, id)
        local nm = N[kind] and N[kind][tostring(id)]
        if nm then used[kind][tostring(id)] = nm end
    end
    for _, r in ipairs(recs) do
        pick("inst", r.inst); pick("enc", r.enc); pick("npc", r.npc)
        for _, it in ipairs(r.items) do pick("items", it) end
    end
    local any = false
    for _, t in pairs(used) do if next(t) then any = true end end
    if any then doc.names = used end
    return "GIFD1:" .. ns.B64url(ns.JSON(doc)), #recs
end

function ns.ExportLoot()
    local s, n = ns.LootExportString()
    if not s then
        ns.Print(ns.L("还没有新的掉落记录（只记副本里的拾取）", "No new drops recorded yet (only inside dungeons and raids)"))
        return
    end
    ns.ShowBox(ns.L("导出掉落（", "Export drops (") .. n .. ns.L(" 条）", ")"),
        ns.L(ns.UPLOAD_HINT_ZH .. "\n上传后输入 " .. (ns.SlashHint or "/gif") .. " loot clear 清掉已导出的",
            ns.UPLOAD_HINT_EN .. "\nThen " .. (ns.SlashHint or "/gif") .. " loot clear"), ns.UploadURL(s))
    ns.db.lootPending = #ns.db.loot
end

function ns.ClearExportedLoot()
    local db = ns.db
    local upto = db.lootPending or 0
    if upto <= db.lootSent then ns.Print(ns.L("没有已导出待清的记录", "Nothing exported to clear")); return end
    for _ = 1, upto do table.remove(db.loot, 1) end
    db.lootSent, db.lootPending = 0, nil
    ns.Print(ns.L("已清掉导出过的记录，剩 ", "Cleared exported drops, left: ") .. #db.loot)
end

table.insert(ns.modules, function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("LOOT_OPENED")
    ns._lootEvent = function(_, e, a1, a2, _, _, success)
        if e == "ENCOUNTER_END" then
            if success == 1 then
                lastEnc.id, lastEnc.t = a1 or 0, time()
                ns.db.lootNames = ns.db.lootNames or {}
                remember("enc", a1, a2)
            end
        elseif e == "LOOT_OPENED" then
            pcall(ns.RecordLoot)
        end
    end
    f:SetScript("OnEvent", ns._lootEvent)
end)
