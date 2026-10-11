-------------------------------------------------------------------------------
-- French localization
-------------------------------------------------------------------------------

local _, ns = ...
local l = ns.I18N;

l.VERS_TITLE    = format("%s %s", ns.TITLE, ns.VERSION);

l.CONFLICT_MESSAGE = "D\195\169sactiv\195\169 : Conflit avec %s";

-- Whats new info
l.WHATSNEW = [[ Nouveautés :
- Nouvelles options (Midnight):
  > Espacement entre les buffs & débuffs
  > Masquer le tooltip lors du survol d'une icône de buff ou débuff
  > Choix du filtre pour les buffs & débuffs
]];

l.WHATSNEW = l.YL..l.VERS_TITLE.." -"..l.YLL..l.WHATSNEW;

l.SUBTITLE      = "Assistance cadres de raid";
l.DESC          = "Am\195\169liore les cadres de raid.\n\n"
.." - Met en \195\169vidence le fond des joueurs en manque de vie\n\n"
.." - Les barres invers\195\169es utiliseront votre choix de couleurs\n\n"
.." - Transparence des unit\195\169s hors de port\195\169e\n\n"
.." - Raid toujours visible\n\n"
.."\n"
.."Am\195\169liore les buffs / d\195\169buffs (taille, max affich\195\169s, ...)\n\n"
.."Colorise les noms en barre d'info, avec ic\195\180nes JcJ |TInterface/PVPFrame/PVP-Currency-Alliance:16|t|TInterface/PVPFrame/PVP-Currency-Horde:16|t\n\n"
.."Affiche les ic\195\180nes de cible (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) sur les cadres de raid\n\n"
l.OPTIONS_TITLE = format("%s - Options", l.VERS_TITLE);

-- Messages
l.MSG_LOADED         = format("%s lanc\195\169", l.VERS_TITLE);
l.MSG_SDB            = "Kallye menu d\'Options";

l.INIT_FAILED = format("%s pas charg\195\169 correctement !", l.VERS_TITLE);

local required = l.YL.."*";
l.OPTION_RAID_HEADER = "Groupe / Raid";
l.OPTION_HIGHLIGHTLOWHP = "Mettre en \195\169vidence le manque de vie (couleurs dynamiques)"..required;
l.OPTION_REVERTBAR = "Barres de "..l.YL.."vies invers\195\169es|r (moins on a de vie, plus la barre grandit !) ";
l.OPTION_HEALTH_LOW = "Presque mort !";
l.OPTION_HEALTH_LOW_TOOLTIP = "La couleur sera appliqu\195\169e "..l.YLL.."SOUS|r cette limite\n\n"
    .."ex : Rouge sous 25%";
l.OPTION_HEALTH_WARN = "Attention";
l.OPTION_HEALTH_WARN_TOOLTIP = "La couleur sera appliqu\195\169e "..l.YLL.."\195\128|r cette limite\n\n"
    .."ex : Jaune \195\160 50%";
l.OPTION_HEALTH_OK = "Bonne sant\195\169";
l.OPTION_HEALTH_OK_TOOLTIP = "La couleur sera appliqu\195\169e "..l.YLL.."AU-DESSUS|r DE cette limite\n\n"
    .."ex : Vert apr\195\168s 75%";
