local _, ns = ...
local SND = ns.SomethingNeedDoing; local I, V = SND._, SND.Values
local edges = {
    default='Interface\\Tooltips\\UI-Tooltip-Border', thin='Interface\\Buttons\\WHITE8X8',
    tooltip='Interface\\Tooltips\\UI-Tooltip-Border', dialog='Interface\\DialogFrame\\UI-DialogBox-Border',
}
local roles = { dialog=true, section=true, button=true, tab=true, input=true, dropdown=true, checkbox=true, slider=true, scrollbar=true }
local controls = {dropdown=true,checkbox=true,slider=true,scrollbar=true}
local function nativeObject(value)
    return V.Readable(value) and (type(value)=='table' or type(value)=='userdata')
end
local function safeFrame(frame)
    if not nativeObject(frame) then return false end
    local ok, safe = pcall(function()
        return (not frame.IsForbidden or not frame:IsForbidden()) and (not frame.IsProtected or not frame:IsProtected())
    end)
    return ok and safe
end
I.safeFrame = safeFrame
local layoutDefaults={fieldWidth=230,minLabelWidth=174,gap=16,rowGap=8,columns=1,minColumnWidth=220,columnGap=16}
function I.formLayout(spec,base)
    I.check(spec==nil or I.plain(spec),'form layout must be a plain table')
    local result=I.copy(base or layoutDefaults)
    for key,value in pairs(spec or {})do
        I.check(layoutDefaults[key]~=nil,'unknown form layout option: '..tostring(key))
        I.check(V.Number(value) and value>=((key=='gap' or key=='rowGap' or key=='columnGap') and 0 or 1),'invalid form dimension')
        result[key]=value
    end
    I.check(result.columns==math.floor(result.columns) and result.columns<=4,'columns must be an integer from 1 to 4')
    return result
end
-- Presets are copied at declaration; consumers can extend tokens for their own renderers.
SND.Themes = {
    modern = { label='Modern', colors={surface={.035,.04,.055,.97},border={.19,.20,.23,1},accent={.86,.79,.63,1},text={.93,.94,.97,1},muted={.65,.65,.68,1}}, border='thin' },
    forever = { label='WoW Forever', colors={surface={.08,.065,.045,.97},border={.57,.44,.25,1},accent={.83,.72,.49,1},text={.94,.90,.80,1},muted={.7,.65,.55,1}}, border='dialog' },
}
local function themeDefinition(definition)
    I.check(I.plain(definition),'theme must be a plain definition')
    local result=I.copy(definition)
    I.check(type(result.label)=='string' and result.label~='' and edges[result.border], 'theme requires label and border')
    I.check(I.plain(result.colors),'theme requires colors')
    for _,key in ipairs({'surface','border','accent','text','muted'})do I.check(result.colors[key]~=nil,'missing theme color: '..key)end
    for key,color in pairs(result.colors)do
        I.check(type(key)=='string' and key~='','theme color name required')
        I.check(I.array(color,'theme color')==4,'theme colors require RGBA')
        for _,v in ipairs(color)do I.check(V.Number(v) and v>=0 and v<=1,'theme color must be in [0,1]')end
    end
    I.check(result.tokens==nil or I.plain(result.tokens),'theme tokens must be plain data')
    return result
