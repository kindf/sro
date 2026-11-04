local ConfigHelper = {}
local classImplMap = {}

function ConfigHelper.RegisterConfigClass(type, c)
    classImplMap[type] = c.new()
end


function ConfigHelper.GetConfigClass(config)
    local name = config._type_
    assert(classImplMap[name], "配置类不存在 name: " .. name)
    return classImplMap[name]
end

return ConfigHelper
