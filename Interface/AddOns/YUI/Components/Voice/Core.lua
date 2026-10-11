local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI then return end

YUI.Sound = YUI.Sound or {}
local S = YUI.Sound
if S._serviceVersion and S._serviceVersion >= 3 then return end
S._serviceVersion = 3

local CombatAPI = YUI.API and YUI.API.Combat or YUI.WOW_API
local SoundAPI = YUI.API and YUI.API.Sound

local VALID_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local LEGACY_DEFAULT_PACK_ID = "yui.default"
local DEFAULT_CHANNEL = "Master"
local MAX_CUSTOM_PATH_LENGTH = 153
local SOURCE_ORDER = { voice = 1, system = 2, lsm = 3, custom = 4 }

S.packs = S.packs or {}
S.packOrder = S.packOrder or {}
S.registeredKeys = S.registeredKeys or {}
S.keyOwners = S.keyOwners or {}
S.systemSounds = S.systemSounds or {}
S.systemSoundOrder = S.systemSoundOrder or {}
S._lastPlay = S._lastPlay or {}

local function Emit(event, ...)
    if YUI.Event and YUI.Event.Emit then
        YUI.Event:Emit(event, ...)
    end
end

local function GetClientVersion()
    if YUI.IsRetail == true then return "mainline" end
    if YUI.IsWrath == true then return "wrath" end
    if YUI.IsMists == true then return "mists" end
    return "unknown"
end

local function CopySoundMap(source)
    local result = {}
    for key, file in pairs(type(source) == "table" and source or {}) do
        local fileType = type(file)
        if type(key) == "string" and key ~= ""
            and (fileType == "string" or fileType == "number") then
            result[key] = file
        end
    end
    return result
end

local function NormalizeChannel(channel)
    return VALID_CHANNELS[channel] and channel or DEFAULT_CHANNEL
end

local function GetStorageProductId()
    if S.storageProductId then return S.storageProductId end
    if YUI.CoreMode == "suite" then return "suite" end
    return YUI.ProductId or "suite"
end

local function GetSavedSettings(create)
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetGlobal) then
        return nil
    end
    local global = DB:GetGlobal(GetStorageProductId())
    if type(global) ~= "table" then return nil end
    if type(global.sound) ~= "table" then
        if not create then return nil end
        global.sound = {}
    end
    return global.sound
end

local function PackSupportsClient(definition)
    local client = GetClientVersion()
    if type(definition.clientVersion) == "string"
        and definition.clientVersion ~= client then
        return false
    end
    if type(definition.clients) == "table"
        and definition.clients[client] ~= true then
        return false
    end
    return true
end

local function GetSharedMedia()
    local stub = _G.LibStub
    local stubType = type(stub)
    local ok, media
    if stubType == "table" and type(stub.GetLibrary) == "function" then
        ok, media = pcall(stub.GetLibrary, stub, "LibSharedMedia-3.0", true)
    elseif stubType == "function" then
        ok, media = pcall(stub, "LibSharedMedia-3.0", true)
    else
        return nil
    end
    return ok and media or nil
end

local function SplitReference(reference)
    local separator = type(reference) == "string"
        and string.find(reference, ":", 1, true) or nil
    if not separator then return nil, reference end
    return string.sub(reference, 1, separator - 1),
        string.sub(reference, separator + 1)
end

local function NormalizeCustomPath(path)
    if type(path) ~= "string" then return nil end
    path = string.match(path, "^%s*(.-)%s*$") or ""
    if path == "" or #path > MAX_CUSTOM_PATH_LENGTH
        or string.match(path, "^[A-Za-z]:[\\/]")
        or string.sub(path, 1, 2) == "\\\\"
        or string.sub(path, 1, 1) == "/" then
        return nil
    end
    return path
end

local function CustomFileLabel(path)
    local fileName = string.match(path, "([^\\/]+)$") or path
    local withoutExtension = string.match(fileName, "^(.+)%.[^%.]+$")
    return withoutExtension or fileName
end

local function ResolveSystemKit(definition)
    if type(definition) ~= "table" then return nil end
    if type(definition.kit) == "number" then return definition.kit end
    if type(definition.kit) == "string" and type(SOUNDKIT) == "table" then
        local value = SOUNDKIT[definition.kit]
        return type(value) == "number" and value or nil
    end
    return nil
end

