-- Runnable minimal single-settings adapter. Existing addons retain their own schema migrations.
-- Pass this module a unique TOC SavedVariables name; do not share it between consumers.
local _, ns = ...
function ns.CreateSettingsAdapter(global)
local function put(t,path,value)
    local keys={};for key in path:gmatch('[^.]+')do keys[#keys+1]=key end
    for i=1,#keys-1 do
        local key=keys[i]
        if t[key]==nil then t[key]={} end
        t=t[key]
        if type(t)~='table' then return false end
    end
    t[keys[#keys]]=value
    return true
end
local function get(t,path)
    for key in path:gmatch('[^.]+')do if type(t)~='table'then return nil end;t=t[key]end
    return t
end
local function writable(values,metadata)
    local db={version=1,values=values}
    for key,value in pairs(metadata or {})do db[key]=value end
    return true,{state={values=values,metadata=metadata,profiles={operations={reset=true}}},saved={[global]=db}}
end
local Adapter={}
function Adapter:Restore(saved,fields)
    local db=saved[global]
    if db~=nil and (type(db)~='table' or db.version~=1)then
        local defaults={};for path,field in pairs(fields)do put(defaults,path,field.default)end
        return true, {state={values=defaults,readOnly=true,profiles={operations={}}}}
    end
    db=db or {version=1,values={}}
    if type(db.values)~='table'then return false,{code='invalid',message='Saved settings require a values table'}end
    -- SND supplies isolated saved globals, state, operations and field declarations.
    -- Keep only sibling metadata in opaque state, without duplicating the values tree.
    local metadata={}
    for key,value in pairs(db)do
        if key~='version' and key~='values' then metadata[key]=value end
    end
    -- New fields get defaults; existing values still pass SND's declared validation.
    for path,field in pairs(fields)do
        if get(db.values,path)==nil and not put(db.values,path,field.default) then
            return false,{code='invalid',message='Invalid saved parent for field: '..path}
        end
    end
    return writable(db.values,next(metadata) and metadata or nil)
end
function Adapter:Prepare(state,operation,fields)
    local values=state.values
    if operation.kind=='set'then put(values,operation.path,operation.value)
    elseif operation.kind=='patch'then for path,value in pairs(operation.values)do put(values,path,value)end
    elseif operation.kind=='reset'then for path,field in pairs(fields)do put(values,path,field.default)end
    else return false,{code='unsupported'}end
    return writable(values,state.metadata)
end
return Adapter
end