end
SND._install[#SND._install + 1] = function(app)
    local ui, fonts, layout = {}, {}, {}; app.ui, app.fonts, app.layout = ui, fonts, layout
    local definitions={modern=themeDefinition(SND.Themes.modern),forever=themeDefinition(SND.Themes.forever)}
    local defaultTheme, configured='modern',false
    local appearance=I.store(app,{theme=I.copy(definitions.modern),themeID='modern',fontRevision=0})
    local styled=setmetatable({}, {__mode='k'})
    local colors=setmetatable({}, {__mode='k'})
    local refreshAppearance, notifyAppearance
    local fontsRequested = false
    local function resolved()
        local id=defaultTheme
        if app._ready and app._settingsFields and app._settingsFields.theme then id=app:Get('theme') end
        return definitions[id] or definitions[defaultTheme], definitions[id] and id or defaultTheme
    end
    function app:Appearance(spec)
        I.check(not configured and not self._ready and not self._disposed and I.plain(spec),'declare appearance once before readiness')
        local nextDefinitions={}
        I.check(I.plain(spec.themes),'appearance requires themes keyed by stable ID')
        for id,definition in pairs(spec.themes)do
            I.check(type(id)=='string' and id~='','theme ID required');nextDefinitions[id]=themeDefinition(definition)
        end
        I.check(type(spec.defaultTheme)=='string' and nextDefinitions[spec.defaultTheme],'unknown default theme')
        definitions,defaultTheme,configured=nextDefinitions,spec.defaultTheme,true
        refreshAppearance(false)
    end
    function app:SelectAppearance(project) return appearance:Select(project) end
    function ui:Themes()
        local entries={};for id,definition in pairs(definitions)do entries[#entries+1]={value=id,label=definition.label}end
        table.sort(entries,function(a,b)return a.label<b.label end);return entries
    end
    local function paint(frame,role)
        if not safeFrame(frame)then return end
        local theme=resolved()
        local edge=role=='dialog' and theme.border or 'thin'
        frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile=edges[edge],edgeSize=edge=='thin' and 1 or edge=='dialog' and 16 or 12,
            insets={left=3,right=3,top=3,bottom=3}})
        frame:SetBackdropColor(unpack(theme.colors.surface));frame:SetBackdropBorderColor(unpack(theme.colors[styled[frame].hover and (not frame.IsEnabled or frame:IsEnabled()) and 'accent' or 'border']))
        if controls[role] then
            local art=frame._sndControlArt
            if role=='dropdown' then
                frame.Background:Hide();frame.Arrow:Hide()
                frame.Text:SetTextColor(unpack(theme.colors.text))
            end
            for _,texture in pairs(art)do texture:SetVertexColor(unpack(theme.colors.accent))end
            frame:SetAlpha(frame:IsEnabled() and 1 or .45)
        end
    end
    local function prepareControl(frame,role)
        if not controls[role] then return end
        if frame._sndControlKind==role then return end
        -- Cache even a partially constructed set: native objects are permanent,
        -- so a failed SetThumbTexture/SetCheckedTexture must reuse its textures.
        local art=frame._sndControlArt or {};frame._sndControlArt=art
        local function texture(key)
            if not art[key] then art[key]=frame:CreateTexture(nil,'ARTWORK')end
            return art[key]
        end
        if role=='dropdown' then
            I.check(frame.Background and frame.Arrow and frame.Text and type(frame.OnButtonStateChanged)=='function','dropdown requires WowStyle1DropdownTemplate')
            for index=1,2 do
                local line=texture(index);line:SetColorTexture(1,1,1,1);line:SetSize(6,1.5)
                line:ClearAllPoints();line:SetPoint('RIGHT',frame,'RIGHT',index==1 and -13 or -9,0)
                line:SetRotation(index==1 and -math.pi/4 or math.pi/4)
            end
        elseif role=='checkbox' then
            for _,key in ipairs({'checked','disabled'})do
                local mark=texture(key);mark:SetTexture('Interface\\Buttons\\UI-CheckBox-Check');mark:SetAllPoints(frame)
            end
            frame:SetCheckedTexture(art.checked);frame:SetDisabledCheckedTexture(art.disabled)
        else
            local thumb=texture('thumb');thumb:SetColorTexture(1,1,1,1)
            thumb:SetSize(role=='slider' and 10 or 8,role=='slider' and 18 or 32)
            frame:SetThumbTexture(thumb)
        end
        frame._sndControlKind=role
    end
    function ui:Border(frame,kind)
        I.check(not app._disposed,'appearance service is disposed')
        if not safeFrame(frame) or type(frame.SetBackdrop)~='function' or type(frame.SetBackdropColor)~='function' or type(frame.SetBackdropBorderColor)~='function' then return false,I.error('unavailable') end
        if kind~='none' and not edges[kind] then return false,I.error('invalid') end
        local ok,err=pcall(function()
            local spec=I.copy(frame.GetBackdrop and frame:GetBackdrop() or {})
            spec.edgeFile=edges[kind];spec.edgeSize=kind=='thin' and 1 or kind=='dialog' and 16 or 12
            local bg=frame.GetBackdropColor and {frame:GetBackdropColor()}
            frame:SetBackdrop(spec);if bg and bg[1] then frame:SetBackdropColor(unpack(bg))end
            frame:SetBackdropBorderColor(unpack(resolved().colors.border))
        end)
        if not ok then return false,I.error('unavailable',err)end
        return true
    end
    function ui:Style(frame,role)
        I.check(not app._disposed,'appearance service is disposed')
        if not roles[role] then return false,I.error('invalid')end
        if not safeFrame(frame) or type(frame.SetBackdrop)~='function' or type(frame.SetBackdropColor)~='function' or type(frame.SetBackdropBorderColor)~='function' then return false,I.error('unavailable')end
        local record=styled[frame]
        if record and record.role~=role then
            if record.owner then record.owner:Cancel()end
            styled[frame]=nil;record=nil
        end
        local fresh=not record
        if not record then
            local disable=false
            if role=='button' or role=='tab' or controls[role] then
                local ok,result=pcall(function()return frame.HasScript and frame:HasScript('OnDisable') or not frame.HasScript and frame.IsEnabled~=nil end)
                if not ok then return false,I.error('unavailable',result)end
                disable=result
            end
            record={role=role};styled[frame]=record
            if role=='button' or role=='tab' or controls[role] then
                local owner=app:Scope();record.owner=owner
                local events={'OnEnter','OnLeave','OnHide'}
                if disable then events[#events+1]='OnDisable';events[#events+1]='OnEnable'end
                for _,event in ipairs(events)do
                    local entering=event=='OnEnter'
                    local ok,err=owner:HookScript(frame,event,function(self)record.hover=entering and (not self.IsEnabled or self:IsEnabled());paint(self,record.role)end)
                    if not ok then owner:Cancel();styled[frame]=nil;return false,err end
                end
                if role=='dropdown' then
                    local ok,err=owner:PostHook(frame,'OnButtonStateChanged',function()paint(frame,record.role)end)
                    if not ok then owner:Cancel();styled[frame]=nil;return false,err end
                end
            end
        end
        record.role=role
        local ok,err=pcall(function()prepareControl(frame,role);paint(frame,role)end)
        if not ok then
            if fresh then if record.owner then record.owner:Cancel()end;styled[frame]=nil end
            return false,I.error('unavailable',err)
        end
        return true
    end
    function ui:Color(object,role)
        I.check(not app._disposed,'appearance service is disposed')
        for _,definition in pairs(definitions)do if not definition.colors[role] then return false,I.error('invalid','Color role must exist in every theme')end end
        if not safeFrame(object) or (type(object.SetTextColor)~='function' and type(object.SetVertexColor)~='function') then return false,I.error('unavailable')end
        local ok,err=pcall(object.SetTextColor or object.SetVertexColor,object,unpack(resolved().colors[role]))
        if not ok then return false,I.error('unavailable',err)end
        colors[object]=role;return true
    end
    local applications = setmetatable({}, {__mode='k'})
    local sizes = {heading=16,body=14,muted=14,control=13,menu=13,emphasis=14}
    local media, refreshing, startFonts, refreshFonts
    local downgrade, generation = {}, 0
    local rejectedBold, nativeFallback = {}, {}
    local measurements = setmetatable({}, {__mode='k'})
    local function nativeFont()
        if GameFontNormal and GameFontNormal.GetFont then return GameFontNormal:GetFont() end
        return 'Fonts\\FRIZQT__.TTF', 13, ''
    end
    local function preference()
        if app._ready and app._settingsFields and app._settingsFields.font then return app:Get('font') end
        return 'Game tooltip'
    end
    local function getMedia()
        if LibStub then local ok, result = pcall(function() return LibStub('LibSharedMedia-3.0', true) end); if ok then return result end end
    end
    function fonts:Entries()
        startFonts()
        media = getMedia()
        local names, out = { ['Game tooltip']=true, ['Arial']=true, ['Friz Quadrata']=true }, {}
        if media and media.List then for _, name in ipairs(media:List('font') or {}) do names[name] = true end end
        names[preference()] = true
        for name in pairs(names) do out[#out+1]={label=name,value=name} end
        table.sort(out,function(a,b) return a.label < b.label end); return out
    end
    local function apply(object, entry)
        local role,options=entry.role,entry.options
        local fallback, nativeSize, flags = nativeFont()
        local path = fallback
        local selected = preference(); media = media or getMedia()
        if selected == 'Arial' then path='Fonts\\ARIALN.TTF'
        elseif selected == 'Friz Quadrata' then path='Fonts\\FRIZQT__.TTF'
        elseif selected == 'Game tooltip' then
            local tooltip=GameTooltipTextLeft2 or GameTooltipText
            if tooltip and tooltip.GetFont then path=tooltip:GetFont()end
        elseif media and media.Fetch then path = media:Fetch('font', selected, true) or fallback end
        local request = selected .. ':' .. tostring(path)
        path = downgrade[request] or path
        local size = sizes[role]
        if (role == 'body' or role == 'muted') and app._ready and app._settingsFields and app._settingsFields.fontSize then size = app:Get('fontSize') end
        size=options.size or size;flags=options.flags or ''

        local function try(candidate)
            local actual,height,actualFlags=object:GetFont()
            if not entry.native and entry.path==candidate and entry.size==size and entry.flags==flags and actual==entry.actual and height==entry.height and actualFlags==entry.actualFlags then return true end
            local ok, result = pcall(object.SetFont,object,candidate,size,flags or '')
            if not ok or result == false then return false end
            local read, actual, height = pcall(object.GetFont,object)
            local valid=read and type(actual)=='string' and actual:gsub('/','\\'):lower()==candidate:gsub('/','\\'):lower() and V.Number(height) and height>0
            if valid then entry.native=nil;entry.path,entry.size,entry.flags=candidate,size,flags;entry.actual,entry.height,entry.actualFlags=object:GetFont()end
            return valid
        end
        if nativeFallback[request] then
            local native=nativeFallback[request]
            local actual,height,flags=object:GetFont()
            if entry.native~=native or actual~=entry.actual or height~=entry.height or flags~=entry.actualFlags then object:SetFontObject(native)end
            entry.native=native;entry.actual,entry.height,entry.actualFlags=object:GetFont();return true
        end
        if role=='emphasis' then
            local bold=media and media.Fetch and media:Fetch('font',selected..' Bold',true)
            local key=request..':'..tostring(bold)
            if type(bold)=='string' and bold~='' and not rejectedBold[key] then
                if try(bold)then return true end
                rejectedBold[key]=true;generation=generation+1
            end
            flags='OUTLINE'
        end
        if not try(path) then
            if path~=fallback and downgrade[request]~=fallback then downgrade[request]=fallback;generation=generation+1 end
            if not try(fallback) then
                if not object.SetFontObject or not GameFontNormal then return false,I.error('unavailable') end
                nativeFallback[request]=GameFontNormal;generation=generation+1
                object:SetFontObject(GameFontNormal);entry.native=GameFontNormal;entry.actual,entry.height,entry.actualFlags=object:GetFont()
            end
        end
        return true
    end
    function fonts:Apply(object, role, options)
        if not sizes[role] or not nativeObject(object) or type(object.SetFont)~='function' or type(object.GetFont)~='function' then return false, I.error('invalid') end
        if options==nil then options={}end
        I.check(I.plain(options) and (options.size==nil or (V.Number(options.size) and options.size>0)) and (options.flags==nil or type(options.flags)=='string'),'invalid font options')
        startFonts()
        local entry=applications[object] or {};applications[object]=entry
        entry.role,entry.options=role,I.copy(options)
        local before=generation
        local ran,ok,err=pcall(apply,object,entry)
        if not ran then ok,err=false,I.error('unavailable',ok)end
        if not ok then applications[object]=nil end
        if generation~=before and not refreshing then refreshFonts(false) end
        return ok,err
    end
    function fonts:Measure(text)
        I.check(nativeObject(text) and type(text.GetStringWidth)=='function' and type(text.GetStringHeight)=='function' and type(text.GetFont)=='function', 'FontString required')
        local path,size,flags=text:GetFont();local scale=text:GetEffectiveScale()
        local key=tostring(path)..':'..tostring(size)..':'..tostring(flags)..':'..tostring(scale)..':'..tostring(text:GetWidth())..':'..(text:GetText()or'')
        local cached=measurements[text]
        if not cached or cached.key~=key then
            cached={key=key,width=math.ceil(text:GetStringWidth()*scale)/scale,height=math.ceil(text:GetStringHeight()*scale)/scale};measurements[text]=cached
        end
        return cached.width,cached.height
    end
    refreshFonts=function(retry)
        if refreshing then return end
        refreshing=true
        startFonts()
        if retry then downgrade={};rejectedBold={};nativeFallback={}end
        media=getMedia()
        for _=1,3 do
            local before=generation
            for object,role in pairs(applications)do local ok,applied,err=pcall(apply,object,role);if not ok then applications[object]=nil;I.report(app,applied)elseif not applied then applications[object]=nil;I.report(app,err)end end
            if before==generation then break end
        end
        refreshing = nil
        notifyAppearance(true)
    end
    function fonts:Refresh()return refreshFonts(true)end
    local notifying=false
    notifyAppearance=function(fontChanged)
        if notifying then return end
        for pass=1,3 do
            local before=generation
            local theme,id=resolved()
            local value={theme=I.copy(theme),themeID=id,fontRevision=appearance._values.fontRevision+(fontChanged and 1 or 0)}
            if I.equal(value,appearance._values) then return end
            appearance._values=value;appearance._revision=appearance._revision+1
            notifying=true
            I.lock(app,function()appearance:_notify()end)
            notifying=false
            -- A later observer can create text that rejects the resolved family.
            -- Earlier observers must remeasure that fallback, without looping on Refresh alone.
            if generation==before then return end
            fontChanged=true
        end
        I.report(app,'Appearance did not settle after three passes')
    end
    refreshAppearance=function(fontChanged)
        for frame,record in pairs(styled)do I.call(app,paint,frame,record.role)end
        for object,role in pairs(colors)do if safeFrame(object)then I.call(app,object.SetTextColor or object.SetVertexColor,object,unpack(resolved().colors[role]))end end
        if fontChanged and fontsRequested then fonts:Refresh() else notifyAppearance(fontChanged)end
    end
    app:OnReady(function()
        refreshAppearance(false)
        app:OnSettingsChanged(function(_,change)
            if change:Touches('theme','font','fontSize') then refreshAppearance(change:Touches('font','fontSize'))end
        end)
    end)
    startFonts = function()
        I.check(not app._disposed, 'font service is disposed')
        if fontsRequested then return end
        fontsRequested = true
        local function activate()
            local connected, mediaOwner
            local function connect()
                local lib=getMedia()
                if lib and lib~=connected and lib.RegisterCallback then
                    local owner=app:Scope()
                    local receiver={}
                    receiver.Changed = owner:Guard(function(_,_,kind)
                        if kind=='font' then downgrade={};rejectedBold={};nativeFallback={};fonts:Refresh();if app._panel then app._panel:Refresh()end end
                    end)
                    I.handle(owner,function()if lib.UnregisterAllCallbacks then lib.UnregisterAllCallbacks(receiver)end end)
                    local ok, err = pcall(function()
                        lib.RegisterCallback(receiver,'LibSharedMedia_Registered','Changed')
                        lib.RegisterCallback(receiver,'LibSharedMedia_SetGlobal','Changed')
                    end)
                    if not ok then owner:Cancel();I.report(app,err);return end
                    if mediaOwner then mediaOwner:Cancel() end
                    connected=lib;media=lib;mediaOwner=owner
                    downgrade={};rejectedBold={};nativeFallback={};fonts:Refresh()
                end
            end
            connect();app._system:Event('ADDON_LOADED',connect)
            fonts:Refresh()
        end
        if app:IsReady() then activate() else app:OnReady(activate) end
    end
    -- One constructor contract for generated options and consumer-owned views.
    -- Cache before decoration so a failed native attachment can reuse its frame.
    local controlPool=setmetatable({}, {__mode='k'})
    local controlTypes={button={'Button','BackdropTemplate','button'},checkbox={'CheckButton','BackdropTemplate','checkbox'},
        input={'EditBox','InputBoxScriptTemplate,BackdropTemplate','input'},
        dropdown={'DropdownButton','WowStyle1DropdownTemplate,BackdropTemplate','dropdown'},slider={'Slider','BackdropTemplate','slider'}}
    function ui:Control(parent,id,kind)
        I.check(type(id)=='string' and id~='' and controlTypes[kind], 'control requires a stable id and supported kind')
        if app._disposed or not safeFrame(parent) then return false,I.error('unavailable')end
        local pool=controlPool[parent];if not pool then pool={};controlPool[parent]=pool end
        local entry=pool[id];I.check(not entry or entry.kind==kind,'control id cannot change kind')
        local ok,result=pcall(function()
            if not entry then
                local definition=controlTypes[kind]
                entry={kind=kind,frame=CreateFrame(definition[1],nil,parent,definition[2])};pool[id]=entry
            end
            local f=entry.frame
            f:EnableMouse(true)
            if kind=='button' or kind=='checkbox' then f:RegisterForClicks('LeftButtonUp')end
            if kind=='input' then
                f:SetAutoFocus(false);f:SetTextInsets(8,8,0,0)
            end
            if not entry.behavior then
                local owner=app:Scope()
                local attached,err=owner:PostHook(f,'SetEnabled',function(self)self:SetAlpha(self:IsEnabled() and 1 or .45)end)
                if attached and kind=='input' then attached,err=owner:HookScript(f,'OnHide',function(self)self:ClearFocus()end)end
                if not attached then owner:Cancel();error(err,0)end
                entry.behavior=owner
            end
            f:SetAlpha(f:IsEnabled() and 1 or .45)
            local styled,err=ui:Style(f,controlTypes[kind][3])
            if not styled then entry.behavior:Cancel();entry.behavior=nil;error(err,0)end
            return f
        end)
        if not ok then return false,I.error('unavailable',result)end
        return true,result
    end
    -- Stateless geometry: no subscriptions, frame allocation or settings binding.
    function layout:Columns(width,spec)
        I.check(V.Number(width) and width>0,'positive content width required')
        local s=I.formLayout(spec)
        local count=math.max(1,math.min(s.columns,math.floor((width+s.columnGap)/(s.minColumnWidth+s.columnGap))))
        return count,(width-(count-1)*s.columnGap)/count
    end
    function layout:Row(parent,spec)
        I.check(I.plain(spec) and V.Number(spec.width) and spec.width>0,'row requires a positive width')
        local s=I.formLayout(spec.layout)
        local kind=spec.kind or 'field'
        I.check(kind=='field' or kind=='check' or kind=='action' or kind=='text','invalid row kind')
        local x,y=spec.x or 0,spec.y or 0
        I.check(V.Number(x) and V.Number(y),'row offsets must be finite')
        I.check(spec.controlWidth==nil or (V.Number(spec.controlWidth) and spec.controlWidth>0),'positive control width required')
        I.check(spec.align==nil or spec.align=='start' or spec.align=='field' or spec.align=='stretch','invalid action alignment')
        local label,control,hint=spec.label,spec.control,spec.hint
        if app._disposed or not safeFrame(parent) then return false,I.error('unavailable')end
        for _,object in pairs({label=label,control=control,hint=hint})do
            if not safeFrame(object) then return false,I.error('unavailable')end
        end
        I.check((kind=='text' and label) or (kind~='text' and control),'row content required')
        I.check(kind~='field' or label,'field requires a label')
        I.check(not control or control:GetParent()==parent,'row control must belong to its parent')
        I.check(not label or label:GetParent()==(kind=='action' and control or parent),'row label has the wrong parent')
        I.check(not hint or hint:GetParent()==parent,'row hint must belong to its parent')
        local ok,height=pcall(function()
            local width=spec.width
            local fieldWidth=math.min(s.fieldWidth,width)
            local inline=width>=s.fieldWidth+s.gap+s.minLabelWidth
            local function measure(text,w)
                text:SetScale(1);text:SetWidth(math.max(1,w));text:SetHeight(0);text:SetWordWrap(true)
                return text:GetStringHeight()
            end
            local function place(object,px,py)
                object:ClearAllPoints();object:SetPoint('TOPLEFT',px,-py)
            end
            local h=0
            if kind=='field' then
                local lh=measure(label,inline and width-fieldWidth-s.gap or width)
                control:SetWidth(math.min(spec.controlWidth or fieldWidth,fieldWidth))
                local ch=control:GetHeight()
                place(label,x,y+(inline and math.max(0,(ch-lh)/2) or 0))
                place(control,x+(inline and width-fieldWidth or 0),y+(inline and 0 or lh+6))
                h=inline and math.max(lh,ch) or lh+6+ch
            elseif kind=='check' then
                local ch=control:GetHeight();local cw=control:GetWidth()
                local lh=label and measure(label,width-cw-8) or 0
                h=math.max(ch,lh);place(control,x,y)
                if label then place(label,x+cw+8,y+math.max(0,(ch-lh)/2))end
                control:SetHitRectInsets(0,-math.max(0,width-cw),0,-math.max(0,h-ch))
            elseif kind=='action' then
                local available=spec.align=='field' and inline and fieldWidth or width
                local cw=spec.align=='stretch' and width or math.min(spec.controlWidth or s.fieldWidth,available)
                control:SetWidth(cw)
                h=math.max(26,(label and measure(label,cw-16) or 0)+10);control:SetHeight(h)
                place(control,x+(spec.align=='field' and inline and width-fieldWidth or 0),y)
                if label then
                    label:ClearAllPoints();label:SetPoint('CENTER',control,'CENTER');label:SetHeight(h-10)
                    label:SetJustifyH('CENTER');label:SetJustifyV('MIDDLE')
                end
            else h=measure(label,width);place(label,x,y)end
            if hint then local hh=measure(hint,width);place(hint,x,y+h+6);h=h+6+hh end
            return h+s.rowGap
        end)
        if not ok then return false,I.error('unavailable',height)end
        return true,height
    end
    local function geometry(frame)
        if not safeFrame(frame) or not frame.GetLeft then return end
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local left, bottom, width, height = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
        if not V.Number(left) or not V.Number(bottom) or not V.Number(ratio) or ratio<=0 then return end
        return left*ratio, bottom*ratio, width*ratio, height*ratio, ratio
    end
    local function track(frame, anchor, spec)
        I.check(spec==nil or I.plain(spec), 'layout spec must be a plain table')
        spec = I.copy(spec or {})
        I.check((spec.preferredSide==nil or spec.preferredSide=='left' or spec.preferredSide=='right') and (spec.fallbackSide==nil or spec.fallbackSide=='left' or spec.fallbackSide=='right'), 'popup sides must be left or right')
        if not safeFrame(frame) or type(frame.GetLeft)~='function' or type(frame.SetPoint)~='function' or (anchor and (not safeFrame(anchor) or type(anchor.GetLeft)~='function')) then return false, I.error('unavailable') end
        local margin = spec.margin; if margin == nil then margin = 0 end
        if not V.Number(margin) or margin<0 then return false, I.error('invalid') end
        local h, dragging = nil, false
        local owner = app:Scope()
        h = I.handle(app, function() owner:Cancel() end)
        function h:Refresh()
            if not self.active or dragging or (frame.IsShown and not frame:IsShown()) then return true end
            if not safeFrame(frame) then return false, I.error('unavailable') end
            local x,y,w,height,ratio = geometry(frame); if not x then return false,I.error('unavailable') end
            local maxX,maxY = UIParent:GetWidth()-w-margin,UIParent:GetHeight()-height-margin
            if anchor then
                local ax,ay,aw,ah = geometry(anchor); if not ax then return false,I.error('unavailable') end
                local function place(side) return side=='left' and ax-w-margin or ax+aw+margin end
                x,y=place(spec.preferredSide or 'right'),ay+ah-height
                if x<margin or x>maxX then x=place(spec.fallbackSide or 'left') end
            end
            local nx,ny=math.max(margin,math.min(maxX,x)),math.max(margin,math.min(maxY,y))
            if anchor or nx~=x or ny~=y then
                frame:ClearAllPoints();frame:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',nx/ratio,ny/ratio)
            end
            return true
        end
        local function attach(ok, err)
            if not ok then h:Cancel();return false,err end
            return true
        end
        for _,event in ipairs({'UI_SCALE_CHANGED','DISPLAY_SIZE_CHANGED'}) do
            local ok,err=attach(owner:Event(event,function() h:Refresh() end))
            if not ok then return false,err end
        end
        local hooks={{frame,'OnShow',function() h:Refresh() end},
            {frame,'OnSizeChanged',function() h:Refresh() end},
            {frame,'OnDragStart',function() dragging=true end},
            {frame,'OnDragStop',function() dragging=false;h:Refresh() end}}
        if anchor then hooks[#hooks+1]={anchor,'OnSizeChanged',function() h:Refresh() end} end
        for _,hook in ipairs(hooks) do
            local ok,err=attach(owner:HookScript(unpack(hook)))
            if not ok then return false,err end
        end
        h:Refresh(); return true, h
    end
    function layout:KeepOnScreen(frame,spec) return track(frame,nil,spec) end
    function layout:PlacePopup(frame,anchor,spec) return track(frame,anchor,spec) end
end
