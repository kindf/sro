local skynet = require "skynet"
local Logger = require "common.logger"
local Handler = {}
local gate

local Socket = {}
local CMD = {}

local tostring = tostring

function Handler.SetGate(gateaddr)
    gate = gateaddr
end

function CMD.start(conf)
    skynet.call(gate, "lua", "open" , conf)
    return true
end

function Socket.open(fd, addr)
    Logger.Info("[WatchDog]open New client from:%s fd:%s",addr, tostring(fd))
    skynet.call(".world", "lua", "accept_client", fd, addr)
    skynet.call(gate, "lua", "accept", fd)
end

function Socket.close(fd)
    skynet.send(".world", "lua", "player_socket_close", fd)
    Logger.Info("[WatchDog]Socket close fd:%s", tostring(fd))
end

function Socket.error(fd, msg)
    skynet.send(".world", "lua", "player_socket_error", fd)
    Logger.Warning( "[WatchDog]Socket error fd:%s, msg:%s", tostring(fd), tostring(msg))
end

function Socket.warning(fd, size)
    Logger.Warning("[WatchDog]Socket warning fd:%s size:%s", tostring(fd), tostring(size))
end

function Socket.data(fd, msg)
    Logger.Info( "[WatchDog]Socket data Socket:%s, call:%s, err:%s", fd, msg)
end

Handler.Socket = Socket
Handler.CMD = CMD

return Handler