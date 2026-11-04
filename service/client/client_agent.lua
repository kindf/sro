local skynet = require "skynet"
local socket = require "skynet.socket"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local Pb = require "pb"
local Pids = require "proto.pids"
local netpack = require "skynet.netpack"
local TableUtil = require "util.table_util"
local RetCode = require "proto.retcode"
local spack = string.pack

local CMD = {}
local account
local loginFd
local gateFd

local function ReceiveMessage(fd)
    local dataLen = socket.read(fd, 2)
    if not dataLen then
        return Logger.Error("[ReceiveMessage] 消息接收失败")
    end
    local len = string.unpack(">H", dataLen, 1)
    local data = socket.read(fd, len)
    if not data then
        return Logger.Error("[ReceiveMessage] 消息接收失败")
    end
    local ok, err, buffMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, data)
    if not ok then
        return Logger.Error("[HandleServerMessage] 协议头解析失败 err:%s", err)
    end
    local protoName = Pids[err]
    local msg = Pb.decode(protoName, buffMsg)
    return msg
end

local function PackMsg(pbName, msgBody)
    local pid = Pids[pbName]
    local ret, msg = pcall(Pb.encode, pbName, msgBody)
    if not ret then
        return Logger.Error("消息编码失败 err:%s", msg)
    end
    local msg_len = #msg
    local pack = spack(">H c" .. msg_len, pid, msg)
    return pack
end

local function C2S(fd, protoName, data, callback)
    Logger.Debug("[C2S] 发包 protocol %s send data:%s", protoName, TableUtil.dump(data))
    local pack = PackMsg(protoName, data)
    socket.write(fd, netpack.pack(pack))
    local resp = ReceiveMessage(fd)
    if callback then
        callback(resp)
    end
    Logger.Debug("[C2S] 收包 protocol callback %s resp:%s", protoName, TableUtil.dump(resp))
end

local loginToken
local uid
local sessionId
local function DoSomething()
    local loginPort = skynet.getenv("login_port")
    loginFd = assert(socket.open("127.0.0.1", loginPort))

    -- 检查版本
    C2S(loginFd, "login.c2s_check_version", { version = "ac01c22155e4a7264482d8ddc71343b5" }, function(_) end)

    -- 登录认证
    local loginResp
    C2S(loginFd, "login.c2s_login_auth", { account = "test1", token = "token" }, function(resp) loginResp = resp end)
    socket.close(loginFd)

    if not loginResp or loginResp.retCode ~= RetCode.SUCCESS then
        return Logger.Error("登录失败 retCode:%s", loginResp and loginResp.retCode or "nil")
    end

    account = loginResp.account
    loginToken = loginResp.loginToken
    gateFd = assert(socket.open(loginResp.gateHost, loginResp.gatePort))

    -- Gate连接认证
    C2S(gateFd, "gate.c2s_gate_auth", { account = account, loginToken = loginToken }, function(resp)
        sessionId = resp.sessionId
    end)

    if not sessionId then
        return Logger.Error("Gate认证失败")
    end

    local function QueryCallBack(resp)
        uid = resp.uid
    end
    C2S(gateFd, "player_base.c2s_query_uid", { account = account }, QueryCallBack)

    if not uid then
        -- 创建角色
        C2S(gateFd, "player_base.c2s_create_role", { name = "test1" }, function(_) end)
    end
    -- 登录游戏
    C2S(gateFd, "player_base.c2s_enter_game", {}, function(resp) Logger.Debug("进入游戏 resp:%s", resp.retCode) end)
end

function CMD.start(acc)
    account = acc
    ProtocolHelper.RegisterProtocol()
    DoSomething()
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
end)
