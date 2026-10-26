local _, ns = ...
local SND = ns.SomethingNeedDoing; local I = SND._
function I.store(app, initial, validate)
    local state = { _app = app, _values = I.copy(initial), _revision = 0, _watchers = {}, _validate = validate }
    I.check(type(initial) == 'table', 'state root must be a table')
    function state:Read() I.check(not app._disposed, 'app disposed'); return I.copy(self._values), self._revision end
    function state:Select(project) I.check(type(project) == 'function', 'selector required'); return { _store = self, _project = project } end
    function state:_notify()
        for _, h in ipairs(I.snapshot(self._watchers)) do if h.active then h._deliver() end end
    end
    function state:Update(mutator, expectedRevision)
        I.check(type(mutator) == 'function', 'mutator required')
        I.check(I.revision(expectedRevision), 'expectedRevision must be a nonnegative integer')
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
                if valid ~= true then return nil, validationError or I.error('invalid') end
            end
            return draft
        end)
        if not ok then return false, I.error('invalid', candidate) end
        if not candidate then return false, I.error('invalid', reason) end
        if I.equal(candidate, self._values) then return true end
        self._values = candidate; self._revision = self._revision + 1
        I.lock(app, function() self:_notify() end)
        return true
    end
    if validate then
        local ok, accepted = I.lock(app, validate, I.copy(initial)); I.check(ok and accepted == true, 'invalid initial state')
    end
    app._stores[state] = true
    return state
end
function I.watch(scope, selection, callback)
    I.check(scope.active and type(callback) == 'function' and I.plain(selection) and type(selection._store) == 'table' and selection._store._app == scope._app, 'invalid watch owner/selection')
    local app, state, project = scope._app, selection._store, selection._project
    local previous, initialized, h
    h = I.handle(scope, function()
        app._pending[h] = nil; state._watchers[h] = nil; h._start = nil; h._deliver = nil
        callback, project, previous = nil, nil, nil
    end)
    app._order = app._order + 1; h._order = app._order
    h._deliver = function()
        local ok, value = I.lock(app, function()
            local selected = project(I.copy(state._values), state._context and I.copy(state._context))
            return I.copy(selected)
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
    function app:State(initial, spec)
        I.check(not self._disposed and not self._locked, 'cannot create state during notification or after disposal')
        I.check(spec == nil or I.plain(spec), 'State spec must be a plain table')
        I.check(not spec or spec.validate == nil or type(spec.validate) == 'function', 'validate must be a function')
        return I.store(self, initial, spec and spec.validate)
    end
end
