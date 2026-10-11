local _, YUI = ...
if not YUI or not YUI.IsWrath then return end

local Components = YUI.Components
local GUI2 = YUI.GUI2
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}

if not Components then return end

local FRAME_WIDTH = 1216
local FRAME_HEIGHT = 735
local TREE_CONTENT_SCALE = 0.79
local TREE_CONTENT_WIDTH = 384
local TREE_CONTENT_HEIGHT = 720
local TREE_FRAME_WIDTH = TREE_CONTENT_WIDTH * TREE_CONTENT_SCALE
local TREE_FRAME_HEIGHT = 642
-- local TREE_BACKGROUND_WIDTH = 496
-- local TREE_BACKGROUND_HEIGHT = 930
local TREE_BACKGROUND_WIDTH = 400
local TREE_BACKGROUND_HEIGHT = 1030
-- local TREE_BACKGROUND_OFFSET_X = -32
local TREE_BACKGROUND_OFFSET_X = -10
local TREE_BACKGROUND_OFFSET_Y = 0
local TREE_BACKGROUND_ALPHA = 0.5
local TREE_BACKGROUND_RIGHT_VISIBLE_RATIO = 0.6875
local TREE_BACKGROUND_BOTTOM_VISIBLE_RATIO = 0.5859375
local TREE_BACKGROUND_SOURCE_WIDTH = 300
local TREE_BACKGROUND_SOURCE_HEIGHT = 331
local TREE_BACKGROUND_SOURCE_LEFT_WIDTH = 256
local TREE_BACKGROUND_SOURCE_RIGHT_WIDTH = 44
local TREE_BACKGROUND_SOURCE_TOP_HEIGHT = 256
local TREE_BACKGROUND_SOURCE_BOTTOM_HEIGHT = 75
local TREE_BACKGROUND_COVER_ALPHA_MULTIPLIER = 0.76
local TREE_TOP = -92
local TREE_LEFT = 40
local TREE_GAP = 10
local GLYPH_COLUMN_WIDTH = 218
local GLYPH_ROW_HEIGHT = 76
local GLYPH_TYPE_MAJOR = _G.GLYPHTYPE_MAJOR or 1
local GLYPH_TYPE_MINOR = _G.GLYPHTYPE_MINOR or 2
local NUM_GLYPH_SLOTS_FALLBACK = 6
local GLYPH_MAJOR_SLOTS = { 1, 4, 6 }
local GLYPH_MINOR_SLOTS = { 2, 3, 5 }
local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local RANK_FONT = "Interface\\AddOns\\YUI\\Media\\Bundles\\sharedmedia-fonts\\YUI Inter Black.ttf"
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local TREE_TITLE_ACTIVE_COLOR = "|cffffd100"
local TREE_TITLE_EMPTY_COLOR = "|cffffffff"
local COLOR_RESET = "|r"
local TOP_BUTTON_Y = -26
local TOP_BUTTON_HEIGHT = 25
local TOP_BUTTON_GAP = 8
local SPEC_SWITCHER_BOTTOM_Y = 2
local SPEC_SWITCHER_RIGHT_X = 0
local SPEC_SWITCHER_ITEM_WIDTH = 122
local SPEC_SWITCHER_ITEM_HEIGHT = 28
local SPEC_SWITCHER_ITEM_GAP = 2
local VISIBLE_FRAME_RIGHT_INSET = 8
local ACTIVATION_CONTROL_RIGHT_X = -(VISIBLE_FRAME_RIGHT_INSET + SPEC_SWITCHER_ITEM_WIDTH + SPEC_SWITCHER_ITEM_GAP)
local ACTIVATION_CONTROL_Y = TOP_BUTTON_Y

local isEnabled = false
local initialized = false
local hooksInstalled = false
local glyphHooksInstalled = false
local refreshScheduled = false
local nativeHookActive = false
local glyphClickActive = false
local treeFrames = {}
local glyphSummary
local topControls
local contentFrame
local specSwitcher
local activationCastEventFrame
local HideBlizzardTalentUI
local InstallGlyphHooks
local ScheduleRefresh

local HIDDEN_BLIZZARD_FRAMES = {
    "PlayerTalentFramePortrait",
    "PlayerTalentFrameTopLeft",
    "PlayerTalentFrameTopRight",
    "PlayerTalentFrameBottomLeft",
    "PlayerTalentFrameBottomRight",
    "PlayerTalentFrameTitleText",
    "PlayerTalentFrameCancelButton",
    "PlayerTalentFrameStatusFrame",
    "PlayerTalentFramePointsBar",
    "PlayerTalentFrameTalentPointsText",
    "PlayerTalentFramePreviewBar",
    "PlayerTalentFramePreviewBarFiller",
    "PlayerTalentFramePreviewBarButtonBorder",
    "PlayerTalentFramePreviewBarFillerButtonBackgroundLeft",
    "PlayerTalentFramePreviewBarFillerButtonBackgroundMiddle",
    "PlayerTalentFramePreviewBarFillerButtonBackgroundRight",
    "PlayerTalentFrameLearnButton",
    "PlayerTalentFrameResetButton",
    "PlayerTalentFrameScrollFrame",
    "PlayerTalentFrameScrollFrameBackgroundTop",
    "PlayerTalentFrameScrollFrameBackgroundBottom",
    "PlayerTalentFrameBackgroundTopLeft",
    "PlayerTalentFrameBackgroundTopRight",
    "PlayerTalentFrameBackgroundBottomLeft",
    "PlayerTalentFrameBackgroundBottomRight",
    "PlayerTalentFrameActiveTalentGroupFrame",
    "PlayerTalentFrameScrollButtonOverlay",
    "PlayerTalentFrame_backdrop",
    "PlayerTalentFrameBackdrop",
    "PlayerTalentFrame_Backdrop",
    "GlyphFrame",
    "GlyphFrameBackground",
    "GlyphFrameTitleText",
}

local BACKDROP_REGION_KEYS = {
    "Center",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "TopLeftCorner",
    "TopRightCorner",
    "BottomLeftCorner",
    "BottomRightCorner",
}

local function T(key)
    return LC[key] or key
end

local function GetConflictAddon(options)
    local external = YUI.API and YUI.API.External
    if type(external) ~= "table" or type(external.ResolveCapability) ~= "function" then return nil, "unknown" end
    local ok, snapshot = pcall(external.ResolveCapability, external, "ui.talent.controller", options)
    if not ok or type(snapshot) ~= "table" then return nil, "unknown" end
    if snapshot.status == "active" then return snapshot.controller, "active" end
    if snapshot.status == "unknown" then return nil, "unknown" end
    return nil, "inactive"
end

local function IsEffective()
    local _, status = GetConflictAddon()
    return isEnabled and status == "inactive"
end

local function SafeHook(functionName, handler)
    if type(hooksecurefunc) ~= "function" or type(_G[functionName]) ~= "function" then
        return
    end
    hooksecurefunc(functionName, handler)
end

local function CreateNativeFrame(frameType, name, parent, template)
    if template then
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then
            return frame
        end
    end
    return CreateFrame(frameType, name, parent)
end

local function CreateText(parent, text, sizeKey, colorKey, justifyH)
    if GUI2 and type(GUI2.CreateText) == "function" then
        return GUI2:CreateText(parent, text, sizeKey, colorKey, justifyH)
    end

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text or "")
    fs:SetJustifyH(justifyH or "LEFT")
    return fs
end

local function CreateTemplateTexture(parent, name, layer, template, fallbackTexture)
    local texture
    if template then
        local ok, created = pcall(parent.CreateTexture, parent, name, layer, template)
        if ok then
            texture = created
        end
    end
    texture = texture or parent:CreateTexture(name, layer)
    if fallbackTexture then
        texture:SetTexture(fallbackTexture)
    end
    return texture
end

local function SetSolidTexture(texture, r, g, b, a)
    if not texture then
        return
    end

    if type(texture.SetColorTexture) == "function" then
        texture:SetColorTexture(r, g, b, a)
    else
        texture:SetTexture(SOLID_TEXTURE)
        texture:SetVertexColor(r, g, b, a)
    end
end

local function SetBackdropColor(frame, color)
    if not frame or not color or type(frame.SetBackdropColor) ~= "function" then
        return
    end
    frame:SetBackdropColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
end

local function SetTextColor(text, color)
    if not text or not color or type(text.SetTextColor) ~= "function" then
        return
    end
    text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function GetFirstTreeVisualLeft()
    return TREE_LEFT + ((TREE_BACKGROUND_OFFSET_X or 0) * TREE_CONTENT_SCALE)
end

local function GetRightControlsAnchorX()
    return -98
end

local function SetShown(frame, shown)
    if not frame then
        return
    end
    if shown then
        frame:Show()
    else
        frame:Hide()
    end
end

local function SetNamedShown(name, shown)
    SetShown(_G[name], shown)
end

local function SuppressFrameVisuals(frame)
    if not frame then
        return
    end

    if type(frame.SetAlpha) == "function" then
        frame:SetAlpha(0)
    end
    if type(frame.EnableMouse) == "function" then
        frame:EnableMouse(false)
    end
    if type(frame.SetMouseClickEnabled) == "function" then
        frame:SetMouseClickEnabled(false)
    end
end

local function SuppressFrame(frame)
    if not frame then
        return
    end

    SuppressFrameVisuals(frame)
    if type(frame.Hide) == "function" then
        frame:Hide()
    end
end

local function RestoreFrame(frame, enableMouse)
    if not frame then
        return
    end

    if type(frame.SetAlpha) == "function" then
        frame:SetAlpha(1)
    end
    if enableMouse ~= false and type(frame.EnableMouse) == "function" then
        frame:EnableMouse(true)
    end
    if enableMouse ~= false and type(frame.SetMouseClickEnabled) == "function" then
        frame:SetMouseClickEnabled(true)
    end
end

local function HideBackdropLayer(frame)
    if not frame then
        return
    end

    SuppressFrame(frame)
    for _, key in ipairs(BACKDROP_REGION_KEYS) do
        local region = frame[key]
        if region then
            if type(region.Hide) == "function" then
                region:Hide()
            end
            if type(region.SetAlpha) == "function" then
                region:SetAlpha(0)
            end
        end
    end
end

local function HideLegacyBackdrops()
    if not PlayerTalentFrame then
        return
    end

    HideBackdropLayer(PlayerTalentFrame.yuiTalentEnhancementBackdrop)
    PlayerTalentFrame.yuiTalentEnhancementBackdrop = nil

    HideBackdropLayer(PlayerTalentFrame.backdrop)
    HideBackdropLayer(_G.PlayerTalentFrame_backdrop)
    HideBackdropLayer(_G.PlayerTalentFrameBackdrop)
    HideBackdropLayer(_G.PlayerTalentFrame_Backdrop)
end

local function ShouldHideBlizzardUI()
    return IsEffective() and initialized and PlayerTalentFrame
end

local function InstallHideProtection(frame)
    if not frame or frame.yuiTalentEnhancementHideProtected or type(frame.HookScript) ~= "function" then
        return
    end

    frame:HookScript("OnShow", function(self)
        if ShouldHideBlizzardUI() then
            SuppressFrameVisuals(self)
        end
    end)
    frame.yuiTalentEnhancementHideProtected = true
end

local function InstallHideProtections()
    for _, name in ipairs(HIDDEN_BLIZZARD_FRAMES) do
        InstallHideProtection(_G[name])
    end
    if PlayerTalentFrame then
        InstallHideProtection(PlayerTalentFrame.backdrop)
        InstallHideProtection(PlayerTalentFrame.yuiTalentEnhancementBackdrop)
    end
end

local function EnsureContentFrame()
    if not PlayerTalentFrame then
        return nil
    end

    if not contentFrame then
        contentFrame = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementContent", PlayerTalentFrame)
        contentFrame:SetAllPoints(PlayerTalentFrame)
    end

    contentFrame:SetFrameLevel(PlayerTalentFrame:GetFrameLevel() + 10)
    contentFrame:Show()
    return contentFrame
end

