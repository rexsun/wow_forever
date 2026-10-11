local _, YUI = ...
local LSM = LibStub("LibSharedMedia-3.0")
local AURA_ANCHOR_TMPL = "YUI - 锚点 - %s"
local AURA_ANCHOR_TYPE_KEY = "_YUI_ANCHOR_TYPE_"
local API = YUI.WOW_API
local SecurityAPI = YUI.API and YUI.API.Security or API
local SpellAPI = YUI.API and YUI.API.Spell or API
local GUI2 = YUI.GUI2
local Secure = GUI2 and GUI2.Secure

YUI.WA = {["UnitFrame"] = {}}

local WA = YUI.WA
local AuraSizeData = {}

function WA:GetAnchor(aura_env)
    local type = aura_env[AURA_ANCHOR_TYPE_KEY]

    if type == nil then
        local ids = YUI.F:StrSplit(aura_env.id, " - ")
        type = ids[#ids]
        aura_env[AURA_ANCHOR_TYPE_KEY] = type
    end

    if type == nil then return nil, nil end

    -- Get Anchor Aura
    local anchor_name = string.format(AURA_ANCHOR_TMPL, type)
    local anchor_aura = WeakAuras.GetData(anchor_name)

    if anchor_aura == nil then return nil, nil end

    -- Get Anchor Group
    local group_name = anchor_aura.parent
    if group_name == nil then return anchor_aura, nil end
    local anchor_group = WeakAuras.GetData(group_name)
    return anchor_aura, anchor_group, type
end

function WA:AuraUpdate(aura_env, pos, reg, is_same)
    local anchor_aura, anchor_group, type

    if is_same then
        anchor_aura, anchor_group, type = WA:GetAnchor(aura_env)
        if anchor_aura == nil or anchor_group == nil or type == nil then
            return
        end
    end

    -- Size
    for _, regionData in ipairs(reg) do
        local region = regionData.region

        if not is_same then
            anchor_aura, anchor_group, type = WA:GetAnchor(region)
            if anchor_aura == nil or anchor_group == nil or type == nil then
                return
            end
        end

        if region.regionType == "icon" then
            region:SetRegionWidth(anchor_aura.width)
            region:SetRegionHeight(anchor_aura.height)
            region:SetZoom(anchor_aura.zoom)
            for i, subRegion in ipairs(region.subRegions) do
                if subRegion.type == "subborder" then
                    local data = anchor_aura.subRegions[i]
                    if not data then break end
                    if data.type == "subborder" then
                        local backdrop = subRegion:GetBackdrop()
                        local colors = data.border_color
                        if backdrop then
                            backdrop.edgeSize = data.border_size
                            subRegion:SetBackdrop(backdrop)
                        end
                        if colors then
                            subRegion:SetBorderColor(unpack(colors))
                        end
                        subRegion:SetVisible(data.border_visible)
                    end
                end
                if subRegion.type == "subtext" then
                    local data = anchor_aura.subRegions[i]
                    if not data then break end
                    if data.type == "subtext" then
                        subRegion:SetXOffset(data.text_anchorXOffset)
                        subRegion:SetYOffset(data.text_anchorYOffset)
                        subRegion.text:SetFont(
                            LSM:Fetch("font", data.text_font),
                            data.text_fontSize, data.text_fontType)
                        subRegion.text:SetShadowColor(unpack(
                                                          data.text_shadowColor))
                        subRegion.text:SetShadowOffset(data.text_shadowXOffset,
                                                       data.text_shadowYOffset)
                    end
                end
            end

        elseif region.regionType == "aurabar" then
            region:SetRegionWidth(anchor_aura.width)
            region:SetRegionHeight(anchor_aura.height)
            region.texture = anchor_aura.texture
            region.textureInput = anchor_aura.textureInput
            region.textureSource = anchor_aura.textureSource
            region:UpdateStatusBarTexture()
            for i, subRegion in ipairs(region.subRegions) do
                if subRegion.type == "subborder" then
                    local data = anchor_aura.subRegions[i]
                    if not data then break end
                    if data.type == "subborder" then
                        local backdrop = subRegion:GetBackdrop()
                        local colors = data.border_color
                        if backdrop then
                            backdrop.edgeSize = data.border_size
                            subRegion:SetBackdrop(backdrop)
                        end
                        if colors then
                            subRegion:SetBorderColor(unpack(colors))
                        end
                        subRegion:SetVisible(data.border_visible)
                    end
                end
                if subRegion.type == "subtext" then
                    local data = anchor_aura.subRegions[i]
                    if not data then break end
                    if data.type == "subtext" then
                        subRegion:SetXOffset(data.text_anchorXOffset)
                        subRegion:SetYOffset(data.text_anchorYOffset)
                        subRegion.text:SetFont(
                            LSM:Fetch("font", data.text_font),
                            data.text_fontSize, data.text_fontType)
                        subRegion.text:SetShadowColor(unpack(
                                                          data.text_shadowColor))
                        subRegion.text:SetShadowOffset(data.text_shadowXOffset,
                                                       data.text_shadowYOffset)
                    end
                elseif subRegion.type == "subtick" then
                    subRegion:SetAutomaticLength(false)
                    subRegion:SetTickLength(anchor_aura.height)
                    subRegion:SetTickPlacement(subRegion.tick_placements[1])
                end
            end

        elseif region.regionType == "text" then
            local data = anchor_aura
            region.text:SetFont(LSM:Fetch("font", data.font), data.fontSize,
                                data.outline)
            region.text:SetShadowColor(unpack(data.shadowColor))
            region.text:SetShadowOffset(data.shadowXOffset, data.shadowYOffset)
            AuraSizeData[type] = data.fontSize
            region:SetHeight(data.fontSize)
            region:SetWidth(region.text:GetWidth())
            region:Color(region.color_r, region.color_g, region.color_b,
                         data.color[4])

        elseif region.regionType == "texture" or region.regionType ==
            "progresstexture" then
            region:SetRegionWidth(anchor_aura.width)
            region:SetRegionHeight(anchor_aura.height)
            for i, subRegion in ipairs(region.subRegions) do
                if subRegion.type == "subtext" then
                    local data = anchor_aura.subRegions[i]
                    if not data then break end
                    if data.type == "subtext" then
                        subRegion:SetXOffset(data.text_anchorXOffset)
                        subRegion:SetYOffset(data.text_anchorYOffset)
                        subRegion.text:SetFont(
                            LSM:Fetch("font", data.text_font),
                            data.text_fontSize, data.text_fontType)
                        subRegion.text:SetShadowColor(unpack(
                                                          data.text_shadowColor))
                        subRegion.text:SetShadowOffset(data.text_shadowXOffset,
                                                       data.text_shadowYOffset)
                    end
                end
            end
        end
    end

    -- Position
    if anchor_group then
        local rType = anchor_group.regionType
        -- print(anchor_group.id, rType)
        if rType == "dynamicgroup" then
            local directionX = (anchor_group.grow == "RIGHT" and {1, 1}) or
                                   (anchor_group.grow == "LEFT" and {-1, -1}) or
                                   {0, 0}
            local directionY = {0, 0} -- 初始化Y方向
            local space = anchor_group.space or 0
            local cSpace = anchor_group.columnSpace or 0
            local rSpace = anchor_group.rowSpace or 0
            local Xoffset = 0
            local Yoffset = 0
            local max = anchor_group.useLimit and anchor_group.limit or 999
            max = #reg <= max and #reg or max
            local n = max -- 实际参与排布的元素数量

            -- ========== 核心修改：VERTICAL模式按指定逻辑排布 ==========
            if anchor_group.grow == "VERTICAL" then
                for i = 1, n do
                    -- 1. 计算元素高度（兼容text类型）
                    local elem_height
                    if reg[i].region.regionType == "text" then
                        elem_height = AuraSizeData[type] or reg[i].region.height
                    else
                        elem_height = reg[i].region.height
                    end
                    -- 2. 总步长 = 元素高度 + 间距（space）
                    local step = elem_height + space
                    -- 3. 计算偏移系数：(n - 2i + 1) / 2
                    local coeff = (n - 2 * i + 1) / 2
                    -- 4. 最终Y偏移（系数 × 总步长）
                    local current_y_offset = coeff * step
                    local current_x_offset = 0 -- VERTICAL模式X轴无偏移

                    -- 赋值给位置表
                    pos[i] = {current_x_offset, current_y_offset}

                    -- 保留原有偏移变量（兼容其他逻辑）
                    Xoffset = current_x_offset
                    Yoffset = current_y_offset
                end
            elseif anchor_group.grow == "GRID" then
                -- ========== GRID模式（修复RD换行问题） ==========
                local grid_type = anchor_group.gridType or "RD" -- 默认向右向下
                local grid_width = math.max(anchor_group.gridWidth or 3, 1) -- 确保列数≥1，避免除以0

                -- 定义网格方向：X(水平)、Y(垂直) 偏移方向（WA中Y轴向上为正，向下为负）
                local grid_dir = {
                    RD = {x = 1, y = -1}, -- 向右(X+) → 向下(Y-) 换行
                    LD = {x = -1, y = -1}, -- 向左(X-) → 向下(Y-) 换行
                    RU = {x = 1, y = 1}, -- 向右(X+) → 向上(Y+) 换行
                    LU = {x = -1, y = 1} -- 向左(X-) → 向上(Y+) 换行
                }
                local dir = grid_dir[grid_type] or grid_dir.RD

                -- 预计算每行的最大高度（确保换行时垂直偏移准确，解决不同高度元素换行错位）
                local row_max_height = {} -- 记录每行的最大元素高度
                for i = 1, n do
                    local row = math.floor((i - 1) / grid_width) + 1 -- 当前元素所属行
                    local elem_height
                    if reg[i].region.regionType == "text" then
                        elem_height = AuraSizeData[type] or reg[i].region.height
                    else
                        elem_height = reg[i].region.height
                    end
                    row_max_height[row] =
                        math.max(row_max_height[row] or 0, elem_height)
                end

                -- 遍历计算每个元素的位置
                local current_row = 1 -- 当前行
                local row_x_offset = 0 -- 每行的初始X偏移
                local row_y_offset = 0 -- 每行的初始Y偏移

                for i = 1, n do
                    local col = ((i - 1) % grid_width) + 1 -- 当前列（1~grid_width）
                    local row = math.floor((i - 1) / grid_width) + 1 -- 当前行（1,2,3...）

                    -- 1. 计算元素尺寸（兼容文本类型）
                    local elem_width = reg[i].region.width
                    local elem_height
                    if reg[i].region.regionType == "text" then
                        elem_height = AuraSizeData[type] or reg[i].region.height
                    else
                        elem_height = reg[i].region.height
                    end

                    -- 2. 换行判断：新行时重置X偏移，叠加Y偏移（核心修复点）
                    if row ~= current_row then
                        row_x_offset = 0 -- 新行回到水平初始位置
                        -- 累加前一行的总高度（最大高度+间距）× 垂直方向
                        row_y_offset = row_y_offset +
                                           (row_max_height[current_row] + rSpace) *
                                           dir.y
                        current_row = row -- 更新当前行
                    end

                    -- 3. 计算当前元素的最终偏移
                    local current_x_offset =
                        row_x_offset + (col - 1) * (elem_width + cSpace) * dir.x
                    local current_y_offset = row_y_offset

                    -- 4. 赋值给位置表
                    pos[i] = {current_x_offset, current_y_offset}

                    -- 保留偏移变量（兼容原有逻辑）
                    Xoffset = current_x_offset
                    Yoffset = current_y_offset
                end
            else
                -- 原有非VERTICAL方向逻辑（UP/DOWN/RIGHT/LEFT）
                directionY = (anchor_group.grow == "UP" and {1, 1}) or
                                 (anchor_group.grow == "DOWN" and {-1, -1}) or
                                 {0, 0}
                for i = 1, max do
                    local height
                    if reg[i].region.regionType == "text" then
                        height = AuraSizeData[type] + space or
                                     reg[i].region.height + space
                    else
                        height = reg[i].region.height + space
                    end
                    local width = reg[i].region.width + space
                    pos[i] = {Xoffset, Yoffset}
                    Xoffset = Xoffset + (width * directionX[i % 2 + 1])
                    Yoffset = Yoffset + (height * directionY[i % 2 + 1])
                end
            end
        elseif rType == "group" then
            for i, _ in ipairs(reg) do pos[i] = {0, 0} end
        end
    end
end

function WA:GetUF(id) return YUI.WA["UnitFrame"][id] end

function WA:CreateUF(id, name)
    -- print("CreateUF: ", name)
    YUI.WA["UnitFrame"][id] = CreateFrame("Button", name, nil,
                                          "SecureUnitButtonTemplate")
    return self:GetUF(id)
end

function WA:ShowUF(id)
    local f = self:GetUF(id)

    if f == nil then return end

    if not UnitAffectingCombat("player") then
        -- print("|cff00ff00Show|r", id)
        f:Show()
    else
        -- print("|cff00ff00Show|r", "脱战后处理")
        if f._yuiShowUFHandle then
            YUI.Event:Off(f._yuiShowUFHandle)
        end
        if f._yuiHideUFHandle then
            YUI.Event:Off(f._yuiHideUFHandle)
            f._yuiHideUFHandle = nil
        end
        f._yuiShowUFHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
            f._yuiShowUFHandle = nil
            f:Show()
        end)
    end
