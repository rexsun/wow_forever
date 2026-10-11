local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local MapEnhancement = YUI.YMap.Markers or {}
YUI.YMap.Markers = MapEnhancement

local PinMixin = _G.YUIMapMarkersPinMixin or {}
_G.YUIMapMarkersPinMixin = PinMixin

local QuickFilterButtonMixin = _G.YUIMapMarkersQuickFilterButtonMixin or {}
_G.YUIMapMarkersQuickFilterButtonMixin = QuickFilterButtonMixin

local LABEL_SCALE_FACTOR = 1.0
local LABEL_MIN_SCALE = 0.88
local LABEL_MAX_SCALE = 1.12
local LABEL_FRAME_LEVEL = "PIN_FRAME_LEVEL_MAP_LINK"

function QuickFilterButtonMixin:OnLoad()
    self:RegisterForClicks("AnyUp")

end

function QuickFilterButtonMixin:Refresh()
    -- MapEnhancement owns the button state; WorldMap overlays require this method.
end

function QuickFilterButtonMixin:OnClick(button)
    if MapEnhancement.HandleQuickFilterClick then
        MapEnhancement:HandleQuickFilterClick(button)
    end
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self)
        and MapEnhancement.ShowQuickFilterTooltip then
        MapEnhancement:ShowQuickFilterTooltip(self)
    end
end

function QuickFilterButtonMixin:OnEnter()
    if MapEnhancement.ShowQuickFilterTooltip then
        MapEnhancement:ShowQuickFilterTooltip(self)
    end
end

function QuickFilterButtonMixin:OnLeave()
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function T(key, fallback)
    local locale = YUI.Locale and YUI.Locale:Get("YMapMarkers") or nil
    local value = locale and locale[key]
    if not value or value == "" or value == key then return fallback or key end
    return value
end

local function MemberLabel(entry)
    return entry.displayLabel or entry.resolvedLabel or T(entry.labelKey)
end

-- 根据官方纹理 alpha 覆盖面积校准视觉重量，而非统一放大 atlas 外框。
local ATLAS_VISUAL_SCALE = {
    Banker=1.19, Auctioneer=1.18, Innkeeper=1.30,
    ["Vehicle-SilvershardMines-MineCartBlue"]=1.38,
    FlightMasterFerry=1.22, ["Fishing-Hole"]=1.36,
}
local function IconVisualScale(member)
    if member.taxiNodeID or member.typeID == "travel.flight" then return 1.2 end
    if member.typeID == "service.guild" then return 1.3 end
    if member.trainerClasses then return 1.30 end
    return ATLAS_VISUAL_SCALE[member.atlas] or 1
end

-- 与原生 Pin 的有限缩放保持一致，避免缩小时图标变小而空隙不变。
function MapEnhancement:GetIconLayoutScale(map)
    local zoom=map.GetCanvasZoomPercent and map:GetCanvasZoomPercent() or .5
    zoom=math.max(0,math.min(1,zoom or .5))
    return LABEL_MIN_SCALE+(LABEL_MAX_SCALE-LABEL_MIN_SCALE)*zoom
end

local function IconDiameter(member,size)
    return member.category=="profession" and not member.atlas and size+2 or size*IconVisualScale(member)
end

