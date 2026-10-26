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
        if type(value) ~= 'table' or #value ~= 3 then return false end
        for k,v in pairs(value) do if (k ~= 1 and k ~= 2 and k ~= 3) or not V.Number(v) or v < 0 or v > 1 then return false end end
        return true
    end
    return false
end
SND._install[#SND._install + 1] = function(app)
    local spec, current, store, listeners = nil, nil, nil, {}
    local function validate(state)
        assert(type(state) == 'table' and type(state.values) == 'table', 'adapter must supply values')
        assert(state.readOnly == nil or type(state.readOnly) == 'boolean', 'invalid readOnly')
        for path, field in pairs(spec.fields) do assert(fieldValid(I.get(state.values, path), field), 'invalid field: ' .. path) end
        return I.copy(state)
    end
    local function savedCopy(saved)
        assert(type(saved) == 'table', 'adapter must supply saved globals')
        local result = {}
        for _, name in ipairs(spec.savedVariables) do assert(saved[name] ~= nil, 'missing saved global: ' .. name); result[name] = I.copy(saved[name]) end
        for name in pairs(saved) do assert(result[name] ~= nil, 'undeclared saved global: ' .. tostring(name)) end
        return result
    end
    local function publish(state, saved)
        current = state
        store._values = I.copy(state.values)
        store._context = { activeProfile = state.activeProfile, readOnly = state.readOnly == true, needsCharacter = state.needsCharacter == true }
        if saved then for _, name in ipairs(spec.savedVariables) do _G[name] = saved[name] end end
    end
    function app:Settings(declaration)
        assert(not spec and not self._ready, 'declare settings once before readiness')
        assert(type(declaration.adapter) == 'table' and type(declaration.adapter.Restore) == 'function' and type(declaration.adapter.Prepare) == 'function', 'settings adapter required')
        spec = { adapter = declaration.adapter, fields = I.copy(declaration.fields), savedVariables = I.copy(declaration.savedVariables) }
        assert(#spec.savedVariables > 0, 'declare saved globals')
        local names = {}
        for _, name in ipairs(spec.savedVariables) do assert(type(name) == 'string' and name:match('^[%a_][%w_]*$') and not names[name], 'invalid saved name'); names[name] = true end
        for path, field in pairs(spec.fields) do
            assert(type(path) == 'string' and path:match('^[%w_]+[.%w_]*$') and not path:find('..',1,true) and path:sub(-1) ~= '.', 'invalid setting path')
            assert(types[field.type] and fieldValid(field.default, field), 'invalid field declaration: ' .. path)
            for other in pairs(spec.fields) do assert(other == path or other:sub(1,#path+1) ~= path .. '.', 'overlapping field paths') end
        end
        store = I.store(self, {}); self._settingsFields = spec.fields; self._settingsStore = store
    end
    function app:_restore()
        if not spec then return true end
        local ok, state, saved = I.lock(self, function()
            local restored = {}
            for _, name in ipairs(spec.savedVariables) do restored[name] = _G[name] end
            -- Saved globals may contain future/legacy data: adapter owns its interpretation.
            local nextState, normalized = spec.adapter:Restore(I.copy(restored), I.copy(spec.fields))
            if not nextState then error(type(normalized) == 'table' and normalized.message or normalized or 'restore failed') end
            nextState = validate(nextState)
            return nextState, not nextState.readOnly and savedCopy(normalized) or nil
        end)
        if not ok then return false, I.error('restore', tostring(state)) end
        publish(state, saved); return true
    end
    function app:Get(path)
        assert(self._ready and store and spec.fields[path], 'unknown field or settings not ready')
        return I.copy(I.get(current.values, path))
    end
    function app:SelectSettings(project) assert(store, 'declare settings first'); return store:Select(project) end
    function app:OnSettingsChanged(callback)
        assert(type(callback) == 'function', 'callback required')
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
            local prepared, err = spec.adapter:Prepare(I.copy(current), I.copy(operation), I.copy(spec.fields))
            if not prepared then return nil, err end
            local state = validate(prepared.state)
            return { state = state, saved = not state.readOnly and savedCopy(prepared.saved) or nil }
        end)
        if not ok then return false, I.error('invalid', tostring(candidate)) end
        if not candidate then return false, type(failure) == 'table' and failure or I.error('rejected', failure) end
        if I.equal(current, candidate.state) then return true end
        local keys = {}
        for path in pairs(spec.fields) do if not I.equal(I.get(current.values,path), I.get(candidate.state.values,path)) then keys[path] = true end end
        local profileChanged = current.activeProfile ~= candidate.state.activeProfile or operation.kind == 'bind'
        -- Candidate is fully valid before any editor cleanup or publication.
        if app._panel then I.lock(app,function()app._panel:_cancelEditors(operation.kind == 'set')end) end
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
        if not spec or not spec.fields[path] then return false, I.error('unknownField') end
        local ok, valid = pcall(fieldValid, value, spec.fields[path])
        if not ok or not valid then return false, I.error('invalid') end
        return commit({ kind='set', path=path, value=value }, revision)
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
            local capabilities = current and current.profiles or {}
            if not (capabilities.operations and capabilities.operations[operation]) then return false, I.error('unsupported') end
            return commit({ kind=operation, name=operation ~= 'bind' and value or nil, identity=operation == 'bind' and value or nil })
        end
    end
end
