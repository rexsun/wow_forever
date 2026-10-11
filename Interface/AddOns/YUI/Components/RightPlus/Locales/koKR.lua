local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("koKR") then return end

YUI.Locale:Register("RightPlus", "koKR", {
    ["feature.name"] = "우클릭 메뉴 기능",
    ["feature.description"] = "플레이어 우클릭 메뉴에 친구 및 길드 기능을 추가합니다.",
})
