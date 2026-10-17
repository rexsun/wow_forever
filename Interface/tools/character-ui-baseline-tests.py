from pathlib import Path
from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'AddOns/CharacterUIBaseline/Bootstrap.lua'


def world(source=False, saved=False):
    lua = lua51.LuaRuntime()
    lua.execute('''
        calls, timers, handlers = {}, {}, {}
        function record(k) calls[k] = (calls[k] or 0) + 1 end
        function CreateFrame() return {RegisterEvent=function() end,
            SetScript=function(_,_,fn) handlers.event=fn end} end
        C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
        function flush() local list=timers timers={} for _,fn in ipairs(list) do fn() end end
        function InCombatLockdown() return combat == true end
        cvarValues={}
        function SetCVar(k,v) record(k) cvarValues[k]=v end
        function GetCVar(k) return cvarValues[k] or ('source:' .. k) end
        function GetRealmName() return 'Test Realm' end
        function UnitNameUnmodified() return playerName or 'Alt', 'Surname' end
        function GetServerTime() return 12345 end
        function GetChatWindowInfo() return 'General', 20 end
        C_EditMode={GetLayouts=function() return {activeLayout=active or 3,
            layouts=missing and {} or {{layoutName='Other'},{layoutName='YUI v3'}}} end,
            SetActiveLayout=function(index) active=index record('layout') end,
            ConvertLayoutInfoToString=function() return nativeString or 'old-ui' end}
        Enum={EditModePresetLayoutsMeta={NumValues=2}}
        EditModeManagerFrame={IsInitialized=function() return true end,
            IsEditModeActive=function() return editing == true end,
            HasActiveChanges=function() return false end}
        ChatFrame1={ClearAllPoints=function() end,
            SetPoint=function(_,_,_,_,x,y) lastX,lastY=x,y end,
            SetSize=function(_,w,h) lastWidth,lastHeight=w,h end,
            GetLeft=function() return 100 end, GetBottom=function() return 80 end,
            GetWidth=function() return 500 end, GetHeight=function() return 280 end,
            GetEffectiveScale=function() return 1 end}
        function FCF_SetChatWindowFontSize(_,_,size) record('font') end
        function FCF_SavePositionAndDimensions() record('chatSave') end
        UIParent={GetWidth=function() return width or 1920 end,
            GetHeight=function() return height or 1080 end,
            GetEffectiveScale=function() return 1 end}
        EllesmereUIDB={activeProfile='Spec UI',specProfiles={healer='Spec UI'},
            profiles={['Spec UI']={addons={EllesmereUIRaidFrames={
                partyUnlockPos={point='CENTER',relPoint='CENTER',x=10,y=20},
                talentChoice='keep',specOverrides={test=true}}}}}}
        function _ERF_RefreshAll() record('eui') end
        printed={}
        function print(m) printed[#printed+1]=m end
        SlashCmdList={}
        baseline={revision=2,layoutName='YUI v3',cvars={showQuestLevel='1'},
            source={enabled=true,key='source-key',character='Source-Surname',realmName='Test Realm'},
            chatFontSize=18,chat={x=.005375,y=.028333,width=475,height=265}}
    ''')
    if source:
        lua.execute("playerName='Source'")
    if saved:
        lua.execute('CharacterUIBaselineDB={revision=99}')
    lua.execute(SOURCE.read_text(), 'CharacterUIBaseline', lua.globals().baseline)
    return lua


