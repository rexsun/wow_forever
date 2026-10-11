local YUI = _G.YUI
if not (YUI and YUI.IsForever and YUI.Dev) then return end
local previousSlashHandler = YUI.HandleSlashCommand

function YUI:HandleSlashCommand(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$"):lower()
    if text:match("^dev%s+clean$") then
        self.Dev:CleanSavedCharacterData()
        return true
    end
    if previousSlashHandler then return previousSlashHandler(self, message) end
    return false
end