function S:NormalizeReference(reference)
    if type(reference) ~= "string" or reference == ""
        or reference == "None" then
        return nil
    end
    local source, key = SplitReference(reference)
    if source == "custom" then
        local path = NormalizeCustomPath(key)
        return path and "custom:" .. path or nil
    end
    if (source == "voice" or source == "system" or source == "lsm")
        and key ~= "" then
        return source .. ":" .. key
    end
    return "voice:" .. reference
end

function S:LoadSettings()
    local saved = GetSavedSettings(self._settingsDirty == true)
    if not saved then return false end
    if self._settingsDirty == true then
        saved.packId = self._activePackId
        saved.channel = NormalizeChannel(self._channel)
        self._settingsDirty = nil
    else
        if type(saved.packId) == "string" and saved.packId ~= "" then
            self._activePackId = saved.packId
        end
        self._channel = NormalizeChannel(saved.channel)
    end
    self._settingsLoaded = true
    return true
end

function S:SaveSettings()
    local saved = GetSavedSettings(true)
    if not saved then
        self._settingsDirty = true
        return false
    end
    saved.packId = self._activePackId
    saved.channel = NormalizeChannel(self._channel)
    self._settingsDirty = nil
    self._settingsLoaded = true
    return true
end

function S:RegisterKeys(owner, definitions)
    if type(owner) ~= "string" or owner == ""
        or type(definitions) ~= "table" then
        return false
    end
    local changed = false
    local function RegisterKey(key, value)
        if type(key) ~= "string" or key == "" then return end
        local label = type(value) == "table" and value.label or key
        if not self.registeredKeys[key] then
            self.registeredKeys[key] = {
                key = key,
                label = type(label) == "string" and label ~= ""
                    and label or key,
            }
            changed = true
        end
        local owners = self.keyOwners[key]
        if not owners then
            owners = {}
            self.keyOwners[key] = owners
        end
        owners[owner] = true
    end
    for index = 1, #definitions do
        RegisterKey(definitions[index], definitions[index])
    end
    for key, value in pairs(definitions) do
        if type(key) == "string" then RegisterKey(key, value) end
    end
    if changed then Emit("YUI_SOUND_KEYS_CHANGED") end
    return true
end

