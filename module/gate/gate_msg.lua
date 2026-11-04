local skynet = require "skynet"
local GateMgr = require "gate.gate_mgr"
local CMD = {}

function CMD.start()
    GateMgr:Init("0.0.0.0", skynet.getenv("gate_port"))
end

CMD.VerifySession = function(...) return GateMgr.VerifySession(...) end
CMD.SetConnectionGaming = function(...) return GateMgr:SetConnectionGaming(...) end
CMD.SendClientMessage = function(...) return GateMgr:SendMessage(...) end
CMD.KickPlayer = function(...) return GateMgr:CloseFd(...) end
CMD.EnterGame = GateMgr.EnterGame

return CMD
