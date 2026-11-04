local YUI = _G.YUI
if not (YUI and YUI.IsForever and YUI.Dev) then return end
local previousSlashHandler = YUI.HandleSlashCommand

function YUI:HandleSlashCommand(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$"):lower()
    local args=text:match("^dev%s+(.+)$")
    if args and self.Dev.HandleNoticePreview and self.Dev:HandleNoticePreview(args) then return true end
    if args and self.Dev.HandleEffectPreview and self.Dev:HandleEffectPreview(args) then return true end
    if args and self.Dev.HandleSkinPreview and self.Dev:HandleSkinPreview(args) then return true end
    if text:match("^dev%s+clean$") then
        self.Dev:CleanSavedCharacterData()
        return true
    end
    if previousSlashHandler then return previousSlashHandler(self, message) end
    return false
end