l.OPTION_HEALTH_ALPHA = l.WH.."Transparence"..required;
l.OPTION_HEALTH_ALPHA_TOOLTIP = "Transparence de la barre de vie (avec la couleur de classe)\n"..l.CY.."Par d\195\169faut dans Wow : 100%"
l.OPTION_MOVEROLEICONS = "Ic\195\180ne de r\195\180le en haut \195\160 gauche";
l.OPTION_HIDEDAMAGEICONS = "Masquer l\'ic\195\180ne de r\195\180le 'd\195\169g\195\160ts'";
l.OPTION_HIDEREALM = "Masquer le royaume des joueurs";
l.OPTION_HIDEREALM_TOOLTIP = "Les noms de royaumes seront masqu\195\169s, ainsi "..l.YLL.."Illidan - Varimathras|r deviendra "..l.YLL.."Illidan (*)|r";
l.OPTION_ICONONDEATH = "Ajouter "..l.RT8.." aux noms des morts";
l.OPTION_FRIENDSCLASSCOLOR = "Noms color\195\169s par classe";
l.OPTION_FRIENDSCLASSCOLOR_TOOLTIP = "Noms des joueurs color\195\169s par classe (cadres de groupe/raid)";
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR = format("Blizzard : %s", RAID_USE_CLASS_COLORS)
l.OPTION_BLIZZARDFRIENDSCLASSCOLOR_TOOLTIP = format("%s : %s", INTERFACE_LABEL, OPTION_TOOLTIP_RAID_USE_CLASS_COLORS)
l.OPTION_BAR_TEXTURE = "Texture"
l.OPTION_BAR_TEXTURE_TOOLTIP = "Texture de la barre de vie"
l.OPTION_SOLORAID = l.CY.."Affiche les cadres de raid en mode solo"..required;
l.OPTION_SOLORAID_TOOLTIP = "Cadres de groupe/raid toujours visibles,\nactivera "..l.YLL..USE_RAID_STYLE_PARTY_FRAMES;

l.OPTION_EDITMODE_PARTY = format("Blizzard : %s", USE_RAID_STYLE_PARTY_FRAMES)
l.OPTION_EDITMODE_PARTY_TOOLTIP = "";
l.OPTION_DEBUG_ON = "! Tester les cadres de raid !";
l.OPTION_DEBUG_ON_MESSAGE = "Test des cadres de raid activ\195\169, recliquez pour stopper !";
l.OPTION_DEBUG_OFF = "! ARR\195\138TER LE TEST !";
l.OPTION_DEBUG_OFF_MESSAGE = "Test arr\195\170t\195\169, vous pouvez reprendre une activit\195\169 normale";

l.OPTION_ACTIVATE_MODULE = "Activer / D\195\169sactiver le module"
l.OPTION_HIDEDISABLED = l.GYL.."Masquer les modules d\195\169sactiv\195\169s"

-- KF START
l.OPTION_INRANGE = "Transparence \195\160 port\195\169e";
l.OPTION_INRANGE_TOOLTIP = l.CY.."Par d\195\169faut dans Wow : 100%";
l.OPTION_NOTINRANGE = "Transparence si hors de port\195\169e";
l.OPTION_NOTINRANGE_TOOLTIP = l.CY.."Par d\195\169faut dans Wow : "..l.DEFAULT_ALPHA_OUTOFRANGE.."%";
l.OPTION_NOTINCOMBAT = "Transparence du raid hors de combat";
l.OPTION_NOTINCOMBAT_TOOLTIP = l.CY.."Par d\195\169faut dans Wow : 100%";
l.OPTION_ALPHADISPELOVERLAY = "Transparence de l'indicateur de dissipations"
l.OPTION_ALPHADISPELOVERLAY_TOOLTIP = l.OPTION_NOTINCOMBAT_TOOLTIP
-- KF END

l.OPTION_ACTIVATE_MODULE_DEBUFFS = l.OPTION_ACTIVATE_MODULE
    .. ( ns.LoadRaidFramesAuras and "\n"..l.WH.."Les buffs/d\195\169buffs Blizzard seront remplac\195\169s par RaidFrameAuras" or "")
