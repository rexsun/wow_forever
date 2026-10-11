-- Unified adjacent-anchor layout. Configuration conversion lives in the model.
local Geometry = {}
-- New compact/centered layout. Pure measurements; no frame operations.
function Geometry.Flow(bar, instances, measurements)
    local order, widths, missing, cross = {}, {}, {}, 0
    local allowOverflow=false
    local vertical = bar.orientation == "vertical"
    for _, id in ipairs(bar.items) do
        local m = measurements[id]
        if m and m.renderable ~= false then
            order[#order+1] = id
            if ((instances[id] or {}).anchorGap or 0)<0 then allowOverflow=true end
            widths[id] = vertical and m.height or m.width
            if vertical or (instances[id] or {}).expandBarHeight~=false then
                cross = math.max(cross, (vertical and m.width or m.height) or 0)
            end
        elseif not m then
            order[#order+1]=id; widths[id]=0; missing[id]=true
        elseif id == bar.centerInstanceId and bar.reserveCenter~=false then
            order[#order+1] = id -- Invisible center remains a virtual anchor.
            widths[id] = 0
        end
    end
    local pad = bar.padding or {}
    local leading, trailing = pad.before or 0, pad.after or 0
    local function gap(left, right)
        local a, b = instances[left] or {}, instances[right] or {}
        return math.max(0, (bar.spacing or 0) + (a.after or 0) + (b.before or 0))
    end
    local function span(first, last)
        local sum = 0
        for i=first,last do
            sum = sum + widths[order[i]] + math.max(0,(instances[order[i]] or {}).anchorGap or 0)
            if i>first then sum=sum+gap(order[i-1],order[i]) end
        end
        return sum
    end
    local center
    for i,id in ipairs(order) do if id==bar.centerInstanceId then center=i end end
    local function alignment(i)
        local instance=instances[order[i]] or {}
        return instance.alignment
            or (center and i>center and "RIGHT" or "LEFT")
    end
    -- A right-facing chain ending in a left-facing neighbor has no external
    -- anchor. Resolve that whole chain from the preceding item (or bar start).
    -- This is derived geometry only; saved directions and order stay untouched.
    local leftFlow={}
    for i=#order-1,1,-1 do
        if i~=center and i+1~=center and alignment(i)=="RIGHT"
            and (alignment(i+1)=="LEFT" or leftFlow[i+1]) then leftFlow[i]=true end
    end
    local required = span(1,#order)+leading+trailing
    if center then
        local before, after = span(1,center-1), span(center+1,#order)
        if center>1 then before=before+gap(order[center-1],order[center]) end
        if center<#order then after=after+gap(order[center],order[center+1]) end
        required=widths[order[center]]+2*math.max(before+leading,after+trailing)
    end
    local length = bar.sizing=="fixed" and (bar.length or required) or required
    local positions, slopes = {}, {}
    -- Direction attaches to the adjacent item without changing saved order.
    -- Mutual attachments use the derived leftward chain, avoiding cycles.
    local function distance(i,left,right)
        local own=instances[order[i]] or {}
        return (own.anchorGap or 0)+(left and right and gap(left,right) or 0)
    end
    local function solve(i)
        local id=order[i]
        if missing[id] then return nil end
        if positions[id]~=nil then return positions[id] end
        local x, slope
        if i==center then slope=0.5;x=(length-widths[id])/2
        elseif alignment(i)=="LEFT" or leftFlow[i] then
            if i==1 then slope=0;x=leading+distance(i,nil,nil)
            else local prev=solve(i-1);slope=prev and slopes[order[i-1]] or 0
                x=(prev and prev+widths[order[i-1]] or leading)+distance(i,order[i-1],id) end
        else
            if i==#order then slope=1;x=length-trailing-widths[id]-distance(i,nil,nil)
            else local nextX=solve(i+1);slope=nextX and slopes[order[i+1]] or 1
                x=(nextX or length-trailing)-distance(i,id,order[i+1])-widths[id] end
        end
        positions[id]=x;slopes[id]=slope
        return x
    end
    for i=1,#order do solve(i) end
    -- Each anchor is affine in bar length (start, midpoint or end). Use the
    -- same solution to size automatic bars, including asymmetric facing chains.
    for _,id in ipairs(order) do
        local x,a=positions[id],slopes[id]
        if x then
            local offset=x-a*length
            if a>0 then required=math.max(required,(leading-offset)/a) end
            if a<1 then required=math.max(required,(offset+widths[id]+trailing)/(1-a)) end
        end
    end
    if bar.sizing~="fixed" and required>length then
        for id,x in pairs(positions) do positions[id]=x+slopes[id]*(required-length) end
        length=required
    end
    return {positions=positions,length=length,requiredLength=required,overflow=required>length,allowOverflow=allowOverflow,
        crossSize=math.max(bar.minCrossSize or 0,cross+(pad.crossBefore or 0)+(pad.crossAfter or 0))}
end
-- Keep actual module dimensions; only its contribution to bar height is optional.
function Geometry.VerticalPosition(bar,instance,height,barHeight)
    local alignment=instance.verticalAlignment or "CENTER"
    local padding=bar.padding or {}
    local y
    if alignment=="TOP" then y=padding.crossBefore or 0
    elseif alignment=="BOTTOM" then y=barHeight-(padding.crossAfter or 0)-height
    else
        y=(barHeight-height)/2
        if instance.verticalAlignment then
            y=y+((padding.crossBefore or 0)-(padding.crossAfter or 0))/2
        end
    end
    return y-(instance.verticalOffset or 0)
end
-- Whole-instance clipping leaves protected actions on their original hosts.
-- Prefer the explicit center, then stable saved order. Explicit overlap permission
-- preserves intentional negative spacing without selecting a different solver.
function Geometry.Visible(result,bar,measurements,limit)
    local visible,intervals,hidden={},{},{}
    local vertical=bar.orientation=="vertical"
    local function admit(id)
        local m=measurements[id]
        local start=result.positions[id]
        if not m or m.renderable==false or start==nil then return end
        local finish=start+(vertical and m.height or m.width)
        local fits=result.allowOverflow or start>=0 and finish<=(limit or result.length)
        if fits and not result.allowOverflow and not bar.allowOverlap then
            for _,interval in ipairs(intervals) do
                if start<interval[2] and finish>interval[1] then fits=false;break end
            end
        end
        if fits then visible[id]=true;intervals[#intervals+1]={start,finish}
        else hidden[#hidden+1]=id end
    end
    if bar.centerInstanceId then admit(bar.centerInstanceId) end
    for _,id in ipairs(bar.items) do if id~=bar.centerInstanceId then admit(id) end end
    return visible,hidden
end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Geometry=Geometry
end
return Geometry
