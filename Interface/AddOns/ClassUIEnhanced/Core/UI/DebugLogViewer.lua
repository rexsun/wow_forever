
-- Paginated viewer for the printdebug ring buffer maintained in Core/Start.lua.
-- Triggered by /cue log. Snapshots on open; refresh re-snapshots; copy mode
-- swaps the editor for a single-line EditBox so Ctrl+C yields the full string
-- (mirrors the PerfProfiler trace-copy pattern, which solved the same problem).

local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local PANEL_W, PANEL_H = 800, 600
local EDITOR_W, EDITOR_H = 780, 480
local LINES_PER_PAGE = 500

local panel = nil
local snapshot = {}
local filtered = {}
local currentPage = 1
local copyModeActive = false

local function formatTime(t)
    local minutes = math.floor(t / 60) % 60
    local seconds = t - math.floor(t / 60) * 60
    return string.format("[%02d:%06.3f]", minutes, seconds)
end

local function rebuildFiltered(filterText)
    filtered = {}
    if not snapshot or #snapshot == 0 then return end
    if not filterText or filterText == "" then
        for i = 1, #snapshot do
            filtered[i] = snapshot[i]
        end
        return
    end
    local needle = filterText:lower()
    for i = 1, #snapshot do
        local entry = snapshot[i]
        if entry.text and entry.text:lower():find(needle, 1, true) then
            filtered[#filtered + 1] = entry
        end
    end
end

local function totalPages()
    if #filtered == 0 then return 1 end
    return math.ceil(#filtered / LINES_PER_PAGE)
end

local function buildPageText(pageIdx)
    local startIdx = (pageIdx - 1) * LINES_PER_PAGE + 1
    local endIdx = math.min(startIdx + LINES_PER_PAGE - 1, #filtered)
    local out = {}
    for i = startIdx, endIdx do
        local entry = filtered[i]
        out[i - startIdx + 1] = formatTime(entry.t) .. " " .. entry.text
    end
    return table.concat(out, "\n")
end

local function buildFullText()
    local out = {}
    for i = 1, #filtered do
        local entry = filtered[i]
        out[i] = formatTime(entry.t) .. " " .. entry.text
    end
    return table.concat(out, "\n")
end

local function refreshDisplay()
    if not panel or not panel.pageLabel then return end
    if currentPage < 1 then currentPage = 1 end
    local pages = totalPages()
    if currentPage > pages then currentPage = pages end
    panel.pageLabel:SetText(string.format("Page %d / %d  (%d entries)", currentPage, pages, #filtered))
    if copyModeActive then
        panel.editor:Hide()
        panel.copyBox:Show()
        panel.hintLabel:Show()
        panel.copyBox:SetText(buildFullText())
        C_Timer.After(0, function()
            if panel and panel.copyBox and panel.copyBox:IsShown() then
                panel.copyBox:SetFocus()
                panel.copyBox:HighlightText()
            end
        end)
    else
        panel.copyBox:Hide()
        panel.hintLabel:Hide()
        panel.editor:Show()
        panel.editor:SetText(buildPageText(currentPage))
    end
end

local function applyFilterAndRefresh()
    if not panel or not panel.filterBox then return end
    local filterText = panel.filterBox:GetText() or ""
    rebuildFiltered(filterText)
    currentPage = 1
    refreshDisplay()
end

local function takeSnapshot()
    snapshot = private.SnapshotDebugLog()
    rebuildFiltered(panel and panel.filterBox and panel.filterBox:GetText() or "")
    currentPage = 1
end

local function createPanel()
    if panel then return panel end

    panel = framework:CreateSimplePanel(UIParent, PANEL_W, PANEL_H, "CUE Debug Log", "CUEDebugLogPanel")
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")

    -- Filter editbox (top)
    local filterLabel = panel:CreateFontString("CUEDebugLogFilterLabel", "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -32)
    filterLabel:SetText("Filter:")

    local filterBox = CreateFrame("EditBox", "CUEDebugLogFilterBox", panel, "BackdropTemplate")
    filterBox:SetSize(220, 20)
    filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
    filterBox:SetAutoFocus(false)
    filterBox:SetFontObject("GameFontHighlight")
    filterBox:SetTextInsets(4, 4, 2, 2)
    filterBox:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1,
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true,
    })
    filterBox:SetBackdropBorderColor(0, 0, 0, 1)
    filterBox:SetBackdropColor(.2, .2, .2, .5)
    filterBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    filterBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    filterBox:SetScript("OnTextChanged", function() applyFilterAndRefresh() end)
    panel.filterBox = filterBox

    -- Buttons row (top right)
    local function makeButton(label, w, onClick)
        local btn = framework:CreateButton(panel, onClick, w, 22, label)
        return btn
    end

    local refreshBtn = makeButton("Refresh", 70, function()
        takeSnapshot()
        refreshDisplay()
    end)
    refreshBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -30)

    local saveBtn = makeButton("Save to SV", 90, function()
        private.SaveDebugLogToSV()
    end)
    saveBtn:SetPoint("RIGHT", refreshBtn.widget, "LEFT", -6, 0)

    local clearBtn = makeButton("Clear buffer", 100, function()
        StaticPopup_Show("CUE_DEBUGLOG_CLEAR_CONFIRM")
    end)
    clearBtn:SetPoint("RIGHT", saveBtn.widget, "LEFT", -6, 0)

    local copyAllBtn = makeButton("Copy all (full)", 110, function()
        copyModeActive = true
        refreshDisplay()
    end)
    copyAllBtn:SetPoint("RIGHT", clearBtn.widget, "LEFT", -6, 0)

    local viewBtn = makeButton("View mode", 90, function()
        copyModeActive = false
        refreshDisplay()
    end)
    viewBtn:SetPoint("RIGHT", copyAllBtn.widget, "LEFT", -6, 0)

    -- Editor (paginated view)
    local luaeditor_backdrop_color = { .2, .2, .2, .5 }
    local luaeditor_border_color = { 0, 0, 0, 1 }
    local editor = framework:NewSpecialLuaEditorEntry(panel, EDITOR_W, EDITOR_H, "DebugLogEditor", "$parentDebugLogEditor", true, false)
    editor.editbox:SetMaxBytes(0)
    editor.editbox:SetMaxLetters(0)
    editor.editbox:SetFontObject("GameFontHighlight")
    editor:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -60)
    editor:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true })
    editor:SetBackdropBorderColor(unpack(luaeditor_border_color))
    editor:SetBackdropColor(unpack(luaeditor_backdrop_color))
    framework:ReskinSlider(editor.scroll)
    panel.editor = editor

    -- Single-line copy box (overlays editor area when active)
    local copyBox = CreateFrame("EditBox", "CUEDebugLogCopyBox", panel, "BackdropTemplate")
    copyBox:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -20)
    copyBox:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", 0, 0)
    copyBox:SetMultiLine(false)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject("GameFontHighlight")
    copyBox:SetMaxBytes(0)
    copyBox:SetMaxLetters(0)
    copyBox:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1,
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true,
    })
    copyBox:SetBackdropBorderColor(unpack(luaeditor_border_color))
    copyBox:SetBackdropColor(unpack(luaeditor_backdrop_color))
    copyBox:SetTextInsets(6, 6, 4, 4)
    copyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    copyBox:Hide()
    panel.copyBox = copyBox

    local copyClickCatcher = CreateFrame("Frame", "CUEDebugLogCopyClickCatcher", copyBox)
    copyClickCatcher:SetAllPoints(copyBox)
    copyClickCatcher:EnableMouse(true)
    local function reselectCopyBox()
        copyBox:SetFocus()
        copyBox:HighlightText()
    end
    copyClickCatcher:SetScript("OnMouseDown", reselectCopyBox)
    copyBox:SetScript("OnCursorChanged", reselectCopyBox)

    local hintLabel = panel:CreateFontString("CUEDebugLogHintLabel", "OVERLAY", "GameFontNormalSmall")
    hintLabel:SetPoint("BOTTOMLEFT", copyBox, "TOPLEFT", 0, 4)
    hintLabel:SetPoint("BOTTOMRIGHT", copyBox, "TOPRIGHT", 0, 4)
    hintLabel:SetJustifyH("CENTER")
    hintLabel:SetText("Click the box and press Ctrl+C to copy. Lines are joined by newlines.")
    hintLabel:Hide()
    panel.hintLabel = hintLabel

    -- Pagination controls (bottom)
    local prevBtn = makeButton("< Prev", 70, function()
        currentPage = currentPage - 1
        refreshDisplay()
    end)
    prevBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)

    local nextBtn = makeButton("Next >", 70, function()
        currentPage = currentPage + 1
        refreshDisplay()
    end)
    nextBtn:SetPoint("LEFT", prevBtn.widget, "RIGHT", 6, 0)

    local pageLabel = panel:CreateFontString("CUEDebugLogPageLabel", "OVERLAY", "GameFontNormal")
    pageLabel:SetPoint("LEFT", nextBtn.widget, "RIGHT", 12, 0)
    pageLabel:SetText("Page 1 / 1  (0 entries)")
    panel.pageLabel = pageLabel

    panel:HookScript("OnHide", function()
        if panel.copyBox then
            panel.copyBox:ClearFocus()
            panel.copyBox:SetText("")
            panel.copyBox:Hide()
        end
        if panel.hintLabel then panel.hintLabel:Hide() end
        copyModeActive = false
    end)

    StaticPopupDialogs["CUE_DEBUGLOG_CLEAR_CONFIRM"] = StaticPopupDialogs["CUE_DEBUGLOG_CLEAR_CONFIRM"] or {
        text = "Clear the debug log buffer and saved dump?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            private.ClearDebugLog()
            if panel and panel:IsShown() then
                takeSnapshot()
                refreshDisplay()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    tinsert(UISpecialFrames, "CUEDebugLogPanel")
    panel:Hide()
    return panel
end

function private.OpenDebugLogViewer()
    createPanel()
    copyModeActive = false
    takeSnapshot()
    refreshDisplay()
    panel:Show()
end

function private.SaveDebugLogToSV()
    if not ClassUIEnhancedDB then
        private.print("Debug log save failed: SavedVariables not initialised yet.")
        return
    end
    local entries = private.SnapshotDebugLog()
    ClassUIEnhancedDB.debug_log_dump = {
        saved_at = GetServerTime(),
        build = GetBuildInfo(),
        entries = entries,
    }
    private.print(string.format("Saved %d entries — /reload then read WTF/Account/<acct>/SavedVariables/ClassUIEnhanced.lua", #entries))
end
