local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B or not YUI.IsForever then return end

local G, A, Security = YUI.GUI2, YUI.API.Bags, YUI.API.Security
local unpack = unpack or table.unpack
local S = {}
B.GuildServices = S

local modes = {"items", "log", "moneylog", "info"}
local events = {
    "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY", "PLAYER_MONEY",
    "GUILDBANK_UPDATE_TABS", "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE",
    "GUILDBANKLOG_UPDATE", "GUILDBANK_UPDATE_TEXT", "GUILDBANK_TEXT_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED",
}

local function T(key) return B:T("guild.service." .. key) end
local function Live(w)
    return w and w.liveBank == "guild" and w.open and B.active and B.guildOpen and A.BankWindowShown("guild")
end
local function CanAct(w)
    return Live(w) and not A.InCombat() and not A.CursorBusy() and not B.Actions.queue and not B.Actions.nativeSort
end
local function Count() return A.GuildTabCount and A.GuildTabCount() end
local function Viewable(id)
    return id and GetGuildBankTabInfo and select(3, GetGuildBankTabInfo(id))
end
local function CanReadTabNote(id)
    local info = A.GuildTab(id)
    return info and info.view == true
end
local tabNoteRetryDelay = 5
local function PendingTabNote(note) return type(note) == "table" end
local function RequestTabNote(s, id, retry)
    local note = s.tabNotes[id]
    local now = GetTime()
    if PendingTabNote(note) and (not retry or now - note.requestedAt < tabNoteRetryDelay) then return end
    local request = {requestedAt = now, changed = PendingTabNote(note) and note.changed}
    s.tabNotes[id] = request
    if not pcall(QueryGuildBankText, id) and s.tabNotes[id] == request then s.tabNotes[id] = nil end
end

function S:ClearTabTooltip(w, owner)
    local s = w.guildServices
    local hover = s and s.tabTooltip
    if not hover or owner and hover.owner ~= owner then return end
    s.tabTooltip = nil
    if GameTooltip:IsOwned(hover.owner) then GameTooltip:Hide() end
end

function S:RefreshTabTooltip(w, opening)
    local s = w.guildServices
    local hover = s and s.tabTooltip
    if not hover then return end
    local owner, id = hover.owner, hover.page
    if not Live(w) or owner.page ~= id or not owner:IsShown() or not GameTooltip:IsOwned(owner)
        or not opening and GameTooltip.IsShown and not GameTooltip:IsShown() then
        self:ClearTabTooltip(w)
        return
    end
    local canRead = CanReadTabNote(id)
    if not canRead then s.tabNotes[id] = nil end
    local note = canRead and s.tabNotes[id]
    local detail = canRead and owner.detail or not canRead and B:T("bank.denied") or nil
    local description
    if canRead then
        if note == nil or PendingTabNote(note) then description = T("loading")
        elseif note == "" then description = T("emptyNote")
        else description = note end
    end
    local shouldRequest = canRead and (note == nil or PendingTabNote(note)) and (opening or not hover.canRead)
    local canEdit = canRead and CanEditGuildBankTabInfo and CanEditGuildBankTabInfo()
    hover.canRead = canRead
    if hover.title ~= owner.tooltip or hover.detail ~= detail or hover.description ~= description or hover.canEdit ~= canEdit then
        hover.title, hover.detail, hover.description = owner.tooltip, detail, description
        hover.canEdit = canEdit
        G.Tooltip:Show(owner, {
            anchor="ANCHOR_TOP", title=owner.tooltip,
            content=function(body)
                body:AddLine(description, "success")
                body:AddLine(detail, "secondary")
            end,
            actions=canEdit and {{button="RightButton", text=B:T("bank.guild_edit_hint"), textTone="heading"}} or nil,
        })
    end
    if shouldRequest then RequestTabNote(s, id, opening) end
end

function S:ShowTabTooltip(w, owner)
    if not Live(w) then return end
    w.guildServices.tabTooltip = {owner=owner, page=owner.page}
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    self:RefreshTabTooltip(w, true)
end

local function Leader() return IsGuildLeader and IsGuildLeader() end
local function TabLimit() return MAX_BUY_GUILDBANK_TABS or 6 end
local function Button(parent, text, callback)
    return B.Appearance:Button(parent, {text=text, width=math.max(48, B.Appearance:TextWidth(text, "label") + 20), onClick=callback})
end
local function FooterButton(parent, text, callback)
    -- GuildBankFrame DepositButton/WithdrawButton use this template at 100 x 21.
    local button = G:CreateButtonFrame(parent, {template="UIPanelButtonTemplate", width=100, height=21, onClick=callback})
    button:SetText(text)
    button.flat = G:CreatePanel(button, {surface="color.control.bg", border="color.border.default"})
    button.flat:SetAllPoints()
    button.flat:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    button.flat:EnableMouse(false)
    return button
end
local footerFonts = {}
local function FooterFont(name)
    local base = _G[name]
    if not base then return name end
    local file, size, flags = base:GetFont()
    if not file or not size then return base end
    local font = footerFonts[name]
    if not font then
        font = CreateFont("YBagsGuildFooter" .. name)
        footerFonts[name] = font
    end
    font:CopyFontObject(base)
    font:SetFont(file, math.max(1, size - 1), flags or "")
    return font
end

local function StyleFooterFont(button, native)
    local normal = FooterFont(native and "GameFontNormal" or "GameFontHighlight")
    button:SetNormalFontObject(normal)
    if button.SetHighlightFontObject then button:SetHighlightFontObject(FooterFont("GameFontHighlight")) end
    button:SetDisabledFontObject(FooterFont("GameFontDisable"))
    -- The template has its own FontString; fit the button using the final label size.
    local label = button.GetFontString and button:GetFontString()
    if label and type(normal) ~= "string" then
        local _, size = normal:GetFont()
        local file, labelSize, flags = label:GetFont()
        if file and size and labelSize ~= size then label:SetFont(file, size, flags) end
    end
end

local function StyleFooterButton(button, native)
    StyleFooterFont(button, native)
    button.Left:SetAlpha(native and 1 or 0)
    button.Middle:SetAlpha(native and 1 or 0)
    button.Right:SetAlpha(native and 1 or 0)
    button.flat:SetShown(not native)
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(native and 1 or .15)
        highlight:SetDesaturated(not native)
    end
    if button.FitToText then
        button:SetWidth(100)
        button.fitTextCanWidthDecrease = false
        button:FitToText()
    else
        button:SetWidth(math.max(100, B.Appearance:TextWidth(button:GetText(), "label") + 40))
    end
end
local function Label(parent, color)
    local label = G:CreateText(parent, "", 12, color or "color.text.primary")
    B.Appearance:Text(label, "label")
    return label
end
local function SetLabel(label, text)
    if (label:GetText() or "") ~= text then label:SetText(text) end