-- KBD START
l.OPTION_BUFFS_HEADER = "Debuffs / Buffs"
l.OPTION_ORIENTATION_LeftThenUp = "\195\128 Gauche, puis en Haut"
l.OPTION_ORIENTATION_LeftThenUp_Default = l.DEFAULT.."\195\128 Gauche, puis en Haut (par d\195\169faut)"
l.OPTION_ORIENTATION_UpThenLeft = "En Haut, puis \195\160 Gauche"
l.OPTION_ORIENTATION_RightThenUp = "\195\128 Droite, puis en Haut"
l.OPTION_ORIENTATION_RightThenUp_Default = l.DEFAULT.."\195\128 Droite, puis en Haut (par d\195\169faut)"
l.OPTION_ORIENTATION_UpThenRight = "En Haut, puis \195\160 Droite"
l.OPTION_BUFFSSCALE = "Taille des buffs"..required;
l.OPTION_BUFFSSCALE_TOOLTIP = l.CY.."Par d\195\169faut dans Wow : 1"
l.OPTION_MAXBUFFS = "Limite de buffs"..required;
l.OPTION_MAXBUFFS_TOOLTIP = "Nombre maximum de buffs \195\160 afficher\n"..l.CY.."Par d\195\169faut dans Wow : "..ns.DEFAULT_MAXBUFFS;
l.OPTION_MAXBUFFS_FORMAT = "%d |4buff:buffs";
l.OPTION_BUFFSPERLINE = "Buffs par ligne"..required;
l.OPTION_BUFFSPERLINE_TOOLTIP = "Nombre de buffs par ligne\n"..l.CY.."Ignor\195\169 si sup\195\169rieur \195\160 la Limite";
l.OPTION_BUFFSPERLINE_FORMAT = "%d par ligne";
l.OPTION_BUFFSORIENTATION = "Orientation des buffs"..required;
l.OPTION_BUFFSORIENTATION_TOOLTIP = "Choisissez l\'arrangement des buffs (supporte le multiligne)\n"..l.CY.."Par d\195\169faut : "..l.OPTION_ORIENTATION_LeftThenUp
l.OPTION_BUFFS_RELATIVE_X = "Position horizontale"..required;
l.OPTION_BUFFS_RELATIVE_X_TOOLTIP = "Ajustez la position horizontale relative des buffs";
l.OPTION_BUFFS_RELATIVE_Y = "Position verticale"..required;
l.OPTION_BUFFS_RELATIVE_Y_TOOLTIP = "Ajustez la position verticale relative des buffs";
l.OPTION_DEBUFFSSCALE = "Taille des d\195\169buffs"..required;
l.OPTION_DEBUFFSSCALE_TOOLTIP = l.CY.."Par d\195\169faut dans Wow : 1"
l.OPTION_MAXDEBUFFS = "Limite de d\195\169buffs"..required;
l.OPTION_MAXDEBUFFS_TOOLTIP = "Nombre maximum de d\195\169buffs \195\160 afficher\n"..l.CY.."Par d\195\169faut dans Wow : "..ns.DEFAULT_MAXDEBUFFS;
l.OPTION_MAXDEBUFFS_FORMAT = "%d |4d\195\169buff:d\195\169buffs";
l.OPTION_DEBUFFSPERLINE = "D\195\169buffs par ligne"..required;
l.OPTION_DEBUFFSPERLINE_TOOLTIP = "Nombre d'ic\195\180nes de d\195\169buff par ligne\n"..l.CY.."Ignor\195\169 si sup\195\169rieur \195\160 la Limite";
l.OPTION_DEBUFFSPERLINE_FORMAT = "%d par ligne";
l.OPTION_DEBUFFSORIENTATION = "Orientation des d\195\169buffs"..required;
l.OPTION_DEBUFFSORIENTATION_TOOLTIP = "Choisissez l\'arrangement des d\195\169buffs (supporte le multiligne)\n"..l.CY.."Par d\195\169faut : "..l.OPTION_ORIENTATION_RightThenUp;
l.OPTION_DEBUFFS_RELATIVE_X = "Position horizontale"..required;
l.OPTION_DEBUFFS_RELATIVE_X_TOOLTIP = "Ajustez la position horizontale relative des d\195\169buffs";
l.OPTION_DEBUFFS_RELATIVE_Y = "Position verticale"..required;
l.OPTION_DEBUFFS_RELATIVE_Y_TOOLTIP = "Ajustez la position verticale relative des d\195\169buffs";
l.OPTION_USETAINTMETHOD = l.CY.."Affichage classique de la Limite de buffs / d\195\169buffs"..required.." "..l.ALERT
l.OPTION_USETAINTMETHOD_TOOLTIP = "D\195\169coch\195\169, utilise l'affichage exp\195\169rimental\nCoch\195\169, utilise l'affichage stable, mais avec une "..l.RDL.."erreur par session|r, pas si grave..."
l.OPTION_BUFFS_TAINTWARNING = l.ALERT.." Changer la Limite provoque une "..l.RDL.."erreur par session|r, pas si grave..."
l.OPTION_BUFFS_FLICKERWARNING = l.INFO.." Le repositionnement peut \195\170tre affect\195\169 quelques secondes \195\160 la mort d'un boss"
l.OPTION_BUFFS_HIDEBLIZZARDAURAS = " Masquer les auras Blizzard"
l.OPTION_BUFFS_RESET = "Annuler tout repositionnement"
l.OPTION_FILTER_AUTO_DEFAULT = l.DEFAULT.."Auto — suit le combat (défaut)";
l.OPTION_FILTER_RAID = "Toujours la liste hors combat";
l.OPTION_FILTER_RAID_IN_COMBAT = "Toujours la liste en combat";
l.OPTION_BUFFS_SPACING_X = "Espacement horizontal";
l.OPTION_BUFFS_SPACING_X_TOOLTIP = "Écart horizontal, en pixels, entre les icônes de buffs\n"..l.CY.."Défaut : 0";
l.OPTION_BUFFS_SPACING_Y = "Espacement vertical";
l.OPTION_BUFFS_SPACING_Y_TOOLTIP = "Écart vertical, en pixels, entre les icônes de buffs\n"..l.CY.."Défaut : 1";
l.OPTION_BUFFSFILTER = "Filtre des buffs";
l.OPTION_BUFFSFILTER_TOOLTIP = "Quelle liste de buffs Blizzard fournit\n"..l.CY.."Auto bascule à l'entrée et à la sortie du combat";
l.OPTION_BUFFS_HIDETOOLTIP = "Masquer les infobulles des buffs"..required;
l.OPTION_BUFFS_HIDETOOLTIP_TOOLTIP = "Aucune infobulle au survol d'une icône de buff\n"..l.RDL.."Désactive aussi le clic droit pour annuler un buff";
l.OPTION_DEBUFFS_SPACING_X = "Espacement horizontal";
l.OPTION_DEBUFFS_SPACING_X_TOOLTIP = "Écart horizontal, en pixels, entre les icônes de débuffs\n"..l.CY.."Défaut : 0";
l.OPTION_DEBUFFS_SPACING_Y = "Espacement vertical";
l.OPTION_DEBUFFS_SPACING_Y_TOOLTIP = "Écart vertical, en pixels, entre les icônes de débuffs\n"..l.CY.."Défaut : 1";
l.OPTION_DEBUFFSFILTER = "Filtre des débuffs";
l.OPTION_DEBUFFSFILTER_TOOLTIP = "Quelle liste de débuffs Blizzard fournit\n"..l.CY.."Auto bascule à l'entrée et à la sortie du combat";
l.OPTION_DEBUFFS_HIDETOOLTIP = "Masquer les infobulles des débuffs"..required;
l.OPTION_DEBUFFS_HIDETOOLTIP_TOOLTIP = "Aucune infobulle au survol d'une icône de débuff\n"..l.RDL.."Désactive aussi le clic droit pour annuler un débuff";
-- KBD END