end

function WA:HideUF(id)
    local f = self:GetUF(id)

    if f == nil then return end

    if not UnitAffectingCombat("player") then
        -- print("|cffff0000> Hide|r", id)
        f:Hide()
    else
        -- print("|cffff0000> Hide|r", "脱战后处理")
        if f._yuiHideUFHandle then
            YUI.Event:Off(f._yuiHideUFHandle)
        end
        if f._yuiShowUFHandle then
            YUI.Event:Off(f._yuiShowUFHandle)
            f._yuiShowUFHandle = nil
        end
        f._yuiHideUFHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
            f._yuiHideUFHandle = nil
            f:Hide()
        end)
    end
end

local pendingQueue = {}
local pendingQueueHandle
local function FlushPendingQueue()
    if SecurityAPI.InCombatLockdown() then return end
    for id, args in pairs(pendingQueue) do
        WA:SetButton(args[1], args[2], args[3], args[4], args[5], args[6],
                     args[7])
    end
    wipe(pendingQueue)
    if pendingQueueHandle then
        YUI.Event:Off(pendingQueueHandle)
        pendingQueueHandle = nil
    end
end

function WA:SetButton(aura_env, buttonName, type, context, context2, context3,
                      tooltip)
    if WeakAuras.IsOptionsOpen() then return end

    if SecurityAPI.InCombatLockdown() then
        if not pendingQueue[aura_env.id] then
            if not next(pendingQueue) then
                pendingQueueHandle = YUI.Event:On("PLAYER_REGEN_ENABLED", FlushPendingQueue)
            end
            pendingQueue[aura_env.id] = {
                aura_env, buttonName, type, context, context2, context3, tooltip
            }
        end
        return
    end

    local f, r

    if type == "player" then
        -- UnitFrame Player
        if not self:GetUF(aura_env.id) then
            r = WeakAuras.GetRegion(aura_env.id)
            f = self:CreateUF(aura_env.id, buttonName)
            f:SetAllPoints(r)
            f:SetSize(r.width, r.height)
            f:SetAttribute("unit", "player")
            f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            f:SetAttribute("type1", "target") -- Left click targets unit
            f:SetAttribute("type2", "togglemenu") -- Right click opens the context menu

            -- Function to show the tooltip
            f:SetScript("OnEnter", function(self)
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                local unit = self:GetAttribute("unit")
                if unit then
                    GameTooltip:SetUnit(unit)
                    GameTooltip:Show()
                end
            end)

            f:SetScript("OnLeave", function(self) YUI.HideGameTooltip() end)
        end

        self:ShowUF(aura_env.id)

    elseif type == "vehicle" then
        -- Vehicle
        if not self:GetUF(aura_env.id) then
            r = WeakAuras.GetRegion(aura_env.id)
            f = self:CreateUF(aura_env.id, buttonName)
            f:SetAllPoints(r)
            f:SetSize(r.width, r.height)
            f:SetAttribute("unit", "vehicle")
            f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            f:SetAttribute("type1", "target") -- Left click targets unit
            f:SetAttribute("type2", "togglemenu") -- Right click opens the context menu

            -- Function to show the tooltip
            f:SetScript("OnEnter", function(self)
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                local unit = self:GetAttribute("unit")
                if unit then
                    GameTooltip:SetUnit(unit)
                    GameTooltip:Show()
                end
            end)

            f:SetScript("OnLeave", function(self) YUI.HideGameTooltip() end)
        end

        self:ShowUF(aura_env.id)

    elseif type == "custom" then
        if not aura_env.button then
            aura_env.button = CreateFrame("Button", buttonName,
                                          WeakAuras.GetRegion(aura_env.id),
                                          "SecureActionButtonTemplate")
            f = aura_env.button
            f:SetAllPoints()
            Secure:RegisterActionClicks(f)
            f:SetScript("OnClick", function(self, btn, down)
                if not Secure:ShouldRunActionClick(down) then return end
                if context then context(btn) end
            end)
            if tooltip then
                f:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(tooltip, 0, 1, 0, 1, 1)
                end)
                f:SetScript("OnLeave", function(self)
                    YUI.HideGameTooltip()
                end)
            end
        end
    else
        -- others
        if not aura_env.button then
            aura_env.button = CreateFrame("Button", buttonName,
                                          WeakAuras.GetRegion(aura_env.id),
                                          "SecureActionButtonTemplate")
            f = aura_env.button
            f:SetAllPoints()
            Secure:RegisterActionClicks(f)
            f:SetAttribute("type", type)

            if type == "macro" then
                f:SetAttribute("macrotext1", context)
                if context2 ~= nil then
                    f:SetAttribute("macrotext2", context2)
                end
                if context3 ~= nil then
                    f:SetAttribute("macrotext3", context3)
                end
            elseif type == "item" then
                f:SetAttribute("item", "item:" .. context)
            elseif type == "spell" then
                local spell = (context2 and SpellAPI.GetName(context)) or
                                  context
                f:SetAttribute("spell", spell)
            end

            if tooltip then
                f:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(tooltip, 0, 1, 0, 1, 1)
                end)

                f:SetScript("OnLeave", function(self)
                    YUI.HideGameTooltip()
                end)
            end

        end
    end

    return f
