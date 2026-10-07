# ForeverUI

## v0.4.65

- **Blizzard's party frames are hidden by default.** ForeverUI's party and
  raid frames replace them, and players were seeing both sets. To keep
  Blizzard's, untick /fui frames > "Hide Blizzard's party frames" and
  /reload. One exception: with the controller interface on
  and Edit Mode's raid-style party frames, Blizzard's stay up, because the
  controller's targeting cursor picks party members on those frames. The
  D-pad's party 1-4 targeting needs no frames and works either way.

## v0.4.64

A clean-up release: a full read-through of the code, with every bug it
turned up fixed.

- **Fixed: the micro bar's Bags button did nothing** with Blizzard's bag bar
  hidden (the default) since 0.4.62. The game won't hand a click to a hidden
  button; Blizzard's backpack button is now kept clickable, off screen.
- **Social on the micro bar** opens the friends list through the game's own
  /friends instead of a script, which could leave the character sheet
  throwing errors afterwards. With a player targeted it tells you to press O
  instead (there /friends would add them as a friend).
- **Party and raid frames in a group:** class colours, class names, trimmed
  names, the Roles list and the AGGRO list no longer break on the names and
  classes the game keeps hidden in groups - in some setups the frames
  stopped drawing. Raid marks now show on the frames.
- **Each grid acts as its own role:** the tank grid keeps its target, AGGRO
  wash and threat meter while you play healer, other grids no longer get
  threat meters while you tank, and each grid's frames always get that
  grid's own clicks (a player joining mid-fight could get another role's
  spells). The focus frame follows your role after a switch.
- **Cast Bar > "Lock it where it is"** works now.
- **Options:** colour swatches in two-column cards sit in their own column
  (Chat, Nameplates).
- **Profile exports and backups** no longer carry diagnostic logs (errors
  from other addons, cast traces).
- **Fewer game-setting writes:** nameplate and action bar settings are only
  written to the game when they actually change.
- Smaller fixes: one failed after-combat job no longer drops the others;
  textures in each role's own look are repaired after a folder rename; the
  frames' error notice names the command that shows it.

## v0.4.63

- **With a controller, the quest guide no longer pops up on every quest you
  pick up.** It is a mouse window that the controller's B button doesn't
  close, so it sat over the game at every quest giver. With the controller
  interface on it now stays closed unless you want it: Quests > "...also
  with a controller". Keyboard and mouse are unchanged, and the guide still
  opens from the quest list any time.

## v0.4.62

- **Fixed: an error every time you open the character sheet**
  (TextStatusBar.lua:110, "execution tainted by 'ForeverUI'"). The micro
  bar's Bags button and the bag window's x opened and closed Blizzard's bags
  from ForeverUI's own code. The next Escape then closed the bags and the
  character sheet in ForeverUI's name, and from then on every C failed. Bags
  now hands its click to Blizzard's own backpack button, and the x is
  Blizzard's own close button, so the game opens and closes its bags itself.
- **Quest kills left on the nameplate.** A mob your quests still need shows
  how many are left beside its plate - "3/10" - and the same for a mob that
  drops a quest item. It updates as you kill and loot and goes away when the
  objective is done. Needs QuestForever switched on. Nameplates > NPCs >
  "Quest kills left beside the plate". In a group the game can hide mob
  names, and then no count shows.

## v0.4.61

- **Fixed: item links in chat showing an item number and not clickable.**
  ForeverUI's chat turns :) and friends into emoji - and an item link's own
  code often ends in "::|h", which holds the ":|" face. The link was
  rewritten into an emoji and broke. Links, icons and the game's other codes
  in a chat line are now left exactly as they are; only the words around
  them get emoji and clickable web links.

## v0.4.60

- **Sell junk by itself at vendors.** Loot > "Sell junk (grey items) by
  itself at vendors": open a vendor and your grey items are sold through the
  game's own sell-all-junk, so nothing that isn't grey is ever touched. It
  says in chat what it sold and for how much. Off unless you turn it on;
  kept through the beta's saving bug.
- **No more bags full of "new" glow after a reload.** The game takes an
  item's new-item glow off when its bag window closes, and ForeverUI's bag
  window never went through that, so everything stayed lit. The glow is now
  forgotten when the bags close and when you enter the world. Bags > "Forget
  the new-item glow when the bags close" turns that off.
- **The Social tile opens your friends list.** Forever has no Social button
  of its own for the micro bar to hand the click to, so every click only
  said "press O". The tile now opens it directly, the same way the O key
  does.
- **Fixed on keyboard and mouse: "ActionBarButton.lua:842: bad argument #1
  to 'SetChecked' ... Secret values are only allowed during untainted
  execution"** (druids, paladins and warriors, often when shifting form).
  The game sets up its controller bar's class-spell button when you log in
  and switches it back on, after ForeverUI had put the hidden controller
  buttons to sleep. They're now put back to sleep once you're in the world.

## v0.4.59

