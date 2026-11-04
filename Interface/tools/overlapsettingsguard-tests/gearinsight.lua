return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf)
  local function BuildGI(w, db)
    GearInsightForeverDB = db or { leveling = { shown = true }, qm = {}, keysHud = true }
    local gi = { db = GearInsightForeverDB, Keys = {}, KeysHud = {}, QM = {} }
    GearInsightForever = gi
    GearInsightForeverLeveling = CreateFrame("Frame")
    if gi.db.leveling and gi.db.leveling.shown then GearInsightForeverLeveling:Show() end
    gi.KeysHud.frame = CreateFrame("Frame")
    if gi.db.keysHud then gi.KeysHud.frame:Show() end
    function gi.KeysHud.Toggle(on)
      gi.db.keysHud = on
      if on then gi.KeysHud.frame:Show() else gi.KeysHud.frame:Hide() end
    end
    function gi.ToggleLeveling()
      gi.db.leveling.shown = not GearInsightForeverLeveling:IsShown()
      if gi.db.leveling.shown then GearInsightForeverLeveling:Show() else GearInsightForeverLeveling:Hide() end
    end
    function gi.QM.PlatesOnOpen()
      if gi.db.qm.autoPlates then SetCVar("nameplateShowFriendlyPlayers", "1") end
    end
    function gi.QM.PlatesOnClose()
      if gi.db.qm.platesWeOpened then SetCVar("nameplateShowFriendlyPlayers", "0"); gi.db.qm.platesWeOpened = nil end
    end
    for _, name in ipairs({ "PlaceMissing", "Restore", "AssignSlotKey", "ApplyKeyTemplate", "RestoreStolen",
      "PlaceSpellAt", "ClearSlot", "ClearSpellEverywhere", "ResetMainBar", "UnbindKey" }) do
      gi.Keys[name] = function() w.edited = true; return 7 end
    end
    return gi
  end

  test("GearInsight defaults and visible duplicates are disabled without changing planning data", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    gi.db.talentPlan, gi.db.wish, gi.db.keysBoard = "build", { [123] = true }, true
    w.Login()
    eq(gi.db.qm.autoPlates, false)
    eq(gi.db.keysHud, false)
    eq(gi.KeysHud.frame:IsShown(), false)
    eq(gi.db.leveling.shown, false)
    eq(GearInsightForeverLeveling:IsShown(), false)
    eq(gi.db.talentPlan, "build")
    eq(gi.db.wish[123], true)
    eq(gi.db.keysBoard, true, "unique rotation board remains available")
    for _, id in ipairs({ "gi.friendlynameplates", "gi.combathud", "gi.resources", "gi.levelingstats", "gi.actionbaredits" }) do
      eq(StatusOf(w.ns.Check(), id), "off", id)
    end
  end)

  test("GearInsight option hooks revert HUD and nameplates on the next frame", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    w.Login()
    gi.KeysHud.Toggle(true)
    w.RunTimers()
    eq(gi.db.keysHud, false)
    eq(gi.KeysHud.frame:IsShown(), false)
    gi.db.qm.autoPlates = true
    gi.QM.PlatesOnOpen()
    w.RunTimers()
    eq(gi.db.qm.autoPlates, false)
  end)

  test("GearInsight checks fresh database references and visible stale frames", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    w.Login()
    gi.db = { qm = {}, leveling = {}, keysHud = false }
    GearInsightForeverDB = gi.db
    gi.KeysHud.frame:Show()
    GearInsightForeverLeveling:Show()
    w.Tick()
    eq(gi.db.qm.autoPlates, false)
    eq(gi.db.leveling.shown, false)
    eq(gi.KeysHud.frame:IsShown(), false)
    eq(GearInsightForeverLeveling:IsShown(), false)
  end)

  test("GearInsight ownership is inactive without owners and releases runtime editing locks", function()
    local loaded = CurrentLoaded()
    loaded.YUI, loaded.EllesmereUINameplates, loaded.EllesmereUIUnitFrames = nil, nil, nil
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local gi = BuildGI(w)
    w.Login()
    eq(gi.db.keysHud, true)
    eq(gi.db.leveling.shown, true)
    gi.Keys.PlaceMissing({})
    eq(w.edited, true)
    loaded.YUI = true
    w.Tick()
    w.edited = false
    gi.Keys.PlaceMissing({})
    eq(w.edited, false)
    loaded.YUI = nil
    gi.Keys.PlaceMissing({})
    eq(w.edited, true, "wrapper is conditional on loaded owner")
  end)

  test("GearInsight actions stay read-only while YUI owns bars with safe return contracts", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    w.Login()
    gi.Keys.PlaceMissing({}); gi.Keys.Restore({})
    gi.Keys.PlaceSpellAt({}, 1); gi.Keys.ClearSlot(1); gi.Keys.ClearSpellEverywhere("spell")
    eq(gi.Keys.UnbindKey("Q"), false)
    local resetCount, resetSkipped = gi.Keys.ResetMainBar()
    eq(resetCount, 0, "caller reads nil as being in combat"); eq(type(resetSkipped), "table")
    local accepted = gi.Keys.AssignSlotKey(1, "Q")
    eq(accepted, false)
    local count, skipped, stolen = gi.Keys.ApplyKeyTemplate({1}, {})
    eq(count, 0); eq(type(skipped), "table"); eq(type(stolen), "table")
    eq(gi.Keys.RestoreStolen(), 0)
    eq(w.edited, nil, "none of the original editing functions ran")
    gi.Keys.PlaceSpellAt = function() w.edited = true end
    w.Tick()
    gi.Keys.PlaceSpellAt({}, 1)
    eq(w.edited, nil, "replaced editing function is guarded again")
  end)

  test("GearInsight enforcement defers in combat and releases only its own nameplate toggle", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded(), cvars = { nameplateShowFriendlyPlayers = "1" } })
    local gi = BuildGI(w)
    gi.db.qm.platesWeOpened = "nameplateShowFriendlyPlayers"
    w.combat = true
    w.Login()
    eq(gi.db.keysHud, true)
    eq(gi.db.qm.autoPlates, nil)
    w.combat = false
    w.Fire("PLAYER_REGEN_ENABLED")
    eq(gi.db.keysHud, false)
    eq(gi.db.qm.autoPlates, false)
    eq(GetCVar("nameplateShowFriendlyPlayers"), "0")
    SetCVar("nameplateShowFriendlyPlayers", "1")
    w.Tick()
    eq(GetCVar("nameplateShowFriendlyPlayers"), "1", "user/EUI visibility survives")
  end)

  test("GearInsight missing APIs block changes and a failed HUD refresh retries", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    local toggle = gi.KeysHud.Toggle
    gi.KeysHud.Toggle = nil
    w.Login()
    eq(gi.db.keysHud, true)
    gi.KeysHud.Toggle = function() gi.db.keysHud = false; error("refresh failed") end
    w.Tick()
    eq(gi.KeysHud.frame:IsShown(), true)
    gi.KeysHud.Toggle = toggle
    w.Tick()
    eq(gi.KeysHud.frame:IsShown(), false)
    eq(gi.db.keysHud, false)
  end)

  test("installed GearInsight bar editor cannot write actions or bindings under the guard", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    gi.L = function(_, en) return en end
    assert(loadfile(ADDON_ROOT .. "../GearInsight_Forever/Keys.lua"))("GearInsight_Forever", gi)
    local writes = 0
    _G.SetBinding = function() writes = writes + 1 end
    _G.SaveBindings = function() writes = writes + 1 end
    _G.PlaceAction = function() writes = writes + 1 end
    w.Login()
    gi.Keys.PlaceMissing({id=1, name="spell"})
    gi.Keys.Restore({cls="Rogue"})
    gi.Keys.PlaceSpellAt({id=1, name="spell"}, 1, "slot")
    gi.Keys.ClearSlot(1, "slot")
    gi.Keys.ClearSpellEverywhere("spell")
    gi.Keys.UnbindKey("Q")
    gi.Keys.ResetMainBar()
    eq(gi.Keys.AssignSlotKey(1, "Q"), false)
    local count, skipped, stolen = gi.Keys.ApplyKeyTemplate({1}, {keys={"Q"}})
    eq(count, 0); eq(#skipped, 0); eq(#stolen, 0)
    eq(gi.Keys.RestoreStolen(), 0)
    eq(writes, 0, "game actions and saved bindings remain untouched")
    eq(gi.Keys.SlotCommand(1), "ACTIONBUTTON1", "read-only inspection remains available")
  end)

  test("every installed GearInsight Keys function is classified as locked or read-only", function()
    local readOnly = {}
    for name in ([[ActiveView AddonBarKeys Backup CurrentFormKey DebugMacros DiagView FirstFreeSideSlot FormByKey
      FormChoices FormKnown Forms GroupOf Grouped InForm KeyAction KeyFree KeyMap LiveMap MacroSpellNames MainPosOfKey
      MainPosSlot MainTree Plan RacialEntries Resolve SharedForms SlotCommand SlotKey SlotMacroSpells SpellOfKey Status
      StolenTable ViewOf]]):gmatch("%S+") do readOnly[name] = true end
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local locked = {}
    for _, name in ipairs(w.ns.adapters.GearInsight.EDITS) do locked[name] = true end
    local file = assert(io.open(ADDON_ROOT .. "../GearInsight_Forever/Keys.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local found = {}
    for name in source:gmatch("function K%.([%w_]+)") do
      found[name] = true
      ok(locked[name] or readOnly[name], "classify new GearInsight function K." .. name)
    end
    for name in pairs(locked) do ok(found[name], "locked function no longer exists: K." .. name) end
  end)

  test("one missing edit function does not cancel the other locks and warns once", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w)
    gi.Keys.Restore = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), "gi.actionbaredits"), "off")
    gi.Keys.PlaceSpellAt({}, 1)
    eq(w.edited, nil, "remaining functions stay locked")
    w.Tick()
    local warnings = 0
    for _, line in ipairs(w.printed) do
      if line:find("Keys.Restore", 1, true) then warnings = warnings + 1 end
    end
    eq(warnings, 1)
  end)

  test("friendly nameplates are enforced before the load-on-demand Group module exists", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w, { leveling = { shown = false }, qm = { autoPlates = true }, keysHud = false })
    gi.QM = nil
    w.Login()
    eq(gi.db.qm.autoPlates, false)
    eq(gi.db.qm.platesV3, 1, "upstream's one-time migration must not re-enable it")
    eq(StatusOf(w.ns.Check(), "gi.friendlynameplates"), "off")
    for _, line in ipairs(w.printed) do
      ok(not line:find("cannot enforce GearInsight: Automatic friendly", 1, true), line)
    end
  end)

  test("an existing setting without the migration marker is protected from the migration", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local gi = BuildGI(w, { leveling = { shown = false }, qm = { autoPlates = false }, keysHud = false })
    gi.QM = nil
    w.Login()
    eq(gi.db.qm.autoPlates, false)
    eq(gi.db.qm.platesV3, 1)
  end)

  test("a leftover toggle waits for the Group module and then is released", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded(), cvars = { nameplateShowFriendlyPlayers = "1" } })
    local gi = BuildGI(w, { leveling = { shown = false }, keysHud = false,
      qm = { autoPlates = false, platesV3 = 1, platesWeOpened = "nameplateShowFriendlyPlayers" } })
    local qm = gi.QM
    gi.QM = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), "gi.friendlynameplates"), "off", "nothing can change the CVar yet")
    eq(GetCVar("nameplateShowFriendlyPlayers"), "1")
    gi.QM = qm
    w.Tick()
    eq(GetCVar("nameplateShowFriendlyPlayers"), "0")
    eq(gi.db.qm.platesWeOpened, nil)
  end)

  test("a loaded Group module is reverted by the periodic check after a later migration", function()
    local loaded = CurrentLoaded()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, cvars = { nameplateShowFriendlyPlayers = "0" } })
    local gi = BuildGI(w, { leveling = { shown = false }, qm = { autoPlates = false, platesV3 = 1 }, keysHud = false })
    local qm = gi.QM
    gi.QM = nil
    w.Login()
    gi.QM, loaded.GearInsight_Forever_Group = qm, true
    gi.db.qm.autoPlates, gi.db.qm.platesWeOpened = true, "nameplateShowFriendlyPlayers"
    SetCVar("nameplateShowFriendlyPlayers", "1")
    w.Tick()
    eq(gi.db.qm.autoPlates, false)
    eq(GetCVar("nameplateShowFriendlyPlayers"), "0")
  end)

  test("a loaded Group module without the expected API reports a blocked rule", function()
    local loaded = CurrentLoaded()
    loaded.GearInsight_Forever_Group = true
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local gi = BuildGI(w, { leveling = { shown = false }, qm = {}, keysHud = false })
    gi.QM = nil
    w.Login()
    eq(StatusOf(w.ns.Check(), "gi.friendlynameplates"), "blocked")
    gi.QM = {}
    w.Tick()
    eq(StatusOf(w.ns.Check(), "gi.friendlynameplates"), "blocked")
  end)
end
