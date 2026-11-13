local Logger = require "common.logger"
local skynet = require "skynet"
local socket = require "skynet.socket"
local ProtocolHelper = require "protocol.protocol_helper"
local HeadCodec = require "protocol.head_codec"
local Pb = require "pb"
local Pids = require "protocol.pids"
local TableUtil = require "common.table_util"

local CMD = {}
local account
local loginFd
local gatePort = skynet.getenv("gateport")

-- 服务端发包格式（HeadCodec.Encode 已经带上了 2B 长度）：
--   [2B BE len][4B LE id][1B flag][4B LE tag?][body]
-- socket.read 先读 2B 长度，再读 len 字节 payload，payload 交给 HeadCodec.Decode。
local function ReceiveMessage(fd)
    local lenBuf = socket.read(fd, 2)
    if not lenBuf then
        return nil, "read length failed"
    end

    local len = string.unpack(">H", lenBuf, 1)
    if len < 5 then
        return nil, "packet too short:" .. len
    end

    local payload = socket.read(fd, len)
    if not payload then
        return nil, "read payload failed"
    end

    local id, flag, tag, body = HeadCodec.Decode(payload)
    if not id then
        return nil, tostring(flag)
    end

    local protoName = Pids[id]
    if not protoName then
        return nil, "unknown proto id:" .. id
    end

    local ok, msg = pcall(Pb.decode, protoName, body)
    if not ok then
        return nil, msg
    end

    return msg, id, flag, tag
end

local function PackMsg(pbName, msgBody, flag, tag)
    local id = assert(Pids[pbName], "unknown message:" .. tostring(pbName))

    local ok, body = pcall(Pb.encode, pbName, msgBody)
    if not ok then
        return nil, body
    end

    return HeadCodec.Encode(body, id, flag or 0, tag)
end

local function C2S(fd, protoName, data, callback)
    Logger.Debug("[C2S] send %s data:%s", protoName, TableUtil.dump(data))

    local packet, err = PackMsg(protoName, data, 0)
    if not packet then
        return Logger.Error("[C2S] pack failed proto:%s err:%s", protoName, tostring(err))
    end
    socket.write(fd, packet)

    local resp, id, flag, tag = ReceiveMessage(fd)
    if not resp then
        return Logger.Error("[C2S] recv failed proto:%s err:%s", protoName, tostring(id))
    end

    Logger.Debug("[C2S] recv id:%s flag:%s tag:%s resp:%s", tostring(id), tostring(flag), tostring(tag), TableUtil.dump(resp))
    if callback then
        callback(resp)
    end
end

local function SendPacket(fd, protoName, data)
    Logger.Debug("[C2S] send %s data:%s", protoName, TableUtil.dump(data))

    local packet, err = PackMsg(protoName, data, 0)
    if not packet then
        return Logger.Error("[C2S] pack failed proto:%s err:%s", protoName, tostring(err))
    end
    socket.write(fd, packet)
end

local function DoSomething()
    loginFd = assert(socket.open("127.0.0.1", gatePort))

    -- 等 gate 把这条 fd forward 给 world，避免连接后立刻发包被丢
    skynet.sleep(10)

    -- Scene.ReqMove 是 proto2 required，五个字段都要给
    -- C2S(loginFd, "Scene.ReqMove", {
    --     common = 90,
    --     time = 0.1,
    --     dx = 10,
    --     dy = 0,
    --     dz = 20,
    -- }, function(resp)
    --     Logger.Info("收到移动响应 %s", TableUtil.dump(resp))
    -- end)

    SendPacket(loginFd, "Scene.ReqMove", {
        common = 90,
        time = 0.1,
        dx = 10,
        dy = 0,
        dz = 20,
    })
end

local function Tick()
    local resp, id, flag, tag = ReceiveMessage(loginFd)
    if not resp then
        return Logger.Error("[C2S] recv failed")
    end

    Logger.Debug("Receive Server recv id:%s flag:%s tag:%s resp:%s", Pids[tonumber(id)], tostring(flag), tostring(tag), TableUtil.dump(resp))
end

local function Start(acc)
    account = acc
    ProtocolHelper.RegisterProtocol()
    DoSomething()

    skynet.fork(function()
        while true do
            Tick()
            skynet.sleep(100)
        end
    end)
end

skynet.start(function()
    Logger.Info("botclient start")
    skynet.fork(function()
        Start("test1")
    end)
end)