end

function WA:ShowButton(aura_env)
    if self:GetUF(aura_env.id) then self:ShowUF(aura_env.id) end
end

function WA:HideButton(aura_env)
    if self:GetUF(aura_env.id) then self:HideUF(aura_env.id) end
end

function WA:SetButtonTooltipByItem(aura_env, buttonName, itemId)
    if not aura_env.button then
        local r = WeakAuras.GetRegion(aura_env.id)
        aura_env.button = CreateFrame("Button", buttonName, r,
                                      "SecureActionButtonTemplate")
    end

    aura_env.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:SetItemByID(itemId)
        GameTooltip:Show()
    end)

    aura_env.button:SetScript("OnLeave", function(self) YUI.HideGameTooltip() end)
end

function WA:SetWeakAuraNever(id, state)
    if not WeakAuras or not WeakAuras.GetData or not WeakAuras.Add then
        return
    end
    local targetState = (state == true)
    local changed = false
    local function apply(aid)
        local data = WeakAuras.GetData(aid)
        if not data then return end
        data.load = data.load or {}
        local current = data.load.use_never and true or false
        if current ~= targetState then
            data.load.use_never = targetState
            changed = true
            if WeakAuras.SetData then
                WeakAuras.SetData(aid, data)
            else
                WeakAuras.Add(data)
            end
        end
        local children = data.controlledChildren
        if children and type(children) == "table" then
            for _, cid in ipairs(children) do apply(cid) end
        end
    end
    apply(id)
    if changed and WeakAuras.ScanForLoads then WeakAuras.ScanForLoads() end
end

function WA:GetWeakAuraNever(id)
    if not WeakAuras or not WeakAuras.GetData then return nil end
    local data = WeakAuras.GetData(id)
    if not data or not data.load then return nil end
    return data.load.use_never and true or false
end

function WA:SetWeakAuraXOffset(id, x)
    if not WeakAuras or not WeakAuras.GetData or not WeakAuras.Add then
        return
    end
    local data = WeakAuras.GetData(id)
    if not data then return end
    data.xOffset = x
    if WeakAuras.SetData then
        WeakAuras.SetData(id, data)
    else
        WeakAuras.Add(data)
    end
    if WeakAuras.ScanForLoads then WeakAuras.ScanForLoads() end
end

