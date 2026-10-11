local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local Util = ns.Util or {}
local function T(text, ...)
    return Util.T and Util.T(text, ...) or text
end

SLASH_RAIDFRAMEAURAS1 = "/raidframeauras"
SLASH_RAIDFRAMEAURAS2 = "/rfa"
SlashCmdList.RAIDFRAMEAURAS = function(msg)
    msg = type(msg) == "string" and strtrim(msg):lower() or ""
    if msg == "debug" then
        RaidFrameAuras:SetOption("debugMode", not RaidFrameAuras:GetOption("debugMode"))
        Util.PrintMessage(T("debug") .. " " .. (RaidFrameAuras:GetOption("debugMode") and T("on") or T("off")))
    elseif msg == "perf" then
        RaidFrameAuras:SetOption("perfMode", not RaidFrameAuras:GetOption("perfMode"))
        Util.PrintMessage(T("perf") .. " " .. (RaidFrameAuras:GetOption("perfMode") and T("on") or T("off")))
    elseif msg == "scan" then
        RaidFrameAuras:InvalidateAuraData()
        RaidFrameAuras:RefreshFrames()
        Util.PrintMessage(T("scan refreshed aura data."))
    elseif msg == "toggle" then
        RaidFrameAuras:SetOption("enabled", not RaidFrameAuras:GetOption("enabled"))
        Util.PrintMessage(RaidFrameAuras:GetOption("enabled") and T("enabled") or T("disabled"))
    else
        if RaidFrameAuras.OpenOptions then
            RaidFrameAuras:OpenOptions()
        else
            Util.PrintMessage(T("Available commands: /rfa toggle, /rfa scan, /rfa debug, /rfa perf"))
        end
    end
end
