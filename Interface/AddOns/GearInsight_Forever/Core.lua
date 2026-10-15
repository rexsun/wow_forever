-- GearInsight 无限版：公共工具（语言、存档、复制框、编码、斜杠命令）
local ADDON, ns = ...
_G.GearInsightForever = ns

local LOC = GetLocale and GetLocale() or "enUS"
ns.zh = (LOC == "zhCN" or LOC == "zhTW")

-- 中英二选一：中文客户端用 cn，其它用 en（en 空时退回 cn）
function ns.L(cn, en)
    if ns.zh then return cn end
    if en and en ~= "" then return en end
    return cn
end

-- 插件版本号：唯一来源 = toc 的 ## Version（标题栏 / 资讯页都读这个，⛔别在 Lua 里写死版本号字符串）
function ns.AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = false, nil
    if get then ok, v = pcall(get, ADDON or "GearInsight_Forever", "Version") end
    return (ok and type(v) == "string") and v or ""
end

-- 英文客户端字体没有全角标点 / 中点 / 箭头 / 长破折号（会显示成方块）→ 换成半角
function ns.EnSafe(s)
    if ns.zh or not s then return s end
    s = s:gsub("–", "-"):gsub("（", " ("):gsub("）", ")"):gsub("、", ", "):gsub("·", "-"):gsub("→", "->"):gsub("：", ": ")
    return s
end

-- 10-10 用户贴报错「attempt to compare local 'name' (a secret string value …)」：《无限》客户端和正式服 12.x 一样有「保密值」——
-- 战斗中 / 动作条悬停时技能名、物品 ID、单位 GUID 可能是保密值，插件只要比较 / 拼接 / 当表键用就报错。
-- 凡是从提示框 / 单位 / 战斗拿到的值，先过 ns.Secret 再用。
function ns.Secret(v)
    if issecretvalue then return issecretvalue(v) and true or false end
    return false
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GearInsight 无限版|r " .. tostring(msg))
end

-- ---------- 存档 ----------
local DEFAULTS = { leveling = { shown = true }, loot = {}, lootSeen = {}, lootSent = 0, lootNames = {} }

local function newUid()
    local t = {}
    for i = 1, 16 do t[i] = string.format("%x", math.random(0, 15)) end
    return table.concat(t)
end

function ns.InitDB()
    GearInsightForeverDB = GearInsightForeverDB or {}
    local db = GearInsightForeverDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                local c = {}
                for kk, vv in pairs(v) do c[kk] = vv end
                db[k] = c
            else
                db[k] = v
            end
        end
    end
    if not db.uid then db.uid = newUid() end
    ns.db = db
end

-- ---------- JSON（只编码，导出用）----------
local function jsonStr(s)
    -- ⛔别用 %c：某些 locale 下中文的 UTF-8 字节也算控制字符，会被拆成 \u00xx 变乱码
    s = tostring(s):gsub('[%z\1-\31"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        return string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

function ns.JSON(v)
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return tostring(v)
    end
    if tv == "string" then return jsonStr(v) end
    if tv == "table" then
        local arr, n = isArray(v)
        local out = {}
        if arr and n > 0 then
            for i = 1, n do out[i] = ns.JSON(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        if arr and next(v) == nil and v.__array then return "[]" end
        local keys = {}
        for k in pairs(v) do if k ~= "__array" then keys[#keys + 1] = tostring(k) end end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            out[#out + 1] = jsonStr(k) .. ":" .. ns.JSON(val)
        end
        if #out == 0 and v.__array then return "[]" end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

-- ---------- base64url（不补 =）----------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
function ns.B64url(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
        if b then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) end
        if c then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) end
    end
    return table.concat(out)
end

-- ---------- 地图打标（10-11 用户「点击标注的同时，打开小地图」）----------
-- 副本任务接任务的人 / 副本入口 / 野外稀有 共用：游戏地图标记 + 超级追踪；装了 TomTom 另外给每个点打 TomTom 点；
-- 然后把世界地图打开并切到那个地区（战斗中不弹，免得挡视线）。pts = {{x, y}, …}（0–100），第一个点用游戏标记
function ns.ShowOnMap(ui, pts, title)
    if not ui or ui == 0 or not pts or not pts[1] then return false end
    local x, y = pts[1][1] or 0, pts[1][2] or 0
    local pinned = false
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(ui)) then
        pinned = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100))
        if pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
    local TT = _G.TomTom
    local tomtom = false
    if TT and TT.AddWaypoint then
        for _, p in ipairs(pts) do
            if pcall(TT.AddWaypoint, TT, ui, p[1] / 100, p[2] / 100, { title = title, persistent = false, minimap = true, world = true, from = "GearInsight" }) then tomtom = true end
        end
    end
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat then
        if OpenWorldMap then pcall(OpenWorldMap, ui)
        elseif WorldMapFrame then
            if not WorldMapFrame:IsShown() and ToggleWorldMap then pcall(ToggleWorldMap) end
            if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, ui) end
        end
    end
    return pinned or tomtom, tomtom
