# YoloMouse setup for WoW: Forever

YoloMouse (Steam app 1283970, version 1.26.1.0) replaces the game cursor with its own cursors. This page records why it did not work with WoW: Forever out of the box, what made it work on 2026-11-25, and how to keep it working.

## Summary

- **Cause 1: the WoW preset never matches this client.** YoloMouse recognises each game cursor by a hash of its image. Its "WoW Basic Blue/Pink" presets carry 88 hashes taken from standard WoW cursors at the Default and largest sizes. WoW: Forever (client 1.60.1, product `wowf`) draws its own cursor art, with a tan corner-pointer triangle on every icon, so none of its cursors match any preset hash at any `cursorSizePreferred` value. Out of 31 cursors YoloMouse recorded from this client, 0 were in the preset.
- **Cause 2: YoloMouse had been switched off** with its toggle hotkey (Ctrl+Alt+Y), so not even the default binding (original cursor plus glow) was applied. Pressing Ctrl+Alt+Y in game switched it back on.
- **Fix:** bindings for this client's own cursor hashes were added to `Bindings.json`. Each one maps to the Basic Blue cursor the preset uses for that job, at size 64. After restarting YoloMouse, the game showed the blue arrow, anvils and speech bubbles at 64×64 instead of the client's 84×84 originals.

## Files

| File | Purpose |
|---|---|
| `%LOCALAPPDATA%\YoloMouse\Bindings.json` | Per-game cursor bindings (hash → bundle, colour, size) and the default binding |
| `%LOCALAPPDATA%\YoloMouse\Settings.json` | Hotkeys and app settings |
| `%LOCALAPPDATA%\YoloMouse\Cache\AppProfiles\AppProfiles.json` | Hashes of every cursor YoloMouse has seen per game; `<hash>.cur` beside it is the original image |
| `%LOCALAPPDATA%\YoloMouse\Cache\Effects\` | Rendered replacement cursors, named `<id>_<colour><glow>..<size>.cur` (e.g. `…_ffffff0000040040` = no glow, size 0x40 = 64) |
| `<Steam>\steamapps\common\YoloMouse\Presets\WoW.Basic.Blue\Preset.json` | The stock preset (hashes for standard WoW only) |
| `<Steam>\steamapps\common\YoloMouse\Cursors\<Bundle>\` | Cursor bundles; each has `Blue.cur`, `DarkBlue.cur` and other colours |

YoloMouse rewrites `Bindings.json` while it runs and when it exits, so edit the file only while YoloMouse is fully closed. It runs as administrator: closing it from a normal shell is denied, so use its tray icon (Exit) or an elevated `Stop-Process -Name YoloMouse -Force`. Start it again with `steam://rungameid/1283970`.

## What was checked

1. The YoloMouse hook DLL (`%LOCALAPPDATA%\YoloMouse\Temp\Yolo64_0.dll`) was loaded in `Wow.exe`, and YoloMouse kept recording new cursors in `AppProfiles.json`, so injection worked.
2. The live cursor, read with `GetCursorInfo` and saved as an image, was the client's own gauntlet (84×84 on a 3840×2160 display at 150% scaling) at `cursorSizePreferred` 2 and 4 alike.
3. Comparing `AppProfiles.json` with `Bindings.json`: 0 of the recorded cursors were in the 88 preset bindings, before and after switching the game to 128×128 cursors.
4. No add-on replaces cursor textures: `tools/cursor_blp.py` notes that this client ignores loose files under `Interface/Cursor`, and none are installed.
5. No replacement cursors were rendered after YoloMouse restarted at 08:01 until Ctrl+Alt+Y was pressed in game at about 09:23, after which each newly seen cursor was rendered at size 64.
6. After the new bindings: the cursors recorded in game were YoloMouse's (64×64, blue arrow, blue and dark-blue anvil, speech bubbles).

Other findings on the way:

