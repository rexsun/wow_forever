local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- Where the folded-in party/raid frame engine meets ForeverUI proper.
--
-- The engine (Frames.lua and its files) is a whole addon in its own right,
-- kept in its own private namespace (FUI.Frames) so its core helpers -- db,
-- Print, WhenOutOfCombat and the rest -- never collide with ForeverUI's.
--
-- It boots HERE, as a ForeverUI module, not on its own ADDON_LOADED: ForeverUI
-- calls OnInit once it has resolved which profile this character is on, and
-- the frames then read and write `FUI.db.frames` -- a sub-table of that same
-- profile. One profile per character for the whole addon; the healer and tank
-- settings both live inside it (Modes.lua), and DPS will too. Every profile
-- switch ForeverUI makes comes through Refresh, so the frames follow it.

local module = FUI.RegisterModule({
  name = "Frames",
  title = "Party & Raid Frames",
  needsReload = true, -- secure headers can't be unmade; turning it off asks for /reload
})
ns.module = module

function module:OnInit()
  -- Frames.xml reaches the engine through one global name, and a standalone
  -- HealForever or TankForever installed alongside sets the same one when it
  -- loads -- whichever of us loaded last would own it. Claim it back here, at
  -- login: when ForeverUI is installed it owns the frames, and the standalone
  -- copy stands aside at this same point without building anything.
  ForeverUIFrames = ns -- luacheck: ignore 111 131
  ns.LocalizeSpellNames()   -- spell lists in the game's own language (SpellData.lua)
  ns.InitProfiles()
  ns.LocalizeSavedSpellNames()
  if FUI.LookAtLoad then FUI.LookAtLoad("Frames.OnInit") end
  ns.booted = true -- the event driver (Frames.lua) ignores everything before this
  ns.SeedRoleLooks() -- every role gets its own copy of the shared look, once
  if ns.adopted then
    ns.Print(("your frame settings moved into your ForeverUI profile (from the old \"%s\" store). One save for everything now."):format(ns.adopted))
    ns.adopted = nil
  end
  ns.FlushErrors() -- anything that broke before the settings existed
  ns.RebuildWatchIndex()
end

function module:OnEnable()
  if ns.anchor then
    ns.anchor:Show()
    ns.ApplyAllSettings()
  else
    ns.SetupLayout()
  end
  -- If the game already has you in a role different from the frames', offer
  -- the switch (out of combat).
  if ns.CheckRoleFlip then
    ns.WhenOutOfCombat(ns.CheckRoleFlip)
  end
end

function module:OnDisable()
  if ns.anchor then ns.anchor:Hide() end
  if ns.targetFrame then ns.targetFrame:Hide() end
  if ns.minimapButton then ns.minimapButton:Hide() end
end

-- ForeverUI switched (or re-applied) a profile: repoint at its frames table
-- and redraw. A different profile can be in a different role, so the swap
-- goes through SetMode, which rebuilds the role-specific parts.
function module:Refresh()
  local before = ns.GetMode()
  local moved = ns.InitProfiles()
  ns.SeedRoleLooks()
  if not ns.anchor then
    return -- not built yet; OnEnable does the first build
  end
  if moved and ns.SetMode and ns.GetMode() ~= before then
    ns.SetMode(ns.GetMode(), { force = true }) -- the role-specific frames and window
  end
  ns.ApplyAllSettings()
end

module.options = {
  { type = "note", label = "Party and raid frames with click-casting, folded in from HealForever and TankForever. They pick a role -- Healer, Tank or DPS -- and change what a click does. The full settings open in their own window." },
  { type = "action", label = "Open frame settings", width = 220,
    onClick = function()
      if ns.ToggleOptions then
        ns.ToggleOptions()
      end
    end },
  { type = "note", label = "Type /fui frames for the frame commands, or /fui role to change role." },
}

-- ForeverUI's /fui forwards its `frames` subcommand here (Commands.lua).
function FUI.ForwardFrames(rest)
  if ns.HandleSlash then
    ns.HandleSlash(rest or "")
  end
end

-- Called by ForeverUI's first-login installer (Core/Install.lua) with the
-- role the player picked on the "How do you play?" page.
function FUI.ChooseFramesRole(preset)
  local map = {
    Healer = "healer", Tank = "tank", Damage = "dps",
    healer = "healer", tank = "tank", dps = "dps", damage = "dps",
  }
  local mode = map[preset or ""] or "healer"
  if ns.SetMode then
    ns.SetMode(mode)
  end
end

-- /fui role: switch which role the frames are set up for. A bare mode word
-- switches the frames; anything else (e.g. "role Bob tank") is a per-player
-- role mark, handled by the engine's own dispatcher.
function FUI.FramesRole(rest)
  local word = (rest or ""):match("^%s*(%S*)%s*$")
  word = word and word:lower() or ""
  local pick = ({ tank = "tank", healer = "healer", heal = "healer",
    dps = "dps", damage = "dps", damager = "dps" })[word]
  if pick then
    -- Playing that role now: its grid comes up, solo too, if it was off.
    if ns.SetMode then ns.SetMode(pick) end
    if ns.GridState and ns.GridState(pick) == "off" and ns.SetGridState then
      ns.SetGridState(pick, "always")
    end
    ns.Print(("frames set to %s."):format(ns.RoleLabel and ns.RoleLabel(pick) or pick))
  elseif word == "" then
    ns.Print(("frames are in %s mode. /fui role healer, tank or dps to switch."):format(
      ns.RoleLabel and ns.RoleLabel(ns.GetMode()) or ns.GetMode()))
  elseif ns.HandleSlash then
    ns.HandleSlash("role " .. rest)   -- a per-player role mark
  end
end
