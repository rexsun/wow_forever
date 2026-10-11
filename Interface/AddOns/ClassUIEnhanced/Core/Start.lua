
--After libraries are loaded, this file is the frist to run

local _
---@type string, private
local addonName, private = ...

---@diagnostic disable-next-line: missing-fields
private.Enum = {}

---GCD reference spell for `C_Spell.GetSpellCooldown`. Retail's `61304` does not
---exist on WoW Forever (interface 16000–19999, ClientScope's "forever"); there the only spell carrying
---"Cooldown never secret" in the GCD category (133) is the test spell `1283885`
---(DB2 `SpellMisc.Attributes_15` bit 31, build 1.60.1.70235). Reads plain in
---combat there (user, 2026-10-06). Issue #56.
---@type number
local interface = select(4, GetBuildInfo())
private.GCD_SPELL_ID = (interface >= 16000 and interface < 20000) and 1283885 or 61304

---External anchor frames registered by other addons via ClassUIEnhancedAPI.AddAnchors().
---Keyed by global frame name; value contains the display name and registering addon.
---@type table<string, {displayName: string, addonName: string}>
private.externalAnchors = {}

local inDebugMode = false

-- Always-on ring buffer capturing every printdebug() invocation. Survives
-- combat secret-text restrictions so the user can copy diagnostics out via
-- the DebugLogViewer panel even when chat content is locked.
local debugLog = {}
local debugLogHead = 1
local debugLogCount = 0
local debugLogCapacity = 10000

function private.print(...)
    print("|cFFFFFF00CUE:|r", ...)
end

---`tostring` that survives a secret value.
---
---`tostring(secret)` does NOT return a plain string — it returns a SECRET
---string, which then poisons everything downstream: `table.concat` rejects it
---outright ("invalid value (secret) at index 1") and `string.format` propagates
---the secrecy into its whole result. So the test has to come BEFORE the
---conversion, never after. Blizzard does exactly this in
---`Blizzard_SharedXML/Dump.lua:312`.
---
---`fmt` is for numeric fields that want rounding (`"%.0f"`); it is applied only
---once the value is known to be plain, because `%f` on a secret fails the same
---way `%s` does.
---@param v any
---@param fmt string|nil
---@return string
function private.safestr(v, fmt)
    if issecretvalue(v) then return "<secret>" end
    if fmt then return string.format(fmt, v) end
    return tostring(v)
end

---Append a fresh entry to the ring buffer. Each entry stores monotonic time
---and the joined args. Allocates ~3 small objects per call (vararg table,
---joined string, entry table); only fires when printdebug is called.
---
---Secret-tolerant by design: this is the sink every `printdebug` in the addon
---funnels through, so one diagnostic that happens to stringify a secret must
---degrade to a placeholder rather than take the whole debug log down with it.
---A caller that wants a *useful* line still has to sanitize its own fields —
---`string.format` makes its entire result secret if any single argument is, so
---by the time it reaches here the whole line is one `<secret>`.
---@return string text  the joined line, so callers can echo it without re-stringifying
function private.AppendDebugLog(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = private.safestr(select(i, ...))
    end
    local text = table.concat(parts, " ")
    local entry = { t = GetTime(), text = text }
    debugLog[debugLogHead] = entry
    debugLogHead = (debugLogHead % debugLogCapacity) + 1
    if debugLogCount < debugLogCapacity then
        debugLogCount = debugLogCount + 1
    end
    return text
end

---Resize the ring buffer, preserving existing entries in chronological order.
---Shrinking drops the oldest excess; growing keeps everything.
---@param n integer
function private.SetDebugLogCapacity(n)
    n = tonumber(n) or 10000
    if n < 1 then n = 1 end
    if n == debugLogCapacity then return end
    local snapshot = private.SnapshotDebugLog()
    local newLog = {}
    local startIdx = 1
    if #snapshot > n then
        startIdx = #snapshot - n + 1
    end
    local count = 0
    for i = startIdx, #snapshot do
        count = count + 1
        newLog[count] = snapshot[i]
    end
    debugLog = newLog
    debugLogCapacity = n
    debugLogCount = count
    debugLogHead = (count % n) + 1
end

---Return a fresh array of entries in chronological (oldest → newest) order.
---@return {t:number, text:string}[]
function private.SnapshotDebugLog()
    local out = {}
    if debugLogCount == 0 then return out end
    local startIdx
    if debugLogCount < debugLogCapacity then
        startIdx = 1
    else
        startIdx = debugLogHead
    end
    for i = 0, debugLogCount - 1 do
        local idx = ((startIdx - 1 + i) % debugLogCapacity) + 1
        out[i + 1] = debugLog[idx]
    end
    return out
end

---Wipe both the in-memory ring buffer and the SavedVariables dump.
function private.ClearDebugLog()
    debugLog = {}
    debugLogHead = 1
    debugLogCount = 0
    if ClassUIEnhancedDB then
        ClassUIEnhancedDB.debug_log_dump = nil
    end
end

function private.printdebug(...)
    -- Echo the SANITIZED line rather than the raw varargs: hardening the ring
    -- buffer alone would just move the crash into `print`, which stringifies
    -- its arguments the same way.
    local text = private.AppendDebugLog(...)
    if inDebugMode or (private.profile and private.profile.debug_mode) then
        print("|cFFFFFF00CUE:|r", text)
    end
end

---Set the runtime debug flag and mirror it into the active profile (if loaded).
---Called by the slash command, Options toggle, and profile-load hydration so
---`inDebugMode` (the hot-path runtime flag) stays in sync with the saved value.
---@param value boolean
function private.SetDebugMode(value)
    inDebugMode = value and true or false
    if private.profile then
        private.profile.debug_mode = inDebugMode
    end
end

---Build a human-readable version info string.
---Includes addon version (from .toc ## Version), DetailsFramework version, and game build.
---@param printOut? boolean  if true, also prints the result to chat
---@return string
function private.GetVersionInfo(printOut)
    local addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
    local dfVersion = select(2, LibStub:GetLibrary("DetailsFramework-1.0"))
    local versionInfo = addonVersion .. " - DF v" .. dfVersion .. " - " .. GetBuildInfo()
    if printOut then
        private.print(versionInfo)
    end
    return versionInfo
end
