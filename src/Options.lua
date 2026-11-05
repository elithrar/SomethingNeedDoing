local _, ns = ...
local SND = ns.SomethingNeedDoing; local I = SND._
function SND.Pages.Profiles() return { id='profiles', label='Profiles', _profiles=true } end
SND._install[#SND._install + 1] = function(app)
    function app:Options(spec)
        if spec==nil then spec={}end
        I.check(not self._panel and not self._disposed and I.plain(spec), 'Options requires a plain declaration on a live app')
        spec=I.definition(spec)
        if spec.pages==nil then
            local controls,paths={},{}
            for path in pairs(app._settingsFields or {})do paths[#paths+1]=path end;table.sort(paths)
            for _,path in ipairs(paths)do
                local field=app._settingsFields[path]
                local c={key=path,label=field.label or path,type=({boolean='checkbox',integer='number',number='number',string='text',enum='select',font='font',color='color'})[field.type]}
                if field.type=='enum' then c.choices={};for _,value in ipairs(field.values)do c.choices[#c.choices+1]={value=value,label=tostring(value)}end end
                controls[#controls+1]=c
            end
            spec.pages={{id='settings',label='Settings',sections={{title='Settings',controls=controls}}},SND.Pages.Profiles()}
        end
        I.array(spec.pages, 'pages', true)
        I.check((spec.width==nil or (SND.Values.Number(spec.width) and spec.width>=160)) and (spec.height==nil or (SND.Values.Number(spec.height) and spec.height>=140)), 'invalid panel dimensions')
        local pageIDs={}
        local function choices(entries)
            I.array(entries,'choices')
            for _,entry in ipairs(entries)do I.check(I.plain(entry) and type(entry.label)=='string' and entry.value~=nil,'choice requires a label and non-nil value')end
        end
        for _,page in ipairs(spec.pages)do
            I.check(I.plain(page) and type(page.id)=='string' and page.id~='' and not pageIDs[page.id], 'invalid or duplicate page id')
            pageIDs[page.id]=true
            I.array(page.sections==nil and {} or page.sections, 'sections')
            for _,section in ipairs(page.sections or {})do
                I.check(I.plain(section),'section must be a plain table')
                I.array(section.controls==nil and {} or section.controls,'controls')
                local controlIDs={}
                for index,c in ipairs(section.controls or {})do
                    I.check(I.plain(c) and ({checkbox=true,slider=true,number=true,text=true,select=true,font=true,color=true,button=true,description=true,custom=true})[c.type], 'invalid control type')
                    I.check(c.id==nil or (type(c.id)=='string' and c.id~=''), 'control id must be a nonempty string')
                    local id=c.id or tostring(index);I.check(not controlIDs[id],'duplicate control id');controlIDs[id]=true
                    for _,key in ipairs({'enabled','visible','preview','action','create'})do I.check(c[key]==nil or type(c[key])=='function', key..' must be a function')end
                    if c.type=='custom' then I.check(type(c.create)=='function','custom requires create')
                    elseif c.type=='button' then I.check(type(c.action)=='function','button requires action')
                    elseif c.type~='description' then
                        I.check(type(c.key)=='string' and c.key~='', 'bound control requires key')
                        local field=app._settingsFields and app._settingsFields[c.key]
                        I.check(field~=nil, 'declare bound settings before Options')
                        local expected=({checkbox='boolean',text='string',font='font',color='color',select='enum'})[c.type]
                        I.check(expected and field.type==expected or (not expected and (field.type=='number' or field.type=='integer')), 'control type does not match field')
                        if c.type=='slider' then I.check(field.min~=nil and field.max~=nil, 'slider requires bounds')end
                    end
                    I.check(c.step==nil or (SND.Values.Number(c.step) and c.step>0), 'control step must be positive')
                    I.check(c.format==nil or c.format=='percent' or type(c.format)=='function', 'invalid control formatter')
                    if c.choices~=nil and type(c.choices)~='function' then choices(c.choices)end
                end
            end
        end
        local panel = { _pages={}, _pool={}, _texts={}, _menus={}, _components={}, _offsets={}, _buttons={} }; self._panel=panel
        local ids={}
        for _, page in ipairs(spec.pages) do I.check(type(page.id)=='string' and not ids[page.id],'duplicate or missing page id');ids[page.id]=true;panel._pages[#panel._pages+1]=page end
        panel._page=spec.pages[1].id
        local function frame(id,kind,parent,template)
            if panel._used then panel._used[id]=true end
            if not panel._pool[id] then panel._pool[id]=CreateFrame(kind,nil,parent,template) end
            return panel._pool[id]
        end
        local function requireResource(ok,err)I.check(ok,err and err.message or 'UI resource unavailable')end
        local function text(id,parent,value,role)
            if panel._usedText then panel._usedText[id]=true end
            local label=panel._texts[id]
            if not label then label=parent:CreateFontString(nil,'OVERLAY','GameTooltipText');panel._texts[id]=label end
            requireResource(app.fonts:Apply(label,role or 'control'));requireResource(app.ui:Color(label,role=='heading' and 'accent' or role=='muted' and 'muted' or 'text'));label:SetText(value or '');label:SetJustifyH('LEFT');label:Show();return label
        end
        local function fitButton(button)
            local label=button.text
            requireResource(app.fonts:Apply(label,'control'));requireResource(app.ui:Color(label,'text'))
            -- Keep the full caption inside its allocation, including narrow tabs
            -- and close buttons. Reset scale before measuring a changed font.
            label:SetScale(1);label:SetWordWrap(false);label:SetWidth(0);label:SetHeight(0)
            local width=label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
            label:SetWidth(math.max(1,width))
            local height=label:GetStringHeight();local effective=label:GetEffectiveScale()
            width=(math.ceil(width*effective)+2)/effective;height=(math.ceil(height*effective)+2)/effective
            local availableWidth,availableHeight=math.max(1,button:GetWidth()-12),math.max(1,button:GetHeight()-6)
            local scale=math.min(1,availableWidth/math.max(1,width),availableHeight/math.max(1,height))
            label:SetScale(scale);label:SetSize(availableWidth/scale,availableHeight/scale)
            label:ClearAllPoints();label:SetPoint('CENTER');label:SetJustifyH('CENTER');label:SetJustifyV('MIDDLE')
        end
        local function button(id,parent,label,action)
            local b=frame(id,'Button',parent,'BackdropTemplate');b:SetSize(math.min(230,math.max(1,parent:GetWidth())),26);requireResource(app.ui:Style(b,'button'))
            b:EnableMouse(true);b:RegisterForClicks('LeftButtonUp')
            b.text=text(id..':text',b,label);panel._buttons[id]=b;b:SetScript('OnClick',action);return b
        end
        local function input(id,parent,width)
            local edit=frame(id,'EditBox',parent,'InputBoxScriptTemplate,BackdropTemplate')
            edit:EnableMouse(true);edit:SetSize(width,26);edit:SetAutoFocus(false);edit:SetTextInsets(8,8,0,0)
            requireResource(app.ui:Style(edit,'input'));requireResource(app.fonts:Apply(edit,'control'));requireResource(app.ui:Color(edit,'text'))
            return edit
        end
        local function report(ok,err) if not ok then app.log:Warn('Options action failed',{code=err and err.code or 'unknown'}) end end
        function panel:_cancelEditors(keepMenus)
            local edit=self._edit;self._edit=nil
            if edit then
                if edit.preview then I.call(app,edit.preview,I.copy(edit.original)) end
                if ColorPickerFrame and ColorPickerFrame.GetExtraInfo and ColorPickerFrame:GetExtraInfo()==edit then ColorPickerFrame:Hide() end
            end
            if not keepMenus then for _, menu in pairs(self._menus) do if menu.CloseMenu then menu:CloseMenu() end end end
            for _, control in pairs(self._pool) do if control.ClearFocus then control:ClearFocus() end end
            if self.frame then self.frame:StopMovingOrSizing() end
        end
        function panel:_deactivate()
            self._confirm=nil;self._profileError=nil
            self:_cancelEditors()
            if self._view then self._view:Cancel();self._view=nil end
            for _, component in pairs(self._components) do I.call(app,component.Hide,component) end
            self._components={}
        end
        local function color(control)
            local picker=ColorPickerFrame
            if not picker or not picker.SetupColorPickerAndShow then return report(false,I.error('unavailable')) end
            panel:_cancelEditors()
            local _,revision=app._settingsStore:Read()
            local edit={original=app:Get(control.key),revision=revision,preview=control.preview,opening=true};panel._edit=edit
            local function owns() return panel._edit==edit and picker:GetExtraInfo()==edit end
            local function cancel()
                if not owns() then return end
                panel._edit=nil;if edit.preview then I.call(app,edit.preview,I.copy(edit.original)) end
            end
            if not panel._pickerHook then
                local hooked, hook=app._system:HookScript(picker,'OnHide',function()
                    local hidden=panel._edit
                    app._system:After(0,'picker-hidden',function()
                        if panel._edit==hidden and hidden and not picker:IsShown() then panel:_cancelEditors(true) end
                    end)
                end)
                if not hooked then panel._edit=nil;return report(false,hook)end
                panel._pickerHook=hook
            end
            picker:SetupColorPickerAndShow({r=edit.original[1],g=edit.original[2],b=edit.original[3],hasOpacity=false,extraInfo=edit,
                swatchFunc=function()
                    if not owns() then return end
                    local value={picker:GetColorRGB()}
                    if not edit.opening and not picker:IsShown() then
                        panel._edit=nil
                        local ok,err=app:Set(control.key,value,edit.revision)
                        if not ok and edit.preview then I.call(app,edit.preview,I.copy(edit.original)) end
                        report(ok,err)
                    elseif edit.preview then I.call(app,edit.preview,value) end
                end,cancelFunc=cancel})
            edit.opening=false
        end
        function panel:_menuOpen()
            for _, menu in pairs(self._menus) do if menu.IsMenuOpen and menu:IsMenuOpen() then return true end end
            return false
        end
        local function caption(dropdown,value)
            local label=dropdown.Text;if not label or dropdown._captioning then return end
            dropdown._captioning=true
            local ok,err=pcall(function()
                local full=tostring(value or '')
                dropdown._fullCaption=full
                requireResource(app.fonts:Apply(label,'control'));requireResource(app.ui:Color(label,'text'))
                local available=math.max(1,dropdown:GetWidth()-32)
                label:SetText(full)
                local function width()return label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()end
                local shortened=full
                while width()>available and #shortened>0 do
                    local last=#shortened
                    while last>1 and shortened:byte(last)>=128 and shortened:byte(last)<192 do last=last-1 end
                    shortened=shortened:sub(1,last-1);label:SetText(shortened..'...')
                end
                dropdown._truncated=shortened~=full
                label:ClearAllPoints();label:SetPoint('CENTER',dropdown,'CENTER',-4,0);label:SetWidth(available);label:SetHeight(dropdown:GetHeight());label:SetJustifyH('CENTER');label:SetJustifyV('MIDDLE');label:SetWordWrap(false)
            end)
            dropdown._captioning=nil
            if not ok then error(err,0)end
        end
        local function dropdown(id,parent,entries,get,set)
            local d=frame(id,'DropdownButton',parent,'WowStyle1DropdownTemplate,BackdropTemplate');panel._menus[id]=d;d:EnableMouse(true);d:SetSize(230,26)
            -- Keep native menu/selection behavior, but own the closed control's
            -- chrome. Forever's template artwork extends beyond its bounds.
            requireResource(app.ui:Style(d,'dropdown'))
            if not panel._menuFont then panel._menuFont=CreateFont(app.name..'_SND_Menu')end
            requireResource(app.fonts:Apply(panel._menuFont,'menu'))
            d:SetupMenu(function(_,root)
                root:SetScrollMode(240)
                root:AddMenuReleasedCallback(function()
                    if panel._refreshPending and panel:IsShown() then
                        app._system:After(0,'options-menu-refresh',function() if panel:IsShown() then panel:Refresh() end end)
                    end
                end)
                local offered=entries
                if type(entries)=='function' then offered=entries() end
                offered=I.copy(offered)
                choices(offered)
                for _, entry in ipairs(offered) do
                    local row=root:CreateRadio(entry.label,function(value)return I.equal(get(),value)end,set,entry.value)
                    row:AddInitializer(function(native) if native.fontString then native.fontString:SetFontObject(panel._menuFont) end end)
                end
            end)
            if d.Text and not d._captionHooks then
                local owner=app:Scope()
                local ok,err=owner:PostHook(d.Text,'SetText',function(_,value)caption(d,value)end)
                if not ok then owner:Cancel();error(err.message)end
                local function hideTip()if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()==d then GameTooltip:Hide()end end
                for event,fn in pairs({OnEnter=function()
                    if d._truncated and GameTooltip then GameTooltip:SetOwner(d,'ANCHOR_RIGHT');GameTooltip:SetText(d._fullCaption,nil,nil,nil,nil,true);GameTooltip:Show()end
                end,OnLeave=hideTip,OnHide=hideTip})do
                    local attached,failure=owner:HookScript(d,event,fn);if not attached then owner:Cancel();error(failure.message)end
                end
                d._captionHooks=owner
            end
            local selected=get();local label=selected==nil and 'Choose' or tostring(selected)
            local offered=type(entries)=='function' and entries() or entries;choices(offered)
            for _,entry in ipairs(offered)do if I.equal(entry.value,selected)then label=entry.label;break end end
            d:SetDefaultText(label);caption(d,label);return d
        end
        local function control(id,parent,c,width)
            local kind=c.type;local widget,label,height
            local field=c.key and app._settingsFields and app._settingsFields[c.key]
            if c.key then I.check(field,'control binds unknown field: '..c.key) end
            local function write(value) if not panel._refreshing then report(app:Set(c.key,value)) end end
            if kind=='custom' then
                local container=frame(id,'Frame',parent);container:SetWidth(width);container:Show()
                local component=panel._components[id]
                if not component then component=c.create(container,app,panel._view);I.check(component and component.Refresh and component.Layout and component.Hide,'invalid custom component');panel._components[id]=component end
                component:Refresh();local height=component:Layout(width);container:SetHeight(height);return container,height,component
            elseif kind=='description' then
                label=text(id,parent,c.text or c.label,'muted');label:SetWidth(width);label:SetWordWrap(true);height=math.max(22,label:GetStringHeight()+8)
            elseif kind=='button' then
                widget=button(id,parent,c.label,function()I.call(app,c.action,app)end);height=34
            elseif kind=='checkbox' then
                widget=frame(id,'CheckButton',parent,'BackdropTemplate');widget:EnableMouse(true);widget:RegisterForClicks('LeftButtonUp');widget:SetSize(20,20);requireResource(app.ui:Style(widget,'checkbox'));widget:SetChecked(app:Get(c.key))
                label=text(id..':label',parent,c.label);label:SetWidth(width-28);widget:SetScript('OnClick',function(b)write(b:GetChecked()==true)end);height=math.max(28,label:GetStringHeight()+8)
            elseif kind=='select' or kind=='font' then
                widget=dropdown(id,parent,kind=='font' and function()return app.fonts:Entries()end or c.choices or {},function()return app:Get(c.key)end,write)
                label=text(id..':label',parent,c.label);height=56
            elseif kind=='text' or kind=='number' then
                widget=input(id,parent,math.min(width,230))
                widget:SetText(tostring(app:Get(c.key)));requireResource(app.fonts:Apply(widget,'control'))
                widget:SetScript('OnEnterPressed',function(e)write(kind=='number' and tonumber(e:GetText()) or e:GetText());e:ClearFocus();panel:Refresh()end)
                widget:SetScript('OnEscapePressed',function(e)e:ClearFocus();panel:Refresh()end)
                label=text(id..':label',parent,c.label);height=56
            elseif kind=='slider' then
                I.check(field and field.min and field.max,'slider requires bounds')
                widget=frame(id,'Slider',parent,'BackdropTemplate');widget:EnableMouse(true);widget:SetSize(math.min(width,260),18);widget:SetOrientation('HORIZONTAL')
                requireResource(app.ui:Style(widget,'slider'))
                widget:SetMinMaxValues(field.min,field.max);widget:SetValueStep(c.step or 1);widget:SetObeyStepOnDrag(true);widget:SetValue(app:Get(c.key))
                widget:SetScript('OnValueChanged',function(_,value)write(value)end)
                local value=app:Get(c.key);local formatted=c.format=='percent' and string.format('%g%%',value*100) or type(c.format)=='function' and c.format(value) or tostring(value)
                label=text(id..':label',parent,c.label..': '..formatted..(c.units and ' '..c.units or ''));height=56
            elseif kind=='color' then
                widget=button(id,parent,'',function()color(c)end)
                label=text(id..':label',parent,c.label)
                local value=app:Get(c.key)
                if not widget._swatch then
                    widget._swatch=widget:CreateTexture(nil,'ARTWORK')
                    widget._swatch:SetPoint('TOPLEFT',5,-5);widget._swatch:SetPoint('BOTTOMRIGHT',-5,5)
                end
                widget._swatch:SetColorTexture(value[1],value[2],value[3],1);height=34
            else I.check(false,'unknown control type') end
            local paired=kind=='select' or kind=='font' or kind=='text' or kind=='number' or kind=='slider' or kind=='color'
            local inline=paired and width>=420
            if label then
                label:SetWidth(kind=='checkbox' and width-28 or inline and width-246 or width);label:SetWordWrap(true)
                if paired then
                    widget:SetWidth(math.min(230,width))
                    if kind=='select' or kind=='font' then caption(widget,widget._fullCaption) end
                    height=inline and math.max(34,label:GetStringHeight()+10) or math.max(56,label:GetStringHeight()+34)
                end
            end
            if c.hint then
                local hint=text(id..':hint',parent,c.hint,'muted');hint:SetWidth(width)
                height=height+hint:GetStringHeight()+6
            end
            if widget then
                local allowed=not app.profiles:Capabilities().readOnly or not c.key
                if c.enabled then allowed=allowed and c.enabled(app) end
                widget:SetEnabled(allowed);widget:SetAlpha(allowed and 1 or .45);widget:Show()
                if widget.Text then requireResource(app.ui:Color(widget.Text,'text')) end
                if label then requireResource(app.ui:Color(label,allowed and 'text' or 'muted')) end
            end
            return widget,height,label
        end
        function panel:_build()
            local name=app.name..'_SND_Options'
            if not self._pool.shell then
                I.check(_G[name]==nil,'options frame name is already in use')
                self._pool.shell=CreateFrame('Frame',name,UIParent,'BackdropTemplate')
            end
            local f=self._pool.shell;self.frame=f;f:Hide()
            f:SetSize(spec.width or 640,spec.height or 500);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
            f:SetScript('OnDragStart',function()f:StartMoving()end);f:SetScript('OnDragStop',function()f:StopMovingOrSizing()end)
            f:SetScript('OnHide',function()self:_deactivate()end);requireResource(app.ui:Style(f,'dialog'))
            local title=text('title',f,spec.title or app.name,'heading');title:SetPoint('TOPLEFT',16,-16)
            local close=button('close',f,'×',function()self:Close()end);close:SetSize(26,26);close:SetPoint('TOPRIGHT',-10,-10)
            local scroll=frame('scroll','ScrollFrame',f);self.scroll=scroll;scroll:SetPoint('TOPLEFT',16,-90);scroll:SetPoint('BOTTOMRIGHT',-30,16)
            local child=frame('body','Frame',scroll);self.body=child;scroll:SetScrollChild(child)
            local bar=frame('scrollbar','Slider',f,'BackdropTemplate');self.bar=bar;bar:EnableMouse(true);bar:SetPoint('TOPRIGHT',-10,-90);bar:SetPoint('BOTTOMRIGHT',-10,16);bar:SetWidth(8);bar:SetValueStep(1);bar:SetOrientation('VERTICAL')
            requireResource(app.ui:Style(bar,'scrollbar'));bar._thumb=bar._sndControlArt.thumb
            bar:SetScript('OnValueChanged',function(_,value)
                if not self._refreshing and value~=(self._offsets[self._page] or 0)then self:_cancelEditors()end
                scroll:SetVerticalScroll(value);self._offsets[self._page]=value
            end)
            scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function(_,delta)bar:SetValue(math.max(0,math.min(self._maximum or 0,(self._offsets[self._page] or 0)-delta*30)))end)
            for i,page in ipairs(self._pages) do
                local b=button('tab:'..page.id,f,page.label or page.id,function()report(self:SelectPage(page.id))end)
                local tabWidth=((spec.width or 640)-32-(#self._pages-1)*4)/#self._pages
                b:SetSize(tabWidth,26);b:SetPoint('TOPLEFT',16+(i-1)*(tabWidth+4),-50)
                if not b._selected then
                    b._selected=b:CreateTexture(nil,'OVERLAY');b._selected:SetColorTexture(1,1,1,1)
                    b._selected:SetPoint('BOTTOMLEFT',1,1);b._selected:SetPoint('BOTTOMRIGHT',-1,1);b._selected:SetHeight(2)
                    requireResource(app.ui:Color(b._selected,'accent'))
                end
            end
            if not self._keep then local ok,result=app.layout:KeepOnScreen(f,{margin=8});I.check(ok,result.message or 'layout unavailable');self._keep=result end
            if not self._escape then
                UISpecialFrames=UISpecialFrames or {};table.insert(UISpecialFrames,name)
                self._escape=I.handle(app,function()
                    for index=#UISpecialFrames,1,-1 do if UISpecialFrames[index]==name then table.remove(UISpecialFrames,index)end end
                end)
            end
            self._built=true
        end
        function panel:_profiles()
            local caps=app.profiles:Capabilities();local operations=caps.operations or {}
            local controls={{type='description',text=caps.needsCharacter and 'Waiting for character identity.' or caps.readOnly and 'Settings are read-only.' or 'Manage this add-on’s profiles.'}}
            -- Profile actions are explicit commands; confirmation lives in this page.
            local parent=self.body;local width=parent:GetWidth()
            local status=text('profile-status',parent,self._profileError or controls[1].text,'muted')
            status:ClearAllPoints();status:SetPoint('TOPLEFT');status:SetWidth(width);status:SetWordWrap(true)
            local y=status:GetStringHeight()+16
            local function place(widget,x)
                widget:ClearAllPoints();widget:SetPoint('TOPLEFT',x or 0,-y);widget:Show()
                widget:SetEnabled(not caps.readOnly);widget:SetAlpha(caps.readOnly and .45 or 1)
            end
            local function menuWidth(menu)
                menu:SetWidth(math.min(230,width));caption(menu,menu._fullCaption)
            end
            local function pair(first,second)
                place(first)
                if width>=384 then
                    second:SetWidth(140);place(second,244)
                else
                    y=y+34;second:SetWidth(math.min(230,width));place(second)
                end
                y=y+36
            end
            local function command(method,name)
                self._confirm=nil
                -- Empty edit fields and unselected menus are ordinary user input,
                -- not programmer calls to the stricter public profile commands.
                if method~='Reset' and (type(name)~='string' or not name:find('%S')) then
                    self._profileError=method=='Duplicate' and 'Enter a profile name.' or 'Choose a profile.'
                else
                    local ok,err=app.profiles[method](app.profiles,name)
                    self._profileError=not ok and err.message or nil
                end
                self:Refresh()
            end
            if operations.switch then
                local menu=dropdown('profile-select',parent,function()local list={};for _,name in ipairs(app.profiles:List())do list[#list+1]={label=name,value=name}end;return list end,function()return app.profiles:Active()end,function(name)report(app.profiles:Switch(name))end)
                menuWidth(menu);place(menu);y=y+36
            end
            if operations.duplicate then
                local input=input('profile-name',parent,math.min(230,width))
                local add=button('profile-add',parent,'Duplicate',function()command('Duplicate',input:GetText())end);pair(input,add)
            end
            if operations.copy then
                local menu=dropdown('profile-copy',parent,function()local list={};for _,name in ipairs(app.profiles:List())do list[#list+1]={label=name,value=name}end;return list end,function()return self._copySource end,function(name)self._copySource=name end)
                menuWidth(menu)
                local copy=button('profile-copy-button',parent,'Copy into active',function()
                    if not self._copySource then command('CopyFrom',nil);return end
                    self._profileError=nil;self._confirm={kind='copy',name=self._copySource};self:Refresh()
                end);pair(menu,copy)
            end
            if operations.reset then
                local reset=button('profile-reset',parent,'Reset active',function()self._confirm={kind='reset'};self:Refresh()end);place(reset);y=y+36
            end
            if self._confirm then
                local confirm=button('profile-confirm',parent,'Confirm replacement',function()
                    local action=self._confirm;self._confirm=nil
                    if not action then return end
                    if action.kind=='copy' then command('CopyFrom',action.name) else command('Reset') end
                end)
                local cancel=button('profile-cancel',parent,'Cancel',function()self._confirm=nil;self:Refresh()end);pair(confirm,cancel)
            end
            return y
        end
        function panel:Refresh()
            if not self:IsShown() then return true end
            if self._refreshing then self._refreshAgain=true;return true end
            if self:_menuOpen() then self._refreshPending=true;return true end
            self._refreshPending=nil
            for pass=1,3 do
            self._refreshAgain=nil
            local ok,err=pcall(function()
                self._refreshing=true
                local scale=math.max(.1,math.min(1,(UIParent:GetWidth()-16)/(spec.width or 640)));self.frame:SetScale(scale)
                self.frame:SetHeight(math.max(140,math.min(spec.height or 500,(UIParent:GetHeight()-16)/scale)))
                local width=(spec.width or 640)-60;self.body:SetWidth(width)
                self._used,self._usedText={},{}
                local page;for _,p in ipairs(self._pages)do if p.id==self._page then page=p end end
                local y=0
                if page._profiles then y=self:_profiles()+12 end
                for si,section in ipairs(page.sections or {}) do
                    if section.title then
                        local label=text(page.id..':section:'..si,self.body,section.title,'heading');label:ClearAllPoints();label:SetWidth(width);label:SetWordWrap(true);label:SetPoint('TOPLEFT',0,-y);y=y+label:GetStringHeight()+10
                    end
                    for ci,c in ipairs(section.controls or {}) do
                        local id=page.id..':'..si..':'..(c.id or ci)
                        if not c.visible or c.visible(app) then
                            local widget,height,caption=control(id,self.body,c,width)
                            local paired=c.type=='select' or c.type=='font' or c.type=='text' or c.type=='number' or c.type=='slider' or c.type=='color'
                            local inline=paired and width>=420
                            if widget then
                                widget:ClearAllPoints();widget:SetPoint('TOPLEFT',inline and width-widget:GetWidth() or 0,-y-(paired and not inline and caption:GetStringHeight()+6 or 0))
                            end
                            if caption and caption.SetPoint then
                                caption:ClearAllPoints();caption:SetPoint('TOPLEFT',c.type=='checkbox' and 28 or 0,-y-(inline and math.max(0,(widget:GetHeight()-caption:GetStringHeight())/2) or 0))
                            end
                            if c.hint then local hint=self._texts[id..':hint'];hint:ClearAllPoints();hint:SetPoint('TOPLEFT',0,-y-height+hint:GetStringHeight()+6)end
                            y=y+height
                        elseif self._components[id] then self._components[id]:Hide() end
                    end
                    y=y+12
                end
                for id,widget in pairs(self._pool)do if widget:GetParent()==self.body and not self._used[id] then widget:Hide()end end
                for id,label in pairs(self._texts)do if label:GetParent()==self.body and not self._usedText[id] then label:Hide()end end
                self._used,self._usedText=nil,nil
                for _,b in pairs(self._buttons)do fitButton(b)end
                for _,p in ipairs(self._pages)do
                    local b=self._pool['tab:'..p.id];b._selected:SetShown(p.id==self._page)
                    requireResource(app.ui:Color(b.text,p.id==self._page and 'accent' or 'muted'))
                end
                self.body:SetHeight(math.max(1,y));self._maximum=math.max(0,y-self.scroll:GetHeight())
                self.bar._thumb:SetHeight(math.max(24,self.bar:GetHeight()*math.min(1,self.scroll:GetHeight()/math.max(1,y))))
                self.bar:SetMinMaxValues(0,self._maximum);self.bar:SetValue(math.min(self._maximum,self._offsets[self._page] or 0));self.bar:SetShown(self._maximum>0)
                if self._keep then self._keep:Refresh() end
            end)
            self._refreshing=nil;self._used,self._usedText=nil,nil
            if not ok then self:Close();I.report(app,err);return false,I.error('build',err) end
            if not self._refreshAgain then return true end
            end
            self._refreshAgain=nil
            self:Close();return false,I.error("build","Options layout did not settle after three passes")
        end
        function panel:Open(pageID)
            if not app._ready then return false,I.error('notReady') end
            if pageID and not ids[pageID] then return false,I.error('unknownPage') end
            if self:IsShown() then if pageID then return self:SelectPage(pageID) end;return true end
            if pageID then self._page=pageID end
            if not self._built then local ok,err=pcall(self._build,self);if not ok then self:Close();return false,I.error('build',err) end end
            self._view=app:Scope('options-page');self.frame:Show()
            local opened,failure=self:Refresh();if not opened then return false,failure end
            local owner=self._view
            owner:Watch(app:SelectAppearance(function(value)return value end),function()self:Refresh()end)
            if self._view~=owner then return false,I.error('build','Initial appearance refresh failed')end
            if app._settingsStore then owner:Watch(app:SelectSettings(function(values,context)return{values=values,context=context}end),function()self._confirm=nil;self._profileError=nil;self:Refresh()end) end
            if self._view~=owner then return false,I.error('build','Initial settings refresh failed')end
            return true
        end
        function panel:Close() self._confirm=nil;self:_deactivate();if self.frame then self.frame:Hide() end;return true end
        function panel:IsShown() return self.frame~=nil and self.frame:IsShown() end
        function panel:Toggle() if self:IsShown() then return self:Close() else return self:Open() end end
        function panel:SelectPage(id)
            if not ids[id] then return false,I.error('unknownPage') end
            if not self:IsShown() then self._page=id;return true end
            if self._page==id then return true end
            self:Close();return self:Open(id)
        end
        app:OnReady(function()
            for _,event in ipairs({'UI_SCALE_CHANGED','DISPLAY_SIZE_CHANGED'})do
                app._system:Event(event,function()panel:_cancelEditors();panel:Refresh()end)
            end
        end)
        return panel
    end
end
