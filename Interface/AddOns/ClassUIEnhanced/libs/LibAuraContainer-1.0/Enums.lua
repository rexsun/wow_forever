--[[ LibAuraContainer-1.0: Enums

The classic-side exports. Data only: key names and values mirror
Blizzard's 12.1.5 tables exactly. Key names are persisted by consumers, so
never rename one. On native clients Core.lua exports Blizzard's own tables and
this file does nothing.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

LAC.SortMethod = {
	Default = 0,
	BigDefensive = 1,
	UnitFrameDebuff = 2,
	ImportantOnly = 3,
	Expiration = 4,
	ExpirationOnly = 5,
	Name = 6,
	NameOnly = 7,
	AuraInstanceIDOnly = 8,
}

LAC.SortDirection = { Normal = 0, Reverse = 1 }

LAC.AuraDataType = { Aura = 0, ItemEnchantment = 1 }

-- Bit flags.
LAC.FrameRefreshResult = { None = 0, FrameAssignmentsChanged = 1, VisibilityChanged = 2 }

local slot = { MainHand = 0, OffHand = 1, Ranged = 2 }
LAC.ItemEnchantmentSlot = slot

-- Inventory slot ids 16/17/18 (INVSLOT_MAINHAND/OFFHAND/RANGED on every client).
LAC.ItemEnchantmentToInventorySlot = { [slot.MainHand] = 16, [slot.OffHand] = 17, [slot.Ranged] = 18 }

LAC.ItemEnchantmentSortMethod = { Slot = 0, Duration = 1 }

LAC.ItemEnchantmentSortOrder = { [slot.MainHand] = 1, [slot.OffHand] = 2, [slot.Ranged] = 3 }

LAC.AuraProcessingPolicy = { None = 0, ProcessAura = 1 }

LAC.ItemEnchantmentPlacement = { BeforeAuraGroups = 0, AfterAuraGroups = 1 }

LAC.FlowLayoutAxis = { Horizontal = 0, Vertical = 1 }

-- Growth sign per screen direction; Right/Up and Left/Down share a value.
LAC.FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }

LAC.DispelTypeTextureStyle = { Border = 0, BorderWithIcon = 1, Icon = 2, PreserveAsset = 3, CustomAsset = 4 }

LAC.DispelTypeStealableFilter = { Stealable = 0, NotStealable = 1 }

LAC.UpdateMode = { Assignment = 0, Update = 1 }

-- Option defaults. Options whose default is "unset" have no key here.
LAC.Defaults = {
	Layout = {
		axis = LAC.FlowLayoutAxis.Horizontal,
		anchorPoint = "TOPLEFT",
		horizontalGrowthDirection = LAC.FlowDirection.Right,
		verticalGrowthDirection = LAC.FlowDirection.Down,
		paddingLeft = 0,
		paddingRight = 0,
		paddingTop = 0,
		paddingBottom = 0,
		maximumLineSize = math.huge,
	},
	Group = {
		maxFrameCount = math.huge,
		sortMethod = LAC.SortMethod.Default,
		sortDirection = LAC.SortDirection.Normal,
	},
	GroupLayout = {
		elementSpacing = 0,
		lineSpacing = 0,
		groupSpacing = 0,
		groupLineSpacing = 0,
		forceNewLine = false,
	},
	Slot = {
		sortMethod = LAC.SortMethod.Default,
		sortDirection = LAC.SortDirection.Normal,
	},
	ProcessAuraPolicy = {
		ignoreBuffs = false,
		ignoreDebuffs = false,
		ignoreDispelDebuffs = false,
		displayOnlyDispellableDebuffs = false,
	},
	ItemEnchantment = {
		hidePermanent = false,
	},
	ItemEnchantmentLayout = {
		placement = LAC.ItemEnchantmentPlacement.BeforeAuraGroups,
		elementSpacing = 0,
		lineSpacing = 0,
		groupSpacing = 0,
		groupLineSpacing = 0,
		forceNewLine = false,
	},
}
