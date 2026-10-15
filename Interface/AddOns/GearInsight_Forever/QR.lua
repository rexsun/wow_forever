-- 二维码编码器（纯 Lua 5.1，零依赖）：字节模式 · 纠错 L / M · 版本 1–13 · 自动选掩码。
-- 自写实现，按 ISO/IEC 18004 与 Project Nayuki「QR Code generator」（MIT）的公开算法结构写成，无第三方代码拷贝。
-- 用法：local m, ver = ns.QR.Encode("https://…", "M")  → m[row][col] = true(黑) / false(白)，行列 1 起；放不下返回 nil
-- 渲染：ns.ShowQR(title, foot, text)；同一行连续黑格合成一块贴图，69×69 也只有几百块。
-- ⛔ 版本上限 13（69×69）：再大游戏里一格太小，手机扫不出来。负载超长由调用方降级（Card.lua 少带 lvt / top）。
-- ⛔ 本文件在 GearInsight_Forever 与 GuildInsight 两个插件里**逐字节相同**（各插件只能加载自己目录下的文件，没法共享一份）：
--   改这里必须同步拷到另一处；scripts/gi_guild_addon_test.py 会比对两份 md5。窗口名按插件目录名生成，两个插件同时加载也不冲突。
local ADDON, ns = ...
local FRAME_NAME = (tostring(ADDON or "GI"):gsub("[^%w]", "")) .. "QR"   -- GearInsight_Forever → GearInsightForeverQR；GuildInsight → GuildInsightQR
local QR = {}
ns.QR = QR

local floor = math.floor

-- ---------- 位运算（WoW 有 bit 库；lupa / 其它环境用算术实现）----------
local bxor
if bit and bit.bxor then
    bxor = bit.bxor
else
    bxor = function(a, b)
        local r, p = 0, 1
        while a > 0 or b > 0 do
            local x, y = a % 2, b % 2
            if x ~= y then r = r + p end
            a, b, p = floor(a / 2), floor(b / 2), p * 2
        end
        return r
    end
end
local function getBit(v, i) return floor(v / 2 ^ i) % 2 == 1 end

-- ---------- GF(256)，本原多项式 0x11D ----------
local EXP, LOG = {}, {}
do
    local x = 1
    for i = 0, 254 do
        EXP[i] = x; LOG[x] = i
        x = x * 2
        if x >= 256 then x = bxor(x, 0x11D) end
    end
    for i = 255, 511 do EXP[i] = EXP[i - 255] end
end
local function gmul(a, b)
    if a == 0 or b == 0 then return 0 end
    return EXP[LOG[a] + LOG[b]]
end

-- 生成多项式系数（最高次项系数 1 省略），长度 = 纠错码字数
local genCache = {}
local function generator(n)
    if genCache[n] then return genCache[n] end
    local g = {}
    for i = 1, n - 1 do g[i] = 0 end
    g[n] = 1
    local root = 1
    for _ = 1, n do
        for j = 1, n do
            g[j] = gmul(g[j], root)
            if j < n then g[j] = bxor(g[j], g[j + 1]) end
        end
        root = gmul(root, 2)
    end
    genCache[n] = g
    return g
end

local function rsRemainder(data, n)
    local g = generator(n)
    local r = {}
    for i = 1, n do r[i] = 0 end
    for _, b in ipairs(data) do
        local factor = bxor(b, r[1])
        table.remove(r, 1); r[n] = 0
        for i = 1, n do r[i] = bxor(r[i], gmul(g[i], factor)) end
    end
    return r
end

-- ---------- 版本表（1–13）：{每块纠错码字数, 组1块数, 组1每块数据码字, 组2块数, 组2每块数据码字} ----------
local ECC = {
    L = { {7,1,19,0,0}, {10,1,34,0,0}, {15,1,55,0,0}, {20,1,80,0,0}, {26,1,108,0,0}, {18,2,68,0,0}, {20,2,78,0,0},
          {24,2,97,0,0}, {30,2,116,0,0}, {18,2,68,2,69}, {20,4,81,0,0}, {24,2,92,2,93}, {26,4,107,0,0} },
    M = { {10,1,16,0,0}, {16,1,28,0,0}, {26,1,44,0,0}, {18,2,32,0,0}, {24,2,43,0,0}, {16,4,27,0,0}, {18,4,31,0,0},
          {22,2,38,2,39}, {22,3,36,2,37}, {26,4,43,1,44}, {30,1,50,4,51}, {22,6,36,2,37}, {22,8,37,1,38} },
}
local FORMAT_BITS = { L = 1, M = 0 }
local ALIGN = { {}, {6,18}, {6,22}, {6,26}, {6,30}, {6,34}, {6,22,38}, {6,24,42}, {6,26,46}, {6,28,50}, {6,30,54},
                {6,32,58}, {6,34,62} }