function S:RegisterPack(packId, definition)
    if type(packId) ~= "string" or packId == ""
        or type(definition) ~= "table" then
        return false, "invalid-pack"
    end
    if not PackSupportsClient(definition) then
        return false, "incompatible-client"
    end
    local sounds = CopySoundMap(definition.sounds)
    if not next(sounds) then return false, "empty-pack" end
    if self.packs[packId] then return false, "duplicate-pack" end

    local pack = {
        id = packId,
        name = type(definition.name) == "string"
            and definition.name ~= "" and definition.name or packId,
        author = type(definition.author) == "string"
            and definition.author or "",
        authorInfo = type(definition.authorInfo) == "string"
            and definition.authorInfo or "",
        version = type(definition.version) == "string"
            and definition.version or "",
        clientVersion = definition.clientVersion or GetClientVersion(),
        sounds = sounds,
    }
    self.packs[packId] = pack
    self.packOrder[#self.packOrder + 1] = packId
    if definition.isDefault == true and not self.defaultPackId then
        self.defaultPackId = packId
    end
    Emit("YUI_SOUND_PACKS_CHANGED", packId)
    return true
end

function S:RegisterSystemSounds(owner, definitions)
    if type(owner) ~= "string" or owner == ""
        or type(definitions) ~= "table" then
        return false
    end
    local changed = false
    for key, value in pairs(definitions) do
        if type(key) == "string" and key ~= "" and type(value) == "table"
            and (type(value.kit) == "string" or type(value.kit) == "number"
                or type(value.file) == "string" and value.file ~= "") then
            if not self.systemSounds[key] then
                self.systemSoundOrder[#self.systemSoundOrder + 1] = key
            end
            self.systemSounds[key] = {
                key = key,
                label = type(value.label) == "string" and value.label ~= ""
                    and value.label or key,
                kit = value.kit,
                file = type(value.file) == "string" and value.file ~= "" and value.file or nil,
                labelKey = value.labelKey,
                owner = owner,
            }
            changed = true
        end
    end
    if changed then Emit("YUI_SYSTEM_SOUNDS_CHANGED", owner) end
    return true
end

function S:GetPacks()
    local result = {}
    for index = 1, #self.packOrder do
        local pack = self.packs[self.packOrder[index]]
        if pack then result[#result + 1] = pack end
    end
    return result
end

function S:GetPack(packId)
    return self.packs[packId]
end

function S:GetActivePackId()
    if not self._settingsLoaded then self:LoadSettings() end
    local packId = self._activePackId
    local migrated = packId == LEGACY_DEFAULT_PACK_ID
    if migrated then packId = self.defaultPackId end
    if self.packs[packId] then
        self._activePackId = packId
        if migrated then self:SaveSettings() end
        return packId
    end
    if self.packs[self.defaultPackId] then
        self._activePackId = self.defaultPackId
        return self.defaultPackId
    end
    for index = 1, #self.packOrder do
        packId = self.packOrder[index]
        if self.packs[packId] then
            self._activePackId = packId
            return packId
        end
    end
    return nil
end

function S:GetActivePack()
    return self.packs[self:GetActivePackId()]
end

function S:SetActivePack(packId)
    if not self.packs[packId] then return false, "unknown-pack" end
    if self:GetActivePackId() == packId then return true end
    self._activePackId = packId
    self:SaveSettings()
    Emit("YUI_SOUND_PACK_CHANGED", packId)
    return true
end

function S:GetChannel()
    if not self._settingsLoaded then self:LoadSettings() end
    self._channel = NormalizeChannel(self._channel)
    return self._channel
end

function S:SetChannel(channel)
    if not VALID_CHANNELS[channel] then return false, "invalid-channel" end
    if self:GetChannel() == channel then return true end
    self._channel = channel
    self:SaveSettings()
    Emit("YUI_SOUND_CHANNEL_CHANGED", channel)
    return true
end

function S:Resolve(reference)
    local normalized = self:NormalizeReference(reference)
    if not normalized then return nil, nil, nil, "invalid-key" end
    local source, key = SplitReference(normalized)
    if source == "voice" then
        local active = self:GetActivePack()
        local file = active and active.sounds[key] or nil
        local packId = active and active.id or nil
        if file == nil and self.defaultPackId ~= packId then
            local fallback = self.packs[self.defaultPackId]
            file = fallback and fallback.sounds[key] or nil
            packId = file ~= nil and self.defaultPackId or packId
        end
        if file == nil then return nil, nil, normalized, "missing-sound" end
        if self.ResolveLegacyEntry then
            local resource = self:ResolveLegacyEntry(key, packId)
            if resource then return "file", resource.value, normalized, resource.packId end
        end
        return "file", file, normalized, packId
    elseif source == "system" then
        local definition = self.systemSounds[key]
        if definition and definition.file then
            return "file", definition.file, normalized, key
        end
        local kit = ResolveSystemKit(definition)
        if not kit then return nil, nil, normalized, "missing-sound" end
        return "kit", kit, normalized, key
    elseif source == "lsm" then
        local media = GetSharedMedia()
        if not (media and type(media.Fetch) == "function") then
            return nil, nil, normalized, "missing-sound"
        end
        local ok, file = pcall(media.Fetch, media, "sound", key, true)
        if not ok or (type(file) ~= "string" and type(file) ~= "number") then
            return nil, nil, normalized, "missing-sound"
        end
        return "file", file, normalized, key
    elseif source == "custom" then
        return "file", key, normalized, key
    end
    return nil, nil, normalized, "unknown-source"
end

function S:GetPackStats(packId)
    local pack = self.packs[packId or self:GetActivePackId()]
    if not pack then return 0, 0 end
    local total, valid = 0, 0
    local fallback = self.packs[self.defaultPackId]
    for key in pairs(self.registeredKeys) do
        total = total + 1
        if pack.sounds[key] ~= nil
            or fallback and fallback.sounds[key] ~= nil then
            valid = valid + 1
        end
    end
    if total == 0 then
        for _ in pairs(pack.sounds) do total = total + 1 end
        valid = total
    end
    return valid, total
end

function S:GetSoundOptions(packId)
    local pack = self.packs[packId or self:GetActivePackId()]
    local options = {}
    if not pack then return options end
    local fallback = self.packs[self.defaultPackId]
    local seen = {}
    local function Add(key)
        if seen[key] then return end
        seen[key] = true
        local definition = self.registeredKeys[key]
        options[#options + 1] = {
            value = key,
            text = definition and definition.label or key,
        }
    end
    for key in pairs(pack.sounds) do Add(key) end
    if fallback and fallback ~= pack then
        for key in pairs(fallback.sounds) do Add(key) end
    end
    table.sort(options, function(a, b)
        return a.text == b.text and a.value < b.value or a.text < b.text
    end)
    return options
end

local function ChoiceMatches(choice, query)
    if query == "" then return true end
    local text = string.lower(tostring(choice.text or ""))
    local value = string.lower(tostring(choice.value or ""))
    return string.find(text, query, 1, true) ~= nil
        or string.find(value, query, 1, true) ~= nil
end

function S:GetSoundChoices(options)
    options = type(options) == "table" and options or {}
    local sourceFilter = options.source or "all"
    local query = string.lower(tostring(options.query or ""))
    local choices, seen = {}, {}
    local function Add(choice)
        if seen[choice.value] or not ChoiceMatches(choice, query) then
            return
        end
        seen[choice.value] = true
        choices[#choices + 1] = choice
    end

    if sourceFilter == "all" or sourceFilter == "voice" then
        for key, definition in pairs(self.registeredKeys) do
            local reference = "voice:" .. key
            local kind = self:Resolve(reference)
            Add({
                value = reference,
                text = definition.label or key,
                source = "voice",
                available = kind ~= nil,
            })
        end
    end
    if sourceFilter == "all" or sourceFilter == "system" then
        for index = 1, #self.systemSoundOrder do
            local key = self.systemSoundOrder[index]
            local definition = self.systemSounds[key]
            if definition then
                Add({
                    value = "system:" .. key,
                    text = definition.labelKey and YUI.Locale and YUI.Locale:Get("Core")[definition.labelKey]
                        or definition.label or key,
                    source = "system",
                    available = definition.file ~= nil or ResolveSystemKit(definition) ~= nil,
                })
            end
        end
    end
    if sourceFilter == "all" or sourceFilter == "lsm" then
        local media = GetSharedMedia()
        local hash = media and type(media.HashTable) == "function"
            and media:HashTable("sound") or nil
        for name in pairs(type(hash) == "table" and hash or {}) do
            Add({
                value = "lsm:" .. name,
                text = name,
                source = "lsm",
                available = true,
            })
        end
    end
    local current = self:NormalizeReference(options.current)
    if current and not seen[current] then
        local source, key = SplitReference(current)
        if sourceFilter == "all" or sourceFilter == source then
            Add({
                value = current,
                text = source == "custom" and CustomFileLabel(key) or key,
                source = source,
                available = source == "custom",
            })
        end
    end
    table.sort(choices, function(a, b)
        local ao = SOURCE_ORDER[a.source] or 99
        local bo = SOURCE_ORDER[b.source] or 99
        if ao ~= bo then return ao < bo end
        if a.text ~= b.text then return a.text < b.text end
        return a.value < b.value
    end)
    return choices
end

function S:GetSoundChoice(reference)
    local normalized = self:NormalizeReference(reference)
    if not normalized then return nil end
    local choices = self:GetSoundChoices({ current = normalized })
    for index = 1, #choices do
        if choices[index].value == normalized then return choices[index] end
    end
    return nil
end

function S:Play(reference, channel, cooldown)
    local playType, value, normalized, code = self:Resolve(reference)
    if not playType then return false, code end

    local cd = tonumber(cooldown) or 0
    if cd < 0 then cd = 0 end
    local now = CombatAPI and CombatAPI.GetTime and CombatAPI.GetTime() or 0
    local lastPlay = self._lastPlay[normalized]
    if cd > 0 and lastPlay and now - lastPlay < cd then
        return false, "cooldown"
    end

    local targetChannel = channel and NormalizeChannel(channel) or self:GetChannel()
    local played, handle
    if playType == "kit" and SoundAPI and SoundAPI.PlayKit then
        played, handle = SoundAPI.PlayKit(value, targetChannel)
    elseif playType == "file" and SoundAPI and SoundAPI.PlayFile then
        played, handle = SoundAPI.PlayFile(value, targetChannel)
    end
    if not played and playType == "file" and self.PlayLegacyFallback then
        played, handle = self:PlayLegacyFallback(normalized, code, value, targetChannel)
    end
    if not played then return false, "play-failed" end
    self._lastPlay[normalized] = now
    return true, handle
end

if YUI.Event and YUI.Event.On and not S._dbReadyListener then
    S._dbReadyListener = true
    YUI.Event:On("YUI_DB_READY", function()
        S:LoadSettings()
    end, S, { moduleId = "component.voice" })
end