end

-- ---------- 复制 / 粘贴框 ----------
local box
-- 10-07 用户截图「UI 也要优化」：原来框高写死 130，说明一折行就压住输入框，确认键 90 宽装不下「已贴好，清掉已导出」→ 字叠在一起。
--   现在：说明多行自动撑高、输入框跟在说明下面、按钮宽度按文字算、框高跟内容走；底部左边「关闭」右边确认。
local function makeBox()
    local f = CreateFrame("Frame", "GearInsightForeverCopy", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(580, 170); f:SetPoint("CENTER", 0, 80); f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.hint:SetPoint("TOPLEFT", 14, -36); f.hint:SetPoint("RIGHT", -14, 0); f.hint:SetJustifyH("LEFT"); f.hint:SetJustifyV("TOP")
    f.hint:SetSpacing(4)
    local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", 6, -10); e:SetPoint("RIGHT", -18, 0); e:SetHeight(26)
    e:SetAutoFocus(true); e:SetMaxLetters(0)
    e:SetScript("OnEscapePressed", function() f:Hide() end)
    f.edit = e
    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetSize(90, 26); ok:SetPoint("BOTTOMRIGHT", -14, 12)
    f.ok = ok
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(80, 26); cancel:SetPoint("BOTTOMLEFT", 14, 12); cancel:SetText(ns.L("关闭", "Close"))
    cancel:SetScript("OnClick", function() f:Hide() end)
    f.cancel = cancel
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

-- mode = "copy"：只读，全选；"paste"：粘贴后点按钮回调 onOk(text)
-- 导出串 → 上传网址（10-07 用户截图「有问题，需要加上url」）：浏览器打开这个网址，网站自动把串填进去上传；
--   放在 # 后面（不进服务器日志、不受网址长度限制）；整行粘到小程序粘贴框也行（服务端在整段里找 GIFS1: / GIFD1:）
function ns.UploadURL(code)
    return (ns.zh and "https://gearinsight.cn" or "https://gearinsight.app") .. "/wow/forever/loot#d=" .. (code or "")
end
ns.UPLOAD_HINT_ZH = "① Ctrl+C 复制下面这行网址\n② 粘到浏览器地址栏打开，自动上传（手机微信里打开也行）\n也可以把整行粘到小程序「无限 · 公测数据」"
ns.UPLOAD_HINT_EN = "1. Ctrl+C to copy the link below\n2. Open it in your browser - it uploads automatically"

function ns.ShowBox(title, hint, text, onOk, okText)
    box = box or makeBox()
    box.title:SetText(title or "")
    box.hint:SetText(hint or "")
    box.edit:SetText(text or "")
    box.edit:SetFocus(); box.edit:HighlightText()
    -- 框高跟说明行数走；确认键宽度按文字
    local hh = (box.hint.GetStringHeight and box.hint:GetStringHeight()) or 14
    box:SetHeight(36 + math.max(14, hh) + 10 + 26 + 18 + 26 + 12)
    box.cancel:SetShown(onOk ~= nil)
    if onOk then
        box.ok:SetText(okText or ns.L("确定", "OK"))
        local fs = box.ok.GetFontString and box.ok:GetFontString()
        local w = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
        box.ok:SetWidth(math.max(90, (w or 0) + 30))
        box.ok:SetScript("OnClick", function() onOk(box.edit:GetText() or ""); box:Hide() end)
        box.edit:SetScript("OnEnterPressed", function() onOk(box.edit:GetText() or ""); box:Hide() end)
    else
        box.ok:SetText(ns.L("关闭", "Close")); box.ok:SetWidth(90)
        box.ok:SetScript("OnClick", function() box:Hide() end)
        box.edit:SetScript("OnEnterPressed", function() box:Hide() end)
    end
    box:Show()
end

-- ---------- 启动 + 斜杠命令 ----------
ns.modules = {}
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
-- ⛔ 10-07：别注册 ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED（只给暴雪 UI），插件一注册就被判
--    「GearInsight_Forever -> Frame:RegisterEvent()」禁用 —— 当时加来当诊断，结果自己成了报错源
ev:SetScript("OnEvent", function(_, e, name)
    if name ~= ADDON then return end
    ns.InitDB()
    for _, m in ipairs(ns.modules) do pcall(m) end
    ev:UnregisterEvent("ADDON_LOADED")
end)

-- 10-07 用户「命令改成 /gi」：主命令 /gi，/gif 留着兼容。
-- ⛔ 正式服 GearInsight 也是 /gi：无限客户端开了「加载过期插件」时两个可能同时在 → 别人已经占了 /gi 就不抢，只用 /gif
local function slashTaken(cmd)
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 6) == "SLASH_" and v == cmd and not k:find("GEARINSIGHTFOREVER", 1, true) then return true end
    end
    return false
