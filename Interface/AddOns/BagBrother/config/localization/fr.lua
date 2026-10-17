--[[
	French Localization
--]]

local CONFIG = ...
local L = LibStub('AceLocale-3.0'):NewLocale(CONFIG, 'frFR')
if not L then return end

-- filters
L.InstalledFilters = 'Filtres installés'
L.CustomFilters = 'Filtres personnalisés'
L.NewFilter = 'Nouveau filtre'
L.NewSearch = 'Nouvelle recherche'
L.NewMacro = 'Nouvelle macro'
L.Import = 'Importer'
L.EnterSearch = 'Saisir la requête de recherche :'
L.SharePopup = 'Copiez ces données et partagez-les :'
L.ImportPopup = 'Collez les données à importer :|n|cnERROR_COLOR:(Avertissement - n’importez que des filtres provenant de sources fiables)|r'

-- general options
L.GeneralOptionsDescription = 'Configuration des options générales de %s'

L.CountItems = 'Activer l\'info-bulle du compteur d\'objets'
L.CountGuild = 'Inclure les banques de guilde'
L.CountCurrency = 'Activer l\'info-bulle du compteur d\'monnaies'
L.ConfirmGlobals = 'Êtes-vous sûr de vouloir désactiver les paramètres spécifiques à ce personnage ? Tous les paramètres spécifiques seront perdus.'
L.CharacterSpecific = 'Paramètres spécifiques au personnage'
L.DisplayBlizzard = 'Afficher les cadres de Blizzard pour les sacs désactivés'
L.DisplayBlizzardTip = 'Si activé, le panneau Blizzard par défaut sera affiché pour les sacs et containers de banque cachés.\n\n|cffff1919Nécessite de recharger l\'UI.|r'
L.Locked = 'Bloquer la position des fenêtres'
L.FlashFind = 'Activer résultat éclair'
L.FlashFindTip = 'Si activé, Alt+Clic sur un objet fait briller tous les emplacements contenant le même objet.'
L.Tooltips = 'Info-bulles'

-- frame options
L.FrameOptions = 'Options des fenêtres'
L.FrameOptionsDescription = 'Configuration des options spécifiques à une fenêtre de %s'

L.Frame = 'Fenêtre'
L.Enabled = 'Activer'
L.EnabledTip = 'Si désactivé, l\'UI Blizzard par defaut ne sera pas affichée pour cette fenêtre.\n\n|cffff1919Nécessite de recharger l\'UI.|r'
L.ActPanel = 'Se comporter comme un panneau standard'
L.ActPanelTip = [[
Si activé, ce panneau se positionnera
automatiquement comme les panneaux standards
le font, tels que le |cffffffffGrimoire|r ou la |cffffffffRecherche de groupe|r,
et ne pourra pas être déplacé.]]

L.BagToggle = 'Fenêtre du sac'
L.Broker = 'Activer le DataBroker'
L.Currency = 'Suivi des monnaies'
L.Deposit = 'Bouton de dépôt'
L.Sidebar = 'Filtres latéraux'
L.Sort = 'Bouton de tri'
L.Search = 'Champ de recherche'
L.Options = 'Affichage des options'
L.Tabs = 'Filtres du bas'

L.Appearance = 'Apparence'
L.Layer = 'Couche'
L.BagBreak = 'Séparation entre les sacs'
L.BreakSpace = 'Espacement de saut'
L.ByType = 'Par type'
L.ReverseBags = 'Inverser ordre des sacs'
L.ReverseSlots = 'Inverser ordre de tri'

L.Color = 'Couleur de la fenêtre'
L.BorderColor = 'Couleur de bordure'

L.Strata = 'Couche'
L.Skin = 'Apparence'
L.Columns = 'Colonnes'
L.Scale = 'Echelle'
L.ItemScale = 'Échelle des objets'
L.Spacing = 'Espacement'
L.Alpha = 'Opacité'

-- slot options
L.SlotOptions = 'Options de couleur'
L.SlotOptionsDescription = 'Options de colorisation des emplacements'

L.GlowQuality = 'Surligner les objets par qualité'
L.GlowQuest = 'Surligner les objets de quête'
L.GlowUnusable = 'Surligner les objets inutiles'
L.GlowSets = 'Surligner les objets d\'ensemble'
L.GlowNew = 'Surligner les nouveaux objets'
L.GlowPoor = 'Surligner les objets de faible qualité'
L.GlowAlpha = 'Contour lumineux des objets'

