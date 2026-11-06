-- gamedata/init.lua
-- 配置表访问入口。生成物格式：return { [id] = {Field=..., ...} }
--
-- 用法：
--   local GD = require "gamedata.init"
--   local Scene = GD.Get("SceneTable")
--   print(Scene[1].SceneType)

local M = {}

local cache = {}
local manifest = require "gamedata._manifest"
local info_by_name = {}

for _, info in ipairs(manifest) do
    info_by_name[info.name] = info
end

-- 按表名取数据；首次 require，之后走缓存。
function M.Get(name)
    local t = cache[name]
    if t == nil then
        local ok, mod = pcall(require, "gamedata." .. name)
        if not ok then
            error(("gamedata: 表 '%s' 加载失败: %s"):format(name, tostring(mod)), 2)
        end
        t = mod
        cache[name] = t
    end
    return t
end

-- 按主键取行；不存在返回 nil。
function M.GetRow(name, id)
    return M.Get(name)[id]
end

function M.Manifest()
    return manifest
end

function M.Info(name)
    return info_by_name[name]
end

function M.Count()
    return #manifest
end

function M.Each()
    local i = 0
    return function()
        i = i + 1
        return manifest[i]
    end
end

return M