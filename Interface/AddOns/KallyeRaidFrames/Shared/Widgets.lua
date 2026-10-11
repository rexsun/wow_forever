local _, ns = ...

K_SHARED_UI = K_SHARED_UI or {};

-- ! avoid conflict override
if ns.CONFLICT then return; end

-- * Share locales between shared ui files
K_SHARED_UI.I18N = K_SHARED_UI.I18N or {}
K_SHARED_UI.I18N[ns.ADDON_NAME] = K_SHARED_UI.I18N[ns.ADDON_NAME] or ns.I18N
--- Shared ui locales access
local function l(localeName)
    for _, locales in pairs(K_SHARED_UI.I18N) do
        if locales[localeName] then
            return locales[localeName]
        end
    end
    return nil
end

--- Function to display a tooltip
--- @param frame frame The frame to which the tooltip is attached
--- @param title string The title of the tooltip
--- @param text string The text of the tooltip (optional)
--- @param anchor string The anchor of the tooltip (optional)
--- @return nil
local function showTooltip(frame, title, text, anchor)
	title = l(title) or _G[title] or title;
	text = l(text) or _G[text] or text or "";
	text = text ~= title and text or "";

	GameTooltip:SetOwner(frame, anchor or "ANCHOR_RIGHT");
	if (title ~= "") then
		GameTooltip:SetText(l("WH")..title);
		GameTooltip:AddLine(text, 1, 0.82, 0, 1);
	else
		GameTooltip:SetText(text, 1, 0.82, 0, 1);
	end
	GameTooltip:AppendText("");
end

-- #region Checkbox Widget
--[[
! Checkbox Widget
Simple checkbutton widget with text
]]
function K_SHARED_UI.CheckboxWidget_OnClick(self)
	if ( self:GetChecked() ) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF, "Master")
	end
end
function K_SHARED_UI.CheckboxWidget_OnLoad(self)
	self.type = "checkbox";

	local text = self:GetAttribute("text");
	text = l(text) or _G[text] or text;

	self.Text:SetText(text);
end
function K_SHARED_UI.CheckboxWidget_OnEnter(self)
	if (not self:IsEnabled()) then return end;
	local text = self:GetAttribute("text") or self:GetAttribute("title") or "";
	local tooltip = self:GetAttribute("tooltip") or "";
	showTooltip(self, text, tooltip, "ANCHOR_RIGHT")
end
function K_SHARED_UI.CheckboxWidget_OnLeave(self)
	-- GameTooltip:Hide(); -- intended, UI too sensitive
end
-- #endregion Checkbox Widget

-- #region Heading Widget
--[[
! Heading Widget
Title with left & right border
]]
function K_SHARED_UI.HeadingWidget_OnLoad (self)
	local transparent = self:CreateTexture(nil, "BACKGROUND")
	self:SetNormalTexture(transparent);
	self:SetHighlightTexture(transparent);
	self:SetPushedTexture(transparent);

	local text = self:GetAttribute("text");
	text = l(text) or _G[text] or text;

	self.label = self:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	self.label:SetPoint("TOP")
	self.label:SetPoint("BOTTOM")
	self.label:SetJustifyH("CENTER")
	self.label:SetText(text);

	self.leftRule = self:CreateTexture(nil, "BACKGROUND")
	local paddingLeft = tonumber(self:GetAttribute("paddingLeft")) or 5
	self.leftRule:SetHeight(8)
	self.leftRule:SetPoint("LEFT", 3, 0)
	self.leftRule:SetPoint("RIGHT", self.label, "LEFT", text ~= "" and -paddingLeft or 1, 0)
	self.leftRule:SetTexture(137057) -- Interface\\Tooltips\\UI-Tooltip-Border
	self.leftRule:SetTexCoord(0.81, 0.94, 0.5, 1)

	self.rightRule = self:CreateTexture(nil, "BACKGROUND")
	local paddingRight = tonumber(self:GetAttribute("paddingRight")) or 5
	self.rightRule:SetHeight(8)
	self.rightRule:SetPoint("RIGHT", -3, 0)
	self.rightRule:SetPoint("LEFT", self.label, "RIGHT", text ~= "" and paddingRight or -1, 0)
	self.rightRule:SetTexture(137057) -- Interface\\Tooltips\\UI-Tooltip-Border
	self.rightRule:SetTexCoord(0.81, 0.94, 0.5, 1);
end
-- disable checked state
function K_SHARED_UI.HeadingWidget_OnClick(self)
	self:SetChecked(false);
end
function K_SHARED_UI.HeadingWidget_SetPaddings(self, paddingLeft, paddingRight)
	self.leftRule:SetPoint("RIGHT", self.label, "LEFT", -paddingLeft, 0)
	self.rightRule:SetPoint("LEFT", self.label, "RIGHT", paddingRight, 0)
