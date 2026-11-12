local skynet = require "skynet"
local Handler = require "world.world_service_handler"
local ServiceHelper = require "common.service_helper"
require "skynet.manager" -- import skynet.abort
require "skynet.queue"
require "world.client_handler"

package.path = package.path .. ';./lualib/world/?.lua'

local CMD = Handler.CMD
local PlayerQueue = skynet.queue()

ServiceHelper.SetCMD(CMD)

-- reg agent start
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = Handler.ClientUnpack,
	dispatch = function (fd, _, protoId, msgName, pbMsg, netMsg, rawMsg, ...)
		-- client 协议是单向的，session 实际是 gate 传下来的 fd，
		-- 不调用 ignoreret 会被 skynet 当成“忘记回包”。
		skynet.ignoreret()
		PlayerQueue(Handler.ClientDispatch, fd, protoId, msgName, pbMsg, netMsg, rawMsg, ...)
	end
}

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        PlayerQueue(ServiceHelper.DispatchCmd, cmd, subcmd, ...)
	end)

    skynet.register(".world")
end)
