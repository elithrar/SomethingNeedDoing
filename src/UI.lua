local _, ns = ...
local SND = ns.SomethingNeedDoing; local I, V = SND._, SND.Values
local edges = {
    default='Interface\\Tooltips\\UI-Tooltip-Border', thin='Interface\\Buttons\\WHITE8X8',
    tooltip='Interface\\Tooltips\\UI-Tooltip-Border', dialog='Interface\\DialogFrame\\UI-DialogBox-Border',
}
local roles = { dialog=true, section=true, button=true, tab=true, input=true }
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
        local fresh=not record
        if not record then
            local disable=false
            if role=='button' or role=='tab' then
                local ok,result=pcall(function()return frame.HasScript and frame:HasScript('OnDisable') or not frame.HasScript and frame.IsEnabled~=nil end)
                if not ok then return false,I.error('unavailable',result)end
                disable=result
            end
            record={role=role};styled[frame]=record
            if role=='button' or role=='tab' then
                local owner=app:Scope();record.owner=owner
                local events={'OnEnter','OnLeave','OnHide'}
                if disable then events[#events+1]='OnDisable'end
                for _,event in ipairs(events)do
                    local entering=event=='OnEnter'
                    local ok,err=owner:HookScript(frame,event,function(self)record.hover=entering and (not self.IsEnabled or self:IsEnabled());paint(self,record.role)end)
                    if not ok then owner:Cancel();styled[frame]=nil;return false,err end
                end
            end
        end
        record.role=role
        local ok,err=pcall(paint,frame,role)
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
