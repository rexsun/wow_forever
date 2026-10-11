local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not (Native and YUI.IsForever and Native.IS_SUITE) then return end

local importOwner = {}
local attempted = false

function Native:CancelBetaProfileImport()
    if YUI.Event then YUI.Event:OffOwner(importOwner) end
end

-- 用户提供的 Beta 完整配置，通过目标插件的公开导入接口应用。
local PROFILE_STRING = [=[PLATY!1!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]=]

local function ResumeImport()
    Native:ApplyBetaProfile()
end

function Native:ApplyBetaProfile()
    self:CancelBetaProfileImport()
    if attempted or not self.runtimeEnabled or not self:GetConfig().importBetaProfile then return end
    local api = _G.Platynator and _G.Platynator.API
    local config = _G.PLATYNATOR_CONFIG
    -- 只读检测已初始化的数据；已有同名配置时不覆盖，也不切换当前配置。
    if not (api and type(api.ImportString) == "function"
        and type(config) == "table" and type(config.Profiles) == "table") then return end
    if config.Profiles.YUI ~= nil then return end
    if InCombatLockdown and InCombatLockdown() then
        if YUI.Event then
            YUI.Event:On("PLAYER_REGEN_ENABLED", ResumeImport, importOwner, {
                moduleId = self.MODULE_ID,
                traceName = "NativeInterface:beta-profile",
            })
        end
        return
    end
    attempted = true
    local ok = pcall(function()
        -- 在原生导入前调整配置，让配置切换同时触发缩放刷新。
        local encoding = C_EncodingUtil
        local profile = encoding.DeserializeCBOR(encoding.DecompressString(encoding.DecodeBase64(PROFILE_STRING:sub(9))))
        assert(type(profile) == "table" and profile.addon == "Platynator" and profile.kind == "profile")
        profile.global_scale = 1.2
        local payload = "PLATY!1!" .. encoding.EncodeBase64(encoding.CompressString(encoding.SerializeCBOR(profile)))
        api.ImportString(payload, "YUI")
    end)
    if not ok or type(config.Profiles.YUI) ~= "table" then
        if YUI.Print then YUI:Print(self:GetLocaleText("beta.import_profile.failed")) end
    end
end
