local ProtocolHelper = require "protocol.protocol_helper"
local HeadCodec = require "protocol.head_codec"
local Logger = require "common.logger"
local Pids = require "protocol.pids"
local pb = require "pb"
local PlayerManager = require "world.player.player_manager"
local PlayerLoader = require "world.player.player_loader"
local skynet = require "skynet"

local Handler = {}

local CMD = {}

function CMD.start()
    ProtocolHelper.RegisterProtocol()
    return true
end


function CMD.player_socket_accept(fd, addr)
    Logger.Info("[World]accept New client from:%s fd:%s",addr, tostring(fd))
    return skynet.self()
end

function CMD.player_socket_ready(fd, addr)
    Logger.Info("[World]socket ready from:%s fd:%s",addr, tostring(fd))
    local player = PlayerManager.GetInstance():GetPlayerByFd(fd)
    if player then
        Logger.Error("[World]accept New client from:%s fd:%s",addr, tostring(fd))
        return
    end
    player = PlayerLoader.LoadPlayer(fd, addr)
    PlayerManager.GetInstance():AddPlayer(player.uid, player)
    local data = player:OnBorn()
    ApplySceneChange(player, data, player.sceneId, false)
end

local function LeaveScene(fd, callback)
    local player = PlayerManager:GetInstance():GetPlayerByFd(fd)
    if player then
        local ok, unit, others = skynet.call(".scene", "lua", "leave", player.uid)
        if ok then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {
                uid = player.uid,
            })
            for _, u in ipairs(others or {}) do
                PlayerManager:GetInstance():SendUidPacket(u.uid, packet)
            end
        end
    end
    if callback then
        callback()
    end
end

function CMD.player_socket_close(fd)
    LeaveScene(fd, function()
        PlayerManager.GetInstance():PlayerSocketClose(fd)
    end)
    Logger.Info("[World]Socket close fd:%s", tostring(fd))
end

function CMD.player_socket_error(fd)
    LeaveScene(fd, function()
        PlayerManager.GetInstance():PlayerSocketError(fd)
    end)
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
    local ok, msg = pcall(pb.decode, protoName, body)
    if not ok then
        return Logger.Error("[World]ClientDispatch: failed to decode message fd:%s, protoId:%s", tostring(fd), tostring(id))
    end
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