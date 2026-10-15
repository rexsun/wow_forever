# WoW: Forever add-ons

Updated 2026-10-14 for client 1.60.1.70374 / Interface 16001. Twelve active upstream addon folders are installed, plus the local OverlapSettingsGuard. YUI carries the two local portable-font references documented below; all other upstream folders remain unmodified. EllesmereUI owns individual frames, group frames and nameplates; YUI supplies the remaining interface features. Live WTF settings were preserved byte-for-byte during the upgrade.

| Package | Version | Purpose and source |
| --- | --- | --- |
| YUI | v341 | Integrated action bars, HUD, maps/minimap, chat, equipment, mail/merchant and combat helpers. [Forever download listing](https://www.wclbox.com/games/1/PluginItem/17520?version=9). TOC includes Interface 16001 and a camelot load path. The source lists 2026-10-15; its Forever archive was available and installed on 2026-10-14 local time. |
| RestedXP Guides | v4.11.23 | Leveling routes, guide steps, navigation and optional automation. [Official release](https://github.com/RestedXP/RXPGuides/releases/tag/v4.11.23). TOC includes Interface 16001 and Forever-specific data/guides. |
| Auctionator | 341 | Auction shopping, selling and price information. [Release](https://www.curseforge.com/wow/addons/auctionator/files/9162359), 2026-10-13; includes Interface 16001. |
| DungeonsForever | 1.8.6 | Forever dungeon, loot, collection, gear-library, reputation and profession reference with navigation helpers. [Release](https://www.curseforge.com/wow/addons/dungeonsforever/files/9159550), 2026-10-13; includes Interface 16001. |
| TalentsForeverBook | 0.38.2 (beta) | Talent planner, builds and optional automatic talent application/trainer alerts. [Release](https://www.curseforge.com/wow/addons/talents-forever/files/9173330), 2026-10-14; Interface 16001. Upstream now uses regular Cinzel without a local patch. |
| !BugGrabber | v12.1.0 | Captures Lua errors in BugGrabberDB; `/buggrabber 1` prints a captured error. [Release](https://www.curseforge.com/wow/addons/bug-grabber/files/8907587), 2026-09-17; includes Interface 16001. |
| EllesmereUI | 9.5.5 | Shared framework for the selected modules. [Suite release](https://www.curseforge.com/wow/addons/ellesmereui/files/9182709), 2026-10-14; Interface 16001. |
| EllesmereUIUnitFrames | 9.5.5 | Player, target, focus, pet and boss frames. Same suite release; player and target enabled, player castbar retained. |
| EllesmereUIRaidFrames | 9.5.5 | Party and raid frames. Same suite release; all eight raid groups enabled. |
| EllesmereUINameplates | 9.5.5 | Nameplates and cast/aura displays. Same suite release; nameplate class power kept off by the guard. |
| EllesmereUIOptions | 9.5.5 | Required load-on-demand options panels. Same suite release. |
| EllesmereUILocales | 9.5.5 | Load-on-demand translations, including the current zhTW locale. Same suite release. |
| OverlapSettingsGuard | 0.6.0 | Local addon restored from ClassUI and extended for YUI/EllesmereUI. Keeps competing settings off, including YUI player health/cast displays; reports changes and reload reminders in chat without popups, applies ten startup CVars individually in order, and exposes `/osg`. [Policy and ownership table](OverlapSettingsGuard/readme.md). Interface 16001. |

All prior addon folders, including OverlapSettingsGuard, were removed during the initial trial. WTF was deleted at the user's request with no new backup, and has since been recreated by the game. ClassUI preserves the previous tracked bundle; WTF is excluded from Git.

## Potential overlaps

- Quest acceptance, turn-ins, rewards and gossip: YUI owns automation; OverlapSettingsGuard keeps competing RXPGuides automation off. Enable/disable these actions in YUI as desired.
- Junk selling: YUI owns it; OverlapSettingsGuard keeps RXPGuides autoSellJunk off.
- Quest items: YUI offers a quest-item action bar and RXPGuides offers its active-item window. Select one display if duplicates appear.
- Experience statistics: YUI's experience bar and RXPGuides leveling tracker provide overlapping statistics; select the displays you want.
- Map pins/navigation: YUI location markers coexist with RXPGuides route pins; verify that the map and waypoint displays remain readable.

- Talent guidance: TalentsForeverBook owns it; OverlapSettingsGuard keeps RXPGuides talent guides off. TalentsForeverBook's general autoApply defaults off; review its starter option before using automatic spending.
- Navigation: DungeonsForever and RXPGuides can provide competing directions; use one active route at a time. Auctionator and BugGrabber have no active replacement counterpart in YUI's Forever loader.

Frame ownership is configured through saved settings: YUI's nameplateOutline and syncFriendlyNameplates are off. YHUD mana, rage, energy and combo-point displays are disabled for all nine Forever classes, including stored druid form overrides and the saved HUD configuration set; swing timers and cooldown tracking are retained. EllesmereUI owns these frame/resource displays. Its upstream code suppresses the Blizzard frames it replaces, while its nameplate class-power display defaults off to avoid duplicating the unit-frame display.

OverlapSettingsGuard 0.6.0 enforces the nameplate/resource ownership above across profiles and stored HUD configurations. It also locks off YUI's new player health/cast selections, dedicated cast-only HUD groups and native castbar suppression, plus EllesmereUI's nameplate class-power display while its unit frames are loaded, and enforces the RestedXP automation/talent rules. Changes wait until combat ends; `/osg` reports locked-off, inactive and blocked rules. Only the documented YUI font references modify upstream source. Layout positions, map/navigation choices and optional statistics remain user-adjustable. The previous pack's player/target frames, group frames, nameplates and RestedXP arrow were reported working in-game; the upgraded pack and appearance at all three resolutions still need visual validation.

## YUI frame investigation

- Individual frames: checked in the downloaded v341 archive, `Products/YUnitFrames/!load_Forever.xml` exists but is not reachable from `YUI_Load_Forever.xml`. Its runtime registers the product, settings and `/yuf` command, so these are unavailable. It covers player, target, focus, pet, target-of-target, focus-of-target, boss frames and player castbar, not party/raid groups. Its source baseline is build 1.60.1.70009; enabling it on the installed build needs live verification. Prefer an upstream supported release. A loader include is a possible local experiment, not a settings-only fix; none was applied. The newly loaded YHUD health and cast resources target only the player.
- Party/raid: no YUI replacement group-frame implementation was found. EllesmereUI Raid Frames now provides them.
- Nameplates: YUI's preset selector requires loaded Platynator and an imported YUI profile; neither is needed for the selected EllesmereUI nameplate setup. Leave that installer step unused. YUI's nameplate synchronization/outline settings are disabled.

YUI bundles seven fonts under its own Media directory. It does not install Windows fonts. Byte-identical custom font copies now live in the game-root Fonts directory; existing game font overrides were retained.

Run `adopt_addons.ps1` from the local source game root (`_classic_beta_`); its positional argument is the destination game root, including a writable UNC share. Close WoW on both installations first. The script checks local source processes; it cannot check the remote client's process state. For example:

```powershell
.\Interface\adopt_addons.ps1 \\destination\WoW\_classic_beta_ -Resolution 1920x1080
```

The named form is `-Destination <path>`. The destination directory must already exist and allow file/directory writes and renames. The script replaces destination Interface and WTF after storing backups and logs under destination `addon-backups`. It merges source Fonts when present while preserving destination-only font files, and restores original folders if replacement fails. Source files remain unchanged. Without `-Resolution` it preserves all settings. For a 1080p destination, `-Resolution 1920x1080` sets `gxWindowedResolution` and fits the EUI options window while retaining gameplay UI scale and frame positions. The same option supports `2560x1440` and `3840x2160`.

## Frame and navigation visibility repair

EUI 9.4 standalone modules explicitly disable themselves when another EUI standalone is enabled. Use the shared core plus UnitFrames, RaidFrames and Nameplates above; the three old standalone folders have been removed from the installation. No other suite feature modules are installed. Preferences were migrated to EllesmereUIDB; the guard now targets the shared modules and their spec override keys.

RestedXP's arrow was not explicitly disabled, but hideInRaid was true. Set hideInRaid=false, disableArrow=false and showEnabled=true, reset arrow size to 32 and scale to 1, and anchor it at TOP/UIParent/TOP, x=0, y=-180. The guide and step progress are unchanged. This repairs visibility preferences; the arrow still requires an active waypoint, usable world coordinates and facing, and normally hides inside instances. A definitive runtime cause was not recorded in saved settings or logs.

Latest BugGrabber saved errors are empty. Old FrameXML/taint logs belong to earlier configurations. The upgraded package bytes, unchanged WTF settings and 32 guard tests were verified; live rendering and the three target resolutions remain pending.
## New characters and other displays

EUI uses the shared Default profile, with no specialization assignments currently present. YUI also selects Default for an unmapped character. RestedXP creates a separate character profile: its supported account default now contains the current layout and complete upstream defaults, with arrow visibility enabled, raid hiding off and competing automation/talent settings off. Guide selection/progress remains character-specific. The guard applies ownership after login to new profiles as well. Built-in Blizzard bars, keybindings and character-only settings are not automatically cloned into a new character.

The obsolete standalone folders are absent, preventing fresh characters from enabling them and receiving conflict popups. Existing disabled entries in AddOns.txt are harmless. Copying WTF assumes the same WoW account folder; a different account needs its account SavedVariables transferred into that account's folder. WTF stays outside Git.

The adoption tests cover source-to-destination and repeated transfers, full source-file preservation, destination backup/rollback, rejection of wrong working directories and overlapping/invalid roots, empty destinations, a running local client, Unicode preservation and fitting the EUI panel at all three target resolutions. EUI options scales are 0.90 / 1.00 / 1.50 respectively. A real writable UNC-share adoption succeeded at 1080p after an initial transient directory-move error; destination settings, custom fonts, source Lua/script copies and original-folder backups were verified. Share permissions and remote-client state remain installation-specific. Eighteen fresh class/faction profiles were checked using the installed database engines; this does not simulate live game APIs or rendering.

The latest tested session has one ADDON_ACTION_BLOCKED report attributed to DungeonsForever for Blizzard PTR feedback's SubmitBug(). No EUI/RestedXP Lua errors were captured. This separate feedback-report issue remains unresolved; the font workaround below is unrelated to that feedback-report issue.

## Local font workaround - 2026-10-12

YUI v341 retains the portable-font workaround introduced on 2026-10-12. TalentsForeverBook 0.38.2 now uses regular Cinzel upstream, so its earlier local UI.lua patch is no longer needed. YUI's original Inter Black face is restored for its SharedMedia selection (including target range text) and talent ranks through `Fonts\YUIInterBlack.ttf`. The LongZhu selection uses `Fonts\YUILongZhu.ttf`. All seven YUI fonts use byte-identical copies from `Media\Bundles\sharedmedia-fonts` under `Fonts`: `YUIInterBlack.ttf`, `YUIInterBold.ttf`, `YUIText.ttf`, `YUILongZhu.ttf`, `YUIHOOGE.ttf`, `YUIDamage1.ttf` and `YUIDark.ttf`. All seven SharedMedia registrations use these paths while retaining their selection names. The short filenames try fresh asset paths after the original Inter Black path reported `Can't find file in build manifest`. No default font is substituted for these selections. EllesmereUI's saved `fctFont` selects that LongZhu copy for damage text; EllesmereUI remains the sole damage-font owner. Font sizes and layout are unchanged.

Upstream updates can overwrite the YUI Lua patch; keep the portable font copies and reapply its references after updating YUI. No new overlapping setting was introduced. The adoption script copies Interface and WTF and merges the game-root `Fonts` directory when present, so it carries the font files and damage-font selection. Destination-only font files are preserved, and Fonts participates in backup and rollback. Local tests verify SharedMedia resolution, font hashes/numeric glyphs, EllesmereUI damage-font application and adoption. Fully exit and restart the game to discover new assets and refresh cached damage fonts. Fresh-session rendering, absence of manifest errors and appearance at 1080p/1440p/4K still require in-game confirmation. Arrow asset 137237 is a separate unresolved issue.
