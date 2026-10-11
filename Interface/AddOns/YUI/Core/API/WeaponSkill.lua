local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI then return end
YUI.API = YUI.API or {}
local WeaponSkill = {}
YUI.API.WeaponSkill = WeaponSkill

local function IsPublic(value)
    return not issecretvalue or not issecretvalue(value)
end

function WeaponSkill.GetCatalog()
    return YUI.IsForever and YUI.WeaponSkillData or nil
end

function WeaponSkill.GetTrainerSite(id)
    local catalog = WeaponSkill.GetCatalog()
    for _, site in ipairs(catalog and catalog.sites or {}) do
        if site.id == id then return site end
    end
end

-- 只读原生技能，不展开/折叠或选择角色技能页；无持续缓存。
-- 返回 state, rank, maxRank, modifier；不完整/受限数据返回 unavailable。
function WeaponSkill.GetPlayerSkill(skill)
    if not WeaponSkill.GetCatalog() or not skill then return "unavailable" end
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return "unavailable" end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skill.id)
    if not ok or not IsPublic(info) then return "unavailable" end
    local spell = YUI.API.Spell
    local known = spell and spell.IsKnown and spell.IsKnown(skill.spellID)
    if not IsPublic(known) then return "unavailable" end
    if info == nil and known ~= true then
        -- 未登录就绪或接口数据缺失时，不能把全部技能误判为未学习。
        local ready, unarmed = pcall(C_SkillInfo.GetSkillLineInfoByID, 162)
        if not ready or not IsPublic(unarmed) or type(unarmed) ~= "table" then return "unavailable" end
        local unit = YUI.API.Unit
        if not (unit and unit.UnitClass) then return "unavailable" end
        local _, _, classID = unit.UnitClass("player")
        if not IsPublic(classID) or type(classID) ~= "number" or classID < 1 or classID > 32 then return "unavailable" end
        local classBit = 2 ^ (classID - 1)
        if math.floor(skill.classMask / classBit) % 2 == 0 then return "unusable" end
        if known ~= false then return "unavailable" end
        return "unlearned"
    end
    if skill.rankID then
        ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skill.rankID)
        if not ok or not IsPublic(info) then return "unavailable" end
    end
    if type(info) ~= "table" then return "unavailable" end
    local rank, maximum, modifier = info.rank, info.maxRank, info.modifier
    if not IsPublic(rank) or not IsPublic(maximum) or not IsPublic(modifier) then return "unavailable" end
    if type(rank) ~= "number" or type(maximum) ~= "number" or maximum <= 0 or rank < 0 then return "unavailable" end
    if modifier ~= nil and type(modifier) ~= "number" then return "unavailable" end
    return "learned", rank, maximum, modifier or 0
end

-- 两处提示均从结构化训练列表及 Core 本地化生成，不存第二份组合文案。
function WeaponSkill.GetTrainerDescription(siteID)
    local site = WeaponSkill.GetTrainerSite(siteID)
    if not site then return nil end
    local L, lines = YUI.Locale:Get("Core"), {}
    for _, trainer in ipairs(site.trainers) do
        local names = {}
        for _, id in ipairs(trainer.skills) do names[#names+1] = L["weapon_skill.name." .. id] end
        lines[#lines+1] = string.format(L["weapon_trainer.description"], L[trainer.nameKey], table.concat(names, L["weapon_skill.separator"]))
    end
    return table.concat(lines, "\n")
end

-- 可选名称格式化函数分别处理 NPC 与城市；默认返回纯文本，不改变共享数据。
function WeaponSkill.GetLearningLocations(skill, faction, formatTrainerName, formatCityName)
    local catalog = WeaponSkill.GetCatalog()
    if not catalog or not skill then return nil end
    local L, locations = YUI.Locale:Get("Core"), {}
    if skill.sourceKey then return L[skill.sourceKey] end
    if not IsPublic(faction) or (faction ~= "Alliance" and faction ~= "Horde") then return nil end
    for _, site in ipairs(catalog.sites) do
        if site.faction == faction then
            local names = {}
            for _, trainer in ipairs(site.trainers) do
                for _, id in ipairs(trainer.skills) do
                    if id == skill.id then
                        local name = L[trainer.nameKey]
                        names[#names+1] = formatTrainerName and formatTrainerName(name) or name
                        break
                    end
                end
            end
            if #names > 0 then
                local city = L[site.cityKey]
                if formatCityName then city = formatCityName(city) end
                locations[#locations+1] = string.format(L["weapon_trainer.location"], city, table.concat(names, L["weapon_skill.separator"]))
            end
        end
    end
    if #locations > 0 then return table.concat(locations, "\n") end
    return nil
end
