-- Deliberately small native boundary fixture; not a rendering emulator.
local W = {frames={}, errors={}, time=0, hooks=0}
local methods={}
local function object(kind,parent)
    local f={kind=kind,parent=parent,scripts={},events={},shown=true,width=100,height=24,scale=1,left=0,bottom=0,text='',enabled=true}
    setmetatable(f,{__index=methods});W.frames[#W.frames+1]=f;return f
end
function CreateFrame(kind,name,parent,template)
    if W.failTemplate and W.failTemplate==template then W.failTemplate=nil;error('simulated constructor failure') end
    local f=object(kind,parent);f.template=template
    if name then _G[name]=f end
    if template=='UICheckButtonTemplate' or kind=='DropdownButton' then f.Text=object('FontString',f) end
    return f
end
function CreateFont(name)local f=object('Font');_G[name]=f;return f end
function methods:CreateFontString()return object('FontString',self)end
function methods:SetScript(name,fn)self.scripts[name]=fn end
function methods:GetScript(name)return self.scripts[name]end
function methods:HookScript(name,fn)
    local old=self.scripts[name];self.scripts[name]=function(...)if old then old(...)end;fn(...)end
end
function methods:RegisterEvent(event)self.events[event]=true end
function methods:UnregisterEvent(event)self.events[event]=nil end
function methods:UnregisterAllEvents()self.events={}end
function methods:GetParent()return self.parent end
function methods:Show()if not self.shown then self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self)end end end
function methods:Hide()if self.shown then self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self)end end end
function methods:IsShown()return self.shown end
function methods:SetShown(value)if value then self:Show()else self:Hide()end end
function methods:SetSize(w,h)self.width,self.height=w,h end
function methods:SetWidth(w)self.width=w end
function methods:SetHeight(h)self.height=h end
function methods:GetWidth()return self.width end
function methods:GetHeight()return self.height end
function methods:SetScale(scale)self.scale=scale end
function methods:GetEffectiveScale()return self.scale*(self.parent and self.parent:GetEffectiveScale()or 1)end
function methods:GetLeft()return self.left end
function methods:GetBottom()return self.bottom end
function methods:ClearAllPoints()self.points={}end
function methods:SetPoint(...)
    self.points={...}
    if select(1,...)=='BOTTOMLEFT' and select('#',...)==5 then self.left,self.bottom=select(4,...),select(5,...)end
end
function methods:SetBackdrop(value)self.backdrop=value end
function methods:GetBackdrop()return self.backdrop end
function methods:SetBackdropColor(...)self.background={...}end
function methods:GetBackdropColor()return unpack(self.background or {0,0,0,1})end
function methods:SetBackdropBorderColor(...)self.border={...}end
function methods:SetFont(path,size,flags)
    if self.rejectFont==path then return false end
    self.font,self.fontSize,self.flags=path,size+.25,flags -- Native void return/fractional readback.
end
function methods:GetFont()return self.font or 'Fonts\\FRIZQT__.TTF',self.fontSize or 13,self.flags or ''end
function methods:SetFontObject(font)self.font,self.fontSize,self.flags=font:GetFont()end
function methods:SetText(value)self.text=tostring(value or '')end
function methods:GetText()return self.text end
function methods:GetStringWidth()return #self.text*7 end
function methods:GetStringHeight()return math.max(14,math.ceil(#self.text*7/self.width)*14)end
function methods:SetEnabled(value)self.enabled=value end
function methods:SetChecked(value)self.checked=value end
function methods:GetChecked()return self.checked end
function methods:SetMinMaxValues(low,high)self.minimum,self.maximum=low,high end
function methods:SetValue(value)
    self.value=math.max(self.minimum or value,math.min(self.maximum or value,value))
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,self.value)end
end
function methods:GetValue()return self.value end
function methods:SetScrollChild(child)self.child=child end
function methods:SetVerticalScroll(value)self.offset=value end
function methods:SetupMenu(build)
    assert(not self.menuOpen,'regenerated an open native menu');self.buildMenu=build
end
function methods:SetDefaultText(text)self.defaultText=text end
function methods:IsMenuOpen()return self.menuOpen end
function methods:OpenMenu()
    self.menuOpen=true
    local root={}
    function root:SetScrollMode()end
    function root:AddMenuReleasedCallback(fn)self.release=fn end
    function root:CreateRadio(label,selected,choose,value)
        local row={};function row:AddInitializer(fn)fn({fontString=object('FontString')})end;return row
    end
    self.root=root;self.buildMenu(self,root)
end
function methods:CloseMenu()if self.menuOpen then self.menuOpen=false;if self.root.release then self.root.release()end end end
function methods:IsProtected()return self.protected==true end
function methods:IsForbidden()return self.forbidden==true end
function methods:StartMoving()self.moving=true end
function methods:StopMovingOrSizing()self.moving=false end
function methods:ClearFocus()self.focus=false end
for _,name in ipairs({'SetFrameStrata','EnableMouse','SetMovable','RegisterForDrag','EnableMouseWheel','SetValueStep','SetObeyStepOnDrag','SetAutoFocus','SetWordWrap','SetJustifyH','SetTextColor'})do methods[name]=function()end end
UIParent=object('Frame');UIParent:SetSize(1280,720)
GameFontNormal=object('Font');GameTooltipText=object('Font')
ColorPickerFrame=object('Frame');ColorPickerFrame:Hide()
function ColorPickerFrame:GetExtraInfo()return self.info and self.info.extraInfo end
function ColorPickerFrame:GetColorRGB()return unpack(self.rgb)end
function ColorPickerFrame:SetupColorPickerAndShow(info)self.info=info;self.rgb={info.r,info.g,info.b};self:Show();info.swatchFunc()end
function W.color(r,g,b,finish,cancel)
    local picker=ColorPickerFrame;picker.rgb={r,g,b}
    if finish then picker:Hide()end
    if cancel then picker.info.cancelFunc()else picker.info.swatchFunc()end
end
function geterrorhandler()return function(message)W.errors[#W.errors+1]=message end end
function hooksecurefunc(target,key,callback)
    W.hooks=W.hooks+1;local old=target[key]
    target[key]=function(...)local out={old(...)};callback(...);return unpack(out)end
end
function W.event(name,...)
    local list={};for _,f in ipairs(W.frames)do list[#list+1]=f end
    for _,f in ipairs(list)do if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name,...)end end
end
function W.tick(elapsed)
    W.time=W.time+elapsed;local list={};for _,f in ipairs(W.frames)do list[#list+1]=f end
    for _,f in ipairs(list)do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,elapsed)end end
end
function W.load(name)
    local ns={}
    for _,file in ipairs({'Core','Diagnostics','Scope','State','Settings','UI','Options'})do assert(loadfile('src/'..file..'.lua'))(name,ns)end
    return ns.SomethingNeedDoing
end
return W
