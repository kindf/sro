local skynet = require "skynet"
local ServiceLauncher = require "common.service_launcher"

local function startWatchdog()
    local port = skynet.getenv("gateport")
    local maxclient = skynet.getenv("maxclient")
    ServiceLauncher.Start("watchdog_service", {
        port = port,
        maxclient = maxclient,
        nodelay = true,
    })
end

local function start()
    -- 配置服务
    -- ServiceLauncher.Start("config_service")
    -- 世界服务
    ServiceLauncher.Start("world_service")
    -- 场景服务
    ServiceLauncher.Start("scene_service")
    -- 网关服务
    startWatchdog()
end

local traceback = debug.traceback
skynet.start(function()
    local ok, err = xpcall(start, traceback)
    if not ok then
        skynet.error(string.format("game start failed. err:%s", err))
        skynet.sleep(100)
        skynet.abort()
    end
    skynet.register(".game")
end)