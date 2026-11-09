-- service/game/config_test_service.lua
-- 配置层验收节点：启动 config_service，再起两个探针。

local skynet = require "skynet"
local ServiceLauncher = require "common.service_launcher"

-- 等待探针完成的 tick 数（100 tick = 1 秒）
local TEST_TIMEOUT_TICKS = 300

skynet.start(function()
    local configAddress, tableCount = ServiceLauncher.Start("config_service")
    skynet.error(("config_test: config_service ready, tables=%d, addr=%s"):format(
        tableCount, tostring(configAddress)))

    skynet.newservice("config_probe_service", "A")
    skynet.newservice("config_probe_service", "B")

    skynet.timeout(TEST_TIMEOUT_TICKS, function()
        skynet.error("config_test: done")
        skynet.exit()
    end)
end)
