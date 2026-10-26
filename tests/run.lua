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
    -- A native caption failure must release its recursion guard so pooled text
    -- can recover on the next refresh instead of silently freezing forever.
    local setWidth=d.Text.SetWidth
    d.Text.SetWidth=function()error('caption allocation failed')end
    assert(not panel:Refresh());assert(d._captioning==nil)
    d.Text.SetWidth=setWidth;assert(panel:Open());assert(d._fullCaption=='Missing font' and not d._captioning)
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


test('default profiles and atomic patches','new addons need safe storage without adapters; related settings must publish once and future saves must survive',function()
    local function fields(name)return {savedVariables={name..'DB'},fields={font={type='font',default='Arial'},fontSize={type='integer',default=13,min=9,max=20},theme={type='enum',default='modern',values={'modern','forever'}},['window.x']={type='number',default=0},['window.y']={type='number',default=0}}}end
    local a=app(fields);local observed={};local scope=a:Scope()
    scope:Watch(a:SelectSettings(function(v)return v.window end),function(v)observed[#observed+1]=v end)
    boot(a);assert(a:IsReady() and a.profiles:Active()=='Default' and #observed==1)
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
    panel._pool['profile-copy-button'].scripts.OnClick();assert(not panel._confirm and panel._texts['profile-status']:GetText()=='Choose a profile.')
    assert(not pcall(function()a.profiles:Duplicate('')end));assert(not pcall(function()a.profiles:CopyFrom(nil)end))
    panel._pool['profile-name']:SetText('Other');panel._pool['profile-add'].scripts.OnClick();assert(a.profiles:Active()=='Other' and not panel._profileError)
    -- Full captions fit fixed geometry after native font metrics change. This
    -- includes shell tabs/close and paired confirmation buttons, not just rows.
    panel._pool['profile-reset'].scripts.OnClick()
    local confirm=panel._pool['profile-confirm'];local count=#W.frames
    for _,button in pairs(panel._buttons)do
        button.text.GetUnboundedStringWidth=function(self)return #self:GetText()*15 end
    end
    assert(a:Set('theme','modern'))
    panel._pool['profile-reset'].scripts.OnClick()
    for _,button in pairs(panel._buttons)do
        local label=button.text;assert(label.scale>0 and label.scale<=1)
        assert(label:GetUnboundedStringWidth()*label.scale<=button:GetWidth()-12+.001)
        assert(label:GetWidth()*label.scale<=button:GetWidth()-12+.001)
        assert(label:GetHeight()*label.scale<=button:GetHeight()-6+.001)
    end
    assert(confirm.text:GetText()=='Confirm replacement' and #W.frames==count)
    local click=confirm.scripts.OnClick;panel:Close();click();assert(a.profiles:Active()=='Other')
    assert(panel:Open('profiles'))
    local frameName=a.name..'_SND_Options';local found=false
    for _,name in ipairs(UISpecialFrames)do if name==frameName then found=true end end;assert(found and _G[frameName]==panel.frame)
    panel._confirm={kind='reset'};_G[frameName]:Hide();assert(not panel:IsShown() and panel._confirm==nil and panel._view==nil)
    assert(panel:Open());W.event('PLAYER_LOGOUT')
    for _,name in ipairs(UISpecialFrames)do assert(name~=frameName)end
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

print('PASS '..total..' focused tests')
