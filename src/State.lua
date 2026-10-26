local _, ns = ...
local SND = ns.SomethingNeedDoing; local I = SND._
function I.store(app, initial, validate)
    local state = { _app = app, _values = I.copy(initial), _revision = 0, _watchers = {}, _validate = validate }
    assert(type(initial) == 'table', 'state root must be a table')
    function state:Read() assert(not app._disposed, 'app disposed'); return I.copy(self._values), self._revision end
    function state:Select(project) assert(type(project) == 'function', 'selector required'); return { _store = self, _project = project } end
    function state:_notify()
        for _, h in ipairs(I.snapshot(self._watchers)) do if h.active then h._deliver() end end
    end
    function state:Update(mutator, expectedRevision)
        assert(type(mutator) == 'function', 'mutator required')
        if app._disposed then return false, I.error('disposed') end
        if app._locked then return false, I.error('reentrant') end
        if expectedRevision ~= nil and expectedRevision ~= self._revision then return false, I.error('stale') end
        local ok, candidate, reason = I.lock(app, function()
            local draft = I.copy(self._values)
            local accepted, err = mutator(draft)
            if accepted == false then return nil, err or I.error('rejected') end
            draft = I.copy(draft)
            if validate then
                local valid, validationError = validate(I.copy(draft))
                if not valid then return nil, validationError or I.error('invalid') end
            end
            return draft
        end)
        if not ok then return false, I.error('invalid', tostring(candidate)) end
        if not candidate then return false, type(reason) == 'table' and reason or I.error('invalid', reason) end
        if I.equal(candidate, self._values) then return true end
        self._values = candidate; self._revision = self._revision + 1
        I.lock(app, function() self:_notify() end)
        return true
    end
    if validate then
        local ok, accepted = I.lock(app, validate, I.copy(initial)); assert(ok and accepted, 'invalid initial state')
    end
    app._stores[state] = true
    return state
end
function I.watch(scope, selection, callback)
    assert(scope.active and type(callback) == 'function' and selection._store and selection._store._app == scope._app, 'invalid watch owner/selection')
    local app, state, project = scope._app, selection._store, selection._project
    local previous, initialized, h
    h = I.handle(scope, function()
        app._pending[h] = nil; state._watchers[h] = nil; h._start = nil; h._deliver = nil
        callback, project, previous = nil, nil, nil
    end)
    app._order = app._order + 1; h._order = app._order
    h._deliver = function()
        local ok, value = I.lock(app, function()
            return I.copy(project(I.copy(state._values), state._context and I.copy(state._context)))
        end)
        if not ok then I.report(app, value); return end
        if not h.active then return end
        if initialized and I.equal(previous, value) then return end
        local old = previous; previous, initialized = I.copy(value), true
        local delivered, err = I.lock(app, callback, I.copy(value), I.copy(old), state._revision)
        if not delivered then I.report(app, err) end
    end
    I.activate(app, h, function() state._watchers[h] = true; h._deliver() end)
    return h
end
SND._install[#SND._install + 1] = function(app)
    function app:State(initial, spec) return I.store(self, initial, spec and spec.validate) end
end