end
local function HideHint(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function ShowHint(owner)
    if not owner.detail then HideHint(owner); return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(owner.tooltip)
    GameTooltip:AddLine(owner.detail, 1, 1, 1, true)
    GameTooltip:Show()
end
local function AttachHint(button, title)
    button.tooltip = title
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnEnter", ShowHint)
    button:HookScript("OnLeave", HideHint)
    button:HookScript("OnHide", HideHint)
end
local function SetDetail(button, detail)
    if button.detail == detail then return end
    button.detail = detail
    if GameTooltip:IsOwned(button) then ShowHint(button) end
end
local function ModeTab(parent, mode, callback)
    local title = T(mode)
    local tab = G:CreateButtonFrame(parent, {width=math.ceil(B.Appearance:TextWidth(title, "label")) + 16, height=24})
    B.Appearance:CommandFeedback(tab)
    tab.label = Label(tab)
    tab.label:SetText(title)
    tab.label:SetPoint("CENTER")
    tab.active = G:CreateTexture(tab, "color.control.hover", "BACKGROUND")
    tab.active:SetAllPoints()
    tab.selected = G:CreateTexture(tab, "color.text.heading", "OVERLAY")
    tab.selected:SetHeight(2)
    tab.selected:SetPoint("BOTTOMLEFT", 1, 0)
    tab.selected:SetPoint("BOTTOMRIGHT", -1, 0)
    tab.underline = tab.selected
    AttachHint(tab, title)
    tab:SetScript("OnClick", callback)
    return tab
end

-- The auction row inherits the shared bottom-tab art. Use the registered
-- template (or its base) without loading the AH or the character addon.
local function NavigationTemplate()
    local frame = YUI.API.Frame
    if not (frame and frame.GetXMLTemplateInfo and PanelTemplates_TabResize
        and PanelTemplates_SelectTab and PanelTemplates_DeselectTab) then return end
    for _, name in ipairs({"AuctionTabTemplate", "AuctionHouseFrameTabTemplate",
            "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate"}) do
        if frame.GetXMLTemplateInfo(name) then return name end
    end
end

local nextTabID = 0
-- SharedXML and the LoD auction/character templates may have different load
-- orders. These are the original CharacterFrameTemplates.xml tab slices.
local function StandaloneAuctionTab(parent, mode, callback)
    local tab = G:CreateButtonFrame(parent, {height=32, clicks="LeftButtonUp", onClick=callback})
    AttachHint(tab, T(mode))
    tab:SetNormalFontObject("GameFontNormalSmall")
    tab:SetDisabledFontObject("GameFontHighlightSmall")
    if tab.SetHighlightFontObject then tab:SetHighlightFontObject("GameFontHighlightSmall") end
    if mode == "permissions" then StyleFooterFont(tab, true) end
    local title = T(mode)
    tab:SetText(title)
    local label = tab.GetFontString and tab:GetFontString()
    local textWidth = label and label:GetStringWidth()
    if not textWidth or textWidth <= 0 then textWidth = B.Appearance:TextWidth(title, "label") end
    tab:SetWidth(math.max(42, math.ceil(textWidth) + 32))
    local function Slices(selected)
        local file = "Interface\\PaperDollInfoFrame\\UI-Character-" .. (selected and "ActiveTab" or "InActiveTab")
        local height, bottom = selected and 35 or 32, selected and .546875 or 1
        local art, y = {}, selected and 0 or -1
        for i = 1, 3 do
            local t = G:CreateTexture(tab, nil, "BACKGROUND")
            t:SetTexture(file)
            t:SetHeight(height)
            if i == 2 then
                t:SetPoint("TOPLEFT", 20, y)
                t:SetPoint("TOPRIGHT", -20, y)
                t:SetTexCoord(.15625, .84375, 0, bottom)
            else
                t:SetWidth(20)
                t:SetPoint(i == 1 and "TOPLEFT" or "TOPRIGHT", 0, y)
                t:SetTexCoord(i == 1 and 0 or .84375, i == 1 and .15625 or 1, 0, bottom)
            end
            t:SetShown(not selected)
            art[i] = t
        end
        return art
    end
    tab.inactiveArt, tab.selectedArt = Slices(false), Slices(true)
    tab.classicCaps = true
    tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-RealHighlight", "ADD")
    return tab
end

local function AuctionModeTab(parent, template, mode, callback)
    if not template then return StandaloneAuctionTab(parent, mode, callback) end
    nextTabID = nextTabID + 1
    local name = "YBagsGuildModeTab" .. nextTabID
    local tab = G:CreateButtonFrame(parent, {name=name, template=template, clicks="LeftButtonUp"})
    tab:UnregisterAllEvents()
    tab:SetScript("OnEvent", nil)
    tab:SetScript("OnShow", nil)
    tab:SetScript("OnLeave", nil)
    tab:SetScript("OnClick", callback)
    -- Classic XML names its slices globally. The shared panel functions use
    -- parent keys, with Active named Disabled in the older artwork.
    tab.Text = tab.Text or tab:GetFontString()
    for _, side in ipairs({"Left", "Middle", "Right"}) do
        tab[side] = tab[side] or _G[name .. side]
        local active = tab[side .. "Active"] or tab[side .. "Disabled"] or _G[name .. side .. "Disabled"]
        tab[side .. "Active"], tab[side .. "Disabled"] = active, active
    end
    tab:SetText(T(mode))
    AttachHint(tab, T(mode))
    if mode == "permissions" then StyleFooterFont(tab, true) end
    PanelTemplates_TabResize(tab, 0)
    -- Named Classic caps chain left to right; unlike PanelTab's atlases the
    -- middle slices have explicit XML widths rather than two stretch anchors.
    if _G[name .. "MiddleDisabled"] then
        tab.classicCaps = true
        -- The inherited hover texture starts five units above the classic
        -- button. Keep hover inside the same seam as the base artwork.
        local highlight = tab:GetHighlightTexture()
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetPoint("TOPLEFT", 3, -1)
            highlight:SetPoint("BOTTOMRIGHT", -3, 0)
        end
        for _, suffix in ipairs({"", "Active"}) do
            tab["Middle" .. suffix]:SetWidth(math.max(1, tab:GetWidth()
                - tab["Left" .. suffix]:GetWidth() - tab["Right" .. suffix]:GetWidth()))
        end
    end
    tab.auctionArt = true
    return tab
end
local function Money()
    local balance = GetGuildBankMoney and GetGuildBankMoney()
    local allowance = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    local permitted = CanWithdrawGuildBankMoney and CanWithdrawGuildBankMoney()
    if not permitted then allowance = 0 end
    if balance and allowance and allowance >= 0 then allowance = math.min(balance, allowance) end
    return balance, allowance, permitted
end
function S:CanBuy(w)
    local count = Count()
    return Live(w) and Leader() and count ~= nil and count < TabLimit() or false
end

local function ClearLocation(w)
    if B.GuildInventory then B.GuildInventory:Clear(w) end
    B.BankView:CancelGuildSplit()
    if B.View.menu then B.View.menu:Hide() end
end

local function SetMode(w, mode)
    if not CanAct(w) then return end
    if mode == "purchase" and not S:CanBuy(w) then return end
    if mode == "log" or mode == "info" then
        local page = w.page
        if not Viewable(page) then
            page = A.CurrentGuildTab()
            if not Viewable(page) then
                page = nil
                for _, tab in ipairs(A.GuildTabs()) do
                    if tab.view then page = tab.id; break end
                end
            end
        end
        if not page then return end
        if w.page ~= page or A.CurrentGuildTab() ~= page then
            if not B.BankView:Select(w, page) then return end
        end
    end
    if mode ~= w.guildMode then
        S:ClearTabTooltip(w)
        ClearLocation(w)
        w.guildMode = mode
        w.scroll:SetVerticalScroll(0)
        B.View:Layout(w, true)
    end
end

function S:OpenPurchase(w) SetMode(w, "purchase") end

function S:IsMouseOverNavigation(w)
    local s = w.guildServices
    local row = s and s.auctionRow
    if not row or row ~= s.row or not row:IsVisible() then return false end
    for _, mode in ipairs(modes) do
        local tab = row.buttons[mode]
        if tab:IsShown() and tab:IsMouseOver() then return true end
    end
    return row.manage:IsShown() and row.manage:IsMouseOver()
end

-- Reuse the game's money inputs, denomination reset, displayed cost and native
-- accept handlers. Only our copies validate the specific session/quote at accept.
local dialogKeys = {buy="CONFIRM_BUY_GUILDBANK_TAB", deposit="GUILDBANK_DEPOSIT", withdraw="GUILDBANK_WITHDRAW"}
local function DialogKey(kind) return "YBAGS_" .. dialogKeys[kind] end
local function CancelTimer(state, key)
    if state[key] then
        state[key]:Cancel()
        state[key] = nil
        B.Stats.timers = math.max(0, B.Stats.timers - 1)
    end
end
local function After(state, key, delay, callback)
    CancelTimer(state, key)
    B.Stats.timers = B.Stats.timers + 1
    state[key] = C_Timer.NewTimer(delay, function()
        state[key] = nil
        B.Stats.timers = math.max(0, B.Stats.timers - 1)
        callback()
    end)
end
local function StopPurchase(s)
    local target = s.purchaseTarget
    if target and B.Deposit.purchaseIntent == target then
        B.Deposit.purchaseIntent, B.Deposit.purchaseDeadline = nil, nil
    end
    s.purchaseTarget = nil
    CancelTimer(s, "purchaseTimer")
end
local function AcceptDialog(dialog, request)
    if not request or request.used then return end
    local w, kind = request.window, request.kind
    local s = w.guildServices
    if not s or s.dialog ~= request or not CanAct(w) or B.Cache.guildKey ~= request.guild then return end
    local balance, available = Money()
    if kind == "buy" then
        if s.purchaseTarget or not S:CanBuy(w) or s.bodyMode ~= "purchase" or Count() ~= request.count
            or GetGuildBankTabCost() ~= request.price or not balance or balance < request.price then
            B:Notify("guild.service.changed")
            return
        end
        local target = request.count + 1
        if not B.Deposit:ExpectGuildPurchase(target) then
            B:Notify("guild.service.changed")
            return
        end
        s.purchaseTarget = target
        After(s, "purchaseTimer", 10, function()
            if Live(w) and S:EnterPurchased(w) then return end
            StopPurchase(s)
            if Live(w) then
                B:Notify("guild.service.changed")
                B.View:Layout(w, true)
            end
        end)
    else
        local copper = MoneyInputFrame_GetCopper(dialog.MoneyInputFrame)
        local limit = kind == "deposit" and GetMoney() or available
        if kind == "withdraw" and limit and limit < 0 then limit = balance end
        if not copper or copper <= 0 or not limit or copper > limit then
            B:Notify("guild.service.invalidAmount")
            return true
        end
    end
    request.used = true
    local ok = pcall(StaticPopupDialogs[dialogKeys[kind]].OnAccept, dialog, request)
    if not ok then
        if kind == "buy" then StopPurchase(s) end
        B:Notify("guild.service.changed")
    end
    if kind == "buy" and Live(w) then S:UpdateMoney(w) end
end
local function OpenDialog(w, kind)
    if not CanAct(w) or not StaticPopupDialogs or not StaticPopup_Show then return end
    local s = w.guildServices
    local balance, available = Money()
    local request = {window=w, kind=kind, guild=B.Cache.guildKey}
    if kind == "buy" then
        if not S:CanBuy(w) or s.purchaseTarget or s.bodyMode ~= "purchase" then return end
        request.count, request.price = Count(), GetGuildBankTabCost()
        if not request.price or not balance or balance < request.price then return end
    elseif kind == "withdraw" and (not balance or balance <= 0 or not available or available == 0) then
        return
    end
    local key, native = DialogKey(kind), StaticPopupDialogs[dialogKeys[kind]]
    if not native then return end
    if not StaticPopupDialogs[key] then
        local definition = {}
        for field, value in pairs(native) do definition[field] = value end
        definition.OnAccept = AcceptDialog
        definition.OnHide = function(dialog, data)
            if native.OnHide then native.OnHide(dialog, data) end
            local owner = data and data.window and data.window.guildServices
            if owner and owner.dialog == data then owner.dialog = nil end
        end
        if native.hasMoneyInputFrame then
            definition.EditBoxOnEnterPressed = function(edit, data)
                local dialog = edit:GetParent():GetParent()
                if not AcceptDialog(dialog, data or dialog.data) then dialog:Hide() end
            end
        end
        StaticPopupDialogs[key] = definition
    end
    if s.dialog then StaticPopup_Hide(DialogKey(s.dialog.kind)) end
    s.dialog = request
    if not StaticPopup_Show(key, nil, nil, request) then s.dialog = nil end
end

function S:EnterPurchased(w)
    local s = w.guildServices
    local target = s.purchaseTarget
    if not target or (Count() or 0) < target then return false end
    if not CanAct(w) or not Viewable(target) then return false end
    B.Deposit:UpdateGuildAccess()
    -- A confirmed page may still be inaccessible to the current selection for
    -- one refresh. Keep its request until Select actually accepts it.
    local oldMode = w.guildMode
    w.guildMode = "items"
    if not B.BankView:Select(w, target) then
        w.guildMode = oldMode
        return false
    end
    StopPurchase(s)
    return true
end

function S:EditTab(w, id)
    if not CanAct(w) or not Viewable(id) or not CanEditGuildBankTabInfo or not CanEditGuildBankTabInfo() then return end
    local popup = GuildBankPopupFrame
    if not popup or not IconSelectorPopupFrameModes or popup:IsProtected() or popup:IsForbidden() then return end
    if popup:IsShown() then popup:Hide() end
    if w.page ~= id or A.CurrentGuildTab() ~= id or w.guildMode == "purchase" then
        if not B.BankView:Select(w, id) then return end
    end
    if id ~= A.CurrentGuildTab() then return end
    -- The native popup inherits alpha and an off-screen anchor from the parked
    -- bank. Its own OnShow/Okay/OnHide still own the provider, input and write.
    if S.hookedPopup ~= popup then
        popup:HookScript("OnHide", function(frame)
            local loan = S.iconLoan
            if not loan or loan.frame ~= frame then return end
            S.iconLoan = nil
            frame:SetParent(loan.parent)
            frame:SetFrameStrata(loan.strata)
            frame:SetFrameLevel(loan.level)
            frame:ClearAllPoints()
            for _, point in ipairs(loan.points) do frame:SetPoint(unpack(point, 1, 5)) end
        end)
        S.hookedPopup = popup
    end
    local loan = {frame=popup, window=w, tab=id, mode=w.guildMode, parent=popup:GetParent(), strata=popup:GetFrameStrata(),
        level=popup:GetFrameLevel(), points={}}
    for i = 1, popup:GetNumPoints() do loan.points[i] = {popup:GetPoint(i)} end
    S.iconLoan = loan
    popup:SetParent(w.root)
    popup:SetFrameStrata("DIALOG")
    popup.mode = IconSelectorPopupFrameModes.Edit
    popup:Show()
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", w.root)
end

local function Manage(w)
    if not CanAct(w) or not Leader() then return end
    local frame, modes = CommunitiesFrame, COMMUNITIES_FRAME_DISPLAY_MODES
    local club = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    -- Blizzard_Communities depends on GuildControlUI. Never initiate either addon's
    -- first load here: GuildControlUI_OnLoad calls the protected GuildControlSetRank.
    if not (frame and GuildControlUI and club and modes and modes.ROSTER and frame.SetDisplayMode
        and frame.SelectClub and frame.GetSelectedClubId and frame.GetDisplayMode)
        or (C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("useClassicGuildUI")) then
        B:Notify("guild.service.permissionRoute")
        return
    end
    if not frame:IsShown() and ToggleGuildFrame then ToggleGuildFrame() end
    if frame:IsShown() then
        if frame:GetSelectedClubId() ~= club then frame:SelectClub(club) end
        if frame:GetSelectedClubId() == club then
            if modes.MINIMIZED and frame:GetDisplayMode() == modes.MINIMIZED then
                local maximize = frame.MaximizeMinimizeFrame and frame.MaximizeMinimizeFrame.MaximizeButton
                if maximize then maximize:Click() end
            end
            frame:SetDisplayMode(modes.ROSTER)
            local control = frame.CommunitiesControlFrame
            if control and control.GuildControlButton and control.GuildControlButton:IsVisible() then
                B:Notify("guild.service.permissionNext")
                return
            end
        end
    end
    B:Notify("guild.service.permissionRoute")
end

local function PageName(id)
    if id then
        local name = GetGuildBankTabInfo(id)
        if name and name ~= "" then return (name:gsub("|", "||")) end
    end
    return string.format(B:T("bank.page"), id or 0)
end

local function Actor(name)
    return NORMAL_FONT_COLOR_CODE .. (name or UNKNOWN):gsub("|", "||") .. FONT_COLOR_CODE_CLOSE
end
local function ItemLine(tab, index)
    local kind, name, link, quantity, from, to, y, m, d, h = GetGuildBankTransaction(tab, index)
    if not link then return end
    local line
    if kind == "move" then
        line = GUILDBANK_MOVE_FORMAT:format(Actor(name), link, quantity or 1, PageName(from), PageName(to))
    elseif kind == "deposit" or kind == "withdraw" then
        local pattern = kind == "deposit" and GUILDBANK_DEPOSIT_FORMAT or GUILDBANK_WITHDRAW_FORMAT
        line = pattern:format(Actor(name), link)
        if quantity and quantity > 1 then line = line .. GUILDBANK_LOG_QUANTITY:format(quantity) end
    end
    return line, y, m, d, h
end
local moneyFormats = {
    deposit="GUILDBANK_DEPOSIT_MONEY_FORMAT", withdraw="GUILDBANK_WITHDRAW_MONEY_FORMAT",
    repair="GUILDBANK_REPAIR_MONEY_FORMAT", withdrawForTab="GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT",
    buyTab="GUILDBANK_BUYTAB_MONEY_FORMAT", buyRename="GUILDBANK_GUILD_RENAME_PURCHASE",
    refundRename="GUILDBANK_GUILD_RENAME_REFUND",
}
local function MoneyLine(index)
    local kind, name, amount, y, m, d, h = GetGuildBankMoneyTransaction(index)
    local money = GetDenominationsFromCopper(amount or 0)
    local line
    if kind == "buyTab" and (amount or 0) == 0 then
        line = GUILDBANK_UNLOCKTAB_FORMAT:format(Actor(name))
    elseif kind == "depositSummary" then
        line = GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT:format(money)
    elseif moneyFormats[kind] then
        line = _G[moneyFormats[kind]]:format(Actor(name), money)
    end
    return line, y, m, d, h
end

local function MakeLog(s)
    local f = G:CreateFrame(s.body, {type="ScrollingMessageFrame", template="InlineHyperlinkFrameTemplate"})
    f:SetPoint("TOPLEFT", 10, -35)
    f:SetPoint("BOTTOMRIGHT", -24, 8)
    f:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP)
    f:SetMaxLines(128)
    f:SetFading(false)
    f:SetFontObject(ChatFontNormal)
    f:SetJustifyH("LEFT")
    if f.SetSpacing then f:SetSpacing(3) end
    f.constrainRangeToText = true
    local bar = G:CreateFrame(s.body, {type="EventFrame", template="MinimalScrollBar"})
    bar:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 4, 0)
    ScrollUtil.InitScrollingMessageFrameWithScrollBar(f, bar)
    s.log, s.logBar = f, bar