end
-- #endregion Heading Widget

-- #region Text Widget
--[[
! Text Widget
Only text
]]
function K_SHARED_UI.TextWidget_OnLoad (self)
	local transparent = self:CreateTexture(nil, "BACKGROUND")
	self:SetNormalTexture(transparent);
	self:SetHighlightTexture(transparent);
	self:SetPushedTexture(transparent);

	local text = self:GetAttribute("text");
	text = l(text) or _G[text] or text;

	self.label = self:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	self.label:SetPoint("LEFT", 5, 0)
	-- self.label:SetPoint("BOTTOM")
	--self.label:SetJustifyH("RIGHT")
	self.label:SetText(text);
end
-- disable checked state
function K_SHARED_UI.TextWidget_OnClick(self)
	self:SetChecked(false);
end
-- #endregion Text Widget

-- #region Color Widget
--[[
! Color Widget
-- Removed OpacitySliderFrame, Since Dragonflight (10)
]]
local function ColorWidget_ShowColorPicker(pickedCallback, cancelledCallback, self)
	ColorPickerFrame.Self = self;
	local r,g,b,o = self._RGBA.r, self._RGBA.g, self._RGBA.b, self._RGBA.a or nil;
	local info = {
		swatchFunc = pickedCallback,

		hasOpacity = (o ~= nil),
		opacityFunc = pickedCallback,
		opacity = o,

		cancelFunc = cancelledCallback,

		r = r,
		g = g,
		b = b,
	}
	ColorPickerFrame:SetupColorPickerAndShow(info)
end
local function ColorWidget_ColorPickedCallback()
	local newR, newG, newB = ColorPickerFrame:GetColorRGB();
	local newA = ColorPickerFrame.hasOpacity and ColorPickerFrame:GetColorAlpha() or nil;
	ColorPickerFrame.Self:SetColor({ r = newR , g = newG, b = newB, a = newA })
end
local function ColorWidget_ColorCancelledCallback()
	local newR, newG, newB, newA = ColorPickerFrame:GetPreviousValues();
	ColorPickerFrame.Self:SetColor({ r = newR , g = newG, b = newB, a = newA });
end

--[[
! Color Widget Classic
Autodetect if alpha is set: opacity available
]]
local function ColorWidget_ShowColorPicker_Classic(pickedCallback, cancelledCallback, self)
	ColorPickerFrame.Self = self;
	local r,g,b,o = self._RGBA.r, self._RGBA.g, self._RGBA.b, self._RGBA.a or nil;
	ColorPickerFrame:SetColorRGB(r,g,b);
	ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = (o ~= nil), o and (1 - o) or nil;
	ColorPickerFrame._previousValues = {r, g, b, o};
	ColorPickerFrame.func, ColorPickerFrame.swatchFunc, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc =
		pickedCallback, pickedCallback, pickedCallback, cancelledCallback;
	ColorPickerFrame:Hide(); -- Need to run the OnShow handler.
	ColorPickerFrame:Show();
end
local function ColorWidget_ColorPickedCallback_Classic()
	local newR, newG, newB = ColorPickerFrame:GetColorRGB();
	local newA = ColorPickerFrame.hasOpacity and (1 - OpacitySliderFrame:GetValue()) or nil;
	ColorPickerFrame.Self:SetColor({ r = newR , g = newG, b = newB, a = newA });
end
local function ColorWidget_ColorCancelledCallback_Classic()
	local newR, newG, newB, newA = unpack(ColorPickerFrame._previousValues);
	ColorPickerFrame.Self:SetColor({ r = newR , g = newG, b = newB, a = newA });
end

local function ColorWidget_SetColor(self, RGBA)
	self._RGBA = RGBA or self._RGBA;
	self._colorSwatch:SetVertexColor(self._RGBA.r, self._RGBA.g, self._RGBA.b, self._RGBA.a)
end
local function ColorWidget_GetColor(self)
	return self._RGBA;
end

