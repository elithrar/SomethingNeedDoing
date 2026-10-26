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
SND._install[#SND._install + 1] = function(app)
    local ui, fonts, layout = {}, {}, {}; app.ui, app.fonts, app.layout = ui, fonts, layout
    local styled = setmetatable({}, {__mode='k'})
    function ui:Border(frame, kind)
        if not safeFrame(frame) or type(frame.SetBackdrop)~='function' or type(frame.SetBackdropColor)~='function' or type(frame.SetBackdropBorderColor)~='function' then return false, I.error('unavailable') end
        if kind ~= 'none' and not edges[kind] then return false, I.error('invalid') end
        local backdrop = frame.GetBackdrop and frame:GetBackdrop() or {}
        local spec = {}; for k,v in pairs(backdrop or {}) do spec[k] = v end
        spec.edgeFile = edges[kind]; spec.edgeSize = kind == 'thin' and 1 or kind == 'dialog' and 16 or 12
        local bg = frame.GetBackdropColor and { frame:GetBackdropColor() }
        local ok, err = pcall(frame.SetBackdrop, frame, spec)
        if not ok then return false, I.error('unavailable', err) end
        if bg and bg[1] then frame:SetBackdropColor(unpack(bg)) end
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(.45,.45,.45,1) end
        return true
    end
    function ui:Style(frame, role)
        if not roles[role] then return false, I.error('invalid') end
        if not safeFrame(frame) or type(frame.SetBackdrop)~='function' or type(frame.SetBackdropColor)~='function' or type(frame.SetBackdropBorderColor)~='function' then return false, I.error('unavailable') end
        frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8', edgeFile=edges.default, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3}})
        frame:SetBackdropColor(.055,.055,.065,.97); frame:SetBackdropBorderColor(.45,.45,.45,1)
        if not styled[frame] and (role=='button' or role=='tab') then
            styled[frame] = true
            app._system:HookScript(frame,'OnEnter',function(self) self:SetBackdropBorderColor(1,.82,.2,1) end)
            app._system:HookScript(frame,'OnLeave',function(self) self:SetBackdropBorderColor(.45,.45,.45,1) end)
        end
        return true
    end
    local applications = setmetatable({}, {__mode='k'})
    local sizes = {heading=16,body=14,muted=14,control=13,menu=13}
    local media, refreshing, startFonts
    local downgrade, generation = {}, 0
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
    local function apply(object, role)
        local fallback, nativeSize, flags = nativeFont()
        local path = fallback
        local selected = preference(); media = media or getMedia()
        if selected == 'Arial' then path='Fonts\\ARIALN.TTF'
        elseif selected == 'Friz Quadrata' then path='Fonts\\FRIZQT__.TTF'
        elseif selected == 'Game tooltip' and GameTooltipText and GameTooltipText.GetFont then path = GameTooltipText:GetFont()
        elseif media and media.Fetch then path = media:Fetch('font', selected, true) or fallback end
        local request = selected .. ':' .. tostring(path)
        path = downgrade[request] or path
        local size = sizes[role]
        if (role == 'body' or role == 'muted') and app._ready and app._settingsFields and app._settingsFields.fontSize then size = app:Get('fontSize') end
        local function try(candidate)
            local ok, result = pcall(object.SetFont,object,candidate,size,flags or '')
            if not ok or result == false then return false end
            local read, actual, height = pcall(object.GetFont,object)
            return read and type(actual)=='string' and actual:gsub('/','\\'):lower()==candidate:gsub('/','\\'):lower() and V.Number(height) and height>0
        end
        if not try(path) then
            if path~=fallback then downgrade[request]=fallback;generation=generation+1 end
            if not try(fallback) then
                if not object.SetFontObject or not GameFontNormal then return false,I.error('unavailable') end
                object:SetFontObject(GameFontNormal)
            end
        end
        if object.SetTextColor then
            if role=='heading' then object:SetTextColor(1,.82,.2)
            elseif role=='muted' then object:SetTextColor(.65,.65,.65)
            else object:SetTextColor(.93,.94,.97) end
        end
        return true
    end
    function fonts:Apply(object, role)
        if not sizes[role] or not nativeObject(object) or type(object.SetFont)~='function' or type(object.GetFont)~='function' then return false, I.error('invalid') end
        startFonts()
        applications[object] = role
        local before=generation
        local ok,err=apply(object,role)
        if generation~=before and not refreshing then self:Refresh() end
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
    function fonts:Refresh()
        startFonts()
        if refreshing then return end
        refreshing = true; media = getMedia()
        for _=1,3 do
            local before=generation
            for object,role in pairs(applications)do local ok,err=pcall(apply,object,role);if not ok then I.report(app,err)end end
            if before==generation then break end
        end
        refreshing = nil
    end
    local fontsRequested = false
    startFonts = function()
        I.check(not app._disposed, 'font service is disposed')
        if fontsRequested then return end
        fontsRequested = true
        local function activate()
            app:OnSettingsChanged(function(_, change) if change:Touches('font','fontSize') then fonts:Refresh() end end)
            local connected, mediaOwner
            local function connect()
                local lib=getMedia()
                if lib and lib~=connected and lib.RegisterCallback then
                    local owner=app:Scope()
                    local receiver={}
                    receiver.Changed = owner:Guard(function(_,_,kind)
                        if kind=='font' then downgrade={};fonts:Refresh();if app._panel then app._panel:Refresh()end end
                    end)
                    I.handle(owner,function()if lib.UnregisterAllCallbacks then lib.UnregisterAllCallbacks(receiver)end end)
                    local ok, err = pcall(lib.RegisterCallback,receiver,'LibSharedMedia_Registered','Changed')
                    if not ok then owner:Cancel();I.report(app,err);return end
                    if mediaOwner then mediaOwner:Cancel() end
                    connected=lib;media=lib;mediaOwner=owner
                    downgrade={};fonts:Refresh()
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
