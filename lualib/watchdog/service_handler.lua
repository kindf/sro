local skynet = require "skynet"
local Handler = {}
local gate

local Socket = {}
local CMD = {}

function Handler.SetGate(gateService)
    gate = gateService
end

function CMD.start(conf)
    skynet.call(gate, "lua", "open" , conf)
    return true
end

function Socket.open(fd, addr)
    LogInfo("Info","[WatchDog]open New client from : %s fd:%s",addr, tostring(fd))
    skynet.call(gate, "lua", "accept", fd)
    local o = {}
    wait_list[fd] = o
    o.fd = fd
    o.addr = addr
    o.time = os.time()
    skynet.timeout(waitTimeout or 300, function()
        local o = wait_list[fd]
        if(o and not o.check)then
            Socket.close_fd(fd)
            LogInfo("Info","fd:%s wait for timeout",fd)
        end
    end)
    --agent[fd] = skynet.newservice("player_agent")
    --skynet.call(agent[fd], "lua", "start", { gate = gate, client = fd, watchdog = skynet.self() })
end

function Socket.close(fd)
    LogInfo("Info", "[WatchDog]Socket close fd:%s", tostring(fd))
    close_agent(fd, GameDefine.PlayerDisconnectFlag.Socket_CLOSE)
end

function Socket.error(fd, msg)
    LogWarning( "[WatchDog]Socket error fd:"..tostring(fd).." msg:"..tostring(msg))
    close_agent(fd, GameDefine.PlayerDisconnectFlag.Socket_ERR)
end

function Socket.warning(fd, size)
    -- size K bytes havn't send out in fd
    LogWarning("[WatchDog]Socket warning fd:%s size:%s", tostring(fd), tostring(size))
end



function Socket.data(fd, msg)
    --print("[WatchDog]data Socket:"..tostring(fd).." data len:"..(msg and #msg or "nil"))
    local o = wait_list[fd]
    if not o then
        return
    end
    --local msgIdx = string.byte(msg, 1) + string.byte(msg, 2)*256
    --local msgBuffer = string.sub(msg, 3)
    --local msgName, pbMsg = Pbmap.GetPBMsg( msgIdx, msgBuffer, sz )
    --for i = 1, #msg do
    --    print("[WatchDog]Socket data msg i:"..i.." byte:"..string.byte(msg, i))
    --end

    local len = #msg

    local msgIdx, msgName, pbMsg, netMsg = Pbmap.UnpackPBMsg( msg )
    
    if not msgName then
        Socket.close_fd(fd, 1)
        LogWarning("[WatchDog]Socket data Socket:"..fd.." data msgIdx:"..tostring(msgIdx).." msg not find")
        return
    end

    -- if msgName == "RetCreateRole" then

    --     trace("[WatchDog]send_package RetCreateRole======================================")

    --     send_package(fd, pbMsg)
    -- end
    local func = MSG["Svr"..msgName]
    if not func then
        return
    end
    local ret, err = skynet.pcall(func, fd, pbMsg, netMsg)
    if ret then
        return
    end
    LogInfo("Info", "[WatchDog]Socket data Socket:%s, call:%s, err:%s", fd, msgName, tostring(err))
end

Handler.Socket = Socket
Handler.CMD = CMD

return Handler