--[[ LibAuraContainer-1.0: Core

Registers the library, picks the backend once at load and creates containers.

BACKEND
  Chosen once, here, by feature presence: if the client knows Blizzard's
  "CustomAuraContainerTemplate" the library is native and CreateContainer hands
  back Blizzard's frame untouched; otherwise the emulated container
  (Emulated/*.lua) is used. Never decided by build number.

PRIVATE NAMESPACE (every library file follows this)
  The files share one private table, registered as its own LibStub entry:

      local Private = LibStub("LibAuraContainer-1.0-Private")

  It is never written to a global and adds nothing to the public LAC table.
  Several addons may embed different copies of the library. Only the copy that
  wins LibStub's version check may run; the files of one copy load back to back,
  so Core.lua (always first in LibAuraContainer.xml) leaves a flag for the files
  that follow it:

      Private.loading  true  while the files of the winning copy load
                       false when this copy lost (equal or older MINOR); Core.lua
                             writes nothing else then, and the rest of the
                             copy's files must return at once
      Private.LAC      the public library table

  Every file after Core.lua therefore starts with

      local Private = LibStub("LibAuraContainer-1.0-Private")
      if not Private.loading then return end

  and every Emulated/*.lua file with

      local Private = LibStub("LibAuraContainer-1.0-Private")
      if not Private.loading or Private.LAC.IsNative then return end

  so on native clients they load but do nothing observable.

  Upgrades: a newer copy gets the same LAC and Private tables back from LibStub
  and takes over by assigning its functions unconditionally. Long-lived state
  kept in Private must be created with `Private.x = Private.x or {}` so a newer
  copy can adopt what an older one built.

  Hooks between files are plain fields of Private, e.g. Private.NewContainer
  (the emulated constructor, provided by Emulated/Container.lua).
]]

local MAJOR, MINOR = "LibAuraContainer-1.0", 6
local PRIVATE_MAJOR = MAJOR .. "-Private"

local LAC = LibStub:NewLibrary(MAJOR, MINOR)
if not LAC then
	-- An equal or newer copy is active; tell the rest of this copy's files to stand down.
	LibStub(PRIVATE_MAJOR).loading = false
	return
end

local Private = LibStub:NewLibrary(PRIVATE_MAJOR, MINOR)
Private.loading = true
Private.LAC = LAC

local NATIVE_TEMPLATE = "CustomAuraContainerTemplate"

LAC.IsNative = (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(NATIVE_TEMPLATE)) ~= nil

-- The consumer's template list, trimmed, without empty entries and without
-- Blizzard's container template (native adds it first, classic lacks it); nil
-- when nothing is left.
local function cleanTemplates(list)
	if not list then return nil end
	local kept, native = {}, NATIVE_TEMPLATE:lower()
	for t in list:gmatch("[^,]+") do
		t = t:match("^%s*(.-)%s*$")
		if t ~= "" and t:lower() ~= native then kept[#kept + 1] = t end
	end
	return kept[1] and table.concat(kept, ", ") or nil
end

if LAC.IsNative then
	-- Pass-through only: no method, field or script of the frame is touched.
	function LAC:CreateContainer(name, parent, extraTemplates)
		local extra = cleanTemplates(extraTemplates)
		return CreateFrame("AuraContainer", name, parent, extra and NATIVE_TEMPLATE .. ", " .. extra or NATIVE_TEMPLATE)
	end

	-- Each export is Blizzard's own table.
	LAC.SortMethod = AuraContainerSortMethod
	LAC.SortDirection = AuraContainerSortDirection
	LAC.AuraDataType = AuraContainerAuraDataType
	LAC.FrameRefreshResult = AuraContainerFrameRefreshResult
	LAC.ItemEnchantmentSlot = AuraContainerItemEnchantmentSlot
	LAC.ItemEnchantmentToInventorySlot = AuraContainerItemEnchantmentToInventorySlot
	LAC.ItemEnchantmentSortMethod = AuraContainerItemEnchantmentSortMethod
	LAC.ItemEnchantmentSortOrder = AuraContainerItemEnchantmentSortOrder
	LAC.AuraProcessingPolicy = CustomAuraContainerAuraProcessingPolicy
	LAC.ItemEnchantmentPlacement = CustomAuraContainerItemEnchantmentPlacement
	LAC.Defaults = {
		Layout = CustomAuraContainerLayoutDefaults,
		Group = CustomAuraContainerGroupDefaultOptions,
		GroupLayout = CustomAuraContainerGroupLayoutDefaultOptions,
		Slot = CustomAuraContainerSlotDefaultOptions,
		ProcessAuraPolicy = CustomAuraContainerProcessAuraPolicyDefaultOptions,
		ItemEnchantment = CustomAuraContainerItemEnchantmentDefaultOptions,
		ItemEnchantmentLayout = CustomAuraContainerItemEnchantmentLayoutDefaultOptions,
	}
	LAC.FlowLayoutAxis = AnchorUtil.FlowLayoutAxis
	LAC.FlowDirection = AnchorUtil.FlowDirection
	LAC.DispelTypeTextureStyle = Enum.CustomAuraButtonDispelTypeTextureStyle
	LAC.DispelTypeStealableFilter = Enum.CustomAuraButtonDispelTypeStealableFilter
	LAC.UpdateMode = Enum.CustomAuraButtonUpdateMode
	LAC.Inbound = AuraContainerInbound
else
	-- Emulated/Container.lua provides the constructor, Enums.lua the enum and
	-- default exports, Emulated/Button.lua and Emulated/Tooltip.lua the Inbound
	-- functions; all of them load right after this file.
	function LAC:CreateContainer(name, parent, extraTemplates)
		return Private.NewContainer(name, parent, cleanTemplates(extraTemplates))
	end
	LAC.Inbound = {}
end
