-- Optional sibling-source checks; no native client or complete consumer migration.
-- Domain baselines (these modules are unchanged in the SND migration PRs):
-- XPIsland f2b9dcdc4da2d8c07815934746622035ad6329f6
-- FindAnUpgrade 89fcaeca4d0b283cdb0de89775bbf3ad52c80b6d
-- AsTheCrowFlies 3d02ab66b5ff836d9215f09674e2a6c371982224
-- Three real domain modules with mock controllers/UI, using the production SND runtime.
local W=dofile('tests/wow.lua')
local examples={};assert(loadfile('examples/SettingsAdapter.lua'))('Examples',examples)
local function loadAddon(name,files)
    local ns={};for _,file in ipairs(files)do assert(loadfile('../'..name..'/'..name..'/'..file))(name,ns)end;return ns
end
local function boot(app)W.event('ADDON_LOADED',app.name)end
local function factory(name)local sdk=W.load(name);return sdk:NewAddon(name),sdk end

-- XPIsland: real sampling model + account profiles with delayed character association.
local XP=loadAddon('XPIsland',{'Model.lua'}).Model
local xp,sdk=factory('XPIntegration')
local function accountAdapter()
    local A={}
    local function state(db,character)
        local active=character and db.characters[character] or 'Shared'
        return {values=sdk._.copy(db.profiles[active]),activeProfile=active,needsCharacter=not character,readOnly=not character,
            database=db,character=character,profiles={names={'Shared','Solo'},operations={bind=true,switch=true}}}
    end
    function A:Restore(saved)
        local db=saved.XPIntegrationDB or {profiles={Shared={scale=1},Solo={scale=1}},characters={}}
        return true,{state=state(db)}
    end
    function A:Prepare(current,op)
        local db,character=current.database,current.character
        if op.kind=='bind'then character=op.identity;db.characters[character]=db.characters[character]or'Shared'
        elseif op.kind=='switch'then if not db.profiles[op.name]then return false,{code='missing'}end;db.characters[character]=op.name
        elseif op.kind=='set'then db.profiles[current.activeProfile][op.path]=op.value end
        return true,{state=state(db,character),saved={XPIntegrationDB=db}}
    end
    return A
end
xp:Settings({savedVariables={'XPIntegrationDB'},adapter=accountAdapter(),fields={scale={type='number',default=1,min=.5,max=2}}})
local identities=0;xp:Scope():Watch(xp:SelectSettings(function(_,context)return{profile=context.activeProfile,waiting=context.needsCharacter}end),function()identities=identities+1 end)
boot(xp);local changed,failure=xp:Set('scale',1.2);assert(changed==false and failure.code=='readOnly' and type(failure.message)=='string');assert(xp.profiles:BindCharacter('Character-Realm'))
assert(xp.profiles:Switch('Solo'));assert(identities==3 and XPIntegrationDB.characters['Character-Realm']=='Solo')
local tracker=XP.NewTracker(XP.NewSession('fixture',100));tracker:Sample(10,100,1000,'unknown',1,false)
local display=xp:State({xp=tracker.xp,cap=tracker.cap});local paints=0;local view=xp:Scope('display')
view:Watch(display:Select(function(s)return s end),function()paints=paints+1 end)
tracker:Sample(10,150,1000,'unknown',2,false)
assert(display:Update(function(s)s.xp,s.cap=tracker.xp,tracker.cap end));assert(paints==2)
view:Cancel();display:Update(function(s)s.xp=200 end);assert(paints==2)
print('PASS XPIsland: authoritative samples, delayed identity, equal-value profile switch, closed view')

