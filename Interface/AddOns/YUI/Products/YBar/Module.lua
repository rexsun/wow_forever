local YUI = _G.YUI
local YBar = YUI.YBar

local Module = {}
YBar.Module = Module
Module.__index = Module

function Module:New(name)
    local obj = setmetatable({}, Module)
    obj.name = name
    obj.settings = {} -- 模块特定设置
    return obj
end

function Module:OnInitialize()
    -- YBar 初始化时调用
end

function Module:OnEnable()
    -- 模块启用时调用
end

function Module:OnDisable()
    -- 模块禁用时调用
end

function Module:OnLifecycleInitialize()
    if self._ybarInitialized then return end
    if self.OnInitialize then
        self:OnInitialize()
    end
    self._ybarInitialized = true
end

function Module:OnLifecycleEnable()
    if self._hasError then
        if self.DetachRuntime then
            self:DetachRuntime()
        end
        return
    end

    if self.AttachRuntime then
        self:AttachRuntime()
    end
    if self.frame then
        self.frame:Show()
    end
    if self.UpdateBarItem then
        self:UpdateBarItem(self.frame, self.parent)
    elseif self.Update then
        self:Update()
    end
end

function Module:OnLifecycleDisable()
    if self.DetachRuntime then
        self:DetachRuntime()
    end
    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and (owner == self.frame or owner == self.content) then
            YUI.HideGameTooltip()
        end
    end
    if self.frame then
        self.frame:Hide()
    end
end

function Module:OnLifecycleProfileChanged()
    if self._hasError then
        self:OnLifecycleDisable()
        return
    end

    if YUI.YBar and YUI.YBar:IsSubModuleEnabled(self.name) then
        self:OnLifecycleEnable()
    else
        self:OnLifecycleDisable()
    end
end

function Module:OnLifecycleConfigChanged()
    if self._hasError then
        return
    end

    if self.UpdateBarItem then
        self:UpdateBarItem(self.frame, self.parent)
    elseif self.Update then
        self:Update()
    end
end

function Module:OnLifecycleLayoutChanged()
    self:OnLifecycleProfileChanged()
end

function Module:UpdateLayout()
    -- 布局需要更新时调用（位置、大小等）
end

function Module:GetConfig()
    -- 返回设置的配置表
    return {}
end
