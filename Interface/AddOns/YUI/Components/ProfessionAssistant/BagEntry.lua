local _, YUI = ...
if not YUI.IsForever then return end

local API, View = YUI.API.ProfessionAssistant, YUI.ProfessionAssistantView
local System, Security = YUI.API.System, YUI.API.Security
local Feature = { enabled = false, failures = 0 }
YUI.ProfessionAssistantBagEntry = Feature
local binding, open
local entries = setmetatable({}, { __mode = "k" })

local function IsOrdinary(frame)
    return frame and type(frame.IsForbidden) == "function" and Security.SafeBoolean(frame:IsForbidden()) == false
        and type(frame.IsProtected) == "function" and Security.SafeBoolean(frame:IsProtected()) == false
end

local function CanShow(frame, addon)
    return Feature.enabled and API.Known() and frame.id == "inventory"
        and frame:GetOwner() == addon.player and not frame:IsCached()
end

local function Click()
    if binding and Feature.enabled and not API.InCombat() then
        local frame = binding.addon.Frames:Get("inventory")
        if frame and CanShow(frame, binding.addon) then open() end
    end
end

local function AddEntry(frame, buttons, current)
    if API.InCombat() or not CanShow(frame, current.addon) or not IsOrdinary(frame) then return buttons end
    if type(buttons) ~= "table" then return buttons end
    local entry = entries[frame]
    if not entry then
        entry = View.Entry(frame, { click = Click, toolbar = true, template = "BagnonButtonTemplate" })
        entries[frame] = entry
    end
    View.PlaceEntry(entry, frame, true)
    -- 不修改原返回表：其他扩展可能复用自己的按钮列表。
    local result = {}
    for i, button in ipairs(buttons) do result[i] = button end
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
    local frame = previous.addon.Frames:Get("inventory")
    if IsOrdinary(frame) and frame:IsShown() then frame:Layout() end
end

function Feature:Refresh()
    if API.InCombat() then return end
    if not self.enabled then Detach(); return end
    if self.blockedReason or not (System and Security) or not System.IsAddOnLoaded("Bagnon") then return end
    if Security.SafeString(System.GetAddOnMetadata("Bagnon", "Version")) ~= "12.1.7" then
        self.blockedReason = "unsupported-version"; return
    end
    local addon = _G.Bagnon
    local class = addon and addon.Inventory
    if not (class and type(class.GetExtraButtons) == "function" and addon.player
        and addon.Frames and type(addon.Frames.Get) == "function") then return end
    if binding and (binding.addon ~= addon or binding.class ~= class
        or class.GetExtraButtons ~= binding.wrapper) then
        self.blockedReason = "changed-interface"; Detach(); return
    end
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
    local frame = addon.Frames:Get("inventory")
    if IsOrdinary(frame) and frame:IsShown() then frame:Layout() end
end

function Feature:Enable(callback)
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