local REMAINDER = { 0, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, 0, 0 }
QR.MAX_VERSION = 13

local function dataCapacity(ver, ecl)
    local e = ECC[ecl][ver]
    return e[2] * e[3] + e[4] * e[5]
end

-- 字节模式能放下的最大字节数
function QR.ByteCapacity(ver, ecl)
    local countBits = ver <= 9 and 8 or 16
    return floor((dataCapacity(ver, ecl) * 8 - 4 - countBits) / 8)
end

-- ---------- 数据码字 ----------
local function buildCodewords(text, ver, ecl)
    local bits = {}
    local function put(v, n) for i = n - 1, 0, -1 do bits[#bits + 1] = getBit(v, i) and 1 or 0 end end
    put(4, 4)                                   -- 0100 = 字节模式
    put(#text, ver <= 9 and 8 or 16)
    for i = 1, #text do put(text:byte(i), 8) end
    local capBits = dataCapacity(ver, ecl) * 8
    for _ = 1, math.min(4, capBits - #bits) do bits[#bits + 1] = 0 end
    while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end
    local data = {}
    for i = 1, #bits, 8 do
        local v = 0
        for j = 0, 7 do v = v * 2 + bits[i + j] end
        data[#data + 1] = v
    end
    local pad = true
    while #data < capBits / 8 do data[#data + 1] = pad and 0xEC or 0x11; pad = not pad end
    -- 分块 + 纠错 + 交织
    local e = ECC[ecl][ver]
    local blocks, k = {}, 1
    for g = 0, 1 do
        local nb, nd = e[2 + g * 2], e[3 + g * 2]
        for _ = 1, nb do
            local b = {}
            for i = 1, nd do b[i] = data[k]; k = k + 1 end
            blocks[#blocks + 1] = { d = b, e = rsRemainder(b, e[1]) }
        end
    end
    local out = {}
    local maxD = math.max(e[3], e[5])
    for i = 1, maxD do
        for _, b in ipairs(blocks) do if b.d[i] then out[#out + 1] = b.d[i] end end
    end
    for i = 1, e[1] do
        for _, b in ipairs(blocks) do out[#out + 1] = b.e[i] end
    end
    return out
end

-- ---------- 矩阵 ----------
local function newGrid(size, v)
    local g = {}
    for y = 0, size - 1 do g[y] = {}; for x = 0, size - 1 do g[y][x] = v end end
    return g
end

local function drawFunctionPatterns(ver, size, mod, fn)
    local function set(x, y, dark) mod[y][x] = dark; fn[y][x] = true end
    for i = 0, size - 1 do set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0) end
    local function finder(cx, cy)
        for dy = -4, 4 do
            for dx = -4, 4 do
                local x, y = cx + dx, cy + dy
                if x >= 0 and x < size and y >= 0 and y < size then
                    local d = math.max(math.abs(dx), math.abs(dy))
                    set(x, y, d ~= 2 and d ~= 4)
                end
            end
        end
    end
    finder(3, 3); finder(size - 4, 3); finder(3, size - 4)
    local pos = ALIGN[ver]
    local n = #pos
    for i = 1, n do
        for j = 1, n do
            if not ((i == 1 and j == 1) or (i == 1 and j == n) or (i == n and j == 1)) then
                for dy = -2, 2 do
                    for dx = -2, 2 do
                        set(pos[i] + dx, pos[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
                    end
                end
            end
        end
    end
    -- 格式区先占位（真值在选完掩码后写）
    for i = 0, 8 do
        if not fn[8][i] then set(i, 8, false) end
        if not fn[i][8] then set(8, i, false) end
    end
    for i = 0, 7 do set(size - 1 - i, 8, false); set(8, size - 1 - i, false) end
    set(8, size - 8, true)                                         -- 暗模块
    if ver >= 7 then
        local rem = ver
        for _ = 1, 12 do
            rem = rem * 2
            if rem >= 4096 then rem = bxor(rem, 0x1F25) end
        end
        local bits = ver * 4096 + rem
        for i = 0, 17 do
            local b = getBit(bits, i)
            local a, c = size - 11 + i % 3, floor(i / 3)
            set(a, c, b); set(c, a, b)
        end
    end
end

local function drawFormat(size, mod, ecl, mask)
    local data = FORMAT_BITS[ecl] * 8 + mask
    local rem = data
    for _ = 1, 10 do
        rem = rem * 2
        if rem >= 1024 then rem = bxor(rem, 0x537) end
    end
    local bits = bxor(data * 1024 + rem, 0x5412)
    local function set(x, y, v) mod[y][x] = v end
    for i = 0, 5 do set(8, i, getBit(bits, i)) end
    set(8, 7, getBit(bits, 6)); set(8, 8, getBit(bits, 7)); set(7, 8, getBit(bits, 8))
    for i = 9, 14 do set(14 - i, 8, getBit(bits, i)) end
    for i = 0, 7 do set(size - 1 - i, 8, getBit(bits, i)) end
    for i = 8, 14 do set(8, size - 15 + i, getBit(bits, i)) end
    set(8, size - 8, true)
end

local function drawCodewords(size, mod, fn, cw, ver)
    local total = #cw * 8
    local i = 0
    local right = size - 1
    while right >= 1 do
        if right == 6 then right = 5 end
        for vert = 0, size - 1 do
            for j = 0, 1 do
                local x = right - j
                local upward = floor((right + 1) / 2) % 2 == 0
                local y = upward and (size - 1 - vert) or vert
                if not fn[y][x] and i < total then
                    mod[y][x] = getBit(cw[floor(i / 8) + 1], 7 - i % 8)
                    i = i + 1
                end
            end
        end
        right = right - 2
    end
end

local MASKS = {
    [0] = function(x, y) return (x + y) % 2 == 0 end,
    function(_, y) return y % 2 == 0 end,
    function(x) return x % 3 == 0 end,
    function(x, y) return (x + y) % 3 == 0 end,
    function(x, y) return (floor(x / 3) + floor(y / 2)) % 2 == 0 end,
    function(x, y) return x * y % 2 + x * y % 3 == 0 end,
    function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
    function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
}

local function applyMask(size, mod, fn, m)
    local f = MASKS[m]
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            if not fn[y][x] and f(x, y) then mod[y][x] = not mod[y][x] end
        end
    end
end

-- 掩码罚分（N1 连续同色 / N2 2×2 / N3 类定位图形 / N4 黑白比例）
local function penalty(size, mod)
    local p = 0
    local function line(get)
        local run, prev = 0, nil
        local seq = {}
        for i = 0, size - 1 do
            local v = get(i)
            seq[i] = v
            if v == prev then run = run + 1 else
                if run >= 5 then p = p + 3 + run - 5 end
                run, prev = 1, v
            end
        end
        if run >= 5 then p = p + 3 + run - 5 end
        -- N3：1011101 前或后接 4 个白（边界外视为白）
        local function at(i) if i < 0 or i >= size then return false end return seq[i] end
        for i = 0, size - 7 do
            if at(i) and not at(i + 1) and at(i + 2) and at(i + 3) and at(i + 4) and not at(i + 5) and at(i + 6) then
                local before = not at(i - 1) and not at(i - 2) and not at(i - 3) and not at(i - 4)
                local after = not at(i + 7) and not at(i + 8) and not at(i + 9) and not at(i + 10)
                if before then p = p + 40 end
                if after then p = p + 40 end
            end
        end
    end
    for y = 0, size - 1 do line(function(i) return mod[y][i] end) end
    for x = 0, size - 1 do line(function(i) return mod[i][x] end) end
    local dark = 0
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local v = mod[y][x]
            if v then dark = dark + 1 end
            if x < size - 1 and y < size - 1 and v == mod[y][x + 1] and v == mod[y + 1][x] and v == mod[y + 1][x + 1] then
                p = p + 3
            end
        end
    end
    local total = size * size
    local k = math.ceil(math.abs(dark * 20 - total * 10) / total) - 1
    if k > 0 then p = p + k * 10 end
    return p
end

local function copyGrid(size, g)
    local c = {}
    for y = 0, size - 1 do c[y] = {}; for x = 0, size - 1 do c[y][x] = g[y][x] end end
    return c
end

-- text：字节串（UTF-8 原样）；ecl："L"/"M"（默认 M）；opts.minVer / maxVer / mask（测试对拍用）
function QR.Encode(text, ecl, opts)
    ecl = (ecl == "L") and "L" or "M"
    opts = opts or {}
    local ver
    for v = opts.minVer or 1, math.min(opts.maxVer or QR.MAX_VERSION, QR.MAX_VERSION) do
        if #text <= QR.ByteCapacity(v, ecl) then ver = v; break end
    end
    if not ver then return nil end
    local size = 17 + 4 * ver
    local mod, fn = newGrid(size, false), newGrid(size, false)
    drawFunctionPatterns(ver, size, mod, fn)
    drawCodewords(size, mod, fn, buildCodewords(text, ver, ecl), ver)
    local best, bestMask, bestP
    local masks = opts.mask and { opts.mask } or { 0, 1, 2, 3, 4, 5, 6, 7 }
    for _, m in ipairs(masks) do
        local g = copyGrid(size, mod)
        applyMask(size, g, fn, m)
        drawFormat(size, g, ecl, m)
        local p = opts.mask and 0 or penalty(size, g)
        if not bestP or p < bestP then best, bestMask, bestP = g, m, p end
    end
    -- 转成 1 起的 [row][col]
    local out = {}
    for y = 0, size - 1 do
        local r = {}
        for x = 0, size - 1 do r[x + 1] = best[y][x] end
        out[y + 1] = r
    end
    return out, ver, bestMask, size
end

-- ---------- 渲染窗口 ----------
local qf
local function makeFrame()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        f:SetBackdropColor(1, 1, 1, 1)
        f:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    end
    f:SetPoint("CENTER")
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); cb:SetPoint("TOPRIGHT", -2, -2)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.title:SetPoint("TOP", 0, -18)
    f.title:SetTextColor(0.1, 0.1, 0.1)
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f.foot:SetPoint("BOTTOM", 0, 14)
    f.foot:SetTextColor(0.3, 0.3, 0.3); f.foot:SetJustifyH("CENTER")
    f.cells = {}
    if UISpecialFrames then table.insert(UISpecialFrames, FRAME_NAME) end   -- ESC 关
    return f
end

-- 返回 true / false（放不下）
function ns.ShowQR(title, foot, text, ecl)
    local m, ver = QR.Encode(text, ecl or "M")
    if not m then
        ns.Print(ns.L("内容太长，二维码放不下", "Too much data for a QR code"))
        return false
    end
    qf = qf or makeFrame()
    local n = #m
    local px = (n <= 41) and 6 or (n <= 57 and 5 or 4)          -- 版本越大格子越小，整图控制在 ~280px 内
    local pad, quiet = 18, 4 * px                                -- quiet = 4 格静区（白底边框）
    local size = n * px
    qf:SetSize(size + 2 * (pad + quiet), size + 2 * (pad + quiet) + 54)
    qf.title:SetText(title or "")
    qf.foot:SetText(foot or "")
    for _, t in ipairs(qf.cells) do t:Hide() end
    local k = 0
    local x0, y0 = pad + quiet, -(pad + 30 + quiet)
    for r = 1, n do
        local c = 1
        while c <= n do
            if m[r][c] then
                local c2 = c
                while c2 < n and m[r][c2 + 1] do c2 = c2 + 1 end
                k = k + 1
                local t = qf.cells[k]
                if not t then t = qf:CreateTexture(nil, "ARTWORK"); t:SetColorTexture(0, 0, 0, 1); qf.cells[k] = t end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", qf, "TOPLEFT", x0 + (c - 1) * px, y0 - (r - 1) * px)
                t:SetSize((c2 - c + 1) * px, px)
                t:Show()
                c = c2 + 1
            else
                c = c + 1
            end
        end
    end
    qf:Show()
    return true, ver
end