-- FAU: actual persistence recovery and command policies, with explicit metadata dependency.
local FAU=loadAddon('FindAnUpgrade',{'Model.lua','Shortlist.lua'})
local fau=factory('FAUIntegration')
fau:Settings({savedVariables={'FAUIntegrationDB'},adapter=examples.CreateSettingsAdapter('FAUIntegrationDB'),fields={scale={type='number',default=1,min=.5,max=2}}})
boot(fau)
local original={ids={101,101,102}};local db=FAU.Shortlist:Load(original);assert(db.recovery==original and #FAU.Shortlist:IDs()==2)
local inputs=fau:State({ids=FAU.Shortlist:IDs(),metadataRevision=0})
local refreshes=0;local visible=fau:Scope('shortlist')
visible:Watch(inputs:Select(function(s)return s end),function()refreshes=refreshes+1 end)
assert(FAU.Shortlist:Toggle(103));assert(inputs:Update(function(s)s.ids=FAU.Shortlist:IDs()end))
assert(inputs:Update(function(s)s.metadataRevision=s.metadataRevision+1 end));assert(refreshes==3)
visible:Cancel();inputs:Update(function(s)s.metadataRevision=s.metadataRevision+1 end)
fau:Scope('shortlist'):Watch(inputs:Select(function(s)return s end),function()refreshes=refreshes+1 end);assert(refreshes==4)
local future={schemaVersion=99,ids={999}};FAU.Shortlist:Load(future);assert(not FAU.Shortlist:Toggle(104) and future.ids[1]==999)
local oversized={};for i=1,21 do oversized[i]=i end;FAU.Shortlist:Load({schemaVersion=1,ids=oversized});assert(not FAU.Shortlist:Toggle(22) and FAU.Shortlist:Remove(1))
print('PASS FAU: recovery, capacity semantics, metadata invalidation, reopen, future-schema protection')

-- ATCF: real navigation state, independently shaped per-character profile persistence.
local ATCF=loadAddon('AsTheCrowFlies',{'Model.lua','Navigation.lua'})
local atcf=factory('ATCFIntegration')
local adapter={}
function adapter:Restore(saved)
    local profiles=saved.ATCFIntegrationProfiles or {active='Default',entries={Default={scale=1},Travel={scale=1}}}
    return true, {state={values=profiles.entries[profiles.active],activeProfile=profiles.active,profiles={names={'Default','Travel'},operations={switch=true}},database=profiles},
        saved={ATCFIntegrationDB=profiles.entries[profiles.active],ATCFIntegrationProfiles=profiles}}
end
function adapter:Prepare(state,op)
    local profiles=state.database
    if op.kind=='switch'then if not profiles.entries[op.name]then return false,{code='missing'}end;profiles.active=op.name
    elseif op.kind=='set'then profiles.entries[profiles.active][op.path]=op.value end
    return self:Restore({ATCFIntegrationProfiles=profiles})
end
atcf:Settings({savedVariables={'ATCFIntegrationDB','ATCFIntegrationProfiles'},adapter=adapter,fields={scale={type='number',default=1,min=.5,max=2}}})
boot(atcf)
local switches=0;atcf:Scope():Watch(atcf:SelectSettings(function(_,context)return context.activeProfile end),function()switches=switches+1 end)
assert(atcf.profiles:Switch('Travel'));assert(switches==2 and ATCFIntegrationProfiles.active=='Travel')
assert(not atcf.profiles:Switch('missing'));assert(atcf.profiles:Active()=='Travel')
local nav=ATCF.Navigation.New();local origin,destination={x=0,y=0,map=1},{x=100,y=0,map=1}
assert(ATCF.Navigation.Start(nav,{legs={{mode='walk',start=origin,finish=destination}},destination=destination},origin,0))
local search=atcf:State({query='',generation=0,searching=false,matches={}})
local requests=atcf:Scope('search-requests')
local function begin(query)
    search:Update(function(s)s.query=query;s.generation=s.generation+1;s.searching=true;s.matches={}end)
    local generation=search:Read().generation
    local completion=function(matches)
        if generation~=search:Read().generation then return false end
        return search:Update(function(s)s.matches=matches;s.searching=false end)
    end
    local scheduled,timer=requests:After(.12,'search',function()assert(completion({query}))end)
    assert(scheduled and type(timer.Cancel)=='function')
    return completion
end
local old=begin('Stormwind');local current=begin('Ironforge');assert(not old({'Stormwind'}));W.tick(.2);assert(search:Read().matches[1]=='Ironforge');assert(nav.state=='walking')
-- Two custom component consumers exercise page ownership without adding a binding DSL.
for _,consumer in ipairs({fau,atcf})do
    local seen,builds=0,0;local runtime=consumer:State({n=0})
    local panel=consumer:Options({pages={{id='domain',sections={{controls={{type='custom',id='status',create=function(parent,app,scope)
        builds=builds+1;scope:Watch(runtime:Select(function(s)return s.n end),function()seen=seen+1 end)
        return{Refresh=function()end,Layout=function()return 32 end,Hide=function()end}
    end}}}}},{id='other',sections={}}}})
    assert(panel:Open());assert(seen==1 and builds==1);panel:Close();runtime:Update(function(s)s.n=1 end);assert(seen==1)
    assert(panel:Open());assert(seen==2 and builds==2);panel:SelectPage('other');runtime:Update(function(s)s.n=2 end);assert(seen==2)
end
assert(xp:Get('scale')==1 and atcf:Get('scale')==1 and fau:Get('scale')==1)
print('PASS ATCF: separate profile layout, stale search suppression, active navigation preservation')
print('PASS FAU + ATCF: custom page subscription rebinding and hidden idle behavior')

-- Two different shutdown responsibilities use the same event contract.
local checkpoint,stopped
assert(xp:Scope():Event('PLAYER_LOGOUT',function()
    assert(xp:IsReady());checkpoint=XP.Copy(tracker.session)
end))
assert(atcf:Scope():Event('PLAYER_LOGOUT',function()
    assert(atcf:IsReady());stopped=true -- consumer's native navigation ticker cancellation
end))
W.event('PLAYER_LOGOUT')
assert(checkpoint and checkpoint.total==50 and stopped and not xp:IsReady() and not atcf:IsReady())
print('PASS XPIsland + ATCF: checkpoint and native-timer cleanup before disposal')
