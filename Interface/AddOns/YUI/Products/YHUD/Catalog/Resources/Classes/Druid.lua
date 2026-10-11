local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

local FORM_ORDER = { "caster", "moonkin", "cat", "bear", "travel" }

local function Form(candidates, defaults)
    return {
        candidates = candidates,
        defaults = defaults,
    }
end

local function ResolveForm(formID, powerType)
    if formID == (_G.DRUID_CAT_FORM or 1) then return "cat" end
    if formID == (_G.DRUID_BEAR_FORM or 5) then return "bear" end
    if formID == (_G.DRUID_MOONKIN_FORM_1 or 31)
        or formID == (_G.DRUID_MOONKIN_FORM_2 or 35) then
        return "moonkin"
    end
    if formID == (_G.DRUID_TRAVEL_FORM or 3)
        or formID == (_G.DRUID_AQUATIC_FORM or 4)
        or formID == (_G.DRUID_FLIGHT_FORM or 27) then
        return "travel"
    end
    if formID == nil or formID == 0
        or formID == (_G.DRUID_TREE_FORM or 2) then
        return "caster"
    end
    if powerType == 3 then return "cat" end
    if powerType == 1 then return "bear" end
    return "caster"
end

Catalog:RegisterClassPack("DRUID", {
    [102] = { "mana", "rage", "lunarPower", "energy", "comboPoints" },
    [103] = { "mana", "rage", "energy", "comboPoints" },
    [104] = { "mana", "rage", "ironfur", "energy", "comboPoints" },
    [105] = { "mana", "rage", "energy", "comboPoints" },
}, {
    formOrder = FORM_ORDER,
    formNameKeys = {
        caster = "designer.resource.form.caster",
        moonkin = "designer.resource.form.moonkin",
        cat = "designer.resource.form.cat",
        bear = "designer.resource.form.bear",
        travel = "designer.resource.form.travel",
    },
    defaultFormBySpec = {
        [102] = "caster",
        [103] = "cat",
        [104] = "bear",
        [105] = "caster",
    },
    resolveForm = ResolveForm,
    specs = {
        [102] = {
            caster = Form({ "mana", "lunarPower" }, { "mana", "lunarPower" }),
            moonkin = Form({ "mana", "lunarPower" }, { "mana", "lunarPower" }),
            cat = Form({ "energy", "comboPoints", "mana" }, { "energy", "comboPoints" }),
            bear = Form({ "rage", "lunarPower", "mana" }, { "rage", "lunarPower" }),
            travel = Form({ "mana", "lunarPower" }, { "mana", "lunarPower" }),
        },
        [103] = {
            caster = Form({ "mana" }, { "mana" }),
            moonkin = Form({ "mana" }, { "mana" }),
            cat = Form({ "energy", "comboPoints", "mana" }, { "energy", "comboPoints" }),
            bear = Form({ "rage", "mana" }, { "rage" }),
            travel = Form({ "mana" }, { "mana" }),
        },
        [104] = {
            caster = Form({ "mana" }, { "mana" }),
            moonkin = Form({ "mana" }, { "mana" }),
            cat = Form({ "energy", "comboPoints", "mana" }, { "energy", "comboPoints" }),
            bear = Form({ "rage", "ironfur", "mana" }, { "rage", "ironfur" }),
            travel = Form({ "mana" }, { "mana" }),
        },
        [105] = {
            caster = Form({ "mana" }, { "mana" }),
            moonkin = Form({ "mana" }, { "mana" }),
            cat = Form({ "energy", "comboPoints", "mana" }, { "energy", "comboPoints" }),
            bear = Form({ "rage", "mana" }, { "rage" }),
            travel = Form({ "mana" }, { "mana" }),
        },
    },
})
