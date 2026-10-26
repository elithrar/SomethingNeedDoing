-- Runnable minimal single-settings adapter. Existing addons retain their own schema migrations.
-- Pass this module a unique TOC SavedVariables name; do not share it between consumers.
local _, ns = ...
function ns.CreateSettingsAdapter(global)
local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
local function put(t,path,value)
    local keys={};for key in path:gmatch('[^.]+')do keys[#keys+1]=key end
    for i=1,#keys-1 do t[keys[i]]=t[keys[i]]or{};t=t[keys[i]]end;t[keys[#keys]]=value
end
local Adapter={}
function Adapter:Restore(saved,fields)
    local defaults={};for path,field in pairs(fields)do put(defaults,path,copy(field.default))end
    local db=saved[global]
    if db and (type(db)~='table' or db.version~=1)then
        return {values=defaults,readOnly=true,profiles={operations={}}}
    end
    db=db or {version=1,values=defaults}
    return {values=copy(db.values),profiles={operations={reset=true}}},{[global]=copy(db)}
end
function Adapter:Prepare(state,operation,fields)
    local values=copy(state.values)
    if operation.kind=='set'then put(values,operation.path,copy(operation.value))
    elseif operation.kind=='reset'then values={};for path,field in pairs(fields)do put(values,path,copy(field.default))end
    else return nil,{code='unsupported'}end
    return {state={values=values,profiles={operations={reset=true}}},saved={[global]={version=1,values=copy(values)}}}
end
return Adapter
end
