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
        function SetCVar(k,v) record(k) end
        function GetCVar(k) return 'source:' .. k end
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
        function print() end
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
    lua.execute('handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(active==4); assert(calls.eui==1); assert(calls.chatSave==1); handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(calls.layout==1)')
    print('PASS every login syncs despite a saved revision; zone transitions do not repeat it')
    lua = world()
    lua.execute('combat=true; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not next(calls)); assert(not CharacterUIBaselineDB.revision); combat=false; handlers.event(nil,"PLAYER_REGEN_ENABLED"); flush(); assert(CharacterUIBaselineDB.revision==2)')
    print('PASS combat defers every write until combat ends')
    lua = world()
    lua.execute('missing=true; handlers.event(nil,"PLAYER_ENTERING_WORLD"); for i=1,35 do flush() end; assert(not next(calls)); assert(not CharacterUIBaselineDB.revision); assert(#timers==0); missing=false; SlashCmdList.CHARACTERUIBASELINE("apply"); flush(); assert(CharacterUIBaselineDB.revision==2)')
    print('PASS missing layout uses bounded retries and supports explicit reapply')
    lua = world()
    lua.execute('editing=true; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not next(calls)); editing=false; flush(); assert(CharacterUIBaselineDB.revision==2); SlashCmdList.CHARACTERUIBASELINE("apply"); flush(); assert(calls.eui==2)')
    print('PASS active layout editing defers writes and manual reapply works')
    for w, h in ((1920,1080),(2560,1440),(3840,2160)):
        lua = world()
        lua.execute(f'width={w};height={h};handlers.event(nil,"PLAYER_ENTERING_WORLD");flush();assert(math.abs(lastX-width*.005375)<.001);assert(math.abs(lastY-height*.028333)<.001);assert(lastWidth==475 and lastHeight==265)')
    print('PASS normalized chat placement at all three resolutions')
    lua = world(source=True)
    lua.execute('active=4; handlers.event(nil,"PLAYER_ENTERING_WORLD"); flush(); assert(not next(calls)); handlers.event(nil,"PLAYER_LOGOUT"); assert(not next(calls)); local d=CharacterUIBaselineAccountDB; assert(d.sourceKey=="source-key"); assert(d.baseline.chatFontSize==20); assert(d.baseline.cvars.showQuestLevel=="source:showQuestLevel"); assert(d.baseline.euiPositions.partyUnlockPos.x==10); assert(d.baseline.nativeLayout=="old-ui"); assert(not d.baseline.specProfiles and not d.baseline.talents)')
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
        baseline.nativeLayout='source-ui';missing=true
        EllesmereUI={ApplyPresetEditMode=function(text,name)
            assert(text=='source-ui' and name=='YUI v3');nativeString=text;missing=false;record('import');return true end}
        handlers.event(nil,'PLAYER_ENTERING_WORLD');flush();assert(calls.import==1 and active==4)
        SlashCmdList.CHARACTERUIBASELINE('apply');flush();assert(calls.import==1)
    ''')
    print('PASS source native layout is imported when missing or different without repeated identical imports')
    lua = world(source=True)
    lua.execute('''
        active=1
        EditModePresetLayoutManager={GetCopyOfPresetLayouts=function() return {{layoutName='Modern'},{layoutName='Classic'}} end}
        handlers.event(nil,'PLAYER_LOGOUT')
        assert(CharacterUIBaselineAccountDB.baseline.presetLayout==1)
    ''')
    lua = world()
    lua.execute("baseline.presetLayout=1;baseline.nativeLayout='preset-ui';handlers.event(nil,'PLAYER_ENTERING_WORLD');flush();assert(active==1 and calls.eui==1 and not calls.import)")
    print('PASS built-in source layouts are captured and selected without importing a custom layout')


if __name__ == '__main__':
    run()
