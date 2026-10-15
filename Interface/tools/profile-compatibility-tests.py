"""Check saved profiles using the installed AceDB and EllesmereUI database engines.

Run with uv run --with lupa python tools/profile-compatibility-tests.py.
Game API stubs verify profile inheritance, not live rendering.
"""

from pathlib import Path

from lupa import lua51


ROOT = Path(__file__).resolve().parents[1]
CLASSES = (
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
)


def check_account(saved: Path, class_name: str, faction: str) -> None:
    lua = lua51.LuaRuntime()
    lua.globals().TEST_CLASS = class_name
    lua.globals().TEST_FACTION = faction
    lua.execute("""
        strmatch = string.match
        function GetRealmName() return "Classic Beta PvP" end
        function UnitName() return "Compatibility" .. TEST_CLASS end
        function UnitClass() return TEST_CLASS, TEST_CLASS end
        function UnitRace() return "Human", "Human" end
        function UnitFactionGroup() return TEST_FACTION end
        function GetLocale() return "zhTW" end
        function GetCurrentRegion() return 1 end
        function GetCurrentRegionName() return "US" end
        function GetBuildInfo() return "1.60.1", "70338", "2026", 16001 end
        function CreateFrame()
            return {RegisterEvent=function() end, SetScript=function() end}
        end
        function CopyTable(t)
            local out = {}
            for k,v in pairs(t) do
                out[k] = type(v)=="table" and CopyTable(v) or v
            end
            return out
        end
        function wipe(t) for k in pairs(t) do t[k]=nil end return t end
        Enum={GameRule={RPRuleset=1, PvPRuleset=2}}
        C_GameRules={IsGameRuleActive=function(rule) return rule==2 end}
    """)
    for relative in (
        "YUI/Libs/LibStub/LibStub.lua",
        "YUI/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
        "YUI/Libs/AceDB-3.0/AceDB-3.0.lua",
        "EllesmereUI/EllesmereUI_ClientGate.lua",
        "EllesmereUI/EllesmereUI_Lite.lua",
    ):
        lua.execute((ROOT / "AddOns" / relative).read_text(encoding="utf-8-sig"), "EllesmereUI")
    for name in ("EllesmereUI", "YUI", "GearInsight_Forever"):
        lua.execute((saved / f"{name}.lua").read_text(encoding="utf-8-sig"))
    lua.execute("""
        assert(EUI_CLIENT_FOREVER and not EUI_CLIENT_BLOCKED)
        assert(EllesmereUIDB.activeProfile=="Default")
        assert(not next(EllesmereUIDB.specProfiles or {}))
        local unit=EllesmereUI.Lite.NewDB("EllesmereUIUnitFramesDB", {
            profile={enabledFrames={player=true,target=true},frameSource={}}
        })
        assert(unit.profile == EllesmereUIDB.profiles.Default.addons.EllesmereUIUnitFrames)
        assert(unit.profile.player.showPlayerCastbar)
        assert(unit.profile.enabledFrames.player and unit.profile.enabledFrames.target)
        assert(unit.profile.frameSource.player=="eui" and unit.profile.frameSource.target=="eui")
        local raid=EllesmereUI.Lite.NewDB("EllesmereUIRaidFramesDB", {
            profile={visibleGroups={true,true,true,true,true,true,true,true}}
        })
        for i=1,8 do assert(raid.profile.visibleGroups[i]) end
        local yui=LibStub("AceDB-3.0"):New("YUI_DB", {}, true)
        assert(yui:GetCurrentProfile()=="Default")
        assert(yui.profile == YUI_DB.profiles.Default)
        assert(GearInsightForeverDB.keysHud==false)
        assert(GearInsightForeverDB.leveling.shown==false)
        assert(GearInsightForeverDB.qm.autoPlates==false)
    """)


def main() -> None:
    accounts = list((ROOT.parent / "WTF" / "Account").glob("*/SavedVariables"))
    assert accounts, "No saved account settings to inspect"
    for saved in accounts:
        for class_name in CLASSES:
            for faction in ("Alliance", "Horde"):
                check_account(saved, class_name, faction)
    assert not list((ROOT / "AddOns").glob("EUIStandalone*"))
    print(f"PASS: {len(accounts) * len(CLASSES) * 2} fresh character profiles; "
          "shared EUI/YUI settings and GearInsight overlap defaults. No WTF files written.")


if __name__ == "__main__":
    main()
