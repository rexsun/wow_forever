local YUI = _G.YUI
local GUI = YUI.GUI2
local Tooltip = {}
GUI.Tooltip = Tooltip

local function T(key, fallback)
    local locale = YUI.Locale and YUI.Locale:Get("Core")
    local value = locale and locale[key]
    return value and value ~= key and value or fallback or key
end

local function Color(tone)
    return GUI:GetColor("color.tooltip." .. (tone or "body"))
end

local function Colored(text, tone)
    local r, g, b = Color(tone)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r*255+.5), math.floor(g*255+.5), math.floor(b*255+.5), text)
end

function Tooltip:ColorText(text, tone)
    return Colored(text, tone)
end

function Tooltip:IconText(text, icon)
    if not icon then return text end
    local size = GUI:GetToken("tooltip.icon.size") or 12
    local atlas = type(icon) == "string" and icon:match("^atlas:(.+)$")
    if atlas then return string.format("|A:%s:%d:%d|a %s", atlas, size, size, text) end
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t %s", icon, size, size, text)
end

local buttons = {LeftButton="left", RightButton="right", MiddleButton="middle"}
local modifiers = {ALT="Alt", CTRL="Ctrl", SHIFT="Shift"}
-- 仅格式化文案；不持有 owner、不绑定按键或改变当前 Tooltip。
function Tooltip:FormatAction(spec, settings)
    local parts = {}
    for _, modifier in ipairs(spec.modifiers or {}) do parts[#parts+1] = modifiers[modifier] or modifier end
    if spec.key then
        parts[#parts+1] = modifiers[spec.key] or spec.key
    else
        local key = "tooltip.button." .. (buttons[spec.button or "LeftButton"] or "left")
        parts[#parts+1] = T(key)
    end
    local text = spec.text or (settings and T("tooltip.open_settings")) or ""
    local keys = table.concat(parts, " + ")
    if spec.key and spec.keyAction == "hold" then
        keys = string.format(T("tooltip.key.hold", "Hold %s"), keys)
    elseif spec.key and spec.keyAction == "release" then
        keys = string.format(T("tooltip.key.release", "Release %s"), keys)
    end
    local keyTone = spec.keyTone or (settings and "settings" or "body")
    local textTone = spec.textTone or (settings and "settings" or "action")
    -- 分隔符也跟随按键颜色；嵌套动作染色不依赖 AddLine 的默认颜色。
    return Colored(string.format(T("tooltip.action_format", "%s: %s"), keys, Colored(text, textTone)), keyTone)
end

local function Clear()
    Tooltip.owner, Tooltip.spec = nil, nil
end

function Tooltip:Hide(owner)
    if self.owner ~= owner then return end
    if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    Clear()
end

local function OwnerHidden(owner) Tooltip:Hide(owner) end

function Tooltip:Show(owner, spec)
    local tip = GameTooltip
    if not owner or not tip or not spec then return end
    if tip.HookScript and not self.hooked then tip:HookScript("OnHide", Clear); self.hooked = true end
    if owner.HookScript and not owner.gui2TooltipOwnerHooked then
        owner:HookScript("OnHide", OwnerHidden)
        owner.gui2TooltipOwnerHooked = true
    end
    tip:SetOwner(owner, spec.anchor or "ANCHOR_RIGHT")
    self.owner, self.spec = owner, spec
    local title = type(spec.title) == "table" and spec.title or {text=spec.title or ""}
    local heading = self:IconText(title.text or "", title.icon)
    if spec.subtitle then
        tip:ClearLines()
        local subtitle = type(spec.subtitle) == "table" and spec.subtitle or {text=spec.subtitle}
        local r,g,b = Color("heading")
        tip:AddDoubleLine(heading, subtitle.text or "", r,g,b,r,g,b)
    else
        local r,g,b = Color("heading")
        tip:SetText(heading,r,g,b)
    end
    -- 标题下方始终留一行空白，包括无正文的提示。
    tip:AddLine(" ")
    local count = 0
    local body = {}
    function body:AddLine(text, tone, icon)
        if not text or text == "" then return end
        local r,g,b = Color(tone)
        tip:AddLine(Tooltip:IconText(text,icon),r,g,b,true)
        count = count + 1
    end
    function body:AddDoubleLine(left,right,leftTone,rightTone)
        local r,g,b = Color(leftTone)
        local rr,rg,rb = Color(rightTone or leftTone)
        -- 原生双列行用左侧文字撑开高度；右列续行也保留一个空格。
        tip:AddDoubleLine(left and left ~= "" and left or " ",right or "",r,g,b,rr,rg,rb)
        count = count + 1
    end
    function body:AddSpace() tip:AddLine(" ") end
    if spec.content then
        local ok, message = pcall(spec.content, body)
        if not ok then self:Hide(owner); error(message, 0) end
    end
    local actions = spec.actions or {}
    if count > 0 and (#actions > 0 or spec.settings or spec.footer) then tip:AddLine(" ") end
    for _, action in ipairs(actions) do body:AddLine(self:FormatAction(action),"action") end
    if spec.settings then body:AddLine(self:FormatAction(spec.settings,true),"settings") end
    if spec.footer then
        local footer = type(spec.footer) == "table" and spec.footer or {text=spec.footer}
        body:AddLine(footer.text,footer.tone or "secondary",footer.icon)
    end
    tip:Show()
end

function Tooltip:Refresh(owner)
    if self.owner == owner and self.spec and GameTooltip and GameTooltip:IsOwned(owner) then
        self:Show(owner,self.spec)
    end
end

-- Shared, inert artwork: neither product runtime nor live combat recommendations are used.
local AssistedHighlightTooltip = {}
GUI.AssistedHighlightTooltip = AssistedHighlightTooltip

function AssistedHighlightTooltip:Hide(owner)
    if owner and self.owner ~= owner then return end
    self.owner = nil
    for _, sample in ipairs(self.samples or {}) do
        GUI:SetManagedAssistedHighlightShown(sample.glow, false)
    end
    if self.panel then self.panel:Hide() end
end

function AssistedHighlightTooltip:Show(owner, title)
    if not owner or YUI.IsRetail ~= true then return end
    self:Hide()
    if YUI.HideGameTooltip then YUI.HideGameTooltip() end
    if not self.panel then
        local panel = GUI:CreatePanel(UIParent, { width = 220, height = 150,
            surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        self.panel = panel
        panel:SetFrameStrata("TOOLTIP")
        panel:SetClampedToScreen(true)
        panel:EnableMouse(false)
        if YUI.Settings and YUI.Settings.RegisterScaleWindow then
            YUI.Settings:RegisterScaleWindow(panel)
        end
        self.title = GUI:CreateText(panel, "", "font.size.md", "color.text.heading")
        self.title:SetPoint("TOP", 0, -10)
        self.footer = GUI:CreateText(panel, "", "font.size.sm", "color.text.secondary")
        self.footer:SetWidth(196)
        self.footer:SetJustifyH("CENTER")
        self.footer:SetWordWrap(true)
        self.footer:SetPoint("BOTTOM", 0, 10)
        self.samples = {}
        for index = 1, 2 do
            local sample = GUI:CreateFrame(panel, { width = 42, height = 42, mouse = false })
            sample:SetPoint("TOPLEFT", index == 1 and 44 or 134, -38)
            sample.icon = sample:CreateTexture(nil, "ARTWORK")
            sample.icon:SetAllPoints(sample)
            sample.icon:SetTexture(132261)
            sample.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            -- This private, unprotected art host can also be created on first hover in combat.
            sample.glow = GUI:CreateFrame(sample, {
                template = "ActionBarButtonAssistedCombatHighlightTemplate", mouse = false })
            GUI:LayoutManagedAssistedHighlight(sample.glow, sample, 42, 42,
                sample:GetFrameLevel() + 15, "TOOLTIP", "square")
            GUI:SetManagedAssistedHighlightShown(sample.glow, false)
            local label = GUI:CreateText(panel,
                T(index == 1 and "assisted_highlight.preview_on" or "assisted_highlight.preview_off"),
                "font.size.sm", "color.text.primary")
            label:SetPoint("TOP", sample, "BOTTOM", 0, -8)
            self.samples[index] = sample
        end
        panel:HookScript("OnHide", function() if self.owner then self:Hide() end end)
    end
    self.owner = owner
    self.title:SetText(title or T("assisted_highlight.title"))
    self.footer:SetText(T("assisted_highlight.requirement"))
    self.panel:ClearAllPoints()
    self.panel:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 10)
    GUI:SetManagedAssistedHighlightShown(self.samples[1].glow, true)
    self.panel:Show()
end

function AssistedHighlightTooltip:Bind(owner, title)
    if not owner or not owner.HookScript then return end
    owner.gui2AssistedHighlightTitle = title
    if owner.gui2AssistedHighlightTooltipBound then return end
    owner.gui2AssistedHighlightTooltipBound = true
    owner:HookScript("OnEnter", function(frame)
        self:Show(frame, frame.gui2AssistedHighlightTitle)
    end)
    owner:HookScript("OnLeave", function(frame) self:Hide(frame) end)
    owner:HookScript("OnHide", function(frame) self:Hide(frame) end)
end
