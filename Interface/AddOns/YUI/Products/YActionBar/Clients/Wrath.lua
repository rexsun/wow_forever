local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

YUI.YActionBar.Client = {
    id = "wrath",
    supported = true,
    ownedStanceButtons = false,
    nativeSpecialButtons = false,
    deterministicSpecialBars = false,
    nonStructuralNativeSuppression = false,
    directUsableRefresh = false,
    assistedCombat = false,
    heldBindings = false,
    professionQuality = false,
    secretRisk = false,
    mainPossess = false,
    vehicleFallbackPage = 12,
    petBattle = "available",
    skyridingVisibility = false,
}