L.EmptySlots = 'Afficher un fond sur les emplacements vides'
L.SlotBackground = 'Artwork'
L.ColorSlots = 'Colorier les emplacements vides par type de sac'
L.AccountColor = 'Couleur du bataillon'
L.NormalColor = 'Normaux'
L.KeyColor = 'Clés'
L.QuiverColor = 'Carquois'
L.SoulColor = 'Sac d\'âmes'
L.ReagentColor = 'Banque des composants'
L.LeatherColor = 'Sac Travail du cuir'
L.InscribeColor = 'Sac Calligraphie'
L.HerbColor = 'Sac Herboristerie'
L.EnchantColor = 'Sac Enchantement'
L.EngineerColor = 'Sac Ingénierie'
L.GemColor = 'Sac de Gemmes'
L.MineColor = 'Sac de Minage'
L.TackleColor = 'Sac de Pêche'
L.FridgeColor = 'Sac de Cuisine'

-- auto display
L.DisplayOptions = 'Affichage automatique'
L.DisplayOptionsDescription = 'Options de l\'affichage automatique'

L.DisplayInventory = 'Afficher votre inventaire'
L.Auctioneer = 'quand vous visitez l\'hôtel des ventes'
L.Banker = 'quand vous visitez la banque'
L.Crafting = 'quand vous craftez'
L.GuildBanker = 'quand vous visitez votre banque de guilde'
L.VoidStorageBanker = 'Auprès de la Chambre du vide'
L.MailInfo = 'quand vous relevez votre courrier'
L.Merchant = 'quand vous quittez un marchand'
L.Character = 'quand vous ouvrez la fenêtre de votre personnage'
L.TradePartner = 'quand vous parlez à un commerçant'
L.Transmogrifier = 'quand vous modifiez vos objets'

L.CloseInventory = 'Fermer votre inventaire'
L.MapFrame = 'quand vous ouvrez la carte du monde'
L.Combat = 'quand vous entrez en combat'
L.Vehicle = 'quand vous montez dans un véhicule'

-- info
L.HelpDescription = 'Ici, nous répondons aux questions les plus fréquemment posées. Si aucune ne résout votre problème, vous pouvez demander de l’aide sur la communauté %s sur Discord.'
L.Patrons = 'Mécènes'
L.PatronsDescription = '%s est distribué gratuitement et financé grâce aux dons. Un immense merci à tous les soutiens sur Patreon et Paypal qui permettent au développement de continuer. Vous pouvez aussi devenir mécène sur |cFFF96854patreon.com/jaliborc|r.'
L.AskCommunity = 'Demander à la communauté'
L.JoinUs = 'Rejoignez-nous'

L.FAQ = {
  'Comment déposer directement des objets dans la banque de la bande de guerre ?',
  'Faites Maj + clic droit sur l’emplacement de l’objet et il sera placé dans les sacs de la bande de guerre au lieu des sacs normaux.',

  'Comment voir la banque, la guilde ou un autre personnage hors ligne ?',
  'Cliquez sur le bouton "Affichage hors ligne" en haut à gauche de votre inventaire. Il ressemble au portrait du personnage que vous jouez actuellement.',

  'Comment faire pour qu’ADDON oublie un personnage supprimé ou renommé ?',
  'Cliquez sur le bouton "Affichage hors ligne" en haut à gauche de votre inventaire. Chaque nom de personnage possède un bouton de suppression à côté (une croix rouge). Cliquez sur la croix du personnage que vous souhaitez supprimer.',

  'Quelque chose ne va pas ! Les niveaux d’objet ne s’affichent pas.',
  'ADDON n’affiche pas nativement les niveaux d’objet. Vous devez utiliser un module tiers tel que |cffffd200Bagnon ItemLevel|r ou |cffffd200Bagnon ItemInfo|r. Essayez de mettre à jour vos modules, la cause la plus fréquente est une version obsolète.|n|nVeuillez signaler tout problème de module à leurs auteurs, et non à Jaliborc.',

  'Certains de mes sacs n’apparaissent pas.',
  'Vous les avez probablement cachés par accident. Cliquez sur le bouton Sacs en haut à gauche de la fenêtre pour les afficher. Vous pouvez ensuite cliquer sur un sac pour basculer sa visibilité.',

  'Comment activer/désactiver ADDON pour la banque, le vide, etc. ?',
  'Allez dans ADDON -> Paramètres des fenêtres. Les deux premières options du panneau permettent de choisir la "fenêtre" à activer et de cliquer sur "Activer la fenêtre".'
}
