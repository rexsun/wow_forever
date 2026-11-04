local YUI = _G.YUI
local GUI2 = YUI and YUI.GUI2
if not GUI2 or GUI2.PaintIconPressedVisual then return end

-- Shared by action buttons and passive icon monitors; geometry stays with the owner.
do
    local innerColor = { 1, 0.78, 0.18, 0.95 }
    local fallbackColor = { 1, 1, 1, 0.24 }
    function GUI2:PaintIconPressedVisual(state, shape, colors, innerTexture)
        local texture = state and state.pressedOverlay
        if not texture then return 0 end
        if self.IsIconSkinManaged and self:IsIconSkinManaged(texture) then return 0 end
        local effect = state.pressedEffect == "innerGlow" and "innerGlow" or "darken"
        local path = effect == "innerGlow" and (innerTexture or self:GetIconStateInnerTexture(shape)) or nil
        local color = effect == "innerGlow" and innerColor or colors and colors.pressed or fallbackColor
        if state.pressedVisualMode == effect and state.pressedTexturePath == path
            and state.pressedColor == color then return 0 end
        local writes = 0
        if path then
            texture:SetTexture(path)
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
            texture:SetBlendMode("ADD")
            writes = 2
        else
            texture:SetBlendMode("BLEND")
            texture:SetColorTexture(color[1], color[2], color[3], color[4])
            writes = 1
        end
        local alpha = effect == "innerGlow" and 0.95 or 0.28
        texture:SetAlpha(alpha)
        texture.yabNativeVisualAlpha = alpha
        texture.yabTexturePath, texture.yabTextureAtlas = path, nil
        state.pressedVisualMode, state.pressedTexturePath, state.pressedColor = effect, path, color
        return writes + 1
    end
end
-- End shared icon press painter.
