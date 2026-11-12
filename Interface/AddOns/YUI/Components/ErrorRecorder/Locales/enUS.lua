local YUI = _G.YUI
if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("enUS") then return end
YUI.Locale:Register("ErrorRecorder", "enUS", {
    ["name"] = "Error Recorder", ["enable"] = "Enable Error Recorder", ["minimap"] = "Show minimap icon",
    ["capture_note"] = "Capture and history continue when the viewer is disabled.",
    ["viewer.yield"] = "BugSack is active. YUI's viewer and minimap icon yield to it; capture and history continue.",
    ["view"] = "View errors", ["current"] = "Current session · %d reports", ["history"] = "%s · %d reports",
    ["empty"] = "No errors in this session", ["unknown"] = "Unknown addon", ["related"] = "Related addons: %s",
    ["previous"] = "Previous", ["next"] = "Next", ["copy_all"] = "Copy all", ["copy_hint"] = "Ctrl+C · Copy full report",
    ["copy_focus"] = "Click report · Ctrl+C to copy", ["source.chat"] = "Chat script", ["source.native"] = "Blizzard UI",
    ["copy.selected"] = "Selected · Ctrl+C copy · Esc exit",
    ["source.label"] = "Source: %s", ["meta"] = "%s · %s occurrences · %s", ["session_meta"] = "%s · %d reports · %s",
    ["stack"] = "Stack", ["locals"] = "Locals", ["recent"] = "%s: %s ×%s",
    ["click_hint"] = "Left: latest error · Right: settings", ["other_hint"] = "Shift-left: reload · Drag: move",
    ["clear"] = "Clear current", ["more"] = "More", ["clear_history"] = "Clear all history",
    ["clear_confirm"] = "Clear current errors and all saved sessions?", ["count"] = "Current: %d reports · Saved: %d",
    ["clear_hint"] = "Alt-left click: clear all errors",
    ["left_click"] = "Left click: latest error", ["right_click"] = "Right click: settings",
    ["reload"] = "Shift-left click: reload UI", ["drag"] = "Drag: move icon",
    ["missing"] = "Collector unavailable. Enable !YUI_Error and reload UI.",
    ["conflict"] = "Embedded capture yielded to %s. Enable !BugGrabber to use this viewer.",
    ["paused"] = "Capture is throttled during an error storm.",
    ["minimum"] = "Early error count is a minimum.", ["all_selected"] = "All reports in the selected session",
})
