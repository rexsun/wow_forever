# Changelog

All notable changes to ClassUIEnhanced are documented here. Newest versions appear first.

## 3.1.0
*October 9th 2026*

### New Features
- The addon now also runs on MoP Classic, TBC Anniversary, Wrath Titan and Classic Era, with potions, flasks, food, weapon oils, poisons, imbues and raid buffs for each version; versions without Blizzard's Cooldown Manager still show your custom spells
- One profile keeps separate custom spell lists for each game version, so the same profile can be shared between them
- The Tracking tab can copy a spell to a second tracker, so it shows on both
- The Tracking tab has a per-spell Alerts menu, starting from the Cooldown Manager's alerts for that spell and saved in your profile
- The Tracking tab can give a single spell its own icon border colour
- The Tracking tab can turn off the active buff display on a cooldown icon for a single spell
- Each tracker's icon order in the Tracking tab is now kept per specialization
- Custom auras can match by name, tracking every rank of a buff, including ranks cast by other players
- Buff icons set to Always Show can glow in a colour of your choice while the aura is missing
- The Buff Tracker can show totems and summons as icons, in front of your buffs
- The Buff Tracker has an experimental option to mix player and target auras in Tracking tab order
- New "No Out of Range Tint" option turns off the red out-of-range tint on cooldown icons
- Spell-type Additional Frames have a colour picker for their ready flash
- WoW Forever: a five-second-rule spark on the mana bar, with a size option
- WoW Forever: Maelstrom Weapon on the secondary resource bar
- WoW Forever: rogue poisons on the consumable buff tracker
- WoW Forever: profiles switch automatically with your dual-spec talent group

### Bug Fixes
- WoW Forever: the global cooldown bar, the instant-cast overlay and the racials' global cooldown hiding now work
- WoW Forever: the Tracking tab's buttons and drag no longer stop responding
- Combo points are read from your target on WoW Forever and the classic versions
- Cooldown icons no longer show the timer of a debuff you cast on yourself or a friendly target
- Divine Purpose tints the filled Holy Power pips again instead of drawing a border around the row
- Totem bars show their countdown again and no longer float away from their anchor, and empty totem slots no longer leave gaps
- Bars anchored to the Buff Tracker follow the buffs actually showing instead of floating a full box above the cooldowns
- Target aura tracking stays correct while you are mind controlled
- The Crusading Strikes swing timer no longer stops after entering a Mythic+ dungeon
- Cooldown Manager aura sounds no longer cause a blocked-action error when your spells change mid-fight
- The changelog window opens on top of the options panel instead of behind it

### Improvements
- Buff trackers build far fewer hidden icons per tracked spell
- The Tracking tab explains the "not on this spec" badge in its tooltip

## 3.0.1
*September 29th 2026*

### New Features
- The Tracking tab has Collapse All and Expand All buttons
- The Tracking tab can move a spell saved by another specialization to a different tracker without switching to that specialization

### Bug Fixes
- Cooldown icons look as they did before 3.0 again: the yellow edge line shows only where it used to, the global cooldown has its dark overlay back, and spells without charges show their cast count again
- An active buff takes over its ability's icon with its own timer again, Hide Cooldown Swipe and Always Desaturate On Cooldown work on it again, and Hide Active Buff Duration is back to off by default so profiles that never changed it get the buff display back
- Buff icon timers sweep in the same direction as Blizzard's again
- Cooldown icons that switch to a buff now show the buff that actually rolled, such as the Roll the Bones outcome, no longer let the ability's icon show through when faded, and can switch to a debuff on your target
- Buff trackers no longer stay empty for a whole fight after attacking straight off a mount
- Hide Cooldown Swipe now also applies to newly shown icons on the Buff Tracker and buff-type Additional Frames
- The spell name on buff bars and bar-type Additional Frames is no longer hidden behind the bar fill when Always Show Tracked Auras is on
- Buff Tracker icons with centre alignment run left to right again, so toggling Always Show Tracked Auras no longer flips their order
- Custom auras that are not spells you know, such as poison debuffs on your target, now show on the buff trackers; each one is tied to the specialization you added it on, with a This Spec checkbox in the Tracking tab
- Cooldown Manager alerts the addon cannot play itself — text-to-speech when a buff is gained or lost, and sounds or text-to-speech on pandemic or a charge gained — now play, by keeping Blizzard's Cooldown Manager running hidden while one is set up
- The Blizzard-style proc glow's opening burst is the right size again and plays before the looping glow instead of on top of it
- The primary resource bar follows switching between a mana specialization and one that hides it without needing a reload
- The Devastation Evoker Unbound Flame bar only shows once you have all four points in Rising Fury
- The consumable tracker counts the fleeting versions of every Midnight potion, not just Light's Potential
- The Additional Frames list in the options scrolls instead of running off the bottom of the window
- The Edit Mode visibility panel's close button no longer floats above other windows

### Improvements
- Choosing whether a tracked aura is watched on you, your target or both now happens on its row in the Tracking tab, and works for every frame, including new ones
- Reduced CPU usage when gaining or losing a target, mounting or dismounting, and entering combat while components have hide rules set up

## 3.0.0
*September 27th 2026*

### New Features
- Rebuilt the cooldown, utility and buff trackers: they now draw their own icons and bars from your Blizzard Cooldown Manager setup, so Blizzard's Cooldown Manager no longer has to stay on screen — the addon offers once to turn it off, and your Cooldown Manager alerts (sounds, text-to-speech and visual flashes) keep playing on the addon's icons
- Added support for patch 12.1.5 and for WoW Forever, including spell ranks, racial abilities for every Forever race, raid buffs at every rank, combo points on your target, and a Weapon Imbues category for Shaman imbues
- New Tracking tab lists the spells of every tracker and Additional Frame in one place: reorder them or drag them between trackers, add or remove spells and items, change icons, set per-spell bar colors and pandemic glow, force a spell Blizzard marks inactive to show, and apply a change to your current specialization or to all of them — it replaces the Icon Overrides tab and the spell lists on the Trackers and Additional Frames tabs
- New Auto-Populate From Cooldown Manager option: turn it off and the trackers show only the spells you add yourself
- Buff trackers can keep a tracked aura's icon on screen while the aura is down, and grey it out until it returns
- The buff bar tracker can show a bar for each totem slot, so summons and totems get a timer
- Proc glows can now be shown on the buff bar tracker and on bar-type Additional Frames
- The trinket tracker recognizes the new patch 12.1 trinkets, and trinkets whose only effect is a stacking buff, with their stack count
- The secondary resource bar can show extra resources in their own rows, with new bars for Frost Mage Shatter, Arcane Mage Arcane Salvo, Demonology Warlock Wild Imps, Devastation Evoker Unbound Flame, Aldrachi Reaver Art of the Glaive, and nearby Soul Fragments for Vengeance, Havoc and Devourer Demon Hunters
- Stack bars can be split into segments or drawn as one fill, with their own color thresholds and an optional pulsing outline
- Devourer Demon Hunters get the nearby-souls overlay and the Collapsing Star marker back on patch 12.1
- The player cast bar follows spell pushback, and a new Pushback Cutaway option shows the progress you lost as a red block that fades away
- The player cast bar can show a latency overlay, and cast bars can show the cast time as elapsed or remaining against the total
- Crit Ebon Might is highlighted again with a glowing border in your crit color, with a new Show Double Time Remaining countdown

### Improvements
- A running buff on a tracked cooldown now shows as a rotating colored edge around the icon, so the cooldown spiral and timer stay visible, and the "while on cooldown" visibility modes follow the cooldown only
- Pandemic and active-aura glows now come from the game itself, so they keep working in combat and on custom spells; the pandemic glow is now a single color, and its urgency colors, thresholds and animated styles were removed
- The Divine Purpose, Lock and Load and Essence Burst highlights no longer need Blizzard's Cooldown Manager, and Divine Purpose now outlines the whole Holy Power bar
- During combat the consumable and raid buff trackers keep a place for every buff, so one that runs out mid-fight reappears in its own slot
- Resetting a profile or copying another one over it now asks for confirmation, and turning off the last Rotation Highlight offers to turn off Blizzard's Assisted Highlight as well
- Additional Frames that follow the cursor now grey out the anchor and offset options that do nothing for them
- Custom spells no longer have Unit and Aura Filter options; a tracked custom aura shows on whichever of you or your target has it
- The Ebon Might Extension Preview and Warn When Extension Will Not Land options are no longer offered on patch 12.1, as the game no longer provides the information they need
- Reduced CPU usage, including when entering and leaving combat and when your bags, action bars, target or spells change

