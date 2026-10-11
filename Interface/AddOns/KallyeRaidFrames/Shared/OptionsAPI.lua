local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

CONTROLTYPE_SLIDER = CONTROLTYPE_SLIDER or "slider"; -- removed since TWW (11)

function ns.SetGradientBg(frame, color)
    local texture = frame:CreateTexture()
    texture:SetAllPoints(true)
    texture:SetColorTexture(color.r, color.g, color.b, color.a)
    texture:SetGradient("VERTICAL", CreateColor(color.r, color.g, color.b, color.a), CreateColor(color.r*.5, color.g*.5, color.b*.5, color.a*.5))
end

--- SHARED API options management (default, load, save)
--- ! Useable only after ADDON_LOADED
function ns.SetDefaultOptions(DefaultOptions, reset)
	if reset or _G[ns.OPTIONS_NAME] == nil then
		_G[ns.OPTIONS_NAME] = CopyTable(DefaultOptions)
	else
        if ns.RemoveOldOptions then
            ns.RemoveOldOptions(_G[ns.OPTIONS_NAME])
        end
		foreach(DefaultOptions,
			function (optionName, defaultValue)
				if _G[ns.OPTIONS_NAME][optionName] == nil then
					_G[ns.OPTIONS_NAME][optionName] = defaultValue;
				end
			end
		);
	end
end

function ns.FindControl(ControlName)
	if ns.optionsFrame[ControlName] then
		return ns.optionsFrame[ControlName];
	else
		local i = 1
		while(ns.optionsFrame["Options"..i])
		do
			if (ns.optionsFrame["Options"..i][ControlName]) then
				return ns.optionsFrame["Options"..i][ControlName];
			end
			i=i+1;
		end
	end
end

--- Save the current options state, automatically matching the UI controls
--- ! Useable only after ADDON_LOADED
--- @param defaultOptions table Table containing the default options
--- @param ComputedReloadOptions function? Function that computes and returns the options (requiring reload) state as a string
function ns.SaveOptions(defaultOptions, ComputedReloadOptions)
    local LastComputedReloadOptions = ComputedReloadOptions ~= nil and ComputedReloadOptions() or nil;

    -- Auto detect options controls and save them
    foreach(defaultOptions,
        function (optionName, defaultValue)
            local optionsObject = ns.FindControl(optionName);
            if (optionsObject ~= nil) then
                local control = optionsObject;
                local previousValue = _G[ns.OPTIONS_NAME][optionName] or defaultValue;
                local value = nil;

                if control.type == "color" then
                    value = control:GetColor();
                elseif control.type == "dropdown" then
                    value = control:GetValue();
                elseif control.type == CONTROLTYPE_SLIDER then
                    value = control:GetValue();
                elseif type(previousValue) == "boolean" then
                    value = control:GetChecked();
                end
                if value == nil then
                    ns.AddMsgErr(format("Incorrect field value, loading default value for %s...", optionName));
                    value = defaultValue;
                end;
                _G[ns.OPTIONS_NAME][optionName] = value;
            end
        end
    );

    if ComputedReloadOptions ~= nil and ComputedReloadOptions() ~= LastComputedReloadOptions then
        ns.AddMsgWarn(format("%s: %s", ns.TITLE, l.OPTION_RELOAD_REQUIRED or ""), true);
    end

    -- OnSave: Modules
    foreach(ns.MODULES,
        function(_, module)
            module:OnSaveOptions(_G[ns.OPTIONS_NAME]);
        end
    );
end

function K_SHARED_UI.AddRefreshOptions(func)
    K_SHARED_UI.optionsRefreshFuncs = K_SHARED_UI.optionsRefreshFuncs or {}
    table.insert(K_SHARED_UI.optionsRefreshFuncs, func)
end
function K_SHARED_UI.RefreshOptions()
    local previewOptions = nil

    -- Get options for direct preview
    if ns.optionsFrame:IsVisible() then
        previewOptions = {}
        foreach(_G[ns.OPTIONS_NAME],
            function (optionName, defaultValue)
                local optionsObject = ns.FindControl(optionName);
                if (optionsObject ~= nil) then
                    local control = optionsObject;
                    local previousValue = _G[ns.OPTIONS_NAME][optionName] or defaultValue;
                    local value = nil;

                    if control.type == "color" then
                        value = control:GetColor();
                    elseif control.type == "dropdown" then
                        value = control:GetValue();
                    elseif control.type == CONTROLTYPE_SLIDER then
                        value = control:GetValue();
                    elseif type(previousValue) == "boolean" then
                        if (control.GetChecked) then
                        value = control:GetChecked();
                        end
                    end
                    previewOptions[optionName] = value;
                end
            end
        );
    end
    --

    foreach(K_SHARED_UI.optionsRefreshFuncs,
        function (_, func)
            func(previewOptions)
        end
    );
