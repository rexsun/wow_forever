-------------------------------------------------------------------------------
-- Spanish localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "Desactivado: Conflicto con %s";


l.SUBTITLE      = "Asistencia de marcos de banda";
l.DESC          = "Mejora los marcos de banda.\n\n"
.." - Resalta el fondo de los jugadores con poca vida\n\n"
.." - Las barras invertidas usar\195\161n tu elecci\195\179n de colores\n\n"
.." - Transparencia de unidades fuera de rango\n\n"
.." - Banda siempre visible\n\n"
.."\n"
.."Mejora los beneficios / perjuicios (tama\195\177o, m\195\161ximo mostrado, ...)\n\n"
.."Colorea los nombres en la barra de informaci\195\179n, con iconos JcJ |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."Muestra los iconos de objetivo (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) en los marcos de banda\n\n"
l.OPTIONS_TITLE = format("%s - Opciones", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s iniciado", l.VERS_TITLE);
l.MSG_SDB            = "Men\195\186 de Opciones de Kallye";

l.INIT_FAILED = format("%s no se carg\195\179 correctamente!", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Grupo / Banda";
l.OPTION_HIGHLIGHTLOWHP = "Resaltar poca vida (colores din\195\161micos)"..required;
l.OPTION_REVERTBAR = "Barras de "..l.YL.."vida invertidas|r (cuanta menos vida, m\195\161s grande es la barra!) ";
l.OPTION_HEALTH_LOW = "\194\161Casi muerto!";
l.OPTION_HEALTH_LOW_TOOLTIP = "El color se aplicar\195\161 "..l.YLL.."POR DEBAJO|r de este l\195\173mite\n\n"
    .."ej: Rojo por debajo del 25%";
l.OPTION_HEALTH_WARN = "Atenci\195\179n";
l.OPTION_HEALTH_WARN_TOOLTIP = "El color se aplicar\195\161 "..l.YLL.."EN|r este l\195\173mite\n\n"
    .."ej: Amarillo al 50%";
l.OPTION_HEALTH_OK = "Buena salud";
l.OPTION_HEALTH_OK_TOOLTIP = "El color se aplicar\195\161 "..l.YLL.."POR ENCIMA|r de este l\195\173mite\n\n"
    .."ej: Verde despu\195\169s del 75%";
l.OPTION_HEALTH_ALPHA = l.WH.."Transparencia"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Transparencia de la barra de vida (con el color de clase)\n"..l.CY.."Por defecto en Wow: 100%"
l.OPTION_MOVEROLEICONS = "Icono de rol arriba a la izquierda";
l.OPTION_HIDEDAMAGEICONS = "Ocultar el icono de rol 'da\195\177o'";
l.OPTION_HIDEREALM = "Ocultar el reino de los jugadores";
l.OPTION_HIDEREALM_TOOLTIP = "Los nombres de los reinos se ocultar\195\161n, as\195\173 "..l.YLL.."Illidan - Varimathras|r se convertir\195\161 en "..l.YLL.."Illidan (*)|r";
l.OPTION_ICONONDEATH = "A\195\177adir "..l.RT8.." a los nombres de los muertos";
l.OPTION_FRIENDSCLASSCOLOR = "Nombres coloreados por clase";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Nombres de los jugadores coloreados por clase (marcos de grupo/banda)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s: %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "Textura"
l.OPTION_BAR_TEXTURE_TOOLTIP = "Textura de la barra de vida"
l.OPTION_SOLORAID = l.CY.."Mostrar marcos de banda en modo solo "..required;
l.OPTION_SOLORAID_TOOLTIP = "Marcos de grupo/banda siempre visibles,\nactivar\195\161 "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "\194\161Probar marcos de banda!";
l.OPTION_DEBUG_ON_MESSAGE = "Prueba de marcos de banda activada, \194\161haz clic de nuevo para detener!";
l.OPTION_DEBUG_OFF = "\194\161DETENER LA PRUEBA!";
l.OPTION_DEBUG_OFF_MESSAGE = "Prueba detenida, puedes reanudar la actividad normal";

l.OPTION_ACTIVATE_MODULE = "Activar / Desactivar m\195\179dulo"
l.OPTION_HIDEDISABLED = l.GYL.."Ocultar m\195\179dulos desactivados"

-- KF START
l.OPTION_INRANGE = "Transparencia cuando está en rango";
l.OPTION_INRANGE_TOOLTIP = l.CY.."Por defecto en Wow: 100%";
l.OPTION_NOTINRANGE = "Transparencia si est\195\161 fuera de rango";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."Por defecto en Wow: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "Transparencia de la banda fuera de combate";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."Por defecto en Wow: 100%";
l.OPTION_ALPHADISPELOVERLAY = "Transparencia del Overlay de disipaci\195\179n"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."Los beneficios/perjuicios de Blizzard ser\195\161n reemplazados por RaidFrameAuras" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Perjuicios / Beneficios"
l.OPTION_ORIENTATION_LeftThenUp = "A la izquierda, luego arriba"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."A la izquierda, luego arriba (por defecto)"
l.OPTION_ORIENTATION_UpThenLeft = "Arriba, luego a la izquierda"
l.OPTION_ORIENTATION_RightThenUp = "A la derecha, luego arriba"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."A la derecha, luego arriba (por defecto)"
l.OPTION_ORIENTATION_UpThenRight = "Arriba, luego a la derecha"
l.OPTION_BUFFSSCALE = "Tama\195\177o de beneficios "..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."Por defecto en Wow: 1"
l.OPTION_MAXBUFFS = "L\195\173mite de beneficios"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "N\195\186mero m\195\161ximo de beneficios a mostrar\n"..l.CY.."Por defecto en Wow: "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4beneficio:beneficios";
l.OPTION_BUFFSPERLINE = "Beneficios por l\195\177nea"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "N\195\186mero de beneficios por l\195\177nea\n"..l.CY.."Ignorado si es superior al L\195\173mite";
l.OPTION_BUFFSPERLINE_FORMAT = "%d por l\195\177nea";
l.OPTION_BUFFSORIENTATION = "Orientaci\195\179n de beneficios"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "Elige la disposici\195\179n de los beneficios (soporta m\195\186ltiples l\195\177neas)\n"..l.CY.."Por defecto: "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "Posici\195\179n horizontal"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Ajusta la posici\195\179n horizontal relativa de los beneficios";
l.OPTION_BUFFS_RELATIVE_Y = "Posici\195\179n vertical"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Ajusta la posici\195\179n vertical relativa de los beneficios";
l.OPTION_DEBUFFSSCALE = "Tama\195\177o de perjuicios "..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."Por defecto en Wow: 1"
l.OPTION_MAXDEBUFFS = "L\195\173mite de perjuicios"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "N\195\186mero m\195\161ximo de perjuicios a mostrar\n"..l.CY.."Por defecto en Wow: "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4perjuicio:perjuicios";
l.OPTION_DEBUFFSPERLINE = "Perjuicios por l\195\177nea"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "N\195\186mero de iconos de perjuicio por l\195\177nea\n"..l.CY.."Ignorado si es superior al L\195\173mite";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d por l\195\177nea";
l.OPTION_DEBUFFSORIENTATION = "Orientaci\195\179n de perjuicios"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "Elige la disposici\195\179n de los perjuicios (soporta m\195\186ltiples l\195\177neas)\n"..l.CY.."Por defecto: "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "Posici\195\179n horizontal"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Ajusta la posici\195\179n horizontal relativa de los perjuicios";
l.OPTION_DEBUFFS_RELATIVE_Y = "Posici\195\179n vertical"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Ajusta la posici\195\179n vertical relativa de los perjuicios";
l.OPTION_USETAINTMETHOD = l.CY.."Visualizaci\195\179n cl\195\161sica del L\195\173mite de beneficios / perjuicios"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "Desmarcado, usa la visualizaci\195\179n experimental\nMarcado, usa la visualizaci\195\179n estable, pero con un "..l.RDL.."error por sesi\195\179n|r, no tan grave..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Cambiar el L\195\173mite provoca un "..l.RDL.."error por sesi\195\179n|r, no tan grave..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." El reposicionamiento puede verse afectado unos segundos al morir un jefe"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Ocultar auras de Blizzard"
l.OPTION_BUFFS_RESET = "Cancelar todo reposicionamiento"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Auto — sigue el combate (predeterminado)";
l.OPTION_FILTER_RAID = "Siempre la lista fuera de combate";
l.OPTION_FILTER_RAID_IN_COMBAT = "Siempre la lista en combate";
l.OPTION_BUFFS_SPACING_X = "Espaciado horizontal";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Separaci\195\179n horizontal, en p\195\173xeles, entre iconos de beneficios\n"..l.CY.."Predeterminado: 0";
l.OPTION_BUFFS_SPACING_Y = "Espaciado vertical";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Separaci\195\179n vertical, en p\195\173xeles, entre iconos de beneficios\n"..l.CY.."Predeterminado: 1";
l.OPTION_BUFFSFILTER = "Filtro de beneficios";
l.OPTION_BUFFSFILTER_TOOLTIP = "Qu\195\169 lista de beneficios entrega Blizzard\n"..l.CY.."Auto cambia al entrar y salir de combate";
l.OPTION_BUFFS_HIDETOOLTIP = "Ocultar descripciones de beneficios"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Sin descripci\195\179n al pasar el cursor sobre un icono de beneficio\n"..l.RDL.."Tambi\195\169n desactiva el clic derecho para cancelar un beneficio";
l.OPTION_DEBUFFS_SPACING_X = "Espaciado horizontal";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Separaci\195\179n horizontal, en p\195\173xeles, entre iconos de perjuicios\n"..l.CY.."Predeterminado: 0";
l.OPTION_DEBUFFS_SPACING_Y = "Espaciado vertical";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Separaci\195\179n vertical, en p\195\173xeles, entre iconos de perjuicios\n"..l.CY.."Predeterminado: 1";
l.OPTION_DEBUFFSFILTER = "Filtro de perjuicios";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Qu\195\169 lista de perjuicios entrega Blizzard\n"..l.CY.."Auto cambia al entrar y salir de combate";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Ocultar descripciones de perjuicios"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Sin descripci\195\179n al pasar el cursor sobre un icono de perjuicio\n"..l.RDL.."Tambi\195\169n desactiva el clic derecho para cancelar un perjuicio";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Barras de informaci\195\179n";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Por defecto";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "Colores de clase";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "Tu elecci\195\179n de color: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Sin icono";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "Icono de facci\195\179n |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "Color si es inferior";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "Selecciona el color del nivel si es inferior al tuyo";
l.OPTION_NAMEPLATES_COLOR_OVER = "Color si es superior";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "Selecciona el color del nivel si es superior al tuyo";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Nunca";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Nunca muestra el nivel en las barras de informaci\195\179n.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Si es diferente al tuyo";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Si es diferente al tuyo, coloreado";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Siempre";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Siempre, coloreado";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Nombres aliados";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Color del nombre en las barras de informaci\195\179n aliadas (fuera de instancias)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Barras aliadas";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Color de las barras de informaci\195\179n aliadas (fuera de instancias)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Textura Barras aliadas"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textura de las barras de informaci\195\179n aliadas (fuera de instancias)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "Iconos JcJ aliados";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Muestra los iconos JcJ en los nombres aliados.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "Niveles aliados";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Muestra el nivel en las barras de informaci\195\179n aliadas.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Nombres enemigos";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Color del nombre en las barras de informaci\195\179n enemigas (fuera de instancias)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Barras enemigas";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Color de las barras de informaci\195\179n enemigas (fuera de instancias)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Textura Barras enemigas"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textura de las barras de informaci\195\179n enemigas (fuera de instancias)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "Iconos JcJ enemigos";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Muestra los iconos JcJ en los nombres enemigos.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "Niveles enemigos";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Muestra el nivel en las barras de informaci\195\179n enemigas.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."Muestra los iconos de objetivo (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) en los marcos de banda"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "Iconos de banda";
l.OPTION_RAIDICONS_ANCHOR = "Alineaci\195\179n de los iconos";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Posici\195\179n del icono de objetivo en el marco de banda";
l.OPTION_CENTER = "Centro"
l.OPTION_TOPLEFT = "Arriba Izquierda";
l.OPTION_TOPRIGHT = "Arriba Derecha";
l.OPTION_BOTTOMLEFT = "Abajo Izquierda";
l.OPTION_BOTTOMRIGHT = "Abajo Derecha";
l.OPTION_RAIDICONS_SIZE = "Tama\195\177o de los iconos";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Ajusta el tama\195\177o de los iconos de banda";
l.OPTION_RAIDICONS_RELATIVE_X = "Posici\195\179n horizontal";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Ajusta la posici\195\179n horizontal relativa de los iconos de banda";
l.OPTION_RAIDICONS_RELATIVE_Y = "Posici\195\179n vertical";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Ajusta la posici\195\179n vertical relativa de los iconos de banda";
-- KRI END

l.OPTION_RESET_OPTIONS = "Restablecer perfil";
l.OPTION_RELOAD_REQUIRED = "Algunos cambios requieren una recarga (escribe: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Opciones que requieren una recarga";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Mostrar mensajes";
l.OPTION_SHOWMSGWARNING = l.GYL.."Mostrar alertas";
l.OPTION_SHOWMSGERR = l.GYL.."Mostrar errores";
l.OPTION_COMPARTMENT_FILTER = "Mostrar en el Filtro de Compartimentos";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "En la lista de addons en la parte superior derecha";
l.OPTION_WHATSNEW = "Novedades";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Recuerda activar la opci\195\179n "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Mostrar marcos de grupo cuando est\195\169s solo "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Mostrar tambi\195\169n los marcos de grupo en banda"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Mostrar tanto los marcos de grupo como los de banda (en banda)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s la opci\195\179n %s|r de los %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Nota: Escribe "..l.YL.."/reload|r despu\195\169s del "..HUD_EDIT_MODE_MENU..", para evitar cualquier error";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Activa el "..l.YL..HUD_EDIT_MODE_MENU.."|r, y muestra directamente las opciones de "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "Prueba de marcos de banda activada (se puede probar en "..HUD_EDIT_MODE_MENU..")\n"
                    .."\194\161Haz clic de nuevo para detener!";
end
