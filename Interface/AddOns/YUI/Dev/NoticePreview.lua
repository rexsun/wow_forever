local YUI = _G.YUI
YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev

function Dev:HandleNoticePreview(args)
    local command=tostring(args or ""):match("^%s*(.-)%s*$"):lower()
    if command~="changelog" and command~="addons" then return false end
    local locale=YUI.Locale:Get("Core")
    local function message(key)
        if YUI.Print then YUI:Print(locale[key]) else print(locale[key]) end
    end
    if command=="changelog" then
        local changelog=YUI.Changelog
        local data=changelog and changelog.GetData and changelog:GetData()
        if not (changelog and changelog.CreatePopup and data and data[1]) then
            message("dev.notice.unavailable"); return true
        end
        changelog:CreatePopup(data[1].version,true)
        return true
    end
    local assistant=YUI.AddonAssistant
    if not (assistant and assistant.View and assistant.View.StartPrompt) then
        message("dev.notice.unavailable"); return true
    end
    if assistant.Runtime.pending then message("dev.notice.busy"); return true end
    if not assistant.Client.Safe() then
        if YUI.Print then YUI:Print(assistant.L.waitSafe) else print(assistant.L.waitSafe) end
        return true
    end
    local records,current=assistant.Client.Scan()
    if not records then message("dev.notice.unavailable"); return true end
    local target=assistant.Model.Copy(current)
    local added,removed=false,false
    -- Demonstration data only: no saved profile, enable flags, rules or runtime pending state are changed.
    for _,record in ipairs(records) do
        if not current[record.name] and not added then target[record.name]=true; added=true
        elseif current[record.name] and not removed and record.name~=assistant.addonName and record.name~=YUI.AddonName then
            target[record.name]=nil; removed=true
        end
    end
    assistant.View:StopPrompt()
    assistant.View:StartPrompt({preview=true,records=records,current=current,target=target,
        profileName=locale["dev.notice.profile"],testLabel=locale["dev.notice.test"],
        confirmText=locale["dev.notice.confirm"],hint=locale["dev.notice.hint"]})
    return true
end
