local ADDON, ns = ...

-- Did the saved settings actually come back from disk?
--
-- The Forever beta client (since ~17 September 2026) writes every addon's
-- saved variables and never reads them back after a restart -- nor after a
-- /reload, once a saved file exists on disk (docs/saving-bug.md). It hides
-- behind the Standard and the installer, which make a fresh profile look
-- like a kept one.
--
-- So this file, loaded first in the TOC, looks at ForeverUIDB at each step of
-- startup and keeps a note. If nothing was read at load, one line says so at
-- login; /fui saved shows the whole trace.

local trace = {}
ns.loadTrace = trace

local function Look(stage)
  local db = rawget(_G, "ForeverUIDB")
  local line
  if type(db) ~= "table" then
    line = stage .. ": nothing loaded"
  else
    local d = db.profiles and db.profiles.Default
    local f = d and d.frames
    local binds = 0
    for _ in pairs(f and f.bindings or {}) do binds = binds + 1 end
    line = ("%s: db=%s profile=%s installed=%s frames=%s clicks=%d"):format(
      stage, tostring(db):sub(-8), d and tostring(d):sub(-8) or "none",
      d and tostring(d.installed) or "-", f and tostring(f):sub(-8) or "none", binds)
  end
  trace[#trace + 1] = line
  return line
end
ns.LookAtLoad = Look

-- True when the game handed us a saved table at ADDON_LOADED, i.e. the file
-- was read. Nil until then.
ns.savedRestored = nil

Look("file-load")

local f = CreateFrame("Frame")
ns.loadTracer = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.savedRestored = type(rawget(_G, "ForeverUIDB")) == "table"
    Look("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    Look("PLAYER_LOGIN")
  else
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Look("ENTERING_WORLD")
    if ns.MacroBackup and ns.MacroBackup.restored then
      ns.Print("|cff66ff66your setup is back|r -- the Forever beta didn't load ForeverUI's saved settings (a known "
        .. "client bug), so it was restored from ForeverUI's backup macros: which parts run, your role grids, "
        .. "their clicks and where they sit. Other settings are at their defaults until Blizzard fixes it.")
    elseif ns.savedRestored == false then
      -- Nothing came back. From in here a first run and the beta's bug look
      -- the same (no table either way), so the old "installed before" check
      -- could never fire: the fresh table it tested never says installed.
      -- Say it every time nothing was read, worded for both.
      ns.Print("|cffff6666no saved settings were found.|r First time? Welcome. Set it up before? Then this is the "
        .. "Forever beta's saved-settings bug, not ForeverUI: the client writes every addon's settings and doesn't read "
        .. "them back after a restart, or even after /reload once a saved file exists. Type /fui saved for the workaround.")
    end
  end
end)

function ns.SavedReport()
  ns.Print(("saved settings %s at load (addon folder \"%s\")."):format(
    ns.savedRestored and "|cff66ff66were read|r" or "|cffff6666were NOT read|r", ADDON))
  for _, line in ipairs(trace) do
    ns.Print("  " .. line)
  end
  if not ns.savedRestored then
    ns.Print("  If this isn't the first run: this is the Forever beta's saved-variables bug -- the file is written and never read. "
      .. "Every addon is affected until Blizzard fixes it; see github.com/ClassicWoWCommunity/forever-bugs issue 34.")
    ns.Print("  Until then, a community tool restores every addon's settings at load: ForeverSVFix, "
      .. "github.com/nobewayo/ForeverSVFix (third-party; quit the game before running it).")
  end
end
