local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

-- Three configuration specializations per class; resource candidates remain client-specific.
Catalog:RegisterClassPack("WARRIOR", { [11650] = { "rage" }, [11657] = { "rage" }, [11670] = { "rage" } })
Catalog:RegisterClassPack("PALADIN", { [11486] = { "mana" }, [11541] = { "mana" }, [11559] = { "mana" } })
Catalog:RegisterClassPack("HUNTER", { [11372] = { "mana" }, [11371] = { "mana" }, [11370] = { "mana" } })
Catalog:RegisterClassPack("ROGUE", { [11580] = { "energy", "comboPoints" }, [11573] = { "energy", "comboPoints" }, [11572] = { "energy", "comboPoints" } })
Catalog:RegisterClassPack("PRIEST", { [11608] = { "mana" }, [11615] = { "mana" }, [11622] = { "mana" } })
Catalog:RegisterClassPack("SHAMAN", { [11326] = { "mana" }, [11363] = { "mana" }, [11362] = { "mana" } })
Catalog:RegisterClassPack("MAGE", { [11582] = { "mana" }, [11594] = { "mana" }, [11601] = { "mana" } })
Catalog:RegisterClassPack("WARLOCK", { [11629] = { "mana" }, [11636] = { "mana" }, [11637] = { "mana" } })

local function Form(candidates, defaults)
    return { candidates = candidates, defaults = defaults }
end

local function ResolveForm(formID, powerType)
    if formID == (_G.DRUID_CAT_FORM or 1) then return "cat" end
    if formID == (_G.DRUID_BEAR_FORM or 5) then return "bear" end
    if formID == (_G.DRUID_MOONKIN_FORM_1 or 31)
        or formID == (_G.DRUID_MOONKIN_FORM_2 or 35) then return "moonkin" end
    if formID == (_G.DRUID_TRAVEL_FORM or 3)
        or formID == (_G.DRUID_AQUATIC_FORM or 4) then return "travel" end
    if powerType == 3 then return "cat" end
    if powerType == 1 then return "bear" end
    return "caster"
end

local druidForms = {
    caster = Form({ "mana" }, { "mana" }),
    moonkin = Form({ "mana" }, { "mana" }),
    cat = Form({ "energy", "comboPoints", "mana" }, { "energy", "comboPoints" }),
    bear = Form({ "rage", "mana" }, { "rage" }),
    travel = Form({ "mana" }, { "mana" }),
}

Catalog:RegisterClassPack("DRUID", {
    [11328] = { "mana", "rage", "energy", "comboPoints" },
    [11347] = { "mana", "rage", "energy", "comboPoints" },
    [11340] = { "mana", "rage", "energy", "comboPoints" },
}, {
    formOrder = { "caster", "moonkin", "cat", "bear", "travel" },
    formNameKeys = {
        caster = "designer.resource.form.caster",
        moonkin = "designer.resource.form.moonkin",
        cat = "designer.resource.form.cat",
        bear = "designer.resource.form.bear",
        travel = "designer.resource.form.travel",
    },
    defaultFormBySpec = { [11328] = "moonkin", [11347] = "cat", [11340] = "caster" },
    resolveForm = ResolveForm,
    specs = { [11328] = druidForms, [11347] = druidForms, [11340] = druidForms },
})
