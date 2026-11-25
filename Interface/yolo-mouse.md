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

All at `"Size": 64`. Blue is used for active cursors and DarkBlue for greyed ones, as in the stock preset. Rows marked 128 are the client's 128×128 versions (`cursorSizePreferred` 4); the others are its 64×64 versions (`cursorSizePreferred` 2).

| Client cursor | Hash | Bundle | Colour |
|---|---|---|---|
| Gauntlet (point) | `FB064CDEEE05E2CC` | Arrow | Blue |
| Gauntlet (point), 128 | `C581271E4B8C5D50` | Arrow | Blue |
| Gauntlet (point), 128 variant | `4EEEB73873806AEF` | Arrow | Blue |
| Dagger (attack) | `536BD734CA1BC01` | Sword | Blue |
| Loot bag | `816E9BD23E96571` | Bag | Blue |
| Loot bag, 128 | `1316F3BCF64B9EFA` | Bag | Blue |
| Loot bag, greyed | `A0AFB2D7A2E867AB` | Bag | DarkBlue |
| Loot bag, greyed, 128 | `CCCB95F31AFA7FC1` | Bag | DarkBlue |
| Several bags, greyed | `4D5DA8F9D9A5066` | Bag | DarkBlue |
| Speech bubble | `81389BC76775C5B2` | Speech | Blue |
| Speech bubble, greyed | `F74275F36BBF2C77` | Speech | DarkBlue |
| Mail | `A2F2005EDC51C6DE` | Mail | Blue |
| Mail, greyed | `5E9C9FAD5310FF3A` | Mail | DarkBlue |
| Hearthstone (innkeeper) | `17FF887D12AD46D0` | Home | Blue |
| Hearthstone, 128 | `440077699B277E05` | Home | Blue |
| Hearthstone, greyed, 128 | `F6DFC9102999B102` | Home | DarkBlue |
| Anvil (repair), 128 | `6D13A35AB2053E3` | Anvil | Blue |
| Anvil, greyed | `64FEF5812A5DC17C` | Anvil | DarkBlue |
| Anvil, greyed, 128 | `996EDC99F59763BA` | Anvil | DarkBlue |
| Helmet (purple) | `B6B56394A10AE696` | Helmet | Blue |
| Helmet, greyed | `43D2E2078A812219` | Helmet | DarkBlue |
| Yellow ! (quest available) | `18101738406A518` | Bang | Blue |
| Grey ! | `18D42120CD624034` | Bang | DarkBlue |
| Grey ? (quest incomplete) | `6899CD451FB083E9` | Question | DarkBlue |
| Gear, greyed | `CB53E7B211FF9B17` | Gear | DarkBlue |
| Book (trainer) | `BCD7E36E00E23EED` | Book | Blue |
| Magnifier (inspect) | `61AF6E00255B2011` | Magnifier | Blue |
| Flowers (herb), greyed | `70B553CE9B3B2E94` | Plant | DarkBlue |
| Gold diamond | `9C41E75097F43981` | Map | Blue (best guess for its job) |

## Keeping it working

- Keep the game's cursor size at 64×64 (`/console cursorSizePreferred 2`); most bindings were recorded there. Only the gauntlet, bag, hearthstone and anvil also have 128×128 bindings.
- A cursor not met yet (mining, fishing, flight master, locked chest and so on) shows the client's own art. Hover it and press **Ctrl+Alt+1** to cycle bundles, or **Ctrl+Alt+C** for the picker; YoloMouse saves the binding itself. To bind a batch by hand: close YoloMouse, read the new hashes from `AppProfiles.json` (images in the same folder), add entries like the ones above to the WoW `Bindings` array, then start YoloMouse.
- If every cursor reverts to the client's art at once, YoloMouse was toggled off: press **Ctrl+Alt+Y** in game.
- After restarting YoloMouse, restart the game if the cursors do not change.
- Before the edit, `Bindings.json` was backed up beside itself as `Bindings.json.bak-20261125-092922` (and `Bindings.json.bak-20261125-075723` from an earlier size change from 92 to 64).

