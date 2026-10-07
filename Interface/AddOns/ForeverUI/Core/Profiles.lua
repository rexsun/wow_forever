local _, ns = ...

-- Settings live in named profiles; characters point at one.
--
--   ForeverUIDB.profiles["Default"] = { ...everything... }
--   ForeverUIDB.characters["Solindius - Classic Beta PvE 2"] = "Default"
--
-- ns.db is the active profile. Profiles are created, switched and copied here
-- only; a few other files keep their own non-profile keys on ForeverUIDB
-- (the error log, the load trace, the capture).

local DEFAULT_PROFILE = "Default"

-- At ADDON_LOADED the game hasn't said who is logging in yet, so this can
-- only be answered properly from PLAYER_LOGIN onwards. Anything saved against
-- the placeholder key would be lost the moment the real one turned up.
function ns.CharacterKey()
  local name = UnitName and UnitName("player")
  local realm = GetRealmName and GetRealmName()
  if not name or not realm then
    return nil
  end
  return name .. " - " .. realm
end

function ns.ActiveProfileName()
  local key = ns.CharacterKey()
  return (key and ForeverUIDB.characters[key]) or ForeverUIDB.lastProfile or DEFAULT_PROFILE
end

-- Module defaults are merged in as each module registers, so a profile made
-- before a module existed still gets that module's settings.
local function Complete(profile)
  -- The owner's standard first, so it wins over the code defaults for
  -- anything not already set; then the code defaults for whatever the
  -- standard doesn't mention.
  if ns.STANDARD then
    ns.FillDefaults(profile, ns.STANDARD)
  end
  ns.FillDefaults(profile, ns.DEFAULTS)
  -- One-time: a profile still carrying the very first default font ("Friz
  -- Quadrata") never chose it -- it was the old default -- so move it to the
  -- new narrow default. The flag means anyone who later picks Friz on
  -- purpose keeps it.
  if profile.media and profile.media.font == "Friz Quadrata" and not profile.fontNarrowDone then
    profile.media.font = "Arial Narrow"
  end
  profile.fontNarrowDone = true
  ns.EnsureProfileMeta(profile)
  profile.modules = profile.modules or {}
  ns.ForEachModule(function(module, name)
    if module.defaults then
      -- The standard's module settings were already laid in above, with the
      -- rest of it; only the code defaults are left to fill.
      profile.modules[name] = profile.modules[name] or {}
      ns.FillDefaults(profile.modules[name], module.defaults)
    end
  end)
  return profile
end
ns.CompleteProfile = Complete

function ns.ProfileNames()
  local names = {}
  for name in pairs(ForeverUIDB.profiles) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function ns.UseProfile(name, quiet)
  if not ForeverUIDB.profiles[name] then
    ForeverUIDB.profiles[name] = Complete({})
  end
  local key = ns.CharacterKey()
  if key then
    ForeverUIDB.characters[key] = name
  end
  ForeverUIDB.lastProfile = name
  ns.db = Complete(ForeverUIDB.profiles[name])
  if ns.ApplyAccentColor then ns.ApplyAccentColor() end   -- this profile's border colour
  ns.RefreshAllModules()
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
  if not quiet then
    ns.Print(("now using profile \"%s\"."):format(name))
  end
end

-- New profiles start from the current one: tweaking beats starting over.
function ns.CopyProfile(newName, sourceName)
  if not newName or newName == "" or ForeverUIDB.profiles[newName] then
    return false
  end
  local from = sourceName or ns.ActiveProfileName()
  local source = ForeverUIDB.profiles[from]
  local copy = source and ns.CopyTable(source) or Complete({})
  ForeverUIDB.profiles[newName] = copy
  -- A copy is a new profile: its own dates, you as author, and a note of
  -- what it started from. Not a favourite until you say so.
  local now = ns.Now()
  copy.meta = {
    created = now, modified = now, version = ns.VERSION, author = ns.MetaAuthor(),
    basedOn = source and from or "Standard", description = (source and source.meta and source.meta.description) or "",
    source = "mine",
  }
  return true
end

function ns.DeleteProfile(name)
  if name == DEFAULT_PROFILE or not ForeverUIDB.profiles[name] then
    return false
  end
  ForeverUIDB.profiles[name] = nil
  for character, used in pairs(ForeverUIDB.characters) do
    if used == name then
      ForeverUIDB.characters[character] = DEFAULT_PROFILE
    end
  end
  ns.UseProfile(ns.ActiveProfileName(), true)
  return true
end

function ns.ResetProfile()
  local name = ns.ActiveProfileName()
  ForeverUIDB.profiles[name] = Complete({})
  ns.db = ForeverUIDB.profiles[name]
  ns.RefreshAllModules()
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
end

---------------------------------------------------------------------------
-- Export / import
---------------------------------------------------------------------------

-- A readable Lua-ish blob rather than a compressed string: no dependency, and
-- a human can see what they're pasting in. Import is deliberately strict.
local function Serialize(value, indent)
  indent = indent or ""
  local kind = type(value)
  if kind == "number" or kind == "boolean" then
    return tostring(value)
  elseif kind == "string" then
    return ("%q"):format(value)
  elseif kind ~= "table" then
    return "nil"
  end
  local parts, inner = {}, indent .. "  "
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    local name = type(key) == "string" and ("[%q]"):format(key) or ("[%s]"):format(tostring(key))
    parts[#parts + 1] = ("%s%s = %s"):format(inner, name, Serialize(value[key], inner))
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

-- Modules that export a slice of their own settings borrow this rather than
-- writing a second serializer.
ns.Serialize = Serialize

-- The same format on one line, no indentation: for the setup backup, where
-- the text is pasted into a box in the game and kept by the player.
local function Compact(value)
  local kind = type(value)
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return "0" end
    return tostring(value)
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "string" then
    return (("%q"):format(value):gsub("\\\n", "\\n"))
  elseif kind ~= "table" then
    return "nil"
  end
  local keys = {}
  for key, v in pairs(value) do
    local vk = type(v)
    if (type(key) == "string" or type(key) == "number" or type(key) == "boolean")
      and (vk == "table" or vk == "string" or vk == "number" or vk == "boolean") then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    local name = type(key) == "string" and ("[%s]"):format(Compact(key)) or ("[%s]"):format(tostring(key))
    parts[#parts + 1] = name .. "=" .. Compact(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
ns.CompactSerialize = Compact

-- Reading it back WITHOUT running it. Import used to hand the text to
-- loadstring; this reads the same format (either layout) as data only:
-- tables of [key] = value, strings, numbers, true / false. Anything else
-- is refused, so pasted text can never be code.
function ns.Deserialize(text)
  if type(text) ~= "string" then return nil, "nothing to read" end
  local s, pos, depth = text, 1, 0
  local ESCAPES = { n = "\n", r = "\r", t = "\t", a = "\a", b = "\b", f = "\f", v = "\v",
    ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }
  local function Skip()
    pos = s:find("[^%s]", pos) or (#s + 1)
  end
  local function String()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("a string never ends") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        local digits = s:match("^%d%d?%d?", pos + 1)
        if digits then
          out[#out + 1] = string.char(tonumber(digits) % 256)
          pos = pos + 1 + #digits
        elseif ESCAPES[n] then
          out[#out + 1] = ESCAPES[n]
          pos = pos + 2
        else
          error("a string has an unknown escape")
        end
      else
        local stop = s:find('[\\"]', pos) or (#s + 1)
        out[#out + 1] = s:sub(pos, stop - 1)
        pos = stop
      end
    end
    return table.concat(out)
  end
  local Value
  function Value()
    Skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      depth = depth + 1
      if depth > 60 then error("nested too deep") end
      pos = pos + 1
      local t = {}
      while true do
        Skip()
        c = s:sub(pos, pos)
        if c == "}" then pos = pos + 1; depth = depth - 1; return t end
        if c ~= "[" then error("expected [ at " .. pos) end
        pos = pos + 1
        local key = Value()
        Skip()
        if s:sub(pos, pos) ~= "]" then error("expected ] at " .. pos) end
        pos = pos + 1
        Skip()
        if s:sub(pos, pos) ~= "=" then error("expected = at " .. pos) end
        pos = pos + 1
        local v = Value()
        if key ~= nil and type(key) ~= "table" then t[key] = v end
        Skip()
        c = s:sub(pos, pos)
        if c == "," then
          pos = pos + 1
        elseif c ~= "}" then
          error("expected , or } at " .. pos)
        end
      end
    elseif c == '"' then
      return String()
    elseif s:find("^true", pos) then
      pos = pos + 4; return true
    elseif s:find("^false", pos) then
      pos = pos + 5; return false
    elseif s:find("^nil", pos) then
      pos = pos + 3; return nil
    elseif s:find("^%-?inf", pos) or s:find("^%-?nan", pos) or s:find("^%-?%(%-?nan%)", pos) then
      pos = s:find("[,}%]]", pos) or (#s + 1)
      return 0
    end
    local number = s:match("^%-?[%d%.]+[eE]?[%-+]?%d*", pos)
    local n = number and tonumber(number)
    if not n then error("unexpected text at " .. pos) end
    pos = pos + #number
    return n
  end
  local ok, result = pcall(function()
    local v = Value()
    Skip()
    if pos <= #s then error("unexpected text after the end") end
    return v
  end)
  if not ok then return nil, tostring(result) end
  return result
end
local function ReadTable(body)
  local parsed, err = ns.Deserialize(body)
  if type(parsed) ~= "table" then
    return nil, "the profile text is damaged" .. (err and (": " .. err) or "")
  end
  return parsed
end

-- What a profile holds that isn't a setting: diagnostics written while you
-- play (the cast trace, the dungeon probe, the frames' error log and binding
-- log, the options-window close stacks). Shared profiles and backups leave
-- them out -- they were kilobytes of other addons' errors handed to whoever
-- imported the text.
local DIAGNOSTICS = { castTrace = true, dungeonProbe = true }
local FRAMES_DIAGNOSTICS = { errors = true, bindingLog = true, panelHides = true }
local function WithoutDiagnostics(profile)
  local out = {}
  for k, v in pairs(profile) do
    if not DIAGNOSTICS[k] then out[k] = v end
  end
  if type(profile.frames) == "table" then
    local frames = {}
    for k, v in pairs(profile.frames) do
      if not FRAMES_DIAGNOSTICS[k] then frames[k] = v end
    end
    out.frames = frames
  end
  return out
end
ns.WithoutDiagnostics = WithoutDiagnostics

function ns.ExportProfile(name)
  local profile = ForeverUIDB.profiles[name or ns.ActiveProfileName()]
  if not profile then
    return nil
  end
  ns.EnsureProfileMeta(profile).name = name or ns.ActiveProfileName()
  return ("ForeverUI:%s:%s"):format(ns.VERSION, Serialize(WithoutDiagnostics(profile)))
end

function ns.ImportProfile(text, newName)
  if type(text) ~= "string" then
    return false, "nothing to import"
  end
  local body = text:match("^ForeverUI:[^:]*:(.+)$")
  if not body then
    return false, "that doesn't look like a ForeverUI profile"
  end
  -- Read as data, never run: see ns.Deserialize.
  local parsed, err = ReadTable(body)
  if not parsed then
    return false, err
  end
  local target = newName and newName ~= "" and newName or ns.ActiveProfileName()
  ForeverUIDB.profiles[target] = Complete(parsed)
  ns.UseProfile(target, true)
  return true
end

---------------------------------------------------------------------------
-- The whole setup as text to keep (owner, 28 Sept 2026: the Forever beta
-- never loads saved settings back, so a player's own copy is the one thing
-- that always survives)
---------------------------------------------------------------------------
--
-- Only what differs from a fresh profile, on one line, so it stays a few
-- KB rather than the ~70 KB of a full export: import fills the rest back in
-- from the defaults, exactly as it does for any profile. Restoring lays it
-- over the profile you're on and applies it at once, with no reload -- on
-- this client a reload is what forgets things -- then refreshes the macro
-- backup so the essentials ride along from then on.

local function Diff(value, ref)
  if type(value) ~= "table" then
    if value ~= ref then return value, true end
    return nil, false
  end
  if type(ref) ~= "table" then
    return value, true
  end
  local out, any = {}, false
  for key, v in pairs(value) do
    local d, changed = Diff(v, ref[key])
    if changed then
      out[key] = d
      any = true
    end
  end
  return out, any
end
ns.DiffFromDefaults = Diff

function ns.ExportSetup()
  local ref = Complete({})
  if ns.Frames and ns.Frames.FillDefaults then
    local ok, frames = pcall(ns.Frames.FillDefaults, {})
    if ok and type(frames) == "table" then ref.frames = frames end
  end
  local diff = Diff(WithoutDiagnostics(ns.db or {}), ref)
  if type(diff) ~= "table" then diff = {} end
  diff.meta = nil   -- dates and author: noise in a backup
  return ("ForeverUI:%s:%s"):format(ns.VERSION or "?", Compact(diff))
end

function ns.RestoreSetup(text)
  local ok, err = ns.ImportProfile(text)
  if not ok then
    return false, err
  end
  if ns.Frames and ns.Frames.InitProfiles then pcall(ns.Frames.InitProfiles) end
  if ns.ApplyMoverPositions then pcall(ns.ApplyMoverPositions) end
  if ns.Skin and ns.Skin.ApplyCorners then pcall(ns.Skin.ApplyCorners) end
  if ns.MacroBackup then pcall(ns.MacroBackup.Write, true) end
  return true
end

function ns.ShowSetupBackup()
  ns.ShowTextPopup("Your whole setup -- copy it (Cmd/Ctrl+C) and keep it somewhere safe", ns.ExportSetup())
end

function ns.ShowSetupRestore()
  ns.ShowTextPopup("Paste a setup you copied with /fui backup, then Import", "", function(text)
    local ok, err = ns.RestoreSetup(text)
    if ok then
      ns.Print("setup restored. Bars, frames and settings are back as they were when you copied it.")
    else
      ns.Print("couldn't restore that: " .. tostring(err))
    end
  end)
end

---------------------------------------------------------------------------
-- What the Profiles page shows about a profile
---------------------------------------------------------------------------
--
-- Each profile carries a small `meta` record: dates, who made it, what it
-- started from, a line of description, whether it is a favourite, and
-- whether it was made here or pasted in from somebody else. It lives inside
-- the profile, so an export takes it along.

function ns.Now()
  return (time and time()) or (os and os.time and os.time()) or 0
end

function ns.MetaAuthor()
  local key = ns.CharacterKey and ns.CharacterKey()
  return key and key:match("^([^%-]+)"):gsub("%s+$", "") or "You"
end

function ns.EnsureProfileMeta(profile)
  if type(profile) ~= "table" then
    return nil
  end
  local meta = profile.meta
  if type(meta) ~= "table" then
    meta = {}
    profile.meta = meta
  end
  local now = ns.Now()
  meta.created = meta.created or now
  meta.modified = meta.modified or meta.created
  meta.version = meta.version or ns.VERSION
  meta.author = meta.author or ns.MetaAuthor()
  meta.description = meta.description or ""
  meta.source = meta.source or "mine"
  return meta
end

function ns.ProfileMeta(name)
  return ns.EnsureProfileMeta(ForeverUIDB.profiles[name])
end

-- Something in the active profile just changed.
function ns.TouchProfile()
  local meta = ns.db and ns.EnsureProfileMeta(ns.db)
  if meta then
    meta.modified = ns.Now()
    meta.version = ns.VERSION
  end
end

-- Which role a profile is for, from the grids it puts on screen: one grid
-- is that role; none or several is "all".
function ns.ProfileRole(name)
  local profile = ForeverUIDB.profiles[name]
  local frames = profile and profile.frames
  if type(frames) ~= "table" then
    return "all"
  end
  local up, count, only = frames.gridsUp, 0, nil
  if type(up) == "table" then
    for _, role in ipairs({ "healer", "tank", "dps" }) do
      if up[role] then
        count, only = count + 1, role
      end
    end
    return count == 1 and only or "all"
  end
  return frames.mode or "healer"
end

function ns.SetProfileFavorite(name, on)
  local meta = ns.ProfileMeta(name)
  if meta then
    meta.favorite = on and true or nil
  end
  return meta ~= nil
end

-- A name nobody has used yet: "base", "base 2", "base 3" ...
function ns.FreeProfileName(base)
  base = (base and base ~= "") and base or "Profile"
  if not ForeverUIDB.profiles[base] then
    return base
  end
  local n = 2
  while ForeverUIDB.profiles[base .. " " .. n] do
    n = n + 1
  end
  return base .. " " .. n
end

function ns.RenameProfile(old, new)
  if not old or not new or new == "" or old == new then
    return false, "give it a different name"
  end
  if old == DEFAULT_PROFILE then
    return false, "the Default profile keeps its name"
  end
  if ForeverUIDB.profiles[new] then
    return false, ("there is already a profile called \"%s\""):format(new)
  end
  local profile = ForeverUIDB.profiles[old]
  if not profile then
    return false, "no such profile"
  end
  ForeverUIDB.profiles[new], ForeverUIDB.profiles[old] = profile, nil
  for character, used in pairs(ForeverUIDB.characters) do
    if used == old then
      ForeverUIDB.characters[character] = new
    end
  end
  if ForeverUIDB.lastProfile == old then
    ForeverUIDB.lastProfile = new
  end
  for _, other in pairs(ForeverUIDB.profiles) do
    if type(other.meta) == "table" and other.meta.basedOn == old then
      other.meta.basedOn = new
    end
  end
  return true
end

function ns.DuplicateProfile(name)
  local newName = ns.FreeProfileName((name or "Profile") .. " copy")
  if ns.CopyProfile(newName, name) then
    return newName
  end
  return nil
end

-- A fresh profile from the standard layout, not a copy of anything.
function ns.NewProfile(base)
  local name = ns.FreeProfileName(base or "New Profile")
  local profile = Complete({})
  profile.meta.basedOn = "Standard"
  ForeverUIDB.profiles[name] = profile
  return name
end

-- Ready-made starting points: the standard layout with one grid, or all.
ns.PROFILE_PRESETS = {
  { key = "standard", name = "Standard", role = "all",
    description = "The standard layout: the whole interface, all three grids." },
  { key = "healer", name = "Healer", role = "healer",
    description = "The standard layout with just the healing grid." },
  { key = "tank", name = "Tank", role = "tank",
    description = "The standard layout with just the tanking grid." },
  { key = "dps", name = "Damage", role = "dps",
    description = "The standard layout with just the DPS grid." },
}

function ns.ProfilePreset(key)
  for _, preset in ipairs(ns.PROFILE_PRESETS) do
    if preset.key == key then
      return preset
    end
  end
  return nil
end

-- Make a real profile from a preset. It is added to your list; using it is
-- a separate step, the same as for any other profile.
function ns.CreateFromPreset(key)
  local preset = ns.ProfilePreset(key)
  if not preset then
    return nil
  end
  local name = ns.NewProfile(preset.name)
  local profile = ForeverUIDB.profiles[name]
  profile.meta.basedOn = "Standard"
  profile.meta.description = preset.description
  if preset.role ~= "all" then
    profile.frames = profile.frames or {}
    profile.frames.gridsUp = { healer = false, tank = false, dps = false }
    profile.frames.gridsUp[preset.role] = true
    profile.frames.mode = preset.role
  end
  return name
end

-- Every profile at once, for a backup or a move between accounts.
function ns.ExportAllProfiles()
  return ("ForeverUI-all:%s:%s"):format(ns.VERSION, Serialize(ForeverUIDB.profiles))
end

local function ParseBlob(text)
  if type(text) ~= "string" then
    return nil, "nothing to import"
  end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local kind, body = text:match("^(ForeverUI%-all):[^:]*:(.+)$")
  if not kind then
    kind, body = text:match("^(ForeverUI):[^:]*:(.+)$")
  end
  if not body then
    return nil, "that doesn't look like a ForeverUI profile"
  end
  local parsed, err = ReadTable(body)
  if not parsed then
    return nil, err
  end
  return parsed, kind
end

-- Paste in one profile or a whole backup. Each arrives as a NEW profile --
-- nothing you have is overwritten -- marked as imported, and none is
-- switched to. Returns the new names.
function ns.ImportProfilesAsNew(text)
  local parsed, kind = ParseBlob(text)
  if not parsed then
    return nil, kind
  end
  local incoming = {}
  if kind == "ForeverUI-all" then
    for name, profile in pairs(parsed) do
      if type(profile) == "table" then
        incoming[#incoming + 1] = { name = tostring(name), profile = profile }
      end
    end
    table.sort(incoming, function(a, b) return a.name < b.name end)
  else
    local meta = type(parsed.meta) == "table" and parsed.meta or {}
    incoming[1] = { name = meta.name or "Imported", profile = parsed }
  end
  local names = {}
  for _, item in ipairs(incoming) do
    local name = ns.FreeProfileName(item.name)
    local profile = Complete(item.profile)
    profile.meta.source = "imported"
    profile.meta.favorite = nil
    ForeverUIDB.profiles[name] = profile
    names[#names + 1] = name
  end
  return names
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

function ns.InitProfiles()
  ForeverUIDB = ForeverUIDB or {}
  ForeverUIDB.profiles = ForeverUIDB.profiles or {}
  ForeverUIDB.characters = ForeverUIDB.characters or {}
  ForeverUIDB.version = ns.VERSION

  local name = ns.ActiveProfileName()
  ForeverUIDB.profiles[name] = ForeverUIDB.profiles[name] or {}
  ns.db = Complete(ForeverUIDB.profiles[name])
  local key = ns.CharacterKey()
  if key then
    ForeverUIDB.characters[key] = name
  end
end

-- Called once the game knows who logged in. If this character last used a
-- different profile, switch to it now rather than running on whichever one
-- was guessed before the name was available.
function ns.ResolveProfile()
  local key = ns.CharacterKey()
  if not key then
    return nil
  end
  local wanted = ForeverUIDB.characters[key]
  if wanted and ForeverUIDB.profiles[wanted] and ForeverUIDB.profiles[wanted] ~= ns.db then
    ns.UseProfile(wanted, true)
  else
    ForeverUIDB.characters[key] = ns.ActiveProfileName()
  end
  return ForeverUIDB.characters[key]
end

---------------------------------------------------------------------------
-- Options page
---------------------------------------------------------------------------

function ns.ProfilesSchema()
  local function cycleTo(offset)
    local names = ns.ProfileNames()
    local current = ns.ActiveProfileName()
    local index = 1
    for i, name in ipairs(names) do
      if name == current then
        index = i
      end
    end
    ns.UseProfile(names[(index - 1 + offset) % #names + 1])
  end

  return {
    { type = "heading", label = "Profiles" },
    { type = "action", width = 300,
      label = "Profile",
      labelFor = function() return ("Using: %s  (click for the next)"):format(ns.ActiveProfileName()) end,
      onClick = function() cycleTo(1) end },
    { type = "action", width = 300, label = "New profile, copied from this one",
      onClick = function()
        local base, n = "Profile", 2
        while ForeverUIDB.profiles[base .. " " .. n] do
          n = n + 1
        end
        local name = base .. " " .. n
        if ns.CopyProfile(name) then
          ns.UseProfile(name)
        end
      end },
    { type = "action", width = 300, label = "Reset this profile to defaults",
      onClick = function() ns.ResetProfile() end },
    { type = "action", width = 300, label = "Delete this profile",
      onClick = function()
        local name = ns.ActiveProfileName()
        if not ns.DeleteProfile(name) then
          ns.Print("the Default profile can't be deleted.")
        end
      end },

    { type = "heading", label = "Share" },
    { type = "action", width = 300, label = "Export this profile",
      onClick = function()
        ns.ShowTextPopup("Export profile", ns.ExportProfile())
      end },
    { type = "action", width = 300, label = "Import a profile",
      onClick = function()
        ns.ShowTextPopup("Paste a profile, then Import", "", function(text)
          local ok, err = ns.ImportProfile(text)
          ns.Print(ok and "profile imported." or err)
        end)
      end },
    { type = "note", label = "Each character remembers the profile it used last." },
  }
end
