local YUI = _G.YUI
if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhTW") then return end
YUI.Locale:Register("ErrorRecorder", "zhTW", {
    ["name"] = "錯誤記錄", ["enable"] = "啟用錯誤記錄", ["minimap"] = "顯示小地圖圖示",
    ["capture_note"] = "關閉檢視器後，仍會收集並儲存錯誤。",
    ["viewer.yield"] = "偵測到 BugSack，已自動避讓檢視器與小地圖圖示。仍會收集並儲存錯誤。",
    ["view"] = "查看錯誤", ["current"] = "本次階段 · %d 筆", ["history"] = "%s · %d 筆",
    ["empty"] = "本次階段沒有錯誤", ["unknown"] = "未知插件", ["related"] = "相關插件：%s",
    ["previous"] = "上一筆", ["next"] = "下一筆", ["copy_all"] = "複製全部", ["copy_hint"] = "Ctrl+C 複製完整錯誤",
    ["copy_focus"] = "點擊正文後 Ctrl+C 複製", ["source.chat"] = "聊天腳本", ["source.native"] = "暴雪介面",
    ["copy.selected"] = "已全選 · Ctrl+C 複製 · Esc 離開",
    ["source.label"] = "來源：%s", ["meta"] = "%s · %s 次 · %s", ["session_meta"] = "%s · %d 筆錯誤 · %s",
    ["stack"] = "呼叫堆疊", ["locals"] = "區域變數", ["recent"] = "%s：%s ×%s",
    ["click_hint"] = "左鍵：最近錯誤 · 右鍵：設定", ["other_hint"] = "Shift+左鍵：重載 · 拖曳：移動",
    ["clear"] = "清空本次", ["more"] = "更多", ["clear_history"] = "清空全部歷史",
    ["clear_confirm"] = "清空本次錯誤和所有歷史記錄？", ["count"] = "本次 %d 筆 · 已儲存 %d 筆",
    ["clear_hint"] = "Alt+左鍵：清空全部錯誤",
    ["left_click"] = "左鍵：查看最近錯誤", ["right_click"] = "右鍵：設定",
    ["reload"] = "Shift+左鍵：重載介面", ["drag"] = "拖曳：移動圖示",
    ["missing"] = "收集器無法使用，請啟用 !YUI_Error 並重載介面。",
    ["conflict"] = "內嵌收集已讓位給 %s；啟用 !BugGrabber 後可使用此檢視器。",
    ["paused"] = "錯誤過於頻繁，收集器正在限流。",
    ["minimum"] = "較早錯誤的次數為已知下限。", ["all_selected"] = "所選階段的全部錯誤",
})
