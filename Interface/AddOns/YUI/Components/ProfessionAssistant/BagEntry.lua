local _, YUI = ...
if not YUI.IsForever then return end

local API, View = YUI.API.ProfessionAssistant, YUI.ProfessionAssistantView
local System, Security = YUI.API.System, YUI.API.Security
local Feature = { enabled = false, failures = 0 }
YUI.ProfessionAssistantBagEntry = Feature
local binding, open
local entries = setmetatable({}, { __mode = "k" })

local function IsOrdinary(frame)
    return (type(frame) == "table" or type(frame) == "userdata")
        and type(frame.IsForbidden) == "function" and Security.SafeBoolean(frame:IsForbidden()) == false
        and type(frame.IsProtected) == "function" and Security.SafeBoolean(frame:IsProtected()) == false
end

local function GetInventory(addon)
    local frames = addon.Frames
    if type(frames) == "table" and type(frames.Get) == "function" then return frames:Get("inventory") end
end

local function LayoutInventory(addon)
    local frame = GetInventory(addon)
    if IsOrdinary(frame) and type(frame.IsShown) == "function" and type(frame.Layout) == "function"
        and type(frame.GetExtraButtons) == "function"
        and frame:IsShown() then frame:Layout() end
end

local function CanShow(frame, addon)
    return Feature.enabled and API.Known() and IsOrdinary(frame) and frame.id == "inventory"
        and type(frame.GetOwner) == "function" and type(frame.IsCached) == "function"
        and frame:GetOwner() == addon.player and not frame:IsCached()
end

local function Click()
    if binding and Feature.enabled and not API.InCombat() then
        local frame = GetInventory(binding.addon)
        if CanShow(frame, binding.addon) then open() end
    end
end

local function AddEntry(frame, buttons, current)
    if API.InCombat() or not CanShow(frame, current.addon) then return buttons end
    assert(type(buttons) == "table", "extra buttons must be a table")
    local entry = entries[frame]
    if not entry then
        entry = View.Entry(frame, { click = Click, toolbar = true, template = "BagnonButtonTemplate" })
        entries[frame] = entry
    end
    View.PlaceEntry(entry, frame, true)
    -- 不修改原返回表：其他扩展可能复用自己的按钮列表。
    local result = {}
    for i, button in pairs(buttons) do result[i] = button end
    result[#result + 1] = entry
    return result
end

local function HideEntries()
    for _, entry in pairs(entries) do entry:Hide() end
end

local function Detach()
    local previous = binding
    binding = nil
    HideEntries()
    if not previous then return end
    if previous.class.GetExtraButtons == previous.wrapper then
        previous.class.GetExtraButtons = previous.original
    end
    LayoutInventory(previous.addon)
end

function Feature:Refresh()
    if API.InCombat() then return end
    if not self.enabled then Detach(); return end
    if self.blockedReason or not (System and Security) or not System.IsAddOnLoaded("Bagnon") then return end
    local addon = _G.Bagnon
    local class = type(addon) == "table" and addon.Inventory
    if binding and (binding.addon ~= addon or binding.class ~= class
        or class.GetExtraButtons ~= binding.wrapper) then
        self.blockedReason = "changed-interface"; Detach(); return
    end
    if not (type(class) == "table" and type(class.GetExtraButtons) == "function" and addon.player
        and type(addon.Frames) == "table" and type(addon.Frames.Get) == "function") then return end
    if not binding then
        local current = { addon = addon, class = class, original = class.GetExtraButtons }
        current.wrapper = function(frame, ...)
            local buttons = current.original(frame, ...)
            if binding ~= current or not Feature.enabled or Feature.blockedReason then return buttons end
            local ok, result = pcall(AddEntry, frame, buttons, current)
            if ok then return result end
            Feature.failures = Feature.failures + 1
            Feature.blockedReason = "entry-error"
            HideEntries()
            if class.GetExtraButtons == current.wrapper then class.GetExtraButtons = current.original end
            binding = nil
            return buttons
        end
        binding = current
        class.GetExtraButtons = current.wrapper
    end
    LayoutInventory(addon)
end

function Feature:Enable(callback)
    if not self.enabled then self.blockedReason = nil end
    self.enabled, open = true, callback
    self:Refresh()
end

function Feature:Disable()
    self.enabled, open = false, nil
    HideEntries()
    if not API.InCombat() then Detach() end
end

function Feature:GetStats()
    local count = 0
    for _ in pairs(entries) do count = count + 1 end
    return { attached = binding ~= nil, allocatedButtons = count, failures = self.failures,
        blockedReason = self.blockedReason, pending = not self.enabled and binding ~= nil }
end
