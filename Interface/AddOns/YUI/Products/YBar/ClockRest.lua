-- Resting indicators use cached native animations; state changes never relayout the bar.
local YUI = _G.YUI
local YBar, GUI2 = YUI.YBar, YUI.GUI2
local Security = YUI.API and YUI.API.Security or YUI.WOW_API
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API
local Rest = {}
YBar.ClockRest = Rest
Rest.views = setmetatable({}, {__mode="k"})
local styles = { zzz=true, moon=true, dots=true, cup=true }
local positions = { right=true, corner=true, corner_top=true, corner_bottom=true,
    top=true, bottom=true, auto=true, symmetric=true }
local scales = { small=.45, medium=.65, large=.85 }
local minimumScales = { small=1, medium=1.3, large=1.6 }
local minimumPixels = { zzz=10, moon=14, dots=18, cup=18 }
local atlas

local function PixelSize(region, pixels)
    return GUI2.GetPixelSize and GUI2:GetPixelSize(region, pixels) or pixels
end

local function Snap(region, value)
    return GUI2.SnapLayoutBoundary and GUI2:SnapLayoutBoundary(region, value) or value
end

function Rest.Resolve(db)
    local style = styles[db.restStyle] and db.restStyle or "zzz"
    local position = positions[db.restPosition] and db.restPosition or "corner"
    if position == "symmetric" and style ~= "dots" then position = "right" end
    local size = scales[db.restSize] and db.restSize or "small"
    return style, position, size
end

function Rest.ReadResting()
    if type(IsResting) ~= "function" then return false end
    local ok, value = pcall(IsResting)
    if not ok then return false end
    if Security.SafeBoolean then
        local boolean = Security.SafeBoolean(value)
        if type(boolean) == "boolean" then return boolean end
        if not Security.IsSecretValue then return false end
    end
    if Security.IsSecretValue and Security.IsSecretValue(value) then return false end
    return value == true or value == 1
end

function Rest.ValidateLevel(value)
    if Security.SafeNumber then value = Security.SafeNumber(value)
    elseif not Security.IsSecretValue or Security.IsSecretValue(value) then return nil end
    if type(value) ~= "number" or value <= 0 or value == math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

local function ReadLevel(read, ...)
    if type(read) ~= "function" then return nil end
    local ok, value = pcall(read, ...)
    return ok and Rest.ValidateLevel(value) or nil
end

function Rest.ReadPlayerLevel()
    if type(UnitAPI.GetPlayerLevel) == "function" then return ReadLevel(UnitAPI.GetPlayerLevel) end
    return ReadLevel(UnitLevel, "player")
end

function Rest.ReadMaxPlayerLevel()
    return ReadLevel(UnitAPI.GetMaxPlayerLevel)
end

function Rest.ReadAtMaxLevel(newLevel)
    local level = Rest.ValidateLevel(newLevel) or Rest.ReadPlayerLevel()
    local maximum = Rest.ReadMaxPlayerLevel()
    -- Unknown levels do not establish that the player has reached the cap.
    return level ~= nil and maximum ~= nil and level >= maximum
end

function Rest.GetColor(color)
    local r, g, b, a = GUI2:GetColor("color.text.accent")
    if type(color) == "table" then
        return color[1] or color.r or r, color[2] or color.g or g,
            color[3] or color.b or b, color[4] or color.a or a
    end
    return r, g, b, a
end

function Rest.IsTop(parent)
    if parent == YBar.topFrame or (parent and parent.ybarLayoutId == "top") then return true end
    if parent == YBar.bottomFrame or (parent and parent.ybarLayoutId == "bottom") then return false end
    local y
    if parent and type(parent.GetCenter) == "function" then
        local _, centerY = parent:GetCenter()
        y = centerY
    end
    return type(y) == "number" and UIParent and y > UIParent:GetHeight() / 2 or false
end

local function Texture(parent, cell)
    atlas = atlas or YUI.Assets:Product("ybar", "clock\\rest.png")
    local texture = GUI2:CreateTexture(parent, {texture=atlas, layer="OVERLAY"})
    -- Smooth subpixel motion; the default texel bias can erase tiny rounded strokes.
    if GUI2.ApplyTexturePixelPolicy then GUI2:ApplyTexturePixelPolicy(texture) end
    texture:SetTexCoord(cell / 4, (cell + 1) / 4, 0, 1)
    -- The paint helper applies a solid texture, so tint this atlas via the theme registry.
    texture.RefreshTheme = function(self)
        self:SetVertexColor(Rest.GetColor(self.restColor))
    end
    texture:RefreshTheme()
    GUI2:RegisterThemeObject(texture)
    texture:Hide()
    return texture