end
local function ReadLog(w, updated)
    local s = w.guildServices
    local isMoney = s.bodyMode == "moneylog"
    if not isMoney and (s.bodyMode ~= "log" or not Viewable(w.page)) then return end
    local n
    if isMoney then n = GetNumGuildBankMoneyTransactions() else n = GetNumGuildBankTransactions(w.page) end
    local log = s.log
    local offset = log:GetScrollOffset()
    log:Clear()
    local shown = 0
    for i = 1, n or 0 do
        local line, y, m, d, h
        if isMoney then line, y, m, d, h = MoneyLine(i)
        else line, y, m, d, h = ItemLine(w.page, i) end
        if line then
            if y and m and d and h then line = line .. GUILD_BANK_LOG_TIME:format(TimeUtil.GetRecentTimeDate(y, m, d, h)) end
            log:AddMessage(line)
            shown = shown + 1
        end
    end
    if offset > 0 and shown > 0 then log:SetScrollOffset(math.min(offset, shown - 1)) end
    local known = shown > 0 or updated and n ~= nil
    SetLabel(s.meta, known and T("logCount"):format(shown) or "")
    SetLabel(s.notice, shown == 0 and T(known and "emptyLog" or "loading") or "")
end

local function CanEditNote(w)
    return w.guildMode == "info" and Viewable(w.page) and w.page == A.CurrentGuildTab()
        and CanEditGuildTabInfo and CanEditGuildTabInfo(w.page)
