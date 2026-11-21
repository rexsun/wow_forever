from pathlib import Path
from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'AddOns/CharacterUIBaseline/Bootstrap.lua'
LAYOUT = ROOT / 'AddOns/CharacterUIBaseline/EditModeLayout.lua'
QUIET = ROOT / 'AddOns/CharacterUIBaseline/QuietLogin.lua'


def world(source=False, saved=False):
    lua = lua51.LuaRuntime()
    lua.execute('''
        calls, timers, handlers = {}, {}, {}
        function record(k) calls[k] = (calls[k] or 0) + 1 end
        frameSlot='layout'
        function CreateFrame() local slot=frameSlot return {RegisterEvent=function() end,
            SetScript=function(_,_,fn) handlers[slot]=fn end} end
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
    lua.execute(LAYOUT.read_text(), 'CharacterUIBaseline', lua.globals().baseline)
    lua.execute("frameSlot='event'")
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
        assert(not calls.layout and not calls.import and active==1 and calls.eui==1 and #printed==1)
    ''')
    print('PASS the login sync never selects or imports Edit Mode layouts')
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


def layout_world(active=1, names=('Other', 'rex'), saved=None, ready=True, group=1):
    lua = world()
    lua.execute(f'''
        active={active}; specGroup={group}; reloads=0
        C_EditMode.GetLayouts=function() local list={{}} for _,n in ipairs(layoutNames) do list[#list+1]={{layoutName=n}} end
            return {{activeLayout=active, layouts=list}} end
        function ReloadUI() reloads=reloads+1 end
        function GetActiveTalentGroup() return specGroup end
        EditModeManagerFrame.accountSettings={'{}' if ready else 'nil'}
    ''')
    lua.globals().layoutNames = lua.table_from(list(names))
    if saved:
        lua.execute(saved)
    return lua


def run_layout():
    lua = layout_world()
    lua.execute('''handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush()
        assert(active==4 and calls.layout==1 and reloads==1)
        assert(CharacterUIBaselineDB.editModeLayout['1'].reloads==1)''')
    print('PASS a character on a Blizzard preset switches to rex and reloads once')
    lua = layout_world(active=4, saved="CharacterUIBaselineDB={editModeLayout={['1']={reloads=1}}}")
    lua.execute('''handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush()
        local e=CharacterUIBaselineDB.editModeLayout['1']
        assert(not calls.layout and reloads==0 and e.assigned=='rex' and not e.reloads and #printed==0)''')
    print('PASS after the reload the switch is recorded without further writes')
    lua = layout_world(saved="CharacterUIBaselineDB={editModeLayout={['1']={reloads=1}}}")
    lua.execute('''handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); flush()
        assert(not calls.layout and reloads==0 and #printed==1 and printed[1]:find('Select it once',1,true))''')
    print('PASS a selection that did not persist is reported instead of reloading again')
    lua = layout_world(saved="CharacterUIBaselineDB={editModeLayout={['1']={assigned='rex'}}}")
    lua.execute("handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); assert(not calls.layout and reloads==0 and #printed==0)")
    lua = layout_world(active=3)
    lua.execute("handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); assert(not calls.layout and reloads==0)")
    print('PASS later preset choices and other saved layouts are kept')
    lua = layout_world(names=('Other',))
    lua.execute("handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); flush(); assert(not calls.layout and #printed==1 and printed[1]:find('not saved',1,true))")
    print('PASS an account without rex keeps its layout and says so once')
    lua = layout_world(ready=False)
    lua.execute('''combat=true; handlers.layout(nil,'PLAYER_ENTERING_WORLD'); for i=1,40 do flush() end
        assert(not calls.layout and #timers==0)
        EditModeManagerFrame.accountSettings={}; handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); assert(not calls.layout)
        combat=false; handlers.layout(nil,'PLAYER_REGEN_ENABLED'); flush(); assert(calls.layout==1 and reloads==1)''')
    print('PASS combat and unready Edit Mode defer the switch with bounded retries')
    lua = layout_world(group=2, saved="CharacterUIBaselineDB={editModeLayout={['1']={assigned='rex'}}}")
    lua.execute('''handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush(); assert(calls.layout==1)
        active=1; reloads=0; specGroup=1; handlers.layout(nil,'ACTIVE_TALENT_GROUP_CHANGED'); flush(); assert(calls.layout==1 and reloads==0)''')
    print('PASS each spec group is switched once')
    lua = layout_world()
    lua.execute('''CharacterUIBaselineDB={loaded=true}; handlers.layout(nil,'PLAYER_ENTERING_WORLD'); flush()
        assert(CharacterUIBaselineDB.loaded and CharacterUIBaselineDB.editModeLayout['1'].reloads==1)''')
    print('PASS the record is written to the loaded per-character saved variables')


