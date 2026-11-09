-- service/game/config_probe_service.lua
-- 配置层验收探针：读取场景表、遍历、报告本服务内存增量。

local skynet = require "skynet"
local ConfigRepository = require "common.config_repository"

local PROBE_TABLE = "tbscenetable"

-- 服务参数由 main chunk 的 ... 传入
local tag = ...

skynet.start(function()
    local startTicks = skynet.now()
    local memBefore = collectgarbage("count")

    local sceneTable = ConfigRepository.Get(PROBE_TABLE)

    local rowCount = 0
    for _, row in pairs(sceneTable) do
        if row.SceneType ~= nil then
            rowCount = rowCount + 1
        end
    end

    local memAfter = collectgarbage("count")
    skynet.error(("probe[%s] %s rows=%d mem=%.1fMB delta=+%.2fMB time=%dms"):format(
        tag, PROBE_TABLE, rowCount, memAfter / 1024,
        (memAfter - memBefore) / 1024, (skynet.now() - startTicks) * 10))

    skynet.exit()
end)