end
local C = slashTaken("/gi") and "/gif" or "/gi"
ns.SlashHint = C

local function help()
    ns.Print(ns.L("命令：" .. C .. " 打开主界面 · " .. C .. " lv 升级指引 · " .. C .. " card 战绩卡（微信扫码进小程序，计入报到）"
        .. " · " .. C .. " talent 导入配点码 · " .. C .. " talent qr 当前配点发到手机 · " .. C .. " talent pop 热门配点一键套用"
        .. " · " .. C .. " macro 宏库 · " .. C .. " news 资讯 · " .. C .. " data 导出数据 · " .. C .. " data off|on 关 / 开记录",
        "Commands: " .. C .. " open window · " .. C .. " lv leveling · " .. C .. " card beta card QR · " .. C .. " talent import build · " .. C .. " talent qr build to phone"
        .. " · " .. C .. " talent pop popular builds · " .. C .. " macro · " .. C .. " news · " .. C .. " data export · " .. C .. " data off|on"))
end

SLASH_GEARINSIGHTFOREVER1 = "/gif"
if C == "/gi" then SLASH_GEARINSIGHTFOREVER2 = "/gi" end
SlashCmdList.GEARINSIGHTFOREVER = function(msg)
    -- 原样的参数（不转小写）：自定义文字要用（10-12 /gi qm text …：lower() 在某些环境会改坏中文字节 →「任务」变「任嚡」）
    local raw = (msg or ""):gsub("^[ 	]+", ""):gsub("[ 	]+$", "")
    local rawRest = raw:match("^[^ 	]*[ 	]*(.-)$") or ""
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" then ns.ToggleMain()
    elseif cmd == "lv" or cmd == "level" then ns.ToggleLeveling()
    elseif cmd == "wish" or cmd == "lootui" then ns.ToggleMain("loot")
    elseif cmd == "tier" then ns.ToggleMain("tier")
    elseif cmd == "macro" or cmd == "m" then ns.ToggleMain("macro")
    elseif cmd == "news" then ns.ToggleMain("news")
    elseif cmd == "talent" or cmd == "t" then
        if rest == "qr" then ns.ShowTalentQR()
        elseif rest == "pop" then ns.ShowPopBuilds()
        else ns.ImportTalentDialog() end
    elseif cmd == "probe" and rest == "keys" and ns.KeysProbe then ns.KeysProbe.Toggle()   -- 键位手法 P0 探针（HOLD）
    elseif cmd == "keys" and rest == "hud" and ns.KeysRot then ns.KeysRot.Toggle()   -- 手法钉板（HOLD）
    elseif cmd == "keys" and rest == "panel" and ns.KeysHud then ns.KeysHud.Toggle()   -- 决策 HUD 分轨面板（HOLD）
    elseif cmd == "keys" and (rest == "off" or rest == "on") then   -- 录像用：隐藏 / 恢复还没发布的页签（重载生效）
        ns.db.hideHold = (rest == "off") or nil
        ns.Print(rest == "off" and ns.L("没发布的页签已隐藏，/reload 后生效（/gif keys on 恢复）", "Unreleased tabs hidden after /reload (/gif keys on to restore)")
            or ns.L("没发布的页签已恢复，/reload 后生效", "Unreleased tabs restored after /reload"))
    elseif cmd == "keys" and rest == "macros" and ns.Keys and ns.Keys.DebugMacros then ns.Keys.DebugMacros()   -- 10-12 宏格识别诊断
    elseif cmd == "keys" and rest == "restore" and ns.Keys and ns.Keys.RestoreStolen then   -- 10-12 改键顶替掉的原功能放回
        local n, why = ns.Keys.RestoreStolen()
        ns.Print(why == "combat" and ns.L("战斗中不能改键位，脱战再来", "Can't change keys in combat")
            or string.format(ns.L("放回了 %d 个被顶替的原功能键", "Restored %d replaced key(s)"), n or 0))
    elseif cmd == "keys" and ns.Keys then ns.ToggleMain("keys")   -- 键位页在 HOLD 里时不响应
    elseif ns.ExtraSlash and ns.ExtraSlash[cmd] then ns.ExtraSlash[cmd](rest, rawRest)   -- 10-12 support / route / site（Offsite.lua、Route.lua 自己挂）
    elseif cmd == "card" or cmd == "qr" then ns.ShowCardQR()
    elseif cmd == "loot" then
        if rest == "clear" then ns.ClearExportedLoot() else ns.ExportLoot() end
    elseif cmd == "data" then
        if rest == "" and ns.ExportAll then ns.ExportAll()
        elseif rest == "clear" then ns.ClearExportedStats()
        elseif rest == "off" then ns.SetCollect(false)
        elseif rest == "on" then ns.SetCollect(true)
        else ns.ExportStats() end
    else help() end
end
