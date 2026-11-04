local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

YUI.YActionBar.Client = {
    id = "mainline",
    petEmptySlots = true,
    supported = true,
    ownedStanceButtons = true,
    nativeSpecialButtons = true,
    deterministicSpecialBars = true,
    nonStructuralNativeSuppression = true,
    directUsableRefresh = true,
    assistedCombat = true,
    assistedHighlight = true,
    heldBindings = true,
    professionQuality = true,
    secretRisk = true,
    mainPossess = true,
    vehicleFallbackPage = 16,
    petBattle = true,
    skyridingVisibility = true,
}
