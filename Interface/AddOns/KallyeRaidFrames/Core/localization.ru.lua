-------------------------------------------------------------------------------
-- Russian localization ZamestoTV
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "Отключено: Конфликт с %s";

l.SUBTITLE      = "Цель рейдовых значков";
l.DESC          = "Улучшает рейдовые рамки.\n\n"
.." - Выделяет фон игроков с низким уровнем здоровья\n\n"
.." - Инвертированные полосы будут использовать выбранные вами цвета\n\n"
.." - Прозрачность юнитов вне зоны действия\n\n"
.." - Рейд всегда виден\n\n"
.."\n"
.."Улучшает баффы / дебаффы (размер, макс. отображаемых, ...)\n\n"
.."Раскрашивает имена в информационных полосах, с PvP-иконками |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n" -- ChatGPT
.."Показывает значки целей (|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:0|t...) на рейдовых рамках\n\n"
l.OPTIONS_TITLE = format("%s - Параметры", l.VERS_TITLE);

l.MSG_LOADED         = format("%s загружен и активен", l.VERS_TITLE);

l.INIT_FAILED = format("%s неправильно инициализирован (конфликт?)!", l.VERS_TITLE);


local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Группа / Рейд"; -- ChatGPT
l.OPTION_HIGHLIGHTLOWHP = "Выделять игроков с низким уровнем здоровья (динамические цвета)"..required; -- ChatGPT
l.OPTION_REVERTBAR = "Инвертированные "..l.YL.."полосы здоровья|r (чем меньше здоровья, тем больше полоса!)"; -- ChatGPT
l.OPTION_HEALTH_LOW = "Почти мертв!"; -- ChatGPT
l.OPTION_HEALTH_LOW_TOOLTIP = "Цвет будет применен "..l.YLL.."НИЖЕ|r этого предела\n\n"
    .."Например: Красный ниже 25%"; -- ChatGPT
l.OPTION_HEALTH_WARN = "Внимание"; -- ChatGPT
l.OPTION_HEALTH_WARN_TOOLTIP = "Цвет будет применен "..l.YLL.."НА|r этом пределе\n\n"
    .."Например: Желтый на 50%"; -- ChatGPT
l.OPTION_HEALTH_OK = "Хорошее здоровье"; -- ChatGPT
l.OPTION_HEALTH_OK_TOOLTIP = "Цвет будет применен "..l.YLL.."ВЫШЕ|r этого предела\n\n"
    .."Например: Зеленый после 75%"; -- ChatGPT
l.OPTION_HEALTH_ALPHA = l.WH.."Прозрачность"..required; -- ChatGPT
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Прозрачность полосы здоровья (с цветом класса)\n"..l.CY.."По умолчанию в WoW: 100%"; -- ChatGPT
l.OPTION_MOVEROLEICONS = "Иконка роли вверху слева"; -- ChatGPT
l.OPTION_HIDEDAMAGEICONS = "Скрыть иконку роли 'урон'"; -- ChatGPT
l.OPTION_HIDEREALM = "Скрыть название игрового мира"; -- ChatGPT
l.OPTION_HIDEREALM_TOOLTIP = "Названия игровых миров будут скрыты, так "..l.YLL.."Иллидан - Вариматрас|r станет "..l.YLL.."Иллидан (*)|r"; -- ChatGPT
l.OPTION_ICONONDEATH = "Добавить "..l.RT8.." к именам мертвых"; -- ChatGPT
l.OPTION_FRIENDSCLASSCOLOR = "Имена, окрашенные по классу"; -- ChatGPT
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Имена игроков, окрашенные по классу (рамки группы/рейда)"; -- ChatGPT
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS) -- ChatGPT
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s: %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS) -- ChatGPT
l.OPTION_BAR_TEXTURE = "Текстура" -- ChatGPT
l.OPTION_BAR_TEXTURE_TOOLTIP = "Текстура полосы здоровья" -- ChatGPT
l.OPTION_SOLORAID = l.CY.."Показывать рейдовые рамки в соло-режиме "..required; -- ChatGPT
l.OPTION_SOLORAID_TOOLTIP = "Рамки группы/рейда всегда видны,\nактивирует "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES; -- ChatGPT

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES) -- ChatGPT
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! Тестировать рейдовые рамки!"; -- ChatGPT
l.OPTION_DEBUG_ON_MESSAGE = "Тест рейдовых рамок активирован, нажмите еще раз, чтобы остановить!"; -- ChatGPT
l.OPTION_DEBUG_OFF = "! ОСТАНОВИТЬ ТЕСТ!"; -- ChatGPT
l.OPTION_DEBUG_OFF_MESSAGE = "Тест остановлен, вы можете вернуться к обычной деятельности"; -- ChatGPT

