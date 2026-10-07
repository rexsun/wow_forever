local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- /hf selftest - checks HealForever against the client it's actually running on
-- and stores the answers in the saved variables, so they can be read outside
-- the game. The point is questions no test harness can answer: does this
-- client have a spellbook API, does it hide unit values, did our frames
-- actually get made, and how long does a refresh take.

local function Yes(value)
  return value and "yes" or "no"
end

local function Timed(fn)
  if not debugprofilestop then
    return nil
  end
  local started = debugprofilestop()
  fn()
  return debugprofilestop() - started
end

function ns.SelfTest()
  local report = {}
  local function line(...)
    report[#report + 1] = table.concat({ ... }, " ")
  end

  local version, build, _, interface = GetBuildInfo()
  line("client", tostring(version), "build", tostring(build), "interface", tostring(interface))
  line("frames", ns.Version(),
    "profile", ns.ActiveProfileName())

  -- What this client lets addons see
  line("secret values:", Yes(ns.Secrets.Enabled()),
    "| health readable:", Yes(ns.Secrets.CanMeasureHealth("player")),
    "| auras readable:", Yes(not ns.Secrets.AurasSecret()))
  if ns.inferStats then
    line("hot inference:", Yes(ns.db.inferHots), "| clicks seen", tostring(ns.inferStats.clicks),
      "| auras inferred", tostring(ns.inferStats.applied),
      "| cast events the game kept secret", tostring(ns.inferStats.unreadable))
  end
  if ns.gameAuraStats then
    local g = ns.gameAuraStats
    line("game-drawn dispels:", Yes(ns.db.gameDispels), "| api", Yes(C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor),
      "| asked", tostring(g.asked), "granted", tostring(g.granted), "refused", tostring(g.refused),
      g.lastError and ("| last: " .. tostring(g.lastError):sub(1, 120)) or "")
  end
  if ns.gameBuffStats then
    local g = ns.gameBuffStats
    line("game-drawn buffs:", Yes(ns.db.gameBuffs), "| combat only", Yes(ns.db.gameBuffsCombatOnly),
      "| asked", tostring(g.asked), "granted", tostring(g.granted), "refused", tostring(g.refused),
      g.lastError and ("| last: " .. tostring(g.lastError):sub(1, 120)) or "")
  end
  if ns.gameHotStats then
    local g = ns.gameHotStats
    line("game-drawn HoT row:", Yes(ns.db.gameHots), "| container", Yes(ns.GameHotsAvailable and ns.GameHotsAvailable()),
      "| made", tostring(g.made), "refused", tostring(g.refused),
      g.lastError and ("| last: " .. tostring(g.lastError):sub(1, 120)) or "")
  end
  line("apis:",
    "C_UnitAuras", Yes(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex),
    "| UnitAura", Yes(UnitAura),
    "| incoming heals", Yes(UnitGetIncomingHeals),
    "| spellbook(classic)", Yes(GetNumSpellTabs and GetSpellBookItemInfo),
    "| spellbook(modern)", Yes(C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines))

  -- Where this character's settings are kept, and how much is in them: the
  -- answer to "did my bindings save?" without guessing.
  local bound = 0
  for _ in pairs(ns.db.bindings or {}) do bound = bound + 1 end
  line("saving to:", ns.CharacterKey(), "->", ns.ActiveProfileName(),
    "|", bound, "bindings,", #(ns.db.auraWatch or {}), "watched auras",
    "| mana bar", (ns.db.powerBarHeight or 0) > 0 and "on" or "off")

  -- Moving the frames: everything someone needs to drag them, in one line.
  local handle = ns.moveHandle
  local point, x, y = "?", 0, 0
  if ns.anchor then
    local p, _, _, px, py = ns.anchor:GetPoint() -- luacheck: ignore
    point, x, y = p or "?", px or 0, py or 0
  end
  line("frames:", ns.db.locked and "LOCKED" or "unlocked",
    "| move box", handle and (handle:IsShown() and "shown" or "hidden") or "MISSING",
    handle and ("%dx%d"):format(handle:GetWidth() or 0, handle:GetHeight() or 0) or "",
    "| anchor", tostring(point), tostring(x), tostring(y),
    "| scale", tostring(ns.db.scale))

  -- What is bound, and what the frames actually carry: a binding that is in
  -- the file but not on the button is the difference between "it didn't save"
  -- and "it didn't apply".
  local saved = {}
  for _, key in ipairs(ns.SortedBindingKeys(ns.db.bindings)) do
    local b = ns.db.bindings[key]
    saved[#saved + 1] = ("%s=%s"):format(key, b.spell or b.kind)
  end
  if #ns.missingEvents > 0 then
    line("events this client doesn't have:", table.concat(ns.missingEvents, " "))
  end

  line("database:", (FUI.db and FUI.db.frames == ns.db) and "frames are inside the ForeverUI profile"
    or "FRAMES NOT WIRED TO THE FOREVERUI PROFILE",
    "| mode", tostring(ns.GetMode and ns.GetMode() or "?"))

  line("bindings saved:", #saved > 0 and table.concat(saved, " ") or "none")

  local sample, applied = nil, {}
  for _, header in ipairs(ns.AllHeaders()) do
    sample = sample or header:GetAttribute("child1")
  end
  if sample then
    for _, key in ipairs(ns.SortedBindingKeys(ns.db.bindings)) do
      local prefix, suffix = key:match("^(.-)(%d)$")
      applied[#applied + 1] = ("%s=%s/%s"):format(key,
        tostring(sample:GetAttribute(prefix .. "type" .. suffix)),
        tostring(sample:GetAttribute(prefix .. "spell" .. suffix)))
    end
  end
  line("bindings on the frame:", sample and (table.concat(applied, " ")) or "no frames to check")

  -- Who last touched each binding. The answer to "it isn't saving" when the
  -- file plainly shows it saved: something wrote over it, and this says what.
  for i, entry in ipairs(ns.db.bindingLog or {}) do
    if i <= 6 then
      line(("  change %d: %s -> %s (%s)"):format(i, entry.key, entry.what, entry.source))
    end
  end

  -- What actually went wrong, in the addon's own words.
  local recorded = ns.db.errors or {}
  line("errors recorded:", #recorded == 0 and "none" or tostring(#recorded))
  for i, entry in ipairs(recorded) do
    if i <= 5 then
      line(("  error %d%s [%s]: %s"):format(i, entry.ours and " (ours)" or "",
        entry.version or "?", entry.message or "?"))
      if entry.ours and entry.stack and entry.stack ~= "" then
        line("    " .. entry.stack:gsub("\n", " | "))
      end
    end
  end

  for i, hide in ipairs(ns.panelHides or {}) do
    if i <= 2 then
      line(("  window closed by: %s"):format((hide.stack or "?"):gsub("\n", " | "):sub(1, 400)))
    end
  end

  local spells, _, couldRead = ns.ScanSpellbook(true)
  line("spellbook:", couldRead and "readable" or "UNREADABLE",
    "-", #spells, "spells,", #(ns.db.manualSpells or {}), "typed by hand")

  -- Did the frames actually get built?
  local frames, shown = 0, 0
  for _, header in ipairs(ns.AllHeaders()) do
    local i, child = 1, header:GetAttribute("child1")
    while child do
      frames = frames + 1
      if child:IsShown() then
        shown = shown + 1
      end
      i = i + 1
      child = header:GetAttribute("child" .. i)
    end
  end
  -- One line per header, so duplicate or stray frames are obvious from outside.
  for _, header in ipairs(ns.AllHeaders()) do
    local i, child, units = 1, header:GetAttribute("child1"), {}
    while child do
      units[#units + 1] = ("%s%s"):format(child:GetAttribute("unit") or "-",
        child:IsShown() and "" or "(hidden)")
      i = i + 1
      child = header:GetAttribute("child" .. i)
    end
    line(" ", header:GetName() or "?", header:IsShown() and "shown" or "hidden",
      "->", #units > 0 and table.concat(units, ",") or "no frames")
  end
  line("other addons drawing frames:",
    "ForeverUI", Yes(_G.ForeverUI ~= nil),
    "| VuhDo", Yes(_G.VUHDO_CONFIG ~= nil or _G.VuhDo ~= nil),
    "| Blizzard party", Yes(PartyFrame and PartyFrame:IsShown()))
  line("frames:", frames, "built,", shown, "shown |",
    "size", ns.db.frameWidth .. "x" .. ns.db.frameHeight,
    "| style", ns.db.frameStyle, "| locked", Yes(ns.db.locked))
  line("bindings:", #ns.SortedBindingKeys(ns.db.bindings), "| watched auras:", #ns.db.auraWatch)

  -- Speed: one full read+draw of every frame, and the ticker's share of it.
  local refresh = Timed(function()
    for _ = 1, 20 do
      ns.RefreshAll()
    end
  end)
  if refresh then
    line(("refresh: %.2f ms for 20 passes over %d frames"):format(refresh, math.max(shown, 1)))
  end

  local errors = BugGrabberDB and BugGrabberDB.errors
  if errors then
    local mine = 0
    for _, entry in ipairs(errors) do
      if entry.message and entry.message:find(ns.FOLDER, 1, true) then
        mine = mine + 1
      end
    end
    line("captured errors:", #errors, "total,", mine, "mentioning " .. ns.FOLDER)
  end

  ns.db.selfTest = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = report }
  ns.Print("self-test:")
  for _, text in ipairs(report) do
    ns.Print("  " .. text)
  end
  ns.Print("saved - log out or /reload to write it to disk.")
  return report
end
