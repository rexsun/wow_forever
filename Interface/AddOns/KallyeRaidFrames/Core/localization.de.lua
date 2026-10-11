-------------------------------------------------------------------------------
-- German localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "Deaktiviert: Konflikt mit %s";


l.SUBTITLE      = "Raidrahmen-Unterst\195\188tzung";
l.DESC          = "Verbessert Raidrahmen.\n\n"
.." - Hebt den Hintergrund von Spielern mit wenig Leben hervor\n\n"
.." - Umgekehrte Balken verwenden Ihre Farbauswahl\n\n"
.." - Transparenz von Einheiten au\195\159erhalb der Reichweite\n\n"
.." - Raid immer sichtbar\n\n"
.."\n"
.."Verbessert Buffs / Debuffs (Gr\195\182\195\159e, max. angezeigt, ...)\n\n"
.."F\195\164rbt Namen in Infobalken, mit PvP-Symbolen |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."Zeigt Zielsymbole (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) auf Raidrahmen an\n\n"
l.OPTIONS_TITLE = format("%s - Optionen", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s geladen", l.VERS_TITLE);
l.MSG_SDB            = "Kallye Optionsmen\195\188";

l.INIT_FAILED = format("%s nicht korrekt geladen!", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Gruppe / Schlachtzug";
l.OPTION_HIGHLIGHTLOWHP = "Hervorheben bei niedrigem Leben (dynamische Farben)"..required;
l.OPTION_REVERTBAR = "Umgekehrte "..l.YL.."Lebensbalken|r (je weniger Leben, desto gr\195\182\195\159er der Balken!) ";
l.OPTION_HEALTH_LOW = "Fast tot!";
l.OPTION_HEALTH_LOW_TOOLTIP = "Die Farbe wird "..l.YLL.."UNTER|r diesem Limit angewendet\n\n"
    .."Bsp: Rot unter 25%";
l.OPTION_HEALTH_WARN = "Warnung";
l.OPTION_HEALTH_WARN_TOOLTIP = "Die Farbe wird "..l.YLL.."BEI|r diesem Limit angewendet\n\n"
    .."Bsp: Gelb bei 50%";
l.OPTION_HEALTH_OK = "Gute Gesundheit";
l.OPTION_HEALTH_OK_TOOLTIP = "Die Farbe wird "..l.YLL.."ÜBER|r diesem Limit angewendet\n\n"
    .."Bsp: Gr\195\188n nach 75%";
l.OPTION_HEALTH_ALPHA = l.WH.."Transparenz"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Transparenz des Lebensbalkens (mit Klassenfarbe)\n"..l.CY.."Standard in Wow: 100%"
l.OPTION_MOVEROLEICONS = "Rollen-Symbol oben links";
l.OPTION_HIDEDAMAGEICONS = "Rollen-Symbol 'Schaden' ausblenden";
l.OPTION_HIDEREALM = "Spielerreich ausblenden";
l.OPTION_HIDEREALM_TOOLTIP = "Reichsnamen werden ausgeblendet, so wird "..l.YLL.."Illidan - Varimathras|r zu "..l.YLL.."Illidan (*)|r";
l.OPTION_ICONONDEATH = "F\195\188ge "..l.RT8.." zu den Namen der Toten hinzu";
l.OPTION_FRIENDSCLASSCOLOR = "Namen nach Klasse einf\195\164rben";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Spielernamen nach Klasse einf\195\164rben (Gruppen-/Raidrahmen)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s: %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "Textur"
l.OPTION_BAR_TEXTURE_TOOLTIP = "Textur des Lebensbalkens"
l.OPTION_SOLORAID = l.CY.."Zeigt Raidrahmen im Solomodus an "..required;
l.OPTION_SOLORAID_TOOLTIP = "Gruppen-/Raidrahmen immer sichtbar,\naktiviert "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;
--

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! Raidrahmen testen !";
l.OPTION_DEBUG_ON_MESSAGE = "Raidrahmen-Test aktiviert, erneut klicken zum Stoppen!";
l.OPTION_DEBUG_OFF = "! TEST STOPPEN !";
l.OPTION_DEBUG_OFF_MESSAGE = "Test gestoppt, Sie k\195\182nnen normale Aktivit\195\164ten wieder aufnehmen";

l.OPTION_ACTIVATE_MODULE = "Modul aktivieren / deaktivieren"
l.OPTION_HIDEDISABLED = l.GYL.."Deaktivierte Module ausblenden"

-- KF START
l.OPTION_INRANGE = "Transparenz bei Reichweite";
l.OPTION_INRANGE_TOOLTIP = l.CY.."Standard in Wow: 100%";
l.OPTION_NOTINRANGE = "Transparenz bei Au\195\159er-Reichweite";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."Standard in Wow: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "Raid-Transparenz au\195\159erhalb des Kampfes";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."Standard in Wow: 100%";
l.OPTION_ALPHADISPELOVERLAY = "Transparenz des Dispel-Overlays"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."Blizzard-Buffs/Debuffs werden durch RaidFrameAuras ersetzt" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Debuffs / Buffs"
l.OPTION_ORIENTATION_LeftThenUp = "Links, dann nach oben"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."Links, dann nach oben (Standard)"
l.OPTION_ORIENTATION_UpThenLeft = "Oben, dann nach links"
l.OPTION_ORIENTATION_RightThenUp = "Rechts, dann nach oben"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."Rechts, dann nach oben (Standard)"
l.OPTION_ORIENTATION_UpThenRight = "Oben, dann nach rechts"
l.OPTION_BUFFSSCALE = "Buff-Gr\195\182\195\159e "..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."Standard in Wow: 1"
l.OPTION_MAXBUFFS = "Buff-Limit"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "Maximale Anzahl der anzuzeigenden Buffs\n"..l.CY.."Standard in Wow: "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4Buff:Buffs";
l.OPTION_BUFFSPERLINE = "Buffs pro Reihe"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "Anzahl der Buffs pro Reihe\n"..l.CY.."Ignoriert, wenn \195\188ber dem Limit";
l.OPTION_BUFFSPERLINE_FORMAT = "%d pro Reihe";
l.OPTION_BUFFSORIENTATION = "Buff-Ausrichtung"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "W\195\164hlen Sie die Anordnung der Buffs (unterst\195\188tzt Mehrzeilen)\n"..l.CY.."Standard: "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "Horizontale Position"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Passen Sie die relative horizontale Position der Buffs an";
l.OPTION_BUFFS_RELATIVE_Y = "Vertikale Position"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Passen Sie die relative vertikale Position der Buffs an";
l.OPTION_DEBUFFSSCALE = "Debuff-Gr\195\182\195\159e "..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."Standard in Wow: 1"
l.OPTION_MAXDEBUFFS = "Debuff-Limit"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "Maximale Anzahl der anzuzeigenden Debuffs\n"..l.CY.."Standard in Wow: "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4Debuff:Debuffs";
l.OPTION_DEBUFFSPERLINE = "Debuffs pro Reihe"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "Anzahl der Debuff-Symbole pro Reihe\n"..l.CY.."Ignoriert, wenn \195\188ber dem Limit";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d pro Reihe";
l.OPTION_DEBUFFSORIENTATION = "Debuff-Ausrichtung"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "W\195\164hlen Sie die Anordnung der Debuffs (unterst\195\188tzt Mehrzeilen)\n"..l.CY.."Standard: "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "Horizontale Position"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Passen Sie die relative horizontale Position der Debuffs an";
l.OPTION_DEBUFFS_RELATIVE_Y = "Vertikale Position"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Passen Sie die relative vertikale Position der Debuffs an";
l.OPTION_USETAINTMETHOD = l.CY.."Klassische Anzeige des Buff-/Debuff-Limits"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "Deaktiviert, verwendet die experimentelle Anzeige\nAktiviert, verwendet die stabile Anzeige, aber mit einem "..l.RDL.."Fehler pro Sitzung|r, nicht so schlimm..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Das \195\164ndern des Limits verursacht einen "..l.RDL.."Fehler pro Sitzung|r, nicht so schlimm..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." Die Neupositionierung kann f\195\188r einige Sekunden nach dem Tod eines Bosses beeintr\195\164chtigt sein"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Blizzard-Auren ausblenden"
l.OPTION_BUFFS_RESET = "Alle Neupositionierungen r\195\188ckg\195\164ngig machen"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Auto — folgt dem Kampf (Standard)";
l.OPTION_FILTER_RAID = "Immer die Liste au\195\159erhalb des Kampfes";
l.OPTION_FILTER_RAID_IN_COMBAT = "Immer die Kampfliste";
l.OPTION_BUFFS_SPACING_X = "Horizontaler Abstand";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Horizontaler Abstand in Pixeln zwischen Buff-Symbolen\n"..l.CY.."Standard: 0";
l.OPTION_BUFFS_SPACING_Y = "Vertikaler Abstand";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Vertikaler Abstand in Pixeln zwischen Buff-Symbolen\n"..l.CY.."Standard: 1";
l.OPTION_BUFFSFILTER = "Buff-Filter";
l.OPTION_BUFFSFILTER_TOOLTIP = "Welche Buff-Liste Blizzard liefert\n"..l.CY.."Auto wechselt beim Betreten und Verlassen des Kampfes";
l.OPTION_BUFFS_HIDETOOLTIP = "Buff-Tooltips ausblenden"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Kein Tooltip beim \195\156berfahren eines Buff-Symbols\n"..l.RDL.."Deaktiviert auch den Rechtsklick zum Abbrechen eines Buffs";
l.OPTION_DEBUFFS_SPACING_X = "Horizontaler Abstand";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Horizontaler Abstand in Pixeln zwischen Debuff-Symbolen\n"..l.CY.."Standard: 0";
l.OPTION_DEBUFFS_SPACING_Y = "Vertikaler Abstand";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Vertikaler Abstand in Pixeln zwischen Debuff-Symbolen\n"..l.CY.."Standard: 1";
l.OPTION_DEBUFFSFILTER = "Debuff-Filter";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Welche Debuff-Liste Blizzard liefert\n"..l.CY.."Auto wechselt beim Betreten und Verlassen des Kampfes";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Debuff-Tooltips ausblenden"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Kein Tooltip beim \195\156berfahren eines Debuff-Symbols\n"..l.RDL.."Deaktiviert auch den Rechtsklick zum Abbrechen eines Debuffs";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Infobalken";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Standard";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "Klassenfarben";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "Ihre Farbauswahl: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Kein Symbol";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "Fraktionssymbol |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "Farbe, wenn niedriger";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "W\195\164hlen Sie die Farbe des Levels, wenn es niedriger ist als Ihres";
l.OPTION_NAMEPLATES_COLOR_OVER = "Farbe, wenn h\195\182her";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "W\195\164hlen Sie die Farbe des Levels, wenn es h\195\182her ist als Ihres";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Nie";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Zeigt niemals das Level auf Infobalken an.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Wenn anders als Ihres";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Wenn anders als Ihres, farbig";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Immer";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Immer, farbig";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Verb\195\188ndete Namen";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Farbe des Namens auf verb\195\188ndeten Infobalken (au\195\159erhalb von Instanzen)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Verb\195\188ndete Balken";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Farbe der verb\195\188ndeten Infobalken (au\195\159erhalb von Instanzen)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Textur verb\195\188ndeter Balken"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textur der verb\195\188ndeten Infobalken (au\195\159erhalb von Instanzen)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "Verb\195\188ndete PvP-Symbole";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Zeigt PvP-Symbole auf verb\195\188ndeten Namen an.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "Verb\195\188ndete Level";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Zeigt das Level auf verb\195\188ndeten Infobalken an.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Feindliche Namen";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Farbe des Namens auf feindlichen Infobalken (au\195\159erhalb von Instanzen)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Feindliche Balken";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Farbe der feindlichen Infobalken (au\195\159erhalb von Instanzen)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Textur feindlicher Balken"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Textur der feindlichen Infobalken (au\195\159erhalb von Instanzen)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "Feindliche PvP-Symbole";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Zeigt PvP-Symbole auf feindlichen Namen an.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "Feindliche Level";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Zeigt das Level auf feindlichen Infobalken an.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."Zeigt Zielsymbole (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) auf Raidrahmen an"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "Raid-Symbole";
l.OPTION_RAIDICONS_ANCHOR = "Symbolausrichtung";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Position des Zielsymbols im Raidrahmen";
l.OPTION_CENTER = "Mitte"
l.OPTION_TOPLEFT = "Oben Links";
l.OPTION_TOPRIGHT = "Oben Rechts";
l.OPTION_BOTTOMLEFT = "Unten Links";
l.OPTION_BOTTOMRIGHT = "Unten Rechts";
l.OPTION_RAIDICONS_SIZE = "Symbolgr\195\182\195\159e";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Passen Sie die Gr\195\182\195\159e der Raid-Symbole an";
l.OPTION_RAIDICONS_RELATIVE_X = "Horizontale Position";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Passen Sie die relative horizontale Position der Raid-Symbole an";
l.OPTION_RAIDICONS_RELATIVE_Y = "Vertikale Position";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Passen Sie die relative vertikale Position der Raid-Symbole an";
-- KRI END

l.OPTION_RESET_OPTIONS = "Profil zur\195\188cksetzen";
l.OPTION_RELOAD_REQUIRED = "Einige \195\164nderungen erfordern einen Neuladen (tippen Sie: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Optionen, die einen Neuladen erfordern";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Nachrichten anzeigen";
l.OPTION_SHOWMSGWARNING = l.GYL.."Warnungen anzeigen";
l.OPTION_SHOWMSGERR = l.GYL.."Fehler anzeigen";
l.OPTION_COMPARTMENT_FILTER = "Im Fachfilter anzeigen";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "In der Addon-Liste oben rechts";
l.OPTION_WHATSNEW = "Neuigkeiten";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Denken Sie daran, die Option "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..") zu aktivieren";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Gruppenrahmen anzeigen, wenn allein "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Gruppenrahmen auch im Schlachtzug anzeigen"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Zeige sowohl Gruppen- als auch Schlachtzugsrahmen (im Schlachtzug)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s die Option %s|r der %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Hinweis: Geben Sie "..l.YL.."/reload|r nach dem "..HUD_EDIT_MODE_MENU.." ein, um Fehler zu vermeiden";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Aktiviert den "..l.YL..HUD_EDIT_MODE_MENU.."|r und zeigt direkt die Optionen f\195\188r "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r an.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "Raidrahmen-Test aktiviert (testbar im "..HUD_EDIT_MODE_MENU..")\n"
                    .."Erneut klicken zum Stoppen!";
end