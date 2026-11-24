local W=dofile('tests/wow.lua')
local examples={};assert(loadfile('examples/SettingsAdapter.lua'))('Examples',examples)
local total=0
local function test(name,why,run)
    local ok,err=pcall(run)
    assert(ok,name..': '..tostring(err));total=total+1;print('PASS '..name..' — '..why)
end
local serial=0
local function app(settings)
    serial=serial+1;local name='SNDTest'..serial
    local sdk=W.load(name);local a=sdk:NewAddon(name)
    if settings then a:Settings(settings(name))end
    return a,sdk
end
local function basic(name)
    return {savedVariables={name..'DB'},adapter=examples.CreateSettingsAdapter(name..'DB'),fields={
        scale={type='number',default=1,min=.5,max=2},font={type='font',default='Game tooltip'},
        color={type='color',default={1,1,1}},enabled={type='boolean',default=true},
    }}
end
local function boot(a)W.event('ADDON_LOADED',a.name)end

test('lifecycle registration failure','a failed bootstrap releases the frame and permits retry with the same name',function()
    local sdk=W.load('BootRetry')
    local create, failedFrame = CreateFrame
    CreateFrame=function(...)
        failedFrame=create(...)
        local register=failedFrame.RegisterEvent
        function failedFrame:RegisterEvent(event)
            if event=='PLAYER_LOGOUT' then return false end
            return register(self,event)
        end
        return failedFrame
    end
    local ok,err=pcall(sdk.NewAddon,sdk,'BootRetry')
    CreateFrame=create
    assert(not ok and tostring(err):find('PLAYER_LOGOUT',1,true) and not next(failedFrame.events))
    local a=sdk:NewAddon('BootRetry');boot(a);assert(a:IsReady())
end)

test('state transactions','prevents partial publication, escaped drafts and notification write loops',function()
    local a=app();local s=a:State({n=0},{validate=function(v)return v.n>=0 end});local paints=0
    local view=a:Scope();view:Watch(s:Select(function(v)return{n=v.n}end),function()paints=paints+1;local ok,e=s:Update(function(v)v.n=2 end);assert(not ok and e.code=='reentrant')end)
    assert(paints==0);boot(a);assert(paints==1)
    local draft;assert(s:Update(function(v)draft=v;v.n=1 end));draft.n=99;assert(s:Read().n==1 and paints==2)
    assert(not s:Update(function(v)v.n=-1 end));assert(not s:Update(function(v)v.n=2;error('abort')end))
    assert(s:Read().n==1);assert(s:Update(function(v)v.n=1 end));assert(paints==2)
    local ok,e=s:Update(function(v)v.n=3 end,0);assert(not ok and e.code=='stale')
    local other=app();boot(other);assert(other:State({n=0}):Update(function(v)v.n=1 end))
    local snap=s:Read();snap.n=88;assert(s:Read().n==1)
end)

test('watch lifecycle','closed views stop work; callbacks can fail or cancel peers without corrupting dispatch',function()
    local a=app();boot(a);local s=a:State({n=0});local owner=a:Scope('view');local later,armed,called=nil,false,0
    owner:Watch(s:Select(function(v)return v.n end),function()if armed then later:Cancel()end end)
    later=owner:Watch(s:Select(function(v)return v.n end),function()called=called+1 end)
    owner:Watch(s:Select(function(v)return v.n end),function()error('broken view')end)
    armed=true;assert(s:Update(function(v)v.n=1 end));assert(called==1)
    owner:Cancel();s:Update(function(v)v.n=2 end);assert(called==1)
    a:Scope('view'):Watch(s:Select(function(v)return v.n end),function(value)assert(value==2)end)
end)

test('settings restoration','reads after ADDON_LOADED and preserves unrecognized future SavedVariables',function()
    local a=app(basic);_G[a.name..'DB']={version=99,unknown={7}}
    boot(a);assert(a:IsReady() and a:Get('scale')==1)
    local ok,e=a:Set('scale',1.2);assert(not ok and e.code=='readOnly');assert(_G[a.name..'DB'].unknown[1]==7)
    local corrupt=app(basic);_G[corrupt.name..'DB']=false;boot(corrupt);assert(corrupt:IsReady() and not corrupt:Set('scale',1.2) and _G[corrupt.name..'DB']==false)
    local b=app(basic)
    local global=b.name..'DB'
    _G[global]={version=1,lastImport={source='manual'},values={scale=1.5,font='Game tooltip',color={1,1,1},enabled=true,legacy=false}}
    boot(b);assert(b:Get('scale')==1.5)
    local seen=0;b:Scope():Watch(b:SelectSettings(function(values)return values.scale end),function(value)assert(value==_G[b.name..'DB'].values.scale);seen=seen+1 end)
    assert(b:Set('scale',1.6));assert(seen==2);assert(not b:Set('scale',4));assert(b:Get('scale')==1.6)
    local reload=app(function()return basic(b.name)end);boot(reload)
    assert(reload:Get('scale')==1.6 and _G[global].lastImport.source=='manual' and _G[global].values.legacy==false)
    assert(reload:SetMany({enabled=false,scale=1.8}) and reload.profiles:Reset())
    assert(reload:Get('scale')==1 and reload:Get('enabled') and _G[global].lastImport.source=='manual' and _G[global].values.legacy==false)
end)

test('saved global limits round trip','every tree accepted for saving can be restored with the same size and depth limits',function()
    local names={'SNDTestLargeHistory','SNDTestDeepSetting'}
    local history,deep={},{}
    for i=1,20000 do history[i]=i end
    local leaf=deep
    for i=2,32 do leaf.next={};leaf=leaf.next end
    leaf.marker='complete'
    local function result(value,first,second)
        return true,{state={values={value=value}},saved={[names[1]]=first,[names[2]]=second}}
    end
    local adapter={}
    function adapter:Restore(saved)
        local first=saved[names[1]] or {}
        return result(first[1] or 0,first,saved[names[2]] or {})
    end
    function adapter:Prepare(_,op)
        history[1]=op.value
        return result(op.value,history,deep)
    end
    local function session()
        local a=app(function()return {fields={value={type='integer',default=0}},savedVariables=names,adapter=adapter}end)
        boot(a)
        return a
    end
    local writer=session()
    assert(writer:Set('value',7))
    writer._frame.scripts.OnEvent(writer._frame,'PLAYER_LOGOUT')
    local reader=session()
    assert(reader:IsReady() and reader:Get('value')==7 and #_G[names[1]]==20000)
    local restored=_G[names[2]]
    for i=2,32 do restored=restored.next end
    assert(restored.marker=='complete')

    local first,second=_G[names[1]],_G[names[2]]
    for _,limit in ipairs({'entries','depth'})do
        if limit=='entries' then history[20001]=1 else leaf.next={} end
        assert(not reader:Set('value',8) and reader:Get('value')==7)
        assert(_G[names[1]]==first and _G[names[2]]==second)
        _G[names[1]],_G[names[2]]=history,deep
        assert(not session():IsReady() and _G[names[1]]==history and _G[names[2]]==deep)
        _G[names[1]],_G[names[2]]=first,second
        history[20001],leaf.next=nil,nil
    end
end)

test('nested profile defaults','a malformed inactive profile must not be normalized over a saved scalar',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={['position.x']={type='number',default=10},
        enabled={type='boolean',default=true}}}end)
    local db={version=1,active='Default',profiles={Default={enabled=false,position={x=3}},Travel={position=false}}}
    _G[a.name..'DB']=db;boot(a)
    assert(not a:IsReady() and _G[a.name..'DB']==db and db.profiles.Travel.position==false)
    assert(db.profiles.Travel.enabled==nil and db.profiles.Default.enabled==false and db.profiles.Default.position.x==3)
    db.profiles.Travel.position=nil
    boot(a)
    assert(a:IsReady() and a:Get('enabled')==false and a:Get('position.x')==3)
    assert(a.profiles:Switch('Travel') and a:Get('position.x')==10 and a:Get('enabled')==true)

    local example=app(function(name)return {savedVariables={name..'DB'},adapter=examples.CreateSettingsAdapter(name..'DB'),
        fields={['position.x']={type='number',default=10},enabled={type='boolean',default=true}}}end)
    local flat={version=1,values={position=false,enabled=false}}
    _G[example.name..'DB']=flat;boot(example)
    assert(not example:IsReady() and _G[example.name..'DB']==flat and flat.values.position==false)
    flat.values.position=nil;boot(example)
    assert(example:IsReady() and example:Get('position.x')==10 and example:Get('enabled')==false)
end)

test('adapter atomicity','an invalid staged result cannot mutate live settings or partially replace multiple globals',function()
    local a=app();local adapter={}
    function adapter:Restore(saved)return true,{state={values={x=1},profiles={operations={reset=true}}},saved={[a.name..'A']={x=1},[a.name..'B']={x=1}}}end
    function adapter:Prepare(state)state.values.x=999;return true,{state=state,saved={[a.name..'A']={x=999}}}end
    a:Settings({savedVariables={a.name..'A',a.name..'B'},adapter=adapter,fields={x={type='integer',default=1,min=0,max=10}}});boot(a)
    assert(not a:Set('x',2));assert(a:Get('x')==1 and _G[a.name..'A'].x==1 and _G[a.name..'B'].x==1)
end)

test('scope scheduling and hooks','bounds timer replacement and native hook retention; idle driver must stop',function()
    local a=app();local scope=a:Scope();local calls=0
    scope:After(0,'refresh',function()calls=calls+100 end);scope:After(0,'refresh',function()calls=calls+1 end)
    boot(a);W.tick(.1);assert(calls==1 and a._frame:GetScript('OnUpdate')==nil)
    local scheduled,recurring=scope:Every(.2,'tick',function()calls=calls+1 end);W.tick(10);assert(scheduled and calls==2);recurring:Cancel();assert(a._frame:GetScript('OnUpdate')==nil)
    local target={Do=function()end};local before=W.hooks
    for i=1,5 do local owner=a:Scope();owner:PostHook(target,'Do',function()calls=calls+1 end);target.Do();owner:Cancel();target.Do()end
    assert(W.hooks==before+1 and calls==7)
    local guard=scope:Guard(function()calls=calls+1 end);scope:Cancel();guard();assert(calls==7)
end)

