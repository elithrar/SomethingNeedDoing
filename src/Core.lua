local _, ns = ...
assert(type(ns) == "table" and ns.SomethingNeedDoing == nil, "SND must load once into the consumer namespace")
local SND = { VERSION = "0.1.0", Values = {}, Pages = {}, _install = {} }
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
function I.error(code, message) return { code = code, message = message or code } end
function I.copy(value, seen, depth, budget)
    assert(V.Readable(value), "restricted value")
    local kind = type(value)
    if kind ~= "table" then
        assert(kind == "nil" or kind == "boolean" or kind == "string" or (kind == "number" and V.Number(value)), "plain data required")
        return value
    end
    depth, budget, seen = (depth or 0) + 1, budget or { n = 0 }, seen or {}
    assert(depth <= 32 and not seen[value] and getmetatable(value) == nil, "invalid state tree")
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        budget.n = budget.n + 1
        assert(budget.n <= 20000, "state tree exceeds 20000 entries")
        assert(V.Readable(key) and (type(key) == "string" or (V.Number(key) and key == math.floor(key))), "invalid state key")
        out[key] = I.copy(child, seen, depth, budget)
    end
    seen[value] = nil
    return out
end
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
function I.put(t, path, value)
    local keys = {}; for key in path:gmatch('[^.]+') do keys[#keys + 1] = key end
    for i = 1, #keys - 1 do t[keys[i]] = t[keys[i]] or {}; t = t[keys[i]] end
    t[keys[#keys]] = value
end
function I.report(app, err)
    local message = V.Readable(err) and type(err) == 'string' and err or 'SND callback failed'
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
        if cleanup then cleanup() end
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
    assert(type(name) == 'string' and name:match('^[%w_%-]+$') and not apps[name], 'invalid or duplicate addon name')
    assert(CreateFrame, 'SND requires WoW frame APIs')
    local app = { name = name, version = (spec or {}).version, _pending = {}, _scopes = {}, _handles = {}, _order = 0, _stores = {} }
    apps[name] = app
    local frame = CreateFrame('Frame'); app._frame = frame
    frame:RegisterEvent('ADDON_LOADED'); frame:RegisterEvent('PLAYER_LOGOUT')
    function app:IsReady() return self._ready == true end
    function app:OnReady(callback)
        assert(type(callback) == 'function' and not self._disposed, 'invalid ready callback')
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
        if self._panel then self._panel:Close() end
        self._disposed = true; self._ready = false
        for _, scope in pairs(self._scopes) do scope:Cancel() end
        for _, h in ipairs(I.snapshot(self._handles)) do h:Cancel() end
        self._pending = {}; self._stores = {}
        frame:UnregisterAllEvents(); frame:SetScript('OnUpdate', nil)
    end
    frame:SetScript('OnEvent', function(_, event, ...)
        if event == 'ADDON_LOADED' and (...) == name then app:_boot()
        elseif event == 'PLAYER_LOGOUT' then app:_dispose() end
        if app._dispatchEvent then app:_dispatchEvent(event, ...) end
    end)
    for _, install in ipairs(self._install) do install(app) end
    app._system = app:Scope('_snd')
    return app
end
