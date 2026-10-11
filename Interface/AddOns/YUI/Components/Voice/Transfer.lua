local _, YUI = ...
YUI = _G.YUI or YUI
local S = YUI and YUI.Sound
local Transfer = YUI and YUI.Settings and YUI.Settings.ConfigTransfer
if not (S and S.Runtime and Transfer) or Transfer.modules['core.sound'] then return end
local Model, Store = S.RuleModel, S.RuleStore
local function Copy(raw)
    if type(raw)~='table' then return raw end
    local out={}; for k,v in pairs(raw) do out[k]=Copy(v) end; return out
end
local function Equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not Equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function Scope(raw)
    if type(raw)~='table' or (raw.kind~='profile' and raw.kind~='specs') then return nil,'invalid-sound-scope' end
    for key in pairs(raw) do if key~='kind' and key~='specs' and key~='includeGeneral' then return nil,'invalid-sound-scope' end end
    if raw.kind=='profile' then
        if raw.specs~=nil or raw.includeGeneral~=nil then return nil,'invalid-sound-scope' end
        return {kind='profile'}
    end
    if type(raw.specs)~='table' or #raw.specs>64 or type(raw.includeGeneral)~='boolean' then return nil,'invalid-sound-scope' end
    local specs,seen={},{}
    for key in pairs(raw.specs) do
        if type(key)~='number' or key%1~=0 or key<1 or key>#raw.specs then return nil,'invalid-sound-scope' end
    end
    for _,spec in ipairs(raw.specs) do
        if type(spec)~='string' or not spec:match('^[A-Z]+:%d+$') or seen[spec] then return nil,'invalid-sound-scope' end
        seen[spec]=true; specs[#specs+1]=spec
    end
    table.sort(specs)
    return {kind='specs',specs=specs,includeGeneral=raw.includeGeneral}
end
local function Normalize(payload)
    if type(payload)~='table' then return nil,'invalid-sound-payload' end
    for key in pairs(payload) do if key~='rules' and key~='scope' then return nil,'invalid-sound-payload' end end
    local scope,code=Scope(payload.scope); if not scope then return nil,code end
    local rules; rules,code=Model:NormalizeLibrary(payload.rules); if not rules then return nil,code end
    if scope.kind=='specs' then
        local clipped; clipped,code=Model:Export(rules,scope.specs,scope.includeGeneral)
        if not clipped or not Equal(clipped,rules) then return nil,code or 'sound-outside-scope' end
    end
    return {rules=rules,scope=scope}
end
S.SoundTransfer={Normalize=Normalize}
Transfer:RegisterModule({id='core.sound',kind='core',schemaVersion=1,labelKey='sound.center.title',
    dataPaths={'SoundRules'},maxPayloadNodes=65536,selectedByDefault=false,
    productId=function() return S.storageProductId end,
    capture=function(_,context)
        context=context or {}
        if context.soundSpecs ~= nil and type(context.soundSpecs) ~= 'table' then return nil, 'invalid-sound-scope' end
        for _, provider in pairs(S.LegacyMigration and S.LegacyMigration.providers or {}) do
            if provider.CheckExport then
                local ok, code = provider:CheckExport(context.soundSpecs)
                if not ok then return nil, code end
            end
        end
        local rules,code=Store:Read(); if not rules then return nil,code end
        if context.soundSpecs~=nil then
            local scope; scope,code=Scope({kind='specs',specs=context.soundSpecs,includeGeneral=context.includeGeneralSounds==true})
            if not scope then return nil,code end
            rules,code=Model:Export(rules,scope.specs,scope.includeGeneral)
            if not rules then return nil,code end
            return {rules=rules,scope=scope}
        end
        return {rules=rules,scope={kind='profile'}}
    end,
    normalize=Normalize,
    snapshot=function(_,context,payload)
        local mode=context and context.soundImportMode or (payload.scope.kind=='profile' and 'replace' or 'incremental')
        if mode~='replace' and mode~='incremental' then return nil,'invalid-sound-import-mode' end
        if context and context.previewNewProfile then
            local rules, counts=Model:PrepareImport({},payload.rules,mode)
            if not rules then return nil,counts end
            return {profileName=context.previewNewProfile,counts=counts,mode=mode,scope=Copy(payload.scope)}
        end
        local plan,code=Store:PrepareImport(payload.rules,mode); if not plan then return nil,code end
        return {database=plan.context.database,profileName=plan.context.name,plan=plan,
            counts=Copy(plan.counts),mode=mode,scope=Copy(payload.scope)}
    end,
    validateSnapshot=function(snapshot) return Store:CheckPrepared(snapshot.plan) end,
    apply=function(_,entry)
        local ok,code=Store:Commit(entry.snapshot.plan,S.Runtime)
        entry.snapshot.applied=ok==true
        return ok,code
    end,
    restore=function(snapshot)
        if not snapshot.applied then return true end
        return Store:Restore(snapshot.plan,S.Runtime)
    end,
})