end

--- Refreshes UI based on the current options state
--- ! Useable only after ADDON_LOADED
--- @param defaultOptions table Table containing the default options
--- @param showOptionsFrame boolean? Optional Whether to show the options frame
--- @param limitToOptionsNames table? Optional table containing the names of options to limit to
function ns.RefreshOptions(defaultOptions, showOptionsFrame, limitToOptionsNames)
    ns.optionsFrame:SetShown(showOptionsFrame);
    -- Auto detect options controls and load them
    foreach(defaultOptions,
        function (optionName, defaultValue)
            if limitToOptionsNames ~= nil and not tContains(limitToOptionsNames, optionName) then
                return
            end
            local optionsObject = ns.FindControl(optionName);
            if (optionsObject ~= nil) then
                local control = optionsObject;
                local value = _G[ns.OPTIONS_NAME][optionName];
                if value == nil then
                    value = defaultValue;
                    ns.AddMsgErr(format("Option not found ("..l.YLD.."%s|r), loading default value...", optionName));
                end;

                if control.type == "color" then
                    control:SetColor(value);
                elseif control.type == "dropdown" then
                    control:SetValue(value);
                elseif control.type == CONTROLTYPE_SLIDER then
                    control:SetValue(value);
                elseif type(value) == "boolean" then
                    control:SetChecked(value);
                else
                    ns.AddMsgDebug(format("Type non prevu pour %s - %s, type de valeur: %s", optionName, control.type or "unknown", type(value)));
                end
            end
        end
    );
    K_SHARED_UI.RefreshOptions()
end


-- SHARED UI
function ns.OptionsEnable(FrameObject, isEnabled, disabledAlpha)
	if isEnabled then
		FrameObject:Enable();
		FrameObject:SetAlpha(1);
	else
		FrameObject:Disable();
		FrameObject:SetAlpha(disabledAlpha or .6);
	end
end
function ns.OptionsSetShownAndEnable(FrameObject, isShowned, isEnabled, disabledAlpha)
	FrameObject:SetShown(isShowned);
	if (isShowned) then
		ns.OptionsEnable(FrameObject, isEnabled, disabledAlpha);
	end
end

function ns.OptionsSiblingsEnable(options, sibling, isEnabled, alpha)
    local parent = sibling:GetParent()
    foreach(options,
        function (optionName, _)
            if parent[optionName] and parent[optionName] ~= sibling then
                ns.OptionsEnable(parent[optionName], isEnabled,  alpha)
            end
        end
    );
end

function ns.IsModuleEnabled(activeCheckbox, headingLabel, option, resize)
    if not activeCheckbox or not headingLabel then
        return true
    end
    if option == nil then
        activeCheckbox:Hide()
        K_SHARED_UI.HeadingWidget_SetPaddings(headingLabel, 5, 5)
        return true
    end
    local isEnabled = activeCheckbox:GetChecked()
    local parent = activeCheckbox:GetParent()
    if resize then
        parent._initialHeight = parent._initialHeight or parent:GetHeight()
        parent:SetClipsChildren(true)
        parent:SetHeight(isEnabled and parent._initialHeight or 40 , 5)
    elseif parent._initialHeight then
        parent:SetHeight(parent._initialHeight)
    end
    return isEnabled
end


--- Resets the specified options to their default values (and refreshes UI only for them)
--- @param optionNamesToReset table A list of option names to reset.
--- @param defaultOptions table  A table containing the default options.
--- @param optionsToForce table? An optional table containing options to force override
function ns.ResetOptions(optionNamesToReset, defaultOptions, optionsToForce)
	for _, optionName in ipairs(optionNamesToReset) do
		_G[ns.OPTIONS_NAME][optionName] = defaultOptions[optionName]
	end
	if optionsToForce then
        foreach(optionsToForce,
            function (optionName, overrideValue)
				_G[ns.OPTIONS_NAME][optionName] = overrideValue
			    table.insert(optionNamesToReset, optionName) -- in case of we forgot
			end
		)
	end
	ns.RefreshOptions(defaultOptions, true, optionNamesToReset)
end