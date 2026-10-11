local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.rankUpgrade == true) then return end

local Upgrade = { active = false, pending = false, passes = 0, replacements = 0 }
YAB.RankUpgrade = Upgrade

local function Enabled()
    local db = YAB:GetDB()
    return db and db.enabled == true and db.interaction.autoRankUpgrade ~= false
        and YAB.BarManager and YAB.BarManager.runtimeActive == true
end

local function BuildFamilies(entries)
    local lines, families, bySpell = {}, {}, {}
    for _, entry in ipairs(entries) do
        local line = lines[entry.skillLineIndex]
        if not line then line = {}; lines[entry.skillLineIndex] = line end
        local family = line[entry.name]
        if not family then
            family = { entries = {} }
            line[entry.name] = family
            families[#families + 1] = family
        end
        family.entries[#family.entries + 1] = entry
        if bySpell[entry.spellID] then
            family.invalid = true
            bySpell[entry.spellID].family.invalid = true
        end
        entry.family = family
        bySpell[entry.spellID] = entry
        if entry.lowRank then
            family.hasLowRank = true
        elseif entry.rank then
            if family.highest then family.invalid = true end
            family.highest = entry
        end
    end
    for _, family in ipairs(families) do
        local highest = family.highest
        if family.hasLowRank and not highest and not family.invalid then return nil, "not-ready" end
        for _, entry in ipairs(family.entries) do
            if not entry.rank or (entry ~= highest and (not entry.lowRank
                or not highest or entry.rank >= highest.rank)) then family.invalid = true end
        end
    end
    return families, bySpell
end

local function PrintReplacements(reports)
    if #reports == 0 then return end
    local locale = YUI.Locale:Get("YActionBar")
    local details = {}
    for _, report in ipairs(reports) do
        details[#details + 1] = string.format(locale["rank_upgrade.detail"],
            report.name, report.oldRank, report.newRank)
    end
    YUI:Print(string.format(locale["rank_upgrade.success"], table.concat(details, locale["rank_upgrade.separator"])))
end

function Upgrade:RunPass()
    local entries, reason = YUI.API.Spell.ReadRankedPlayerSpellBook()
    if not entries then return false, reason end
    local families, bySpell = BuildFamilies(entries)
    if not families then return false, bySpell end
    local action = YUI.API.ActionBar
    local slots, counts = action:ReadPlayerSpellSlots()
    if not slots then return false, counts end
    self.passes = self.passes + 1
    -- Ascending slots break ties. Each family keeps only its highest placed rank.
    for _, record in ipairs(slots) do
        local entry = bySpell[record.spellID]
        local family = entry and entry.family
        if family and not family.invalid and family.highest and entry.lowRank
            and not counts[family.highest.spellID] then
            if not family.candidate or entry.rank > family.candidate.entry.rank then
                family.candidate = { slot = record.slot, entry = entry }
            end
        end
    end
    local reports = {}
    for _, family in ipairs(families) do
        local candidate, highest = family.candidate, family.highest
        if candidate and not counts[highest.spellID] then
            if not Enabled() or YAB.Adapter:InCombat() or not action:IsCursorEmpty() then break end
            local ok = action:ReplaceSpellSlot(candidate.slot, candidate.entry.spellID, highest.spellID)
            if ok then
                counts[highest.spellID] = 1
                counts[candidate.entry.spellID] = counts[candidate.entry.spellID] - 1
                self.replacements = self.replacements + 1
                reports[#reports + 1] = { name = highest.name,
                    oldRank = candidate.entry.rank, newRank = highest.rank }
                local buttons = YAB.BarManager.slotButtons[candidate.slot]
                for _, button in ipairs(buttons or {}) do
                    YAB.Visuals:FlashRankUpgrade(button, highest.spellID)
                end
            end
        end
    end
    PrintReplacements(reports)
    return true
end

local function ClearWaitEvents()
    if not Upgrade.frame then return end
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED", "SPELL_TEXT_UPDATE", "SPELLS_CHANGED" }) do
        Upgrade.frame:UnregisterEvent(event)
    end
end

local function RunPending()
    Upgrade.timer = nil
    if not Upgrade.pending or not Enabled() then Upgrade:CancelPending(); return end
    if YAB.Adapter:InCombat() then Upgrade.frame:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    if not YUI.API.ActionBar:IsCursorEmpty() then Upgrade.frame:RegisterEvent("CURSOR_CHANGED"); return end
    ClearWaitEvents()
    Upgrade.pending = false
    Upgrade.running = true
    local runOK, ok, reason = pcall(Upgrade.RunPass, Upgrade)
    Upgrade.running = false
    if not runOK then
        Upgrade:CancelPending()
        if YUI.Debug then YUI:Debug("YActionBar rank upgrade failed") end
        return
    end
    if not ok and reason == "not-ready" then
        Upgrade.attempts = (Upgrade.attempts or 0) + 1
        if Upgrade.attempts < 3 then
            Upgrade.pending = true
            Upgrade.frame:RegisterEvent("SPELL_TEXT_UPDATE")
            Upgrade.frame:RegisterEvent("SPELLS_CHANGED")
        end
    else
        Upgrade.attempts = 0
    end
    if Upgrade.pending and ok then Upgrade:Schedule() end
end

function Upgrade:Schedule()
    if not self.pending or self.timer or self.running then return end
    if YAB.Adapter:InCombat() then self.frame:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    if not YUI.API.ActionBar:IsCursorEmpty() then self.frame:RegisterEvent("CURSOR_CHANGED"); return end
    self.timer = C_Timer.NewTimer(0.15, RunPending)
end

function Upgrade:Request()
    if not self.active or not Enabled() then return end
    self.pending = true
    self.attempts = 0
    self:Schedule()
end

local function OnEvent(_, event)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        Upgrade:Request()
    elseif Upgrade.pending then
        Upgrade:Schedule()
    end
end

function Upgrade:CancelPending()
    if self.timer then self.timer:Cancel(); self.timer = nil end
    self.pending = false
    self.attempts = 0
    ClearWaitEvents()
end

function Upgrade:Stop()
    self:CancelPending()
    self.active = false
    if self.frame then self.frame:UnregisterAllEvents(); self.frame:SetScript("OnEvent", nil) end
    if YAB.Visuals then YAB.Visuals:StopAllRankUpgrades() end
end

function Upgrade:SyncEnabled()
    if not Enabled() then self:Stop(); return end
    if self.active then return end
    self.frame = self.frame or CreateFrame("Frame")
    self.frame:SetScript("OnEvent", OnEvent)
    self.frame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    self.active = true
    -- Startup/profile restoration installs listeners only; it never requests a pass.
end

function Upgrade:SetEnabled(value)
    local db = YAB:GetDB()
    local enabled, wasEnabled = value == true, db.interaction.autoRankUpgrade ~= false
    if enabled == wasEnabled then return end
    db.interaction.autoRankUpgrade = enabled
    self:SyncEnabled()
    if enabled then self:Request() end
end
