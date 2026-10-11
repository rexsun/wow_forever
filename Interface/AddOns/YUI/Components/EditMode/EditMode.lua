-------------------------------------------------------------------------------
-- YUI | 编辑模式
-------------------------------------------------------------------------------
local _, YUI = ...

YUI.EditMode = {}

local EM = YUI.EditMode
local C_EditMode = C_EditMode
local C_AddOns = C_AddOns
local EditModeManagerFrame = EditModeManagerFrame
local UIParent = UIParent
local CreateFrame = CreateFrame

local function GetGlobalDB()
    if YUI.DB and YUI.DB.GetGlobal then
        local global = YUI.DB:GetGlobal(YUI.ProductId or "suite")
        if type(global) == "table" then
            return global
        end
    end
    return type(YUI.global) == "table" and YUI.global or nil
end

-- 布局名称
local LAYOUT_NAME = "YUI"
local LAYOUT_COLORED_NAME = "|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r"

-- 判断是否为 YUI 布局 (YUI 或 YUI vX)
function EM:IsYUILayout(name)
    if not name then return false end
    return name == LAYOUT_NAME or name:match("^" .. LAYOUT_NAME .. " v%d+$")
end

-- 获取布局版本号
function EM:GetCurrentLayoutVersion(name)
    if not name then return -1 end
    if name == LAYOUT_NAME then return 0 end -- 旧版 YUI 视为 v0
    local ver = name:match("^" .. LAYOUT_NAME .. " v(%d+)$")
    return tonumber(ver) or -1
end

-- 获取最新版本的 YUI 布局名称 (从 Data 获取)
function EM:GetLatestYUILayout()
    if not YUI.Data then return nil, 0 end
    local version = YUI.Data:GetVersion("EditMode")

    if version > 0 then
        local name = LAYOUT_NAME .. " v" .. version
        return name, version
    end
    return LAYOUT_NAME, 0