end

local function EnsureAnimation(part, floating)
    if part.restGroup or type(part.CreateAnimationGroup) ~= "function" then return end
    local group = part:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    if floating then
        part.restDelay = group:CreateAnimation("Alpha")
        part.restDelay:SetOrder(1); part.restDelay:SetFromAlpha(0); part.restDelay:SetToAlpha(0)
    end
    local fadeIn = group:CreateAnimation("Alpha")
    fadeIn:SetOrder(floating and 2 or 1); fadeIn:SetFromAlpha(floating and 0 or .25); fadeIn:SetToAlpha(1)
    fadeIn:SetSmoothing("IN_OUT")
    local fadeOut = group:CreateAnimation("Alpha")
    fadeOut:SetOrder(floating and 3 or 2); fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(floating and 0 or .25)
    fadeOut:SetSmoothing("IN_OUT")
    if floating then
        part.restMove = group:CreateAnimation("Translation")
        part.restMove:SetOrder(2)
        part.restHold = group:CreateAnimation("Alpha")
        part.restHold:SetOrder(4); part.restHold:SetFromAlpha(0); part.restHold:SetToAlpha(0)
    end
    part.restGroup, part.restFadeIn, part.restFadeOut = group, fadeIn, fadeOut
end

local function ConfigureAnimation(part, distance, delay)
    EnsureAnimation(part, distance ~= nil)
    if not part.restGroup then return end
    local floating = distance ~= nil
    part.restFadeIn:SetDuration(floating and .65 or 1.3)
    part.restFadeIn:SetStartDelay(0)
    part.restFadeOut:SetDuration(floating and 1.05 or 1.3)
    if floating then
        part.restMove:SetDuration(1.7)
        part.restMove:SetStartDelay(0)
        part.restMove:SetOffset(0, distance)
        local phaseDelay = math.max(.01, delay or 0)
        part.restDelay:SetDuration(phaseDelay)
        part.restHold:SetDuration(.9 - phaseDelay)
    end
end

local function Place(part, parent, width, height, x, y)
    part:ClearAllPoints(); part:SetSize(Snap(parent, width), Snap(parent, height))
    part:SetPoint("CENTER", parent, "CENTER", Snap(parent, x), Snap(parent, y))
end

function Rest.New(content)
    if Rest.views[content] then return Rest.views[content] end
    local self = setmetatable({parts={}, active=false, configured=false, sideReserve=0}, {__index=Rest})
    self.frame = GUI2:CreateFrame(content, {width=1, height=1})
    self.frame:EnableMouse(false)
    self.text = GUI2:CreateText(self.frame, "zZZ", "font.size.sm", "color.text.accent")
    self.text.RefreshTheme = function(text) text:SetTextColor(Rest.GetColor(text.restColor)) end
    self.text:Hide()
    self.icon = Texture(self.frame, 0)
    self.dots, self.steam = {}, {}
    for i=1,6 do self.dots[i]=Texture(self.frame, 2) end
    for i=1,2 do
        self.steam[i]=Texture(self.frame, 3)
        self.steam[i]:SetTexCoord(213/256, 235/256, 8/64, 56/64)
    end
    self.frame:Hide()
    Rest.views[content] = self
    return self
end

function Rest:ApplyColor(color)
    self.text.restColor = color; self.text:RefreshTheme()
    self.icon.restColor = color; self.icon:RefreshTheme()
    for i=1,6 do self.dots[i].restColor=color; self.dots[i]:RefreshTheme() end
    for i=1,2 do self.steam[i].restColor=color; self.steam[i]:RefreshTheme() end
end

function Rest:SetActive(active)
    active = active == true and self.configured
    if self.active == active then return end
    self.active = active
    if active then
        self.frame:Show()
        for i=1,#self.parts do
            local part = self.parts[i]
            part:Show(); part:SetAlpha(1)
            if part.restGroup and part.restAnimate ~= false then part.restGroup:Play() end
        end
    else
        for i=1,#self.parts do
            local part = self.parts[i]
            if part.restGroup then part.restGroup:Stop() end
            part:Hide()
        end
        self.frame:Hide()
    end
end