-- KNC START
l.OPTION_OTHERS_HEADER = "Barres d'infos";
l.OPTION_NAMEPLATES_USECOLOR_BLIZZARD = l.DEFAULT.."Par d\195\169faut";
l.OPTION_NAMEPLATES_USECOLOR_CLASS = "Couleurs de classe";
l.OPTION_NAMEPLATES_USECOLOR_CUSTOM = "Votre choix de couleur : ";
l.OPTION_NAMEPLATES_SHOWPVPICONS_BLIZZARD = l.DEFAULT.."Pas d'ic\195\180ne";
l.OPTION_NAMEPLATES_SHOWPVPICONS_FACTION = "Ic\195\180ne de faction |TInterface/PVPFrame/PVP-Currency-Alliance:16|t - |TInterface/PVPFrame/PVP-Currency-Horde:16|t";
l.OPTION_NAMEPLATES_COLOR_UNDER = "Couleur si inf\195\169rieur";
l.OPTION_NAMEPLATES_COLOR_UNDER_TOOLTIP = "S\195\169lectionnez la couleur du niveau s'il est inf\195\169rieur au votre";
l.OPTION_NAMEPLATES_COLOR_OVER = "Couleur si sup\195\169rieur";
l.OPTION_NAMEPLATES_COLOR_OVER_TOOLTIP = "S\195\169lectionnez la couleur du niveau s'il est sup\195\169rieur au votre";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER = l.DEFAULT.."Jamais";
l.OPTION_NAMEPLATES_SHOWLEVEL_NEVER_TOOLTIP = "Ne montre jamais le niveau sur les barres d'info.";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT = "Si diff\195\169rent du votre";
l.OPTION_NAMEPLATES_SHOWLEVEL_DIFFERENT_COLORED = "Si diff\195\169rent du votre, color\195\169";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS = "Toujours";
l.OPTION_NAMEPLATES_SHOWLEVEL_ALWAYS_COLORED = "Toujours, color\195\169";

