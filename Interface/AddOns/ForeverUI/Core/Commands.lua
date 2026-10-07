local _, ns = ...

-- /fui and friends. Commands open windows rather than expecting anyone to
-- remember syntax; the few that take an argument say so in /fui help.

local HELP = {
  "Everyday",
  { "/fui", "open the options window" },
  { "/fui move", "drag frames where you want them (Done when finished)" },
  { "/fui grab", "point at any Blizzard frame to make it movable" },
  { "/fui grab reset", "hand every grabbed frame back" },
  { "/fui unlock", "drop new spells onto the bars" },
  { "/fui lock", "lock the bars again" },
  { "/fui keys", "hover a button and press a key to bind it" },
  { "/fui keys reset", "clear the bars' keybinds, give the game its keys back" },
  { "/fui copy", "open the chat as text you can select and copy" },
  { "/fui errors", "show ForeverUI's own errors, ready to copy for a report" },
  { "/fui saved", "did the saved settings come back from disk at load?" },
  { "/fui micro", "show or hide the micro bar (or: micro on / micro off)" },
  { "/fui plates", "who draws the nameplates (or: plates on / plates off for Plater)" },
  { "/fui plates why", "why each plate on screen is the colour it is" },
  { "/fui frames", "open the party & raid frame settings (click-casting)" },
  { "/fui role", "switch role: healer, tank or DPS" },
  { "/fui quests", "roll the quest tracker up or down" },
  { "/fui quests log", "open the full quest log" },
  { "/fui quests prune", "list low-level or far quests you could drop" },
  { "/fui hide", "point at a minimap button to be rid of it" },
  { "/fui shot", "screenshot now (/fui shot 5 waits 5s, hides the chat)" },
  { "/fui test", "show mock frames so you can lay things out solo" },
  { "/fui test setup", "go through first-time setup as a new player (add dry: change nothing)" },
  { "/fui test group", "a pretend party on the grids, to test them solo (10/25/40, off)" },
  { "/fui test help", "every testing tool" },
  { "/fui profile", "profiles: switch, copy, export, import" },
  { "/fui auras", "ForeverAuras: your own cooldown and aura icons (WeakAuras-style)" },
  { "/fui loot", "loot advice: junk, upgrades and gear that isn't for you" },
  { "/fui new", "what's new in this version (and the last few)" },
  { "/fui backup", "your whole setup as text to copy and keep" },
  { "/fui restore", "paste that text back after the beta forgets your settings" },
  { "/fui module <name>", "turn a module on or off" },
  { "/fui qf", "QuestForever: quests on your map and minimap, on or off" },
  { "/fui cooldowns", "Blizzard's Cooldown Manager in ForeverUI's style (also /fui cd)" },
  { "/fui kicks", "kick alerts: enemy casts to interrupt, heals first (/fui kicks test)" },
  { "/fui only heal", "only the healing frames - nothing else of ForeverUI (also tank, dps)" },
  { "/fui only frames", "just the party & raid frames, nothing else" },
  { "/fui only ui", "the whole interface except the party & raid frames" },
  { "/fui only everything", "put it all back on" },
  { "/fui reset", "reset every frame position" },
  { "/fui install", "run first-time setup again" },
  { "/fui off", "turn every module off (/fui on puts them back)" },
  { "/fui version", "what's running, and on which client" },
  "Diagnostics",
  { "/fui bars", "what got hidden of Blizzard's bars" },
  { "/fui click", "why a button isn't clicking (hover it first)" },
  { "/fui coords", "find everything on screen that reads like coordinates" },
  { "/fui scan <text>", "name what's still on screen, so it can be hidden" },
  { "/fui quests dump", "what this client calls the tracker's parts" },
  { "/fui cast trace", "log cast events, for when the cast bar misbehaves" },
  { "/fui cast dump", "print the last cast events" },
  { "/fui share", "send us quest tips, routes and screenshots (BETA)" },
}

-- What /fui off switched off, so /fui on puts back exactly that and no more.
ns.turnedOff = {}