local function SetFrameBorderColor(frame, colorKey, r, g, b, a)
    if not frame then
        return
    end

    if GUI2 and type(GUI2.SetBorderColor) == "function" and frame.gui2Borders then
        GUI2:SetBorderColor(frame, colorKey, r, g, b, a)
        return
    end

    local borders = frame.yuiTalentBorders
    if not borders then
        return
    end

    local red, green, blue, alpha = r or 0.45, g or 0.48, b or 0.52, a or 0.9
    if colorKey == "color.border.accent" then
        red, green, blue, alpha = 0.96, 0.74, 0.28, 0.95
    elseif colorKey == "color.border.focus" then
        red, green, blue, alpha = 0.55, 0.78, 1, 1
    elseif colorKey == "color.border.subtle" then
        red, green, blue, alpha = 0.22, 0.24, 0.28, 0.75
    elseif colorKey == "color.border.default" then
        red, green, blue, alpha = 0.42, 0.46, 0.52, 0.9
    end

    for _, texture in ipairs(borders) do
        SetSolidTexture(texture, red, green, blue, alpha)
    end
end

local function CreateSimpleBorder(frame, colorKey)
    if not frame or frame.yuiTalentBorderReady then
        return
    end

    if GUI2 and type(GUI2.CreateBorder) == "function" then
        GUI2:CreateBorder(frame, colorKey or "color.border.default")
    else
        local top = frame:CreateTexture(nil, "OVERLAY")
        top:SetPoint("TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", 0, 0)
        top:SetHeight(1)

        local bottom = frame:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)

        local left = frame:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", 0, 0)
        left:SetWidth(1)

        local right = frame:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)

        frame.yuiTalentBorders = { top, bottom, left, right }
    end

    frame.yuiTalentBorderReady = true
    SetFrameBorderColor(frame, colorKey or "color.border.default")
end

local function InitializeBranchArray(frame)
    if type(TalentFrame_Load) == "function" then
        TalentFrame_Load(frame)
        return
    end

    frame.TALENT_BRANCH_ARRAY = {}
    for tier = 1, MAX_NUM_TALENT_TIERS do
        frame.TALENT_BRANCH_ARRAY[tier] = {}
        for column = 1, NUM_TALENT_COLUMNS do
            frame.TALENT_BRANCH_ARRAY[tier][column] = {
                id = nil,
                up = 0,
                down = 0,
                left = 0,
                right = 0,
                leftArrow = 0,
                rightArrow = 0,
                topArrow = 0,
            }
        end
    end
end

local function GetPreviewEnabled()
    return type(GetCVarBool) == "function" and GetCVarBool("previewTalentsOption") == true
end

local function GetTreeBackgroundTargetSize()
    local rightWidth = math.max((TREE_BACKGROUND_WIDTH or 256) - 256, 0) * TREE_BACKGROUND_RIGHT_VISIBLE_RATIO
    local bottomHeight = math.max((TREE_BACKGROUND_HEIGHT or 256) - 256, 0) * TREE_BACKGROUND_BOTTOM_VISIBLE_RATIO
    return 256 + rightWidth, 256 + bottomHeight
end

local function GetTreeBackgroundCoverLayout()
    local targetWidth, targetHeight = GetTreeBackgroundTargetSize()
    local scale = math.max(targetWidth / TREE_BACKGROUND_SOURCE_WIDTH, targetHeight / TREE_BACKGROUND_SOURCE_HEIGHT)
    local sourceCropWidth = targetWidth / scale
    local sourceLeft = (TREE_BACKGROUND_SOURCE_WIDTH - sourceCropWidth) / 2
    local sourceRight = sourceLeft + sourceCropWidth

    return targetWidth, targetHeight, scale, sourceLeft, sourceRight
end

local function ConfigureBackgroundCoverPiece(texture, sourceLeft, sourceRight, pieceSourceLeft, pieceSourceWidth, pieceSourceHeight, texCoordRight, texCoordBottom, scale, offsetX, offsetY)
    local pieceSourceRight = pieceSourceLeft + pieceSourceWidth
    local visibleLeft = math.max(sourceLeft, pieceSourceLeft)
    local visibleRight = math.min(sourceRight, pieceSourceRight)
    if visibleRight <= visibleLeft then
        texture:Hide()
        return 0
    end

    local width = (visibleRight - visibleLeft) * scale
    local height = pieceSourceHeight * scale
    local texLeft = ((visibleLeft - pieceSourceLeft) / pieceSourceWidth) * texCoordRight
    local texRight = ((visibleRight - pieceSourceLeft) / pieceSourceWidth) * texCoordRight

    texture:ClearAllPoints()
    texture:SetSize(width, height)
    texture:SetPoint("TOPLEFT", offsetX, offsetY)
    texture:SetTexCoord(texLeft, texRight, 0, texCoordBottom)
    texture:SetAlpha(TREE_BACKGROUND_ALPHA * TREE_BACKGROUND_COVER_ALPHA_MULTIPLIER)
    texture:Show()

    return width
end

local function GetTalentEmuXCreateEmulator()
    if not IsAddonLoadedSafe("TalentEmuX") then
        return nil
    end

    local meta = _G.__ala_meta__
    local emu = meta and meta.emu
    local mt = emu and emu.MT
    if mt and type(mt.CreateEmulator) == "function" then
        return mt.CreateEmulator
    end
    return nil
end

local function HasTalentEmuXEntry()
    return GetTalentEmuXCreateEmulator() ~= nil
end

local function HideTalentEmuXNativeButton()
    if not PlayerTalentFrame then
        return
    end

    local button = PlayerTalentFrame.__TalentEmuCall
    if button then
        InstallHideProtection(button)
        SuppressFrame(button)
    end
end

local function ShowTalentEmuXNativeButton()
    if not PlayerTalentFrame then
        return
    end

    local button = PlayerTalentFrame.__TalentEmuCall
    if button then
        RestoreFrame(button, true)
        button:Show()
    end
end

local function GetPreviewPointsSpent()
    if not PlayerTalentFrame or type(GetGroupPreviewTalentPointsSpent) ~= "function" then
        return 0
    end
    return GetGroupPreviewTalentPointsSpent(PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup) or 0
end

local function GetUnspentPoints()
    if not PlayerTalentFrame or type(GetUnspentTalentPoints) ~= "function" then
        return 0
    end

    local points = GetUnspentTalentPoints(PlayerTalentFrame.inspect, PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup) or 0
    return points - GetPreviewPointsSpent()
end

local function TalentButton_OnClick(button, mouseButton)
    local frame = button.yuiTalentFrame
    local tabIndex = frame and frame.yuiTalentTab
    if not tabIndex or not PlayerTalentFrame then
        return
    end

    if IsModifiedClick("CHATLINK") and type(GetTalentLink) == "function" then
        local link = GetTalentLink(tabIndex, button:GetID(), PlayerTalentFrame.inspect, PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup, GetPreviewEnabled())
        if link and ChatFrameUtil and ChatFrameUtil.InsertLink then
            ChatFrameUtil.InsertLink(link)
        end
        return
    end

    local selectedSpec = TalentUIUtil and TalentUIUtil.GetSelectedSpec and TalentUIUtil.GetSelectedSpec()
    local activeSelected = TalentUIUtil and TalentUIUtil.IsActiveSpecSelected and TalentUIUtil.IsActiveSpecSelected()
    if selectedSpec and not (activeSelected or selectedSpec.pet) then
        return
    end

    if mouseButton == "LeftButton" then
        if GetPreviewEnabled() and type(AddPreviewTalentPoints) == "function" then
            AddPreviewTalentPoints(tabIndex, button:GetID(), 1, PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup)
        elseif type(LearnTalent) == "function" then
            LearnTalent(tabIndex, button:GetID(), PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup)
        end
    elseif mouseButton == "RightButton" and GetPreviewEnabled() and type(AddPreviewTalentPoints) == "function" then
        AddPreviewTalentPoints(tabIndex, button:GetID(), -1, PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup)
    end
end

local function GetTalentInfoForButton(button)
    local frame = button.yuiTalentFrame
    local tabIndex = frame and frame.yuiTalentTab
    if not tabIndex or not C_SpecializationInfo or type(C_SpecializationInfo.GetTalentInfo) ~= "function" then
        return nil
    end

    local query = {
        specializationIndex = tabIndex,
        talentIndex = button:GetID(),
        isInspect = PlayerTalentFrame and PlayerTalentFrame.inspect,
        isPet = PlayerTalentFrame and PlayerTalentFrame.pet,
        groupIndex = PlayerTalentFrame and PlayerTalentFrame.talentGroup,
    }
    local ok, talentInfo = pcall(C_SpecializationInfo.GetTalentInfo, query)
    if ok then
        return talentInfo
    end
    return nil
end

local function GetTalentRank(talentInfo)
    if not talentInfo then
        return 0
    end

    local preview = GetPreviewEnabled()
    return (preview and talentInfo.previewRank or talentInfo.rank) or 0
end

local function GetTalentPrereqState(talentInfo)
    if not talentInfo then
        return false
    end

    local preview = GetPreviewEnabled()
    if preview and talentInfo.meetsPreviewPrereq ~= nil then
        return talentInfo.meetsPreviewPrereq == true
    end
    if talentInfo.meetsPrereq ~= nil then
        return talentInfo.meetsPrereq == true
    end
    return true
end

local function IsSelectedTalentGroupEditable()
    if not PlayerTalentFrame or PlayerTalentFrame.inspect then
        return false
    end

    if PlayerTalentFrame.pet then
        return true
    end

    if TalentUIUtil and type(TalentUIUtil.IsActiveSpecSelected) == "function" then
        local ok, activeSelected = pcall(TalentUIUtil.IsActiveSpecSelected)
        if ok then
            return activeSelected == true
        end
    end

    return true
end

local function IsTalentTierUnlocked(button, talentInfo)
    local tier = talentInfo and talentInfo.tier or 1
    if tier <= 1 then
        return true
    end

    local frame = button and button.yuiTalentFrame
    local pointsSpent = (frame and frame.pointsSpent) or 0
    if GetPreviewEnabled() then
        pointsSpent = pointsSpent + ((frame and frame.previewPointsSpent) or 0)
    end

    local pointsPerTier = (frame and frame.pet) and (_G.PET_TALENTS_PER_TIER or 3) or (_G.PLAYER_TALENTS_PER_TIER or 5)
    return pointsSpent >= ((tier - 1) * pointsPerTier)
end

local function CanSpendTalentPoint(button, talentInfo, rank)
    if not button or not button:IsShown() or not talentInfo then
        return false
    end
    if not IsSelectedTalentGroupEditable() then
        return false
    end
    if GetUnspentPoints() <= 0 then
        return false
    end

    local currentRank = rank or GetTalentRank(talentInfo)
    local maxRank = talentInfo.maxRank or 0
    if maxRank > 0 and currentRank >= maxRank then
        return false
    end
    if not IsTalentTierUnlocked(button, talentInfo) then
        return false
    end
    return GetTalentPrereqState(talentInfo)
end

local function HideTalentButtonTexture(texture)
    if not texture then
        return
    end

    if type(texture.Hide) == "function" then
        texture:Hide()
    end
    if type(texture.SetAlpha) == "function" then
        texture:SetAlpha(0)
    end
    if type(texture.SetTexture) == "function" then
        texture:SetTexture(nil)
    end
end

local function HideTalentButtonNativeBorder(button)
    if not button then
        return
    end

    if type(button.GetNormalTexture) == "function" then
        HideTalentButtonTexture(button:GetNormalTexture())
    end

    local name = button:GetName()
    if not name then
        return
    end

    HideTalentButtonTexture(_G[name .. "NormalTexture"])
    HideTalentButtonTexture(_G[name .. "Slot"])
    HideTalentButtonTexture(_G[name .. "RankBorder"])
end

local function GetBodyFont()
    if RANK_FONT then
        return RANK_FONT
    end
    if GUI2 and type(GUI2.GetFont) == "function" then
        return GUI2:GetFont("font.family.body")
    end
    return STANDARD_TEXT_FONT
end

local function GetTalentButtonIconRegion(button)
    if not button then
        return nil
    end

    if button.icon then
        return button.icon
    end
    if button.Icon then
        return button.Icon
    end

    local name = button:GetName()
    if not name then
        return nil
    end

    return _G[name .. "IconTexture"] or _G[name .. "Icon"] or _G[name .. "icon"]
