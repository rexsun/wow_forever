local ADDON_NAME, YUI = ...

-- 仅针对时光服 (Wrath Classic)
if not YUI.IsWrath then return end
if not C_AddOns.IsAddOnLoaded("Platynator") then return end

local Components = YUI.Components

local restoreShowLevel
local suppressionApplied = false

local function SetFriendlyNamePlateShowLevel(showLevel)
    if not (NamePlateFriendlyFrameOptions and TextureLoadingGroupMixin
        and TextureLoadingGroupMixin.RemoveTexture and TextureLoadingGroupMixin.AddTexture) then
        return false
    end

    local textureGroup = { textures = NamePlateFriendlyFrameOptions }
    if showLevel then
        TextureLoadingGroupMixin.AddTexture(textureGroup, "showLevel")
    else
        TextureLoadingGroupMixin.RemoveTexture(textureGroup, "showLevel")
    end
    return true
end

local function GetEffectiveState()
    if not (TextureLoadingGroupMixin and TextureLoadingGroupMixin.RemoveTexture and TextureLoadingGroupMixin.AddTexture) then
        return {
            effective = false,
            reason = "姓名板优化所需的 TextureLoadingGroupMixin API 不可用。",
            tone = "danger",
        }
    end
    if not NamePlateFriendlyFrameOptions then
        return {
            effective = false,
            reason = "友方姓名板默认配置表不可用。",
            tone = "danger",
        }
    end
    return { effective = true }
end

-- 注册 Components 功能
Components:RegisterFeature("ForbiddenNamePlates", {
    name = "Platynator姓名板优化",
    description = "在副本等受限区域隐藏友方姓名板等级数字。",
    default = false,
    requiresReload = true,
    GetEffectiveState = GetEffectiveState,
    callback = function(enable)
        -- 通过暴雪的 Mixin 修改受限环境也会读取的友方姓名板配置表
        if enable then
            if not NamePlateFriendlyFrameOptions then
                return
            end
            if not suppressionApplied then
                restoreShowLevel = NamePlateFriendlyFrameOptions.showLevel == true
            end
            if not SetFriendlyNamePlateShowLevel(false) then
                return
            end
            suppressionApplied = true
        elseif suppressionApplied then
            SetFriendlyNamePlateShowLevel(restoreShowLevel == true)
            restoreShowLevel = nil
            suppressionApplied = false
        else
            return
        end
    end
})