end
-- local DEFAULT_LAYOUT_STRING =
--     "2 50 0 0 0 7 7 UIParent -20.0 2.0 -1 ##$$%/&('%)$+$,$ 0 1 0 6 0 MainActionBar 0.0 4.0 -1 ##$$%/&('%(#,$ 0 2 0 6 0 MultiBarBottomLeft 0.0 4.0 -1 ##$$%/&('%(#,$ 0 3 0 7 7 UIParent -392.5 2.0 -1 #$$'%,&('&(#,# 0 4 0 7 7 UIParent -383.3 4.5 -1 ##$'%,&('&(#,# 0 5 0 7 7 UIParent 345.5 4.5 -1 ##$'%,&('&(#,# 0 6 0 0 0 UIParent 2037.4 -395.0 -1 #$$$%/&('%(&,# 0 7 0 8 2 DamageMeter 0.0 4.0 -1 #$$$%/&('%(#,# 0 10 0 1 1 UIParent -1.0 -978.0 -1 ##$$&('% 0 11 0 6 0 MultiBarLeft 0.0 4.0 -1 ##$%&''%,# 0 12 0 6 0 MultiBarBottomRight 0.0 4.0 -1 ##$$&('% 1 -1 0 1 1 UIParent -8.4 -891.4 -1 #'$#%$ 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -335.5 -181.0 -1 $#3& 3 1 0 4 4 UIParent 335.5 -184.4 -1 %$3& 3 2 0 8 8 UIParent -361.2 265.3 -1 %#&#3& 3 3 0 0 0 UIParent 386.0 -218.0 -1 '$(#)#-k.G/#1$3#5%607-7$ 3 4 0 0 0 UIParent 2.0 -466.0 -1 ,#-3.1/#0$1#2(5%6+7U 3 5 0 2 2 UIParent -294.0 -307.0 -1 &#*$3# 3 6 0 2 2 UIParent -1576.5 -2.0 -1 -k.G/#4&5%6-6$7-7$ 3 7 0 1 1 UIParent -362.0 -867.6 -1 3# 4 -1 0 4 4 UIParent 0.0 -380.0 -1 # 5 -1 0 6 0 MultiBar5 0.0 4.0 -1 # 6 0 0 2 2 UIParent -277.4 -5.8 -1 ##$#%#&.(()( 6 1 0 5 3 MinimapCluster -4.4 -61.8 -1 ##$#%#'+(*)(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -696.8 -1.9 -1 # 8 -1 0 0 0 UIParent 52.7 -995.0 -1 #'$Q%$&Y 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 5 5 UIParent 0.0 -187.2 -1 # 12 -1 0 2 8 MinimapCluster 0.4 -4.4 -1 ##$#%# 13 -1 0 1 1 UIParent -429.8 -2.0 -1 ##$$%)&' 14 -1 1 2 2 MicroButtonAndBagsBar 0.0 0.0 -1 ##$#%( 15 0 0 1 1 UIParent 900.0 -278.0 -1 # 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 # 16 -1 0 0 2 ChatFrame1 29.0 60.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 8 UIParent -474.2 0.0 -1 #- 19 -1 0 1 1 UIParent 0.0 -962.0 -1 ## 20 0 0 7 7 UIParent 0.4 350.6 -1 ##$*%$&&'&(-($)#+$,$-$ 20 1 0 1 7 UIParent 0.0 306.6 -1 ##$/%$&(''(-($)#+$,$-$ 20 2 0 7 1 EssentialCooldownViewer -1.5 4.0 -1 ##$$%$&''&(-($)#+$,$-$ 20 3 0 7 7 UIParent -280.0 390.6 -1 #$$$%#&('((-($)#*#+$,$-$.U 21 -1 0 7 7 UIParent 0.0 332.0 -1 #$$# 22 0 0 1 1 UIParent 383.2 -97.4 -1 #$$$%$&.'&(#)-)$*$+$,$ 22 1 0 7 7 UIParent 0.0 950.6 -1 &('()-)$*#+$ 22 2 0 4 4 UIParent 0.0 380.0 -1 &('()-)$*#+$ 22 3 0 4 4 UIParent 0.0 340.0 -1 &('()-)$*#+$ 23 -1 0 8 2 MicroMenuContainer 0.0 4.0 -1 ##$#%#&O'C($)U+$,$-'.(/#"
-- local DEFAULT_LAYOUT_STRING =
    -- "2 50 0 0 0 7 7 UIParent -20.0 2.0 -1 ##$$%/&('%)$+$,$ 0 1 0 6 0 MainActionBar 0.0 4.0 -1 ##$$%/&('%(#,$ 0 2 0 0 0 UIParent 674.2 -952.1 -1 ##$$%/&('%(#,$ 0 3 0 7 7 UIParent -392.5 2.0 -1 #$$'%,&('&(#,# 0 4 0 7 7 UIParent -383.3 4.5 -1 ##$'%,&('&(#,# 0 5 0 7 7 UIParent 345.5 4.5 -1 ##$'%,&('&(#,# 0 6 0 0 0 UIParent 2037.4 -395.0 -1 #$$$%/&('%(&,# 0 7 0 8 2 DamageMeter 0.0 4.0 -1 #$$$%/&('%(#,# 0 10 0 1 1 UIParent -1.0 -978.0 -1 ##$$&('% 0 11 0 0 0 UIParent 521.4 -891.8 -1 ##$%&''%,# 0 12 0 0 0 UIParent 674.2 -918.1 -1 ##$$&('% 1 -1 0 1 1 UIParent -8.4 -891.4 -1 #'$#%$ 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -335.5 -181.0 -1 $#3& 3 1 0 4 4 UIParent 335.5 -184.4 -1 %$3& 3 2 0 8 8 UIParent -361.2 265.3 -1 %#&#3& 3 3 0 0 0 UIParent 1384.0 -305.8 -1 '$(#)#-k.?/#1$3#5%607-7$ 3 4 0 0 0 UIParent 2.0 -466.0 -1 ,#-3.1/#0$1#2(5%6+7U 3 5 0 2 2 UIParent -294.0 -307.0 -1 &#*$3# 3 6 0 2 2 UIParent -1576.5 -2.0 -1 -k.G/#4&5%6-6$7-7$ 3 7 0 1 1 UIParent -362.0 -867.6 -1 3# 4 -1 0 4 4 UIParent 0.0 -380.0 -1 # 5 -1 0 0 0 UIParent 1250.2 -827.6 -1 # 6 0 0 2 2 UIParent -277.4 -5.8 -1 ##$#%#&.(()( 6 1 0 5 3 MinimapCluster -4.4 -61.8 -1 ##$#%#'+(*)(-$ 6 2 0 1 4 UIParent -194.5 -2.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -696.8 -1.9 -1 # 8 -1 0 0 0 UIParent 52.7 -995.0 -1 #'$Q%$&Y 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 5 5 UIParent 0.0 -187.2 -1 # 12 -1 0 2 8 MinimapCluster 0.4 -4.4 -1 ##$#%# 13 -1 0 1 1 UIParent -429.8 -2.0 -1 ##$$%)&' 14 -1 1 2 2 MicroButtonAndBagsBar 0.0 0.0 -1 ##$#%( 15 0 0 1 1 UIParent 900.0 -278.0 -1 # 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 # 16 -1 0 0 2 ChatFrame1 29.0 60.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 8 UIParent -474.2 0.0 -1 #- 19 -1 0 1 1 UIParent 0.0 -962.0 -1 ## 20 0 0 7 7 UIParent 0.4 350.6 -1 ##$*%$&&'&(-($)#+$,$-$ 20 1 0 1 7 UIParent 0.0 306.6 -1 ##$/%$&(''(-($)#+$,$-$ 20 2 0 0 0 UIParent 903.5 -627.3 -1 ##$$%$&''&(-($)#+$,$-$ 20 3 0 7 7 UIParent -280.0 390.6 -1 #$$$%#&('((-($)#*#+$,$-$.U 21 -1 0 7 7 UIParent 0.0 332.0 -1 #$$# 22 0 0 1 1 UIParent 383.2 -97.4 -1 #$$$%$&.'&(#)-)$*$+$,$-#.#/U0% 22 1 0 7 7 UIParent 0.0 950.6 -1 &('()-)$*#+$ 22 2 0 4 4 UIParent 0.0 380.0 -1 &('()-)$*#+$ 22 3 0 4 4 UIParent 0.0 340.0 -1 &('()-)$*#+$ 23 -1 0 5 5 UIParent -2.0 -437.6 -1 ##$#%$&V'R(#)U+$,$-+.&/#"
    -- "2 50 0 0 0 7 7 UIParent -20.0 2.0 -1 ##$$%/&('%)$+$,$ 0 1 0 6 0 MainActionBar 0.0 4.0 -1 ##$$%/&('%(#,$ 0 2 0 0 0 UIParent 674.2 -952.1 -1 ##$$%/&('%(#,$ 0 3 0 7 7 UIParent -392.5 2.0 -1 #$$'%,&('&(#,# 0 4 0 7 7 UIParent -383.3 4.5 -1 ##$'%,&('&(#,# 0 5 0 7 7 UIParent 345.5 4.5 -1 ##$'%,&('&(#,# 0 6 0 0 0 UIParent 2037.4 -395.0 -1 #$$$%/&('%(&,# 0 7 0 8 2 DamageMeter 0.0 4.0 -1 #$$$%/&('%(#,# 0 10 0 1 1 UIParent -1.0 -978.0 -1 ##$$&('% 0 11 0 0 0 UIParent 521.4 -891.8 -1 ##$%&''%,# 0 12 0 0 0 UIParent 674.2 -918.1 -1 ##$$&('% 1 -1 0 1 1 UIParent -8.4 -891.4 -1 #'$#%$ 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -335.5 -181.0 -1 $#3& 3 1 0 4 4 UIParent 335.5 -184.4 -1 %$3& 3 2 0 8 8 UIParent -361.2 265.3 -1 %#&#3& 3 3 0 0 0 UIParent 1384.0 -305.8 -1 '$(#)#-k.?/#1$3#5%607-7$ 3 4 0 0 0 UIParent 2.0 -466.0 -1 ,#-3.1/#0$1#2(5%6+7U 3 5 0 2 2 UIParent -294.0 -307.0 -1 &#*$3# 3 6 0 2 2 UIParent -1576.5 -2.0 -1 -k.G/#4&5%6-6$7-7$ 3 7 0 1 1 UIParent -362.0 -867.6 -1 3# 4 -1 0 4 4 UIParent 0.0 -380.0 -1 # 5 -1 0 0 0 UIParent 1250.2 -827.6 -1 # 6 0 0 2 2 UIParent -277.4 -5.8 -1 ##$#%#&.(()( 6 1 0 5 3 MinimapCluster -4.4 -61.8 -1 ##$#%#'+(*)(-$ 6 2 0 1 4 UIParent -194.5 -2.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -696.8 -1.9 -1 # 8 -1 0 0 0 UIParent 52.7 -995.0 -1 #'$Q%$&Y 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 5 5 UIParent 0.0 -187.2 -1 # 12 -1 0 2 8 MinimapCluster 0.4 -4.4 -1 ##$#%# 13 -1 0 1 1 UIParent -429.8 -2.0 -1 ##$$%)&' 14 -1 1 2 2 MicroButtonAndBagsBar 0.0 0.0 -1 ##$#%( 15 0 0 1 1 UIParent 900.0 -278.0 -1 # 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 # 16 -1 0 0 2 ChatFrame1 29.0 60.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 8 UIParent -474.2 0.0 -1 #- 19 -1 0 1 1 UIParent 0.0 -962.0 -1 ## 20 0 0 7 7 UIParent 0.4 350.6 -1 ##$*%$&&'&(-($)#+$,$-$ 20 1 0 1 7 UIParent 0.0 306.6 -1 ##$/%$&(''(-($)#+$,$-$ 20 2 0 7 1 EssentialCooldownViewer -2.9 4.0 -1 ##$$%$&''&(-($)#+$,$-$ 20 3 0 7 7 UIParent -280.0 390.6 -1 #$$$%#&('((-($)#*#+$,$-$.U 21 -1 0 7 7 UIParent 0.0 332.0 -1 #$$# 22 0 0 1 1 UIParent 383.2 -97.4 -1 #$$$%$&.'&(#)-)$*$+$,$-#.#/U0% 22 1 0 7 7 UIParent 0.0 950.6 -1 &('()-)$*#+$ 22 2 0 4 4 UIParent 0.0 380.0 -1 &('()-)$*#+$ 22 3 0 4 4 UIParent 0.0 340.0 -1 &('()-)$*#+$ 23 -1 0 5 5 UIParent -2.0 -437.6 -1 ##$#%$&V'R(#)U+$,$-+.&/#"
    -- "2 50 0 0 0 7 7 UIParent -20.0 2.0 -1 ##$$%/&('%)$+$,$ 0 1 0 6 0 MainActionBar 0.0 4.0 -1 ##$$%/&('%(#,$ 0 2 0 0 0 UIParent 674.2 -952.1 -1 ##$$%/&('%(#,$ 0 3 0 7 7 UIParent -392.5 2.0 -1 #$$'%,&('&(#,# 0 4 0 7 7 UIParent -383.3 4.5 -1 ##$'%,&('&(#,# 0 5 0 7 7 UIParent 345.5 4.5 -1 ##$'%,&('&(#,# 0 6 0 0 0 UIParent 2037.4 -395.0 -1 #$$$%/&('%(&,# 0 7 0 8 2 DamageMeter 0.0 4.0 -1 #$$$%/&('%(#,# 0 10 0 1 1 UIParent -1.0 -978.0 -1 ##$$&('% 0 11 0 0 0 UIParent 521.4 -891.8 -1 ##$%&''%,# 0 12 0 0 0 UIParent 674.2 -918.1 -1 ##$$&('% 1 -1 0 1 1 UIParent -8.4 -891.4 -1 #'$#%$ 2 -1 1 2 2 UIParent 0.0 0.0 -1 ##$#%( 3 0 0 4 4 UIParent -335.5 -181.0 -1 $#3& 3 1 0 4 4 UIParent 335.5 -184.4 -1 %$3& 3 2 0 8 8 UIParent -361.2 265.3 -1 %#&#3& 3 3 0 0 0 UIParent 1384.0 -305.8 -1 '$(#)#-k.?/#1$3#5%607-7$ 3 4 0 0 0 UIParent 2.0 -466.0 -1 ,#-3.1/#0$1#2(5%6+7U 3 5 0 2 2 UIParent -294.0 -307.0 -1 &#*$3# 3 6 0 2 2 UIParent -1576.5 -2.0 -1 -k.G/#4&5%6-6$7-7$ 3 7 0 1 1 UIParent -362.0 -867.6 -1 3# 4 -1 0 4 4 UIParent 0.0 -380.0 -1 # 5 -1 0 0 0 UIParent 1250.2 -827.6 -1 # 6 0 0 2 2 UIParent -277.4 -5.8 -1 ##$#%#&.(()( 6 1 0 5 3 MinimapCluster -4.4 -61.8 -1 ##$#%#'+(*)(-$ 6 2 0 1 4 UIParent -194.5 -2.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 1 1 UIParent -696.8 -1.9 -1 # 8 -1 0 0 0 UIParent 52.7 -995.0 -1 #'$Q%$&Y 9 -1 1 7 7 UIParent 0.0 45.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 5 5 UIParent 0.0 -187.2 -1 # 12 -1 0 4 4 UIParent 843.2 80.0 -1 ##$#%# 13 -1 0 1 1 UIParent -429.8 -2.0 -1 ##$$%)&' 14 -1 1 2 2 MicroButtonAndBagsBar 0.0 0.0 -1 ##$#%( 15 0 0 1 1 UIParent 900.0 -278.0 -1 # 15 1 1 7 1 MainStatusTrackingBarContainer 0.0 0.0 -1 # 16 -1 0 0 2 ChatFrame1 29.0 60.0 -1 #( 17 -1 1 1 1 UIParent 0.0 -100.0 -1 ## 18 -1 0 8 8 UIParent -474.2 0.0 -1 #- 19 -1 0 1 1 UIParent 0.0 -962.0 -1 ## 20 0 0 7 7 UIParent 0.4 350.6 -1 ##$*%$&&'&(-($)#+$,$-$ 20 1 0 1 7 UIParent 0.0 306.6 -1 ##$/%$&(''(-($)#+$,$-$ 20 2 0 7 1 EssentialCooldownViewer -2.9 4.0 -1 ##$$%$&''&(-($)#+$,$-$ 20 3 0 7 7 UIParent -280.0 390.6 -1 #$$$%#&('((-($)#*#+$,$-$.U 21 -1 0 7 7 UIParent 0.0 332.0 -1 #$$# 22 0 0 1 1 UIParent 383.2 -97.4 -1 #$$$%$&.'&(#)-)$*$+$,$-#.#/U0% 22 1 0 7 7 UIParent 0.0 950.6 -1 &('()-)$*#+$ 22 2 0 4 4 UIParent 0.0 380.0 -1 &('()-)$*#+$ 22 3 0 4 4 UIParent 0.0 340.0 -1 &('()-)$*#+$ 23 -1 0 5 5 UIParent -2.0 -437.6 -1 ##$#%$&V'R(#)U+$,$-+.&/#"
