local YUI = _G.YUI
local YBar = YUI.YBar
local System = YUI.API.System
local Logging = {}
Logging.__index = Logging
YBar.RaidMarkerLogging = Logging

local MODERN_RAIDS = { [14]="raid_normal", [15]="raid_heroic", [16]="raid_mythic", [233]="raid_mythic", [7]="raid_lfr", [17]="raid_lfr" }
local MODERN_DUNGEONS = { [1]="dungeon_normal", [2]="dungeon_heroic", [23]="dungeon_mythic", [8]="mythic_plus" }
local AUTO_EVENTS = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED", "CHALLENGE_MODE_START" }
local RETAIL_SCENES = {"raid_lfr", "raid_normal", "raid_heroic", "raid_mythic", "raid_other", "dungeon_normal", "dungeon_heroic", "dungeon_mythic", "mythic_plus", "arena", "battleground", "scenario"}
local FOREVER_SCENES = {"raid", "dungeon", "arena", "battleground", "scenario"}

function Logging.GetSceneKeys()
    return YUI.IsForever and FOREVER_SCENES or RETAIL_SCENES
end

function Logging.New(changed, failed)
    return setmetatable({ changed=changed, failed=failed }, Logging)
end

function Logging:GetRule(kind, difficulty)
    if YUI.IsForever then
        if kind == "raid" or difficulty == 198 then return "raid" end
        if kind == "party" then return "dungeon" end
    elseif YUI.IsRetail then
        if kind == "raid" then return MODERN_RAIDS[difficulty] or "raid_other" end
        if kind == "party" then return MODERN_DUNGEONS[difficulty] end
    end
    if kind == "arena" or kind == "ratedarena" then return "arena" end
    if kind == "pvp" then return "battleground" end
    if kind == "scenario" then return "scenario" end
end

function Logging:ReadState(external)
    local enabled, advanced = System.GetCombatLoggingState()
    if enabled == nil then return nil end
    local different = self.enabled ~= enabled
    if external and different and not self.changing then
        self.owned = false
        if self.db and self.db.autoLogEnabled then self.manual = enabled end
    end
    local changed = different or self.advanced ~= advanced
    self.enabled, self.advanced = enabled, advanced
    if changed and self.changed then self.changed() end
    return enabled
end

function Logging:SetRecording(enabled)
    self.changing = true
    local ok = System.SetCombatLoggingState(enabled)
    self:ReadState(false)
    self.changing = false
    if not ok and self.failed then self.failed() end
    return ok
end

function Logging:Release()
    if self.owned then
        -- The event listener stays active during this operation so UI follows reality.
        local ok = self:SetRecording(false)
        if not ok then return false end
    end
    self.owned = false
    return true
end

function Logging:Evaluate()
    if not self.active then return end
    local current = self:ReadState(true)
    -- Turning automation off must release its recording even while zone metadata is unavailable.
    if not self.db.autoLogEnabled then self:Release() end
    local kind, difficulty, mapID, name = System.GetCombatLogContext()
    if not kind then return end -- Loading screen metadata is incomplete; wait for the next event.
    local key = kind .. ":" .. difficulty .. ":" .. tostring(mapID)
    if key ~= self.context then
        self.manual = nil
        self.context = key
    end
    self.rule, self.instanceName = self:GetRule(kind, difficulty), name
    self.matches = self.rule ~= nil and self.db.autoLogScenes[self.rule] == true
    if current ~= nil and self.db.autoLogEnabled then
        if self.matches and self.manual == nil then
            if not current and self:SetRecording(true) then self.owned = true end
        elseif not self.matches then
            self:Release()
        end
    end
    if self.changed then self.changed() end
end

function Logging:OnEvent(event)
    if not self.active then return end
    if event == "CHAT_LOGGING_CHANGED" then
        self:ReadState(true)
    elseif event == "CVAR_UPDATE" then
        self:ReadState(true)
    else
        if self.timer then self.timer:Cancel() end
        self.timer = C_Timer.NewTimer(event == "CHALLENGE_MODE_START" and 1 or 2, function()
            self.timer = nil
            if self.active then self:Evaluate() end
        end)
    end
end

function Logging:Start(db)
    if self.active and self.db ~= db then self:Stop() end
    local first = not self.active
    self.db, self.active = db, true
    if self.timer then self.timer:Cancel(); self.timer = nil end
    YUI.Event:OffOwner(self)
    if YUI.IsRetail or YUI.IsForever then
        YUI.Event:On("CHAT_LOGGING_CHANGED", "OnEvent", self)
        YUI.Event:On("CVAR_UPDATE", "OnEvent", self)
        if db.autoLogEnabled then
            for _, event in ipairs(AUTO_EVENTS) do YUI.Event:On(event, "OnEvent", self) end
        end
    end
    if first then self:ReadState(false) end
    self:Evaluate()
end

function Logging:Stop()
    if self.timer then self.timer:Cancel(); self.timer = nil end
    self:Release()
    self.owned = false
    self.active = false
    self.manual, self.context = nil, nil
    YUI.Event:OffOwner(self)
end

function Logging:ToggleManual()
    local current = self:ReadState(true)
    if current == nil then if self.failed then self.failed() end; return end
    if self:SetRecording(not current) then
        self.manual, self.owned = not current, false
        if self.changed then self.changed() end
    end
end

function Logging:SetAutomatic(enabled)
    if not (YUI.IsRetail or YUI.IsForever) then return false end
    self.db.autoLogEnabled = enabled == true
    self.manual = nil
    if self.active then self:Start(self.db) end
    return true
end
