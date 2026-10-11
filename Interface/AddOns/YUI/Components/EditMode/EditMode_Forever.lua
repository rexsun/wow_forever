local _, YUI = ...
if not YUI.IsForever or not YUI.EditMode then return end
local EM = YUI.EditMode

function EM:CanModifyLayouts()
    local api, manager = C_EditMode, EditModeManagerFrame
    if InCombatLockdown() then return false, "combat" end
    if not (api and api.GetLayouts and api.SaveLayouts and api.OnLayoutAdded
        and api.OnLayoutDeleted and EditModePresetLayoutManager
        and EditModePresetLayoutManager.GetCopyOfPresetLayouts
        and manager and manager.IsInitialized and manager:IsInitialized()) then
        return false, "not-ready"
    end
    if manager:IsEditModeActive() or manager:HasActiveChanges() then
        return false, "editing"
    end
    return true
end

local function SaveSnapshot(snapshot)
    local all = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    for _, layout in ipairs(snapshot.layouts) do all[#all + 1] = layout end
    snapshot.layouts = all
    C_EditMode.SaveLayouts(snapshot)
    EM.changedByInstaller = true
end

local function DeleteMatching(predicate)
    local ready, reason = EM:CanModifyLayouts()
    if not ready then return false, reason end
    local snapshot = C_EditMode.GetLayouts()
    if not snapshot or type(snapshot.layouts) ~= "table" then return false, "not-ready" end
    for index = #snapshot.layouts, 1, -1 do
        local current = C_EditMode.GetLayouts()
        local layout = current.layouts[index]
        if layout and predicate(layout) then
            table.remove(current.layouts, index)
            SaveSnapshot(current)
            C_EditMode.OnLayoutDeleted(index + Enum.EditModePresetLayoutsMeta.NumValues)
        end
    end
    return true
end

function EM:DeleteLayout(name, matchSuffix)
    if not name then return false end
    local ok, result = pcall(DeleteMatching, function(layout)
        if name == "YUI" or self:IsYUILayout(name) then
            return self:IsYUILayout(layout.layoutName)
        end
        return layout.layoutName == name
            or (matchSuffix and layout.layoutName:match("^" .. name .. "_?%d*$"))
    end)
    return ok and result == true
end

function EM:DeleteNonYUILayout()
    local ready = self:CanModifyLayouts()
    if not ready then return false end
    for index = #(self:GetAllLayouts() or {}), 1, -1 do
        local layout = self:GetAllLayouts()[index]
        if layout.layoutType == Enum.EditModeLayoutType.Account and not self:IsYUILayout(layout.layoutName) then
            local name = layout.layoutName
            local ok, result = pcall(DeleteMatching, function(candidate) return candidate.layoutName == name end)
            return ok and result == true
        end
    end
    return false
end

function EM:ImportLayout(layoutString, layoutName, matchSuffix)
    local ready, reason = self:CanModifyLayouts()
    if not ready then return false, reason end
    local parsed, info = pcall(C_EditMode.ConvertStringToLayoutInfo, layoutString)
    if not parsed or type(info) ~= "table" or type(info.systems) ~= "table" or #info.systems == 0 then
        return false, "invalid-layout"
    end
    local ok, failure = pcall(function()
        -- Parse before replacing old layouts, then use native index notifications.
        assert(self:DeleteLayout(layoutName, matchSuffix ~= false), "delete failed")
        local layoutType, name = self:GetLayoutInfo(layoutName)
        info.layoutType, info.layoutName = layoutType, name
        local snapshot = C_EditMode.GetLayouts()
        local insertAt = 1
        for index, layout in ipairs(snapshot.layouts) do
            if layout.layoutType == Enum.EditModeLayoutType.Account then insertAt = index + 1 end
        end
        if layoutType == Enum.EditModeLayoutType.Character then insertAt = #snapshot.layouts + 1 end
        table.insert(snapshot.layouts, insertAt, info)
        SaveSnapshot(snapshot)
        C_EditMode.OnLayoutAdded(insertAt + Enum.EditModePresetLayoutsMeta.NumValues, true, true)
        assert(self:GetCurrentLayoutName() == name, "layout was not activated")
    end)
    return ok, ok and nil or failure
end

function EM:ImportDefaultLayout()
    local layoutString = YUI.Data and YUI.Data:GetData("EditMode")
    if not layoutString then return false, "missing-preset" end
    local name = self:GetLatestYUILayout()
    return self:ImportLayout(layoutString, name, false)
end

local SwitchLayoutByName = EM.SwitchLayoutByName
local SwitchToLatestLayout = EM.SwitchToLatestLayout
function EM:SwitchLayoutByName(name)
    if not self:CanModifyLayouts() then return false end
    return SwitchLayoutByName(self, name)
end
function EM:SwitchToLatestLayout()
    if not self:CanModifyLayouts() then return false end
    return SwitchToLatestLayout(self)
end

-- The prompt shares the suite's themed confirmation UI; accepting is explicit.
function EM:ShowSwitchPrompt()
    if not YUI.Settings or not YUI.Settings.ShowConfirmPopup then return end
    local locale = YUI.Locale:Get("NativeInterface")
    local function SavePreference(checked)
        YUI.DB:GetGlobal(YUI.ProductId or "suite").ignoreYUISwitchPrompt = checked == true
    end
    YUI.Settings:ShowConfirmPopup(locale["beta.switch_edit_mode.message"], function(checked)
        SavePreference(checked)
        self:SwitchToLatestLayout()
    end, {
        owner = self,
        titleText = locale["beta.switch_edit_mode.title"],
        acceptText = locale["beta.switch_edit_mode.accept"],
        cancelText = locale["beta.switch_edit_mode.cancel"],
        checkboxText = locale["beta.switch_edit_mode.ignore"],
        onCancel = SavePreference,
    })
end