local MAX_ACCOUNT_LAYOUTS = 5 -- 最大Account布局数量

-- 打印,支持多参数
function EM:Print(...) YUI:Print("|cFFFFFF00<编辑模式>|r ", ...) end

function EM:GetAllLayouts()
    -- if not EditModeManagerFrame then return nil end
    -- EditModeManagerFrame:UpdateDropdownOptions()
    -- local layouts = EditModeManagerFrame:GetLayouts()
    -- return layouts
    if not C_EditMode then return nil end
    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then return nil end
    return layouts.layouts
end

-- 检查布局限制状态
function EM:CheckLayoutLimit()
    local layouts = self:GetAllLayouts() or {}
    local accountLayoutCount = 0
    local hasYuiLayout = false
    local ACC_TYPE = Enum.EditModeLayoutType.Account
    
    for _, layout in ipairs(layouts) do
        if layout.layoutType == ACC_TYPE then
            accountLayoutCount = accountLayoutCount + 1
        end
        if self:IsYUILayout(layout.layoutName) then
            hasYuiLayout = true
        end
    end
    
    local isFull = (accountLayoutCount >= MAX_ACCOUNT_LAYOUTS)
    
    return accountLayoutCount, isFull, hasYuiLayout
end

-- 获取可用的布局名称和类型
function EM:GetLayoutInfo(name)
    local layouts = self:GetAllLayouts() or {}
    local exists = {}
    local accCount = 0
    local ACC_TYPE = Enum.EditModeLayoutType.Account
    local CHAR_TYPE = Enum.EditModeLayoutType.Character

    for _, layout in ipairs(layouts) do
        exists[layout.layoutName] = true
        if layout.layoutType == ACC_TYPE then accCount = accCount + 1 end
    end

    local layoutName = name
    local layoutType = accCount < MAX_ACCOUNT_LAYOUTS and ACC_TYPE or CHAR_TYPE -- 优先使用Account布局

    if exists[name] then
        local i = 1
        while exists[name .. "_" .. i] do i = i + 1 end
        layoutName = name .. "_" .. i
    end

    return layoutType, layoutName