end

local function AnchorTalentBorderToIcon(button, border)
    if not button or not border then
        return
    end

    border:ClearAllPoints()
    local icon = GetTalentButtonIconRegion(button)
    if icon then
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    else
        border:SetSize(42, 42)
        border:SetPoint("LEFT", button, "LEFT", 34, 0)
    end
end

local function AnchorTalentRankBadge(button, badge)
    if not button or not badge then
        return
    end

    badge:ClearAllPoints()
    badge:SetPoint("BOTTOMRIGHT", button.yuiTalentBorder or GetTalentButtonIconRegion(button) or button, "BOTTOMRIGHT", 5, -5)
end

local function EnsureTalentRankBadge(button)
    if not button then
        return nil
    end
    if button.yuiTalentRankBadge then
        return button.yuiTalentRankBadge
    end

    local name = button:GetName()
    local badge = CreateNativeFrame("Frame", name and (name .. "YUIRankBadge") or nil, button)
    badge:SetSize(21, 18)
    AnchorTalentRankBadge(button, badge)
    badge:SetFrameLevel(button:GetFrameLevel() + 11)
    badge:EnableMouse(false)
    if type(badge.SetMouseClickEnabled) == "function" then
        badge:SetMouseClickEnabled(false)
    end

    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bg:SetAllPoints()
    SetSolidTexture(badge.bg, 0.02, 0.025, 0.035, 0.86)
    CreateSimpleBorder(badge, "color.border.accent")

    badge.text = CreateText(badge, "", 16, "color.text.heading", "CENTER")
    badge.text:SetPoint("CENTER", badge, "CENTER", 1, 0)
    if badge.text.SetJustifyH then
        badge.text:SetJustifyH("CENTER")
    end
    if badge.text.SetJustifyV then
        badge.text:SetJustifyV("MIDDLE")
    end
    if badge.text.SetFont then
        badge.text:SetFont(GetBodyFont(), 16, "OUTLINE")
    end
    if badge.text.SetShadowColor then
        badge.text:SetShadowColor(0, 0, 0, 0.95)
        badge.text:SetShadowOffset(1, -1)
    end

    button.yuiTalentRankBadge = badge
    return badge
end

local function UpdateTalentRankBadge(button, talentInfo)
    local badge = EnsureTalentRankBadge(button)
    if not badge then
        return
    end

    local name = button and button:GetName()
    local nativeRank = name and _G[name .. "Rank"]
    local nativeRankBorder = name and _G[name .. "RankBorder"]
    local rankText = nativeRank and nativeRank:GetText() or ""

    HideTalentButtonTexture(nativeRankBorder)
    if nativeRank then
        nativeRank:SetAlpha(0)
        nativeRank:Hide()
    end

    if not button:IsShown() or rankText == nil or rankText == "" then
        badge:Hide()
        return
    end

    local rankValue = tonumber(string.match(rankText, "^(%d+)") or "") or 0
    if rankValue == 0 and not CanSpendTalentPoint(button, talentInfo, rankValue) then
        badge:Hide()
        return
    end

    badge:SetFrameLevel(button:GetFrameLevel() + 11)
    AnchorTalentRankBadge(button, badge)
    badge.text:SetText(rankText)
    if badge.text.SetFont then
        badge.text:SetFont(GetBodyFont(), 16, "OUTLINE")
    end
    local textWidth = badge.text.GetStringWidth and badge.text:GetStringWidth() or 0
    badge:SetSize(math.max(21, textWidth + 9), 18)
    badge:Show()

    local maxRank = talentInfo and talentInfo.maxRank or 0
    if maxRank > 0 and rankValue >= maxRank then
        SetFrameBorderColor(badge, "color.border.accent")
        if badge.text.SetTextColor then
            badge.text:SetTextColor(1, 0.92, 0.18, 1)
        end
    else
        SetFrameBorderColor(badge, "color.border.default")
        if badge.text.SetTextColor then
            badge.text:SetTextColor(0.38, 1, 0.25, 1)
        end
    end
end

local function EnsureTalentButtonStyle(button)
    if not button then
        return
    end

    HideTalentButtonNativeBorder(button)
    if button.yuiTalentEnhancementStyled then
        AnchorTalentBorderToIcon(button, button.yuiTalentBorder)
        AnchorTalentRankBadge(button, button.yuiTalentRankBadge)
        return
    end

    local name = button:GetName()
    local border = CreateNativeFrame("Frame", name and (name .. "YUIBorder") or nil, button)
    AnchorTalentBorderToIcon(button, border)
    border:SetFrameLevel(button:GetFrameLevel() + 8)
    border:EnableMouse(false)
    if type(border.SetMouseClickEnabled) == "function" then
        border:SetMouseClickEnabled(false)
    end
    CreateSimpleBorder(border, "color.border.subtle")
    button.yuiTalentBorder = border

    EnsureTalentRankBadge(button)
    button.yuiTalentEnhancementStyled = true
end

local function UpdateTalentButtonStyle(button, talentInfo)
    EnsureTalentButtonStyle(button)
    local border = button and button.yuiTalentBorder
    if not border then
        return
    end

    HideTalentButtonNativeBorder(button)
    border:SetFrameLevel(button:GetFrameLevel() + 8)
    SetShown(border, button:IsShown())
    UpdateTalentRankBadge(button, talentInfo)

    if button.yuiTalentHover then
        SetFrameBorderColor(border, "color.border.accent")
        return
    end

    if not talentInfo then
        SetFrameBorderColor(border, "color.border.subtle")
        return
    end

    local rank = GetTalentRank(talentInfo)

    if rank > 0 then
        SetFrameBorderColor(border, "color.border.accent")
    elseif CanSpendTalentPoint(button, talentInfo, rank) then
        SetFrameBorderColor(border, "color.border.default")
    else
        SetFrameBorderColor(border, "color.border.subtle")
    end
end

local function UpdateTreeButtonStyles(frame)
    if not frame then
        return
    end

    local frameName = frame:GetName()
    for index = 1, MAX_NUM_TALENTS do
        local button = _G[frameName .. "Talent" .. index]
        if button then
            UpdateTalentButtonStyle(button, GetTalentInfoForButton(button))
        end
    end
end

local function TalentButton_OnEnter(button)
    if not GameTooltip or not PlayerTalentFrame then
        return
    end

    button.yuiTalentHover = true
    UpdateTalentButtonStyle(button, GetTalentInfoForButton(button))

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local talentInfo = GetTalentInfoForButton(button)
    if talentInfo and talentInfo.talentID then
        GameTooltip:SetTalent(talentInfo.talentID, PlayerTalentFrame.inspect, PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup)
    end
    button.UpdateTooltip = TalentButton_OnEnter
end

local function TalentButton_OnLeave(button)
    button.yuiTalentHover = false
    UpdateTalentButtonStyle(button, GetTalentInfoForButton(button))
    if YUI.HideGameTooltip then
        YUI.HideGameTooltip()
    end
end

local function TalentButton_OnEvent(button)
    if GameTooltip and GameTooltip:IsOwned(button) then
        TalentButton_OnEnter(button)
    end
    UpdateTalentButtonStyle(button, GetTalentInfoForButton(button))
end

local function FormatTreeTitle(name, totalPoints)
    local points = totalPoints or 0
    local titleColor = points > 0 and TREE_TITLE_ACTIVE_COLOR or TREE_TITLE_EMPTY_COLOR
    return string.format(
        T("settings.general.feature.talent_frame_enhancement.tree_title"),
        titleColor .. (name or "") .. COLOR_RESET,
        titleColor .. tostring(points) .. COLOR_RESET
    )
end

local function LayoutTreeTitle(frame, width, centerX)
    if not frame or not frame.title then
        return
    end

    frame.title:ClearAllPoints()
    if frame.title.SetWidth then
        frame.title:SetWidth(width or (TREE_FRAME_WIDTH - 24))
    end
    if frame.title.SetHeight then
        frame.title:SetHeight(22)
    end
    frame.title:SetPoint("TOP", frame, "TOPLEFT", centerX or (TREE_FRAME_WIDTH / 2), 0)
end

local function SetTreeTitle(frame, title)
    if not frame or not frame.title then
        return
    end
    if frame.title.gui2DividerText then
        frame.title.gui2DividerText:SetText(title or "")
    else
        frame.title:SetText(title or "")
    end
end

