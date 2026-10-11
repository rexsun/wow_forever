local _, YUI = ...

local Icons = YUI.API and YUI.API.Icons
local Assets = YUI.Assets
if not Icons or not Assets then
    return
end

Icons.RegisterIconSet({
    id = "YUISpec1",
    name = "YUI 幻彩",
    nameKey = "settings.appearance.icons.yuispec1",
    detailsLabel = "YUI 幻彩",
    order = 10,
    texture = Assets:Bundle("spec-icons", "YUISpec1.blp"),
    specCoords = true,
    custom = true,
})
