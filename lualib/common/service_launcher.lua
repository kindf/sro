-- lualib/common/service_launcher.lua
-- 统一的服务启动流程。
--
-- 约定：
--   1. newservice(name) 启动服务
--   2. call(addr, "lua", "start")，根据返回值判断是否成功
--   3. 失败则 abort 整个 skynet 节点

local skynet = require "skynet"
require "skynet.manager" -- import skynet.abort

local ServiceLauncher = {}

-- 启动服务并等待其 start 成功。
-- 参数 name: 服务脚本名，例如 "config_service"。
-- 参数 ...: 传给服务 main chunk 的参数。
-- 返回：成功 addr, start 返回值；失败 nil（并 abort）。
function ServiceLauncher.Start(name, ...)
    local addr = skynet.newservice(name)
    local ok, result = skynet.call(addr, "lua", "start", ...)

    if not ok then
        skynet.error(("service_launcher: %s 启动失败: %s"):format(name, tostring(result)))
        skynet.abort()
        return nil
    end

    return addr, result
end

return ServiceLauncher