l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR = "Noms alli\195\169s";
l.OPTION_FRIENDSNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Couleur du nom sur les barres d'info alli\195\169es (hors instances)";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR = "Barres alli\195\169es";
l.OPTION_FRIENDSNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Couleur des barres d'info alli\195\169es (hors instances)"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE = "Texture Barres alli\195\169es"
l.OPTION_FRIENDSNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Texture des barres d'info alli\195\169es (hors instances)"
l.OPTION_FRIENDSNAMEPLATES_PVPICONS = "Ic\195\180nes JcJ alli\195\169es";
l.OPTION_FRIENDSNAMEPLATES_PVPICONS_TOOLTIP = "Affiche les ic\195\180nes JcJ sur les noms alli\195\169s.";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL = "Niveaux alli\195\169s";
l.OPTION_FRIENDSNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Affiche le niveau sur les barres d'info alli\195\169es.";

l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR = "Noms ennemis";
l.OPTION_ENEMIESNAMEPLATES_TXT_USECOLOR_TOOLTIP = "Couleur du nom sur les barres d'info ennemies (hors instances)";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR = "Barres ennemies";
l.OPTION_ENEMIESNAMEPLATES_BAR_USECOLOR_TOOLTIP = "Couleur des barres d'info ennemies (hors instances)";
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE = "Texture Barres ennemies"
l.OPTION_ENEMIESNAMEPLATES_BAR_TEXTURE_TOOLTIP = "Texture des barres d'info ennemies (hors instances)"
l.OPTION_ENEMIESNAMEPLATES_PVPICONS = "Ic\195\180nes JcJ ennemies";
l.OPTION_ENEMIESNAMEPLATES_PVPICONS_TOOLTIP = "Affiche les ic\195\180nes JcJ sur les noms ennemis.";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL = "Niveaux ennemis";
l.OPTION_ENEMIESNAMEPLATES_TXT_SHOWLEVEL_TOOLTIP = "Affiche le niveau sur les barres d'info ennemies.";
-- KNC END

l.OPTION_ACTIVATE_MODULE_RAIDICONS = l.OPTION_ACTIVATE_MODULE .. "\n"
    ..l.WH.."Affiche les ic\195\180nes de cible (|TInterface/TargetingFrame/UI-RaidTargetingIcon_1:0|t|TInterface/TargetingFrame/UI-RaidTargetingIcon_2:0|t...) sur les cadres de raid"
-- KRI START
l.OPTION_RAIDICONS_HEADER = "Ic\195\180nes de raid";
l.OPTION_RAIDICONS_ANCHOR = "Alignement des ic\195\180nes";
l.OPTION_RAIDICONS_ANCHOR_TOOLTIP = "Position de l'ic\195\180ne cible dans le cadre de raid";
l.OPTION_CENTER = "Centre"
l.OPTION_TOPLEFT = "Haut Gauche";
l.OPTION_TOPRIGHT = "Haut Droit";
l.OPTION_BOTTOMLEFT = "Bas Gauche";
l.OPTION_BOTTOMRIGHT = "Bas Droit";
l.OPTION_RAIDICONS_SIZE = "Taille des ic\195\180nes";
l.OPTION_RAIDICONS_SIZE_TOOLTIP = "Ajustez la taille des ic\195\180nes de raid";
l.OPTION_RAIDICONS_RELATIVE_X = "Position horizontale";
l.OPTION_RAIDICONS_RELATIVE_X_TOOLTIP = "Ajustez la position horizontale relative des ic\195\180nes de raid";
l.OPTION_RAIDICONS_RELATIVE_Y = "Position verticale";
l.OPTION_RAIDICONS_RELATIVE_Y_TOOLTIP = "Ajustez la position verticale relative des ic\195\180nes de raid";
-- KRI END