local function CreateTreeFrame(tabIndex)
    local frameName = "YUI_TalentFrameEnhancementTree" .. tabIndex
    local parent = EnsureContentFrame() or PlayerTalentFrame
    local frame = CreateNativeFrame("Frame", frameName, parent)
    frame:SetSize(TREE_FRAME_WIDTH, TREE_FRAME_HEIGHT)
    frame:SetFrameLevel(parent:GetFrameLevel() + 2)
    frame:Hide()
    frame.yuiTalentTab = tabIndex
    frame.inspect = false
    frame.pet = false
    frame.talentGroup = 1

    if GUI2 and type(GUI2.CreateDivider) == "function" then
        frame.title = GUI2:CreateDivider(frame, TREE_FRAME_WIDTH - 24, 22, "", false)
        LayoutTreeTitle(frame)
        if frame.title.SetFrameLevel then
            frame.title:SetFrameLevel(frame:GetFrameLevel() + 1)
        end
    else
        frame.title = CreateText(frame, "", "font.size.md", "color.text.heading", "CENTER")
        frame.title:SetPoint("TOPLEFT", 0, 0)
        frame.title:SetPoint("TOPRIGHT", 0, 0)
        frame.title:SetHeight(20)
        if frame.title.SetTextColor then
            frame.title:SetTextColor(1, 0.82, 0)
        end
        LayoutTreeTitle(frame)
    end

    frame.TalentPointsText = CreateText(frame, "", "font.size.sm", "color.text.heading", "CENTER")
    frame.TalentPointsText:SetPoint("BOTTOMLEFT", 0, 4)
    frame.TalentPointsText:SetPoint("BOTTOMRIGHT", 0, 4)
    frame.TalentPointsText:SetHeight(18)
    if frame.TalentPointsText.SetTextColor then
        frame.TalentPointsText:SetTextColor(1, 0.82, 0)
    end
    frame.TalentPointsText:SetAlpha(0)
    frame.TalentPointsText:Hide()
    _G[frameName .. "TalentPointsText"] = frame.TalentPointsText

    local content = CreateNativeFrame("Frame", frameName .. "ScrollChildFrame", frame)
    content:SetSize(TREE_CONTENT_WIDTH, TREE_CONTENT_HEIGHT)
    content:SetScale(TREE_CONTENT_SCALE)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -30)
    frame.scrollChild = content

    local dummyScrollDown = CreateNativeFrame("Button", frameName .. "ScrollFrameScrollBarScrollDownButton", frame)
    dummyScrollDown:Hide()
    _G[frameName .. "DownArrow_OnClick"] = function() end

    local bgTopLeft = content:CreateTexture(frameName .. "BackgroundTopLeft", "BACKGROUND")
    local bgTopRight = content:CreateTexture(frameName .. "BackgroundTopRight", "BACKGROUND")
    local bgBottomLeft = content:CreateTexture(frameName .. "BackgroundBottomLeft", "BACKGROUND")
    local bgBottomRight = content:CreateTexture(frameName .. "BackgroundBottomRight", "BACKGROUND")

    local borderWidth, borderHeight, backgroundScale, sourceLeft, sourceRight = GetTreeBackgroundCoverLayout()
    local topOffsetY = TREE_BACKGROUND_OFFSET_Y
    local bottomOffsetY = TREE_BACKGROUND_OFFSET_Y - (TREE_BACKGROUND_SOURCE_TOP_HEIGHT * backgroundScale)
    local topLeftWidth = ConfigureBackgroundCoverPiece(
        bgTopLeft,
        sourceLeft,
        sourceRight,
        0,
        TREE_BACKGROUND_SOURCE_LEFT_WIDTH,
        TREE_BACKGROUND_SOURCE_TOP_HEIGHT,
        1,
        1,
        backgroundScale,
        TREE_BACKGROUND_OFFSET_X,
        topOffsetY
    )
    ConfigureBackgroundCoverPiece(
        bgTopRight,
        sourceLeft,
        sourceRight,
        TREE_BACKGROUND_SOURCE_LEFT_WIDTH,
        TREE_BACKGROUND_SOURCE_RIGHT_WIDTH,
        TREE_BACKGROUND_SOURCE_TOP_HEIGHT,
        TREE_BACKGROUND_RIGHT_VISIBLE_RATIO,
        1,
        backgroundScale,
        TREE_BACKGROUND_OFFSET_X + topLeftWidth,
        topOffsetY
    )
    local bottomLeftWidth = ConfigureBackgroundCoverPiece(
        bgBottomLeft,
        sourceLeft,
        sourceRight,
        0,
        TREE_BACKGROUND_SOURCE_LEFT_WIDTH,
        TREE_BACKGROUND_SOURCE_BOTTOM_HEIGHT,
        1,
        TREE_BACKGROUND_BOTTOM_VISIBLE_RATIO,
        backgroundScale,
        TREE_BACKGROUND_OFFSET_X,
        bottomOffsetY
    )
    ConfigureBackgroundCoverPiece(
        bgBottomRight,
        sourceLeft,
        sourceRight,
        TREE_BACKGROUND_SOURCE_LEFT_WIDTH,
        TREE_BACKGROUND_SOURCE_RIGHT_WIDTH,
        TREE_BACKGROUND_SOURCE_BOTTOM_HEIGHT,
        TREE_BACKGROUND_RIGHT_VISIBLE_RATIO,
        TREE_BACKGROUND_BOTTOM_VISIBLE_RATIO,
        backgroundScale,
        TREE_BACKGROUND_OFFSET_X + bottomLeftWidth,
        bottomOffsetY
    )

    local bgBorderTop = content:CreateTexture(frameName .. "BackgroundBorderTop", "BORDER")
    bgBorderTop:SetSize(borderWidth, 1)
    bgBorderTop:SetPoint("TOPLEFT", bgTopLeft, "TOPLEFT", 0, 0)
    SetSolidTexture(bgBorderTop, 0.38, 0.40, 0.44, 0.72)
    local bgBorderBottom = content:CreateTexture(frameName .. "BackgroundBorderBottom", "BORDER")
    bgBorderBottom:SetSize(borderWidth, 1)
    bgBorderBottom:SetPoint("TOPLEFT", bgTopLeft, "TOPLEFT", 0, -borderHeight)
    SetSolidTexture(bgBorderBottom, 0.38, 0.40, 0.44, 0.72)
    local bgBorderLeft = content:CreateTexture(frameName .. "BackgroundBorderLeft", "BORDER")
    bgBorderLeft:SetSize(1, borderHeight)
    bgBorderLeft:SetPoint("TOPLEFT", bgTopLeft, "TOPLEFT", 0, 0)
    SetSolidTexture(bgBorderLeft, 0.38, 0.40, 0.44, 0.72)
    local bgBorderRight = content:CreateTexture(frameName .. "BackgroundBorderRight", "BORDER")
    bgBorderRight:SetSize(1, borderHeight)
    bgBorderRight:SetPoint("TOPLEFT", bgTopLeft, "TOPLEFT", borderWidth, 0)
    SetSolidTexture(bgBorderRight, 0.38, 0.40, 0.44, 0.72)

    local titleWidth = math.max(180, (borderWidth * TREE_CONTENT_SCALE) - 26)
    local titleCenterX = (TREE_BACKGROUND_OFFSET_X + (borderWidth / 2)) * TREE_CONTENT_SCALE
    LayoutTreeTitle(frame, titleWidth, titleCenterX)

    for index = 1, MAX_NUM_BRANCH_TEXTURES do
        local branch = CreateTemplateTexture(content, frameName .. "Branch" .. index, "ARTWORK", "TalentBranchTemplate", "Interface\\TalentFrame\\UI-TalentBranches")
        branch:Hide()
    end

    for index = 1, MAX_NUM_TALENTS do
        local button = CreateNativeFrame("Button", frameName .. "Talent" .. index, content, "PlayerTalentButtonTemplate")
        button:SetID(index)
        button.yuiTalentFrame = frame
        button:SetScript("OnClick", TalentButton_OnClick)
        button:SetScript("OnEnter", TalentButton_OnEnter)
        button:SetScript("OnLeave", TalentButton_OnLeave)
        button:SetScript("OnEvent", TalentButton_OnEvent)
        button:Hide()
        EnsureTalentButtonStyle(button)
    end

    local arrowFrame = CreateNativeFrame("Frame", frameName .. "ArrowFrame", content)
    arrowFrame:SetAllPoints(content)
    frame.arrowFrame = arrowFrame

    for index = 1, MAX_NUM_ARROW_TEXTURES do
        local arrow = CreateTemplateTexture(arrowFrame, frameName .. "Arrow" .. index, "OVERLAY", "TalentArrowTemplate", "Interface\\TalentFrame\\UI-TalentArrows")
        arrow:Hide()
    end

    InitializeBranchArray(frame)
    return frame
end

local function EnsureTreeFrame(tabIndex)
    local frame = treeFrames[tabIndex]
    if not frame then
        frame = CreateTreeFrame(tabIndex)
        treeFrames[tabIndex] = frame
    end
    return frame
end

local function HideAllTrees()
    for _, frame in pairs(treeFrames) do
        frame:Hide()
    end
end

local function UpdateTreeFrame(frame, tabIndex)
    if not frame or not PlayerTalentFrame then
        return
    end

    frame.yuiTalentTab = tabIndex
    frame.selectedTab = tabIndex
    frame.inspect = PlayerTalentFrame.inspect
    frame.pet = PlayerTalentFrame.pet
    frame.talentGroup = PlayerTalentFrame.talentGroup

    local name = ""
    local totalPoints = 0
    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
        local _, specName, _, _, _, _, pointsSpent, _, previewPointsSpent = C_SpecializationInfo.GetSpecializationInfo(tabIndex, frame.inspect, frame.pet, nil, nil, frame.talentGroup)
        name = specName or ""
        totalPoints = (pointsSpent or 0) + (previewPointsSpent or 0)
        frame.pointsSpent = pointsSpent or 0
        frame.previewPointsSpent = previewPointsSpent or 0
    end

    if type(TalentFrame_Update) == "function" then
        TalentFrame_Update(frame)
    end
    UpdateTreeButtonStyles(frame)

    if frame.title and frame.title.SetFrameLevel then
        frame.title:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
    SetTreeTitle(frame, FormatTreeTitle(name, totalPoints))
    frame.TalentPointsText:SetText("")
    frame.TalentPointsText:SetAlpha(0)
    frame.TalentPointsText:Hide()
end

local function SuppressNativeVisuals(duringNative)
    InstallHideProtections()
    HideLegacyBackdrops()
    HideTalentEmuXNativeButton()

    for _, name in ipairs(HIDDEN_BLIZZARD_FRAMES) do
        if duringNative then
            SuppressFrameVisuals(_G[name])
        else
            SuppressFrame(_G[name])
        end
    end

    for index = 1, 4 do
        local tab = _G["PlayerTalentFrameTab" .. index]
        if duringNative then
            SuppressFrameVisuals(tab)
        else
            SuppressFrame(tab)
        end
    end
end

HideBlizzardTalentUI = function()
    SuppressNativeVisuals(false)
end

local function ShowBlizzardTalentUI()
    local restoreNames = {
        "PlayerTalentFramePortrait",
        "PlayerTalentFrameTopLeft",
        "PlayerTalentFrameTopRight",
        "PlayerTalentFrameBottomLeft",
        "PlayerTalentFrameBottomRight",
        "PlayerTalentFrameTitleText",
        "PlayerTalentFrameCancelButton",
        "PlayerTalentFramePointsBar",
        "PlayerTalentFrameTalentPointsText",
        "PlayerTalentFrameScrollFrame",
    }

    for _, name in ipairs(restoreNames) do
        RestoreFrame(_G[name], true)
        SetNamedShown(name, true)
    end

    for index = 1, 4 do
        RestoreFrame(_G["PlayerTalentFrameTab" .. index], true)
        SetNamedShown("PlayerTalentFrameTab" .. index, true)
    end
    for index = 1, 3 do
        RestoreFrame(_G["PlayerSpecTab" .. index], true)
        SetNamedShown("PlayerSpecTab" .. index, true)
    end
    if PlayerTalentFrameCloseButton and PlayerTalentFrameCloseButton.SetScale then
        PlayerTalentFrameCloseButton:SetScale(1)
    end
    if specSwitcher then
        specSwitcher:Hide()
    end
    if PlayerTalentFrameActivateButton and PlayerTalentFrame then
        PlayerTalentFrameActivateButton:SetParent(PlayerTalentFrame)
        PlayerTalentFrameActivateButton:ClearAllPoints()
        PlayerTalentFrameActivateButton:SetPoint("TOP", PlayerTalentFrame, "TOP", 0, -45)
        RestoreFrame(PlayerTalentFrameActivateButton, true)
    end
    ShowTalentEmuXNativeButton()
end

local function UpdateSpecTabs()
    if not PlayerTalentFrame then
        return
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local level = parent:GetFrameLevel() + 9
    local playerGroups = 1
    local petGroups = 0
    if type(GetNumTalentGroups) == "function" then
        local ok, count = pcall(GetNumTalentGroups, false, false)
        if ok and count then
            playerGroups = count
        end
        ok, count = pcall(GetNumTalentGroups, false, true)
        if ok and count then
            petGroups = count
        end
    end

    for index = 1, 3 do
        local tab = _G["PlayerSpecTab" .. index]
        if tab then
            RestoreFrame(tab, true)
            tab:SetFrameLevel(level)
            local shouldShow = index == 1
            if index == 2 then
                shouldShow = playerGroups > 1
            elseif index == 3 then
                shouldShow = petGroups > 0
            end
            if shouldShow then
                tab:Show()
            else
                tab:Hide()
            end

            if index <= 2 and tab:IsShown() then
                local spec = TALENT_UI_SPECS and TALENT_UI_SPECS[tab.specIndex]
                local normalTexture = tab.GetNormalTexture and tab:GetNormalTexture()
                if spec and normalTexture then
                    local totalPoints = 0
                    local fallbackIcon
                    local maxPoints = -1
                    local numTabs = type(GetNumTalentTabs) == "function" and GetNumTalentTabs(false, false) or 0
                    for tabIndex = 1, numTabs do
                        if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
                            local ok, _, _, _, icon, _, _, pointsSpent, _, previewPointsSpent = pcall(C_SpecializationInfo.GetSpecializationInfo, tabIndex, false, false, nil, nil, spec.talentGroup)
                            if ok then
                                local displayPoints = (pointsSpent or 0) + (previewPointsSpent or 0)
                                totalPoints = totalPoints + displayPoints
                                if displayPoints > maxPoints then
                                    maxPoints = displayPoints
                                    fallbackIcon = icon
                                end
                            end
                        end
                    end

                    if totalPoints <= 0 then
                        normalTexture:SetTexture(QUESTION_MARK_ICON)
                        normalTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        tab.usingPortraitTexture = false
                        tab.yuiTalentQuestionMarkIcon = true
                    elseif tab.yuiTalentQuestionMarkIcon and fallbackIcon then
                        normalTexture:SetTexture(fallbackIcon)
                        normalTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        tab.usingPortraitTexture = false
                        tab.yuiTalentQuestionMarkIcon = false
                    end
                end
            end

            tab.yuiTalentEnhancementSwitcherShown = shouldShow
            if shouldShow then
                SuppressFrame(tab)
            end
        end
    end
end

local function GetSpecSwitcherLabel(index)
    if index == 2 then
        return _G.TALENT_SPEC_SECONDARY or T("settings.general.feature.talent_frame_enhancement.title_secondary")
    elseif index == 3 then
        return _G.TALENT_SPEC_PET_PRIMARY or T("settings.general.feature.talent_frame_enhancement.title_pet")
    end
    return _G.TALENT_SPEC_PRIMARY or T("settings.general.feature.talent_frame_enhancement.title_primary")
end

