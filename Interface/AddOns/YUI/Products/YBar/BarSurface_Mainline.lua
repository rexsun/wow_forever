-- Background chrome is independent from measured module geometry.
local Surface={}
local solidColor={0.06,0.08,0.11,0.88}
local materialColor={1,1,1,0.9}
local borderColor={0.28,0.35,0.42,1}
local transparent={0,0,0,0}
local function PaintRounded(frame)
    local color=frame.ybarColor
    if color then
        for _,part in ipairs(frame.gui2SolidParts) do part:SetColorTexture(color[1],color[2],color[3],color[4] or 1) end
    end
    frame:UpdateSolidRoundedLayout()
end
-- Keep old profiles readable without adding retired choices to the editor.
function Surface.Resolve(config)
    config=config or {}
    local preset=config.preset or "none"
    local hidden=preset=="none"
    if hidden then preset="none"
    elseif preset=="legacy" or preset=="custom" then preset="legacy"
    elseif preset=="rounded" or preset=="native" then preset="rounded"
    else preset="solid" end
    local color=config.color or (hidden and transparent or preset=="legacy" and materialColor or solidColor)
    if type(color[1])=="table" then color=color[1] end
    return preset,color,config.borderColor or (hidden and transparent or borderColor)
end
function Surface.New(gui,media,unit)
    return setmetatable({gui=gui,media=media,unit=unit,cache=setmetatable({},{__mode="k"})},{__index=Surface})
end
function Surface:Apply(host,config)
    config=config or {}
    local gui=self.gui
    local frame=host.ybarSurface
    if not frame then
        frame=gui:CreateFrame(host,{template="BackdropTemplate",radius=0})
        frame:SetAllPoints(host);frame:SetFrameLevel(host:GetFrameLevel())
        frame:EnableMouse(false)
        frame.fill=gui:CreateTexture(frame,{layer="BACKGROUND"});frame.fill:SetAllPoints(frame)
        gui:CreateBorder(frame,"color.border.subtle")
        host.ybarSurface=frame
    end
    if host.bg then host.bg:Hide() end
    local preset,color,border=Surface.Resolve(config)
    local r,g,b,a=color[1],color[2],color[3],color[4] or 1
    if preset~="none" and config.classColor==true then
        r,g,b=gui:GetColor("color.class.primary")
    end
    -- A fixed top/bottom bar can be shorter than two native edge tiles.
    local edgeSize=preset=="rounded" and math.min(gui:GetPixelSize(frame,16,1),host:GetWidth()/2,host:GetHeight()/2) or 0
    local key=table.concat({edgeSize,preset,tostring(config.texture),r,g,b,a,border[1],border[2],border[3],border[4] or 1},":")
    if self.cache[host]==key then return end
    self.cache[host]=key
    frame:ClearBackdrop()
    frame.fill:Hide()
    if frame.rounded then frame.rounded:Hide() end
    gui:SetBorderColor(frame,0,0,0,0)
    frame:SetShown(preset~="none")
    if preset=="none" then return end
    if preset=="rounded" then
        if not frame.rounded then
            frame.rounded=gui:CreateSolidRoundedSurface(frame,{radiusPixels=8,mouse=false})
            frame.rounded:SetAllPoints(frame)
            frame.rounded.RefreshTheme=PaintRounded
            frame.rounded.edge=gui:CreateFrame(frame.rounded,{template="BackdropTemplate",mouse=false,radius=0})
            frame.rounded.edge:SetAllPoints(frame.rounded)
        end
        local fillColor=frame.rounded.ybarColor or {}
        fillColor[1],fillColor[2],fillColor[3],fillColor[4]=r,g,b,a
        frame.rounded.ybarColor=fillColor;PaintRounded(frame.rounded);frame.rounded:Show()
        -- Standard GUI2 rounded edge; the fill remains independently transparent.
        frame.rounded.edge:SetBackdrop({edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=math.max(edgeSize,1)})
        frame.rounded.edge:SetBackdropBorderColor(border[1],border[2],border[3],border[4] or 1)
    else
        frame.fill:SetVertexColor(1,1,1,1)
        if preset=="legacy" then
            local texture=self.media and self.media:Fetch("statusbar",config.texture or "None",true)
            frame.fill:SetTexture(texture or nil)
            frame.fill:SetVertexColor(r,g,b,a)
            frame.fill:SetShown(not not texture)
        else
            frame.fill:SetColorTexture(r,g,b,a);frame.fill:Show()
        end
        gui:SetBorderColor(frame,border[1],border[2],border[3],border[4] or 1)
    end
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Surface=Surface
end
return Surface
