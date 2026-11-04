local YUI = _G.YUI
local CL = YUI.Changelog or {}
YUI.Changelog = CL
local Assets = YUI.Assets
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}

local C_Timer = C_Timer

function CL:CreatePopup(version, preview)
    local GUI2 = YUI.GUI2
    if not GUI2 then return end
    local key = preview and "previewPopup" or "popup"
    if not self[key] then
        self[key] = GUI2.Overlay:CreateTimedNotice(UIParent, {
            width=380,height=90,
            icon=Assets:Core("images\\YUI-LOGO-300.png"),
        })
        self[key]:SetPoint("LEFT",50,0)
    end
    local popup=self[key]
    local function dismiss() if not preview then self:MarkAsSeen(version) end; popup:Hide() end
    popup:Start({
        title=LC["settings.changelog.popup_title"]..(preview and (" · "..LC["dev.notice.test"]) or ""),
        body=string.format(LC["settings.changelog.popup_subtext"],version),
        duration=10,pauseOnHover=true,onExpire=dismiss,onDismiss=dismiss,
        onClick=function()
            dismiss()
            if YUI.Settings and YUI.Settings.Toggle then
                YUI.Settings:Toggle()
                local module=YUI.Settings.modulesById and YUI.Settings.modulesById["core.changelog"]
                if module then YUI.Settings:SelectModule(module) end
            end
        end,
    })
end

-- 检查版本
function CL:CheckVersion()
    -- 获取最新版本
    local data = self:GetData()
    if not data or #data == 0 then return end
    
    local latestVer = data[1].version
    
    -- 获取上次检查的版本
    local lastVer = YUI.global and YUI.global.lastChangelogVersion
    
    -- 首次运行（无记录），直接记录当前版本，不弹窗
    if not lastVer then
        if YUI.global then
            YUI.global.lastChangelogVersion = latestVer
        end
        return
    end
    
    -- 比较
    local compareResult = self:CompareVersion(latestVer, lastVer)
    
    -- Dev模式下只要版本不同(包括降级)都显示，方便调试
    -- 正常模式下只显示新版本
    --if compareResult > 0 or YUI.IsDev then
    if compareResult > 0 then
        -- 延迟显示，确保 UI 加载完毕
        C_Timer.After(8, function()
            self:CreatePopup(latestVer)
        end)
    end
end

-- 初始化事件监听
local function Initialize()
    if not YUI.Event then return end

    YUI.Event:Once("PLAYER_ENTERING_WORLD", function()
        -- 尝试检查版本
        if YUI.global then
            CL:CheckVersion()
        else
            print("|cff00ffff[YUI]|r DB not ready, retrying...")
            -- 如果 DB 还没好（极低概率），延迟重试
            C_Timer.After(1, function()
                if YUI.global then CL:CheckVersion() end
            end)
        end
    end)
end

Initialize()