local function GetSpecSwitcherIcon(tab)
    local normalTexture = tab and tab.GetNormalTexture and tab:GetNormalTexture()
    if normalTexture and normalTexture.GetTexture then
        return normalTexture:GetTexture()
    end
    return QUESTION_MARK_ICON
end

local function ApplySpecSwitcherState(button, selected, active)
    if not button then
        return
    end

    if selected then
        SetSolidTexture(button.fill, 0.18, 0.13, 0.035, 0.88)
        SetFrameBorderColor(button, 0.95, 0.76, 0.18, 0.95)
        SetTextColor(button.text, { 1.00, 0.86, 0.22, 1 })
    elseif active then
        SetSolidTexture(button.fill, 0.05, 0.18, 0.06, 0.72)
        SetFrameBorderColor(button, 0.26, 0.92, 0.22, 0.82)
        SetTextColor(button.text, { 0.56, 1.00, 0.38, 1 })
    else
        SetSolidTexture(button.fill, 0.025, 0.03, 0.04, 0.76)
        SetFrameBorderColor(button, 0.30, 0.34, 0.39, 0.78)
        SetTextColor(button.text, { 0.88, 0.90, 0.94, 1 })
    end
end

local function CreateSpecSwitcherItem(parent, index)
    local button = CreateNativeFrame("Button", "YUI_TalentFrameEnhancementSpecSwitcherItem" .. index, parent, "BackdropTemplate")
    button:SetSize(SPEC_SWITCHER_ITEM_WIDTH, SPEC_SWITCHER_ITEM_HEIGHT)
    button:SetID(index)
    button:EnableMouse(true)
    if type(button.RegisterForClicks) == "function" then
        button:RegisterForClicks("AnyUp")
    end

    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetPoint("TOPLEFT", 1, -1)
    button.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    CreateSimpleBorder(button, "color.border.default")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("LEFT", 7, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.text = CreateText(button, GetSpecSwitcherLabel(index), "font.size.md", "color.text.primary", "LEFT")
    button.text:SetPoint("LEFT", button.icon, "RIGHT", 7, 0)
    button.text:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.text:SetJustifyH("LEFT")

    button:SetScript("OnEnter", function(self)
        if self.yuiSelected then
            ApplySpecSwitcherState(self, true, self.yuiActive)
        else
            SetSolidTexture(self.fill, 0.09, 0.10, 0.12, 0.86)
            SetFrameBorderColor(self, 0.54, 0.58, 0.64, 0.88)
        end
    end)
    button:SetScript("OnLeave", function(self)
        ApplySpecSwitcherState(self, self.yuiSelected, self.yuiActive)
    end)
    button:SetScript("OnClick", function(self)
        local tab = _G["PlayerSpecTab" .. tostring(self:GetID())]
        if tab and type(PlayerSpecTab_OnClick) == "function" then
            PlayerSpecTab_OnClick(tab)
            if ScheduleRefresh then
                ScheduleRefresh()
            end
        end
    end)

    ApplySpecSwitcherState(button, false, false)
    return button
end

local function GetSpecSwitcherAnchorFrame()
    local chrome = PlayerTalentFrame and PlayerTalentFrame.yuiTalentEnhancementChrome
    return (chrome and chrome.bg) or PlayerTalentFrame
end

local function EnsureSpecSwitcher()
    if specSwitcher or not PlayerTalentFrame then
        return specSwitcher
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local anchor = GetSpecSwitcherAnchorFrame()
    local frame = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementSpecSwitcher", parent)
    frame:SetSize((SPEC_SWITCHER_ITEM_WIDTH * 3) + (SPEC_SWITCHER_ITEM_GAP * 2), SPEC_SWITCHER_ITEM_HEIGHT)
    frame:SetFrameLevel(parent:GetFrameLevel() + 14)
    frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", SPEC_SWITCHER_RIGHT_X, SPEC_SWITCHER_BOTTOM_Y)
    frame.items = {}
    for index = 1, 3 do
        local item = CreateSpecSwitcherItem(frame, index)
        item:SetPoint("RIGHT", frame, "RIGHT", -((index - 1) * (SPEC_SWITCHER_ITEM_WIDTH + SPEC_SWITCHER_ITEM_GAP)), 0)
        frame.items[index] = item
    end
    specSwitcher = frame
    return frame
end

local function UpdateSpecSwitcher()
    local frame = EnsureSpecSwitcher()
    if not frame then
        return
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local anchor = GetSpecSwitcherAnchorFrame()
    frame:SetFrameLevel(parent:GetFrameLevel() + 14)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", SPEC_SWITCHER_RIGHT_X, SPEC_SWITCHER_BOTTOM_Y)

    local visibleCount = 0
    for index = 1, 3 do
        local item = frame.items and frame.items[index]
        local tab = _G["PlayerSpecTab" .. index]
        local show = tab and tab.yuiTalentEnhancementSwitcherShown
        if item then
            if show then
                visibleCount = visibleCount + 1
                item:ClearAllPoints()
                item:SetPoint("RIGHT", frame, "RIGHT", -((visibleCount - 1) * (SPEC_SWITCHER_ITEM_WIDTH + SPEC_SWITCHER_ITEM_GAP)), 0)
                item.text:SetText(GetSpecSwitcherLabel(index))
                item.icon:SetTexture(GetSpecSwitcherIcon(tab))
                local selected = tab.GetChecked and tab:GetChecked()
                local active = false
                if TalentUIUtil and type(TalentUIUtil.IsSpecActive) == "function" and tab.specIndex then
                    local ok, value = pcall(TalentUIUtil.IsSpecActive, tab.specIndex)
                    active = ok and value
                end
                item.yuiSelected = selected and true or false
                item.yuiActive = active and true or false
                ApplySpecSwitcherState(item, item.yuiSelected, item.yuiActive)
                item:Show()
            else
                item:Hide()
            end
        end
    end

    if visibleCount > 0 then
        frame:SetWidth((visibleCount * SPEC_SWITCHER_ITEM_WIDTH) + (math.max(visibleCount - 1, 0) * SPEC_SWITCHER_ITEM_GAP))
        frame:Show()
    else
        frame:Hide()
    end
end

local function EnsureChrome()
    if not PlayerTalentFrame then
        return
    end

    local chrome = PlayerTalentFrame.yuiTalentEnhancementChrome
    if chrome then
        chrome:SetFrameLevel(PlayerTalentFrame:GetFrameLevel() + 1)
        if chrome.bg then
            SetSolidTexture(chrome.bg, 0.025, 0.03, 0.035, 0.92)
        end
        if chrome.inner then
            chrome.inner:Hide()
            chrome.inner:SetAlpha(0)
        end
        chrome:Show()
        return chrome
    end

    chrome = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementChrome", PlayerTalentFrame)
    chrome:SetAllPoints(PlayerTalentFrame)
    chrome:SetFrameLevel(PlayerTalentFrame:GetFrameLevel() + 1)

    chrome.bg = chrome:CreateTexture(nil, "BACKGROUND")
    chrome.bg:SetPoint("TOPLEFT", 8, -12)
    chrome.bg:SetPoint("BOTTOMRIGHT", -8, 10)
    SetSolidTexture(chrome.bg, 0.025, 0.03, 0.035, 0.92)

    chrome.top = chrome:CreateTexture(nil, "BORDER")
    chrome.top:SetHeight(1)
    chrome.top:SetPoint("TOPLEFT", chrome.bg, "TOPLEFT", 0, 0)
    chrome.top:SetPoint("TOPRIGHT", chrome.bg, "TOPRIGHT", 0, 0)
    SetSolidTexture(chrome.top, 0.19, 0.22, 0.25, 0.9)

    chrome.bottom = chrome:CreateTexture(nil, "BORDER")
    chrome.bottom:SetHeight(1)
    chrome.bottom:SetPoint("BOTTOMLEFT", chrome.bg, "BOTTOMLEFT", 0, 0)
    chrome.bottom:SetPoint("BOTTOMRIGHT", chrome.bg, "BOTTOMRIGHT", 0, 0)
    SetSolidTexture(chrome.bottom, 0.19, 0.22, 0.25, 0.9)

    chrome.left = chrome:CreateTexture(nil, "BORDER")
    chrome.left:SetWidth(1)
    chrome.left:SetPoint("TOPLEFT", chrome.bg, "TOPLEFT", 0, 0)
    chrome.left:SetPoint("BOTTOMLEFT", chrome.bg, "BOTTOMLEFT", 0, 0)
    SetSolidTexture(chrome.left, 0.19, 0.22, 0.25, 0.9)

    chrome.right = chrome:CreateTexture(nil, "BORDER")
    chrome.right:SetWidth(1)
    chrome.right:SetPoint("TOPRIGHT", chrome.bg, "TOPRIGHT", 0, 0)
    chrome.right:SetPoint("BOTTOMRIGHT", chrome.bg, "BOTTOMRIGHT", 0, 0)
    SetSolidTexture(chrome.right, 0.19, 0.22, 0.25, 0.9)

    PlayerTalentFrame.yuiTalentEnhancementChrome = chrome
    return chrome
end

local function CreateStyledButton(parent, name, text, width, height)
    local button
    if GUI2 and GUI2.Form and type(GUI2.Form.CreateButton) == "function" then
        button = GUI2.Form:CreateButton(parent, {
            name = name,
            text = text or "",
            width = width,
            height = height,
            tone = "accent",
        })
    else
        button = CreateNativeFrame("Button", name, parent, "BackdropTemplate")
        button:SetSize(width, height)
        if GUI2 and type(GUI2.ApplyBackdrop) == "function" then
            GUI2:ApplyBackdrop(button, "color.control.bg")
        end
        CreateSimpleBorder(button, "color.border.default")

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER")
        button.text:SetText(text or "")
        button.SetText = function(self, value)
            if self.text then
                self.text:SetText(value or "")
            end
        end
    end

    if button then
        button:EnableMouse(true)
        if type(button.RegisterForClicks) == "function" then
            button:RegisterForClicks("AnyUp")
        end
    end
    return button
end

local ACTION_BUTTON_PALETTES = {
    learn = {
        normal = { 0.24, 0.42, 0.16, 0.88 },
        hover = { 0.32, 0.56, 0.20, 0.94 },
        pressed = { 0.18, 0.32, 0.12, 0.96 },
        border = { 0.72, 0.88, 0.26, 0.96 },
        text = { 1.00, 0.93, 0.28, 1 },
    },
    reset = {
        normal = { 0.44, 0.19, 0.10, 0.88 },
        hover = { 0.60, 0.25, 0.12, 0.94 },
        pressed = { 0.34, 0.13, 0.08, 0.96 },
        border = { 0.95, 0.48, 0.20, 0.96 },
        text = { 1.00, 0.86, 0.28, 1 },
    },
}

local function ApplyActionButtonPalette(button, state)
    if not button or not button.yuiActionButtonPalette then
        return
    end

    local palette = button.yuiActionButtonPalette
    local surface = palette[state or "normal"] or palette.normal
    if button.yuiActionButtonFill then
        SetSolidTexture(button.yuiActionButtonFill, surface[1], surface[2], surface[3], surface[4])
    end
    SetBackdropColor(button, surface)
    if palette.border then
        SetFrameBorderColor(button, palette.border[1], palette.border[2], palette.border[3], palette.border[4])
    end
    local text = button.text or (button.GetFontString and button:GetFontString())
    SetTextColor(text, palette.text)
end

local function StyleActionButton(button, palette)
    if not button or not palette then
        return
    end

    button.yuiActionButtonPalette = palette
    if not button.yuiActionButtonFill then
        local fill = button:CreateTexture(nil, "BACKGROUND")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        button.yuiActionButtonFill = fill
    end

    button:SetScript("OnEnter", function(self)
        ApplyActionButtonPalette(self, "hover")
    end)
    button:SetScript("OnLeave", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, 0) end
        ApplyActionButtonPalette(self, "normal")
    end)
    button:SetScript("OnMouseDown", function(self)
        if self.text then self.text:SetPoint("CENTER", 1, -1) end
        ApplyActionButtonPalette(self, "pressed")
    end)
    button:SetScript("OnMouseUp", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, 0) end
        ApplyActionButtonPalette(self, self:IsMouseOver() and "hover" or "normal")
    end)
    ApplyActionButtonPalette(button, "normal")