end
local function NoteControls(w)
    local s = w.guildServices
    local permission = CanEditNote(w)
    local canEdit = CanAct(w) and permission and s.noteReady and s.noteBase ~= nil
    local changed = s.noteBase ~= nil and s.edit:GetText() ~= s.noteBase
    s.edit:EnableMouse(canEdit and not s.saving or false)
    s.edit:EnableKeyboard(canEdit and not s.saving or false)
    if not canEdit or s.saving then s.edit:ClearFocus() end
    s.save:SetShown(canEdit == true)
    s.cancel:SetShown(canEdit == true)
    s.save:SetEnabled(changed and not s.saving and not s.conflict)
    s.cancel:SetEnabled(changed and not s.saving)
    s.noteStatus:SetText(s.saving and T("saving") or s.conflict and T("conflict") or "")
    if s.bodyMode == "info" then
        local hasText = s.edit:GetText() ~= ""
        if s.noteReady then
            SetLabel(s.meta, T(permission and "editable" or "readOnly"))
            local hint = canEdit and not s.saving and "writeNote" or "emptyNote"
            SetLabel(s.notice, not hasText and not changed and not s.saving and T(hint) or "")
        else
            SetLabel(s.meta, hasText and T("loading") or "")
            SetLabel(s.notice, hasText and "" or T("loading"))
        end
    end
