-- 按需加载子插件的「占位」底座（11-13 重构第 4 期，docs/forever-ui-refactor-design.md 第 4.4 节）
-- 第 3 期 PlanStub.lua 给升级 / 装备子插件写的那一套（占位页 / 外壳函数 / ns.Data 大字段懒加载 / 没装时说一次），
--   这里抽成通用的，给第 4 期的三个子插件用：
--     GearInsight_Forever_Prof   专业（ProfStub.lua 登记入口）
--     GearInsight_Forever_Class  职业：天赋 / 键位 / 手法 / 宏 / 宠物 / 弹药（ClassStub.lua）—— 含安全按钮，⛔ 战斗中不加载
--     GearInsight_Forever_Info   资讯：资讯 / 共建 / 进阶 / 报告 / 攻略（InfoStub.lua）
--   用户「功能不能少」：子插件没加载时，页签 / 命令 / 小地图菜单 / 设置项 / 「窗口与提醒」里的入口照常显示，点了再加载。
--
-- 用法：local M = ns.LazyModule({ key = "prof", addon = "GearInsight_Forever_Prof", zh = "专业", en = "Professions", noCombat = false })
--   M:Page({ key, order, title, tabTitle, icon, class, file })   占位页（和真页登记的页名 / 顺序 / 图标一模一样）
--   M:Shell(name, { file =, defer = true })                       ns[name] 外壳：调用时加载再转给真函数（defer = 战斗中排到脱战后再调）
--   M:Slash({ "cmd", … }, file)                                    ns.ExtraSlash 占位：先加载，再把原参数转给真处理函数
--   M:Table(name, file)                                            ns[name] 占位表：读字段时加载（只认 t.x / t[k] 这种读法）
--   M:DataKeys({ "talents", … })                                   ns.Data 上这些字段没加载时一读就加载（PlanStub.lua 的元表转过来）
--   M:Window(w)                                                    「窗口与提醒」占位（真模块用同一个 key 登记会顶替）
--   M:Has(file)                                                    这个文件在不在发出去的包里（ModManifest.lua；HOLD 的文件发版时不进包）
--
-- 合并打包（发版脚本默认，回滚开关）：子插件的文件排在主插件 toc 末尾、没有子插件文件夹 →
--   这里查不到子插件 = 不放任何占位（真页 / 真命令照旧自己登记），子插件最后一个文件 *Init.lua 把就绪标记置上。
local _, ns = ...

ns._modReady = ns._modReady or {}
ns._ModFiles = ns._ModFiles or {}
local SPECS = {}
ns._LazySpecs = SPECS   -- 测试用

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function addonThere(name)
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not f then return false end
    local ok, n, _, _, _, reason = pcall(f, name)
    return ok and n ~= nil and reason ~= "MISSING"
end

-- 这个子插件的这个文件在不在包里（HOLD 的不在）。合并打包时同样按 ModManifest.lua 认（发版脚本按实际进包的文件重写那份清单）
function ns.ModHas(key, file)
    local m = ns._ModFiles[key]
    if not (m and m[file]) then return false end
    return ns._modReady[key] == true or (ns.ModuleAvailable ~= nil and ns.ModuleAvailable(key))
end

function ns.ModReady(key) return ns._modReady[key] == true end

-- ---------- 战斗中排队（只给 noCombat 的模块用）----------
local pending, said = {}, {}
local regen = CreateFrame("Frame")
ns._ModRegen = regen   -- 测试用
regen:SetScript("OnEvent", function(self)
    if inCombat() then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local todo = pending
    pending, said = {}, {}
    for key, list in pairs(todo) do
        if ns.ModLoad(key) then
            for _, fn in ipairs(list) do pcall(fn) end
        end
    end
end)

local failed = {}
function ns._ModResetFailed(key) failed[key] = nil end   -- 测试用

