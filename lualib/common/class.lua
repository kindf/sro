
local setmetatable = setmetatable
local getmetatable = getmetatable

_class = _class or {}
_tname = _tname or {}
_weakMeta = _weakMeta or {__mode = 'k'}

local _class = _class
local _tname = _tname
local _weakMeta = _weakMeta

_objectLeak = _objectLeak or {}
setmetatable(_objectLeak, _weakMeta)
local _objectLeak = _objectLeak

local function __pairs(t)
    local function itr(t, idx)
        local v
        while true do
            repeat
                idx, v = next(t, idx)
                if(type(idx) == 'string' and string.byte(idx) ==95)then
                    break
                end
                return idx,v
            until true
        end
    end
    return itr, t, nil
end

local function class(name, parent)
    assert(type(name) == 'string')
    local template = _class[name]
    if not template then
        local parentTemplate
        if parent then
            assert(_tname[parent], parent)
            parentTemplate = parent
        end
        template = {}
        template.__index = template
        template.__pairs = __pairs
        template._classname_ = name
        template.__gc = function (inst)
            if(inst.OnDestroy)then
                inst:OnDestroy()
            end
        end
        template.Bind = function(inst,...)
            local o = setmetatable(inst, template)
            if(o.OnBind)then
                o:OnBind(...)
            end
            return o
        end
        template.GetClassName = function() return name end
        template.GetSuper = function() return parentTemplate end

        local meta = {
            __call = function(...)
                --assert(tlt == template)
                local o = {}
                setmetatable(o, template)
                if(o.Ctor)then o.Ctor(o, ...) end
                _objectLeak[o] = true
                return o
            end,
            __index = parentTemplate
        }
        template.new = meta.__call
        
        meta.__call = nil
        setmetatable(template, meta)
        _class[name] = template
        _tname[template] = name
    end
    return template
end

function getClassName(t)
    if _tname[t] then
        return _tname[t]
    end
    local meta = getmetatable(t)
    return meta and _tname[meta.__index]
end

function getClass(nm)
    return _class[nm]
end

function getLeakObjs()
    return _objectLeak
end

function findObject(obj,findDest,findedObjMap)
    if not findDest then
        return false
    end
    if findedObjMap[findDest] then
        return false
    end
    findedObjMap[findDest] = true
    local destType = type(findDest)
    if destType == "table" then
        for key, value in pairs(findDest) do
            if key == obj or value == obj then
                print("Finded Object",key,value)
                return true
            end
            if findObject(obj, key,findedObjMap) == true then
                print("table key:",key)
                if type(key) == "table" then
                    --tprint(key,3)
                end
                return true
            end
            if findObject(obj, value,findedObjMap) == true then
                print("table value - key:",value)
                return true
            end
        end
        local metaTable = getmetatable(findDest)
        if metaTable and findObject(obj,metaTable,findedObjMap) == true then

            print("tablemetable")
            if type(metaTable) == "table" then
                --tprint(metaTable,3)
            end
        end

    elseif destType == "function" then
        local uvIndex = 1
        while true do
            local name, value = debug.getupvalue(findDest, uvIndex)
            if name == nil then
                break
            end
            if value and findObject(obj, value,findedObjMap) == true then
                print("upvalue name:["..tostring(name).."]")
                if getClassName(value) then
                    print(getClassName(value))
                end
                return true
            end
            uvIndex = uvIndex + 1
        end
        local fenv = getfenv(findDest)
        if fenv and findObject(obj,fenv,findedObjMap)  == true then
            print("fenv.finded")
            if type(fenv) == "table" then
                --tprint(fenv,3)
            end
            return true
        end

    elseif destType == "thread" then
        local fenv = getfenv(0)
        if fenv and findObject(obj,fenv,findedObjMap) == true then
            print("thread.fenv.finded")
            if type(fenv) == "table" then
                --tprint(fenv,3)
            end
            return true
        end
        local metaTable = getmetatable(0)
        if metaTable and findObject(obj,metaTable,findedObjMap) == true then
            print("thread.metaTable.finded")
            if type(metaTable) == "table" then
                --tprint(metaTable,3)
            end
            return true
        end
    elseif destType == "userdata" then
        local fenv = getfenv(1)
        if fenv and findObject(obj,fenv,findedObjMap) == true then
            print("userdata.fenv.finded")
            if type(fenv) == "table" then
                --tprint(fenv,3)
            end
            return true
        end
        local metaTable = getmetatable(findDest)
        if metaTable and findObject(obj,metaTable,findedObjMap) == true then
            print("userdata.metaTable.finded")
            if type(metaTable) == "table" then
                --tprint(metaTable,3)
            end
            return true
        end
    end
    return false
end

return class