## Bindings.json (as of 2026-11-25 09:29)

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
            "Glow": 10,
            "GlowColor": "FFFFFFFF"
        },
        "Bindings":
        [
            {
                "Hash": "FB064CDEEE05E2CC",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "C581271E4B8C5D50",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "4EEEB73873806AEF",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "536BD734CA1BC01",
                "Bundle": "Sword",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "816E9BD23E96571",
                "Bundle": "Bag",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "1316F3BCF64B9EFA",
                "Bundle": "Bag",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "A0AFB2D7A2E867AB",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "CCCB95F31AFA7FC1",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "4D5DA8F9D9A5066",
                "Bundle": "Bag",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "81389BC76775C5B2",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "F74275F36BBF2C77",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "A2F2005EDC51C6DE",
                "Bundle": "Mail",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "5E9C9FAD5310FF3A",
                "Bundle": "Mail",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "17FF887D12AD46D0",
                "Bundle": "Home",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "440077699B277E05",
                "Bundle": "Home",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "F6DFC9102999B102",
                "Bundle": "Home",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "6D13A35AB2053E3",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "64FEF5812A5DC17C",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "996EDC99F59763BA",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "B6B56394A10AE696",
                "Bundle": "Helmet",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "43D2E2078A812219",
                "Bundle": "Helmet",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "18101738406A518",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "18D42120CD624034",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "6899CD451FB083E9",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "CB53E7B211FF9B17",
                "Bundle": "Gear",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "BCD7E36E00E23EED",
                "Bundle": "Book",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "61AF6E00255B2011",
                "Bundle": "Magnifier",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "70B553CE9B3B2E94",
                "Bundle": "Plant",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "9C41E75097F43981",
                "Bundle": "Map",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "A9C9DCD5A72D2827",
                "Bundle": "Sword",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "E78B9D6A6A62C34A",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "47CA3F1285AABBF0",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "A1851749475D141F",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "9C1E583EF7C6F062",
                "Bundle": "Coins",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "F6042F7A8CD8C7B",
                "Bundle": "Coins",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "8A585C0C4418084E",
                "Bundle": "Sword",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "50E6E0518630BE9",
                "Bundle": "Mail",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "78C599A521E065BA",
                "Bundle": "Mail",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "C4482F2DEB4B711D",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "F30E3195D613F390",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "DDADC2975773935A",
                "Bundle": "Map",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "AA4FE41763433438",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "91920AAFFF3DAB92",
                "Bundle": "Question",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "3B4A0A4AE68194D7",
                "Bundle": "Gear",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "3C7BF5DB26D9F810",
                "Bundle": "Gear",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "49A79A3EA6AB75BD",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "821D7CAD7C22C53A",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "96A9D5091E6035B2",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "B1E781B9255098EB",
                "Bundle": "Question",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "C3B2BBADD4F24F57",
                "Bundle": "Sword",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "F49296E62393132E",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "71E6E58DDF3ACC48",
                "Bundle": "Bird",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "1304B9AC03620E07",
                "Bundle": "Bird",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "D9A3162D7C223DF1",
                "Bundle": "Bird",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "EEC7A8433EFF8D11",
                "Bundle": "Bird",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "7791913B7E980A80",
                "Bundle": "Map",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "67F80BDFBFCABDEB",
                "Bundle": "Map",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "5A55DC1C5EBDCA8E",
                "Bundle": "Map",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "B7F8227CF0FBC69D",
                "Bundle": "Horse",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "FE93C2A112316BD7",
                "Bundle": "Gear",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "72CFC6AF07F2A64",
                "Bundle": "Horse",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "A37BCAA56D4ECC61",
                "Bundle": "Horse",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "BDFFA3D7E208D4C3",
                "Bundle": "Horse",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "62A708F8DD3FE56E",
                "Bundle": "Book",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "4340B35CF923F309",
                "Bundle": "Book",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "51326BA465E829AA",
                "Bundle": "Home",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "4D0CC324E5F6B9D0",
                "Bundle": "Home",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "73C4F03ADCC2F4E3",
                "Bundle": "Book",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "B4F727A3DAC5D7C",
                "Bundle": "Book",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "1AB292E18C7D202C",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "BFFE5C98A416C790",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "613D99BD9C5CD244",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "EFEDEFA8FB1D67D1",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "63ACED4A40FF0020",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "A11CA37FF9606491",
                "Bundle": "Sword",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "B9176029D65AD569",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "30F68349A3969316",
                "Bundle": "Mail",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "A31BF14AD793BFA6",
                "Bundle": "Mail",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "2DDF34FC4955A67C",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "66FF68B6ECDF16A3",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "83EFACB44CEDA752",
                "Bundle": "Bang",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "3A37AE7DECB3F1B2",
                "Bundle": "Bang",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "82F70802C95DE577",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "58C6F782FE2AD271",
                "Bundle": "Question",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "E080D3113053360D",
                "Bundle": "Question",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "3630C946721F7D88",
                "Bundle": "HandOpen",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "BACFCB1D4A5A5D1",
                "Bundle": "HandOpen",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "B14C580E05A86DD",
                "Bundle": "HandOpen",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "53FB17B5256CC012",
                "Bundle": "HandOpen",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "F2404A452B9C6B64",
                "Bundle": "Gear",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "D1FDEDBE839C44DE",
                "Bundle": "Question",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "98867198FD48135E",
                "Bundle": "Pick",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "8366B28447EC7971",
                "Bundle": "Plant",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "C526028A80FA349E",
                "Bundle": "Plant",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "978FCAC11D57192E",
                "Bundle": "Plant",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "91185E743E749E5F",
                "Bundle": "Plant",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "9A9031DB4AAD38CF",
                "Bundle": "Pick",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "BA261EC6C27B687D",
                "Bundle": "Pick",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "1A77200702EA43C7",
                "Bundle": "Pick",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "FC6EAAB270E6E330",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "246692FEB44EDB72",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "26ABD269C847B213",
                "Bundle": "Anvil",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "C824D4E5EB9DE86E",
                "Bundle": "Anvil",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "FD37BC2D3DA575E2",
                "Bundle": "Pick",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "452F18DD0F07C0A1",
                "Bundle": "Pick",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "5FC29766622345E7",
                "Bundle": "HandOpen",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "25F58C7104D88495",
                "Bundle": "HandOpen",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "8B469A4850441378",
                "Bundle": "Arrow",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "1A7BE95CE1BF9538",
                "Bundle": "Arrow",
                "Cursor": "DarkBlue",
                "Size": 64
            },
            {
                "Hash": "FEA9A846F88E0266",
                "Bundle": "Speech",
                "Cursor": "Blue",
                "Size": 64
            },
            {
                "Hash": "A335809BBC348B85",
                "Bundle": "Speech",
                "Cursor": "DarkBlue",
                "Size": 64
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
