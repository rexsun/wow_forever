--@ Class Module
local _, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

ns.MODULES = {};

local function noop() end;
ns.Module = {};
ns.Module.__index = ns.Module;
ns.Module.cacheOptions = {};

-- Constructeur pour les modules
function ns.Module:new(onInit, name, onEnterWorld)
	local instance = setmetatable({
		onInit = onInit or noop,
		onEnterWorld = onEnterWorld or nil,
		name = name or "Unnamed",
		onSaveOptions = noop,
		getInfo = noop,
		isLoaded = false
	}, ns.Module);

	table.insert(ns.MODULES, instance);
	return instance;
end

--#region Setters for callbacks
function ns.Module:SetOnSaveOptions(onSaveOptions)
	self.onSaveOptions = onSaveOptions or noop;
	return self;
end

function ns.Module:SetGetInfo(getInfo)
	self.getInfo = getInfo or noop;
	return self;
end
--#endregion

local function registerEnterWorld(self)
	if not self.onEnterWorld then
		return
	end
	local eventsFrame = CreateFrame("Frame", nil, UIParent)
	eventsFrame:SetScript("OnEvent",
		function(frame, event, ...)
			frame:UnregisterEvent("PLAYER_ENTERING_WORLD");
			if ns.AddMsgDebug then
				ns.AddMsgDebug(string.format("Enter world <%s> module...", self.name));
			end
			self.onEnterWorld(self, ns.Module.cacheOptions, ...);
		end
	);
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
end
--#region CalledByCore
function ns.Module:Init(options, ...)
	registerEnterWorld(self)
	if ns.AddMsgDebug then
		ns.AddMsgDebug(string.format("Loading <%s> module...", self.name));
	end
	ns.Module.cacheOptions = options or {};
	self.onInit(self, ns.Module.cacheOptions, ...);
	self.isLoaded = true;
	return self;
end

function ns.Module:OnSaveOptions(options, ...)
    if not self.isLoaded then
        ns.AddMsgWarn(l.INIT_FAILED)
        return
    end
    ns.Module.cacheOptions = options or ns.Module.cacheOptions;
    self.onSaveOptions(self, ns.Module.cacheOptions, ...)
end

-- Only if Standalone
function ns.Module:GetInfo(...)
    if not self.isLoaded then
        ns.AddMsgWarn(l.INIT_FAILED)
        return
    end
    self.getInfo(self, ...)
end

function ns.Module:Name()
	return self.name;
end

function ns.Module:IsLoaded()
	return self.isLoaded;
end

function ns.Module:GetCacheOptions()
	return ns.Module.cacheOptions;
end
--#endregion