function Rest:UpdateDirection(parent)
    if not self.configured or (self.position ~= "corner" and self.position ~= "auto") then return end
    local top = Rest.IsTop(parent)
    if self.top == top then return end
    self.top, self.placementY = top, -self.placementY
    self:ApplyAnchor()
end

function Rest:ApplyAnchor()
    self.anchorY = Snap(self.frame, self.placementY + self.textCenterOffset)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", self.anchorRegion, "CENTER", self.anchorX, self.anchorY)
end

function Rest:Configure(db, clockWidth, font, fontSize, globalDB, applyTextStyle, parent)
    self:SetActive(false)
    self.text:Hide(); self.icon:Hide()
    for i=1,6 do self.dots[i]:Hide() end
    for i=1,2 do self.steam[i]:Hide() end
    for i=#self.parts,1,-1 do self.parts[i]=nil end
    self:ApplyColor(db.restColor)
    local style, position, size = Rest.Resolve(db)
    local minimum = minimumPixels[style] * minimumScales[size]
    local edge = Snap(self.frame, math.max(PixelSize(self.frame, minimum), fontSize * scales[size]))
    local width, height = edge, edge
    if style == "zzz" then
        applyTextStyle(self.text, font, edge, globalDB)
        self.text:SetText("zZZ")
        width, height = math.ceil(self.text:GetStringWidth() or edge * 2), edge + 2
        self.text:ClearAllPoints(); self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        ConfigureAnimation(self.text)
        self.text.restAnimate = true
        self.parts[1] = self.text
    elseif style == "moon" then
        self.icon:SetTexCoord(0, .25, 0, 1)
        Place(self.icon, self.frame, edge, edge, 0, 0)
        ConfigureAnimation(self.icon)
        self.icon.restAnimate = true
        self.parts[1] = self.icon
    elseif style == "cup" then
        self.icon:SetTexCoord(.25, .5, 0, 1)
        Place(self.icon, self.frame, edge, edge, 0, 0)
        self.icon.restAnimate = false
        self.parts[1] = self.icon
        for i=1,2 do
            local steam = self.steam[i]
            Place(steam, self.frame, math.max(PixelSize(self.frame, 3), edge * .18), edge * .36,
                (i==1 and -.13 or .13)*edge, edge * .24)
            ConfigureAnimation(steam, edge * .18, (i-1)*.42)
            self.parts[#self.parts+1] = steam
        end
    else
        local count = position == "symmetric" and 6 or 3
        for i=1,count do
            local slot = (i-1)%3
            local x = (slot-1)*edge*.32
            if position == "symmetric" then
                x = (i<=3 and -1 or 1)*(clockWidth/2 + 4 + edge/2 + x)
            end
            local dot = self.dots[i]
            local diameter = math.max(PixelSize(self.frame, slot==1 and 4 or 3), edge * (slot==1 and .22 or .17))
            local y = (slot==0 and -.18 or slot==2 and .10 or 0)*edge
            Place(dot, self.frame, diameter, diameter, x, y)
            ConfigureAnimation(dot, edge*.18, slot*.25)
            self.parts[#self.parts+1] = dot
        end
    end
    self.frame:SetSize(width, height)
    local content = self.frame:GetParent()
    self.anchorRegion = content.textSep or content
    -- Digit glyphs sit above the font line box center. Texture centers need the
    -- full optical lift; zZZ already has its own, smaller font's line descent.
    self.textCenterOffset = (fontSize - (style == "zzz" and edge or 0)) * .1
    local top = Rest.IsTop(parent)
    local halfClock, gap = clockWidth/2, 4
    local x, y = 0, 0
    self.sideReserve = 0
    if position == "right" then
        x = halfClock+gap+width/2
        self.sideReserve = gap+width
    elseif position == "corner" or position == "corner_top" or position == "corner_bottom" then
        local upper = position == "corner_top" or (position == "corner" and not top)
        x, y = halfClock+gap+width/2, (upper and 1 or -1)*math.abs(fontSize-height)/2
        self.sideReserve = gap+width
    elseif position == "symmetric" then
        self.sideReserve = gap+edge
    else
        local upper = position == "top" or (position == "auto" and not top)
        y = (upper and 1 or -1)*(fontSize/2+gap+height/2)
    end
    if db.restEnabled == false then self.sideReserve = 0 end
    self.anchorX, self.placementY, self.top = Snap(self.frame, x), y, top
    self:ApplyAnchor()
    self.style, self.position, self.configured = style, position, true
end

return Rest