end

-- 查找所有匹配的布局
function EM:FindExistingLayouts(name, matchSuffix)
    local layouts = self:GetAllLayouts() or {}
    local found = {}

    for index, layout in ipairs(layouts) do
        local isMatch = false
        if self:IsYUILayout(layout.layoutName) then
            isMatch = true
        end

        if isMatch then
            table.insert(found, {index = index, layout = layout.layoutName})
        end
    end

    return found
end

-- 删除已存在的布局
function EM:DeleteLayout(name, matchSuffix)
    if not C_EditMode or not name then return end
    
    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then return end
    
    local removed = false
    for i = #layouts.layouts, 1, -1 do
        local lName = layouts.layouts[i].layoutName
        local isMatch = false
        
        -- 如果是要删除 YUI 布局，删除所有历史版本
        if name == LAYOUT_NAME or self:IsYUILayout(name) then
            if self:IsYUILayout(lName) then
                isMatch = true
            end
        else
            if lName == name then
                isMatch = true
            elseif matchSuffix and lName:match("^" .. name .. "_?%d*$") then
                isMatch = true
            end
        end
        
        if isMatch then
            table.remove(layouts.layouts, i)
            removed = true
        end
    end
    
    if removed then
        C_EditMode.SaveLayouts(layouts)
    end
