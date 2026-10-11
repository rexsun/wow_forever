local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local function onInit(self, options)
    if (AddonCompartmentFrame and ns.SLASHCMD and options.AddonCompartmentFilter ~= false) then
        -- AddonCompartmentFrame, Since DF (10)
        AddonCompartmentFrame:RegisterAddon({
            text = ns.TITLE,
            icon = ns.ICON,
            notCheckable = true,
            func = _G[ns.SLASHCMD],
        })
    end
end
local module = ns.Module:new(onInit, "AddonCompartmentFilter");