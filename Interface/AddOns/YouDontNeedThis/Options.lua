-- You Don't Need This - settings panel (Esc > Options > AddOns) and the addon compartment entry
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.

local _, ns = ...

local TITLE = "You Don't Need This"
local ROW_HEIGHT = 22

local panel = CreateFrame("Frame")
panel.name = TITLE
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(TITLE)

local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
intro:SetJustifyH("LEFT")
intro:SetText("Marks quest items once every quest that uses them is completed. It never deletes, sells or moves anything.")

------------------------------------------------------------------------
-- Checkboxes
------------------------------------------------------------------------
local checks = {}

local function Check(key, label, anchor)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local text = cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.DB().settings[key] = self:GetChecked() and true or false
        if ns.Refresh then ns.Refresh(false, true) end
    end)
    cb.key = key
    checks[#checks + 1] = cb
    return cb
end

local marksCheck = Check("marks", "Red X on items you don't need (bags and bank)", intro)
local alertsCheck = Check("alerts", "Alerts: a summary after login, and a message when an item stops being needed", marksCheck)
local nudgeCheck = Check("questNudge", "Tell me in chat when I have low-level quests (after login and on level-up)", alertsCheck)
local onlyMoreCheck = Check("questNudgeOnlyMore", "At login, only when I have more low-level quests than last time", nudgeCheck)
onlyMoreCheck:SetPoint("TOPLEFT", nudgeCheck, "BOTTOMLEFT", 20, -2) -- indented under the box it depends on
nudgeCheck:HookScript("OnClick", function(self) onlyMoreCheck:SetEnabled(self:GetChecked()) end)

-- Minimap button: stored as settings.minimap.hide, so this box is the inverse.
local minimapCheck = Check("minimapShown", "Minimap button (click: low-level quests, right-click: settings)", onlyMoreCheck)
minimapCheck:SetPoint("TOPLEFT", onlyMoreCheck, "BOTTOMLEFT", -20, -6)
minimapCheck:SetScript("OnClick", function(self)
    ns.DB().settings.minimap.hide = not self:GetChecked()
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
end)

local listButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
listButton:SetSize(220, 24)
listButton:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 2, -10)
listButton:SetText("List items I don't need in chat")
listButton:SetScript("OnClick", function() ns.ListJunk() end)

local questsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
questsButton:SetSize(200, 24)
questsButton:SetPoint("LEFT", listButton, "RIGHT", 8, 0)
questsButton:SetText("Low-level quests...")
questsButton:SetScript("OnClick", function() if ns.ToggleQuests then ns.ToggleQuests() end end)

------------------------------------------------------------------------
-- Your verdicts (/ydnt ignore, /ydnt keep)
------------------------------------------------------------------------
local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
header:SetPoint("TOPLEFT", listButton, "BOTTOMLEFT", -2, -20)
header:SetText("Your choices (all characters)")

local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
help:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
help:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
help:SetJustifyH("LEFT")
help:SetText("Type /ydnt ignore and shift-click an item to mark it as not needed, for example when its quest "
    .. "can't be done anymore. /ydnt keep <item> never marks it.")

local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -8)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
empty:SetPoint("TOPLEFT", 4, -4)
empty:SetText("Nothing yet.")

local rows = {}

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:EnableMouse(true)

    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(70, 20)
    row.remove:SetPoint("RIGHT", 0, 0)
    row.remove:SetText("Remove")
    row.remove:SetScript("OnClick", function() ns.SetOverride(row.itemID, nil) end)

    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.state:SetPoint("RIGHT", row.remove, "LEFT", -10, 0)
    row.state:SetWidth(90)
    row.state:SetJustifyH("LEFT")

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.state, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = row
    return row
end

local RequestItem = C_Item and C_Item.RequestLoadItemDataByID

local function RefreshList()
    local ids = {}
    for itemID in pairs(ns.Global().overrides) do ids[#ids + 1] = itemID end
    table.sort(ids)

    for i, itemID in ipairs(ids) do
        local row = Row(i)
        row.itemID = itemID
        local label = ns.ItemLabel(itemID)
        if label:sub(1, 5) == "item " and RequestItem then RequestItem(itemID) end
        row.name:SetText(label)
        local kind = ns.Global().overrides[itemID]
        row.state:SetText(kind == "keep" and "|cff66ff66Keep|r" or "|cffff5959Not needed|r")
        row:Show()
    end
    for i = #ids + 1, #rows do rows[i]:Hide() end
    empty:SetShown(#ids == 0)
    content:SetSize(math.max(1, scroll:GetWidth()), math.max(1, #ids * ROW_HEIGHT))
end

local function RefreshPanel()
    local s = ns.DB().settings
    for _, cb in ipairs(checks) do cb:SetChecked(s[cb.key]) end
    minimapCheck:SetChecked(not s.minimap.hide)
    onlyMoreCheck:SetEnabled(s.questNudge)
    RefreshList()
end

panel:SetScript("OnShow", RefreshPanel)
-- Item names that weren't cached yet arrive later.
panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
panel:SetScript("OnEvent", function(self)
    if self:IsVisible() then RefreshList() end
end)

function ns.OnOverridesChanged()
    if panel:IsVisible() then RefreshPanel() end
end

------------------------------------------------------------------------
-- Registration (feature-detected: Settings API on modern UIs, InterfaceOptions on older ones)
------------------------------------------------------------------------
local category

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call only opens the frame on some older clients.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

------------------------------------------------------------------------
-- Addon compartment (the addons button by the minimap), named in the .toc
------------------------------------------------------------------------
-- Left-click: settings. Right-click: the low-level quests window.
function YouDontNeedThis_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" and ns.ToggleQuests then
        ns.ToggleQuests()
    else
        ns.OpenOptions()
    end
end

function YouDontNeedThis_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine(TITLE)
    GameTooltip:AddLine("Click to open the settings.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for low-level quests.", 1, 1, 1)
    GameTooltip:AddLine("/ydnt for commands.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function YouDontNeedThis_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