end

local function SetNote(w, text)
    local s = w.guildServices
    s.noteBase, s.saving, s.conflict = text, nil, nil
    CancelTimer(s, "saveTimer")
    if s.edit:GetText() ~= (text or "") then s.edit:SetText(text or "") end
    NoteControls(w)
end
local function ReadNote(w, confirmed)
    local s = w.guildServices
    if s.bodyMode ~= "info" or not Viewable(w.page) or A.CurrentGuildTab() ~= w.page then return end
    local text = GetGuildBankText(w.page)
    if text == nil and not confirmed then return end
    if confirmed then s.noteReady = true end
    text = text or ""
    if not CanEditNote(w) or s.noteBase == nil or s.edit:GetText() == text or s.edit:GetText() == s.noteBase then
        SetNote(w, text)
    else
        s.conflict = text ~= s.noteBase
        NoteControls(w)
    end
end
local function SaveNote(w)
    local s = w.guildServices
    if not CanAct(w) or not CanEditNote(w) or not s.noteReady or s.noteBase == nil or s.conflict or s.saving then return end
    local text = s.edit:GetText()
    if text == s.noteBase then return end
    if (GetGuildBankText(w.page) or "") ~= s.noteBase then
        s.conflict = true
        NoteControls(w)
        return
    end
    s.saving = text
    After(s, "saveTimer", 8, function()
        s.saving = nil
        if Live(w) and s.bodyMode == "info" then
            ReadNote(w, true)
            if s.edit:GetText() ~= s.noteBase then B:Notify("guild.service.changed") end
        end
    end)
    NoteControls(w)
    SetGuildBankText(w.page, text)
end

local function MakeNote(w)
    local s = w.guildServices
    local scroll = G:CreateScrollFrame(s.body, {child=false})
    scroll:SetPoint("TOPLEFT", 8, -35)
    scroll:SetPoint("BOTTOMRIGHT", -27, 35)
    local edit = G:CreateFrame(scroll, {type="EditBox", height=1, width=1})
    edit:SetAutoFocus(false)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(500)
    edit:SetFontObject(GameFontHighlight)
    edit:SetJustifyH("LEFT")
    edit:SetTextInsets(2, 2, 2, 2)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnMouseDown", function()
        if CanAct(w) and CanEditNote(w) and s.noteReady and not s.saving then edit:SetFocus() end
    end)
    scroll:HookScript("OnSizeChanged", function(_, width, height)
        edit:SetWidth(math.max(1, width))
        edit:SetHeight(math.max(1, height))
    end)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top = -y
        if top < scroll:GetVerticalScroll() then scroll:SetVerticalScroll(math.max(0, top))
        elseif top + height > scroll:GetVerticalScroll() + scroll:GetHeight() then
            scroll:SetVerticalScroll(math.max(0, top + height - scroll:GetHeight()))
        end
    end)
    edit:SetScript("OnTextChanged", function(_, user)
        if user then NoteControls(w) end
    end)
    s.note, s.edit = scroll, edit
    s.save = Button(s.body, T("save"), function() SaveNote(w) end)
    s.save:SetPoint("BOTTOMLEFT", 6, 4)
    s.cancel = Button(s.body, B:T("action.cancel"), function()
        if CanAct(w) and CanEditNote(w) then SetNote(w, GetGuildBankText(w.page) or "") end
    end)
    s.cancel:SetPoint("LEFT", s.save, "RIGHT", 4, 0)
    s.noteStatus = Label(s.body, "color.text.secondary")
    s.noteStatus:SetPoint("LEFT", s.cancel, "RIGHT", 6, 0)
    s.noteStatus:SetPoint("RIGHT", s.body, "RIGHT", -4, 0)
    s.noteStatus:SetJustifyH("LEFT")
end

local function FooterAmount(copper)
    if not copper then return "—" end
    if copper <= 100 * 10000 then return A.MoneyText(copper) end
    local gold = math.floor(copper / 10000)
    return (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold))
        .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12|t"
end

