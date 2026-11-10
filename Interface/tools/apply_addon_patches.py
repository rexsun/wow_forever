"""Reapply the pack's local patches to upstream addon files after an update.

    uv run python tools/apply_addon_patches.py          # apply, idempotent
    uv run python tools/apply_addon_patches.py --check  # report only; exit 1 if unpatched

A patch whose expected text is missing fails loudly: upstream changed, so review it
rather than leave a file half patched. No file is written unless every patch applies.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

ADDONS = Path(__file__).resolve().parents[1] / "AddOns"
LSM_PREFIX = 'LSM:Register("font", " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3'


@dataclass(frozen=True)
class Patch:
    file: str
    upstream: str
    patched: str


def _font(label: str, bundled: str, portable: str) -> Patch:
    return Patch(
        "YUI/Media/Init_SharedMedia.lua",
        f'{LSM_PREFIX}{label}|r", Bundle("sharedmedia-fonts", "{bundled}"), 255)',
        f'{LSM_PREFIX}{label}|r", "Fonts\\\\{portable}", 255)',
    )


PATCHES = (
    _font("Inter Black", "YUI Inter Black.ttf", "YUIInterBlack.ttf"),
    _font("Inter Bold", "YUI Inter Bold.ttf", "YUIInterBold.ttf"),
    _font("Text", "YUI Text.TTF", "YUIText.ttf"),
    _font("龙珠", "YUI LongZhu.ttf", "YUILongZhu.ttf"),
    _font("HOOGE", "YUI HOOGE.ttf", "YUIHOOGE.ttf"),
    _font("胖娃", "YUI Damage1.ttf", "YUIDamage1.ttf"),
    _font("Dark", "YUI Dark.ttf", "YUIDark.ttf"),
    Patch(
        "YUI/Components/TalentFrameEnhancement/TalentFrameEnhancement.lua",
        'local RANK_FONT = "Interface\\\\AddOns\\\\YUI\\\\Media\\\\Bundles\\\\sharedmedia-fonts\\\\YUI Inter Black.ttf"',
        'local RANK_FONT = "Fonts\\\\YUIInterBlack.ttf"',
    ),
    # Upstream's EUI skin switches Skinner to a profile with every Blizzard skin disabled
    # and routes skinning through callbacks that only EllesmereUIBlizzardSkin delivers.
    # That module is not in this pack and Skinner offers no setting to skip the file.
    Patch(
        "Skinner/AddonSkins/_AddonSkins.xml",
        '<Script file="EllesmereUI.lua"/>',
        '<!-- Script file="EllesmereUI.lua" excluded by this pack: see AddOns/readme.md -->',
    ),
    # beta12.70688.1 dropped this line, assuming [Family] resolves to Forever. On this
    # client [Family] is Mainline, so SetupForever_* stay nil and OnInitialize aborts.
    Patch(
        "Skinner/Skinner.toc",
        "[Family]\\_Support.xml",
        "[Family]\\_Support.xml\n\n"
        "Forever\\_Support.xml [AllowLoadGameType camelot] [ExcludeLoadGameType standard, classic]",
    ),
    # Bagnon hides only ContainerFrame1..N and relies on combined bags being off, but its nil
    # write leaves combinedBags unsaved on this client, so ContainerFrameCombinedBags still
    # opens beside it. Write an explicit 0, also outside the tutorial-constant guard.
    Patch(
        "BagBrother/core/features/uiOverrides.lua",
        "\tself:RegisterEvent('CVAR_UPDATE', self.Delay, 'OnCVar')",
        "\tself:RegisterEvent('CVAR_UPDATE', self.Delay, 'OnCVar')\n"
        "\tif Addon.Frames:IsEnabled('inventory') then\n"
        "\t\tC_CVar.SetCVar('combinedBags', '0')\n"
        "\tend",
    ),
    Patch(
        "BagBrother/core/features/uiOverrides.lua",
        "IsEnabled('inventory') then\n\t\t\tC_CVar.SetCVar('combinedBags', nil)",
        "IsEnabled('inventory') then\n\t\t\tC_CVar.SetCVar('combinedBags', '0')",
    ),
    Patch(
        "BagBrother/core/features/uiOverrides.lua",
        "InCombatLockdown() and Addon.Frames:IsEnabled('inventory') then\n\t\tC_CVar.SetCVar('combinedBags', nil)",
        "InCombatLockdown() and Addon.Frames:IsEnabled('inventory') then\n\t\tC_CVar.SetCVar('combinedBags', '0')",
    ),
    # Details 15400 ships commit 803d6220 and the parser guard, so four of these six now match
    # upstream and are reported as already applied. The util.lua death-log and Midnight breakdown
    # lookups are still unguarded upstream. Guarding callers rather
    # than DF:GetSpec* keeps the fix effective if another addon's newer DetailsFramework loads.
    Patch(
        "Details/classes/class_damage.lua",
        "spec = detailsFramework:GetSpecInfoFromSpecIcon(specIcon), --0",
        "spec = not issecretvalue(specIcon) and detailsFramework:GetSpecInfoFromSpecIcon(specIcon) or nil, --0",
    ),
    Patch(
        "Details/classes/class_damage.lua",
        "local specInfo = detailsFramework:GetSpecInfoFromSpecIcon(self.thisSpecIcon)",
        "local specInfo = not issecretvalue(self.thisSpecIcon)"
        " and detailsFramework:GetSpecInfoFromSpecIcon(self.thisSpecIcon)",
    ),
    Patch(
        "Details/functions/util.lua",
        "local specInfo = detailsFramework:GetSpecInfoFromSpecIcon(blzSpecIcon)",
        "local specInfo = not issecretvalue(blzSpecIcon) and detailsFramework:GetSpecInfoFromSpecIcon(blzSpecIcon)",
    ),
    Patch(
        "Details/functions/util.lua",
        '["spec"] = detailsFramework:GetSpecIdFromSpecIcon(specIcon),',
        '["spec"] = not issecretvalue(specIcon) and detailsFramework:GetSpecIdFromSpecIcon(specIcon) or nil,',
    ),
    Patch(
        "Details/frames/window_breakdown_midnight/breakdown_dataprovider.lua",
        "source.classFilename, detailsFramework:GetSpecIdFromSpecIcon(source.specIconID) or 62,",
        "source.classFilename, not issecretvalue(source.specIconID)"
        " and detailsFramework:GetSpecIdFromSpecIcon(source.specIconID) or 62,",
    ),
    Patch(
        "Details/core/parser_nocleu_tp.lua",
        "thisSerial = thisSerial or bParser.guidCache[icon or sourcePlayer.specIconID] or nil",
        "thisSerial = thisSerial or (not issecretvalue(icon or sourcePlayer.specIconID)"
        " and bParser.guidCache[icon or sourcePlayer.specIconID]) or nil",
    ),
    # Upstream skips the check only when the text has a secret aspect, but IsTruncated() can still
    # return a secret boolean, which threw on row hover (BugGrabber, 2026-11-05).
    Patch(
        "Details/frames/window_main.lua",
        "if (canCheckForTrancation and lefttext:IsTruncated()) then",
        "if (canCheckForTrancation and not issecretvalue(lefttext:IsTruncated()) and lefttext:IsTruncated()) then",
    ),
    # Upstream fixes the size and Unlock Mode cannot resize it; 40 was too small to read at a glance.
    Patch(
        "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Fishing.lua",
        "local INDICATOR_SIZE = 40",
        "local INDICATOR_SIZE = 100",
    ),
    # Upstream only ducks music and ambience. Every float plays the same file on the effects
    # channel, so other players' floats cannot be filtered: silencing the other channels and
    # maximising effects is the most an addon can do.
    Patch(
        "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Fishing.lua",
        "    Sound_MusicVolume = function(before) return before * 0.3 end,\n"
        "    Sound_AmbienceVolume = function(before) return before * 0.3 end,\n"
        "    Sound_SFXVolume = function(before) return math.max(before, 0.8) end,\n",
        "    Sound_MusicVolume = function() return 0 end,\n"
        "    Sound_AmbienceVolume = function() return 0 end,\n"
        "    Sound_DialogVolume = function() return 0 end,\n"
        "    Sound_SFXVolume = function() return 1 end,\n"
        "    Sound_MasterVolume = function() return 1 end,\n",
    ),
    Patch(
        "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Fishing.lua",
        "--  Fishing Sounds   music and ambience down, effects up, for the session.",
        "--  Fishing Sounds   music, ambience and dialog off, effects and master full, for the session.",
    ),
    Patch(
        "EllesmereUIOptions/EUI_ForeverEssentials_General_Options.lua",
        'tooltip = "While you fish: music and ambience down, effects up, sound on in the background.",',
        'tooltip = "While you fish: music, ambience and dialog off, effects and master volume full, sound on in the background.",',
    ),
    # The tooltip is the translation key, so the client's locale must move with it.
    Patch(
        "EllesmereUILocales/zhTW.lua",
        'L["While you fish: music and ambience down, effects up, sound on in the background."] = '
        '"釣魚時：降低音樂與環境音、提高音效，並在遊戲於背景執行時仍播放聲音。"',
        'L["While you fish: music, ambience and dialog off, effects and master volume full, sound on in the background."] = '
        '"釣魚時：關閉音樂、環境音與對話，音效與主音量調到最大，並在遊戲於背景執行時仍播放聲音。"',
    ),
    # 1.5.6 keeps its world map fader on whenever PlayerMovementFrameFader exists, even with
    # WORLDMAPFADE off; it then holds the map at full opacity and its SetAlpha hook undoes YUI's
    # fade while moving. Restoring the 1.4.25 check lets the mu.worldmapfade guard rule work again.
    Patch(
        "MapUtils/mapframe.lua",
        '["isEnabled"] = function() return PlayerMovementFrameFader ~= nil or '
        '(type(MAUTTAB) == "table" and MAUTTAB["WORLDMAPFADE"] ~= false) end,',
        '["isEnabled"] = function() return type(MAUTTAB) == "table" and MAUTTAB["WORLDMAPFADE"] ~= false end,',
    ),
)

# Any other use of these markers means upstream added a reference the patches do not cover.
UNCOVERED_MARKERS = {
    "YUI/Media/Init_SharedMedia.lua": ', Bundle("sharedmedia-fonts"',
    "YUI/Components/TalentFrameEnhancement/TalentFrameEnhancement.lua": "sharedmedia-fonts",
}


def apply_patches(addons: Path, check: bool = False) -> list[str]:
    """Return problems found; write files only when there are none and check is False."""
    problems: list[str] = []
    updated: dict[Path, str] = {}
    for patch in PATCHES:
        path = addons / patch.file
        if not path.is_file():
            problems.append(f"{patch.file}: file not found")
            continue
        with path.open(encoding="utf-8", newline="") as stream:
            text = updated.get(path, stream.read())
        newline = "\r\n" if "\r\n" in text else "\n"
        upstream = patch.upstream.replace("\n", newline)
        patched = patch.patched.replace("\n", newline)
        if patched in text:
            # An additive patch legitimately contains its upstream line, so only look outside it.
            if upstream in text.replace(patched, ""):
                problems.append(f"{patch.file}: both patched and upstream text present: {patch.upstream}")
            updated.setdefault(path, text)
        elif text.count(upstream) == 1:
            if check:
                problems.append(f"{patch.file}: not patched: {patch.upstream}")
            updated[path] = text.replace(upstream, patched)
        else:
            problems.append(f"{patch.file}: expected text not found once: {patch.upstream}")
    for relative, marker in UNCOVERED_MARKERS.items():
        path = addons / relative
        if path in updated and marker in updated[path]:
            problems.append(f"{relative}: uncovered reference remains: {marker}")
    if problems or check:
        return problems
    for path, text in updated.items():
        with path.open("w", encoding="utf-8", newline="") as stream:
            stream.write(text)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report without writing")
    parser.add_argument("--addons", type=Path, default=ADDONS)
    args = parser.parse_args()
    problems = apply_patches(args.addons, args.check)
    for problem in problems:
        print(f"FAIL: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"OK: {len(PATCHES)} local patches in place")
    return 0


if __name__ == "__main__":
    sys.exit(main())
