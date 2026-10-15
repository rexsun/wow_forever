local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and Native.IS_SUITE and YUI.IsForever == true and Security) then return end

-- Verified on 1.60.1.70338: this atlas resolves to unrelated window artwork.
local WHITE_ATLAS = "auctionhouse-itemicon-border-white"
local BROKEN_FILE, BORDER_FILE = 8164391, 3046538
local LEFT, RIGHT, TOP, BOTTOM = 139 / 1024, 275 / 1024, 715 / 1024, 851 / 1024
local owner, recoveryOwner = {}, {}
local states = setmetatable({}, { __mode = "k" })
local forms = setmetatable({}, { __mode = "k" })
local watching, recovering = false, false
local repairs, restores, hookCount = 0, 0, 0
local lastReason = "inactive"
local Reconcile, ReleaseAll

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Usable(object)
    if not Public(object) or not object then return false end
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return false end
    if object.IsForbidden then
        local ok, value = Security.SafeMethod("NativeInterface:profession-icon-forbidden", object, "IsForbidden")
        if not ok or not Public(value) or value ~= false then return false end
    end
    if object.HasSecretValues then
        local ok, value = Security.SafeMethod("NativeInterface:profession-icon-secret", object, "HasSecretValues")
        if not ok or not Public(value) or value ~= false then return false end
    end
    return true
end

local function Coordinates(texture, left, right, top, bottom)
    local ok, a, b, c, d, e, f, g, h = Security.SafeMethod("NativeInterface:profession-icon-coords", texture, "GetTexCoord")
    if not (ok and Public(a) and Public(b) and Public(c) and Public(d)
        and Public(e) and Public(f) and Public(g) and Public(h)) then return nil end
    return a == left and b == top and c == left and d == bottom
        and e == right and f == top and g == right and h == bottom
end

local function ReadAsset(texture)
    local atlasOK, atlas = Security.SafeMethod("NativeInterface:profession-icon-atlas", texture, "GetAtlas")
    local fileOK, file = Security.SafeMethod("NativeInterface:profession-icon-file", texture, "GetTexture")
    if atlasOK and fileOK and Public(atlas) and Public(file) then return true, atlas, file end
    return false
end

local function OnRecovery()
    if Security.InCombatLockdown() then return end
    if watching then Reconcile() else ReleaseAll() end
end

local function SetRecovery(enabled)
    if enabled == recovering then return end
    recovering = enabled
    if enabled then
        YUI.Event:On("PLAYER_REGEN_ENABLED", OnRecovery, recoveryOwner, { moduleId = Native.MODULE_ID })
    else
        YUI.Event:OffOwner(recoveryOwner)
    end
end

-- SetAtlas can retain explicit sheet coordinates. Release only our own crop,
-- even when the next native atlas uses the same source file (e.g. green quality).
local function ClearCrop(texture, state)
    if not state.owned then return true end
    if not Usable(texture) or Security.InCombatLockdown() then SetRecovery(true); return false end
    local cropped = Coordinates(texture, LEFT, RIGHT, TOP, BOTTOM)
    if cropped == nil then SetRecovery(true); return false end
    if cropped then
        state.writing = true
        local ok = Security.SafeMethod("NativeInterface:profession-icon-clear-crop", texture, "SetTexCoord", 0, 1, 0, 1)
        state.writing = false
        if not ok then SetRecovery(true); return false end
    end
    state.owned = false
    return true
end

local function Restore(texture, state)
    if not state.owned then return true end
    if not Usable(texture) or Security.InCombatLockdown() then return false end
    local ok, atlas, file = ReadAsset(texture)
    local cropped = Coordinates(texture, LEFT, RIGHT, TOP, BOTTOM)
    local default = Coordinates(texture, 0, 1, 0, 1)
    if not ok or cropped == nil or default == nil then return false end
    -- A different explicit crop belongs to another writer.
    if not cropped and not default then state.owned = false; return true end
    state.writing = true
    local restored = true
    if file == BORDER_FILE and (atlas == nil or atlas == WHITE_ATLAS) then
        restored = Security.SafeMethod("NativeInterface:profession-icon-restore-atlas", texture, "SetAtlas", WHITE_ATLAS)
    end
    if restored and cropped then
        restored = Security.SafeMethod("NativeInterface:profession-icon-restore-crop", texture, "SetTexCoord", 0, 1, 0, 1)
    end
    state.writing = false
    if restored then state.owned = false; restores = restores + 1 end
    return restored
end

ReleaseAll = function()
    local pending = false
    for texture, state in pairs(states) do
        if not Restore(texture, state) then pending = true end
    end
    SetRecovery(pending)
    lastReason = pending and "restore-deferred" or "inactive"
end

local function Target()
    local frame = _G.ProfessionsFrame
    local page = Usable(frame) and frame.CraftingPage
    local form = Usable(page) and page.SchematicForm
    local button = Usable(form) and form.OutputIcon
    if not (Usable(button) and type(button.GetParent) == "function"
        and type(button.GetHighlightTexture) == "function") then return end
    local ok, parent = Security.SafeMethod("NativeInterface:profession-icon-button-parent", button, "GetParent")
    if not ok or not Public(parent) or parent ~= form then return end
    local highlightOK, highlight = Security.SafeMethod("NativeInterface:profession-icon-highlight", button, "GetHighlightTexture")
    if not highlightOK or not Public(highlight) then return end
    return button, form, highlight
