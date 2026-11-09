-- lualib/common/config_repository.lua
-- 配置表读取入口（sharedata 版）。

local sharedata = require "skynet.sharedata"

-- sharedata 键前缀，与 config_manager 保持一致
local CONFIG_PREFIX = "config."
-- 表文件名清单的 sharedata 键
local CONFIG_FILES_KEY = "config.allconfigfiles"

local ConfigRepository = {}

-- 获取一张配置表。
-- 参数 name: 表文件名，例如 "tbscenetable"。
-- 返回：只读代理表。
function ConfigRepository.Get(name)
    return sharedata.query(CONFIG_PREFIX .. name)
end

-- 获取全部表文件名。
-- 返回：文件名数组。
function ConfigRepository.GetFiles()
    return sharedata.query(CONFIG_FILES_KEY)
end

return ConfigRepository
