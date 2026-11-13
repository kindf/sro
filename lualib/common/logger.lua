local skynet = require "skynet"
local Logger = {}
local sformat = string.format

local DEBUG_COLOR = "\27[94m"
local INFO_COLOR = "\27[32m"
local WARNING_COLOR = "\27[33m"
local ERROR_COLOR = "\27[31m"

local function ColorOutput(colorStr, dateStr, str)
    skynet.error(colorStr,dateStr,str,"\27[0m")
end

function Logger.Debug(...)
    ColorOutput(DEBUG_COLOR, os.date("%Y-%m-%d %H:%M:%S"), sformat(...))
end

function Logger.Info(...)
    ColorOutput(INFO_COLOR, os.date("%Y-%m-%d %H:%M:%S"), sformat(...))
end

function Logger.Warning(...)
    ColorOutput(WARNING_COLOR, os.date("%Y-%m-%d %H:%M:%S"), sformat(...))
end

function Logger.Error(...)
    ColorOutput(ERROR_COLOR, os.date("%Y-%m-%d %H:%M:%S"), sformat(...))
    ColorOutput(ERROR_COLOR, os.date("%Y-%m-%d %H:%M:%S"), debug.traceback())
end

return Logger
