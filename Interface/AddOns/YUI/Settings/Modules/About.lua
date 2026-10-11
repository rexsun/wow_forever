local YUI = _G.YUI
local S = YUI.Settings
local API = YUI.WOW_API
local SystemAPI = YUI.API and YUI.API.System or API
local LC = YUI.Locale:Get("Core")
local Assets = YUI.Assets

local function GetActiveProduct()
    return YUI.Products and YUI.Products[S.ActiveProductId] or nil
end

local function GetProductLogo(product)
    local logo = product and product.smallLogo
    if not logo or logo == "" then
        logo = product and product.logo
    end
    if logo and logo ~= "" then
        if logo:find("^Interface\\") or logo:find("^Interface/") then
            return logo
        end
        return Assets:Product(product.id, logo)
    end
    return Assets:Core("images\\YUI-LOGO-300.png")
end

local function GetConfig()
    local product = GetActiveProduct() or {}
    local addonName = product.addonName or YUI.AddonName or "YUI"
    local version = product.version or SystemAPI.GetAddOnMetadata(addonName, "Version") or "Unknown"
    local title = YUI.GetProductTitle and YUI:GetProductTitle(product) or product.title or "YUI"
    local author = product.author or "阿言"
    local notes = YUI.GetProductNotes and YUI:GetProductNotes(product) or product.notes or LC["settings.about.default_notes"]
    local relationship = product.id == "suite"
        and LC["settings.about.suite_note"]
        or LC["settings.about.standalone_note"]
    local sectionTitle = product.id == "suite"
        and LC["settings.about.section.yui"]
        or LC["settings.about.section.product"]

    return {
        { type = "row", children = {
             { type = "image", width = 32, height = 32, texture = GetProductLogo(product) },
             { type = "header", label = title, width = 540 },
        }},
        { type = "space", height = 12 },
        { type = "text", width = 600, label = string.format(LC["settings.about.details"], notes, version, author), justify = "LEFT", wrap = true },
        { type = "space", height = 8 },
        { type = "text", width = 600, label = relationship, colorKey = "color.text.secondary", justify = "LEFT", wrap = true },
        { type = "space", height = 10 },
        { type = "divider", label = sectionTitle, alignLeft = true, width = 600 },
        { type = "text", width = 600, label = LC["settings.about.follow"], colorKey = "color.text.secondary", justify = "LEFT", wrap = true },
        { type = "row", children = {
            { type = "button", label = LC["settings.copy_bilibili"], width = 160, onClick = function()
                S:ShowCopyPopup(LC["settings.copy_bilibili"], "https://space.bilibili.com/43313099")
            end },
            { type = "button", label = LC["settings.copy_douyin_id"], width = 140, onClick = function()
                S:ShowCopyPopup(LC["settings.copy_douyin_id"], "https://www.douyin.com/user/MS4wLjABAAAA-JzrkAy8gbpvF_bEuKTwuzZk5E85QwKPp9NBmeEEI5AOgYwoHA_WC3sqeGS3s9DX")
            end },
        }},
    }
end

local function Render(parent)
    S:RenderConfig(parent, GetConfig())
end

S:RegisterModule(LC["settings.modules.about"], "Interface\\Icons\\INV_Misc_Note_02", Render, { id = "core.about", product = "core", scope = "core", standaloneOnly = true, titleKey = "settings.modules.about" })
