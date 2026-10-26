local _, ns = ...
local SND = ns.SomethingNeedDoing; local I, V = SND._, SND.Values
SND._install[#SND._install + 1] = function(app)
    local records, threshold = {}, 2
    local levels = { Debug = 1, Info = 2, Warn = 3, Error = 4 }
    local log = {}; app.log = log
    for name, priority in pairs(levels) do
        local level, rank = name, priority
        log[level] = function(_, message, fields)
            if rank < threshold then return end
            if not V.Readable(message) or type(message) ~= 'string' then message = 'Unreadable diagnostic' end
            local context, count, examined = {}, 0, 0
            if V.Readable(fields) and type(fields) == 'table' then
                for k, v in pairs(fields) do
                    examined = examined + 1
                    if count == 16 or examined > 64 then break end
                    if V.Readable(k) and type(k) == 'string' and V.Readable(v) and
                        (type(v) == 'string' or type(v) == 'boolean' or V.Number(v)) then
                        context[k:sub(1,64)] = type(v) == 'string' and v:sub(1,256) or v; count = count + 1
                    end
                end
            end
            message = message:sub(1,1024)
            local last = records[#records]
            if last and last.level == level and last.message == message and I.equal(last.fields, context) then
                last.count = math.min(last.count + 1, 2147483647); return
            end
            records[#records + 1] = { level = level, message = message, fields = context, count = 1 }
            if #records > 200 then table.remove(records, 1) end
        end
    end
    function log:Entries() return I.copy(records) end
    function log:Clear() records = {} end
    function log:SetLevel(level) I.check(levels[level], 'unknown log level'); threshold = levels[level] end
end
