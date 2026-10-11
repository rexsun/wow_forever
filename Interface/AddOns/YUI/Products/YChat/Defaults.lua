local YUI = _G.YUI
if not YUI then return end

local YChat = YUI.YChat or {}
YUI.YChat = YChat

YChat.PRODUCT_ID = "ychat"
YChat.STORAGE_KEY = "YChat"
YChat.SETTINGS_ENTRY = "ychat.settings"
YChat.VERSION = "0.10.0-retail-slice09"

YChat.Defaults = {
    enabled = false,
    timestamp = {
        enabled = true,
        layout = "column",
        format = "hms",
        color = { 0.62, 0.72, 0.82, 0.95 },
        nativeIndentedWrap = false,
        gap = 6,
    },
    typography = {},
    itemLinks = { enabled = false, cropIcons = true },
    channelInput = {
        nameStyle = "native",
        publicFormat = "numberShort",
        hidePlayerRealm = true,
        customNames = {},
        showNumber = true,
        tabCycle = false,
    },
    autoInvite = {
        enabled = false,
        matchMode = "exact",
        keywords = { "123" },
        allowlist = {},
        denylist = {},
        senderCooldown = 10,
        rateLimit = 5,
        rateWindow = 10,
    },
    history = {
        enabled = false,
        frameLimit = 200,
        limit = 2000,
        restoreOnLogin = false,
        restoreLimit = 50,
        categories = {
            player = true,
            guild = true,
            group = true,
            channel = true,
            whisper = true,
            output = true,
            system = false,
            rewards = false,
            achievement = false,
        },
    },
    appearance = {
        preset = "deep",
        backgroundAlpha = 0.76,
        backgroundColor = { 0.00, 0.00, 0.00, 1.00 },
        borderStyle = "hairline",
        borderWidth = 1,
        borderColor = { 0.86, 0.70, 0.28, 0.90 },
        classColorBorder = false,
        tabStyle = "underline",
        tabTextEffect = "outlineShadow",
        tabFontSize = 14,
        tabWidthMode = "auto",
        tabWidth = 72,
        tabSpacing = 4,
        tabLeftInset = 0,
        classColorTabs = true,
        classColorWhisperNames = true,
        tabColor = { 1.00, 0.82, 0.00, 1.00 },
        hideNativeButtons = true,
        hideCombatLog = false,
        fadeElements = false,
        fadeScope = "solo",
        fadeDelay = 120,
        fadeChatBar = false,
        fadeStatsMode = "none",
        inputPosition = "bottom",
        inputHeight = 32,
        tooltipAnchor = "ANCHOR_RIGHT",
        messageEffect = "fade",
    },
    layout = {},
}

YChat.sessionEnabled = false
YChat.runtimeEnabled = false
YChat.lifecycleListenerCount = 0
YChat.lifecycleDisablePending = false
YChat.productionPendingReason = nil
