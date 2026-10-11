# RacialTracker

Standalone (no CooldownViewer). Displays cooldown icons for the player's active racial abilities (e.g., Blood Fury, Berserking, Stoneform). Spells resolved by name at runtime via `C_Spell.GetSpellInfo()` to handle per-class variants. Horizontal/vertical layout. Glow on cooldown finish. `reverse_swipe` is applied before the cooldown is set, on both the refresh and the OnUpdate transition path — see `Core/IconTracker.md` for why the opposite order reads as dead. Right of TrinketTracker. `GetWantsContentWidth()` → true. `keybind_font` and `duration_font` profiles with anchor_point/offsets control keybind and active cooldown duration text positioning via `ApplyFontProfile`. Hover tooltip via `private.Tooltip.Apply` (`SetSpellByID(spellID)`); `tooltip_mode` default `off`.

Defaults: icon_size 50.

## One `RACIAL_SPELLS` table across clients

Entries are keyed by `UnitRace()` race token and hold a *list* of spellIDs. Two reasons a race
carries more than one, both resolved by the same `C_SpellBook.IsSpellInSpellBook` filter:
per-class variants of one racial (Blood Fury, Arcane Torrent), and **the same racial living
under different IDs on different clients** — Blizzard renumbered several between 1.x and
retail, and each client's data simply lacks the other's ID.

So the table lists both and lets the filter decide. Nothing branches on the client, and an ID
that is wrong for the running client is inert rather than harmful, which is what makes the
list safe to extend additively.

Verified by name lookup in a WoW Forever 1.60.1 client (2026-09-18): Perception `20600`,
Shadowmeld `20580` and Berserking `20554` resolve there; `59752` / `58984` / `26297` do not,
and on retail it is the reverse. `26297` was the *only* Troll entry, so Trolls resolved
nothing at all on that client. Forever carries no TBC-or-later spells (`28880`, `28730`,
`33697` all absent), so the Draenei, Blood Elf and allied-race rows are inert there — correct
as written, not pending work.

**Forever both renumbers and invents**, which is why the 1.x set is not a sufficient source:
*Will to Survive* is `1259718` there against retail's `59752`, and *Elune's Light*,
*Shatter Curse*, *Eureka!*, *Rapid Regeneration* and the entire **Skyborne** set exist in no
retail build at all. Skyborne is a playable Forever race (`ChrRaces` 95 "High Order Skyborne"
/ 96 "Windshaper Skyborne", both `UnitRace` token `Skyborne`) that the table previously had no
row for.

The Forever entries come from that client's own DB2 (build `1.60.1.69913`, 2026-09-18), not
from guesswork: `SkillLine` → `SkillLineAbility` → `SpellName` over the nine racial skill
lines, filtered to spells with a non-zero `SpellCooldowns` recovery and without
`SPELL_ATTR0_PASSIVE`. Passives (Quickness, Hardiness, Touch of the Grave, Big Game Hunter)
and cooldown-less toggles (Find Treasure, Plainsrunning) are deliberately excluded — this
component draws cooldown icons. Recipe and the `?build=` query form are in
`.context/memory/reference_spell_data_lookup.md`.

> The default `wago.tools` endpoint serves **retail**, which has pruned the vanilla-only IDs,
> so a miss there proves nothing about a classic-family client — pass `?build=`. And its
> builds list is not sorted newest-first; reading `[0]` of `wow_classic_beta` yields a 2025
> MoP Classic build and the false conclusion that no Forever dump exists.

**Additional frame routing:** Racial abilities can be assigned to additional frames via the spell dropdown (source key `"Racial"`). Same cross-parent positioning pattern as TrinketTracker. Notifies AF via `OnAddonIconRefresh()` after each refresh.

**Fonts:** a font edit made while hidden waits on a `fontsOwed` latch for the next shown `Refresh`, as in `TrinketTracker.md`.