def quiet_world(loaded=('YUI',), addons=True, before=''):
    lua = lua51.LuaRuntime()
    lua.execute('''
        calls, bits, cvars = {}, {}, {showTutorials='1'}
        function record(k) calls[k] = (calls[k] or 0) + 1 end
        function CreateFrame() return {RegisterEvent=function() end, SetScript=function(_,_,fn) onLogin=fn end} end
        loadedAddons = {}
        C_AddOns = {IsAddOnLoaded=function(n) return loadedAddons[n] end}
        C_CVar = {GetCVarBitfield=function(f,i) return bits[f..i] == true end,
            SetCVarBitfield=function(f,i,v) record(f) bits[f..i]=v end,
            GetCVar=function(k) return cvars[k] end, SetCVar=function(k,v) record(k) cvars[k]=v end}
        LE_FRAME_TUTORIAL_BAGS=3; LE_FRAME_TUTORIAL_TALENTS=7; LE_FRAME_TUTORIAL_ACCOUNT_PING=2
        bits['closedInfoFrames7'] = true
    ''')
    for name in loaded:
        lua.execute(f"loadedAddons['{name}']=true")
    if addons:
        lua.execute('''
            installerDone, prompted, welcome = false, false, 0
            YUI = {Installer={CheckInstall=function() installerShown=true return true end},
                EditMode={CheckAndPromptSwitchToYUI=function() prompted=true end}}
            levelingShown = true
            GearInsightForever = {LevelingShown=function() return levelingShown end,
                SetLevelingShown=function(on) record('leveling') levelingShown=on end,
                db={whatsNewSeen='1.2.2'}, WhatsNew={Current=function() return {}, '1.2.4' end,
                    Check=function() giNews=true return true end}}
            YUI.global={lastChangelogVersion='v361'}
            YUI.Changelog={GetData=function() return {{version='v363'}} end,
                CheckVersion=function() yuiNews=true end}
            MAUTTAB={WHATSNEW={seen={a=true}}}
            Bagnon_Sets={latest={id='99.0.0', cooldown=0}}
            Details = {is_first_run=true, OpenWelcomeWindow=function() welcome=welcome+1 end}
            GatherLite = {db={global={}}}
            EllesmereUIDB = {styleChoicePending=true}; EllesmereUI = {_firstInstallPending=true}
        ''')
    if before:
        lua.execute(before)
    lua.execute(QUIET.read_text(), 'CharacterUIBaseline', lua.table())
    return lua


def run_quiet():
    lua = quiet_world()
    lua.execute('''
        local done
        assert(YUI.Installer:CheckInstall(function() done=true end) == false and done and not installerShown)
        YUI.EditMode:CheckAndPromptSwitchToYUI(); assert(not prompted)
    ''')
    print('PASS YUI setup wizard and layout prompt are skipped while the login chain continues')
    lua.execute("assert(levelingShown==false and calls.leveling==1); onLogin(); assert(calls.leveling==1)")
    lua = quiet_world(loaded=())
    lua.execute("assert(levelingShown==true and not calls.leveling)")
    print('PASS GearInsight leveling window is hidden only under YUI, matching the guard rule')
    lua = quiet_world()
    lua.execute("onLogin(); Details:OpenWelcomeWindow(); assert(welcome==0); Details:OpenWelcomeWindow(); assert(welcome==1)")
    lua = quiet_world(before="Details.is_first_run=nil")
    lua.execute("onLogin(); Details:OpenWelcomeWindow(); assert(welcome==1)")
    print('PASS the Details first-run welcome is skipped once; later manual opens work')
    lua = quiet_world()
    lua.execute("assert(GatherLite.db.global.controlsGuideSeen==true)")
    print('PASS GatherLite controls guide is marked seen')
    lua = quiet_world()
    lua.execute('''
        assert(bits.closedInfoFrames3 and bits.closedInfoFramesAccountWide2 and not bits.closedInfoFrames2)
        assert(calls.closedInfoFrames==1 and calls.closedInfoFramesAccountWide==1)
        assert(cvars.showTutorials=='0')
        onLogin(); assert(calls.closedInfoFrames==1 and calls.showTutorials==1)
    ''')
    print('PASS Blizzard help tips are closed per character and account without repeated writes')
    lua = quiet_world()
    lua.execute('''
        YUI.Changelog:CheckVersion(); assert(not yuiNews and YUI.global.lastChangelogVersion=='v363')
        assert(GearInsightForever.WhatsNew.Check()==false and not giNews and GearInsightForever.db.whatsNewSeen=='1.2.4')
        assert(MAUTTAB.WHATSNEW.enabled==false and MAUTTAB.WHATSNEW.seen.a)
        assert(Bagnon_Sets.latest.id=='99.0.0' and Bagnon_Sets.latest.cooldown==2147483647)
    ''')
    print('PASS update notices (YUI changelog, GearInsight and MapUtils what\'s new, Bagnon outdated) are marked seen or held')
    lua = quiet_world()
    lua.execute("assert(EllesmereUIDB.firstInstallPopupShown and not EllesmereUIDB.styleChoicePending and not EllesmereUI._firstInstallPending and _EUI_ConflictCheckRan)")
    print('PASS EllesmereUI first-install, style and conflict popups are held')
    lua = quiet_world(loaded=(), addons=False)
    lua.execute("onLogin(); assert(cvars.showTutorials=='0')")
    print('PASS missing add-ons are skipped without errors')


if __name__ == '__main__':
    run()
    run_layout()
    run_quiet()