end

local function IsTarget(texture)
    local button, _, highlight = Target()
    if not (button and Usable(texture) and type(texture.GetParent) == "function") then return false end
    local ok, parent = Security.SafeMethod("NativeInterface:profession-icon-texture-parent", texture, "GetParent")
    return ok and Public(parent) and parent == button
        and (texture == button.IconBorder or texture == highlight)
end

local function Repair(texture, state)
    if not watching or not IsTarget(texture) then return end
    if Security.InCombatLockdown() then SetRecovery(true); lastReason = "combat-deferred"; return end
    if state.failed then
        if not Restore(texture, state) then SetRecovery(true) end
        lastReason = "write-failed"; return
    end
    local ok, atlas, file = ReadAsset(texture)
    if not ok then lastReason = "asset-unconfirmed"; return end
    if state.owned and file == BORDER_FILE and (atlas == nil or atlas == WHITE_ATLAS)
        and Coordinates(texture, LEFT, RIGHT, TOP, BOTTOM) == true then return end
    if not ClearCrop(texture, state) then return end
    if atlas ~= WHITE_ATLAS or file ~= BROKEN_FILE then lastReason = "native-material-retained"; return end
    if Coordinates(texture, 0, 1, 0, 1) ~= true then lastReason = "custom-crop-retained"; return end
    state.writing, state.owned = true, true
    local textureOK = Security.SafeMethod("NativeInterface:profession-icon-texture", texture, "SetTexture", BORDER_FILE)
    local coordsOK = textureOK and Security.SafeMethod("NativeInterface:profession-icon-crop", texture,
        "SetTexCoord", LEFT, RIGHT, TOP, BOTTOM)
    state.writing = false
    if textureOK and coordsOK then
        repairs = repairs + 1; lastReason = "repaired"
    else
        state.failed = true
        if not Restore(texture, state) then SetRecovery(true) end
        lastReason = "write-failed"
    end
end

local function OnAtlas(texture)
    local state = states[texture]
    if not state or state.writing or not (watching or state.owned) then return end
    if not ClearCrop(texture, state) then return end
    if watching then Repair(texture, state) else ReleaseAll() end
end

local function OnTexture(texture)
    local state = states[texture]
    if state and not state.writing and state.owned and ClearCrop(texture, state) and not watching then ReleaseAll() end
end

local function EnsureTexture(texture)
    if not IsTarget(texture) then return end
    local state = states[texture]
    if not state then state = {}; states[texture] = state end
    if not state.atlasHook then
        state.atlasHook = Security.SafeHook("NativeInterface:profession-icon-native-atlas", texture, "SetAtlas", OnAtlas)
        if state.atlasHook then hookCount = hookCount + 1 end
    end
    if not state.textureHook then
        state.textureHook = Security.SafeHook("NativeInterface:profession-icon-native-texture", texture, "SetTexture", OnTexture)
        if state.textureHook then hookCount = hookCount + 1 end
    end
    if state.atlasHook and state.textureHook then Repair(texture, state) end
end

local function OnShow()
    if watching then Reconcile() end
end

Reconcile = function()
    if Security.InCombatLockdown() then SetRecovery(true); lastReason = "combat-deferred"; return end
    SetRecovery(false)
    local button, form, highlight = Target()
    if not button then ReleaseAll(); lastReason = "native-structure-unconfirmed"; return end
    if not forms[form] then
        forms[form] = Security.SafeMethod("NativeInterface:profession-icon-on-show", form, "HookScript", "OnShow", OnShow)
        if forms[form] then hookCount = hookCount + 1 end
    end
    EnsureTexture(button.IconBorder)
    EnsureTexture(highlight)
    -- Pending crops can also belong to replaced native texture objects.
    local pending = recovering
    for texture, state in pairs(states) do
        if state.owned and not IsTarget(texture) and not Restore(texture, state) then pending = true end
    end
    SetRecovery(pending)
end

local function OnEvent(event, addonName)
    if not watching then return end
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_Professions"
        and addonName ~= "Blizzard_ProfessionsTemplates" and addonName ~= "Blizzard_ProfessionsCrafting" then return end
    Reconcile()
end

function Native:RefreshProfessionsIconFix()
    local enabled = self.runtimeEnabled == true and self:GetConfig().fixProfessionsIcon == true and YUI.Event
        and type(YUI.Event.On) == "function" and type(YUI.Event.OffOwner) == "function"
    enabled = enabled == true
    if watching ~= enabled then
        watching = enabled
        if watching then
            YUI.Event:On("ADDON_LOADED", OnEvent, owner, { moduleId = self.MODULE_ID })
            YUI.Event:On("PLAYER_ENTERING_WORLD", OnEvent, owner, { moduleId = self.MODULE_ID })
        else YUI.Event:OffOwner(owner) end
    end
    for _, state in pairs(states) do state.failed = nil end
    if watching then Reconcile() else ReleaseAll() end
end

function Native:ReleaseProfessionsIconFix()
    watching = false
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(owner) end
    ReleaseAll()
end

function Native:GetProfessionsIconFixDiagnostics()
    local owned = 0
    for _, state in pairs(states) do if state.owned then owned = owned + 1 end end
    return { watching = watching, recovering = recovering, owned = owned,
        repairs = repairs, restores = restores, hookCount = hookCount, lastReason = lastReason }
end
