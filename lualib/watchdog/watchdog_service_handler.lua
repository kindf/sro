local skynet = require "skynet"
local socketdriver = require "skynet.socketdriver"
local Logger = require "common.logger"
local Handler = {}
local gate
local connections = {}

local Socket = {}
local CMD = {}

local tostring = tostring

-- 清理连接状态并通知 gate 完成底层关闭；重复通知由 gate/world 幂等处理。
-- 使用单向消息，不在清理过程中让出协程。
local function closeClient(fd, command)
    connections[fd] = nil
    -- 玩家会话已经结束，丢弃积压的广播；kick 同时移除 gate 对 fd 的登记。
    socketdriver.shutdown(fd)
    skynet.send(gate, "lua", "kick", fd)
    skynet.send(".world", "lua", command, fd)
end

-- 保存本 watchdog 管理的 gate 服务地址。
function Handler.SetGate(gateaddr)
    gate = gateaddr
end

-- 打开监听端口；等待 gate 完成初始化。
function CMD.start(conf)
    skynet.call(gate, "lua", "open" , conf)
    return true
end

-- world 串行完成转发和玩家入场。等待期间若已断开，清理消息已交给 world。
function Socket.open(fd, addr)
    local connection = {}
    connections[fd] = connection
    Logger.Info("[WatchDog]open New client from:%s fd:%s",addr, tostring(fd))
    local delivered, handled, accepted = pcall(skynet.call, ".world", "lua", "player_socket_accept", fd, addr, gate)
    if connections[fd] ~= connection then
        return
    end
    if not delivered or not handled or not accepted then
        closeClient(fd, "player_socket_close")
        Logger.Warning("[WatchDog]world accept failed fd:%s err:%s", tostring(fd), tostring(accepted or handled))
    end
end

-- 对端关闭后清理玩家，并释放 gate 中处于半关闭状态的 socket。
function Socket.close(fd)
    closeClient(fd, "player_socket_close")
    Logger.Info("[WatchDog]Socket close fd:%s", tostring(fd))
end

-- 网络异常时清理连接和玩家；允许随后再次收到 close 通知。
function Socket.error(fd, msg)
    closeClient(fd, "player_socket_error")
    Logger.Warning( "[WatchDog]Socket error fd:%s, msg:%s", tostring(fd), tostring(msg))
end

-- 记录发送缓冲区积压告警。
function Socket.warning(fd, size)
    Logger.Warning("[WatchDog]Socket warning fd:%s size:%s", tostring(fd), tostring(size))
end

-- 记录尚未转发到 world 的数据。
function Socket.data(fd, msg)
    Logger.Info( "[WatchDog]Socket data Socket:%s, msg:%s", fd, msg)
end

Handler.Socket = Socket
Handler.CMD = CMD

return Handler
