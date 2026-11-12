local YUI = _G.YUI
if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhCN") then return end
YUI.Locale:Register("ErrorRecorder", "zhCN", {
    ["name"] = "报错记录", ["enable"] = "启用报错记录", ["minimap"] = "显示小地图图标",
    ["capture_note"] = "关闭查看器后，仍会收集并保存报错。",
    ["viewer.yield"] = "检测到 BugSack，已自动避让查看器与小地图图标。仍会收集并保存报错。",
    ["view"] = "查看报错", ["current"] = "本次会话 · %d 条", ["history"] = "%s · %d 条",
    ["empty"] = "本次会话没有报错", ["unknown"] = "未知插件", ["related"] = "相关插件：%s",
    ["previous"] = "上一条", ["next"] = "下一条", ["copy_all"] = "复制全部", ["copy_hint"] = "Ctrl+C 复制完整报错",
    ["copy_focus"] = "点击正文后 Ctrl+C 复制", ["source.chat"] = "聊天脚本", ["source.native"] = "暴雪界面",
    ["copy.selected"] = "已全选 · Ctrl+C 复制 · Esc 退出",
    ["source.label"] = "来源：%s", ["meta"] = "%s · %s 次 · %s", ["session_meta"] = "%s · %d 条报错 · %s",
    ["stack"] = "调用栈", ["locals"] = "局部变量", ["recent"] = "%s：%s ×%s",
    ["click_hint"] = "左键：最近报错 · 右键：设置", ["other_hint"] = "Shift+左键：重载 · 拖动：移动",
    ["clear"] = "清空本次", ["more"] = "更多", ["clear_history"] = "清空全部历史",
    ["clear_confirm"] = "清空本次报错和所有历史记录？", ["count"] = "本次 %d 条 · 已保存 %d 条",
    ["clear_hint"] = "Alt+左键：清空全部报错",
    ["left_click"] = "左键：查看最近报错", ["right_click"] = "右键：设置",
    ["reload"] = "Shift+左键：重载界面", ["drag"] = "拖动：移动图标",
    ["missing"] = "收集器不可用，请启用 !YUI_Error 并重载界面。",
    ["conflict"] = "内嵌收集已让位给 %s；启用 !BugGrabber 后可使用此查看器。",
    ["paused"] = "报错过于频繁，收集器正在限流。",
    ["minimum"] = "较早报错的次数为已知下限。", ["all_selected"] = "所选会话的全部报错",
})
