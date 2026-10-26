local _, ns = ...
local SND = ns.SomethingNeedDoing; local I, V = SND._, SND.Values
local types = { boolean=true, number=true, integer=true, string=true, enum=true, font=true, color=true }
local function fieldValid(value, field)
    if not V.Readable(value) then return false end
    local kind = field.type
    if kind == 'boolean' then return type(value) == 'boolean' end
    if kind == 'number' or kind == 'integer' then
        return V.Number(value) and (kind ~= 'integer' or value == math.floor(value)) and
            (not field.min or value >= field.min) and (not field.max or value <= field.max)
    end
    if kind == 'string' or kind == 'font' then return type(value) == 'string' and #value <= (field.maxLength or 256) end
    if kind == 'enum' then
        for _, entry in ipairs(field.values) do if I.equal(value, entry) then return true end end
        return false
    end
    if kind == 'color' then
        if not I.plain(value) or value[1]==nil or value[2]==nil or value[3]==nil then return false end
        for k,v in pairs(value) do if (k ~= 1 and k ~= 2 and k ~= 3) or not V.Number(v) or v < 0 or v > 1 then return false end end
        return true
    end
    return false
end
local function put(values,path,value)
    local keys={};for key in path:gmatch('[^.]+')do keys[#keys+1]=key end
    for index=1,#keys-1 do local key=keys[index];values[key]=values[key] or {};values=values[key]end
    values[keys[#keys]]=value
end
-- Default storage is deliberately small. Existing databases keep their migration adapters.
local function profileAdapter(global)
    local function defaults(fields)
        local values={};for path,field in pairs(fields)do put(values,path,I.copy(field.default))end;return values
    end
    local function result(db,readOnly)
        local names={};for name in pairs(db.profiles)do names[#names+1]=name end;table.sort(names)
        return {state={values=I.copy(db.profiles[db.active]),activeProfile=db.active,readOnly=readOnly==true,
            profiles={names=names,operations={switch=true,duplicate=true,copy=true,reset=true}},database=db},
            saved=not readOnly and {[global]=db} or nil}
    end
    local function nameValid(name)
        return type(name)=='string' and #name>0 and #name<=48 and name:match('^%s*(.-)%s*$')==name and not name:find('[%c|]')
    end
    local adapter={}
    function adapter:Restore(saved,fields)
        local empty={version=1,active='Default',profiles={Default=defaults(fields)}}
        local db=saved[global]
        if db==nil then return true,result(empty)end
        if not I.plain(db) or db.version~=1 then return true,result(empty,true)end
        if not I.plain(db.profiles) or not nameValid(db.active) or not I.plain(db.profiles[db.active]) then return false,I.error('invalid','Malformed profile database')end
        local count=0
        for name,values in pairs(db.profiles)do
            count=count+1
            if count>32 or not nameValid(name) or not I.plain(values) then return false,I.error('invalid','Malformed profile')end
            for path,field in pairs(fields)do
                if I.get(values,path)==nil then put(values,path,I.copy(field.default))end
                if not fieldValid(I.get(values,path),field) then return false,I.error('invalid','Invalid saved field: '..path)end
            end
        end
        return true,result(db)
    end
    function adapter:Prepare(state,operation,fields)
        local db=state.database;local name=operation.name;local kind=operation.kind
        if kind=='set' then put(db.profiles[db.active],operation.path,I.copy(operation.value))
        elseif kind=='patch' then for path,value in pairs(operation.values)do put(db.profiles[db.active],path,I.copy(value))end
        elseif kind=='reset' then db.profiles[db.active]=defaults(fields)
        elseif kind=='switch' or kind=='copy' then
            if not db.profiles[name] then return false,I.error('notFound','Profile not found')end
            if kind=='switch' then db.active=name else db.profiles[db.active]=I.copy(db.profiles[name])end
        elseif kind=='duplicate' then
            if not nameValid(name) then return false,I.error('invalid','Use a profile name of 1–48 characters without control characters or pipes')end
            if db.profiles[name] then return false,I.error('exists','Profile already exists')end
            local count=0;for _ in pairs(db.profiles)do count=count+1 end
            if count>=32 then return false,I.error('limit','Profile limit reached (32)')end
            db.profiles[name]=I.copy(db.profiles[db.active]);db.active=name
        else return false,I.error('unsupported')end
        return true,result(db)
    end
    return adapter
end
SND._install[#SND._install + 1] = function(app)
    local spec, current, store, listeners = nil, nil, nil, {}
    local function validate(state)
        I.check(type(state) == 'table' and type(state.values) == 'table', 'adapter must supply values')
        I.check(state.needsCharacter == nil or type(state.needsCharacter) == 'boolean', 'invalid needsCharacter')
        I.check(state.activeProfile == nil or (type(state.activeProfile) == 'string' and state.activeProfile ~= ''), 'invalid activeProfile')
        if state.profiles ~= nil then
            I.check(I.plain(state.profiles), 'invalid profiles descriptor')
            local names = state.profiles.names; if names==nil then names={} end; I.array(names, 'profile names')
            local unique = {}; for _, name in ipairs(names) do I.check(type(name)=='string' and name~='' and not unique[name], 'invalid or duplicate profile name'); unique[name]=true end
            I.check(state.activeProfile == nil or unique[state.activeProfile], 'active profile is missing from profile names')
            I.check(state.profiles.operations == nil or I.plain(state.profiles.operations), 'invalid profile operations')
            for key, value in pairs(state.profiles.operations or {}) do
                I.check(({switch=true,duplicate=true,copy=true,reset=true,bind=true})[key] and type(value)=='boolean', 'invalid profile operation')
            end
        end
        I.check(state.readOnly == nil or type(state.readOnly) == 'boolean', 'invalid readOnly')
        for path, field in pairs(spec.fields) do I.check(fieldValid(I.get(state.values, path), field), 'invalid field: ' .. path) end
        return I.copy(state)
    end
    local function savedCopy(saved)
        I.check(type(saved) == 'table', 'adapter must supply saved globals')
        local result = {}
        for _, name in ipairs(spec.savedVariables) do I.check(saved[name] ~= nil, 'missing saved global: ' .. name); result[name] = I.copy(saved[name]) end
        for name in pairs(saved) do I.check(result[name] ~= nil, 'undeclared saved global: ' .. tostring(name)) end
        return result
    end
    local function publish(state, saved)
        current = state
        store._values = I.copy(state.values)
        store._context = { activeProfile = state.activeProfile, readOnly = state.readOnly == true, needsCharacter = state.needsCharacter == true }
        if saved then for _, name in ipairs(spec.savedVariables) do _G[name] = saved[name] end end
    end
    function app:Settings(declaration)
        I.check(not spec and not self._ready and not self._disposed, 'declare settings once before readiness')
        I.check(I.plain(declaration), 'settings declaration must be a plain table')
        declaration=I.definition(declaration)
        if declaration.adapter==nil then
            I.check(I.array(declaration.savedVariables,'savedVariables',true)==1,'default profiles require one saved global')
            declaration.adapter=profileAdapter(declaration.savedVariables[1])
        end
        I.check(I.plain(declaration.adapter), 'settings adapter must be a plain table')
        I.check(type(declaration.adapter.Restore)=='function' and type(declaration.adapter.Prepare)=='function', 'settings adapter requires Restore and Prepare')
        local candidate = { adapter=I.definition(declaration.adapter), fields=I.copy(declaration.fields), savedVariables=I.copy(declaration.savedVariables) }
        I.check(I.plain(candidate.fields), 'fields must be a plain table')
        I.array(candidate.savedVariables, 'savedVariables', true)
        local names = {}
        for _, name in ipairs(candidate.savedVariables) do I.check(type(name)=='string' and name:match('^[%a_][%w_]*$') and not names[name], 'invalid saved name'); names[name]=true end
        for path, field in pairs(candidate.fields) do
            I.check(type(path)=='string' and path:match('^[%w_]+[.%w_]*$') and not path:find('..',1,true) and path:sub(-1)~='.', 'invalid setting path')
            I.check(I.plain(field) and types[field.type], 'invalid field declaration: '..path)
            I.check(field.label==nil or type(field.label)=='string','field label must be a string')
            for _, key in ipairs({'min','max','maxLength'}) do I.check(field[key]==nil or V.Number(field[key]), 'field bounds must be finite numbers') end
            I.check(not field.min or not field.max or field.min<=field.max, 'field min exceeds max')
            I.check(field.maxLength==nil or (field.maxLength>=0 and field.maxLength==math.floor(field.maxLength)), 'maxLength must be a nonnegative integer')
            if field.type=='enum' then I.array(field.values, 'enum values', true) end
            I.check(fieldValid(field.default, field), 'invalid field default: '..path)
            for other in pairs(candidate.fields) do I.check(type(other)=='string' and (other==path or other:sub(1,#path+1)~=path..'.'), 'overlapping or invalid field paths') end
        end
        spec = candidate -- Invalid declarations must leave registration retryable.
        store = I.store(self, {}); self._settingsFields = spec.fields; self._settingsStore = store
    end
    function app:_restore()
        if not spec then return true end
        local ok, state, saved = I.lock(self, function()
            local restored = {}
            for _, name in ipairs(spec.savedVariables) do restored[name] = _G[name] end
            -- Saved globals may contain future/legacy data: adapter owns its interpretation.
            local accepted, result = spec.adapter:Restore(I.copy(restored), I.copy(spec.fields))
            I.check(type(accepted)=='boolean', 'Restore must return a Result tuple')
            if not accepted then error(I.error('restore', result)) end
            I.check(I.plain(result), 'Restore result must contain state and saved')
            local nextState = validate(result.state)
            return nextState, not nextState.readOnly and savedCopy(result.saved) or nil
        end)
        if not ok then return false, I.error('restore', state) end
        publish(state, saved); return true
    end
    function app:Get(path)
        I.check(type(path)=='string' and self._ready and store and spec.fields[path], 'unknown field or settings not ready')
        return I.copy(I.get(current.values, path))
    end
    function app:SelectSettings(project) I.check(store, 'declare settings first'); return store:Select(project) end
    function app:OnSettingsChanged(callback)
        I.check(not self._disposed and type(callback) == 'function', 'callback required on a live app')
        local h; h = I.handle(self, function() listeners[h] = nil; h._callback = nil end)
        self._order = self._order + 1; h._order = self._order; h._callback = callback; listeners[h] = true
        return h
    end
    local function commit(operation, expectedRevision)
        if not app._ready or not store then return false, I.error('notReady') end
        if app._locked then return false, I.error('reentrant') end
        if expectedRevision ~= nil and expectedRevision ~= store._revision then return false, I.error('stale') end
        if current.readOnly and not (operation.kind == 'bind' and current.needsCharacter) then return false, I.error('readOnly') end
        local ok, candidate, failure = I.lock(app, function()
            local accepted, prepared = spec.adapter:Prepare(I.copy(current), I.copy(operation), I.copy(spec.fields))
            I.check(type(accepted)=='boolean', 'Prepare must return a Result tuple')
            if not accepted then return nil, prepared end
            I.check(I.plain(prepared), 'Prepare result must contain state and saved')
            local state = validate(prepared.state)
            return { state = state, saved = not state.readOnly and savedCopy(prepared.saved) or nil }
        end)
        if not ok then return false, I.error('invalid', candidate) end
        if not candidate then return false, I.error('rejected', failure) end
        if I.equal(current, candidate.state) then return true end
        local keys = {}
        for path in pairs(spec.fields) do if not I.equal(I.get(current.values,path), I.get(candidate.state.values,path)) then keys[path] = true end end
        local profileChanged = current.activeProfile ~= candidate.state.activeProfile or operation.kind == 'bind'
        -- Candidate is fully valid before any editor cleanup or publication.
        if app._panel then I.lock(app,function()app._panel:_cancelEditors((operation.kind == 'set' or operation.kind == 'patch'))end) end
        publish(candidate.state, candidate.saved); store._revision = store._revision + 1
        local change = { revision = store._revision, reason = operation.kind, keys = keys, profileChanged = profileChanged }
        function change:Touches(...) for i=1,select('#',...) do if self.keys[select(i,...)] then return true end end; return false end
        I.lock(app, function()
            store:_notify()
            for _, h in ipairs(I.snapshot(listeners)) do
                if h.active then
                    local record = { revision=change.revision, reason=change.reason, keys=I.copy(keys), profileChanged=profileChanged, Touches=change.Touches }
                    I.call(app, h._callback, app, record)
                end
            end
        end)
        return true
    end
    function app:Set(path, value, revision)
        I.check(type(path)=='string' and path~='', 'setting path must be a nonempty string')
        I.check(I.revision(revision), 'expectedRevision must be a nonnegative integer')
        if not spec or not spec.fields[path] then return false, I.error('unknownField') end
        local ok, valid = pcall(fieldValid, value, spec.fields[path])
        if not ok or not valid then return false, I.error('invalid') end
        return commit({ kind='set', path=path, value=value }, revision)
    end
    function app:SetMany(values,revision)
        I.check(I.plain(values),'settings patch must be a plain path/value map')
        I.check(I.revision(revision),'expectedRevision must be a nonnegative integer')
        for path,value in pairs(values)do
            I.check(type(path)=='string' and path~='','setting path must be a nonempty string')
            if not spec or not spec.fields[path] then return false,I.error('unknownField')end
            local ok,valid=pcall(fieldValid,value,spec.fields[path])
            if not ok or not valid then return false,I.error('invalid')end
        end
        return commit({kind='patch',values=values},revision)
    end
    local profiles = {}; app.profiles = profiles
    function profiles:List() return current and I.copy((current.profiles or {}).names or {}) or {} end
    function profiles:Active() return current and current.activeProfile end
    function profiles:Capabilities()
        local result = current and I.copy(current.profiles or {}) or {}
        result.readOnly = not current or current.readOnly == true; result.needsCharacter = current and current.needsCharacter == true or false
        return result
    end
    for method, kind in pairs({ BindCharacter='bind', Switch='switch', Duplicate='duplicate', CopyFrom='copy', Reset='reset' }) do
        local operation = kind
        profiles[method] = function(_, value)
            if operation=='bind' then I.check(value~=nil and value~=false, 'character identity required')
            elseif operation~='reset' then I.check(type(value)=='string' and value~='', 'profile name must be a nonempty string') end
            local capabilities = current and current.profiles or {}
            if not (capabilities.operations and capabilities.operations[operation]) then return false, I.error('unsupported') end
            return commit({ kind=operation, name=operation ~= 'bind' and value or nil, identity=operation == 'bind' and value or nil })
        end
    end
end
