local skynet = require "skynet"
local Handler = require "watchdog.watchdog_service_handler"
require "skynet.manager" -- import skynet.abort

package.path = package.path .. ';./lualib/watchdog/?.lua'

local gate

local SOCKET = Handler.Socket
local CMD = Handler.CMD

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

    skynet.register(".watchdog")
	gate = skynet.newservice("gate")
    Handler.SetGate(gate)
end)