def run():
    lua = world(saved=True)
    lua.execute('handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(calls.eui==1); assert(calls.chatSave==1); handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(calls.eui==1); assert(not calls.layout)')
    print('PASS every login syncs despite a saved revision; zone transitions do not repeat it')
    lua = world()
    lua.execute('combat=true; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not next(calls)); assert(not CharacterUIBaselineDB.revision); combat=false; handlers.event(nil,"PLAYER_REGEN_ENABLED"); flush(); assert(CharacterUIBaselineDB.revision==2)')
    print('PASS combat defers every write until combat ends')
    lua = world()
    lua.execute('width=0; handlers.event(nil,"PLAYER_ENTERING_WORLD"); for i=1,35 do flush() end; assert(not next(calls)); assert(not CharacterUIBaselineDB.revision); assert(#timers==0); width=1920; SlashCmdList.CHARACTERUIBASELINE("apply"); flush(); assert(CharacterUIBaselineDB.revision==2); SlashCmdList.CHARACTERUIBASELINE("apply"); flush(); assert(calls.eui==2)')
    print('PASS unavailable UI uses bounded retries and supports explicit reapply')
    lua = world()
    lua.execute('cvarValues.showQuestLevel="1"; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not calls.showQuestLevel); assert(calls.eui==1)')
    print('PASS CVars already at the source value are not rewritten')
    for w, h in ((1920,1080),(2560,1440),(3840,2160)):
        lua = world()
        lua.execute(f'width={w};height={h};handlers.event(nil,"PLAYER_ENTERING_WORLD");flush();assert(math.abs(lastX-width*.005375)<.001);assert(math.abs(lastY-height*.028333)<.001);assert(lastWidth==475 and lastHeight==265)')
    print('PASS normalized chat placement at all three resolutions')
    lua = world(source=True)
    lua.execute('active=4; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not next(calls)); handlers.event(nil,"PLAYER_LOGOUT"); assert(not next(calls)); local d=CharacterUIBaselineAccountDB; assert(d.sourceKey=="source-key"); assert(d.baseline.chatFontSize==20); assert(d.baseline.cvars.showQuestLevel=="source:showQuestLevel"); assert(d.baseline.euiPositions.partyUnlockPos.x==10); assert(d.baseline.layoutName=="YUI v3" and not d.baseline.nativeLayout); assert(not d.baseline.specProfiles and not d.baseline.talents)')
    print('PASS source login is not overwritten and logout publishes whitelisted UI values')
    lua = world()
    lua.execute('''
        CharacterUIBaselineAccountDB={sourceKey='source-key',baseline={revision=2,layoutName='YUI v3',
            cvars={showQuestLevel='updated',talentChoice='BAD'},chatFontSize=22,
            chat={x=.1,y=.2,width=600,height=300},
            euiPositions={partyUnlockPos={point='CENTER',relPoint='CENTER',x=42,y=55},specOverrides={BAD=true}},
            specProfiles={BAD=true},talents={BAD=true}}}
        handlers.event(nil,'PLAYER_ENTERING_WORLD');flush()
        assert(lastWidth==600 and lastHeight==300 and lastX==192 and lastY==216)
        assert(not calls.talentChoice)
        assert(EllesmereUIDB.activeProfile=='Spec UI' and EllesmereUIDB.specProfiles.healer=='Spec UI')
        local p=EllesmereUIDB.profiles['Spec UI'].addons.EllesmereUIRaidFrames
        assert(p.partyUnlockPos.x==42 and p.specOverrides.test and not p.specOverrides.BAD and p.talentChoice=='keep')
    ''')
    print('PASS latest same-account publication is used without applying spec/talent or profile assignments')
    lua = world()
    lua.execute("baseline.source.key='new-key';CharacterUIBaselineAccountDB={sourceKey='old-key',baseline={}};handlers.event(nil,'PLAYER_ENTERING_WORLD');flush();assert(lastWidth==475)")
    print('PASS a changed configured source ignores the previous source publication')
    lua = world()
    lua.execute("baseline.source.enabled=false;handlers.event(nil,'PLAYER_ENTERING_WORLD');flush();assert(not next(calls))")
    print('PASS disabled configuration performs no UI writes')
    lua = world()
    lua.execute('''
        baseline.nativeLayout='source-ui';baseline.presetLayout=1;active=1
        EditModePresetLayoutManager={GetCopyOfPresetLayouts=function() return {{layoutName='Modern'},{layoutName='Classic'}} end}
        EllesmereUI={ApplyPresetEditMode=function() record('import') return true end}
        handlers.event(nil,'PLAYER_ENTERING_WORLD');flush()
        assert(not calls.layout and not calls.import and active==1 and calls.eui==1)
        local found
        for _,m in ipairs(printed) do if m:find("'Modern'",1,true) and m:find("'YUI v3'",1,true) then found=true end end
        assert(found)
    ''')
    lua = world()
    lua.execute("active=4;handlers.event(nil,'PLAYER_ENTERING_WORLD');flush();assert(#printed==1 and not calls.layout)")
    print('PASS Edit Mode layouts are never selected or imported; a mismatch is reported once')
    lua = world(source=True)
    lua.execute('''
        active=1
        EditModePresetLayoutManager={GetCopyOfPresetLayouts=function() return {{layoutName='Modern'},{layoutName='Classic'}} end}
        handlers.event(nil,'PLAYER_ENTERING_WORLD');handlers.event(nil,'PLAYER_LOGOUT')
        local d=CharacterUIBaselineAccountDB.baseline
        assert(d.presetLayout==1 and d.layoutName=='Modern' and not d.nativeLayout)
    ''')
    print('PASS built-in source layouts are captured by name without a native layout export')
    lua = world(source=True)
    lua.execute('''
        EditModePresetLayoutManager={GetCopyOfPresetLayouts=function() return {{layoutName='Modern'},{layoutName='Classic'}} end}
        active=3;handlers.event(nil,'PLAYER_ENTERING_WORLD');active=4;handlers.event(nil,'EDIT_MODE_LAYOUTS_UPDATED')
        active=1;handlers.event(nil,'PLAYER_LOGOUT')
        local d=CharacterUIBaselineAccountDB.baseline
        assert(d.layoutName=='YUI v3' and not d.presetLayout)
    ''')
    lua = world(source=True)
    lua.execute("handlers.event(nil,'PLAYER_LOGOUT');assert(not CharacterUIBaselineAccountDB.baseline)")
    print('PASS the source publishes the layout last seen in the world, not the logout-time preset')

if __name__ == '__main__':
    run()