end

function EM:DeleteDefaultLayout() self:DeleteLayout(LAYOUT_NAME, true) end

-- 删除一个非 YUI 的 Account 布局
function EM:DeleteNonYUILayout()
    if not C_EditMode then return false end
    
    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then return false end
    
    local ACC_TYPE = Enum.EditModeLayoutType.Account
    
    -- 记录当前的活动布局名称
    local currentActiveName = nil
    if layouts.activeLayout then
        currentActiveName = self:GetCurrentLayoutName()
    end

    for i = #layouts.layouts, 1, -1 do
        local layout = layouts.layouts[i]
        if layout.layoutType == ACC_TYPE and not self:IsYUILayout(layout.layoutName) then
            local name = layout.layoutName
            table.remove(layouts.layouts, i)
            C_EditMode.SaveLayouts(layouts)
            
            -- 处理删除后的激活逻辑
            if currentActiveName and currentActiveName ~= name then
                -- 1. 如果删除的不是当前配置，则删除后再一次激活当前配置
                self:SwitchLayoutByName(currentActiveName)
            else
                -- 删除的是当前配置
                local newLayouts = C_EditMode.GetLayouts()
                if newLayouts and newLayouts.layouts and #newLayouts.layouts > 0 then
                    -- 3. 如果删除后还有配置，则自动激活第一个可用配置
                    C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + 1)
                else
                    -- 2. 如果删除后没有配置了，则自动激活第一个 Preset 的配置 (通常索引为 1)
                    C_EditMode.SetActiveLayout(1)
                end
            end
            
            self:Print("已自动删除旧布局: " .. name)
            return true
        end
    end

    self:Print("未找到可删除的非 YUI 布局")
    return false
