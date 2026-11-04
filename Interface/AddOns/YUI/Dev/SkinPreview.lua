local YUI = _G.YUI
if not YUI then return end
YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev
local Gallery = { shadow = true, capture = false }
local Showcase = {}
Gallery.showcase = Showcase
Dev.SkinPreview = Gallery

local WIDTH, STAGE_WIDTH, COLUMNS = 680, 640, 4
local CELL_WIDTH, CELL_HEIGHT, COLUMN_STEP, ROW_STEP, ICON_SIZE = 144, 104, 156, 112, 64
local ICONS = { 135808, 4667417 }
local SHAPE_BORDERS = { "thin", "thick", "contour", "shade" }

local function L(key) return YUI.Locale:Get("Core")[key] end
local function Print(key)
    if YUI.Print then YUI:Print(L("dev.skins." .. key)) else print(L("dev.skins." .. key)) end
end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

function Gallery:Close()
    Showcase:Close()
    if self.frame then self.frame:Hide() end
    if YUI.Event then YUI.Event:OffOwner(self) end
end

local function CloseForCombat() Gallery:Close() end

function Gallery:RefreshShadows()
    local gui = YUI.GUI2
    for _, sample in ipairs(self.samples or {}) do
        local width, height = gui:GetIconAppearanceSize(ICON_SIZE, sample.shape)
        gui:ApplyShapeShadow(sample.shadow, { enabled = self.shadow, shape = sample.shape,
            color = sample.shadowColor }, { anchor = sample, width = width, height = height, allowLayout = true })
    end
    if self.shadowControl then self.shadowControl:SetChecked(self.shadow, true) end
end

function Gallery:SetShadow(enabled)
    enabled = enabled == true
    if self.shadow == enabled then return end
    self.shadow = enabled
    self:RefreshShadows()
end

function Gallery:Fit()
    self.frame:SetScale(math.min(1, (UIParent:GetWidth() - 32) / WIDTH,
        (UIParent:GetHeight() - 32) / self.height))
end

function Gallery:SetCapture(enabled)
    self.capture = enabled == true
    if not self.frame then return end
    self.chrome:SetShown(not self.capture)
    self.stage:ClearAllPoints()
    self.stage:SetPoint("TOPLEFT", 20, self.capture and -20 or -112)
    self.height = self.stageHeight + (self.capture and 40 or 132)
    self.frame:SetHeight(self.height)
    self:Fit()
end

