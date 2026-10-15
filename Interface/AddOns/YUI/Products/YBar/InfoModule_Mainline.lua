local YUI = _G.YUI
local YBar = YUI.YBar
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local Info = {}
YBar.InfoModule = Info

function Info.DB(self)
    local root = self.instanceContext and self.instanceContext:GetRoot()
        or (YBar.GetModuleRoot and YBar:GetModuleRoot(self.configKey or self.name)) or YBar:EnsureDB()
    root[self.configKey or self.name] = root[self.configKey or self.name] or {}
    self.db = root[self.configKey or self.name]
    return self.db
end

function Info.Create(self, parent)
    local frame = YBar:CreateBarItem(parent, { variant = "bare", width = 80, height = 20,
        clickable = true, hoverable = true, showIcon = false, text = false, value = false })
    frame.iconSlot, frame.icon = YBar:CreateIconSlot(frame, { size = 16, icon = self.defaultIcon or 134400, padding = 0 })
    frame.iconSlot:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.statusText, frame.text = YBar:CreateStatusText(frame, { variant = "single", value = "", width = 80,
        height = 20, justifyH = "LEFT", colorKey = "color.ybar.text" })
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame.iconSlot, "RIGHT", 4, 0)
    frame.text:SetWordWrap(false)
    YBar:RegisterBarItemHoverText(frame, frame.text)
    frame:RegisterForClicks("AnyUp")
    frame:SetScript("OnClick", function(f, button)
        if button=="LeftButton" and IsAltKeyDown and IsAltKeyDown() then
            YUI:OpenYBarModuleSettings(self.instanceContext and self.instanceContext.id or self.name)
            return
        end
        if self.OnClick then self:OnClick(f, button) end
    end)
    frame:SetScript("OnEnter", function(f)
        YBar:OnModuleEnter(f)
        if self.OnEnter then self:OnEnter(f) end
    end)
    frame:SetScript("OnLeave", function(f)
        YBar:OnModuleLeave(f)
        if self.OnLeave then self:OnLeave(f) else YUI.HideGameTooltip() end
    end)
    self.frame, self.parent = frame, parent
    self:UpdateBarItem()
    if YBar:IsSubModuleEnabled(self.name) then self:AttachRuntime() end
    return frame
end

function Info.Display(self, text, icon)
    if not self.frame then return end
    local db = self.GetDisplayDB and self:GetDisplayDB() or Info.DB(self)
    local f, root = self.frame, self.instanceContext and self.instanceContext:GetRoot()
        or (YBar.GetModuleRoot and YBar:GetModuleRoot(self.configKey or self.name)) or YBar:EnsureDB()
    local size = tonumber(db.size) or 14
    local font = YBar:ResolveFontPath(db.font, STANDARD_TEXT_FONT)
    local flags = root.fontFlags or (root.fontOutline and "OUTLINE" or "")
    local iconSize = tonumber(db.iconSize) or size + 2
    local iconGap = tonumber(db.iconGap) or 4
    if self.font ~= font or self.size ~= size or self.flags ~= flags then
        local applied=f.text:SetFont(font, size, flags)
        if applied~=false then self.font, self.size, self.flags = font, size, flags end
    end
    if self.iconSize ~= iconSize then
        self.iconSize = iconSize
        f.iconSlot:SetSize(iconSize, iconSize)
    end
    local color = db.colorMode == "custom" and db.color
    if color then
        if self.colorR~=color[1] or self.colorG~=color[2] or self.colorB~=color[3] or self.colorA~=(color[4] or 1) then
            self.colorR,self.colorG,self.colorB,self.colorA=color[1],color[2],color[3],color[4] or 1
            YBar:SetThemedTextRawColor(f.text,self.colorR,self.colorG,self.colorB,self.colorA)
        end
    elseif self.colorR then
        self.colorR,self.colorG,self.colorB,self.colorA=nil,nil,nil,nil
        YBar:SetThemedTextColor(f.text,"color.ybar.text")
    end
    local shadow = root.fontShadow == true
    if self.shadow ~= shadow then
        if shadow then f.text:SetShadowColor(0, 0, 0, 1) end
        f.text:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
        self.shadow = shadow
    end
    if self.chrome ~= (db.iconBackground ~= false) then
        self.chrome = db.iconBackground ~= false
        YBar:SetIconSlotChromeVisible(f.iconSlot, self.chrome)
    end
    text = tostring(text or "")
    local showIcon, showText = db.display ~= "text", db.display ~= "icon"
    local maxWidth = tonumber(db.maxWidth) or 180
    local reservedWidth = showText and self.GetReservedTextWidth and self:GetReservedTextWidth(font, size, flags) or 0
    local deferWidth = self.GetReservedTextWidth and YUI.API.Security.InCombatLockdown()
    if self.font == font and self.size == size and self.flags == flags
        and self.text == text and self.icon == icon and self.display == db.display and self.maxWidth == maxWidth
        and self.measuredSize == size and self.measuredFont == font and self.measuredFlags == flags
        and self.measuredIconSize == iconSize and self.measuredIconGap == iconGap
        and self.measuredReservedWidth == reservedWidth
        and not (self.reservedWidthPending and not deferWidth) then return end
    self.text, self.icon, self.display, self.maxWidth = text, icon, db.display, maxWidth
    self.measuredSize, self.measuredFont = size, font
    self.measuredFlags,self.measuredIconSize,self.measuredIconGap=flags,iconSize,iconGap
    self.measuredReservedWidth = reservedWidth
    f.iconSlot:SetShown(showIcon)
    f.text:SetShown(showText)
    YBar:SetIconSlotTexture(f.iconSlot, icon or self.defaultIcon or 134400)
    YBar:SetIconSlotChromeVisible(f.iconSlot, self.chrome)
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f, "LEFT", showIcon and iconSize + iconGap or 0, 0)
    f.text:SetWidth(0)
    f.text:SetText(text)
    if showText and self.FitBarText then
        local fitted = self:FitBarText(text, f.text, maxWidth)
        if fitted ~= text then f.text:SetText(fitted) end
    end
    local measured=0
    if showText then
        measured=f.text.GetUnboundedStringWidth and f.text:GetUnboundedStringWidth()
        measured=tonumber(measured) or f.text:GetStringWidth()
        -- A hidden/startup FontString may not have usable metrics yet. Retry on
        -- the next normal refresh instead of caching a permanent one-pixel label.
        if measured<=0 and text~="" then self.text=nil end
    end
    local width=showText and math.min(math.ceil(math.max(measured, reservedWidth))+1,maxWidth) or 0
    local iconWidth = showIcon and iconSize + iconGap or 0
    if deferWidth and self.width and width + iconWidth + 2 ~= self.width then
        -- 耐久下降、首屏测量恢复或外观变化恰逢战斗时，保留已应用的空间，脱战再收紧。
        self.reservedWidthPending = true
        width = math.max(self.width - iconWidth - 2, 0)
    else
        self.reservedWidthPending = nil
    end
    f.text:SetWidth(math.max(width, 1))
    width = math.ceil(width + iconWidth + 2)
    self.contentHeight = math.max(showText and size or 0,showIcon and iconSize or 0)
    if self.width ~= width then
        self.width = width
        f:SetWidth(width)
        YBar:UpdateLayout()
    end