end

-- 导出当前活动布局为字符串
function EM:ExportLayout()
    if not EditModeManagerFrame then return nil end
    local activeLayoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
    return C_EditMode.ConvertLayoutInfoToString(activeLayoutInfo)
end

-- 导入布局字符串
function EM:ImportLayout(layoutString, layoutName, matchSuffix)
    if not layoutString or not layoutName or not C_EditMode then return false end

    if matchSuffix == nil then matchSuffix = true end

    EM:DeleteLayout(layoutName, matchSuffix)

    local importLayoutInfo = C_EditMode.ConvertStringToLayoutInfo(layoutString)

    if not importLayoutInfo then return false end

    local layoutType, _layoutName = self:GetLayoutInfo(layoutName)

    if layoutType == nil then return false end
    
    importLayoutInfo.layoutName = _layoutName
    importLayoutInfo.layoutType = layoutType

    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then return false end
    
    table.insert(layouts.layouts, importLayoutInfo)
    C_EditMode.SaveLayouts(layouts)
    
    -- 激活新布局
    local newLayouts = C_EditMode.GetLayouts()
    for i, v in ipairs(newLayouts.layouts) do
        if v.layoutName == _layoutName then
            C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + i)
            break
        end
    end

    return true
end

-- 导入默认布局字符串 (从 YUI.Data 获取)
function EM:ImportDefaultLayout()
    if not YUI.Data then return false end
    
    local layoutString = YUI.Data:GetData("EditMode")
    if not layoutString then return false end
    
    local version = YUI.Data:GetVersion("EditMode")
    if version == 0 then version = 1 end
    
    -- 构造带版本的名称，例如 "YUI v1"
    local layoutName = LAYOUT_NAME .. " v" .. version
    
    -- 删除旧的 YUI 布局 (所有版本)
    self:DeleteLayout(LAYOUT_NAME)
    
    return EM:ImportLayout(layoutString, layoutName, false)