function Gallery:CreateSample(definition, border, label, index, top, count, icon)
    local gui = YUI.GUI2
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    local rowCount = math.min(COLUMNS, count - row * COLUMNS)
    local card = gui:CreatePanel(self.stage, { width = CELL_WIDTH, height = CELL_HEIGHT,
        surface = "color.surface.raised", border = false })
    card:SetPoint("TOPLEFT", 14 + column * COLUMN_STEP + (COLUMNS - rowCount) * COLUMN_STEP / 2,
        -top - row * ROW_STEP)
    local snapshot = gui:CompileIconStyle({ shape = definition.shape, border = border,
        zoom = definition.zoom, borderColor = definition.borderColor })
    local sample = gui:CreateIconSlot(card, { size = ICON_SIZE, icon = icon or ICONS[1],
        shape = snapshot.shape, border = snapshot.border, variant = "bare" })
    sample:EnableMouse(false)
    sample:SetPoint("CENTER", card, "TOP", 0, -43)
    sample:SetIconAppearance({ size = ICON_SIZE, shape = snapshot.shape,
        border = snapshot.border, zoom = snapshot.zoom })
    sample:SetIconBorderColor(snapshot.borderColor)
    sample.shape, sample.border, sample.snapshot = snapshot.shape, snapshot.border, snapshot
    sample.shadowColor = definition.shadowColor
    sample.shadow = gui:CreateShapeShadow(sample)
    local caption = gui:CreateText(card, label, "font.size.md", "color.text.primary")
    caption:SetPoint("BOTTOMLEFT", 4, 6)
    caption:SetPoint("BOTTOMRIGHT", -4, 6)
    caption:SetJustifyH("CENTER")
    caption:SetWordWrap(false)
    self.samples[#self.samples + 1] = sample
end

function Gallery:Create()
    if self.frame then return self.frame end
    local gui, shapes = YUI.GUI2, {}
    local skins = gui.IconSkins
    for _, id in ipairs(skins.order) do
        local definition = skins.definitions[id]
        if definition and definition.shape then shapes[#shapes + 1] = { id = id, definition = definition } end
    end
    local borders
    for _, parameter in ipairs(skins:GetParameters("minimal-rounded")) do
        if parameter.key == "border" then borders = parameter.choices; break end
    end
    local borderTop = 52 + math.ceil(#shapes / COLUMNS) * ROW_STEP + 34
    self.stageHeight = borderTop + math.ceil(#borders / COLUMNS) * ROW_STEP + 6
    self.height = self.stageHeight + 132
    local frame = gui:CreatePanel(UIParent, { name = "YUI_DevSkinPreview", width = WIDTH, height = self.height,
        surface = "color.control.bg", border = "color.border.strong", shadow = true })
    frame:Hide()
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        for _, sample in ipairs(Gallery.samples or {}) do gui:HideShapeShadow(sample.shadow) end
        if YUI.Event then YUI.Event:OffOwner(Gallery) end
    end)
    self.frame, self.samples = frame, {}
    if UISpecialFrames then table.insert(UISpecialFrames, "YUI_DevSkinPreview") end
    self.chrome = gui:CreatePanel(frame, { width = STAGE_WIDTH, height = 94,
        surface = "color.control.bg", border = false })
    self.chrome:SetPoint("TOPLEFT", 20, -12)
    local title = gui:CreateText(self.chrome, L("dev.skins.title"), "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", 0, -4)
    local note = gui:CreateText(self.chrome, L("dev.skins.note"), "font.size.sm", "color.text.secondary")
    note:SetPoint("TOPLEFT", 0, -34)
    local close = gui:CreateCloseButton(self.chrome, function() Gallery:Close() end)
    close:SetPoint("TOPRIGHT", 0, -2)
    self.shadowControl = gui.Form:CreateCheckbox(self.chrome, { width = 180, height = 28,
        text = L("icon_skin.parameter.shadow"), default = self.shadow,
        onChange = function(_, value) Gallery:SetShadow(value) end })
    self.shadowControl:SetPoint("TOPLEFT", 0, -62)
    local capture = gui.Form:CreateButton(self.chrome, { width = 144, height = 28,
        text = L("dev.skins.capture"), onClick = function() Gallery:SetCapture(true); Print("captureHint") end })
    capture:SetPoint("TOPRIGHT", 0, -62)
    self.stage = gui:CreatePanel(frame, { width = STAGE_WIDTH, height = self.stageHeight,
        surface = "color.control.bg", border = false })
    local shapeTitle = gui:CreateText(self.stage, string.format(L("dev.skins.shapes"), #shapes),
        "font.size.lg", "color.text.heading")
    shapeTitle:SetPoint("TOPLEFT", 14, -16)
    local borderTitle = gui:CreateText(self.stage, string.format(L("dev.skins.borders"), #borders),
        "font.size.lg", "color.text.heading")
    borderTitle:SetPoint("TOPLEFT", 14, -borderTop + 34)
    for index, shape in ipairs(shapes) do
        local border = SHAPE_BORDERS[math.floor((index - 1) / 2) % #SHAPE_BORDERS + 1]
        self:CreateSample(shape.definition, border, L("icon_skin." .. shape.id), index, 52, #shapes,
            ICONS[(index - 1) % #ICONS + 1])
    end
    for index, border in ipairs(borders) do
        self:CreateSample(skins.definitions["minimal-rounded"], border,
            L("icon_skin.value." .. border), index, borderTop, #borders)
    end
    self:SetCapture(self.capture)
    return frame
end

function Gallery:Open(capture)
    if InCombat() then Print("combat"); return end
    local gui = YUI.GUI2
    if not (gui and gui.Form and gui.IconSkins and gui.CreateIconSlot and gui.CreateShapeShadow) then
        Print("notLoaded"); return
    end
    Showcase:Close()
    local frame = self:Create()
    self:SetCapture(capture)
    self:RefreshShadows()
    frame:Show()
    if YUI.Event then
        YUI.Event:OffOwner(self)
        YUI.Event:On("PLAYER_REGEN_DISABLED", CloseForCombat, self)
    end
end

local GRID_LEFT, GRID_TOP, GRID_STEP_X, GRID_STEP_Y = 180, 140, 116, 80
local LEAD_IN, STAGGER, REVEAL_TIME = 0.65, 0.06, 0.20

function Showcase:Stop()
    if YUI.Animation then YUI.Animation:StopOwner(self, false) end
    self.playing = false
end

function Showcase:Close()
    self:Stop()
    if self.frame then self.frame:Hide() end
    if YUI.Event then YUI.Event:OffOwner(self) end
end

function Showcase:Create()
    if self.frame then return self.frame end
    local gui, shapes, borders = YUI.GUI2, {}, nil
    local skins = gui.IconSkins
    for _, id in ipairs(skins.order) do
        local definition = skins.definitions[id]
        if definition and definition.shape then shapes[#shapes + 1] = id end
    end
    for _, parameter in ipairs(skins:GetParameters(skins.defaultId)) do
        if parameter.key == "border" then borders = parameter.choices; break end
    end
    if #shapes == 0 or not borders or #borders == 0 then return end
    self.total, self.samples, self.rowLabels = #shapes * #borders, {}, {}
    self.width, self.height = GRID_LEFT + #borders * GRID_STEP_X + 24, GRID_TOP + #shapes * GRID_STEP_Y + 24
    local frame = gui:CreatePanel(UIParent, { name = "YUI_DevSkinShowcase", width = self.width, height = self.height,
        surface = "color.control.bg", border = "color.border.strong", shadow = true })
    frame:Hide()
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        Showcase:Stop()
        for _, sample in ipairs(Showcase.samples) do gui:HideShapeShadow(sample.shadow) end
        if YUI.Event then YUI.Event:OffOwner(Showcase) end
    end)
    self.frame = frame
    if UISpecialFrames then table.insert(UISpecialFrames, "YUI_DevSkinShowcase") end
    local title = gui:CreateText(frame, string.format(L("dev.skins.showcaseTitle"), self.total),
        "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", 32, -24)
    local formula = gui:CreateText(frame, string.format(L("dev.skins.showcaseFormula"), #shapes, #borders),
        "font.size.md", "color.text.secondary")
    formula:SetPoint("TOPLEFT", 32, -62)
    self.counter = gui:CreateText(frame, "", "font.size.title", "color.text.heading")
    self.counter:SetPoint("TOPRIGHT", -32, -24)
    for column, border in ipairs(borders) do
        local label = gui:CreateText(frame, L("icon_skin.value." .. border), "font.size.md", "color.text.primary")
        label:SetPoint("CENTER", frame, "TOPLEFT", GRID_LEFT + (column - 0.5) * GRID_STEP_X, -112)
    end
    for row, id in ipairs(shapes) do
        local label = gui:CreateText(frame, L("icon_skin." .. id), "font.size.md", "color.text.primary")
        label:SetPoint("RIGHT", frame, "TOPLEFT", GRID_LEFT - 24, -GRID_TOP - (row - 0.5) * GRID_STEP_Y)
        self.rowLabels[row] = label
        for column, border in ipairs(borders) do
            -- Resolve the actual shared recipe; the showcase owns no product configuration.
            local recipe = skins:Resolve({ skinId = id, skinOptions = { [id] = { border = border } } }, "Halo")
            local snapshot = gui:CompileIconStyle(recipe)
            local cell = gui:CreateFrame(frame, { width = GRID_STEP_X, height = GRID_STEP_Y, mouse = false })
            cell:SetPoint("TOPLEFT", GRID_LEFT + (column - 1) * GRID_STEP_X, -GRID_TOP - (row - 1) * GRID_STEP_Y)
            local sample = gui:CreateIconSlot(cell, { size = ICON_SIZE, icon = ICONS[1],
                shape = snapshot.shape, border = snapshot.border, variant = "bare" })
            sample:EnableMouse(false)
            sample:SetPoint("CENTER", cell, "CENTER")
            sample:SetIconAppearance({ size = ICON_SIZE, shape = snapshot.shape, border = snapshot.border, zoom = snapshot.zoom })
            sample:SetIconBorderColor(snapshot.borderColor)
            sample.shape, sample.border, sample.snapshot = snapshot.shape, border, snapshot
            sample.row, sample.shadowColor = row, recipe.shadowColor
            sample.shadow = gui:CreateShapeShadow(sample)
            self.samples[#self.samples + 1] = sample
        end
    end
    return frame
end

function Showcase:Advance(elapsed)
    local revealed = self.revealed
    -- At most a few samples enter together; completed samples receive no further writes.
    for index = self.finished + 1, self.total do
        local age = elapsed - LEAD_IN - (index - 1) * STAGGER
        if age < 0 then break end
        local sample = self.samples[index]
        if index > revealed then
            sample:Show()
            self.rowLabels[sample.row]:Show()
            revealed = index
        end
        local progress = math.min(1, age / REVEAL_TIME)
        sample:SetAlpha(progress)
        sample:SetScale(0.84 + 0.16 * (1 - (1 - progress) ^ 3))
        if progress == 1 then self.finished = index end
    end
    if revealed ~= self.revealed then
        self.revealed = revealed
        self.counter:SetText(string.format(L("dev.skins.showcaseProgress"), revealed, self.total))
    end
end

local function CloseShowcaseForCombat() Showcase:Close() end
local function AdvanceShowcase(value) Showcase:Advance(value) end
local function FinishShowcase(_, _, finished)
    if finished then Showcase:Advance(Showcase.duration + 1) end
    Showcase.playing = false
end

function Showcase:Open(all)
    if InCombat() then Print("combat"); return end
    local gui, animation = YUI.GUI2, YUI.Animation
    if not (gui and gui.IconSkins and gui.CreateIconSlot and gui.CreateShapeShadow and animation) then
        Print("notLoaded"); return
    end
    Gallery:Close()
    local frame = self:Create()
    if not frame then Print("notLoaded"); return end
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 32) / self.width, (UIParent:GetHeight() - 32) / self.height))
    self.revealed, self.finished = 0, 0
    self.counter:SetText(string.format(L("dev.skins.showcaseProgress"), 0, self.total))
    for _, label in ipairs(self.rowLabels) do label:Hide() end
    for _, sample in ipairs(self.samples) do
        sample:Hide()
        sample:SetAlpha(0)
        sample:SetScale(1)
        local width, height = gui:GetIconAppearanceSize(ICON_SIZE, sample.shape)
        gui:ApplyShapeShadow(sample.shadow, { enabled = true, shape = sample.shape, color = sample.shadowColor },
            { anchor = sample, width = width, height = height, allowLayout = true })
    end
    frame:Show()
    if YUI.Event then YUI.Event:On("PLAYER_REGEN_DISABLED", CloseShowcaseForCombat, self) end
    self.duration = LEAD_IN + (self.total - 1) * STAGGER + REVEAL_TIME
    if all then self:Advance(self.duration + 1); return end
    self.playing = true
    animation:Tween({ target = frame, owner = self, key = "skins56", from = 0, to = self.duration,
        duration = self.duration, easing = "linear", onUpdate = AdvanceShowcase, onFinished = FinishShowcase })
end

function Dev:HandleSkinPreview(args)
    local text = tostring(args or ""):match("^%s*(.-)%s*$"):lower()
    local command, action = text:match("^(%S+)%s*(.-)$")
    if command == "skins56" then
        if action == "" or action == "play" or action == "replay" then Showcase:Open(false)
        elseif action == "all" then Showcase:Open(true)
        elseif action == "off" then Showcase:Close()
        else Print("showcaseUsage") end
        return true
    end
    if command ~= "skins" then return false end
    if action == "" or action == "on" then Gallery:Open(false)
    elseif action == "off" then Gallery:Close()
    elseif action == "capture" then Gallery:Open(true)
    elseif action == "shadow on" or action == "shadow off" then
        if InCombat() then Print("combat"); return true end
        Gallery:SetShadow(action == "shadow on")
        Gallery:Open(Gallery.capture)
    else Print("usage") end
    return true
end
