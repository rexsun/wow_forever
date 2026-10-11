local _, namespace = ...
local YUI = _G.YUI or namespace
local S = YUI and YUI.Sound
if not (S and S.RegisterVoicePack) or S.PackDiagnostics then return end
local D = {}
S.PackDiagnostics = D

local function T(key,...)
    local locale=YUI.Locale and YUI.Locale:Get('Core')
    return string.format(locale and locale['voice.pack.'..key] or key,...)
end
local function Client()
    return YUI.IsRetail and 'mainline' or YUI.IsWrath and 'wrath' or YUI.IsMists and 'mists' or 'unknown'
end
local function InScope(scope,entry)
    if scope.mode=='all' then return true end
    if scope.mode=='sample' then return false end
    return entry.class and scope.classes[entry.class] or not entry.class and scope.general
end
local function Row(id,file)
    return {id=id,name=S:GetEntryLabel(id),file=file or (S.voiceRecordingNames or {})[id] or id}
end

function S:GetVoicePackReport(packId,client)
    client=client or Client()
    local pack=self.voicePacks[packId]
    local rejected=self.rejectedVoicePacks and self.rejectedVoicePacks[packId]
    local report={packId=packId,client=client,registered=pack~=nil,reason=rejected and rejected.code,
        info=self:GetVoicePackInfo(packId),missing={},outside={},newEntries={},unknown={},removed={},
        targetCount=0,mappedCount=0,checkedFileCount=0,files={},manifest=pack and pack.manifest}
    if not pack then return report end
    local manifest=pack.manifest
    report.supported=not pack.clients or pack.clients[client]==true
    if manifest then
        report.supported=report.supported and manifest.scope.clients[client]==true
        report.catalogChanged=manifest.catalogVersion~=self.voiceCatalogVersion
        for _ in pairs(manifest.checkedFiles) do report.checkedFileCount=report.checkedFileCount+1 end
    end
    for id,entry in pairs(self.entries) do
        if entry.clients[client] then
            local expected=report.supported and (not manifest or manifest.expectedEntries[id])
            if expected then
                report.targetCount=report.targetCount+1
                local recording=pack.entries[id]
                if recording then
                    report.mappedCount=report.mappedCount+1
                    report.files[#report.files+1]={id=id,name=self:GetEntryLabel(id),file=recording.file,duration=recording.duration}
                else report.missing[#report.missing+1]=Row(id,manifest and manifest.expectedEntries[id]) end
            elseif manifest and report.supported and not manifest.catalogIds[id] and InScope(manifest.scope,entry) then
                report.newEntries[#report.newEntries+1]=Row(id)
            else report.outside[#report.outside+1]=Row(id) end
        end
    end
    for id in pairs(pack.entries) do
        if not self.entries[id] then report.unknown[#report.unknown+1]=Row(id) end
    end
    if manifest then
        for id,file in pairs(manifest.expectedEntries) do
            if not self.entries[id] then report.removed[#report.removed+1]=Row(id,file) end
        end
    end
    for _,key in ipairs({'missing','outside','newEntries','unknown','removed','files'}) do
        table.sort(report[key],function(a,b) return a.id<b.id end)
    end
    return report
end

function D:Format(report)
    local info=report.info
    local lines={T('title'),T('identity',S:GetVoicePackLabel(report.packId),report.packId),
        T('metadata',info.author or '-',info.version or '-',report.client),
        T('registration',report.registered and T('registered') or report.reason or T('notRegistered'))}
    if report.registered then
        lines[#lines+1]=T('coverage',report.mappedCount,report.targetCount,#report.missing,#report.outside)
        if report.supported==false then lines[#lines+1]=T('unsupported') end
        if report.manifest then
            lines[#lines+1]=T('catalog',report.manifest.catalogVersion,S.voiceCatalogVersion or '-')
            lines[#lines+1]=T('generation',report.manifest.generatedAt or '-',report.checkedFileCount)
        else lines[#lines+1]=T('legacy') end
        for _,section in ipairs({{'missing','missing'},{'newEntries','new'},{'unknown','unknown'},{'removed','removed'}}) do
            lines[#lines+1]=''
            lines[#lines+1]=T(section[2],#report[section[1]])
            for _,row in ipairs(report[section[1]]) do lines[#lines+1]=row.name..'  '..row.id..'  '..row.file end
        end
        lines[#lines+1]=''
        lines[#lines+1]=T('recordings')
        for _,row in ipairs(report.files) do lines[#lines+1]=row.name..'  '..row.id..'  '..tostring(row.duration or '-')..'s  '..tostring(row.file) end
    end
    lines[#lines+1]=''
    lines[#lines+1]=T('boundary')
    lines[#lines+1]=T('commands',report.packId,report.packId)
    return table.concat(lines,'\n')
end

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(message) end
end
local function FindEntry(value)
    if S.entries[value] then return value end
    for id,file in pairs(S.voiceRecordingNames or {}) do if file==value then return id end end
end

function D:Command(message)
    local args={}
    for word in (message or ''):gmatch('%S+') do args[#args+1]=word end
    local prefs=S.GetPreferences and S:GetPreferences()
    local selected=prefs and prefs.voicePackId or 'yui.default'
    local command=args[1]
    if command=='stop' then if S.StopPreview then S:StopPreview() end; Print(T('stopped'));return end
    if command=='list' then
        local ids={}
        for id in pairs(S.voicePacks) do ids[#ids+1]=id end
        for id in pairs(S.rejectedVoicePacks or {}) do if not S.voicePacks[id] then ids[#ids+1]=id end end
        table.sort(ids)
        for _,id in ipairs(ids) do Print(id..'  '..S:GetVoicePackLabel(id)) end
        return
    end
    if command=='play' or command=='forecast' then
        local packId=args[2] or selected
        local ok,code
        if command=='play' then
            local id=FindEntry(args[3] or '')
            if id and S.PreviewVoicePackEntry then ok,code=S:PreviewVoicePackEntry(packId,id)
            else code='unknown-entry' end
        elseif S.PreviewVoicePackForecast then
            local intro=FindEntry(args[3] or 'arcane_soul_prepare.ogg')
            local ending=FindEntry(args[4] or 'arcane_soul.ogg')
            local count=args[5] and tonumber(args[5]) or 3
            if args[5] and not tonumber(args[5]) then code='invalid-forecast-count'
            elseif intro and ending then ok,code=S:PreviewVoicePackForecast(packId,intro,ending,count)
            else code='unknown-entry' end
        else code='voice-service-unavailable' end
        Print(ok and T('auditionStarted') or T('auditionFailed',code or '-'))
        return
    end
    local packId=command or selected
    local report=S:GetVoicePackReport(packId)
    local text=self:Format(report)
    Print(T('identity',S:GetVoicePackLabel(packId),packId))
    Print(T('coverage',report.mappedCount,report.targetCount,#report.missing,#report.outside))
    local settings=YUI.Settings
    if settings and settings.ShowCopyPopup then settings:ShowCopyPopup(T('title'),text)
    else for line in text:gmatch('[^\n]+') do Print(line) end end
end

if SlashCmdList and not SlashCmdList.YUIVOICEPACK then
    _G.SLASH_YUIVOICEPACK1='/yvoicepack'
    SlashCmdList.YUIVOICEPACK=function(message) D:Command(message) end
end
return D
