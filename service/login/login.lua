local skynet = require "skynet.manager"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local RetCode = require "proto.retcode"
local Pids = require "proto.pids"
local Pb = require "pb"
local LoginTokenMgr = require "login.token_mgr"
local Timer = require "public.timer"

local CMD = {}
local SOCKET = {}

local loginGate
local timer = Timer.New()
local gateConfig

local function IsEmpty(value)
    return not value or value == ""
end

local function GetGateConfig()
    if not gateConfig then
        gateConfig = {
            node = skynet.getenv("default_gate_node") or "gatenode",
            host = skynet.getenv("default_gate_host") or "127.0.0.1",
            port = tonumber(skynet.getenv("default_gate_port")) or 8888,
        }
    end
    return gateConfig
end

local function CloseSocket(fd)
    if not loginGate then
        return
    end
    skynet.call(loginGate, "lua", "kick", fd)
end

local function SendMessage(fd, protoName, resp)
    local pack = ProtocolHelper.Encode(protoName, resp)
    local ok, err = pcall(socket.write, fd, netpack.pack(pack))
    if not ok then
        Logger.Error("Login.SendMessage failed fd=%s err=%s", fd, err)
        CloseSocket(fd)
        return false
    end
    return true
end

function CMD.CheckVersion(msg)
    if msg then
        local ret, req = pcall(Pb.decode, "login.c2s_check_version", msg)
        if not ret then
            Logger.Error("[CMD.CheckVersion] 协议解析失败 err:%s", req)
            return RetCode.PROTO_DECODE_ERROR
        end

        if IsEmpty(req.version) then
            return RetCode.CHECK_VERSION_FAILED
        end
    end
    return RetCode.SUCCESS
end

function CMD.CheckAuth(msg)
    local resp = {
        retCode = RetCode.SUCCESS,
        loginToken = nil,
        account = nil,
    }
    repeat
        local ret, req = pcall(Pb.decode, "login.c2s_login_auth", msg)
        if not ret then
            resp.retCode = RetCode.PROTO_DECODE_ERROR
            Logger.Error("[CMD.CheckAuth] 协议解析失败 err:%s", req)
            break
        end
        -- TODO: sdk token认证
        local token = req.token
        local account = req.account
        if IsEmpty(account) or IsEmpty(token) then
            resp.retCode = RetCode.INVALID_TOKEN
            break
        end

        local gate = GetGateConfig()
        local tokenInfo = LoginTokenMgr:Issue(account, gate.node, gate.host, gate.port)
        resp.loginToken = tokenInfo.token
        resp.account = account
        resp.gateHost = tokenInfo.gateHost
        resp.gatePort = tokenInfo.gatePort
        resp.expireTime = tokenInfo.expireTime
    until true
    return resp
end

function CMD.ConsumeLoginToken(account, token, gateNode)
    if IsEmpty(account) or IsEmpty(token) then
        return RetCode.INVALID_TOKEN
    end

    local ret, tokenInfo = LoginTokenMgr:Consume(account, token, gateNode)
    if not ret then
        Logger.Warning("ConsumeLoginToken failed account=%s gateNode=%s", account or "nil", gateNode or "nil")
        return RetCode.INVALID_TOKEN
    end
    return RetCode.SUCCESS, tokenInfo.account
end

function SOCKET.open(fd, ip)
    skynet.call(loginGate, "lua", "accept", fd)
    Logger.Info("Login socket open fd=%d ip=%s", fd, ip)
end

function SOCKET.close(fd)
    Logger.Info("Login socket close fd=%d", fd)
end

function SOCKET.error(fd, err)
    Logger.Warning("Login socket error fd=%d err=%s", fd, err)
    CloseSocket(fd)
end

function SOCKET.warning(fd, size)
    Logger.Warning("Login socket warning fd=%d size=%d", fd, size)
end

function SOCKET.data(fd, msg)
    local ok, protoId, protoMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, msg)
    if not ok then
        Logger.Error("Login socket unpack failed fd=%s err=%s", fd, protoId)
        CloseSocket(fd)
        return
    end

    local protoName = Pids[protoId]
    if protoName == "login.c2s_check_version" then
        SendMessage(fd, "login.s2c_check_version", { retCode = CMD.CheckVersion(protoMsg) })
    elseif protoName == "login.c2s_login_auth" then
        SendMessage(fd, "login.s2c_login_auth", CMD.CheckAuth(protoMsg))
    else
        Logger.Warning("Login socket invalid proto fd=%s protoId=%s", fd, protoId)
        CloseSocket(fd)
    end
end

local function InitLoginSocket()
    loginGate = skynet.newservice("gate")
    local loginHost = skynet.getenv("login_host") or "0.0.0.0"
    local loginPort = tonumber(skynet.getenv("login_port")) or 9999
    skynet.send(loginGate, "lua", "open", {
        host = loginHost,
        port = loginPort,
    })
    Logger.Info("Login socket listen on %s:%d", loginHost, loginPort)
end

function CMD.start()
    math.randomseed(os.time())
    ProtocolHelper.RegisterProtocol()
    GetGateConfig()
    InitLoginSocket()
    timer:Interval(60, function() LoginTokenMgr:Cleanup() end, false)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            if f then
                f(...)
            else
                Logger.Error("Login invalid socket cmd:%s", subcmd)
            end
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
    skynet.register(".login")
end)
