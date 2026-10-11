local _, YUI = ...

YUI.LUX = {}
LWA = LWA or {}

local LUX = YUI.LUX

local CLASS_MAP = {
    ["WARRIOR"] = "战士",
    ["PALADIN"] = "骑士",
    ["HUNTER"] = "猎人",
    ["ROGUE"] = "盗贼",
    ["PRIEST"] = "牧师",
    ["DEATHKNIGHT"] = "死骑",
    ["SHAMAN"] = "萨满",
    ["MAGE"] = "法师",
    ["WARLOCK"] = "术士",
    ["DRUID"] = "小德"
}

local MAX_DYNAMIC_SPELL_PER_ROW = 3
-- local RES_YOFFSET = 5
-- local SEC_YOFFSET = 7

LUX.config = {}
LUX.config.RES_YOFFSET = 5
LUX.config.SEC_YOFFSET = 7


function LUX:Init(aura_env)
    local local_env = aura_env
    local CLASS = local_env.id:gsub("通用设置 %- ", "")
    local CLASS_CN = CLASS_MAP[string.upper(string.gsub(CLASS, "%s+", ""))]
    local_env.CLASS = CLASS

    LWA[CLASS] = LWA[CLASS] or {}

    local LWA = LWA[CLASS]

    LWA.config = nil
    LWA.configs = LWA.configs or {}
    LWA.configs["general"] = local_env.config

    LWA.CLASS = CLASS
    LWA.MAX_WIDTH = 405
    LWA.RESOURCES_HEIGHT = 0

    local CLASS_GROUP = CLASS_CN .. " - Luxthos - " .. CLASS
    local CLASS_OPTIONS = "职业设置 - " .. CLASS
    local CORE_GROUP = "主要技能 - " .. CLASS
    local RESOURCES_GROUP = "资源组 - " .. CLASS
    local DYNAMIC_EFFECTS_GROUP = "动态效果 - " .. CLASS
    local DYNAMIC_SPELLS_GROUP = "动态技能 - " .. CLASS
    local LEFT_SIDE_GROUP = "左侧组 - " .. CLASS
    local RIGHT_SIDE_GROUP = "右侧组 - " .. CLASS
    local MAINTENANCE_GROUP = "维护组 - " .. CLASS
    local CAST_BAR = "施法条 - " .. CLASS

    local_env.parent = CLASS_GROUP
    local nbCore = 8
    local resources

    local function tclone(t1)
        local t = {}

        if t1 then
            for k, v in pairs(t1) do
                if "table" == type(v) then v = tclone(v) end

                if "string" == type(k) then
                    t[k] = v
                else
                    tinsert(t, v)
                end
            end
        end

        return t
    end

    local function tmerge(...)
        local ts = {...}
        local t = tclone(ts[1])
        local t2

        for i = 2, #ts do
            t2 = ts[i] or {}

            for k, v in pairs(t2) do
                if "table" == type(v) then
                    v = tclone(v)

                    if t[k] and #t[k] == 0 then
                        t[k] = tmerge(t[k], v)
                    else
                        t[k] = v
                    end
                else
                    t[k] = v
                end
            end
        end

        return t
    end

    local function SetRegionSize(r, w, h)
        r:SetRegionWidth(w)
        r:SetRegionHeight(h)
    end

    local function ResizeAnchorFrame()
        local config = LWA.GetConfig()
        local h = 0
        local cr = WeakAuras.GetRegion(CORE_GROUP)

        if cr and cr:IsVisible() then
            h = cr:GetHeight()

            if config.primary.resources_position == 1 then -- Above
                h = h + config.primary.spacing + LWA.RESOURCES_HEIGHT
            end
        end

        if 1 == h % 2 then h = h + 1 end

        SetRegionSize(local_env.region, LWA.MAX_WIDTH, max(1, h, config.primary
                                                               .height +
                                                               config.primary
                                                                   .spacing +
                                                               LWA.RESOURCES_HEIGHT))

        local g = WeakAuras.GetRegion(g)

        if g then
            g:PositionChildren()

            if 0 == #g.sortedChildren then
                g:SetHeight(configs[i].height)
                g.currentHeight = configs[i].height
            end
        end
    end

    function LWA.GetConfig(grp, force)
        local default = {
            style = {
                border_size = 0,
                border_color = {[1] = 0, [2] = 0, [3] = 0, [4] = 1},
                apply_border = true,
                zoom = 30
            },
            primary = {
                nb = 8,
                width = 48,
                height = 48,
                spacing = 0,
                resources_position = 2 -- Below
            },
            secondary = {width = 38, height = 38, spacing = 0},
            dynamic = {width = 38, height = 38, spacing = 0, margin = 10},
            side = {
                width = 36,
                height = 36,
                spacing = 0,
                margin = 3,
                grow_horizontal = 0
            },
            maintenance = {width = 36, height = 36, spacing = 0, margin = 10},
            ooc_alpha = {alpha = 1, ignore_enemy = true, ignore_friendly = true},
            resources = {health_bar = {format = 1}, mana_bar = {format = 1}}
        }

        if force or not LWA.config or WeakAuras.IsOptionsOpen() then
            LWA.config = tmerge(default, LWA.configs["general"],
                                LWA.configs["class"] or {})
        end

        if grp then return LWA.config[grp] or {} end

        return LWA.config
    end

    local throttledInitHandler = nil
    local initLastRun = 0

    function LWA.ThrottledInit()
        if throttledInitHandler then return end

        local currentTime = time()

        if WeakAuras.IsImporting() then
            throttledInitHandler = C_Timer.NewTimer(2, LWA.ThrottledInit)

        elseif initLastRun <= currentTime - 0.2 then
            throttledInitHandler = C_Timer.NewTimer(0.05, LWA.Init)
        else
            throttledInitHandler = C_Timer.NewTimer(
                                       max(0.05, currentTime - initLastRun),
                                       LWA.Init)
        end
    end

    function LWA.Init()
        if WeakAuras.IsImporting() then return end

        initLastRun = time()

        local config = LWA.GetConfig(nil, true)
        local isOptionsOpen = WeakAuras.IsOptionsOpen()
        local zoom = config.style.zoom / 100

        if throttledInitHandler then
            throttledInitHandler:Cancel()
            throttledInitHandler = nil
        end

        if not local_env.parentFrame then
            local_env.parentFrame = WeakAuras.GetRegion(CLASS_GROUP)
        end

        if local_env.parentFrame and not local_env.parentFrame.SetRealScale then
            local_env.parentFrame.SetRealScale = local_env.parentFrame.SetScale

            local_env.parentFrame.SetScale =
                function(self, scale)
                    local_env.parentFrame:SetRealScale(scale)
                    local castBar = WeakAuras.GetRegion(CAST_BAR)

                    if castBar then castBar:SetScale(scale) end
                end
        end

        if isOptionsOpen then
            nbCore = config.primary.nb
        else
            nbCore = max(8, min(nbCore, config.primary.nb))
        end

        LWA.MAX_WIDTH =
            nbCore * (config.primary.width + config.primary.spacing) -
                config.primary.spacing

        local function InitIcons(group, c, selfPoint)
            local grpRegion = WeakAuras.GetRegion(group)

            if not grpRegion then return end

            local i, isAbilities = 0, CORE_GROUP == group

            for childId, regions in pairs(grpRegion.controlledChildren) do
                local region = regions[""] and regions[""].regionData.region

                i = i + 1

                if region then
                    region:SetAnchor(selfPoint, region.relativeTo,
                                     region.relativePoint)

                    if region.SetZoom then
                        region:SetZoom(min(1, zoom + (region.extraZoom or 0)))
                    else
                        print(
                            "LWA Issue: " .. CLASS .. " > " .. group .. " > " ..
                                childId)
                    end

                    if isAbilities and i > nbCore then
                        SetRegionSize(region, config.secondary.width,
                                      config.secondary.height)
                    else
                        SetRegionSize(region, c.width, c.height)
                    end

                    LWA.UpdateBorder(region)
                end
            end

            if isAbilities then
                grpRegion:PositionChildren()

                if not isOptionsOpen then
                    nbCore = max(8, min(#grpRegion.sortedChildren,
                                        config.primary.nb))

                    LWA.MAX_WIDTH = nbCore *
                                        (config.primary.width +
                                            config.primary.spacing) -
                                        config.primary.spacing
                end

                local_env.region:SetRegionWidth(LWA.MAX_WIDTH)
            end
        end

        InitIcons(CORE_GROUP, config.primary, "TOP")
        InitIcons(LEFT_SIDE_GROUP, config.side, "TOPRIGHT")
        InitIcons(RIGHT_SIDE_GROUP, config.side, "TOPLEFT")
        InitIcons(MAINTENANCE_GROUP, config.maintenance, "TOP")
        InitIcons(DYNAMIC_EFFECTS_GROUP, config.dynamic, "BOTTOMLEFT")
        InitIcons(DYNAMIC_SPELLS_GROUP, config.dynamic, "BOTTOMRIGHT")

        LWA.UpdateResources()

        for i, g in ipairs({
            DYNAMIC_EFFECTS_GROUP, DYNAMIC_SPELLS_GROUP, LEFT_SIDE_GROUP,
            RIGHT_SIDE_GROUP
        }) do
            g = WeakAuras.GetRegion(g)

            if g then g:PositionChildren() end
        end
    end

    hooksecurefunc("SetUIVisibility", function(isVisible)
        if isVisible and LWA.ThrottledInit then LWA.ThrottledInit() end
    end)

    function LWA.UpdateResources()
        if WeakAuras.IsImporting() then return end

        local config = LWA.GetConfig()

        local totalHeight, nb = 0, 0
        local h1 = config.primary.height
        local s1 = config.primary.spacing
        local y = 0
        local grpRegion = WeakAuras.GetRegion(RESOURCES_GROUP)

        if not resources then
            local grpData = WeakAuras.GetData(RESOURCES_GROUP)

            resources = grpData and grpData.controlledChildren
        end

        if grpRegion and resources and #resources > 0 then
            if config.primary.resources_position == 2 then -- Below
                -- y = h1 + s1
                y = h1 + LUX.config.RES_YOFFSET
            end

            grpRegion:SetOffset(0, -y)

            local isOptionsOpen = WeakAuras.IsOptionsOpen()

            local resData, resRegion, isVisible, regionType
            local w, h = 0, 0

            local function InitResource(region, index, nb)
                if not region then return end

                index = max(1, index or 1)
                nb = max(1, nb or 1)

                w, h = LWA.MAX_WIDTH, 20

                if nb > 1 then
                    local s = config.primary.spacing

                    w = (w + s) / nb - s
                end

                local cg = region.configGroup

                if cg and config.resources[cg] then
                    h = config.resources[cg].height or 20
                end

                SetRegionSize(region, w, h)
                region.bar:Update()
                -- LWA.UpdateBorder(region, true)
                LWA.UpdateBar({region = region}, index, nb)

                if region.bar.spark then
                    region.bar.spark:SetHeight(max(15, Round(h * 2)))
                end
            end

            y = 0

            for _, resId in ipairs(resources) do
                resRegion = WeakAuras.GetRegion(resId)

                if resRegion then
                    isVisible = isOptionsOpen or resRegion:IsVisible()
                    regionType = resRegion.regionType
                    h = 0

                    if "aurabar" == regionType then
                        InitResource(resRegion)

                    elseif "dynamicgroup" == regionType then
                        local nbChild = 0
                        local childRegions = {}

                        for _, region in pairs(resRegion.controlledChildren) do
                            if region and region[""] then
                                nbChild = nbChild + 1

                                childRegions[region[""].regionData.dataIndex] =
                                    region[""].regionData.region
                            end
                        end

                        if not isOptionsOpen and childRegions[1] then
                            isVisible = childRegions[1]:IsVisible()
                        end

                        for i, region in ipairs(childRegions) do
                            InitResource(region, i, nbChild)

                            region:SetYOffset(-y)
                        end
                    end

                    if isVisible then
                        nb = nb + 1

                        if isVisible then
                            if "dynamicgroup" == regionType then
                                resRegion:PositionChildren()
                            else
                                resRegion:SetOffset(0, -y)
                            end
                        end

                        totalHeight = totalHeight + h
                        -- y = y + h + s1
                        y = y + h + 1
                    end
                end
            end

            LWA.RESOURCES_HEIGHT = totalHeight + max(nb - 1, 0) *
                                       config.primary.spacing
        end

        grpRegion = WeakAuras.GetRegion(CORE_GROUP)

        if grpRegion then grpRegion:DoPositionChildren() end

        ResizeAnchorFrame()

        local castBar = WeakAuras.GetRegion(CAST_BAR)

        if castBar then
            castBar:SetParent(UIParent)

            if local_env.parentFrame then
                castBar:SetScale(local_env.parentFrame:GetScale())
            end
        end

        grpRegion = WeakAuras.GetRegion(MAINTENANCE_GROUP)

        if grpRegion then grpRegion:DoPositionChildren() end

        C_Timer.After(0.1, ResizeAnchorFrame)
    end

    function LWA.GrowCore(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then
            C_Timer.After(0.125, ResizeAnchorFrame)

            return
        end

        local config = LWA.GetConfig()

        local w1 = config.primary.width
        local h1 = config.primary.height
        local s1 = config.primary.spacing

        local maxCore = min(nb, config.primary.nb)
        local x, y
        local xOffset = ((maxCore - 1) * (w1 + s1) / 2)
        local yOffset = 0

        if not WeakAuras.IsOptionsOpen() then
            nbCore = max(8, maxCore)

            LWA.MAX_WIDTH = nbCore * (w1 + s1) - s1

            ResizeAnchorFrame()
        end

        if config.primary.resources_position == 1 then -- Above
            yOffset = LWA.RESOURCES_HEIGHT + s1
        end

        for i, regionData in ipairs(activeRegions) do
            x = (i - 1) * (w1 + s1) - xOffset
            y = -yOffset

            SetRegionSize(regionData.region, w1, h1)

            newPositions[i] = {x, y}

            if i == maxCore then break end
        end

        local maxSecondary = nb - maxCore

        if maxSecondary > 0 then
            local w2 = config.secondary.width
            local h2 = config.secondary.height
            local s2 = config.secondary.spacing

            local nbPerRow = math.floor((LWA.MAX_WIDTH + s2) / (w2 + s2)) or 1
            local yOffset = yOffset + h1 - h2 + max(s1, s2) - s2
            local i2, m

            if config.primary.resources_position == 2 then -- Below
                -- yOffset = yOffset + LWA.RESOURCES_HEIGHT + s1
                yOffset = yOffset + LWA.RESOURCES_HEIGHT + LUX.config.SEC_YOFFSET
            end

            for i, regionData in ipairs(activeRegions) do
                if i > maxCore then
                    i2 = i - maxCore
                    m = (i2 % nbPerRow)

                    if m == 1 then
                        xOffset =
                            (min(maxSecondary - i + maxCore, nbPerRow - 1)) *
                                (w2 + s2) / 2
                        yOffset = yOffset + h2 + s2
                    end

                    if m == 0 then m = nbPerRow end

                    x = (m - 1) * (w2 + s2) - xOffset
                    y = -yOffset

                    SetRegionSize(regionData.region, w2, h2)

                    newPositions[i] = {x, y}
                end
            end
        end

        C_Timer.After(0.125, ResizeAnchorFrame)
    end

    function LWA.GrowDynamicEffects(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local w = config.dynamic.width
        local h = config.dynamic.height
        local s1 = config.primary.spacing
        local s2 = config.dynamic.spacing

        local xOffset = 0
        local yOffset = config.dynamic.margin + max(s1, s2) - s2 - h
        local nbPerRow, m = math.floor(((LWA.MAX_WIDTH / 2) + s2) / (w + s2)) or
                                1
        nbPerRow = math.min(nbPerRow, MAX_DYNAMIC_SPELL_PER_ROW)

        for i, regionData in ipairs(activeRegions) do
            m = (i % nbPerRow)

            if m == 1 then
                xOffset = 0
                yOffset = yOffset + h + s2
            end

            if m == 0 then m = nbPerRow end

            newPositions[i] = {xOffset, yOffset}

            xOffset = xOffset + w + s2
        end
    end

    function LWA.GrowDynamicSpells(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local w = config.dynamic.width
        local h = config.dynamic.height
        local s1 = config.primary.spacing
        local s2 = config.dynamic.spacing

        local xOffset = 0
        local yOffset = config.dynamic.margin + max(s1, s2) - s2 - h
        local nbPerRow, m = math.floor(((LWA.MAX_WIDTH / 2) + s2) / (w + s2)) or
                                1
        nbPerRow = math.min(nbPerRow, MAX_DYNAMIC_SPELL_PER_ROW)

        for i, regionData in ipairs(activeRegions) do
            m = (i % nbPerRow)

            if m == 1 then
                xOffset = 0
                yOffset = yOffset + h + s2
            end

            if m == 0 then m = nbPerRow end

            newPositions[i] = {-xOffset, yOffset}

            xOffset = xOffset + w + s2
        end
    end

    function LWA.GrowLeftSide(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local w1 = config.primary.width
        local h1 = config.primary.height
        local s1 = config.primary.spacing

        local w2 = config.side.width
        local h2 = config.side.height
        local s2 = config.side.spacing

        local x, y
        local xOffset = config.side.margin + max(s1, s2)
        local yOffset = 0

        for i, regionData in ipairs(activeRegions) do
            x = -xOffset
            y = -yOffset

            newPositions[i] = {x, y}

            if config.side.grow_horizontal then
                xOffset = xOffset + w2 + s2
            else
                yOffset = yOffset + h2 + s2
            end
        end
    end

    function LWA.GrowRightSide(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local w1 = config.primary.width
        local h1 = config.primary.height
        local s1 = config.primary.spacing

        local w2 = config.side.width
        local h2 = config.side.height
        local s2 = config.side.spacing

        local x, y
        local xOffset = config.side.margin + max(s1, s2)
        local yOffset = 0

        for i, regionData in ipairs(activeRegions) do
            x = xOffset
            y = -yOffset

            newPositions[i] = {x, y}

            if config.side.grow_horizontal then
                xOffset = xOffset + w2 + s2
            else
                yOffset = yOffset + h2 + s2
            end
        end
    end

    function LWA.GrowMaintenance(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local maxCore = min(nb, config.primary.nb)

        local w1 = config.primary.width
        local h1 = config.primary.height
        local s1 = config.primary.spacing

        local w2 = config.maintenance.width
        local h2 = config.maintenance.height
        local s2 = config.maintenance.spacing

        local x, y
        local xOffset = (maxCore - 1) * (w1 + s1) / 2
        local yOffset = config.maintenance.margin + max(s1, s2) - s2 - h2

        local nbPerRow = math.floor((LWA.MAX_WIDTH + s2) / (w2 + s2)) or 1
        local m

        for i, regionData in ipairs(activeRegions) do
            m = (i % nbPerRow)

            if m == 1 then
                xOffset = (min(nb - i, nbPerRow - 1)) * (w2 + s2) / 2
                yOffset = yOffset + h2 + s2
            end

            if m == 0 then m = nbPerRow end

            x = (m - 1) * (w2 + s2) - xOffset
            y = -yOffset

            newPositions[i] = {x, y}
        end
    end

    function LWA.UpdateBorder(region, isBar)
        if #region.subRegions > 0 then
            local config, size, r, g, b, a = LWA.GetConfig(), 0

            if not isBar or (isBar and config.style.apply_border) then
                size = config.style.border_size
                r, g, b, a = unpack(config.style.border_color)
            end

            for _, border in ipairs(region.subRegions) do
                if "subborder" == border.type then
                    border:SetVisible(size > 0)

                    if size > 0 then
                        local bd = border:GetBackdrop()
                        bd.edgeSize = size
                        border:SetBackdrop(bd)
                        border:SetBorderColor(r, g, b, a)
                    end
                end
            end
        end
    end

    local function MixRGB(c1, c2, pos)
        pos = 1 - (pos or 0.5)

        return {
            (c1[1] * pos) + (c2[1] * (1 - pos)),
            (c1[2] * pos) + (c2[2] * (1 - pos)),
            (c1[3] * pos) + (c2[3] * (1 - pos)),
            (c1[4] * pos) + (c2[4] * (1 - pos))
        }
    end

    function LWA.UpdateBar(aura, i, nb)
        local config = LWA.GetConfig("resources")
        local e = aura or aura_env
        local region = e.region
        local cg = region.configGroup

        if not (region and cg and config[cg]) then return end

        cg = config[cg]

        local cs = region.colorState or ""

        if cs ~= "" then cs = cs .. "_" end

        i = (i or region.index or 1) - (region.colorOffset or 0)
        nb = min(region.colorMax or 99, nb or 1)

        local c1, c2 = cg[cs .. "color1"], cg[cs .. "color2"]
        local bar = region.bar

        if c1 and c2 then
            if cg[cs .. "gradient"] and cg[cs .. "gradient"] < 3 then
                if nb > 1 and 1 == cg[cs .. "gradient"] then
                    local cc1, cc2 = c1, c2

                    if i > 1 then
                        c1 = MixRGB(cc1, cc2, (i - 1) / nb)
                    end

                    c2 = MixRGB(cc1, cc2, i / nb)
                end

                local orientation = "HORIZONTAL"

                if 2 == cg[cs .. "gradient"] then
                    orientation = "VERTICAL"

                    local tmp = c1
                    c1 = c2
                    c2 = tmp
                end

                bar.fg:SetGradient(orientation, CreateColor(unpack(c1)),
                                   CreateColor(unpack(c2)))
            else
                bar:SetForegroundColor(unpack(c1))
            end

            if region.ot then region.ot:SetColorTexture(unpack(c2)) end
        end
    end

    function LWA.GrowDynamicResource(newPositions, activeRegions)
        local nb = #activeRegions

        if nb <= 0 then return end

        local config = LWA.GetConfig()

        local s = config.primary.spacing

        local w, h = (LWA.MAX_WIDTH + s) / nb
        local x, xOffset = 0, (LWA.MAX_WIDTH - w + s) / 2

        for i, regionData in ipairs(activeRegions) do
            x = (i - 1) * w - xOffset

            regionData.region:SetRegionWidth(w - s)
            LWA.UpdateBar({region = regionData.region}, i, nb)
            regionData.region.bar:Update()

            newPositions[i] = {x, 0}
        end
    end

    local function round(num, decimals)
        local mult = 10 ^ (decimals or 0)

        return Round(num * mult) / mult
    end

    local barFormats = {
        "value", "kvalue", "value (percent%)", "kvalue (percent%)", "percent%"
    }

    function LWA.UpdateBarText(value, percent, format)
        local text = barFormats[format] or "value"

        text = text:gsub("percent", round(percent, 0))

        if 2 == format or 4 == format then
            local rem = math.fmod(value, 1000) or 0

            if rem >= 950 then rem = 0 end

            text = text:gsub("kvalue",
                             FormatLargeNumber(Round((value - rem) / 1000)) ..
                                 "." .. Round(rem / 100) .. "K"):gsub("%.0K",
                                                                      "K"):gsub(
                       "%.", DECIMAL_SEPERATOR)
        else
            text = text:gsub("value", value)
        end

        return text
    end
end

function LUX:InitClassCfg(aura_env)
    aura_env.CLASS = aura_env.id:gsub("职业设置 %- ", "")

    LWA[aura_env.CLASS] = LWA[aura_env.CLASS] or {}

    local LWA = LWA[aura_env.CLASS]

    LWA.configs = LWA.configs or {}
    LWA.configs["class"] = aura_env.config
end