-- 加载子插件 → true = 已经在了 / 刚加载上。没装 / 加载失败 / 战斗中（noCombat）→ false
--   after：战斗中时脱战后加载完再调它（同一场战斗里只提示一次「脱战后自动打开」）；quiet：战斗中也不提示
function ns.ModLoad(key, after, quiet)
    if ns._modReady[key] then return true end
    local s = SPECS[key]
    if not s or failed[key] or not (ns.ModuleAvailable and ns.ModuleAvailable(key)) then return false end
    if s.noCombat and inCombat() then
        if after then
            local q = pending[key]
            if not q then q = {}; pending[key] = q end
            q[#q + 1] = after
            regen:RegisterEvent("PLAYER_REGEN_ENABLED")
            if not quiet and not said[key] then
                said[key] = true
                ns.Print(string.format(ns.L("战斗中不加载%s模块（里面有动作条 / 键位相关的安全按钮），脱战后自动打开", "The %s module can't load in combat (it has secure action buttons) - it will open after combat"),
                    ns.L(s.zh, s.en)))
            end
        end
        return false
    end
    -- 先把这个模块的占位（外壳函数 / 占位表 / 斜杠命令占位）摘掉，让模块里的文件照原样登记
    --   （有的文件写的是「没人登记过才登记」，比如 /gi bug；HOLD 没进包的就保持没有，和拆分前一样）
    local saved = {}
    local function take(t, k, v) if t and rawget(t, k) == v then t[k] = nil; saved[#saved + 1] = { t, k, v } end end
    for n, st in pairs(s.shells) do take(ns, n, st) end
    for n, px in pairs(s.tables) do take(ns, n, px) end
    for c, st in pairs(s.slashes) do take(ns.ExtraSlash, c, st) end
    local ok, loaded = pcall(ns.LoadModule, key)
    if not (ok and loaded) then
        for _, x in ipairs(saved) do if rawget(x[1], x[2]) == nil then x[1][x[2]] = x[3] end end   -- 加载失败：占位放回去（之后再点只会安静地返回空）
        failed[key] = true
        return false
    end
    -- 模块加载上了，但某张占位页它没给（这一页的文件在 HOLD 里没进包）：把占位页撤掉，别留一张点了没东西的页签
    for _, p in ipairs(s.pages) do
        if p.lazy == key and ns._Pages then
            for i, q in ipairs(ns._Pages) do if q == p then table.remove(ns._Pages, i); break end end
        end
    end
    return true
end

-- ---------- 定义一个按需加载的子插件 ----------
local Mod = {}
Mod.__index = Mod

function ns.LazyModule(spec)
    local s = setmetatable(spec, Mod)
    s.pages, s.shells, s.tables, s.slashes = {}, {}, {}, {}
    SPECS[s.key] = s
    -- 借用 UI.lua 的 ns.LoadModule / ModuleAvailable / ModuleLoaded（和公会 / 组队 / 升级装备子插件同一套）
    if ns._Modules then
        ns._Modules[s.key] = { addon = s.addon, zh = s.zh, en = s.en,
            ready = function() return ns._modReady[s.key] == true end,
            attach = function() end }
    end
    s.installed = addonThere(s.addon)
    if not s.installed then
        -- 既没有子插件文件夹、合并包里的文件也没跟上（只装了主插件）：登录后说一次
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_LOGIN")
        ev:SetScript("OnEvent", function()
            if ns._modReady[s.key] then return end
            local function say()
                if ns._modReady[s.key] then return end
                ns.Print(string.format(ns.L("安装不完整：缺少 %s 文件夹，%s暂时用不了。请重新安装（把压缩包里的文件夹全部放进 AddOns）。",
                    "Incomplete install: the %s folder is missing, so %s is unavailable. Please reinstall (copy every folder from the zip into AddOns)."),
                    s.addon, ns.L(s.what or s.zh, s.whatEn or s.en)))
            end
            if C_Timer and C_Timer.After then C_Timer.After(8, say) else say() end
        end)
        s._missingNotice = ev:GetScript("OnEvent")   -- 测试用
    end
    return s
end

function Mod:Load(after, quiet) return ns.ModLoad(self.key, after, quiet) end
function Mod:Has(file) return ns.ModHas(self.key, file) end
-- 占位只在「子插件文件夹在、这个文件进了包」时放
function Mod:Active(file) return self.installed and (file == nil or self:Has(file)) end

-- 占位页：第一次点开 → 加载 → 真页就地顶替（UI.lua 的 ns.RegisterPage 认 lazy 字段）
function Mod:Page(def)
    if not (self:Active(def.file) and ns.RegisterPage) then return nil end
    local p, key, M = {}, self.key, self
    for k, v in pairs(def) do if k ~= "file" then p[k] = v end end
    p.lazy = key
    local mine
    mine = function(f)
        if M:Load(function()
            -- 战斗中点开的：脱战后加载完，把这页的占位框扔掉、按真页重画（主窗口还开着这一页的话）
            if p.frame then p.frame:Hide(); p.frame = nil end
            if ns.CurrentPage and ns.CurrentPage() == p.key and ns.ShowPage then ns.ShowPage(p.key) end
        end) and p.build and p.build ~= mine then
            return p.build(f)
        end
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", 0, 20)
        fs:SetWidth(520)
        if M.noCombat and inCombat() and ns.ModuleAvailable(key) then
            fs:SetText(ns.L("战斗中不加载这一页（里面有动作条 / 键位相关的安全按钮）。\n脱战后会自动打开。",
                "This page can't load in combat (it has secure action buttons).\nIt will open after combat."))
        else
            fs:SetText(string.format(ns.L("这一页在「%s」文件夹里，没能加载上。\n请重新安装插件（解压时把压缩包里的文件夹全部放进 AddOns），或在插件列表里把它勾上。",
                "This page lives in the %s folder, which couldn't be loaded.\nReinstall the addon (copy every folder from the zip into AddOns) or enable it in your AddOns list."), M.addon, M.addon))
        end
    end
    p.build = mine
    self.pages[#self.pages + 1] = p
    ns.RegisterPage(p)
    return p
end

-- ns[name] 外壳：真函数加载后会把 ns[name] 盖掉；这里调用时再读一次 ns[name]，读到的还是自己 = 没加载上 → 返回 nil
--   opts.defer：战斗中（noCombat 模块）把这次调用排到脱战后（打开窗口这类动作）；不 defer 的战斗中直接返回 nil（调用方按「没有」处理）
function Mod:Shell(name, opts)
    opts = opts or {}
    if not self:Active(opts.file) or rawget(ns, name) ~= nil then return end
    local M = self
    local stub
    stub = function(...)
        local args, n = { ... }, select("#", ...)
        local after = opts.defer and function()
            local f = ns[name]
            if f and f ~= stub then f(unpack(args, 1, n)) end
        end or nil
        if not M:Load(after, not opts.defer) then return nil end
        local f = ns[name]
        if f and f ~= stub then return f(...) end
        return nil
    end
    ns[name] = stub
    self.shells[name] = stub
    return stub
end

-- 斜杠命令占位：先加载模块，再把原参数转给真处理函数（和 UI.lua 给公会 / 组队做的一样）。战斗中（noCombat）脱战后再执行
--   force：内核里排在前面的文件也登记了同名命令、拆分前是子插件里的文件后加载把它顶掉的（/gi report：公会通报 → 升级报告）→ 照样占位顶掉
function Mod:Slash(cmds, file, force)
    if not self:Active(file) then return end
    ns.ExtraSlash = ns.ExtraSlash or {}
    local M = self
    for _, c in ipairs(cmds) do
        if force or rawget(ns.ExtraSlash, c) == nil then
            local stub
            stub = function(rest, rawRest)
                local function go()
                    local f = ns.ExtraSlash[c]
                    if f and f ~= stub then return f(rest, rawRest) end
                end
                if not M:Load(go) then return end
                return go()
            end
            ns.ExtraSlash[c] = stub
            self.slashes[c] = stub
        end
    end
end

-- 占位表：ns[name].x 读字段时加载，返回真表里的字段（真表加载后 ns[name] 换成真表，以后不再经过这里）
--   ⛔ 只认 t.x / t[k] 这种读法；pairs / ipairs / # 不会触发加载 —— 用到这些读法的地方要先 M:Load()
function Mod:Table(name, file)
    if not self:Active(file) or rawget(ns, name) ~= nil then return end
    local M = self
    local proxy = {}
    setmetatable(proxy, { __index = function(_, k)
        M:Load(nil, true)
        local real = rawget(ns, name)
        if real ~= nil and real ~= proxy then return real[k] end
        return nil
    end })
    ns[name] = proxy
    self.tables[name] = proxy
    return proxy
end

-- ns.Data 上的字段：没加载时一读就加载（PlanStub.lua 的元表转过来调 ns._DataLazy[k]）
function Mod:DataKeys(keys)
    if not self.installed then return end
    ns._DataLazy = ns._DataLazy or {}
    local M = self
    for _, k in ipairs(keys) do
        ns._DataLazy[k] = function(t)
            M:Load(nil, true)
            return rawget(t, k)
        end
    end
end

function Mod:Window(w, file)
    if not (self:Active(file) and ns.RegisterWindow) then return end
    ns.RegisterWindow(w)
end