test('timer dispatch order','a changing timer set defers additions and skips canceled peers while steady frames reuse their order',function()
    local a,sdk=app();boot(a)
    local scope=a:Scope()
    local calls,intervals={},{}
    local canceled
    scope:After(0,'first',function()
        calls[#calls+1]='first'
        scope:After(0,'replace',function()calls[#calls+1]='replacement' end)
        canceled:Cancel()
    end)
    local driver=a._frame:GetScript('OnUpdate')
    scope:After(0,'replace',function()calls[#calls+1]='obsolete' end)
    local ok
    ok,canceled=scope:After(0,'cancel',function()calls[#calls+1]='canceled' end)
    assert(ok)
    local scheduled,pulse=scope:Every(.25,'pulse',function(elapsed)
        calls[#calls+1]='pulse';intervals[#intervals+1]=elapsed
    end)
    assert(scheduled and a._frame:GetScript('OnUpdate')==driver)
    W.tick(.25)
    assert(table.concat(calls,',')=='first,pulse')
    W.tick(.5)
    assert(table.concat(calls,',')=='first,pulse,pulse,replacement' and intervals[2]==.5)

    W.tick(.125) -- The one-shot has fired. Only the recurring timer remains.
    local snapshots,snapshot=0,sdk._.snapshot
    sdk._.snapshot=function(set)snapshots=snapshots+1;return snapshot(set)end
    W.tick(.125);W.tick(.25)
    sdk._.snapshot=snapshot
    assert(snapshots==0 and #intervals==4 and intervals[3]==.25 and intervals[4]==.25)
    pulse:Cancel()
    assert(not a._frame:GetScript('OnUpdate'))
    scope:After(0,'restart',function()calls[#calls+1]='restart' end)
    assert(a._frame:GetScript('OnUpdate')==driver)
    W.tick(.125)
    assert(calls[#calls]=='restart' and not a._frame:GetScript('OnUpdate'))
end)

test('options editor ownership','rejects stale color callbacks and respects native hide-before-accept ordering',function()
    local a=app(basic);local panel=a:Options({pages={{id='appearance',sections={{title='Color',controls={{type='color',key='color',label='Color'}}}}}}})
    boot(a);assert(panel:Open());local button=panel._pool['appearance:1:1'];button.scripts.OnClick()
    W.color(.3,.4,.5,false);assert(a:Get('color')[1]==1)
    W.color(.3,.4,.5,true);assert(a:Get('color')[1]==.3)
    button.scripts.OnClick();local old=ColorPickerFrame.info.swatchFunc
    assert(a:Set('scale',1.2));old();assert(a:Get('color')[1]==.3)
    button.scripts.OnClick();W.color(.8,.8,.8,true,true);assert(a:Get('color')[1]==.3)
    panel:Close();assert(panel._view==nil)
end)

test('shared color picker takeover','a second owner can replace a visible picker without leaving the original preview applied',function()
    local a=app(basic)
    local paints={}
    local panel=a:Options({pages={{id='colors',sections={{controls={{type='color',key='color',label='Tint',
        preview=function(v)paints[#paints+1]=v[1]end}}}}}}})
    boot(a);assert(panel:Open())
    local swatch=panel._pool['colors:1:1']
    local picker=ColorPickerFrame
    local nativeHook=hooksecurefunc
    local unavailable=true
    local setupHooks=0
    hooksecurefunc=function(target,method,callback)
        if target==picker and method=='SetupColorPickerAndShow' then
            if unavailable then error('picker hook refused') end
            setupHooks=setupHooks+1
        end
        return nativeHook(target,method,callback)
    end
    assert(W.click(swatch))
    assert(not panel._edit and #paints==0)
    unavailable=false
    assert(W.click(swatch))
    W.color(.25,.4,.6)
    local stale=picker.info
    assert(paints[#paints]==.25 and a:Get('color')[1]==1)
    local foreignCalls=0
    local foreign={r=0,g=.2,b=.4,swatchFunc=function()foreignCalls=foreignCalls+1 end}
    picker:SetupColorPickerAndShow(foreign)
    assert(not panel._edit and paints[#paints]==1 and a:Get('color')[1]==1)
    assert(picker:IsShown() and picker.info==foreign and foreignCalls==1)
    local restored=#paints
    stale.swatchFunc();stale.cancelFunc();panel:Close()
    assert(#paints==restored and picker:IsShown())
    W.color(.1,.2,.3,true);W.tick(.1)
    assert(foreignCalls==2 and a:Get('color')[1]==1)
    assert(panel:Open());assert(W.click(swatch));W.color(.4,.5,.6,true)
    hooksecurefunc=nativeHook
    assert(a:Get('color')[1]==.4 and setupHooks==1)
end)

test('options construction and menu lifetime','failed builds are retryable and settings refresh never rebuilds an open menu',function()
    local a=app(basic);local panel=a:Options({pages={{id='appearance',sections={{title='Font',controls={{type='font',key='font',label='Font'},{type='checkbox',key='enabled',label='Enabled'},{type='slider',key='scale',label='Scale',step=.1}}}}}}})
    boot(a);W.failKind='Slider';assert(not panel:Open());assert(panel:Open())
    local d=panel._menus['appearance:1:1'];d:OpenMenu();assert(a:Set('font','Missing font'));assert(panel._refreshPending)
    d:CloseMenu();W.tick(.01);assert(not panel._refreshPending)
    local check=panel._pool['appearance:1:2'];check:SetChecked(false);check.scripts.OnClick(check);assert(a:Get('enabled')==false)
    panel._pool['appearance:1:3']:SetValue(1.4);assert(a:Get('scale')==1.4)
    local count=#W.frames;panel:Close();assert(panel:Open());assert(#W.frames==count)
    -- A native caption failure must release its recursion guard so pooled text
    -- can recover on the next refresh instead of silently freezing forever.
    local setWidth=d.Text.SetWidth
    d.Text.SetWidth=function()error('caption allocation failed')end
    assert(not panel:Refresh());assert(d._captioning==nil)
    d.Text.SetWidth=setWidth;assert(panel:Open());assert(d._fullCaption=='Missing font' and not d._captioning)
end)

-- SpellStats reported Options.lua:499 from the bare command. The options and
-- containment owners share display events on a duplicate-refusing native frame.
test('slash opens a usable options window','a shared display registration or unavailable layout hook cannot block the settings editor',function()
    for _, refuseSizeHook in ipairs({false, true}) do
        local a=app(basic)
        local panel=a:Options({pages={{id='display',sections={{controls={
            {type='font',key='font',id='font',label='Font'},
        }}}}}})
        local opened, failure
        local registered, handle=a:Slash('/bare',function()
            opened, failure=panel:Open()
        end)
        assert(registered)
        boot(a)
        local id=a.name:upper()..'_SND_BARE'
        local command=assert(SlashCmdList[id])
        assert(_G['SLASH_'..id..'1']=='/bare')
        local nativeCreate=CreateFrame
        local refused=false
        if refuseSizeHook then
            CreateFrame=function(kind,name,...)
                local frame=nativeCreate(kind,name,...)
                if name==a.name..'_SND_Options' then
                    local hook=frame.HookScript
                    function frame:HookScript(event, fn)
                        if event=='OnSizeChanged' then
                            refused=true
                            error('size hook unavailable')
                        end
                        return hook(self,event,fn)
                    end
                end
                return frame
            end
        end
        command('')
        CreateFrame=nativeCreate
        assert(opened and panel:IsShown(), failure and failure.message or 'missing panel')
        if refuseSizeHook then
            assert(refused and panel.frame.clampedToScreen, 'use native clamping after a refused layout hook')
        else
            assert(panel._keep and panel._keep.active, 'shared events must still attach the complete layout tracker')
        end
        local font=panel._menus['display:1:font']
        font:OpenMenu()
        for _,row in ipairs(font.root.rows)do
            if row.value=='Arial' then row.choose(row.value)end
        end
        font:CloseMenu()
        W.tick(.01)
        assert(a:Get('font')=='Arial' and font.Text:GetText()=='Arial')
        assert(W.click(panel._pool.close) and not panel:IsShown())
        command('')
        assert(opened and panel:IsShown() and font.Text:GetText()=='Arial')
        assert(W.click(panel._pool.close) and not panel._view)
        handle:Cancel()
    end
end)

test('font and geometry native boundaries','accepts void SetFont results and clamps using effective scale; refuses protected frames',function()
    local a=app(basic);boot(a);local label=UIParent:CreateFontString();assert(a.fonts:Apply(label,'body'));assert(label.fontSize==14.25)
    local media={List=function()return{'Fixture'}end,Fetch=function()return'Fixture.ttf'end,RegisterCallback=function()end,UnregisterAllCallbacks=function()end}
    LibStub=function()return media end;W.event('ADDON_LOADED','FixtureMedia');assert(a:Set('font','Fixture'))
    assert(label.font=='Fixture.ttf')
    local rejecting=UIParent:CreateFontString();rejecting.rejectFont='Fixture.ttf';assert(a.fonts:Apply(rejecting,'body'))
    assert(label.font=='Fonts\\FRIZQT__.TTF' and rejecting.font=='Fonts\\FRIZQT__.TTF');LibStub=nil
    local f=CreateFrame('Frame',nil,UIParent);f:SetSize(100,100);f:SetScale(2);f.left=700;f.bottom=-50
    local placed,h=a.layout:KeepOnScreen(f,{margin=10});assert(placed);assert(f.left==535 and f.bottom==5)
    f.protected=true;assert(not h:Refresh());assert(not a.layout:KeepOnScreen(f));h:Cancel()
end)

test('diagnostics and instance isolation','bounded logs and per-app ownership prevent cross-addon contamination',function()
    local a=app();local b=app();boot(a);boot(b)
    for i=1,250 do a.log:Info('event '..i,{number=i,object={}})end
    assert(#a.log:Entries()==200 and #b.log:Entries()==0)
    a.log:Info('repeat');a.log:Info('repeat');local entries=a.log:Entries();assert(entries[#entries].count==2)
    assert(a:Slash('/sndfixture',function()end));local h,e=b:Slash('/sndfixture',function()end);assert(not h and e.code=='collision')
    local late=0;a:OnReady(function()late=late+1 end);assert(late==0);W.tick(.1);assert(late==1)
end)
-- Blizzard imports this registry before dispatching native commands (including /pvp).
-- Forever b401e0332adfbf0460d319b06d8ea29279a941f1: ChatFrameUtil.ImportAllListsToHash.
-- Catch even same-value global assignments; ordinary Lua does not model WoW taint.
test('slash registry ownership','registration and disposal must not reassign Blizzard globals',function()
    local a=app();local registry=SlashCmdList;local received
    setfenv(a.Slash,setmetatable({}, {__index=_G,__newindex=function(_,key)
        error('unexpected global write: '..key)
    end}))
    local native=function()end;registry.PVP=native
    local ok,handle=a:Slash('/registryfixture',function(text)received=text end)
    assert(ok and SlashCmdList==registry and registry.PVP==native)
    local id=a.name:upper()..'_SND_REGISTRYFIXTURE';local handler=registry[id]
    handler('before readiness');assert(received==nil)
    boot(a);handler('keep Case and spaces ');assert(received=='keep Case and spaces ')
    handle:Cancel();assert(registry[id]==nil and _G['SLASH_'..id..'1']==nil)
    assert(SlashCmdList==registry and registry.PVP==native)
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT');registry.PVP=nil
end)

test('imported slash command ownership','cancellation after chat imports a command must release its spelling for reuse and preserve foreign replacements',function()
    local a=app();boot(a)
    -- Forever 734f0653, ChatFrameSetup.AddListProxyTable and ChatFrameUtil.ImportListToHash.
    local proxy,dispatch,names={},{},{}
    local registry=setmetatable({},{__index=proxy})
    local env=setmetatable({SlashCmdList=registry,hash_SlashCmdList=dispatch,hash_ChatTypeInfoList=names},{__index=_G})
    env._G=env
    env.IsSecureCmd=function(command)return command=='/securefixture' end
    setfenv(a.Slash,env)
    local id=a.name:upper()..'_SND_IMPORTED'
    local alias='SLASH_'..id..'1'
    local function import()
        local command=env[alias]:upper()
        local handler=assert(rawget(registry,id))
        dispatch[command],names[command],proxy[id]=handler,id,handler
        registry[id]=nil
    end
    local received
    local available,collision=a:Slash('/securefixture',function()end)
    assert(not available and collision.code=='collision')
    local ok,first=a:Slash('/imported',function(text)received=text end);assert(ok)
    import()
    local cached=dispatch['/IMPORTED'];cached('first');assert(received=='first')
    first:Cancel();cached('obsolete')
    assert(received=='first' and #a.log:Entries()==0)
    assert(not registry[id] and not env[alias] and not dispatch['/IMPORTED'] and not names['/IMPORTED'])
    local second;ok,second=a:Slash('/imported',function(text)received=text end);assert(ok)
    import();dispatch['/IMPORTED']('second');assert(received=='second')
    -- Another add-on replaces the dispatch and the pending registry entry before cancellation.
    local foreign=function()end
    dispatch['/IMPORTED'],names['/IMPORTED'],registry[id]=foreign,'OTHER',foreign
    second:Cancel()
    assert(dispatch['/IMPORTED']==foreign and names['/IMPORTED']=='OTHER' and env[alias]=='/imported')
    assert(registry[id]==foreign and not proxy[id])
    registry[id],env[alias]=nil,nil
    local err;ok,err=a:Slash('/imported',function()end);assert(not ok and err.code=='collision')
    dispatch['/IMPORTED'],names['/IMPORTED']=nil,nil
    assert(a:Slash('/imported',function()error('after logout')end));import()
    W.event('PLAYER_LOGOUT')
    assert(not dispatch['/IMPORTED'] and not names['/IMPORTED'] and not registry[id] and not env[alias])
end)

test('slash registry unavailable','missing native infrastructure must not be synthesized or partially registered',function()
    local a=app();local available=false;local registry=SlashCmdList
    setfenv(a.Slash,setmetatable({}, {__index=function(_,key)
        if key=='SlashCmdList' then if available then return registry end;return nil end
        return _G[key]
    end,__newindex=function(_,key)error('unexpected global write: '..key)end}))
    local ok,err=a:Slash('/registryretry',function()end)
    local id=a.name:upper()..'_SND_REGISTRYRETRY'
    assert(not ok and err.code=='unavailable' and registry[id]==nil and _G['SLASH_'..id..'1']==nil)
    available=true;local registered,handle=a:Slash('/registryretry',function()end)
    assert(registered and registry[id]);handle:Cancel();a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

test('Lua value and return boundaries','extra Lua returns and shared table aliases must not corrupt selector copying',function()
    local a=app();boot(a);local shared={x=1};local s=a:State({left=shared,right=shared})
    shared.x=9;assert(s:Read().left.x==1)
    local calls=0;a:Scope():Watch(s:Select(function(v)return{left=v.left.x},'extra',nil end),function(value)calls=calls+1;assert(value.left==calls)end)
    assert(calls==1);assert(s:Update(function(v)v.left.x=2 end));assert(s:Read().right.x==1 and calls==2)
    assert(not s:Update(function(v)v.loop=v end))
    local ok,one,two,three
    local sdk=W.load('ReturnFixture');local b=sdk:NewAddon('ReturnFixture')
    ok,one,two,three=sdk._.call(b,function()return false,nil,'tail'end)
    assert(ok and one==false and two==nil and three=='tail')
end)

test('declaration ownership and dense arrays','sparse lists must fail visibly and caller edits cannot mutate registered definitions',function()
    local a=app(basic)
    local bad={pages={[1]={id='one'},[3]={id='three'}}}
    local ok,e=pcall(function()a:Options(bad)end);assert(not ok and e:find('SND:',1,true))
    assert(not pcall(function()a:Options({pages={{id='bad',sections=false}}})end))
    local wrong={pages={{id='wrong',sections={{controls={{type='checkbox',key='scale',label='Wrong'}}}}}}}
    assert(not pcall(function()a:Options(wrong)end))
    local declaration={pages={{id='one',sections={{controls={{type='font',key='font',label='Font'}}}}}}}
    local panel=a:Options(declaration);declaration.pages[1].id='changed';declaration.pages[1].sections[1].controls[1].key='missing'
    boot(a);assert(panel:Open('one'));panel:Close()
    local b=app();local settings=basic(b.name);settings.savedVariables={[1]='One',[3]='Three'}
    assert(not pcall(function()b:Settings(settings)end));settings=basic(b.name);b:Settings(settings)
    settings.fields.scale.max=0;settings.adapter.Restore=function()error('caller replaced adapter')end
    boot(b);assert(b:IsReady() and b:Set('scale',1.5))
    local c=app();settings=basic(c.name);settings.fields.choice={type='enum',default='a',values={[1]='a',[3]='c'}}
    assert(not pcall(function()c:Settings(settings)end))
end)

test('structured error containment','arbitrary Lua error values cannot escape recovery or leak mutable error references',function()
    local a=app();boot(a);local s=a:State({x=1})
    local hostile=setmetatable({}, {__tostring=function()error('must not format')end,__index=function()error('must not index')end})
    local survived,ok,err=pcall(function()return s:Update(function()error(hostile)end)end)
    assert(survived and ok==false and type(err.code)=='string' and type(err.message)=='string')
    local original={code='domain',message='Rejected'}
    ok,err=s:Update(function()return false,original end);assert(not ok and err~=original and err.code=='domain')
    original.message='mutated';assert(err.message=='Rejected' and s:Read().x==1)
    local malformed={code={},message=false};ok,err=s:Update(function()return false,malformed end)
    assert(not ok and type(err.code)=='string' and type(err.message)=='string')
    a:Scope():Watch(s:Select(function(v)return v.x end),function()error({code='view',message='View failed'})end)
    local logs=a.log:Entries();assert(logs[#logs].message=='View failed')
end)

test('Result tuples and argument errors','all fallible resource APIs share a boolean discriminant; invalid API usage fails before mutation',function()
    local a=app();boot(a);local scope=a:Scope()
    local ok,h=scope:After(0,'timer',function()end);assert(ok==true and type(h.Cancel)=='function');h:Cancel()
    local unsupported,reason=a.fonts:Apply(42,'body');assert(unsupported==false and reason.code=='invalid')
    unsupported,reason=a.layout:KeepOnScreen({});assert(unsupported==false and reason.code=='unavailable')
    local failed,err=scope:Every(0,'bad',function()end);assert(failed==false and err.code=='invalid')
    failed,err=scope:PostHook({},'Absent',function()end);assert(failed==false and err.code=='unavailable')
    ok,h=scope:Event('PLAYER_LOGIN',function()end);assert(ok==true and type(h.Cancel)=='function');h:Cancel()
    ok,h=a:Slash('/resultfixture',function()end);assert(ok==true and type(h.Cancel)=='function');h:Cancel()
    local state=a:State({value=false});local passed,empty=state:Update(function(v)v.value=false end);assert(passed==true and empty==nil)
    assert(not pcall(function()scope:After(1,0/0,function()end)end))
    assert(not pcall(function()a:Scope(false)end))
    assert(not pcall(function()scope:Watch(nil,function()end)end))
    assert(not pcall(function()state:Update(function()end,'revision')end))
    local native=a._frame.RegisterEvent;a._frame.RegisterEvent=function()error({message='bad event'})end
    failed,err=scope:Event('BAD_EVENT',function()end);a._frame.RegisterEvent=native
    assert(failed==false and err.message=='bad event')
    local cleanup=a:Scope();local fired=0
    cleanup:Event('CLEANUP_TEST',function()fired=fired+1 end)
    cleanup:After(1,'cleanup',function()fired=fired+1 end)
    local unregister=a._frame.UnregisterEvent;a._frame.UnregisterEvent=function()error('native cleanup failed')end
    cleanup:Cancel();a._frame.UnregisterEvent=unregister
    W.tick(2);W.event('CLEANUP_TEST');assert(fired==0)

end)


test('logout checkpoint and disposal','checkpoints must run once before cleanup, even with recursive delivery and throwing callbacks or native UI cleanup',function()
    local a=app(basic);local scope=a:Scope();local checkpoint,stopped,late=0,0,0
    local panel=a:Options({pages={{id='one',sections={}}}})
    boot(a);assert(panel:Open());assert(a:Set('scale',1.5))
    panel.frame.Hide=function()error('native hide failed')end
    assert(a:Slash('/shutdownfixture',function()late=late+1 end))
    local target={Run=function()end};assert(scope:PostHook(target,'Run',function()late=late+1 end))
    assert(scope:Event('PLAYER_LOGOUT',function()
        assert(a:IsReady() and a:Get('scale')==1.5);checkpoint=checkpoint+1
        W.event('PLAYER_LOGOUT') -- Synchronous nested delivery cannot checkpoint twice.
        assert(scope:After(0,'late',function()late=late+1 end))
    end))
    assert(scope:Event('PLAYER_LOGOUT',function()error('checkpoint subscriber failed')end))
    assert(scope:Event('PLAYER_LOGOUT',function()stopped=stopped+1 end))
    W.event('PLAYER_LOGOUT');W.event('PLAYER_LOGOUT');W.tick(1);target.Run()
    assert(checkpoint==1 and stopped==1 and late==0 and not a:IsReady())
    assert(not SlashCmdList[a.name:upper()..'_SND_SHUTDOWNFIXTURE'])
    assert(not a._frame:GetScript('OnUpdate') and not next(a._frame.events))
    local errors=a.log:Entries();assert(#errors==2)
    assert(errors[1].message:find('checkpoint subscriber failed',1,true) and errors[2].message:find('native hide failed',1,true))
end)

test('lazy font ownership','unused services must stay idle while preboot, late-media, retry and disposed callbacks retain correct ownership',function()
    local registrations,lookups=0,0;local receivers={};local fail=false
    local lib={List=function()return{'Later'}end,Fetch=function()return'Later.ttf'end}
    lib.RegisterCallback=function(receiver,event,method)
        registrations=registrations+1;receivers[#receivers+1]=receiver
        if fail then error('partial media registration') end
        assert((event=='LibSharedMedia_Registered' or event=='LibSharedMedia_SetGlobal') and method=='Changed')
    end
    -- No unregister API: stale native callbacks still must be inert.
    LibStub=function()lookups=lookups+1;return lib end
    local a=app(basic);boot(a)
    local text=UIParent:CreateFontString();a.fonts:Measure(text)
    assert(lookups==0 and registrations==0 and not a._frame.events.UI_SCALE_CHANGED)
    assert(a:Set('font','Arial'));assert(a:Set('font','Game tooltip'));assert(lookups==0 and registrations==0)
    local b=app(basic);assert(b.fonts:Apply(text,'body'));assert(registrations==0)
    _G[b.name..'DB']={version=1,values={scale=1,font='Later',color={1,1,1},enabled=true}}
    boot(b);assert(registrations==2 and text.font=='Later.ttf')
    b.fonts:Entries();b.fonts:Apply(text,'body');assert(registrations==2)
    local late=UIParent:CreateFontString();fail=true
    assert(a.fonts:Apply(late,'body'));assert(registrations==3)
    fail=false;W.event('ADDON_LOADED','MediaRetry');assert(registrations==5)
    assert(a:Set('font','Later'));late.rejectFont='Later.ttf';late.font='Replaced.ttf';a.fonts:Refresh();assert(late.font~='Later.ttf')
    late.rejectFont=nil;receivers[#receivers]:Changed('LibSharedMedia_Registered','font');assert(late.font=='Later.ttf')
    -- A partial registration must not leave an extra active callback.
    local refreshes=0;local refresh=a.fonts.Refresh
    a.fonts.Refresh=function(self)refreshes=refreshes+1;return refresh(self)end
    receivers[3]:Changed('LibSharedMedia_Registered','font');assert(refreshes==0)
    W.event('PLAYER_LOGOUT');for _,receiver in ipairs(receivers)do receiver:Changed('LibSharedMedia_Registered','font')end
    assert(refreshes==0 and not pcall(function()a.fonts:Entries()end))
    LibStub=nil
    local c=app(basic);boot(c);local missing=UIParent:CreateFontString()
    assert(c:Set('font','Later'));assert(c.fonts:Apply(missing,'body'));assert(missing.font~='Later.ttf')
    LibStub=function()return lib end;W.event('ADDON_LOADED','LateMedia');assert(missing.font=='Later.ttf')
    W.event('PLAYER_LOGOUT');LibStub=nil
end)

test('lazy layout ownership','tracking must start on demand and release display listeners after cancellation or partial hook failure',function()
    local a=app();boot(a);assert(not a._frame.events.DISPLAY_SIZE_CHANGED)
    local frame=CreateFrame('Frame',nil,UIParent)
    local ok,first=a.layout:KeepOnScreen(frame);assert(ok and a._frame.events.DISPLAY_SIZE_CHANGED)
    local _,second=a.layout:KeepOnScreen(CreateFrame('Frame',nil,UIParent))
    first:Cancel();assert(a._frame.events.DISPLAY_SIZE_CHANGED)
    second:Cancel();assert(not a._frame.events.DISPLAY_SIZE_CHANGED)
    local bad=CreateFrame('Frame',nil,UIParent);local hook=bad.HookScript
    bad.HookScript=function(self,event,callback)if event=='OnDragStart'then error('native hook unavailable')end;return hook(self,event,callback)end
    local failed,err=a.layout:KeepOnScreen(bad);assert(not failed and err.code=='unavailable' and not a._frame.events.DISPLAY_SIZE_CHANGED)
    W.event('PLAYER_LOGOUT');assert(not pcall(function()a.layout:KeepOnScreen(frame)end))
end)

test('executable consumer settings ownership','the shipped example must restore old fields, bind its view, and cancel previews without persisting them',function()
    local name='ConsumerExample';local ns={SomethingNeedDoing=W.load(name)}
    assert(loadfile('examples/SettingsAdapter.lua'))(name,ns)
    ExampleProfiles={version=1,active='Default',profiles={Default={scale=1.25,font='Game tooltip'}}} -- predates the example's tint field
    assert(loadfile('examples/Consumer.lua'))(name,ns)
    assert(not ns.Preview);W.event('ADDON_LOADED',name)
    assert(ns.app:IsReady() and ns.Preview.scale==1.25 and ExampleProfiles.profiles.Default.tint[1]==.2)
    assert(ns.app:Set('scale',1.5));assert(ns.Preview.scale==1.5 and ExampleProfiles.profiles.Default.scale==1.5)
    local panel=ns.app._panel;assert(panel:Open())
    local button=panel._pool['appearance:1:3'];button.scripts.OnClick()
    W.color(.8,.7,.6,false,false);assert(ns.Preview.background[1]==.8 and ExampleProfiles.profiles.Default.tint[1]==.2)
    W.color(.8,.7,.6,true,true);assert(ns.Preview.background[1]==.2 and ExampleProfiles.profiles.Default.tint[1]==.2)
    assert(ns.app.profiles:Reset());assert(ns.Preview.scale==1 and ExampleProfiles.profiles.Default.scale==1)
    W.event('PLAYER_LOGOUT');ExampleProfiles=nil
end)


test('character-profile login example','a missing name at restore must bind to Shared when the player enters the world',function()
    local name='CharacterProfilesExample'
    local ns={SomethingNeedDoing=W.load(name)}
    local oldName,oldRealm=UnitName,GetRealmName
    UnitName=function() return nil end
    GetRealmName=function() return 'Realm' end
    assert(loadfile('examples/CharacterProfiles.lua'))(name,ns)
    W.event('ADDON_LOADED',name)
    assert(ns.app:IsReady() and ns.app.profiles:Capabilities().needsCharacter and not ExampleCharacterProfiles)
    UnitName=function() return 'Player' end
    W.event('PLAYER_ENTERING_WORLD')
    assert(ExampleCharacterProfiles.characters['Player-Realm']=='Shared')
    assert(ns.app:Set('showTotals',false) and not ExampleCharacterProfiles.profiles.Shared.showTotals)
    W.event('PLAYER_LOGOUT')
    UnitName,GetRealmName,ExampleCharacterProfiles=oldName,oldRealm,nil
end)

test('default profiles and atomic patches','new addons need safe storage without adapters; related settings must publish once and future saves must survive',function()
    local function fields(name)return {savedVariables={name..'DB'},fields={font={type='font',default='Arial'},fontSize={type='integer',default=13,min=9,max=20},theme={type='enum',default='modern',values={'modern','forever'}},['window.x']={type='number',default=0},['window.y']={type='number',default=0}}}end
    local a=app(fields);local observed={};local scope=a:Scope()
    scope:Watch(a:SelectSettings(function(v)return v.window end),function(v)observed[#observed+1]=v end)
    boot(a);assert(a:IsReady() and a.profiles:Active()=='Default' and #observed==1)
    assert(not a.profiles:BindCharacter('A-Realm') and #a.profiles:Characters()==0)
    assert(a:SetMany({['window.x']=10,['window.y']=20}));assert(#observed==2 and observed[2].x==10 and observed[2].y==20)
    local db=_G[a.name..'DB'];local ok=a:SetMany({fontSize=100,['window.x']=30});assert(not ok and _G[a.name..'DB']==db and #observed==2)
    assert(a.profiles:Duplicate('Travel'));assert(a:Set('window.x',50));assert(a.profiles:Switch('Default'));assert(a:Get('window.x')==10)
    assert(a.profiles:CopyFrom('Travel'));assert(a:Get('window.x')==50);assert(a.profiles:Reset());assert(a:Get('window.x')==0)
    assert(not a.profiles:Duplicate('Travel'));assert(not a.profiles:Duplicate(' Bad '))
    db=_G[a.name..'DB'];db.profiles.Default.window.x=99;assert(a:Get('window.x')==0)
    local future=app(fields);local saved={version=99,unknown={'keep'}};_G[future.name..'DB']=saved;boot(future)
    assert(future:IsReady() and future.profiles:Capabilities().readOnly);assert(not future:Set('font','Game tooltip'));assert(_G[future.name..'DB']==saved)
    local malformed=app(fields);local bad={version=1,active='Default',profiles={Default={font=false}}};_G[malformed.name..'DB']=bad;boot(malformed)
    assert(not malformed:IsReady() and _G[malformed.name..'DB']==bad)
end)

test('character profile selection','sharing values and selecting profiles are independent across characters and reloads',function()
    local global='SNDTestCharacterProfiles'
    local legacy={enabled=false,position={x=17}}
    legacy.oldPosition=legacy.position
    local seeds=0
    local function session()
        local a=app(function()return {savedVariables={global},characterProfiles=true,
            initialProfile=function()seeds=seeds+1;return legacy end,
            fields={enabled={type='boolean',default=true},['position.x']={type='integer',default=0},
                ['position.y']={type='integer',default=0}}}end)
        boot(a)
        return a
    end
    local a=session();local profiles=a.profiles
    local caps=profiles:Capabilities()
    assert(a:IsReady() and caps.readOnly and caps.needsCharacter and caps.operations.bind and profiles:Active()=='Shared')
    assert(a:Get('enabled')==false and a:Get('position.x')==17 and a:Get('position.y')==0)
    assert(not a:SetMany({enabled=true}) and not profiles:Duplicate('Solo') and not profiles:Switch('Shared'))
    assert(not profiles:BindCharacter(' ') and not profiles:BindCharacter('bad|name') and _G[global]==nil)
    assert(legacy.position.y==nil and #profiles:Characters()==0 and seeds==1)
    assert(profiles:BindCharacter('B-Realm') and profiles:BindCharacter('A-Realm'))
    local seeded=_G[global].profiles.Shared
    assert(seeded.position~=seeded.oldPosition and seeded.position.y==0 and seeded.oldPosition.y==nil)
    assert(not profiles:Capabilities().readOnly and not profiles:Capabilities().needsCharacter)
    local shared=profiles:Characters()
    assert(table.concat(shared,',')=='A-Realm,B-Realm');shared[1]='different'
    assert(_G[global].characters['A-Realm']=='Shared' and profiles:Characters()[1]=='A-Realm')
    assert(profiles:Duplicate('Solo') and a:Get('enabled')==false and a:Get('position.x')==17)
    assert(not profiles:Duplicate('Solo') and not profiles:Switch('Missing'))
    assert(a:SetMany({enabled=true,['position.x']=42}) and profiles:Characters()[1]=='A-Realm')
    assert(profiles:BindCharacter('B-Realm') and profiles:Active()=='Shared' and a:Get('position.x')==17)
    assert(a:Set('position.x',21) and legacy.position.x==17)
    assert(profiles:BindCharacter('A-Realm') and profiles:Active()=='Solo' and a:Get('position.x')==42)
    assert(profiles:CopyFrom('Shared') and a:Get('position.x')==21 and not a:Get('enabled'))
    assert(profiles:Reset() and a:Get('position.x')==0 and a:Get('enabled'))
    assert(profiles:Switch('Shared') and a:Get('position.x')==21 and #profiles:Characters('Solo')==0)
    assert(profiles:Switch('Solo') and profiles:Characters('Shared')[1]=='B-Realm')
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
    local saved=_G[global]
    local reloaded=session()
    assert(seeds==1 and _G[global]==saved and reloaded.profiles:Capabilities().needsCharacter)
    assert(reloaded.profiles:BindCharacter('A-Realm') and reloaded.profiles:Active()=='Solo' and reloaded:Get('enabled'))
    assert(reloaded.profiles:BindCharacter('B-Realm') and not reloaded:Get('enabled') and reloaded:Get('position.x')==21)
    assert(table.concat(reloaded.profiles:List(),',')=='Shared,Solo' and #reloaded.profiles:Characters('Unknown')==0)
end)

test('character profile storage limits','binding and reloading a large Shared profile do not count its active values twice',function()
    local global='SNDTestFullCharacterDB'
    local function session()
        local a=app(function()return {savedVariables={global},characterProfiles=true,fields={flag={type='boolean',default=true}}}end)
        boot(a);return a
    end
    local data={}
    -- This saved tree has exactly 20,000 entries, including its two profiles and binding.
    for i=1,19991 do data[i]=i end
    _G[global]={version=1,characters={A='Solo'},profiles={Shared={flag=false,data=data},Solo={flag=true}}}
    local a=session()
    assert(a:IsReady() and not a:Get('flag') and a.profiles:BindCharacter('A') and a:Get('flag'))
    assert(a.profiles:Switch('Shared') and a:Set('flag',true))
    local saved=_G[global]
    assert(not a.profiles:BindCharacter('B') and _G[global]==saved and saved.characters.B==nil)
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
    local b=session()
    assert(b:IsReady() and b.profiles:BindCharacter('A') and b:Get('flag'))
    assert(b:Set('flag',false) and #_G[global].profiles.Shared.data==19991)

    local nested={}
    local leaf=nested
    for depth=5,32 do leaf.next={};leaf=leaf.next end -- db -> profiles -> Shared -> nested
    leaf.keep=false
    _G[global]={version=1,characters={A='Shared'},profiles={Shared={flag=false,nested=nested}}}
    local c=session()
    assert(c:IsReady() and c.profiles:BindCharacter('A') and c:Set('flag',true))
    leaf=_G[global].profiles.Shared.nested
    for depth=5,32 do leaf=leaf.next end
    assert(leaf.keep==false and nested~=_G[global].profiles.Shared.nested)
end)

test('character profile restoration','future settings and invalid inactive bindings cannot be overwritten by a later bind',function()
    local function settings(name,seed)
        return {savedVariables={name..'DB'},characterProfiles=true,initialProfile=seed,fields={flag={type='boolean',default=true}}}
    end
    local function restore(saved,seed)
        local a=app()
        a:Settings(settings(a.name,seed));_G[a.name..'DB']=saved;boot(a)
        return a
    end
    local function seedMustNotRun()error('seed called for existing database')end
    for _,db in ipairs({
        {version=1,characters={},profiles={Other={flag=true}}},
        {version=1,characters={Other='Missing'},profiles={Shared={flag=false}}},
        {version=1,characters={['Bad|Identity']='Shared'},profiles={Shared={flag=false}}},
        {version=1,characters={},profiles={Shared={flag=true},Other={flag=1}}},
    }) do
        local a=restore(db,seedMustNotRun)
        assert(not a:IsReady() and not a.profiles:BindCharacter('A-Realm') and _G[a.name..'DB']==db)
        assert(a.log:Entries()[1].message:find('Invalid') or a.log:Entries()[1].message:find('Malformed'))
    end
    local future={version=99,metadata='keep'}
    local a=restore(future,seedMustNotRun)
    local b=restore(nil,function()return nil,'readOnly'end)
    for _,locked in ipairs({a,b})do
        local caps=locked.profiles:Capabilities()
        assert(locked:IsReady() and locked:Get('flag') and caps.readOnly and not caps.needsCharacter)
        assert(not locked.profiles:BindCharacter('A-Realm') and not locked:Set('flag',false))
    end
    assert(_G[a.name..'DB']==future and _G[b.name..'DB']==nil)
    local malformed=restore(nil,function()return {flag=0}end)
    assert(not malformed:IsReady() and _G[malformed.name..'DB']==nil)
    local fresh=restore(nil,nil)
    assert(fresh.profiles:BindCharacter('A-Realm') and fresh.profiles:Active()=='Shared' and fresh:Get('flag'))
    local retry=app()
    local invalid=settings(retry.name)
    invalid.adapter=examples.CreateSettingsAdapter(retry.name..'DB')
    assert(not pcall(retry.Settings,retry,invalid))
    invalid.adapter=nil;invalid.characterProfiles=false;invalid.initialProfile=function()return {}end
    assert(not pcall(retry.Settings,retry,invalid))
    invalid.characterProfiles=true;retry:Settings(invalid);boot(retry)
    assert(retry.profiles:BindCharacter('A-Realm') and retry:Get('flag'))
end)

test('appearance ownership and custom surfaces','themes must propagate beyond options without mutating definitions, product colors or canceled views',function()
    local a,sdk=app(function(name)return {savedVariables={name..'DB'},fields={theme={type='enum',default='modern',values={'modern','forever','custom'}},font={type='font',default='Arial'},fontSize={type='integer',default=13,min=9,max=20}}}end)
    local custom=sdk._.copy(sdk.Themes.modern);custom.label='Custom';custom.colors.accent={.2,.7,.9,1};custom.tokens={track={.1,.2,.3,1}};custom.colors.track={.1,.2,.3,1}
    local bad=sdk._.copy(custom);bad.colors.accent={1,1};assert(not pcall(function()a:Appearance({defaultTheme='custom',themes={custom=bad}})end))
    a:Appearance({defaultTheme='modern',themes={modern=sdk.Themes.modern,forever=sdk.Themes.forever,custom=custom}})
    custom.colors.accent[1]=1;custom.tokens.track[1]=1
    local frame=CreateFrame('Button',nil,UIParent,'BackdropTemplate');local text=frame:CreateFontString();local product=frame:CreateFontString()
    text.SetTextColor=function(self,...)self.color={...}end;product.SetTextColor=text.SetTextColor;product:SetTextColor(.1,.8,.2)
    assert(a.ui:Style(frame,'button'));assert(not a.ui:Color(text,'track'));assert(a.ui:Color(text,'accent'));assert(a.fonts:Apply(text,'body'));assert(a.fonts:Apply(product,'body',{size=17}))
    local changes,latest=0,nil;local owner=a:Scope();owner:Watch(a:SelectAppearance(function(v)return v end),function(v)changes=changes+1;latest=v;assert(product.color[1]==.1)end)
    boot(a);local before=changes;assert(a:Set('theme','custom'));assert(changes==before+1 and latest.theme.tokens.track[1]==.1 and text.color[1]==.2)
    frame.scripts.OnEnter(frame);assert(frame.border[1]==.2);assert(a:Set('theme','forever'));assert(frame.border[1]==sdk.Themes.forever.colors.accent[1])
    -- Hiding or disabling a hovered surface must not retain the highlight.
    frame:Hide();frame:Show();assert(a.ui:Style(frame,'button'));assert(frame.border[1]==sdk.Themes.forever.colors.border[1])
    local button=CreateFrame('Button',nil,UIParent,'BackdropTemplate')
    button.IsEnabled=function(self)return self.enabled end;button.HasScript=function(_,event)return event=='OnDisable' end
    assert(a.ui:Style(button,'button'));button.scripts.OnEnter(button);button.enabled=false;button.scripts.OnDisable(button)
    button.scripts.OnEnter(button);button.enabled=true;assert(a.ui:Style(button,'button'));assert(button.border[1]==sdk.Themes.forever.colors.border[1])
    local ordinary=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');ordinary.HasScript=function(_,event)return event~='OnDisable' end
    assert(a.ui:Style(ordinary,'button'));assert(not ordinary.scripts.OnDisable)
    local probe=CreateFrame('Button',nil,UIParent,'BackdropTemplate');probe.HasScript=function()error('native capability failure')end
    local safe,accepted=pcall(a.ui.Style,a.ui,probe,'button');assert(safe and not accepted)
    probe.HasScript=function()return true end;assert(a.ui:Style(probe,'button'));probe.scripts.OnEnter(probe);assert(probe.border[1]==sdk.Themes.forever.colors.accent[1])
    -- Roll back earlier hooks when a later lifecycle hook cannot attach.
    local partial=CreateFrame('Button',nil,UIParent,'BackdropTemplate');local hook=partial.HookScript
    partial.HookScript=function(self,event,fn)if event=='OnHide' then error('hide hook unavailable')end;return hook(self,event,fn)end
    assert(not a.ui:Style(partial,'button'));local entries=#a.log:Entries();partial.scripts.OnEnter(partial);assert(#a.log:Entries()==entries and not partial.border)
    partial.HookScript=hook;assert(a.ui:Style(partial,'button'));partial.scripts.OnEnter(partial);assert(partial.border[1]==sdk.Themes.forever.colors.accent[1])
    assert(a:Set('fontSize',16));assert(text.fontSize==16.25 and product.fontSize==17.25)
    local protectedCalls=0;frame.protected=true;frame.SetBackdrop=function()protectedCalls=protectedCalls+1 end
    assert(a:Set('theme','custom'));frame.scripts.OnEnter(frame);assert(protectedCalls==0)
    local broken=CreateFrame('Button',nil,UIParent,'BackdropTemplate');broken.SetBackdrop=function()error('native paint failed')end
    assert(not a.ui:Style(broken,'button'));local errors=#a.log:Entries();broken.scripts.OnEnter(broken);assert(#a.log:Entries()==errors)
    before=changes;owner:Cancel();assert(a:Set('theme','modern'));assert(changes==before)
    W.event('PLAYER_LOGOUT');assert(not pcall(function()a.ui:Style(frame,'dialog')end))
end)

test('generated options and settled font layout','default panels must bind valid controls and remeasure after font changes without reopening menus or allocating again',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={font={type='font',default='Arial',label='Font'},theme={type='enum',default='modern',values={'modern','forever'},label='Theme'}}}end)
    assert(not pcall(function()a:Options(false)end))
    local panel=a:Options();boot(a);assert(panel:Open())
    local menu=panel._menus['settings:1:2'];menu:OpenMenu()
    assert(a:Set('theme','forever'));assert(menu:IsMenuOpen() and panel._refreshPending)
    menu:CloseMenu();W.tick(.01);assert(not panel._refreshPending)
    menu:OpenMenu();panel.bar:SetMinMaxValues(0,100);panel.bar:SetValue(10);assert(not menu:IsMenuOpen())
    local count=#W.frames;panel:Close();assert(panel:Open());assert(#W.frames==count)
    assert(panel:SelectPage('profiles'))
    -- Ordinary empty fields must produce feedback, while direct API misuse
    -- remains a programmer error. Missing copy selection must never confirm.
    panel._pool['profile-add'].scripts.OnClick();assert(panel._texts['profile-status']:GetText()=='Enter a profile name.')
    panel._pool['profile-name']:SetText('   ');panel._pool['profile-add'].scripts.OnClick();assert(panel._texts['profile-status']:GetText()=='Enter a profile name.')
    panel._confirm={kind='reset'};panel._pool['profile-copy-button'].scripts.OnClick();assert(not panel._confirm and panel._texts['profile-status']:GetText()=='Choose a profile.')
    assert(not pcall(function()a.profiles:Duplicate('')end));assert(not pcall(function()a.profiles:CopyFrom(nil)end))
    panel._pool['profile-name']:SetText('Other');panel._pool['profile-add'].scripts.OnClick();assert(a.profiles:Active()=='Other' and not panel._profileError)
    -- Captions keep the selected font size and grow their row when wrapping.
    assert(a:Set('theme','modern'))
    panel._pool['profile-reset'].scripts.OnClick()
    local confirm=panel._pool['profile-confirm'];local count=#W.frames
    local close=panel._pool.close;local closeMeasure=close.text.GetStringHeight
    close.text.GetStringHeight=function(self)return closeMeasure(self)*2 end
    local closeHeight=close:GetHeight();assert(panel:Refresh());assert(close:GetHeight()>closeHeight)
    local beforeHeight=confirm:GetHeight()
    local measure=confirm.text.GetStringHeight
    confirm.text.GetStringHeight=function(self)return measure(self)*2 end
    panel._pool['profile-reset'].scripts.OnClick()
    assert(confirm.text.scale==1 and confirm:GetHeight()>beforeHeight)
    local cancel=panel._pool['profile-cancel']
    assert(cancel.points[3]==confirm.points[3],'paired actions start on the same row')
    assert(confirm.text:GetText()=='Confirm replacement' and #W.frames==count)
    local click=confirm.scripts.OnClick;panel:Close();click();assert(a.profiles:Active()=='Other')
    assert(panel:Open('profiles'))
    local frameName=a.name..'_SND_Options';local found=false
    for _,name in ipairs(UISpecialFrames)do if name==frameName then found=true end end;assert(found and _G[frameName]==panel.frame)
    panel._confirm={kind='reset'};_G[frameName]:Hide();assert(not panel:IsShown() and panel._confirm==nil and panel._view==nil)
    assert(panel:Open());W.event('PLAYER_LOGOUT')
    for _,name in ipairs(UISpecialFrames)do assert(name~=frameName)end
end)

test('registered font recovers on refresh','a transient read failure must preserve the last successful binding for a live label',function()
    local a=app(basic);boot(a)
    local bar=UIParent:CreateFontString()
    local preview=UIParent:CreateFontString()
    assert(a.fonts:Apply(bar,'body',{size=18,flags='THICKOUTLINE'}))
    assert(a.fonts:Apply(preview,'body',{size=12}))
    local read=bar.GetFont
    bar.GetFont=function()error('temporarily unreadable font')end
    assert(a:Set('font','Arial'))
    assert(preview.font=='Fonts\\ARIALN.TTF' and bar.font~=preview.font)
    local ok,err=a.fonts:Apply(bar,'control',{size=9})
    assert(not ok and err.code=='unavailable')
    a.fonts:Refresh()
    local entries=a.log:Entries()
    assert(#entries==1 and entries[1].count==1)
    bar.GetFont=read
    a.fonts:Refresh()
    assert(bar.font==preview.font and bar.fontSize==18.25 and bar.flags=='THICKOUTLINE')
end)

test('font family retry and native read failures','both consumers require regular text to survive bold rejection and recover together after a transient per-object failure',function()
    local lib={List=function()return {'Family'}end,Fetch=function(_,_,name)if name=='New' then return 'New.ttf' elseif name=='Family' then return 'Family.ttf' elseif name=='Family Bold' then return 'Bold.ttf' end end}
    LibStub=function()return lib end
    local a=app(basic);boot(a);assert(a:Set('font','Family'))
    local body=UIParent:CreateFontString();local bold=UIParent:CreateFontString();bold.rejectFont='Bold.ttf'
    assert(a.fonts:Apply(body,'body',{size=13}));assert(a.fonts:Apply(bold,'emphasis',{size=13}))
    assert(body.font=='Family.ttf' and bold.font=='Family.ttf' and bold.flags=='OUTLINE')
    local broken=UIParent:CreateFontString();broken.GetFont=function()error('native read failed')end
    local ok,err=a.fonts:Apply(broken,'body');assert(not ok and err.code=='unavailable')
    local normalSize=GameFontNormal.fontSize;GameFontNormal.fontSize=13.25
    local native=UIParent:CreateFontString();local set=native.SetFont;native.SetFont=function()return false end
    assert(a.fonts:Apply(native,'body',{size=13}));assert(body.font==GameFontNormal:GetFont())
    native.SetFont=set;a.fonts:Refresh();assert(body.font=='Family.ttf' and native.font=='Family.ttf')
    assert(#a.log:Entries()==0) -- A failed application is not retained for automatic refresh.
    local measured,create=false,false;local observer=a:Scope()
    observer:Watch(a:SelectAppearance(function(v)return v end),function()measured=body.font end)
    observer:Watch(a:SelectAppearance(function(v)return v end),function()
        if create then create=false;local late=UIParent:CreateFontString();late.rejectFont='New.ttf';assert(a.fonts:Apply(late,'body'))end
    end)
    create=true;assert(a:Set('font','New'));assert(body.font==measured and body.font~='New.ttf')
    GameFontNormal.fontSize=normalSize;W.event('PLAYER_LOGOUT');LibStub=nil
end)


-- XPIsland's migration exposed stacked fields in a wide shell, absent selected
-- tabs, and native gold chrome overflowing otherwise flat theme surfaces.
test('compact options presentation','aligned fields, disabled feedback and selected navigation survive refresh and page reuse',function()
    local a=app(basic)
    local profiles=W.load('ProfilePageDefinition').Pages.Profiles()
    profiles.sections={{title='Shortcuts',controls={{type='button',id='extra',label='Extra action',action=function()end}}}}
    local panel=a:Options({width=560,pages={{id='settings',label='Settings',sections={{controls={
        {type='font',id='font',key='font',label='Font',enabled=function(app)return app:Get('enabled')end},
        {type='checkbox',id='enabled',key='enabled',label='Enabled'},
    }}}},profiles}})
    boot(a);assert(panel:Open())
    local menu=panel._pool['settings:1:font'];local label=panel._texts['settings:1:font:label']
    assert(menu.points[2]==panel.body:GetWidth()-menu:GetWidth() and label.points[2]==0,'field and label use separate columns')
    assert(not panel._texts['settings:section:1'],'untitled sections must not consume an empty heading row')
    assert(panel._pool[':tab:settings']._selected:IsShown() and not panel._pool[':tab:profiles']._selected:IsShown())
    assert(a:Set('enabled',false));assert(menu.alpha==.45 and not menu.enabled)
    assert(a:Set('enabled',true));assert(menu.alpha==1 and menu.enabled)
    assert(panel.bar.template=='BackdropTemplate' and panel.bar.thumb==panel.bar._thumb)
    assert(panel:SelectPage('profiles'));assert(panel._pool['profiles:1:extra']:IsShown())
    assert(panel._pool[':tab:profiles']._selected:IsShown() and not panel._pool[':tab:settings']._selected:IsShown())
    local count=#W.frames;assert(panel:SelectPage('settings'));panel:Close();assert(panel:Open());assert(#W.frames==count)
end)

test('rejected slider write','an adapter rejection restores the moved thumb before returning to the player',function()
    local attempts=0
    local a=app(function(name)
        local declaration=basic(name)
        local prepare=declaration.adapter.Prepare
        function declaration.adapter:Prepare(state,operation,fields)
            attempts=attempts+1
            if operation.kind=='set' and operation.path=='scale' and operation.value==1.5 then
                return false,{code='rejected',message='Unavailable at this scale'}
            end
            return prepare(self,state,operation,fields)
        end
        return declaration
    end)
    local panel=a:Options({pages={{id='display',sections={{controls={
        {type='slider',id='size',key='scale',label='Size',step=.1,editable=true},
        {type='slider',id='scale',key='scale',label='Scale',step=.1,format='percent'},
    }}}}}})
    boot(a);assert(panel:Open())
    local editable,plain=panel._pool['display:1:size'],panel._pool['display:1:scale']
    local entry,label=panel._pool['display:1:size:value'],panel._texts['display:1:scale:value']
    for _,slider in ipairs({editable,plain}) do
        slider:SetValue(1.5)
        assert(slider:GetValue()==1 and entry:GetText()=='1' and label:GetText()=='100%')
        assert(a:Get('scale')==1 and _G[a.name..'DB'].values.scale==1)
    end
    assert(attempts==2,'restoring native positions cannot submit another write')
    editable:SetValue(1.2)
    assert(attempts==3 and a:Get('scale')==1.2 and plain:GetValue()==1.2 and label:GetText()=='120%')
    panel:Close()
end)

test('native settings controls follow adapter decisions','a rejected checkbox or a normalized slider must show the saved value and accept the next gesture',function()
    local attempts=0
    local a=app(function(name)
        local declaration=basic(name)
        local prepare=declaration.adapter.Prepare
        function declaration.adapter:Prepare(state,operation,fields)
            attempts=attempts+1
            if operation.path=='enabled' and attempts==1 then return false,{code='rejected'} end
            if operation.path=='scale' then operation.value=math.floor(operation.value*2)/2 end
            return prepare(self,state,operation,fields)
        end
        return declaration
    end)
    local panel=a:Options({pages={{id='display',sections={{controls={
        {type='checkbox',id='enabled',key='enabled',label='Enable'},
        {type='slider',id='scale',key='scale',label='Scale',step=.1,editable=true},
    }}}}}})
    boot(a);assert(panel:Open())
    local check,slider=panel._pool['display:1:enabled'],panel._pool['display:1:scale']
    local entry=panel._pool['display:1:scale:value']
    local function clickCheck()
        check:SetChecked(not check:GetChecked()) -- native check buttons toggle before OnClick
        assert(W.click(check))
    end
    clickCheck()
    assert(attempts==1 and check:GetChecked() and a:Get('enabled') and _G[a.name..'DB'].values.enabled)
    clickCheck()
    assert(attempts==2 and not check:GetChecked() and not a:Get('enabled') and not _G[a.name..'DB'].values.enabled)
    slider:SetValue(1.2)
    assert(attempts==3 and slider:GetValue()==1 and entry:GetText()=='1' and a:Get('scale')==1)
    slider:SetValue(1.7)
    assert(attempts==4 and slider:GetValue()==1.5 and entry:GetText()=='1.5' and _G[a.name..'DB'].values.scale==1.5)
    panel:Close()
end)

test('editable slider','typing and dragging share one value while unfinished or invalid input cannot escape its settings view',function()
    local function fields(name)
        return {savedVariables={name..'DB'},fields={
            size={type='integer',default=12,min=8,max=16},
            enabled={type='boolean',default=true},
        }}
    end
    local function panelFor(a)
        return a:Options({pages={{id='fonts',sections={{controls={
            {type='slider',id='size',key='size',label='Size',step=2,editable=true,enabled=function(app)return app:Get('enabled')end},
            {type='slider',id='narrow',key='size',label='Narrow field',width=80,step=2,editable=true},
        }}}},{id='other'}}})
    end
    local a=app(fields)
    local panel=panelFor(a)
    boot(a);assert(panel:Open())
    local slider,entry=panel._pool['fonts:1:size'],panel._pool['fonts:1:size:value']
    assert(entry.kind=='EditBox' and entry:GetText()=='12' and slider:GetValue()==12)
    local narrow,group=panel._pool['fonts:1:narrow:value'],panel._pool['fonts:1:narrow:field']
    assert(narrow.anchors.TOPRIGHT[5]<0 and group:GetHeight()>=26+narrow:GetHeight())
    local function enter(text)
        entry:SetFocus();entry:SetText(text);entry.scripts.OnEnterPressed(entry)
        assert(not entry:HasFocus())
    end
    enter('16');assert(a:Get('size')==16 and slider:GetValue()==16 and entry:GetText()=='16')
    slider:SetValue(10);assert(a:Get('size')==10 and entry:GetText()=='10' and narrow:GetText()=='10')
    for _,invalid in ipairs({'','large','99','11','10.5','1e1000'}) do
        enter(invalid);assert(a:Get('size')==10 and entry:GetText()=='10' and slider:GetValue()==10)
    end
    entry:SetFocus();entry:SetText('14');assert(panel:Refresh() and entry:GetText()=='14')
    entry.scripts.OnEscapePressed(entry);assert(not entry:HasFocus() and entry:GetText()=='10')
    entry:SetFocus();entry:SetText('16');entry:ClearFocus();assert(entry:GetText()=='10')
    -- A committed write ends the edit, even when the source was the matching
    -- slider. A delayed Enter event must never resurrect those keystrokes.
    entry:SetFocus();entry:SetText('16')
    local oldEnter=entry.scripts.OnEnterPressed
    slider:SetValue(14);oldEnter(entry)
    assert(not entry:HasFocus() and entry:GetText()=='14' and a:Get('size')==14)
    assert(a:Set('size',12) and a.profiles:Duplicate('Second'))
    -- Equal values leave the same readout on screen but begin a new profile
    -- lifetime. Exercise switch, copy, and reset through their real commands.
    for _,command in ipairs({
        function()return a.profiles:Switch('Default')end,
        function()return a.profiles:CopyFrom('Second')end,
        function()return a.profiles:Reset()end,
    }) do
        entry:SetFocus();entry:SetText('16')
        oldEnter=entry.scripts.OnEnterPressed
        assert(command());oldEnter(entry)
        assert(not entry:HasFocus() and entry:GetText()=='12' and a:Get('size')==12)
    end
    assert(a:Set('size',10))
    entry:SetFocus();entry:SetText('14');assert(panel:SelectPage('other'))
    assert(not entry:IsShown() and not entry:HasFocus() and a:Get('size')==10)
    assert(panel:SelectPage('fonts'));local count=#W.frames
    entry:SetFocus();entry:SetText('8');assert(panel:Close() and panel:Open())
    assert(not entry:HasFocus() and entry:GetText()=='10' and #W.frames==count)
    entry:SetFocus();entry:SetText('16');assert(a:Set('enabled',false))
    assert(not entry:IsEnabled() and not slider:IsEnabled() and not entry:HasFocus() and entry:GetText()=='10')
    panel:Close()
    local b=app(fields);local locked=panelFor(b)
    _G[b.name..'DB']={version=999}
    boot(b);assert(locked:Open())
    assert(not locked._pool['fonts:1:size:value']:IsEnabled() and not locked._pool['fonts:1:size']:IsEnabled())
    assert(_G[b.name..'DB'].version==999);locked:Close()
end)

test('single-page settings shell','a single page recovers its navigation space and preserves the slider value when resized or reopened',function()
    local a=app(basic)
    local page={id='display',label='Display',sections={{title='Display options',controls={
        {type='slider',key='scale',label='Scale',step=.1,format='percent'},
        {type='font',key='font',label='Font'},
    }}}}
    local panel=a:Options({title='Settings',width=520,height=240,pages={page}})
    boot(a);assert(panel:Open())
    assert(not panel._pool[':tab:display'],'single-page windows do not have a tab strip')
    assert(panel._texts.title.fontSize>panel._texts['display:section:1'].fontSize)
    local top=panel.scroll.anchors.TOPLEFT
    assert(-top[3] >= 10+panel._pool.close:GetHeight() and -top[3] < 70,'viewport starts just below the title and close button')
    assert(not panel.bar:IsShown() and panel.body:GetWidth()==488,'fitted fields use both margins without a scrollbar gutter')
    local id='display:1:1'
    local slider,label,value=panel._pool[id],panel._texts[id..':label'],panel._texts[id..':value']
    assert(label:GetText()=='Scale' and value and value:GetText()=='100%')
    local inset=value.anchors.LEFT
    assert(inset and inset[2]==slider and inset[3]=='RIGHT' and inset[4]>0 and value.justifyH=='RIGHT')
    local railWidth=slider:GetWidth()
    slider:SetValue(1.5)
    assert(a:Get('scale')==1.5 and label:GetText()=='Scale' and value:GetText()=='150%' and slider:GetWidth()==railWidth)
    local count=#W.frames
    local oldWidth,oldHeight=UIParent:GetWidth(),UIParent:GetHeight()
    UIParent:SetSize(260,164);W.event('DISPLAY_SIZE_CHANGED')
    assert(panel.bar:IsShown() and value:IsShown(),'the slider value remains available on short screens')
    UIParent:SetSize(oldWidth,oldHeight);W.event('DISPLAY_SIZE_CHANGED')
    panel:Close();assert(panel:Open() and #W.frames==count and value:IsShown())

    local b=app(basic)
    local multi=b:Options({title='Settings',width=520,height=240,pages={page,{id='other',label='Other'}}})
    boot(b);assert(multi:Open())
    assert(-multi.scroll.anchors.TOPLEFT[3]>=-top[3]+multi._pool[':tab:display']:GetHeight())
    assert(W.click(multi._pool[':tab:other']) and multi._page=='other')
    multi:Close();panel:Close()
end)

test('text close button setup retry','a temporary caption or anchor refusal must not leave an unusable pooled close button',function()
    local a=app(basic)
    local panel=a:Options({pages={{id='main'}}})
    boot(a)
    local apply=a.fonts.Apply
    a.fonts.Apply=function(self,label,...)
        if panel._pool.textClose and label:GetParent()==panel._pool.textClose then
            return false,{message='close caption refused'}
        end
        return apply(self,label,...)
    end
    local ok,err=panel:Open()
    assert(not ok and err.message:find('close caption refused',1,true))
    a.fonts.Apply=apply
    local close,caption=panel._pool.textClose,panel._texts['textClose:text']
    local point,count=close.SetPoint,#W.frames
    close.SetPoint=function()error('close anchor refused')end
    ok,err=panel:Open()
    assert(not ok and err.message:find('close anchor refused',1,true))
    close.SetPoint=point
    assert(panel:Open() and panel._pool.close==close and #W.frames==count)
    assert(close.text==caption and caption:GetText()=='×' and close:GetWidth()==26)
    assert(close.points[1]=='TOPRIGHT' and close.points[2]==-10 and close.points[3]==-10)
    assert(W.click(close) and not panel._view and not panel:IsShown())
    assert(panel:Open() and #W.frames==count and W.click(close))
end)

test('Forever native close button','click and Escape release the page; only the active theme owns the close hit area',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={
        theme={type='enum',default='forever',values={'forever','modern'}},
    }}end)
    local panel=a:Options({pages={{id='main'}}})
    boot(a);assert(panel:Open())
    local native=panel._pool.close
    assert(native.template=='UIPanelCloseButtonDefaultAnchors' and not panel._pool.textClose and not native.hitInsets)
    assert(native:GetWidth()==24 and native:GetHeight()==24 and native.points[1]=='TOPRIGHT')
    assert(native.points[2]==-2 and native.points[3]==1)
    assert(W.click(native) and not panel:IsShown() and not panel._view)
    assert(panel:Open() and panel._pool.close==native)
    assert(a:Set('theme','modern'))
    local text=panel._pool.close
    assert(text~=native and text.text:GetText()=='×' and not W.click(native) and panel:IsShown())
    local count=#W.frames
    assert(a:Set('theme','forever') and panel._pool.close==native and not W.click(text))
    local name=a.name..'_SND_Options'
    for _,entry in ipairs(UISpecialFrames)do if entry==name then _G[entry]:Hide() end end
    assert(not panel:IsShown() and not panel._view)
    assert(panel:Open() and panel._pool.close==native and #W.frames==count)
    assert(W.click(native))
end)

test('Forever native control artwork','the dialog rim, slider track and thumb appear together and release their art when switching themes',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={
        theme={type='enum',default='forever',values={'modern','forever'}},
        size={type='integer',default=12,min=8,max=16},
    }}end)
    local panel=a:Options({pages={{id='font',sections={{controls={
        {id='size',type='slider',key='size',label='Font size'},
        {id='style',type='select',key='theme',label='Style',choices={{value='forever',label='WoW Forever'},{value='modern',label='Modern'}}},
    }}}}}})
    boot(a);assert(panel:Open())
    local slider=panel._pool['font:1:size']
    local menu=panel._pool['font:1:style']
    local chrome=panel.frame:GetBackdrop()
    assert(chrome.edgeFile=='Interface\\DialogFrame\\UI-DialogBox-Border' and chrome.edgeSize==32)
    assert(chrome.bgFile=='Interface\\DialogFrame\\UI-DialogBox-Background-Dark')
    assert(chrome.insets.left==11 and chrome.insets.right==12 and chrome.insets.top==12 and chrome.insets.bottom==11)
    assert(math.min(unpack(panel.frame.border))>.8,'the dialog edge must retain its engraved highlights')
    assert(menu:GetBackdrop().edgeFile=='Interface\\Tooltips\\UI-Tooltip-Border')
    assert(menu.Text.justifyH=='LEFT' and menu.Text.anchors.LEFT[4]>0,'text starts inside the field border')
    local track={}
    for _,region in ipairs(W.frames) do
        if region.parent==slider and region.atlas then track[region.atlas]=region end
    end
    for _,atlas in ipairs({'Minimal_SliderBar_Left','_Minimal_SliderBar_Middle','Minimal_SliderBar_Right'}) do
        assert(track[atlas] and track[atlas]:IsShown(),atlas..' must be visible on the slider')
    end
    assert(slider.thumb.texture=='Interface\\Buttons\\UI-SliderBar-Button-Horizontal')
    assert(not slider:GetBackdrop() or not slider:GetBackdrop().edgeFile,'the slider rail must not have a full-size border')
    slider:SetValue(14);assert(a:Get('size')==14)
    assert(a:Set('theme','modern'))
    for _,texture in pairs(track) do assert(not texture:IsShown(),'native rail leaked into Modern') end
    assert(menu.Text.justifyH=='CENTER' and slider:GetBackdrop().edgeSize==1 and slider:GetValue()==14)
    assert(slider.thumb:GetWidth()==10 and slider.thumb:GetHeight()==18)
    local count=#W.frames
    assert(a:Set('theme','forever') and #W.frames==count)
    for _,texture in pairs(track) do assert(texture:IsShown(),'reused rail must be visible') end
    assert(slider.thumb:GetWidth()==24 and slider.thumb:GetHeight()==24)
    panel:Close()

    -- A missing atlas can fail partway through dressing the three rail pieces.
    local retry=CreateFrame('Slider',nil,UIParent,'BackdropTemplate')
    retry:SetOrientation('HORIZONTAL')
    local create,failed=retry.CreateTexture,false
    function retry:CreateTexture(...)
        local texture=create(self,...)
        local setAtlas=texture.SetAtlas
        function texture:SetAtlas(atlas)
            if atlas=='_Minimal_SliderBar_Middle' and not failed then
                failed=true;error('simulated missing slider atlas')
            end
            setAtlas(self,atlas)
        end
        return texture
    end
    assert(not a.ui:Style(retry,'slider') and failed)
    count=#W.frames;assert(a.ui:Style(retry,'slider') and #W.frames==count)
    assert(retry.thumb:GetWidth()==24 and retry._sndControlArt.railMiddle.atlas=='_Minimal_SliderBar_Middle')
end)

test('shared native control styling','native state changes preserve the palette, failed art creation retries without leaks, and refresh preserves slider gestures',function()
    local a,sdk=app(basic);boot(a)
    local menu=CreateFrame('DropdownButton',nil,UIParent,'WowStyle1DropdownTemplate,BackdropTemplate')
    assert(a.ui:Style(menu,'dropdown'));menu:OnButtonStateChanged()
    assert(menu.Text.textColor[1]==sdk.Themes.modern.colors.text[1] and not menu.Arrow:IsShown())
    local slider=CreateFrame('Slider',nil,UIParent,'BackdropTemplate')
    local original=slider.SetThumbTexture
    slider.SetThumbTexture=function()error('thumb failure')end
    assert(not a.ui:Style(slider,'slider'));local count=#W.frames
    slider.SetThumbTexture=original;assert(a.ui:Style(slider,'slider'));assert(#W.frames==count)
    slider:SetEnabled(false);assert(slider.alpha==.45);slider:SetEnabled(true);assert(slider.alpha==1)
    local panel=a:Options({width=320,pages={{id='settings',label='Settings',sections={{controls={
        {type='slider',id='scale',key='scale',label='Scale',min=.5,max=2,step=.1},
    }}}},sdk.Pages.Profiles()}})
    assert(panel:Open());local control=panel._pool['settings:1:scale'];local hides=0
    control:HookScript('OnHide',function()hides=hides+1 end)
    local originalSet=control.SetValue;local nested=0
    control.SetValue=function(self,value)
        originalSet(self,value)
        if nested==0 then nested=1;assert(panel:Refresh())end
    end
    assert(a:Set('scale',1.2));assert(nested==1 and panel:IsShown())
    assert(hides==0,'value refresh must not end a drag by hiding its slider')
    assert(panel:SelectPage('profiles'));assert(hides==1)
    for _,widget in pairs(panel._pool)do
        if widget:GetParent()==panel.body and widget:IsShown() then
            assert(widget:GetWidth()<=panel.body:GetWidth(),'profile controls fit narrow body')
            assert((widget.points[2] or 0)==0,'narrow profile actions stack')
        end
    end
end)

test('mouse navigation and color field layout','buttons must accept input; swatches align with fields and follow commit/cancel across page clicks',function()
    local a=app(basic)
    local panel=a:Options({width=560,pages={
        {id='appearance',label='Appearance',sections={{controls={
            {type='color',id='color',key='color',label='Normal XP'},
            {type='font',id='font',key='font',label='Font'},
        }}}},
        {id='behavior',label='Behavior',sections={{controls={{type='checkbox',key='enabled',label='Enabled'}}}}},
        {id='tracking',label='Tracking',sections={}},
        W.load('MouseProfiles').Pages.Profiles(),
    }})
    boot(a);assert(panel:Open())
    assert(W.click(panel._pool[':tab:behavior']),'tab must accept a mouse click')
    assert(panel._page=='behavior');assert(W.click(panel._pool[':tab:appearance']))
    local color=panel._pool['appearance:1:color'];local label=panel._texts['appearance:1:color:label']
    local font=panel._pool['appearance:1:font']
    assert(color.points[2]==font.points[2] and label.points[2]==0)
    assert(color._swatch.color[1]==1 and color.text:GetText()=='')
    assert(W.click(color));W.color(.2,.4,.6,true)
    assert(a:Get('color')[1]==.2 and color._swatch.color[1]==.2)
    assert(W.click(color));W.color(.9,.8,.7,true,true)
    assert(a:Get('color')[1]==.2 and color._swatch.color[1]==.2)
    for _,id in ipairs({'behavior','tracking','profiles','appearance'})do
        assert(W.click(panel._pool[':tab:'..id]));assert(panel._page==id and panel:IsShown())
        assert(panel._pool[':tab:'..id]._selected:IsShown())
    end
    local count=#W.frames;assert(W.click(panel._pool.close));assert(not panel:IsShown())
    assert(not W.click(panel._pool[':tab:behavior']))
    assert(panel:Open());assert(W.click(panel._pool[':tab:behavior']));assert(#W.frames==count)
end)

-- Reuse the exact layout path used by generated options in a custom view. These
-- contracts protect native-failure retry, width reflow and readable captions.
-- Native methods verified in Forever 1.60.1.70338 at
-- 943764493e6b16d63ded3ab304150d1f05e58b57: SimpleFrame SetHitRectInsets,
-- SimpleScriptRegion EnableMouse, SimpleButton RegisterForClicks, and
-- SimpleButton/SimpleEditBox/SimpleSlider SetEnabled + IsEnabled. Native
-- hit routing itself still requires an in-client check.
test('public form layout and controls','custom views share measured rows and input setup without owning another settings store',function()
    local a=app();boot(a)
    local parent=CreateFrame('Frame',nil,UIParent);parent:SetSize(500,400)
    local original=CreateFrame;local first
    CreateFrame=function(...)
        local f=original(...);first=f
        f.EnableMouse=function()error('input unavailable')end
        return f
    end
    assert(not a.ui:Control(parent,'action','button'));CreateFrame=original
    first.EnableMouse=nil;local count=#W.frames
    local ok,button=a.ui:Control(parent,'action','button');assert(ok and button==first and #W.frames==count)
    local clicks=0;button:SetScript('OnClick',function()clicks=clicks+1 end);assert(W.click(button) and clicks==1)
    assert(a.ui:Control(parent,'action','button'));assert(W.click(button) and clicks==2)
    button:SetEnabled(false);assert(button.alpha==.45 and not W.click(button));button:SetEnabled(true);assert(button.alpha==1)
    assert(not pcall(function()a.ui:Control(parent,'action','checkbox')end))
    local label=parent:CreateFontString();label:SetText('Normal XP')
    button:SetHeight(26)
    local placed,height=a.layout:Row(parent,{width=500,label=label,control=button,controlWidth=36})
    assert(placed and button:GetWidth()==36 and button.points[2]==270 and label.points[2]==0)
    assert(a.layout:Row(parent,{width=250,label=label,control=button,controlWidth=36}))
    assert(button.points[2]==0 and button.points[3]<label.points[3],'narrow field stacks at readable font size')
    local actionLabel=button:CreateFontString();actionLabel:SetText(string.rep('Long caption ',10))
    assert(a.layout:Row(parent,{width=160,kind='action',control=button,label=actionLabel,align='stretch'}))
    assert(actionLabel.scale==1 and button:GetHeight()>26)
    local _,check=a.ui:Control(parent,'check','checkbox');check:SetSize(20,20)
    assert(a.layout:Row(parent,{width=250,kind='check',control=check,label=label}))
    assert(check.hitInsets[2]==-230,'label is included in the native hit rectangle')
    local _,edit=a.ui:Control(parent,'edit','input');edit:SetFocus();edit:Hide();assert(not edit.focus)
    local columns,cw=a.layout:Columns(500,{columns=2,minColumnWidth=220});assert(columns==2 and cw==242)
    columns,cw=a.layout:Columns(300,{columns=2,minColumnWidth=220});assert(columns==1 and cw==300)
    assert(not pcall(function()a.layout:Columns(300,{columns=1.5})end))
    assert(not pcall(function()a.layout:Row(parent,{width=0})end))
    local setPoint=button.SetPoint;button.SetPoint=function()error('native placement failure')end
    assert(not a.layout:Row(parent,{width=500,label=label,control=button}))
    button.SetPoint=setPoint;assert(a.layout:Row(parent,{width=500,label=label,control=button}))
    W.event('PLAYER_LOGOUT');assert(not a.ui:Control(parent,'new','button'))
end)

test('column-first options sections','related controls stay together when a multicolumn page narrows or hides a cell',function()
    local a=app(basic)
    assert(not pcall(a.Options,a,{pages={{id='p',sections={{flow='diagonal'}}}}}))
    local controls={}
    for _,id in ipairs({'a','b','c','d','e'}) do
        controls[#controls+1]={type='button',id=id,label=id,action=function()end,
            visible=id=='b' and function(app)return app:Get('enabled')end or nil}
    end
    local p=a:Options({width=660,pages={{id='p',sections={{
        flow='column',layout={columns=3,minColumnWidth=180},controls=controls,
    }}}}})
    boot(a);assert(p:Open())
    local function xy(id)local point=p._pool['p:1:'..id].points;return point[2],point[3]end
    local ax,ay=xy('a');local bx,by=xy('b');local cx,cy=xy('c');local dx,dy=xy('d');local ex,ey=xy('e')
    assert(ax==bx and cx==dx and ax<cx and cx<ex and ay==cy and cy==ey and by==dy and by<ay)
    assert(a:Set('enabled',false))
    cx,cy=xy('c');dx,dy=xy('d')
    assert(not p._pool['p:1:b']:IsShown() and cx==ax and cy==by and dx>cx and dy==ay)
    assert(a:Set('enabled',true))
    local old=UIParent:GetWidth();UIParent:SetWidth(240);W.event('DISPLAY_SIZE_CHANGED')
    local last
    for _,id in ipairs({'a','b','c','d','e'})do
        local x,y=xy(id);assert(x==ax and (not last or y<last));last=y
    end
    UIParent:SetWidth(old);W.event('DISPLAY_SIZE_CHANGED');p:Close()
end)

test('responsive options sections','screen changes collapse fields, columns and navigation without losing controls or font size',function()
    local a=app(basic)
    local panel=a:Options({width=560,pages={
        {id='form',label='Appearance',sections={
            {controls={{type='font',id='font',key='font',label='Font'},{type='color',key='color',label='Tint',width=36}}},
            {layout={columns=2,minColumnWidth=220},controls={
                {type='button',id='one',label='First action',align='stretch',visible=function(app)return app:Get('enabled')end,action=function()end},
                {type='button',id='two',label='Second action',align='stretch',action=function()end},
            }},
        }},
        {id='behavior',label='Behavior'},{id='tracking',label='Tracking'},{id='profiles',label='Profiles'},
    }})
    boot(a);assert(panel:Open())
    local one,two=panel._pool['form:2:one'],panel._pool['form:2:two']
    assert(one.points[3]==two.points[3] and two.points[2]>one.points[2])
    assert(a:Set('enabled',false));assert(not one:IsShown() and two.points[2]==0,'hidden cells leave no gap')
    assert(a:Set('enabled',true));assert(one:IsShown() and two.points[2]>0)
    local count=#W.frames;local old=UIParent:GetWidth();UIParent:SetWidth(360);W.event('DISPLAY_SIZE_CHANGED')
    assert(panel.frame:GetWidth()==344 and panel.frame.scale==1)
    assert(panel._pool['form:1:font'].points[2]==0)
    assert(two.points[2]==0 and two.points[3]<one.points[3])
    assert(panel._pool[':tab:tracking'].points[3]<panel._pool[':tab:form'].points[3])
    for _,b in pairs(panel._buttons)do assert(b.text.scale==1)end
    assert(W.click(panel._pool[':tab:behavior']) and panel._page=='behavior')
    assert(W.click(panel._pool[':tab:form']));UIParent:SetWidth(old);W.event('DISPLAY_SIZE_CHANGED')
    assert(one.points[3]==two.points[3] and #W.frames==count)
    panel:Close();assert(panel:Open());assert(#W.frames==count)
    local oldHeight=UIParent:GetHeight();UIParent:SetSize(200,180);W.event('DISPLAY_SIZE_CHANGED')
    assert(panel.frame:GetHeight()*panel.frame.scale<=164.001,'wrapped header and viewport fit short screens')
    assert(panel.frame:GetHeight()>=200,'wrapped header reserves a usable body')
    UIParent:SetSize(old,oldHeight);W.event('DISPLAY_SIZE_CHANGED')
end)

-- User report: native navigation/closing left options-page registered, so the
-- next slash command raised "scope name already active". Native DropdownButton
-- CloseMenu also calls SignalUpdate when closed (Forever 70338, DropdownButton.lua),
-- unlike the old fixture. A failing cleanup must never retain the page observer.
test('options navigation and cleanup recovery','tabs replace the page without hiding the shell, and failed cleanup cannot block reopening',function()
    local a=app(basic);local panel=a:Options({pages={
        {id='appearance',sections={{controls={{type='font',id='font',key='font',label='Font'}}}}},
        {id='behavior',sections={{controls={{type='checkbox',id='enabled',key='enabled',label='Enabled'}}}}},
    }})
    boot(a);assert(panel:Open());local first=panel._view
    local hides=0;panel.frame:HookScript('OnHide',function()hides=hides+1 end)
    local menu=panel._pool['appearance:1:font'];local closeMenu=menu.CloseMenu
    menu.CloseMenu=function(self)closeMenu(self);error('native selection refresh failed after closing')end
    -- Closed native dropdowns do not need CloseMenu/SignalUpdate at navigation.
    assert(W.click(panel._pool[':tab:behavior']))
    assert(panel._page=='behavior' and panel._pool['behavior:1:enabled']:IsShown())
    assert(not first.active and hides==0,'tab navigation must not hide/reopen the shell')
    assert(W.click(panel._pool[':tab:appearance']));menu:OpenMenu()
    local second=panel._view
    assert(pcall(panel.frame.Hide,panel.frame));assert(not panel:IsShown() and not second.active and panel._view==nil)
    menu.CloseMenu=closeMenu;assert(panel:Open('behavior'))
    local check=panel._pool['behavior:1:enabled'];check:SetChecked(false);assert(W.click(check));assert(not a:Get('enabled'))
    -- Recover the reported hidden-window/stale-owner state, even when a native
    -- OnHide callback was previously interrupted before cleanup completed.
    local stale=panel._view;panel.frame.shown=false
    assert(panel:Open('appearance'));assert(not stale.active and panel._view.active)
    assert(W.click(panel._pool[':tab:behavior']));check:SetChecked(true);assert(W.click(check));assert(a:Get('enabled'))
    local nested=false
    panel.frame:HookScript('OnShow',function()
        local ok,err=panel:Open();assert(not ok and err.code=='reentrant');nested=true
    end)
    local count=#W.frames
    for _=1,10 do panel.frame:Hide();assert(panel:Open());assert(W.click(panel._pool[':tab:appearance']));assert(W.click(panel._pool[':tab:behavior']))end
    assert(nested and #W.frames==count)
    panel:Close();assert(panel._view==nil)
    local closeOnShow=true
    panel.frame:HookScript('OnShow',function()if closeOnShow then closeOnShow=false;assert(panel:Close())end end)
    assert(not panel:Open());assert(not panel:IsShown() and panel._view==nil)
    assert(panel:Open());assert(panel._view.active)
    panel:Close()
    local show=panel.frame.Show;panel.frame.Show=function()error('native show failed')end
    assert(not panel:Open());assert(panel._view==nil and not panel._opening)
    panel.frame.Show=show;assert(panel:Open());assert(panel._view.active)
end)

test('options survive inherited visibility','restoring the game interface rebinds an open preview and controls, while a closed panel stays closed',function()
    local original=UIParent
    UIParent=CreateFrame('Frame');UIParent:SetSize(original:GetWidth(),original:GetHeight())
    local a=app(basic)
    local host,owner,preview,fail
    local panel=a:Options({header={width=44,create=function(parent,app,scope)
        if fail then error('preview unavailable')end
        assert(not host or host==parent);host,owner=parent,scope
        return {Refresh=function()preview=app:Get('font')end,Layout=function()return 44 end,Hide=function()preview=nil end}
    end},pages={{id='first'},{id='display',sections={{controls={{type='font',id='font',key='font'}}}}}}})
    boot(a);assert(panel:Open('display') and host:IsVisible());local first=owner
    UIParent:Hide()
    assert(panel:IsShown() and not panel.frame:IsVisible() and not first.active and not preview)
    assert(a:Set('font','Arial'));assert(panel:Refresh() and not preview)
    UIParent:Show()
    assert(panel._page=='display' and owner~=first and owner.active and host:IsVisible() and preview=='Arial')
    local menu=panel._menus['display:1:font'];menu:OpenMenu()
    for _,row in ipairs(menu.root.rows)do if row.value=='Friz Quadrata' then row.choose(row.value)end end
    menu:CloseMenu();W.tick(.01)
    assert(a:Get('font')=='Friz Quadrata' and preview=='Friz Quadrata')
    UIParent:Hide();assert(panel:Close());UIParent:Show()
    assert(not panel:IsShown() and not owner.active)
    UIParent:Hide();assert(panel:Open() and panel:IsShown() and not preview)
    fail=true;UIParent:Show();assert(not panel:IsShown() and not panel._view)
    fail=false;assert(panel:Open() and host:IsVisible() and preview=='Friz Quadrata')
    assert(panel:Close() and not owner.active);UIParent=original
end)

test('equal-value profile replacement','reset/copy/switch must invalidate previews and consumer gestures even without changed fields',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={color={type='color',default={1,1,1}}}}end)
    local preview;local p=a:Options({pages={{id='color',sections={{controls={{type='color',key='color',preview=function(v)preview=v end}}}}},{id='profiles',_profiles=true}}})
    boot(a);assert(p:Open());assert(a.profiles:Duplicate('Same'))
    local changes=0
    local listener=a:OnSettingsChanged(function(_,change)
        changes=changes+1;assert(not next(change.keys));assert(change.reason~='set' and change.reason~='patch')
    end)
    for _,replace in ipairs({function()return a.profiles:Reset()end,function()return a.profiles:CopyFrom('Default')end,function()return a.profiles:Switch('Same')end})do
        assert(W.click(p._pool['color:1:1']));local stale=ColorPickerFrame.info.swatchFunc
        local _,revision=a._settingsStore:Read()
        W.color(.2,.3,.4);assert(preview[1]==.2 and a:Get('color')[1]==1)
        assert(replace());assert(preview[1]==1 and not ColorPickerFrame:IsShown())
        stale();assert(a:Get('color')[1]==1)
        local ok,err=a:Set('color',{.2,.3,.4},revision);assert(not ok and err.code=='stale')
    end
    assert(changes==3)
    assert(a:Set('color',{1,1,1}));assert(a:SetMany({color={1,1,1}}));assert(changes==3)
    listener:Cancel()
    assert(W.click(p._pool['color:1:1']));W.color(.4,.5,.6)
    assert(not a.profiles:CopyFrom('Missing'));assert(ColorPickerFrame:IsShown() and preview[1]==.4)
    W.color(.4,.5,.6,true);assert(a:Get('color')[1]==.4)
    assert(a.profiles:Reset());assert(p:Open('profiles'));assert(W.click(p._pool['profile-reset']))
    assert(p._confirm and p._pool['profile-confirm']:IsShown())
    assert(a.profiles:Reset());assert(not p._confirm and not p._pool['profile-confirm']:IsShown())
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

-- Forever 94376449, Blizzard_Menu/Vanilla/MenuVariants.lua and Menu.lua:
-- the popup owns compositor textures and a native radio owns leftTexture1.
test('Forever popup presentation','only owned menus receive an opaque fill and a single selected check',function()
    local a,sdk=app()
    a:Appearance({defaultTheme='forever',themes={forever=sdk.Themes.forever,modern=sdk.Themes.modern}})
    a:Settings({savedVariables={a.name..'DB'},fields={theme={type='enum',values={'forever','modern'},default='forever'}}})
    local choices={{label='Forever',value='forever'},{label='Modern',value='modern'}}
    local panel=a:Options({pages={{id='p',sections={{controls={{type='select',id='theme',key='theme',label='Theme',choices=choices}}}}}}})
    boot(a);assert(panel:Open())
    local dropdown=panel._menus['p:1:theme'];dropdown:OpenMenu()
    local root=dropdown.root
    local fill=root.popup.children[1]
    assert(fill and fill.layer=='BACKGROUND' and fill.color[4]==1 and fill.color[1]<.2)
    local first,second=root.rows[1],root.rows[2]
    assert(first.button.leftTexture1.atlas=='common-dropdown-icon-checkmark-yellow-classic-2')
    assert(first.button.leftTexture1.width==20 and second.button.leftTexture1.atlas==nil)
    assert(first.button.highlight.texture=='Interface\\QuestFrame\\UI-QuestTitleHighlight')

    local foreign=CreateFrame('DropdownButton',nil,UIParent,'WowStyle1DropdownTemplate')
    foreign:SetupMenu(function(_,menu)menu:CreateRadio('Other',function()return false end,function()end)end)
    foreign:OpenMenu()
    assert(#foreign.root.popup.children==0 and foreign.root.rows[1].button.leftTexture1.atlas=='common-dropdown-tickradial-classic')
    foreign:CloseMenu()

    second.choose(second.value);assert(a:Get('theme')=='modern')
    dropdown:CloseMenu();W.tick(.01);dropdown:OpenMenu()
    assert(#dropdown.root.popup.children==0)
    assert(dropdown.root.rows[2].button.leftTexture1.atlas=='common-dropdown-icon-radialtick-yellow-classic')
    dropdown:CloseMenu();panel:Close()
end)

test('dropdown callback identity','native selections retained across profile changes or page reuse cannot edit the new owner',function()
    local a=app(function(name)return {savedVariables={name..'DB'},fields={choice={type='enum',default='a',values={'a','b'}},enabled={type='boolean',default=true}}}end)
    local p=a:Options();boot(a);assert(p:Open())
    local d=p._menus['settings:1:1']
    local function selectB()d:OpenMenu();local row=d.root.rows[2];return function(input)row.choose(row.value,input)end end
    local dismissed=selectB();d:CloseMenu()
    dismissed({context=MenuInputContext.MouseButton});assert(a:Get('choice')=='a')
    local wheel=selectB()
    dismissed({context=MenuInputContext.MouseButton});dismissed({context=MenuInputContext.MouseWheel})
    assert(a:Get('choice')=='a','a successor root owns the active selection')
    d:CloseMenu();wheel({context=MenuInputContext.MouseWheel});assert(a:Get('choice')=='b')
    assert(a:Set('choice','a'))
    local stale=selectB();assert(a.profiles:Duplicate('Other'));stale();assert(a:Get('choice')=='a')
    stale=selectB();assert(a:Set('enabled',false));stale();assert(a:Get('choice')=='a')
    d:CloseMenu();W.tick(.01)
    stale=selectB();p:Close();assert(p:Open());stale();assert(a:Get('choice')=='a')
    local current=selectB();current();d:CloseMenu();W.tick(.01);assert(a:Get('choice')=='b')
    assert(p:Open('profiles'));local menu=p._menus['profile-select'];menu:OpenMenu()
    local row=menu.root.rows[1];assert(a.profiles:Reset());row.choose(row.value)
    assert(a.profiles:Active()=='Other')
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

-- Forever 70338 SimpleFrame:RegisterEvent returns a boolean, not just an exception.
test('native event refusal','a false registration result must not publish a subscription or prevent a later retry',function()
    local a=app();boot(a);local owner=a:Scope();local register=a._frame.RegisterEvent
    a._frame.RegisterEvent=function()return false end
    local ok,err=owner:Event('PLAYER_ENTERING_WORLD',function()end)
    assert(not ok and err.code=='unavailable' and not next(owner._handles))
    a._frame.RegisterEvent=register;local calls=0
    local accepted,handle=owner:Event('PLAYER_ENTERING_WORLD',function()calls=calls+1 end)
    assert(accepted);W.event('PLAYER_ENTERING_WORLD');assert(calls==1)
    handle:Cancel();assert(not a._frame.events.PLAYER_ENTERING_WORLD)
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

test('hidden drag recovery','hiding during a drag must not suspend containment for the next window lifetime',function()
    local a=app();boot(a);local frame=CreateFrame('Frame',nil,UIParent);frame:SetSize(100,100)
    local ok,handle=a.layout:KeepOnScreen(frame,{margin=10});assert(ok)
    frame.scripts.OnDragStart(frame);frame.left=1500;assert(handle:Refresh());assert(frame.left==1500)
    frame:Hide();frame:Show();assert(frame.left==1170)
    frame.scripts.OnDragStart(frame);frame.left=-20;frame.scripts.OnDragStop(frame);assert(frame.left==10)
    handle:Cancel();a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

-- Forever 70338 geometry methods can return nothing or restricted values. The
-- fixture detects inspection before guards; it does not emulate native secrets.
test('layout failure and unresolved geometry','unavailable geometry preserves anchors; native failures return Results and leave refresh retryable',function()
    local a=app();boot(a);local f=CreateFrame('Frame',nil,UIParent);f:SetSize(100,100)
    f:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',10,10)
    local ok,h=a.layout:KeepOnScreen(f);assert(ok)
    local points=f.points;local getWidth=f.GetWidth;f.GetWidth=function()return nil end
    local placed,err=h:Refresh();assert(not placed and err.code=='unavailable' and f.points==points)
    f.GetWidth=getWidth;local getScale=f.GetEffectiveScale
    local secret=setmetatable({}, {__div=function()error('inspected secret')end});local previous=issecretvalue
    issecretvalue=function(value)return value==secret end;f.GetEffectiveScale=function()return secret end
    placed,err=h:Refresh();assert(not placed and err.code=='unavailable' and f.points==points)
    f.GetEffectiveScale=getScale;issecretvalue=previous
    local setPoint=f.SetPoint;f.left=1500;f.SetPoint=function()error('native anchor failed')end
    local called;called,placed,err=pcall(h.Refresh,h);assert(called and not placed and err.code=='unavailable')
    f.SetPoint=function(self,...)assert(h:Refresh());return setPoint(self,...)end
    assert(h:Refresh());assert(f.left==1180)
    h:Cancel();assert(not a._frame.events.DISPLAY_SIZE_CHANGED)
    a._frame.scripts.OnEvent(a._frame,'PLAYER_LOGOUT')
end)

test('custom control visibility','hidden, failed and superseded controls release their subscriptions without disturbing their page',function()
    local a=app(basic)
    local host,owner,fail
    local creates,hides,events=0,0,0
    local sample={id='sample',type='custom',visible=function(app)return app:Get('enabled')end}
    function sample.create(parent,app,scope)
        assert(not host or host==parent)
        host,owner=parent,scope;creates=creates+1
        assert(owner:Event('PLAYER_ENTERING_WORLD',function()events=events+1 end))
        if fail then error('sample construction failed') end
        return {Refresh=function()end,Layout=function()return 20 end,Hide=function()hides=hides+1 end}
    end
    local panel=a:Options({pages={{id='sample',sections={{controls={sample}}}},{id='other'}}})
    boot(a);assert(panel:Open());W.event('PLAYER_ENTERING_WORLD');assert(events==1)
    local first=owner
    assert(a:Set('enabled',false));assert(not first.active and not host:IsShown() and hides==1)
    assert(a:Set('scale',1.5));W.event('PLAYER_ENTERING_WORLD');assert(events==1 and hides==1)
    assert(a:Set('enabled',true));assert(owner~=first and owner.active and host:IsShown() and creates==2)
    W.event('PLAYER_ENTERING_WORLD');assert(events==2)
    assert(panel:SelectPage('other'));assert(not owner.active and hides==2)
    fail=true
    local ok,err=panel:SelectPage('sample')
    assert(not ok and err.message:find('sample construction failed',1,true) and not owner.active)
    W.event('PLAYER_ENTERING_WORLD');assert(events==2 and hides==2)
    fail=false
    assert(panel:Open() and host:IsShown() and creates==4)
    W.event('PLAYER_ENTERING_WORLD');assert(events==3)
    assert(panel:Close());assert(not owner.active and hides==3)
end)

test('options subheader component','a fixed selector sits below the title and stacks clear of the preview and scrolling controls',function()
    for _,withPreview in ipairs({false,true})do
        local a=app(basic);local parent,owner,preview
        local function component(height)return {Refresh=function()end,Hide=function()end,Layout=function()return height end}end
        local p=a:Options({title='A title',width=440,subheader={width=200,create=function(host,_,scope)
            assert(not parent or host==parent);parent,owner=host,scope;return component(26)
        end},header=withPreview and {width=46,create=function(host)preview=host;return component(46)end} or nil,
            pages={{id='main'}}})
        boot(a);assert(p:Open());local initial=owner
        local function check()
            local bottom=-parent.points[3]+26
            assert(-parent.points[3]>=16+p._texts.title:GetStringHeight() and parent.points[2]==16)
            assert(bottom< -p.scroll.anchors.TOPLEFT[3])
        end
        check();assert(parent:GetWidth()==200)
        if preview then assert(preview.points[3]==-16 and preview.points[1]=='TOPRIGHT')end
        local old=UIParent:GetWidth();UIParent:SetWidth(175);W.event('DISPLAY_SIZE_CHANGED');check()
        assert(parent:GetWidth()==p.frame:GetWidth()-32)
        if preview then assert(-preview.points[3]>=-parent.points[3]+26)end
        UIParent:SetWidth(old);W.event('DISPLAY_SIZE_CHANGED')
        assert(p:Close() and not initial.active);assert(p:Open() and owner~=initial and owner.active);p:Close()
    end
end)

test('options header component','a sample stays clear of the close button and scroll area, updates with settings and reuses its parent when reopened',function()
    local a=app(basic)
    local host,owner,last,hides
    local pages={{id='options',sections={}}}
    assert(not pcall(a.Options,a,{pages=pages,header={width=0,create=function()end}}))
    local panel=a:Options({pages=pages,title='Sample settings',header={width=46,create=function(parent,app,scope)
        assert(app==a and (not host or host==parent))
        host,owner=parent,scope
        return {
            Refresh=function()last=a:Get('enabled')end,
            Layout=function(_,width)assert(width==46);return width end,
            Hide=function()hides=(hides or 0)+1 end,
        }
    end}})
    boot(a);assert(panel:Open() and last and host:GetParent()==panel.frame)
    assert(host.points[1]=='TOPRIGHT' and -host.points[2]>panel._pool.close:GetWidth())
    local function checkTitle()
        local point=panel._texts.title.anchors.TOPLEFT
        assert(point[2]==16 and point[3]==-16,'a tall preview must not move the title down')
        assert(host.points[3]<=point[3],'the preview must not start above the title')
    end
    local function aboveBody()
        assert(-host.points[3]+host:GetHeight() <= -panel.scroll.anchors.TOPLEFT[3])
    end
    checkTitle();aboveBody()
    assert(a:Set('enabled',false) and last==false)
    local originalWidth=UIParent:GetWidth()
    UIParent:SetWidth(176);W.event('DISPLAY_SIZE_CHANGED')
    assert(-host.points[3]>=16+panel._texts.title:GetStringHeight(),'narrow title and preview have separate rows')
    checkTitle();aboveBody()
    UIParent:SetWidth(originalWidth);W.event('DISPLAY_SIZE_CHANGED')
    checkTitle();aboveBody()
    local count=#W.frames
    panel:Close();assert(hides==1 and not owner.active)
    assert(a:Set('enabled',true) and last==false)
    assert(panel:Open() and last and owner.active and #W.frames==count);panel:Close()
end)

test('distinct authored form IDs','an editable slider and a separately named text field never share their edit box',function()
    local a=app(function(name)
        return {savedVariables={name..'DB'},fields={
            size={type='integer',default=12,min=1,max=64},
            note={type='string',default='memo'},other={type='string',default='other'},
        }}
    end)
    local panel=a:Options({pages={{id='text:style',sections={{controls={
        {type='slider',key='size',id='size',label='Size',editable=true},
        {type='text',key='note',id='size:value',label='Note'},
        {type='text',key='other',id='size%3Avalue',label='Other'},
    }}}},{id='text%3Astyle',sections={{controls={
        {type='text',key='other',id='size:value',label='Other page'},
    }}}},{id='tab',sections={{controls={{type='description',id='text',text='Help text'}}}}},
        {id='1',label='First'}}})
    boot(a);assert(panel:Open())
    local entries={}
    for _,widget in pairs(panel._pool) do
        if widget.kind=='EditBox' and widget:IsShown() then entries[widget:GetText()]=widget end
    end
    assert(entries['12'] and entries.memo and entries.other,'each field displays its own setting')
    local edit=entries['12']
    edit:SetFocus();edit:SetText('20');edit.scripts.OnEnterPressed(edit)
    assert(a:Get('size')==20 and a:Get('note')=='memo' and a:Get('other')=='other')
    local note=entries.memo
    note:SetText('changed');note.scripts.OnEnterPressed(note)
    assert(a:Get('size')==20 and a:Get('note')=='changed')
    assert(panel:SelectPage('text%3Astyle') and not note:IsShown())
    assert(panel:SelectPage('text:style') and note:IsShown() and note:GetText()=='changed')
    assert(panel:SelectPage('tab'))
    assert(panel._pool[':tab:1'].text:GetText()=='First' and panel._texts['tab:1:text']:GetText()=='Help text')
    panel:Close()
end)

print('PASS '..total..' focused tests')
