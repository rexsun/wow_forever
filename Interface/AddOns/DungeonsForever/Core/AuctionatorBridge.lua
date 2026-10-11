-- =============================================================================
-- DungeonsForever · 购物清单导出桥接
-- 把插件内购物清单经拍卖行插件的官方公开 API 推送为其购物清单；
-- 未安装时降级为可复制的导入串弹窗。只对无限服加载。
-- =============================================================================

local _, ns = ...

if not ns.LoadForeverPages then return end

local L = ns.L

local AB = {}
ns.AuctionBridge = AB

local CALLER = "DungeonsForever"

local format = string.format

-- 聊天框反馈（浅金色正文，与本插件其他提示同风格）
local function Say(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage("|cffffd100" .. msg .. "|r")
    end
end

-- 目标插件可用性（公开 API 层，逐级判空，任何一层缺都不硬闯）
function AB.Available()
    return type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
        and type(Auctionator.API.v1.CreateShoppingList) == "function"
end

-- 清单名：[DF] 前缀便于在拍卖行插件的清单列表里一眼认出本插件推的清单
function AB.ListName(profName)
    return format(L["[DF] %s购物清单"], profName or "?")
end

-- 条目搜索串：精确匹配（双引号包裹）+ 数量（末位字段）。
--   目标插件存储格式 = 14 字段 `;` 分隔（queryString;…;tier;expansion;quantity），
--   tier 缺省占位 "#"；有 API 时走 ConvertToSearchString（官方拼装，零格式风险），
--   无 API（降级导出串）时按同一契约 strjoin 手拼。
function AB.SearchString(name, need)
    local quoted = "\"" .. (name or "") .. "\""
    local hasNeed = (type(need) == "number" and need > 0) and true or false
    if AB.Available() and type(Auctionator.API.v1.ConvertToSearchString) == "function" then
        local term = { searchString = name, isExact = true }
        if hasNeed then term.quantity = need end
        local ok, s = pcall(Auctionator.API.v1.ConvertToSearchString, CALLER, term)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    if hasNeed then
        return strjoin(";", quoted, "", "", "", "", "", "", "", "", "", "", "#", "", tostring(need))
    end
    return quoted
end

-- 调公开 API 建清单；成功 true。只收合法名字，空名跳过（不中断整单）
function AB.Import(listName, items)
    if not AB.Available() then return false, "Auctionator not available" end
    local strings = {}
    for _, e in ipairs(items) do
        if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then
            strings[#strings + 1] = AB.SearchString(e.name, e.need)
        end
    end
    local ok, err = pcall(Auctionator.API.v1.CreateShoppingList, CALLER, listName, strings)
    if ok then return true end
    return false, err
end

-- 降级导出串：拍卖行插件原生批量导入格式「清单名^物品1^物品2」（单行一条清单）
function AB.ExportString(listName, items)
    local parts = { listName }
    for _, e in ipairs(items) do
        if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then
            parts[#parts + 1] = AB.SearchString(e.name, e.need)
        end
    end
    return table.concat(parts, "^")
end

-- 降级弹窗：全选可复制（同 DungeonUI ShowSourceURL 的 StaticPopup 口径）
local POPUP = "DungeonsForever_AuctionImport"
local pendingImportText = ""
function AB.ShowCopy(text)
    pendingImportText = text or ""
    if not StaticPopupDialogs[POPUP] then
        StaticPopupDialogs[POPUP] = {
            text = L["未检测到 Auctionator，请复制以下导入串"],
            button1 = L["关闭"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            hasEditBox = true,
            editBoxWidth = 320,
            OnShow = function(self)
                local edit = self.EditBox or self.editBox
                edit:SetText(pendingImportText)
                edit:HighlightText()
                edit:SetFocus()
            end,
            EditBoxOnEnterPressed = function(self)
                self:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(self)
                self:GetParent():Hide()
            end,
        }
    end
    StaticPopup_Show(POPUP)
end

-- 一键导入主入口（ProfFollow 两个按钮共用）
function AB.DoImport(profName, items)
    if not (type(items) == "table" and #items > 0) then
        Say(L["购物清单为空，没有可导入的物品"])
        return
    end
    local listName = AB.ListName(profName)
    if AB.Available() then
        local ok, err = AB.Import(listName, items)
        if ok then
            Say(format(L["已导入 Auctionator：%s（共 %d 种）"], listName, #items))
        else
            Say(L["导入失败："] .. tostring(err or "?"))
        end
        return
    end
    -- 未装目标插件：降级为导入串弹窗（提示去其购物清单页粘贴）
    AB.ShowCopy(AB.ExportString(listName, items))
    Say(L["未检测到 Auctionator，请在 Auctionator → 购物清单 → 导入 中粘贴"])
end
