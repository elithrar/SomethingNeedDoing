-- Offline design model, NOT a vendorable SND runtime. Lua 5.1.
-- Deliberately omits WoW lifecycle, persistence, diagnostics and UI adapters.
local Model = {}
local function copy(value, seen)
    if type(value) ~= "table" then
        assert(type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread", "plain data only")
        assert(type(value) ~= "number" or (value == value and math.abs(value) < math.huge), "finite numbers only")
        return value
    end
    assert(getmetatable(value) == nil, "plain tables only")
    seen = seen or {}; assert(not seen[value], "cycles unsupported"); seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        assert(type(key) == "string" or (type(key) == "number" and key == math.floor(key)), "invalid key")
        result[key] = copy(child, seen)
    end
    seen[value] = nil
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
Model.copy, Model.equal = copy, equal
local dispatching = false
local function compact(watches)
    for i = #watches, 1, -1 do
        if not watches[i].active then table.remove(watches, i) end
    end
end
function Model.State(initial, spec)
    spec = spec or {}
    local values, revision, watches = copy(initial), 0, {}
    if spec.validate then assert(spec.validate(copy(values))) end
    local state = {}
    function state:Read() return copy(values), revision end
    function state:Select(project)
        return { state = self, project = project, watches = watches }
    end
    function state:Update(mutate, expectedRevision)
        if dispatching then return false, "reentrant" end
        if expectedRevision ~= nil and expectedRevision ~= revision then return false, "stale" end
        local candidate = copy(values)
        dispatching = true
        local ok, err = pcall(function()
            local accepted, reason = mutate(candidate)
            if accepted == false then error(reason or "rejected") end
            candidate = copy(candidate) -- A retained draft cannot mutate a commit.
            if spec.validate then
                local valid, reason = spec.validate(copy(candidate))
                if not valid then error(reason or "invalid") end
            end
        end)
        dispatching = false
        if not ok then return false, err end
        if equal(values, candidate) then return true end
        values, revision = candidate, revision + 1
        dispatching = true
        local count = #watches
        for i = 1, count do
            local watch = watches[i]
            if watch.active then watch.deliver() end
        end
        dispatching = false
        compact(watches)
        return true
    end
    return state
end
function Model.Scope()
    local scope = { active = true, subscriptions = {}, errors = {} }
    function scope:Watch(selection, callback)
        assert(self.active, "scope canceled")
        local watch = { active = true }
        local initialized, previous = false, nil
        function watch.deliver()
            local snapshot, revision = selection.state:Read()
            local ok, selected = pcall(function() return copy(selection.project(snapshot)) end)
            if not ok then self.errors[#self.errors + 1] = selected; return end
            if initialized and equal(previous, selected) then return end
            local old = copy(previous)
            previous, initialized = copy(selected), true
            local delivered, err = pcall(callback, copy(selected), old, revision)
            if not delivered then self.errors[#self.errors + 1] = err end
        end
        -- Use tombstones during dispatch so cancellation cannot shift dispatch indexes.
        function watch:Cancel()
            self.active = false
            self.deliver = nil
            if not dispatching then compact(selection.watches) end
        end
        selection.watches[#selection.watches + 1] = watch
        self.subscriptions[#self.subscriptions + 1] = watch
        local wasDispatching = dispatching; dispatching = true
        watch.deliver(); dispatching = wasDispatching
        return watch
    end
    function scope:Cancel()
        self.active = false
        for _, watch in ipairs(self.subscriptions) do watch:Cancel() end
        self.subscriptions = {}
    end
    return scope
end
return Model
