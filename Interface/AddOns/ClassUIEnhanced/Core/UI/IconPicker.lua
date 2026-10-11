--[[
    IconPicker.lua

    The icon-selection popup: a searchable grid of spellbook and CDM icons, plus
    manual entry of a texture ID or path. Shared so any options surface can ask
    the player for an icon; the Tracking tab is its first caller.
--]]

local _
---@type string, private
local addonName, private = ...

local L = private.L

---@class private : table
---@field IconPicker iconpicker

---@class iconpicker : table
---@field Open fun(anchorParent: frame, onPick: fun(texture: number|string))

---@type iconpicker
---@diagnostic disable-next-line: missing-fields
local iconPicker = {}
private.IconPicker = iconPicker

---Prefix for the picker's global frame names. Kept identical to the Options
---panel's own prefix so the frames are named exactly as they were when the
---picker was built inline in Core/UI/Options.lua.
local frameName = "CUE_OptionsPanel"

---The built picker frame and its open function; nil until the first Open.
local builtFrame ---@type frame|nil
local builtOpen ---@type fun(callback: fun(texture: number|string))|nil

---Build the picker frame, hidden, parented to `panel`.
---@param panel frame
---@return frame pickerFrame
---@return fun(callback: fun(texture: number|string)) openPicker
local function createPicker(panel)
    -- =====================================================================
    -- Icon Picker popup
    -- =====================================================================
    local pickerFrame = CreateFrame("Frame", frameName .. "IconPicker", panel, "BackdropTemplate")
    pickerFrame:SetSize(340, 360)
    pickerFrame:SetPoint("CENTER", panel, "CENTER", 0, 0)
    pickerFrame:SetFrameStrata("DIALOG")
    pickerFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    pickerFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    pickerFrame:EnableMouse(true)
    pickerFrame:Hide()

    local pickerTitle = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerTitle:SetPoint("TOP", pickerFrame, "TOP", 0, -10)
    pickerTitle:SetText(L["ICON_OVERRIDES_PICKER_TITLE"])

    local pickerCloseBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelCloseButton")
    pickerCloseBtn:SetPoint("TOPRIGHT", pickerFrame, "TOPRIGHT", -2, -2)
    pickerCloseBtn:SetScript("OnClick", function() pickerFrame:Hide() end)

    -- Search/manual entry field
    local pickerSearchBox = CreateFrame("EditBox", frameName .. "IconPickerSearch", pickerFrame, "InputBoxTemplate")
    pickerSearchBox:SetSize(310, 22)
    pickerSearchBox:SetPoint("TOP", pickerTitle, "BOTTOM", 0, -8)
    pickerSearchBox:SetAutoFocus(false)
    pickerSearchBox:SetMaxLetters(256)

    local pickerSearchPlaceholder = pickerSearchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    pickerSearchPlaceholder:SetPoint("LEFT", pickerSearchBox, "LEFT", 5, 0)
    pickerSearchPlaceholder:SetText(L["ICON_OVERRIDES_PICKER_SEARCH"])

    pickerSearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        pickerSearchPlaceholder:SetShown(text == "")
    end)

    -- Preview of manually entered icon (beside the search box)
    local pickerPreview = pickerFrame:CreateTexture(nil, "ARTWORK")
    pickerPreview:SetSnapToPixelGrid(false)
    pickerPreview:SetTexelSnappingBias(0)
    pickerPreview:SetSize(22, 22)
    pickerPreview:SetPoint("LEFT", pickerSearchBox, "RIGHT", 4, 0)
    pickerPreview:Hide()

    -- Icon grid scroll frame
    local gridScrollFrame = CreateFrame("ScrollFrame", frameName .. "IconPickerGrid", pickerFrame, "UIPanelScrollFrameTemplate")
    gridScrollFrame:SetPoint("TOPLEFT", pickerSearchBox, "BOTTOMLEFT", -2, -8)
    gridScrollFrame:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -26, 10)

    local gridChild = CreateFrame("Frame", nil, gridScrollFrame)
    gridChild:SetWidth(300)
    gridChild:SetHeight(1)
    gridScrollFrame:SetScrollChild(gridChild)

    local gridNoResults = gridChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gridNoResults:SetPoint("TOPLEFT", gridChild, "TOPLEFT", 5, -10)
    gridNoResults:SetText(L["ICON_OVERRIDES_NO_RESULTS"])
    gridNoResults:SetTextColor(0.5, 0.5, 0.5)
    gridNoResults:Hide()

    -- Pool of icon buttons for the picker grid
    local gridButtons = {}
    local GRID_ICON_SIZE = 36
    local GRID_PAD = 4
    local GRID_COLS = 7
    local pickerCallback = nil ---@type fun(texture: number|string)|nil

    ---Create or reuse an icon grid button.
    ---@param index number
    ---@return frame
    local function getGridButton(index)
        if gridButtons[index] then return gridButtons[index] end
        local btn = CreateFrame("Button", nil, gridChild)
        btn:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSnapToPixelGrid(false)
        btn.icon:SetTexelSnappingBias(0)
        btn.icon:SetAllPoints(btn)

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetSnapToPixelGrid(false)
        btn.highlight:SetTexelSnappingBias(0)
        btn.highlight:SetAllPoints(btn)
        btn.highlight:SetColorTexture(1, 1, 1, 0.2)

        btn:SetScript("OnEnter", function(self)
            if self._cue_tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._cue_tooltip, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        gridButtons[index] = btn
        return btn
    end

    ---Build the list of available icons for the picker.
    ---Collects icons from all spellbook abilities (class, spec, general) and
    ---CDM tracked spells, deduplicated by texture to maximize variety.
    ---@param filterText string search filter
    ---@return table[] entries  { texture, spellID, name }
    local function buildIconList(filterText)
        local entries = {}
        local seenTexture = {}
        local filter = filterText and filterText:lower() or ""

        ---Add a spell to entries if it passes the filter and has a unique texture.
        local function addSpell(spellID, name, texture)
            if not texture or seenTexture[texture] then return end
            if filter ~= "" and not name:lower():find(filter, 1, true) then return end
            seenTexture[texture] = true
            entries[#entries + 1] = { texture = texture, spellID = spellID, name = name }
        end

        -- 1) All spellbook abilities (class, spec, general)
        local numSkillLines = private.compat.GetNumSpellBookSkillLines()
        for skillLineIndex = 1, numSkillLines do
            local skillLineInfo = private.compat.GetSpellBookSkillLineInfo(skillLineIndex)
            if skillLineInfo and not skillLineInfo.shouldHide and not skillLineInfo.offSpecID then
                for i = 1, skillLineInfo.numSpellBookItems do
                    local slotIndex = skillLineInfo.itemIndexOffset + i
                    local itemInfo = private.compat.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                    if itemInfo and itemInfo.spellID and itemInfo.iconID
                        and itemInfo.itemType == Enum.SpellBookItemType.Spell then
                        local name = itemInfo.name or C_Spell.GetSpellName(itemInfo.spellID) or ""
                        addSpell(itemInfo.spellID, name, itemInfo.iconID)
                    end
                end
            end
        end

        -- 2) CDM tracked spells (may include spells not in the spellbook, e.g. procs/buffs)
        local allCategories = {
            Enum.CooldownViewerCategory.Essential,
            Enum.CooldownViewerCategory.Utility,
            Enum.CooldownViewerCategory.TrackedBuff,
            Enum.CooldownViewerCategory.TrackedBar,
        }
        for _, cat in ipairs(allCategories) do
            local cooldownIds = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            for _, cdId in ipairs(cooldownIds) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdId)
                if info then
                    local sid = info.overrideSpellID or info.spellID
                    if sid then
                        local name = C_Spell.GetSpellName(sid) or ""
                        local texture = C_Spell.GetSpellTexture(sid)
                        addSpell(sid, name, texture)
                    end
                end
            end
        end

        table.sort(entries, function(a, b) return a.name < b.name end)
        return entries
    end

    ---Populate the icon grid based on filter text.
    local function populateGrid()
        local filterText = pickerSearchBox:GetText()

        -- Check if the filter text is a valid texture ID/path for manual entry preview
        local manualTex = tonumber(filterText)
        if not manualTex and filterText ~= "" and filterText:find("\\") then
            manualTex = filterText
        end
        if manualTex then
            pickerPreview:SetTexture(manualTex)
            pickerPreview:Show()
        else
            pickerPreview:Hide()
        end

        local entries = buildIconList(filterText)

        -- Hide all buttons first
        for _, btn in ipairs(gridButtons) do
            btn:Hide()
        end

        gridNoResults:SetShown(#entries == 0)

        for i, entry in ipairs(entries) do
            local btn = getGridButton(i)
            local col = (i - 1) % GRID_COLS
            local row = math.floor((i - 1) / GRID_COLS)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", gridChild, "TOPLEFT", col * (GRID_ICON_SIZE + GRID_PAD), -(row * (GRID_ICON_SIZE + GRID_PAD)))
            btn.icon:SetTexture(entry.texture)
            btn._cue_tooltip = entry.name
            btn._cue_texture = entry.texture
            btn:SetScript("OnClick", function()
                if pickerCallback then
                    pickerCallback(entry.texture)
                end
                pickerFrame:Hide()
            end)
            btn:Show()
        end

        local totalRows = math.ceil(#entries / GRID_COLS)
        gridChild:SetHeight(math.max(1, totalRows * (GRID_ICON_SIZE + GRID_PAD)))
    end

    pickerSearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        pickerSearchPlaceholder:SetShown(text == "")
        populateGrid()
    end)

    -- Enter key in search box: if there's a manual texture entry, use it
    pickerSearchBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local manualTex = tonumber(text)
        if not manualTex and text ~= "" and text:find("\\") then
            manualTex = text
        end
        if manualTex and pickerCallback then
            pickerCallback(manualTex)
            pickerFrame:Hide()
        end
        self:ClearFocus()
    end)

    pickerSearchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        pickerFrame:Hide()
    end)

    ---Open the icon picker popup.
    ---@param callback fun(texture: number|string)
    local function openPicker(callback)
        pickerCallback = callback
        pickerSearchBox:SetText("")
        pickerFrame:Show()
        populateGrid()
    end

    return pickerFrame, openPicker
end

---Open the icon picker centred on `anchorParent`; `onPick` receives the chosen
---texture (a fileID, or a path/ID typed into the search box). The frame is
---created on the first call and parented to that call's `anchorParent`, at
---DIALOG strata; later calls re-centre it on theirs.
---@param anchorParent frame
---@param onPick fun(texture: number|string)
function iconPicker.Open(anchorParent, onPick)
    if not builtFrame then
        builtFrame, builtOpen = createPicker(anchorParent)
    end
    builtFrame:ClearAllPoints()
    builtFrame:SetPoint("CENTER", anchorParent, "CENTER", 0, 0)
    builtOpen(onPick)
end