end

local function GetActiveTalentGroupContext()
    local group = PlayerTalentFrame and PlayerTalentFrame.talentGroup or 1
    local numGroups = 1

    if C_SpecializationInfo and type(C_SpecializationInfo.GetActiveSpecGroup) == "function" then
        local ok, activeGroup = pcall(C_SpecializationInfo.GetActiveSpecGroup, false, PlayerTalentFrame and PlayerTalentFrame.pet)
        if not ok then
            ok, activeGroup = pcall(C_SpecializationInfo.GetActiveSpecGroup)
        end
        if ok and activeGroup then
            group = activeGroup
        end
    elseif type(GetActiveTalentGroup) == "function" then
        local ok, activeGroup = pcall(GetActiveTalentGroup, false, PlayerTalentFrame and PlayerTalentFrame.pet)
        if not ok then
            ok, activeGroup = pcall(GetActiveTalentGroup)
        end
        if ok and activeGroup then
            group = activeGroup
        end
    end

    if type(GetNumTalentGroups) == "function" then
        local ok, count = pcall(GetNumTalentGroups, false, PlayerTalentFrame and PlayerTalentFrame.pet)
        if not ok then
            ok, count = pcall(GetNumTalentGroups)
        end
        if ok and count then
            numGroups = count
        end
    end

    return group or 1, numGroups or 1
end

local function GetTalentGroupTitle(group, selectedSpec)
    if (selectedSpec and selectedSpec.pet) or (PlayerTalentFrame and PlayerTalentFrame.pet) then
        return _G.TALENT_SPEC_PET_PRIMARY or T("settings.general.feature.talent_frame_enhancement.title_pet")
    end
    if selectedSpec and selectedSpec.name and selectedSpec.name ~= "" then
        return selectedSpec.name
    end
    if group == 2 then
        return _G.TALENT_SPEC_SECONDARY or T("settings.general.feature.talent_frame_enhancement.title_secondary")
    end
    return _G.TALENT_SPEC_PRIMARY or T("settings.general.feature.talent_frame_enhancement.title_primary") or T("settings.general.feature.talent_frame_enhancement.title")
end

local function GetSelectedTalentGroupInfo()
    local selectedSpec
    if TalentUIUtil and type(TalentUIUtil.GetSelectedSpec) == "function" then
        local ok, spec = pcall(TalentUIUtil.GetSelectedSpec)
        if ok then
            selectedSpec = spec
        end
    end

    local selectedGroup = selectedSpec and selectedSpec.talentGroup or (PlayerTalentFrame and PlayerTalentFrame.talentGroup) or 1
    local isPet = PlayerTalentFrame and PlayerTalentFrame.pet
    if selectedSpec and selectedSpec.pet ~= nil then
        isPet = selectedSpec.pet
    end

    local numGroups = 1
    if type(GetNumTalentGroups) == "function" then
        local ok, count = pcall(GetNumTalentGroups, false, isPet)
        if not ok then
            ok, count = pcall(GetNumTalentGroups)
        end
        if ok and count then
            numGroups = count
        end
    end

    local activeSelected
    if TalentUIUtil and type(TalentUIUtil.IsActiveSpecSelected) == "function" then
        local ok, value = pcall(TalentUIUtil.IsActiveSpecSelected)
        if ok then
            activeSelected = value == true
        end
    end
    if activeSelected == nil then
        local activeGroup = GetActiveTalentGroupContext()
        activeSelected = activeGroup == selectedGroup
    end

    return selectedGroup, numGroups, activeSelected, GetTalentGroupTitle(selectedGroup, selectedSpec), selectedSpec
end

local function RefreshNativeTalentControls()
    local group, numGroups = GetActiveTalentGroupContext()

    if type(PlayerTalentFrame_UpdateControls) == "function" then
        local ok = pcall(PlayerTalentFrame_UpdateControls, group, numGroups)
        if not ok then
            pcall(PlayerTalentFrame_UpdateControls)
        end
    end
    if type(PlayerTalentFrame_Update) == "function" then
        PlayerTalentFrame_Update()
    elseif type(PlayerTalentFrame_Refresh) == "function" then
        PlayerTalentFrame_Refresh()
    end
    if ScheduleRefresh then
        ScheduleRefresh()
    end
end

local function EnablePreviewMode()
    if type(SetCVar) == "function" then
        SetCVar("previewTalentsOption", "1")
    end
    RefreshNativeTalentControls()
end

local function OpenTalentEmuX()
    local createEmulator = GetTalentEmuXCreateEmulator()
    if createEmulator then
        pcall(createEmulator)
    end
end

local function LearnPreviewTalents()
    if type(PlayerTalentFrameLearnButton_OnClick) == "function" then
        local ok = pcall(PlayerTalentFrameLearnButton_OnClick, PlayerTalentFrameLearnButton)
        if ok then
            return
        end
    end
    if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("CONFIRM_LEARN_PREVIEW_TALENTS")
    end
end

local function ResetPreviewTalents()
    if type(PlayerTalentFrameResetButton_OnClick) == "function" then
        local ok = pcall(PlayerTalentFrameResetButton_OnClick, PlayerTalentFrameResetButton)
        if ok then
            return
        end
    end
    if PlayerTalentFrame and type(ResetGroupPreviewTalentPoints) == "function" then
        ResetGroupPreviewTalentPoints(PlayerTalentFrame.pet, PlayerTalentFrame.talentGroup)
    end
end

local function AnchorActivationControl(frame, parent)
    if not frame or not parent then
        return
    end

    frame:ClearAllPoints()
    frame:SetSize(SPEC_SWITCHER_ITEM_WIDTH, SPEC_SWITCHER_ITEM_HEIGHT)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ACTIVATION_CONTROL_RIGHT_X, ACTIVATION_CONTROL_Y)
end

local function EnsureActivationCastBar(controls)
    if not controls or controls.activationCastBar then
        return controls and controls.activationCastBar
    end
    if not (GUI2 and GUI2.Data and type(GUI2.Data.CreateProgressBar) == "function") then
        return nil
    end

    local bar = GUI2.Data:CreateProgressBar(controls, {
        width = SPEC_SWITCHER_ITEM_WIDTH,
        height = SPEC_SWITCHER_ITEM_HEIGHT,
        value = 0,
    })
    AnchorActivationControl(bar, controls)
    bar:SetFrameLevel(controls:GetFrameLevel() + 5)
    bar:EnableMouse(false)
    if type(bar.SetMouseClickEnabled) == "function" then
        bar:SetMouseClickEnabled(false)
    end

    bar.text = GUI2:CreateText(bar, "", "font.size.sm", "color.text.heading", "CENTER")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetWidth(SPEC_SWITCHER_ITEM_WIDTH - 10)
    bar.text:SetJustifyH("CENTER")
    if bar.text.SetJustifyV then
        bar.text:SetJustifyV("MIDDLE")
    end
    bar:Hide()

    controls.activationCastBar = bar
    return bar
end

local function GetSelectedActivationTalentGroup()
    if TalentUIUtil and type(TalentUIUtil.GetSelectedSpec) == "function" then
        local spec = TalentUIUtil.GetSelectedSpec()
        if spec and spec.talentGroup then
            return spec.talentGroup
        end
    end
    return PlayerTalentFrame and PlayerTalentFrame.talentGroup
end

local function IsCurrentSpellID(spellID)
    if not spellID then
        return false
    end
    if C_Spell and type(C_Spell.IsCurrentSpell) == "function" then
        local ok, current = pcall(C_Spell.IsCurrentSpell, spellID)
        return ok and current and true or false
    end
    if type(IsCurrentSpell) == "function" then
        local ok, current = pcall(IsCurrentSpell, spellID)
        return ok and current and true or false
    end
    return false
end

local function IsTalentActivationSpellCurrent()
    local talentGroup = GetSelectedActivationTalentGroup()
    local spellID = talentGroup and TALENT_ACTIVATION_SPELLS and TALENT_ACTIVATION_SPELLS[talentGroup]
    return IsCurrentSpellID(spellID)
end

local function GetTalentActivationCastInfo()
    if not IsTalentActivationSpellCurrent() then
        return nil
    end

    local name, text, _, startTime, endTime
    if type(UnitCastingInfo) == "function" then
        name, text, _, startTime, endTime = UnitCastingInfo("player")
    end
    if not name and type(UnitChannelInfo) == "function" then
        name, text, _, startTime, endTime = UnitChannelInfo("player")
    end
    if not name or not startTime or not endTime or endTime <= startTime then
        return nil
    end

    return text or name, startTime / 1000, endTime / 1000
end

local function HideActivationCastBar()
    local bar = topControls and topControls.activationCastBar
    if not bar then
        return
    end

    bar:SetScript("OnUpdate", nil)
    if bar.SetValue then
        bar:SetValue(0, true)
    end
    bar:Hide()
end

local UpdateActivationCastBar
local function ActivationCastBar_OnUpdate(self)
    if not UpdateActivationCastBar() then
        self:SetScript("OnUpdate", nil)
    end
end

UpdateActivationCastBar = function()
    local controls = topControls
    local bar = controls and controls.activationCastBar
    if not bar then
        return false
    end

    if not IsEffective() or not PlayerTalentFrame or PlayerTalentFrame.pet or not PlayerTalentFrame:IsShown() then
        HideActivationCastBar()
        return false
    end

    local label, startTime, endTime = GetTalentActivationCastInfo()
    if not startTime or not endTime then
        HideActivationCastBar()
        return false
    end

    local duration = endTime - startTime
    if duration <= 0 then
        HideActivationCastBar()
        return false
    end

    local now = GetTime and GetTime() or startTime
    local progress = (now - startTime) / duration
    if progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end

    AnchorActivationControl(bar, controls)
    bar:SetFrameLevel(controls:GetFrameLevel() + 5)
    bar:SetValue(progress, true)
    if bar.text then
        bar.text:SetFormattedText("%d%%", math.floor((progress * 100) + 0.5))
    end
    bar:SetScript("OnUpdate", ActivationCastBar_OnUpdate)
    bar:Show()

    if PlayerTalentFrameActivateButton then
        PlayerTalentFrameActivateButton:Hide()
    end
    return true
end

local function OnActivationCastEvent(_, event, unit)
    if event ~= "CURRENT_SPELL_CAST_CHANGED" and unit and unit ~= "player" then
        return
    end

    local shown = UpdateActivationCastBar()
    if not shown and ScheduleRefresh then
        ScheduleRefresh()
    end
end

local function EnsureActivationCastEvents()
    if activationCastEventFrame then
        return
    end

    local frame = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementActivationCastEvents")
    local unitEvents = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_CHANNEL_STOP",
    }
    for _, event in ipairs(unitEvents) do
        if type(frame.RegisterUnitEvent) == "function" then
            frame:RegisterUnitEvent(event, "player")
        else
            frame:RegisterEvent(event)
        end
    end
    frame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
    frame:SetScript("OnEvent", OnActivationCastEvent)
    activationCastEventFrame = frame
end

