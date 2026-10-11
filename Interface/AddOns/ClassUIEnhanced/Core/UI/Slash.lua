
local _
---@type string, private
local addonName, private = ...

SLASH_CUE1 = "/cue"

local L = private.L

local commandFunctions = {}

commandFunctions["minimap"] = function()
    local db = private.public.db.global.minimap
    db.hide = not db.hide
    if db.hide then
        private.libDBIcon:Hide("ClassUIEnhanced")
        private.print(L["MINIMAP_TOGGLED_OFF"])
    else
        private.libDBIcon:Show("ClassUIEnhanced")
        private.print(L["MINIMAP_TOGGLED_ON"])
    end
end

commandFunctions["debugbuffs"] = function()
    if private.ConsumableBuffTracker and private.ConsumableBuffTracker.DebugDetection then
        private.ConsumableBuffTracker.DebugDetection()
    else
        private.print("ConsumableBuffTracker not loaded.")
    end
end

commandFunctions["debugcast"] = function()
    if private.CastBar and private.CastBar.ToggleTextTrace then
        private.CastBar.ToggleTextTrace()
    else
        private.print("CastBar not loaded.")
    end
end

commandFunctions["debug"] = function()
    private.SetDebugMode(not private.profile.debug_mode)
    private.print(L["DEBUG_TOGGLED"], private.profile.debug_mode and L["DEBUG_ON"] or L["DEBUG_OFF"])
end

commandFunctions["version"] = function()
    private.GetVersionInfo(true)
end

commandFunctions["resetoptionspanel"] = function()
    private.public.db.global.options_panel_scale = 1
    if private.Options.ResetOptionsPanelLayout then
        private.Options.ResetOptionsPanelLayout()
    end
    private.print(L["OPTIONS_PANEL_RESET"])
end

commandFunctions["log"] = function()
    if private.OpenDebugLogViewer then
        private.OpenDebugLogViewer()
    else
        private.print("DebugLogViewer not loaded.")
    end
end

commandFunctions["logsave"] = function()
    if private.SaveDebugLogToSV then
        private.SaveDebugLogToSV()
    else
        private.print("DebugLogViewer not loaded.")
    end
end

commandFunctions["logclear"] = function()
    private.ClearDebugLog()
    private.print("Debug log cleared.")
end

commandFunctions["logtest"] = function()
    private.printdebug("logtest:", "synthetic entry", GetTime(), "ok")
    private.printdebug("logtest:", "second line", math.random(1, 9999))
    private.print("Wrote 2 test entries to the debug log buffer.")
end

---Dump the player's whole spellbook as `name = spellID`, grouped by skill line.
---
---Exists because racials are per-race *and* per-client data that no external dump
---covers: WoW Forever renumbered several of the 1.x racials and added new ones
---outright (Night Elf "Elune's Light" 1259799 is in no retail DB2), so the only
---way to fill `RACIAL_SPELLS` for a race is to stand on a character of it. Run
---this on a fresh character of each race and paste the output back.
---
---Dumps every skill line rather than just General: whether racials live there is
---itself an assumption, and on a level-1 character the whole book is a few lines.
commandFunctions["racials"] = function()
    local raceName, raceToken = UnitRace("player")
    local _, class = UnitClass("player")
    private.print(("Spellbook dump — race %s (token %s), class %s"):format(
        raceName or "?", raceToken or "?", class or "?"))
    for lineIndex = 1, private.compat.GetNumSpellBookSkillLines() do
        local line = private.compat.GetSpellBookSkillLineInfo(lineIndex)
        if line then
            private.print(("  [%s]"):format(line.name))
            for i = 1, line.numSpellBookItems do
                local info = private.compat.GetSpellBookItemInfo(line.itemIndexOffset + i,
                    Enum.SpellBookSpellBank.Player)
                if info and info.spellID then
                    private.print(("    %s = %d%s"):format(info.name, info.spellID,
                        info.isPassive and "  (passive)" or ""))
                end
            end
        end
    end
end

-- Alias for the /cueperf toggle, which private.slashHelp advertises as "/cue perf".
commandFunctions["perf"] = function()
    SlashCmdList["CUEPERF"]("")
end

commandFunctions["help"] = function()
    private.print("Available commands:")
    private.print("  /cue — open options panel")
    private.print("  /cue minimap — toggle minimap button")
    private.print("  /cue debugbuffs — debug consumable buff detection")
    private.print("  /cue debugcast — toggle cast bar name/time tracing into the debug log")
    private.print("  /cue debug — toggle debug logging")
    private.print("  /cue racials — dump this character's spellbook as name = spellID")
    private.print("  /cue log — open debug log viewer")
    private.print("  /cue log save — save buffer to SavedVariables (read after /reload)")
    private.print("  /cue log clear — clear the in-memory buffer and saved dump")
    private.print("  /cue version — print version info to chat")
    private.print("  /cue resetoptionspanel — reset options panel scale to 1 and re-center")
    private.print("  /cue help — show this list")
    if private.slashHelp then
        for _, entry in ipairs(private.slashHelp) do
            private.print("  /cue " .. entry.cmd .. " — " .. entry.desc)
        end
    end
end
commandFunctions["?"] = commandFunctions["help"]

function SlashCmdList.CUE(msg, editbox)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    rest = rest or ""
    local key = cmd
    if rest ~= "" then
        local second = rest:match("^(%S+)")
        if second then
            local combined = cmd .. string.lower(second)
            if commandFunctions[combined] then
                key = combined
            end
        end
    end

    if (commandFunctions[key]) then
        commandFunctions[key]()
    else
        private.Options.ToggleOptionsPanel()
    end
end