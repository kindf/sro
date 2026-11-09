local skynet = require "skynet"
local Logger = require "common.logger"
local HeadCodec = require "protocol.head_codec"
require "skynet.manager"
local ServiceHelper = {}
local CMD = {}
function ServiceHelper.SetCMD(cmd)
    CMD = cmd
end

function ServiceHelper.DispatchCmd(cmd, ...)
    local f = CMD[cmd]
    if not f then
        skynet.ret(skynet.pack(false, string.format("cmd不存在 cmd:%s", cmd)))
        return Logger.Error("invalid cmd. cmd:%s", cmd)
    end
    skynet.ret(skynet.pack(pcall(f, ...)))
end

-- 分发
function ServiceHelper.ClientDispatch(id, flag, tag, body, ...)

end

-- 解包
function ServiceHelper.ClientUnpack(msg, sz)
    local id, flag, tag, body = HeadCodec.Decode(msg, sz)
    if not id then
        return nil, "invalid head"
    end
    return id, flag, tag, body
end

return ServiceHelper