-- Non-interactive visual snapshots keep secure module hosts parked during design.
local Snapshot={}
Snapshot.__index=Snapshot
local function Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
function Snapshot.New(gui,parent)
    local frame=gui:CreateFrame(parent,{width=40,height=20})
    frame:EnableMouse(false)
    return setmetatable({gui=gui,frame=frame,texts={},icons={}},Snapshot)
end
function Snapshot:Update(source)
    local left,bottom=Public(source:GetLeft()),Public(source:GetBottom())
    if not left or not bottom then return end
    local texts,icons=0,0
    local function visit(frame,depth)
        if depth>4 or not frame:IsShown() then return end
        for _,region in ipairs({frame:GetRegions()}) do
            if region:IsShown() then
                local x,y=Public(region:GetLeft()),Public(region:GetBottom())
                local width,height=Public(region:GetWidth()),Public(region:GetHeight())
                if x and y and width and height and width>0 and height>0 then
                    local target
                    if region:IsObjectType("FontString") then
                        local text=Public(region:GetText())
                        if text then
                            texts=texts+1;target=self.texts[texts]
                            if not target then target=self.gui:CreateText(self.frame,"");self.texts[texts]=target end
                            local font,size,flags=region:GetFont()
                            if Public(font) and Public(size) then target:SetFont(font,size,Public(flags)) end
                            target:SetText(text);target:SetJustifyH(region:GetJustifyH())
                            local r,g,b,a=region:GetTextColor()
                            if Public(r) and Public(g) and Public(b) and Public(a) then target:SetTextColor(r,g,b,a) end
                            if region.GetShadowOffset and target.SetShadowOffset then
                                local sx,sy=region:GetShadowOffset()
                                if Public(sx) and Public(sy) then target:SetShadowOffset(sx,sy) end
                            end
                            if region.GetShadowColor and target.SetShadowColor then
                                local sr,sg,sb,sa=region:GetShadowColor()
                                if Public(sr) and Public(sg) and Public(sb) and Public(sa) then target:SetShadowColor(sr,sg,sb,sa) end
                            end
                        end
                    elseif region:IsObjectType("Texture") and not region:IsObjectType("MaskTexture") then
                        local texture=Public(region:GetTexture())
                        local atlas=region.GetAtlas and Public(region:GetAtlas())
                        if atlas or texture and (type(texture)=="number" or type(texture)=="string") then
                            icons=icons+1;target=self.icons[icons]
                            if not target then
                                target=self.gui:CreateTexture(self.frame,{layer="ARTWORK"});self.icons[icons]=target
                            end
                            if atlas then target:SetAtlas(atlas) else target:SetTexture(texture) end
                            local coords={region:GetTexCoord()}
                            local valid=true
                            for _,value in ipairs(coords) do if not Public(value) then valid=false;break end end
                            if valid then target:SetTexCoord(unpack(coords)) end
                            local r,g,b,a=region:GetVertexColor()
                            if Public(r) and Public(g) and Public(b) and Public(a) then target:SetVertexColor(r,g,b,a) end
                        end
                    end
                    if target then
                        if target.SetAlpha and region.GetAlpha then
                            local alpha=Public(region:GetAlpha());if alpha then target:SetAlpha(alpha) end
                        end
                        if target.SetDrawLayer and region.GetDrawLayer then
                            local layer,sub=region:GetDrawLayer()
                            if Public(layer) and Public(sub) then target:SetDrawLayer(layer,sub) end
                        end
                        target:ClearAllPoints();target:SetPoint("BOTTOMLEFT",self.frame,"BOTTOMLEFT",x-left,y-bottom)
                        target:SetSize(width,height);target:Show()
                    end
                end
            end
        end
        for _,child in ipairs({frame:GetChildren()}) do visit(child,depth+1) end
    end
    visit(source,0)
    for i=texts+1,#self.texts do self.texts[i]:Hide() end
    for i=icons+1,#self.icons do self.icons[i]:Hide() end
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Snapshot=Snapshot
end
return Snapshot