### Bug Fixes
- Fixed a stream of errors from Blizzard's Cooldown Manager that could last until a reload
- Fixed the outbound buff tracker, the Ebon Might duration, the Duplicate timer, Ignore Pain, and the Sweeping Strikes, Teachings of the Monastery and Coup de Grace stack counts going blank or wrong during combat on patch 12.1
- Weapon oils and stones are tracked again on patch 12.1
- Trinket cooldown and buff timers count down smoothly, and Stormbound Emblem of Dazar's haste buff is tracked for its full duration
- Soul Fire casts now preview the incoming Soul Shard, and the Ironfur count no longer stays too high while a Guardian of Elune Ironfur is running
- Frames that inherit their visibility now hide along with the frame they are anchored to, including under mounted, out-of-combat and no-target hide rules
- Changes that wait for combat to end, such as a profile switched mid-fight, now always apply when that fight ends
- A damaged import string is refused before anything changes, imports apply Additional Frames and the Cooldown Manager layout straight away, and a layout-only import no longer creates empty Additional Frames
- Consumable and raid buff trackers: icons faded by a visibility rule no longer stay invisible, a reused button no longer uses the previous item, Hide When Applied no longer leaves an invisible icon taking clicks, flask and food no longer show as missing after dying in an encounter, Show Duration is respected, and the two can no longer be set to follow each other
- The trinket and racial trackers no longer collapse when an entry is sent to an Additional Frame and excluded, consumable countdowns no longer restart on every layout update, and Reverse Swipe works on the racial tracker
- The player health bar's click area matches the bar and leaves no invisible clickable spot behind, toggling Show Shields or Show Healing Prediction no longer hides it, and a disabled health bar no longer blocks clicks
- Button press highlights mark the right icon on vehicle and override bars and no longer flash during pet battles
- Channel tick marks no longer vanish when a channel is clipped, and Evoker cast bars no longer leave extra tick marks
- Edit Mode's Reset Position returns a frame to its default anchor and Reset To Default restores the addon's defaults, free-moving frames no longer jump when their anchor or frame point changes, and a cursor-following Additional Frame keeps following the cursor after being dragged
- Proc and pandemic glow style changes, the cast bar background texture and the Essence Burst color now apply immediately, Death Knights can choose their resource color, and the Colors tab scrolls instead of running off the window
- Width sliders are no longer greyed out where they apply, Edit Mode offers width controls on the global cooldown bar and following buff trackers, and an Additional Frame's Anchor Side greys out when it has no anchor
- Deleting an Additional Frame always deletes the frame you confirmed
- Turning off Hide Inactive Background brings the background back on the global cooldown and player cast bars
- Full-profile exports keep the profile name, and automatic spec profiles no longer skip restoring the Cooldown Manager layout after a manual switch or after being turned off
- Secondary resource threshold colors no longer cause an error in combat, and the Devourer soul count hides along with the resource bar

## 2.13.4
*August 17th 2026*

### New Features
- The consumable tracker now recognizes the three new patch 12.1 potions — Liquid Luster, Alluring Nostrum and Concentrated Silvermoon Health Potion — each with its own toggle

### Improvements
- Reduced CPU and memory use during combat
- Width, Bar Width and Min Width sliders now reach 1000, and anchor offsets ±1000, for wider layouts on high-resolution displays

### Bug Fixes
- Fixed the Holy Power swing timer running too slow after the patch 12.1 Crusading Strikes change
- Fixed cooldown sweeps turning yellow on patch 12.1
- Fixed an error during combat coming from the cooldown trackers on patch 12.1
- Devourer Demon Hunters see their soul fragment count again on patch 12.1; the nearby-souls overlay and the Collapsing Star marker are unavailable there, as the game no longer shares that information with addons
- Fixed the pixel glow style staying invisible on a spell's first proc
- Fixed proc glows showing on top of icons that a visibility setting had hidden
- Fixed a stray rounded border left over hidden icons after switching profiles
- Switching profile during combat no longer produces errors or a half-applied layout
- Fixed the cast bar Text Display option — along with name width, orientation and bar size settings — not taking effect until a reload, and the cast name and time reappearing on the next cast after being turned off
- Fixed icons pulsing when an additional frame reused a tracker's icons
- Fixed a tracker becoming stuck hidden when a custom-tracked spell from another class was set up
- Fixed icons appearing squished on trackers with non-square icon sizes
- Additional frames set to "auto" now hide while mounted, matching the main trackers

## 2.13.3
*July 9th 2026*

### New Features
- Pandemic glow on buff trackers now has adjustable "Appear Below %" and "Urgent Below %" sliders, so you can choose when the border appears and when it turns urgent
- Mistweaver Monks can now show Teachings of the Monastery stacks on the secondary resource bar (optional, off by default)

### Improvements
- Large performance improvement during combat — noticeably lower CPU use, especially in raids
- Added a dedicated anchor point for other addons (such as frame-anchoring tools) to attach to, so anchoring to the trackers no longer freezes them at the wrong size in combat

### Bug Fixes
- Fixed the native cast bar staying visible in combat on some anchor-locked layouts
- Custom resource colors now apply to Maelstrom, Astral Power, and Insanity on the secondary bar
- Resource breakpoint markers now appear correctly on the secondary bar for Elemental Shaman, Balance Druid, and Shadow Priest
- Fixed uneven pandemic glow border thickness and a brief flicker when a heal-over-time was refreshed
- Elements anchored to a component now reposition immediately when that component is hidden or shown by a visibility rule

## 2.13.2
*June 22nd 2026*

### New Features
- The Trinket Tracker now shows equipped proc and passive trinkets — bright when ready, dimmed with a cooldown sweep once they fire, plus an active-buff timer and stack count — with a new "Show Passive Trinkets" toggle to hide them if you prefer

### Improvements
- Elemental Shaman, Balance Druid, and Shadow Priest now show their combat resource (Maelstrom, Astral Power, Insanity) on the secondary bar and mana on the primary bar, matching every other spec; the mana bar auto-hides by default for specs that don't need it, with new per-spec toggles to bring it back when you want it

### Bug Fixes
- Fixed crashes and in-combat errors that could come from the cooldown timers
- Custom-tracked spells now correctly hide on specs where they are replaced by a different spell
- Timer text position is now respected when "Hide Active Buff Duration" is turned on
- Consumable icons routed to a custom tracker (such as a looted Healthstone) now appear right away after bag changes instead of staying invisible
- The "Hide Ready Blink" option now correctly suppresses the end-of-cooldown shine

## 2.13.1
*June 9th 2026*

### New Features
- The consumable tracker now recognizes two more Midnight crafted consumables — Void-Touched Drums and Emergency Soul Link — each shown as its own icon
- Added a standalone "Hide Ready Blink" toggle for Cooldown and Utilities trackers that turns off the end-of-cooldown flash while keeping the icon fully visible

### Bug Fixes
- Fixed a Cooldown Manager bar set to "Hidden" reappearing after a reload or Edit Mode when its matching tracker was turned off
- Fixed custom glows sometimes lingering on screen after a tracker was hidden, such as when switching to a ground mount

## 2.13.0
*May 28th 2026*

### New Features
- Pandemic glow can now shift through three colors as the buff winds down — a fresh color, a mid-life color, and an urgent color near expiry — with separate pickers for each band
- Glow styles for pandemic and proc highlights now include three new looks: an animated ants-trail border, a soft autocast shimmer, and a sharp pixel border, alongside the existing inner and outer border styles

### Improvements
- The glow thickness slider now affects the new pixel and autocast glow styles as well, not just the border styles

## 2.12.0
*May 22nd 2026*

### New Features
- Trackers now show a hover tooltip on mouse-over, with per-component control over when it appears (always, only out of combat, or off) and where it anchors (default, cursor, right of the icon, or above it); tooltips are off by default
- Cooldown and Utilities trackers — and spell-type Additional Frames — gained an icon visibility mode that can hide or fade icons either when they become ready or while they are on cooldown
- The proc glow setting is now a three-way style choice: Blizzard's default glow, a custom colorable border glow with adjustable thickness, or off
- Destruction Warlocks can now display fractional Soul Shard counts as text (for example 3.6) to match the bar fill, via a new opt-in toggle

### Bug Fixes
- Fixed an error that could be thrown on every tracker refresh when a profile used the "None" font outline option
- Fixed a Lua error that could occur when leaving a Mythic+ dungeon in combat with a tracker set to always show
- Fixed buff icons sometimes sticking at Blizzard's default position after targeting yourself
- Cooldown swipe and charge-recharge text hide options now apply correctly to charge spells, including those that gain a buff overlay from talents, and stay hidden across consecutive charge spends

### Improvements
- Tracker visibility settings now take priority over Blizzard's built-in Cooldown Manager visibility; an existing "In Combat Only" choice from Blizzard's Edit Mode is carried over to the tracker's own out-of-combat hide rule
- Glow settings in the options panel are now grouped under clear per-type headings so multi-setting glows are easier to configure

## 2.11.0
*May 13th 2026*

### New Features
- Custom spell entries now have an "Only When Usable" toggle (on by default) so you can opt out per entry to track item-cast spells like Hearthstone and trinkets, or buffs cast on you by other classes like Power Word: Shield and Bloodlust
- Custom cooldown icons now show charge counts for multi-charge spells and remaining-cast counts for resource-driven spells (Monk Expel Harm spheres, Demon Hunter Soul Fragments, reagent spells); custom buff icons now show their aura stack count
- Added a Power Word: Radiance charge bar for Discipline Priests (opt-in, with its own color)
- Added an Essence Burst spender-prediction indicator on the Evoker Essence bar that highlights the segments your next main spender would consume (opt-in, shares its color with the Essence Burst tint)
- Instant-cast spells can now briefly repurpose the player cast bar as a 1.5-second GCD bar with the spell's name and icon (opt-in, with its own color)
- Added a built-in debug log viewer (`/cue log`) with filtering, copy, and save-across-reload support, useful when reporting bugs

