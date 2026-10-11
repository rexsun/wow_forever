-------------------------------------------------------------------------------
-- Italian localization (ChatGPT)
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "Disattivato: Conflitto con %s";


l.SUBTITLE      = "Assistenza cornici raid";
l.DESC          = "Migliora le cornici del raid.\n\n"
.." - Evidenzia lo sfondo dei giocatori con poca vita\n\n"
.." - Le barre invertite useranno la tua scelta di colori\n\n"
.." - Trasparenza delle unit\195\160 fuori portata\n\n"
.." - Raid sempre visibile\n\n"
.."\n"
.."Migliora i buff / debuff (dimensione, max visualizzati, ...)\n\n"
.."Colora i nomi nelle barre informative, con icone PvP |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."Mostra le icone del bersaglio (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) sulle cornici del raid\n\n"
l.OPTIONS_TITLE = format("%s - Opzioni", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s caricato", l.VERS_TITLE);
l.MSG_SDB            = "Kallye menu Opzioni";

l.INIT_FAILED = format("%s non caricato correttamente!", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Gruppo / Raid";
l.OPTION_HIGHLIGHTLOWHP = "Evidenziare la poca vita (colori dinamici)"..required;
l.OPTION_REVERTBAR = "Barre di "..l.YL.."vita invertite|r (meno vita si ha, pi\195\185 la barra cresce!) ";
l.OPTION_HEALTH_LOW = "Quasi morto!";
l.OPTION_HEALTH_LOW_TOOLTIP = "Il colore sar\195\160 applicato "..l.YLL.."SOTTO|r questo limite\n\n"
    .."ex : Rosso sotto il 25%";
l.OPTION_HEALTH_WARN = "Attenzione";
l.OPTION_HEALTH_WARN_TOOLTIP = "Il colore sar\195\160 applicato "..l.YLL.."A|r questa limite\n\n"
    .."ex : Giallo al 50%";
l.OPTION_HEALTH_OK = "Buona salute";
l.OPTION_HEALTH_OK_TOOLTIP = "Il colore sar\195\160 applicato "..l.YLL.."SOPRA|r questa limite\n\n"
    .."ex : Verde dopo il 75%";
l.OPTION_HEALTH_ALPHA = l.WH.."Trasparenza"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Trasparenza della barra della vita (con il colore della classe)\n"..l.CY.."Per impostazione predefinita in Wow: 100%"
l.OPTION_MOVEROLEICONS = "Icona del ruolo in alto a sinistra";
l.OPTION_HIDEDAMAGEICONS = "Nascondi l'icona del ruolo 'danni'";
l.OPTION_HIDEREALM = "Nascondi il reame dei giocatori";
l.OPTION_HIDEREALM_TOOLTIP = "I nomi dei reami saranno nascosti, cos\195\174 "..l.YLL.."Illidan - Varimathras|r diventer\195\160 "..l.YLL.."Illidan (*)|r";
l.OPTION_ICONONDEATH = "Aggiungi "..l.RT8.." ai nomi dei morti";
l.OPTION_FRIENDSCLASSCOLOR = "Nomi colorati per classe";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Nomi dei giocatori colorati per classe (cornici gruppo/raid)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard: %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s : %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "Texture"
l.OPTION_BAR_TEXTURE_TOOLTIP = "Texture della barra della vita"
l.OPTION_SOLORAID = l.CY.."Mostra le cornici del raid in modalit\195\160 solo "..required;
l.OPTION_SOLORAID_TOOLTIP = "Cornici gruppo/raid sempre visibili,\nattiver\195\160 "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;

l.OPTION_EDITMODE_PARTY = format("Blizzard: %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! Testa le cornici del raid !";
l.OPTION_DEBUG_ON_MESSAGE = "Test delle cornici del raid attivato, clicca di nuovo per fermare!";
l.OPTION_DEBUG_OFF = "! FERMA IL TEST !";
l.OPTION_DEBUG_OFF_MESSAGE = "Test fermato, puoi riprendere l'attivit\195\160 normale";

l.OPTION_ACTIVATE_MODULE = "Attiva / Disattiva il modulo"
l.OPTION_HIDEDISABLED = l.GYL.."Nascondi i moduli disattivati"

-- KF START
l.OPTION_INRANGE = "Trasparenza quando in portata";
l.OPTION_INRANGE_TOOLTIP = l.CY.."Per impostazione predefinita in Wow: 100%";
l.OPTION_NOTINRANGE = "Trasparenza se fuori portata";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."Per impostazione predefinita in Wow: "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "Trasparenza del raid fuori combattimento";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."Per impostazione predefinita in Wow: 100%";
l.OPTION_ALPHADISPELOVERLAY = "Trasparenza indicatore dissoluzione"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE .. "\n"
  .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."I buff/debuff di Blizzard saranno sostituiti da RaidFrameAuras" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Debuff / Buff"
l.OPTION_ORIENTATION_LeftThenUp = "A Sinistra, poi in Alto"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."A Sinistra, poi in Alto (predefinito)"
l.OPTION_ORIENTATION_UpThenLeft = "In Alto, poi a Sinistra"
l.OPTION_ORIENTATION_RightThenUp = "A Destra, poi in Alto"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."A Destra, poi in Alto (predefinito)"
l.OPTION_ORIENTATION_UpThenRight = "In Alto, poi a Destra"
l.OPTION_BUFFSSCALE = "Dimensione dei buff "..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."Per impostazione predefinita in Wow: 1"
l.OPTION_MAXBUFFS = "Limite di buff"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "Numero massimo di buff da visualizzare\n"..l.CY.."Per impostazione predefinita in Wow: "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4buff:buffs";
l.OPTION_BUFFSPERLINE = "Buff per riga"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "Numero di buff per riga\n"..l.CY.."Ignorato se superiore al Limite";
l.OPTION_BUFFSPERLINE_FORMAT = "%d per riga";
l.OPTION_BUFFSORIENTATION = "Orientamento dei buff"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "Scegli l'organizzazione dei buff (supporta il multilinea)\n"..l.CY.."Per impostazione predefinita: "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "Posizione orizzontale"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Regola la posizione orizzontale relativa dei buff";
l.OPTION_BUFFS_RELATIVE_Y = "Posizione verticale"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Regola la posizione verticale relativa dei buff";
l.OPTION_DEBUFFSSCALE = "Dimensione dei debuff "..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."Per impostazione predefinita in Wow: 1"
l.OPTION_MAXDEBUFFS = "Limite di debuff"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "Numero massimo di debuff da visualizzare\n"..l.CY.."Per impostazione predefinita in Wow: "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4debuff:debuffs";
l.OPTION_DEBUFFSPERLINE = "Debuff per riga"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "Numero di icone di debuff per riga\n"..l.CY.."Ignorato se superiore al Limite";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d per riga";
l.OPTION_DEBUFFSORIENTATION = "Orientamento dei debuff"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "Scegli l'organizzazione dei debuff (supporta il multilinea)\n"..l.CY.."Per impostazione predefinita: "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "Posizione orizzontale"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Regola la posizione orizzontale relativa dei debuff";
l.OPTION_DEBUFFS_RELATIVE_Y = "Posizione verticale"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Regola la posizione verticale relativa dei debuff";
l.OPTION_USETAINTMETHOD = l.CY.."Visualizzazione classica del Limite di buff / debuff"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "Deselezionato, usa la visualizzazione sperimentale\nSelezionato, usa la visualizzazione stabile, ma con un "..l.RDL.."errore per sessione|r, non cos\195\174 grave..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Cambiare il Limite provoca un "..l.RDL.."errore per sessione|r, non cos\195\174 grave..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." Il riposizionamento pu\195\170 essere influenzato per alcuni secondi alla morte di un boss"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Nascondere le aure Blizzard"
l.OPTION_BUFFS_RESET = "Annulla tutto il riposizionamento"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Auto — segue il combattimento (predefinito)";
l.OPTION_FILTER_RAID = "Sempre l'elenco fuori combattimento";
l.OPTION_FILTER_RAID_IN_COMBAT = "Sempre l'elenco in combattimento";
l.OPTION_BUFFS_SPACING_X = "Spaziatura orizzontale";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Distanza orizzontale, in pixel, tra le icone dei benefici\n"..l.CY.."Predefinito: 0";
l.OPTION_BUFFS_SPACING_Y = "Spaziatura verticale";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Distanza verticale, in pixel, tra le icone dei benefici\n"..l.CY.."Predefinito: 1";
l.OPTION_BUFFSFILTER = "Filtro dei benefici";
l.OPTION_BUFFSFILTER_TOOLTIP = "Quale elenco di benefici fornisce Blizzard\n"..l.CY.."Auto cambia quando entri ed esci dal combattimento";
l.OPTION_BUFFS_HIDETOOLTIP = "Nascondi i suggerimenti dei benefici"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Nessun suggerimento passando sopra un'icona di beneficio\n"..l.RDL.."Disattiva anche il clic destro per annullare un beneficio";
l.OPTION_DEBUFFS_SPACING_X = "Spaziatura orizzontale";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Distanza orizzontale, in pixel, tra le icone dei malefici\n"..l.CY.."Predefinito: 0";
l.OPTION_DEBUFFS_SPACING_Y = "Spaziatura verticale";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Distanza verticale, in pixel, tra le icone dei malefici\n"..l.CY.."Predefinito: 1";
l.OPTION_DEBUFFSFILTER = "Filtro dei malefici";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Quale elenco di malefici fornisce Blizzard\n"..l.CY.."Auto cambia quando entri ed esci dal combattimento";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Nascondi i suggerimenti dei malefici"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Nessun suggerimento passando sopra un'icona di maleficio\n"..l.RDL.."Disattiva anche il clic destro per annullare un maleficio";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Barre informative";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Predefinito";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "Colori di classe";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "La tua scelta di colore: ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Nessuna icona";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "Icona della fazione |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "Colore se inferiore";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "Seleziona il colore del livello se \195\168 inferiore al tuo";
l.OPTION_NAMEPLATES_COLOR_OVER = "Colore se superiore";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "Seleziona il colore del livello se \195\168 superiore al tuo";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Mai";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Non mostra mai il livello sulle barre informative.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Se diverso dal tuo";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Se diverso dal tuo, colorato";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Sempre";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Sempre, colorato";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Nomi alleati";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Colore del nome sulle barre informative alleate (fuori istanze)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Barre alleate";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Colore delle barre informative alleate (fuori istanze)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Texture Barre alleate"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Texture delle barre informative alleate (fuori istanze)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "Icone PvP alleate";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Mostra le icone PvP sui nomi alleati.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "Livelli alleati";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Mostra il livello sulle barre informative alleate.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Nomi nemici";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Colore del nome sulle barre informative nemiche (fuori istanze)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Barre nemiche";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Colore delle barre informative nemiche (fuori istanze)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Texture Barre nemiche"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Texture delle barre informative nemiche (fuori istanze)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "Icone PvP nemiche";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Mostra le icone PvP sui nomi nemici.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "Livelli nemici";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Mostra il livello sulle barre informative nemiche.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."Mostra le icone del bersaglio (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) sulle cornici del raid"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "Icone del raid";
l.OPTION_RAIDICONS_ANCHOR = "Allineamento delle icone";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Posizione dell'icona del bersaglio nella cornice del raid";
l.OPTION_CENTER = "Centro"
l.OPTION_TOPLEFT = "In Alto a Sinistra";
l.OPTION_TOPRIGHT = "In Alto a Destra";
l.OPTION_BOTTOMLEFT = "In Basso a Sinistra";
l.OPTION_BOTTOMRIGHT = "In Basso a Destra";
l.OPTION_RAIDICONS_SIZE = "Dimensione delle icone";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Regola la dimensione delle icone del raid";
l.OPTION_RAIDICONS_RELATIVE_X = "Posizione orizzontale";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Regola la posizione orizzontale relativa delle icone del raid";
l.OPTION_RAIDICONS_RELATIVE_Y = "Posizione verticale";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Regola la posizione verticale relativa delle icone del raid";
-- KRI END

l.OPTION_RESET_OPTIONS = "Reimposta il profilo";
l.OPTION_RELOAD_REQUIRED = "Alcuni cambiamenti richiedono un ricaricamento (scrivi: "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Opzioni che richiedono un ricaricamento";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Mostra i messaggi";
l.OPTION_SHOWMSGWARNING = l.GYL.."Mostra gli avvisi";
l.OPTION_SHOWMSGERR = l.GYL.."Mostra gli errori";
l.OPTION_COMPARTMENT_FILTER = "Mostra nel Compartment Filter";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "Nella lista degli addon in alto a destra";
l.OPTION_WHATSNEW = "Novit\195\160";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Ricorda di attivare l'opzione "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Mostra i frame del gruppo quando sei solo "..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Mostra anche i frame del gruppo in raid"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Mostra sia i frame del gruppo che quelli del raid (quando sei in raid)"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s l'opzione %s|r di %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Nota: Digita "..l.YL.."/reload|r dopo il "..HUD_EDIT_MODE_MENU..", per evitare errori";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Attiva il "..l.YL..HUD_EDIT_MODE_MENU.."|r, e mostra direttamente le opzioni di "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "Test delle cornici del raid attivato (testabile in "..HUD_EDIT_MODE_MENU..")\n"
                    .."Clicca di nuovo per fermare!";
end