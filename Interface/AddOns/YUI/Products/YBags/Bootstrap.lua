local addonName, addonTable = ...
local bootstrap = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[addonName]
if bootstrap and not bootstrap.productEnabled then return end
local YUI = _G.YUI or addonTable
if not YUI or not (YUI.IsRetail or YUI.IsForever) then return end
local host = YUI.GetAddonProductId and YUI:GetAddonProductId(addonName, "suite") or YUI.ProductId or "suite"
if host ~= "suite" and host ~= "ybags" then return end
if YUI.YBags then return end

YUI.YBags = {
    PRODUCT_ID = "ybags", STORAGE_KEY = "YBags", SETTINGS_ENTRY = "ybags.settings",
    HOST_ID = host, ADDON_NAME = addonName, VERSION = "0.1.0", client = YUI.IsForever and "forever" or "mainline",
}
local B = YUI.YBags
B.toolbarActions={}
function B:RegisterToolbarAction(id,definition)
    if type(id)~="string" or type(definition)~="table" or type(definition.onClick)~="function" then return false end
    self.toolbarActions[id]=definition
    if self.View and self.View.windows.player then self.View:Toolbar(self.View.windows.player) end
    return true
end
function B:UnregisterToolbarAction(id)
    self.toolbarActions[id]=nil
    if self.View and self.View.windows.player then self.View:Toolbar(self.View.windows.player) end
end
function B:T(key)
    return YUI.Locale:Get("YBags")[key]
end
function B:Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = self:Copy(child) end
    return result
end
function B:Notify(key)
    if YUI.Print then YUI:Print(self:T(key)) end
end
function B:Plain(value,depth,seen,budget)
    depth,seen,budget=depth or 0,seen or {},budget or {left=20000}
    budget.left=budget.left-1
    if budget.left<0 or depth>12 then return nil,false end
    local kind=type(value)
    if kind=="number" then return value,value==value and value~=math.huge and value~=-math.huge end
    if kind=="string" then return value,#value<=131072 end
    if kind=="boolean" or kind=="nil" then return value,true end
    if kind~="table" or seen[value] or getmetatable(value) then return nil,false end
    seen[value]=true
    local result={}
    for key,child in pairs(value) do
        if type(key)~="string" and type(key)~="number" then return nil,false end
        local nextValue,ok=self:Plain(child,depth+1,seen,budget)
        if not ok then return nil,false end
        result[key]=nextValue
    end
    seen[value]=nil;return result,true
end
