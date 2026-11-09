-- service/game/config_service.lua
-- 配置表发布服务入口。
--
-- 启动约定：
--   1. 调用方 newservice("config_service")
--   2. 调用方 call(addr, "lua", "start")，根据返回值判断是否成功
--   3. 失败则由调用方 abort skynet

local skynet = require "skynet"
local ConfigManager = require "config.config_manager"

local CMD = {}

local started = false

-- 启动配置服务：发布全部配置表。
-- 返回：成功 true, 表数量；失败 false, 错误信息。
function CMD.start()
    if started then
        return true, ConfigManager.GetPublishedCount()
    end

    local startTicks = skynet.now()
    local ok, result = ConfigManager.PublishAll()
    if not ok then
        return false, result
    end

    started = true
    collectgarbage()

    skynet.error(("config_service: 发布 %d 张表，耗时 %d ms"):format(
        result, (skynet.now() - startTicks) * 10))
    return true, result
end

-- 健康检查。
-- 返回：true。
function CMD.ping()
    return true
end

-- 获取已发布的表数量。
-- 返回：number。
function CMD.get_count()
    return ConfigManager.GetPublishedCount()
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, ...)
        local handler = CMD[cmd]
        if handler == nil then
            skynet.ret(skynet.pack(false))
            return
        end
        skynet.ret(skynet.pack(handler(...)))
    end)
end)
