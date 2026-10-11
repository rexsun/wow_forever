local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Sound and YUI.Sound.RuleModel) then return end
local S, Model = YUI.Sound, YUI.Sound.RuleModel
local Store={}
S.RuleStore=Store
local KEY="SoundRules"
local previews=setmetatable({}, {__mode="k"})
local edits=setmetatable({}, {__mode="k"})
local committed=setmetatable({}, {__mode="k"})
local FAMILY_VERSION=1
local familyNotices=setmetatable({}, {__mode='k'})

local function Copy(value)
    if type(value)~="table" then return value end
    local out={}; for k,v in pairs(value) do out[k]=Copy(v) end; return out
end

local function Same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not Same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end

local function Context()
    local DB=YUI.DB
    if not (DB and DB.GetAceDB and DB.GetProfile) then return nil,"db-not-ready" end
    local product=S.storageProductId or (YUI.CoreMode=="suite" and "suite" or YUI.ProductId or "suite")
    local database=DB:GetAceDB(product)
    local profile=DB:GetProfile(product)
    if not (database and profile and database.GetCurrentProfile) then return nil,"profile-unavailable" end
    return {database=database,profile=profile,name=database:GetCurrentProfile()}
end

local function Includes(rule,key)
    for _,value in ipairs(rule.specs or rule.exceptSpecs or {}) do
        if value==key then return rule.specs~=nil end
    end
    return rule.specs==nil
end

