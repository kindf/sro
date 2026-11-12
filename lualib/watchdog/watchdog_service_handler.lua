local skynet = require "skynet"
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

-- 建立玩家后启用转发；两次 call 都可能让出协程，恢复后需检查连接是否已关闭。
function Socket.open(fd, addr)
    local connection = {}
    connections[fd] = connection
    Logger.Info("[WatchDog]open New client from:%s fd:%s",addr, tostring(fd))
    -- 先让 world 建好 player，并拿到 world 地址
    local called, ok, world = pcall(skynet.call, ".world", "lua", "accept_client", fd, addr)
    if connections[fd] ~= connection then
        return
    end
    if not called or not ok or not world then
        closeClient(fd, "player_socket_close")
        if not called then
            world = ok
        end
        return Logger.Error("[WatchDog]world accept_client failed fd:%s err:%s", tostring(fd), tostring(world))
    end
    -- 再把这条 fd 的后续数据转发给 world
    -- 标准 gate.forward 成功时没有返回值，pcall 的状态才表示调用是否成功。
    local fok, ferr = pcall(skynet.call, gate, "lua", "forward", fd, 0, world)
    if not fok then
        -- 连接在 accept 和 forward 之间断开了，回滚 player
        if connections[fd] == connection then
            closeClient(fd, "player_socket_close")
        end
        Logger.Error("[WatchDog]gate forward failed fd:%s err:%s", tostring(fd), tostring(ferr))
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