end

-- 获取当前激活的编辑模式布局名称
function EM:GetCurrentLayoutName()
    if not C_EditMode then return nil end
    local layouts = self:GetAllLayouts()
    if not layouts then return nil end
    local activeIndex = (C_EditMode.GetLayouts() or {}).activeLayout
    if not activeIndex then return nil end
    local realIndex = activeIndex - Enum.EditModePresetLayoutsMeta.NumValues
    if realIndex <= 0 or realIndex > #layouts then return nil end
    return layouts[realIndex].layoutName
end

-- 切换到最新版本的 YUI 布局
function EM:SwitchToLatestLayout()
    if not C_EditMode then return false end

    local layouts = self:GetAllLayouts() or {}
    if not layouts then return false end
    
    local bestIndex = nil
    local bestVer = -1
    
    for index, layout in ipairs(layouts) do
        if self:IsYUILayout(layout.layoutName) then
             local ver = self:GetCurrentLayoutVersion(layout.layoutName)
             if ver > bestVer then
                 bestVer = ver
                 bestIndex = index
             end
        end
    end
    
    if bestIndex then
        C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + bestIndex)
        local layoutName = layouts[bestIndex].layoutName
        self:Print("已切换到布局: |cFFFF00FF" .. layoutName .. "|r")
        return true
    end

    self:Print("未找到 YUI 布局")
    return false
end