- **Fixed: CompactUnitFrame errors from Edit Mode and the flight master**
  ("CompactUnitFrame.lua:699 ... secret number value, while execution
  tainted by 'ForeverUI'", and the "outOfRange" one after it). ForeverUI
  put Blizzard's own player, target and target-of-target frames away by
  hiding them, and hiding the target-of-target runs a bit of Blizzard's code
  that reconfigures the target frame - under ForeverUI's name. Edit Mode
  reads the target frame on the way in and out, so its whole pass ran as
  ForeverUI, Blizzard's party frames were redrawn as ForeverUI, and they kept
  that name afterwards (which is the flight master one). Blizzard's
  protected frames are now faded out and made unclickable instead, which
  runs none of their code.

## v0.4.58

- **Fixed: CompactUnitFrame errors in combat** ("CompactUnitFrame.lua:699:
  attempt to compare local 'oldR' (a secret number value, while execution
  tainted by 'ForeverUI')" and the "outOfRange" one after it, usually the
  moment a mob targets you). When ForeverUI hid Blizzard's own nameplates,
  the game ran Blizzard's hide code under ForeverUI's name, and that code
  signed the plate up for its health and threat updates as ForeverUI - so
  every threat change in a fight ran Blizzard's code as ForeverUI. Blizzard's
  plate is now simply made invisible instead, which runs none of its code.
  The same goes for Blizzard's party and raid frames when you choose to hide
  them: they no longer listen for anything once put away.

## v0.4.57

- **Pet happiness is back for hunters.** ForeverUI puts Blizzard's pet frame
  away, and the happy / content / unhappy face went with it. It now sits
  beside ForeverUI's pet frame - the game's own icon, so it changes as your
  pet's mood does - and pointing at it shows the same details as Blizzard's:
  damage, loyalty and what your pet eats. Unit Frames > General > "Pet
  happiness (hunters)" turns it off.

## v0.4.56

- **Fixed: opening the quest log with a controller got QuestForever
  blocked** ("QuestForever has been blocked from an action only available
  to the Blizzard UI", and the offer to switch it off). On Forever the quest
  log is the world map, and with the controller interface on, the game's
  navigation steps through everything on the open map - including
  QuestForever's pins, which carried QuestForever's name into whatever the
  navigation did next. With the controller interface on, QuestForever now
  stays off the world map; its minimap pins, tooltips and waypoint arrow
  still work. Keyboard and mouse players keep the map pins as before.

## v0.4.55

- **Power text on the unit frames.** Unit frames > General > "Power text":
  mana, rage or energy as words on the power bar - current, percent, both,
  or current / max - the same way the health text works. "Power text
  position" puts it left, centre or right, and "Power text size" sets how
  big (it's small by default, since the bar is thin). Each frame's own tab
  can pick a different one. Kept through the beta's saving bug.

## v0.4.54

- **Fixed: the Blizzard_MawBuffs error from the quest tracker** ("Auras
  cannot be accessed when secret while tainted by 'ForeverUI'"). Clicking a
  quest in ForeverUI's list, or the old nearest-quests trim, nudged
  Blizzard's hidden tracker into redrawing on ForeverUI's behalf, and from
  then on every redraw carried ForeverUI's name - until one landed in a
  fight and read your buffs. While ForeverUI's list (or no list) is on
  screen, Blizzard's tracker now sits still. The nearest-quests cap still
  applies to ForeverUI's list; it no longer takes quests off your watch
  list.

## v0.4.53

- **The micro bar can fade out until you point at it.** Micro bar > "Only
  show it when the mouse is over it": the row fades away when the mouse
  leaves and back in when you point at it - still clickable while faded,
  in a fight too. "While faded, show" leaves a little of it visible if you
  like (0% is gone). Kept through the beta's saving bug.

## v0.4.52

- **Fixed: B opening nothing (just the bag sound).** With the game's
  "separate bags" setting there's no combined bag for ForeverUI's window to
  follow, so Blizzard's own bag windows are your bags - and 0.4.50 faded
  them as if ForeverUI's window were showing them. They're only faded now
  while ForeverUI's bag window is actually up.

## v0.4.51

- **Swap bags from ForeverUI's bag window.** A bag button beside the X in
  the bag window's title shows a strip of your bag slots above it (and the
  reagent bag's, where the game has one). Drag a bigger bag onto a slot to
  put it in; click a bag to pick it up; hover one to see what it is. No need
  to bring back Blizzard's bag bar. Bags > "Show your bag slots above the
  bags" does the same.

## v0.4.50

- **The micro bar's Bags button opens just your bags.** It opened every bag
  the game has - and on Forever that puts the reagent bag in a Blizzard
  window of its own beside ForeverUI's, which already shows it. It now does
  what the B key does. And whenever something else opens every bag (a
  vendor), that extra Blizzard window is faded and click-through while
  ForeverUI's bag is in use.

## v0.4.49

- **Fixed on keyboard and mouse: "ActionBarButton.lua:981 ... secret
  boolean value (execution tainted by 'ForeverUI')".** The controller's own
  action bars are always loaded, hidden, even when nobody uses a controller,
  and ForeverUI's guard on them made their spell flyouts trip. When neither
  the game nor ForeverUI is in controller mode they are now simply put to
  sleep: their events off and out of the game's shared button lists, so
  none of their code runs. Pick up a controller and the reload brings them
  back.
- **Fixed: "StatusTrackingManager.lua:228: attempt to call a nil value"
  when opening Edit Mode** with Blizzard's XP bar hidden. The XP and
  reputation bar containers ask their parent to lay them out, and ForeverUI
  had moved them under its own hidden frame. They stay where they belong
  now, hidden with the bar above them.
- **Loot advice: no more "Fishing Pole" after a boat ride.** Taking an item
  off (swapping the pole for your weapon) put it in your bags and it was
  announced as new loot; what you wear now counts as carried. For a few
  seconds after a loading screen the bags fill back in, and that isn't new
  loot either. And a fishing pole is a tool, so it gets no upgrade advice.
- **Fixed: the page keys moved every bar, and the main bar ignored stealth
  and stances.** ForeverUI's buttons carried a number the game treats as
  "page me with the action bar": each page key shifted all of them by 12
  slots (Bar 5 showed Bar 3, Bar 7 showed Bar 8), and the page ForeverUI
  set for stealth or a stance was ignored. They carry none now, so each bar
  shows its own slots and only the main bar pages - into stealth, forms
  and stances (after the fight, if you switch in the middle of one).
- **Fixed: keybind text vanishing** from the bars after the game refreshed
  its key bindings. ForeverUI's labels go back on after the game's.
- **"Show empty button outlines" works on ForeverUI's bars.** Off, an
  empty slot is see-through - no tile, no keybind - and they all show again
  while you're carrying a spell to drop.
- **Quests > Text size works on the quest list.** It only ever sized
  Blizzard's tracker, which ForeverUI's own list replaces; now the list's
  titles, objectives and distances follow it (12 is the size it always had).
- **QuestForever: fewer quests that aren't yours to take.** With "Show
  profession quests" on, a profession quest shows only if you have that
  profession far enough along (Gaffer Jacks needs Fishing 30). The Scourge
  Invasion's quests only show while the game's calendar lists the invasion.
  And a quest started by an item a monster drops ("The Moss-twined Heart",
  from a rare in Teldrassil) no longer gets a "!" somewhere nobody hands it
  out - just the pin where the item drops.
- **Easier to read settings.** Numbers on the parchment cards (sizes,
  spacing, opacity) are written in a deep purple ink instead of the pale
  lilac meant for the dark wood.

## v0.4.48

- **Turn the tanking or DPS grid on whenever you like - levelling too.**
  Quick Setup's party & raid frames are now one tile per role that says
  when its grid shows: "Tanking: always" (solo and in groups), "in groups
  only", or "off" - click to go round. The separate "Solo: every grid
  that's on" tile is gone: it was why switching the tanking grid on while
  levelling seemed to do nothing. The switch beside each role in the
  sidebar and /fui grids tank put a grid up for solo play too, and /fui
  role tank (or dps) brings that grid up if it was off. Kept through the
  beta's saving bug.
- **One XP bar with a controller.** In controller mode the game draws its
  own XP bar with its controller bars, so ForeverUI's now steps aside too,
  like its action bars, bag and micro bar.

## v0.4.47

- **Chat tabs that fade out completely.** Chat > Look > "Fade the chat
  tabs out completely": General, Combat Log and the rest vanish when the
  pointer leaves the chat, instead of Blizzard's half-faded row, and come
  back when you point at it. A tab flashing for a new whisper still shows.
  Kept through the beta's saving bug too.
- **The map, the quest log and Legacy open directly again.** Since the
  character-sheet fix a few versions ago these only said which key to
  press, because ForeverUI opening Blizzard's windows itself broke the
  character sheet and Edit Mode later. Now the click is handed to the
  game's own button instead - the minimap's zone name for the map, the
  quest log and Legacy buttons for the others - so the window opens and
  nothing is left broken. On the micro bar (M, L, Y), the minimap's zone
  line, and the quest guide's "Map" and "Blizzard's log". Legacy says to
  press Y until your first Legacy progress (Blizzard keeps its button off
  until then), and in a fight the quest guide's two still name the key.
  The friends list stays on "press O": the only way in would unfriend
  whoever you have targeted.

## v0.4.46

- **Fixed: "SetCooldown ... Secret values are only allowed during untainted
  execution" every time you cast at an enemy** on keyboard and mouse. The
  controller's own action bars are always there, hidden, and share an event
  loop with ForeverUI's buttons; since 0.4.43 they were left unguarded and
  threw from Blizzard_GamepadActionBars. On keyboard they're guarded again;
  with a controller they're still never touched.
- **Fixed with a controller: "gamepadPanMagnitude (a nil value)" flooding
  from the world map.** The map's cursor pans at the edge by how far the
  stick is pushed, and the game only knows that once the stick has moved
  on the map. It now starts at full speed.
- **Action buttons really touch at Spacing 0.** Blizzard's button clips its
  icon to a smaller rounded shape, and hiding that shape didn't lift it, so
  flat buttons kept a wide dark gap between them. The icon now fills the
  block edge to edge - the Bartender look.
- **The options window opens where you left it.** Drag it once and /fui
  opens it there from then on, kept through the beta's saving bug too.

## v0.4.45

- **Loot advice: what each new item in your bags is good for.** When loot
  lands in your bags ForeverUI tells you, on screen: junk to sell (and what
  it's worth), gear that isn't for you (the game's own red lines decide -
  wrong armour or weapon type), gear for a higher level (and whether it'll
  be an upgrade then), and upgrades worth putting on, with how much better
  and "right-click to equip". Upgrades get a green + in the bags and a line
  on the item's tooltip. Weighed for your class and role - healing, tanking,
  or strength, agility or spell damage - or pick one yourself. It never
  equips anything for you. /fui loot for its settings; drag the messages
  with /fui move.

## v0.4.44

- **The controller setting in plain words.** General > Controller now reads
  "Controller or keyboard?" with Automatic, Always controller or Always
  keyboard + mouse, and says what Automatic does (switches by itself when
  the game is in controller mode - nothing to set) and which mode you're in
  right now.
- **Fixed: a lower rank clicked on a frame landed on you.** A click bound to
  a lower rank (Mark of the Wild, Rank 3) is now cast by that rank's own
  spell, so it goes to the player you clicked. Clicks with no rank were
  never affected.
- **Mining veins, herbs and chests show their name.** Things you can
  interact with get a plate of their own (the controller turns that on), and
  ForeverUI drew them like a monster with a health bar. They're now just
  their name, in gold.

## v0.4.43

- **Playing with a controller.** Forever has Blizzard's full controller UI -
  its own action bars, a pointer that walks the windows, the radial menu -
  and ForeverUI was getting in its way: it wrapped the controller's action
  buttons along with everything else, so in a fight the game could block
  them as ForeverUI's, and its bag window, buff frame and micro menu
  changes left the pointer and the radial menu with nothing to reach. Now
  the controller's buttons are never touched, and when you play with a
  controller ForeverUI's action bars, bag window and micro bar step aside
  for the game's own. Unit frames, the healing grids, quests, nameplates and
  the rest of the look stay. General > Controller: Auto (follows the game),
  Controller, or Keyboard and mouse; a switch asks for a reload.
- Controller buttons show as A, B, X, Y, LB, RB, LT, RT and the d-pad on the
  action bars' keybind text.
- **Fixed with a controller: "SmartNavigation.lua:926 ... tainted by
  'ForeverUI'"** right after the setup, and "QuestForever is being blocked
  from an action only available to the Blizzard UI". The controller's
  navigation watches every frame an addon makes; the game's aura icons made
  for ForeverUI's frames, and quest pins made while the map was open, ran it
  as ForeverUI's. With a controller, no game aura containers are made (the
  frames use their own buff and HoT icons), and the map's pins are made
  while it's closed and only reused while it's open.
- **NPC jobs back on the nameplates.** <Hunter Trainer>, <Innkeeper> and the
  rest under an NPC's plate, the way the game shows them. Nameplates > NPC >
  "Their job under the plate" (on as standard).

## v0.4.42

- **Fixed: right-clicking some bag items was "blocked from an action only
  available to the Blizzard UI"** (Waylaid crates, and anything else whose
  use casts a spell). ForeverUI's bag window told each slot which bag it is
  in itself, and that one number, being ForeverUI's, made the game refuse
  the use as an addon's. The slots now get their bag from the game.
- **Icon zoom on the action bars.** Action Bars > "Icon zoom": crop more of
  each spell's picture edge for the Bartender look, with almost no border.
  8% (the icon's own frame trimmed) is where it ships.
- **Chat, your way.** Chat > Look: your own background colour and opacity,
  your own border colour (or General's, as before), any font size from 9 to
  24 - 13 and 15 included - and the line you type on above the chat or
  under it. Kept in the macro backup through the beta's saving bug.
- **ForeverAuras: your own cooldown and aura icons, no WeakAuras needed.**
  /fui auras (or its page in the options). Add a cooldown, a buff, or your
  debuff on the target, type the spell, unlock and drag it where you want it.
  A cooldown greys out while it's cooling down, with the game's own
  countdown, turns red out of range and blue without the mana, glows on a
  proc, and can glow or play a sound when it's ready. Buffs and your debuffs
  on the target are drawn by the game itself, so they keep working in
  combat and in groups, with the time left and stacks; a buff can show a
  dimmed icon while it's missing. Show always, only in combat or only out of
  it; each loads only on the class that made it. Export and import as text
  to share. Your auras are kept in the macro backup too, so the beta's
  saving bug doesn't lose them.
- **Rounded action buttons and unit frames.** With General > Appearance >
  Corners > "Rounded corners" on, the action buttons and the unit frames
  (player, target, focus and the rest) round too, their borders curving to
  match - a class-coloured border included. The spell icon and the health
  and power bars move in a pixel or two so their corners stay inside the
  curve. Each has its own switch there ("Round the action buttons too",
  "Round the unit frames too"), both on with rounded corners.

## v0.4.41

- **What's new, in the game.** The first time you log in after an update, a
  window lists what changed since the version you last saw - the same notes
  as this changelog - so nothing that ships goes unnoticed. It opens once
  per update (after the saving notice, if that's up) and remembers you've
  seen it even through the beta's saving bug. /fui new opens it any time.

## v0.4.40

- **Rounded corners, if you like them.** General > Appearance > Corners:
  switch on "Rounded corners" and the windows, panels and buttons ForeverUI
  draws - the options window, the quest list and its windows, bags, chat,
  the setup - get rounded corners, with a curved border to match. "Corner
  size" sets how round; small boxes and buttons stay gentler than windows,
  so a checkbox never turns into a radio button. Off by default: square, as
  before. Bars, nameplates and the minimap stay square for now.
- **Moved frames stay where you put them.** The Forever beta forgets every
  addon's saved settings at a restart, and ForeverUI's macro backup didn't
  keep what you'd dragged with /fui move, so a layout snapped back to the
  defaults every time. Every frame you've moved is in the backup now, right
  after your clicks and ahead of the other roles' clicks, and the backup can
  use up to five macros to fit it.
- **Keep your whole setup as text.** /fui backup (or "Copy my whole setup"
  in the saving window, /fui saving) gives you everything - colours,
  textures, sizes, every setting - as one line to copy and keep. After a
  restart, /fui restore and paste it: it all comes back at once, with no
  reload (on this client a reload is what forgets things). Only the settings
  you changed are in it, so it stays short. Pasted text is read as data and
  never run, which also makes profile import work on clients that don't
  allow addons to run code from text.

## v0.4.39

- **Incoming heals on the healing grids, at last.** The green "heal on its
  way" stretch never drew on the party and raid frames. On Forever health
  always comes back as a secret number; the health text's percentage
  couldn't be worked out from it, and that one failure switched the incoming
  heals off too - on every frame, for everyone. They are drawn from the
  game's own numbers and never needed the sum, so they no longer care.
  (Thanks to the priest who kept checking.)
- **UI Scale now really scales, and nothing slips after a reload.** A scale
  below 100% in the setup shrank only the invisible move handles, not the
  bars riding on them, so after a reload the action bars and micro bar sat
  off to one side until /fui move put them back. The frames are now drawn at
  the chosen scale, and the setup applies it straight away.
- **The setup backup finds its macro slots.** Forever allows 30 macros per
  character; ForeverUI counted to 18, called anyone with 18 or more "full"
  and saved nothing. It counts to 30 now, and if the game ever refuses the
  macro it says why instead of quietly giving up.
- **Shift + drag moves spells.** The bars stay locked, but hold Shift and
  drag a spell to another button, the way Blizzard's locked bars work - no
  need to open Edit bars. Action Bars > "Shift + drag moves spells" turns it
  off.
- **QuestForever on its own has a settings window.** Without ForeverUI, /qf
  used to switch the quest helper off; now it opens its settings (everything
  ForeverUI's quest helper page has), and it is listed under the game's
  Options > AddOns too. /qf on and /qf off still switch it.

## v0.4.38

- **Every grid you switched on, solo too - if you like.** On your own, only
  the grid for the role you're playing shows; the others appear as soon as
  you're in a group (a shadow priest with Healing and DPS on saw one at a
  time and had to click the other to bring it up). Quick Setup has a new
  switch next to Healing / Tanking / DPS: "Solo: every grid that's on".

## v0.4.37

- **Holiday quests only in season.** Lunar Festival, Midsummer, Darkmoon
  Faire and the other holiday quests no longer put "!" on the map (or in
  Next, or in a quest line as "take it now") outside their holiday. The quest
  helper asks the game's calendar which holidays are on today; a holiday quest
  shows "holiday not on now" otherwise.
- **The Dungeons tab learns the new dungeons.** Walk into a dungeon the data
  has no entrance for - Forever's new ones - and the quest helper notes where
  you stood outside, and which quests you pick up or move on while inside.
  They show on the Dungeons tab straight away (the entrance marked as
  recorded), and Share (/fui share) sends them in so the next update has them
  for everyone. Off with the rest of the quest helper's learning.
- **Fixed: RXPGuides' guide box not showing** ("RXPGuides/GuideWindow.lua:380:
  attempt to perform arithmetic on a nil value" at login). Loading the
  quest helper in the middle of logging in told RXPGuides about it before
  its window was built. The quest helper now waits until you're in the
  world, and a moment more, before it loads.

## v0.4.36

- **Dungeons tab.** The quest list has a Dungeons tab under the others:
  every dungeon, lowest level first, coloured for your level, with how many
  of its quests you can take or are carrying. Click one for its window -
  level range, group size, its wings, where the entrance is (with an arrow)
  and its quests with where each stands for you; click a quest for its
  whole line. Right-click a dungeon for the arrow straight away. The list
  and levels come from the game itself, so the new Forever dungeons (Hall
  of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of
  Dalaran) are there too - their entrances and quests aren't known yet.
  Entrances and quests come from QuestForever, loaded for the tab even
  with the quest helper's map pins off.
- **DPS: "IT'S ON YOU".** Playing a damage role in a group, the moment the
  mob you are hitting turns on you it says so in the middle of the screen,
  with a warning sound. Threat is hidden on this client in groups, so it
  asks a question the game can still show - is my target's target me? - and
  lets the game draw the answer. Frames > On each frame (DPS role) turns it
  or its sound off; unlock the frames to drag it.
- **Fixed: TankForever booted as a healer.** The standalone builds lock
  their role before a character's settings load, so the settings kept
  saying "healer": healer clicks, and no tank alarm or Loose list. They now
  move onto the build's own role at login, bringing any clicks you set up.

- **One grid while solo.** With the healing, tanking and DPS grids all
  switched on, playing on your own showed three boxes with just your name in
  each. Now only the grid of the role you are playing shows you solo; the
  others appear the moment you join a group (in combat too), and a grid with
  nobody in it shows no empty box.
- **Quest chains, from every quest.** A quest that is part of a line wears
  its place in the quest list ("2/5"). Click it - or "see the whole chain"
  in the quest guide - for the whole line: every step in order, side
  branches together, ticks for what you've done, YOU ARE HERE on yours, and
  who gives each step you haven't taken and where. Click a step for its
  guide, right-click for the arrow to it.
- **Quest tips and routes.** Some quests now come with a tip in the quest
  guide and a route: the Arrow walks the route point by point (it moves on
  by itself as you reach each one), then on to the objective, and the route
  shows on the map as green dots. More are added as they are walked.
- **Add your own (BETA - for developer use).** In the quest guide, "Add a
  tip or a route": type a tip, and walk the way you'd tell a friend to go,
  pressing "Add point here" at each turn. Then press Share (or type
  /fui share): it gives you a link - ispress.de/foreverui/share - and the
  text to paste there, and you can add screenshots on the same page. The
  best ones go into ForeverUI for everyone. (This beta client forgets what
  you added when the game restarts, so share before you log out.)
- **Fixed: the quest list crept up under the minimap** as quests were
  added. It now keeps its top edge and grows downward.
- **Fixed: the setup wizard closed itself at login** (entering the world
  closes every window Escape can close). It now opens a moment later.

## v0.4.35

- **Fixed: the character sheet (C) and Edit Mode throwing "attempt to
  compare a secret number value (execution tainted by 'ForeverUI')".**
  Some of ForeverUI's shortcuts opened Blizzard's windows themselves - the
  micro bar's Map, Social and Legacy tiles (this client has no Blizzard
  button for them to hand the click to), the quest list's "open the log",
  the quest guide's Map button, "Say hello" and the Cooldown Manager's
  settings and Edit Mode buttons. Opening a window from an addon leaves the
  game's window manager marked as that addon's, and the next window opened
  - the character sheet - then fails on its own health text. ForeverUI no
  longer opens any of these itself: tiles with a Blizzard button still hand
  it the click, and the rest tell you the key (for example "To open the
  world map, press M").
- **All eight action bars.** ForeverUI had four; the game has eight. Bars 5
  to 8 are in now, on the game's own slots for Bars 5-8, so anything you
  already put on them shows up. They start switched off: Action Bars >
  "Show bar 5" ... "Show bar 8", each with its own tab (buttons, rows, size,
  vertical), and /fui move to put them where you like.

## v0.4.34

- **Fixed: "GetAuraDataByIndex(): Auras cannot be accessed when secret while
  tainted by 'ForeverUIApp'"** from Blizzard's quest tracker, in combat,
  after an Edit Mode layout pass. ForeverUI put the game's tracker (and
  Blizzard's right-hand action bars) away with Hide(), and even the plain
  Hide makes those frames take themselves off the game's frame manager from
  inside ForeverUI's code - which left the manager's lists marked as
  ForeverUI's, so the next layout pass ran the tracker "tainted" and it died
  reading an aura. They are now faded out and taken off the mouse instead,
  never hidden, collapsed or updated by ForeverUI.

## v0.4.33

- **Nameplates on starting-zone mobs.** Many low-level quest mobs (the
  zombies in Deathknell, for one) are what the game calls "minor" units, and
  those were hidden twice: "Show minor units" was off as standard, and the
  critter filter counted every minor unit as a critter. So only your target
  got a plate - the rest showed just a small name. Minor units are now on
  (switched on once for everyone), and "Hide critters" hides only critters.
- **Incoming heals and shields on the unit frames.** Player, target, focus
  and the rest now show heals on their way as a pale green stretch past the
  end of the health bar, and shields (Power Word: Shield and the like) as a
  pale white stretch past that - no healing frames needed. Unit Frames >
  General > "Incoming heals" / "Shields" turn them off.
- **Action bars: red when out of range.** The whole icon turns red when the
  target is out of range, not just the keybind (Action Bars > "Red icon when
  out of range"; on as standard).
- **No more flashing red square with a wand or auto attack.** The game
  flashes the button while you shoot or swing; that is off as standard now
  (Action Bars > "Flash while auto-attacking or shooting" brings it back).
- **Your own colour for the action button borders** (Action Bars > "Own
  colour for the button borders"), instead of the accent colour everything
  else uses.

## v0.4.32

- **Where you are in a quest line, and what to take next.** (Quest helper on:
  Quick Setup > "Quest helper".)
  - The quest guide (left-click a quest in the list) now shows the quest's
    whole line: what came before, what comes after, and the side branches -
    each step ticked done, in your log, ready to take now, or waiting (and
    on what: your level, an earlier step), and a branch you can no longer
    take (because you took the other one) crossed out. Click any step to
    open it, even one you haven't picked up yet: who gives it, and the
    Arrow button points you there.
  - The quest list has a Next tab: the quests you can pick up where you
    are, nearest first. Click one for the arrow to its quest giver,
    right-click to see where it leads. An empty quest log shows the same
    list instead of "Go and pick some up".

- **Buffs and debuffs on the unit frames, each where you want them.**
  Debuffs and buffs are now placed separately: above, below, left or right
  of the frame (Unit Frames > General > "Debuffs go" / "Buffs go", and on
  each frame's own tab). On the same side, buffs sit beyond the debuffs;
  beside the frame they run in rows of six, away from it.
- **Text size on the aura icons**: "Text size on the icons" sets the stack
  count and the seconds left (10 as standard) - they were drawn much bigger
  than the icon.
- **Hide the game's buff bar** (top right), which Edit Mode can't: Unit
  Frames > General > "Hide the game's buff bar". Your own frame then shows
  your buffs and debuffs instead. Off as standard. Thanks to sprutorgel on
  CurseForge for all three.

## v0.4.31

- **Your role follows the game's Set Role.** Right-click your frame > Set
  Role > Tank (or a role check) now changes your badge on every grid, and the
  tank-first order with it. A role you'd set by hand on the Roles page used
  to win and kept the old badge; the game's choice is the newer one, so it
  replaces yours (Damage leaves a Melee or Ranged you set alone).
- **See who took your mob (Tanking grid).** In a group Forever hides threat
  from addons, so the red "has aggro" borders never lit. Now the frame of
  whoever your target is attacking lights up red with HAS YOUR TARGET - the
  paladin who taunted, the mage who pulled - and goes dark when it comes back
  to you. The game picks the frame; ForeverUI never learns the name.
- **Loot window over your bars?** General > "Open the loot window at the
  mouse" (the game's own setting). Or move it: Esc > Edit Mode - on Forever
  the loot window is an Edit Mode frame, which ForeverUI leaves alone.

## v0.4.30

- **Guild on the micro bar (J).** After Social, with a shield: the Guild &
  Communities window, as the J key opens it.
- **"Auras cannot be accessed when secret ... tainted by ForeverUI" in
  dungeons.** At every login and every settings change ForeverUI told the
  game's quest tracker to "roll down" - even though it already was. Running
  the tracker's code from an addon leaves it marked as the addon's, and in a
  dungeon the tracker's scenario section then reads an aura on that pass,
  which Forever refuses in combat. ForeverUI now leaves the tracker alone
  unless you actually roll it up or down. Thanks to the CurseForge commenter
  who reported it.
- **Your watched HoTs stay on the frames in group combat.** Spells you watch
  in a frame corner (Rejuvenation top left, Regrowth top right...) were still
  ForeverUI's own reads, and in a fight its guesses from your casts - which,
  with names hidden in a group, only worked for casts you clicked onto a
  frame. Now the game draws them too: each watched helpful spell gets its own
  game-drawn icon in its corner, with the real time left, however it was
  cast and whoever it's on. (Up to six per grid; a debuff you watch, or one
  set to "others only", stays as before.)
- **"attempt to perform boolean test on ... a secret boolean value" in
  Casting.lua** when a unit frame showed someone channelling: the cast bar
  asked whether a channel could be interrupted in a way Forever forbids.
  Thanks to the CurseForge commenter who sent it.
- **The tank on top in a dungeon.** The Roles page's Frame order did nothing
  in a group: it sorts by a list of names, and Forever hides everyone's name
  from addons once you're grouped. Grouped, the same order now goes by the
  game's own roles (dungeon finder or role check - the shield / cross / sword
  badges): tank, damage, healer, or however you arrange it. Pressing the
  arrows switches the order on (it used to need Layout > Sort by first).
  "Tanks first" on the Layout page also goes by those roles now - a
  five-player group never has a Main Tank, so the tank stayed put. Setting
  someone's role by clicking their name can't work while names are hidden;
  it now says so instead of doing nothing.
- **Where to send an error report** is now said in the `/fui errors` window:
  copy it and paste it in a comment on ForeverUI's CurseForge page.
- **Restore Defaults no longer sits on top of the search box** on the settings
  pages; it is beside it.

## v0.4.29

- **Your HoTs stay on the frames in a dungeon.** Rejuvenation, Regrowth,
  Renew and shields vanished from the Healing, Tanking and DPS frames the
  moment a group pull started. Forever hides auras from addons in combat,
  and the stand-in (timing your HoTs from your own casts) remembered them
  by the player's name - which Forever also hides in a group, so solo it
  worked and in a dungeon nothing was ever remembered. Two fixes:
  - The HoT row is now drawn by the game itself, into ForeverUI's frames:
    your own buffs of a minute or less, soonest to run out first, with the
    real time left and the stack count of a buff that builds - in combat
    or out, grouped or solo, however you cast
    them. Same place, size and count as before. "On each frame" > "...drawn
    by the game (real timers, in combat too)". A spell you watch in a
    corner shows there only, not twice.
  - The cast-timing stand-in (still used for watched spells in corners, and
    for a frame that first appears mid-fight) goes by the frame's place in
    the group when names are hidden, so it works grouped too.

- **Buffs and debuffs on the unit frames.** The target and focus frames now
  show what's on them: debuffs nearest the frame, with the dispel colour on
  the border (blue magic, green poison, purple curse, brown disease), buffs
  on the row beyond, each with its seconds left and stack count. They keep
  working in a fight: Forever hides auras from addons in combat, so the game
  draws them itself into ForeverUI's frames. Hover one for what it is;
  right-click one of your own buffs to cancel it. Unit Frames > General >
  "Buffs and debuffs": buffs, debuffs, "Only debuffs I cast", above or below
  the frame, icon size, how many. Each frame's own tab switches them on or
  off; the player's are off as standard, since the game's buff bar already
  shows them. Thanks to the CurseForge commenter who asked.

## v0.4.28

- **Hunters and warlocks: your pet bar is back.** Hiding Blizzard's action
  bars took the pet bar with it, and ForeverUI has none of its own. Blizzard's
  pet bar is now left standing (it shows only when you have a pet; move it
  with Esc > Edit Mode). Action Bars > "...but keep Blizzard's pet bar". The
  stance / form bar can be kept the same way (off by default). Thanks to the
  CurseForge commenter who asked.
- **A smart mark key: skull on the first mob, cross on the next.** Each press
  puts the next mark (skull, cross, square, moon...) on the next unmarked mob:
  hover them one after another before the pull. A mob that already has a
  mark keeps it. It starts over at skull when a fight ends or after half a
  minute. (In a fight it keeps the mark it's on: the game won't let an addon
  change what a key does mid-combat.)
- **Set the marker keys from Quick Setup** (and the Raid Markers page): click
  "Skull: no key", press the key - done. Esc cancels, Backspace clears. The
  keys are kept with your bar keys, so they come back after a restart.
- **The last "blocked" error from the first dungeon** is gone: Blizzard's own
  hidden bar buttons now wait for the fight to end too.
- **Marker keys mark what's under the mouse** as standard: hover a mob (or
  its nameplate) and press skull. "Your target" is still a choice on the
  Raid Markers page.
- **You can see the raid marks.** Marking worked, but nothing of ForeverUI's
  drew the mark: the nameplates, the target and focus frames and the party
  grid now show the skull, cross or whichever it is. (Forever hides which
  mark a unit has from addons, even solo; the icon is drawn by the game
  from the hidden value, so it is always right.)

## v0.4.27

- **Raid markers for tanks.** A small bar of the eight marks, skull first,
  and a clear button: left-click puts that mark on your target, right-click
  takes it off. Every mark is also a key (Key Bindings > ForeverUI > "Mark:
  Skull" and so on), and the keys can mark your target or whatever is under
  the mouse - hover the mob on your healer and press skull. On the Tanking
  grid a click can mark what that player is fighting (Tank window >
  Click-casting > Skull, Cross, Moon). Shown when you're in a group (or
  always, or never - the keys still work); moves with /fui move. The game's
  own secure marking does it, so it works in combat.
- **Enemy nameplates in dungeons.** In a group Forever hides a mob's name and
  creature type from addons, and the critter check tripped over it - every
  enemy plate in the dungeon disappeared (thousands of errors). Fixed, along
  with the other places ForeverUI compared a unit's hidden text.
- **The healing grid shows who's out of range.** Only the health bar faded;
  the healing look's coloured border and mana bar stayed bright, so a player
  across the room still looked healable. They fade together now.
- **Class colours in a group** no longer throw an error (876 in one dungeon):
  a group member's class is hidden too, and the game's own colour is used.
- **No more "blocked" errors from bar 2 in combat**, and no warning about an
  event Forever doesn't have.
- **Dungeon size in a box you can move.** Blizzard's "5 / Dungeon" flag sat
  behind the clock; ForeverUI shows its own, beside the minimap buttons, in
  an instance only, and /fui move puts it anywhere.

## v0.4.26

- **Party & raid frames work on non-English clients.** Every spell the
  frames know by name - Buff Watch and missing buffs, the starter watch,
  the heal put on left click, taunts, rescues, resurrections - was written
  in English, so on a Russian client (for one) a Druid couldn't pick Mark of
  the Wild in Buff Watch. Each is now looked up by its spell ID and shown in
  your game's own language - German, French, Spanish, Portuguese, Russian,
  Korean and Chinese (Italian Classic is in English already); names already
  saved in English are translated once. Thanks to the CurseForge commenter
  who reported it.

## v0.4.25

- **Quick Setup: the things you do most, one click each.** `/fui` now opens
  on a Quick Setup page: move frames, keybind the bars, put spells on the
  bars, the Healing / Tanking / DPS frames on or off, the quest helper on or
  off, ForeverUI's nameplates or the game's, Blizzard's look with only the
  frames kept, Healing only, how many buttons on bars 1-3 and per row, and
  "Reset every frame position" / "Run the setup again". Every tile is the
  same setting as on the full pages, so a change shows on both.
- **Fewer pages, every setting in one place.** Nothing was taken away:
  - Keybinds and the Cooldown Manager are tabs on Action Bars; Kick alerts
    is a tab on Nameplates; Info is a section of General. Old names still
    work (`/fui keybinds` opens the Keybinds tab).
  - The Heal / Tank / DPS window has one Move frames button (the footer)
    instead of three. Names, health text, mana bar and colours live on
    Appearance, role badges on Roles, the Focus group and sorting on Layout -
    no longer repeated on On the frames. Everything on / off still covers
    them all, so off is still a bare bar.
  - Hiding Blizzard's micro menu, bag bar and XP bar moved from Action Bars
    to the Micro Bar, Bags and XP Bar pages. "Vertical" is on each bar's own
    tab only.
  - One minimap-button switch (General); the frames' own copy only shows in
    the standalone HealForever / TankForever.
  - The Healing, Tanking and DPS worlds stay separate, each with its own
    clicks, looks and place on screen.
- **Restore Defaults on every settings page**, top right, in the same place
  everywhere. It asks once, then puts that page's settings back as they
  shipped, leaving the module on or off as it was.
- **Professions on the micro bar (K)**, after Talents, with a hammer glyph.
- **Eight controls that did nothing, or the wrong thing, fixed:**
  - Unit Frames' "Lock frames" box did nothing (removed; /fui move locks).
  - The gear beside Party & Raid Frames on the Modules page opened General
    instead of the frames' settings.
  - `/fui frames check` (the diagnostic) could never run - another command
    caught the word first.
  - `/fui role dps` said DPS frames weren't built yet.
  - `/fui heal`, `/fui tank` and `/fui dps` open that role's window.
  - "Open the quest guide when I pick a quest up" now has a switch on the
    Quests page, not only a slash command.
  - The Minimap page no longer says to drag the map with /fui move.
  - The quest list's notes say to move it with /fui move, not Edit Mode.
- **The frame tooltip says what your clicks cast, HealBot-style.** Hover a
  party or raid frame and the tooltip lists "Left - Rejuvenation", "Right -
  Target", wheel and extra-button binds too; hold Shift, Ctrl or Alt and it
  switches to those bindings on the spot. With the unit tooltip set to
  "Don't show one" you get a small tooltip with just the clicks. On the
  frames' "On each frame" list: "What my clicks cast, in the tooltip". Thanks
  to the CurseForge commenter who asked.
- **Your HoT timers stay on the frames in combat.** Rejuvenation or Regrowth
  cast before the pull vanished from the frames the moment a fight started,
  on the Tanking and DPS grids above all: "keep my HoTs showing in combat"
  was off by default there. It's on for every grid now (switched on once for
  saved settings), and whenever a read in combat finds nothing - the game
  hiding the auras - the frames fall back to what you were seen to cast.
- **Wheel binds on your bars work in combat again.** At the start of a fight
  the party/raid frames take the mouse-wheel keys they have spells on, so
  hover-casting works mid-fight - but they also took a key you'd put on an
  action bar, and an addon can't press a bar button for you in combat, so it
  went dead until the fight ended. A wheel key that's on your bars now stays
  your bars' in combat; out of combat, over a frame, the frames still win.
- **A pretend fight for testing: `/fui test combat 5|10|20|40`.** The
  pretend group on your grids starts fighting: tanks take steady hits, a
  raid-wide blast every 8 seconds, random spikes, dispellable debuffs, deaths
  and rezzes, other healers topping people up, HoTs ticking, someone pulling
  threat now and then, and enemy casts flowing into the kick alerts. Click a
  pretend player and your spell goes off on you as usual - and they get
  healed. A corner panel shows the fight and how long each redraw of every
  frame takes. `/fui test combat off` to stop.
- **Kick priority on the enemy's own cast bar.** The nameplate cast bar
  turns green for a heal and red for a cast the game marks as important, with
  a KICK tag beside it - on the enemy you're fighting, not in a list
  somewhere else. Casts that can't be interrupted stay grey. Nameplates >
  "Kick priority". (Forever keeps enemy casts secret from addons; the game
  itself decides which is which.)
- **Kick alerts in the middle of the screen (optional, off).** Enemy casts you might want to interrupt, in
  the middle of the screen (move them with /fui move): heals in a big green
  lane at the top, spells the game marks as important in red under them,
  everything else small in amber, each with a filling cast bar and who's
  casting. Casts that can't be interrupted are faded. Forever keeps enemy
  casts secret from addons, so the game itself sorts each cast into its lane
  - ForeverUI never reads it. `/fui kicks`, `/fui kicks test`.
- **Cooldown numbers on the action bars.** Every button that isn't ready
  shows how many seconds are left, in combat too. The game draws the number
  itself (ForeverUI hands each button's spinner the game's own duration
  object, which Forever doesn't lock in a fight), so nothing is guessed. The
  global cooldown gets no number. Action Bars > "Cooldown numbers".

## v0.4.24

- **Click a quest: the quest guide.** Left-clicking a quest in ForeverUI's
  quest list now opens a guide that says what to do as a list, instead of
  nothing visible (it used to only point the arrow, and only with
  QuestForever on): the game's one-line goal, numbered steps in plain words
  with your progress ("Loot Azure Feather from Windfury Sorceress - 0/6"),
  finished ones ticked, who to hand it in to and where, and buttons for the
  arrow, the map, sharing and abandoning. Click a step and the arrow points
  at the nearest place for it. Right-click still opens Blizzard's log.
  It also opens by itself when you pick a quest up (the line at the bottom
  of the guide switches that off, or `/fui quests guide off`).
- **Cooldowns: Blizzard's Cooldown Manager, ForeverUI's style.** Forever
  hides cooldowns from addons in a fight, so instead of a tracker of our own
  that would go blank, ForeverUI now dresses the game's own Cooldown Manager
  (which keeps working in combat): square icons without the round mask and
  ring, a thin flat border, our font on the counts, flat buff bars. Its page
  (`/fui cooldowns`) switches the manager on, opens Blizzard's "choose
  cooldowns" panel and Edit Mode to move it, and can fade it out of combat.
  Thanks to wixer5851 for asking.
- **Buffs and HoTs in combat, drawn by the game (test).** Forever won't let
  an addon read auras in a fight, so the frames' buff icons went dark the
  moment combat started (thanks KruegerVox). The game's own aura drawing -
  the same service that already keeps dispellable debuffs on the frames in
  combat - can draw buffs too: /fui frames > On the frames > "Everyone's
  buffs & HoTs, drawn by the game", or `/fui frames gamebuffs`. By default
  they show only in combat, where ours can't. On trial until it's been seen
  working on the live client.
- **QuestForever knows more quests and names the right mobs.** New quest data
  from more sources: Forever's new quests with a known giver went from 175 to
  362, objectives from 2,428 to 2,968, and Zephras Isle now has its quest
  chains. The guide's own names for a spot are kept, so a step reads "Loot
  Azure Feather from Windfury Sorceress" and that harpy's tooltip says so.
  A quest whose target is a hidden "credit" (e.g. Traditions of the Bluff)
  shows the game's own objective lines instead of "Kill ?".

## v0.4.23

- **QuestForever tells you what to do, not just where.**
  - Hover a mob, an NPC or an object in the world and its tooltip says which
    of your quests it is for and how far along you are ("The Fargodeep Mine:
    Kobold Vermin slain: 3/10"). Hover a quest giver and it lists the quests
    they have for you. (QuestForever page > "Quest lines on mobs', NPCs' and
    objects' tooltips".)
  - Every quest in plain steps: "Kill Kobold Vermin", "Loot Candle from
    Murloc", "Use Wanted Poster", "Go to: ...". A map pin's tooltip lists them
    all, ticks the finished ones and marks the step that spot is for.
  - Click a quest in ForeverUI's quest list and the waypoint arrow points to
    your next step - the nearest unfinished objective, or the hand-in once
    it's done. Hover it to see the steps.

## v0.4.22

- **QuestForever: quests on your map while you level.** A yellow "!" where
  you can pick a quest up, a "?" where you hand one in, and dots where the
  mobs, items and objects for your quests are - on the world map and the
  minimap. Click one and the waypoint arrow points there. Only quests that fit
  your character show: faction, race, class, level, reputation, not done yet,
  earlier quests in the chain done. Off unless you want it: the first-time
  setup now asks "Levelling?", and the QuestForever page sits near the top of
  `/fui` (under Heal, Tank and DPS). `/fui qf` turns it on or off.
  - A quest hub is one "!" listing every quest there (with level and XP),
    not a pile of icons on top of each other.
  - A camp of mobs is one dot, not twenty, and an objective you've finished
    disappears; the tooltip shows your progress ("Kobold slain: 3/10").
  - Quests that start from a dropped item show where the item drops.
  - Escorts and patrolling targets show the route they walk.
  - "Explore" objectives show the spot to reach.
  - Talk to a quest giver and anything the data thought they'd offer but they
    don't is hidden until you hand a quest in or level up.
  - **It learns.** Many quests new in Forever have no known giver yet. Pick
    one up and QuestForever remembers where, and draws it from then on. "Share
    what it found" (or `/fui qf export`) gives text to post as a comment so
    the next update has it for everyone.
  - It is its own folder (QuestForever) that loads only when switched on, so
    leaving it off costs nothing. It is also its own download, and runs
    without ForeverUI (`/qf`).
  Quest data from QuestieDB (Forever branch), forever-guide-mate and Wowhead's
  Forever quest list - see QuestForever/README.txt.
- **Healing only, in one click.** `/fui` > General > **Healing only** (or
  `/fui only heal`) turns off every part of ForeverUI except the party and
  raid frames, puts up only the healing grid, and sets the frames up for
  healing - everything else is the game's own again. `/fui only tank` and
  `/fui only dps` do the same for the other roles. "Frames only" used to
  leave the tank and DPS grids up as well.
- **Each action bar its own layout, Bartender-style.** Action Bars now has a
  tab per bar (Main bar, Bar 2, Bar 3, Bar 4): how many buttons it has (1 to
  12), buttons per row, vertical or not, button size and spacing. Anything a
  bar leaves alone follows the settings above; "Follow the settings above"
  puts a bar back. Thanks to sprutorgel for asking.

## v0.4.21

- **A unit frame switched off can be switched on again.** Unit Frames >
  (a frame's tab) > Show this frame wrote "off" whichever way you ticked it,
  so a player or target frame turned off stayed off. Reset this section now
  also switches every frame back on (each frame's own size and looks are
  kept). Thanks to ReflexzxGaming for the report.
- **Bar editing and keybind mode toggle off again.** The same slip made
  their toggles (the key bindings for them) switch on but never off.

## v0.4.20

- **Healer tools** (party & raid frames, new *Healer tools* page - VuhDo's
  smart cast and friends):
  - **Click a dead player to resurrect them.** Any heal click on someone dead
    casts your resurrection instead; in a fight it battle-rezzes, if your
    class has one.
  - **Fire a trinket, or an instant like Nature's Swiftness, in the same click**,
    just before the heal - only when the click lands on a living friend.
  - **Your own macro on any click or key**, with `@unit` meaning the player
    under the mouse.
  - **"Resurrecting Solindius"** said to your group as the cast goes (off by
    default).
- **Status** (new page): **raid markers** on the frames, and **one status
  icon** - ready check, incoming summon, incoming resurrection, dead or
  offline - showing the first that applies in an order you set.
- **Panels** (new page - VuhDo's extra panels): up to ten more movable sets
  of frames beside the main grid - **tanks**, **healers**, a **raid group**,
  a **class**, **players you name**, or a **targets** strip (your target,
  their target, your focus). Same clicks and indicators as the grid; each
  can be hidden, run in a row or a column, and dragged with Move frames.
- **Buff Watch** (new page - VuhDo's buff panel): a small movable panel with
  a button per group buff your class brings - red when someone is missing
  it (with how many), yellow when someone's runs out soon, green when
  everyone has it. Click it to cast that buff on the next person who needs
  it, or the group version (Prayer of Fortitude, Gift of the Wild) once
  enough of them do. It holds still in a fight - the game hides buffs until
  the fight ends.
- **Looks** (new page): **HoT bars** that shrink as each HoT runs out;
  **debuff icons** - how many (up to 5), how big, which corner, and
  dispellable-only or every debuff (still drawn by the game in combat);
  a colour for **dead players' bars** and for **incoming heals**; and your
  own **class colours**.
- **"Group 3" labels** over each raid group, and **bars that fill bottom to
  top** (Appearance > Bars fill).
- **Tooltips off means off.** The Tooltips switch now hides every tooltip
  the game fills in - players and creatures, and spells, items and buffs -
  and each has its own Always / Out of combat only / Never. Before, only
  unit tooltips were covered, and one the game showed a second time came
  straight back. ForeverUI's own button hints still show.
- **The settings sidebar no longer runs under Reset to Defaults.** With
  twenty pages the last rows slid under the button; the rows now close up
  just enough to fit.

## v0.4.19

- **The mouse wheel zooms the camera in combat again.** To cast with the
  wheel over your frames mid-fight, ForeverUI has to hold the wheel from the
  pull to the end (the game won't let addons change bindings during a
  fight), and until now that meant it did nothing anywhere else. Away from
  the frames, a tick now does what the key is bound to in your Key Bindings:
  camera zoom, or paging the chat.
- **Tracking works on Forever: Find Herbs, Find Minerals and the rest.** The
  "o" in the strip over the minimap opens the game's tracking menu again.
  Forever's tracking button opens on a press, not a click, so ours had
  quietly done nothing on this client. Herbs and ore show on the minimap
  once you've ticked them, if your character has Herbalism or Mining.
- **The ForeverUI minimap button opens ForeverUI again**, not the world map.
  Forever's zone-name button (whose click opens the map) had been tucked
  into the button row, invisible but still taking clicks, right over it.
  It is left out of the row now, and a button in the row with nothing to
  show no longer takes clicks at all.

## v0.4.18

- **The minimap's day/night indicator is gone.** Blizzard's sun-and-moon disc
  kept peeking out from behind the strip over the map -- Forever draws its
  own at the top of the map, separate from the old one -- and both are now
  put away for you. Want it back? Minimap > "Hide the day/night indicator" (takes a
  /reload).
- **Unit tooltips on and off.** The box that pops up when you point at a
  player or a creature: always, out of combat only, or never. Flip it with
  `/fui tooltips` (or `on` / `off`), a key under ForeverUI in the game's Key
  Bindings, or the switch on the new Tooltips page. Item and spell tooltips
  always show.
- **The Bags page, rebuilt to the mock-up** (`/fui` > Bags): the bag window's
  **scale**, **background opacity** and **border thickness**; lock its
  position, remember the category you were on (even across a reload), a
  quick open/close fade; show or hide the **search bar**, the **item count**
  (left or right) and the **category buttons**; the **currency bar** with
  class-coloured text, coin icons or letters, and its own text and icon
  size. A **live preview** of your own bags on the page, **presets** you can
  save, duplicate and delete (kept for every character), and Restore Defaults.
- **Waypoint arrow.** A 3D arrow above your character that points the way to
  the pin you dropped on the map, or the quest you're tracking (or, if you
  like, the nearest quest in your log), with the distance and the target's
  name under it. Six styles - classic, chevron, crystal, rounded, double
  chevron, spear - in any colour from the colour wheel, any size and opacity.
  It puts itself away when you arrive and can hide in combat. `/fui arrow`
  for the settings, `/fui arrow why` if it isn't showing, `/fui move` to put
  it exactly over your head.
- **Turn the arrow on and off in one go:** type `/fui arrow` (or `/fui arrow
  on` / `off`), bind a key to it under ForeverUI in the game's Key Bindings,
  or use the switch at the top of its page (`/fui arrow options`).

## v0.4.17

- **Your HoTs show in combat again.** In a fight Forever won't let addons read
  auras, so the frames show the HoTs they saw you cast. Two things stopped
  that: every grid read with the *current* role's settings, so a fight in
  tank mode (where "keep HoTs showing in combat" is off) blanked the healer
  frames too; and a HoT cast from your action bars was invisible, because the
  game hides the spell and the target. Each grid now reads with its own
  settings, casts are noted whichever role is current, ForeverUI's action
  bars say which spell you pressed, and with no friendly target a heal is
  counted on you - the game's own self-cast rule.

## v0.4.16

- **The Quests page, rebuilt to the mock-up** (`/fui quests options`): one
  Quest Tracker sheet with Reset to Default; the quest list's switches beside
  a painted scroll; Tracker Appearance and Text Styling with sliders; which
  quests to keep; and on the right a **live preview of your own quests** as
  the tracker would list them, a tip, and the quest-log buttons.
- **The XP Bar page, rebuilt to the mock-up** (`/fui xp`): sliders with the
  value beside them for **Width**, **Height**, and two new settings, **Text
  Size** and **Text Opacity**; a Text Position dropdown; switches for rested
  experience and hiding at max level; and **Restore Defaults**.
- **Role badges.** Tank, healer and damage badges on every frame, so you can
  see who plays what at a glance (Roles page, `/fui frames roles`): switch
  them on or off, keep the old letter instead, choose the size, and put them
  anywhere on the frame or hanging off either side of it (top, middle or
  bottom). Melee and ranged wear the damage badge.
- `/fui frames role Name tank` finds Forever's two-part names from the first
  one: "Solindius" marks "Solindius Runez".
- The Roles page no longer has a paragraph about the old form-following
  running over the group list and the Focus button.
- **HoT and aura indicators, your way.** On the healer frames' Auras page
  (`/fui frames auras`) every watched spell now has:
  - **Where on the frame:** a little map of the frame, five across and three
    down: fifteen places, not four corners. Several spells in one place sit
    side by side, so Rejuvenation and Regrowth can live together in the top
    left. **Nudge** arrows then move a spell a pixel at a time from there.
  - **What it looks like:** its own icon, a square, or a symbol (dot, ring,
    diamond, triangle, star, heart, spade, club, cross, plus, moon) in any
    colour from the colour wheel.
  - **Its own size and its own timer,** if you want it different from the rest.
- Below the lists, for every indicator on that role's frames: **size**,
  **timer** (counts down, counts up, or none), **timer text size**, and where
  **your HoT row** sits.

## v0.4.15

- **Projected healing on the bar.** An incoming heal now draws ahead of the
  health fill as a ghost -- half-transparent, with a tick at the front -- so
  it reads as healing that is on the way, not healing that already landed.
  Yours is brighter than everyone else's.
- **An overheal lane.** Turn it on under your healer frames and every bar
  keeps a narrow lane at its right end: a heal that would spill past full
  runs into the lane, so you can see the waste without doing the arithmetic.
  **Lane width** is a slider, and the lane is off by default.
- **The role shell is optional.** Tank, Healer and DPS frames each have
  **Show the frame shell** at the top of their page: switch it off and you
  get the health bar and the name alone, the way Blizzard's frames look.
- **The Modules, Cast Bar and Keybinds pages are rebuilt.** Painted cards, a
  preview panel, and the settings that were missing: the cast bar's spell
  name, spark, latency band, texture, bar and border colours and a lock; the
  keybind page's saved sets, with export and import as text you can paste to
  a friend, hover-binding, mouse buttons and modifiers, and a bind sound.
- **A drawn crest and name.** The options window wears the hand-drawn badge
  and wordmark instead of the infinity mark and two lines of type.
- **Frame Management sits at the top of General**, where it should have been:
  moving and resetting frames is what that page is opened for.

## v0.4.14

- **Pick your own border colour -- everywhere.** The blue on everything
  ForeverUI draws is a setting: **General > Border colour** opens the colour
  wheel and the whole interface follows at once. Not just the edges: the chat
  box and its hairline, the chat tab, the minimap coordinates and zone name,
  the quest tracker's tabs, chevrons, rules, eye and gear, the bag window's
  rules and counts, the micro bar's tiles, keys and icons.
- `/fui border` opens it, `/fui border 0.9 0.4 0.1` sets it outright, and
  `/fui border reset` puts the blue back.

## v0.4.12

- **Incoming heals actually show up.** On the Forever beta the game hands
  these numbers back as "secret" values, and the old code needed to measure
  them, so the prediction never drew for anyone. It is now drawn straight
  from the game's own numbers: your heal bright over everyone else's,
  starting where the health fill ends. (Thanks for the report.)
- **The tooltip can get out of the way.** It followed the cursor and covered
  the frame you were pointing at. On each frame > "Tooltip when hovering a
  frame": at the cursor, beside the frames, or not at all.
- **The micro bar is yours to colour.** Border, glow, tile and text colours
  are settings, and the blue border and its glow can be switched off.
- **Chat no longer breaks on a secret value.** Printing one (which some game
  functions return) took the copy history down with it.

## v0.4.11

- **Hover a button and press a key.** Binding used to need a click to pick a
  button first, so hovering and pressing -- what every other bar addon does --
  bound nothing. Now the key goes to the button under the mouse: it lights up,
  its tooltip shows what it is bound to, and Backspace clears it. Picking with
  a click still works if you would rather press the key elsewhere on screen.
  (Thanks, jayangek3532.)
- **The mode tells you what it is doing.** A small panel holds the
  instructions, the last thing bound and a Done button, instead of paragraphs
  in chat.
- **Typing beats binding.** With chat open, what you type is typed -- even
  with the cursor resting on a bar.
- **A button can keep two keys.** A button bound to both a key and a mouse
  button used to lose one of them at the next login.
- **The Keybinds page is rebuilt**: Keybind Actions, Binding Options (hover to
  bind, mouse buttons, modifier combinations, a sound on bind, key text on
  buttons) and Saved Keybinds.

## v0.4.10

- **Your changes survive a quick reload.** The backup that carries your
  setup through the Forever beta's saving bug was only written every 20
  seconds, so a click-cast set and reloaded straight away could be lost. It
  is now saved within a second of any change, and again just before
  "Save and reload UI" reloads. (Thanks, oxydie.)
- **A notice about the beta's saving bug.** If the game didn't load your
  settings, a short window explains that it's a Blizzard bug affecting every
  addon, what ForeverUI keeps for you, how to keep your changes (make the
  change, wait a few seconds, then reload), and how to report it -- with a
  ready-made report to paste in. Please report it: the more reports, the
  sooner it's fixed. /fui saving opens it any time.

## v0.4.9

- **Each role's grid has its own look.** Healing, Tanking and DPS keep their
  own size, bar texture, colours, text and borders -- change the tank's bars
  and the others stay as they are.
- **A new Health Bar tab.** Each role window's Appearance page now has tabs
  (Health Bar, Power Bar, Text, Borders, Size). Health Bar has texture and
  style pickers with samples, 21 bar backgrounds as picture tiles (carbon,
  metal, runes, wood, hex, nebula, embers, frost and more), full / low /
  critical health colours with their own thresholds, your own colour or the
  grid's colour, gradient fill, show health lost, animate on heal,
  transparency, and a live preview.
- **Painted bar fills.** Twelve new bar textures -- Sheen, Vines, Energy,
  Swirl, Metal, Runic, Marble, Heartbeat, Honeycomb, Dotted, Starry, Braid --
  tinted by whatever colour the bar is. Also offered on the unit frames.
- **Fixed: all three grids update.** With more than one grid up, only one of
  them was refreshed on health changes and restyled on setting changes.
- **Fixed: opening the character window from the micro bar** no longer
  throws a "secret number value" error. The micro bar hands the click to
  Blizzard's own buttons; the Y tile opens Forever's Legacy track.

## v0.4.8

- **Fixed: "MultiBarRight:SetScale(): Scale must be > 0".** ForeverUI hides
  Blizzard's micro menu by parking it off screen, and it was parked above the
  screen. Blizzard sizes its right-hand action bars to the space between the
  minimap and that menu, so the space came out negative and the game threw
  this error whenever it re-laid those bars. It's parked below the screen now.

## v0.4.7

- **The mouse wheel works on the grids.** Wheel Up and Wheel Down over a
  Healing, Tanking or DPS frame now cast what you bound to them. Three things
  were in the way: the wheel's clicks were stored under a name the game never
  looked for, a single wheel tick was ignored, and the wheel over one grid
  used another role's spells. Each grid now uses its own.
- **Macs: the wheel goes the way you roll it.** macOS reverses the wheel by
  default ("natural scrolling"), so rolling down reached the game as Wheel Up.
  ForeverUI now corrects for it on a Mac. If you've turned natural scrolling
  off, untick "Reverse the mouse wheel" on the General page of the role window.
- **The quest list no longer overlaps itself.** A long objective that wraps
  onto a second line pushes the next one down instead of being drawn over it.

## v0.4.6

- **Your setup survives the beta's saving bug.** The Forever beta currently
  saves every addon's settings and never loads them back after a restart
  (a client bug, forever-bugs #34), so ForeverUI kept dropping back to the
  full interface. It now keeps the essentials in one or two character macros
  named "FUI Save 1", "FUI Save 2" -- your setup answers, which parts of
  ForeverUI run (Frames only stays Frames only), your role grids, every
  role's click-casts and where each grid sits -- and brings them back at
  login when the game hands back nothing. You don't need to do anything;
  please don't delete those macros. Other settings still start from their
  defaults until Blizzard fixes the client.
- **It tells you what happened.** The login warning for the saving bug never
  fired before; it does now, and the setup screen explains it too.

## v0.4.5

- **A painted options window.** The main window is a tavern war-room: a
  castle scene across the top, parchment cards, the candle and mug in one
  corner and the quill and "A Better Azeroth Together" scroll in the other --
  and the page scrolls behind the scroll, not over it. One serif face
  throughout, dark controls with brass edges, purple for what's chosen.
- **Painted role windows.** Heal, Tank and DPS each open on their own art:
  a moonlit forest for healers, a burning fortress for tanks, a violet
  castle between two banners for DPS -- each with its own crest, colours and
  mark. The healer window now uses the Keybinds card (Modifier Key / Mouse
  Key tabs, Clear All) like the other two.
- **Unit frames you can shape.** Hide the name or the health text, place
  them, pick a bar texture, a background (VuhDo-style), a border and its
  colour, the fill direction and more -- per frame, with a live preview.
  The grids take the same text, texture and background choices, and the
  Healing/Tanking/DPS titles over them can be turned off.
- **DPS is purple** everywhere it has a colour.
- **Fixed:** the DPS window's header said "Healer".

## v0.4.4

- **A new Profiles page.** A list of your profiles -- star your favourites,
  sort by name, role, version or date, search -- and the chosen one beside it:
  its role, a description, when it was made and changed, who made it, what it
  started from, and a preview. Apply, Edit (rename and describe it in place),
  Duplicate and Delete from there. Tabs for All, Mine, Imported and Defaults;
  the Defaults (Standard, Healer, Tank, Damage) make a ready profile in one
  click.
- **Share profiles as text.** Export one, or all of them as a backup, and
  paste one in to import it. An import always arrives as a new profile and
  never overwrites one you have. (WoW addons can't read or write files, so
  copy and paste is how profiles travel.)
- **The quest list goes flush right.** Its move handle kept an old size and
  hung off the side of the panel, which stopped it at the screen edge.
  Every move handle now fits its frame.
- **Coordinates you can read.** They were drawn underneath their own dark
  box; now they sit on top of it, in bright blue.

## v0.4.3

- **A Target you pick stays picked.** Choosing *Target* for left click looked
  exactly like the out-of-the-box setting, so the class defaults replaced it
  with a heal the next time they ran -- every login, on the current beta. A
  click you set by hand is now marked as yours and is never overwritten.
- **No more cooldown errors when you are stunned.** The "SetCooldown ...
  Secret values are only allowed during untainted execution" error at
  ActionButton.lua:881 came from the loss-of-control spiral a button shows
  while you are stunned, feared or silenced, and from the gamepad action
  bars. Both are covered now, including buttons the game makes later.
- **Save and reload UI reloads.** It rebuilt the frames in the same click,
  which the game refuses; it reloads cleanly now.
- **Testing tools** for anyone checking the addon: `/fui test setup` walks
  through first-time setup as a new player (`/fui test setup dry` changes
  nothing), and `/fui test group` fills every grid with a pretend party (or
  `10`, `25`, `40` for a raid) whose clicks really cast -- on you. `/fui test
  help` lists them all.

## v0.4.2

- **Choosing Healer now means Healer.** Setup asked how you play and then
  never acted on it: the step that should have taken the other grids down
  called something that did not exist, so everyone got all three. Pick Healer
  and you get the healing grid, and nothing else. Tick *I want more than one
  role grid now* to have two or all three.
- **A new welcome, in five steps.** The author note and the installer were two
  windows, and the installer asked the role question twice. It is one window
  now: what ForeverUI is (with the three grids side by side), how much of it
  you want, how big, how you play, and a summary with who to tell when
  something breaks. It sizes itself to your screen, and */fui install* brings
  it back any time.
- **Setup reloads when you ask it to.** The game refuses a reload made in the
  same click as the setup's other changes, so the last step is *Apply*, then
  *Reload now*.
- **Damage is a real choice.** Picking Damage used to be ignored; it sets up
  the DPS grid now.
- **About settings resetting on logout.** This is a bug in the Forever beta
  client itself: since about 17 September it writes every addon's settings to
  disk and never reads them back, for all addons, not just this one. Your
  changes last until you quit. ForeverUI now says so at login rather than
  looking broken. It is tracked at github.com/ClassicWoWCommunity/forever-bugs
  (issue 34); the community tool ForeverSVFix works around it until Blizzard
  fixes the client.
- **Bars no longer draw blank under some folder names.** The standard layout
  named the bar texture by a developer folder path; saved paths are now
  re-rooted to wherever the addon is installed.

## v0.3.4

- **How much of it do you want?** One click for the whole interface, for only
  the party & raid frames, or for everything except them -- so somebody who
  wants nothing but healing frames, or who keeps VuhDo for the group and likes
  the rest, gets there without hunting through a dozen switches. It is the
  first card on the General page, the second question the installer asks, and
  `/fui only frames` / `only ui` / `only everything` from the command line. The
  line under the buttons says what is actually on, and tells the truth when you
  have flipped something by hand.
- **Nameplates, rethought.** Six tabs -- General, Friendly, Enemy, NPC,
  Personal, Advanced -- and about sixty settings behind them. Each category of
  unit picks its own rule (always, in combat, when targeted, never), colour and
  size. Text and layout, health bar with a low-health warning and incoming
  heals, cast bar with the spell's icon and a latency mark, threat on the edge,
  your own debuffs, filters for critters, pets, the dead and anything you can't
  attack, name lists you type yourself, and separate sizes for your target,
  your focus, bosses and elites. A live preview shows one plate of every colour.
- **Nameplate colours now match the game.** Reading the attitude scale as three
  buckets made an unfriendly Cloudrunner -- which never attacks first -- come
  out the same red as something that hunts you, and anything unreadable came
  out red as well. Red, orange, yellow and green mean what they mean in the
  game, tapped mobs go grey so you know there is no experience or loot in them,
  and nothing invents an enemy any more. `/fui plates why` explains any plate.
- **Nameplates can be turned off entirely.** For anyone running Plater: the
  game's own plates come back, the aura lists go home, and every nameplate
  setting is put back as it was found, without a reload. If a nameplate addon
  is already installed ForeverUI stands aside by itself at login, once.
- **Quests you are on are listed again.** The tracker read the game's watch
  list, which this client never ticks, so a character with seven quests could
  be staring at an empty panel. It reads the quest log now. "Only tracked
  quests" on the Quests page puts the old behaviour back.
- **Presets for a nameplate setup**, saved by name inside the character's one
  profile, with copy and paste as text.
- **New logo** throughout, and the greyed-out glyphs replaced with a set of
  white icons across every window.

## v0.3.3

- **A new face.** The ForeverUI window: emblem, title and tagline up top with
  a search box that narrows the pages; an icon sidebar with the open page lit;
  each page a big title, a subtitle and cards -- General reads UI Scale (a real
  slider) | Font | Bar Texture (dropdowns) across one line, the switches two
  across with check marks, and Move / Reset / Installer as glyph tiles; Apply
  and Close in the footer; Reset to Defaults asks twice.
- **The Healer window** wears the same face in green: icon sidebar, three cards,
  binding rows showing the bound spell's icon with an x to clear (a + on an
  empty one), a spell search, three wide tiles across the foot and a status row
  with Save now.
- **The Tank window** to its own concept in orange: a title block -- shield,
  Tank, "Hold the line. Control the fight.", SURVIVE CONTROL PROTECT -- one
  Keybinds card with Modifier Key / Mouse Key headings, Bindings (modifier) with
  Clear All, the click actions as glyph buttons, and a Tank Settings column on
  the right with every page one click away.
- **Micro bar switch.** Show or hide it from its page, or with /fui micro.

## v0.3.2

- **Bags, drawn by ForeverUI.** Title with the bag icon, a search line with
  used / total, a sidebar of categories -- All, Equipment, Consumables,
  Materials, Quest Items, Miscellaneous -- with counts, slots ringed in the
  item's quality colour, the money line, and Clean Up. The slots are Blizzard's
  own secure item buttons, so picking up, using and selling are untouched; the
  B key, the bag bar, merchants and the bank open it as before.
- **Quests, drawn by ForeverUI.** Quests (N) with a roll-up; All / Zone / Story
  / Daily tabs; a badge, [level] title, distance and arrow per quest, with its
  objectives ringed and ticked; the quest you follow highlighted (click a row to
  follow it); show or hide completed quests. Blizzard's tracker is put away.
- **Nameplates to the mock-up.** One box: name and level on a top row, a flat
  health bar with the percent inside, a cast bar with the spell's icon and a
  0.8 / 2.0 timer. Your own debuffs -- Moonfire, Faerie Fire -- are drawn above
  the plate by the game itself, so they show in combat.
- **Minimap.** A strip over the map with the zone name (click for the world
  map), tracking and zoom; coordinates in a corner box; Blizzard's top strip,
  tracking sun and zoom pair gone; the button bar shows only buttons that have
  something on them.
- **Chat.** The box hugs the messages and the input line; the tab wears the
  box's clothes; Blizzard's side icons, frame art and the jump-to-bottom arrow
  are gone, with flat Menu and Copy buttons in the corner.
- **Micro bar.** One flat row -- Char C, Spells P, Talents N, Quests L, Map M,
  Social O, Achieve Y, Bags B, Menu Esc -- movable with the rest.
- **Keybinds that stick.** Binding a key saves it and lets go of the button;
  Escape lets go, Backspace clears. Every key the addon sees is echoed in chat.
  Side mouse buttons and the wheel bind from anywhere on screen. The binds are
  kept in ForeverUI's own per-character and Shared sets and put back on the bars
  at every login; copy between the two from the Keybinds page. Short hotkey
  labels (M4, N*) stay put over Blizzard's long ones.
- **Fixed: the level-up crash.** Hiding an Edit Mode frame the Blizzard way
  wrote into Edit Mode under our taint, and the next layout pass died reading an
  aura. Every hide now goes through the game's own originals.
- **Fixed:** a party member's hidden power maximum no longer throws; a cast
  bar's uninterruptible flag is read through the guard; the stance, pet and
  possess bars are hidden with the rest.

## v0.3.1

- **One save for the whole addon.** The party and raid frames no longer keep
  profiles of their own beside ForeverUI's. Everything -- bars, chat, healer
  frames, tank frames -- lives in the one ForeverUI profile your character is
  on, and the healer and tank setups sit inside it side by side (DPS will too).
  The frames' own Profiles page is gone; ForeverUI > Profiles is the one place.
  Switching ForeverUI profiles switches the frames with it, role and all.
- **A straight answer to "did it save?"** `/fui saved` shows whether the game
  handed your settings back at load, step by step. If a profile that was set up
  before comes back empty, one line at login says so -- that is the client not
  reading the file (it happens to an addon name it first met with a file already
  in place), not the addon forgetting. `/fui frames status` says which profile
  the frames are writing into.
- **The beta's Issue Reporter is hidden.** It used to float a quarter of the way
  up the screen every login. *General > Hide the beta Issue Reporter* is on by
  default; turn it off and it sits tucked in the top-left corner instead, small
  and green.
- **Frame settings changes no longer take spare copies or snapshots** -- there is
  nothing to guard against now that they are in the one profile.
- The frames' chat lines say ForeverUI, not HealForever, and point at
  `/fui frames` instead of `/hf`.
- The addon runs under any folder name: every media path follows the folder.

## v0.3.0

- **HealForever and TankForever are now part of ForeverUI.** One addon, one
  download. At first login ForeverUI asks Healer, Tank or Damage and sets the
  party and raid frames up for that role. Healer frames are HealForever exactly:
  click-casting, incoming heals, HoTs, dispels, watched auras. Tank frames add
  the threat tools: right-click engages whatever a player pulled, taunt where
  your class has one, loose/pulling/holding borders, an AGGRO alarm, a threat
  meter, a Loose list, and the name of what each player is fighting. A druid or
  paladin keeps separate healer and tank setups, so switching never clobbers the
  other.
- **It asks before switching roles.** Change spec within your class and the
  frames don't move on their own -- they ask whether to switch tank to healer or
  back. A damage spec is left alone, because DPS frames aren't built yet. Change
  it any time with /fui role tank or /fui role healer, and open the settings with
  /fui frames.
- **Your old HealForever settings come across on their own.** The first time the
  merged frames run with the old addon still enabled, your bindings, profiles and
  frame positions are copied over in memory, and it tells you it's safe to turn
  HealForever off.
- **Keybinding actually binds now.** Setting a key over a button did nothing on
  this client: the "is the mouse over this button?" check could hand back a
  value the game won't let an addon read, which came out as "no button here,"
  so the key bound nothing. ForeverUI now follows the mouse onto a button
  through the button's own enter/leave, which the game reports plainly, and
  binds to that. The button you're about to bind also brightens while you hover
  it in keybind mode.
- **Mouse buttons bind too.** Right-clicking a button used to cast the spell
  instead of binding. Now, in keybind mode, a thin catcher sits over the button
  you're hovering: right-click, middle-click, an extra mouse button or the
  wheel all bind to it, and the spell no longer fires while you do it. (Left
  click is left alone -- it clicks the whole UI.)
- **Keybinds have their own page.** A "Keybinds" category sits on the left just
  under Action Bars, with the binder, a clear-all button, and a choice of where
  the binds are saved: **this character only** or **all characters** (the game's
  own per-character and account-wide binding sets). Easy to get out of, too:
  the button says "click here (or Esc) when done," and Escape in open space
  leaves keybind mode.
- **Long option pages scroll.** The Action Bars page ran off the bottom of the
  window with no way to reach the last rows. Every page now scrolls with the
  wheel and opens at the top.
- **The chat is one square box.** The tabs, the messages and the typing line now
  sit inside a single dark panel with a thin blue edge -- no separate boxes
  floating above or below -- and the Copy button moved into the top-right
  corner, on the tab row. A faint hairline sets the input line off from the
  messages.
- **The quest list sits under its header.** The modern tracker reserves a tall
  empty band above the first quest; the panel used to include it, leaving a
  slab of black between the blue "Quests" header and the quests. It now drops
  onto the first quest so the header sits right on top of the list.
- **An error book, so bugs can be reported.** ForeverUI now catches the Lua
  errors it causes and keeps them -- de-duplicated, with a tally and the
  version they happened on -- in your saved variables. `/fui errors` opens a
  window you can select and copy from; paste it into a Discord or CurseForge
  comment and I can fix it. `/fui errors clear` empties the book. A quiet
  one-line notice at login says how many are waiting. It chains onto whatever
  error display you already use (BugSack, the red box, nothing), so it never
  takes their place. Addons can't send anything over the network, so a report
  is always a copy-and-paste, never automatic.

## v0.2.4

- **Chat feels like a chat room.** A solid dark background with a thin blue
  border -- the rest of the UI's look -- sits behind each window; the scroll
  arrows are gone (the wheel still scrolls) and the dock icons (social, voice,
  channel, menu) are gathered into one tidy column instead of scattered down
  the edge. Emoticons -- :) ;) :D :'( <3 :P B) and word codes like :fire: --
  turn into little emoji, and web links become clickable (they open a box to
  copy from). Two switches in the Chat options turn emoji and links off.
- **The quest tracker keeps only the nearest quests.** A full log used to run
  off the bottom of the screen; now the tracker holds the nearest few
  (default 5) and the rest stay in the quest log -- an "Open the quest log"
  button and /fui quests log open it, and /fui quests prune lists low-level or
  far-off quests you could abandon (it never abandons one for you).
- **The quest panel fits the list.** It was as tall as the tracker's own
  reserved height -- most of the screen -- so it became a giant empty box that
  collided with the minimap. It now measures the visible lines and ends just
  under the last quest.
- **A narrower font by default.** Arial Narrow, with the body text at 12 and
  the smaller labels a touch below Blizzard's, so more fits and the panels
  read cleaner. Any font is still yours to pick; a profile still on the old
  default is moved across once.

## v0.2.3

- **The chat matches the rest of the UI, and you can copy it.** The ornate
  typing box is flattened to a panel and the messages and tabs take our
  font. A **Copy** button on the chat (and **`/fui copy`**) opens a window
  with the whole conversation as plain, selectable text -- colour codes,
  links and inline textures stripped to the words. Hiding Blizzard's chat
  still works and is still reversible.
- **The quest list comes back after you roll it up.** Collapsing then
  re-expanding the tracker left an empty black box: on this client the old
  collapse globals don't exist, so expanding was a bare show with nothing to
  rebuild the list and no real height to measure. It now uses the tracker's
  own collapse, forces a rebuild, and re-measures on the next frame.
- **A grabbed frame is no longer re-anchored in combat.** `/fui grab` holds
  a frame to its handle whenever the game moves it -- but that is a SetPoint,
  and on a frame that only reads protected once a fight starts it would be
  blocked and taint us. It now waits for the fight to end.
- **The copy window (and any of our edit boxes) no longer errors on open.**
  Our font helper passed nil where a text box wants an empty string for "no
  outline", which a font string tolerates but an edit box does not.
- **`/fui` lists every command now**, grouped into everyday and diagnostic,
  and the options General tab says in a line what ForeverUI is.

- **No more combat error floods from the quest tracker.** Rolling the tracker
  down used to call its update from our code, which taints the whole pass --
  and on this client that pass reads auras and dies, over and over. It now
  leans on the tracker's own collapse, which rebuilds it the safe way, and
  never pokes it in combat.
- **Action-bar cooldowns no longer flood the log in combat.** Blizzard's
  cooldown update runs on our buttons tainted, and in combat the secret
  cooldown numbers made it throw many times a second. The call is guarded:
  quiet in combat, unchanged out of it.

## v0.2.2

- **The cast bar holds.** It used to end about a second in on some casts,
  with no error -- a late stop event for the *previous* cast wiped the new
  one off the moment it appeared. Each cast now carries the id its START
  event gave it, and a stop only ends the cast it names, so the bar fills
  and finishes on its own clock. Verified in game.
- **Keybinding no longer swallows the keyboard.** Every bar button used to
  listen for keys, so one that erred left the whole keyboard dead -- chat
  included -- with no way to type the command that would end it; and typing
  a chat message in keybind mode bound each letter to a button. Now a single
  frame listens, passes the key on before it does anything that could go
  wrong, and only keeps it once a button is under the mouse. The keys the
  game can't do without -- Enter, Escape, /, Tab -- are refused outright.
- **"Clear all keybinds" gives the game its keys back.** Clearing a binding
  used to leave the key doing nothing; it now restores the game's own
  binding for anything a button had taken (Enter to chat, the movement keys,
  the number keys), so a tangle is always recoverable by a click.
- **The minimap's coordinate sweep no longer hides other addons' windows.**
  It walked the whole interface for text shaped like a coordinate pair and
  hid the frame that text hung off -- and a version label like "0.14.1"
  matches, so another addon's window was hidden five times a second. The
  sweep now keeps to the minimap, and never hides a frame that isn't part
  of it; the game's own white coordinates are still gone.
- **A Done button for move mode.** Unlocking the frames now opens a small
  panel -- Done, Reset all -- so there's a clear way out that isn't a slash
  command, and closing it puts the handles away.
- **`/fui grab`** hands any Blizzard frame over to the mover: point at it,
  run the command, and drag it with the rest. `/fui grab reset` gives them
  all back.
- **The quest tracker shows one header, once.** The strip that thins
  Blizzard's tracker now runs whenever the tracker rebuilds itself (through
  its own update method on this client, not a global), matches section
  headers by the game's own strings, and measures the space a hidden header
  held so the list sits flush beneath -- no second "Quests", no gap.
- **`/fui shot`** takes the game's screenshot from a click; `/fui shot 5`
  waits five seconds and hides the chat first, for a clean picture.
- **`/fui cast trace`** and **`/fui cast dump`** keep a short, secret-safe
  record of what happens to a cast, for when a bar behaves oddly.

## v0.2.1

- **Every frame is clickable again.** The drag handle over each frame was
  still catching the mouse with move mode off -- on this client
  EnableMouse(false) alone doesn't stop a movable frame -- so action bars,
  minimap buttons and the quest list took no clicks, and "clicking" one
  dragged it. Put-away handles now give up the mouse, the drag and their
  strata entirely.
- **Your setup is the standard.** `tools/adopt_profile.lua` snapshots the saved
  profile into `Config/Standard.lua`; a fresh character, a new profile or a
  reset frame lands on it. Precedence: your drag, then where a module put a
  frame, then the standard, then the code's fallback.
- **The game's own coordinates are gone for good.** They fill in a moment
  after login, after the first sweep had already looked; the bar now keeps
  sweeping until it finds them, and hides the frame they hang off. `/fui
  coords` names anything on screen that reads like coordinates.
- Bars can be laid vertical individually, and bars 3 and 4 can be switched
  on from the window at last.
- Minimap buttons: horizontal, vertical or grid; the clock at the top of a
  column or the far end of a row; the zone name drawn under the bar.
- **Cast bar** -- a flat, movable bar for your own casts: name, seconds left
  over total, icon. `/fui test` shows a pretend cast to place it.
  **Known problem on Forever:** it can end early, about a second in, on
  some casts. No error is thrown; the cause is still open.
- **Cast timing is kept clear of secret values.** The target frame divided a
  secret start time and threw -- and every throw taints the addon until your
  own buttons stop casting. All casts now go through Core/Casting.lua: the
  bar's range is the game's own milliseconds untouched, the label is tried
  once inside a guard, and nothing read from a cast is truth-tested,
  compared or branched on. Stops are matched to casts by the START event's
  own ID, since the one UnitCastingInfo returns is secret here.

## v0.2.0

The first build worth putting in front of anyone: a flat look of its own, three
new modules, and settings that survive a reload.

### Its own look
- Every panel, button and checkbox is drawn by ForeverUI rather than borrowed
  from Blizzard's templates. Flat dark fill, one real pixel of border, accent
  blue on hover. No stone frames, no gold, no red gradient buttons.
- The options window no longer pushes its controls off its own right edge, and
  shrinks to fit if your UI scale makes it taller than the screen.

### Action bars
- Buttons are the spell and nothing else: the slot art is gone, the icon fills
  the whole block with its own border cropped off, and the game putting that
  art back is undone as it happens.
- **Keybinding.** `/fui keys`, hover a button, press a key. Escape clears it.
  Modifiers count, and the corner text is short enough to read on a 30px
  button. Bindings set in Blizzard's own window show up too.
- Buttons are locked in normal play so nothing is knocked off by accident --
  but while your cursor is carrying a spell they accept it, so arranging a bar
  needs no mode and no command.
- Blizzard's bars, micro menu, bag bar and status bars are hidden, including
  the names Classic Era uses rather than only the old ones.

### New modules
- **XP bar** -- a thin purple line you can put anywhere, with rested experience
  as a lighter band and the numbers on hover.
- **Quest tracker** -- Blizzard's list in a panel of its own: a header that
  rolls it up, a position dropdown, a drag handle, and its gold headers and
  artwork stripped. It is held in place against the tracker re-anchoring
  itself, which is what used to leave an empty box behind.
- **Nameplates** -- flat health bars over enemies with name, level, percent and
  a cast bar. Off until you turn it on.

### Settings that stay
- The quest tracker no longer deletes its own saved position at every login.
- The installer asks once. Closing it counts; it used to reappear forever and
  overwrite your scale and frame positions if you let it finish.
- Your profile is chosen once the game says which character logged in, not
  before, so nothing is saved against a placeholder.
- Chat comes back the moment you untick it, with the conversation intact --
  and where a reload genuinely is needed, ForeverUI does it for you, after a
  pause, never in combat.

## v0.1.0

- First build: core, profiles, movers, options window, unit frames, action
  bars, chat.