-- 图标聚合只使用筛选后的地点；中心到每个成员都不得超过半个图标。
function MapEnhancement:GroupVisibleIcons(points,width,height,pairSpacing)
    local groups,membership = {},{}
    local limit = self:GetConfig().iconSize/2
    for _,point in ipairs(points) do
        local target,cx,cy
        if not point.taxiNodeID then
            for _,group in ipairs(groups) do
                if not group.taxiNodeID then
                    local n = #group.members
                    local x,y = (group.x*n+point.x)/(n+1),(group.y*n+point.y)/(n+1)
                    local memberLimit=limit
                    if pairSpacing and n==1 then
                        memberLimit=(IconDiameter(point,limit*2)+IconDiameter(group.members[1],limit*2))/4+.75
                    end
                    local fits = ((point.x-x)*width)^2+((point.y-y)*height)^2 <= memberLimit^2
                    if fits then
                        for _,member in ipairs(group.members) do
                            if ((member.x-x)*width)^2+((member.y-y)*height)^2 > memberLimit^2 then fits=false; break end
                        end
                    end
                    if fits then target,cx,cy=group,x,y; break end
                end
            end
        end
        if target then
            target.members[#target.members+1]=point
            target.x,target.y=cx,cy
            target.hub=true
            target.professionGroup=target.professionGroup and point.category=="profession"
            target.category=target.professionGroup and "profession" or "service"
        else
            target={id=point.id,x=point.x,y=point.y,members={point},taxiNodeID=point.taxiNodeID,
                professionGroup=point.category=="profession"}
            setmetatable(target,{__index=point})
            groups[#groups+1]=target
        end
        membership[point.id]=target.id
    end
    return groups,membership
end

-- 独立点保持原始位置，合集使用受约束的中心；不再二次推移邻居。
function MapEnhancement:LayoutVisibleIcons(pins,width,height)
    for _,pin in ipairs(pins) do
        local entry=pin.entry
        if entry.layoutX~=entry.x or entry.layoutY~=entry.y then
            entry.layoutX,entry.layoutY=entry.x,entry.y
            pin:SetPosition(entry.x,entry.y)
        end
    end
end

-- 在已排布的可见组之间检查双点展开；只试原方向及垂直方向，不连续向外推。
function MapEnhancement:PrepareVisibleIconGroups(points,width,height)
    local groups,membership=self:GroupVisibleIcons(points,width,height,true)
    local pins={}
    for _,group in ipairs(groups) do pins[#pins+1]={entry=group,SetPosition=function()end} end
    self:LayoutVisibleIcons(pins,width,height)
    local size=self:GetConfig().iconSize
    local function extent(member) return (size*IconVisualScale(member)+4)*LABEL_MAX_SCALE*1.08*1.06 end
    local result={}
    for index=1,#pins do
        local group=groups[index]
        local split
        if #group.members==2 then
            local a,b=group.members[1],group.members[2]
            local ea,eb=extent(a),extent(b)
            -- 双点内部只按可见图案/实心描边留缝；阴影与 hover 余量仅用于外围避障。
            local da=IconDiameter(a,size)
            local db=IconDiameter(b,size)
            local gap=(da+db)/2+1.5
            local dx,dy=(b.x-a.x)*width,(b.y-a.y)*height
            local distance=math.sqrt(dx*dx+dy*dy)
            local ux,uy=distance>0 and dx/distance or 1,distance>0 and dy/distance or 0
            for attempt=1,2 do
                local ox,oy=ux*gap/2,uy*gap/2
                if attempt==2 then ox,oy=-oy,ox end
                local candidates={
                    {member=a,x=group.x*width-ox,y=group.y*height-oy,extent=ea},
                    {member=b,x=group.x*width+ox,y=group.y*height+oy,extent=eb},
                }
                local free=true
                for _,candidate in ipairs(candidates) do
                    local radius=candidate.extent/2
                    if (candidate.x-candidate.member.x*width)^2+(candidate.y-candidate.member.y*height)^2>(radius+2)^2
                        or candidate.x-radius<0 or candidate.x+radius>width or candidate.y-radius<0 or candidate.y+radius>height then free=false;break end
                    for _,other in ipairs(groups) do
                        if other~=group then
                            local e=extent(other.members[1])
                            local extra=other.hub and (self:GetConfig().fontSize*#tostring(#other.members)+6)*LABEL_MAX_SCALE or 0
                            local x,y=other.layoutX*width,other.layoutY*height
                            if candidate.x+radius>x-e/2 and candidate.x-radius<x+e/2+extra
                                and math.abs(candidate.y-y)<(candidate.extent+e)/2 then free=false;break end
                        end
                    end
                    if not free then break end
                end
                if free then split=candidates;break end
            end
        end
        if split then
            -- 后续双点也必须避开本次展开的两个实际位置。
            for _,candidate in ipairs(split) do
                local member=candidate.member
                local entry=setmetatable({id=member.id,members={member},x=member.x,y=member.y,tightPair=true,
                    layoutX=candidate.x/width,layoutY=candidate.y/height},{__index=member})
                result[#result+1]=entry
            end
            group.layoutX,group.layoutY=result[#result-1].layoutX,result[#result-1].layoutY
            group.members={split[1].member}
            group.hub=nil
            groups[#groups+1]=result[#result]
        else
            result[#result+1]=group
        end
    end
    return result,membership
end

function PinMixin:SetHovered(hovered)
    self.isHovered = hovered == true
    for index, slot in ipairs(self.iconBorders or {}) do
        if self.icons[index] then
            slot:SetScale(self.isHovered and 1.08 or 1)

        end
    end
end

-- 只在正式服刷新时组装固定文字，缩放复用这些条目，不按距离重新分组。
function MapEnhancement:PrepareRetailTextEntries(points, mapID)
    local data, entries, byID, detail, bundled = self.Data, {}, {}, {}, {}
    for _, point in ipairs(points) do byID[point.id] = point end
    for _, definition in ipairs(data.groups[mapID] or {}) do
        local members = {}
        for _, id in ipairs(definition.members) do
            detail[id] = true
            if byID[id] then members[#members + 1] = byID[id] end
        end
        if #members > 0 then
            entries[#entries + 1] = {
                id = definition.id, labelKey = definition.labelKey, tooltipKey = definition.tooltipKey,
                x = definition.x, y = definition.y, category = "profession", members = members,
                retailSummary = true, zoomVisibility = "compact", waypoint = false,
            }
        end
    end
    local function add(members)
        if #members == 0 then return end
        local first = members[1]
        entries[#entries + 1] = setmetatable({members = members,
            zoomVisibility = (detail[first.id] or data.detailTextPoints[first.id]) and "detail" or nil,
        }, {__index = first})
    end
    for _, ids in ipairs(data.textBundles[mapID] or {}) do
        local members = {}
        for _, id in ipairs(ids) do
            bundled[id] = true
            if byID[id] then members[#members + 1] = byID[id] end
        end
        add(members)
    end
    for _, point in ipairs(points) do
        if not bundled[point.id] then add({point}) end
    end
    return entries
end

local function ResolveDisplayLabel(entry)
    local config = MapEnhancement:GetConfig()
    if YUI.IsRetail and entry.retailSummary then return T(entry.labelKey) end
    if entry.hub then
        if config.displayMode == "icon" then return tostring(#entry.members) end
        return T("cluster.professions")
    end
    local labels = {}
    for _, member in ipairs(entry.members or {entry}) do
        if (not YUI.IsRetail and member.taxiNodeID) or config.displayMode == "icon" then
            labels[#labels+1] = ""
        else
            local label = MemberLabel(member)
            if YUI.IsRetail and MapEnhancement:IsCompactZoom() then
                local key = MapEnhancement.Data.compactTextLabels[member.typeID]
                if key then label = T(key) end
            end
            local color = member.resolvedColor or MapEnhancement:GetCategoryColor(member.category,config)
            if color then
                label = string.format("|cff%02x%02x%02x%s|r",math.floor((color.r or color[1])*255),math.floor((color.g or color[2])*255),math.floor((color.b or color[3])*255),label)
            end
            labels[#labels+1] = label
        end
    end
    return table.concat(labels,config.displayMode == "icon" and " " or "\n")
end

local function UpdateLabelSize(pin)
    local width = math.max(24, pin.Label:GetStringWidth() + 8)
    local height = math.max(16, pin.Label:GetStringHeight() + 4)
    pin:SetSize(width, height)
end

local function ApplyCurrentScaleIfReady(pin)
    if not (pin and type(pin.ApplyCurrentScale) == "function") then return false end
    local map = type(pin.GetMap) == "function" and pin:GetMap() or nil
    if not (map and type(map.HasZoomLevels) == "function" and map:HasZoomLevels()) then
        return false
    end
    pin:ApplyCurrentScale()
    return true
end

local function SetWaypoint(entry)
    if not (entry and C_Map and UiMapPoint and C_SuperTrack) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(entry.mapID) then return false end
    local point = UiMapPoint.CreateFromCoordinates(entry.mapID, entry.x, entry.y)
    if not point or not C_Map.SetUserWaypoint(point) then return false end
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end

function PinMixin:OnLoad()
    self:HookScript("OnHide",function(owner) owner:CloseExpansion(true) end)
    if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
    if self.SetScalingLimits then
        self:SetScalingLimits(LABEL_SCALE_FACTOR, LABEL_MIN_SCALE, LABEL_MAX_SCALE)
    end
    if self.UseFrameLevelType then self:UseFrameLevelType(LABEL_FRAME_LEVEL) end
end

function PinMixin:OnAcquired(entry)
    self.Label:Show()
    self:SetHovered(false)
    self.entry = entry
    self.retailLabelCompact = nil
    self.dataProvider = entry and entry.dataProvider or nil

    local config = MapEnhancement.GetConfig and MapEnhancement:GetConfig() or {}
    local fontPath = STANDARD_TEXT_FONT
    if GameFontNormalSmall and GameFontNormalSmall.GetFont then
        fontPath = GameFontNormalSmall:GetFont() or fontPath
    end

    local size = tonumber(config.fontSize) or 11
    self.Label:SetFont(fontPath, size, config.fontOutline or "OUTLINE")
    if self.Label.SetWordWrap then self.Label:SetWordWrap(true) end
    PinMixin.ApplyZoomLabel(self)

    local category = MapEnhancement.Data and MapEnhancement.Data.categories[entry.category]
    local color = MapEnhancement.GetCategoryColor and MapEnhancement:GetCategoryColor(entry.category, config)
        or category and category.color or { 1, 1, 1 }
    local classColor = entry.resolvedColor
    if classColor then
        self.Label:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
    else
        self.Label:SetTextColor(color[1], color[2], color[3], 1)
    end

    self:SetPosition(entry.x, entry.y)
    ApplyCurrentScaleIfReady(self)
    self:UpdateIcons()
    self:ApplyZoomVisibility()
end

-- 图标使用 GUI2 标准裁剪与像素策略，Pin 池复用最多两个 Texture。
function PinMixin:UpdateIcons()
    local entry, config = self.entry, MapEnhancement:GetConfig()
    if not entry then return end
    self.Label:Show()
    local members = entry.members or {entry}
    local icons = not YUI.IsRetail and (config.displayMode == "icon" or members[1].taxiNodeID)
    self.icons = self.icons or {}
    self.iconBorders = self.iconBorders or {}
    local count = icons and (entry.hub and 1 or #members) or 0
    local size = config.iconSize
    local dx,dy = 0,0
    if entry.layoutX then
        self:SetPosition(entry.layoutX,entry.layoutY)

    end
    if count == 2 then
        local map = self.GetMap and self:GetMap()
        local canvas = map and map.GetCanvas and map:GetCanvas()
        local width = canvas and canvas:GetWidth() or 1000
        local height = canvas and canvas:GetHeight() or 668
        local pinScale = self.GetScale and self:GetScale() or 1
        -- Frame 坐标换算后仍落在各成员的真实投影上，只沿重叠较少的一轴推开。
        dx = (members[2].x-members[1].x)*width/pinScale
        dy = (members[1].y-members[2].y)*height/pinScale
        dx,dy = MapEnhancement:SeparateIconPair(dx,dy,size)
    end
    for index=1,count do
        local member = members[index]
        local slot = self.iconBorders[index]
        if not slot then
            slot = YUI.GUI:CreateIconSlot(self,{icon=member.icon,size=size,variant="bare",shape="square",border="none",animate=false})
            slot:EnableMouse(false)
            self.iconBorders[index] = slot
            self.icons[index] = slot.icon
        end
        local texture = slot.icon
        local rounded = member.category == "profession" and not member.atlas
        slot:SetIconAppearance({size=size,shape=rounded and "circle" or "square",border="none",zoom=rounded and 0.08 or 0})
        -- 实心圆底衬被图标覆盖，只露出连续外沿；避免放大空心圆环造成同心圆和透底间隙。
        if rounded then
            if not slot.mapOutline then
                local silhouette = YUI.GUI:GetIconAppearancePreset("circle").mask
                slot.mapOutline = YUI.GUI:CreateIcon(slot,{icon=silhouette,crop=false,layer="BACKGROUND",subLevel=1})
                slot.mapShadow = YUI.GUI:CreateIcon(slot,{icon=silhouette,crop=false,layer="BACKGROUND",subLevel=0})
                slot.mapOutline:SetVertexColor(0.04,0.03,0.02,0.95)
                slot.mapShadow:SetVertexColor(0,0,0,0.30)
                slot.mapOutline:SetPoint("CENTER",slot,"CENTER",0,0)
                slot.mapShadow:SetPoint("CENTER",slot,"CENTER",0,-0.5)
            end
            slot.mapOutline:SetSize(size+2,size+2)
            slot.mapShadow:SetSize(size+4,size+4)
            slot.mapOutline:Show()
            slot.mapShadow:Show()
        elseif slot.mapOutline then
            slot.mapOutline:Hide()
            slot.mapShadow:Hide()
        end
        slot:SetSize(size,size)
        slot:ClearAllPoints()
        slot:SetPoint("CENTER",self,"CENTER",(index == 1 and -0.5 or 0.5)*dx,(index == 1 and -0.5 or 0.5)*dy)
        slot:Show()
        local class = member.trainerClasses and member.trainerClasses[1]
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if member.atlas then
            YUI.GUI:SetIconTexture(texture,"atlas:"..member.atlas)
        elseif coords then
            YUI.GUI:SetIconTexture(texture,"Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            texture:SetTexCoord(unpack(coords))
        else
            YUI.GUI:SetIconTexture(texture,member.icon)
            texture:SetTexCoord(0.08,0.92,0.08,0.92)
        end
        texture:ClearAllPoints()
        texture:SetPoint("CENTER",slot,"CENTER",0,0)
        local visualSize = size*IconVisualScale(member)
        texture:SetSize(visualSize,visualSize)
        texture:SetDesaturated(false)
        texture:SetAlpha(1)
        texture:Show()
    end
    for index=count+1,#self.icons do self.icons[index]:Hide(); if self.iconBorders[index] then self.iconBorders[index]:Hide() end end
    self.Label:ClearAllPoints()
    if icons then
        if entry.hub then self.Label:SetPoint("LEFT",self,"CENTER",size/2+3,0)
        else self.Label:SetPoint("CENTER") end
        if entry.tightPair then
            self:SetSize(size+2,size+2)
        else
            self:SetSize(size+math.abs(dx)+8+(entry.hub and self.Label:GetStringWidth()+3 or 0),
                size+math.abs(dy)+6)
        end
    else
        self.Label:SetPoint("CENTER")
        UpdateLabelSize(self)
    end
end

-- 两点不交换方向；各自的最大额外偏移不超过半个图标加间隔。
function MapEnhancement:SeparateIconPair(dx,dy,size)
    local gap = size+3
    local overlapX,overlapY = gap-math.abs(dx),gap-math.abs(dy)
    if overlapX > 0 and overlapY > 0 then
        if overlapX <= overlapY then dx = (dx < 0 and -1 or 1)*gap
        else dy = (dy < 0 and -1 or 1)*gap end
    end
    return dx,dy
end

function PinMixin:ApplyZoomLabel()
    local entry = self.entry
    if not (entry and self.Label) then return end
    if YUI.IsRetail then
        local compact = MapEnhancement:IsCompactZoom()
        if self.retailLabelCompact == compact then return end
        self.retailLabelCompact = compact
    end
    local label = ResolveDisplayLabel(entry)
    if not self.Label.GetText or self.Label:GetText() ~= label then
        self.Label:SetText(label)
        UpdateLabelSize(self)
    end
end

function PinMixin:ApplyZoomVisibility()
    if not YUI.IsRetail then self:SetShown(true); return end
    local visibility = self.entry and self.entry.zoomVisibility
    local compact = MapEnhancement:IsCompactZoom()
    local shown = visibility == nil or (visibility == "compact" and compact)
        or (visibility == "detail" and not compact)
    if self.retailShown ~= shown then
        self.retailShown = shown
        self:SetShown(shown)
    end
end

function PinMixin:OnCanvasScaleChanged()
    if YUI.IsRetail then
        MapEnhancement:UpdateZoomMode(self:GetMap())
        self:ApplyZoomLabel()
        ApplyCurrentScaleIfReady(self)
        self:ApplyZoomVisibility()
        return
    end
    self:CloseExpansion(true)
    ApplyCurrentScaleIfReady(self)
    self:UpdateIcons()
end

function PinMixin:OnReleased()
    self:CloseExpansion(true)
    self:SetHovered(false)
    YUI.GUI.Tooltip:Hide(self)
    self.entry = nil
    self.dataProvider = nil
    self.retailShown = nil
    self.retailLabelCompact = nil
    for _, texture in ipairs(self.icons or {}) do texture:Hide() end
    for _, border in pairs(self.iconBorders or {}) do border:Hide() end
    if self.Label then self.Label:SetText("") end
    if MapCanvasPinMixin and MapCanvasPinMixin.OnReleased then
        MapCanvasPinMixin.OnReleased(self)
    end
end

local function TooltipMemberLabel(member)
    local label = T(member.tooltipTitleKey or member.labelKey)
    if member.typeID == "service.guild" then label = T("tooltip.guild_registrar")
    elseif member.typeID == "equipment.weapon_trainer" then label = T("tooltip.weapon_trainer")
    elseif member.trainerClasses or member.category == "profession" then
        label = string.format(T("tooltip.trainer_format", "%s Trainer"), label)
    end
    local class = member.trainerClasses and member.trainerClasses[1]
    if class then
        local api = YUI.API and YUI.API.Icons
        local info = api and api.GetClassIcon and api.GetClassIcon(class)
        local coords = info and info.texCoord or CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            local texture = info and info.texture or "Interface\\TargetingFrame\\UI-Classes-Circles"
            local size = YUI.GUI:GetToken("tooltip.icon.size") or 12
            return string.format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t %s",texture,size,size,
                math.floor(coords[1]*256+.5),math.floor(coords[2]*256+.5),
                math.floor(coords[3]*256+.5),math.floor(coords[4]*256+.5),label)
        end
    end
    local icon = member.atlas and "atlas:"..member.atlas or member.icon
    return YUI.GUI.Tooltip:IconText(label,icon)
end

local function ReadProfessionRanks(members)
    local needed = false
    for _, member in ipairs(members) do
        if member.category == "profession" then needed = true; break end
    end
    local api = YUI.API and YUI.API.Profession
    if not needed or not (api and api.GetProfessions and api.GetProfessionInfo) then return nil end
    local ranks = {}
    local indexes = { api.GetProfessions() }
    -- 次要专业位于稀疏返回值末尾，不能使用 ipairs。
    for slot = 1, 6 do
        if indexes[slot] then
            local skillID, _, rank, maximum = api.GetProfessionInfo(indexes[slot])
            if skillID then
                ranks[skillID] = { rank = rank, maximum = maximum }
            end
        end
    end
    return ranks
end

local function AddProfessionRank(body, member, ranks)
    if member.category ~= "profession" then return end
    local skillID = tonumber((member.typeID or ""):match("^profession%.(%d+)$"))
    local info = ranks and ranks[skillID]
    local value, tone
    if info and type(info.rank) == "number" and type(info.maximum) == "number" and info.maximum > 0 then
        value = string.format("%d/%d", info.rank, info.maximum)
        tone = info.rank >= info.maximum and "success" or "body"
    else
        if ranks and not info then return end
        value = T("tooltip.skill_unavailable")
        tone = "secondary"
    end
    body:AddLine(string.format(T("tooltip.skill_rank", "Skill level: %s"), value), tone)
end

function PinMixin:CancelExpansionCollapse()
    if self.collapseTimer then self.collapseTimer:Cancel(); self.collapseTimer=nil end
end

function PinMixin:CloseExpansion(skipRedraw)
    self:CancelExpansionCollapse()
    if YUI.Animation then YUI.Animation:StopOwner(self) end
    if not self.expanded then return end
    self.expanded,self.expansionProgress=nil,nil
    if MapEnhancement.expandedPin==self then MapEnhancement.expandedPin=nil end
    for _,child in ipairs(self.expansionButtons or {}) do
        YUI.GUI.Tooltip:Hide(child)
        child:SetHovered(false)
        child:Hide()
        child.entry,child.expansionOwner=nil,nil
    end
    if self.expansionFrameLevel then self:SetFrameLevel(self.expansionFrameLevel); self.expansionFrameLevel=nil end
    if not skipRedraw and self.entry then self.Label:Show(); self:UpdateIcons(); self:ApplyZoomLabel() end
end

function PinMixin:AnimateExpansion(to)
    if YUI.Animation then YUI.Animation:StopOwner(self) end
    local function update(value)
        self.expansionProgress=value
        for _,child in ipairs(self.expansionButtons or {}) do
            if child.entry then
                child:ClearAllPoints()
                child:SetPoint("CENTER",self,"CENTER",child.expandX*value,child.expandY*value)
            end
        end
    end
    local function finish(_,_,completed) if to==0 and completed~=false then self:CloseExpansion() end end
    local motion=YUI.GUI:PlayControlMotion(self,"map-expand",{owner=self,duration=.16,
        from=self.expansionProgress or 0,to=to,onUpdate=update,onFinished=finish})
    if not motion or motion.noop then update(to);finish() end
end

function PinMixin:ScheduleExpansionCollapse()
    self:CancelExpansionCollapse()
    if not self.expanded then return end
    self.collapseTimer=C_Timer.NewTimer(2,function()
        self.collapseTimer=nil
        if self.expanded then self:AnimateExpansion(0) end
    end)
end

function PinMixin:OpenExpansion()
    self:CancelExpansionCollapse()
    if self.expanded then self:AnimateExpansion(1); return end
    if MapEnhancement.expandedPin then MapEnhancement.expandedPin:CloseExpansion() end
    self.expanded=true
    MapEnhancement.expandedPin=self
    self.expansionFrameLevel=self:GetFrameLevel()
    self:SetFrameLevel(self.expansionFrameLevel+30)
    local members=self.entry.members
    local size=MapEnhancement:GetConfig().iconSize
    local scale=1
    for _,member in ipairs(members) do scale=math.max(scale,IconVisualScale(member)) end
    local step=size*scale+4
    local columns=math.ceil(math.sqrt(#members))
    local rows=math.ceil(#members/columns)
    self.expansionButtons=self.expansionButtons or {}
    for i,member in ipairs(members) do
        local child=self.expansionButtons[i]
        if not child then
            child=YUI.GUI:CreateButtonFrame(self,{width=size+4,height=size+4})
            child.Label=YUI.GUI:CreateText(child,"","font.size.small","color.text.primary")
            child.SetHovered=PinMixin.SetHovered
            child:SetScript("OnEnter",PinMixin.OnMouseEnter)
            child:SetScript("OnLeave",PinMixin.OnMouseLeave)
            child:SetScript("OnClick",PinMixin.OnMouseClickAction)
            self.expansionButtons[i]=child
        end
        child.entry={members={member},mapID=self.entry.mapID,waypoint=member.waypoint}
        child.expansionOwner=self
        child:SetFrameLevel(self:GetFrameLevel()+1)
        child.expandX=((i-1)%columns-(columns-1)/2)*step
        child.expandY=( (rows-1)/2-math.floor((i-1)/columns))*step
        PinMixin.UpdateIcons(child)
        -- 热区紧贴单个图标，避免邻近按钮抢占点击。
        child:SetSize(step-1,step-1)
        child.Label:Hide()
        child:Show()
    end
    for _,slot in ipairs(self.iconBorders or {}) do slot:Hide() end
    self.Label:Hide()
    self:AnimateExpansion(1)
end

function PinMixin:OnMouseEnter()
    if self.expansionOwner then
        self.expansionOwner:CancelExpansionCollapse()
        if self.expansionOwner.expansionProgress ~= 1 then self.expansionOwner:AnimateExpansion(1) end
    elseif self.entry and self.entry.hub and MapEnhancement:GetConfig().displayMode=="icon"
        and YUI.GUI.CreateButtonFrame and YUI.GUI.PlayControlMotion then
        self:OpenExpansion()
    end
    self:SetHovered(true)
    local entry = self.entry
    local config = MapEnhancement.GetConfig and MapEnhancement:GetConfig() or {}
    if not (entry and config.showTooltips ~= false) then return end
    local members = entry.members or {entry}
    local grouped = #members > 1
    local title = grouped and T((entry.professionGroup or entry.category == "profession") and "cluster.professions" or "menu.destination") or TooltipMemberLabel(members[1])
    if entry.retailSummary then title = T(entry.labelKey) end
    YUI.GUI.Tooltip:Show(self, {
        title = title,
        content = function(body)
            if entry.retailSummary and entry.tooltipKey then body:AddLine(T(entry.tooltipKey)) end
            local ranks = ReadProfessionRanks(members)
            for _, member in ipairs(members) do
                if grouped then body:AddLine(TooltipMemberLabel(member)) end
                AddProfessionRank(body, member, ranks)
                if member.weaponTrainerSiteID and YUI.API.WeaponSkill then
                    local description = YUI.API.WeaponSkill.GetTrainerDescription(member.weaponTrainerSiteID)
                    if description then body:AddLine(description) end
                end
                if member.tooltipKey then body:AddLine(T(member.tooltipKey)) end
                if member.flightState and member.flightState ~= "unknown" then body:AddLine(T("flight."..member.flightState)) end
            end
        end,
        actions = config.enableWaypoints ~= false and entry.waypoint ~= false and {
            {button="LeftButton",text=T(grouped and "tooltip.action.choose" or "tooltip.action.waypoint")},
        } or nil,
    })
end

function PinMixin:OnMouseLeave()
    self:SetHovered(false)
    YUI.GUI.Tooltip:Hide(self)
    local owner=self.expansionOwner or self
    if owner.expanded then owner:ScheduleExpansionCollapse() end
end

function PinMixin:OnMouseClickAction(button)
    if button ~= "LeftButton" then return end
    local config = MapEnhancement.GetConfig and MapEnhancement:GetConfig() or {}
    if config.enableWaypoints == false or not self.entry or self.entry.waypoint == false then return end
    local members = self.entry.members
    if members and #members > 1 then
        local choices = {}
        for _, member in ipairs(members) do
            local target = member
            if target.waypoint ~= false then
                choices[#choices+1] = {text=MemberLabel(target),action=function() SetWaypoint(target); MapEnhancement:HideMarkerMenu() end}
            end
        end
        MapEnhancement:ShowMarkerMenu(self,choices)
    else SetWaypoint(members and members[1] or self.entry) end
end

function PinMixin:ShouldMouseButtonBePassthrough(button)
    return button ~= "LeftButton"
end

function PinMixin:CheckMouseButtonPassthrough(...)
    -- 无限服模板已固定右键穿透，Pin 复用时无需再调用受保护的设置。
    if YUI.IsForever then return end
    return MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
end

function MapEnhancement:PreparePinMixin()
    if PinMixin.__yuiBaseReady then return true end
    if type(MapCanvasPinMixin) ~= "table" then return false end
    for key, value in pairs(MapCanvasPinMixin) do
        if PinMixin[key] == nil then PinMixin[key] = value end
    end
    PinMixin.__yuiBaseReady = true
    return true
end

-- 当前地图可见点的屏幕碰撞聚合。每个成员仍保留原始坐标供导航使用。
function MapEnhancement:ClusterPoints(points, width, height, previous)
    local groups, membership = {}, {}
    local independent = self:GetConfig().displayMode == "text" and self.Data.unclusteredTextPoints
    -- 混合服务双点先按距离配对，避免早到的较远地点占用最近邻。
    -- 专业先独立聚合，未聚合的单点再参与混合服务配对。
    local paired = {}
    if self:GetConfig().displayMode == "icon" then
        -- 先保留专业组，避免邻近兽栏/旅店拆走成员后产生跨组重叠。
        local professionGroups = {}
        for _, point in ipairs(points) do
            if point.category == "profession" and not point.taxiNodeID then
                local target
                for _, group in ipairs(professionGroups) do
                    local close = true
                    for _, member in ipairs(group.members) do
                        local slack = previous and previous[point.id] and previous[point.id] == previous[member.id] and 1.15 or 1
                        local dx,dy = math.abs(point.x-member.x)*width,math.abs(point.y-member.y)*height
                        local limitX = math.min(120,((point.displayWidth or 24)+(member.displayWidth or 24))/2+6)
                        local limitY = math.max(point.displayHeight or 20,member.displayHeight or 20)+4
                        if dx > limitX*slack or dy > limitY*slack then close = false; break end
                    end
                    if close then target = group; break end
                end
                if not target then
                    target = {members={},x=0,y=0,id=point.id,professionGroup=true,noCluster=true}
                    professionGroups[#professionGroups+1] = target
                end
                target.members[#target.members+1] = point
                target.x,target.y = target.x+point.x,target.y+point.y
            end
        end
        for _, group in ipairs(professionGroups) do
            if #group.members > 1 then
                groups[#groups+1] = group
                for _, point in ipairs(group.members) do paired[point.id],membership[point.id] = true,group.id end
            end
        end
        local candidates = {}
        for i = 1, #points - 1 do
            local a = points[i]
            if not a.taxiNodeID and not paired[a.id] then
                for j = i + 1, #points do
                    local b = points[j]
                    if not b.taxiNodeID and not paired[b.id] and (a.category ~= "profession" or b.category ~= "profession") then
                        local dx,dy = math.abs(a.x-b.x)*width,math.abs(a.y-b.y)*height
                        local slack = previous and previous[a.id] and previous[a.id] == previous[b.id] and 1.15 or 1
                        local limitX = math.min(120,((a.displayWidth or 24)+(b.displayWidth or 24))/2+6)
                        local limitY = math.max(a.displayHeight or 20,b.displayHeight or 20)+4
                        if dx <= limitX*slack and dy <= limitY*slack then
                            candidates[#candidates+1] = {a=a,b=b,distance=dx*dx+dy*dy}
                        end
                    end
                end
            end
        end
        table.sort(candidates,function(a,b)
            if a.distance ~= b.distance then return a.distance < b.distance end
            if a.a.id ~= b.a.id then return a.a.id < b.a.id end
            return a.b.id < b.b.id
        end)
        for _, pair in ipairs(candidates) do
            local a,b = pair.a,pair.b
            if not paired[a.id] and not paired[b.id] then
                paired[a.id],paired[b.id] = true,true
                membership[a.id],membership[b.id] = a.id,a.id
                groups[#groups+1] = {members={a,b},x=a.x+b.x,y=a.y+b.y,id=a.id,noCluster=true}
            end
        end
    end
    for _, point in ipairs(points) do
        if not paired[point.id] then
            local target
            local noCluster = independent and independent[point.id]
            if not point.taxiNodeID and not noCluster then
                for _, group in ipairs(groups) do
                    local members = group.members
                    local professionals = group.professionGroup and point.category == "profession"
                    if not group.taxiNodeID and not group.noCluster and (professionals or #members < 2) then
                        local close = true
                        for _, member in ipairs(members) do
                            local slack = previous and previous[point.id] and previous[point.id] == previous[member.id] and 1.15 or 1
                            local dx, dy = math.abs(point.x-member.x)*width, math.abs(point.y-member.y)*height
                            local limitX = math.min(120, ((point.displayWidth or 24)+(member.displayWidth or 24))/2+6)
                            local limitY = math.max(point.displayHeight or 20, member.displayHeight or 20)+4
                            if dx > limitX*slack or dy > limitY*slack then close = false; break end
                        end
                        if close then target = group; break end
                    end
                end
            end
            if not target then
                target = { members = {}, x = 0, y = 0, taxiNodeID = point.taxiNodeID,
                    professionGroup = point.category == "profession", id = point.id, noCluster = noCluster }
                groups[#groups+1] = target
            end
            target.members[#target.members+1] = point
            target.professionGroup = target.professionGroup and point.category == "profession"
            target.x, target.y = target.x+point.x, target.y+point.y
            membership[point.id] = target.id
        end
    end
    for _, group in ipairs(groups) do
        group.x, group.y = group.x/#group.members, group.y/#group.members
        if #group.members == 1 then
            setmetatable(group, { __index = group.members[1] })
        else
            group.category = group.professionGroup and "profession" or "service"
            group.hub = group.professionGroup and #group.members > 2
        end
    end
    return groups, membership
end
