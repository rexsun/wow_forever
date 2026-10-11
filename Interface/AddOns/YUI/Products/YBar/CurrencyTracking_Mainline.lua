local YUI = _G.YUI
local YBar = YUI.YBar
local L = YUI.Locale:Get("YBar")
local Tracking = {}
YBar.CurrencyTracking = Tracking

-- 12.1: five upgrade tiers, low to high. Keep season IDs separate from general presets.
Tracking.CrestIDs = {3442, 3443, 3444, 3445, 3446}
Tracking.PresetIDs = {3316, 2803, 3356, 3028}
function Tracking.IsCrest(id)
    return type(id) == "number" and id >= 3442 and id <= 3446
end

function Tracking.Prepare(root)
    if root.currencySplitVersion == 1 then return end
    local legacy = root.Currency or {}
    root.CurrencyTracker = root.CurrencyTracker or {}
    root.SeasonCrests = root.SeasonCrests or {}
    local general, crests = root.CurrencyTracker, root.SeasonCrests
    local existingGeneral, existingCrests = general.tracked, crests.tracked
    if not existingGeneral then general.tracked = {} end
    if not existingCrests then crests.tracked = {} end
    local function append(list, id, bar, tooltip)
        for _, item in ipairs(list) do if item.id == id then return end end
        list[#list+1] = {id=id, bar=bar ~= false, tooltip=tooltip ~= false}
    end
    local old = legacy.tracked
    if not old then
        old = {}
        if type(legacy.currencyID) == "number" and legacy.currencyID > 0 then
            append(old, legacy.currencyID, true, true)
        end
        for _, id in ipairs(legacy.tooltipCurrencies or {}) do append(old,id,true,true) end
    end
    for _, item in ipairs(old) do
        if Tracking.IsCrest(item.id) then
            if not existingCrests then append(crests.tracked,item.id,item.bar,item.tooltip) end
        elseif not existingGeneral then append(general.tracked,item.id,item.bar,item.tooltip) end
    end
    if not existingGeneral and legacy.tracked == nil then
        for _, id in ipairs(Tracking.PresetIDs) do append(general.tracked,id,true,true) end
    end
    if not existingCrests then
        for _, id in ipairs(Tracking.CrestIDs) do append(crests.tracked,id,true,true) end
    end
    table.sort(crests.tracked,function(a,b) return a.id < b.id end)
    for _, config in ipairs({general,crests}) do
        config.font = config.font or legacy.font
        config.size = config.size or legacy.size or 14
        config.style = config.style or (legacy.showIcon == false and "numbers" or "icons")
        config.display = "text"
        config.maxWidth = config.maxWidth or 400
    end
    general.excludeCrests = true
    root.currencySplitVersion = 1
end

function Tracking.Ensure(db)
    if db.tracked then return db.tracked end
    db.tracked = {}
    local seen = {}
    local function add(id, bar)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            db.tracked[#db.tracked+1] = {id=id, bar=bar, tooltip=true}
        end
    end
    add(db.currencyID, true)
    for _, id in ipairs(db.tooltipCurrencies or {}) do add(id, true) end
    return db.tracked
end

function Tracking.BarText(db)
    local parts = {}
    for _, item in ipairs(Tracking.Ensure(db)) do
        if item.bar and (not db.excludeCrests or not Tracking.IsCrest(item.id)) then
            local info = C_CurrencyInfo.GetCurrencyInfo(item.id)
            local icon = info and info.iconFileID or 134400
            local count = info and info.discovered ~= false and not info.isTypeUnused and BreakUpLargeNumbers(info.quantity or 0) or "?"
            parts[#parts+1] = ((db.style == "icons" or (db.style == nil and db.showIcon)) and ("|T" .. icon .. ":" .. (db.size or 14) .. ":" .. (db.size or 14) .. "|t ") or "") .. count
        end
    end
    return #parts > 0 and table.concat(parts, db.style == "icons" and "  " or " | ") or L["tracking.empty"]
end

function Tracking.MenuIDs(db)
    local result, seen = {}, {}
    for _, id in ipairs(db.tooltipCurrencies or {}) do
        if not seen[id] then result[#result+1]=id; seen[id]=true end
    end
    for _, item in ipairs(Tracking.Ensure(db)) do
        if not seen[item.id] then result[#result+1]=item.id; seen[item.id]=true end
    end
    return result
end

function Tracking.Progress(info)
    local lines = {}
    if info.maxQuantity and info.maxQuantity > 0 then
        local total = info.useTotalEarnedForMaxQty and info.totalEarned or info.quantity
        lines[#lines+1] = {L[info.useTotalEarnedForMaxQty and "tracking.total" or "tracking.holding"],
            BreakUpLargeNumbers(total or 0) .. " / " .. BreakUpLargeNumbers(info.maxQuantity)}
    end
    if info.maxWeeklyQuantity and info.maxWeeklyQuantity > 0 then
        lines[#lines+1] = {L["tracking.weekly"], BreakUpLargeNumbers(info.quantityEarnedThisWeek or 0) .. " / " .. BreakUpLargeNumbers(info.maxWeeklyQuantity)}
    end
    return lines
end

function Tracking.Catalog()
    local entries, groups, order, expanded = {}, {}, {}, {}
    local category = L["tracking.other"]
    local ok, reason = pcall(function()
        local index = 1
        while index <= C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(index)
            if info then
                if info.isHeader then
                    category = info.name
                    if not info.isHeaderExpanded and C_CurrencyInfo.ExpandCurrencyList then
                        expanded[#expanded+1] = index
                        C_CurrencyInfo.ExpandCurrencyList(index, true)
                    end
                else
                    local link = C_CurrencyInfo.GetCurrencyListLink(index)
                    local id = link and tonumber(link:match("currency:(%d+)"))
                    if id then
                        entries[#entries+1] = {text=info.name,value=id,icon=info.icon or (C_CurrencyInfo.GetCurrencyInfo(id) or {}).iconFileID}
                        groups[id]=category;order[id]=#entries
                    end
                end
            end
            index=index+1
        end
    end)
    -- Reverse order preserves list indices when nested headers collapse.
    for index=#expanded,1,-1 do C_CurrencyInfo.ExpandCurrencyList(expanded[index],false) end
    if not ok then error(reason,0) end
    return entries, groups, order
end

function Tracking.Tooltip(db, ordered)
    GameTooltip:AddLine(" ")
    if ordered then GameTooltip:AddDoubleLine(" ",L["tracking.crest_counts"],1,1,1,1,1,1) end
    local _, groups, order = Tracking.Catalog()
    local list = {}
    for _, item in ipairs(Tracking.Ensure(db)) do
        if (not db.excludeCrests or not Tracking.IsCrest(item.id))
            and (not ordered or Tracking.IsCrest(item.id)) then list[#list+1]=item end
    end
    if not ordered then table.sort(list,function(a,b)
        local ai,bi=order[a.id] or math.huge,order[b.id] or math.huge
        if ai==bi then return a.id<b.id end
        return ai<bi
    end) end
    local group
    for _, item in ipairs(list) do
        local current=groups[item.id] or L["tracking.other"]
        if not ordered and current~=group then GameTooltip:AddLine(" "); GameTooltip:AddLine(current); group=current end
        local info=C_CurrencyInfo.GetCurrencyInfo(item.id)
        local name=info and info.name or tostring(item.id)
        if not info or info.discovered==false or info.isTypeUnused then
            GameTooltip:AddDoubleLine(name,L["tracking.unavailable"],1,1,1,1,1,1)
        else
            local counts=BreakUpLargeNumbers(info.quantity or 0)
            if ordered then
                counts=counts.." / "..BreakUpLargeNumbers(info.totalEarned or 0).." / "..BreakUpLargeNumbers(info.maxQuantity or 0)
            elseif info.maxQuantity and info.maxQuantity>0 then
                counts=counts.." / "..BreakUpLargeNumbers(info.maxQuantity)
            end
            GameTooltip:AddDoubleLine("|T"..(info.iconFileID or 134400)..":14:14|t "..name,counts,1,1,1,1,1,1)
        end
    end
end

function Tracking.Options(module, options, fixed)
    local tracked=Tracking.Ensure(module.db)
    local function refresh()
        module:UpdateBarItem()
        YBar:UpdateLayout()
        if YBar.RefreshFeatureSettings then YBar:RefreshFeatureSettings() end
    end
    options[#options+1]={type="divider",label=L["feature.contents"],width=400,alignLeft=true}
    local presets
    if not fixed then
    local function choices()
    local catalog=Tracking.Catalog()
    local choices={}
    for _, item in ipairs(catalog) do
        local exists=false
        for _,entry in ipairs(tracked)do if entry.id==item.value then exists=true;break end end
        if not exists and not Tracking.IsCrest(item.value) then choices[#choices+1]=item end
    end
    choices[#choices+1]={text=L["tracking.manual_id"],value="manual"}
    return choices
    end
    local function add(id, quiet)
        if id=="manual" then module.currencyManual=true;refresh();return end
        if id and Tracking.IsCrest(id) then YUI:Print(L["tracking.crest_excluded"]); return end
        for _, item in ipairs(tracked) do if item.id==id then return end end
        local info = id and id > 0 and id == math.floor(id) and C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.name and info.name ~= "" then
            tracked[#tracked+1]={id=id,bar=true,tooltip=true}
            if not quiet then refresh() end
            return true
        end
    end
    presets={type="button",label=L["tracking.presets"],width=220,onClick=function()
        local changed = false
        for _, id in ipairs(Tracking.PresetIDs) do if add(id,true) then changed = true end end
        if changed then refresh() end
    end}
    local children
    if module.currencyManual then
        children={
            {type="editbox",transient=true,width=224,get=function()return module.currencyInput or "" end,
                set=function(v)module.currencyInput=v end},
            {type="button",label=YUI.Locale:Get("Core")["common.cancel"],width=76,onClick=function()
                module.currencyManual=nil;module.currencyInput=nil;refresh()
            end},
            {type="button",label=L["tracking.add"],width=76,onClick=function()
                if add(tonumber(module.currencyInput)) then module.currencyInput="" end
            end},
        }
    else
        children={
            {type="dropdown",width=312,options=choices,placeholder=L["tracking.choose"],
                get=function()return module.currencySelected end,set=function(id)
                    if id=="manual" then module.currencyManual=true;module.currencySelected=nil;refresh()
                    else module.currencySelected=id end
                end},
            {type="button",label=L["tracking.add"],width=76,onClick=function()
                if add(module.currencySelected) then module.currencySelected=nil end
            end},
        }
    end
    options[#options+1]={type="row",gap=12,children=children}

    end
    options[#options+1]={type="custom",width=400,render=function(parent,x,y)
        local GUI = YUI.GUI2
        local function edit(callback)
            return function(...)
                if module.RunConfigEdit then return module:RunConfigEdit(callback,...) end
                return callback(...)
            end
        end
        local width = fixed and 300 or 400
        local rowHeight = GUI:GetMetric("layout.form.rowHeight",32) + 6
        local list = GUI:CreateFrame(parent,{width=width,height=#tracked*rowHeight+22})
        list:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
        local actionWidth = fixed and 0 or 90
        local barX = width-actionWidth-60
        local function label(parent,text,left,top,w)
            local font = GUI:CreateText(parent,text,"font.size.md","color.text.primary")
            font:SetPoint("TOPLEFT",left,top)
            font:SetWidth(w);font:SetJustifyH("LEFT");font:SetWordWrap(false)
            return font
        end
        label(list,L["tracking.column_name"],0,0,barX-8)
        label(list,L["tracking.column_bar"],barX,0,60)
        for index, item in ipairs(tracked) do
            local i, entry = index,item
            local row = GUI:CreateFrame(list,{width=width,height=rowHeight})
            row:SetPoint("TOPLEFT",0,-22-(index-1)*rowHeight)
            local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
            local icon = GUI:CreateIconSlot(row,{size=18,icon=info and info.iconFileID or 134400,padding=0,shape="rounded"})
            icon:SetPoint("LEFT",0,0)
            local name=label(row,info and info.name or tostring(entry.id),26,0,barX-34)
            name:ClearAllPoints();name:SetPoint("LEFT",row,"LEFT",26,0)
            local hover=GUI:CreateFrame(row,{width=barX-8,height=rowHeight,mouse=true})
            hover:SetPoint("LEFT")
            hover:SetScript("OnEnter",function()
                GameTooltip:SetOwner(hover,"ANCHOR_RIGHT");GameTooltip:SetCurrencyByID(entry.id);GameTooltip:Show()
            end)
            local function hide()if GameTooltip:GetOwner()==hover then YUI.HideGameTooltip()end end
            hover:SetScript("OnLeave",hide);hover:SetScript("OnHide",hide)
            local bar = GUI.Form:CreateCheckbox(row,{width=26,height=26,get=function() return entry.bar end,
                set=edit(function(v) entry.bar=v;module:UpdateBarItem() end)})
            bar:SetPoint("LEFT",barX,0)
            if not fixed then
                local function button(text,position,help,disabled,fn)
                    local b=GUI.Form:CreateButton(row,{text="",width=26,height=26,tooltip=help,disabled=disabled,onClick=edit(fn)})
                    local glyph
                    if text=="trash-2" then glyph=GUI:CreateIcon(b,{icon=GUI:GetSettingsIcon(text),size=16})
                    else glyph=GUI:CreateMicroIcon(b,{name=text,size=16}) end
                    glyph:SetPoint("CENTER");glyph:SetAlpha(disabled and 0.3 or 1)
                    b:SetPoint("LEFT",width-90+position*30,0)
                end
                local function move(delta)
                    if tracked[i+delta] then tracked[i],tracked[i+delta]=tracked[i+delta],tracked[i];refresh() end
                end
                button("move-up",0,L["feature.up"],i==1,function() move(-1) end)
                button("move-down",1,L["feature.down"],i==#tracked,function() move(1) end)
                button("trash-2",2,L["feature.remove"],false,function() table.remove(tracked,i);refresh() end)
            end
        end
        return width,#tracked*rowHeight+22
    end}
    if presets then options[#options+1]=presets end
    return options
end
