-- =============================================================================
-- DungeonsForever · 商人直售价动态采集库
-- 打开商人窗口时自动记录货架售价，供升级路线取商人价兜底。
-- =============================================================================

local _, ns = ...

local VDB = {}
ns.VendorPriceDB = VDB

-- ── 存储层 ──────────────────────────────────────────────────────────────────

local function Table()
    local db = ns.DB()
    if type(db.vendorPrices) ~= "table" then
        db.vendorPrices = {}
    end
    return db.vendorPrices
end

-- ── 扫描：把当前商人货架的「用钱直售」条目折算单件价入库 ──────────────────────

local function Scan()
    if not GetMerchantNumItems or not GetMerchantItemInfo then return 0 end
    local num = GetMerchantNumItems()
    if type(num) ~= "number" or num <= 0 then return 0 end

    local tab = Table()
    local now = time()
    local fresh = 0
    for i = 1, num do
        local ok, name, _, price, quantity, _, _, _, currencyID =
            pcall(GetMerchantItemInfo, i)
        if ok and price and price > 0 and not (currencyID and currencyID > 0) then
            local link = GetMerchantItemLink and GetMerchantItemLink(i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                local q = tonumber(quantity) or 1
                if q < 1 then q = 1 end
                local unit = math.floor(price / q + 0.5)   -- 单件价（铜）
                local old = tab[id]
                if not old then
                    tab[id] = { p = unit, t = now }
                    fresh = fresh + 1
                elseif old.p ~= unit then                    -- 价格变了才回写，减少 SV 脏写
                    old.p = unit
                    old.t = now
                end
            end
        end
    end
    return fresh
end

-- ── 事件挂接：MERCHANT_SHOW 打开商人 / MERCHANT_UPDATE 货架刷新（翻页、补货）──

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("MERCHANT_SHOW")
    f:RegisterEvent("MERCHANT_UPDATE")
    f:SetScript("OnEvent", function(_, event)
        C_Timer.After(0, function()
        -- 扫描是纯读 API + 表写入，代价可忽略；MERCHANT_UPDATE 会重复触发，
        -- Scan 内部「价同不写」保证幂等。
        pcall(Scan)
        end)
    end)
end

-- ── 对外 API ────────────────────────────────────────────────────────────────

function VDB.GetPrice(itemID)
    if type(itemID) ~= "number" then return nil end
    -- ① 动态采集库（开过商人窗口的记录，最实时）
    local rec = Table()[itemID]
    if type(rec) == "table" and type(rec.p) == "number" and rec.p > 0 then
        return rec.p
    end
    -- ② 静态种子表（内置数据，装上插件即有价）
    local s = rawget(ns, "VendorPriceSeed")
    if type(s) == "table" then
        local p = s[itemID]
        if type(p) == "number" and p > 0 then return p end
    end
    return nil
end

function VDB.Count()
    local n = 0
    for _ in pairs(Table()) do n = n + 1 end
    return n
end

function VDB.Scan()
    return Scan()
end
