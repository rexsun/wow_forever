return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local EARLY = {
    { id = "gi.layernetwork", values = { layer = { on = false, pub = false, helper = false, helperV = 2 } }, owner = "YUI" },
    { id = "gi.layerautoaccept", values = { layer = { autoAccept = false } }, owner = "YUI" },
    { id = "gi.layerautoinvite", values = { layer = { autoHelp = false } }, owner = "YUI" },
    { id = "gi.layerautoleave", values = { layer = { autoLeave = false } }, owner = "YUI" },
    { id = "gi.groupautoload", values = { qm = { thanks = false }, ui = { groupLazy = true } }, owner = "YUI" },
    { id = "gi.questshare", values = { qm = { share = false } }, owner = "YUI" },
    { id = "gi.magewater", values = { ["dchat.mw"] = { fieldAsk = false, thank = false } }, owner = "YUI" },
    { id = "gi.cityplates", values = { cityPlates = { on = false } }, owner = "EllesmereUINameplates" },
  }

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function Saved(db)
    return function() GearInsightForeverDB = db end
  end

  local function UserData()
    return { layer = { order = { [1] = { 7 } }, log = { "kept" }, gather = "CODE" },
      cityPlates = { noted = true }, qm = { share = true, pinned = true }, ui = { page = "tier" },
      dchat = { rec = { roles = { TANK = true } }, mw = { bar = false } } }
  end

  -- Mirrors the 1.0.1 runtime pieces the guard calls or hooks.
  local function BuildGI(w, db)
    local gi = { db = db, Keys = {}, KeysHud = { Toggle = function() end }, QM = nil, calls = {} }
    gi.GuildChatLevel = {
      Enabled = function() return false end, WhisperOn = function() return false end, PartyOn = function() return false end,
      SetEnabled = function() end, SetWhisperOn = function() end, SetPartyOn = function() end,
    }
    gi.Layer = {
      SyncPub = function() gi.calls.syncPub = (gi.calls.syncPub or 0) + 1 end,
      SetPub = function(v) gi.db.layer.pub = v and true or false end,
    }
    gi.CityPlates = {
      Restore = function() gi.calls.restore = (gi.calls.restore or 0) + 1 end,
      SetOn = function(v) gi.db.cityPlates.on = v and true or false end,
    }
    gi.ItemLevel = {
      RefreshAll = function() gi.calls.refresh = (gi.calls.refresh or 0) + 1 end,
      SetOn = function(on) gi.db.ui = gi.db.ui or {}; if on then gi.db.ui.ilvl = nil else gi.db.ui.ilvl = false end end,
    }
    GearInsightForever = gi
    return gi
  end

  local function Section(db, path)
    for part in path:gmatch("[^.]+") do db = db and db[part] end
    return db
  end

  local function AssertOff(db, rule, what)
    for path, values in pairs(rule.values) do
      local section = Section(db, path)
      for field, value in pairs(values) do
        eq(section and section[field], value, rule.id .. " " .. path .. "." .. field .. (what and (" " .. what) or ""))
      end
    end
  end

  test("GearInsight 1.0 rules pair with their owners and the layer rules run before login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local ids = {}
    for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
    for _, spec in ipairs(EARLY) do
      local rule = ids[spec.id]
      ok(rule, spec.id)
      eq(rule.when[1], "GearInsight_Forever", spec.id)
      eq(rule.when[2], spec.owner, spec.id)
      eq(rule.early, true, spec.id .. " runs before login")
      eq(rule.needsReload, nil, spec.id .. " needs no reload")
    end
    eq(ids["gi.itemlevel"].when[2], "YUI")
    eq(ids["gi.itemlevel"].early, nil, "item level is drawn after login")
  end)

  test("GearInsight layer, city plate and group switches are written when the guard loads", function()
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded(), beforeGuard = Saved(db) })
    for _, rule in ipairs(EARLY) do AssertOff(db, rule, "before login") end
    eq(db.ui.ilvl, nil, "item level waits for the normal check")
    eq(db.layer.log[1], "kept")
    eq(db.layer.gather, "CODE")
    eq(db.cityPlates.noted, true)
    eq(db.qm.pinned, true, "other quest-mate settings kept")
    eq(db.ui.page, "tier", "other UI settings kept")
    eq(db.dchat.rec.roles.TANK, true, "dungeon recruiting settings kept")
    eq(db.dchat.mw.bar, false, "other Mage water settings kept")
    ok(not ChatContains(w, "/reload"), "no reload")
    local gi = BuildGI(w, db)
    w.Login()
    eq(db.ui.ilvl, false)
    eq(gi.calls.refresh, 1, "item level display is refreshed at once")
    for _, rule in ipairs(EARLY) do eq(StatusOf(w.ns.Check(), rule.id), "off", rule.id) end
    eq(StatusOf(w.ns.Check(), "gi.itemlevel"), "off")
  end)

  test("GearInsight first run: the saved table is created and GearInsight keeps it", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded() })
    local db = GearInsightForeverDB
    ok(type(db) == "table", "saved table created")
    for _, rule in ipairs(EARLY) do AssertOff(db, rule) end
  end)

  test("GearInsight's helper migration cannot switch the hop helper back on", function()
    local db = { layer = { on = false, pub = false, helper = false } }
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded(), beforeGuard = Saved(db) })
    eq(db.layer.helperV, 2, "a missing migration marker counts as on")
    eq(db.layer.helper, false)
  end)

  test("GearInsight switches turned back on are reverted and live state is released", function()
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = CurrentLoaded(), beforeGuard = Saved(db) })
    local gi = BuildGI(w, db)
    w.Login()
    gi.Layer.SetPub(true)
    w.RunTimers()
    eq(db.layer.pub, false, "public channel toggle is reverted on the next frame")
    ok(gi.calls.syncPub >= 1, "the per-map channel is left at once")
    gi.CityPlates.SetOn(true)
    w.RunTimers()
    eq(db.cityPlates.on, false, "city plate toggle is reverted")
    ok(gi.calls.restore >= 1, "nameplates GearInsight hid are restored")
    gi.ItemLevel.SetOn(true)
    w.RunTimers()
    eq(db.ui.ilvl, false, "item level toggle is reverted")
    db.layer.autoAccept, db.layer.autoHelp, db.layer.autoLeave, db.layer.on = true, true, true, true
    db.qm.thanks, db.ui.groupLazy, db.qm.share = nil, nil, true
    db.dchat.mw = nil
    w.Tick()
    for _, rule in ipairs(EARLY) do AssertOff(db, rule, "after slash-command edits") end
  end)

  test("GearInsight 1.0 rules are inactive without their owners", function()
    local loaded = CurrentLoaded()
    loaded.YUI, loaded.EllesmereUINameplates = nil, nil
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, beforeGuard = Saved(db) })
    BuildGI(w, db)
    w.Login()
    eq(db.layer.on, nil)
    eq(db.layer.autoAccept, nil)
    eq(db.qm.thanks, nil)
    eq(db.qm.share, true)
    eq(db.ui.groupLazy, nil)
    eq(db.dchat.mw.thank, nil)
    eq(db.cityPlates.on, nil)
    eq(db.ui.ilvl, nil)
    for _, id in ipairs({ "gi.layernetwork", "gi.groupautoload", "gi.questshare", "gi.magewater", "gi.cityplates", "gi.itemlevel" }) do
      eq(StatusOf(w.ns.Check(), id), "inactive", id)
    end
  end)

  test("guarded GearInsight 1.0 switches exist in the installed source", function()
    local root = ADDON_ROOT .. "../GearInsight_Forever/"
    local layer = ReadFile(root .. "Layer.lua")
    for _, needle in ipairs({ "if d.on == nil then d.on = true end", "if d.pub == nil then d.pub = true end",
      "if d.helperV ~= 2 then d.helper = true; d.helperV = 2 end",
      -- 1.1.x: nil asks once and the one-time migration clears only true, so the guard's false survives.
      "if d[k] == true then d[k] = nil end",
      "local want = (LY.DB().pub and not inInstance())", "function LY.SyncPub()", "function LY.SetPub(v)" }) do
      ok(layer:find(needle, 1, true), "Layer.lua: " .. needle)
    end
    local _, beats = layer:gsub("if not d.on then return end", "")
    eq(beats, 2, "heartbeat building and sending both check layer.on")
    ok(ReadFile(root .. "LayerGuild.lua"):find("if LY.DB().autoAccept == false then return nil end", 1, true), "auto-accept switch")
    local hop = ReadFile(root .. "LayerHop.lua")
    ok(hop:find("if LY.DB().autoHelp == false then return false end", 1, true), "auto-invite switch")
    ok(hop:find("if a == true then doLeave(); return true end", 1, true), "auto-leave switch")
    local plates = ReadFile(root .. "CityPlates.lua")
    ok(plates:find("function CP.Enabled() return CP.DB().on ~= false end", 1, true), "city plate switch")
    ok(plates:find("function CP.Restore()", 1, true), "city plate restore")
    local ui = ReadFile(root .. "UI.lua")
    ok(ui:find("if ns.db and ns.db.qm and ns.db.qm.thanks == false then return end", 1, true), "group auto-load in a group")
    ok(ui:find("function ns.GroupAutoLoad() return not (ns.db and ns.db.ui and ns.db.ui.groupLazy) end", 1, true),
      "group auto-load at login")
    local quests = ReadFile(root .. "../GearInsight_Forever_Group/QuestMates.lua")
    ok(quests:find("if q.share == nil then q.share = true end", 1, true), "quest sharing defaults on")
    local _, shareChecks = quests:gsub("if not dbq%(%).share", "")
    eq(shareChecks, 2, "broadcasts and replies both check qm.share")
    local parts = ReadFile(root .. "../GearInsight_Forever_Group/GroupParts.lua")
    ok(parts:find("return not (o and o.fieldAsk == false) or not (o and o.thank == false)", 1, true),
      "Mage water auto-loads unless both switches are off")
    local water = ReadFile(root .. "../GearInsight_Forever_GroupMage/MageWater.lua")
    ok(water:find('if not MW.Opt("thank") or MW.IsMage() then return end', 1, true), "thank-you whisper switch")
    ok(water:find('if not MW.Opt("fieldAsk") then return end', 1, true), "nearby Mage popup switch")
    local ilvl = ReadFile(root .. "ItemLevel.lua")
    ok(ilvl:find("ns.db.ui.ilvl == false", 1, true), "item level switch")
    ok(ilvl:find("function IL.RefreshAll()", 1, true), "item level refresh")
    local chat = ReadFile(root .. "GuildChatLevel.lua")
    for _, name in ipairs({ "GL.WhisperOn()", "GL.PartyOn()", "GL.SetWhisperOn(on)", "GL.SetPartyOn(on)", "GL.SetEnabled(on)" }) do
      ok(chat:find("function " .. name, 1, true), "GuildChatLevel " .. name)
    end
  end)
end
