local _, namespace = ...
local YUI = _G.YUI or namespace
local Eligibility = {}
Eligibility.__index = Eligibility
YUI.Sound.SpellEligibility = Eligibility

function Eligibility.Applies(rule)
    return YUI.IsRetail and rule.object.kind=='spell' and not rule.trigger.extension
        and (rule.trigger.event=='ready' or rule.trigger.event=='charge')
end

local function CanonicalID(id)
    local editor=YUI.Sound.EditorModel
    if editor and editor.CanonicalSpellID then return editor:CanonicalSpellID(id,editor:CurrentSpec()) end
    return id
end

local function PublicBoolean(value)
    if issecretvalue and issecretvalue(value) then return end
    if type(value)=='boolean' then return value end
end

-- Diagnostic values are observations, never inputs to eligibility decisions.
local function Trace(registry,phase,key,record,observed,previous,decision,reason)
    local timing=YUI.Sound.DebugTiming
    if not (timing and timing.enabled) then return end
    timing:WatchSpell(key);timing:WatchSpell(record.base);timing:WatchSpell(record.id)
    timing:Record('eligibility-'..phase,key,timing:Identity(registry),record.base,record.id,
        observed,previous,record.state,record.origin,decision,reason)
end

local function Known(id,cache,generation)
    local entry=cache and cache[id]
    if entry and entry.generation==generation then return entry.value,entry.origin end
    local api=YUI.API and YUI.API.Spell
    local value,origin,player,pet
    if api and api.GetKnownState then
        player=PublicBoolean(api.GetKnownState(id))
        if player==true then value,origin=true,'player'
        else
            pet=PublicBoolean(api.GetKnownState(id,true))
            if pet==true then value,origin=true,'pet'
            elseif player==false and pet==false then value=false end
        end
    end
    local timing=YUI.Sound.DebugTiming
    if timing and timing.enabled then
        timing:Record('eligibility-read',id,player,player==true and 'not-read' or pet,value,origin)
    end
    if cache then
        if not entry then entry={};cache[id]=entry end
        entry.generation,entry.value,entry.origin=generation,value,origin
    end
    return value,origin
end

local function Read(base,id,cache,generation)
    local known,origin=Known(id,cache,generation)
    if known==true or base==id then return known,origin end
    -- Granted replacements can be absent from the book while their base is known.
    local original,originalOrigin=Known(base,cache,generation)
    if original==true then return true,originalOrigin end
    if known==false and original==false then return false end
end

-- Each applied context owns its registry. Staging never mutates the applied
-- registry, so a failed source acquisition can restore the previous context.
function Eligibility.New(spec,previous,preserve,owner)
    return setmetatable({spec=spec,records={},cache={},generation=1,owner=owner,
        previous=preserve and previous and previous.spec==spec and previous or nil},Eligibility)
end

function Eligibility:Track(rule,id)
    if not Eligibility.Applies(rule) or self.records[rule.object.id] then return end
    local key,base=rule.object.id,CanonicalID(rule.object.id)
    local state,origin=Read(base,id,self.cache,self.generation)
    local observed=state
    local old=self.previous and self.previous.records[key]
    if state==nil and old and old.id==id and old.base==base then state,origin=old.state,old.origin end
    self.records[key]={base=base,id=id,state=state,origin=origin}
    Trace(self,'track',key,self.records[key],observed,old and old.state,
        observed==nil and state~=nil and 'unknown-retained' or 'observed')
end

function Eligibility:Finish()
    self.previous=nil
end

function Eligibility:Reset()
    self.records,self.cache,self.previous={},{},nil
end

function Eligibility:BeginObservation()
    self.generation=self.generation+1
end

-- Also tracks excluded/waiting skills: unknown -> true must wake reconciliation.
-- Reuse query slots across events; duplicate rules/aliases share one batch read.
function Eligibility:Refresh(key,id,petChanged,reason)
    local record=self.records[key]
    if not record then return false end
    local base=CanonicalID(key)
    local reset=petChanged and record.origin=='pet'
    local state,origin=Read(base,id,self.cache,self.generation)
    local observed,previous=state,record.state
    if state==nil and not reset and record.id==id and record.base==base then state,origin=record.state,record.origin end
    local changed=reset or state~=record.state or record.id~=id or record.base~=base
    record.id,record.base,record.state,record.origin=id,base,state,origin
    Trace(self,'refresh',key,record,observed,previous,reset and 'pet-reset'
        or observed==nil and state~=nil and 'unknown-retained' or 'observed',reason)
    return changed
end

-- Admission and last-moment verification share this policy. Unknown only
-- inherits trust within the same context and identity; it cannot grant trust.
function Eligibility.Allows(context,rule,id,fresh)
    if not Eligibility.Applies(rule) then return true end
    local registry=context and context.eligibility
    local record=registry and registry.records[rule.object.id]
    if not record then
        local known
        if not registry then known=Read(CanonicalID(rule.object.id),id) end
        local timing=YUI.Sound.DebugTiming
        if timing and timing.enabled then
            timing:Record('eligibility-missing',rule.object.id,timing:Identity(registry),id,fresh,known)
        end
        return known==true,known==false and 'spell-not-known' or 'spell-known-unknown'
    end
    if record.id~=id then
        Trace(registry,'veto',rule.object.id,record,'not-read',record.state,'spell-identity-changed',id)
        return false,'spell-identity-changed'
    end
    local observed,previous,revoked='not-read',record.state,false
    if fresh and record.state==true then
        local known,origin=Read(record.base,id)
        observed=known
        if known==true then record.origin=origin
        elseif known==false then
            record.state,record.origin=false,nil
            revoked=true
        end
    end
    Trace(registry,fresh and 'check' or 'admit',rule.object.id,record,observed,previous,
        record.state==true and 'allow' or record.state==false and 'spell-not-known' or 'spell-known-unknown')
    if revoked and registry.owner then registry.owner:OnEligibilityRevoked(rule.object.id) end
    return record.state==true,record.state==false and 'spell-not-known' or 'spell-known-unknown'
end

return Eligibility
