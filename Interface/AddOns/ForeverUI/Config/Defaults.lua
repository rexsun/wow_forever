local _, ns = ...

-- Core defaults. Module settings live under modules[name] and come from each
-- module's own `defaults`, so this stays small.

ns.DEFAULTS = {
  installed = false,   -- first run shows the installer instead of the options
  minimapButton = true,
  minimapAngle = 198,  -- where it sits around the minimap's edge
  hideIssueReporter = true, -- the beta's floating Issue Reporter; off = tucked top-left instead
  scale = 1,           -- ForeverUI's own scale, applied to our frames
  roundCorners = false, -- windows and panels with rounded corners (General > Appearance)
  cornerRadius = 6,
  controllerMode = "auto", -- auto | on | off (Core/Controller.lua)
  roundButtons = true,    -- ...the action buttons too (when roundCorners is on)
  roundUnitFrames = true, -- ...and the unit frames

  media = {
    font = "Arial Narrow",
    texture = "Blizzard",
    roles = {},        -- per-role overrides: roles.unitName = { size = 12 }
  },

  movers = {},         -- name -> { point, relativePoint, x, y }
  grabbed = {},        -- Blizzard frames given a handle by /fui grab, by name
  released = {},       -- ones handed back, so the few we adopt stay handed back

  modules = {},        -- name -> { enabled = bool, ...module settings }
}
