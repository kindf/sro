-- lualib/config/config_manager.lua
-- 配置表发布逻辑：把 gamedata/generated 下的表发布到 sharedata。

local skynet = require "skynet"
local sharedata = require "skynet.sharedata"

-- sharedata 键前缀；业务侧通过 config_repository 读取
local CONFIG_PREFIX = "config."
-- 表文件名清单的 sharedata 键
local CONFIG_FILES_KEY = "config.allconfigfiles"
-- 表文件名清单模块
local CONFIG_FILES_MODULE = "gamedata.generated.allconfigfiles"

local ConfigManager = {}

local publishedCount = 0

-- 加载并发布一张表。
-- 参数 file: 表文件名，例如 "tbscenetable"。
-- 返回：成功 true；失败 false, 错误信息。
local function publishTable(file)
    local moduleName = "gamedata.generated." .. file
    local ok, data = pcall(require, moduleName)
    if not ok then
        return false, ("加载 %s 失败: %s"):format(file, tostring(data))
    end

    local published, err = pcall(sharedata.new, CONFIG_PREFIX .. file, data)
    -- require 会缓存模块；发布后清掉，避免本服务继续持有整张表
    package.loaded[moduleName] = nil
    data = nil

    if not published then
        return false, ("发布 %s 失败: %s"):format(file, tostring(err))
    end

    publishedCount = publishedCount + 1
    return true
end

-- 发布全部配置表。
-- 返回：成功 true, 已发布数量；失败 false, 错误信息。
function ConfigManager.PublishAll()
    local files = require(CONFIG_FILES_MODULE)
    local total = #files
    local errors = {}

    publishedCount = 0

    for i, file in ipairs(files) do
        local ok, err = publishTable(file)
        if not ok then
            errors[#errors + 1] = err
        end

        if i % 20 == 0 then
            collectgarbage()
        end
        if i % 50 == 0 then
            skynet.error(("config_manager: %d/%d"):format(i, total))
        end
    end

    local ok, err = pcall(sharedata.new, CONFIG_FILES_KEY, files)
    if not ok then
        errors[#errors + 1] = ("发布 %s 失败: %s"):format(CONFIG_FILES_KEY, tostring(err))
    end

    if #errors > 0 then
        return false, ("%d 张表发布失败，首个: %s"):format(#errors, errors[1])
    end
    return true, publishedCount
end

-- 获取已发布的表数量。
function ConfigManager.GetPublishedCount()
    return publishedCount
end

return ConfigManager
