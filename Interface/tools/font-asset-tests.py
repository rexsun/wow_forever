"""Run with uv run --with lupa --with fonttools python tools/font-asset-tests.py."""

from hashlib import sha256
from pathlib import Path

from fontTools.ttLib import TTFont
from lupa import lua51


ROOT = Path(__file__).resolve().parents[1]
INTER_KEY = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3Inter Black|r"
LONGZHU_KEY = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3龙珠|r"
OTHER_FONTS = (
    ("Inter Bold", "YUI Inter Bold.ttf"),
    ("Text", "YUI Text.TTF"),
    ("HOOGE", "YUI HOOGE.ttf"),
    ("胖娃", "YUI Damage1.ttf"),
    ("Dark", "YUI Dark.ttf"),
)


def main() -> None:
    lua = lua51.LuaRuntime()
    lua.execute('strmatch=string.match; function GetLocale() return "zhTW" end')
    lua.globals().bit = lua.table_from({"band": lambda a, b: int(a) & int(b)})
    for relative in (
        "YUI/Libs/LibStub/LibStub.lua",
        "YUI/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
        "YUI/Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua",
    ):
        lua.execute((ROOT / "AddOns" / relative).read_text(encoding="utf-8-sig"))
    lua.execute('YUI={}; STANDARD_TEXT_FONT="Fonts\\\\FRIZQT__.TTF"')
    lua.execute((ROOT / "AddOns/YUI/Core/Assets.lua").read_text(encoding="utf-8"), "YUI", lua.globals().YUI)
    lua.execute((ROOT / "AddOns/YUI/Media/Init_SharedMedia.lua").read_text(encoding="utf-8"), "YUI", lua.globals().YUI)
    fetch = lua.eval('function(key) return LibStub("LibSharedMedia-3.0"):Fetch("font", key, true) end')
    selections = [(INTER_KEY, "YUI Inter Black.ttf"), (LONGZHU_KEY, "YUI LongZhu.ttf")]
    selections.extend((" |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3" + label + "|r", source)
                      for label, source in OTHER_FONTS)
    assert {source for _, source in selections} == {
        file.name for file in (ROOT / "AddOns/YUI").rglob("*")
        if file.is_file() and file.suffix.lower() in (".ttf", ".otf")
    }, "Uncovered YUI font asset"
    for key, source_name in selections:
        path = fetch(key)
        assert path and path.startswith("Fonts\\"), f"Custom font must resolve to portable asset: {path}"
        asset = ROOT.parent / Path(path.replace("\\", "/"))
        source = ROOT / "AddOns/YUI/Media/Bundles/sharedmedia-fonts" / source_name
        assert asset.is_file(), f"Missing font: {asset}"
        assert sha256(asset.read_bytes()).digest() == sha256(source.read_bytes()).digest(), "Font face changed"
        with TTFont(asset) as font:
            assert all(ord(c) in font.getBestCmap() for c in "0123456789"), "Missing numeric glyphs"
    print("PASS: all seven YUI fonts resolve to portable, unchanged fonts with numeric glyphs")
    lua.execute('''
        frames={}; SlashCmdList={}; EUI_CLIENT_FOREVER=true
        function CreateFrame()
            local frame={events={}}
            function frame:RegisterEvent(event) self.events[event]=true end
            function frame:UnregisterEvent(event) self.events[event]=nil end
            function frame:SetScript(_, callback) self.callback=callback end
            table.insert(frames,frame)
            return frame
        end
        DAMAGE_TEXT_FONT="Fonts\\\\FRIZQT__.TTF"
    ''')
    applied = []

    def set_font(_self, path, _size, _flags):
        assert (ROOT.parent / Path(path.replace("\\", "/"))).is_file(), f"Missing damage font: {path}"
        applied.append(path)
        return True

    lua.globals().CombatTextFont = lua.table_from({"SetFont": set_font})
    lua.execute((ROOT / "AddOns/EllesmereUI/EllesmereUI_Startup.lua").read_text(encoding="utf-8-sig"), "EllesmereUI")
    accounts = list((ROOT.parent / "WTF/Account").glob("*/SavedVariables/EllesmereUI.lua"))
    assert accounts, "No EllesmereUI settings found"
    for saved in accounts:
        lua.execute(saved.read_text(encoding="utf-8-sig"))
        lua.execute('''
            for _,frame in ipairs(frames) do
                if frame.events.ADDON_LOADED then frame.callback(frame,"ADDON_LOADED","Blizzard_CombatText") end
            end
        ''')
        assert lua.globals().DAMAGE_TEXT_FONT == "Fonts\\YUILongZhu.ttf"
        assert applied[-1] == "Fonts\\YUILongZhu.ttf"
    print("PASS: EllesmereUI applies saved LongZhu damage font after saved variables load")


if __name__ == "__main__":
    main()