-- Configuration-only audit. Current talents and runtime spell APIs are not used.
local function AuditFamilies(rules,migrate)
    Store.familyAuditCount=(Store.familyAuditCount or 0)+1
    local editor=S.EditorModel
    local families,scopes=editor.SpellFamilies,editor.SpellFamilyScopes
    local candidates,canonical={},{}
    for index,rule in ipairs(rules) do
        if rule.object.kind=='spell' and not rule.trigger.extension then
            local relevant=false
            for _,group in pairs(families) do
                for alias,base in pairs(group) do
                    if rule.object.id==alias or rule.object.id==base then relevant=true end
                end
            end
            if relevant then
                candidates[#candidates+1]=index
                local base
                -- A whole rule can be removed only if EVERY applicable spec is confirmed.
                if rule.specs then
                    for _,key in ipairs(rule.specs) do
                        local spec=tonumber(key:match(':(%d+)$'))
                        local target=scopes[spec]==key and families[spec] and families[spec][rule.object.id]
                        if not target or base and base~=target then base=nil;break end
                        base=target
                    end
                end
                canonical[index]=rule
                if base then canonical[index]=Copy(rule);canonical[index].object.id=base end
            end
        end
    end
    local function Related(a,b)
        if a.object.id==b.object.id then return false end
        for id,selected in pairs(a.talents) do
            if b.talents[id]~=nil and b.talents[id]~=selected then return false end
        end
        for spec,group in pairs(families) do
            if Includes(a,scopes[spec]) and Includes(b,scopes[spec])
                and (group[a.object.id] or a.object.id)==(group[b.object.id] or b.object.id) then return true end
        end
        return false
    end
    local removed,notices={},{}
    if migrate then
        for i,index in ipairs(candidates) do
            for j=1,i-1 do
                local other=candidates[j]
                if not removed[index] and not removed[other] and Related(rules[index],rules[other])
                    and Same(canonical[index],canonical[other]) then
                    -- Prefer the existing base-ID rule without changing its settings or order.
                    removed[canonical[index].object.id==rules[index].object.id and other or index]=true
                end
            end
        end
    end
    for i,index in ipairs(candidates) do
        for j=1,i-1 do
            local other=candidates[j]
            if not removed[index] and not removed[other] and Related(rules[index],rules[other]) then
                notices[Model:Key(rules[index])]=true;notices[Model:Key(rules[other])]=true
            end
        end
    end
    local result={}
    for index,rule in ipairs(rules) do if not removed[index] then result[#result+1]=rule end end
    return result,notices,removed
end

local function Read(context)
    local raw=context.profile[KEY]
    if raw==nil then return {},0 end
    if type(raw)~="table" or raw.schemaVersion~=Model.SCHEMA_VERSION
        or type(raw.revision)~="number" or raw.revision<0 or raw.revision%1~=0 then return nil,"invalid-rule-storage" end
    for key in pairs(raw) do
        if key~='schemaVersion' and key~='revision' and key~='rules' and key~='familyMigrationVersion' then return nil,'invalid-rule-storage' end
    end
    if raw.familyMigrationVersion~=nil and raw.familyMigrationVersion~=FAMILY_VERSION then return nil,'invalid-rule-storage' end
    local rules,code=Model:NormalizeLibrary(raw.rules)
    if not rules then return nil,code end
    if YUI.IsRetail and S.EditorModel and S.EditorModel.SpellFamilyScopes then
        local cached=familyNotices[raw]
        if not cached or cached.revision~=raw.revision or cached.rules~=raw.rules then
            local migrate=raw.familyMigrationVersion~=FAMILY_VERSION
            local nextRules,notices,removed=AuditFamilies(rules,migrate)
            if migrate then
                local stored=raw.rules
                if next(removed) then
                    stored={}
                    for index,rule in ipairs(raw.rules) do if not removed[index] then stored[#stored+1]=rule end end
                end
                raw={schemaVersion=raw.schemaVersion,revision=raw.revision+1,rules=stored,familyMigrationVersion=FAMILY_VERSION}
                context.profile[KEY]=raw
                rules=nextRules
            end
            familyNotices[raw]={revision=raw.revision,rules=raw.rules,notices=notices}
        end
    end
    return rules,raw.revision
end

function Store:HasFamilyNotice(rule)
    local context=Context()
    local raw=context and context.profile[KEY]
    local cached=raw and familyNotices[raw]
    return cached and rule.object and rule.object.unit and cached.notices[Model:Key(rule)]==true or false
end

function Store:Read()
    local context,code=Context(); if not context then return nil,code end
    return Read(context)
end

function Store:BeginEdit()
    local context,code=Context(); if not context then return nil,code end
    local rules,revision=Read(context); if not rules then return nil,revision end
    local token={rules=Copy(rules)}
    edits[token]={context=context,rules=rules,revision=revision}
    return token
end

function Store:CommitEdit(token,rules,runtime)
    local guard=edits[token]
    local context,code=Context()
    if not guard or not context or context.database~=guard.context.database or context.profile~=guard.context.profile
        or context.name~=guard.context.name then return nil,'stale-editor' end
    local current,revision=Read(context)
    if not current or revision~=guard.revision or not Same(current,guard.rules) then return nil,'stale-editor' end
    local prepared; prepared,code=self:PrepareImport(rules,'replace')
    if not prepared then return nil,code end
    local ok,detail,failure=self:Commit(prepared,runtime)
    if ok then edits[token]=nil end
    return ok,detail,failure
end

function Store:PrepareImport(incoming,mode)
    local context,code=Context(); if not context then return nil,code end
    local rules,revision=Read(context); if not rules then return nil,revision end
    local nextRules,counts=Model:PrepareImport(rules,incoming,mode)
    if not nextRules then return nil,counts end
    local prepared={context=context,before=Copy(context.profile[KEY]),rules=nextRules,
        revision=revision,counts=counts,consumed=false}
    previews[prepared]={context={database=context.database,profile=context.profile,name=context.name},
        before=Copy(prepared.before),rules=Copy(nextRules),revision=revision}
    return prepared
end

function Store:CheckPrepared(prepared)
    if type(prepared)~="table" or prepared.consumed or type(prepared.context)~="table" then return nil,"stale-preview" end
    local trusted=previews[prepared]
    if not trusted or trusted.context.database~=prepared.context.database
        or trusted.context.profile~=prepared.context.profile or trusted.context.name~=prepared.context.name
        or trusted.revision~=prepared.revision
        or not Same(trusted.rules,prepared.rules) or not Same(trusted.before,prepared.before) then return nil,"stale-preview" end
    local context,code=Context(); if not context then return nil,code end
    local source=prepared.context
    if context.database~=source.database or context.profile~=source.profile or context.name~=source.name
        or not Same(context.profile[KEY],prepared.before) then return nil,"stale-preview" end
    return true
end

function Store:Commit(prepared,runtime)
    if type(InCombatLockdown)=="function" and InCombatLockdown() then return nil,"combat-lockdown" end
    local ok,code=self:CheckPrepared(prepared); if not ok then return nil,code end
    if self.busy then return nil,"busy" end
    local normalized,why=Model:NormalizeLibrary(prepared.rules)
    if not normalized then return nil,why end
    local old=prepared.context.profile[KEY]
    local nextValue={schemaVersion=Model.SCHEMA_VERSION,revision=prepared.revision+1,rules=normalized}
    nextValue.familyMigrationVersion=old and old.familyMigrationVersion
        or YUI.IsRetail and S.EditorModel and S.EditorModel.SpellFamilyScopes and FAMILY_VERSION or nil
    self.busy=true
    prepared.context.profile[KEY]=nextValue
    local applied,result,detail=true,true
    if runtime then applied,result,detail=pcall(runtime.Apply,runtime,normalized) end
    local current=Context()
    local contextChanged=not current or current.database~=prepared.context.database
        or current.profile~=prepared.context.profile or current.name~=prepared.context.name
    if not applied or result==false or result==nil or contextChanged then
        prepared.context.profile[KEY]=old
        local restored,restoreResult=true,true
        local restoreRules=old and Copy(old.rules) or {}
        if contextChanged then restoreRules=current and Read(current) or nil end
        if runtime then
            if restoreRules then restored,restoreResult=pcall(runtime.Apply,runtime,restoreRules)
            elseif runtime.Stop then restored,restoreResult=pcall(runtime.Stop,runtime)
            else restored=false end
        end
        self.busy=nil
        prepared.consumed=true
        previews[prepared]=nil
        return nil,contextChanged and "stale-preview" or "runtime-apply-failed",
            {restored=restored and restoreResult~=false and restoreResult~=nil,reason=applied and detail or result}
    end
    prepared.consumed=true
    committed[prepared]={context=prepared.context,before=old,installed=prepared.context.profile[KEY]}
    previews[prepared]=nil
    self.busy=nil
    if YUI.Event then YUI.Event:Emit("YUI_SOUND_RULES_CHANGED") end
    return true,prepared.counts
end

function Store:Restore(prepared,runtime)
    local state=committed[prepared]
    if not state then return nil,'invalid-restore' end
    local context=Context()
    if not context or context.database~=state.context.database or context.profile~=state.context.profile
        or context.name~=state.context.name or context.profile[KEY]~=state.installed then return nil,'stale-restore' end
    context.profile[KEY]=state.before
    committed[prepared]=nil
    if runtime then
        local called,ok=pcall(runtime.Apply,runtime,state.before and Copy(state.before.rules) or {})
        if not called or ok~=true then return nil,'runtime-restore-failed' end
    end
    if YUI.Event then YUI.Event:Emit('YUI_SOUND_RULES_CHANGED') end
    return true
end

return Store
