local YUI = _G.YUI
if not (YUI and YUI.IsForever and YUI.Dev) then return end
local previousSlashHandler = YUI.HandleSlashCommand

function YUI:HandleSlashCommand(message)
    local text = tostring(message or ""):match("^%s*(.-)%s*$")
    local command, args = text:match("^(%S+)%s*(.*)$")
    if command and command:lower() == "dev" then
        if self.Dev.HandleBagSortSlash and self.Dev:HandleBagSortSlash(args) then return true end
        args = args:lower()
        if args == "" or args == "help" then
            local help = "/yui dev bagsort | changelog | addons | effects | skins | skins56 | clean"
            if self.Print then self:Print(help) else print(help) end
            return true
        end
        if self.Dev.HandleNoticePreview and self.Dev:HandleNoticePreview(args) then return true end
        if self.Dev.HandleEffectPreview and self.Dev:HandleEffectPreview(args) then return true end
        if self.Dev.HandleSkinPreview and self.Dev:HandleSkinPreview(args) then return true end
        if args == "clean" then
            self.Dev:CleanSavedCharacterData()
            return true
        end
    end
    if previousSlashHandler then return previousSlashHandler(self, message) end
    return false
end
