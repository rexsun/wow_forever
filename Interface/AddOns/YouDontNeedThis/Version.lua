-- You Don't Need This - "a newer version is out" notice
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.
--
-- Addons can't reach the internet, so the newest version is learned from other players: every copy
-- announces its version over hidden addon messages (guild on login, party/raid on joining a group)
-- and answers anyone running an older one. A newer version seen this way is remembered
-- account-wide (YDNT_Global.newestVersion), so the notice also shows at every login until you update.

local ADDON, ns = ...

local MSG_PREFIX = "YDNT"
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MY_VERSION = GetMetadata and GetMetadata(ADDON, "Version") or "0"

local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local SendAddonMsg = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if not (RegisterPrefix and SendAddonMsg) then return end
RegisterPrefix(MSG_PREFIX)

-- "0.10.2" vs "0.9" compared number by number. Returns <0, 0 or >0.
local function Compare(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x - y end
    end
    return 0
end

local warned = false
local function Warn(newest)
    if warned then return end
    warned = true
    local text = ("you're running version %s, but %s is out. Please update (CurseForge)."):format(MY_VERSION, newest)
    print(ns.PREFIX .. "|cffffd100" .. text .. "|r")
end

local function Send(channel)
    pcall(SendAddonMsg, MSG_PREFIX, "VER:" .. MY_VERSION, channel)
end

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end

-- Don't flood: at most one announcement per channel per minute.
local lastSent = {}
local function Announce(channel)
    if not channel then return end
    local now = GetTime()
    if lastSent[channel] and now - lastSent[channel] < 60 then return end
    lastSent[channel] = now
    Send(channel)
end

local me = UnitName("player")
local wasGrouped = false

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED") -- older clients
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if event == "PLAYER_LOGIN" then
        local g = ns.Global()
        if g.newestVersion and Compare(g.newestVersion, MY_VERSION) > 0 then
            C_Timer.After(8, function() Warn(g.newestVersion) end)
        else
            g.newestVersion = nil -- updated (or never saw a newer one)
        end
        C_Timer.After(15, function()
            if IsInGuild and IsInGuild() then Announce("GUILD") end
            Announce(GroupChannel())
            wasGrouped = GroupChannel() ~= nil
        end)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        -- Announce when we join a group, not on every roster change.
        local grouped = GroupChannel() ~= nil
        if grouped and not wasGrouped then C_Timer.After(3, function() Announce(GroupChannel()) end) end
        wasGrouped = grouped
    elseif event == "CHAT_MSG_ADDON" and prefix == MSG_PREFIX then
        if sender and Ambiguate and Ambiguate(sender, "none") == me then return end
        if sender == me then return end
        local theirs = text and text:match("^VER:(.+)$")
        if not theirs then return end
        local diff = Compare(theirs, MY_VERSION)
        if diff > 0 then
            local g = ns.Global()
            if not g.newestVersion or Compare(theirs, g.newestVersion) > 0 then g.newestVersion = theirs end
            Warn(g.newestVersion)
        elseif diff < 0 then
            Announce(channel) -- tell them a newer version exists
        end
    end
end)