l.OPTION_ACTIVATE_MODULE = "Активировать / Деактивировать модуль" -- ChatGPT
l.OPTION_HIDEDISABLED = l.GYL.."Скрыть отключенные модули" -- ChatGPT

-- KF START
l.OPTION_INRANGE = "Прозрачность, если в зоне действия";
l.OPTION_INRANGE_TOOLTIP = l.CY.."По умолчанию в WoW: 100%"; -- ChatGPT
l.OPTION_NOTINRANGE = "Прозрачность, если вне зоны действия"; -- ChatGPT
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."По умолчанию в WoW: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%"; -- ChatGPT
l.OPTION_NOTINCOMBAT = "Прозрачность рейда вне боя"; -- ChatGPT
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."По умолчанию в WoW: 100%"; -- ChatGPT
l.OPTION_ALPHADISPELOVERLAY = "Прозрачность наложения рассеивания" -- ChatGPT
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."Баффы и дебаффы Blizzard будут заменены RaidFrameAuras" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Дебаффы / Баффы";
l.OPTION_ORIENTATION_LeftThenUp = "Влево, затем вверх"; -- ChatGPT
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."Влево, затем вверх (по умолчанию)"; -- ChatGPT
l.OPTION_ORIENTATION_UpThenLeft = "Вверх, затем влево"; -- ChatGPT
l.OPTION_ORIENTATION_RightThenUp = "Вправо, затем вверх"; -- ChatGPT
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."Вправо, затем вверх (по умолчанию)"; -- ChatGPT
l.OPTION_ORIENTATION_UpThenRight = "Вверх, затем вправо"; -- ChatGPT
l.OPTION_BUFFSSCALE = "Относительный размер баффов"..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."По умолчанию в WoW: 1"
l.OPTION_MAXBUFFS = "Максимум баффов"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "Максимальное количество отображаемых баффов\n"..l.CY.."По умолчанию в WoW: "..ns.DEFAULT_MAXBUFFS
l.OPTION_MAXBUFFS_FORMAT = "%d |4бафф:баффа:баффов";
l.OPTION_BUFFSPERLINE = "Баффов в строке";
l.OPTION_BUFFSPERLINE_TOOLTIP = "Количество иконок баффов в строке\n"..l.CY.."По умолчанию в WoW: максимум"
l.OPTION_BUFFSPERLINE_FORMAT = "%d в строке"..required;
l.OPTION_BUFFSORIENTATION = "Ориентация баффов"..required; -- ChatGPT
l.OPTION_BUFFSORIENTATION_TOOLTIP = "Выберите расположение баффов (поддерживает несколько строк)\n"..l.CY.."По умолчанию: "..l.OPTION_ORIENTATION_LeftThenUp; -- ChatGPT
l.OPTION_BUFFS_RELATIVE_X = "Горизонтальное положение"..required; -- ChatGPT
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Отрегулируйте относительное горизонтальное положение баффов"; -- ChatGPT
l.OPTION_BUFFS_RELATIVE_Y = "Вертикальное положение"..required; -- ChatGPT
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Отрегулируйте относительное вертикальное положение баффов"; -- ChatGPT
l.OPTION_DEBUFFSSCALE = "Относительный размер дебаффов"..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."По умолчанию в WoW: 1"
l.OPTION_MAXDEBUFFS = "Максимум дебаффов"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "Максимальное количество отображаемых дебаффов\n"..l.CY.."По умолчанию в WoW: "..ns.DEFAULT_MAXDEBUFFS
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4дебафф:дебаффа:дебаффов";
l.OPTION_DEBUFFSPERLINE = "Дебаффов в строке"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "Количество иконок дебаффов в строке\n"..l.CY.."По умолчанию в WoW: максимум"
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d в строке";
l.OPTION_DEBUFFSORIENTATION = "Ориентация дебаффов"..required; -- ChatGPT
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "Выберите расположение дебаффов (поддерживает несколько строк)\n"..l.CY.."По умолчанию: "..l.OPTION_ORIENTATION_RightThenUp; -- ChatGPT
l.OPTION_DEBUFFS_RELATIVE_X = "Горизонтальное положение"..required; -- ChatGPT
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Отрегулируйте относительное горизонтальное положение дебаффов"; -- ChatGPT
l.OPTION_DEBUFFS_RELATIVE_Y = "Вертикальное положение"..required; -- ChatGPT
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Отрегулируйте относительное вертикальное положение дебаффов"; -- ChatGPT
l.OPTION_USETAINTMETHOD = l.CY.."Устаревший метод отображения для максимума баффов/дебаффов"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "Если не отмечено, используется экспериментальный метод отображения\nЕсли отмечено, используется стабильный метод, но с одной "..l.RDL.."ошибкой за сессию|r, не критично..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Изменение максимума баффов/дебаффов вызывает одну "..l.RDL.."ошибку за сессию|r, не критично..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." Перепозиционирование может быть затронуто в течение нескольких секунд после убийства босса"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Скрыть ауры Blizzard"
l.OPTION_BUFFS_RESET = "Отменить все изменения положения"; -- ChatGPT
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Авто — следует за боем (по умолчанию)";
l.OPTION_FILTER_RAID = "Всегда список вне боя";
l.OPTION_FILTER_RAID_IN_COMBAT = "Всегда боевой список";
l.OPTION_BUFFS_SPACING_X = "Горизонтальный отступ";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Горизонтальный зазор в пикселях между значками усилений\n"..l.CY.."По умолчанию: 0";
l.OPTION_BUFFS_SPACING_Y = "Вертикальный отступ";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Вертикальный зазор в пикселях между значками усилений\n"..l.CY.."По умолчанию: 1";
l.OPTION_BUFFSFILTER = "Фильтр усилений";
l.OPTION_BUFFSFILTER_TOOLTIP = "Какой список усилений предоставляет Blizzard\n"..l.CY.."Авто переключается при входе в бой и выходе из него";
l.OPTION_BUFFS_HIDETOOLTIP = "Скрыть подсказки усилений"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Подсказка не появляется при наведении на значок усиления\n"..l.RDL.."Также отключает отмену усиления правой кнопкой мыши";
l.OPTION_DEBUFFS_SPACING_X = "Горизонтальный отступ";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Горизонтальный зазор в пикселях между значками ослаблений\n"..l.CY.."По умолчанию: 0";
l.OPTION_DEBUFFS_SPACING_Y = "Вертикальный отступ";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Вертикальный зазор в пикселях между значками ослаблений\n"..l.CY.."По умолчанию: 1";
l.OPTION_DEBUFFSFILTER = "Фильтр ослаблений";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Какой список ослаблений предоставляет Blizzard\n"..l.CY.."Авто переключается при входе в бой и выходе из него";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Скрыть подсказки ослаблений"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Подсказка не появляется при наведении на значок ослабления\n"..l.RDL.."Также отключает отмену ослабления правой кнопкой мыши";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Таблички с именами";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Цвета Blizzard по умолчанию";
l.OPTION_NAMEPLATES_USECOLOR_CLASS ="Использовать цвет класса";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM ="Ваш выбор цвета: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Без иконки";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "Иконка фракции |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t"
l.OPTION_NAMEPLATES_COLOR_UNDER = "Цвет, если ниже";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "Выберите цвет уровня, если он ниже вашего";
l.OPTION_NAMEPLATES_COLOR_OVER = "Цвет, если выше";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "Выберите цвет уровня, если он выше вашего";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Никогда";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Никогда не показывать уровень на информационных полосах.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Если отличается от вашего";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Если отличается от вашего, с цветом";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Всегда";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Всегда, с цветом";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Имена союзников";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Цвет текста имени над табличками союзников (вне подземелий)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Полосы союзников";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Цвет табличек союзников (вне подземелий)";
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Текстура полос союзников" -- ChatGPT
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Текстура информационных полос союзников (вне подземелий)" -- ChatGPT
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "PvP-иконки союзников";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Отображает PvP-иконки на именах союзников.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "Уровень союзников";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Отображает уровень на информационных полосах союзников.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Имена врагов";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Цвет текста имени над табличками врагов (вне подземелий)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Полосы врагов";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Цвет табличек врагов (вне подземелий)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Текстура полос врагов" -- ChatGPT
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Текстура информационных полос врагов (вне подземелий)" -- ChatGPT
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "PvP-иконки врагов";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Отображает PvP-иконки на именах врагов.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "Уровень врагов";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Отображает уровень на информационных полосах врагов.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE

