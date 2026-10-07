# Talents Forever changelog

## 0.37.1
- The data as the site has it after the 3 Oct accuracy audit: 250 corrected talent and spell lines, the same words in the
  addon and on talentsforever.com. Nothing else changed from 0.37.0.

## 0.37.0
- More than one plan for a class on this character, like the game's equipment sets. A Druid at 26 asked for it from inside
  the addon, and a CurseForge comment asked how to swap to a second spec. A Plans button after your class in the window
  lists them, with New (an empty plan), Copy (the open plan again) and Rename. A click on a plan puts it on your trees and
  keeps the one you left as it was; Apply and the level-up card follow the open plan, and its name reads on the line
  beside the button. Eight a class at most. /talents plans and /talents plan <name>
  do the same from chat. Saved builds are as before: those are copies kept for every character, and opening one still
  lands in the open plan.

## 0.36.1
- Priest: Focused Casting is Martyrdom's own effect, not a trainer spell, and the reminders asked you to learn it. It is
  out of the list, and so is Mage Fire Vulnerability (Improved Scorch's).
- Druid: Aquatic Form comes from the level 16 quest, not the trainer. It is out of the reminders and the trainer page,
  and the book by level shows it at 16 marked "From a quest". A spell you already have under another id than the files
  give counts as known now, read off your spellbook's own names.
- Thunder Bluff has no Warlock trainer in the beta (a Warlock there told us), so Warlocks get no trainer card in it. The
  card has a Not here button for any other capital that lacks your trainer, and opening a class trainer window in that
  city puts the cards back, with a line saying so.
- The trainer card says what the spells cost, and when it lists something your gold does not cover it offers a button,
  Only what I can afford. Press it and from then on the card counts only what you can pay for, with one line for the
  rest, and stays away while nothing on the list is affordable; it comes when the gold does, if you are in a capital.
  The same switch is in Settings, off unless you turn it on. Prices come from the trainer window the first time you open
  one on that character; before that the card has no price to compare.
- Minimap: when LibDBIcon is loaded by another addon you have, the button is registered through it, so minimap button
  managers collect and place it with the rest. Same icon, clicks and tooltip, the Settings switch still hides it, and
  the spot you drag it to is kept either way. It is the library's round button then, not this addon's own look; without
  the library nothing changes.
- Train all: its switch has been in Settings since 0.34, and the button sits under the trainer window, below the game's
  own Train button, off the money display.

## 0.36.0
- Warrior: the Fury and Protection rework from Blizzard's 1 Oct notes is in the trees. It reached the game as server
  hotfixes on 1 to 2 Oct over build 70170, not in the client's files, so the Warrior trees here come from the hotfix
  cache as other readers logged it, checked against the notes. Fury gains Lingering Rage (row 2), Furious Precision
  (row 3) and Gore Drinker (row 6, under Enrage) and loses Improved Cleave, Boundless Rage and Precision. Iron Will moves
  to Protection row 1 and Toughness is gone. Flurry now follows Death Wish. Bloodthirst and Last Stand lose their
  arrows; those two rest on two readers of the hotfix cache and are not in Blizzard's notes, so if the game disagrees,
  say so. Improved Bloodrage, Anticipation, Improved Revenge, Improved Disarm, Vanguard, Improved Shield Bash, Focused
  Rage, Bastion, Improved Berserker Rage and Flurry sit in new spots. Bloodthirst deals 45% of your Attack Power at
  every rank. The other eight classes are as in 0.35.0.
- Links and saved plans from before still open on the right talents: Iron Will keeps its points in its new tree, a talent
  that is gone hands them back and the planner says so, and "Fill it in for me" offers the new ones. New links end in
  -6. Paste a -6 link into an older version of the addon and it will read wrong, so update.

## 0.35.0
- Beta build 70170 (1 Oct): the trees as the new client has them. Hot Streak is Heating Up and Soul Harvesting is Soul
  Harvest, same spots. Feral loses King of the Jungle and gains Shifting Power in row 4 under Shredding Attacks (which
  moves up to row 3) and Improved Shifting Power in row 5. Deflection, Redoubt, Holy Shield, Champion of the Light and
  Sniper Shot carry their new numbers.
- Links and saved plans made before this build still open on the right talents: a renamed talent keeps its points, a
  talent that is gone hands them back and the planner says so. New links end in -5. Paste a -5 link into an older
  version of the addon and it will read wrong, so update.
- The Fury and Protection Warrior rework in Blizzard's notes is not in this build's files yet; the addon follows the files.

## 0.34.6
- Settings: Open this instead of the game's talents. With it on, the game's talent tab closes again the moment it opens,
  however you opened it (the key, the micro bar, the spellbook's tab), and Talents Forever stands in its place. Hold Shift
  while opening it to get the game's window that once; a fight leaves it alone. A Hunter at 20 asked. Off unless you
  want it, and the older "The talents key opens this" switch still works on its own.

## 0.34.5
- "Fill it in for me" on a build from before the trees changed now judges by your spec, not your class: the pick rates it
  fills by come from the builds that lead in the same tree yours does, and a talent only comes back when the road to it
  (its new arrow, the row fillers) is one at least one in five of those builds take. Otherwise it is skipped, its points go
  where your spec puts them, and the card says which road and the rate. From u/Davajey, whose Enhancement build had been
  offered a cast-time Elemental talent. The same plan as the site for the same link.
- Pick rates on Shaman and Paladin tiles had two talents' numbers swapped since the Sep 24 patch (the daily refresh
  re-ordered a list that was already in today's order). Right again.

## 0.34.4
- The book by level now lists the trainer skills that sit outside the class spell lines: Dual Wield and Parry, for
  Warriors, Rogues, Hunters and Paladins. A Rogue at 9 asked. Warrior Parry at 6 was read in a Forever trainer's
  window; the others carry Classic's trainer level and say so until a Forever trainer confirms each one. They never
  turn into reminders, and at the trainer the window's own list still decides what is for sale.

## 0.34.3
- A Druid at 20 kept being told to learn Aquatic Form when it was already in the book: the game files list the form
  under one spell id and this character had it under another. A spell the character has under its name now counts as
  known, for the reminders, the trainer list and the book by level. Ranked spells still have to be the right rank.
- One reader's game froze on opening the class list at the top of the planner, with the game's own "action forbidden"
  warning pointing at the gamepad path the dropdown template uses. The planner now uses a plain class button instead
  of the game's dropdown while a gamepad is enabled, the moment the game blocks the dropdown once (it says so and
  remembers), or when you choose it in Settings (Game-style class list, off). Thanks for the trace.

## 0.34.2
- Hunters: Beast Training opens the same window as a trainer, and the addon put its Train all button on it. Those rows
  are the pet's, paid in training points, and the game blocks an addon from buying them, so the button raised the game's
  warning over and over and then claimed it had trained. No button on the pet's window now. At any trainer, a purchase
  the game refuses stops the run and says so instead of counting it. Thanks u/Squimbert.

## 0.34.1
- The Train all button moved: it now sits just under the trainer window, below the game's Train button, instead of
  beside it where it grew over your money once it showed a count and a price. Two of you wrote in about that.
- Settings: Train all at the trainer can be switched off. With it off the trainer window is the game's own, and
  /talents trainall still buys the lot.
- A Hunter on 0.33.0 hit an error in the emblem pulse when a build reached full points. Guarded.

## 0.34.0
The beta keeps moving talents, so a build from before a patch can carry points the game no longer takes.
- Load one and it settles to today's trees: the points that no longer fit come back to you, the talents they left are
  ringed in orange, and a card says what moved and why.
- Press Fill it in for me and it puts them back where the rules allow, tells you where each point went, and Undo is
  right there. Popular only lists builds the game takes now.
- Nothing you saved is changed. A build only settles on the screen when you load it.
- Also in this update: if you pressed Follow the top build before 0.32, "Place points for me, no asking" was still on;
  it is off now and a card at login says so. German and other non-English clients get the trainer card in the six capitals,
  with prices kept. The PvE or PvP mark's tooltip says the mark stays on this computer. Popular's header counts builds.

## 0.33.0
The trees now match beta build 70009, the 24 Sep patch.
- Paladin: Improved Holy Strike and Crusade are gone. Druid: Mangle is now Primal Bite, Primal Fury is Blood Frenzy.
  Shaman: Elemental Alacrity is in row 3, Elemental Fury in row 6. Plus the number changes from Blizzard's notes.
- Your saved builds and any link from before still open on the right talents.

## 0.32.0
Everything in here came from notes sent from the Feedback page. Thank you.
- Follow the top build asks before every point now. It used to switch on hands-free placing by itself, and one Warrior
  paid 2g for that. Sorry.
- The reminder card can be dragged anywhere and stays there. Settings puts it back.
- Settings: the talents key can open Talents Forever. Your key bindings stay as they are.
- Hover a spell in the book and it says how much of your spell power it uses.
- Replies. Under the Feedback box, every note that turned into something and what happened to it. Send a note from
  here and the answer shows up under it.

## 0.31.3
- No more build cards for people you only walk past. Some addons inspect everyone under the mouse (item level
  tooltips do), and each answer put up a card for that person's build. A card now comes only from /talents inspect,
  the Inspect button in the window, or the game's own Inspect window. Thanks u/Diamond-Intelligent.

## 0.31.2
- Try it (was Compare). No more small numbers in the tile corners: Try it rings the talents a build takes on your
  trees, over your own points, so you see where it differs; the footer says how many points you share and offers
  Load it and Stop. Load is still the one that makes it your plan, with Undo.
- Clear, in the footer. One press takes off whatever was switched on for a look: a tried build, a level view, the
  trainer or spellbook list, the search, and lands on Home. The plan is not touched; Reset is the one that empties it.
- Undo is a footer button of its own now, lit when there is something to bring back. The Undo on a footer note is gold.
- The trainer and spellbook list has a Move left / Move right button, a filled top bar with a drag mark, and can be
  dragged anywhere by it; Snap back sets it beside the window again. The side is remembered.
- Popular builds come from the site's live list (13 to 22 Sep so far), not the pre-beta file.
- The Copy buttons are called Select now, and a line under the link says the rest: Select, then Ctrl+C. No addon
  can copy to the clipboard, the game does not allow it, so the button selects the whole link and that key is yours.
- The paste box's gold glow no longer shows through the Phone QR sheet.
- The window opens about 30 percent smaller the first time. Tooltips at 80 percent.
- Settings: a slider for the window size, one percent at a time, next to the arrows. Both bottom corners of the
  window resize it now; the top stays put. Placing points on level up starts off (older saves are set off once,
  unless Follow the top build is on).
- A side-panel row's tooltip sits to the right of the window now, where nothing is written; over the trees only
  when the screen ends on the right.
- Import lands on Load a build with the paste box lit gold for a moment, and the footer says what to do.
- The rail: when the level being looked at is close to yours, the word you steps aside so the number reads.
- Feedback: the one thing to do is a purple line, "To send it: Ctrl+C, then paste the link in any browser", with a
  Copy button beside the link.
- The minimap button is the book in a dark disc with the gold ring, like the corner of the window.
- The title is in the site's Cinzel, bold, 16 px, drawn by the addon itself over the game's title string. The window is built and laid out half a second after login, so the first
  open from the minimap, the character pane or /tf is as quick as the second.
- The footer's buttons pull their padding in when the row is full, so Import never runs past the edge. The bottom-left
  grip is the right one mirrored, pointing out into its corner.
- /tf is ours outright now, no longer stepping aside when another addon has it. A Settings switch for the book tab on
  the character pane, next to the one for the minimap button.
- For the person shipping it: addon/tools/daily_data.py builds a dated zip when the site's popular list changed and
  uploads it with addon/tools/cf_upload.py; .github/workflows/addon-popular.yml runs that daily once the CurseForge
  token is a repository secret.

## 0.31.1
- One look. The Look like talentsforever.com switch is gone; the window is always the dark glass one with the game's
  own art. It was easy to tick by accident and made the addon look like a different one.

## 0.31.0
- Tooltips: one plate behind the words, at 60 percent, so the tiles under it still show where you are; the game's own
  fill steps aside while ours is up. A talent's tooltip goes to the tile's left rather than lie over the side panel.
- Compare (was Ghost): nothing happens on hover; press Compare and the build's points sit in the tile corners as small
  gold numbers, the footer says what they are and offers Stop comparing.
- Builds page in three blocks: Share this plan (Copy, Phone QR, Party, Guild, To target), Load a build (Inspect target
  on the title line), Saved builds (compact rows, three showing, the count in the title), and a Popular builds card at
  the foot with the five most shared, one click to load.
- The trainer drawer: The list on Home opens a panel off the window's edge, learn now with the price, later with the
  level, already in your book. The Spellbook chip in the header opens the same drawer as the whole book by level.
- Settings in four groups with an icon per row and one plain sentence each; a Settings button in the footer.
- Footer buttons in one even chain. The site link is gold with a small book. Clear ghost sits in the status line.
- Races: all ten Forever races as the client's own faces, yours first; the ones that cannot be this class dimmed.
- Coach: three cards. Feedback: one screen; Send makes the link, selected, that lands on a one-line Got it page.
- The rail marks your level with a gold diamond and the word you; hover a level and what the plan gains by then pulses
  gold. Hold Ctrl on a talent to read the spell it changes. Hover a tree's name for the site's share.
- Minimap button on the rim. The window is built after login so the first open is instant. Gold X beside the gear.
- /talentsforever and /tf (where no other addon owns it) open the window too.

## 0.30.1
- Compare to Classic marks edges only; the greying of unchanged tiles is gone. Tooltips get a solid plate. The trainer and spellbook drawer, the minimap button on the rim, the window built at login, popular builds on the Builds page. This is the build to install.

## 0.30.0
- Tooltips follow the site's one rule, so the hand learns it once. A talent's opens just off the tile, level with its
  top, the way the game and Wowhead place it, and flips to the tile's other side when the screen ends. Anything on the
  side panel (a plan row, a build, a checkbox, a button) opens level with it just outside the panel, over the third
  tree, so the list you are reading stays clear and the tooltip is never off at the far edge. A box or button in the
  header opens under itself, never over what you are typing or pressing; the footer's open above. Nothing is ever
  cut off by the screen.
- Hover a build on Popular or Builds and its points are laid over your trees while the mouse is there, at full size,
  where the eye already is; the small picture beside the row is gone. Ghost keeps it on the trees, Load makes it
  your plan.
- Races shows every race this class can be, as a row of faces with yours first and lit. Click a face for that race's
  racials and the class racials it gets. A Paladin can read what a Dwarf would give before rolling one.
- Coach speaks in cards, a headline and a line under it, from the site's numbers: the shape of the plan against what
  the class's players build, how many points match the #1 build and which talents differ, a talent most players
  take that the plan skips, what in the plan is new or changed since Classic, the deepest talent and the level it
  lands, and the next point with its reasons. The trainer's list follows the cards.
- Feedback: a button in the footer opens a page to say what would help. The game gives an addon no way to send
  anything, so the note becomes a link (and a code for a phone); pasted in a browser it lands in the site's ideas
  inbox with the addon's version, the class and the level in front of the words. Your character's name is not in it.
- Home: the level box says whose level it is and how far to the next, the strip's sentence wraps instead of being
  cut, four points after the next one, and the two tree switches (Classic marks, pick rates) at the foot of the page
  where they can be seen. Words a size up across the side panel; section titles too.
- The phone code takes the whole Builds page, big enough to read from across a desk, with Back at its top.
- Clear ghost sits with its sentence in the status line instead of crowding the button row.
- Since Classic, the next point and the level box read as one system: headline in colour, body in plain words.

## 0.29.0
- The best of the three looks in one window, the way the poll on the site asked (the game's style 58, the site's 17):
  the dark glass window with the game's own talent art is the default; the site look stays a switch in Settings.
  Cinzel for the window's title and the build's name, the site's one visible tie.
- Tooltips, one rule per thing. A talent's tooltip opens level with the talent and just outside its tree, so the tree
  you are working in is never covered and the eye stays on the row it was reading; it flips to the other side rather
  than land on the plan list. A row on the side panel that lights a talent opens its tooltip beside the whole window.
  Nothing opens over what is under the mouse. The talent's icon leads its tooltip.
- Hover a talent and the chain shows: the talent it needs and the talents it unlocks light up, arrows and all.
- Home, without the second set of buttons: the page buttons that doubled the tabs and the footer are gone. The room
  goes to the five points after the next one and a Since Classic line (new, changed, moved, gone) that opens the
  Classic page. The next point stays on the featured card. Compare to Classic is set on the Classic page alone.
- Every tree's header carries the site's thin gold bar that grows with the points in it.
- A saved build names the character that saved it when it was another one.
- The level bar's percentage sits on the bar, not under its fill.
- The data table's global name is the addon's own (TalentsForeverBookData), so no other addon can overwrite it.
- From Chris's in-game shots: the point labels in the header stood clear of the points box by too little for the
  game's font; the Popular page's build picture and its words now open beside the window, not over the trees; the
  Builds page is three plain blocks (this plan, load a build, saved builds) with no button on a header line; the
  strip on Home wears the class crest, so the next talent's icon shows once; the leveling rail can be switched off
  in Settings and stands down by itself at level 60, making the window shorter.
- Buttons answer the mouse: the words go white on hover and the plate's wash comes up, the words dip a pixel while
  pressed.
- Nothing is said twice: an empty plan no longer repeats itself down the Home page, a plan for another class says one
  thing on the strip and another in the footer, and the level 60 card speaks of points earned, not placed.

## 0.28.0
- The site look, on by default: talentsforever.com brought in game. Its colours (the #121212 page, #1e1e1e panels, the
  #3a3a3a line, its gold), Cinzel for the headings, the emblem in its gold ring with the class name beside it, the
  site's tree headers with the gold fill bar, its tiles with the black rank badge and a green edge on a talent you
  can take, its grey buttons with white words and the one gold button. The glass look from 0.27 stays: Settings,
  "Look like talentsforever.com", or /talents look glass, then /reload.

## 0.27.0
- Home, the hub, first tab and the page the window opens on: the featured build (a band of your class's own painting,
  the build's name in its colour, a progress bar, the next point), one strip for the thing that needs you now with the
  button that does it (unspent points and Learn it, spells at the trainer with the price and See the list, no plan yet
  and Popular, every point placed and Share), this level's progress with what the plan places at the next one, and a
  grid of buttons with pictures to every page. The Plan page is rows only again. Classic moved off the tab row into
  the grid.
- Its own look: the window is dark glass with one bronze line and corners cut at an angle, the book sits as a medallion
  on the top-left corner, the pages sit in a framed pane, every button is a dark plate with a bronze edge (gold for the
  one that acts on your character). The game's own pieces stay where they are better than ours: the talent node art,
  the class paintings, the dropdown, text boxes, checkboxes and tooltips. New image files: restart the game once.
- Saved builds take a PvE or PvP mark (click "mark" on the row). The mark stays with the build.
- Bars move: the level bar and the build bar ease to their new value instead of jumping.

## 0.26.0
- The addon's folder is now TalentsForeverBook (was TalentsForever), its saved data TalentsForeverBookDB, its commands
  /talents and /tfb (was /tf). Another author's addon on CurseForge uses the old folder name, saved-data name and /tf, so
  the two overwrote each other; now they can sit side by side. Nothing else changed in how it looks or works.
- The level-up card has a Not again button. Level-up reminders stay on by default (the poll on the site said keep them,
  59 to 17); one click turns them off, Settings turns them back on.
- Trainer reminders stay off by themselves while What's Training is installed, until you set them yourself.
- /tf still works when no other addon has claimed it; with the other TalentsForever installed, ours answers to /talents and /tfb.
- First open: a three-step walkthrough in the footer (Next, Skip, Done), no popups. /talents intro replays it.
- /talents probe now records the trainer window's functions, which neighbour addons are loaded, and prints a test chat link.
- Prices: every price seen at a trainer is remembered for that class, so the Coach page and the trainer card can say
  what the owed spells cost for any class once one character of it has visited a trainer (from the ideas page: trainer prices).
- Your group's builds: the Popular page starts with the builds people in your group sent (Ask for their builds, or a
  build they shared), each with Ghost, Load and a mini tree; nothing is posted in chat (from the ideas page: sync with
  the builds of the people you play with).
- Saved builds list your own class first and remember which character saved them.
- The look, a step up: the Plan page opens with a hero card (a band of the class's own painting for your lead tree,
  the build's name in its class colour, a progress bar, the next point with its icon and level); section rules on the
  Builds and Coach pages; the footer buttons carry pictures (the next talent on Apply next, your class crest on From
  character, the book on Share, a scroll on Import); Coach rows show each spell's price; the class crest in the header
  is the game's own class icon.
- Detail pass: a talent's tooltip opens beside the window, never over the tiles next to it; the level arrows stand
  clear of the points box; the level-up card goes away when the window opens; scrolling pages fade at the foot
  while there is more below; the Popular and Classic pages use the same section rules as the rest; the hero card's
  next line lights its tile on hover and shows its tooltip; even row gaps on Races and Coach; one space between
  sentences in the footer.
- The TOC lists only the Forever client (16001), so the CurseForge packager tags the file Forever and nothing else.

## 0.1.0 (first build, not yet published)
- The site's three trees in game, same rules and share links as talentsforever.com.
- Plan without spending a point; your real talents shown beside the plan.
- Leveling plan in the order you placed points; a level-up card says what to take.
- Apply the next planned point when the client allows it.
- Share, import, saved builds, popular builds.

## 0.2.0
- Resizable: drag the corner grip, drag the header to move; both remembered. /talents scale, /talents center.
- Side panel with tabs: Plan, My builds (save, load, delete), Popular, Classic, Racials.
- Ghost: lay any saved or popular build over your trees; gold numbers show its points next to yours, the footer counts what you share.
- Compare to Classic on the tiles (gold new, blue changed, purple moved) with the Classic text in the tooltip; list of talents gone since Classic.
- Pick rates from the site on the tiles, on request.
- Racials for your race and class, plus the class ability notes.
- The ringed book emblem in the header, the minimap button and cards.

## 0.3.0
- Apply all: places every unspent point in plan order (rebuilds a build after a reset in one click).
- Optional hands-free leveling: place my points for me on level up (Plan tab, off by default).
- Motion: trees fade in one after another, tiles lift on hover, tabs fade, the points counter pops, a slow light passes over the title.
- Racials and Classic text no longer overlap.

## 0.4.0
- The path: a gold thread through the tiles in plan order, bright where you have been, faint ahead, a pulse on the next point.
- The journey bar: level by level across the bottom, hover a tick for the talent, click to find it.
- Goals: an empty plan asks where you want it to go and offers the top build per spec, to take or to ghost.
- Calmer clicks: a ring settles on the tile, no burst.

## 0.5.0
- Shift right click on a tile gives the real point back on your character, when the client allows it.
- Remembers which Blizzard talent window this client loads, so the addon can sit on it later.

## 0.6.0
- Level-up companion: the card and the plan rows say what the trainer should have for you at that level; the footer names the next trainer level.
- Send a build to your party, raid, guild or a player from the Share window. Anyone with the addon gets a card to ghost or load it; everyone else gets the link.
- Grey buttons now say why on hover. Goals opens any time. From character asks before replacing a plan.

## 0.7.0
- The layer over the game's own talent window: your plan's numbers on its tiles, the thread in your order, a pulse on the next point, a ghost beside yours. Toggle in the Plan tab.
- A book tab on the character pane, under the other side tabs, opens the planner.
- Coach tab: reads the plan and says what it sees (deepest talent and when it lands, split starts, rare picks, skipped favourites, half-filled talents, the ghost, your character).
- Apply all stages every point and applies them with one commit, the way the window's Apply does. Commit failures are reported.

## 0.8.0
- The tome. The window is drawn from our own art now, not Blizzard's stock backdrops: a dark leather cover with gold tooling and corner fleurons, a grained page with a vignette, a fold between the trees and the side panel. Every card, sheet and toast wears the same cover. Generated by addon/tools/art.py from the site's palette.
- Trees sit on the page without boxes; the paintings melt into the page at their edges, a gold hairline between columns.
- Tiles: the site's square slot, a rim that goes green as you fill and gold when maxed, a soft glow behind maxed talents, gold ink when a point lands.
- The side panel's tabs are ribbons hanging from the rule; the open one is gold and a little longer, and swings when picked.
- The level is a seal in the header, breathing softly; the masthead has the site's warm glow behind the title.
- Buttons are the site's pills, one gold primary (Apply next). Close buttons and the resize corner are ours. Ctrl and the mouse wheel scale the window anywhere on it.
- The path is a real thread (soft edges, brighter core) and a spark runs it from the first level to the last, over and over. The journey rail is the same thread.
- Motes: a few slow sparks drift up the page, the book's own glow. Plan tab switch.
- A crisp small book for the character pane tab (Media/book-tab.png): tighter crop, no haze, sharpened.
- Journey labels no longer touch the status line; the content clears the cover band.
- Needs a full game restart once (new images), then /reload is enough.

## 0.9.0
- Plan any class: a Class pill in the footer opens a card with the nine classes, like the site's class tabs. Each class keeps its own plan on the character; switching back brings the old plan back untouched. Apply only ever touches your own class.
- The thread no longer cuts across the tiles when the plan hops to another tree: the hop is an arc over the tree headers, dimmer than the thread inside a tree. The spark follows it.
- The stock scroll bars are gone from the side panel; a thin gold line on the right says where you are, the wheel scrolls.
- Checkboxes are ours: a small slot with a gold rim and tick.
- The blue "0" badge no longer sits on every planned talent; the character's real rank shows only where it has a point.
- Prerequisite arrows in the page's own ink instead of grey.
- A touch more leather on the cover so the frame reads as a book.
- Restart the game once more for the cover (an image changed); Lua changes alone would only need /reload.

## 0.10.0
- Motion, rebuilt from the site's own rules. A point landing is the site's flash: a gold halo contracts onto the tile while a glow behind it fades, and the rank pops up white and settles back to its colour. Taking a point back dips the tile and lets a thin ring go. No more bump and blur.
- Tiles grow in place under the mouse, eased, instead of snapping and sliding.
- The side panel turns its page: the old page folds away to the left, the new one unfolds from the same edge. Rows arrive one after another, rising into place.
- The window opens like the book: a fade, a touch of scale, a lift.
- Each tree header carries a gold fill bar that grows with the points in the tree. The journey's gold grows instead of jumping.
- The next point breathes slowly (the site's 2.8 second breathe) and keeps breathing across clicks.
- Two soft lights drift behind the book in the header; the book breathes under the mouse and pulses when a talent is maxed.
- Motes are smaller and slower, a short rise, like the site's.
- Under the hood: a tween engine (Motion) beside the animation groups, and a preview harness (addon/tools/preview) that runs the addon on a WoW simulator and draws it in a browser, frame by frame, so motion can be watched without the game.
- /reload is enough: no new images in this build.

## 0.11.0
- Simpler. The grain is gone from the page and the cover, the vignette is lighter. No motes, no mist, no light passing over the title, no running spark, no pulsing on open tiles, no breathing seal or ribbon. What stays: the landing flash, tiles growing under the mouse, the page turn, the fill bars, the breathing next point.
- Bigger text everywhere: rows, tree names, ranks, the header, the footer, the pills.
- A refusal (max rank, row not open, prerequisite) is a gold line in the footer for a few seconds, not a card.
- The toast is a small line at the bottom of the screen instead of a card at the top. Level-up cards keep their buttons.
- The header loses its second line.
- Restart the game once for the page and cover images; after that /reload.

## 0.12.0
- Undo. Reset and From character replace the whole plan, so their toast now carries an Undo button for eight seconds. Loading a build remembers the plan before it too.
- Reset on an empty plan just says so; Reset no longer pops the Goals card.
- The tile tooltip says when your plan takes the talent ("In your plan: levels 14 to 18") and marks the tile your next point goes to.
- Compare to Classic marks are off until you turn them on in the Classic tab, as on the site. Cleaner tiles by default.
- Plan rows lose the small trainer glyph; the talent name gets the room. The trainer still shows on the row's tooltip, in the footer and on the level-up card.
- The panel button says Hide panel or Show panel.
- /reload is enough.

## 0.13.0
- The lines through the trees are gone, on our window and on the game's talent window. The next point breathes, the plan list and the journey carry the order. The path checkbox is gone with them.
- Each tree header says when its next row opens ("next row in 3") or that all rows are open, like the site.
- The header counts what is left ("POINTS PLACED · 11 LEFT").
- Slash commands that do the work: /talents next and /talents all place planned points, /talents save <name>, /talents builds, /talents open <name or number>, /talents undo.
- A key binding for "Apply the next planned point", under Talents Forever in the game's key bindings, so a level up can be answered with one key.
- The plan note is one line.
- /reload is enough.

## 0.14.0
- Settings in one place: the gear next to the close button opens a card with level-up reminders, hands-free placing, the layer over the game's window, sounds, the minimap button, Classic marks, and the window size with a centre button. The Plan tab is just the plan now.
- A saved build is a link: click its row in Builds and the share sheet opens for that build, with the party, guild and whisper buttons sending it, not the open plan.
- /talents find <part of a name> opens the window, lights the tile and shows its tooltip. /talents settings opens the card.
- The Coach reads the build level by level: what you have at 20, 30, 40, 50 and 60 and how deep each tree goes by then.
- /reload is enough.

## 0.15.0
- Fewer buttons. The footer is Apply next, Apply all, then From character and Reset, and Share, Import on the right. Class moved to the header: the class name under the title is the button. Goals lives in the empty plan's card and the Top tab. Hide panel is gone; the side panel is part of the window.
- Less text. The header keeps one line of words and one number with one label. The side panel drops its label and its note. The plan is just the plan.
- Less colour. Planned talents are gold and grey; nothing on the trees is green any more. Paintings and pill outlines sit back a step.
- Shorter tab names (Top, Races) so nothing clips.
- Rows give the talent name more room. The toast sits higher, clear of tall action bars.
- /reload is enough.

## 0.16.0
- Tooltips sit beside what you point at, the way the site places them: to the right, pushed in from the screen edge, flipped left only when they would cover the thing itself, never off the bottom. Rows in the panel put theirs beside the window, so the tile they light up stays in view.
- The footer has air: the rail, the level marks, the status line and the buttons each get their own line, and the trees no longer touch it. "you, 12" sits above the rail, the count sits at the right of the status line.
- Top tab rebuilt: one line of context, rows whose name has the first line and whose numbers and buttons share the second, then "Almost everyone takes" and "Almost nobody takes" as lines you can point at, each lighting its tile. Everything scrolls together.
- Builds rows use the same two-line layout; the class and date moved to the row's tooltip. Loading a build, saved or popular, has Undo on its toast.
- Toasts are as tall as their words, with the buttons on a line of their own.
- Coach, Races and Classic rows size themselves for the game's wide font.
- The tile tooltip's click hint shows only until the plan has five points.
- /reload is enough.

## 0.16.1
- Build codes v3: share links a third the length, the same codes the site writes since 18 Sep. Older v1 and v2 links and codes still open.
- /reload is enough.

## 0.17.0
- Rank badges have a hairline border in the tile's state colour, like the site's, instead of a bare black box.
- Locked talents are solid dark grey instead of see-through, so the painting no longer bleeds into them. Open talents get a warm rim that reads apart from locked ones.
- The tree paintings sit at strength, each tree is a panel with a gold hairline, and the loose separators are gone. Tree header icons get the same hairline.
- Checkboxes are a dark box with a gold hairline and a gold tick.
- "you, 1" stays inside the rail at either end.
- Classic tab sits tighter.
- /reload is enough.

## 0.18.0
- The level does something now, and never destroys anything. It is the level you are looking at: the trees show your build as it stands there, points above it wait their turn and come back as it rises. Roll the wheel on the seal or the path, press - and +, click any mark on the path, or click the number to jump between your level and 60. Before, lowering the level threw points away for good.
- The path shows the abilities worth waiting for: the ones your plan buys and the class's well-known ones from the trainer, each at its level, lit once the level you are looking at reaches them. Your character sits on it as the class crest. A gold pointer marks the level being looked at.
- No more cards over the trees. Classes open in the header, in place. Settings are a page of the side panel behind the gear. Share and Import are part of the Builds page: this plan's link ready to copy, send to party, guild or a name, paste a link to load one. The starting-point card is gone; an empty plan opens on the popular builds. From character no longer asks first, it has Undo. With the window open every message is a line in the footer, with Undo or Learn it beside it when there is something to press; cards are only for when the window is closed.
- The class crest sits in the header beside the class name. The header line says what the build is ("Frost Mage, 0 / 0 / 10").
- Top tab: who plays what ("Fire 37%, Frost 34%, Arcane 29%"), and each row's tooltip says what stands behind it: shares, saves, opens, and how many close builds it speaks for. Data follows the site's family ranking of 18 Sep.
- "Mark the tiles" is "Compare to Classic".
- Motion is shorter and sharper everywhere: hover, landing, page turns, rows, bars, opening.
- The book in the header is the whole brand book, resampled cleanly, with a soft glow. This one file needs a game restart to show; everything else is /reload.
- Fixed: the Centre button in settings did nothing.

## 0.19.0
- Phone QR: the Builds page shows this plan's link as a QR code. Point a phone's camera at it and the same build opens on talentsforever.com. Made in the addon, checked against a real decoder for links from 31 to 265 characters.
- talentsforever.com signs the footer, quietly, beside Share. Click it for the link and the code. The Popular page says where its numbers come from by name.
- The lead tree wears the class colour, points and bar, the way the site does it.
- Tabs say what they are: "Top" is "Popular", and each ribbon is as wide as its word.
- The Plan page has one line saying what the list is. Click a line and the trees show the build at that level.
- While you look at a lower level a "Show all" pill sits in the footer. One click and the whole plan is back.
- The class name has a small arrow, because it opens. The window's close and settings sit inside the page, off the corner ornament, and settings is drawn as sliders instead of a muddy icon.
- The first time the window opens, one line says how it works. Placing the last point of a build gives the book a pulse and offers Share.
- An ability on the path gives a small bump the moment the level reaches it. The book's glow breathes.
- The coach's level-by-level note reads as lines, one per ten levels.
- /reload is enough (the 0.18 book art still wants one game restart if you have not restarted since).

## 0.20.0
The grid pass. Everything measured, then set on one set of numbers.
- Buttons hold their words alike: every button is as wide as its words plus the same padding either side (16 for the tall ones, 12 for the small), where before the footer's ran from 11 to 18. Gaps between buttons are 8 everywhere, 24 between groups. The words dip a pixel while a button is held.
- Every page of the side panel starts on the same left edge (12) and ends on the same right one. The ribbons start on that edge too and hang from the header's rule.
- The talent grid is centred in its tree (it sat 16 from the left, 28 from the right), with 12 under the header line and as much under the last row. Tree headers are 44 tall with a quiet band behind them so the title reads over any painting.
- The header sits on one line through the middle of the book and the seal: title and class row centred on the book, the minus and plus as true circles with drawn glyphs centred on the seal, the points block centred on the same line.
- Nothing sits on a half pixel any more: the class row, the 51 marks of the path, the ability icons and the list offsets are all on whole pixels, so they draw sharp.
- List rows are 50 tall on an 8 grid, their small buttons 20 tall; controls on the Builds page are all 24 tall with one rhythm between them.
- /reload is enough.

## 0.21.0
Buttons, rebuilt. The old ones were thin outline images stretched to each size, so their line weight was never the same twice and they had no body: they read as pencil sketches.
- Every button, tab and close is now a plate built from crisp rectangles: each edge exactly one pixel on every button at every size, corners rounded by one pixel, a body that runs from light to dark, a lit top edge, a dark bottom edge and a line of shadow underneath. Gold trim and a wash of light under the mouse; the body turns over and the words dip while it is held; a flat grey plate with grey words when it cannot be pressed (before, a disabled button was the same button at 40% see-through).
- The one action that matters, Apply next, is a solid gold plate with dark engraved words.
- Two heights only, 24 and 20. Widths sit on an 8 grid with a floor, so neighbours match: Reset, Share and Import are all 80, Load and Ghost are both 64, Party and Guild both 56.
- Words are a size larger (13) with a shadow, so they read as part of a solid thing.
- Tabs are plates standing on a rule, the open one gold, replacing the stretched ribbon images. The close and the settings control are small plates; the close carries the title face's X. The minus and plus by the level are plates too.
- The Builds page's phone code is a real button now, and its send row is four matching small plates.
- /reload is enough. No new image files.

## 0.22.0
- The path shows abilities all the way to 60. It looked empty from 40 up because the ability list behind it only had levels for spells with ranks, so single-rank abilities (Blink, the Portals, Whirlwind, Recklessness, Divine Shield, Feign Death) had no level at all, and my hand-picked names were mostly pre-40. The addon now reads the full trainer table from the beta client's files: a level for every trainer-taught class spell, with the leftover Season of Discovery spells filtered out.
- One marker per level, standing for everything new at that level; a small gold pip says there is more than one thing, and the tooltip lists it all. Hover any mark on the path and it also says what the trainer has at that level.
- Trainer lines everywhere (footer, level-up card, plan rows) know three things they did not: rank 1 of a talent ability comes from the talent, not the trainer; later ranks of a talent ability only count if your plan takes the talent; the Priest's racial spells only count for your own race.
- Checked against Wowhead's Forever database: 324 trainer unlocks from level 8 to 60 compared, the levels agree. Two spells our files list and Wowhead does not (Mage Felfire, Hunter Black Arrow) are held back until a trainer shows them.
- /reload is enough.

## 0.23.0
The game's own look. The window is now built from the parts the game builds its own windows from, so it reads as part of the game. The site-style version before this one is kept whole in addon/versions/0.22.0-site-style.
- The window is the game's frame: its metal edge, its title bar with Talents Forever in it, the book as the round portrait in the corner, the game's red X. The settings cog is the game's small gold one, in the title bar beside the X. The resize corner is the game's size grabber.
- Every button is the game's red button (22 tall, 20 in rows). The level steps with the game's page arrows, like a spellbook page. Settings and the Classic page use the game's checkboxes, and their words click too. The boxes you type in are the game's input boxes.
- The class picker is the game's dropdown, the nine classes in their colours with their crests. A pick closes the list.
- The side panel's tabs are the game's tab art (the dark tab, the lit one for the open page), standing on the game's inset panel, with the game's tab sound.
- Every word is in the game's face with its one-pixel shadow; gold and white are the game's own gold and white.
- The level-up card outside the window wears the game's tooltip border.
- Nothing of the game's art is in the addon: every piece is asked for by name, so it follows whatever art the client ships. Where a client lacks a piece, the addon's own plate stands in, so the window always opens.
- The header is one slim row under the title bar; the window is 58 shorter for the same trees, and the side panel 20 wider.
- American spelling in the two places a player could see the other kind.
- A new template or art name needs only /reload.

## 0.23.1
- The side panel's tabs: the words sat too high, against the top edge with empty tab under them. The top 8 of the game's tab art is only its shadow, so the word now sits in the middle of what the eye sees (where the game's own top tabs put it), the lit tab stands a little taller with its word raised, and its top lines up with the top of the trees. The words are padded by 20 like the game's. The pages gained the 5 the tabs gave up.
- /reload is enough.

## 0.23.2
What the trainer really sells. On 18 Sep 2026 the Stormwind mage trainer's whole list was recorded in the beta (158 rows through level 60): every level the addon had matched, and the list settled what the game's files cannot, which spells a class trainer does NOT sell.
- Mage: 25 ranks are no longer announced as new at the trainer. The six teleports and six portals now say (portal trainer). The tome, quest and drop spells (Arcane Brilliance, Fireball 12, Frostbolt 11, Arcane Missiles 8, Conjure Food 7, Conjure Water 7 and 8, Frost Ward 5, the Polymorph animals, Chilled) are left out of the trainer lines on the path, the footer and the level-up card.
- Comprehend Scroll, a new Forever spell the mage trainer sells at level 6, is on the path.
- The other eight classes get the same treatment as soon as one of their city trainers is recorded. Their levels were checked a second way meanwhile: against Wowhead's trainer lists (which turned out to be the Classic lists), no level differs in any class.
- /reload is enough.

## 0.24.0
What readers asked for on the addon's ideas page and in the poll (19 Sep 2026).
- The trainer, for real. The addon now asks the game which spells your character knows and compares that with what the trainer sells at your level. When you level up, or walk into a capital city, a card says "3 spells waiting at your trainer: Frostbolt (rank 4), Blink, Frost Ward" with a button to see the whole list. Once per level and place, so it never nags. The Coach page opens with the same list, /talents trainer prints it, and the Settings switch "Trainer reminders" turns the cards off.
- Build links in chat. Any talentsforever.com build link that appears in chat becomes a clickable link for everyone running the addon: it reads [Mage 31/20/0, level 60] in gold, and a click lays that build over your trees with a Load button. Shift-click a saved build, a popular build or the link box to put your own link in the chat box, the way you would link an item.
- Which spells a talent changes. Hover a talent and the tooltip says "Changes Frostbolt, Ice Lance and Cone of Cold" (u/Fluxraw's idea). The names come from the talent's own words.
- Send an idea. A button on the Settings page shows a code for talentsforever.com/ideas, where the addon poll and the note box live.
- /reload is enough.

## 0.25.0 (in progress: the ten ideas from other addons, one at a time)
- Skip a trainer spell. The Coach page now lists what the trainer has for you as rows, one spell each. Skip on a row keeps that rank out of every reminder, for this character only, the way What's Training and Class Trainer Plus let you ignore a spell. Skipped rows sit dimmed at the bottom with a Back button. The row's tooltip is the spell's own.
- /reload is enough.
- Train all. The game's trainer window gets a Train all button beside its own Train button: "Train all (3, 1g 40s)". One click buys every spell the trainer has for you that you have not skipped, one after another, in the trainer's order, and a card says what it cost. Its tooltip lists each spell with its price, what you skipped, and what your money does not cover. The way Class Trainer Plus does it with shift-Train. /talents trainall does the same from the keyboard.
- What it costs. Where a class's city trainer has been recorded with the Check addon (Mage so far), every rank carries the price the trainer asked. The Coach page header says "AT THE TRAINER, 5 YOU CAN LEARN NOW, 1G 40S", each row's tooltip says its price, and the level-up and city cards carry the total, so you know whether the trip is worth it before you go. The way What's Training shows it. Other classes get prices the moment their trainer is recorded.
- Follow the top build. A switch on the Settings page, and a button on an empty plan: the most popular build for your class becomes your plan and every point is placed for you as you level, nothing to set up. Change a point by hand and it stops following, the plan is yours again. Retail calls this Starter Build.
- Find a talent. A box in the header, like retail's: type part of a name and the matching talents light up while the rest step back. It also searches the spells a talent changes, so "frostbolt" lights every talent that touches Frostbolt. Enter jumps to the first match, Escape clears. /talents find uses the same box.
- Someone else's build. Inspect a player, with the game's own window or the Inspect target button on the Builds page (/talents inspect too), and a card comes back with their build: lay it over your trees as gold numbers, or load it. The addon reads Blizzard's own talent string for that, so it also understands strings pasted from the game's export. The way Talent Loadout Manager makes a loadout from an inspect.
- Why here. Hover a line of the plan and the tooltip says why that point sits there: "Opens row 3 of Arms", "Unlocks Deep Wounds", "Cruelty is complete", "86% of Warriors on the site take it", "The #1 Fury build takes it too". The Coach page opens with the next point and its reasons, and the level-up card carries the first one. TalentGuide's step-by-step, written from the site's own numbers.
- The shape of a build. Hover a saved or popular build and a small picture appears beside it: the three trees as dots, gold where the build puts points, so you see its shape before you Load or Ghost it. Talent Tree Tweaks' mini tree, ours.
- The "#1 build takes it too" line no longer shows when the plan is that build.
- The safety lock. Reset your talents at a trainer and hands-free placing (Follow the top build, Place my points on level up) switches itself off, with a card saying so, the way MyTalents does it. Nothing gets spent behind your back while your plan is out of date.
- A line for your bar. If you run TitanPanel, ChocolateBar or another LibDataBroker bar, Talents Forever shows "12 / 51  3 at the trainer" on it; hover for the next point and what the trainer has, click to open the planner. Nothing is bundled: it appears only when such a bar is installed.
- The new Classic look. The window now asks for the same pieces the Forever client's own talent window is made of: its stone frame, its dark talent background, the thin bronze inner frame, the divider under the headers and the two between the trees, each tree's icon in the bronze ring with its points in the small box at the ring's foot, and the points box in the header with the number still free. Every piece is asked for by name, so it follows the game's art; a client without it falls back to the old look.
- The game's own nodes and arrows. Every talent is now the game's rounded square node: its shadow, its frame in the game's colours (gold with points, green when a point can go there, grey when not yet, dim when locked), the rank as outlined text at its foot, the game's green glow on your next point and its outline for a ghosted build; the arrows are the game's line and head art. Behind the three trees sits the class painting the Forever client draws behind its own talents, one panel per tree.
- Quiet by rule. The addon never posts in chat on its own: a link goes out only when you press Party, Guild, Whisper or shift-click a build. The "loaded" line in chat appears once per version, not every login, and login brings one card at most. The Settings page says so in plain words.
- Every link the addon makes ends in a two-character marker, so talentsforever.com can count visits that came from the addon. A pasted link with a query or hash on it still reads.
- Tooltips out of the way. A tooltip on the side panel now opens to the left, over the trees, so it never covers the list you are working down. Trainer rows too.
- Readable on any screen. The window sizes itself the first time it opens, about three fifths of the screen's width, so on a dense laptop screen with a small UI scale it no longer comes up tiny. Set a size yourself in Settings and that is kept.
- Ask your group. Shift-click the Party button (or /talents party) and every group member with the addon sends back their build as a card: lay it over yours or load it. A switch in Settings turns answering off.
- The build picture beside a hovered row fades in instead of popping.
- Your pages, your call. Settings has a Pages list: switch off Coach, Builds, Popular, Classic or Races and its tab closes up. And a switch, Show other people's builds: off, the Popular page goes away and a build another player sends is not shown as a card. Both asked for on the ideas page. The Settings page scrolls now.
- Tile tooltips lose the Passive tag. Nearly every talent is a passive, so the game's tag sat at the top of every tooltip and said nothing. The tooltip is now the talent's name, the game's own words for it, then the plan lines.
- On Builds and Popular the build picture and the row's tooltip no longer cover each other: the words sit above the picture (below it when there is no room).
- The Races page is races only; the site's note on new class abilities is gone from it.
