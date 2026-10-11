local YUI = _G.YUI
local YBar = YUI.YBar
local Info, Tracking = YBar.InfoModule, YBar.CurrencyTracking
local L = YUI.Locale:Get("YBar")

local function Register(name, title, fixed, context)
    local Events = context and context.events or YUI.Event
    local module = YBar.Module:New(context and context.id or name)
    module.moduleType, module.configKey, module.instanceContext = name, name, context
    module.defaultIcon = fixed and 135884 or 133784
    module.CreateBarItem = Info.Create
    function module:GetDisplayDB()
        local root = context and context:GetRoot() or YBar:EnsureDB()
        if not context then Tracking.Prepare(root) end
        self.db = root[name]
        if context and self.db.tracked==nil then
            local defaults={}
            for _,id in ipairs(fixed and Tracking.CrestIDs or Tracking.PresetIDs) do
                defaults[#defaults+1]={id=id,bar=true,tooltip=true}
            end
            self.db.tracked=defaults
            self.db.maxWidth=self.db.maxWidth or 400
            self.db.style=self.db.style or "icons"
            self.db.excludeCrests=not fixed
        end
        Tracking.Ensure(self.db)
        -- Each visible currency owns a reusable GUI2 IconSlot and status text.
        self.db.display = "text"
        return self.db
    end
    function module:UpdateBarItem()
        local db = self:GetDisplayDB()
        if not self.frame then return end
        if not self.cells then
            self.cells = {}
            self.frame.text:Hide()
            self.frame.iconSlot:Hide()
        end
        local count, offset, contentHeight = 0, 0, 0
        local available=false
        for _, item in ipairs(db.tracked) do
            local info
            if context and Events.ReadData then info=Events:ReadData(item.id,C_CurrencyInfo.GetCurrencyInfo,item.id)
            else info=C_CurrencyInfo.GetCurrencyInfo(item.id) end
            if info and info.discovered~=false and not info.isTypeUnused then available=true end
            if info and info.discovered~=false and not info.isTypeUnused and item.bar and (fixed and Tracking.IsCrest(item.id) or not fixed and not Tracking.IsCrest(item.id)) then
                count = count + 1
                local cell = self.cells[count]
                if not cell then
                    cell = {name=self.name .. ":cell:" .. count, config={}, instanceContext=context, AttachRuntime=function() end}
                    function cell:GetDisplayDB() return self.config end
                    function cell:UpdateBarItem() end
                    Info.Create(cell,self.frame)
                    cell.frame:EnableMouse(false)
                    YBar:RegisterBarItemHoverText(self.frame,cell.frame.text)
                    self.cells[count] = cell
                end
                local config = cell.config
                config.font, config.size = db.font, db.size
                config.iconBackground = db.iconBackground
                config.iconSize,config.iconGap=db.iconSize,db.iconGap
                config.color,config.colorMode=db.color,db.colorMode
                config.display, config.maxWidth = db.style == "icons" and "both" or "text", 400
                local text = BreakUpLargeNumbers(info.quantity or 0)
                if fixed and db.numberColors=="white" then text="|cffffffff"..text.."|r"
                elseif fixed and ITEM_QUALITY_COLORS then
                    local quality=ITEM_QUALITY_COLORS[item.id-3441]
                    if quality and quality.hex then text=quality.hex..text.."|r" end
                end
                if count > 1 and db.style ~= "icons" then text = " | " .. text end
                Info.Display(cell,text,info and info.iconFileID or 134400)
                contentHeight=math.max(contentHeight,cell.contentHeight or config.size or 14)
                if cell.offset ~= offset then
                    cell.offset = offset
                    cell.frame:ClearAllPoints()
                    cell.frame:SetPoint("LEFT",self.frame,"LEFT",offset,0)
                end
                if not cell.visible then cell.frame:Show(); cell.visible = true end
                offset = offset + cell.width + (db.style == "icons" and 6 or 0)
            end
        end
        for index=count+1,#self.cells do
            local cell = self.cells[index]
            if cell.visible then cell.frame:Hide();cell.visible=false end
        end
        self.available=available
        if count==0 and available then
            self.empty=true;Info.Display(self,L[title],self.defaultIcon)
            return
        end
        if self.empty then self.frame.text:Hide();self.frame.iconSlot:Hide() end
        self.empty=count==0
        self.contentHeight=contentHeight
        local width = math.max(offset - (count > 0 and db.style == "icons" and 6 or 0),2)
        if self.width ~= width then
            self.width = width
            self.frame:SetWidth(width)
            YBar:UpdateLayout()
        end
    end
    function module:IsBarItemRenderable()return self.available==true end
    function module:GetWidth() return self.width or 100 end
    function module:OnEvent(_, id)
        local db = self:GetDisplayDB()
        if id then
            local relevant = false
            for _, item in ipairs(db.tracked) do if item.id == id then relevant = true; break end end
            if not relevant then return end
        end
        self:UpdateBarItem()
        if self.frame and GameTooltip:GetOwner() == self.frame then self:OnEnter() end
    end
    function module:AttachRuntime()
        if self.active then return end
        self.active = true
        Events:On("CURRENCY_DISPLAY_UPDATE", "OnEvent", self)
        Events:On("YUI_WORLD_READY", "OnEvent", self)
    end
    function module:DetachRuntime()
        self.active = false
        Events:OffOwner(self)
        if self.frame and GameTooltip:GetOwner() == self.frame then YUI.HideGameTooltip() end
    end
    function module:OnDBReload()
        self:DetachRuntime()
        self:GetDisplayDB()
        if YBar:IsSubModuleEnabled(self.name) then self:AttachRuntime() end
        self:UpdateBarItem()
    end
    function module:OnEnter()
        Info.Tooltip(self,L[title])
        Tracking.Tooltip(self:GetDisplayDB(),fixed)
        local core=YUI.Locale:Get("Core")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff808080"..core["common.alt_left_click"]..": "..core["common.open_settings"].."|r")
        GameTooltip:Show()
    end
    function module:OnClick()
        if not InCombatLockdown() then ToggleCharacter("TokenFrame") end
    end
    function module:GetOptions()
        self:GetDisplayDB()
        local common = Info.Options(self)
        -- Font/size and width use the same controls as other information modules.
        local options = {common[1], common[2], common[3], {
            type="dropdown",label=L["tracking.style"],width=220,
            options={{text=L["tracking.numbers"],value="numbers"},{text=L["tracking.icons"],value="icons"}},
            get=function() return self.db.style end,
            set=function(value) self.db.style=value; self:UpdateBarItem() end,
        }, common[5]}
        if fixed then
            options[#options+1]={type="dropdown",label=L["tracking.number_colors"],width=220,
                options={{text=L["tracking.quality_colors"],value="quality"},{text=L["tracking.white"],value="white"}},
                get=function()return self.db.numberColors or "quality"end,
                set=function(v)self.db.numberColors=v;self:UpdateBarItem()end}
        end
        Tracking.Options(self,options,fixed)
        return options
    end
    if not context then Info.Register(module) end
    return module
end

YBar.ModuleFactories = YBar.ModuleFactories or {}
YBar.ModuleFactories.CurrencyTracker = function(context)
    return Register("CurrencyTracker", "ybar.module.currency_tracker", false, context)
end
YBar.ModuleFactories.SeasonCrests = function(context)
    return Register("SeasonCrests", "ybar.module.season_crests", true, context)
end
Register("CurrencyTracker","ybar.module.currency_tracker",false)
Register("SeasonCrests","ybar.module.season_crests",true)
