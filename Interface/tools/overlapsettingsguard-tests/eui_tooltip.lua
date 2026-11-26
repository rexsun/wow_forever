return function(test, eq, ok, Stubs, CurrentLoaded, StatusOf, ChatContains)
  local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
  end

  local function Loaded(withYUI)
    local loaded = CurrentLoaded()
    loaded.EllesmereUI = true
    loaded.YUI = withYUI ~= false or nil
    return loaded
  end

  test("EllesmereUI item level on item tooltips is a rule owned by YUI", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    local rule
    for _, r in ipairs(w.ns.policy) do
      if r.id == "eui.itemleveltip" then rule = r end
    end
    ok(rule, "eui.itemleveltip")
    eq(rule.adapter, "EllesmereUI", "adapter")
    eq(rule.key, "ItemLevelTooltip", "key")
    eq(rule.when[1], "EllesmereUI", "watches EllesmereUI first")
    eq(rule.when[2], "YUI", "YUI owns item tooltips")
    eq(#w.ns.ValidatePolicy(w.ns.policy, w.ns.adapters), 0, "policy validates")
  end)

  test("EllesmereUI item level on item tooltips is switched off while YUI loads", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    EllesmereUIDB = { tooltipItemLevelItems = true, tooltipItemLevelItemsCompare = true, profiles = {} }
    w.Login()
    eq(EllesmereUIDB.tooltipItemLevelItems, false, "switched off")
    eq(EllesmereUIDB.tooltipItemLevelItemsCompare, true, "its cog options are kept")
    ok(ChatContains(w, "EllesmereUI: Item level on item tooltips"), "reported in chat")
    EllesmereUIDB.tooltipItemLevelItems = true
    w.Tick()
    eq(EllesmereUIDB.tooltipItemLevelItems, false, "switched off again after the options page turns it on")
  end)

  test("EllesmereUI item level rule is off without saved settings and inactive without YUI", function()
    local w = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded() })
    eq(StatusOf(w.ns.Check(), "eui.itemleveltip"), "off", "no EllesmereUIDB yet")
    local alone = Stubs.Fresh(ADDON_ROOT, { loaded = Loaded(false) })
    EllesmereUIDB = { tooltipItemLevelItems = true }
    alone.Login()
    eq(EllesmereUIDB.tooltipItemLevelItems, true, "kept without YUI")
    eq(StatusOf(alone.ns.Check(), "eui.itemleveltip"), "inactive")
  end)

  -- 9.9.5 adds the line on Forever only, off by default; YUI's Forever defaults already add one.
  test("EllesmereUI 9.9.5 and YUI both add item level to item tooltips", function()
    local addons = ADDON_ROOT .. "../"
    local eui = ReadFile(addons .. "EllesmereUI/EllesmereUI.lua")
    ok(eui:find("if not (db and db.tooltipItemLevelItems) then return end", 1, true),
      "EllesmereUI's tooltip hook reads its switch on every tooltip")
    ok(eui:find("TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemLevelTooltipHook)", 1, true),
      "EllesmereUI hooks item tooltips")
    ok(eui:find("if not (EllesmereUIDB and EllesmereUIDB.tooltipItemLevelItems) then return end", 1, true),
      "EllesmereUI registers the hook only when the switch is on")
    local options = ReadFile(addons .. "EllesmereUIOptions/EUI_BlizzardSkin_Options.lua")
    ok(options:find("EllesmereUIDB.tooltipItemLevelItems = v", 1, true), "the options page writes the root key")
    local yuiDefaults = ReadFile(addons .. "YUI/Core/Defaults_Forever.lua")
    ok(yuiDefaults:find("tooltipItemLevelEnabled = true,", 1, true), "YUI's item level line is on by default")
    local yuiTooltip = ReadFile(addons .. "YUI/Components/MouseEnhancement/ItemTooltip.lua")
    ok(yuiTooltip:find("db.tooltipItemLevelEnabled ~= false", 1, true), "YUI reads its own switch")
  end)
end
