local skynet = require "skynet"
local Handler = require "world.world_service_handler"
local ServiceHelper = require "common.service_helper"
require "skynet.manager" -- import skynet.abort
require "skynet.queue"

package.path = package.path .. ';./lualib/world/?.lua'

local CMD = Handler.CMD
local PlayerQueue = skynet.queue()

ServiceHelper.SetCMD(CMD)

-- reg agent start
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = Handler.ClientUnpack,
	dispatch = function (_, _, msgIdx, msgName, pbMsg, netMsg, rawMsg, ...)
		PlayerQueue(Handler.ClientDispatch, msgIdx, msgName, pbMsg, netMsg, rawMsg, ...)
	end
}

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        PlayerQueue(ServiceHelper.DispatchCmd, cmd, subcmd, ...)
	end)

    skynet.register(".world")
end)