- WoW's own cursor size (`cursorSizePreferred`) only decides which image, and so which hash, the client hands to YoloMouse. The size shown is YoloMouse's `Size` (64 here).
- After YoloMouse restarts, a WoW session started under the previous YoloMouse instance may not pick up the new one; start YoloMouse first, then the game.
- `YUI` Mouse Enhancement can set `cursorSizePreferred` from its own `cursorSize` setting, but only while its cursor effects are on (they are off).

## Bindings added

All at `"Size": 64`, with the white glow (`"Glow": 6`) chosen in YoloMouse's editor. Blue is used for active cursors and DarkBlue for greyed ones, as in the stock preset. Rows marked 128 are the client's 128×128 versions (`cursorSizePreferred` 4); the others are its 64×64 versions (`cursorSizePreferred` 2). Rows marked *new* were added on 2026-11-25 at 11:50, after YoloMouse had recorded them in game.

| Client cursor | Hash | Bundle | Colour |
|---|---|---|---|
| Gauntlet (point) | `FB064CDEEE05E2CC` | Arrow | Blue |
| Gauntlet (point), 128 | `C581271E4B8C5D50` | Arrow | Blue |
| Gauntlet (point), 128 variant | `4EEEB73873806AEF` | Arrow | Blue |
| Dagger (attack), *new* | `A08963F8D6119022` | Sword | Blue |
| Dagger, greyed (was Blue before the coloured dagger was seen) | `536BD734CA1BC01` | Sword | DarkBlue |
| Loot bag | `816E9BD23E96571` | Bag | Blue |
| Loot bag, 128 | `1316F3BCF64B9EFA` | Bag | Blue |
| Loot bag, greyed | `A0AFB2D7A2E867AB` | Bag | DarkBlue |
| Loot bag, greyed, 128 | `CCCB95F31AFA7FC1` | Bag | DarkBlue |
| Several bags, greyed | `4D5DA8F9D9A5066` | Bag | DarkBlue |
| Speech bubble | `81389BC76775C5B2` | Speech | Blue |
| Speech bubble, greyed | `F74275F36BBF2C77` | Speech | DarkBlue |
| Speech bubble, 128, *new* | `613D99BD9C5CD244` | Speech | Blue |
| Speech bubble, greyed, 128, *new* | `BFFE5C98A416C790` | Speech | DarkBlue |
| Mail | `A2F2005EDC51C6DE` | Mail | Blue |
| Mail, greyed | `5E9C9FAD5310FF3A` | Mail | DarkBlue |
| Hearthstone (innkeeper) | `17FF887D12AD46D0` | Home | Blue |
| Hearthstone, 128 | `440077699B277E05` | Home | Blue |
| Hearthstone, greyed, 128 | `F6DFC9102999B102` | Home | DarkBlue |
| Hearthstone, greyed, *new* | `BFA59479D90F4C69` | Home | DarkBlue |
| Anvil (repair), 128 | `6D13A35AB2053E3` | Anvil | Blue |
| Anvil (repair), *new* | `49FBCB4F601DA6E` | Anvil | Blue |
| Anvil, greyed | `64FEF5812A5DC17C` | Anvil | DarkBlue |
| Anvil, greyed, 128 | `996EDC99F59763BA` | Anvil | DarkBlue |
| Helmet (purple) | `B6B56394A10AE696` | Helmet | Blue |
| Helmet, greyed | `43D2E2078A812219` | Helmet | DarkBlue |
| Yellow ! (quest available) | `18101738406A518` | Bang | Blue |
| Grey ! | `18D42120CD624034` | Bang | DarkBlue |
| Grey ? (quest incomplete) | `6899CD451FB083E9` | Question | DarkBlue |
| Gear, greyed | `CB53E7B211FF9B17` | Gear | DarkBlue |
| Book (trainer) | `BCD7E36E00E23EED` | Book | Blue |
| Book, greyed, *new* | `DF80BE4D0D83E9E7` | Book | DarkBlue |
| Winged boot (flight master), *new* | `E5C2325E2D303BEF` | Bird | Blue |
| Winged boot, greyed, *new* | `4A042F904E43FAD7` | Bird | DarkBlue |
| Skinning, *new* | `318D9A8144978C94` | Hatchet | Blue |
| Skinning, greyed, *new* | `6E2E3040FF1F5582` | Hatchet | DarkBlue |
| Several bags (loot), *new* | `60660C41305440CC` | Coins | Blue |
| Pick (mining), greyed, *new* | `109EC49519072622` | Pick | DarkBlue |
| Magnifier (inspect) | `61AF6E00255B2011` | Magnifier | Blue |
| Flowers (herb), greyed | `70B553CE9B3B2E94` | Plant | DarkBlue |
| Gold diamond | `9C41E75097F43981` | Map | Blue (best guess for its job) |

