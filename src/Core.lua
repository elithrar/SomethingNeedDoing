local _, ns = ...
assert(type(ns) == "table" and ns.SomethingNeedDoing == nil, "SND must load once into the consumer namespace")
local SND = { VERSION = "0.4.0", Values = {}, Pages = {}, _install = {} }
ns.SomethingNeedDoing = SND
local I = {}; SND._ = I
local V = SND.Values
function V.Readable(value)
    if not issecretvalue then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end
function V.Number(value)
    return V.Readable(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
-- Errors never invoke consumer metamethods or retain consumer-owned error tables.
function I.error(code, detail)
    local message
    if V.Readable(detail) and type(detail) == 'table' then
        local suppliedCode, suppliedMessage = rawget(detail, 'code'), rawget(detail, 'message')
        if V.Readable(suppliedCode) and type(suppliedCode) == 'string' and suppliedCode:match('^[%w_]+$') and #suppliedCode <= 64 then code = suppliedCode end
        if V.Readable(suppliedMessage) and type(suppliedMessage) == 'string' then message = suppliedMessage end
    elseif V.Readable(detail) and type(detail) == 'string' then message = detail end
    return { code = code, message = (message or code):sub(1, 1024) }
end
function I.check(condition, message)
    if not condition then error('SND: ' .. message, 3) end
    return condition
end
function I.plain(value)
    return V.Readable(value) and type(value) == 'table' and getmetatable(value) == nil
end
function I.array(value, label, nonempty)
    I.check(I.plain(value), label .. ' must be a plain dense array')
    local count, maximum = 0, 0
    for key in pairs(value) do
        I.check(V.Number(key) and key >= 1 and key == math.floor(key), label .. ' must use consecutive integer keys starting at 1')
        count = count + 1; maximum = math.max(maximum, key)
    end
    I.check(count == maximum and (not nonempty or count > 0), label .. ' must be dense' .. (nonempty and ' and nonempty' or ''))
    return count
end
function I.revision(value)
    return value == nil or (V.Number(value) and value >= 0 and value == math.floor(value))
end
function I.copy(value, seen, depth, budget, functions)
    I.check(V.Readable(value), "restricted value")
    local kind = type(value)
    if kind ~= "table" then
        I.check((functions and kind == "function") or kind == "nil" or kind == "boolean" or kind == "string" or (kind == "number" and V.Number(value)), "plain data required")
        return value
    end
    depth, budget, seen = (depth or 0) + 1, budget or { n = 0 }, seen or {}
    I.check(depth <= 32 and not seen[value] and getmetatable(value) == nil, "invalid state tree")
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        budget.n = budget.n + 1
        I.check(budget.n <= 20000, "state tree exceeds 20000 entries")
        I.check(V.Readable(key) and (type(key) == "string" or (V.Number(key) and key == math.floor(key))), "invalid state key")
        out[key] = I.copy(child, seen, depth, budget, functions)
    end
    seen[value] = nil
    return out
end
function I.definition(value) return I.copy(value, nil, nil, nil, true) end
function I.equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not I.equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function I.get(t, path)
    for key in path:gmatch('[^.]+') do if type(t) ~= 'table' then return nil end; t = t[key] end
    return t
end
function I.report(app, err)
    local message = I.error('callback', err).message
    if app.log then app.log:Error(message) end
    if geterrorhandler then local ok, handler = pcall(geterrorhandler); if ok and handler then pcall(handler, message) end end
end
local function pack(...) return { n = select("#", ...), ... } end
function I.call(app, fn, ...)
    local result = pack(pcall(fn, ...))
    if not result[1] then I.report(app, result[2]) end
    return unpack(result, 1, result.n)
end
function I.lock(app, fn, ...)
    local old = app._locked; app._locked = true
    local result = pack(pcall(fn, ...)); app._locked = old
    return unpack(result, 1, result.n)
end
function I.handle(owner, cancel)
    local h = { active = true }
    local app = owner and (owner._app or owner)
    if app and app._order then app._order = app._order + 1; h._order = app._order end
    function h:Cancel()
        if not self.active then return end
        self.active = false
        if owner then owner._handles[self] = nil end
        local cleanup = cancel; cancel = nil
        if cleanup then if app then I.call(app, cleanup) else cleanup() end end
    end
    if owner then owner._handles[h] = true end
    return h
end
function I.snapshot(set)
    local out = {}; for h in pairs(set) do out[#out + 1] = h end
    table.sort(out, function(a,b) return (a._order or 0) < (b._order or 0) end)
    return out
end
function I.activate(app, h, fn)
    h._start = fn
    if app._ready then h._start = nil; if h.active then fn() end
    else app._pending[h] = true end
end
local apps = {}
function SND:NewAddon(name, spec)
    I.check(type(name) == 'string' and name:match('^[%w_%-]+$') and not apps[name], 'invalid or duplicate addon name')
    I.check(spec == nil or I.plain(spec), 'NewAddon spec must be a plain table')
    I.check(not spec or spec.version==nil or type(spec.version)=='string', 'version must be a string')
    I.check(CreateFrame, 'SND requires WoW frame APIs')
    local app = { name = name, version = (spec or {}).version, _pending = {}, _scopes = {}, _handles = {}, _order = 0, _stores = {} }
    apps[name] = app
    local frame = CreateFrame('Frame'); app._frame = frame
    frame:RegisterEvent('ADDON_LOADED'); frame:RegisterEvent('PLAYER_LOGOUT')
    function app:IsReady() return self._ready == true end
    function app:OnReady(callback)
        I.check(type(callback) == 'function' and not self._disposed, 'invalid ready callback')
        local h
        h = I.handle(self, function() self._pending[h] = nil; h._start = nil; callback = nil end)
        if self._ready then
            self._system:After(0, h, function() if h.active then local fn = callback; h:Cancel(); I.call(self, fn, self) end end)
        else
            self._pending[h] = true
            h._start = function() local fn = callback; h:Cancel(); I.call(self, fn, self) end
        end
        return h
    end
    function app:_boot()
        if self._ready or self._disposed then return end
        if self._restore then
            local ok, err = self:_restore()
            if not ok then I.report(self, err.message); return end
        end
        self._ready = true
        -- Ready callbacks and owned subscriptions activate in registration order.
        local pending = I.snapshot(self._pending)
        for _, h in ipairs(pending) do
            self._pending[h] = nil
            if h.active and h._start then local start = h._start; h._start = nil; I.call(self, start) end
        end
    end
    function app:_dispose()
        if self._disposed then return end
        self._disposed = true; self._ready = false
        if self._panel then I.call(self, self._panel.Close, self._panel) end
        for _, scope in pairs(self._scopes) do scope:Cancel() end
        for _, h in ipairs(I.snapshot(self._handles)) do h:Cancel() end
        self._pending = {}; self._stores = {}
        frame:UnregisterAllEvents(); frame:SetScript('OnUpdate', nil)
    end
    frame:SetScript('OnEvent', function(_, event, ...)
        if event == 'PLAYER_LOGOUT' then
            if app._stopping or app._disposed then return end
            app._stopping = true
            -- Checkpoints observe committed state before scopes and editors are disposed.
            if app._dispatchEvent then app:_dispatchEvent(event, ...) end
            app:_dispose()
            return
        end
        if event == 'ADDON_LOADED' and (...) == name then app:_boot() end
        if app._dispatchEvent then app:_dispatchEvent(event, ...) end
    end)
    for _, install in ipairs(self._install) do install(app) end
    app._system = app:Scope('_snd')
    return app
end
