local YUI = _G.YUI
local Assistant = YUI and YUI.MailAssistant
if not Assistant then return end

local Compatibility = {}
Assistant.Compatibility = Compatibility
local watched = setmetatable({}, { __mode = "k" })
local sendSubjects = setmetatable({}, { __mode = "k" })

local function Loaded(name)
    local api = _G.C_AddOns
    return api and api.IsAddOnLoaded and api.IsAddOnLoaded(name)
        or _G.IsAddOnLoaded and _G.IsAddOnLoaded(name) or false
end

local function ModuleEnabled(addon, name)
    if not (addon and type(addon.GetModule) == "function") then return false end
    local ok, module = pcall(addon.GetModule, addon, name, true)
    if not (ok and module and type(module.IsEnabled) == "function") then return false end
    local enabledOK, enabled = pcall(module.IsEnabled, module)
    return enabledOK and enabled == true
end

function Compatibility:GetOwners()
    local inbox, contacts
    local postal = Loaded("Postal") and _G.Postal
    if postal then
        if ModuleEnabled(postal, "OpenAll") or ModuleEnabled(postal, "Select")
            or ModuleEnabled(postal, "Express") then inbox = "Postal" end
        if ModuleEnabled(postal, "BlackBook") then contacts = "Postal" end
    end
    local root = Loaded("NDui") and _G.NDui
    local provider = root and root[1]
    if provider and type(provider.GetModule) == "function" then
        local ok, module = pcall(provider.GetModule, provider, "Misc")
        -- Created controls remain installed until reload, even if the setting changed.
        if ok and module and module.GoldButton then inbox = inbox or "NDui" end
        if _G.NDuiMailBoxScrollFrame then contacts = contacts or "NDui" end
    end
    local addressBook = _G.EQOLMailboxFrame
    if addressBook and addressBook.IsShown and addressBook:IsShown() then
        contacts = contacts or "EnhanceQoL"
    end
    return inbox, contacts
end

function Compatibility:GetThemeStyle(style)
    if style ~= "auto" then return style end
    -- The shared appearance provider already resolves per-window opt-outs here.
    if Loaded("EllesmereUIBlizzardSkin") then return "auto" end
    local root = Loaded("ElvUI") and _G.ElvUI
    local engine = root and root[1]
    local skins = engine and engine.private and engine.private.skins
    local blizzard = skins and skins.blizzard
    if blizzard then
        return (blizzard.enable == false or blizzard.mail == false) and "native" or "auto"
    end
    local ndui = Loaded("NDui") and _G.NDui
    local config = ndui and ndui[2]
    local nativeSkins = config and config.db and config.db.Skins
    if nativeSkins and nativeSkins.BlizzardSkins == false then return "native" end
    return "auto"
end

function Compatibility:HasNativeInbox()
    return _G.MailFrame and _G.InboxFrame and _G.MailItem1
        and _G.MailItem1Button and type(_G.GetInboxHeaderInfo) == "function"
        and type(_G.TakeInboxItem) == "function" and type(_G.TakeInboxMoney) == "function"
        and _G.C_Mail and type(_G.C_Mail.IsCommandPending) == "function"
end

function Compatibility:GetInboxRefreshTarget()
    if _G.InboxFrame and type(_G.InboxFrame.Update) == "function" then
        return _G.InboxFrame, "Update"
    elseif type(_G.InboxFrame_Update) == "function" then
        return _G, "InboxFrame_Update"
    end
end

function Compatibility:LayoutSendSubject()
    local runtime, send = Assistant.runtime, _G.SendMailFrame
    local active = runtime.enabled and Assistant:GetConfiguration().contactsEnabled and send and send:IsShown()
        and Loaded("EllesmereUIBlizzardSkin")
    if active then local _, contactsOwner = self:GetOwners(); active = not contactsOwner end
    local appearance = YUI.GUI2.WindowAppearance
    local context = active and appearance:Resolve("auto", { blizzardWindow = "mail" })
    if not context or context.source ~= "ellesmere" then
        for field, state in pairs(sendSubjects) do
            if field:GetWidth() == state.applied then field:SetWidth(state.width) end
            sendSubjects[field] = nil
        end
        return
    end
    local field, mailbox = _G.SendMailSubjectEditBox, _G.MailFrame
    if not field or not mailbox or (field.IsProtected and field:IsProtected()) then return end
    local left, right = field:GetLeft(), mailbox:GetRight()
    if not left or not right then return end
    local fieldScale, mailScale = field:GetEffectiveScale(), mailbox:GetEffectiveScale()
    local edge = (right - 18) * mailScale
    local recipient = _G.SendMailNameEditBox
    local recipientRight = recipient and recipient.GetRight and recipient:GetRight()
    if recipientRight then edge = math.min(edge, recipientRight * recipient:GetEffectiveScale()) end
    local available = edge / fieldScale - left
    if available <= 0 then return end
    local width, state = field:GetWidth(), sendSubjects[field]
    if state and width ~= state.applied then sendSubjects[field], state = nil, nil end
    local original = state and state.width or width
    local wanted = math.min(original, available)
    if width ~= wanted then
        sendSubjects[field] = wanted < original and { width = original, applied = wanted } or nil
        field:SetWidth(wanted)
    end
end

local function Changed()
    local inbox = Assistant.Inbox
    if inbox and inbox.open then
        if inbox:Availability() and inbox.model:IsBusy() then inbox:Stop("conflict") end
        inbox:Schedule()
    end
    Assistant:ApplyPanelVisibility()
end

local function WatchMethods(object, first, second)
    if not object or watched[object] then return end
    watched[object] = true
    local security = YUI.API and YUI.API.Security
    if not (security and security.SafeHook) then return end
    if type(object[first]) == "function" then security.SafeHook("MailAssistant:OwnerEnabled", object, first, Changed) end
    if second and type(object[second]) == "function" then security.SafeHook("MailAssistant:OwnerDisabled", object, second, Changed) end
end

function Compatibility:EnsureHooks()
    local addon = Loaded("Postal") and _G.Postal
    if addon and type(addon.GetModule) == "function" then
        for _, name in ipairs({ "OpenAll", "Select", "Express", "BlackBook" }) do
            local ok, module = pcall(addon.GetModule, addon, name, true)
            if ok then WatchMethods(module, "OnEnable", "OnDisable") end
        end
    end
    local root = Loaded("NDui") and _G.NDui
    local provider = root and root[1]
    if provider and type(provider.GetModule) == "function" then
        local ok, module = pcall(provider.GetModule, provider, "Misc")
        if ok then WatchMethods(module, "MailBox") end
    end
    local frame = _G.EQOLMailboxFrame
    if frame and frame.HookScript and not watched[frame] then
        watched[frame] = true
        frame:HookScript("OnShow", Changed)
        frame:HookScript("OnHide", Changed)
    end
end
