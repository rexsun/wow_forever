local YUI=_G.YUI
local YAB=YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars) then return end
local S={rosterDirty=true,pending={}}
YAB.SoulstoneBinding=S
local Unit,Safe=YUI.API.Unit,YUI.API.Security
local function Queue() YAB.BarManager:QueueSpecialRefresh("warlockTools","soulstone-binding") end
function S:Prepare(entry)
    if YAB.Adapter:InCombat() then return end
    if not entry.enabled then return self:Stop() end
    self.active=true
    if self.rosterDirty or self.stale then
        local members,complete
        if Unit.ReadGroupMembers then members,complete=Unit.ReadGroupMembers() end
        local player=Unit.GetDisplayNameInfo and Unit.GetDisplayNameInfo("player")
        self.playerName=player and Safe.SafeString(player.displayName)
        self.units,self.pending={},{}
        for _,member in ipairs(members or {}) do
            if member.name~=self.playerName then
                local class=Safe.SafeString(member.class) or (Unit.GetClassToken and Unit.GetClassToken(member.unit))
                self.units[member.unit]={name=member.name,class=class}
                self.pending[member.unit]=true
            end
        end
        self.stale,self.rosterDirty=(not members or complete==false),nil
        if self.binding then
            if self.stale then self.binding.unit,self.binding.unknown=nil,true
            else
                -- Roster slots can change; only the confirmed full name owns this clock.
                local boundUnit
                for unit,member in pairs(self.units) do
                    if member.name==self.binding.name then
                        boundUnit=unit
                        member.class=member.class or self.binding.class
                        self.binding.class=member.class
                        break
                    end
                end
                if boundUnit then
                    if self.binding.unit~=boundUnit then self.binding.unknown=true end
                    self.binding.unit=boundUnit
                else self.binding=nil end
            end
        end
        self.groupAuraActive=next(self.units)~=nil
    end
end
function S:OnUnitAura(unit)
    unit=Safe.SafeString(unit)
    if self.active and self.units and self.units[unit] then self.pending[unit]=true;Queue() end
end
function S:Refresh()
    if not self.active then return end
    local now=YUI.API.System and Safe.SafeNumber(YUI.API.System.GetTime())
    if self.binding and now and self.binding.expirationTime<=now then self.binding=nil end
    if self.stale then if self.binding then self.binding.unknown=true end;return end
    local spell=YUI.API.Spell.GetInfo(20765)
    local name=spell and Safe.SafeString(spell.name)
    if not name or not Unit.ReadHelpfulTimersByName then return end
    for unit in pairs(self.pending) do
        self.pending[unit]=nil
        local auras,unknown=Unit.ReadHelpfulTimersByName(unit,{[name]="soulstone"})
        local aura=auras and auras.soulstone
        if not auras or unknown and unknown.soulstone then
            if self.binding and self.binding.unit==unit then self.binding.unknown=true end
        elseif aura and aura.sourceUnit=="player" and aura.duration and aura.expirationTime then
            local member=self.units[unit]
            self.binding={unit=unit,name=member.name,class=member.class,duration=aura.duration,expirationTime=aura.expirationTime}
        elseif self.binding and self.binding.unit==unit then
            if aura and (not aura.sourceUnit or aura.sourceUnit=="player") then self.binding.unknown=true else self.binding=nil end
        end
    end
end
function S:OnEvent(event)
    local restrictionsChanged=event=="ADDON_RESTRICTION_STATE_CHANGED"
    if (event=="PLAYER_REGEN_ENABLED" or restrictionsChanged) and self.units then
        for unit in pairs(self.units) do self.pending[unit]=true end
    end
    local recoverRoster=self.stale and (event=="PLAYER_REGEN_ENABLED" or restrictionsChanged and not YAB.Adapter:InCombat())
    if event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" or recoverRoster then
        self.rosterDirty=true
        if YAB.Adapter:InCombat() then self.stale=true end
        YAB.ClassBars.configDirty.warlockTools=true
    end
end
function S:Stop()
    self.active,self.binding,self.units,self.groupAuraActive=nil,nil,nil,nil
    self.pending,self.rosterDirty={},true
end
