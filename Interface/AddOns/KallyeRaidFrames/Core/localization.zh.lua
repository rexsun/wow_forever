-------------------------------------------------------------------------------
-- Chinese localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "已禁用：与 %s 冲突";


l.SUBTITLE      = "团队框架助手";
l.DESC          = "改进团队框架。\n\n"
.." - 突出显示生命值不足的玩家背景\n\n"
.." - 反转的生命条将使用您选择的颜色\n\n"
.." - 范围外单位透明化\n\n"
.." - 团队框架始终可见\n\n"
.."\n"
.."改进增益/减益效果 (大小, 最大显示数量, ...)\n\n"
.."信息条上的名称着色，带有PvP图标 |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."在团队框架上显示目标图标 (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...)\n\n"
l.OPTIONS_TITLE = format("%s - 选项", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s 已加载", l.VERS_TITLE);
l.MSG_SDB            = "Kallye 选项菜单";

l.INIT_FAILED = format("%s 未正确加载！", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "队伍 / 团队";
l.OPTION_HIGHLIGHTLOWHP = "突出显示低生命值 (动态颜色)"..required;
l.OPTION_REVERTBAR = "反转"..l.YL.."生命条|r (生命值越低，生命条越长！) ";
l.OPTION_HEALTH_LOW = "濒死！";
l.OPTION_HEALTH_LOW_TOOLTIP = "颜色将应用在"..l.YLL.."低于|r此限制时\n\n"
    .."例如：低于25%时为红色";
l.OPTION_HEALTH_WARN = "警告";
l.OPTION_HEALTH_WARN_TOOLTIP = "颜色将应用在"..l.YLL.."达到|r此限制时\n\n"
    .."例如：达到50%时为黄色";
l.OPTION_HEALTH_OK = "健康";
l.OPTION_HEALTH_OK_TOOLTIP = "颜色将应用在"..l.YLL.."高于|r此限制时\n\n"
    .."例如：高于75%时为绿色";
l.OPTION_HEALTH_ALPHA = l.WH.."透明度"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "生命条透明度 (使用职业颜色)\n"..l.CY.."魔兽世界默认：100%"
l.OPTION_MOVEROLEICONS = "角色图标移至左上角";
l.OPTION_HIDEDAMAGEICONS = "隐藏'伤害'角色图标";
l.OPTION_HIDEREALM = "隐藏玩家服务器名称";
l.OPTION_HIDEREALM_TOOLTIP = "服务器名称将被隐藏，例如"..l.YLL.."伊利丹 - 瓦里玛萨斯|r 将变为 "..l.YLL.."伊利丹 (*)|r";
l.OPTION_ICONONDEATH = "在死亡玩家名称上添加"..l.RT8;
l.OPTION_FRIENDSCLASSCOLOR = "按职业颜色显示名称";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "玩家名称按职业颜色显示 (队伍/团队框架)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s : %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "材质"
l.OPTION_BAR_TEXTURE_TOOLTIP = "生命条材质"
l.OPTION_SOLORAID = l.CY.."在单人模式下显示团队框架"..required;
l.OPTION_SOLORAID_TOOLTIP = "队伍/团队框架始终可见，\n将激活"..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! 测试团队框架 !";
l.OPTION_DEBUG_ON_MESSAGE = "团队框架测试已激活，再次点击停止！";
l.OPTION_DEBUG_OFF = "! 停止测试 !";
l.OPTION_DEBUG_OFF_MESSAGE = "测试已停止，您可以恢复正常活动";

l.OPTION_ACTIVATE_MODULE = "启用 / 禁用模块"
l.OPTION_HIDEDISABLED = l.GYL.."隐藏已禁用模块"

-- KF START
l.OPTION_INRANGE = "范围内透明度";
l.OPTION_INRANGE_TOOLTIP = l.CY.."魔兽世界默认：100%";
l.OPTION_NOTINRANGE = "范围外透明化";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."魔兽世界默认："..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "脱战时团队透明化";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."魔兽世界默认：100%";
l.OPTION_ALPHADISPELOVERLAY = "驱散覆盖层透明度"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."暴雪增益/减益效果将被 RaidFrameAuras 取代" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "减益 / 增益"
l.OPTION_ORIENTATION_LeftThenUp = "左侧，然后向上"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."左侧，然后向上 (默认)"
l.OPTION_ORIENTATION_UpThenLeft = "向上，然后向左"
l.OPTION_ORIENTATION_RightThenUp = "右侧，然后向上"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."右侧，然后向上 (默认)"
l.OPTION_ORIENTATION_UpThenRight = "向上，然后向右"
l.OPTION_BUFFSSCALE = "增益图标大小"..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."魔兽世界默认：1"
l.OPTION_MAXBUFFS = "增益上限"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "最大显示增益数量\n"..l.CY.."魔兽世界默认："..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4增益:增益";
l.OPTION_BUFFSPERLINE = "每行增益数量"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "每行增益图标数量\n"..l.CY.."如果超过上限则忽略";
l.OPTION_BUFFSPERLINE_FORMAT = "%d 每行";
l.OPTION_BUFFSORIENTATION = "增益方向"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "选择增益排列方式 (支持多行)\n"..l.CY.."默认："..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "水平位置"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "调整增益的相对水平位置";
l.OPTION_BUFFS_RELATIVE_Y = "垂直位置"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "调整增益的相对垂直位置";
l.OPTION_DEBUFFSSCALE = "减益图标大小"..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."魔兽世界默认：1"
l.OPTION_MAXDEBUFFS = "减益上限"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "最大显示减益数量\n"..l.CY.."魔兽世界默认："..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4减益:减益";
l.OPTION_DEBUFFSPERLINE = "每行减益数量"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "每行减益图标数量\n"..l.CY.."如果超过上限则忽略";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d 每行";
l.OPTION_DEBUFFSORIENTATION = "减益方向"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "选择减益排列方式 (支持多行)\n"..l.CY.."默认："..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "水平位置"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "调整减益的相对水平位置";
l.OPTION_DEBUFFS_RELATIVE_Y = "垂直位置"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "调整减益的相对垂直位置";
l.OPTION_USETAINTMETHOD = l.CY.."经典增益/减益上限显示"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "未勾选时，使用实验性显示\n勾选时，使用稳定显示，但每会话会产生一个"..l.RDL.."错误|r，问题不大..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." 更改上限会导致每会话产生一个"..l.RDL.."错误|r，问题不大..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." 在首领死亡时，重新定位可能会受到几秒钟的影响"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " 隐藏暴雪光环"
l.OPTION_BUFFS_RESET = "取消所有重新定位"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."自动 — 跟随战斗状态（默认）";
l.OPTION_FILTER_RAID = "始终使用非战斗列表";
l.OPTION_FILTER_RAID_IN_COMBAT = "始终使用战斗列表";
l.OPTION_BUFFS_SPACING_X = "水平间距";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "增益图标之间的水平间距（像素）\n"..l.CY.."默认：0";
l.OPTION_BUFFS_SPACING_Y = "垂直间距";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "增益图标之间的垂直间距（像素）\n"..l.CY.."默认：1";
l.OPTION_BUFFSFILTER = "增益过滤";
l.OPTION_BUFFSFILTER_TOOLTIP = "选择暴雪提供的增益列表\n"..l.CY.."自动会在进入和脱离战斗时切换";
l.OPTION_BUFFS_HIDETOOLTIP = "隐藏增益提示"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "鼠标悬停增益图标时不显示提示\n"..l.RDL.."同时禁用右键取消增益";
l.OPTION_DEBUFFS_SPACING_X = "水平间距";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "减益图标之间的水平间距（像素）\n"..l.CY.."默认：0";
l.OPTION_DEBUFFS_SPACING_Y = "垂直间距";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "减益图标之间的垂直间距（像素）\n"..l.CY.."默认：1";
l.OPTION_DEBUFFSFILTER = "减益过滤";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "选择暴雪提供的减益列表\n"..l.CY.."自动会在进入和脱离战斗时切换";
l.OPTION_DEBUFFS_HIDETOOLTIP = "隐藏减益提示"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "鼠标悬停减益图标时不显示提示\n"..l.RDL.."同时禁用右键取消减益";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "信息条";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."默认";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "职业颜色";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "您的自定义颜色：";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."无图标";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "阵营图标 |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "低于时颜色";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "选择当等级低于您时显示的颜色";
l.OPTION_NAMEPLATES_COLOR_OVER = "高于时颜色";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "选择当等级高于您时显示的颜色";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."从不";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "从不在信息条上显示等级。";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "如果与您不同";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "如果与您不同，则着色";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "总是";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "总是，并着色";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "友方名称";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "友方信息条上的名称颜色 (副本外)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "友方血条";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "友方信息条的颜色 (副本外)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "友方血条材质"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "友方信息条的材质 (副本外)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "友方PvP图标";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "在友方名称上显示PvP图标。";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "友方等级";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "在友方信息条上显示等级。";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "敌方名称";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "敌方信息条上的名称颜色 (副本外)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "敌方血条";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "敌方信息条的颜色 (副本外)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "敌方血条材质"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "敌方信息条的材质 (副本外)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "敌方PvP图标";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "在敌方名称上显示PvP图标。";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "敌方等级";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "在敌方信息条上显示等级。";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."在团队框架上显示目标图标 (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...)"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "团队图标";
l.OPTION_RAIDICONS_ANCHOR = "图标对齐";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "目标图标在团队框架中的位置";
l.OPTION_CENTER = "居中"
l.OPTION_TOPLEFT = "左上";
l.OPTION_TOPRIGHT = "右上";
l.OPTION_BOTTOMLEFT = "左下";
l.OPTION_BOTTOMRIGHT = "右下";
l.OPTION_RAIDICONS_SIZE = "图标大小";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "调整团队图标的大小";
l.OPTION_RAIDICONS_RELATIVE_X = "水平位置";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "调整团队图标的相对水平位置";
l.OPTION_RAIDICONS_RELATIVE_Y = "垂直位置";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "调整团队图标的相对垂直位置";
-- KRI END

l.OPTION_RESET_OPTIONS = "重置配置";
l.OPTION_RELOAD_REQUIRED = "某些更改需要重新加载 (输入："..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": 需要重新加载的选项";

l.OPTION_SHOWMSGNORMAL = l.GYL.."显示消息";
l.OPTION_SHOWMSGWARNING = l.GYL.."显示警告";
l.OPTION_SHOWMSGERR = l.GYL.."显示错误";
l.OPTION_COMPARTMENT_FILTER = "在隔间过滤器中显示";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "在右上角的插件列表中";
l.OPTION_WHATSNEW = "新功能";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "请考虑启用选项"..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."单人时显示队伍框架 "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "在团队中也显示队伍框架"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "在团队中同时显示队伍和团队框架"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s 选项 %s|r 的 %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "注意：在"..l.YL..HUD_EDIT_MODE_MENU.."|r 后输入 "..l.YL.."/reload|r，以避免任何错误";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "激活"..l.YL..HUD_EDIT_MODE_MENU.."|r，并直接显示"..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r 的选项。\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "团队框架测试已激活 (可在"..HUD_EDIT_MODE_MENU.."中测试)\n"
                    .."再次点击停止！";
end