function S:UpdateMoney(w)
    local s = w.guildServices
    local balance, available, permitted = Money()
    if s.balanceValue ~= balance or s.balance:GetText() == "" then
        s.balanceValue = balance
        s.balance:SetText(T("balance"):format(FooterAmount(balance)))
    end
    if s.availableValue ~= available or s.available:GetText() == "" then
        s.availableValue = available
        local text = available and available < 0 and T("unlimited") or FooterAmount(available)
        s.available:SetText(T("available"):format(text))
    end
    local act = CanAct(w)
    local blocked
    if not act then blocked = A.InCombat() and T("inCombat") or B:T("bank.transfer_busy") end
    local wallet = GetMoney and GetMoney()
    local depositHint = blocked
    if not depositHint and (not wallet or wallet <= 0) then depositHint = wallet and T("emptyWallet") or T("loading") end
    SetDetail(s.deposit, depositHint)
    s.deposit:SetEnabled(not depositHint)
    local withdrawHint = blocked
    if not withdrawHint then
        if not permitted then withdrawHint = T("withdrawDenied")
        elseif not balance or not available then withdrawHint = T("loading")
        elseif balance <= 0 then withdrawHint = T("emptyVault")
        elseif available == 0 then withdrawHint = T("quotaUsed") end
    end
    SetDetail(s.withdraw, withdrawHint)
    s.withdraw:SetEnabled(not withdrawHint)
    s.manage:SetShown(Leader() == true)
    s.manage:SetEnabled(not blocked)
    SetDetail(s.manage, blocked or T("permissionRoute"))
    local hasPage = (w.visiblePageCount or 0) > 0
    for key, tab in pairs(s.tabs) do
        local detail = blocked
        if not detail and not hasPage and (key == "info" or key == "log") then
            detail = T("needsPage")
        end
        local enabled = not detail
        local selected = key == w.guildMode and s.bodyMode ~= "purchase"
        SetDetail(tab, detail)
        if tab.isCurrent ~= selected or tab.available ~= enabled then
            tab.isCurrent, tab.available = selected, enabled
            if tab.auctionArt then
                if selected then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
                if not enabled then tab:SetEnabled(false) end
            elseif tab.selectedArt then
                for i = 1, 3 do
                    tab.inactiveArt[i]:SetShown(not selected)
                    tab.selectedArt[i]:SetShown(selected)
                end
                tab:SetEnabled(enabled and not selected)
            else
                tab:SetEnabled(enabled)
                B.Appearance:GuildTabSelection(tab, selected, enabled)
            end
            tab:SetAlpha(enabled and 1 or .55)
        end
    end
    if s.bodyMode ~= "purchase" then return end

    local count, canBuy = Count(), self:CanBuy(w)
    local target = s.purchaseTarget or (canBuy and count + 1)
    local title = target and (target == 1 and T("first") or T("next"):format(target)) or T("purchase")
    SetLabel(s.heading, title)
    SetLabel(s.meta, count and T("purchased"):format(count, TabLimit()) or "")
    local price = canBuy and target == count + 1 and GetGuildBankTabCost and GetGuildBankTabCost()
    s.price:SetShown(canBuy)
    SetLabel(s.price, price and T("price"):format(A.MoneyText(price)) or "")
    local status
    if s.purchaseTarget then status = T("buying")
    elseif count == nil then status = T("loading")
    elseif count >= TabLimit() then status = T("full")
    elseif not canBuy then status = count == 0 and T("unopened") .. " " .. T("leaderBuy") or T("leaderBuy")
    elseif not price or not balance then status = T("loading")
    elseif blocked then status = blocked
    elseif balance < price then status = T(depositHint and "funds" or "fundsDeposit"):format(A.MoneyText(price - balance))
    else status = T("afterPurchase"):format(A.MoneyText(balance - price)) end
    SetLabel(s.purchaseStatus, canBuy and status or "")
    SetLabel(s.notice, canBuy and "" or status)
    s.buy:SetShown(canBuy)
    s.buy:SetEnabled(act and canBuy and not s.purchaseTarget and balance and price and balance >= price or false)
end

local function ResetBody(w)
    local s = w.guildServices
    if s.log then
        s.log:Clear()
        s.log:Hide()
        s.logBar:Hide()
    end
    if s.note then
        s.noteReady = nil
        SetNote(w, nil)
        s.edit:ClearFocus()
        s.note:SetVerticalScroll(0)
        s.note:Hide()
        s.save:Hide()
        s.cancel:Hide()
        s.noteStatus:Hide()
    end
    s.buy:Hide()
    s.price:Hide()
    s.purchaseStatus:SetText("")
    s.meta:SetText("")
    s.notice:SetText("")
    CancelTimer(s, "logTimer")
    if s.logListening then
        YUI.Event:OffOwner(s.logOwner)
        s.logListening = nil
        B.Stats.listeners = math.max(0, B.Stats.listeners - 1)
    end
end

local function QueryLog(w)
    local s = w.guildServices
    if not Live(w) then return end
    if s.bodyMode == "moneylog" then QueryGuildBankLog(MAX_GUILDBANK_TABS + 1)
    elseif s.bodyMode == "log" and Viewable(w.page) then QueryGuildBankLog(w.page) end
end
local function QueueLog(w)
    local s = w.guildServices
    if s.logTimer then return end
    After(s, "logTimer", .15, function()
        QueryLog(w)
    end)
end

local function ShowBody(w, mode, page)
    local s = w.guildServices
    if mode == "log" or mode == "info" then
        SetLabel(s.heading, PageName(page) .. " · " .. T(mode))
    elseif mode == "moneylog" then
        SetLabel(s.heading, T("guildScope") .. " · " .. T(mode))
    elseif mode == "denied" then
        SetLabel(s.heading, T(w.guildMode))
    end
    if mode == s.bodyMode and s.bodyPage == page then return end
    if s.dialog and s.dialog.kind == "buy" and mode ~= "purchase" then StaticPopup_Hide(DialogKey("buy")) end
    ResetBody(w)
    s.bodyMode, s.bodyPage = mode, page
    s.body:SetShown(mode ~= "items")
    w.scroll:SetShown(mode == "items")
    if mode == "log" or mode == "moneylog" then
        if not s.log then MakeLog(s) end
        s.log:Show()
        s.logBar:Show()
        ReadLog(w, false)
        QueryLog(w)
        if mode == "log" then
            YUI.Event:On("GUILDBANKBAGSLOTS_CHANGED", s.queueLog, s.logOwner)
            s.logListening = true
            B.Stats.listeners = B.Stats.listeners + 1
        end
    elseif mode == "info" then
        if not s.note then MakeNote(w) end
        s.note:Show()
        s.noteStatus:Show()
        SetNote(w, nil)
        ReadNote(w, false)
        RequestTabNote(s, page)
    elseif mode == "denied" then
        s.notice:SetText(B:T("bank.denied"))
    end
end

local function CheckEditor(w)
    local loan = S.iconLoan
    if loan and loan.window == w and (not CanAct(w) or w.page ~= loan.tab or A.CurrentGuildTab() ~= loan.tab
        or not Viewable(loan.tab) or w.guildMode ~= loan.mode or not CanEditGuildBankTabInfo()) then
        loan.frame:Hide()
    end
end

