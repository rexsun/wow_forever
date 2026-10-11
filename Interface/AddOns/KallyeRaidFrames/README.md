# Kallye Raid Frames
_EN / FR / RU_

Modifications to Blizzards default raid/party frames according to my own preferences.  
All features are optional.

1._**Always show Raid frames**
- Works while solo ^^

2._**Changes to Blizzard CompactRaidFrames**
- Highlight unit background depending on health:
  - default from black, to yellow, then red
  - options to change colors and %
- Invert HP bars (less life = bigger red bar !) (sRaidFrames like)
- Skull icon added before dead players names. **(NEW)**
- Transparency of units out of range
- Roles icons
   - Move role icons on top left
   - Hides DPS role icons
- Buffs / Debuffs Size
- Buffs / Debuffs Max display limit
- Buffs / Debuffs relative position (alpha)
- Buffs / Debuffs alignment / multiline
- Target icons (💀❌🔴...) on raid frames

3._**Changes to both CompactRaidFrames and Nameplates**
- Removes servernames from the unitframe ( "Illidan (*)" instead of "Illidan - Varimathras" )
- Change players nameplate (on the head) color according to your preference (class color, custom color)
- Pvp Icons
- Show Players level option
- Health bar texture


## Slash Commands
**/krf** - shows options
**/krf test** - toggle test mode


**Known errors**  
- Classic / Mists: One error by session while changing Max (De)buffs setting, expected. Explicit warning added  
- Just after a boss kill, buffs & debuffs positions may flicker (back to Blizzard defaults until out of combat).  


## Example
![]( https://media.forgecdn.net/attachments/315/778/wowscrnshot_100520_184645.jpg )



https://www.curseforge.com/members/kaspou/projects

## License

Kallye Raid Frames is **All Rights Reserved** (see [License.txt](License.txt)).

The **buffs/debuffs** feature on retail uses code from **Raid Frame Auras** ([CurseForge](https://www.curseforge.com/wow/addons/raid-party-frame-auras)) by **Anahkas**, included under the [Apache License 2.0](Modules/RaidFrameAuras/LICENSE) in `Modules/RaidFrameAuras/`.

[LibEditModeOverride-1.0](Libs/LibEditModeOverride-1.0/LICENSE) is under the MIT License.