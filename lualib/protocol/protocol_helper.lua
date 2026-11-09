local lfs = require "lfs"
local Pb = require "pb"
local Pids = require "protocol.pids"
local HeadCodec = require "protocol.head_codec"
local Logger = require "common.logger"
local ProtocolHelper = {}
local sformat = string.format

local protocolHandler = {}
function ProtocolHelper.RegisterProtocolHandler(protoId, handler)
    assert(not protocolHandler[protoId], "协议处理函数重复注册 pid:"..protoId)
    protocolHandler[protoId] = {
        handler = handler,
        type = "protocol",
    }
end

function ProtocolHelper.RegisterRpcHandler(reqName, respName, handler)
    local protoId = assert(Pids[reqName], sformat("不存在的消息 reqName:%s", reqName))
    local respProtoId = assert(Pids[respName], sformat("不存在的消息 respName:%s", respName))
    assert(not protocolHandler[protoId], "协议处理函数重复注册 pid:"..protoId)
    protocolHandler[protoId] = {
        handler = handler,
        type = "rpc",
        respProtoId = respProtoId,
    }
end

function ProtocolHelper.GetProtocolHandler(protoId)
    return protocolHandler[protoId]
end

function ProtocolHelper.RegisterProtocol()
    local root_path = lfs.currentdir()
    local pb_path = root_path.."/protocol/pb/"
    local protos = require "protocol.protos"
    for _, name in ipairs(protos) do
        Pb.loadfile(pb_path..name..".pb")
    end
end

function ProtocolHelper.UnpackHeader(msg, sz)
    local id, flag, tag, body = HeadCodec.Decode(msg, sz)
    return id, body, flag, tag
end

function ProtocolHelper.Encode(respName, resp, flag, tag)
    local ok, body = pcall(Pb.encode, respName, resp)
    assert(ok, sformat("消息编码失败 err:%s", tostring(body)))

    local id = assert(Pids[respName], sformat("不存在的消息 respName:%s", respName))
    local packet, err = HeadCodec.Encode(body, id, flag or 0, tag)
    assert(packet, sformat("消息打包失败 err:%s", tostring(err)))
    return packet
end

return ProtocolHelper
