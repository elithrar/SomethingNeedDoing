local _, ns = ...
local SND = ns.SomethingNeedDoing; local I, V = SND._, SND.Values
-- A bundled factory retains one inert native dispatcher per target, never subscribers after cancellation.
local hooks = setmetatable({}, { __mode = 'k' })
local globalHooks = {}
SND._install[#SND._install + 1] = function(app)
    local events, tasks = {}, {}
    local function schedule(scope, seconds, key, callback, repeating)
        assert(scope.active and type(callback) == 'function', 'invalid timer owner/callback')
        if not V.Number(seconds) or seconds < 0 or (repeating and seconds == 0) then return nil, I.error('invalid', 'invalid timer interval') end
        assert(key ~= nil, 'timer requires a key')
        if scope._timers[key] then scope._timers[key]:Cancel() end
        local h
        h = I.handle(scope, function() tasks[h] = nil; app._pending[h] = nil; h._start = nil; callback = nil
            if scope._timers[key] == h then scope._timers[key] = nil end
            if not next(tasks) and app._frame then app._frame:SetScript('OnUpdate', nil) end
        end)
        scope._timers[key] = h
        I.activate(app, h, function()
            tasks[h] = { remaining = seconds, elapsed = 0 }
            app._frame:SetScript('OnUpdate', function(_, elapsed)
                for _, timer in ipairs(I.snapshot(tasks)) do
                    local task = tasks[timer]
                    if task then
                        task.remaining = task.remaining - elapsed; task.elapsed = task.elapsed + elapsed
                        if task.remaining <= 0 then timer._fire(task) end
                    end
                end
            end)
        end)
        h._fire = function(task)
            if not h.active then return end
            local fn, elapsed = callback, task.elapsed
            if repeating then task.remaining = seconds; task.elapsed = 0 else h:Cancel() end
            I.call(app, fn, elapsed)
        end
        return h
    end
    function app:_dispatchEvent(event, ...)
        local entries = events[event]; if not entries or not self._ready then return end
        for _, h in ipairs(I.snapshot(entries)) do if h.active then I.call(self, h._callback, ...) end end
    end
    function app:Scope(name)
        assert(not self._disposed and (name == nil or not self._scopes[name]), 'scope name already active')
        local scope = { active = true, _handles = {}, _timers = {}, _app = self }
        local identity = name or scope; self._scopes[identity] = scope
        function scope:Cancel()
            if not self.active then return end
            self.active = false
            for _, h in ipairs(I.snapshot(self._handles)) do h:Cancel() end
            app._scopes[identity] = nil
        end
        function scope:Event(event, callback)
            assert(self.active and type(event) == 'string' and type(callback) == 'function', 'invalid event subscription')
            local h
            h = I.handle(self, function()
                app._pending[h] = nil; h._start = nil; h._callback = nil
                if events[event] then
                    events[event][h] = nil
                    if not next(events[event]) then
                        events[event] = nil
                        if event ~= 'ADDON_LOADED' and event ~= 'PLAYER_LOGOUT' then app._frame:UnregisterEvent(event) end
                    end
                end
            end)
            h._callback = callback; app._order = app._order + 1; h._order = app._order
            I.activate(app, h, function()
                local ok, err = pcall(app._frame.RegisterEvent, app._frame, event)
                if not ok then h:Cancel(); I.report(app, err); return end
                events[event] = events[event] or {}; events[event][h] = true
            end)
            return h
        end
        function scope:After(seconds, key, callback) return schedule(self, seconds, key, callback, false) end
        function scope:Every(seconds, key, callback) return schedule(self, seconds, key, callback, true) end
        function scope:Guard(callback)
            assert(self.active and type(callback) == 'function', 'invalid guard')
            I.handle(self, function() callback = nil end)
            return function(...) if callback and self.active and app._ready then I.call(app, callback, ...) end end
        end
        local function hook(owner, target, method, callback, script)
            assert(owner.active and type(callback) == 'function', 'invalid hook callback')
            if not target or (script and not target.HookScript) or (not script and type(target[method]) ~= 'function') then return nil, I.error('unavailable') end
            local map
            if target == _G then map = globalHooks else hooks[target] = hooks[target] or {}; map = hooks[target] end
            local key = (script and 'script:' or 'method:') .. method
            local dispatcher = map[key]
            if not dispatcher then
                dispatcher = {}; map[key] = dispatcher
                local function dispatch(...)
                    for _, sub in ipairs(I.snapshot(dispatcher)) do
                        if sub.active and sub._app._ready then I.call(sub._app, sub._callback, ...) end
                    end
                end
                local ok, err
                if script then ok, err = pcall(target.HookScript, target, method, dispatch)
                elseif hooksecurefunc then ok, err = pcall(hooksecurefunc, target, method, dispatch)
                else ok, err = false, 'hooksecurefunc unavailable' end
                if not ok then map[key] = nil; return nil, I.error('unavailable', err) end
            end
            local h
            h = I.handle(owner, function() dispatcher[h] = nil; h._callback = nil; h._app = nil end)
            app._order = app._order + 1; h._order = app._order
            h._callback, h._app = callback, app; dispatcher[h] = true
            return h
        end
        function scope:PostHook(target, method, callback)
            if type(target) == 'string' then callback, method, target = method, target, _G end
            return hook(self, target, method, callback, false)
        end
        function scope:HookScript(frame, script, callback) return hook(self, frame, script, callback, true) end
        function scope:Watch(selection, callback) return I.watch(self, selection, callback) end
        return scope
    end
    function app:Slash(command, callback)
        assert(type(command) == 'string' and command:match('^/[%w]+$') and type(callback) == 'function', 'invalid slash command')
        command = command:lower()
        for key, value in pairs(_G) do
            if type(key) == 'string' and key:match('^SLASH_.+%d+$') and type(value) == 'string' and value:lower() == command then return nil, I.error('collision') end
        end
        local id = self.name:gsub('[^%w]', '_'):upper() .. '_SND_' .. command:sub(2):upper()
        SlashCmdList = SlashCmdList or {}
        if SlashCmdList[id] then return nil, I.error('collision') end
        _G['SLASH_' .. id .. '1'] = command
        local handler = function(text) if self._ready then I.call(self, callback, text) end end
        SlashCmdList[id] = handler
        return I.handle(self, function()
            if SlashCmdList[id] == handler then SlashCmdList[id] = nil; _G['SLASH_' .. id .. '1'] = nil end
            callback = nil
        end)
    end
end