function K_SHARED_UI.ColorWidget_OnLoad (self)
	self.type = "color";

	local text = self:GetAttribute("text");
	text = l(text) or _G[text] or text;

	self._RGBA = { r=1, g=1, b=1, a=1}
	self.SetColor = ColorWidget_SetColor;
	self.GetColor = ColorWidget_GetColor;

	self:EnableMouse(true)

	local transparent = self:CreateTexture(nil, "BACKGROUND")
	self:SetNormalTexture(transparent)

	local colorSwatch = self:CreateTexture(nil, "OVERLAY")
	colorSwatch:SetWidth(20)
	colorSwatch:SetHeight(20)
	colorSwatch:SetTexture(130939) -- Interface\\ChatFrame\\ChatFrameColorSwatch
	colorSwatch:SetPoint("LEFT", 4, 0)
	self._colorSwatch = colorSwatch

	local texture = self:CreateTexture(nil, "BACKGROUND")
	colorSwatch.background = texture
	texture:SetWidth(16)
	texture:SetHeight(16)
	texture:SetColorTexture(1, 1, 1)
	texture:SetPoint("CENTER", colorSwatch)
	texture:Show()

	local checkers = self:CreateTexture(nil, "BACKGROUND")
	colorSwatch.checkers = checkers
	checkers:SetWidth(14)
	checkers:SetHeight(14)
	checkers:SetTexture(188523) -- Tileset\\Generic\\Checkers
	checkers:SetTexCoord(.25, 0, 0.5, .25)
	checkers:SetDesaturated(true)
	checkers:SetVertexColor(1, 1, 1, 0.75)
	checkers:SetPoint("CENTER", colorSwatch)
	checkers:Show()

	self.Text:SetText(text);
end
function K_SHARED_UI.ColorWidget_OnClick(self)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION, "Master")
	if (not OpacitySliderFrame) then
		-- Removed OpacitySliderFrame, Since Dragonflight (10)
		ColorWidget_ShowColorPicker(ColorWidget_ColorPickedCallback, ColorWidget_ColorCancelledCallback, self);
	else
		ColorWidget_ShowColorPicker_Classic(ColorWidget_ColorPickedCallback_Classic, ColorWidget_ColorCancelledCallback_Classic, self);
	end
end


function K_SHARED_UI.ColorWidget_OnEnter(self)
	if (not self:IsEnabled()) then return end;
	local text = self:GetAttribute("text") or self:GetAttribute("title") or "";
	local tooltip = self:GetAttribute("tooltip") or "";
	showTooltip(self, text, tooltip, "ANCHOR_RIGHT")
end
function K_SHARED_UI.ColorWidget_OnLeave(self)
	GameTooltip:Hide();
end
-- #endregion Color Widget

-- #region Slider Widget
--[[
! Slider Widget
]]
local function SliderWidget_SetValue (self, value)
	self:SetDisplayValue(value);
	self._Value = value;
end

local function toDecimal(number, decimals)
	if tonumber(number) == nil or tonumber(decimals) == nil then
		return number
	end
    return tonumber(format("%."..decimals.."f", number))
end
local function SliderWidget_GetValue(self)
	local decimals = tonumber(self:GetAttribute("decimals")) or nil;
	if decimals then
		return toDecimal(self._Value, decimals)
	end
	return self._Value;
end

local function SliderWidget_GetLabel(self)
	return self.Label:GetText()
end
local function SliderWidget_SetLabel(self, value)
	self.Label:SetText(value)
end
function K_SHARED_UI.SliderWidget_OnLoad (self)
	self._isLoaded = false
	self.type = CONTROLTYPE_SLIDER;
	--? Since Shadowlands (9)
	if (BackdropTemplateMixin) then
		BackdropTemplateMixin.OnBackdropLoaded(self);
	end

	local text = self:GetAttribute("text") or "";
	text = l(text) or _G[text] or text;

	self._Value = 0;

	self.SetDisplayValue = self.SetValue;
	self.GetExactValue = self.GetValue;
	self.SetValue = SliderWidget_SetValue
	self.GetValue = SliderWidget_GetValue
	self.GetLabel = SliderWidget_GetLabel
	self.SetLabel = SliderWidget_SetLabel
	self.Text:SetFontObject("OptionsFontSmall");
	self.Text:SetText(text);
	self.High:Hide();

	self.Label = self.Low;
	self.Label:ClearAllPoints();
	self.Label:SetPoint("LEFT", self, "RIGHT", 3.5, 1);
	C_Timer.After(1, function()
		self._isLoaded = true
	end)
end
function K_SHARED_UI.SliderWidget_OnValueChanged(self, value)
	local format = self:GetAttribute("format") or nil;
	format = l(format) or _G[format] or format;
	self.Label =self.Low;
	local formatRatio = self:GetAttribute("formatRatio") or 1;
	if format ~= nil then
		self.Label:SetFormattedText(format, value * tonumber(formatRatio));
	else
		self.Label:SetText(value * tonumber(formatRatio));
	end
	local default = self:GetAttribute("default") or nil;
	default = l(default) or _G[default] or default;
	if tostring(value) == tostring(default) then
		self.Label:SetText(l("DEFAULT")..self.Label:GetText().."|r")
	end
	self:SetValue(value);

	if not self._isLoaded then
		return
	end
	local onEventScript = self:GetScript("OnEvent")
	if onEventScript then
		onEventScript(self, "change")
	end
end
function K_SHARED_UI.SliderWidget_OnEnter(self,...)
	if (not self:IsEnabled()) then return end;
	local text = self:GetAttribute("text") or self:GetAttribute("title") or ""
	local tooltip = self:GetAttribute("tooltip") or ""
	showTooltip(self, text, tooltip, "ANCHOR_TOP")