-- 根据布局名称切换编辑模式配置
function EM:SwitchLayoutByName(targetName)
    if targetName == LAYOUT_NAME then
        return self:SwitchToLatestLayout()
    end

    if not C_EditMode then return end
    local layouts = self:GetAllLayouts() or {}
    if not layouts then return false end

    for index, layout in ipairs(layouts) do
        if layout.layoutName == targetName then
            C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + index)
            -- self:Print("已切换到布局: |cFFFF00FF" .. targetName .. "|r")
            return true
        end
    end

    self:Print("未找到名为 |cFFFF00FF" .. targetName .. "|r 的布局")
    return false
end

-- 显示切换提示框
function EM:ShowSwitchPrompt()
    if _G["YUI_SwitchLayoutPrompt"] then
        _G["YUI_SwitchLayoutPrompt"]:Show()
        return
    end

    -- 创建提示框
    local frame = CreateFrame("Frame", "YUI_SwitchLayoutPrompt", UIParent,
                              "BackdropTemplate")
    frame:SetFrameStrata("DIALOG") -- 提高层级
    frame:SetPoint("CENTER")
    frame:SetSize(450, 180)

    local isElvUILoaded = C_AddOns.IsAddOnLoaded("ElvUI")
    if isElvUILoaded and _G.ElvUI then
        if frame.SetTemplate then frame:SetTemplate("Transparent") end
    else
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
        frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9) -- 加深背景
    end

    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetPoint("CENTER", 0, 20)
    text:SetWidth(380)
    text:SetJustifyH("CENTER")
    text:SetText(string.format(
                     "检测到您已导入 %s 布局，但当前未启用。\n\n是否切换到 %s 布局？",
                     LAYOUT_COLORED_NAME, LAYOUT_COLORED_NAME))

    -- 取消按钮 (左边，灰色)
    local btnNo = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    btnNo:SetPoint("BOTTOMLEFT", 20, 20)
    btnNo:SetSize(80, 25)
    btnNo:SetText("取消")
    btnNo:SetScript("OnClick", function() frame:Hide() end)

    -- 不再提示 (取消按钮右边)
    local check =
        CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetPoint("LEFT", btnNo, "RIGHT", 10, 0)
    check.text:SetText("不再提示")
    check:SetScript("OnClick", function(self)
        local global = GetGlobalDB()
        if global then
            global.ignoreYUISwitchPrompt = self:GetChecked()
        end
    end)

    -- 切换按钮 (最右边)
    local btnYes = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnYes:SetPoint("BOTTOMRIGHT", -20, 20)
    btnYes:SetSize(80, 25)
    btnYes:SetText("切换")
    btnYes:SetScript("OnClick", function()
        EM:SwitchToLatestLayout()
        frame:Hide()
    end)

    if isElvUILoaded and ElvUI then
        local E, L, V, P, G = unpack(ElvUI)
        local S = E:GetModule('Skins')
        if S then
            S:HandleButton(btnNo)
            S:HandleButton(btnYes)
            S:HandleCheckBox(check)
        end
    end

    frame:Show()
end

-- 检查并提示切换到 YUI 布局
function EM:CheckAndPromptSwitchToYUI()
    if not C_EditMode then return end

    -- 检查是否已勾选不再提示 (账户级别)
    local global = GetGlobalDB()
    if global and global.ignoreYUISwitchPrompt then return end

    -- 检查当前角色是否已通过安装器安装，如果未安装，则不弹出切换提示
    local isInstalled = YUI.Installer and YUI.Installer.IsInstalled and YUI.Installer:IsInstalled()
    if not isInstalled then
        return
    end

    local currName = self:GetCurrentLayoutName()
    
    -- 如果当前已经是 YUI 布局 (任意版本)，则不提示
    if self:IsYUILayout(currName) then return end

    local layouts = self:GetAllLayouts() or {}

    for _, layout in ipairs(layouts) do
        if self:IsYUILayout(layout.layoutName) then
            EM:ShowSwitchPrompt()
            return
        end
    end
end
