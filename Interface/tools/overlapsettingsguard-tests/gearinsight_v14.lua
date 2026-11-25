return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  -- GearInsight 1.4.x features that act without a click. Paths are sections of GearInsightForeverDB;
  -- "" is the saved table's root.
  local RULES = {
    { id = "gi.tradereceipt", values = { ui = { tradeReceipt = false } }, owner = "YUI" },
    { id = "gi.mounttrinket", values = { [""] = { mountTrinket = false }, mtBtn = { hide = true } }, owner = "YUI" },
    { id = "gi.auraremind", values = { auraRemind = { on = false } }, owner = "YUI" },
    { id = "gi.ammoremind", values = { ammoRemind = { on = false } }, owner = "YUI" },
    { id = "gi.xpprep", values = { xpcheck = { prep = false } }, owner = "YUI" },
    { id = "gi.selljunk", values = { sellJunk = { panel = false, auto = false } }, owner = "YUI" },
    { id = "gi.dungeonnav", values = { dnav = { on = false } }, owner = "MapUtils" },
    { id = "gi.auctionpricetip", values = { sellJunk = { ahTip = false } }, owner = "Auctionator" },
    { id = "gi.profshopping", values = { prof = { quick = false, btn = false } }, owner = "Auctionator" },
    { id = "gi.bagbuttons", values = { bagButtons = { show = false } }, owner = "Bagnon" },
  }
  local BUFFASK = { buffAsk = { auto = false, field = false, dmode = "off", ss = false } }

  local function Loaded()
    local loaded = CurrentLoaded()
    loaded.MapUtils, loaded.Auctionator, loaded.Bagnon = true, true, true
    return loaded
  end

  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function Section(db, path)
    for part in path:gmatch("[^.]+") do db = db and db[part] end
    return db
  end

  local function AssertValues(db, values, label)
    for path, fields in pairs(values) do
      local section = Section(db, path)
      for field, value in pairs(fields) do
        eq(section and section[field], value, label .. " " .. path .. "." .. field)
      end
    end
  end

  local function UserData()
    return { mtSwaps = { ["Ann-Realm"] = 13 }, mtBtn = { x = 10 }, auraRemind = { last = "devotion" },
      ammoRemind = { nav = false }, xpcheck = { on = true, thank = true }, sellJunk = { white = true, sort = "name" },
      dnav = { run = { id = 1 } }, prof = { route = "lw" }, bagButtons = { pos = 2 },
      ui = { tradeReceiptGot = false, page = "tier" }, buffAsk = { whisper = true, dmode = "auto" } }
  end

  local function Saved(db)
    return function() GearInsightForeverDB = db end
  end

  -- Mirrors the 1.4.20 runtime pieces the guard calls or hooks.
  local function BuildGI(db)
    local calls = {}
    local function count(name) return function() calls[name] = (calls[name] or 0) + 1 end end
    local function onSwitch(path, field)
      return function(v)
        local section = db
        for part in path:gmatch("[^.]+") do section[part] = section[part] or {}; section = section[part] end
        if v then section[field] = nil else section[field] = false end
      end
    end
    local gi = { db = db, Keys = {}, KeysHud = { Toggle = function() end }, calls = calls }
    gi.GuildChatLevel = {
      Enabled = function() return false end, WhisperOn = function() return false end, PartyOn = function() return false end,
      SetEnabled = function() end, SetWhisperOn = function() end, SetPartyOn = function() end,
    }
    gi.TradeReceipt = { SetOn = onSwitch("ui", "tradeReceipt") }
    gi.MountTrinket = { Sync = count("mtSync"), BtnUpdate = count("mtBtn") }
    gi.AuraRemind = { SetOn = onSwitch("auraRemind", "on"), Refresh = count("aura") }
    gi.AmmoRemind = { SetOn = onSwitch("ammoRemind", "on"), Update = count("ammo") }
    gi.XpCheck = { Prep = { Hide = count("prep") } }
    gi.DungeonNav = { SetEnabled = onSwitch("dnav", "on"), frame = { Hide = count("dnav") } }
    gi.SellCfg = { SetOpt = function(k, v) onSwitch("sellJunk", k)(v) end }
    gi.BagButtons = { SetOpt = function(k, v) onSwitch("bagButtons", k)(v) end, ApplyAll = count("bags") }
    gi.BuffAsk = {
      SetOpt = function(k, v) onSwitch("buffAsk", k)(v) end,
      SetDMode = function(m) db.buffAsk.dmode = m end,
      SyncEvents = count("sync"),
    }
    gi.SetFeature = function(key, v) if key == "mounttrinket" then db.mountTrinket = (not v) and false or nil end end
    GearInsightForever = gi
    return gi
  end

  test("GearInsight 1.4 rules pair with their owners and are written before login", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local ids = {}
    for _, rule in ipairs(w.ns.policy) do ids[rule.id] = rule end
    for _, spec in ipairs(RULES) do
      local rule = ids[spec.id]
      ok(rule, spec.id)
      if rule then
        eq(rule.adapter, "GearInsight", spec.id)
        eq(rule.when[1], "GearInsight_Forever", spec.id)
        eq(rule.when[2], spec.owner, spec.id)
        eq(rule.early, true, spec.id .. " runs before login")
      end
    end
  end)

  test("GearInsight 1.4 switches are written when the guard loads and other settings are kept", function()
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(), beforeGuard = Saved(db) })
    for _, rule in ipairs(RULES) do AssertValues(db, rule.values, rule.id) end
    AssertValues(db, BUFFASK, "gi.buffask")
    eq(db.mtSwaps["Ann-Realm"], 13, "a pending trinket swap-back is kept")
    eq(db.mtBtn.x, 10, "carrot icon position kept")
    eq(db.auraRemind.last, "devotion", "last aura kept")
    eq(db.ammoRemind.nav, false, "ammo vendor button choice kept")
    eq(db.xpcheck.on, true, "departure check itself kept")
    eq(db.sellJunk.white, true, "sell-junk white-item choice kept")
    eq(db.sellJunk.sort, "name", "sell-junk sort kept")
    eq(db.dnav.run.id, 1, "dungeon run progress kept")
    eq(db.prof.route, "lw", "profession route kept")
    eq(db.bagButtons.pos, 2, "bag button position kept")
    eq(db.ui.tradeReceiptGot, false, "trade receipt detail choice kept")
    eq(db.ui.page, "tier", "other UI settings kept")
    eq(db.buffAsk.whisper, true, "buff request whisper choice kept")
    local gi = BuildGI(db)
    w.Login()
    for _, rule in ipairs(RULES) do eq(StatusOf(w.ns.Check(), rule.id), "off", rule.id) end
    eq(StatusOf(w.ns.Check(), "gi.buffask"), "off")
  end)

  test("GearInsight 1.4 first run: the new switches start off", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    for _, rule in ipairs(RULES) do AssertValues(GearInsightForeverDB, rule.values, rule.id) end
    AssertValues(GearInsightForeverDB, BUFFASK, "gi.buffask")
  end)

  test("GearInsight 1.4 switches turned back on are reverted and live displays refresh", function()
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(), beforeGuard = Saved(db) })
    local gi = BuildGI(db)
    w.Login()
    local calls = gi.calls
    local before = { mtSync = calls.mtSync or 0, mtBtn = calls.mtBtn or 0, aura = calls.aura or 0, ammo = calls.ammo or 0,
      prep = calls.prep or 0, dnav = calls.dnav or 0, bags = calls.bags or 0, sync = calls.sync or 0 }
    gi.TradeReceipt.SetOn(true)
    w.RunTimers()
    eq(db.ui.tradeReceipt, false, "trade receipt whisper is reverted")
    gi.SetFeature("mounttrinket", true)
    w.RunTimers()
    eq(db.mountTrinket, false, "mount trinket swap is reverted")
    ok((calls.mtSync or 0) > before.mtSync, "a swapped trinket is put back at once")
    ok((calls.mtBtn or 0) > before.mtBtn, "the carrot icon is hidden at once")
    gi.AuraRemind.SetOn(true)
    w.RunTimers()
    eq(db.auraRemind.on, false, "aura reminder is reverted")
    ok((calls.aura or 0) > before.aura, "the aura bar is hidden at once")
    gi.AmmoRemind.SetOn(true)
    w.RunTimers()
    eq(db.ammoRemind.on, false, "ammo reminder is reverted")
    ok((calls.ammo or 0) > before.ammo, "the ammo icon is hidden at once")
    gi.DungeonNav.SetEnabled(true)
    w.RunTimers()
    eq(db.dnav.on, false, "dungeon guide pop-up is reverted")
    ok((calls.dnav or 0) > before.dnav, "an open dungeon guide is closed")
    gi.SellCfg.SetOpt("panel", true)
    gi.SellCfg.SetOpt("ahTip", true)
    w.RunTimers()
    eq(db.sellJunk.panel, false, "sell-junk panel is reverted")
    eq(db.sellJunk.ahTip, false, "auction price tooltip line is reverted")
    gi.BagButtons.SetOpt("show", true)
    w.RunTimers()
    eq(db.bagButtons.show, false, "bag window buttons are reverted")
    ok((calls.bags or 0) > before.bags, "bag window buttons are removed at once")
    gi.BuffAsk.SetDMode("auto")
    w.RunTimers()
    eq(db.buffAsk.dmode, "off", "dungeon buff request mode is reverted")
    ok((calls.sync or 0) > before.sync, "buff request events are resynced at once")
    db.xpcheck.prep, db.prof.quick, db.prof.btn, db.buffAsk.ss = nil, nil, nil, nil
    w.Tick()
    for _, rule in ipairs(RULES) do AssertValues(db, rule.values, rule.id .. " after settings-page edits") end
    AssertValues(db, BUFFASK, "gi.buffask after settings-page edits")
    ok((calls.prep or 0) > before.prep, "an open departure checklist is closed")
  end)

  test("GearInsight 1.4 rules are inactive without their owners", function()
    local loaded = Loaded()
    loaded.YUI, loaded.MapUtils, loaded.Auctionator, loaded.Bagnon = nil, nil, nil, nil
    local db = UserData()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded, beforeGuard = Saved(db) })
    BuildGI(db)
    w.Login()
    eq(db.ui.tradeReceipt, nil)
    eq(db.mountTrinket, nil)
    eq(db.dnav.on, nil)
    eq(db.sellJunk.ahTip, nil)
    eq(db.bagButtons.show, nil)
    for _, rule in ipairs(RULES) do eq(StatusOf(w.ns.Check(), rule.id), "inactive", rule.id) end
  end)

  test("guarded GearInsight 1.4 switches exist in the installed source", function()
    local root = ADDON_ROOT .. "../GearInsight_Forever/"
    local function has(file, needles)
      local text = ReadFile(root .. file)
      for _, needle in ipairs(needles) do ok(text:find(needle, 1, true), file .. ": " .. needle) end
    end
    has("TradeReceipt.lua", { "ns.TradeReceipt = TR",
      "function TR.On() local u = ui(); return u ~= nil and u.tradeReceipt ~= false end", "function TR.SetOn(v)" })
    has("MountStub.lua", { "local function mtGet() return ns.db.mountTrinket ~= false end",
      "if MT then MT.wait = true; pcall(MT.Sync); pcall(MT.BtnUpdate) end" })
    has("../GearInsight_Forever_Bag/MountTrinket.lua", { "ns.MountTrinket = MT",
      "function MT.BtnDB() ns.db.mtBtn = ns.db.mtBtn or {}; return ns.db.mtBtn end" })
    has("AuraRemind.lua", { "ns.AuraRemind = AR",
      "function AR.On() return not (ns.db and type(ns.db.auraRemind) == \"table\" and ns.db.auraRemind.on == false) end" })
    has("AmmoRemind.lua", { "ns.AmmoRemind = R", "function R.On() return ns.db ~= nil and R.DB().on ~= false end",
      "function R.Update()" })
    has("XpCheck.lua", { "ns.XpCheck = XC", 'if not (XC.Enabled() and opt("prep", true))' })
    has("DungeonNav.lua", { "ns.DungeonNav = DN",
      "function DN.Enabled() return not (ns.db and ns.db.dnav and ns.db.dnav.on == false) end" })
    has("BagStub.lua", { 'ns.SellCfg = cfg("sellJunk", { panel = true, auto = false, white = false, sort = "value", ahTip = true }',
      'if loaded("SellJunk") or ns.SellCfg.Opt("panel") or ns.SellCfg.Opt("auto") then',
      'not ns.SellCfg.Opt("ahTip") then return end' })
    has("ProfStub.lua", { "if not ns.db or (ns.db.prof and ns.db.prof.quick == false) then return false end",
      "if ns.db.prof and ns.db.prof.btn == false then b:Hide() end" })
    has("BagButtons.lua", { "ns.BagButtons = BB", "BB.DEFAULTS = { show = true }", "function BB.ApplyAll()" })
    has("Features.lua", { "function ns.SetFeature(key, v)" })
    has("../GearInsight_Forever_Group/BuffAsk.lua", {
      "if BA.DMODES[d.dmode] then return d.dmode end", 'if d.auto == false then return "off" end',
      'function BA.AutoOn() return BA.DMode() ~= "off" end', "function BA.SetDMode(m)",
      'local function ssWant() return ns.db and BA.Opt("on") and BA.DB().ss ~= false and myClass() ~= "WARLOCK" end' })
    -- YUI's HUD shows the equipped ammo count on Forever, which the ammo reminder duplicates.
    local hud = ReadFile(root .. "../YUI/Products/YHUD/Catalog/Forever/DefaultProfile.lua")
    ok(hud:find('["sourceType"] = "yhud.ammo-count"', 1, true), "YUI's Forever HUD shows ammo")
  end)
end