local function Help()
  ns.Print("ForeverUI -- one flat, movable interface for WoW: Forever.")
  for _, line in ipairs(HELP) do
    if type(line) == "string" then
      print(("|cff4dc3ff%s|r"):format(line))
    else
      print(("  |cffffd100%s|r - %s"):format(line[1], line[2]))
    end
  end
end

local function Handle(input)
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = (command or ""):lower()

  if command == "" or command == "config" or command == "options" then
    ns.OpenOptions()
  elseif command == "move" then
    ns.ToggleMovers()
  elseif command == "install" then
    ns.ShowInstaller(true)
  elseif command == "profile" or command == "profiles" then
    ns.OpenOptions("profiles")
  elseif command == "module" then
    local name = rest ~= "" and rest or nil
    local module = name and ns.GetModule(name)
    if module then
      local enabled = not ns.IsModuleEnabled(name)
      ns.SetModuleEnabled(name, enabled)
      ns.Print(("%s is now %s."):format(module.title or name, enabled and "on" or "off"))
    else
      ns.Print("modules: " .. table.concat(ns.moduleOrder, ", "))
    end
  elseif command == "reset" then
    if InCombatLockdown() then
      ns.Print("frames can't be moved in combat.")
    else
      ns.ResetAllMovers()
      ns.Print("frame positions reset.")
    end
  elseif command == "test" then
    -- Bare /fui test is still the mock frames; the rest is Core/Testing.lua.
    if ns.TestCommand then ns.TestCommand(rest) else ns.ToggleTestMode() end
  elseif command == "copy" then
    local chat = ns.GetModule("Chat")
    if chat and chat.OpenCopy then
      chat.OpenCopy()
    end
  elseif (command == "heal" or command == "healer" or command == "tank" or command == "dps")
    and rest == "" and ns.OpenRoleWindow then
    -- /fui heal, /fui tank, /fui dps: that role's window, the same as its
    -- row at the top of /fui. (They used to open click-casting for whichever
    -- role happened to be current, which read as "it ignored me".)
    ns.OpenRoleWindow(({ heal = "healer", healer = "healer", tank = "tank", dps = "dps" })[command])
  elseif command == "frames" or command == "heal" or command == "healer" or command == "tank" then
    -- The party/raid frame engine's own commands (see Modules/Frames).
    if ns.ForwardFrames then ns.ForwardFrames(rest) end
  elseif command == "info" or command == "about" or command == "author" then
    -- Who made it and how to reach him, without hunting for the page.
    if rest == "welcome" then
      if ns.ShowWelcome then ns.ShowWelcome(true) end
    elseif rest == "tag" or rest == "battletag" then
      if ns.CopyBattleTag then ns.CopyBattleTag() end
    else
      ns.OpenOptions("info")
    end
  elseif command == "grids" or command == "grid" then
    -- Which role grids are on screen. Any combination; they are not modes.
    if ns.ForwardFrames then ns.ForwardFrames("grids " .. (rest or "")) end
  elseif command == "role" or command == "roles" then
    if ns.FramesRole then ns.FramesRole(rest) end
  elseif command == "only" or command == "loadout" then
    -- How much of ForeverUI runs at all: everything, only the party and raid
    -- frames, or everything except them.
    local word = (rest or ""):match("^%s*(%S*)%s*$") or ""
    word = word:lower()
    -- /fui only heal (or tank, or dps): only that role's frames, and nothing
    -- else of ForeverUI at all.
    local role = ({ heal = "healer", healer = "healer", healing = "healer", tank = "tank",
      tanking = "tank", dps = "dps", damage = "dps" })[word]
    if role then
      local ok, moved = ns.ApplyRoleOnly(role)
      if not ok then
        ns.Print(moved)
        return
      end
      ns.Print(("%s -- only the %s frames; everything else is the game's own. %d module%s changed."):format(
        ns.ROLE_ONLY[role].label, role == "dps" and "DPS" or role, moved, moved == 1 and "" or "s"))
      return
    end
    if word == "all" or word == "full" then
      word = "everything"
    elseif word == "frames" then
      word = "frames"
    end
    if word ~= "" then
      local ok, moved = ns.ApplyLoadout(word)
      if not ok then
        ns.Print(moved) -- the refusal, which names what it does not know
        return
      end
      ns.Print(("%s -- %d module%s changed."):format(
        ns.Loadout(word).label, moved, moved == 1 and "" or "s"))
    end
    ns.Print(ns.LoadoutSummary())
  elseif command == "plates" or command == "nameplates" then
    -- The handover switch, without opening the window: "plates off" gives
    -- the nameplates back to the game, or to whatever else wants them.
    local module = ns.GetModule("Nameplates")
    if module then
      if rest == "why" or rest == "explain" then
        module.Explain()
        return
      end
      if rest == "probe" and module.Probe then
        for _, line in ipairs(module.Probe("target")) do
          ns.Print(line)
        end
        return
      end
      if rest == "on" or rest == "off" then
        local on = rest == "on"
        ns.db.modules.Nameplates.stoodDown = nil
        ns.SetModuleEnabled("Nameplates", on)
      end
      ns.Print(module.StatusLine and module.StatusLine() or "")
    end
  elseif command == "micro" or command == "microbar" then
    local module = ns.GetModule("MicroBar")
    if module and module.Toggle then
      local state = (rest == "on" and true) or (rest == "off" and false) or nil
      ns.Print(("micro bar %s."):format(module.Toggle(state) and "shown" or "hidden"))
    end
  elseif command == "modules" then
    ns.OpenOptions("modules")
  elseif command == "keybinds" or command == "binds" then
    ns.OpenOptions("Keybinds")
  elseif command == "castbar" then
    ns.OpenOptions("CastBar")
  elseif command == "xp" or command == "xpbar" then
    ns.OpenOptions("XPBar")
  elseif command == "tooltips" or command == "tooltip" or command == "tips" then
    local tips = ns.GetModule("Tooltips")
    if tips and (rest == "options" or rest == "settings") then
      ns.OpenOptions("Tooltips")
    elseif tips and (rest == "on" or rest == "show") then
      tips.Toggle(true)
    elseif tips and (rest == "off" or rest == "hide") then
      tips.Toggle(false)
    elseif tips and rest == "combat" then
      ns.db.modules.Tooltips.units = "combat"
      ns.db.modules.Tooltips.other = "combat"
      ns.Print("tooltips hide in combat.")
    elseif tips then
      tips.Toggle()
    end
  elseif command == "arrow" or command == "waypoint" then
    local arrow = ns.GetModule("Arrow")
    if arrow and rest == "why" then
      arrow.Why()
    elseif rest == "options" or rest == "settings" or not arrow then
      ns.OpenOptions("Arrow")
    elseif rest == "on" or rest == "show" then
      arrow.Toggle(true)
    elseif rest == "off" or rest == "hide" then
      arrow.Toggle(false)
    else
      arrow.Toggle()
    end
  elseif command == "border" or command == "accent" then
    -- /fui border            the colour wheel
    -- /fui border 1 0.6 0.1  set it straight away (0-1, or 0-255)
    -- /fui border reset      back to blue
    if rest == "reset" or rest == "blue" then
      ns.db.accentColor = { unpack(ns.Colors.defaultAccent, 1, 3) }
      ns.ApplyAccentColor()
      ns.Print("border colour back to blue.")
    elseif rest ~= "" then
      local r, g, b = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
      r, g, b = tonumber(r), tonumber(g), tonumber(b)
      if not (r and g and b) then
        ns.Print("try |cff4dc3ff/fui border 0.9 0.4 0.1|r, or |cff4dc3ff/fui border|r for the colour wheel.")
      else
        if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        ns.db.accentColor = { r, g, b }
        ns.ApplyAccentColor()
        ns.Print(("border colour set to %.2f %.2f %.2f."):format(r, g, b))
      end
    else
      ns.OpenOptions("general")
      ns.Print("General > Border colour -- click the swatch for the wheel.")
    end
  elseif command == "loot" then
    ns.OpenOptions("Loot")
  elseif command == "auras" or command == "aura" or command == "fa" or command == "foreverauras" then
    ns.OpenOptions("ForeverAuras")
  elseif command == "new" or command == "whatsnew" or command == "news" or command == "changes" then
    if ns.ShowWhatsNew then ns.ShowWhatsNew() end
  elseif command == "backup" or command == "export" then
    if ns.ShowSetupBackup then ns.ShowSetupBackup() end
  elseif command == "restore" or command == "import" then
    if ns.ShowSetupRestore then ns.ShowSetupRestore() end
  elseif command == "saving" or command == "savebug" then
    if ns.ShowSaveNotice then ns.ShowSaveNotice() end
  elseif command == "saved" or command == "trace" then
    if ns.SavedReport then ns.SavedReport() end
  elseif command == "share" then
    -- The link to send tips, routes and screenshots, and the text to paste.
    if ns.ShareWithForeverUI then ns.ShareWithForeverUI() end
  elseif command == "capture" and ns.IsOwner and ns.IsOwner() then
    -- The owner's play recorder (Core/Capture.lua); not there for players.
    ns.Capture.Command(rest)
  elseif command == "errors" or command == "error" or command == "bug" or command == "bugs" then
    if ns.Errors then
      if rest == "clear" or rest == "reset" or rest == "wipe" then
        ns.Errors.Clear()
        ns.Print("error log cleared.")
      else
        ns.Errors.Open()
      end
    end
  elseif command == "cast" then
    if rest == "trace" then
      ns.Casting.tracing = not ns.Casting.tracing
      ns.Print(ns.Casting.tracing and "cast tracing on - cast something." or "cast tracing off.")
    else
      local trace = ns.db.castTrace or {}
      ns.Print(("cast trace, %d lines:"):format(#trace))
      for _, line in ipairs(trace) do
        print("  " .. line)
      end
    end
  elseif command == "keys" and (rest == "reset" or rest == "clear") then
    local module = ns.GetModule("ActionBars")
    if module then
      module.SetMode(nil)
      module.ClearAllKeybinds()
    end
  elseif command == "shot" or command == "screenshot" then
    -- "/fui shot 3" waits three seconds first, and says nothing, so the
    -- picture shows the UI and not the line announcing the picture. While
    -- it waits, chat text is told to fade at once instead of after two
    -- minutes, so the picture isn't captioned with the commands that set
    -- it up; the old fade time comes back afterwards.
    local delay = tonumber(rest)
    if Screenshot and delay and delay > 0 and C_Timer and C_Timer.After then
      local restore = {}
      for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.GetTimeVisible and frame.SetTimeVisible then
          restore[frame] = frame:GetTimeVisible()
          frame:SetTimeVisible(0)
        end
      end
      -- Fading is not enough while other people keep talking, so the chat
      -- goes see-through as well, and the two buttons docked beside it.
      local faded = {}
      for i = 1, NUM_CHAT_WINDOWS or 10 do
        for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
          faded[#faded + 1] = _G["ChatFrame" .. i .. suffix]
        end
      end
      faded[#faded + 1] = ChatFrameMenuButton
      faded[#faded + 1] = ChatFrameChannelButton
      local alphas = {}
      for _, frame in ipairs(faded) do
        if frame and frame.GetAlpha and frame.SetAlpha then
          alphas[frame] = frame:GetAlpha()
          frame:SetAlpha(0)
        end
      end
      C_Timer.After(delay, function()
        Screenshot()
        -- The capture happens when the frame is drawn, not on the call,
        -- so the chat waits a moment before it comes back or it is in
        -- the picture after all.
        C_Timer.After(0.5, function()
          for frame, seconds in pairs(restore) do
            frame:SetTimeVisible(seconds)
          end
          for frame, alpha in pairs(alphas) do
            frame:SetAlpha(alpha)
          end
        end)
      end)
    elseif Screenshot then
      Screenshot()
      ns.Print("screenshot taken.")
    else
      ns.Print("this client has no Screenshot() to call.")
    end
  elseif command == "unlock" or command == "lock" or command == "keys" then
    local module = ns.GetModule("ActionBars")
    if module then
      local wanted = (command == "unlock" and "drag")
        or (command == "keys" and "keys")
        or nil
      module.SetMode(wanted)
    end
  elseif command == "kicks" or command == "kick" or command == "interrupts" then
    local kicks = ns.GetModule("Kicks")
    if kicks and rest == "test" then
      kicks.Test()
    else
      ns.OpenOptions("Kicks")
    end
  elseif command == "cooldowns" or command == "cd" or command == "cdm" then
    local cd = ns.GetModule("Cooldowns")
    if cd and (rest == "choose" or rest == "pick") then
      cd.OpenChooser()
    elseif cd and (rest == "move" or rest == "edit") then
      cd.OpenEditMode()
    else
      ns.OpenOptions("Cooldowns")
    end
  elseif command == "qf" or command == "questforever"
    or ((command == "quests" or command == "quest") and (rest == "helper" or rest:match("^helper "))) then
    -- The quest helper: /fui qf (flip), /fui qf on|off|options|export.
    local qf = ns.GetModule("QuestForever")
    local word = (command == "qf" or command == "questforever") and rest or rest:gsub("^helper%s*", "")
    if qf and (word == "options" or word == "settings") then
      ns.OpenOptions("QuestForever")
    elseif qf and word == "export" then
      qf.Export()
    elseif qf and word == "on" then
      qf.Toggle(true)
    elseif qf and word == "off" then
      qf.Toggle(false)
    elseif qf then
      qf.Toggle()
    end
  elseif command == "quests" or command == "quest" then
    local guideWord = rest:match("^guide%s*(%a*)$")
    if guideWord then
      -- The switch for how you're playing now: keyboard, or controller.
      local qs, qm = ns.db.modules.Quests, ns.GetModule("Quests")
      local key = qm and qm.AutoGuideKey and qm.AutoGuideKey() or "guideOnAccept"
      local was = qm and qm.AutoGuideOn and qm.AutoGuideOn() or qs[key] ~= false
      if guideWord == "on" then qs[key] = true
      elseif guideWord == "off" then qs[key] = false
      else qs[key] = not was end
      ns.Print(("the quest guide %s when you pick up a quest%s."):format(
        qs[key] and "opens" or "no longer opens", key == "guideOnAcceptPad" and " with the controller" or ""))
      return
    end
    local module = ns.GetModule("Quests")
    if module and rest == "dump" then
      module.Dump()
    elseif module and rest == "log" then
      module.OpenLog()
    elseif module and rest == "probe" and module.Probe then
      module.Probe()
    elseif module and (rest == "prune" or rest == "drop") then
      module.SuggestPrune()
    elseif module and (rest == "options" or rest == "settings") then
      ns.OpenOptions("Quests")
    elseif module then
      local settings = ns.db.modules.Quests
      settings.hide = not settings.hide
      module:Refresh()
      ns.Print(("quest tracker %s%s."):format(
        settings.hide and "hidden" or "shown",
        module.trackerName and "" or " - this client has no tracker frame we know of"))
      ns.RefreshOptions()
    end
  elseif command == "off" then
    local turned = 0
    -- Only what was on, so turning them back on doesn't switch on something
    -- that was deliberately off.
    ns.Wipe(ns.turnedOff)
    ns.ForEachModule(function(_, name)
      if ns.IsModuleEnabled(name) then
        ns.db.modules[name].enabled = false
        ns.turnedOff[name] = true
        turned = turned + 1
      end
    end)
    ns.Print(("%d modules off. Reload, and Blizzard's interface comes back."):format(turned))
    ns.Print("If it still doesn't click with everything off, the problem isn't ForeverUI.")
    ns.RequestReload("turning everything off")
  elseif command == "on" then
    local turned = 0
    for name in pairs(ns.turnedOff) do
      if ns.db.modules[name] then
        ns.db.modules[name].enabled = nil
        turned = turned + 1
      end
    end
    ns.Wipe(ns.turnedOff)
    ns.Print(("%d modules back on."):format(turned))
    ns.RequestReload("turning everything back on")
  elseif command == "probe" and (rest == "dungeons" or rest == "dungeon" or rest == "") then
    ns.ProbeDungeons()   -- Core/DungeonProbe.lua
  elseif command == "coords" then
    local module = ns.GetModule("Minimap")
    if module and module.FindCoordinateText then
      module.FindCoordinateText()
    end
  elseif command == "grab" then
    if rest == "reset" or rest == "all" then
      ns.ReleaseGrabs()
    else
      ns.GrabUnderCursor()
    end
  elseif command == "hide" then
    local module = ns.GetModule("Minimap")
    if module then
      if rest == "reset" or rest == "all" then
        module.ShowHiddenButtons()
      else
        module.HideUnderCursor()
      end
    end
  elseif command == "click" then
    local module = ns.GetModule("ActionBars")
    if module then
      module.Diagnose()
    end
  elseif command == "scan" then
    ns.ScanUI(rest)
  elseif command == "bars" then
    local module = ns.GetModule("ActionBars")
    local hidden = module and module.hidden
    if not hidden then
      ns.Print("Blizzard's bars haven't been hidden this session.")
    else
      ns.Print(("hid %d of Blizzard's frames."):format(#hidden))
      ns.Print(("bars are %s%s."):format(
        module.GetMode() and ("in " .. module.GetMode() .. " mode")
          or "locked (clicks cast; pick a spell up and they accept it)",
        module.IsCarrying() and ", cursor is carrying something" or ""))
      if ns.MoversShown() then
        ns.Print("|cffff6666move mode is on|r - the drag handles are swallowing your clicks. /fui move to finish.")
      end
      if #module.missing > 0 then
        ns.Print("this client doesn't have: " .. table.concat(module.missing, ", "))
      end
    end
  elseif command == "version" then
    ns.Print(("version %s on %s."):format(ns.VERSION, ns.Compat.Describe()))
    ns.Print(ns.Secrets.Describe())
  else
    Help()
  end
end

---------------------------------------------------------------------------
-- What's still on screen
---------------------------------------------------------------------------
--
-- Frames are named differently on different clients, so a hide list written
-- against one build quietly misses on another. Rather than guessing, this
-- reports what is actually visible right now. /fui scan xp narrows it.

local function Scan(filter)
  filter = (filter or ""):lower()
  local named, anonymous = {}, 0
  for _, child in ipairs({ UIParent:GetChildren() }) do
    if child.IsShown and child:IsShown() then
      local name = child.GetName and child:GetName()
      if not name then
        anonymous = anonymous + 1
      elseif not name:find("^ForeverUI") then
        if filter == "" or name:lower():find(filter, 1, true) then
          named[#named + 1] = name
        end
      end
    end
  end
  table.sort(named)
  ns.Print(("%d visible frames%s (%d unnamed)."):format(
    #named, filter ~= "" and (" matching '" .. filter .. "'") or "", anonymous))
  if #named > 0 then
    print(table.concat(named, ", "))
  end
  return named, anonymous
end
ns.ScanUI = Scan

SLASH_FOREVERUI1 = "/fui"
SLASH_FOREVERUI2 = "/foreverui"
SlashCmdList.FOREVERUI = Handle

ns.HandleCommand = Handle

---------------------------------------------------------------------------
-- Test mode
---------------------------------------------------------------------------

-- Modules that can show mock content register a toggle; the core just relays,
-- so /fui test works whatever is installed.
local testMode = false

function ns.TestModeShown()
  return testMode
end

function ns.ToggleTestMode(show)
  if show == nil then
    show = not testMode
  end
  testMode = show and true or false
  local any = false
  ns.ForEachModule(function(module, name)
    if module.SetTestMode and ns.ModuleRunning(name) then
      any = true
      module:SetTestMode(testMode)
    end
  end)
  if not any then
    ns.Print("nothing to show yet - test mode needs a module that draws frames.")
  end
end
