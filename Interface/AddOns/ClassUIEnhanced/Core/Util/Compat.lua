--[[
    Compat — the one place classic (MoP Classic) API divergence lives (#27).

    `.context/api.md` makes every other file call `C_*` directly, with no
    aliases and no existence guards.  This file is the carve-out: it wraps the
    APIs a supported client lacks, picks each implementation ONCE at load by
    feature presence (never by build number), and always hands back the retail
    shape, so a call site reads the same on every client.

    Only APIs measured missing in a MoP 5.5.4 client are here (2026-10-08).
    Retail-only class content that sits behind a class or talent check
    (Devourer, Evoker, Crusading Strikes) never runs on MoP and calls its
    APIs directly.  The aura side is LibAuraContainer's, not this file's.
--]]

local _
---@type string, private
local addonName, private = ...

---@class compat
---@field GetOverrideSpell fun(spellID: number): number  the active spell; the input when nothing overrides it
---@field GetBaseSpell fun(spellID: number): number  the base spell; the input when it is one
---@field GetLastCategoryCooldownSource fun(spellCategoryID: number): number|nil  nil on clients without it
---@field GetItemCooldown fun(itemID: number): number, number, boolean  startTime, duration, enable (boolean on every client)
---@field GetTemporaryEnchantmentInfo fun(invSlot: number): table|nil  `{ hasExpirationTime, remainingTimeMs, chargesRemaining, enchantID }`
---@field GetNumSpellBookSkillLines fun(): number
---@field GetSpellBookSkillLineInfo fun(skillLineIndex: number): table|nil  retail `SpellBookSkillLineInfo` fields the addon reads
---@field GetSpellBookItemInfo fun(slot: number, bank: number): table|nil  retail `SpellBookItemInfo` fields the addon reads
---@field GetGlidingInfo fun(): boolean, boolean, number  isGliding, canGlide, forwardSpeed
---@field GetUnitChargedPowerPoints fun(unit: string): number[]|nil
---@field GetSpecializationRole fun(specIndex: number): string|nil  nil on a talent-tab client (Era, TBC, Wrath)
---@field PlaySoundKit fun(soundKitID: number)  the CDM alert channel, "Gameplay SFX" where the client has it
---@field UnitIsPlayerControlledOrGroupMember fun(unit: string): boolean
---@field ResizeToBoundsRect fun(frame: frame)
---@field HasCooldownManager fun(): boolean  Blizzard's Cooldown Manager UI addon is loaded (false on MoP Classic)

---@class private : table
---@field compat compat

---@type compat
local compat = {}
private.compat = compat

-- Spells -----------------------------------------------------------------

if C_Spell.GetOverrideSpell then
    compat.GetOverrideSpell = C_Spell.GetOverrideSpell
    compat.GetBaseSpell = C_Spell.GetBaseSpell
else
    -- The C_SpellBook pair returns nil where retail returns the input.
    compat.GetOverrideSpell = function(spellID)
        return C_SpellBook.FindSpellOverrideByID(spellID) or spellID
    end
    compat.GetBaseSpell = function(spellID)
        return C_SpellBook.FindBaseSpellByID(spellID) or spellID
    end
end

compat.GetLastCategoryCooldownSource = C_Spell.GetLastCategoryCooldownSource or function()
    return nil
end

-- Items ------------------------------------------------------------------

if C_Item.GetItemCooldown then
    compat.GetItemCooldown = C_Item.GetItemCooldown
else
    -- `enable` is a number there, and 0 is truthy in Lua.
    compat.GetItemCooldown = function(itemID)
        local startTime, duration, enable = C_Container.GetItemCooldown(itemID)
        return startTime, duration, enable == 1
    end
end

if C_PaperDollInfo.GetTemporaryEnchantmentInfo then
    compat.GetTemporaryEnchantmentInfo = C_PaperDollInfo.GetTemporaryEnchantmentInfo
else
    -- GetWeaponEnchantInfo: four values per weapon, main hand first --
    -- has, expirationMs, charges, enchantID (BuffFrame.lua's RETURNS_PER_ITEM).
    compat.GetTemporaryEnchantmentInfo = function(invSlot)
        local offset = invSlot == INVSLOT_OFFHAND and 4 or 0
        local has, expiration, charges, enchantID = select(offset + 1, GetWeaponEnchantInfo())
        if not has then return nil end
        return {
            hasExpirationTime = true,
            remainingTimeMs = expiration,
            chargesRemaining = charges,
            enchantID = enchantID,
        }
    end
end

-- Spellbook --------------------------------------------------------------

if C_SpellBook.GetSpellBookItemInfo then
    compat.GetNumSpellBookSkillLines = C_SpellBook.GetNumSpellBookSkillLines
    compat.GetSpellBookSkillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo
    compat.GetSpellBookItemInfo = C_SpellBook.GetSpellBookItemInfo
else
    local ITEM_TYPE = {
        SPELL = Enum.SpellBookItemType.Spell,
        FUTURESPELL = Enum.SpellBookItemType.FutureSpell,
        PETACTION = Enum.SpellBookItemType.PetAction,
        FLYOUT = Enum.SpellBookItemType.Flyout,
    }

    compat.GetNumSpellBookSkillLines = GetNumSpellTabs

    compat.GetSpellBookSkillLineInfo = function(skillLineIndex)
        local name, iconID, offset, numSlots, isGuild, offSpecID, shouldHide, specID =
            GetSpellTabInfo(skillLineIndex)
        if not name then return nil end
        return {
            name = name,
            iconID = iconID,
            itemIndexOffset = offset,
            numSpellBookItems = numSlots,
            isGuild = isGuild,
            -- 0 there means "not an off-spec line"; retail leaves the field nil.
            offSpecID = offSpecID ~= 0 and offSpecID or nil,
            shouldHide = shouldHide,
            specID = specID,
        }
    end

    -- Retail's `actionID` is the book's own id and `spellID` the active one.
    compat.GetSpellBookItemInfo = function(slot, bank)
        local book = bank == Enum.SpellBookSpellBank.Pet and "pet" or "spell"
        local slotType, id = GetSpellBookItemInfo(slot, book)
        if not slotType then return nil end
        local itemType = ITEM_TYPE[slotType] or Enum.SpellBookItemType.None
        local isSpell = itemType == Enum.SpellBookItemType.Spell
            or itemType == Enum.SpellBookItemType.FutureSpell
        return {
            itemType = itemType,
            actionID = id,
            spellID = isSpell and (C_SpellBook.FindSpellOverrideByID(id) or id) or nil,
            name = GetSpellBookItemName(slot, book),
            iconID = GetSpellBookItemTexture(slot, book),
            isPassive = IsPassiveSpell(slot, book),
            isOffSpec = false,
        }
    end
end

-- Player -----------------------------------------------------------------

compat.GetGlidingInfo = C_PlayerInfo.GetGlidingInfo or function()
    return false, false, 0
end

compat.GetUnitChargedPowerPoints = GetUnitChargedPowerPoints or function()
    return nil
end

-- A talent-tab client (Era, TBC, Wrath) has GetSpecializationRole and throws
-- "API unsupported" from it (user's error report on TBC Anniversary, 2026-10-08;
-- Era and Wrath inferred from the same talent-tab system).  Blizzard calls
-- it only under the ChrSpecialization system (Blizzard_SharedXML/UnitUtil.lua
-- PlayerUtil.IsPlayerEffectivelyTank, classic_era); MoP has real specs and no
-- GetSpecializationSystem, and its own UnitUtil calls it unguarded.
if GetSpecializationSystem then
    compat.GetSpecializationRole = function(specIndex)
        if GetSpecializationSystem() ~= Enum.SpecializationSystem.ChrSpecialization then return nil end
        return GetSpecializationRole(specIndex)
    end
else
    compat.GetSpecializationRole = GetSpecializationRole
end

compat.UnitIsPlayerControlledOrGroupMember = UnitIsPlayerControlledOrGroupMember or function()
    -- LibAuraContainer's emulated identity gate short-circuits on group TOKENS
    -- only (Emulated/Filter.lua CanTestIdentity), so for the "player"/"target"
    -- containers the addon creates, falling through to UnitCanAssist is its answer.
    return false
end

if C_Sound.PlaySoundWithOptions then
    compat.PlaySoundKit = function(soundKitID)
        C_Sound.PlaySoundWithOptions({ soundKitID = soundKitID, uiSoundSubType = "Gameplay SFX" })
    end
else
    compat.PlaySoundKit = function(soundKitID)
        PlaySound(soundKitID, "SFX")
    end
end

-- Cooldown Manager -------------------------------------------------------

-- MoP Classic ships Blizzard_CooldownViewer's source but will not load it
-- (`LoadAddOn` -> WRONG_GAME_TYPE, 2026-10-08), so its frames, alert helpers
-- and sound tables are absent.  `C_CooldownViewer` exists there and is not this.
-- A function, not a flag: it reads the global at call time, never at our load.
compat.HasCooldownManager = function()
    return CooldownViewerSettings ~= nil
end

-- Frames -----------------------------------------------------------------

if UIParent.ResizeToBoundsRect then
    compat.ResizeToBoundsRect = function(frame)
        frame:ResizeToBoundsRect()
    end
else
    -- Nothing is secret there, so Lua may read the bounds the engine would use.
    compat.ResizeToBoundsRect = function(frame)
        local _, _, width, height = frame:GetBoundsRect()
        frame:SetSize(width, height)
    end
end