local function OnEvent(w, event, arg)
    if not Live(w) then return end
    local s = w.guildServices
    if event == "GUILDBANKLOG_UPDATE" then
        if s.bodyMode == "moneylog" or s.bodyMode == "log" then ReadLog(w, true) end
    elseif event == "GUILDBANK_UPDATE_TEXT" or event == "GUILDBANK_TEXT_CHANGED" then
        local id = Security.SafeNumber(arg) or tonumber(Security.SafeString(arg))
        if not id then return end
        local editing = s.bodyMode == "info" and w.page == id and A.CurrentGuildTab() == id
        local hovered = s.tabTooltip and s.tabTooltip.page == id
        local note = s.tabNotes[id]
        if not editing and not hovered and note == nil then return end
        if not CanReadTabNote(id) then
            s.tabNotes[id] = nil
        elseif event == "GUILDBANK_UPDATE_TEXT" then
            if PendingTabNote(note) and note.changed then
                s.tabNotes[id] = nil
                if editing or hovered then RequestTabNote(s, id) end
            else
                if note ~= nil or editing then
                    local ok, text = pcall(GetGuildBankText, id)
                    if ok and not Security.IsSecretValue(text) then
                        local plain = text == nil and "" or Security.SafeString(text)
                        s.tabNotes[id] = plain and plain:gsub("|", "||")
                    else s.tabNotes[id] = nil end
                end
                if editing then ReadNote(w, true) end
            end
        elseif PendingTabNote(note) then
            -- The next reply may predate this notification. Requery once it arrives.
            note.changed = true
        else
            s.tabNotes[id] = nil
            if editing or hovered then RequestTabNote(s, id) end
        end
        if hovered then S:RefreshTabTooltip(w) end
    elseif event == "CURSOR_CHANGED" then
        CheckEditor(w)
        S:UpdateMoney(w)
        if s.bodyMode == "info" then NoteControls(w) end
    elseif event == "PLAYER_MONEY" or event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        S:UpdateMoney(w)
        if event == "GUILDBANK_UPDATE_MONEY" and s.bodyMode == "moneylog" then QueueLog(w) end
    else
        CheckEditor(w)
        if event == "GUILDBANK_UPDATE_TABS" or event == "GUILD_ROSTER_UPDATE" or event == "GUILD_RANKS_UPDATE" then
            for id in pairs(s.tabNotes) do
                if not CanReadTabNote(id) then s.tabNotes[id] = nil end
            end
            S:RefreshTabTooltip(w)
        end
        if event == "PLAYER_REGEN_DISABLED" then
            if s.dialog then StaticPopup_Hide(DialogKey(s.dialog.kind)) end
            S:UpdateMoney(w)
            if s.bodyMode == "info" then NoteControls(w) end
            return
        end
        if S:EnterPurchased(w) then return end
        if (s.bodyMode == "info" or s.bodyMode == "log") and not Viewable(w.page) then
            ShowBody(w, "denied")
        elseif s.bodyMode == "info" and not CanEditNote(w) then
            SetNote(w, GetGuildBankText(w.page))
        end
        -- Runtime already coalesces tab metadata changes into the bank layout.
        -- Rank events also need to invalidate the parent's capacity/permission row.
        if event ~= "GUILDBANK_UPDATE_TABS" and event ~= "GUILD_ROSTER_UPDATE" then
            B.View:Layout(w, true)
        else
            S:UpdateMoney(w)
        end
    end
end

local serviceTextInset, moneyColumnGap = 10, 13

function S:Setup(w)
    if w.guildServices then return end
    local s = {tabs={}, logOwner={}, tabNotes={}}
    w.guildServices = s
    w.guildMode = w.guildMode or "items"
    s.event = function(event, arg) OnEvent(w, event, arg) end
    s.queueLog = function() QueueLog(w) end
    s.footer = G:CreateFrame(w.root, {hidden=true})
    local line = B.Appearance:BankDivider(s.footer)
    line:SetPoint("TOPLEFT", 4, 3)
    line:SetPoint("TOPRIGHT", -4, 3)
    s.moneyRow = G:CreateFrame(s.footer, {})
    s.moneyRow:SetPoint("TOPLEFT", serviceTextInset, -4)
    s.moneyRow:SetPoint("TOPRIGHT", -serviceTextInset, -4)
    s.balance = Label(s.moneyRow)
    s.balance:SetJustifyH("LEFT")
    s.balance:SetWordWrap(false)
    s.available = Label(s.moneyRow, "color.text.secondary")
    s.available:SetJustifyH("LEFT")
    s.available:SetWordWrap(false)
    s.withdraw = FooterButton(s.moneyRow, T("withdraw"), function() OpenDialog(w, "withdraw") end)
    AttachHint(s.withdraw, T("withdraw"))
    s.withdraw:SetPoint("RIGHT")
    s.deposit = FooterButton(s.moneyRow, T("deposit"), function() OpenDialog(w, "deposit") end)
    AttachHint(s.deposit, T("deposit"))
    s.deposit:SetPoint("RIGHT", s.withdraw, "LEFT", -4, 0)
    s.nav = G:CreateFrame(s.footer, {})
    s.body = G:CreateFrame(w.root, {mouse=true, hidden=true})
    s.body:SetAllPoints(w.scroll)
    s.meta = Label(s.body, "color.text.secondary")
    s.meta:SetPoint("TOPRIGHT", -10, -6)
    s.meta:SetWordWrap(false)
    s.heading = G:CreateText(s.body, "", 13, "color.text.heading")
    B.Appearance:Text(s.heading, "heading")
    s.heading:SetPoint("TOPLEFT", serviceTextInset, -6)
    s.heading:SetPoint("RIGHT", s.meta, "LEFT", -10, 0)
    s.heading:SetJustifyH("LEFT")
    s.heading:SetWordWrap(false)
    s.notice = Label(s.body, "color.text.secondary")
    s.notice:SetPoint("LEFT", 10, -8)
    s.notice:SetPoint("RIGHT", -10, -8)
    s.notice:SetJustifyH("CENTER")
    s.buy = Button(s.body, T("purchase"), function() OpenDialog(w, "buy") end)
    s.buy:SetPoint("TOPRIGHT", -serviceTextInset, -35)
    s.price = Label(s.body)
    s.price:SetPoint("LEFT", s.body, "TOPLEFT", serviceTextInset, -46)
    s.price:SetPoint("RIGHT", s.buy, "LEFT", -8, 0)
    s.price:SetJustifyH("LEFT")
    s.purchaseStatus = Label(s.body, "color.text.secondary")
    s.purchaseStatus:SetPoint("TOPLEFT", serviceTextInset, -66)
    s.purchaseStatus:SetPoint("TOPRIGHT", -serviceTextInset, -66)
    s.purchaseStatus:SetJustifyH("LEFT")
end

