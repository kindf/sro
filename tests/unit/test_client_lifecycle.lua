-- 在项目根目录运行：lua tests/unit/test_client_lifecycle.lua
-- 模拟 Skynet 消息所有权和 call 让出期间的断开，不依赖原生模块。
package.path = "./lualib/?.lua;" .. package.path

local sent = {}
local onCall
local copied = 0
local pointer = {}
local payload = string.pack("<I4I1", 123, 0) .. "body"

package.loaded["skynet"] = {
    -- 模拟借用消息的只读复制；不转移或释放所有权。
    tostring = function(buffer, size)
        assert(buffer == pointer and size == #payload)
        copied = copied + 1
        return payload
    end,
    -- 记录单向清理消息。
    send = function(address, protocol, command, fd)
        table.insert(sent, {address = address, command = command, fd = fd})
    end,
    -- 由每个场景控制调用返回值、异常及协程交错。
    call = function(...)
        return onCall(...)
    end,
}
package.preload["skynet.netpack"] = function()
    error("borrowed client messages must never be freed by netpack.tostring")
end

-- 日志不影响状态断言。
local function ignoreLog() end
package.loaded["common.logger"] = {
    Info = ignoreLog, Error = ignoreLog, Warning = ignoreLog,
}

local HeadCodec = require "protocol.head_codec"
local id, flag, tag, body = HeadCodec.Decode(pointer, #payload)
assert(id == 123 and flag == 0 and tag == nil and body == "body")
assert(copied == 1, "client message must be copied without releasing it")
payload = "bad"
assert(HeadCodec.Decode(pointer, #payload) == nil, "short borrowed message rejected")
assert(copied == 2)

local Handler = require "watchdog.watchdog_service_handler"
Handler.SetGate(100)

-- 检查 gate 关闭和 world 清理消息的目标、顺序和 fd。
local function checkCleanup(fd, command)
    assert(#sent == 2, "cleanup must notify gate and world")
    assert(sent[1].address == 100 and sent[1].command == "kick" and sent[1].fd == fd)
    assert(sent[2].address == ".world" and sent[2].command == command and sent[2].fd == fd)
end

-- gate.forward 正常不返回任何值，必须保留玩家直到真正断开。
onCall = function(address, protocol, command, fd, client, world)
    if command == "accept_client" then
        return true, 200
    end
    assert(command == "forward" and address == 100 and client == 0 and world == 200)
end
Handler.Socket.open(1, "test")
assert(#sent == 0, "successful forward must not remove player")
Handler.Socket.close(1)
checkCleanup(1, "player_socket_close")
sent = {}
Handler.Socket.close(1)
checkCleanup(1, "player_socket_close")

-- accept_client 让出期间断开，恢复后不再 forward。
sent = {}
onCall = function(address, protocol, command, fd)
    assert(command == "accept_client", "closed connection must not be forwarded")
    Handler.Socket.close(fd)
    return true, 200
end
Handler.Socket.open(2, "test")
checkCleanup(2, "player_socket_close")

-- gate 在 forward 期间断开并抛错，异常不能逃出 socket 回调。
sent = {}
onCall = function(address, protocol, command)
    if command == "accept_client" then
        return true, 200
    end
    error("connection already closed")
end
assert(pcall(Handler.Socket.open, 3, "test"))
checkCleanup(3, "player_socket_close")

-- world 业务失败和服务调用异常都必须释放尚未启用的连接。
for _, throws in ipairs({false, true}) do
    sent = {}
    onCall = function()
        if throws then
            error("world unavailable")
        end
        return false, "accept failed"
    end
    assert(pcall(Handler.Socket.open, 4, "test"))
    checkCleanup(4, "player_socket_close")
end

-- error 后再收到 close，两个清理路径均能安全调用。
sent = {}
Handler.Socket.error(5, "reset")
checkCleanup(5, "player_socket_error")
sent = {}
Handler.Socket.close(5)
checkCleanup(5, "player_socket_close")
print("OK client_lifecycle")
