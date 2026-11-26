# Credits

## Quest data

`SeedData.lua` is generated from the database of the **QuestieDB** addon
(<https://github.com/Questie/QuestieDB>), maintained by the Questie team and its contributors.
QuestieDB's data was originally imported from Questie (<https://github.com/Questie/Questie>).
Both projects are licensed under the GNU General Public License v3, and so is this addon.

What was taken: for each quest, the items it needs (item objectives, required source items and
the item handed out when accepting it), plus each quest's name and race/class restrictions.
For items that start a quest, the quest they start. The data was read in game from QuestieDB's
public API (`LibQuestieDB`) by `/ydnt export` and converted by `tools/Build-SeedData.ps1`; the
exact QuestieDB version and export date are recorded in `SeedData.lua`.

This addon is not affiliated with or endorsed by the Questie team.