end

function Info.Options(self)
    local function db() return self.GetDisplayDB and self:GetDisplayDB() or Info.DB(self) end
    local function set(key, value) db()[key] = value; self:UpdateBarItem() end
    local function fontValue()
        local value = db().font or STANDARD_TEXT_FONT
        local media = LibStub("LibSharedMedia-3.0", true)
        for name, path in pairs(media and media:HashTable("font") or {}) do
            if path == value then return name end
        end
        return value
    end
    local options = {
        { type = "divider", label = L["ybar.settings.section.info_bar"], width = 400, alignLeft = true },
        { type = "row", children = {
            { type = "font", label = LC["common.font"], width = 220,
                get = fontValue,
                prependOptions = function()
                    local value = fontValue()
                    if type(value) == "string" and (value:find("\\", 1, true) or value:find("/", 1, true)) then
                        return {{text=value, value=value, fontPath=value}}
                    end
                end,
                set = function(v) set("font", v) end },
            { type = "slider", label = LC["common.size"], width = 220, min = 10, max = 32, step = 1,
                get = function() return db().size or 14 end, set = function(v) set("size", v) end },
        } },
        { type = "row", children = {
            { type = "dropdown", label = L["feature.display"], width = 220,
                options = {{text=L["feature.icon_text"],value="both"},{text=LC["common.show_icon"],value="icon"},{text=L["feature.text"],value="text"}},
                get = function() return db().display or "both" end, set = function(v) set("display", v) end },
            { type = "checkbox", label = L["bugsack.option.icon_background"],
                get = function() return db().iconBackground ~= false end, set = function(v) set("iconBackground", v) end },
        } },
        { type = "slider", label = L["feature.max_width"], width = 220, min = 40, max = 400, step = 10,
            get = function() return db().maxWidth or 180 end, set = function(v) set("maxWidth", v) end },
    }
    local font, size = options[2].children[1], options[2].children[2]
    local display, chrome = options[3].children[1], options[3].children[2]
    chrome.labelPosition = "left"
    return {options[1],font,size,display,chrome,options[4]}
end

function Info.Register(module)
    YBar:RegisterModule(module, { id = "ybar." .. module.name:lower(), parent = "ybar", product = "ybar",
        scope = "ybar", dependencies = {"ybar", "core.event"}, defaultEnabled = true })
end

function Info.Tooltip(self, title, body)
    GameTooltip:SetOwner(self.frame, self.parent == YBar.topFrame and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
    if self.moduleType~="CurrencyTracker" and self.moduleType~="SeasonCrests" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff808080"..LC["common.alt_left_click"]..": "..LC["common.open_settings"].."|r")
    end
    GameTooltip:Show()
end
