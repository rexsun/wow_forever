--[[ LibAuraContainer-1.0: Emulated/Enchant

The client side of item enchantments on classic: what GetWeaponEnchantInfo
reports for one weapon. Keeps no state.

INTERFACE (Private.Enchant)

  Enchant.Read(slot) -> present, enchantID, remainingMs, charges, expires
      slot is an LAC.ItemEnchantmentSlot value. present is false when the
      weapon has no temporary enchant (or the client reports no such weapon);
      the other values are then nil. expires is false for an enchant whose
      remaining time is 0 or nil (remainingMs is then 0).

GetWeaponEnchantInfo returns four values per weapon (has enchant, remaining
milliseconds, charges, enchant ID), main hand first, then off hand, then
ranged.
]]

local Private = LibStub("LibAuraContainer-1.0-Private")
if not Private.loading or Private.LAC.IsNative then return end
local LAC = Private.LAC

local Enchant = {}
Private.Enchant = Enchant

local VALUES_PER_WEAPON = 4

local SLOT = LAC.ItemEnchantmentSlot
local WEAPON = { [SLOT.MainHand] = 1, [SLOT.OffHand] = 2, [SLOT.Ranged] = 3 }

function Enchant.Read(slot)
	local first = (WEAPON[slot] - 1) * VALUES_PER_WEAPON + 1
	local has, remainingMs, charges, enchantID = select(first, GetWeaponEnchantInfo())
	if not has then return false end
	remainingMs = remainingMs or 0
	return true, enchantID, remainingMs, charges or 0, remainingMs > 0
end