local function ModeRow(w, native)
    local s = w.guildServices
    local key = native and "auctionRow" or "minimalRow"
    if s[key] then return s[key] end
    -- Hide the parent during construction: inherited OnShow expects an AH or
    -- character frame until AuctionModeTab replaces the template scripts.
    local row = G:CreateFrame(s.nav, {hidden=true})
    local template = native and NavigationTemplate()
    row.buttons = {}
    local previous
    row.naturalWidth = 0
    for _, mode in ipairs(modes) do
        local function click() SetMode(w, mode) end
        local tab = native and AuctionModeTab(row, template, mode, click) or ModeTab(row, mode, click)
        local gap = tab.classicCaps and -15 or (template and 0 or 3)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        else tab:SetPoint("TOPLEFT") end
        row.buttons[mode] = tab
        row.naturalWidth = row.naturalWidth + tab:GetWidth() + (previous and gap or 0)
        previous = tab
    end
    row:SetPoint("TOPLEFT")
    local function manage() Manage(w) end
    if native then
        row.manage = AuctionModeTab(row, template, "permissions", manage)
        if template then PanelTemplates_DeselectTab(row.manage) end
    else
        row.manage = FooterButton(row, T("permissions"), manage)
        AttachHint(row.manage, T("permissions"))
        StyleFooterButton(row.manage, false)
    end
    row.manage.detail = T("permissionRoute")
    local height = 24
    if native then
        -- Match the character window's bottom tabs. The NineSlice corner
        -- rectangle extends to -3, but its lower fringe is shadow. Tuck both
        -- tab families behind the metal at +2; the shell paints over the seam.
        local tab = row.manage
        row.seamY = 2
        height = math.max(35, tab:GetHeight())
        if tab.auctionArt and not tab.classicCaps then
            for _, part in ipairs({"Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive"}) do
                height = math.max(height, tab[part]:GetHeight())
            end
        end
    end
    row:SetSize(row.naturalWidth, height)
    s[key] = row
    return row
end

-- Both values are root-local UI units. View budgets the first inside the root
-- and the second below it when limiting the body to the available screen height.
function S:FooterMetrics(w, width, m)
    local s = w.guildServices
    if not s then self:Setup(w); s = w.guildServices end
    local native = B:GetConfig().skin == "native"
    local rootLevel = native and w.root:GetFrameLevel()
    if width == s.width and m == s.metrics and rootLevel == s.rootLevel then return s.insideHeight, s.outsideHeight end
    if m ~= s.metrics then
        StyleFooterButton(s.deposit, native)
        StyleFooterButton(s.withdraw, native)
    end
    local row = ModeRow(w, native)
    if s.row ~= row then
        if s.row then s.row:Hide() end
        s.row, s.tabs, s.manage = row, row.buttons, row.manage
        row:Show()
    end
    local footerWidth = width - m.left - m.right
    local usable = footerWidth - 2 * serviceTextInset
    local free = usable - s.deposit:GetWidth() - s.withdraw:GetWidth() - 4 - 8
    local stackAmounts = free < 180
    local moneyHeight = stackAmounts and 42 or 32
    s.moneyRow:SetHeight(moneyHeight)
    s.balance:ClearAllPoints()
    s.available:ClearAllPoints()
    if stackAmounts then
        s.balance:SetPoint("LEFT", 0, 9)
        s.available:SetPoint("LEFT", 0, -9)
    else
        s.balance:SetPoint("LEFT")
        s.available:SetPoint("LEFT", s.balance, "RIGHT", moneyColumnGap, 0)
    end
    local textWidth = math.max(1, stackAmounts and free or (free - moneyColumnGap) / 2)
    s.balance:SetWidth(textWidth)
    s.available:SetWidth(textWidth)
    -- Keep translations legible at minimum width. The action moves below the
    -- tabs if needed; its right edge always matches the withdrawal control.
    local wrap = row.naturalWidth + 10 + s.manage:GetWidth() > usable
    local navHeight = row:GetHeight() * (wrap and 2 or 1)
    s.nav:ClearAllPoints()
    if native then
        s.nav:SetPoint("TOPLEFT", w.root, "BOTTOMLEFT", m.left + serviceTextInset, row.seamY)
        -- The shell's NineSlice is at rootLevel - 1. Set the actual buttons:
        -- the template's OnLoad can raise a button above its parent row.
        local level = math.max(0, rootLevel - 2)
        for _, tab in pairs(row.buttons) do tab:SetFrameLevel(level) end
        row.manage:SetFrameLevel(level)
    else
        s.nav:SetPoint("BOTTOMLEFT", serviceTextInset, 0)
    end
    s.nav:SetSize(usable, navHeight)
    s.manage:ClearAllPoints()
    if native then
        -- Shared panel art projects its right cap beyond the button. Named
        -- Classic caps end at the button edge, like the money button's cap.
        local capOffset = s.manage.classicCaps and 0 or -7
        s.manage:SetPoint("TOPRIGHT", s.nav, "TOPRIGHT", capOffset, wrap and -row:GetHeight() or 0)
    else
        s.manage:SetPoint(wrap and "BOTTOMRIGHT" or "RIGHT", s.nav)
    end
    s.insideHeight = 4 + moneyHeight + (native and 0 or navHeight)
    s.outsideHeight = native and navHeight - row.seamY or 0
    s.footer:ClearAllPoints()
    s.footer:SetPoint("BOTTOMLEFT", m.left, m.bottom)
    s.footer:SetSize(footerWidth, s.insideHeight)
    if w.root.SetClampRectInsets then w.root:SetClampRectInsets(0, 0, 0, -s.outsideHeight) end
    s.width, s.metrics, s.rootLevel = width, m, rootLevel
    return s.insideHeight, s.outsideHeight
end

function S:Layout(w, width, m)
    if not Live(w) then return end
    self:FooterMetrics(w, width, m)
    local s = w.guildServices
    if not s.listening then
        for _, event in ipairs(events) do YUI.Event:On(event, s.event, s) end
        B.Stats.listeners = B.Stats.listeners + #events
        s.listening = true
        s.footer:Show()
    end
    local mode, page = w.guildMode or "items", w.page
    local count = Count()
    if mode == "items" and count == 0 then mode = "purchase" end
    if mode == "info" or mode == "log" then
        if not Viewable(page) or A.CurrentGuildTab() ~= page then mode = "denied" end
    end
    CheckEditor(w)
    ShowBody(w, mode, (mode == "log" or mode == "info") and page or nil)
    if mode == "info" then
        if not CanEditNote(w) then ReadNote(w, false) else NoteControls(w) end
    end
    self:UpdateMoney(w)
end

function S:Close(w)
    local s = w.guildServices
    if not s then return end
    self:ClearTabTooltip(w)
    s.tabNotes = {}
    if self.iconLoan and self.iconLoan.window == w then self.iconLoan.frame:Hide() end
    if s.dialog then StaticPopup_Hide(DialogKey(s.dialog.kind)); s.dialog = nil end
    if s.listening then
        YUI.Event:OffOwner(s)
        B.Stats.listeners = math.max(0, B.Stats.listeners - #events)
        s.listening = nil
    end
    StopPurchase(s)
    ResetBody(w)
    s.bodyMode, s.bodyPage = nil, nil
    s.body:Hide()
    s.footer:Hide()
    s.width = nil -- Restore anchors, levels and clamp on the next bank session.
    w.scroll:Show()
    w.guildMode = "items"
end
