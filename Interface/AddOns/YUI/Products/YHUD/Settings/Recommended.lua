local YUI = _G.YUI
local HUD = YUI and YUI.YHUD
if not HUD then return end
local Library = { entries = {} }
HUD.Recommended = Library

-- Curated, shipped content only. Keep empty until real configurations are approved.
-- Each entry: id, name, author, description, optional product-relative image, share.
function Library:Describe(entry)
    if type(entry)~='table' or type(entry.id)~='string' or entry.id==''
        or type(entry.name)~='string' or type(entry.author)~='string'
        or type(entry.description)~='string' or type(entry.share)~='string'
        or (entry.image~=nil and type(entry.image)~='string') then
        return nil,'invalid-recommendation'
    end
    local transfer=YUI.Settings.ConfigTransfer
    local parsed,code=transfer:ParseImportString(entry.share)
    if not parsed then return nil,code end
    local graph=parsed.byId[HUD.Sharing.MODULE_ID]
    if not graph or graph.status~='ready' then return nil,'graph-unavailable' end
    for _,item in ipairs(parsed.modules) do
        if item.status~='ready' or (item.id~=HUD.Sharing.MODULE_ID and item.id~='core.sound') then return nil,'unsupported-recommendation-module' end
    end
    local payload; payload,code=HUD.Sharing.Normalize(HUD:CopyValue(graph.rawPayload))
    if not payload then return nil,code end
    local count=0
    local sound=parsed.byId['core.sound']
    if sound then
        if HUD.Client and HUD.Client.soundReminders == false
            or not (YUI.Sound and YUI.Sound.SoundTransfer) then
            return nil,'sound-unavailable-client'
        end
        local normalized
        normalized,code=YUI.Sound.SoundTransfer.Normalize(HUD:CopyValue(sound.rawPayload))
        if not normalized then return nil,code end
        count=#normalized.rules
    end
    return {entry=entry, specs=payload.scope.kind=='specs' and payload.scope.specs or payload.recommendedSpecs,
        full=payload.scope.kind=='full', soundCount=count}
end

function Library:List()
    local rows,seen={},{}
    for _,entry in ipairs(self.entries) do
        local row,code=self:Describe(entry)
        local id=type(entry)=='table' and entry.id
        if id and seen[id] then row,code=nil,'duplicate-recommendation' end
        if type(id)=='string' then seen[id]=true end
        rows[#rows+1]=row or {entry=type(entry)=='table' and entry or {},error=code}
    end
    return rows
end
