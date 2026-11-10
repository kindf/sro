local skynet = require "skynet"
local Handler = require "scene.scene_service_handler"
local ServiceHelper = require "common.service_helper"
require "skynet.queue"
require "skynet.manager" -- import skynet.abort

GlobalQueue = skynet.queue()
local GlobalQueue = GlobalQueue

package.path = package.path .. ';./lualib/scene/?.lua'

local CMD = Handler.CMD
ServiceHelper.SetCMD(CMD)

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        GlobalQueue(ServiceHelper.DispatchCmd, cmd, subcmd, ...)
	end)

    skynet.register(".scene")
end)