Left unbound on purpose, so they keep the client's art at the default size and glow: the item icons the client shows while an item is dragged (fish `224DDB0EA8AE3111`, heart `CFF9178C64AF3D1F`, potion `40B610DD6FB4168A`) and a blank cursor with only the corner triangle (`DEDDFCF59ED3C0EF`).

## Keeping it working

- **Don't apply a preset to the World of Warcraft game in YoloMouse's editor.** Applying one replaces the game's whole binding list with the preset's 88 stock WoW hashes, which this client never shows. On 2026-11-25 at about 11:46 an edit-and-apply did this: 23 of the 29 bindings above were dropped and every cursor reverted to the client's art. The fix was to close YoloMouse, put the client bindings back into `Bindings.json` and start it again. To change the look of every cursor, change the hand-written bindings instead, or ask for them to be regenerated with the new bundle, colour, size or glow.
- **Keep the client bindings first, and leave the stock preset's entries out.** After the preset apply, the 80 stock entries sat ahead of the client bindings, and YoloMouse then matched only the first client binding (the gauntlet). Repair, quest and hearthstone cursors kept the client's art with just the default glow. With the 41 client bindings alone, every bound cursor is replaced again, without restarting the game.
- The local preset **Rex Blue** (`%LOCALAPPDATA%\YoloMouse\Presets\Preset002`, last saved 2026-11-25 at 12:07) holds exactly the live WoW set: the 41 bindings above in the same order, and the same default binding (the client's own art at size 64 with the white glow). Applying it is the one safe preset apply, because it puts this exact set back. It is a snapshot, so bindings added later are not in it until it is saved again.

- Keep the game's cursor size at 64×64 (`/console cursorSizePreferred 2`); most bindings were recorded there. Only the gauntlet, bag, hearthstone and anvil also have 128×128 bindings.
- A cursor not met yet (mining, fishing, flight master, locked chest and so on) shows the client's own art. Hover it and press **Ctrl+Alt+1** to cycle bundles, or **Ctrl+Alt+C** for the picker; YoloMouse saves the binding itself. To bind a batch by hand: close YoloMouse, read the new hashes from `AppProfiles.json` (images in the same folder), add entries like the ones above to the WoW `Bindings` array, then start YoloMouse.
- If every cursor reverts to the client's art at once, YoloMouse was toggled off: press **Ctrl+Alt+Y** in game.
- After restarting YoloMouse, restart the game if the cursors do not change.
- Before the edit, `Bindings.json` was backed up beside itself as `Bindings.json.bak-20261125-092922` (and `Bindings.json.bak-20261125-075723` from an earlier size change from 92 to 64). The bindings dropped by the preset apply were put back after a backup to `Bindings.json.bak-20261125-115039`.

## Bindings.json (as of 2026-11-25 12:07)

`%LOCALAPPDATA%\YoloMouse\Bindings.json`, verbatim. The `Name` fields hold the game's Traditional Chinese title as YoloMouse stores it.

```json
[
    {
        "Game":
        {
            "Id": "world of warcraft",
            "OldId": "Program_Files_World_of_Warcraft__forever__Wow_exe",
            "Path": "D:\\Program Files\\World of Warcraft\\_forever_\\Wow.exe",
            "Name": "魔獸世界"
        },
        "DefaultBinding":
        {
            "Original": "true",
            "Size": 64,
            "Glow": 6,
            "GlowColor": "FFFFFFFF"
        },
        "Bindings":
        [
            {
                "Hash": "FB064CDEEE05E2CC",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C581271E4B8C5D50",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "4EEEB73873806AEF",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "A08963F8D6119022",
                "Bundle": "Sword",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "536BD734CA1BC01",
                "Bundle": "Sword",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "816E9BD23E96571",
                "Bundle": "Bag",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "1316F3BCF64B9EFA",
                "Bundle": "Bag",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "A0AFB2D7A2E867AB",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "CCCB95F31AFA7FC1",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "4D5DA8F9D9A5066",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "81389BC76775C5B2",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "613D99BD9C5CD244",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "F74275F36BBF2C77",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "BFFE5C98A416C790",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "A2F2005EDC51C6DE",
                "Bundle": "Mail",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "5E9C9FAD5310FF3A",
                "Bundle": "Mail",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "17FF887D12AD46D0",
                "Bundle": "Home",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "440077699B277E05",
                "Bundle": "Home",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "F6DFC9102999B102",
                "Bundle": "Home",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "BFA59479D90F4C69",
                "Bundle": "Home",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "6D13A35AB2053E3",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "49FBCB4F601DA6E",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "64FEF5812A5DC17C",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "996EDC99F59763BA",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "B6B56394A10AE696",
                "Bundle": "Helmet",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "43D2E2078A812219",
                "Bundle": "Helmet",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "18101738406A518",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "18D42120CD624034",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "6899CD451FB083E9",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "CB53E7B211FF9B17",
                "Bundle": "Gear",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "BCD7E36E00E23EED",
                "Bundle": "Book",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "DF80BE4D0D83E9E7",
                "Bundle": "Book",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "61AF6E00255B2011",
                "Bundle": "Magnifier",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "70B553CE9B3B2E94",
                "Bundle": "Plant",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "9C41E75097F43981",
                "Bundle": "Map",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "E5C2325E2D303BEF",
                "Bundle": "Bird",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "4A042F904E43FAD7",
                "Bundle": "Bird",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "318D9A8144978C94",
                "Bundle": "Hatchet",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "6E2E3040FF1F5582",
                "Bundle": "Hatchet",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "60660C41305440CC",
                "Bundle": "Coins",
                "Cursor": "Blue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "109EC49519072622",
                "Bundle": "Pick",
                "Cursor": "DarkBlue",
                "Size": 64,
                "Glow": 6,
                "GlowColor": "FFFFFFFF"
            }
        ],
        "Preset": "WoW.Basic.Blue"
    },
    {
        "Game":
        {
            "Id": "mumu安卓设备",
            "OldId": "nx_device______shell_MuMuNxDevice_exe",
            "Path": "C:\\Program Files\\Netease\\MuMu\\nx_device\\15.0\\shell\\MuMuNxDevice.exe",
            "Name": "mumu安卓设备"
        },
        "DefaultBinding":
        {
            "Bundle": "Arrow",
            "Cursor": "Blue",
            "Size": 48,
            "Glow": 5,
            "GlowColor": "FFFFFFFF"
        },
        "Preset": "Shared.BlueArrow"
    },
    {
        "Game":
        {
            "Id": "windows",
            "OldId": "windows",
            "Name": "Windows"
        },
        "Bindings":
        [
            {
                "Hash": "C0FFEE0000000001",
                "Bundle": "Desktop",
                "Cursor": "AppStarting.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000002",
                "Bundle": "Desktop",
                "Cursor": "Crosshair.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000003",
                "Bundle": "Hand",
                "Cursor": "Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000004",
                "Bundle": "Desktop",
                "Cursor": "Help.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000005",
                "Bundle": "Desktop",
                "Cursor": "IBeam.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000006",
                "Bundle": "Stop",
                "Cursor": "Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000007",
                "Bundle": "Desktop",
                "Cursor": "Person.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000008",
                "Bundle": "Desktop",
                "Cursor": "Pin.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000009",
                "Bundle": "Desktop",
                "Cursor": "SizeAll.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000A",
                "Bundle": "Desktop",
                "Cursor": "SizeNESW.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000B",
                "Bundle": "Desktop",
                "Cursor": "SizeNS.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000C",
                "Bundle": "Desktop",
                "Cursor": "SizeNWSE.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000D",
                "Bundle": "Desktop",
                "Cursor": "SizeWE.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE0000000000",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000E",
                "Bundle": "Desktop",
                "Cursor": "UpArrow.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            },
            {
                "Hash": "C0FFEE000000000F",
                "Bundle": "Desktop",
                "Cursor": "Wait.Blue",
                "Size": 32,
                "Glow": 5,
                "GlowColor": "FFFFFFFF"
            }
        ],
        "Preset": "Windows.Basic.Blue"
    }
]
```

## Settings.json (as of 2026-11-25 09:34)

`%LOCALAPPDATA%\YoloMouse\Settings.json`, verbatim. YoloMouse writes `Version` unquoted, so this file is not strict JSON.

```json
{
    "Version": 1.26.1.0,
    "AutoStart": "true",
    "IgnoreDesktop": "false",
    "BrowserOrder": "trending",
    "ShowTooltips": "true",
    "ShowPrompts": "true",
    "AchievementsEnabled": "true",
    "BackgroundStart": "false",
    "PreferredAssignTab": "preset",
    "UiScale": "AUTO",
    "MouseSensitivity": 0.5,
    "Language": "default",
    "SteamSync": "true",
    "Hotkeys":
    {
        "Toggle": "CONTROL ALT Y",
        "Picker": "CONTROL ALT C",
        "BindBundle": "CONTROL ALT 1",
        "BindCursor": "CONTROL ALT 2",
        "BindDefault": "CONTROL ALT D",
        "Unbind": "CONTROL ALT 0",
        "UnbindAll": "CONTROL ALT P",
        "Smaller": "CONTROL ALT -",
        "Larger": "CONTROL ALT =",
        "MouseSensitivityHold": "ALT MOUSE-MIDDLE",
        "MouseSensitivityToggle": "",
        "MouseLock": "CONTROL ALT L"
    },
    "HiddenCursors":
    {
    },
    "Session":
    {
        "Tutorial": "false",
        "LastTarget":
        {
            "Id": "world of warcraft",
            "OldId": "Program_Files_World_of_Warcraft__forever__Wow_exe",
            "Path": "D:\\Program Files\\World of Warcraft\\_forever_\\Wow.exe",
            "Name": "魔獸世界"
        }
    }
}
```

## Preset.json for comparison

The stock preset's `DefaultBinding` and first binding, from `<Steam>\steamapps\common\YoloMouse\Presets\WoW.Basic.Blue\Preset.json`; its 88 hashes are already inside `Bindings.json` above.

```json
{
    "Name": "Basic Blue",
    "Author": "Dragonrise Games",
    "Description": "Use default or largest cursor\nsize in WoW settings",
    "Game":
    {
        "Id": "world of warcraft",
        "Name": "World of Warcraft"
    },
    "DefaultBinding":
    {
        "Original": "true",
        "Size": 92,
        "Glow": 10,
        "GlowColor": "FFFFFFFF"
    },
    "Bindings":
    [
        {
            "Hash": "A9C9DCD5A72D2827",
            "Bundle": "Sword",
            "Cursor": "DarkBlue",
            "Size": 92
        },
        ...
    ]
}
```
