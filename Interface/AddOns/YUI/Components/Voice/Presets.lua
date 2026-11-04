local _,YUI=...
YUI=_G.YUI or YUI
if not (YUI and (YUI.IsRetail or YUI.IsForever) and YUI.Sound) then return end
local S=YUI.Sound
local P={}
S.Presets=P
local requests=setmetatable({},{__mode='k'})
local function Copy(t) return S.EditorModel.Copy(t) end
local function Includes(rule,key)
    for _,value in ipairs(rule.specs or rule.exceptSpecs or {}) do if value==key then return rule.specs~=nil end end
    return rule.specs==nil
end
function P:Rows() return S.PresetCatalog and S.PresetCatalog.rows or {} end
function P:DefaultSelection(class)
    local selected={}
    for _,row in ipairs(self:Rows()) do
        if row.section=='class' and row.class==class and row.core then selected[row.key]=true end
    end
    return selected
end
function P:Availability(row)
    -- Save reusable presets independently of the current character's abilities.
    -- Runtime resolution still requires a known racial spell before binding it.
    if row.section=='events' then
        local api=YUI.API.SoundEvents
        if not api or not api.Available(row.rule.object.id) then return nil,'source-unavailable' end
    end
    local entry=S.entries[row.rule.sound.value] or S.factionVoices and S.factionVoices[row.rule.sound.value]
    local client=YUI.IsForever and 'forever' or 'mainline'
    if not entry or not entry.clients or not entry.clients[client] then return nil,'unsupported-entry-client' end
    return true
end
-- The imported review lists only approved identities. Do not query current
-- talents/CDM to decide whether another class's stored preset should exist.
function P:Equivalent(a,b)
    local function Key(rule,spec)
        local value=Copy(rule)
        if value.object.kind=='spell' then value.object.id=S.EditorModel:CanonicalSpellID(value.object.id,spec) end
        return S.RuleModel:Key(value)
    end
    local scopes=a.specs or b.specs
    if scopes then
        local matched=false
        for _,key in ipairs(scopes) do
            if Includes(a,key) and Includes(b,key) then
                matched=true
                local spec=tonumber(key:match(':(%d+)$'))
                if Key(a,spec)~=Key(b,spec) then
                    if not YUI.IsForever or a.object.kind~=b.object.kind or a.object.unit~=b.object.unit then return false end
                    local same=false
                    for _,row in ipairs(self:Rows()) do
                        if row.class==key:match('^([^:]+):') and row.rule.object.kind==a.object.kind then
                            local ids=row.aliases or {row.rule.object.id}
                            local left,right=false,false
                            for _,id in ipairs(ids) do left=left or a.object.id==id;right=right or b.object.id==id end
                            if left and right then
                                local copy=Copy(a);copy.object.id=b.object.id
                                same=S.RuleModel:Key(copy)==S.RuleModel:Key(b)
                                if same then break end
                            end
                        end
                    end
                    if not same then return false end
                end
            end
        end
        return matched
    end
    return false
end
function P:Prepare(selected,enabled)
    if type(selected)~='table' or enabled~=nil and type(enabled)~='boolean' then return nil,'invalid-selection' end
    local incoming,unavailable,known,available={},{},{},{}
    for _,row in ipairs(self:Rows()) do
        known[row.key]=true
        if selected[row.key] then
            local ok,code=self:Availability(row)
            if ok then local rule=Copy(row.rule);rule.enabled=enabled~=false;incoming[#incoming+1]=rule;available[#available+1]=row
            else unavailable[#unavailable+1]={key=row.key,code=code} end
        end
    end
    for key,value in pairs(selected) do if value and not known[key] then return nil,'invalid-selection' end end
    local prepared,code=S.RuleStore:PrepareImport(incoming,'missing',function(a,b) return self:Equivalent(a,b) end)
    if not prepared then return nil,code end
    prepared.counts.unavailable=#unavailable
    prepared.unavailable=unavailable
    local outcomes,byKey={},{}
    for i,row in ipairs(available) do
        local item=prepared.items[i]
        byKey[row.key]={row=row,status=item.added>0 and 'add' or 'keep',added=item.added,
            partial=item.partial,rules=item.rules,kept=item.kept}
    end
    for _,item in ipairs(unavailable) do byKey[item.key]={status='skip',code=item.code} end
    for _,row in ipairs(self:Rows()) do
        local item=byKey[row.key]
        if item then item.row=row;outcomes[#outcomes+1]=item end
    end
    prepared.outcomes=outcomes
    requests[prepared]=available
    return prepared
end
function P:Commit(prepared)
    local ok,code=S.RuleStore:CheckPrepared(prepared)
    if not ok or not requests[prepared] then return nil,code or 'stale-preview' end
    -- Event/voice capabilities can change while reviewing.
    for _,row in ipairs(requests[prepared]) do if not self:Availability(row) then return nil,'stale-preview' end end
    if prepared.counts.added==0 then return S.RuleStore:CheckPrepared(prepared) end
    return S.RuleStore:Commit(prepared,S.Runtime)
end
