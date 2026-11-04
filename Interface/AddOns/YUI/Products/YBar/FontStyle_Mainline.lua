local YUI = _G.YUI
local YBar = YUI and YUI.YBar
local Style = YUI and YUI.GUI2 and YUI.GUI2.FontStyle
if not (YBar and Style and (YUI.IsRetail or YUI.IsForever)) then return end
local M = YBar.LayoutLibraries.Model
local L = YUI.Locale:Get("YBar")
-- Registration is metadata only. It never requests a module root or instance.
function YBar:RegisterFontStyles(bridge)
    Style:Register("ybar", function()
        local profile = YBar:GetProfile()
        local expectedRoot = profile and profile.YBar
        local session = bridge.session or bridge.settingsSession
        local model = session and session:GetModel() or bridge.active and bridge:GetModel() or expectedRoot
        if not (model and model.version == 2 and model.instances) then return nil end
        local group = { targets = {}, label = L["ybar.title"] }
        local function CurrentSession() return bridge.session or bridge.settingsSession end
        group.current = function()
            return YBar:GetProfile() == profile and profile.YBar == expectedRoot and CurrentSession() == session
                and (not session or session:IsCurrent() and session.state == "editing")
                and not bridge:InCombat()
        end
        local function Model() return session and session:GetModel() or bridge.active and bridge:GetModel() or profile.YBar end
        local function Path(value)
            local media = LibStub and LibStub("LibSharedMedia-3.0", true)
            local fonts = media and media:HashTable("font") or {}
            value = fonts[value] or value or STANDARD_TEXT_FONT
            return YBar.ResolveFontPath and YBar:ResolveFontPath(value, STANDARD_TEXT_FONT) or value
        end
        local targets = {}
        local function Raw(db, id)
            local target = targets[id]
            if not target then return nil end
            if target.scope == "global" then return db.defaults end
            if target.scope == "bar" then return db.bars[target.id] and db.bars[target.id].appearance end
            return db.instances[target.id] and db.instances[target.id].appearance
        end
        local function Resolve(db, id, key)
            local target = targets[id]
            if target.scope == "instance" then return M.Resolve(db, target.id, key) end
            local raw = Raw(db, id)
            if raw[key] ~= nil then return raw[key], target.scope end
            return db.defaults[key], "global"
        end
        local function Read(id)
            local db = Model()
            local legacy = db.legacyRemainder or {}
            local outline, shadow = Resolve(db, id, "outline"), Resolve(db, id, "shadow")
            if outline == nil then outline = legacy.fontOutline and "OUTLINE" or "NONE" end
            if shadow == nil then shadow = legacy.fontShadow == true end
            local effect = Style.Decode(outline, shadow, Resolve(db, id, "monochrome"))
            effect.font = Path(Resolve(db, id, "font"))
            effect.size = Resolve(db, id, "size") or 14
            local mode = Resolve(db, id, "colorMode")
            if mode == "custom" then effect.color = M.Copy(Resolve(db, id, "color") or {1,1,1,1}) end
            if mode == "class" then effect.color = { mode = "class", alpha = Resolve(db, id, "colorAlpha") or 1 } end
            return effect
        end
        local function Default(key, db)
            if key == "font" then return STANDARD_TEXT_FONT end
            if key == "size" then return 14 end
            if key == "monochrome" then return false end
            local legacy = db.legacyRemainder or {}
            if key == "outline" then return legacy.fontOutline and "OUTLINE" or "NONE" end
            if key == "shadow" then return legacy.fontShadow == true end
        end
        local function ColorInfo(id, requestedMode)
            local db = Model()
            local mode, owner = Resolve(db, id, "colorMode")
            mode = requestedMode or mode or "state"
            local info = { mode = mode, inherited = owner ~= targets[id].scope }
            if mode == "custom" then info.color = M.Copy(Resolve(db, id, "color") or {1,1,1,1})
            elseif mode == "class" then
                info.color = { YUI.GUI2:GetColor("color.class.primary") }
                info.color[4] = Resolve(db, id, "colorAlpha") or 1
            elseif targets[id].moduleType == "Clock" then
                -- Clock:ApplyTextColors uses white for normal hour/minute digits.
                -- This display sample does not replace separator/combat rules or
                -- become a fixed-color copy payload in Read().
                info.color = {1,1,1,1}
            elseif targets[id].scope == "instance" then
                local view = bridge.runtime and bridge.runtime.views[id]
                if view and view.appearance then info.color = view.appearance:ModuleColor() end
            end
            return info
        end
        group.snapshot = function(id)
            local raw = Raw(Model(), id)
            return raw and M.Copy(raw)
        end
        local function Command(command)
            if not group.current() then return false, "stale" end
            local ok, reason
            if session then
                local ran, result, detail = pcall(session.Apply, session, command)
                expectedRoot = profile.YBar
                ok, reason = ran and result, ran and detail or "failed"
            else
                local candidate = M.Copy(Model())
                command(candidate)
                ok, reason = M.Validate(candidate)
                if ok then
                    profile.YBar = candidate
                    expectedRoot = candidate
                    if bridge.active then bridge.committed = candidate; bridge.revision = bridge.revision + 1; bridge:Changed() end
                end
            end
            if ok then expectedRoot = profile.YBar end
            return ok, reason
        end
        group.apply = function(changes)
            for id in pairs(changes) do
                if not Raw(Model(), id) then return false, "stale" end
            end
            return Command(function(db)
                for id, patch in pairs(changes) do
                    local appearance = Raw(db, id)
                    for key, value in pairs(patch.values) do
                        if key == "color" then
                            appearance.colorMode = value.mode or "custom"
                            appearance.colorAlpha = value.mode == "class" and value.alpha or nil
                            if appearance.colorMode == "custom" then appearance.color = {value[1],value[2],value[3],value[4]} end
                        else appearance[key] = M.Copy(value) end
                    end
                    for key in pairs(patch.reset or {}) do
                        local global = targets[id].scope == "global"
                        if global then appearance[key] = Default(key, db) else appearance[key] = nil end
                        if key == "color" then appearance.colorMode, appearance.colorAlpha = global and "state" or nil, nil end
                    end
                end
            end)
        end
        group.restore = function(snapshots, attributes)
            for id in pairs(snapshots) do if not Raw(Model(), id) then return false, "stale" end end
            return Command(function(db)
                for id, appearance in pairs(snapshots) do
                    if attributes then
                        local current = Raw(db, id)
                        for key in pairs(attributes) do
                            current[key] = M.Copy(appearance[key])
                            if key == "color" then current.colorMode, current.colorAlpha = appearance.colorMode, appearance.colorAlpha end
                        end
                    else
                        local current = Raw(db, id)
                        for key in pairs(current) do current[key] = nil end
                        for key, value in pairs(appearance) do current[key] = M.Copy(value) end
                    end
                end
            end)
        end
        local function Add(id, scope, rawId, label, moduleType)
            targets[id] = {scope=scope, id=rawId, moduleType=moduleType}
            group.targets[#group.targets + 1] = {
                id = id, label = label,
                capabilities = { font = true, size = true, outline = true, shadow = true, monochrome = true, color = true },
                colorModes = { custom = true, class = true, state = true },
                minSize = 8, maxSize = 40, read = function() return Read(id) end,
                colorInfo = function(mode) return ColorInfo(id, mode) end,
                parent = function(key)
                    local db = Model()
                    local parentBar = scope == "instance" and M.FindBar(db, rawId)
                    local function Parent(attr)
                        local result = parentBar and parentBar.appearance[attr]
                        if result == nil and scope ~= "global" then result = db.defaults[attr] end
                        return result
                    end
                    local value = Parent(key)
                    local legacy = db.legacyRemainder or {}
                    if key == "font" then return Path(value)
                    elseif key == "size" then return value or 14
                    elseif key == "outline" then return value or (legacy.fontOutline and "OUTLINE" or "NONE")
                    elseif key == "shadow" then if value == nil then return legacy.fontShadow == true end; return value
                    elseif key == "monochrome" then return value == true
                    elseif key == "color" then
                        local mode = Parent("colorMode") or "state"
                        if mode == "class" then return {mode="class",alpha=Parent("colorAlpha") or 1} end
                        return mode == "custom" and M.Copy(value or {1,1,1,1}) or {mode="state"}
                    end
                end,
            }
        end
        Add("@global", "global", nil, L["designer.global_settings"])
        local function BarTitle(id)
            local bar = id and model.bars[id]
            local name = bar and bar.name
            if name and name ~= "" and name ~= id then return name end
            return L["designer." .. ((id == "top" or id == "bottom") and id or bar and "independent" or "unplaced")]
        end
        for _, id in ipairs(model.barOrder) do Add("@bar:"..id, "bar", id, BarTitle(id)) end
        local indices = {}
        local titleClass, titleContext = YBar.LayoutLibraries.Designer, {L=L}
        for _, id in ipairs(model.instanceOrder) do
            local instance = model.instances[id]
            local cap = instance and bridge.adapters and bridge.adapters[instance.moduleType]
            if instance and cap and cap.appearance and cap.appearance.font then
                local kind = instance.moduleType
                indices[kind] = (indices[kind] or 0) + 1
                local _, barId = M.FindBar(model, id)
                local title = bridge.designer and bridge.designer:ModuleTitle(kind)
                    or titleClass and titleClass.ModuleTitle(titleContext, kind) or kind
                if cap.multi then title = title .. " " .. indices[kind] end
                Add(id, "instance", id, tostring(BarTitle(barId)) .. " · " .. title, kind)
            end
        end
        return group
    end)
end
