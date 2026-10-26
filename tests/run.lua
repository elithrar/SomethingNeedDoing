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
    local b=app(basic);_G[b.name..'DB']={version=1,values={scale=1.5,font='Game tooltip',color={1,1,1},enabled=true}}
    boot(b);assert(b:Get('scale')==1.5)
    local seen=0;b:Scope():Watch(b:SelectSettings(function(values)return values.scale end),function(value)assert(value==_G[b.name..'DB'].values.scale);seen=seen+1 end)
    assert(b:Set('scale',1.6));assert(seen==2);assert(not b:Set('scale',4));assert(b:Get('scale')==1.6)
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

test('options construction and menu lifetime','failed builds are retryable and settings refresh never rebuilds an open menu',function()
    local a=app(basic);local panel=a:Options({pages={{id='appearance',sections={{title='Font',controls={{type='font',key='font',label='Font'},{type='checkbox',key='enabled',label='Enabled'},{type='slider',key='scale',label='Scale',step=.1}}}}}}})
    boot(a);W.failTemplate='UIPanelScrollBarTemplate';assert(not panel:Open());assert(panel:Open())
    local d=panel._menus['appearance:1:1'];d:OpenMenu();assert(a:Set('font','Missing font'));assert(panel._refreshPending)
    d:CloseMenu();W.tick(.01);assert(not panel._refreshPending)
    local check=panel._pool['appearance:1:2'];check:SetChecked(false);check.scripts.OnClick(check);assert(a:Get('enabled')==false)
    panel._pool['appearance:1:3']:SetValue(1.4);assert(a:Get('scale')==1.4)
    local count=#W.frames;panel:Close();assert(panel:Open());assert(#W.frames==count)
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

print('PASS '..total..' focused tests')
