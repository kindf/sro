local ProtocolHelper = require "protocol.protocol_helper"
local HeadCodec = require "protocol.head_codec"
local Logger = require "common.logger"
local Pids = require "protocol.pids"
local pb = require "pb"
local PlayerManager = require "world.player.player_manager"
local PlayerLoader = require "world.player.player_loader"

local Handler = {}

local CMD = {}

function CMD.start()
    ProtocolHelper.RegisterProtocol()
    return true
end

function CMD.accept_client(fd, addr)
    Logger.Info("[World]accept New client from:%s fd:%s",addr, tostring(fd))
    local player = PlayerManager.GetInstance():GetPlayerByFd(fd)
    if not player then
        player = PlayerLoader.LoadPlayer(fd, addr)
        PlayerManager.GetInstance():AddPlayer(player.uid, player)
    end
end

function CMD.player_socket_close(fd)
    PlayerManager.GetInstance():PlayerSocketClose(fd)
    Logger.Info("[World]Socket close fd:%s", tostring(fd))
end

function CMD.player_socket_error(fd)
    PlayerManager.GetInstance():PlayerSocketError(fd)
    Logger.Info( "[World]Socket error fd:%s", tostring(fd))
end
-- 分发
function Handler.ClientDispatch(fd, id, flag, tag, body, ...)
    local protoName = Pids[id]
    local player = PlayerManager.GetInstance():GetPlayerByFd(fd)
    if not player then
        Logger.Error("[World]ClientDispatch: Player not found for fd:%s, protoId:%s", tostring(fd), tostring(id))
        return
    end
    if not protoName then
        return Logger.Error("[World]ClientDispatch: unknown protoId:%s fd:%s", tostring(id), tostring(fd))
    end
    local msg = pb.decode(protoName, body)
    local handler = ProtocolHelper.GetProtocolHandler(id)
    if not handler then
        return Logger.Error("协议处理函数不存在 protoId:%s", id)
    end
    if handler.type == "protocol" then
        local ret, err = pcall(handler.handler, player, msg)
        if not ret then
            Logger.Error("协议处理函数调用失败 fd:%s uid:%s protoId:%s, err:%s", tostring(player.fd), tostring(player.uid), tostring(id), tostring(err))
            return
        end
    elseif handler.type == "rpc" then
        local resp = {}
        local ret, err = pcall(handler.handler, player, msg, resp)
        if not ret then
            Logger.Error("协议处理函数调用失败 fd:%s uid:%s protoId:%s, err:%s", tostring(player.fd), tostring(player.uid), tostring(id), tostring(err))
            return
        end
        local packet = ProtocolHelper.Encode(handler.respName, resp, 1, tag)
        player:SendPackage(packet)
    else
        return Logger.Error("协议处理函数类型错误 protoId:%s, type:%s", id, handler.type)
    end
end

-- 解包
function Handler.ClientUnpack(msg, sz)
    local id, flag, tag, body = HeadCodec.Decode(msg, sz)
    if not id then
        return nil, "invalid head"
    end
    return id, flag, tag, body
end

Handler.CMD = CMD

return Handler