### Bug Fixes
- The Raid Buff Tracker's own-buff click now always self-casts, even when you have a friendly target selected
- The instant-cast overlay no longer shows the previous cast's name and no longer collides with the player cast bar's fade-out
- The spell icon on the GCD bar is now sized to match the bar height instead of rendering at its native size
- The classic Healthstone now desaturates and shows its cooldown sweep after use, including during combat
- Augmentation Evoker Essence Burst now correctly highlights two bars instead of three when the Volcanism talent is taken; Preservation Evoker Essence Burst now correctly highlights its bar (Echo was previously missed)
- The Ebon Might crit bar tint no longer fires on specs and talent setups that have no real crit roll, and now stays accurate across deaths and phase changes that shift the alive-DPS count
- Cooldown trackers no longer error during shapeshifts or spec swaps mid-combat
- Cooldown and buff tracker icons no longer appear squished on non-square (taller or wider) icon layouts after using a consumable, swapping an action-bar slot, or other quick refresh events

## 2.10.0
*May 8th 2026*

### New Features
- Added a Custom Spell Tracker so you can pin extra spells onto the cooldown, utilities, buff, and buff-bar trackers — and Additional Frames of those types — by spell ID, including unit and filter choices for aura entries
- Added a Sweeping Strikes secondary resource bar for Arms warriors that shows the remaining cleave stacks, including the extra stacks from Improved Sweeping Strikes
- Added a color picker for the Ebon Might crit bar tint, alongside the existing crit-color toggle
- The "Don't Override Icons on Procs" toggle is now available on the Utilities Tracker as well as the Cooldown Tracker
- Talent-swapped aura variants (such as Death Knight Outbreak's Virulent Plague vs Dread Plague) can now be picked individually in custom buff and Buff Bar Additional Frame dropdowns

### Bug Fixes
- Fixed cooldown icons briefly turning greyscale at the end of the global cooldown and during or between channels
- Fixed a crash when exiting an override, vehicle, or skyriding bar
- Fixed cooldown trackers showing stale keybinds after druid shapeshift or other action-bar page swaps
- Fixed primary trackers set to "Always show" hiding anyway when Blizzard's native cooldown viewer was set to hide out of combat

### Improvements
- The Trackers options tab now scrolls smoothly
- Options-panel rows now highlight on mouse hover

## 2.9.1
*April 30th 2026*

### Bug Fixes
- Fixed several issues with the Paladin Crusading Strikes swing timer — it no longer breaks on weapon swaps or mid-fight reloads, no longer freezes after stepping out of melee range, no longer runs slow with the Zealot's Fervor talent, and now works on locales that use a comma decimal separator
- Fixed several issues with the Devourer Demon Hunter Reap forecast — it no longer overflows past the bar at high soul counts, no longer lags behind Moment of Craving expiring, no longer covers its own threshold markers, no longer lingers after swapping to a different soul-bar spec, and no longer triggers a protected-value error
- Fixed an error spam in Mythic+ from the assisted-combat target highlight
- Fixed a crash from the Warrior Ignore Pain pandemic glow
- Fixed Additional Frames not applying their UI layer setting to icons routed through them
- Fixed cursor-anchored Additional Frames briefly snapping to the screen center during refreshes
- Fixed a load-time warning on the Devourer Demon Hunter soul tracker
- Corrected the in-game description for the Collapsing Star threshold marker

### Improvements
- Trinket, consumable, and racial tracker icons now click through to whatever sits behind them
- The Devourer Reap forecast slab now interpolates smoothly with the soul bar fill instead of snapping in place
- Removed a redundant threshold marker on the Devourer Reap forecast that overlapped the bar's right edge

## 2.9.0
*April 25th 2026*

### New Features
- The Devourer Demon Hunter soul bar now previews how many souls a Reap will consume, shows nearby fragments, and marks the Collapsing Star threshold during Void Metamorphosis
- Added an option to color the player cast bar fill with your class color
- Added an "Icon & Bar (No Name)" layout for bar trackers
- Added a per-tracker option to control which UI layer it sits on
- The Ebon Might bar now turns red when an extension cast will not finish in time to refresh the buff
- Rogue supercharged combo points now show on a dedicated border so the bar fill stays free for class color
- The Ebon Might display keeps showing your active Duplicate count and remaining time after the buff drops
- Bar trackers and bar Additional Frames can now stretch to a percentage of their parent's width

### Bug Fixes
- Fixed the Paladin Crusading Strikes swing timer freezing during cleaves and made it react instantly to mid-swing haste procs
- Fixed the Ebon Might Duplicate count dropping to zero while the buff was still running
- Fixed the keybind font being skipped by the Apply All Fonts button
- Fixed the outbound buff tracker disappearing when every tracked buff was routed to an Additional Frame
- Fixed cooldown icons showing the wrong keybind when an ability was placed directly on a bar instead of through a macro
- Fixed the Vigor bar's Thrill of the Skies color getting stuck on or off through a flight
- Fixed cooldown trackers staying visible after Blizzard's native cooldown viewer hid out of combat
- Fixed cooldown icons showing the wrong keybind when more than one bar slot cast the same spell
- Fixed the Evoker Essence fill rate not accounting for the Innate Magic talent

### Improvements
- The Evoker Essence bar now follows haste procs precisely, including those that fire mid-bar
- Other addons can now anchor to ClassUIEnhanced frames using stable, prefixed names
- Moved the addon icon back to the upper-left of the options panel

## 2.8.4
*April 22nd 2026*

### Bug Fixes
- Fixed a crash caused by Evoker channel cast bar tick marks on Midnight after spell haste became a protected value
- Fixed Mage Frost Icicle stack progress not updating correctly on Midnight after spell haste became a protected value

### Improvements
- Reworked the Evoker Essence bar so it fills smoothly and at the correct rate, including through haste changes mid-bar

## 2.8.3
*April 22nd 2026*

### Bug Fixes
- Fixed the Essence bar not filling correctly on Midnight after the resource regeneration rate became a protected value
- Fixed font choices in the options panel not actually applying when changed

## 2.8.2
*April 22nd 2026*

### New Features
- Added a scale slider to the options panel so you can resize it to taste; `/cue resetoptionspanel` restores the default size and position

### Bug Fixes
- Fixed a Crusading Strikes swing timer error that appeared on Midnight after attack speed became a protected value

## 2.8.1
*April 21st 2026*

### Bug Fixes
- Fixed consumable stack counts not appearing the first time a new consumable entered your bag during a session
- Fixed inherit-visibility trackers staying on screen when a hide rule (like mounted) applied higher up the anchor chain through an auto-hidden parent

## 2.8.0
*April 21st 2026*

### New Features
- Added OutboundBuffTracker, a new tracker for watching buffs you cast on party and raid members — ships with Prescience support for Augmentation Evokers
- Added an option to hide Blizzard's native cooldown viewer so it stays out of the way when ClassUIEnhanced is handling cooldowns
- Added an option to show the Duplicate stack count next to Ebon Might's remaining time

### Bug Fixes
- Fixed Augmentation's Essence Burst highlight always showing 3 bars — Eruption now highlights the right number based on your talents and active effects
- Fixed Ebon Might crit detection breaking on Midnight after player Intellect became a protected value
- Fixed Ebon Might not accounting for Duplicate stacks or Breath of Eons extensions
- Fixed children of free-moving trackers briefly disappearing when the parent emptied out
- Fixed OutboundBuffTracker not updating for party and raid members, and not picking up group changes
- Fixed a crash when opening the OutboundBuffTracker options panel
- Fixed the Edit Mode visibility panel's Show/Hide buttons overlapping the first row
- Fixed free-move and inherit-visibility trackers not honoring their own Hide rules
- Fixed the GCD edge showing incorrectly on available charges when Hide Active Buff Duration was off

### Improvements
- Ebon Might now measures the actual stat gained from Duplicate extensions instead of estimating it

## 2.7.0
*April 18th 2026*

### New Features
- Ebon Might now shows the stat value it grants and highlights crit rolls, so Augmentation Evokers know when to extend
- Casting Eruption, Upheaval, or Fire Breath now previews how much time it will add to Ebon Might
- Mana users now see a cost preview on the resource bar while casting
- Trinkets now stay glowing while ready during a Mythic+ key, matching combat potions
- Added an option to show on-use trinkets and combat potions inside the Cooldown Tracker
- Added a Hide Icon Texture toggle to the buff trackers and buffs-type Additional Frames
- Added a per-tracker option to keep cooldown icons on their base texture instead of swapping to the active buff's icon
- Added an Edge-Only Indicator for No Cooldown Dimming that shows a leading-edge ring instead of the pie sweep
- Added per-spell bar fill colors for bar-type trackers
- Keybind text now resolves for macro-wrapped abilities on ElvUI, Bartender4, Dominos, Neuron, and RazerNaga

### Bug Fixes
- Fixed a GetSpecialization error on Midnight 12.0+
- Fixed free-moving ConsumableBuffTracker and RaidBuffTracker drifting on layout and not switching to free-move from Options
- Fixed secure components showing anchor settings that weren't actually in use
- Fixed Inherit visibility so parent hides propagate and explicit Hidden/Always beats programmatic overrides
- Fixed Skyriding ability bars and Skyriding Vigor disappearing during skyriding
- Fixed /cueperf trace exports dropping the game to a crawl on large profiling windows
- Fixed keybind labels hanging in empty space after skyriding or other hide paths
- Fixed the Show Spark toggle not suppressing the player cast bar spark
- Fixed rank 2 Midnight weapon oils not appearing in the ConsumableBuffTracker bag scan
- Fixed the previous global icon-lock option affecting trackers it shouldn't have
- Fixed stack, charge, and keybind text being hidden under the cooldown swipe
- Fixed RacialTracker, ConsumableTracker, and TrinketTracker drifting on combat transitions
- Fixed bar rows inflating to the hidden icon's height in Name Only and Bar Only layouts
- Fixed cooldown dimming looking darker and flatter than 2.5.0
- Fixed No Cooldown Dimming leaving the cooldown animation invisible — a light golden tint now shows the sweep
- Fixed Ebon Might crit detection misfiring during active Duplicate windows

### Improvements
- Large memory and performance win on heavy profiles — layout refresh no longer runs every frame
- Proc glow animations now fully stop when Hide Proc Glow is on, instead of running invisibly

## 2.6.0
*April 15th 2026*

### New Features
- Added a per-spec toggle for breakpoint pips so you can disable them on individual specs while keeping them enabled elsewhere
- Added per-spec resource threshold colors for secondary resource bars
- Added an Assisted Combat rotation highlight toggle
- Added an Always Desaturate On Cooldown option for trackers that previously only desaturated under specific conditions
- Added X and Y offset settings for icons inside bar-type trackers
- Added a per-tracker color picker for the "ready soon" cooldown flash animation
- Added a persistent potion glow that stays lit once your Mythic+ combat potion is ready, with the Approaching Time slider now reaching 300 seconds to cover the full window

### Bug Fixes
- Fixed the cooldown swipe being replaced by a yellow edge glow on every addon-owned cooldown since 2.5.1
- Fixed "No Cooldown Dimming" not actually removing the dark fill in some configurations
- Fixed icons not desaturating when both the active swipe and dimming overlay were hidden
- Fixed a yellow aura swipe and stale charge-recharge text persisting after a buff dropped
- Fixed taint caused by reading the secret currentCharges field inside the desaturation hook
- Fixed keybind text not shortening on non-English clients (e.g. German "Strg-Umschalt-Maus…")

### Improvements
- Active consumable countdown digits now tick at 0.1s so the seconds no longer visibly skip
- Icons now desaturate while a buff is active with Hide Active Buff Duration on, matching the rest of the cooldown visuals
- Class and spec labels in the addon UI and debug prints are now localized (e.g. "Warrior" instead of "WARRIOR")

## 2.5.1
*April 13th 2026*

### New Features
- Added a bar fill color picker to BuffTrackerBars and Additional Frame bar-type frames
- Added bar color and glow options to Additional Frames so bar-type entries get the same visual controls as icon-type ones
- Extended the Hide Cooldown Swipe toggle to BuffTracker, ConsumableBuffTracker, RaidBuffTracker, and custom Additional Frames
- Added a toggle to hide the keybind text on override and skyriding ability icons without affecting regular CooldownEssential keybinds
- Added desaturation of Trinket, Consumable, and Racial icons while on cooldown

### Bug Fixes
- Fixed a position and font-size jump when the addon-owned cooldown frame handed control back to Blizzard's native cooldown while Hide Active Buff Duration was enabled
- Fixed Summon Demonic Tyrant and similar spells still showing Blizzard's yellow duration swipe with Hide Active Swipe active
- Fixed Brewmaster stagger bar pips and threshold sections persisting and misaligning after the secondary resource bar swapped to Vigor during skyriding
- Fixed a crash when switching glow style from Blizzard to Border on bar-type frames, and removed the unused "proc" marching-ants glow style (existing profiles are migrated automatically)
- Fixed stacked double glow when a spell was routed to an Additional Frame from a source tracker
- Fixed oversized bar glow overlays by tightening their offsets so the halo hugs short bars

### Improvements
- Reorganized the Additional Frames options panel into three purpose-grouped columns (visibility/anchor/size, layout/features/glow, text/font)
- Free-move drag now selects the closest anchor pair across all candidate frame points so saved positions near screen edges no longer drift off-screen on reload
- Active-swipe color is now reset and desaturation is skipped while a spell's buff is active, keeping the icon visually consistent
- The addon-owned cooldown frame now owns the swipe visual from buff start through cooldown end when Hide Active Swipe is enabled

## 2.5.0
*April 12th 2026*

### New Features
- Added a search field to the Additional Frames "Add Spell" dropdown for filtering spells, trinkets, consumables, and racials by name or ID
- Added Marksmanship Hunter Aimed Shot charges as a secondary resource bar with Lock and Load proc coloring
- Added a suite of pandemic glow features: persistent active-aura glow, configurable solid border thickness, and a per-spell glow filter list across all viewer trackers and icon-type additional frames
- Added per-component proc glow customization with independent hide, color, and alpha settings for each tracker
- Added a pandemic glow to the Ignore Pain bar that pulses and recolors during the last 30% of its duration
- Added a Reverse Cooldown Swipe toggle for icon trackers and additional frames
- Added a GCD Edge on Available Charges option that renders the GCD as an edge sweep on charge spells with charges remaining
- Added a Hide Cooldown Swipe toggle for CooldownTracker and UtilitiesTracker
- Added per-class mana bar auto-hide overrides so Protection Paladin, Preservation Evoker, and Guardian Druid can each opt in or out
- Added separate Anchor Point and Frame Point controls in Options and Edit Mode, allowing explicit repositioning without offset recalculation
- Added manual anchor point and frame point controls to the free-moving drag system
- Added a description to the Edit Mode Visibility panel
- Added bag scanning, click-to-use, and item count support for Midnight food items including hearty variants

### Bug Fixes
- Fixed the primary resource bar disappearing after loading screens, when mounted, or when zoning, including crashes from secret values in GetStatusBarColor
- Fixed the Ebon Might resource bar vanishing after dungeon loading screens due to dropped unit event registration and transient spec lookups
- Fixed several pandemic glow crashes on BuffTracker, BuffTrackerBars, and UtilitiesTracker caused by forward-declaration ordering
- Fixed pandemic glow staying visible at all times instead of only below its threshold
- Fixed the free-moving anchor system losing its position across reloads when switching anchor points
- Fixed Hide Charge CD Text and Hide Zero Charges settings not persisting through cooldown updates
- Fixed charge count text briefly flashing "0" on additional frames between layout passes
- Fixed the cooldown swipe edge disappearing when all charges were spent
- Fixed the GCD Edge on Available Charges option applying to the wrong cooldown frame
- Fixed duration and trinket buff timer text rendering below the cooldown swipe on icon trackers
- Fixed Essence Burst coloring not resetting on the rightmost charge and reworked the display so burst bars fill from the first bar with the charging animation shifted behind
- Fixed trinket buff countdown numbers briefly reappearing between update cycles
- Fixed racial icons not displaying in non-English clients by switching from spell names to spell IDs
- Fixed the skyriding override bar showing player class abilities by adding a whitelist of known skyriding spells, and added Lightning Rush to the whitelist
- Fixed mouse button keybind abbreviations failing to match "Mousebutton 5" style text
- Fixed secure frame taint errors when anchored-to-parent secure components were repositioned during combat
- Fixed tracker containers leaving dead space on the right in max-width mode with an explicit icon size
- Fixed bar name text staying hidden after a buff routed to an additional frame expired and the bar was reused
- Fixed Additional Frames created before the glow defaults were added missing their glow customization options in the Options panel
- Fixed missing hide icon, hide zero charges, hide cd text, and no cd overlay options on older spells-type Additional Frames
- Fixed hearty food (e.g. Hearty Royal Roast) not being detected because it grants the "Hearty Well Fed" buff instead of "Well Fed"
- Fixed a secret-number taint crash in UpdateViewerChargeDisplay by using isActive instead of comparing currentCharges

## 2.4.0
*April 5th 2026*

### New Features
- Added spell queue window indicator for the GCD bar, showing a pip where the input window begins
- Added duration text, spell name display, and fill direction options for the GCD bar
- Added option to hide cast bar and GCD bar backgrounds when inactive
- Added option to hide the cast bar spark effect
- Added option to hide icon textures on trackers and additional frames, leaving only cooldown overlays and text visible
- Added option to hide cooldown countdown text on all icon-based trackers and additional frames
- Added option to hide charge count when all charges are depleted
- Added option to hide cooldown text on charge spells that still have remaining charges
- Added item blacklist for Trinket Tracker with drag-and-drop support and per-slot visibility toggles
- Added per-ability toggles for Racial Tracker to hide specific racial cooldowns
- Added alignment setting for Trinket Tracker in Edit Mode
- Added bar content, timer display, and fill-width size mode options for bar-type additional frames
- Added manual anchor point and X/Y offset controls for free-move components
- Added absolute value mode for breakpoint pips, allowing positioning at fixed power values instead of percentages
- Added vehicle and override bar ability display to cooldown trackers with independent toggles for each source
- Added charge count display and keybind labels to skyriding ability frames
- Unusable skyriding spells are now dimmed to match Blizzard action bar style
- Consumable buff tracker is now hidden by default in Mythic+ with an opt-in override setting
- GCD swipe overlay now appears on charge and aura spell icons, matching Blizzard action bar behavior
- Added unreleased changes preview to the in-game changelog for alpha builds

### Bug Fixes
- Fixed glow effects not rendering on icons routed to additional frames
- Fixed cast bar spark option not persisting between consecutive casts
- Fixed charge count and cooldown text options not applying to viewer icons
- Fixed override bar showing placeholder slots with no ability assigned
- Fixed GCD bar showing during cast-time spells and gaps between chain casts
- Fixed GCD bar not triggering for certain spells and chained instant casts
- Fixed cooldown swipe flickering on hidden icons in the anchor chain
- Fixed consumable buff tracker icons remaining visible when their parent was hidden
- Fixed consumable buff tracker reappearing in Mythic+ after dying
- Fixed consumable buff tracker causing action blocked errors during combat
- Fixed wrong flask icon in consumable buff tracker
- Fixed additional frame bar name text flickering on buff activation and in icon-only mode
- Fixed additional frame bars ignoring anchor width percentage and icon space not collapsing when hidden
- Fixed raid buff tracker persisting in Mythic+ and glow flickering on unrelated aura changes
- Fixed icon borders not updating correctly during layout changes
- Fixed GCD bar not inheriting parent width when anchored to another component
- Fixed numpad keybinds displaying full names instead of abbreviations on the override bar
- Fixed errors when accessing override bar charge settings and scanning vehicle bar abilities
- Fixed breakpoint pips options panel crashing when changing certain settings
- Fixed per-component font changes not applying until a UI reload
- Fixed utility icons disappearing in Edit Mode after disabling additional frames
- Fixed skyriding icons flickering when routed to additional frames and ignoring the padding setting
- Fixed skyriding speed text not updating when all vigor charges were full
- Fixed Edit Mode drag snapping back on components with child frames
- Fixed keybinds not resolving for addon action bars (ElvUI, Bartender4, Dominos) and item slots
- Fixed keybind text showing wrong binding for action bars 2-8 and paged action bars
- Fixed position reference anchoring not persisting between sessions
- Fixed hide-when-applied icons leaving gaps in tracker layout and delayed raid buff detection
- Fixed "In Combat Only" visibility mode not sticking after dismounting

### Improvements
- Free-move components now grow from the alignment edge instead of center when icon count changes
- Standardized default font across all components
- Improved layout performance by merging content sizing into a single recursive anchor pass
- Cast bar latency texture now renders below the status bar fill

## 2.3.0
*April 1st 2026*

### New Features
- Added Global Cooldown bar component showing GCD progress after casting, with an optional instant-only mode that hides it during cast-time spells
- Added skyriding ability cooldown tracking — styled icons with keybind labels and cooldown swipes appear automatically while on a skyriding mount
- Added background zone coloring for breakpoint pips with per-pip color picker, auto-hide at threshold, and a toggle to show or hide the pip line
- Added dynamic bar fill color for the primary resource bar that changes based on breakpoint pip thresholds with step or linear interpolation
- Added cursor-follow anchor mode for additional frames that tracks the mouse position in real-time
- Added option to hide channel tick marks on the player cast bar
- Ironfur resource bar now accounts for duration modifiers from Ursoc's Endurance and Guardian of Elune talents

### Bug Fixes
- Fixed consumable buff tracker showing incorrect data during raid combat and Mythic+ by auto-hiding when aura data is unavailable
- Fixed consumable expiring glow causing errors in dungeons and raid combat
- Fixed cooldown icons not appearing greyed out while on cooldown
- Fixed cast bar border disappearing at certain UI scales
- Fixed one-frame flicker on additional frame icons when switching targets
- Fixed disabling an additional frame causing its routed icons to disappear from their source viewers
- Fixed GCD bar disappearing when a spell fails while a previous GCD is still active
- Fixed GCD bar not appearing for channeled and empowered spells
- Fixed GCD bar incorrectly triggering for off-GCD abilities
- Fixed resource bar ignoring fade-out alpha settings
- Fixed breakpoint pip zones not appearing when auto-hide was disabled
- Fixed breakpoint pips options panel crashing when opening settings
- Fixed Ebon Might bar remaining visible while mounted
- Fixed stack count text hidden behind cooldown swipe overlay on icon-based trackers

### Improvements
- Shortened mouse wheel and middle mouse button keybind labels on cooldown icons

## 2.2.2
*March 28th 2026*

### New Features
- Added "No Desaturation" option for Cooldown Tracker, Utilities Tracker, and Additional Frames to keep icons fully colorful while on cooldown

### Bug Fixes
- Fixed secondary resource bar (e.g. icicles) becoming one icon too wide when anchored to another component during spell override transitions
- Fixed Ebon Might bar disappearing on combat entry for Augmentation Evokers
- Fixed charge spells with remaining charges appearing greyed out unnecessarily
- Fixed flask tracking not detecting lower quality ranks and Shattered Sun flask
- Fixed stack overflow when two components referenced each other in position reference chains
- Fixed stack count text rendering behind the cooldown swipe overlay on Additional Frames

### Improvements
- Added duplicate child deduplication for Additional Frames during spell override transitions

## 2.2.1
*March 28th 2026*

### Bug Fixes
- Fixed Stagger bar causing an error on login for Brewmaster Monks

## 2.2.0
*March 28th 2026*

### New Features
- Added optional threshold markers to the Stagger bar showing light, moderate, and heavy stagger zones with colored sections
- Added clickable option for Consumable Buff Tracker and Raid Buff Tracker icons to trigger item use or spell cast
- Added pandemic glow option to Cooldown Tracker and Utilities Tracker with three glow styles and color picker

### Bug Fixes
- Fixed components using position reference not inheriting visibility and alpha from their reference chain
- Fixed tracker icons staying visible after exiting Edit Mode with "In Combat Only" visibility
- Fixed cooldown and buff trackers not initializing when viewers are hidden on login
- Fixed Edit Mode selection anchors becoming stuck when components are disabled
- Fixed charge-based spells not tracking cooldown correctly at zero or one remaining charges
- Fixed Haranir racial ability Thorn Bloom not appearing on Racial Tracker
- Fixed profile switching leaving frames hidden when cooldown viewer visibility is set to "In Combat Only"
- Fixed inconsistent pixel spacing between tracker icons at non-default UI scales
- Fixed circular anchor dependency causing errors when switching profiles
- Fixed addon cooldown overlays remaining visible when their parent viewer was hidden
- Fixed import/export editor overlapping the import button
- Fixed font shadow on addon cooldown timers ignoring outline and zero-offset settings
- Fixed active aura cooldown swipe showing grey instead of golden color

### Improvements
- Reworked Stagger bar to display percentage of max health instead of absolute values
- Replaced deprecated specialization API calls with modern equivalents

## 2.1.0
*March 27th 2026*

### New Features
- Added Consumable Buff Tracker for flask, food, rune, oil, and weapon buff status icons with click-to-use, per-item toggles, item count display, and missing/expiring glow alerts
- Added Raid Buff Tracker for class raid buffs (Arcane Intellect, Battle Shout, Fortitude, Mark of the Wild, Blessing of the Bronze, Skyfury) with click-to-cast and group scan
- Added show-when-casting option for PlayerCastBar that keeps the bar visible during casts regardless of visibility rules
- Added option to suppress icon dimming when a tracked spell is on cooldown
- Added hide-when-applied option for Raid Buff Tracker and Consumable Buff Tracker to fade icons when their buff is active
- Added tooltips on hover to tracked item and buff rows in component options
- Added `/cue version` slash command and made the About tab version info copyable

### Bug Fixes
- Fixed multiple sources of UI taint when cooldown viewers are hidden or set to "only in combat"
- Fixed charge-based spells not showing recharge cooldown timer
- Fixed Raid Buff Tracker not updating glow when the player casts their buff during combat
- Fixed tracker icons staying visible after untracking an entry or when their parent is hidden
- Fixed bar border not applying when toggled on after initial load
- Fixed font shadow appearing as a bold effect when shadow offset is 0/0

### Improvements
- Improved cooldown overlay accuracy with addon-owned cooldown frames instead of modifying Blizzard frames
- Restricted cooldown glows to combat potions only in Consumable Tracker (configurable)
- Cleaned up Consumable Tracker edit mode panel to prevent overflow

## 2.0.0
*March 24th 2026*

### New Features
- Added Frost Mage Icicles secondary resource bar with engine-driven fill animation and hidden 6th timer for Glacial Spike
- Added Guardian Druid Ironfur secondary resource bar with overlapping stack tick marks and cast-based tracking
- Added Protection Warrior Ignore Pain secondary resource bar with absorb stacks and optional time remaining mode
- Added builder prediction overlay for secondary resource bars showing predicted resource gain during cast-time builders (Incinerate, Shadow Bolt, Demonbolt, Arcane Blast)
- Added spend prediction for Warlock Soul Shard resource bars that dims segments during shard-spending casts
- Added Divine Purpose proc tracker for Paladin Holy Power bars that color-shifts filled segments during the proc
- Added overflow border indicator for Crusading Strikes at max Holy Power with swing progress and wasted generation pulse
- Added per-component visibility rules with conditions for mounted, out of combat, and no target — each condition can hide or fade with configurable opacity
- Added automatic per-spec and per-role profile switching with mappings stored globally across profiles
- Added per-component background panels with color, padding, rounded corners, border styles, and six background styles (Dialog, Dialog Gold, Achievement Wood, Chat Bubble, Toast, Party with corner variants)
- Added edit mode frame visibility toggle panel for temporarily hiding components during UI setup
- Added Hidden visibility mode for trackers that keeps hooks and routing active while hiding the main frame
- Added Hide GCD Swipe option for all cooldown components to suppress the dark cooldown flash during the global cooldown
- Added Hide Active Buff Duration with spell cooldown overlay, dark icon effect, and charge recharge timer support
- Added Additional Frames type system with three types (spells, buffs, bar) and dual routing so a spell can appear in both a cooldown and buff tracker simultaneously
- Added full font options to Additional Frames including timer, stacks, name, duration, position controls, and keybind font settings
- Added visibility options to Additional Frames with mode, opacity, conditional rules, and fade
- Added Additional Frames as anchor targets for other components
- Added shield indicator options for target and focus cast bars with independent show/hide, size, and position controls
- Added cast bar background texture option with color tinting
- Added cast bar background color picker to each cast bar component
- Added keybind text shortening for numpad, mouse, gamepad, and special keys
- Added Haranir racial spell Thorn Bloom to the racial tracker
- Added layout alignment option for consumable tracker (left, center, right, top, bottom)
- Added icon offset setting for bar trackers with configurable pixel gap between icon and progress bar
- Added Bar Only (No Name) content mode for bar-type trackers
- Added bar height and icon size as independent settings for bar-type trackers
- Added scroll frame to Additional Frames options panel
- Added performance profiler with flame graph trace viewer accessible via `/cueperf` or minimap button context menu
- Added incoming heal bar overlay texture matching the user's selected status bar texture
- Added viewer hide/show detection that propagates visibility to anchored children
- Added fleeting potion variants (alchemy procs) to consumable tracker
- Added ability routing that is source-aware so racial, trinket, and consumable spells route independently from the same spell in cooldown viewers
- Added Essential and Utility spells to bar-type Additional Frame spell dropdown
- Added consolidated buff list to bar-type Additional Frames spell dropdown showing both BuffIcon and BuffBar sources
- Added split horizontal and vertical padding sliders for component backgrounds

### Bug Fixes
- Fixed C stack overflow from unbounded hook accumulation when Layout hooks failed to register their guard correctly
- Fixed CooldownViewer taint from button press overlay writing directly to protected frame tables
- Fixed CooldownManager not restoring after hiding the UI with Alt+Z, barber, or trading post
- Fixed components not re-showing after pet battle ends due to stale visibility state
- Fixed "Always" visibility mode inheriting parent fade and opacity instead of being independent
- Fixed anchored children detaching when their parent hides during mounted or combat transitions
- Fixed vigor bar appearing after dismounting a ride-along mount
- Fixed swipe suppression state transitions losing CooldownFrame alpha across GCD, aura, and charge recharge states
- Fixed Hide GCD and Hide Active Buff Duration toggles not applying and flickering in raids
- Fixed icon overrides briefly reverting on target switch before being re-applied
- Fixed swipe animation jitter from repeated cooldown override calls fighting Blizzard's timer
- Fixed charge recharge timers hidden by Hide Active Buff Duration
- Fixed Demonology and Affliction soul shard bars showing fractional fill from raw fragment counts
- Fixed Additional Frames not honoring hidden visibility mode when source component was also hidden
- Fixed Additional Frame icons jumping on initial load before viewers finished populating
- Fixed Additional Frames not showing until disable/enable cycle after adding spells
- Fixed AF-routed buff icons not appearing until combat ends when the primary tracker was disabled
- Fixed AF-routed icons snapping back to main tracker on aura updates
- Fixed buff icons routed to Additional Frames snapping back to bar position
- Fixed new Additional Frames not appearing and showing stale EditMode names
- Fixed Additional Frames enable/disable not working due to incorrect settings lookup
- Fixed edit mode Hide All not hiding disabled components
- Fixed visibility rules not restored from older profiles or imports that stored boolean values
- Fixed bar content setting not persisting and bleeding across additional frames
- Fixed bar-type bar fill not matching icon height due to hardcoded vertical padding
- Fixed bar borders not applied to bar-type additional frames
- Fixed buff tracker bar text rendering behind the border overlay
- Fixed cast bar icon slightly taller than bar in horizontal mode
- Fixed cast bar background color having no visible effect due to solid black overlay
- Fixed cast bar snapping to inflated parent width on anchor refresh in overflow mode
- Fixed cast bar snapping to oversized width when anchored to tracker group
- Fixed border edge 1px misalignment on some resolutions from disabled pixel grid snapping
- Fixed 1px centering error with odd icon offsets from unnecessary floor rounding
- Fixed sub-pixel icon positioning causing border bleed at half-pixel boundaries
- Fixed background roundness slider being inverted and crashing at max value
- Fixed component background rendering above icons instead of behind
- Fixed unclickable background and keybind toggles when switching between tracker components
- Fixed BuildMenuVolatile checkboxes not visually updating on click
- Fixed Ignore Pain time bar toggle staying disabled after toggling parent off and back on
- Fixed ConsumableTracker growing centered in free anchor mode instead of expanding from the alignment edge
- Fixed ConsumableTracker causing ~162 KB/s memory growth at idle from repeated bag scanning
- Fixed racial spells showing as untracked in Additional Frame spell list
- Fixed gamepad keybinds displaying as raw atlas escape text
- Fixed icon offset of zero still leaving a gap in viewer-based components
- Fixed nil crash in Anchoring when importing older profiles with missing additional frame settings
- Fixed import confirmation UI overlap and edit box not clearing after import
- Fixed general settings (borders, proc glow, icon zoom, aspect ratio, resource colors) not included in profile export
- Fixed options panels not refreshing after profile import
- Fixed viewer layout not updating on child visibility changes from multiple code paths
- Fixed cross-column refresh not working in Colors and General tab option panels
- Fixed secret boolean error from IsDesaturated() in GCD swipe suppression
- Fixed CDM layout not restoring after queue-based spec swap via dungeon or PvP queue
- Fixed circular anchor dependencies from corrupted saved profiles causing layout errors
- Fixed external anchors registered after initialization leaving components orphaned
- Fixed buff duration text re-showing when show_timer is off after bar recycling
- Fixed Hidden visibility for components and Additional Frames using incorrect alpha cascading
- Fixed health gradient evaluating against max health plus absorbs instead of actual health percentage
- Fixed auto-hide setting being shared between PrimaryResources and ConsumableTracker
- Fixed spell routing not rebuilding when cooldown viewer spell overrides change
- Fixed CDM viewer hooks fighting other addons when all CUE components are disabled
- Fixed mounting overriding user's visibility setting instead of respecting configured mode
- Fixed Additional Frames font settings from parent components overwriting custom tracker fonts
- Fixed buff bar name text overflowing the bar width on long spell names
- Fixed shield absorb bar not adapting to DetailsFramework one-sided anchoring change
- Fixed bar width stretching to full width when icon is hidden in Bar Only mode
- Fixed deprecated API usage in RacialTracker from external commit
- Fixed dropdown menus extending past the visible scroll area in options panel
- Compatibility fix for 12.0.1.66562 secret and cooldown API changes

### Improvements
- Reduced combat memory allocations by coalescing per-event layout processing into once-per-frame passes
- Added pass-scoped caching for keybind lookups, icon border application, and inherited width computation
- Added visibility-only fast path for target changes, skipping unnecessary repositioning
- Throttled pandemic overlay hook to reduce combat memory growth from per-frame allocations
- Coalesced swipe watcher, viewer layout callbacks, and deferred refreshes to reduce redundant layout passes
- Skipped redundant font application, bag scans, bar borders, and keybind text on transient refreshes
- Eliminated per-call table allocations in DK rune sort and hoisted swing timer closures
- Cached visibility state per layout pass to eliminate redundant game API calls
- Deferred viewer hook refreshes for Essence Burst and Coup de Grâce to once per frame
- Cast bar spark now auto-adjusts height to match the bar size
- Cast bar border now spans the icon when the icon is visible
- Auto-hide mana bar for Guardian Druids outside Bear Form
- Ironfur bar hides outside Bear Form and falls through to combo points in Cat Form
- Rewrote CooldownLayoutSync to per-class storage with dirty tracking, removing redundant restores
- Queue-based spec swaps via dungeon finder are now detected and handled correctly
- Options panel now renders above cooldown manager frames in edit mode
- Reduced out-of-combat CPU usage in pandemic glow and Divine Purpose hooks
- Updated DetailsFramework to version 699

## 1.10.0
*March 11th 2026*

### New Features
- Added Maelstrom Weapon stack tracking for Enhancement Shamans with optional highlight at 5+ stacks
- Added Coup de Grâce stack tracking pips on combo points for Rogue Trickster
- Added bar smoothing option for resource and health bars with smooth animated transitions
- Added pandemic glow style selection with three styles (ripple, solid pulse, marching ants) and color customization
- Added a Cooldown Manager Settings button to the options panel for quick access to Blizzard's cooldown settings
- Added width percentage and size mode options to Additional Frames for more flexible layouts
- Spells moved between categories in Cooldown Settings now appear correctly in the spell dropdown

### Bug Fixes
- Fixed font color option not being applied to icon tracker timer and stack count text
- Fixed max icons per row mode incorrectly being limited by the max width setting
- Fixed proc glow animation having a visible size jump between flash and pulse phases
- Fixed 1px height mismatch on the last secondary resource bar segment
- Fixed static background color ignoring the custom color and using class color instead
- Fixed custom resource colors not applying for vigor, DK runes, and other special power types
- Fixed last resource bar segment having incorrect size due to anchor-based height calculation
- Fixed secondary resource bar text rendering behind borders
- Fixed icon opacity not respecting the component transparency setting
- Fixed Additional Frames alpha handling for owned child icons

### Improvements
- Improved resource color and event handling during spec changes and power type transitions

## 1.9.2
*March 10th 2026*

### New Features
- Added color customization for all secondary resource bar types including DK runes, Monk stagger, Soul Fragments, and more
- Added font color option to all component text elements
- Added font shadow color and offset options with automatic disabling when outline is active
- Added border thickness option for bar and icon borders
- Added bar spacing option for secondary resource bars
- Added anchor, layout, and size settings to the additional frames options panel

### Bug Fixes
- Fixed icon and bar borders not hiding when their parent component is hidden via the alpha chain
- Fixed pandemic glow sometimes rendering behind icon borders
- Fixed cooldown manager layouts being auto-saved on every login or reload instead of only on explicit user action

### Improvements
- Stopped suppressing Blizzard visual alerts on buff icons so custom alert preferences are respected
- Moved per-resource color options to the Colors tab for better organization

## 1.9.1
*March 10th 2026*

### New Features
- Added color customization for all secondary resource bar types including DK runes, Monk stagger, Soul Fragments, and more
- Added font color option to all component text elements
- Added font shadow color and offset options with automatic disabling when outline is active
- Added border thickness option for bar and icon borders
- Added bar spacing option for secondary resource bars
- Added anchor, layout, and size settings to the additional frames options panel

### Bug Fixes
- Fixed pandemic glow sometimes rendering behind icon borders
- Fixed cooldown manager layouts being auto-saved on every login or reload instead of only on explicit user action

### Improvements
- Stopped suppressing Blizzard visual alerts on buff icons so custom alert preferences are respected
- Moved per-resource color options to the Colors tab for better organization

## 1.9.0
*March 9th 2026*

### New Features
- Added Vitality (Aspect of Harmony) tracking for Brewmaster and Mistweaver Monks as a secondary resource bar
- Added Tip of the Spear stack tracking for Survival Hunters as a secondary resource bar
- Added button press overlay for tracker icons that mirrors the action bar push effect when pressing keybinds
- Added layout settings panel for additional frames with icon size, height, spacing, direction, and alignment options
- Added spell name max width option for cast bars to truncate long spell names with ellipsis
- Added inside/outside border toggle for component borders
- Added dedicated Colors tab in options for cast bar, health gradient, and resource color settings
- Added show/hide spell icon option for cast bars
- Added icon height override for cast bar spell icons, consumable tracker, trinket tracker, and racial tracker

### Bug Fixes
- Fixed cast bar spell icon reappearing after each cast when hidden
- Fixed pandemic glow appearing on permanent buffs with no duration
- Fixed component position shifting when its anchor parent was hidden by Blizzard
- Fixed text being clipped by borders from adjacent components
- Fixed border sub-options not updating when toggling the show border setting
- Fixed dragging a cooldown viewer in EditMode moving the addon component instead
- Fixed layout sync showing false mismatches and popup dismissing itself on spec change
- Fixed options tabs not refreshing when switching profiles
- Fixed EditMode slider errors when profile values were missing
- Fixed override spells not being recognized in additional frame routing

### Improvements
- Layout sync now silently restores layouts on login, spec change, and profile change instead of prompting
- Replaced Blizzard's pandemic glow with a more reliable addon-owned overlay for accurate timing
- Buff bar spells now appear in the additional frame icon spell dropdown
- Spell cast events for secondary resources now use unit events for better performance
- Moved breakpoint pip options to a better position in primary resource settings

## 1.8.0
*March 9th 2026*

### New Features
- Added Racial Tracker component for tracking racial ability cooldowns with auto-detection
- Added Icon Overrides feature for replacing any spell icon across all trackers with a searchable icon picker
- Added vertical orientation support for all bar components (health, cast, resources)
- Added inherited opacity setting for all components with anchor chain inheritance
- Added text hiding options for cast bars, health bar, and primary resources
- Added Essence Burst color shift for Evoker Essence bars, highlighting the spender cost
- Added interactable option for the Player Health Bar with left-click targeting and right-click menu
- Added Auto visibility mode that follows Blizzard's cooldown viewer availability
- Added Fire Blast charge recharge fill animation for Fire Mage secondary resource bar
- Added icon height override for non-square tracker icons
- Added custom fill color option for Crusading Strikes swing timer
- Added option to hide active buff duration overlay on cooldown tracker icons
- Added Preserve Aspect Ratio option to prevent icon stretching in non-square layouts
- Added trinket and consumable routing to Additional Frames
- Added size mode support for vertical tracker layouts

### Bug Fixes
- Fixed all dropdown options not saving their selected value until the next reload
- Fixed components not hiding during skyriding
- Fixed Demonic Healthstone charges and cooldown not tracking correctly
- Fixed icon overrides flickering on buff and debuff stack changes
- Fixed buff tracker bar height option having no visible effect
- Fixed buff tracker bar icon size not applying until reload
- Fixed overflow icons ignoring icon height setting
- Fixed vertical trackers ignoring alignment on left/right sides
- Fixed bar tracker alignment options not matching layout orientation
- Fixed EditMode settings becoming tainted after selecting addon components
- Fixed interactable click overlay causing errors during combat
- Fixed Mass Disintegrate glow not hiding when clipping into a new channel
- Fixed errors from secret number values in spell cooldown handling
- Fixed options panel crashing when reopened

### Improvements
- Druid travel forms are now recognized as mounted for Hide When Mounted
- Added missing bonus and stance bar slots to keybind text lookup
- When active buff duration is hidden, the real spell cooldown is shown instead

## 1.7.0
*March 6th 2026*

### New Features
- Added Improved Whirlwind charge tracking for Fury Warriors, showing charge segments on the secondary resource bar
- Added Crusading Strikes swing timer for Retribution Paladins, gradually filling the next Holy Power segment as the auto-attack progresses
- Added Fire Blast charge segments for Fire Mages on the secondary resource bar
- Added Mass Disintegrate glow for Scalecommander Evokers, showing a pulsing border on the cast bar when channeling Disintegrate with charges available

### Bug Fixes
- Fixed components and skyriding vigour showing during client scenes after a reload
- Fixed hide-when-mounted staying active after entering delves
- Fixed tracker containers keeping incorrect width on reload when using max-per-row mode

### Improvements
- Replaced deprecated Blizzard APIs with their modern equivalents for forward compatibility

## 1.6.2
*March 6th 2026*

### New Features
- Added optional border setting for tracker icons with configurable color

### Bug Fixes
- Fixed vigor bar not appearing on login or reload while mounted
- Fixed options panel error when opening component settings
- Fixed secondary resource bar showing on ground mounts instead of only skyriding mounts
- Fixed icon spacing being uneven at certain UI scales
- Fixed tracker container width flickering when anchored to a parent with inherited width
- Fixed consumable tracker icons filling toward the anchor instead of away from it
- Fixed corner-anchored components not detecting vertical mode correctly
- Fixed additional frame icons appearing misaligned in overflow mode

### Improvements
- Hide-when-mounted mode now also hides during flight paths, pet battles, minigames, and client scenes
- Overflow mode now fits as many icons as the width allows, ignoring the max-per-row setting
- Class-specific resource options are now visible for all classes
- Fixed option sub-toggles not visually updating when their parent toggle changes

## 1.6.1
*March 5th 2026*

### Bug Fixes
- Fixed texture dropdown not applying the selected texture to bars
- Fixed texture dropdown in Edit Mode growing off-screen when many textures are installed

## 1.6.0
*March 5th 2026*

### New Features
- Added Skyriding Vigor tracking with charge display and flight speed readout while mounted
- Added Brewmaster Monk Stagger tracking on the secondary resource bar
- Added Demon Hunter Soul Fragment tracking with Vengeance segment and Devourer fill modes
- Added Ebon Might duration bar for Augmentation Evokers on the primary resource bar
- Added configurable breakpoint pips on the primary resource bar for marking power thresholds
- Added rune sorting option for Death Knights, grouping ready runes on the left
- Added bar texture selection for primary and secondary resource bars
- Added bulk texture editor to apply a single texture across all bar components at once
- Added font anchor and position controls for timer, stacks, name, and duration texts on all tracker components
- Added three fixed-width icon layout modes: Fixed Width, Spread, and Stretch
- Added minimum width option for tracker containers using Max Per Row or vertical layouts

### Bug Fixes
- Fixed Stagger toggle not taking effect until a reload
- Fixed secondary resource bar not updating on spec change
- Fixed rune count text not updating when the last rune finished filling
- Fixed keybind text overlays rendering above unrelated UI elements
- Fixed Druid combo points showing for non-Feral specs by default

### Improvements
- Restructured the options panel from 7 tabs to 6 with a unified Trackers tab and component sidebar
- Tracker icons now respect their parent component's width, preventing overflow
- Consumable family names are now localized automatically instead of using hardcoded English text
- Shortened mouse button keybind labels (e.g. "Mouse Button 4" to "mb4")
- Fonts and textures now re-apply correctly when other addons register media late
- Improved pixel-perfect rendering at non-100% UI scales
- Updated DetailsFramework library

## 1.5.0
*March 4th 2026*

### New Features
- Added keybind text overlay on cooldown, tracker, and additional icon frames showing the keyboard shortcut for each spell
- Added shields and healing prediction toggles for the health bar
- Added tradeskill casts (cooking, blacksmithing, etc.) to the cast bar
- Added font position controls with anchor point and X/Y offset for all addon-owned text elements

### Bug Fixes
- Fixed components not hiding during vehicle encounters when "hide when mounted" was enabled
- Fixed active buff glow not working on non-English clients
- Fixed Edit Mode crash when switching profiles with additional frames
- Fixed width-based anchoring showing distorted sizes in Edit Mode
- Fixed cast bar not appearing when becoming visible during an active cast
- Fixed infinite loop when components toggled visibility during layout
- Fixed errors caused by tainted addon code running during Edit Mode exit

### Improvements
- Reworked the Fonts tab with a scrollable layout, component headings, and balanced columns
- Moved keybind text toggle from Options to Edit Mode for quicker access
- Updated DetailsFramework library

## 1.4.0
*March 3rd 2026*

### New Features
- Added active buff glow for trinkets and combat potions, showing a pulsing border and countdown while the effect is active
- Added optional resource value text overlay for secondary resources, configurable via Edit Mode and the Fonts tab
- Added minimap icon visibility toggle in General options and via `/cue minimap`

## 1.3.1
*March 3rd 2026*

### Bug Fixes
- Fixed components not being movable in Edit Mode after selecting them

## 1.3.0
*March 3rd 2026*

### New Features
- Added Additional Frames for creating custom spell tracking layouts with independent positioning, sizing, and growth direction
- Added per-component visibility options — choose between Inherit, Always, Hide When Mounted, or Only In Combat
- Added layout direction, alignment, and corner anchor options for icon and bar trackers
- Added block direction option for Consumable Tracker
- Components now auto-detach from their anchor when dragged far enough in Edit Mode

### Bug Fixes
- Fixed shield icon appearing on non-interruptible casts
- Fixed inconsistent spacing between secondary resource bars
- Fixed cast bar border causing errors during combat
- Fixed Consumable Tracker auto-hide tooltip showing the wrong description
- Fixed delayed icon positioning after aura changes during combat
- Fixed target and focus cast bars not updating on unit change
- Fixed Edit Mode component selection sometimes causing errors

### Improvements
- Improved locale string compatibility across different client languages

## 1.2.1
*March 2nd 2026*

### New Features
- Added a Changelog button to the About tab showing the full release history

### Bug Fixes
- Fixed bar text sometimes rendering behind the border overlay
- Fixed target and focus cast bars not updating when changing targets

## 1.2.0
*March 2nd 2026*

### New Features
- Added configurable text format for the primary resource bar — choose between percentage, abbreviated value, or both, with separate settings for mana and other resources
- Added customizable background colors for health bar, primary resource bar, and secondary resource bars
- Added color override for primary resource bar with per-power-type color pickers
- Added optional border around health, resource, and cast bars with configurable color
- Added independent X and Y anchor offsets for precise two-axis positioning
- Added width mode toggle — anchored components can now use a fixed pixel width instead of scaling from their parent
- Added a dedicated Colors tab in the options panel, consolidating all color settings in one place
- Added a dedicated Fonts tab in the options panel with per-component font settings, moved out of Edit Mode
- Blizzard's native Edit Mode settings now appear alongside the addon dialog when selecting a tracker component

### Bug Fixes
- Fixed class color pickers being disabled at the wrong time
- Fixed target and focus cast bars not updating when switching targets during an in-progress cast
- Fixed tracker containers remaining visible after disabling a component in Edit Mode
- Fixed anchor chain not refreshing during combat when a tracker became visible
- Fixed trackers sometimes becoming invisible when disabled by other addons

### Improvements
- Disabled tracker components are now visible and repositionable in Edit Mode
- Inapplicable Edit Mode settings are now hidden instead of greyed out
- External anchor points registered after initialization now appear in the anchor dropdown

## 1.1.1
*March 1st 2026*

### Improvements
- Components now show live previews in Edit Mode — health bar displays real health data, cast bars show a dummy cast, and resource bars show real resource values
- Empty trackers now remain visible in Edit Mode with a minimum size, making them easier to find and reposition
- Target and focus cast bars now default to the top-middle of the screen instead of below the player cast bar

## 1.1.0
*February 28th 2026*

### New Features
- Added Player Health Bar with class color or health gradient modes, heal prediction, and shield absorption
- Added Buff Tracker Bars component for bar-based buff tracking with configurable width, height, spacing, and growth direction
- Added icon zoom option to crop default icon border edges for a cleaner look
- Added version and build info to the options About tab

### Bug Fixes
- Fixed cast bars showing the wrong texture and colors when their anchor was hidden at login
- Fixed components causing errors during combat from tainted CooldownViewer interactions

### Improvements
- Consumable icons now show next to each category toggle in the options panel
- Resource color pickers are now disabled when "Use Class Color" is turned on
- Setting tooltips now preview the visual change directly
- Import now defaults to "import as new profile" when the source profile name differs from the current one
- Added Potent Healing Potion to the health potion tracking list
- Improved import button styling

## 1.0.2
*February 27th 2026*

### New Features
- Added spec-aware secondary resources with an arcane mana bar option for Mage

### Bug Fixes
- Fixed components causing "addon blocked" errors during combat
- Fixed icon rows only showing one icon per row
- Fixed anchor chain breaking when a parent component was disabled or unavailable

### Improvements
- Component position is now preserved when switching to free-moving mode
- Added "Class Specific Tweaks" section header in options panel for better organization

## 1.0.1
*February 26th 2026*

### New Features
- External anchor registration API for other addons to integrate with ClassUIEnhanced

### Bug Fixes
- Fixed icon centering when using non-default Edit Mode icon size settings
- Fixed errors when exiting Edit Mode caused by system override conflicts
- Fixed addon blocked errors during combat when repositioning frames
- Fixed Edit Mode width slider not reaching the default width on wider components

### Improvements
- Blizzard CooldownViewer position is now captured on first profile load, preserving any existing Edit Mode placement

## 1.0.0
*February 26th 2026*

Initial release.

### Features
- **Cast Bars** — Player, target, and focus cast bars with channeled spell tick marks and haste-adjusted positioning
- **Cooldown Tracker** — Tracks essential cooldowns with multi-row icon layout
- **Buff Tracker** — Tracks active buffs with configurable icon sizes
- **Utilities Tracker** — Tracks utility cooldowns separately
- **Trinket Tracker** — Dedicated on-use trinket cooldown tracking
- **Consumable Tracker** — Combat potions, health potions, mana potions, and healthstones with category-based best-only logic
- **Primary Resources** — Class resource bar (mana, energy, rage, etc.)
- **Secondary Resources** — Combo points, runes, chi, arcane charges, etc. with animated fills
- **Glow Effects** — Marching ants, approaching-ready border glow, low health alerts, and pandemic glow
- **Edit Mode Integration** — Full Blizzard Edit Mode support with per-component settings panels
- **Per-Spec Layouts** — Automatic CooldownViewer layout sync per specialization
- **Profile System** — Full profile management with partial import/export and Wago integration
- **Options Panel** — General settings, cast bar colors, font customization, and About tab
- **Localization** — Framework with enUS base and stubs for all WoW locales