local function EnsureTopControls()
    if topControls or not PlayerTalentFrame then
        return topControls
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local frame = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementTopControls", parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 12)
    frame:EnableMouse(false)

    frame.simulator = CreateStyledButton(frame, "YUI_TalentFrameEnhancementSimulatorButton", T("settings.general.feature.talent_frame_enhancement.simulator"), 98, TOP_BUTTON_HEIGHT)
    frame.simulator:SetPoint("TOPLEFT", frame, "TOPLEFT", GetFirstTreeVisualLeft(), TOP_BUTTON_Y)
    frame.simulator:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.simulator:SetScript("OnClick", OpenTalentEmuX)

    frame.learn = CreateStyledButton(frame, "YUI_TalentFrameEnhancementLearnButton", T("settings.general.feature.talent_frame_enhancement.learn"), 70, TOP_BUTTON_HEIGHT)
    frame.learn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", GetRightControlsAnchorX(), TOP_BUTTON_Y)
    frame.learn:SetFrameLevel(frame:GetFrameLevel() + 2)
    StyleActionButton(frame.learn, ACTION_BUTTON_PALETTES.learn)
    frame.learn:SetScript("OnClick", LearnPreviewTalents)

    frame.reset = CreateStyledButton(frame, "YUI_TalentFrameEnhancementResetButton", T("settings.general.feature.talent_frame_enhancement.reset"), 70, TOP_BUTTON_HEIGHT)
    frame.reset:SetPoint("RIGHT", frame.learn, "LEFT", -TOP_BUTTON_GAP, 0)
    frame.reset:SetFrameLevel(frame:GetFrameLevel() + 2)
    StyleActionButton(frame.reset, ACTION_BUTTON_PALETTES.reset)
    frame.reset:SetScript("OnClick", ResetPreviewTalents)

    frame.title = CreateText(parent, T("settings.general.feature.talent_frame_enhancement.title"), "font.size.lg", "color.text.heading", "CENTER")
    frame.title:SetPoint("TOP", parent, "TOP", 0, -34)
    frame.title:SetHeight(20)
    if frame.title.SetTextColor then
        frame.title:SetTextColor(1, 0.82, 0)
    end

    frame.points = CreateText(parent, "", "font.size.md", "color.text.heading", "CENTER")
    frame.points:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)
    frame.points:SetHeight(18)
    if frame.points.SetTextColor then
        frame.points:SetTextColor(1, 0.82, 0)
    end

    frame.status = CreateText(frame, "", "font.size.md", "color.state.success", "RIGHT")
    frame.status:SetSize(190, 24)
    frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", GetRightControlsAnchorX(), TOP_BUTTON_Y)
    if frame.status.SetTextColor then
        frame.status:SetTextColor(0.38, 1, 0.25)
    end
    frame.status:Hide()

    EnsureActivationCastBar(frame)
    topControls = frame
    return frame
end

local function StyleNativeActivateButton(button)
    if not button then
        return
    end

    if not button.yuiTalentEnhancementStyled then
        CreateSimpleBorder(button, "color.border.default")
        button.yuiTalentEnhancementStyled = true
    end

    button:SetSize(SPEC_SWITCHER_ITEM_WIDTH, SPEC_SWITCHER_ITEM_HEIGHT)
end

local function GetTopControlsLeftAnchor(controls)
    if not controls then
        return nil
    end
    if controls.reset and controls.reset:IsShown() then
        return controls.reset
    end
    if controls.learn and controls.learn:IsShown() then
        return controls.learn
    end
    return nil
end

local function UpdateActivateButton()
    local button = PlayerTalentFrameActivateButton
    if not button or not PlayerTalentFrame then
        return false
    end

    if PlayerTalentFrame.pet then
        button:Hide()
        return false
    end

    RestoreFrame(button, true)
    StyleNativeActivateButton(button)
    if type(PlayerTalentFrameActivateButton_Update) == "function" then
        pcall(PlayerTalentFrameActivateButton_Update)
    end
    StyleNativeActivateButton(button)

    local parent = EnsureContentFrame() or PlayerTalentFrame
    button:SetParent(parent)
    button:SetFrameLevel(parent:GetFrameLevel() + 16)

    if button:IsShown() then
        local controls = EnsureTopControls()
        AnchorActivationControl(button, controls or parent)
        button:Show()
    end
    return button:IsShown()
end

local function UpdateActiveStatusText(controls, activeSelected, numGroups, activateShown)
    if not controls or not controls.status then
        return
    end

    local showStatus = activeSelected and (numGroups or 1) > 1 and not activateShown and not (PlayerTalentFrame and PlayerTalentFrame.pet)
    if not showStatus then
        controls.status:Hide()
        return
    end

    controls.status:SetText(T("settings.general.feature.talent_frame_enhancement.active_status"))
    controls.status:ClearAllPoints()
    local anchor = GetTopControlsLeftAnchor(controls)
    if anchor and anchor:IsShown() then
        controls.status:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        controls.status:SetPoint("TOPRIGHT", controls, "TOPRIGHT", GetRightControlsAnchorX(), TOP_BUTTON_Y)
    end
    controls.status:Show()
end

local function UpdateTopControls()
    local frame = EnsureTopControls()
    if not frame then
        return
    end

    frame:Show()
    frame:SetFrameLevel((EnsureContentFrame() or PlayerTalentFrame):GetFrameLevel() + 12)
    frame.title:Show()
    frame.points:Show()
    if frame.status then
        frame.status:Hide()
    end
    if frame.simulator then
        frame.simulator:SetFrameLevel(frame:GetFrameLevel() + 3)
    end
    if frame.learn then
        frame.learn:SetFrameLevel(frame:GetFrameLevel() + 2)
    end
    if frame.reset then
        frame.reset:SetFrameLevel(frame:GetFrameLevel() + 2)
    end
    local _, numGroups, activeSelected, title = GetSelectedTalentGroupInfo()
    frame.title:SetText(title)
    frame.points:SetFormattedText(T("settings.general.feature.talent_frame_enhancement.remaining"), GetUnspentPoints())

    local preview = GetPreviewEnabled()
    local pending = GetPreviewPointsSpent()
    local isPet = PlayerTalentFrame and PlayerTalentFrame.pet
    local hasTalentEmuX = (not isPet) and HasTalentEmuXEntry()
    SetShown(frame.simulator, hasTalentEmuX)
    if frame.simulator.SetSelected and frame.simulator.gui2Selected then
        frame.simulator:SetSelected(false)
    elseif frame.simulator.SetState and frame.simulator.gui2State ~= "normal" then
        frame.simulator:SetState("normal")
    elseif not frame.simulator.SetSelected and not frame.simulator.SetState then
        frame.simulator:SetAlpha(hasTalentEmuX and 1 or 0.78)
    end
    SetShown(frame.learn, preview and pending > 0)
    SetShown(frame.reset, preview and pending > 0)
    ApplyActionButtonPalette(frame.learn, "normal")
    ApplyActionButtonPalette(frame.reset, "normal")
    local activateShown = UpdateActivateButton()
    local activationCastShown = UpdateActivationCastBar()
    UpdateActiveStatusText(frame, activeSelected, numGroups, activateShown or activationCastShown)
end

local function HideTopControls()
    if not topControls then
        return
    end

    HideActivationCastBar()
    topControls:Hide()
    if topControls.title then
        topControls.title:Hide()
    end
    if topControls.points then
        topControls.points:Hide()
    end
    if topControls.status then
        topControls.status:Hide()
    end
end

local function LoadGlyphUI()
    if _G.GlyphFrame and _G.GlyphFrameGlyph1 then
        return true
    end

    if type(GlyphFrame_LoadUI) == "function" then
        pcall(GlyphFrame_LoadUI)
    else
        local System = YUI.API and YUI.API.System
        if System and type(System.LoadAddOn) == "function" then
            pcall(System.LoadAddOn, "Blizzard_GlyphUI")
        elseif type(LoadAddOn) == "function" then
            pcall(LoadAddOn, "Blizzard_GlyphUI")
        end
    end

    if InstallGlyphHooks then
        InstallGlyphHooks()
    end
    return _G.GlyphFrame and _G.GlyphFrameGlyph1
end

local function SuppressGlyphFrameContainer()
    if not _G.GlyphFrame then
        return
    end

    InstallHideProtection(_G.GlyphFrame)
    SuppressFrame(_G.GlyphFrame)
    SuppressFrame(_G.GlyphFrameBackground)
    SuppressFrame(_G.GlyphFrameTitleText)
end

local function GlyphButton_OnClick(button, mouseButton)
    glyphClickActive = true
    local ok, err = true, nil
    if type(GlyphFrameGlyph_OnClick) == "function" then
        ok, err = pcall(GlyphFrameGlyph_OnClick, button, mouseButton)
    end
    glyphClickActive = false

    if ShouldHideBlizzardUI() then
        SuppressNativeVisuals(true)
    end
    if ScheduleRefresh then
        ScheduleRefresh()
    end
    if not ok then
        error(err)
    end
end

local function CreateGlyphRow(parent, name)
    local row = CreateNativeFrame("Frame", name, parent)
    row:SetSize(GLYPH_COLUMN_WIDTH, GLYPH_ROW_HEIGHT)
    row:EnableMouse(false)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row, "LEFT", 76, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.text:SetJustifyH("LEFT")

    return row
end

local function EnsureGlyphSummary()
    if glyphSummary or not PlayerTalentFrame then
        return glyphSummary
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local frame = CreateNativeFrame("Frame", "YUI_TalentFrameEnhancementGlyphSummary", parent)
    frame:SetSize(GLYPH_COLUMN_WIDTH, 560)
    frame:SetFrameLevel(parent:GetFrameLevel() + 7)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 974, -106)

    frame.majorTitle = CreateText(frame, T("settings.general.feature.talent_frame_enhancement.glyph_major"), "font.size.md", "color.text.heading", "LEFT")
    frame.majorTitle:SetPoint("TOPLEFT", 0, 0)
    frame.majorTitle:SetHeight(20)
    if frame.majorTitle.SetTextColor then
        frame.majorTitle:SetTextColor(1, 0.82, 0)
    end

    frame.majorRows = {}
    for index = 1, 3 do
        local row = CreateGlyphRow(frame, "YUI_TalentFrameEnhancementMajorGlyph" .. index)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22 - ((index - 1) * GLYPH_ROW_HEIGHT))
        frame.majorRows[index] = row
    end

    frame.minorTitle = CreateText(frame, T("settings.general.feature.talent_frame_enhancement.glyph_minor"), "font.size.md", "color.text.heading", "LEFT")
    frame.minorTitle:SetPoint("TOPLEFT", frame.majorRows[3], "BOTTOMLEFT", 0, -22)
    frame.minorTitle:SetHeight(20)
    if frame.minorTitle.SetTextColor then
        frame.minorTitle:SetTextColor(1, 0.82, 0)
    end

    frame.minorRows = {}
    for index = 1, 3 do
        local row = CreateGlyphRow(frame, "YUI_TalentFrameEnhancementMinorGlyph" .. index)
        row:SetPoint("TOPLEFT", frame.minorTitle, "BOTTOMLEFT", 0, -2 - ((index - 1) * GLYPH_ROW_HEIGHT))
        frame.minorRows[index] = row
    end

    glyphSummary = frame
    return frame
end

local function GetGlyphLink(slot, glyphID)
    if not glyphID or not C_GlyphInfo or type(C_GlyphInfo.GetGlyphLink) ~= "function" then
        return nil
    end

    local ok, link = pcall(C_GlyphInfo.GetGlyphLink, slot, glyphID)
    if ok then
        return link
    end
    return nil
end

local function GetGlyphData(slot)
    local data = {
        slot = slot,
        enabled = false,
        glyphType = (slot == 1 or slot == 4 or slot == 6) and GLYPH_TYPE_MAJOR or GLYPH_TYPE_MINOR,
    }

    if type(GetGlyphSocketInfo) ~= "function" then
        return data
    end

    local ok, enabled, glyphType, _, glyphSpell, iconFilename, glyphID = pcall(GetGlyphSocketInfo, slot, PlayerTalentFrame and PlayerTalentFrame.talentGroup)
    if not ok then
        return data
    end

    data.enabled = enabled == true
    data.glyphType = glyphType or data.glyphType
    data.glyphSpell = glyphSpell
    data.glyphID = glyphID
    data.link = GetGlyphLink(slot, glyphID)

    if glyphSpell and type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(glyphSpell)
        data.name = name
        data.icon = iconFilename or icon
    else
        data.icon = iconFilename
    end

    return data
end

local function AttachNativeGlyphButton(row, slot)
    local button = _G["GlyphFrameGlyph" .. tostring(slot)]
    if not row or not button then
        return nil
    end

    button:SetParent(row)
    button:SetID(slot)
    button:ClearAllPoints()
    button:SetScale(0.72)
    button:SetPoint("LEFT", row, "LEFT", -7, 0)
    button:SetFrameLevel(row:GetFrameLevel() + 2)
    button:SetAlpha(1)
    button:EnableMouse(true)
    if type(button.SetMouseClickEnabled) == "function" then
        button:SetMouseClickEnabled(true)
    end
    if type(button.RegisterForClicks) == "function" then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    button:SetScript("OnClick", GlyphButton_OnClick)
    button:Show()

    row.button = button
    return button
end