end
function K_SHARED_UI.SliderWidget_OnLeave(self)
	GameTooltip:Hide();
end
-- #endregion Slider Widget

-- #region DropDown Widget
--[[
! DropDown Widget
Main attributes: text, tooltip, width, justify
Items attributes: text1, value1, color1, ...
* Warning: name has to be set if you want to enable/disable widget
]]
local function DropDownWidget_OnSelect(dropdown, value, text)
	local onEventScript = dropdown:GetScript("OnEvent")
	if onEventScript then
		onEventScript(dropdown, "select")
	end
end
local function DropDownWidget_Func(self, b)
	local val, txt = b.menuList, b.value
	UIDropDownMenu_SetSelectedValue(self, val, txt)
	UIDropDownMenu_SetText(self, txt)
	b.checked = true
	DropDownWidget_OnSelect(self, val, txt)
end

local function DropDownWidget_Initialize(self, level, _)
	local info = UIDropDownMenu_CreateInfo()
	local i = 0
	local autoWidth	= 0;
	local curValue = self:GetValue()
	local localFunc = function(b) DropDownWidget_Func(self, b) end
	while(i == 0 or self:GetAttribute("text"..i))
	do
		local tooltip = self:GetAttribute("text")
		local val, txt, color
		if i == 0 then
			val, txt, color = nil, tooltip, nil
		else
			val, txt, color = self:GetAttribute("value"..i), self:GetAttribute("text"..i), self:GetAttribute("color"..i)
		end
		txt = l(txt) or _G[txt] or txt;
		tooltip = l(tooltip) or _G[tooltip] or tooltip;
		color = l(color) or _G[color] or color;

		info.isTitle = not val;
		info.notCheckable = not val;
		info.disabled = self:GetAttribute("disabled"..i) == "true";
		info.text = txt;
		info.checked = (val == curValue)
		info.menuList= val
		info.hasArrow = false
		info.tooltipTitle = tooltip;
		info.tooltipText = txt;
		info.colorCode = color;
		info.justifyH = self:GetAttribute("justify") or "RIGHT";
		info.func = localFunc;
		UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL);

		-- autodetect dropdown option width
		self.dd_title:SetText(txt);
		local textWidth = self.dd_title:GetStringWidth() + 20;
		autoWidth = math.max(autoWidth, textWidth);
		i=i+1;
	end
	local txt = self:GetAttribute("text")
	txt = l(txt) or _G[txt] or txt;
	self.dd_title:SetText(txt);
	UIDropDownMenu_SetWidth(self, self:GetAttribute("width") or autoWidth);
	UIDropDownMenu_JustifyText(self, self:GetAttribute("justify") or "RIGHT")
end
local function DropDownWidget_SetValue(self, value)
	local i = 1
	while(self:GetAttribute("text"..i))
	do
		local key, val = self:GetAttribute("value"..i), self:GetAttribute("text"..i);
		val = l(val) or _G[val] or val;
		if (key == value) then
			UIDropDownMenu_SetSelectedValue(self, key);
			UIDropDownMenu_SetText(self, val);
			return;
		end
		i=i+1;
	end
end
local function DropDownWidget_GetValue(self, value)
	return UIDropDownMenu_GetSelectedValue(self);
end
local function DropDownWidget_Disable(self)
	if (not self:GetName()) then
		ns.AddMsgErr("Dropdown with no name, can't disable: "..(self:GetAttribute("text") or ""), true);
	end;
	UIDropDownMenu_DisableDropDown(self)
end
local function DropDownWidget_Enable(self)
	if (not self:GetName()) then
		ns.AddMsgErr("Dropdown with no name, can't enable: "..(self:GetAttribute("text") or ""), true);
	end;
	UIDropDownMenu_EnableDropDown(self)
end
function K_SHARED_UI.DropDownWidget_OnLoad(self)
	self.type = "dropdown";
	self.Disable = DropDownWidget_Disable;
	self.Enable = DropDownWidget_Enable;
	self.SetValue = DropDownWidget_SetValue;
	self.GetValue = DropDownWidget_GetValue;
    self.dd_title = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.dd_title:SetPoint("TOPLEFT", 20, 15)
	UIDropDownMenu_Initialize(self, DropDownWidget_Initialize);
end

function K_SHARED_UI.DropDownWidget_OnEnter(self)
	if self.isDisabled then
		return;
	end
	showTooltip(self, self:GetAttribute("text"), self:GetAttribute("tooltip"), "ANCHOR_TOPLEFT")
end

function K_SHARED_UI.DropDownWidget_OnLeave(self)
	GameTooltip:Hide();
end
-- #endregion DropDown Widget

