return function(test, eq, ok, Stubs, _, StatusOf)
  local function Build(w, owners)
    local loaded = { Skinner = true }
    for _, name in ipairs(owners or { "YUI", "EllesmereUIUnitFrames", "EllesmereUIRaidFrames", "EllesmereUINameplates", "Details" }) do
      loaded[name] = true
    end
    w = Stubs.Fresh(ADDON_ROOT, { loaded = loaded })
    local defaults = { CastingBar = { skin = true, glaze = true }, CompactFrames = { skin = true, sbars = true },
      Nameplates = true, MainMenuBar = { skin = true, glazesb = true, altpowerbar = true, actbtns = true, extraab = true },
      Minimap = { skin = false, gloss = false }, MinimapButtons = { skin = false, style = false },
      WorldMap = { skin = true }, ChatBubbles = { skin = true }, ChatButtons = true, ChatConfig = true,
      ChatEditBox = { skin = true, style = 3 }, ChatFrames = false, ChatTabs = false, ChatTabsFade = true,
      CombatLogQBF = false, Tooltips = { skin = true, glazesb = true }, DisabledSkins = {} }
    local active = { MerchantFrame = true, QuestFrame = true, WorldMap = { skin = true, size = 1.2 },
      Minimap = { skin = true, gloss = true }, MinimapButtons = { skin = true, style = true },
      DisabledSkins = { Auctionator = false }, ChatEditBox = { skin = true, style = 3 } }
    local old = { CastingBar = { skin = true }, Nameplates = true }
    SkinnerDB = { profiles = { Default = active, Other = old }, namespaces = {
      UnitFrames = { profiles = { Default = { pet = true, petlvl = true, party = true }, Other = { target = true } } } } }
    local namespace = { profile = SkinnerDB.namespaces.UnitFrames.profiles.Default,
      defaults = { profile = { player = false, target = false, focus = false, pet = true, petlvl = true, arena = false, party = false } } }
    local callbacks = {}
    Skinner = { db = { profile = active, defaults = { profile = defaults }, sv = SkinnerDB,
      GetNamespace = function(_, name) if name == "UnitFrames" then return namespace end end,
      RegisterCallback = function(_, event, fn) callbacks[event] = fn end }, prdb = active, initialized = {} }
    w.skinnerCallbacks, w.skinnerNamespace, w.skinnerDefaults = callbacks, namespace, defaults
    return w, active, old
  end

  test("Skinner overlaps are off at login before its delayed skin passes", function()
    local w, p, old = Build()
    w.Fire("PLAYER_LOGIN")
    eq(p.CastingBar.skin, false)
    eq(p.CastingBar.glaze, false)
    eq(p.CompactFrames.skin, false)
    eq(p.CompactFrames.sbars, false)
    eq(p.Nameplates, false)
    for _, field in ipairs({ "skin", "glazesb", "altpowerbar", "actbtns", "extraab" }) do eq(p.MainMenuBar[field], false, field) end
    eq(p.WorldMap.skin, false)
    eq(p.WorldMap.size, 1.2, "map size preserved")
    eq(p.ChatEditBox.skin, false)
    eq(p.ChatEditBox.style, 3, "chat style preserved")
    eq(p.ChatButtons, false)
    eq(p.ChatBubbles.skin, false)
    eq(p.ChatConfig, false)
    eq(p.ChatFrames, false)
    eq(p.ChatTabs, false)
    eq(p.ChatTabsFade, false)
    eq(p.CombatLogQBF, false)
    eq(p.Minimap.skin, false)
    eq(p.Minimap.gloss, false)
    eq(p.MinimapButtons.skin, false)
    eq(p.MinimapButtons.style, false)
    eq(p.Tooltips.skin, false)
    eq(p.Tooltips.glazesb, false)
    eq(p.DisabledSkins.Details, true)
    eq(p.DisabledSkins["DetailsFramework-1.0 (Lib)"], true)
    eq(p.DisabledSkins.Auctionator, false)
    eq(p.MerchantFrame, true)
    eq(p.QuestFrame, true)
    eq(old.CastingBar.skin, false)
    eq(old.DisabledSkins.Details, true)
    eq(w.skinnerNamespace.profile.pet, false, "hunter/warlock defaults suppressed")
    eq(w.skinnerNamespace.profile.petlvl, false)
    eq(w.skinnerNamespace.profile.party, false)
    eq(SkinnerDB.namespaces.UnitFrames.profiles.Other.target, false)
    eq(#w.popups, 0)
  end)

  test("Skinner owner conditions preserve all settings when owners are absent", function()
    local w, p = Build(nil, {})
    w.Login()
    eq(p.WorldMap.skin, true)
    eq(p.ChatEditBox.skin, true)
    eq(p.CastingBar, nil)
    eq(p.DisabledSkins.Details, nil)
    eq(w.skinnerNamespace.profile.pet, true)
    eq(StatusOf(w.ns.Check(), "skinner.actionbars"), "inactive")
  end)

  test("Skinner rules defer in combat and require reload after skins were applied", function()
    local w, p = Build()
    w.combat = true
    w.Login()
    eq(p.ChatEditBox.skin, true)
    Skinner.initialized.ChatEditBox = true
    w.combat = false
    w.Fire("PLAYER_REGEN_ENABLED")
    eq(p.ChatEditBox.skin, false)
    local reload = false
    for _, line in ipairs(w.printed) do if line:find("/reload", 1, true) then reload = true end end
    eq(reload, true, "already applied skin needs reload")
    eq(#w.popups, 0)
  end)

  test("Skinner profile switches copies and resets enforce fresh profiles", function()
    local w = Build()
    w.Login()
    for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
      local fresh = { DisabledSkins = {}, WorldMap = { skin = true } }
      Skinner.db.profile = fresh
      SkinnerDB.profiles.Fresh = fresh
      w.skinnerNamespace.profile = { pet = true }
      ok(w.skinnerCallbacks[event], event .. " is watched")
      w.skinnerCallbacks[event]()
      w.RunTimers()
      eq(fresh.WorldMap.skin, false)
      eq(fresh.DisabledSkins.Details, true)
      eq(w.skinnerNamespace.profile.pet, false)
    end
    Skinner.db.profile.ChatButtons = true
    w.Tick()
    eq(Skinner.db.profile.ChatButtons, false, "direct option edits caught")
  end)

  test("Skinner missing database fails safely without modifying saved settings", function()
    local w, p = Build()
    Skinner.db = nil
    w.Login()
    eq(p.WorldMap.skin, true)
    eq(StatusOf(w.ns.Check(), "skinner.actionbars"), "blocked")
  end)

  test("installed Skinner AceDB defaults are guarded before login and after real profile resets", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = { Skinner = true, YUI = true,
      EllesmereUIUnitFrames = true, EllesmereUIRaidFrames = true, EllesmereUINameplates = true, Details = true },
      beforeGuard = function()
        strmatch = string.match
        strlenutf8 = string.len
        securecallfunction = function(fn, ...) return fn(...) end
        GetRealmName = function() return "Test Realm" end
        UnitName = function() return "Test Hunter" end
        UnitNameUnmodified = UnitName
        UnitClass = function() return "Hunter", "HUNTER" end
        UnitRace = function() return "Human", "Human" end
        UnitFactionGroup = function() return "Alliance" end
        GetLocale = function() return "zhTW" end
        GetCurrentRegion = function() return 1 end
        GetCurrentRegionName = function() return "US" end
        CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
        local root = ADDON_ROOT .. "../Skinner/"
        for _, file in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", "Libs/AceDB-3.0/AceDB-3.0.lua" }) do
          assert(loadfile(root .. file))()
        end
        local module = { SetEnabledState = function() end, IsEnabled = function() return false end }
        Skinner = { isFrvr = true, isMorF = true, uCls = "HUNTER", checkLoadable = function() return true end,
          NewModule = function() return module end, GetModule = function() return module end, initialized = {} }
        assert(loadfile(root .. "Core/Options.lua"))("Skinner", Skinner)
        Skinner:SetupDefaults()
        Skinner.prdb = Skinner.db.profile
        assert(loadfile(root .. "Modules/UnitFrames.lua"))("Skinner", Skinner)
        module:OnInitialize()
        eq(module.db.profile.pet, true, "upstream hunter default starts on")
      end })
    local p = Skinner.db.profile
    eq(p.CastingBar.skin, false, "before PLAYER_LOGIN")
    eq(Skinner.db:GetNamespace("UnitFrames").profile.pet, false, "before module enable")
    eq(p.DisabledSkins["DetailsFramework-1.0 (Lib)"], true)
    w.Login()
    Skinner.db:SetProfile("New profile")
    w.RunTimers()
    eq(Skinner.db.profile.WorldMap.skin, false)
    Skinner.db:ResetProfile()
    w.RunTimers()
    eq(Skinner.db.profile.ChatEditBox.skin, false)
    eq(Skinner.db:GetNamespace("UnitFrames").profile.pet, false)
  end)
end