local function UpdateGlyphRow(row, slot)
    if not row or not slot then
        return
    end

    row.slot = slot
    local data = GetGlyphData(slot)
    local button = AttachNativeGlyphButton(row, slot)
    if button and type(GlyphFrameGlyph_UpdateSlot) == "function" then
        pcall(GlyphFrameGlyph_UpdateSlot, button)
    end

    if data.glyphSpell then
        row.text:SetText(data.link or (data.name and ("[" .. data.name .. "]")) or T("settings.general.feature.talent_frame_enhancement.glyph_empty"))
        row.text:SetTextColor(0.32, 0.72, 1)
        row:SetAlpha(1)
    else
        row.text:SetText(T("settings.general.feature.talent_frame_enhancement.glyph_empty"))
        row.text:SetTextColor(0.55, 0.58, 0.62)
        row:SetAlpha(data.enabled and 0.78 or 0.46)
    end
end

local function UpdateGlyphSummary()
    if not LoadGlyphUI() then
        return
    end

    local frame = EnsureGlyphSummary()
    if not frame then
        return
    end

    SuppressGlyphFrameContainer()
    frame:Show()
    local parent = EnsureContentFrame() or PlayerTalentFrame
    frame:SetFrameLevel(parent:GetFrameLevel() + 7)
    for index = 1, 3 do
        if frame.majorRows[index] then
            frame.majorRows[index]:SetFrameLevel(frame:GetFrameLevel() + 1)
        end
        if frame.minorRows[index] then
            frame.minorRows[index]:SetFrameLevel(frame:GetFrameLevel() + 1)
        end
    end

    for index = 1, 3 do
        UpdateGlyphRow(frame.majorRows[index], GLYPH_MAJOR_SLOTS[index])
        UpdateGlyphRow(frame.minorRows[index], GLYPH_MINOR_SLOTS[index])
    end
end

local function HideGlyphSummary()
    if glyphSummary then
        glyphSummary:Hide()
    end
end

local function ApplyFrameChrome()
    if not PlayerTalentFrame then
        return
    end

    PlayerTalentFrame:SetWidth(FRAME_WIDTH)
    PlayerTalentFrame:SetHeight(FRAME_HEIGHT)
    if type(PlayerTalentFrame.SetHitRectInsets) == "function" then
        PlayerTalentFrame:SetHitRectInsets(0, 0, 0, 0)
    end

    local info = UIPanelWindows and UIPanelWindows.PlayerTalentFrame
    if info then
        if not PlayerTalentFrame.yuiTalentEnhancementOriginalPanelAreaCaptured then
            PlayerTalentFrame.yuiTalentEnhancementOriginalPanelArea = info.area
            PlayerTalentFrame.yuiTalentEnhancementOriginalPanelAreaCaptured = true
        end

        -- Blizzard registers this as a left panel; the enhanced frame is much wider.
        info.area = "center"
        info.width = FRAME_WIDTH
        info.height = FRAME_HEIGHT
    end

    EnsureChrome()
    EnsureContentFrame()
    HideBlizzardTalentUI()
    if not PlayerTalentFrame.yuiTalentEnhancementCenteredOnce and PlayerTalentFrame:IsShown() then
        PlayerTalentFrame.yuiTalentEnhancementCenteredOnce = true
        PlayerTalentFrame:ClearAllPoints()
        PlayerTalentFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    if PlayerTalentFrameCloseButton then
        PlayerTalentFrameCloseButton:ClearAllPoints()
        if PlayerTalentFrameCloseButton.SetScale then
            PlayerTalentFrameCloseButton:SetScale(1.18)
        end
        PlayerTalentFrameCloseButton:SetPoint("TOPRIGHT", PlayerTalentFrame, "TOPRIGHT", -20, -18)
        PlayerTalentFrameCloseButton:SetFrameLevel(PlayerTalentFrame:GetFrameLevel() + 20)
        PlayerTalentFrameCloseButton:Show()
    end
end

local function HideCustomUI()
    if PlayerTalentFrame and PlayerTalentFrame.yuiTalentEnhancementChrome then
        PlayerTalentFrame.yuiTalentEnhancementChrome:Hide()
    end
    if contentFrame then
        contentFrame:Hide()
    end
    HideAllTrees()
    HideGlyphSummary()
    HideTopControls()
    if specSwitcher then
        specSwitcher:Hide()
    end

    local info = UIPanelWindows and UIPanelWindows.PlayerTalentFrame
    if info and PlayerTalentFrame and PlayerTalentFrame.yuiTalentEnhancementOriginalPanelAreaCaptured then
        info.area = PlayerTalentFrame.yuiTalentEnhancementOriginalPanelArea
    end
end

local function RefreshTalentEnhancement()
    if not IsEffective() or not initialized or not PlayerTalentFrame then
        return
    end

    ApplyFrameChrome()
    UpdateSpecTabs()
    UpdateSpecSwitcher()
    UpdateTopControls()
    if PlayerTalentFrame.pet then
        HideGlyphSummary()
    else
        UpdateGlyphSummary()
    end

    local parent = EnsureContentFrame() or PlayerTalentFrame
    local numTabs = GetNumTalentTabs(PlayerTalentFrame.inspect, PlayerTalentFrame.pet)
    numTabs = math.min(numTabs or 0, MAX_TALENT_TABS)
    local treeLeft = TREE_LEFT
    if PlayerTalentFrame.pet then
        local totalWidth = (numTabs * TREE_FRAME_WIDTH) + (math.max(numTabs - 1, 0) * TREE_GAP)
        treeLeft = math.floor((FRAME_WIDTH - totalWidth) / 2)
    end
    for tabIndex = 1, numTabs do
        local frame = EnsureTreeFrame(tabIndex)
        frame:SetFrameLevel(parent:GetFrameLevel() + 2)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", treeLeft + ((tabIndex - 1) * (TREE_FRAME_WIDTH + TREE_GAP)), TREE_TOP)
        frame:Show()
        UpdateTreeFrame(frame, tabIndex)
    end

    for tabIndex, frame in pairs(treeFrames) do
        if tabIndex > numTabs then
            frame:Hide()
        end
    end
end

function ScheduleRefresh()
    if refreshScheduled or not IsEffective() then
        return
    end

    refreshScheduled = true
    local function Run()
        refreshScheduled = false
        RefreshTalentEnhancement()
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Run)
    elseif nativeHookActive or glyphClickActive then
        refreshScheduled = false
    else
        Run()
    end
end

local function AfterNativeTalentFrameChanged()
    if nativeHookActive then
        return
    end

    nativeHookActive = true
    if ShouldHideBlizzardUI() then
        SuppressNativeVisuals(true)
    end
    nativeHookActive = false
    ScheduleRefresh()
end

InstallGlyphHooks = function()
    if glyphHooksInstalled or type(hooksecurefunc) ~= "function" or type(_G.GlyphFrame_Update) ~= "function" then
        return
    end

    hooksecurefunc("GlyphFrame_Update", AfterNativeTalentFrameChanged)
    glyphHooksInstalled = true
end

local function InstallHooks()
    if hooksInstalled then
        return
    end

    SafeHook("PlayerTalentFrame_Update", AfterNativeTalentFrameChanged)
    SafeHook("PlayerTalentFrame_Refresh", AfterNativeTalentFrameChanged)
    SafeHook("PlayerTalentFrame_UpdateControls", AfterNativeTalentFrameChanged)
    SafeHook("PlayerTalentFrame_UpdateTabs", AfterNativeTalentFrameChanged)
    SafeHook("PlayerTalentFrame_ShowGlyphFrame", AfterNativeTalentFrameChanged)
    SafeHook("PlayerTalentFrame_HideGlyphFrame", AfterNativeTalentFrameChanged)
    SafeHook("PlayerSpecTab_OnClick", AfterNativeTalentFrameChanged)
    InstallGlyphHooks()

    hooksInstalled = true
end

local function InitializeTalentFrame()
    if initialized or not IsEffective() or not PlayerTalentFrame then
        return
    end

    initialized = true
    EnsureActivationCastEvents()
    if not PlayerTalentFrame.yuiTalentEnhancementShowHookInstalled and type(PlayerTalentFrame.HookScript) == "function" then
        PlayerTalentFrame:HookScript("OnShow", function()
            if PlayerTalentFrame and not PlayerTalentFrame.yuiTalentEnhancementCenteredOnce and PlayerTalentFrame:IsShown() then
                PlayerTalentFrame.yuiTalentEnhancementCenteredOnce = true
                PlayerTalentFrame:ClearAllPoints()
                PlayerTalentFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end)
        PlayerTalentFrame.yuiTalentEnhancementShowHookInstalled = true
    end
    InstallHooks()
    RefreshTalentEnhancement()
end

local function WaitForTalentUI()
    if not IsEffective() then
        return
    end

    if IsAddonLoadedSafe("Blizzard_TalentUI") and PlayerTalentFrame then
        InitializeTalentFrame()
        return
    end

    local System = YUI.API and YUI.API.System
    if System and type(System.LoadAddOn) == "function" then
        pcall(System.LoadAddOn, "Blizzard_TalentUI")
    elseif type(LoadAddOn) == "function" then
        pcall(LoadAddOn, "Blizzard_TalentUI")
    end

    if IsAddonLoadedSafe("Blizzard_TalentUI") and PlayerTalentFrame then
        InitializeTalentFrame()
    end
end

local function ApplyConflictState(options)
    local controller, status = GetConflictAddon(options)
    if isEnabled and status == "active" then
        HideCustomUI()
        if YUI.Yield then
            YUI.Yield:Set("talent", controller, { status = status, enabled = true })
        end
        return true
    end
    if YUI.Yield then YUI.Yield:Clear("talent") end
    return status == "unknown"
end

local function OnEnable(enable)
    isEnabled = enable == true
    if isEnabled and not ApplyConflictState() then
        WaitForTalentUI()
    else
        HideCustomUI()
    end
end

local Feature = {
    localeNamespace = "Core",
    nameKey = "settings.general.feature.talent_frame_enhancement.label",
    descriptionKey = "settings.general.feature.talent_frame_enhancement.text",
    name = T("settings.general.feature.talent_frame_enhancement.label"),
    description = T("settings.general.feature.talent_frame_enhancement.text"),
    tags = { "实用功能" },
    default = true,
    settingsMode = "toggleOnly",
    requiresReload = true,
    callback = OnEnable,
    GetEffectiveState = function()
        local conflictAddon, status = GetConflictAddon()
        if status == "active" or status == "unknown" then
            return {
                effective = false,
                kind = status == "active" and "yield" or nil,
                controller = conflictAddon,
                featureKey = "talent",
                status = status,
                tone = "warning",
            }
        end
        return { effective = true }
    end,
}

Components:RegisterFeature("TalentFrameEnhancement", Feature)

YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
    if not isEnabled then return end
    local blocked = ApplyConflictState({ force = true })
    if not blocked then WaitForTalentUI() end
end, Feature, { moduleId = "component:TalentFrameEnhancement" })

YUI.Event:On("ADDON_LOADED", function(_, addonName)
    if addonName == "Blizzard_TalentUI" then
        InitializeTalentFrame()
    elseif addonName == "Blizzard_GlyphUI" then
        InstallGlyphHooks()
        ScheduleRefresh()
    elseif addonName == "TalentEmuX" then
        ScheduleRefresh()
    end
end)
YUI.Event:On("PLAYER_TALENT_UPDATE", ScheduleRefresh)
YUI.Event:On("PET_TALENT_UPDATE", ScheduleRefresh)
YUI.Event:On("PREVIEW_TALENT_POINTS_CHANGED", ScheduleRefresh)
YUI.Event:On("PREVIEW_PET_TALENT_POINTS_CHANGED", ScheduleRefresh)
YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", ScheduleRefresh)
YUI.Event:On("PLAYER_LEVEL_UP", ScheduleRefresh)
YUI.Event:On("UNIT_PET", function(_, unit)
    if unit == "player" then
        ScheduleRefresh()
    end
end)
YUI.Event:On("GLYPH_ADDED", ScheduleRefresh)
YUI.Event:On("GLYPH_REMOVED", ScheduleRefresh)
YUI.Event:On("GLYPH_UPDATED", ScheduleRefresh)
