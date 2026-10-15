local _, YUI = ...
YUI = _G.YUI or YUI
if not YUI then return end
YUI.Sound = YUI.Sound or {}
local M = {}
YUI.Sound.RuleModel = M
M.SCHEMA_VERSION = 1
M.MAX_RULES = 512

local function Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Copy(v) end
    return out
end

local function Number(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function Set(values)
    if values == nil then return nil end
    if type(values) ~= "table" or #values == 0 or #values > 64 then return nil, "invalid-range" end
    local result, seen = {}, {}
    for key in pairs(values) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #values then return nil, "invalid-range" end
    end
    for _, value in ipairs(values) do
        if type(value) ~= "string" or not value:match("^[A-Z]+:%d+$") then return nil, "invalid-range" end
        if not seen[value] then result[#result + 1], seen[value] = value, true end
    end
    table.sort(result)
    return result
end

local EVENTS = {
    ready=true, cooldownStarted=true, charge=true, cast=true, castAfter=true,
    auraAdded=true, auraRemoved=true, auraRemaining=true, auraStacks=true, auraStackUp=true, auraStackDown=true,
    timerStarted=true, timerEnded=true, timerRemaining=true,
    totemAdded=true, totemRemoved=true,
}
local KINDS = { spell=true, spellGroup=true, aura=true, item=true, slot=true, itemGroup=true, equipmentAura=true, totem=true }
local ALLOWED = { object=true, trigger=true, specs=true, exceptSpecs=true, enabled=true, sound=true, talents=true, category=true }

function M:DefaultLossDelay(object)
    return object.kind=='aura' and object.id==188290 and 168 or 0
end

function M:Normalize(raw)
    if type(raw) ~= "table" then return nil, "invalid-rule" end
    for k in pairs(raw) do if not ALLOWED[k] then return nil, "unknown-rule-field" end end
    local o, t = raw.object, raw.trigger
    if type(o) ~= "table" or not KINDS[o.kind] or type(t) ~= "table" or not EVENTS[t.event] then
        return nil, "invalid-trigger"
    end
    for k in pairs(o) do if k~="kind" and k~="id" and k~="unit" then return nil,"invalid-object-field" end end
    for k in pairs(t) do if k~="event" and k~="value" and k~="operator" and k~="extension" and k~='duration' and k~='policy' and k~='lossDelay' then return nil,"invalid-trigger-field" end end
    if t.lossDelay~=nil and (t.event~='auraRemoved' or not Number(t.lossDelay)
        or t.lossDelay<0 or t.lossDelay>60000 or t.lossDelay%1~=0) then return nil,'invalid-threshold' end
    local timer=t.event=='timerStarted' or t.event=='timerEnded' or t.event=='timerRemaining'
    if timer then
        if (o.kind~='spell' and o.kind~='spellGroup') or not Number(t.duration) or t.duration<=0 or t.duration>86400
            or (t.policy~='ignore' and t.policy~='restart' and t.policy~='parallel') then return nil,'invalid-timer' end
    elseif t.duration~=nil or t.policy~=nil then return nil,'unexpected-timer' end
    local bone=t.extension=='bone-shield'
    if bone and (o.kind~='spell' or o.id~=195181 or t.event~='castAfter' or not Number(t.value) or t.value<1 or t.value>15 or t.value%1~=0) then return nil,'invalid-threshold' end
    local window=t.extension=='boiling-point'
    if window and (o.kind~='spell' or (o.id~=1265968 and o.id~=1265982) or t.event~='castAfter' or t.value~=0 or (o.unit and o.unit~='player')) then return nil,'invalid-window-trigger' end
    if window then o={kind=o.kind,id=1265968,unit=o.unit} end -- Normalize the former event-window preset without touching YHUD.
    if t.extension~=nil and not window and not bone and (t.extension~='arcane-soul' or o.kind~='spell' or o.id~=365350
        or (o.unit and o.unit~='player') or t.event~='castAfter' or t.value~=0) then return nil,'invalid-cast-extension' end
    if o.kind=='spellGroup' then
        if o.id~='burst-potion' or not timer or t.duration~=30 or t.policy~='restart' then return nil,'invalid-group' end
    elseif o.kind == "itemGroup" then
        if o.id ~= "health-potion" and o.id ~= "burst-potion" then return nil,"invalid-group" end
    elseif not Number(o.id) or o.id < 1 or o.id % 1 ~= 0 then return nil,"invalid-object" end
    if o.kind=="equipmentAura" and ((o.id~=13 and o.id~=14) or (o.unit and o.unit~="player") or (t.event~="auraAdded" and t.event~="auraRemoved")) then return nil,"invalid-equipment-aura" end
    if o.kind == "slot" and o.id ~= 13 and o.id ~= 14 then return nil,"invalid-slot" end
    local unit=o.unit or (o.kind=='aura' and 'cdm' or 'player')
    -- Unit selection is no longer part of these rules. Discard former UI values
    -- when reading the unreleased draft library, instead of blocking every edit.
    if o.kind=='aura' and (unit=='player' or unit=='target' or unit=='focus') then unit='cdm' end
    if o.kind=='spell' and (t.event=='cast' or t.event=='castAfter')
        and (unit=='target' or unit=='focus') then unit='player' end
    if o.kind=='totem' and (unit~='player' or (t.event~='totemAdded' and t.event~='totemRemoved')) then return nil,'invalid-trigger-object' end
    if o.kind=='aura' then
        if unit~='cdm' then return nil,'invalid-unit' end
    elseif unit~='player' then return nil,'invalid-unit' end
    if o.kind=='itemGroup' and t.event~='ready' then return nil,'invalid-trigger-object' end
    if (o.kind=="item" or o.kind=="itemGroup" or o.kind=="slot")
        and ((t.event~="ready" and t.event~='cooldownStarted') or unit~="player") then
        return nil,"invalid-trigger-object"
    end
    if o.kind=="spell" and not (timer or t.event=="ready" or t.event=='cooldownStarted' or t.event=="charge" or t.event=="cast" or t.event=="castAfter") then
        return nil,"invalid-trigger-object"
    end
    if o.kind=="spell" and (t.event=="ready" or t.event=='cooldownStarted' or t.event=="charge") and unit~="player" then
        return nil,"invalid-trigger-object"
    end
    if o.kind=="aura" and not t.event:match("^aura") then return nil,"invalid-trigger-object" end
    local trigger={event=t.event,extension=t.extension,duration=t.duration,policy=t.policy}
    -- Delay changes an existing loss rule, not its identity during imports.
    if t.event=='auraRemoved' then
        -- Missing fields in old libraries inherit the creation default. Keep
        -- explicit zero so opting out survives reload and import normalization.
        if t.lossDelay~=nil then trigger.lossDelay=t.lossDelay
        elseif self:DefaultLossDelay(o)>0 then trigger.lossDelay=self:DefaultLossDelay(o) end
    end
    if t.event=="castAfter" or t.event=="auraRemaining" or t.event=="auraStacks" or t.event=='timerRemaining' then
        if not Number(t.value) or t.value < 0 or t.value > 86400 then return nil,"invalid-threshold" end
        trigger.value=t.value
        if t.event=='timerRemaining' and t.value>=t.duration then return nil,'invalid-threshold' end
        if t.event=="auraStacks" then
            if t.value%1~=0 or (t.operator~="ge" and t.operator~="le") then return nil,"invalid-threshold" end
            trigger.operator=t.operator
        elseif t.operator~=nil then return nil,"invalid-operator" end
    elseif t.value~=nil or t.operator~=nil then return nil,"unexpected-threshold" end
    local specs, code=Set(raw.specs)
    if code then return nil,code end
    local exceptSpecs
    if raw.exceptSpecs~=nil then
        if specs~=nil then return nil,"invalid-range-complement" end
        exceptSpecs,code=Set(raw.exceptSpecs)
        if code then return nil,code end
    end
    if raw.enabled~=nil and type(raw.enabled)~="boolean" then return nil,"invalid-enabled" end
    if raw.category~=nil and raw.category~='class' and raw.category~='general' then return nil,'invalid-category' end
    local category=raw.category or ((o.kind=='item' or o.kind=='itemGroup' or o.kind=='spellGroup' or o.kind=='slot') and 'general' or 'class')
    local racial=YUI.API and YUI.API.Racial
    local member=racial and racial.GetEntry(o.id,o.kind)
    if member then category='general'; specs=nil; exceptSpecs=nil end
    local sound=raw.sound
    if type(sound)~="table" then return nil,"invalid-sound" end
    for k in pairs(sound) do
        if k~="kind" and k~="value" and not ((sound.kind=='forecast' or sound.kind=='eventWindow' or sound.kind=='boneShield') and (k=='ending' or k=='countdown' or k=='gap'
            or k=='introKind' or k=='endingKind' or k=='introDuration')) then return nil,"invalid-sound-field" end
    end
    if sound.kind~="voice" and sound.kind~="system" and sound.kind~="tts" and sound.kind~="custom" and sound.kind~="lsm" and sound.kind~='forecast' and sound.kind~='eventWindow' and sound.kind~='boneShield' then return nil,"invalid-sound-kind" end
    if (sound.introKind~='none' or (sound.kind~='forecast' and sound.kind~='eventWindow' and sound.kind~='boneShield')) and (type(sound.value)~="string" or sound.value=="" or #sound.value>2048) then return nil,"invalid-sound-value" end
    local function VoiceReference(value)
        if YUI.Sound.IsVoiceReference then return YUI.Sound:IsVoiceReference(value) end
        return type(value)=='string' and value:match('^VC%-%x%x%x%x%x%x%x%x$')~=nil
    end
    if sound.kind=="voice" and not VoiceReference(sound.value) then return nil,"invalid-voice-id" end
    if (sound.kind=='forecast')~=(t.extension=='arcane-soul') then return nil,'invalid-forecast-trigger' end
    if (sound.kind=='eventWindow')~=(t.extension=='boiling-point') then return nil,'invalid-window-trigger' end
    if (sound.kind=='boneShield')~=bone then return nil,'invalid-window-trigger' end
    if sound.kind=='forecast' or sound.kind=='eventWindow' or sound.kind=='boneShield' then
        local function ValidPart(kind,value)
            return kind=='none' and (value==nil or value=='') or (kind=='voice' or kind=='system' or kind=='lsm') and type(value)=='string' and value~='' and #value<=2048
                and (kind~='voice' or VoiceReference(value))
        end
        if not ValidPart(sound.introKind==nil and 'voice' or sound.introKind,sound.value)
            or not ValidPart(sound.endingKind==nil and 'voice' or sound.endingKind,sound.ending)
            or sound.kind=='forecast' and (not Number(sound.countdown) or sound.countdown<1 or sound.countdown>10 or sound.countdown%1~=0
            or not Number(sound.gap) or sound.gap<0 or sound.gap>10) then return nil,'invalid-forecast-sound' end
        if sound.introDuration~=nil and (not Number(sound.introDuration) or sound.introDuration<=0 or sound.introDuration>86400) then
            return nil,'invalid-forecast-duration'
        end
        if (sound.kind=='eventWindow' or sound.kind=='boneShield') and (sound.countdown~=nil or sound.gap~=nil or sound.introDuration~=nil) then return nil,'invalid-window-sound' end
        if sound.kind=='forecast' and sound.introKind~='none' and (sound.introKind or 'voice')~='voice' and not sound.introDuration then return nil,'invalid-forecast-duration' end
    end
    local talents={}
    if raw.talents~=nil then
        if type(raw.talents)~="table" then return nil,"invalid-talents" end
        local n=0
        for id, selected in pairs(raw.talents) do
            n=n+1
            if n>32 or not Number(id) or id%1~=0 or id<1 or type(selected)~="boolean" then return nil,"invalid-talents" end
            talents[id]=selected
        end
    end
    if (window or bone) and (not specs or #specs~=1 or specs[1]~='DEATHKNIGHT:250') then return nil,'invalid-window-load' end
    if t.extension=='arcane-soul' and (not specs or #specs~=1 or specs[1]~='MAGE:62' or talents[449619]~=true) then
        return nil,'invalid-forecast-load'
    end
    return {object={kind=o.kind,id=o.kind=='spell' and member and member.spellID or o.id,unit=unit},trigger=trigger,specs=specs,exceptSpecs=exceptSpecs,
        enabled=raw.enabled~=false,sound=Copy(sound),talents=talents,category=category}
end

-- Thresholds describe distinct trigger edges. Talent predicates select a variant
-- of that edge and are replaced together with the complete imported rule.
function M:Key(rule)
    local o,t=rule.object,rule.trigger
    -- One paired preset per load scope; editing its lead time must not duplicate
    -- the independent Ossuary removal registration during incremental import.
    if t.extension=='bone-shield' then return 'spell:195181:player:bone-shield' end
    local key=o.kind..":"..tostring(o.id)..":"..o.unit..":"..t.event..":"..tostring(t.value or "")..":"..(t.operator or "")
    if t.duration then key=key..':'..t.duration..':'..t.policy end
    return t.extension and key..':'..t.extension or key
end

local function Contains(values,value)
    for _,v in ipairs(values or {}) do if v==value then return true end end
    return false
end

local function Includes(rule,spec)
    return rule.specs and Contains(rule.specs,spec) or rule.specs==nil and not Contains(rule.exceptSpecs,spec)
end

local function ScopeIntersection(a,b)
    if a.specs or b.specs then
        local result={}
        for _,spec in ipairs(a.specs or b.specs) do
            if Includes(a,spec) and Includes(b,spec) then result[#result+1]=spec end
        end
        return #result>0 and {specs=result} or nil
    end
    local excluded={}
    for _,spec in ipairs(a.exceptSpecs or {}) do excluded[#excluded+1]=spec end
    for _,spec in ipairs(b.exceptSpecs or {}) do if not Contains(excluded,spec) then excluded[#excluded+1]=spec end end
    table.sort(excluded)
    return {exceptSpecs=#excluded>0 and excluded or nil}
end

local function Intersect(a,b)
    if not ScopeIntersection(a,b) then return false end
    for id,selected in pairs(a.talents) do
        if b.talents[id]~=nil and b.talents[id]~=selected then return false end
    end
    return true
end

local function WithScope(rule,scope)
    local out=Copy(rule)
    out.specs=scope.specs and Copy(scope.specs) or nil
    out.exceptSpecs=scope.exceptSpecs and Copy(scope.exceptSpecs) or nil
    return out
end

-- Difference preserves unknown future specializations and unselected talent
-- contexts. It never enumerates the client's present specialization catalog.
local function Subtract(old,new)
    if not Intersect(old,new) then return {old} end
    local shared=ScopeIntersection(old,new)
    local outside
    if old.specs then
        local keep={}
        for _,spec in ipairs(old.specs) do if not Includes(new,spec) then keep[#keep+1]=spec end end
        if #keep>0 then outside={specs=keep} end
    elseif new.specs then
        local excluded=Copy(old.exceptSpecs or {})
        for _,spec in ipairs(new.specs) do if not Contains(excluded,spec) then excluded[#excluded+1]=spec end end
        table.sort(excluded); outside={exceptSpecs=excluded}
    else
        local keep={}
        for _,spec in ipairs(new.exceptSpecs or {}) do if Includes(old,spec) then keep[#keep+1]=spec end end
        if #keep>0 then outside={specs=keep} end
    end
    local result={}
    if outside then result[#result+1]=WithScope(old,outside) end
    local intersection=WithScope(old,shared)
    local ids={}
    for id in pairs(new.talents) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
        if intersection.talents[id]==nil then
            local branch=Copy(intersection)
            branch.talents[id]=not new.talents[id]
            result[#result+1]=branch
            intersection.talents[id]=new.talents[id]
        end
    end
    return result
end

local function Same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not Same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end

function M:NormalizeLibrary(rules)
    if type(rules)~="table" or #rules>self.MAX_RULES then return nil,"invalid-library" end
    for k in pairs(rules) do if type(k)~="number" or k%1~=0 or k<1 or k>#rules then return nil,"invalid-library" end end
    local out={}
    for i,raw in ipairs(rules) do
        local rule,code=self:Normalize(raw)
        if not rule then return nil,code,i end
        local key=self:Key(rule)
        for j,other in ipairs(out) do
            if key==self:Key(other) and Intersect(rule,other) then
                return nil,"conflicting-entry",{first=j,second=i}
            end
        end
        out[#out+1]=rule
    end
    return out
end

function M:Export(rules, selectedSpecs, includeGeneral)
    local normalized,code=self:NormalizeLibrary(rules)
    if not normalized then return nil,code end
    -- Empty selection never expands into an unrestricted export.
    if type(selectedSpecs)~="table" or #selectedSpecs==0 then
        if includeGeneral~=true then return {} end
        selectedSpecs={}
    else
        selectedSpecs,code=Set(selectedSpecs); if code then return nil,code end
    end
    local out={}
    for _,rule in ipairs(normalized) do
        if rule.specs==nil then
            if includeGeneral==true then out[#out+1]=rule end
        else
            local clipped={}
            for _,spec in ipairs(rule.specs) do
                for _,selected in ipairs(selectedSpecs) do if spec==selected then clipped[#clipped+1]=spec; break end end
            end
            if #clipped>0 then rule.specs=clipped; out[#out+1]=rule end
        end
    end
    return out
end

function M:PrepareImport(current, incoming, mode)
    if mode~="incremental" and mode~="replace" then return nil,"invalid-import-mode" end
    local existing,code=self:NormalizeLibrary(current)
    if not existing then return nil,code end
    local imported,detail=self:NormalizeLibrary(incoming)
    if not imported then return nil,detail end
    if mode=="replace" then return imported,{replaceAll=true,removed=#existing,added=#imported} end
    local result,counts={}, {added=0,updated=0,preserved=0,unchanged=0}
    for _,old in ipairs(existing) do
        local remaining={Copy(old)}
        for _,new in ipairs(imported) do
            if self:Key(old)==self:Key(new) then
                local nextRemaining={}
                for _,part in ipairs(remaining) do
                    for _,piece in ipairs(Subtract(part,new)) do nextRemaining[#nextRemaining+1]=piece end
                end
                remaining=nextRemaining
            end
        end
        for _,part in ipairs(remaining) do result[#result+1]=part; counts.preserved=counts.preserved+1 end
    end
    for _,new in ipairs(imported) do
        local matched,unchanged=false,false
        for _,old in ipairs(existing) do
            if self:Key(old)==self:Key(new) and Intersect(old,new) then
                matched=true; unchanged=Same(old,new); break
            end
        end
        local field=unchanged and "unchanged" or matched and "updated" or "added"
        counts[field]=counts[field]+1
        result[#result+1]=new
    end
    if #result>self.MAX_RULES then return nil,"rule-budget-exceeded" end
    return result,counts
end

return M