-- KRI START
l.OPTION_RAIDICONS_HEADER = "Значки рейдов |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t";
l.OPTION_RAIDICONS_ANCHOR = "Выравнивание значков";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Положение значка цели в рамке рейда";
l.OPTION_CENTER = "Центр"
l.OPTION_TOPLEFT = "Вверху слева";
l.OPTION_TOPRIGHT = "Вверху справа";
l.OPTION_BOTTOMLEFT = "Внизу слева";
l.OPTION_BOTTOMRIGHT = "Внизу справа";
l.OPTION_RAIDICONS_SIZE = "Размер значка рейда";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Отрегулируйте размер значков рейда";
l.OPTION_RAIDICONS_RELATIVE_X = "Горизонтальное положение";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Отрегулируйте относительное горизонтальное положение значков рейда.";
l.OPTION_RAIDICONS_RELATIVE_Y = "Вертикальное положение";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Отрегулируйте относительное вертикальное положение значков рейда.";
-- KRI END

l.OPTION_RESET_OPTIONS = "Сбросить настройки";
l.OPTION_RELOAD_REQUIRED = "Некоторые изменения требуют перезагрузки (введите: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Настройки, требующие перезагрузки";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Отображать сообщения";
l.OPTION_SHOWMSGWARNING = l.GYL.."Отображать предупреждения";
l.OPTION_SHOWMSGERR = l.GYL.."Отображать ошибки";
l.OPTION_COMPARTMENT_FILTER = "Показывать в фильтре отсеков"; -- ChatGPT
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "В списке дополнений в правом верхнем углу"; -- ChatGPT
l.OPTION_WHATSNEW = "Что нового";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Подумайте об активации опции "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")"; -- ChatGPT
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Отображать рамки группы в одиночку "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Показывать также рамки группы в рейде"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Показывать как рамки группы, так и рейда (в рейде)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s опцию %s|r из %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU); -- ChatGPT
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL; -- ChatGPT
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Примечание: Введите "..l.YL.."/reload|r после "..HUD_EDIT_MODE_MENU..", чтобы избежать ошибок"; -- ChatGPT
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Активирует "..l.YL..HUD_EDIT_MODE_MENU.."|r и напрямую отображает опции "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r"; -- ChatGPT
    l.OPTION_DEBUG_ON_MESSAGE = "Тест рейдовых рамок активирован (можно тестировать в "..HUD_EDIT_MODE_MENU..")\n"
                    .."Нажмите еще раз, чтобы остановить!"; -- ChatGPT
end