l.OPTION_RESET_OPTIONS = "R\195\169initialiser le profil";
l.OPTION_RELOAD_REQUIRED = "Certains changements n\195\169cessitent un rechargement (\195\169crivez : "..l.YL.."/reload|r )";
l.OPTIONS_ASTERIX = l.YL.."*|r"..l.WH..": Options n\195\169cessitant un rechargement";

l.OPTION_SHOWMSGNORMAL = l.GYL.."Afficher les messages";
l.OPTION_SHOWMSGWARNING = l.GYL.."Afficher les alertes";
l.OPTION_SHOWMSGERR = l.GYL.."Afficher les erreurs";
l.OPTION_COMPARTMENT_FILTER = "Afficher dans le Compartment Filter";
l.OPTION_COMPARTMENT_FILTER_TOOLTIP = "Dans la iste des addons en haut à droite";
l.OPTION_WHATSNEW = "Nouveaut\195\169s";

--? Edit Mode - Since DragonFlight (10)
if (EditModeManagerFrame.UseRaidStylePartyFrames) then
    -- Edit mode takes a while...
    l.UpdateLocales = function ()
        C_Timer.After(1, function()
        if (not ns.CanEditActiveLayout()) then
            l.OPTION_SOLORAID_TOOLTIP = "Pensez \195\160 activer l'option "..l.YLL..HUD_EDIT_MODE_SETTING_UNIT_FRAME_RAID_STYLE_PARTY_FRAMES.."|r ("..HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL..")";
            l.DESC = l.DESC.."\n"..l.CY..l.OPTION_SOLORAID_TOOLTIP.."|r\n\n";
        end
        end)
    end
    l.OPTION_SOLORAID = l.CY.."Affiche les cadres de groupe en mode solo"..required;
    l.OPTION_SOLORAID_GROUPINRAID = "Affiche aussi les cadres de groupe en raid"..required
    l.OPTION_SOLORAID_GROUPINRAID_TOOLTIP = "Lorsque vous \195\170tes en raid, affiche les cadres de groupe et de raid en m\195\170me temps"
    l.OPTION_EDITMODE_PARTY_TOOLTIP = format("%s / %s l'option %s|r des %s|r\n(%s|r)", ENABLE, DISABLE, l.YL..USE_RAID_STYLE_PARTY_FRAMES, l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL, l.RDD..HUD_EDIT_MODE_MENU)
    l.OPTION_EDITMODE_BTN_PARTY = HUD_EDIT_MODE_MENU.." : "..HUD_EDIT_MODE_PARTY_FRAMES_LABEL;
    l.OPTION_EDITMODE_BTN_PARTY_NOTE = "Note : Tapez "..l.YL.."/reload|r apr\195\168s le "..HUD_EDIT_MODE_MENU..", pour \195\169viter toute erreur";
    l.OPTION_EDITMODE_BTN_PARTY_TOOLTIP = "Active le "..l.YL..HUD_EDIT_MODE_MENU.."|r, et affiche directement les options de "..l.YL..HUD_EDIT_MODE_PARTY_FRAMES_LABEL.."|r.\n\n"..l.CY..l.OPTION_EDITMODE_BTN_PARTY_NOTE.."|r";
    l.OPTION_DEBUG_ON_MESSAGE = "Test des cadres de raid activ\195\169 (testable en "..HUD_EDIT_MODE_MENU..")\n"
                    .."Recliquez pour stopper !";
end

